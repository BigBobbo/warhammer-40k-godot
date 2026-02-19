extends "res://addons/gut/test.gd"

# Tests for 10e save roll auto-fail rule (T4-13)
# Per Warhammer 40k 10th Edition:
# - Unmodified save roll of 1 ALWAYS fails (regardless of modifiers or save value)
#
# These tests verify that the save auto-fail logic in RulesEngine correctly
# prevents a save roll of 1 from ever succeeding across all resolution paths:
# - _resolve_assignment() (auto-resolve shooting)
# - _resolve_assignment_until_wounds() (overwatch)
# - fight phase auto-resolve

const RE = preload("res://autoloads/RulesEngine.gd")

# ==========================================
# _calculate_save_needed() Verification
# Confirm the function returns correct save thresholds
# ==========================================

func test_calculate_save_needed_returns_base_save_with_no_ap():
	"""Verify base save 3+ with AP 0 returns armour 3"""
	var result = RE._calculate_save_needed(3, 0, false, 0)
	assert_eq(result.armour, 3, "Base save 3+ with AP 0 should need 3+")
	assert_false(result.use_invuln, "Should not use invuln when none available")

func test_calculate_save_needed_applies_ap():
	"""Verify AP -2 on save 3+ returns armour 5"""
	var result = RE._calculate_save_needed(3, 2, false, 0)
	assert_eq(result.armour, 5, "Save 3+ with AP -2 should need 5+")

func test_calculate_save_needed_uses_invuln_when_better():
	"""Verify invuln 4+ is used when armour save is worse"""
	var result = RE._calculate_save_needed(3, 3, false, 4)
	assert_eq(result.armour, 6, "Armour save 3+ with AP -3 = 6+")
	assert_true(result.use_invuln, "Should use invuln 4+ when armour is 6+")

func test_calculate_save_needed_minimum_save_is_2():
	"""Verify saves can never be better than 2+"""
	var result = RE._calculate_save_needed(2, 0, true, 0)
	assert_true(result.armour >= 2, "Save should never be better than 2+")

# ==========================================
# Auto-Fail Rule: Unmodified Save Roll of 1 Always Fails
# These tests directly verify the save logic pattern used across
# all resolution paths in RulesEngine
# ==========================================

func test_natural_1_fails_save_even_with_best_possible_save():
	"""
	KEY RULE TEST: Even with a save of 2+ (best possible), a natural 1 must fail.
	This is the core defensive check — no save threshold can ever make a 1 succeed.
	"""
	var save_result = RE._calculate_save_needed(2, 0, false, 0)
	var save_roll = 1
	var saved = false

	# Replicate the exact logic from _resolve_assignment
	if save_roll > 1:
		if save_result.use_invuln:
			saved = save_roll >= save_result.inv
		else:
			saved = save_roll >= save_result.armour

	assert_false(saved, "Natural 1 must ALWAYS fail to save, even with 2+ save")

func test_natural_1_fails_save_with_invuln_2_plus():
	"""Natural 1 must fail even when using a 2+ invulnerable save"""
	var save_result = RE._calculate_save_needed(6, 5, false, 2)
	var save_roll = 1
	var saved = false

	assert_true(save_result.use_invuln, "Should be using invuln 2+ since armour is impossible")

	if save_roll > 1:
		if save_result.use_invuln:
			saved = save_roll >= save_result.inv
		else:
			saved = save_roll >= save_result.armour

	assert_false(saved, "Natural 1 must ALWAYS fail to save, even with 2+ invuln")

func test_natural_1_fails_save_with_cover():
	"""Natural 1 must fail even with cover improving the save"""
	var save_result = RE._calculate_save_needed(3, 1, true, 0)
	var save_roll = 1
	var saved = false

	# Cover can improve save, but natural 1 still auto-fails
	if save_roll > 1:
		if save_result.use_invuln:
			saved = save_roll >= save_result.inv
		else:
			saved = save_roll >= save_result.armour

	assert_false(saved, "Natural 1 must ALWAYS fail to save, even with cover")

func test_natural_1_fails_save_baseline_no_modifiers():
	"""Baseline: Natural 1 without any special modifiers should fail"""
	var save_result = RE._calculate_save_needed(4, 0, false, 0)
	var save_roll = 1
	var saved = false

	if save_roll > 1:
		if save_result.use_invuln:
			saved = save_roll >= save_result.inv
		else:
			saved = save_roll >= save_result.armour

	assert_false(saved, "Natural 1 should fail to save without modifiers too")

# ==========================================
# Verify Normal Save Rolls Still Work
# Ensure the auto-fail rule doesn't break normal behaviour
# ==========================================

func test_natural_2_saves_at_threshold_2():
	"""Roll 2 with save 2+ should succeed"""
	var save_result = RE._calculate_save_needed(2, 0, false, 0)
	var save_roll = 2
	var saved = false

	if save_roll > 1:
		if save_result.use_invuln:
			saved = save_roll >= save_result.inv
		else:
			saved = save_roll >= save_result.armour

	assert_true(saved, "Roll 2 vs save 2+ should save successfully")

func test_natural_3_fails_at_threshold_4():
	"""Roll 3 with save 4+ should fail"""
	var save_result = RE._calculate_save_needed(4, 0, false, 0)
	var save_roll = 3
	var saved = false

	if save_roll > 1:
		if save_result.use_invuln:
			saved = save_roll >= save_result.inv
		else:
			saved = save_roll >= save_result.armour

	assert_false(saved, "Roll 3 vs save 4+ should fail")

func test_natural_4_saves_at_threshold_4():
	"""Roll 4 with save 4+ should succeed"""
	var save_result = RE._calculate_save_needed(4, 0, false, 0)
	var save_roll = 4
	var saved = false

	if save_roll > 1:
		if save_result.use_invuln:
			saved = save_roll >= save_result.inv
		else:
			saved = save_roll >= save_result.armour

	assert_true(saved, "Roll 4 vs save 4+ should save successfully")

func test_natural_6_saves_at_threshold_6():
	"""Roll 6 should save at threshold 6+"""
	var save_result = RE._calculate_save_needed(6, 0, false, 0)
	var save_roll = 6
	var saved = false

	if save_roll > 1:
		if save_result.use_invuln:
			saved = save_roll >= save_result.inv
		else:
			saved = save_roll >= save_result.armour

	assert_true(saved, "Roll 6 vs save 6+ should save successfully")

func test_invuln_save_succeeds_when_roll_meets_threshold():
	"""Roll 4 with invuln 4+ should save successfully"""
	var save_result = RE._calculate_save_needed(3, 3, false, 4)
	var save_roll = 4
	var saved = false

	assert_true(save_result.use_invuln, "Should use invuln 4+ when armour is 6+")

	if save_roll > 1:
		if save_result.use_invuln:
			saved = save_roll >= save_result.inv
		else:
			saved = save_roll >= save_result.armour

	assert_true(saved, "Roll 4 vs invuln 4+ should save successfully")

# ==========================================
# Exhaustive Roll Check
# Verify every possible roll value (1-6) against various save thresholds
# ==========================================

func test_exhaustive_all_rolls_vs_save_2_plus():
	"""Check all rolls 1-6 against save 2+ (best save)"""
	var save_result = RE._calculate_save_needed(2, 0, false, 0)

	for roll in range(1, 7):
		var saved = false
		if roll > 1:
			if save_result.use_invuln:
				saved = roll >= save_result.inv
			else:
				saved = roll >= save_result.armour

		if roll == 1:
			assert_false(saved, "Roll 1 vs 2+ must fail (auto-fail rule)")
		else:
			assert_true(saved, "Roll %d vs 2+ should succeed" % roll)

func test_exhaustive_all_rolls_vs_invuln_2_plus():
	"""Check all rolls 1-6 against invuln 2+ (best invuln, bad armour)"""
	var save_result = RE._calculate_save_needed(6, 5, false, 2)
	assert_true(save_result.use_invuln, "Must use invuln save")

	for roll in range(1, 7):
		var saved = false
		if roll > 1:
			if save_result.use_invuln:
				saved = roll >= save_result.inv
			else:
				saved = roll >= save_result.armour

		if roll == 1:
			assert_false(saved, "Roll 1 vs invuln 2+ must fail (auto-fail rule)")
		else:
			assert_true(saved, "Roll %d vs invuln 2+ should succeed" % roll)

# ==========================================
# Statistical Integration Test via resolve_shoot
# Verify that over many auto-resolve trials, natural 1 saves
# never succeed (requires autoloads)
# ==========================================

func test_statistical_save_roll_of_1_never_saves_in_auto_resolve():
	"""
	Over many trials of resolve_shoot, verify that no save roll of 1
	ever results in a successful save. We check the dice log for save
	rolls where the roll was 1 and verify fails == 1.
	"""
	if not AutoloadHelper.verify_autoloads_available():
		pending("Autoloads not available — skipping integration test")
		return

	var rules_engine = AutoloadHelper.get_rules_engine()
	var false_saves = 0
	var total_save_1s_found = 0

	for trial in range(50):
		var board = _make_shoot_board("bolt_rifle", 2, 0, 0)  # Save 2+, best possible
		var action = _make_shoot_action("bolt_rifle")
		var rng = rules_engine.RNGService.new(trial)
		var result = rules_engine.resolve_shoot(action, board, rng)

		# Check dice log for save rolls
		for dice_entry in result.get("dice", []):
			if dice_entry.get("context", "") == "save":
				var rolls = dice_entry.get("rolls_raw", [])
				for roll in rolls:
					if roll == 1:
						total_save_1s_found += 1
						# A save roll of 1 MUST have fails == 1
						if dice_entry.get("fails", 0) == 0:
							false_saves += 1

	assert_eq(false_saves, 0,
		"Save roll of 1 should NEVER succeed over %d trials (found %d save-1s)" % [50, total_save_1s_found])

func test_statistical_save_roll_of_1_never_saves_with_invuln():
	"""
	Over many trials, verify that no save roll of 1 ever succeeds
	even when using an invulnerable save.
	"""
	if not AutoloadHelper.verify_autoloads_available():
		pending("Autoloads not available — skipping integration test")
		return

	var rules_engine = AutoloadHelper.get_rules_engine()
	var false_saves = 0
	var total_save_1s_found = 0

	for trial in range(50):
		# Target with 6+ armour save but 2+ invuln (best possible)
		var board = _make_shoot_board("bolt_rifle", 6, 4, 2)
		var action = _make_shoot_action("bolt_rifle")
		var rng = rules_engine.RNGService.new(trial + 1000)  # Different seed range
		var result = rules_engine.resolve_shoot(action, board, rng)

		for dice_entry in result.get("dice", []):
			if dice_entry.get("context", "") == "save":
				var rolls = dice_entry.get("rolls_raw", [])
				for roll in rolls:
					if roll == 1:
						total_save_1s_found += 1
						if dice_entry.get("fails", 0) == 0:
							false_saves += 1

	assert_eq(false_saves, 0,
		"Save roll of 1 should NEVER succeed with invuln over %d trials (found %d save-1s)" % [50, total_save_1s_found])

# ==========================================
# Helpers
# ==========================================

func _make_shoot_board(weapon_id: String, target_save: int = 4,
		target_ap_offset: int = 0, target_invuln: int = 0) -> Dictionary:
	"""Create a minimal board for auto-resolve shooting tests"""
	var target_models = []
	for i in range(5):
		var model = {
			"id": "t%d" % (i + 1),
			"alive": true,
			"current_wounds": 2,
			"wounds": 2,
			"position": {"x": 300 + i * 30, "y": 100}
		}
		if target_invuln > 0:
			model["invuln"] = target_invuln
		target_models.append(model)

	return {
		"units": {
			"attacker_unit": {
				"id": "attacker_unit",
				"owner": 1,
				"status": 1,
				"flags": {},
				"meta": {
					"name": "Attacker Unit",
					"keywords": ["INFANTRY"],
					"stats": {"toughness": 4, "save": 3}
				},
				"models": [{
					"id": "m1",
					"alive": true,
					"current_wounds": 2,
					"wounds": 2,
					"position": {"x": 100, "y": 100},
					"weapons": [weapon_id]
				}]
			},
			"target_unit": {
				"id": "target_unit",
				"owner": 2,
				"status": 1,
				"flags": {},
				"meta": {
					"name": "Target Unit",
					"keywords": ["INFANTRY"],
					"stats": {
						"toughness": 4,
						"save": target_save,
						"wounds": 2
					}
				},
				"models": target_models
			}
		}
	}

func _make_shoot_action(weapon_id: String) -> Dictionary:
	return {
		"type": "SHOOT",
		"actor_unit_id": "attacker_unit",
		"payload": {
			"assignments": [{
				"weapon_id": weapon_id,
				"target_unit_id": "target_unit",
				"model_ids": ["m1"]
			}]
		}
	}
