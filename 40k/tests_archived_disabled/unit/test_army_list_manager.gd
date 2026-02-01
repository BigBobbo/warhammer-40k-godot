extends "res://addons/gut/test.gd"

# Unit tests for ArmyListManager
# Tests loading, validation, and parsing of army lists

var army_manager: ArmyListManager
var test_army_data: Dictionary

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	army_manager = ArmyListManager.new()

	# Create test army data
	test_army_data = {
		"faction": {
			"name": "Test Marines",
			"points": 500,
			"detachment": "Test Company"
		},
		"units": {
			"TEST_UNIT_A": {
				"id": "TEST_UNIT_A",
				"squad_id": "TEST_UNIT_A",
				"owner": 1,
				"status": "UNDEPLOYED",
				"meta": {
					"name": "Test Squad",
					"keywords": ["INFANTRY", "IMPERIUM"],
					"stats": {"move": 6, "toughness": 4, "save": 3},
					"weapons": [
						{
							"name": "Test Bolter",
							"type": "Ranged",
							"range": "24",
							"attacks": "2",
							"ballistic_skill": "3",
							"strength": "4",
							"ap": "-1",
							"damage": "1",
							"special_rules": "rapid fire 1"
						}
					]
				},
				"models": [
					{"id": "m1", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true}
				]
			}
		}
	}

func after_each():
	if army_manager:
		army_manager.queue_free()

func test_validate_army_structure_valid():
	var result = army_manager.validate_army_structure(test_army_data)
	
	assert_true(result.valid, "Valid army structure should pass validation")
	assert_eq(result.errors.size(), 0, "Valid army should have no errors")

func test_validate_army_structure_missing_units():
	var invalid_data = {"faction": {"name": "Test"}}
	var result = army_manager.validate_army_structure(invalid_data)
	
	assert_false(result.valid, "Army without units should fail validation")
	assert_true(result.errors.size() > 0, "Should have validation errors")

func test_validate_army_structure_missing_unit_fields():
	var invalid_army = test_army_data.duplicate(true)
	invalid_army.units.TEST_UNIT_A.erase("meta")
	
	var result = army_manager.validate_army_structure(invalid_army)
	
	assert_false(result.valid, "Army with missing unit fields should fail validation")
	assert_true(result.errors.size() > 0, "Should have validation errors")

func test_validate_army_structure_empty_models():
	var invalid_army = test_army_data.duplicate(true)
	invalid_army.units.TEST_UNIT_A.models = []
	
	var result = army_manager.validate_army_structure(invalid_army)
	
	assert_false(result.valid, "Army with empty models should fail validation")

func test_apply_army_to_game_state():
	# Mock GameState
	if not GameState:
		pending("GameState not available in test environment")
		return
	
	GameState.state = {"units": {}, "factions": {}}
	
	army_manager.apply_army_to_game_state(test_army_data, 1)
	
	assert_true(GameState.state.units.has("TEST_UNIT_A"), "Unit should be added to game state")
	assert_eq(GameState.state.units.TEST_UNIT_A.owner, 1, "Unit owner should be set correctly")
	assert_true(GameState.state.factions.has("1"), "Faction should be set for player")

func test_create_fallback_army():
	var fallback = army_manager.create_fallback_army(1)
	
	assert_true(fallback.has("faction"), "Fallback should have faction")
	assert_true(fallback.has("units"), "Fallback should have units")
	assert_eq(fallback.faction.name, "Fallback Army", "Fallback should have correct name")

# Test weapon parsing integration
func test_weapon_parsing_integration():
	var weapon_data = {
		"name": "Test Weapon",
		"type": "Ranged",
		"range": "24",
		"attacks": "D6",
		"ballistic_skill": "3",
		"strength": "6",
		"ap": "-2",
		"damage": "2",
		"special_rules": "assault"
	}
	
	var parsed = RulesEngine.parse_weapon_stats(weapon_data)
	
	assert_eq(parsed.range, 24, "Range should be parsed correctly")
	assert_eq(parsed.strength, 6, "Strength should be parsed correctly")
	assert_eq(parsed.ap, -2, "AP should be parsed correctly")
	assert_eq(parsed.attacks.dice, "D6", "Dice notation should be preserved")
	assert_eq(parsed.damage.min, 2, "Damage should be parsed correctly")

func test_dice_notation_parsing():
	# Test various dice notations
	var test_cases = [
		{"input": "D3", "expected_min": 1, "expected_max": 3, "expected_dice": "D3"},
		{"input": "D6", "expected_min": 1, "expected_max": 6, "expected_dice": "D6"},
		{"input": "2D6", "expected_min": 2, "expected_max": 12, "expected_dice": "2D6"},
		{"input": "3", "expected_min": 3, "expected_max": 3, "expected_dice": ""},
		{"input": "D6+2", "expected_min": 3, "expected_max": 8, "expected_dice": "D6+2"}
	]
	
	for test_case in test_cases:
		var result = RulesEngine._parse_dice_notation(test_case.input)
		
		assert_eq(result.min, test_case.expected_min, "Min value for " + test_case.input)
		assert_eq(result.max, test_case.expected_max, "Max value for " + test_case.input)
		assert_eq(result.dice, test_case.expected_dice, "Dice notation for " + test_case.input)

func test_damage_notation_parsing():
	var test_cases = [
		{"input": "1", "expected_min": 1, "expected_max": 1},
		{"input": "D3", "expected_min": 1, "expected_max": 3},
		{"input": "D6+1", "expected_min": 2, "expected_max": 7}
	]
	
	for test_case in test_cases:
		var result = RulesEngine._parse_damage(test_case.input)
		
		assert_eq(result.min, test_case.expected_min, "Min damage for " + test_case.input)
		assert_eq(result.max, test_case.expected_max, "Max damage for " + test_case.input)

func test_ap_value_parsing():
	var test_cases = [
		{"input": "0", "expected": 0},
		{"input": "-1", "expected": -1},
		{"input": "-3", "expected": -3},
		{"input": "2", "expected": -2}  # Positive numbers should become negative
	]
	
	for test_case in test_cases:
		var result = RulesEngine._parse_ap_value(test_case.input)
		assert_eq(result, test_case.expected, "AP value for " + test_case.input)

func test_range_parsing():
	assert_eq(RulesEngine._parse_range("Melee"), 0, "Melee range should be 0")
	assert_eq(RulesEngine._parse_range("24"), 24, "Numeric range should parse correctly")
	assert_eq(RulesEngine._parse_range("12"), 12, "Numeric range should parse correctly")
	assert_eq(RulesEngine._parse_range("invalid"), 24, "Invalid range should default to 24")

func test_special_rules_validation():
	var result = RulesEngine.validate_weapon_special_rules("assault, rapid fire 2")
	assert_true(result.valid, "Known special rules should be valid")
	
	# Test unknown rule (should warn but not fail)
	result = RulesEngine.validate_weapon_special_rules("unknown_rule")
	assert_true(result.valid, "Unknown rules should not fail validation")

# Integration test - load actual army file
func test_load_real_army_file():
	# This test requires the actual JSON files to exist
	var available_armies = army_manager.get_available_armies()
	
	if available_armies.has("space_marines"):
		var army = army_manager.load_army_list("space_marines", 1)
		assert_false(army.is_empty(), "Should be able to load space_marines army")
		assert_true(army.has("units"), "Loaded army should have units")
		assert_true(army.has("faction"), "Loaded army should have faction")
	else:
		pending("space_marines.json not found for integration test")