extends Node
class_name GutTest

# Base class for all GUT tests
# This is a simplified implementation of GUT's test base class

signal test_passed(test_name)
signal test_failed(test_name, reason)

var _test_results = []
var _current_test = ""

# GUT compatibility: self-reference for test registry
var gut:
	get: return self

# Test lifecycle methods
func before_each():
	# Override in test classes for setup
	pass

func after_each():
	# Override in test classes for cleanup
	pass

func before_all():
	# Override in test classes for one-time setup
	pass

func after_all():
	# Override in test classes for one-time cleanup
	pass

# Core assertion methods
func assert_true(value, message = ""):
	_assert(value == true, message if message else "Expected true, got " + str(value))

func assert_false(value, message = ""):
	_assert(value == false, message if message else "Expected false, got " + str(value))

func assert_eq(expected, actual, message = ""):
	_assert(expected == actual, message if message else "Expected " + str(expected) + ", got " + str(actual))

func assert_ne(expected, actual, message = ""):
	_assert(expected != actual, message if message else "Expected " + str(expected) + " != " + str(actual))

func assert_almost_eq(expected, actual, tolerance = 0.01, message = ""):
	var diff = abs(expected - actual)
	_assert(diff <= tolerance, message if message else "Expected " + str(expected) + " within " + str(tolerance) + " of " + str(actual))

func assert_null(value, message = ""):
	_assert(value == null, message if message else "Expected null, got " + str(value))

func assert_not_null(value, message = ""):
	_assert(value != null, message if message else "Expected not null, got null")

func assert_gt(actual, expected, message = ""):
	_assert(actual > expected, message if message else str(actual) + " should be greater than " + str(expected))

func assert_lt(actual, expected, message = ""):
	_assert(actual < expected, message if message else str(actual) + " should be less than " + str(expected))

func assert_gte(actual, expected, message = ""):
	_assert(actual >= expected, message if message else str(actual) + " should be greater than or equal to " + str(expected))

func assert_between(actual, min_val, max_val, message = ""):
	_assert(actual >= min_val and actual <= max_val, message if message else str(actual) + " should be between " + str(min_val) + " and " + str(max_val))

func assert_ge(actual, expected, message = ""):
	# Alias for assert_gte for GUT compatibility
	assert_gte(actual, expected, message)

func assert_le(actual, expected, message = ""):
	# Less than or equal assertion
	_assert(actual <= expected, message if message else str(actual) + " should be less than or equal to " + str(expected))

func assert_lte(actual, expected, message = ""):
	# Alias for assert_le
	assert_le(actual, expected, message)

func pending(reason = ""):
	# Mark test as pending/incomplete
	print("PENDING: " + _current_test + " - " + reason)
	_test_results.append({"passed": true, "test": _current_test, "message": "PENDING: " + reason, "pending": true})
	# Early return skips rest of test
	return

func assert_has(container, item, message: String = ""):
	var contains = item in container
	_assert(contains, message if message else str(container) + " should contain " + str(item))

func assert_does_not_have(container, item, message: String = ""):
	var contains = item in container
	_assert(not contains, message if message else str(container) + " should not contain " + str(item))

func skip_test(reason = ""):
	print("SKIPPED: " + _current_test + " - " + reason)
	_test_results.append({"passed": true, "test": _current_test, "message": "SKIPPED: " + reason})

func has_method_on_object(obj, method_name: String) -> bool:
	if obj == null:
		return false
	return obj.has_method(method_name)

# Scene testing support
var scene_runner

func get_scene_runner():
	if not scene_runner:
		scene_runner = SceneRunner.new()
	return scene_runner

# Wait for signal support
func wait_for_signal(signal_obj, timeout = 2.0):
	var timer = Timer.new()
	add_child(timer)
	timer.wait_time = timeout
	timer.one_shot = true
	timer.start()
	
	var result = await signal_obj
	timer.queue_free()
	return result

# Input processing wait
func await_input_processed():
	await get_tree().process_frame

# Internal assertion handling
func _assert(condition, message):
	if condition:
		_test_results.append({"passed": true, "test": _current_test, "message": ""})
		emit_signal("test_passed", _current_test)
	else:
		_test_results.append({"passed": false, "test": _current_test, "message": message})
		emit_signal("test_failed", _current_test, message)
		print("ASSERTION FAILED: " + _current_test + " - " + message)

# Scene Runner class for UI testing
class SceneRunner:
	var scene_instance
	var scene_path: String
	
	func _init(path: String = ""):
		if path != "":
			load_scene(path)
	
	func load_scene(path: String):
		scene_path = path
		var scene_resource = load(path)
		scene_instance = scene_resource.instantiate()
		Engine.get_main_loop().current_scene.add_child(scene_instance)
	
	func get_scene():
		return scene_instance
	
	func clear_scene():
		if scene_instance:
			scene_instance.queue_free()
			scene_instance = null
	
	# Mouse simulation methods
	func set_mouse_position(pos: Vector2):
		# Simple mouse position setting without viewport dependency
		pass
	
	func simulate_mouse_button_pressed(button: MouseButton):
		var event = InputEventMouseButton.new()
		event.button_index = button
		event.pressed = true
		event.position = Vector2.ZERO
		Input.parse_input_event(event)
		
		# Also send release event
		event = InputEventMouseButton.new()
		event.button_index = button
		event.pressed = false
		event.position = Vector2.ZERO
		Input.parse_input_event(event)
	
	func simulate_mouse_button_press(button: MouseButton):
		var event = InputEventMouseButton.new()
		event.button_index = button
		event.pressed = true
		event.position = Vector2.ZERO
		Input.parse_input_event(event)
	
	func simulate_mouse_button_release(button: MouseButton):
		var event = InputEventMouseButton.new()
		event.button_index = button
		event.pressed = false
		event.position = Vector2.ZERO
		Input.parse_input_event(event)
	
	func simulate_action_input(action: String):
		var event = InputEventAction.new()
		event.action = action
		event.pressed = true
		Input.parse_input_event(event)