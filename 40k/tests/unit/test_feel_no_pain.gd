extends "res://addons/gut/test.gd"

# Tests for the FEEL NO PAIN (FNP) implementation
# Per Warhammer 40k 10e rules: "Each time a model would lose a wound,
# roll one D6: if the result >= the FNP value, that wound is not lost."
# FNP applies to ALL damage: failed saves, devastating wounds, mortal wounds.

const GameStateData = preload("res://autoloads/GameState.gd")

var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

# ==========================================
# get_unit_fnp() Tests
# ==========================================

func test_get_unit_fnp_returns_value_when_present():
	"""Test that get_unit_fnp returns the FNP value from unit stats"""
	var unit = {"meta": {"stats": {"fnp": 5}}}
	var result = RulesEngine.get_unit_fnp(unit)
	assert_eq(result, 5, "Should return FNP value 5")

func test_get_unit_fnp_returns_0_when_no_fnp():
	"""Test that get_unit_fnp returns 0 when unit has no FNP"""
	var unit = {"meta": {"stats": {"save": 3, "toughness": 4}}}
	var result = RulesEngine.get_unit_fnp(unit)
	assert_eq(result, 0, "Should return 0 for unit without FNP")

func test_get_unit_fnp_returns_0_for_empty_unit():
	"""Test that get_unit_fnp returns 0 for empty unit dict"""
	var unit = {}
	var result = RulesEngine.get_unit_fnp(unit)
	assert_eq(result, 0, "Should return 0 for empty unit")

func test_get_unit_fnp_returns_0_when_fnp_is_0():
	"""Test that get_unit_fnp returns 0 when fnp is explicitly 0"""
	var unit = {"meta": {"stats": {"fnp": 0}}}
	var result = RulesEngine.get_unit_fnp(unit)
	assert_eq(result, 0, "Should return 0 when FNP is 0")

func test_get_unit_fnp_returns_correct_for_fnp_6():
	"""Test 6+ FNP (worst possible FNP)"""
	var unit = {"meta": {"stats": {"fnp": 6}}}
	var result = RulesEngine.get_unit_fnp(unit)
	assert_eq(result, 6, "Should return 6 for 6+ FNP")

func test_get_unit_fnp_returns_correct_for_fnp_4():
	"""Test 4+ FNP (common for Death Guard)"""
	var unit = {"meta": {"stats": {"fnp": 4}}}
	var result = RulesEngine.get_unit_fnp(unit)
	assert_eq(result, 4, "Should return 4 for 4+ FNP")

# ==========================================
# roll_feel_no_pain() Tests
# ==========================================

func test_roll_feel_no_pain_rolls_correct_number_of_dice():
	"""Test that FNP rolls the correct number of dice"""
	var rng = RulesEngine.RNGService.new(42)
	var result = RulesEngine.roll_feel_no_pain(3, 5, rng)
	assert_eq(result.rolls.size(), 3, "Should roll 3 dice for 3 wounds")

func test_roll_feel_no_pain_returns_correct_structure():
	"""Test that FNP result has all required fields"""
	var rng = RulesEngine.RNGService.new(42)
	var result = RulesEngine.roll_feel_no_pain(2, 5, rng)
	assert_has(result, "rolls", "Result should have rolls")
	assert_has(result, "fnp_value", "Result should have fnp_value")
	assert_has(result, "wounds_prevented", "Result should have wounds_prevented")
	assert_has(result, "wounds_remaining", "Result should have wounds_remaining")

func test_roll_feel_no_pain_fnp_value_matches_input():
	"""Test that returned FNP value matches input"""
	var rng = RulesEngine.RNGService.new(42)
	var result = RulesEngine.roll_feel_no_pain(2, 5, rng)
	assert_eq(result.fnp_value, 5, "FNP value should match input")

func test_roll_feel_no_pain_wounds_add_up():
	"""Test that prevented + remaining = total wounds"""
	var rng = RulesEngine.RNGService.new(42)
	var result = RulesEngine.roll_feel_no_pain(4, 5, rng)
	assert_eq(result.wounds_prevented + result.wounds_remaining, 4, "Prevented + remaining should equal total wounds")

func test_roll_feel_no_pain_single_wound():
	"""Test FNP with single wound"""
	var rng = RulesEngine.RNGService.new(42)
	var result = RulesEngine.roll_feel_no_pain(1, 5, rng)
	assert_eq(result.rolls.size(), 1, "Should roll 1 die for 1 wound")
	assert_eq(result.wounds_prevented + result.wounds_remaining, 1, "Total should be 1")

func test_roll_feel_no_pain_zero_wounds():
	"""Test FNP with zero wounds (edge case)"""
	var rng = RulesEngine.RNGService.new(42)
	var result = RulesEngine.roll_feel_no_pain(0, 5, rng)
	assert_eq(result.rolls.size(), 0, "Should roll 0 dice for 0 wounds")
	assert_eq(result.wounds_prevented, 0, "Should prevent 0 wounds")
	assert_eq(result.wounds_remaining, 0, "Should have 0 remaining")

# ==========================================
# FNP with Seeded RNG (Deterministic Tests)
# ==========================================

func test_fnp_with_guaranteed_success_threshold():
	"""Test that a roll >= FNP value counts as prevented"""
	# Use seeded RNG and check multiple runs to verify logic
	var rng = RulesEngine.RNGService.new(12345)
	var result = RulesEngine.roll_feel_no_pain(10, 5, rng)
	# With 10 dice, we can verify the math is correct
	var manual_prevented = 0
	for roll in result.rolls:
		if roll >= 5:
			manual_prevented += 1
	assert_eq(result.wounds_prevented, manual_prevented, "Prevented count should match manual calculation")
	assert_eq(result.wounds_remaining, 10 - manual_prevented, "Remaining should be total minus prevented")

func test_fnp_2_plus_prevents_most_wounds():
	"""Test that FNP 2+ (very strong) prevents most wounds over many dice"""
	var rng = RulesEngine.RNGService.new(42)
	# Roll 100 dice with FNP 2+ (83% success rate)
	var result = RulesEngine.roll_feel_no_pain(100, 2, rng)
	# With 2+ FNP, roughly 83% should be prevented. Allow wide range.
	assert_gt(result.wounds_prevented, 50, "FNP 2+ should prevent more than half the wounds over 100 rolls")

func test_fnp_6_plus_prevents_few_wounds():
	"""Test that FNP 6+ (weakest) prevents few wounds"""
	var rng = RulesEngine.RNGService.new(42)
	# Roll 100 dice with FNP 6+ (16.7% success rate)
	var result = RulesEngine.roll_feel_no_pain(100, 6, rng)
	# With 6+ FNP, roughly 16.7% should be prevented
	assert_lt(result.wounds_prevented, 50, "FNP 6+ should prevent fewer than half the wounds over 100 rolls")

# ==========================================
# Integration Tests: apply_save_damage with FNP
# ==========================================

func _create_test_unit_with_fnp(fnp_value: int, wounds_per_model: int = 2, model_count: int = 3) -> Dictionary:
	"""Helper to create a test unit with FNP"""
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % i,
			"alive": true,
			"wounds": wounds_per_model,
			"current_wounds": wounds_per_model,
			"base_mm": 32
		})
	return {
		"meta": {
			"name": "Test FNP Unit",
			"stats": {
				"toughness": 4,
				"save": 3,
				"wounds": wounds_per_model,
				"fnp": fnp_value
			}
		},
		"models": models
	}

func _create_test_unit_without_fnp(wounds_per_model: int = 2, model_count: int = 3) -> Dictionary:
	"""Helper to create a test unit without FNP"""
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % i,
			"alive": true,
			"wounds": wounds_per_model,
			"current_wounds": wounds_per_model,
			"base_mm": 32
		})
	return {
		"meta": {
			"name": "Test No-FNP Unit",
			"stats": {
				"toughness": 4,
				"save": 3,
				"wounds": wounds_per_model
			}
		},
		"models": models
	}

func test_apply_save_damage_includes_fnp_fields_in_result():
	"""Test that apply_save_damage returns FNP tracking fields"""
	var unit = _create_test_unit_with_fnp(5, 2, 3)
	var board = {"units": {"test_unit": unit}}
	var save_data = {
		"target_unit_id": "test_unit",
		"damage": 1
	}
	var save_results = [{"saved": true, "model_index": 0}]
	var rng = RulesEngine.RNGService.new(42)
	var result = RulesEngine.apply_save_damage(save_results, save_data, board, -1, rng)
	assert_has(result, "fnp_rolls", "Result should have fnp_rolls field")
	assert_has(result, "fnp_wounds_prevented", "Result should have fnp_wounds_prevented field")

func test_apply_save_damage_no_fnp_rolls_when_all_saved():
	"""Test that no FNP rolls happen when all saves succeed"""
	var unit = _create_test_unit_with_fnp(5, 2, 3)
	var board = {"units": {"test_unit": unit}}
	var save_data = {"target_unit_id": "test_unit", "damage": 1}
	var save_results = [{"saved": true, "model_index": 0}]
	var rng = RulesEngine.RNGService.new(42)
	var result = RulesEngine.apply_save_damage(save_results, save_data, board, -1, rng)
	assert_eq(result.fnp_rolls.size(), 0, "No FNP rolls when all saves succeed")
	assert_eq(result.fnp_wounds_prevented, 0, "No FNP wounds prevented when all saves succeed")

func test_apply_save_damage_fnp_rolls_on_failed_save():
	"""Test that FNP dice are rolled for each failed save"""
	var unit = _create_test_unit_with_fnp(5, 3, 3)
	var board = {"units": {"test_unit": unit}}
	var save_data = {"target_unit_id": "test_unit", "damage": 2}
	# One failed save with D2 weapon = 2 FNP rolls
	var save_results = [{"saved": false, "model_index": 0}]
	var rng = RulesEngine.RNGService.new(42)
	var result = RulesEngine.apply_save_damage(save_results, save_data, board, -1, rng)
	assert_eq(result.fnp_rolls.size(), 1, "Should have 1 FNP roll block for 1 failed save")
	assert_eq(result.fnp_rolls[0].rolls.size(), 2, "Should roll 2 FNP dice for D2 weapon")

func test_apply_save_damage_no_fnp_when_unit_has_no_fnp():
	"""Test that no FNP rolls happen when unit has no FNP ability"""
	var unit = _create_test_unit_without_fnp(2, 3)
	var board = {"units": {"test_unit": unit}}
	var save_data = {"target_unit_id": "test_unit", "damage": 2}
	var save_results = [{"saved": false, "model_index": 0}]
	var rng = RulesEngine.RNGService.new(42)
	var result = RulesEngine.apply_save_damage(save_results, save_data, board, -1, rng)
	assert_eq(result.fnp_rolls.size(), 0, "No FNP rolls when unit has no FNP")
	assert_eq(result.fnp_wounds_prevented, 0, "No FNP wounds prevented when unit has no FNP")

func test_apply_save_damage_fnp_reduces_damage():
	"""Test that FNP can reduce damage applied to a model"""
	# Use seeded RNG to get deterministic results
	# Test over many iterations to verify FNP reduces total damage on average
	var total_damage_with_fnp = 0
	var total_damage_without_fnp = 0

	for seed_val in range(100):
		# With FNP 4+ (50% chance per wound)
		var unit_fnp = _create_test_unit_with_fnp(4, 10, 1)  # 10 wound model
		var board_fnp = {"units": {"test_unit": unit_fnp}}
		var save_data = {"target_unit_id": "test_unit", "damage": 3}
		var save_results = [{"saved": false, "model_index": 0}]
		var rng_fnp = RulesEngine.RNGService.new(seed_val)
		var result_fnp = RulesEngine.apply_save_damage(save_results, save_data, board_fnp, -1, rng_fnp)
		total_damage_with_fnp += result_fnp.damage_applied

		# Without FNP
		var unit_no_fnp = _create_test_unit_without_fnp(10, 1)
		var board_no_fnp = {"units": {"test_unit": unit_no_fnp}}
		var rng_no_fnp = RulesEngine.RNGService.new(seed_val)
		var result_no_fnp = RulesEngine.apply_save_damage(save_results, save_data, board_no_fnp, -1, rng_no_fnp)
		total_damage_without_fnp += result_no_fnp.damage_applied

	assert_lt(total_damage_with_fnp, total_damage_without_fnp, "FNP 4+ should reduce total damage compared to no FNP over 100 iterations")

func test_apply_save_damage_fnp_on_devastating_wounds():
	"""Test that FNP applies to devastating wounds damage"""
	var unit = _create_test_unit_with_fnp(5, 10, 1)
	var board = {"units": {"test_unit": unit}}
	var save_data = {
		"target_unit_id": "test_unit",
		"damage": 2,
		"devastating_damage": 4  # 4 devastating wounds damage
	}
	var save_results = []  # No regular saves, only devastating
	var rng = RulesEngine.RNGService.new(42)
	var result = RulesEngine.apply_save_damage(save_results, save_data, board, -1, rng)
	# Should have rolled FNP for the 4 devastating damage
	var has_dw_fnp = false
	for fnp_block in result.fnp_rolls:
		if fnp_block.get("source", "") == "devastating_wounds":
			has_dw_fnp = true
			assert_eq(fnp_block.rolls.size(), 4, "Should roll 4 FNP dice for 4 devastating damage")
	assert_true(has_dw_fnp, "Should have FNP rolls for devastating wounds")

func test_apply_save_damage_fnp_prevents_all_damage_skips_wound():
	"""Test that if FNP prevents all damage from a failed save, no wound is applied"""
	# Use a seeded RNG that will give all 6s for FNP rolls
	# We can't guarantee a specific seed will work, so test the logic differently:
	# Use FNP 2+ with D1 weapon - high chance of preventing the 1 wound
	var prevented_count = 0
	var iterations = 100
	for seed_val in range(iterations):
		var unit = _create_test_unit_with_fnp(2, 2, 1)
		var board = {"units": {"test_unit": unit}}
		var save_data = {"target_unit_id": "test_unit", "damage": 1}
		var save_results = [{"saved": false, "model_index": 0}]
		var rng = RulesEngine.RNGService.new(seed_val)
		var result = RulesEngine.apply_save_damage(save_results, save_data, board, -1, rng)
		if result.damage_applied == 0:
			prevented_count += 1
	# With FNP 2+ on D1 weapon, ~83% of the time all damage should be prevented
	assert_gt(prevented_count, 50, "FNP 2+ with D1 should prevent all damage more than half the time")

# ==========================================
# Integration Test: Warboss in Mega Armour has FNP
# ==========================================

func test_warboss_mega_armour_has_fnp_in_game_state():
	"""Test that Warboss in Mega Armour unit has FNP 5+ in loaded game state"""
	var unit = GameState.get_unit("U_WARBOSS_IN_MEGA_ARMOUR_D")
	if unit == null or unit.is_empty():
		# Unit might not be loaded, skip gracefully
		pending("Unit not loaded - skipping game state test")
		return
	var fnp = RulesEngine.get_unit_fnp(unit)
	assert_eq(fnp, 5, "Warboss in Mega Armour should have FNP 5+")
