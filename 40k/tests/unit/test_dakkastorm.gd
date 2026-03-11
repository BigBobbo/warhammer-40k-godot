extends "res://addons/gut/test.gd"

# Tests for the DAKKASTORM ability implementation (OA-16)
#
# Per Warhammer 40k 10th Edition rules (Dakkajet datasheet):
# Each time this model makes a ranged attack, a successful Hit roll
# scores a Critical Hit.
#
# This means:
# - Every successful Hit roll is treated as a Critical Hit for ranged attacks
# - Sustained Hits and Lethal Hits trigger on every successful hit
# - Does NOT apply to melee attacks
#
# These tests verify:
# 1. has_dakkastorm() correctly detects the ability (dict and string formats)
# 2. has_dakkastorm() returns false when ability is absent
# 3. Ability is registered in UnitAbilityManager.ABILITY_EFFECTS with correct properties
# 4. Ability is ranged-only (does not apply to melee)

var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

# ==========================================
# has_dakkastorm() Tests
# ==========================================

func test_has_dakkastorm_dict_format():
	"""Dakkastorm as a dictionary ability should be detected."""
	var unit = {
		"meta": {
			"abilities": [{"name": "Dakkastorm", "type": "Datasheet", "description": "..."}]
		}
	}
	assert_true(rules_engine.has_dakkastorm(unit), "Should detect Dakkastorm as dictionary ability")

func test_has_dakkastorm_string_format():
	"""Dakkastorm as a simple string should be detected."""
	var unit = {
		"meta": {
			"abilities": ["Dakkastorm"]
		}
	}
	assert_true(rules_engine.has_dakkastorm(unit), "Should detect Dakkastorm as string ability")

func test_has_dakkastorm_returns_false_without_ability():
	"""Unit without Dakkastorm should return false."""
	var unit = {
		"meta": {
			"abilities": [{"name": "Ramshackle", "type": "Datasheet"}]
		}
	}
	assert_false(rules_engine.has_dakkastorm(unit), "Should not detect Dakkastorm when absent")

func test_has_dakkastorm_returns_false_empty_abilities():
	"""Unit with empty abilities should return false."""
	var unit = {"meta": {"abilities": []}}
	assert_false(rules_engine.has_dakkastorm(unit), "Should return false for empty abilities")

func test_has_dakkastorm_returns_false_no_meta():
	"""Unit with no meta should return false."""
	var unit = {}
	assert_false(rules_engine.has_dakkastorm(unit), "Should return false for unit with no meta")

func test_has_dakkastorm_with_multiple_abilities():
	"""Dakkastorm should be detected among multiple abilities."""
	var unit = {
		"meta": {
			"abilities": [
				{"name": "Deadly Demise D3", "type": "Datasheet"},
				{"name": "Dakkastorm", "type": "Datasheet"},
				"Hover"
			]
		}
	}
	assert_true(rules_engine.has_dakkastorm(unit), "Should detect Dakkastorm among multiple abilities")

func test_has_dakkastorm_wrong_name():
	"""Similar but different ability names should not match."""
	var unit = {
		"meta": {
			"abilities": ["Dakka Storm", "DAKKASTORM", "Dakkastorms"]
		}
	}
	assert_false(rules_engine.has_dakkastorm(unit), "Should not match similar but different names (case-sensitive, exact match)")

# ==========================================
# UnitAbilityManager Registration Tests
# ==========================================

func test_dakkastorm_in_ability_effects():
	"""Dakkastorm should be registered in UnitAbilityManager.ABILITY_EFFECTS."""
	var ability_def = UnitAbilityManager.ABILITY_EFFECTS.get("Dakkastorm", {})
	assert_false(ability_def.is_empty(), "Dakkastorm must exist in ABILITY_EFFECTS")
	assert_true(ability_def.get("implemented", false), "Dakkastorm must be marked as implemented")
	assert_eq(ability_def.get("attack_type", ""), "ranged", "Dakkastorm must be ranged only")
	assert_eq(ability_def.get("condition", ""), "always", "Dakkastorm should be always-on")

func test_dakkastorm_effects_definition():
	"""Dakkastorm effect should be all_hits_critical."""
	var ability_def = UnitAbilityManager.ABILITY_EFFECTS.get("Dakkastorm", {})
	var effects = ability_def.get("effects", [])
	assert_eq(effects.size(), 1, "Should have exactly one effect")
	assert_eq(effects[0].get("type", ""), "all_hits_critical", "Effect type should be all_hits_critical")

func test_dakkastorm_is_ranged_only():
	"""Dakkastorm should explicitly be ranged-only, not applying to melee."""
	var ability_def = UnitAbilityManager.ABILITY_EFFECTS.get("Dakkastorm", {})
	assert_eq(ability_def.get("attack_type", ""), "ranged", "Dakkastorm must be ranged only — should NOT apply to melee attacks")
