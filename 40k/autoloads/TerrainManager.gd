extends Node

# TerrainManager - Manages terrain features and their interactions
# Handles terrain data, layout configurations, and terrain-related rules

signal terrain_loaded(terrain_features: Array)
signal terrain_visibility_changed(visible: bool)

var terrain_features: Array = []
var terrain_visible: bool = true
var current_layout: String = "layout_2"

# Terrain height categories affect line of sight
enum HeightCategory {
	LOW,      # <2" - provides cover but doesn't block LoS
	MEDIUM,   # 2-5" - provides cover, partial LoS blocking
	TALL      # >5" - blocks LoS completely (obscuring)
}

func _ready() -> void:
	print("[TerrainManager] Initializing terrain system")
	load_terrain_layout(current_layout)

func load_terrain_layout(layout_name: String) -> void:
	terrain_features.clear()
	
	match layout_name:
		"layout_2":
			_setup_layout_2()
		_:
			print("[TerrainManager] Unknown layout: ", layout_name)
	
	emit_signal("terrain_loaded", terrain_features)
	print("[TerrainManager] Loaded ", terrain_features.size(), " terrain pieces")

func _setup_layout_2() -> void:
	# Chapter Approved Layout 2
	# Board is 44"x60" (1760x2400 pixels at 40px per inch)
	var board_width = 1760
	var board_height = 2400
	
	# 6" x 4" ruins (4 pieces) - 240x160 pixels
	_add_terrain_piece("ruins_1", Vector2(720, 200), Vector2(240, 160), HeightCategory.TALL, 90.0)
	_add_terrain_piece("ruins_2", Vector2(1040, 2200), Vector2(240, 160), HeightCategory.TALL, 90.0)
	_add_terrain_piece("ruins_3", Vector2(440, 1080), Vector2(240, 160), HeightCategory.TALL, 90.0)  # Rotated 45 degrees
	_add_terrain_piece("ruins_4", Vector2(1320, 680), Vector2(240, 160), HeightCategory.TALL, 90.0)  # Rotated -45 degrees
	
	# 10" x 5" ruins (2 pieces) - 400x200 pixels
	_add_terrain_piece("ruins_5", Vector2(220, 1400), Vector2(400, 200), HeightCategory.TALL, 90.0)  # Rotated 30 degrees
	_add_terrain_piece("ruins_6", Vector2(1500, 1000), Vector2(400, 200), HeightCategory.MEDIUM, 90.0)  # Rotated -30 degrees
	
	# 12" x 6" ruins (6 pieces) - 480x240 pixels
	_add_terrain_piece("ruins_7", Vector2(1360, 320), Vector2(480, 240), HeightCategory.TALL, 0.0)  # Slight rotation
	_add_terrain_piece("ruins_8", Vector2(400, 440), Vector2(480, 240), HeightCategory.MEDIUM, 0.0)
	_add_terrain_piece("ruins_9", Vector2(1360, 1960), Vector2(480, 240), HeightCategory.LOW, 0.0)
	_add_terrain_piece("ruins_10", Vector2(400, 2080), Vector2(480, 240), HeightCategory.TALL, 0.0)
	_add_terrain_piece("ruins_11", Vector2(880, 760), Vector2(480, 240), HeightCategory.MEDIUM, 45.0)  # Rotated 60 degrees
	_add_terrain_piece("ruins_12", Vector2(880, 1640), Vector2(480, 240), HeightCategory.TALL, 45.0)

func _add_terrain_piece(id: String, position: Vector2, size: Vector2, height_cat: HeightCategory, rotation_degrees: float = 0.0) -> void:
	# Create polygon from position and size (rectangle)
	var half_size = size * 0.5
	
	# Create base rectangle corners
	var corners = [
		Vector2(-half_size.x, -half_size.y),
		Vector2(half_size.x, -half_size.y),
		Vector2(half_size.x, half_size.y),
		Vector2(-half_size.x, half_size.y)
	]
	
	# Apply rotation if needed
	var polygon = PackedVector2Array()
	if rotation_degrees != 0.0:
		var rotation_rad = deg_to_rad(rotation_degrees)
		for corner in corners:
			# Rotate corner around origin
			var rotated = corner.rotated(rotation_rad)
			# Translate to position
			polygon.append(position + rotated)
	else:
		# No rotation, just translate
		for corner in corners:
			polygon.append(position + corner)
	
	var height_name = ""
	match height_cat:
		HeightCategory.LOW:
			height_name = "low"
		HeightCategory.MEDIUM:
			height_name = "medium"
		HeightCategory.TALL:
			height_name = "tall"
	
	var terrain_piece = {
		"id": id,
		"type": "ruins",
		"polygon": polygon,
		"height_category": height_name,
		"position": position,
		"size": size,
		"rotation": rotation_degrees,
		"can_move_through": {
			"INFANTRY": true,
			"VEHICLE": false,
			"MONSTER": false
		}
	}
	
	terrain_features.append(terrain_piece)

func get_terrain_at_position(pos: Vector2) -> Dictionary:
	for terrain in terrain_features:
		if is_point_in_polygon(pos, terrain.polygon):
			return terrain
	return {}

func is_point_in_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	return Geometry2D.is_point_in_polygon(point, polygon)

func check_line_intersects_terrain(from_pos: Vector2, to_pos: Vector2, terrain_piece: Dictionary) -> bool:
	var polygon = terrain_piece.get("polygon", PackedVector2Array())
	if polygon.is_empty():
		return false
	
	# Check if line segment intersects any edge of the polygon
	for i in range(polygon.size()):
		var edge_start = polygon[i]
		var edge_end = polygon[(i + 1) % polygon.size()]
		
		if Geometry2D.segment_intersects_segment(from_pos, to_pos, edge_start, edge_end):
			return true
	
	return false

func can_unit_move_through_terrain(unit_keywords: Array, terrain_piece: Dictionary) -> bool:
	var can_move = terrain_piece.get("can_move_through", {})
	
	# Check if any of the unit's keywords allow movement through terrain
	for keyword in unit_keywords:
		if can_move.get(keyword, false):
			return true
	
	return false

func set_terrain_visibility(visible: bool) -> void:
	terrain_visible = visible
	emit_signal("terrain_visibility_changed", visible)

func toggle_terrain_visibility() -> void:
	set_terrain_visibility(not terrain_visible)

func get_terrain_for_save() -> Array:
	# Return simplified terrain data for saving
	var save_data = []
	for terrain in terrain_features:
		save_data.append({
			"id": terrain.id,
			"type": terrain.type,
			"position": [terrain.position.x, terrain.position.y],
			"size": [terrain.size.x, terrain.size.y],
			"height_category": terrain.height_category
		})
	return save_data

func load_terrain_from_save(save_data: Array) -> void:
	terrain_features.clear()
	
	for terrain_data in save_data:
		var pos = Vector2(terrain_data.position[0], terrain_data.position[1])
		var size = Vector2(terrain_data.size[0], terrain_data.size[1])
		var height_cat = HeightCategory.TALL
		
		match terrain_data.height_category:
			"low":
				height_cat = HeightCategory.LOW
			"medium":
				height_cat = HeightCategory.MEDIUM
			"tall":
				height_cat = HeightCategory.TALL
		
		_add_terrain_piece(terrain_data.id, pos, size, height_cat)
	
	emit_signal("terrain_loaded", terrain_features)