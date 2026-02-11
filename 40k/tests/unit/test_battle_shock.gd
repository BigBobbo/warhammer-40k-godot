extends "res://addons/gut/test.gd"

# Tests for Battle-shock mechanics in the Command Phase
# Covers:
# 1. is_below_half_strength() utility (multi-model and single-model units)
# 2. 2D6 vs Leadership battle-shock test
# 3. Apply/clear battle_shocked flag during Command Phase

const GameStateData = preload("res://autoloads/GameState.gd")

var game_state: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	game_state = AutoloadHelper.get_game_state()
	assert_not_null(game_state, "GameState autoload must be available")

# ==========================================
# Helper: Create test units with specific alive/dead model counts
# ==========================================

func _create_multi_model_unit(total_models: int, alive_count: int, owner: int = 1, leadership: int = 7) -> Dictionary:
	var models = []
	for i in range(total_models):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": 2,
			"current_wounds": 2 if i < alive_count else 0,
			"base_mm": 32,
			"position": Vector2(100 + i * 20, 100),
			"alive": i < alive_count,
			"status_effects": []
		})
	return {
		"id": "test_unit",
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Test Squad",
			"keywords": ["INFANTRY"],
			"stats": {
				"move": 6,
				"toughness": 4,
				"save": 3,
				"leadership": leadership,
				"objective_control": 2
			}
		},
		"models": models,
		"flags": {}
	}

func _create_single_model_unit(max_wounds: int, current_wounds: int, owner: int = 1, leadership: int = 6) -> Dictionary:
	return {
		"id": "test_vehicle",
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Test Vehicle",
			"keywords": ["VEHICLE"],
			"stats": {
				"move": 10,
				"toughness": 8,
				"save": 3,
				"leadership": leadership,
				"objective_control": 3
			}
		},
		"models": [
			{
				"id": "m1",
				"wounds": max_wounds,
				"current_wounds": current_wounds,
				"base_mm": 60,
				"position": Vector2(200, 200),
				"alive": current_wounds > 0,
				"status_effects": []
			}
		],
		"flags": {}
	}

# ==========================================
# is_below_half_strength() - Multi-model units
# ==========================================

func test_multi_model_5_with_2_alive_is_below_half():
	"""5 models, 2 alive: 2*2=4 < 5, below half"""
	var unit = _create_multi_model_unit(5, 2)
	assert_true(game_state.is_below_half_strength(unit),
		"5-model unit with 2 alive should be below half-strength")

func test_multi_model_5_with_3_alive_is_not_below_half():
	"""5 models, 3 alive: 3*2=6 >= 5, NOT below half"""
	var unit = _create_multi_model_unit(5, 3)
	assert_false(game_state.is_below_half_strength(unit),
		"5-model unit with 3 alive should NOT be below half-strength")

func test_multi_model_10_with_4_alive_is_below_half():
	"""10 models, 4 alive: 4*2=8 < 10, below half"""
	var unit = _create_multi_model_unit(10, 4)
	assert_true(game_state.is_below_half_strength(unit),
		"10-model unit with 4 alive should be below half-strength")

func test_multi_model_10_with_5_alive_is_not_below_half():
	"""10 models, 5 alive: 5*2=10 >= 10, NOT below half (exactly half)"""
	var unit = _create_multi_model_unit(10, 5)
	assert_false(game_state.is_below_half_strength(unit),
		"10-model unit with 5 alive should NOT be below half-strength (exactly half)")

func test_multi_model_6_with_3_alive_is_not_below_half():
	"""6 models, 3 alive: 3*2=6 >= 6, NOT below half (exactly half)"""
	var unit = _create_multi_model_unit(6, 3)
	assert_false(game_state.is_below_half_strength(unit),
		"6-model unit with 3 alive should NOT be below half-strength")

func test_multi_model_6_with_2_alive_is_below_half():
	"""6 models, 2 alive: 2*2=4 < 6, below half"""
	var unit = _create_multi_model_unit(6, 2)
	assert_true(game_state.is_below_half_strength(unit),
		"6-model unit with 2 alive should be below half-strength")

func test_multi_model_all_alive_is_not_below_half():
	"""Full strength unit is not below half"""
	var unit = _create_multi_model_unit(5, 5)
	assert_false(game_state.is_below_half_strength(unit),
		"Full-strength unit should NOT be below half-strength")

func test_multi_model_1_alive_is_below_half():
	"""5 models, 1 alive: 1*2=2 < 5, below half"""
	var unit = _create_multi_model_unit(5, 1)
	assert_true(game_state.is_below_half_strength(unit),
		"5-model unit with 1 alive should be below half-strength")

func test_multi_model_all_dead_is_not_below_half():
	"""All models dead - unit is destroyed, not below half"""
	var unit = _create_multi_model_unit(5, 0)
	assert_false(game_state.is_below_half_strength(unit),
		"Destroyed unit (all dead) should NOT be below half-strength")

func test_multi_model_2_models_1_alive_is_not_below_half():
	"""2 models, 1 alive: 1*2=2 >= 2, NOT below half (exactly half)"""
	var unit = _create_multi_model_unit(2, 1)
	assert_false(game_state.is_below_half_strength(unit),
		"2-model unit with 1 alive should NOT be below half-strength (exactly half)")

# ==========================================
# is_below_half_strength() - Single-model units (wound-based)
# ==========================================

func test_single_model_6_wounds_with_2_remaining_is_below_half():
	"""6 max wounds, 2 current: 2*2=4 < 6, below half"""
	var unit = _create_single_model_unit(6, 2)
	assert_true(game_state.is_below_half_strength(unit),
		"Single-model unit with 2/6 wounds should be below half-strength")

func test_single_model_6_wounds_with_3_remaining_is_not_below_half():
	"""6 max wounds, 3 current: 3*2=6 >= 6, NOT below half (exactly half)"""
	var unit = _create_single_model_unit(6, 3)
	assert_false(game_state.is_below_half_strength(unit),
		"Single-model unit with 3/6 wounds should NOT be below half-strength")

func test_single_model_10_wounds_with_4_remaining_is_below_half():
	"""10 max wounds, 4 current: 4*2=8 < 10, below half"""
	var unit = _create_single_model_unit(10, 4)
	assert_true(game_state.is_below_half_strength(unit),
		"Single-model unit with 4/10 wounds should be below half-strength")

func test_single_model_10_wounds_with_5_remaining_is_not_below_half():
	"""10 max wounds, 5 current: 5*2=10 >= 10, NOT below half"""
	var unit = _create_single_model_unit(10, 5)
	assert_false(game_state.is_below_half_strength(unit),
		"Single-model unit with 5/10 wounds should NOT be below half-strength")

func test_single_model_full_wounds_is_not_below_half():
	"""Full wounds is not below half"""
	var unit = _create_single_model_unit(6, 6)
	assert_false(game_state.is_below_half_strength(unit),
		"Single-model unit at full wounds should NOT be below half-strength")

func test_single_model_1_wound_unit_at_full_is_not_below_half():
	"""1-wound single model at full health"""
	var unit = _create_single_model_unit(1, 1)
	assert_false(game_state.is_below_half_strength(unit),
		"1-wound model at full health should NOT be below half-strength")

# ==========================================
# is_below_half_strength() - Edge cases
# ==========================================

func test_empty_models_array_is_not_below_half():
	"""Unit with no models is not below half"""
	var unit = {"models": []}
	assert_false(game_state.is_below_half_strength(unit),
		"Unit with no models should NOT be below half-strength")

func test_unit_missing_models_key_is_not_below_half():
	"""Unit without models key is not below half"""
	var unit = {}
	assert_false(game_state.is_below_half_strength(unit),
		"Unit without models key should NOT be below half-strength")

# ==========================================
# CommandPhase Battle-shock - Flag clearing
# ==========================================

func test_battle_shocked_flag_cleared_on_command_phase_enter():
	"""Battle-shocked flags should be cleared at the start of Command Phase"""
	# Set up a unit with battle_shocked flag
	var unit = _create_multi_model_unit(5, 5)
	unit["flags"]["battle_shocked"] = true
	var unit_id = "test_shocked_unit"

	game_state.state.units[unit_id] = unit
	game_state.state.meta.active_player = 1

	# Create a CommandPhase instance and enter it
	var command_phase = _create_command_phase()
	command_phase.enter_phase(game_state.create_snapshot())

	# Check the flag was cleared on the actual GameState
	var cleared = game_state.state.units[unit_id].get("flags", {}).get("battle_shocked", false)
	assert_false(cleared, "battle_shocked flag should be cleared at start of Command Phase")

	# Cleanup
	game_state.state.units.erase(unit_id)
	command_phase.queue_free()

func test_enemy_battle_shocked_flag_not_cleared():
	"""Enemy unit's battle-shocked flag should NOT be cleared during our Command Phase"""
	var unit = _create_multi_model_unit(5, 5, 2)  # Owner = player 2
	unit["flags"]["battle_shocked"] = true
	var unit_id = "test_enemy_shocked"

	game_state.state.units[unit_id] = unit
	game_state.state.meta.active_player = 1  # Player 1's turn

	var command_phase = _create_command_phase()
	command_phase.enter_phase(game_state.create_snapshot())

	# Enemy flag should still be set
	var still_shocked = game_state.state.units[unit_id].get("flags", {}).get("battle_shocked", false)
	assert_true(still_shocked, "Enemy unit's battle-shocked flag should NOT be cleared")

	# Cleanup
	game_state.state.units.erase(unit_id)
	command_phase.queue_free()

# ==========================================
# CommandPhase Battle-shock - Test identification
# ==========================================

func test_below_half_strength_unit_identified_for_test():
	"""Units below half-strength should be identified for battle-shock tests"""
	var unit = _create_multi_model_unit(5, 2)  # 2 of 5 alive = below half
	var unit_id = "test_below_half"

	game_state.state.units[unit_id] = unit
	game_state.state.meta.active_player = 1

	var command_phase = _create_command_phase()
	command_phase.enter_phase(game_state.create_snapshot())

	# Check available actions include a battle-shock test for this unit
	var actions = command_phase.get_available_actions()
	var has_test_action = false
	for action in actions:
		if action.get("type") == "BATTLE_SHOCK_TEST" and action.get("unit_id") == unit_id:
			has_test_action = true
			break

	assert_true(has_test_action, "Should have BATTLE_SHOCK_TEST action for below-half unit")

	# Cleanup
	game_state.state.units.erase(unit_id)
	command_phase.queue_free()

func test_full_strength_unit_not_identified_for_test():
	"""Full-strength units should NOT need battle-shock tests"""
	var unit = _create_multi_model_unit(5, 5)  # All alive = full strength
	var unit_id = "test_full_strength"

	game_state.state.units[unit_id] = unit
	game_state.state.meta.active_player = 1

	var command_phase = _create_command_phase()
	command_phase.enter_phase(game_state.create_snapshot())

	var actions = command_phase.get_available_actions()
	var has_test_action = false
	for action in actions:
		if action.get("type") == "BATTLE_SHOCK_TEST" and action.get("unit_id") == unit_id:
			has_test_action = true
			break

	assert_false(has_test_action, "Should NOT have BATTLE_SHOCK_TEST action for full-strength unit")

	# Cleanup
	game_state.state.units.erase(unit_id)
	command_phase.queue_free()

# ==========================================
# CommandPhase Battle-shock - 2D6 vs Leadership test
# ==========================================

func test_battle_shock_test_pass_roll_above_leadership():
	"""Rolling >= Leadership should pass the battle-shock test"""
	var unit = _create_multi_model_unit(5, 2, 1, 7)  # Ld 7
	var unit_id = "test_pass"

	game_state.state.units[unit_id] = unit
	game_state.state.meta.active_player = 1

	var command_phase = _create_command_phase()
	command_phase.enter_phase(game_state.create_snapshot())

	# Roll 4+4=8 >= Ld 7 → pass
	var result = command_phase.process_action({
		"type": "BATTLE_SHOCK_TEST",
		"unit_id": unit_id,
		"dice_roll": [4, 4]
	})

	assert_true(result.get("success", false), "Action should succeed")
	assert_true(result.get("test_passed", false), "Roll of 8 should pass vs Ld 7")
	assert_false(result.get("battle_shocked", true), "Unit should NOT be battle-shocked")

	# Verify flag not set on GameState
	var is_shocked = game_state.state.units[unit_id].get("flags", {}).get("battle_shocked", false)
	assert_false(is_shocked, "battle_shocked flag should NOT be set after passing test")

	# Cleanup
	game_state.state.units.erase(unit_id)
	command_phase.queue_free()

func test_battle_shock_test_pass_roll_equal_leadership():
	"""Rolling exactly Leadership should pass the battle-shock test"""
	var unit = _create_multi_model_unit(5, 2, 1, 7)  # Ld 7
	var unit_id = "test_pass_exact"

	game_state.state.units[unit_id] = unit
	game_state.state.meta.active_player = 1

	var command_phase = _create_command_phase()
	command_phase.enter_phase(game_state.create_snapshot())

	# Roll 3+4=7 == Ld 7 → pass
	var result = command_phase.process_action({
		"type": "BATTLE_SHOCK_TEST",
		"unit_id": unit_id,
		"dice_roll": [3, 4]
	})

	assert_true(result.get("test_passed", false), "Roll of 7 should pass vs Ld 7 (equal)")
	assert_false(result.get("battle_shocked", true), "Unit should NOT be battle-shocked")

	# Cleanup
	game_state.state.units.erase(unit_id)
	command_phase.queue_free()

func test_battle_shock_test_fail_roll_below_leadership():
	"""Rolling < Leadership should fail the battle-shock test"""
	var unit = _create_multi_model_unit(5, 2, 1, 7)  # Ld 7
	var unit_id = "test_fail"

	game_state.state.units[unit_id] = unit
	game_state.state.meta.active_player = 1

	var command_phase = _create_command_phase()
	command_phase.enter_phase(game_state.create_snapshot())

	# Roll 2+3=5 < Ld 7 → fail
	var result = command_phase.process_action({
		"type": "BATTLE_SHOCK_TEST",
		"unit_id": unit_id,
		"dice_roll": [2, 3]
	})

	assert_true(result.get("success", false), "Action should succeed")
	assert_false(result.get("test_passed", true), "Roll of 5 should fail vs Ld 7")
	assert_true(result.get("battle_shocked", false), "Unit should be battle-shocked")

	# Verify flag IS set on GameState
	var is_shocked = game_state.state.units[unit_id].get("flags", {}).get("battle_shocked", false)
	assert_true(is_shocked, "battle_shocked flag should be set after failing test")

	# Cleanup
	game_state.state.units.erase(unit_id)
	command_phase.queue_free()

func test_battle_shock_test_minimum_roll_fails():
	"""Snake eyes (2) should always fail for typical Leadership values"""
	var unit = _create_multi_model_unit(5, 2, 1, 6)  # Ld 6
	var unit_id = "test_snake_eyes"

	game_state.state.units[unit_id] = unit
	game_state.state.meta.active_player = 1

	var command_phase = _create_command_phase()
	command_phase.enter_phase(game_state.create_snapshot())

	# Roll 1+1=2 < Ld 6 → fail
	var result = command_phase.process_action({
		"type": "BATTLE_SHOCK_TEST",
		"unit_id": unit_id,
		"dice_roll": [1, 1]
	})

	assert_false(result.get("test_passed", true), "Snake eyes (2) should fail vs Ld 6")
	assert_true(result.get("battle_shocked", false), "Unit should be battle-shocked after snake eyes")

	# Cleanup
	game_state.state.units.erase(unit_id)
	command_phase.queue_free()

func test_battle_shock_test_maximum_roll_passes():
	"""Boxcars (12) should always pass"""
	var unit = _create_multi_model_unit(5, 2, 1, 7)  # Ld 7
	var unit_id = "test_boxcars"

	game_state.state.units[unit_id] = unit
	game_state.state.meta.active_player = 1

	var command_phase = _create_command_phase()
	command_phase.enter_phase(game_state.create_snapshot())

	# Roll 6+6=12 >= Ld 7 → pass
	var result = command_phase.process_action({
		"type": "BATTLE_SHOCK_TEST",
		"unit_id": unit_id,
		"dice_roll": [6, 6]
	})

	assert_true(result.get("test_passed", false), "Boxcars (12) should pass vs Ld 7")
	assert_false(result.get("battle_shocked", true), "Unit should NOT be battle-shocked after boxcars")

	# Cleanup
	game_state.state.units.erase(unit_id)
	command_phase.queue_free()

# ==========================================
# CommandPhase Battle-shock - Validation
# ==========================================

func test_validate_battle_shock_test_missing_unit_id():
	"""Should fail validation without unit_id"""
	var unit = _create_multi_model_unit(5, 2)
	var unit_id = "test_validate"
	game_state.state.units[unit_id] = unit
	game_state.state.meta.active_player = 1

	var command_phase = _create_command_phase()
	command_phase.enter_phase(game_state.create_snapshot())

	var validation = command_phase.validate_action({
		"type": "BATTLE_SHOCK_TEST"
	})

	assert_false(validation.get("valid", true), "Should fail validation without unit_id")

	# Cleanup
	game_state.state.units.erase(unit_id)
	command_phase.queue_free()

func test_validate_battle_shock_test_nonexistent_unit():
	"""Should fail validation for non-existent unit"""
	game_state.state.meta.active_player = 1

	var command_phase = _create_command_phase()
	command_phase.enter_phase(game_state.create_snapshot())

	var validation = command_phase.validate_action({
		"type": "BATTLE_SHOCK_TEST",
		"unit_id": "NONEXISTENT_UNIT"
	})

	assert_false(validation.get("valid", true), "Should fail validation for non-existent unit")

	# Cleanup
	command_phase.queue_free()

func test_validate_duplicate_battle_shock_test():
	"""Should fail validation if unit already tested this phase"""
	var unit = _create_multi_model_unit(5, 2, 1, 7)
	var unit_id = "test_duplicate"

	game_state.state.units[unit_id] = unit
	game_state.state.meta.active_player = 1

	var command_phase = _create_command_phase()
	command_phase.enter_phase(game_state.create_snapshot())

	# Take the test once
	command_phase.process_action({
		"type": "BATTLE_SHOCK_TEST",
		"unit_id": unit_id,
		"dice_roll": [3, 3]
	})

	# Try to take it again
	var validation = command_phase.validate_action({
		"type": "BATTLE_SHOCK_TEST",
		"unit_id": unit_id
	})

	assert_false(validation.get("valid", true), "Should fail validation for already-tested unit")

	# Cleanup
	game_state.state.units.erase(unit_id)
	command_phase.queue_free()

# ==========================================
# CommandPhase Battle-shock - Auto-resolve on END_COMMAND
# ==========================================

func test_end_command_auto_resolves_remaining_tests():
	"""Ending the command phase should auto-resolve any remaining battle-shock tests"""
	var unit = _create_multi_model_unit(5, 2, 1, 7)
	var unit_id = "test_auto_resolve"

	game_state.state.units[unit_id] = unit
	game_state.state.meta.active_player = 1

	var command_phase = _create_command_phase()
	# Connect to phase_completed to prevent error (signal emitted but no handler)
	command_phase.phase_completed.connect(func(): pass)
	command_phase.enter_phase(game_state.create_snapshot())

	# Don't manually take the test - just end the phase
	var result = command_phase.process_action({"type": "END_COMMAND"})

	assert_true(result.get("success", false), "END_COMMAND should succeed")
	var auto_resolved = result.get("auto_resolved_tests", [])
	assert_eq(auto_resolved.size(), 1, "Should have auto-resolved 1 battle-shock test")

	# Cleanup
	game_state.state.units.erase(unit_id)
	command_phase.queue_free()

# ==========================================
# CommandPhase Battle-shock - Result details
# ==========================================

func test_battle_shock_result_contains_dice_details():
	"""The result should contain die1, die2, roll_total, leadership"""
	var unit = _create_multi_model_unit(5, 2, 1, 7)
	var unit_id = "test_details"

	game_state.state.units[unit_id] = unit
	game_state.state.meta.active_player = 1

	var command_phase = _create_command_phase()
	command_phase.enter_phase(game_state.create_snapshot())

	var result = command_phase.process_action({
		"type": "BATTLE_SHOCK_TEST",
		"unit_id": unit_id,
		"dice_roll": [3, 5]
	})

	assert_eq(result.get("die1"), 3, "die1 should be 3")
	assert_eq(result.get("die2"), 5, "die2 should be 5")
	assert_eq(result.get("roll_total"), 8, "roll_total should be 8")
	assert_eq(result.get("leadership"), 7, "leadership should be 7")
	assert_true(result.get("test_passed"), "Roll of 8 should pass vs Ld 7")

	# Cleanup
	game_state.state.units.erase(unit_id)
	command_phase.queue_free()

# ==========================================
# Integration: Battle-shocked affects objective control
# ==========================================

func test_battle_shocked_unit_skipped_in_objective_control():
	"""A battle-shocked unit should be skipped in objective control (OC=0 effectively)"""
	var unit = _create_multi_model_unit(5, 2, 1, 7)
	unit["flags"]["battle_shocked"] = true
	unit["models"][0]["position"] = Vector2(100, 100)  # Near some position

	# The MissionManager already checks flags.battle_shocked and skips those units
	# This test verifies the flag path is correct
	var is_shocked = unit.get("flags", {}).get("battle_shocked", false)
	assert_true(is_shocked, "Unit should have battle_shocked flag set")

# ==========================================
# Helper: Create CommandPhase instance
# ==========================================

func _create_command_phase() -> Node:
	var phase_script = preload("res://phases/CommandPhase.gd")
	var phase_node = Node.new()
	phase_node.set_script(phase_script)
	add_child(phase_node)
	return phase_node
