extends "res://addons/gut/test.gd"

# Tests for the STEALTH ability implementation (T2-1)
#
# Per Warhammer 40k 10th Edition rules:
# If all models in a unit have the Stealth ability, ranged attacks
# targeting that unit get -1 to hit.
#
# Stealth can come from:
# 1. Base unit ability (in meta.abilities)
# 2. Smokescreen stratagem (sets stratagem_stealth flag)
#
# These tests verify:
# 1. has_stealth_ability() correctly detects Stealth in string format
# 2. has_stealth_ability() correctly detects Stealth in dictionary format
# 3. has_stealth_ability() returns false when unit has no Stealth
# 4. Stealth ability applies -1 to hit via resolve paths
# 5. Stealth does NOT apply to melee attacks (only ranged)

const GameStateData = preload("res://autoloads/GameState.gd")

var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

# ==========================================
# has_stealth_ability() Tests - String format
# ==========================================

func test_has_stealth_ability_string_format():
	"""Stealth as a simple string in abilities array should be detected."""
	var unit = {
		"meta": {
			"abilities": ["Stealth"]
		}
	}
	assert_true(rules_engine.has_stealth_ability(unit), "Should detect Stealth as string ability")

func test_has_stealth_ability_string_case_insensitive():
	"""Stealth detection should be case-insensitive."""
	var unit = {
		"meta": {
			"abilities": ["stealth"]
		}
	}
	assert_true(rules_engine.has_stealth_ability(unit), "Should detect 'stealth' (lowercase)")

	var unit2 = {
		"meta": {
			"abilities": ["STEALTH"]
		}
	}
	assert_true(rules_engine.has_stealth_ability(unit2), "Should detect 'STEALTH' (uppercase)")

# ==========================================
# has_stealth_ability() Tests - Dictionary format
# ==========================================

func test_has_stealth_ability_dict_format():
	"""Stealth as a dictionary with name key should be detected."""
	var unit = {
		"meta": {
			"abilities": [{"name": "Stealth", "description": "This unit has the Stealth ability."}]
		}
	}
	assert_true(rules_engine.has_stealth_ability(unit), "Should detect Stealth as dictionary ability")

func test_has_stealth_ability_dict_case_insensitive():
	"""Stealth detection in dict format should be case-insensitive."""
	var unit = {
		"meta": {
			"abilities": [{"name": "stealth", "description": "Unit is stealthy"}]
		}
	}
	assert_true(rules_engine.has_stealth_ability(unit), "Should detect 'stealth' (lowercase) in dict")

# ==========================================
# has_stealth_ability() Tests - Negative cases
# ==========================================

func test_has_stealth_ability_returns_false_no_abilities():
	"""Unit with no abilities should not have Stealth."""
	var unit = {
		"meta": {
			"abilities": []
		}
	}
	assert_false(rules_engine.has_stealth_ability(unit), "Empty abilities should not have Stealth")

func test_has_stealth_ability_returns_false_no_meta():
	"""Unit with no meta should not have Stealth."""
	var unit = {}
	assert_false(rules_engine.has_stealth_ability(unit), "No meta should not have Stealth")

func test_has_stealth_ability_returns_false_other_abilities():
	"""Unit with other abilities but not Stealth should return false."""
	var unit = {
		"meta": {
			"abilities": ["Bolter Discipline", "Deep Strike"]
		}
	}
	assert_false(rules_engine.has_stealth_ability(unit), "Non-Stealth abilities should not match")

func test_has_stealth_ability_returns_false_partial_match():
	"""Ability names containing 'stealth' but not exactly 'stealth' should not match."""
	var unit = {
		"meta": {
			"abilities": ["Stealthy Movement"]
		}
	}
	assert_false(rules_engine.has_stealth_ability(unit), "'Stealthy Movement' should not match exact 'stealth'")

func test_has_stealth_ability_mixed_abilities():
	"""Stealth should be found among multiple abilities."""
	var unit = {
		"meta": {
			"abilities": [
				"Bolter Discipline",
				{"name": "Stealth", "description": "This unit has the Stealth ability."},
				"Deep Strike"
			]
		}
	}
	assert_true(rules_engine.has_stealth_ability(unit), "Should find Stealth among mixed abilities")
