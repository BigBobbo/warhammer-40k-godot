extends Polygon2D

# DeploymentZoneVisual - Enhanced deployment zone rendering with edge highlighting
# T5-V14: Pulsing animated dashed border, glow layers on inner edges,
# and zone depth labels for clearer boundary visibility.
# P3-48: Diagonal hatching and military-style corner brackets for zone theming.
# Follows sine-wave animation pattern from EngagementRangeVisual.gd
# and dashed line pattern from PileInMovementVisual.gd / RangeCircle.gd

var is_active: bool = false
var border_color: Color = Color.WHITE
var border_width: float = 3.0
var player_number: int = 0  # 1 or 2, set by Main.gd

# P3-52: Dimming state — when true, reduces animation intensity and glow for opponent zone
var is_dimmed: bool = false
const DIMMED_PULSE_SCALE: float = 0.3  # Reduce pulse amplitude when dimmed
const DIMMED_GLOW_SCALE: float = 0.3  # Reduce glow intensity when dimmed
const DIMMED_HATCH_SCALE: float = 0.4  # Reduce hatching visibility when dimmed
const DIMMED_BRACKET_SCALE: float = 0.3  # Reduce bracket visibility when dimmed

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

# P3-48: Diagonal hatching constants
const HATCH_SPACING: float = 40.0  # Distance between hatch lines in pixels
const HATCH_LINE_WIDTH: float = 1.0
const HATCH_ALPHA: float = 0.08  # Very subtle so it doesn't overwhelm the board
const HATCH_DASH_LENGTH: float = 10.0
const HATCH_GAP_LENGTH: float = 6.0

# P3-48: Military corner bracket constants
const BRACKET_LENGTH: float = 16.0  # Length of each bracket arm
const BRACKET_WIDTH: float = 2.5
const BRACKET_ALPHA: float = 0.6
const BRACKET_INSET: float = 6.0  # Pixels inward from the corner point

var default_font: Font = null

func _ready() -> void:
	z_index = -5
	default_font = FactionPalettes.FONT_RAJDHANI_SEMIBOLD

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
	# P3-52: Reduce pulse amplitude when dimmed
	var pulse_range = 0.2 * (DIMMED_PULSE_SCALE if is_dimmed else 1.0)
	var pulse_alpha = (0.8 - pulse_range) + pulse_range * (1.0 + sin(_pulse_time * 2.5)) / 2.0
	if is_dimmed:
		pulse_alpha *= 0.6  # Further reduce overall alpha when dimmed

	# Marching ants offset
	var march_offset = fmod(_pulse_time * MARCH_SPEED, DASH_LENGTH + GAP_LENGTH)

	# Get board dimensions for inner/outer edge detection
	var board_width_px = Measurement.inches_to_px(44.0) if Measurement else 44.0 * 40
	var board_height_px = Measurement.inches_to_px(60.0) if Measurement else 60.0 * 40

	# P3-48: Draw diagonal hatching pattern inside the zone (drawn first, behind edges)
	_draw_diagonal_hatching(points, pulse_alpha)

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

	# P3-48: Draw military-style corner brackets on inner corners (replaces simple circle markers)
	_draw_corner_brackets(points, board_width_px, board_height_px, pulse_alpha)

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
	# P3-52: Scale glow intensity down when dimmed
	var glow_scale = DIMMED_GLOW_SCALE if is_dimmed else 1.0

	# Outer glow layer (wider, more transparent)
	var glow_outer = Color(border_color.r, border_color.g, border_color.b, GLOW_ALPHA_OUTER * pulse_alpha * glow_scale)
	draw_line(p1, p2, glow_outer, GLOW_WIDTH_OUTER, true)

	# Inner glow layer (narrower, slightly more visible)
	var glow_inner = Color(border_color.r, border_color.g, border_color.b, GLOW_ALPHA_INNER * pulse_alpha * glow_scale)
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

func _draw_corner_brackets(points: PackedVector2Array, board_w: float, board_h: float, pulse_alpha: float) -> void:
	# P3-48: Draw military-style L-shaped brackets at corners where inner edges meet
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
			# P3-52: Scale bracket visibility down when dimmed
			var bracket_scale = DIMMED_BRACKET_SCALE if is_dimmed else 1.0
			var bracket_color = Color(border_color.r, border_color.g, border_color.b, BRACKET_ALPHA * pulse_alpha * bracket_scale)

			# Compute direction vectors along each edge from this corner
			var dir_to_prev = (p_prev - p_curr).normalized()
			var dir_to_next = (p_next - p_curr).normalized()

			# Inset the bracket slightly into the polygon so it doesn't overlap the border
			var inset_dir = (dir_to_prev + dir_to_next).normalized()
			if inset_dir.length_squared() < 0.01:
				# Edges are nearly parallel — fallback to perpendicular
				inset_dir = Vector2(-dir_to_prev.y, dir_to_prev.x)
			var corner_pt = p_curr + inset_dir * BRACKET_INSET

			# Draw L-bracket: two arms extending along the edge directions
			var arm1_end = corner_pt + dir_to_prev * BRACKET_LENGTH
			var arm2_end = corner_pt + dir_to_next * BRACKET_LENGTH
			draw_line(arm1_end, corner_pt, bracket_color, BRACKET_WIDTH, true)
			draw_line(corner_pt, arm2_end, bracket_color, BRACKET_WIDTH, true)

func _draw_diagonal_hatching(points: PackedVector2Array, pulse_alpha: float) -> void:
	# P3-48: Draw subtle diagonal hatching lines (45 degrees) clipped to the zone polygon.
	# Uses Geometry2D.intersect_polyline_with_polygon to handle arbitrary zone shapes.
	if points.size() < 3:
		return

	# Compute the axis-aligned bounding box of the polygon
	var min_pt = Vector2(INF, INF)
	var max_pt = Vector2(-INF, -INF)
	for p in points:
		min_pt.x = min(min_pt.x, p.x)
		min_pt.y = min(min_pt.y, p.y)
		max_pt.x = max(max_pt.x, p.x)
		max_pt.y = max(max_pt.y, p.y)

	# P3-52: Scale hatching down when dimmed
	var hatch_scale = DIMMED_HATCH_SCALE if is_dimmed else 1.0
	var hatch_color = Color(border_color.r, border_color.g, border_color.b, HATCH_ALPHA * pulse_alpha * hatch_scale)

	# Generate 45-degree lines sweeping across the bounding box.
	# For a 45° line (top-left to bottom-right), the diagonal offset is x + y = c.
	# We sweep c from min(x+y) to max(x+y) with HATCH_SPACING steps.
	var c_min = min_pt.x + min_pt.y
	var c_max = max_pt.x + max_pt.y

	var c = c_min
	while c <= c_max:
		# Line equation: x + y = c, parameterized along the diagonal
		# Intersect with the bounding box to get the line segment endpoints
		# x = c - y, so when y = min_pt.y -> x = c - min_pt.y
		#            and when y = max_pt.y -> x = c - max_pt.y
		var x1 = c - min_pt.y
		var y1 = min_pt.y
		var x2 = c - max_pt.y
		var y2 = max_pt.y

		# Clip to horizontal bounding box bounds
		if x1 > max_pt.x:
			y1 = c - max_pt.x
			x1 = max_pt.x
		if x1 < min_pt.x:
			y1 = c - min_pt.x
			x1 = min_pt.x
		if x2 > max_pt.x:
			y2 = c - max_pt.x
			x2 = max_pt.x
		if x2 < min_pt.x:
			y2 = c - min_pt.x
			x2 = min_pt.x

		# Create the line as a polyline and clip to the polygon
		var line = PackedVector2Array([Vector2(x1, y1), Vector2(x2, y2)])
		if line[0].distance_to(line[1]) < 1.0:
			c += HATCH_SPACING
			continue

		var clipped_segments = Geometry2D.intersect_polyline_with_polygon(line, points)

		for segment in clipped_segments:
			if segment.size() < 2:
				continue
			# Draw each clipped segment as a dashed line for a cleaner military look
			_draw_hatch_dashed_segment(segment[0], segment[segment.size() - 1], hatch_color)

		c += HATCH_SPACING

func _draw_hatch_dashed_segment(p1: Vector2, p2: Vector2, color: Color) -> void:
	# Draw a dashed line segment for hatching (no animation, static pattern)
	var direction = (p2 - p1).normalized()
	var total_length = p1.distance_to(p2)

	if total_length < 2.0:
		draw_line(p1, p2, color, HATCH_LINE_WIDTH, true)
		return

	var pos: float = 0.0
	var segment_length = HATCH_DASH_LENGTH + HATCH_GAP_LENGTH
	while pos < total_length:
		var dash_end = min(pos + HATCH_DASH_LENGTH, total_length)
		var start_pt = p1 + direction * pos
		var end_pt = p1 + direction * dash_end
		draw_line(start_pt, end_pt, color, HATCH_LINE_WIDTH, true)
		pos += segment_length

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
