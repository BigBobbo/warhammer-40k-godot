extends Node2D
class_name CircleShape

var radius: float = 32.0
var color: Color = Color.WHITE
var filled: bool = false
var width: float = 2.0

func _draw() -> void:
	if filled:
		draw_circle(Vector2.ZERO, radius, color)
	else:
		draw_arc(Vector2.ZERO, radius, 0, TAU, 64, color, width)

func set_color(new_color: Color) -> void:
	color = new_color
	queue_redraw()

func set_radius(new_radius: float) -> void:
	radius = new_radius
	queue_redraw()