extends SceneTree

# T-015: Witchseekers Scouts ability is named "Core" in the JSON which means
# GameState._unit_has_scout_own (which begins_with("scout")) never matches and
# Witchseekers never get a scout move. The audit asks for the JSON to use
# "Scouts 6\"". This test pins:
# - The JSON for both adeptus_custodes.json and A_C_test.json names the ability
#   correctly.
# - GameState._unit_has_scout_own returns true for a deployed Witchseekers unit.
# - GameState._get_scout_distance_from_abilities returns 6.0 for that ability.
#
# Usage: godot --headless --path . -s tests/test_t015_witchseekers_scouts.gd

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

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_t015_witchseekers_scouts ===\n")
	_test_json_ability_name()
	_test_scout_check_with_witchseekers_in_state()
	_test_scout_distance_extraction()
	_finish()

func _test_json_ability_name() -> void:
	print("\n-- T-015a: Witchseekers JSON ability is named 'Scouts 6\"' --")
	for path in ["res://tests/fixtures/armies/adeptus_custodes.json", "res://tests/fixtures/armies/A_C_test.json"]:
		var f := FileAccess.open(path, FileAccess.READ)
		_check("%s readable" % path, f != null)
		if f == null:
			continue
		var json = JSON.parse_string(f.get_as_text())
		f.close()
		var unit = json.get("units", {}).get("U_WITCHSEEKERS_C", {})
		var abilities = unit.get("meta", {}).get("abilities", [])
		var has_scout_named = false
		var has_old_core_name = false
		for ability in abilities:
			var ability_name = ability.get("name", "")
			if ability_name == "Scouts 6\"":
				has_scout_named = true
			# Old buggy "Core" with no description and parameter "6\""
			if ability_name == "Core" and ability.get("parameter", "") == "6\"" and ability.get("description", "") == "":
				has_old_core_name = true
		_check("%s U_WITCHSEEKERS_C abilities contain 'Scouts 6\"'" % path, has_scout_named)
		_check("%s no leftover 'Core' (parameter 6\") ability" % path, not has_old_core_name)

func _test_scout_check_with_witchseekers_in_state() -> void:
	print("\n-- T-015b: GameState._unit_has_scout_own returns true for renamed unit --")
	var gs = root.get_node("GameState")
	# Inject a minimal Witchseeker unit into state directly
	var unit = {
		"id": "U_WS_TEST",
		"meta": {
			"name": "Witchseekers",
			"keywords": ["WITCHSEEKERS", "INFANTRY"],
			"abilities": [
				{"name": "Scouts 6\"", "type": "Core", "parameter": "6\""},
			],
		},
		"models": [],
		"flags": {},
	}
	gs.state["units"]["U_WS_TEST"] = unit
	var has_scout = gs._unit_has_scout_own("U_WS_TEST")
	_check("Renamed Witchseekers ability triggers _unit_has_scout_own", has_scout)

	# Also check the old, broken name does NOT match (regression guard)
	gs.state["units"]["U_WS_OLD"] = {
		"id": "U_WS_OLD",
		"meta": {
			"name": "Witchseekers (old)",
			"abilities": [{"name": "Core", "type": "Core", "parameter": "6\""}],
		},
		"models": [],
		"flags": {},
	}
	var old_match = gs._unit_has_scout_own("U_WS_OLD")
	_check("Old 'Core' name does NOT trigger scout — confirms the bug is real", not old_match)

	# Cleanup
	gs.state["units"].erase("U_WS_TEST")
	gs.state["units"].erase("U_WS_OLD")

func _test_scout_distance_extraction() -> void:
	print("\n-- T-015c: scout distance parsed from 'Scouts 6\"' --")
	var gs = root.get_node("GameState")
	var abilities = [{"name": "Scouts 6\"", "type": "Core", "parameter": "6\""}]
	var dist = gs._get_scout_distance_from_abilities(abilities)
	_check("Distance == 6.0", abs(dist - 6.0) < 0.0001, "got %f" % dist)

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
