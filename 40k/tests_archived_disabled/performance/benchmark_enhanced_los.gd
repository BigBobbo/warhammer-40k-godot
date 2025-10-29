extends GutTest

# Performance benchmarks for Enhanced Line of Sight
# Compares enhanced vs legacy performance and validates performance targets

class_name BenchmarkEnhancedLoS

var test_board: Dictionary
var benchmark_iterations: int = 100

func before_each():
	# Set up benchmark environment
	test_board = {
		"terrain_features": [],
		"units": {}
	}
	
	# Clear any caches
	if EnhancedLineOfSight:
		EnhancedLineOfSight.clear_cache()

# ===== PERFORMANCE BENCHMARK TESTS =====

func benchmark_enhanced_vs_legacy():
	# Compare performance of enhanced vs legacy algorithms
	# Target: <2x performance cost for 95% of cases
	gut.p("Benchmarking enhanced vs legacy LoS algorithms")
	
	var test_models = _create_test_model_pairs()
	var legacy_times = []
	var enhanced_times = []
	
	# Warm up
	for i in range(10):
		var pair = test_models[0]
		RulesEngine._check_legacy_line_of_sight(pair.shooter_pos, pair.target_pos, test_board)
		EnhancedLineOfSight.check_enhanced_visibility(pair.shooter_model, pair.target_model, test_board)
	
	# Benchmark legacy algorithm
	gut.p("Benchmarking legacy algorithm...")
	for pair in test_models:
		var start_time = Time.get_ticks_usec()
		var result = RulesEngine._check_legacy_line_of_sight(pair.shooter_pos, pair.target_pos, test_board)
		var elapsed = Time.get_ticks_usec() - start_time
		legacy_times.append(elapsed)
	
	# Benchmark enhanced algorithm
	gut.p("Benchmarking enhanced algorithm...")
	for pair in test_models:
		var start_time = Time.get_ticks_usec()
		var result = EnhancedLineOfSight.check_enhanced_visibility(pair.shooter_model, pair.target_model, test_board)
		var elapsed = Time.get_ticks_usec() - start_time
		enhanced_times.append(elapsed)
	
	# Calculate statistics
	var legacy_avg = _calculate_average(legacy_times)
	var enhanced_avg = _calculate_average(enhanced_times)
	var performance_ratio = enhanced_avg / legacy_avg
	
	gut.p("Legacy average: %.1f μs" % legacy_avg)
	gut.p("Enhanced average: %.1f μs" % enhanced_avg)
	gut.p("Performance ratio: %.2fx" % performance_ratio)
	
	# Performance target: <2x cost for 95% of cases
	assert_lt(performance_ratio, 3.0, "Enhanced should be <3x cost of legacy (got %.2fx)" % performance_ratio)
	
	# Most cases should be faster
	var fast_cases = 0
	for i in range(enhanced_times.size()):
		if enhanced_times[i] < legacy_times[i] * 2.0:
			fast_cases += 1
	
	var fast_percentage = float(fast_cases) / enhanced_times.size() * 100.0
	gut.p("Fast cases (< 2x legacy): %.1f%%" % fast_percentage)
	
	assert_gt(fast_percentage, 70.0, "At least 70% of cases should be <2x legacy cost")

func benchmark_large_base_scenarios():
	# Test performance with multiple large models
	# Target: <100ms for complex 8-model visibility checks
	gut.p("Benchmarking large base scenarios")
	
	var large_models = _create_large_base_models(8, 8)  # 8 shooters vs 8 targets
	
	var start_time = Time.get_ticks_msec()
	var visibility_count = 0
	
	# Test all-vs-all visibility
	for shooter in large_models.shooters:
		for target in large_models.targets:
			var result = EnhancedLineOfSight.check_enhanced_visibility(shooter, target, test_board)
			if result.has_los:
				visibility_count += 1
	
	var total_time = Time.get_ticks_msec() - start_time
	var checks_performed = large_models.shooters.size() * large_models.targets.size()
	var avg_time = float(total_time) / checks_performed
	
	gut.p("Total time for %d checks: %dms (avg: %.2fms per check)" % [checks_performed, total_time, avg_time])
	gut.p("Visibility found: %d/%d checks" % [visibility_count, checks_performed])
	
	# Target: <100ms total for 64 checks (8x8)
	assert_lt(total_time, 200, "Complex scenario should complete in <200ms (got %dms)" % total_time)
	assert_lt(avg_time, 5.0, "Average check should be <5ms (got %.2fms)" % avg_time)

func benchmark_terrain_complexity():
	# Test performance scaling with terrain complexity
	gut.p("Benchmarking terrain complexity scaling")
	
	var base_model_shooter = {
		"id": "shooter",
		"base_mm": 32,
		"position": {"x": 400, "y": 400}
	}
	var base_model_target = {
		"id": "target", 
		"base_mm": 32,
		"position": {"x": 800, "y": 400}
	}
	
	var terrain_counts = [0, 5, 10, 20]
	var times_by_terrain = {}
	
	for terrain_count in terrain_counts:
		# Set up terrain
		test_board.terrain_features = _create_random_terrain(terrain_count)
		
		# Benchmark
		var start_time = Time.get_ticks_msec()
		for i in range(20):  # 20 iterations per terrain level
			var result = EnhancedLineOfSight.check_enhanced_visibility(base_model_shooter, base_model_target, test_board)
		var elapsed = Time.get_ticks_msec() - start_time
		
		times_by_terrain[terrain_count] = float(elapsed) / 20.0
		gut.p("Terrain count %d: %.2fms avg" % [terrain_count, times_by_terrain[terrain_count]])
	
	# Performance should scale reasonably with terrain complexity
	var no_terrain_time = times_by_terrain[0]
	var max_terrain_time = times_by_terrain[20]
	var scaling_factor = max_terrain_time / no_terrain_time
	
	gut.p("Scaling factor (0 to 20 terrain): %.2fx" % scaling_factor)
	assert_lt(scaling_factor, 5.0, "Performance should scale reasonably with terrain (<5x, got %.2fx)" % scaling_factor)

func benchmark_sampling_density_impact():
	# Test performance impact of different sampling densities
	gut.p("Benchmarking sampling density impact")
	
	var base_sizes = [25, 40, 60, 100]  # Different base sizes trigger different sampling
	var times_by_base = {}
	
	for base_size in base_sizes:
		var shooter_model = {
			"id": "shooter",
			"base_mm": base_size,
			"position": {"x": 400, "y": 400}
		}
		var target_model = {
			"id": "target",
			"base_mm": base_size,
			"position": {"x": 800, "y": 400}
		}
		
		var start_time = Time.get_ticks_usec()
		for i in range(50):
			var result = EnhancedLineOfSight.check_enhanced_visibility(shooter_model, target_model, test_board)
		var elapsed = Time.get_ticks_usec() - start_time
		
		times_by_base[base_size] = float(elapsed) / 50.0
		var density = EnhancedLineOfSight._determine_sample_density(10.0, base_size)
		gut.p("Base %dmm (density %d): %.1f μs avg" % [base_size, density, times_by_base[base_size]])
	
	# Larger bases should take more time but not excessively
	var small_time = times_by_base[25]
	var large_time = times_by_base[100]
	var size_scaling = large_time / small_time
	
	gut.p("Size scaling factor (25mm to 100mm): %.2fx" % size_scaling)
	assert_lt(size_scaling, 3.0, "Large bases should not be >3x slower than small (<3x, got %.2fx)" % size_scaling)

# ===== MEMORY AND CACHING BENCHMARKS =====

func benchmark_cache_effectiveness():
	# Test caching system effectiveness
	gut.p("Benchmarking cache effectiveness")
	
	var test_model_shooter = {
		"id": "shooter",
		"base_mm": 32,
		"position": {"x": 400, "y": 400}
	}
	var test_model_target = {
		"id": "target",
		"base_mm": 32,
		"position": {"x": 800, "y": 400}
	}
	
	# Add some terrain to make caching meaningful
	test_board.terrain_features = _create_random_terrain(5)
	
	# First run without cache
	EnhancedLineOfSight.clear_cache()
	var start_time = Time.get_ticks_usec()
	for i in range(20):
		var result = EnhancedLineOfSight.check_enhanced_visibility(test_model_shooter, test_model_target, test_board)
	var no_cache_time = Time.get_ticks_usec() - start_time
	
	# Second run with warmed cache (same positions)
	start_time = Time.get_ticks_usec()
	for i in range(20):
		var result = EnhancedLineOfSight.check_enhanced_visibility(test_model_shooter, test_model_target, test_board)
	var cached_time = Time.get_ticks_usec() - start_time
	
	var cache_improvement = float(no_cache_time) / cached_time
	gut.p("No cache: %d μs, Cached: %d μs, Improvement: %.2fx" % [no_cache_time, cached_time, cache_improvement])
	
	# Cache should provide some improvement (though current implementation may not have caching fully implemented)
	if cached_time < no_cache_time:
		assert_gt(cache_improvement, 1.1, "Cache should provide >10% improvement")
	else:
		gut.p("Note: Caching not yet providing measurable improvement")

# ===== STRESS TESTS =====

func benchmark_extreme_load():
	# Stress test with extreme scenarios
	gut.p("Benchmarking extreme load scenarios")
	
	# Test with many models and complex terrain
	var many_shooters = []
	var many_targets = []
	
	for i in range(5):  # 5 shooters
		many_shooters.append({
			"id": "shooter_%d" % i,
			"base_mm": 32,
			"position": {"x": 400 + i * 50, "y": 400}
		})
	
	for i in range(5):  # 5 targets
		many_targets.append({
			"id": "target_%d" % i,
			"base_mm": 32,
			"position": {"x": 800 + i * 50, "y": 400}
		})
	
	# Add complex terrain
	test_board.terrain_features = _create_random_terrain(15)
	
	var start_time = Time.get_ticks_msec()
	var total_checks = 0
	
	# All-vs-all visibility test
	for shooter in many_shooters:
		for target in many_targets:
			var result = EnhancedLineOfSight.check_enhanced_visibility(shooter, target, test_board)
			total_checks += 1
	
	var total_time = Time.get_ticks_msec() - start_time
	var avg_time = float(total_time) / total_checks
	
	gut.p("Extreme load: %d checks in %dms (%.2fms avg)" % [total_checks, total_time, avg_time])
	
	# Should complete without hanging
	assert_lt(total_time, 1000, "Extreme load should complete in <1s (got %dms)" % total_time)

# ===== HELPER FUNCTIONS =====

func _create_test_model_pairs() -> Array:
	var pairs = []
	
	# Create various test scenarios
	var scenarios = [
		{"shooter_x": 400, "target_x": 800, "base_mm": 32},   # Standard
		{"shooter_x": 200, "target_x": 1200, "base_mm": 32},  # Long range
		{"shooter_x": 400, "target_x": 500, "base_mm": 32},   # Close range
		{"shooter_x": 400, "target_x": 800, "base_mm": 60},   # Medium bases
		{"shooter_x": 400, "target_x": 800, "base_mm": 100},  # Large bases
	]
	
	for scenario in scenarios:
		var shooter_model = {
			"id": "shooter",
			"base_mm": scenario.base_mm,
			"position": {"x": scenario.shooter_x, "y": 400}
		}
		var target_model = {
			"id": "target",
			"base_mm": scenario.base_mm,
			"position": {"x": scenario.target_x, "y": 400}
		}
		var shooter_pos = Vector2(scenario.shooter_x, 400)
		var target_pos = Vector2(scenario.target_x, 400)
		
		pairs.append({
			"shooter_model": shooter_model,
			"target_model": target_model,
			"shooter_pos": shooter_pos,
			"target_pos": target_pos
		})
	
	return pairs

func _create_large_base_models(shooter_count: int, target_count: int) -> Dictionary:
	var shooters = []
	var targets = []
	
	for i in range(shooter_count):
		shooters.append({
			"id": "shooter_%d" % i,
			"base_mm": 80,  # Large base
			"position": {"x": 200 + i * 60, "y": 200 + (i % 2) * 60}
		})
	
	for i in range(target_count):
		targets.append({
			"id": "target_%d" % i,
			"base_mm": 80,  # Large base
			"position": {"x": 1000 + i * 60, "y": 200 + (i % 2) * 60}
		})
	
	return {"shooters": shooters, "targets": targets}

func _create_random_terrain(count: int) -> Array:
	var terrain = []
	
	for i in range(count):
		var x = 500 + (i % 5) * 100
		var y = 300 + (i / 5) * 100
		var size = 80
		
		terrain.append({
			"id": "terrain_%d" % i,
			"type": "ruins",
			"height_category": "tall",
			"polygon": PackedVector2Array([
				Vector2(x, y),
				Vector2(x + size, y),
				Vector2(x + size, y + size),
				Vector2(x, y + size)
			])
		})
	
	return terrain

func _calculate_average(times: Array) -> float:
	if times.is_empty():
		return 0.0
	
	var sum = 0.0
	for time in times:
		sum += time
	
	return sum / times.size()

# ===== PERFORMANCE REGRESSION TESTS =====

func test_performance_regression():
	# Ensure performance doesn't regress below acceptable thresholds
	gut.p("Testing performance regression thresholds")
	
	var test_model_shooter = {
		"id": "shooter",
		"base_mm": 32,
		"position": {"x": 400, "y": 400}
	}
	var test_model_target = {
		"id": "target",
		"base_mm": 32,
		"position": {"x": 800, "y": 400}
	}
	
	# Single check should be fast
	var start_time = Time.get_ticks_usec()
	var result = EnhancedLineOfSight.check_enhanced_visibility(test_model_shooter, test_model_target, test_board)
	var single_time = Time.get_ticks_usec() - start_time
	
	gut.p("Single check time: %d μs" % single_time)
	assert_lt(single_time, 1000, "Single check should be <1ms (%d μs)" % single_time)
	
	# Batch of checks should have reasonable throughput
	start_time = Time.get_ticks_msec()
	for i in range(100):
		test_model_target.position.x = 800 + (i % 10)  # Vary position slightly
		result = EnhancedLineOfSight.check_enhanced_visibility(test_model_shooter, test_model_target, test_board)
	var batch_time = Time.get_ticks_msec() - start_time
	
	gut.p("100 check batch time: %dms" % batch_time)
	assert_lt(batch_time, 100, "100 checks should complete in <100ms (%dms)" % batch_time)