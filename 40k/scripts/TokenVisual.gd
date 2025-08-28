extends Node2D

var radius: float = 20.0
var owner_player: int = 1
var is_preview: bool = false
var model_number: int = 1
var debug_mode: bool = false

func _ready() -> void:
	z_index = 10

func _draw() -> void:
	var fill_color: Color
	var border_color: Color
	var border_width: float = 3.0
	
	if debug_mode:
		# Use distinct debug colors (bright yellow/orange)
		fill_color = Color(1.0, 0.8, 0.0, 0.9)  # Yellow
		border_color = Color(1.0, 0.5, 0.0, 1.0)  # Orange
		border_width = 4.0  # Thicker border in debug mode
		
		# Draw additional debug indicator ring
		draw_arc(Vector2.ZERO, radius + 4, 0, TAU, 32, Color(1.0, 1.0, 0.0, 0.5), 2.0)
	elif owner_player == 1:
		fill_color = Color(0.2, 0.2, 0.8, 0.8 if is_preview else 1.0)
		border_color = Color(0.1, 0.1, 0.6, 1.0)
	else:
		fill_color = Color(0.8, 0.2, 0.2, 0.8 if is_preview else 1.0)
		border_color = Color(0.6, 0.1, 0.1, 1.0)
	
	draw_circle(Vector2.ZERO, radius, fill_color)
	
	draw_arc(Vector2.ZERO, radius, 0, TAU, 64, border_color, border_width)
	
	var font = ThemeDB.fallback_font
	var text = str(model_number)
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
	var text_pos = Vector2(-text_size.x / 2, text_size.y / 4)
	
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color.WHITE)

func set_preview(preview: bool) -> void:
	is_preview = preview
	queue_redraw()

func set_debug_mode(active: bool) -> void:
	debug_mode = active
	queue_redraw()