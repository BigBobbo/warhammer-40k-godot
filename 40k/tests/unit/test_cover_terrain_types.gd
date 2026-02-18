extends "res://addons/gut/test.gd"

# Tests for T2-10: Cover determination supports all terrain types
#
# Per Warhammer 40k 10e rules:
# - Ruins, obstacles, barricades: cover when target is within OR behind (LoS crosses terrain)
# - Area terrain (woods, craters): cover when target is within the terrain
# - Non-cover terrain types (e.g., impassable) do not grant cover

const RulesEngineScript = preload("res://autoloads/RulesEngine.gd")

# ==========================================
# Helpers
# ==========================================

func _make_terrain(type: String, polygon: PackedVector2Array) -> Dictionary:
	return {
		"type": type,
		"polygon": polygon,
		"height_category": "tall"
	}

func _make_rect_polygon(center_x: float, center_y: float, half_w: float, half_h: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(center_x - half_w, center_y - half_h),
		Vector2(center_x + half_w, center_y - half_h),
		Vector2(center_x + half_w, center_y + half_h),
		Vector2(center_x - half_w, center_y + half_h)
	])

func _make_board_with_terrain(terrain_features: Array) -> Dictionary:
	return {
		"terrain_features": terrain_features
	}

# ==========================================
# Ruins cover tests (existing behavior - regression check)
# ==========================================

func test_ruins_cover_target_within():
	"""Target within ruins terrain gets cover"""
	var polygon = _make_rect_polygon(300, 300, 50, 50)
	var board = _make_board_with_terrain([_make_terrain("ruins", polygon)])

	var target_pos = Vector2(300, 300)  # Inside ruins
	var shooter_pos = Vector2(100, 300)  # Outside ruins

	assert_true(
		RulesEngineScript.check_benefit_of_cover(target_pos, shooter_pos, board),
		"Target within ruins should have cover"
	)

func test_ruins_cover_target_behind():
	"""Target behind ruins (LoS crosses terrain) gets cover"""
	var polygon = _make_rect_polygon(300, 300, 50, 50)
	var board = _make_board_with_terrain([_make_terrain("ruins", polygon)])

	var target_pos = Vector2(500, 300)  # Behind ruins from shooter's perspective
	var shooter_pos = Vector2(100, 300)  # Shooter on other side of ruins

	assert_true(
		RulesEngineScript.check_benefit_of_cover(target_pos, shooter_pos, board),
		"Target behind ruins should have cover (LoS crosses terrain)"
	)

func test_ruins_no_cover_in_open():
	"""Target in open ground with ruins nearby does not get cover"""
	var polygon = _make_rect_polygon(300, 300, 50, 50)
	var board = _make_board_with_terrain([_make_terrain("ruins", polygon)])

	var target_pos = Vector2(500, 500)  # Not in ruins, LoS doesn't cross
	var shooter_pos = Vector2(100, 500)  # Shooter

	assert_false(
		RulesEngineScript.check_benefit_of_cover(target_pos, shooter_pos, board),
		"Target in open ground should not have cover"
	)

# ==========================================
# Woods cover tests (area terrain - within only)
# ==========================================

func test_woods_cover_target_within():
	"""Target within woods terrain gets cover"""
	var polygon = _make_rect_polygon(300, 300, 50, 50)
	var board = _make_board_with_terrain([_make_terrain("woods", polygon)])

	var target_pos = Vector2(300, 300)  # Inside woods
	var shooter_pos = Vector2(100, 300)  # Outside woods

	assert_true(
		RulesEngineScript.check_benefit_of_cover(target_pos, shooter_pos, board),
		"Target within woods should have cover"
	)

func test_woods_no_cover_target_behind():
	"""Target behind woods does NOT get cover (area terrain = within only)"""
	var polygon = _make_rect_polygon(300, 300, 50, 50)
	var board = _make_board_with_terrain([_make_terrain("woods", polygon)])

	var target_pos = Vector2(500, 300)  # Behind woods but not within
	var shooter_pos = Vector2(100, 300)  # Shooter on other side

	assert_false(
		RulesEngineScript.check_benefit_of_cover(target_pos, shooter_pos, board),
		"Target behind woods should NOT have cover (area terrain grants cover only when within)"
	)

# ==========================================
# Crater cover tests (area terrain - within only)
# ==========================================

func test_crater_cover_target_within():
	"""Target within crater terrain gets cover"""
	var polygon = _make_rect_polygon(300, 300, 50, 50)
	var board = _make_board_with_terrain([_make_terrain("crater", polygon)])

	var target_pos = Vector2(300, 300)  # Inside crater
	var shooter_pos = Vector2(100, 300)  # Outside crater

	assert_true(
		RulesEngineScript.check_benefit_of_cover(target_pos, shooter_pos, board),
		"Target within crater should have cover"
	)

func test_crater_no_cover_target_behind():
	"""Target behind crater does NOT get cover (area terrain)"""
	var polygon = _make_rect_polygon(300, 300, 50, 50)
	var board = _make_board_with_terrain([_make_terrain("crater", polygon)])

	var target_pos = Vector2(500, 300)  # Behind crater
	var shooter_pos = Vector2(100, 300)  # Shooter

	assert_false(
		RulesEngineScript.check_benefit_of_cover(target_pos, shooter_pos, board),
		"Target behind crater should NOT have cover (area terrain)"
	)

# ==========================================
# Obstacle/barricade cover tests (within and behind)
# ==========================================

func test_obstacle_cover_target_within():
	"""Target within obstacle terrain gets cover"""
	var polygon = _make_rect_polygon(300, 300, 50, 50)
	var board = _make_board_with_terrain([_make_terrain("obstacle", polygon)])

	var target_pos = Vector2(300, 300)  # Inside obstacle footprint
	var shooter_pos = Vector2(100, 300)  # Outside

	assert_true(
		RulesEngineScript.check_benefit_of_cover(target_pos, shooter_pos, board),
		"Target within obstacle should have cover"
	)

func test_obstacle_cover_target_behind():
	"""Target behind obstacle (LoS crosses terrain) gets cover"""
	var polygon = _make_rect_polygon(300, 300, 50, 50)
	var board = _make_board_with_terrain([_make_terrain("obstacle", polygon)])

	var target_pos = Vector2(500, 300)  # Behind obstacle
	var shooter_pos = Vector2(100, 300)  # Shooter on other side

	assert_true(
		RulesEngineScript.check_benefit_of_cover(target_pos, shooter_pos, board),
		"Target behind obstacle should have cover (LoS crosses terrain)"
	)

func test_barricade_cover_target_behind():
	"""Target behind barricade gets cover"""
	var polygon = _make_rect_polygon(300, 300, 50, 10)  # Thin barricade
	var board = _make_board_with_terrain([_make_terrain("barricade", polygon)])

	var target_pos = Vector2(500, 300)  # Behind barricade
	var shooter_pos = Vector2(100, 300)  # Shooter

	assert_true(
		RulesEngineScript.check_benefit_of_cover(target_pos, shooter_pos, board),
		"Target behind barricade should have cover"
	)

# ==========================================
# Area terrain cover tests
# ==========================================

func test_area_terrain_cover_target_within():
	"""Target within generic area_terrain gets cover"""
	var polygon = _make_rect_polygon(300, 300, 50, 50)
	var board = _make_board_with_terrain([_make_terrain("area_terrain", polygon)])

	var target_pos = Vector2(300, 300)  # Inside area terrain
	var shooter_pos = Vector2(100, 300)  # Outside

	assert_true(
		RulesEngineScript.check_benefit_of_cover(target_pos, shooter_pos, board),
		"Target within area_terrain should have cover"
	)

func test_area_terrain_no_cover_target_behind():
	"""Target behind area_terrain does NOT get cover"""
	var polygon = _make_rect_polygon(300, 300, 50, 50)
	var board = _make_board_with_terrain([_make_terrain("area_terrain", polygon)])

	var target_pos = Vector2(500, 300)  # Behind area terrain
	var shooter_pos = Vector2(100, 300)  # Shooter

	assert_false(
		RulesEngineScript.check_benefit_of_cover(target_pos, shooter_pos, board),
		"Target behind area_terrain should NOT have cover"
	)

# ==========================================
# Non-cover terrain types
# ==========================================

func test_impassable_terrain_no_cover():
	"""Impassable terrain does not grant cover"""
	var polygon = _make_rect_polygon(300, 300, 50, 50)
	var board = _make_board_with_terrain([_make_terrain("impassable", polygon)])

	var target_pos = Vector2(300, 300)  # Inside impassable terrain
	var shooter_pos = Vector2(100, 300)  # Outside

	assert_false(
		RulesEngineScript.check_benefit_of_cover(target_pos, shooter_pos, board),
		"Impassable terrain should not grant cover"
	)

func test_unknown_terrain_no_cover():
	"""Unknown terrain types do not grant cover"""
	var polygon = _make_rect_polygon(300, 300, 50, 50)
	var board = _make_board_with_terrain([_make_terrain("unknown_type", polygon)])

	var target_pos = Vector2(300, 300)  # Inside terrain
	var shooter_pos = Vector2(100, 300)  # Outside

	assert_false(
		RulesEngineScript.check_benefit_of_cover(target_pos, shooter_pos, board),
		"Unknown terrain type should not grant cover"
	)

# ==========================================
# Edge cases
# ==========================================

func test_no_terrain_no_cover():
	"""No terrain features means no cover"""
	var board = _make_board_with_terrain([])

	var target_pos = Vector2(300, 300)
	var shooter_pos = Vector2(100, 300)

	assert_false(
		RulesEngineScript.check_benefit_of_cover(target_pos, shooter_pos, board),
		"No terrain should mean no cover"
	)

func test_empty_polygon_no_cover():
	"""Terrain with empty polygon does not grant cover"""
	var board = _make_board_with_terrain([_make_terrain("ruins", PackedVector2Array())])

	var target_pos = Vector2(300, 300)
	var shooter_pos = Vector2(100, 300)

	assert_false(
		RulesEngineScript.check_benefit_of_cover(target_pos, shooter_pos, board),
		"Terrain with empty polygon should not grant cover"
	)

func test_shooter_inside_ruins_target_outside_no_cover():
	"""Shooter inside ruins, target outside and no LoS crossing = no cover"""
	var polygon = _make_rect_polygon(100, 300, 50, 50)
	var board = _make_board_with_terrain([_make_terrain("ruins", polygon)])

	var target_pos = Vector2(500, 300)  # Outside ruins, LoS may cross
	var shooter_pos = Vector2(100, 300)  # Inside ruins

	# Shooter is inside the polygon, target is outside
	# LoS crosses the polygon, but since shooter is inside, no cover
	assert_false(
		RulesEngineScript.check_benefit_of_cover(target_pos, shooter_pos, board),
		"Target should not get cover when shooter is inside the same terrain piece"
	)

func test_mixed_terrain_cover_from_woods():
	"""Test cover from woods when ruins don't apply"""
	var ruins_polygon = _make_rect_polygon(300, 100, 50, 50)  # Ruins far away
	var woods_polygon = _make_rect_polygon(500, 500, 80, 80)  # Woods around target
	var board = _make_board_with_terrain([
		_make_terrain("ruins", ruins_polygon),
		_make_terrain("woods", woods_polygon)
	])

	var target_pos = Vector2(500, 500)  # Inside woods
	var shooter_pos = Vector2(100, 500)  # Outside all terrain

	assert_true(
		RulesEngineScript.check_benefit_of_cover(target_pos, shooter_pos, board),
		"Target within woods should have cover even with ruins elsewhere"
	)

func test_forest_type_cover_within():
	"""Forest terrain type grants cover when target is within"""
	var polygon = _make_rect_polygon(300, 300, 50, 50)
	var board = _make_board_with_terrain([_make_terrain("forest", polygon)])

	var target_pos = Vector2(300, 300)  # Inside forest
	var shooter_pos = Vector2(100, 300)  # Outside

	assert_true(
		RulesEngineScript.check_benefit_of_cover(target_pos, shooter_pos, board),
		"Target within forest should have cover"
	)
