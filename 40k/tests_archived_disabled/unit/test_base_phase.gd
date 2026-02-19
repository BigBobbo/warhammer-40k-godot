extends "res://addons/gut/test.gd"
const GameStateData = preload("res://autoloads/GameState.gd")
const BasePhase = preload("res://phases/BasePhase.gd")

# Unit tests for BasePhase class
# Tests the abstract base functionality that all phases inherit

var test_base_phase: Node  # Use Node type since we're using concrete implementation
var test_snapshot: Dictionary
var action_taken_received: bool = false
var phase_completed_received: bool = false
var last_action_received: Dictionary

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	# Use concrete MovementPhase for testing BasePhase functionality
	var MovementPhaseScript = preload("res://phases/MovementPhase.gd")
	test_base_phase = MovementPhaseScript.new()
	add_child(test_base_phase)
	
	# Create test snapshot using TestDataFactory
	test_snapshot = TestDataFactory.create_test_game_state()
	
	# Connect signals
	test_base_phase.action_taken.connect(_on_action_taken)
	test_base_phase.phase_completed.connect(_on_phase_completed)
	
	# Reset signal flags
	action_taken_received = false
	phase_completed_received = false
	last_action_received = {}

func after_each():
	if test_base_phase:
		test_base_phase.queue_free()

func _on_action_taken(action: Dictionary):
	action_taken_received = true
	last_action_received = action

func _on_phase_completed():
	phase_completed_received = true

# Test lifecycle methods
func test_enter_phase():
	assert_true(test_base_phase.game_state_snapshot.is_empty(), "Should start with empty snapshot")
	
	test_base_phase.enter_phase(test_snapshot)
	
	assert_false(test_base_phase.game_state_snapshot.is_empty(), "Should have snapshot after enter_phase")
	assert_eq(test_snapshot, test_base_phase.game_state_snapshot, "Should store the provided snapshot")

func test_exit_phase():
	test_base_phase.enter_phase(test_snapshot)
	
	# Should not crash when calling exit_phase
	test_base_phase.exit_phase()
	assert_true(true, "exit_phase should complete without error")

func test_on_phase_enter_override():
	# Base implementation should do nothing
	test_base_phase._on_phase_enter()
	assert_true(true, "_on_phase_enter should complete without error")

func test_on_phase_exit_override():
	# Base implementation should do nothing  
	test_base_phase._on_phase_exit()
	assert_true(true, "_on_phase_exit should complete without error")

# Test action validation
func test_validate_action_default():
	var action = {"type": "test_action"}
	var result = test_base_phase.validate_action(action)
	
	assert_not_null(result, "Should return validation result")
	assert_true(result.has("valid"), "Result should have valid field")
	assert_true(result.has("errors"), "Result should have errors field")
	assert_true(result.valid, "Base implementation should return valid=true")
	assert_eq(0, result.errors.size(), "Base implementation should have no errors")

# Test available actions
func test_get_available_actions_default():
	var actions = test_base_phase.get_available_actions()
	
	assert_not_null(actions, "Should return actions array")
	assert_true(actions is Array, "Should return an array")
	assert_eq(0, actions.size(), "Base implementation should return empty array")

# Test action processing
func test_process_action_default():
	var action = {"type": "test_action"}
	var result = test_base_phase.process_action(action)
	
	assert_not_null(result, "Should return processing result")
	assert_true(result.has("success"), "Result should have success field")
	assert_false(result.success, "Base implementation should return success=false")
	assert_true(result.has("error"), "Result should have error field")
	assert_eq("Not implemented", result.error, "Should return 'Not implemented' error")

# Test action execution
func test_execute_action_with_invalid_action():
	# Create a mock BasePhase that returns invalid validation
	var MovementPhaseScript = preload("res://phases/MovementPhase.gd")
	var custom_phase = MovementPhaseScript.new()
	# Note: GDScript doesn't support method reassignment, this test needs refactoring
	# custom_phase.validate_action = func(action): return {"valid": false, "errors": ["Test error"]}
	add_child(custom_phase)
	
	var action = {"type": "invalid_action"}
	var result = custom_phase.execute_action(action)
	
	assert_not_null(result, "Should return execution result")
	assert_false(result.success, "Should return success=false for invalid action")
	assert_true(result.has("errors"), "Should have errors field")
	assert_eq("Test error", result.errors[0], "Should include validation errors")
	
	custom_phase.queue_free()

func test_execute_action_with_valid_action():
	if not Engine.has_singleton("PhaseManager"):
		pending("PhaseManager autoload not available in test environment")
		return

	# Create a mock phase that returns successful processing
	var MovementPhaseScript = preload("res://phases/MovementPhase.gd")
	var custom_phase = MovementPhaseScript.new()
	# Note: GDScript doesn't support method reassignment, this test needs refactoring
	# custom_phase.validate_action = func(action): return {"valid": true, "errors": []}
	# custom_phase.process_action = func(action): return {"success": true, "changes": []}
	# custom_phase._should_complete_phase = func(): return false
	add_child(custom_phase)
	
	# Connect signal to verify it's emitted
	custom_phase.action_taken.connect(_on_action_taken)
	
	var action = {"type": "valid_action"}
	var result = custom_phase.execute_action(action)
	
	assert_not_null(result, "Should return execution result")
	assert_true(result.success, "Should return success=true for valid action")
	assert_true(action_taken_received, "Should emit action_taken signal")
	assert_eq(action, last_action_received, "Should emit the correct action")
	
	custom_phase.queue_free()

func test_execute_action_with_phase_completion():
	if not Engine.has_singleton("PhaseManager"):
		pending("PhaseManager autoload not available in test environment")
		return

	# Create a mock phase that completes after the action
	var MovementPhaseScript = preload("res://phases/MovementPhase.gd")
	var custom_phase = MovementPhaseScript.new()
	# Note: GDScript doesn't support method reassignment, this test needs refactoring
	# custom_phase.validate_action = func(action): return {"valid": true, "errors": []}
	# custom_phase.process_action = func(action): return {"success": true, "changes": []}
	# custom_phase._should_complete_phase = func(): return true  # Always complete
	add_child(custom_phase)
	
	custom_phase.phase_completed.connect(_on_phase_completed)
	
	var action = {"type": "completing_action"}
	var result = custom_phase.execute_action(action)
	
	assert_true(result.success, "Action should succeed")
	assert_true(phase_completed_received, "Should emit phase_completed signal")
	
	custom_phase.queue_free()

# Test completion logic
func test_should_complete_phase_default():
	var should_complete = test_base_phase._should_complete_phase()
	assert_false(should_complete, "Base implementation should return false")

# Test utility methods
func test_get_current_player():
	if not Engine.has_singleton("GameState"):
		pending("GameState autoload not available in test environment")
		return
	
	var player = test_base_phase.get_current_player()
	assert_true(player is int, "Should return an integer")
	assert_gt(player, 0, "Player should be positive")

func test_get_turn_number():
	test_base_phase.enter_phase(test_snapshot)
	
	var turn = test_base_phase.get_turn_number()
	assert_eq(1, turn, "Should return turn number from snapshot")

func test_get_turn_number_no_snapshot():
	# Without snapshot, should return default value
	var turn = test_base_phase.get_turn_number()
	assert_eq(1, turn, "Should return default turn number")

func test_get_units_for_player():
	test_base_phase.enter_phase(test_snapshot)
	
	var player1_units = test_base_phase.get_units_for_player(1)
	var player2_units = test_base_phase.get_units_for_player(2)
	
	assert_not_null(player1_units, "Should return units for player 1")
	assert_not_null(player2_units, "Should return units for player 2")
	assert_true(player1_units is Dictionary, "Should return dictionary")
	assert_true(player2_units is Dictionary, "Should return dictionary")
	
	# Check that units belong to correct players
	for unit_id in player1_units:
		var unit = player1_units[unit_id]
		assert_eq(1, unit.get("owner", 0), "Player 1 unit should have owner=1")
	
	for unit_id in player2_units:
		var unit = player2_units[unit_id]
		assert_eq(2, unit.get("owner", 0), "Player 2 unit should have owner=2")

func test_get_units_for_player_no_snapshot():
	# Without snapshot, should return empty
	var units = test_base_phase.get_units_for_player(1)
	assert_true(units.is_empty(), "Should return empty dict without snapshot")

func test_get_unit():
	test_base_phase.enter_phase(test_snapshot)
	
	var unit = test_base_phase.get_unit("test_unit_1")
	assert_not_null(unit, "Should find existing unit")
	assert_eq("test_unit_1", unit.get("id", ""), "Should return correct unit")
	
	var missing_unit = test_base_phase.get_unit("nonexistent")
	assert_true(missing_unit.is_empty(), "Should return empty dict for missing unit")

func test_get_deployment_zone_for_player():
	test_base_phase.enter_phase(test_snapshot)
	
	var zone1 = test_base_phase.get_deployment_zone_for_player(1)
	var zone2 = test_base_phase.get_deployment_zone_for_player(2)
	
	# Note: TestDataFactory might not include deployment zones, so we test the method works
	assert_not_null(zone1, "Should return a result for player 1")
	assert_not_null(zone2, "Should return a result for player 2")
	assert_true(zone1 is Dictionary, "Should return dictionary")
	assert_true(zone2 is Dictionary, "Should return dictionary")

func test_get_deployment_zone_no_snapshot():
	# Without snapshot, should return empty
	var zone = test_base_phase.get_deployment_zone_for_player(1)
	assert_true(zone.is_empty(), "Should return empty dict without snapshot")

# Test helper methods
func test_create_action():
	if not Engine.has_singleton("GameState"):
		pending("GameState autoload not available in test environment")
		return
	
	test_base_phase.enter_phase(test_snapshot)
	test_base_phase.phase_type = GameStateData.Phase.MOVEMENT
	
	var action = test_base_phase.create_action("move_unit", {"unit_id": "test_unit"})
	
	assert_not_null(action, "Should create action")
	assert_eq("move_unit", action.type, "Should have correct type")
	assert_eq(GameStateData.Phase.MOVEMENT, action.phase, "Should have correct phase")
	assert_eq("test_unit", action.unit_id, "Should include parameters")
	assert_true(action.has("player"), "Should have player field")
	assert_true(action.has("turn"), "Should have turn field") 
	assert_true(action.has("timestamp"), "Should have timestamp field")

func test_create_action_no_parameters():
	if not Engine.has_singleton("GameState"):
		pending("GameState autoload not available in test environment")
		return
	
	test_base_phase.enter_phase(test_snapshot)
	test_base_phase.phase_type = GameStateData.Phase.SHOOTING
	
	var action = test_base_phase.create_action("end_phase")
	
	assert_eq("end_phase", action.type, "Should have correct type")
	assert_eq(GameStateData.Phase.SHOOTING, action.phase, "Should have correct phase")

func test_create_result_success():
	test_base_phase.phase_type = GameStateData.Phase.CHARGE
	
	var changes = [{"op": "set", "path": "test", "value": "data"}]
	var result = test_base_phase.create_result(true, changes)
	
	assert_not_null(result, "Should create result")
	assert_true(result.success, "Should be successful")
	assert_eq(GameStateData.Phase.CHARGE, result.phase, "Should have correct phase")
	assert_eq(changes, result.changes, "Should include changes")
	assert_true(result.has("timestamp"), "Should have timestamp")
	assert_false(result.has("error"), "Should not have error field for success")

func test_create_result_failure():
	test_base_phase.phase_type = GameStateData.Phase.FIGHT
	
	var result = test_base_phase.create_result(false, [], "Test error")
	
	assert_false(result.success, "Should be unsuccessful")
	assert_eq("Test error", result.error, "Should include error message")
	assert_eq(GameStateData.Phase.FIGHT, result.phase, "Should have correct phase")
	assert_false(result.has("changes"), "Should not have changes field for failure")

func test_update_local_state():
	var original_snapshot = TestDataFactory.create_clean_state()
	var new_snapshot = TestDataFactory.create_test_game_state()
	
	test_base_phase.enter_phase(original_snapshot)
	assert_eq(original_snapshot, test_base_phase.game_state_snapshot, "Should have original snapshot")
	
	test_base_phase.update_local_state(new_snapshot)
	assert_eq(new_snapshot, test_base_phase.game_state_snapshot, "Should update to new snapshot")

func test_log_phase_message():
	test_base_phase.phase_type = GameStateData.Phase.MORALE
	
	# Should not crash when logging
	test_base_phase.log_phase_message("Test message")
	test_base_phase.log_phase_message("Warning message", "WARN")
	test_base_phase.log_phase_message("Error message", "ERROR")
	
	assert_true(true, "Logging should complete without error")

# Test signals
func test_signals_exist():
	assert_true(test_base_phase.has_signal("phase_completed"), "Should have phase_completed signal")
	assert_true(test_base_phase.has_signal("action_taken"), "Should have action_taken signal")

func test_signal_emission_action_taken():
	var test_action = {"type": "test"}
	
	test_base_phase.action_taken.connect(_on_action_taken)
	test_base_phase.emit_signal("action_taken", test_action)
	
	assert_true(action_taken_received, "Should receive action_taken signal")
	assert_eq(test_action, last_action_received, "Should receive correct action")

func test_signal_emission_phase_completed():
	test_base_phase.phase_completed.connect(_on_phase_completed)
	test_base_phase.emit_signal("phase_completed")
	
	assert_true(phase_completed_received, "Should receive phase_completed signal")

# Test properties and state
func test_initial_state():
	assert_true(test_base_phase.game_state_snapshot.is_empty(), "Should start with empty snapshot")
	# phase_type is not set by default in BasePhase

func test_phase_type_property():
	test_base_phase.phase_type = GameStateData.Phase.DEPLOYMENT
	assert_eq(GameStateData.Phase.DEPLOYMENT, test_base_phase.phase_type, "Should set phase type")

# Test method existence
func test_all_methods_exist():
	var required_methods = [
		"enter_phase",
		"exit_phase",
		"_on_phase_enter",
		"_on_phase_exit",
		"validate_action",
		"get_available_actions",
		"process_action",
		"execute_action",
		"_should_complete_phase",
		"get_current_player",
		"get_turn_number",
		"get_units_for_player",
		"get_unit",
		"get_deployment_zone_for_player",
		"create_action",
		"create_result",
		"update_local_state",
		"log_phase_message"
	]
	
	for method_name in required_methods:
		assert_true(test_base_phase.has_method(method_name), "Should have method: " + method_name)

# Test inheritance behavior
func test_extends_node():
	assert_true(test_base_phase is Node, "Should extend Node")
	assert_true(test_base_phase is BasePhase, "Should be instance of BasePhase")

# Test error handling
func test_empty_snapshot_handling():
	# Methods should handle empty snapshots gracefully
	test_base_phase.enter_phase({})
	
	var units = test_base_phase.get_units_for_player(1)
	assert_true(units.is_empty(), "Should return empty units for empty snapshot")
	
	var unit = test_base_phase.get_unit("test")
	assert_true(unit.is_empty(), "Should return empty unit for empty snapshot")
	
	var zone = test_base_phase.get_deployment_zone_for_player(1)
	assert_true(zone.is_empty(), "Should return empty zone for empty snapshot")
	
	var turn = test_base_phase.get_turn_number()
	assert_eq(1, turn, "Should return default turn for empty snapshot")

# Test edge cases
func test_invalid_player_ids():
	test_base_phase.enter_phase(test_snapshot)
	
	var units_negative = test_base_phase.get_units_for_player(-1)
	assert_true(units_negative.is_empty(), "Should return empty for invalid player ID")
	
	var units_zero = test_base_phase.get_units_for_player(0)
	assert_true(units_zero.is_empty(), "Should return empty for player ID 0")
	
	var units_large = test_base_phase.get_units_for_player(999)
	assert_true(units_large.is_empty(), "Should return empty for non-existent player")
