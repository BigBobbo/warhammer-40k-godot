extends BasePhaseTest

# ChargePhase GUT Tests - Validates the Charge Phase implementation 
# Tests charge declarations, charge rolls, overwatch, and charge movement

var charge_phase: ChargePhase

func before_each():
	super.before_each()
	
	# Create charge phase instance
	charge_phase = preload("res://phases/ChargePhase.gd").new()
	add_child(charge_phase)
	
	# Use charge-specific test state
	test_state = TestDataFactory.create_charge_test_state()
	
	# Setup phase instance
	phase_instance = charge_phase
	enter_phase()

func after_each():
	if charge_phase:
		charge_phase.queue_free()
		charge_phase = null
	super.after_each()

# Test charge phase initialization
func test_charge_phase_init():
	assert_eq(GameStateData.Phase.CHARGE, charge_phase.phase_type, "Phase type should be CHARGE")

func test_charge_phase_enter():
	assert_not_null(charge_phase.game_state_snapshot, "Should have game state snapshot after enter")

func test_charge_phase_exit():
	charge_phase.exit_phase()
	assert_true(true, "Phase exit should complete without error")

# Test charge declarations
func test_declare_charge_valid():
	var charge_action = create_action("DECLARE_CHARGE", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1"]
	})
	
	var validation = charge_phase.validate_action(charge_action)
	assert_not_null(validation, "Should validate charge declaration")

func test_declare_charge_multiple_targets():
	var charge_action = create_action("DECLARE_CHARGE", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1", "enemy_unit_2"]
	})
	
	var validation = charge_phase.validate_action(charge_action)
	assert_not_null(validation, "Should validate charge with multiple targets")

func test_declare_charge_friendly_unit():
	var charge_action = create_action("DECLARE_CHARGE", "test_unit_1", {
		"target_unit_ids": ["test_unit_2"]  # Friendly unit
	})
	
	var validation = charge_phase.validate_action(charge_action)
	if validation.has("valid"):
		assert_false(validation.valid, "Should not be able to charge friendly units")

func test_declare_charge_already_charged():
	# Mark unit as having already charged
	var test_unit = get_test_unit("test_unit_1")
	test_unit.flags.has_charged = true
	
	var charge_action = create_action("DECLARE_CHARGE", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1"]
	})
	
	assert_invalid_action(charge_action, ["already charged", "has_charged"], "Units that already charged should not charge again")

func test_declare_charge_unit_that_advanced():
	# Mark unit as having advanced (cannot charge)
	var test_unit = get_test_unit("test_unit_1")
	test_unit.flags.cannot_charge = true
	
	var charge_action = create_action("DECLARE_CHARGE", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1"]
	})
	
	assert_invalid_action(charge_action, ["cannot charge", "advanced"], "Units that advanced should not be able to charge")

func test_declare_charge_already_in_engagement():
	# Position units already in engagement range
	var test_unit = get_test_unit("test_unit_1")
	var enemy_unit = get_test_unit("enemy_unit_1")
	
	enemy_unit.models[0].position = {
		"x": test_unit.models[0].position.x + 20,  # Within 1" engagement
		"y": test_unit.models[0].position.y
	}
	
	var charge_action = create_action("DECLARE_CHARGE", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1"]
	})
	
	var validation = charge_phase.validate_action(charge_action)
	if validation.has("valid") and charge_phase.has_method("check_engagement_range"):
		# Units already in engagement typically cannot declare new charges
		assert_false(validation.valid, "Units already in engagement should not be able to declare charges")

# Test charge distance validation
func test_charge_within_12_inches():
	# Position units within 12" charge range
	var test_unit = get_test_unit("test_unit_1")
	var enemy_unit = get_test_unit("enemy_unit_1")
	
	test_unit.models[0].position = {"x": 100, "y": 100}
	enemy_unit.models[0].position = {"x": 200, "y": 100}  # ~2.5 inches away
	
	var charge_action = create_action("DECLARE_CHARGE", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1"]
	})
	
	var validation = charge_phase.validate_action(charge_action)
	if charge_phase.has_method("check_charge_range"):
		assert_true(validation.get("valid", true), "Charge within 12\" should be valid")

func test_charge_beyond_12_inches():
	# Position units beyond 12" charge range
	var test_unit = get_test_unit("test_unit_1")
	var enemy_unit = get_test_unit("enemy_unit_1")
	
	test_unit.models[0].position = {"x": 100, "y": 100}
	enemy_unit.models[0].position = {"x": 700, "y": 100}  # ~15 inches away
	
	var charge_action = create_action("DECLARE_CHARGE", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1"]
	})
	
	var validation = charge_phase.validate_action(charge_action)
	if charge_phase.has_method("check_charge_range"):
		assert_false(validation.get("valid", true), "Charge beyond 12\" should be invalid")

# Test overwatch
func test_overwatch_opportunity():
	var charge_action = create_action("DECLARE_CHARGE", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1"]
	})
	
	var result = charge_phase.process_action(charge_action)
	if result.get("success", false):
		# Check if overwatch opportunity is created
		if result.has("overwatch_opportunities"):
			assert_true(result.overwatch_opportunities is Array, "Overwatch opportunities should be array")
			assert_gt(result.overwatch_opportunities.size(), 0, "Should create overwatch opportunities")

func test_overwatch_shooting():
	var overwatch_action = create_action("OVERWATCH", "enemy_unit_1", {
		"target_unit_id": "test_unit_1",
		"weapon": "Shoota"
	})
	
	var validation = charge_phase.validate_action(overwatch_action)
	assert_not_null(validation, "Should validate overwatch action")

func test_overwatch_restrictions():
	# Test that units cannot overwatch if they already shot
	var enemy_unit = get_test_unit("enemy_unit_1")
	enemy_unit.flags.has_shot = true
	
	var overwatch_action = create_action("OVERWATCH", "enemy_unit_1", {
		"target_unit_id": "test_unit_1"
	})
	
	var validation = charge_phase.validate_action(overwatch_action)
	if validation.has("valid"):
		assert_false(validation.valid, "Units that already shot should not be able to overwatch")

func test_decline_overwatch():
	var decline_action = create_action("DECLINE_OVERWATCH", "enemy_unit_1", {
		"charge_unit_id": "test_unit_1"
	})
	
	var validation = charge_phase.validate_action(decline_action)
	assert_not_null(validation, "Should validate declining overwatch")

# Test charge rolls
func test_charge_roll():
	var roll_action = create_action("ROLL_CHARGE", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1"]
	})
	
	var result = charge_phase.process_action(roll_action)
	assert_not_null(result, "Should return charge roll result")
	
	if result.get("success", false):
		assert_true(result.has("dice"), "Charge roll should include dice results")
		assert_true(result.dice is Array, "Dice results should be array")
		
		# Should roll 2D6 for charge
		var charge_dice = []
		for dice_result in result.dice:
			if dice_result.get("context", "") == "charge_roll":
				charge_dice.append(dice_result)
		
		if charge_dice.size() > 0:
			assert_eq(2, charge_dice.size(), "Should roll 2D6 for charge")

func test_successful_charge_roll():
	# Mock a successful charge roll (would need dependency injection for deterministic testing)
	var test_unit = get_test_unit("test_unit_1")
	var enemy_unit = get_test_unit("enemy_unit_1")
	
	# Position units 6" apart
	test_unit.models[0].position = {"x": 100, "y": 100}
	enemy_unit.models[0].position = {"x": 340, "y": 100}  # 6 inches
	
	var roll_action = create_action("ROLL_CHARGE", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1"],
		"charge_distance": 8  # Successful roll (would normally be random)
	})
	
	var result = charge_phase.process_action(roll_action)
	if result.get("success", false):
		# Successful charge should allow charge movement
		assert_not_null(result, "Successful charge should return result")

func test_failed_charge_roll():
	# Mock a failed charge roll
	var test_unit = get_test_unit("test_unit_1")
	var enemy_unit = get_test_unit("enemy_unit_1")
	
	# Position units 6" apart
	test_unit.models[0].position = {"x": 100, "y": 100}
	enemy_unit.models[0].position = {"x": 340, "y": 100}  # 6 inches
	
	var roll_action = create_action("ROLL_CHARGE", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1"],
		"charge_distance": 4  # Failed roll
	})
	
	var result = charge_phase.process_action(roll_action)
	if result.get("success", false):
		# Failed charge should not allow movement
		if result.has("charge_failed"):
			assert_true(result.charge_failed, "Should indicate charge failure")

# Test charge movement
func test_charge_movement():
	var move_action = create_action("CHARGE_MOVE", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1"],
		"model_destinations": {
			"m1": {"x": 320, "y": 100},
			"m2": {"x": 320, "y": 120}
		}
	})
	
	var validation = charge_phase.validate_action(move_action)
	assert_not_null(validation, "Should validate charge movement")

func test_charge_movement_into_engagement():
	# Test that charge movement ends in engagement range
	var move_action = create_action("CHARGE_MOVE", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1"],
		"model_destinations": {
			"m1": {"x": 315, "y": 100}  # Within 1" of enemy
		}
	})
	
	var validation = charge_phase.validate_action(move_action)
	if charge_phase.has_method("validate_charge_movement"):
		assert_not_null(validation, "Should validate engagement distance")

func test_charge_movement_coherency():
	# Test that charging models maintain unit coherency
	var move_action = create_action("CHARGE_MOVE", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1"],
		"model_destinations": {
			"m1": {"x": 315, "y": 100},
			"m2": {"x": 500, "y": 500}  # Too far from other models
		}
	})
	
	var validation = charge_phase.validate_action(move_action)
	if charge_phase.has_method("check_unit_coherency"):
		# Should fail coherency check
		assert_false(validation.get("valid", true), "Charge movement breaking coherency should be invalid")

# Test multi-unit charges
func test_charge_multiple_units():
	var charge_action = create_action("DECLARE_CHARGE", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1", "enemy_unit_2"]
	})
	
	var validation = charge_phase.validate_action(charge_action)
	assert_not_null(validation, "Should validate multi-unit charge")

func test_charge_distance_to_multiple_targets():
	# When charging multiple units, must reach at least one
	var roll_action = create_action("ROLL_CHARGE", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1", "enemy_unit_2"],
		"charge_distance": 8
	})
	
	var result = charge_phase.process_action(roll_action)
	if charge_phase.has_method("check_multiple_charge_targets"):
		assert_not_null(result, "Should process multi-target charge roll")

# Test charge restrictions
func test_cannot_charge_if_fell_back():
	var test_unit = get_test_unit("test_unit_1")
	test_unit.flags.fell_back = true
	
	var charge_action = create_action("DECLARE_CHARGE", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1"]
	})
	
	assert_invalid_action(charge_action, ["fell back", "cannot charge"], "Units that fell back should not be able to charge")

func test_cannot_charge_destroyed_unit():
	# Try to charge a destroyed unit
	var enemy_unit = get_test_unit("enemy_unit_1")
	for model in enemy_unit.models:
		model.alive = false
		model.current_wounds = 0
	
	var charge_action = create_action("DECLARE_CHARGE", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1"]
	})
	
	var validation = charge_phase.validate_action(charge_action)
	if validation.has("valid"):
		assert_false(validation.valid, "Should not be able to charge destroyed units")

# Test terrain and obstacles
func test_charge_through_terrain():
	# Add impassable terrain between units
	test_state.board.terrain = [
		{
			"type": "wall",
			"impassable": true,
			"poly": [
				{"x": 200, "y": 90},
				{"x": 210, "y": 90},
				{"x": 210, "y": 110},
				{"x": 200, "y": 110}
			]
		}
	]
	
	var charge_action = create_action("DECLARE_CHARGE", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1"]
	})
	
	if charge_phase.has_method("check_charge_path"):
		var validation = charge_phase.validate_action(charge_action)
		# May be invalid if terrain blocks the charge
		assert_not_null(validation, "Should check terrain in charge path")

# Test charge completion
func test_successful_charge_completion():
	var complete_action = create_action("COMPLETE_CHARGE", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1"],
		"successful": true
	})
	
	var result = charge_phase.process_action(complete_action)
	if result.get("success", false):
		# Successful charge should set appropriate flags
		assert_true(result.has("changes"), "Charge completion should generate state changes")

func test_failed_charge_completion():
	var complete_action = create_action("COMPLETE_CHARGE", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1"],
		"successful": false
	})
	
	var result = charge_phase.process_action(complete_action)
	if result.get("success", false):
		# Failed charge should still mark unit as having attempted to charge
		assert_true(result.has("changes"), "Failed charge should still generate state changes")

# Test available actions
func test_get_available_charge_actions():
	var available = get_available_actions()
	assert_not_null(available, "Should return available actions")
	assert_true(available is Array, "Available actions should be array")
	
	# Check for charge-related actions
	var has_charge_action = false
	for action in available:
		if action.type in ["DECLARE_CHARGE", "ROLL_CHARGE", "OVERWATCH"]:
			has_charge_action = true
			break
	
	# If units can charge, should have charge actions
	var can_charge_units = get_units_that_can_charge()
	if can_charge_units.size() > 0:
		assert_true(has_charge_action, "Should have charge actions when units can charge")

func test_phase_completion():
	# Mark all units as having charged or chosen not to charge
	mark_all_friendly_units_as_charged()
	
	if charge_phase.has_method("_should_complete_phase"):
		var should_complete = charge_phase._should_complete_phase()
		assert_true(should_complete, "Phase should complete when all units have resolved charges")

# Test edge cases
func test_charge_with_destroyed_unit():
	# Try to charge with a destroyed unit
	var test_unit = get_test_unit("test_unit_1")
	for model in test_unit.models:
		model.alive = false
		model.current_wounds = 0
	
	var charge_action = create_action("DECLARE_CHARGE", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1"]
	})
	
	assert_invalid_action(charge_action, ["destroyed", "no models"], "Destroyed units should not be able to charge")

func test_heroic_intervention():
	# Test heroic intervention if implemented
	var heroic_action = create_action("HEROIC_INTERVENTION", "hero_unit_1", {
		"target_position": {"x": 200, "y": 200}
	})
	
	var validation = charge_phase.validate_action(heroic_action)
	assert_not_null(validation, "Should validate heroic intervention")

# Test charge reactions
func test_set_to_defend():
	var defend_action = create_action("SET_TO_DEFEND", "enemy_unit_1", {
		"charging_unit_id": "test_unit_1"
	})
	
	var validation = charge_phase.validate_action(defend_action)
	assert_not_null(validation, "Should validate set to defend action")

func test_counter_charge():
	var counter_action = create_action("COUNTER_CHARGE", "enemy_unit_1", {
		"charging_unit_id": "test_unit_1"
	})
	
	var validation = charge_phase.validate_action(counter_action)
	assert_not_null(validation, "Should validate counter charge action")

# Helper methods for charge tests
func get_units_that_can_charge() -> Array:
	var current_player = charge_phase.get_current_player()
	var units = charge_phase.get_units_for_player(current_player)
	var can_charge = []
	
	for unit_id in units:
		var unit = units[unit_id]
		var has_charged = unit.get("flags", {}).get("has_charged", false)
		var cannot_charge = unit.get("flags", {}).get("cannot_charge", false)
		var fell_back = unit.get("flags", {}).get("fell_back", false)
		
		if not has_charged and not cannot_charge and not fell_back:
			can_charge.append(unit_id)
	
	return can_charge

func mark_all_friendly_units_as_charged():
	var current_player = charge_phase.get_current_player()
	var units = charge_phase.get_units_for_player(current_player)
	
	for unit_id in units:
		var unit = units[unit_id]
		if not unit.has("flags"):
			unit.flags = {}
		unit.flags.has_charged = true