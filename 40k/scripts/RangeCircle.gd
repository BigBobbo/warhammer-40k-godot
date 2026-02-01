extends Node2D

# RangeCircle - Visual indicator for weapon range
# Shows a circular area with radius and weapon label

var radius: float = 100.0
var weapon_name: String = "Weapon"
var circle_color: Color = Color(0, 1, 0, 0.15)  # Semi-transparent green fill
var outline_color: Color = Color.GREEN
var outline_width: float = 2.0

func setup(range_px: float, weapon: String, custom_color: Color = Color(-1, -1, -1)) -> void:
	radius = range_px
	weapon_name = weapon

	# Allow custom colors (negative means use default)
	if custom_color.r >= 0:
		outline_color = custom_color
		circle_color = Color(custom_color.r, custom_color.g, custom_color.b, 0.15)

	queue_redraw()

	# Add label
	var label = Label.new()
	label.text = "%s: %.0f\"" % [weapon_name, Measurement.px_to_inches(radius)]
	label.position = Vector2(radius * 0.7, -25)
	label.add_theme_color_override("font_color", outline_color)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_font_size_override("font_size", 12)
	add_child(label)

func _draw() -> void:
	if radius <= 0:
		return
	
	# Draw filled circle with transparency
	draw_circle(Vector2.ZERO, radius, circle_color)
	
	# Draw circle outline
	draw_arc(Vector2.ZERO, radius, 0, TAU, 64, outline_color, outline_width, true)
	
	# Draw small center point
	draw_circle(Vector2.ZERO, 5, outline_color)