extends Node2D

var board_width: float = 1760.0  # 44 inches
var board_height: float = 2400.0 # 60 inches

func _ready() -> void:
	z_index = -10
	board_width = SettingsService.get_board_width_px()
	board_height = SettingsService.get_board_height_px()

func _draw() -> void:
	var board_rect = Rect2(Vector2.ZERO, Vector2(board_width, board_height))
	
	draw_rect(board_rect, Color(0.15, 0.12, 0.08, 1.0))
	
	draw_rect(board_rect, Color(0.3, 0.25, 0.2, 1.0), false, 3.0)
	
	var grid_color = Color(0.25, 0.2, 0.15, 0.3)
	var grid_spacing = Measurement.inches_to_px(6.0)
	
	var x = grid_spacing
	while x < board_width:
		draw_line(Vector2(x, 0), Vector2(x, board_height), grid_color, 1.0)
		x += grid_spacing
	
	var y = grid_spacing
	while y < board_height:
		draw_line(Vector2(0, y), Vector2(board_width, y), grid_color, 1.0)
		y += grid_spacing