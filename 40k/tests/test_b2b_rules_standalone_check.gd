extends SceneTree

# Standalone port of tests/unit/test_base_contact_enforcement.gd (the GUT
# runner hangs in this container). Exercises the SAME cases against
# RulesEngine.validate_base_to_base_possible_rules after the 11.04
# candidate-consistency fixes (band tolerance + wall/terrain awareness).
#
# Usage: godot --headless --path . -s tests/test_b2b_rules_standalone_check.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s %s" % [label, ("(" + detail + ")") if detail != "" else ""])

func _init():
	create_timer(0.2).timeout.connect(_run)

func _make_model(id: String, pos_x: float, pos_y: float, alive: bool = true) -> Dictionary:
	return {"id": id, "alive": alive, "current_wounds": 1, "wounds": 1,
		"base_mm": 32, "base_type": "circular", "position": {"x": pos_x, "y": pos_y}}

func _make_unit(owner: int, models: Array) -> Dictionary:
	return {"owner": owner, "models": models, "meta": {"name": "Test Unit (owner %d)" % owner, "keywords": ["INFANTRY"]}}

func _run():
	print("\n=== b2b rules standalone check ===")
	var RE = load("res://autoloads/RulesEngine.gd")
	root.get_node("TerrainManager").terrain_features.clear()

	# 1. model in b2b — valid
	var r = RE.validate_base_to_base_possible_rules("charger_unit",
		{"marine_1": [[0, 0], [120.0, 0]]}, ["target_unit"],
		{"units": {"charger_unit": _make_unit(0, [_make_model("marine_1", 0, 0)]),
			"target_unit": _make_unit(1, [_make_model("ork_1", 170.4, 0)])}}, 7)
	_check("model in b2b is valid", r.valid, str(r.errors))

	# 2. model could close within 1" but stopped 1.5" out — invalid
	r = RE.validate_base_to_base_possible_rules("charger_unit",
		{"marine_1": [[0, 0], [60.0, 0]]}, ["target_unit"],
		{"units": {"charger_unit": _make_unit(0, [_make_model("marine_1", 0, 0)]),
			"target_unit": _make_unit(1, [_make_model("ork_1", 170.4, 0)])}}, 7)
	_check("model that could close but didn't is flagged", not r.valid, str(r.errors))
	_check("error mentions within 1", r.errors.size() > 0 and "within 1" in str(r.errors[0]), str(r.errors))

	# 3. per-model: one based up, second stops 2.5" short — invalid, names marine_b
	var board3 = {"units": {
		"charger_unit": _make_unit(0, [_make_model("marine_a", 0, 0), _make_model("marine_b", 0, 80)]),
		"target_unit": _make_unit(1, [_make_model("ork_1", 300, 0), _make_model("ork_2", 300, 80)])}}
	r = RE.validate_base_to_base_possible_rules("charger_unit",
		{"marine_a": [[0, 0], [300 - 50.4, 0]], "marine_b": [[0, 80], [150, 80]]},
		["target_unit"], board3, 10)
	_check("second model that could close is flagged", not r.valid, str(r.errors))
	_check("flag names marine_b", "marine_b" in str(r.errors), str(r.errors))

	# 4. per-model: both based up — valid
	r = RE.validate_base_to_base_possible_rules("charger_unit",
		{"marine_a": [[0, 0], [300 - 50.4, 0]], "marine_b": [[0, 80], [300 - 50.4, 80]]},
		["target_unit"], board3, 10)
	_check("both models in contact valid", r.valid, str(r.errors))

	# 5. b2b unreachable (12.5" away, roll 12) — ends 0.9" out, valid
	r = RE.validate_base_to_base_possible_rules("charger_unit",
		{"marine_1": [[0, 0], [550.4 - 86.4, 0]]}, ["target_unit"],
		{"units": {"charger_unit": _make_unit(0, [_make_model("marine_1", 0, 0)]),
			"target_unit": _make_unit(1, [_make_model("ork_1", 550.4, 0)])}}, 12)
	_check("unreachable b2b: ER stop is valid", r.valid, str(r.errors))

	# 6. mixed reachability — near model bases, far model advances — valid
	r = RE.validate_base_to_base_possible_rules("charger_unit",
		{"marine_1": [[0, 0], [120.0, 0]], "marine_2": [[-340, 0], [-60, 0]]},
		["target_unit"],
		{"units": {"charger_unit": _make_unit(0, [_make_model("marine_1", 0, 0), _make_model("marine_2", -340, 0)]),
			"target_unit": _make_unit(1, [_make_model("ork_1", 170.4, 0)])}}, 7)
	_check("mixed reachability valid", r.valid, str(r.errors))

	# 7. dead target models ignored
	r = RE.validate_base_to_base_possible_rules("charger_unit",
		{"marine_1": [[0, 0], [550.4 - 86.4, 0]]}, ["target_unit"],
		{"units": {"charger_unit": _make_unit(0, [_make_model("marine_1", 0, 0)]),
			"target_unit": _make_unit(1, [_make_model("ork_dead", 60, 0, false), _make_model("ork_1", 550.4, 0)])}}, 12)
	_check("dead targets ignored", r.valid, str(r.errors))

	# 8. empty paths — valid
	r = RE.validate_base_to_base_possible_rules("charger_unit", {}, ["target_unit"],
		{"units": {"charger_unit": _make_unit(0, [_make_model("marine_1", 0, 0)]),
			"target_unit": _make_unit(1, [_make_model("ork_1", 100, 0)])}}, 7)
	_check("empty paths valid", r.valid, str(r.errors))

	# 9. within 0.2" tolerance counts as based
	r = RE.validate_base_to_base_possible_rules("charger_unit",
		{"marine_1": [[0, 0], [170.4 - 58.4, 0]]}, ["target_unit"],
		{"units": {"charger_unit": _make_unit(0, [_make_model("marine_1", 0, 0)]),
			"target_unit": _make_unit(1, [_make_model("ork_1", 170.4, 0)])}}, 7)
	_check("model within tolerance counts as close", r.valid, str(r.errors))

	# 10. NEW: candidate spot on a wall cannot be demanded — a model stopped
	# outside the band is valid when the only band spot overlaps a wall
	var tmgr = root.get_node("TerrainManager")
	tmgr.terrain_features.append({
		"id": "wall_ruin", "type": "ruins",
		"polygon": PackedVector2Array([Vector2(200, -100), Vector2(400, -100), Vector2(400, 100), Vector2(200, 100)]),
		"height_category": "tall",
		"walls": [{"start": Vector2(170, -100), "end": Vector2(170, 100)}],
		"can_move_through": {"INFANTRY": true, "VEHICLE": false, "MONSTER": false},
	})
	# target behind the wall (x=250, edge 4.99" from the charger): with roll 4
	# the only reachable 1"-band centre (x≈159.6) puts the base across the
	# wall at x=170 — the validator may not demand that endpoint (pre-fix it
	# did, and every otherwise-legal move was rejected)
	r = RE.validate_base_to_base_possible_rules("charger_unit",
		{"marine_1": [[0, 0], [100.0, 0]]}, ["target_unit"],
		{"units": {"charger_unit": _make_unit(0, [_make_model("marine_1", 0, 0)]),
			"target_unit": _make_unit(1, [_make_model("ork_1", 250.0, 0)])}}, 4)
	_check("band spot on a wall is not demanded", r.valid, str(r.errors))
	tmgr.terrain_features.clear()

	print("\n=== %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
