extends SceneTree

# ISS-053 (step 1): 11e benefit-of-cover qualification (13.08, in-area
# half + Stealth) and Plunging Fire (22.05). Both edition-gated; the BS
# application lands with the ISS-041 resolution flow + ModifierStack.
#
# Usage: godot --headless --path . -s tests/test_iss053_cover_plunging_11e.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _rect(cx: float, cy: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(cx - w / 2, cy - h / 2), Vector2(cx + w / 2, cy - h / 2),
		Vector2(cx + w / 2, cy + h / 2), Vector2(cx - w / 2, cy + h / 2)])

func _unit(positions: Array, keywords: Array, abilities: Array = []) -> Dictionary:
	var models = []
	for i in range(positions.size()):
		models.append({"id": "m%d" % i, "alive": true, "base_mm": 32, "base_type": "circular",
			"position": {"x": positions[i].x, "y": positions[i].y}})
	return {"meta": {"keywords": keywords, "abilities": abilities}, "flags": {}, "models": models}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss053_cover_plunging_11e ===\n")
	var tm = root.get_node_or_null("TerrainManager")
	var prev = tm.terrain_features.duplicate(true)
	tm.terrain_features = [
		{"id": "ruin", "type": "ruins", "polygon": _rect(400, 400, 240, 240), "height_category": "tall"},
	]
	GameConstants.edition = 11

	print("-- 13.08 cover qualification (in-area half) --")
	_check("ALL models in the area: cover",
		tm.unit_has_cover_11e(_unit([Vector2(380, 380), Vector2(420, 420)], ["INFANTRY"])))
	_check("one model outside: NO cover (every model must qualify)",
		not tm.unit_has_cover_11e(_unit([Vector2(400, 400), Vector2(800, 800)], ["INFANTRY"])))
	_check("VEHICLE in area: no in-area cover (keyword gate)",
		not tm.unit_has_cover_11e(_unit([Vector2(400, 400)], ["VEHICLE"])))
	_check("Stealth grants cover anywhere (24.33)",
		tm.unit_has_cover_11e(_unit([Vector2(800, 800)], ["INFANTRY"], [{"name": "Stealth"}])))
	GameConstants.edition = 10
	_check("edition 10: primitive inert",
		not tm.unit_has_cover_11e(_unit([Vector2(400, 400)], ["INFANTRY"])))
	GameConstants.edition = 11

	print("\n-- 22.05 plunging fire --")
	var ground_target = _unit([Vector2(800, 400)], ["INFANTRY"])
	var elevated_attacker = {"id": "a0", "alive": true, "base_mm": 32, "base_type": "circular",
		"position": {"x": 400, "y": 400}, "elevation_inches": 3.0}
	var ground_attacker = {"id": "a1", "alive": true, "base_mm": 32, "base_type": "circular",
		"position": {"x": 400, "y": 400}, "elevation_inches": 0.0}
	var plain_unit = _unit([Vector2(400, 400)], ["INFANTRY"])
	var towering_unit = _unit([Vector2(400, 400)], ["MONSTER", "TOWERING"])
	_check("attacker on >=3\" elevation vs ground target: applies",
		tm.plunging_fire_applies(elevated_attacker, plain_unit, ground_target))
	_check("ground-level attacker without TOWERING: does not apply",
		not tm.plunging_fire_applies(ground_attacker, plain_unit, ground_target))
	var close_target = _unit([Vector2(400 + 10 * 40, 400)], ["INFANTRY"])  # 10\" away
	var far_target = _unit([Vector2(400 + 14 * 40, 400)], ["INFANTRY"])   # 14\" away
	_check("TOWERING within 12\": applies",
		tm.plunging_fire_applies(ground_attacker, towering_unit, close_target))
	_check("TOWERING beyond 12\": does not apply",
		not tm.plunging_fire_applies(ground_attacker, towering_unit, far_target))
	var airborne_target = _unit([Vector2(800, 400)], ["INFANTRY"])
	airborne_target.models[0]["elevation_inches"] = 4.0
	_check("no ground-level models in target: does not apply",
		not tm.plunging_fire_applies(elevated_attacker, plain_unit, airborne_target))

	GameConstants.edition = 10
	tm.terrain_features = prev
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
