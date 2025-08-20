extends BasePhase
class_name ShootingPhase

# ShootingPhase - Full implementation of the Shooting phase following 10e rules
# Supports: Target selection, weapon assignment, attack resolution, damage allocation

signal unit_selected_for_shooting(unit_id: String)
signal targets_available(unit_id: String, eligible_targets: Dictionary)
signal shooting_begun(unit_id: String)
signal shooting_resolved(unit_id: String, target_unit_id: String, result: Dictionary)
signal dice_rolled(dice_data: Dictionary)

# Shooting state tracking
var active_shooter_id: String = ""
var pending_assignments: Array = []  # Weapon assignments before confirmation
var confirmed_assignments: Array = []  # Assignments ready to resolve
var resolution_state: Dictionary = {}  # State for step-by-step resolution
var dice_log: Array = []
var units_that_shot: Array = []  # Track which units have completed shooting

func _init():
	phase_type = GameStateData.Phase.SHOOTING

func _on_phase_enter() -> void:
	log_phase_message("Entering Shooting Phase")
	active_shooter_id = ""
	pending_assignments.clear()
	confirmed_assignments.clear()
	resolution_state.clear()
	dice_log.clear()
	units_that_shot.clear()
	
	_initialize_shooting()

func _on_phase_exit() -> void:
	log_phase_message("Exiting Shooting Phase")
	# Clear shooting flags
	_clear_phase_flags()

func _initialize_shooting() -> void:
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	var can_shoot = false
	for unit_id in units:
		var unit = units[unit_id]
		if _can_unit_shoot(unit):
			can_shoot = true
			break
	
	if not can_shoot:
		log_phase_message("No units available for shooting, completing phase")
		emit_signal("phase_completed")

func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")
	
	match action_type:
		"SELECT_SHOOTER":
			return _validate_select_shooter(action)
		"ASSIGN_TARGET":
			return _validate_assign_target(action)
		"CLEAR_ASSIGNMENT":
			return _validate_clear_assignment(action)
		"CLEAR_ALL_ASSIGNMENTS":
			return _validate_clear_all_assignments(action)
		"CONFIRM_TARGETS":
			return _validate_confirm_targets(action)
		"RESOLVE_SHOOTING":
			return _validate_resolve_shooting(action)
		"SKIP_UNIT":
			return _validate_skip_unit(action)
		"END_SHOOTING":
			return _validate_end_shooting(action)
		"SHOOT":  # Full shooting action from UI
			return _validate_shoot(action)
		_:
			return {"valid": false, "errors": ["Unknown action type: " + action_type]}

func process_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")
	
	match action_type:
		"SELECT_SHOOTER":
			return _process_select_shooter(action)
		"ASSIGN_TARGET":
			return _process_assign_target(action)
		"CLEAR_ASSIGNMENT":
			return _process_clear_assignment(action)
		"CLEAR_ALL_ASSIGNMENTS":
			return _process_clear_all_assignments(action)
		"CONFIRM_TARGETS":
			return _process_confirm_targets(action)
		"RESOLVE_SHOOTING":
			return _process_resolve_shooting(action)
		"SKIP_UNIT":
			return _process_skip_unit(action)
		"END_SHOOTING":
			return _process_end_shooting(action)
		"SHOOT":  # Full shooting action
			return _process_shoot(action)
		_:
			return create_result(false, [], "Unknown action type: " + action_type)

# Validation Methods

func _validate_select_shooter(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}
	
	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}
	
	if not _can_unit_shoot(unit):
		return {"valid": false, "errors": ["Unit cannot shoot"]}
	
	if unit_id in units_that_shot:
		return {"valid": false, "errors": ["Unit has already shot this phase"]}
	
	return {"valid": true, "errors": []}

func _validate_assign_target(action: Dictionary) -> Dictionary:
	var payload = action.get("payload", {})
	var weapon_id = payload.get("weapon_id", "")
	var target_unit_id = payload.get("target_unit_id", "")
	var model_ids = payload.get("model_ids", [])
	
	if active_shooter_id == "":
		return {"valid": false, "errors": ["No shooter selected"]}
	
	if weapon_id == "" or target_unit_id == "":
		return {"valid": false, "errors": ["Missing weapon_id or target_unit_id"]}
	
	# Check if weapon assignment would split attacks
	for assignment in pending_assignments:
		if assignment.weapon_id == weapon_id and assignment.target_unit_id != target_unit_id:
			return {"valid": false, "errors": ["Cannot split a weapon's attacks across multiple targets"]}
	
	# Validate with RulesEngine
	var shoot_action = {
		"type": "SHOOT",
		"actor_unit_id": active_shooter_id,
		"payload": {
			"assignments": [{
				"weapon_id": weapon_id,
				"target_unit_id": target_unit_id,
				"model_ids": model_ids
			}]
		}
	}
	
	var validation = RulesEngine.validate_shoot(shoot_action, game_state_snapshot)
	return validation

func _validate_clear_assignment(action: Dictionary) -> Dictionary:
	var payload = action.get("payload", {})
	var weapon_id = payload.get("weapon_id", "")
	
	if weapon_id == "":
		return {"valid": false, "errors": ["Missing weapon_id"]}
	
	return {"valid": true, "errors": []}

func _validate_clear_all_assignments(action: Dictionary) -> Dictionary:
	return {"valid": true, "errors": []}

func _validate_confirm_targets(action: Dictionary) -> Dictionary:
	if pending_assignments.is_empty():
		return {"valid": false, "errors": ["No targets assigned"]}
	
	return {"valid": true, "errors": []}

func _validate_resolve_shooting(action: Dictionary) -> Dictionary:
	if confirmed_assignments.is_empty():
		return {"valid": false, "errors": ["No confirmed targets to resolve"]}
	
	return {"valid": true, "errors": []}

func _validate_skip_unit(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	return {"valid": true, "errors": []}

func _validate_end_shooting(action: Dictionary) -> Dictionary:
	# Can always end the phase
	return {"valid": true, "errors": []}

func _validate_shoot(action: Dictionary) -> Dictionary:
	# Full shoot action validation
	var validation = RulesEngine.validate_shoot(action, game_state_snapshot)
	return validation

# Processing Methods

func _process_select_shooter(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	active_shooter_id = unit_id
	pending_assignments.clear()
	confirmed_assignments.clear()
	
	# Get eligible targets
	var eligible_targets = RulesEngine.get_eligible_targets(unit_id, game_state_snapshot)
	
	emit_signal("unit_selected_for_shooting", unit_id)
	emit_signal("targets_available", unit_id, eligible_targets)
	
	var unit = get_unit(unit_id)
	log_phase_message("Selected %s for shooting" % unit.get("meta", {}).get("name", unit_id))
	
	return create_result(true, [])

func _process_assign_target(action: Dictionary) -> Dictionary:
	var payload = action.get("payload", {})
	var weapon_id = payload.get("weapon_id", "")
	var target_unit_id = payload.get("target_unit_id", "")
	var model_ids = payload.get("model_ids", [])
	
	# Remove any existing assignment for this weapon
	pending_assignments = pending_assignments.filter(func(a): return a.weapon_id != weapon_id)
	
	# Add new assignment
	pending_assignments.append({
		"weapon_id": weapon_id,
		"target_unit_id": target_unit_id,
		"model_ids": model_ids
	})
	
	log_phase_message("Assigned %s to target %s" % [weapon_id, target_unit_id])
	
	return create_result(true, [])

func _process_clear_assignment(action: Dictionary) -> Dictionary:
	var payload = action.get("payload", {})
	var weapon_id = payload.get("weapon_id", "")
	
	pending_assignments = pending_assignments.filter(func(a): return a.weapon_id != weapon_id)
	
	log_phase_message("Cleared assignment for %s" % weapon_id)
	
	return create_result(true, [])

func _process_clear_all_assignments(action: Dictionary) -> Dictionary:
	pending_assignments.clear()
	log_phase_message("Cleared all weapon assignments")
	
	return create_result(true, [])

func _process_confirm_targets(action: Dictionary) -> Dictionary:
	confirmed_assignments = pending_assignments.duplicate(true)
	pending_assignments.clear()
	
	emit_signal("shooting_begun", active_shooter_id)
	log_phase_message("Confirmed targets, ready to resolve shooting")
	
	# Initialize resolution state
	resolution_state = {
		"current_assignment": 0,
		"phase": "ready"  # ready, hitting, wounding, saving, damage
	}
	
	# AUTO-RESOLVE: Immediately trigger shooting resolution
	var initial_result = create_result(true, [])
	
	# Call resolution directly
	var resolve_result = _process_resolve_shooting({})
	
	# Combine results
	if resolve_result.success:
		initial_result.changes.append_array(resolve_result.get("changes", []))
		initial_result["dice"] = resolve_result.get("dice", [])
		initial_result["log_text"] = resolve_result.get("log_text", "")
	
	return initial_result

func _process_resolve_shooting(action: Dictionary) -> Dictionary:
	# Emit signal to indicate resolution is starting
	emit_signal("dice_rolled", {"context": "resolution_start", "message": "Beginning attack resolution..."})
	
	# Build full shoot action for RulesEngine
	var shoot_action = {
		"type": "SHOOT",
		"actor_unit_id": active_shooter_id,
		"payload": {
			"assignments": confirmed_assignments
		}
	}
	
	# Resolve with RulesEngine
	var rng_service = RulesEngine.RNGService.new()
	var result = RulesEngine.resolve_shoot(shoot_action, game_state_snapshot, rng_service)
	
	if not result.success:
		return create_result(false, [], result.get("log_text", "Shooting failed"))
	
	# Apply changes
	var changes = result.get("diffs", [])
	
	# Record dice rolls
	var dice_data = result.get("dice", [])
	for dice_block in dice_data:
		dice_log.append(dice_block)
		emit_signal("dice_rolled", dice_block)
	
	# Mark unit as having shot
	changes.append({
		"op": "set",
		"path": "units.%s.flags.has_shot" % active_shooter_id,
		"value": true
	})
	
	units_that_shot.append(active_shooter_id)
	
	# Emit resolution signal
	for assignment in confirmed_assignments:
		emit_signal("shooting_resolved", active_shooter_id, assignment.target_unit_id, result)
	
	# Clear state
	active_shooter_id = ""
	confirmed_assignments.clear()
	resolution_state.clear()
	
	log_phase_message(result.get("log_text", "Shooting resolved"))
	
	return create_result(true, changes, "", {"dice": dice_data})

func _process_skip_unit(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	
	units_that_shot.append(unit_id)
	
	var changes = [{
		"op": "set",
		"path": "units.%s.flags.has_shot" % unit_id,
		"value": true
	}]
	
	# Clear any active state
	if active_shooter_id == unit_id:
		active_shooter_id = ""
		pending_assignments.clear()
		confirmed_assignments.clear()
	
	var unit = get_unit(unit_id)
	log_phase_message("Skipped shooting for %s" % unit.get("meta", {}).get("name", unit_id))
	
	return create_result(true, changes)

func _process_end_shooting(action: Dictionary) -> Dictionary:
	log_phase_message("Ending Shooting Phase")
	emit_signal("phase_completed")
	return create_result(true, [])

func _process_shoot(action: Dictionary) -> Dictionary:
	# Full shoot action - select shooter, assign targets, and resolve
	var unit_id = action.get("actor_unit_id", "")
	
	# Select shooter
	var select_result = _process_select_shooter({"actor_unit_id": unit_id})
	if not select_result.success:
		return select_result
	
	# Process assignments
	var assignments = action.get("payload", {}).get("assignments", [])
	for assignment in assignments:
		pending_assignments.append(assignment)
	
	# Confirm targets
	var confirm_result = _process_confirm_targets({})
	if not confirm_result.success:
		return confirm_result
	
	# Resolve shooting
	return _process_resolve_shooting({})

# Helper Methods

func _can_unit_shoot(unit: Dictionary) -> bool:
	var status = unit.get("status", 0)
	var flags = unit.get("flags", {})
	
	# Check if unit is deployed
	if status != GameStateData.UnitStatus.DEPLOYED and status != GameStateData.UnitStatus.MOVED:
		return false
	
	# Check restriction flags
	if flags.get("cannot_shoot", false):
		return false
	
	if flags.get("has_shot", false):
		return false
	
	# Check if unit is in engagement range (MVP: units in engagement cannot shoot)
	if flags.get("in_engagement", false):
		return false
	
	# Check if unit has any alive models
	var has_alive = false
	for model in unit.get("models", []):
		if model.get("alive", true):
			has_alive = true
			break
	
	return has_alive

func _clear_phase_flags() -> void:
	var units = game_state_snapshot.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.has("flags"):
			unit.flags.erase("has_shot")

func get_available_actions() -> Array:
	var actions = []
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	# If we have an active shooter with pending assignments
	if active_shooter_id != "" and not pending_assignments.is_empty():
		actions.append({
			"type": "CONFIRM_TARGETS",
			"description": "Confirm target assignments"
		})
		actions.append({
			"type": "CLEAR_ALL_ASSIGNMENTS",
			"description": "Clear all assignments"
		})
	
	# If we have confirmed assignments ready to resolve
	if not confirmed_assignments.is_empty():
		actions.append({
			"type": "RESOLVE_SHOOTING",
			"description": "Resolve shooting"
		})
	
	# Units that can shoot
	for unit_id in units:
		var unit = units[unit_id]
		if _can_unit_shoot(unit) and unit_id not in units_that_shot:
			actions.append({
				"type": "SELECT_SHOOTER",
				"actor_unit_id": unit_id,
				"description": "Select %s for shooting" % unit.get("meta", {}).get("name", unit_id)
			})
			
			actions.append({
				"type": "SKIP_UNIT",
				"actor_unit_id": unit_id,
				"description": "Skip shooting for %s" % unit.get("meta", {}).get("name", unit_id)
			})
	
	# Always can end phase
	actions.append({
		"type": "END_SHOOTING",
		"description": "End Shooting Phase"
	})
	
	return actions

func _should_complete_phase() -> bool:
	# Check if all eligible units have shot or been skipped
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	for unit_id in units:
		var unit = units[unit_id]
		if _can_unit_shoot(unit) and unit_id not in units_that_shot:
			return false
	
	return true

func get_dice_log() -> Array:
	return dice_log

func get_active_shooter() -> String:
	return active_shooter_id

func get_pending_assignments() -> Array:
	return pending_assignments

func get_confirmed_assignments() -> Array:
	return confirmed_assignments

func get_units_that_shot() -> Array:
	return units_that_shot

func has_active_shooter() -> bool:
	return active_shooter_id != ""

func get_current_shooting_state() -> Dictionary:
	return {
		"active_shooter_id": active_shooter_id,
		"pending_assignments": pending_assignments,
		"confirmed_assignments": confirmed_assignments,
		"units_that_shot": units_that_shot,
		"eligible_targets": {} # Will be populated when targets are queried
	}

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

func validate_loaded_state() -> bool:
	"""Validate that the loaded shooting phase state is consistent"""
	# Check if active shooter is valid
	if active_shooter_id != "":
		var shooter = get_unit(active_shooter_id)
		if shooter.is_empty():
			print("WARNING: Invalid active shooter after load: ", active_shooter_id)
			active_shooter_id = ""
			return false
		
		if not _can_unit_shoot(shooter):
			print("WARNING: Active shooter cannot shoot after load: ", active_shooter_id) 
			active_shooter_id = ""
			return false
	
	# Validate assignments reference valid units and weapons
	for assignment in pending_assignments:
		var target = get_unit(assignment.target_unit_id)
		if target.is_empty():
			print("WARNING: Invalid target in assignments: ", assignment.target_unit_id)
			return false
	
	return true
