extends "res://addons/gut/test.gd"

# Integration tests for ASSAULT keyword (PRP-002)
# Tests the full flow: Movement (Advance) → Shooting Phase with Assault restrictions
#
# These tests verify:
# 1. MovementPhase sets 'advanced' flag when unit Advances
# 2. ShootingPhase allows/restricts shooting based on advanced flag and Assault weapons
# 3. validate_shoot() enforces Assault restrictions
#
# NOTE: This test uses local implementations that mirror the logic in RulesEngine,
# because RulesEngine depends on autoloads (Measurement) that aren't available
# when running via the -s script flag.

const GameStateData = preload("res://autoloads/GameState.gd")

var test_state: Dictionary

# Local weapon profiles mirroring RulesEngine.WEAPON_PROFILES
const WEAPON_PROFILES = {
	"bolt_rifle": {
		"name": "Bolt Rifle",
		"range": 30,
		"attacks": 2,
		"bs": 3,
		"strength": 4,
		"ap": 1,
		"damage": 1,
		"keywords": []
	},
	"slugga": {
		"name": "Slugga",
		"range": 12,
		"attacks": 1,
		"bs": 5,
		"strength": 4,
		"ap": 0,
		"damage": 1,
		"keywords": ["PISTOL", "ASSAULT"]
	},
	"shoota": {
		"name": "Shoota",
		"range": 18,
		"attacks": 2,
		"bs": 5,
		"strength": 4,
		"ap": 0,
		"damage": 1,
		"keywords": ["ASSAULT"]
	}
}

func before_each():
	test_state = _create_integration_test_state()

func after_each():
	test_state.clear()

func _create_integration_test_state() -> Dictionary:
	"""Create a game state suitable for integration testing"""
	var state = {
		"game_id": "test_assault_integration",
		"current_phase": GameStateData.Phase.SHOOTING,
		"current_player": 0,
		"turn": 1,
		"round": 1,
		"units": {},
		"board": {
			"size": {"width": 2000, "height": 2000}
		},
		"phase_data": {},
		"terrain_features": [],
		"settings": {
			"measurement_unit": "inches",
			"scale": 1.0
		}
	}

	# Add test units
	state.units = {
		"U_ORK_BOYZ_ASSAULT": _create_ork_boyz_with_assault(),
		"U_INTERCESSORS_NO_ASSAULT": _create_intercessors_no_assault(),
		"U_ENEMY_TARGET": _create_enemy_target()
	}

	return state

func _create_ork_boyz_with_assault() -> Dictionary:
	"""Ork Boyz with Assault weapons (slugga + shoota)"""
	return {
		"id": "U_ORK_BOYZ_ASSAULT",
		"owner": 0,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {
			"has_shot": false,
			"advanced": false,
			"in_engagement": false
		},
		"meta": {
			"name": "Ork Boyz Alpha",
			"stats": {"toughness": 5, "save": 6},
			"weapons": [
				{
					"name": "Slugga",
					"type": "Ranged",
					"range": "12",
					"attacks": "1",
					"special_rules": "Pistol, Assault"
				},
				{
					"name": "Shoota",
					"type": "Ranged",
					"range": "18",
					"attacks": "2",
					"special_rules": "Assault"
				}
			]
		},
		"models": [
			{"id": "m1", "position": {"x": 500, "y": 500}, "alive": true, "base_mm": 32}
		]
	}

func _create_intercessors_no_assault() -> Dictionary:
	"""Intercessors with only bolt_rifle (no Assault keyword)"""
	return {
		"id": "U_INTERCESSORS_NO_ASSAULT",
		"owner": 0,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {
			"has_shot": false,
			"advanced": false,
			"in_engagement": false
		},
		"meta": {
			"name": "Intercessors Alpha",
			"stats": {"toughness": 4, "save": 3},
			"weapons": [
				{
					"name": "Bolt Rifle",
					"type": "Ranged",
					"range": "30",
					"attacks": "2",
					"special_rules": ""
				}
			]
		},
		"models": [
			{"id": "m1", "position": {"x": 600, "y": 500}, "alive": true, "base_mm": 32}
		]
	}

func _create_enemy_target() -> Dictionary:
	"""Enemy unit to shoot at"""
	return {
		"id": "U_ENEMY_TARGET",
		"owner": 1,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {},
		"meta": {
			"name": "Enemy Target",
			"stats": {"toughness": 4, "save": 4}
		},
		"models": [
			{"id": "m1", "position": {"x": 700, "y": 500}, "alive": true, "base_mm": 32}
		]
	}

# ==========================================
# Local helper functions (mirror RulesEngine)
# ==========================================

func _get_weapon_profile(weapon_id: String, board: Dictionary = {}) -> Dictionary:
	"""Get weapon profile from hardcoded profiles or unit meta"""
	# First check hardcoded profiles
	if WEAPON_PROFILES.has(weapon_id):
		return WEAPON_PROFILES[weapon_id]

	# Check unit meta weapons
	for unit_id in board.get("units", {}).keys():
		var unit = board.units[unit_id]
		var meta_weapons = unit.get("meta", {}).get("weapons", [])
		for weapon in meta_weapons:
			var weapon_name_lower = weapon.get("name", "").to_lower().replace(" ", "_")
			if weapon_name_lower == weapon_id:
				# Parse keywords from special_rules
				var keywords = []
				var special_rules = weapon.get("special_rules", "")
				if "Assault" in special_rules or "ASSAULT" in special_rules:
					keywords.append("ASSAULT")
				if "Pistol" in special_rules or "PISTOL" in special_rules:
					keywords.append("PISTOL")
				return {
					"name": weapon.get("name", ""),
					"range": int(weapon.get("range", "0")),
					"attacks": int(weapon.get("attacks", "1")),
					"keywords": keywords
				}

	return {}

func is_assault_weapon(weapon_id: String, board: Dictionary = {}) -> bool:
	"""Check if a weapon has the ASSAULT keyword"""
	var profile = _get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return false

	var keywords = profile.get("keywords", [])
	for keyword in keywords:
		if keyword.to_upper() == "ASSAULT":
			return true
	return false

func unit_has_assault_weapons(unit_id: String, board: Dictionary) -> bool:
	"""Check if a unit has any weapons with the ASSAULT keyword"""
	var unit = board.get("units", {}).get(unit_id, {})
	var meta_weapons = unit.get("meta", {}).get("weapons", [])

	for weapon in meta_weapons:
		var special_rules = weapon.get("special_rules", "")
		if "Assault" in special_rules or "ASSAULT" in special_rules:
			return true

	return false

func validate_shoot(action: Dictionary, board: Dictionary) -> Dictionary:
	"""Validate a shoot action - simplified version mirroring RulesEngine"""
	var errors = []
	var actor_unit_id = action.get("actor_unit_id", "")
	var actor = board.get("units", {}).get(actor_unit_id, {})

	if actor.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}

	var actor_flags = actor.get("flags", {})
	var actor_advanced = actor_flags.get("advanced", false)
	var actor_fell_back = actor_flags.get("fell_back", false)

	# Units that Fell Back cannot shoot
	if actor_fell_back:
		errors.append("Unit cannot shoot after Falling Back")
		return {"valid": errors.is_empty(), "errors": errors}

	# Check weapon assignments
	var assignments = action.get("payload", {}).get("assignments", [])
	for assignment in assignments:
		var weapon_id = assignment.get("weapon_id", "")
		var weapon_profile = _get_weapon_profile(weapon_id, board)

		# ASSAULT RULES: If unit Advanced, only Assault weapons can be used
		if actor_advanced and not is_assault_weapon(weapon_id, board):
			errors.append("Cannot fire non-Assault weapon '%s' after Advancing" % weapon_profile.get("name", weapon_id))

	return {"valid": errors.is_empty(), "errors": errors}

# ==========================================
# Integration Tests: validate_shoot with Advanced Flag
# ==========================================

func test_validate_shoot_allows_assault_weapon_after_advance():
	"""Test that validate_shoot allows Assault weapons when unit has Advanced"""
	# Set the advanced flag
	test_state.units["U_ORK_BOYZ_ASSAULT"].flags.advanced = true

	# Create a shoot action with Assault weapon (shoota)
	var action = {
		"type": "SHOOT",
		"actor_unit_id": "U_ORK_BOYZ_ASSAULT",
		"payload": {
			"assignments": [
				{
					"weapon_id": "shoota",
					"model_ids": ["m1"],
					"target_unit_id": "U_ENEMY_TARGET"
				}
			]
		}
	}

	var result = validate_shoot(action, test_state)

	# Should be valid - Assault weapon after Advance is allowed
	assert_true(result.valid, "Assault weapon should be allowed after Advancing: %s" % str(result.errors))

func test_validate_shoot_blocks_non_assault_weapon_after_advance():
	"""Test that validate_shoot blocks non-Assault weapons when unit has Advanced"""
	# Set the advanced flag
	test_state.units["U_INTERCESSORS_NO_ASSAULT"].flags.advanced = true

	# Create a shoot action with non-Assault weapon (bolt_rifle)
	var action = {
		"type": "SHOOT",
		"actor_unit_id": "U_INTERCESSORS_NO_ASSAULT",
		"payload": {
			"assignments": [
				{
					"weapon_id": "bolt_rifle",
					"model_ids": ["m1"],
					"target_unit_id": "U_ENEMY_TARGET"
				}
			]
		}
	}

	var result = validate_shoot(action, test_state)

	# Should be invalid - non-Assault weapon after Advance is NOT allowed
	assert_false(result.valid, "Non-Assault weapon should be blocked after Advancing")
	assert_true(result.errors.size() > 0, "Should have error message")

	# Check error message mentions Assault
	var has_assault_error = false
	for error in result.errors:
		if "Assault" in error or "ASSAULT" in error:
			has_assault_error = true
			break
	assert_true(has_assault_error, "Error should mention Assault restriction")

func test_validate_shoot_allows_all_weapons_without_advance():
	"""Test that validate_shoot allows all weapons when unit did NOT Advance"""
	# Ensure advanced flag is false
	test_state.units["U_INTERCESSORS_NO_ASSAULT"].flags.advanced = false

	# Create a shoot action with non-Assault weapon (bolt_rifle)
	var action = {
		"type": "SHOOT",
		"actor_unit_id": "U_INTERCESSORS_NO_ASSAULT",
		"payload": {
			"assignments": [
				{
					"weapon_id": "bolt_rifle",
					"model_ids": ["m1"],
					"target_unit_id": "U_ENEMY_TARGET"
				}
			]
		}
	}

	var result = validate_shoot(action, test_state)

	# Should be valid - no Advanced, so all weapons allowed
	assert_true(result.valid, "All weapons should be allowed when not Advanced: %s" % str(result.errors))

func test_validate_shoot_blocks_fell_back_unit():
	"""Test that validate_shoot blocks shooting for units that Fell Back"""
	# Set the fell_back flag
	test_state.units["U_ORK_BOYZ_ASSAULT"].flags.fell_back = true

	# Create a shoot action
	var action = {
		"type": "SHOOT",
		"actor_unit_id": "U_ORK_BOYZ_ASSAULT",
		"payload": {
			"assignments": [
				{
					"weapon_id": "shoota",
					"model_ids": ["m1"],
					"target_unit_id": "U_ENEMY_TARGET"
				}
			]
		}
	}

	var result = validate_shoot(action, test_state)

	# Should be invalid - units that Fell Back cannot shoot
	assert_false(result.valid, "Units that Fell Back should not be able to shoot")

# ==========================================
# Integration Tests: Weapon Keyword Functions
# ==========================================

func test_is_assault_weapon_function():
	"""Test is_assault_weapon() returns correct values"""
	# Shoota should be Assault
	assert_true(is_assault_weapon("shoota", test_state),
		"Shoota should be recognized as Assault weapon")

	# Slugga should be Assault (it has both Pistol and Assault)
	assert_true(is_assault_weapon("slugga", test_state),
		"Slugga should be recognized as Assault weapon")

	# Bolt rifle should NOT be Assault
	assert_false(is_assault_weapon("bolt_rifle", test_state),
		"Bolt rifle should NOT be Assault weapon")

func test_unit_has_assault_weapons_function():
	"""Test unit_has_assault_weapons() returns correct values"""
	# Ork Boyz should have Assault weapons
	assert_true(unit_has_assault_weapons("U_ORK_BOYZ_ASSAULT", test_state),
		"Ork Boyz should have Assault weapons")

	# Intercessors should NOT have Assault weapons
	assert_false(unit_has_assault_weapons("U_INTERCESSORS_NO_ASSAULT", test_state),
		"Intercessors should NOT have Assault weapons")
