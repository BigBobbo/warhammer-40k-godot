extends Node2D

# AIUnitHighlight - Pulsing glow ring for AI active unit highlighting (T7-52)
# Draws a colored pulsing ring around models of the unit the AI is currently acting with.
# Color indicates the action type: blue=move, red=shoot, orange=charge/fight.
# Follows the EngagementRangeVisual.gd pulsing pattern.

# Action type color constants
const COLOR_MOVE: Color = Color(0.2, 0.5, 1.0)     # Blue for movement
const COLOR_SHOOT: Color = Color(1.0, 0.15, 0.15)   # Red for shooting
const COLOR_CHARGE: Color = Color(1.0, 0.55, 0.1)   # Orange for charge/fight

var highlight_color: Color = COLOR_MOVE
var ring_radius: float = 28.0  # Slightly larger than typical base radius
var ring_width: float = 3.0
var glow_width: float = 8.0
var pulse_enabled: bool = true
var _pulse_time: float = 0.0

func setup(radius: float, color: Color) -> void:
	ring_radius = radius
	highlight_color = color
	queue_redraw()

func _process(delta: float) -> void:
	if pulse_enabled:
		_pulse_time += delta
		queue_redraw()

func _draw() -> void:
	if ring_radius <= 0:
		return

	# Pulsing alpha using sine wave (matches EngagementRangeVisual pattern)
	var pulse_alpha = 0.7 + 0.3 * sin(_pulse_time * 3.0)

	# Layer 1: Outer glow (wide, transparent)
	var glow_color = highlight_color
	glow_color.a = 0.25 * pulse_alpha
	draw_arc(Vector2.ZERO, ring_radius + glow_width, 0, TAU, 48, glow_color, glow_width * 2.0, true)

	# Layer 2: Main ring
	var main_color = highlight_color
	main_color.a = 0.9 * pulse_alpha
	draw_arc(Vector2.ZERO, ring_radius, 0, TAU, 48, main_color, ring_width, true)

	# Layer 3: Inner subtle fill
	var fill_color = highlight_color
	fill_color.a = 0.1 * pulse_alpha
	draw_circle(Vector2.ZERO, ring_radius - 2, fill_color)
