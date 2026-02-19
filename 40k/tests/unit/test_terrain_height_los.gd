extends "res://addons/gut/test.gd"

# Tests for T3-19: Terrain height handling in LoS
#
# Per Warhammer 40k 10e rules:
# - Tall terrain (>5"): Blocks LoS for all models (Obscuring)
# - Medium terrain (2-5"): Blocks LoS only if both models are shorter than terrain height
#   MONSTER/VEHICLE/TITANIC models (~5") can see and be seen over medium terrain (3.5")
# - Low terrain (<2"): Never blocks LoS (provides cover only)

const RulesEngineScript = preload("res://autoloads/RulesEngine.gd")

# ==========================================
# Helpers
# ==========================================

func _make_terrain(height_category: String, polygon: PackedVector2Array) -> Dictionary:
	return {
		"id": "test_terrain",
		"type": "ruins",
		"height_category": height_category,
		"polygon": polygon,
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

func _make_vehicle_model(pos: Vector2) -> Dictionary:
	return {
		"id": "vehicle_1",
		"position": pos,
		"base_mm": 80,
		"base_type": "circular",
		"alive": true,
		"keywords": ["VEHICLE"]
	}

# ==========================================
# Model height estimation tests
# ==========================================

func test_infantry_model_height():
	"""Infantry models should be 2.0 inches tall"""
	var model = _make_infantry_model(Vector2(100, 100))
	var height = LineOfSightCalculator.get_model_height_inches(model)
	assert_eq(height, 2.0, "Infantry model should be 2.0 inches")

func test_monster_model_height():
	"""MONSTER models should be 5.0 inches tall"""
	var model = _make_monster_model(Vector2(100, 100))
	var height = LineOfSightCalculator.get_model_height_inches(model)
	assert_eq(height, 5.0, "MONSTER model should be 5.0 inches")

func test_vehicle_model_height():
	"""VEHICLE models should be 5.0 inches tall"""
	var model = _make_vehicle_model(Vector2(100, 100))
	var height = LineOfSightCalculator.get_model_height_inches(model)
	assert_eq(height, 5.0, "VEHICLE model should be 5.0 inches")

func test_titanic_model_height():
	"""TITANIC models should be 5.0 inches tall"""
	var model = {
		"id": "titan_1",
		"position": Vector2(100, 100),
		"keywords": ["TITANIC"]
	}
	var height = LineOfSightCalculator.get_model_height_inches(model)
	assert_eq(height, 5.0, "TITANIC model should be 5.0 inches")

func test_explicit_height_override():
	"""Explicit model_height_inches should override keyword detection"""
	var model = {
		"id": "custom_1",
		"position": Vector2(100, 100),
		"model_height_inches": 4.0,
		"keywords": ["INFANTRY"]
	}
	var height = LineOfSightCalculator.get_model_height_inches(model)
	assert_eq(height, 4.0, "Explicit height override should be used")

func test_empty_model_default_height():
	"""Empty model dictionary should default to infantry height"""
	var height = LineOfSightCalculator.get_model_height_inches({})
	assert_eq(height, 2.0, "Empty model should default to infantry height")

func test_meta_keywords_detection():
	"""Keywords in meta.keywords should be detected"""
	var model = {
		"id": "meta_model",
		"position": Vector2(100, 100),
		"meta": {"keywords": ["MONSTER", "CHARACTER"]}
	}
	var height = LineOfSightCalculator.get_model_height_inches(model)
	assert_eq(height, 5.0, "MONSTER in meta.keywords should be detected")

# ==========================================
# Terrain height helper tests
# ==========================================

func test_terrain_height_low():
	"""Low terrain should be 1.5 inches"""
	var terrain = {"height_category": "low"}
	assert_eq(LineOfSightCalculator._get_terrain_height_inches(terrain), 1.5)

func test_terrain_height_medium():
	"""Medium terrain should be 3.5 inches"""
	var terrain = {"height_category": "medium"}
	assert_eq(LineOfSightCalculator._get_terrain_height_inches(terrain), 3.5)

func test_terrain_height_tall():
	"""Tall terrain should be 6.0 inches"""
	var terrain = {"height_category": "tall"}
	assert_eq(LineOfSightCalculator._get_terrain_height_inches(terrain), 6.0)

# ==========================================
# LineOfSightCalculator: Low terrain tests
# ==========================================

func test_low_terrain_never_blocks_los():
	"""Low terrain should never block LoS regardless of model height"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var terrain = [_make_terrain("low", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_infantry_model(from),
		_make_infantry_model(to)
	)
	assert_true(has_los, "Low terrain should not block LoS between infantry")

# ==========================================
# LineOfSightCalculator: Medium terrain tests
# ==========================================

func test_medium_terrain_blocks_infantry_vs_infantry():
	"""Medium terrain should block LoS between two infantry models"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var terrain = [_make_terrain("medium", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_infantry_model(from),
		_make_infantry_model(to)
	)
	assert_false(has_los, "Medium terrain should block LoS between infantry models")

func test_medium_terrain_does_not_block_monster_shooter():
	"""Medium terrain should NOT block LoS when shooter is a MONSTER"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var terrain = [_make_terrain("medium", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_monster_model(from),
		_make_infantry_model(to)
	)
	assert_true(has_los, "MONSTER shooter should see over medium terrain")

func test_medium_terrain_does_not_block_monster_target():
	"""Medium terrain should NOT block LoS when target is a MONSTER"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var terrain = [_make_terrain("medium", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_infantry_model(from),
		_make_monster_model(to)
	)
	assert_true(has_los, "MONSTER target should be seen over medium terrain")

func test_medium_terrain_does_not_block_vehicle_shooter():
	"""Medium terrain should NOT block LoS when shooter is a VEHICLE"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var terrain = [_make_terrain("medium", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_vehicle_model(from),
		_make_infantry_model(to)
	)
	assert_true(has_los, "VEHICLE shooter should see over medium terrain")

func test_medium_terrain_inside_model_not_blocked():
	"""Models inside medium terrain can still see out"""
	var polygon = _make_rect_polygon(100, 100, 50, 50)  # Terrain centered on shooter
	var terrain = [_make_terrain("medium", polygon)]

	var from = Vector2(100, 100)  # Inside terrain
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_infantry_model(from),
		_make_infantry_model(to)
	)
	assert_true(has_los, "Model inside medium terrain should be able to see out")

func test_medium_terrain_no_intersection_no_blocking():
	"""Medium terrain that doesn't intersect the sight line should not block LoS"""
	var polygon = _make_rect_polygon(300, 300, 50, 50)  # Terrain far from the sight line
	var terrain = [_make_terrain("medium", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_infantry_model(from),
		_make_infantry_model(to)
	)
	assert_true(has_los, "Medium terrain not on sight line should not block LoS")

# ==========================================
# LineOfSightCalculator: Tall terrain tests (regression)
# ==========================================

func test_tall_terrain_blocks_all_models():
	"""Tall terrain should block LoS regardless of model height"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var terrain = [_make_terrain("tall", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	# Infantry vs infantry
	var has_los_infantry = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_infantry_model(from),
		_make_infantry_model(to)
	)
	assert_false(has_los_infantry, "Tall terrain should block LoS between infantry")

	# Monster vs infantry
	var has_los_monster = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_monster_model(from),
		_make_infantry_model(to)
	)
	assert_false(has_los_monster, "Tall terrain should block LoS even for MONSTER")

	# Monster vs monster
	var has_los_both = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_monster_model(from),
		_make_monster_model(to)
	)
	assert_false(has_los_both, "Tall terrain should block LoS even between two MONSTERs")

func test_tall_terrain_inside_model_can_see():
	"""Models inside tall terrain can see out (regression test)"""
	var polygon = _make_rect_polygon(100, 100, 50, 50)  # Centered on shooter
	var terrain = [_make_terrain("tall", polygon)]

	var from = Vector2(100, 100)  # Inside terrain
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_infantry_model(from),
		_make_infantry_model(to)
	)
	assert_true(has_los, "Model inside tall terrain should see out (regression)")

# ==========================================
# EnhancedLineOfSight tests
# ==========================================

func test_enhanced_los_medium_terrain_blocks_infantry():
	"""EnhancedLineOfSight should block LoS through medium terrain for infantry"""
	var polygon = _make_rect_polygon(500, 400, 80, 80)
	var board = {
		"terrain_features": [_make_terrain("medium", polygon)]
	}

	var shooter = _make_infantry_model(Vector2(300, 400))
	var target = _make_infantry_model(Vector2(700, 400))

	var result = EnhancedLineOfSight.check_enhanced_visibility(shooter, target, board)
	assert_false(result.has_los, "EnhancedLoS: medium terrain should block infantry vs infantry")

func test_enhanced_los_medium_terrain_allows_monster():
	"""EnhancedLineOfSight should allow LoS through medium terrain for MONSTER"""
	var polygon = _make_rect_polygon(500, 400, 80, 80)
	var board = {
		"terrain_features": [_make_terrain("medium", polygon)]
	}

	var shooter = _make_monster_model(Vector2(300, 400))
	var target = _make_infantry_model(Vector2(700, 400))

	var result = EnhancedLineOfSight.check_enhanced_visibility(shooter, target, board)
	assert_true(result.has_los, "EnhancedLoS: MONSTER should see over medium terrain")

func test_enhanced_los_low_terrain_allows_all():
	"""EnhancedLineOfSight should allow LoS through low terrain for all models"""
	var polygon = _make_rect_polygon(500, 400, 80, 80)
	var board = {
		"terrain_features": [_make_terrain("low", polygon)]
	}

	var shooter = _make_infantry_model(Vector2(300, 400))
	var target = _make_infantry_model(Vector2(700, 400))

	var result = EnhancedLineOfSight.check_enhanced_visibility(shooter, target, board)
	assert_true(result.has_los, "EnhancedLoS: low terrain should not block any LoS")

func test_enhanced_los_tall_terrain_blocks_all():
	"""EnhancedLineOfSight should block LoS through tall terrain for all models"""
	var polygon = _make_rect_polygon(500, 400, 80, 80)
	var board = {
		"terrain_features": [_make_terrain("tall", polygon)]
	}

	var shooter = _make_monster_model(Vector2(300, 400))
	var target = _make_monster_model(Vector2(700, 400))

	var result = EnhancedLineOfSight.check_enhanced_visibility(shooter, target, board)
	assert_false(result.has_los, "EnhancedLoS: tall terrain should block even MONSTERs")

# ==========================================
# RulesEngine legacy LoS tests
# ==========================================

func test_legacy_los_medium_terrain_blocks():
	"""Legacy LoS (no model data) should conservatively block through medium terrain"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var board = {
		"terrain_features": [_make_terrain("medium", polygon)]
	}

	var has_los = RulesEngineScript._check_legacy_line_of_sight(
		Vector2(100, 100), Vector2(500, 100), board
	)
	assert_false(has_los, "Legacy LoS should block through medium terrain (conservative)")

func test_legacy_los_low_terrain_allows():
	"""Legacy LoS should allow sight through low terrain"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var board = {
		"terrain_features": [_make_terrain("low", polygon)]
	}

	var has_los = RulesEngineScript._check_legacy_line_of_sight(
		Vector2(100, 100), Vector2(500, 100), board
	)
	assert_true(has_los, "Legacy LoS should allow sight through low terrain")

func test_legacy_los_tall_terrain_blocks():
	"""Legacy LoS should block through tall terrain (regression)"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var board = {
		"terrain_features": [_make_terrain("tall", polygon)]
	}

	var has_los = RulesEngineScript._check_legacy_line_of_sight(
		Vector2(100, 100), Vector2(500, 100), board
	)
	assert_false(has_los, "Legacy LoS should block through tall terrain (regression)")

# ==========================================
# Mixed terrain scenario tests
# ==========================================

func test_multiple_terrain_mixed_heights():
	"""LoS should be blocked if any blocking terrain intersects the sight line"""
	var low_polygon = _make_rect_polygon(200, 100, 30, 30)
	var medium_polygon = _make_rect_polygon(350, 100, 30, 30)
	var terrain = [
		_make_terrain("low", low_polygon),
		_make_terrain("medium", medium_polygon)
	]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	# Infantry: medium terrain should block even though low doesn't
	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_infantry_model(from),
		_make_infantry_model(to)
	)
	assert_false(has_los, "Medium terrain in mixed layout should still block infantry LoS")

	# Monster: should see over both low and medium
	var has_los_monster = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_monster_model(from),
		_make_monster_model(to)
	)
	assert_true(has_los_monster, "MONSTERs should see over both low and medium terrain")

func test_backward_compatibility_no_model_data():
	"""check_line_of_sight without model data should use conservative defaults"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var terrain = [_make_terrain("medium", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	# Call without model data (backward compatibility)
	var has_los = LineOfSightCalculator.check_line_of_sight(from, to, terrain)
	assert_false(has_los, "No model data should default to infantry height (blocked by medium)")
