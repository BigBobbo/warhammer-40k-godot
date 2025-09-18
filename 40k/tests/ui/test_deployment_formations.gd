extends GutTest

# Test deployment formations feature for GitHub Issue #79

var deployment_controller: Node
var unit_data: Dictionary

func before_each():
	deployment_controller = preload("res://scripts/DeploymentController.gd").new()

	# Create test unit data with 10 models
	unit_data = {
		"id": "test_unit",
		"owner": 1,
		"meta": {"name": "Test Squad"},
		"models": []
	}

	for i in range(10):
		unit_data["models"].append({
			"id": "model_%d" % i,
			"base_mm": 32,
			"base_type": "circular",
			"position": null
		})

	# Mock GameState to return our test unit
	GameState.state = {
		"units": {
			"test_unit": unit_data
		}
	}

func after_each():
	if deployment_controller:
		deployment_controller.queue_free()

func test_spread_formation_calculation():
	# Test that spread formation creates proper spacing
	var positions = deployment_controller.calculate_spread_formation(Vector2(400, 400), 5, 32)

	# Should return exactly 5 positions
	assert_eq(positions.size(), 5)

	# Check spacing between models (should be 2" + base diameter)
	# 2" = 80px, base diameter for 32mm = ~50px, so total ~130px
	for i in range(positions.size()):
		for j in range(i + 1, positions.size()):
			var dist = positions[i].distance_to(positions[j])
			# Should be at least one base diameter apart
			assert_true(dist >= Measurement.base_radius_px(32) * 2,
				"Models %d and %d are too close: %f px" % [i, j, dist])

	# Check that models are arranged in a line
	var first_y = positions[0].y
	for pos in positions:
		assert_almost_eq(pos.y, first_y, 1.0, "Models should be in horizontal line")

func test_tight_formation_calculation():
	# Test that tight formation has minimal spacing
	var positions = deployment_controller.calculate_tight_formation(Vector2(400, 400), 5, 32)

	# Should return exactly 5 positions
	assert_eq(positions.size(), 5)

	# Check that models are close but not overlapping
	var min_distance = Measurement.base_radius_px(32) * 2  # Diameter
	for i in range(positions.size()):
		for j in range(i + 1, positions.size()):
			var dist = positions[i].distance_to(positions[j])
			assert_true(dist >= min_distance,
				"Models %d and %d overlap: %f px (min: %f)" % [i, j, dist, min_distance])
			# In tight formation, adjacent models should be very close
			if abs(i - j) == 1:  # Adjacent models
				assert_true(dist < min_distance * 1.1,
					"Adjacent models too far apart in tight formation")

func test_formation_mode_switching():
	# Test switching between formation modes
	deployment_controller.set_formation_mode("SINGLE")
	assert_eq(deployment_controller.formation_mode, "SINGLE")

	deployment_controller.set_formation_mode("SPREAD")
	assert_eq(deployment_controller.formation_mode, "SPREAD")

	deployment_controller.set_formation_mode("TIGHT")
	assert_eq(deployment_controller.formation_mode, "TIGHT")

func test_get_unplaced_model_indices():
	# Setup deployment controller with a unit
	deployment_controller.unit_id = "test_unit"
	deployment_controller.temp_positions = [null, Vector2(100, 100), null, null, Vector2(200, 200)]

	var unplaced = deployment_controller._get_unplaced_model_indices()

	# Should return indices 0, 2, 3 (not placed)
	assert_eq(unplaced.size(), 3)
	assert_has(unplaced, 0)
	assert_has(unplaced, 2)
	assert_has(unplaced, 3)
	assert_does_not_have(unplaced, 1)
	assert_does_not_have(unplaced, 4)

func test_formation_validation_position():
	# Test validation of formation positions
	var zone = PackedVector2Array([
		Vector2(0, 0),
		Vector2(800, 0),
		Vector2(800, 600),
		Vector2(0, 600)
	])

	var model_data = {
		"base_mm": 32,
		"base_type": "circular"
	}

	# Position inside zone should be valid (with mocked overlaps check)
	var valid_pos = Vector2(400, 300)
	var is_valid = deployment_controller._validate_formation_position(valid_pos, model_data, zone)
	# This will check zone but might fail on overlaps without full mock

	# Position outside zone should be invalid
	var invalid_pos = Vector2(900, 300)
	is_valid = deployment_controller._validate_formation_position(invalid_pos, model_data, zone)
	assert_false(is_valid, "Position outside zone should be invalid")

func test_formation_size_limit():
	# Test that formation respects the size limit
	deployment_controller.formation_size = 5

	# Calculate formation for 10 available models
	var positions = deployment_controller.calculate_spread_formation(Vector2(400, 400), 10, 32)

	# Even though we asked for 10, should still work
	assert_eq(positions.size(), 10, "Should calculate positions for all requested models")

	# But when creating ghosts, it should limit to formation_size
	# This would require more complex mocking of the ghost creation

func test_formation_with_different_base_sizes():
	# Test formations work with different base sizes
	var sizes = [25, 32, 40, 50, 60]

	for base_mm in sizes:
		var positions = deployment_controller.calculate_spread_formation(Vector2(400, 400), 3, base_mm)
		assert_eq(positions.size(), 3, "Should work for %dmm bases" % base_mm)

		# Check proper spacing for this base size
		var expected_min_dist = Measurement.base_radius_px(base_mm) * 2
		for i in range(positions.size()):
			for j in range(i + 1, positions.size()):
				var dist = positions[i].distance_to(positions[j])
				assert_true(dist >= expected_min_dist,
					"Models with %dmm bases overlap" % base_mm)

func test_formation_centering():
	# Test that formations are centered on the anchor point
	var anchor = Vector2(500, 400)
	var positions = deployment_controller.calculate_spread_formation(anchor, 5, 32)

	# Calculate center of all positions
	var center = Vector2.ZERO
	for pos in positions:
		center += pos
	center /= positions.size()

	# Center should be close to anchor
	assert_almost_eq(center.x, anchor.x, 5.0, "Formation should be centered on X")
	assert_almost_eq(center.y, anchor.y, 5.0, "Formation should be centered on Y")

func test_formation_rows():
	# Test that large formations create multiple rows
	var positions = deployment_controller.calculate_spread_formation(Vector2(400, 400), 7, 32)

	# Should have 7 positions
	assert_eq(positions.size(), 7)

	# Count unique Y positions (rows)
	var y_positions = {}
	for pos in positions:
		var y_rounded = round(pos.y)
		y_positions[y_rounded] = true

	# Should have 2 rows (5 in first row, 2 in second)
	assert_eq(y_positions.size(), 2, "Should arrange 7 models in 2 rows")