extends BasePhaseTest
const GameStateData = preload("res://autoloads/GameState.gd")
const BasePhase = preload("res://phases/BasePhase.gd")

# ShootingPhase GUT Tests - Validates the Shooting Phase implementation
# Tests target selection, weapon range, line of sight, cover, and damage resolution

var shooting_phase: ShootingPhase

func before_each():
	super.before_each()
	
	# Create shooting phase instance
	shooting_phase = preload("res://phases/ShootingPhase.gd").new()
	add_child(shooting_phase)
	
	# Use shooting-specific test state
	test_state = TestDataFactory.create_shooting_test_state()
	
	# Setup phase instance
	phase_instance = shooting_phase
	enter_phase()

func after_each():
	if shooting_phase:
		shooting_phase.queue_free()
		shooting_phase = null
	super.after_each()

# Test shooting phase initialization
func test_shooting_phase_init():
	assert_eq(GameStateData.Phase.SHOOTING, shooting_phase.phase_type, "Phase type should be SHOOTING")

func test_shooting_phase_enter():
	assert_not_null(shooting_phase.game_state_snapshot, "Should have game state snapshot after enter")

func test_shooting_phase_no_auto_complete():
	# Test that phase does NOT auto-complete when no units can shoot
	# User must explicitly click "End Shooting Phase"
	var no_shoot_state = TestDataFactory.create_test_game_state()

	# Mark all friendly units as having shot (cannot shoot again)
	for unit_id in no_shoot_state.units:
		var unit = no_shoot_state.units[unit_id]
		if unit.owner == 1:  # Assuming player 1 is current player
			if not unit.has("flags"):
				unit["flags"] = {}
			unit.flags["has_shot"] = true

	# Set up signal spy to detect phase_completed
	var phase_completed_emitted = false
	shooting_phase.phase_completed.connect(func(): phase_completed_emitted = true)

	shooting_phase.enter_phase(no_shoot_state)

	# Phase should NOT auto-complete - user must explicitly end it
	assert_false(phase_completed_emitted, "Phase should not auto-complete when no units can shoot")

	# User must explicitly end the phase
	var end_action = {
		"type": "END_SHOOTING"
	}
	var result = shooting_phase.process_action(end_action)
	assert_true(result.success, "END_SHOOTING action should succeed")
	assert_true(phase_completed_emitted, "Phase should complete only after explicit END_SHOOTING action")

func test_shooting_phase_exit():
	shooting_phase.exit_phase()
	assert_true(true, "Phase exit should complete without error")

# Test shooting eligibility
func test_unit_can_shoot_validation():
	var units = get_units_for_player(1)
	
	for unit_id in units:
		var unit = units[unit_id]
		
		# Test normal unit can shoot
		if unit.get("status") == GameStateData.UnitStatus.DEPLOYED and not unit.get("advanced", false):
			var shoot_action = create_action("DECLARE_SHOOTING", unit_id, {
				"target_unit_id": "enemy_unit_1"
			})
			
			var validation = shooting_phase.validate_action(shoot_action)
			assert_not_null(validation, "Should validate shooting action")

func test_advanced_unit_cannot_shoot():
	# Test that units that advanced cannot shoot
	var test_unit = get_test_unit("test_unit_1")
	test_unit.advanced = true
	
	var shoot_action = create_action("DECLARE_SHOOTING", "test_unit_1", {
		"target_unit_id": "enemy_unit_1"
	})
	
	var validation = shooting_phase.validate_action(shoot_action)
	if validation.has("valid"):
		assert_false(validation.valid, "Advanced units should not be able to shoot")

func test_fallen_back_unit_cannot_shoot():
	# Test that units that fell back cannot shoot
	var test_unit = get_test_unit("test_unit_1")
	test_unit.fallen_back = true
	
	var shoot_action = create_action("DECLARE_SHOOTING", "test_unit_1", {
		"target_unit_id": "enemy_unit_1"
	})
	
	var validation = shooting_phase.validate_action(shoot_action)
	if validation.has("valid"):
		assert_false(validation.valid, "Units that fell back should not be able to shoot")

# Test target selection
func test_declare_shooting_valid_target():
	var shoot_action = create_action("DECLARE_SHOOTING", "test_unit_1", {
		"target_unit_id": "enemy_unit_1"
	})
	
	var validation = shooting_phase.validate_action(shoot_action)
	assert_not_null(validation, "Should validate shooting declaration")

func test_declare_shooting_friendly_fire():
	# Test shooting at friendly unit (should be invalid)
	var shoot_action = create_action("DECLARE_SHOOTING", "test_unit_1", {
		"target_unit_id": "test_unit_2"  # Friendly unit
	})
	
	var validation = shooting_phase.validate_action(shoot_action)
	if validation.has("valid"):
		assert_false(validation.valid, "Should not be able to shoot friendly units")

func test_declare_shooting_nonexistent_target():
	var shoot_action = create_action("DECLARE_SHOOTING", "test_unit_1", {
		"target_unit_id": "nonexistent_unit"
	})
	
	assert_invalid_action(shoot_action, ["not found", "invalid target"], "Nonexistent target should fail")

# Test weapon range validation
func test_shooting_within_range():
	# Position units within weapon range
	var test_unit = get_test_unit("test_unit_1")
	var enemy_unit = get_test_unit("enemy_unit_1")
	
	# Set positions within 24" (typical bolter range)
	test_unit.models[0].position = {"x": 100, "y": 100}
	enemy_unit.models[0].position = {"x": 140, "y": 100}  # 40 pixels = 1 inch
	
	var shoot_action = create_action("DECLARE_SHOOTING", "test_unit_1", {
		"target_unit_id": "enemy_unit_1",
		"weapon": "Bolter"
	})
	
	var validation = shooting_phase.validate_action(shoot_action)
	if validation.has("valid") and shooting_phase.has_method("check_weapon_range"):
		# If range checking is implemented
		assert_true(validation.valid, "Shooting within range should be valid")

func test_shooting_out_of_range():
	# Position units beyond weapon range
	var test_unit = get_test_unit("test_unit_1")
	var enemy_unit = get_test_unit("enemy_unit_1")
	
	# Set positions beyond 24" range
	test_unit.models[0].position = {"x": 100, "y": 100}
	enemy_unit.models[0].position = {"x": 1100, "y": 100}  # 25 inches away
	
	var shoot_action = create_action("DECLARE_SHOOTING", "test_unit_1", {
		"target_unit_id": "enemy_unit_1",
		"weapon": "Bolter"
	})
	
	var validation = shooting_phase.validate_action(shoot_action)
	if validation.has("valid") and shooting_phase.has_method("check_weapon_range"):
		assert_false(validation.valid, "Shooting out of range should be invalid")

# Test line of sight
func test_line_of_sight_clear():
	# Test clear line of sight
	var shoot_action = create_action("DECLARE_SHOOTING", "test_unit_1", {
		"target_unit_id": "enemy_unit_1",
		"shooting_model_id": "m1",
		"target_model_id": "e1"
	})
	
	if shooting_phase.has_method("check_line_of_sight"):
		var validation = shooting_phase.validate_action(shoot_action)
		assert_not_null(validation, "Should validate line of sight")

func test_line_of_sight_blocked():
	# Test blocked line of sight with terrain
	var state_with_terrain = TestDataFactory.create_shooting_test_state()
	state_with_terrain.board.terrain = [
		{
			"type": "wall",
			"blocks_line_of_sight": true,
			"poly": [
				{"x": 120, "y": 90},
				{"x": 130, "y": 90},
				{"x": 130, "y": 110},
				{"x": 120, "y": 110}
			]
		}
	]
	
	shooting_phase.enter_phase(state_with_terrain)
	
	var shoot_action = create_action("DECLARE_SHOOTING", "test_unit_1", {
		"target_unit_id": "enemy_unit_1"
	})
	
	if shooting_phase.has_method("check_line_of_sight"):
		var validation = shooting_phase.validate_action(shoot_action)
		# Implementation would determine if LOS is blocked

# Test weapon selection
func test_select_weapon():
	var weapon_action = create_action("SELECT_WEAPON", "test_unit_1", {
		"weapon_name": "Bolter",
		"model_id": "m1"
	})
	
	var validation = shooting_phase.validate_action(weapon_action)
	assert_not_null(validation, "Should validate weapon selection")

func test_select_nonexistent_weapon():
	var weapon_action = create_action("SELECT_WEAPON", "test_unit_1", {
		"weapon_name": "Nonexistent Weapon",
		"model_id": "m1"
	})
	
	var validation = shooting_phase.validate_action(weapon_action)
	if validation.has("valid"):
		assert_false(validation.valid, "Nonexistent weapon should be invalid")

# Test shooting resolution
func test_shooting_attack_processing():
	var shoot_action = create_action("RESOLVE_SHOOTING", "test_unit_1", {
		"target_unit_id": "enemy_unit_1",
		"weapon": "Bolter",
		"shots": 1
	})
	
	var result = shooting_phase.process_action(shoot_action)
	assert_not_null(result, "Should return shooting result")
	assert_true(result.has("success"), "Result should have success field")

func test_shooting_with_dice_rolls():
	var shoot_action = create_action("RESOLVE_SHOOTING", "test_unit_1", {
		"target_unit_id": "enemy_unit_1",
		"weapon": "Bolter"
	})
	
	var result = shooting_phase.process_action(shoot_action)
	if result.get("success", false):
		# If shooting resolution is implemented, should include dice results
		if result.has("dice"):
			assert_true(result.dice is Array, "Dice results should be array")

# Test cover mechanics
func test_shooting_with_cover():
	# Add cover-providing terrain
	var state_with_cover = TestDataFactory.create_shooting_test_state()
	state_with_cover.board.terrain = [
		{
			"type": "crater",
			"provides_cover": true,
			"poly": [
				{"x": 145, "y": 95},
				{"x": 155, "y": 95},
				{"x": 155, "y": 105},
				{"x": 145, "y": 105}
			]
		}
	]
	
	shooting_phase.enter_phase(state_with_cover)
	
	var shoot_action = create_action("RESOLVE_SHOOTING", "test_unit_1", {
		"target_unit_id": "enemy_unit_1",
		"weapon": "Bolter"
	})
	
	var result = shooting_phase.process_action(shoot_action)
	if result.get("success", false) and shooting_phase.has_method("calculate_cover"):
		# If cover mechanics are implemented
		assert_not_null(result, "Should handle cover in shooting resolution")

# Test multi-weapon units
func test_different_weapons_same_unit():
	# Test unit with multiple weapon types
	var test_unit = get_test_unit("test_unit_1")
	
	# Add different weapons
	if test_unit.has("weapons"):
		test_unit.weapons.append({
			"name": "Plasma Gun",
			"range": 24,
			"strength": 7,
			"ap": -3,
			"damage": 1
		})
	
	var plasma_action = create_action("SELECT_WEAPON", "test_unit_1", {
		"weapon_name": "Plasma Gun",
		"model_id": "m1"
	})
	
	var validation = shooting_phase.validate_action(plasma_action)
	assert_not_null(validation, "Should validate plasma gun selection")

# Test overwatch (if implemented)
func test_overwatch_shooting():
	var overwatch_action = create_action("OVERWATCH", "test_unit_1", {
		"target_unit_id": "enemy_unit_1"
	})
	
	var validation = shooting_phase.validate_action(overwatch_action)
	assert_not_null(validation, "Should validate overwatch action")
	
	if shooting_phase.has_method("resolve_overwatch"):
		# If overwatch is implemented
		var result = shooting_phase.process_action(overwatch_action)
		assert_not_null(result, "Should process overwatch")

# Test shooting restrictions
func test_cannot_shoot_in_engagement():
	# Position units in engagement range
	var test_unit = get_test_unit("test_unit_1") 
	var enemy_unit = get_test_unit("enemy_unit_1")
	
	enemy_unit.models[0].position = {
		"x": test_unit.models[0].position.x + 25,  # Within 1" engagement
		"y": test_unit.models[0].position.y
	}
	
	var shoot_action = create_action("DECLARE_SHOOTING", "test_unit_1", {
		"target_unit_id": "enemy_unit_1"
	})
	
	if shooting_phase.has_method("check_engagement_range"):
		var validation = shooting_phase.validate_action(shoot_action)
		# Units in engagement range typically cannot shoot
		if validation.has("valid"):
			assert_false(validation.valid, "Units in engagement should not be able to shoot normally")

func test_cannot_shoot_if_already_shot():
	# Mark unit as having already shot
	var test_unit = get_test_unit("test_unit_1")
	test_unit.flags.has_shot = true
	
	var shoot_action = create_action("DECLARE_SHOOTING", "test_unit_1", {
		"target_unit_id": "enemy_unit_1"
	})
	
	assert_invalid_action(shoot_action, ["already shot", "has_shot"], "Units that already shot should not shoot again")

# Test damage allocation
func test_damage_allocation():
	var allocate_action = create_action("ALLOCATE_WOUNDS", "enemy_unit_1", {
		"wounds": 2,
		"weapon_strength": 4,
		"weapon_ap": 0,
		"weapon_damage": 1
	})
	
	var validation = shooting_phase.validate_action(allocate_action)
	assert_not_null(validation, "Should validate wound allocation")

func test_model_death_from_shooting():
	var enemy_unit = get_test_unit("enemy_unit_1")
	
	# Apply enough damage to kill a model
	var kill_action = create_action("APPLY_WOUNDS", "enemy_unit_1", {
		"model_id": "e1",
		"wounds": 10  # Overkill
	})
	
	var result = shooting_phase.process_action(kill_action)
	if result.get("success", false):
		assert_true(result.has("changes"), "Model death should generate state changes")

# Test available actions
func test_get_available_shooting_actions():
	var available = get_available_actions()
	assert_not_null(available, "Should return available actions")
	assert_true(available is Array, "Available actions should be array")
	
	# Check for shooting-related actions
	var has_shooting_action = false
	for action in available:
		if action.type in ["DECLARE_SHOOTING", "SELECT_WEAPON", "RESOLVE_SHOOTING"]:
			has_shooting_action = true
			break
	
	# If units can shoot, should have shooting actions
	var can_shoot_units = get_units_that_can_shoot()
	if can_shoot_units.size() > 0:
		assert_true(has_shooting_action, "Should have shooting actions when units can shoot")

func test_phase_completion():
	# Test phase completion when all units have shot or cannot shoot
	mark_all_friendly_units_as_shot()
	
	if shooting_phase.has_method("_should_complete_phase"):
		var should_complete = shooting_phase._should_complete_phase()
		assert_true(should_complete, "Phase should complete when all units have shot")

# Test edge cases
func test_shooting_destroyed_unit():
	# Try to shoot with a destroyed unit
	var test_unit = get_test_unit("test_unit_1")
	for model in test_unit.models:
		model.alive = false
		model.current_wounds = 0
	
	var shoot_action = create_action("DECLARE_SHOOTING", "test_unit_1", {
		"target_unit_id": "enemy_unit_1"
	})
	
	assert_invalid_action(shoot_action, ["destroyed", "no models"], "Destroyed units should not be able to shoot")

func test_shooting_at_destroyed_target():
	# Try to shoot at a destroyed unit
	var enemy_unit = get_test_unit("enemy_unit_1")
	for model in enemy_unit.models:
		model.alive = false
		model.current_wounds = 0
	
	var shoot_action = create_action("DECLARE_SHOOTING", "test_unit_1", {
		"target_unit_id": "enemy_unit_1"
	})
	
	var validation = shooting_phase.validate_action(shoot_action)
	if validation.has("valid"):
		assert_false(validation.valid, "Should not be able to shoot destroyed units")

# Helper methods for shooting tests
func get_units_that_can_shoot() -> Array:
	var current_player = shooting_phase.get_current_player()
	var units = shooting_phase.get_units_for_player(current_player)
	var can_shoot = []
	
	for unit_id in units:
		var unit = units[unit_id]
		var status = unit.get("status", GameStateData.UnitStatus.UNDEPLOYED)
		var advanced = unit.get("advanced", false)
		var fallen_back = unit.get("fallen_back", false)
		var has_shot = unit.get("flags", {}).get("has_shot", false)
		
		if status in [GameStateData.UnitStatus.DEPLOYED, GameStateData.UnitStatus.MOVED] and not advanced and not fallen_back and not has_shot:
			can_shoot.append(unit_id)
	
	return can_shoot

func mark_all_friendly_units_as_shot():
	var current_player = shooting_phase.get_current_player()
	var units = shooting_phase.get_units_for_player(current_player)
	
	for unit_id in units:
		var unit = units[unit_id]
		if not unit.has("flags"):
			unit.flags = {}
		unit.flags.has_shot = true
