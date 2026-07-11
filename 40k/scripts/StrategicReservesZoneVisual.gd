extends Node2D

# StrategicReservesZoneVisual - Highlights the VALID placement band for a unit
# arriving from Strategic Reserves. Such a unit must be set up wholly within 6"
# of a battlefield edge (and, separately, >9" from enemy models — that exclusion
# is drawn by DeepStrikeExclusionVisual). This visual paints the 6"-from-edge
# "frame" band around the board perimeter in green ("you can deploy here"),
# complementing the red enemy-exclusion bubbles.
#
# The 6" rule is measured from the model's centre to the nearest board edge, to
# match DeploymentController._validate_reinforcement_position exactly.

const PX_PER_INCH: float = 40.0
const EDGE_DISTANCE_INCHES: float = 6.0
const DEFAULT_BOARD_W_INCHES: float = 44.0
const DEFAULT_BOARD_H_INCHES: float = 60.0

# Dashed line style (matches the other placement visuals)
const DASH_LENGTH: float = 12.0
const GAP_LENGTH: float = 8.0
const LINE_WIDTH: float = 2.5
const MARCH_SPEED: float = 25.0

# Colors - green to signal a permitted area (contrast with the red exclusion visual)
const LINE_COLOR: Color = Color(0.3, 1.0, 0.45, 0.85)
const GLOW_COLOR: Color = Color(0.3, 1.0, 0.45, 0.15)
const GLOW_WIDTH: float = 8.0
const FILL_COLOR: Color = Color(0.3, 1.0, 0.45, 0.07)
const LABEL_BG_COLOR: Color = Color(0.05, 0.1, 0.06, 0.85)
const LABEL_BG_PADDING: Vector2 = Vector2(6, 3)
const FONT_SIZE: int = 13

var _board_w_px: float = DEFAULT_BOARD_W_INCHES * PX_PER_INCH
var _board_h_px: float = DEFAULT_BOARD_H_INCHES * PX_PER_INCH
var _band_px: float = EDGE_DISTANCE_INCHES * PX_PER_INCH
var _pulse_time: float = 0.0
var _is_active: bool = false
var _default_font: Font = null

func _ready() -> void:
	z_index = -4  # Same layer as the exclusion visuals
	_default_font = FactionPalettes.FONT_RAJDHANI_SEMIBOLD
	set_process(false)

func show_zone() -> void:
	"""Show the within-6\"-of-edge valid placement band. Reads the current board
	dimensions from GameState so the band always matches the real board."""
	_resolve_board_size()
	_is_active = true
	_pulse_time = 0.0
	set_process(true)
	visible = true
	queue_redraw()
	print("[StrategicReservesZoneVisual] Showing 6\" board-edge placement band (board %.0fx%.0f px)" % [_board_w_px, _board_h_px])

func hide_zone() -> void:
	"""Hide the valid placement band."""
	_is_active = false
	set_process(false)
	visible = false
	queue_redraw()

func _resolve_board_size() -> void:
	_board_w_px = DEFAULT_BOARD_W_INCHES * PX_PER_INCH
	_board_h_px = DEFAULT_BOARD_H_INCHES * PX_PER_INCH
	var gs = get_node_or_null("/root/GameState")
	if gs and gs.state.has("board"):
		var size = gs.state.board.get("size", null)
		if size != null:
			var w = size.get("width", DEFAULT_BOARD_W_INCHES)
			var h = size.get("height", DEFAULT_BOARD_H_INCHES)
			if w > 0 and h > 0:
				_board_w_px = float(w) * PX_PER_INCH
				_board_h_px = float(h) * PX_PER_INCH
	# Never let the band exceed half the board (degenerate on tiny boards)
	_band_px = min(EDGE_DISTANCE_INCHES * PX_PER_INCH, min(_board_w_px, _board_h_px) / 2.0)

func _process(delta: float) -> void:
	if _is_active:
		_pulse_time += delta
		queue_redraw()

func _draw() -> void:
	if not _is_active:
		return

	var pulse_alpha = 0.7 + 0.3 * (1.0 + sin(_pulse_time * 2.0)) / 2.0
	var march_offset = fmod(_pulse_time * MARCH_SPEED, DASH_LENGTH + GAP_LENGTH)

	var w = _board_w_px
	var h = _board_h_px
	var b = _band_px

	# Fill the perimeter frame as four non-overlapping rectangles so the alpha
	# does not double up where bands meet at the corners.
	var fill = Color(FILL_COLOR.r, FILL_COLOR.g, FILL_COLOR.b, FILL_COLOR.a * pulse_alpha)
	draw_rect(Rect2(0, 0, w, b), fill, true)                 # top band
	draw_rect(Rect2(0, h - b, w, b), fill, true)             # bottom band
	draw_rect(Rect2(0, b, b, h - 2.0 * b), fill, true)       # left band
	draw_rect(Rect2(w - b, b, b, h - 2.0 * b), fill, true)   # right band

	# Draw the inner boundary (the 6" line) as an animated dashed rectangle.
	# Anything inside this rectangle (toward the board centre) is NOT a legal
	# Strategic Reserves position.
	var inner = [
		Vector2(b, b),
		Vector2(w - b, b),
		Vector2(w - b, h - b),
		Vector2(b, h - b),
	]
	for i in range(inner.size()):
		var p1 = inner[i]
		var p2 = inner[(i + 1) % inner.size()]
		var glow_color = Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, GLOW_COLOR.a * pulse_alpha)
		draw_line(p1, p2, glow_color, GLOW_WIDTH, true)
		_draw_dashed_line(p1, p2, pulse_alpha, march_offset)

	_draw_zone_label(pulse_alpha)

func _draw_dashed_line(p1: Vector2, p2: Vector2, pulse_alpha: float, march_offset: float) -> void:
	"""Draw a marching-ants dashed line between two points."""
	var direction = (p2 - p1).normalized()
	var total_length = p1.distance_to(p2)
	var segment_length = DASH_LENGTH + GAP_LENGTH

	if total_length < 1.0:
		return

	var line_color = Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, LINE_COLOR.a * pulse_alpha)

	var pos = -march_offset
	while pos < total_length:
		var dash_start = max(pos, 0.0)
		var dash_end = min(pos + DASH_LENGTH, total_length)

		if dash_start < dash_end:
			var start_pt = p1 + direction * dash_start
			var end_pt = p1 + direction * dash_end
			draw_line(start_pt, end_pt, line_color, LINE_WIDTH, true)

		pos += segment_length

func _draw_zone_label(pulse_alpha: float) -> void:
	"""Draw a 'Reserves: within 6\" of edge' label centred on the top band."""
	if not _default_font:
		return

	var label_text = "Reserves: within 6\" of edge"
	var text_size = _default_font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)

	# Centre horizontally, sit vertically in the middle of the top band.
	var label_pos = Vector2(_board_w_px / 2.0, _band_px / 2.0)

	var bg_rect = Rect2(
		label_pos - LABEL_BG_PADDING - Vector2(text_size.x / 2.0, text_size.y / 2.0),
		text_size + LABEL_BG_PADDING * 2
	)
	var bg_color = Color(LABEL_BG_COLOR.r, LABEL_BG_COLOR.g, LABEL_BG_COLOR.b, LABEL_BG_COLOR.a * pulse_alpha)
	draw_rect(bg_rect, bg_color, true)

	var text_color = Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, pulse_alpha)
	draw_string(
		_default_font,
		label_pos - Vector2(text_size.x / 2.0, -text_size.y / 4.0),
		label_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE,
		text_color
	)
