extends GutTest

# Unit tests for Measurement autoload
# Tests unit conversion and distance calculation functionality

var test_measurement: Node

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	test_measurement = preload("res://autoloads/Measurement.gd").new()

func after_each():
	if test_measurement:
		test_measurement.queue_free()

# Test constants
func test_constants():
	assert_eq(40.0, test_measurement.PX_PER_INCH, "PX_PER_INCH should be 40.0")
	assert_eq(25.4, test_measurement.MM_PER_INCH, "MM_PER_INCH should be 25.4")

# Test inches to pixels conversion
func test_inches_to_px():
	assert_eq(0.0, test_measurement.inches_to_px(0.0), "0 inches should be 0 pixels")
	assert_eq(40.0, test_measurement.inches_to_px(1.0), "1 inch should be 40 pixels")
	assert_eq(80.0, test_measurement.inches_to_px(2.0), "2 inches should be 80 pixels")
	assert_eq(240.0, test_measurement.inches_to_px(6.0), "6 inches should be 240 pixels")
	
	# Test fractional inches
	assert_almost_eq(20.0, test_measurement.inches_to_px(0.5), 0.01, "0.5 inches should be 20 pixels")
	assert_almost_eq(100.0, test_measurement.inches_to_px(2.5), 0.01, "2.5 inches should be 100 pixels")

# Test pixels to inches conversion
func test_px_to_inches():
	assert_eq(0.0, test_measurement.px_to_inches(0.0), "0 pixels should be 0 inches")
	assert_eq(1.0, test_measurement.px_to_inches(40.0), "40 pixels should be 1 inch")
	assert_eq(2.0, test_measurement.px_to_inches(80.0), "80 pixels should be 2 inches")
	assert_eq(6.0, test_measurement.px_to_inches(240.0), "240 pixels should be 6 inches")
	
	# Test fractional pixels
	assert_almost_eq(0.5, test_measurement.px_to_inches(20.0), 0.01, "20 pixels should be 0.5 inches")
	assert_almost_eq(2.5, test_measurement.px_to_inches(100.0), 0.01, "100 pixels should be 2.5 inches")

# Test mm to pixels conversion
func test_mm_to_px():
	assert_eq(0.0, test_measurement.mm_to_px(0.0), "0 mm should be 0 pixels")
	
	# 25.4 mm = 1 inch = 40 pixels
	assert_almost_eq(40.0, test_measurement.mm_to_px(25.4), 0.01, "25.4 mm should be 40 pixels")
	
	# 50.8 mm = 2 inches = 80 pixels
	assert_almost_eq(80.0, test_measurement.mm_to_px(50.8), 0.01, "50.8 mm should be 80 pixels")
	
	# Standard base sizes
	assert_almost_eq(39.37, test_measurement.mm_to_px(25.0), 0.1, "25mm base should convert correctly")
	assert_almost_eq(50.39, test_measurement.mm_to_px(32.0), 0.1, "32mm base should convert correctly")

# Test pixels to mm conversion
func test_px_to_mm():
	assert_eq(0.0, test_measurement.px_to_mm(0.0), "0 pixels should be 0 mm")
	
	# 40 pixels = 1 inch = 25.4 mm
	assert_almost_eq(25.4, test_measurement.px_to_mm(40.0), 0.01, "40 pixels should be 25.4 mm")
	
	# 80 pixels = 2 inches = 50.8 mm
	assert_almost_eq(50.8, test_measurement.px_to_mm(80.0), 0.01, "80 pixels should be 50.8 mm")

# Test base radius calculation
func test_base_radius_px():
	# 25mm base should have radius of 12.5mm
	var radius_25mm = test_measurement.base_radius_px(25)
	var expected_25mm = test_measurement.mm_to_px(12.5)  # radius = diameter / 2
	assert_almost_eq(expected_25mm, radius_25mm, 0.01, "25mm base radius should be correct")
	
	# 32mm base should have radius of 16mm
	var radius_32mm = test_measurement.base_radius_px(32)
	var expected_32mm = test_measurement.mm_to_px(16.0)  # radius = diameter / 2
	assert_almost_eq(expected_32mm, radius_32mm, 0.01, "32mm base radius should be correct")
	
	# 40mm base should have radius of 20mm
	var radius_40mm = test_measurement.base_radius_px(40)
	var expected_40mm = test_measurement.mm_to_px(20.0)  # radius = diameter / 2
	assert_almost_eq(expected_40mm, radius_40mm, 0.01, "40mm base radius should be correct")

# Test distance calculations
func test_distance_inches():
	var pos1 = Vector2(0, 0)
	var pos2 = Vector2(40, 0)  # 40 pixels = 1 inch
	
	assert_almost_eq(1.0, test_measurement.distance_inches(pos1, pos2), 0.01, "40 pixel distance should be 1 inch")
	
	var pos3 = Vector2(0, 0)
	var pos4 = Vector2(0, 240)  # 240 pixels = 6 inches
	
	assert_almost_eq(6.0, test_measurement.distance_inches(pos3, pos4), 0.01, "240 pixel distance should be 6 inches")
	
	# Diagonal distance (Pythagorean theorem)
	var pos5 = Vector2(0, 0)
	var pos6 = Vector2(30, 40)  # 3-4-5 triangle scaled by 10, so 50 pixels = 1.25 inches
	
	assert_almost_eq(1.25, test_measurement.distance_inches(pos5, pos6), 0.01, "50 pixel diagonal should be 1.25 inches")

func test_distance_px():
	var pos1 = Vector2(0, 0)
	var pos2 = Vector2(40, 0)
	
	assert_eq(40.0, test_measurement.distance_px(pos1, pos2), "Distance should be 40 pixels")
	
	var pos3 = Vector2(0, 0)
	var pos4 = Vector2(0, 240)
	
	assert_eq(240.0, test_measurement.distance_px(pos3, pos4), "Distance should be 240 pixels")
	
	# Diagonal distance
	var pos5 = Vector2(0, 0)
	var pos6 = Vector2(3, 4)  # 3-4-5 triangle, distance = 5
	
	assert_eq(5.0, test_measurement.distance_px(pos5, pos6), "Distance should be 5 pixels")

# Test polyline distance calculations
func test_distance_polyline_px():
	# Empty array
	assert_eq(0.0, test_measurement.distance_polyline_px([]), "Empty array should return 0")
	
	# Single point
	assert_eq(0.0, test_measurement.distance_polyline_px([Vector2(0, 0)]), "Single point should return 0")
	
	# Two points
	var two_points = [Vector2(0, 0), Vector2(40, 0)]
	assert_eq(40.0, test_measurement.distance_polyline_px(two_points), "Two points should return distance between them")
	
	# Three points forming an L shape
	var l_shape = [Vector2(0, 0), Vector2(40, 0), Vector2(40, 30)]
	assert_eq(70.0, test_measurement.distance_polyline_px(l_shape), "L shape should be 40 + 30 = 70 pixels")
	
	# Square path
	var square = [Vector2(0, 0), Vector2(40, 0), Vector2(40, 40), Vector2(0, 40), Vector2(0, 0)]
	assert_eq(160.0, test_measurement.distance_polyline_px(square), "Square path should be 40 * 4 = 160 pixels")

func test_distance_polyline_inches():
	var points = [Vector2(0, 0), Vector2(40, 0), Vector2(40, 40)]  # 40 + 40 = 80 pixels = 2 inches
	assert_almost_eq(2.0, test_measurement.distance_polyline_inches(points), 0.01, "Should be 2 inches")

func test_distance_polyline_with_invalid_points():
	# Mix of valid and invalid points
	var mixed_points = [Vector2(0, 0), "invalid", Vector2(40, 0)]
	
	# Should handle invalid points gracefully
	var result = test_measurement.distance_polyline_px(mixed_points)
	assert_gte(result, 0.0, "Should return non-negative result even with invalid points")

# Test edge-to-edge distance calculations
func test_edge_to_edge_distance_px():
	var pos1 = Vector2(0, 0)
	var radius1 = 10.0
	var pos2 = Vector2(50, 0)
	var radius2 = 15.0
	
	# Center distance = 50, radii = 10 + 15 = 25, edge distance = 50 - 25 = 25
	assert_eq(25.0, test_measurement.edge_to_edge_distance_px(pos1, radius1, pos2, radius2), "Edge distance should be 25 pixels")
	
	# Overlapping circles
	var close_pos2 = Vector2(20, 0)  # Center distance = 20, radii = 25, so edge distance should be 0
	assert_eq(0.0, test_measurement.edge_to_edge_distance_px(pos1, radius1, close_pos2, radius2), "Overlapping circles should have 0 edge distance")
	
	# Very close circles (result should be clamped to 0)
	var very_close_pos2 = Vector2(10, 0)  # Center distance = 10, radii = 25, so would be negative
	assert_eq(0.0, test_measurement.edge_to_edge_distance_px(pos1, radius1, very_close_pos2, radius2), "Very close circles should be clamped to 0")

func test_edge_to_edge_distance_inches():
	var pos1 = Vector2(0, 0)
	var pos2 = Vector2(120, 0)  # 120 pixels = 3 inches
	
	# 25mm bases: radius = 12.5mm each
	var distance_25mm = test_measurement.edge_to_edge_distance_inches(pos1, 25, pos2, 25)
	
	# Should be close to 3 inches minus the two radii converted to inches
	var expected = 3.0 - 2 * (12.5 / 25.4)  # 3 inches - 2 radii in inches
	assert_almost_eq(expected, distance_25mm, 0.1, "25mm base edge distance should be correct")
	
	# 32mm bases
	var distance_32mm = test_measurement.edge_to_edge_distance_inches(pos1, 32, pos2, 32)
	var expected_32mm = 3.0 - 2 * (16.0 / 25.4)  # 3 inches - 2 radii in inches
	assert_almost_eq(expected_32mm, distance_32mm, 0.1, "32mm base edge distance should be correct")

# Test conversion accuracy and consistency
func test_conversion_round_trip_accuracy():
	var test_values = [0.0, 0.5, 1.0, 2.5, 6.0, 12.0, 24.0]
	
	for inches in test_values:
		var pixels = test_measurement.inches_to_px(inches)
		var back_to_inches = test_measurement.px_to_inches(pixels)
		assert_almost_eq(inches, back_to_inches, 0.0001, "Round trip inches->px->inches should be accurate for " + str(inches))
	
	for mm in [0.0, 25.0, 25.4, 32.0, 50.8, 76.2]:
		var pixels = test_measurement.mm_to_px(mm)
		var back_to_mm = test_measurement.px_to_mm(pixels)
		assert_almost_eq(mm, back_to_mm, 0.0001, "Round trip mm->px->mm should be accurate for " + str(mm))

# Test standard 40k measurements
func test_standard_40k_measurements():
	# 1 inch movement should be exactly 40 pixels
	assert_eq(40.0, test_measurement.inches_to_px(1.0), "1 inch movement should be 40 pixels")
	
	# 6 inch standard move should be 240 pixels
	assert_eq(240.0, test_measurement.inches_to_px(6.0), "6 inch move should be 240 pixels")
	
	# 12 inch charge range should be 480 pixels
	assert_eq(480.0, test_measurement.inches_to_px(12.0), "12 inch charge should be 480 pixels")
	
	# 24 inch weapon range should be 960 pixels
	assert_eq(960.0, test_measurement.inches_to_px(24.0), "24 inch range should be 960 pixels")

# Test common base sizes used in 40k
func test_common_base_sizes():
	# Infantry base (25mm)
	var infantry_radius = test_measurement.base_radius_px(25)
	assert_gt(infantry_radius, 0, "Infantry base should have positive radius")
	assert_almost_eq(19.69, infantry_radius, 0.1, "25mm base radius should be ~19.69 pixels")
	
	# Space Marine base (32mm) 
	var marine_radius = test_measurement.base_radius_px(32)
	assert_gt(marine_radius, 0, "Marine base should have positive radius")
	assert_almost_eq(25.20, marine_radius, 0.1, "32mm base radius should be ~25.20 pixels")
	
	# Large base (40mm)
	var large_radius = test_measurement.base_radius_px(40)
	assert_gt(large_radius, 0, "Large base should have positive radius")
	assert_almost_eq(31.50, large_radius, 0.1, "40mm base radius should be ~31.50 pixels")

# Test edge cases and error conditions
func test_negative_values():
	# Distance calculations should handle negative coordinates
	var pos1 = Vector2(-20, -30)
	var pos2 = Vector2(20, 30)
	var distance = test_measurement.distance_px(pos1, pos2)
	assert_gt(distance, 0, "Distance should be positive even with negative coordinates")
	
	# Base radius with 0 should return 0
	assert_eq(0.0, test_measurement.base_radius_px(0), "0mm base should have 0 radius")

func test_zero_values():
	assert_eq(0.0, test_measurement.inches_to_px(0.0), "0 inches should be 0 pixels")
	assert_eq(0.0, test_measurement.px_to_inches(0.0), "0 pixels should be 0 inches")
	assert_eq(0.0, test_measurement.mm_to_px(0.0), "0 mm should be 0 pixels")
	assert_eq(0.0, test_measurement.px_to_mm(0.0), "0 pixels should be 0 mm")

# Test method existence
func test_all_methods_exist():
	var required_methods = [
		"inches_to_px",
		"px_to_inches", 
		"mm_to_px",
		"px_to_mm",
		"base_radius_px",
		"distance_inches",
		"distance_px",
		"distance_polyline_px",
		"distance_polyline_inches",
		"edge_to_edge_distance_px",
		"edge_to_edge_distance_inches"
	]
	
	for method_name in required_methods:
		assert_true(test_measurement.has_method(method_name), "Should have method: " + method_name)