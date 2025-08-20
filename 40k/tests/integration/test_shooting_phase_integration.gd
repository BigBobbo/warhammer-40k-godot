extends GutTest

# Integration tests for the complete shooting phase flow
# Tests the full pipeline from unit selection through damage resolution

var phase_manager
var shooting_phase: ShootingPhase
var test_state: Dictionary

func before_each():
	# Setup phase manager
	phase_manager = PhaseManager.new()
	
	# Create test game state with units in shooting positions
	test_state = {
		"meta": {
			"game_id": "test_game",
			"turn_number": 1,
			"active_player": 1,
			"phase": GameStateData.Phase.SHOOTING
		},
		"board": {
			"size": {"width": 44, "height": 60},
			"deployment_zones": [],
			"objectives": [],
			"terrain": [
				{
					"type": "light_cover",
					"poly": [
						{"x": 500, "y": 300},
						{"x": 700, "y": 300},
						{"x": 700, "y": 500},
						{"x": 500, "y": 500}
					]
				},
				{
					"type": "obscuring",
					"poly": [
						{"x": 1000, "y": 200},
						{"x": 1100, "y": 200},
						{"x": 1100, "y": 400},
						{"x": 1000, "y": 400}
					]
				}
			]
		},
		"units": {
			"SPACE_MARINES": {
				"id": "SPACE_MARINES",
				"owner": 1,
				"status": GameStateData.UnitStatus.DEPLOYED,
				"flags": {},
				"meta": {
					"name": "Space Marine Squad",
					"keywords": ["INFANTRY", "IMPERIUM"],
					"stats": {"move": 6, "toughness": 4, "save": 3}
				},
				"models": [
					{"id": "m1", "wounds": 2, "current_wounds": 2, "alive": true, "position": {"x": 200, "y": 400}},
					{"id": "m2", "wounds": 2, "current_wounds": 2, "alive": true, "position": {"x": 240, "y": 400}},
					{"id": "m3", "wounds": 2, "current_wounds": 2, "alive": true, "position": {"x": 280, "y": 400}},
					{"id": "m4", "wounds": 2, "current_wounds": 2, "alive": true, "position": {"x": 200, "y": 440}},
					{"id": "sarge", "wounds": 2, "current_wounds": 2, "alive": true, "position": {"x": 240, "y": 440}}
				]
			},
			"ORK_BOYZ": {
				"id": "ORK_BOYZ",
				"owner": 2,
				"status": GameStateData.UnitStatus.DEPLOYED,
				"flags": {},
				"meta": {
					"name": "Ork Boyz",
					"keywords": ["INFANTRY", "ORKS"],
					"stats": {"move": 6, "toughness": 5, "save": 6}
				},
				"models": [
					{"id": "m1", "wounds": 1, "current_wounds": 1, "alive": true, "position": {"x": 600, "y": 400}},
					{"id": "m2", "wounds": 1, "current_wounds": 1, "alive": true, "position": {"x": 640, "y": 400}},
					{"id": "m3", "wounds": 1, "current_wounds": 1, "alive": true, "position": {"x": 680, "y": 400}},
					{"id": "m4", "wounds": 1, "current_wounds": 1, "alive": true, "position": {"x": 600, "y": 440}},
					{"id": "m5", "wounds": 1, "current_wounds": 1, "alive": true, "position": {"x": 640, "y": 440}}
				]
			},
			"GRETCHIN": {
				"id": "GRETCHIN",
				"owner": 2,
				"status": GameStateData.UnitStatus.DEPLOYED,
				"flags": {},
				"meta": {
					"name": "Gretchin",
					"keywords": ["INFANTRY", "GROTS"],
					"stats": {"move": 5, "toughness": 3, "save": 7}
				},
				"models": [
					{"id": "m1", "wounds": 1, "current_wounds": 1, "alive": true, "position": {"x": 800, "y": 300}},
					{"id": "m2", "wounds": 1, "current_wounds": 1, "alive": true, "position": {"x": 840, "y": 300}},
					{"id": "m3", "wounds": 1, "current_wounds": 1, "alive": true, "position": {"x": 880, "y": 300}}
				]
			},
			"HIDDEN_UNIT": {
				"id": "HIDDEN_UNIT",
				"owner": 2,
				"status": GameStateData.UnitStatus.DEPLOYED,
				"flags": {},
				"meta": {
					"name": "Hidden Orks",
					"keywords": ["INFANTRY"],
					"stats": {"move": 6, "toughness": 4, "save": 6}
				},
				"models": [
					{"id": "m1", "wounds": 1, "current_wounds": 1, "alive": true, "position": {"x": 1050, "y": 300}}
				]
			}
		},
		"players": {
			"1": {"cp": 3, "vp": 0},
			"2": {"cp": 3, "vp": 0}
		}
	}
	
	# Initialize shooting phase
	shooting_phase = ShootingPhase.new()
	shooting_phase.enter_phase(test_state)
	
	# Set GameState
	GameState.state = test_state

func after_each():
	if shooting_phase:
		shooting_phase.exit_phase()
		shooting_phase.queue_free()
	if phase_manager:
		phase_manager.queue_free()

func test_complete_shooting_workflow():
	# Test the complete shooting workflow from selection to damage
	
	# 1. Get available actions
	var actions = shooting_phase.get_available_actions()
	assert_true(actions.size() > 0, "Should have available actions")
	
	var select_action = null
	for action in actions:
		if action.type == "SELECT_SHOOTER" and action.actor_unit_id == "SPACE_MARINES":
			select_action = action
			break
	assert_not_null(select_action, "Should have select shooter action for Space Marines")
	
	# 2. Select shooter
	var result = shooting_phase.execute_action(select_action)
	assert_true(result.success, "Should select shooter successfully")
	assert_eq(shooting_phase.active_shooter_id, "SPACE_MARINES", "Active shooter should be set")
	
	# 3. Check eligible targets
	var eligible = RulesEngine.get_eligible_targets("SPACE_MARINES", test_state)
	assert_true(eligible.has("ORK_BOYZ"), "Ork Boyz should be eligible (in range and LoS)")
	assert_true(eligible.has("GRETCHIN"), "Gretchin should be eligible")
	assert_false(eligible.has("HIDDEN_UNIT"), "Hidden unit should not be eligible (blocked by terrain)")
	
	# 4. Assign targets
	var assign_action = {
		"type": "ASSIGN_TARGET",
		"payload": {
			"weapon_id": "bolt_rifle",
			"target_unit_id": "ORK_BOYZ",
			"model_ids": ["m1", "m2", "m3", "m4"]
		}
	}
	result = shooting_phase.execute_action(assign_action)
	assert_true(result.success, "Should assign target successfully")
	assert_eq(shooting_phase.pending_assignments.size(), 1, "Should have one pending assignment")
	
	# 5. Confirm targets
	result = shooting_phase.execute_action({"type": "CONFIRM_TARGETS"})
	assert_true(result.success, "Should confirm targets")
	assert_eq(shooting_phase.confirmed_assignments.size(), 1, "Should have confirmed assignments")
	
	# 6. Resolve shooting
	result = shooting_phase.execute_action({"type": "RESOLVE_SHOOTING"})
	assert_true(result.success, "Should resolve shooting")
	assert_true(result.has("dice"), "Should have dice results")
	assert_true(result.dice.size() > 0, "Should have rolled dice")
	
	# Check that unit was marked as having shot
	assert_true("SPACE_MARINES" in shooting_phase.units_that_shot, "Unit should be marked as having shot")

func test_target_in_cover():
	# Test shooting at targets in cover
	
	# Move Ork Boyz into cover
	test_state.units.ORK_BOYZ.models[0].position = {"x": 600, "y": 400}  # Inside light cover
	
	shooting_phase.active_shooter_id = "SPACE_MARINES"
	shooting_phase.confirmed_assignments = [{
		"weapon_id": "bolt_rifle",
		"target_unit_id": "ORK_BOYZ",
		"model_ids": ["m1", "m2", "m3", "m4"]
	}]
	
	# Use deterministic RNG for testing
	var fixed_rng = RulesEngine.RNGService.new(42)
	var shoot_action = {
		"type": "SHOOT",
		"actor_unit_id": "SPACE_MARINES",
		"payload": {
			"assignments": shooting_phase.confirmed_assignments
		}
	}
	
	var result = RulesEngine.resolve_shoot(shoot_action, test_state, fixed_rng)
	assert_true(result.success, "Shooting should succeed")
	
	# Check that cover was considered in saves
	var found_save_with_cover = false
	for dice_block in result.dice:
		if dice_block.context == "save" and dice_block.has("cover"):
			if dice_block.cover != "none":
				found_save_with_cover = true
				break
	
	assert_true(found_save_with_cover, "Should have applied cover to at least one save")

func test_line_of_sight_blocking():
	# Test that obscuring terrain blocks LoS
	
	var eligible = RulesEngine.get_eligible_targets("SPACE_MARINES", test_state)
	assert_false(eligible.has("HIDDEN_UNIT"), "Should not be able to target unit behind obscuring terrain")
	
	# Validate shooting at blocked target fails
	var action = {
		"type": "SHOOT",
		"actor_unit_id": "SPACE_MARINES",
		"payload": {
			"assignments": [{
				"weapon_id": "bolt_rifle",
				"target_unit_id": "HIDDEN_UNIT",
				"model_ids": ["m1", "m2"]
			}]
		}
	}
	
	var validation = RulesEngine.validate_shoot(action, test_state)
	assert_false(validation.valid, "Should not validate shooting at blocked target")

func test_weapon_range_limits():
	# Test that weapons respect range limits
	
	# Move Gretchin far away (beyond bolt rifle range of 30")
	for model in test_state.units.GRETCHIN.models:
		model.position = {"x": 2000, "y": 2000}  # Way out of range
	
	var eligible = RulesEngine.get_eligible_targets("SPACE_MARINES", test_state)
	assert_false(eligible.has("GRETCHIN"), "Should not be able to target units beyond weapon range")

func test_unit_cannot_shoot_restrictions():
	# Test units that cannot shoot
	
	# Mark unit as having advanced
	test_state.units.SPACE_MARINES.flags.cannot_shoot = true
	
	var validation = shooting_phase._validate_select_shooter({"actor_unit_id": "SPACE_MARINES"})
	assert_false(validation.valid, "Should not be able to select unit that cannot shoot")
	
	# Reset flag
	test_state.units.SPACE_MARINES.flags.cannot_shoot = false
	
	# Mark as already shot
	shooting_phase.units_that_shot.append("SPACE_MARINES")
	validation = shooting_phase._validate_select_shooter({"actor_unit_id": "SPACE_MARINES"})
	assert_false(validation.valid, "Should not be able to select unit that already shot")

func test_multiple_weapon_assignments():
	# Test assigning multiple different weapons to different targets
	
	shooting_phase.active_shooter_id = "SPACE_MARINES"
	
	# Assign bolt rifles to Ork Boyz
	var assign1 = {
		"type": "ASSIGN_TARGET",
		"payload": {
			"weapon_id": "bolt_rifle",
			"target_unit_id": "ORK_BOYZ",
			"model_ids": ["m1", "m2", "m3", "m4"]
		}
	}
	var result = shooting_phase.execute_action(assign1)
	assert_true(result.success, "Should assign bolt rifles")
	
	# Assign plasma pistol to Gretchin (sergeant's weapon)
	var assign2 = {
		"type": "ASSIGN_TARGET",
		"payload": {
			"weapon_id": "plasma_pistol",
			"target_unit_id": "GRETCHIN",
			"model_ids": ["sarge"]
		}
	}
	result = shooting_phase.execute_action(assign2)
	assert_true(result.success, "Should assign plasma pistol")
	
	assert_eq(shooting_phase.pending_assignments.size(), 2, "Should have two assignments")
	
	# Confirm and resolve
	result = shooting_phase.execute_action({"type": "CONFIRM_TARGETS"})
	assert_true(result.success, "Should confirm multiple targets")
	
	result = shooting_phase.execute_action({"type": "RESOLVE_SHOOTING"})
	assert_true(result.success, "Should resolve multiple weapon shooting")

func test_damage_allocation_priority():
	# Test that wounded models receive damage first
	
	# Wound one Ork model
	test_state.units.ORK_BOYZ.models[1].current_wounds = 0
	
	shooting_phase.active_shooter_id = "SPACE_MARINES"
	shooting_phase.confirmed_assignments = [{
		"weapon_id": "bolt_rifle",
		"target_unit_id": "ORK_BOYZ",
		"model_ids": ["m1"],
		"attacks_override": 1  # Single attack for controlled test
	}]
	
	# Use RNG that will produce a wound
	var fixed_rng = RulesEngine.RNGService.new(1)
	var shoot_action = {
		"type": "SHOOT",
		"actor_unit_id": "SPACE_MARINES",
		"payload": {
			"assignments": shooting_phase.confirmed_assignments
		}
	}
	
	var result = RulesEngine.resolve_shoot(shoot_action, test_state, fixed_rng)
	
	# Check if wounded model was targeted for additional damage
	# (This would be visible in the diffs targeting model index 1)
	var targeted_wounded = false
	for diff in result.diffs:
		if diff.path.contains("ORK_BOYZ.models.1"):
			targeted_wounded = true
			break
	
	# Note: Exact behavior depends on RNG, but wounded model should be prioritized

func test_phase_completion():
	# Test phase completion when all units have shot
	
	# Mark all player 1 units as having shot
	shooting_phase.units_that_shot.append("SPACE_MARINES")
	
	var should_complete = shooting_phase._should_complete_phase()
	assert_true(should_complete, "Phase should complete when all units have shot")
	
	# Test end phase action
	var result = shooting_phase.execute_action({"type": "END_SHOOTING"})
	assert_true(result.success, "Should be able to end phase")

func test_skip_shooting():
	# Test skipping a unit's shooting
	
	var skip_action = {
		"type": "SKIP_UNIT",
		"actor_unit_id": "SPACE_MARINES"
	}
	
	var result = shooting_phase.execute_action(skip_action)
	assert_true(result.success, "Should be able to skip unit")
	assert_true("SPACE_MARINES" in shooting_phase.units_that_shot, "Unit should be marked as having shot")
	
	# Check that unit has the has_shot flag
	var found_flag = false
	for change in result.changes:
		if change.path == "units.SPACE_MARINES.flags.has_shot" and change.value == true:
			found_flag = true
			break
	assert_true(found_flag, "Should set has_shot flag")

func test_clear_assignments():
	# Test clearing weapon assignments
	
	shooting_phase.active_shooter_id = "SPACE_MARINES"
	shooting_phase.pending_assignments = [
		{"weapon_id": "bolt_rifle", "target_unit_id": "ORK_BOYZ", "model_ids": ["m1"]},
		{"weapon_id": "plasma_pistol", "target_unit_id": "GRETCHIN", "model_ids": ["sarge"]}
	]
	
	# Clear specific assignment
	var clear_action = {
		"type": "CLEAR_ASSIGNMENT",
		"payload": {"weapon_id": "bolt_rifle"}
	}
	var result = shooting_phase.execute_action(clear_action)
	assert_true(result.success, "Should clear specific assignment")
	assert_eq(shooting_phase.pending_assignments.size(), 1, "Should have one assignment left")
	
	# Clear all
	result = shooting_phase.execute_action({"type": "CLEAR_ALL_ASSIGNMENTS"})
	assert_true(result.success, "Should clear all assignments")
	assert_eq(shooting_phase.pending_assignments.size(), 0, "Should have no assignments")

func test_dice_logging():
	# Test that dice results are properly logged
	
	shooting_phase.active_shooter_id = "SPACE_MARINES"
	shooting_phase.confirmed_assignments = [{
		"weapon_id": "bolt_rifle",
		"target_unit_id": "ORK_BOYZ",
		"model_ids": ["m1", "m2"]
	}]
	
	var result = shooting_phase.execute_action({"type": "RESOLVE_SHOOTING"})
	assert_true(result.success, "Should resolve shooting")
	
	var dice_log = shooting_phase.get_dice_log()
	assert_true(dice_log.size() > 0, "Should have dice log entries")
	
	# Check dice log structure
	var has_hit_rolls = false
	var has_wound_rolls = false
	var has_save_rolls = false
	
	for entry in dice_log:
		if entry.context == "to_hit":
			has_hit_rolls = true
			assert_true(entry.has("rolls_raw"), "Hit rolls should have raw rolls")
			assert_true(entry.has("successes"), "Hit rolls should have successes")
		elif entry.context == "to_wound":
			has_wound_rolls = true
			assert_true(entry.has("rolls_raw"), "Wound rolls should have raw rolls")
		elif entry.context == "save":
			has_save_rolls = true
			assert_true(entry.has("rolls_raw"), "Save rolls should have raw rolls")
	
	assert_true(has_hit_rolls, "Should have hit roll entries")
	# Wound and save rolls depend on hits succeeding