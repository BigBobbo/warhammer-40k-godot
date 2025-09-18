extends Node

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

func _ready() -> void:
	set_process(true)
	set_process_unhandled_input(true)

func set_layers(tokens: Node2D, ghosts: Node2D) -> void:
	token_layer = tokens
	ghost_layer = ghosts

func _unhandled_input(event: InputEvent) -> void:
	if not is_placing():
		return

	# Check if we have ghosts to work with
	if not ghost_sprite and formation_preview_ghosts.is_empty():
		return

	# Handle clicks for formation placement
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var mouse_pos = _get_world_mouse_position()
			if formation_mode != "SINGLE":
				try_place_formation_at(mouse_pos)
			else:
				try_place_at(mouse_pos)
			return

	# Handle rotation controls during deployment (single mode only)
	if formation_mode == "SINGLE" and ghost_sprite and event is InputEventKey and event.pressed:
		if event.keycode == KEY_Q:
			# Rotate left
			if ghost_sprite.has_method("rotate_by"):
				ghost_sprite.rotate_by(-PI/12)  # 15 degrees
		elif event.keycode == KEY_E:
			# Rotate right
			if ghost_sprite.has_method("rotate_by"):
				ghost_sprite.rotate_by(PI/12)  # 15 degrees
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			# Rotate with mouse wheel
			if ghost_sprite.has_method("rotate_by"):
				ghost_sprite.rotate_by(PI/12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if ghost_sprite.has_method("rotate_by"):
				ghost_sprite.rotate_by(-PI/12)

func begin_deploy(_unit_id: String) -> void:
	unit_id = _unit_id
	model_idx = 0
	temp_positions.clear()
	temp_rotations.clear()
	var unit_data = GameState.get_unit(unit_id)
	temp_positions.resize(unit_data["models"].size())
	temp_rotations.resize(unit_data["models"].size())
	temp_rotations.fill(0.0)

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
			positions = calculate_spread_formation(world_pos, models_to_place, base_mm)
		"TIGHT":
			positions = calculate_tight_formation(world_pos, models_to_place, base_mm)

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
	# Create deployment action for PhaseManager
	var model_positions = []
	for pos in temp_positions:
		model_positions.append(pos)
	
	var deployment_action = {
		"type": "DEPLOY_UNIT",
		"unit_id": unit_id,
		"model_positions": model_positions,
		"model_rotations": temp_rotations,  # Added to fix Battlewagon save/load issue
		"phase": GameStateData.Phase.DEPLOYMENT,
		"player": GameState.get_active_player(),
		"timestamp": Time.get_unix_time_from_system()
	}
	
	# Execute through PhaseManager
	if has_node("/root/PhaseManager"):
		var phase_manager = get_node("/root/PhaseManager")
		if phase_manager.current_phase_instance and phase_manager.current_phase_instance.has_method("execute_action"):
			var result = phase_manager.current_phase_instance.execute_action(deployment_action)
			if result.success:
				print("[DeploymentController] Deployment successful for unit: ", unit_id)
				print("[DeploymentController] Action should trigger turn switch")
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

func _create_ghost() -> void:
	if ghost_sprite != null:
		ghost_sprite.queue_free()

	ghost_sprite = preload("res://scripts/GhostVisual.gd").new()
	ghost_sprite.name = "GhostPreview"

	var unit_data = GameState.get_unit(unit_id)
	if model_idx < unit_data["models"].size():
		var model_data = unit_data["models"][model_idx]
		var base_mm = model_data["base_mm"]
		ghost_sprite.radius = Measurement.base_radius_px(base_mm)
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
		var base_mm = model_data["base_mm"]
		ghost_sprite.radius = Measurement.base_radius_px(base_mm)
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
	var radius_px = Measurement.base_radius_px(base_mm)

	var base_circle = preload("res://scripts/TokenVisual.gd").new()
	base_circle.radius = radius_px
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
		return _circle_wholly_in_polygon(center, shape.radius, polygon)

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
	# Simple distance check for now - can be improved with actual shape collision
	var shape1 = Measurement.create_base_shape(model1)
	var shape2 = Measurement.create_base_shape(model2)

	if not shape1 or not shape2:
		return false

	# For simplicity, use bounding circle check
	var radius1 = _get_bounding_radius(shape1)
	var radius2 = _get_bounding_radius(shape2)

	return pos1.distance_to(pos2) < (radius1 + radius2)

func _get_bounding_radius(shape: BaseShape) -> float:
	var bounds = shape.get_bounds()
	return max(bounds.size.x, bounds.size.y) / 2.0

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
func calculate_spread_formation(anchor_pos: Vector2, model_count: int, base_mm: int) -> Array:
	"""Calculate positions for maximum spread (2 inch coherency)"""
	var positions = []
	var base_radius = Measurement.base_radius_px(base_mm)
	var spacing_inches = 2.0  # Maximum coherency distance
	var spacing_px = Measurement.inches_to_px(spacing_inches)
	var total_spacing = spacing_px + (base_radius * 2)

	# Arrange in rows of 5
	var cols = min(5, model_count)
	var rows = ceil(model_count / 5.0)

	for i in range(model_count):
		var col = i % cols
		var row = floor(i / cols)
		var x_offset = (col - cols/2.0) * total_spacing
		var y_offset = row * total_spacing
		positions.append(anchor_pos + Vector2(x_offset, y_offset))

	return positions

func calculate_tight_formation(anchor_pos: Vector2, model_count: int, base_mm: int) -> Array:
	"""Calculate positions for tight formation (bases touching)"""
	var positions = []
	var base_radius = Measurement.base_radius_px(base_mm)
	var spacing_px = base_radius * 2 + 1  # 1px gap to prevent overlap

	# Arrange in rows of 5
	var cols = min(5, model_count)
	var rows = ceil(model_count / 5.0)

	for i in range(model_count):
		var col = i % cols
		var row = floor(i / cols)
		var x_offset = (col - cols/2.0) * spacing_px
		var y_offset = row * spacing_px
		positions.append(anchor_pos + Vector2(x_offset, y_offset))

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
		ghost.radius = Measurement.base_radius_px(model_data["base_mm"])
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
			positions = calculate_spread_formation(mouse_pos, formation_preview_ghosts.size(), base_mm)
		"TIGHT":
			positions = calculate_tight_formation(mouse_pos, formation_preview_ghosts.size(), base_mm)

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

	return true
