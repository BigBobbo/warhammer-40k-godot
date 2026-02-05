extends Node
# Note: GameStateData, BaseShape, CircularBase, OvalBase are available globally via class_name
# Removed preloads to fix web export loading issues

signal deployment_complete()
signal unit_confirmed()
signal models_placed_changed()

var unit_id: String = ""
var model_idx: int = -1
var temp_positions: Array = []
var temp_rotations: Array = []  # Store rotations for each model
var token_layer: Node2D
var ghost_layer: Node2D
var ghost_sprite: Node2D = null
var placed_tokens: Array = []

# Formation deployment state
var formation_mode: String = "SINGLE"  # SINGLE, SPREAD, TIGHT
var formation_size: int = 5  # Models per formation group
var formation_preview_ghosts: Array = []  # Ghost visuals for formation
var formation_anchor_pos: Vector2  # Where user clicks to place formation
var formation_rotation: float = 0.0  # Rotation angle for formation (radians)

# Model repositioning state
var repositioning_model: bool = false
var reposition_model_index: int = -1
var reposition_start_pos: Vector2
var reposition_ghost: Node2D = null

# Transport embark state
var pending_embark_units: Array = []  # Units to embark after deployment
var is_awaiting_embark_dialog: bool = false  # Waiting for transport embark dialog

func _ready() -> void:
	set_process(true)
	set_process_unhandled_input(true)

func set_layers(tokens: Node2D, ghosts: Node2D) -> void:
	token_layer = tokens
	ghost_layer = ghosts

func _unhandled_input(event: InputEvent) -> void:
	if not is_placing():
		return

	# In multiplayer, block all input if it's not your turn
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.is_networked() and not network_manager.is_local_player_turn():
		return

	# Check if we have ghosts to work with (unless repositioning)
	if not repositioning_model and not ghost_sprite and formation_preview_ghosts.is_empty():
		return

	# Handle clicks for formation placement
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var mouse_pos = _get_world_mouse_position()

				# Check for shift+click on deployed model for repositioning
				if Input.is_key_pressed(KEY_SHIFT):
					var deployed_model = _get_deployed_model_at_position(mouse_pos)
					if not deployed_model.is_empty():
						_start_model_repositioning(deployed_model)
						return

				# Handle repositioning end
				if repositioning_model:
					_end_model_repositioning(mouse_pos)
					return

				# Normal placement logic
				if formation_mode != "SINGLE":
					try_place_formation_at(mouse_pos)
				else:
					try_place_at(mouse_pos)
				return
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Cancel repositioning on right-click
			if repositioning_model:
				_cancel_model_repositioning()
				return

	elif event is InputEventMouseMotion:
		if repositioning_model:
			_update_model_repositioning(event.position)
			return

	# Handle rotation controls during deployment
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_Q:
			# Rotate left
			if formation_mode == "SINGLE":
				# Rotate individual model ghost
				if ghost_sprite and ghost_sprite.has_method("rotate_by"):
					ghost_sprite.rotate_by(-PI/12)  # 15 degrees
			else:
				# Rotate formation
				formation_rotation -= PI/12  # 15 degrees counter-clockwise
		elif event.keycode == KEY_E:
			# Rotate right
			if formation_mode == "SINGLE":
				# Rotate individual model ghost
				if ghost_sprite and ghost_sprite.has_method("rotate_by"):
					ghost_sprite.rotate_by(PI/12)  # 15 degrees
			else:
				# Rotate formation
				formation_rotation += PI/12  # 15 degrees clockwise
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			# Rotate with mouse wheel
			if formation_mode == "SINGLE":
				if ghost_sprite and ghost_sprite.has_method("rotate_by"):
					ghost_sprite.rotate_by(PI/12)
			else:
				formation_rotation += PI/12
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if formation_mode == "SINGLE":
				if ghost_sprite and ghost_sprite.has_method("rotate_by"):
					ghost_sprite.rotate_by(-PI/12)
			else:
				formation_rotation -= PI/12

func begin_deploy(_unit_id: String) -> void:
	# In multiplayer, block deployment if it's not your turn
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.is_networked() and not network_manager.is_local_player_turn():
		print("[DeploymentController] Blocking deployment - not your turn")
		return

	unit_id = _unit_id
	model_idx = 0
	temp_positions.clear()
	temp_rotations.clear()
	var unit_data = GameState.get_unit(unit_id)
	temp_positions.resize(unit_data["models"].size())
	temp_rotations.resize(unit_data["models"].size())
	temp_rotations.fill(0.0)
	formation_rotation = 0.0  # Reset formation rotation for new unit

	# Update through PhaseManager instead of BoardState
	if has_node("/root/PhaseManager"):
		var phase_manager = get_node("/root/PhaseManager")
		if phase_manager.current_phase_instance:
			# Set unit status to deploying in GameState
			phase_manager.apply_state_changes([{
				"op": "set",
				"path": "units.%s.status" % unit_id,
				"value": GameStateData.UnitStatus.DEPLOYING
			}])

	# Create appropriate ghosts based on formation mode
	if formation_mode == "SINGLE":
		_create_ghost()
	else:
		var remaining = _get_unplaced_model_indices()
		if not remaining.is_empty():
			_create_formation_ghosts(min(formation_size, remaining.size()))

func is_placing() -> bool:
	return unit_id != ""

func get_current_unit() -> String:
	return unit_id

func get_placed_count() -> int:
	var count = 0
	for pos in temp_positions:
		if pos != null:
			count += 1
	return count

func try_place_at(world_pos: Vector2) -> void:
	if not is_placing():
		return

	if model_idx >= temp_positions.size():
		return

	var unit_data = GameState.get_unit(unit_id)
	var model_data = unit_data["models"][model_idx]
	var active_player = GameState.get_active_player()
	var zone = BoardState.get_deployment_zone_for_player(active_player)

	# Get current rotation from ghost
	var rotation = 0.0
	if ghost_sprite and ghost_sprite.has_method("get_base_rotation"):
		rotation = ghost_sprite.get_base_rotation()

	# Check if wholly within deployment zone based on shape
	var base_type = model_data.get("base_type", "circular")
	var is_in_zone = false

	if base_type == "circular":
		var radius_px = Measurement.base_radius_px(model_data["base_mm"])
		is_in_zone = _circle_wholly_in_polygon(world_pos, radius_px, zone)
	else:
		# For non-circular bases, use shape-aware validation
		is_in_zone = _shape_wholly_in_polygon(world_pos, model_data, rotation, zone)

	if not is_in_zone:
		_show_toast("Must be wholly within your deployment zone")
		return

	# Check for overlap with existing models
	if _overlaps_with_existing_models_shape(world_pos, model_data, rotation):
		_show_toast("Cannot overlap with existing models")
		return

	# Check for overlap with walls
	var test_model = model_data.duplicate()
	test_model["position"] = world_pos
	test_model["rotation"] = rotation
	if Measurement.model_overlaps_any_wall(test_model):
		_show_toast("Cannot overlap with walls")
		return

	# Store position and rotation (rotation already captured above)
	temp_positions[model_idx] = world_pos
	temp_rotations[model_idx] = rotation
	_spawn_preview_token(unit_id, model_idx, world_pos, rotation)
	model_idx += 1

	_check_coherency_warning()
	emit_signal("models_placed_changed")

	if model_idx < temp_positions.size():
		_update_ghost_for_next_model()

func try_place_formation_at(world_pos: Vector2) -> void:
	"""Place multiple models in formation at once"""
	if formation_mode == "SINGLE":
		try_place_at(world_pos)
		return

	var unit_data = GameState.get_unit(unit_id)
	var remaining_indices = _get_unplaced_model_indices()
	var models_to_place = min(formation_size, remaining_indices.size())

	if models_to_place == 0:
		return

	# Calculate formation positions
	var model_data = unit_data["models"][remaining_indices[0]]
	var base_mm = model_data["base_mm"]
	var positions = []

	match formation_mode:
		"SPREAD":
			positions = calculate_spread_formation(world_pos, models_to_place, base_mm, formation_rotation)
		"TIGHT":
			positions = calculate_tight_formation(world_pos, models_to_place, base_mm, formation_rotation)

	# Validate all positions
	var zone = BoardState.get_deployment_zone_for_player(GameState.get_active_player())
	var all_valid = true
	var error_msg = ""

	for i in range(positions.size()):
		var pos = positions[i]
		var idx = remaining_indices[i]
		var model = unit_data["models"][idx]

		if not _validate_formation_position(pos, model, zone):
			all_valid = false
			error_msg = "Formation would place models outside deployment zone or overlapping"
			break

	if not all_valid:
		_show_toast(error_msg)
		return

	# Place all models
	for i in range(positions.size()):
		var idx = remaining_indices[i]
		temp_positions[idx] = positions[i]
		temp_rotations[idx] = 0.0
		_spawn_preview_token(unit_id, idx, positions[i], 0.0)

	# Update model_idx to next unplaced model
	if models_to_place < remaining_indices.size():
		model_idx = remaining_indices[models_to_place]
	else:
		model_idx = temp_positions.size()

	_check_coherency_warning()
	emit_signal("models_placed_changed")

	# Update or clear ghosts
	if model_idx < temp_positions.size():
		if formation_mode == "SINGLE":
			_update_ghost_for_next_model()
		else:
			_create_formation_ghosts(formation_size)
	else:
		_clear_formation_ghosts()
		_remove_ghost()

func undo() -> void:
	_clear_previews()
	temp_positions.fill(null)
	temp_rotations.fill(0.0)  # Reset rotations to default
	model_idx = 0

	# Update through PhaseManager instead of BoardState
	if has_node("/root/PhaseManager"):
		var phase_manager = get_node("/root/PhaseManager")
		if phase_manager.current_phase_instance:
			phase_manager.apply_state_changes([{
				"op": "set",
				"path": "units.%s.status" % unit_id,
				"value": GameStateData.UnitStatus.UNDEPLOYED
			}])

	unit_id = ""
	_clear_formation_ghosts()  # Clear any formation ghosts
	_remove_ghost()

func confirm() -> void:
	# Check if this is a transport - if so, show embark dialog FIRST
	if _is_transport(unit_id) and not is_awaiting_embark_dialog:
		DebugLogger.info("Transport being deployed - showing embark dialog before confirmation", {
			"unit_id": unit_id
		})
		is_awaiting_embark_dialog = true
		_show_transport_embark_dialog()
		return  # Don't proceed with deployment yet - wait for dialog

	# Proceed with actual deployment (called either directly for non-transports, or after embark dialog closes)
	_complete_deployment()

func _is_transport(unit_id: String) -> bool:
	var unit = GameState.get_unit(unit_id)
	return unit.has("transport_data") and unit.transport_data.get("capacity", 0) > 0

func _show_transport_embark_dialog() -> void:
	DebugLogger.info("Creating transport embark dialog", {"unit_id": unit_id})

	var dialog_script = load("res://scripts/TransportEmbarkDialog.gd")
	var dialog = dialog_script.new()
	dialog.setup(unit_id)
	dialog.units_selected.connect(_on_embark_units_selected)

	# Add to scene tree and show
	get_tree().root.add_child(dialog)
	dialog.popup_centered()

func _on_embark_units_selected(unit_ids: Array) -> void:
	DebugLogger.info("Embark dialog closed", {
		"transport_id": unit_id,
		"selected_units": unit_ids,
		"count": unit_ids.size()
	})

	# Store units to embark AFTER deployment completes
	pending_embark_units = unit_ids
	is_awaiting_embark_dialog = false

	# Now proceed with actual deployment
	_complete_deployment()

func _complete_deployment() -> void:
	# In multiplayer, verify it's still our turn before submitting
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.is_networked() and not network_manager.is_local_player_turn():
		print("[DeploymentController] ERROR: Attempted deployment when not your turn")
		push_error("Cannot deploy - not your turn")
		return

	# Create deployment action for PhaseManager
	var model_positions = []
	for pos in temp_positions:
		model_positions.append(pos)

	# Note: Don't set "player" here - NetworkIntegration will add the correct local player ID
	# This ensures the action uses the actual local player, not just whoever's turn it is
	var deployment_action = {
		"type": "DEPLOY_UNIT",
		"unit_id": unit_id,
		"model_positions": model_positions,
		"model_rotations": temp_rotations,  # Added to fix Battlewagon save/load issue
		"phase": GameStateData.Phase.DEPLOYMENT,
		"timestamp": Time.get_unix_time_from_system()
	}

	# Route through NetworkIntegration (handles multiplayer and single-player)
	var result = NetworkIntegration.route_action(deployment_action)

	if result.success:
		if result.get("pending", false):
			print("[DeploymentController] Deployment submitted to network for unit: ", unit_id)
		else:
			print("[DeploymentController] Deployment successful for unit: ", unit_id)
			print("[DeploymentController] Action should trigger turn switch")

		# Handle embarkation if units were selected
		if pending_embark_units.size() > 0:
			print("[DeploymentController] ===== EMBARKATION TRIGGERED =====")
			print("[DeploymentController] Transport: %s, Units: %s" % [unit_id, str(pending_embark_units)])

			DebugLogger.info("Processing embarkation for selected units", {
				"transport_id": unit_id,
				"units_to_embark": pending_embark_units
			})

			# Check if we're in multiplayer mode
			var network_manager = get_node_or_null("/root/NetworkManager")
			var is_networked = network_manager != null and network_manager.is_networked()

			print("[DeploymentController] NetworkManager found: %s, is_networked: %s" % [str(network_manager != null), str(is_networked)])

			if is_networked:
				# In multiplayer, send action for synchronization
				print("[DeploymentController] MULTIPLAYER MODE - sending embarkation action")
				_send_embarkation_action(unit_id, pending_embark_units)
			else:
				# In single-player, execute directly for immediate effect
				print("[DeploymentController] SINGLE-PLAYER MODE - processing embarkation directly")
				_process_embarkation(unit_id, pending_embark_units)

			pending_embark_units = []
			print("[DeploymentController] ===== EMBARKATION COMPLETE =====")
		else:
			print("[DeploymentController] No pending embark units (size: %d)" % pending_embark_units.size())
	else:
		print("[DeploymentController] ERROR - Deployment failed for unit: ", unit_id)
		print("[DeploymentController] Errors: ", result.get("errors", []))
		push_error("Deployment failed: " + str(result.get("error", "Unknown error")))

	_finalize_tokens()
	_clear_previews()
	_remove_ghost()

	unit_id = ""
	model_idx = -1
	temp_positions.clear()
	temp_rotations.clear()  # Added to properly clear rotations

	emit_signal("unit_confirmed")

	if GameState.all_units_deployed():
		emit_signal("deployment_complete")

func _send_embarkation_action(transport_id: String, unit_ids: Array) -> void:
	"""Send embarkation action through network sync (multiplayer only)"""
	# Note: Don't set "player" here - NetworkIntegration will add the correct local player ID
	var embark_action = {
		"type": "EMBARK_UNITS_DEPLOYMENT",
		"transport_id": transport_id,
		"unit_ids": unit_ids,
		"phase": GameStateData.Phase.DEPLOYMENT,
		"timestamp": Time.get_unix_time_from_system()
	}

	var result = NetworkIntegration.route_action(embark_action)

	if result.success:
		DebugLogger.info("Embarkation action sent successfully", {
			"transport_id": transport_id,
			"unit_count": unit_ids.size()
		})
	else:
		push_error("Embarkation action failed: " + str(result.get("error", "Unknown")))
		DebugLogger.error("Failed to send embarkation action", {
			"transport_id": transport_id,
			"unit_ids": unit_ids,
			"error": result.get("error", "Unknown")
		})

func _process_embarkation(transport_id: String, unit_ids: Array) -> void:
	"""Process embarkation directly (single-player mode)"""
	print("[DeploymentController] _process_embarkation called with transport: %s, units: %s" % [transport_id, str(unit_ids)])

	for unit_id in unit_ids:
		print("[DeploymentController] Processing embarkation for unit: %s" % unit_id)

		# Check if unit exists and is undeployed
		var unit = GameState.get_unit(unit_id)
		if unit.is_empty():
			push_error("[DeploymentController] Unit not found: %s" % unit_id)
			continue

		var unit_status = unit.get("status", -1)
		print("[DeploymentController] Unit %s status before embark: %d (0=UNDEPLOYED, 1=DEPLOYING, 2=DEPLOYED)" % [unit_id, unit_status])

		# Use TransportManager to handle the embarkation
		var can_embark_result = TransportManager.can_embark(unit_id, transport_id)
		print("[DeploymentController] Can embark? %s" % str(can_embark_result))

		if can_embark_result.valid:
			TransportManager.embark_unit(unit_id, transport_id)
			print("[DeploymentController] embark_unit() called successfully")
		else:
			push_error("[DeploymentController] Cannot embark %s: %s" % [unit_id, can_embark_result.reason])
			continue

		# Mark embarked units as deployed via PhaseManager
		if has_node("/root/PhaseManager"):
			var phase_manager = get_node("/root/PhaseManager")
			if phase_manager.current_phase_instance:
				phase_manager.apply_state_changes([{
					"op": "set",
					"path": "units.%s.status" % unit_id,
					"value": GameStateData.UnitStatus.DEPLOYED
				}])
				print("[DeploymentController] Set status to DEPLOYED for %s" % unit_id)

		# Verify embarkation
		unit = GameState.get_unit(unit_id)
		var embarked_in = unit.get("embarked_in", null)
		var final_status = unit.get("status", -1)
		print("[DeploymentController] After embark - embarked_in: %s, status: %d" % [str(embarked_in), final_status])

		var unit_name = unit.get("meta", {}).get("name", unit_id)
		print("[DeploymentController] Embarked %s in %s" % [unit_name, transport_id])

func _create_ghost() -> void:
	if ghost_sprite != null:
		ghost_sprite.queue_free()

	ghost_sprite = preload("res://scripts/GhostVisual.gd").new()
	ghost_sprite.name = "GhostPreview"

	var unit_data = GameState.get_unit(unit_id)
	if model_idx < unit_data["models"].size():
		var model_data = unit_data["models"][model_idx]
		ghost_sprite.owner_player = unit_data["owner"]
		# Set the complete model data for shape handling
		ghost_sprite.set_model_data(model_data)

	ghost_layer.add_child(ghost_sprite)

func _remove_ghost() -> void:
	if ghost_sprite != null:
		ghost_sprite.queue_free()
		ghost_sprite = null

func _update_ghost_for_next_model() -> void:
	if ghost_sprite == null:
		return

	var unit_data = GameState.get_unit(unit_id)
	if model_idx < unit_data["models"].size():
		var model_data = unit_data["models"][model_idx]
		# Update model data for the next model
		ghost_sprite.set_model_data(model_data)
		# Reset rotation for new model
		ghost_sprite.set_base_rotation(0.0)
		ghost_sprite.queue_redraw()

func _spawn_preview_token(unit_id: String, model_index: int, pos: Vector2, rotation: float = 0.0) -> void:
	var token = _create_token_visual(unit_id, model_index, pos, true, rotation)
	placed_tokens.append(token)
	token_layer.add_child(token)

func _create_token_visual(unit_id: String, model_index: int, pos: Vector2, is_preview: bool = false, rotation: float = 0.0) -> Node2D:
	var token = Node2D.new()
	token.position = pos
	token.name = "Token_%s_%d" % [unit_id, model_index]

	var unit_data = GameState.get_unit(unit_id)
	var model_data = unit_data["models"][model_index].duplicate()
	# Add rotation to model data
	model_data["rotation"] = rotation
	var base_mm = model_data["base_mm"]
	var base_circle = preload("res://scripts/TokenVisual.gd").new()
	base_circle.owner_player = unit_data["owner"]
	base_circle.is_preview = is_preview
	base_circle.model_number = model_index + 1
	# Set the complete model data for shape handling
	base_circle.set_model_data(model_data)

	token.add_child(base_circle)

	return token

func _clear_previews() -> void:
	for token in placed_tokens:
		if is_instance_valid(token):
			token.queue_free()
	placed_tokens.clear()

func _finalize_tokens() -> void:
	for token in placed_tokens:
		if is_instance_valid(token):
			for child in token.get_children():
				if child.has_method("set_preview"):
					child.set_preview(false)
	placed_tokens.clear()

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

func _check_coherency_warning() -> void:
	var placed_positions = []
	for pos in temp_positions:
		if pos != null:
			placed_positions.append(pos)
	
	if placed_positions.size() < 2:
		return
	
	var incoherent = false
	
	if placed_positions.size() <= 6:
		for pos in placed_positions:
			var has_neighbor = false
			for other_pos in placed_positions:
				if pos != other_pos:
					var dist_inches = Measurement.distance_inches(pos, other_pos)
					if dist_inches <= 2.0:
						has_neighbor = true
						break
			if not has_neighbor:
				incoherent = true
				break
	else:
		for pos in placed_positions:
			var neighbor_count = 0
			for other_pos in placed_positions:
				if pos != other_pos:
					var dist_inches = Measurement.distance_inches(pos, other_pos)
					if dist_inches <= 2.0:
						neighbor_count += 1
			if neighbor_count < 2:
				incoherent = true
				break
	
	if incoherent:
		_show_toast("Warning: Some models >2″ from unit mates", Color.YELLOW)

func _shape_wholly_in_polygon(center: Vector2, model_data: Dictionary, rotation: float, polygon: PackedVector2Array) -> bool:
	# Create the base shape
	var shape = Measurement.create_base_shape(model_data)
	if not shape:
		return false

	# For circular, use existing method
	if shape.get_type() == "circular":
		var circular = shape as CircularBase
		return _circle_wholly_in_polygon(center, circular.radius, polygon)

	# For non-circular shapes, we need to check multiple points around the edge
	print("\n=== DEBUG: Zone Validation for %s ===" % shape.get_type())
	print("Center: ", center)
	print("Rotation: %.2f degrees (%.4f radians)" % [rad_to_deg(rotation), rotation])

	# Generate sample points around the shape's edge
	var sample_points = []

	if shape.get_type() == "oval":
		# For ovals, sample points around the ellipse perimeter
		var oval = shape as OvalBase
		var num_samples = 16  # Check 16 points around the ellipse
		print("Oval shape - length: %.2f, width: %.2f" % [oval.length, oval.width])

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

	print("Checking %d sample points" % sample_points.size())

	# Transform sample points to world space and check if in polygon
	var point_idx = 0
	for local_point in sample_points:
		var world_point = shape.to_world_space(local_point, center, rotation)
		var in_poly = Geometry2D.is_point_in_polygon(world_point, polygon)

		if point_idx < 4 or not in_poly:  # Only print first 4 and failures
			print("Point %d: local=%s -> world=%s, in_polygon=%s" % [point_idx, local_point, world_point, in_poly])

		if not in_poly:
			print("❌ FAILED: Point outside polygon")
			return false

		point_idx += 1

	print("✅ SUCCESS: All %d points in polygon" % sample_points.size())
	return true

func _overlaps_with_existing_models_shape(pos: Vector2, model_data: Dictionary, rotation: float) -> bool:
	var shape = Measurement.create_base_shape(model_data)
	if not shape:
		return false

	# Check overlap with already placed models in current unit
	var unit_data = GameState.get_unit(unit_id)
	for i in range(temp_positions.size()):
		if temp_positions[i] != null:
			var other_model_data = unit_data["models"][i]
			var other_rotation = temp_rotations[i] if i < temp_rotations.size() else 0.0
			if _shapes_overlap(pos, model_data, rotation, temp_positions[i], other_model_data, other_rotation):
				return true

	# Check overlap with all deployed models from all units
	var all_units = GameState.state.get("units", {})
	for other_unit_id in all_units:
		var other_unit = all_units[other_unit_id]
		if other_unit["status"] == GameStateData.UnitStatus.DEPLOYED:
			for model in other_unit["models"]:
				var model_position = model.get("position", null)
				if model_position:
					var other_pos = Vector2(model_position.x, model_position.y)
					var other_rotation = model.get("rotation", 0.0)
					if _shapes_overlap(pos, model_data, rotation, other_pos, model, other_rotation):
						return true

	return false

func _shapes_overlap(pos1: Vector2, model1: Dictionary, rot1: float, pos2: Vector2, model2: Dictionary, rot2: float) -> bool:
	# Use actual shape collision detection from BaseShape API
	var shape1 = Measurement.create_base_shape(model1)
	var shape2 = Measurement.create_base_shape(model2)

	if not shape1 or not shape2:
		return false

	# Use shape-aware collision (works for all shape combinations)
	return shape1.overlaps_with(shape2, pos1, rot1, pos2, rot2)

func _get_shape_max_extent(model_data: Dictionary) -> float:
	"""Get maximum extent of a model's base shape for spacing calculations"""
	var shape = Measurement.create_base_shape(model_data)
	if not shape:
		# Fallback to circular assumption
		return Measurement.base_radius_px(model_data.get("base_mm", 32))

	var bounds = shape.get_bounds()
	return max(bounds.size.x, bounds.size.y)

func _overlaps_with_existing_models(pos: Vector2, radius: float) -> bool:
	# Check overlap with already placed models in current unit
	for placed_pos in temp_positions:
		if placed_pos != null:
			var distance = pos.distance_to(placed_pos)
			var other_radius = radius  # Same unit, same base size
			if distance < (radius + other_radius):
				return true

	# Check overlap with all deployed models from all units
	var all_units = GameState.state.get("units", {})
	for other_unit_id in all_units:
		var other_unit = all_units[other_unit_id]
		if other_unit["status"] == GameStateData.UnitStatus.DEPLOYED:
			for model in other_unit["models"]:
				var model_position = model.get("position", null)
				if model_position != null:
					var model_pos = Vector2(model_position.get("x", 0), model_position.get("y", 0))
					var distance = pos.distance_to(model_pos)
					var other_radius = Measurement.base_radius_px(model["base_mm"])
					if distance < (radius + other_radius):
						return true
	
	return false

func _show_toast(message: String, color: Color = Color.RED) -> void:
	print("[%s] %s" % ["WARNING" if color == Color.YELLOW else "ERROR", message])

func _dict_array_to_packed_vector2(dict_array: Array) -> PackedVector2Array:
	var packed = PackedVector2Array()
	for dict in dict_array:
		if dict is Dictionary and dict.has("x") and dict.has("y"):
			packed.append(Vector2(dict.x, dict.y))
	return packed

func _process(delta: float) -> void:
	if not is_placing():
		return

	var mouse_pos = _get_world_mouse_position()

	# Handle repositioning ghost updates (highest priority)
	if repositioning_model and reposition_ghost:
		reposition_ghost.position = mouse_pos
		var unit_data = GameState.get_unit(unit_id)
		var model_data = unit_data["models"][reposition_model_index]
		var is_valid = _validate_reposition(mouse_pos, model_data, reposition_model_index)
		reposition_ghost.set_validity(is_valid)
		return

	# Handle formation mode ghost updates
	if formation_mode != "SINGLE" and not formation_preview_ghosts.is_empty():
		_update_formation_ghost_positions(mouse_pos)
		return

	# Handle single mode ghost updates
	if ghost_sprite != null and model_idx < temp_positions.size():
		ghost_sprite.position = mouse_pos

		var unit_data = GameState.get_unit(unit_id)
		var model_data = unit_data["models"][model_idx]
		var active_player = GameState.get_active_player()
		var zone = BoardState.get_deployment_zone_for_player(active_player)

		# Get current rotation from ghost
		var rotation = 0.0
		if ghost_sprite.has_method("get_base_rotation"):
			rotation = ghost_sprite.get_base_rotation()

		# Check both deployment zone and model overlap based on shape
		var is_valid = false
		var base_type = model_data.get("base_type", "circular")

		if base_type == "circular":
			var radius_px = Measurement.base_radius_px(model_data["base_mm"])
			is_valid = _circle_wholly_in_polygon(mouse_pos, radius_px, zone) and not _overlaps_with_existing_models(mouse_pos, radius_px)
		else:
			is_valid = _shape_wholly_in_polygon(mouse_pos, model_data, rotation, zone) and not _overlaps_with_existing_models_shape(mouse_pos, model_data, rotation)

		# Also check wall collision
		if is_valid:
			var test_model = model_data.duplicate()
			test_model["position"] = mouse_pos
			test_model["rotation"] = rotation
			if Measurement.model_overlaps_any_wall(test_model):
				is_valid = false

		if ghost_sprite.has_method("set_validity"):
			ghost_sprite.set_validity(is_valid)

func _get_world_mouse_position() -> Vector2:
	# Get the main scene to access the coordinate conversion
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("screen_to_world_position"):
		var screen_pos = get_viewport().get_mouse_position()
		return main_scene.screen_to_world_position(screen_pos)
	else:
		# Fallback to simple mouse position
		return get_viewport().get_mouse_position()

# Formation mode management
func set_formation_mode(mode: String) -> void:
	formation_mode = mode
	formation_rotation = 0.0  # Reset rotation when changing modes
	print("[DeploymentController] Formation mode set to: ", mode)

	# If we're currently placing, update the ghosts
	if is_placing():
		if mode == "SINGLE":
			_clear_formation_ghosts()
			if not ghost_sprite:
				_create_ghost()
		else:
			_remove_ghost()
			var remaining = _get_unplaced_model_indices()
			if not remaining.is_empty():
				_create_formation_ghosts(min(formation_size, remaining.size()))

func _get_unplaced_model_indices() -> Array:
	"""Get indices of models that haven't been placed yet"""
	var unplaced = []
	for i in range(temp_positions.size()):
		if temp_positions[i] == null:
			unplaced.append(i)
	return unplaced

# Formation calculation functions
func calculate_spread_formation(anchor_pos: Vector2, model_count: int, base_mm: int, rotation: float = 0.0) -> Array:
	"""Calculate positions for maximum spread (2 inch coherency)"""
	var positions = []

	# Get first model data to determine base type
	var unit_data = GameState.get_unit(unit_id)
	var remaining_indices = _get_unplaced_model_indices()
	if remaining_indices.is_empty():
		return positions

	var model_data = unit_data["models"][remaining_indices[0]]
	var shape = Measurement.create_base_shape(model_data)

	# Use bounding box for spacing calculations
	var bounds = shape.get_bounds()
	var spacing_inches = 2.0  # Maximum coherency distance
	var spacing_px = Measurement.inches_to_px(spacing_inches)

	# For spacing, use the maximum dimension of the base
	var base_extent = max(bounds.size.x, bounds.size.y)
	var total_spacing = spacing_px + base_extent

	# Arrange in rows of 5
	var cols = min(5, model_count)
	var rows = ceil(model_count / 5.0)

	for i in range(model_count):
		var col = i % cols
		var row = floor(i / cols)
		var x_offset = (col - cols/2.0) * total_spacing
		var y_offset = row * total_spacing
		var base_pos = Vector2(x_offset, y_offset)

		# Apply rotation around origin, then translate to anchor
		var rotated_pos = base_pos.rotated(rotation)
		positions.append(anchor_pos + rotated_pos)

	return positions

func calculate_tight_formation(anchor_pos: Vector2, model_count: int, base_mm: int, rotation: float = 0.0) -> Array:
	"""Calculate positions for tight formation (bases touching)"""
	var positions = []

	# Get first model data to determine base type
	var unit_data = GameState.get_unit(unit_id)
	var remaining_indices = _get_unplaced_model_indices()
	if remaining_indices.is_empty():
		return positions

	var model_data = unit_data["models"][remaining_indices[0]]
	var shape = Measurement.create_base_shape(model_data)

	# Use bounding box for spacing calculations
	var bounds = shape.get_bounds()

	# For tight formation, use actual dimensions plus minimal gap
	var base_extent = max(bounds.size.x, bounds.size.y)
	var spacing_px = base_extent + 1  # 1px gap to prevent overlap

	# Arrange in rows of 5
	var cols = min(5, model_count)
	var rows = ceil(model_count / 5.0)

	for i in range(model_count):
		var col = i % cols
		var row = floor(i / cols)
		var x_offset = (col - cols/2.0) * spacing_px
		var y_offset = row * spacing_px
		var base_pos = Vector2(x_offset, y_offset)

		# Apply rotation around origin, then translate to anchor
		var rotated_pos = base_pos.rotated(rotation)
		positions.append(anchor_pos + rotated_pos)

	return positions

# Formation ghost management
func _create_formation_ghosts(count: int) -> void:
	"""Create multiple ghost visuals for formation preview"""
	_clear_formation_ghosts()

	var unit_data = GameState.get_unit(unit_id)
	var remaining_models = _get_unplaced_model_indices()
	var models_to_place = min(count, remaining_models.size())

	for i in range(models_to_place):
		var model_index = remaining_models[i]
		var model_data = unit_data["models"][model_index]
		var ghost = preload("res://scripts/GhostVisual.gd").new()
		ghost.name = "FormationGhost_%d" % i
		ghost.owner_player = unit_data["owner"]
		ghost.set_model_data(model_data)
		ghost.modulate.a = 0.6  # Slightly transparent for formation ghosts
		ghost_layer.add_child(ghost)
		formation_preview_ghosts.append(ghost)

func _clear_formation_ghosts() -> void:
	"""Remove all formation ghost visuals"""
	for ghost in formation_preview_ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	formation_preview_ghosts.clear()

func _update_formation_ghost_positions(mouse_pos: Vector2) -> void:
	"""Update positions of all formation ghosts"""
	if formation_preview_ghosts.is_empty():
		return

	var unit_data = GameState.get_unit(unit_id)
	var remaining_models = _get_unplaced_model_indices()
	if remaining_models.is_empty():
		return

	var model_data = unit_data["models"][remaining_models[0]]
	var base_mm = model_data["base_mm"]

	var positions = []
	match formation_mode:
		"SPREAD":
			positions = calculate_spread_formation(mouse_pos, formation_preview_ghosts.size(), base_mm, formation_rotation)
		"TIGHT":
			positions = calculate_tight_formation(mouse_pos, formation_preview_ghosts.size(), base_mm, formation_rotation)

	# Update ghost positions and validity
	var zone = BoardState.get_deployment_zone_for_player(GameState.get_active_player())
	for i in range(formation_preview_ghosts.size()):
		var ghost = formation_preview_ghosts[i]
		if i < positions.size():
			ghost.position = positions[i]
			ghost.visible = true

			# Check validity for each ghost position
			var is_valid = _validate_formation_position(positions[i], model_data, zone)
			ghost.set_validity(is_valid)

func _validate_formation_position(pos: Vector2, model_data: Dictionary, zone: PackedVector2Array) -> bool:
	"""Validate a single position in a formation"""
	var base_type = model_data.get("base_type", "circular")

	if base_type == "circular":
		var radius_px = Measurement.base_radius_px(model_data["base_mm"])
		if not _circle_wholly_in_polygon(pos, radius_px, zone):
			return false
		if _overlaps_with_existing_models(pos, radius_px):
			return false
	else:
		# For non-circular bases, use shape-aware validation
		if not _shape_wholly_in_polygon(pos, model_data, 0.0, zone):
			return false
		if _overlaps_with_existing_models_shape(pos, model_data, 0.0):
			return false

	# Check wall collision
	var test_model = model_data.duplicate()
	test_model["position"] = pos
	test_model["rotation"] = 0.0
	if Measurement.model_overlaps_any_wall(test_model):
		return false

	return true

# Model Repositioning Functions
func _get_deployed_model_at_position(world_pos: Vector2) -> Dictionary:
	"""Find deployed model from current unit at given position"""
	if unit_id == "" or temp_positions.is_empty():
		return {}

	var unit_data = GameState.get_unit(unit_id)
	for i in range(temp_positions.size()):
		if temp_positions[i] != null:  # Model is placed
			var model_pos = temp_positions[i]
			var model_data = unit_data["models"][i]
			var rotation = temp_rotations[i] if i < temp_rotations.size() else 0.0

			# Use shape-aware hit detection
			var shape = Measurement.create_base_shape(model_data)
			if shape and shape.contains_point(world_pos, model_pos, rotation):
				return {
					"model_index": i,
					"position": model_pos,
					"model_data": model_data
				}

	return {}

func _start_model_repositioning(deployed_model: Dictionary) -> void:
	"""Begin repositioning a deployed model"""
	repositioning_model = true
	reposition_model_index = deployed_model.model_index
	reposition_start_pos = deployed_model.position

	print("Starting repositioning of model ", reposition_model_index)

	# Create ghost visual for repositioning
	var model_data = deployed_model.model_data
	reposition_ghost = preload("res://scripts/GhostVisual.gd").new()
	reposition_ghost.name = "RepositionGhost"
	reposition_ghost.owner_player = GameState.get_active_player()
	reposition_ghost.set_model_data(model_data)
	ghost_layer.add_child(reposition_ghost)

	# Make the original token semi-transparent during repositioning
	for token in placed_tokens:
		if is_instance_valid(token) and token.name == "Token_%s_%d" % [unit_id, reposition_model_index]:
			token.modulate.a = 0.3  # Make original semi-transparent
			break

func _update_model_repositioning(mouse_pos: Vector2) -> void:
	"""Update ghost position during repositioning"""
	if not repositioning_model or not reposition_ghost:
		return

	var world_pos = _get_world_mouse_position()
	reposition_ghost.position = world_pos

	# Validate new position
	var unit_data = GameState.get_unit(unit_id)
	var model_data = unit_data["models"][reposition_model_index]
	var is_valid = _validate_reposition(world_pos, model_data, reposition_model_index)

	reposition_ghost.set_validity(is_valid)

func _validate_reposition(world_pos: Vector2, model_data: Dictionary, model_index: int) -> bool:
	"""Validate if repositioning is allowed at the given position"""
	var active_player = GameState.get_active_player()
	var zone = BoardState.get_deployment_zone_for_player(active_player)
	var base_type = model_data.get("base_type", "circular")

	# Check deployment zone
	var in_zone = false
	if base_type == "circular":
		var radius_px = Measurement.base_radius_px(model_data["base_mm"])
		in_zone = _circle_wholly_in_polygon(world_pos, radius_px, zone)
	else:
		var rotation = temp_rotations[model_index] if model_index < temp_rotations.size() else 0.0
		in_zone = _shape_wholly_in_polygon(world_pos, model_data, rotation, zone)

	if not in_zone:
		return false

	# Check overlap (excluding the model being repositioned)
	return not _would_overlap_excluding_self(world_pos, model_data, model_index)

func _would_overlap_excluding_self(pos: Vector2, model_data: Dictionary, exclude_index: int) -> bool:
	"""Check for overlaps excluding the model being repositioned"""
	var shape = Measurement.create_base_shape(model_data)
	if not shape:
		return false

	# Check overlap with other models in current unit (excluding self)
	var unit_data = GameState.get_unit(unit_id)
	for i in range(temp_positions.size()):
		if i != exclude_index and temp_positions[i] != null:
			var other_model_data = unit_data["models"][i]
			var other_rotation = temp_rotations[i] if i < temp_rotations.size() else 0.0
			var self_rotation = temp_rotations[exclude_index] if exclude_index < temp_rotations.size() else 0.0
			if _shapes_overlap(pos, model_data, self_rotation, temp_positions[i], other_model_data, other_rotation):
				return true

	# Check overlap with all deployed models from other units
	var all_units = GameState.state.get("units", {})
	for other_unit_id in all_units:
		if other_unit_id == unit_id:
			continue  # Skip current unit, already checked above

		var other_unit = all_units[other_unit_id]
		if other_unit["status"] == GameStateData.UnitStatus.DEPLOYED:
			for model in other_unit["models"]:
				var model_position = model.get("position", null)
				if model_position:
					var other_pos = Vector2(model_position.x, model_position.y)
					var other_rotation = model.get("rotation", 0.0)
					var self_rotation = temp_rotations[exclude_index] if exclude_index < temp_rotations.size() else 0.0
					if _shapes_overlap(pos, model_data, self_rotation, other_pos, model, other_rotation):
						return true

	return false

func _end_model_repositioning(mouse_pos: Vector2) -> void:
	"""Complete model repositioning"""
	if not repositioning_model:
		return

	var world_pos = _get_world_mouse_position()
	var unit_data = GameState.get_unit(unit_id)
	var model_data = unit_data["models"][reposition_model_index]

	# Validate final position
	if _validate_reposition(world_pos, model_data, reposition_model_index):
		# Update position
		temp_positions[reposition_model_index] = world_pos

		# Update the token position
		for token in placed_tokens:
			if is_instance_valid(token) and token.name == "Token_%s_%d" % [unit_id, reposition_model_index]:
				token.position = world_pos
				token.modulate.a = 1.0  # Restore full opacity
				break

		print("Model ", reposition_model_index, " repositioned to ", world_pos)
		emit_signal("models_placed_changed")
		_check_coherency_warning()
	else:
		# Revert to original position
		for token in placed_tokens:
			if is_instance_valid(token) and token.name == "Token_%s_%d" % [unit_id, reposition_model_index]:
				token.modulate.a = 1.0  # Restore full opacity
				break
		_show_toast("Invalid position for repositioning")

	_cleanup_repositioning()

func _cancel_model_repositioning() -> void:
	"""Cancel model repositioning and restore original state"""
	if not repositioning_model:
		return

	# Restore original token opacity
	for token in placed_tokens:
		if is_instance_valid(token) and token.name == "Token_%s_%d" % [unit_id, reposition_model_index]:
			token.modulate.a = 1.0
			break

	_cleanup_repositioning()

func _cleanup_repositioning() -> void:
	"""Clean up repositioning state"""
	repositioning_model = false
	reposition_model_index = -1
	reposition_start_pos = Vector2.ZERO

	if reposition_ghost and is_instance_valid(reposition_ghost):
		reposition_ghost.queue_free()
		reposition_ghost = null
