extends "res://addons/gut/test.gd"

# Tests for the DA BOSS' LADZ ability implementation (OA-15)
#
# Per Warhammer 40k 10th Edition rules (Nobz datasheet):
# While a Warboss model is leading this unit, each time an attack targets
# this unit, if the Strength of that attack is greater than this unit's
# Toughness, subtract 1 from the Wound roll.
#
# Applies to: Nobz (when led by a Warboss)
#
# These tests verify:
# 1. has_da_boss_ladz() correctly detects the ability
# 2. is_warboss_leading_unit() checks leader attachment correctly
# 3. get_da_boss_ladz_wound_modifier() returns correct modifier
# 4. No effect when S <= T
# 5. No effect when no Warboss attached
# 6. Ability is in UnitAbilityManager.ABILITY_EFFECTS

var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

# ==========================================
# has_da_boss_ladz() Tests
# ==========================================

func test_has_da_boss_ladz_dict_format():
	"""Da Boss' Ladz as a dictionary ability should be detected."""
	var unit = {
		"meta": {
			"abilities": [{"name": "Da Boss' Ladz", "type": "Datasheet", "description": "..."}]
		}
	}
	assert_true(rules_engine.has_da_boss_ladz(unit), "Should detect Da Boss' Ladz as dictionary ability")

func test_has_da_boss_ladz_string_format():
	"""Da Boss' Ladz as a simple string should be detected."""
	var unit = {
		"meta": {
			"abilities": ["Da Boss' Ladz"]
		}
	}
	assert_true(rules_engine.has_da_boss_ladz(unit), "Should detect Da Boss' Ladz as string ability")

func test_has_da_boss_ladz_returns_false_without_ability():
	"""Unit without Da Boss' Ladz should return false."""
	var unit = {
		"meta": {
			"abilities": [{"name": "Ramshackle", "type": "Datasheet"}]
		}
	}
	assert_false(rules_engine.has_da_boss_ladz(unit), "Should not detect Da Boss' Ladz when absent")

func test_has_da_boss_ladz_returns_false_empty_abilities():
	"""Unit with empty abilities should return false."""
	var unit = {"meta": {"abilities": []}}
	assert_false(rules_engine.has_da_boss_ladz(unit), "Should return false for empty abilities")

func test_has_da_boss_ladz_returns_false_no_meta():
	"""Unit with no meta should return false."""
	var unit = {}
	assert_false(rules_engine.has_da_boss_ladz(unit), "Should return false for unit with no meta")

# ==========================================
# is_warboss_leading_unit() Tests
# ==========================================

func _make_warboss_unit(unit_id: String = "U_WARBOSS_A") -> Dictionary:
	"""Helper: create a minimal Warboss unit."""
	return {
		"id": unit_id,
		"meta": {
			"name": "Warboss",
			"keywords": ["CHARACTER", "INFANTRY", "ORKS", "WARBOSS"]
		},
		"models": [
			{"id": "m1", "alive": true, "current_wounds": 6}
		]
	}

func _make_nobz_unit_with_ability(unit_id: String = "U_NOBZ_A", attached: Array = []) -> Dictionary:
	"""Helper: create a minimal Nobz unit with Da Boss' Ladz."""
	var unit = {
		"id": unit_id,
		"meta": {
			"name": "Nobz",
			"keywords": ["INFANTRY", "ORKS", "NOBZ"],
			"abilities": [{"name": "Da Boss' Ladz", "type": "Datasheet"}],
			"stats": {"toughness": 5}
		},
		"models": [
			{"id": "m1", "alive": true, "current_wounds": 2},
			{"id": "m2", "alive": true, "current_wounds": 2}
		]
	}
	if not attached.is_empty():
		unit["attachment_data"] = {"attached_characters": attached}
	return unit

func test_warboss_leading_with_attachment():
	"""Warboss attached to unit should be detected as leading."""
	var board = {
		"units": {
			"U_NOBZ_A": _make_nobz_unit_with_ability("U_NOBZ_A", ["U_WARBOSS_A"]),
			"U_WARBOSS_A": _make_warboss_unit("U_WARBOSS_A")
		}
	}
	var nobz = board.units["U_NOBZ_A"]
	assert_true(rules_engine.is_warboss_leading_unit(nobz, board), "Warboss attached should be detected as leading")

func test_no_attachment_data():
	"""Unit without attachment_data should not have Warboss leading."""
	var nobz = _make_nobz_unit_with_ability("U_NOBZ_A", [])
	var board = {"units": {"U_NOBZ_A": nobz}}
	assert_false(rules_engine.is_warboss_leading_unit(nobz, board), "No attachment should mean no Warboss leading")

func test_non_warboss_leader():
	"""Non-Warboss character leading should not trigger."""
	var mek = {
		"id": "U_MEK_A",
		"meta": {
			"name": "Mek",
			"keywords": ["CHARACTER", "INFANTRY", "ORKS", "MEK"]
		},
		"models": [
			{"id": "m1", "alive": true, "current_wounds": 4}
		]
	}
	var board = {
		"units": {
			"U_NOBZ_A": _make_nobz_unit_with_ability("U_NOBZ_A", ["U_MEK_A"]),
			"U_MEK_A": mek
		}
	}
	var nobz = board.units["U_NOBZ_A"]
	assert_false(rules_engine.is_warboss_leading_unit(nobz, board), "Non-Warboss leader should not trigger")

func test_dead_warboss_not_leading():
	"""Dead Warboss should not count as leading."""
	var dead_warboss = _make_warboss_unit("U_WARBOSS_A")
	dead_warboss.models[0].alive = false
	var board = {
		"units": {
			"U_NOBZ_A": _make_nobz_unit_with_ability("U_NOBZ_A", ["U_WARBOSS_A"]),
			"U_WARBOSS_A": dead_warboss
		}
	}
	var nobz = board.units["U_NOBZ_A"]
	assert_false(rules_engine.is_warboss_leading_unit(nobz, board), "Dead Warboss should not count as leading")

func test_beastboss_counts_as_warboss():
	"""Beastboss has WARBOSS keyword and should count as leading."""
	var beastboss = {
		"id": "U_BEASTBOSS_A",
		"meta": {
			"name": "Beastboss",
			"keywords": ["CHARACTER", "INFANTRY", "ORKS", "BEAST SNAGGA", "BEASTBOSS", "WARBOSS"]
		},
		"models": [
			{"id": "m1", "alive": true, "current_wounds": 6}
		]
	}
	var board = {
		"units": {
			"U_NOBZ_A": _make_nobz_unit_with_ability("U_NOBZ_A", ["U_BEASTBOSS_A"]),
			"U_BEASTBOSS_A": beastboss
		}
	}
	var nobz = board.units["U_NOBZ_A"]
	assert_true(rules_engine.is_warboss_leading_unit(nobz, board), "Beastboss (WARBOSS keyword) should count as leading")

# ==========================================
# get_da_boss_ladz_wound_modifier() Tests
# ==========================================

func test_modifier_when_s_gt_t_and_warboss_leads():
	"""Should return MINUS_ONE when S > T and Warboss is leading."""
	var board = {
		"units": {
			"U_NOBZ_A": _make_nobz_unit_with_ability("U_NOBZ_A", ["U_WARBOSS_A"]),
			"U_WARBOSS_A": _make_warboss_unit("U_WARBOSS_A")
		}
	}
	var nobz = board.units["U_NOBZ_A"]
	# S8 > T5
	var modifier = rules_engine.get_da_boss_ladz_wound_modifier(nobz, board, 8, 5)
	assert_eq(modifier, RulesEngine.WoundModifier.MINUS_ONE, "Should return MINUS_ONE when S > T with Warboss leading")

func test_no_modifier_when_s_equals_t():
	"""Should return NONE when S == T (even with Warboss leading)."""
	var board = {
		"units": {
			"U_NOBZ_A": _make_nobz_unit_with_ability("U_NOBZ_A", ["U_WARBOSS_A"]),
			"U_WARBOSS_A": _make_warboss_unit("U_WARBOSS_A")
		}
	}
	var nobz = board.units["U_NOBZ_A"]
	# S5 == T5
	var modifier = rules_engine.get_da_boss_ladz_wound_modifier(nobz, board, 5, 5)
	assert_eq(modifier, RulesEngine.WoundModifier.NONE, "Should return NONE when S == T")

func test_no_modifier_when_s_lt_t():
	"""Should return NONE when S < T (even with Warboss leading)."""
	var board = {
		"units": {
			"U_NOBZ_A": _make_nobz_unit_with_ability("U_NOBZ_A", ["U_WARBOSS_A"]),
			"U_WARBOSS_A": _make_warboss_unit("U_WARBOSS_A")
		}
	}
	var nobz = board.units["U_NOBZ_A"]
	# S3 < T5
	var modifier = rules_engine.get_da_boss_ladz_wound_modifier(nobz, board, 3, 5)
	assert_eq(modifier, RulesEngine.WoundModifier.NONE, "Should return NONE when S < T")

func test_no_modifier_without_warboss():
	"""Should return NONE when no Warboss is leading (even with S > T)."""
	var mek = {
		"id": "U_MEK_A",
		"meta": {
			"name": "Mek",
			"keywords": ["CHARACTER", "INFANTRY", "ORKS", "MEK"]
		},
		"models": [{"id": "m1", "alive": true, "current_wounds": 4}]
	}
	var board = {
		"units": {
			"U_NOBZ_A": _make_nobz_unit_with_ability("U_NOBZ_A", ["U_MEK_A"]),
			"U_MEK_A": mek
		}
	}
	var nobz = board.units["U_NOBZ_A"]
	# S8 > T5, but no Warboss
	var modifier = rules_engine.get_da_boss_ladz_wound_modifier(nobz, board, 8, 5)
	assert_eq(modifier, RulesEngine.WoundModifier.NONE, "Should return NONE without Warboss leading")

func test_no_modifier_without_ability():
	"""Should return NONE when unit doesn't have the ability."""
	var unit_no_ability = {
		"id": "U_BOYZ_A",
		"meta": {
			"name": "Boyz",
			"keywords": ["INFANTRY", "ORKS"],
			"abilities": [],
			"stats": {"toughness": 5}
		},
		"models": [{"id": "m1", "alive": true}],
		"attachment_data": {"attached_characters": ["U_WARBOSS_A"]}
	}
	var board = {
		"units": {
			"U_BOYZ_A": unit_no_ability,
			"U_WARBOSS_A": _make_warboss_unit("U_WARBOSS_A")
		}
	}
	# S8 > T5 and Warboss leads, but no ability
	var modifier = rules_engine.get_da_boss_ladz_wound_modifier(unit_no_ability, board, 8, 5)
	assert_eq(modifier, RulesEngine.WoundModifier.NONE, "Should return NONE without ability")

func test_no_modifier_no_attachment_at_all():
	"""Should return NONE when unit has ability but no attachment data at all."""
	var nobz = {
		"id": "U_NOBZ_A",
		"meta": {
			"name": "Nobz",
			"keywords": ["INFANTRY", "ORKS", "NOBZ"],
			"abilities": [{"name": "Da Boss' Ladz", "type": "Datasheet"}],
			"stats": {"toughness": 5}
		},
		"models": [{"id": "m1", "alive": true}]
	}
	var board = {"units": {"U_NOBZ_A": nobz}}
	# S8 > T5, has ability, but no attachment
	var modifier = rules_engine.get_da_boss_ladz_wound_modifier(nobz, board, 8, 5)
	assert_eq(modifier, RulesEngine.WoundModifier.NONE, "Should return NONE with no attachment data")

# ==========================================
# UnitAbilityManager Integration Tests
# ==========================================

func test_ability_in_effects_dictionary():
	"""Da Boss' Ladz should be registered in ABILITY_EFFECTS."""
	var effects = UnitAbilityManager.ABILITY_EFFECTS
	assert_true(effects.has("Da Boss' Ladz"), "Da Boss' Ladz should be in ABILITY_EFFECTS")

func test_ability_marked_implemented():
	"""Da Boss' Ladz should be marked as implemented."""
	var effects = UnitAbilityManager.ABILITY_EFFECTS
	var entry = effects.get("Da Boss' Ladz", {})
	assert_true(entry.get("implemented", false), "Da Boss' Ladz should be marked as implemented")

func test_ability_applies_to_all_attack_types():
	"""Da Boss' Ladz should apply to all attack types (ranged and melee)."""
	var effects = UnitAbilityManager.ABILITY_EFFECTS
	var entry = effects.get("Da Boss' Ladz", {})
	assert_eq(entry.get("attack_type", ""), "all", "Da Boss' Ladz should apply to all attack types")

func test_ability_has_minus_one_wound_effect():
	"""Da Boss' Ladz should have minus_one_wound_incoming effect."""
	var effects = UnitAbilityManager.ABILITY_EFFECTS
	var entry = effects.get("Da Boss' Ladz", {})
	var effect_list = entry.get("effects", [])
	assert_true(effect_list.size() > 0, "Should have at least one effect")
	assert_eq(effect_list[0].get("type", ""), "minus_one_wound_incoming", "First effect should be minus_one_wound_incoming")
	assert_eq(effect_list[0].get("requirement", ""), "strength_gt_toughness", "Effect should require S > T")
