extends Node

# MovementPhaseTest - Validates the Movement Phase implementation
# Tests all movement types, validation rules, and edge cases

var test_results: Array = []
var phase: MovementPhase
var test_state: Dictionary

func run_all_tests() -> void:
	print("\n========================================")
	print("MOVEMENT PHASE TEST SUITE")
	print("========================================\n")
	
	setup_test_environment()
	
	# Run test categories
	test_normal_movement()
	test_advance_movement()
	test_fall_back_movement()
	test_engagement_range_rules()
	test_terrain_collision()
	test_desperate_escape()
	test_movement_restrictions()
	test_action_validation()
	
	print_test_summary()

func setup_test_environment() -> void:
	# Create a test phase instance
	phase = MovementPhase.new()
	
	# Create test game state
	test_state = {
		"meta": {
			"game_id": "test-game",
			"turn_number": 1,
			"active_player": 1,
			"phase": GameStateData.Phase.MOVEMENT
		},
		"board": {
			"size": {"width": 44, "height": 60},
			"terrain": [
				{
					"type": "impassable",
					"poly": [
						{"x": 20, "y": 20},
						{"x": 24, "y": 20},
						{"x": 24, "y": 24},
						{"x": 20, "y": 24}
					]
				}
			]
		},
		"units": {
			"test_unit_1": {
				"id": "test_unit_1",
				"owner": 1,
				"status": GameStateData.UnitStatus.DEPLOYED,
				"flags": {},
				"meta": {
					"name": "Test Unit 1",
					"stats": {"move": 6}
				},
				"models": [
					{
						"id": "m1",
						"base_mm": 32,
						"position": {"x": 400, "y": 400},
						"alive": true,
						"current_wounds": 2
					},
					{
						"id": "m2",
						"base_mm": 32,
						"position": {"x": 440, "y": 400},
						"alive": true,
						"current_wounds": 2
					}
				]
			},
			"enemy_unit_1": {
				"id": "enemy_unit_1",
				"owner": 2,
				"status": GameStateData.UnitStatus.DEPLOYED,
				"flags": {},
				"meta": {
					"name": "Enemy Unit 1",
					"stats": {"move": 6}
				},
				"models": [
					{
						"id": "e1",
						"base_mm": 32,
						"position": {"x": 480, "y": 400},
						"alive": true,
						"current_wounds": 1
					}
				]
			}
		}
	}
	
	phase.enter_phase(test_state)
	print("✅ Test environment setup complete")

func test_normal_movement() -> void:
	print("\n--- Testing Normal Movement ---")
	
	# Test 1: Valid normal move
	var action = {
		"type": "BEGIN_NORMAL_MOVE",
		"actor_unit_id": "test_unit_1",
		"payload": {}
	}
	
	var validation = phase.validate_action(action)
	assert_true(validation.valid, "Normal move should be valid when not engaged")
	
	var result = phase.process_action(action)
	assert_true(result.success, "Normal move should process successfully")
	assert_equals(phase.active_moves["test_unit_1"].mode, "NORMAL", "Move mode should be NORMAL")
	assert_equals(phase.active_moves["test_unit_1"].move_cap_inches, 6.0, "Move cap should be 6 inches")
	
	print("✅ Normal movement tests passed")

func test_advance_movement() -> void:
	print("\n--- Testing Advance Movement ---")
	
	# Reset phase state
	phase.active_moves.clear()
	
	var action = {
		"type": "BEGIN_ADVANCE",
		"actor_unit_id": "test_unit_1",
		"payload": {}
	}
	
	var validation = phase.validate_action(action)
	assert_true(validation.valid, "Advance should be valid when not engaged")
	
	var result = phase.process_action(action)
	assert_true(result.success, "Advance should process successfully")
	assert_true(result.has("dice"), "Result should include dice rolls")
	
	var move_data = phase.active_moves["test_unit_1"]
	assert_equals(move_data.mode, "ADVANCE", "Move mode should be ADVANCE")
	assert_true(move_data.move_cap_inches >= 7.0 and move_data.move_cap_inches <= 12.0, 
		"Advance move cap should be M + D6 (7-12 inches)")
	
	print("✅ Advance movement tests passed")

func test_fall_back_movement() -> void:
	print("\n--- Testing Fall Back Movement ---")
	
	# Move enemy unit close to create engagement
	test_state["units"]["enemy_unit_1"]["models"][0]["position"] = {"x": 440, "y": 400}
	phase.game_state_snapshot = test_state
	phase.active_moves.clear()
	
	# Test Fall Back when engaged
	var action = {
		"type": "BEGIN_FALL_BACK",
		"actor_unit_id": "test_unit_1",
		"payload": {}
	}
	
	var validation = phase.validate_action(action)
	assert_true(validation.valid, "Fall Back should be valid when engaged")
	
	var result = phase.process_action(action)
	assert_true(result.success, "Fall Back should process successfully")
	assert_equals(phase.active_moves["test_unit_1"].mode, "FALL_BACK", "Move mode should be FALL_BACK")
	
	# Test that Normal Move is invalid when engaged
	phase.active_moves.clear()
	var normal_action = {
		"type": "BEGIN_NORMAL_MOVE",
		"actor_unit_id": "test_unit_1",
		"payload": {}
	}
	
	validation = phase.validate_action(normal_action)
	assert_false(validation.valid, "Normal move should be invalid when engaged")
	
	print("✅ Fall Back movement tests passed")

func test_engagement_range_rules() -> void:
	print("\n--- Testing Engagement Range Rules ---")
	
	# Reset positions
	test_state["units"]["test_unit_1"]["models"][0]["position"] = {"x": 400, "y": 400}
	test_state["units"]["enemy_unit_1"]["models"][0]["position"] = {"x": 500, "y": 400}
	phase.game_state_snapshot = test_state
	phase.active_moves.clear()
	
	# Start a normal move
	phase.process_action({
		"type": "BEGIN_NORMAL_MOVE",
		"actor_unit_id": "test_unit_1",
		"payload": {}
	})
	
	# Test moving into engagement range (should be invalid)
	var dest_near_enemy = {
		"type": "SET_MODEL_DEST",
		"actor_unit_id": "test_unit_1",
		"payload": {
			"model_id": "m1",
			"dest": [480, 400]  # Too close to enemy
		}
	}
	
	var validation = phase.validate_action(dest_near_enemy)
	assert_false(validation.valid, "Normal move should not be able to end in engagement range")
	
	print("✅ Engagement range tests passed")

func test_terrain_collision() -> void:
	print("\n--- Testing Terrain Collision ---")
	
	phase.active_moves.clear()
	
	# Start a normal move
	phase.process_action({
		"type": "BEGIN_NORMAL_MOVE",
		"actor_unit_id": "test_unit_1",
		"payload": {}
	})
	
	# Test moving into terrain (should be invalid)
	var dest_in_terrain = {
		"type": "SET_MODEL_DEST",
		"actor_unit_id": "test_unit_1",
		"payload": {
			"model_id": "m1",
			"dest": [880, 880]  # Inside terrain at (22, 22) inches
		}
	}
	
	var validation = phase.validate_action(dest_in_terrain)
	assert_false(validation.valid, "Move should not be able to end in impassable terrain")
	
	print("✅ Terrain collision tests passed")

func test_desperate_escape() -> void:
	print("\n--- Testing Desperate Escape ---")
	
	# Setup Fall Back scenario
	test_state["units"]["enemy_unit_1"]["models"][0]["position"] = {"x": 420, "y": 400}
	phase.game_state_snapshot = test_state
	phase.active_moves.clear()
	
	# Start Fall Back
	phase.process_action({
		"type": "BEGIN_FALL_BACK",
		"actor_unit_id": "test_unit_1",
		"payload": {}
	})
	
	# Move through enemy
	phase.process_action({
		"type": "SET_MODEL_DEST",
		"actor_unit_id": "test_unit_1",
		"payload": {
			"model_id": "m1",
			"dest": [300, 400]  # Moving away, crossing enemy
		}
	})
	
	# Confirm move (should trigger Desperate Escape)
	var result = phase.process_action({
		"type": "CONFIRM_UNIT_MOVE",
		"actor_unit_id": "test_unit_1",
		"payload": {}
	})
	
	assert_true(result.success, "Fall Back confirmation should succeed")
	# Note: Can't test dice rolls deterministically without mocking RNG
	
	print("✅ Desperate Escape tests passed")

func test_movement_restrictions() -> void:
	print("\n--- Testing Movement Restrictions ---")
	
	phase.active_moves.clear()
	
	# Test Advance restrictions
	phase.process_action({
		"type": "BEGIN_ADVANCE",
		"actor_unit_id": "test_unit_1",
		"payload": {}
	})
	
	var result = phase.process_action({
		"type": "CONFIRM_UNIT_MOVE",
		"actor_unit_id": "test_unit_1",
		"payload": {}
	})
	
	# Check that flags are set correctly
	var changes = result.changes
	var has_cannot_shoot = false
	var has_cannot_charge = false
	
	for change in changes:
		if change.path.ends_with("cannot_shoot"):
			has_cannot_shoot = change.value == true
		if change.path.ends_with("cannot_charge"):
			has_cannot_charge = change.value == true
	
	assert_true(has_cannot_shoot, "Advance should set cannot_shoot flag")
	assert_true(has_cannot_charge, "Advance should set cannot_charge flag")
	
	print("✅ Movement restriction tests passed")

func test_action_validation() -> void:
	print("\n--- Testing Action Validation ---")
	
	# Test invalid unit ID
	var invalid_action = {
		"type": "BEGIN_NORMAL_MOVE",
		"actor_unit_id": "non_existent_unit",
		"payload": {}
	}
	
	var validation = phase.validate_action(invalid_action)
	assert_false(validation.valid, "Action with invalid unit ID should fail validation")
	
	# Test already moved unit
	test_state["units"]["test_unit_1"]["flags"]["moved"] = true
	phase.game_state_snapshot = test_state
	
	var moved_action = {
		"type": "BEGIN_NORMAL_MOVE",
		"actor_unit_id": "test_unit_1",
		"payload": {}
	}
	
	validation = phase.validate_action(moved_action)
	assert_false(validation.valid, "Unit that already moved should fail validation")
	
	print("✅ Action validation tests passed")

# Helper functions

func assert_true(condition: bool, message: String) -> void:
	if condition:
		test_results.append({"passed": true, "message": message})
	else:
		test_results.append({"passed": false, "message": "FAILED: " + message})
		push_error("Test failed: " + message)

func assert_false(condition: bool, message: String) -> void:
	assert_true(not condition, message)

func assert_equals(actual, expected, message: String) -> void:
	if actual == expected:
		test_results.append({"passed": true, "message": message})
	else:
		var error_msg = "FAILED: %s (expected: %s, got: %s)" % [message, str(expected), str(actual)]
		test_results.append({"passed": false, "message": error_msg})
		push_error(error_msg)

func print_test_summary() -> void:
	print("\n========================================")
	print("TEST SUMMARY")
	print("========================================")
	
	var passed = 0
	var failed = 0
	
	for result in test_results:
		if result.passed:
			passed += 1
		else:
			failed += 1
			print("❌ " + result.message)
	
	print("\nTotal Tests: %d" % test_results.size())
	print("Passed: %d" % passed)
	print("Failed: %d" % failed)
	
	if failed == 0:
		print("\n🎉 ALL TESTS PASSED! 🎉")
	else:
		print("\n⚠️  SOME TESTS FAILED")
	
	print("========================================\n")
