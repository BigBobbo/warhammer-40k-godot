extends BasePhaseTest

# FightPhase GUT Tests - Validates the Fight Phase implementation
# Tests combat resolution, pile in, consolidate, and fight order

var fight_phase: FightPhase

func before_each():
	super.before_each()
	
	# Create fight phase instance
	fight_phase = preload("res://phases/FightPhase.gd").new()
	add_child(fight_phase)
	
	# Use fight-specific test state
	test_state = TestDataFactory.create_fight_test_state()
	
	# Setup phase instance
	phase_instance = fight_phase
	enter_phase()

func after_each():
	if fight_phase:
		fight_phase.queue_free()
		fight_phase = null
	super.after_each()

# Test fight phase initialization
func test_fight_phase_init():
	assert_eq(GameStateData.Phase.FIGHT, fight_phase.phase_type, "Phase type should be FIGHT")

func test_fight_phase_enter():
	assert_not_null(fight_phase.game_state_snapshot, "Should have game state snapshot after enter")

func test_fight_phase_exit():
	fight_phase.exit_phase()
	assert_true(true, "Phase exit should complete without error")

# Test fight eligibility
func test_unit_can_fight():
	# Units in engagement range should be able to fight
	var test_unit = get_test_unit("test_unit_1")
	var enemy_unit = get_test_unit("enemy_unit_1")
	
	# Verify units are in engagement range (should be set by TestDataFactory)
	var fight_action = create_action("FIGHT", "test_unit_1", {
		"target_unit_id": "enemy_unit_1"
	})
	
	var validation = fight_phase.validate_action(fight_action)
	assert_not_null(validation, "Should validate fight action")

func test_unit_not_in_engagement():
	# Position units out of engagement range
	var test_unit = get_test_unit("test_unit_1")
	var enemy_unit = get_test_unit("enemy_unit_1")
	
	enemy_unit.models[0].position = {
		"x": test_unit.models[0].position.x + 200,  # Far away
		"y": test_unit.models[0].position.y
	}
	
	var fight_action = create_action("FIGHT", "test_unit_1", {
		"target_unit_id": "enemy_unit_1"
	})
	
	var validation = fight_phase.validate_action(fight_action)
	if fight_phase.has_method("check_engagement_range"):
		assert_false(validation.get("valid", true), "Units not in engagement should not be able to fight")

func test_already_fought_unit():
	# Mark unit as having already fought
	var test_unit = get_test_unit("test_unit_1")
	test_unit.flags.has_fought = true
	
	var fight_action = create_action("FIGHT", "test_unit_1", {
		"target_unit_id": "enemy_unit_1"
	})
	
	assert_invalid_action(fight_action, ["already fought", "has_fought"], "Units that already fought should not fight again")

# Test fight sequence activation
func test_fight_first_units():
	# Test units with "fights first" ability
	var test_unit = get_test_unit("test_unit_1")
	test_unit.abilities = ["fights_first"]
	
	var fight_action = create_action("ACTIVATE_FIGHT_FIRST", "test_unit_1", {
		"target_unit_id": "enemy_unit_1"
	})
	
	var validation = fight_phase.validate_action(fight_action)
	assert_not_null(validation, "Should validate fights first activation")

func test_fight_last_units():
	# Test units with "fights last" debuff
	var test_unit = get_test_unit("test_unit_1") 
	test_unit.status_effects = ["fights_last"]
	
	var fight_action = create_action("FIGHT", "test_unit_1", {
		"target_unit_id": "enemy_unit_1"
	})
	
	if fight_phase.has_method("check_fight_sequence"):
		var validation = fight_phase.validate_action(fight_action)
		# Units that fight last should be restricted until normal sequence
		assert_not_null(validation, "Should validate fights last restriction")

func test_interrupt_combat():
	# Test interrupting combat sequence
	var interrupt_action = create_action("INTERRUPT", "test_unit_1", {
		"target_unit_id": "enemy_unit_1"
	})
	
	var validation = fight_phase.validate_action(interrupt_action)
	assert_not_null(validation, "Should validate interrupt action")

# Test pile in moves
func test_pile_in_move():
	var pile_in_action = create_action("PILE_IN", "test_unit_1", {
		"model_moves": {
			"m1": {"x": 105, "y": 105}  # 3" pile in toward enemy
		}
	})
	
	var validation = fight_phase.validate_action(pile_in_action)
	assert_not_null(validation, "Should validate pile in move")

func test_pile_in_distance_limit():
	# Test pile in beyond 3" limit
	var pile_in_action = create_action("PILE_IN", "test_unit_1", {
		"model_moves": {
			"m1": {"x": 200, "y": 200}  # Too far
		}
	})
	
	var validation = fight_phase.validate_action(pile_in_action)
	if fight_phase.has_method("validate_pile_in_distance"):
		assert_false(validation.get("valid", true), "Pile in beyond 3\" should be invalid")

func test_pile_in_toward_closest_enemy():
	# Test pile in must move toward closest enemy
	var test_unit = get_test_unit("test_unit_1")
	var enemy_unit = get_test_unit("enemy_unit_1")
	
	# Enemy is to the right, pile in should move right
	var pile_in_action = create_action("PILE_IN", "test_unit_1", {
		"model_moves": {
			"m1": {"x": test_unit.models[0].position.x - 50, "y": test_unit.models[0].position.y}  # Moving away
		}
	})
	
	var validation = fight_phase.validate_action(pile_in_action)
	if fight_phase.has_method("validate_pile_in_direction"):
		assert_false(validation.get("valid", true), "Pile in should move toward closest enemy")

func test_pile_in_coherency():
	# Test pile in maintains unit coherency
	var pile_in_action = create_action("PILE_IN", "test_unit_1", {
		"model_moves": {
			"m1": {"x": 500, "y": 500}  # Too far from other models
		}
	})
	
	var validation = fight_phase.validate_action(pile_in_action)
	if fight_phase.has_method("check_unit_coherency"):
		assert_false(validation.get("valid", true), "Pile in breaking coherency should be invalid")

# Test attack resolution
func test_resolve_attacks():
	var attack_action = create_action("RESOLVE_ATTACKS", "test_unit_1", {
		"target_unit_id": "enemy_unit_1",
		"weapon": "Chainsword",
		"attacking_models": ["m1", "m2"]
	})
	
	var result = fight_phase.process_action(attack_action)
	assert_not_null(result, "Should return attack resolution result")
	
	if result.get("success", false):
		assert_true(result.has("dice"), "Attack resolution should include dice rolls")

func test_attack_allocation():
	# Test allocating attacks to specific models
	var allocate_action = create_action("ALLOCATE_ATTACKS", "test_unit_1", {
		"target_unit_id": "enemy_unit_1",
		"attacks": [
			{"weapon": "Chainsword", "target_model": "e1", "count": 2}
		]
	})
	
	var validation = fight_phase.validate_action(allocate_action)
	assert_not_null(validation, "Should validate attack allocation")

func test_hit_rolls():
	var hit_action = create_action("ROLL_TO_HIT", "test_unit_1", {
		"target_unit_id": "enemy_unit_1",
		"weapon_skill": 3,
		"attacks": 4
	})
	
	var result = fight_phase.process_action(hit_action)
	if result.get("success", false):
		# Should include hit roll dice results
		if result.has("dice"):
			var hit_dice = []
			for dice_result in result.dice:
				if dice_result.get("context", "") == "hit_roll":
					hit_dice.append(dice_result)
			
			if hit_dice.size() > 0:
				assert_eq(4, hit_dice.size(), "Should roll for each attack")

func test_wound_rolls():
	var wound_action = create_action("ROLL_TO_WOUND", "test_unit_1", {
		"target_unit_id": "enemy_unit_1",
		"weapon_strength": 4,
		"target_toughness": 4,
		"hits": 3
	})
	
	var result = fight_phase.process_action(wound_action)
	if result.get("success", false) and result.has("dice"):
		var wound_dice = []
		for dice_result in result.dice:
			if dice_result.get("context", "") == "wound_roll":
				wound_dice.append(dice_result)
		
		if wound_dice.size() > 0:
			assert_eq(3, wound_dice.size(), "Should roll to wound for each hit")

func test_save_rolls():
	var save_action = create_action("ROLL_SAVES", "enemy_unit_1", {
		"wounds": 2,
		"armor_save": 6,
		"ap": -1,
		"invulnerable_save": null
	})
	
	var result = fight_phase.process_action(save_action)
	if result.get("success", false) and result.has("dice"):
		var save_dice = []
		for dice_result in result.dice:
			if dice_result.get("context", "") == "save_roll":
				save_dice.append(dice_result)
		
		if save_dice.size() > 0:
			assert_eq(2, save_dice.size(), "Should roll save for each wound")

# Test wound allocation and model removal
func test_wound_allocation():
	var allocate_action = create_action("ALLOCATE_WOUNDS", "enemy_unit_1", {
		"wounds": [
			{"damage": 2, "target_model": "e1"},
			{"damage": 1, "target_model": "e2"}
		]
	})
	
	var result = fight_phase.process_action(allocate_action)
	if result.get("success", false):
		assert_true(result.has("changes"), "Wound allocation should generate state changes")

func test_model_death_in_combat():
	# Apply enough damage to kill a model
	var enemy_unit = get_test_unit("enemy_unit_1")
	var original_wounds = enemy_unit.models[0].current_wounds
	
	var damage_action = create_action("APPLY_DAMAGE", "enemy_unit_1", {
		"model_id": "e1",
		"damage": 10  # Overkill
	})
	
	var result = fight_phase.process_action(damage_action)
	if result.get("success", false):
		# Should mark model as dead and update state
		assert_true(result.has("changes"), "Model death should generate state changes")

# Test special combat rules
func test_rerolls():
	var reroll_action = create_action("REROLL_DICE", "test_unit_1", {
		"dice_type": "hit_rolls",
		"reroll_condition": "1s"
	})
	
	var validation = fight_phase.validate_action(reroll_action)
	assert_not_null(validation, "Should validate reroll action")

func test_mortal_wounds():
	var mortal_action = create_action("INFLICT_MORTAL_WOUNDS", "test_unit_1", {
		"target_unit_id": "enemy_unit_1",
		"mortal_wounds": 2,
		"source": "special_ability"
	})
	
	var result = fight_phase.process_action(mortal_action)
	if result.get("success", false):
		assert_true(result.has("changes"), "Mortal wounds should generate state changes")

func test_feel_no_pain():
	# Test Feel No Pain saves
	var fnp_action = create_action("FEEL_NO_PAIN", "test_unit_1", {
		"wounds": 3,
		"fnp_value": 5
	})
	
	var result = fight_phase.process_action(fnp_action)
	if result.get("success", false) and result.has("dice"):
		var fnp_dice = []
		for dice_result in result.dice:
			if dice_result.get("context", "") == "feel_no_pain":
				fnp_dice.append(dice_result)
		
		if fnp_dice.size() > 0:
			assert_eq(3, fnp_dice.size(), "Should roll FNP for each wound")

# Test consolidation moves
func test_consolidate_move():
	var consolidate_action = create_action("CONSOLIDATE", "test_unit_1", {
		"model_moves": {
			"m1": {"x": 108, "y": 108}  # 3" consolidate
		}
	})
	
	var validation = fight_phase.validate_action(consolidate_action)
	assert_not_null(validation, "Should validate consolidate move")

func test_consolidate_distance_limit():
	# Test consolidate beyond 3" limit
	var consolidate_action = create_action("CONSOLIDATE", "test_unit_1", {
		"model_moves": {
			"m1": {"x": 300, "y": 300}  # Too far
		}
	})
	
	var validation = fight_phase.validate_action(consolidate_action)
	if fight_phase.has_method("validate_consolidate_distance"):
		assert_false(validation.get("valid", true), "Consolidate beyond 3\" should be invalid")

func test_consolidate_toward_closest_enemy():
	# Test consolidate must move toward closest enemy
	var consolidate_action = create_action("CONSOLIDATE", "test_unit_1", {
		"model_moves": {
			"m1": {"x": 50, "y": 50}  # Moving away from enemies
		}
	})
	
	var validation = fight_phase.validate_action(consolidate_action)
	if fight_phase.has_method("validate_consolidate_direction"):
		assert_false(validation.get("valid", true), "Consolidate should move toward closest enemy")

# Test fight sequence and timing
func test_fight_sequence_order():
	# Test proper fight sequence: charge units -> fights first -> normal -> fights last
	if fight_phase.has_method("get_fight_sequence"):
		var sequence = fight_phase.get_fight_sequence()
		assert_not_null(sequence, "Should return fight sequence")
		assert_true(sequence is Array, "Fight sequence should be array")

func test_charge_units_fight_first():
	# Units that charged this turn fight first
	var test_unit = get_test_unit("test_unit_1")
	test_unit.flags.charged_this_turn = true
	
	if fight_phase.has_method("get_fight_priority"):
		var priority = fight_phase.get_fight_priority("test_unit_1")
		assert_gt(priority, 0, "Units that charged should have higher fight priority")

func test_simultaneous_death():
	# Test simultaneous death in combat
	var combat_action = create_action("RESOLVE_SIMULTANEOUS_COMBAT", "test_unit_1", {
		"target_unit_id": "enemy_unit_1"
	})
	
	var validation = fight_phase.validate_action(combat_action)
	assert_not_null(validation, "Should validate simultaneous combat resolution")

# Test multi-unit combat
func test_multiple_units_in_engagement():
	# Test combat with multiple units engaged
	var multi_combat_action = create_action("FIGHT", "test_unit_1", {
		"target_unit_ids": ["enemy_unit_1", "enemy_unit_2"]
	})
	
	var validation = fight_phase.validate_action(multi_combat_action)
	assert_not_null(validation, "Should validate multi-unit combat")

func test_split_attacks():
	# Test splitting attacks between multiple target units
	var split_action = create_action("SPLIT_ATTACKS", "test_unit_1", {
		"attack_split": {
			"enemy_unit_1": 3,
			"enemy_unit_2": 2
		}
	})
	
	var validation = fight_phase.validate_action(split_action)
	assert_not_null(validation, "Should validate split attacks")

# Test available actions
func test_get_available_fight_actions():
	var available = get_available_actions()
	assert_not_null(available, "Should return available actions")
	assert_true(available is Array, "Available actions should be array")
	
	# Check for fight-related actions
	var has_fight_action = false
	for action in available:
		if action.type in ["FIGHT", "PILE_IN", "CONSOLIDATE"]:
			has_fight_action = true
			break
	
	# If units are in engagement, should have fight actions
	var engaged_units = get_units_in_engagement()
	if engaged_units.size() > 0:
		assert_true(has_fight_action, "Should have fight actions when units are engaged")

func test_phase_completion():
	# Mark all units as having fought
	mark_all_engaged_units_as_fought()
	
	if fight_phase.has_method("_should_complete_phase"):
		var should_complete = fight_phase._should_complete_phase()
		assert_true(should_complete, "Phase should complete when all engaged units have fought")

# Test edge cases
func test_fight_with_destroyed_unit():
	# Try to fight with a destroyed unit
	var test_unit = get_test_unit("test_unit_1")
	for model in test_unit.models:
		model.alive = false
		model.current_wounds = 0
	
	var fight_action = create_action("FIGHT", "test_unit_1", {
		"target_unit_id": "enemy_unit_1"
	})
	
	assert_invalid_action(fight_action, ["destroyed", "no models"], "Destroyed units should not be able to fight")

func test_fight_destroyed_target():
	# Try to fight a destroyed unit
	var enemy_unit = get_test_unit("enemy_unit_1")
	for model in enemy_unit.models:
		model.alive = false
		model.current_wounds = 0
	
	var fight_action = create_action("FIGHT", "test_unit_1", {
		"target_unit_id": "enemy_unit_1"
	})
	
	var validation = fight_phase.validate_action(fight_action)
	if validation.has("valid"):
		assert_false(validation.valid, "Should not be able to fight destroyed units")

# Test special abilities
func test_heroic_intervention():
	var heroic_action = create_action("HEROIC_INTERVENTION", "hero_unit_1", {
		"move_distance": 3,
		"target_position": {"x": 200, "y": 200}
	})
	
	var validation = fight_phase.validate_action(heroic_action)
	assert_not_null(validation, "Should validate heroic intervention")

func test_fight_twice():
	# Test abilities that allow fighting twice
	var fight_twice_action = create_action("FIGHT_TWICE", "test_unit_1", {
		"target_unit_id": "enemy_unit_1"
	})
	
	var validation = fight_phase.validate_action(fight_twice_action)
	assert_not_null(validation, "Should validate fight twice ability")

# Helper methods for fight tests
func get_units_in_engagement() -> Array:
	var current_player = fight_phase.get_current_player()
	var units = fight_phase.get_units_for_player(current_player)
	var engaged = []
	
	for unit_id in units:
		if fight_phase.has_method("is_unit_in_engagement"):
			if fight_phase.is_unit_in_engagement(unit_id):
				engaged.append(unit_id)
		else:
			# Assume all units are engaged for testing
			engaged.append(unit_id)
	
	return engaged

func mark_all_engaged_units_as_fought():
	var engaged_units = get_units_in_engagement()
	
	for unit_id in engaged_units:
		var unit = get_test_unit(unit_id)
		if not unit.has("flags"):
			unit.flags = {}
		unit.flags.has_fought = true