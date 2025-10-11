extends BasePhase
class_name ChargePhase

# ChargePhase - Full implementation of the Charge phase following 10e rules
# Supports: Charge declarations, 2D6 charge rolls, movement validation, engagement range

signal unit_selected_for_charge(unit_id: String)
signal targets_declared(unit_id: String, target_ids: Array)
signal charge_targets_available(unit_id: String, eligible_targets: Dictionary)
signal charge_roll_made(unit_id: String, distance: int, dice: Array)
signal charge_path_preview(unit_id: String, per_model_paths: Dictionary)
signal charge_path_tools_enabled(unit_id: String, rolled_distance: int)
signal charge_validation_feedback(unit_id: String, validation_result: Dictionary)
signal charge_resolved(unit_id: String, success: bool, result: Dictionary)
signal dice_rolled(dice_data: Dictionary)

const ENGAGEMENT_RANGE_INCHES: float = 1.0  # 10e standard ER
const CHARGE_RANGE_INCHES: float = 12.0     # Maximum charge declaration range

# Charge state tracking
var active_charges: Dictionary = {}     # unit_id -> charge_data
var pending_charges: Dictionary = {}    # units awaiting resolution  
var dice_log: Array = []
var units_that_charged: Array = []     # Track which units have completed charges
var current_charging_unit = null       # Track which unit is actively charging
var completed_charges: Array = []      # Units that finished charging this phase

func _init():
	phase_type = GameStateData.Phase.CHARGE

func _on_phase_enter() -> void:
	log_phase_message("Entering Charge Phase")
	active_charges.clear()
	pending_charges.clear() 
	dice_log.clear()
	units_that_charged.clear()
	current_charging_unit = null
	completed_charges.clear()
	
	_initialize_charge()

func _on_phase_exit() -> void:
	log_phase_message("Exiting Charge Phase")
	# Clear charge flags
	_clear_phase_flags()

func _initialize_charge() -> void:
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	var can_charge = false
	for unit_id in units:
		var unit = units[unit_id]
		if _can_unit_charge(unit):
			can_charge = true
			break
	
	if not can_charge:
		log_phase_message("No units available for charging, completing phase")
		emit_signal("phase_completed")

func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")
	
	match action_type:
		"SELECT_CHARGE_UNIT":
			return _validate_select_charge_unit(action)
		"DECLARE_CHARGE":
			return _validate_declare_charge(action)
		"CHARGE_ROLL":
			return _validate_charge_roll(action)
		"APPLY_CHARGE_MOVE":
			return _validate_apply_charge_move(action)
		"COMPLETE_UNIT_CHARGE":
			return _validate_complete_unit_charge(action)
		"SKIP_CHARGE":
			return _validate_skip_charge(action)
		"END_CHARGE":
			return _validate_end_charge(action)
		_:
			return {"valid": false, "errors": ["Unknown action type: " + action_type]}

func process_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	match action_type:
		"SELECT_CHARGE_UNIT":
			return _process_select_charge_unit(action)
		"DECLARE_CHARGE":
			return _process_declare_charge(action)
		"CHARGE_ROLL":
			return _process_charge_roll(action)
		"APPLY_CHARGE_MOVE":
			return _process_apply_charge_move(action)
		"COMPLETE_UNIT_CHARGE":
			return _process_complete_unit_charge(action)
		"SKIP_CHARGE":
			return _process_skip_charge(action)
		"END_CHARGE":
			return _process_end_charge(action)
		_:
			return create_result(false, [], "Unknown action type: " + action_type)

# Validation Methods

func _validate_select_charge_unit(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}
	
	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}
	
	if not _can_unit_charge(unit):
		return {"valid": false, "errors": ["Unit cannot charge"]}
	
	if unit_id in completed_charges:
		return {"valid": false, "errors": ["Unit has already charged this phase"]}
	
	return {"valid": true, "errors": []}

func _validate_complete_unit_charge(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	if unit_id != current_charging_unit:
		return {"valid": false, "errors": ["Unit is not currently charging"]}
	
	return {"valid": true, "errors": []}

func _validate_declare_charge(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var target_ids = action.get("payload", {}).get("target_unit_ids", [])
	
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	if target_ids.is_empty():
		return {"valid": false, "errors": ["Missing target_unit_ids"]}
	
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}
	
	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}
	
	if not _can_unit_charge(unit):
		return {"valid": false, "errors": ["Unit cannot charge"]}
	
	if unit_id in completed_charges:
		return {"valid": false, "errors": ["Unit has already charged this phase"]}
	
	# Validate each target
	for target_id in target_ids:
		var target_unit = get_unit(target_id)
		if target_unit.is_empty():
			return {"valid": false, "errors": ["Target unit not found: " + target_id]}
		
		if target_unit.get("owner", 0) == get_current_player():
			return {"valid": false, "errors": ["Cannot charge own units"]}
		
		# Check 12" range
		if not _is_target_within_charge_range(unit_id, target_id):
			return {"valid": false, "errors": ["Target beyond 12\" charge range: " + target_id]}
	
	return {"valid": true, "errors": []}

func _validate_charge_roll(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	if not pending_charges.has(unit_id):
		return {"valid": false, "errors": ["No charge declared for unit"]}
	
	return {"valid": true, "errors": []}

func _validate_apply_charge_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var payload = action.get("payload", {})
	var per_model_paths = payload.get("per_model_paths", {})
	
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	if per_model_paths.is_empty():
		return {"valid": false, "errors": ["Missing per_model_paths"]}
	
	if not pending_charges.has(unit_id):
		return {"valid": false, "errors": ["No charge roll made for unit"]}
	
	var charge_data = pending_charges[unit_id]
	if not charge_data.has("distance"):
		return {"valid": false, "errors": ["No charge distance available"]}
	
	# Validate all movement constraints
	var validation = _validate_charge_movement_constraints(unit_id, per_model_paths, charge_data)
	return validation

func _validate_skip_charge(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}
	
	if unit_id in completed_charges:
		return {"valid": false, "errors": ["Unit has already acted this phase"]}
	
	return {"valid": true, "errors": []}

func _validate_end_charge(action: Dictionary) -> Dictionary:
	# Can always end the phase
	return {"valid": true, "errors": []}

# Processing Methods

func _process_select_charge_unit(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	
	current_charging_unit = unit_id
	
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("Selected %s for charging" % unit_name)
	
	emit_signal("unit_selected_for_charge", unit_id)
	
	return create_result(true, [])

func _process_complete_unit_charge(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	
	completed_charges.append(unit_id)
	current_charging_unit = null
	
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("Completed charge sequence for %s" % unit_name)
	
	# Don't end phase - allow selection of next unit
	return create_result(true, [])

func _process_declare_charge(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var target_ids = action.get("payload", {}).get("target_unit_ids", [])
	
	# Store charge declaration
	pending_charges[unit_id] = {
		"targets": target_ids,
		"declared_at": Time.get_unix_time_from_system()
	}
	
	# Get eligible targets for UI
	var eligible_targets = _get_eligible_targets_for_unit(unit_id)
	
	emit_signal("unit_selected_for_charge", unit_id)
	emit_signal("targets_declared", unit_id, target_ids)
	emit_signal("charge_targets_available", unit_id, eligible_targets)
	
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var target_names = []
	for target_id in target_ids:
		var target = get_unit(target_id)
		target_names.append(target.get("meta", {}).get("name", target_id))
	
	log_phase_message("%s declared charge against %s" % [unit_name, ", ".join(target_names)])
	
	return create_result(true, [])

func _process_charge_roll(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var charge_data = pending_charges[unit_id]
	
	# Roll 2D6 for charge distance
	var rng = RulesEngine.RNGService.new()
	var rolls = rng.roll_d6(2)
	var total_distance = rolls[0] + rolls[1]
	
	# Store rolled distance
	charge_data.distance = total_distance
	charge_data.dice_rolls = rolls
	
	# Add to dice log
	var dice_result = {
		"context": "charge_roll",
		"unit_id": unit_id,
		"unit_name": get_unit(unit_id).get("meta", {}).get("name", unit_id),
		"rolls": rolls,
		"total": total_distance
	}
	dice_log.append(dice_result)
	
	emit_signal("charge_roll_made", unit_id, total_distance, rolls)
	emit_signal("charge_path_tools_enabled", unit_id, total_distance)
	emit_signal("dice_rolled", dice_result)
	
	log_phase_message("Charge roll: 2D6 = %d (%d + %d)" % [total_distance, rolls[0], rolls[1]])
	
	return create_result(true, [], "", {"dice": [dice_result]})

func _process_apply_charge_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var payload = action.get("payload", {})
	var per_model_paths = payload.get("per_model_paths", {})
	var per_model_rotations = payload.get("per_model_rotations", {})

	# Enhanced validation - check for empty per_model_paths
	if per_model_paths.is_empty():
		print("ERROR: No model paths provided for charge movement")
		return create_result(false, [], "No model paths provided")

	if not pending_charges.has(unit_id):
		print("ERROR: No pending charge data found for unit ", unit_id)
		return create_result(false, [], "No pending charge data found")

	var charge_data = pending_charges[unit_id]

	# Final validation
	var validation = _validate_charge_movement_constraints(unit_id, per_model_paths, charge_data)
	if not validation.valid:
		# Charge fails - no movement applied
		var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
		log_phase_message("Charge failed for %s: %s" % [unit_name, validation.errors[0]])
		
		# Mark as charged (attempted) but unsuccessful
		units_that_charged.append(unit_id)
		pending_charges.erase(unit_id)
		
		emit_signal("charge_resolved", unit_id, false, {"reason": validation.errors[0]})
		return create_result(true, [])
	
	# Apply successful charge movement
	var changes = []

	# Update model positions
	for model_id in per_model_paths:
		var path = per_model_paths[model_id]

		if not (path is Array and path.size() > 0):
			print("WARNING: Invalid path for model ", model_id, " - skipping")
			continue

		var final_pos = path[-1]  # Last position in path
		var model_index = _get_model_index(unit_id, model_id)

		if model_index < 0:
			print("ERROR: Invalid model_index for ", model_id, " - model not found in unit")
			continue

		var change = {
			"op": "set",
			"path": "units.%s.models.%d.position" % [unit_id, model_index],
			"value": {"x": final_pos[0], "y": final_pos[1]}
		}
		changes.append(change)

		# Also apply rotation if provided
		if per_model_rotations.has(model_id):
			var rotation = per_model_rotations[model_id]
			var rotation_change = {
				"op": "set",
				"path": "units.%s.models.%d.rotation" % [unit_id, model_index],
				"value": rotation
			}
			changes.append(rotation_change)
	
	# Mark unit as charged and grant Fights First
	changes.append({
		"op": "set",
		"path": "units.%s.flags.charged_this_turn" % unit_id,
		"value": true
	})
	changes.append({
		"op": "set",
		"path": "units.%s.flags.fights_first" % unit_id,
		"value": true
	})
	
	# Clean up charge state
	units_that_charged.append(unit_id)
	pending_charges.erase(unit_id)
	# Don't mark as completed yet - wait for COMPLETE_UNIT_CHARGE action
	
	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
	log_phase_message("Successful charge: %s moved into engagement range" % unit_name)

	emit_signal("charge_resolved", unit_id, true, {"distance": charge_data.distance})

	return create_result(true, changes)

func _process_skip_charge(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	
	units_that_charged.append(unit_id)
	completed_charges.append(unit_id)
	current_charging_unit = null
	
	# Clear any pending charge for this unit
	if pending_charges.has(unit_id):
		pending_charges.erase(unit_id)
	
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("Skipped charge for %s" % unit_name)
	
	return create_result(true, [])

func _process_end_charge(action: Dictionary) -> Dictionary:
	log_phase_message("Ending Charge Phase")
	emit_signal("phase_completed")
	return create_result(true, [])

# Helper Methods

func _can_unit_charge(unit: Dictionary) -> bool:
	var status = unit.get("status", 0)
	var flags = unit.get("flags", {})
	
	# Check if unit is deployed
	if not (status == GameStateData.UnitStatus.DEPLOYED or 
			status == GameStateData.UnitStatus.MOVED or 
			status == GameStateData.UnitStatus.SHOT):
		return false
	
	# Check restriction flags
	if flags.get("cannot_charge", false):
		return false
	
	if flags.get("advanced", false):
		return false
	
	if flags.get("fell_back", false):
		return false
	
	if flags.get("charged_this_turn", false):
		return false
	
	# Check if already in engagement range (cannot declare charges)
	if _is_unit_in_engagement_range(unit):
		return false
	
	# Check if unit has any alive models
	var has_alive = false
	for model in unit.get("models", []):
		if model.get("alive", true):
			has_alive = true
			break
	
	return has_alive

func _is_unit_in_engagement_range(unit: Dictionary) -> bool:
	var unit_id = unit.get("id", "")
	var models = unit.get("models", [])
	var current_player = get_current_player()
	var all_units = game_state_snapshot.get("units", {})
	
	for model in models:
		if not model.get("alive", true):
			continue
		
		var model_pos = _get_model_position(model)
		if model_pos == null:
			continue
		
		var model_radius = Measurement.base_radius_px(model.get("base_mm", 32))
		var er_px = Measurement.inches_to_px(ENGAGEMENT_RANGE_INCHES)
		
		# Check against all enemy models
		for enemy_unit_id in all_units:
			var enemy_unit = all_units[enemy_unit_id]
			if enemy_unit.get("owner", 0) == current_player:
				continue  # Skip friendly units
			
			for enemy_model in enemy_unit.get("models", []):
				if not enemy_model.get("alive", true):
					continue
				
				var enemy_pos = _get_model_position(enemy_model)
				if enemy_pos == null:
					continue
				
				var enemy_radius = Measurement.base_radius_px(enemy_model.get("base_mm", 32))
				var edge_distance = model_pos.distance_to(enemy_pos) - model_radius - enemy_radius
				
				if edge_distance <= er_px:
					return true
	
	return false

func _is_target_within_charge_range(unit_id: String, target_id: String) -> bool:
	var unit = get_unit(unit_id)
	var target = get_unit(target_id)
	
	if unit.is_empty() or target.is_empty():
		return false
	
	# Find closest edge-to-edge distance between any models
	var min_distance = INF
	
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		
		var model_pos = _get_model_position(model)
		if model_pos == null:
			continue
		
		var model_radius = Measurement.base_radius_px(model.get("base_mm", 32))
		
		for target_model in target.get("models", []):
			if not target_model.get("alive", true):
				continue
			
			var target_pos = _get_model_position(target_model)
			if target_pos == null:
				continue
			
			var target_radius = Measurement.base_radius_px(target_model.get("base_mm", 32))
			var edge_distance = Measurement.edge_to_edge_distance_px(model_pos, model_radius, target_pos, target_radius)
			var distance_inches = Measurement.px_to_inches(edge_distance)
			
			min_distance = min(min_distance, distance_inches)
	
	return min_distance <= CHARGE_RANGE_INCHES

func _get_eligible_targets_for_unit(unit_id: String) -> Dictionary:
	var eligible = {}
	var current_player = get_current_player()
	var all_units = game_state_snapshot.get("units", {})
	
	for target_id in all_units:
		var target_unit = all_units[target_id]
		if target_unit.get("owner", 0) != current_player:  # Enemy unit
			if _is_target_within_charge_range(unit_id, target_id):
				eligible[target_id] = {
					"name": target_unit.get("meta", {}).get("name", target_id),
					"distance": _get_min_distance_to_target(unit_id, target_id)
				}
	
	return eligible

func _get_min_distance_to_target(unit_id: String, target_id: String) -> float:
	var unit = get_unit(unit_id)
	var target = get_unit(target_id)
	var min_distance = INF
	
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		
		var model_pos = _get_model_position(model)
		if model_pos == null:
			continue
		
		for target_model in target.get("models", []):
			if not target_model.get("alive", true):
				continue
			
			var target_pos = _get_model_position(target_model)
			if target_pos == null:
				continue
			
			var distance = Measurement.distance_inches(model_pos, target_pos)
			min_distance = min(min_distance, distance)
	
	return min_distance

func _validate_charge_movement_constraints(unit_id: String, per_model_paths: Dictionary, charge_data: Dictionary) -> Dictionary:
	var errors = []
	var rolled_distance = charge_data.distance
	var target_ids = charge_data.targets

	# 1. Validate path distances
	for model_id in per_model_paths:
		var path = per_model_paths[model_id]
		if path is Array and path.size() >= 2:
			var path_distance = Measurement.distance_polyline_inches(path)
			if path_distance > rolled_distance:
				errors.append("Model %s path exceeds charge distance: %.1f\" > %d\"" % [model_id, path_distance, rolled_distance])

	# 2. Validate no model overlaps
	var overlap_validation = _validate_no_model_overlaps(unit_id, per_model_paths)
	if not overlap_validation.valid:
		errors.append_array(overlap_validation.errors)

	# 3. Validate engagement range with ALL targets
	var engagement_validation = _validate_engagement_range_constraints(unit_id, per_model_paths, target_ids)
	if not engagement_validation.valid:
		errors.append_array(engagement_validation.errors)

	# 4. Validate unit coherency
	var coherency_validation = _validate_unit_coherency_for_charge(unit_id, per_model_paths)
	if not coherency_validation.valid:
		errors.append_array(coherency_validation.errors)

	# 5. Validate base-to-base if possible
	var base_to_base_validation = _validate_base_to_base_possible(unit_id, per_model_paths, target_ids)
	if not base_to_base_validation.valid:
		errors.append_array(base_to_base_validation.errors)

	return {"valid": errors.is_empty(), "errors": errors}

func _validate_engagement_range_constraints(unit_id: String, per_model_paths: Dictionary, target_ids: Array) -> Dictionary:
	var errors = []
	var er_px = Measurement.inches_to_px(ENGAGEMENT_RANGE_INCHES)
	var current_player = get_current_player()
	var all_units = game_state_snapshot.get("units", {})
	
	# Check that unit ends within ER of ALL targets
	for target_id in target_ids:
		var target_unit = all_units.get(target_id, {})
		if target_unit.is_empty():
			continue
		
		var unit_in_er_of_target = false
		
		for model_id in per_model_paths:
			var path = per_model_paths[model_id]
			if path is Array and path.size() > 0:
				var final_pos = Vector2(path[-1][0], path[-1][1])
				var model = _get_model_in_unit(unit_id, model_id)
				var model_radius = Measurement.base_radius_px(model.get("base_mm", 32))
				
				# Check if this model is in ER of any target model
				for target_model in target_unit.get("models", []):
					if not target_model.get("alive", true):
						continue
					
					var target_pos = _get_model_position(target_model)
					if target_pos == null:
						continue
					
					var target_radius = Measurement.base_radius_px(target_model.get("base_mm", 32))
					var edge_distance = final_pos.distance_to(target_pos) - model_radius - target_radius
					
					if edge_distance <= er_px:
						unit_in_er_of_target = true
						break
				
				if unit_in_er_of_target:
					break
		
		if not unit_in_er_of_target:
			var target_name = target_unit.get("meta", {}).get("name", target_id)
			errors.append("Must end within engagement range of all targets: " + target_name)
	
	# Check that unit does NOT end in ER of non-target enemies
	for enemy_unit_id in all_units:
		var enemy_unit = all_units[enemy_unit_id]
		if enemy_unit.get("owner", 0) == current_player:
			continue  # Skip friendly
		
		if enemy_unit_id in target_ids:
			continue  # Skip declared targets
		
		# Check if any charging model ends in ER of this non-target
		for model_id in per_model_paths:
			var path = per_model_paths[model_id]
			if path is Array and path.size() > 0:
				var final_pos = Vector2(path[-1][0], path[-1][1])
				var model = _get_model_in_unit(unit_id, model_id)
				var model_radius = Measurement.base_radius_px(model.get("base_mm", 32))
				
				for enemy_model in enemy_unit.get("models", []):
					if not enemy_model.get("alive", true):
						continue
					
					var enemy_pos = _get_model_position(enemy_model)
					if enemy_pos == null:
						continue
					
					var enemy_radius = Measurement.base_radius_px(enemy_model.get("base_mm", 32))
					var edge_distance = final_pos.distance_to(enemy_pos) - model_radius - enemy_radius
					
					if edge_distance <= er_px:
						var enemy_name = enemy_unit.get("meta", {}).get("name", enemy_unit_id)
						errors.append("Cannot end within engagement range of non-target unit: " + enemy_name)
						break
	
	return {"valid": errors.is_empty(), "errors": errors}

func _validate_unit_coherency_for_charge(unit_id: String, per_model_paths: Dictionary) -> Dictionary:
	var errors = []
	var coherency_distance = 2.0  # 2" coherency in 10e
	var coherency_px = Measurement.inches_to_px(coherency_distance)
	
	var final_positions = []
	
	# Get final positions for all models
	for model_id in per_model_paths:
		var path = per_model_paths[model_id]
		if path is Array and path.size() > 0:
			final_positions.append(Vector2(path[-1][0], path[-1][1]))
	
	if final_positions.size() < 2:
		return {"valid": true, "errors": []}  # Single model or no movement
	
	# Check that each model is within 2" of at least one other model
	for i in range(final_positions.size()):
		var pos = final_positions[i]
		var has_nearby_model = false
		
		for j in range(final_positions.size()):
			if i == j:
				continue
			
			var other_pos = final_positions[j]
			var distance = pos.distance_to(other_pos)
			
			if distance <= coherency_px:
				has_nearby_model = true
				break
		
		if not has_nearby_model:
			errors.append("Unit coherency broken: model %d too far from other models" % i)
	
	return {"valid": errors.is_empty(), "errors": errors}

func _validate_base_to_base_possible(unit_id: String, per_model_paths: Dictionary, target_ids: Array) -> Dictionary:
	# For MVP, we'll implement a simplified check
	# In full implementation, this would check if base-to-base contact is achievable
	# and required when all other constraints are satisfied
	return {"valid": true, "errors": []}

func _get_model_position(model: Dictionary) -> Vector2:
	var pos = model.get("position")
	if pos == null:
		return Vector2.ZERO
	if pos is Dictionary:
		return Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO

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

func _clear_phase_flags() -> void:
	var units = game_state_snapshot.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.has("flags"):
			unit.flags.erase("charged_this_turn")
			unit.flags.erase("fights_first")

func get_available_actions() -> Array:
	var actions = []
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	# Units that can declare charges
	for unit_id in units:
		var unit = units[unit_id]
		if _can_unit_charge(unit) and unit_id not in completed_charges:
			
			# If no charge declared, can declare charge
			if not pending_charges.has(unit_id):
				var eligible_targets = _get_eligible_targets_for_unit(unit_id)
				for target_id in eligible_targets:
					actions.append({
						"type": "DECLARE_CHARGE",
						"actor_unit_id": unit_id,
						"payload": {"target_unit_ids": [target_id]},
						"description": "Declare charge: %s -> %s" % [unit.get("meta", {}).get("name", unit_id), eligible_targets[target_id].name]
					})
				
				# Skip charge option
				actions.append({
					"type": "SKIP_CHARGE",
					"actor_unit_id": unit_id,
					"description": "Skip charge for " + unit.get("meta", {}).get("name", unit_id)
				})
			
			# If charge declared but no roll made, can roll
			elif pending_charges.has(unit_id) and not pending_charges[unit_id].has("distance"):
				actions.append({
					"type": "CHARGE_ROLL",
					"actor_unit_id": unit_id,
					"description": "Roll 2D6 for charge distance"
				})
			
			# If roll made, can apply movement (handled by UI typically)
	
	# Always can end phase
	actions.append({
		"type": "END_CHARGE",
		"description": "End Charge Phase"
	})
	
	return actions

func _should_complete_phase() -> bool:
	# Check if all eligible units have charged or been skipped
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	for unit_id in units:
		var unit = units[unit_id]
		if _can_unit_charge(unit) and unit_id not in completed_charges:
			return false
	
	return true

func get_dice_log() -> Array:
	return dice_log

func _validate_no_model_overlaps(unit_id: String, per_model_paths: Dictionary) -> Dictionary:
	var errors = []
	var all_units = game_state_snapshot.get("units", {})

	# Get all models from the charging unit
	var unit = all_units.get(unit_id, {})
	var models = unit.get("models", [])

	# Check each model's final position
	for model_id in per_model_paths:
		var path = per_model_paths[model_id]
		if not (path is Array and path.size() > 0):
			continue

		var final_pos = Vector2(path[-1][0], path[-1][1])
		var model = _get_model_in_unit(unit_id, model_id)
		if model.is_empty():
			continue

		# Build model dict with final position
		var check_model = model.duplicate()
		check_model["position"] = final_pos

		# Check against all other models (both friendly and enemy)
		for check_unit_id in all_units:
			var check_unit = all_units[check_unit_id]
			var check_models = check_unit.get("models", [])

			for i in range(check_models.size()):
				var other_model = check_models[i]
				var other_model_id = other_model.get("id", "m%d" % (i+1))

				# Skip self
				if check_unit_id == unit_id and other_model_id == model_id:
					continue

				# Skip dead models
				if not other_model.get("alive", true):
					continue

				# Get the current position of the other model
				# For other charging models in same unit, use their final positions
				var other_position = _get_model_position(other_model)
				if check_unit_id == unit_id and per_model_paths.has(other_model_id):
					var other_path = per_model_paths[other_model_id]
					if other_path is Array and other_path.size() > 0:
						other_position = Vector2(other_path[-1][0], other_path[-1][1])

				if other_position == null:
					continue

				# Build other model dict with correct position
				var other_model_check = other_model.duplicate()
				other_model_check["position"] = other_position

				# Check for overlap
				if Measurement.models_overlap(check_model, other_model_check):
					errors.append("Model %s would overlap with %s/%s" % [model_id, check_unit_id, other_model_id])

	return {"valid": errors.is_empty(), "errors": errors}

func get_pending_charges() -> Dictionary:
	return pending_charges

func get_units_that_charged() -> Array:
	return units_that_charged

func get_eligible_charge_units() -> Array:
	var eligible = []
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	for unit_id in units:
		var unit = units[unit_id]
		if _can_unit_charge(unit) and unit_id not in completed_charges:
			eligible.append(unit_id)
	
	return eligible

func get_completed_charges() -> Array:
	return completed_charges

func has_pending_charge(unit_id: String) -> bool:
	return pending_charges.has(unit_id)

func get_charge_distance(unit_id: String) -> int:
	if pending_charges.has(unit_id) and pending_charges[unit_id].has("distance"):
		return pending_charges[unit_id].distance
	return 0

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