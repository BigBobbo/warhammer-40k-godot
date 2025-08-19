extends BasePhase
class_name ChargePhase

# ChargePhase - Stub implementation for the Charge phase
# This is a placeholder that can be expanded with full charge mechanics

func _init():
	phase_type = GameStateData.Phase.CHARGE

func _on_phase_enter() -> void:
	log_phase_message("Entering Charge Phase")
	
	# Initialize charge phase state
	_initialize_charge()

func _on_phase_exit() -> void:
	log_phase_message("Exiting Charge Phase")

func _initialize_charge() -> void:
	# Check if there are any units that can charge
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	var can_charge = false
	for unit_id in units:
		var unit = units[unit_id]
		var status = unit.get("status", 0)
		var fallen_back = unit.get("fallen_back", false)
		
		# Units that fell back generally cannot charge
		if (status == GameStateData.UnitStatus.DEPLOYED or status == GameStateData.UnitStatus.MOVED or status == GameStateData.UnitStatus.SHOT) and not fallen_back:
			can_charge = true
			break
	
	if not can_charge:
		log_phase_message("No units available for charging, completing phase")
		emit_signal("phase_completed")

func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")
	
	match action_type:
		"DECLARE_CHARGE":
			return _validate_declare_charge_action(action)
		"CHARGE_MOVE":
			return _validate_charge_move_action(action)
		"SKIP_CHARGE":
			return _validate_skip_charge_action(action)
		_:
			return {"valid": false, "errors": ["Unknown action type: " + action_type]}

func _validate_declare_charge_action(action: Dictionary) -> Dictionary:
	var errors = []
	
	# Check required fields
	var required_fields = ["unit_id", "target_unit_id"]
	for field in required_fields:
		if not action.has(field):
			errors.append("Missing required field: " + field)
	
	if errors.size() > 0:
		return {"valid": false, "errors": errors}
	
	var unit_id = action.unit_id
	var target_unit_id = action.target_unit_id
	
	var unit = get_unit(unit_id)
	var target_unit = get_unit(target_unit_id)
	
	# Check if units exist
	if unit.is_empty():
		errors.append("Charging unit not found: " + unit_id)
	if target_unit.is_empty():
		errors.append("Target unit not found: " + target_unit_id)
	
	if errors.size() > 0:
		return {"valid": false, "errors": errors}
	
	# Check if unit belongs to active player
	if unit.get("owner", 0) != get_current_player():
		errors.append("Unit does not belong to active player")
	
	# Check if target belongs to enemy player
	if target_unit.get("owner", 0) == get_current_player():
		errors.append("Cannot charge own units")
	
	# Check if unit can charge
	var fallen_back = unit.get("fallen_back", false)
	if fallen_back:
		errors.append("Unit cannot charge after falling back")
	
	# TODO: Add detailed charge validation
	# - Check charge range (typically 12")
	# - Check line of sight
	# - Check if unit is already in combat
	# - Check terrain between charger and target
	
	return {"valid": errors.size() == 0, "errors": errors}

func _validate_charge_move_action(action: Dictionary) -> Dictionary:
	var errors = []
	
	# Check required fields
	var required_fields = ["unit_id", "charge_roll", "final_positions"]
	for field in required_fields:
		if not action.has(field):
			errors.append("Missing required field: " + field)
	
	if errors.size() > 0:
		return {"valid": false, "errors": errors}
	
	var unit_id = action.unit_id
	var charge_roll = action.charge_roll
	var final_positions = action.final_positions
	
	var unit = get_unit(unit_id)
	if unit.is_empty():
		errors.append("Unit not found: " + unit_id)
		return {"valid": false, "errors": errors}
	
	# Check if unit has declared a charge
	var charge_declared = unit.get("charge_declared", false)
	if not charge_declared:
		errors.append("Unit has not declared a charge")
	
	# TODO: Add detailed charge move validation
	# - Validate charge roll result
	# - Check if charge distance is sufficient
	# - Check final positions are within engagement range
	# - Validate charge path (shortest route, terrain effects)
	
	return {"valid": errors.size() == 0, "errors": errors}

func _validate_skip_charge_action(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing unit_id"]}
	
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}
	
	return {"valid": true, "errors": []}

func process_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")
	
	match action_type:
		"DECLARE_CHARGE":
			return _process_declare_charge(action)
		"CHARGE_MOVE":
			return _process_charge_move(action)
		"SKIP_CHARGE":
			return _process_skip_charge(action)
		_:
			return create_result(false, [], "Unknown action type: " + action_type)

func _process_declare_charge(action: Dictionary) -> Dictionary:
	var unit_id = action.unit_id
	var target_unit_id = action.target_unit_id
	var changes = []
	
	# Mark unit as having declared a charge
	changes.append({
		"op": "set",
		"path": "units.%s.charge_declared" % unit_id,
		"value": true
	})
	
	# Record the charge target
	changes.append({
		"op": "set",
		"path": "units.%s.charge_target" % unit_id,
		"value": target_unit_id
	})
	
	# Apply changes through PhaseManager
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)
	
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("%s declared charge against %s" % [unit_name, target_unit_id])
	
	return create_result(true, changes)

func _process_charge_move(action: Dictionary) -> Dictionary:
	var unit_id = action.unit_id
	var charge_roll = action.charge_roll
	var final_positions = action.final_positions
	var changes = []
	
	# Update model positions
	for i in range(final_positions.size()):
		var pos = final_positions[i]
		if pos != null:
			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.position" % [unit_id, i],
				"value": {"x": pos.x, "y": pos.y}
			})
	
	# Mark unit as charged
	changes.append({
		"op": "set",
		"path": "units.%s.status" % unit_id,
		"value": GameStateData.UnitStatus.CHARGED
	})
	
	# Record charge roll
	changes.append({
		"op": "set",
		"path": "units.%s.charge_roll" % unit_id,
		"value": charge_roll
	})
	
	# Apply changes through PhaseManager
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)
	
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("%s completed charge (rolled %d)" % [unit_name, charge_roll])
	
	return create_result(true, changes)

func _process_skip_charge(action: Dictionary) -> Dictionary:
	var unit_id = action.unit_id
	log_phase_message("Skipped charge for %s" % unit_id)
	return create_result(true, [])

func get_available_actions() -> Array:
	var actions = []
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	# Get enemy units as potential targets
	var enemy_player = 3 - current_player  # Switch between 1 and 2
	var enemy_units = get_units_for_player(enemy_player)
	
	for unit_id in units:
		var unit = units[unit_id]
		var status = unit.get("status", 0)
		var fallen_back = unit.get("fallen_back", false)
		var charge_declared = unit.get("charge_declared", false)
		
		# Check if unit can charge
		if (status == GameStateData.UnitStatus.DEPLOYED or status == GameStateData.UnitStatus.MOVED or status == GameStateData.UnitStatus.SHOT) and not fallen_back:
			
			if not charge_declared:
				# Add charge declaration actions for each potential target
				for target_unit_id in enemy_units:
					actions.append({
						"type": "DECLARE_CHARGE",
						"unit_id": unit_id,
						"target_unit_id": target_unit_id,
						"description": "Declare charge: %s -> %s" % [unit.get("meta", {}).get("name", unit_id), target_unit_id]
					})
				
				# Skip charge option
				actions.append({
					"type": "SKIP_CHARGE",
					"unit_id": unit_id,
					"description": "Skip charge for " + unit.get("meta", {}).get("name", unit_id)
				})
			else:
				# Unit has declared charge, can now make charge move
				actions.append({
					"type": "CHARGE_MOVE",
					"unit_id": unit_id,
					"description": "Make charge move for " + unit.get("meta", {}).get("name", unit_id)
				})
	
	return actions

func _should_complete_phase() -> bool:
	# For now, require manual phase completion
	# TODO: Implement automatic completion logic
	# - All eligible units have charged or been marked to skip
	# - All declared charges have been resolved
	return false

# TODO: Add helper methods for charge mechanics
# func _calculate_charge_distance(charger: Dictionary, target: Dictionary) -> float
# func _roll_charge_distance() -> int
# func _check_charge_path(start_pos: Vector2, end_pos: Vector2, unit: Dictionary) -> bool
# func _calculate_engagement_range(unit1: Dictionary, unit2: Dictionary) -> float
# func _resolve_overwatch(charging_unit: Dictionary, target_unit: Dictionary) -> Dictionary