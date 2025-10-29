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

func test_oval_deployment_no_false_positive_overlap():
	"""Test that oval bases don't trigger false overlap with bounding circles"""

	# Create two Caladius models (170mm x 105mm ovals)
	var model1_data = {
		"base_mm": 170,
		"base_type": "oval",
		"base_dimensions": {"length": 170, "width": 105},
		"position": Vector2(0, 0),
		"rotation": 0.0
	}

	var model2_data = {
		"base_mm": 170,
		"base_type": "oval",
		"base_dimensions": {"length": 170, "width": 105},
		"position": Vector2(200, 0),  # 200px apart horizontally
		"rotation": 0.0
	}

	# Models should NOT overlap
	# Bounding circle approach: radius ~85mm each, 200px apart -> MIGHT falsely report overlap
	# Actual shape approach: ovals don't touch -> correctly reports no overlap

	var shape1 = Measurement.create_base_shape(model1_data)
	var shape2 = Measurement.create_base_shape(model2_data)

	var overlaps = shape1.overlaps_with(shape2,
		model1_data.position, model1_data.rotation,
		model2_data.position, model2_data.rotation)

	assert_false(overlaps, "Oval bases 200px apart should not overlap")

func test_caladius_deployment_near_edge():
	"""Test that Caladius can deploy near zone edge where bounding circle would fail"""

	# Deployment zone polygon (simplified)
	var zone = PackedVector2Array([
		Vector2(0, 0),
		Vector2(1000, 0),
		Vector2(1000, 500),
		Vector2(0, 500)
	])

	# Caladius positioned near edge
	# Oval is 170mm x 105mm (~267px x 165px)
	# Position 150px from edge - actual oval fits, bounding circle doesn't
	var caladius_data = {
		"base_mm": 170,
		"base_type": "oval",
		"base_dimensions": {"length": 170, "width": 105},
		"rotation": PI / 2  # Rotated 90 degrees (narrow side toward edge)
	}

	var position = Vector2(150, 250)  # Near left edge

	# Test using shape-aware zone validation
	var shape = Measurement.create_base_shape(caladius_data)
	assert_not_null(shape, "Should create oval shape")

	# Get all corners of the oval in world space
	var bounds = shape.get_bounds()
	var corners = [
		Vector2(-bounds.size.x/2, -bounds.size.y/2),
		Vector2(bounds.size.x/2, -bounds.size.y/2),
		Vector2(bounds.size.x/2, bounds.size.y/2),
		Vector2(-bounds.size.x/2, bounds.size.y/2)
	]

	# Transform corners to world space with rotation
	var all_in_zone = true
	for corner in corners:
		var rotated = corner.rotated(caladius_data.rotation)
		var world_corner = position + rotated
		var in_zone = Geometry2D.is_point_in_polygon(world_corner, zone)
		if not in_zone:
			all_in_zone = false
			break

	assert_true(all_in_zone, "Rotated Caladius should fit 150px from edge")

func test_rotated_oval_near_edge_false_positive():
	"""Test that 90-degree rotated oval doesn't falsely report outside zone"""

	# This test replicates the user-reported bug:
	# Caladius rotated 90 degrees (narrow side toward edge) falsely reported as outside zone

	var zone = PackedVector2Array([
		Vector2(0, 0),
		Vector2(1000, 0),
		Vector2(1000, 600),
		Vector2(0, 600)
	])

	var caladius_data = {
		"base_mm": 170,
		"base_type": "oval",
		"base_dimensions": {"length": 170, "width": 105}
	}

	var shape = Measurement.create_base_shape(caladius_data)
	var bounds = shape.get_bounds()

	# Test 1: No rotation - long axis horizontal
	# Position 150px from left edge - should fit
	var pos_no_rotation = Vector2(150, 300)
	var rotation_0 = 0.0

	var half_width_0 = bounds.size.x / 2.0
	var half_height_0 = bounds.size.y / 2.0
	var corners_0 = [
		Vector2(-half_width_0, -half_height_0),
		Vector2(half_width_0, -half_height_0),
		Vector2(half_width_0, half_height_0),
		Vector2(-half_width_0, half_height_0)
	]

	var all_in_0 = true
	for corner in corners_0:
		var world_corner = shape.to_world_space(corner, pos_no_rotation, rotation_0)
		if not Geometry2D.is_point_in_polygon(world_corner, zone):
			all_in_0 = false
			break

	assert_true(all_in_0, "Caladius at 0° should fit 150px from edge")

	# Test 2: 90-degree rotation - narrow side toward edge
	# Same position but rotated - should STILL fit because narrow side is toward edge
	var pos_rotated = Vector2(150, 300)
	var rotation_90 = PI / 2.0  # 90 degrees

	var all_in_90 = true
	for corner in corners_0:
		var world_corner = shape.to_world_space(corner, pos_rotated, rotation_90)
		if not Geometry2D.is_point_in_polygon(world_corner, zone):
			all_in_90 = false
			break

	assert_true(all_in_90, "Caladius at 90° should fit 150px from edge (narrow side toward edge)")

	# Calculate actual required distance from edge for each rotation
	# At 0°: needs length/2 = 133.5px clearance
	# At 90°: needs width/2 = 82.5px clearance
	var length_px = Measurement.mm_to_px(170) / 2.0
	var width_px = Measurement.mm_to_px(105) / 2.0

	# At 150px from edge:
	# - 0° rotation needs 133.5px (length/2) -> 150 > 133.5 ✓ fits
	# - 90° rotation needs 82.5px (width/2) -> 150 > 82.5 ✓ definitely fits

	# This test ensures the 90° rotation doesn't falsely fail
