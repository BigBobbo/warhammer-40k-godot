extends SceneTree

# ISS-069 (11e 24.24): "Lone Operative X\"" gates targeting (visibility AND
# [INDIRECT FIRE]) at X" rather than a fixed 12". Verifies range parsing and
# that the REAL RulesEngine.get_eligible_targets honours the custom range.
#
# Usage: godot --headless --path . -s tests/test_iss069_lone_operative_11e.gd

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

func _lo_unit(uid: String, ability_name: String, pos: Vector2) -> Dictionary:
	return {"id": uid, "owner": 2, "status": 2, "flags": {},
		"meta": {"name": uid, "keywords": ["INFANTRY"], "abilities": [{"name": ability_name}], "stats": {}},
		"models": [{"id": "x0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32, "base_type": "circular", "position": {"x": pos.x, "y": pos.y}}]}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss069_lone_operative_11e ===\n")
	var gs = root.get_node_or_null("GameState")
	var rules = root.get_node_or_null("RulesEngine")
	if gs == null or rules == null:
		_check("autoloads", false); _finish(); return
	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11

	print("-- get_lone_operative_range parsing --")
	_check("default 'Lone Operative' -> 12\"",
		rules.get_lone_operative_range({"meta": {"abilities": [{"name": "Lone Operative"}]}}) == 12.0)
	_check("'Lone Operative 9\\\"' -> 9\"",
		rules.get_lone_operative_range({"meta": {"abilities": [{"name": "Lone Operative 9\""}]}}) == 9.0)
	_check("no Lone Operative ability -> 12\" default",
		rules.get_lone_operative_range({"meta": {"abilities": [{"name": "Stealth"}]}}) == 12.0)

	print("\n-- custom range gates real targeting (get_eligible_targets) --")
	# Actor at (500,500) with a long-range weapon, no terrain. Two LO targets
	# at the SAME ~11.2" edge distance (centre 500px): the X=9 unit is out of
	# range (excluded), the default-12 unit is in range (included).
	gs.state["units"] = {
		"U_A": {"id": "U_A", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Shooter", "keywords": ["INFANTRY"],
				"weapons": [{"name": "Long Rifle", "type": "Ranged", "range": "48", "attacks": "2",
					"ballistic_skill": "3", "strength": "4", "ap": "0", "damage": "1", "special_rules": ""}], "stats": {}},
			"models": [{"id": "a0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32, "base_type": "circular", "position": {"x": 500, "y": 500}}]},
		"U_LO9": _lo_unit("U_LO9", "Lone Operative 9\"", Vector2(1000, 500)),
		"U_LO12": _lo_unit("U_LO12", "Lone Operative", Vector2(500, 1000)),
	}
	gs.state["meta"]["active_player"] = 1
	if gs.state.has("terrain_features"):
		gs.state["terrain_features"] = []
	var tm = root.get_node_or_null("TerrainManager")
	if tm != null:
		tm.terrain_features = []

	var elig = rules.get_eligible_targets("U_A", gs.state)
	var keys = elig.keys() if elig is Dictionary else elig
	_check("Lone Operative 9\" unit at ~11\" is EXCLUDED (>9\")", not ("U_LO9" in keys), str(keys))
	_check("default Lone Operative (12\") unit at ~11\" is INCLUDED (<12\")", "U_LO12" in keys, str(keys))

	gs.state = prev_state
	GameConstants.edition = prev_edition
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
