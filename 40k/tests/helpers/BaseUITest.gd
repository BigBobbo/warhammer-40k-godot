extends GutTest
class_name BaseUITest

# Base class for UI testing with mouse simulation
# Provides utilities for testing UI interactions, button clicks, and mouse operations

var main_scene
var camera: Camera2D

func before_each():
	# Load the main scene for UI testing
	scene_runner = get_scene_runner()
	scene_runner.load_scene("res://scenes/Main.tscn")
	main_scene = scene_runner.get_scene()
	
	# Wait for scene to be ready
	await wait_for_signal(main_scene.ready, 2)
	
	# Find the camera for coordinate transformations
	camera = main_scene.find_child("Camera2D", true, false)
	
	# Ensure game is in a clean state
	reset_game_state()

func after_each():
	if scene_runner:
		scene_runner.clear_scene()
	scene_runner = null
	main_scene = null
	camera = null

func reset_game_state():
	# Reset GameState to known clean state
	if GameState:
		var clean_state = TestDataFactory.create_clean_state()
		GameState.load_from_snapshot(clean_state)

# Button interaction methods
func click_button(button_name: String):
	var button = find_ui_element(button_name, Button)
	assert_not_null(button, "Button should exist: " + button_name)
	assert_true(button.visible, "Button should be visible: " + button_name)
	assert_false(button.disabled, "Button should be enabled: " + button_name)
	
	var button_pos = get_global_center(button)
	scene_runner.set_mouse_position(button_pos)
	scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	await await_input_processed()

func assert_button_visible(button_name: String, visible: bool = true):
	var button = find_ui_element(button_name, Button)
	assert_not_null(button, "Button should exist: " + button_name)
	assert_eq(visible, button.visible, "Button " + button_name + " visibility should be " + str(visible))

func assert_button_enabled(button_name: String, enabled: bool = true):
	var button = find_ui_element(button_name, Button)
	assert_not_null(button, "Button should exist: " + button_name)
	assert_eq(enabled, not button.disabled, "Button " + button_name + " enabled state should be " + str(enabled))

# Mouse simulation methods
func drag_model(from_pos: Vector2, to_pos: Vector2):
	# Convert screen coordinates to world coordinates if needed
	var world_from = screen_to_world(from_pos)
	var world_to = screen_to_world(to_pos)
	
	scene_runner.set_mouse_position(world_from)
	scene_runner.simulate_mouse_button_press(MOUSE_BUTTON_LEFT)
	await await_input_processed()
	
	# Simulate drag movement
	var steps = 5
	for i in range(steps + 1):
		var progress = float(i) / float(steps)
		var current_pos = world_from.lerp(world_to, progress)
		scene_runner.set_mouse_position(current_pos)
		await await_input_processed()
	
	scene_runner.simulate_mouse_button_release(MOUSE_BUTTON_LEFT)
	await await_input_processed()

func click_at_position(pos: Vector2):
	var world_pos = screen_to_world(pos)
	scene_runner.set_mouse_position(world_pos)
	scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	await await_input_processed()

func right_click_at_position(pos: Vector2):
	var world_pos = screen_to_world(pos)
	scene_runner.set_mouse_position(world_pos)
	scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	await await_input_processed()

# Coordinate transformation methods
func screen_to_world(screen_pos: Vector2) -> Vector2:
	if camera:
		# Account for camera position and zoom
		var camera_transform = camera.get_global_transform()
		return camera_transform * screen_pos
	return screen_pos

func world_to_screen(world_pos: Vector2) -> Vector2:
	if camera:
		# Convert world position to screen coordinates
		var camera_transform = camera.get_global_transform()
		return camera_transform.affine_inverse() * world_pos
	return world_pos

# UI element finding methods
func find_ui_element(element_name: String, element_type = null):
	# Try different search patterns
	var element = main_scene.find_child(element_name, true, false)
	if element:
		return element
	
	# Try with different naming patterns
	var patterns = [
		element_name + "Button",
		element_name + "Panel", 
		element_name + "Label",
		element_name.to_pascal_case(),
		element_name.to_snake_case()
	]
	
	for pattern in patterns:
		element = main_scene.find_child(pattern, true, false)
		if element:
			return element
	
	return null

func get_global_center(node: Control) -> Vector2:
	return node.global_position + node.size / 2

# Unit list interaction methods
func select_unit_from_list(unit_index: int):
	var unit_list = find_ui_element("UnitListPanel", ItemList)
	assert_not_null(unit_list, "Unit list should exist")
	assert_gt(unit_list.get_item_count(), unit_index, "Unit list should have enough items")
	
	# Click on the unit list item
	var item_rect = unit_list.get_item_rect(unit_index)
	var click_pos = unit_list.global_position + item_rect.position + item_rect.size / 2
	
	scene_runner.set_mouse_position(click_pos)
	scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	await await_input_processed()

func get_unit_list_count() -> int:
	var unit_list = find_ui_element("UnitListPanel", ItemList)
	if unit_list:
		return unit_list.get_item_count()
	return 0

# Phase transition helpers
func transition_to_phase(phase: GameStateData.Phase):
	if PhaseManager:
		PhaseManager.transition_to_phase(phase)
		await await_input_processed()

func click_end_phase_button():
	click_button("EndDeploymentButton")  # This button changes text based on phase

# Model token interaction methods
func find_model_token(unit_id: String, model_id: String = "") -> Node2D:
	# Look for model tokens in the TokenLayer
	var token_layer = main_scene.find_child("TokenLayer", true, false)
	if not token_layer:
		return null
	
	for child in token_layer.get_children():
		if child.has_method("get_unit_id") and child.get_unit_id() == unit_id:
			if model_id == "" or (child.has_method("get_model_id") and child.get_model_id() == model_id):
				return child
	
	return null

func get_model_token_position(unit_id: String, model_id: String = "") -> Vector2:
	var token = find_model_token(unit_id, model_id)
	if token:
		return token.global_position
	return Vector2.ZERO

func click_model_token(unit_id: String, model_id: String = ""):
	var token = find_model_token(unit_id, model_id)
	assert_not_null(token, "Model token should exist for " + unit_id + "/" + model_id)
	
	var token_pos = token.global_position
	scene_runner.set_mouse_position(token_pos)
	scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	await await_input_processed()

func drag_model_token(unit_id: String, model_id: String, to_pos: Vector2):
	var token = find_model_token(unit_id, model_id)
	assert_not_null(token, "Model token should exist for " + unit_id + "/" + model_id)
	
	var from_pos = token.global_position
	drag_model(from_pos, to_pos)

# UI state verification methods
func assert_phase_label(expected_text: String):
	var phase_label = find_ui_element("PhaseLabel", Label)
	assert_not_null(phase_label, "Phase label should exist")
	assert_eq(expected_text, phase_label.text, "Phase label should show correct phase")

func assert_status_message(expected_text: String):
	var status_label = find_ui_element("StatusLabel", Label)
	assert_not_null(status_label, "Status label should exist")
	assert_eq(expected_text, status_label.text, "Status should show correct message")

func assert_unit_card_visible(visible: bool = true):
	var unit_card = find_ui_element("UnitCard", VBoxContainer)
	assert_not_null(unit_card, "Unit card should exist")
	assert_eq(visible, unit_card.visible, "Unit card visibility should be " + str(visible))

# Camera and viewport helpers
func get_test_viewport() -> Viewport:
	return main_scene.get_viewport()

func wait_for_ui_update():
	# Wait multiple frames for UI to fully update
	await await_input_processed()
	await await_input_processed()

# Error handling helpers
func expect_no_errors():
	# Check that no error dialogs or messages are shown
	# This can be extended based on how errors are displayed in the game
	pass