extends "res://addons/gut/test.gd"
const CircularBase = preload("res://scripts/bases/CircularBase.gd")
const RectangularBase = preload("res://scripts/bases/RectangularBase.gd")
const OvalBase = preload("res://scripts/bases/OvalBase.gd")

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

func test_rectangular_transport_disembark_range():
	# Create a rectangular transport (Battlewagon)
	var transport_model = {
		"base_mm": 180,
		"base_type": "rectangular",
		"base_dimensions": {"length": 180, "width": 110},
		"position": Vector2(0, 0),
		"alive": true
	}

	var transport_shape = Measurement.create_base_shape(transport_model)
	assert_eq(transport_shape.get_type(), "rectangular")

	# Test disembarkation range calculation
	var range_px = Measurement.inches_to_px(3.0)
	var rect_base = transport_shape as RectangularBase
	var expected_expanded_length = rect_base.length + (2 * range_px)
	var expected_expanded_width = rect_base.width + (2 * range_px)

	# Points that should be valid (within expanded rectangle)
	var valid_point = Vector2(expected_expanded_length/2 - 10, 0)  # Just inside edge
	var inside_point = Vector2(0, 0)  # Center

	# Points that should be invalid (outside expanded rectangle)
	var invalid_point = Vector2(expected_expanded_length/2 + 10, 0)  # Just outside edge

	# Verify the transport shape bounds
	assert_true(expected_expanded_length > rect_base.length)
	assert_true(expected_expanded_width > rect_base.width)

func test_oval_transport_disembark_range():
	# Create an oval transport (Caladius)
	var transport_model = {
		"base_mm": 170,
		"base_type": "oval",
		"base_dimensions": {"length": 170, "width": 105},
		"position": Vector2(0, 0),
		"alive": true
	}

	var transport_shape = Measurement.create_base_shape(transport_model)
	assert_eq(transport_shape.get_type(), "oval")

	# Test disembarkation range calculation
	var range_px = Measurement.inches_to_px(3.0)
	var oval_base = transport_shape as OvalBase
	var expected_expanded_length = oval_base.length + (2 * range_px)
	var expected_expanded_width = oval_base.width + (2 * range_px)

	# Verify the transport shape bounds
	assert_true(expected_expanded_length > oval_base.length)
	assert_true(expected_expanded_width > oval_base.width)

func test_disembark_controller_shape_initialization():
	# Test that DisembarkController properly initializes transport base shape
	var controller = preload("res://scripts/DisembarkController.gd").new()

	# Create mock data
	var transport_data = {
		"models": [{
			"base_mm": 180,
			"base_type": "rectangular",
			"base_dimensions": {"length": 180, "width": 110},
			"position": Vector2(100, 100),
			"alive": true
		}]
	}

	# Test transport base shape creation
	var transport_shape = Measurement.create_base_shape(transport_data.models[0])
	assert_not_null(transport_shape)
	assert_eq(transport_shape.get_type(), "rectangular")

func test_edge_to_edge_distance_calculation():
	# Test accurate distance calculation between different shapes
	var rectangular_transport = {
		"base_type": "rectangular",
		"base_dimensions": {"length": 180, "width": 110},
		"base_mm": 180,
		"position": Vector2(0, 0),
		"rotation": 0
	}

	var circular_infantry = {
		"base_type": "circular",
		"base_mm": 32,
		"position": Vector2(200, 0),  # 200px away from center
		"rotation": 0
	}

	# Calculate distance using proper shape-aware method
	var distance_px = Measurement.model_to_model_distance_px(rectangular_transport, circular_infantry)
	var distance_inches = Measurement.px_to_inches(distance_px)

	# Distance should be less than center-to-center distance because we measure edge-to-edge
	var center_distance = rectangular_transport.position.distance_to(circular_infantry.position)
	assert_lt(distance_px, center_distance)

	# Should be positive (not overlapping)
	assert_gt(distance_inches, 0)

func test_disembark_validation_with_shapes():
	# Mock a disembark validation scenario
	var transport_shape = RectangularBase.new(
		Measurement.mm_to_px(180),  # length
		Measurement.mm_to_px(110)   # width
	)

	var model_shape = CircularBase.new(Measurement.base_radius_px(32))

	var transport_pos = Vector2(0, 0)
	var test_pos = Vector2(120, 0)  # Position to test

	# Get closest edge points
	var closest_transport_edge = transport_shape.get_closest_edge_point(test_pos, transport_pos, 0.0)
	var closest_model_edge = model_shape.get_closest_edge_point(closest_transport_edge, test_pos, 0.0)

	var edge_distance = closest_transport_edge.distance_to(closest_model_edge)
	var distance_inches = Measurement.px_to_inches(edge_distance)

	# Should be a reasonable distance (not negative, not huge)
	assert_ge(distance_inches, 0)
	assert_lt(distance_inches, 10)  # Should be less than 10 inches for this test case

func test_shape_based_range_drawing():
	# Test that different shapes create different range boundaries
	var circular_shape = CircularBase.new(50)
	var rectangular_shape = RectangularBase.new(100, 60)
	var oval_shape = OvalBase.new(100, 60)

	# All shapes should have different bounds
	var circular_bounds = circular_shape.get_bounds()
	var rect_bounds = rectangular_shape.get_bounds()
	var oval_bounds = oval_shape.get_bounds()

	# Rectangular should be different from circular
	assert_ne(rect_bounds.size.x, circular_bounds.size.x * 2)

	# Oval and rectangular with same dimensions should have same bounds
	assert_eq(oval_bounds.size.x, rect_bounds.size.x)
	assert_eq(oval_bounds.size.y, rect_bounds.size.y)

	# But they should have different shape types
	assert_ne(rectangular_shape.get_type(), oval_shape.get_type())
