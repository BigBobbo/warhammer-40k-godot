extends BasePhase
class_name CommandPhase

const BasePhase = preload("res://phases/BasePhase.gd")


# CommandPhase - Handles the Command Phase of each player's turn
# Steps: 1) Generate CP  2) Resolve abilities  3) Battle-shock tests (future)

func _on_phase_enter() -> void:
	phase_type = GameStateData.Phase.COMMAND
	var current_player = get_current_player()
	var battle_round = GameState.get_battle_round()
	print("CommandPhase: Entering command phase for player ", current_player)
	print("CommandPhase: Battle round ", battle_round)

	# Step 1: Generate Command Points
	# Per 10th edition rules, both players gain 1 CP at the start of each Command Phase
	_generate_command_points(current_player)

	# Check objectives at start of command phase
	if MissionManager:
		MissionManager.check_all_objectives()

func _generate_command_points(active_player: int) -> void:
	var opponent = 1 if active_player == 2 else 2
	var changes = []

	# Active player gains 1 CP
	var active_cp = GameState.state.get("players", {}).get(str(active_player), {}).get("cp", 0)
	changes.append({
		"op": "set",
		"path": "players.%s.cp" % str(active_player),
		"value": active_cp + 1
	})

	# Opponent also gains 1 CP
	var opponent_cp = GameState.state.get("players", {}).get(str(opponent), {}).get("cp", 0)
	changes.append({
		"op": "set",
		"path": "players.%s.cp" % str(opponent),
		"value": opponent_cp + 1
	})

	# Apply via PhaseManager so changes propagate to network peers
	PhaseManager.apply_state_changes(changes)

	# Refresh our local snapshot to reflect the CP changes
	game_state_snapshot = GameState.create_snapshot()

	print("CommandPhase: Generated CP — Player %d: %d → %d, Player %d: %d → %d" % [
		active_player, active_cp, active_cp + 1,
		opponent, opponent_cp, opponent_cp + 1
	])

func _on_phase_exit() -> void:
	print("CommandPhase: Exiting command phase")

func get_available_actions() -> Array:
	return [
		{
			"type": "END_COMMAND",
			"description": "End Command Phase",
			"player": get_current_player()
		}
	]

func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	# Check base phase validation first (handles DEBUG_MOVE)
	var base_validation = super.validate_action(action)
	if not base_validation.get("valid", true):
		return base_validation

	var errors = []

	match action_type:
		"END_COMMAND":
			# END_COMMAND is always valid in command phase
			pass
		"DEBUG_MOVE":
			# Already validated by base class
			return {"valid": true, "errors": []}
		_:
			errors.append("Unknown action type: %s" % action_type)

	return {
		"valid": errors.size() == 0,
		"errors": errors
	}

func process_action(action: Dictionary) -> Dictionary:
	match action.get("type", ""):
		"END_COMMAND":
			return _handle_end_command()
		_:
			return {"success": false, "error": "Unknown action type"}

func _handle_end_command() -> Dictionary:
	var current_player = get_current_player()
	
	print("CommandPhase: Player %d ending command phase" % current_player)
	
	# Score primary objectives before ending phase
	if MissionManager:
		MissionManager.score_primary_objectives()
	
	# Emit phase completion signal to proceed to next phase
	emit_signal("phase_completed")
	
	# No state changes needed - just complete the phase
	return {
		"success": true,
		"message": "Command phase ended, objectives scored"
	}

func _should_complete_phase() -> bool:
	# Don't auto-complete - phase completion will be triggered by END_COMMAND action
	return false
