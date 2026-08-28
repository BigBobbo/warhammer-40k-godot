extends Node2D

# StrategicReservesZoneVisual - Highlights the VALID placement band for a unit
# arriving from Strategic Reserves. Such a unit must be set up wholly within 6"
# of a battlefield edge (and, separately, >9" from enemy models — that exclusion
# is drawn by DeepStrikeExclusionVisual). This visual paints the 6"-from-edge
# "frame" band around the board perimeter in green ("you can deploy here"),
# complementing the red enemy-exclusion bubbles.
#
# 20.04 says "wholly within" the 6" set-up distance, so the band drawn is where
# the model's CENTRE may legally sit: the 6" line pulled in by the base radius
# (the far side of the base has to fit too) and the board edge pushed out by it
# (no base may hang off the table). That inset is per-model, so the band is
# rebuilt whenever the model being placed changes — a fixed 6" frame would go
# back to over-promising by a base radius, which is 2" for a 100mm oval.
#
# 11e 20.04 also bans arriving models from the OPPONENT'S DEPLOYMENT ZONE before
# the third battle round, and the band along the opponent's board edge sits
# squarely inside it. Painting the whole perimeter green told the player that
# strip was a legal drop — the single most misleading thing this visual could
# do — so the banned slice is now carved out of the green fill and drawn in red
# instead. Deep Strike (24.09) lifts the ban, but this visual is only shown for
# Strategic Reserves placements (Main._is_strategic_reserves_placement), so the
# carve-out is unconditional apart from the battle round.

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

# The opponent-DZ slice of the band: legal-looking, but banned before round 3.
const BANNED_FILL_COLOR: Color = Color(1.0, 0.28, 0.28, 0.13)
const BANNED_LINE_COLOR: Color = Color(1.0, 0.35, 0.35, 0.9)

var _board_w_px: float = DEFAULT_BOARD_W_INCHES * PX_PER_INCH
var _board_h_px: float = DEFAULT_BOARD_H_INCHES * PX_PER_INCH
var _band_px: float = EDGE_DISTANCE_INCHES * PX_PER_INCH
var _pulse_time: float = 0.0
var _is_active: bool = false
var _default_font: Font = null
# Band slice inside the opponent's DZ (px polygons), empty once the ban lifts.
var _banned_polys: Array = []
var _legal_polys: Array = []
var _arriving_owner: int = -1
# Base radius (inches) of the model currently being placed, and the controller
# to re-read it from as the player works through the unit's model types.
var _base_radius_inches: float = 0.0
var _placement_controller: Node = null

func _ready() -> void:
	z_index = -4  # Same layer as the exclusion visuals
	_default_font = FactionPalettes.FONT_RAJDHANI_SEMIBOLD
	set_process(false)

func show_zone(arriving_owner: int = -1, placement_controller: Node = null) -> void:
	"""Show the valid Strategic Reserves placement band. Reads the current board
	dimensions from GameState so the band always matches the real board.
	[param arriving_owner] is the player whose unit is arriving — pass it so the
	opponent-DZ carve-out is right during a Rapid Ingress, where the arriving
	player is NOT the active player. Defaults to the active player.
	[param placement_controller] is the DeploymentController running the
	placement; the band re-reads the current model's base radius from it each
	frame so it keeps matching the model actually about to be placed."""
	_arriving_owner = arriving_owner
	_placement_controller = placement_controller
	_base_radius_inches = _read_base_radius_inches()
	_resolve_board_size()
	_resolve_banned_slice()
	_is_active = true
	_pulse_time = 0.0
	set_process(true)
	visible = true
	queue_redraw()
	print("[StrategicReservesZoneVisual] Showing 6\" board-edge placement band (board %.0fx%.0f px, %d banned opponent-DZ slice(s))" % [_board_w_px, _board_h_px, _banned_polys.size()])

func _resolve_banned_slice() -> void:
	"""Split the 6\" perimeter band into the part the arriving unit may actually
	use and the part 20.04 bans (inside the opponent's deployment zone, before
	the third battle round). Both are px polygons in board space."""
	_legal_polys = []
	_banned_polys = []
	var bands := _band_rect_polys()
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		_legal_polys = bands
		return
	# Deep Strike arrivals never show this visual (Main only raises it for
	# Strategic Reserves), so is_deep_strike is false here.
	if not gs.ingress_opponent_dz_ban_applies(gs.get_battle_round(), false):
		_legal_polys = bands
		return
	# NB: not named `owner` — that shadows Node.owner.
	var arriving := _arriving_owner if _arriving_owner > 0 else int(gs.get_active_player())
	var opponent := 3 - arriving
	var dz: PackedVector2Array = gs.get_deployment_zone_poly_px(opponent)
	if dz.size() < 3:
		_legal_polys = bands
		return
	for band in bands:
		for part in Geometry2D.clip_polygons(band, dz):
			_legal_polys.append(part)
		for part in Geometry2D.intersect_polygons(band, dz):
			_banned_polys.append(part)

func _band_rect_polys() -> Array:
	"""The legal-centre frame as four non-overlapping rectangles (px): the 6"
	band pulled in by the base radius on the inner side (the base must fit
	wholly inside the set-up distance) and out by it on the outer side (no base
	may overhang the table). With a zero radius this is the plain 6" frame."""
	var w := _board_w_px
	var h := _board_h_px
	var r: float = clamp(_base_radius_inches * PX_PER_INCH, 0.0, _band_px)
	var outer := r                 # nearest the centre of a model can sit to the table edge
	var b: float = _band_px - r    # furthest it can sit from that edge
	if b <= outer:
		# Base wider than the whole band — nothing is legal, say so honestly
		# rather than drawing an inside-out rectangle.
		return []
	return [
		PackedVector2Array([Vector2(outer, outer), Vector2(w - outer, outer), Vector2(w - outer, b), Vector2(outer, b)]),
		PackedVector2Array([Vector2(outer, h - b), Vector2(w - outer, h - b), Vector2(w - outer, h - outer), Vector2(outer, h - outer)]),
		PackedVector2Array([Vector2(outer, b), Vector2(b, b), Vector2(b, h - b), Vector2(outer, h - b)]),
		PackedVector2Array([Vector2(w - b, b), Vector2(w - outer, b), Vector2(w - outer, h - b), Vector2(w - b, h - b)]),
	]

func _draw_filled_poly(poly: PackedVector2Array, color: Color) -> void:
	"""Fill an arbitrary (possibly concave) polygon. clip_polygons can hand back
	concave pieces, which draw_colored_polygon does not tessellate reliably, so
	triangulate first."""
	if poly.size() < 3:
		return
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		draw_colored_polygon(poly, color)
		return
	var i := 0
	while i + 2 < tris.size():
		draw_colored_polygon(PackedVector2Array([poly[tris[i]], poly[tris[i + 1]], poly[tris[i + 2]]]), color)
		i += 3

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
		# The player can switch model type mid-placement (a Runtherd's base is
		# not a Gretchin's), which moves the legal band. Rebuild on change only.
		var r := _read_base_radius_inches()
		if not is_equal_approx(r, _base_radius_inches):
			_base_radius_inches = r
			_resolve_banned_slice()
		queue_redraw()

func _read_base_radius_inches() -> float:
	"""Base radius of the model the controller is about to place, in inches.
	0.0 when there is nothing to read — the band then degrades to the old
	centre-point frame rather than disappearing."""
	if _placement_controller == null or not is_instance_valid(_placement_controller):
		return 0.0
	if not _placement_controller.has_method("current_placement_base_radius_inches"):
		return 0.0
	return float(_placement_controller.current_placement_base_radius_inches())

func _draw() -> void:
	if not _is_active:
		return

	var pulse_alpha = 0.7 + 0.3 * (1.0 + sin(_pulse_time * 2.0)) / 2.0
	var march_offset = fmod(_pulse_time * MARCH_SPEED, DASH_LENGTH + GAP_LENGTH)

	# Fill the perimeter frame. The bands are four non-overlapping rectangles so
	# the alpha does not double up where they meet at the corners; before the
	# third battle round each has had the opponent's deployment zone clipped out
	# of it (_resolve_banned_slice), so the green really is "you can deploy here".
	var fill = Color(FILL_COLOR.r, FILL_COLOR.g, FILL_COLOR.b, FILL_COLOR.a * pulse_alpha)
	for poly in _legal_polys:
		_draw_filled_poly(poly, fill)

	# The slice 20.04 bans: within 6" of a battlefield edge, but inside the
	# opponent's deployment zone. Red fill + dashed red outline so it reads as
	# "not here" rather than as part of the green band.
	var banned_fill = Color(BANNED_FILL_COLOR.r, BANNED_FILL_COLOR.g, BANNED_FILL_COLOR.b, BANNED_FILL_COLOR.a * pulse_alpha)
	var banned_line = Color(BANNED_LINE_COLOR.r, BANNED_LINE_COLOR.g, BANNED_LINE_COLOR.b, BANNED_LINE_COLOR.a * pulse_alpha)
	for poly in _banned_polys:
		_draw_filled_poly(poly, banned_fill)
		for i in range(poly.size()):
			_draw_dashed_line_colored(poly[i], poly[(i + 1) % poly.size()], banned_line, march_offset)

	# Draw the inner boundary (the 6" line) as an animated dashed rectangle.
	# Anything inside this rectangle (toward the board centre) is NOT a legal
	# Strategic Reserves position. Where the band is barred the boundary carries
	# no meaning — running a green "legal side is out here" line through the red
	# zone is the same lie this visual used to tell — so it is clipped to the
	# legal region (_inner_boundary_runs).
	var glow_color = Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, GLOW_COLOR.a * pulse_alpha)
	for run in _inner_boundary_runs():
		for i in range(run.size() - 1):
			draw_line(run[i], run[i + 1], glow_color, GLOW_WIDTH, true)
			_draw_dashed_line(run[i], run[i + 1], pulse_alpha, march_offset)

	_draw_zone_label(pulse_alpha)

func _inner_boundary_runs() -> Array:
	"""The 6\" inner boundary as one or more polylines, with any stretch inside
	the barred opponent-DZ slice removed."""
	var w := _board_w_px
	var h := _board_h_px
	# Same inset as _band_rect_polys: the boundary is where the CENTRE stops
	# being legal, which the base radius pulls in from the bare 6" line.
	var b: float = _band_px - clamp(_base_radius_inches * PX_PER_INCH, 0.0, _band_px)
	if b <= 0.0 or w - b <= b or h - b <= b:
		return []
	var ring := PackedVector2Array([
		Vector2(b, b), Vector2(w - b, b), Vector2(w - b, h - b), Vector2(b, h - b), Vector2(b, b),
	])
	if _banned_polys.is_empty():
		return [ring]
	var runs: Array = [ring]
	for banned in _banned_polys:
		var next_runs: Array = []
		for run in runs:
			for part in Geometry2D.clip_polyline_with_polygon(run, banned):
				next_runs.append(part)
		runs = next_runs
	return runs

func _draw_dashed_line(p1: Vector2, p2: Vector2, pulse_alpha: float, march_offset: float) -> void:
	"""Draw a marching-ants dashed line between two points."""
	var direction = (p2 - p1).normalized()
	var total_length = p1.distance_to(p2)
	var segment_length = DASH_LENGTH + GAP_LENGTH

	if total_length < 1.0:
		return

	var line_color = Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, LINE_COLOR.a * pulse_alpha)
	_draw_dashed_line_colored(p1, p2, line_color, march_offset)

func _draw_dashed_line_colored(p1: Vector2, p2: Vector2, line_color: Color, march_offset: float) -> void:
	"""Marching-ants dashed line in an explicit colour (green band boundary vs
	red opponent-DZ outline)."""
	var direction = (p2 - p1).normalized()
	var total_length = p1.distance_to(p2)
	var segment_length = DASH_LENGTH + GAP_LENGTH

	if total_length < 1.0:
		return

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

	var label_text = "Reserves: wholly within 6\" of edge"
	# Centre horizontally, sit vertically in the middle of the top band.
	_draw_band_label(label_text, Vector2(_board_w_px / 2.0, _band_px / 2.0), LINE_COLOR, pulse_alpha)

	# Name the red slice so the player knows why part of the band is barred
	# rather than assuming the visual is glitching.
	for poly in _banned_polys:
		var centroid := Vector2.ZERO
		for pt in poly:
			centroid += pt
		if poly.size() > 0:
			centroid /= float(poly.size())
		_draw_band_label("Opponent's DZ — barred until battle round 3", centroid, BANNED_LINE_COLOR, pulse_alpha)

func _draw_band_label(label_text: String, label_pos: Vector2, color: Color, pulse_alpha: float) -> void:
	"""Draw one pill-backed caption centred on [param label_pos]."""
	if not _default_font:
		return
	var text_size = _default_font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)

	var bg_rect = Rect2(
		label_pos - LABEL_BG_PADDING - Vector2(text_size.x / 2.0, text_size.y / 2.0),
		text_size + LABEL_BG_PADDING * 2
	)
	var bg_color = Color(LABEL_BG_COLOR.r, LABEL_BG_COLOR.g, LABEL_BG_COLOR.b, LABEL_BG_COLOR.a * pulse_alpha)
	draw_rect(bg_rect, bg_color, true)

	var text_color = Color(color.r, color.g, color.b, pulse_alpha)
	draw_string(
		_default_font,
		label_pos - Vector2(text_size.x / 2.0, -text_size.y / 4.0),
		label_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE,
		text_color
	)
