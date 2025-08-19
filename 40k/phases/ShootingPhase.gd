extends BasePhase
class_name ShootingPhase

# ShootingPhase - Stub implementation for the Shooting phase
# This is a placeholder that can be expanded with full shooting mechanics

func _init():
	phase_type = GameStateData.Phase.SHOOTING

func _on_phase_enter() -> void:
	log_phase_message("Entering Shooting Phase")
	
	# Initialize shooting phase state
	_initialize_shooting()

func _on_phase_exit() -> void:
	log_phase_message("Exiting Shooting Phase")

func _initialize_shooting() -> void:
	# Check if there are any units that can shoot
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	var can_shoot = false
	for unit_id in units:
		var unit = units[unit_id]
		var status = unit.get("status", 0)
		var advanced = unit.get("advanced", false)
		var fallen_back = unit.get("fallen_back", false)
		
		# Units that advanced or fell back generally cannot shoot
		if (status == GameStateData.UnitStatus.DEPLOYED or status == GameStateData.UnitStatus.MOVED) and not advanced and not fallen_back:
			can_shoot = true
			break
	
	if not can_shoot:
		log_phase_message("No units available for shooting, completing phase")
		emit_signal("phase_completed")

func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")
	
	match action_type:
		"SHOOT_WEAPON":
			return _validate_shoot_weapon_action(action)
		"OVERWATCH":
			return _validate_overwatch_action(action)
		"SKIP_SHOOTING":
			return _validate_skip_shooting_action(action)
		_:
			return {"valid": false, "errors": ["Unknown action type: " + action_type]}

func _validate_shoot_weapon_action(action: Dictionary) -> Dictionary:
	var errors = []
	
	# Check required fields
	var required_fields = ["unit_id", "weapon_id", "target_unit_id"]
	for field in required_fields:
		if not action.has(field):
			errors.append("Missing required field: " + field)
	
	if errors.size() > 0:
		return {"valid": false, "errors": errors}
	
	var unit_id = action.unit_id
	var weapon_id = action.weapon_id
	var target_unit_id = action.target_unit_id
	
	var unit = get_unit(unit_id)
	var target_unit = get_unit(target_unit_id)
	
	# Check if units exist
	if unit.is_empty():
		errors.append("Shooting unit not found: " + unit_id)
	if target_unit.is_empty():
		errors.append("Target unit not found: " + target_unit_id)
	
	if errors.size() > 0:
		return {"valid": false, "errors": errors}
	
	# Check if unit belongs to active player
	if unit.get("owner", 0) != get_current_player():
		errors.append("Unit does not belong to active player")
	
	# Check if target belongs to enemy player
	if target_unit.get("owner", 0) == get_current_player():
		errors.append("Cannot target own units")
	
	# Check if unit can shoot
	var unit_status = unit.get("status", 0)
	var advanced = unit.get("advanced", false)
	var fallen_back = unit.get("fallen_back", false)
	
	if advanced:
		errors.append("Unit cannot shoot after advancing")
	if fallen_back:
		errors.append("Unit cannot shoot after falling back")
	
	# TODO: Add detailed shooting validation
	# - Check weapon range
	# - Check line of sight
	# - Check if weapon has already fired
	# - Check target visibility
	# - Check special weapon rules
	
	return {"valid": errors.size() == 0, "errors": errors}

func _validate_overwatch_action(action: Dictionary) -> Dictionary:
	# Overwatch is typically a reactive shooting action
	var base_validation = _validate_shoot_weapon_action(action)
	if not base_validation.valid:
		return base_validation
	
	# TODO: Add overwatch-specific validation
	# - Check if unit is being charged
	# - Check if unit has eligible weapons for overwatch
	# - Apply overwatch penalties
	
	return {"valid": true, "errors": []}

func _validate_skip_shooting_action(action: Dictionary) -> Dictionary:
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
		"SHOOT_WEAPON":
			return _process_shoot_weapon(action)
		"OVERWATCH":
			return _process_overwatch(action)
		"SKIP_SHOOTING":
			return _process_skip_shooting(action)
		_:
			return create_result(false, [], "Unknown action type: " + action_type)

func _process_shoot_weapon(action: Dictionary) -> Dictionary:
	var unit_id = action.unit_id
	var weapon_id = action.weapon_id
	var target_unit_id = action.target_unit_id
	var changes = []
	
	# TODO: Implement actual shooting mechanics
	# - Roll to hit
	# - Roll to wound
	# - Target saves
	# - Apply damage
	# - Remove casualties
	
	# For now, just mark unit as having shot
	changes.append({
		"op": "set",
		"path": "units.%s.status" % unit_id,
		"value": GameStateData.UnitStatus.SHOT
	})
	
	# Record the shooting action
	changes.append({
		"op": "add",
		"path": "units.%s.actions_taken" % unit_id,
		"value": {
			"type": "shoot",
			"weapon": weapon_id,
			"target": target_unit_id,
			"turn": get_turn_number()
		}
	})
	
	# Apply changes through PhaseManager
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)
	
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("%s shot at %s" % [unit_name, target_unit_id])
	
	return create_result(true, changes)

func _process_overwatch(action: Dictionary) -> Dictionary:
	# Process as normal shooting but with overwatch modifiers
	var result = _process_shoot_weapon(action)
	if result.success:
		var unit_id = action.unit_id
		var overwatch_change = {
			"op": "set",
			"path": "units.%s.overwatched" % unit_id,
			"value": true
		}
		
		if get_parent() and get_parent().has_method("apply_state_changes"):
			get_parent().apply_state_changes([overwatch_change])
		
		result.changes.append(overwatch_change)
		log_phase_message("Unit %s fired overwatch" % unit_id)
	
	return result

func _process_skip_shooting(action: Dictionary) -> Dictionary:
	var unit_id = action.unit_id
	log_phase_message("Skipped shooting for %s" % unit_id)
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
		var advanced = unit.get("advanced", false)
		var fallen_back = unit.get("fallen_back", false)
		
		# Check if unit can shoot
		if (status == GameStateData.UnitStatus.DEPLOYED or status == GameStateData.UnitStatus.MOVED) and not advanced and not fallen_back:
			
			# Add shooting actions for each potential target
			for target_unit_id in enemy_units:
				actions.append({
					"type": "SHOOT_WEAPON",
					"unit_id": unit_id,
					"target_unit_id": target_unit_id,
					"weapon_id": "primary_weapon",  # TODO: Get actual weapon list
					"description": "Shoot %s at %s" % [unit.get("meta", {}).get("name", unit_id), target_unit_id]
				})
			
			# Skip shooting option
			actions.append({
				"type": "SKIP_SHOOTING",
				"unit_id": unit_id,
				"description": "Skip shooting for " + unit.get("meta", {}).get("name", unit_id)
			})
	
	return actions

func _should_complete_phase() -> bool:
	# For now, require manual phase completion
	# TODO: Implement automatic completion logic
	# - All eligible units have shot or been marked to skip
	# - No more valid targets in range
	return false

# TODO: Add helper methods for shooting mechanics
# func _calculate_range(shooter_pos: Vector2, target_pos: Vector2) -> float
# func _check_line_of_sight(shooter: Dictionary, target: Dictionary) -> bool
# func _roll_to_hit(weapon_skill: int, modifiers: Dictionary) -> Array
# func _roll_to_wound(strength: int, toughness: int, modifiers: Dictionary) -> Array
# func _apply_saves(wounds: int, save_value: int, ap: int, modifiers: Dictionary) -> int
# func _allocate_wounds(unit: Dictionary, wounds: int) -> Array