extends Node2D
# All base shape classes are available via class_name - no preloads needed

# DisembarkController - Handles model placement when disembarking from transports
# Similar to DeploymentController but with 3" range restriction from transport

signal disembark_completed(unit_id: String, positions: Array)
signal disembark_canceled(unit_id: String)
signal model_placed(index: int)

var unit_id: String
var transport_id: String
var unit_data: Dictionary = {}
var transport_data: Dictionary = {}
var model_positions: Array = []
var model_rotations: Array = []
var ghost_visuals: Array = []
var placed_tokens: Array = []
var current_model_idx: int = 0
var transport_position: Vector2
var transport_base_shape: BaseShape = null  # Store the transport's base shape

# Visual layers
var ghost_layer: Node2D
var token_layer: Node2D
var range_indicator: Node2D

# Colors
const VALID_COLOR = Color.GREEN
const INVALID_COLOR = Color.RED
const RANGE_COLOR = Color(0.3, 0.6, 1.0, 0.3)  # Light blue with transparency

func _ready() -> void:
	# Create visual layers
	ghost_layer = Node2D.new()
	ghost_layer.name = "GhostLayer"
	add_child(ghost_layer)

	token_layer = Node2D.new()
	token_layer.name = "TokenLayer"
	add_child(token_layer)

	range_indicator = Node2D.new()
	range_indicator.name = "RangeIndicator"
	add_child(range_indicator)

	print("DisembarkController initialized")

func start_disembark(p_unit_id: String) -> void:
	unit_id = p_unit_id
	unit_data = GameState.get_unit(unit_id)

	if not unit_data:
		print("ERROR: Unit not found: ", unit_id)
		_cancel_disembark()
		return

	transport_id = unit_data.get("embarked_in", null)
	if not transport_id:
		print("ERROR: Unit is not embarked")
		_cancel_disembark()
		return

	transport_data = GameState.get_unit(transport_id)
	if not transport_data:
		print("ERROR: Transport not found: ", transport_id)
		_cancel_disembark()
		return

	# Calculate transport center position
	transport_position = _calculate_transport_center()

	# Get transport base shape for range calculation
	if transport_data.models.size() > 0:
		transport_base_shape = Measurement.create_base_shape(transport_data.models[0])
	else:
		# Fallback to circular base
		transport_base_shape = CircularBase.new(Measurement.base_radius_px(32))

	# Initialize positions array
	model_positions.clear()
	model_rotations.clear()
	for i in range(unit_data.models.size()):
		if unit_data.models[i].alive:
			model_positions.append(null)
			model_rotations.append(0.0)

	# Draw 3" disembark range indicator
	_draw_range_indicator()

	# Create ghost for first model
	current_model_idx = 0
	_create_ghost_for_model(current_model_idx)

	# Enable input processing
	set_process_unhandled_input(true)

	# Show instructions
	_show_instructions()

func _calculate_transport_center() -> Vector2:
	var center = Vector2.ZERO
	var count = 0

	for model in transport_data.models:
		if model.alive and model.has("position") and model.position != null:
			center += Vector2(model.position.x, model.position.y)
			count += 1

	if count > 0:
		center /= count

	return center

func _draw_range_indicator() -> void:
	# Clear previous indicator
	for child in range_indicator.get_children():
		child.queue_free()

	# Create a visual range indicator (3" from transport edge)
	var range_visual = Node2D.new()
	range_indicator.add_child(range_visual)

	# Get the 3" range in pixels
	var range_px = Measurement.inches_to_px(3.0)

	# Create a shape that represents 3" from the transport's actual base shape
	if transport_base_shape:
		_draw_shape_based_range(range_visual, range_px)
	else:
		# Fallback to circular
		_draw_circular_range(range_visual, range_px)

func _draw_shape_based_range(range_visual: Node2D, range_px: float) -> void:
	var shape_type = transport_base_shape.get_type()

	if shape_type == "circular":
		var circular_base = transport_base_shape as CircularBase
		var total_radius = circular_base.radius + range_px
		_draw_circular_range_with_radius(range_visual, total_radius)

	elif shape_type == "rectangular":
		var rect_base = transport_base_shape as RectangularBase
		# Create an expanded rectangle: original dimensions + 2 * range_px
		var expanded_length = rect_base.length + (2 * range_px)
		var expanded_width = rect_base.width + (2 * range_px)
		_draw_rectangular_range(range_visual, expanded_length, expanded_width)

	elif shape_type == "oval":
		var oval_base = transport_base_shape as OvalBase
		# Create an expanded oval: original dimensions + 2 * range_px
		var expanded_length = oval_base.length + (2 * range_px)
		var expanded_width = oval_base.width + (2 * range_px)
		_draw_oval_range(range_visual, expanded_length, expanded_width)

func _draw_circular_range(range_visual: Node2D, range_px: float) -> void:
	# Fallback for when we don't have transport shape info
	var default_radius = Measurement.base_radius_px(32) + range_px
	_draw_circular_range_with_radius(range_visual, default_radius)

func _draw_circular_range_with_radius(range_visual: Node2D, radius: float) -> void:
	var circle_points = PackedVector2Array()
	var segments = 64
	for i in range(segments + 1):
		var angle = (i / float(segments)) * TAU
		var point = transport_position + Vector2(cos(angle), sin(angle)) * radius
		circle_points.append(point)

	var line = Line2D.new()
	line.points = circle_points
	line.default_color = RANGE_COLOR
	line.width = 2.0
	line.z_index = -1
	range_visual.add_child(line)

func _draw_rectangular_range(range_visual: Node2D, length: float, width: float) -> void:
	# Draw an expanded rectangle
	var half_length = length / 2
	var half_width = width / 2

	var corners = [
		Vector2(-half_length, -half_width),
		Vector2(half_length, -half_width),
		Vector2(half_length, half_width),
		Vector2(-half_length, half_width),
		Vector2(-half_length, -half_width)  # Close the shape
	]

	# Transform to world position
	var world_points = PackedVector2Array()
	for corner in corners:
		world_points.append(transport_position + corner)

	var line = Line2D.new()
	line.points = world_points
	line.default_color = RANGE_COLOR
	line.width = 2.0
	line.z_index = -1
	range_visual.add_child(line)

func _draw_oval_range(range_visual: Node2D, length: float, width: float) -> void:
	# Draw an expanded oval using parametric equations
	var oval_points = PackedVector2Array()
	var segments = 64

	for i in range(segments + 1):
		var t = (i / float(segments)) * TAU
		var x = (length / 2.0) * cos(t)
		var y = (width / 2.0) * sin(t)
		var point = transport_position + Vector2(x, y)
		oval_points.append(point)

	var line = Line2D.new()
	line.points = oval_points
	line.default_color = RANGE_COLOR
	line.width = 2.0
	line.z_index = -1
	range_visual.add_child(line)

func _create_ghost_for_model(idx: int) -> void:
	# Find the actual model index (skip dead models)
	var actual_idx = _get_actual_model_index(idx)
	if actual_idx == -1:
		print("ERROR: No more alive models to place")
		_complete_disembark()
		return

	var model = unit_data.models[actual_idx]

	var ghost = preload("res://scripts/GhostVisual.gd").new()
	ghost.owner_player = unit_data.owner
	ghost.set_model_data(model)  # This sets up the base shape
	ghost.modulate.a = 0.6  # Semi-transparent

	ghost_layer.add_child(ghost)
	ghost_visuals.append(ghost)

	# Position at mouse initially (convert screen to world coordinates)
	var screen_pos = get_viewport().get_mouse_position()
	ghost.position = _get_world_position_from_screen(screen_pos)

func _get_actual_model_index(placement_idx: int) -> int:
	var alive_count = 0
	for i in range(unit_data.models.size()):
		if unit_data.models[i].alive:
			if alive_count == placement_idx:
				return i
			alive_count += 1
	return -1

func _validate_disembark_position(pos: Vector2, model_idx: int) -> Dictionary:
	var model = unit_data.models[model_idx]

	# Must be within 3" of transport edge
	# Calculate distance from the edge of the transport's base shape to the edge of the model's base
	var dist_from_edge: float

	if transport_base_shape:
		# Create the disembarking model's base shape for more accurate measurement
		var model_base_shape = Measurement.create_base_shape(model)

		# Get the closest point on the transport's edge to the model's position
		var closest_transport_edge = transport_base_shape.get_closest_edge_point(pos, transport_position, 0.0)

		# Get the closest point on the model's edge to the transport
		var closest_model_edge = model_base_shape.get_closest_edge_point(closest_transport_edge, pos, 0.0)

		# Calculate edge-to-edge distance
		dist_from_edge = closest_transport_edge.distance_to(closest_model_edge)
	else:
		# Fallback to simple circular calculation
		var dist_from_center = pos.distance_to(transport_position)
		var model_radius = Measurement.base_radius_px(model.get("base_mm", 32))
		var transport_radius = Measurement.base_radius_px(32)
		dist_from_edge = dist_from_center - transport_radius - model_radius

	var dist_inches = Measurement.px_to_inches(dist_from_edge)

	# Allow placement within 3" of transport edge
	if dist_from_edge > Measurement.inches_to_px(3.0):
		return {"valid": false, "reason": "Must be within 3\" of transport (%.1f\" away)" % dist_inches}

	# Cannot be in engagement range of enemies
	var enemy_player = 3 - unit_data.owner  # Switch between player 1 and 2
	for enemy_id in GameState.state.units:
		var enemy = GameState.state.units[enemy_id]
		if enemy.owner != enemy_player:
			continue

		# Skip embarked enemies
		if enemy.get("embarked_in", null) != null:
			continue

		for enemy_model in enemy.models:
			if not enemy_model.alive or enemy_model.position == null:
				continue

			# Create a test model for shape-aware distance check
			var test_model = model.duplicate()
			test_model["position"] = {"x": pos.x, "y": pos.y}

			# Use shape-aware distance calculation
			var distance = Measurement.model_to_model_distance_px(test_model, enemy_model)
			var engagement_dist = Measurement.inches_to_px(1.0)

			if distance <= engagement_dist:
				return {"valid": false, "reason": "Cannot disembark within Engagement Range"}

	# Check for model overlaps
	if _check_model_overlap(pos, model_idx):
		return {"valid": false, "reason": "Model would overlap"}

	# Check wall overlaps
	var test_model = model.duplicate()
	test_model["position"] = {"x": pos.x, "y": pos.y}
	if Measurement.model_overlaps_any_wall(test_model):
		return {"valid": false, "reason": "Model cannot overlap with walls"}

	# Check terrain overlap if needed
	# ... add terrain checks here if needed ...

	return {"valid": true}

func _check_model_overlap(pos: Vector2, exclude_idx: int) -> bool:
	# Get the current model's data for proper shape checking
	var current_model = unit_data.models[exclude_idx].duplicate()
	current_model["position"] = {"x": pos.x, "y": pos.y}

	# Check against already placed models from this unit
	for i in range(model_positions.size()):
		if i != exclude_idx and model_positions[i] != null:
			var other_pos = model_positions[i]
			var other_idx = _get_actual_model_index(i)
			var other_model = unit_data.models[other_idx].duplicate()
			other_model["position"] = {"x": other_pos.x, "y": other_pos.y}

			# Use proper shape-aware overlap detection
			if Measurement.models_overlap(current_model, other_model):
				return true

	# Check against all other deployed models
	for check_unit_id in GameState.state.units:
		var check_unit = GameState.state.units[check_unit_id]

		# Skip our own unit (we're checking that separately above)
		if check_unit_id == unit_id:
			continue

		# Skip embarked units
		if check_unit.get("embarked_in", null) != null:
			continue

		for check_model in check_unit.models:
			if not check_model.alive or check_model.position == null:
				continue

			# Use proper shape-aware overlap detection
			if Measurement.models_overlap(current_model, check_model):
				return true

	return false

func _unhandled_input(event: InputEvent) -> void:
	if not is_processing_unhandled_input():
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_on_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_on_right_click()

	elif event is InputEventMouseMotion:
		_on_mouse_move(event.position)

	elif event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			_cancel_disembark()

func _on_click(screen_pos: Vector2) -> void:
	var world_pos = _get_world_position_from_screen(screen_pos)
	var actual_idx = _get_actual_model_index(current_model_idx)
	var validation = _validate_disembark_position(world_pos, actual_idx)

	if validation.valid:
		# Place the model
		model_positions[current_model_idx] = world_pos
		model_rotations[current_model_idx] = 0.0  # Default rotation

		# Create visual token
		_spawn_preview_token(actual_idx, world_pos)

		# Remove current ghost
		if ghost_visuals.size() > 0:
			var ghost = ghost_visuals.pop_back()
			ghost.queue_free()

		# Move to next model
		current_model_idx += 1
		emit_signal("model_placed", current_model_idx)

		# Check if all models are placed
		if current_model_idx >= _count_alive_models():
			_complete_disembark()
		else:
			_create_ghost_for_model(current_model_idx)
			_show_instructions()
	else:
		# Show error message
		_show_error(validation.reason)

func _on_right_click() -> void:
	# Undo last placement if possible
	if current_model_idx > 0:
		current_model_idx -= 1
		model_positions[current_model_idx] = null
		model_rotations[current_model_idx] = 0.0

		# Remove last placed token
		if placed_tokens.size() > 0:
			var token = placed_tokens.pop_back()
			token.queue_free()

		# Recreate ghost for this model
		if ghost_visuals.size() > 0:
			var ghost = ghost_visuals.pop_back()
			ghost.queue_free()
		_create_ghost_for_model(current_model_idx)

		_show_instructions()

func _on_mouse_move(screen_pos: Vector2) -> void:
	if ghost_visuals.size() > 0:
		var world_pos = _get_world_position_from_screen(screen_pos)
		var ghost = ghost_visuals[-1]
		ghost.position = world_pos

		# Update validity color
		var actual_idx = _get_actual_model_index(current_model_idx)
		var validation = _validate_disembark_position(world_pos, actual_idx)
		if ghost.has_method("set_validity"):
			ghost.set_validity(validation.valid)
		else:
			ghost.modulate = VALID_COLOR if validation.valid else INVALID_COLOR

func _spawn_preview_token(model_idx: int, pos: Vector2) -> void:
	var model = unit_data.models[model_idx]
	var token = preload("res://scripts/TokenVisual.gd").new()

	token.owner_player = unit_data.owner
	token.position = pos
	token.z_index = 1
	token.set_model_data(model)  # Use the setter method instead of direct assignment

	# Set metadata for enhanced visual overlays (sprites, wound pips, etc.)
	var model_id_str = model.get("id", "m%d" % (model_idx + 1))
	token.set_meta("unit_id", unit_id)
	token.set_meta("model_id", model_id_str)
	token.queue_redraw()

	token_layer.add_child(token)
	placed_tokens.append(token)

func _count_alive_models() -> int:
	var count = 0
	for model in unit_data.models:
		if model.alive:
			count += 1
	return count

func _complete_disembark() -> void:
	print("Disembark placement complete for unit: ", unit_id)

	# Convert null positions to actual positions for TransportManager
	var final_positions = []
	for i in range(unit_data.models.size()):
		if unit_data.models[i].alive:
			var placement_idx = _get_placement_index(i)
			if placement_idx != -1 and model_positions[placement_idx] != null:
				final_positions.append(model_positions[placement_idx])
			else:
				# This shouldn't happen if placement was successful
				print("WARNING: Missing position for model ", i)

	# Just emit the completion signal - MovementPhase will handle offering movement
	emit_signal("disembark_completed", unit_id, final_positions)
	_cleanup()


func _get_placement_index(model_idx: int) -> int:
	# Convert model index to placement index (counting only alive models)
	var alive_count = 0
	for i in range(model_idx + 1):
		if unit_data.models[i].alive:
			if i == model_idx:
				return alive_count
			alive_count += 1
	return -1

func _cancel_disembark() -> void:
	print("Disembark canceled for unit: ", unit_id)
	emit_signal("disembark_canceled", unit_id)
	_cleanup()

func _cleanup() -> void:
	set_process_unhandled_input(false)

	# Clear all visuals
	for ghost in ghost_visuals:
		ghost.queue_free()
	ghost_visuals.clear()

	for token in placed_tokens:
		token.queue_free()
	placed_tokens.clear()

	for child in range_indicator.get_children():
		child.queue_free()

	# Queue free self after a frame to allow signals to propagate
	queue_free()

func _show_instructions() -> void:
	var remaining = _count_alive_models() - current_model_idx
	var msg = "Place model %d of %d within 3\" of transport (ESC to cancel, right-click to undo)" % [
		current_model_idx + 1,
		_count_alive_models()
	]

	# This would normally show in a UI element - for now just print
	print(msg)

func _show_error(reason: String) -> void:
	print("Cannot place model: ", reason)
	# This would normally show in a toast/notification UI

func _get_world_position_from_screen(screen_pos: Vector2) -> Vector2:
	"""Convert screen position to world position, accounting for camera"""
	# Use the same method as DeploymentController
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("screen_to_world_position"):
		return main_scene.screen_to_world_position(screen_pos)
	else:
		# Fallback to viewport mouse position
		return get_viewport().get_mouse_position()
