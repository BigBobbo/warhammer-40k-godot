extends "res://addons/gut/test.gd"
const GameStateData = preload("res://autoloads/GameState.gd")
const FightPhase = preload("res://phases/FightPhase.gd")

var fight_phase: FightPhase
var game_manager: Node
var test_state: Dictionary
var _game_state

func before_each():
	fight_phase = FightPhase.new()
	add_child_autofree(fight_phase)

	_game_state = Engine.get_singleton("GameState")
	if _game_state == null:
		push_error("GameState singleton unavailable")
		return

	# Set up GameState mock
	_game_state.state = {
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

func test_defending_player_selects_first():
	"""Verify defending player (Player 2) selects first when active player is 1"""
	test_state = _create_scenario_both_players_have_charged_units()

	# Active player is 1
	_game_state.state["meta"]["active_player"] = 1

	fight_phase.enter_phase(test_state)

	# Defending player (2) should select first
	assert_eq(fight_phase.current_selecting_player, 2, "Defending player (2) should select first")
	assert_eq(fight_phase.current_subphase, fight_phase.Subphase.FIGHTS_FIRST, "Should start in Fights First")

func test_players_alternate_after_each_activation():
	"""Verify players alternate after each unit completes fighting"""
	test_state = _create_scenario_multiple_units_per_player()

	_game_state.state["meta"]["active_player"] = 1
	fight_phase.enter_phase(test_state)

	# Player 2 selects first
	assert_eq(fight_phase.current_selecting_player, 2)

	# Player 2 selects unit P2_CHARGED_1
	var result1 = fight_phase.execute_action({
		"type": "SELECT_FIGHTER",
		"unit_id": "P2_CHARGED_1"
	})
	assert_true(result1.success, "Player 2 should successfully select")

	# Complete activation: pile in, attacks, consolidate
	_complete_unit_activation("P2_CHARGED_1")

	# Should switch to Player 1
	assert_eq(fight_phase.current_selecting_player, 1, "Should switch to Player 1 after Player 2's activation")

	# Player 1 selects unit P1_CHARGED_1
	var result2 = fight_phase.execute_action({
		"type": "SELECT_FIGHTER",
		"unit_id": "P1_CHARGED_1"
	})
	assert_true(result2.success, "Player 1 should successfully select")

	_complete_unit_activation("P1_CHARGED_1")

	# Should switch back to Player 2
	assert_eq(fight_phase.current_selecting_player, 2, "Should switch back to Player 2")

func test_one_player_continues_when_opponent_has_no_units():
	"""Verify when one player has no eligible units, other continues selecting"""
	test_state = _create_scenario_only_player_1_has_units()

	_game_state.state["meta"]["active_player"] = 1
	fight_phase.enter_phase(test_state)

	# Player 2 (defender) should try to select first, but has no units
	# System should auto-switch to Player 1
	assert_eq(fight_phase.current_selecting_player, 1, "Should switch to Player 1 since Player 2 has no units")

	# Player 1 activates first unit
	var result1 = fight_phase.execute_action({
		"type": "SELECT_FIGHTER",
		"unit_id": "P1_CHARGED_1"
	})
	assert_true(result1.success)
	_complete_unit_activation("P1_CHARGED_1")

	# Player 1 should continue (not switch to Player 2)
	assert_eq(fight_phase.current_selecting_player, 1, "Player 1 should continue since Player 2 has no units")

	# Player 1 activates second unit
	var result2 = fight_phase.execute_action({
		"type": "SELECT_FIGHTER",
		"unit_id": "P1_CHARGED_2"
	})
	assert_true(result2.success)
	_complete_unit_activation("P1_CHARGED_2")

	# Should still be Player 1's turn for any remaining units
	assert_eq(fight_phase.current_selecting_player, 1)

func test_subphase_transition_resets_to_defending_player():
	"""Verify Remaining Combats subphase starts with defending player again"""
	test_state = _create_scenario_fights_first_then_normal()

	_game_state.state["meta"]["active_player"] = 1
	fight_phase.enter_phase(test_state)

	# Complete all Fights First activations
	# Player 2 goes first (defender)
	_complete_unit_activation_as_player("P2_CHARGED", 2)

	# Should transition to Remaining Combats
	assert_eq(fight_phase.current_subphase, fight_phase.Subphase.REMAINING_COMBATS)

	# Should reset to defending player (Player 2)
	assert_eq(fight_phase.current_selecting_player, 2, "Should reset to defending player for Remaining Combats")

func test_wrong_player_cannot_select():
	"""Verify only current selecting player can select units"""
	test_state = _create_scenario_both_players_have_charged_units()

	_game_state.state["meta"]["active_player"] = 1
	fight_phase.enter_phase(test_state)

	# Player 2 should select first
	assert_eq(fight_phase.current_selecting_player, 2)

	# Player 1 tries to select (should fail)
	var result = fight_phase.execute_action({
		"type": "SELECT_FIGHTER",
		"unit_id": "P1_CHARGED_1"  # Player 1's unit
	})

	assert_false(result.success, "Player 1 should not be able to select when it's Player 2's turn")
	assert_true("Not your turn" in str(result.get("errors", [])), "Should have 'Not your turn' error")

# Helper Functions

func _complete_unit_activation(unit_id: String) -> void:
	"""Complete full activation sequence for a unit"""
	# Pile in
	fight_phase.execute_action({
		"type": "PILE_IN",
		"unit_id": unit_id,
		"movements": {}
	})

	# Assign attacks (simplified)
	fight_phase.execute_action({
		"type": "ASSIGN_ATTACKS",
		"unit_id": unit_id,
		"target_id": "ENEMY_UNIT",
		"weapon_id": "chainsword",
		"attacking_models": ["0"]
	})

	# Confirm and resolve
	fight_phase.execute_action({
		"type": "CONFIRM_AND_RESOLVE_ATTACKS"
	})

	# Roll dice
	fight_phase.execute_action({
		"type": "ROLL_DICE"
	})

	# Consolidate
	fight_phase.execute_action({
		"type": "CONSOLIDATE",
		"unit_id": unit_id,
		"movements": {}
	})

func _complete_unit_activation_as_player(unit_id: String, player: int) -> void:
	"""Helper that verifies it's the right player's turn before completing activation"""
	assert_eq(fight_phase.current_selecting_player, player, "Should be Player %d's turn" % player)
	_complete_unit_activation(unit_id)

func _create_scenario_both_players_have_charged_units() -> Dictionary:
	"""Both players have 1 charged unit each"""
	return {
		"units": {
			"P1_CHARGED_1": {
				"id": "P1_CHARGED_1",
				"owner": 1,
				"flags": {"charged_this_turn": true},
				"meta": {"name": "SM Intercessors", "weapons": {"chainsword": {}}},
				"models": [{"id": "0", "position": {"x": 100, "y": 100}, "alive": true}]
			},
			"P2_CHARGED_1": {
				"id": "P2_CHARGED_1",
				"owner": 2,
				"flags": {"charged_this_turn": true},
				"meta": {"name": "Ork Boyz", "weapons": {"choppa": {}}},
				"models": [{"id": "0", "position": {"x": 125, "y": 100}, "alive": true}]
			},
			"ENEMY_UNIT": {
				"id": "ENEMY_UNIT",
				"owner": 1,
				"flags": {},
				"meta": {"name": "Target Dummy"},
				"models": [{"id": "0", "position": {"x": 150, "y": 100}, "alive": true}]
			}
		}
	}

func _create_scenario_multiple_units_per_player() -> Dictionary:
	"""Both players have 2 charged units each for alternation testing"""
	return {
		"units": {
			"P1_CHARGED_1": _create_unit("P1_CHARGED_1", 1, Vector2(100, 100), true),
			"P1_CHARGED_2": _create_unit("P1_CHARGED_2", 1, Vector2(100, 150), true),
			"P2_CHARGED_1": _create_unit("P2_CHARGED_1", 2, Vector2(125, 100), true),
			"P2_CHARGED_2": _create_unit("P2_CHARGED_2", 2, Vector2(125, 150), true),
			"ENEMY_UNIT": _create_unit("ENEMY_UNIT", 1, Vector2(150, 100), false)
		}
	}

func _create_scenario_only_player_1_has_units() -> Dictionary:
	"""Only Player 1 has charged units (tests 'one player continues' rule)"""
	return {
		"units": {
			"P1_CHARGED_1": _create_unit("P1_CHARGED_1", 1, Vector2(100, 100), true),
			"P1_CHARGED_2": _create_unit("P1_CHARGED_2", 1, Vector2(100, 150), true),
			"P2_NORMAL": _create_unit("P2_NORMAL", 2, Vector2(125, 100), false),  # Not charged
			"ENEMY_UNIT": _create_unit("ENEMY_UNIT", 2, Vector2(150, 100), false)
		}
	}

func _create_scenario_fights_first_then_normal() -> Dictionary:
	"""Mix of charged and normal units to test subphase transition"""
	return {
		"units": {
			"P2_CHARGED": _create_unit("P2_CHARGED", 2, Vector2(100, 100), true),
			"P1_NORMAL": _create_unit("P1_NORMAL", 1, Vector2(125, 100), false),
			"P2_NORMAL": _create_unit("P2_NORMAL", 2, Vector2(125, 150), false),
			"ENEMY_UNIT": _create_unit("ENEMY_UNIT", 1, Vector2(150, 100), false)
		}
	}

func _create_unit(unit_id: String, owner: int, pos: Vector2, charged: bool) -> Dictionary:
	return {
		"id": unit_id,
		"owner": owner,
		"flags": {"charged_this_turn": charged},
		"meta": {
			"name": "%s Unit" % unit_id,
			"weapons": {"chainsword": {"type": "Melee", "attacks": 2}}
		},
		"models": [{
			"id": "0",
			"position": {"x": pos.x, "y": pos.y},
			"alive": true,
			"current_wounds": 2,
			"max_wounds": 2
		}]
	}
