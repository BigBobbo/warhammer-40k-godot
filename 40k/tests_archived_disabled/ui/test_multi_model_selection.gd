extends BaseUITest

# Multi-Model Selection Tests - Test comprehensive multi-selection functionality
# Tests Ctrl+click, drag-box selection, group movement, and validation

func test_ctrl_click_multi_selection():
	"""Test Ctrl+click for selecting multiple models"""
	transition_to_phase(GameStateData.Phase.MOVEMENT)

	# Start movement for a unit
	click_button("BeginNormalMove")

	# Simulate Ctrl+click on first model
	var ctrl_key_event = InputEventKey.new()
	ctrl_key_event.keycode = KEY_CTRL
	ctrl_key_event.pressed = true
	get_viewport().push_input(ctrl_key_event)

	click_model_token("test_unit_1", "m1")

	# Verify first model is selected
	var movement_controller = get_movement_controller()
	assert_eq(movement_controller.selected_models.size(), 1, "First model should be selected")
	assert_eq(movement_controller.selection_mode, "SINGLE", "Selection mode should be SINGLE for one model")

	# Add second model to selection
	click_model_token("test_unit_1", "m2")

	assert_eq(movement_controller.selected_models.size(), 2, "Two models should be selected")
	assert_eq(movement_controller.selection_mode, "MULTI", "Selection mode should be MULTI for multiple models")

	# Release Ctrl key
	ctrl_key_event.pressed = false
	get_viewport().push_input(ctrl_key_event)

func test_ctrl_click_deselection():
	"""Test Ctrl+click for deselecting models"""
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	click_button("BeginNormalMove")

	var movement_controller = get_movement_controller()

	# Select two models first
	var ctrl_key_event = InputEventKey.new()
	ctrl_key_event.keycode = KEY_CTRL
	ctrl_key_event.pressed = true
	get_viewport().push_input(ctrl_key_event)

	click_model_token("test_unit_1", "m1")
	click_model_token("test_unit_1", "m2")

	assert_eq(movement_controller.selected_models.size(), 2, "Two models should be selected")

	# Ctrl+click on first model again to deselect it
	click_model_token("test_unit_1", "m1")

	assert_eq(movement_controller.selected_models.size(), 1, "One model should remain selected")
	assert_eq(movement_controller.selection_mode, "SINGLE", "Selection mode should return to SINGLE")

	ctrl_key_event.pressed = false
	get_viewport().push_input(ctrl_key_event)

func test_drag_box_selection():
	"""Test drag-box selection for multiple models"""
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	click_button("BeginNormalMove")

	var movement_controller = get_movement_controller()

	# Ensure no models are initially selected
	assert_eq(movement_controller.selected_models.size(), 0, "No models should be initially selected")

	# Perform drag-box selection
	var start_pos = Vector2(50, 50)
	var end_pos = Vector2(300, 300)

	# Start drag
	scene_runner.set_mouse_position(start_pos)
	scene_runner.simulate_mouse_button_press(MOUSE_BUTTON_LEFT)

	# Verify drag box is active
	assert_true(movement_controller.drag_box_active, "Drag box should be active")
	assert_eq(movement_controller.selection_mode, "DRAG_BOX", "Selection mode should be DRAG_BOX")

	# Drag to create selection box
	var steps = 5
	for i in range(steps):
		var progress = float(i + 1) / float(steps)
		var current_pos = start_pos.lerp(end_pos, progress)
		scene_runner.set_mouse_position(current_pos)
		await await_input_processed()

	# End drag
	scene_runner.simulate_mouse_button_release(MOUSE_BUTTON_LEFT)
	await wait_for_ui_update()

	# Verify models were selected
	assert_false(movement_controller.drag_box_active, "Drag box should no longer be active")
	assert_gt(movement_controller.selected_models.size(), 0, "Models should be selected within the box")

func test_ctrl_a_select_all():
	"""Test Ctrl+A for selecting all models in unit"""
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	click_button("BeginNormalMove")

	var movement_controller = get_movement_controller()

	# Press Ctrl+A
	var ctrl_key_event = InputEventKey.new()
	ctrl_key_event.keycode = KEY_CTRL
	ctrl_key_event.pressed = true
	get_viewport().push_input(ctrl_key_event)

	var a_key_event = InputEventKey.new()
	a_key_event.keycode = KEY_A
	a_key_event.pressed = true
	get_viewport().push_input(a_key_event)

	await wait_for_ui_update()

	# Verify all models in unit are selected
	assert_gt(movement_controller.selected_models.size(), 1, "Multiple models should be selected")
	assert_eq(movement_controller.selection_mode, "MULTI", "Selection mode should be MULTI")

	# Release keys
	ctrl_key_event.pressed = false
	a_key_event.pressed = false
	get_viewport().push_input(ctrl_key_event)
	get_viewport().push_input(a_key_event)

func test_escape_clear_selection():
	"""Test Escape key for clearing selection"""
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	click_button("BeginNormalMove")

	var movement_controller = get_movement_controller()

	# Select multiple models first
	var ctrl_key_event = InputEventKey.new()
	ctrl_key_event.keycode = KEY_CTRL
	ctrl_key_event.pressed = true
	get_viewport().push_input(ctrl_key_event)

	click_model_token("test_unit_1", "m1")
	click_model_token("test_unit_1", "m2")

	assert_gt(movement_controller.selected_models.size(), 0, "Models should be selected")

	# Press Escape
	var escape_event = InputEventKey.new()
	escape_event.keycode = KEY_ESCAPE
	escape_event.pressed = true
	get_viewport().push_input(escape_event)

	await wait_for_ui_update()

	# Verify selection is cleared
	assert_eq(movement_controller.selected_models.size(), 0, "Selection should be cleared")
	assert_eq(movement_controller.selection_mode, "SINGLE", "Selection mode should return to SINGLE")

	ctrl_key_event.pressed = false
	escape_event.pressed = false
	get_viewport().push_input(ctrl_key_event)
	get_viewport().push_input(escape_event)

func test_group_movement_distance_tracking():
	"""Test that group movement correctly tracks individual model distances"""
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	click_button("BeginNormalMove")

	var movement_controller = get_movement_controller()

	# Select multiple models
	var ctrl_key_event = InputEventKey.new()
	ctrl_key_event.keycode = KEY_CTRL
	ctrl_key_event.pressed = true
	get_viewport().push_input(ctrl_key_event)

	click_model_token("test_unit_1", "m1")
	click_model_token("test_unit_1", "m2")

	# Get initial positions
	var initial_distances = {}
	for model_data in movement_controller.selected_models:
		var model_id = model_data.model_id
		initial_distances[model_id] = movement_controller._get_model_accumulated_distance(model_id)

	# Perform group movement
	var start_pos = get_model_token_position("test_unit_1", "m1")
	var target_pos = start_pos + Vector2(100, 0)  # Move 100 pixels right

	# Start group movement
	movement_controller._start_group_movement(start_pos)

	# Simulate dragging to new position
	movement_controller._update_group_drag(target_pos)
	movement_controller._end_group_drag(target_pos)

	await wait_for_ui_update()

	# Verify distances have increased for all selected models
	for model_data in movement_controller.selected_models:
		var model_id = model_data.model_id
		var final_distance = movement_controller._get_model_accumulated_distance(model_id)
		var initial_distance = initial_distances.get(model_id, 0.0)

		assert_gt(final_distance, initial_distance, "Model %s distance should have increased" % model_id)

	ctrl_key_event.pressed = false
	get_viewport().push_input(ctrl_key_event)

func test_group_formation_preservation():
	"""Test that group movement preserves relative formation"""
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	click_button("BeginNormalMove")

	var movement_controller = get_movement_controller()

	# Select multiple models
	var ctrl_key_event = InputEventKey.new()
	ctrl_key_event.keycode = KEY_CTRL
	ctrl_key_event.pressed = true
	get_viewport().push_input(ctrl_key_event)

	click_model_token("test_unit_1", "m1")
	click_model_token("test_unit_1", "m2")

	# Get initial relative positions
	var initial_positions = {}
	for model_data in movement_controller.selected_models:
		initial_positions[model_data.model_id] = model_data.position

	var initial_center = movement_controller._calculate_group_center(movement_controller.selected_models)
	var initial_offsets = {}
	for model_data in movement_controller.selected_models:
		initial_offsets[model_data.model_id] = model_data.position - initial_center

	# Start group movement and calculate formation offsets
	movement_controller._start_group_movement(initial_center)

	# Verify formation offsets are calculated correctly
	for model_id in initial_offsets:
		var calculated_offset = movement_controller.group_formation_offsets.get(model_id, Vector2.ZERO)
		var expected_offset = initial_offsets[model_id]

		assert_almost_eq(calculated_offset.x, expected_offset.x, 1.0,
			"Model %s X offset should be preserved" % model_id)
		assert_almost_eq(calculated_offset.y, expected_offset.y, 1.0,
			"Model %s Y offset should be preserved" % model_id)

	ctrl_key_event.pressed = false
	get_viewport().push_input(ctrl_key_event)

func test_visual_selection_indicators():
	"""Test that visual selection indicators appear for selected models"""
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	click_button("BeginNormalMove")

	var movement_controller = get_movement_controller()

	# Initially no indicators
	assert_eq(movement_controller.selection_indicators.size(), 0, "No indicators should exist initially")

	# Select a model
	var ctrl_key_event = InputEventKey.new()
	ctrl_key_event.keycode = KEY_CTRL
	ctrl_key_event.pressed = true
	get_viewport().push_input(ctrl_key_event)

	click_model_token("test_unit_1", "m1")

	await wait_for_ui_update()

	# Verify indicator appears
	assert_eq(movement_controller.selection_indicators.size(), 1, "One indicator should exist")

	# Select second model
	click_model_token("test_unit_1", "m2")

	await wait_for_ui_update()

	# Verify two indicators
	assert_eq(movement_controller.selection_indicators.size(), 2, "Two indicators should exist")

	# Clear selection
	var escape_event = InputEventKey.new()
	escape_event.keycode = KEY_ESCAPE
	escape_event.pressed = true
	get_viewport().push_input(escape_event)

	await wait_for_ui_update()

	# Verify indicators are cleared
	assert_eq(movement_controller.selection_indicators.size(), 0, "Indicators should be cleared")

	ctrl_key_event.pressed = false
	escape_event.pressed = false
	get_viewport().push_input(ctrl_key_event)
	get_viewport().push_input(escape_event)

func test_group_movement_validation():
	"""Test that group movement validation works correctly"""
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	click_button("BeginNormalMove")

	var movement_phase = get_movement_phase()

	# Create mock group moves that exceed movement limit
	var group_moves = [
		{
			"model_id": "m1",
			"dest": [1000.0, 1000.0]  # Very far position
		},
		{
			"model_id": "m2",
			"dest": [1100.0, 1100.0]  # Very far position
		}
	]

	var validation_result = movement_phase._validate_group_movement(group_moves, "test_unit_1")

	# Validation should fail due to distance limits
	assert_false(validation_result.valid, "Group movement should be invalid due to distance limits")
	assert_gt(validation_result.errors.size(), 0, "Should have validation errors")

func test_group_ui_display_updates():
	"""Test that UI displays update correctly for group movement"""
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	click_button("BeginNormalMove")

	var movement_controller = get_movement_controller()

	# Select multiple models
	var ctrl_key_event = InputEventKey.new()
	ctrl_key_event.keycode = KEY_CTRL
	ctrl_key_event.pressed = true
	get_viewport().push_input(ctrl_key_event)

	click_model_token("test_unit_1", "m1")
	click_model_token("test_unit_1", "m2")

	await wait_for_ui_update()

	# Check that UI labels show group information
	var inches_used_label = movement_controller.inches_used_label
	var inches_left_label = movement_controller.inches_left_label

	if inches_used_label:
		assert_true(inches_used_label.text.contains("Group"), "Used label should show group information")

	if inches_left_label:
		assert_true(inches_left_label.text.contains("Group"), "Left label should show group information")

	ctrl_key_event.pressed = false
	get_viewport().push_input(ctrl_key_event)

func test_mixed_single_and_multi_selection():
	"""Test switching between single and multi-selection modes"""
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	click_button("BeginNormalMove")

	var movement_controller = get_movement_controller()

	# Start with single selection
	click_model_token("test_unit_1", "m1")
	assert_eq(movement_controller.selection_mode, "SINGLE", "Should start in SINGLE mode")

	# Switch to multi-selection
	var ctrl_key_event = InputEventKey.new()
	ctrl_key_event.keycode = KEY_CTRL
	ctrl_key_event.pressed = true
	get_viewport().push_input(ctrl_key_event)

	click_model_token("test_unit_1", "m2")
	assert_eq(movement_controller.selection_mode, "MULTI", "Should switch to MULTI mode")

	# Click without Ctrl should clear multi-selection and start single selection
	ctrl_key_event.pressed = false
	get_viewport().push_input(ctrl_key_event)

	click_model_token("test_unit_1", "m3")

	await wait_for_ui_update()

	# Should clear multi-selection and select single model
	assert_eq(movement_controller.selected_models.size(), 0, "Multi-selection should be cleared")
	assert_false(movement_controller.selected_model.is_empty(), "Single model should be selected")

# Helper function to get MovementController instance
func get_movement_controller():
	var main = get_node_or_null("/root/Main")
	if main and main.has_method("get_current_phase_controller"):
		return main.get_current_phase_controller()
	return null

# Helper function to get MovementPhase instance
func get_movement_phase():
	return PhaseManager.get_current_phase()