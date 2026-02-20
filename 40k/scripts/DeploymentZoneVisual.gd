extends Polygon2D

# DeploymentZoneVisual - Enhanced deployment zone rendering with edge highlighting
# T5-V14: Pulsing animated dashed border, glow layers on inner edges,
# and zone depth labels for clearer boundary visibility.
# Follows sine-wave animation pattern from EngagementRangeVisual.gd
# and dashed line pattern from PileInMovementVisual.gd / RangeCircle.gd

var is_active: bool = false
var border_color: Color = Color.WHITE
var border_width: float = 3.0
var player_number: int = 0  # 1 or 2, set by Main.gd

# Animation state
var _pulse_time: float = 0.0

# Dashed line constants
const DASH_LENGTH: float = 14.0
const GAP_LENGTH: float = 8.0
const MARCH_SPEED: float = 30.0  # Pixels per second for marching ants

# Glow constants
const GLOW_WIDTH_OUTER: float = 10.0
const GLOW_WIDTH_INNER: float = 6.0
const GLOW_ALPHA_OUTER: float = 0.15
const GLOW_ALPHA_INNER: float = 0.3

# Inner edge emphasis (edges facing no-man's-land, not board boundary)
const INNER_EDGE_BORDER_WIDTH: float = 4.0
const OUTER_EDGE_BORDER_WIDTH: float = 2.0

# Board boundary threshold (pixels) — edges within this distance of the board edge are "outer"
const BOARD_EDGE_THRESHOLD: float = 5.0

# Zone depth label
const FONT_SIZE: int = 14
const LABEL_BG_COLOR: Color = Color(0.1, 0.08, 0.05, 0.85)
const LABEL_BG_PADDING: Vector2 = Vector2(6, 3)

var default_font: Font = null

func _ready() -> void:
	z_index = -5
	default_font = ThemeDB.fallback_font

func _process(delta: float) -> void:
	if is_active:
		_pulse_time += delta
		queue_redraw()

func _draw() -> void:
	if not is_active:
		return

	var points = polygon
	if points.size() < 2:
		return

	# Compute pulse alpha (sine wave breathing: 0.6 to 1.0)
	var pulse_alpha = 0.8 + 0.2 * sin(_pulse_time * 2.5)

	# Marching ants offset
	var march_offset = fmod(_pulse_time * MARCH_SPEED, DASH_LENGTH + GAP_LENGTH)

	# Get board dimensions for inner/outer edge detection
	var board_width_px = Measurement.inches_to_px(44.0) if Measurement else 44.0 * 40
	var board_height_px = Measurement.inches_to_px(60.0) if Measurement else 60.0 * 40

	# Draw each edge with appropriate styling
	for i in range(points.size()):
		var p1 = points[i]
		var p2 = points[(i + 1) % points.size()]
		var is_inner = _is_inner_edge(p1, p2, board_width_px, board_height_px)

		if is_inner:
			# Inner edges (facing no-man's-land) get full treatment: glow + dashed + emphasis
			_draw_edge_glow(p1, p2, pulse_alpha)
			_draw_dashed_edge(p1, p2, border_color, INNER_EDGE_BORDER_WIDTH, march_offset, pulse_alpha)
		else:
			# Board boundary edges: subtle dashed line, no glow
			var dim_color = Color(border_color.r, border_color.g, border_color.b, border_color.a * 0.5)
			_draw_dashed_edge(p1, p2, dim_color, OUTER_EDGE_BORDER_WIDTH, march_offset, pulse_alpha)

	# Draw corner markers on inner edge endpoints
	_draw_corner_markers(points, board_width_px, board_height_px, pulse_alpha)

	# Draw zone depth label on the longest inner edge
	_draw_zone_depth_label(points, board_width_px, board_height_px, pulse_alpha)

func _is_inner_edge(p1: Vector2, p2: Vector2, board_w: float, board_h: float) -> bool:
	# An edge is "outer" (board boundary) if both points lie on the same board edge
	# Check if both points are on x=0, x=board_w, y=0, or y=board_h
	var on_left = abs(p1.x) < BOARD_EDGE_THRESHOLD and abs(p2.x) < BOARD_EDGE_THRESHOLD
	var on_right = abs(p1.x - board_w) < BOARD_EDGE_THRESHOLD and abs(p2.x - board_w) < BOARD_EDGE_THRESHOLD
	var on_top = abs(p1.y) < BOARD_EDGE_THRESHOLD and abs(p2.y) < BOARD_EDGE_THRESHOLD
	var on_bottom = abs(p1.y - board_h) < BOARD_EDGE_THRESHOLD and abs(p2.y - board_h) < BOARD_EDGE_THRESHOLD
	return not (on_left or on_right or on_top or on_bottom)

func _draw_edge_glow(p1: Vector2, p2: Vector2, pulse_alpha: float) -> void:
	# Outer glow layer (wider, more transparent)
	var glow_outer = Color(border_color.r, border_color.g, border_color.b, GLOW_ALPHA_OUTER * pulse_alpha)
	draw_line(p1, p2, glow_outer, GLOW_WIDTH_OUTER, true)

	# Inner glow layer (narrower, slightly more visible)
	var glow_inner = Color(border_color.r, border_color.g, border_color.b, GLOW_ALPHA_INNER * pulse_alpha)
	draw_line(p1, p2, glow_inner, GLOW_WIDTH_INNER, true)

func _draw_dashed_edge(p1: Vector2, p2: Vector2, color: Color, width: float, march_offset: float, pulse_alpha: float) -> void:
	# Draw a dashed line with marching ants animation between two points
	var direction = (p2 - p1).normalized()
	var total_length = p1.distance_to(p2)
	var segment_length = DASH_LENGTH + GAP_LENGTH

	if total_length < 1.0:
		return

	var line_color = Color(color.r, color.g, color.b, color.a * pulse_alpha)

	# Iterate with offset for marching ants effect
	var pos = -march_offset
	while pos < total_length:
		var dash_start = max(pos, 0.0)
		var dash_end = min(pos + DASH_LENGTH, total_length)

		if dash_start < dash_end:
			var start_pt = p1 + direction * dash_start
			var end_pt = p1 + direction * dash_end
			draw_line(start_pt, end_pt, line_color, width, true)

		pos += segment_length

func _draw_corner_markers(points: PackedVector2Array, board_w: float, board_h: float, pulse_alpha: float) -> void:
	# Draw small diamond markers at corners where inner edges meet
	for i in range(points.size()):
		var prev_idx = (i - 1 + points.size()) % points.size()
		var next_idx = (i + 1) % points.size()
		var p_prev = points[prev_idx]
		var p_curr = points[i]
		var p_next = points[next_idx]

		# Check if this corner has at least one inner edge
		var edge_before_inner = _is_inner_edge(p_prev, p_curr, board_w, board_h)
		var edge_after_inner = _is_inner_edge(p_curr, p_next, board_w, board_h)

		if edge_before_inner or edge_after_inner:
			var marker_color = Color(border_color.r, border_color.g, border_color.b, 0.9 * pulse_alpha)
			draw_circle(p_curr, 4.0, marker_color)

func _draw_zone_depth_label(points: PackedVector2Array, board_w: float, board_h: float, pulse_alpha: float) -> void:
	# Find the longest inner edge and draw a depth label on it
	if not default_font:
		return

	var best_length: float = 0.0
	var best_p1: Vector2 = Vector2.ZERO
	var best_p2: Vector2 = Vector2.ZERO
	var found_inner: bool = false

	for i in range(points.size()):
		var p1 = points[i]
		var p2 = points[(i + 1) % points.size()]
		if _is_inner_edge(p1, p2, board_w, board_h):
			var edge_len = p1.distance_to(p2)
			if edge_len > best_length:
				best_length = edge_len
				best_p1 = p1
				best_p2 = p2
				found_inner = true

	if not found_inner or best_length < 10.0:
		return

	# Calculate the zone depth in inches from this inner edge
	var zone_depth_inches = _estimate_zone_depth(points, best_p1, best_p2, board_w, board_h)
	if zone_depth_inches <= 0:
		return

	var label_text = "%d\"" % int(round(zone_depth_inches))

	# Position label at midpoint of the inner edge, offset toward no-man's-land
	var midpoint = (best_p1 + best_p2) / 2.0
	var direction = (best_p2 - best_p1).normalized()
	var perpendicular = Vector2(-direction.y, direction.x)

	# Determine which side of the edge is "outward" (toward no-man's-land)
	# by checking which direction moves away from the polygon center
	var center = _polygon_center(points)
	var outward = perpendicular
	if midpoint.distance_to(center) > (midpoint + perpendicular * 10).distance_to(center):
		outward = -perpendicular

	var label_pos = midpoint + outward * 16

	# Draw label with background
	var text_size = default_font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var bg_rect = Rect2(
		label_pos - LABEL_BG_PADDING - Vector2(text_size.x / 2.0, text_size.y),
		text_size + LABEL_BG_PADDING * 2
	)

	var bg_color = Color(LABEL_BG_COLOR.r, LABEL_BG_COLOR.g, LABEL_BG_COLOR.b, LABEL_BG_COLOR.a * pulse_alpha)
	draw_rect(bg_rect, bg_color, true)

	var text_color = Color(border_color.r, border_color.g, border_color.b, pulse_alpha)
	draw_string(
		default_font,
		label_pos - Vector2(text_size.x / 2.0, 0),
		label_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE,
		text_color
	)

func _estimate_zone_depth(points: PackedVector2Array, edge_p1: Vector2, edge_p2: Vector2, board_w: float, board_h: float) -> float:
	# Estimate the zone depth by finding the maximum perpendicular distance
	# from any board-boundary edge to this inner edge
	var edge_dir = (edge_p2 - edge_p1).normalized()
	var edge_normal = Vector2(-edge_dir.y, edge_dir.x)

	# Project all polygon points onto the edge normal to find the depth
	var min_proj: float = INF
	var max_proj: float = -INF
	for p in points:
		var proj = (p - edge_p1).dot(edge_normal)
		min_proj = min(min_proj, proj)
		max_proj = max(max_proj, proj)

	var depth_px = max_proj - min_proj
	if Measurement:
		return Measurement.px_to_inches(depth_px)
	return depth_px / 40.0

func _polygon_center(points: PackedVector2Array) -> Vector2:
	var center = Vector2.ZERO
	for p in points:
		center += p
	return center / float(points.size())

func set_active(active: bool) -> void:
	is_active = active
	if not is_active:
		set_process(false)
	else:
		set_process(true)
	queue_redraw()
