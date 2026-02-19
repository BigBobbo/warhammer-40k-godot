extends RefCounted
class_name InputSimulator

# Advanced input simulation utilities for complex user interactions
# Provides utilities for simulating realistic player mouse actions, keyboard shortcuts, and complex input sequences

static func simulate_mouse_click_sequence(scene_runner, positions: Array[Vector2], delay_ms: float = 100.0):
	"""Simulate clicking a sequence of positions with delays"""
	for pos in positions:
		scene_runner.set_mouse_position(pos)
		scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		await scene_runner.get_scene().get_tree().create_timer(delay_ms / 1000.0).timeout

static func simulate_double_click(scene_runner, position: Vector2):
	"""Simulate a double-click at a position"""
	scene_runner.set_mouse_position(position)

	# First click
	scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	await scene_runner.get_scene().get_tree().process_frame
	scene_runner.simulate_mouse_button_released(MOUSE_BUTTON_LEFT)

	# Short delay
	await scene_runner.get_scene().get_tree().create_timer(0.1).timeout

	# Second click
	scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	await scene_runner.get_scene().get_tree().process_frame
	scene_runner.simulate_mouse_button_released(MOUSE_BUTTON_LEFT)

static func simulate_drag_with_modifier(scene_runner, start_pos: Vector2, end_pos: Vector2, modifier_key: Key):
	"""Simulate dragging with a modifier key held (e.g., SHIFT, CTRL)"""
	var viewport = scene_runner.get_scene().get_viewport()

	# Press modifier key
	var key_event = InputEventKey.new()
	key_event.keycode = modifier_key
	key_event.pressed = true
	viewport.push_input(key_event)

	await scene_runner.get_scene().get_tree().process_frame

	# Perform drag
	scene_runner.set_mouse_position(start_pos)
	scene_runner.simulate_mouse_button_press(MOUSE_BUTTON_LEFT)

	var steps = 10
	for i in range(steps + 1):
		var progress = float(i) / float(steps)
		var current_pos = start_pos.lerp(end_pos, progress)
		scene_runner.set_mouse_position(current_pos)
		await scene_runner.get_scene().get_tree().process_frame

	scene_runner.simulate_mouse_button_release(MOUSE_BUTTON_LEFT)

	# Release modifier key
	key_event.pressed = false
	viewport.push_input(key_event)

static func simulate_mouse_wheel(scene_runner, position: Vector2, delta: float):
	"""Simulate mouse wheel scroll at a position"""
	scene_runner.set_mouse_position(position)

	var wheel_event = InputEventMouseButton.new()
	wheel_event.position = position
	wheel_event.button_index = MOUSE_BUTTON_WHEEL_UP if delta > 0 else MOUSE_BUTTON_WHEEL_DOWN
	wheel_event.pressed = true

	scene_runner.get_scene().get_viewport().push_input(wheel_event)
	await scene_runner.get_scene().get_tree().process_frame

	wheel_event.pressed = false
	scene_runner.get_scene().get_viewport().push_input(wheel_event)

static func simulate_box_selection(scene_runner, top_left: Vector2, bottom_right: Vector2):
	"""Simulate drag-to-select box selection"""
	scene_runner.set_mouse_position(top_left)
	scene_runner.simulate_mouse_button_press(MOUSE_BUTTON_LEFT)

	# Drag to create selection box
	var steps = 5
	for i in range(steps + 1):
		var progress = float(i) / float(steps)
		var current_pos = top_left.lerp(bottom_right, progress)
		scene_runner.set_mouse_position(current_pos)
		await scene_runner.get_scene().get_tree().process_frame

	scene_runner.simulate_mouse_button_release(MOUSE_BUTTON_LEFT)
	await scene_runner.get_scene().get_tree().process_frame

static func simulate_right_click_menu_selection(scene_runner, click_pos: Vector2, menu_item_index: int):
	"""Simulate right-clicking and selecting a menu item"""
	# Right click to open menu
	scene_runner.set_mouse_position(click_pos)
	scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	await scene_runner.get_scene().get_tree().create_timer(0.2).timeout

	# TODO: Find menu and click on item at index
	# This would need to find the popup menu and calculate item position
	# For now, just open the menu

static func simulate_keyboard_shortcut(scene_runner, keys: Array):
	"""Simulate pressing a keyboard shortcut (e.g., [KEY_CTRL, KEY_S])"""
	var viewport = scene_runner.get_scene().get_viewport()
	var key_events = []

	# Press all keys in sequence
	for key in keys:
		var key_event = InputEventKey.new()
		key_event.keycode = key
		key_event.pressed = true
		key_events.append(key_event)
		viewport.push_input(key_event)
		await scene_runner.get_scene().get_tree().process_frame

	# Release all keys in reverse
	key_events.reverse()
	for key_event in key_events:
		key_event.pressed = false
		viewport.push_input(key_event)
		await scene_runner.get_scene().get_tree().process_frame

static func simulate_hover_delay(scene_runner, position: Vector2, duration_seconds: float):
	"""Simulate hovering mouse at position for a duration (for tooltips, etc.)"""
	scene_runner.set_mouse_position(position)
	await scene_runner.get_scene().get_tree().create_timer(duration_seconds).timeout

static func simulate_rapid_clicks(scene_runner, position: Vector2, count: int, delay_ms: float = 50.0):
	"""Simulate rapid clicking at a position"""
	scene_runner.set_mouse_position(position)

	for i in range(count):
		scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		await scene_runner.get_scene().get_tree().process_frame
		scene_runner.simulate_mouse_button_released(MOUSE_BUTTON_LEFT)
		await scene_runner.get_scene().get_tree().create_timer(delay_ms / 1000.0).timeout

static func simulate_mouse_gesture(scene_runner, waypoints: Array[Vector2], duration_seconds: float = 1.0):
	"""Simulate a complex mouse gesture through multiple waypoints"""
	if waypoints.size() < 2:
		return

	var time_per_segment = duration_seconds / float(waypoints.size() - 1)
	var steps_per_segment = 10

	for i in range(waypoints.size() - 1):
		var start_pos = waypoints[i]
		var end_pos = waypoints[i + 1]

		for step in range(steps_per_segment):
			var progress = float(step) / float(steps_per_segment)
			var current_pos = start_pos.lerp(end_pos, progress)
			scene_runner.set_mouse_position(current_pos)
			await scene_runner.get_scene().get_tree().create_timer(time_per_segment / steps_per_segment).timeout

static func simulate_camera_pan_with_mouse(scene_runner, start_pos: Vector2, end_pos: Vector2):
	"""Simulate panning camera by middle mouse button drag"""
	scene_runner.set_mouse_position(start_pos)
	scene_runner.simulate_mouse_button_press(MOUSE_BUTTON_MIDDLE)

	var steps = 10
	for i in range(steps + 1):
		var progress = float(i) / float(steps)
		var current_pos = start_pos.lerp(end_pos, progress)
		scene_runner.set_mouse_position(current_pos)
		await scene_runner.get_scene().get_tree().process_frame

	scene_runner.simulate_mouse_button_release(MOUSE_BUTTON_MIDDLE)

static func simulate_zoom_gesture(scene_runner, center_pos: Vector2, zoom_in: bool, steps: int = 5):
	"""Simulate zoom gesture at a position"""
	scene_runner.set_mouse_position(center_pos)

	for i in range(steps):
		var delta = 1.0 if zoom_in else -1.0
		await simulate_mouse_wheel(scene_runner, center_pos, delta)
		await scene_runner.get_scene().get_tree().create_timer(0.1).timeout

static func simulate_multi_touch_pinch(scene_runner, center: Vector2, start_distance: float, end_distance: float):
	"""Simulate pinch gesture (for touch/trackpad zoom)"""
	# This is complex and may require custom event handling
	# For now, just simulate equivalent mouse wheel
	var zoom_amount = (end_distance - start_distance) / start_distance
	await simulate_mouse_wheel(scene_runner, center, zoom_amount * 5.0)

static func wait_for_animation(scene_runner, duration_seconds: float):
	"""Wait for an animation to complete"""
	await scene_runner.get_scene().get_tree().create_timer(duration_seconds).timeout

static func wait_for_signal_or_timeout(scene_runner, signal_object: Object, signal_name: String, timeout_seconds: float = 5.0) -> bool:
	"""Wait for a signal with timeout, returns true if signal fired, false if timeout"""
	var timer = scene_runner.get_scene().get_tree().create_timer(timeout_seconds)
	var signal_received = false

	var signal_callback = func():
		signal_received = true

	signal_object.connect(signal_name, signal_callback, CONNECT_ONE_SHOT)

	# Wait for either signal or timeout
	while not signal_received and not timer.time_left <= 0:
		await scene_runner.get_scene().get_tree().process_frame

	if signal_object.is_connected(signal_name, signal_callback):
		signal_object.disconnect(signal_name, signal_callback)

	return signal_received

static func simulate_realistic_mouse_movement(scene_runner, start_pos: Vector2, end_pos: Vector2, duration_seconds: float = 0.5):
	"""Simulate realistic human-like mouse movement with slight curves and varying speed"""
	var distance = start_pos.distance_to(end_pos)
	var steps = max(10, int(distance / 10.0))  # More steps for longer distances

	var time_per_step = duration_seconds / float(steps)

	for i in range(steps + 1):
		var progress = float(i) / float(steps)

		# Apply easing for more realistic movement (fast in middle, slow at ends)
		var eased_progress = ease(progress, -2.0)  # Ease out curve

		# Add slight random curve for human-like movement
		var randomness = Vector2(randf_range(-2, 2), randf_range(-2, 2))
		var base_pos = start_pos.lerp(end_pos, eased_progress)
		var current_pos = base_pos + randomness * (1.0 - abs(progress - 0.5) * 2.0)  # More wobble in middle

		scene_runner.set_mouse_position(current_pos)
		await scene_runner.get_scene().get_tree().create_timer(time_per_step).timeout

static func simulate_player_hesitation(scene_runner, duration_seconds: float = 0.5):
	"""Simulate player hesitation/thinking pause"""
	await scene_runner.get_scene().get_tree().create_timer(duration_seconds).timeout

static func simulate_frantic_clicking(scene_runner, positions: Array[Vector2], clicks_per_second: float = 10.0):
	"""Simulate frantic/panicked clicking at multiple positions"""
	var delay = 1.0 / clicks_per_second

	for pos in positions:
		scene_runner.set_mouse_position(pos)
		scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		await scene_runner.get_scene().get_tree().create_timer(delay).timeout
		scene_runner.simulate_mouse_button_released(MOUSE_BUTTON_LEFT)
		await scene_runner.get_scene().get_tree().create_timer(delay).timeout

# Gameplay-specific helpers

static func simulate_deployment_click(scene_runner, position: Vector2, rotation_taps: int = 0):
	"""Simulate deployment: click to place, then Q/E to rotate"""
	scene_runner.set_mouse_position(position)
	scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	await scene_runner.get_scene().get_tree().process_frame

	# Rotate if needed
	if rotation_taps != 0:
		var key = KEY_E if rotation_taps > 0 else KEY_Q
		for i in range(abs(rotation_taps)):
			await simulate_key_press(scene_runner, key)

static func simulate_key_press(scene_runner, key: Key):
	"""Simulate a single key press and release"""
	var viewport = scene_runner.get_scene().get_viewport()

	var key_event = InputEventKey.new()
	key_event.keycode = key
	key_event.pressed = true
	viewport.push_input(key_event)

	await scene_runner.get_scene().get_tree().process_frame

	key_event.pressed = false
	viewport.push_input(key_event)

	await scene_runner.get_scene().get_tree().process_frame

static func simulate_unit_movement_sequence(scene_runner, unit_positions: Array, move_to_positions: Array):
	"""Simulate moving multiple units in sequence"""
	for i in range(min(unit_positions.size(), move_to_positions.size())):
		# Click unit
		scene_runner.set_mouse_position(unit_positions[i])
		scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		await scene_runner.get_scene().get_tree().create_timer(0.2).timeout

		# Drag to new position
		var end_pos = move_to_positions[i]
		await simulate_realistic_mouse_movement(scene_runner, unit_positions[i], end_pos, 0.5)

		scene_runner.simulate_mouse_button_release(MOUSE_BUTTON_LEFT)
		await scene_runner.get_scene().get_tree().create_timer(0.3).timeout

static func simulate_shooting_sequence(scene_runner, shooter_pos: Vector2, target_pos: Vector2):
	"""Simulate shooting: click shooter, click target, confirm"""
	# Select shooter
	await simulate_realistic_mouse_movement(scene_runner, scene_runner.get_mouse_position(), shooter_pos)
	scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	await scene_runner.get_scene().get_tree().create_timer(0.2).timeout

	# Select target
	await simulate_realistic_mouse_movement(scene_runner, shooter_pos, target_pos)
	scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	await scene_runner.get_scene().get_tree().create_timer(0.3).timeout

static func simulate_measurement(scene_runner, from_pos: Vector2, to_pos: Vector2):
	"""Simulate using measurement tool"""
	# This would typically involve:
	# 1. Activating measurement tool (button or hotkey)
	# 2. Click start point
	# 3. Move to end point
	# 4. Click end point

	scene_runner.set_mouse_position(from_pos)
	scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	await scene_runner.get_scene().get_tree().process_frame

	await simulate_realistic_mouse_movement(scene_runner, from_pos, to_pos, 0.5)

	scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	await scene_runner.get_scene().get_tree().process_frame
