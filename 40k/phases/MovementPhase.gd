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
signal command_reroll_opportunity(unit_id: String, player: int, roll_context: Dictionary)
signal overwatch_opportunity(moved_unit_id: String, defending_player: int, eligible_units: Array)
signal overwatch_result(shooter_unit_id: String, target_unit_id: String, result: Dictionary)
signal fire_overwatch_opportunity(player: int, eligible_units: Array, enemy_unit_id: String)

const ENGAGEMENT_RANGE_INCHES: float = 1.0  # 10e standard ER
const MOVEMENT_CAP_EPSILON: float = 0.02  # Floating-point tolerance for movement cap checks (< 1px)

# Movement state tracking
var active_moves: Dictionary = {}  # unit_id -> move_data
var dice_log: Array = []
var _awaiting_reroll_decision: bool = false
var _reroll_pending_unit_id: String = ""
var _reroll_pending_data: Dictionary = {}  # Stores original roll info
var _awaiting_overwatch_decision: bool = false
var _overwatch_moved_unit_id: String = ""  # The unit that just moved (potential target)

# Fire Overwatch state tracking (T3-11)
var _awaiting_fire_overwatch: bool = false
var _fire_overwatch_player: int = 0           # Defending player being offered Overwatch
var _fire_overwatch_enemy_unit_id: String = "" # The enemy unit that triggered the opportunity
var _fire_overwatch_eligible_units: Array = [] # Units eligible for Overwatch

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
	_awaiting_reroll_decision = false
	_reroll_pending_unit_id = ""
	_reroll_pending_data = {}
	_awaiting_overwatch_decision = false
	_overwatch_moved_unit_id = ""
	_awaiting_fire_overwatch = false
	_fire_overwatch_player = 0
	_fire_overwatch_enemy_unit_id = ""
	_fire_overwatch_eligible_units = []

	# Connect to TransportManager to handle disembark completion
	if TransportManager and not TransportManager.disembark_completed.is_connected(_on_transport_manager_disembark_completed):
		TransportManager.disembark_completed.connect(_on_transport_manager_disembark_completed)

	# Movement phase continues with the current active player
	# Player switching only happens during scoring phase transitions

	# Apply unit ability eligibility effects (fall_back_and_charge, etc.)
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		ability_mgr.on_movement_phase_start()

	_initialize_movement()

func _on_phase_exit() -> void:
	log_phase_message("Exiting Movement Phase")

	# Clear unit ability eligibility flags
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		ability_mgr.on_movement_phase_end()

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
		"EMBARK_UNIT":
			return _validate_embark_unit(action)
		"PLACE_REINFORCEMENT":
			return _validate_place_reinforcement(action)
		"USE_COMMAND_REROLL":
			if not _awaiting_reroll_decision:
				return {"valid": false, "errors": ["Not awaiting a Command Re-roll decision"]}
			return {"valid": true}
		"DECLINE_COMMAND_REROLL":
			if not _awaiting_reroll_decision:
				return {"valid": false, "errors": ["Not awaiting a Command Re-roll decision"]}
			return {"valid": true}
		"USE_FIRE_OVERWATCH":
			return _validate_use_fire_overwatch(action)
		"DECLINE_FIRE_OVERWATCH":
			return _validate_decline_fire_overwatch(action)
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
		"EMBARK_UNIT":
			return _process_embark_unit(action)
		"PLACE_REINFORCEMENT":
			return _process_place_reinforcement(action)
		"USE_COMMAND_REROLL":
			return _process_use_command_reroll(action)
		"DECLINE_COMMAND_REROLL":
			return _process_decline_command_reroll(action)
		"USE_FIRE_OVERWATCH":
			return _process_use_fire_overwatch(action)
		"DECLINE_FIRE_OVERWATCH":
			return _process_decline_fire_overwatch(action)
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

	# Check if unit is attached to a bodyguard - cannot move independently
	if unit.get("attached_to", null) != null:
		return {"valid": false, "errors": ["Attached character moves with its bodyguard unit"]}

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
	# Add terrain elevation penalty: non-FLY units must count vertical distance for tall terrain
	# FLY units ignore terrain elevation entirely (penalty = 0)
	var terrain_penalty = _get_movement_terrain_penalty(current_pos, dest_vec, unit_id)
	var effective_distance = distance_inches + terrain_penalty
	if effective_distance > move_data.move_cap_inches:
		return {"valid": false, "errors": ["Move exceeds cap: %.1f\" > %.1f\"" % [effective_distance, move_data.move_cap_inches]]}

	# Check engagement range restrictions
	var er_check = _check_engagement_range_at_position(unit_id, model_id, dest_vec, move_data.mode)
	if not er_check.valid:
		return {"valid": false, "errors": er_check.errors}

	# 10e Rule: Normal Move and Advance cannot cross enemy model bases
	# FLY units are exempt — they can move over enemy models
	# Fall Back is also exempt (handled separately via Desperate Escape)
	if move_data.mode in ["NORMAL", "ADVANCE"] and not _unit_has_fly_keyword(unit_id):
		if _path_crosses_enemy_bases(current_pos, dest_vec, unit_id, model):
			log_phase_message("  FAILED: Path crosses enemy model base (Normal/Advance cannot move through enemies)")
			return {"valid": false, "errors": ["Cannot move through enemy models during Normal Move or Advance"]}

	# Check terrain collision
	if _position_intersects_terrain(dest_vec, model):
		return {"valid": false, "errors": ["Position intersects impassable terrain"]}

	# Check model overlap
	if _position_overlaps_other_models(unit_id, model_id, dest_vec, model):
		return {"valid": false, "errors": ["Cannot end move on top of another model"]}

	# Check board edge - no part of model base can extend beyond the battlefield
	if _position_outside_board_bounds(dest_vec, model):
		return {"valid": false, "errors": ["Model cannot be placed beyond the board edge"]}

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
	# Add terrain elevation penalty: non-FLY units must count vertical distance for tall terrain
	# FLY units ignore terrain elevation entirely (penalty = 0)
	var terrain_penalty = _get_movement_terrain_penalty(original_pos, dest_vec, unit_id)
	total_distance_for_model += terrain_penalty
	log_phase_message("  Distance calculation: %.2f inches (terrain penalty: %.2f\")" % [total_distance_for_model, terrain_penalty])

	# Check if this specific model's distance exceeds cap (with floating-point tolerance)
	if total_distance_for_model > move_data.move_cap_inches + MOVEMENT_CAP_EPSILON:
		log_phase_message("  FAILED: Distance %.1f\" exceeds cap %.1f\"" % [total_distance_for_model, move_data.move_cap_inches])
		return {"valid": false, "errors": ["Model %s would exceed movement cap: %.1f\" > %.1f\"" % [model_id, total_distance_for_model, move_data.move_cap_inches]]}
	
	# Check engagement range restrictions for the destination
	var er_check = _check_engagement_range_at_position(unit_id, model_id, dest_vec, move_data.mode)
	if not er_check.valid:
		return {"valid": false, "errors": er_check.errors}

	# 10e Rule: Normal Move and Advance cannot cross enemy model bases
	# FLY units are exempt — they can move over enemy models
	# Fall Back is also exempt (handled separately via Desperate Escape)
	if move_data.mode in ["NORMAL", "ADVANCE"] and not _unit_has_fly_keyword(unit_id):
		if _path_crosses_enemy_bases(current_pos, dest_vec, unit_id, model):
			log_phase_message("  FAILED: Path crosses enemy model base (Normal/Advance cannot move through enemies)")
			return {"valid": false, "errors": ["Cannot move through enemy models during Normal Move or Advance"]}

	# Check terrain collision
	if _position_intersects_terrain(dest_vec, model):
		return {"valid": false, "errors": ["Position intersects impassable terrain"]}

	# Check model overlap
	if _position_overlaps_other_models(unit_id, model_id, dest_vec, model):
		return {"valid": false, "errors": ["Cannot end move on top of another model"]}

	# Check board edge - no part of model base can extend beyond the battlefield
	if _position_outside_board_bounds(dest_vec, model):
		log_phase_message("  FAILED: Model would extend beyond board edge")
		return {"valid": false, "errors": ["Model cannot be placed beyond the board edge"]}

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

	# Check unit coherency after all staged moves are applied
	# Rule: Each model must be within 2" of at least one other model (2 others for 7+ model units)
	var coherency_result = _validate_unit_coherency_after_move(unit_id, move_data)
	if not coherency_result.valid:
		return {"valid": false, "errors": coherency_result.errors}

	return {"valid": true, "errors": []}

func _check_models_coherency(final_models: Array) -> Dictionary:
	"""Check unit coherency for an array of model dicts with positions.
	Each model must be within 2" of at least one other model (2 others for 7+ model units).
	Returns {valid: bool, errors: Array}."""
	if final_models.size() <= 1:
		return {"valid": true, "errors": []}

	var model_count = final_models.size()
	var required_connections = 1 if model_count <= 6 else 2

	for i in range(final_models.size()):
		var connections = 0
		for j in range(final_models.size()):
			if i == j:
				continue
			var distance = Measurement.model_to_model_distance_inches(final_models[i], final_models[j])
			if distance <= 2.0:
				connections += 1
				if connections >= required_connections:
					break  # No need to check further

		if connections < required_connections:
			var model_id = final_models[i].get("id", "model %d" % i)
			var needed_str = "%d model(s)" % required_connections
			log_phase_message("Coherency check failed: model %s has %d connections, needs %s" % [model_id, connections, needed_str])
			return {"valid": false, "errors": ["Unit coherency broken: model %s is not within 2\" of %s" % [model_id, needed_str]]}

	return {"valid": true, "errors": []}

func _validate_unit_coherency_after_move(unit_id: String, move_data: Dictionary) -> Dictionary:
	"""Validate that the unit maintains coherency after all staged moves are applied.
	Returns {valid: bool, errors: Array} — rejects the move if coherency is broken."""
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}

	var models = unit.get("models", [])
	var alive_models = []
	for model in models:
		if model.get("alive", true):
			alive_models.append(model)

	# Single model units are always coherent
	if alive_models.size() <= 1:
		return {"valid": true, "errors": []}

	# Build a map of model_id -> staged destination
	var staged_positions = {}
	for staged_move in move_data.get("staged_moves", []):
		staged_positions[staged_move.model_id] = staged_move.dest

	# Build final model dicts with their post-move positions
	var final_models = []
	for model in alive_models:
		var model_id = model.get("id", "")
		var final_model = model.duplicate()
		if staged_positions.has(model_id):
			final_model["position"] = staged_positions[model_id]
		final_models.append(final_model)

	return _check_models_coherency(final_models)

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

	# Check local active_moves for uncommitted staged/model moves
	for unit_id in active_moves:
		var move_data = active_moves[unit_id]
		# Check if unit has been marked as moved in GameState (synced across network)
		var unit = get_unit(unit_id)
		var has_moved = unit.get("flags", {}).get("moved", false)
		var unit_name = unit.get("meta", {}).get("name", unit_id)

		log_phase_message("Checking active_move for unit %s (%s)" % [unit_id, unit_name])
		log_phase_message("  - flags.moved: %s" % str(has_moved))
		log_phase_message("  - flags.movement_active: %s" % str(unit.get("flags", {}).get("movement_active", false)))
		log_phase_message("  - staged_moves: %d" % move_data.get("staged_moves", []).size())
		log_phase_message("  - model_moves: %d" % move_data.get("model_moves", []).size())
		log_phase_message("  - completed flag (local): %s" % str(move_data.get("completed", false)))

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

	# Also check synced GameState for any units with movement_active but not moved (T2-12)
	# This catches cases where the client's active_moves dict is out of sync with the host
	for unit_id in all_units:
		var unit = all_units[unit_id]
		if unit.get("flags", {}).get("movement_active", false) and not unit.get("flags", {}).get("moved", false):
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			log_phase_message("  → BLOCKING (via GameState): Unit %s (%s) has movement_active=true but moved=false" % [unit_id, unit_name])
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
		},
		{
			"op": "set",
			"path": "units.%s.flags.movement_active" % unit_id,
			"value": true
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
	var unit_name = unit.get("meta", {}).get("name", unit_id)

	log_phase_message("Advance: %s → D6 = %d" % [unit_name, advance_roll])

	# Check if Command Re-roll is available
	var current_player = get_current_player()
	var strat_manager = get_node_or_null("/root/StratagemManager")
	var reroll_available = false
	if strat_manager:
		var reroll_check = strat_manager.is_command_reroll_available(current_player)
		reroll_available = reroll_check.available

	if reroll_available:
		# Pause — store roll and offer Command Re-roll
		_awaiting_reroll_decision = true
		_reroll_pending_unit_id = unit_id
		_reroll_pending_data = {
			"advance_roll": advance_roll,
			"move_inches": move_inches,
			"unit_id": unit_id,
			"unit_name": unit_name,
		}

		var context_text = "Advance roll: %d (M %d\" + %d\" = %d\" total)" % [advance_roll, int(move_inches), advance_roll, int(move_inches + advance_roll)]
		var roll_context = {
			"roll_type": "advance_roll",
			"original_rolls": [advance_roll],
			"total": advance_roll,
			"unit_id": unit_id,
			"unit_name": unit_name,
			"context_text": context_text,
		}

		print("MovementPhase: Command Re-roll available for %s advance — pausing for decision" % unit_name)
		emit_signal("command_reroll_opportunity", unit_id, current_player, roll_context)

		return create_result(true, [], "", {
			"dice": [{"context": "advance", "n": 1, "rolls": [advance_roll]}],
			"awaiting_reroll": true,
		})

	# No reroll available — resolve immediately
	return _resolve_advance_roll(unit_id, advance_roll)

func _resolve_advance_roll(unit_id: String, advance_roll: int) -> Dictionary:
	"""Resolve an advance roll with the given die value."""
	var unit = get_unit(unit_id)
	var move_inches = get_unit_movement(unit)
	var total_move = move_inches + advance_roll
	var unit_name = unit.get("meta", {}).get("name", unit_id)

	active_moves[unit_id] = {
		"mode": "ADVANCE",
		"mode_locked": false,
		"completed": false,
		"move_cap_inches": total_move,
		"advance_roll": advance_roll,
		"model_moves": [],
		"staged_moves": [],
		"original_positions": {},
		"model_distances": {},
		"dice_rolls": [{"context": "advance", "rolls": [advance_roll]}],
		"group_moves": [],
		"group_selection": [],
		"group_formation": {}
	}

	dice_log.append({
		"unit_id": unit_id,
		"unit_name": unit_name,
		"type": "Advance",
		"roll": advance_roll,
		"result": "Move cap = %d\" (M %d\" + %d\")" % [total_move, int(move_inches), advance_roll]
	})

	emit_signal("unit_move_begun", unit_id, "ADVANCE")
	log_phase_message("Advance: %s → D6 = %d → Move cap = %d\"" % [unit_name, advance_roll, total_move])

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
		},
		{
			"op": "set",
			"path": "units.%s.flags.movement_active" % unit_id,
			"value": true
		}
	], "", {"dice": [{"context": "advance", "n": 1, "rolls": [advance_roll]}]})

func _process_use_command_reroll(action: Dictionary) -> Dictionary:
	"""Process USE_COMMAND_REROLL for advance roll."""
	var unit_id = _reroll_pending_unit_id
	var old_data = _reroll_pending_data.duplicate()
	_awaiting_reroll_decision = false
	_reroll_pending_unit_id = ""
	_reroll_pending_data = {}

	var unit_name = old_data.get("unit_name", unit_id)
	var old_roll = old_data.get("advance_roll", 0)
	var current_player = get_current_player()

	# Execute the stratagem (deduct CP, record usage)
	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager:
		var roll_context = {
			"roll_type": "advance_roll",
			"original_rolls": [old_roll],
			"unit_name": unit_name,
		}
		var strat_result = strat_manager.execute_command_reroll(current_player, unit_id, roll_context)
		if not strat_result.success:
			print("MovementPhase: Command Re-roll failed: %s" % strat_result.get("error", ""))
			return _resolve_advance_roll(unit_id, old_roll)

	# Re-roll D6
	var rng_service = RulesEngine.RNGService.new()
	var new_rolls = rng_service.roll_d6(1)
	var new_advance = new_rolls[0]

	log_phase_message("COMMAND RE-ROLL: Advance re-rolled from %d → %d" % [old_roll, new_advance])
	print("MovementPhase: COMMAND RE-ROLL — %s advance re-rolled: %d → %d" % [unit_name, old_roll, new_advance])

	return _resolve_advance_roll(unit_id, new_advance)

func _process_decline_command_reroll(action: Dictionary) -> Dictionary:
	"""Process DECLINE_COMMAND_REROLL for advance roll."""
	var unit_id = _reroll_pending_unit_id
	var old_data = _reroll_pending_data.duplicate()
	_awaiting_reroll_decision = false
	_reroll_pending_unit_id = ""
	_reroll_pending_data = {}

	print("MovementPhase: Command Re-roll DECLINED for %s — resolving with original roll" % unit_id)
	return _resolve_advance_roll(unit_id, old_data.get("advance_roll", 0))

# ============================================================================
# FIRE OVERWATCH (T3-11)
# ============================================================================

func _validate_use_fire_overwatch(action: Dictionary) -> Dictionary:
	var errors = []
	var unit_id = action.get("unit_id", "")
	var player = action.get("player", _fire_overwatch_player)

	if not _awaiting_fire_overwatch and not _awaiting_overwatch_decision:
		errors.append("Not awaiting Fire Overwatch decision")
		return {"valid": false, "errors": errors}

	if unit_id.is_empty():
		errors.append("No unit specified for Fire Overwatch")
		return {"valid": false, "errors": errors}

	# Validate through StratagemManager
	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager:
		var check = strat_manager.is_fire_overwatch_available(player)
		if not check.available:
			errors.append(check.reason)
			return {"valid": false, "errors": errors}

	# Validate the unit is eligible
	var unit = get_unit(unit_id)
	if unit.is_empty():
		errors.append("Unit not found: " + unit_id)
		return {"valid": false, "errors": errors}

	if int(unit.get("owner", 0)) != player:
		errors.append("Unit does not belong to player %d" % player)
		return {"valid": false, "errors": errors}

	# Check unit is not battle-shocked
	var flags = unit.get("flags", {})
	if flags.get("battle_shocked", false):
		errors.append("Battle-shocked units cannot use Stratagems")
		return {"valid": false, "errors": errors}

	return {"valid": true, "errors": []}

func _validate_decline_fire_overwatch(action: Dictionary) -> Dictionary:
	if not _awaiting_fire_overwatch and not _awaiting_overwatch_decision:
		return {"valid": false, "errors": ["Not awaiting Fire Overwatch decision"]}
	return {"valid": true, "errors": []}

func _process_use_fire_overwatch(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var player = action.get("player", _fire_overwatch_player)
	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
	var enemy_unit_id = _fire_overwatch_enemy_unit_id
	if enemy_unit_id.is_empty():
		enemy_unit_id = _overwatch_moved_unit_id
	var enemy_unit_name = get_unit(enemy_unit_id).get("meta", {}).get("name", enemy_unit_id)

	# Use the stratagem via StratagemManager (deducts CP, records usage)
	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager:
		var strat_result = strat_manager.use_stratagem(player, "fire_overwatch", unit_id)
		if not strat_result.success:
			return create_result(false, [], "Failed to use Fire Overwatch: %s" % strat_result.get("error", "unknown"))

	log_phase_message("Player %d uses FIRE OVERWATCH — %s shoots at moving %s!" % [player, unit_name, enemy_unit_name])
	print("MovementPhase: Fire Overwatch activated — %s (Player %d) shooting at %s" % [unit_name, player, enemy_unit_name])

	# Resolve Overwatch shooting using RulesEngine
	var ow_shooting_result = _resolve_overwatch_shooting(unit_id, enemy_unit_id, player)

	# Clear Overwatch state
	_awaiting_fire_overwatch = false
	_fire_overwatch_player = 0
	_fire_overwatch_enemy_unit_id = ""
	_fire_overwatch_eligible_units = []
	_awaiting_overwatch_decision = false
	_overwatch_moved_unit_id = ""

	emit_signal("overwatch_result", unit_id, enemy_unit_id, ow_shooting_result)

	var result = create_result(true, ow_shooting_result.get("diffs", []))
	result["fire_overwatch_used"] = true
	result["fire_overwatch_unit_id"] = unit_id
	result["fire_overwatch_target_id"] = enemy_unit_id
	result["fire_overwatch_shooting_result"] = ow_shooting_result
	if ow_shooting_result.has("dice"):
		result["dice"] = ow_shooting_result.dice
	if ow_shooting_result.has("log_text"):
		result["log_text"] = ow_shooting_result.log_text
	return result

func _process_decline_fire_overwatch(action: Dictionary) -> Dictionary:
	var player = action.get("player", _fire_overwatch_player)
	log_phase_message("Player %d declined FIRE OVERWATCH" % player)
	print("MovementPhase: Fire Overwatch DECLINED by Player %d" % player)

	# Clear Overwatch state
	_awaiting_fire_overwatch = false
	_fire_overwatch_player = 0
	_fire_overwatch_enemy_unit_id = ""
	_fire_overwatch_eligible_units = []
	_awaiting_overwatch_decision = false
	_overwatch_moved_unit_id = ""

	return create_result(true, [])

func _resolve_overwatch_shooting(shooting_unit_id: String, target_unit_id: String, player: int) -> Dictionary:
	"""
	Resolve Overwatch shooting. Uses the normal shooting resolution but forces
	all hit rolls to only succeed on unmodified 6s (per 10e Overwatch rules).
	"""
	var shooting_unit = get_unit(shooting_unit_id)
	var target_unit = get_unit(target_unit_id)

	if shooting_unit.is_empty() or target_unit.is_empty():
		return {"diffs": [], "dice": [], "log_text": "Overwatch: Invalid units"}

	# Build weapon assignments from all ranged weapons
	var assignments = []
	var weapons = shooting_unit.get("meta", {}).get("weapons", [])
	var alive_model_ids = []
	for model in shooting_unit.get("models", []):
		if model.get("alive", true):
			alive_model_ids.append(model.get("id", ""))

	for weapon in weapons:
		var weapon_type = weapon.get("type", "").to_lower()
		var weapon_range = weapon.get("range", "")
		var is_melee = weapon_type == "melee" or weapon_range == "Melee"
		if is_melee:
			continue

		# All alive models fire their ranged weapons
		assignments.append({
			"weapon_id": weapon.get("id", weapon.get("name", "")),
			"target_unit_id": target_unit_id,
			"model_ids": alive_model_ids,
			"overwatch": true,  # Flag for RulesEngine to use hit_on: 6
		})

	if assignments.is_empty():
		log_phase_message("Overwatch: %s has no ranged weapons to fire" % shooting_unit.get("meta", {}).get("name", shooting_unit_id))
		return {"diffs": [], "dice": [], "log_text": "No ranged weapons available for Overwatch"}

	# Build the shooting action for RulesEngine
	var shoot_action = {
		"actor_unit_id": shooting_unit_id,
		"payload": {
			"assignments": assignments,
			"overwatch": true,  # Global overwatch flag
		}
	}

	# Use RulesEngine.resolve_shoot for full resolution
	var board = game_state_snapshot
	var rng = RulesEngine.RNGService.new()
	var shoot_result = RulesEngine.resolve_shoot(shoot_action, board, rng)

	log_phase_message("FIRE OVERWATCH result: %s fired at %s — %s" % [
		shooting_unit.get("meta", {}).get("name", shooting_unit_id),
		target_unit.get("meta", {}).get("name", target_unit_id),
		shoot_result.get("log_text", "no hits")
	])

	return shoot_result


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
		},
		{
			"op": "set",
			"path": "units.%s.flags.movement_active" % unit_id,
			"value": true
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
	# Add terrain elevation penalty: non-FLY units must count vertical distance for tall terrain
	# FLY units ignore terrain elevation entirely (penalty = 0)
	var terrain_penalty = _get_movement_terrain_penalty(original_pos, dest_vec, unit_id)
	total_distance_for_model += terrain_penalty

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

	# Clear movement_active flag (synced across network)
	changes.append({
		"op": "remove",
		"path": "units.%s.flags.movement_active" % unit_id
	})
	# Also clear move_cap_inches since the move is being reset
	changes.append({
		"op": "remove",
		"path": "units.%s.flags.move_cap_inches" % unit_id
	})
	# Clear fell_back flag if it was set during BEGIN_FALL_BACK
	if move_data.mode == "FALL_BACK":
		changes.append({
			"op": "remove",
			"path": "units.%s.flags.fell_back" % unit_id
		})
	# Clear advanced flag if it was set during BEGIN_ADVANCE
	if move_data.mode == "ADVANCE":
		changes.append({
			"op": "remove",
			"path": "units.%s.flags.advanced" % unit_id
		})

	# Remove from local tracking
	active_moves.erase(unit_id)

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

	# Move attached character models with the bodyguard unit
	var _unit = get_unit(unit_id)
	var attached_chars = _unit.get("attachment_data", {}).get("attached_characters", [])
	if attached_chars.size() > 0:
		changes.append_array(_move_attached_characters(unit_id, attached_chars))

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

	# Clear movement_active flag (synced across network)
	changes.append({
		"op": "remove",
		"path": "units.%s.flags.movement_active" % unit_id
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

	# T3-11: Check for Fire Overwatch opportunity for the defending player
	# Per 10e rules: The defending player may use Fire Overwatch (1CP) when an enemy
	# unit starts or ends a Normal, Advance, or Fall Back move within 24" of an eligible unit
	var moving_owner = int(unit.get("owner", 0))
	var defending_player = 2 if moving_owner == 1 else 1

	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager:
		var ow_check = strat_manager.is_fire_overwatch_available(defending_player)
		if ow_check.available:
			# Build a temporary snapshot with the new positions applied
			var temp_snapshot = game_state_snapshot.duplicate(true)
			for change in changes:
				if change.get("op", "") == "set":
					var path_parts = change.path.split(".")
					if path_parts.size() >= 4 and path_parts[0] == "units" and path_parts[2] == "models":
						var u_id = path_parts[1]
						var m_idx = int(path_parts[3])
						var field = path_parts[4] if path_parts.size() > 4 else ""
						if field == "position" and temp_snapshot.get("units", {}).has(u_id):
							var models = temp_snapshot.units[u_id].get("models", [])
							if m_idx < models.size():
								models[m_idx]["position"] = change.value

			var ow_eligible = strat_manager.get_fire_overwatch_eligible_units(
				defending_player, unit_id, temp_snapshot
			)

			if not ow_eligible.is_empty():
				# Fire Overwatch is available! Pause and offer it to the defender
				_awaiting_fire_overwatch = true
				_awaiting_overwatch_decision = true
				_overwatch_moved_unit_id = unit_id
				_fire_overwatch_player = defending_player
				_fire_overwatch_enemy_unit_id = unit_id
				_fire_overwatch_eligible_units = ow_eligible
				log_phase_message("FIRE OVERWATCH available for Player %d (%d eligible units) against moving %s" % [defending_player, ow_eligible.size(), unit_name])
				print("MovementPhase: Fire Overwatch opportunity — Player %d has %d eligible units" % [defending_player, ow_eligible.size()])

				emit_signal("fire_overwatch_opportunity", defending_player, ow_eligible, unit_id)
				emit_signal("overwatch_opportunity", unit_id, defending_player, ow_eligible)

				var result = create_result(true, changes, "", {"dice": additional_dice})
				result["trigger_fire_overwatch"] = true
				result["awaiting_overwatch"] = true
				result["fire_overwatch_player"] = defending_player
				result["fire_overwatch_eligible_units"] = ow_eligible
				result["fire_overwatch_enemy_unit_id"] = unit_id
				return result

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

func _validate_place_reinforcement(action: Dictionary) -> Dictionary:
	"""Validate placing a reserve unit onto the battlefield during the Reinforcements step"""
	var errors = []

	var required_fields = ["unit_id", "model_positions"]
	for field in required_fields:
		if not action.has(field):
			errors.append("Missing required field: " + field)

	if errors.size() > 0:
		return {"valid": false, "errors": errors}

	var unit_id = action.unit_id
	var model_positions = action.model_positions

	# Check if unit exists and is in reserves
	var unit = get_unit(unit_id)
	if unit.is_empty():
		errors.append("Unit not found: " + unit_id)
		return {"valid": false, "errors": errors}

	if unit.get("status", 0) != GameStateData.UnitStatus.IN_RESERVES:
		errors.append("Unit is not in reserves: " + unit_id)
		return {"valid": false, "errors": errors}

	# Check unit belongs to active player
	var active_player = get_current_player()
	if unit.get("owner", 0) != active_player:
		errors.append("Unit does not belong to active player")
		return {"valid": false, "errors": errors}

	# Check battle round - reserves can only arrive from Turn 2 onwards
	var battle_round = GameState.get_battle_round()
	if battle_round < 2:
		errors.append("Reserves cannot arrive until Battle Round 2 (currently Round %d)" % battle_round)
		return {"valid": false, "errors": errors}

	var reserve_type = unit.get("reserve_type", "strategic_reserves")

	# Validate model positions
	if model_positions is Array:
		var board_width = GameState.state.board.size.width  # 44 inches
		var board_height = GameState.state.board.size.height  # 60 inches
		var px_per_inch = 40.0

		for i in range(model_positions.size()):
			var pos = model_positions[i]
			if pos == null:
				continue

			var pos_inches_x = pos.x / px_per_inch
			var pos_inches_y = pos.y / px_per_inch

			# All reinforcements must be on the board
			if pos_inches_x < 0 or pos_inches_x > board_width or pos_inches_y < 0 or pos_inches_y > board_height:
				errors.append("Model %d: position is off the board" % i)
				continue

			# Must be >9" from all enemy models (edge-to-edge)
			var model_data = unit.get("models", [])[i] if i < unit.get("models", []).size() else {}
			var model_base_mm = model_data.get("base_mm", 32)
			var model_radius_inches = (model_base_mm / 2.0) / 25.4  # mm to inches

			var enemy_positions = GameState.get_enemy_model_positions(active_player)
			for enemy in enemy_positions:
				var enemy_pos_px = Vector2(enemy.x, enemy.y)
				var enemy_radius_inches = (enemy.base_mm / 2.0) / 25.4
				var dist_px = pos.distance_to(enemy_pos_px)
				var dist_inches = dist_px / px_per_inch
				# Edge-to-edge distance: center distance minus both radii
				var edge_dist = dist_inches - model_radius_inches - enemy_radius_inches
				if edge_dist < 9.0:
					errors.append("Model %d: must be >9\" from enemy models (currently %.1f\")" % [i, edge_dist])
					break

			# Strategic Reserves: must be within 6" of a battlefield edge
			if reserve_type == "strategic_reserves":
				var dist_to_left = pos_inches_x
				var dist_to_right = board_width - pos_inches_x
				var dist_to_top = pos_inches_y
				var dist_to_bottom = board_height - pos_inches_y
				var min_edge_dist = min(dist_to_left, dist_to_right, dist_to_top, dist_to_bottom)

				if min_edge_dist > 6.0:
					errors.append("Model %d: Strategic Reserves must be within 6\" of a battlefield edge (nearest edge: %.1f\")" % [i, min_edge_dist])

				# Turn 2: cannot be in opponent's deployment zone
				if battle_round == 2:
					var opponent = 3 - active_player
					var opponent_zone = GameState.get_deployment_zone_for_player(opponent)
					var zone_poly = opponent_zone.get("poly", [])
					if _point_in_deployment_zone(pos_inches_x, pos_inches_y, zone_poly):
						errors.append("Model %d: Strategic Reserves cannot arrive in opponent's deployment zone during Turn 2" % i)

			# Deep Strike: can be placed anywhere on the board (>9" check already done above)
			# No additional restrictions for deep strike placement

	# Check unit coherency: reinforcement models must maintain 2" coherency
	if errors.is_empty():
		var final_models = []
		var unit_models = unit.get("models", [])
		for i in range(model_positions.size()):
			if model_positions[i] == null:
				continue
			if i >= unit_models.size():
				break
			if not unit_models[i].get("alive", true):
				continue
			var model_at_pos = unit_models[i].duplicate()
			model_at_pos["position"] = model_positions[i]
			final_models.append(model_at_pos)

		var coherency_result = _check_models_coherency(final_models)
		if not coherency_result.valid:
			errors.append_array(coherency_result.errors)

	return {"valid": errors.size() == 0, "errors": errors}

func _point_in_deployment_zone(x_inches: float, y_inches: float, zone_poly: Array) -> bool:
	"""Check if a point (in inches) is within a deployment zone polygon"""
	if zone_poly.is_empty():
		return false
	var packed = PackedVector2Array()
	for coord in zone_poly:
		if coord is Dictionary and coord.has("x") and coord.has("y"):
			packed.append(Vector2(coord.x, coord.y))
	return Geometry2D.is_point_in_polygon(Vector2(x_inches, y_inches), packed)

func _process_place_reinforcement(action: Dictionary) -> Dictionary:
	"""Process placing a reserve unit onto the battlefield"""
	var unit_id = action.unit_id
	var model_positions = action.model_positions
	var model_rotations = action.get("model_rotations", [])
	var changes = []

	# Update model positions
	for i in range(model_positions.size()):
		var pos = model_positions[i]
		if pos != null:
			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.position" % [unit_id, i],
				"value": {"x": pos.x, "y": pos.y}
			})
			if i < model_rotations.size() and model_rotations[i] != null:
				changes.append({
					"op": "set",
					"path": "units.%s.models.%d.rotation" % [unit_id, i],
					"value": model_rotations[i]
				})

	# Update unit status from IN_RESERVES to DEPLOYED
	changes.append({
		"op": "set",
		"path": "units.%s.status" % unit_id,
		"value": GameStateData.UnitStatus.DEPLOYED
	})

	# Apply changes through PhaseManager
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)

	# Update local snapshot
	if game_state_snapshot.has("units") and game_state_snapshot.units.has(unit_id):
		game_state_snapshot.units[unit_id]["status"] = GameStateData.UnitStatus.DEPLOYED

	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var reserve_type = unit.get("reserve_type", "strategic_reserves")
	var type_label = "Deep Strike" if reserve_type == "deep_strike" else "Strategic Reserves"
	log_phase_message("Reinforcement arrived: %s via %s" % [unit_name, type_label])

	return create_result(true, changes)

func _process_end_movement(action: Dictionary) -> Dictionary:
	log_phase_message("=== PROCESSING END_MOVEMENT ===")

	# Clean up any stale movement_active flags (safety net for T2-12)
	var changes = []
	var current_player = get_current_player()
	var all_units = get_units_for_player(current_player)
	for unit_id in all_units:
		var unit = all_units[unit_id]
		if unit.get("flags", {}).get("movement_active", false):
			log_phase_message("Cleaning up stale movement_active flag for unit %s" % unit_id)
			changes.append({
				"op": "remove",
				"path": "units.%s.flags.movement_active" % unit_id
			})

	log_phase_message("Ending Movement Phase - emitting phase_completed signal")
	emit_signal("phase_completed")
	log_phase_message("=== END_MOVEMENT COMPLETE ===")
	return create_result(true, changes)

func _process_desperate_escape(unit_id: String, move_data: Dictionary) -> Dictionary:
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])
	var changes = []
	var dice_rolls = []

	# FLY and TITANIC units skip Desperate Escape tests when Falling Back
	# 10e Rule: FLY units can move over enemy models without taking Desperate Escape tests
	# 10e Rule: TITANIC models do not take Desperate Escape tests when Falling Back
	var keywords = unit.get("meta", {}).get("keywords", [])
	if "FLY" in keywords or "TITANIC" in keywords:
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var skip_reason = "FLY" if "FLY" in keywords else "TITANIC"
		log_phase_message("Desperate Escape skipped for %s (%s keyword)" % [unit_name, skip_reason])
		return {"changes": [], "dice": []}

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

## T3-9: Get the effective engagement range between two model positions,
## accounting for barricade terrain (2" instead of 1" if barricade is between them).
func _get_effective_engagement_range(pos1: Vector2, pos2: Vector2) -> float:
	if not is_inside_tree():
		return ENGAGEMENT_RANGE_INCHES
	var terrain_manager = get_node_or_null("/root/TerrainManager")
	if terrain_manager and terrain_manager.has_method("get_engagement_range_for_positions"):
		return terrain_manager.get_engagement_range_for_positions(pos1, pos2)
	return ENGAGEMENT_RANGE_INCHES

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
				# T3-9: Use barricade-aware engagement range (2" through barricades)
				var effective_er = _get_effective_engagement_range(pos, enemy_pos)
				if Measurement.is_in_engagement_range_shape_aware(model_at_pos, enemy_model, effective_er):
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

func _unit_has_fly_keyword(unit_id: String) -> bool:
	# Check if the unit has the FLY keyword in its metadata
	var units = game_state_snapshot.get("units", {})
	var unit = units.get(unit_id, {})
	var keywords = unit.get("meta", {}).get("keywords", [])
	return "FLY" in keywords

func _get_movement_terrain_penalty(from_pos: Vector2, to_pos: Vector2, unit_id: String) -> float:
	# Calculate terrain elevation penalty for movement.
	# FLY units ignore terrain elevation entirely (return 0).
	# Non-FLY units must count vertical distance (climb up + down) for terrain >2".
	var terrain_manager = get_node_or_null("/root/TerrainManager")
	if not terrain_manager or not terrain_manager.has_method("calculate_movement_terrain_penalty"):
		return 0.0
	var has_fly = _unit_has_fly_keyword(unit_id)
	var penalty = terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, has_fly)
	if penalty > 0.0:
		log_phase_message("  Terrain elevation penalty: %.1f\" (FLY=%s)" % [penalty, has_fly])
	return penalty

func _path_crosses_enemy_bases(from: Vector2, to: Vector2, unit_id: String, model: Dictionary) -> bool:
	# Check if a movement path crosses any enemy model bases using shape-aware overlap.
	# 10e Rule: A model cannot move through enemy models during Normal Move or Advance.
	# Only Fall Back and FLY units may move through enemy models.
	# This checks base-to-base overlap only — moving *near* enemies is fine,
	# moving *through* their bases is not.
	var current_player = get_current_player()
	var units = game_state_snapshot.get("units", {})

	# Build a reference model for path sampling
	var reference_model = model.duplicate()

	# Sample points along the path (approximately every 10 pixels for good coverage)
	var path_length = from.distance_to(to)
	var num_samples = max(2, int(path_length / 10.0))

	for i in range(num_samples + 1):
		var t = float(i) / float(num_samples)
		var sample_pos = from.lerp(to, t)

		# Create a temporary model at this position
		var model_at_pos = reference_model.duplicate()
		model_at_pos["position"] = sample_pos

		# Check against all enemy models only (friendly models can be crossed freely)
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
					# Only check base overlap — moving close to enemies is allowed,
					# only moving through their bases is illegal
					if Measurement.models_overlap(model_at_pos, enemy_model):
						return true

	return false

func _path_crosses_enemy(from: Vector2, to: Vector2, unit_id: String, base_mm: int) -> bool:
	# Legacy wrapper for Fall Back path checking (keeps crosses_enemy tracking for Desperate Escape)
	# Fall Back moves are allowed to cross enemies, so this is used for tracking, not blocking
	var units = game_state_snapshot.get("units", {})
	var unit = units.get(unit_id, {})
	var reference_model = null
	for m in unit.get("models", []):
		if m.get("alive", true):
			reference_model = m.duplicate()
			break
	if reference_model == null:
		return false
	return _path_crosses_enemy_bases(from, to, unit_id, reference_model)

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

func _position_outside_board_bounds(pos: Vector2, model: Dictionary) -> bool:
	# Check if any part of the model's base would extend beyond the board edges
	# Rule: No part of a model (including its base) can cross the edge of the battlefield
	var board_size = game_state_snapshot.get("board", {}).get("size", {})
	var board_width_inches = board_size.get("width", 44.0)
	var board_height_inches = board_size.get("height", 60.0)
	var board_width_px = Measurement.inches_to_px(board_width_inches)
	var board_height_px = Measurement.inches_to_px(board_height_inches)

	# Get the model's base radius in pixels
	var base_shape = Measurement.create_base_shape(model)
	var bounds = base_shape.get_bounds()
	var half_width = bounds.size.x / 2.0
	var half_height = bounds.size.y / 2.0

	# Check if any edge of the base extends beyond the board
	if pos.x - half_width < 0 or pos.x + half_width > board_width_px:
		return true
	if pos.y - half_height < 0 or pos.y + half_height > board_height_px:
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

	# Add reinforcement actions for units in reserves (from Turn 2 onwards)
	var battle_round = GameState.get_battle_round()
	if battle_round >= 2:
		var reserves = GameState.get_reserves_for_player(current_player)
		for reserve_unit_id in reserves:
			var reserve_unit = get_unit(reserve_unit_id)
			var reserve_name = reserve_unit.get("meta", {}).get("name", reserve_unit_id)
			var reserve_type = reserve_unit.get("reserve_type", "strategic_reserves")
			var type_label = "Deep Strike" if reserve_type == "deep_strike" else "Reserves"
			actions.append({
				"type": "PLACE_REINFORCEMENT",
				"unit_id": reserve_unit_id,
				"description": "Arrive from %s: %s" % [type_label, reserve_name]
			})

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
	
	# Add active move actions (skip completed moves)
	# Use synced GameState flags.moved to determine completion for multiplayer compatibility
	for unit_id in active_moves:
		var unit_check = get_unit(unit_id)
		if unit_check.get("flags", {}).get("moved", false):
			continue
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
	# Check using synced GameState flags for multiplayer compatibility (T2-12 fix)
	var has_incomplete_moves = false
	log_phase_message("[get_available_actions] Checking if END_MOVEMENT should be available...")
	log_phase_message("[get_available_actions] Active moves (local): %s" % str(active_moves.keys()))

	# Check local active_moves against synced GameState
	for unit_id in active_moves:
		var unit = get_unit(unit_id)
		var has_moved = unit.get("flags", {}).get("moved", false)
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		log_phase_message("[get_available_actions]   Unit %s (%s): flags.moved = %s" % [unit_id, unit_name, str(has_moved)])
		if not has_moved:
			has_incomplete_moves = true
			log_phase_message("[get_available_actions]   → This unit has incomplete moves!")
			break

	# Also check GameState for any units with movement_active flag set
	# This catches cases where the client's active_moves is out of sync (T2-12)
	if not has_incomplete_moves:
		var all_units = get_units_for_player(current_player)
		for unit_id in all_units:
			var unit = all_units[unit_id]
			if unit.get("flags", {}).get("movement_active", false) and not unit.get("flags", {}).get("moved", false):
				has_incomplete_moves = true
				var unit_name = unit.get("meta", {}).get("name", unit_id)
				log_phase_message("[get_available_actions]   → GameState flags show %s (%s) has active movement!" % [unit_id, unit_name])
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

func _check_active_moves_sync() -> void:
	# T2-12: Debug consistency check between local active_moves and synced GameState
	# Call this periodically or after action processing to detect desync
	for unit_id in active_moves:
		var unit = get_unit(unit_id)
		var local_completed = active_moves[unit_id].get("completed", false)
		var synced_moved = unit.get("flags", {}).get("moved", false)
		var synced_active = unit.get("flags", {}).get("movement_active", false)

		# If local says completed but GameState says not moved, we have a desync
		if local_completed and not synced_moved:
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			log_phase_message("WARNING: MULTIPLAYER DESYNC DETECTED for %s (%s) - local completed=%s, GameState moved=%s" % [unit_id, unit_name, local_completed, synced_moved])

		# If local has active move but GameState doesn't show movement_active
		if not local_completed and not synced_active and not synced_moved:
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			log_phase_message("WARNING: MULTIPLAYER DESYNC DETECTED for %s (%s) - local has active move but GameState movement_active=%s" % [unit_id, unit_name, synced_active])

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
		# Add terrain elevation penalty: non-FLY units must count vertical distance for tall terrain
		# FLY units ignore terrain elevation entirely (penalty = 0)
		total_distance += _get_movement_terrain_penalty(original_pos, new_pos, unit_id)
		group_validation.individual_distances[model_id] = total_distance

		# Validate against movement cap (with floating-point tolerance)
		if total_distance > move_cap_inches + MOVEMENT_CAP_EPSILON:
			group_validation.valid = false
			group_validation.errors.append("Model %s exceeds movement cap (%.1f\" > %.1f\")" % [model_id, total_distance, move_cap_inches])

		# Check for terrain collisions
		var full_model = _get_model_in_unit(unit_id, model_id)
		if not full_model.is_empty() and _check_terrain_collision(new_pos, full_model):
			group_validation.valid = false
			group_validation.errors.append("Model %s would collide with terrain" % model_id)

		# Check for model overlaps
		if _would_overlap_other_models(unit_id, model_id, new_pos, model_data):
			group_validation.valid = false
			group_validation.errors.append("Model %s would overlap with another model" % model_id)

		# 10e Rule: Normal Move and Advance cannot cross enemy model bases
		# FLY units are exempt — they can move over enemy models
		if move_data.mode in ["NORMAL", "ADVANCE"] and not _unit_has_fly_keyword(unit_id):
			if not full_model.is_empty() and _path_crosses_enemy_bases(model_data.position, new_pos, unit_id, full_model):
				group_validation.valid = false
				group_validation.errors.append("Model %s path crosses enemy model base" % model_id)

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
	# Add terrain elevation penalty: non-FLY units must count vertical distance for tall terrain
	# FLY units ignore terrain elevation entirely (penalty = 0)
	total_distance += _get_movement_terrain_penalty(original_pos, dest_pos, unit_id)

	if total_distance > move_data.move_cap_inches:
		return false

	# Check terrain collision
	if _check_terrain_collision(dest_pos, model):
		return false

	# Check model overlap
	if _would_overlap_other_models(unit_id, model_id, dest_pos, model):
		return false

	# 10e Rule: Normal Move and Advance cannot cross enemy model bases
	if move_data.mode in ["NORMAL", "ADVANCE"] and not _unit_has_fly_keyword(unit_id):
		var current_pos = _get_model_position(model)
		if current_pos and _path_crosses_enemy_bases(current_pos, dest_pos, unit_id, model):
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

func _check_terrain_collision(position: Vector2, model: Dictionary) -> bool:
	"""Check if a position collides with impassable terrain using shape-aware bounds"""
	return _position_intersects_terrain(position, model)

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
	# Skip embark prompts for AI players — AI doesn't use UI dialogs
	var ai_player = get_node_or_null("/root/AIPlayer")
	if ai_player and ai_player.is_ai_player(get_current_player()):
		return

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
	"""Show dialog asking if player wants to embark unit.
	On confirm, routes through the action system via NetworkIntegration
	so the embark is validated and synchronized across all clients."""
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
		# Route through action system for network synchronization
		var action = {
			"type": "EMBARK_UNIT",
			"actor_unit_id": unit_id,
			"payload": {
				"transport_id": transport_id
			}
		}
		var result = NetworkIntegration.route_action(action)
		if not result.get("success", false) and not result.get("pending", false):
			log_phase_message("Embark action failed: %s" % str(result.get("errors", result.get("error", "unknown"))))
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

		# Check board edge - no part of model base can extend beyond the battlefield
		if _position_outside_board_bounds(pos if pos is Vector2 else Vector2(pos.x, pos.y), model_at_pos):
			return {"valid": false, "errors": ["Cannot disembark beyond the board edge"]}

	# Check unit coherency: disembarked models must maintain 2" coherency
	var final_models = []
	for i in range(positions.size()):
		if i >= unit.models.size():
			break
		if not unit.models[i].get("alive", true):
			continue
		var model_at_pos = unit.models[i].duplicate()
		model_at_pos["position"] = positions[i]
		final_models.append(model_at_pos)

	var coherency_result = _check_models_coherency(final_models)
	if not coherency_result.valid:
		return {"valid": false, "errors": coherency_result.errors}

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

			# T3-9: Use barricade-aware engagement range (2" through barricades)
			var model_pos = model_data.get("position", Vector2.ZERO)
			if model_pos is Dictionary:
				model_pos = Vector2(model_pos.get("x", 0), model_pos.get("y", 0))
			var enemy_pos = model.get("position", Vector2.ZERO)
			if enemy_pos is Dictionary:
				enemy_pos = Vector2(enemy_pos.get("x", 0), enemy_pos.get("y", 0))
			var effective_er = _get_effective_engagement_range(model_pos, enemy_pos)
			if Measurement.is_in_engagement_range_shape_aware(model_data, model, effective_er):
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
	dialog.disembark_canceled.connect(_on_disembark_canceled.bind(unit_id))
	get_tree().root.add_child(dialog)
	dialog.popup_centered()

func _on_disembark_confirmed(unit_id: String) -> void:
	"""Handle disembark confirmation - start placement"""
	var controller = preload("res://scripts/DisembarkController.gd").new()
	controller.disembark_completed.connect(_on_disembark_placement_completed)
	controller.disembark_canceled.connect(_on_disembark_placement_canceled)
	get_tree().root.add_child(controller)
	controller.start_disembark(unit_id)

func _on_disembark_canceled(unit_id: String) -> void:
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
		},
		{
			"op": "set",
			"path": "units.%s.flags.movement_active" % unit_id,
			"value": true
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
	local_unit.flags["movement_active"] = true

	log_phase_message("Active moves successfully set up for %s. Total active moves: %s" % [unit_id, active_moves.keys()])

	emit_signal("unit_move_begun", unit_id, "NORMAL")
	log_phase_message("Movement initialized for disembarked unit %s (M: %d\")" % [unit.meta.get("name", unit_id), move_inches])

func _on_disembark_placement_canceled(unit_id: String) -> void:
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

# Embark action handlers

func _validate_embark_unit(action: Dictionary) -> Dictionary:
	"""Validate that a unit can embark into a transport during the movement phase"""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}

	var transport_id = action.get("payload", {}).get("transport_id", "")
	if transport_id == "":
		return {"valid": false, "errors": ["Missing transport_id in payload"]}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found: " + unit_id]}

	# Unit must belong to the current player
	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}

	# Unit must have moved this phase (embark happens after movement)
	if not unit.get("flags", {}).get("moved", false):
		return {"valid": false, "errors": ["Unit must complete movement before embarking"]}

	# Units that disembarked this phase cannot re-embark
	if unit.get("disembarked_this_phase", false):
		return {"valid": false, "errors": ["Unit disembarked this phase and cannot re-embark"]}

	# Delegate capacity/keyword checks to TransportManager
	var can_embark = TransportManager.can_embark(unit_id, transport_id)
	if not can_embark.valid:
		return {"valid": false, "errors": [can_embark.reason]}

	return {"valid": true, "errors": []}

func _process_embark_unit(action: Dictionary) -> Dictionary:
	"""Process embarking a unit into a transport via the action system"""
	var unit_id = action.get("actor_unit_id", "")
	var transport_id = action.get("payload", {}).get("transport_id", "")

	var unit = get_unit(unit_id)
	var transport = get_unit(transport_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var transport_name = transport.get("meta", {}).get("name", transport_id)

	# Build state changes following the same pattern as DeploymentPhase embark
	var changes = []

	# Set the unit's embarked_in field
	changes.append({
		"op": "set",
		"path": "units.%s.embarked_in" % unit_id,
		"value": transport_id
	})

	# Update transport's embarked_units list
	var current_embarked = transport.get("transport_data", {}).get("embarked_units", []).duplicate()
	if unit_id not in current_embarked:
		current_embarked.append(unit_id)
	changes.append({
		"op": "set",
		"path": "units.%s.transport_data.embarked_units" % transport_id,
		"value": current_embarked
	})

	log_phase_message("Unit %s embarked in transport %s" % [unit_name, transport_name])

	return create_result(true, changes)

func _move_attached_characters(bodyguard_id: String, attached_char_ids: Array) -> Array:
	"""Move attached character models to maintain formation with bodyguard.
	Calculates delta from the bodyguard's first model move and applies to character models."""
	var changes = []
	var bodyguard = get_unit(bodyguard_id)
	if bodyguard.is_empty():
		return changes

	# Calculate movement delta from first bodyguard model
	var bg_models = bodyguard.get("models", [])
	var move_delta = Vector2.ZERO
	var found_delta = false

	# Find the movement delta from the active_moves data
	if active_moves.has(bodyguard_id):
		var move_data = active_moves[bodyguard_id]
		for model_move in move_data.model_moves:
			var from_pos = model_move.get("from", null)
			var to_pos = model_move.get("dest", null)
			if from_pos != null and to_pos != null:
				var from_vec = Vector2(from_pos.x if from_pos is Vector2 else from_pos.get("x", 0), from_pos.y if from_pos is Vector2 else from_pos.get("y", 0))
				var to_vec = Vector2(to_pos.x if to_pos is Vector2 else to_pos.get("x", 0), to_pos.y if to_pos is Vector2 else to_pos.get("y", 0))
				move_delta = to_vec - from_vec
				found_delta = true
				break

	if not found_delta:
		print("[MovementPhase] WARNING: Could not determine move delta for attached characters of %s" % bodyguard_id)
		return changes

	print("[MovementPhase] Moving attached characters with delta: %s" % str(move_delta))

	for char_id in attached_char_ids:
		var char_unit = get_unit(char_id)
		if char_unit.is_empty():
			continue

		var char_models = char_unit.get("models", [])
		for i in range(char_models.size()):
			var model = char_models[i]
			var model_pos = model.get("position", null)
			if model_pos == null:
				continue

			var pos_x = model_pos.get("x", 0) if model_pos is Dictionary else model_pos.x
			var pos_y = model_pos.get("y", 0) if model_pos is Dictionary else model_pos.y
			var new_pos = Vector2(pos_x + move_delta.x, pos_y + move_delta.y)

			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.position" % [char_id, i],
				"value": {"x": new_pos.x, "y": new_pos.y}
			})

		# Also set character unit flags to match bodyguard
		changes.append({
			"op": "set",
			"path": "units.%s.flags.moved" % char_id,
			"value": true
		})

		var char_name = char_unit.get("meta", {}).get("name", char_id)
		print("[MovementPhase] Moved attached character %s with bodyguard %s" % [char_name, bodyguard_id])

	return changes
