extends SceneTree

# Tests for T3-23: Full re-roll support for hits and wounds
# Validates:
# - HitModifier.REROLL_FAILED re-rolls all failed hit rolls
# - WoundModifier.REROLL_ONES re-rolls wound rolls of 1
# - WoundModifier.REROLL_FAILED re-rolls all failed wound rolls
# - Re-roll ones takes priority over re-roll failed (both set)
# - apply_hit_modifiers with hit_threshold parameter

const RE = preload("res://autoloads/RulesEngine.gd")

func _init():
	print("=== Re-roll Support Tests (T3-23) ===")
	var pass_count = 0
	var fail_count = 0

	# ==========================================
	# HitModifier enum tests
	# ==========================================

	# Test: REROLL_FAILED enum value is 8
	if RE.HitModifier.REROLL_FAILED == 8:
		print("PASS: HitModifier.REROLL_FAILED has value 8")
		pass_count += 1
	else:
		print("FAIL: HitModifier.REROLL_FAILED expected 8, got %d" % RE.HitModifier.REROLL_FAILED)
		fail_count += 1

	# Test: All flags can be combined without conflict
	var all_flags = RE.HitModifier.REROLL_ONES | RE.HitModifier.PLUS_ONE | RE.HitModifier.MINUS_ONE | RE.HitModifier.REROLL_FAILED
	if all_flags == 15:
		print("PASS: All HitModifier flags combined = 15 (1|2|4|8)")
		pass_count += 1
	else:
		print("FAIL: All HitModifier flags combined expected 15, got %d" % all_flags)
		fail_count += 1

	# ==========================================
	# HitModifier.REROLL_FAILED tests
	# ==========================================
	var rng = RE.RNGService.new(42)

	# Test: REROLL_FAILED triggers on miss (roll 2, BS 4+)
	var r1 = RE.apply_hit_modifiers(2, RE.HitModifier.REROLL_FAILED, rng, 4)
	if r1.rerolled:
		print("PASS: REROLL_FAILED triggers on roll 2 vs BS 4+")
		pass_count += 1
	else:
		print("FAIL: REROLL_FAILED should trigger on roll 2 vs BS 4+")
		fail_count += 1

	# Test: REROLL_FAILED does NOT trigger on success (roll 4, BS 4+)
	rng = RE.RNGService.new(42)
	var r2 = RE.apply_hit_modifiers(4, RE.HitModifier.REROLL_FAILED, rng, 4)
	if not r2.rerolled:
		print("PASS: REROLL_FAILED does not trigger on roll 4 vs BS 4+")
		pass_count += 1
	else:
		print("FAIL: REROLL_FAILED should NOT trigger on roll 4 vs BS 4+")
		fail_count += 1

	# Test: REROLL_FAILED does NOT trigger on 6
	rng = RE.RNGService.new(42)
	var r3 = RE.apply_hit_modifiers(6, RE.HitModifier.REROLL_FAILED, rng, 4)
	if not r3.rerolled:
		print("PASS: REROLL_FAILED does not trigger on roll 6")
		pass_count += 1
	else:
		print("FAIL: REROLL_FAILED should NOT trigger on roll 6")
		fail_count += 1

	# Test: REROLL_FAILED triggers on roll 1 (which is a failed hit)
	rng = RE.RNGService.new(42)
	var r4 = RE.apply_hit_modifiers(1, RE.HitModifier.REROLL_FAILED, rng, 4)
	if r4.rerolled:
		print("PASS: REROLL_FAILED triggers on roll 1 vs BS 4+")
		pass_count += 1
	else:
		print("FAIL: REROLL_FAILED should trigger on roll 1 vs BS 4+")
		fail_count += 1

	# Test: REROLL_FAILED without threshold does nothing
	rng = RE.RNGService.new(42)
	var r5 = RE.apply_hit_modifiers(2, RE.HitModifier.REROLL_FAILED, rng)
	if not r5.rerolled:
		print("PASS: REROLL_FAILED without threshold (default 0) does nothing")
		pass_count += 1
	else:
		print("FAIL: REROLL_FAILED without threshold should not trigger")
		fail_count += 1

	# Test: REROLL_ONES takes priority over REROLL_FAILED for roll of 1
	rng = RE.RNGService.new(42)
	var combined = RE.HitModifier.REROLL_ONES | RE.HitModifier.REROLL_FAILED
	var r6 = RE.apply_hit_modifiers(1, combined, rng, 4)
	if r6.rerolled:
		print("PASS: Combined REROLL_ONES|REROLL_FAILED re-rolls roll of 1")
		pass_count += 1
	else:
		print("FAIL: Combined flags should re-roll roll of 1")
		fail_count += 1

	# Test: REROLL_FAILED with BS 3+ re-rolls roll of 2
	rng = RE.RNGService.new(42)
	var r7 = RE.apply_hit_modifiers(2, RE.HitModifier.REROLL_FAILED, rng, 3)
	if r7.rerolled:
		print("PASS: REROLL_FAILED triggers on roll 2 vs BS 3+")
		pass_count += 1
	else:
		print("FAIL: REROLL_FAILED should trigger on roll 2 vs BS 3+")
		fail_count += 1

	# Test: REROLL_FAILED with BS 3+ does NOT re-roll roll of 3
	rng = RE.RNGService.new(42)
	var r8 = RE.apply_hit_modifiers(3, RE.HitModifier.REROLL_FAILED, rng, 3)
	if not r8.rerolled:
		print("PASS: REROLL_FAILED does not trigger on roll 3 vs BS 3+")
		pass_count += 1
	else:
		print("FAIL: REROLL_FAILED should NOT trigger on roll 3 vs BS 3+")
		fail_count += 1

	# ==========================================
	# WoundModifier re-roll tests (verify existing)
	# ==========================================

	# Test: REROLL_ONES wounds triggers on 1
	rng = RE.RNGService.new(42)
	var w1 = RE.apply_wound_modifiers(1, RE.WoundModifier.REROLL_ONES, 4, rng)
	if w1.rerolled:
		print("PASS: WoundModifier.REROLL_ONES triggers on wound roll 1")
		pass_count += 1
	else:
		print("FAIL: WoundModifier.REROLL_ONES should trigger on wound roll 1")
		fail_count += 1

	# Test: REROLL_ONES wounds does NOT trigger on 2
	rng = RE.RNGService.new(42)
	var w2 = RE.apply_wound_modifiers(2, RE.WoundModifier.REROLL_ONES, 4, rng)
	if not w2.rerolled:
		print("PASS: WoundModifier.REROLL_ONES does not trigger on wound roll 2")
		pass_count += 1
	else:
		print("FAIL: WoundModifier.REROLL_ONES should NOT trigger on wound roll 2")
		fail_count += 1

	# Test: REROLL_FAILED wounds triggers below threshold
	rng = RE.RNGService.new(42)
	var w3 = RE.apply_wound_modifiers(3, RE.WoundModifier.REROLL_FAILED, 4, rng)
	if w3.rerolled:
		print("PASS: WoundModifier.REROLL_FAILED triggers on wound roll 3 vs threshold 4")
		pass_count += 1
	else:
		print("FAIL: WoundModifier.REROLL_FAILED should trigger on wound roll 3 vs threshold 4")
		fail_count += 1

	# Test: REROLL_FAILED wounds does NOT trigger at threshold
	rng = RE.RNGService.new(42)
	var w4 = RE.apply_wound_modifiers(4, RE.WoundModifier.REROLL_FAILED, 4, rng)
	if not w4.rerolled:
		print("PASS: WoundModifier.REROLL_FAILED does not trigger on wound roll 4 vs threshold 4")
		pass_count += 1
	else:
		print("FAIL: WoundModifier.REROLL_FAILED should NOT trigger on wound roll 4 vs threshold 4")
		fail_count += 1

	# Test: Combined wound re-roll flags work
	rng = RE.RNGService.new(42)
	var w_combined = RE.WoundModifier.REROLL_ONES | RE.WoundModifier.REROLL_FAILED
	var w5 = RE.apply_wound_modifiers(1, w_combined, 4, rng)
	if w5.rerolled:
		print("PASS: Combined WoundModifier REROLL_ONES|REROLL_FAILED re-rolls wound roll 1")
		pass_count += 1
	else:
		print("FAIL: Combined wound flags should re-roll wound roll 1")
		fail_count += 1

	# ==========================================
	# Statistical validation: REROLL_FAILED improves hit rate
	# ==========================================
	rng = RE.RNGService.new(12345)
	var hits_without_reroll = 0
	var hits_with_reroll = 0
	var trials = 10000
	var bs = 4  # BS 4+ = need 4, 5, or 6 to hit (50% base rate)

	# Without re-rolls
	for _i in range(trials):
		var roll = rng.roll_d6(1)[0]
		if roll >= bs:
			hits_without_reroll += 1

	# With re-roll failed
	rng = RE.RNGService.new(12345)
	for _i in range(trials):
		var roll = rng.roll_d6(1)[0]
		var result = RE.apply_hit_modifiers(roll, RE.HitModifier.REROLL_FAILED, rng, bs)
		if result.modified_roll >= bs:
			hits_with_reroll += 1

	var hit_rate_without = float(hits_without_reroll) / trials * 100.0
	var hit_rate_with = float(hits_with_reroll) / trials * 100.0

	if hits_with_reroll > hits_without_reroll:
		print("PASS: Re-roll failed improves hit rate (%.1f%% -> %.1f%%)" % [hit_rate_without, hit_rate_with])
		pass_count += 1
	else:
		print("FAIL: Re-roll failed should improve hit rate (without: %.1f%%, with: %.1f%%)" % [hit_rate_without, hit_rate_with])
		fail_count += 1

	# Expected: BS 4+ base rate ~50%, with re-roll failed ~75%
	if hit_rate_with > 70.0 and hit_rate_with < 80.0:
		print("PASS: Re-roll failed hit rate ~75%% as expected (got %.1f%%)" % hit_rate_with)
		pass_count += 1
	else:
		print("FAIL: Re-roll failed hit rate expected ~75%%, got %.1f%%" % hit_rate_with)
		fail_count += 1

	# ==========================================
	# Summary
	# ==========================================
	print("\n=== Results: %d passed, %d failed ===" % [pass_count, fail_count])
	if fail_count == 0:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")

	quit()
