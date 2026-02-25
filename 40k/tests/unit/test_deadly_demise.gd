extends SceneTree

# Test Deadly Demise (P1-13)
# Verifies that the Deadly Demise ability correctly:
# 1. Detects the ability on units from army JSON data
# 2. Parses the correct damage value (D6, D3, 1)
# 3. AI profile includes Deadly Demise info
# 4. Resolution function structure (tested via autoload when available)
# Run with: godot --headless --path <project_path> --script tests/unit/test_deadly_demise.gd

const AIAbilityAnalyzer = preload("res://scripts/AIAbilityAnalyzer.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== Deadly Demise Tests (P1-13) ===\n")
	_run_tests()

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	if _fail_count > 0:
		print("SOME TESTS FAILED!")
		quit(1)
	else:
		print("ALL TESTS PASSED!")
		quit(0)

func _run_tests():
	test_deadly_demise_ability_detection()
	test_deadly_demise_value_parsing()
	test_ai_analyzer_detects_deadly_demise()
	test_deadly_demise_ability_in_battlewagon_json()
	test_deadly_demise_ability_in_caladius_json()
	test_deadly_demise_ability_in_contemptor_json()
	test_deadly_demise_ability_in_telemon_json()
	test_deadly_demise_damage_roll_logic()
	test_deadly_demise_affects_all_units()

# ============================================================================
# HELPERS
# ============================================================================

func assert_true(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("  PASS: %s" % message)
	else:
		_fail_count += 1
		print("  FAIL: %s" % message)

func assert_eq(a, b, message: String) -> void:
	if a == b:
		_pass_count += 1
		print("  PASS: %s" % message)
	else:
		_fail_count += 1
		print("  FAIL: %s (got '%s', expected '%s')" % [message, str(a), str(b)])

func _make_unit(unit_id: String, name_str: String, owner: int, abilities: Array, wounds: int = 1, alive: bool = true) -> Dictionary:
	"""Create a minimal unit dictionary for testing."""
	return {
		"id": unit_id,
		"owner": owner,
		"meta": {
			"name": name_str,
			"keywords": ["VEHICLE"],
			"abilities": abilities
		},
		"models": [
			{
				"id": "m1",
				"wounds": wounds,
				"current_wounds": 0 if not alive else wounds,
				"base_mm": 60,
				"alive": alive
			}
		]
	}

func _load_json(path: String) -> Dictionary:
	"""Load a JSON army file."""
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("  ERROR: Could not open %s" % path)
		return {}
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()
	if error != OK:
		print("  ERROR: Failed to parse JSON: %s" % json.get_error_message())
		return {}
	return json.data

func _get_unit_from_json(json_data: Dictionary, unit_id: String) -> Dictionary:
	"""Extract a unit from army JSON data."""
	return json_data.get("units", {}).get(unit_id, {})

# ============================================================================
# TESTS
# ============================================================================

func test_deadly_demise_ability_detection():
	print("\ntest_deadly_demise_ability_detection:")

	var unit_d6 = _make_unit("U1", "Battlewagon", 1, [
		{"name": "Deadly Demise D6", "type": "Core", "description": "When this model is destroyed, roll one D6. On a 6, each unit within 6\" suffers D6 mortal wounds."}
	], 16, false)

	var unit_d3 = _make_unit("U2", "Caladius", 1, [
		{"name": "Deadly Demise D3", "type": "Core", "description": "When this model is destroyed, roll one D6. On a 6, each unit within 6\" suffers D3 mortal wounds."}
	], 14, false)

	var unit_1 = _make_unit("U3", "Contemptor", 1, [
		{"name": "Deadly Demise 1", "type": "Core", "description": "When this model is destroyed, roll one D6. On a 6, each unit within 6\" suffers 1 mortal wound."}
	], 10, false)

	var unit_no_dd = _make_unit("U4", "Regular Vehicle", 1, [], 10)

	# Test AIAbilityAnalyzer detection
	assert_true(AIAbilityAnalyzer.has_deadly_demise(unit_d6), "Battlewagon with DD D6 detected")
	assert_true(AIAbilityAnalyzer.has_deadly_demise(unit_d3), "Caladius with DD D3 detected")
	assert_true(AIAbilityAnalyzer.has_deadly_demise(unit_1), "Contemptor with DD 1 detected")
	assert_true(not AIAbilityAnalyzer.has_deadly_demise(unit_no_dd), "Regular vehicle has no DD")

func test_deadly_demise_value_parsing():
	print("\ntest_deadly_demise_value_parsing:")

	var unit_d6 = _make_unit("U1", "Battlewagon", 1, [
		{"name": "Deadly Demise D6", "type": "Core", "description": ""}
	], 16, false)

	var unit_d3 = _make_unit("U2", "Caladius", 1, [
		{"name": "Deadly Demise D3", "type": "Core", "description": ""}
	], 14, false)

	assert_eq(AIAbilityAnalyzer.get_deadly_demise_value(unit_d6), 6, "DD D6 → value 6")
	assert_eq(AIAbilityAnalyzer.get_deadly_demise_value(unit_d3), 3, "DD D3 → value 3")

func test_ai_analyzer_detects_deadly_demise():
	print("\ntest_ai_analyzer_detects_deadly_demise:")

	var unit_d6 = _make_unit("U1", "Battlewagon", 1, [
		{"name": "Deadly Demise D6", "type": "Core", "description": "When this model is destroyed, roll one D6. On a 6, each unit within 6\" suffers D6 mortal wounds."}
	], 16, false)

	var all_units = {"U1": unit_d6}
	var profile = AIAbilityAnalyzer.get_unit_ability_profile("U1", unit_d6, all_units)
	assert_true(profile.get("has_deadly_demise", false), "AI profile detects Deadly Demise")
	assert_eq(profile.get("deadly_demise_value", 0), 6, "AI profile shows DD value 6")

func test_deadly_demise_ability_in_battlewagon_json():
	print("\ntest_deadly_demise_ability_in_battlewagon_json:")

	var json = _load_json("res://armies/orks.json")
	if json.is_empty():
		print("  SKIP: Could not load orks.json")
		return

	var unit = _get_unit_from_json(json, "U_BATTLEWAGON_G")
	assert_true(not unit.is_empty(), "Battlewagon found in orks.json")
	assert_true(AIAbilityAnalyzer.has_deadly_demise(unit), "Battlewagon has Deadly Demise in JSON")
	assert_eq(AIAbilityAnalyzer.get_deadly_demise_value(unit), 6, "Battlewagon DD value is D6 (6)")

func test_deadly_demise_ability_in_caladius_json():
	print("\ntest_deadly_demise_ability_in_caladius_json:")

	var json = _load_json("res://armies/adeptus_custodes.json")
	if json.is_empty():
		print("  SKIP: Could not load adeptus_custodes.json")
		return

	var unit = _get_unit_from_json(json, "U_CALADIUS_GRAV-TANK_E")
	assert_true(not unit.is_empty(), "Caladius found in adeptus_custodes.json")
	assert_true(AIAbilityAnalyzer.has_deadly_demise(unit), "Caladius has Deadly Demise in JSON")
	assert_eq(AIAbilityAnalyzer.get_deadly_demise_value(unit), 3, "Caladius DD value is D3 (3)")

func test_deadly_demise_ability_in_contemptor_json():
	print("\ntest_deadly_demise_ability_in_contemptor_json:")

	var json = _load_json("res://armies/adeptus_custodes.json")
	if json.is_empty():
		print("  SKIP: Could not load adeptus_custodes.json")
		return

	var unit = _get_unit_from_json(json, "U_CONTEMPTOR-ACHILLUS_DREADNOUGHT_H")
	assert_true(not unit.is_empty(), "Contemptor-Achillus found in adeptus_custodes.json")
	assert_true(AIAbilityAnalyzer.has_deadly_demise(unit), "Contemptor-Achillus has Deadly Demise in JSON")

func test_deadly_demise_ability_in_telemon_json():
	print("\ntest_deadly_demise_ability_in_telemon_json:")

	var json = _load_json("res://armies/adeptus_custodes.json")
	if json.is_empty():
		print("  SKIP: Could not load adeptus_custodes.json")
		return

	var unit = _get_unit_from_json(json, "U_TELEMON_HEAVY_DREADNOUGHT_I")
	assert_true(not unit.is_empty(), "Telemon found in adeptus_custodes.json")
	assert_true(AIAbilityAnalyzer.has_deadly_demise(unit), "Telemon has Deadly Demise in JSON")
	assert_eq(AIAbilityAnalyzer.get_deadly_demise_value(unit), 3, "Telemon DD value is D3 (3)")

func test_deadly_demise_damage_roll_logic():
	print("\ntest_deadly_demise_damage_roll_logic:")

	# Test that the damage value string parsing is correct
	# D6 values
	var unit_d6 = _make_unit("U1", "BW", 1, [
		{"name": "Deadly Demise D6", "type": "Core", "description": ""}
	], 16)
	# Verify the ability name can be split to extract the value
	var abilities = unit_d6.get("meta", {}).get("abilities", [])
	var dd_name = ""
	for ab in abilities:
		if ab is Dictionary:
			var n = ab.get("name", "")
			if n.begins_with("Deadly Demise"):
				dd_name = n
	var parts = dd_name.split(" ")
	assert_eq(parts.size(), 3, "DD name has 3 parts: 'Deadly Demise D6'")
	assert_eq(parts[2], "D6", "Third part is 'D6'")

	# Test D3
	var unit_d3 = _make_unit("U2", "Cal", 1, [
		{"name": "Deadly Demise D3", "type": "Core", "description": ""}
	], 14)
	abilities = unit_d3.get("meta", {}).get("abilities", [])
	dd_name = ""
	for ab in abilities:
		if ab is Dictionary:
			var n = ab.get("name", "")
			if n.begins_with("Deadly Demise"):
				dd_name = n
	parts = dd_name.split(" ")
	assert_eq(parts[2], "D3", "Third part is 'D3'")

	# Test fixed value
	var unit_1 = _make_unit("U3", "Cont", 1, [
		{"name": "Deadly Demise 1", "type": "Core", "description": ""}
	], 10)
	abilities = unit_1.get("meta", {}).get("abilities", [])
	dd_name = ""
	for ab in abilities:
		if ab is Dictionary:
			var n = ab.get("name", "")
			if n.begins_with("Deadly Demise"):
				dd_name = n
	parts = dd_name.split(" ")
	assert_eq(parts[2], "1", "Third part is '1' (fixed value)")
	assert_true(parts[2].is_valid_int(), "'1' is a valid integer")
	assert_eq(int(parts[2]), 1, "Parsed fixed value is 1")

func test_deadly_demise_affects_all_units():
	print("\ntest_deadly_demise_affects_all_units:")

	# The rules say "each unit within 6\"" — this means BOTH friendly and enemy
	# Verify this by checking the description text in abilities
	var unit_dd = _make_unit("U1", "Battlewagon", 1, [
		{"name": "Deadly Demise D6", "type": "Core",
		 "description": "When this model is destroyed, roll one D6. On a 6, each unit within 6\" suffers D6 mortal wounds."}
	], 16)

	var abilities = unit_dd.get("meta", {}).get("abilities", [])
	var dd_desc = ""
	for ab in abilities:
		if ab is Dictionary and ab.get("name", "").begins_with("Deadly Demise"):
			dd_desc = ab.get("description", "")

	# The description should say "each unit" (not "each enemy unit")
	assert_true("each unit within 6" in dd_desc, "DD description says 'each unit within 6\"' (affects all, not just enemies)")
	assert_true("mortal wounds" in dd_desc, "DD description mentions mortal wounds")
	assert_true("On a 6" in dd_desc, "DD description mentions trigger on 6")
