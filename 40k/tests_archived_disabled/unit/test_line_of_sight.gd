extends "res://addons/gut/test.gd"

# Unit tests for Line of Sight functionality

var los_calculator: LineOfSightCalculator
var test_terrain: Array

func before_each() -> void:
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	los_calculator = LineOfSightCalculator.new()
	test_terrain = []

func after_each() -> void:
	test_terrain.clear()

func test_clear_line_of_sight_with_no_terrain() -> void:
	# Test that LoS works when there's no terrain
	var from = Vector2(100, 100)
	var to = Vector2(500, 500)

	var has_los = LineOfSightCalculator.check_line_of_sight(from, to, [])

	assert_true(has_los, "Should have clear line of sight with no terrain")

func test_line_of_sight_blocked_by_tall_terrain() -> void:
	# Test that tall terrain blocks LoS
	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	# Create tall terrain between the two points
	test_terrain = [{
		"id": "terrain_1",
		"height_category": "tall",
		"polygon": PackedVector2Array([
			Vector2(200, 50),
			Vector2(400, 50),
			Vector2(400, 150),
			Vector2(200, 150)
		])
	}]

	var has_los = LineOfSightCalculator.check_line_of_sight(from, to, test_terrain)

	assert_false(has_los, "Should not have line of sight through tall terrain")

func test_line_of_sight_not_blocked_by_low_terrain() -> void:
	# Test that low terrain does not block LoS
	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	# Create low terrain between the two points
	test_terrain = [{
		"id": "terrain_2",
		"height_category": "low",
		"polygon": PackedVector2Array([
			Vector2(200, 50),
			Vector2(400, 50),
			Vector2(400, 150),
			Vector2(200, 150)
		])
	}]

	var has_los = LineOfSightCalculator.check_line_of_sight(from, to, test_terrain)

	assert_true(has_los, "Should have line of sight over low terrain")

func test_line_of_sight_from_inside_terrain() -> void:
	# Test that models inside terrain can see out
	var from = Vector2(300, 100)  # Inside terrain
	var to = Vector2(500, 100)    # Outside terrain

	test_terrain = [{
		"id": "terrain_3",
		"height_category": "tall",
		"polygon": PackedVector2Array([
			Vector2(200, 50),
			Vector2(400, 50),
			Vector2(400, 150),
			Vector2(200, 150)
		])
	}]

	var has_los = LineOfSightCalculator.check_line_of_sight(from, to, test_terrain)

	assert_true(has_los, "Models inside terrain should be able to see out")

func test_visibility_grid_calculation() -> void:
	# Test grid visibility calculation
	var models = [{
		"position": Vector2(100, 100),
		"base_mm": 32
	}]

	var grid = LineOfSightCalculator.calculate_visibility_grid(models, 50, 10.0)

	assert_not_null(grid, "Grid should not be null")
	assert_gt(grid.size(), 0, "Grid should have visible points")

	# Check that points near the model are visible
	var found_nearby = false
	for point in grid:
		if point.distance_to(Vector2(100, 100)) < 100:
			found_nearby = true
			break

	assert_true(found_nearby, "Should have visible points near the model")

func test_segment_intersects_polygon() -> void:
	# Test polygon intersection
	var polygon = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(100, 100),
		Vector2(0, 100)
	])

	# Line that crosses the polygon
	var crosses = LineOfSightCalculator._segment_intersects_polygon(
		Vector2(-50, 50),
		Vector2(150, 50),
		polygon
	)
	assert_true(crosses, "Line should intersect polygon")

	# Line that doesn't cross the polygon
	var misses = LineOfSightCalculator._segment_intersects_polygon(
		Vector2(-50, -50),
		Vector2(150, -50),
		polygon
	)
	assert_false(misses, "Line should not intersect polygon")

func test_point_in_polygon() -> void:
	# Test point in polygon detection
	var polygon = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(100, 100),
		Vector2(0, 100)
	])

	# Point inside polygon
	var inside = LineOfSightCalculator._point_in_polygon(Vector2(50, 50), polygon)
	assert_true(inside, "Point should be inside polygon")

	# Point outside polygon
	var outside = LineOfSightCalculator._point_in_polygon(Vector2(150, 150), polygon)
	assert_false(outside, "Point should be outside polygon")

func test_batch_visibility_check() -> void:
	# Test batch visibility checking
	var from = Vector2(100, 100)
	var targets = [
		Vector2(200, 100),
		Vector2(300, 100),
		Vector2(400, 100)
	]

	var results = LineOfSightCalculator.check_visibility_batch(from, targets, [])

	assert_eq(results.size(), 3, "Should have results for all targets")
	for result in results:
		assert_true(result, "All targets should be visible with no terrain")

func test_area_visibility_percentage() -> void:
	# Test area visibility calculation
	var from = Vector2(100, 100)
	var area_center = Vector2(300, 100)
	var area_radius = 50.0

	var visibility = LineOfSightCalculator.calculate_area_visibility(
		from, area_center, area_radius, 8
	)

	assert_gte(visibility, 0.0, "Visibility should be >= 0")
	assert_lte(visibility, 1.0, "Visibility should be <= 1")

	# With no terrain, should be fully visible
	assert_eq(visibility, 1.0, "Area should be fully visible with no terrain")

func test_adaptive_grid_size() -> void:
	# Test adaptive grid size calculation
	var small_bounds = Rect2(0, 0, 100, 100)
	var large_bounds = Rect2(0, 0, 2000, 2000)

	var small_grid = LineOfSightCalculator._calculate_adaptive_grid_size(small_bounds, 20)
	var large_grid = LineOfSightCalculator._calculate_adaptive_grid_size(large_bounds, 20)

	assert_eq(small_grid, 20, "Small area should use base grid size")
	assert_gt(large_grid, 20, "Large area should use larger grid size for performance")

func test_los_manager_input_handling() -> void:
	# Test that LineOfSightManager responds to input
	pending("Requires scene tree and input simulation")

func test_los_visual_rendering() -> void:
	# Test that LineOfSightVisual renders correctly
	pending("Requires scene tree and rendering context")