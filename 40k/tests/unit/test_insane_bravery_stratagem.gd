extends "res://addons/gut/test.gd"

# Tests for INSANE BRAVERY stratagem implementation
#
# Per Warhammer 40k 10th Edition Core Rules:
# - INSANE BRAVERY (Core – Epic Deed Stratagem, 1 CP)
# - WHEN: Battle-shock step of your Command phase, just before you take
#   a Battle-shock test for a unit from your army.
# - TARGET: That unit from your army.
# - EFFECT: Your unit automatically passes that Battle-shock test.
# - RESTRICTIONS: You cannot use this Stratagem more than once per battle.
#
# These tests verify:
# 1. StratagemManager correctly validates Insane Bravery usage
# 2. CP is deducted when used
# 3. Once-per-battle restriction is enforced
# 4. CommandPhase correctly auto-passes the test
# 5. Battle-shocked flag is NOT set when Insane Bravery is used

const GameStateData = preload("res://autoloads/GameState.gd")


# ==========================================
# Helpers
# ==========================================

func _create_command_phase():
	var phase = preload("res://phases/CommandPhase.gd").new()
	add_child(phase)
	return phase

func _create_unit(id: String, model_count: int, leadership: int = 7, owner: int = 1, wounds_per_model: int = 1) -> Dictionary:
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": wounds_per_model,
			"current_wounds": wounds_per_model,
			"base_mm": 32,
			"position": {"x": 100 + i * 20, "y": 100},
			"alive": true,
			"status_effects": []
		})
	return {
		"id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Test Unit %s" % id,
			"keywords": ["INFANTRY"],
			"stats": {
				"move": 6,
				"toughness": 4,
				"save": 3,
				"wounds": wounds_per_model,
				"leadership": leadership,
				"objective_control": 1
			},
			"abilities": []
		},
		"models": models,
		"flags": {}
	}

func _kill_models(unit: Dictionary, count: int) -> void:
	var killed = 0
	for model in unit.models:
		if killed >= count:
			break
		if model.get("alive", true):
			model["alive"] = false
			model["current_wounds"] = 0
			killed += 1

func _setup_game_state_with_below_half_unit(unit_id: String = "U_TEST_A") -> Dictionary:
	"""Set up GameState with a unit below half-strength that needs a battle-shock test."""
	# Create a 10-model unit and kill 6 (4 alive < 5 needed = below half)
	var unit = _create_unit(unit_id, 10, 7, 1)
	_kill_models(unit, 6)

	# Set up in GameState
	GameState.state.units[unit_id] = unit
	GameState.state.meta.phase = GameStateData.Phase.COMMAND
	GameState.state.meta.active_player = 1

	# Ensure player has CP
	GameState.state.players["1"]["cp"] = 3

	return unit


# ==========================================
# Section 1: StratagemManager Basics
# ==========================================

func test_stratagem_manager_loads_insane_bravery():
	"""StratagemManager should have Insane Bravery loaded."""
	var strat = StratagemManager.get_stratagem("insane_bravery")
	assert_false(strat.is_empty(), "Insane Bravery stratagem should be loaded")
	assert_eq(strat.name, "INSANE BRAVERY", "Name should match")
	assert_eq(strat.cp_cost, 1, "CP cost should be 1")

func test_stratagem_manager_loads_all_core_stratagems():
	"""StratagemManager should load all 11 core stratagems."""
	var expected_ids = [
		"insane_bravery", "command_re_roll", "go_to_ground", "smokescreen",
		"epic_challenge", "grenade", "tank_shock", "fire_overwatch",
		"heroic_intervention", "counter_offensive", "rapid_ingress"
	]
	for strat_id in expected_ids:
		var strat = StratagemManager.get_stratagem(strat_id)
		assert_false(strat.is_empty(), "Core stratagem '%s' should be loaded" % strat_id)

func test_get_player_cp():
	"""StratagemManager should correctly read player CP from GameState."""
	GameState.state.players["1"]["cp"] = 5
	assert_eq(StratagemManager.get_player_cp(1), 5, "Should read Player 1 CP")

	GameState.state.players["2"]["cp"] = 2
	assert_eq(StratagemManager.get_player_cp(2), 2, "Should read Player 2 CP")


# ==========================================
# Section 2: Insane Bravery Validation
# ==========================================

func test_can_use_insane_bravery_with_sufficient_cp():
	"""Player with enough CP should be able to use Insane Bravery."""
	GameState.state.players["1"]["cp"] = 3
	GameState.state.meta.phase = GameStateData.Phase.COMMAND
	GameState.state.meta.active_player = 1
	StratagemManager.reset_for_new_game()

	var result = StratagemManager.can_use_stratagem(1, "insane_bravery", "U_TEST")
	assert_true(result.can_use, "Should be able to use with 3 CP")

func test_cannot_use_insane_bravery_with_zero_cp():
	"""Player with 0 CP cannot use Insane Bravery."""
	GameState.state.players["1"]["cp"] = 0
	StratagemManager.reset_for_new_game()

	var result = StratagemManager.can_use_stratagem(1, "insane_bravery", "U_TEST")
	assert_false(result.can_use, "Should not be able to use with 0 CP")
	assert_string_contains(result.reason, "Not enough CP")

func test_cannot_use_insane_bravery_twice_per_battle():
	"""Insane Bravery can only be used once per battle."""
	GameState.state.players["1"]["cp"] = 5
	GameState.state.meta.phase = GameStateData.Phase.COMMAND
	GameState.state.meta.active_player = 1
	StratagemManager.reset_for_new_game()

	# Set up a unit in game state
	_setup_game_state_with_below_half_unit("U_TEST_A")

	# First use should succeed
	var result1 = StratagemManager.use_stratagem(1, "insane_bravery", "U_TEST_A")
	assert_true(result1.success, "First use should succeed")

	# Second use should fail (once per battle)
	var result2 = StratagemManager.can_use_stratagem(1, "insane_bravery", "U_TEST_A")
	assert_false(result2.can_use, "Second use should be blocked")
	assert_string_contains(result2.reason, "once per battle")

func test_insane_bravery_unknown_stratagem_rejected():
	"""Unknown stratagem ID should be rejected."""
	var result = StratagemManager.can_use_stratagem(1, "nonexistent_stratagem", "U_TEST")
	assert_false(result.can_use, "Unknown stratagem should be rejected")


# ==========================================
# Section 3: CP Deduction
# ==========================================

func test_insane_bravery_deducts_1_cp():
	"""Using Insane Bravery should deduct 1 CP."""
	GameState.state.players["1"]["cp"] = 4
	GameState.state.meta.phase = GameStateData.Phase.COMMAND
	GameState.state.meta.active_player = 1
	StratagemManager.reset_for_new_game()

	_setup_game_state_with_below_half_unit("U_TEST_A")

	var result = StratagemManager.use_stratagem(1, "insane_bravery", "U_TEST_A")
	assert_true(result.success, "Use should succeed")

	var cp_after = GameState.state.players["1"]["cp"]
	assert_eq(cp_after, 3, "CP should be deducted from 4 to 3")


# ==========================================
# Section 4: CommandPhase Integration
# ==========================================

func test_command_phase_offers_insane_bravery_for_below_half_unit():
	"""CommandPhase should offer Insane Bravery as an available action for below-half units."""
	StratagemManager.reset_for_new_game()
	_setup_game_state_with_below_half_unit("U_TEST_A")

	var phase = _create_command_phase()
	var state = GameState.create_snapshot()
	phase.enter_phase(state)

	var actions = phase.get_available_actions()

	# Should have both a BATTLE_SHOCK_TEST and USE_STRATAGEM for the unit
	var has_shock_test = false
	var has_insane_bravery = false
	for action in actions:
		if action.get("type", "") == "BATTLE_SHOCK_TEST" and action.get("unit_id", "") == "U_TEST_A":
			has_shock_test = true
		if action.get("type", "") == "USE_STRATAGEM" and action.get("stratagem_id", "") == "insane_bravery":
			has_insane_bravery = true

	assert_true(has_shock_test, "Should offer BATTLE_SHOCK_TEST for below-half unit")
	assert_true(has_insane_bravery, "Should offer INSANE BRAVERY stratagem for below-half unit")

	phase.queue_free()

func test_command_phase_insane_bravery_auto_passes_test():
	"""Using Insane Bravery via CommandPhase should auto-pass the battle-shock test."""
	StratagemManager.reset_for_new_game()
	_setup_game_state_with_below_half_unit("U_TEST_A")

	var phase = _create_command_phase()
	var state = GameState.create_snapshot()
	phase.enter_phase(state)

	# Use Insane Bravery
	var action = {
		"type": "USE_STRATAGEM",
		"stratagem_id": "insane_bravery",
		"target_unit_id": "U_TEST_A"
	}

	var validation = phase.validate_action(action)
	assert_true(validation.valid, "Insane Bravery action should validate: %s" % str(validation.get("errors", [])))

	var result = phase.process_action(action)
	assert_true(result.success, "Insane Bravery should succeed")
	assert_true(result.test_passed, "Test should pass automatically")
	assert_false(result.battle_shocked, "Unit should NOT be battle-shocked")
	assert_true(result.get("auto_passed", false), "Should be flagged as auto-passed")

	# Verify unit is NOT battle-shocked in game state
	var unit = GameState.state.units.get("U_TEST_A", {})
	var is_shocked = unit.get("flags", {}).get("battle_shocked", false)
	assert_false(is_shocked, "Unit should not be battle-shocked after Insane Bravery")

	phase.queue_free()

func test_command_phase_insane_bravery_marks_unit_tested():
	"""After Insane Bravery, the unit should not appear in available actions for testing."""
	StratagemManager.reset_for_new_game()
	_setup_game_state_with_below_half_unit("U_TEST_A")

	var phase = _create_command_phase()
	var state = GameState.create_snapshot()
	phase.enter_phase(state)

	# Use Insane Bravery
	phase.process_action({
		"type": "USE_STRATAGEM",
		"stratagem_id": "insane_bravery",
		"target_unit_id": "U_TEST_A"
	})

	# Check available actions - should no longer have test or stratagem for this unit
	var actions = phase.get_available_actions()
	for action in actions:
		if action.get("unit_id", "") == "U_TEST_A" or action.get("target_unit_id", "") == "U_TEST_A":
			assert_true(false, "Unit should not appear in available actions after using Insane Bravery")

	phase.queue_free()


# ==========================================
# Section 5: Validation Edge Cases
# ==========================================

func test_command_phase_rejects_insane_bravery_for_already_tested_unit():
	"""Can't use Insane Bravery on a unit that already took its test."""
	StratagemManager.reset_for_new_game()
	_setup_game_state_with_below_half_unit("U_TEST_A")

	var phase = _create_command_phase()
	var state = GameState.create_snapshot()
	phase.enter_phase(state)

	# First, roll the normal battle-shock test
	phase.process_action({
		"type": "BATTLE_SHOCK_TEST",
		"unit_id": "U_TEST_A"
	})

	# Now try Insane Bravery - should be rejected (already tested)
	var validation = phase.validate_action({
		"type": "USE_STRATAGEM",
		"stratagem_id": "insane_bravery",
		"target_unit_id": "U_TEST_A"
	})
	assert_false(validation.valid, "Should reject Insane Bravery for already-tested unit")

	phase.queue_free()

func test_command_phase_rejects_insane_bravery_missing_target():
	"""Insane Bravery requires a target unit."""
	StratagemManager.reset_for_new_game()
	_setup_game_state_with_below_half_unit("U_TEST_A")

	var phase = _create_command_phase()
	var state = GameState.create_snapshot()
	phase.enter_phase(state)

	var validation = phase.validate_action({
		"type": "USE_STRATAGEM",
		"stratagem_id": "insane_bravery",
		"target_unit_id": ""
	})
	assert_false(validation.valid, "Should reject Insane Bravery without target")

	phase.queue_free()

func test_command_phase_rejects_insane_bravery_for_unit_not_needing_test():
	"""Can't use Insane Bravery on a unit that doesn't need a battle-shock test."""
	StratagemManager.reset_for_new_game()

	# Create a full-strength unit (doesn't need battle-shock test)
	var unit = _create_unit("U_FULL", 10, 7, 1)
	GameState.state.units["U_FULL"] = unit
	GameState.state.meta.phase = GameStateData.Phase.COMMAND
	GameState.state.meta.active_player = 1
	GameState.state.players["1"]["cp"] = 3

	var phase = _create_command_phase()
	var state = GameState.create_snapshot()
	phase.enter_phase(state)

	var validation = phase.validate_action({
		"type": "USE_STRATAGEM",
		"stratagem_id": "insane_bravery",
		"target_unit_id": "U_FULL"
	})
	assert_false(validation.valid, "Should reject Insane Bravery for unit not needing test")

	phase.queue_free()


# ==========================================
# Section 6: StratagemManager Reset
# ==========================================

func test_reset_clears_usage_history():
	"""reset_for_new_game should clear all usage tracking."""
	GameState.state.players["1"]["cp"] = 5
	GameState.state.meta.phase = GameStateData.Phase.COMMAND
	GameState.state.meta.active_player = 1

	_setup_game_state_with_below_half_unit("U_TEST_A")

	# Use a stratagem
	StratagemManager.reset_for_new_game()
	StratagemManager.use_stratagem(1, "insane_bravery", "U_TEST_A")

	# Can't use again (once per battle)
	var result_before = StratagemManager.can_use_stratagem(1, "insane_bravery", "U_TEST_A")
	assert_false(result_before.can_use, "Should be blocked before reset")

	# Reset
	StratagemManager.reset_for_new_game()

	# Should be available again
	GameState.state.players["1"]["cp"] = 5
	var result_after = StratagemManager.can_use_stratagem(1, "insane_bravery", "U_TEST_A")
	assert_true(result_after.can_use, "Should be available after reset")
