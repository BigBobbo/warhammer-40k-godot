extends Node2D

# TerrainVisual - Renders terrain features on the battlefield
# Uses Polygon2D for area representation with borders
# Supports distinct visual styles per terrain type (ruins, woods, crater, etc.)

var terrain_pieces: Array = []
var terrain_containers: Dictionary = {}  # terrain_id -> Node2D container

# Border width
const BORDER_WIDTH = 2.5

# Terrain type color palettes: { fill: Color, border: Color, label_prefix: String }
# Each type has low/medium/tall variants via alpha modulation
const TERRAIN_STYLES = {
	"ruins": {
		"fill": Color(0.45, 0.38, 0.32, 1.0),       # Warm stone/concrete gray-brown
		"border": Color(0.3, 0.25, 0.2, 0.9),        # Dark stone border
		"label_prefix": "Ruins",
	},
	"woods": {
		"fill": Color(0.18, 0.42, 0.15, 1.0),        # Forest green
		"border": Color(0.12, 0.3, 0.1, 0.9),        # Dark green border
		"label_prefix": "Woods",
	},
	"forest": {
		"fill": Color(0.18, 0.42, 0.15, 1.0),        # Same as woods
		"border": Color(0.12, 0.3, 0.1, 0.9),
		"label_prefix": "Forest",
	},
	"crater": {
		"fill": Color(0.28, 0.25, 0.22, 1.0),        # Scorched dark earth
		"border": Color(0.2, 0.18, 0.15, 0.9),       # Charred border
		"label_prefix": "Crater",
	},
	"hill": {
		"fill": Color(0.52, 0.45, 0.3, 1.0),         # Sandy tan/earth
		"border": Color(0.4, 0.35, 0.22, 0.9),       # Earthy border
		"label_prefix": "Hill",
	},
	"obstacle": {
		"fill": Color(0.35, 0.35, 0.38, 1.0),        # Industrial dark gray
		"border": Color(0.25, 0.25, 0.28, 0.9),      # Steel-dark border
		"label_prefix": "Obstacle",
	},
	"barricade": {
		"fill": Color(0.4, 0.42, 0.45, 1.0),         # Metallic gray-blue
		"border": Color(0.3, 0.32, 0.38, 0.9),       # Metal border
		"label_prefix": "Barricade",
	},
	"impassable": {
		"fill": Color(0.4, 0.2, 0.18, 1.0),          # Dark red-brown (danger)
		"border": Color(0.5, 0.15, 0.12, 0.9),       # Red-tinted border
		"label_prefix": "Impassable",
	},
	"area_terrain": {
		"fill": Color(0.3, 0.38, 0.28, 1.0),         # Olive green (generic)
		"border": Color(0.2, 0.28, 0.18, 0.9),       # Dark olive border
		"label_prefix": "Area",
	},
}

# Default style for unknown terrain types
const DEFAULT_STYLE = {
	"fill": Color(0.3, 0.35, 0.25, 1.0),
	"border": Color(0.15, 0.15, 0.1, 0.9),
	"label_prefix": "Terrain",
}

# Alpha multipliers by height category — taller terrain renders more opaque
const HEIGHT_ALPHA = {
	"low": 0.4,
	"medium": 0.55,
	"tall": 0.7,
}

func _ready() -> void:
	z_index = -8  # Above board (-10), below deployment zones (-5)
	name = "TerrainVisual"

	# Connect to TerrainManager signals
	if TerrainManager:
		TerrainManager.terrain_loaded.connect(_on_terrain_loaded)
		TerrainManager.terrain_visibility_changed.connect(_on_visibility_changed)

		# Load existing terrain if any
		if TerrainManager.terrain_features.size() > 0:
			_on_terrain_loaded(TerrainManager.terrain_features)

	print("[TerrainVisual] Initialized")

func _on_terrain_loaded(terrain_features: Array) -> void:
	# Clear existing terrain visuals
	_clear_terrain_visuals()

	# Create visuals for each terrain piece
	for terrain_data in terrain_features:
		_add_terrain_piece(terrain_data)

	print("[TerrainVisual] Rendered ", terrain_features.size(), " terrain pieces")

## Get the visual style for a terrain type, falling back to DEFAULT_STYLE
func _get_terrain_style(terrain_type: String) -> Dictionary:
	if TERRAIN_STYLES.has(terrain_type):
		return TERRAIN_STYLES[terrain_type]
	return DEFAULT_STYLE

## Build the fill color for a terrain piece based on type and height
func _get_fill_color(terrain_type: String, height_cat: String) -> Color:
	var style = _get_terrain_style(terrain_type)
	var base_color: Color = style.fill
	var alpha = HEIGHT_ALPHA.get(height_cat, 0.7)
	return Color(base_color.r, base_color.g, base_color.b, alpha)

## Build the border color for a terrain piece based on type
func _get_border_color(terrain_type: String) -> Color:
	var style = _get_terrain_style(terrain_type)
	return style.border

## Build the label text for a terrain piece
func _get_label_text(terrain_data: Dictionary) -> String:
	var terrain_type = terrain_data.get("type", "ruins")
	var terrain_id = terrain_data.get("id", "")
	var height_cat = terrain_data.get("height_category", "tall")
	var style = _get_terrain_style(terrain_type)

	# Extract the numeric suffix from the ID (e.g., "ruins_3" -> "3")
	var id_suffix = terrain_id
	var underscore_pos = terrain_id.rfind("_")
	if underscore_pos >= 0:
		id_suffix = terrain_id.substr(underscore_pos + 1)

	var height_label = height_cat.substr(0, 1).to_upper()
	return "%s %s (%s)" % [style.label_prefix, id_suffix, height_label]

func _add_terrain_piece(terrain_data: Dictionary) -> void:
	var container = Node2D.new()
	container.name = terrain_data.get("id", "terrain")

	var terrain_type = terrain_data.get("type", "ruins")
	var height_cat = terrain_data.get("height_category", "tall")
	var polygon_points = terrain_data.get("polygon", PackedVector2Array())

	# Create the polygon fill with type-specific color
	var piece = Polygon2D.new()
	piece.polygon = polygon_points
	piece.color = _get_fill_color(terrain_type, height_cat)

	# Create the border with type-specific color
	var border = Line2D.new()
	for point in polygon_points:
		border.add_point(point)
	# Close the polygon by adding the first point at the end
	if polygon_points.size() > 0:
		border.add_point(polygon_points[0])

	border.width = BORDER_WIDTH
	border.default_color = _get_border_color(terrain_type)
	border.joint_mode = Line2D.LINE_JOINT_ROUND

	# Add terrain label with type-specific prefix
	var label = Label.new()
	label.text = _get_label_text(terrain_data)
	label.position = terrain_data.get("position", Vector2.ZERO) - Vector2(30, 10)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)

	# Assemble the terrain piece
	container.add_child(piece)
	container.add_child(border)
	container.add_child(label)

	# Add type-specific decorative details
	_add_terrain_decorations(container, terrain_data)

	# Add walls if present - tactical map colors
	var walls = terrain_data.get("walls", [])
	if walls.size() > 0:
		# Add walls directly to the TerrainVisual, not the container
		for wall in walls:
			var line = Line2D.new()
			line.add_point(wall.get("start", Vector2.ZERO))
			line.add_point(wall.get("end", Vector2.ZERO))
			# Set wall thickness and tactical-map colors
			match wall.get("type", "solid"):
				"solid":
					line.default_color = Color(0.25, 0.25, 0.22, 1.0)  # Dark gray-brown
					line.width = 6.0
				"window":
					line.default_color = Color(0.4, 0.5, 0.6, 0.8)  # Blue-gray
					line.width = 4.0
				"door":
					line.default_color = Color(0.45, 0.35, 0.2, 0.9)  # Warm brown
					line.width = 5.0

			line.z_index = 10  # High z-index
			line.z_as_relative = false
			line.visible = true

			# Add directly to TerrainVisual (self), not container
			add_child(line)

			print("[TerrainVisual] Added wall line from ", wall.get("start"), " to ", wall.get("end"), " type: ", wall.get("type", "solid"))

	add_child(container)

	# Store reference
	terrain_containers[terrain_data.get("id", "")] = container
	terrain_pieces.append(container)

	print("[TerrainVisual] Added terrain piece '%s' type=%s height=%s" % [terrain_data.get("id", ""), terrain_type, height_cat])

## Add decorative visual elements based on terrain type
func _add_terrain_decorations(container: Node2D, terrain_data: Dictionary) -> void:
	var terrain_type = terrain_data.get("type", "ruins")
	var position = terrain_data.get("position", Vector2.ZERO)
	var size = terrain_data.get("size", Vector2(100, 100))
	var polygon_points = terrain_data.get("polygon", PackedVector2Array())

	match terrain_type:
		"ruins":
			_add_ruins_decorations(container, position, size, polygon_points)
		"woods", "forest":
			_add_woods_decorations(container, position, size)
		"crater":
			_add_crater_decorations(container, position, size)
		"hill":
			_add_hill_decorations(container, position, size)
		"barricade":
			_add_barricade_decorations(container, position, size, polygon_points)
		"impassable":
			_add_impassable_decorations(container, position, size, polygon_points)

## Ruins: small interior line segments suggesting broken walls/rubble
func _add_ruins_decorations(container: Node2D, position: Vector2, size: Vector2, polygon_points: PackedVector2Array) -> void:
	var half = size * 0.3
	var rubble_color = Color(0.5, 0.42, 0.35, 0.35)

	# Add a few small interior line segments to suggest rubble
	var offsets = [
		[Vector2(-half.x * 0.5, -half.y * 0.3), Vector2(-half.x * 0.1, -half.y * 0.6)],
		[Vector2(half.x * 0.2, half.y * 0.1), Vector2(half.x * 0.6, half.y * 0.3)],
		[Vector2(-half.x * 0.3, half.y * 0.4), Vector2(half.x * 0.1, half.y * 0.2)],
	]

	for offset_pair in offsets:
		var line = Line2D.new()
		line.add_point(position + offset_pair[0])
		line.add_point(position + offset_pair[1])
		line.default_color = rubble_color
		line.width = 2.0
		container.add_child(line)

## Woods/Forest: small circles suggesting tree canopy viewed from above
func _add_woods_decorations(container: Node2D, position: Vector2, size: Vector2) -> void:
	var tree_color = Color(0.15, 0.35, 0.12, 0.3)
	var half = size * 0.3

	# Place a few "tree" circles (approximated with small polygons)
	var tree_positions = [
		position + Vector2(-half.x * 0.4, -half.y * 0.3),
		position + Vector2(half.x * 0.3, -half.y * 0.1),
		position + Vector2(-half.x * 0.1, half.y * 0.4),
		position + Vector2(half.x * 0.5, half.y * 0.3),
	]

	for tree_pos in tree_positions:
		var tree = Polygon2D.new()
		var radius = min(size.x, size.y) * 0.08
		var circle_points = PackedVector2Array()
		for i in range(8):
			var angle = i * TAU / 8
			circle_points.append(tree_pos + Vector2(cos(angle), sin(angle)) * radius)
		tree.polygon = circle_points
		tree.color = tree_color
		container.add_child(tree)

## Crater: concentric rings suggesting a blast depression
func _add_crater_decorations(container: Node2D, position: Vector2, size: Vector2) -> void:
	var ring_color = Color(0.22, 0.2, 0.18, 0.3)
	var radius_outer = min(size.x, size.y) * 0.3
	var radius_inner = radius_outer * 0.5

	for radius in [radius_outer, radius_inner]:
		var ring = Line2D.new()
		for i in range(17):  # 16 segments + close
			var angle = i * TAU / 16
			ring.add_point(position + Vector2(cos(angle), sin(angle)) * radius)
		ring.default_color = ring_color
		ring.width = 1.5
		ring.joint_mode = Line2D.LINE_JOINT_ROUND
		container.add_child(ring)

## Hill: contour lines suggesting elevation
func _add_hill_decorations(container: Node2D, position: Vector2, size: Vector2) -> void:
	var contour_color = Color(0.45, 0.4, 0.28, 0.3)
	var half = size * 0.25

	# Draw two contour ellipses at different scales
	for scale_factor in [0.8, 0.5]:
		var contour = Line2D.new()
		for i in range(17):
			var angle = i * TAU / 16
			contour.add_point(position + Vector2(cos(angle) * half.x * scale_factor, sin(angle) * half.y * scale_factor))
		contour.default_color = contour_color
		contour.width = 1.5
		contour.joint_mode = Line2D.LINE_JOINT_ROUND
		container.add_child(contour)

## Barricade: dashed center line suggesting a linear barrier
func _add_barricade_decorations(container: Node2D, position: Vector2, size: Vector2, polygon_points: PackedVector2Array) -> void:
	var dash_color = Color(0.5, 0.5, 0.55, 0.4)

	# Draw dashed line through the center along the longer axis
	var half = size * 0.35
	if size.x >= size.y:
		# Horizontal dashes
		var y_center = position.y
		var dash_len = size.x * 0.08
		var gap = dash_len * 0.6
		var x_start = position.x - half.x
		var x_end = position.x + half.x
		var x = x_start
		while x < x_end:
			var dash = Line2D.new()
			dash.add_point(Vector2(x, y_center))
			dash.add_point(Vector2(min(x + dash_len, x_end), y_center))
			dash.default_color = dash_color
			dash.width = 3.0
			container.add_child(dash)
			x += dash_len + gap
	else:
		# Vertical dashes
		var x_center = position.x
		var dash_len = size.y * 0.08
		var gap = dash_len * 0.6
		var y_start = position.y - half.y
		var y_end = position.y + half.y
		var y = y_start
		while y < y_end:
			var dash = Line2D.new()
			dash.add_point(Vector2(x_center, y))
			dash.add_point(Vector2(x_center, min(y + dash_len, y_end)))
			dash.default_color = dash_color
			dash.width = 3.0
			container.add_child(dash)
			y += dash_len + gap

## Impassable: X-pattern warning marks
func _add_impassable_decorations(container: Node2D, position: Vector2, size: Vector2, polygon_points: PackedVector2Array) -> void:
	var warn_color = Color(0.6, 0.2, 0.15, 0.3)
	var half = size * 0.25

	# Draw an X through the center
	var line1 = Line2D.new()
	line1.add_point(position + Vector2(-half.x, -half.y))
	line1.add_point(position + Vector2(half.x, half.y))
	line1.default_color = warn_color
	line1.width = 2.0
	container.add_child(line1)

	var line2 = Line2D.new()
	line2.add_point(position + Vector2(half.x, -half.y))
	line2.add_point(position + Vector2(-half.x, half.y))
	line2.default_color = warn_color
	line2.width = 2.0
	container.add_child(line2)

func _clear_terrain_visuals() -> void:
	for container in terrain_pieces:
		if is_instance_valid(container):
			container.queue_free()

	# Also clean up wall Line2D nodes added directly to self (not in containers)
	for child in get_children():
		if child is Line2D and is_instance_valid(child):
			child.queue_free()

	terrain_pieces.clear()
	terrain_containers.clear()

func _on_visibility_changed(visible: bool) -> void:
	self.visible = visible

func highlight_terrain(terrain_id: String, highlight: bool, color: Color = Color.YELLOW) -> void:
	if terrain_id in terrain_containers:
		var container = terrain_containers[terrain_id]
		if is_instance_valid(container):
			var border = container.get_child(1) if container.get_child_count() > 1 else null
			if border and border is Line2D:
				if highlight:
					border.default_color = color
					border.width = BORDER_WIDTH * 1.5
				else:
					var terrain_type = _get_terrain_type_for_id(terrain_id)
					border.default_color = _get_border_color(terrain_type)
					border.width = BORDER_WIDTH

## Look up the terrain type for a terrain ID from stored terrain data
func _get_terrain_type_for_id(terrain_id: String) -> String:
	if TerrainManager:
		for terrain in TerrainManager.terrain_features:
			if terrain.get("id", "") == terrain_id:
				return terrain.get("type", "ruins")
	return "ruins"

func show_cover_indicator_at(position: Vector2, in_cover: bool) -> void:
	# Create a temporary indicator showing cover status
	var indicator = Label.new()
	indicator.text = "+COVER" if in_cover else ""
	indicator.position = position - Vector2(30, 40)
	indicator.add_theme_font_size_override("font_size", 14)
	indicator.add_theme_color_override("font_color", Color.GREEN if in_cover else Color.RED)
	indicator.add_theme_color_override("font_shadow_color", Color.BLACK)
	indicator.add_theme_constant_override("shadow_offset_x", 1)
	indicator.add_theme_constant_override("shadow_offset_y", 1)

	add_child(indicator)

	# Auto-remove after 2 seconds
	var timer = Timer.new()
	timer.wait_time = 2.0
	timer.one_shot = true
	timer.timeout.connect(func(): indicator.queue_free())
	add_child(timer)
	timer.start()
