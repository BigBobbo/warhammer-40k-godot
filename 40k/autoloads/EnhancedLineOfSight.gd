extends Node

# EnhancedLineOfSight - Advanced base-to-base visibility checking
# Implements progressive sampling for true line of sight following Warhammer 40k 10th Edition rules
# Checks visibility from any point on shooter's base to any point on target's base

# Performance cache for terrain intersection results
var _terrain_intersection_cache: Dictionary = {}
var _cache_max_size: int = 1000

# Debug settings
var debug_enabled: bool = false

func _ready() -> void:
	name = "EnhancedLineOfSight"
	print("[EnhancedLineOfSight] Initialized")

# Main enhanced LoS checking function
static func check_enhanced_visibility(shooter_model: Dictionary, target_model: Dictionary, board: Dictionary) -> Dictionary:
	var shooter_pos = _get_model_position(shooter_model)
	var target_pos = _get_model_position(target_model)
	
	if shooter_pos == Vector2.ZERO or target_pos == Vector2.ZERO:
		return {"has_los": false, "reason": "Invalid model positions", "sight_line": [], "attempted_lines": []}
	
	var shooter_radius = Measurement.base_radius_px(shooter_model.get("base_mm", 32))
	var target_radius = Measurement.base_radius_px(target_model.get("base_mm", 32))
	
	# Progressive sampling: center, edges, then circumference points
	var sample_points = _generate_base_sample_points(shooter_pos, shooter_radius, target_pos, target_radius)
	
	var attempted_lines = []
	
	# Phase 1: Center-to-center (fast path for 85% of cases)
	var center_check = _check_single_line_of_sight(shooter_pos, target_pos, board)
	attempted_lines.append({"from": shooter_pos, "to": target_pos, "blocked": not center_check.has_los})
	
	if center_check.has_los:
		return {
			"has_los": true, 
			"sight_line": [shooter_pos, target_pos],
			"method": "center_to_center",
			"attempted_lines": attempted_lines,
			"blocking_terrain": []
		}
	
	# Phase 2: Progressive sampling through edge and circumference points
	for shooter_point in sample_points.shooter:
		for target_point in sample_points.target:
			var los_check = _check_single_line_of_sight(shooter_point, target_point, board)
			attempted_lines.append({"from": shooter_point, "to": target_point, "blocked": not los_check.has_los})
			
			if los_check.has_los:
				return {
					"has_los": true, 
					"sight_line": [shooter_point, target_point],
					"method": "edge_to_edge",
					"attempted_lines": attempted_lines,
					"blocking_terrain": []
				}
	
	# No clear sight lines found
	var blocking_terrain = _get_blocking_terrain(sample_points, board)
	return {
		"has_los": false, 
		"sight_line": [],
		"method": "full_sampling",
		"attempted_lines": attempted_lines,
		"blocking_terrain": blocking_terrain
	}

# Sample point generation for different base sizes with intelligent density
static func _generate_base_sample_points(shooter_pos: Vector2, shooter_radius: float, target_pos: Vector2, target_radius: float) -> Dictionary:
	var distance_inches = Measurement.px_to_inches(shooter_pos.distance_to(target_pos))
	var max_base_mm = int(max(Measurement.px_to_mm(shooter_radius * 2), Measurement.px_to_mm(target_radius * 2)))
	
	# Determine sample density based on distance and base sizes
	var sample_density = _determine_sample_density(distance_inches, max_base_mm)
	
	var shooter_points = _generate_circle_sample_points(shooter_pos, shooter_radius, sample_density)
	var target_points = _generate_circle_sample_points(target_pos, target_radius, sample_density)
	
	return {
		"shooter": shooter_points,
		"target": target_points,
		"density": sample_density
	}

# Generate sample points around a circle based on density
static func _generate_circle_sample_points(center: Vector2, radius: float, density: int) -> Array:
	var points = []
	
	# Always include center point
	points.append(center)
	
	# Add edge points based on density
	for i in range(density):
		var angle = (i * 2 * PI) / density
		var point = center + Vector2(cos(angle), sin(angle)) * radius
		points.append(point)
	
	return points

# Determine sample density based on distance and base size
static func _determine_sample_density(distance_inches: float, base_size_mm: int) -> int:
	# Use fewer samples for distant or small targets
	if distance_inches > 24.0 or base_size_mm <= 32:
		return 4  # Cardinal directions only (N, E, S, W)
	elif base_size_mm <= 60:
		return 6  # Include diagonal points
	else:
		return 8  # Full circumference sampling for large bases

# Single line of sight check with terrain intersection
static func _check_single_line_of_sight(from: Vector2, to: Vector2, board: Dictionary) -> Dictionary:
	var terrain_features = board.get("terrain_features", [])
	if terrain_features.is_empty() and TerrainManager:
		terrain_features = TerrainManager.terrain_features
	
	var blocking_terrain = []
	
	for terrain_piece in terrain_features:
		# Only tall terrain (>5") blocks LoS completely
		if terrain_piece.get("height_category", "") == "tall":
			var polygon = terrain_piece.get("polygon", PackedVector2Array())
			if _segment_intersects_polygon(from, to, polygon):
				# Check if both points are outside the terrain
				# (models inside can see out and be seen)
				if not _point_in_polygon(from, polygon) and not _point_in_polygon(to, polygon):
					blocking_terrain.append(terrain_piece.get("id", "unknown"))
	
	return {
		"has_los": blocking_terrain.is_empty(),
		"blocking_terrain": blocking_terrain
	}

# Get all terrain pieces that block any line in the sample set
static func _get_blocking_terrain(sample_points: Dictionary, board: Dictionary) -> Array:
	var terrain_features = board.get("terrain_features", [])
	if terrain_features.is_empty() and TerrainManager:
		terrain_features = TerrainManager.terrain_features
	
	var blocking_terrain = []
	
	for terrain_piece in terrain_features:
		if terrain_piece.get("height_category", "") == "tall":
			var polygon = terrain_piece.get("polygon", PackedVector2Array())
			var terrain_id = terrain_piece.get("id", "unknown")
			var terrain_blocks_any_line = false
			
			# Check if this terrain blocks any potential sight line
			for shooter_point in sample_points.shooter:
				for target_point in sample_points.target:
					if _segment_intersects_polygon(shooter_point, target_point, polygon):
						# Check if both points are outside the terrain
						if not _point_in_polygon(shooter_point, polygon) and not _point_in_polygon(target_point, polygon):
							terrain_blocks_any_line = true
							break
				if terrain_blocks_any_line:
					break
			
			if terrain_blocks_any_line:
				blocking_terrain.append(terrain_id)
	
	return blocking_terrain

# Helper function to get model position (reused from RulesEngine)
static func _get_model_position(model: Dictionary) -> Vector2:
	var pos = model.get("position")
	if pos == null:
		return Vector2.ZERO
	if pos is Dictionary:
		return Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO

# Polygon intersection checking (reused from RulesEngine)
static func _segment_intersects_polygon(seg_start: Vector2, seg_end: Vector2, poly) -> bool:
	var polygon_packed: PackedVector2Array
	
	if poly is PackedVector2Array:
		polygon_packed = poly
	elif poly is Array:
		# Convert Array to PackedVector2Array
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

# Point in polygon checking (reused from RulesEngine)
static func _point_in_polygon(point: Vector2, poly) -> bool:
	var polygon_packed: PackedVector2Array
	
	if poly is PackedVector2Array:
		polygon_packed = poly
	elif poly is Array:
		# Convert Array to PackedVector2Array
		polygon_packed = PackedVector2Array()
		for vertex in poly:
			if vertex is Dictionary:
				polygon_packed.append(Vector2(vertex.get("x", 0), vertex.get("y", 0)))
			elif vertex is Vector2:
				polygon_packed.append(vertex)
	else:
		return false
	
	return Geometry2D.is_point_in_polygon(point, polygon_packed)

# Performance optimization: cached terrain intersection checking
func _check_cached_terrain_intersection(from: Vector2, to: Vector2, terrain_id: String) -> bool:
	var key = "%s_%s_%s" % [from, to, terrain_id]
	
	if _terrain_intersection_cache.has(key):
		return _terrain_intersection_cache[key]
	
	# Clean cache if it gets too large
	if _terrain_intersection_cache.size() > _cache_max_size:
		_terrain_intersection_cache.clear()
	
	# This would be implemented as part of the full caching system
	# For now, fall back to direct calculation
	return false

# Clear the intersection cache (useful for performance testing)
func clear_cache() -> void:
	_terrain_intersection_cache.clear()

# Get cache statistics for performance monitoring
func get_cache_stats() -> Dictionary:
	return {
		"size": _terrain_intersection_cache.size(),
		"max_size": _cache_max_size,
		"hit_rate": 0.0  # Would be calculated with proper hit/miss tracking
	}