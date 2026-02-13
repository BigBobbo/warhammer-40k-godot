extends BasePhase
class_name DeploymentPhase

const OvalBase = preload("res://scripts/bases/OvalBase.gd")
const BasePhase = preload("res://phases/BasePhase.gd")


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

	# Check base phase validation first (handles DEBUG_MOVE)
	var base_validation = super.validate_action(action)
	if not base_validation.get("valid", true):
		return base_validation

	match action_type:
		"DEPLOY_UNIT":
			return _validate_deploy_unit_action(action)
		"PLACE_IN_RESERVES":
			return _validate_place_in_reserves(action)
		"SWITCH_PLAYER":
			return _validate_switch_player_action(action)
		"END_DEPLOYMENT":
			return _validate_end_deployment_action(action)
		"EMBARK_UNITS_DEPLOYMENT":
			return _validate_embark_units_deployment(action)
		"ATTACH_CHARACTER_DEPLOYMENT":
			return _validate_attach_character_deployment(action)
		"DEBUG_MOVE":
			# Already validated by base class
			return {"valid": true}
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
	var model_rotations = action.get("model_rotations", [])

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
				var rotation = model_rotations[i] if i < model_rotations.size() else 0.0
				var validation = _validate_model_position(pos, unit, i, deployment_zone, rotation)
				if not validation.valid:
					errors.append_array(validation.errors)
	
	return {"valid": errors.size() == 0, "errors": errors}

func _validate_model_position(position: Vector2, unit: Dictionary, model_index: int, zone: Dictionary, rotation: float = 0.0) -> Dictionary:
	var errors = []

	# Get model info
	var models = unit.get("models", [])
	if model_index >= models.size():
		errors.append("Model index out of range")
		return {"valid": false, "errors": errors}

	var model = models[model_index]

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

func _validate_place_in_reserves(action: Dictionary) -> Dictionary:
	"""Validate placing a unit into Strategic Reserves or Deep Strike reserves"""
	var errors = []

	if not action.has("unit_id"):
		errors.append("Missing required field: unit_id")
		return {"valid": false, "errors": errors}

	var unit_id = action.unit_id
	var reserve_type = action.get("reserve_type", "strategic_reserves")  # "strategic_reserves" or "deep_strike"

	# Check if unit exists and is undeployed
	var unit = get_unit(unit_id)
	if unit.is_empty():
		errors.append("Unit not found: " + unit_id)
		return {"valid": false, "errors": errors}

	if unit.get("status", 0) != GameStateData.UnitStatus.UNDEPLOYED:
		errors.append("Unit is not available for reserves: " + unit_id)
		return {"valid": false, "errors": errors}

	# Check if unit belongs to active player
	var active_player = get_current_player()
	if unit.get("owner", 0) != active_player:
		errors.append("Unit does not belong to active player")
		return {"valid": false, "errors": errors}

	# Deep Strike validation: unit must have the Deep Strike ability
	if reserve_type == "deep_strike":
		if not GameState.unit_has_deep_strike(unit_id):
			errors.append("Unit does not have Deep Strike ability: " + unit_id)
			return {"valid": false, "errors": errors}

	# Strategic Reserves point limit: max 25% of total army points
	var unit_points = unit.get("meta", {}).get("points", 0)
	var total_points = GameState.get_total_army_points(active_player)
	var current_reserves_points = GameState.get_reserves_points(active_player)
	var max_reserves_points = int(total_points * 0.25)

	if current_reserves_points + unit_points > max_reserves_points:
		errors.append("Exceeds 25%% reserves limit: %d + %d > %d (of %d total)" % [current_reserves_points, unit_points, max_reserves_points, total_points])
		return {"valid": false, "errors": errors}

	return {"valid": true, "errors": []}

func _validate_switch_player_action(action: Dictionary) -> Dictionary:
	# Can only switch if current player has no more units to deploy
	var current_player = get_current_player()
	if _has_undeployed_units(current_player):
		return {"valid": false, "errors": ["Current player still has units to deploy"]}

	# Validate that new_player is the expected next player (prevents arbitrary player switching)
	var expected_next = 3 - current_player
	var new_player = action.get("new_player", 0)
	if new_player != 0 and new_player != expected_next:
		return {"valid": false, "errors": ["Invalid new_player: expected %d but got %d" % [expected_next, new_player]]}

	return {"valid": true, "errors": []}

func _validate_end_deployment_action(action: Dictionary) -> Dictionary:
	# Can only end deployment if all units are deployed
	var all_deployed = _all_units_deployed()

	if not all_deployed:
		return {"valid": false, "errors": ["Not all units have been deployed"]}

	return {"valid": true, "errors": []}

func _validate_embark_units_deployment(action: Dictionary) -> Dictionary:
	"""Validate that units can embark in a transport during deployment"""
	var errors = []

	# Check required fields
	if not action.has("transport_id"):
		errors.append("Missing transport_id")
	if not action.has("unit_ids"):
		errors.append("Missing unit_ids")

	if errors.size() > 0:
		return {"valid": false, "errors": errors}

	var transport_id = action.transport_id
	var unit_ids = action.unit_ids

	# Check if transport exists
	var transport = get_unit(transport_id)
	if transport.is_empty():
		errors.append("Transport not found: " + transport_id)
		return {"valid": false, "errors": errors}

	# Note: We don't strictly check if transport is DEPLOYED because in multiplayer,
	# this action may arrive before the deployment action is fully processed.
	# The transport should be deployed by the time this action is processed.

	# Check if transport has transport_data
	if not transport.has("transport_data"):
		errors.append("Unit is not a transport: " + transport_id)
		return {"valid": false, "errors": errors}

	var capacity = transport.transport_data.get("capacity", 0)
	var capacity_keywords = transport.transport_data.get("capacity_keywords", [])
	var currently_embarked = transport.transport_data.get("embarked_units", [])

	# Count current embarked models
	var current_count = 0
	for embarked_id in currently_embarked:
		var embarked_unit = get_unit(embarked_id)
		if not embarked_unit.is_empty():
			current_count += _count_alive_models(embarked_unit)

	# Validate each unit to embark
	# IMPORTANT: Check against transport owner, not active player!
	# Deployment switches turns, so active player may have changed by the time embarkation arrives
	var transport_owner = transport.get("owner", 0)
	var total_new_models = 0

	for unit_id in unit_ids:
		var unit = get_unit(unit_id)

		if unit.is_empty():
			errors.append("Unit not found: " + unit_id)
			continue

		# Must be undeployed
		if unit.get("status", 0) != GameStateData.UnitStatus.UNDEPLOYED:
			errors.append("Unit must be undeployed to embark during deployment: " + unit_id)
			continue

		# Must belong to same player as transport (not necessarily active player)
		if unit.get("owner", 0) != transport_owner:
			errors.append("Unit does not belong to transport owner: " + unit_id)
			continue

		# Check keywords if required
		if capacity_keywords.size() > 0:
			if not _unit_has_keywords(unit, capacity_keywords):
				errors.append("Unit missing required keywords %s: %s" % [str(capacity_keywords), unit_id])
				continue

		# Count models
		var model_count = _count_alive_models(unit)
		total_new_models += model_count

	# Check capacity
	if current_count + total_new_models > capacity:
		errors.append("Insufficient capacity: %d/%d (adding %d)" % [current_count + total_new_models, capacity, total_new_models])

	return {"valid": errors.size() == 0, "errors": errors}

func process_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	match action_type:
		"DEPLOY_UNIT":
			return _process_deploy_unit(action)
		"PLACE_IN_RESERVES":
			return _process_place_in_reserves(action)
		"SWITCH_PLAYER":
			return _process_switch_player(action)
		"END_DEPLOYMENT":
			return _process_end_deployment(action)
		"EMBARK_UNITS_DEPLOYMENT":
			return _process_embark_units_deployment(action)
		"ATTACH_CHARACTER_DEPLOYMENT":
			return _process_attach_character_deployment(action)
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

func _process_place_in_reserves(action: Dictionary) -> Dictionary:
	"""Process placing a unit into reserves (Strategic Reserves or Deep Strike)"""
	var unit_id = action.unit_id
	var reserve_type = action.get("reserve_type", "strategic_reserves")
	var changes = []

	# Set unit status to IN_RESERVES
	changes.append({
		"op": "set",
		"path": "units.%s.status" % unit_id,
		"value": GameStateData.UnitStatus.IN_RESERVES
	})

	# Store the reserve type on the unit for later use during reinforcements
	changes.append({
		"op": "set",
		"path": "units.%s.reserve_type" % unit_id,
		"value": reserve_type
	})

	# Apply changes through PhaseManager
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)

	# Update local snapshot
	_apply_changes_to_local_state(changes)

	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var type_label = "Deep Strike" if reserve_type == "deep_strike" else "Strategic Reserves"
	log_phase_message("Placed %s in %s" % [unit_name, type_label])

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
	log_phase_message("Deployment phase ending - all units deployed")

	# Emit phase_completed signal to trigger phase transition
	emit_signal("phase_completed")

	return create_result(true, [])

func _process_embark_units_deployment(action: Dictionary) -> Dictionary:
	"""Process units embarking in a transport during deployment"""
	var transport_id = action.transport_id
	var unit_ids = action.unit_ids
	var changes = []

	# For each unit to embark
	for unit_id in unit_ids:
		# Set embarked_in field
		changes.append({
			"op": "set",
			"path": "units.%s.embarked_in" % unit_id,
			"value": transport_id
		})

		# Set status to DEPLOYED (embarked units count as deployed)
		changes.append({
			"op": "set",
			"path": "units.%s.status" % unit_id,
			"value": GameStateData.UnitStatus.DEPLOYED
		})

		var unit = get_unit(unit_id)
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		log_phase_message("Unit %s embarked in transport %s" % [unit_name, transport_id])

	# Update transport's embarked_units list
	var transport = get_unit(transport_id)
	var current_embarked = transport.get("transport_data", {}).get("embarked_units", []).duplicate()
	current_embarked.append_array(unit_ids)

	changes.append({
		"op": "set",
		"path": "units.%s.transport_data.embarked_units" % transport_id,
		"value": current_embarked
	})

	# Apply changes through PhaseManager
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)

	# Update local snapshot
	_apply_changes_to_local_state(changes)

	log_phase_message("Embarked %d units in transport %s" % [unit_ids.size(), transport_id])

	return create_result(true, changes)

func _validate_attach_character_deployment(action: Dictionary) -> Dictionary:
	"""Validate that characters can attach to a bodyguard during deployment"""
	var errors = []

	if not action.has("bodyguard_id"):
		errors.append("Missing bodyguard_id")
	if not action.has("character_ids"):
		errors.append("Missing character_ids")

	if errors.size() > 0:
		return {"valid": false, "errors": errors}

	var bodyguard_id = action.bodyguard_id
	var character_ids = action.character_ids

	# Check if bodyguard exists
	var bodyguard = get_unit(bodyguard_id)
	if bodyguard.is_empty():
		errors.append("Bodyguard unit not found: " + bodyguard_id)
		return {"valid": false, "errors": errors}

	var bodyguard_owner = bodyguard.get("owner", 0)
	var bg_keywords = bodyguard.get("meta", {}).get("keywords", [])

	# Bodyguard should not be a CHARACTER
	if "CHARACTER" in bg_keywords:
		errors.append("Cannot attach to a CHARACTER unit")
		return {"valid": false, "errors": errors}

	for char_id in character_ids:
		var char_unit = get_unit(char_id)

		if char_unit.is_empty():
			errors.append("Character unit not found: " + char_id)
			continue

		# Must be undeployed
		if char_unit.get("status", 0) != GameStateData.UnitStatus.UNDEPLOYED:
			errors.append("Character must be undeployed to attach during deployment: " + char_id)
			continue

		# Must belong to same player as bodyguard
		if char_unit.get("owner", 0) != bodyguard_owner:
			errors.append("Character does not belong to bodyguard owner: " + char_id)
			continue

		# Must be a CHARACTER
		var char_keywords = char_unit.get("meta", {}).get("keywords", [])
		if "CHARACTER" not in char_keywords:
			errors.append("Unit is not a CHARACTER: " + char_id)
			continue

		# Must have leader_data with compatible keywords
		var leader_data = char_unit.get("meta", {}).get("leader_data", {})
		var can_lead = leader_data.get("can_lead", [])
		if can_lead.is_empty():
			errors.append("Character has no Leader ability: " + char_id)
			continue

		var has_match = false
		for lead_keyword in can_lead:
			if lead_keyword in bg_keywords:
				has_match = true
				break
		if not has_match:
			errors.append("Character cannot lead this unit type: " + char_id)

	return {"valid": errors.size() == 0, "errors": errors}

func _process_attach_character_deployment(action: Dictionary) -> Dictionary:
	"""Process character attachment to bodyguard during deployment"""
	var bodyguard_id = action.bodyguard_id
	var character_ids = action.character_ids
	var changes = []

	var bodyguard = get_unit(bodyguard_id)

	# Find a reference position from bodyguard models
	var ref_pos = null
	for model in bodyguard.get("models", []):
		var pos = model.get("position", null)
		if pos != null:
			ref_pos = pos
			break

	for char_id in character_ids:
		# Set attached_to field on character
		changes.append({
			"op": "set",
			"path": "units.%s.attached_to" % char_id,
			"value": bodyguard_id
		})

		# Set status to DEPLOYED
		changes.append({
			"op": "set",
			"path": "units.%s.status" % char_id,
			"value": GameStateData.UnitStatus.DEPLOYED
		})

		# Place character model adjacent to bodyguard
		if ref_pos != null:
			var char_unit = get_unit(char_id)
			var char_models = char_unit.get("models", [])
			for i in range(char_models.size()):
				var char_base_mm = char_models[i].get("base_mm", 40)
				var bg_base_mm = bodyguard.get("models", [{}])[0].get("base_mm", 32)
				var offset_px = Measurement.base_radius_px(char_base_mm) + Measurement.base_radius_px(bg_base_mm) + 2
				var ref_x = ref_pos.get("x", 0) if ref_pos is Dictionary else ref_pos.x
				var ref_y = ref_pos.get("y", 0) if ref_pos is Dictionary else ref_pos.y
				changes.append({
					"op": "set",
					"path": "units.%s.models.%d.position" % [char_id, i],
					"value": {"x": ref_x + offset_px, "y": ref_y}
				})

		var char_unit = get_unit(char_id)
		var char_name = char_unit.get("meta", {}).get("name", char_id)
		log_phase_message("Character %s attached to bodyguard %s" % [char_name, bodyguard_id])

	# Update bodyguard's attachment_data.attached_characters
	var current_attached = bodyguard.get("attachment_data", {}).get("attached_characters", []).duplicate()
	current_attached.append_array(character_ids)

	changes.append({
		"op": "set",
		"path": "units.%s.attachment_data.attached_characters" % bodyguard_id,
		"value": current_attached
	})

	# Apply changes through PhaseManager
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)

	_apply_changes_to_local_state(changes)

	log_phase_message("Attached %d character(s) to bodyguard %s" % [character_ids.size(), bodyguard_id])

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

		# Units can be placed in reserves (strategic reserves or deep strike)
		var unit = get_unit(unit_id)
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		if GameState.unit_has_deep_strike(unit_id):
			actions.append({
				"type": "PLACE_IN_RESERVES",
				"unit_id": unit_id,
				"reserve_type": "deep_strike",
				"description": "Deep Strike %s" % unit_name
			})
		else:
			actions.append({
				"type": "PLACE_IN_RESERVES",
				"unit_id": unit_id,
				"reserve_type": "strategic_reserves",
				"description": "Strategic Reserves %s" % unit_name
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
		# Skip units that are attached to a bodyguard (they're deployed with their bodyguard)
		if unit.get("attached_to", null) != null:
			continue
		# Skip units in reserves (they're off-table)
		if unit.get("status", 0) == GameStateData.UnitStatus.IN_RESERVES:
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
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		# Skip embarked units (they're deployed when inside a transport)
		if unit.get("embarked_in", null) != null:
			continue
		# Skip attached characters (they're deployed with their bodyguard)
		if unit.get("attached_to", null) != null:
			continue
		# Skip units in reserves (they're off-table, handled during reinforcements)
		if unit.get("status", 0) == GameStateData.UnitStatus.IN_RESERVES:
			continue

		var status = unit.get("status", 0)
		if status == GameStateData.UnitStatus.UNDEPLOYED:
			return false

	return true

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

	# Generate sample points around the shape's edge
	var sample_points = []

	if shape.get_type() == "oval":
		# For ovals, sample points around the ellipse perimeter
		var oval = shape as OvalBase
		var num_samples = 16  # Check 16 points around the ellipse

		for i in range(num_samples):
			var angle = (i * TAU) / num_samples
			# Points on ellipse: (a*cos(θ), b*sin(θ))
			var local_point = Vector2(
				oval.length * cos(angle),
				oval.width * sin(angle)
			)
			sample_points.append(local_point)
	elif shape.get_type() == "rectangular":
		# For rectangles, check the 4 corners
		var bounds = shape.get_bounds()
		var half_width = bounds.size.x / 2.0
		var half_height = bounds.size.y / 2.0

		sample_points = [
			Vector2(-half_width, -half_height),
			Vector2(half_width, -half_height),
			Vector2(half_width, half_height),
			Vector2(-half_width, half_height)
		]
	else:
		# Fallback: use bounding box corners
		var bounds = shape.get_bounds()
		var half_width = bounds.size.x / 2.0
		var half_height = bounds.size.y / 2.0

		sample_points = [
			Vector2(-half_width, -half_height),
			Vector2(half_width, -half_height),
			Vector2(half_width, half_height),
			Vector2(-half_width, half_height)
		]

	# Transform sample points to world space and check if in polygon
	for local_point in sample_points:
		var world_point = shape.to_world_space(local_point, center, rotation)

		if not Geometry2D.is_point_in_polygon(world_point, polygon):
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

# Helper functions for embarkation validation
func _unit_has_keywords(unit: Dictionary, required_keywords: Array) -> bool:
	"""Check if unit has all required keywords"""
	if not unit.has("meta") or not unit.meta.has("keywords"):
		return false

	var unit_keywords = unit.meta.keywords
	for keyword in required_keywords:
		if not keyword in unit_keywords:
			return false
	return true

func _count_alive_models(unit: Dictionary) -> int:
	"""Count alive models in a unit"""
	var count = 0
	if unit.has("models"):
		for model in unit.models:
			if model.get("alive", true):
				count += 1
	return count
