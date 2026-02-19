extends "res://addons/gut/test.gd"

# Tests for the EXTRA ATTACKS keyword implementation (T3-3)
# Tests the actual RulesEngine methods for detecting Extra Attacks weapons.
#
# Per Warhammer 40k 10e rules: Extra Attacks weapons are used IN ADDITION to
# another weapon, not as an alternative. A model makes attacks with this weapon
# on top of whichever other weapon it selects.

const GameStateData = preload("res://autoloads/GameState.gd")

var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

# ==========================================
# Helper: Build a board with weapons for lookup
# ==========================================

func _make_board_with_weapons(weapons: Array) -> Dictionary:
	return {
		"units": {
			"test_unit": {
				"owner": 1,
				"models": [{"alive": true, "current_wounds": 3, "wounds": 3, "position": {"x": 100, "y": 100}}],
				"meta": {
					"name": "Test Unit",
					"stats": {"toughness": 4, "save": 3, "wounds": 3},
					"weapons": weapons,
					"keywords": ["INFANTRY"]
				}
			},
			"target_unit": {
				"owner": 2,
				"models": [{"alive": true, "current_wounds": 1, "wounds": 1, "position": {"x": 130, "y": 100}}],
				"meta": {
					"name": "Target",
					"stats": {"toughness": 4, "save": 4, "wounds": 1},
					"weapons": [],
					"keywords": ["INFANTRY"]
				}
			}
		}
	}

# ==========================================
# has_extra_attacks() Tests
# ==========================================

func test_has_extra_attacks_true_for_weapon_with_special_rules():
	"""Test that a weapon with 'extra attacks' in special_rules is detected"""
	var board = _make_board_with_weapons([{
		"name": "Attack squig",
		"type": "Melee",
		"range": "Melee",
		"attacks": "2",
		"weapon_skill": "4",
		"strength": "4",
		"ap": "0",
		"damage": "1",
		"special_rules": "extra attacks"
	}])
	var result = rules_engine.has_extra_attacks("attack_squig", board)
	assert_true(result, "Weapon with 'extra attacks' in special_rules should be detected")

func test_has_extra_attacks_false_for_regular_weapon():
	"""Test that a regular weapon without Extra Attacks returns false"""
	var board = _make_board_with_weapons([{
		"name": "Power klaw",
		"type": "Melee",
		"range": "Melee",
		"attacks": "4",
		"weapon_skill": "3",
		"strength": "10",
		"ap": "-2",
		"damage": "2"
	}])
	var result = rules_engine.has_extra_attacks("power_klaw", board)
	assert_false(result, "Weapon without Extra Attacks should return false")

func test_has_extra_attacks_case_insensitive():
	"""Test that Extra Attacks detection is case-insensitive"""
	var board = _make_board_with_weapons([{
		"name": "Test weapon",
		"type": "Melee",
		"range": "Melee",
		"attacks": "1",
		"weapon_skill": "4",
		"strength": "4",
		"ap": "0",
		"damage": "1",
		"special_rules": "Extra Attacks"
	}])
	var result = rules_engine.has_extra_attacks("test_weapon", board)
	assert_true(result, "Extra Attacks detection should be case-insensitive")

func test_has_extra_attacks_with_other_keywords():
	"""Test that Extra Attacks is detected even when mixed with other keywords"""
	var board = _make_board_with_weapons([{
		"name": "Complex weapon",
		"type": "Melee",
		"range": "Melee",
		"attacks": "3",
		"weapon_skill": "3",
		"strength": "5",
		"ap": "-1",
		"damage": "1",
		"special_rules": "lethal hits, extra attacks, sustained hits 1"
	}])
	var result = rules_engine.has_extra_attacks("complex_weapon", board)
	assert_true(result, "Extra Attacks should be detected among other keywords")

func test_has_extra_attacks_false_for_empty_weapon():
	"""Test that has_extra_attacks returns false for non-existent weapon"""
	var board = _make_board_with_weapons([])
	var result = rules_engine.has_extra_attacks("nonexistent_weapon", board)
	assert_false(result, "Non-existent weapon should return false")

# ==========================================
# weapon_data_has_extra_attacks() Tests
# ==========================================

func test_weapon_data_has_extra_attacks_true():
	"""Test that weapon_data_has_extra_attacks detects from raw weapon data"""
	var weapon_data = {
		"name": "Attack squig",
		"type": "Melee",
		"special_rules": "extra attacks"
	}
	var result = rules_engine.weapon_data_has_extra_attacks(weapon_data)
	assert_true(result, "Should detect Extra Attacks from weapon data dict")

func test_weapon_data_has_extra_attacks_false():
	"""Test that weapon_data_has_extra_attacks returns false for regular weapon"""
	var weapon_data = {
		"name": "Big choppa",
		"type": "Melee",
		"special_rules": "anti-infantry 4+"
	}
	var result = rules_engine.weapon_data_has_extra_attacks(weapon_data)
	assert_false(result, "Should return false for weapon without Extra Attacks")

func test_weapon_data_has_extra_attacks_empty_special_rules():
	"""Test that weapon_data_has_extra_attacks returns false when no special_rules"""
	var weapon_data = {
		"name": "Close combat weapon",
		"type": "Melee"
	}
	var result = rules_engine.weapon_data_has_extra_attacks(weapon_data)
	assert_false(result, "Should return false when no special_rules field")

# ==========================================
# Integration: Extra Attacks with existing Ork data
# ==========================================

func test_ork_warboss_attack_squig_has_extra_attacks():
	"""Test that the Ork Warboss's Attack squig is recognized as Extra Attacks using board data"""
	# Build a board with the Ork Warboss weapons (mirrors actual army data)
	var board = _make_board_with_weapons([
		{
			"name": "Attack squig",
			"type": "Melee",
			"range": "Melee",
			"attacks": "2",
			"weapon_skill": "4",
			"strength": "4",
			"ap": "0",
			"damage": "1",
			"special_rules": "extra attacks"
		},
		{
			"name": "Power klaw",
			"type": "Melee",
			"range": "Melee",
			"attacks": "4",
			"weapon_skill": "3",
			"strength": "10",
			"ap": "-2",
			"damage": "2"
		}
	])
	var result = rules_engine.has_extra_attacks("attack_squig", board)
	assert_true(result, "Ork Warboss Attack squig should have Extra Attacks keyword")

func test_ork_warboss_power_klaw_not_extra_attacks():
	"""Test that the Ork Warboss's Power klaw is NOT Extra Attacks"""
	var board = _make_board_with_weapons([{
		"name": "Power klaw",
		"type": "Melee",
		"range": "Melee",
		"attacks": "4",
		"weapon_skill": "3",
		"strength": "10",
		"ap": "-2",
		"damage": "2"
	}])
	var result = rules_engine.has_extra_attacks("power_klaw", board)
	assert_false(result, "Ork Warboss Power klaw should not have Extra Attacks")

func test_ork_warboss_big_choppa_not_extra_attacks():
	"""Test that the Ork Warboss's Big choppa is NOT Extra Attacks"""
	var board = _make_board_with_weapons([{
		"name": "Big choppa",
		"type": "Melee",
		"range": "Melee",
		"attacks": "5",
		"weapon_skill": "2",
		"strength": "8",
		"ap": "-1",
		"damage": "2"
	}])
	var result = rules_engine.has_extra_attacks("big_choppa", board)
	assert_false(result, "Ork Warboss Big choppa should not have Extra Attacks")

# ==========================================
# Melee resolution: Extra Attacks weapon resolves alongside regular weapon
# ==========================================

func test_extra_attacks_weapon_resolves_in_melee():
	"""Test that an Extra Attacks weapon can be resolved as part of melee combat"""
	# Position models within engagement range (1" = 40 pixels)
	var board = {
		"units": {
			"test_unit": {
				"owner": 1,
				"models": [{"alive": true, "current_wounds": 3, "wounds": 3, "position": {"x": 100, "y": 100}}],
				"meta": {
					"name": "Test Attacker",
					"stats": {"toughness": 4, "save": 3, "wounds": 3},
					"weapons": [
						{
							"name": "Power klaw",
							"type": "Melee",
							"range": "Melee",
							"attacks": "4",
							"weapon_skill": "3",
							"strength": "10",
							"ap": "-2",
							"damage": "2"
						},
						{
							"name": "Attack squig",
							"type": "Melee",
							"range": "Melee",
							"attacks": "2",
							"weapon_skill": "4",
							"strength": "4",
							"ap": "0",
							"damage": "1",
							"special_rules": "extra attacks"
						}
					],
					"keywords": ["INFANTRY"]
				}
			},
			"target_unit": {
				"owner": 2,
				"models": [
					{"alive": true, "current_wounds": 2, "wounds": 2, "position": {"x": 120, "y": 100}},
					{"alive": true, "current_wounds": 2, "wounds": 2, "position": {"x": 120, "y": 130}},
					{"alive": true, "current_wounds": 2, "wounds": 2, "position": {"x": 120, "y": 160}},
					{"alive": true, "current_wounds": 2, "wounds": 2, "position": {"x": 120, "y": 190}},
					{"alive": true, "current_wounds": 2, "wounds": 2, "position": {"x": 120, "y": 220}}
				],
				"meta": {
					"name": "Test Target",
					"stats": {"toughness": 4, "save": 4, "wounds": 2},
					"weapons": [],
					"keywords": ["INFANTRY"]
				}
			}
		}
	}

	# Build action with BOTH weapons (as Extra Attacks rule requires)
	# Empty models array = all eligible models fight
	var action = {
		"type": "FIGHT",
		"actor_unit_id": "test_unit",
		"payload": {
			"assignments": [
				{
					"attacker": "test_unit",
					"weapon": "power_klaw",
					"target": "target_unit",
					"models": []
				},
				{
					"attacker": "test_unit",
					"weapon": "attack_squig",
					"target": "target_unit",
					"models": []
				}
			]
		}
	}

	var rng = rules_engine.RNGService.new()
	var result = rules_engine.resolve_melee_attacks(action, board, rng)

	assert_true(result.success, "Melee resolution with both regular and Extra Attacks weapon should succeed")
	# Both weapons should produce dice blocks
	assert_true(result.dice.size() >= 2, "Should have dice blocks from both weapons (got %d)" % result.dice.size())
