extends "res://addons/gut/test.gd"

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

func test_battlewagon_has_rectangular_base():
	var army = ArmyListManager.load_army_list("orks", 2)
	var battlewagon = army.units.get("U_BATTLEWAGON_G")
	assert_not_null(battlewagon)

	var model = battlewagon.models[0]
	assert_eq(model.base_type, "rectangular")
	assert_eq(model.base_dimensions.length, 180)
	assert_eq(model.base_dimensions.width, 110)

func test_caladius_has_oval_base():
	var army = ArmyListManager.load_army_list("adeptus_custodes", 1)
	var caladius = army.units.get("U_CALADIUS_GRAV-TANK_E")
	assert_not_null(caladius)

	var model = caladius.models[0]
	assert_eq(model.base_type, "oval")
	assert_eq(model.base_dimensions.length, 170)
	assert_eq(model.base_dimensions.width, 105)

func test_token_visual_renders_correct_shape():
	var model_rect = {
		"base_mm": 180,
		"base_type": "rectangular",
		"base_dimensions": {"length": 180, "width": 110}
	}

	var token = preload("res://scripts/TokenVisual.gd").new()
	token.set_model_data(model_rect)

	assert_not_null(token.base_shape)
	assert_eq(token.base_shape.get_type(), "rectangular")

func test_ghost_visual_renders_correct_shape():
	var model_oval = {
		"base_mm": 170,
		"base_type": "oval",
		"base_dimensions": {"length": 170, "width": 105}
	}

	var ghost = preload("res://scripts/GhostVisual.gd").new()
	ghost.set_model_data(model_oval)

	assert_not_null(ghost.base_shape)
	assert_eq(ghost.base_shape.get_type(), "oval")

func test_distance_calculation_with_shapes():
	var battlewagon = {
		"position": Vector2(0, 0),
		"rotation": 0,
		"base_type": "rectangular",
		"base_dimensions": {"length": 180, "width": 110},
		"base_mm": 180
	}

	var infantry = {
		"position": Vector2(300, 0),
		"rotation": 0,
		"base_mm": 32,
		"base_type": "circular"
	}

	var distance = Measurement.model_to_model_distance_inches(battlewagon, infantry)
	# Should measure from edge of rectangle to edge of circle
	assert_gt(distance, 0)

	# More specific test: distance should be approximately the center-to-center distance
	# minus half the rectangle length (90mm) minus the infantry radius (16mm)
	# 300px - 90mm_in_px - 16mm_in_px converted to inches
	var expected_min = Measurement.px_to_inches(300 - Measurement.mm_to_px(90) - Measurement.mm_to_px(16))
	assert_gte(distance, expected_min - 0.1)  # Allow small tolerance

func test_models_overlap_with_shapes():
	var rect_model = {
		"position": Vector2(0, 0),
		"rotation": 0,
		"base_type": "rectangular",
		"base_dimensions": {"length": 180, "width": 110},
		"base_mm": 180
	}

	var oval_model = {
		"position": Vector2(100, 0),  # Overlapping position
		"rotation": 0,
		"base_type": "oval",
		"base_dimensions": {"length": 170, "width": 105},
		"base_mm": 170
	}

	var far_model = {
		"position": Vector2(500, 0),  # Far away
		"rotation": 0,
		"base_mm": 32,
		"base_type": "circular"
	}

	# Test overlapping models
	assert_true(Measurement.models_overlap(rect_model, oval_model))

	# Test non-overlapping models
	assert_false(Measurement.models_overlap(rect_model, far_model))

func test_measurement_create_base_shape():
	# Test circular base creation
	var circular_model = {
		"base_mm": 32,
		"base_type": "circular"
	}
	var circular_shape = Measurement.create_base_shape(circular_model)
	assert_not_null(circular_shape)
	assert_eq(circular_shape.get_type(), "circular")

	# Test rectangular base creation
	var rect_model = {
		"base_mm": 180,
		"base_type": "rectangular",
		"base_dimensions": {"length": 180, "width": 110}
	}
	var rect_shape = Measurement.create_base_shape(rect_model)
	assert_not_null(rect_shape)
	assert_eq(rect_shape.get_type(), "rectangular")

	# Test oval base creation
	var oval_model = {
		"base_mm": 170,
		"base_type": "oval",
		"base_dimensions": {"length": 170, "width": 105}
	}
	var oval_shape = Measurement.create_base_shape(oval_model)
	assert_not_null(oval_shape)
	assert_eq(oval_shape.get_type(), "oval")

	# Test default to circular when type is missing
	var default_model = {
		"base_mm": 50
	}
	var default_shape = Measurement.create_base_shape(default_model)
	assert_not_null(default_shape)
	assert_eq(default_shape.get_type(), "circular")