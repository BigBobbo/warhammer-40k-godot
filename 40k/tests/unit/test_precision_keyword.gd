extends "res://addons/gut/test.gd"

# Tests for the PRECISION weapon keyword implementation (T3-4)
# Tests the ACTUAL RulesEngine methods for ranged precision handling
#
# Per Warhammer 40k 10e rules: PRECISION weapons that score Critical Hits
# (unmodified 6 to hit) can have those wounds allocated to CHARACTER models
# in the target unit, even if bodyguard models are still alive.

const GameStateData = preload("res://autoloads/GameState.gd")

var rules_engine: Node
var game_state: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	rules_engine = AutoloadHelper.get_rules_engine()
	game_state = AutoloadHelper.get_game_state()
	assert_not_null(rules_engine, "RulesEngine autoload must be available")
	assert_not_null(game_state, "GameState autoload must be available")

# ==========================================
# has_precision() Tests
# ==========================================

func test_has_precision_returns_true_for_precision_weapon():
	"""Test that has_precision detects precision in special_rules"""
	var board = _create_test_board_with_precision_weapon()
	var result = RulesEngine.has_precision("test_precision_rifle", board)
	assert_true(result, "Weapon with 'precision' in special_rules should be detected")

func test_has_precision_returns_false_for_non_precision_weapon():
	"""Test that has_precision returns false for weapons without precision"""
	var result = RulesEngine.has_precision("bolt_rifle")
	assert_false(result, "bolt_rifle should NOT have precision")

# ==========================================
# prepare_save_resolution() with Precision data
# ==========================================

func test_prepare_save_resolution_includes_precision_data():
	"""Test that prepare_save_resolution includes precision fields in save_data"""
	var board = _create_test_board_with_attached_character()
	var weapon_profile = {"name": "Precision Rifle", "bs": 3, "ap": -1, "damage": 2, "damage_raw": "2"}
	var precision_data = {"has_precision": true, "critical_hits": 2, "precision_wounds": 2}

	var save_data = RulesEngine.prepare_save_resolution(
		3,  # wounds_caused
		"bodyguard_unit",
		"shooter_unit",
		weapon_profile,
		board,
		{},  # devastating_wounds_data
		{},  # melta_data
		precision_data
	)

	assert_true(save_data.success, "save_data should succeed")
	assert_true(save_data.has_precision, "save_data should have has_precision=true")
	assert_eq(save_data.precision_wounds, 2, "save_data should have precision_wounds=2")
	assert_eq(save_data.precision_critical_hits, 2, "save_data should have precision_critical_hits=2")

func test_prepare_save_resolution_no_precision_when_not_set():
	"""Test that prepare_save_resolution has no precision when data is empty"""
	var board = _create_test_board_with_attached_character()
	var weapon_profile = {"name": "Bolt Rifle", "bs": 3, "ap": -1, "damage": 1, "damage_raw": "1"}

	var save_data = RulesEngine.prepare_save_resolution(
		3,
		"bodyguard_unit",
		"shooter_unit",
		weapon_profile,
		board,
		{},
		{},
		{}  # empty precision_data
	)

	assert_true(save_data.success, "save_data should succeed")
	assert_false(save_data.has_precision, "save_data should have has_precision=false")
	assert_eq(save_data.precision_wounds, 0, "save_data should have precision_wounds=0")

func test_prepare_save_resolution_includes_character_model_ids():
	"""Test that save_data includes character model IDs for precision targeting"""
	var board = _create_test_board_with_attached_character()
	var weapon_profile = {"name": "Test Gun", "bs": 3, "ap": 0, "damage": 1, "damage_raw": "1"}
	var precision_data = {"has_precision": true, "critical_hits": 1, "precision_wounds": 1}

	var save_data = RulesEngine.prepare_save_resolution(
		1,
		"bodyguard_unit",
		"shooter_unit",
		weapon_profile,
		board,
		{},
		{},
		precision_data
	)

	assert_true(save_data.success, "save_data should succeed")
	assert_true(save_data.has("character_model_ids"), "save_data should include character_model_ids")
	assert_true(save_data.character_model_ids.size() > 0, "character_model_ids should not be empty when character is attached")

func test_prepare_save_resolution_includes_bodyguard_alive():
	"""Test that save_data includes bodyguard_alive flag"""
	var board = _create_test_board_with_attached_character()
	var weapon_profile = {"name": "Test Gun", "bs": 3, "ap": 0, "damage": 1, "damage_raw": "1"}

	var save_data = RulesEngine.prepare_save_resolution(
		1,
		"bodyguard_unit",
		"shooter_unit",
		weapon_profile,
		board,
		{},
		{},
		{}
	)

	assert_true(save_data.success, "save_data should succeed")
	assert_true(save_data.has("bodyguard_alive"), "save_data should include bodyguard_alive flag")
	assert_true(save_data.bodyguard_alive, "bodyguard_alive should be true when bodyguard models exist")

func test_prepare_save_resolution_model_profiles_include_is_character():
	"""Test that model_save_profiles include the is_character flag"""
	var board = _create_test_board_with_attached_character()
	var weapon_profile = {"name": "Test Gun", "bs": 3, "ap": 0, "damage": 1, "damage_raw": "1"}

	var save_data = RulesEngine.prepare_save_resolution(
		1,
		"bodyguard_unit",
		"shooter_unit",
		weapon_profile,
		board,
		{},
		{},
		{}
	)

	assert_true(save_data.success, "save_data should succeed")
	var profiles = save_data.model_save_profiles
	assert_true(profiles.size() > 0, "Should have model save profiles")

	# Check that at least one profile has is_character
	var has_character_profile = false
	var has_non_character_profile = false
	for profile in profiles:
		assert_true(profile.has("is_character"), "Each profile should have is_character field")
		if profile.is_character:
			has_character_profile = true
		else:
			has_non_character_profile = true

	assert_true(has_character_profile, "Should have at least one character profile (attached character)")
	assert_true(has_non_character_profile, "Should have at least one non-character profile (bodyguard)")

# ==========================================
# Precision wounds capped by critical hits
# ==========================================

func test_precision_wounds_capped_by_critical_hits():
	"""Test that precision_wounds is min(critical_hits, wounds_caused)"""
	var board = _create_test_board_with_attached_character()
	var weapon_profile = {"name": "Precision Rifle", "bs": 3, "ap": -1, "damage": 2, "damage_raw": "2"}

	# 1 critical hit but 3 wounds caused -> only 1 precision wound
	var precision_data = {"has_precision": true, "critical_hits": 1, "precision_wounds": 1}
	var save_data = RulesEngine.prepare_save_resolution(
		3, "bodyguard_unit", "shooter_unit", weapon_profile, board, {}, {}, precision_data
	)
	assert_eq(save_data.precision_wounds, 1, "precision_wounds should be 1 (capped by critical_hits)")

func test_precision_wounds_capped_by_wounds_caused():
	"""Test that precision_wounds doesn't exceed wounds_caused"""
	var board = _create_test_board_with_attached_character()
	var weapon_profile = {"name": "Precision Rifle", "bs": 3, "ap": -1, "damage": 2, "damage_raw": "2"}

	# 5 critical hits but only 2 wounds caused -> only 2 precision wounds
	var precision_data = {"has_precision": true, "critical_hits": 5, "precision_wounds": 2}
	var save_data = RulesEngine.prepare_save_resolution(
		2, "bodyguard_unit", "shooter_unit", weapon_profile, board, {}, {}, precision_data
	)
	assert_eq(save_data.precision_wounds, 2, "precision_wounds should be 2 (capped by wounds_caused)")

# ==========================================
# Helper functions
# ==========================================

func _create_test_board_with_precision_weapon() -> Dictionary:
	return {
		"units": {
			"target_unit": {
				"meta": {"name": "Test Target", "stats": {"toughness": 4, "save": 6}, "keywords": []},
				"models": [{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1}]
			}
		},
		"weapons": {
			"test_precision_rifle": {
				"name": "Precision Rifle",
				"bs": 3, "s": 4, "ap": -1, "damage": 2, "damage_raw": "2",
				"special_rules": "precision",
				"keywords": []
			}
		}
	}

func _create_test_board_with_attached_character() -> Dictionary:
	return {
		"units": {
			"bodyguard_unit": {
				"id": "bodyguard_unit",
				"meta": {
					"name": "Bodyguard Squad",
					"stats": {"toughness": 4, "save": 3},
					"keywords": ["INFANTRY"]
				},
				"models": [
					{"id": "m0", "alive": true, "wounds": 2, "current_wounds": 2},
					{"id": "m1", "alive": true, "wounds": 2, "current_wounds": 2},
					{"id": "m2", "alive": true, "wounds": 2, "current_wounds": 2}
				],
				"attachment_data": {
					"attached_characters": ["char_unit"]
				}
			},
			"char_unit": {
				"id": "char_unit",
				"meta": {
					"name": "Captain",
					"stats": {"toughness": 4, "save": 3},
					"keywords": ["CHARACTER", "INFANTRY"]
				},
				"models": [
					{"id": "leader", "alive": true, "wounds": 5, "current_wounds": 5, "keywords": ["CHARACTER"]}
				]
			},
			"shooter_unit": {
				"id": "shooter_unit",
				"meta": {
					"name": "Sniper Squad",
					"stats": {"toughness": 3, "save": 4},
					"keywords": ["INFANTRY"]
				},
				"models": [
					{"id": "m0", "alive": true, "wounds": 1, "current_wounds": 1}
				]
			}
		}
	}
