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
	print("DeploymentPhase: ========== validate_action CALLED ==========")
	print("DeploymentPhase: Full action dictionary: ", action)
	var action_type = action.get("type", "")
	print("DeploymentPhase: action_type = '", action_type, "' (length: ", action_type.length(), ")")
	print("DeploymentPhase: action_type == 'END_DEPLOYMENT': ", action_type == "END_DEPLOYMENT")
	DebugLogger.info("DeploymentPhase.validate_action", {
		"action_type": action_type,
		"full_action": str(action),
		"phase_class": get_class()
	})

	match action_type:
		"DEPLOY_UNIT":
			print("DeploymentPhase: Matched DEPLOY_UNIT")
			return _validate_deploy_unit_action(action)
		"SWITCH_PLAYER":
			print("DeploymentPhase: Matched SWITCH_PLAYER")
			return _validate_switch_player_action(action)
		"END_DEPLOYMENT":
			print("DeploymentPhase: Matched END_DEPLOYMENT")
			return _validate_end_deployment_action(action)
		_:
			print("DeploymentPhase: NO MATCH - fell through to default case")
			print("DeploymentPhase: Returning unknown action error")
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
	var rotation = 0.0  # Validation uses default rotation

	# Check deployment zone - convert zone from inches to pixels
	var zone_poly_inches = zone.get("poly", [])
	var zone_poly_pixels = _convert_zone_inches_to_pixels(zone_poly_inches)

	# Use shape-aware validation
	if not _shape_wholly_in_polygon(position, model, rotation, zone_poly_pixels):
		errors.append("Model must be wholly within deployment zone")

	# Check overlap with other models using shape-aware collision
	if _position_overlaps_existing_models_shape(position, model, rotation, unit.get("id", "")):
		errors.append("Model cannot overlap with existing models")

	# Check overlap with walls
	var test_model = model.duplicate()
	test_model["position"] = position
	test_model["rotation"] = rotation
	if Measurement.model_overlaps_any_wall(test_model):
		errors.append("Model cannot overlap with walls")

	return {"valid": errors.size() == 0, "errors": errors}

func _validate_switch_player_action(action: Dictionary) -> Dictionary:
	# Can only switch if current player has no more units to deploy
	var current_player = get_current_player()
	if _has_undeployed_units(current_player):
		return {"valid": false, "errors": ["Current player still has units to deploy"]}

	return {"valid": true, "errors": []}

func _validate_end_deployment_action(action: Dictionary) -> Dictionary:
	# Can only end deployment if all units are deployed
	var all_deployed = _all_units_deployed()
	print("DeploymentPhase: _validate_end_deployment_action - all_deployed: ", all_deployed)
	DebugLogger.info("DeploymentPhase._validate_end_deployment_action", {
		"all_deployed": all_deployed
	})

	if not all_deployed:
		return {"valid": false, "errors": ["Not all units have been deployed"]}

	print("DeploymentPhase: END_DEPLOYMENT validation PASSED")
	return {"valid": true, "errors": []}

func process_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	match action_type:
		"DEPLOY_UNIT":
			return _process_deploy_unit(action)
		"SWITCH_PLAYER":
			return _process_switch_player(action)
		"END_DEPLOYMENT":
			return _process_end_deployment(action)
		_:
			return create_result(false, [], "Unknown action type: " + action_type)

func _process_deploy_unit(action: Dictionary) -> Dictionary:
	var unit_id = action.unit_id
	var model_positions = action.model_positions
	var model_rotations = action.get("model_rotations", [])
	var changes = []

	# Update model positions and rotations
	for i in range(model_positions.size()):
		var pos = model_positions[i]
		if pos != null:
			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.position" % [unit_id, i],
				"value": {"x": pos.x, "y": pos.y}
			})

			# Apply rotation if provided
			if i < model_rotations.size() and model_rotations[i] != null:
				changes.append({
					"op": "set",
					"path": "units.%s.models.%d.rotation" % [unit_id, i],
					"value": model_rotations[i]
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

	# Transport embark dialog is now handled by DeploymentController BEFORE deployment

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

func _process_end_deployment(action: Dictionary) -> Dictionary:
	print("DeploymentPhase: ⚠️⚠️⚠️ _process_end_deployment CALLED ⚠️⚠️⚠️")
	DebugLogger.info("DeploymentPhase._process_end_deployment", {"action": action})

	log_phase_message("Deployment phase ending - all units deployed")

	# Emit phase_completed signal to trigger phase transition
	print("DeploymentPhase: ⚠️ Emitting phase_completed signal")
	DebugLogger.info("Emitting phase_completed signal", {})
	emit_signal("phase_completed")
	print("DeploymentPhase: ⚠️ phase_completed signal emitted")

	var result = create_result(true, [])
	print("DeploymentPhase: ⚠️ Returning result: ", result)
	DebugLogger.info("_process_end_deployment returning", {"result": result})
	return result

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
		# Skip units that are embarked (they're considered deployed when inside a transport)
		if unit.get("embarked_in", null) != null:
			continue
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
	# CRITICAL: Use GameState directly instead of game_state_snapshot
	# The snapshot may be stale and not reflect recent deployments
	print("DeploymentPhase: ⚠️ Checking deployment status - using GameState directly")

	var undeployed_list = []
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		# Skip embarked units (they're deployed when inside a transport)
		if unit.get("embarked_in", null) != null:
			print("  - Skipping ", unit_id, " (embarked)")
			continue

		var status = unit.get("status", 0)
		if status == GameStateData.UnitStatus.UNDEPLOYED:
			var owner = unit.get("owner", unit.get("player", 0))
			undeployed_list.append(unit_id + " (owner:" + str(owner) + " status:" + str(status) + ")")
			print("  - UNDEPLOYED: ", unit_id, " owner=", owner, " status=", status)

	var all_deployed = undeployed_list.size() == 0
	print("DeploymentPhase: ⚠️ Deployment check result: all_deployed=", all_deployed)

	if not all_deployed:
		print("DeploymentPhase: ⚠️ Still undeployed: ", undeployed_list)
		DebugLogger.info("Undeployed units remaining", {"units": undeployed_list})

	return all_deployed

# Player switching is now handled by TurnManager via the action_taken signal
# Transport embark dialog is now handled by DeploymentController BEFORE deployment

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

func _shape_wholly_in_polygon(center: Vector2, model_data: Dictionary, rotation: float, polygon: PackedVector2Array) -> bool:
	"""Check if a model's base shape is wholly within a polygon"""
	# Create the base shape
	var shape = Measurement.create_base_shape(model_data)
	if not shape:
		return false

	# For circular, use existing method
	var base_type = model_data.get("base_type", "circular")
	if base_type == "circular":
		var radius = Measurement.base_radius_px(model_data.get("base_mm", 32))
		return _circle_wholly_in_polygon(center, radius, polygon)

	# For non-circular shapes, check if all corners are inside
	var bounds = shape.get_bounds()
	var corners = [
		Vector2(bounds.position.x, bounds.position.y),
		Vector2(bounds.position.x + bounds.size.x, bounds.position.y),
		Vector2(bounds.position.x + bounds.size.x, bounds.position.y + bounds.size.y),
		Vector2(bounds.position.x, bounds.position.y + bounds.size.y)
	]

	# Transform corners to world space
	for corner in corners:
		var world_corner = shape.to_world_space(corner, center, rotation)
		if not Geometry2D.is_point_in_polygon(world_corner, polygon):
			return false

	return true

func _position_overlaps_existing_models_shape(pos: Vector2, model_data: Dictionary, rotation: float, current_unit_id: String) -> bool:
	"""Check if a model's shape overlaps with any existing deployed models"""
	var shape = Measurement.create_base_shape(model_data)
	if not shape:
		return false

	var units = game_state_snapshot.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("status", 0) == GameStateData.UnitStatus.DEPLOYED:
			var models = unit.get("models", [])
			for model in models:
				var model_pos_dict = model.get("position", null)
				if model_pos_dict != null:
					var model_pos = Vector2(model_pos_dict.get("x", 0), model_pos_dict.get("y", 0))
					var other_rotation = model.get("rotation", 0.0)

					# Create shape for existing model
					var other_shape = Measurement.create_base_shape(model)
					if other_shape:
						# Use shape-based collision detection
						if shape.overlaps_with(other_shape, pos, rotation, model_pos, other_rotation):
							return true

	return false

# Transport embark dialog is now handled by DeploymentController BEFORE deployment
# No need to detect transport deployments here anymore