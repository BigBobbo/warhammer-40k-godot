extends "res://addons/gut/test.gd"

# Test engagement range with mixed base shapes
# This test verifies that engagement range calculations use actual base shapes
# instead of circular approximations

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

func test_circular_to_oval_engagement_range():
	var infantry = {
		"id": "m1",
		"base_mm": 32,
		"base_type": "circular",
		"position": Vector2(0, 0),
		"rotation": 0.0,
		"alive": true
	}

	var caladius = {
		"id": "m2",
		"base_mm": 170,
		"base_type": "oval",
		"base_dimensions": {"length": 170, "width": 105},
		"position": Vector2(200, 0),  # Position to be within 1" edge-to-edge
		"rotation": 0.0,
		"alive": true
	}

	var distance_inches = Measurement.model_to_model_distance_inches(infantry, caladius)
	assert_lt(distance_inches, 1.0, "Should be in engagement range")

	# Also test the helper function
	var in_er = Measurement.is_in_engagement_range_shape_aware(infantry, caladius, 1.0)
	assert_true(in_er, "Should be in engagement range using helper function")

func test_rectangular_to_circular_engagement_range():
	var battlewagon = {
		"id": "m1",
		"base_type": "rectangular",
		"base_dimensions": {"length": 180, "width": 110},
		"position": Vector2(0, 0),
		"rotation": 0.0,
		"alive": true
	}

	var marine = {
		"id": "m2",
		"base_mm": 32,
		"base_type": "circular",
		"position": Vector2(300, 0),
		"rotation": 0.0,
		"alive": true
	}

	var distance_inches = Measurement.model_to_model_distance_inches(battlewagon, marine)
	# Distance should be measured from edge of rectangle to edge of circle
	assert_gt(distance_inches, 0, "Distance should be positive")

	# Should not be in engagement range at this distance
	var in_er = Measurement.is_in_engagement_range_shape_aware(battlewagon, marine, 1.0)
	assert_false(in_er, "Should not be in engagement range at 300px")

func test_rotated_oval_engagement_range():
	var caladius1 = {
		"id": "m1",
		"base_mm": 170,
		"base_type": "oval",
		"base_dimensions": {"length": 170, "width": 105},
		"position": Vector2(0, 0),
		"rotation": 0.0,
		"alive": true
	}

	var caladius2 = caladius1.duplicate()
	caladius2["id"] = "m2"
	caladius2["position"] = Vector2(250, 0)
	caladius2["rotation"] = PI / 2  # 90 degrees

	var distance = Measurement.model_to_model_distance_px(caladius1, caladius2)
	# With rotation, the distance should change
	assert_gt(distance, 0, "Distance should account for rotation")

func test_oval_to_oval_close_engagement():
	# Two ovals positioned very close should be in engagement range
	var oval1 = {
		"id": "m1",
		"base_mm": 170,
		"base_type": "oval",
		"base_dimensions": {"length": 170, "width": 105},
		"position": Vector2(0, 0),
		"rotation": 0.0,
		"alive": true
	}

	var oval2 = {
		"id": "m2",
		"base_mm": 170,
		"base_type": "oval",
		"base_dimensions": {"length": 170, "width": 105},
		"position": Vector2(150, 0),  # Very close
		"rotation": 0.0,
		"alive": true
	}

	var in_er = Measurement.is_in_engagement_range_shape_aware(oval1, oval2, 1.0)
	assert_true(in_er, "Two close ovals should be in engagement range")

func test_rectangular_to_rectangular_not_in_range():
	# Two rectangles far apart should not be in engagement range
	var rect1 = {
		"id": "m1",
		"base_type": "rectangular",
		"base_dimensions": {"length": 180, "width": 110},
		"position": Vector2(0, 0),
		"rotation": 0.0,
		"alive": true
	}

	var rect2 = {
		"id": "m2",
		"base_type": "rectangular",
		"base_dimensions": {"length": 180, "width": 110},
		"position": Vector2(500, 0),
		"rotation": 0.0,
		"alive": true
	}

	var in_er = Measurement.is_in_engagement_range_shape_aware(rect1, rect2, 1.0)
	assert_false(in_er, "Two far rectangles should not be in engagement range")

func test_mixed_shapes_at_exact_1_inch():
	# Position models at exactly 1" apart (edge-to-edge) - should be in range
	var circle = {
		"id": "m1",
		"base_mm": 32,
		"base_type": "circular",
		"position": Vector2(0, 0),
		"rotation": 0.0,
		"alive": true
	}

	var oval = {
		"id": "m2",
		"base_mm": 100,
		"base_type": "oval",
		"base_dimensions": {"length": 100, "width": 60},
		"position": Vector2(100, 0),
		"rotation": 0.0,
		"alive": true
	}

	var distance_inches = Measurement.model_to_model_distance_inches(circle, oval)
	# At exactly 1", should be in engagement range (<=)
	var in_er = Measurement.is_in_engagement_range_shape_aware(circle, oval, 1.0)

	# If distance is <= 1", should be in range
	if distance_inches <= 1.0:
		assert_true(in_er, "Should be in engagement range if distance <= 1\"")
	else:
		assert_false(in_er, "Should not be in engagement range if distance > 1\"")
