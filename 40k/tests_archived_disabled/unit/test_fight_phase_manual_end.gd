extends GutTest

var fight_phase: FightPhase
var test_state: Dictionary

func before_each():
	fight_phase = FightPhase.new()
	add_child_autofree(fight_phase)

	# Set up GameState mock
	GameState.state = {
		"meta": {
			"active_player": 1,
			"turn": 1,
			"battle_round": 1,
			"phase": GameStateData.Phase.FIGHT
		},
		"units": {},
		"board": {},
		"players": {
			"1": {"cp": 0, "vp": 0},
			"2": {"cp": 0, "vp": 0}
		}
	}

func test_no_auto_advance_when_all_units_fought():
	"""Verify phase does not auto-complete when all eligible units have fought"""
	# Create scenario with two units that will fight
	test_state = {
		"units": {
			"P1_UNIT": {
				"id": "P1_UNIT",
				"owner": 1,
				"flags": {"charged_this_turn": true},
				"meta": {"name": "Unit 1"},
				"models": [{
					"id": "0",
					"position": {"x": 100, "y": 100},
					"alive": true,
					"base_mm": 25.0
				}]
			},
			"P2_UNIT": {
				"id": "P2_UNIT",
				"owner": 2,
				"flags": {"charged_this_turn": true},
				"meta": {"name": "Unit 2"},
				"models": [{
					"id": "0",
					"position": {"x": 120, "y": 100},  # Within 1" engagement
					"alive": true,
					"base_mm": 25.0
				}]
			}
		}
	}

	# Track if phase_completed was emitted
	var phase_completed_count = 0
	fight_phase.phase_completed.connect(func(): phase_completed_count += 1)

	# Enter fight phase
	GameState.state["meta"]["active_player"] = 1
	fight_phase.enter_phase(test_state)

	# Complete P2's unit activation (defending player goes first)
	var select_result = fight_phase.execute_action({
		"type": "SELECT_FIGHTER",
		"unit_id": "P2_UNIT"
	})
	assert_true(select_result.success, "Should select P2 unit")

	# Complete the activation
	fight_phase.execute_action({"type": "PILE_IN", "unit_id": "P2_UNIT", "movements": {}})
	fight_phase.execute_action({
		"type": "ASSIGN_ATTACKS",
		"unit_id": "P2_UNIT",
		"target_id": "P1_UNIT",
		"weapon_id": "close_combat_weapon",
		"attacking_models": ["0"]
	})
	fight_phase.execute_action({"type": "CONFIRM_AND_RESOLVE_ATTACKS"})
	fight_phase.execute_action({"type": "ROLL_DICE"})
	fight_phase.execute_action({"type": "CONSOLIDATE", "unit_id": "P2_UNIT", "movements": {}})

	# Complete P1's unit activation
	select_result = fight_phase.execute_action({
		"type": "SELECT_FIGHTER",
		"unit_id": "P1_UNIT"
	})
	assert_true(select_result.success, "Should select P1 unit")

	fight_phase.execute_action({"type": "PILE_IN", "unit_id": "P1_UNIT", "movements": {}})
	fight_phase.execute_action({
		"type": "ASSIGN_ATTACKS",
		"unit_id": "P1_UNIT",
		"target_id": "P2_UNIT",
		"weapon_id": "close_combat_weapon",
		"attacking_models": ["0"]
	})
	fight_phase.execute_action({"type": "CONFIRM_AND_RESOLVE_ATTACKS"})
	fight_phase.execute_action({"type": "ROLL_DICE"})
	fight_phase.execute_action({"type": "CONSOLIDATE", "unit_id": "P1_UNIT", "movements": {}})

	# CRITICAL TEST: phase_completed should NOT have been emitted yet
	assert_eq(phase_completed_count, 0, "phase_completed should NOT be auto-emitted after all units fight")

	# Check that END_FIGHT action is available
	var available_actions = fight_phase.get_available_actions()
	var end_fight_action = null
	for action in available_actions:
		if action.get("type") == "END_FIGHT":
			end_fight_action = action
			break

	assert_not_null(end_fight_action, "END_FIGHT action should be available")

	# Now manually end the fight phase
	var end_result = fight_phase.execute_action({"type": "END_FIGHT"})
	assert_true(end_result.success, "END_FIGHT should succeed")

	# NOW phase_completed should have been emitted
	assert_eq(phase_completed_count, 1, "phase_completed should be emitted after END_FIGHT action")

func test_end_fight_available_when_all_units_fought():
	"""Verify END_FIGHT button becomes available when all eligible units complete fighting"""
	test_state = {
		"units": {
			"P1_UNIT": {
				"id": "P1_UNIT",
				"owner": 1,
				"flags": {"charged_this_turn": true},
				"meta": {"name": "Unit 1"},
				"models": [{
					"id": "0",
					"position": {"x": 100, "y": 100},
					"alive": true,
					"base_mm": 25.0
				}]
			},
			"P2_UNIT": {
				"id": "P2_UNIT",
				"owner": 2,
				"flags": {"charged_this_turn": true},
				"meta": {"name": "Unit 2"},
				"models": [{
					"id": "0",
					"position": {"x": 120, "y": 100},
					"alive": true,
					"base_mm": 25.0
				}]
			}
		}
	}

	GameState.state["meta"]["active_player"] = 1
	fight_phase.enter_phase(test_state)

	# Mark both units as having fought manually (to test _all_eligible_units_have_fought)
	fight_phase.units_that_fought = ["P1_UNIT", "P2_UNIT"]

	# Check available actions
	var actions = fight_phase.get_available_actions()
	var has_end_fight = false
	for action in actions:
		if action.get("type") == "END_FIGHT":
			has_end_fight = true
			break

	assert_true(has_end_fight, "END_FIGHT action should be available when all units have fought")
