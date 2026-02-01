extends "res://addons/gut/test.gd"

# Unit tests for wall mechanics in terrain system

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

func test_vehicle_cannot_cross_wall():
	var wall = {
		"start": Vector2(100, 100),
		"end": Vector2(200, 100),
		"blocks_movement": {"VEHICLE": true}
	}

	var can_cross = TerrainManager.can_unit_cross_wall(["VEHICLE"], wall)
	assert_false(can_cross, "Vehicles should not cross walls")

func test_infantry_can_cross_wall():
	var wall = {
		"start": Vector2(100, 100),
		"end": Vector2(200, 100),
		"blocks_movement": {"INFANTRY": false}
	}

	var can_cross = TerrainManager.can_unit_cross_wall(["INFANTRY"], wall)
	assert_true(can_cross, "Infantry should cross walls")

func test_monster_cannot_cross_wall():
	var wall = {
		"start": Vector2(100, 100),
		"end": Vector2(200, 100),
		"blocks_movement": {"MONSTER": true}
	}

	var can_cross = TerrainManager.can_unit_cross_wall(["MONSTER"], wall)
	assert_false(can_cross, "Monsters should not cross walls")

func test_flying_unit_can_cross_wall():
	var wall = {
		"start": Vector2(100, 100),
		"end": Vector2(200, 100),
		"blocks_movement": {"VEHICLE": true, "INFANTRY": false}
	}

	# FLY keyword allows crossing walls
	var can_cross = TerrainManager.can_unit_cross_wall(["VEHICLE", "FLY"], wall)
	assert_true(can_cross, "Flying vehicles should cross walls")

func test_wall_intersection_detection():
	var wall = {
		"start": Vector2(100, 100),
		"end": Vector2(200, 100)
	}

	# Path that crosses the wall
	var intersects = TerrainManager.check_line_intersects_wall(
		Vector2(150, 50), Vector2(150, 150), wall
	)
	assert_true(intersects, "Should detect line crossing wall")

	# Path that doesn't cross the wall
	var no_intersect = TerrainManager.check_line_intersects_wall(
		Vector2(50, 50), Vector2(50, 150), wall
	)
	assert_false(no_intersect, "Should not detect line not crossing wall")

func test_wall_blocks_line_of_sight():
	# Setup terrain with a solid wall
	var terrain = {
		"id": "test_terrain",
		"walls": [
			{
				"start": Vector2(100, 100),
				"end": Vector2(200, 100),
				"blocks_los": true  # Solid wall blocks LoS
			}
		]
	}

	# Test LoS blocked by wall
	var blocked = LineOfSightCalculator._walls_block_los(
		Vector2(150, 50),   # Shooter position
		Vector2(150, 150),  # Target position
		terrain
	)
	assert_true(blocked, "Solid wall should block line of sight")

func test_window_allows_line_of_sight():
	# Setup terrain with a window
	var terrain = {
		"id": "test_terrain",
		"walls": [
			{
				"start": Vector2(100, 100),
				"end": Vector2(200, 100),
				"type": "window",
				"blocks_los": false  # Windows don't block LoS
			}
		]
	}

	# Test LoS not blocked by window
	var blocked = LineOfSightCalculator._walls_block_los(
		Vector2(150, 50),   # Shooter position
		Vector2(150, 150),  # Target position
		terrain
	)
	assert_false(blocked, "Window should not block line of sight")

func test_add_wall_to_terrain():
	# Setup TerrainManager
	TerrainManager.terrain_features = [
		{
			"id": "test_terrain",
			"type": "ruins"
		}
	]

	# Add a wall
	var wall_data = {
		"id": "test_wall",
		"start": Vector2(100, 100),
		"end": Vector2(200, 100),
		"type": "solid",
		"blocks_movement": {"VEHICLE": true}
	}

	TerrainManager.add_wall_to_terrain("test_terrain", wall_data)

	# Verify wall was added
	var terrain = TerrainManager.terrain_features[0]
	assert_true(terrain.has("walls"), "Terrain should have walls array")
	assert_eq(terrain.walls.size(), 1, "Should have one wall")
	assert_eq(terrain.walls[0].id, "test_wall", "Wall should have correct id")

func test_multiple_wall_types():
	# Test different wall types have correct properties
	var solid_wall = {
		"type": "solid",
		"blocks_movement": {"INFANTRY": false, "VEHICLE": true, "MONSTER": true},
		"blocks_los": true
	}

	var window = {
		"type": "window",
		"blocks_movement": {"INFANTRY": false, "VEHICLE": true, "MONSTER": true},
		"blocks_los": false
	}

	var door = {
		"type": "door",
		"blocks_movement": {"INFANTRY": false, "VEHICLE": true, "MONSTER": true},
		"blocks_los": false
	}

	# Infantry can pass all wall types
	assert_true(TerrainManager.can_unit_cross_wall(["INFANTRY"], solid_wall))
	assert_true(TerrainManager.can_unit_cross_wall(["INFANTRY"], window))
	assert_true(TerrainManager.can_unit_cross_wall(["INFANTRY"], door))

	# Vehicles cannot pass any wall types (unless flying)
	assert_false(TerrainManager.can_unit_cross_wall(["VEHICLE"], solid_wall))
	assert_false(TerrainManager.can_unit_cross_wall(["VEHICLE"], window))
	assert_false(TerrainManager.can_unit_cross_wall(["VEHICLE"], door))

func test_wall_visual_creation():
	var wall_visual = WallVisual.new()

	var wall_data = {
		"start": Vector2(100, 100),
		"end": Vector2(200, 100),
		"type": "solid"
	}

	wall_visual.add_wall(wall_data)

	# Check that a Line2D was created
	assert_eq(wall_visual.wall_lines.size(), 1, "Should have one wall line")
	assert_eq(wall_visual.get_child_count(), 1, "Should have one child Line2D")

	# Clean up
	wall_visual.queue_free()

func test_parallel_walls_no_intersection():
	var wall1 = {
		"start": Vector2(100, 100),
		"end": Vector2(200, 100)
	}

	var wall2 = {
		"start": Vector2(100, 200),
		"end": Vector2(200, 200)
	}

	# Line parallel to walls shouldn't intersect
	var no_intersect1 = TerrainManager.check_line_intersects_wall(
		Vector2(50, 150), Vector2(250, 150), wall1
	)
	assert_false(no_intersect1, "Parallel line shouldn't intersect wall1")

	var no_intersect2 = TerrainManager.check_line_intersects_wall(
		Vector2(50, 150), Vector2(250, 150), wall2
	)
	assert_false(no_intersect2, "Parallel line shouldn't intersect wall2")