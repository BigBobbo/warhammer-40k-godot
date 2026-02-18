extends "res://addons/gut/test.gd"

# Tests for Mathhammer._extract_damage_from_result() — T1-9
# Validates that damage extraction correctly computes wound deltas from diffs,
# including the case where a model receives multiple current_wounds diffs in
# one resolve (e.g. devastating wounds + failed save damage).

# ==========================================
# Helper: build a minimal trial_board
# ==========================================
func _make_board(unit_id: String, model_wounds: Array) -> Dictionary:
	var models = []
	for i in range(model_wounds.size()):
		models.append({
			"id": "m%d" % i,
			"wounds": model_wounds[i],
			"current_wounds": model_wounds[i],
			"alive": true
		})
	return {
		"units": {
			unit_id: {
				"id": unit_id,
				"models": models
			}
		}
	}

# ==========================================
# Test: Single model takes partial damage (not killed)
# ==========================================
func test_partial_damage_single_model():
	"""A lascannon dealing 6 damage to a 12W vehicle that doesn't die should count as 6 damage"""
	var board = _make_board("defender", [12])
	var combat_result = {
		"diffs": [
			{"op": "set", "path": "units.defender.models.0.current_wounds", "value": 6}
		]
	}
	var damage = Mathhammer._extract_damage_from_result(combat_result, board)
	assert_eq(damage, 6, "Should count 6 damage (12 - 6)")

# ==========================================
# Test: Single model killed (wounds go to 0)
# ==========================================
func test_model_killed():
	"""Killing a 2W model should count as 2 damage"""
	var board = _make_board("defender", [2])
	var combat_result = {
		"diffs": [
			{"op": "set", "path": "units.defender.models.0.current_wounds", "value": 0},
			{"op": "set", "path": "units.defender.models.0.alive", "value": false}
		]
	}
	var damage = Mathhammer._extract_damage_from_result(combat_result, board)
	assert_eq(damage, 2, "Should count 2 damage for killed 2W model")

# ==========================================
# Test: Multiple models take damage
# ==========================================
func test_multiple_models_damaged():
	"""Two models taking different amounts of damage"""
	var board = _make_board("defender", [3, 3])
	var combat_result = {
		"diffs": [
			{"op": "set", "path": "units.defender.models.0.current_wounds", "value": 1},
			{"op": "set", "path": "units.defender.models.1.current_wounds", "value": 2}
		]
	}
	var damage = Mathhammer._extract_damage_from_result(combat_result, board)
	assert_eq(damage, 3, "Should count 2 + 1 = 3 damage across two models")

# ==========================================
# Test: No damage (no current_wounds diffs)
# ==========================================
func test_no_damage_no_diffs():
	"""No diffs means no damage"""
	var board = _make_board("defender", [6])
	var combat_result = {"diffs": []}
	var damage = Mathhammer._extract_damage_from_result(combat_result, board)
	assert_eq(damage, 0, "No diffs should yield 0 damage")

# ==========================================
# Test: Multiple diffs on same model (devastating wounds + failed save)
# ==========================================
func test_multiple_diffs_same_model_no_double_count():
	"""Devastating wounds (12->8) then failed save (8->3) on same model = 9 total, not 13"""
	var board = _make_board("defender", [12])
	var combat_result = {
		"diffs": [
			# Devastating wounds: 12W -> 8W
			{"op": "set", "path": "units.defender.models.0.current_wounds", "value": 8},
			# Failed save damage: 8W -> 3W
			{"op": "set", "path": "units.defender.models.0.current_wounds", "value": 3}
		]
	}
	var damage = Mathhammer._extract_damage_from_result(combat_result, board)
	assert_eq(damage, 9, "Should count (12-8) + (8-3) = 9, not (12-8) + (12-3) = 13")

# ==========================================
# Test: Multiple diffs on same model ending in death
# ==========================================
func test_multiple_diffs_same_model_killed():
	"""Devastating wounds (6->3) then failed save kills (3->0) = 6 total damage"""
	var board = _make_board("defender", [6])
	var combat_result = {
		"diffs": [
			{"op": "set", "path": "units.defender.models.0.current_wounds", "value": 3},
			{"op": "set", "path": "units.defender.models.0.current_wounds", "value": 0},
			{"op": "set", "path": "units.defender.models.0.alive", "value": false}
		]
	}
	var damage = Mathhammer._extract_damage_from_result(combat_result, board)
	assert_eq(damage, 6, "Should count (6-3) + (3-0) = 6 total damage")

# ==========================================
# Test: Mixed — one model gets multiple diffs, another gets one
# ==========================================
func test_mixed_single_and_multiple_diffs():
	"""Model 0: 10->7->0 (killed), Model 1: 10->4 (wounded). Total = 10 + 6 = 16"""
	var board = _make_board("defender", [10, 10])
	var combat_result = {
		"diffs": [
			# Model 0: devastating wounds 10->7
			{"op": "set", "path": "units.defender.models.0.current_wounds", "value": 7},
			# Model 0: failed save kills 7->0
			{"op": "set", "path": "units.defender.models.0.current_wounds", "value": 0},
			{"op": "set", "path": "units.defender.models.0.alive", "value": false},
			# Model 1: single failed save 10->4
			{"op": "set", "path": "units.defender.models.1.current_wounds", "value": 4}
		]
	}
	var damage = Mathhammer._extract_damage_from_result(combat_result, board)
	assert_eq(damage, 16, "Should count (10-7)+(7-0) + (10-4) = 3+7+6 = 16")

# ==========================================
# Test: 1W models (common infantry)
# ==========================================
func test_one_wound_models():
	"""Three 1W models killed = 3 damage"""
	var board = _make_board("defender", [1, 1, 1, 1, 1])
	var combat_result = {
		"diffs": [
			{"op": "set", "path": "units.defender.models.0.current_wounds", "value": 0},
			{"op": "set", "path": "units.defender.models.0.alive", "value": false},
			{"op": "set", "path": "units.defender.models.1.current_wounds", "value": 0},
			{"op": "set", "path": "units.defender.models.1.alive", "value": false},
			{"op": "set", "path": "units.defender.models.2.current_wounds", "value": 0},
			{"op": "set", "path": "units.defender.models.2.alive", "value": false}
		]
	}
	var damage = Mathhammer._extract_damage_from_result(combat_result, board)
	assert_eq(damage, 3, "Should count 3 damage for three killed 1W models")

# ==========================================
# Test: Ignores non-current_wounds diffs
# ==========================================
func test_ignores_alive_diffs():
	"""Only current_wounds diffs contribute to damage, not alive diffs"""
	var board = _make_board("defender", [1])
	var combat_result = {
		"diffs": [
			{"op": "set", "path": "units.defender.models.0.alive", "value": false}
		]
	}
	var damage = Mathhammer._extract_damage_from_result(combat_result, board)
	assert_eq(damage, 0, "alive diffs alone should not count as damage")
