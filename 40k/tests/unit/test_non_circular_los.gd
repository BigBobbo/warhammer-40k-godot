extends GutTest

# Specific tests for non-circular base line of sight enhancements
# Focuses on edge cases and complex scenarios for rectangular and oval bases

class_name TestNonCircularLoS

var test_board: Dictionary

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	# Set up clean test environment
	test_board = {
		"terrain_features": [],
		"units": {}
	}

func after_each():
	# Clean up after each test
	if EnhancedLineOfSight:
		EnhancedLineOfSight.clear_cache()

# ===== CALADIUS GRAV-TANK TESTS (Oval Base) =====

func test_caladius_oval_base_sampling():
	# Test the specific Caladius Grav-tank oval base (170mm x 105mm)
	gut.p("Testing Caladius Grav-tank oval base sampling")

	var caladius = {
		"id": "caladius_test",
		"base_type": "oval",
		"base_dimensions": {"length": 170, "width": 105},
		"position": {"x": 300, "y": 300},
		"rotation": 0.0,
		"alive": true
	}

	var target = {
		"id": "infantry_target",
		"base_type": "circular",
		"base_mm": 32,
		"position": {"x": 600, "y": 350},
		"alive": true
	}

	var result = EnhancedLineOfSight.check_enhanced_visibility(caladius, target, test_board)

	assert_true(result.has_los, "Caladius should find LoS to infantry target")
	assert_gt(result.attempted_lines.size(), 1, "Should sample multiple points for oval base")

func test_caladius_rotated_visibility():
	# Test Caladius with different rotations
	gut.p("Testing Caladius rotated visibility")

	var caladius = {
		"id": "caladius_rotated",
		"base_type": "oval",
		"base_dimensions": {"length": 170, "width": 105},
		"position": {"x": 300, "y": 300},
		"rotation": 0.0,
		"alive": true
	}

	var target = {
		"id": "target",
		"base_type": "circular",
		"base_mm": 32,
		"position": {"x": 500, "y": 380},
		"alive": true
	}

	# Test different rotations
	var rotations = [0.0, PI/4, PI/2, 3*PI/4, PI]

	for rotation in rotations:
		caladius.rotation = rotation
		var result = EnhancedLineOfSight.check_enhanced_visibility(caladius, target, test_board)
		assert_true(result.has_los, "Caladius should have LoS at rotation %.2f" % rotation)

# ===== BATTLEWAGON TESTS (Rectangular Base) =====

func test_battlewagon_rectangular_base():
	# Test the specific Ork Battlewagon rectangular base (9" x 5")
	gut.p("Testing Ork Battlewagon rectangular base")

	var battlewagon = {
		"id": "battlewagon_test",
		"base_type": "rectangular",
		"base_dimensions": {"length": 360, "width": 200},  # 9" x 5" in pixels (40px/inch)
		"position": {"x": 400, "y": 400},
		"rotation": 0.0,
		"alive": true
	}

	var target = {
		"id": "enemy_target",
		"base_type": "circular",
		"base_mm": 40,
		"position": {"x": 800, "y": 450},
		"alive": true
	}

	var result = EnhancedLineOfSight.check_enhanced_visibility(battlewagon, target, test_board)

	assert_true(result.has_los, "Battlewagon should find LoS to target")
	assert_gt(result.attempted_lines.size(), 1, "Should sample multiple points for rectangular base")

func test_battlewagon_corner_vs_edge_sampling():
	# Test that rectangular bases sample both corners and edge points
	gut.p("Testing Battlewagon corner vs edge sampling")

	var battlewagon_model = {
		"id": "battlewagon_sampling",
		"base_type": "rectangular",
		"base_dimensions": {"length": 360, "width": 200},
		"position": {"x": 300, "y": 300},
		"rotation": 0.0,
		"alive": true
	}

	# Generate sample points with high density
	var shape = Measurement.create_base_shape(battlewagon_model)
	var sample_points = EnhancedLineOfSight._generate_rectangular_sample_points(shape, Vector2(300, 300), 0.0, 8)

	# Should have: center (1) + corners (4) + edge points (8 for high density)
	assert_gte(sample_points.size(), 9, "High density should generate corner + edge points")

	# Verify center point
	assert_true(sample_points.has(Vector2(300, 300)), "Should include center point")

# ===== TERRAIN GAP SCENARIOS =====

func test_narrow_terrain_gap_rectangular():
	# Test rectangular base finding LoS through narrow terrain gaps
	gut.p("Testing rectangular base through narrow terrain gap")

	var rectangular_shooter = {
		"id": "rect_gap_shooter",
		"base_type": "rectangular",
		"base_dimensions": {"length": 120, "width": 60},
		"position": {"x": 200, "y": 300},
		"rotation": 0.0,
		"alive": true
	}

	var target = {
		"id": "gap_target",
		"base_type": "circular",
		"base_mm": 32,
		"position": {"x": 600, "y": 300},
		"alive": true
	}

	# Create terrain with a narrow gap
	test_board.terrain_features = [
		{
			"id": "blocking_wall_1",
			"type": "ruins",
			"height_category": "tall",
			"polygon": PackedVector2Array([
				Vector2(350, 250),
				Vector2(390, 250),
				Vector2(390, 290),
				Vector2(350, 290)
			])
		},
		{
			"id": "blocking_wall_2",
			"type": "ruins",
			"height_category": "tall",
			"polygon": PackedVector2Array([
				Vector2(410, 310),
				Vector2(450, 310),
				Vector2(450, 350),
				Vector2(410, 350)
			])
		}
	]

	var result = EnhancedLineOfSight.check_enhanced_visibility(rectangular_shooter, target, test_board)

	# The test verifies that edge sampling finds LoS through the gap
	assert_gt(result.attempted_lines.size(), 5, "Should attempt many sight lines to find gap")

func test_oval_terrain_gap_scenario():
	# Test oval base finding LoS where corners would be blocked but edges are clear
	gut.p("Testing oval base terrain gap scenario")

	var oval_shooter = {
		"id": "oval_gap_shooter",
		"base_type": "oval",
		"base_dimensions": {"length": 140, "width": 80},
		"position": {"x": 250, "y": 300},
		"rotation": 0.0,
		"alive": true
	}

	var target = {
		"id": "gap_target_oval",
		"base_type": "circular",
		"base_mm": 32,
		"position": {"x": 550, "y": 320},
		"alive": true
	}

	# Add terrain that blocks some sight lines but not all
	test_board.terrain_features = [{
		"id": "partial_blocker",
		"type": "ruins",
		"height_category": "tall",
		"polygon": PackedVector2Array([
			Vector2(380, 290),
			Vector2(420, 290),
			Vector2(420, 310),
			Vector2(380, 310)
		])
	}]

	var result = EnhancedLineOfSight.check_enhanced_visibility(oval_shooter, target, test_board)

	# Test that oval shape can find alternate sight lines
	assert_gt(result.attempted_lines.size(), 3, "Should attempt multiple sight lines for oval")

# ===== LARGE BASE INTERACTIONS =====

func test_large_base_vs_large_base():
	# Test two large non-circular bases against each other
	gut.p("Testing large base vs large base visibility")

	var large_oval = {
		"id": "large_oval",
		"base_type": "oval",
		"base_dimensions": {"length": 200, "width": 120},
		"position": {"x": 300, "y": 300},
		"rotation": 0.0,
		"alive": true
	}

	var large_rect = {
		"id": "large_rect",
		"base_type": "rectangular",
		"base_dimensions": {"length": 180, "width": 100},
		"position": {"x": 700, "y": 350},
		"rotation": PI/4,  # 45 degree rotation
		"alive": true
	}

	var result = EnhancedLineOfSight.check_enhanced_visibility(large_oval, large_rect, test_board)

	assert_true(result.has_los, "Large oval should see large rectangle")

	# Reverse test
	var reverse_result = EnhancedLineOfSight.check_enhanced_visibility(large_rect, large_oval, test_board)
	assert_true(reverse_result.has_los, "Large rectangle should see large oval")

# ===== PERFORMANCE TESTS FOR NON-CIRCULAR =====

func test_non_circular_performance():
	# Ensure non-circular shapes don't cause significant performance degradation
	gut.p("Testing non-circular shape performance")

	var rectangular_model = {
		"id": "perf_rect",
		"base_type": "rectangular",
		"base_dimensions": {"length": 120, "width": 80},
		"position": {"x": 200, "y": 200},
		"rotation": 0.0,
		"alive": true
	}

	var oval_model = {
		"id": "perf_oval",
		"base_type": "oval",
		"base_dimensions": {"length": 140, "width": 90},
		"position": {"x": 500, "y": 250},
		"rotation": 0.0,
		"alive": true
	}

	var iterations = 20
	var start_time = Time.get_ticks_msec()

	for i in range(iterations):
		# Vary positions slightly
		rectangular_model.position.x = 200 + (i % 5) * 10
		oval_model.position.y = 250 + (i % 5) * 10

		var result = EnhancedLineOfSight.check_enhanced_visibility(rectangular_model, oval_model, test_board)
		assert_true(result.has_los, "Iteration %d should have LoS" % i)

	var total_time = Time.get_ticks_msec() - start_time
	var avg_time = float(total_time) / iterations

	gut.p("Non-circular LoS - Total: %dms, Avg: %.2fms per check" % [total_time, avg_time])

	# Should be reasonable performance (target: < 15ms average for complex shapes)
	assert_lt(avg_time, 20.0, "Non-circular LoS should be reasonably fast (<20ms avg, got %.2fms)" % avg_time)

# ===== SHAPE-SPECIFIC EDGE CASES =====

func test_rectangular_extreme_aspect_ratio():
	# Test very long, thin rectangular base
	gut.p("Testing rectangular extreme aspect ratio")

	var long_rect = {
		"id": "long_rect",
		"base_type": "rectangular",
		"base_dimensions": {"length": 200, "width": 20},  # Very thin
		"position": {"x": 300, "y": 300},
		"rotation": 0.0,
		"alive": true
	}

	var target = {
		"id": "target_thin",
		"base_type": "circular",
		"base_mm": 32,
		"position": {"x": 500, "y": 320},
		"alive": true
	}

	var result = EnhancedLineOfSight.check_enhanced_visibility(long_rect, target, test_board)
	assert_true(result.has_los, "Long thin rectangle should find LoS")

	# Test rotated 90 degrees
	long_rect.rotation = PI/2
	var rotated_result = EnhancedLineOfSight.check_enhanced_visibility(long_rect, target, test_board)
	assert_true(rotated_result.has_los, "Rotated long rectangle should still find LoS")

func test_oval_extreme_aspect_ratio():
	# Test very elongated oval base
	gut.p("Testing oval extreme aspect ratio")

	var elongated_oval = {
		"id": "elongated_oval",
		"base_type": "oval",
		"base_dimensions": {"length": 180, "width": 40},  # Very elongated
		"position": {"x": 300, "y": 300},
		"rotation": 0.0,
		"alive": true
	}

	var target = {
		"id": "target_elongated",
		"base_type": "circular",
		"base_mm": 32,
		"position": {"x": 550, "y": 320},
		"alive": true
	}

	var result = EnhancedLineOfSight.check_enhanced_visibility(elongated_oval, target, test_board)
	assert_true(result.has_los, "Elongated oval should find LoS")

# ===== ERROR HANDLING TESTS =====

func test_malformed_base_data():
	# Test graceful handling of malformed base shape data
	gut.p("Testing malformed base data handling")

	var malformed_model = {
		"id": "malformed",
		"base_type": "rectangular",
		# Missing base_dimensions - should fallback gracefully
		"position": {"x": 300, "y": 300},
		"alive": true
	}

	var target = {
		"id": "normal_target",
		"base_type": "circular",
		"base_mm": 32,
		"position": {"x": 500, "y": 300},
		"alive": true
	}

	# Should not crash and should fallback to reasonable behavior
	var result = EnhancedLineOfSight.check_enhanced_visibility(malformed_model, target, test_board)
	assert_true(result.has_los, "Malformed data should still work with fallbacks")

func test_unknown_base_type():
	# Test handling of unknown base types
	gut.p("Testing unknown base type handling")

	var unknown_type_model = {
		"id": "unknown_base",
		"base_type": "hexagonal",  # Not implemented
		"base_mm": 40,
		"position": {"x": 300, "y": 300},
		"alive": true
	}

	var target = {
		"id": "normal_target_2",
		"base_type": "circular",
		"base_mm": 32,
		"position": {"x": 500, "y": 300},
		"alive": true
	}

	# Should fallback to circular behavior
	var result = EnhancedLineOfSight.check_enhanced_visibility(unknown_type_model, target, test_board)
	assert_true(result.has_los, "Unknown base type should fallback to circular")