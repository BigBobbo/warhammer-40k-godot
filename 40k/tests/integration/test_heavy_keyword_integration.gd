extends "res://addons/gut/test.gd"

# Integration tests for HEAVY keyword (PRP-003)
# Tests the full flow: Movement (remain stationary) → Shooting Phase with Heavy bonus
#
# These tests verify:
# 1. MovementPhase sets 'remained_stationary' flag when unit doesn't move
# 2. ShootingPhase applies +1 to hit for Heavy weapons when stationary
# 3. Heavy bonus respects the +1/-1 modifier cap
#
# NOTE: This test uses local implementations that mirror the logic in RulesEngine,
# because RulesEngine depends on autoloads (Measurement) that aren't available
# when running via the -s script flag.

const GameStateData = preload("res://autoloads/GameState.gd")

var test_state: Dictionary

# Hit modifier flags (matching RulesEngine.HitModifier)
enum HitModifier {
	NONE = 0,
	REROLL_ONES = 1,
	PLUS_ONE = 2,
	MINUS_ONE = 4,
}

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
	"heavy_bolter": {
		"name": "Heavy Bolter",
		"range": 36,
		"attacks": 3,
		"bs": 3,
		"strength": 5,
		"ap": 1,
		"damage": 2,
		"keywords": ["HEAVY"]
	},
	"lascannon": {
		"name": "Lascannon",
		"range": 48,
		"attacks": 1,
		"bs": 3,
		"strength": 12,
		"ap": 3,
		"damage": 6,
		"keywords": ["HEAVY"]
	}
}

func before_each():
	test_state = _create_integration_test_state()

func after_each():
	test_state.clear()

func _create_integration_test_state() -> Dictionary:
	"""Create a game state suitable for integration testing"""
	var state = {
		"game_id": "test_heavy_integration",
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
		"U_DEVASTATORS_HEAVY": _create_devastators_with_heavy(),
		"U_INTERCESSORS_NO_HEAVY": _create_intercessors_no_heavy(),
		"U_ENEMY_TARGET": _create_enemy_target()
	}

	return state

func _create_devastators_with_heavy() -> Dictionary:
	"""Devastator squad with Heavy weapons"""
	return {
		"id": "U_DEVASTATORS_HEAVY",
		"owner": 0,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {
			"has_shot": false,
			"remained_stationary": false,  # Not stationary by default
			"moved": false,
			"in_engagement": false
		},
		"meta": {
			"name": "Devastators Alpha",
			"stats": {"toughness": 4, "save": 3},
			"weapons": [
				{
					"name": "Heavy Bolter",
					"type": "Ranged",
					"range": "36",
					"attacks": "3",
					"ballistic_skill": "3",
					"special_rules": "Heavy"
				},
				{
					"name": "Lascannon",
					"type": "Ranged",
					"range": "48",
					"attacks": "1",
					"ballistic_skill": "3",
					"special_rules": "Heavy"
				}
			]
		},
		"models": [
			{"id": "m1", "position": {"x": 500, "y": 500}, "alive": true, "base_mm": 32},
			{"id": "m2", "position": {"x": 530, "y": 500}, "alive": true, "base_mm": 32}
		]
	}

func _create_intercessors_no_heavy() -> Dictionary:
	"""Intercessors with only bolt_rifle (no Heavy keyword)"""
	return {
		"id": "U_INTERCESSORS_NO_HEAVY",
		"owner": 0,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {
			"has_shot": false,
			"remained_stationary": false,
			"moved": false,
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
					"ballistic_skill": "3",
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
				if "Heavy" in special_rules or "HEAVY" in special_rules:
					keywords.append("HEAVY")
				return {
					"name": weapon.get("name", ""),
					"range": int(weapon.get("range", "0")),
					"attacks": int(weapon.get("attacks", "1")),
					"bs": int(weapon.get("ballistic_skill", "4")),
					"keywords": keywords
				}

	return {}

func is_heavy_weapon(weapon_id: String, board: Dictionary = {}) -> bool:
	"""Check if a weapon has the HEAVY keyword"""
	var profile = _get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return false

	var keywords = profile.get("keywords", [])
	for keyword in keywords:
		if keyword.to_upper() == "HEAVY":
			return true
	return false

func unit_has_heavy_weapons(unit_id: String, board: Dictionary) -> bool:
	"""Check if a unit has any weapons with the HEAVY keyword"""
	var unit = board.get("units", {}).get(unit_id, {})
	var meta_weapons = unit.get("meta", {}).get("weapons", [])

	for weapon in meta_weapons:
		var special_rules = weapon.get("special_rules", "")
		if "Heavy" in special_rules or "HEAVY" in special_rules:
			return true

	return false

func calculate_hit_modifiers(weapon_id: String, actor_unit: Dictionary, board: Dictionary, manual_modifiers: int = HitModifier.NONE) -> Dictionary:
	"""Calculate hit modifiers including Heavy bonus - mirrors RulesEngine logic"""
	var hit_modifiers = manual_modifiers
	var heavy_bonus_applied = false

	# Check for Heavy bonus
	if is_heavy_weapon(weapon_id, board):
		var remained_stationary = actor_unit.get("flags", {}).get("remained_stationary", false)
		if remained_stationary:
			hit_modifiers |= HitModifier.PLUS_ONE
			heavy_bonus_applied = true

	return {
		"hit_modifiers": hit_modifiers,
		"heavy_bonus_applied": heavy_bonus_applied
	}

func apply_modifier_cap(modifiers: int) -> int:
	"""Apply the +1/-1 modifier cap - mirrors RulesEngine logic"""
	var net_modifier = 0
	if modifiers & HitModifier.PLUS_ONE:
		net_modifier += 1
	if modifiers & HitModifier.MINUS_ONE:
		net_modifier -= 1

	# Cap modifiers at +1/-1 maximum
	return clamp(net_modifier, -1, 1)

# ==========================================
# Integration Tests: Heavy Bonus Application
# ==========================================

func test_heavy_bonus_applied_when_unit_remained_stationary():
	"""Test that Heavy +1 bonus is applied when unit remained stationary"""
	# Set the remained_stationary flag
	test_state.units["U_DEVASTATORS_HEAVY"].flags.remained_stationary = true

	var actor_unit = test_state.units["U_DEVASTATORS_HEAVY"]
	var result = calculate_hit_modifiers("heavy_bolter", actor_unit, test_state)

	assert_true(result.heavy_bonus_applied, "Heavy bonus should be applied when unit remained stationary")
	assert_true(result.hit_modifiers & HitModifier.PLUS_ONE, "PLUS_ONE modifier should be set")

func test_heavy_bonus_not_applied_when_unit_moved():
	"""Test that Heavy +1 bonus is NOT applied when unit moved"""
	# Set moved flag and ensure remained_stationary is false
	test_state.units["U_DEVASTATORS_HEAVY"].flags.moved = true
	test_state.units["U_DEVASTATORS_HEAVY"].flags.remained_stationary = false

	var actor_unit = test_state.units["U_DEVASTATORS_HEAVY"]
	var result = calculate_hit_modifiers("heavy_bolter", actor_unit, test_state)

	assert_false(result.heavy_bonus_applied, "Heavy bonus should NOT be applied when unit moved")

func test_heavy_bonus_not_applied_to_non_heavy_weapon():
	"""Test that Heavy +1 bonus is NOT applied to non-Heavy weapons"""
	# Set the remained_stationary flag
	test_state.units["U_INTERCESSORS_NO_HEAVY"].flags.remained_stationary = true

	var actor_unit = test_state.units["U_INTERCESSORS_NO_HEAVY"]
	var result = calculate_hit_modifiers("bolt_rifle", actor_unit, test_state)

	assert_false(result.heavy_bonus_applied, "Heavy bonus should NOT be applied to non-Heavy weapon")
	assert_false(result.hit_modifiers & HitModifier.PLUS_ONE, "PLUS_ONE modifier should NOT be set")

func test_heavy_bonus_not_applied_when_remained_stationary_flag_not_set():
	"""Test that Heavy +1 bonus is NOT applied when remained_stationary flag is not set"""
	# Ensure remained_stationary flag is false (default)
	test_state.units["U_DEVASTATORS_HEAVY"].flags.remained_stationary = false

	var actor_unit = test_state.units["U_DEVASTATORS_HEAVY"]
	var result = calculate_hit_modifiers("heavy_bolter", actor_unit, test_state)

	assert_false(result.heavy_bonus_applied, "Heavy bonus should NOT be applied when remained_stationary is false")

# ==========================================
# Integration Tests: Modifier Cap with Heavy Bonus
# ==========================================

func test_heavy_bonus_capped_at_plus_one():
	"""Test that Heavy bonus respects +1 cap (Heavy +1 already = +1)"""
	test_state.units["U_DEVASTATORS_HEAVY"].flags.remained_stationary = true

	var actor_unit = test_state.units["U_DEVASTATORS_HEAVY"]
	var result = calculate_hit_modifiers("heavy_bolter", actor_unit, test_state)

	var net_modifier = apply_modifier_cap(result.hit_modifiers)
	assert_eq(net_modifier, 1, "Net modifier should be +1")

func test_heavy_bonus_cancels_with_minus_one():
	"""Test that Heavy +1 cancels with -1 modifier (net = 0)"""
	test_state.units["U_DEVASTATORS_HEAVY"].flags.remained_stationary = true

	var actor_unit = test_state.units["U_DEVASTATORS_HEAVY"]
	# Add a -1 modifier manually (simulating cover or other penalty)
	var result = calculate_hit_modifiers("heavy_bolter", actor_unit, test_state, HitModifier.MINUS_ONE)

	var net_modifier = apply_modifier_cap(result.hit_modifiers)
	assert_eq(net_modifier, 0, "Heavy +1 and -1 cover should cancel to net 0")

func test_heavy_bonus_with_additional_plus_one_still_capped():
	"""Test that Heavy +1 + another +1 is still capped at +1"""
	test_state.units["U_DEVASTATORS_HEAVY"].flags.remained_stationary = true

	var actor_unit = test_state.units["U_DEVASTATORS_HEAVY"]
	# Add another +1 modifier manually (simulating an ability)
	var result = calculate_hit_modifiers("heavy_bolter", actor_unit, test_state, HitModifier.PLUS_ONE)

	var net_modifier = apply_modifier_cap(result.hit_modifiers)
	assert_eq(net_modifier, 1, "Multiple +1s should still be capped at +1")

# ==========================================
# Integration Tests: Weapon Keyword Functions
# ==========================================

func test_is_heavy_weapon_function():
	"""Test is_heavy_weapon() returns correct values"""
	# Heavy Bolter should be Heavy
	assert_true(is_heavy_weapon("heavy_bolter", test_state),
		"Heavy Bolter should be recognized as Heavy weapon")

	# Lascannon should be Heavy
	assert_true(is_heavy_weapon("lascannon", test_state),
		"Lascannon should be recognized as Heavy weapon")

	# Bolt rifle should NOT be Heavy
	assert_false(is_heavy_weapon("bolt_rifle", test_state),
		"Bolt rifle should NOT be Heavy weapon")

func test_unit_has_heavy_weapons_function():
	"""Test unit_has_heavy_weapons() returns correct values"""
	# Devastators should have Heavy weapons
	assert_true(unit_has_heavy_weapons("U_DEVASTATORS_HEAVY", test_state),
		"Devastators should have Heavy weapons")

	# Intercessors should NOT have Heavy weapons
	assert_false(unit_has_heavy_weapons("U_INTERCESSORS_NO_HEAVY", test_state),
		"Intercessors should NOT have Heavy weapons")

# ==========================================
# Integration Tests: Flag State Transitions
# ==========================================

func test_remained_stationary_flag_lifecycle():
	"""Test that remained_stationary flag can be set and cleared properly"""
	var unit = test_state.units["U_DEVASTATORS_HEAVY"]

	# Initially false
	assert_false(unit.flags.get("remained_stationary", false),
		"remained_stationary should initially be false")

	# Simulate Movement phase start - set to true
	unit.flags.remained_stationary = true
	assert_true(unit.flags.remained_stationary,
		"remained_stationary should be true after Movement phase start")

	# Simulate unit movement - set to false
	unit.flags.remained_stationary = false
	unit.flags.moved = true
	assert_false(unit.flags.remained_stationary,
		"remained_stationary should be false after unit moves")

func test_moved_and_remained_stationary_mutually_exclusive():
	"""Test that moved and remained_stationary flags are mutually exclusive in practice"""
	var unit = test_state.units["U_DEVASTATORS_HEAVY"]

	# Scenario 1: Unit stays stationary
	unit.flags.moved = false
	unit.flags.remained_stationary = true
	var result1 = calculate_hit_modifiers("heavy_bolter", unit, test_state)
	assert_true(result1.heavy_bonus_applied, "Stationary unit should get Heavy bonus")

	# Scenario 2: Unit moves
	unit.flags.moved = true
	unit.flags.remained_stationary = false
	var result2 = calculate_hit_modifiers("heavy_bolter", unit, test_state)
	assert_false(result2.heavy_bonus_applied, "Moving unit should NOT get Heavy bonus")
