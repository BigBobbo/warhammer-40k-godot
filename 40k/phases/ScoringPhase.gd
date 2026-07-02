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

# Generic end-of-turn redeploy to reserves (From Golden Light, Guerrilla Tactics, etc.)
# Each entry: { ability_name, distance_check (inches), once_per_battle }
const END_TURN_REDEPLOY_ABILITIES = [
	{"ability_name": "From Golden Light", "distance_check": 1.0, "once_per_battle": true},
	{"ability_name": "Guerrilla Tactics", "distance_check": 1.0, "once_per_battle": true},
	{"ability_name": "Webway Shunt Generator", "distance_check": 1.0, "once_per_battle": true},
	{"ability_name": "Teleportation Matrix", "distance_check": 1.0, "once_per_battle": true},
]

var _awaiting_end_turn_redeploy: bool = false
var _end_turn_redeploy_pending: Array = []  # [{unit_id, unit_name, player, ability_name}]
var _end_turn_redeploy_offered: bool = false

signal end_turn_redeploy_available(unit_id: String, unit_name: String, player: int, ability_name: String)

# ISS-042 follow-up / audit #16 (11e 03.03 "Regaining Coherency"): at the End
# of Turn step the PLAYER chooses which models to remove from units that are
# out of coherency. Human-owned incoherent units pause END_TURN behind this
# offer; AI owners (and anything left unresolved) fall through to the
# PhaseManager auto-pick hook, which remains the enforcement backstop.
var _awaiting_coherency_removal: bool = false
var _coherency_removal_pending: Array = []  # [{unit_id, unit_name, player, offenders: [model ids]}]

signal coherency_removal_required(pending: Array, player: int)

func _on_phase_enter() -> void:
	_turn_ended = false
	_awaiting_acrobatic_escape_vanish = false
	_acrobatic_escape_vanish_pending.clear()
	_acrobatic_escape_vanish_offered = false
	_awaiting_end_turn_redeploy = false
	_end_turn_redeploy_pending.clear()
	_end_turn_redeploy_offered = false
	_awaiting_coherency_removal = false
	_coherency_removal_pending.clear()
	phase_type = GameStateData.Phase.SCORING
	var current_player = get_current_player()
	DebugLogger.info(str("ScoringPhase: Entering scoring phase for player ", current_player))
	DebugLogger.info(str("ScoringPhase: Current battle round ", GameState.get_battle_round()))

	# Update objective control before scoring (ensures secondary missions
	# that depend on objective control have accurate data)
	if MissionManager:
		MissionManager.check_all_objectives()
		DebugLogger.info("ScoringPhase: Updated objective control for scoring")

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
			DebugLogger.info(str("ScoringPhase: Player %d scored secondary missions:" % current_player))
			for result in _secondary_results:
				DebugLogger.info(str("  - %s: %d VP" % [result["mission_name"], result["vp_earned"]]))
			if game_event_log:
				for result in _secondary_results:
					game_event_log.add_player_entry(current_player, "Scored %d VP from %s" % [result["vp_earned"], result["mission_name"]])

		# Also score end-of-opponent-turn missions for the opponent
		var opponent = 2 if current_player == 1 else 1
		if secondary_mgr.is_initialized(opponent):
			var opponent_results = secondary_mgr.score_secondary_missions_for_player(opponent)
			if opponent_results.size() > 0:
				DebugLogger.info(str("ScoringPhase: Player %d scored secondary missions (end of opponent turn):" % opponent))
				for result in opponent_results:
					DebugLogger.info(str("  - %s: %d VP" % [result["mission_name"], result["vp_earned"]]))
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
	DebugLogger.info("ScoringPhase: Exiting scoring phase")
	_secondary_results.clear()

func get_available_actions() -> Array:
	var actions = []
	var current_player = get_current_player()

	# 03.03 coherency removals when awaiting: one action per offender model.
	# Mandatory — nothing else (incl. END_TURN) is offered until resolved.
	if _awaiting_coherency_removal and not _coherency_removal_pending.is_empty():
		for entry in _coherency_removal_pending:
			for model_id in entry.offenders:
				actions.append({
					"type": "REMOVE_MODEL_FOR_COHERENCY",
					"unit_id": entry.unit_id,
					"model_id": model_id,
					"description": "Remove %s (%s) — unit out of coherency (03.03)" % [model_id, entry.unit_name],
					"player": entry.player,
				})
		return actions

	# Acrobatic Escape vanish actions when awaiting
	# Only list these if the pending unit is AI-controlled — human players
	# interact via the dialog (which dispatches the action directly).
	# Returning empty blocks the AI from ending the turn while the dialog is open.
	if _awaiting_acrobatic_escape_vanish and not _acrobatic_escape_vanish_pending.is_empty():
		var ae_unit = _acrobatic_escape_vanish_pending[0]
		var ai_player_node = get_node_or_null("/root/AIPlayer")
		if ai_player_node and ai_player_node.is_ai_player(ae_unit.player):
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

	# End-of-turn redeploy to reserves actions (From Golden Light, etc.)
	if _awaiting_end_turn_redeploy and not _end_turn_redeploy_pending.is_empty():
		var rd_unit = _end_turn_redeploy_pending[0]
		var ai_player_node = get_node_or_null("/root/AIPlayer")
		if ai_player_node and ai_player_node.is_ai_player(rd_unit.player):
			actions.append({
				"type": "END_TURN_REDEPLOY",
				"unit_id": rd_unit.unit_id,
				"description": "%s: Remove %s to Strategic Reserves" % [rd_unit.ability_name, rd_unit.unit_name],
				"player": rd_unit.player,
			})
			actions.append({
				"type": "DECLINE_END_TURN_REDEPLOY",
				"unit_id": rd_unit.unit_id,
				"description": "Keep %s on the battlefield" % rd_unit.unit_name,
				"player": rd_unit.player,
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
			if _awaiting_coherency_removal:
				errors.append("Out-of-coherency removals must be resolved first (03.03)")
		"REMOVE_MODEL_FOR_COHERENCY":
			if not _awaiting_coherency_removal:
				errors.append("No coherency removal is pending")
			else:
				var rm_unit_id = str(action.get("unit_id", ""))
				var rm_model_id = str(action.get("model_id", ""))
				var found := false
				for entry in _coherency_removal_pending:
					if entry.unit_id == rm_unit_id and rm_model_id in entry.offenders.map(func(o): return str(o)):
						found = true
						break
				if not found:
					errors.append("Model %s of %s is not an out-of-coherency offender" % [rm_model_id, rm_unit_id])
		"END_FIGHT":
			# Idempotent no-op: previous phase auto-advanced before END_FIGHT was dispatched.
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
		"END_TURN_REDEPLOY":
			if not _awaiting_end_turn_redeploy:
				errors.append("No end-of-turn redeploy is pending")
		"DECLINE_END_TURN_REDEPLOY":
			if not _awaiting_end_turn_redeploy:
				errors.append("No end-of-turn redeploy is pending")
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
		"REMOVE_MODEL_FOR_COHERENCY":
			return _handle_remove_model_for_coherency(action)
		"END_FIGHT":
			return {"success": true, "changes": []}
		"DISCARD_SECONDARY":
			return _handle_discard_secondary(action)
		"ACROBATIC_ESCAPE_VANISH":
			return _handle_acrobatic_escape_vanish(action)
		"DECLINE_ACROBATIC_ESCAPE_VANISH":
			return _handle_decline_acrobatic_escape_vanish(action)
		"END_TURN_REDEPLOY":
			return _handle_end_turn_redeploy(action)
		"DECLINE_END_TURN_REDEPLOY":
			return _handle_decline_end_turn_redeploy(action)
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
		DebugLogger.info(str("ScoringPhase: Player %d discarded %s (gained %d CP)" % [
			current_player, result["discarded"], result["cp_gained"]]))
		var game_event_log = get_node_or_null("/root/GameEventLog")
		if game_event_log:
			game_event_log.add_player_entry(current_player, "Discarded %s (gained %d CP)" % [result["discarded"], result["cp_gained"]])
	return result

func _handle_end_turn() -> Dictionary:
	var current_player = get_current_player()
	var next_player = 2 if current_player == 1 else 1

	# 11e 03.03 (audit #16): units out of coherency must remove models at the
	# End of Turn step — pause so a HUMAN owner chooses which. Re-checked on
	# every END_TURN (no offered-flag): removals below re-validate, and the
	# gate clears only when every human-owned unit is coherent.
	if GameConstants.edition >= 11 and not _awaiting_coherency_removal:
		var incoherent = _get_incoherent_human_units()
		if not incoherent.is_empty():
			_awaiting_coherency_removal = true
			_coherency_removal_pending = incoherent
			var names: Array = incoherent.map(func(e): return e.unit_name)
			DebugLogger.info(str("ScoringPhase: 03.03 coherency removal required for %s — offering model choice" % str(names)))
			emit_signal("coherency_removal_required", incoherent, current_player)
			return {
				"success": true,
				"changes": [],
				"message": "Out of coherency: choose models to remove (03.03): %s" % ", ".join(names),
				"trigger_coherency_removal": true,
				"coherency_removal_pending": incoherent,
			}

	# Check for Acrobatic Escape vanish eligibility before ending the turn
	# "At the end of your opponent's turn" — the opponent is the NON-active player
	var ae_eligible = _get_acrobatic_escape_vanish_eligible(current_player)
	if not ae_eligible.is_empty() and not _awaiting_acrobatic_escape_vanish and not _acrobatic_escape_vanish_offered:
		_awaiting_acrobatic_escape_vanish = true
		_acrobatic_escape_vanish_offered = true
		_acrobatic_escape_vanish_pending = ae_eligible.duplicate()

		var first = ae_eligible[0]
		DebugLogger.info(str("ScoringPhase: ACROBATIC ESCAPE VANISH: %s (player %d) eligible — offering choice" % [first.unit_name, first.player]))
		emit_signal("acrobatic_escape_vanish_available", first.unit_id, first.unit_name, first.player)

		return {
			"success": true,
			"changes": [],
			"message": "Acrobatic Escape: %s can vanish from the battlefield" % first.unit_name,
			"trigger_acrobatic_escape_vanish": true,
			"acrobatic_escape_vanish_unit_id": first.unit_id,
			"acrobatic_escape_vanish_player": first.player,
		}

	# Check for end-of-turn redeploy abilities (From Golden Light, etc.)
	var rd_eligible = _get_end_turn_redeploy_eligible(current_player)
	if not rd_eligible.is_empty() and not _awaiting_end_turn_redeploy and not _end_turn_redeploy_offered:
		_awaiting_end_turn_redeploy = true
		_end_turn_redeploy_offered = true
		_end_turn_redeploy_pending = rd_eligible.duplicate()

		var first = rd_eligible[0]
		DebugLogger.info(str("ScoringPhase: END-TURN REDEPLOY: %s (player %d) eligible via %s — offering choice" % [first.unit_name, first.player, first.ability_name]))
		emit_signal("end_turn_redeploy_available", first.unit_id, first.unit_name, first.player, first.ability_name)

		return {
			"success": true,
			"changes": [],
			"message": "%s: %s can redeploy to Strategic Reserves" % [first.ability_name, first.unit_name],
			"trigger_end_turn_redeploy": true,
			"end_turn_redeploy_unit_id": first.unit_id,
			"end_turn_redeploy_player": first.player,
			"end_turn_redeploy_ability": first.ability_name,
		}

	_turn_ended = true

	DebugLogger.info(str("ScoringPhase: Player %d ending turn, switching to player %d" % [current_player, next_player]))

	# ISS-038: End of Turn step (07.02) — run registered hooks in 07.03
	# order (non-mission rules, then mission rules) before the player-switch
	# diffs are built.
	PhaseManager.run_turn_ending_hooks(current_player)

	# P3-128: Record VP snapshot at end of each player's turn for the timeline chart
	if MissionManager:
		var battle_round = GameState.get_battle_round()
		MissionManager.record_vp_snapshot(battle_round)

	# Detect end-of-game: P2 finishing the final battle round (10e: 5 rounds).
	# Set meta.game_ended/winner in state so saves, replays, MCP queries, and
	# PhaseManager._handle_game_end() (via is_game_complete()) all observe it.
	if current_player == 2 and GameState.get_battle_round() >= GameState.MAX_BATTLE_ROUNDS:
		return _handle_game_end_turn()

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
		# ISS-038: End of Battle Round step (07.03).
		PhaseManager.emit_signal("battle_round_ending", current_battle_round)
		var new_battle_round = current_battle_round + 1
		DebugLogger.info(str("ScoringPhase: Completing battle round, advancing to battle round %d" % new_battle_round))

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

## 03.03 (audit #16): units with >1 positioned model, a HUMAN owner, and a
## failed coherency check. AI-owned units are left to the PhaseManager
## auto-pick hook.
func _get_incoherent_human_units() -> Array:
	var out: Array = []
	var gc = GameState.state.get("meta", {}).get("game_config", {})
	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		var alive := 0
		for m in unit.get("models", []):
			if m.get("alive", true) and m.get("position") != null:
				alive += 1
		if alive <= 1:
			continue
		var owner := int(unit.get("owner", 0))
		var ptype := str(gc.get("player%d_type" % owner, "HUMAN")).to_upper()
		if ptype != "HUMAN":
			continue
		var coh = AttackSequence.check_unit_coherency(unit)
		if not coh.coherent:
			out.append({
				"unit_id": str(unit_id),
				"unit_name": unit.get("meta", {}).get("name", str(unit_id)),
				"player": owner,
				"offenders": coh.offenders.duplicate(),
			})
	return out

## Player-chosen 03.03 removal: destroy the chosen offender (no on-death
## triggers), then re-check — the gate clears when every human-owned unit
## is coherent again, and END_TURN can be re-dispatched.
func _handle_remove_model_for_coherency(action: Dictionary) -> Dictionary:
	var unit_id = str(action.get("unit_id", ""))
	var model_id = str(action.get("model_id", ""))
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	var changes: Array = []
	for mi in range(unit.get("models", []).size()):
		if str(unit.models[mi].get("id", mi)) == model_id:
			changes.append({"op": "set", "path": StateSchema.path_model_field(unit_id, mi, "alive"), "value": false})
			changes.append({"op": "set", "path": StateSchema.path_model_field(unit_id, mi, "current_wounds"), "value": 0})
			break
	if changes.is_empty():
		return {"success": false, "errors": ["Model not found: %s in %s" % [model_id, unit_id]]}
	# Apply immediately so the re-check below sees the removal; the same
	# diffs also ride in the result for network sync (idempotent set ops,
	# so the pipeline re-apply is harmless).
	PhaseManager.apply_state_changes(changes)
	log_phase_message("03.03: removed %s from %s (player's choice, destroyed, no on-death triggers)" % [model_id, unit.get("meta", {}).get("name", unit_id)])

	_coherency_removal_pending = _get_incoherent_human_units()
	if _coherency_removal_pending.is_empty():
		_awaiting_coherency_removal = false
		DebugLogger.info("ScoringPhase: 03.03 coherency restored — END_TURN unblocked")
	return {
		"success": true,
		"changes": changes,
		"message": "Removed %s for coherency" % model_id,
		"coherency_removal_pending": _coherency_removal_pending,
		"awaiting_coherency_removal": _awaiting_coherency_removal,
	}

func _handle_game_end_turn() -> Dictionary:
	# Score Scorched Earth end-of-game burn bonuses BEFORE determining the winner
	# so the bonus VP counts toward the result.
	if MissionManager and MissionManager.has_method("score_end_of_game_burn_bonus"):
		MissionManager.score_end_of_game_burn_bonus()

	var winner := _determine_winner()

	DebugLogger.info(str("ScoringPhase: Final battle round complete — game ended. Winner: %s" % (
		"Draw" if winner == 0 else "Player %d" % winner)))

	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log:
		var msg = "Game ended after %d battle rounds — %s" % [
			GameState.MAX_BATTLE_ROUNDS,
			"Draw" if winner == 0 else "Player %d wins" % winner,
		]
		game_event_log.add_info_entry(msg)

	var changes := [
		{"op": "set", "path": "meta.game_ended", "value": true},
		{"op": "set", "path": "meta.winner", "value": winner},
	]

	return {
		"success": true,
		"changes": changes,
		"message": "Game ended after %d battle rounds" % GameState.MAX_BATTLE_ROUNDS,
		"game_ended": true,
		"winner": winner,
	}

func _determine_winner() -> int:
	if not MissionManager or not MissionManager.has_method("get_vp_summary"):
		return 0
	var vp = MissionManager.get_vp_summary()
	var p1 = int(vp.get("player1", {}).get("total", 0))
	var p2 = int(vp.get("player2", {}).get("total", 0))
	if p1 > p2:
		return 1
	if p2 > p1:
		return 2
	return 0

func _create_flag_reset_changes(player: int) -> Array:
	"""Create state changes to reset per-turn action flags for a player's units"""
	var changes = []
	var units = game_state_snapshot.get("units", {})

	if units.is_empty():
		DebugLogger.info("ScoringPhase: No units found in game state, skipping flag reset")
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
		"performed_terraform",
		# 06_SYNTHESIS launch-blocker #5 / issue #365: Da Jump (Weirdboy psychic)
		# flag was never cleared across turn boundaries, permanently locking the
		# Weirdboy after one Da Jump. `awaiting_da_jump_placement` is also reset
		# as a safety net so a save mid-Da-Jump cannot strand the unit in
		# placement-pending state across a turn boundary. Mirrors the same
		# entries on the multiplayer path in `GameManager.process_end_scoring`.
		"da_jump_used_this_turn", "awaiting_da_jump_placement",
		"heroic_intervention",
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
			DebugLogger.info(str("ScoringPhase:   Reset flags for %s: %s" % [unit_name, reset_flags_for_unit]))

	if reset_count > 0:
		DebugLogger.info(str("ScoringPhase: Resetting flags for %d units owned by player %d" % [reset_count, player]))
	else:
		DebugLogger.info(str("ScoringPhase: No flags to reset for player %d units" % player))

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

		DebugLogger.info(str("ScoringPhase: P1-37 — Destroying reserves unit '%s' (player %d) — not arrived by end of Round 3" % [unit_name, owner]))

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
			DebugLogger.info(str("ScoringPhase: %s" % msg))
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
		DebugLogger.info(str("ScoringPhase: P1-37 — Total %d reserves unit(s) destroyed at end of Round 3" % total_destroyed))
	else:
		DebugLogger.info("ScoringPhase: P1-37 — No reserves units remaining at end of Round 3")

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
			DebugLogger.info(str("ScoringPhase: ACROBATIC ESCAPE: %s is within 3\" of enemies — cannot vanish" % unit_name))
			continue

		var unit_name = unit.get("meta", {}).get("name", unit_id)
		eligible.append({
			"unit_id": unit_id,
			"unit_name": unit_name,
			"player": opponent,
		})
		DebugLogger.info(str("ScoringPhase: ACROBATIC ESCAPE: %s (player %d) eligible to vanish" % [unit_name, opponent]))

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

	DebugLogger.info(str("ScoringPhase: ACROBATIC ESCAPE: %s vanishing from battlefield — moving to reserves" % unit_name))

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
		toast_mgr.show_toast("Acrobatic Escape: %s vanished — will return next Movement phase" % unit_name)

	# Remove from pending list
	_acrobatic_escape_vanish_pending = _acrobatic_escape_vanish_pending.filter(
		func(u): return u.unit_id != unit_id
	)

	# Check for more pending units
	if not _acrobatic_escape_vanish_pending.is_empty():
		var next = _acrobatic_escape_vanish_pending[0]
		DebugLogger.info(str("ScoringPhase: ACROBATIC ESCAPE: Next eligible — %s (player %d)" % [next.unit_name, next.player]))
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
	DebugLogger.info(str("ScoringPhase: ACROBATIC ESCAPE: %s declined vanish — staying on battlefield" % unit_name))

	# Remove from pending list
	_acrobatic_escape_vanish_pending = _acrobatic_escape_vanish_pending.filter(
		func(u): return u.unit_id != unit_id
	)

	# Check for more pending units
	if not _acrobatic_escape_vanish_pending.is_empty():
		var next = _acrobatic_escape_vanish_pending[0]
		DebugLogger.info(str("ScoringPhase: ACROBATIC ESCAPE: Next eligible — %s (player %d)" % [next.unit_name, next.player]))
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

# ============================================================================
# END-OF-TURN REDEPLOY TO RESERVES (From Golden Light, Guerrilla Tactics, etc.)
# ============================================================================

func _get_end_turn_redeploy_eligible(current_player: int) -> Array:
	var eligible = []
	var all_units = game_state_snapshot.get("units", {})
	var opponent = 2 if current_player == 1 else 1
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")

	for unit_id in all_units:
		var unit = all_units[unit_id]
		if int(unit.get("owner", 0)) != opponent:
			continue

		if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
			continue

		var models = unit.get("models", [])
		var has_alive = false
		for model in models:
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		var abilities = unit.get("meta", {}).get("abilities", [])
		for ability_def in END_TURN_REDEPLOY_ABILITIES:
			var ability_name = ability_def["ability_name"]
			var has_ability = false
			for ability in abilities:
				if ability is Dictionary and ability.get("name", "") == ability_name:
					has_ability = true
					break
				elif ability is String and ability == ability_name:
					has_ability = true
					break

			if not has_ability:
				continue

			# Check once-per-battle usage
			if ability_def["once_per_battle"] and ability_mgr:
				if ability_mgr.is_once_per_battle_used(unit_id, ability_name):
					DebugLogger.info(str("ScoringPhase: END-TURN REDEPLOY: %s already used %s this battle" % [unit.get("meta", {}).get("name", unit_id), ability_name]))
					continue

			# Must NOT be within Engagement Range of enemies
			if _is_unit_within_distance_of_enemies(unit, unit_id, ability_def["distance_check"]):
				var unit_name = unit.get("meta", {}).get("name", unit_id)
				DebugLogger.info(str("ScoringPhase: END-TURN REDEPLOY: %s is within Engagement Range — cannot use %s" % [unit_name, ability_name]))
				continue

			var unit_name = unit.get("meta", {}).get("name", unit_id)
			eligible.append({
				"unit_id": unit_id,
				"unit_name": unit_name,
				"player": opponent,
				"ability_name": ability_name,
			})
			DebugLogger.info(str("ScoringPhase: END-TURN REDEPLOY: %s (player %d) eligible via %s" % [unit_name, opponent, ability_name]))
			break  # One ability per unit is enough

	return eligible

func _handle_end_turn_redeploy(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var unit = game_state_snapshot.get("units", {}).get(unit_id, {})
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var player = int(unit.get("owner", 0))

	# Find the ability name from pending list
	var ability_name = ""
	for pending in _end_turn_redeploy_pending:
		if pending.unit_id == unit_id:
			ability_name = pending.ability_name
			break

	DebugLogger.info(str("ScoringPhase: END-TURN REDEPLOY: %s using %s — moving to Strategic Reserves" % [unit_name, ability_name]))

	var changes = []

	changes.append({
		"op": "set",
		"path": "units.%s.status" % unit_id,
		"value": GameStateData.UnitStatus.IN_RESERVES
	})

	changes.append({
		"op": "set",
		"path": "units.%s.reserve_type" % unit_id,
		"value": "strategic_reserves"
	})

	changes.append({
		"op": "set",
		"path": "units.%s.flags.strategic_reserves_redeploy" % unit_id,
		"value": true
	})

	# Mark once-per-battle used
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		ability_mgr.mark_once_per_battle_used(unit_id, ability_name)

	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log:
		game_event_log.add_player_entry(player, "%s: %s removed to Strategic Reserves" % [ability_name, unit_name])

	var toast_mgr = get_node_or_null("/root/ToastManager")
	if toast_mgr:
		toast_mgr.show_toast("%s: %s moved to Strategic Reserves — will return next Movement phase" % [ability_name, unit_name])

	# Remove from pending list
	_end_turn_redeploy_pending = _end_turn_redeploy_pending.filter(
		func(u): return u.unit_id != unit_id
	)

	# Check for more pending units
	if not _end_turn_redeploy_pending.is_empty():
		var next = _end_turn_redeploy_pending[0]
		DebugLogger.info(str("ScoringPhase: END-TURN REDEPLOY: Next eligible — %s (player %d) via %s" % [next.unit_name, next.player, next.ability_name]))
		emit_signal("end_turn_redeploy_available", next.unit_id, next.unit_name, next.player, next.ability_name)

		return {
			"success": true,
			"changes": changes,
			"message": "%s: %s moved to Strategic Reserves" % [ability_name, unit_name],
			"trigger_end_turn_redeploy": true,
			"end_turn_redeploy_unit_id": next.unit_id,
			"end_turn_redeploy_player": next.player,
			"end_turn_redeploy_ability": next.ability_name,
		}

	_awaiting_end_turn_redeploy = false

	var end_turn_result = _handle_end_turn()
	var all_changes = changes.duplicate()
	all_changes.append_array(end_turn_result.get("changes", []))
	end_turn_result["changes"] = all_changes
	return end_turn_result

func _handle_decline_end_turn_redeploy(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var unit_name = ""
	if not unit_id.is_empty():
		var unit = game_state_snapshot.get("units", {}).get(unit_id, {})
		unit_name = unit.get("meta", {}).get("name", unit_id)
	DebugLogger.info(str("ScoringPhase: END-TURN REDEPLOY: %s declined — staying on battlefield" % unit_name))

	_end_turn_redeploy_pending = _end_turn_redeploy_pending.filter(
		func(u): return u.unit_id != unit_id
	)

	if not _end_turn_redeploy_pending.is_empty():
		var next = _end_turn_redeploy_pending[0]
		DebugLogger.info(str("ScoringPhase: END-TURN REDEPLOY: Next eligible — %s (player %d) via %s" % [next.unit_name, next.player, next.ability_name]))
		emit_signal("end_turn_redeploy_available", next.unit_id, next.unit_name, next.player, next.ability_name)

		return {
			"success": true,
			"changes": [],
			"message": "%s stays on the battlefield" % unit_name,
			"trigger_end_turn_redeploy": true,
			"end_turn_redeploy_unit_id": next.unit_id,
			"end_turn_redeploy_player": next.player,
			"end_turn_redeploy_ability": next.ability_name,
		}

	_awaiting_end_turn_redeploy = false
	return _handle_end_turn()
