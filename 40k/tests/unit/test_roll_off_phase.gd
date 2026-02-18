extends "res://addons/gut/test.gd"

# Tests for the First Turn Roll-Off implementation (T3-7)
#
# Per Warhammer 40k 10th Edition rules:
# After deployment and Scout moves, players roll off (each rolls 1D6).
# The winner chooses who takes the first turn.
# If tied, re-roll until there is a winner.
# The player who goes first is the Attacker; the other is the Defender.
#
# These tests verify:
# 1. ROLL_OFF phase exists in Phase enum
# 2. Phase transitions: SCOUT → ROLL_OFF → COMMAND
# 3. Roll-off mechanics (winner determination, tie handling)
# 4. Turn order choice (winner picks first or second)
# 5. Active player set correctly after choice
# 6. Roll-off data stored in game state meta

const GameStateData = preload("res://autoloads/GameState.gd")
const RollOffPhaseScript = preload("res://phases/RollOffPhase.gd")

var game_state_node: Node
var phase: Node

# ==========================================
# Setup / Teardown
# ==========================================

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	game_state_node = AutoloadHelper.get_game_state()
	assert_not_null(game_state_node, "GameState autoload must be available")

func after_each():
	if phase:
		phase.queue_free()
		phase = null

# ==========================================
# Helpers
# ==========================================

func _create_roll_off_test_state() -> Dictionary:
	"""Create a test game state for roll-off phase."""
	return {
		"game_id": "test_roll_off",
		"meta": {
			"active_player": 1,
			"turn_number": 1,
			"battle_round": 1,
			"phase": GameStateData.Phase.ROLL_OFF
		},
		"units": {},
		"board": {
			"size": {"width": 44, "height": 60},
			"deployment_zones": [],
			"objectives": [],
			"terrain": [],
			"terrain_features": []
		},
		"players": {
			"1": {"cp": 0, "vp": 0},
			"2": {"cp": 0, "vp": 0}
		},
		"factions": {},
		"phase_log": [],
		"history": []
	}

func _setup_phase_with_state(test_state: Dictionary) -> void:
	"""Create a RollOffPhase and enter it with the given state."""
	# Set game state
	GameState.state = test_state

	# Create phase instance
	var phase_node = Node.new()
	phase_node.set_script(RollOffPhaseScript)
	phase = phase_node
	add_child(phase)

	# Enter phase
	phase.enter_phase(test_state)

# ==========================================
# Phase Enum Tests
# ==========================================

func test_roll_off_phase_exists_in_enum():
	"""ROLL_OFF should exist in the Phase enum between SCOUT and COMMAND."""
	var roll_off_value = GameStateData.Phase.ROLL_OFF
	var scout_value = GameStateData.Phase.SCOUT
	var command_value = GameStateData.Phase.COMMAND
	assert_true(roll_off_value > scout_value, "ROLL_OFF should be after SCOUT")
	assert_true(roll_off_value < command_value, "ROLL_OFF should be before COMMAND")

# ==========================================
# Phase Transition Tests
# ==========================================

func test_phase_manager_transitions_scout_to_roll_off():
	"""PhaseManager._get_next_phase should return ROLL_OFF after SCOUT."""
	var pm = get_node_or_null("/root/PhaseManager")
	if not pm:
		pending("PhaseManager autoload not available")
		return
	var next = pm._get_next_phase(GameStateData.Phase.SCOUT)
	assert_eq(next, GameStateData.Phase.ROLL_OFF, "Next phase after SCOUT should be ROLL_OFF")

func test_phase_manager_transitions_roll_off_to_command():
	"""PhaseManager._get_next_phase should return COMMAND after ROLL_OFF."""
	var pm = get_node_or_null("/root/PhaseManager")
	if not pm:
		pending("PhaseManager autoload not available")
		return
	var next = pm._get_next_phase(GameStateData.Phase.ROLL_OFF)
	assert_eq(next, GameStateData.Phase.COMMAND, "Next phase after ROLL_OFF should be COMMAND")

# ==========================================
# Roll-Off Initialization Tests
# ==========================================

func test_roll_off_phase_initializes_correctly():
	"""RollOffPhase should initialize with no rolls and no winner."""
	var test_state = _create_roll_off_test_state()
	_setup_phase_with_state(test_state)

	assert_eq(phase._player1_roll, 0, "Player 1 roll should start at 0")
	assert_eq(phase._player2_roll, 0, "Player 2 roll should start at 0")
	assert_eq(phase._roll_off_winner, 0, "Winner should start at 0")
	assert_eq(phase._first_turn_player, 0, "First turn player should start at 0")
	assert_false(phase._roll_complete, "Roll should not be complete initially")
	assert_false(phase._choice_made, "Choice should not be made initially")

# ==========================================
# Roll-Off Action Tests
# ==========================================

func test_roll_off_available_actions_before_roll():
	"""Before rolling, only ROLL_FOR_FIRST_TURN should be available."""
	var test_state = _create_roll_off_test_state()
	_setup_phase_with_state(test_state)

	var actions = phase.get_available_actions()
	assert_eq(actions.size(), 1, "Should have exactly 1 available action")
	assert_eq(actions[0].type, "ROLL_FOR_FIRST_TURN", "Action should be ROLL_FOR_FIRST_TURN")

func test_roll_off_player1_wins():
	"""When Player 1 rolls higher, Player 1 wins the roll-off."""
	var test_state = _create_roll_off_test_state()
	_setup_phase_with_state(test_state)

	# Player 1 rolls 6, Player 2 rolls 3
	var result = phase.process_action({
		"type": "ROLL_FOR_FIRST_TURN",
		"dice_roll": [6, 3]
	})

	assert_true(result.success, "Roll should succeed")
	assert_false(result.tied, "Roll should not be tied")
	assert_eq(result.winner, 1, "Player 1 should win")
	assert_eq(phase._roll_off_winner, 1, "Internal winner should be Player 1")
	assert_true(phase._roll_complete, "Roll should be complete")

func test_roll_off_player2_wins():
	"""When Player 2 rolls higher, Player 2 wins the roll-off."""
	var test_state = _create_roll_off_test_state()
	_setup_phase_with_state(test_state)

	# Player 1 rolls 2, Player 2 rolls 5
	var result = phase.process_action({
		"type": "ROLL_FOR_FIRST_TURN",
		"dice_roll": [2, 5]
	})

	assert_true(result.success, "Roll should succeed")
	assert_false(result.tied, "Roll should not be tied")
	assert_eq(result.winner, 2, "Player 2 should win")

func test_roll_off_tie_requires_reroll():
	"""When both players roll the same, a re-roll is required."""
	var test_state = _create_roll_off_test_state()
	_setup_phase_with_state(test_state)

	# Both roll 4
	var result = phase.process_action({
		"type": "ROLL_FOR_FIRST_TURN",
		"dice_roll": [4, 4]
	})

	assert_true(result.success, "Tied roll should still succeed")
	assert_true(result.tied, "Roll should be marked as tied")
	assert_false(phase._roll_complete, "Roll should NOT be complete after tie")

	# ROLL_FOR_FIRST_TURN should still be available
	var actions = phase.get_available_actions()
	assert_eq(actions.size(), 1, "Should still have 1 available action after tie")
	assert_eq(actions[0].type, "ROLL_FOR_FIRST_TURN", "Should be able to re-roll")

func test_roll_off_tie_then_winner():
	"""After a tie, a subsequent non-tied roll should determine the winner."""
	var test_state = _create_roll_off_test_state()
	_setup_phase_with_state(test_state)

	# First roll: tie
	phase.process_action({
		"type": "ROLL_FOR_FIRST_TURN",
		"dice_roll": [3, 3]
	})

	# Second roll: Player 2 wins
	var result = phase.process_action({
		"type": "ROLL_FOR_FIRST_TURN",
		"dice_roll": [1, 6]
	})

	assert_true(result.success, "Second roll should succeed")
	assert_false(result.tied, "Second roll should not be tied")
	assert_eq(result.winner, 2, "Player 2 should win the second roll")
	assert_true(phase._roll_complete, "Roll should be complete after non-tied re-roll")

# ==========================================
# Turn Order Choice Tests
# ==========================================

func test_choose_first_turn_as_winner():
	"""Winner choosing 'first' should set themselves as first turn player."""
	var test_state = _create_roll_off_test_state()
	_setup_phase_with_state(test_state)

	# Player 1 wins
	phase.process_action({
		"type": "ROLL_FOR_FIRST_TURN",
		"dice_roll": [6, 2]
	})

	# Player 1 chooses to go first
	var result = phase.process_action({
		"type": "CHOOSE_TURN_ORDER",
		"choice": "first"
	})

	assert_true(result.success, "Choice should succeed")
	assert_eq(result.first_turn_player, 1, "Player 1 should go first")
	assert_true(phase._choice_made, "Choice should be marked as made")

func test_choose_second_turn_as_winner():
	"""Winner choosing 'second' should set the OTHER player as first turn player."""
	var test_state = _create_roll_off_test_state()
	_setup_phase_with_state(test_state)

	# Player 1 wins
	phase.process_action({
		"type": "ROLL_FOR_FIRST_TURN",
		"dice_roll": [5, 1]
	})

	# Player 1 chooses to go second
	var result = phase.process_action({
		"type": "CHOOSE_TURN_ORDER",
		"choice": "second"
	})

	assert_true(result.success, "Choice should succeed")
	assert_eq(result.first_turn_player, 2, "Player 2 should go first when Player 1 chooses second")

func test_available_actions_after_roll():
	"""After a successful roll, CHOOSE_TURN_ORDER options should be available."""
	var test_state = _create_roll_off_test_state()
	_setup_phase_with_state(test_state)

	# Player 2 wins
	phase.process_action({
		"type": "ROLL_FOR_FIRST_TURN",
		"dice_roll": [2, 6]
	})

	var actions = phase.get_available_actions()
	assert_eq(actions.size(), 2, "Should have 2 available actions (first/second)")
	assert_eq(actions[0].type, "CHOOSE_TURN_ORDER", "First action should be CHOOSE_TURN_ORDER")
	assert_eq(actions[0].choice, "first", "First option should be 'first'")
	assert_eq(actions[1].type, "CHOOSE_TURN_ORDER", "Second action should be CHOOSE_TURN_ORDER")
	assert_eq(actions[1].choice, "second", "Second option should be 'second'")

# ==========================================
# Phase Completion Tests
# ==========================================

func test_phase_not_complete_before_roll():
	"""Phase should not auto-complete before rolling."""
	var test_state = _create_roll_off_test_state()
	_setup_phase_with_state(test_state)

	assert_false(phase._should_complete_phase(), "Phase should not complete before roll")

func test_phase_not_complete_after_roll_only():
	"""Phase should not auto-complete after rolling but before choice."""
	var test_state = _create_roll_off_test_state()
	_setup_phase_with_state(test_state)

	phase.process_action({
		"type": "ROLL_FOR_FIRST_TURN",
		"dice_roll": [6, 3]
	})

	assert_false(phase._should_complete_phase(), "Phase should not complete before choice is made")

func test_phase_completes_after_choice():
	"""Phase should auto-complete after both roll and choice are done."""
	var test_state = _create_roll_off_test_state()
	_setup_phase_with_state(test_state)

	phase.process_action({
		"type": "ROLL_FOR_FIRST_TURN",
		"dice_roll": [6, 3]
	})
	phase.process_action({
		"type": "CHOOSE_TURN_ORDER",
		"choice": "first"
	})

	assert_true(phase._should_complete_phase(), "Phase should complete after roll and choice")

# ==========================================
# State Changes Tests
# ==========================================

func test_roll_off_stores_results_in_meta():
	"""Roll-off results should be stored in game state meta via changes."""
	var test_state = _create_roll_off_test_state()
	_setup_phase_with_state(test_state)

	var result = phase.process_action({
		"type": "ROLL_FOR_FIRST_TURN",
		"dice_roll": [5, 3]
	})

	assert_true(result.has("changes"), "Result should have changes array")
	var changes = result.changes

	# Find the roll value changes
	var found_p1_roll = false
	var found_p2_roll = false
	var found_winner = false
	for change in changes:
		if change.path == "meta.roll_off_player1_roll":
			assert_eq(change.value, 5, "Player 1 roll should be stored as 5")
			found_p1_roll = true
		elif change.path == "meta.roll_off_player2_roll":
			assert_eq(change.value, 3, "Player 2 roll should be stored as 3")
			found_p2_roll = true
		elif change.path == "meta.roll_off_winner":
			assert_eq(change.value, 1, "Winner should be stored as Player 1")
			found_winner = true

	assert_true(found_p1_roll, "Should store Player 1 roll in meta")
	assert_true(found_p2_roll, "Should store Player 2 roll in meta")
	assert_true(found_winner, "Should store winner in meta")

func test_choice_sets_active_player_in_changes():
	"""Choosing turn order should set active_player in the state changes."""
	var test_state = _create_roll_off_test_state()
	_setup_phase_with_state(test_state)

	phase.process_action({
		"type": "ROLL_FOR_FIRST_TURN",
		"dice_roll": [4, 6]
	})

	# Player 2 won, chooses to go second (Player 1 goes first)
	var result = phase.process_action({
		"type": "CHOOSE_TURN_ORDER",
		"choice": "second"
	})

	assert_true(result.has("changes"), "Result should have changes array")
	var changes = result.changes

	var found_active_player = false
	var found_first_turn = false
	for change in changes:
		if change.path == "meta.active_player":
			assert_eq(change.value, 1, "Active player should be set to Player 1")
			found_active_player = true
		elif change.path == "meta.first_turn_player":
			assert_eq(change.value, 1, "First turn player should be Player 1")
			found_first_turn = true

	assert_true(found_active_player, "Should set active_player in changes")
	assert_true(found_first_turn, "Should set first_turn_player in changes")

# ==========================================
# Validation Tests
# ==========================================

func test_cannot_roll_twice():
	"""Cannot roll again once roll-off is complete (non-tie)."""
	var test_state = _create_roll_off_test_state()
	_setup_phase_with_state(test_state)

	phase.process_action({
		"type": "ROLL_FOR_FIRST_TURN",
		"dice_roll": [6, 2]
	})

	var validation = phase.validate_action({"type": "ROLL_FOR_FIRST_TURN"})
	assert_false(validation.valid, "Should not be able to roll again after completion")

func test_cannot_choose_before_roll():
	"""Cannot choose turn order before rolling."""
	var test_state = _create_roll_off_test_state()
	_setup_phase_with_state(test_state)

	var validation = phase.validate_action({
		"type": "CHOOSE_TURN_ORDER",
		"choice": "first"
	})
	assert_false(validation.valid, "Should not be able to choose before rolling")

func test_invalid_choice_value():
	"""Invalid choice value should fail validation."""
	var test_state = _create_roll_off_test_state()
	_setup_phase_with_state(test_state)

	phase.process_action({
		"type": "ROLL_FOR_FIRST_TURN",
		"dice_roll": [6, 2]
	})

	var validation = phase.validate_action({
		"type": "CHOOSE_TURN_ORDER",
		"choice": "invalid"
	})
	assert_false(validation.valid, "Invalid choice value should fail validation")
