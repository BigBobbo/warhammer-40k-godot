extends Node2D

var board_width: float = 1760.0  # 44 inches
var board_height: float = 2400.0 # 60 inches
var grass_background: ColorRect

func _ready() -> void:
	z_index = -10
	board_width = SettingsService.get_board_width_px()
	board_height = SettingsService.get_board_height_px()
	_setup_grass_background()

func _setup_grass_background() -> void:
	# Create a ColorRect with the grass shader for the board background
	grass_background = ColorRect.new()
	grass_background.size = Vector2(board_width, board_height)
	grass_background.color = Color(0.18, 0.38, 0.14, 1.0)
	grass_background.z_index = -1  # Behind grid lines but part of this node

	var shader = load("res://shaders/felt_texture.gdshader")
	var shader_material = ShaderMaterial.new()
	shader_material.shader = shader
	grass_background.material = shader_material

	add_child(grass_background)
	DebugLogger.info("BoardVisual", "Grass texture shader applied to board background")

func _draw() -> void:
	var board_rect = Rect2(Vector2.ZERO, Vector2(board_width, board_height))

	# Dark wood outer border
	draw_rect(board_rect, Color(0.35, 0.28, 0.15, 1.0), false, 4.0)

	# Inner gold accent border
	var inset_rect = Rect2(Vector2(4, 4), Vector2(board_width - 8, board_height - 8))
	draw_rect(inset_rect, Color(0.83, 0.59, 0.38, 0.6), false, 2.0)

	# Grid lines - muted green to complement felt
	var grid_color = Color(0.2, 0.45, 0.2, 0.2)
	var grid_spacing = Measurement.inches_to_px(6.0)

	var x = grid_spacing
	while x < board_width:
		draw_line(Vector2(x, 0), Vector2(x, board_height), grid_color, 1.0)
		x += grid_spacing

	var y = grid_spacing
	while y < board_height:
		draw_line(Vector2(0, y), Vector2(board_width, y), grid_color, 1.0)
		y += grid_spacing
