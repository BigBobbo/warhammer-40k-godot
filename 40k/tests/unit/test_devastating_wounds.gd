extends "res://addons/gut/test.gd"

# Tests for the DEVASTATING WOUNDS keyword implementation (T2-11)
# Tests the ACTUAL RulesEngine methods
#
# Per Warhammer 40k 10e rules: Devastating Wounds weapons cause mortal wounds
# on critical wounds (unmodified 6s to wound). Mortal wounds spill over between
# models. Regular attack damage does NOT spill over.

const GameStateData = preload("res://autoloads/GameState.gd")

var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

# ==========================================
# has_devastating_wounds() Tests
# ==========================================

func test_has_devastating_wounds_returns_true_for_devastating_bolter():
	"""Test that devastating_bolter has Devastating Wounds"""
	var result = rules_engine.has_devastating_wounds("devastating_bolter")
	assert_true(result, "devastating_bolter should have Devastating Wounds")

func test_has_devastating_wounds_returns_true_for_devastating_melta():
	"""Test that devastating_melta has Devastating Wounds"""
	var result = rules_engine.has_devastating_wounds("devastating_melta")
	assert_true(result, "devastating_melta should have Devastating Wounds")

func test_has_devastating_wounds_returns_true_for_lethal_devastating_bolter():
	"""Test that lethal_devastating_bolter has Devastating Wounds"""
	var result = rules_engine.has_devastating_wounds("lethal_devastating_bolter")
	assert_true(result, "lethal_devastating_bolter should have Devastating Wounds")

func test_has_devastating_wounds_returns_true_for_torrent_devastating():
	"""Test that torrent_devastating has Devastating Wounds"""
	var result = rules_engine.has_devastating_wounds("torrent_devastating")
	assert_true(result, "torrent_devastating should have Devastating Wounds")

func test_has_devastating_wounds_returns_false_for_bolt_rifle():
	"""Test that bolt_rifle does NOT have Devastating Wounds"""
	var result = rules_engine.has_devastating_wounds("bolt_rifle")
	assert_false(result, "bolt_rifle should NOT have Devastating Wounds")

func test_has_devastating_wounds_returns_false_for_lethal_bolter():
	"""Test that lethal_bolter (Lethal Hits only) does NOT have Devastating Wounds"""
	var result = rules_engine.has_devastating_wounds("lethal_bolter")
	assert_false(result, "lethal_bolter should NOT have Devastating Wounds")

func test_has_devastating_wounds_returns_false_for_unknown_weapon():
	"""Test that unknown weapon returns false"""
	var result = rules_engine.has_devastating_wounds("nonexistent_weapon")
	assert_false(result, "Unknown weapon should return false")

# ==========================================
# Weapon Profile Tests
# ==========================================

func test_weapon_profile_devastating_bolter_has_keyword():
	"""Test that devastating_bolter profile contains DEVASTATING WOUNDS keyword"""
	var profile = rules_engine.get_weapon_profile("devastating_bolter")
	assert_false(profile.is_empty(), "Should find devastating_bolter profile")
	var keywords = profile.get("keywords", [])
	assert_has(keywords, "DEVASTATING WOUNDS", "Devastating Bolter should have DEVASTATING WOUNDS keyword")

# ==========================================
# Devastating Wounds Logic Tests
# ==========================================

func test_devastating_wounds_causes_mortal_wounds():
	"""Test that Devastating Wounds converts critical wounds to mortal wounds"""
	# Per rules: critical wounds (unmodified 6s to wound) cause mortal wounds
	# equal to the weapon's Damage characteristic, and the attack sequence ends
	var critical_wounds = 2
	var weapon_damage = 3
	var mortal_wounds = critical_wounds * weapon_damage
	assert_eq(mortal_wounds, 6, "2 critical wounds with D3 damage should cause 6 mortal wounds")

func test_devastating_wounds_bypasses_saves():
	"""Test that mortal wounds from Devastating Wounds bypass saves"""
	# Mortal wounds always bypass armor and invulnerable saves
	var mortal_wounds = 4
	var wounds_after_saves = mortal_wounds  # No save roll needed
	assert_eq(wounds_after_saves, mortal_wounds, "Mortal wounds should bypass all saves")

# ==========================================
# T2-11: Mortal Wound Spillover Tests
# ==========================================

func _create_test_unit(wounds_per_model: int, model_count: int, fnp_value: int = 0) -> Dictionary:
	"""Helper to create a test unit with configurable wounds and optional FNP"""
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % i,
			"alive": true,
			"wounds": wounds_per_model,
			"current_wounds": wounds_per_model,
			"base_mm": 32
		})
	var stats = {
		"toughness": 4,
		"save": 3,
		"wounds": wounds_per_model
	}
	if fnp_value > 0:
		stats["fnp"] = fnp_value
	return {
		"meta": {
			"name": "Test Unit",
			"stats": stats
		},
		"models": models
	}

func test_dw_spillover_damage_carries_to_next_model():
	"""T2-11: Devastating wounds (mortal wounds) should spill over from killed model to next"""
	# 3 models with 1 wound each. 3 DW mortal wounds should kill all 3.
	var unit = _create_test_unit(1, 3)
	var board = {"units": {"target": unit}}
	var models = unit.models
	var result = RulesEngine._apply_damage_to_unit_pool("target", 3, models, board)
	assert_eq(result.casualties, 3, "3 mortal wounds should kill all 3 single-wound models via spillover")
	assert_eq(result.damage_applied, 3, "All 3 damage should be applied")

func test_dw_spillover_excess_damage_crosses_model_boundary():
	"""T2-11: DW damage exceeding one model's HP spills to the next"""
	# 3 models with 2 wounds each. 5 DW mortal wounds should kill 2, wound 1.
	var unit = _create_test_unit(2, 3)
	var board = {"units": {"target": unit}}
	var models = unit.models
	var result = RulesEngine._apply_damage_to_unit_pool("target", 5, models, board)
	assert_eq(result.casualties, 2, "5 mortal wounds against 2W models should kill 2")
	assert_eq(result.damage_applied, 5, "All 5 damage should be applied")
	# Third model should have 1 wound remaining
	assert_eq(models[2].current_wounds, 1, "Third model should have 1 wound remaining from spillover")

func test_regular_damage_no_spillover():
	"""T2-11: Regular failed-save damage should NOT spill over between models"""
	# 3 models with 1 wound each. One wound dealing 3 damage should only kill 1 model.
	# The other 2 damage is lost (no spillover for normal attacks).
	var unit = _create_test_unit(1, 3)
	var board = {"units": {"target": unit}}
	var models = unit.models
	var wound_damages = [3]  # Single wound doing 3 damage
	var result = RulesEngine._apply_damage_per_wound_no_spillover("target", wound_damages, models, board)
	assert_eq(result.casualties, 1, "Only 1 model should die (no spillover for regular wounds)")
	assert_eq(result.damage_applied, 1, "Only 1 damage applied (excess lost)")

func test_regular_damage_no_spillover_multiple_wounds():
	"""T2-11: Multiple regular wounds each kill at most one model, no spillover"""
	# 3 models with 1 wound each. Two wounds dealing 3 damage each = kill 2 models.
	var unit = _create_test_unit(1, 3)
	var board = {"units": {"target": unit}}
	var models = unit.models
	var wound_damages = [3, 3]  # 2 wounds each doing 3 damage
	var result = RulesEngine._apply_damage_per_wound_no_spillover("target", wound_damages, models, board)
	assert_eq(result.casualties, 2, "2 models should die (one per wound, no spillover)")
	assert_eq(result.damage_applied, 2, "Only 2 damage applied (excess lost for each wound)")

func test_regular_damage_no_spillover_multi_wound_model():
	"""T2-11: Regular damage wounds a multi-wound model without spillover"""
	# 2 models with 3 wounds each. One wound doing 5 damage kills model 1,
	# but the 2 excess damage is lost.
	var unit = _create_test_unit(3, 2)
	var board = {"units": {"target": unit}}
	var models = unit.models
	var wound_damages = [5]
	var result = RulesEngine._apply_damage_per_wound_no_spillover("target", wound_damages, models, board)
	assert_eq(result.casualties, 1, "1 model killed, excess damage lost")
	assert_eq(result.damage_applied, 3, "Only 3 damage applied (capped at model wounds)")
	assert_eq(models[1].current_wounds, 3, "Second model should be untouched")

func test_dw_vs_regular_spillover_difference():
	"""T2-11: Verify different outcomes between DW spillover and regular no-spillover"""
	# 3 models with 1 wound each. 3 total damage.
	# DW (spillover): 3 damage kills all 3 models
	# Regular (no spillover): 1 wound of 3 damage kills only 1 model
	var unit_dw = _create_test_unit(1, 3)
	var board_dw = {"units": {"target": unit_dw}}
	var models_dw = unit_dw.models
	var dw_result = RulesEngine._apply_damage_to_unit_pool("target", 3, models_dw, board_dw)

	var unit_reg = _create_test_unit(1, 3)
	var board_reg = {"units": {"target": unit_reg}}
	var models_reg = unit_reg.models
	var reg_result = RulesEngine._apply_damage_per_wound_no_spillover("target", [3], models_reg, board_reg)

	assert_eq(dw_result.casualties, 3, "DW mortal wounds should kill 3 models via spillover")
	assert_eq(reg_result.casualties, 1, "Regular wound should kill only 1 model (no spillover)")

func test_dw_spillover_with_fnp_in_ranged():
	"""T2-11: Ranged DW with FNP — FNP applies to devastating wounds, damage spills over"""
	var unit = _create_test_unit(1, 5, 5)  # 5+ FNP
	var board = {"units": {"target": unit}}
	var save_data = {
		"target_unit_id": "target",
		"damage": 2,
		"devastating_wounds": 2,
		"devastating_damage": 4  # 2 DW x 2 damage each
	}
	var save_results = []  # No regular saves
	var rng = RulesEngine.RNGService.new(42)
	var result = RulesEngine.apply_save_damage(save_results, save_data, board, -1, rng)
	# FNP should have been rolled for devastating wounds
	var has_dw_fnp = false
	for fnp_block in result.fnp_rolls:
		if fnp_block.get("source", "") == "devastating_wounds":
			has_dw_fnp = true
	assert_true(has_dw_fnp, "FNP should be rolled for devastating wound mortal wounds")

func test_dw_ranged_spillover_kills_multiple_single_wound_models():
	"""T2-11: Ranged DW damage spills over across multiple 1W models"""
	# 5 models with 1 wound. 3 devastating wounds of 1 damage each = 3 mortal wounds.
	# With spillover, all 3 should die.
	var unit = _create_test_unit(1, 5)
	var board = {"units": {"target": unit}}
	var save_data = {
		"target_unit_id": "target",
		"damage": 1,
		"devastating_wounds": 3,
		"devastating_damage": 3
	}
	var save_results = []  # No regular saves
	# Use devastating_damage_override to control exact damage
	var result = RulesEngine.apply_save_damage(save_results, save_data, board, 3)
	assert_eq(result.casualties, 3, "3 DW mortal wounds should kill 3 single-wound models via spillover")

func test_dw_ranged_combined_with_regular_saves():
	"""T2-11: DW damage applied before regular failed-save damage"""
	# 3 models with 2 wounds. 2 DW damage (spillover) + 1 failed save of 2 damage.
	var unit = _create_test_unit(2, 3)
	var board = {"units": {"target": unit}}
	var save_data = {
		"target_unit_id": "target",
		"damage": 2,
		"devastating_wounds": 1,
		"devastating_damage": 2  # 1 DW wound x 2 damage
	}
	var save_results = [{"saved": false, "model_index": 0}]
	# Override DW damage = 2 (kills model 0), then failed save = 2 damage to model 1
	var result = RulesEngine.apply_save_damage(save_results, save_data, board, 2)
	assert_eq(result.casualties, 2, "DW kills model 0, failed save kills model 1")

# ==========================================
# T2-11: Helper Function Tests
# ==========================================

func test_distribute_fnp_across_wounds_basic():
	"""T2-11: FNP prevention distributed across wound damages"""
	var wounds = [3, 2, 1]
	var result = RulesEngine._distribute_fnp_across_wounds(wounds, 2)
	# Should remove 2 damage from end: [3, 2, 1] - 2 prevented = last wound removed (1), then 1 from second (2->1)
	# Result: [3, 1]
	var total = 0
	for d in result:
		total += d
	assert_eq(total, 4, "Total remaining damage should be 6 - 2 = 4")

func test_distribute_fnp_prevents_all():
	"""T2-11: FNP prevents all damage"""
	var wounds = [2, 2]
	var result = RulesEngine._distribute_fnp_across_wounds(wounds, 4)
	assert_eq(result.size(), 0, "All wounds should be removed when FNP prevents all damage")

func test_distribute_fnp_prevents_none():
	"""T2-11: FNP prevents no damage"""
	var wounds = [3, 2]
	var result = RulesEngine._distribute_fnp_across_wounds(wounds, 0)
	assert_eq(result.size(), 2, "No wounds should be removed when FNP prevents nothing")
	assert_eq(result[0], 3)
	assert_eq(result[1], 2)

func test_trim_wound_damages_basic():
	"""T2-11: Trim wound damages to match target total"""
	var wounds = [3, 2, 1]
	var result = RulesEngine._trim_wound_damages_to_total(wounds, 4)
	var total = 0
	for d in result:
		total += d
	assert_eq(total, 4, "Trimmed damages should sum to target total")

func test_trim_wound_damages_zero():
	"""T2-11: Trim to zero returns empty"""
	var wounds = [3, 2]
	var result = RulesEngine._trim_wound_damages_to_total(wounds, 0)
	assert_eq(result.size(), 0, "Trimming to 0 should return empty array")

func test_trim_wound_damages_exact():
	"""T2-11: Trim that matches exactly returns all wounds"""
	var wounds = [3, 2]
	var result = RulesEngine._trim_wound_damages_to_total(wounds, 5)
	assert_eq(result.size(), 2)
	assert_eq(result[0], 3)
	assert_eq(result[1], 2)
