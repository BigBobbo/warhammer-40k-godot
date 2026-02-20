extends Node2D

# RangeCircle - Visual indicator for weapon range
# Shows a circular area with radius and weapon label
# Supports solid (full range) and dashed (half-range) styles
# T5-V5: Enhanced range circle visualization for weapons

var radius: float = 100.0
var weapon_name: String = "Weapon"
var circle_color: Color = Color(0, 1, 0, 0.15)  # Semi-transparent green fill
var outline_color: Color = Color.GREEN
var outline_width: float = 2.0
var dashed: bool = false  # If true, draw dashed outline instead of solid
var dash_length: float = 12.0  # Length of each dash segment in pixels
var gap_length: float = 8.0  # Length of each gap between dashes
var pulse_enabled: bool = true  # Subtle pulse animation on the outline
var _pulse_time: float = 0.0

func setup(range_px: float, weapon: String, custom_color: Color = Color(-1, -1, -1), is_dashed: bool = false) -> void:
	radius = range_px
	weapon_name = weapon
	dashed = is_dashed

	# Allow custom colors (negative means use default)
	if custom_color.r >= 0:
		outline_color = custom_color
		circle_color = Color(custom_color.r, custom_color.g, custom_color.b, 0.1 if is_dashed else 0.15)

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

func _process(delta: float) -> void:
	if pulse_enabled:
		_pulse_time += delta
		queue_redraw()

func _draw() -> void:
	if radius <= 0:
		return

	# Compute pulse alpha modulation (subtle breathing effect)
	var pulse_alpha = 1.0
	if pulse_enabled:
		pulse_alpha = 0.7 + 0.3 * sin(_pulse_time * 2.0)

	# Draw filled circle with transparency
	var fill = circle_color
	fill.a *= pulse_alpha
	draw_circle(Vector2.ZERO, radius, fill)

	# Draw circle outline (solid or dashed)
	var line_color = outline_color
	line_color.a *= pulse_alpha
	if dashed:
		_draw_dashed_arc(Vector2.ZERO, radius, line_color, outline_width)
	else:
		draw_arc(Vector2.ZERO, radius, 0, TAU, 64, line_color, outline_width, true)

	# Draw small center point
	var center_color = outline_color
	center_color.a *= pulse_alpha
	draw_circle(Vector2.ZERO, 5, center_color)

func _draw_dashed_arc(center: Vector2, arc_radius: float, color: Color, width: float) -> void:
	# Draw a dashed circle by drawing many small arc segments with gaps
	var circumference = TAU * arc_radius
	var segment_length = dash_length + gap_length
	var num_segments = int(circumference / segment_length)
	if num_segments < 8:
		num_segments = 8

	var dash_angle = (dash_length / circumference) * TAU
	var total_angle = TAU / float(num_segments)

	for i in range(num_segments):
		var start_angle = i * total_angle
		# Draw just the dash portion of each segment
		draw_arc(center, arc_radius, start_angle, start_angle + dash_angle, 8, color, width, true)
