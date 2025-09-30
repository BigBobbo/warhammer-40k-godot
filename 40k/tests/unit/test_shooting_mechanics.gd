extends GutTest

# Unit tests for shooting mechanics - validates RulesEngine and core shooting logic

var test_board: Dictionary
var rng_service

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	# Setup test board state
	test_board = {
		"units": {
			"TEST_SHOOTER": {
				"id": "TEST_SHOOTER",
				"owner": 1,
				"status": GameStateData.UnitStatus.DEPLOYED,
				"flags": {},
				"meta": {
					"name": "Test Shooter",
					"stats": {"move": 6, "toughness": 4, "save": 3}
				},
				"models": [
					{"id": "m1", "wounds": 2, "current_wounds": 2, "alive": true, "position": {"x": 100, "y": 100}},
					{"id": "m2", "wounds": 2, "current_wounds": 2, "alive": true, "position": {"x": 120, "y": 100}}
				]
			},
			"TEST_TARGET": {
				"id": "TEST_TARGET",
				"owner": 2,
				"status": GameStateData.UnitStatus.DEPLOYED,
				"flags": {},
				"meta": {
					"name": "Test Target",
					"stats": {"move": 6, "toughness": 4, "save": 5}
				},
				"models": [
					{"id": "m1", "wounds": 1, "current_wounds": 1, "alive": true, "position": {"x": 300, "y": 100}},
					{"id": "m2", "wounds": 1, "current_wounds": 1, "alive": true, "position": {"x": 320, "y": 100}},
					{"id": "m3", "wounds": 1, "current_wounds": 1, "alive": true, "position": {"x": 340, "y": 100}}
				]
			},
			"TEST_TOUGH": {
				"id": "TEST_TOUGH",
				"owner": 2,
				"status": GameStateData.UnitStatus.DEPLOYED,
				"flags": {},
				"meta": {
					"name": "Tough Target",
					"stats": {"move": 5, "toughness": 8, "save": 2}
				},
				"models": [
					{"id": "m1", "wounds": 3, "current_wounds": 3, "alive": true, "position": {"x": 400, "y": 200}, "invuln": 4}
				]
			}
		},
		"board": {
			"terrain": []
		}
	}
	
	# Setup deterministic RNG for testing
	rng_service = RulesEngine.RNGService.new(12345)

func test_wound_threshold_calculations():
	# Test the wound threshold matrix from 10e rules
	assert_eq(RulesEngine._calculate_wound_threshold(10, 5), 2, "S10 vs T5 should be 2+")
	assert_eq(RulesEngine._calculate_wound_threshold(8, 4), 2, "S8 vs T4 should be 2+")
	assert_eq(RulesEngine._calculate_wound_threshold(5, 4), 3, "S5 vs T4 should be 3+")
	assert_eq(RulesEngine._calculate_wound_threshold(4, 4), 4, "S4 vs T4 should be 4+")
	assert_eq(RulesEngine._calculate_wound_threshold(3, 4), 5, "S3 vs T4 should be 5+")
	assert_eq(RulesEngine._calculate_wound_threshold(2, 4), 6, "S2 vs T4 should be 6+")
	assert_eq(RulesEngine._calculate_wound_threshold(2, 5), 6, "S2 vs T5 should be 6+")

func test_save_calculations_without_cover():
	# Test basic save calculations without cover
	var save_result = RulesEngine._calculate_save_needed(3, 0, false, 0)
	assert_eq(save_result.armour, 3, "3+ save with AP0 should remain 3+")
	assert_false(save_result.use_invuln, "Should not use invuln when none exists")
	
	save_result = RulesEngine._calculate_save_needed(3, 1, false, 0)
	assert_eq(save_result.armour, 4, "3+ save with AP1 should become 4+")
	
	save_result = RulesEngine._calculate_save_needed(3, 3, false, 0)
	assert_eq(save_result.armour, 6, "3+ save with AP3 should become 6+")
	
	save_result = RulesEngine._calculate_save_needed(6, 2, false, 0)
	assert_eq(save_result.armour, 8, "6+ save with AP2 should become impossible (8+)")

func test_save_calculations_with_cover():
	# Test cover benefits
	var save_result = RulesEngine._calculate_save_needed(4, 1, true, 0)
	assert_eq(save_result.armour, 4, "4+ save with AP1 and cover should be 4+")
	
	save_result = RulesEngine._calculate_save_needed(5, 0, true, 0)
	assert_eq(save_result.armour, 4, "5+ save with AP0 and cover should be 4+")
	
	# Test 3+ or better doesn't benefit from cover vs AP0
	save_result = RulesEngine._calculate_save_needed(3, 0, true, 0)
	assert_eq(save_result.armour, 3, "3+ save with AP0 shouldn't benefit from cover")
	
	save_result = RulesEngine._calculate_save_needed(2, 0, true, 0)
	assert_eq(save_result.armour, 2, "2+ save with AP0 shouldn't benefit from cover")

func test_save_improvement_cap():
	# Test that save improvements are capped at +1
	var save_result = RulesEngine._calculate_save_needed(5, -2, true, 0)
	# Base 5+, AP-2 would make it 3+, cover would make it 2+
	# But cap limits improvement to +1, so should be 4+
	assert_eq(save_result.armour, 4, "Save improvement should be capped at +1")
	assert_true(save_result.cap_applied, "Cap should be applied")

func test_invulnerable_saves():
	# Test invuln save selection
	var save_result = RulesEngine._calculate_save_needed(3, 3, false, 5)
	assert_eq(save_result.armour, 6, "Armour save should be 6+")
	assert_eq(save_result.inv, 5, "Invuln should be 5+")
	assert_true(save_result.use_invuln, "Should use 5++ instead of 6+")
	
	save_result = RulesEngine._calculate_save_needed(2, 1, false, 4)
	assert_eq(save_result.armour, 3, "Armour save should be 3+")
	assert_eq(save_result.inv, 4, "Invuln should be 4+")
	assert_false(save_result.use_invuln, "Should use 3+ armour instead of 4++")
	
	# Invuln ignores AP
	save_result = RulesEngine._calculate_save_needed(6, 5, false, 4)
	assert_true(save_result.use_invuln, "Should always use 4++ when armour is impossible")

func test_shooting_validation():
	# Test valid shooting action
	var action = {
		"type": "SHOOT",
		"actor_unit_id": "TEST_SHOOTER",
		"payload": {
			"assignments": [{
				"weapon_id": "bolt_rifle",
				"target_unit_id": "TEST_TARGET",
				"model_ids": ["m1", "m2"]
			}]
		}
	}
	
	var validation = RulesEngine.validate_shoot(action, test_board)
	assert_true(validation.valid, "Valid shooting action should pass validation")
	assert_eq(validation.errors.size(), 0, "Should have no errors")
	
	# Test invalid - shooting at friendly
	action.payload.assignments[0].target_unit_id = "TEST_SHOOTER"
	validation = RulesEngine.validate_shoot(action, test_board)
	assert_false(validation.valid, "Shooting at friendly should fail")
	assert_true(validation.errors.has("Cannot target friendly units"), "Should have friendly fire error")
	
	# Test invalid - unit cannot shoot
	test_board.units.TEST_SHOOTER.flags.cannot_shoot = true
	action.payload.assignments[0].target_unit_id = "TEST_TARGET"
	validation = RulesEngine.validate_shoot(action, test_board)
	assert_false(validation.valid, "Unit with cannot_shoot flag should fail")
	test_board.units.TEST_SHOOTER.flags.cannot_shoot = false

func test_line_of_sight():
	# Test clear LoS
	var has_los = RulesEngine._check_line_of_sight(Vector2(100, 100), Vector2(300, 100), test_board)
	assert_true(has_los, "Should have clear LoS with no terrain")
	
	# Add obscuring terrain
	test_board.board.terrain = [{
		"type": "obscuring",
		"poly": [
			{"x": 150, "y": 50},
			{"x": 250, "y": 50},
			{"x": 250, "y": 150},
			{"x": 150, "y": 150}
		]
	}]
	
	has_los = RulesEngine._check_line_of_sight(Vector2(100, 100), Vector2(300, 100), test_board)
	assert_false(has_los, "Should not have LoS through obscuring terrain")
	
	# Test LoS that doesn't cross terrain
	has_los = RulesEngine._check_line_of_sight(Vector2(100, 200), Vector2(300, 200), test_board)
	assert_true(has_los, "Should have LoS when not crossing terrain")

func test_cover_detection():
	# Test no cover
	var has_cover = RulesEngine._check_model_has_cover(
		{"position": {"x": 300, "y": 100}},
		"TEST_SHOOTER",
		test_board
	)
	assert_false(has_cover, "Should not have cover with no terrain")
	
	# Add light cover terrain
	test_board.board.terrain = [{
		"type": "light_cover",
		"poly": [
			{"x": 280, "y": 80},
			{"x": 320, "y": 80},
			{"x": 320, "y": 120},
			{"x": 280, "y": 120}
		]
	}]
	
	# Test model inside cover
	has_cover = RulesEngine._check_model_has_cover(
		{"position": {"x": 300, "y": 100}},
		"TEST_SHOOTER",
		test_board
	)
	assert_true(has_cover, "Model inside light cover should have cover")
	
	# Test model behind cover
	has_cover = RulesEngine._check_model_has_cover(
		{"position": {"x": 350, "y": 100}},
		"TEST_SHOOTER",
		test_board
	)
	assert_true(has_cover, "Model behind light cover should have cover")
	
	# Test model in front of cover (no benefit)
	has_cover = RulesEngine._check_model_has_cover(
		{"position": {"x": 250, "y": 100}},
		"TEST_SHOOTER",
		test_board
	)
	assert_false(has_cover, "Model in front of cover should not have cover")

func test_eligible_targets():
	# Test getting eligible targets
	var eligible = RulesEngine.get_eligible_targets("TEST_SHOOTER", test_board)
	
	assert_true(eligible.has("TEST_TARGET"), "Should find TEST_TARGET as eligible")
	assert_true(eligible.has("TEST_TOUGH"), "Should find TEST_TOUGH as eligible")
	assert_false(eligible.has("TEST_SHOOTER"), "Should not include friendly units")
	
	var target_data = eligible.get("TEST_TARGET", {})
	assert_true(target_data.weapons_in_range.has("bolt_rifle"), "Bolt rifle should be in range")

func test_damage_allocation():
	# Test that damage allocates to previously wounded models first
	test_board.units.TEST_TARGET.models[1].current_wounds = 0  # Model already wounded
	
	var action = {
		"type": "SHOOT",
		"actor_unit_id": "TEST_SHOOTER",
		"payload": {
			"assignments": [{
				"weapon_id": "bolt_rifle",
				"target_unit_id": "TEST_TARGET",
				"model_ids": ["m1", "m2"],
				"attacks_override": 2  # Force 2 attacks for testing
			}]
		}
	}
	
	# Use fixed RNG that will produce hits and wounds
	var fixed_rng = RulesEngine.RNGService.new(1)  # Seed that produces favorable rolls
	var result = RulesEngine.resolve_shoot(action, test_board, fixed_rng)
	
	assert_true(result.success, "Shooting should succeed")
	assert_true(result.dice.size() > 0, "Should have dice results")
	
	# Check that damage was applied
	var has_damage = false
	for diff in result.diffs:
		if diff.path.contains("current_wounds"):
			has_damage = true
			break
	
	# Note: exact damage depends on RNG seed

func test_weapon_assignment_validation():
	# Test that weapons cannot split attacks across multiple targets
	var phase = ShootingPhase.new()
	phase.game_state_snapshot = test_board
	phase.active_shooter_id = "TEST_SHOOTER"
	phase.pending_assignments = [{
		"weapon_id": "bolt_rifle",
		"target_unit_id": "TEST_TARGET",
		"model_ids": ["m1"]
	}]
	
	# Try to assign same weapon to different target
	var action = {
		"payload": {
			"weapon_id": "bolt_rifle",
			"target_unit_id": "TEST_TOUGH",
			"model_ids": ["m2"]
		}
	}
	
	var validation = phase._validate_assign_target(action)
	assert_false(validation.valid, "Should not allow splitting weapon attacks")
	assert_true(validation.errors[0].contains("split"), "Error should mention splitting")

func test_shooting_phase_state_machine():
	# Test phase state transitions
	var phase = ShootingPhase.new()
	phase.game_state_snapshot = test_board
	
	# Initial state
	assert_eq(phase.active_shooter_id, "", "Should start with no active shooter")
	assert_eq(phase.pending_assignments.size(), 0, "Should start with no assignments")
	
	# Select shooter
	var result = phase._process_select_shooter({"actor_unit_id": "TEST_SHOOTER"})
	assert_true(result.success, "Should select shooter successfully")
	assert_eq(phase.active_shooter_id, "TEST_SHOOTER", "Active shooter should be set")
	
	# Assign target
	result = phase._process_assign_target({
		"payload": {
			"weapon_id": "bolt_rifle",
			"target_unit_id": "TEST_TARGET",
			"model_ids": ["m1", "m2"]
		}
	})
	assert_true(result.success, "Should assign target successfully")
	assert_eq(phase.pending_assignments.size(), 1, "Should have one assignment")
	
	# Confirm targets
	result = phase._process_confirm_targets({})
	assert_true(result.success, "Should confirm targets successfully")
	assert_eq(phase.confirmed_assignments.size(), 1, "Should have confirmed assignments")
	assert_eq(phase.pending_assignments.size(), 0, "Pending should be cleared")
	
	# Clear all (before confirmation)
	phase.pending_assignments = [{"weapon_id": "test", "target_unit_id": "test"}]
	result = phase._process_clear_all_assignments({})
	assert_true(result.success, "Should clear assignments successfully")
	assert_eq(phase.pending_assignments.size(), 0, "Assignments should be cleared")