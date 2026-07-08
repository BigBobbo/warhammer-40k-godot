extends BasePhase
class_name RollOffPhase

const BasePhase = preload("res://phases/BasePhase.gd")

# RollOffPhase — Pre-deployment "Determine Attacker/Defender" roll-off.
#
# 10th edition has TWO independent pre-battle roll-offs:
#   1. THIS phase (before deployment): both players roll a D6; the winner
#      chooses to DEPLOY FIRST (Defender) or DEPLOY SECOND (Attacker). This
#      decides the deployment order ONLY.
#   2. FirstTurnRollOffPhase (after deployment): a separate roll-off whose
#      winner TAKES THE FIRST TURN, with no choice.
#
# Historically this phase did both jobs at once (9th-edition style, where the
# winner's deploy choice also fixed the first turn). That coupling has been
# removed: this phase now sets meta.attacker / meta.defender only and never
# touches meta.first_turn_player.
#
# If the dice tie, players must re-roll (per the core rules).

# Emitted whenever a roll-off resolves (win or tie). This is the ONLY channel
# the UI listens on — in multiplayer the submitting peer gets {pending:true}
# back from route_action, so reading roll results from the return value never
# worked networked. The host emits during processing; NetworkManager re-emits
# on clients from the broadcast result.
signal roll_off_result(p1_roll: int, p2_roll: int, winner: int, tied: bool)

var _rng  # RulesEngine.RNGService — picks up test_mode_seed via PR #346
var _player1_roll: int = 0
var _player2_roll: int = 0
var _roll_off_winner: int = 0  # Player who won the roll-off (gets to choose deploy order)
var _defender: int = 0         # Player who deploys first
var _roll_complete: bool = false
var _choice_made: bool = false

func _init():
	# Issue #329: route through RNGService so static test_mode_seed applies
	_rng = RulesEngine.make_rng()

func _on_phase_enter() -> void:
	phase_type = GameStateData.Phase.ROLL_OFF
	_player1_roll = 0
	_player2_roll = 0
	_roll_off_winner = 0
	_defender = 0
	_roll_complete = false
	_choice_made = false
	log_phase_message("Entering Roll-Off Phase — determining who deploys first")

func _on_phase_exit() -> void:
	log_phase_message("Exiting Roll-Off Phase — Player %d deploys first (Defender)" % _defender)

func get_available_actions() -> Array:
	var actions = []

	if not _roll_complete:
		# Roll-off hasn't happened yet.
		actions.append({
			"type": "ROLL_OFF_DEPLOYMENT",
			"description": "Roll off to determine who deploys first",
			"player": get_current_player()
		})
	elif not _choice_made:
		# Roll-off done — winner picks their deployment role.
		#   choice "first"  = deploy first  = Defender
		#   choice "second" = deploy second = Attacker
		actions.append({
			"type": "CHOOSE_DEPLOYMENT",
			"choice": "first",
			"description": "Player %d chooses to DEPLOY FIRST (Defender)" % _roll_off_winner,
			"player": _roll_off_winner
		})
		actions.append({
			"type": "CHOOSE_DEPLOYMENT",
			"choice": "second",
			"description": "Player %d chooses to DEPLOY SECOND (Attacker)" % _roll_off_winner,
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
		"ROLL_OFF_DEPLOYMENT":
			if _roll_complete:
				errors.append("Deployment roll-off has already been completed")
		"CHOOSE_DEPLOYMENT":
			if not _roll_complete:
				errors.append("Roll-off has not been completed yet")
			if _choice_made:
				errors.append("Deployment choice has already been made")
			# Only the roll-off winner may pick the deploy order. Without this,
			# any peer could submit the choice (it bypasses turn validation as
			# an exempt reactive action). Only enforced when the action claims
			# a player: the networked path always injects one (NetworkIntegration
			# stamps the local player), while direct SP/test dispatches may omit it.
			var choosing_player = action.get("player", -1)
			if _roll_off_winner > 0 and choosing_player != -1 and choosing_player != _roll_off_winner:
				errors.append("Only Player %d (roll-off winner) may choose the deployment order" % _roll_off_winner)
			var choice = action.get("choice", "")
			if choice != "first" and choice != "second":
				errors.append("Invalid choice: must be 'first' (deploy first) or 'second' (deploy second)")
		_:
			errors.append("Unknown action type for Roll-Off phase: %s" % action_type)

	return {
		"valid": errors.size() == 0,
		"errors": errors
	}

func process_action(action: Dictionary) -> Dictionary:
	match action.get("type", ""):
		"ROLL_OFF_DEPLOYMENT":
			return _handle_roll_off(action)
		"CHOOSE_DEPLOYMENT":
			return _handle_choose_deployment(action)
		_:
			return {"success": false, "error": "Unknown action type"}

func _handle_roll_off(action: Dictionary) -> Dictionary:
	# Allow overriding rolls for deterministic testing
	var p1_roll: int
	var p2_roll: int

	# Issue #329: honor payload.rng_seed when provided; fall back to persistent _rng
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

	log_phase_message("Deployment roll-off: Player 1 rolled %d, Player 2 rolled %d" % [p1_roll, p2_roll])

	if p1_roll == p2_roll:
		# Tie — must re-roll per the rules
		log_phase_message("Deployment roll-off tied at %d — players must re-roll" % p1_roll)
		_player1_roll = 0
		_player2_roll = 0
		_roll_complete = false

		emit_signal("roll_off_result", p1_roll, p2_roll, 0, true)
		return {
			"success": true,
			"player1_roll": p1_roll,
			"player2_roll": p2_roll,
			"tied": true,
			"message": "Roll-off tied at %d! Re-roll required." % p1_roll,
			"log_text": "Deployment roll-off: Player 1 = %d, Player 2 = %d — TIED, re-roll!" % [p1_roll, p2_roll]
		}

	# Determine winner
	if p1_roll > p2_roll:
		_roll_off_winner = 1
	else:
		_roll_off_winner = 2

	_roll_complete = true

	log_phase_message("Player %d wins the deployment roll-off (%d vs %d)" % [_roll_off_winner, p1_roll, p2_roll])

	# Store roll-off results in game state meta
	var changes = [
		{"op": "set", "path": "meta.roll_off_player1_roll", "value": p1_roll},
		{"op": "set", "path": "meta.roll_off_player2_roll", "value": p2_roll},
		{"op": "set", "path": "meta.roll_off_winner", "value": _roll_off_winner}
	]

	emit_signal("roll_off_result", p1_roll, p2_roll, _roll_off_winner, false)
	return {
		"success": true,
		"changes": changes,
		"player1_roll": p1_roll,
		"player2_roll": p2_roll,
		"winner": _roll_off_winner,
		"tied": false,
		"message": "Player %d wins the roll-off (%d vs %d) and chooses who deploys first!" % [_roll_off_winner, p1_roll, p2_roll],
		"log_text": "Deployment roll-off: Player 1 = %d, Player 2 = %d — Player %d wins!" % [p1_roll, p2_roll, _roll_off_winner]
	}

func _handle_choose_deployment(action: Dictionary) -> Dictionary:
	# choice "first"  = winner deploys first  → winner is the Defender
	# choice "second" = winner deploys second → winner is the Attacker
	var choice = action.get("choice", "first")

	if choice == "first":
		_defender = _roll_off_winner            # winner deploys first
	else:
		_defender = 3 - _roll_off_winner        # winner deploys second → opponent deploys first

	var attacker_player = 3 - _defender
	_choice_made = true

	log_phase_message("Player %d chose to DEPLOY %s — Player %d (Defender) deploys first, Player %d (Attacker) deploys second" % [
		_roll_off_winner, ("FIRST" if choice == "first" else "SECOND"), _defender, attacker_player
	])

	# Set deployment roles ONLY. The first turn is decided later by the
	# separate FirstTurnRollOffPhase, so meta.first_turn_player is NOT set here.
	# TurnManager._handle_deployment_phase_start reads meta.defender to seat the
	# first deployer.
	var changes = [
		{"op": "set", "path": "meta.roll_off_choice", "value": choice},
		{"op": "set", "path": "meta.attacker", "value": attacker_player},
		{"op": "set", "path": "meta.defender", "value": _defender},
		{"op": "set", "path": "meta.active_player", "value": _defender}
	]

	return {
		"success": true,
		"changes": changes,
		"defender": _defender,
		"attacker": attacker_player,
		"choice": choice,
		"message": "Player %d (Defender) will deploy first." % _defender,
		"log_text": "Player %d chose to deploy %s — Player %d deploys first" % [_roll_off_winner, choice, _defender]
	}

func _should_complete_phase() -> bool:
	# Phase completes when both the roll and the deploy-order choice are done
	return _roll_complete and _choice_made
