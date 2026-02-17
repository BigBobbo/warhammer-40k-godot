extends "res://addons/gut/test.gd"

# Tests for the MELTA X keyword implementation (T1-1)
# Tests the ACTUAL RulesEngine methods, not duplicate local implementations
#
# Per Warhammer 40k 10e rules: MELTA X weapons add +X to the Damage
# characteristic when the target unit is within half the weapon's range.

const GameStateData = preload("res://autoloads/GameState.gd")

var rules_engine: Node
var game_state: Node

func before_each():
	# Verify autoloads are available
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return

	# Get actual autoload singletons
	rules_engine = AutoloadHelper.get_rules_engine()
	game_state = AutoloadHelper.get_game_state()

	assert_not_null(rules_engine, "RulesEngine autoload must be available")
	assert_not_null(game_state, "GameState autoload must be available")

# ==========================================
# get_melta_value() Tests
# ==========================================

func test_get_melta_value_returns_2_for_meltagun():
	"""Test that meltagun has Melta 2"""
	var result = rules_engine.get_melta_value("meltagun")
	assert_eq(result, 2, "meltagun should have Melta value of 2")

func test_get_melta_value_returns_2_for_multi_melta():
	"""Test that multi_melta has Melta 2"""
	var result = rules_engine.get_melta_value("multi_melta")
	assert_eq(result, 2, "multi_melta should have Melta value of 2")

func test_get_melta_value_returns_2_for_test_melta_fixed():
	"""Test that test_melta_fixed has Melta 2"""
	var result = rules_engine.get_melta_value("test_melta_fixed")
	assert_eq(result, 2, "test_melta_fixed should have Melta value of 2")

func test_get_melta_value_returns_0_for_bolt_rifle():
	"""Test that bolt_rifle has no Melta"""
	var result = rules_engine.get_melta_value("bolt_rifle")
	assert_eq(result, 0, "bolt_rifle should NOT have Melta")

func test_get_melta_value_returns_0_for_lascannon():
	"""Test that lascannon has no Melta"""
	var result = rules_engine.get_melta_value("lascannon")
	assert_eq(result, 0, "lascannon should NOT have Melta")

func test_get_melta_value_returns_0_for_unknown_weapon():
	"""Test that unknown weapon returns 0"""
	var result = rules_engine.get_melta_value("nonexistent_weapon")
	assert_eq(result, 0, "Unknown weapon should return 0")

# ==========================================
# is_melta_weapon() Tests
# ==========================================

func test_is_melta_weapon_returns_true_for_meltagun():
	"""Test that meltagun is recognized as a Melta weapon"""
	var result = rules_engine.is_melta_weapon("meltagun")
	assert_true(result, "meltagun should be a Melta weapon")

func test_is_melta_weapon_returns_true_for_multi_melta():
	"""Test that multi_melta is recognized as a Melta weapon"""
	var result = rules_engine.is_melta_weapon("multi_melta")
	assert_true(result, "multi_melta should be a Melta weapon")

func test_is_melta_weapon_returns_false_for_bolt_rifle():
	"""Test that bolt_rifle is NOT a Melta weapon"""
	var result = rules_engine.is_melta_weapon("bolt_rifle")
	assert_false(result, "bolt_rifle should NOT be a Melta weapon")

func test_is_melta_weapon_returns_false_for_flamer():
	"""Test that flamer is NOT a Melta weapon"""
	var result = rules_engine.is_melta_weapon("flamer")
	assert_false(result, "flamer should NOT be a Melta weapon")

# ==========================================
# Melta value parsing from special_rules string
# ==========================================

func test_get_melta_value_from_special_rules():
	"""Test that Melta value can be parsed from special_rules string"""
	# Create a mock board with a weapon that uses special_rules format
	# Board weapon format uses strings for numeric values (army list format)
	var board = {
		"units": {
			"test_unit": {
				"meta": {
					"weapons": [{
						"id": "test_melta_sr",
						"name": "Test Melta SR",
						"range": "12",
						"attacks": "1",
						"ballistic_skill": "3",
						"strength": "9",
						"ap": "-4",
						"damage": "D6",
						"special_rules": "Melta 4",
						"keywords": []
					}]
				},
				"models": [{"id": "m1", "alive": true, "weapons": ["test_melta_sr"]}]
			}
		}
	}
	var result = rules_engine.get_melta_value("test_melta_sr", board)
	assert_eq(result, 4, "Should parse Melta 4 from special_rules")

# ==========================================
# prepare_save_resolution() includes melta data
# ==========================================

func test_prepare_save_resolution_includes_melta_bonus():
	"""Test that prepare_save_resolution includes melta_bonus in save_data"""
	var board = _create_test_board()
	var weapon_profile = rules_engine.get_weapon_profile("test_melta_fixed")
	var melta_data = {
		"melta_value": 2,
		"models_in_half_range": 1,
		"total_models": 1
	}

	var save_data = rules_engine.prepare_save_resolution(
		1,  # wounds_caused
		"target_unit",
		"shooter_unit",
		weapon_profile,
		board,
		{},  # devastating_wounds_data
		melta_data
	)

	assert_true(save_data.success, "save_data should succeed")
	assert_eq(save_data.melta_bonus, 2, "save_data should have melta_bonus of 2")
	assert_eq(save_data.melta_models_in_half_range, 1, "save_data should have 1 model in half range")
	assert_eq(save_data.melta_total_models, 1, "save_data should have 1 total model")

func test_prepare_save_resolution_no_melta_when_not_melta_weapon():
	"""Test that prepare_save_resolution has 0 melta_bonus for non-melta weapons"""
	var board = _create_test_board()
	var weapon_profile = rules_engine.get_weapon_profile("bolt_rifle")

	var save_data = rules_engine.prepare_save_resolution(
		1,  # wounds_caused
		"target_unit",
		"shooter_unit",
		weapon_profile,
		board,
		{}  # devastating_wounds_data
		# No melta_data — defaults to empty
	)

	assert_true(save_data.success, "save_data should succeed")
	assert_eq(save_data.melta_bonus, 0, "save_data should have melta_bonus of 0 for non-melta weapon")

# ==========================================
# apply_save_damage() with Melta bonus
# ==========================================

func test_apply_save_damage_adds_melta_bonus_to_damage():
	"""Test that apply_save_damage adds melta bonus when in half range"""
	var board = _create_test_board_with_high_wounds()
	var save_data = {
		"target_unit_id": "target_unit",
		"damage": 3,  # Fixed base damage
		"damage_raw": "3",
		"total_wounds": 1,
		"melta_bonus": 2,
		"melta_models_in_half_range": 1,
		"melta_total_models": 1,
		"devastating_wounds": 0,
		"devastating_damage": 0,
		"has_devastating_wounds": false
	}
	var save_results = [{"saved": false, "model_index": 0}]

	var result = rules_engine.apply_save_damage(save_results, save_data, board)

	# Base damage 3 + melta bonus 2 = 5 total damage
	assert_eq(result.damage_applied, 5, "Damage should be 3 (base) + 2 (melta) = 5")

func test_apply_save_damage_no_melta_when_outside_half_range():
	"""Test that apply_save_damage does NOT add melta bonus when outside half range"""
	var board = _create_test_board_with_high_wounds()
	var save_data = {
		"target_unit_id": "target_unit",
		"damage": 3,
		"damage_raw": "3",
		"total_wounds": 1,
		"melta_bonus": 2,
		"melta_models_in_half_range": 0,  # No models in half range
		"melta_total_models": 1,
		"devastating_wounds": 0,
		"devastating_damage": 0,
		"has_devastating_wounds": false
	}
	var save_results = [{"saved": false, "model_index": 0}]

	var result = rules_engine.apply_save_damage(save_results, save_data, board)

	# No melta bonus — just base damage 3
	assert_eq(result.damage_applied, 3, "Damage should be 3 (base only, no melta)")

func test_apply_save_damage_melta_proportional_for_split_range():
	"""Test that melta bonus applies proportionally when some models in half range"""
	var board = _create_test_board_with_high_wounds()
	var save_data = {
		"target_unit_id": "target_unit",
		"damage": 3,
		"damage_raw": "3",
		"total_wounds": 2,
		"melta_bonus": 2,
		"melta_models_in_half_range": 1,  # 1 of 2 models in half range
		"melta_total_models": 2,
		"devastating_wounds": 0,
		"devastating_damage": 0,
		"has_devastating_wounds": false
	}
	# 2 failed saves
	var save_results = [
		{"saved": false, "model_index": 0},
		{"saved": false, "model_index": 0}
	]

	var result = rules_engine.apply_save_damage(save_results, save_data, board)

	# 1 wound with melta (3+2=5) + 1 wound without melta (3) = 8 total
	assert_eq(result.damage_applied, 8, "Damage should be 5 (melta) + 3 (no melta) = 8")

func test_apply_save_damage_no_melta_bonus_for_non_melta_weapon():
	"""Test that non-melta weapons get no bonus even with save_data fields present"""
	var board = _create_test_board_with_high_wounds()
	var save_data = {
		"target_unit_id": "target_unit",
		"damage": 3,
		"damage_raw": "3",
		"total_wounds": 1,
		"melta_bonus": 0,  # No melta bonus
		"melta_models_in_half_range": 0,
		"melta_total_models": 0,
		"devastating_wounds": 0,
		"devastating_damage": 0,
		"has_devastating_wounds": false
	}
	var save_results = [{"saved": false, "model_index": 0}]

	var result = rules_engine.apply_save_damage(save_results, save_data, board)

	assert_eq(result.damage_applied, 3, "Damage should be 3 (no melta bonus)")

# ==========================================
# Helper functions
# ==========================================

func _create_test_board() -> Dictionary:
	return {
		"units": {
			"target_unit": {
				"meta": {
					"name": "Test Target",
					"stats": {"toughness": 4, "save": 6},
					"keywords": []
				},
				"models": [
					{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1}
				]
			},
			"shooter_unit": {
				"meta": {
					"name": "Test Shooter",
					"stats": {"toughness": 4, "save": 3},
					"keywords": []
				},
				"models": [
					{"id": "m1", "alive": true, "wounds": 2, "current_wounds": 2}
				]
			}
		}
	}

func _create_test_board_with_high_wounds() -> Dictionary:
	return {
		"units": {
			"target_unit": {
				"meta": {
					"name": "Test Vehicle",
					"stats": {"toughness": 10, "save": 3},
					"keywords": ["VEHICLE"]
				},
				"models": [
					{"id": "m1", "alive": true, "wounds": 20, "current_wounds": 20}
				]
			}
		}
	}
