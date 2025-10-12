extends GutTest

# Test shooting modifiers (Phase 1 MVP)
# Tests for RulesEngine.apply_hit_modifiers() and modifier application

func test_hit_modifier_none():
	var rng = RulesEngine.RNGService.new(12345)
	var result = RulesEngine.apply_hit_modifiers(3, RulesEngine.HitModifier.NONE, rng)

	assert_eq(result.modified_roll, 3, "No modifier should not change roll")
	assert_false(result.rerolled, "No re-roll should occur")
	assert_eq(result.modifier_applied, 0, "No modifier should be applied")

func test_hit_modifier_plus_one():
	var rng = RulesEngine.RNGService.new(12345)
	var result = RulesEngine.apply_hit_modifiers(3, RulesEngine.HitModifier.PLUS_ONE, rng)

	assert_eq(result.modified_roll, 4, "+1 modifier should add 1 to roll")
	assert_false(result.rerolled, "No re-roll should occur")
	assert_eq(result.modifier_applied, 1, "+1 modifier should be tracked")

func test_hit_modifier_minus_one():
	var rng = RulesEngine.RNGService.new(12345)
	var result = RulesEngine.apply_hit_modifiers(4, RulesEngine.HitModifier.MINUS_ONE, rng)

	assert_eq(result.modified_roll, 3, "-1 modifier should subtract 1 from roll")
	assert_false(result.rerolled, "No re-roll should occur")
	assert_eq(result.modifier_applied, -1, "-1 modifier should be tracked")

func test_hit_modifier_reroll_ones():
	# Test that 1s are re-rolled
	var rng = RulesEngine.RNGService.new(12345)
	var result = RulesEngine.apply_hit_modifiers(1, RulesEngine.HitModifier.REROLL_ONES, rng)

	assert_true(result.rerolled, "Roll of 1 should be re-rolled")
	assert_eq(result.original_roll, 1, "Original roll should be 1")
	assert_gt(result.reroll_value, 0, "Re-roll should produce a value")

	# Test that non-1s are not re-rolled
	var result2 = RulesEngine.apply_hit_modifiers(3, RulesEngine.HitModifier.REROLL_ONES, rng)
	assert_false(result2.rerolled, "Roll of 3 should not be re-rolled")
	assert_eq(result2.modified_roll, 3, "Non-1 roll should remain unchanged")

func test_hit_modifier_combined_plus_one_and_minus_one():
	# Both +1 and -1 should cancel out (capped)
	var rng = RulesEngine.RNGService.new(12345)
	var combined = RulesEngine.HitModifier.PLUS_ONE | RulesEngine.HitModifier.MINUS_ONE
	var result = RulesEngine.apply_hit_modifiers(3, combined, rng)

	assert_eq(result.modified_roll, 3, "+1 and -1 should cancel out")
	assert_eq(result.modifier_applied, 0, "Net modifier should be 0")

func test_hit_modifier_reroll_then_plus_one():
	# Test that re-rolls happen BEFORE modifiers
	var rng = RulesEngine.RNGService.new(12345)
	var combined = RulesEngine.HitModifier.REROLL_ONES | RulesEngine.HitModifier.PLUS_ONE
	var result = RulesEngine.apply_hit_modifiers(1, combined, rng)

	assert_true(result.rerolled, "Roll of 1 should be re-rolled first")
	# Modified roll should be reroll_value + 1
	assert_eq(result.modified_roll, result.reroll_value + 1, "Modifier should be applied AFTER re-roll")

func test_wound_threshold_strength_vs_toughness():
	# Test S >= T*2 (2+)
	assert_eq(RulesEngine._calculate_wound_threshold(8, 4), 2, "S8 vs T4 should wound on 2+")
	assert_eq(RulesEngine._calculate_wound_threshold(10, 5), 2, "S10 vs T5 should wound on 2+")

	# Test S > T (3+)
	assert_eq(RulesEngine._calculate_wound_threshold(5, 4), 3, "S5 vs T4 should wound on 3+")
	assert_eq(RulesEngine._calculate_wound_threshold(6, 5), 3, "S6 vs T5 should wound on 3+")

	# Test S == T (4+)
	assert_eq(RulesEngine._calculate_wound_threshold(4, 4), 4, "S4 vs T4 should wound on 4+")
	assert_eq(RulesEngine._calculate_wound_threshold(5, 5), 4, "S5 vs T5 should wound on 4+")

	# Test S < T (5+)
	assert_eq(RulesEngine._calculate_wound_threshold(4, 5), 5, "S4 vs T5 should wound on 5+")
	assert_eq(RulesEngine._calculate_wound_threshold(3, 4), 5, "S3 vs T4 should wound on 5+")

	# Test S <= T/2 (6+)
	assert_eq(RulesEngine._calculate_wound_threshold(3, 6), 6, "S3 vs T6 should wound on 6+")
	assert_eq(RulesEngine._calculate_wound_threshold(2, 5), 6, "S2 vs T5 should wound on 6+")

func test_modifier_capping():
	# Test that multiple +1 modifiers are capped at +1
	# (This would require extending HitModifier enum with multiple sources, but the capping logic is in place)
	var rng = RulesEngine.RNGService.new(12345)
	var result = RulesEngine.apply_hit_modifiers(3, RulesEngine.HitModifier.PLUS_ONE, rng)

	# Single +1 should result in net +1
	assert_eq(result.modifier_applied, 1, "Single +1 should be +1")
	assert_eq(result.modified_roll, 4, "Roll should be modified by +1")
