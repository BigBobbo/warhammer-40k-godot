extends Node

signal result_applied(result: Dictionary)
signal action_logged(log_text: String)

var action_history: Array = []

func apply_action(action: Dictionary) -> Dictionary:
	var result = process_action(action)
	if result["success"]:
		# Normalize: phases return "changes", we need "diffs" for network sync
		if result.has("changes") and not result.has("diffs"):
			result["diffs"] = result["changes"]

		# Add action type and data to result so consumers can identify what happened
		# This is needed for client-side visual updates in multiplayer
		result["action_type"] = action.get("type", "")
		result["action_data"] = action

		apply_result(result)
		action_history.append(action)
	return result

func process_action(action: Dictionary) -> Dictionary:
	match action["type"]:
		# Deployment actions
		"DEPLOY_UNIT":
			return process_deploy_unit(action)
		"END_DEPLOYMENT":
			return process_end_deployment(action)

		# Movement actions
		"BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "BEGIN_FALL_BACK":
			return process_begin_move(action)
		"SET_MODEL_DEST":
			return process_set_model_dest(action)
		"STAGE_MODEL_MOVE":
			return process_stage_model_move(action)
		"CONFIRM_UNIT_MOVE":
			return process_confirm_move(action)
		"UNDO_LAST_MODEL_MOVE":
			return process_undo_last_move(action)
		"RESET_UNIT_MOVE":
			return process_reset_move(action)
		"REMAIN_STATIONARY":
			return process_remain_stationary(action)
		"LOCK_MOVEMENT_MODE":
			return process_lock_movement_mode(action)
		"SET_ADVANCE_BONUS":
			return process_set_advance_bonus(action)
		"END_MOVEMENT":
			return process_end_movement(action)
		"DISEMBARK_UNIT":
			return process_disembark(action)
		"CONFIRM_DISEMBARK":
			return process_confirm_disembark(action)

		# Shooting actions
		"SELECT_TARGET", "DESELECT_TARGET":
			return process_select_target(action)
		"RESOLVE_ATTACKS":
			return process_resolve_attacks(action)
		"ALLOCATE_WOUNDS":
			return process_allocate_wounds(action)
		"END_SHOOTING":
			return process_end_shooting(action)

		# Charge actions
		"DECLARE_CHARGE":
			return process_declare_charge(action)
		"ROLL_CHARGE":
			return process_roll_charge(action)
		"END_CHARGE":
			return process_end_charge(action)

		# Fight actions
		"SELECT_FIGHT_TARGET":
			return process_fight_target(action)
		"RESOLVE_FIGHT":
			return process_resolve_fight(action)
		"END_FIGHT":
			return process_end_fight(action)

		# Command actions
		"USE_STRATAGEM":
			return process_use_stratagem(action)
		"END_COMMAND":
			return process_end_command(action)

		# Scoring actions
		"SCORE_OBJECTIVE":
			return process_score_objective(action)
		"END_SCORING":
			return process_end_scoring(action)

		# Morale actions
		"END_MORALE":
			return process_end_morale(action)

		_:
			return {"success": false, "error": "Unknown action type: " + str(action.get("type", "UNKNOWN"))}

func process_deploy_unit(action: Dictionary) -> Dictionary:
	var unit_id = action["unit_id"]
	var model_positions = action.get("model_positions", [])
	var model_rotations = action.get("model_rotations", [])
	var diffs = []

	# Create diffs for each model's position and rotation
	for i in range(model_positions.size()):
		var pos = model_positions[i]
		if pos != null:
			diffs.append({
				"op": "set",
				"path": "units.%s.models.%d.position" % [unit_id, i],
				"value": {"x": pos.x, "y": pos.y}
			})

			# Add rotation if available
			if i < model_rotations.size():
				diffs.append({
					"op": "set",
					"path": "units.%s.models.%d.rotation" % [unit_id, i],
					"value": model_rotations[i]
				})

	# Set unit status to DEPLOYED
	diffs.append({
		"op": "set",
		"path": "units.%s.status" % unit_id,
		"value": GameStateData.UnitStatus.DEPLOYED
	})

	# Handle deployment player alternation for multiplayer sync
	var current_player = GameState.get_active_player()
	var player1_has_units = _has_undeployed_units(1)
	var player2_has_units = _has_undeployed_units(2)

	# Determine if we need to switch players
	var should_switch = false
	var new_player = current_player

	# Simple alternation - if both players have units, just alternate every time
	if player1_has_units and player2_has_units:
		new_player = 2 if current_player == 1 else 1
		should_switch = true
	# If only one player has units left, switch to that player if needed
	elif player1_has_units and current_player != 1:
		new_player = 1
		should_switch = true
	elif player2_has_units and current_player != 2:
		new_player = 2
		should_switch = true

	# Add active_player change to diffs if needed
	if should_switch:
		diffs.append({
			"op": "set",
			"path": "meta.active_player",
			"value": new_player
		})
		print("GameManager: Switching active player from ", current_player, " to ", new_player)

	# Get unit info for logging
	var unit_data = GameState.get_unit(unit_id)
	var unit_name = unit_data.get("meta", {}).get("name", "Unknown Unit")
	var log_text = "Deployed %s (%d models) wholly within DZ." % [unit_name, model_positions.size()]

	return {
		"success": true,
		"phase": "DEPLOYMENT",
		"diffs": diffs,
		"log_text": log_text
	}

func process_end_deployment(action: Dictionary) -> Dictionary:
	print("GameManager: Processing END_DEPLOYMENT action")
	var next_phase = _get_next_phase(GameStateData.Phase.DEPLOYMENT)
	_trigger_phase_completion()
	return {"success": true, "diffs": [{"op": "set", "path": "meta.phase", "value": next_phase}]}

func apply_result(result: Dictionary) -> void:
	if not result["success"]:
		return

	# Handle both "diffs" and "changes" (phases use "changes", network uses "diffs")
	var changes = result.get("diffs", result.get("changes", []))
	print("GameManager: Applying result with %d changes/diffs" % changes.size())

	for diff in changes:
		apply_diff(diff)

	if result.has("log_text"):
		emit_signal("action_logged", result["log_text"])

	emit_signal("result_applied", result)

	# Trigger a state change signal so UI updates
	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.has_signal("state_changed"):
		print("GameManager: Emitting state_changed signal")
		game_state.emit_signal("state_changed")

func apply_diff(diff: Dictionary) -> void:
	var op = diff["op"]
	var path = diff["path"]
	var value = diff.get("value", null)
	
	match op:
		"set":
			set_value_at_path(path, value)

func set_value_at_path(path: String, value) -> void:
	var parts = path.split(".")
	if parts.is_empty():
		return

	# Get GameState reference
	var game_state = get_node_or_null("/root/GameState")
	if not game_state:
		push_error("GameManager: Cannot find GameState")
		return

	# Start from GameState.state dictionary
	var current = game_state.state
	for i in range(parts.size() - 1):
		var part = parts[i]
		if current is Dictionary:
			if current.has(part):
				current = current[part]
			else:
				push_error("GameManager: Path not found in state: %s (part: %s)" % [path, part])
				return
		elif current is Array:
			var index = part.to_int()
			if index >= 0 and index < current.size():
				current = current[index]
			else:
				push_error("GameManager: Array index out of bounds: %s[%d]" % [path, index])
				return
		else:
			push_error("GameManager: Cannot traverse path at %s (not dict/array)" % part)
			return

	var final_key = parts[-1]
	if current is Dictionary:
		print("GameManager: Setting %s = %s" % [path, value])
		current[final_key] = value
	elif current is Array:
		var index = final_key.to_int()
		if index >= 0 and index < current.size():
			print("GameManager: Setting %s[%d] = %s" % [path, index, value])
			current[index] = value
		else:
			push_error("GameManager: Array index out of bounds for final key: %s[%d]" % [path, index])
	else:
		push_error("GameManager: Cannot set value at %s (not dict/array)" % path)

# ============================================================================
# MOVEMENT ACTION PROCESSORS
# ============================================================================

func process_begin_move(action: Dictionary) -> Dictionary:
	# Movement actions must be executed by the phase to update active_moves
	return _delegate_to_current_phase(action)

func process_set_model_dest(action: Dictionary) -> Dictionary:
	return _delegate_to_current_phase(action)

func process_stage_model_move(action: Dictionary) -> Dictionary:
	return _delegate_to_current_phase(action)

func process_confirm_move(action: Dictionary) -> Dictionary:
	return _delegate_to_current_phase(action)

func process_undo_last_move(action: Dictionary) -> Dictionary:
	return _delegate_to_current_phase(action)

func process_reset_move(action: Dictionary) -> Dictionary:
	return _delegate_to_current_phase(action)

func process_remain_stationary(action: Dictionary) -> Dictionary:
	return _delegate_to_current_phase(action)

func process_lock_movement_mode(action: Dictionary) -> Dictionary:
	return _delegate_to_current_phase(action)

func process_set_advance_bonus(action: Dictionary) -> Dictionary:
	return _delegate_to_current_phase(action)

func process_end_movement(action: Dictionary) -> Dictionary:
	print("GameManager: Processing END_MOVEMENT action")
	var next_phase = _get_next_phase(GameStateData.Phase.MOVEMENT)
	_trigger_phase_completion()
	return {"success": true, "diffs": [{"op": "set", "path": "meta.phase", "value": next_phase}]}

func process_disembark(action: Dictionary) -> Dictionary:
	return _delegate_to_current_phase(action)

func process_confirm_disembark(action: Dictionary) -> Dictionary:
	return _delegate_to_current_phase(action)

# ============================================================================
# SHOOTING ACTION PROCESSORS
# ============================================================================

func process_select_target(action: Dictionary) -> Dictionary:
	return _delegate_to_current_phase(action)

func process_resolve_attacks(action: Dictionary) -> Dictionary:
	return _delegate_to_current_phase(action)

func process_allocate_wounds(action: Dictionary) -> Dictionary:
	return _delegate_to_current_phase(action)

func process_end_shooting(action: Dictionary) -> Dictionary:
	print("GameManager: Processing END_SHOOTING action")
	var next_phase = _get_next_phase(GameStateData.Phase.SHOOTING)
	_trigger_phase_completion()
	return {"success": true, "diffs": [{"op": "set", "path": "meta.phase", "value": next_phase}]}

# ============================================================================
# CHARGE ACTION PROCESSORS
# ============================================================================

func process_declare_charge(action: Dictionary) -> Dictionary:
	return _delegate_to_current_phase(action)

func process_roll_charge(action: Dictionary) -> Dictionary:
	return _delegate_to_current_phase(action)

func process_end_charge(action: Dictionary) -> Dictionary:
	print("GameManager: Processing END_CHARGE action")
	var next_phase = _get_next_phase(GameStateData.Phase.CHARGE)
	_trigger_phase_completion()
	return {"success": true, "diffs": [{"op": "set", "path": "meta.phase", "value": next_phase}]}

# ============================================================================
# FIGHT ACTION PROCESSORS
# ============================================================================

func process_fight_target(action: Dictionary) -> Dictionary:
	return _delegate_to_current_phase(action)

func process_resolve_fight(action: Dictionary) -> Dictionary:
	return _delegate_to_current_phase(action)

func process_end_fight(action: Dictionary) -> Dictionary:
	print("GameManager: Processing END_FIGHT action")
	var next_phase = _get_next_phase(GameStateData.Phase.FIGHT)
	_trigger_phase_completion()
	return {"success": true, "diffs": [{"op": "set", "path": "meta.phase", "value": next_phase}]}

# ============================================================================
# COMMAND ACTION PROCESSORS
# ============================================================================

func process_use_stratagem(action: Dictionary) -> Dictionary:
	return {"success": true, "diffs": []}

func process_end_command(action: Dictionary) -> Dictionary:
	print("GameManager: Processing END_COMMAND action")

	# Calculate next phase
	var next_phase = _get_next_phase(GameStateData.Phase.COMMAND)
	print("GameManager: Advancing from COMMAND to phase ", next_phase)

	# Create diff for phase change
	var diffs = [{
		"op": "set",
		"path": "meta.phase",
		"value": next_phase
	}]

	# Trigger phase completion (this will update PhaseManager on host)
	_trigger_phase_completion()

	return {"success": true, "diffs": diffs}

# ============================================================================
# SCORING ACTION PROCESSORS
# ============================================================================

func process_score_objective(action: Dictionary) -> Dictionary:
	return {"success": true, "diffs": []}

func process_end_scoring(action: Dictionary) -> Dictionary:
	print("GameManager: Processing END_SCORING action")

	var current_player = GameState.get_active_player()
	var next_player = 2 if current_player == 1 else 1
	var next_phase = _get_next_phase(GameStateData.Phase.SCORING)

	print("GameManager: Player %d ending turn, switching to player %d" % [current_player, next_player])

	var diffs = [
		{
			"op": "set",
			"path": "meta.phase",
			"value": next_phase
		},
		{
			"op": "set",
			"path": "meta.active_player",
			"value": next_player
		}
	]

	# If Player 2 just finished their turn, advance battle round
	if current_player == 2:
		var new_battle_round = GameState.get_battle_round() + 1
		print("GameManager: Completing battle round, advancing to battle round %d" % new_battle_round)

		diffs.append({
			"op": "set",
			"path": "meta.battle_round",
			"value": new_battle_round
		})

	_trigger_phase_completion()
	return {"success": true, "diffs": diffs}

# ============================================================================
# MORALE ACTION PROCESSORS
# ============================================================================

func process_end_morale(action: Dictionary) -> Dictionary:
	print("GameManager: Processing END_MORALE action")
	var next_phase = _get_next_phase(GameStateData.Phase.MORALE)
	_trigger_phase_completion()
	return {"success": true, "diffs": [{"op": "set", "path": "meta.phase", "value": next_phase}]}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

func _delegate_to_current_phase(action: Dictionary) -> Dictionary:
	"""
	Delegates an action to the current phase for execution.
	This is used for actions that modify phase-local state (like active_moves in MovementPhase).
	"""
	var phase_mgr = get_node_or_null("/root/PhaseManager")
	if not phase_mgr:
		push_error("GameManager: PhaseManager not available for action delegation")
		return {"success": false, "error": "PhaseManager not available"}

	var current_phase = phase_mgr.get_current_phase_instance()
	if not current_phase:
		push_error("GameManager: No current phase instance for action delegation")
		return {"success": false, "error": "No active phase"}

	if not current_phase.has_method("execute_action"):
		push_error("GameManager: Current phase does not have execute_action method")
		return {"success": false, "error": "Phase cannot execute actions"}

	# Execute the action on the phase
	return current_phase.execute_action(action)

func _trigger_phase_completion() -> void:
	"""
	Triggers the current phase to complete by emitting the phase_completed signal.
	This is used by "end phase" actions (END_COMMAND, END_MOVEMENT, etc.) to
	advance to the next phase in multiplayer mode.
	"""
	var phase_mgr = get_node_or_null("/root/PhaseManager")
	if phase_mgr:
		var current_phase_instance = phase_mgr.get_current_phase_instance()
		if current_phase_instance and current_phase_instance.has_signal("phase_completed"):
			print("GameManager: Emitting phase_completed signal on current phase")
			current_phase_instance.emit_signal("phase_completed")
		else:
			push_warning("GameManager: Could not emit phase_completed - no phase instance")
	else:
		push_warning("GameManager: PhaseManager not available to trigger phase completion")

func _get_next_phase(current: int) -> int:
	"""
	Returns the next phase in the standard 40k phase sequence.
	This mirrors PhaseManager._get_next_phase() logic.
	"""
	match current:
		GameStateData.Phase.DEPLOYMENT:
			return GameStateData.Phase.COMMAND
		GameStateData.Phase.COMMAND:
			return GameStateData.Phase.MOVEMENT
		GameStateData.Phase.MOVEMENT:
			return GameStateData.Phase.SHOOTING
		GameStateData.Phase.SHOOTING:
			return GameStateData.Phase.CHARGE
		GameStateData.Phase.CHARGE:
			return GameStateData.Phase.FIGHT
		GameStateData.Phase.FIGHT:
			return GameStateData.Phase.SCORING
		GameStateData.Phase.SCORING:
			# After scoring, always go to command phase for next player
			return GameStateData.Phase.COMMAND
		GameStateData.Phase.MORALE:
			# Legacy support - morale phase leads to deployment (next turn)
			return GameStateData.Phase.DEPLOYMENT
		_:
			return GameStateData.Phase.DEPLOYMENT

func _has_undeployed_units(player: int) -> bool:
	"""Check if a player has any undeployed units remaining"""
	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) == player and unit.get("status", 0) == GameStateData.UnitStatus.UNDEPLOYED:
			return true
	return false
