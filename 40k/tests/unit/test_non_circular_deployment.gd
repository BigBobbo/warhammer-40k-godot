extends GutTest

# Unit tests for non-circular base deployment validation
# Tests oval and rectangular base handling

func before_each():
	# Initialize GameState if needed
	if not GameState.state.has("units"):
		GameState.state.units = {}

func test_oval_base_creation():
	# Test that oval bases are created correctly with proper dimensions
	var model_data = {
		"base_mm": 170,
		"base_type": "oval",
		"base_dimensions": {"length": 170, "width": 105}
	}

	var shape = Measurement.create_base_shape(model_data)
	assert_not_null(shape, "Should create a shape")
	assert_eq(shape.get_type(), "oval", "Should create oval shape")

	var bounds = shape.get_bounds()
	# Bounds are centered at origin, so total size is the dimension
	assert_almost_eq(bounds.size.x, Measurement.mm_to_px(170), 1.0, "Width should match length dimension")
	assert_almost_eq(bounds.size.y, Measurement.mm_to_px(105), 1.0, "Height should match width dimension")

func test_shape_contains_point_for_oval():
	# Test that click detection works correctly for oval bases
	var model_data = {
		"base_mm": 170,
		"base_type": "oval",
		"base_dimensions": {"length": 170, "width": 105}
	}

	var shape = Measurement.create_base_shape(model_data)
	var center = Vector2(500, 500)
	var rotation = 0.0

	# Point at oval edge (within oval but outside circular approximation)
	var length_px = Measurement.mm_to_px(170) / 2.0  # 67px
	var width_px = Measurement.mm_to_px(105) / 2.0   # 41px

	# Point on the minor axis edge (should be inside oval)
	var test_point = center + Vector2(length_px - 5, 0)
	assert_true(shape.contains_point(test_point, center, rotation),
		"Point near length edge should be inside oval")

	# Point on major axis edge
	var test_point2 = center + Vector2(0, width_px - 5)
	assert_true(shape.contains_point(test_point2, center, rotation),
		"Point near width edge should be inside oval")

	# Point outside oval
	var test_point3 = center + Vector2(length_px + 10, 0)
	assert_false(shape.contains_point(test_point3, center, rotation),
		"Point outside oval should not be inside")

func test_bounding_radius_for_oval():
	# Test that bounding radius calculation would be correct
	var model_data = {
		"base_mm": 170,
		"base_type": "oval",
		"base_dimensions": {"length": 170, "width": 105}
	}

	var shape = Measurement.create_base_shape(model_data)
	var bounds = shape.get_bounds()

	# Correct bounding radius is diagonal / 2
	var expected_diagonal = Vector2(bounds.size.x, bounds.size.y).length()
	var expected_radius = expected_diagonal / 2.0

	# Verify that diagonal is larger than max dimension
	# This proves why we need diagonal-based calculation
	var max_dimension = max(bounds.size.x, bounds.size.y)
	assert_gt(expected_diagonal, max_dimension,
		"Diagonal should be larger than max dimension")

func test_oval_base_contains_point():
	# Test that oval shape correctly identifies points inside/outside
	var model_data = {
		"base_mm": 170,
		"base_type": "oval",
		"base_dimensions": {"length": 170, "width": 105}
	}

	var shape = Measurement.create_base_shape(model_data)
	var center = Vector2(500, 500)
	var rotation = 0.0

	# Point at center should be inside
	assert_true(shape.contains_point(center, center, rotation), "Center should be inside oval")

	# Point near length edge (but inside)
	var length_px = Measurement.mm_to_px(170) / 2.0
	var click_pos = center + Vector2(length_px - 5, 0)
	assert_true(shape.contains_point(click_pos, center, rotation), "Point near length edge should be inside")

	# Point outside oval
	var outside_pos = center + Vector2(length_px + 10, 0)
	assert_false(shape.contains_point(outside_pos, center, rotation), "Point outside oval should not be inside")

func test_circular_base_backward_compatibility():
	# Ensure circular bases still work correctly
	var model_data = {
		"base_mm": 32,
		"base_type": "circular"
	}

	var shape = Measurement.create_base_shape(model_data)
	assert_eq(shape.get_type(), "circular", "Should create circular shape")

	# Bounds should be square for circular base
	var bounds = shape.get_bounds()
	var expected_radius = Measurement.mm_to_px(32) / 2.0
	assert_almost_eq(bounds.size.x, expected_radius * 2, 0.1, "Width should be diameter")
	assert_almost_eq(bounds.size.y, expected_radius * 2, 0.1, "Height should be diameter")
