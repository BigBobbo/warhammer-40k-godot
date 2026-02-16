extends SceneTree

# Test script for AI deployment collision detection
# Run: godot --headless --script tests/unit/test_ai_deployment_collision.gd

const PIXELS_PER_INCH: float = 40.0

func _init():
	print("=== AI Deployment Collision Test ===")
	var pass_count = 0
	var fail_count = 0

	# Test 1: _model_bounding_radius_px for circular base
	var radius_32mm = AIDecisionMaker._model_bounding_radius_px(32, "circular", {})
	var expected_radius = (32.0 / 2.0) * (PIXELS_PER_INCH / 25.4)
	if absf(radius_32mm - expected_radius) < 0.1:
		print("PASS: Circular 32mm base radius = %.2f px" % radius_32mm)
		pass_count += 1
	else:
		print("FAIL: Circular 32mm base radius = %.2f px, expected %.2f" % [radius_32mm, expected_radius])
		fail_count += 1

	# Test 2: _model_bounding_radius_px for rectangular base
	var radius_rect = AIDecisionMaker._model_bounding_radius_px(100, "rectangular", {"length": 100, "width": 60})
	var diag = sqrt(100.0*100.0 + 60.0*60.0)
	var expected_rect = (diag / 2.0) * (PIXELS_PER_INCH / 25.4)
	if absf(radius_rect - expected_rect) < 0.1:
		print("PASS: Rectangular 100x60mm base radius = %.2f px" % radius_rect)
		pass_count += 1
	else:
		print("FAIL: Rectangular 100x60mm base radius = %.2f px, expected %.2f" % [radius_rect, expected_rect])
		fail_count += 1

	# Test 3: _position_collides_with_deployed - collision case
	var deployed = [{"position": Vector2(100, 100), "base_mm": 32, "base_type": "circular", "base_dimensions": {}}]
	var collides = AIDecisionMaker._position_collides_with_deployed(Vector2(110, 100), 32, deployed, 4.0)
	if collides:
		print("PASS: Position (110,100) correctly collides with model at (100,100) for 32mm bases")
		pass_count += 1
	else:
		print("FAIL: Position (110,100) should collide with model at (100,100) for 32mm bases")
		fail_count += 1

	# Test 4: _position_collides_with_deployed - no collision case
	var no_collide = AIDecisionMaker._position_collides_with_deployed(Vector2(200, 100), 32, deployed, 4.0)
	if not no_collide:
		print("PASS: Position (200,100) correctly does not collide with model at (100,100)")
		pass_count += 1
	else:
		print("FAIL: Position (200,100) should not collide with model at (100,100)")
		fail_count += 1

	# Test 5: _get_all_deployed_model_positions with empty snapshot
	var empty_snapshot = {"units": {}}
	var positions = AIDecisionMaker._get_all_deployed_model_positions(empty_snapshot)
	if positions.size() == 0:
		print("PASS: Empty snapshot returns 0 deployed positions")
		pass_count += 1
	else:
		print("FAIL: Empty snapshot should return 0 deployed positions, got %d" % positions.size())
		fail_count += 1

	# Test 6: _get_all_deployed_model_positions with deployed models
	var snapshot_with_deployed = {
		"units": {
			"unit1": {
				"status": 2,  # DEPLOYED (UnitStatus enum: UNDEPLOYED=0, DEPLOYING=1, DEPLOYED=2)
				"models": [
					{"alive": true, "position": {"x": 100, "y": 200}, "base_mm": 32, "base_type": "circular"},
					{"alive": true, "position": {"x": 150, "y": 200}, "base_mm": 32, "base_type": "circular"}
				]
			},
			"unit2": {
				"status": 0,  # UNDEPLOYED
				"models": [
					{"alive": true, "base_mm": 32, "base_type": "circular"}  # no position
				]
			}
		}
	}
	var deployed_pos = AIDecisionMaker._get_all_deployed_model_positions(snapshot_with_deployed)
	if deployed_pos.size() == 2:
		print("PASS: Snapshot with 2 deployed models returns 2 positions")
		pass_count += 1
	else:
		print("FAIL: Expected 2 deployed positions, got %d" % deployed_pos.size())
		fail_count += 1

	# Test 7: _resolve_formation_collisions - no collisions
	var zone = {"min_x": 0.0, "max_x": 1000.0, "min_y": 0.0, "max_y": 500.0}
	var formation_pos = [Vector2(200, 200), Vector2(300, 200)]
	var resolved = AIDecisionMaker._resolve_formation_collisions(formation_pos, 32, [], zone)
	if resolved.size() == 2 and resolved[0].distance_to(Vector2(200, 200)) < 1.0:
		print("PASS: No-collision formation keeps original positions")
		pass_count += 1
	else:
		print("FAIL: No-collision formation should keep original positions")
		fail_count += 1

	# Test 8: _resolve_formation_collisions - with collision
	var blocking_models = [{"position": Vector2(200, 200), "base_mm": 32, "base_type": "circular", "base_dimensions": {}}]
	var collision_pos = [Vector2(210, 200), Vector2(500, 200)]
	var resolved2 = AIDecisionMaker._resolve_formation_collisions(collision_pos, 32, blocking_models, zone)
	if resolved2.size() == 2:
		# First position should have been moved
		var moved_dist = resolved2[0].distance_to(Vector2(210, 200))
		if moved_dist > 5.0:
			print("PASS: Colliding position was moved (%.1f px away from original)" % moved_dist)
			pass_count += 1
		else:
			print("FAIL: Colliding position should have been moved, only moved %.1f px" % moved_dist)
			fail_count += 1
		# Second position should stay roughly the same
		if resolved2[1].distance_to(Vector2(500, 200)) < 1.0:
			print("PASS: Non-colliding position stayed at original")
			pass_count += 1
		else:
			print("FAIL: Non-colliding position should stay at original")
			fail_count += 1
	else:
		print("FAIL: resolve_formation_collisions should return 2 positions, got %d" % resolved2.size())
		fail_count += 2

	# Test 9: _generate_formation_positions
	var centroid = Vector2(500, 250)
	var gen_pos = AIDecisionMaker._generate_formation_positions(centroid, 5, 32, zone)
	if gen_pos.size() == 5:
		print("PASS: Generated 5 formation positions")
		pass_count += 1
		# Verify all are within zone bounds
		var all_in_zone = true
		for p in gen_pos:
			if p.x < zone.min_x or p.x > zone.max_x or p.y < zone.min_y or p.y > zone.max_y:
				all_in_zone = false
				break
		if all_in_zone:
			print("PASS: All formation positions within zone bounds")
			pass_count += 1
		else:
			print("FAIL: Some formation positions outside zone bounds")
			fail_count += 1
	else:
		print("FAIL: Expected 5 formation positions, got %d" % gen_pos.size())
		fail_count += 2

	# Test 10: Deployment spread logic - simulate multiple units deploying
	# Simulate the column-based distribution
	var test_zone = {"min_x": 40.0, "max_x": 1720.0, "min_y": 10.0, "max_y": 470.0}
	var all_deployed: Array = []
	var deploy_success_count = 0
	var num_test_units = 7  # Same as Adeptus Custodes army

	for idx in range(num_test_units):
		var zone_width = test_zone.max_x - test_zone.min_x
		var num_columns = maxi(3, mini(5, num_test_units))
		var col_width = zone_width / num_columns
		var col_index = idx % num_columns
		var depth_row = idx / num_columns
		var col_center_x = test_zone.min_x + col_width * (col_index + 0.5)
		var depth_step = mini(200, int((test_zone.max_y - test_zone.min_y) / 3.0))
		var deploy_y = test_zone.max_y - 80.0 - depth_row * depth_step

		var unit_center = Vector2(col_center_x, deploy_y)
		# Generate 3 models per unit (typical squad)
		var unit_positions = AIDecisionMaker._generate_formation_positions(unit_center, 3, 32, test_zone)
		unit_positions = AIDecisionMaker._resolve_formation_collisions(unit_positions, 32, all_deployed, test_zone)

		# Check no collisions with existing models
		var has_collision = false
		for p in unit_positions:
			if AIDecisionMaker._position_collides_with_deployed(p, 32, all_deployed, 4.0):
				has_collision = true
				break

		if not has_collision:
			deploy_success_count += 1
			# Add these models to deployed list
			for p in unit_positions:
				all_deployed.append({"position": p, "base_mm": 32, "base_type": "circular", "base_dimensions": {}})
		else:
			print("  Unit %d had collision despite resolution" % idx)

	if deploy_success_count == num_test_units:
		print("PASS: All %d test units deployed without collisions (%d total models)" % [num_test_units, all_deployed.size()])
		pass_count += 1
	else:
		print("FAIL: Only %d/%d units deployed without collisions" % [deploy_success_count, num_test_units])
		fail_count += 1

	# Summary
	print("")
	print("=== Results: %d passed, %d failed ===" % [pass_count, fail_count])
	if fail_count == 0:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")

	quit()
