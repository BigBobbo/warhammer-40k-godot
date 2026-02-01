extends BasePhase
class_name ScoringPhase

const BasePhase = preload("res://phases/BasePhase.gd")


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

	# Reset unit flags for the player whose turn is starting
	var changes = _create_flag_reset_changes(next_player)

	# Create state changes to switch player
	changes.append({
		"op": "set",
		"path": "meta.active_player",
		"value": next_player
	})

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

func _create_flag_reset_changes(player: int) -> Array:
	"""Create state changes to reset per-turn action flags for a player's units"""
	var changes = []
	var units = game_state_snapshot.get("units", {})

	if units.is_empty():
		print("ScoringPhase: No units found in game state, skipping flag reset")
		return changes

	var reset_count = 0
	var flags_to_reset = [
		"moved", "advanced", "fell_back", "remained_stationary",
		"cannot_shoot", "cannot_charge", "cannot_move",
		"has_shot", "charged_this_turn", "fights_first",
		"move_cap_inches"
	]

	for unit_id in units:
		var unit = units[unit_id]

		# Only reset flags for units belonging to the player whose turn is starting
		if unit.get("owner", 0) != player:
			continue

		# Skip embarked units (they don't act while inside transports)
		if unit.get("embarked_in", null) != null:
			continue

		var flags = unit.get("flags", {})
		if flags.is_empty():
			continue

		var reset_flags_for_unit = []

		for flag in flags_to_reset:
			if flags.has(flag):
				changes.append({
					"op": "remove",
					"path": "units.%s.flags.%s" % [unit_id, flag]
				})
				reset_flags_for_unit.append(flag)

		if not reset_flags_for_unit.is_empty():
			reset_count += 1
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			print("ScoringPhase:   Reset flags for %s: %s" % [unit_name, reset_flags_for_unit])

	if reset_count > 0:
		print("ScoringPhase: Resetting flags for %d units owned by player %d" % [reset_count, player])
	else:
		print("ScoringPhase: No flags to reset for player %d units" % player)

	return changes

func _should_complete_phase() -> bool:
	# Scoring phase completes immediately after END_TURN action
	return true
