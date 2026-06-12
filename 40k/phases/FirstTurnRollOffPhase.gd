extends BasePhase
class_name FirstTurnRollOffPhase

const BasePhase = preload("res://phases/BasePhase.gd")

# FirstTurnRollOffPhase — "Determine First Turn" roll-off.
#
# 10th edition: AFTER both armies have been deployed (and any redeployment
# abilities resolved), both players roll a D6. The winner TAKES THE FIRST
# TURN — there is no choice. (This is independent of the pre-deployment
# Attacker/Defender roll-off handled by RollOffPhase.)
#
# Flow:
#   ROLL_OFF_FIRST_TURN  — both roll; higher roll wins and becomes
#                          meta.first_turn_player. Ties re-roll.
#   CONFIRM_FIRST_TURN   — acknowledgement that completes the phase. A human
#                          clicks "Continue" on the dialog; the AI dispatches
#                          it automatically in an AI-vs-AI game. This keeps the
#                          dramatic result on screen until it is dismissed.
#
# Placed between REDEPLOYMENT and SCOUT so the first-turn player is known
# before pre-game Scout moves (which are made in first-turn order).

var _rng  # RulesEngine.RNGService — honours static test_mode_seed
var _player1_roll: int = 0
var _player2_roll: int = 0
var _first_turn_player: int = 0
var _roll_complete: bool = false
var _confirmed: bool = false

func _init():
	_rng = RulesEngine.make_rng()

func _on_phase_enter() -> void:
	phase_type = GameStateData.Phase.FIRST_TURN_ROLLOFF
	_player1_roll = 0
	_player2_roll = 0
	_first_turn_player = 0
	_roll_complete = false
	_confirmed = false
	log_phase_message("Entering First-Turn Roll-Off — determining who takes the first turn")

func _on_phase_exit() -> void:
	log_phase_message("Exiting First-Turn Roll-Off — Player %d takes the first turn" % _first_turn_player)

func get_available_actions() -> Array:
	var actions = []

	if not _roll_complete:
		actions.append({
			"type": "ROLL_OFF_FIRST_TURN",
			"description": "Roll off to determine who takes the first turn",
			"player": get_current_player()
		})
	elif not _confirmed:
		# No choice — the winner goes first. Just an acknowledgement to proceed.
		actions.append({
			"type": "CONFIRM_FIRST_TURN",
			"description": "Begin the battle — Player %d takes the first turn" % _first_turn_player,
			"player": get_current_player()
		})

	return actions

func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	var base_validation = super.validate_action(action)
	if not base_validation.get("valid", true):
		return base_validation

	var errors = []

	match action_type:
		"ROLL_OFF_FIRST_TURN":
			if _roll_complete:
				errors.append("First-turn roll-off has already been completed")
		"CONFIRM_FIRST_TURN":
			if not _roll_complete:
				errors.append("First-turn roll-off has not been completed yet")
			if _confirmed:
				errors.append("First turn has already been confirmed")
		_:
			errors.append("Unknown action type for First-Turn Roll-Off phase: %s" % action_type)

	return {
		"valid": errors.size() == 0,
		"errors": errors
	}

func process_action(action: Dictionary) -> Dictionary:
	match action.get("type", ""):
		"ROLL_OFF_FIRST_TURN":
			return _handle_roll_off(action)
		"CONFIRM_FIRST_TURN":
			return _handle_confirm(action)
		_:
			return {"success": false, "error": "Unknown action type"}

func _handle_roll_off(action: Dictionary) -> Dictionary:
	var p1_roll: int
	var p2_roll: int

	var rng_seed: int = action.get("payload", {}).get("rng_seed", -1)
	var rng_inst = RulesEngine.RNGService.new(rng_seed) if rng_seed >= 0 else _rng
	if action.has("dice_roll"):
		var rolls = action.get("dice_roll", [])
		p1_roll = rolls[0] if rolls.size() > 0 else rng_inst.rng.randi_range(1, 6)
		p2_roll = rolls[1] if rolls.size() > 1 else rng_inst.rng.randi_range(1, 6)
	else:
		p1_roll = rng_inst.rng.randi_range(1, 6)
		p2_roll = rng_inst.rng.randi_range(1, 6)

	_player1_roll = p1_roll
	_player2_roll = p2_roll

	log_phase_message("First-turn roll-off: Player 1 rolled %d, Player 2 rolled %d" % [p1_roll, p2_roll])

	if p1_roll == p2_roll:
		log_phase_message("First-turn roll-off tied at %d — players must re-roll" % p1_roll)
		_player1_roll = 0
		_player2_roll = 0
		_roll_complete = false
		return {
			"success": true,
			"player1_roll": p1_roll,
			"player2_roll": p2_roll,
			"tied": true,
			"message": "Roll-off tied at %d! Re-roll required." % p1_roll,
			"log_text": "First-turn roll-off: Player 1 = %d, Player 2 = %d — TIED, re-roll!" % [p1_roll, p2_roll]
		}

	# Higher roll wins and takes the first turn — no choice.
	_first_turn_player = 1 if p1_roll > p2_roll else 2
	_roll_complete = true

	log_phase_message("Player %d wins the first-turn roll-off (%d vs %d) and TAKES THE FIRST TURN" % [_first_turn_player, p1_roll, p2_roll])

	# Apply the first-turn result immediately. Seat the winner as active so
	# pre-game Scout moves (next phase) are made in first-turn order; the
	# winner is the player who takes battle round 1.
	var changes = [
		{"op": "set", "path": "meta.first_turn_roll_player1", "value": p1_roll},
		{"op": "set", "path": "meta.first_turn_roll_player2", "value": p2_roll},
		{"op": "set", "path": "meta.first_turn_player", "value": _first_turn_player},
		{"op": "set", "path": "meta.active_player", "value": _first_turn_player}
	]

	return {
		"success": true,
		"changes": changes,
		"player1_roll": p1_roll,
		"player2_roll": p2_roll,
		"winner": _first_turn_player,
		"first_turn_player": _first_turn_player,
		"tied": false,
		"message": "Player %d takes the first turn!" % _first_turn_player,
		"log_text": "First-turn roll-off: Player 1 = %d, Player 2 = %d — Player %d takes the first turn!" % [p1_roll, p2_roll, _first_turn_player]
	}

func _handle_confirm(action: Dictionary) -> Dictionary:
	_confirmed = true
	log_phase_message("First turn confirmed — Player %d begins the battle" % _first_turn_player)
	return {
		"success": true,
		"first_turn_player": _first_turn_player,
		"message": "Battle begins — Player %d takes the first turn." % _first_turn_player,
		"log_text": "First turn confirmed — Player %d goes first" % _first_turn_player
	}

func _should_complete_phase() -> bool:
	# Complete once the roll resolved a winner AND it has been acknowledged.
	return _roll_complete and _confirmed
