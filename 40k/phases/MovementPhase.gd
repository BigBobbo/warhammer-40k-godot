extends BasePhase
class_name MovementPhase

const BasePhase = preload("res://phases/BasePhase.gd")


# MovementPhase - Full implementation of the Movement phase following 10e rules
# Supports: Normal Move, Advance, Fall Back, Remain Stationary

signal unit_move_begun(unit_id: String, mode: String)
signal model_drop_preview(unit_id: String, model_id: String, path_px: Array, inches_used: float, legal: bool)
signal model_drop_committed(unit_id: String, model_id: String, dest_px: Vector2)
signal unit_move_confirmed(unit_id: String, result_summary: Dictionary)
signal unit_move_reset(unit_id: String)
signal movement_mode_locked(unit_id: String, mode: String)

const ENGAGEMENT_RANGE_INCHES: float = 1.0  # 10e standard ER

# Movement state tracking
var active_moves: Dictionary = {}  # unit_id -> move_data
var dice_log: Array = []

# Helper function to get unit movement stat with proper error handling
func get_unit_movement(unit: Dictionary) -> float:
	# Try the expected path first
	if unit.has("meta") and unit.meta.has("stats") and unit.meta.stats.has("move"):
		var movement = float(unit.meta.stats.move)
		return movement
	
	# Try nested get with type safety
	var stats = unit.get("meta", {}).get("stats", {})
	if stats and stats.has("move"):
		var movement = float(stats.get("move"))
		return movement
	
	# Log warning and return default
	var unit_name = unit.get("meta", {}).get("name", "Unknown")
	push_warning("Unit %s missing movement stat, using default: 6" % unit_name)
	return 6.0

func _init():
	phase_type = GameStateData.Phase.MOVEMENT

func _on_phase_enter() -> void:
	log_phase_message("Entering Movement Phase")
	active_moves.clear()
	dice_log.clear()

	# Connect to TransportManager to handle disembark completion
	if TransportManager and not TransportManager.disembark_completed.is_connected(_on_transport_manager_disembark_completed):
		TransportManager.disembark_completed.connect(_on_transport_manager_disembark_completed)

	# Movement phase continues with the current active player
	# Player switching only happens during scoring phase transitions

	_initialize_movement()

func _on_phase_exit() -> void:
	log_phase_message("Exiting Movement Phase")
	# Disconnect from TransportManager
	if TransportManager and TransportManager.disembark_completed.is_connected(_on_transport_manager_disembark_completed):
		TransportManager.disembark_completed.disconnect(_on_transport_manager_disembark_completed)
	# Clear any temporary movement data
	for unit_id in active_moves:
		_clear_unit_move_state(unit_id)

func _initialize_movement() -> void:
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	var can_move = false
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("status", 0) == GameStateData.UnitStatus.DEPLOYED:
			can_move = true
			break
	
	if not can_move:
		log_phase_message("No units available for movement, completing phase")
		emit_signal("phase_completed")

func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	# Check base phase validation first (handles DEBUG_MOVE)
	var base_validation = super.validate_action(action)
	if not base_validation.get("valid", true):
		return base_validation

	match action_type:
		"BEGIN_NORMAL_MOVE":
			return _validate_begin_normal_move(action)
		"BEGIN_ADVANCE":
			return _validate_begin_advance(action)
		"BEGIN_FALL_BACK":
			return _validate_begin_fall_back(action)
		"SET_MODEL_DEST":
			return _validate_set_model_dest(action)
		"STAGE_MODEL_MOVE":
			return _validate_stage_model_move(action)
		"UNDO_LAST_MODEL_MOVE":
			return _validate_undo_last_model_move(action)
		"RESET_UNIT_MOVE":
			return _validate_reset_unit_move(action)
		"CONFIRM_UNIT_MOVE":
			return _validate_confirm_unit_move(action)
		"REMAIN_STATIONARY":
			return _validate_remain_stationary(action)
		"LOCK_MOVEMENT_MODE":
			return _validate_lock_movement_mode(action)
		"SET_ADVANCE_BONUS":
			return _validate_set_advance_bonus(action)
		"END_MOVEMENT":
			return _validate_end_movement(action)
		"DISEMBARK_UNIT":
			return _validate_disembark_unit(action)
		"CONFIRM_DISEMBARK":
			return _validate_confirm_disembark(action)
		"DEBUG_MOVE":
			# Already validated by base class
			return {"valid": true}
		_:
			return {"valid": false, "errors": ["Unknown action type: " + action_type]}

func process_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")
	
	match action_type:
		"BEGIN_NORMAL_MOVE":
			return _process_begin_normal_move(action)
		"BEGIN_ADVANCE":
			return _process_begin_advance(action)
		"BEGIN_FALL_BACK":
			return _process_begin_fall_back(action)
		"SET_MODEL_DEST":
			return _process_set_model_dest(action)
		"STAGE_MODEL_MOVE":
			return _process_stage_model_move(action)
		"UNDO_LAST_MODEL_MOVE":
			return _process_undo_last_model_move(action)
		"RESET_UNIT_MOVE":
			return _process_reset_unit_move(action)
		"CONFIRM_UNIT_MOVE":
			return _process_confirm_unit_move(action)
		"REMAIN_STATIONARY":
			return _process_remain_stationary(action)
		"LOCK_MOVEMENT_MODE":
			return _process_lock_movement_mode(action)
		"SET_ADVANCE_BONUS":
			return _process_set_advance_bonus(action)
		"END_MOVEMENT":
			return _process_end_movement(action)
		"DISEMBARK_UNIT":
			return _process_disembark_unit(action)
		"CONFIRM_DISEMBARK":
			return _process_confirm_disembark(action)
		_:
			return create_result(false, [], "Unknown action type: " + action_type)

# Validation Methods

func _validate_begin_normal_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found: " + unit_id]}

	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}

	# Check if unit is embarked - if so, trigger disembark flow instead
	if unit.get("embarked_in", null) != null:
		# This will be handled by showing disembark dialog
		return {"valid": false, "errors": ["Unit is embarked - must disembark first"], "show_disembark": true}

	if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
		return {"valid": false, "errors": ["Unit is not deployed"]}

	# Check if unit has already moved
	if unit.get("flags", {}).get("moved", false):
		return {"valid": false, "errors": ["Unit has already moved this phase"]}

	# Check if unit cannot move due to disembarking restrictions
	if unit.get("flags", {}).get("cannot_move", false):
		return {"valid": false, "errors": ["Unit cannot move (disembarked from transport that moved)"]}

	# Check if unit is in engagement range (cannot use Normal Move if engaged)
	if _is_unit_engaged(unit_id):
		return {"valid": false, "errors": ["Unit is engaged, must Fall Back instead"]}

	return {"valid": true, "errors": []}

func _validate_begin_advance(action: Dictionary) -> Dictionary:
	# Same validation as normal move, plus advance-specific checks
	var base_validation = _validate_begin_normal_move(action)
	if not base_validation.valid:
		return base_validation
	
	# No additional restrictions for advance at this stage
	return {"valid": true, "errors": []}

func _validate_begin_fall_back(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found: " + unit_id]}
	
	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}
	
	if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
		return {"valid": false, "errors": ["Unit is not deployed"]}
	
	# Check if unit has already moved
	if unit.get("flags", {}).get("moved", false):
		return {"valid": false, "errors": ["Unit has already moved this phase"]}
	
	# Fall Back is only allowed if engaged
	if not _is_unit_engaged(unit_id):
		return {"valid": false, "errors": ["Unit is not engaged, use Normal Move instead"]}
	
	return {"valid": true, "errors": []}

func _validate_set_model_dest(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var payload = action.get("payload", {})
	var model_id = payload.get("model_id", "")
	var dest = payload.get("dest", [])
	
	if unit_id == "" or model_id == "" or dest.size() != 2:
		return {"valid": false, "errors": ["Missing required fields"]}
	
	# Check if unit has an active move
	if not active_moves.has(unit_id):
		return {"valid": false, "errors": ["No active move for unit"]}
	
	var move_data = active_moves[unit_id]
	var dest_vec = Vector2(dest[0], dest[1])
	
	# Validate movement distance
	var model = _get_model_in_unit(unit_id, model_id)
	if model.is_empty():
		return {"valid": false, "errors": ["Model not found in unit"]}
	
	var current_pos = _get_model_position(model)
	if current_pos == null:
		return {"valid": false, "errors": ["Model has no current position"]}
	
	var distance_inches = Measurement.distance_inches(current_pos, dest_vec)
	if distance_inches > move_data.move_cap_inches:
		return {"valid": false, "errors": ["Move exceeds cap: %.1f\" > %.1f\"" % [distance_inches, move_data.move_cap_inches]]}
	
	# Check engagement range restrictions
	var er_check = _check_engagement_range_at_position(unit_id, model_id, dest_vec, move_data.mode)
	if not er_check.valid:
		return {"valid": false, "errors": er_check.errors}
	
	# Check terrain collision
	if _position_intersects_terrain(dest_vec, model):
		return {"valid": false, "errors": ["Position intersects impassable terrain"]}

	# Check model overlap
	if _position_overlaps_other_models(unit_id, model_id, dest_vec, model):
		return {"valid": false, "errors": ["Cannot end move on top of another model"]}

	return {"valid": true, "errors": []}

func _validate_stage_model_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var payload = action.get("payload", {})
	var model_id = payload.get("model_id", "")
	var dest = payload.get("dest", [])

	if unit_id == "" or model_id == "" or dest.size() != 2:
		return {"valid": false, "errors": ["Missing required fields"]}

	# Check if unit has an active move
	if not active_moves.has(unit_id):
		log_phase_message("ERROR: No active move for unit %s. Active moves: %s" % [unit_id, active_moves.keys()])
		return {"valid": false, "errors": ["No active move for unit"]}
	
	var move_data = active_moves[unit_id]
	var dest_vec = Vector2(dest[0], dest[1])
	
	# Get model's current position (may be staged position)
	var model = _get_model_in_unit(unit_id, model_id)
	if model.is_empty():
		return {"valid": false, "errors": ["Model not found in unit"]}
	
	# Check staged position if model has one
	var current_pos = null
	for staged_move in move_data.staged_moves:
		if staged_move.model_id == model_id:
			current_pos = staged_move.dest
			break
	
	# If no staged position, use actual position
	if current_pos == null:
		current_pos = _get_model_position(model)
		if current_pos == null:
			return {"valid": false, "errors": ["Model has no current position"]}
	
	# Get the model's original position
	var original_pos = move_data.original_positions.get(model_id, current_pos)
	log_phase_message("DEBUG: Validating move for model %s" % model_id)
	log_phase_message("  Original pos: %s, Current pos: %s, Dest: %s" % [original_pos, current_pos, dest_vec])

	# Calculate total distance from original position to destination
	var total_distance_for_model = Measurement.distance_inches(original_pos, dest_vec)
	log_phase_message("  Distance calculation: %.2f inches" % total_distance_for_model)

	# Check if this specific model's distance exceeds cap
	if total_distance_for_model > move_data.move_cap_inches:
		log_phase_message("  FAILED: Distance %.1f\" exceeds cap %.1f\"" % [total_distance_for_model, move_data.move_cap_inches])
		return {"valid": false, "errors": ["Model %s would exceed movement cap: %.1f\" > %.1f\"" % [model_id, total_distance_for_model, move_data.move_cap_inches]]}
	
	# Check engagement range restrictions for the destination
	var er_check = _check_engagement_range_at_position(unit_id, model_id, dest_vec, move_data.mode)
	if not er_check.valid:
		return {"valid": false, "errors": er_check.errors}
	
	# Check terrain collision
	if _position_intersects_terrain(dest_vec, model):
		return {"valid": false, "errors": ["Position intersects impassable terrain"]}

	# Check model overlap
	if _position_overlaps_other_models(unit_id, model_id, dest_vec, model):
		return {"valid": false, "errors": ["Cannot end move on top of another model"]}

	return {"valid": true, "errors": []}

func _validate_undo_last_model_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	if not active_moves.has(unit_id):
		return {"valid": false, "errors": ["No active move for unit"]}
	
	var move_data = active_moves[unit_id]
	if move_data.model_moves.is_empty():
		return {"valid": false, "errors": ["No model moves to undo"]}
	
	return {"valid": true, "errors": []}

func _validate_reset_unit_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	if not active_moves.has(unit_id):
		return {"valid": false, "errors": ["No active move for unit"]}
	
	return {"valid": true, "errors": []}

func _validate_confirm_unit_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	if not active_moves.has(unit_id):
		return {"valid": false, "errors": ["No active move for unit"]}
	
	var move_data = active_moves[unit_id]
	
	# For Fall Back, ensure all models end outside engagement range
	if move_data.mode == "FALL_BACK":
		for model_move in move_data.model_moves:
			var dest = model_move.dest
			if _is_position_in_engagement_range(unit_id, model_move.model_id, dest):
				return {"valid": false, "errors": ["Model %s would still be in engagement range" % model_move.model_id]}
	
	return {"valid": true, "errors": []}

func _validate_remain_stationary(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}
	
	if unit.get("flags", {}).get("moved", false):
		return {"valid": false, "errors": ["Unit has already acted this phase"]}
	
	return {"valid": true, "errors": []}

func _validate_end_movement(action: Dictionary) -> Dictionary:
	# Check if there are any active moves that need to be resolved
	# Only incomplete moves should block phase end
	# NOTE: Check both local active_moves AND synced GameState to ensure multiplayer compatibility

	log_phase_message("=== END_MOVEMENT VALIDATION START ===")
	log_phase_message("Active moves count: %d" % active_moves.size())
	log_phase_message("Active moves keys: %s" % str(active_moves.keys()))

	# Get all deployed units for current player
	var current_player = get_current_player()
	var all_units = get_units_for_player(current_player)
	log_phase_message("Total deployed units for player %d: %d" % [current_player, all_units.size()])

	# Check which units have moved
	var moved_count = 0
	var unacted_count = 0
	for unit_id in all_units:
		var unit = all_units[unit_id]
		if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
			continue
		var has_moved = unit.get("flags", {}).get("moved", false)
		if has_moved:
			moved_count += 1
			log_phase_message("  ✓ Unit %s has moved" % unit_id)
		else:
			unacted_count += 1
			log_phase_message("  ✗ Unit %s has NOT moved (not marked in flags)" % unit_id)

	log_phase_message("Summary: %d moved, %d not moved" % [moved_count, unacted_count])

	for unit_id in active_moves:
		var move_data = active_moves[unit_id]
		# Check if unit has been marked as moved in GameState (synced across network)
		var unit = get_unit(unit_id)
		var has_moved = unit.get("flags", {}).get("moved", false)
		var unit_name = unit.get("meta", {}).get("name", unit_id)

		log_phase_message("Checking active_move for unit %s (%s)" % [unit_id, unit_name])
		log_phase_message("  - flags.moved: %s" % str(has_moved))
		log_phase_message("  - staged_moves: %d" % move_data.get("staged_moves", []).size())
		log_phase_message("  - model_moves: %d" % move_data.get("model_moves", []).size())
		log_phase_message("  - completed flag: %s" % str(move_data.get("completed", false)))

		# If not marked as moved in GameState, check if move was actually started
		if not has_moved:
			# Allow ending if no models have been moved (just initialized but not acted on)
			if move_data.get("staged_moves", []).is_empty() and move_data.get("model_moves", []).is_empty():
				# Unit was initialized for movement but never actually moved - this is OK
				log_phase_message("  → ALLOWING: Movement initialized but no models moved")
				continue

			# Unit has staged or committed moves that haven't been confirmed
			log_phase_message("  → BLOCKING: Unit has uncommitted moves!")
			log_phase_message("=== END_MOVEMENT VALIDATION FAILED ===")
			return {"valid": false, "errors": ["There are active moves that need to be confirmed or reset"]}

	# Player can always choose to end the phase
	log_phase_message("=== END_MOVEMENT VALIDATION PASSED ===")
	return {"valid": true, "errors": []}

# Processing Methods

func _process_begin_normal_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var unit = get_unit(unit_id)
	var move_inches = get_unit_movement(unit)
	
	active_moves[unit_id] = {
		"mode": "NORMAL",
		"mode_locked": false,  # Track if mode is confirmed
		"completed": false,  # Track if unit has completed movement
		"move_cap_inches": move_inches,
		"advance_roll": 0,  # Store advance dice result
		"model_moves": [],
		"staged_moves": [],  # NEW: Temporary moves before confirmation
		"original_positions": {},  # NEW: Track starting positions for reset
		"model_distances": {},  # NEW: Track per-model distances
		"dice_rolls": [],
		# Multi-selection group movement support
		"group_moves": [],  # Track group movement operations
		"group_selection": [],  # Current multi-selected models
		"group_formation": {}  # Relative positions within group
	}
	
	emit_signal("unit_move_begun", unit_id, "NORMAL")
	log_phase_message("Beginning normal move for %s (M: %d\")" % [unit.get("meta", {}).get("name", unit_id), move_inches])
	
	return create_result(true, [
		{
			"op": "set",
			"path": "units.%s.flags.move_cap_inches" % unit_id,
			"value": move_inches
		}
	])

func _process_begin_advance(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var unit = get_unit(unit_id)
	var move_inches = get_unit_movement(unit)
	
	# Roll D6 for advance (with deterministic seed for multiplayer)
	var rng_seed = -1
	if has_node("/root/NetworkManager"):
		var net_mgr = get_node("/root/NetworkManager")
		if net_mgr.is_networked() and net_mgr.is_host():
			rng_seed = net_mgr.get_next_rng_seed()

	var rng_service = RulesEngine.RNGService.new(rng_seed)
	var rolls = rng_service.roll_d6(1)
	var advance_roll = rolls[0]
	var total_move = move_inches + advance_roll
	
	active_moves[unit_id] = {
		"mode": "ADVANCE",
		"mode_locked": false,  # Track if mode is confirmed
		"completed": false,  # Track if unit has completed movement
		"move_cap_inches": total_move,
		"advance_roll": advance_roll,  # Store advance dice result
		"model_moves": [],
		"staged_moves": [],  # NEW: Temporary moves before confirmation
		"original_positions": {},  # NEW: Track starting positions for reset
		"model_distances": {},  # NEW: Track per-model distances
		"dice_rolls": [{"context": "advance", "rolls": [advance_roll]}],
		# Multi-selection group movement support
		"group_moves": [],  # Track group movement operations
		"group_selection": [],  # Current multi-selected models
		"group_formation": {}  # Relative positions within group
	}
	
	dice_log.append({
		"unit_id": unit_id,
		"unit_name": unit.get("meta", {}).get("name", unit_id),
		"type": "Advance",
		"roll": advance_roll,
		"result": "Move cap = %d\" (M %d\" + %d\")" % [total_move, move_inches, advance_roll]
	})
	
	emit_signal("unit_move_begun", unit_id, "ADVANCE")
	log_phase_message("Advance: %s → D6 = %d → Move cap = %d\"" % [unit.get("meta", {}).get("name", unit_id), advance_roll, total_move])
	
	return create_result(true, [
		{
			"op": "set",
			"path": "units.%s.flags.advanced" % unit_id,
			"value": true
		},
		{
			"op": "set",
			"path": "units.%s.flags.move_cap_inches" % unit_id,
			"value": total_move
		}
	], "", {"dice": [{"context": "advance", "n": 1, "rolls": [advance_roll]}]})

func _process_begin_fall_back(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var unit = get_unit(unit_id)
	var move_inches = get_unit_movement(unit)
	
	active_moves[unit_id] = {
		"mode": "FALL_BACK",
		"mode_locked": false,  # Track if mode is confirmed
		"completed": false,  # Track if unit has completed movement
		"move_cap_inches": move_inches,
		"advance_roll": 0,  # Not used for Fall Back but kept for consistency
		"model_moves": [],
		"staged_moves": [],  # NEW: Temporary moves before confirmation
		"original_positions": {},  # NEW: Track starting positions for reset
		"model_distances": {},  # NEW: Track per-model distances
		"dice_rolls": [],
		"battle_shocked": unit.get("status_effects", {}).get("battle_shocked", false),
		# Multi-selection group movement support
		"group_moves": [],  # Track group movement operations
		"group_selection": [],  # Current multi-selected models
		"group_formation": {}  # Relative positions within group
	}
	
	emit_signal("unit_move_begun", unit_id, "FALL_BACK")
	log_phase_message("Beginning fall back for %s (M: %d\")" % [unit.get("meta", {}).get("name", unit_id), move_inches])
	
	return create_result(true, [
		{
			"op": "set",
			"path": "units.%s.flags.fell_back" % unit_id,
			"value": true
		},
		{
			"op": "set",
			"path": "units.%s.flags.move_cap_inches" % unit_id,
			"value": move_inches
		}
	])

func _process_set_model_dest(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var payload = action.get("payload", {})
	var model_id = payload.get("model_id", "")
	var dest = payload.get("dest", [])
	var dest_vec = Vector2(dest[0], dest[1])
	
	var move_data = active_moves[unit_id]
	var model = _get_model_in_unit(unit_id, model_id)
	var current_pos = _get_model_position(model)
	
	# Calculate path and check for enemy crossing (Fall Back)
	var crosses_enemy = false
	if move_data.mode == "FALL_BACK":
		crosses_enemy = _path_crosses_enemy(current_pos, dest_vec, unit_id, model.get("base_mm", 32))
	
	# Add to model moves
	move_data.model_moves.append({
		"model_id": model_id,
		"from": current_pos,
		"dest": dest_vec,
		"crosses_enemy": crosses_enemy
	})
	
	var distance_inches = Measurement.distance_inches(current_pos, dest_vec)
	emit_signal("model_drop_committed", unit_id, model_id, dest_vec)
	
	return create_result(true, [
		{
			"op": "set",
			"path": "units.%s.models.%s.position" % [unit_id, _get_model_index(unit_id, model_id)],
			"value": {"x": dest_vec.x, "y": dest_vec.y}
		}
	])

func _process_stage_model_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var payload = action.get("payload", {})
	var model_id = payload.get("model_id", "")
	var dest = payload.get("dest", [])
	var rotation = payload.get("rotation", 0.0)
	var dest_vec = Vector2(dest[0], dest[1])

	print("[MovementPhase] Processing STAGE_MODEL_MOVE for model ", model_id, " to ", dest_vec)

	var move_data = active_moves[unit_id]
	var model = _get_model_in_unit(unit_id, model_id)
	
	# Get current position (may be staged)
	var current_pos = null
	for staged_move in move_data.staged_moves:
		if staged_move.model_id == model_id:
			current_pos = staged_move.dest
			break
	
	# If no staged position, use actual position
	if current_pos == null:
		current_pos = _get_model_position(model)
		# Store original position if this is the first move for this model
		if not move_data.original_positions.has(model_id):
			move_data.original_positions[model_id] = current_pos
	
	# Calculate distance for this stage
	var distance_inches = Measurement.distance_inches(current_pos, dest_vec)
	
	# Check for enemy crossing (Fall Back)
	var crosses_enemy = false
	if move_data.mode == "FALL_BACK":
		crosses_enemy = _path_crosses_enemy(current_pos, dest_vec, unit_id, model.get("base_mm", 32))
	
	# Calculate total distance from original position
	var original_pos = move_data.original_positions.get(model_id, current_pos)
	var total_distance_for_model = Measurement.distance_inches(original_pos, dest_vec)
	
	# Remove any existing staged move for this model to prevent duplicates
	var moves_to_remove = []
	for i in range(move_data.staged_moves.size()):
		if move_data.staged_moves[i].model_id == model_id:
			moves_to_remove.append(i)

	# Remove in reverse order to maintain indices
	for i in range(moves_to_remove.size() - 1, -1, -1):
		move_data.staged_moves.remove_at(moves_to_remove[i])

	# Add the new staged move
	move_data.staged_moves.append({
		"model_id": model_id,
		"from": current_pos,
		"dest": dest_vec,
		"rotation": rotation,  # Preserve rotation
		"distance": distance_inches,  # Keep individual segment distance for display
		"total_distance": total_distance_for_model,  # Track total from origin
		"crosses_enemy": crosses_enemy
	})
	
	# Update per-model distance tracking
	move_data.model_distances[model_id] = total_distance_for_model
	
	print("  - Distance this segment: ", distance_inches, "\"")
	print("  - Total distance from origin: ", total_distance_for_model, "\"")
	print("  - Remaining for this model: ", (move_data.move_cap_inches - total_distance_for_model), "\"")
	
	# Emit both signals for visual update
	emit_signal("model_drop_preview", unit_id, model_id, [current_pos, dest_vec], distance_inches, true)
	# Also emit committed signal so model visually moves (but game state not updated)
	emit_signal("model_drop_committed", unit_id, model_id, dest_vec)
	
	# Return result without state changes (staged only)
	return create_result(true, [], "", {
		"staged": true, 
		"model_distance": total_distance_for_model,
		"model_remaining": move_data.move_cap_inches - total_distance_for_model,
		"model_distances": move_data.model_distances
	})

func _process_undo_last_model_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var move_data = active_moves[unit_id]
	
	if move_data.model_moves.is_empty():
		return create_result(false, [], "No moves to undo")
	
	var last_move = move_data.model_moves.pop_back()
	var model_id = last_move.model_id
	var from_pos = last_move.from
	
	return create_result(true, [
		{
			"op": "set",
			"path": "units.%s.models.%s.position" % [unit_id, _get_model_index(unit_id, model_id)],
			"value": {"x": from_pos.x, "y": from_pos.y} if from_pos else null
		}
	])

func _process_reset_unit_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var move_data = active_moves[unit_id]
	var changes = []
	
	# Reset models from staged moves to their original positions
	for model_id in move_data.original_positions:
		var original_pos = move_data.original_positions[model_id]
		if original_pos:
			changes.append({
				"op": "set",
				"path": "units.%s.models.%s.position" % [unit_id, _get_model_index(unit_id, model_id)],
				"value": {"x": original_pos.x, "y": original_pos.y}
			})
	
	# Reset all model positions from permanent moves (if any)
	for model_move in move_data.model_moves:
		var from_pos = model_move.from
		changes.append({
			"op": "set",
			"path": "units.%s.models.%s.position" % [unit_id, _get_model_index(unit_id, model_move.model_id)],
			"value": {"x": from_pos.x, "y": from_pos.y} if from_pos else null
		})
	
	# Clear all move data
	move_data.model_moves.clear()
	move_data.staged_moves.clear()
	move_data.model_distances.clear()  # Clear per-model distances
	move_data.original_positions.clear()
	
	emit_signal("unit_move_reset", unit_id)
	
	return create_result(true, changes)

func _process_confirm_unit_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var move_data = active_moves[unit_id]
	var changes = []
	var additional_dice = []

	print("[MovementPhase] Confirming unit move with ", move_data.staged_moves.size(), " staged moves")

	# Get unique model IDs
	var unique_models = {}
	for staged_move in move_data.staged_moves:
		unique_models[staged_move.model_id] = true
	print("[MovementPhase] Processing ", unique_models.size(), " unique models")

	# Convert staged moves to permanent moves
	for staged_move in move_data.staged_moves:
		print("  Confirming move for model ", staged_move.model_id, " to ", staged_move.dest)
		# Add to permanent moves
		move_data.model_moves.append({
			"model_id": staged_move.model_id,
			"from": staged_move.get("from"),
			"dest": staged_move.dest,
			"rotation": staged_move.get("rotation", 0.0),
			"crosses_enemy": staged_move.get("crosses_enemy", false)
		})

		# Update model position in game state
		changes.append({
			"op": "set",
			"path": "units.%s.models.%s.position" % [unit_id, _get_model_index(unit_id, staged_move.model_id)],
			"value": {"x": staged_move.dest.x, "y": staged_move.dest.y}
		})

		# Update model rotation in game state
		changes.append({
			"op": "set",
			"path": "units.%s.models.%s.rotation" % [unit_id, _get_model_index(unit_id, staged_move.model_id)],
			"value": staged_move.get("rotation", 0.0)
		})
	
	# Clear staged moves after converting them
	move_data.staged_moves.clear()
	move_data.accumulated_distance = 0.0
	
	# Handle Desperate Escape for Fall Back
	if move_data.mode == "FALL_BACK":
		var desperate_escape_result = _process_desperate_escape(unit_id, move_data)
		changes.append_array(desperate_escape_result.changes)
		additional_dice.append_array(desperate_escape_result.dice)
	
	# Mark unit as moved
	changes.append({
		"op": "set",
		"path": "units.%s.flags.moved" % unit_id,
		"value": true
	})
	
	# Clear temporary move data
	changes.append({
		"op": "remove",
		"path": "units.%s.flags.move_cap_inches" % unit_id
	})
	
	# Set movement restrictions for later phases
	if move_data.mode == "ADVANCE":
		# ASSAULT RULES: Set the 'advanced' flag for Shooting phase to check
		# Units that Advanced can shoot with Assault weapons only
		changes.append({
			"op": "set",
			"path": "units.%s.flags.advanced" % unit_id,
			"value": true
		})
		changes.append({
			"op": "set",
			"path": "units.%s.flags.cannot_charge" % unit_id,
			"value": true
		})
	elif move_data.mode == "FALL_BACK":
		# Set fell_back flag - units that Fell Back cannot shoot or charge
		changes.append({
			"op": "set",
			"path": "units.%s.flags.fell_back" % unit_id,
			"value": true
		})
		changes.append({
			"op": "set",
			"path": "units.%s.flags.cannot_shoot" % unit_id,
			"value": true
		})
		changes.append({
			"op": "set",
			"path": "units.%s.flags.cannot_charge" % unit_id,
			"value": true
		})
	
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("Confirmed %s move for %s" % [move_data.mode.to_lower(), unit_name])
	
	# Mark unit as completed before cleanup
	move_data["completed"] = true

	emit_signal("unit_move_confirmed", unit_id, {"mode": move_data.mode, "models_moved": move_data.model_moves.size()})

	# Check for embark opportunity after movement
	if not unit.get("disembarked_this_phase", false):
		call_deferred("_check_embark_opportunity", unit_id)

	return create_result(true, changes, "", {"dice": additional_dice})

func _process_remain_stationary(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var unit = get_unit(unit_id)
	
	var changes = [
		{
			"op": "set",
			"path": "units.%s.flags.moved" % unit_id,
			"value": true
		},
		{
			"op": "set",
			"path": "units.%s.flags.remained_stationary" % unit_id,
			"value": true
		}
	]
	
	log_phase_message("%s remained stationary" % unit.get("meta", {}).get("name", unit_id))
	
	# Mark unit as completed in active_moves
	if active_moves.has(unit_id):
		active_moves[unit_id]["completed"] = true
	else:
		active_moves[unit_id] = {
			"mode": "REMAIN_STATIONARY",
			"mode_locked": true,
			"completed": true,
			"move_cap_inches": 0,
			"advance_roll": 0,
			"model_moves": [],
			"staged_moves": [],
			"original_positions": {},
			"model_distances": {},
			"dice_rolls": [],
			# Multi-selection group movement support
			"group_moves": [],  # Track group movement operations
			"group_selection": [],  # Current multi-selected models
			"group_formation": {}  # Relative positions within group
		}
	
	emit_signal("unit_move_confirmed", unit_id, {"mode": "REMAIN_STATIONARY", "distance": 0})
	
	return create_result(true, changes)

func _validate_lock_movement_mode(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	if not active_moves.has(unit_id):
		return {"valid": false, "errors": ["Unit has not begun movement"]}
	
	if active_moves[unit_id].get("mode_locked", false):
		return {"valid": false, "errors": ["Movement mode already locked"]}
	
	return {"valid": true}

func _process_lock_movement_mode(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var mode = action.get("payload", {}).get("mode", "")
	
	if active_moves.has(unit_id):
		active_moves[unit_id]["mode_locked"] = true
		if mode != "":
			active_moves[unit_id]["mode"] = mode
		
		emit_signal("movement_mode_locked", unit_id, active_moves[unit_id]["mode"])
		log_phase_message("Locked movement mode for %s: %s" % [get_unit(unit_id).get("meta", {}).get("name", unit_id), active_moves[unit_id]["mode"]])
	
	return create_result(true, [])

func _validate_set_advance_bonus(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	if not active_moves.has(unit_id):
		return {"valid": false, "errors": ["Unit has not begun movement"]}
	
	if active_moves[unit_id].get("mode", "") != "ADVANCE":
		return {"valid": false, "errors": ["Unit is not advancing"]}
	
	return {"valid": true}

func _process_set_advance_bonus(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var bonus = action.get("payload", {}).get("bonus", 0)
	
	if active_moves.has(unit_id):
		active_moves[unit_id]["advance_roll"] = bonus
		var unit = get_unit(unit_id)
		var base_move = get_unit_movement(unit)
		active_moves[unit_id]["move_cap_inches"] = base_move + bonus
		
		log_phase_message("Set advance bonus for %s: +%d\" (total: %d\")" % [
			unit.get("meta", {}).get("name", unit_id),
			bonus,
			active_moves[unit_id]["move_cap_inches"]
		])
	
	return create_result(true, [])

func _process_end_movement(action: Dictionary) -> Dictionary:
	log_phase_message("=== PROCESSING END_MOVEMENT ===")
	log_phase_message("Ending Movement Phase - emitting phase_completed signal")
	emit_signal("phase_completed")
	log_phase_message("=== END_MOVEMENT COMPLETE ===")
	return create_result(true, [])

func _process_desperate_escape(unit_id: String, move_data: Dictionary) -> Dictionary:
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])
	var changes = []
	var dice_rolls = []
	
	# Determine which models need Desperate Escape tests
	var models_to_test = []
	
	if move_data.battle_shocked:
		# All models test if Battle-shocked
		for i in range(models.size()):
			var model = models[i]
			if model.get("alive", true):
				models_to_test.append({"index": i, "id": model.get("id", "m%d" % i)})
	else:
		# Only models that crossed enemies
		for model_move in move_data.model_moves:
			if model_move.crosses_enemy:
				var idx = _get_model_index(unit_id, model_move.model_id)
				if idx >= 0:
					models_to_test.append({"index": idx, "id": model_move.model_id})
	
	if models_to_test.is_empty():
		return {"changes": [], "dice": []}
	
	# Roll D6 for each model (with deterministic seed for multiplayer)
	var rng_seed = -1
	if has_node("/root/NetworkManager"):
		var net_mgr = get_node("/root/NetworkManager")
		if net_mgr.is_networked() and net_mgr.is_host():
			rng_seed = net_mgr.get_next_rng_seed()

	var rng_service = RulesEngine.RNGService.new(rng_seed)
	var casualties = 0
	var rolls = []

	for model_data in models_to_test:
		var roll_result = rng_service.roll_d6(1)
		var roll = roll_result[0]
		rolls.append(roll)
		if roll <= 2:
			casualties += 1
	
	# Apply casualties (player chooses which models)
	# For MVP, remove the first N alive models
	var removed = 0
	for i in range(models.size()):
		if removed >= casualties:
			break
		if models[i].get("alive", true):
			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.alive" % [unit_id, i],
				"value": false
			})
			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.current_wounds" % [unit_id, i],
				"value": 0
			})
			removed += 1
	
	dice_rolls.append({
		"context": "desperate_escape",
		"n": models_to_test.size(),
		"rolls": rolls
	})
	
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	if casualties > 0:
		dice_log.append({
			"unit_id": unit_id,
			"unit_name": unit_name,
			"type": "Desperate Escape",
			"rolls": rolls,
			"result": "%d models lost" % casualties
		})
		log_phase_message("Desperate Escape: %s → rolls: %s → models lost: %d" % [unit_name, str(rolls), casualties])
	
	return {"changes": changes, "dice": dice_rolls}

# Helper Methods

func _is_unit_engaged(unit_id: String) -> bool:
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])
	
	for model in models:
		if not model.get("alive", true):
			continue
		var pos = _get_model_position(model)
		if pos and _is_position_in_engagement_range(unit_id, model.get("id", ""), pos):
			return true
	
	return false

func _is_position_in_engagement_range(unit_id: String, model_id: String, pos: Vector2) -> bool:
	var model = _get_model_in_unit(unit_id, model_id)

	# Create a temporary model dict with the proposed position for shape-aware checks
	var model_at_pos = model.duplicate()
	model_at_pos["position"] = pos

	# Check against all enemy units using shape-aware distance
	var current_player = get_current_player()
	var units = game_state_snapshot.get("units", {})

	for enemy_unit_id in units:
		var enemy_unit = units[enemy_unit_id]
		if enemy_unit.get("owner", 0) == current_player:
			continue  # Skip friendly units

		var enemy_models = enemy_unit.get("models", [])
		for enemy_model in enemy_models:
			if not enemy_model.get("alive", true):
				continue
			var enemy_pos = _get_model_position(enemy_model)
			if enemy_pos:
				if Measurement.is_in_engagement_range_shape_aware(model_at_pos, enemy_model, ENGAGEMENT_RANGE_INCHES):
					return true

	return false

func _check_engagement_range_at_position(unit_id: String, model_id: String, dest: Vector2, mode: String) -> Dictionary:
	if mode == "FALL_BACK":
		# Fall Back allows ending outside ER even if path goes through
		if _is_position_in_engagement_range(unit_id, model_id, dest):
			return {"valid": false, "errors": ["Fall Back must end outside engagement range"]}
	else:
		# Normal and Advance cannot enter or end in ER
		if _is_position_in_engagement_range(unit_id, model_id, dest):
			return {"valid": false, "errors": ["Cannot end within engagement range"]}
	
	return {"valid": true, "errors": []}

func _path_crosses_enemy(from: Vector2, to: Vector2, unit_id: String, base_mm: int) -> bool:
	# Check if path segment crosses any enemy model bases using shape-aware overlap
	# Sample points along the path and check for overlap at each point
	var current_player = get_current_player()
	var units = game_state_snapshot.get("units", {})

	# Get a reference model to build temporary model dicts for path checking
	# We'll use the first alive model from the unit
	var reference_model = null
	var unit = units.get(unit_id, {})
	for model in unit.get("models", []):
		if model.get("alive", true):
			reference_model = model.duplicate()
			break

	if reference_model == null:
		return false  # No alive models to check

	# Sample points along the path (approximately every 10 pixels for good coverage)
	var path_length = from.distance_to(to)
	var num_samples = max(2, int(path_length / 10.0))

	for i in range(num_samples + 1):
		var t = float(i) / float(num_samples)
		var sample_pos = from.lerp(to, t)

		# Create a temporary model at this position
		var model_at_pos = reference_model.duplicate()
		model_at_pos["position"] = sample_pos

		# Check against all enemy models
		for enemy_unit_id in units:
			var enemy_unit = units[enemy_unit_id]
			if enemy_unit.get("owner", 0) == current_player:
				continue

			var enemy_models = enemy_unit.get("models", [])
			for enemy_model in enemy_models:
				if not enemy_model.get("alive", true):
					continue
				var enemy_pos = _get_model_position(enemy_model)
				if enemy_pos:
					# Use shape-aware overlap check or engagement range check
					if Measurement.models_overlap(model_at_pos, enemy_model):
						return true
					# Also check if within engagement range (path can't cross ER)
					if Measurement.is_in_engagement_range_shape_aware(model_at_pos, enemy_model, ENGAGEMENT_RANGE_INCHES):
						return true

	return false

func _segment_intersects_circle(seg_start: Vector2, seg_end: Vector2, circle_center: Vector2, radius: float) -> bool:
	# Calculate closest point on segment to circle center
	var seg_vec = seg_end - seg_start
	var to_center = circle_center - seg_start
	var t = clamp(to_center.dot(seg_vec) / seg_vec.length_squared(), 0.0, 1.0)
	var closest_point = seg_start + seg_vec * t
	var distance = closest_point.distance_to(circle_center)
	return distance <= radius

func _position_overlaps_other_models(unit_id: String, model_id: String, position: Vector2, model_data: Dictionary = {}) -> bool:
	# Check if a position would overlap with any other models
	# Returns true if there's an overlap (invalid position)
	var units = game_state_snapshot.get("units", {})

	# Build a model dict for the checking position
	var check_model = model_data.duplicate() if not model_data.is_empty() else _get_model_in_unit(unit_id, model_id)
	check_model["position"] = position

	for check_unit_id in units:
		var unit = units[check_unit_id]
		# Check models in all units (friendly and enemy)
		var models = unit.get("models", [])

		for i in range(models.size()):
			var other_model = models[i]
			var other_model_id = other_model.get("id", "m%d" % (i+1))

			# Skip self
			if check_unit_id == unit_id and other_model_id == model_id:
				continue

			# Skip dead models
			if not other_model.get("alive", true):
				continue

			# Get the current position of the other model
			# Check if it has a staged position in active moves
			var other_position = null
			if active_moves.has(check_unit_id):
				var move_data = active_moves[check_unit_id]
				# Check if this model has a staged position
				for staged_move in move_data.get("staged_moves", []):
					if staged_move.get("model_id") == other_model_id:
						other_position = staged_move.get("dest")
						break

			# If no staged position, use actual position
			if other_position == null:
				other_position = _get_model_position(other_model)

			if other_position == null:
				continue

			# Build other model dict with correct position
			var other_model_check = other_model.duplicate()
			other_model_check["position"] = other_position

			# Check for overlap using the Measurement utility
			if Measurement.models_overlap(check_model, other_model_check):
				return true

	return false

func _position_intersects_terrain(pos: Vector2, model: Dictionary) -> bool:
	# Check against terrain polygons using shape-aware bounds
	var terrain = game_state_snapshot.get("board", {}).get("terrain", [])

	# Create the base shape to get accurate bounds
	var base_shape = Measurement.create_base_shape(model)
	var bounds = base_shape.get_bounds()

	# Use the maximum dimension of the bounds as the expansion
	# This provides better coverage for non-circular bases
	var expansion = max(bounds.size.x, bounds.size.y) / 2.0

	for terrain_piece in terrain:
		if terrain_piece.get("type", "") == "impassable":
			var poly = terrain_piece.get("poly", [])
			if _point_in_expanded_polygon(pos, poly, expansion):
				return true

	return false

func _point_in_expanded_polygon(point: Vector2, poly: Array, expansion: float) -> bool:
	# Simple point-in-polygon test with expansion
	# For MVP, treat as rectangle bounds check
	if poly.is_empty():
		return false
	
	var min_x = INF
	var max_x = -INF
	var min_y = INF
	var max_y = -INF
	
	for vertex in poly:
		min_x = min(min_x, vertex.x)
		max_x = max(max_x, vertex.x)
		min_y = min(min_y, vertex.y)
		max_y = max(max_y, vertex.y)
	
	return point.x >= (min_x - expansion) and point.x <= (max_x + expansion) and \
		   point.y >= (min_y - expansion) and point.y <= (max_y + expansion)

func _get_model_in_unit(unit_id: String, model_id: String) -> Dictionary:
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])
	for model in models:
		if model.get("id", "") == model_id:
			return model
	return {}

func _get_model_index(unit_id: String, model_id: String) -> int:
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])
	for i in range(models.size()):
		if models[i].get("id", "") == model_id:
			return i
	return -1

func _get_model_position(model: Dictionary) -> Vector2:
	var pos = model.get("position")
	if pos == null:
		return Vector2.ZERO
	if pos is Dictionary:
		return Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO

func _clear_unit_move_state(unit_id: String) -> void:
	if active_moves.has(unit_id):
		active_moves.erase(unit_id)

func get_available_actions() -> Array:
	var actions = []
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
			continue
		
		# Skip if already moved
		if unit.get("flags", {}).get("moved", false):
			continue
		
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var is_engaged = _is_unit_engaged(unit_id)
		
		if is_engaged:
			# Can only Fall Back or Remain Stationary when engaged
			actions.append({
				"type": "BEGIN_FALL_BACK",
				"actor_unit_id": unit_id,
				"description": "Fall Back with " + unit_name
			})
			actions.append({
				"type": "REMAIN_STATIONARY",
				"actor_unit_id": unit_id,
				"description": unit_name + " remains stationary"
			})
		else:
			# Normal movement options
			actions.append({
				"type": "BEGIN_NORMAL_MOVE",
				"actor_unit_id": unit_id,
				"description": "Move " + unit_name
			})
			actions.append({
				"type": "BEGIN_ADVANCE",
				"actor_unit_id": unit_id,
				"description": "Advance with " + unit_name
			})
			actions.append({
				"type": "REMAIN_STATIONARY",
				"actor_unit_id": unit_id,
				"description": unit_name + " remains stationary"
			})
	
	# Add active move actions
	for unit_id in active_moves:
		actions.append({
			"type": "CONFIRM_UNIT_MOVE",
			"actor_unit_id": unit_id,
			"description": "Confirm move"
		})
		actions.append({
			"type": "RESET_UNIT_MOVE",
			"actor_unit_id": unit_id,
			"description": "Reset move"
		})
		if not active_moves[unit_id].model_moves.is_empty():
			actions.append({
				"type": "UNDO_LAST_MODEL_MOVE",
				"actor_unit_id": unit_id,
				"description": "Undo last model"
			})
	
	# Add End Movement Phase action if no incomplete moves
	# Check using synced GameState to ensure multiplayer compatibility
	var has_incomplete_moves = false
	log_phase_message("[get_available_actions] Checking if END_MOVEMENT should be available...")
	log_phase_message("[get_available_actions] Active moves: %s" % str(active_moves.keys()))

	for unit_id in active_moves:
		var unit = get_unit(unit_id)
		var has_moved = unit.get("flags", {}).get("moved", false)
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		log_phase_message("[get_available_actions]   Unit %s (%s): flags.moved = %s" % [unit_id, unit_name, str(has_moved)])
		if not has_moved:
			has_incomplete_moves = true
			log_phase_message("[get_available_actions]   → This unit has incomplete moves!")
			break

	if not has_incomplete_moves:
		log_phase_message("[get_available_actions] ✓ Adding END_MOVEMENT action")
		actions.append({
			"type": "END_MOVEMENT",
			"description": "End Movement Phase"
		})
	else:
		log_phase_message("[get_available_actions] ✗ NOT adding END_MOVEMENT (incomplete moves exist)")
	
	return actions

func _should_complete_phase() -> bool:
	# Movement phase should NOT auto-complete
	# Phase completion must be explicit via END_MOVEMENT action for:
	# 1. User control - player may want to use stratagems before ending phase
	# 2. Multiplayer sync - phase transitions must be synchronized via actions
	return false

func get_dice_log() -> Array:
	return dice_log

func get_active_move_data(unit_id: String) -> Dictionary:
	# Helper method for MovementController to access active move data
	if active_moves.has(unit_id):
		return active_moves[unit_id]
	return {}

# GROUP MOVEMENT VALIDATION FUNCTIONS

func _process_group_movement(selected_models: Array, drag_vector: Vector2, unit_id: String) -> Dictionary:
	"""Process and validate group movement for multiple models"""
	var group_validation = {"valid": true, "errors": [], "individual_distances": {}}

	if not active_moves.has(unit_id):
		group_validation.valid = false
		group_validation.errors.append("No active move data for unit")
		return group_validation

	var move_data = active_moves[unit_id]
	var move_cap_inches = move_data.move_cap_inches

	for model_data in selected_models:
		var model_id = model_data.model_id
		var original_pos = move_data.original_positions.get(model_id, model_data.position)
		var new_pos = model_data.position + drag_vector

		# Calculate individual distance
		var total_distance = Measurement.distance_inches(original_pos, new_pos)
		group_validation.individual_distances[model_id] = total_distance

		# Validate against movement cap
		if total_distance > move_cap_inches:
			group_validation.valid = false
			group_validation.errors.append("Model %s exceeds movement cap (%.1f\" > %.1f\")" % [model_id, total_distance, move_cap_inches])

		# Check for terrain collisions
		if _check_terrain_collision(new_pos):
			group_validation.valid = false
			group_validation.errors.append("Model %s would collide with terrain" % model_id)

		# Check for model overlaps
		if _would_overlap_other_models(unit_id, model_id, new_pos, model_data):
			group_validation.valid = false
			group_validation.errors.append("Model %s would overlap with another model" % model_id)

	return group_validation

func _validate_group_movement(group_moves: Array, unit_id: String) -> Dictionary:
	"""Validate a group of movement actions for coherency and rule compliance"""
	var validation_result = {"valid": true, "errors": [], "warnings": []}

	if not active_moves.has(unit_id):
		validation_result.valid = false
		validation_result.errors.append("No active move data for unit")
		return validation_result

	var move_data = active_moves[unit_id]

	for move in group_moves:
		var model_id = move.get("model_id", "")
		var dest_pos = Vector2(move.get("dest", [0, 0])[0], move.get("dest", [0, 0])[1])

		# Individual validations
		if not _validate_individual_move_internal(unit_id, model_id, dest_pos):
			validation_result.valid = false
			validation_result.errors.append("Invalid move for model %s" % model_id)

	# Check unit coherency for the entire group
	if not _check_group_unit_coherency(group_moves, unit_id):
		validation_result.warnings.append("Group movement may break unit coherency")

	return validation_result

func _validate_individual_move_internal(unit_id: String, model_id: String, dest_pos: Vector2) -> bool:
	"""Internal validation for a single model move"""
	if not active_moves.has(unit_id):
		return false

	var move_data = active_moves[unit_id]
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])

	# Find the model
	var model = null
	for m in models:
		if m.get("id", "") == model_id:
			model = m
			break

	if not model:
		return false

	# Check distance limit
	var original_pos = move_data.original_positions.get(model_id, _get_model_position(model))
	var total_distance = Measurement.distance_inches(original_pos, dest_pos)

	if total_distance > move_data.move_cap_inches:
		return false

	# Check terrain collision
	if _check_terrain_collision(dest_pos):
		return false

	# Check model overlap
	if _would_overlap_other_models(unit_id, model_id, dest_pos, model):
		return false

	return true

func _check_group_unit_coherency(group_moves: Array, unit_id: String) -> bool:
	"""Check if a group of moves maintains unit coherency"""
	var unit = get_unit(unit_id)
	if not unit:
		return false

	var models = unit.get("models", [])
	if models.size() <= 1:
		return true  # Single model units are always coherent

	# Build model dicts with final positions for shape-aware distance checks
	var final_models = {}

	# Add model dicts for models not being moved
	for model in models:
		if not model.get("alive", true):
			continue
		var model_id = model.get("id", "")
		final_models[model_id] = model

	# Update positions for models being moved
	for move in group_moves:
		var model_id = move.get("model_id", "")
		var dest = move.get("dest", [0, 0])
		if final_models.has(model_id):
			var moved_model = final_models[model_id].duplicate()
			moved_model["position"] = Vector2(dest[0], dest[1])
			final_models[model_id] = moved_model

	# Check coherency rules using shape-aware edge-to-edge distance
	var model_count = final_models.size()

	for model_id1 in final_models:
		var connections = 0

		for model_id2 in final_models:
			if model_id1 == model_id2:
				continue

			var distance = Measurement.model_to_model_distance_inches(final_models[model_id1], final_models[model_id2])

			if distance <= 2.0:
				connections += 1

		# Coherency rules based on unit size
		var required_connections = 1 if model_count <= 6 else 2

		if connections < required_connections:
			return false

	return true

func _check_terrain_collision(position: Vector2) -> bool:
	"""Check if a position collides with terrain"""
	# Implementation depends on terrain system
	# For now, return false (no collision)
	return false

func _would_overlap_other_models(unit_id: String, model_id: String, position: Vector2, model_data: Dictionary) -> bool:
	"""Check if placing a model at the given position would overlap with other models"""
	return _position_overlaps_other_models(unit_id, model_id, position, model_data)

# Override create_result to support additional data
func create_result(success: bool, changes: Array = [], error: String = "", additional_data: Dictionary = {}) -> Dictionary:
	var result = {
		"success": success,
		"phase": phase_type,
		"timestamp": Time.get_unix_time_from_system()
	}
	
	if success:
		result["changes"] = changes
		for key in additional_data:
			result[key] = additional_data[key]
	else:
		result["error"] = error
	
	return result

# Transport-related methods

func _check_embark_opportunity(unit_id: String) -> void:
	"""Check if a unit that just moved can embark in a nearby transport"""
	var unit = get_unit(unit_id)
	if not unit:
		return

	# Skip if unit is a transport itself
	if unit.has("transport_data"):
		return

	# Get unit's center position
	var unit_pos = _get_unit_center_position(unit_id)
	if unit_pos == Vector2.ZERO:
		return

	# Find friendly transports within 3"
	var player = unit.owner
	for transport_id in game_state_snapshot.units:
		var transport = game_state_snapshot.units[transport_id]

		# Skip if not same owner
		if transport.owner != player:
			continue

		# Skip if not a transport
		if not transport.has("transport_data") or transport.transport_data.get("capacity", 0) == 0:
			continue

		# Skip if transport is the same unit
		if transport_id == unit_id:
			continue

		# Get transport position
		var transport_pos = _get_unit_center_position(transport_id)
		if transport_pos == Vector2.ZERO:
			continue

		# Check if all models are within 3" of transport (edge-to-edge)
		var all_within_range = true
		var transport_model = transport.models[0] if transport.models.size() > 0 else {}
		for model in unit.models:
			if not model.alive or model.position == null:
				continue

			var dist_inches = Measurement.model_to_model_distance_inches(model, transport_model) if not transport_model.is_empty() else INF

			if dist_inches > 3.0:
				all_within_range = false
				break

		if all_within_range:
			# Check if unit can embark
			var can_embark = TransportManager.can_embark(unit_id, transport_id)
			if can_embark.valid:
				_show_embark_prompt(unit_id, transport_id)
				return  # Only show one prompt at a time

func _show_embark_prompt(unit_id: String, transport_id: String) -> void:
	"""Show dialog asking if player wants to embark unit"""
	var dialog = ConfirmationDialog.new()
	var unit = get_unit(unit_id)
	var transport = get_unit(transport_id)

	dialog.title = "Embark Unit"
	dialog.dialog_text = "Do you want to embark %s into %s?" % [
		unit.meta.get("name", unit_id),
		transport.meta.get("name", transport_id)
	]

	dialog.get_ok_button().text = "Embark"
	dialog.get_cancel_button().text = "Stay Deployed"

	dialog.confirmed.connect(func():
		TransportManager.embark_unit(unit_id, transport_id)
		log_phase_message("Unit %s embarked in transport %s" % [
			unit.meta.get("name", unit_id),
			transport.meta.get("name", transport_id)
		])
		dialog.queue_free()
	)

	dialog.canceled.connect(func():
		dialog.queue_free()
	)

	get_tree().root.add_child(dialog)
	dialog.popup_centered()

func _get_unit_center_position(unit_id: String) -> Vector2:
	"""Get the center position of a unit (average of all alive models)"""
	var unit = get_unit(unit_id)
	if not unit:
		return Vector2.ZERO

	var center = Vector2.ZERO
	var count = 0

	for model in unit.models:
		if model.alive and model.position != null:
			center += Vector2(model.position.x, model.position.y)
			count += 1

	if count > 0:
		center /= count

	return center

# Add new actions for transport operations

func validate_action_with_transport_check(action: Dictionary) -> Dictionary:
	"""Enhanced validation that checks for transport operations"""
	var action_type = action.get("type", "")

	# Check for disembark action
	if action_type == "DISEMBARK_UNIT":
		return _validate_disembark_unit(action)
	elif action_type == "CONFIRM_DISEMBARK":
		return _validate_confirm_disembark(action)

	# For normal movement actions, check if unit is embarked
	var movement_actions = ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "BEGIN_FALL_BACK"]
	if action_type in movement_actions:
		var unit_id = action.get("actor_unit_id", "")
		if unit_id != "":
			var unit = get_unit(unit_id)
			if unit and unit.get("embarked_in", null) != null:
				# Redirect to disembark flow
				return {"valid": false, "redirect_to": "DISEMBARK", "unit_id": unit_id}

	# Otherwise use normal validation
	return validate_action(action)

func _validate_disembark_unit(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}

	if unit.get("embarked_in", null) == null:
		return {"valid": false, "errors": ["Unit is not embarked"]}

	var validation = TransportManager.can_disembark(unit_id)
	if not validation.valid:
		return {"valid": false, "errors": [validation.reason]}

	return {"valid": true, "errors": []}

func _validate_confirm_disembark(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var positions = action.get("payload", {}).get("positions", [])

	if positions.size() == 0:
		return {"valid": false, "errors": ["No positions provided for disembark"]}

	# Validate each position
	var unit = get_unit(unit_id)
	var transport_id = unit.get("embarked_in", null)
	var transport = get_unit(transport_id)

	if not transport:
		return {"valid": false, "errors": ["Transport not found"]}

	# Get transport position for range check
	var transport_pos = _get_unit_center_position(transport_id)
	print("DEBUG MovementPhase: Transport position: ", transport_pos)

	var transport_model = transport.models[0] if transport.models.size() > 0 else {}

	for i in range(positions.size()):
		if i >= unit.models.size():
			break

		if not unit.models[i].alive:
			continue

		var pos = positions[i]
		print("DEBUG MovementPhase: Model position: ", pos)

		# Use shape-aware edge-to-edge distance for transport range check
		var model_at_pos = unit.models[i].duplicate()
		model_at_pos["position"] = pos
		var dist_edge_to_edge = Measurement.model_to_model_distance_inches(model_at_pos, transport_model) if not transport_model.is_empty() else INF
		print("DEBUG MovementPhase: Edge-to-edge distance (inches): ", dist_edge_to_edge)

		if dist_edge_to_edge > 3.0:
			return {"valid": false, "errors": ["Model must be placed within 3\" of transport (%.1f\" from edge)" % dist_edge_to_edge]}

		# Check engagement range using shape-aware distance
		if _model_in_engagement_range(model_at_pos, unit.owner):
			return {"valid": false, "errors": ["Cannot disembark within Engagement Range of enemy"]}

	return {"valid": true, "errors": []}

func _model_in_engagement_range(model_data: Dictionary, owner: int) -> bool:
	"""Check if a model is within engagement range of any enemy model (shape-aware)"""
	var enemy_player = 3 - owner
	for enemy_id in game_state_snapshot.units:
		var enemy = game_state_snapshot.units[enemy_id]
		if enemy.owner != enemy_player:
			continue

		# Skip embarked enemies
		if enemy.get("embarked_in", null) != null:
			continue

		for model in enemy.models:
			if not model.alive or model.position == null:
				continue

			if Measurement.is_in_engagement_range_shape_aware(model_data, model, 1.0):
				return true

	return false

func _position_in_engagement_range(pos: Vector2, owner: int) -> bool:
	"""Check if a position is within engagement range of any enemy model"""
	var enemy_player = 3 - owner
	for enemy_id in game_state_snapshot.units:
		var enemy = game_state_snapshot.units[enemy_id]
		if enemy.owner != enemy_player:
			continue

		# Skip embarked enemies
		if enemy.get("embarked_in", null) != null:
			continue

		for model in enemy.models:
			if not model.alive or model.position == null:
				continue

			var model_pos = Vector2(model.position.x, model.position.y)
			if Measurement.distance_inches(pos, model_pos) <= 1.0:
				return true

	return false

# Disembark action handlers

func _process_disembark_unit(action: Dictionary) -> Dictionary:
	"""Start the disembark process by showing dialog"""
	var unit_id = action.get("actor_unit_id", "")
	var unit = get_unit(unit_id)

	# Check if unit can disembark
	var validation = TransportManager.can_disembark(unit_id)
	if not validation.valid:
		return create_result(false, [], validation.reason)

	# Show disembark dialog
	call_deferred("_show_disembark_dialog", unit_id)

	log_phase_message("Starting disembark for %s" % unit.meta.get("name", unit_id))
	return create_result(true, [])

func _show_disembark_dialog(unit_id: String) -> void:
	"""Show disembark confirmation dialog"""
	var dialog = preload("res://scripts/DisembarkDialog.gd").new()
	dialog.setup(unit_id)
	dialog.disembark_confirmed.connect(_on_disembark_confirmed.bind(unit_id))
	dialog.disembark_cancelled.connect(_on_disembark_cancelled.bind(unit_id))
	get_tree().root.add_child(dialog)
	dialog.popup_centered()

func _on_disembark_confirmed(unit_id: String) -> void:
	"""Handle disembark confirmation - start placement"""
	var controller = preload("res://scripts/DisembarkController.gd").new()
	controller.disembark_completed.connect(_on_disembark_placement_completed)
	controller.disembark_cancelled.connect(_on_disembark_placement_cancelled)
	get_tree().root.add_child(controller)
	controller.start_disembark(unit_id)

func _on_disembark_cancelled(unit_id: String) -> void:
	"""Handle disembark cancellation"""
	log_phase_message("Disembark cancelled for %s" % get_unit(unit_id).meta.get("name", unit_id))

func _on_disembark_placement_completed(unit_id: String, positions: Array) -> void:
	"""Handle completed disembark placement"""
	# Use TransportManager to handle the disembark
	TransportManager.disembark_unit(unit_id, positions)

	var unit = get_unit(unit_id)
	log_phase_message("Unit %s disembarked" % unit.meta.get("name", unit_id))

	# Check if unit can move after disembark (if transport hasn't moved)
	var unit_refreshed = get_unit(unit_id)  # Get updated unit state
	if not unit_refreshed.get("flags", {}).get("cannot_move", false):
		# Unit can move - initialize movement for them
		call_deferred("_offer_movement_after_disembark", unit_id)

func _offer_movement_after_disembark(unit_id: String) -> void:
	"""Offer the option to move after disembark if transport hasn't moved"""
	var unit = get_unit(unit_id)

	# Check if unit can still move
	if unit.get("flags", {}).get("cannot_move", false):
		return  # Unit cannot move due to transport restrictions

	# Automatically initialize movement for the unit (no dialog needed)
	# The unit can move, so set up the movement state immediately
	log_phase_message("Unit %s can move after disembark" % unit.meta.get("name", unit_id))
	_initialize_movement_for_disembarked_unit(unit_id)

func _initialize_movement_for_disembarked_unit(unit_id: String) -> void:
	"""Initialize movement state for a unit that just disembarked"""
	log_phase_message("Initializing movement for disembarked unit: %s" % unit_id)
	var unit = get_unit(unit_id)
	var move_inches = get_unit_movement(unit)

	log_phase_message("Setting up active_moves for %s with %d\" movement" % [unit_id, move_inches])

	# Set up active movement similar to BEGIN_NORMAL_MOVE
	active_moves[unit_id] = {
		"mode": "NORMAL",
		"mode_locked": true,  # Lock to normal move since they just disembarked
		"completed": false,
		"move_cap_inches": move_inches,
		"advance_roll": 0,
		"model_moves": [],
		"staged_moves": [],
		"original_positions": {},
		"model_distances": {},
		"dice_rolls": [],
		"group_moves": [],
		"group_selection": [],
		"group_formation": {},
		"accumulated_distance": 0.0  # Track distance moved
	}

	# Store original positions for reset capability
	log_phase_message("Storing original positions for %s models" % unit_id)
	for i in range(unit.models.size()):
		var model = unit.models[i]
		if model.alive and model.position:
			var pos = Vector2(model.position.x, model.position.y)
			active_moves[unit_id]["original_positions"][model.id] = pos
			active_moves[unit_id]["model_distances"][model.id] = 0.0
			log_phase_message("  Model %s original position: %s" % [model.id, pos])

	# Apply movement capability state changes
	var changes = [
		{
			"op": "set",
			"path": "units.%s.flags.move_cap_inches" % unit_id,
			"value": move_inches
		}
	]

	# Apply through parent if it exists (PhaseManager)
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)

	# Update our local copy of the state
	var local_unit = game_state_snapshot.units[unit_id]
	if not local_unit.has("flags"):
		local_unit["flags"] = {}
	local_unit.flags["move_cap_inches"] = move_inches

	log_phase_message("Active moves successfully set up for %s. Total active moves: %s" % [unit_id, active_moves.keys()])

	emit_signal("unit_move_begun", unit_id, "NORMAL")
	log_phase_message("Movement initialized for disembarked unit %s (M: %d\")" % [unit.meta.get("name", unit_id), move_inches])

func _on_disembark_placement_cancelled(unit_id: String) -> void:
	"""Handle cancelled disembark placement"""
	log_phase_message("Disembark placement cancelled for %s" % get_unit(unit_id).meta.get("name", unit_id))

func _on_transport_manager_disembark_completed(unit_id: String) -> void:
	"""Handle disembark completion from TransportManager (via MovementController)"""
	log_phase_message("TransportManager reports disembark completed for %s" % unit_id)

	# IMPORTANT: Update our local snapshot to get the new positions after disembark
	# The TransportManager just updated GameState, so we need fresh data
	game_state_snapshot = GameState.state.duplicate(true)
	log_phase_message("Refreshed game state snapshot after disembark")

	# Check if the unit can move after disembark
	var unit = get_unit(unit_id)
	if unit and not unit.get("flags", {}).get("cannot_move", false):
		# Unit can move - initialize movement for them
		log_phase_message("Unit %s can move after disembark" % unit.meta.get("name", unit_id))
		_initialize_movement_for_disembarked_unit(unit_id)
	else:
		log_phase_message("Unit %s cannot move after disembark (transport moved)" % unit.meta.get("name", unit_id))

func _process_confirm_disembark(action: Dictionary) -> Dictionary:
	"""Process confirmation of disembark positions"""
	var unit_id = action.get("actor_unit_id", "")
	var positions = action.get("payload", {}).get("positions", [])

	# Validate positions
	var validation = _validate_confirm_disembark(action)
	if not validation.valid:
		return create_result(false, [], validation.errors[0])

	# Execute disembark
	TransportManager.disembark_unit(unit_id, positions)

	var unit = get_unit(unit_id)
	log_phase_message("Unit %s disembarked via action" % unit.meta.get("name", unit_id))

	return create_result(true, [])
