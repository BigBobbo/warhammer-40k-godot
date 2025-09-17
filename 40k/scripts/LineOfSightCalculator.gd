extends Resource
class_name LineOfSightCalculator

# LineOfSightCalculator - Utility class for Line of Sight calculations
# Provides optimized raycasting and visibility checking methods

# Configuration
const DEFAULT_GRID_SIZE: int = 20
const DEFAULT_MAX_RANGE: float = 48.0  # inches

# Static methods for LoS calculations
static func calculate_visibility_grid(models: Array, grid_size: int = DEFAULT_GRID_SIZE, max_range_inches: float = DEFAULT_MAX_RANGE) -> Dictionary:
	var visibility_map = {}

	if models.is_empty():
		return visibility_map

	# Get board dimensions
	var board_width = SettingsService.get_board_width_px() if SettingsService else 1760.0
	var board_height = SettingsService.get_board_height_px() if SettingsService else 2400.0
	var max_range_px = Measurement.inches_to_px(max_range_inches) if Measurement else max_range_inches * 40

	# Calculate bounds for checking
	var bounds = _calculate_check_bounds(models, max_range_px, board_width, board_height)

	# Get terrain features once for efficiency
	var terrain_features = _get_terrain_features()

	# Use adaptive grid resolution based on area size
	var adaptive_grid_size = _calculate_adaptive_grid_size(bounds, grid_size)

	# Sample points in the bounds
	var x = bounds.position.x
	while x <= bounds.end.x:
		var y = bounds.position.y
		while y <= bounds.end.y:
			var target_pos = Vector2(x, y)

			# Check visibility from any model
			for model in models:
				var model_pos = _get_model_position(model)

				# Skip if beyond range
				if model_pos.distance_to(target_pos) > max_range_px:
					continue

				# Check line of sight
				if check_line_of_sight(model_pos, target_pos, terrain_features):
					visibility_map[target_pos] = true
					break  # One model can see it, no need to check others

			y += adaptive_grid_size
		x += adaptive_grid_size

	return visibility_map

# Check if there's clear line of sight between two points
static func check_line_of_sight(from: Vector2, to: Vector2, terrain_features: Array = []) -> bool:
	# If no terrain provided, get it
	if terrain_features.is_empty():
		terrain_features = _get_terrain_features()

	# Check each terrain piece for blocking
	for terrain in terrain_features:
		if _terrain_blocks_los(from, to, terrain):
			return false

		# Check walls within this terrain piece
		if _walls_block_los(from, to, terrain):
			return false

	return true

# Check if terrain blocks line of sight
static func _terrain_blocks_los(from: Vector2, to: Vector2, terrain: Dictionary) -> bool:
	# Only tall terrain blocks LoS completely
	var height_cat = terrain.get("height_category", "")
	if height_cat != "tall":
		# TODO: Handle medium/low terrain based on model height
		return false

	var polygon = terrain.get("polygon", PackedVector2Array())
	if polygon.is_empty():
		return false

	# Check if the line intersects the terrain polygon
	if _segment_intersects_polygon(from, to, polygon):
		# Models inside terrain can see out and be seen
		# So only block if both points are outside
		if not _point_in_polygon(from, polygon) and not _point_in_polygon(to, polygon):
			return true

	return false

# Check if walls block line of sight
static func _walls_block_los(from: Vector2, to: Vector2, terrain: Dictionary) -> bool:
	var walls = terrain.get("walls", [])

	for wall in walls:
		if wall.get("blocks_los", true):  # Default to blocking if not specified
			if TerrainManager.check_line_intersects_wall(from, to, wall):
				return true  # Wall blocks LoS

	return false  # No blocking walls found

# Calculate optimal bounds for visibility checking
static func _calculate_check_bounds(models: Array, max_range: float, board_width: float, board_height: float) -> Rect2:
	if models.is_empty():
		return Rect2()

	var min_pos = Vector2(INF, INF)
	var max_pos = Vector2(-INF, -INF)

	# Find extents of all models
	for model in models:
		var pos = _get_model_position(model)
		if pos == Vector2.ZERO:
			continue

		min_pos.x = min(min_pos.x, pos.x - max_range)
		min_pos.y = min(min_pos.y, pos.y - max_range)
		max_pos.x = max(max_pos.x, pos.x + max_range)
		max_pos.y = max(max_pos.y, pos.y + max_range)

	# Clamp to board bounds
	min_pos.x = max(0, min_pos.x)
	min_pos.y = max(0, min_pos.y)
	max_pos.x = min(board_width, max_pos.x)
	max_pos.y = min(board_height, max_pos.y)

	return Rect2(min_pos, max_pos - min_pos)

# Calculate adaptive grid size based on area
static func _calculate_adaptive_grid_size(bounds: Rect2, base_grid_size: int) -> int:
	var area = bounds.size.x * bounds.size.y
	var max_points = 10000  # Maximum points to calculate for performance

	# Calculate how many points we'd have with base grid size
	var estimated_points = (bounds.size.x / base_grid_size) * (bounds.size.y / base_grid_size)

	if estimated_points > max_points:
		# Increase grid size to reduce points
		var scale_factor = sqrt(estimated_points / max_points)
		return int(base_grid_size * scale_factor)

	return base_grid_size

# Get terrain features from TerrainManager or board state
static func _get_terrain_features() -> Array:
	if TerrainManager and TerrainManager.terrain_features.size() > 0:
		return TerrainManager.terrain_features
	return []

# Extract model position from dictionary
static func _get_model_position(model: Dictionary) -> Vector2:
	var pos = model.get("position")
	if pos == null:
		return Vector2.ZERO
	if pos is Dictionary:
		return Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO

# Check if a line segment intersects a polygon
static func _segment_intersects_polygon(seg_start: Vector2, seg_end: Vector2, poly) -> bool:
	var polygon_packed: PackedVector2Array

	# Convert to PackedVector2Array if needed
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

	# Check intersection with each edge of the polygon
	for i in range(polygon_packed.size()):
		var edge_start = polygon_packed[i]
		var edge_end = polygon_packed[(i + 1) % polygon_packed.size()]

		# Use Godot's built-in geometry functions
		var intersection = Geometry2D.segment_intersects_segment(seg_start, seg_end, edge_start, edge_end)
		if intersection:
			return true

	return false

# Check if a point is inside a polygon
static func _point_in_polygon(point: Vector2, poly) -> bool:
	var polygon_packed: PackedVector2Array

	# Convert to PackedVector2Array if needed
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

	# Use Godot's built-in point-in-polygon test
	return Geometry2D.is_point_in_polygon(point, polygon_packed)

# Optimized batch visibility check for multiple targets
static func check_visibility_batch(from: Vector2, targets: Array, terrain_features: Array = []) -> Array:
	var results = []

	if terrain_features.is_empty():
		terrain_features = _get_terrain_features()

	for target in targets:
		var target_pos = target if target is Vector2 else _get_model_position(target)
		results.append(check_line_of_sight(from, target_pos, terrain_features))

	return results

# Get visibility percentage for an area
static func calculate_area_visibility(from: Vector2, area_center: Vector2, area_radius: float, sample_count: int = 8) -> float:
	var visible_count = 0
	var terrain_features = _get_terrain_features()

	# Sample points around the area
	for i in range(sample_count):
		var angle = (i * TAU) / sample_count
		var sample_point = area_center + Vector2(cos(angle), sin(angle)) * area_radius

		if check_line_of_sight(from, sample_point, terrain_features):
			visible_count += 1

	# Also check center
	if check_line_of_sight(from, area_center, terrain_features):
		visible_count += 1

	return float(visible_count) / float(sample_count + 1)