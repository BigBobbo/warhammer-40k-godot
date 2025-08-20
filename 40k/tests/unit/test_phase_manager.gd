extends GutTest

# Unit tests for PhaseManager autoload
# Tests phase transition orchestration and signal management

var test_phase_manager: Node
var mock_game_state: GameStateData
var phase_changed_received: bool = false
var phase_completed_received: bool = false
var action_taken_received: bool = false
var last_phase_changed: GameStateData.Phase
var last_action: Dictionary

func before_each():
	# Create a mock GameState for testing
	mock_game_state = GameStateData.new()
	mock_game_state.initialize_default_state()
	
	# Create PhaseManager instance
	test_phase_manager = preload("res://autoloads/PhaseManager.gd").new()
	add_child(test_phase_manager)
	
	# Connect to signals for testing
	test_phase_manager.phase_changed.connect(_on_phase_changed)
	test_phase_manager.phase_completed.connect(_on_phase_completed)
	test_phase_manager.phase_action_taken.connect(_on_phase_action_taken)
	
	# Reset signal flags
	phase_changed_received = false
	phase_completed_received = false
	action_taken_received = false
	last_phase_changed = GameStateData.Phase.DEPLOYMENT
	last_action = {}

func after_each():
	if test_phase_manager:
		test_phase_manager.queue_free()
	if mock_game_state:
		mock_game_state.queue_free()

func _on_phase_changed(phase: GameStateData.Phase):
	phase_changed_received = true
	last_phase_changed = phase

func _on_phase_completed(phase: GameStateData.Phase):
	phase_completed_received = true

func _on_phase_action_taken(action: Dictionary):
	action_taken_received = true
	last_action = action

# Test phase class registration
func test_register_phase_classes():
	test_phase_manager.register_phase_classes()
	
	var phase_classes = test_phase_manager.phase_classes
	assert_not_null(phase_classes, "Phase classes should be registered")
	
	# Check all phases are registered
	var required_phases = [
		GameStateData.Phase.DEPLOYMENT,
		GameStateData.Phase.MOVEMENT,
		GameStateData.Phase.SHOOTING,
		GameStateData.Phase.CHARGE,
		GameStateData.Phase.FIGHT,
		GameStateData.Phase.MORALE
	]
	
	for phase in required_phases:
		assert_true(phase_classes.has(phase), "Should have phase class for " + str(phase))
		assert_not_null(phase_classes[phase], "Phase class should not be null")

# Test phase transitions
func test_transition_to_phase():
	# Mock the GameState calls since we can't easily replace the autoload in tests
	if not Engine.has_singleton("GameState"):
		skip_test("GameState autoload not available in test environment")
		return
	
	test_phase_manager.transition_to_phase(GameStateData.Phase.MOVEMENT)
	
	assert_true(phase_changed_received, "phase_changed signal should be emitted")
	assert_eq(GameStateData.Phase.MOVEMENT, last_phase_changed, "Should transition to MOVEMENT phase")
	assert_not_null(test_phase_manager.current_phase_instance, "Should have phase instance")

func test_get_current_phase():
	# This depends on GameState autoload, so we'll test the method exists
	assert_true(test_phase_manager.has_method("get_current_phase"), "Should have get_current_phase method")

func test_get_current_phase_instance():
	var instance = test_phase_manager.get_current_phase_instance()
	# Initially might be null until transition happens
	assert_true(instance == null or instance is BasePhase, "Should return BasePhase or null")

# Test phase progression
func test_get_next_phase():
	var next_from_deployment = test_phase_manager._get_next_phase(GameStateData.Phase.DEPLOYMENT)
	assert_eq(GameStateData.Phase.MOVEMENT, next_from_deployment, "After DEPLOYMENT should be MOVEMENT")
	
	var next_from_movement = test_phase_manager._get_next_phase(GameStateData.Phase.MOVEMENT)
	assert_eq(GameStateData.Phase.SHOOTING, next_from_movement, "After MOVEMENT should be SHOOTING")
	
	var next_from_shooting = test_phase_manager._get_next_phase(GameStateData.Phase.SHOOTING)
	assert_eq(GameStateData.Phase.CHARGE, next_from_shooting, "After SHOOTING should be CHARGE")
	
	var next_from_charge = test_phase_manager._get_next_phase(GameStateData.Phase.CHARGE)
	assert_eq(GameStateData.Phase.FIGHT, next_from_charge, "After CHARGE should be FIGHT")
	
	var next_from_fight = test_phase_manager._get_next_phase(GameStateData.Phase.FIGHT)
	assert_eq(GameStateData.Phase.MORALE, next_from_fight, "After FIGHT should be MORALE")
	
	var next_from_morale = test_phase_manager._get_next_phase(GameStateData.Phase.MORALE)
	assert_eq(GameStateData.Phase.DEPLOYMENT, next_from_morale, "After MORALE should be DEPLOYMENT (next turn)")

func test_advance_to_next_phase():
	if not Engine.has_singleton("GameState"):
		skip_test("GameState autoload not available in test environment")
		return
	
	# This method relies on get_current_phase which needs GameState
	assert_true(test_phase_manager.has_method("advance_to_next_phase"), "Should have advance_to_next_phase method")

# Test signal handling
func test_on_phase_completed():
	if not Engine.has_singleton("GameState"):
		skip_test("GameState autoload not available in test environment")
		return
	
	# Test the signal handler method exists and is callable
	assert_true(test_phase_manager.has_method("_on_phase_completed"), "Should have _on_phase_completed method")
	
	# Call it directly to test the logic
	test_phase_manager._on_phase_completed()
	assert_true(phase_completed_received, "phase_completed signal should be emitted")

func test_on_phase_action_taken():
	if not Engine.has_singleton("GameState"):
		skip_test("GameState autoload not available in test environment") 
		return
	
	var test_action = {"type": "test", "unit_id": "test_unit"}
	test_phase_manager._on_phase_action_taken(test_action)
	
	assert_true(action_taken_received, "phase_action_taken signal should be emitted")
	assert_eq(test_action, last_action, "Should receive the correct action")

# Test state management utilities
func test_get_game_state_snapshot():
	if not Engine.has_singleton("GameState"):
		skip_test("GameState autoload not available in test environment")
		return
	
	var snapshot = test_phase_manager.get_game_state_snapshot()
	assert_not_null(snapshot, "Should return a snapshot")
	assert_true(snapshot is Dictionary, "Snapshot should be a dictionary")

func test_apply_state_changes():
	if not Engine.has_singleton("GameState"):
		skip_test("GameState autoload not available in test environment")
		return
	
	var changes = [
		{"op": "set", "path": "meta.turn_number", "value": 5}
	]
	
	# Test that method exists and is callable
	assert_true(test_phase_manager.has_method("apply_state_changes"), "Should have apply_state_changes method")
	test_phase_manager.apply_state_changes(changes)

# Test individual state change operations
func test_apply_single_change_set():
	if not Engine.has_singleton("GameState"):
		skip_test("GameState autoload not available in test environment")
		return
	
	var change = {"op": "set", "path": "meta.turn_number", "value": 10}
	test_phase_manager._apply_single_change(change)
	# We can't easily verify this without mocking GameState, but we can test it doesn't crash

func test_apply_single_change_unknown_op():
	var change = {"op": "unknown_operation", "path": "some.path", "value": "test"}
	
	# Should handle unknown operations gracefully (push_error but not crash)
	test_phase_manager._apply_single_change(change)
	assert_true(true, "Should handle unknown operations without crashing")

# Test path parsing for state changes
func test_set_state_value_simple_path():
	if not Engine.has_singleton("GameState"):
		skip_test("GameState autoload not available in test environment")
		return
	
	# Test that method exists
	assert_true(test_phase_manager.has_method("_set_state_value"), "Should have _set_state_value method")

func test_add_to_state_array():
	if not Engine.has_singleton("GameState"):
		skip_test("GameState autoload not available in test environment")
		return
	
	# Test that method exists
	assert_true(test_phase_manager.has_method("_add_to_state_array"), "Should have _add_to_state_array method")

func test_remove_from_state_array():
	if not Engine.has_singleton("GameState"):
		skip_test("GameState autoload not available in test environment")
		return
	
	# Test that method exists
	assert_true(test_phase_manager.has_method("_remove_from_state_array"), "Should have _remove_from_state_array method")

# Test validation methods
func test_validate_phase_action():
	# With no current phase instance, should return valid
	var result = test_phase_manager.validate_phase_action({"type": "test"})
	assert_not_null(result, "Should return validation result")
	assert_true(result.has("valid"), "Result should have valid field")
	assert_true(result.get("valid", false), "Should be valid when no phase instance")
	assert_true(result.has("errors"), "Result should have errors array")

func test_get_available_actions():
	# With no current phase instance, should return empty array
	var actions = test_phase_manager.get_available_actions()
	assert_not_null(actions, "Should return actions array")
	assert_true(actions is Array, "Should return an array")
	assert_eq(0, actions.size(), "Should be empty when no phase instance")

# Test error handling
func test_transition_to_invalid_phase():
	# Try to transition to a phase that doesn't exist in phase_classes
	test_phase_manager.phase_classes = {}  # Clear phase classes
	
	# This should push an error but not crash
	test_phase_manager.transition_to_phase(GameStateData.Phase.MOVEMENT)
	assert_null(test_phase_manager.current_phase_instance, "Should not have phase instance for invalid phase")

# Test initialization 
func test_ready_initialization():
	# Create a fresh PhaseManager to test _ready
	var fresh_manager = preload("res://autoloads/PhaseManager.gd").new()
	add_child(fresh_manager)
	
	# Call _ready manually since add_child may not trigger it in tests
	fresh_manager._ready()
	
	# Verify phase classes are registered
	assert_not_null(fresh_manager.phase_classes, "Phase classes should be registered after _ready")
	assert_gt(fresh_manager.phase_classes.size(), 0, "Should have registered phase classes")
	
	fresh_manager.queue_free()

# Integration-style tests (limited without full scene setup)
func test_phase_instance_lifecycle():
	if not Engine.has_singleton("GameState"):
		skip_test("GameState autoload not available in test environment")
		return
	
	# Test the basic lifecycle: transition should create instance
	assert_null(test_phase_manager.current_phase_instance, "Should start with no phase instance")
	
	test_phase_manager.transition_to_phase(GameStateData.Phase.MOVEMENT)
	
	var first_instance = test_phase_manager.current_phase_instance
	assert_not_null(first_instance, "Should have phase instance after transition")
	
	# Transition to another phase should replace instance  
	test_phase_manager.transition_to_phase(GameStateData.Phase.SHOOTING)
	
	var second_instance = test_phase_manager.current_phase_instance
	assert_not_null(second_instance, "Should have new phase instance")
	assert_ne(first_instance, second_instance, "Should be different instance")

# Test method existence (for methods that depend on external dependencies)
func test_required_methods_exist():
	var required_methods = [
		"register_phase_classes",
		"transition_to_phase", 
		"get_current_phase",
		"get_current_phase_instance",
		"advance_to_next_phase",
		"get_game_state_snapshot",
		"apply_state_changes",
		"validate_phase_action",
		"get_available_actions"
	]
	
	for method_name in required_methods:
		assert_true(test_phase_manager.has_method(method_name), "Should have method: " + method_name)

# Test signal definitions
func test_required_signals_exist():
	var required_signals = [
		"phase_changed",
		"phase_completed", 
		"phase_action_taken"
	]
	
	for signal_name in required_signals:
		assert_true(test_phase_manager.has_signal(signal_name), "Should have signal: " + signal_name)