extends Node2D

# CoherencyWarningVisual - flashing red marker for a model that is OUT OF unit
# coherency (11e 03.03 "Regaining Coherency").
#
# Before this existed the player was told "this unit is out of coherency, remove
# a model" with no indication of WHICH model was the problem or how far it would
# have to move to fix it. Two rings are drawn around the offender:
#
#   1. A hard, fast-flashing red boundary hugging the model's base — "this is
#      the model the game is complaining about".
#   2. The 2" coherency reach circle (base edge + 2"), dashed and slowly
#      pulsing — any friendly model of the same unit inside that ring puts this
#      model back in coherency, so it doubles as "move a mate to here".
#
# Sibling of CoherencyCircleVisual (the faint green/red deployment helper); kept
# separate because this one is an ERROR callout, not placement guidance.

# 2" comes from GameConstants.coherency_distance_inches() (ISS-002).
const RING_MARGIN_PX: float = 4.0     # Gap between base edge and the hard ring
const RING_WIDTH: float = 3.5
const REACH_WIDTH: float = 2.0
const DASH_LENGTH: float = 10.0
const GAP_LENGTH: float = 7.0
const REACH_FILL_ALPHA: float = 0.07
const FLASH_HZ: float = 2.2           # Hard-ring flash rate
const REACH_PULSE_HZ: float = 0.9     # Reach-circle pulse (slower, calmer)
const LABEL_OFFSET_PX: float = 14.0

const COLOR_RED: Color = Color(0.95, 0.16, 0.16)

var base_radius_px: float = 25.0
var reach_radius_px: float = 105.0
var label_text: String = ""
# When the 9" envelope is what broke, every model in the unit is technically an
# offender. Only the worst one (furthest from its nearest mate) is drawn at full
# strength; the rest are muted so the player's eye lands on the actual straggler
# instead of a wall of identical rings.
var is_primary: bool = true

var _t: float = 0.0

func set_primary(p_is_primary: bool) -> void:
	is_primary = p_is_primary
	queue_redraw()

func setup(model_base_radius_px: float, p_label_text: String = "") -> void:
	base_radius_px = max(model_base_radius_px, 1.0)
	# The coherency reach is measured edge-to-edge, so the drawn radius has to
	# include this model's own base radius (same convention as
	# CoherencyCircleVisual.setup).
	reach_radius_px = base_radius_px + Measurement.inches_to_px(GameConstants.coherency_distance_inches())
	label_text = p_label_text
	z_index = 20  # Above tokens (z_index 10) — this is a blocking error callout
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	# 0.5 .. 1.0 flash: it has to read as an alert while never dimming to the
	# point where the marker is invisible (including in a screenshot that lands
	# on the trough).
	var flash: float = 0.5 + 0.5 * (0.5 + 0.5 * sin(_t * TAU * FLASH_HZ))
	var pulse: float = 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * TAU * REACH_PULSE_HZ))
	var strength: float = 1.0 if is_primary else 0.35

	# 2" reach circle — where a friendly model has to be for this one to be coherent
	var reach_fill := COLOR_RED
	reach_fill.a = REACH_FILL_ALPHA * pulse * strength
	draw_circle(Vector2.ZERO, reach_radius_px, reach_fill)
	var reach_line := COLOR_RED
	reach_line.a = 0.75 * pulse * strength
	_draw_dashed_circle(reach_radius_px, reach_line, REACH_WIDTH)

	# Hard flashing boundary on the offending model itself
	var ring := COLOR_RED
	ring.a = flash * strength
	draw_arc(Vector2.ZERO, base_radius_px + RING_MARGIN_PX, 0.0, TAU, 48, ring,
		RING_WIDTH if is_primary else RING_WIDTH * 0.6, true)

	if label_text != "":
		var font := ThemeDB.fallback_font
		var font_size := 13
		var width := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var pos := Vector2(-width / 2.0, -(reach_radius_px + LABEL_OFFSET_PX))
		# Shadow first so the text stays readable over light terrain
		draw_string(font, pos + Vector2(1, 1), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, Color(0, 0, 0, 0.85 * flash))
		var text_color := COLOR_RED
		text_color.a = flash
		draw_string(font, pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

func _draw_dashed_circle(radius: float, color: Color, width: float) -> void:
	var circumference := TAU * radius
	if circumference <= 0.0:
		return
	var total_segment := DASH_LENGTH + GAP_LENGTH
	var num_dashes := int(circumference / total_segment)
	if num_dashes < 1:
		num_dashes = 1
	var dash_angle := (DASH_LENGTH / circumference) * TAU
	var gap_angle := (GAP_LENGTH / circumference) * TAU
	# Slow rotation so the dashes crawl — reads as "active warning"
	var spin := _t * 0.6
	for i in range(num_dashes):
		var start_angle := spin + i * (dash_angle + gap_angle)
		draw_arc(Vector2.ZERO, radius, start_angle, start_angle + dash_angle, 8, color, width, true)
