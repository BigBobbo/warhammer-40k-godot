extends Node2D

# InfiltratorExclusionVisual - Shows the 9" exclusion boundary around the enemy
# deployment zone when deploying Infiltrator units. Draws a dashed line representing
# the closest edge where Infiltrators can legally be placed.

const PX_PER_INCH: float = 40.0
const EXCLUSION_DISTANCE_INCHES: float = 9.0

# Dashed line style
const DASH_LENGTH: float = 12.0
const GAP_LENGTH: float = 8.0
const LINE_WIDTH: float = 2.5
const MARCH_SPEED: float = 25.0  # Marching ants animation speed

# Colors
const LINE_COLOR: Color = Color(1.0, 0.4, 0.3, 0.8)  # Orange-red for exclusion
const GLOW_COLOR: Color = Color(1.0, 0.4, 0.3, 0.15)
const GLOW_WIDTH: float = 8.0
const LABEL_BG_COLOR: Color = Color(0.1, 0.08, 0.05, 0.85)
const LABEL_BG_PADDING: Vector2 = Vector2(6, 3)
const FONT_SIZE: int = 13

# Computed exclusion boundary polygons (in pixels, clipped to board)
var _exclusion_polygons: Array = []  # Array of PackedVector2Array
var _pulse_time: float = 0.0
var _is_active: bool = false
var _default_font: Font = null

func _ready() -> void:
	z_index = -4  # Just above deployment zones (-5)
	_default_font = FactionPalettes.FONT_RAJDHANI_SEMIBOLD
	set_process(false)

func show_exclusion(enemy_zone_poly_inches: Array) -> void:
	"""Compute and show the 9-inch exclusion boundary around the enemy deployment zone."""
	_exclusion_polygons.clear()

	if enemy_zone_poly_inches.size() < 3:
		return

	# Convert enemy zone to pixels
	var enemy_poly_px = PackedVector2Array()
	for coord in enemy_zone_poly_inches:
		if coord is Dictionary and coord.has("x") and coord.has("y"):
			enemy_poly_px.append(Vector2(coord.x * PX_PER_INCH, coord.y * PX_PER_INCH))

	if enemy_poly_px.size() < 3:
		return

	var offset_px = EXCLUSION_DISTANCE_INCHES * PX_PER_INCH

	# Use Geometry2D.offset_polygon to expand outward by 9 inches
	# Positive delta = outward expansion (Godot uses CCW winding for outward)
	# Try both directions and pick the one that's larger (outward expansion)
	var expanded_pos = Geometry2D.offset_polygon(enemy_poly_px, offset_px)
	var expanded_neg = Geometry2D.offset_polygon(enemy_poly_px, -offset_px)

	var expanded: Array
	if expanded_pos.size() > 0 and expanded_neg.size() > 0:
		# Pick whichever result is the outward expansion (larger area)
		var area_pos = _polygon_area(expanded_pos[0]) if expanded_pos.size() > 0 else 0.0
		var area_neg = _polygon_area(expanded_neg[0]) if expanded_neg.size() > 0 else 0.0
		var area_orig = _polygon_area(enemy_poly_px)
		if abs(area_pos) > abs(area_orig):
			expanded = expanded_pos
		elif abs(area_neg) > abs(area_orig):
			expanded = expanded_neg
		else:
			expanded = expanded_pos
	elif expanded_pos.size() > 0:
		expanded = expanded_pos
	elif expanded_neg.size() > 0:
		expanded = expanded_neg
	else:
		return

	# Clip each expanded polygon to the board boundaries
	var board_width_px = 44.0 * PX_PER_INCH
	var board_height_px = 60.0 * PX_PER_INCH
	var board_rect = PackedVector2Array([
		Vector2(0, 0),
		Vector2(board_width_px, 0),
		Vector2(board_width_px, board_height_px),
		Vector2(0, board_height_px)
	])

	for poly in expanded:
		var clipped = Geometry2D.intersect_polygons(poly, board_rect)
		for clipped_poly in clipped:
			if clipped_poly.size() >= 3:
				_exclusion_polygons.append(clipped_poly)

	_is_active = true
	_pulse_time = 0.0
	set_process(true)
	visible = true
	queue_redraw()
	print("[InfiltratorExclusionVisual] Showing 9\" exclusion boundary (%d polygons)" % _exclusion_polygons.size())

func hide_exclusion() -> void:
	"""Hide the exclusion boundary."""
	_is_active = false
	_exclusion_polygons.clear()
	set_process(false)
	visible = false
	queue_redraw()

func _process(delta: float) -> void:
	if _is_active:
		_pulse_time += delta
		queue_redraw()

func _draw() -> void:
	if not _is_active or _exclusion_polygons.is_empty():
		return

	# Pulse alpha for breathing effect
	var pulse_alpha = 0.7 + 0.3 * (1.0 + sin(_pulse_time * 2.0)) / 2.0
	var march_offset = fmod(_pulse_time * MARCH_SPEED, DASH_LENGTH + GAP_LENGTH)

	# Get board dimensions for detecting board-edge segments
	var board_width_px = 44.0 * PX_PER_INCH
	var board_height_px = 60.0 * PX_PER_INCH
	var edge_threshold = 5.0  # pixels

	for poly in _exclusion_polygons:
		if poly.size() < 3:
			continue

		# Draw each edge of the exclusion polygon
		for i in range(poly.size()):
			var p1 = poly[i]
			var p2 = poly[(i + 1) % poly.size()]

			# Skip edges that lie on the board boundary (they aren't the exclusion line)
			if _is_board_edge(p1, p2, board_width_px, board_height_px, edge_threshold):
				continue

			# Draw glow behind the dashed line
			var glow_color = Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, GLOW_COLOR.a * pulse_alpha)
			draw_line(p1, p2, glow_color, GLOW_WIDTH, true)

			# Draw dashed line
			_draw_dashed_line(p1, p2, pulse_alpha, march_offset)

		# Draw "9\" exclusion" label on the longest non-board edge
		_draw_exclusion_label(poly, board_width_px, board_height_px, edge_threshold, pulse_alpha)

func _is_board_edge(p1: Vector2, p2: Vector2, board_w: float, board_h: float, threshold: float) -> bool:
	"""Check if both points of an edge lie on the same board boundary."""
	var on_left = abs(p1.x) < threshold and abs(p2.x) < threshold
	var on_right = abs(p1.x - board_w) < threshold and abs(p2.x - board_w) < threshold
	var on_top = abs(p1.y) < threshold and abs(p2.y) < threshold
	var on_bottom = abs(p1.y - board_h) < threshold and abs(p2.y - board_h) < threshold
	return on_left or on_right or on_top or on_bottom

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

func _draw_exclusion_label(poly: PackedVector2Array, board_w: float, board_h: float, threshold: float, pulse_alpha: float) -> void:
	"""Draw a '9\" limit' label on the longest non-board edge."""
	if not _default_font:
		return

	var best_length: float = 0.0
	var best_p1: Vector2 = Vector2.ZERO
	var best_p2: Vector2 = Vector2.ZERO
	var found: bool = false

	for i in range(poly.size()):
		var p1 = poly[i]
		var p2 = poly[(i + 1) % poly.size()]
		if _is_board_edge(p1, p2, board_w, board_h, threshold):
			continue
		var edge_len = p1.distance_to(p2)
		if edge_len > best_length:
			best_length = edge_len
			best_p1 = p1
			best_p2 = p2
			found = true

	if not found or best_length < 40.0:
		return

	var label_text = "9\" exclusion"
	var midpoint = (best_p1 + best_p2) / 2.0

	# Offset label slightly away from the enemy zone (toward valid placement area)
	var direction = (best_p2 - best_p1).normalized()
	var perpendicular = Vector2(-direction.y, direction.x)

	# Determine outward direction (away from polygon center)
	var center = Vector2.ZERO
	for p in poly:
		center += p
	center /= float(poly.size())

	var outward = perpendicular
	if midpoint.distance_to(center) > (midpoint + perpendicular * 10).distance_to(center):
		outward = -perpendicular

	var label_pos = midpoint + outward * 14

	var text_size = _default_font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var bg_rect = Rect2(
		label_pos - LABEL_BG_PADDING - Vector2(text_size.x / 2.0, text_size.y),
		text_size + LABEL_BG_PADDING * 2
	)

	var bg_color = Color(LABEL_BG_COLOR.r, LABEL_BG_COLOR.g, LABEL_BG_COLOR.b, LABEL_BG_COLOR.a * pulse_alpha)
	draw_rect(bg_rect, bg_color, true)

	var text_color = Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, pulse_alpha)
	draw_string(
		_default_font,
		label_pos - Vector2(text_size.x / 2.0, 0),
		label_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE,
		text_color
	)

func _polygon_area(poly: PackedVector2Array) -> float:
	"""Calculate signed area of a polygon using the shoelace formula."""
	var area: float = 0.0
	var n = poly.size()
	for i in range(n):
		var j = (i + 1) % n
		area += poly[i].x * poly[j].y
		area -= poly[j].x * poly[i].y
	return area / 2.0
