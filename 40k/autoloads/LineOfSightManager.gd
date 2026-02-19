extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# LineOfSightManager - Manages Line of Sight visualization system
# Shows all models that can see the mouse cursor position when holding 'V' key

signal los_visibility_changed(visible_models: Array, target_pos: Vector2)
signal los_calculation_started()
signal los_calculation_ended()

# State tracking
var is_calculating: bool = false
var visible_models: Array = []  # Models that can see the target
var target_position: Vector2 = Vector2.ZERO  # Position we're checking LoS to
var visual_node: Node2D = null

# Configuration
var grid_resolution: int = 20  # pixels per grid cell (for area visualization)
var max_range_inches: float = 48.0  # Maximum visibility range
var debug_mode: bool = false

# Performance optimization
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _mouse_move_threshold: float = 10.0  # Minimum mouse movement before recalculating

func _ready() -> void:
	name = "LineOfSightManager"
	set_process_unhandled_input(true)
	set_process(false)  # Only process when calculating
	print("[LineOfSightManager] Initialized - Hold 'V' to check what can see the cursor position")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.keycode == KEY_V:
			if event.pressed:
				start_los_calculation()
			else:
				end_los_calculation()
	elif event is InputEventMouseMotion and is_calculating:
		# Update calculation if mouse moved significantly
		if event.position.distance_to(_last_mouse_pos) > _mouse_move_threshold:
			_last_mouse_pos = event.position
			_update_los_calculation()

func start_los_calculation() -> void:
	if is_calculating:
		return

	# Get target position at mouse cursor
	target_position = _get_world_mouse_position()
	_last_mouse_pos = get_viewport().get_mouse_position()

	if debug_mode:
		print("[LineOfSightManager] Starting LoS calculation to position: ", target_position)

	is_calculating = true
	set_process(true)
	emit_signal("los_calculation_started")

	# Calculate which models can see this position
	visible_models = calculate_los_to_position(target_position)
	emit_signal("los_visibility_changed", visible_models, target_position)

func end_los_calculation() -> void:
	if not is_calculating:
		return

	is_calculating = false
	set_process(false)
	visible_models.clear()
	target_position = Vector2.ZERO
	emit_signal("los_calculation_ended")

	if debug_mode:
		print("[LineOfSightManager] Ended LoS calculation")

func _update_los_calculation() -> void:
	if not is_calculating:
		return

	# Update target position
	target_position = _get_world_mouse_position()

	# Recalculate which models can see the new position
	visible_models = calculate_los_to_position(target_position)
	emit_signal("los_visibility_changed", visible_models, target_position)

func calculate_los_to_position(target_pos: Vector2) -> Array:
	var models_with_los = []

	# Get all deployed models on the board
	var all_models = _get_all_deployed_models()

	if debug_mode:
		print("[LineOfSightManager] Checking LoS from ", all_models.size(), " models to ", target_pos)

	var max_range_px = Measurement.inches_to_px(max_range_inches) if Measurement else max_range_inches * 40

	# Create a dummy target model representing the cursor position
	# This allows us to check LoS to a point as if it were a small model
	var target_model = _create_point_target(target_pos)

	# Check each model to see if it has LoS to the target
	for model_data in all_models:
		var model_pos = model_data.position

		# Skip if beyond max range (check from center for quick culling)
		if model_pos.distance_to(target_pos) > max_range_px:
			continue

		# Use EnhancedLineOfSight to check from any point on the model's base
		# to the target position (treating it as a point target)
		var los_result = EnhancedLineOfSight.check_enhanced_visibility(
			model_data.model,  # The actual model dictionary
			target_model,       # The target point as a model
			{"terrain_features": TerrainManager.terrain_features if TerrainManager else []}
		)

		if los_result.has_los:
			# Store the actual sight line points for visualization
			model_data["sight_line"] = los_result.sight_line  # [from_point, to_point]
			model_data["los_method"] = los_result.method  # How LoS was found (center/edge)
			models_with_los.append(model_data)

	if debug_mode:
		print("[LineOfSightManager] Found ", models_with_los.size(), " models with LoS to target")

	return models_with_los

func _create_point_target(position: Vector2) -> Dictionary:
	# Create a dummy model representing a single point for LoS checking
	# This represents the cursor position as a very small circular "model"
	return {
		"position": position,
		"base_type": "circular",
		"base_mm": 1,  # 1mm base = essentially a point
		"rotation": 0.0,
		"id": "cursor_target",
		"wounds": 1,
		"current_wounds": 1
	}

func check_los(from: Vector2, to: Vector2, shooter_model: Dictionary = {}, target_model: Dictionary = {}) -> bool:
	# Check if line of sight is blocked by terrain
	# T3-19: Now handles all terrain heights, not just tall
	var terrain_features = []

	# Get terrain from TerrainManager
	if TerrainManager and TerrainManager.terrain_features.size() > 0:
		terrain_features = TerrainManager.terrain_features

	# Check each terrain piece
	for terrain in terrain_features:
		var height_cat = terrain.get("height_category", "")

		# Low terrain never blocks LoS
		if height_cat == "low":
			continue

		var polygon = terrain.get("polygon", PackedVector2Array())
		if polygon.is_empty():
			continue

		# Check if the line intersects the terrain polygon
		if not _segment_intersects_polygon(from, to, polygon):
			continue

		# Check if both points are outside the terrain
		# (models inside terrain can see out and be seen)
		if _point_in_polygon(from, polygon) or _point_in_polygon(to, polygon):
			continue

		if height_cat == "tall":
			return false  # Tall terrain blocks LoS for all models

		if height_cat == "medium":
			# T3-19: Medium terrain blocks LoS only if both models are shorter than terrain
			var terrain_height = LineOfSightCalculator._get_terrain_height_inches(terrain)
			var shooter_height = LineOfSightCalculator.get_model_height_inches(shooter_model)
			var target_height = LineOfSightCalculator.get_model_height_inches(target_model)
			if shooter_height < terrain_height and target_height < terrain_height:
				return false  # Both models shorter than medium terrain — LoS blocked

	return true  # Clear line of sight

func _get_world_mouse_position() -> Vector2:
	# Get mouse position in world coordinates
	# The Main scene uses a custom transform system with BoardRoot instead of Camera2D

	var main_scene = get_tree().current_scene
	if not main_scene:
		return Vector2.ZERO

	# Try to get the BoardRoot node which has the transform
	var board_root = main_scene.get_node_or_null("BoardRoot")
	if board_root:
		# Convert screen position to world position using BoardRoot's transform
		var screen_pos = get_viewport().get_mouse_position()
		var world_pos = board_root.transform.affine_inverse() * screen_pos
		return world_pos

	# Fallback: try to use the Main scene's conversion function if available
	if main_scene.has_method("screen_to_world_position"):
		var screen_pos = get_viewport().get_mouse_position()
		return main_scene.screen_to_world_position(screen_pos)

	# Last resort: raw viewport position
	return get_viewport().get_mouse_position()

func _get_all_deployed_models() -> Array:
	var all_models = []

	# Check all units for deployed models
	if not GameState or not GameState.state.has("units"):
		return all_models

	var units = GameState.state["units"]
	for unit_id in units:
		var unit = units[unit_id]

		# Skip undeployed units
		if unit.get("status", 0) == GameStateData.UnitStatus.UNDEPLOYED:
			continue

		# Add each model in the unit
		var unit_models = unit.get("models", [])
		for i in range(unit_models.size()):
			var model = unit_models[i]
			var model_pos = _get_model_position(model)
			if model_pos == Vector2.ZERO:
				continue

			# Store model data with additional info for visualization
			all_models.append({
				"position": model_pos,
				"unit_id": unit_id,
				"model_index": i,
				"owner": unit.get("owner", 0),
				"unit_name": unit.get("meta", {}).get("name", "Unknown"),
				"base_radius": _get_model_base_radius(model),
				"model": model
			})

	return all_models

func _get_model_position(model: Dictionary) -> Vector2:
	var pos = model.get("position")
	if pos == null:
		return Vector2.ZERO
	if pos is Dictionary:
		return Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO

func _get_model_base_radius(model: Dictionary) -> float:
	var base_type = model.get("base_type", "circular")

	if base_type == "circular":
		var base_mm = model.get("base_mm", 32)
		return Measurement.base_radius_px(base_mm) if Measurement else base_mm * 1.2
	else:
		# For non-circular bases, use approximate radius
		var base_dimensions = model.get("base_dimensions", {})
		var length = base_dimensions.get("length", 32)
		var width = base_dimensions.get("width", 32)
		var max_dimension = max(length, width)
		return Measurement.mm_to_px(max_dimension / 2.0) if Measurement else max_dimension * 0.6

# Calculate a grid showing all positions that can see the target
# This is an optional enhanced visualization mode
func calculate_visibility_grid_to_target(target_pos: Vector2) -> Dictionary:
	var grid = {}

	# Get board dimensions
	var board_width = SettingsService.get_board_width_px() if SettingsService else 1760.0
	var board_height = SettingsService.get_board_height_px() if SettingsService else 2400.0

	# Sample grid points to see which positions can see the target
	var x = 0
	while x <= board_width:
		var y = 0
		while y <= board_height:
			var check_pos = Vector2(x, y)

			# Check if this position can see the target
			if check_los(check_pos, target_pos):
				grid[check_pos] = true

			y += grid_resolution
		x += grid_resolution

	return grid

# Polygon intersection checking (adapted from EnhancedLineOfSight)
func _segment_intersects_polygon(seg_start: Vector2, seg_end: Vector2, poly) -> bool:
	var polygon_packed: PackedVector2Array

	if poly is PackedVector2Array:
		polygon_packed = poly
	elif poly is Array:
		polygon_packed = PackedVector2Array()
		for vertex in poly:
			if vertex is Dictionary:
				polygon_packed.append(Vector2(vertex.get("x", 0), vertex.get("y", 0)))
			elif vertex is Vector2:
				polygon_packed.append(vertex)
	else:
		return false

	if polygon_packed.is_empty():
		return false

	# Check if line segment intersects any edge of the polygon
	for i in range(polygon_packed.size()):
		var edge_start = polygon_packed[i]
		var edge_end = polygon_packed[(i + 1) % polygon_packed.size()]

		if Geometry2D.segment_intersects_segment(seg_start, seg_end, edge_start, edge_end):
			return true

	return false

# Point in polygon checking (adapted from EnhancedLineOfSight)
func _point_in_polygon(point: Vector2, poly) -> bool:
	var polygon_packed: PackedVector2Array

	if poly is PackedVector2Array:
		polygon_packed = poly
	elif poly is Array:
		polygon_packed = PackedVector2Array()
		for vertex in poly:
			if vertex is Dictionary:
				polygon_packed.append(Vector2(vertex.get("x", 0), vertex.get("y", 0)))
			elif vertex is Vector2:
				polygon_packed.append(vertex)
	else:
		return false

	return Geometry2D.is_point_in_polygon(point, polygon_packed)

# Set the visual node for direct updates (optional optimization)
func set_visual_node(node: Node2D) -> void:
	visual_node = node

# Debug functions
func set_debug_mode(enabled: bool) -> void:
	debug_mode = enabled

func set_grid_resolution(resolution: int) -> void:
	grid_resolution = clamp(resolution, 10, 100)

func set_max_range(range_inches: float) -> void:
	max_range_inches = clamp(range_inches, 12.0, 72.0)
