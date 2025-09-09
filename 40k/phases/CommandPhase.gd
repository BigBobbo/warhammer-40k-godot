extends BasePhase
class_name CommandPhase

# CommandPhase - Placeholder phase for command functionality
# Currently just provides "End Command Phase" functionality to proceed to Movement

func _on_phase_enter() -> void:
	phase_type = GameStateData.Phase.COMMAND
	print("CommandPhase: Entering command phase for player ", get_current_player())
	print("CommandPhase: Battle round ", GameState.get_battle_round())

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
	var errors = []
	var action_type = action.get("type", "")
	
	match action_type:
		"END_COMMAND":
			# END_COMMAND is always valid in command phase
			pass
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
	
	print("CommandPhase: Player %d ending command phase, proceeding to movement" % current_player)
	
	# Emit phase completion signal to proceed to next phase
	emit_signal("phase_completed")
	
	# No state changes needed - just complete the phase
	return {
		"success": true,
		"message": "Command phase ended, proceeding to movement phase"
	}

func _should_complete_phase() -> bool:
	# Don't auto-complete - phase completion will be triggered by END_COMMAND action
	return false