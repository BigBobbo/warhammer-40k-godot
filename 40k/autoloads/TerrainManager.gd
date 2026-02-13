extends Node

# TerrainManager - Manages terrain features and their interactions
# Handles terrain data, layout configurations, and terrain-related rules
# Supports data-driven terrain loading from JSON layout files

signal terrain_loaded(terrain_features: Array)
signal terrain_visibility_changed(visible: bool)

var terrain_features: Array = []
var terrain_visible: bool = true
var current_layout: String = "layout_2"

# Cache of loaded layout metadata for UI recommendations
var _layout_metadata: Dictionary = {}

# Terrain height categories affect line of sight
enum HeightCategory {
	LOW,      # <2" - provides cover but doesn't block LoS
	MEDIUM,   # 2-5" - provides cover, partial LoS blocking
	TALL      # >5" - blocks LoS completely (obscuring)
}

# Standard wall movement blocking rules for ruins
const DEFAULT_WALL_BLOCKS_MOVEMENT = {
	"INFANTRY": false,
	"VEHICLE": true,
	"MONSTER": true
}

func _ready() -> void:
	print("[TerrainManager] Initializing terrain system")
	_preload_layout_metadata()
	load_terrain_layout(current_layout)

func _preload_layout_metadata() -> void:
	# Load metadata (name, description, recommended deployments) from all layout JSON files
	for i in range(1, 9):
		var layout_id = "layout_%d" % i
		var json_path = "res://terrain_layouts/%s.json" % layout_id
		if FileAccess.file_exists(json_path):
			var file = FileAccess.open(json_path, FileAccess.READ)
			if file:
				var json = JSON.new()
				var parse_result = json.parse(file.get_as_text())
				file.close()
				if parse_result == OK:
					var data = json.data
					_layout_metadata[layout_id] = {
						"id": data.get("id", layout_id),
						"name": data.get("name", "Layout %d" % i),
						"description": data.get("description", ""),
						"recommended_deployments": data.get("recommended_deployments", [])
					}
	print("[TerrainManager] Preloaded metadata for ", _layout_metadata.size(), " terrain layouts")

func get_layout_metadata(layout_id: String) -> Dictionary:
	return _layout_metadata.get(layout_id, {})

func get_all_layout_ids() -> Array:
	var ids = []
	for i in range(1, 9):
		var layout_id = "layout_%d" % i
		if _layout_metadata.has(layout_id):
			ids.append(layout_id)
	return ids

func get_recommended_deployments(layout_id: String) -> Array:
	var metadata = get_layout_metadata(layout_id)
	return metadata.get("recommended_deployments", [])

func load_terrain_layout(layout_name: String) -> void:
	terrain_features.clear()
	current_layout = layout_name

	# Try loading from JSON first
	if _load_layout_from_json(layout_name):
		print("[TerrainManager] Loaded layout '%s' from JSON (%d terrain pieces)" % [layout_name, terrain_features.size()])
	else:
		# Fallback to hardcoded layouts
		match layout_name:
			"layout_2":
				_setup_layout_2()
				print("[TerrainManager] Loaded layout_2 from hardcoded fallback (%d terrain pieces)" % terrain_features.size())
			_:
				print("[TerrainManager] Unknown layout: ", layout_name)

	emit_signal("terrain_loaded", terrain_features)

func _load_layout_from_json(layout_name: String) -> bool:
	var json_path = "res://terrain_layouts/%s.json" % layout_name
	if not FileAccess.file_exists(json_path):
		print("[TerrainManager] No JSON file found at: ", json_path)
		return false

	var file = FileAccess.open(json_path, FileAccess.READ)
	if not file:
		print("[TerrainManager] Failed to open JSON file: ", json_path)
		return false

	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()

	if parse_result != OK:
		print("[TerrainManager] Failed to parse JSON: ", json.get_error_message(), " at line ", json.get_error_line())
		return false

	var data = json.data
	if not data.has("pieces"):
		print("[TerrainManager] JSON layout missing 'pieces' array")
		return false

	var px_per_inch = Measurement.PX_PER_INCH

	for piece_data in data.pieces:
		var pos_inches = piece_data.get("position", [0, 0])
		var size_inches = piece_data.get("size", [6, 4])
		var height_str = piece_data.get("height", "tall")
		var rotation_deg = piece_data.get("rotation", 0.0)
		var piece_id = piece_data.get("id", "terrain")

		# Convert inches to pixels
		var position_px = Vector2(pos_inches[0] * px_per_inch, pos_inches[1] * px_per_inch)
		var size_px = Vector2(size_inches[0] * px_per_inch, size_inches[1] * px_per_inch)

		var height_cat = _parse_height_category(height_str)

		_add_terrain_piece(piece_id, position_px, size_px, height_cat, rotation_deg)

		# Process walls from JSON (local coordinates -> absolute world coordinates)
		var json_walls = piece_data.get("walls", [])
		if json_walls.size() > 0:
			var converted_walls = _convert_json_walls(piece_id, json_walls, position_px, rotation_deg, px_per_inch)
			_add_walls_to_terrain(piece_id, converted_walls)

	return true

func _parse_height_category(height_str: String) -> HeightCategory:
	match height_str:
		"low":
			return HeightCategory.LOW
		"medium":
			return HeightCategory.MEDIUM
		"tall":
			return HeightCategory.TALL
		_:
			return HeightCategory.TALL

func _convert_json_walls(terrain_id: String, json_walls: Array, position_px: Vector2, rotation_deg: float, px_per_inch: float) -> Array:
	# Convert wall definitions from local coordinates (inches) to absolute world coordinates (pixels)
	var walls = []
	var rotation_rad = deg_to_rad(rotation_deg)

	for wall_data in json_walls:
		var local_start = wall_data.get("local_start", [0, 0])
		var local_end = wall_data.get("local_end", [0, 0])

		# Convert local coordinates from inches to pixels
		var start_local_px = Vector2(local_start[0] * px_per_inch, local_start[1] * px_per_inch)
		var end_local_px = Vector2(local_end[0] * px_per_inch, local_end[1] * px_per_inch)

		# Apply rotation if needed
		if rotation_deg != 0.0:
			start_local_px = start_local_px.rotated(rotation_rad)
			end_local_px = end_local_px.rotated(rotation_rad)

		# Translate to absolute world position
		var wall_start = position_px + start_local_px
		var wall_end = position_px + end_local_px

		var wall = {
			"id": "%s_%s" % [terrain_id, wall_data.get("id", "wall")],
			"start": wall_start,
			"end": wall_end,
			"type": wall_data.get("type", "solid"),
			"blocks_movement": DEFAULT_WALL_BLOCKS_MOVEMENT.duplicate(),
			"blocks_los": wall_data.get("blocks_los", true)
		}
		walls.append(wall)

	return walls

func _setup_layout_2() -> void:
	# Chapter Approved Layout 2 - Hardcoded fallback
	# Board is 44"x60" (1760x2400 pixels at 40px per inch)
	var board_width = 1760
	var board_height = 2400

	# 6" x 4" ruins (4 pieces) - 240x160 pixels
	_add_terrain_piece("ruins_1", Vector2(720, 200), Vector2(240, 160), HeightCategory.TALL, 90.0)
	_add_terrain_piece("ruins_2", Vector2(1040, 2200), Vector2(240, 160), HeightCategory.TALL, 90.0)
	_add_terrain_piece("ruins_3", Vector2(440, 1080), Vector2(240, 160), HeightCategory.TALL, 90.0)
	_add_terrain_piece("ruins_4", Vector2(1320, 1320), Vector2(240, 160), HeightCategory.TALL, 90.0)

	# 10" x 5" ruins (2 pieces) - 400x200 pixels
	_add_terrain_piece("ruins_5", Vector2(260, 1400), Vector2(400, 200), HeightCategory.TALL, 90.0)
	_add_terrain_piece("ruins_6", Vector2(1500, 1000), Vector2(400, 200), HeightCategory.TALL, 90.0)

	# 12" x 6" ruins (6 pieces) - 480x240 pixels
	_add_terrain_piece("ruins_7", Vector2(1360, 320), Vector2(480, 240), HeightCategory.TALL, 0.0)
	_add_terrain_piece("ruins_8", Vector2(400, 440), Vector2(480, 240), HeightCategory.MEDIUM, 0.0)
	_add_terrain_piece("ruins_9", Vector2(1360, 1960), Vector2(480, 240), HeightCategory.LOW, 0.0)
	_add_terrain_piece("ruins_10", Vector2(400, 2080), Vector2(480, 240), HeightCategory.TALL, 0.0)
	_add_terrain_piece("ruins_11", Vector2(880, 760), Vector2(480, 240), HeightCategory.MEDIUM, -45.0)
	_add_terrain_piece("ruins_12", Vector2(880, 1640), Vector2(480, 240), HeightCategory.TALL, -45.0)

	# Add walls to terrain pieces based on layout diagram
	_add_sample_walls_to_terrain()

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

# Wall management methods
func add_wall_to_terrain(terrain_id: String, wall_data: Dictionary) -> void:
	for terrain in terrain_features:
		if terrain.id == terrain_id:
			if not terrain.has("walls"):
				terrain["walls"] = []
			terrain.walls.append(wall_data)
			emit_signal("terrain_loaded", terrain_features)
			break

func check_line_intersects_wall(from_pos: Vector2, to_pos: Vector2, wall: Dictionary) -> bool:
	var wall_start = wall.get("start", Vector2.ZERO)
	var wall_end = wall.get("end", Vector2.ZERO)

	# Check if movement line intersects wall segment
	var intersection = Geometry2D.segment_intersects_segment(
		from_pos, to_pos, wall_start, wall_end
	)
	return intersection != null

func can_unit_cross_wall(unit_keywords: Array, wall: Dictionary) -> bool:
	var blocks_movement = wall.get("blocks_movement", {})

	# Check each keyword
	for keyword in unit_keywords:
		if blocks_movement.get(keyword, true) == false:
			return true

	# Check FLY keyword separately - flying units go over walls
	if "FLY" in unit_keywords:
		return true

	return false

func _add_walls_to_terrain(terrain_id: String, walls: Array) -> void:
	for terrain in terrain_features:
		if terrain.id == terrain_id:
			terrain["walls"] = walls
			break

func _add_sample_walls_to_terrain() -> void:
	# Add walls to select terrain pieces based on the layout diagram
	# These walls represent the light grey sections in the attached layout

	# ruins_1 - 6"x4" piece at (720, 200), rotated 90 degrees
	# Since it's rotated 90 degrees, width and height are swapped
	var ruins_1_walls = []
	var r1_pos = Vector2(720, 200)
	# After 90 degree rotation: original 240x160 becomes 160x240
	var r1_half = Vector2(80, 120)  # Half of rotated size
	ruins_1_walls.append({
		"id": "ruins_1_wall_north",
		"start": Vector2(640, 80),  # Left edge of rotated ruins_1
		"end": Vector2(800, 80),    # Right edge of rotated ruins_1
		"type": "solid",
		"blocks_movement": {"INFANTRY": false, "VEHICLE": true, "MONSTER": true},
		"blocks_los": true
	})
	ruins_1_walls.append({
		"id": "ruins_1_wall_west",
		"start": Vector2(640, 80),   # Top-left corner
		"end": Vector2(640, 200),    # Mid-left side
		"type": "window",
		"blocks_movement": {"INFANTRY": false, "VEHICLE": true, "MONSTER": true},
		"blocks_los": false
	})
	_add_walls_to_terrain("ruins_1", ruins_1_walls)

	# ruins_7 - 12"x6" piece at (1360, 320), no rotation
	var ruins_7_walls = []
	# Position: 1360, 320; Size: 480x240
	# Boundaries: x: 1120-1600, y: 200-440
	ruins_7_walls.append({
		"id": "ruins_7_wall_north",
		"start": Vector2(1120, 200),  # Top-left corner
		"end": Vector2(1600, 200),    # Top-right corner
		"type": "solid",
		"blocks_movement": {"INFANTRY": false, "VEHICLE": true, "MONSTER": true},
		"blocks_los": true
	})
	ruins_7_walls.append({
		"id": "ruins_7_wall_south",
		"start": Vector2(1120, 440),  # Bottom-left corner
		"end": Vector2(1600, 440),    # Bottom-right corner
		"type": "solid",
		"blocks_movement": {"INFANTRY": false, "VEHICLE": true, "MONSTER": true},
		"blocks_los": true
	})
	ruins_7_walls.append({
		"id": "ruins_7_wall_west",
		"start": Vector2(1120, 280),  # Left side, upper third
		"end": Vector2(1120, 360),    # Left side, lower third
		"type": "door",
		"blocks_movement": {"INFANTRY": false, "VEHICLE": true, "MONSTER": true},
		"blocks_los": false
	})
	# Add an east wall with a window
	ruins_7_walls.append({
		"id": "ruins_7_wall_east",
		"start": Vector2(1600, 250),  # Right side
		"end": Vector2(1600, 390),    # Right side
		"type": "window",
		"blocks_movement": {"INFANTRY": false, "VEHICLE": true, "MONSTER": true},
		"blocks_los": false  # Windows don't block line of sight
	})
	_add_walls_to_terrain("ruins_7", ruins_7_walls)

	# ruins_8 - 12"x6" piece at (400, 440), no rotation
	var ruins_8_walls = []
	# Position: 400, 440; Size: 480x240
	# Boundaries: x: 160-640, y: 320-560
	ruins_8_walls.append({
		"id": "ruins_8_wall_east",
		"start": Vector2(640, 320),   # Right side, top
		"end": Vector2(640, 560),     # Right side, bottom
		"type": "solid",
		"blocks_movement": {"INFANTRY": false, "VEHICLE": true, "MONSTER": true},
		"blocks_los": true
	})
	ruins_8_walls.append({
		"id": "ruins_8_wall_center",
		"start": Vector2(280, 440),   # Center horizontal wall, left
		"end": Vector2(520, 440),     # Center horizontal wall, right
		"type": "window",
		"blocks_movement": {"INFANTRY": false, "VEHICLE": true, "MONSTER": true},
		"blocks_los": false
	})
	_add_walls_to_terrain("ruins_8", ruins_8_walls)

	# ruins_10 - 12"x6" piece at (400, 2080), no rotation
	var ruins_10_walls = []
	# Position: 400, 2080; Size: 480x240
	# Boundaries: x: 160-640, y: 1960-2200
	ruins_10_walls.append({
		"id": "ruins_10_wall_north",
		"start": Vector2(160, 1960),   # Top-left corner
		"end": Vector2(640, 1960),     # Top-right corner
		"type": "solid",
		"blocks_movement": {"INFANTRY": false, "VEHICLE": true, "MONSTER": true},
		"blocks_los": true
	})
	ruins_10_walls.append({
		"id": "ruins_10_wall_west",
		"start": Vector2(160, 1960),   # Left side, top
		"end": Vector2(160, 2200),     # Left side, bottom
		"type": "solid",
		"blocks_movement": {"INFANTRY": false, "VEHICLE": true, "MONSTER": true},
		"blocks_los": true
	})
	_add_walls_to_terrain("ruins_10", ruins_10_walls)

	# ruins_11 - 12"x6" piece at (880, 760), rotated -45 degrees
	var ruins_11_walls = []
	# For rotated piece, calculate wall along one edge
	var r11_pos = Vector2(880, 760)
	var r11_rot = deg_to_rad(-45.0)

	# Top edge of rotated rectangle
	var start_offset = Vector2(-240, -120).rotated(r11_rot)
	var end_offset = Vector2(240, -120).rotated(r11_rot)

	ruins_11_walls.append({
		"id": "ruins_11_wall_north",
		"start": r11_pos + start_offset,
		"end": r11_pos + end_offset,
		"type": "solid",
		"blocks_movement": {"INFANTRY": false, "VEHICLE": true, "MONSTER": true},
		"blocks_los": true
	})
	_add_walls_to_terrain("ruins_11", ruins_11_walls)

	print("[TerrainManager] Added walls to terrain pieces")

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
			"height_category": terrain.height_category,
			"rotation": terrain.get("rotation", 0.0),
			"layout": current_layout
		})
	return save_data

func load_terrain_from_save(save_data: Array) -> void:
	terrain_features.clear()

	# Check if save data includes layout info for full reload
	if save_data.size() > 0 and save_data[0].has("layout"):
		var saved_layout = save_data[0].get("layout", "")
		if saved_layout != "" and _load_layout_from_json(saved_layout):
			current_layout = saved_layout
			emit_signal("terrain_loaded", terrain_features)
			return

	# Fallback: reconstruct from save data
	for terrain_data in save_data:
		var pos = Vector2(terrain_data.position[0], terrain_data.position[1])
		var size = Vector2(terrain_data.size[0], terrain_data.size[1])
		var rotation = terrain_data.get("rotation", 0.0)
		var height_cat = HeightCategory.TALL

		match terrain_data.height_category:
			"low":
				height_cat = HeightCategory.LOW
			"medium":
				height_cat = HeightCategory.MEDIUM
			"tall":
				height_cat = HeightCategory.TALL

		_add_terrain_piece(terrain_data.id, pos, size, height_cat, rotation)

	emit_signal("terrain_loaded", terrain_features)
