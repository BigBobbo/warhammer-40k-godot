extends Node2D

# CoherencyCircleVisual - Faint 2" coherency range circle drawn around placed models
# during deployment. Shows green when the next model (ghost) is within coherency range,
# red when outside range. Uses edge-to-edge measurement so the visual radius accounts
# for the model's own base size.

var circle_radius_px: float = 80.0  # Default: 2" * 40 px/inch
var base_radius_px: float = 0.0  # The model's own base radius in pixels
var circle_color: Color = Color(0.2, 0.9, 0.2, 0.25)  # Faint green default
var _pulse_time: float = 0.0

const COHERENCY_INCHES: float = 2.0
const DASH_LENGTH: float = 8.0
const GAP_LENGTH: float = 6.0
const OUTLINE_WIDTH: float = 1.5
const FILL_ALPHA: float = 0.08
const OUTLINE_ALPHA: float = 0.35

# Colors
const COLOR_GREEN: Color = Color(0.2, 0.9, 0.2)
const COLOR_RED: Color = Color(0.9, 0.2, 0.2)

func setup(model_base_radius_px: float) -> void:
	base_radius_px = model_base_radius_px
	# The coherency circle shows 2" from the edge of this model's base.
	# So the drawn circle radius = base_radius + 2" in pixels.
	circle_radius_px = base_radius_px + Measurement.inches_to_px(COHERENCY_INCHES)
	z_index = 5  # Below tokens (z_index 10) but above board
	queue_redraw()

func set_in_range(is_in_range: bool) -> void:
	var new_color = COLOR_GREEN if is_in_range else COLOR_RED
	if circle_color != new_color:
		circle_color = new_color
		queue_redraw()

func _process(delta: float) -> void:
	_pulse_time += delta
	queue_redraw()

func _draw() -> void:
	if circle_radius_px <= 0:
		return

	# Subtle pulse: alpha modulates between 0.8 and 1.0
	var pulse = 0.8 + 0.2 * sin(_pulse_time * 1.5)

	# Draw faint filled circle
	var fill_color = circle_color
	fill_color.a = FILL_ALPHA * pulse
	draw_circle(Vector2.ZERO, circle_radius_px, fill_color)

	# Draw dashed outline
	_draw_dashed_circle(circle_radius_px, pulse)

func _draw_dashed_circle(radius: float, pulse: float) -> void:
	var line_color = circle_color
	line_color.a = OUTLINE_ALPHA * pulse

	var circumference = TAU * radius
	var total_segment = DASH_LENGTH + GAP_LENGTH
	var num_dashes = int(circumference / total_segment)
	if num_dashes < 1:
		num_dashes = 1

	var dash_angle = (DASH_LENGTH / circumference) * TAU
	var gap_angle = (GAP_LENGTH / circumference) * TAU

	for i in range(num_dashes):
		var start_angle = i * (dash_angle + gap_angle)
		draw_arc(Vector2.ZERO, radius, start_angle, start_angle + dash_angle, 8, line_color, OUTLINE_WIDTH, true)
