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

func test_wounds_applied_after_melee_combat():
	"""Verify wounds are applied to defending unit after successful melee attacks"""
	test_state = _create_warboss_vs_witchseeker_scenario()

	# Initialize game state with test units
	GameState.state["units"] = test_state["units"]
	fight_phase.enter_phase(test_state)

	# Get initial state
	var witchseeker = GameState.state["units"]["witchseeker_1"]
	var initial_alive_count = _count_alive_models(witchseeker)
	print("[Test] Initial alive Witchseekers: %d" % initial_alive_count)
	assert_eq(initial_alive_count, 3, "Should start with 3 alive Witchseekers")

	# Select Warboss to fight
	var select_result = fight_phase.execute_action({
		"type": "SELECT_FIGHTER",
		"unit_id": "warboss_1"
	})
	assert_true(select_result.success, "Should successfully select Warboss")

	# Pile in (no movement needed, just pass empty movements)
	var pilein_result = fight_phase.execute_action({
		"type": "PILE_IN",
		"unit_id": "warboss_1",
		"payload": {
			"movements": {}
		}
	})
	assert_true(pilein_result.success, "Pile-in should succeed")

	# Assign attacks - Warboss attacks Witchseekers
	var assign_result = fight_phase.execute_action({
		"type": "ASSIGN_ATTACKS",
		"actor_unit_id": "warboss_1",
		"payload": {
			"weapon_index": 0,
			"target": "witchseeker_1"
		}
	})
	assert_true(assign_result.success, "Should successfully assign attacks")

	# Confirm attacks
	var confirm_result = fight_phase.execute_action({
		"type": "CONFIRM_AND_RESOLVE_ATTACKS",
		"actor_unit_id": "warboss_1"
	})
	assert_true(confirm_result.success, "Should confirm attacks")

	# Roll dice - this should apply damage
	var roll_result = fight_phase.execute_action({
		"type": "ROLL_DICE",
		"actor_unit_id": "warboss_1"
	})

	print("[Test] Roll result success: %s" % roll_result.success)
	print("[Test] Roll result has changes: %s" % roll_result.has("changes"))
	if roll_result.has("changes"):
		print("[Test] Number of state changes: %d" % roll_result.changes.size())

	assert_true(roll_result.success, "Dice roll should succeed")

	# Verify wounds were applied - check GameState.state, not snapshot
	witchseeker = GameState.state["units"]["witchseeker_1"]
	var final_alive_count = _count_alive_models(witchseeker)
	print("[Test] Final alive Witchseekers: %d" % final_alive_count)

	# With 4 attacks, WS 2+, S10 vs T3, AP-2 vs 4+ save, D3 damage vs 1W models
	# Even with bad rolls, we should kill at least 1 model statistically
	# This is a probabilistic test, so we just verify wounds were applied
	var wounds_were_applied = false
	for model in witchseeker.models:
		if not model.alive or model.current_wounds < model.wounds:
			wounds_were_applied = true
			break

	assert_true(wounds_were_applied, "At least some wounds should have been applied to Witchseekers")

func test_state_changes_included_in_result():
	"""Verify that ROLL_DICE action returns state changes in result"""
	test_state = _create_warboss_vs_witchseeker_scenario()

	GameState.state["units"] = test_state["units"]
	fight_phase.enter_phase(test_state)

	# Execute fight sequence
	fight_phase.execute_action({"type": "SELECT_FIGHTER", "unit_id": "warboss_1"})
	fight_phase.execute_action({"type": "PILE_IN", "unit_id": "warboss_1", "payload": {"movements": {}}})
	fight_phase.execute_action({
		"type": "ASSIGN_ATTACKS",
		"actor_unit_id": "warboss_1",
		"payload": {"weapon_index": 0, "target": "witchseeker_1"}
	})
	fight_phase.execute_action({"type": "CONFIRM_AND_RESOLVE_ATTACKS", "actor_unit_id": "warboss_1"})

	# Roll dice and check result structure
	var roll_result = fight_phase.execute_action({"type": "ROLL_DICE", "actor_unit_id": "warboss_1"})

	assert_true(roll_result.success, "Roll should succeed")
	assert_true(roll_result.has("changes"), "Result should include changes array")

	# Changes array might be empty if all attacks missed, but key should exist
	print("[Test] Changes in result: %s" % JSON.stringify(roll_result.get("changes", [])))

func _count_alive_models(unit: Dictionary) -> int:
	var count = 0
	for model in unit.get("models", []):
		if model.get("alive", false):
			count += 1
	return count

func _create_warboss_vs_witchseeker_scenario() -> Dictionary:
	"""Create scenario: Warboss (high damage) vs Witchseekers (low wounds)"""
	return {
		"units": {
			"warboss_1": {
				"id": "warboss_1",
				"owner": 1,
				"flags": {
					"charged_this_turn": true,
					"has_fought": false
				},
				"meta": {
					"name": "Ork Warboss",
					"type": "infantry",
					"stats": {
						"movement": 5,
						"weapon_skill": 2,  # WS 2+
						"ballistic_skill": 5,
						"strength": 5,
						"toughness": 5,
						"wounds": 6,
						"attacks": 4,
						"leadership": 6,
						"save": 4,
						"invuln": 4
					},
					"weapons": [
						{
							"name": "Power Klaw",
							"type": "melee",
							"attacks": 4,
							"weapon_skill": 3,  # WS 3+ for this weapon
							"strength": 10,  # S x2
							"ap": 2,
							"damage": 3,
							"abilities": []
						}
					],
					"abilities": []
				},
				"models": [
					{
						"id": "warboss_m0",
						"position": {"x": 100, "y": 100},
						"alive": true,
						"wounds": 6,
						"current_wounds": 6,
						"base_mm": 32.0
					}
				]
			},
			"witchseeker_1": {
				"id": "witchseeker_1",
				"owner": 2,
				"flags": {
					"charged_this_turn": false,
					"has_fought": false
				},
				"meta": {
					"name": "Witchseeker Squad",
					"type": "infantry",
					"stats": {
						"movement": 6,
						"weapon_skill": 4,
						"ballistic_skill": 3,
						"strength": 3,
						"toughness": 3,
						"wounds": 1,
						"attacks": 1,
						"leadership": 7,
						"save": 4,
						"invuln": 6
					},
					"weapons": [
						{
							"name": "Witchseeker Blade",
							"type": "melee",
							"attacks": 1,
							"weapon_skill": 4,
							"strength": 3,
							"ap": 0,
							"damage": 1,
							"abilities": []
						}
					],
					"abilities": []
				},
				"models": [
					{
						"id": "witch_m0",
						"position": {"x": 105, "y": 100},
						"alive": true,
						"wounds": 1,
						"current_wounds": 1,
						"base_mm": 25.0
					},
					{
						"id": "witch_m1",
						"position": {"x": 110, "y": 100},
						"alive": true,
						"wounds": 1,
						"current_wounds": 1,
						"base_mm": 25.0
					},
					{
						"id": "witch_m2",
						"position": {"x": 115, "y": 100},
						"alive": true,
						"wounds": 1,
						"current_wounds": 1,
						"base_mm": 25.0
					}
				]
			}
		}
	}
