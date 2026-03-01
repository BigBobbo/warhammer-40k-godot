extends "res://addons/gut/test.gd"

# Tests for P1-68: Wall-based LoS blocking in EnhancedLineOfSight
#
# Critical bug fix: EnhancedLineOfSight was not checking walls at all,
# meaning walls with blocks_los=true were being completely ignored in
# the primary shooting LoS path.
#
# Also tests: _segment_intersects_polygon now correctly handles the
# case where both endpoints are inside a polygon (no edge crossing).

# ==========================================
# Helpers
# ==========================================

func _make_ruins_terrain_with_wall(height_category: String, polygon: PackedVector2Array, wall_start: Vector2, wall_end: Vector2, blocks_los: bool = true) -> Dictionary:
	return {
		"id": "test_ruins",
		"type": "ruins",
		"height_category": height_category,
		"polygon": polygon,
		"walls": [{
			"id": "test_wall",
			"start": wall_start,
			"end": wall_end,
			"type": "solid" if blocks_los else "window",
			"blocks_movement": {"INFANTRY": false, "VEHICLE": true, "MONSTER": true},
			"blocks_los": blocks_los
		}]
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

# ==========================================
# BUG FIX: EnhancedLineOfSight wall checking
# ==========================================

func test_enhanced_los_wall_blocks_sight_into_ruins():
	"""P1-68: Wall should block LoS even when shooting into ruins"""
	# Ruin at (400,400), 400x400 pixels
	var polygon = _make_rect_polygon(400, 400, 200, 200)
	# Wall across the west face of the ruin
	var wall_start = Vector2(200, 200)  # Top-left corner
	var wall_end = Vector2(200, 600)    # Bottom-left corner
	var board = {
		"terrain_features": [_make_ruins_terrain_with_wall("tall", polygon, wall_start, wall_end, true)]
	}

	var shooter = _make_infantry_model(Vector2(100, 400))  # Outside, west of ruin
	var target = _make_infantry_model(Vector2(400, 400))   # Inside ruin center

	var result = EnhancedLineOfSight.check_enhanced_visibility(shooter, target, board)
	assert_false(result.has_los, "P1-68: Wall should block LoS even when seeing into ruins")

func test_enhanced_los_wall_blocks_sight_out_of_ruins():
	"""P1-68: Wall should block LoS when shooting out of ruins"""
	# Large ruin at (300,400), 400x400 pixels
	var polygon = _make_rect_polygon(300, 400, 200, 200)
	# Wall across the east face of the ruin
	var wall_start = Vector2(500, 200)
	var wall_end = Vector2(500, 600)
	var board = {
		"terrain_features": [_make_ruins_terrain_with_wall("tall", polygon, wall_start, wall_end, true)]
	}

	var shooter = _make_infantry_model(Vector2(300, 400))  # Inside ruin center (wholly within)
	var target = _make_infantry_model(Vector2(700, 400))   # Outside, east of ruin

	var result = EnhancedLineOfSight.check_enhanced_visibility(shooter, target, board)
	assert_false(result.has_los, "P1-68: Wall should block LoS even when shooting out of ruins")

func test_enhanced_los_window_does_not_block():
	"""P1-68: Window (blocks_los=false) should NOT block LoS"""
	var polygon = _make_rect_polygon(400, 400, 200, 200)
	var wall_start = Vector2(200, 200)
	var wall_end = Vector2(200, 600)
	var board = {
		"terrain_features": [_make_ruins_terrain_with_wall("tall", polygon, wall_start, wall_end, false)]
	}

	var shooter = _make_infantry_model(Vector2(100, 400))
	var target = _make_infantry_model(Vector2(400, 400))

	var result = EnhancedLineOfSight.check_enhanced_visibility(shooter, target, board)
	assert_true(result.has_los, "P1-68: Window (blocks_los=false) should not block LoS into ruins")

func test_enhanced_los_no_wall_no_blocking():
	"""Ruins without walls should follow normal ruins rules (see into OK)"""
	var polygon = _make_rect_polygon(400, 400, 200, 200)
	var board = {
		"terrain_features": [{
			"id": "test_ruins",
			"type": "ruins",
			"height_category": "tall",
			"polygon": polygon,
			"walls": []
		}]
	}

	var shooter = _make_infantry_model(Vector2(100, 400))
	var target = _make_infantry_model(Vector2(400, 400))

	var result = EnhancedLineOfSight.check_enhanced_visibility(shooter, target, board)
	assert_true(result.has_los, "Ruins without walls should allow seeing into ruins")

func test_enhanced_los_wall_not_on_sight_line():
	"""Wall that doesn't intersect the sight line should not block"""
	var polygon = _make_rect_polygon(400, 400, 200, 200)
	# Wall on the south face - not in the path of the sight line
	var wall_start = Vector2(200, 600)
	var wall_end = Vector2(600, 600)
	var board = {
		"terrain_features": [_make_ruins_terrain_with_wall("tall", polygon, wall_start, wall_end, true)]
	}

	var shooter = _make_infantry_model(Vector2(100, 400))
	var target = _make_infantry_model(Vector2(400, 400))

	var result = EnhancedLineOfSight.check_enhanced_visibility(shooter, target, board)
	assert_true(result.has_los, "Wall not on sight line should not block LoS")

# ==========================================
# BUG FIX: _segment_intersects_polygon point-in-polygon
# ==========================================

func test_segment_intersects_polygon_both_inside():
	"""P1-68: Segment with both endpoints inside polygon should return true"""
	var polygon = _make_rect_polygon(300, 300, 200, 200)
	var from = Vector2(250, 300)  # Inside
	var to = Vector2(350, 300)    # Also inside

	var intersects = EnhancedLineOfSight._segment_intersects_polygon(from, to, polygon)
	assert_true(intersects, "P1-68: Both endpoints inside should count as intersecting")

func test_segment_intersects_polygon_one_inside():
	"""Segment with one endpoint inside polygon should return true"""
	var polygon = _make_rect_polygon(300, 300, 100, 100)
	var from = Vector2(300, 300)  # Inside
	var to = Vector2(600, 300)    # Outside

	var intersects = EnhancedLineOfSight._segment_intersects_polygon(from, to, polygon)
	assert_true(intersects, "One endpoint inside should count as intersecting")

func test_segment_intersects_polygon_both_outside_crossing():
	"""Segment crossing polygon should return true (regression)"""
	var polygon = _make_rect_polygon(300, 300, 50, 50)
	var from = Vector2(100, 300)  # Outside, west
	var to = Vector2(500, 300)    # Outside, east

	var intersects = EnhancedLineOfSight._segment_intersects_polygon(from, to, polygon)
	assert_true(intersects, "Segment crossing polygon should return true (regression)")

func test_segment_intersects_polygon_both_outside_not_crossing():
	"""Segment not touching polygon should return false"""
	var polygon = _make_rect_polygon(300, 300, 50, 50)
	var from = Vector2(100, 100)
	var to = Vector2(500, 100)    # Above the polygon

	var intersects = EnhancedLineOfSight._segment_intersects_polygon(from, to, polygon)
	assert_false(intersects, "Segment not touching polygon should return false")

# ==========================================
# Wall blocking in non-ruins terrain
# ==========================================

func test_enhanced_los_wall_in_tall_obstacle():
	"""Wall inside tall non-ruins terrain should still block (terrain polygon already blocks)"""
	var polygon = _make_rect_polygon(400, 400, 100, 100)
	var board = {
		"terrain_features": [{
			"id": "tall_obstacle",
			"type": "obstacle",
			"height_category": "tall",
			"polygon": polygon,
			"walls": [{
				"id": "obstacle_wall",
				"start": Vector2(300, 300),
				"end": Vector2(300, 500),
				"type": "solid",
				"blocks_los": true
			}]
		}]
	}

	var shooter = _make_infantry_model(Vector2(100, 400))
	var target = _make_infantry_model(Vector2(700, 400))

	var result = EnhancedLineOfSight.check_enhanced_visibility(shooter, target, board)
	assert_false(result.has_los, "Tall obstacle with wall should block LoS")

# ==========================================
# Wall + ruins interaction edge cases
# ==========================================

func test_both_models_inside_ruins_wall_between():
	"""P1-68: Two models inside same ruins with wall between them should have LoS blocked"""
	# Large ruin containing both models
	var polygon = _make_rect_polygon(400, 400, 300, 200)
	# Wall cutting through the middle of the ruin (north-south)
	var wall_start = Vector2(400, 200)
	var wall_end = Vector2(400, 600)
	var board = {
		"terrain_features": [_make_ruins_terrain_with_wall("tall", polygon, wall_start, wall_end, true)]
	}

	var shooter = _make_infantry_model(Vector2(250, 400))  # Inside, west half
	var target = _make_infantry_model(Vector2(550, 400))   # Inside, east half

	var result = EnhancedLineOfSight.check_enhanced_visibility(shooter, target, board)
	assert_false(result.has_los, "P1-68: Wall between models inside same ruins should block LoS")

func test_enhanced_los_wall_in_low_terrain():
	"""P1-68: Wall in low terrain should still block LoS"""
	var polygon = _make_rect_polygon(400, 400, 100, 100)
	var board = {
		"terrain_features": [{
			"id": "low_terrain",
			"type": "ruins",
			"height_category": "low",
			"polygon": polygon,
			"walls": [{
				"id": "low_wall",
				"start": Vector2(400, 300),
				"end": Vector2(400, 500),
				"type": "solid",
				"blocks_los": true
			}]
		}]
	}

	var shooter = _make_infantry_model(Vector2(300, 400))
	var target = _make_infantry_model(Vector2(500, 400))

	var result = EnhancedLineOfSight.check_enhanced_visibility(shooter, target, board)
	assert_false(result.has_los, "P1-68: Wall in low terrain should still block LoS")
