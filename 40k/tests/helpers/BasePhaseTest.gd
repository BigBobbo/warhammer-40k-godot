extends "res://addons/gut/test.gd"
class_name BasePhaseTest

const BasePhase = preload("res://phases/BasePhase.gd")


# Base class for phase testing
# Provides common utilities for testing all phases

var phase_instance
var test_state: Dictionary

func before_each():
	# Ensure autoloads available
	AutoloadHelper.verify_autoloads_available()

	test_state = TestDataFactory.create_test_game_state()
	setup_phase_instance()

func setup_phase_instance():
	# Override in subclasses to create specific phase instances
	# Example: phase_instance = MovementPhase.new()
	pass

func after_each():
	if phase_instance:
		phase_instance.queue_free()
		phase_instance = null

# Assertion helpers for phase testing
func assert_valid_action(action: Dictionary, message: String = ""):
	var result = phase_instance.validate_action(action)
	assert_true(result.valid, message if message else "Action should be valid: " + str(action))
	return result

func assert_invalid_action(action: Dictionary, expected_errors: Array = [], message: String = ""):
	var result = phase_instance.validate_action(action)
	assert_false(result.valid, message if message else "Action should be invalid: " + str(action))
	
	if expected_errors.size() > 0:
		for expected_error in expected_errors:
			var found_error = false
			for error in result.get("errors", []):
				if error.contains(expected_error):
					found_error = true
					break
			assert_true(found_error, "Expected error containing '" + expected_error + "' in: " + str(result.get("errors", [])))
	
	return result

func assert_action_success(action: Dictionary, message: String = ""):
	var result = phase_instance.execute_action(action)
	assert_true(result.get("success", false), message if message else "Action execution should succeed: " + str(action))
	return result

func assert_action_failure(action: Dictionary, message: String = ""):
	var result = phase_instance.execute_action(action)
	assert_false(result.get("success", true), message if message else "Action execution should fail: " + str(action))
	return result

# Helper to enter phase with test state
func enter_phase():
	if phase_instance:
		phase_instance.enter_phase(test_state)

# Helper to get available actions
func get_available_actions() -> Array:
	if phase_instance and phase_instance.has_method("get_available_actions"):
		return phase_instance.get_available_actions()
	return []

# Helper to verify state changes
func assert_state_change(before_value, after_value, message: String = ""):
	assert_ne(before_value, after_value, message if message else "State should have changed")

func assert_no_state_change(before_value, after_value, message: String = ""):
	assert_eq(before_value, after_value, message if message else "State should not have changed")

# Helper to create common actions
func create_action(action_type: String, unit_id: String = "", payload: Dictionary = {}) -> Dictionary:
	return {
		"type": action_type,
		"actor_unit_id": unit_id,
		"payload": payload
	}

# Helper to verify phase transition readiness
func assert_phase_can_complete(message: String = ""):
	if phase_instance and phase_instance.has_method("_should_complete_phase"):
		var can_complete = phase_instance._should_complete_phase()
		assert_true(can_complete, message if message else "Phase should be ready to complete")

func assert_phase_cannot_complete(message: String = ""):
	if phase_instance and phase_instance.has_method("_should_complete_phase"):
		var can_complete = phase_instance._should_complete_phase()
		assert_false(can_complete, message if message else "Phase should not be ready to complete")

# Utility for testing unit states
func get_test_unit(unit_id: String = "test_unit_1") -> Dictionary:
	if test_state.has("units") and test_state.units.has(unit_id):
		return test_state.units[unit_id]
	return {}

func assert_unit_has_flag(unit_id: String, flag_name: String, expected_value = true, message: String = ""):
	var unit = get_test_unit(unit_id)
	var actual_value = unit.get("flags", {}).get(flag_name, false)
	assert_eq(expected_value, actual_value, message if message else "Unit " + unit_id + " should have flag " + flag_name + " = " + str(expected_value))

func assert_unit_status(unit_id: String, expected_status: int, message: String = ""):
	var unit = get_test_unit(unit_id)
	var actual_status = unit.get("status", 0)
	assert_eq(expected_status, actual_status, message if message else "Unit " + unit_id + " should have status " + str(expected_status))

# Helper for testing model positions
func assert_model_position(unit_id: String, model_id: String, expected_pos: Vector2, tolerance: float = 1.0, message: String = ""):
	var unit = get_test_unit(unit_id)
	var models = unit.get("models", [])
	
	for model in models:
		if model.get("id", "") == model_id:
			var pos = model.get("position", {})
			var actual_pos = Vector2(pos.get("x", 0), pos.get("y", 0))
			assert_almost_eq(expected_pos.x, actual_pos.x, tolerance, message if message else "Model X position should match")
			assert_almost_eq(expected_pos.y, actual_pos.y, tolerance, message if message else "Model Y position should match")
			return
	
	assert_true(false, "Model " + model_id + " not found in unit " + unit_id)

# Helper for dice testing
func assert_dice_rolled(result: Dictionary, dice_type: String, message: String = ""):
	assert_true(result.has("dice"), "Result should contain dice information")
	var dice_results = result.get("dice", [])
	var found_dice_type = false

	for dice_result in dice_results:
		if dice_result.get("context", "") == dice_type:
			found_dice_type = true
			break

	assert_true(found_dice_type, message if message else "Should have rolled dice for " + dice_type)

# Collection assertion helpers
func assert_has(container, item, message: String = ""):
	var contains = item in container
	assert_true(contains, message if message else str(container) + " should contain " + str(item))

func assert_does_not_have(container, item, message: String = ""):
	var contains = item in container
	assert_false(contains, message if message else str(container) + " should not contain " + str(item))
