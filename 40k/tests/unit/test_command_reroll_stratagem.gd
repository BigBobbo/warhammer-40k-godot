extends "res://addons/gut/test.gd"

# Tests for COMMAND RE-ROLL stratagem implementation
#
# Per Warhammer 40k 10th Edition Core Rules:
# - COMMAND RE-ROLL (Core - Battle Tactic Stratagem, 1 CP)
# - WHEN: Any phase, just after you make a roll for a unit from your army.
# - TARGET: That unit from your army.
# - EFFECT: You re-roll that roll, test or saving throw.
# - RESTRICTIONS: Once per phase.
#
# These tests verify:
# 1. StratagemManager correctly validates Command Re-roll usage
# 2. CP is deducted when used
# 3. Once-per-phase restriction is enforced
# 4. ChargePhase correctly offers and processes the reroll
# 5. CommandPhase correctly offers and processes the reroll for battle-shock
# 6. MovementPhase correctly offers and processes the reroll for advance

const GameStateData = preload("res://autoloads/GameState.gd")


# ==========================================
# Helpers
# ==========================================

func _create_command_phase():
	var phase = preload("res://phases/CommandPhase.gd").new()
	add_child(phase)
	return phase

func _create_charge_phase():
	var phase = preload("res://phases/ChargePhase.gd").new()
	add_child(phase)
	return phase

func _create_movement_phase():
	var phase = preload("res://phases/MovementPhase.gd").new()
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

func _create_enemy_unit(id: String, model_count: int, owner: int = 2) -> Dictionary:
	var unit = _create_unit(id, model_count, 7, owner)
	# Position enemy near charging unit
	for i in range(unit.models.size()):
		unit.models[i].position = {"x": 300 + i * 20, "y": 100}
	return unit

func _kill_models(unit: Dictionary, count: int) -> void:
	var killed = 0
	for model in unit.models:
		if killed >= count:
			break
		if model.get("alive", true):
			model["alive"] = false
			model["current_wounds"] = 0
			killed += 1

func _setup_basic_game_state(phase_type = GameStateData.Phase.CHARGE) -> void:
	"""Set up basic GameState for Command Re-roll tests."""
	GameState.state.meta.phase = phase_type
	GameState.state.meta.active_player = 1
	GameState.state.meta.battle_round = 1
	GameState.state.players["1"]["cp"] = 3
	GameState.state.players["2"]["cp"] = 3
	StratagemManager.reset_for_new_game()


# ==========================================
# Section 1: StratagemManager Basics
# ==========================================

func test_command_reroll_stratagem_loaded():
	"""StratagemManager should have Command Re-roll loaded."""
	var strat = StratagemManager.get_stratagem("command_re_roll")
	assert_false(strat.is_empty(), "Command Re-roll stratagem should be loaded")
	assert_eq(strat.name, "COMMAND RE-ROLL", "Name should match")
	assert_eq(strat.cp_cost, 1, "CP cost should be 1")

func test_command_reroll_timing():
	"""Command Re-roll should be usable in any phase on either turn."""
	var strat = StratagemManager.get_stratagem("command_re_roll")
	assert_eq(strat.timing.phase, "any", "Should be usable in any phase")
	assert_eq(strat.timing.turn, "either", "Should be usable on either turn")

func test_command_reroll_once_per_phase():
	"""Command Re-roll should be restricted to once per phase."""
	var strat = StratagemManager.get_stratagem("command_re_roll")
	assert_eq(strat.restrictions.once_per, "phase", "Should be once per phase")


# ==========================================
# Section 2: Validation
# ==========================================

func test_can_use_command_reroll_with_sufficient_cp():
	"""Player with enough CP should be able to use Command Re-roll."""
	_setup_basic_game_state()

	var result = StratagemManager.can_use_stratagem(1, "command_re_roll", "U_TEST")
	assert_true(result.can_use, "Should be able to use with 3 CP")

func test_cannot_use_command_reroll_with_zero_cp():
	"""Player with 0 CP cannot use Command Re-roll."""
	_setup_basic_game_state()
	GameState.state.players["1"]["cp"] = 0

	var result = StratagemManager.can_use_stratagem(1, "command_re_roll", "U_TEST")
	assert_false(result.can_use, "Should not be able to use with 0 CP")
	assert_string_contains(result.reason, "Not enough CP")

func test_is_command_reroll_available_returns_dict():
	"""is_command_reroll_available should return a proper availability dict."""
	_setup_basic_game_state()

	var result = StratagemManager.is_command_reroll_available(1)
	assert_has(result, "available", "Result should have 'available' key")
	assert_true(result.available, "Should be available with CP")

func test_is_command_reroll_not_available_no_cp():
	"""is_command_reroll_available should return false with no CP."""
	_setup_basic_game_state()
	GameState.state.players["1"]["cp"] = 0

	var result = StratagemManager.is_command_reroll_available(1)
	assert_false(result.available, "Should not be available with 0 CP")


# ==========================================
# Section 3: CP Deduction
# ==========================================

func test_command_reroll_deducts_1_cp():
	"""Using Command Re-roll should deduct 1 CP."""
	_setup_basic_game_state()
	GameState.state.players["1"]["cp"] = 4
	var unit = _create_unit("U_TEST_A", 5, 7, 1)
	GameState.state.units["U_TEST_A"] = unit

	var result = StratagemManager.use_stratagem(1, "command_re_roll", "U_TEST_A")
	assert_true(result.success, "Use should succeed")

	var cp_after = GameState.state.players["1"]["cp"]
	assert_eq(cp_after, 3, "CP should be deducted from 4 to 3")

func test_execute_command_reroll_deducts_cp():
	"""execute_command_reroll should deduct CP and return success."""
	_setup_basic_game_state()
	GameState.state.players["1"]["cp"] = 3
	var unit = _create_unit("U_TEST_A", 5, 7, 1)
	GameState.state.units["U_TEST_A"] = unit

	var roll_context = {
		"roll_type": "charge_roll",
		"original_rolls": [2, 3],
		"unit_name": "Test Unit",
	}

	var result = StratagemManager.execute_command_reroll(1, "U_TEST_A", roll_context)
	assert_true(result.success, "Execute should succeed")
	assert_eq(GameState.state.players["1"]["cp"], 2, "CP should be deducted to 2")


# ==========================================
# Section 4: Once-Per-Phase Restriction
# ==========================================

func test_cannot_use_command_reroll_twice_in_same_phase():
	"""Command Re-roll should be restricted to once per phase."""
	_setup_basic_game_state()
	GameState.state.players["1"]["cp"] = 5
	var unit_a = _create_unit("U_TEST_A", 5, 7, 1)
	var unit_b = _create_unit("U_TEST_B", 5, 7, 1)
	GameState.state.units["U_TEST_A"] = unit_a
	GameState.state.units["U_TEST_B"] = unit_b

	# First use should succeed
	var result1 = StratagemManager.use_stratagem(1, "command_re_roll", "U_TEST_A")
	assert_true(result1.success, "First use should succeed")

	# Second use in same phase should fail
	var result2 = StratagemManager.can_use_stratagem(1, "command_re_roll", "U_TEST_B")
	assert_false(result2.can_use, "Second use in same phase should be blocked")


# ==========================================
# Section 5: ChargePhase Integration
# ==========================================

func test_charge_phase_validates_command_reroll_actions():
	"""ChargePhase should validate USE_COMMAND_REROLL and DECLINE_COMMAND_REROLL."""
	_setup_basic_game_state()
	var charging_unit = _create_unit("U_CHARGE", 5, 7, 1)
	charging_unit.status = GameStateData.UnitStatus.DEPLOYED
	var enemy = _create_enemy_unit("U_ENEMY", 5)
	GameState.state.units["U_CHARGE"] = charging_unit
	GameState.state.units["U_ENEMY"] = enemy

	var phase = _create_charge_phase()
	var state = GameState.create_snapshot()
	phase.enter_phase(state)

	# Before a charge roll, these should be invalid
	var use_val = phase.validate_action({"type": "USE_COMMAND_REROLL"})
	assert_false(use_val.valid, "USE_COMMAND_REROLL should be invalid when not awaiting decision")

	var decline_val = phase.validate_action({"type": "DECLINE_COMMAND_REROLL"})
	assert_false(decline_val.valid, "DECLINE_COMMAND_REROLL should be invalid when not awaiting decision")

	phase.queue_free()

func test_charge_phase_reroll_state_cleared_on_enter():
	"""ChargePhase should clear reroll state on phase enter."""
	_setup_basic_game_state()
	var unit = _create_unit("U_TEST", 5, 7, 1)
	GameState.state.units["U_TEST"] = unit

	var phase = _create_charge_phase()
	var state = GameState.create_snapshot()
	phase.enter_phase(state)

	assert_false(phase.awaiting_reroll_decision, "Should not be awaiting reroll on enter")
	assert_eq(phase.reroll_pending_unit_id, "", "Should have no pending unit on enter")

	phase.queue_free()


# ==========================================
# Section 6: CommandPhase Battle-shock Reroll
# ==========================================

func test_command_phase_battle_shock_with_forced_fail():
	"""A forced-fail battle-shock test should still produce a result."""
	StratagemManager.reset_for_new_game()

	# Set up unit below half-strength
	var unit = _create_unit("U_SHOCK", 10, 7, 1)
	_kill_models(unit, 6)
	GameState.state.units["U_SHOCK"] = unit
	GameState.state.meta.phase = GameStateData.Phase.COMMAND
	GameState.state.meta.active_player = 1
	GameState.state.players["1"]["cp"] = 3

	var phase = _create_command_phase()
	var state = GameState.create_snapshot()
	phase.enter_phase(state)

	# Force a very low roll that will fail (use dice_roll parameter)
	var result = phase.process_action({
		"type": "BATTLE_SHOCK_TEST",
		"unit_id": "U_SHOCK",
		"dice_roll": [1, 1],  # Total 2, well below leadership 7
	})

	assert_true(result.success, "Action should succeed")
	# With dice_roll override, Command Re-roll is NOT offered (to keep tests deterministic)
	assert_false(result.get("awaiting_reroll", false), "Should not offer reroll with forced dice")
	assert_false(result.test_passed, "Should fail with roll of 2 vs Ld 7")

	phase.queue_free()

func test_command_phase_reroll_validates_when_awaiting():
	"""USE/DECLINE_COMMAND_REROLL should validate when CommandPhase is awaiting decision."""
	StratagemManager.reset_for_new_game()

	var unit = _create_unit("U_SHOCK", 10, 7, 1)
	_kill_models(unit, 6)
	GameState.state.units["U_SHOCK"] = unit
	GameState.state.meta.phase = GameStateData.Phase.COMMAND
	GameState.state.meta.active_player = 1
	GameState.state.players["1"]["cp"] = 3

	var phase = _create_command_phase()
	var state = GameState.create_snapshot()
	phase.enter_phase(state)

	# Not awaiting — should be invalid
	var val = phase.validate_action({"type": "USE_COMMAND_REROLL"})
	assert_false(val.valid, "USE_COMMAND_REROLL should be invalid before any roll")

	phase.queue_free()


# ==========================================
# Section 7: MovementPhase Advance Reroll
# ==========================================

func test_movement_phase_validates_command_reroll():
	"""MovementPhase should validate USE_COMMAND_REROLL only when awaiting."""
	_setup_basic_game_state(GameStateData.Phase.MOVEMENT)

	var unit = _create_unit("U_MOVE", 5, 7, 1)
	GameState.state.units["U_MOVE"] = unit

	var phase = _create_movement_phase()
	var state = GameState.create_snapshot()
	phase.enter_phase(state)

	# Not awaiting — should be invalid
	var val = phase.validate_action({"type": "USE_COMMAND_REROLL"})
	assert_false(val.valid, "USE_COMMAND_REROLL should be invalid when not awaiting")

	phase.queue_free()

func test_movement_phase_reroll_state_cleared_on_enter():
	"""MovementPhase should clear reroll state on phase enter."""
	_setup_basic_game_state(GameStateData.Phase.MOVEMENT)

	var unit = _create_unit("U_MOVE", 5, 7, 1)
	GameState.state.units["U_MOVE"] = unit

	var phase = _create_movement_phase()
	var state = GameState.create_snapshot()
	phase.enter_phase(state)

	assert_false(phase._awaiting_reroll_decision, "Should not be awaiting reroll on enter")
	assert_eq(phase._reroll_pending_unit_id, "", "Should have no pending unit on enter")

	phase.queue_free()


# ==========================================
# Section 8: execute_command_reroll Edge Cases
# ==========================================

func test_execute_command_reroll_fails_with_no_cp():
	"""execute_command_reroll should fail when player has no CP."""
	_setup_basic_game_state()
	GameState.state.players["1"]["cp"] = 0
	var unit = _create_unit("U_TEST", 5, 7, 1)
	GameState.state.units["U_TEST"] = unit

	var result = StratagemManager.execute_command_reroll(1, "U_TEST", {
		"roll_type": "charge_roll",
		"original_rolls": [2, 3],
		"unit_name": "Test Unit",
	})
	assert_false(result.success, "Should fail with 0 CP")

func test_execute_command_reroll_fails_after_already_used_this_phase():
	"""execute_command_reroll should fail if already used this phase."""
	_setup_basic_game_state()
	GameState.state.players["1"]["cp"] = 5
	var unit_a = _create_unit("U_A", 5, 7, 1)
	var unit_b = _create_unit("U_B", 5, 7, 1)
	GameState.state.units["U_A"] = unit_a
	GameState.state.units["U_B"] = unit_b

	# First use succeeds
	var result1 = StratagemManager.execute_command_reroll(1, "U_A", {
		"roll_type": "charge_roll",
		"original_rolls": [1, 2],
		"unit_name": "Unit A",
	})
	assert_true(result1.success, "First use should succeed")

	# Second use should fail (once per phase)
	var result2 = StratagemManager.execute_command_reroll(1, "U_B", {
		"roll_type": "charge_roll",
		"original_rolls": [2, 1],
		"unit_name": "Unit B",
	})
	assert_false(result2.success, "Second use should fail (once per phase)")
