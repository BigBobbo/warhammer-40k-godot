extends Node2D

# TerrainVisual - Renders terrain features on the battlefield
# Uses Polygon2D for area representation with borders
# Supports distinct visual styles per terrain type (ruins, woods, crater, etc.)

var terrain_pieces: Array = []
var terrain_containers: Dictionary = {}  # terrain_id -> Node2D container
var _ruins_polygons: Array = []  # Track ruins Polygon2D nodes for style changes

# Border width
const BORDER_WIDTH = 3.0

# Preloaded ruins shaders
var _ruins_shaders: Dictionary = {
	"concrete": preload("res://shaders/ruins_concrete.gdshader"),
	"marble": preload("res://shaders/ruins_marble.gdshader"),
	"brick": preload("res://shaders/ruins_brick.gdshader"),
	"weathered_stone": preload("res://shaders/ruins_weathered_stone.gdshader"),
}

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

	# Connect to ruins style changes from settings
	if SettingsService:
		SettingsService.ruins_style_changed.connect(_on_ruins_style_changed)
		if SettingsService.has_signal("terrain_debug_labels_changed"):
			SettingsService.terrain_debug_labels_changed.connect(_on_terrain_debug_labels_changed)

	print("[TerrainVisual] Initialized")

## Re-render all terrain when the debug-labels setting flips, so the label
## style switches live without reloading the board.
func _on_terrain_debug_labels_changed(_enabled: bool) -> void:
	if TerrainManager and TerrainManager.terrain_features.size() > 0:
		_on_terrain_loaded(TerrainManager.terrain_features)

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

## Whether the verbose internal id labels + LoS badges should render.
func _debug_labels_enabled() -> bool:
	return SettingsService != null and SettingsService.terrain_debug_labels

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

	# Apply ruins shader if this is a ruins terrain piece
	if terrain_type == "ruins":
		_apply_ruins_shader(piece)
		_ruins_polygons.append(piece)

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

	# Terrain id label is debug-only. The verbose "Ruins corner-short-11 (T)"
	# text on every piece of scenery reads as developer clutter, and the
	# TerrainCoverOverlay shield (LB/+2/+1) already gives players the
	# gameplay-relevant height/cover info at each piece's centroid.
	var debug_labels = _debug_labels_enabled()
	var blocks_los = terrain_data.get("blocks_los", false)
	var label_panel: PanelContainer = null
	if debug_labels:
		label_panel = PanelContainer.new()
		var label_style = StyleBoxFlat.new()
		label_style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
		label_style.set_corner_radius_all(3)
		label_style.content_margin_left = 4
		label_style.content_margin_right = 4
		label_style.content_margin_top = 1
		label_style.content_margin_bottom = 1
		label_panel.add_theme_stylebox_override("panel", label_style)
		label_panel.position = terrain_data.get("position", Vector2.ZERO) - Vector2(30, 10)

		var label = Label.new()
		label.text = _get_label_text(terrain_data)
		label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
		label.add_theme_font_size_override("font_size", 11)
		label_panel.add_child(label)

	# Assemble the terrain piece
	container.add_child(piece)
	container.add_child(border)
	if label_panel != null:
		container.add_child(label_panel)

	# Add type-specific decorative details
	_add_terrain_decorations(container, terrain_data)

	# Add LoS-blocker badge only with debug labels on — the compact height chip
	# already encodes blocks_los via its gold tint.
	if blocks_los and debug_labels:
		_add_los_blocker_indicator(container, terrain_data)

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

			line.z_index = 2  # Above terrain fill (0) but stays within parent sort group
			line.visible = true

			# Add directly to TerrainVisual (self), not container
			add_child(line)

			print("[TerrainVisual] Added wall line from ", wall.get("start"), " to ", wall.get("end"), " type: ", wall.get("type", "solid"))

	add_child(container)

	# Store reference
	terrain_containers[terrain_data.get("id", "")] = container
	terrain_pieces.append(container)

	print("[TerrainVisual] Added terrain piece '%s' type=%s height=%s" % [terrain_data.get("id", ""), terrain_type, height_cat])

## Add a "LoS" badge to terrain pieces that block line-of-sight
## Visible icon helps players read which terrain blocks visibility at a glance
func _add_los_blocker_indicator(container: Node2D, terrain_data: Dictionary) -> void:
	var position = terrain_data.get("position", Vector2.ZERO)
	var size = terrain_data.get("size", Vector2(100, 100))

	# Place badge at top-right corner of terrain piece bounding box
	var badge_offset = Vector2(size.x * 0.35, -size.y * 0.35)
	var badge_pos = position + badge_offset
	var badge_radius = 14.0

	# Dark shaded circle background
	var bg = Polygon2D.new()
	var circle_pts = PackedVector2Array()
	for i in range(20):
		var angle = i * TAU / 20.0
		circle_pts.append(badge_pos + Vector2(cos(angle), sin(angle)) * badge_radius)
	bg.polygon = circle_pts
	bg.color = Color(0.1, 0.1, 0.12, 0.85)
	bg.z_index = 3
	container.add_child(bg)

	# Bright outline ring
	var ring = Line2D.new()
	for i in range(21):
		var angle = i * TAU / 20.0
		ring.add_point(badge_pos + Vector2(cos(angle), sin(angle)) * badge_radius)
	ring.default_color = Color(1.0, 0.85, 0.2, 0.95)  # Yellow-gold for visibility
	ring.width = 1.8
	ring.joint_mode = Line2D.LINE_JOINT_ROUND
	ring.z_index = 3
	container.add_child(ring)

	# "LoS" text label
	var label = Label.new()
	label.text = "LoS"
	label.position = badge_pos - Vector2(11, 9)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6, 1.0))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.z_index = 4
	container.add_child(label)

## Add decorative visual elements based on terrain type
func _add_terrain_decorations(container: Node2D, terrain_data: Dictionary) -> void:
	var terrain_type = terrain_data.get("type", "ruins")
	var position = terrain_data.get("position", Vector2.ZERO)
	var size = terrain_data.get("size", Vector2(100, 100))
	var polygon_points = terrain_data.get("polygon", PackedVector2Array())
	var terrain_id = str(terrain_data.get("id", "terrain"))

	match terrain_type:
		"ruins":
			_add_ruins_decorations(container, terrain_id, position, size, polygon_points)
		"woods", "forest":
			_add_woods_decorations(container, terrain_id, position, size, polygon_points)
		"crater":
			_add_crater_decorations(container, position, size)
		"hill":
			_add_hill_decorations(container, position, size)
		"barricade":
			_add_barricade_decorations(container, position, size, polygon_points)
		"impassable":
			_add_impassable_decorations(container, position, size, polygon_points)

# Scatter-prop sprite pools (Kenney CC0, see assets/tilepack/CREDITS.md).
const _RUINS_PROPS := [
	"res://assets/tilepack/crateWood.png",
	"res://assets/tilepack/crateMetal.png",
	"res://assets/tilepack/barrelBlack_top.png",
	"res://assets/tilepack/sandbagBrown.png",
	"res://assets/tilepack/sandbagBeige.png",
]
const _TREE_PROPS := [
	"res://assets/tilepack/treeGreen_small.png",
	"res://assets/tilepack/treeGreen_large.png",
	"res://assets/tilepack/treeBrown_small.png",
]

## Deterministically scatter prop sprites inside a terrain footprint. Seeded by
## the terrain id so the same layout renders the same props every load.
func _scatter_props(container: Node2D, terrain_id: String, position: Vector2, size: Vector2, polygon_points: PackedVector2Array, pool: Array, count: int, prop_alpha: float = 0.95) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(terrain_id)
	var half = size * 0.5
	var placed = 0
	var attempts = 0
	while placed < count and attempts < count * 8:
		attempts += 1
		var p = position + Vector2(rng.randf_range(-half.x * 0.8, half.x * 0.8), rng.randf_range(-half.y * 0.8, half.y * 0.8))
		if polygon_points.size() >= 3 and not Geometry2D.is_point_in_polygon(p, polygon_points):
			continue
		var sprite = Sprite2D.new()
		sprite.texture = load(pool[rng.randi() % pool.size()])
		sprite.position = p
		sprite.rotation = rng.randf_range(0.0, TAU)
		# Native sprite size is crate-the-size-of-a-tank at board scale; shrink
		# to genuine scatter-prop proportions with a little variance.
		sprite.scale = Vector2.ONE * rng.randf_range(0.5, 0.68)
		sprite.modulate = Color(1, 1, 1, prop_alpha)
		sprite.z_index = 1  # Above terrain fill, below walls (2)
		container.add_child(sprite)
		placed += 1

## Ruins: crates, barrels and sandbags strewn inside the footprint
func _add_ruins_decorations(container: Node2D, terrain_id: String, position: Vector2, size: Vector2, polygon_points: PackedVector2Array) -> void:
	# Scale prop count with footprint area (a 4x6" ruin gets ~4, big ones ~8)
	var area_sq_inches = (size.x / 40.0) * (size.y / 40.0)
	var count = clampi(int(area_sq_inches / 6.0), 3, 8)
	_scatter_props(container, terrain_id, position, size, polygon_points, _RUINS_PROPS, count)

## Woods/Forest: top-down tree sprites
func _add_woods_decorations(container: Node2D, terrain_id: String, position: Vector2, size: Vector2, polygon_points: PackedVector2Array) -> void:
	var area_sq_inches = (size.x / 40.0) * (size.y / 40.0)
	var count = clampi(int(area_sq_inches / 4.0), 4, 10)
	_scatter_props(container, terrain_id, position, size, polygon_points, _TREE_PROPS, count)

## Crater: oil-spill scorch mark + concentric rings suggesting a blast depression
func _add_crater_decorations(container: Node2D, position: Vector2, size: Vector2) -> void:
	var scorch = Sprite2D.new()
	scorch.texture = load("res://assets/tilepack/oilSpill_large.png")
	scorch.position = position
	var target = min(size.x, size.y) * 0.55
	var tex_size = float(max(scorch.texture.get_width(), scorch.texture.get_height()))
	scorch.scale = Vector2.ONE * (target / tex_size)
	scorch.modulate = Color(1, 1, 1, 0.55)
	scorch.z_index = 1
	container.add_child(scorch)

	var ring_color = Color(0.22, 0.2, 0.18, 0.3)
	var radius_outer = min(size.x, size.y) * 0.3

	var ring = Line2D.new()
	for i in range(17):  # 16 segments + close
		var angle = i * TAU / 16
		ring.add_point(position + Vector2(cos(angle), sin(angle)) * radius_outer)
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

## Barricade: metal barricade sprites tiled along the longer axis
func _add_barricade_decorations(container: Node2D, position: Vector2, size: Vector2, polygon_points: PackedVector2Array) -> void:
	var tex: Texture2D = load("res://assets/tilepack/barricadeMetal.png")
	var seg_w = float(tex.get_width())
	var horizontal = size.x >= size.y
	var run = (size.x if horizontal else size.y) * 0.9
	var count = maxi(1, int(run / (seg_w + 4.0)))
	var start = -(count - 1) * (seg_w + 4.0) * 0.5
	for i in range(count):
		var sprite = Sprite2D.new()
		sprite.texture = tex
		var offset = start + i * (seg_w + 4.0)
		sprite.position = position + (Vector2(offset, 0) if horizontal else Vector2(0, offset))
		if not horizontal:
			sprite.rotation = PI / 2.0
		sprite.z_index = 1
		container.add_child(sprite)

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
	_ruins_polygons.clear()

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

## Apply the current ruins shader to a Polygon2D
func _apply_ruins_shader(polygon: Polygon2D) -> void:
	var style = SettingsService.ruins_style if SettingsService else "concrete"
	if style in _ruins_shaders:
		var mat = ShaderMaterial.new()
		mat.shader = _ruins_shaders[style]
		polygon.material = mat
		print("[TerrainVisual] Applied ruins shader: %s" % style)
	else:
		polygon.material = null

## Handle ruins style change from settings — update all existing ruins polygons
func _on_ruins_style_changed(new_style: String) -> void:
	print("[TerrainVisual] Ruins style changed to: %s" % new_style)
	for polygon in _ruins_polygons:
		if is_instance_valid(polygon):
			if new_style in _ruins_shaders:
				var mat = ShaderMaterial.new()
				mat.shader = _ruins_shaders[new_style]
				polygon.material = mat
			else:
				polygon.material = null

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
