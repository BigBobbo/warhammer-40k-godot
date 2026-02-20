extends "res://addons/gut/test.gd"

# Tests for Half Damage defensive ability — T4-17
# Validates that the half-damage ability correctly halves the Damage characteristic
# of incoming attacks (rounding up), applied after melta but before FNP.

# ==========================================
# Unit Tests: apply_half_damage static function
# ==========================================

func test_half_damage_even_number():
	"""6 damage halved = 3"""
	var result = RulesEngine.apply_half_damage(6)
	assert_eq(result, 3, "6 halved should be 3")

func test_half_damage_odd_number_rounds_up():
	"""5 damage halved rounds up = 3"""
	var result = RulesEngine.apply_half_damage(5)
	assert_eq(result, 3, "5 halved should round up to 3")

func test_half_damage_one_stays_one():
	"""1 damage halved rounds up = 1 (minimum)"""
	var result = RulesEngine.apply_half_damage(1)
	assert_eq(result, 1, "1 halved should round up to 1")

func test_half_damage_two():
	"""2 damage halved = 1"""
	var result = RulesEngine.apply_half_damage(2)
	assert_eq(result, 1, "2 halved should be 1")

func test_half_damage_three():
	"""3 damage halved rounds up = 2"""
	var result = RulesEngine.apply_half_damage(3)
	assert_eq(result, 2, "3 halved should round up to 2")

func test_half_damage_twelve():
	"""12 damage halved = 6"""
	var result = RulesEngine.apply_half_damage(12)
	assert_eq(result, 6, "12 halved should be 6")

# ==========================================
# Unit Tests: get_unit_half_damage
# ==========================================

func test_get_unit_half_damage_true():
	"""Unit with half_damage flag should return true"""
	var unit = {"meta": {"stats": {"half_damage": true}}}
	assert_true(RulesEngine.get_unit_half_damage(unit), "Should detect half_damage flag")

func test_get_unit_half_damage_false():
	"""Unit without half_damage flag should return false"""
	var unit = {"meta": {"stats": {"toughness": 8}}}
	assert_false(RulesEngine.get_unit_half_damage(unit), "Should return false when no half_damage flag")

func test_get_unit_half_damage_empty_unit():
	"""Empty unit should return false"""
	var unit = {}
	assert_false(RulesEngine.get_unit_half_damage(unit), "Empty unit should return false")

# ==========================================
# Helper: Build a minimal board for apply_save_damage tests
# ==========================================
func _make_board(unit_id: String, model_wounds: Array, half_damage: bool = false) -> Dictionary:
	var models = []
	for i in range(model_wounds.size()):
		models.append({
			"id": "m%d" % i,
			"wounds": model_wounds[i],
			"current_wounds": model_wounds[i],
			"alive": true
		})
	var stats = {"toughness": 4, "save": 3}
	if half_damage:
		stats["half_damage"] = true
	return {
		"units": {
			unit_id: {
				"id": unit_id,
				"models": models,
				"meta": {"stats": stats}
			}
		}
	}

# ==========================================
# Integration Tests: apply_save_damage with Half Damage
# ==========================================

func test_apply_save_damage_half_damage_reduces_damage():
	"""Half damage should reduce damage dealt from failed saves"""
	var rng = RulesEngine.RNGService.new(42)

	# Board WITHOUT half damage
	var board_no_hd = _make_board("defender", [10], false)
	var save_results = [{"saved": false, "model_index": 0}]
	var save_data = {
		"target_unit_id": "defender",
		"damage": 6,
		"damage_raw": "6",
		"devastating_wounds": 0
	}
	var rng_no_hd = RulesEngine.RNGService.new(42)
	var result_no_hd = RulesEngine.apply_save_damage(save_results, save_data, board_no_hd, -1, rng_no_hd)

	# Board WITH half damage
	var board_hd = _make_board("defender", [10], true)
	var rng_hd = RulesEngine.RNGService.new(42)
	var result_hd = RulesEngine.apply_save_damage(save_results, save_data, board_hd, -1, rng_hd)

	# Half damage should result in less or equal damage
	assert_true(result_hd.damage_applied <= result_no_hd.damage_applied,
		"Half damage (%d) should be <= normal damage (%d)" % [result_hd.damage_applied, result_no_hd.damage_applied])

func test_apply_save_damage_half_damage_fixed_6_becomes_3():
	"""Fixed damage 6 with half damage should become 3"""
	var board = _make_board("defender", [10], true)
	var save_results = [{"saved": false, "model_index": 0}]
	var save_data = {
		"target_unit_id": "defender",
		"damage": 6,
		"damage_raw": "6",
		"devastating_wounds": 0
	}
	var rng = RulesEngine.RNGService.new(42)
	var result = RulesEngine.apply_save_damage(save_results, save_data, board, -1, rng)

	# Fixed damage of 6 halved = 3
	assert_eq(result.damage_applied, 3, "Fixed 6 damage with half damage should apply 3 wounds")

func test_apply_save_damage_half_damage_fixed_5_becomes_3():
	"""Fixed damage 5 with half damage should become 3 (rounds up)"""
	var board = _make_board("defender", [10], true)
	var save_results = [{"saved": false, "model_index": 0}]
	var save_data = {
		"target_unit_id": "defender",
		"damage": 5,
		"damage_raw": "5",
		"devastating_wounds": 0
	}
	var rng = RulesEngine.RNGService.new(42)
	var result = RulesEngine.apply_save_damage(save_results, save_data, board, -1, rng)

	# Fixed damage of 5 halved rounds up = 3
	assert_eq(result.damage_applied, 3, "Fixed 5 damage with half damage should apply 3 wounds (round up)")

func test_apply_save_damage_half_damage_fixed_1_stays_1():
	"""Fixed damage 1 with half damage should stay 1 (rounds up from 0.5)"""
	var board = _make_board("defender", [10], true)
	var save_results = [{"saved": false, "model_index": 0}]
	var save_data = {
		"target_unit_id": "defender",
		"damage": 1,
		"damage_raw": "1",
		"devastating_wounds": 0
	}
	var rng = RulesEngine.RNGService.new(42)
	var result = RulesEngine.apply_save_damage(save_results, save_data, board, -1, rng)

	# Fixed damage of 1 halved rounds up = 1
	assert_eq(result.damage_applied, 1, "Fixed 1 damage with half damage should apply 1 wound (rounds up)")

func test_apply_save_damage_no_half_damage_full_damage():
	"""Without half damage, full damage should apply"""
	var board = _make_board("defender", [10], false)
	var save_results = [{"saved": false, "model_index": 0}]
	var save_data = {
		"target_unit_id": "defender",
		"damage": 6,
		"damage_raw": "6",
		"devastating_wounds": 0
	}
	var rng = RulesEngine.RNGService.new(42)
	var result = RulesEngine.apply_save_damage(save_results, save_data, board, -1, rng)

	# Full damage of 6 should apply
	assert_eq(result.damage_applied, 6, "Without half damage, full 6 damage should apply")

func test_apply_save_damage_half_damage_on_devastating_wounds():
	"""Half damage should also apply to devastating wound damage"""
	var board = _make_board("defender", [10], true)
	var save_results = []  # No regular saves
	var save_data = {
		"target_unit_id": "defender",
		"damage": 6,
		"damage_raw": "6",
		"devastating_wounds": 1
	}
	# Use fixed devastating damage override for deterministic testing
	# 6 devastating damage halved = 3
	var result = RulesEngine.apply_save_damage(save_results, save_data, board, 6)

	# Fixed devastating damage of 6 halved = 3
	assert_eq(result.damage_applied, 3, "Devastating wound damage 6 with half damage should apply 3")
