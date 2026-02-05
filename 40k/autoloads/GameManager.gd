extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

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

		# Capture reverse diffs BEFORE applying changes (for undo support)
		var diffs = result.get("diffs", [])
		var reverse_diffs = _create_reverse_diffs(diffs)

		apply_result(result)
		action_history.append(action)

		# Store reverse diffs for undo (only if there were actual changes)
		if not reverse_diffs.is_empty():
			undo_history.append(reverse_diffs)
		else:
			# Store empty array to keep histories aligned
			undo_history.append([])

	return result

func process_action(action: Dictionary) -> Dictionary:
	match action["type"]:
		# Deployment actions
		"DEPLOY_UNIT":
			return process_deploy_unit(action)
		"EMBARK_UNITS_DEPLOYMENT":
			return _delegate_to_current_phase(action)
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

		# Shooting actions (new phase-based system)
		"SELECT_SHOOTER", "ASSIGN_TARGET", "CLEAR_ASSIGNMENT", "CLEAR_ALL_ASSIGNMENTS":
			return _delegate_to_current_phase(action)
		"CONFIRM_TARGETS", "RESOLVE_SHOOTING", "SKIP_UNIT":
			return _delegate_to_current_phase(action)
		"SHOOT", "APPLY_SAVES", "RESOLVE_WEAPON_SEQUENCE", "CONTINUE_SEQUENCE":
			return _delegate_to_current_phase(action)

		# Legacy shooting actions (kept for compatibility)
		"SELECT_TARGET", "DESELECT_TARGET":
			return process_select_target(action)
		"RESOLVE_ATTACKS":
			return process_resolve_attacks(action)
		"ALLOCATE_WOUNDS":
			return process_allocate_wounds(action)
		"END_SHOOTING":
			return process_end_shooting(action)

		# Charge actions
		"SELECT_CHARGE_UNIT":
			return _delegate_to_current_phase(action)
		"DECLARE_CHARGE":
			return process_declare_charge(action)
		"CHARGE_ROLL":
			return process_roll_charge(action)
		"APPLY_CHARGE_MOVE":
			return _delegate_to_current_phase(action)
		"COMPLETE_UNIT_CHARGE":
			return _delegate_to_current_phase(action)
		"SKIP_CHARGE":
			return _delegate_to_current_phase(action)
		"END_CHARGE":
			return process_end_charge(action)

		# Fight actions (modern phase-based system)
		"SELECT_FIGHTER":
			return _delegate_to_current_phase(action)
		"SELECT_MELEE_WEAPON":
			return _delegate_to_current_phase(action)
		"PILE_IN":
			return _delegate_to_current_phase(action)
		"ASSIGN_ATTACKS":
			return _delegate_to_current_phase(action)
		"CONFIRM_AND_RESOLVE_ATTACKS":
			return _delegate_to_current_phase(action)
		"ROLL_DICE":
			return _delegate_to_current_phase(action)
		"CONSOLIDATE":
			return _delegate_to_current_phase(action)
		"SKIP_UNIT":
			return _delegate_to_current_phase(action)
		"HEROIC_INTERVENTION":
			return _delegate_to_current_phase(action)
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

		# Debug actions
		"DEBUG_MOVE":
			return process_debug_move(action)

		_:
			return {"success": false, "error": "Unknown action type: " + str(action.get("type", "UNKNOWN"))}

func process_deploy_unit(action: Dictionary) -> Dictionary:
	var unit_id = action["unit_id"]
	var model_positions = action.get("model_positions", [])
	var model_rotations = action.get("model_rotations", [])
	var diffs = []

	# Validate deployment zone
	var unit = GameState.get_unit(unit_id)
	if not unit:
		return {
			"success": false,
			"message": "Unit not found: %s" % unit_id
		}

	# First try to get owner from top level, then from meta
	var owner_player = unit.get("owner", 0)
	if owner_player == 0:
		owner_player = unit.get("meta", {}).get("player", 0)
	if owner_player == 0:
		return {
			"success": false,
			"message": "Unit has no owner player"
		}

	# Validate it's the unit owner's turn to deploy
	var active_player = GameState.get_active_player()
	if active_player != 0 and owner_player != active_player:
		return {
			"success": false,
			"message": "Cannot deploy - it is Player %d's turn, not Player %d's" % [active_player, owner_player]
		}

	# Check all model positions are within deployment zone
	# Positions are in pixels, need to convert for validation
	# Standard deployment zones: Player 1 at bottom, Player 2 at top
	# Board is 44x60 inches (1760x2400 pixels at 40px/inch)
	const PIXELS_PER_INCH = 40.0
	const DEPLOYMENT_ZONE_DEPTH_PX = 480.0  # 12 inches * 40 px/inch
	const BOARD_HEIGHT_PX = 2400.0  # 60 inches * 40 px/inch

	for pos in model_positions:
		if pos != null:
			var valid_deployment = false
			if owner_player == 1:
				# Player 1 deploys at bottom of board (low y values)
				valid_deployment = pos.y >= 0 and pos.y <= DEPLOYMENT_ZONE_DEPTH_PX
			elif owner_player == 2:
				# Player 2 deploys at top of board (high y values)
				valid_deployment = pos.y >= (BOARD_HEIGHT_PX - DEPLOYMENT_ZONE_DEPTH_PX) and pos.y <= BOARD_HEIGHT_PX

			if not valid_deployment:
				return {
					"success": false,
					"message": "Unit cannot be deployed outside deployment zone (position y=%d px is invalid for player %d)" % [pos.y, owner_player]
				}

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
		"remove":
			remove_value_at_path(path)

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

func remove_value_at_path(path: String) -> void:
	var parts = path.split(".")
	if parts.is_empty():
		return

	# Get GameState reference
	var game_state = get_node_or_null("/root/GameState")
	if not game_state:
		push_error("GameManager: Cannot find GameState")
		return

	# Navigate to parent of the value to remove
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

	# Remove the final key
	var final_key = parts[-1]
	if current is Dictionary:
		if current.has(final_key):
			print("GameManager: Removing %s" % path)
			current.erase(final_key)
		else:
			# Not an error - flag might already be absent
			pass
	else:
		push_error("GameManager: Cannot remove value at %s (parent is not a dictionary)" % path)

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

# Legacy fight processors - DEPRECATED
# These were replaced by modern action routing in process_action()
# Kept as comments for reference during transition period
#
# func process_fight_target(action: Dictionary) -> Dictionary:
#     return _delegate_to_current_phase(action)
#
# func process_resolve_fight(action: Dictionary) -> Dictionary:
#     return _delegate_to_current_phase(action)

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

	# Reset unit flags for the player whose turn is starting
	var diffs = _create_flag_reset_diffs(next_player)

	# Add phase transition
	diffs.append({
		"op": "set",
		"path": "meta.phase",
		"value": next_phase
	})

	# Add player switch
	diffs.append({
		"op": "set",
		"path": "meta.active_player",
		"value": next_player
	})

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
# DEBUG ACTION PROCESSORS
# ============================================================================

func process_debug_move(action: Dictionary) -> Dictionary:
	"""Handle debug mode model movement - bypasses normal phase restrictions"""
	var unit_id = action.get("unit_id", "")
	var model_id = action.get("model_id", "")
	var position = action.get("position", [])

	if unit_id == "" or model_id == "" or position.size() != 2:
		return {"success": false, "error": "Invalid DEBUG_MOVE action data"}

	# Validate unit exists
	if not GameState.state.units.has(unit_id):
		return {"success": false, "error": "Unit not found: " + unit_id}

	var unit = GameState.state.units[unit_id]
	var models = unit.get("models", [])

	# Find model index
	var model_index = -1
	for i in range(models.size()):
		if models[i].get("id") == model_id:
			model_index = i
			break

	if model_index == -1:
		return {"success": false, "error": "Model not found: " + model_id}

	# Create diff for position update
	var diff = {
		"op": "set",
		"path": "units.%s.models.%d.position" % [unit_id, model_index],
		"value": {"x": position[0], "y": position[1]}
	}

	var unit_name = unit.get("meta", {}).get("name", "Unknown")
	var log_text = "[DEBUG] Moved %s model %s to (%d, %d)" % [unit_name, model_id, position[0], position[1]]

	return {
		"success": true,
		"phase": "DEBUG",
		"diffs": [diff],
		"log_text": log_text
	}

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

func deploy_unit(unit_id: String, position: Vector2) -> bool:
	"""
	Simplified deployment method for test mode.
	Wraps the full action processing system.
	"""
	print("GameManager: deploy_unit() called - unit_id: %s, position: %s" % [unit_id, position])

	# Debug: Print all available units
	var all_units = GameState.state.get("units", {})
	print("GameManager: Total units in GameState: %d" % all_units.size())
	print("GameManager: Unit IDs: %s" % str(all_units.keys()))

	# Get the unit to find model positions
	var unit = GameState.get_unit(unit_id)
	if not unit:
		push_error("GameManager: Unit not found: %s" % unit_id)
		push_error("GameManager: Available units: %s" % str(all_units.keys()))
		return false

	var models = unit.get("models", [])
	if models.is_empty():
		push_error("GameManager: Unit %s has no models" % unit_id)
		return false

	# For simplified test mode, place all models at the specified position
	# In real game, models would be spread out in formation
	var model_positions = []
	var model_rotations = []

	for i in range(models.size()):
		# Place all models at same position for now (test mode simplification)
		# In production, would use proper formation spacing
		model_positions.append(position)
		model_rotations.append(0.0)

	# Create the proper action dictionary
	var action = {
		"type": "DEPLOY_UNIT",
		"unit_id": unit_id,
		"model_positions": model_positions,
		"model_rotations": model_rotations
	}

	# Process the action through the standard action system
	var result = apply_action(action)

	print("GameManager: deploy_unit() result: success=%s" % result.get("success", false))
	return result.get("success", false)

var undo_history: Array = []  # Stores reverse diffs for each action

func undo_last_action() -> bool:
	"""
	Undo the last action performed by reversing its diffs.
	"""
	print("GameManager: undo_last_action() called")

	if action_history.is_empty() or undo_history.is_empty():
		push_warning("GameManager: No actions to undo")
		return false

	# Remove last action and its undo data
	var last_action = action_history.pop_back()
	var reverse_diffs = undo_history.pop_back()

	print("GameManager: Undoing action: %s with %d reverse diffs" % [last_action.get("type", "UNKNOWN"), reverse_diffs.size()])

	# Apply the reverse diffs to restore previous state
	for diff in reverse_diffs:
		apply_diff(diff)

	# Emit state changed so UI updates
	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.has_signal("state_changed"):
		game_state.emit_signal("state_changed")

	return true

func _create_reverse_diffs(diffs: Array) -> Array:
	"""
	Create reverse diffs that can undo the given diffs.
	For 'set' operations, we need to capture the current value before it changes.
	For 'remove' operations, we capture what was removed.
	"""
	var reverse = []
	var game_state = get_node_or_null("/root/GameState")
	if not game_state:
		return reverse

	for diff in diffs:
		var op = diff.get("op", "")
		var path = diff.get("path", "")

		match op:
			"set":
				# Capture current value before it's overwritten
				var current_value = _get_value_at_path(path)
				if current_value != null:
					# Reverse is to set back to the old value
					reverse.append({
						"op": "set",
						"path": path,
						"value": current_value
					})
				else:
					# Value didn't exist before, reverse is to remove it
					reverse.append({
						"op": "remove",
						"path": path
					})
			"remove":
				# Capture value being removed so we can restore it
				var current_value = _get_value_at_path(path)
				if current_value != null:
					reverse.append({
						"op": "set",
						"path": path,
						"value": current_value
					})

	# Reverse the order so undos happen in reverse sequence
	reverse.reverse()
	return reverse

func _get_value_at_path(path: String):
	"""
	Get the current value at a path in GameState.
	Returns null if path doesn't exist.
	"""
	var parts = path.split(".")
	if parts.is_empty():
		return null

	var game_state = get_node_or_null("/root/GameState")
	if not game_state:
		return null

	var current = game_state.state
	for part in parts:
		if current is Dictionary:
			if current.has(part):
				current = current[part]
			else:
				return null
		elif current is Array:
			var index = part.to_int()
			if index >= 0 and index < current.size():
				current = current[index]
			else:
				return null
		else:
			return null

	# Deep copy to avoid reference issues
	if current is Dictionary or current is Array:
		return current.duplicate(true)
	return current

func complete_deployment(player_id: int) -> bool:
	"""
	Mark deployment as complete for the specified player.
	Triggers phase transition when both players complete.
	"""
	print("GameManager: complete_deployment() called for player %d" % player_id)

	# Create END_DEPLOYMENT action
	var action = {
		"type": "END_DEPLOYMENT",
		"player_id": player_id
	}

	# Process through standard action system
	var result = apply_action(action)

	print("GameManager: complete_deployment() result: success=%s" % result.get("success", false))
	return result.get("success", false)

func _has_undeployed_units(player: int) -> bool:
	"""Check if a player has any undeployed units remaining"""
	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) == player and unit.get("status", 0) == GameStateData.UnitStatus.UNDEPLOYED:
			return true
	return false

func _create_flag_reset_diffs(player: int) -> Array:
	"""Create diffs to reset per-turn action flags for a player's units"""
	var diffs = []
	var units = GameState.state.get("units", {})

	if units.is_empty():
		print("GameManager: No units found in game state, skipping flag reset")
		return diffs

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
				diffs.append({
					"op": "remove",
					"path": "units.%s.flags.%s" % [unit_id, flag]
				})
				reset_flags_for_unit.append(flag)

		if not reset_flags_for_unit.is_empty():
			reset_count += 1
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			print("GameManager:   Reset flags for %s: %s" % [unit_name, reset_flags_for_unit])

	if reset_count > 0:
		print("GameManager: Resetting flags for %d units owned by player %d" % [reset_count, player])
	else:
		print("GameManager: No flags to reset for player %d units" % player)

	return diffs
