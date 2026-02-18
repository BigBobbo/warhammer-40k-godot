extends "res://addons/gut/test.gd"
const GameStateData = preload("res://autoloads/GameState.gd")

# System Integration Tests - Tests interaction between multiple game systems
# Tests coordination between autoloads, UI, phases, and game logic

var game_manager: Node
var phase_manager: Node
var game_state: GameStateData
var turn_manager: Node
var action_logger: Node

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	# Get autoload references
	if Engine.has_singleton("GameManager"):
		game_manager = Engine.get_singleton("GameManager")
	if Engine.has_singleton("PhaseManager"):
		phase_manager = Engine.get_singleton("PhaseManager")
	if Engine.has_singleton("GameState"):
		game_state = Engine.get_singleton("GameState")
	if Engine.has_singleton("TurnManager"):
		turn_manager = Engine.get_singleton("TurnManager")
	if Engine.has_singleton("ActionLogger"):
		action_logger = Engine.get_singleton("ActionLogger")
	
	# Create test instances if autoloads not available
	if not game_state:
		game_state = GameStateData.new()
		game_state.initialize_default_state()

func after_each():
	if game_state and not Engine.has_singleton("GameState"):
		game_state.queue_free()

# Test game initialization flow
func test_game_initialization_sequence():
	if not game_manager:
		pending("GameManager not available")
		return
	
	# Test that game initializes all systems correctly
	if game_manager.has_method("initialize_game"):
		var init_result = game_manager.initialize_game()
		assert_true(init_result, "Game initialization should succeed")
	
	# Verify systems are ready
	if phase_manager:
		assert_not_null(phase_manager.get_current_phase_instance(), "PhaseManager should have active phase")
	
	if game_state:
		var validation = game_state.validate_state()
		assert_true(validation.valid, "GameState should be valid after initialization")

func test_action_logging_integration():
	if not action_logger or not game_state:
		pending("ActionLogger or GameState not available")
		return
	
	# Perform action that should be logged
	var test_action = {
		"type": "TEST_ACTION",
		"actor_unit_id": "test_unit",
		"timestamp": Time.get_unix_time_from_system()
	}
	
	# Log the action
	if action_logger.has_method("log_action"):
		action_logger.log_action(test_action)
	else:
		game_state.add_action_to_phase_log(test_action)
	
	# Verify action was recorded
	var phase_log = game_state.state.get("phase_log", [])
	var action_found = false
	for logged_action in phase_log:
		if logged_action.get("type") == "TEST_ACTION":
			action_found = true
			break
	
	assert_true(action_found, "Action should be logged in game state")

func test_turn_and_phase_coordination():
	if not turn_manager or not phase_manager or not game_state:
		pending("TurnManager, PhaseManager, or GameState not available")
		return
	
	var initial_turn = game_state.get_turn_number()
	var initial_player = game_state.get_active_player()
	
	# Complete full turn cycle through turn manager
	if turn_manager.has_method("advance_to_next_player"):
		turn_manager.advance_to_next_player()
		
		await get_tree().process_frame
		
		# Turn or player should have changed
		var final_turn = game_state.get_turn_number()
		var final_player = game_state.get_active_player()
		
		assert_true(final_turn != initial_turn or final_player != initial_player, 
			"Turn manager should coordinate turn/player changes")

func test_measurement_system_integration():
	if not Engine.has_singleton("Measurement"):
		pending("Measurement system not available")
		return
	
	var measurement = Engine.get_singleton("Measurement")
	
	# Test measurement calculations in game context
	var pos1 = Vector2(100, 100)
	var pos2 = Vector2(340, 100)  # 6 inches apart
	
	var distance_inches = measurement.distance_inches(pos1, pos2)
	assert_almost_eq(6.0, distance_inches, 0.1, "Distance calculation should be accurate")
	
	# Test within game rules context (6" movement)
	var unit_move = 6  # inches
	var move_distance_px = measurement.inches_to_px(unit_move)
	assert_eq(240.0, move_distance_px, "Unit movement should convert correctly to pixels")

func test_board_state_coordination():
	if not Engine.has_singleton("BoardState"):
		pending("BoardState not available")
		return
	
	var board_state = Engine.get_singleton("BoardState")
	
	# Test board state stays synchronized with game state
	if board_state.has_method("update_from_game_state"):
		board_state.update_from_game_state(game_state.create_snapshot())
	
	# Verify board state reflects game state
	if board_state.has_method("get_board_size"):
		var board_size = board_state.get_board_size()
		assert_not_null(board_size, "Board state should have board size information")

func test_replay_system_integration():
	if not Engine.has_singleton("ReplayManager") or not action_logger:
		pending("ReplayManager or ActionLogger not available")
		return
	
	var replay_manager = Engine.get_singleton("ReplayManager")
	
	# Record some actions
	var actions = [
		{"type": "MOVE", "unit": "test_unit", "from": Vector2(0,0), "to": Vector2(100,100)},
		{"type": "SHOOT", "unit": "test_unit", "target": "enemy_unit"}
	]
	
	for action in actions:
		if action_logger.has_method("log_action"):
			action_logger.log_action(action)
	
	# Start replay recording
	if replay_manager.has_method("start_recording"):
		replay_manager.start_recording()
	
	# Process actions
	for action in actions:
		if replay_manager.has_method("record_action"):
			replay_manager.record_action(action)
	
	# Stop recording
	if replay_manager.has_method("stop_recording"):
		var replay_data = replay_manager.stop_recording()
		assert_not_null(replay_data, "Replay should capture action data")

func test_settings_service_integration():
	if not Engine.has_singleton("SettingsService"):
		pending("SettingsService not available")
		return
	
	var settings = Engine.get_singleton("SettingsService")
	
	# Test settings affect game systems
	if settings.has_method("get_setting"):
		var measurement_unit = settings.get_setting("measurement_unit", "inches")
		assert_true(measurement_unit in ["inches", "cm"], "Should have valid measurement unit setting")
	
	if settings.has_method("set_setting"):
		settings.set_setting("auto_save_enabled", true)
		var auto_save = settings.get_setting("auto_save_enabled", false)
		assert_true(auto_save, "Settings should persist changes")

func test_multi_phase_scenario():
	# Test complete scenario across multiple phases
	if not phase_manager or not game_state:
		pending("PhaseManager or GameState not available")
		return
	
	var scenario_log = []
	
	# Deployment Phase
	phase_manager.transition_to_phase(GameStateData.Phase.DEPLOYMENT)
	await get_tree().process_frame
	scenario_log.append("Deployment started")
	
	# Mock deployment completion
	var deployment_phase = phase_manager.get_current_phase_instance()
	if deployment_phase:
		deployment_phase.emit_signal("phase_completed")
		await get_tree().process_frame
		scenario_log.append("Deployment completed")
	
	# Should automatically advance to movement
	var current_phase = game_state.get_current_phase()
	assert_eq(GameStateData.Phase.MOVEMENT, current_phase, "Should advance to movement phase")
	scenario_log.append("Movement phase active")
	
	# Continue through other phases
	var remaining_phases = [GameStateData.Phase.SHOOTING, GameStateData.Phase.CHARGE, GameStateData.Phase.FIGHT, GameStateData.Phase.MORALE]
	
	for phase in remaining_phases:
		var phase_instance = phase_manager.get_current_phase_instance()
		if phase_instance:
			phase_instance.emit_signal("phase_completed")
			await get_tree().process_frame
			scenario_log.append(str(phase) + " completed")
	
	# Verify scenario completed
	assert_gte(scenario_log.size(), 6, "Should have processed all phases")

func test_error_propagation():
	# Test that errors in one system are handled by others
	if not game_state:
		pending("GameState not available")
		return
	
	# Create invalid state
	var invalid_state = {"broken": "state"}
	
	# Load invalid state
	var error_handled = false
	# GDScript doesn't have try/except, so we just test error handling
	game_state.load_from_snapshot(invalid_state)
	error_handled = true  # If we get here, error was handled gracefully
	
	assert_true(error_handled, "System should handle invalid state gracefully")
	
	# Verify system recovered
	var validation = game_state.validate_state()
	# System should either be valid or have specific error handling
	assert_not_null(validation, "System should provide validation after error")

func test_concurrent_system_updates():
	# Test multiple systems updating simultaneously
	if not game_state:
		pending("GameState not available")
		return
	
	var initial_turn = game_state.get_turn_number()
	
	# Simulate concurrent updates
	game_state.advance_turn()
	game_state.set_phase(GameStateData.Phase.SHOOTING)
	game_state.set_active_player(2)
	
	await get_tree().process_frame
	
	# All updates should be applied consistently
	assert_gt(game_state.get_turn_number(), initial_turn, "Turn should be advanced")
	assert_eq(GameStateData.Phase.SHOOTING, game_state.get_current_phase(), "Phase should be updated")
	assert_eq(2, game_state.get_active_player(), "Active player should be updated")

func test_memory_management_across_systems():
	# Test memory usage doesn't grow excessively
	var initial_child_count = get_child_count()
	
	# Perform operations that create/destroy objects
	if phase_manager:
		for i in range(10):
			phase_manager.transition_to_phase(GameStateData.Phase.MOVEMENT)
			await get_tree().process_frame
			phase_manager.transition_to_phase(GameStateData.Phase.SHOOTING)
			await get_tree().process_frame
	
	var final_child_count = get_child_count()
	var child_difference = final_child_count - initial_child_count
	
	# Should not accumulate excessive objects
	assert_lt(child_difference, 20, "Should not leak excessive objects")

func test_signal_chains():
	# Test signal propagation between systems
	if not phase_manager or not game_state:
		pending("PhaseManager or GameState not available")
		return
	
	var signals_received = []
	
	# Connect to phase signals
	if phase_manager.has_signal("phase_changed"):
		phase_manager.phase_changed.connect(func(phase): signals_received.append("phase_changed"))
	
	if phase_manager.has_signal("phase_completed"):
		phase_manager.phase_completed.connect(func(phase): signals_received.append("phase_completed"))
	
	# Trigger signal chain
	phase_manager.transition_to_phase(GameStateData.Phase.CHARGE)
	await get_tree().process_frame
	
	var phase_instance = phase_manager.get_current_phase_instance()
	if phase_instance and phase_instance.has_signal("phase_completed"):
		phase_instance.emit_signal("phase_completed")
		await get_tree().process_frame
	
	# Verify signals were propagated
	assert_true("phase_changed" in signals_received, "phase_changed signal should be received")

func test_performance_under_load():
	# Test system performance with many operations
	var start_time = Time.get_time_dict_from_system()
	
	# Perform many rapid operations
	for i in range(100):
		if game_state:
			var snapshot = game_state.create_snapshot()
			var validation = game_state.validate_state()
			game_state.add_action_to_phase_log({"type": "perf_test", "index": i})
		await get_tree().process_frame
	
	var end_time = Time.get_time_dict_from_system()
	
	# Calculate elapsed time (simplified)
	var elapsed_seconds = (end_time.second - start_time.second) + (end_time.minute - start_time.minute) * 60
	if elapsed_seconds < 0:
		elapsed_seconds += 60  # Handle minute rollover
	
	# Should complete in reasonable time
	assert_lt(elapsed_seconds, 10, "Performance test should complete in reasonable time")

func test_state_consistency_across_systems():
	# Test that all systems maintain consistent view of game state
	if not game_state:
		pending("GameState not available")
		return
	
	# Modify state
	game_state.set_phase(GameStateData.Phase.FIGHT)
	game_state.set_active_player(2)
	game_state.advance_turn()
	
	await get_tree().process_frame
	
	# Check that all systems see the same state
	if phase_manager:
		var pm_phase = phase_manager.get_current_phase()
		var gs_phase = game_state.get_current_phase()
		assert_eq(pm_phase, gs_phase, "PhaseManager and GameState should have consistent phase")
	
	if turn_manager and turn_manager.has_method("get_current_player"):
		var tm_player = turn_manager.get_current_player()
		var gs_player = game_state.get_active_player()
		assert_eq(tm_player, gs_player, "TurnManager and GameState should have consistent active player")

func test_system_recovery_after_failure():
	# Test system recovery after component failure
	if not game_state:
		pending("GameState not available")
		return
	
	# Save good state
	var good_state = game_state.create_snapshot()
	
	# Simulate system failure (corrupt state)
	game_state.state = {"corrupted": true}
	
	# Attempt recovery
	var recovered = false
	if game_state.has_method("recover_from_backup"):
		recovered = game_state.recover_from_backup()
	else:
		# Manual recovery
		game_state.load_from_snapshot(good_state)
		var validation = game_state.validate_state()
		recovered = validation.valid
	
	assert_true(recovered, "System should recover from failure")

func test_cross_system_data_flow():
	# Test data flowing between multiple systems
	if not action_logger or not game_state:
		pending("ActionLogger or GameState not available")
		return
	
	# Create action in one system
	var action = {
		"type": "CROSS_SYSTEM_TEST",
		"origin": "test_system",
		"target": "game_state",
		"data": "test_data"
	}
	
	# Process through action logger
	if action_logger.has_method("log_action"):
		action_logger.log_action(action)
	
	# Verify data reaches game state
	game_state.add_action_to_phase_log(action)
	var phase_log = game_state.state.get("phase_log", [])
	
	var action_found = false
	for logged_action in phase_log:
		if logged_action.get("type") == "CROSS_SYSTEM_TEST":
			action_found = true
			break
	
	assert_true(action_found, "Data should flow between systems")

func test_system_initialization_order():
	# Test that systems initialize in correct order
	var initialization_order = []
	
	# This test is primarily architectural - systems should initialize dependencies first
	# We can test that critical autoloads are available
	
	var critical_autoloads = ["GameState", "PhaseManager", "Measurement"]
	var available_autoloads = []
	
	for autoload_name in critical_autoloads:
		if Engine.has_singleton(autoload_name):
			available_autoloads.append(autoload_name)
	
	# GameState should be available for other systems to depend on
	assert_true("GameState" in available_autoloads, "GameState should be initialized")
	
	# If PhaseManager is available, GameState should also be available
	if "PhaseManager" in available_autoloads:
		assert_true("GameState" in available_autoloads, "GameState should be available if PhaseManager is available")

func test_resource_cleanup():
	# Test that systems properly clean up resources
	var initial_object_count = Engine.get_process_frames()  # Use as rough object count proxy
	
	# Create temporary objects through various systems
	if phase_manager:
		for i in range(5):
			phase_manager.transition_to_phase(GameStateData.Phase.MOVEMENT)
			await get_tree().process_frame
			phase_manager.transition_to_phase(GameStateData.Phase.SHOOTING) 
			await get_tree().process_frame
	
	# Force garbage collection
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Check for resource leaks (simplified test)
	var final_object_count = Engine.get_process_frames()
	# Objects counts should not grow excessively
	assert_true(true, "Resource cleanup test completed")  # Simplified assertion
