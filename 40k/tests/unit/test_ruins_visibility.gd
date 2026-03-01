extends "res://addons/gut/test.gd"

# Tests for TER-2: Ruins visibility rules per 10e Core Rules
#
# Rules:
# 1. Models cannot see over or through Ruins terrain
# 2. Aircraft models are exceptions (visibility to/from determined normally)
# 3. Models can see into Ruins normally
# 4. Models wholly within Ruins can see out normally
# 5. Towering models within (not wholly within) Ruins can also see out normally

const RulesEngineScript = preload("res://autoloads/RulesEngine.gd")

# ==========================================
# Helpers
# ==========================================

func _make_ruins_terrain(height_category: String, polygon: PackedVector2Array) -> Dictionary:
	return {
		"id": "test_ruins",
		"type": "ruins",
		"height_category": height_category,
		"polygon": polygon,
		"walls": []
	}

func _make_non_ruins_terrain(height_category: String, polygon: PackedVector2Array) -> Dictionary:
	return {
		"id": "test_obstacle",
		"type": "obstacle",
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

func _make_aircraft_model(pos: Vector2) -> Dictionary:
	return {
		"id": "aircraft_1",
		"position": pos,
		"base_mm": 80,
		"base_type": "circular",
		"alive": true,
		"keywords": ["AIRCRAFT", "FLY", "VEHICLE"]
	}

func _make_towering_model(pos: Vector2) -> Dictionary:
	return {
		"id": "towering_1",
		"position": pos,
		"base_mm": 130,
		"base_type": "circular",
		"alive": true,
		"keywords": ["TOWERING", "MONSTER", "TITANIC"]
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
# Rule 1: Cannot see over or through Ruins
# ==========================================

func test_ruins_blocks_los_between_outside_models():
	"""Models on opposite sides of Ruins cannot see each other"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var terrain = [_make_ruins_terrain("tall", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_infantry_model(from),
		_make_infantry_model(to)
	)
	assert_false(has_los, "Ruins should block LoS between models on opposite sides")

func test_ruins_blocks_los_regardless_of_height():
	"""Even medium-height Ruins block LoS (unlike generic medium terrain for tall models)"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var terrain = [_make_ruins_terrain("medium", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	# Monsters can normally see over medium non-ruins terrain, but NOT over medium Ruins
	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_monster_model(from),
		_make_infantry_model(to)
	)
	assert_false(has_los, "Medium Ruins should block LoS even for MONSTER models")

func test_ruins_blocks_los_monster_vs_monster():
	"""Two MONSTER models cannot see through Ruins"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var terrain = [_make_ruins_terrain("tall", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_monster_model(from),
		_make_monster_model(to)
	)
	assert_false(has_los, "Ruins should block LoS even between two MONSTER models")

# ==========================================
# Rule 2: Aircraft exception
# ==========================================

func test_aircraft_shooter_sees_through_ruins():
	"""Aircraft models can see through Ruins"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var terrain = [_make_ruins_terrain("tall", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_aircraft_model(from),
		_make_infantry_model(to)
	)
	assert_true(has_los, "Aircraft shooter should see through Ruins")

func test_aircraft_target_seen_through_ruins():
	"""Aircraft targets can be seen through Ruins"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var terrain = [_make_ruins_terrain("tall", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_infantry_model(from),
		_make_aircraft_model(to)
	)
	assert_true(has_los, "Aircraft target should be visible through Ruins")

func test_aircraft_both_see_through_ruins():
	"""Two Aircraft models can see each other through Ruins"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var terrain = [_make_ruins_terrain("tall", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_aircraft_model(from),
		_make_aircraft_model(to)
	)
	assert_true(has_los, "Two Aircraft should see through Ruins")

# ==========================================
# Rule 3: Can see INTO Ruins normally
# ==========================================

func test_can_see_into_ruins():
	"""Models outside Ruins can see targets inside the Ruins"""
	var polygon = _make_rect_polygon(400, 100, 150, 100)  # Large ruin
	var terrain = [_make_ruins_terrain("tall", polygon)]

	var from = Vector2(100, 100)  # Outside
	var to = Vector2(400, 100)    # Inside the ruin

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_infantry_model(from),
		_make_infantry_model(to)
	)
	assert_true(has_los, "Should be able to see INTO Ruins normally")

# ==========================================
# Rule 4: Models wholly within Ruins can see out
# ==========================================

func test_model_wholly_within_ruins_can_see_out():
	"""Models wholly within Ruins can see out normally"""
	var polygon = _make_rect_polygon(100, 100, 100, 100)  # Large ruin containing shooter
	var terrain = [_make_ruins_terrain("tall", polygon)]

	var from = Vector2(100, 100)  # Inside the ruin
	var to = Vector2(500, 100)    # Outside

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_infantry_model(from),
		_make_infantry_model(to)
	)
	assert_true(has_los, "Model wholly within Ruins should see out normally")

# ==========================================
# Rule 5: Towering models within can see out
# ==========================================

func test_towering_model_outside_does_not_see_through_ruins():
	"""Towering models OUTSIDE Ruins cannot see through them"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var terrain = [_make_ruins_terrain("tall", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_towering_model(from),
		_make_infantry_model(to)
	)
	assert_false(has_los, "Towering model OUTSIDE should not see through Ruins")

# ==========================================
# Non-ruins terrain: regression tests
# ==========================================

func test_non_ruins_tall_terrain_still_blocks():
	"""Non-ruins tall terrain should still block LoS (regression)"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var terrain = [_make_non_ruins_terrain("tall", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_infantry_model(from),
		_make_infantry_model(to)
	)
	assert_false(has_los, "Non-ruins tall terrain should still block LoS")

func test_non_ruins_medium_terrain_allows_monster():
	"""Non-ruins medium terrain should allow MONSTER to see over (regression)"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var terrain = [_make_non_ruins_terrain("medium", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_monster_model(from),
		_make_infantry_model(to)
	)
	assert_true(has_los, "Non-ruins medium terrain should allow MONSTER to see over (regression)")

func test_non_ruins_inside_model_can_see():
	"""Non-ruins terrain inside model can still see out (regression)"""
	var polygon = _make_rect_polygon(100, 100, 50, 50)
	var terrain = [_make_non_ruins_terrain("tall", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_infantry_model(from),
		_make_infantry_model(to)
	)
	assert_true(has_los, "Model inside non-ruins tall terrain should see out (regression)")

# ==========================================
# EnhancedLineOfSight tests
# ==========================================

func test_enhanced_los_ruins_blocks_infantry():
	"""EnhancedLineOfSight: Ruins should block LoS between infantry outside"""
	var polygon = _make_rect_polygon(500, 400, 80, 80)
	var board = {
		"terrain_features": [_make_ruins_terrain("tall", polygon)]
	}

	var shooter = _make_infantry_model(Vector2(300, 400))
	var target = _make_infantry_model(Vector2(700, 400))

	var result = EnhancedLineOfSight.check_enhanced_visibility(shooter, target, board)
	assert_false(result.has_los, "EnhancedLoS: Ruins should block infantry vs infantry")

func test_enhanced_los_ruins_aircraft_exception():
	"""EnhancedLineOfSight: Aircraft should see through Ruins"""
	var polygon = _make_rect_polygon(500, 400, 80, 80)
	var board = {
		"terrain_features": [_make_ruins_terrain("tall", polygon)]
	}

	var shooter = _make_aircraft_model(Vector2(300, 400))
	var target = _make_infantry_model(Vector2(700, 400))

	var result = EnhancedLineOfSight.check_enhanced_visibility(shooter, target, board)
	assert_true(result.has_los, "EnhancedLoS: Aircraft should see through Ruins")

func test_enhanced_los_ruins_see_into():
	"""EnhancedLineOfSight: Can see into Ruins"""
	var polygon = _make_rect_polygon(600, 400, 200, 200)  # Large ruin containing target
	var board = {
		"terrain_features": [_make_ruins_terrain("tall", polygon)]
	}

	var shooter = _make_infantry_model(Vector2(200, 400))
	var target = _make_infantry_model(Vector2(600, 400))  # Inside

	var result = EnhancedLineOfSight.check_enhanced_visibility(shooter, target, board)
	assert_true(result.has_los, "EnhancedLoS: Should be able to see into Ruins")

func test_enhanced_los_ruins_wholly_within_see_out():
	"""EnhancedLineOfSight: Model wholly within Ruins can see out"""
	# Make the ruin large enough that the model's base (32mm) is entirely inside
	var polygon = _make_rect_polygon(300, 400, 200, 200)
	var board = {
		"terrain_features": [_make_ruins_terrain("tall", polygon)]
	}

	var shooter = _make_infantry_model(Vector2(300, 400))  # Center of large ruin
	var target = _make_infantry_model(Vector2(700, 400))

	var result = EnhancedLineOfSight.check_enhanced_visibility(shooter, target, board)
	assert_true(result.has_los, "EnhancedLoS: Model wholly within Ruins should see out")

func test_enhanced_los_medium_ruins_blocks_all():
	"""EnhancedLineOfSight: Medium Ruins block even MONSTER (unlike generic medium terrain)"""
	var polygon = _make_rect_polygon(500, 400, 80, 80)
	var board = {
		"terrain_features": [_make_ruins_terrain("medium", polygon)]
	}

	var shooter = _make_monster_model(Vector2(300, 400))
	var target = _make_infantry_model(Vector2(700, 400))

	var result = EnhancedLineOfSight.check_enhanced_visibility(shooter, target, board)
	assert_false(result.has_los, "EnhancedLoS: Medium Ruins should block even MONSTER")

# ==========================================
# Keyword detection helper tests
# ==========================================

func test_aircraft_keyword_detection():
	"""_model_has_aircraft_keyword should detect AIRCRAFT in keywords"""
	var model = {"keywords": ["AIRCRAFT", "FLY", "VEHICLE"]}
	assert_true(LineOfSightCalculator._model_has_aircraft_keyword(model), "Should detect AIRCRAFT keyword")

func test_aircraft_keyword_detection_meta():
	"""_model_has_aircraft_keyword should detect AIRCRAFT in meta.keywords"""
	var model = {"meta": {"keywords": ["AIRCRAFT", "FLY"]}}
	assert_true(LineOfSightCalculator._model_has_aircraft_keyword(model), "Should detect AIRCRAFT in meta.keywords")

func test_aircraft_keyword_not_present():
	"""_model_has_aircraft_keyword should return false when not present"""
	var model = {"keywords": ["INFANTRY"]}
	assert_false(LineOfSightCalculator._model_has_aircraft_keyword(model), "Should not detect AIRCRAFT on infantry")

func test_towering_keyword_detection():
	"""_model_has_towering_keyword should detect TOWERING"""
	var model = {"keywords": ["TOWERING", "MONSTER", "TITANIC"]}
	assert_true(LineOfSightCalculator._model_has_towering_keyword(model), "Should detect TOWERING keyword")

func test_towering_keyword_not_present():
	"""_model_has_towering_keyword should return false when not present"""
	var model = {"keywords": ["MONSTER"]}
	assert_false(LineOfSightCalculator._model_has_towering_keyword(model), "MONSTER alone is not TOWERING")

func test_empty_model_no_aircraft():
	"""Empty model should not have AIRCRAFT keyword"""
	assert_false(LineOfSightCalculator._model_has_aircraft_keyword({}), "Empty model should not have AIRCRAFT")

func test_empty_model_no_towering():
	"""Empty model should not have TOWERING keyword"""
	assert_false(LineOfSightCalculator._model_has_towering_keyword({}), "Empty model should not have TOWERING")

# ==========================================
# Legacy LoS path tests
# ==========================================

func test_legacy_los_ruins_blocks():
	"""Legacy LoS path should block through Ruins"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var board = {
		"terrain_features": [_make_ruins_terrain("tall", polygon)]
	}

	var has_los = RulesEngineScript._check_legacy_line_of_sight(
		Vector2(100, 100), Vector2(500, 100), board
	)
	assert_false(has_los, "Legacy LoS should block through Ruins")

func test_legacy_los_ruins_see_into():
	"""Legacy LoS path should allow seeing into Ruins"""
	var polygon = _make_rect_polygon(400, 100, 150, 100)
	var board = {
		"terrain_features": [_make_ruins_terrain("tall", polygon)]
	}

	var has_los = RulesEngineScript._check_legacy_line_of_sight(
		Vector2(100, 100), Vector2(400, 100), board  # Target inside
	)
	assert_true(has_los, "Legacy LoS should allow seeing into Ruins")

func test_legacy_los_ruins_see_out():
	"""Legacy LoS path should allow seeing out of Ruins"""
	var polygon = _make_rect_polygon(100, 100, 100, 100)
	var board = {
		"terrain_features": [_make_ruins_terrain("tall", polygon)]
	}

	var has_los = RulesEngineScript._check_legacy_line_of_sight(
		Vector2(100, 100), Vector2(500, 100), board  # Shooter inside
	)
	assert_true(has_los, "Legacy LoS should allow seeing out of Ruins")

# ==========================================
# Edge cases
# ==========================================

func test_ruins_no_intersection_no_blocking():
	"""Ruins that don't intersect the sight line should not block"""
	var polygon = _make_rect_polygon(300, 300, 50, 50)  # Far from sight line
	var terrain = [_make_ruins_terrain("tall", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_infantry_model(from),
		_make_infantry_model(to)
	)
	assert_true(has_los, "Ruins not on sight line should not block")

func test_low_ruins_never_block():
	"""Low-height Ruins should never block LoS"""
	var polygon = _make_rect_polygon(300, 100, 50, 50)
	var terrain = [_make_ruins_terrain("low", polygon)]

	var from = Vector2(100, 100)
	var to = Vector2(500, 100)

	var has_los = LineOfSightCalculator.check_line_of_sight(
		from, to, terrain,
		_make_infantry_model(from),
		_make_infantry_model(to)
	)
	assert_true(has_los, "Low Ruins should never block LoS")
