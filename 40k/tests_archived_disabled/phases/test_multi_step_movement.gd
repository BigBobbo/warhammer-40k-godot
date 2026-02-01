extends "res://addons/gut/test.gd"
const GameStateData = preload("res://autoloads/GameState.gd")

# Test for multi-step movement feature (GitHub Issue #16)

var phase: MovementPhase

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	phase = preload("res://phases/MovementPhase.gd").new()

	# Create a minimal game state for testing
	var test_state = {
		"game_id": "test_game",
		"turn": 1,
		"phase": GameStateData.Phase.MOVEMENT,
		"active_player": 1,
		"units": {
			"unit_1": {
				"owner": 1,
				"status": GameStateData.UnitStatus.DEPLOYED,
				"meta": {
					"name": "Test Unit",
					"stats": {"move": 6}
				},
				"models": [
					{
						"id": "m1",
						"alive": true,
						"position": {"x": 100, "y": 100},
						"base_mm": 32
					}
				],
				"flags": {}
			}
		},
		"board": {
			"terrain": []
		}
	}
	
	phase.game_state_snapshot = test_state

func test_staged_movement_state_initialization():
	# Begin a normal move
	var action = {
		"type": "BEGIN_NORMAL_MOVE",
		"actor_unit_id": "unit_1",
		"payload": {}
	}
	
	var result = phase.process_action(action)
	assert_true(result.success)
	
	# Check that staged movement fields are initialized
	var move_data = phase.active_moves.get("unit_1", {})
	assert_has(move_data, "staged_moves")
	assert_has(move_data, "accumulated_distance")
	assert_has(move_data, "original_positions")
	assert_eq(move_data.staged_moves, [])
	assert_eq(move_data.accumulated_distance, 0.0)
	assert_eq(move_data.original_positions, {})

func test_stage_model_move_action():
	# Begin a normal move first
	phase.process_action({
		"type": "BEGIN_NORMAL_MOVE",
		"actor_unit_id": "unit_1",
		"payload": {}
	})
	
	# Stage a model move
	var stage_action = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "unit_1",
		"payload": {
			"model_id": "m1",
			"dest": [103, 100]  # 3 inches to the right
		}
	}
	
	var result = phase.process_action(stage_action)
	assert_true(result.success)
	assert_has(result, "staged")
	assert_true(result.staged)
	
	# Check staged moves
	var move_data = phase.active_moves["unit_1"]
	assert_eq(move_data.staged_moves.size(), 1)
	assert_gt(move_data.accumulated_distance, 0.0)

func test_multiple_staged_moves():
	# Begin a normal move
	phase.process_action({
		"type": "BEGIN_NORMAL_MOVE",
		"actor_unit_id": "unit_1",
		"payload": {}
	})
	
	# First staged move (3 inches)
	phase.process_action({
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "unit_1",
		"payload": {
			"model_id": "m1",
			"dest": [103, 100]
		}
	})
	
	# Second staged move (another 2 inches)
	phase.process_action({
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "unit_1",
		"payload": {
			"model_id": "m1",
			"dest": [105, 100]
		}
	})
	
	var move_data = phase.active_moves["unit_1"]
	# Should only have one staged move for the model (replaced)
	assert_eq(move_data.staged_moves.size(), 1)
	# But accumulated distance should reflect total movement
	assert_lt(move_data.accumulated_distance, 6.0)  # Within movement cap

func test_staged_move_exceeds_cap():
	# Begin a normal move
	phase.process_action({
		"type": "BEGIN_NORMAL_MOVE",
		"actor_unit_id": "unit_1",
		"payload": {}
	})
	
	# Try to stage a move that exceeds cap (10 inches)
	var stage_action = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "unit_1",
		"payload": {
			"model_id": "m1",
			"dest": [110, 100]  # 10 inches - exceeds 6" cap
		}
	}
	
	var validation = phase.validate_action(stage_action)
	assert_false(validation.valid)
	assert_has(validation.errors[0], "exceeds cap")

func test_confirm_staged_moves():
	# Begin a normal move
	phase.process_action({
		"type": "BEGIN_NORMAL_MOVE",
		"actor_unit_id": "unit_1",
		"payload": {}
	})
	
	# Stage a move
	phase.process_action({
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "unit_1",
		"payload": {
			"model_id": "m1",
			"dest": [103, 100]
		}
	})
	
	# Confirm the move
	var confirm_action = {
		"type": "CONFIRM_UNIT_MOVE",
		"actor_unit_id": "unit_1",
		"payload": {}
	}
	
	var result = phase.process_action(confirm_action)
	assert_true(result.success)
	
	# Check that staged moves were converted to permanent
	var move_data = phase.active_moves.get("unit_1")
	assert_null(move_data)  # Should be cleared after confirmation
	
	# Check that model position was updated in changes
	var position_change_found = false
	for change in result.changes:
		if change.path == "units.unit_1.models.0.position":
			position_change_found = true
			assert_eq(change.value.x, 103)
			assert_eq(change.value.y, 100)
			break
	assert_true(position_change_found)

func test_reset_staged_moves():
	# Begin a normal move
	phase.process_action({
		"type": "BEGIN_NORMAL_MOVE",
		"actor_unit_id": "unit_1",
		"payload": {}
	})
	
	# Stage a move
	phase.process_action({
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "unit_1",
		"payload": {
			"model_id": "m1",
			"dest": [103, 100]
		}
	})
	
	# Reset the move
	var reset_action = {
		"type": "RESET_UNIT_MOVE",
		"actor_unit_id": "unit_1",
		"payload": {}
	}
	
	var result = phase.process_action(reset_action)
	assert_true(result.success)
	
	# Check that staged moves were cleared
	var move_data = phase.active_moves["unit_1"]
	assert_eq(move_data.staged_moves, [])
	assert_eq(move_data.accumulated_distance, 0.0)
	
	# Check that model position was reset in changes
	var position_reset_found = false
	for change in result.changes:
		if change.path == "units.unit_1.models.0.position":
			position_reset_found = true
			assert_eq(change.value.x, 100)  # Back to original
			assert_eq(change.value.y, 100)
			break
	assert_true(position_reset_found)

func test_get_active_move_data():
	# Begin a normal move
	phase.process_action({
		"type": "BEGIN_NORMAL_MOVE",
		"actor_unit_id": "unit_1",
		"payload": {}
	})
	
	# Stage a move
	phase.process_action({
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "unit_1",
		"payload": {
			"model_id": "m1",
			"dest": [103, 100]
		}
	})
	
	# Test the helper method
	var move_data = phase.get_active_move_data("unit_1")
	assert_not_null(move_data)
	assert_has(move_data, "staged_moves")
	assert_has(move_data, "accumulated_distance")
	assert_gt(move_data.accumulated_distance, 0.0)
	
	# Test with non-existent unit
	var empty_data = phase.get_active_move_data("non_existent")
	assert_eq(empty_data, {})
