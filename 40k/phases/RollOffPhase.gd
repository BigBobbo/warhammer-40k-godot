extends BasePhase
class_name RollOffPhase

const BasePhase = preload("res://phases/BasePhase.gd")

# RollOffPhase - Determines which player takes the first turn
# Per 10th edition rules:
# - After deployment (and Scout moves), players roll off (each rolls 1D6)
# - The winner chooses who takes the first turn
# - If tied, re-roll until there is a winner
# - The player who goes first is the Attacker; the other is the Defender

var _rng: RandomNumberGenerator
var _player1_roll: int = 0
var _player2_roll: int = 0
var _roll_off_winner: int = 0  # Player who won the roll-off (gets to choose)
var _first_turn_player: int = 0  # Player who will actually go first
var _roll_complete: bool = false
var _choice_made: bool = false

func _init():
	_rng = RandomNumberGenerator.new()
	_rng.randomize()

func _on_phase_enter() -> void:
	phase_type = GameStateData.Phase.ROLL_OFF
	_player1_roll = 0
	_player2_roll = 0
	_roll_off_winner = 0
	_first_turn_player = 0
	_roll_complete = false
	_choice_made = false
	log_phase_message("Entering Roll-Off Phase — determining first turn")

func _on_phase_exit() -> void:
	log_phase_message("Exiting Roll-Off Phase — Player %d will go first" % _first_turn_player)

func get_available_actions() -> Array:
	var actions = []

	if not _roll_complete:
		# Roll-off hasn't happened yet
		actions.append({
			"type": "ROLL_FOR_FIRST_TURN",
			"description": "Roll off to determine first turn",
			"player": get_current_player()
		})
	elif not _choice_made:
		# Roll-off done, winner needs to choose
		actions.append({
			"type": "CHOOSE_TURN_ORDER",
			"choice": "first",
			"description": "Player %d chooses to go FIRST" % _roll_off_winner,
			"player": _roll_off_winner
		})
		actions.append({
			"type": "CHOOSE_TURN_ORDER",
			"choice": "second",
			"description": "Player %d chooses to go SECOND" % _roll_off_winner,
			"player": _roll_off_winner
		})

	return actions

func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	# Check base phase validation first (handles DEBUG_MOVE)
	var base_validation = super.validate_action(action)
	if not base_validation.get("valid", true):
		return base_validation

	var errors = []

	match action_type:
		"ROLL_FOR_FIRST_TURN":
			if _roll_complete:
				errors.append("Roll-off has already been completed")
		"CHOOSE_TURN_ORDER":
			if not _roll_complete:
				errors.append("Roll-off has not been completed yet")
			if _choice_made:
				errors.append("Turn order choice has already been made")
			var choice = action.get("choice", "")
			if choice != "first" and choice != "second":
				errors.append("Invalid choice: must be 'first' or 'second'")
		_:
			errors.append("Unknown action type for Roll-Off phase: %s" % action_type)

	return {
		"valid": errors.size() == 0,
		"errors": errors
	}

func process_action(action: Dictionary) -> Dictionary:
	match action.get("type", ""):
		"ROLL_FOR_FIRST_TURN":
			return _handle_roll_for_first_turn(action)
		"CHOOSE_TURN_ORDER":
			return _handle_choose_turn_order(action)
		_:
			return {"success": false, "error": "Unknown action type"}

func _handle_roll_for_first_turn(action: Dictionary) -> Dictionary:
	# Allow overriding rolls for deterministic testing
	var p1_roll: int
	var p2_roll: int

	if action.has("dice_roll"):
		var rolls = action.get("dice_roll", [])
		p1_roll = rolls[0] if rolls.size() > 0 else _rng.randi_range(1, 6)
		p2_roll = rolls[1] if rolls.size() > 1 else _rng.randi_range(1, 6)
	else:
		p1_roll = _rng.randi_range(1, 6)
		p2_roll = _rng.randi_range(1, 6)

	_player1_roll = p1_roll
	_player2_roll = p2_roll

	log_phase_message("Roll-off: Player 1 rolled %d, Player 2 rolled %d" % [p1_roll, p2_roll])

	if p1_roll == p2_roll:
		# Tie — must re-roll per the rules
		log_phase_message("Roll-off tied at %d — players must re-roll" % p1_roll)
		_player1_roll = 0
		_player2_roll = 0
		_roll_complete = false

		return {
			"success": true,
			"player1_roll": p1_roll,
			"player2_roll": p2_roll,
			"tied": true,
			"message": "Roll-off tied at %d! Re-roll required." % p1_roll,
			"log_text": "Roll-off: Player 1 = %d, Player 2 = %d — TIED, re-roll!" % [p1_roll, p2_roll]
		}

	# Determine winner
	if p1_roll > p2_roll:
		_roll_off_winner = 1
	else:
		_roll_off_winner = 2

	_roll_complete = true

	log_phase_message("Player %d wins the roll-off (%d vs %d)" % [_roll_off_winner, p1_roll, p2_roll])

	# Store roll-off results in game state meta
	var changes = [
		{"op": "set", "path": "meta.roll_off_player1_roll", "value": p1_roll},
		{"op": "set", "path": "meta.roll_off_player2_roll", "value": p2_roll},
		{"op": "set", "path": "meta.roll_off_winner", "value": _roll_off_winner}
	]

	return {
		"success": true,
		"changes": changes,
		"player1_roll": p1_roll,
		"player2_roll": p2_roll,
		"winner": _roll_off_winner,
		"tied": false,
		"message": "Player %d wins the roll-off (%d vs %d) and chooses who goes first!" % [_roll_off_winner, p1_roll, p2_roll],
		"log_text": "Roll-off: Player 1 = %d, Player 2 = %d — Player %d wins!" % [p1_roll, p2_roll, _roll_off_winner]
	}

func _handle_choose_turn_order(action: Dictionary) -> Dictionary:
	var choice = action.get("choice", "first")

	if choice == "first":
		_first_turn_player = _roll_off_winner
	else:
		_first_turn_player = 3 - _roll_off_winner  # The other player

	_choice_made = true

	log_phase_message("Player %d chose to go %s — Player %d takes the first turn" % [
		_roll_off_winner, choice.to_upper(), _first_turn_player
	])

	# Store the choice and set the active player for the first turn
	var changes = [
		{"op": "set", "path": "meta.roll_off_choice", "value": choice},
		{"op": "set", "path": "meta.first_turn_player", "value": _first_turn_player},
		{"op": "set", "path": "meta.active_player", "value": _first_turn_player}
	]

	return {
		"success": true,
		"changes": changes,
		"first_turn_player": _first_turn_player,
		"choice": choice,
		"message": "Player %d will take the first turn!" % _first_turn_player,
		"log_text": "Player %d chose %s — Player %d takes the first turn" % [_roll_off_winner, choice, _first_turn_player]
	}

func _should_complete_phase() -> bool:
	# Phase completes when both the roll and choice are done
	return _roll_complete and _choice_made
