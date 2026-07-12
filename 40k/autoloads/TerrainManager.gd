extends Node

# TerrainManager - Manages terrain features and their interactions
# Handles terrain data, layout configurations, and terrain-related rules
# Supports data-driven terrain loading from JSON layout files

signal terrain_loaded(terrain_features: Array)
signal terrain_visibility_changed(visible: bool)

var terrain_features: Array = []
var terrain_visible: bool = true
var current_layout: String = "layout_2"

# D3-a: objective markers authored by the loaded layout (the converted 11e
# layouts carry an objectives[] array; legacy layouts don't). Raw JSON dicts
# — id, position [x,y] inches, radius_mm, zone. MissionManager prefers these
# over the deployment-zone objectives when non-empty.
var layout_objectives: Array = []

# Cache of loaded layout metadata for UI recommendations
var _layout_metadata: Dictionary = {}

# Ids of the converted official 11e layouts (from terrain_layouts/index_11e.json),
# in index order. Kept separate so get_all_layout_ids can list legacy first.
var _layout_ids_11e: Array = []

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

## TER-4: Obscuring terrain trait.
## Terrain with the "obscuring" trait blocks line of sight for models that are
## not within the terrain feature, regardless of height category.
## Per 10e rules: if the line between two models passes through an Obscuring
## terrain feature and neither model is within it, LoS is blocked.
## Tall terrain (>5") is implicitly Obscuring even without the trait.
const OBSCURING_TRAIT: String = "obscuring"

## T3-16: Difficult Ground terrain trait penalty in inches.
## When a unit moves through terrain with the "difficult_ground" trait,
## this flat penalty is added to the effective movement distance per terrain piece.
## FLY units ignore this penalty entirely.
const DIFFICULT_GROUND_PENALTY_INCHES: float = 2.0

func _ready() -> void:
	print("[TerrainManager] Initializing terrain system")
	_preload_layout_metadata()
	load_terrain_layout(current_layout)

func _preload_layout_metadata() -> void:
	# Load metadata (name, description, recommended deployments) from all layout JSON files
	var ids_to_load: Array = []
	for i in range(1, 9):
		ids_to_load.append("layout_%d" % i)
	# Parse-test layouts (catalog-based parser output, see tools/PARSE_TERRAIN_GUIDE.md)
	ids_to_load.append("layout_parse_test")
	ids_to_load.append("layout_parse_test_1")
	for layout_id in ids_to_load:
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
						"name": data.get("name", layout_id),
						"description": data.get("description", ""),
						"recommended_deployments": data.get("recommended_deployments", [])
					}
	_preload_11e_layout_index()
	print("[TerrainManager] Preloaded metadata for ", _layout_metadata.size(), " terrain layouts")

## Register the converted official 11e layouts from the generated registry
## (scripts/40kdc/generate-terrain-layouts.mjs writes index_11e.json alongside
## the 45 layout files). Metadata-only — layout JSON parses on demand.
func _preload_11e_layout_index() -> void:
	var index_path = "res://terrain_layouts/index_11e.json"
	if not FileAccess.file_exists(index_path):
		print("[TerrainManager] No 11e layout index at ", index_path)
		return
	var file = FileAccess.open(index_path, FileAccess.READ)
	if not file:
		return
	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()
	if parse_result != OK:
		print("[TerrainManager] Failed to parse index_11e.json: ", json.get_error_message())
		return
	_layout_ids_11e.clear()
	for entry in json.data.get("layouts", []):
		var layout_id = str(entry.get("id", ""))
		if layout_id == "":
			continue
		_layout_ids_11e.append(layout_id)
		_layout_metadata[layout_id] = {
			"id": layout_id,
			"name": entry.get("name", layout_id),
			"description": "",
			"recommended_deployments": entry.get("recommended_deployments", []),
			"mission_matchup_id": entry.get("mission_matchup_id", ""),
			"variant": int(entry.get("variant", 0)),
			"piece_count": int(entry.get("piece_count", 0)),
			"source": "gw-11e"
		}
	print("[TerrainManager] Registered ", _layout_ids_11e.size(), " official 11e terrain layouts")

func get_layout_metadata(layout_id: String) -> Dictionary:
	return _layout_metadata.get(layout_id, {})

func get_all_layout_ids() -> Array:
	var ids = []
	for i in range(1, 9):
		var layout_id = "layout_%d" % i
		if _layout_metadata.has(layout_id):
			ids.append(layout_id)
	for extra_id in ["layout_parse_test", "layout_parse_test_1"]:
		if _layout_metadata.has(extra_id):
			ids.append(extra_id)
	ids.append_array(_layout_ids_11e)
	return ids

## Ids of the converted official 11e layouts (matchup/variant metadata is in
## get_layout_metadata). Empty if the generated index is absent.
func get_11e_layout_ids() -> Array:
	return _layout_ids_11e.duplicate()

## D5: the official 11e layouts for a Force-Disposition pairing. Takes the
## game's underscore disposition ids (e.g. "take_and_hold", as used by
## PrimaryMissionData11e.DISPOSITIONS), converts to the dataset's hyphenated
## form, and tries both orderings of the matchup id — the dataset authors one
## canonical ordering per unordered pairing (mirrors use "<a>-vs-<a>").
## Returns the layout metadata dictionaries sorted by variant (1..3);
## empty if the 11e index isn't present or the pairing is unknown.
func get_layouts_for_matchup(disposition_a: String, disposition_b: String) -> Array:
	var a := disposition_a.replace("_", "-")
	var b := disposition_b.replace("_", "-")
	for candidate in ["%s-vs-%s" % [a, b], "%s-vs-%s" % [b, a]]:
		var found: Array = []
		for layout_id in _layout_ids_11e:
			var meta = _layout_metadata.get(layout_id, {})
			if str(meta.get("mission_matchup_id", "")) == candidate:
				found.append(meta)
		if not found.is_empty():
			found.sort_custom(func(x, y): return int(x.get("variant", 0)) < int(y.get("variant", 0)))
			return found
	return []

func get_recommended_deployments(layout_id: String) -> Array:
	var metadata = get_layout_metadata(layout_id)
	return metadata.get("recommended_deployments", [])

func load_terrain_layout(layout_name: String) -> void:
	terrain_features.clear()
	layout_objectives.clear()
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

	# Issue #385: mirror the loaded terrain into GameState.state.board.terrain
	# so MovementPhase._position_intersects_terrain (which reads from there)
	# can actually find impassable pieces. Pre-fix this was perpetually empty.
	if has_node("/root/GameState"):
		var gs = get_node("/root/GameState")
		if gs.state.has("board"):
			gs.state["board"]["terrain"] = terrain_features.duplicate(true)
			print("[TerrainManager] Mirrored %d terrain pieces into state.board.terrain" % terrain_features.size())

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

	# D3-a: converted 11e layouts author their own objective markers.
	layout_objectives = data.get("objectives", [])
	if layout_objectives.size() > 0:
		print("[TerrainManager] Layout '%s' authors %d objective markers (layout-sourced, D3-a)" % [layout_name, layout_objectives.size()])

	var px_per_inch = Measurement.PX_PER_INCH

	for piece_data in data.pieces:
		var pos_inches = piece_data.get("position", [0, 0])
		var height_str = piece_data.get("height", "tall")
		var rotation_deg = piece_data.get("rotation", 0.0)
		var piece_id = piece_data.get("id", "terrain")
		var piece_type = piece_data.get("type", "ruins")

		var position_px = Vector2(pos_inches[0] * px_per_inch, pos_inches[1] * px_per_inch)
		var height_cat = _parse_height_category(height_str)
		var piece_traits = piece_data.get("traits", [])  # T3-16: load terrain traits

		if piece_data.has("polygon"):
			# Explicit-polygon piece (11e converted layouts, spec Decision D1):
			# vertices are absolute board inches with rotation already baked in.
			_add_polygon_terrain_piece(piece_data, position_px, height_cat, piece_type, piece_traits, px_per_inch)
		else:
			# Legacy path: axis-aligned rectangle from position + size + rotation.
			var size_inches = piece_data.get("size", [6, 4])
			var size_px = Vector2(size_inches[0] * px_per_inch, size_inches[1] * px_per_inch)
			_add_terrain_piece(piece_id, position_px, size_px, height_cat, rotation_deg, piece_type, piece_traits)

		# Process walls from JSON (local coordinates -> absolute world coordinates)
		var json_walls = piece_data.get("walls", [])
		if json_walls.size() > 0:
			var converted_walls = _convert_json_walls(piece_id, json_walls, position_px, rotation_deg, px_per_inch)
			_add_walls_to_terrain(piece_id, converted_walls)

	return true

## Build a runtime terrain piece from an explicit-polygon JSON piece (the 11e
## converted layouts emitted by scripts/40kdc/generate-terrain-layouts.mjs).
## Also plumbs the 11e metadata fields (piece_class, floor, category,
## height_inches, objective flags, link_group) onto the runtime dict so
## mission/rules code can read them (spec §4).
func _add_polygon_terrain_piece(piece_data: Dictionary, position_px: Vector2, height_cat: HeightCategory, terrain_type: String, piece_traits: Array, px_per_inch: float) -> void:
	var piece_id = piece_data.get("id", "terrain")
	var polygon = PackedVector2Array()
	for vert in piece_data.get("polygon", []):
		polygon.append(Vector2(float(vert[0]) * px_per_inch, float(vert[1]) * px_per_inch))
	if polygon.size() < 3:
		print("[TerrainManager] Skipping polygon piece '%s' — fewer than 3 vertices" % str(piece_id))
		return

	# Bounding box: keeps save-data and badge placement working for shapes
	# that have no explicit size.
	var min_v = polygon[0]
	var max_v = polygon[0]
	for v in polygon:
		min_v = min_v.min(v)
		max_v = max_v.max(v)

	var height_name = ""
	match height_cat:
		HeightCategory.LOW:
			height_name = "low"
		HeightCategory.MEDIUM:
			height_name = "medium"
		HeightCategory.TALL:
			height_name = "tall"

	var terrain_piece = {
		"id": piece_id,
		"type": terrain_type,
		"polygon": polygon,
		"height_category": height_name,
		"position": position_px,
		"size": max_v - min_v,
		"rotation": float(piece_data.get("rotation", 0.0)),
		"can_move_through": {
			"INFANTRY": true,
			"VEHICLE": false,
			"MONSTER": false
		},
		"traits": piece_traits,
		"piece_class": str(piece_data.get("piece_class", "feature")),
		"floor": int(piece_data.get("floor", 0))
	}
	if piece_data.has("height_inches"):
		terrain_piece["height_inches"] = float(piece_data["height_inches"])
	if piece_data.has("category"):
		terrain_piece["category"] = str(piece_data["category"])
	if piece_data.has("is_objective"):
		terrain_piece["is_objective"] = bool(piece_data["is_objective"])
	if piece_data.has("objective_role"):
		terrain_piece["objective_role"] = str(piece_data["objective_role"])
	if piece_data.has("link_group"):
		terrain_piece["link_group"] = str(piece_data["link_group"])
	if piece_data.has("parent_area_id"):
		terrain_piece["parent_area_id"] = str(piece_data["parent_area_id"])

	terrain_features.append(terrain_piece)

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

func _add_terrain_piece(id: String, position: Vector2, size: Vector2, height_cat: HeightCategory, rotation_degrees: float = 0.0, terrain_type: String = "ruins", traits: Array = []) -> void:
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
		"type": terrain_type,
		"polygon": polygon,
		"height_category": height_name,
		"position": position,
		"size": size,
		"rotation": rotation_degrees,
		"can_move_through": {
			"INFANTRY": true,
			"VEHICLE": false,
			"MONSTER": false
		},
		"traits": traits  # T3-16: terrain traits like "difficult_ground"
	}

	terrain_features.append(terrain_piece)

## T3-9: standard and barricade engagement ranges now live in GameConstants
## (ISS-002) so the edition switch applies everywhere at once.

## T3-9: Check if a barricade terrain feature lies between two positions.
## Returns true if the line from pos1 to pos2 crosses a barricade terrain piece.
func is_barricade_between(pos1: Vector2, pos2: Vector2) -> bool:
	for terrain in terrain_features:
		if terrain.get("type", "") != "barricade":
			continue
		if check_line_intersects_terrain(pos1, pos2, terrain):
			print("[TerrainManager] Barricade '%s' detected between positions" % terrain.get("id", "unknown"))
			return true
	return false

## T3-9: Get the effective engagement range between two model positions.
## Returns the barricade engagement range (2") if a barricade lies between
## them, otherwise the standard edition-dependent engagement range.
func get_engagement_range_for_positions(pos1: Vector2, pos2: Vector2) -> float:
	if is_barricade_between(pos1, pos2):
		return GameConstants.barricade_engagement_range_inches()
	return GameConstants.engagement_range_inches()

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

## Returns the height in inches for a terrain height category.
## LOW (<2") = 1.5", MEDIUM (2-5") = 3.5", TALL (>5") = 6.0"
func get_height_inches(terrain_piece: Dictionary) -> float:
	var height_cat = terrain_piece.get("height_category", "tall")
	match height_cat:
		"low":
			return 1.5  # Representative height for <2" terrain
		"medium":
			return 3.5  # Representative height for 2-5" terrain
		"tall":
			return 6.0  # Representative height for >5" terrain
		_:
			return 6.0  # Default to tall

## T3-16: Get the traits array for a terrain piece. Returns empty array if none.
func get_terrain_traits(terrain_piece: Dictionary) -> Array:
	return terrain_piece.get("traits", [])

## T3-16: Check if a terrain piece has a specific trait.
func has_terrain_trait(terrain_piece: Dictionary, trait_name: String) -> bool:
	return trait_name in get_terrain_traits(terrain_piece)

## TER-4: Check if a terrain piece has the Obscuring trait.
## Terrain is considered Obscuring if it explicitly has the "obscuring" trait
## OR if it is tall (>5") — tall terrain is implicitly Obscuring per 10e rules.
func is_terrain_obscuring(terrain_piece: Dictionary) -> bool:
	if has_terrain_trait(terrain_piece, OBSCURING_TRAIT):
		return true
	# Tall terrain is implicitly Obscuring
	return terrain_piece.get("height_category", "") == "tall"

## Calculate the terrain penalty for a charge path crossing terrain.
## Terrain 2" or less has no climb penalty.
## Terrain taller than 2" requires counting vertical distance (climb up + down).
## T3-16: Applies difficult_ground trait penalty (flat 2" per piece crossed).
## FLY units measure diagonally instead of climbing; FLY units ignore difficult ground.
##
## Returns the extra distance in inches that must be added to the path distance.
func calculate_charge_terrain_penalty(from_pos: Vector2, to_pos: Vector2, has_fly: bool, unit_keywords: Array = []) -> float:
	var total_penalty: float = 0.0
	var is_infantry = "INFANTRY" in unit_keywords

	for terrain in terrain_features:
		var polygon = terrain.get("polygon", PackedVector2Array())
		var starts_inside = is_point_in_polygon(from_pos, polygon)
		var ends_inside = is_point_in_polygon(to_pos, polygon)
		var crosses_edge = check_line_intersects_terrain(from_pos, to_pos, terrain)

		if not crosses_edge and not starts_inside and not ends_inside:
			continue

		var can_move_through = terrain.get("can_move_through", {})
		var unit_can_traverse = false
		if is_infantry and can_move_through.get("INFANTRY", false):
			unit_can_traverse = true

		# A segment wholly inside one footprint crosses no wall — ground-floor
		# movement within the same ruin pays no climb (matches movement phase).
		var wholly_inside = starts_inside and ends_inside and not crosses_edge

		# Units that can move through terrain at ground level (e.g. Infantry through ruins)
		# don't pay height climbing penalties — same as movement phase rules.
		if unit_can_traverse:
			print("[TerrainManager] Charge: %s traversable by INFANTRY — no height penalty (ground floor)" % terrain.get("id", "unknown"))
		elif wholly_inside:
			print("[TerrainManager] Charge segment wholly inside %s: no height penalty (ground floor)" % terrain.get("id", "unknown"))
		else:
			var from_inside = not polygon.is_empty() and starts_inside
			var to_inside = not polygon.is_empty() and ends_inside
			var height_inches = get_height_inches(terrain)

			if height_inches > 2.0:
				if has_fly:
					var cross_distance_px = _get_terrain_crossing_distance(from_pos, to_pos, polygon)
					var cross_distance_inches = cross_distance_px / Measurement.PX_PER_INCH
					var diagonal = sqrt(height_inches * height_inches + cross_distance_inches * cross_distance_inches)
					var fly_penalty = diagonal - cross_distance_inches
					total_penalty += fly_penalty
					print("[TerrainManager] FLY terrain penalty for %s: diagonal=%.1f\" cross=%.1f\" penalty=%.1f\"" % [
						terrain.get("id", "unknown"), diagonal, cross_distance_inches, fly_penalty])
				else:
					var climb_multiplier: float
					if from_inside or to_inside:
						climb_multiplier = 1.0
					else:
						climb_multiplier = 2.0
					var height_penalty = height_inches * climb_multiplier
					total_penalty += height_penalty
					var climb_desc = "climb up + down" if climb_multiplier == 2.0 else ("climb up" if not from_inside else "climb down")
					print("[TerrainManager] Terrain penalty for %s: %s = %.1f\" (height=%.1f\")" % [
						terrain.get("id", "unknown"), climb_desc, height_penalty, height_inches])
			else:
				print("[TerrainManager] Charge path interacts with %s: no height penalty (height <= 2\")" % terrain.get("id", "unknown"))

		# T3-16: Difficult ground trait penalty — flat 2" per terrain piece crossed
		# FLY units ignore difficult ground
		if not has_fly and has_terrain_trait(terrain, "difficult_ground"):
			total_penalty += DIFFICULT_GROUND_PENALTY_INCHES
			print("[TerrainManager] Difficult ground penalty for %s: +%.1f\"" % [
				terrain.get("id", "unknown"), DIFFICULT_GROUND_PENALTY_INCHES])

	return total_penalty

## Calculate the terrain penalty for a movement path crossing terrain.
## Units always stay on the ground floor — no vertical height penalty.
## Infantry can move through ruins walls freely; no climbing is involved.
## FLY units ignore difficult ground entirely — penalty is always 0.
## T3-16: Applies difficult_ground trait penalty (flat 2" per piece crossed).
##
## 10e Ruins fix: a unit that can move through a terrain piece (e.g. INFANTRY
## through a Ruin's walls/floors) is NOT slowed by it — Ruins are not Difficult
## Ground for such a unit, so no distance is added. Only units that cannot
## traverse the piece (e.g. VEHICLES over a low ruin) pay the flat penalty.
## Pass the moving unit's keywords via unit_keywords to enable this exemption;
## callers that omit it (legacy/tests) get the pre-fix "everyone pays" behaviour.
##
## Returns the extra distance in inches that must be added to the movement distance.
func calculate_movement_terrain_penalty(from_pos: Vector2, to_pos: Vector2, has_fly: bool, unit_keywords: Array = []) -> float:
	# FLY units ignore difficult ground entirely during movement
	if has_fly:
		print("[TerrainManager] FLY unit ignores difficult ground during movement")
		return 0.0

	var total_penalty: float = 0.0

	for terrain in terrain_features:
		var polygon = terrain.get("polygon", PackedVector2Array())
		var starts_inside = is_point_in_polygon(from_pos, polygon)
		var ends_inside = is_point_in_polygon(to_pos, polygon)
		var crosses_edge = check_line_intersects_terrain(from_pos, to_pos, terrain)

		# Skip terrain that the path doesn't interact with at all
		if not crosses_edge and not starts_inside and not ends_inside:
			continue

		# No height/climbing penalty — units stay on the ground floor.
		# Infantry move through ruins walls freely per 10e rules.
		print("[TerrainManager] Movement path interacts with %s: no height penalty (ground floor)" % terrain.get("id", "unknown"))

		# T3-16: Difficult ground trait penalty — flat 2" per terrain piece crossed.
		# 10e Ruins fix: units that can move through this piece (INFANTRY through a
		# Ruin) move freely and pay nothing — Ruins are not Difficult Ground for them.
		if has_terrain_trait(terrain, "difficult_ground"):
			if can_unit_move_through_terrain(unit_keywords, terrain):
				print("[TerrainManager] %s traversable by unit — no difficult ground penalty (moves through freely)" % terrain.get("id", "unknown"))
			else:
				total_penalty += DIFFICULT_GROUND_PENALTY_INCHES
				print("[TerrainManager] Difficult ground penalty for %s: +%.1f\"" % [
					terrain.get("id", "unknown"), DIFFICULT_GROUND_PENALTY_INCHES])

	return total_penalty

## Calculate the horizontal distance a path travels through a terrain polygon.
func _get_terrain_crossing_distance(from_pos: Vector2, to_pos: Vector2, polygon: PackedVector2Array) -> float:
	if polygon.is_empty():
		return 0.0

	# Find intersection points of the line with the polygon edges
	var intersections: Array[Vector2] = []
	for i in range(polygon.size()):
		var edge_start = polygon[i]
		var edge_end = polygon[(i + 1) % polygon.size()]
		var result = Geometry2D.segment_intersects_segment(from_pos, to_pos, edge_start, edge_end)
		if result != null:
			intersections.append(result)

	if intersections.size() >= 2:
		# Distance between the two intersection points (entry and exit)
		return intersections[0].distance_to(intersections[1])
	elif intersections.size() == 1:
		# Path starts or ends inside the terrain — use distance from intersection to whichever end is inside
		if is_point_in_polygon(from_pos, polygon):
			return from_pos.distance_to(intersections[0])
		elif is_point_in_polygon(to_pos, polygon):
			return to_pos.distance_to(intersections[0])
		return 0.0
	else:
		# Both points might be inside the terrain or no intersection
		if is_point_in_polygon(from_pos, polygon) and is_point_in_polygon(to_pos, polygon):
			return from_pos.distance_to(to_pos)
		return 0.0

## Get all terrain pieces that a path segment crosses which are taller than 2".
func get_tall_terrain_on_path(from_pos: Vector2, to_pos: Vector2) -> Array:
	var results = []
	for terrain in terrain_features:
		var height_inches = get_height_inches(terrain)
		if height_inches <= 2.0:
			continue
		if check_line_intersects_terrain(from_pos, to_pos, terrain):
			results.append(terrain)
	return results

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
			"traits": terrain.get("traits", []),  # T3-16: save terrain traits
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

		var saved_type = terrain_data.get("type", "ruins")
		var saved_traits = terrain_data.get("traits", [])  # T3-16: restore terrain traits
		_add_terrain_piece(terrain_data.id, pos, size, height_cat, rotation, saved_type, saved_traits)

	emit_signal("terrain_loaded", terrain_features)


# ════════════════════════════════════════════════════════════════════
# ISS-051 (step 1): 11e terrain model — categories + area queries
# (core rules 13.01-13.05). Derived from the existing runtime pieces so
# current layouts keep working; layout schema v2 can override per piece
# via explicit "category" / "height_inches" fields when authored.
# ════════════════════════════════════════════════════════════════════

## 13.03-13.05 terrain categories.
const CATEGORY_EXPOSED := "exposed"
const CATEGORY_LIGHT := "light"
const CATEGORY_DENSE := "dense"

## Map a runtime terrain piece to its 11e category.
## Explicit piece "category" wins; otherwise derived from type:
##   ruins / woods / building / container -> dense (13.05)
##   barricade / low walls / statuary     -> light (13.04)
##   craters / debris / razorwire / other -> exposed (13.03)
static func category_of(piece: Dictionary) -> String:
	var explicit = str(piece.get("category", ""))
	if explicit in [CATEGORY_EXPOSED, CATEGORY_LIGHT, CATEGORY_DENSE]:
		return explicit
	match str(piece.get("type", "")):
		"ruins", "woods", "building", "container":
			return CATEGORY_DENSE
		"barricade", "wall", "statuary":
			return CATEGORY_LIGHT
		_:
			return CATEGORY_EXPOSED

## Numeric feature height in inches. Explicit "height_inches" wins;
## otherwise derived from the legacy height_category labels
## (low <2", medium 2-5", tall >5") at documented representative values.
static func height_inches_of(piece: Dictionary) -> float:
	if piece.has("height_inches"):
		return float(piece.height_inches)
	match str(piece.get("height_category", "")):
		"low":
			return 1.5
		"medium":
			return 3.5
		"tall":
			return 6.0
		_:
			return 0.0

## 13.01: each piece footprint is its terrain AREA (until layouts author
## multi-feature area boundaries explicitly via schema v2). Returns the
## piece whose area contains the point, or {} if open ground.
func area_at(point: Vector2) -> Dictionary:
	for piece in terrain_features:
		var poly = piece.get("polygon", PackedVector2Array())
		if poly.size() >= 3 and Geometry2D.is_point_in_polygon(point, poly):
			return piece
	return {}

## Pieces whose footprint the segment from `from_pos` to `to_pos` crosses
## (entering, leaving, or passing through). Used by 11e obscuring/solid
## visibility (ISS-052) and movement gating (ISS-054).
func features_crossing(from_pos: Vector2, to_pos: Vector2) -> Array:
	var crossed: Array = []
	for piece in terrain_features:
		if check_line_intersects_terrain(from_pos, to_pos, piece):
			crossed.append(piece)
	return crossed

## True if every line between the two points crosses at least one
## obscuring (light or dense) feature that NEITHER point is within —
## the center-line approximation of 13.10 used until ISS-052's full
## visibility module lands.
func is_obscured_between(p1: Vector2, p2: Vector2) -> bool:
	var inside_ids := {}
	var a1 = area_at(p1)
	var a2 = area_at(p2)
	if not a1.is_empty():
		inside_ids[a1.get("id")] = true
	if not a2.is_empty():
		inside_ids[a2.get("id")] = true
	for piece in features_crossing(p1, p2):
		if inside_ids.has(piece.get("id")):
			continue
		var cat = category_of(piece)
		if cat == CATEGORY_LIGHT or cat == CATEGORY_DENSE:
			return true
	return false


## ISS-052 (step 1) — 13.09 HIDDEN. A model is hidden while:
##   ▪ it has the INFANTRY/BEASTS/SWARM keyword AND is within a terrain
##     area that contains one or more DENSE terrain features, and
##   ▪ its unit made no ranged attacks this turn or the previous turn
##     (tracked via the unit flag `shot_recently`, maintained by the
##     shooting phase when ISS-048 lands; callers pass the unit).
## While hidden, the model is only visible to enemies within its
## detection range — 15" unless otherwise stated
## (GameConstants.hidden_detection_range_inches()).
func is_model_hidden(model: Dictionary, unit: Dictionary) -> bool:
	if GameConstants.edition < 11:
		return false
	var keywords: Array = unit.get("meta", {}).get("keywords", [])
	var qualifies := false
	for kw in ["INFANTRY", "BEASTS", "SWARM"]:
		if kw in keywords:
			qualifies = true
			break
	if not qualifies:
		return false
	# 13.09: a model is hidden only while its unit did NOT make ranged attacks
	# during this turn or the previous turn. ShootingPhase stamps
	# flags.last_shot_idx = battle_round*2 + (player==1?0:1) whenever the unit
	# actually shoots; "this or previous turn" = current_idx - last_shot_idx < 2.
	# The plain shot_recently flag is honoured unconditionally (headless tests
	# and effect code set it directly, without a live battle-round counter).
	if unit.get("flags", {}).get("shot_recently", false):
		return false
	var gs = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("get_battle_round"):
		var cur_idx := int(gs.get_battle_round()) * 2 + (0 if int(gs.get_active_player()) == 1 else 1)
		var last_shot_idx := int(unit.get("flags", {}).get("last_shot_idx", -100))
		if cur_idx - last_shot_idx < 2:
			return false
	var pos = model.get("position", null)
	if pos == null:
		return false
	var p := Vector2(float(pos.x) if pos is Dictionary else pos.x, float(pos.y) if pos is Dictionary else pos.y)
	var area = area_at(p)
	if area.is_empty():
		return false
	return category_of(area) == CATEGORY_DENSE

## Visibility gate for hidden models: visible only when the observer is
## within the detection range (13.09), as refined per observer by
## detection_range_inches_for (Gone to Ground, datasheet modifiers).
func hidden_model_visible_to(model: Dictionary, unit: Dictionary, observer_model: Dictionary) -> bool:
	if not is_model_hidden(model, unit):
		return true
	var det_px = Measurement.inches_to_px(detection_range_inches_for(model, unit, observer_model))
	return Measurement.model_to_model_distance_px(observer_model, model) <= det_px

## Audit Tier-1 #4 (review doc Tab 6) — a hidden model's effective
## detection range against a specific observer:
##   ▪ base: the unit's "Detection Range X\"" datasheet ability when
##     present (parsed like Lone Operative X"), else 15" (13.09).
##   ▪ Gone to Ground: −3" while the model is obscured from this
##     observer behind a dense/Solid feature — i.e. at least one
##     13.10/13.11 sight line is blocked by an intervening DENSE piece.
##   ▪ floor: modifiers never take detection range below 9".
func detection_range_inches_for(model: Dictionary, unit: Dictionary, observer_model: Dictionary) -> float:
	var range_in := detection_range_base_inches(unit)
	if _obscured_by_dense_11e(observer_model, model):
		range_in -= GameConstants.gone_to_ground_penalty_inches()
	return maxf(range_in, GameConstants.detection_range_floor_inches())

## "Detection Range X\"" datasheet ability — mirrors the Lone Operative X"
## parser (RulesEngine.get_lone_operative_range). Absent → 15" default.
func detection_range_base_inches(unit: Dictionary) -> float:
	for ab in unit.get("meta", {}).get("abilities", []):
		var nm := ""
		if ab is String:
			nm = ab
		elif ab is Dictionary:
			nm = str(ab.get("name", ""))
		if nm.to_lower().contains("detection range"):
			var digits := ""
			for c in nm:
				if c >= "0" and c <= "9":
					digits += c
				elif digits != "":
					break
			if digits != "":
				return float(digits.to_int())
	return GameConstants.hidden_detection_range_inches()

## Gone to Ground predicate: at least one observer→target sight line
## (center + 8 base-perimeter points, 13.10/13.11 semantics with both
## models' own areas excluded) is blocked by a DENSE-category piece.
func _obscured_by_dense_11e(observer: Dictionary, target: Dictionary) -> bool:
	var o = _model_vec(observer)
	var t = _model_vec(target)
	if o == Vector2.INF or t == Vector2.INF:
		return false
	var exclude := {}
	var ao = area_at(o)
	var at_ = area_at(t)
	if not ao.is_empty():
		exclude[ao.get("id")] = true
	if not at_.is_empty():
		exclude[at_.get("id")] = true
	for p in _sight_points(target):
		for piece in features_crossing(o, p):
			if exclude.has(piece.get("id")):
				continue
			if category_of(piece) == CATEGORY_DENSE:
				return true
	return false


## ISS-052 (step 2) — 06.01/13.10/13.11 visibility, 2D approximation.
## Sight lines run from the observer's base center to the target base's
## center + 8 perimeter points (base_mm/2 radius approximation for all
## base shapes). A line is BLOCKED when it crosses:
##   ▪ an obscuring (light/dense) terrain area that NEITHER model is
##     within — 13.10's every-line semantics fall out of the per-line
##     test — or
##   ▪ a DENSE feature's footprint while both models are at ground level
##     (< 3" elevation): the Solid rule's 2D effect (13.11; windows and
##     small gaps never help at ground level).
## visible = at least one clear line (06.01 MODEL VISIBLE);
## FULLY visible = every line clear (06.01 MODEL FULLY VISIBLE).

func _model_vec(model: Dictionary) -> Vector2:
	var pos = model.get("position", null)
	if pos == null:
		return Vector2.INF
	return Vector2(float(pos.x) if pos is Dictionary else pos.x, float(pos.y) if pos is Dictionary else pos.y)

func _sight_points(model: Dictionary) -> Array:
	var c = _model_vec(model)
	var out: Array = [c]
	var radius_px = Measurement.base_radius_px(int(model.get("base_mm", 32)))
	for i in range(8):
		var ang = TAU * i / 8.0
		out.append(c + Vector2(cos(ang), sin(ang)) * radius_px)
	return out

func _line_blocked_11e(a: Vector2, b: Vector2, exclude_ids: Dictionary, ground_level: bool) -> bool:
	for piece in features_crossing(a, b):
		var cat = category_of(piece)
		if exclude_ids.has(piece.get("id")):
			continue
		if cat == CATEGORY_LIGHT or cat == CATEGORY_DENSE:
			return true  # obscuring area crossed (13.10)
		if ground_level and cat == CATEGORY_DENSE:
			return true  # Solid at ground level (13.11)
	return false

func _visibility_lines_11e(observer: Dictionary, target: Dictionary) -> Dictionary:
	var o = _model_vec(observer)
	var t = _model_vec(target)
	if o == Vector2.INF or t == Vector2.INF:
		return {"clear": 0, "total": 0}
	var exclude := {}
	var ao = area_at(o)
	var at_ = area_at(t)
	if not ao.is_empty():
		exclude[ao.get("id")] = true
	if not at_.is_empty():
		exclude[at_.get("id")] = true
	var ground = float(observer.get("elevation_inches", 0.0)) < 3.0 \
			and float(target.get("elevation_inches", 0.0)) < 3.0
	var clear := 0
	var pts = _sight_points(target)
	for p in pts:
		if not _line_blocked_11e(o, p, exclude, ground):
			clear += 1
	return {"clear": clear, "total": pts.size()}

func model_visible_11e(observer: Dictionary, target: Dictionary) -> bool:
	if GameConstants.edition < 11:
		return true
	var v = _visibility_lines_11e(observer, target)
	return v.total > 0 and v.clear > 0

func model_fully_visible_11e(observer: Dictionary, target: Dictionary) -> bool:
	if GameConstants.edition < 11:
		return true
	var v = _visibility_lines_11e(observer, target)
	return v.total > 0 and v.clear == v.total

## 06.01 UNIT FULLY VISIBLE: every alive model fully visible (the
## observer sees through the target unit's own models — inherent here,
## since only terrain blocks these lines).
func unit_fully_visible_11e(observer: Dictionary, unit: Dictionary) -> bool:
	if GameConstants.edition < 11:
		return true
	var any := false
	for m in unit.get("models", []):
		if not m.get("alive", true):
			continue
		any = true
		if not model_fully_visible_11e(observer, m):
			return false
	return any


## ISS-054 — 13.06 TERRAIN AND MOVEMENT (+24.35 SUPER-HEAVY WALKER),
## 2D approximation. Horizontal traversal along from→to:
##   ▪ exposed/light: every model passes.
##   ▪ dense: INFANTRY/BEASTS/SWARM/MOBILE pass; other models pass only
##     when every crossed dense feature is ≤2" high (≤4" with
##     SUPER-HEAVY WALKER) — taller sections demand vertical movement,
##     which the 2D board does not path (callers refuse the segment).
## MOBILE may be granted per-move (e.g. 24.35's gamble) via the
## extra_keywords argument.
##
## Stompa-on-walls fix (two refinements):
##   ▪ piece_class "area" footprints never block — they are enterable
##     regions whose walls are their own "feature" pieces. Legacy layouts
##     author no piece_class, so their whole-ruin rectangles keep blocking.
##   ▪ pass the moving model via `model` to make the test shape-aware: the
##     model's BASE is swept along the segment instead of testing only the
##     centre line, so a wide base cannot straddle a wall its centre line
##     never crosses. Pieces the base already overlaps at from_pos are
##     exempt for that segment, so a model stranded inside a wall by a
##     pre-fix save can always move OUT.
func can_move_through_11e(model_keywords: Array, from_pos: Vector2, to_pos: Vector2, extra_keywords: Array = [], model: Dictionary = {}) -> Dictionary:
	if GameConstants.edition < 11:
		return {"allowed": true, "blockers": []}
	var kws := _upper_keywords(model_keywords, extra_keywords)
	if _passes_dense_11e(kws):
		return {"allowed": true, "blockers": []}
	var height_limit := _dense_height_limit_11e(kws)
	var blockers: Array = []
	for piece in terrain_features:
		if not _is_solid_blocker_11e(piece, height_limit):
			continue
		var hit: bool
		if model.is_empty():
			hit = check_line_intersects_terrain(from_pos, to_pos, piece)
		else:
			hit = _swept_base_hits_piece(model, from_pos, to_pos, piece)
		if hit:
			blockers.append(str(piece.get("id", piece.get("type", "terrain"))))
	return {"allowed": blockers.is_empty(), "blockers": blockers}

## Endpoint companion to 13.06 (Stompa-on-walls fix): a model whose
## keywords do not let it traverse dense terrain may not END a move,
## deployment, disembark or pile-in with its base overlapping a solid
## dense feature taller than its step-over limit — a Stompa cannot stand
## in a ruin wall. Returns the blocking piece id, or "" when the position
## is legal. Inert below edition 11, like can_move_through_11e.
func solid_terrain_endpoint_blocker_11e(model: Dictionary, model_keywords: Array, extra_keywords: Array = []) -> String:
	if GameConstants.edition < 11:
		return ""
	var kws := _upper_keywords(model_keywords, extra_keywords)
	if _passes_dense_11e(kws):
		return ""
	var height_limit := _dense_height_limit_11e(kws)
	for piece in terrain_features:
		if not _is_solid_blocker_11e(piece, height_limit):
			continue
		if Measurement.model_overlaps_polygon(model, piece.get("polygon", PackedVector2Array())):
			return str(piece.get("id", piece.get("type", "terrain")))
	return ""

func _upper_keywords(model_keywords: Array, extra_keywords: Array) -> Array:
	var kws: Array = []
	for k in model_keywords:
		kws.append(str(k).to_upper())
	for k in extra_keywords:
		kws.append(str(k).to_upper())
	return kws

## 13.06: these keywords traverse dense terrain freely.
func _passes_dense_11e(upper_kws: Array) -> bool:
	for k in ["INFANTRY", "BEASTS", "SWARM", "MOBILE"]:
		if k in upper_kws:
			return true
	return false

## Step-over limit: dense sections at or below this height never block
## (2", or 4" with SUPER-HEAVY WALKER / abilities that grant its allowance).
func _dense_height_limit_11e(upper_kws: Array) -> float:
	return 4.0 if "SUPER-HEAVY WALKER" in upper_kws else 2.0

## A piece is a solid movement blocker when it is a dense FEATURE taller
## than the step-over limit. "area" footprints are enterable regions, not
## solid objects — their walls are separate feature pieces. Legacy layout
## pieces carry no piece_class and keep blocking on the whole footprint.
func _is_solid_blocker_11e(piece: Dictionary, height_limit: float) -> bool:
	if str(piece.get("piece_class", "")) == "area":
		return false
	if category_of(piece) != CATEGORY_DENSE:
		return false
	return height_inches_of(piece) > height_limit

## Shape-aware sweep: does the model's base, dragged from from_pos to
## to_pos, overlap the piece's footprint at any point? Samples the segment
## at quarter-base spacing (destination always included) and tests the full
## base shape at each sample. A piece the base already overlaps at from_pos
## never blocks — the escape clause that lets stranded models move out.
func _swept_base_hits_piece(model: Dictionary, from_pos: Vector2, to_pos: Vector2, piece: Dictionary) -> bool:
	var poly: PackedVector2Array = piece.get("polygon", PackedVector2Array())
	if poly.size() < 3:
		return false
	var test_model: Dictionary = model.duplicate()
	test_model["position"] = from_pos
	if Measurement.model_overlaps_polygon(test_model, poly):
		return false  # started overlapped — allow moving out
	# Cheap reject: swept-base bounding box vs polygon bounding box.
	var shape = Measurement.create_base_shape(model)
	var local_bounds: Rect2 = shape.get_bounds()
	var margin := maxf(local_bounds.size.x, local_bounds.size.y) * 0.5
	var poly_min := poly[0]
	var poly_max := poly[0]
	for v in poly:
		poly_min = poly_min.min(v)
		poly_max = poly_max.max(v)
	var sweep_min := from_pos.min(to_pos) - Vector2(margin, margin)
	var sweep_max := from_pos.max(to_pos) + Vector2(margin, margin)
	if sweep_max.x < poly_min.x or sweep_min.x > poly_max.x \
			or sweep_max.y < poly_min.y or sweep_min.y > poly_max.y:
		return false
	# Sample the sweep densely enough that a wall stroke cannot slip
	# between consecutive base placements (walls are ≥0.5" thick; the
	# sampled discs overlap heavily at quarter-base spacing).
	var step_px := maxf(minf(local_bounds.size.x, local_bounds.size.y) * 0.25, 8.0)
	var samples := maxi(1, int(ceil(from_pos.distance_to(to_pos) / step_px)))
	for i in range(1, samples + 1):
		test_model["position"] = from_pos.lerp(to_pos, float(i) / float(samples))
		if Measurement.model_overlaps_polygon(test_model, poly):
			return true
	return false


## ISS-053 (step 1) — 13.08 BENEFIT OF COVER qualification (the in-area
## half; the not-fully-visible half arrives with ISS-052's fully-visible
## module). A unit has the benefit of cover against a ranged attack when
## EVERY model meets a qualifying condition:
##   ▪ INFANTRY/BEASTS/SWARM model within a terrain area, or
##   ▪ (ISS-052, pending) not fully visible to the attacker.
## In 11e the effect is WORSENING the attack's BS by 1 (not a save mod) —
## applied by the resolution flow; this primitive answers qualification.
## Stealth (24.33) grants the benefit unconditionally.
func unit_has_cover_11e(unit: Dictionary, attacker_model: Dictionary = {}) -> bool:
	if GameConstants.edition < 11:
		return false
	if UnitAbilities.unit_has(unit, "stealth"):
		return true
	var keywords: Array = unit.get("meta", {}).get("keywords", [])
	var qualifies_kw := false
	for kw in ["INFANTRY", "BEASTS", "SWARM"]:
		if kw in keywords:
			qualifies_kw = true
			break
	var any_model := false
	for m in unit.get("models", []):
		if not m.get("alive", true):
			continue
		any_model = true
		var pos = m.get("position", null)
		if pos == null:
			return false
		var p := Vector2(float(pos.x) if pos is Dictionary else pos.x, float(pos.y) if pos is Dictionary else pos.y)
		# 13.08: EVERY model meets one or more conditions —
		#   ▪ INFANTRY/BEASTS/SWARM within a terrain area, or
		#   ▪ not fully visible to the attacker due to intervening
		#     terrain (ISS-052 module; terrain is the only blocker it
		#     models, so the "due to terrain" clause is inherent).
		var in_area_ok = qualifies_kw and not area_at(p).is_empty()
		var nfv_ok = not attacker_model.is_empty() \
				and not model_fully_visible_11e(attacker_model, m)
		if not (in_area_ok or nfv_ok):
			return false
	return any_model


## ISS-053 (step 1) — 22.05 PLUNGING FIRE qualification: the attack's BS
## IMPROVES by 1 when the target unit has one or more models on ground
## level and either:
##   ▪ the attacking model is on a terrain section >= 3" in height
##     (model "elevation_inches" field), or
##   ▪ the attacker has TOWERING and the target is within 12".
func plunging_fire_applies(attacker_model: Dictionary, attacker_unit: Dictionary, target_unit: Dictionary) -> bool:
	if GameConstants.edition < 11:
		return false
	var target_on_ground := false
	for m in target_unit.get("models", []):
		if m.get("alive", true) and float(m.get("elevation_inches", 0.0)) <= 0.0:
			target_on_ground = true
			break
	if not target_on_ground:
		return false
	if float(attacker_model.get("elevation_inches", 0.0)) >= 3.0:
		return true
	if "TOWERING" in attacker_unit.get("meta", {}).get("keywords", []):
		var det_px = Measurement.inches_to_px(12.0)
		for m in target_unit.get("models", []):
			if m.get("alive", true) and Measurement.model_to_model_distance_px(attacker_model, m) <= det_px:
				return true
	return false
