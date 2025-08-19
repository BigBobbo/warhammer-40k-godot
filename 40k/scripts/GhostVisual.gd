extends Node2D

var radius: float = 20.0
var owner_player: int = 1
var is_valid_position: bool = true

func _ready() -> void:
	z_index = 20
	set_process(true)

func _draw() -> void:
	var fill_color: Color
	var border_color: Color
	
	if not is_valid_position:
		fill_color = Color(0.8, 0.2, 0.2, 0.5)
		border_color = Color(1.0, 0.0, 0.0, 0.8)
	else:
		if owner_player == 1:
			fill_color = Color(0.2, 0.2, 0.8, 0.5)
			border_color = Color(0.3, 0.3, 1.0, 0.8)
		else:
			fill_color = Color(0.8, 0.2, 0.2, 0.5)
			border_color = Color(1.0, 0.3, 0.3, 0.8)
	
	draw_circle(Vector2.ZERO, radius, fill_color)
	
	var segments = 64
	for i in range(segments):
		var angle1 = (i * TAU) / segments
		var angle2 = ((i + 1) * TAU) / segments
		var p1 = Vector2(cos(angle1), sin(angle1)) * radius
		var p2 = Vector2(cos(angle2), sin(angle2)) * radius
		draw_line(p1, p2, border_color, 2.0)

func set_validity(valid: bool) -> void:
	is_valid_position = valid
	queue_redraw()