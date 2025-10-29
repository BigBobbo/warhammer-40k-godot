extends GutTest

# Unit tests for MeasuringTapeManager functionality

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	# Clear any existing measurements before each test
	if MeasuringTapeManager:
		MeasuringTapeManager.clear_all_measurements()
		MeasuringTapeManager.set_save_persistence(false)

func test_start_measurement():
	# Test starting a new measurement
	var start_pos = Vector2(100, 100)
	
	MeasuringTapeManager.start_measurement(start_pos)
	
	assert_true(MeasuringTapeManager.is_measuring, "Should be in measuring state")
	assert_eq(MeasuringTapeManager.measurement_start, start_pos, "Start position should be set")
	assert_false(MeasuringTapeManager.current_preview.is_empty(), "Preview should exist")
	assert_eq(MeasuringTapeManager.current_preview.from, start_pos, "Preview from should match start")

func test_update_measurement():
	# Test updating measurement while dragging
	var start_pos = Vector2(100, 100)
	var current_pos = Vector2(200, 100)
	
	MeasuringTapeManager.start_measurement(start_pos)
	MeasuringTapeManager.update_measurement(current_pos)
	
	assert_eq(MeasuringTapeManager.current_preview.to, current_pos, "Preview to should update")
	
	# Check distance calculation (100px = 2.5 inches at 40px per inch)
	var expected_distance = 2.5
	assert_almost_eq(MeasuringTapeManager.current_preview.distance, expected_distance, 0.1, 
		"Distance should be calculated correctly")

func test_complete_measurement():
	# Test completing a measurement
	var start_pos = Vector2(100, 100)
	var end_pos = Vector2(340, 100)  # 240px = 6 inches
	
	MeasuringTapeManager.start_measurement(start_pos)
	MeasuringTapeManager.complete_measurement(end_pos)
	
	assert_false(MeasuringTapeManager.is_measuring, "Should not be measuring after completion")
	assert_eq(MeasuringTapeManager.measurements.size(), 1, "Should have one measurement")
	
	var measurement = MeasuringTapeManager.measurements[0]
	assert_eq(measurement.from, start_pos, "Measurement from should match")
	assert_eq(measurement.to, end_pos, "Measurement to should match")
	assert_almost_eq(measurement.distance, 6.0, 0.1, "Distance should be 6 inches")

func test_cancel_measurement():
	# Test cancelling a measurement
	var start_pos = Vector2(100, 100)
	
	MeasuringTapeManager.start_measurement(start_pos)
	MeasuringTapeManager.cancel_measurement()
	
	assert_false(MeasuringTapeManager.is_measuring, "Should not be measuring after cancel")
	assert_eq(MeasuringTapeManager.measurements.size(), 0, "Should have no measurements")
	assert_true(MeasuringTapeManager.current_preview.is_empty(), "Preview should be cleared")

func test_clear_all_measurements():
	# Test clearing all measurements
	var positions = [
		[Vector2(100, 100), Vector2(200, 100)],
		[Vector2(300, 300), Vector2(400, 400)],
		[Vector2(0, 0), Vector2(100, 0)]
	]
	
	# Add multiple measurements
	for pos_pair in positions:
		MeasuringTapeManager.start_measurement(pos_pair[0])
		MeasuringTapeManager.complete_measurement(pos_pair[1])
	
	assert_eq(MeasuringTapeManager.measurements.size(), 3, "Should have 3 measurements")
	
	MeasuringTapeManager.clear_all_measurements()
	
	assert_eq(MeasuringTapeManager.measurements.size(), 0, "Should have no measurements after clear")

func test_measurement_limit():
	# Test that there's a maximum measurement limit
	assert_true(MeasuringTapeManager.can_add_measurement(), "Should be able to add measurement initially")
	
	# Add measurements up to the limit
	for i in range(MeasuringTapeManager.MAX_MEASUREMENTS):
		var start = Vector2(i * 10, 0)
		var end = Vector2(i * 10 + 50, 0)
		MeasuringTapeManager.start_measurement(start)
		MeasuringTapeManager.complete_measurement(end)
	
	assert_eq(MeasuringTapeManager.measurements.size(), MeasuringTapeManager.MAX_MEASUREMENTS,
		"Should have maximum measurements")
	assert_false(MeasuringTapeManager.can_add_measurement(), "Should not be able to add more")

func test_save_data_generation():
	# Test save data generation
	MeasuringTapeManager.set_save_persistence(true)
	
	var start_pos = Vector2(100, 100)
	var end_pos = Vector2(200, 200)
	
	MeasuringTapeManager.start_measurement(start_pos)
	MeasuringTapeManager.complete_measurement(end_pos)
	
	var save_data = MeasuringTapeManager.get_save_data()
	
	assert_false(save_data.is_empty(), "Save data should not be empty")
	assert_eq(save_data.size(), 1, "Should have one measurement in save data")
	
	var saved_measurement = save_data[0]
	assert_eq(saved_measurement.from.x, start_pos.x, "Saved from.x should match")
	assert_eq(saved_measurement.from.y, start_pos.y, "Saved from.y should match")
	assert_eq(saved_measurement.to.x, end_pos.x, "Saved to.x should match")
	assert_eq(saved_measurement.to.y, end_pos.y, "Saved to.y should match")

func test_save_data_when_disabled():
	# Test that save data is empty when persistence is disabled
	MeasuringTapeManager.set_save_persistence(false)
	
	MeasuringTapeManager.start_measurement(Vector2(100, 100))
	MeasuringTapeManager.complete_measurement(Vector2(200, 200))
	
	var save_data = MeasuringTapeManager.get_save_data()
	
	assert_true(save_data.is_empty(), "Save data should be empty when persistence is disabled")

func test_load_save_data():
	# Test loading save data
	var test_data = [
		{
			"from": {"x": 50, "y": 50},
			"to": {"x": 150, "y": 150},
			"distance": 3.5
		},
		{
			"from": {"x": 200, "y": 200},
			"to": {"x": 300, "y": 200},
			"distance": 2.5
		}
	]
	
	MeasuringTapeManager.load_save_data(test_data)
	
	assert_eq(MeasuringTapeManager.measurements.size(), 2, "Should have loaded 2 measurements")
	
	var first = MeasuringTapeManager.measurements[0]
	assert_eq(first.from, Vector2(50, 50), "First measurement from should match")
	assert_eq(first.to, Vector2(150, 150), "First measurement to should match")
	assert_eq(first.distance, 3.5, "First measurement distance should match")
	
	var second = MeasuringTapeManager.measurements[1]
	assert_eq(second.from, Vector2(200, 200), "Second measurement from should match")
	assert_eq(second.to, Vector2(300, 200), "Second measurement to should match")
	assert_eq(second.distance, 2.5, "Second measurement distance should match")

func test_distance_calculation_accuracy():
	# Test various distance calculations
	var test_cases = [
		# [from, to, expected_inches]
		[Vector2(0, 0), Vector2(40, 0), 1.0],  # 40px = 1 inch
		[Vector2(0, 0), Vector2(240, 0), 6.0],  # 240px = 6 inches
		[Vector2(0, 0), Vector2(480, 0), 12.0],  # 480px = 12 inches
		[Vector2(0, 0), Vector2(960, 0), 24.0],  # 960px = 24 inches
		[Vector2(100, 100), Vector2(100, 340), 6.0],  # Vertical 240px = 6 inches
		[Vector2(0, 0), Vector2(30, 40), 1.25],  # Diagonal: sqrt(900+1600) = 50px = 1.25 inches
	]
	
	for test_case in test_cases:
		var from_pos = test_case[0]
		var to_pos = test_case[1]
		var expected = test_case[2]
		
		MeasuringTapeManager.start_measurement(from_pos)
		MeasuringTapeManager.complete_measurement(to_pos)
		
		var measurement = MeasuringTapeManager.measurements.back()
		assert_almost_eq(measurement.distance, expected, 0.01, 
			"Distance from %s to %s should be %.2f inches" % [from_pos, to_pos, expected])
		
		MeasuringTapeManager.clear_all_measurements()

func test_measurement_count():
	# Test get_measurement_count
	assert_eq(MeasuringTapeManager.get_measurement_count(), 0, "Should start with 0 measurements")
	
	MeasuringTapeManager.start_measurement(Vector2(0, 0))
	MeasuringTapeManager.complete_measurement(Vector2(100, 0))
	
	assert_eq(MeasuringTapeManager.get_measurement_count(), 1, "Should have 1 measurement")
	
	MeasuringTapeManager.start_measurement(Vector2(200, 200))
	MeasuringTapeManager.complete_measurement(Vector2(300, 300))
	
	assert_eq(MeasuringTapeManager.get_measurement_count(), 2, "Should have 2 measurements")
	
	MeasuringTapeManager.clear_all_measurements()
	
	assert_eq(MeasuringTapeManager.get_measurement_count(), 0, "Should have 0 after clear")