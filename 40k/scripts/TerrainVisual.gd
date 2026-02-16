extends Node2D

# TerrainVisual - Renders terrain features on the battlefield
# Uses Polygon2D for area representation with borders

var terrain_pieces: Array = []
var terrain_containers: Dictionary = {}  # terrain_id -> Node2D container

# Visual settings - olive/green-brown palette for green felt board
const TERRAIN_COLOR_LOW = Color(0.25, 0.4, 0.22, 0.4)      # Light olive-green
const TERRAIN_COLOR_MEDIUM = Color(0.3, 0.35, 0.25, 0.5)    # Medium olive
const TERRAIN_COLOR_TALL = Color(0.35, 0.3, 0.2, 0.6)       # Dark olive-brown
const BORDER_COLOR = Color(0.15, 0.15, 0.1, 0.9)            # Dark border
const BORDER_WIDTH = 2.5

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

func _add_terrain_piece(terrain_data: Dictionary) -> void:
	var container = Node2D.new()
	container.name = terrain_data.get("id", "terrain")

	# Create the polygon fill
	var piece = Polygon2D.new()
	piece.polygon = terrain_data.get("polygon", PackedVector2Array())

	# Set color based on height category
	var height_cat = terrain_data.get("height_category", "tall")
	match height_cat:
		"low":
			piece.color = TERRAIN_COLOR_LOW
		"medium":
			piece.color = TERRAIN_COLOR_MEDIUM
		"tall":
			piece.color = TERRAIN_COLOR_TALL
		_:
			piece.color = TERRAIN_COLOR_TALL

	# Create the border
	var border = Line2D.new()
	var polygon_points = terrain_data.get("polygon", PackedVector2Array())

	# Convert PackedVector2Array to array for Line2D
	for point in polygon_points:
		border.add_point(point)

	# Close the polygon by adding the first point at the end
	if polygon_points.size() > 0:
		border.add_point(polygon_points[0])

	border.width = BORDER_WIDTH
	border.default_color = BORDER_COLOR
	border.joint_mode = Line2D.LINE_JOINT_ROUND

	# Add height indicator label
	var label = Label.new()
	label.text = terrain_data.get("id", "").replace("ruins_", "R") + " (" + height_cat.substr(0, 1).to_upper() + ")"
	label.position = terrain_data.get("position", Vector2.ZERO) - Vector2(20, 10)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)

	# Assemble the terrain piece
	container.add_child(piece)
	container.add_child(border)
	container.add_child(label)

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
					border.default_color = BORDER_COLOR
					border.width = BORDER_WIDTH

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
