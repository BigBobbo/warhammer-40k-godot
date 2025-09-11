extends GutTest

# Integration tests for terrain system with other game systems

func before_each():
	# Reset game state
	GameState.initialize_default_state()
	
	# Ensure terrain is loaded
	if TerrainManager:
		TerrainManager.load_terrain_layout("layout_2")

func test_shooting_with_terrain_blocking():
	# Setup units on opposite sides of tall terrain
	var shooter_unit = {
		"id": "U_SHOOTER",
		"owner": 1,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Test Shooter",
			"keywords": ["INFANTRY"],
			"stats": {"toughness": 4, "save": 3},
			"weapons": [{
				"name": "Bolt Rifle",
				"type": "Ranged",
				"range": "30",
				"attacks": "2",
				"bs": "3",
				"strength": "4",
				"ap": "1",
				"damage": "1"
			}]
		},
		"models": [
			{"id": "m1", "alive": true, "position": {"x": 200, "y": 500}, "wounds": 2, "current_wounds": 2}
		]
	}
	
	var target_unit = {
		"id": "U_TARGET",
		"owner": 2,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Test Target",
			"keywords": ["INFANTRY"],
			"stats": {"toughness": 4, "save": 4}
		},
		"models": [
			{"id": "m1", "alive": true, "position": {"x": 800, "y": 500}, "wounds": 1, "current_wounds": 1}
		]
	}
	
	GameState.set_unit("U_SHOOTER", shooter_unit)
	GameState.set_unit("U_TARGET", target_unit)
	
	# Get eligible targets (should be empty due to terrain blocking LoS)
	var board = GameState.create_snapshot()
	var eligible = RulesEngine.get_eligible_targets("U_SHOOTER", board)
	
	assert_eq(eligible.size(), 0, "No targets should be eligible when LoS is blocked by tall terrain")
	
	# Move target to where it's visible
	target_unit.models[0].position = {"x": 300, "y": 500}
	GameState.set_unit("U_TARGET", target_unit)
	board = GameState.create_snapshot()
	
	eligible = RulesEngine.get_eligible_targets("U_SHOOTER", board)
	assert_gt(eligible.size(), 0, "Target should be eligible when LoS is clear")

func test_movement_with_terrain_obstacles():
	# Setup a vehicle unit
	var vehicle_unit = {
		"id": "U_VEHICLE",
		"owner": 1,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Test Vehicle",
			"keywords": ["VEHICLE"],
			"stats": {"move": 10}
		},
		"models": [
			{"id": "m1", "alive": true, "position": {"x": 300, "y": 500}}
		]
	}
	
	GameState.set_unit("U_VEHICLE", vehicle_unit)
	
	# Create movement controller
	var movement_controller = preload("res://scripts/MovementController.gd").new()
	movement_controller.active_unit_id = "U_VEHICLE"
	
	# Test path through terrain (should fail for vehicles)
	var path = [
		Vector2(300, 500),  # Start
		Vector2(500, 500),  # Through terrain
		Vector2(700, 500)   # End
	]
	
	var valid = movement_controller._validate_terrain_traversal(path)
	assert_false(valid, "Vehicle should not be able to move through ruins terrain")
	
	# Test infantry movement (should succeed)
	var infantry_unit = {
		"id": "U_INFANTRY",
		"owner": 1,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Test Infantry",
			"keywords": ["INFANTRY"],
			"stats": {"move": 6}
		},
		"models": [
			{"id": "m1", "alive": true, "position": {"x": 300, "y": 500}}
		]
	}
	
	GameState.set_unit("U_INFANTRY", infantry_unit)
	movement_controller.active_unit_id = "U_INFANTRY"
	
	valid = movement_controller._validate_terrain_traversal(path)
	assert_true(valid, "Infantry should be able to move through ruins terrain")
	
	# Clean up
	movement_controller.queue_free()

func test_terrain_layout_2_setup():
	# Verify Layout 2 is loaded correctly
	assert_eq(TerrainManager.current_layout, "layout_2", "Layout 2 should be current")
	assert_eq(TerrainManager.terrain_features.size(), 12, "Layout 2 should have 12 terrain pieces")
	
	# Check terrain piece types
	var tall_count = 0
	var medium_count = 0
	var low_count = 0
	
	for terrain in TerrainManager.terrain_features:
		assert_eq(terrain.type, "ruins", "All terrain should be ruins type")
		
		match terrain.height_category:
			"tall":
				tall_count += 1
			"medium":
				medium_count += 1
			"low":
				low_count += 1
	
	assert_gt(tall_count, 0, "Should have at least some tall terrain")
	assert_gt(medium_count, 0, "Should have at least some medium terrain")
	assert_gt(low_count, 0, "Should have at least some low terrain")

func test_save_load_with_terrain():
	# Setup initial state with terrain
	var initial_terrain = TerrainManager.terrain_features.duplicate(true)
	assert_gt(initial_terrain.size(), 0, "Should have terrain loaded")
	
	# Create a save
	var save_data = StateSerializer.serialize_game_state()
	assert_not_null(save_data, "Save data should be created")
	
	# Parse and check terrain is included
	var json = JSON.new()
	var parse_result = json.parse(save_data)
	assert_eq(parse_result, OK, "Should parse save data successfully")
	
	var loaded_data = json.data
	assert_has(loaded_data.board, "terrain_features", "Save should include terrain_features")
	assert_eq(loaded_data.board.terrain_features.size(), initial_terrain.size(), 
		"Save should have same number of terrain pieces")
	
	# Clear terrain
	TerrainManager.terrain_features.clear()
	assert_eq(TerrainManager.terrain_features.size(), 0, "Terrain should be cleared")
	
	# Load the save
	var restored_state = StateSerializer.deserialize_game_state(save_data)
	GameState.load_from_snapshot(restored_state)
	
	# Verify terrain is restored
	assert_eq(TerrainManager.terrain_features.size(), initial_terrain.size(), 
		"Terrain should be restored after load")

func test_cover_saves_in_shooting():
	# Setup shooter and target with terrain providing cover
	var shooter_unit = {
		"id": "U_SHOOTER",
		"owner": 1,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Test Shooter",
			"keywords": ["INFANTRY"],
			"stats": {"toughness": 4, "save": 3}
		},
		"models": [
			{"id": "m1", "alive": true, "position": {"x": 200, "y": 500}}
		]
	}
	
	var target_unit = {
		"id": "U_TARGET", 
		"owner": 2,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Test Target",
			"keywords": ["INFANTRY"],
			"stats": {"toughness": 4, "save": 4}
		},
		"models": [
			{"id": "m1", "alive": true, "position": {"x": 500, "y": 500}, "wounds": 1, "current_wounds": 1}
		]
	}
	
	GameState.set_unit("U_SHOOTER", shooter_unit)
	GameState.set_unit("U_TARGET", target_unit)
	
	var board = GameState.create_snapshot()
	
	# Check target has cover (should be in terrain)
	var model = target_unit.models[0]
	var has_cover = RulesEngine._check_model_has_cover(model, "U_SHOOTER", board)
	assert_true(has_cover, "Target model at (500,500) should have cover from terrain")
	
	# Test save calculation with cover
	var base_save = 4
	var ap = 1
	var save_result = RulesEngine._calculate_save_needed(base_save, ap, has_cover, 0)
	
	# With AP-1, base save 4+ becomes 5+
	# With cover, it should improve by 1 (back to 4+)
	assert_eq(save_result.armour, 4, "Save should be 4+ with cover against AP-1")

func test_terrain_visual_creation():
	# Test that terrain visual can be created and added to scene
	var terrain_visual = preload("res://scripts/TerrainVisual.gd").new()
	assert_not_null(terrain_visual, "TerrainVisual should be created")
	
	# Check z-index is set correctly
	assert_eq(terrain_visual.z_index, -8, "Terrain should render above board but below deployment zones")
	
	# Clean up
	terrain_visual.queue_free()

func test_terrain_toggle_ui():
	# This would test the UI toggle functionality
	# In a real integration test, we'd create the Main scene and test the button
	# For now, just test the manager functionality
	
	assert_true(TerrainManager.terrain_visible, "Terrain should be visible by default")
	
	TerrainManager.toggle_terrain_visibility()
	assert_false(TerrainManager.terrain_visible, "Terrain should be hidden after toggle")
	
	TerrainManager.toggle_terrain_visibility()
	assert_true(TerrainManager.terrain_visible, "Terrain should be visible after second toggle")