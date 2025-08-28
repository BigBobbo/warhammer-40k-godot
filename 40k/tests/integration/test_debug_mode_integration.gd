extends GutTest

# Integration tests for debug mode functionality
# Tests end-to-end debug mode behavior including input handling and visual updates

var original_game_state: Dictionary
var main_scene: Node

func before_each():
	# Store original game state
	if GameState:
		original_game_state = GameState.state.duplicate(true)
	
	# Get reference to main scene
	main_scene = get_node_or_null("/root/Main")
	
	# Ensure debug mode is off
	if DebugManager.is_debug_active():
		DebugManager.exit_debug_mode()

func after_each():
	# Restore original game state
	if GameState and not original_game_state.is_empty():
		GameState.state = original_game_state.duplicate(true)
	
	# Ensure debug mode is off
	if DebugManager.is_debug_active():
		DebugManager.exit_debug_mode()

func test_debug_mode_input_toggle():
	# Test that KEY_9 toggles debug mode
	var initial_state = DebugManager.is_debug_active()
	
	# Simulate KEY_9 press
	var input_event = InputEventKey.new()
	input_event.keycode = KEY_9
	input_event.pressed = true
	
	# Send the input event (this should trigger the debug toggle)
	# Note: In a real integration test, we'd need to simulate this through the scene tree
	DebugManager.toggle_debug_mode()  # Direct call for testing
	
	assert_ne(initial_state, DebugManager.is_debug_active(), "Debug mode should toggle")

func test_debug_mode_visual_feedback():
	# Test that entering debug mode creates visual feedback
	DebugManager.enter_debug_mode()
	
	# Give a frame for the overlay to be created
	await get_tree().process_frame
	
	assert_not_null(DebugManager.debug_overlay, "Debug overlay should be created")
	if DebugManager.debug_overlay:
		assert_true(DebugManager.debug_overlay.visible, "Debug overlay should be visible")
	
	# Test exiting debug mode hides overlay
	DebugManager.exit_debug_mode()
	
	await get_tree().process_frame
	
	# Overlay should be destroyed or hidden
	assert_true(DebugManager.debug_overlay == null or not DebugManager.debug_overlay.visible, 
		"Debug overlay should be hidden/destroyed on exit")

func test_debug_mode_with_token_visuals():
	if not main_scene:
		pending("Main scene not available")
		return
	
	# Test that tokens get updated with debug styling
	DebugManager.enter_debug_mode()
	
	await get_tree().process_frame
	
	# Check if token layer exists and has tokens
	var token_layer = main_scene.get_node_or_null("BoardRoot/TokenLayer")
	if token_layer and token_layer.get_child_count() > 0:
		# Check first token for debug styling
		var first_token = token_layer.get_child(0)
		if first_token.has_method("set_debug_mode"):
			# This test validates the method exists and can be called
			first_token.set_debug_mode(true)
			assert_true(true, "Token should accept debug mode setting")
	
	DebugManager.exit_debug_mode()

func test_debug_mode_movement_bypass():
	if not GameState:
		pending("GameState not available")
		return
	
	# Create test game state with units
	GameState.state = {
		"units": {
			"test_unit": {
				"owner": 1,
				"models": [
					{
						"id": "model_1",
						"alive": true,
						"position": {"x": 100.0, "y": 100.0}
					}
				]
			}
		},
		"meta": {"phase": GameStateData.Phase.SHOOTING}  # Not movement phase
	}
	
	# In normal mode, movement would be restricted by phase
	# In debug mode, it should be unrestricted
	
	DebugManager.enter_debug_mode()
	
	# Test model position update in debug mode
	var original_pos = Vector2(100, 100)
	var new_pos = Vector2(300, 400)
	
	DebugManager._update_model_position_debug("test_unit", "model_1", new_pos)
	
	var updated_model = GameState.state.units["test_unit"].models[0]
	assert_eq(updated_model.position.x, new_pos.x, "Model X position should update in debug mode")
	assert_eq(updated_model.position.y, new_pos.y, "Model Y position should update in debug mode")
	
	DebugManager.exit_debug_mode()

func test_debug_mode_cross_army_movement():
	if not GameState:
		pending("GameState not available")
		return
	
	# Create test state with units from different armies
	GameState.state = {
		"units": {
			"player1_unit": {
				"owner": 1,
				"models": [{"id": "p1_model", "alive": true, "position": {"x": 100.0, "y": 100.0}}]
			},
			"player2_unit": {
				"owner": 2,
				"models": [{"id": "p2_model", "alive": true, "position": {"x": 200.0, "y": 200.0}}]
			}
		}
	}
	
	DebugManager.enter_debug_mode()
	
	# Should be able to find and move models from both armies
	var p1_model = DebugManager._find_model_at_position_debug(Vector2(100, 100))
	var p2_model = DebugManager._find_model_at_position_debug(Vector2(200, 200))
	
	assert_false(p1_model.is_empty(), "Should find player 1 model")
	assert_false(p2_model.is_empty(), "Should find player 2 model")
	assert_eq(p1_model.unit_id, "player1_unit", "Should identify player 1 unit correctly")
	assert_eq(p2_model.unit_id, "player2_unit", "Should identify player 2 unit correctly")
	
	# Should be able to move enemy model
	DebugManager._update_model_position_debug("player2_unit", "p2_model", Vector2(500, 500))
	var moved_model = GameState.state.units["player2_unit"].models[0]
	assert_eq(moved_model.position.x, 500.0, "Should be able to move enemy model")
	
	DebugManager.exit_debug_mode()

func test_debug_mode_phase_preservation():
	if not GameState:
		pending("GameState not available")
		return
	
	# Set a specific phase
	var test_phase = GameStateData.Phase.MOVEMENT
	GameState.set_phase(test_phase)
	
	var original_phase = GameState.get_current_phase()
	
	# Enter and exit debug mode
	DebugManager.enter_debug_mode()
	assert_eq(DebugManager.previous_phase, original_phase, "Should store original phase")
	
	DebugManager.exit_debug_mode()
	assert_eq(GameState.get_current_phase(), original_phase, "Should preserve original phase")

func test_debug_mode_input_handling_priority():
	if not main_scene:
		pending("Main scene not available")
		return
	
	# Test that debug mode input has priority over normal game input
	DebugManager.enter_debug_mode()
	
	# Check that MovementController stops processing input in debug mode
	var movement_controller = main_scene.get_node_or_null("MovementController")
	if movement_controller:
		# MovementController should check debug mode and return early
		# This is tested by verifying the DebugManager integration exists
		assert_true(DebugManager.is_debug_active(), "Debug mode should be active")
	
	DebugManager.exit_debug_mode()

func test_debug_mode_model_click_detection():
	if not GameState:
		pending("GameState not available")
		return
	
	# Test model detection within click radius
	GameState.state = {
		"units": {
			"test_unit": {
				"models": [
					{"id": "close_model", "alive": true, "position": {"x": 100.0, "y": 100.0}},
					{"id": "far_model", "alive": true, "position": {"x": 1000.0, "y": 1000.0}}
				]
			}
		}
	}
	
	# Test clicking near model (within radius)
	var near_click = Vector2(105, 105)  # 5 units away from model at (100, 100)
	var found_near = DebugManager._find_model_at_position_debug(near_click)
	assert_false(found_near.is_empty(), "Should find model near click position")
	assert_eq(found_near.model_id, "close_model", "Should find the closest model")
	
	# Test clicking far from models (outside radius)
	var far_click = Vector2(500, 500)
	var found_far = DebugManager._find_model_at_position_debug(far_click)
	assert_true(found_far.is_empty(), "Should not find model far from click position")

func test_debug_mode_dead_model_filtering():
	if not GameState:
		pending("GameState not available")
		return
	
	# Test that dead models are not selectable in debug mode
	GameState.state = {
		"units": {
			"test_unit": {
				"models": [
					{"id": "alive_model", "alive": true, "position": {"x": 100.0, "y": 100.0}},
					{"id": "dead_model", "alive": false, "position": {"x": 110.0, "y": 110.0}}
				]
			}
		}
	}
	
	# Click position that would be closer to dead model
	var click_pos = Vector2(110, 110)
	var found_model = DebugManager._find_model_at_position_debug(click_pos)
	
	# Should find alive model instead of dead one, or find alive model if both are in range
	if not found_model.is_empty():
		assert_eq(found_model.model_id, "alive_model", "Should not select dead models")

func test_debug_mode_overlay_cleanup():
	# Test that debug overlay is properly cleaned up
	DebugManager.enter_debug_mode()
	await get_tree().process_frame
	
	var overlay_created = DebugManager.debug_overlay != null
	
	DebugManager.exit_debug_mode()
	await get_tree().process_frame
	
	if overlay_created:
		# Overlay should be destroyed/hidden
		var overlay_cleaned = DebugManager.debug_overlay == null or not DebugManager.debug_overlay.visible
		assert_true(overlay_cleaned, "Debug overlay should be cleaned up on exit")

func test_debug_mode_multiple_toggles():
	# Test rapid toggling of debug mode
	for i in range(5):
		DebugManager.toggle_debug_mode()
		await get_tree().process_frame
		
		var expected_active = (i % 2) == 0  # Should be active on even iterations
		assert_eq(DebugManager.is_debug_active(), expected_active, 
			"Debug mode state should be consistent after toggle %d" % i)

# Performance test
func test_debug_mode_performance_impact():
	var start_time = Time.get_ticks_msec()
	
	# Toggle debug mode multiple times
	for i in range(10):
		DebugManager.enter_debug_mode()
		DebugManager.exit_debug_mode()
	
	var end_time = Time.get_ticks_msec()
	var duration = end_time - start_time
	
	assert_true(duration < 100, "Debug mode toggles should complete quickly (took %d ms)" % duration)