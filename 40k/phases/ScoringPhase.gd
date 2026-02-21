extends BasePhase
class_name ScoringPhase

const BasePhase = preload("res://phases/BasePhase.gd")


# ScoringPhase - Handles end-of-turn scoring including secondary missions
# and provides "End Turn" functionality to switch between players

# Store secondary mission scoring results for UI display
var _secondary_results: Array = []

func _on_phase_enter() -> void:
	phase_type = GameStateData.Phase.SCORING
	var current_player = get_current_player()
	print("ScoringPhase: Entering scoring phase for player ", current_player)
	print("ScoringPhase: Current battle round ", GameState.get_battle_round())

	# Update objective control before scoring (ensures secondary missions
	# that depend on objective control have accurate data)
	if MissionManager:
		MissionManager.check_all_objectives()
		print("ScoringPhase: Updated objective control for scoring")

		# T7-57: Track objectives held per round for AI performance summary
		if AIPlayer and AIPlayer.enabled:
			var battle_round = GameState.get_battle_round()
			var obj_summary = MissionManager.get_objective_control_summary()
			for p in [1, 2]:
				if AIPlayer.is_ai_player(p):
					var held = obj_summary.get("player%d_controlled" % p, 0)
					AIPlayer.record_ai_objectives(p, battle_round, held)

	# Score secondary missions for the active player
	_secondary_results.clear()
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if secondary_mgr and secondary_mgr.is_initialized(current_player):
		# Score end-of-your-turn missions for active player
		_secondary_results = secondary_mgr.score_secondary_missions_for_player(current_player)
		if _secondary_results.size() > 0:
			print("ScoringPhase: Player %d scored secondary missions:" % current_player)
			for result in _secondary_results:
				print("  - %s: %d VP" % [result["mission_name"], result["vp_earned"]])

		# Also score end-of-opponent-turn missions for the opponent
		var opponent = 2 if current_player == 1 else 1
		if secondary_mgr.is_initialized(opponent):
			var opponent_results = secondary_mgr.score_secondary_missions_for_player(opponent)
			if opponent_results.size() > 0:
				print("ScoringPhase: Player %d scored secondary missions (end of opponent turn):" % opponent)
				for result in opponent_results:
					print("  - %s: %d VP" % [result["mission_name"], result["vp_earned"]])

func _on_phase_exit() -> void:
	print("ScoringPhase: Exiting scoring phase")
	_secondary_results.clear()

func get_available_actions() -> Array:
	var actions = []
	var current_player = get_current_player()

	# Offer voluntary discard of active secondary missions
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if secondary_mgr and secondary_mgr.is_initialized(current_player):
		var active_missions = secondary_mgr.get_active_missions(current_player)
		for i in range(active_missions.size()):
			var mission = active_missions[i]
			actions.append({
				"type": "DISCARD_SECONDARY",
				"mission_index": i,
				"description": "Discard %s (gain 1 CP)" % mission["name"],
				"player": current_player,
			})

	actions.append({
		"type": "END_SCORING",
		"description": "End Turn",
		"player": current_player,
	})

	return actions

func validate_action(action: Dictionary) -> Dictionary:
	var errors = []
	var action_type = action.get("type", "")

	match action_type:
		"END_SCORING", "END_TURN":  # Support both for backward compatibility
			pass
		"DISCARD_SECONDARY":
			var mission_index = action.get("mission_index", -1)
			if mission_index < 0:
				errors.append("Invalid mission index")
		_:
			errors.append("Unknown action type: %s" % action_type)

	return {
		"valid": errors.size() == 0,
		"errors": errors
	}

func process_action(action: Dictionary) -> Dictionary:
	match action.get("type", ""):
		"END_SCORING", "END_TURN":
			return _handle_end_turn()
		"DISCARD_SECONDARY":
			return _handle_discard_secondary(action)
		_:
			return {"success": false, "error": "Unknown action type"}

func _handle_discard_secondary(action: Dictionary) -> Dictionary:
	var current_player = get_current_player()
	var mission_index = action.get("mission_index", -1)

	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if not secondary_mgr:
		return {"success": false, "error": "SecondaryMissionManager not available"}

	var result = secondary_mgr.voluntary_discard(current_player, mission_index)
	if result["success"]:
		print("ScoringPhase: Player %d discarded %s (gained %d CP)" % [
			current_player, result["discarded"], result["cp_gained"]])
	return result

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
		"has_shot", "has_fought", "charged_this_turn", "fights_first",
		"has_been_charged", "move_cap_inches",
		"is_engaged", "fight_priority"
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
