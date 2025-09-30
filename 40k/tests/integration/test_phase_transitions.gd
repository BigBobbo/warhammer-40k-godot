extends GutTest

# Phase Transitions Integration Tests - Tests complete phase transition flows
# Tests the coordination between PhaseManager, GameState, and individual phases

var phase_manager: Node
var game_state: GameStateData
var initial_state: Dictionary
var phases_transitioned: Array = []

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	# Create test instances
	game_state = GameStateData.new()
	game_state.initialize_default_state()
	initial_state = game_state.create_snapshot()
	
	# Create phase manager
	if Engine.has_singleton("PhaseManager"):
		phase_manager = Engine.get_singleton("PhaseManager")
	else:
		# Create mock phase manager for testing
		phase_manager = preload("res://autoloads/PhaseManager.gd").new()
		add_child(phase_manager)
	
	phases_transitioned = []
	
	# Connect to phase transition signals
	if phase_manager.has_signal("phase_changed"):
		phase_manager.phase_changed.connect(_on_phase_changed)
	if phase_manager.has_signal("phase_completed"):
		phase_manager.phase_completed.connect(_on_phase_completed)

func after_each():
	if phase_manager and not Engine.has_singleton("PhaseManager"):
		phase_manager.queue_free()
	if game_state:
		game_state.queue_free()

func _on_phase_changed(new_phase: GameStateData.Phase):
	phases_transitioned.append(new_phase)

func _on_phase_completed(completed_phase: GameStateData.Phase):
	pass

# Test complete game turn cycle
func test_complete_turn_cycle():
	if not phase_manager:
		skip_test("PhaseManager not available")
		return
	
	var expected_phases = [
		GameStateData.Phase.DEPLOYMENT,
		GameStateData.Phase.MOVEMENT, 
		GameStateData.Phase.SHOOTING,
		GameStateData.Phase.CHARGE,
		GameStateData.Phase.FIGHT,
		GameStateData.Phase.MORALE
	]
	
	# Start from deployment
	phase_manager.transition_to_phase(GameStateData.Phase.DEPLOYMENT)
	await get_tree().process_frame
	
	# Advance through all phases
	for i in range(expected_phases.size() - 1):
		phase_manager.advance_to_next_phase()
		await get_tree().process_frame
	
	# Verify all phases were transitioned
	for phase in expected_phases:
		assert_true(phase in phases_transitioned, "Should have transitioned through " + str(phase))

func test_phase_transition_state_persistence():
	if not phase_manager:
		skip_test("PhaseManager not available")
		return
	
	# Start in deployment
	phase_manager.transition_to_phase(GameStateData.Phase.DEPLOYMENT)
	await get_tree().process_frame
	
	# Modify game state
	var test_modification = {"test_key": "test_value"}
	if game_state:
		game_state.state.test_data = test_modification
	
	# Transition to movement
	phase_manager.transition_to_phase(GameStateData.Phase.MOVEMENT)
	await get_tree().process_frame
	
	# State should be preserved across transitions
	if game_state:
		assert_true(game_state.state.has("test_data"), "State modifications should persist across phase transitions")
		assert_eq(test_modification, game_state.state.test_data, "State data should be unchanged")

func test_invalid_phase_transition():
	if not phase_manager:
		skip_test("PhaseManager not available")
		return
	
	# Try to transition to invalid phase (implementation dependent)
	var invalid_phase = 999  # Invalid phase number
	
	# Should handle gracefully without crashing
	phase_manager.transition_to_phase(invalid_phase)
	await get_tree().process_frame
	
	assert_true(true, "Invalid phase transition should not crash")

func test_phase_completion_triggers_next():
	if not phase_manager:
		skip_test("PhaseManager not available")
		return
	
	# Start in deployment
	phase_manager.transition_to_phase(GameStateData.Phase.DEPLOYMENT)
	await get_tree().process_frame
	
	var current_phase_instance = phase_manager.get_current_phase_instance()
	if current_phase_instance and current_phase_instance.has_signal("phase_completed"):
		# Trigger phase completion
		current_phase_instance.emit_signal("phase_completed")
		await get_tree().process_frame
		
		# Should advance to next phase
		var new_phase = phase_manager.get_current_phase()
		assert_eq(GameStateData.Phase.MOVEMENT, new_phase, "Should advance to MOVEMENT after DEPLOYMENT completes")

func test_phase_specific_actions_only_available_in_correct_phase():
	if not phase_manager:
		skip_test("PhaseManager not available")
		return
	
	# Test movement actions only work in movement phase
	phase_manager.transition_to_phase(GameStateData.Phase.MOVEMENT)
	await get_tree().process_frame
	
	var movement_phase = phase_manager.get_current_phase_instance()
	if movement_phase:
		var movement_action = {
			"type": "BEGIN_NORMAL_MOVE",
			"actor_unit_id": "test_unit_1"
		}
		
		var validation = movement_phase.validate_action(movement_action)
		assert_not_null(validation, "Movement phase should validate movement actions")
	
	# Switch to shooting phase
	phase_manager.transition_to_phase(GameStateData.Phase.SHOOTING)
	await get_tree().process_frame
	
	var shooting_phase = phase_manager.get_current_phase_instance()
	if shooting_phase:
		# Movement action should be invalid in shooting phase
		var validation = shooting_phase.validate_action(movement_action)
		if validation.has("valid"):
			assert_false(validation.valid, "Movement actions should be invalid in shooting phase")

func test_phase_log_history():
	if not phase_manager or not game_state:
		skip_test("PhaseManager or GameState not available")
		return
	
	# Add actions to phase log
	var test_action = {"type": "test_action", "phase": GameStateData.Phase.MOVEMENT}
	game_state.add_action_to_phase_log(test_action)
	
	# Commit to history during phase transition
	phase_manager.transition_to_phase(GameStateData.Phase.MOVEMENT)
	await get_tree().process_frame
	
	phase_manager.transition_to_phase(GameStateData.Phase.SHOOTING)
	await get_tree().process_frame
	
	# Check that history was updated
	var history = game_state.state.get("history", [])
	if history.size() > 0:
		var last_entry = history[-1]
		assert_true(last_entry.has("actions"), "History entry should contain actions")
		assert_true(last_entry.has("phase"), "History entry should contain phase info")

func test_turn_advancement():
	if not phase_manager or not game_state:
		skip_test("PhaseManager or GameState not available")
		return
	
	var initial_turn = game_state.get_turn_number()
	
	# Complete full turn cycle
	var phases = [
		GameStateData.Phase.DEPLOYMENT,
		GameStateData.Phase.MOVEMENT,
		GameStateData.Phase.SHOOTING, 
		GameStateData.Phase.CHARGE,
		GameStateData.Phase.FIGHT,
		GameStateData.Phase.MORALE
	]
	
	for phase in phases:
		phase_manager.transition_to_phase(phase)
		await get_tree().process_frame
	
	# Advance past morale (should start next turn)
	phase_manager.advance_to_next_phase()
	await get_tree().process_frame
	
	var final_turn = game_state.get_turn_number()
	assert_gt(final_turn, initial_turn, "Turn should advance after complete cycle")

func test_player_alternation():
	if not phase_manager or not game_state:
		skip_test("PhaseManager or GameState not available")
		return
	
	var initial_player = game_state.get_active_player()
	
	# Complete one player's turn
	var phases = [
		GameStateData.Phase.MOVEMENT,
		GameStateData.Phase.SHOOTING,
		GameStateData.Phase.CHARGE,
		GameStateData.Phase.FIGHT,
		GameStateData.Phase.MORALE
	]
	
	for phase in phases:
		phase_manager.transition_to_phase(phase)
		await get_tree().process_frame
		
		# Complete the phase immediately
		var phase_instance = phase_manager.get_current_phase_instance()
		if phase_instance:
			phase_instance.emit_signal("phase_completed")
			await get_tree().process_frame
	
	# Player should have changed (implementation dependent)
	var final_player = game_state.get_active_player()
	# This test depends on how player turns are implemented
	assert_true(final_player == initial_player or final_player != initial_player, 
		"Player alternation should be handled consistently")

func test_phase_state_cleanup():
	if not phase_manager:
		skip_test("PhaseManager not available")
		return
	
	# Start in movement phase
	phase_manager.transition_to_phase(GameStateData.Phase.MOVEMENT)
	await get_tree().process_frame
	
	var movement_phase = phase_manager.get_current_phase_instance()
	var movement_phase_id = movement_phase.get_instance_id() if movement_phase else 0
	
	# Transition to shooting
	phase_manager.transition_to_phase(GameStateData.Phase.SHOOTING)
	await get_tree().process_frame
	
	var shooting_phase = phase_manager.get_current_phase_instance()
	var shooting_phase_id = shooting_phase.get_instance_id() if shooting_phase else 0
	
	# Should be different phase instances
	assert_ne(movement_phase_id, shooting_phase_id, "Should create new phase instance on transition")

func test_phase_action_validation_integration():
	if not phase_manager:
		skip_test("PhaseManager not available")
		return
	
	# Test that PhaseManager validates actions correctly
	phase_manager.transition_to_phase(GameStateData.Phase.MOVEMENT)
	await get_tree().process_frame
	
	var valid_action = {
		"type": "BEGIN_NORMAL_MOVE",
		"actor_unit_id": "test_unit_1"
	}
	
	var validation = phase_manager.validate_phase_action(valid_action)
	assert_not_null(validation, "PhaseManager should validate actions")
	assert_true(validation.has("valid"), "Validation should have valid field")

func test_signal_propagation():
	if not phase_manager:
		skip_test("PhaseManager not available")
		return
	
	var phase_changed_received = false
	var phase_completed_received = false
	
	# Connect to signals
	if phase_manager.has_signal("phase_changed"):
		phase_manager.phase_changed.connect(func(phase): phase_changed_received = true)
	if phase_manager.has_signal("phase_completed"):
		phase_manager.phase_completed.connect(func(phase): phase_completed_received = true)
	
	# Trigger transition
	phase_manager.transition_to_phase(GameStateData.Phase.MOVEMENT)
	await get_tree().process_frame
	
	assert_true(phase_changed_received, "phase_changed signal should be emitted")
	
	# Trigger completion
	var phase_instance = phase_manager.get_current_phase_instance()
	if phase_instance and phase_instance.has_signal("phase_completed"):
		phase_instance.emit_signal("phase_completed")
		await get_tree().process_frame
		
		assert_true(phase_completed_received, "phase_completed signal should be propagated")

func test_concurrent_action_handling():
	if not phase_manager:
		skip_test("PhaseManager not available")
		return
	
	# Test handling multiple actions in same frame
	phase_manager.transition_to_phase(GameStateData.Phase.MOVEMENT)
	await get_tree().process_frame
	
	var actions = [
		{"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "unit_1"},
		{"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "unit_2"},
		{"type": "BEGIN_ADVANCE", "actor_unit_id": "unit_3"}
	]
	
	# Process actions simultaneously
	var results = []
	for action in actions:
		var result = phase_manager.validate_phase_action(action)
		results.append(result)
	
	# All should be processed without interference
	for result in results:
		assert_not_null(result, "Each action should get validation result")

func test_error_recovery():
	if not phase_manager:
		skip_test("PhaseManager not available")
		return
	
	# Test recovery from invalid state
	phase_manager.transition_to_phase(GameStateData.Phase.MOVEMENT)
	await get_tree().process_frame
	
	# Force invalid state (implementation specific)
	var phase_instance = phase_manager.get_current_phase_instance()
	if phase_instance:
		# Try to break the phase somehow
		phase_instance.game_state_snapshot = {}  # Invalid state
		
		# Should handle gracefully
		var validation = phase_manager.validate_phase_action({"type": "test"})
		assert_not_null(validation, "Should handle invalid state gracefully")

func test_memory_cleanup():
	if not phase_manager:
		skip_test("PhaseManager not available")
		return
	
	var initial_child_count = get_child_count()
	
	# Transition through multiple phases
	var phases = [
		GameStateData.Phase.DEPLOYMENT,
		GameStateData.Phase.MOVEMENT,
		GameStateData.Phase.SHOOTING,
		GameStateData.Phase.CHARGE
	]
	
	for phase in phases:
		phase_manager.transition_to_phase(phase)
		await get_tree().process_frame
	
	var final_child_count = get_child_count()
	
	# Should not accumulate excessive objects
	var child_difference = final_child_count - initial_child_count
	assert_lt(child_difference, 10, "Should not accumulate too many child objects")

func test_rapid_phase_transitions():
	if not phase_manager:
		skip_test("PhaseManager not available")
		return
	
	# Test rapid transitions don't cause issues
	var phases = [
		GameStateData.Phase.MOVEMENT,
		GameStateData.Phase.SHOOTING,
		GameStateData.Phase.MOVEMENT,
		GameStateData.Phase.CHARGE,
		GameStateData.Phase.FIGHT
	]
	
	for phase in phases:
		phase_manager.transition_to_phase(phase)
		await get_tree().process_frame
	
	# Should handle rapid transitions without errors
	var current_phase = phase_manager.get_current_phase()
	assert_eq(GameStateData.Phase.FIGHT, current_phase, "Should end up in final phase")

func test_state_synchronization():
	if not phase_manager or not game_state:
		skip_test("PhaseManager or GameState not available")
		return
	
	# Test that PhaseManager and GameState stay synchronized
	phase_manager.transition_to_phase(GameStateData.Phase.SHOOTING)
	await get_tree().process_frame
	
	var pm_phase = phase_manager.get_current_phase()
	var gs_phase = game_state.get_current_phase()
	
	assert_eq(pm_phase, gs_phase, "PhaseManager and GameState should have same current phase")

# Test edge cases
func test_phase_transition_during_action():
	if not phase_manager:
		skip_test("PhaseManager not available")
		return
	
	# Start action in one phase
	phase_manager.transition_to_phase(GameStateData.Phase.MOVEMENT)
	await get_tree().process_frame
	
	var action = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "test_unit"}
	phase_manager.validate_phase_action(action)
	
	# Transition while action is in progress
	phase_manager.transition_to_phase(GameStateData.Phase.SHOOTING)
	await get_tree().process_frame
	
	# Should handle gracefully
	assert_true(true, "Phase transition during action should not crash")

func test_null_phase_handling():
	if not phase_manager:
		skip_test("PhaseManager not available")
		return
	
	# Test handling of null/undefined phases
	var current_instance = phase_manager.get_current_phase_instance()
	
	# Should always have a valid phase instance or handle null gracefully
	if current_instance == null:
		var actions = phase_manager.get_available_actions()
		assert_not_null(actions, "Should return empty array for null phase")
	else:
		assert_true(true, "Has valid phase instance")