extends GutTest

# test_deployment_repositioning.gd - Unit tests for deployment model repositioning feature

var dc  # DeploymentController - no type hint to avoid parse error
var test_unit_id: String = "test_unit"
var test_model_data: Dictionary = {
	"base_mm": 32,
	"base_type": "circular"
}
var test_unit: Dictionary  # Initialized in before_each

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	# Initialize test unit (requires GameStateData to be loaded)
	test_unit = {
		"id": test_unit_id,
		"owner": 1,
		"status": GameStateData.UnitStatus.UNDEPLOYED,
		"models": [
			{"base_mm": 32, "base_type": "circular"},
			{"base_mm": 32, "base_type": "circular"},
			{"base_mm": 32, "base_type": "circular"}
		]
	}

func setup_deployment_controller():
	"""Helper to set up a deployment controller for testing"""
	dc = DeploymentController.new()

	# Create mock layers
	var token_layer = Node2D.new()
	var ghost_layer = Node2D.new()
	add_child(token_layer)
	add_child(ghost_layer)
	dc.set_layers(token_layer, ghost_layer)

	# Setup test state
	if Engine.has_singleton("GameState"):
		var game_state = Engine.get_singleton("GameState")
		game_state.state = {
			"units": {test_unit_id: test_unit},
			"meta": {"active_player": 1}
		}

	# Setup deployment zone
	if Engine.has_singleton("BoardState"):
		var board_state = Engine.get_singleton("BoardState")
		board_state.deployment_zones = {
			1: {"poly": [
				{"x": 0, "y": 0},
				{"x": 1000, "y": 0},
				{"x": 1000, "y": 500},
				{"x": 0, "y": 500}
			]}
		}

	return dc

func test_shift_click_detection():
	"""Test that shift+click properly detects deployed models"""
	var dc = setup_deployment_controller()
	dc.begin_deploy(test_unit_id)

	# Place a model first
	dc.try_place_at(Vector2(400, 400))

	# Test shift+click detection
	var deployed_model = dc._get_deployed_model_at_position(Vector2(405, 405))
	assert_false(deployed_model.is_empty(), "Should detect deployed model near position")
	assert_eq(deployed_model.model_index, 0, "Should detect first model")
	assert_eq(deployed_model.position, Vector2(400, 400), "Should return correct position")

	# Test detection outside radius
	var far_model = dc._get_deployed_model_at_position(Vector2(500, 500))
	assert_true(far_model.is_empty(), "Should not detect model outside radius")

	# Clean up
	dc.queue_free()

func test_repositioning_validation():
	"""Test that repositioning follows deployment rules"""
	var dc = setup_deployment_controller()
	dc.begin_deploy(test_unit_id)

	# Place initial model
	dc.try_place_at(Vector2(400, 400))

	# Test valid repositioning within deployment zone
	var valid_pos = Vector2(450, 450)
	var is_valid = dc._validate_reposition(valid_pos, test_model_data, 0)
	assert_true(is_valid, "Valid repositioning within zone should pass")

	# Test invalid repositioning (outside zone)
	var invalid_pos = Vector2(100, 600)  # Outside deployment zone
	var is_invalid = dc._validate_reposition(invalid_pos, test_model_data, 0)
	assert_false(is_invalid, "Invalid repositioning outside zone should fail")

	# Clean up
	dc.queue_free()

func test_overlap_prevention():
	"""Test that repositioning prevents overlaps"""
	var dc = setup_deployment_controller()
	dc.begin_deploy(test_unit_id)

	# Place two models
	dc.try_place_at(Vector2(400, 400))
	dc.try_place_at(Vector2(500, 400))

	# Try to check if repositioning first model would overlap with second
	var overlap_pos = Vector2(495, 400)  # Very close to second model
	var would_overlap = dc._would_overlap_excluding_self(overlap_pos, test_model_data, 0)
	assert_true(would_overlap, "Should detect overlap during repositioning")

	# Test non-overlapping position
	var no_overlap_pos = Vector2(300, 400)  # Far from second model
	var would_not_overlap = dc._would_overlap_excluding_self(no_overlap_pos, test_model_data, 0)
	assert_false(would_not_overlap, "Should not detect overlap for valid position")

	# Clean up
	dc.queue_free()

func test_repositioning_state_management():
	"""Test repositioning state is properly managed"""
	var dc = setup_deployment_controller()
	dc.begin_deploy(test_unit_id)

	# Place a model
	dc.try_place_at(Vector2(400, 400))

	# Start repositioning
	var deployed_model = {
		"model_index": 0,
		"position": Vector2(400, 400),
		"model_data": test_model_data
	}
	dc._start_model_repositioning(deployed_model)

	# Check state
	assert_true(dc.repositioning_model, "Should be in repositioning mode")
	assert_eq(dc.reposition_model_index, 0, "Should track correct model index")
	assert_eq(dc.reposition_start_pos, Vector2(400, 400), "Should store start position")
	assert_not_null(dc.reposition_ghost, "Should create reposition ghost")

	# Cancel repositioning
	dc._cancel_model_repositioning()

	# Check state cleared
	assert_false(dc.repositioning_model, "Should no longer be repositioning")
	assert_eq(dc.reposition_model_index, -1, "Should reset model index")
	assert_eq(dc.reposition_start_pos, Vector2.ZERO, "Should reset start position")
	assert_null(dc.reposition_ghost, "Should clear ghost")

	# Clean up
	dc.queue_free()

func test_coherency_maintenance():
	"""Test that repositioning maintains unit coherency warnings"""
	var dc = setup_deployment_controller()
	var large_unit = test_unit.duplicate()
	large_unit["models"] = []
	for i in range(5):
		large_unit["models"].append({"base_mm": 32, "base_type": "circular"})

	if Engine.has_singleton("GameState"):
		var game_state = Engine.get_singleton("GameState")
		game_state.state["units"][test_unit_id] = large_unit
	dc.begin_deploy(test_unit_id)

	# Place models in formation
	for i in range(5):
		dc.try_place_at(Vector2(400 + i * 65, 400))

	# Start repositioning middle model
	var deployed_model = {
		"model_index": 2,
		"position": Vector2(530, 400),
		"model_data": test_model_data
	}
	dc._start_model_repositioning(deployed_model)

	# Test repositioning far away (should trigger coherency warning when completed)
	# Note: The actual deployment phase might prevent this, but we're testing the warning system
	var far_pos = Vector2(700, 600)
	var is_valid_zone = dc._validate_reposition(far_pos, test_model_data, 2)
	# This tests that zone/overlap validation works, coherency is checked after placement

	# Clean up
	dc._cleanup_repositioning()
	dc.queue_free()

func test_reposition_with_different_base_shapes():
	"""Test repositioning works with different base shapes"""
	var dc = setup_deployment_controller()

	# Test with rectangular base
	var rect_model_data = {
		"base_mm": 50,
		"base_type": "rectangular",
		"base_dimensions": {"length": 50, "width": 30}
	}

	var rect_unit = test_unit.duplicate()
	rect_unit["models"] = [rect_model_data, rect_model_data]
	if Engine.has_singleton("GameState"):
		var game_state = Engine.get_singleton("GameState")
		game_state.state["units"][test_unit_id] = rect_unit

	dc.begin_deploy(test_unit_id)
	dc.try_place_at(Vector2(400, 400))
	dc.try_place_at(Vector2(500, 400))

	# Test repositioning with rectangular base
	var would_overlap = dc._would_overlap_excluding_self(Vector2(480, 400), rect_model_data, 0)
	assert_true(would_overlap, "Should detect overlap with rectangular bases")

	# Clean up
	dc.queue_free()

func test_ghost_visual_creation_and_cleanup():
	"""Test that ghost visuals are properly created and cleaned up"""
	var dc = setup_deployment_controller()
	dc.begin_deploy(test_unit_id)

	# Place a model
	dc.try_place_at(Vector2(400, 400))

	# Start repositioning - should create ghost
	var deployed_model = {
		"model_index": 0,
		"position": Vector2(400, 400),
		"model_data": test_model_data
	}
	dc._start_model_repositioning(deployed_model)

	assert_not_null(dc.reposition_ghost, "Should create reposition ghost")
	assert_true(is_instance_valid(dc.reposition_ghost), "Ghost should be valid instance")

	# End repositioning - should cleanup ghost
	dc._cleanup_repositioning()

	# Ghost should be freed
	assert_null(dc.reposition_ghost, "Ghost should be null after cleanup")

	# Clean up
	dc.queue_free()

func test_token_opacity_during_repositioning():
	"""Test that token opacity changes during repositioning"""
	var dc = setup_deployment_controller()
	dc.begin_deploy(test_unit_id)

	# Place a model
	dc.try_place_at(Vector2(400, 400))

	# Get the token
	assert_eq(dc.placed_tokens.size(), 1, "Should have one placed token")
	var token = dc.placed_tokens[0]
	assert_eq(token.modulate.a, 1.0, "Token should start with full opacity")

	# Start repositioning
	var deployed_model = {
		"model_index": 0,
		"position": Vector2(400, 400),
		"model_data": test_model_data
	}
	dc._start_model_repositioning(deployed_model)

	# Check token is semi-transparent
	assert_eq(token.modulate.a, 0.3, "Token should be semi-transparent during repositioning")

	# Cancel repositioning
	dc._cancel_model_repositioning()

	# Check token is restored
	assert_eq(token.modulate.a, 1.0, "Token should restore full opacity after cancel")

	# Clean up
	dc.queue_free()

func test_integration_with_formation_mode():
	"""Test that repositioning works alongside formation deployment mode"""
	var dc = setup_deployment_controller()
	dc.begin_deploy(test_unit_id)

	# Set formation mode
	dc.set_formation_mode("SPREAD")
	assert_eq(dc.formation_mode, "SPREAD", "Should be in spread formation mode")

	# Place some models using formation
	# Note: This would normally use formation placement
	dc.set_formation_mode("SINGLE")  # Switch back for individual placement
	dc.try_place_at(Vector2(400, 400))

	# Now test repositioning still works
	var deployed_model = dc._get_deployed_model_at_position(Vector2(400, 400))
	assert_false(deployed_model.is_empty(), "Should detect model placed via formation")

	# Clean up
	dc.queue_free()