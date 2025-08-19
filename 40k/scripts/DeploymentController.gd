extends Node

signal deployment_complete()
signal unit_confirmed()
signal models_placed_changed()

var unit_id: String = ""
var model_idx: int = -1
var temp_positions: Array = []
var token_layer: Node2D
var ghost_layer: Node2D
var ghost_sprite: Node2D = null
var placed_tokens: Array = []

func _ready() -> void:
	set_process(true)

func set_layers(tokens: Node2D, ghosts: Node2D) -> void:
	token_layer = tokens
	ghost_layer = ghosts

func begin_deploy(_unit_id: String) -> void:
	unit_id = _unit_id
	model_idx = 0
	temp_positions.clear()
	var unit_data = GameState.get_unit(unit_id)
	temp_positions.resize(unit_data["models"].size())
	
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
	
	_create_ghost()

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
	var base_mm = unit_data["models"][model_idx]["base_mm"]
	var radius_px = Measurement.base_radius_px(base_mm)
	var active_player = GameState.get_active_player()
	var zone = BoardState.get_deployment_zone_for_player(active_player)
	
	# Check if wholly within deployment zone
	if not _circle_wholly_in_polygon(world_pos, radius_px, zone):
		_show_toast("Must be wholly within your deployment zone")
		return
	
	# Check for overlap with existing models
	if _overlaps_with_existing_models(world_pos, radius_px):
		_show_toast("Cannot overlap with existing models")
		return
	
	temp_positions[model_idx] = world_pos
	_spawn_preview_token(unit_id, model_idx, world_pos)
	model_idx += 1
	
	_check_coherency_warning()
	emit_signal("models_placed_changed")
	
	if model_idx < temp_positions.size():
		_update_ghost_for_next_model()

func undo() -> void:
	_clear_previews()
	temp_positions.fill(null)
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
				print("Deployment successful via PhaseManager")
			else:
				print("Deployment failed: ", result.get("error", "Unknown error"))
	
	_finalize_tokens()
	_clear_previews()
	_remove_ghost()
	
	unit_id = ""
	model_idx = -1
	temp_positions.clear()
	
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
		var base_mm = unit_data["models"][model_idx]["base_mm"]
		ghost_sprite.radius = Measurement.base_radius_px(base_mm)
		ghost_sprite.owner_player = unit_data["owner"]
	
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
		var base_mm = unit_data["models"][model_idx]["base_mm"]
		ghost_sprite.radius = Measurement.base_radius_px(base_mm)
		ghost_sprite.queue_redraw()

func _spawn_preview_token(unit_id: String, model_index: int, pos: Vector2) -> void:
	var token = _create_token_visual(unit_id, model_index, pos, true)
	placed_tokens.append(token)
	token_layer.add_child(token)

func _create_token_visual(unit_id: String, model_index: int, pos: Vector2, is_preview: bool = false) -> Node2D:
	var token = Node2D.new()
	token.position = pos
	token.name = "Token_%s_%d" % [unit_id, model_index]
	
	var unit_data = GameState.get_unit(unit_id)
	var base_mm = unit_data["models"][model_index]["base_mm"]
	var radius_px = Measurement.base_radius_px(base_mm)
	
	var base_circle = preload("res://scripts/TokenVisual.gd").new()
	base_circle.radius = radius_px
	base_circle.owner_player = unit_data["owner"]
	base_circle.is_preview = is_preview
	base_circle.model_number = model_index + 1
	
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
	if ghost_sprite != null and is_placing() and model_idx < temp_positions.size():
		# Get mouse position in world coordinates
		var mouse_pos = _get_world_mouse_position()
		ghost_sprite.position = mouse_pos
		
		var unit_data = GameState.get_unit(unit_id)
		var base_mm = unit_data["models"][model_idx]["base_mm"]
		var radius_px = Measurement.base_radius_px(base_mm)
		var active_player = GameState.get_active_player()
		var zone = BoardState.get_deployment_zone_for_player(active_player)
		
		# Check both deployment zone and model overlap
		var is_valid = _circle_wholly_in_polygon(mouse_pos, radius_px, zone) and not _overlaps_with_existing_models(mouse_pos, radius_px)
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