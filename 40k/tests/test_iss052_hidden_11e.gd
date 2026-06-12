extends SceneTree

# ISS-052 (step 1): the 11e HIDDEN rule (13.09) — INFANTRY/BEASTS/SWARM in
# a dense-containing terrain area that haven't shot recently are visible
# only within 15" detection range. Edition-gated (no effect at 10e).
#
# Usage: godot --headless --path . -s tests/test_iss052_hidden_11e.gd

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

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss052_hidden_11e ===\n")
	var tm = root.get_node_or_null("TerrainManager")
	var prev = tm.terrain_features.duplicate(true)
	tm.terrain_features = [
		{"id": "ruin", "type": "ruins", "polygon": _rect(400, 400, 200, 200), "height_category": "tall"},
		{"id": "crater", "type": "crater", "polygon": _rect(900, 400, 100, 100), "height_category": "low"},
	]

	var in_ruin = {"id": "m0", "alive": true, "base_mm": 32, "base_type": "circular", "position": {"x": 400, "y": 400}}
	var in_crater = {"id": "m1", "alive": true, "base_mm": 32, "base_type": "circular", "position": {"x": 900, "y": 400}}
	var in_open = {"id": "m2", "alive": true, "base_mm": 32, "base_type": "circular", "position": {"x": 650, "y": 800}}
	var infantry = {"meta": {"keywords": ["INFANTRY"]}, "flags": {}}
	var vehicle = {"meta": {"keywords": ["VEHICLE"]}, "flags": {}}
	var infantry_shot = {"meta": {"keywords": ["INFANTRY"]}, "flags": {"shot_recently": true}}

	GameConstants.edition = 11
	print("-- hidden qualification (13.09) --")
	_check("infantry in a dense area is hidden", tm.is_model_hidden(in_ruin, infantry))
	_check("infantry in an EXPOSED area (crater) is not hidden", not tm.is_model_hidden(in_crater, infantry))
	_check("infantry in the open is not hidden", not tm.is_model_hidden(in_open, infantry))
	_check("VEHICLE in a dense area is not hidden", not tm.is_model_hidden(in_ruin, vehicle))
	_check("infantry that shot recently is not hidden", not tm.is_model_hidden(in_ruin, infantry_shot))

	print("\n-- detection range (15\") --")
	# 14" away (560px) -> within detection; 16" (640px) -> not visible.
	var near_observer = {"id": "o1", "alive": true, "base_mm": 32, "base_type": "circular", "position": {"x": 400 + 14 * 40, "y": 400}}
	var far_observer = {"id": "o2", "alive": true, "base_mm": 32, "base_type": "circular", "position": {"x": 400 + 17 * 40, "y": 400}}
	_check("hidden model visible within 15\" detection",
		tm.hidden_model_visible_to(in_ruin, infantry, near_observer))
	_check("hidden model NOT visible beyond detection range",
		not tm.hidden_model_visible_to(in_ruin, infantry, far_observer))
	_check("non-hidden model visible regardless of range",
		tm.hidden_model_visible_to(in_open, infantry, far_observer))

	print("\n-- edition gate --")
	GameConstants.edition = 10
	_check("no Hidden rule at edition 10", not tm.is_model_hidden(in_ruin, infantry))
	GameConstants.edition = 10

	GameConstants.edition = 11
	print("\n-- step 2: 06.01 visible vs FULLY visible + 13.08 cover half --")
	# A thin dense strip that crosses the CENTER line between observer
	# (200,1000) and target (1200,1000) but not the off-center edge lines.
	tm.terrain_features = [
		{"id": "strip", "type": "ruins", "polygon": _rect(690, 1035, 20, 90), "height_category": "tall"},
	]
	var obs = {"id": "o1", "alive": true, "base_mm": 32, "base_type": "circular",
		"position": {"x": 200, "y": 1000}}
	var tgt = {"id": "t1", "alive": true, "base_mm": 32, "base_type": "circular",
		"position": {"x": 1200, "y": 1000}}
	_check("partial block: still VISIBLE (some lines clear, 06.01)",
		tm.model_visible_11e(obs, tgt))
	_check("partial block: NOT fully visible (a line crosses the strip)",
		not tm.model_fully_visible_11e(obs, tgt))
	tm.terrain_features = []
	_check("open ground: fully visible", tm.model_fully_visible_11e(obs, tgt))
	tm.terrain_features = [
		{"id": "wall", "type": "ruins", "polygon": _rect(600, 1000, 100, 3000), "height_category": "tall"},
	]
	_check("full wall: not visible at all (13.10 every line)",
		not tm.model_visible_11e(obs, tgt))
	var obs_inside = {"id": "o2", "alive": true, "base_mm": 32, "base_type": "circular",
		"position": {"x": 600, "y": 1000}}
	_check("observer INSIDE the area sees out (13.10 exclusion)",
		tm.model_visible_11e(obs_inside, tgt))

	# 13.08's not-fully-visible half: a VEHICLE (no INFANTRY keyword, not
	# within an area) still gets cover when partially blocked.
	tm.terrain_features = [
		{"id": "strip", "type": "ruins", "polygon": _rect(690, 1035, 20, 90), "height_category": "tall"},
	]
	var veh_unit = {"id": "U_V", "owner": 2, "flags": {},
		"meta": {"keywords": ["VEHICLE"], "stats": {}},
		"models": [tgt]}
	_check("cover via not-fully-visible (13.08 second condition, VEHICLE)",
		tm.unit_has_cover_11e(veh_unit, obs))
	tm.terrain_features = []
	_check("fully visible in the open: no cover",
		not tm.unit_has_cover_11e(veh_unit, obs))

	GameConstants.edition = 10
	tm.terrain_features = prev
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
