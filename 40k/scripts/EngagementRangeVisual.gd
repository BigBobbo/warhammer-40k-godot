extends Node2D

# EngagementRangeVisual - Pulsing engagement range circle for Fight Phase
# T5-V9: Draws a pulsing circle around models to show engagement range (1 inch)
# Follows the same sine-wave animation pattern as RangeCircle.gd

enum Mode { ENGAGEMENT_RANGE, TARGET_HIGHLIGHT }

var circle_radius: float = 25.4  # Default 1 inch in mm
var circle_color: Color = FALLBACK_ORANGE
var fill_alpha: float = 0.2
var outline_width: float = 2.0
var mode: int = Mode.ENGAGEMENT_RANGE
var pulse_enabled: bool = true
var _pulse_time: float = 0.0

# T29: when true, this ring is being shown by the PersistentEngagementOverlay
# rather than as a transient selection / hover affordance. The flag itself
# does not change rendering — it lets scenarios distinguish "ambient
# engaged" vs "ephemeral selection" rings.
var is_persistent: bool = false

# T12: default colors resolve from the UIConstants slot table at setup time.
# Color(0,0,0,0) is the "use the slot default" sentinel — every current
# caller passes an explicit color. The FALLBACK_* literals equal the
# canonical slot hexes for headless -s contexts where the autoload is
# absent (bare autoload names don't compile there); keep in sync with §9.
const FALLBACK_ORANGE: Color = Color(1.0, 0.55, 0.0, 1.0)  # == UIConstants.WARNING_ORANGE
const FALLBACK_GREEN: Color = Color(0.2, 0.85, 0.3, 1.0)   # == UIConstants.CONFIRMED_GREEN

func _slot_color(slot: String, fallback: Color) -> Color:
	var uic = get_node_or_null("/root/UIConstants")
	return uic.get(slot) if uic != null else fallback

func setup_engagement_range(radius: float, color: Color = Color(0, 0, 0, 0)) -> void:
	circle_radius = radius
	circle_color = color if color.a > 0.0 else _slot_color("WARNING_ORANGE", FALLBACK_ORANGE)
	fill_alpha = 0.2
	outline_width = 2.0
	mode = Mode.ENGAGEMENT_RANGE
	queue_redraw()

func setup_target_highlight(radius: float, color: Color = Color(0, 0, 0, 0), is_eligible: bool = true) -> void:
	circle_radius = radius
	circle_color = color if color.a > 0.0 else _slot_color("CONFIRMED_GREEN", FALLBACK_GREEN)
	fill_alpha = 0.3
	outline_width = 4.0
	mode = Mode.TARGET_HIGHLIGHT
	# Only pulse eligible (green) targets, not ineligible (gray) ones
	pulse_enabled = is_eligible
	queue_redraw()

func _process(delta: float) -> void:
	if pulse_enabled:
		_pulse_time += delta
		queue_redraw()

func _draw() -> void:
	if circle_radius <= 0:
		return

	# Compute pulse alpha modulation (subtle breathing effect)
	# Matches RangeCircle.gd pattern: 0.7 to 1.0 range using sine wave
	var pulse_alpha = 1.0
	if pulse_enabled:
		pulse_alpha = 0.7 + 0.3 * sin(_pulse_time * 2.0)

	if mode == Mode.ENGAGEMENT_RANGE:
		_draw_engagement_range(pulse_alpha)
	elif mode == Mode.TARGET_HIGHLIGHT:
		_draw_target_highlight(pulse_alpha)

func _draw_engagement_range(pulse_alpha: float) -> void:
	# Draw filled circle with pulsing transparency
	var fill_color = circle_color
	fill_color.a = fill_alpha * pulse_alpha
	draw_circle(Vector2.ZERO, circle_radius, fill_color)

	# Draw engagement range circle outline with pulsing
	var line_color = circle_color
	line_color.a = pulse_alpha
	draw_arc(Vector2.ZERO, circle_radius, 0, TAU, 32, line_color, outline_width, true)

func _draw_target_highlight(pulse_alpha: float) -> void:
	# Draw outer ring with pulsing
	var line_color = circle_color
	line_color.a = pulse_alpha
	draw_arc(Vector2.ZERO, circle_radius, 0, TAU, 32, line_color, outline_width, true)

	# Draw inner filled circle with pulsing transparency
	var fill_color = circle_color
	fill_color.a = fill_alpha * pulse_alpha
	draw_circle(Vector2.ZERO, circle_radius - 3, fill_color)

	# Draw extra outer ring for eligible targets (pulsing glow effect)
	if pulse_enabled:
		var glow_color = circle_color
		glow_color.a = 0.4 * pulse_alpha
		draw_arc(Vector2.ZERO, circle_radius + 8, 0, TAU, 32, glow_color, 1.5, true)
