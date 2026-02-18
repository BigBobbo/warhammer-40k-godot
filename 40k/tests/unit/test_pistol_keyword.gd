extends "res://addons/gut/test.gd"

# Tests for the PISTOL keyword implementation
# Tests the ACTUAL RulesEngine methods, not duplicate local implementations
#
# Per Warhammer 40k rules: Units with PISTOL weapons can shoot while in
# Engagement Range, but can only target units they are in Engagement Range with.

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
# is_pistol_weapon() Tests
# Tests the actual RulesEngine.is_pistol_weapon() method
# ==========================================

func test_is_pistol_weapon_returns_true_for_plasma_pistol():
	"""Test that plasma_pistol is recognized as a Pistol weapon"""
	var result = rules_engine.is_pistol_weapon("plasma_pistol")
	assert_true(result, "plasma_pistol should be recognized as a Pistol weapon")

func test_is_pistol_weapon_returns_true_for_slugga():
	"""Test that slugga is recognized as a Pistol weapon"""
	var result = rules_engine.is_pistol_weapon("slugga")
	assert_true(result, "slugga should be recognized as a Pistol weapon")

func test_is_pistol_weapon_returns_false_for_bolt_rifle():
	"""Test that bolt_rifle is NOT a Pistol weapon"""
	var result = rules_engine.is_pistol_weapon("bolt_rifle")
	assert_false(result, "bolt_rifle should NOT be recognized as a Pistol weapon")

func test_is_pistol_weapon_returns_false_for_shoota():
	"""Test that shoota (Assault weapon) is NOT a Pistol weapon"""
	var result = rules_engine.is_pistol_weapon("shoota")
	assert_false(result, "shoota should NOT be recognized as a Pistol weapon")

func test_is_pistol_weapon_returns_false_for_heavy_bolter():
	"""Test that heavy_bolter (Heavy weapon) is NOT a Pistol weapon"""
	var result = rules_engine.is_pistol_weapon("heavy_bolter")
	assert_false(result, "heavy_bolter should NOT be recognized as a Pistol weapon")

func test_is_pistol_weapon_returns_false_for_unknown_weapon():
	"""Test that unknown weapon returns false"""
	var result = rules_engine.is_pistol_weapon("nonexistent_weapon")
	assert_false(result, "Unknown weapon should return false")

# ==========================================
# Weapon Profile Tests
# Verify WEAPON_PROFILES are correctly configured
# ==========================================

func test_weapon_profile_plasma_pistol_has_pistol_keyword():
	"""Test that plasma_pistol profile contains PISTOL keyword"""
	var profile = rules_engine.get_weapon_profile("plasma_pistol")
	assert_false(profile.is_empty(), "Should find plasma_pistol profile")
	var keywords = profile.get("keywords", [])
	assert_has(keywords, "PISTOL", "Plasma Pistol should have PISTOL keyword")

func test_weapon_profile_slugga_has_pistol_keyword():
	"""Test that slugga profile contains PISTOL keyword"""
	var profile = rules_engine.get_weapon_profile("slugga")
	assert_false(profile.is_empty(), "Should find slugga profile")
	var keywords = profile.get("keywords", [])
	assert_has(keywords, "PISTOL", "Slugga should have PISTOL keyword")

func test_weapon_profile_bolt_rifle_no_pistol_keyword():
	"""Test that bolt_rifle profile does NOT contain PISTOL keyword"""
	var profile = rules_engine.get_weapon_profile("bolt_rifle")
	assert_false(profile.is_empty(), "Should find bolt_rifle profile")
	var keywords = profile.get("keywords", [])
	assert_does_not_have(keywords, "PISTOL", "Bolt rifle should NOT have PISTOL keyword")

# ==========================================
# unit_has_pistol_weapons() Tests
# ==========================================

func test_unit_has_pistol_weapons_intercessors():
	"""Test that Intercessors unit has Pistol weapons (plasma_pistol on sergeant)"""
	var result = rules_engine.unit_has_pistol_weapons("U_INTERCESSORS_A")
	assert_true(result, "Intercessors (U_INTERCESSORS_A) should have Pistol weapons")

func test_unit_has_pistol_weapons_ork_boyz():
	"""Test that Ork Boyz unit has Pistol weapons (slugga)"""
	var result = rules_engine.unit_has_pistol_weapons("U_BOYZ_A")
	assert_true(result, "Ork Boyz (U_BOYZ_A) should have Pistol weapons (slugga)")

func test_unit_has_no_pistol_weapons_gretchin():
	"""Test that Gretchin unit does NOT have Pistol weapons"""
	var result = rules_engine.unit_has_pistol_weapons("U_GRETCHIN_A")
	assert_false(result, "Gretchin should NOT have Pistol weapons")

func test_unit_has_pistol_weapons_unknown_unit():
	"""Test that unknown unit returns false"""
	var result = rules_engine.unit_has_pistol_weapons("NONEXISTENT_UNIT")
	assert_false(result, "Unknown unit should return false")

# ==========================================
# get_unit_pistol_weapons() Tests
# ==========================================

func test_get_unit_pistol_weapons_intercessors():
	"""Test that we can get the pistol weapons for Intercessors"""
	var weapons = rules_engine.get_unit_pistol_weapons("U_INTERCESSORS_A")
	assert_false(weapons.is_empty(), "Intercessors should have pistol weapons")
	# The sergeant (m5) should have plasma_pistol
	var has_pistol = false
	for model_id in weapons:
		for weapon_id in weapons[model_id]:
			if weapon_id == "plasma_pistol":
				has_pistol = true
				break
	assert_true(has_pistol, "Should find plasma_pistol in Intercessors weapons")

func test_get_unit_pistol_weapons_gretchin_empty():
	"""Test that Gretchin have no pistol weapons"""
	var weapons = rules_engine.get_unit_pistol_weapons("U_GRETCHIN_A")
	assert_true(weapons.is_empty(), "Gretchin should have no pistol weapons")

# ==========================================
# Pistol + Other Keywords Tests
# ==========================================

func test_slugga_has_both_pistol_and_assault():
	"""Test that slugga has both PISTOL and ASSAULT keywords"""
	var is_pistol = rules_engine.is_pistol_weapon("slugga")
	var is_assault = rules_engine.is_assault_weapon("slugga")
	assert_true(is_pistol, "slugga should be a Pistol weapon")
	assert_true(is_assault, "slugga should also be an Assault weapon")

# ==========================================
# Pistol Mutual Exclusivity Tests (T2-5)
# Per 10e: "If a model is equipped with one or more Pistols, unless it is a
# MONSTER or VEHICLE model, it can either shoot with its Pistols or with all
# of its other ranged weapons."
# ==========================================

func _create_pistol_exclusivity_board(actor_keywords: Array = ["INFANTRY"]) -> Dictionary:
	"""Helper: create a board with a unit that has both Pistol and non-Pistol weapons"""
	return {
		"units": {
			"shooter": {
				"owner": 1,
				"meta": {
					"name": "Test Shooter",
					"keywords": actor_keywords,
					"stats": {"toughness": 4, "save": 3, "wounds": 2},
					"weapons": [
						{
							"name": "Bolt Rifle",
							"type": "Ranged",
							"range": "24",
							"attacks": "2",
							"ballistic_skill": "3",
							"strength": "4",
							"ap": "-1",
							"damage": "1",
							"special_rules": ""
						},
						{
							"name": "Plasma Pistol",
							"type": "Ranged",
							"range": "12",
							"attacks": "1",
							"ballistic_skill": "3",
							"strength": "7",
							"ap": "-2",
							"damage": "1",
							"special_rules": "pistol"
						}
					]
				},
				"models": [
					{"id": "m1", "alive": true, "wounds_current": 2, "wounds_max": 2, "position": {"x": 100, "y": 100}, "base_size_mm": 32}
				],
				"flags": {}
			},
			"target": {
				"owner": 2,
				"meta": {
					"name": "Enemy Target",
					"keywords": ["INFANTRY"],
					"stats": {"toughness": 4, "save": 4, "wounds": 1},
					"weapons": []
				},
				"models": [
					{"id": "t1", "alive": true, "wounds_current": 1, "wounds_max": 1, "position": {"x": 200, "y": 100}, "base_size_mm": 32}
				],
				"flags": {}
			}
		}
	}

func test_pistol_exclusivity_rejects_pistol_and_non_pistol_together():
	"""Test that validate_shoot rejects mixing Pistol and non-Pistol weapons"""
	var board = _create_pistol_exclusivity_board()
	var action = {
		"actor_unit_id": "shooter",
		"payload": {
			"assignments": [
				{"weapon_id": "plasma_pistol", "target_unit_id": "target", "model_ids": ["m1"]},
				{"weapon_id": "bolt_rifle", "target_unit_id": "target", "model_ids": ["m1"]}
			]
		}
	}
	var result = rules_engine.validate_shoot(action, board)
	assert_false(result.valid, "Should reject mixing Pistol and non-Pistol weapons")
	var has_exclusivity_error = false
	for error in result.errors:
		if "Pistol" in error and "non-Pistol" in error:
			has_exclusivity_error = true
			break
	assert_true(has_exclusivity_error, "Error should mention Pistol mutual exclusivity")

func test_pistol_exclusivity_allows_only_pistol_weapons():
	"""Test that validate_shoot allows using only Pistol weapons"""
	var board = _create_pistol_exclusivity_board()
	var action = {
		"actor_unit_id": "shooter",
		"payload": {
			"assignments": [
				{"weapon_id": "plasma_pistol", "target_unit_id": "target", "model_ids": ["m1"]}
			]
		}
	}
	var result = rules_engine.validate_shoot(action, board)
	# Should not have a pistol exclusivity error (may have other errors like range)
	var has_exclusivity_error = false
	for error in result.get("errors", []):
		if "Pistol" in error and "non-Pistol" in error:
			has_exclusivity_error = true
			break
	assert_false(has_exclusivity_error, "Should NOT have pistol exclusivity error when using only Pistol weapons")

func test_pistol_exclusivity_allows_only_non_pistol_weapons():
	"""Test that validate_shoot allows using only non-Pistol weapons"""
	var board = _create_pistol_exclusivity_board()
	var action = {
		"actor_unit_id": "shooter",
		"payload": {
			"assignments": [
				{"weapon_id": "bolt_rifle", "target_unit_id": "target", "model_ids": ["m1"]}
			]
		}
	}
	var result = rules_engine.validate_shoot(action, board)
	var has_exclusivity_error = false
	for error in result.get("errors", []):
		if "Pistol" in error and "non-Pistol" in error:
			has_exclusivity_error = true
			break
	assert_false(has_exclusivity_error, "Should NOT have pistol exclusivity error when using only non-Pistol weapons")

func test_pistol_exclusivity_monster_vehicle_exempt():
	"""Test that MONSTER/VEHICLE units are exempt from pistol mutual exclusivity"""
	var board = _create_pistol_exclusivity_board(["MONSTER", "INFANTRY"])
	var action = {
		"actor_unit_id": "shooter",
		"payload": {
			"assignments": [
				{"weapon_id": "plasma_pistol", "target_unit_id": "target", "model_ids": ["m1"]},
				{"weapon_id": "bolt_rifle", "target_unit_id": "target", "model_ids": ["m1"]}
			]
		}
	}
	var result = rules_engine.validate_shoot(action, board)
	var has_exclusivity_error = false
	for error in result.get("errors", []):
		if "Pistol" in error and "non-Pistol" in error:
			has_exclusivity_error = true
			break
	assert_false(has_exclusivity_error, "MONSTER should be exempt from pistol mutual exclusivity")

func test_pistol_exclusivity_vehicle_exempt():
	"""Test that VEHICLE units are exempt from pistol mutual exclusivity"""
	var board = _create_pistol_exclusivity_board(["VEHICLE"])
	var action = {
		"actor_unit_id": "shooter",
		"payload": {
			"assignments": [
				{"weapon_id": "plasma_pistol", "target_unit_id": "target", "model_ids": ["m1"]},
				{"weapon_id": "bolt_rifle", "target_unit_id": "target", "model_ids": ["m1"]}
			]
		}
	}
	var result = rules_engine.validate_shoot(action, board)
	var has_exclusivity_error = false
	for error in result.get("errors", []):
		if "Pistol" in error and "non-Pistol" in error:
			has_exclusivity_error = true
			break
	assert_false(has_exclusivity_error, "VEHICLE should be exempt from pistol mutual exclusivity")

func test_pistol_exclusivity_multiple_pistols_allowed():
	"""Test that using multiple different Pistol weapons is allowed"""
	var board = _create_pistol_exclusivity_board()
	var action = {
		"actor_unit_id": "shooter",
		"payload": {
			"assignments": [
				{"weapon_id": "plasma_pistol", "target_unit_id": "target", "model_ids": ["m1"]},
				{"weapon_id": "slugga", "target_unit_id": "target", "model_ids": ["m1"]}
			]
		}
	}
	var result = rules_engine.validate_shoot(action, board)
	var has_exclusivity_error = false
	for error in result.get("errors", []):
		if "Pistol" in error and "non-Pistol" in error:
			has_exclusivity_error = true
			break
	assert_false(has_exclusivity_error, "Multiple Pistol weapons should be allowed together")
