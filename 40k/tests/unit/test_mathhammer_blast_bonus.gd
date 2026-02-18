extends "res://addons/gut/test.gd"

# Tests for Mathhammer Blast attack bonus auto-calculation (T3-22)
# Validates that _build_shoot_action correctly adjusts attack counts
# for Blast weapons based on defender model count.
#
# Per 10e rules:
# - 5 or fewer models: no bonus
# - 6-10 models: +1 attack
# - 11+ models: +2 attacks
# - Minimum 3 attacks vs 6+ model units

# ==========================================
# Helper: build a minimal board with defender unit
# ==========================================
func _make_board(defender_unit_id: String, model_count: int) -> Dictionary:
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % i,
			"wounds": 1,
			"current_wounds": 1,
			"alive": true
		})
	return {
		"units": {
			defender_unit_id: {
				"id": defender_unit_id,
				"models": models,
				"meta": {"name": "Test Defender", "stats": {}}
			}
		}
	}

# ==========================================
# Helper: build attacker config
# ==========================================
func _make_attacker_config(unit_id: String, weapon_id: String, model_ids: Array, attacks: int) -> Dictionary:
	return {
		"unit_id": unit_id,
		"weapons": [{
			"weapon_id": weapon_id,
			"model_ids": model_ids,
			"attacks": attacks
		}]
	}

# ==========================================
# Helper: build defender config
# ==========================================
func _make_defender_config(unit_id: String) -> Dictionary:
	return {"unit_id": unit_id}

# ==========================================
# Test: No Blast bonus for small units (5 or fewer models)
# ==========================================
func test_blast_no_bonus_small_unit():
	"""Blast weapon vs 5-model unit should get no bonus attacks"""
	var board = _make_board("defender", 5)
	var attacker = _make_attacker_config("attacker", "frag_grenade", ["m1"], 2)
	var defender = _make_defender_config("defender")
	var rule_toggles = {}

	var action = Mathhammer._build_shoot_action(attacker, defender, rule_toggles, board)
	var assignments = action.payload.assignments
	assert_eq(assignments.size(), 1, "Should have 1 assignment")
	assert_eq(assignments[0].attacks_override, 2, "No blast bonus for 5 models, should stay at base 2")

# ==========================================
# Test: +1 Blast bonus for 6-10 model units
# ==========================================
func test_blast_bonus_medium_unit():
	"""Blast weapon vs 6-model unit should get +1 bonus attack"""
	var board = _make_board("defender", 6)
	var attacker = _make_attacker_config("attacker", "frag_grenade", ["m1"], 2)
	var defender = _make_defender_config("defender")
	var rule_toggles = {}

	var action = Mathhammer._build_shoot_action(attacker, defender, rule_toggles, board)
	var assignments = action.payload.assignments
	assert_eq(assignments.size(), 1, "Should have 1 assignment")
	assert_eq(assignments[0].attacks_override, 3, "Blast bonus +1 for 6 models: 2 + 1 = 3")

# ==========================================
# Test: +2 Blast bonus for 11+ model units
# ==========================================
func test_blast_bonus_large_unit():
	"""Blast weapon vs 11-model unit should get +2 bonus attacks"""
	var board = _make_board("defender", 11)
	var attacker = _make_attacker_config("attacker", "frag_grenade", ["m1"], 2)
	var defender = _make_defender_config("defender")
	var rule_toggles = {}

	var action = Mathhammer._build_shoot_action(attacker, defender, rule_toggles, board)
	var assignments = action.payload.assignments
	assert_eq(assignments.size(), 1, "Should have 1 assignment")
	assert_eq(assignments[0].attacks_override, 4, "Blast bonus +2 for 11 models: 2 + 2 = 4")

# ==========================================
# Test: Blast minimum 3 attacks vs 6+ model units
# ==========================================
func test_blast_minimum_3_attacks():
	"""Blast weapon with 1 base attack vs 6-model unit should be raised to minimum 3"""
	var board = _make_board("defender", 6)
	var attacker = _make_attacker_config("attacker", "frag_grenade", ["m1"], 1)
	var defender = _make_defender_config("defender")
	var rule_toggles = {}

	var action = Mathhammer._build_shoot_action(attacker, defender, rule_toggles, board)
	var assignments = action.payload.assignments
	assert_eq(assignments.size(), 1, "Should have 1 assignment")
	# 1 base + 1 blast bonus = 2, but minimum is 3 for 6+ models
	assert_eq(assignments[0].attacks_override, 3, "Blast minimum 3 should apply: base 1 + bonus 1 = 2, raised to 3")

# ==========================================
# Test: Non-Blast weapon gets no bonus
# ==========================================
func test_non_blast_weapon_no_bonus():
	"""Non-Blast weapon vs large unit should get no bonus"""
	var board = _make_board("defender", 11)
	var attacker = _make_attacker_config("attacker", "bolt_rifle", ["m1"], 2)
	var defender = _make_defender_config("defender")
	var rule_toggles = {}

	var action = Mathhammer._build_shoot_action(attacker, defender, rule_toggles, board)
	var assignments = action.payload.assignments
	assert_eq(assignments.size(), 1, "Should have 1 assignment")
	assert_eq(assignments[0].attacks_override, 2, "Non-blast weapon should stay at base attacks")

# ==========================================
# Test: Blast bonus stacks with Rapid Fire
# ==========================================
func test_blast_plus_rapid_fire():
	"""Blast + Rapid Fire should both apply their bonuses"""
	# Note: frag_grenade is Blast but not Rapid Fire, so RF toggle won't add anything
	# This test verifies they don't interfere with each other
	var board = _make_board("defender", 10)
	var attacker = _make_attacker_config("attacker", "frag_grenade", ["m1"], 3)
	var defender = _make_defender_config("defender")
	var rule_toggles = {"rapid_fire": true}

	var action = Mathhammer._build_shoot_action(attacker, defender, rule_toggles, board)
	var assignments = action.payload.assignments
	assert_eq(assignments.size(), 1, "Should have 1 assignment")
	# frag_grenade is not Rapid Fire, so RF adds 0, Blast adds +1 for 10 models
	assert_eq(assignments[0].attacks_override, 4, "Blast +1 for 10 models: 3 + 1 = 4 (RF adds 0 for non-RF weapon)")

# ==========================================
# Test: Blast with 10 models (boundary - still +1)
# ==========================================
func test_blast_bonus_10_models():
	"""10-model unit should still get +1 (not +2)"""
	var board = _make_board("defender", 10)
	var attacker = _make_attacker_config("attacker", "frag_grenade", ["m1"], 2)
	var defender = _make_defender_config("defender")
	var rule_toggles = {}

	var action = Mathhammer._build_shoot_action(attacker, defender, rule_toggles, board)
	var assignments = action.payload.assignments
	assert_eq(assignments[0].attacks_override, 3, "10 models should get +1 blast bonus: 2 + 1 = 3")
