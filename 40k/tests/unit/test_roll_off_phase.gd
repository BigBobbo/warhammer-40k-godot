extends "res://addons/gut/test.gd"

# Tests for the TWO independent 10th-edition pre-battle roll-offs.
#
# Per the 10e core rules there are two separate roll-offs:
#   1. RollOffPhase (pre-deployment): both players roll; the winner chooses to
#      DEPLOY FIRST (Defender) or DEPLOY SECOND (Attacker). Sets
#      meta.attacker / meta.defender. Decides deployment order ONLY — it does
#      NOT decide the first turn.
#   2. FirstTurnRollOffPhase (post-deployment): both players roll; the winner
#      TAKES THE FIRST TURN — no choice. Sets meta.first_turn_player.
#
# Standard sequence: FORMATIONS -> ROLL_OFF -> DEPLOYMENT -> REDEPLOYMENT ->
#                    FIRST_TURN_ROLLOFF -> SCOUT -> COMMAND.

const GameStateData = preload("res://autoloads/GameState.gd")
const RollOffPhaseScript = preload("res://phases/RollOffPhase.gd")
const FirstTurnRollOffPhaseScript = preload("res://phases/FirstTurnRollOffPhase.gd")

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

func _base_state(phase_value: int) -> Dictionary:
	return {
		"game_id": "test_roll_off",
		"meta": {
			"active_player": 1,
			"turn_number": 1,
			"battle_round": 1,
			"phase": phase_value
		},
		"units": {},
		"board": {"size": {"width": 44, "height": 60}, "deployment_zones": [], "objectives": [], "terrain": [], "terrain_features": []},
		"players": {"1": {"cp": 0, "vp": 0}, "2": {"cp": 0, "vp": 0}},
		"factions": {},
		"phase_log": [],
		"history": []
	}

func _setup_phase(script: Script, phase_value: int) -> void:
	GameState.state = _base_state(phase_value)
	var phase_node = Node.new()
	phase_node.set_script(script)
	phase = phase_node
	add_child(phase)
	phase.enter_phase(GameState.state)

# ==========================================
# Phase enum / sequence
# ==========================================

func test_both_roll_off_phases_exist_in_enum():
	assert_true(GameStateData.Phase.ROLL_OFF >= 0, "ROLL_OFF exists")
	assert_true(GameStateData.Phase.FIRST_TURN_ROLLOFF >= 0, "FIRST_TURN_ROLLOFF exists")

func test_sequence_predeploy_roll_off_before_deployment():
	var pm = get_node_or_null("/root/PhaseManager")
	if not pm:
		pending("PhaseManager autoload not available")
		return
	assert_eq(pm._get_next_phase(GameStateData.Phase.FORMATIONS), GameStateData.Phase.ROLL_OFF)
	assert_eq(pm._get_next_phase(GameStateData.Phase.ROLL_OFF), GameStateData.Phase.DEPLOYMENT)

func test_sequence_first_turn_roll_off_after_redeployment():
	var pm = get_node_or_null("/root/PhaseManager")
	if not pm:
		pending("PhaseManager autoload not available")
		return
	assert_eq(pm._get_next_phase(GameStateData.Phase.REDEPLOYMENT), GameStateData.Phase.FIRST_TURN_ROLLOFF)
	assert_eq(pm._get_next_phase(GameStateData.Phase.FIRST_TURN_ROLLOFF), GameStateData.Phase.SCOUT)

# ==========================================
# Roll-off #1: deployment order
# ==========================================

func test_deploy_roll_off_winner_higher_roll():
	_setup_phase(RollOffPhaseScript, GameStateData.Phase.ROLL_OFF)
	var result = phase.process_action({"type": "ROLL_OFF_DEPLOYMENT", "dice_roll": [5, 2]})
	assert_true(result.success, "roll succeeds")
	assert_eq(result.winner, 1, "higher roll (P1) wins")

func test_deploy_roll_off_tie_rerolls():
	_setup_phase(RollOffPhaseScript, GameStateData.Phase.ROLL_OFF)
	var result = phase.process_action({"type": "ROLL_OFF_DEPLOYMENT", "dice_roll": [4, 4]})
	assert_true(result.get("tied", false), "tie reported")
	assert_false(phase._should_complete_phase(), "tie does not complete the phase")

func test_deploy_choice_first_makes_winner_defender():
	_setup_phase(RollOffPhaseScript, GameStateData.Phase.ROLL_OFF)
	phase.process_action({"type": "ROLL_OFF_DEPLOYMENT", "dice_roll": [5, 2]})  # P1 wins
	var result = phase.process_action({"type": "CHOOSE_DEPLOYMENT", "choice": "first"})
	assert_eq(result.defender, 1, "deploy first → winner is Defender")
	assert_eq(result.attacker, 2, "opponent is Attacker")

func test_deploy_choice_second_makes_winner_attacker():
	_setup_phase(RollOffPhaseScript, GameStateData.Phase.ROLL_OFF)
	phase.process_action({"type": "ROLL_OFF_DEPLOYMENT", "dice_roll": [5, 2]})  # P1 wins
	var result = phase.process_action({"type": "CHOOSE_DEPLOYMENT", "choice": "second"})
	assert_eq(result.attacker, 1, "deploy second → winner is Attacker")
	assert_eq(result.defender, 2, "opponent is Defender (deploys first)")

func test_deploy_roll_off_does_not_set_first_turn():
	_setup_phase(RollOffPhaseScript, GameStateData.Phase.ROLL_OFF)
	phase.process_action({"type": "ROLL_OFF_DEPLOYMENT", "dice_roll": [5, 2]})
	var result = phase.process_action({"type": "CHOOSE_DEPLOYMENT", "choice": "first"})
	for c in result.get("changes", []):
		assert_ne(c.get("path", ""), "meta.first_turn_player",
			"deploy roll-off must NOT set first_turn_player")

func test_deploy_roll_off_completes_after_choice():
	_setup_phase(RollOffPhaseScript, GameStateData.Phase.ROLL_OFF)
	phase.process_action({"type": "ROLL_OFF_DEPLOYMENT", "dice_roll": [5, 2]})
	assert_false(phase._should_complete_phase(), "not complete before choice")
	phase.process_action({"type": "CHOOSE_DEPLOYMENT", "choice": "first"})
	assert_true(phase._should_complete_phase(), "complete after choice")

# ==========================================
# Roll-off #2: first turn (no choice)
# ==========================================

func test_first_turn_roll_off_winner_goes_first():
	_setup_phase(FirstTurnRollOffPhaseScript, GameStateData.Phase.FIRST_TURN_ROLLOFF)
	var result = phase.process_action({"type": "ROLL_OFF_FIRST_TURN", "dice_roll": [2, 6]})
	assert_eq(result.winner, 2, "higher roll (P2) wins")
	assert_eq(result.first_turn_player, 2, "winner takes the first turn")

func test_first_turn_roll_off_sets_meta():
	_setup_phase(FirstTurnRollOffPhaseScript, GameStateData.Phase.FIRST_TURN_ROLLOFF)
	var result = phase.process_action({"type": "ROLL_OFF_FIRST_TURN", "dice_roll": [6, 2]})
	var found := false
	for c in result.get("changes", []):
		if c.get("path", "") == "meta.first_turn_player" and c.get("value") == 1:
			found = true
	assert_true(found, "sets meta.first_turn_player to the winner")

func test_first_turn_roll_off_no_choice_only_confirm():
	_setup_phase(FirstTurnRollOffPhaseScript, GameStateData.Phase.FIRST_TURN_ROLLOFF)
	phase.process_action({"type": "ROLL_OFF_FIRST_TURN", "dice_roll": [6, 2]})
	var types := []
	for a in phase.get_available_actions():
		types.append(a.get("type", ""))
	assert_eq(types, ["CONFIRM_FIRST_TURN"], "only an acknowledgement is offered — no choice")

func test_first_turn_roll_off_completes_after_confirm():
	_setup_phase(FirstTurnRollOffPhaseScript, GameStateData.Phase.FIRST_TURN_ROLLOFF)
	phase.process_action({"type": "ROLL_OFF_FIRST_TURN", "dice_roll": [6, 2]})
	assert_false(phase._should_complete_phase(), "not complete before confirm")
	phase.process_action({"type": "CONFIRM_FIRST_TURN"})
	assert_true(phase._should_complete_phase(), "complete after confirm")

func test_first_turn_roll_off_tie_rerolls():
	_setup_phase(FirstTurnRollOffPhaseScript, GameStateData.Phase.FIRST_TURN_ROLLOFF)
	var result = phase.process_action({"type": "ROLL_OFF_FIRST_TURN", "dice_roll": [3, 3]})
	assert_true(result.get("tied", false), "tie reported")
	assert_false(phase._should_complete_phase(), "tie does not complete the phase")
