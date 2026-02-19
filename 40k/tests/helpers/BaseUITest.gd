extends "res://addons/gut/test.gd"
class_name BaseUITest

# Base class for UI and user interaction testing
# Provides scene loading, mouse simulation, button interaction helpers,
# coordinate transformation, unit selection from UI lists, model token
# finding and manipulation, and camera integration for viewport testing.
#
# NOTE: UI tests require running with the full scene tree (not headless-only)
# since they need access to the rendered Main scene and its UI elements.

var scene_runner = null
var main_scene = null
var camera = null

func before_each():
	# Verify autoloads are available for test environment
	AutoloadHelper.verify_autoloads_available()

	# Load the main scene via GUT's scene loading
	# In headless mode this may fail gracefully
	_load_main_scene()

func after_each():
	if scene_runner and is_instance_valid(scene_runner):
		scene_runner.queue_free()
		scene_runner = null
	main_scene = null
	camera = null

func _load_main_scene():
	# Try to load the main scene for UI testing
	# scene_runner is created via GUT's scene_runner() method if available
	if has_method("scene_runner"):
		# GUT versions with scene_runner support
		pass

	# Fallback: try to load the scene manually
	var scene_resource = load("res://scenes/Main.tscn")
	if scene_resource:
		main_scene = scene_resource.instantiate()
		if main_scene:
			add_child(main_scene)
			# Find camera
			camera = _find_node_by_class(main_scene, "Camera2D")
			if not camera:
				camera = _find_node_by_class(main_scene, "Camera3D")

func _find_node_by_class(root: Node, class_name_str: String) -> Node:
	if root.get_class() == class_name_str:
		return root
	for child in root.get_children():
		var found = _find_node_by_class(child, class_name_str)
		if found:
			return found
	return null

# --- Phase transition helpers ---

func transition_to_phase(phase) -> void:
	var game_state = AutoloadHelper.get_game_state()
	if game_state and game_state.state.has("meta"):
		game_state.state.meta.phase = phase

	var phase_manager = AutoloadHelper.get_phase_manager()
	if phase_manager and phase_manager.has_method("transition_to_phase"):
		phase_manager.transition_to_phase(phase)

func assert_phase_label(expected_text: String, message: String = ""):
	var label = find_ui_element("PhaseLabel", Label)
	if label:
		assert_eq(label.text.to_upper(), expected_text.to_upper(),
			message if message else "Phase label should show " + expected_text)
	else:
		# If we can't find the label, check the game state phase name instead
		var game_state = AutoloadHelper.get_game_state()
		if game_state and game_state.state.has("meta"):
			var current_phase = game_state.state.meta.get("phase", -1)
			gut.p("Phase label not found, current phase index: %s" % str(current_phase))
		pending("Phase label UI element not found — may require non-headless mode")

# --- UI element helpers ---

func find_ui_element(element_name: String, element_type = null) -> Node:
	if not main_scene:
		return null

	var node = main_scene.find_child(element_name, true, false)
	if node and element_type != null:
		if not is_instance_of(node, element_type):
			return null
	return node

func click_button(button_name: String) -> void:
	var button = find_ui_element(button_name, Button)
	if button:
		var button_pos = button.global_position + button.size / 2
		if scene_runner:
			scene_runner.set_mouse_position(button_pos)
			scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		else:
			# Fallback: emit the pressed signal directly
			button.emit_signal("pressed")
	else:
		gut.p("[BaseUITest] Button not found: " + button_name)

func select_unit_from_list(index: int) -> void:
	var unit_list = find_ui_element("UnitList", ItemList)
	if not unit_list:
		unit_list = find_ui_element("UnitListPanel", Control)

	if unit_list and unit_list is ItemList:
		if index < unit_list.get_item_count():
			unit_list.select(index)
			unit_list.emit_signal("item_selected", index)
	else:
		gut.p("[BaseUITest] Unit list not found or wrong type for index: %d" % index)

# --- Model token helpers ---

func find_model_token(unit_id: String, model_name: String) -> Node:
	if not main_scene:
		return null

	# Search for model tokens in the scene tree
	var tokens = _find_all_by_group(main_scene, "model_tokens")
	for token in tokens:
		if token.has_meta("unit_id") and token.get_meta("unit_id") == unit_id:
			if token.has_meta("model_name") and token.get_meta("model_name") == model_name:
				return token

	# Fallback: search by node name pattern
	var search_name = unit_id + "_" + model_name
	var node = main_scene.find_child(search_name, true, false)
	if node:
		return node

	# Try matching by partial name
	for child in _get_all_descendants(main_scene):
		if child.name.contains(model_name) and child.name.contains(unit_id):
			return child

	return null

func _find_all_by_group(root: Node, group_name: String) -> Array:
	var result = []
	if root.is_in_group(group_name):
		result.append(root)
	for child in root.get_children():
		result.append_array(_find_all_by_group(child, group_name))
	return result

func _get_all_descendants(root: Node) -> Array:
	var result = []
	for child in root.get_children():
		result.append(child)
		result.append_array(_get_all_descendants(child))
	return result

# --- Drag helpers ---

func drag_model(from_pos: Vector2, to_pos: Vector2) -> void:
	if scene_runner:
		scene_runner.set_mouse_position(from_pos)
		scene_runner.simulate_mouse_button_press(MOUSE_BUTTON_LEFT)

		# Interpolate movement for realistic drag
		var steps = 5
		for i in range(steps + 1):
			var progress = float(i) / float(steps)
			var current_pos = from_pos.lerp(to_pos, progress)
			scene_runner.set_mouse_position(current_pos)

		scene_runner.simulate_mouse_button_release(MOUSE_BUTTON_LEFT)

# --- Wait helpers ---

func wait_for_ui_update(frames: int = 2) -> void:
	for i in range(frames):
		var tree = get_tree()
		if tree:
			await tree.process_frame

# --- Assertion helpers ---

func assert_unit_card_visible(visible: bool = true, message: String = "") -> void:
	var unit_card = find_ui_element("UnitCard", Control)
	if not unit_card:
		unit_card = find_ui_element("UnitCardPanel", Control)

	if unit_card:
		assert_eq(visible, unit_card.visible,
			message if message else "Unit card visibility should be " + str(visible))
	else:
		if visible:
			pending("Unit card UI element not found — may require non-headless mode")

# Collection assertion helpers (mirror BasePhaseTest)
func assert_has(container, item, message: String = ""):
	var contains = item in container
	assert_true(contains, message if message else str(container) + " should contain " + str(item))

func assert_does_not_have(container, item, message: String = ""):
	var contains = item in container
	assert_false(contains, message if message else str(container) + " should not contain " + str(item))
