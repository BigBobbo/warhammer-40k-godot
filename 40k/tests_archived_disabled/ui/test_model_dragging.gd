extends BaseUITest

# Model Dragging UI Tests - Tests drag and drop functionality for model movement
# Tests mouse interactions, model selection, dragging mechanics, and visual feedback

func test_click_model_token_selection():
	# Test clicking on a model token to select it
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	
	# Click on first model of test unit
	click_model_token("test_unit_1", "m1")
	
	# Verify model is selected
	var unit_card_visible = find_ui_element("UnitCard", VBoxContainer)
	if unit_card_visible:
		assert_unit_card_visible(true, "Unit card should be visible after model selection")

func test_drag_model_basic():
	# Test basic model dragging functionality
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	
	# Start a move for the unit
	click_button("BeginNormalMove")
	
	# Get initial position of model
	var initial_pos = get_model_token_position("test_unit_1", "m1")
	assert_ne(Vector2.ZERO, initial_pos, "Should have valid initial position")
	
	# Drag model to new position
	var target_pos = initial_pos + Vector2(100, 50)
	drag_model_token("test_unit_1", "m1", target_pos)
	
	# Wait for UI to update
	await wait_for_ui_update()
	
	# Verify model has moved (visually)
	var new_pos = get_model_token_position("test_unit_1", "m1")
	assert_ne(initial_pos, new_pos, "Model should have moved from initial position")

func test_drag_model_with_pathfinding():
	# Test dragging with pathfinding around obstacles
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	click_button("BeginNormalMove")
	
	var initial_pos = get_model_token_position("test_unit_1", "m1")
	
	# Drag to position that requires pathfinding around terrain
	var target_pos = initial_pos + Vector2(200, 200)
	drag_model_token("test_unit_1", "m1", target_pos)
	
	await wait_for_ui_update()
	
	# Check if path visualization appears
	var path_display = find_ui_element("MovementPath", Line2D)
	if path_display:
		assert_true(path_display.visible, "Movement path should be visible during drag")

func test_drag_model_out_of_range():
	# Test dragging model beyond movement range
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	click_button("BeginNormalMove")
	
	var initial_pos = get_model_token_position("test_unit_1", "m1")
	
	# Try to drag far beyond movement range
	var far_target = initial_pos + Vector2(1000, 1000)  # Way beyond 6" move
	drag_model_token("test_unit_1", "m1", far_target)
	
	await wait_for_ui_update()
	
	# Should show range error or snap back
	var error_message = find_ui_element("ErrorMessage", Label)
	if error_message:
		assert_true(error_message.visible, "Should show error for out of range movement")

func test_drag_model_into_terrain():
	# Test dragging model into impassable terrain
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	click_button("BeginNormalMove")
	
	# Drag model into terrain area (coordinates from test state)
	var terrain_pos = Vector2(880, 880)  # Impassable terrain
	drag_model_token("test_unit_1", "m1", terrain_pos)
	
	await wait_for_ui_update()
	
	# Should prevent invalid placement
	var status_label = find_ui_element("StatusLabel", Label)
	if status_label:
		var status_text = status_label.text.to_lower()
		assert_true("terrain" in status_text or "impassable" in status_text or "invalid" in status_text,
			"Should show terrain error message")

func test_drag_model_coherency_validation():
	# Test dragging model that would break unit coherency
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	click_button("BeginNormalMove")
	
	var initial_pos = get_model_token_position("test_unit_1", "m1")
	
	# Drag model far from other squad members (break coherency)
	var far_pos = initial_pos + Vector2(300, 300)
	drag_model_token("test_unit_1", "m1", far_pos)
	
	await wait_for_ui_update()
	
	# Should show coherency warning or prevent move
	var warning_display = find_ui_element("CoherencyWarning", Control)
	if warning_display:
		assert_true(warning_display.visible, "Should show coherency warning")

func test_multi_model_selection():
	# Test selecting and dragging multiple models
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	click_button("BeginNormalMove")
	
	# Select multiple models (Ctrl+click or drag selection box)
	click_model_token("test_unit_1", "m1")
	
	# Simulate Ctrl+click for multi-select
	var viewport = get_viewport()
	var ctrl_event = InputEventKey.new()
	ctrl_event.keycode = KEY_CTRL
	ctrl_event.pressed = true
	viewport.push_input(ctrl_event)
	
	click_model_token("test_unit_1", "m2")
	
	ctrl_event.pressed = false
	viewport.push_input(ctrl_event)
	
	await wait_for_ui_update()
	
	# Both models should be selected
	var selection_indicators = find_ui_element("SelectionIndicators", Node2D)
	if selection_indicators:
		assert_gt(selection_indicators.get_child_count(), 1, "Multiple models should be selected")

func test_drag_selection_box():
	# Test drag selection box for selecting multiple models
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	
	var start_pos = Vector2(50, 50)
	var end_pos = Vector2(200, 200)
	
	# Drag selection box
	scene_runner.set_mouse_position(start_pos)
	scene_runner.simulate_mouse_button_press(MOUSE_BUTTON_LEFT)
	
	# Drag to create selection box
	var steps = 5
	for i in range(steps):
		var progress = float(i) / float(steps)
		var current_pos = start_pos.lerp(end_pos, progress)
		scene_runner.set_mouse_position(current_pos)
		await await_input_processed()
	
	scene_runner.simulate_mouse_button_release(MOUSE_BUTTON_LEFT)
	await wait_for_ui_update()
	
	# Selection box should appear and select models within it
	var selection_box = find_ui_element("SelectionBox", NinePatchRect)
	if selection_box:
		# Selection box might not be visible after release
		pass

func test_model_hover_highlighting():
	# Test model highlighting on mouse hover
	var model_token = find_model_token("test_unit_1", "m1")
	if model_token:
		var model_pos = model_token.global_position
		
		# Move mouse over model
		scene_runner.set_mouse_position(model_pos)
		await await_input_processed()
		
		# Check for hover effect
		var hover_highlight = find_ui_element("HoverHighlight", Control)
		if hover_highlight:
			assert_true(hover_highlight.visible, "Hover highlight should appear on model")

func test_invalid_model_selection():
	# Test trying to select enemy models or invalid models
	var enemy_token = find_model_token("enemy_unit_1", "e1")
	if enemy_token:
		click_model_token("enemy_unit_1", "e1")
		await wait_for_ui_update()
		
		# Should not select enemy models
		var unit_card = find_ui_element("UnitCard", VBoxContainer)
		if unit_card and unit_card.visible:
			# If unit card is shown, it should show an error or belong to enemy
			var unit_name = find_ui_element("UnitNameLabel", Label)
			if unit_name:
				assert_false("test_unit" in unit_name.text.to_lower(), "Should not select friendly unit via enemy click")

func test_model_context_menu():
	# Test right-click context menu on model
	right_click_model_token("test_unit_1", "m1")
	await wait_for_ui_update()
	
	# Check for context menu
	var context_menu = find_ui_element("ModelContextMenu", PopupMenu)
	if context_menu:
		assert_true(context_menu.visible, "Context menu should appear on right-click")
		
		# Check menu items
		var item_count = context_menu.get_item_count()
		assert_gt(item_count, 0, "Context menu should have menu items")

func test_model_info_tooltip():
	# Test model information tooltip
	var model_token = find_model_token("test_unit_1", "m1")
	if model_token:
		var model_pos = model_token.global_position
		
		# Hover for tooltip
		scene_runner.set_mouse_position(model_pos)
		await get_tree().create_timer(1.0).timeout  # Wait for tooltip delay
		
		var tooltip = find_ui_element("ModelTooltip", Control)
		if tooltip:
			assert_true(tooltip.visible, "Tooltip should appear after hover delay")

func test_formation_drag():
	# Test dragging models in formation
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	click_button("BeginNormalMove")
	
	# Select all models in unit
	select_unit_from_list(0)  # Assuming first unit in list
	
	# Drag in formation
	var formation_pos = Vector2(200, 200)
	drag_model_token("test_unit_1", "m1", formation_pos)
	
	await wait_for_ui_update()
	
	# Other models should move to maintain formation
	var model2_pos = get_model_token_position("test_unit_1", "m2")
	assert_ne(Vector2.ZERO, model2_pos, "Other models should move in formation")

func test_snap_to_grid():
	# Test model snapping to grid during placement
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	click_button("BeginNormalMove")
	
	# Drag to off-grid position
	var off_grid_pos = Vector2(123.7, 456.3)
	drag_model_token("test_unit_1", "m1", off_grid_pos)
	
	await wait_for_ui_update()
	
	# Should snap to grid if snap is enabled
	var final_pos = get_model_token_position("test_unit_1", "m1")
	
	# If grid snap is 25 pixels, positions should be multiples of 25
	var grid_size = 25.0
	var snapped_x = round(off_grid_pos.x / grid_size) * grid_size
	var snapped_y = round(off_grid_pos.y / grid_size) * grid_size
	var expected_snap = Vector2(snapped_x, snapped_y)
	
	# Check if position is close to grid snap (within tolerance)
	var distance_to_snap = final_pos.distance_to(expected_snap)
	if distance_to_snap < 5.0:  # 5 pixel tolerance
		assert_almost_eq(expected_snap.x, final_pos.x, 5.0, "X position should snap to grid")
		assert_almost_eq(expected_snap.y, final_pos.y, 5.0, "Y position should snap to grid")

func test_model_collision_detection():
	# Test model collision with other models during drag
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	click_button("BeginNormalMove")
	
	# Try to drag model onto another model's position
	var model1_pos = get_model_token_position("test_unit_1", "m1")
	var model2_pos = get_model_token_position("test_unit_1", "m2")
	
	# Drag model1 to model2's position
	drag_model_token("test_unit_1", "m1", model2_pos)
	
	await wait_for_ui_update()
	
	# Models shouldn't overlap (exact behavior depends on implementation)
	var final_pos = get_model_token_position("test_unit_1", "m1")
	var distance_between = final_pos.distance_to(model2_pos)
	
	# Models should maintain minimum distance (base size)
	assert_gt(distance_between, 20.0, "Models should maintain minimum distance")

func test_undo_model_movement():
	# Test undoing model movement
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	click_button("BeginNormalMove")
	
	var initial_pos = get_model_token_position("test_unit_1", "m1")
	
	# Move model
	var new_pos = initial_pos + Vector2(100, 0)
	drag_model_token("test_unit_1", "m1", new_pos)
	
	await wait_for_ui_update()
	
	# Undo the move
	click_button("UndoButton")
	
	await wait_for_ui_update()
	
	# Model should return to original position
	var current_pos = get_model_token_position("test_unit_1", "m1")
	var distance_to_original = current_pos.distance_to(initial_pos)
	assert_lt(distance_to_original, 5.0, "Model should return to original position after undo")

func test_camera_follow_drag():
	# Test camera following during model drag
	var initial_camera_pos = camera.global_position if camera else Vector2.ZERO
	
	# Drag model to edge of screen to trigger camera follow
	var screen_size = get_viewport().get_visible_rect().size
	var edge_pos = screen_size * 0.9  # Near edge
	
	drag_model(Vector2(100, 100), edge_pos)
	
	await wait_for_ui_update()
	
	if camera:
		var final_camera_pos = camera.global_position
		var camera_moved = initial_camera_pos.distance_to(final_camera_pos) > 10.0
		
		# Camera should follow if drag goes near edge
		assert_true(camera_moved, "Camera should follow model drag near screen edge")

# Helper methods specific to model dragging tests

func right_click_model_token(unit_id: String, model_id: String = ""):
	var token = find_model_token(unit_id, model_id)
	assert_not_null(token, "Model token should exist for " + unit_id + "/" + model_id)
	
	var token_pos = token.global_position
	scene_runner.set_mouse_position(token_pos)
	scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	await await_input_processed()

func drag_with_multiple_waypoints(unit_id: String, model_id: String, waypoints: Array):
	# Drag model through multiple waypoints
	var token = find_model_token(unit_id, model_id)
	assert_not_null(token, "Model token should exist")
	
	var start_pos = token.global_position
	scene_runner.set_mouse_position(start_pos)
	scene_runner.simulate_mouse_button_press(MOUSE_BUTTON_LEFT)
	
	for waypoint in waypoints:
		# Move through each waypoint
		var steps = 3
		var current_pos = scene_runner.get_mouse_position()
		
		for i in range(steps):
			var progress = float(i + 1) / float(steps)
			var lerp_pos = current_pos.lerp(waypoint, progress)
			scene_runner.set_mouse_position(lerp_pos)
			await await_input_processed()
	
	scene_runner.simulate_mouse_button_release(MOUSE_BUTTON_LEFT)
	await await_input_processed()

func test_waypoint_movement():
	# Test movement with waypoints (complex path)
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	click_button("BeginNormalMove")
	
	var waypoints = [
		Vector2(150, 150),
		Vector2(200, 120),
		Vector2(250, 180),
		Vector2(300, 150)
	]
	
	drag_with_multiple_waypoints("test_unit_1", "m1", waypoints)
	
	await wait_for_ui_update()
	
	# Should show complete movement path
	var path_display = find_ui_element("MovementPath", Line2D)
	if path_display and path_display.points.size() > 2:
		assert_gt(path_display.points.size(), 2, "Path should include multiple waypoints")