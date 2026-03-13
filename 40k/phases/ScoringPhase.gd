extends BasePhase
class_name ScoringPhase

const BasePhase = preload("res://phases/BasePhase.gd")


# ScoringPhase - Handles end-of-turn scoring including secondary missions
# and provides "End Turn" functionality to switch between players
#
# P3-103: Objective Control Timing (10e Core Rules)
# ================================================
# Per 10th edition: "A player controls an objective marker at the end of any phase or turn."
# Objective control is rechecked at these key points:
#   1. CommandPhase entry — snapshot for secondary missions + OC state
#   2. MovementPhase — after each unit move/reinforcement (real-time UI feedback)
#   3. ShootingPhase exit — after unit casualties change OC balance
#   4. ChargePhase — after each successful charge move
#   5. FightPhase exit — after unit casualties change OC balance
#   6. ScoringPhase entry — final recheck before secondary mission scoring
#
# Primary scoring happens at the end of the Command phase (CommandPhase._handle_end_command()),
# which matches the rules: "Score VP by controlling objectives at the end of your Command phase."

# Store secondary mission scoring results for UI display
var _secondary_results: Array = []
# Track whether the phase should complete (only after END_TURN, not after discard)
var _turn_ended: bool = false

# Acrobatic Escape vanish state tracking
var _awaiting_acrobatic_escape_vanish: bool = false
var _acrobatic_escape_vanish_pending: Array = []  # [{unit_id, unit_name, player}]
var _acrobatic_escape_vanish_offered: bool = false  # Prevents re-checking after all resolved

signal acrobatic_escape_vanish_available(unit_id: String, unit_name: String, player: int)

func _on_phase_enter() -> void:
	_turn_ended = false
	_awaiting_acrobatic_escape_vanish = false
	_acrobatic_escape_vanish_pending.clear()
	_acrobatic_escape_vanish_offered = false
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

	# Acrobatic Escape vanish actions when awaiting
	if _awaiting_acrobatic_escape_vanish and not _acrobatic_escape_vanish_pending.is_empty():
		var ae_unit = _acrobatic_escape_vanish_pending[0]
		actions.append({
			"type": "ACROBATIC_ESCAPE_VANISH",
			"unit_id": ae_unit.unit_id,
			"description": "Acrobatic Escape: Remove %s from battlefield" % ae_unit.unit_name,
			"player": ae_unit.player,
		})
		actions.append({
			"type": "DECLINE_ACROBATIC_ESCAPE_VANISH",
			"unit_id": ae_unit.unit_id,
			"description": "Keep %s on the battlefield" % ae_unit.unit_name,
			"player": ae_unit.player,
		})
		return actions

	# Offer voluntary discard of active secondary missions (tactical mode only — fixed missions cannot be discarded)
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if secondary_mgr and secondary_mgr.is_initialized(current_player) and not secondary_mgr.is_fixed_mode(current_player):
		var active_missions = secondary_mgr.get_active_missions(current_player)
		var can_gain_cp = GameState.can_gain_bonus_cp(current_player)
		for i in range(active_missions.size()):
			var mission = active_missions[i]
			var cp_text = "gain 1 CP" if can_gain_cp else "no CP — bonus cap reached"
			actions.append({
				"type": "DISCARD_SECONDARY",
				"mission_index": i,
				"description": "Discard %s (%s)" % [mission["name"], cp_text],
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
		"ACROBATIC_ESCAPE_VANISH":
			if not _awaiting_acrobatic_escape_vanish:
				errors.append("No Acrobatic Escape vanish is pending")
		"DECLINE_ACROBATIC_ESCAPE_VANISH":
			if not _awaiting_acrobatic_escape_vanish:
				errors.append("No Acrobatic Escape vanish is pending")
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
		"ACROBATIC_ESCAPE_VANISH":
			return _handle_acrobatic_escape_vanish(action)
		"DECLINE_ACROBATIC_ESCAPE_VANISH":
			return _handle_decline_acrobatic_escape_vanish(action)
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
	var current_player = get_current_player()
	var next_player = 2 if current_player == 1 else 1

	# Check for Acrobatic Escape vanish eligibility before ending the turn
	# "At the end of your opponent's turn" — the opponent is the NON-active player
	var ae_eligible = _get_acrobatic_escape_vanish_eligible(current_player)
	if not ae_eligible.is_empty() and not _awaiting_acrobatic_escape_vanish and not _acrobatic_escape_vanish_offered:
		_awaiting_acrobatic_escape_vanish = true
		_acrobatic_escape_vanish_offered = true
		_acrobatic_escape_vanish_pending = ae_eligible.duplicate()

		var first = ae_eligible[0]
		print("ScoringPhase: ACROBATIC ESCAPE VANISH: %s (player %d) eligible — offering choice" % [first.unit_name, first.player])
		emit_signal("acrobatic_escape_vanish_available", first.unit_id, first.unit_name, first.player)

		return {
			"success": true,
			"changes": [],
			"message": "Acrobatic Escape: %s can vanish from the battlefield" % first.unit_name,
			"trigger_acrobatic_escape_vanish": true,
			"acrobatic_escape_vanish_unit_id": first.unit_id,
			"acrobatic_escape_vanish_player": first.player,
		}

	_turn_ended = true

	print("ScoringPhase: Player %d ending turn, switching to player %d" % [current_player, next_player])

	# P3-128: Record VP snapshot at end of each player's turn for the timeline chart
	if MissionManager:
		var battle_round = GameState.get_battle_round()
		MissionManager.record_vp_snapshot(battle_round)

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
		"is_engaged", "fight_priority",
		"burned_objective",
		"performed_ritual",
		"performed_terraform"
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

# ============================================================================
# ACROBATIC ESCAPE VANISH (End of opponent's turn)
# ============================================================================

func _get_acrobatic_escape_vanish_eligible(current_player: int) -> Array:
	"""Find units with Acrobatic Escape that belong to the opponent and are NOT within 3\" of enemies.
	The current_player is the active player whose turn is ending — the opponent's Callidus can vanish."""
	var eligible = []
	var all_units = game_state_snapshot.get("units", {})
	var opponent = 2 if current_player == 1 else 1

	for unit_id in all_units:
		var unit = all_units[unit_id]
		if int(unit.get("owner", 0)) != opponent:
			continue

		# Check if unit has Acrobatic Escape ability
		var abilities = unit.get("meta", {}).get("abilities", [])
		var has_ability = false
		for ability in abilities:
			if ability is Dictionary and ability.get("name", "") == "Acrobatic Escape":
				has_ability = true
				break
			elif ability is String and ability == "Acrobatic Escape":
				has_ability = true
				break

		if not has_ability:
			continue

		# Check if unit is alive and deployed
		var models = unit.get("models", [])
		var has_alive = false
		for model in models:
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
			continue

		# Must NOT be within 3" of any enemy model
		if _is_unit_within_distance_of_enemies(unit, unit_id, 3.0):
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			print("ScoringPhase: ACROBATIC ESCAPE: %s is within 3\" of enemies — cannot vanish" % unit_name)
			continue

		var unit_name = unit.get("meta", {}).get("name", unit_id)
		eligible.append({
			"unit_id": unit_id,
			"unit_name": unit_name,
			"player": opponent,
		})
		print("ScoringPhase: ACROBATIC ESCAPE: %s (player %d) eligible to vanish" % [unit_name, opponent])

	return eligible

func _is_unit_within_distance_of_enemies(unit: Dictionary, unit_id: String, distance_inches: float) -> bool:
	"""Check if any enemy model is within the specified distance (edge-to-edge) of any model in the unit."""
	var all_units = game_state_snapshot.get("units", {})
	var unit_owner = int(unit.get("owner", 0))

	for other_unit_id in all_units:
		if other_unit_id == unit_id:
			continue
		var other_unit = all_units[other_unit_id]
		if int(other_unit.get("owner", 0)) == unit_owner:
			continue

		# Skip destroyed units
		var other_alive = false
		for m in other_unit.get("models", []):
			if m.get("alive", true):
				other_alive = true
				break
		if not other_alive:
			continue

		var models1 = unit.get("models", [])
		var models2 = other_unit.get("models", [])

		for model1 in models1:
			if not model1.get("alive", true):
				continue
			for model2 in models2:
				if not model2.get("alive", true):
					continue
				var dist = Measurement.model_to_model_distance_inches(model1, model2)
				if dist <= distance_inches:
					return true

	return false

func _handle_acrobatic_escape_vanish(action: Dictionary) -> Dictionary:
	"""Remove the Callidus from the battlefield and put into reserves."""
	var unit_id = action.get("unit_id", "")
	var unit = game_state_snapshot.get("units", {}).get(unit_id, {})
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var player = int(unit.get("owner", 0))

	print("ScoringPhase: ACROBATIC ESCAPE: %s vanishing from battlefield — moving to reserves" % unit_name)

	var changes = []

	# Set unit status to IN_RESERVES
	changes.append({
		"op": "set",
		"path": "units.%s.status" % unit_id,
		"value": GameStateData.UnitStatus.IN_RESERVES
	})

	# Set flag so we know this is an Acrobatic Escape reserves (for destruction at battle end)
	changes.append({
		"op": "set",
		"path": "units.%s.flags.acrobatic_escape_reserves" % unit_id,
		"value": true
	})

	# Log the event
	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log:
		game_event_log.add_player_entry(player, "Acrobatic Escape: %s vanished from the battlefield" % unit_name)

	# Show toast
	var toast_mgr = get_node_or_null("/root/ToastManager")
	if toast_mgr:
		toast_mgr.show_info("Acrobatic Escape: %s vanished — will return next Movement phase" % unit_name)

	# Remove from pending list
	_acrobatic_escape_vanish_pending = _acrobatic_escape_vanish_pending.filter(
		func(u): return u.unit_id != unit_id
	)

	# Check for more pending units
	if not _acrobatic_escape_vanish_pending.is_empty():
		var next = _acrobatic_escape_vanish_pending[0]
		print("ScoringPhase: ACROBATIC ESCAPE: Next eligible — %s (player %d)" % [next.unit_name, next.player])
		emit_signal("acrobatic_escape_vanish_available", next.unit_id, next.unit_name, next.player)

		return {
			"success": true,
			"changes": changes,
			"message": "Acrobatic Escape: %s vanished" % unit_name,
			"trigger_acrobatic_escape_vanish": true,
			"acrobatic_escape_vanish_unit_id": next.unit_id,
			"acrobatic_escape_vanish_player": next.player,
		}

	# All resolved — now do the actual end turn
	_awaiting_acrobatic_escape_vanish = false

	# Process the actual end turn now
	var end_turn_result = _handle_end_turn()
	# Merge our changes with the end-turn changes
	var all_changes = changes.duplicate()
	all_changes.append_array(end_turn_result.get("changes", []))
	end_turn_result["changes"] = all_changes
	return end_turn_result

func _handle_decline_acrobatic_escape_vanish(action: Dictionary) -> Dictionary:
	"""Player chose not to vanish the Callidus."""
	var unit_id = action.get("unit_id", "")
	var unit_name = ""
	if not unit_id.is_empty():
		var unit = game_state_snapshot.get("units", {}).get(unit_id, {})
		unit_name = unit.get("meta", {}).get("name", unit_id)
	print("ScoringPhase: ACROBATIC ESCAPE: %s declined vanish — staying on battlefield" % unit_name)

	# Remove from pending list
	_acrobatic_escape_vanish_pending = _acrobatic_escape_vanish_pending.filter(
		func(u): return u.unit_id != unit_id
	)

	# Check for more pending units
	if not _acrobatic_escape_vanish_pending.is_empty():
		var next = _acrobatic_escape_vanish_pending[0]
		print("ScoringPhase: ACROBATIC ESCAPE: Next eligible — %s (player %d)" % [next.unit_name, next.player])
		emit_signal("acrobatic_escape_vanish_available", next.unit_id, next.unit_name, next.player)

		return {
			"success": true,
			"changes": [],
			"message": "%s stays on the battlefield" % unit_name,
			"trigger_acrobatic_escape_vanish": true,
			"acrobatic_escape_vanish_unit_id": next.unit_id,
			"acrobatic_escape_vanish_player": next.player,
		}

	# All resolved — now do the actual end turn
	_awaiting_acrobatic_escape_vanish = false

	# Process the actual end turn
	return _handle_end_turn()
