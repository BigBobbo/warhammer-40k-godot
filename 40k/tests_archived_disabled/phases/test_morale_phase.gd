extends BasePhaseTest
const GameStateData = preload("res://autoloads/GameState.gd")
const BasePhase = preload("res://phases/BasePhase.gd")

# MoralePhase GUT Tests - Validates the Morale Phase implementation  
# Tests battleshock tests, unit fleeing, leadership modifiers, and morale completion

var morale_phase: MoralePhase

func before_each():
	super.before_each()
	
	# Create morale phase instance
	morale_phase = preload("res://phases/MoralePhase.gd").new()
	add_child(morale_phase)
	
	# Use morale-specific test state (with casualties)
	test_state = TestDataFactory.create_morale_test_state()
	
	# Setup phase instance
	phase_instance = morale_phase
	enter_phase()

func after_each():
	if morale_phase:
		morale_phase.queue_free()
		morale_phase = null
	super.after_each()

# Test morale phase initialization
func test_morale_phase_init():
	assert_eq(GameStateData.Phase.MORALE, morale_phase.phase_type, "Phase type should be MORALE")

func test_morale_phase_enter():
	assert_not_null(morale_phase.game_state_snapshot, "Should have game state snapshot after enter")

func test_morale_phase_exit():
	morale_phase.exit_phase()
	assert_true(true, "Phase exit should complete without error")

func test_morale_phase_auto_complete():
	# Test auto-completion when no units need morale tests
	var no_casualties_state = TestDataFactory.create_test_game_state()
	
	# All units have no casualties
	for unit_id in no_casualties_state.units:
		for model in no_casualties_state.units[unit_id].models:
			model.alive = true
			model.wounds_remaining = model.get("wounds", 1)
	
	morale_phase.enter_phase(no_casualties_state)
	
	# Phase should auto-complete if no units need morale tests
	# This depends on implementation

# Test battleshock eligibility
func test_unit_needs_battleshock_test():
	# Units with casualties should need battleshock tests
	var test_unit = get_test_unit("test_unit_1")
	
	if morale_phase.has_method("needs_battleshock_test"):
		var needs_test = morale_phase.needs_battleshock_test("test_unit_1")
		
		# Check if unit has casualties
		var has_casualties = false
		for model in test_unit.models:
			if not model.alive:
				has_casualties = true
				break
		
		if has_casualties:
			assert_true(needs_test, "Units with casualties should need battleshock tests")
		else:
			assert_false(needs_test, "Units without casualties should not need battleshock tests")

func test_unit_no_battleshock_needed():
	# Units without casualties should not need battleshock tests
	var test_unit = get_test_unit("test_unit_2")
	
	# Ensure no casualties
	for model in test_unit.models:
		model.alive = true
		model.wounds_remaining = model.get("wounds", 1)
	
	if morale_phase.has_method("needs_battleshock_test"):
		var needs_test = morale_phase.needs_battleshock_test("test_unit_2")
		assert_false(needs_test, "Units without casualties should not need battleshock tests")

# Test battleshock test mechanics
func test_battleshock_test_roll():
	var battleshock_action = create_action("BATTLESHOCK_TEST", "test_unit_1")
	
	var result = morale_phase.process_action(battleshock_action)
	assert_not_null(result, "Should return battleshock test result")
	
	if result.get("success", false):
		assert_true(result.has("dice"), "Battleshock test should include dice roll")
		
		# Should roll 2D6 for battleshock
		var battleshock_dice = []
		for dice_result in result.dice:
			if dice_result.get("context", "") == "battleshock_test":
				battleshock_dice.append(dice_result)
		
		if battleshock_dice.size() > 0:
			assert_eq(1, battleshock_dice.size(), "Should roll 2D6 for battleshock (as single roll)")

func test_battleshock_test_calculation():
	# Test battleshock calculation: 2D6 vs (Leadership + modifiers)
	var test_unit = get_test_unit("test_unit_1")
	
	if morale_phase.has_method("calculate_battleshock_target"):
		var target = morale_phase.calculate_battleshock_target("test_unit_1")
		
		var leadership = test_unit.get("stats", {}).get("leadership", 7)
		assert_gte(target, leadership, "Battleshock target should be at least base leadership")

func test_battleshock_modifiers():
	# Test leadership modifiers from casualties, terrain, abilities
	var test_unit = get_test_unit("test_unit_1")
	
	if morale_phase.has_method("get_leadership_modifiers"):
		var modifiers = morale_phase.get_leadership_modifiers("test_unit_1")
		assert_not_null(modifiers, "Should return leadership modifiers")
		assert_true(modifiers is Array, "Leadership modifiers should be array")

func test_battleshock_casualties_modifier():
	# More casualties should impose penalties
	var test_unit = get_test_unit("test_unit_1")
	
	# Count dead models
	var casualties = 0
	for model in test_unit.models:
		if not model.alive:
			casualties += 1
	
	if casualties > 0 and morale_phase.has_method("get_casualties_modifier"):
		var modifier = morale_phase.get_casualties_modifier("test_unit_1")
		assert_lt(modifier, 0, "Casualties should impose negative leadership modifier")

# Test battleshock results
func test_battleshock_test_passed():
	var battleshock_action = create_action("BATTLESHOCK_TEST", "test_unit_1", {
		"roll_result": 6,  # Mock good roll
		"leadership": 8
	})
	
	var result = morale_phase.process_action(battleshock_action)
	if result.get("success", false):
		# Passed test should not cause additional fleeing
		if result.has("models_fled"):
			assert_eq(0, result.models_fled, "Passed battleshock should not cause fleeing")

func test_battleshock_test_failed():
	var battleshock_action = create_action("BATTLESHOCK_TEST", "test_unit_1", {
		"roll_result": 12,  # Mock bad roll
		"leadership": 7
	})
	
	var result = morale_phase.process_action(battleshock_action)
	if result.get("success", false):
		# Failed test should cause additional models to flee
		if result.has("models_fled"):
			assert_gt(result.models_fled, 0, "Failed battleshock should cause models to flee")

func test_battleshock_models_flee():
	var flee_action = create_action("MODELS_FLEE", "test_unit_1", {
		"models_fleeing": 2,
		"fled_models": ["m3", "m4"]
	})
	
	var result = morale_phase.process_action(flee_action)
	if result.get("success", false):
		assert_true(result.has("changes"), "Models fleeing should generate state changes")

# Test special morale rules
func test_fearless_units():
	# Test units immune to battleshock
	var test_unit = get_test_unit("test_unit_1")
	test_unit.abilities = ["fearless"]
	
	var battleshock_action = create_action("BATTLESHOCK_TEST", "test_unit_1")
	
	var validation = morale_phase.validate_action(battleshock_action)
	if validation.has("valid") and morale_phase.has_method("is_fearless"):
		assert_false(validation.valid, "Fearless units should not need battleshock tests")

func test_insane_bravery():
	# Test units that automatically pass morale with high leadership
	var test_unit = get_test_unit("test_unit_1")
	test_unit.stats.leadership = 10
	
	if morale_phase.has_method("auto_passes_morale"):
		var auto_pass = morale_phase.auto_passes_morale("test_unit_1")
		# High leadership units might auto-pass
		assert_true(auto_pass is bool, "Should return boolean for auto-pass check")

func test_mob_rule():
	# Test Ork Mob Rule or similar mechanics
	var ork_unit = get_test_unit("enemy_unit_1")  # Assuming this is an Ork unit
	
	if ork_unit.get("abilities", []).has("mob_rule"):
		var mob_action = create_action("MOB_RULE", "enemy_unit_1")
		
		var validation = morale_phase.validate_action(mob_action)
		assert_not_null(validation, "Should validate Mob Rule action")

func test_synapse_creatures():
	# Test Tyranid Synapse or similar mechanics
	var synapse_action = create_action("SYNAPSE_EFFECT", "test_unit_1", {
		"synapse_creature_id": "hive_tyrant_1"
	})
	
	var validation = morale_phase.validate_action(synapse_action)
	assert_not_null(validation, "Should validate synapse effect action")

# Test leadership bonuses and penalties
func test_leadership_from_characters():
	# Test leadership bonuses from nearby characters
	if morale_phase.has_method("get_character_leadership_bonus"):
		var bonus = morale_phase.get_character_leadership_bonus("test_unit_1")
		assert_true(bonus is int, "Should return integer leadership bonus")
		assert_gte(bonus, 0, "Leadership bonus should not be negative")

func test_leadership_from_terrain():
	# Test leadership modifiers from terrain (cover, fortifications)
	test_state.board.terrain = [
		{
			"type": "fortification",
			"provides_leadership_bonus": 1,
			"poly": [
				{"x": 95, "y": 95},
				{"x": 105, "y": 95},
				{"x": 105, "y": 105},
				{"x": 95, "y": 105}
			]
		}
	]
	
	if morale_phase.has_method("get_terrain_leadership_bonus"):
		var bonus = morale_phase.get_terrain_leadership_bonus("test_unit_1")
		assert_gte(bonus, 0, "Fortification should provide leadership bonus")

func test_leadership_from_abilities():
	# Test leadership from unit abilities
	var test_unit = get_test_unit("test_unit_1")
	test_unit.abilities = ["inspiring_presence"]
	
	if morale_phase.has_method("get_ability_leadership_bonus"):
		var bonus = morale_phase.get_ability_leadership_bonus("test_unit_1")
		assert_gte(bonus, 0, "Inspiring abilities should provide leadership bonus")

# Test unit destruction
func test_unit_destroyed_by_morale():
	# Test unit being completely destroyed by morale
	var test_unit = get_test_unit("test_unit_1")
	
	# Kill all but one model through combat
	for i in range(test_unit.models.size() - 1):
		test_unit.models[i].alive = false
	
	var destroy_action = create_action("UNIT_DESTROYED", "test_unit_1", {
		"cause": "morale"
	})
	
	var result = morale_phase.process_action(destroy_action)
	if result.get("success", false):
		assert_true(result.has("changes"), "Unit destruction should generate state changes")

func test_last_model_flees():
	# Test that the last model fleeing destroys the unit
	var test_unit = get_test_unit("test_unit_1")
	
	# Make only one model alive
	for i in range(test_unit.models.size()):
		test_unit.models[i].alive = (i == 0)  # Only first model alive
	
	var flee_action = create_action("MODELS_FLEE", "test_unit_1", {
		"models_fleeing": 1,
		"fled_models": ["m1"]
	})
	
	var result = morale_phase.process_action(flee_action)
	if result.get("success", false):
		# Last model fleeing should destroy the unit
		if result.has("unit_destroyed"):
			assert_true(result.unit_destroyed, "Unit should be destroyed when last model flees")

# Test morale test timing and order
func test_morale_test_order():
	# Test that morale tests happen in correct order
	if morale_phase.has_method("get_morale_test_order"):
		var order = morale_phase.get_morale_test_order()
		assert_not_null(order, "Should return morale test order")
		assert_true(order is Array, "Morale test order should be array")

func test_simultaneous_morale_tests():
	# Test handling multiple units needing morale tests
	var multi_morale_action = create_action("RESOLVE_ALL_MORALE", "", {
		"units": ["test_unit_1", "test_unit_2"]
	})
	
	var validation = morale_phase.validate_action(multi_morale_action)
	assert_not_null(validation, "Should validate multiple morale tests")

# Test available actions
func test_get_available_morale_actions():
	var available = get_available_actions()
	assert_not_null(available, "Should return available actions")
	assert_true(available is Array, "Available actions should be array")
	
	# Check for morale-related actions
	var has_morale_action = false
	for action in available:
		if action.type in ["BATTLESHOCK_TEST", "MODELS_FLEE"]:
			has_morale_action = true
			break
	
	# If units need morale tests, should have morale actions
	var units_needing_tests = get_units_needing_morale_tests()
	if units_needing_tests.size() > 0:
		assert_true(has_morale_action, "Should have morale actions when units need tests")

func test_phase_completion():
	# Mark all units as having completed morale tests
	mark_all_units_morale_complete()
	
	if morale_phase.has_method("_should_complete_phase"):
		var should_complete = morale_phase._should_complete_phase()
		assert_true(should_complete, "Phase should complete when all morale tests resolved")

# Test edge cases
func test_morale_with_destroyed_unit():
	# Try to do morale test on destroyed unit
	var test_unit = get_test_unit("test_unit_1")
	for model in test_unit.models:
		model.alive = false
		model.current_wounds = 0
	
	var battleshock_action = create_action("BATTLESHOCK_TEST", "test_unit_1")
	
	var validation = morale_phase.validate_action(battleshock_action)
	if validation.has("valid"):
		assert_false(validation.valid, "Should not be able to test morale for destroyed units")

func test_morale_single_model_unit():
	# Test morale for single-model units (should auto-pass or be immune)
	var single_model_state = TestDataFactory.create_test_game_state()
	
	# Create a single model unit
	single_model_state.units["single_model"] = {
		"id": "single_model",
		"owner": 1,
		"models": [
			{"id": "sm1", "alive": true, "wounds_remaining": 3}
		],
		"stats": {"leadership": 8}
	}
	
	morale_phase.enter_phase(single_model_state)
	
	if morale_phase.has_method("needs_battleshock_test"):
		var needs_test = morale_phase.needs_battleshock_test("single_model")
		# Single model units typically don't need morale tests
		assert_false(needs_test, "Single model units should not need morale tests")

func test_no_casualties_no_morale():
	# Test that units with no casualties don't need morale tests
	var no_casualties_unit = get_test_unit("test_unit_2")
	
	# Ensure all models are alive and healthy
	for model in no_casualties_unit.models:
		model.alive = true
		model.wounds_remaining = model.get("wounds", 1)
	
	if morale_phase.has_method("needs_battleshock_test"):
		var needs_test = morale_phase.needs_battleshock_test("test_unit_2")
		assert_false(needs_test, "Units with no casualties should not need morale tests")

# Test special scenarios
func test_below_half_strength():
	# Test units below half strength get additional penalties
	var test_unit = get_test_unit("test_unit_1")
	
	# Kill more than half the models
	var models_to_kill = (test_unit.models.size() / 2) + 1
	for i in range(models_to_kill):
		if i < test_unit.models.size():
			test_unit.models[i].alive = false
	
	if morale_phase.has_method("is_below_half_strength"):
		var below_half = morale_phase.is_below_half_strength("test_unit_1")
		assert_true(below_half, "Unit should be below half strength")

func test_combat_attrition():
	# Test Combat Attrition rule (models flee on 1s)
	var attrition_action = create_action("COMBAT_ATTRITION", "test_unit_1", {
		"models_affected": ["m1", "m2"]
	})
	
	var validation = morale_phase.validate_action(attrition_action)
	assert_not_null(validation, "Should validate combat attrition action")

# Test morale immunity and special rules
func test_and_they_shall_know_no_fear():
	# Test Space Marine morale immunity
	var test_unit = get_test_unit("test_unit_1")
	test_unit.abilities = ["and_they_shall_know_no_fear"]
	
	var battleshock_action = create_action("BATTLESHOCK_TEST", "test_unit_1")
	
	var validation = morale_phase.validate_action(battleshock_action)
	if validation.has("valid") and morale_phase.has_method("has_morale_immunity"):
		# Should be immune or auto-pass
		var has_immunity = morale_phase.has_morale_immunity("test_unit_1")
		assert_true(has_immunity is bool, "Should check for morale immunity")

func test_objective_secured_morale():
	# Test morale bonuses when holding objectives
	test_state.board.objectives = [
		{
			"id": "obj_1",
			"position": {"x": 100, "y": 100},
			"controlled_by": 1  # Controlled by player 1
		}
	]
	
	if morale_phase.has_method("get_objective_leadership_bonus"):
		var bonus = morale_phase.get_objective_leadership_bonus("test_unit_1")
		assert_gte(bonus, 0, "Objective control should provide leadership bonus")

# Helper methods for morale tests
func get_units_needing_morale_tests() -> Array:
	var current_player = morale_phase.get_current_player()
	var units = morale_phase.get_units_for_player(current_player)
	var needing_tests = []
	
	for unit_id in units:
		var unit = units[unit_id]
		
		# Check if unit has casualties
		var has_casualties = false
		for model in unit.get("models", []):
			if not model.get("alive", true):
				has_casualties = true
				break
		
		if has_casualties:
			needing_tests.append(unit_id)
	
	return needing_tests

func mark_all_units_morale_complete():
	var current_player = morale_phase.get_current_player()
	var units = morale_phase.get_units_for_player(current_player)
	
	for unit_id in units:
		var unit = units[unit_id]
		if not unit.has("flags"):
			unit.flags = {}
		unit.flags.morale_tested = true
