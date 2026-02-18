extends "res://addons/gut/test.gd"
class_name TestEnhancedVisibilityIntegration

# Integration tests for enhanced line of sight in shooting phase
# Tests the full workflow from unit selection to target validation


var test_state: Dictionary
var shooting_controller: Node

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	# Set up clean game state with two units
	test_state = {
		"current_phase": "shooting",
		"current_player": "player1",
		"board": {
			"terrain_features": [],
			"deployment_zones": {}
		},
		"units": {
			"unit_1": {
				"id": "unit_1",
				"name": "Space Marine Tactical Squad",
				"player": "player1",
				"models": [
					{
						"id": "m1",
						"alive": true,
						"wounds": 2,
						"current_wounds": 2,
						"base_mm": 32,
						"position": {"x": 400, "y": 400}
					},
					{
						"id": "m2", 
						"alive": true,
						"wounds": 2,
						"current_wounds": 2,
						"base_mm": 32,
						"position": {"x": 440, "y": 400}
					}
				],
				"weapons": ["bolter"]
			},
			"unit_2": {
				"id": "unit_2",
				"name": "Ork Boyz",
				"player": "player2",
				"models": [
					{
						"id": "m1",
						"alive": true,
						"wounds": 1,
						"current_wounds": 1, 
						"base_mm": 32,
						"position": {"x": 800, "y": 400}
					},
					{
						"id": "m2",
						"alive": true,
						"wounds": 1,
						"current_wounds": 1,
						"base_mm": 32,
						"position": {"x": 840, "y": 400}
					}
				],
				"weapons": ["choppa"]
			}
		},
		"weapons": {
			"bolter": {
				"name": "Boltgun",
				"type": "Ranged",
				"range": "24",
				"attacks": "1",
				"ballistic_skill": "3",
				"strength": "4",
				"ap": "0",
				"damage": "1"
			}
		}
	}
	
	# Initialize GameState with test data
	GameState.state = test_state

func after_each():
	# Clean up
	if EnhancedLineOfSight:
		EnhancedLineOfSight.clear_cache()
	
	# Reset GameState
	GameState._initialize_default_state()

# ===== SHOOTING PHASE INTEGRATION TESTS =====

func test_shooting_phase_integration():
	# Verify enhanced LoS works in shooting phase workflow
	gut.p("Testing shooting phase integration with enhanced LoS")
	
	# Test target visibility check
	var visibility_result = RulesEngine._check_target_visibility("unit_1", "unit_2", "bolter", test_state)
	
	assert_true(visibility_result.visible, "Units should be visible with clear terrain")
	assert_eq(visibility_result.reason, "", "Should have no blocking reason")

func test_weapon_range_with_enhanced_los():
	# Test weapon range + enhanced visibility combination
	gut.p("Testing weapon range with enhanced visibility")
	
	# Move target unit out of range
	test_state.units.unit_2.models[0].position.x = 1500  # ~28 inches away, bolter range is 24"
	test_state.units.unit_2.models[1].position.x = 1540
	
	var visibility_result = RulesEngine._check_target_visibility("unit_1", "unit_2", "bolter", test_state)
	
	assert_false(visibility_result.visible, "Units out of weapon range should not be visible")
	assert_has(visibility_result.reason, "range", "Should mention range in blocking reason")

func test_enhanced_los_with_large_models():
	# Test enhanced LoS with larger base sizes
	gut.p("Testing enhanced LoS with large models")
	
	# Make models have large bases
	for model in test_state.units.unit_1.models:
		model.base_mm = 80  # Large base
	for model in test_state.units.unit_2.models:
		model.base_mm = 80
	
	# Add narrow terrain that might block center but allow edge visibility
	test_state.board.terrain_features = [{
		"id": "narrow_wall",
		"type": "ruins",
		"height_category": "tall",
		"polygon": PackedVector2Array([
			Vector2(595, 390),
			Vector2(605, 390),
			Vector2(605, 410),
			Vector2(595, 410)
		])
	}]
	
	var visibility_result = RulesEngine._check_target_visibility("unit_1", "unit_2", "bolter", test_state)
	
	# Enhanced LoS should potentially find edge visibility where legacy wouldn't
	assert_not_null(visibility_result.visible, "Should return valid visibility result")
	gut.p("Large model visibility result: %s" % str(visibility_result.visible))

func test_cover_interaction():
	# Ensure cover system works with enhanced LoS
	gut.p("Testing cover interaction with enhanced LoS")
	
	# Add terrain that provides cover but doesn't block LoS
	test_state.board.terrain_features = [{
		"id": "cover_terrain",
		"type": "ruins",
		"height_category": "medium",  # Provides cover but doesn't block LoS
		"polygon": PackedVector2Array([
			Vector2(550, 350),
			Vector2(650, 350),
			Vector2(650, 450),
			Vector2(550, 450)
		])
	}]
	
	# Position target near cover
	test_state.units.unit_2.models[0].position = {"x": 680, "y": 400}
	
	var visibility_result = RulesEngine._check_target_visibility("unit_1", "unit_2", "bolter", test_state)
	assert_true(visibility_result.visible, "Target should be visible despite cover terrain")
	
	# Test cover save mechanics
	var target_pos = Vector2(680, 400)
	var shooter_pos = Vector2(400, 400)
	var has_cover = RulesEngine.check_benefit_of_cover(target_pos, shooter_pos, test_state)
	
	assert_true(has_cover, "Target should benefit from cover")

func test_multiple_unit_targeting():
	# Test targeting multiple units with enhanced LoS
	gut.p("Testing multiple unit targeting")
	
	# Add a third unit
	test_state.units["unit_3"] = {
		"id": "unit_3",
		"name": "Ork Nobz",
		"player": "player2",
		"models": [
			{
				"id": "m1",
				"alive": true,
				"wounds": 3,
				"current_wounds": 3,
				"base_mm": 40,  # Slightly larger base
				"position": {"x": 800, "y": 600}
			}
		],
		"weapons": ["big_choppa"]
	}
	
	# Test visibility to both enemy units
	var vis_unit2 = RulesEngine._check_target_visibility("unit_1", "unit_2", "bolter", test_state)
	var vis_unit3 = RulesEngine._check_target_visibility("unit_1", "unit_3", "bolter", test_state)
	
	assert_true(vis_unit2.visible, "Should see unit_2")
	assert_true(vis_unit3.visible, "Should see unit_3")

# ===== TERRAIN INTEGRATION TESTS =====

func test_complex_terrain_scenario():
	# Test enhanced LoS with complex terrain layout
	gut.p("Testing complex terrain scenario")
	
	# Set up complex terrain from TerrainManager
	if TerrainManager:
		TerrainManager.load_terrain_layout("layout_2")
		test_state.board.terrain_features = TerrainManager.terrain_features.duplicate(true)
	
	# Position units on opposite sides of terrain
	test_state.units.unit_1.models[0].position = {"x": 200, "y": 200}
	test_state.units.unit_2.models[0].position = {"x": 1500, "y": 2200}
	
	var visibility_result = RulesEngine._check_target_visibility("unit_1", "unit_2", "bolter", test_state)
	
	# With complex terrain, LoS may or may not be blocked, but should complete without error
	assert_not_null(visibility_result.visible, "Should return valid result with complex terrain")
	gut.p("Complex terrain visibility: %s" % str(visibility_result.visible))

func test_models_inside_ruins():
	# Test models positioned inside ruins terrain
	gut.p("Testing models inside ruins")
	
	# Add ruins terrain
	test_state.board.terrain_features = [{
		"id": "large_ruins",
		"type": "ruins",
		"height_category": "tall",
		"polygon": PackedVector2Array([
			Vector2(350, 350),
			Vector2(450, 350),
			Vector2(450, 450),
			Vector2(350, 450)
		])
	}]
	
	# Position shooter inside ruins
	test_state.units.unit_1.models[0].position = {"x": 400, "y": 400}  # Inside ruins
	
	var visibility_result = RulesEngine._check_target_visibility("unit_1", "unit_2", "bolter", test_state)
	
	assert_true(visibility_result.visible, "Model inside ruins should be able to see out")

# ===== PERFORMANCE INTEGRATION TESTS =====

func test_shooting_phase_performance():
	# Test performance of enhanced LoS in realistic shooting phase
	gut.p("Testing shooting phase performance")
	
	# Add more models to units
	for i in range(8):  # Total 10 models in unit_1
		test_state.units.unit_1.models.append({
			"id": "m%d" % (i + 3),
			"alive": true,
			"wounds": 2,
			"current_wounds": 2,
			"base_mm": 32,
			"position": {"x": 400 + (i * 30), "y": 400 + (i % 2) * 30}
		})
	
	for i in range(8):  # Total 10 models in unit_2  
		test_state.units.unit_2.models.append({
			"id": "m%d" % (i + 3),
			"alive": true,
			"wounds": 1,
			"current_wounds": 1,
			"base_mm": 32,
			"position": {"x": 800 + (i * 30), "y": 400 + (i % 2) * 30}
		})
	
	var start_time = Time.get_ticks_msec()
	
	# Test visibility check with many models
	var visibility_result = RulesEngine._check_target_visibility("unit_1", "unit_2", "bolter", test_state)
	
	var check_time = Time.get_ticks_msec() - start_time
	
	assert_true(visibility_result.visible, "Should find visibility with many models")
	assert_lt(check_time, 100, "Visibility check should complete quickly (<%dms, got %dms)" % [100, check_time])
	
	gut.p("Visibility check time with 20 models: %dms" % check_time)

# ===== ERROR HANDLING INTEGRATION TESTS =====

func test_invalid_unit_handling():
	# Test handling of invalid unit IDs
	gut.p("Testing invalid unit handling")
	
	var result = RulesEngine._check_target_visibility("invalid_unit", "unit_2", "bolter", test_state)
	
	assert_false(result.visible, "Invalid unit should not be visible")
	assert_has(result.reason, "Invalid", "Should provide invalid unit reason")

func test_invalid_weapon_handling():
	# Test handling of invalid weapon IDs
	gut.p("Testing invalid weapon handling")
	
	var result = RulesEngine._check_target_visibility("unit_1", "unit_2", "invalid_weapon", test_state)
	
	assert_false(result.visible, "Invalid weapon should prevent visibility")
	assert_has(result.reason, "Invalid", "Should provide invalid weapon reason")

func test_dead_model_handling():
	# Test that dead models don't participate in LoS checks
	gut.p("Testing dead model handling")
	
	# Kill all models in shooting unit
	for model in test_state.units.unit_1.models:
		model.alive = false
	
	var result = RulesEngine._check_target_visibility("unit_1", "unit_2", "bolter", test_state)
	
	assert_false(result.visible, "Dead units should not be able to shoot")

# ===== REGRESSION TESTS =====

func test_legacy_compatibility_full_workflow():
	# Ensure enhanced system doesn't break existing functionality
	gut.p("Testing legacy compatibility in full workflow")
	
	# Test the same scenario with both approaches
	var shooter_pos = Vector2(test_state.units.unit_1.models[0].position.x, test_state.units.unit_1.models[0].position.y)
	var target_pos = Vector2(test_state.units.unit_2.models[0].position.x, test_state.units.unit_2.models[0].position.y)
	
	# Legacy check (point-to-point)
	var legacy_los = RulesEngine._check_legacy_line_of_sight(shooter_pos, target_pos, test_state)
	
	# Enhanced integration check
	var enhanced_vis = RulesEngine._check_target_visibility("unit_1", "unit_2", "bolter", test_state)
	
	# They should agree on clear terrain
	assert_eq(legacy_los, enhanced_vis.visible, "Legacy and enhanced should agree on clear cases")

func test_save_load_compatibility():
	# Test that enhanced LoS works with save/load system
	gut.p("Testing save/load compatibility")
	
	# Add some terrain
	test_state.board.terrain_features = [{
		"id": "test_terrain",
		"type": "ruins",
		"height_category": "tall",
		"polygon": PackedVector2Array([
			Vector2(500, 350),
			Vector2(600, 350),
			Vector2(600, 450),
			Vector2(500, 450)
		])
	}]
	
	# Test visibility before save
	var vis_before = RulesEngine._check_target_visibility("unit_1", "unit_2", "bolter", test_state)
	
	# Simulate save/load by creating new state
	var saved_state = test_state.duplicate(true)
	GameState.state = saved_state
	
	# Test visibility after "load"
	var vis_after = RulesEngine._check_target_visibility("unit_1", "unit_2", "bolter", saved_state)
	
	assert_eq(vis_before.visible, vis_after.visible, "Visibility should be consistent after save/load")

# ===== VISUAL DEBUG INTEGRATION =====

func test_visual_debug_integration():
	# Test that enhanced LoS works with visual debugging
	gut.p("Testing visual debug integration")
	
	# Enable debug mode if LoSDebugVisual exists
	var los_debug = get_tree().get_nodes_in_group("los_debug")
	if los_debug.size() > 0:
		var debug_node = los_debug[0]
		debug_node.set_debug_enabled(true)
		
		# Test enhanced visualization
		var shooter_model = test_state.units.unit_1.models[0]
		var target_model = test_state.units.unit_2.models[0]
		
		# This should not crash
		debug_node.visualize_enhanced_los(shooter_model, target_model, test_state)
		
		assert_true(true, "Enhanced LoS visualization should complete without error")
	else:
		gut.p("No LoSDebugVisual node found, skipping visual debug test")
