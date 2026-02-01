extends "res://addons/gut/test.gd"

# Unit tests for terrain system functionality

var test_board: Dictionary

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	test_board = {
		"units": {},
		"terrain_features": [],
		"board": {}
	}

func test_line_of_sight_blocked_by_tall_terrain():
	# Add tall terrain between two positions
	test_board.terrain_features = [{
		"id": "test_terrain",
		"type": "ruins",
		"polygon": PackedVector2Array([
			Vector2(400, 400),
			Vector2(600, 400),
			Vector2(600, 600),
			Vector2(400, 600)
		]),
		"height_category": "tall"
	}]
	
	# Test positions on either side of terrain
	var shooter_pos = Vector2(200, 500)  # Left of terrain
	var target_pos = Vector2(800, 500)   # Right of terrain
	
	# Check that LoS is blocked
	var has_los = RulesEngine._check_line_of_sight(shooter_pos, target_pos, test_board)
	assert_false(has_los, "Line of sight should be blocked by tall terrain")
	
	# Test positions where both are inside terrain (should have LoS)
	var inside_pos1 = Vector2(450, 450)
	var inside_pos2 = Vector2(550, 550)
	
	has_los = RulesEngine._check_line_of_sight(inside_pos1, inside_pos2, test_board)
	assert_true(has_los, "Models inside same terrain should have LoS to each other")

func test_line_of_sight_not_blocked_by_low_terrain():
	# Add low terrain
	test_board.terrain_features = [{
		"id": "test_terrain",
		"type": "ruins",
		"polygon": PackedVector2Array([
			Vector2(400, 400),
			Vector2(600, 400),
			Vector2(600, 600),
			Vector2(400, 600)
		]),
		"height_category": "low"
	}]
	
	# Test positions on either side
	var shooter_pos = Vector2(200, 500)
	var target_pos = Vector2(800, 500)
	
	# Check that LoS is NOT blocked by low terrain
	var has_los = RulesEngine._check_line_of_sight(shooter_pos, target_pos, test_board)
	assert_true(has_los, "Line of sight should NOT be blocked by low terrain")

func test_benefit_of_cover_within_terrain():
	# Add ruins terrain
	test_board.terrain_features = [{
		"id": "test_terrain",
		"type": "ruins",
		"polygon": PackedVector2Array([
			Vector2(400, 400),
			Vector2(600, 400),
			Vector2(600, 600),
			Vector2(400, 600)
		]),
		"height_category": "tall"
	}]
	
	# Test model inside terrain
	var target_pos = Vector2(500, 500)  # Inside terrain
	var shooter_pos = Vector2(200, 500)  # Outside terrain
	
	var has_cover = RulesEngine.check_benefit_of_cover(target_pos, shooter_pos, test_board)
	assert_true(has_cover, "Model within ruins should have benefit of cover")

func test_benefit_of_cover_behind_terrain():
	# Add ruins terrain
	test_board.terrain_features = [{
		"id": "test_terrain",
		"type": "ruins",
		"polygon": PackedVector2Array([
			Vector2(400, 400),
			Vector2(600, 400),
			Vector2(600, 600),
			Vector2(400, 600)
		]),
		"height_category": "tall"
	}]
	
	# Test model behind terrain (LoS crosses terrain)
	var shooter_pos = Vector2(200, 500)  # Left of terrain
	var target_pos = Vector2(700, 500)   # Right of terrain (behind it)
	
	var has_cover = RulesEngine.check_benefit_of_cover(target_pos, shooter_pos, test_board)
	assert_true(has_cover, "Model behind ruins should have benefit of cover")
	
	# Test model in the open
	var open_pos = Vector2(200, 200)  # Nowhere near terrain
	has_cover = RulesEngine.check_benefit_of_cover(open_pos, shooter_pos, test_board)
	assert_false(has_cover, "Model in the open should NOT have benefit of cover")

func test_segment_intersects_polygon():
	var polygon = PackedVector2Array([
		Vector2(100, 100),
		Vector2(200, 100),
		Vector2(200, 200),
		Vector2(100, 200)
	])
	
	# Test line that crosses polygon
	var crosses = RulesEngine._segment_intersects_polygon(
		Vector2(50, 150),   # Start outside
		Vector2(250, 150),  # End outside on other side
		polygon
	)
	assert_true(crosses, "Line crossing polygon should intersect")
	
	# Test line that doesn't cross
	var misses = RulesEngine._segment_intersects_polygon(
		Vector2(50, 50),    # Start outside
		Vector2(250, 50),   # End outside, parallel to polygon
		polygon
	)
	assert_false(misses, "Line missing polygon should not intersect")

func test_point_in_polygon():
	var polygon = PackedVector2Array([
		Vector2(100, 100),
		Vector2(200, 100),
		Vector2(200, 200),
		Vector2(100, 200)
	])
	
	# Test point inside
	var inside = RulesEngine._point_in_polygon(Vector2(150, 150), polygon)
	assert_true(inside, "Point inside polygon should return true")
	
	# Test point outside
	var outside = RulesEngine._point_in_polygon(Vector2(50, 50), polygon)
	assert_false(outside, "Point outside polygon should return false")
	
	# Test point on edge (implementation dependent)
	var on_edge = RulesEngine._point_in_polygon(Vector2(100, 150), polygon)
	# Edge behavior varies by implementation, just check it doesn't crash
	assert_not_null(on_edge, "Point on edge should return a valid result")

func test_terrain_manager_initialization():
	# Test that TerrainManager loads terrain features
	assert_not_null(TerrainManager, "TerrainManager should be loaded")
	assert_gt(TerrainManager.terrain_features.size(), 0, "TerrainManager should have terrain features loaded")
	
	# Test Layout 2 has correct number of pieces
	var expected_pieces = 12  # 4 + 2 + 6 from Layout 2
	assert_eq(TerrainManager.terrain_features.size(), expected_pieces, 
		"Layout 2 should have exactly 12 terrain pieces")

func test_terrain_manager_can_move_through():
	var terrain_piece = {
		"type": "ruins",
		"can_move_through": {
			"INFANTRY": true,
			"VEHICLE": false,
			"MONSTER": false
		}
	}
	
	# Test infantry can move through
	var infantry_keywords = ["INFANTRY", "PRIMARIS"]
	var can_move = TerrainManager.can_unit_move_through_terrain(infantry_keywords, terrain_piece)
	assert_true(can_move, "Infantry should be able to move through ruins")
	
	# Test vehicles cannot
	var vehicle_keywords = ["VEHICLE", "TRANSPORT"]
	can_move = TerrainManager.can_unit_move_through_terrain(vehicle_keywords, terrain_piece)
	assert_false(can_move, "Vehicles should NOT be able to move through ruins")
	
	# Test monsters cannot
	var monster_keywords = ["MONSTER", "TITANIC"]
	can_move = TerrainManager.can_unit_move_through_terrain(monster_keywords, terrain_piece)
	assert_false(can_move, "Monsters should NOT be able to move through ruins")

func test_terrain_manager_check_line_intersects():
	var terrain_piece = {
		"polygon": PackedVector2Array([
			Vector2(400, 400),
			Vector2(600, 400),
			Vector2(600, 600),
			Vector2(400, 600)
		])
	}
	
	# Test line that crosses terrain
	var intersects = TerrainManager.check_line_intersects_terrain(
		Vector2(300, 500),
		Vector2(700, 500),
		terrain_piece
	)
	assert_true(intersects, "Line crossing terrain should intersect")
	
	# Test line that misses
	var misses = TerrainManager.check_line_intersects_terrain(
		Vector2(300, 300),
		Vector2(700, 300),
		terrain_piece
	)
	assert_false(misses, "Line missing terrain should not intersect")

func test_unit_has_cover():
	# Setup test units
	test_board.units = {
		"shooter": {
			"owner": 1,
			"models": [
				{"id": "m1", "alive": true, "position": {"x": 200, "y": 500}}
			]
		},
		"target": {
			"owner": 2,
			"models": [
				{"id": "m1", "alive": true, "position": {"x": 500, "y": 500}},  # In terrain
				{"id": "m2", "alive": true, "position": {"x": 100, "y": 100}}   # In open
			]
		}
	}
	
	# Add terrain
	test_board.terrain_features = [{
		"type": "ruins",
		"polygon": PackedVector2Array([
			Vector2(400, 400),
			Vector2(600, 400),
			Vector2(600, 600),
			Vector2(400, 600)
		])
	}]
	
	# Check if unit has cover (majority of models)
	var has_cover = RulesEngine.check_unit_has_cover("target", "shooter", test_board)
	assert_false(has_cover, "Unit should NOT have cover when only 1 of 2 models is in cover")
	
	# Move second model into cover
	test_board.units.target.models[1].position = {"x": 450, "y": 450}
	has_cover = RulesEngine.check_unit_has_cover("target", "shooter", test_board)
	assert_true(has_cover, "Unit should have cover when both models are in cover")