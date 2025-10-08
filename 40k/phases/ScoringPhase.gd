extends BasePhase
class_name ScoringPhase

# ScoringPhase - Placeholder phase for scoring functionality
# Currently just provides "End Turn" functionality to switch between players

func _on_phase_enter() -> void:
	phase_type = GameStateData.Phase.SCORING
	print("ScoringPhase: Entering scoring phase for player ", get_current_player())
	print("ScoringPhase: Current battle round ", GameState.get_battle_round())

func _on_phase_exit() -> void:
	print("ScoringPhase: Exiting scoring phase")

func get_available_actions() -> Array:
	return [
		{
			"type": "END_SCORING",
			"description": "End Turn",
			"player": get_current_player()
		}
	]

func validate_action(action: Dictionary) -> Dictionary:
	var errors = []
	var action_type = action.get("type", "")

	match action_type:
		"END_SCORING", "END_TURN":  # Support both for backward compatibility
			# END_SCORING/END_TURN is always valid in scoring phase
			pass
		_:
			errors.append("Unknown action type: %s" % action_type)

	return {
		"valid": errors.size() == 0,
		"errors": errors
	}

func process_action(action: Dictionary) -> Dictionary:
	match action.get("type", ""):
		"END_SCORING", "END_TURN":  # Support both for backward compatibility
			return _handle_end_turn()
		_:
			return {"success": false, "error": "Unknown action type"}

func _handle_end_turn() -> Dictionary:
	var current_player = get_current_player()
	var next_player = 2 if current_player == 1 else 1
	
	print("ScoringPhase: Player %d ending turn, switching to player %d" % [current_player, next_player])
	
	# Create state changes to switch player
	var changes = [
		{
			"op": "set",
			"path": "meta.active_player",
			"value": next_player
		}
	]
	
	# If Player 2 just finished their turn, advance battle round
	if current_player == 2:
		var new_battle_round = GameState.get_battle_round() + 1
		print("ScoringPhase: Completing battle round, advancing to battle round %d" % new_battle_round)
		
		changes.append({
			"op": "set",
			"path": "meta.battle_round",
			"value": new_battle_round
		})
	
	return {
		"success": true,
		"changes": changes,
		"message": "Turn ended, control switched to player %d" % next_player
	}

func _should_complete_phase() -> bool:
	# Scoring phase completes immediately after END_TURN action
	return true