extends "res://addons/gut/test.gd"

# Tests for TER-4: Obscuring terrain keyword
#
# Per Warhammer 40k 10e rules:
# - Terrain with the Obscuring keyword blocks LoS when the sight line
#   crosses the terrain's footprint and neither model is within the terrain
# - Tall terrain (>5") is implicitly Obscuring
# - The "obscuring" trait can be explicitly added to any terrain height
# - Models inside Obscuring terrain can still see out and be seen

# ==========================================
# Helpers
# ==========================================

func _make_terrain(height_category: String, polygon: PackedVector2Array, traits: Array = []) -> Dictionary:
	return {
		"id": "test_terrain",
		"type": "obstacle",
		"height_category": height_category,
		"polygon": polygon,
		"traits": traits,
		"walls": []
	}

func _make_rect_polygon(center_x: float, center_y: float, half_w: float, half_h: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(center_x - half_w, center_y - half_h),
		Vector2(center_x + half_w, center_y - half_h),
		Vector2(center_x + half_w, center_y + half_h),
		Vector2(center_x - half_w, center_y + half_h)
	])

func _make_infantry_model(pos: Vector2) -> Dictionary:
	return {
		"id": "infantry_1",
		"position": pos,
		"base_mm": 32,
		"base_type": "circular",
		"alive": true,
		"keywords": ["INFANTRY"]
	}

func _make_monster_model(pos: Vector2) -> Dictionary:
	return {
		"id": "monster_1",
		"position": pos,
		"base_mm": 80,
		"base_type": "circular",
		"alive": true,
		"keywords": ["MONSTER"]
	}

# ==========================================
# TerrainManager.is_terrain_obscuring() tests
# ==========================================

func test_tall_terrain_is_implicitly_obscuring():
	"""Tall terrain should be considered Obscuring even without the trait"""
	var terrain = _make_terrain("tall", _make_rect_polygon(300, 100, 50, 50))
	assert_true(TerrainManager.is_terrain_obscuring(terrain), "Tall terrain should be implicitly Obscuring")

func test_medium_terrain_not_obscuring_by_default():
	"""Medium terrain without the obscuring trait should NOT be Obscuring"""
	var terrain = _make_terrain("medium", _make_rect_polygon(300, 100, 50, 50))
	assert_false(TerrainManager.is_terrain_obscuring(terrain), "Medium terrain without trait should not be Obscuring")

func test_low_terrain_not_obscuring_by_default():
	"""Low terrain without the obscuring trait should NOT be Obscuring"""
	var terrain = _make_terrain("low", _make_rect_polygon(300, 100, 50, 50))
	assert_false(TerrainManager.is_terrain_obscuring(terrain), "Low terrain without trait should not be Obscuring")

func test_medium_terrain_with_obscuring_trait():
	"""Medium terrain with the 'obscuring' trait should be considered Obscuring"""
	var terrain = _make_terrain("medium", _make_rect_polygon(300, 100, 50, 50), ["obscuring"])
	assert_true(TerrainManager.is_terrain_obscuring(terrain), "Medium terrain with obscuring trait should be Obscuring")

func test_low_terrain_with_obscuring_trait():
	"""Low terrain with the 'obscuring' trait should be considered Obscuring"""
	var terrain = _make_terrain("low", _make_rect_polygon(300, 100, 50, 50), ["obscuring"])
	assert_true(TerrainManager.is_terrain_obscuring(terrain), "Low terrain with obscuring trait should be Obscuring")

func test_terrain_with_multiple_traits_including_obscuring():
	"""Terrain with multiple traits including 'obscuring' should be Obscuring"""
	var terrain = _make_terrain("medium", _make_rect_polygon(300, 100, 50, 50), ["difficult_ground", "obscuring"])
	assert_true(TerrainManager.is_terrain_obscuring(terrain), "Terrain with obscuring among multiple traits should be Obscuring")

# ==========================================
# LineOfSightCalculator: Obscuring trait LoS tests
# ==========================================

func test_obscuring_medium_terrain_blocks_infantry_los():
	"""Medium terrain with Obscuring trait should block LoS between infantry"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var terrain = [_make_terrain("medium", polygon, ["obscuring"])]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_infantry_model(from),
		_make_infantry_model(to)
	)
	assert_false(has_los, "Obscuring medium terrain should block infantry LoS")

func test_obscuring_medium_terrain_blocks_monster_los():
	"""Medium terrain with Obscuring trait should block LoS even for MONSTER models"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var terrain = [_make_terrain("medium", polygon, ["obscuring"])]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_monster_model(from),
		_make_monster_model(to)
	)
	assert_false(has_los, "Obscuring medium terrain should block even MONSTER LoS")

func test_non_obscuring_medium_terrain_allows_monster_los():
	"""Medium terrain WITHOUT Obscuring trait should allow MONSTER to see over it"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var terrain = [_make_terrain("medium", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_monster_model(from),
		_make_infantry_model(to)
	)
	assert_true(has_los, "Non-Obscuring medium terrain should allow MONSTER LoS over it")

func test_obscuring_terrain_allows_model_inside_to_see_out():
	"""Models inside Obscuring terrain should still see out"""
	var polygon = _make_rect_polygon(100, 100, 50, 50)  # Centered on shooter
	var terrain = [_make_terrain("medium", polygon, ["obscuring"])]

	var from = Vector2(100, 100)  # Inside terrain
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_infantry_model(from),
		_make_infantry_model(to)
	)
	assert_true(has_los, "Model inside Obscuring terrain should see out")

func test_obscuring_terrain_allows_seeing_model_inside():
	"""Models should be able to see a target inside Obscuring terrain"""
	var polygon = _make_rect_polygon(500, 100, 50, 50)  # Centered on target
	var terrain = [_make_terrain("medium", polygon, ["obscuring"])]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)  # Inside terrain

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_infantry_model(from),
		_make_infantry_model(to)
	)
	assert_true(has_los, "Should be able to see model inside Obscuring terrain")

func test_obscuring_terrain_no_intersection_does_not_block():
	"""Obscuring terrain that doesn't intersect the sight line should not block LoS"""
	var polygon = _make_rect_polygon(300, 300, 50, 50)  # Terrain far from sight line
	var terrain = [_make_terrain("medium", polygon, ["obscuring"])]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_infantry_model(from),
		_make_infantry_model(to)
	)
	assert_true(has_los, "Obscuring terrain off the sight line should not block LoS")

# ==========================================
# EnhancedLineOfSight: Obscuring trait tests
# ==========================================

func test_enhanced_los_obscuring_medium_blocks_all():
	"""EnhancedLineOfSight should block LoS through Obscuring medium terrain"""
	var polygon = _make_rect_polygon(500, 400, 80, 80)
	var board = {
		"terrain_features": [_make_terrain("medium", polygon, ["obscuring"])]
	}

	var shooter = _make_monster_model(Vector2(300, 400))
	var target = _make_monster_model(Vector2(700, 400))

	var result = EnhancedLineOfSight.check_enhanced_visibility(shooter, target, board)
	assert_false(result.has_los, "EnhancedLoS: Obscuring medium terrain should block even MONSTERs")

func test_enhanced_los_non_obscuring_medium_allows_monster():
	"""EnhancedLineOfSight should allow MONSTER LoS through non-Obscuring medium terrain"""
	var polygon = _make_rect_polygon(500, 400, 80, 80)
	var board = {
		"terrain_features": [_make_terrain("medium", polygon)]
	}

	var shooter = _make_monster_model(Vector2(300, 400))
	var target = _make_infantry_model(Vector2(700, 400))

	var result = EnhancedLineOfSight.check_enhanced_visibility(shooter, target, board)
	assert_true(result.has_los, "EnhancedLoS: MONSTER should see over non-Obscuring medium terrain")

# ==========================================
# Regression: existing tall terrain tests still pass
# ==========================================

func test_tall_terrain_still_blocks_all_models():
	"""Tall terrain (implicitly Obscuring) should still block all LoS (regression)"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var terrain = [_make_terrain("tall", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_monster_model(from),
		_make_monster_model(to)
	)
	assert_false(has_los, "Tall terrain should still block LoS between MONSTERs (regression)")

func test_tall_terrain_inside_model_still_sees():
	"""Models inside tall terrain should still see out (regression)"""
	var polygon = _make_rect_polygon(100, 100, 50, 50)
	var terrain = [_make_terrain("tall", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_infantry_model(from),
		_make_infantry_model(to)
	)
	assert_true(has_los, "Model inside tall terrain should still see out (regression)")
