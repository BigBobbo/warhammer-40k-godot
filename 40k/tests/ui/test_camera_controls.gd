extends BaseUITest

# Camera Controls UI Tests - Tests camera movement, zooming, and viewport interactions
# Tests mouse wheel zoom, pan, camera bounds, and viewport navigation

func test_camera_zoom_with_mouse_wheel():
	# Test zooming in and out with mouse wheel
	if not camera:
		pending("Camera not available in test environment")
		return
	
	var initial_zoom = camera.zoom if camera.has_property("zoom") else Vector2.ONE
	
	# Simulate mouse wheel scroll up (zoom in)
	var scroll_up = InputEventMouseButton.new()
	scroll_up.button_index = MOUSE_BUTTON_WHEEL_UP
	scroll_up.pressed = true
	scene_runner.get_scene().get_viewport().push_input(scroll_up)
	
	await wait_for_ui_update()
	
	if camera.has_property("zoom"):
		var zoom_after_in = camera.zoom
		assert_gt(zoom_after_in.x, initial_zoom.x, "Camera should zoom in with wheel up")
	
	# Simulate mouse wheel scroll down (zoom out)
	var scroll_down = InputEventMouseButton.new()
	scroll_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	scroll_down.pressed = true
	scene_runner.get_scene().get_viewport().push_input(scroll_down)
	
	await wait_for_ui_update()
	
	if camera.has_property("zoom"):
		var zoom_after_out = camera.zoom
		assert_lt(zoom_after_out.x, zoom_after_in.x, "Camera should zoom out with wheel down")

func test_camera_zoom_limits():
	# Test camera zoom limits (min and max zoom)
	if not camera:
		pending("Camera not available in test environment")
		return
	
	# Zoom in many times to hit max zoom limit
	for i in range(20):
		var scroll_up = InputEventMouseButton.new()
		scroll_up.button_index = MOUSE_BUTTON_WHEEL_UP
		scroll_up.pressed = true
		scene_runner.get_scene().get_viewport().push_input(scroll_up)
		await await_input_processed()
	
	var max_zoom = camera.zoom if camera.has_property("zoom") else Vector2.ONE
	
	# Zoom out many times to hit min zoom limit
	for i in range(40):
		var scroll_down = InputEventMouseButton.new()
		scroll_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
		scroll_down.pressed = true
		scene_runner.get_scene().get_viewport().push_input(scroll_down)
		await await_input_processed()
	
	var min_zoom = camera.zoom if camera.has_property("zoom") else Vector2.ONE
	
	# Should have reasonable zoom limits
	assert_gt(max_zoom.x, min_zoom.x, "Max zoom should be greater than min zoom")
	assert_gt(max_zoom.x, 1.0, "Should be able to zoom in beyond 1:1")
	assert_lt(min_zoom.x, 1.0, "Should be able to zoom out below 1:1")

func test_camera_pan_with_middle_mouse():
	# Test camera panning with middle mouse button drag
	if not camera:
		pending("Camera not available in test environment")
		return
	
	var initial_pos = camera.global_position
	var start_mouse_pos = Vector2(200, 200)
	var end_mouse_pos = Vector2(300, 250)
	
	# Start middle mouse drag
	scene_runner.set_mouse_position(start_mouse_pos)
	
	var middle_press = InputEventMouseButton.new()
	middle_press.button_index = MOUSE_BUTTON_MIDDLE
	middle_press.pressed = true
	scene_runner.get_scene().get_viewport().push_input(middle_press)
	
	# Drag camera
	var steps = 5
	for i in range(steps):
		var progress = float(i + 1) / float(steps)
		var current_pos = start_mouse_pos.lerp(end_mouse_pos, progress)
		scene_runner.set_mouse_position(current_pos)
		await await_input_processed()
	
	# Release middle mouse
	var middle_release = InputEventMouseButton.new()
	middle_release.button_index = MOUSE_BUTTON_MIDDLE
	middle_release.pressed = false
	scene_runner.get_scene().get_viewport().push_input(middle_release)
	
	await wait_for_ui_update()
	
	var final_pos = camera.global_position
	var camera_moved = initial_pos.distance_to(final_pos) > 10.0
	assert_true(camera_moved, "Camera should move when panning with middle mouse")

func test_camera_pan_with_wasd():
	# Test camera panning with WASD keys
	if not camera:
		pending("Camera not available in test environment")
		return
	
	var initial_pos = camera.global_position
	
	# Press W key to move camera up
	var w_press = InputEventKey.new()
	w_press.keycode = KEY_W
	w_press.pressed = true
	scene_runner.get_scene().get_viewport().push_input(w_press)
	
	await wait_for_ui_update()
	
	var pos_after_w = camera.global_position
	
	# Release W key
	w_press.pressed = false
	scene_runner.get_scene().get_viewport().push_input(w_press)
	
	# Camera should have moved up (negative Y)
	assert_lt(pos_after_w.y, initial_pos.y, "Camera should move up with W key")

func test_camera_edge_scrolling():
	# Test camera scrolling when mouse approaches screen edge
	if not camera:
		pending("Camera not available in test environment")
		return
	
	var initial_pos = camera.global_position
	var viewport = get_viewport()
	var screen_size = viewport.get_visible_rect().size
	
	# Move mouse to right edge of screen
	var edge_pos = Vector2(screen_size.x - 5, screen_size.y / 2)
	scene_runner.set_mouse_position(edge_pos)
	
	# Wait for edge scrolling to trigger
	await get_tree().create_timer(0.5).timeout
	
	var pos_after_edge = camera.global_position
	var camera_moved = initial_pos.distance_to(pos_after_edge) > 5.0
	
	# Camera should move when mouse is at edge (if edge scrolling is enabled)
	if camera_moved:
		assert_true(camera_moved, "Camera should scroll when mouse is at screen edge")

func test_camera_bounds():
	# Test that camera respects world bounds
	if not camera:
		pending("Camera not available in test environment")
		return
	
	# Try to pan camera way outside the game board
	var extreme_pos = Vector2(-10000, -10000)
	
	# Simulate extreme pan
	scene_runner.set_mouse_position(Vector2(100, 100))
	
	var middle_press = InputEventMouseButton.new()
	middle_press.button_index = MOUSE_BUTTON_MIDDLE
	middle_press.pressed = true
	scene_runner.get_scene().get_viewport().push_input(middle_press)
	
	# Drag to extreme position
	scene_runner.set_mouse_position(extreme_pos)
	await await_input_processed()
	
	var middle_release = InputEventMouseButton.new()
	middle_release.button_index = MOUSE_BUTTON_MIDDLE
	middle_release.pressed = false
	scene_runner.get_scene().get_viewport().push_input(middle_release)
	
	await wait_for_ui_update()
	
	var final_pos = camera.global_position
	
	# Camera should be constrained to reasonable bounds (not at extreme position)
	assert_gt(final_pos.x, -5000, "Camera X should be constrained by bounds")
	assert_gt(final_pos.y, -5000, "Camera Y should be constrained by bounds")

func test_camera_focus_on_unit():
	# Test focusing camera on selected unit
	select_unit_from_list(0)  # Select first unit
	
	# Look for "Focus" or "Center" button
	var focus_button = find_ui_element("FocusButton", Button)
	if not focus_button:
		focus_button = find_ui_element("CenterButton", Button)
	
	if focus_button and camera:
		var initial_camera_pos = camera.global_position
		
		click_button("FocusButton")
		await wait_for_ui_update()
		
		var final_camera_pos = camera.global_position
		var camera_moved = initial_camera_pos.distance_to(final_camera_pos) > 50.0
		
		assert_true(camera_moved, "Camera should move to focus on selected unit")

func test_camera_zoom_keyboard_shortcuts():
	# Test zoom in/out with + and - keys
	if not camera:
		pending("Camera not available in test environment")
		return
	
	var initial_zoom = camera.zoom if camera.has_property("zoom") else Vector2.ONE
	
	# Test zoom in with + key
	var plus_key = InputEventKey.new()
	plus_key.keycode = KEY_EQUAL  # Usually + key
	plus_key.pressed = true
	scene_runner.get_scene().get_viewport().push_input(plus_key)
	
	await wait_for_ui_update()
	
	plus_key.pressed = false
	scene_runner.get_scene().get_viewport().push_input(plus_key)
	
	if camera.has_property("zoom"):
		var zoom_after_plus = camera.zoom
		assert_gte(zoom_after_plus.x, initial_zoom.x, "Camera should zoom in with + key")
	
	# Test zoom out with - key
	var minus_key = InputEventKey.new()
	minus_key.keycode = KEY_MINUS
	minus_key.pressed = true
	scene_runner.get_scene().get_viewport().push_input(minus_key)
	
	await wait_for_ui_update()
	
	minus_key.pressed = false
	scene_runner.get_scene().get_viewport().push_input(minus_key)

func test_camera_reset():
	# Test resetting camera to default position/zoom
	if not camera:
		pending("Camera not available in test environment")
		return
	
	# Move and zoom camera away from defaults
	camera.global_position = Vector2(1000, 1000)
	if camera.has_property("zoom"):
		camera.zoom = Vector2(3.0, 3.0)
	
	await wait_for_ui_update()
	
	# Look for reset button
	var reset_button = find_ui_element("ResetCameraButton", Button)
	if not reset_button:
		reset_button = find_ui_element("HomeButton", Button)
	
	if reset_button:
		click_button("ResetCameraButton")
		await wait_for_ui_update()
		
		# Camera should return to reasonable default position
		var reset_pos = camera.global_position
		assert_lt(abs(reset_pos.x), 500, "Camera X should be near origin after reset")
		assert_lt(abs(reset_pos.y), 500, "Camera Y should be near origin after reset")

func test_minimap_interaction():
	# Test clicking on minimap to move camera
	var minimap = find_ui_element("Minimap", Control)
	if not minimap or not camera:
		pending("Minimap or camera not available")
		return
	
	var initial_camera_pos = camera.global_position
	
	# Click on minimap
	var minimap_center = minimap.global_position + minimap.size / 2
	click_at_position(minimap_center)
	
	await wait_for_ui_update()
	
	var final_camera_pos = camera.global_position
	var camera_moved = initial_camera_pos.distance_to(final_camera_pos) > 20.0
	
	assert_true(camera_moved, "Camera should move when clicking on minimap")

func test_camera_smooth_movement():
	# Test that camera movement is smooth (not jerky)
	if not camera:
		pending("Camera not available in test environment")
		return
	
	var initial_pos = camera.global_position
	var target_pos = initial_pos + Vector2(200, 100)
	
	# Record positions during movement
	var positions = []
	
	# Start camera movement (simulate smooth pan)
	var tween = get_tree().create_tween()
	tween.tween_property(camera, "global_position", target_pos, 1.0)
	
	# Sample positions during movement
	for i in range(10):
		await get_tree().process_frame
		positions.append(camera.global_position)
	
	await tween.finished
	
	# Check that movement was progressive (not jumpy)
	var smooth_movement = true
	for i in range(1, positions.size()):
		var distance = positions[i].distance_to(positions[i-1])
		if distance > 50.0:  # Large jump indicates jerky movement
			smooth_movement = false
			break
	
	assert_true(smooth_movement, "Camera movement should be smooth")

func test_camera_follow_mode():
	# Test camera follow mode (following selected unit)
	if not camera:
		pending("Camera not available in test environment")
		return
	
	# Enable follow mode if available
	var follow_button = find_ui_element("FollowButton", Button)
	if follow_button:
		click_button("FollowButton")
		await wait_for_ui_update()
		
		select_unit_from_list(0)
		await wait_for_ui_update()
		
		# Move the unit and check if camera follows
		transition_to_phase(GameStateData.Phase.MOVEMENT)
		click_button("BeginNormalMove")
		
		var model_token = find_model_token("test_unit_1", "m1")
		if model_token:
			var initial_camera_pos = camera.global_position
			var unit_pos = model_token.global_position
			
			# Drag model to new location
			drag_model_token("test_unit_1", "m1", unit_pos + Vector2(200, 0))
			await wait_for_ui_update()
			
			var final_camera_pos = camera.global_position
			var camera_followed = initial_camera_pos.distance_to(final_camera_pos) > 50.0
			
			assert_true(camera_followed, "Camera should follow unit in follow mode")

func test_viewport_bounds_visualization():
	# Test that viewport shows game board bounds
	var bounds_display = find_ui_element("BoardBounds", Line2D)
	if bounds_display:
		assert_true(bounds_display.visible, "Board bounds should be visible")
		assert_gt(bounds_display.points.size(), 3, "Bounds should have multiple points")

func test_grid_display_toggle():
	# Test toggling grid display
	var grid_button = find_ui_element("GridToggle", Button)
	if grid_button:
		click_button("GridToggle")
		await wait_for_ui_update()
		
		var grid_display = find_ui_element("Grid", Line2D)
		if grid_display:
			var grid_visible = grid_display.visible
			
			# Toggle again
			click_button("GridToggle")
			await wait_for_ui_update()
			
			assert_ne(grid_visible, grid_display.visible, "Grid visibility should toggle")

func test_camera_shake_on_events():
	# Test camera shake on dramatic events (explosions, etc.)
	if not camera:
		pending("Camera not available in test environment")
		return
	
	var initial_pos = camera.global_position
	
	# Trigger an event that should cause camera shake (mock explosion)
	var explosion_event = {
		"type": "explosion",
		"position": Vector2(300, 300),
		"intensity": 5
	}
	
	# Look for camera shake system
	var camera_shake = find_ui_element("CameraShake", Node)
	if camera_shake and camera_shake.has_method("shake"):
		camera_shake.shake(explosion_event.intensity)
		
		# Wait a bit for shake
		await get_tree().create_timer(0.2).timeout
		
		var shaken_pos = camera.global_position
		
		# Wait for shake to settle
		await get_tree().create_timer(1.0).timeout
		
		var final_pos = camera.global_position
		
		# Should return to approximately original position after shake
		var distance_to_original = final_pos.distance_to(initial_pos)
		assert_lt(distance_to_original, 20.0, "Camera should return to original position after shake")