extends BasePhase
class_name DeploymentPhase

# DeploymentPhase - Handles the deployment phase logic using the modular system

var deployment_controller: Node = null

func _init():
	phase_type = GameStateData.Phase.DEPLOYMENT

func _on_phase_enter() -> void:
	log_phase_message("Entering Deployment Phase")
	
	# Find or create deployment controller
	_setup_deployment_controller()
	
	# Set up initial deployment state
	_initialize_deployment()

func _on_phase_exit() -> void:
	log_phase_message("Exiting Deployment Phase")
	
	# Clean up deployment controller
	if deployment_controller:
		deployment_controller.deployment_complete.disconnect(_on_deployment_complete)

func _setup_deployment_controller() -> void:
	# Find existing deployment controller in the scene
	var main_scene = get_tree().current_scene
	if main_scene:
		deployment_controller = main_scene.find_child("DeploymentController")
		
		if deployment_controller:
			# Connect to deployment signals
			if not deployment_controller.deployment_complete.is_connected(_on_deployment_complete):
				deployment_controller.deployment_complete.connect(_on_deployment_complete)

func _initialize_deployment() -> void:
	# Check if deployment is already complete
	if _all_units_deployed():
		log_phase_message("All units already deployed, completing phase")
		emit_signal("phase_completed")
		return
	
	# Initial player setting is handled by TurnManager via _handle_deployment_phase_start()
	log_phase_message("Deployment phase initialized")

func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")
	
	match action_type:
		"DEPLOY_UNIT":
			return _validate_deploy_unit_action(action)
		"SWITCH_PLAYER":
			return _validate_switch_player_action(action)
		_:
			return {"valid": false, "errors": ["Unknown action type: " + action_type]}

func _validate_deploy_unit_action(action: Dictionary) -> Dictionary:
	var errors = []
	
	# Check required fields
	var required_fields = ["unit_id", "model_positions"]
	for field in required_fields:
		if not action.has(field):
			errors.append("Missing required field: " + field)
	
	if errors.size() > 0:
		return {"valid": false, "errors": errors}
	
	var unit_id = action.unit_id
	var model_positions = action.model_positions
	
	# Check if unit exists and is undeployed
	var unit = get_unit(unit_id)
	if unit.is_empty():
		errors.append("Unit not found: " + unit_id)
	elif unit.get("status", 0) != GameStateData.UnitStatus.UNDEPLOYED:
		errors.append("Unit is not available for deployment: " + unit_id)
	
	# Check if unit belongs to active player
	var active_player = get_current_player()
	if unit.get("owner", 0) != active_player:
		errors.append("Unit does not belong to active player")
	
	# Validate model positions
	if model_positions is Array:
		var unit_owner = unit.get("owner", 0)
		var deployment_zone = get_deployment_zone_for_player(unit_owner)
		for i in range(model_positions.size()):
			var pos = model_positions[i]
			if pos != null:
				var validation = _validate_model_position(pos, unit, i, deployment_zone)
				if not validation.valid:
					errors.append_array(validation.errors)
	
	return {"valid": errors.size() == 0, "errors": errors}

func _validate_model_position(position: Vector2, unit: Dictionary, model_index: int, zone: Dictionary) -> Dictionary:
	var errors = []
	
	# Get model info
	var models = unit.get("models", [])
	if model_index >= models.size():
		errors.append("Model index out of range")
		return {"valid": false, "errors": errors}
	
	var model = models[model_index]
	var base_mm = model.get("base_mm", 32)
	var radius_px = _base_radius_px(base_mm)
	
	# Check deployment zone - convert zone from inches to pixels
	var zone_poly_inches = zone.get("poly", [])
	var zone_poly_pixels = _convert_zone_inches_to_pixels(zone_poly_inches)
	
	if not _circle_wholly_in_polygon(position, radius_px, zone_poly_pixels):
		errors.append("Model must be wholly within deployment zone")
	
	# Check overlap with other models
	if _position_overlaps_existing_models(position, radius_px, unit.get("id", "")):
		errors.append("Model cannot overlap with existing models")
	
	return {"valid": errors.size() == 0, "errors": errors}

func _validate_switch_player_action(action: Dictionary) -> Dictionary:
	# Can only switch if current player has no more units to deploy
	var current_player = get_current_player()
	if _has_undeployed_units(current_player):
		return {"valid": false, "errors": ["Current player still has units to deploy"]}
	
	return {"valid": true, "errors": []}

func process_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")
	
	match action_type:
		"DEPLOY_UNIT":
			return _process_deploy_unit(action)
		"SWITCH_PLAYER":
			return _process_switch_player(action)
		_:
			return create_result(false, [], "Unknown action type: " + action_type)

func _process_deploy_unit(action: Dictionary) -> Dictionary:
	var unit_id = action.unit_id
	var model_positions = action.model_positions
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
	
	# Update unit status to deployed
	changes.append({
		"op": "set",
		"path": "units.%s.status" % unit_id,
		"value": GameStateData.UnitStatus.DEPLOYED
	})
	
	# Apply changes through PhaseManager
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)
	
	# Update local snapshot
	_apply_changes_to_local_state(changes)
	
	# Don't handle player switching here - let TurnManager do it via the action_taken signal
	
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("Deployed %s" % unit_name)
	
	return create_result(true, changes)

func _process_switch_player(action: Dictionary) -> Dictionary:
	var changes = []
	var new_player = action.get("new_player", 0)
	
	if new_player > 0:
		changes.append({
			"op": "set",
			"path": "meta.active_player",
			"value": new_player
		})
		
		# Apply changes
		if get_parent() and get_parent().has_method("apply_state_changes"):
			get_parent().apply_state_changes(changes)
		
		_apply_changes_to_local_state(changes)
		
		log_phase_message("Switched to Player %d" % new_player)
	
	return create_result(true, changes)

func get_available_actions() -> Array:
	var actions = []
	var current_player = get_current_player()
	
	# Get undeployed units for current player
	var undeployed_units = _get_undeployed_units_for_player(current_player)
	for unit_id in undeployed_units:
		actions.append({
			"type": "DEPLOY_UNIT",
			"unit_id": unit_id,
			"description": "Deploy " + get_unit(unit_id).get("meta", {}).get("name", unit_id)
		})
	
	# Check if player can be switched
	if not _has_undeployed_units(current_player):
		var other_player = 3 - current_player  # Switch between 1 and 2
		if _has_undeployed_units(other_player):
			actions.append({
				"type": "SWITCH_PLAYER",
				"new_player": other_player,
				"description": "Switch to Player %d" % other_player
			})
	
	return actions

func _should_complete_phase() -> bool:
	return _all_units_deployed()

func _on_deployment_complete() -> void:
	log_phase_message("Deployment completed")
	emit_signal("phase_completed")

# Helper methods
func _has_undeployed_units(player: int) -> bool:
	var units = get_units_for_player(player)
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("status", 0) == GameStateData.UnitStatus.UNDEPLOYED:
			return true
	return false

func _get_undeployed_units_for_player(player: int) -> Array:
	var undeployed = []
	var units = get_units_for_player(player)
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("status", 0) == GameStateData.UnitStatus.UNDEPLOYED:
			undeployed.append(unit_id)
	return undeployed

func _all_units_deployed() -> bool:
	var units = game_state_snapshot.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("status", 0) == GameStateData.UnitStatus.UNDEPLOYED:
			return false
	return true

# Player switching is now handled by TurnManager via the action_taken signal
# These methods have been removed to avoid conflicts with TurnManager

func _apply_changes_to_local_state(changes: Array) -> void:
	for change in changes:
		_apply_single_change_to_local(change)

func _apply_single_change_to_local(change: Dictionary) -> void:
	match change.get("op", ""):
		"set":
			_set_local_value(change.path, change.value)

func _set_local_value(path: String, value) -> void:
	var parts = path.split(".")
	var current = game_state_snapshot
	
	for i in range(parts.size() - 1):
		var part = parts[i]
		if part.is_valid_int():
			var index = part.to_int()
			if current is Array and index >= 0 and index < current.size():
				current = current[index]
			else:
				return
		else:
			if current is Dictionary and current.has(part):
				current = current[part]
			else:
				return
	
	var final_key = parts[-1]
	if final_key.is_valid_int():
		var index = final_key.to_int()
		if current is Array and index >= 0 and index < current.size():
			current[index] = value
	else:
		if current is Dictionary:
			current[final_key] = value

# Geometry and validation helpers
func _base_radius_px(base_mm: int) -> float:
	return (base_mm / 2.0) * (40.0 / 25.4)  # Convert mm to pixels at 40px/inch

func _convert_zone_inches_to_pixels(zone_inches: Array) -> PackedVector2Array:
	var packed = PackedVector2Array()
	for coord in zone_inches:
		if coord is Dictionary and coord.has("x") and coord.has("y"):
			# Convert inches to pixels at 40px/inch
			var x_px = coord.x * 40.0
			var y_px = coord.y * 40.0
			packed.append(Vector2(x_px, y_px))
	return packed

func _dict_array_to_packed_vector2(dict_array: Array) -> PackedVector2Array:
	var packed = PackedVector2Array()
	for dict in dict_array:
		if dict is Dictionary and dict.has("x") and dict.has("y"):
			packed.append(Vector2(dict.x, dict.y))
	return packed

func _circle_wholly_in_polygon(center: Vector2, radius: float, polygon: PackedVector2Array) -> bool:
	if not Geometry2D.is_point_in_polygon(center, polygon):
		return false
	
	for i in range(polygon.size()):
		var p1 = polygon[i]
		var p2 = polygon[(i + 1) % polygon.size()]
		var dist = _point_to_line_distance(center, p1, p2)
		if dist < radius:
			return false
	
	return true

func _point_to_line_distance(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	var line_vec = line_end - line_start
	var point_vec = point - line_start
	var line_len = line_vec.length()
	
	if line_len == 0:
		return point_vec.length()
	
	var t = max(0, min(1, point_vec.dot(line_vec) / (line_len * line_len)))
	var projection = line_start + t * line_vec
	
	return point.distance_to(projection)

func _position_overlaps_existing_models(pos: Vector2, radius: float, current_unit_id: String) -> bool:
	var units = game_state_snapshot.get("units", {})
	
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("status", 0) == GameStateData.UnitStatus.DEPLOYED:
			var models = unit.get("models", [])
			for model in models:
				var model_pos_dict = model.get("position", null)
				if model_pos_dict != null:
					var model_pos = Vector2(model_pos_dict.get("x", 0), model_pos_dict.get("y", 0))
					var model_radius = _base_radius_px(model.get("base_mm", 32))
					var distance = pos.distance_to(model_pos)
					if distance < (radius + model_radius):
						return true
	
	return false