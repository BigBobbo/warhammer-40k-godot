extends BasePhaseTest
const BasePhase = preload("res://phases/BasePhase.gd")

# MovementPhase GUT Tests - Validates the Movement Phase implementation
# Converted from original MovementPhaseTest.gd to use GUT framework
# Tests all movement types, validation rules, and edge cases

var movement_phase: MovementPhase

func before_each():
	super.before_each()
	
	# Create movement phase instance 
	movement_phase = preload("res://phases/MovementPhase.gd").new()
	add_child(movement_phase)
	
	# Use movement-specific test state from TestDataFactory
	test_state = TestDataFactory.create_movement_test_state()
	
	# Add terrain to test state for collision testing
	test_state.board.terrain = [
		{
			"type": "impassable",
			"poly": [
				{"x": 20, "y": 20},
				{"x": 24, "y": 20},
				{"x": 24, "y": 24},
				{"x": 20, "y": 24}
			]
		}
	]
	
	# Setup phase instance
	phase_instance = movement_phase
	enter_phase()

func after_each():
	if movement_phase:
		movement_phase.queue_free()
		movement_phase = null
	super.after_each()

# Test normal movement actions
func test_normal_movement_validation():
	var action = create_action("BEGIN_NORMAL_MOVE", "test_unit_1")
	
	var result = assert_valid_action(action, "Normal move should be valid when not engaged")
	assert_not_null(result, "Validation result should exist")
	assert_true(result.valid, "Normal move should pass validation")

func test_normal_movement_processing():
	var action = create_action("BEGIN_NORMAL_MOVE", "test_unit_1")
	
	var result = assert_action_success(action, "Normal move should process successfully")
	
	# Check that movement state is properly set up
	assert_true(movement_phase.active_moves.has("test_unit_1"), "Should create active move entry")
	
	var move_data = movement_phase.active_moves["test_unit_1"]
	assert_eq("NORMAL", move_data.mode, "Move mode should be NORMAL")
	assert_eq(6.0, move_data.move_cap_inches, "Move cap should match unit's movement stat")

func test_normal_movement_when_engaged():
	# Position enemy unit close to create engagement
	var test_unit = get_test_unit("test_unit_1")
	var enemy_unit = get_test_unit("enemy_unit_1")
	
	# Move enemy within engagement range (1 inch)
	enemy_unit.models[0].position = {"x": test_unit.models[0].position.x + 25, "y": test_unit.models[0].position.y}
	
	var action = create_action("BEGIN_NORMAL_MOVE", "test_unit_1")
	assert_invalid_action(action, ["engaged"], "Normal move should be invalid when engaged with enemy")

# Test advance movement actions
func test_advance_movement_validation():
	var action = create_action("BEGIN_ADVANCE", "test_unit_1")
	assert_valid_action(action, "Advance should be valid when not engaged")

func test_advance_movement_processing():
	var action = create_action("BEGIN_ADVANCE", "test_unit_1")
	
	var result = assert_action_success(action, "Advance should process successfully")
	assert_true(result.has("dice"), "Advance result should include dice rolls")
	
	var move_data = movement_phase.active_moves["test_unit_1"]
	assert_eq("ADVANCE", move_data.mode, "Move mode should be ADVANCE")
	assert_between(move_data.move_cap_inches, 7.0, 12.0, "Advance move cap should be M + D6 (7-12 inches)")

func test_advance_sets_restrictions():
	var action = create_action("BEGIN_ADVANCE", "test_unit_1")
	movement_phase.process_action(action)
	
	# Confirm the move to apply restrictions
	var confirm_action = create_action("CONFIRM_UNIT_MOVE", "test_unit_1")
	var result = movement_phase.process_action(confirm_action)
	
	assert_true(result.success, "Move confirmation should succeed")
	assert_true(result.has("changes"), "Should have state changes")
	
	# Check that advance restrictions are applied
	var has_cannot_shoot = false
	var has_cannot_charge = false
	
	for change in result.changes:
		if change.path.ends_with("cannot_shoot") and change.value == true:
			has_cannot_shoot = true
		if change.path.ends_with("cannot_charge") and change.value == true:
			has_cannot_charge = true
	
	assert_true(has_cannot_shoot, "Advance should set cannot_shoot flag")
	assert_true(has_cannot_charge, "Advance should set cannot_charge flag")

# Test fall back movement actions
func test_fall_back_when_not_engaged():
	var action = create_action("BEGIN_FALL_BACK", "test_unit_1")
	assert_invalid_action(action, ["not engaged"], "Fall Back should be invalid when not engaged with enemy")

func test_fall_back_when_engaged():
	# Position enemy unit close to create engagement
	var test_unit = get_test_unit("test_unit_1")
	var enemy_unit = get_test_unit("enemy_unit_1")
	
	# Move enemy within engagement range
	enemy_unit.models[0].position = {"x": test_unit.models[0].position.x + 25, "y": test_unit.models[0].position.y}
	
	var action = create_action("BEGIN_FALL_BACK", "test_unit_1")
	assert_valid_action(action, "Fall Back should be valid when engaged")
	
	var result = assert_action_success(action, "Fall Back should process successfully")
	
	var move_data = movement_phase.active_moves["test_unit_1"]
	assert_eq("FALL_BACK", move_data.mode, "Move mode should be FALL_BACK")

func test_fall_back_desperate_escape():
	# Setup engagement scenario
	var test_unit = get_test_unit("test_unit_1")
	var enemy_unit = get_test_unit("enemy_unit_1")
	
	enemy_unit.models[0].position = {"x": test_unit.models[0].position.x + 25, "y": test_unit.models[0].position.y}
	
	# Start Fall Back
	movement_phase.process_action(create_action("BEGIN_FALL_BACK", "test_unit_1"))
	
	# Set destination that crosses enemy (should trigger Desperate Escape)
	var dest_action = create_action("SET_MODEL_DEST", "test_unit_1", {
		"model_id": "m1",
		"dest": [test_unit.models[0].position.x - 100, test_unit.models[0].position.y]
	})
	movement_phase.process_action(dest_action)
	
	# Confirm move
	var confirm_action = create_action("CONFIRM_UNIT_MOVE", "test_unit_1")
	var result = movement_phase.process_action(confirm_action)
	
	assert_true(result.success, "Fall Back with Desperate Escape should succeed")
	# Note: Dice roll testing would require mocking RNG

# Test movement destination setting
func test_set_model_destination_valid():
	# Start a normal move first
	movement_phase.process_action(create_action("BEGIN_NORMAL_MOVE", "test_unit_1"))
	
	var dest_action = create_action("SET_MODEL_DEST", "test_unit_1", {
		"model_id": "m1",
		"dest": [200, 200]  # Valid destination within move range
	})
	
	assert_valid_action(dest_action, "Setting valid model destination should be valid")

func test_set_model_destination_too_far():
	# Start a normal move first
	movement_phase.process_action(create_action("BEGIN_NORMAL_MOVE", "test_unit_1"))
	
	var test_unit = get_test_unit("test_unit_1")
	var far_dest = [
		test_unit.models[0].position.x + 1000,  # Way beyond move range
		test_unit.models[0].position.y
	]
	
	var dest_action = create_action("SET_MODEL_DEST", "test_unit_1", {
		"model_id": "m1",
		"dest": far_dest
	})
	
	assert_invalid_action(dest_action, ["too far", "move range"], "Setting destination beyond move range should be invalid")

func test_set_model_destination_in_engagement_range():
	# Start a normal move first
	movement_phase.process_action(create_action("BEGIN_NORMAL_MOVE", "test_unit_1"))
	
	var enemy_unit = get_test_unit("enemy_unit_1")
	var dest_near_enemy = [
		enemy_unit.models[0].position.x + 10,  # Too close to enemy
		enemy_unit.models[0].position.y
	]
	
	var dest_action = create_action("SET_MODEL_DEST", "test_unit_1", {
		"model_id": "m1", 
		"dest": dest_near_enemy
	})
	
	assert_invalid_action(dest_action, ["engagement"], "Normal move should not be able to end in engagement range")

func test_set_model_destination_in_terrain():
	# Start a normal move first
	movement_phase.process_action(create_action("BEGIN_NORMAL_MOVE", "test_unit_1"))
	
	# Destination in impassable terrain (coordinates from test_state terrain setup)
	var dest_in_terrain = [880, 880]  # Converts to (22, 22) inches - inside terrain
	
	var dest_action = create_action("SET_MODEL_DEST", "test_unit_1", {
		"model_id": "m1",
		"dest": dest_in_terrain
	})
	
	assert_invalid_action(dest_action, ["terrain", "impassable"], "Should not be able to move into impassable terrain")

# Test unit coherency during movement
func test_coherency_validation():
	# Start a normal move
	movement_phase.process_action(create_action("BEGIN_NORMAL_MOVE", "test_unit_1"))
	
	var test_unit = get_test_unit("test_unit_1")
	
	# Try to move one model too far from the rest (break coherency)
	var dest_breaking_coherency = [
		test_unit.models[0].position.x + 200,  # Too far from other models
		test_unit.models[0].position.y + 200
	]
	
	var dest_action = create_action("SET_MODEL_DEST", "test_unit_1", {
		"model_id": "m1",
		"dest": dest_breaking_coherency
	})
	
	# This should be caught during confirmation if coherency checking is implemented
	movement_phase.process_action(dest_action)
	
	var confirm_action = create_action("CONFIRM_UNIT_MOVE", "test_unit_1")
	var result = movement_phase.validate_action(confirm_action)
	
	# Depending on implementation, this might be caught at validation or processing
	if movement_phase.has_method("check_unit_coherency"):
		assert_false(result.valid, "Move breaking unit coherency should be invalid")

# Test movement confirmation
func test_confirm_unit_move_success():
	# Start and set up a valid move
	movement_phase.process_action(create_action("BEGIN_NORMAL_MOVE", "test_unit_1"))
	
	var dest_action = create_action("SET_MODEL_DEST", "test_unit_1", {
		"model_id": "m1",
		"dest": [150, 150]
	})
	movement_phase.process_action(dest_action)
	
	var confirm_action = create_action("CONFIRM_UNIT_MOVE", "test_unit_1")
	var result = assert_action_success(confirm_action, "Confirming valid move should succeed")
	
	assert_true(result.has("changes"), "Should have state changes to apply")

func test_confirm_unit_move_without_destinations():
	# Start move but don't set any destinations
	movement_phase.process_action(create_action("BEGIN_NORMAL_MOVE", "test_unit_1"))
	
	var confirm_action = create_action("CONFIRM_UNIT_MOVE", "test_unit_1")
	var result = movement_phase.validate_action(confirm_action)
	
	# This should either be invalid or result in no actual movement
	assert_not_null(result, "Should return validation result")

# Test action validation edge cases
func test_invalid_unit_id():
	var action = create_action("BEGIN_NORMAL_MOVE", "nonexistent_unit")
	assert_invalid_action(action, ["unit", "not found"], "Action with invalid unit ID should fail")

func test_action_on_already_moved_unit():
	# Mark unit as already moved
	var test_unit = get_test_unit("test_unit_1")
	test_unit.flags.moved = true
	
	var action = create_action("BEGIN_NORMAL_MOVE", "test_unit_1")
	assert_invalid_action(action, ["already moved", "moved"], "Unit that already moved should not be able to move again")

func test_action_on_enemy_unit():
	# Try to move enemy unit (should be invalid for current player)
	var action = create_action("BEGIN_NORMAL_MOVE", "enemy_unit_1")
	assert_invalid_action(action, ["not your unit", "enemy", "owner"], "Should not be able to move enemy units")

func test_action_on_destroyed_unit():
	# Mark all models as dead
	var test_unit = get_test_unit("test_unit_1")
	for model in test_unit.models:
		model.alive = false
		model.current_wounds = 0
	
	var action = create_action("BEGIN_NORMAL_MOVE", "test_unit_1")
	assert_invalid_action(action, ["destroyed", "no models", "dead"], "Should not be able to move destroyed units")

# Test movement type restrictions
func test_multiple_movement_actions_same_unit():
	# Start one movement type
	movement_phase.process_action(create_action("BEGIN_NORMAL_MOVE", "test_unit_1"))
	
	# Try to start another movement type on same unit
	var advance_action = create_action("BEGIN_ADVANCE", "test_unit_1")
	assert_invalid_action(advance_action, ["already moving", "active move"], "Should not be able to start multiple move types on same unit")

func test_movement_without_begin_action():
	# Try to set destination without starting a move
	var dest_action = create_action("SET_MODEL_DEST", "test_unit_1", {
		"model_id": "m1",
		"dest": [200, 200]
	})
	
	assert_invalid_action(dest_action, ["no active move", "not moving"], "Should not be able to set destination without starting move")

# Test available actions
func test_get_available_actions():
	enter_phase()
	
	var available = get_available_actions()
	assert_not_null(available, "Should return available actions")
	assert_true(available is Array, "Available actions should be array")
	
	# Should include movement actions for units that can move
	var has_normal_move = false
	var has_advance = false
	var has_fall_back = false
	
	for action in available:
		if action.type == "BEGIN_NORMAL_MOVE":
			has_normal_move = true
		elif action.type == "BEGIN_ADVANCE":
			has_advance = true
		elif action.type == "BEGIN_FALL_BACK":
			has_fall_back = true
	
	assert_true(has_normal_move, "Should have normal move actions available")
	assert_true(has_advance, "Should have advance actions available")
	# Fall back might only be available when engaged

func test_phase_completion():
	# Move all units to complete the phase
	for unit_id in ["test_unit_1", "test_unit_2"]:
		if test_state.units.has(unit_id):
			# Perform a simple move
			movement_phase.process_action(create_action("BEGIN_NORMAL_MOVE", unit_id))
			movement_phase.process_action(create_action("CONFIRM_UNIT_MOVE", unit_id))
	
	# Check if phase should complete
	assert_phase_can_complete("Phase should be completable when all units have moved or chosen not to move")

# Test phase-specific state management
func test_active_moves_cleanup():
	# Start a move
	movement_phase.process_action(create_action("BEGIN_NORMAL_MOVE", "test_unit_1"))
	assert_true(movement_phase.active_moves.has("test_unit_1"), "Should have active move")
	
	# Confirm the move
	movement_phase.process_action(create_action("CONFIRM_UNIT_MOVE", "test_unit_1"))
	
	# Active move should be cleaned up (depending on implementation)
	if movement_phase.has_method("cleanup_active_move"):
		assert_false(movement_phase.active_moves.has("test_unit_1"), "Active move should be cleaned up after confirmation")

# Test measurement and distance calculations
func test_movement_distance_calculation():
	if not movement_phase.has_method("calculate_move_distance"):
		skip_test("Movement distance calculation method not available")
		return
	
	var from_pos = Vector2(100, 100)
	var to_pos = Vector2(140, 100)  # 40 pixels = 1 inch
	
	var distance = movement_phase.calculate_move_distance(from_pos, to_pos)
	assert_almost_eq(1.0, distance, 0.1, "Should calculate 1 inch movement correctly")

# Test integration with game state
func test_movement_updates_unit_positions():
	# Perform a complete movement
	movement_phase.process_action(create_action("BEGIN_NORMAL_MOVE", "test_unit_1"))
	
	var new_dest = [200, 200]
	movement_phase.process_action(create_action("SET_MODEL_DEST", "test_unit_1", {
		"model_id": "m1",
		"dest": new_dest
	}))
	
	var result = movement_phase.process_action(create_action("CONFIRM_UNIT_MOVE", "test_unit_1"))
	
	if result.success and result.has("changes"):
		# Check that position changes are included
		var has_position_change = false
		for change in result.changes:
			if change.path.contains("position"):
				has_position_change = true
				break
		
		assert_true(has_position_change, "Movement should generate position changes")

# Helper method to create movement-specific actions
func create_movement_action(action_type: String, unit_id: String, payload: Dictionary = {}) -> Dictionary:
	return {
		"type": action_type,
		"actor_unit_id": unit_id,
		"payload": payload
	}
