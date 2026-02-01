extends "res://addons/gut/test.gd"

# Unit tests for DebugManager functionality
# Tests debug mode toggle, state preservation, and visual feedback

var debug_manager: Node

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	# Get reference to the DebugManager autoload
	debug_manager = DebugManager
	
	# Ensure debug mode is off at start of each test
	if debug_manager.is_debug_active():
		debug_manager.exit_debug_mode()
	
	assert_false(debug_manager.is_debug_active(), "Debug mode should be off initially")

func after_each():
	# Clean up debug state after each test
	if debug_manager.is_debug_active():
		debug_manager.exit_debug_mode()

func test_debug_mode_toggle():
	# Test entering debug mode
	debug_manager.enter_debug_mode()
	assert_true(debug_manager.is_debug_active(), "Debug mode should be active after enter")
	
	# Test exiting debug mode
	debug_manager.exit_debug_mode()
	assert_false(debug_manager.is_debug_active(), "Debug mode should be inactive after exit")

func test_debug_mode_signal_emission():
	var signal_watcher = watch_signals(debug_manager)
	
	# Test entering debug mode emits signal
	debug_manager.enter_debug_mode()
	assert_signal_emitted(debug_manager, "debug_mode_changed")
	assert_signal_emitted_with_parameters(debug_manager, "debug_mode_changed", [true])
	
	# Test exiting debug mode emits signal
	debug_manager.exit_debug_mode()
	assert_signal_emitted_with_parameters(debug_manager, "debug_mode_changed", [false])

func test_debug_mode_toggle_function():
	var initial_state = debug_manager.is_debug_active()
	
	# Toggle should change state
	debug_manager.toggle_debug_mode()
	assert_ne(initial_state, debug_manager.is_debug_active(), "Toggle should change debug state")
	
	# Toggle again should return to original state
	debug_manager.toggle_debug_mode()
	assert_eq(initial_state, debug_manager.is_debug_active(), "Second toggle should return to original state")

func test_phase_state_preservation():
	# Mock having a phase active
	if GameState:
		var original_phase = GameState.get_current_phase()
		
		debug_manager.enter_debug_mode()
		assert_true(debug_manager.was_in_phase, "Should record that we were in a phase")
		assert_eq(debug_manager.previous_phase, original_phase, "Should store the original phase")
		
		debug_manager.exit_debug_mode()
		# Phase should remain unchanged since we don't actually change it
		assert_eq(GameState.get_current_phase(), original_phase, "Phase should be preserved")

func test_debug_input_handling_activation():
	# Initially should not be processing input
	assert_false(debug_manager.is_processing_unhandled_input(), "Should not process input initially")
	
	debug_manager.enter_debug_mode()
	assert_true(debug_manager.is_processing_unhandled_input(), "Should process input in debug mode")
	
	debug_manager.exit_debug_mode()
	assert_false(debug_manager.is_processing_unhandled_input(), "Should not process input after exit")

func test_model_finding_algorithm():
	# Test the debug model finding function with mock data
	if not GameState:
		pending("GameState not available for test")
		return
	
	# Create mock game state with test units
	var mock_state = {
		"units": {
			"test_unit_1": {
				"models": [
					{
						"id": "model_1",
						"alive": true,
						"position": {"x": 100.0, "y": 100.0}
					},
					{
						"id": "model_2", 
						"alive": true,
						"position": {"x": 200.0, "y": 200.0}
					}
				]
			}
		}
	}
	
	# Temporarily replace game state
	var original_state = GameState.state
	GameState.state = mock_state
	
	# Test finding model at exact position
	var found_model = debug_manager._find_model_at_position_debug(Vector2(100, 100))
	assert_false(found_model.is_empty(), "Should find model at exact position")
	assert_eq(found_model.get("model_id"), "model_1", "Should find correct model")
	assert_eq(found_model.get("unit_id"), "test_unit_1", "Should identify correct unit")
	
	# Test finding model within click radius
	found_model = debug_manager._find_model_at_position_debug(Vector2(110, 110))
	assert_false(found_model.is_empty(), "Should find model within click radius")
	
	# Test not finding model outside click radius
	found_model = debug_manager._find_model_at_position_debug(Vector2(500, 500))
	assert_true(found_model.is_empty(), "Should not find model outside click radius")
	
	# Restore original game state
	GameState.state = original_state

func test_model_position_update():
	if not GameState:
		pending("GameState not available for test")
		return
	
	# Create mock game state
	var mock_state = {
		"units": {
			"test_unit": {
				"models": [
					{
						"id": "test_model",
						"alive": true,
						"position": {"x": 100.0, "y": 100.0}
					}
				]
			}
		}
	}
	
	var original_state = GameState.state
	GameState.state = mock_state
	
	# Test updating model position
	debug_manager._update_model_position_debug("test_unit", "test_model", Vector2(300, 400))
	
	var updated_unit = GameState.state.units["test_unit"]
	var updated_model = updated_unit.models[0]
	
	assert_eq(updated_model.position.x, 300.0, "X position should be updated")
	assert_eq(updated_model.position.y, 400.0, "Y position should be updated")
	
	# Restore original state
	GameState.state = original_state

func test_debug_constants():
	# Test that required constants are defined
	assert_true(debug_manager.TOKEN_CLICK_RADIUS > 0, "TOKEN_CLICK_RADIUS should be positive")
	assert_eq(debug_manager.TOKEN_CLICK_RADIUS, 30.0, "TOKEN_CLICK_RADIUS should match expected value")

# Test error handling
func test_invalid_unit_position_update():
	if not GameState:
		pending("GameState not available for test")
		return
	
	var original_state = GameState.state
	GameState.state = {"units": {}}  # Empty units
	
	# This should not crash, just log an error
	debug_manager._update_model_position_debug("nonexistent_unit", "nonexistent_model", Vector2(0, 0))
	
	# Should still have empty units (no crash)
	assert_true(GameState.state.units.is_empty(), "Should handle invalid unit gracefully")
	
	GameState.state = original_state

func test_debug_drag_state_management():
	# Test debug drag state tracking
	assert_false(debug_manager.debug_drag_active, "Debug drag should be inactive initially")
	assert_true(debug_manager.debug_selected_model.is_empty(), "No model should be selected initially")
	
	debug_manager.enter_debug_mode()
	
	# Simulate starting a drag (this would normally be done through input)
	debug_manager.debug_drag_active = true
	debug_manager.debug_selected_model = {"unit_id": "test", "model_id": "model1"}
	
	assert_true(debug_manager.debug_drag_active, "Debug drag should be active")
	assert_false(debug_manager.debug_selected_model.is_empty(), "Selected model should be tracked")
	
	debug_manager.exit_debug_mode()
	
	# Exit should clear drag state
	assert_false(debug_manager.debug_drag_active, "Debug drag should be cleared on exit")
	assert_true(debug_manager.debug_selected_model.is_empty(), "Selected model should be cleared on exit")

func test_multiple_enter_exit_calls():
	# Test that multiple enter calls don't break anything
	debug_manager.enter_debug_mode()
	assert_true(debug_manager.is_debug_active(), "First enter should activate debug mode")
	
	debug_manager.enter_debug_mode()  # Second call
	assert_true(debug_manager.is_debug_active(), "Second enter should not break anything")
	
	# Test that multiple exit calls don't break anything
	debug_manager.exit_debug_mode()
	assert_false(debug_manager.is_debug_active(), "First exit should deactivate debug mode")
	
	debug_manager.exit_debug_mode()  # Second call
	assert_false(debug_manager.is_debug_active(), "Second exit should not break anything")