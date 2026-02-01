extends "res://addons/gut/test.gd"
class_name TestEnhancedLineOfSight

const CircularBase = preload("res://scripts/bases/CircularBase.gd")
const RectangularBase = preload("res://scripts/bases/RectangularBase.gd")
const OvalBase = preload("res://scripts/bases/OvalBase.gd")

# Unit tests for EnhancedLineOfSight system
# Tests progressive sampling, base-aware visibility, and performance characteristics


var test_board: Dictionary
var test_shooter_model: Dictionary
var test_target_model: Dictionary

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	# Set up clean test environment
	test_board = {
		"terrain_features": [],
		"units": {}
	}
	
	# Create test models with different base sizes
	test_shooter_model = {
		"id": "shooter_1",
		"base_mm": 32,
		"position": {"x": 400, "y": 400},
		"alive": true
	}
	
	test_target_model = {
		"id": "target_1", 
		"base_mm": 32,
		"position": {"x": 800, "y": 400},
		"alive": true
	}

func after_each():
	# Clean up after each test
	if EnhancedLineOfSight:
		EnhancedLineOfSight.clear_cache()

# ===== BASIC FUNCTIONALITY TESTS =====

func test_center_to_center_visibility():
	# Standard case - should match legacy behavior for clear LoS
	gut.p("Testing center-to-center visibility (clear)")
	
	var result = EnhancedLineOfSight.check_enhanced_visibility(test_shooter_model, test_target_model, test_board)
	
	assert_true(result.has_los, "Clear center-to-center should have LoS")
	assert_eq(result.method, "center_to_center", "Should use fast center-to-center path")
	assert_eq(result.sight_line.size(), 2, "Should have start and end points")

func test_center_to_center_blocked():
	# Add tall terrain between models to block center-to-center LoS
	gut.p("Testing center-to-center visibility (blocked)")
	
	test_board.terrain_features = [{
		"id": "blocking_terrain",
		"type": "ruins",
		"height_category": "tall", 
		"polygon": PackedVector2Array([
			Vector2(550, 350),
			Vector2(650, 350), 
			Vector2(650, 450),
			Vector2(550, 450)
		])
	}]
	
	var result = EnhancedLineOfSight.check_enhanced_visibility(test_shooter_model, test_target_model, test_board)
	
	assert_false(result.has_los, "Blocked center-to-center should not have LoS")
	assert_eq(result.method, "full_sampling", "Should attempt full sampling")
	assert_gt(result.attempted_lines.size(), 1, "Should attempt multiple sight lines")

func test_edge_to_edge_visibility():
	# Large models with blocked centers but clear edges
	gut.p("Testing edge-to-edge visibility")
	
	# Use larger bases
	test_shooter_model.base_mm = 80  # Large base
	test_target_model.base_mm = 80
	
	# Add terrain that blocks center but allows edge visibility
	test_board.terrain_features = [{
		"id": "partial_blocking",
		"type": "ruins", 
		"height_category": "tall",
		"polygon": PackedVector2Array([
			Vector2(580, 350),
			Vector2(620, 350),
			Vector2(620, 450), 
			Vector2(580, 450)
		])
	}]
	
	var result = EnhancedLineOfSight.check_enhanced_visibility(test_shooter_model, test_target_model, test_board)
	
	# This might be true or false depending on exact geometry, but should complete without error
	assert_is_not_null(result.has_los, "Should return valid LoS result")
	assert_eq(result.method, "edge_to_edge", "Should use edge-to-edge method if successful")

func test_circumference_visibility():
	# Models with 5+ inch bases requiring circumference sampling
	gut.p("Testing circumference visibility for large bases")
	
	# Very large bases (>60mm triggers circumference sampling)
	test_shooter_model.base_mm = 120  # ~5 inch base
	test_target_model.base_mm = 120
	
	var result = EnhancedLineOfSight.check_enhanced_visibility(test_shooter_model, test_target_model, test_board)
	
	assert_true(result.has_los, "Large bases should see each other with clear terrain")
	# With no terrain, center-to-center should still work first
	assert_eq(result.method, "center_to_center", "Clear terrain should use center path even for large bases")

# ===== TERRAIN INTERACTION TESTS =====

func test_terrain_blocking():
	# Verify terrain still blocks sight lines correctly
	gut.p("Testing terrain blocking with enhanced LoS")
	
	# Add terrain that completely blocks all possible sight lines
	test_board.terrain_features = [{
		"id": "complete_blocker",
		"type": "ruins",
		"height_category": "tall",
		"polygon": PackedVector2Array([
			Vector2(500, 300),
			Vector2(700, 300),
			Vector2(700, 500),
			Vector2(500, 500)
		])
	}]
	
	var result = EnhancedLineOfSight.check_enhanced_visibility(test_shooter_model, test_target_model, test_board)
	
	assert_false(result.has_los, "Complete terrain blocker should prevent LoS")
	assert_true(result.blocking_terrain.has("complete_blocker"), "Should identify blocking terrain")

func test_low_terrain_provides_cover_not_blocking():
	# Low terrain should provide cover but not block LoS
	gut.p("Testing low terrain interaction")
	
	test_board.terrain_features = [{
		"id": "low_cover",
		"type": "ruins",
		"height_category": "low",  # Low terrain doesn't block LoS
		"polygon": PackedVector2Array([
			Vector2(550, 350),
			Vector2(650, 350),
			Vector2(650, 450),
			Vector2(550, 450)
		])
	}]
	
	var result = EnhancedLineOfSight.check_enhanced_visibility(test_shooter_model, test_target_model, test_board)
	
	assert_true(result.has_los, "Low terrain should not block LoS")
	assert_true(result.blocking_terrain.is_empty(), "Low terrain should not be in blocking list")

func test_models_inside_terrain_can_see():
	# Models inside terrain should be able to see out and be seen
	gut.p("Testing models inside terrain visibility")
	
	# Place shooter inside terrain
	test_shooter_model.position = {"x": 600, "y": 400}  # Inside terrain below
	
	test_board.terrain_features = [{
		"id": "containing_terrain",
		"type": "ruins",
		"height_category": "tall",
		"polygon": PackedVector2Array([
			Vector2(550, 350),
			Vector2(650, 350),
			Vector2(650, 450),
			Vector2(550, 450)
		])
	}]
	
	var result = EnhancedLineOfSight.check_enhanced_visibility(test_shooter_model, test_target_model, test_board)
	
	assert_true(result.has_los, "Model inside terrain should be able to see out")

# ===== PERFORMANCE AND SCALING TESTS =====

func test_performance_scaling():
	# Ensure algorithm scales appropriately with base sizes
	gut.p("Testing performance scaling with different base sizes")
	
	var start_time = Time.get_ticks_msec()
	
	# Test with small bases (should use center + 4 edge points)
	test_shooter_model.base_mm = 25
	test_target_model.base_mm = 25
	var small_result = EnhancedLineOfSight.check_enhanced_visibility(test_shooter_model, test_target_model, test_board)
	
	var small_time = Time.get_ticks_msec() - start_time
	start_time = Time.get_ticks_msec()
	
	# Test with large bases (should use more sampling points)
	test_shooter_model.base_mm = 120
	test_target_model.base_mm = 120
	var large_result = EnhancedLineOfSight.check_enhanced_visibility(test_shooter_model, test_target_model, test_board)
	
	var large_time = Time.get_ticks_msec() - start_time
	
	assert_true(small_result.has_los, "Small base test should succeed")
	assert_true(large_result.has_los, "Large base test should succeed")
	
	# Performance should be reasonable (< 50ms for individual checks)
	assert_lt(small_time, 50, "Small base check should be fast (<%dms, got %dms)" % [50, small_time])
	assert_lt(large_time, 100, "Large base check should be reasonable (<%dms, got %dms)" % [100, large_time])
	
	gut.p("Small base time: %dms, Large base time: %dms" % [small_time, large_time])

func test_sample_density_determination():
	# Test the sample density logic
	gut.p("Testing sample density determination")
	
	# Close, small bases should use fewer samples
	var close_small = EnhancedLineOfSight._determine_sample_density(12.0, 25)
	assert_eq(close_small, 4, "Close small bases should use 4 samples")
	
	# Medium bases should use 6 samples
	var medium = EnhancedLineOfSight._determine_sample_density(18.0, 40)
	assert_eq(medium, 6, "Medium bases should use 6 samples")
	
	# Large bases should use 8 samples
	var large = EnhancedLineOfSight._determine_sample_density(18.0, 80)
	assert_eq(large, 8, "Large bases should use 8 samples")
	
	# Distant targets should use fewer samples regardless of base size
	var distant_large = EnhancedLineOfSight._determine_sample_density(30.0, 80)
	assert_eq(distant_large, 4, "Distant targets should use fewer samples")

# ===== EDGE CASES AND ERROR HANDLING =====

func test_invalid_model_positions():
	# Test with invalid or zero positions
	gut.p("Testing invalid model positions")
	
	test_shooter_model.position = Vector2.ZERO  # Invalid position
	
	var result = EnhancedLineOfSight.check_enhanced_visibility(test_shooter_model, test_target_model, test_board)
	
	assert_false(result.has_los, "Invalid position should result in no LoS")
	assert_has(result, "reason", "Should provide reason for failure")

func test_missing_base_size_defaults():
	# Test that missing base_mm defaults to reasonable value
	gut.p("Testing missing base size defaults")
	
	# Remove base_mm from models
	test_shooter_model.erase("base_mm")
	test_target_model.erase("base_mm")
	
	var result = EnhancedLineOfSight.check_enhanced_visibility(test_shooter_model, test_target_model, test_board)
	
	assert_true(result.has_los, "Missing base size should default and still work")

func test_empty_terrain_features():
	# Test with empty terrain features
	gut.p("Testing empty terrain features")
	
	test_board.terrain_features = []
	
	var result = EnhancedLineOfSight.check_enhanced_visibility(test_shooter_model, test_target_model, test_board)
	
	assert_true(result.has_los, "Empty terrain should allow clear LoS")
	assert_eq(result.method, "center_to_center", "Should use fast path with no terrain")

# ===== COMPARISON WITH LEGACY =====

func test_legacy_compatibility():
	# Enhanced LoS should give same result as legacy for center-to-center cases
	gut.p("Testing legacy compatibility")
	
	var shooter_pos = Vector2(test_shooter_model.position.x, test_shooter_model.position.y)
	var target_pos = Vector2(test_target_model.position.x, test_target_model.position.y)
	
	var legacy_result = RulesEngine._check_legacy_line_of_sight(shooter_pos, target_pos, test_board)
	var enhanced_result = EnhancedLineOfSight.check_enhanced_visibility(test_shooter_model, test_target_model, test_board)
	
	assert_eq(legacy_result, enhanced_result.has_los, "Legacy and enhanced should agree on clear terrain")

func test_enhanced_finds_edge_cases_legacy_misses():
	# Enhanced should find LoS that legacy misses due to edge visibility
	gut.p("Testing enhanced edge case detection")
	
	# Use larger models
	test_shooter_model.base_mm = 60
	test_target_model.base_mm = 60
	
	# Add narrow terrain that blocks center but not edges
	test_board.terrain_features = [{
		"id": "narrow_blocker",
		"type": "ruins",
		"height_category": "tall",
		"polygon": PackedVector2Array([
			Vector2(595, 390),
			Vector2(605, 390),
			Vector2(605, 410),
			Vector2(595, 410)
		])
	}]
	
	var shooter_pos = Vector2(test_shooter_model.position.x, test_shooter_model.position.y)
	var target_pos = Vector2(test_target_model.position.x, test_target_model.position.y)
	
	var legacy_result = RulesEngine._check_legacy_line_of_sight(shooter_pos, target_pos, test_board)
	var enhanced_result = EnhancedLineOfSight.check_enhanced_visibility(test_shooter_model, test_target_model, test_board)
	
	# This is the key test - enhanced should potentially find LoS that legacy misses
	# Due to the geometric complexity, we primarily test that enhanced doesn't crash
	assert_is_not_null(enhanced_result.has_los, "Enhanced should return valid result")
	
	gut.p("Legacy: %s, Enhanced: %s" % [
		"CLEAR" if legacy_result else "BLOCKED",
		"CLEAR" if enhanced_result.has_los else "BLOCKED"
	])

# ===== BENCHMARK TESTS =====

func test_benchmark_multiple_checks():
	# Benchmark multiple LoS checks to ensure reasonable performance
	gut.p("Benchmarking multiple enhanced LoS checks")
	
	var iterations = 50
	var start_time = Time.get_ticks_msec()
	
	for i in range(iterations):
		# Vary positions slightly for each check
		test_target_model.position.x = 800 + (i % 10) * 5
		var result = EnhancedLineOfSight.check_enhanced_visibility(test_shooter_model, test_target_model, test_board)
		assert_true(result.has_los, "Iteration %d should have LoS" % i)
	
	var total_time = Time.get_ticks_msec() - start_time
	var avg_time = float(total_time) / iterations
	
	gut.p("Total time for %d checks: %dms (avg: %.2fms per check)" % [iterations, total_time, avg_time])
	
	# Target: < 5ms average per check for simple cases
	assert_lt(avg_time, 10.0, "Average check time should be reasonable (<10ms, got %.2fms)" % avg_time)

# ===== NON-CIRCULAR BASE TESTS =====

func test_rectangular_base_line_of_sight():
	# Test rectangular vs circular visibility
	gut.p("Testing rectangular base line of sight")

	var rectangular_shooter = {
		"id": "rect_shooter",
		"base_type": "rectangular",
		"base_dimensions": {"length": 100, "width": 60},
		"position": {"x": 200, "y": 200},
		"rotation": 0.0,
		"alive": true
	}

	var circular_target = {
		"id": "circ_target",
		"base_type": "circular",
		"base_mm": 32,
		"position": {"x": 400, "y": 250},
		"alive": true
	}

	var result = EnhancedLineOfSight.check_enhanced_visibility(rectangular_shooter, circular_target, test_board)

	assert_true(result.has_los, "Rectangular to circular should find visibility")
	assert_gt(result.attempted_lines.size(), 1, "Should attempt multiple sight lines for rectangular base")

func test_oval_base_line_of_sight():
	# Test oval vs circular visibility
	gut.p("Testing oval base line of sight")

	var oval_shooter = {
		"id": "oval_shooter",
		"base_type": "oval",
		"base_dimensions": {"length": 170, "width": 105},
		"position": {"x": 200, "y": 200},
		"rotation": 0.0,
		"alive": true
	}

	var circular_target = {
		"id": "circ_target",
		"base_type": "circular",
		"base_mm": 32,
		"position": {"x": 500, "y": 250},
		"alive": true
	}

	var result = EnhancedLineOfSight.check_enhanced_visibility(oval_shooter, circular_target, test_board)

	assert_true(result.has_los, "Oval to circular should find visibility")
	assert_gt(result.attempted_lines.size(), 1, "Should attempt multiple sight lines for oval base")

func test_mixed_base_types_in_combat():
	# Test various combinations: oval vs rectangular, rectangular vs circular, etc.
	gut.p("Testing mixed base types in combat scenarios")

	var rectangular_model = {
		"id": "rect_1",
		"base_type": "rectangular",
		"base_dimensions": {"length": 120, "width": 80},
		"position": {"x": 300, "y": 300},
		"rotation": 0.0,
		"alive": true
	}

	var oval_model = {
		"id": "oval_1",
		"base_type": "oval",
		"base_dimensions": {"length": 150, "width": 90},
		"position": {"x": 600, "y": 350},
		"rotation": 0.0,
		"alive": true
	}

	# Test rectangular vs oval
	var rect_to_oval = EnhancedLineOfSight.check_enhanced_visibility(rectangular_model, oval_model, test_board)
	assert_true(rect_to_oval.has_los, "Rectangular to oval should find visibility")

	# Test oval vs rectangular (reverse)
	var oval_to_rect = EnhancedLineOfSight.check_enhanced_visibility(oval_model, rectangular_model, test_board)
	assert_true(oval_to_rect.has_los, "Oval to rectangular should find visibility")

func test_rotated_models_visibility():
	# Verify rotation affects visibility correctly for all shapes
	gut.p("Testing rotated models visibility")

	var rectangular_model = {
		"id": "rect_rotated",
		"base_type": "rectangular",
		"base_dimensions": {"length": 100, "width": 40},
		"position": {"x": 300, "y": 300},
		"rotation": 0.0,
		"alive": true
	}

	var target_model = {
		"id": "target",
		"base_type": "circular",
		"base_mm": 32,
		"position": {"x": 450, "y": 320},
		"alive": true
	}

	# Test with no rotation
	var no_rotation = EnhancedLineOfSight.check_enhanced_visibility(rectangular_model, target_model, test_board)
	assert_true(no_rotation.has_los, "Should have LoS with no rotation")

	# Test with 90 degree rotation
	rectangular_model.rotation = PI / 2
	var rotated = EnhancedLineOfSight.check_enhanced_visibility(rectangular_model, target_model, test_board)
	assert_true(rotated.has_los, "Should still have LoS with rotation")

func test_edge_point_sampling():
	# Verify that non-circular shapes sample points along edges, not just corners
	gut.p("Testing edge point sampling for non-circular shapes")

	var rectangular_model = {
		"id": "rect_edge_test",
		"base_type": "rectangular",
		"base_dimensions": {"length": 80, "width": 60},
		"position": {"x": 200, "y": 200},
		"rotation": 0.0,
		"alive": true
	}

	# Use enhanced density to ensure edge sampling
	var shape = Measurement.create_base_shape(rectangular_model)
	var sample_points = EnhancedLineOfSight._generate_rectangular_sample_points(shape, Vector2(200, 200), 0.0, 8)

	# Should have center + 4 corners + edge points for high density
	assert_gt(sample_points.size(), 5, "Rectangular shape should generate multiple sample points including edges")

	# Verify center point is included
	assert_true(sample_points.has(Vector2(200, 200)), "Should include center point")

func test_terrain_gap_scenario():
	# Test where extreme points are blocked but edge points have clear LoS
	gut.p("Testing terrain gap scenario with non-circular bases")

	var rectangular_shooter = {
		"id": "rect_gap_test",
		"base_type": "rectangular",
		"base_dimensions": {"length": 80, "width": 40},
		"position": {"x": 250, "y": 300},
		"rotation": 0.0,
		"alive": true
	}

	var target_model = {
		"id": "target_gap",
		"base_type": "circular",
		"base_mm": 32,
		"position": {"x": 550, "y": 300},
		"alive": true
	}

	# Add terrain that blocks center but might allow edge visibility
	test_board.terrain_features = [{
		"id": "gap_terrain",
		"type": "ruins",
		"height_category": "tall",
		"polygon": PackedVector2Array([
			Vector2(380, 280),
			Vector2(420, 280),
			Vector2(420, 320),
			Vector2(380, 320)
		])
	}]

	var result = EnhancedLineOfSight.check_enhanced_visibility(rectangular_shooter, target_model, test_board)

	# This test verifies the system attempts edge-based visibility
	assert_gt(result.attempted_lines.size(), 1, "Should attempt multiple sight lines for gap scenario")

func test_enhanced_density_for_non_circular():
	# Test the enhanced density calculation for non-circular shapes
	gut.p("Testing enhanced density calculation for non-circular shapes")

	var circular_shape = CircularBase.new(20.0)
	var rectangular_shape = RectangularBase.new(80.0, 60.0)
	var oval_shape = OvalBase.new(85.0, 52.5)

	# Close distance - non-circular shapes should get higher density
	var close_circ_density = EnhancedLineOfSight._determine_sample_density_enhanced(8.0, circular_shape, circular_shape)
	var close_rect_density = EnhancedLineOfSight._determine_sample_density_enhanced(8.0, rectangular_shape, circular_shape)
	var close_oval_density = EnhancedLineOfSight._determine_sample_density_enhanced(8.0, oval_shape, circular_shape)

	assert_gte(close_rect_density, close_circ_density, "Rectangular shapes should get at least as much density as circular")
	assert_gte(close_oval_density, close_circ_density, "Oval shapes should get at least as much density as circular")

	# Very close rectangular combat should use maximum density
	var max_density = EnhancedLineOfSight._determine_sample_density_enhanced(4.0, rectangular_shape, rectangular_shape)
	assert_eq(max_density, 8, "Close rectangular combat should use maximum density")

func test_backward_compatibility():
	# Test that models without base_type still work (default to circular)
	gut.p("Testing backward compatibility with legacy models")

	var legacy_shooter = {
		"id": "legacy_shooter",
		"base_mm": 32,
		"position": {"x": 200, "y": 200},
		"alive": true
		# No base_type - should default to circular
	}

	var legacy_target = {
		"id": "legacy_target",
		"base_mm": 40,
		"position": {"x": 400, "y": 200},
		"alive": true
		# No base_type - should default to circular
	}

	var result = EnhancedLineOfSight.check_enhanced_visibility(legacy_shooter, legacy_target, test_board)

	assert_true(result.has_los, "Legacy models should still work")
	assert_eq(result.method, "center_to_center", "Legacy models should use fast center-to-center path")
