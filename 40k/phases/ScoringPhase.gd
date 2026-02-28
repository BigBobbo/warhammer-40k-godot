extends BasePhase
class_name ScoringPhase

const BasePhase = preload("res://phases/BasePhase.gd")


# ScoringPhase - Handles end-of-turn scoring including secondary missions
# and provides "End Turn" functionality to switch between players

# Store secondary mission scoring results for UI display
var _secondary_results: Array = []
# Track whether the phase should complete (only after END_TURN, not after discard)
var _turn_ended: bool = false

func _on_phase_enter() -> void:
	_turn_ended = false
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
	var game_event_log = get_node_or_null("/root/GameEventLog")
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if secondary_mgr and secondary_mgr.is_initialized(current_player):
		# Score end-of-your-turn missions for active player
		_secondary_results = secondary_mgr.score_secondary_missions_for_player(current_player)
		if _secondary_results.size() > 0:
			print("ScoringPhase: Player %d scored secondary missions:" % current_player)
			for result in _secondary_results:
				print("  - %s: %d VP" % [result["mission_name"], result["vp_earned"]])
			if game_event_log:
				for result in _secondary_results:
					game_event_log.add_player_entry(current_player, "Scored %d VP from %s" % [result["vp_earned"], result["mission_name"]])

		# Also score end-of-opponent-turn missions for the opponent
		var opponent = 2 if current_player == 1 else 1
		if secondary_mgr.is_initialized(opponent):
			var opponent_results = secondary_mgr.score_secondary_missions_for_player(opponent)
			if opponent_results.size() > 0:
				print("ScoringPhase: Player %d scored secondary missions (end of opponent turn):" % opponent)
				for result in opponent_results:
					print("  - %s: %d VP" % [result["mission_name"], result["vp_earned"]])
				if game_event_log:
					for result in opponent_results:
						game_event_log.add_player_entry(opponent, "Scored %d VP from %s" % [result["vp_earned"], result["mission_name"]])

	# Log VP totals summary
	if game_event_log and MissionManager:
		var vp = MissionManager.get_vp_summary()
		var p1 = vp["player1"]
		var p2 = vp["player2"]
		game_event_log.add_info_entry("VP Totals — P1: %d (Pri %d + Sec %d) | P2: %d (Pri %d + Sec %d)" % [
			p1["total"], p1["primary"], p1["secondary"],
			p2["total"], p2["primary"], p2["secondary"]])

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
		var game_event_log = get_node_or_null("/root/GameEventLog")
		if game_event_log:
			game_event_log.add_player_entry(current_player, "Discarded %s (gained %d CP)" % [result["discarded"], result["cp_gained"]])
	return result

func _handle_end_turn() -> Dictionary:
	_turn_ended = true
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
		var current_battle_round = GameState.get_battle_round()
		var new_battle_round = current_battle_round + 1
		print("ScoringPhase: Completing battle round, advancing to battle round %d" % new_battle_round)

		changes.append({
			"op": "set",
			"path": "meta.battle_round",
			"value": new_battle_round
		})

		# P1-37: Destroy reserves units not arrived by end of Round 3
		if current_battle_round == 3:
			var reserves_changes = _destroy_remaining_reserves()
			changes.append_array(reserves_changes)

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

func _destroy_remaining_reserves() -> Array:
	"""P1-37: At end of Round 3, destroy any units still IN_RESERVES.
	Per 10th Edition rules, reserves units not on the battlefield by end of
	Round 3 count as destroyed."""
	var changes = []
	var units = game_state_snapshot.get("units", {})
	var destroyed_units_by_player: Dictionary = {1: [], 2: []}
	var game_event_log = get_node_or_null("/root/GameEventLog")

	# First pass: find units directly in reserves
	var reserves_unit_ids: Array = []
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("status", -1) == GameStateData.UnitStatus.IN_RESERVES:
			reserves_unit_ids.append(unit_id)

	# Second pass: also find units embarked in a reserves transport
	for unit_id in units:
		var unit = units[unit_id]
		var embarked_in = unit.get("embarked_in", null)
		if embarked_in != null and embarked_in in reserves_unit_ids:
			if unit_id not in reserves_unit_ids:
				reserves_unit_ids.append(unit_id)

	# Now destroy all identified units
	for unit_id in reserves_unit_ids:
		var unit = units[unit_id]
		var owner = unit.get("owner", 0)
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var models = unit.get("models", [])

		print("ScoringPhase: P1-37 — Destroying reserves unit '%s' (player %d) — not arrived by end of Round 3" % [unit_name, owner])

		# Mark all models as dead
		for i in range(models.size()):
			if models[i].get("alive", true):
				changes.append({
					"op": "set",
					"path": "units.%s.models.%d.alive" % [unit_id, i],
					"value": false
				})

		destroyed_units_by_player[owner].append(unit_name)

		# Report unit destruction for secondary mission scoring
		var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
		if secondary_mgr:
			secondary_mgr.check_and_report_unit_destroyed(unit_id)

		# Report unit destruction for primary mission scoring
		# The "destroying player" is the opponent since they benefit from VP
		if MissionManager:
			var destroyed_by = 2 if owner == 1 else 1
			MissionManager.record_unit_destroyed(destroyed_by)

	# Notify both players via game event log and toast
	for player in [1, 2]:
		var destroyed_names = destroyed_units_by_player[player]
		if destroyed_names.size() > 0:
			var names_str = ", ".join(destroyed_names)
			var msg = "Player %d reserves destroyed (not arrived by Round 3): %s" % [player, names_str]
			print("ScoringPhase: %s" % msg)
			if game_event_log:
				game_event_log.add_player_entry(player, "Reserves destroyed (not arrived by Round 3): %s" % names_str)

	# Show toast notification if any units were destroyed
	var total_destroyed = destroyed_units_by_player[1].size() + destroyed_units_by_player[2].size()
	if total_destroyed > 0:
		var toast_mgr = get_node_or_null("/root/ToastManager")
		if toast_mgr:
			var all_names = []
			for player in [1, 2]:
				for unit_name in destroyed_units_by_player[player]:
					all_names.append("P%d %s" % [player, unit_name])
			toast_mgr.show_warning("Reserves destroyed (Round 3 ended): %s" % ", ".join(all_names))
		print("ScoringPhase: P1-37 — Total %d reserves unit(s) destroyed at end of Round 3" % total_destroyed)
	else:
		print("ScoringPhase: P1-37 — No reserves units remaining at end of Round 3")

	return changes

func _should_complete_phase() -> bool:
	# Only complete after END_TURN, not after a discard action
	return _turn_ended
