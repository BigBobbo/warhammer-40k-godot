extends Node2D

# DeepStrikeExclusionVisual - Shows a 9" exclusion bubble around every enemy model
# when deploying units from Deep Strike or Strategic Reserves. Models cannot be
# placed within 9" (edge-to-edge) of any enemy model.

const PX_PER_INCH: float = 40.0
const EXCLUSION_DISTANCE_INCHES: float = 9.0
const CIRCLE_SEGMENTS: int = 48  # Smooth circles

# Dashed line style (matches InfiltratorExclusionVisual)
const DASH_LENGTH: float = 12.0
const GAP_LENGTH: float = 8.0
const LINE_WIDTH: float = 2.5
const MARCH_SPEED: float = 25.0

# Colors - orange-red to match existing exclusion visuals
const LINE_COLOR: Color = Color(1.0, 0.4, 0.3, 0.8)
const GLOW_COLOR: Color = Color(1.0, 0.4, 0.3, 0.15)
const GLOW_WIDTH: float = 8.0
const FILL_COLOR: Color = Color(1.0, 0.3, 0.2, 0.06)
const LABEL_BG_COLOR: Color = Color(0.1, 0.08, 0.05, 0.85)
const LABEL_BG_PADDING: Vector2 = Vector2(6, 3)
const FONT_SIZE: int = 13

# Internal state
var _exclusion_circles: Array = []  # Array of { center: Vector2, radius_px: float }
var _merged_polygons: Array = []  # One clipped polygon per connected enemy cluster
var _pulse_time: float = 0.0
var _is_active: bool = false
var _default_font: Font = null

func _ready() -> void:
	z_index = -4  # Same layer as InfiltratorExclusionVisual
	_default_font = FactionPalettes.FONT_RAJDHANI_SEMIBOLD
	set_process(false)

func show_exclusion(enemy_positions: Array) -> void:
	"""Show 9-inch exclusion bubbles around all enemy model positions.
	enemy_positions: Array of { x: float, y: float, base_mm: int } in pixels."""
	_exclusion_circles.clear()
	_merged_polygons.clear()

	if enemy_positions.is_empty():
		return

	# Build circle data for each enemy model
	# The 9" exclusion is edge-to-edge, so the bubble radius = 9" + enemy base radius
	for enemy in enemy_positions:
		var center = Vector2(enemy.x, enemy.y)
		var base_radius_inches = (enemy.base_mm / 2.0) / 25.4
		var total_radius_inches = EXCLUSION_DISTANCE_INCHES + base_radius_inches
		var radius_px = total_radius_inches * PX_PER_INCH
		_exclusion_circles.append({ "center": center, "radius_px": radius_px })

	# Merge all circles into a single polygon for efficient rendering
	_build_merged_polygon()

	_is_active = true
	_pulse_time = 0.0
	set_process(true)
	visible = true
	queue_redraw()
	print("[DeepStrikeExclusionVisual] Showing 9\" exclusion bubbles around %d enemy models (%d polygons)" % [enemy_positions.size(), _merged_polygons.size()])

func hide_exclusion() -> void:
	"""Hide the exclusion bubbles."""
	_is_active = false
	_exclusion_circles.clear()
	_merged_polygons.clear()
	set_process(false)
	visible = false
	queue_redraw()

func _build_merged_polygon() -> void:
	"""Merge exclusion circles into polygon(s) clipped to the board.

	Enemy models frequently sit in several physically-separate clusters (e.g. a
	block at the top of the board and another at the bottom). Each cluster must
	produce its own exclusion polygon. The previous implementation progressively
	merged every circle into one running polygon and, after each pairwise merge,
	kept only the LARGEST resulting polygon — so any circle that did not touch the
	largest connected blob was silently dropped and its exclusion zone never drew.
	We now group circles into connected clusters first and merge each cluster on
	its own, so every enemy group gets an exclusion zone."""
	if _exclusion_circles.is_empty():
		return

	var board_width_px = 44.0 * PX_PER_INCH
	var board_height_px = 60.0 * PX_PER_INCH
	var board_rect = PackedVector2Array([
		Vector2(0, 0),
		Vector2(board_width_px, 0),
		Vector2(board_width_px, board_height_px),
		Vector2(0, board_height_px)
	])

	# Group circles into connected clusters (bubbles that overlap belong together),
	# then merge each cluster independently and clip it to the board.
	var clusters = _group_circles_into_clusters()
	for cluster in clusters:
		var merged = _merge_cluster(cluster)
		if merged.size() < 3:
			continue
		var clipped = Geometry2D.intersect_polygons(merged, board_rect)
		for poly in clipped:
			if poly.size() >= 3:
				_merged_polygons.append(poly)

func _group_circles_into_clusters() -> Array:
	"""Union-find grouping of exclusion circles whose bubbles overlap.
	Returns an Array of clusters; each cluster is an Array of circle dictionaries."""
	var n = _exclusion_circles.size()
	var parent: Array = []
	parent.resize(n)
	for i in range(n):
		parent[i] = i

	# Two circles are connected when their bubbles overlap (edge distance < 0).
	for i in range(n):
		var ci = _exclusion_circles[i]
		for j in range(i + 1, n):
			var cj = _exclusion_circles[j]
			if ci.center.distance_to(cj.center) < ci.radius_px + cj.radius_px:
				_union(parent, i, j)

	var groups: Dictionary = {}
	for i in range(n):
		var root = _find(parent, i)
		if not groups.has(root):
			groups[root] = []
		groups[root].append(_exclusion_circles[i])
	return groups.values()

func _find(parent: Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]  # path halving
		i = parent[i]
	return i

func _union(parent: Array, a: int, b: int) -> void:
	var ra = _find(parent, a)
	var rb = _find(parent, b)
	if ra != rb:
		parent[rb] = ra

func _merge_cluster(cluster: Array) -> PackedVector2Array:
	"""Merge all circles in a connected cluster into its outer boundary polygon.

	Circles are folded in connectivity order (only a circle that overlaps something
	already merged is folded in), so the accumulating shape always stays one connected
	blob and _largest_polygon reliably returns the outer boundary ring.

	KNOWN LIMITATION: if a cluster forms a ring of enemies with an uncovered gap in the
	middle (a legal deep-strike pocket >9\" from every model), that gap is an interior
	'hole' ring in the union. We keep only the outer boundary here, and the fill in _draw
	uses draw_colored_polygon which cannot express holes, so such a pocket is drawn as
	excluded. This is a rare, purely-cosmetic over-exclusion — the authoritative legality
	check is DeploymentController._validate_reinforcement_position, not this overlay — so
	it never permits or blocks an actual placement. Punching the hole out would require
	hole-aware triangulation of the fill and is deliberately out of scope."""
	if cluster.is_empty():
		return PackedVector2Array()

	var merged: PackedVector2Array = _circle_to_polygon(cluster[0].center, cluster[0].radius_px)
	var merged_circles: Array = [cluster[0]]
	var pending: Array = []
	for i in range(1, cluster.size()):
		pending.append(cluster[i])

	# Repeatedly fold in a pending circle that overlaps something already merged.
	# Because the cluster is connected, every circle is eventually reachable.
	var progress = true
	while not pending.is_empty() and progress:
		progress = false
		var i = 0
		while i < pending.size():
			var pc = pending[i]
			var overlaps = false
			for mc in merged_circles:
				if pc.center.distance_to(mc.center) < pc.radius_px + mc.radius_px:
					overlaps = true
					break
			if overlaps:
				var circle_poly = _circle_to_polygon(pc.center, pc.radius_px)
				var union_result = Geometry2D.merge_polygons(merged, circle_poly)
				merged = _largest_polygon(union_result)
				merged_circles.append(pc)
				pending.remove_at(i)
				progress = true
			else:
				i += 1

	return merged

func _largest_polygon(polys: Array) -> PackedVector2Array:
	"""Return the polygon with the greatest absolute area (the outer ring)."""
	var largest := PackedVector2Array()
	var largest_area := -1.0
	for poly in polys:
		var area = abs(_polygon_area(poly))
		if area > largest_area:
			largest_area = area
			largest = poly
	return largest

func _circle_to_polygon(center: Vector2, radius: float) -> PackedVector2Array:
	"""Convert a circle to a polygon approximation.

	The polygon is CIRCUMSCRIBED (vertices pushed out by 1/cos(PI/segments)) so it
	fully contains the true circle instead of being inscribed inside it. This matters
	because clustering and the fold-in test (_group_circles_into_clusters / _merge_cluster)
	decide overlap from the TRUE circle radii, while the actual union is computed on these
	polygons. An inscribed polygon can fall a fraction of a pixel short of the true circle,
	so two barely-overlapping bubbles could pass the radius test yet produce disjoint
	polygons — which merge_polygons would then leave unmerged and _largest_polygon would
	silently drop. Circumscribing guarantees polygon overlap whenever the circles overlap.
	The cost is enlarging every drawn bubble by ~0.2% (about 1px at these radii)."""
	var effective_radius = radius / cos(PI / float(CIRCLE_SEGMENTS))
	var points = PackedVector2Array()
	for i in range(CIRCLE_SEGMENTS):
		var angle = TAU * float(i) / float(CIRCLE_SEGMENTS)
		points.append(center + Vector2(cos(angle), sin(angle)) * effective_radius)
	return points

func _process(delta: float) -> void:
	if _is_active:
		_pulse_time += delta
		queue_redraw()

func _draw() -> void:
	if not _is_active or _merged_polygons.is_empty():
		return

	var pulse_alpha = 0.7 + 0.3 * (1.0 + sin(_pulse_time * 2.0)) / 2.0
	var march_offset = fmod(_pulse_time * MARCH_SPEED, DASH_LENGTH + GAP_LENGTH)

	var board_width_px = 44.0 * PX_PER_INCH
	var board_height_px = 60.0 * PX_PER_INCH
	var edge_threshold = 5.0

	for poly in _merged_polygons:
		if poly.size() < 3:
			continue

		# Draw semi-transparent fill
		var fill = Color(FILL_COLOR.r, FILL_COLOR.g, FILL_COLOR.b, FILL_COLOR.a * pulse_alpha)
		draw_colored_polygon(poly, fill)

		# Draw each edge
		for i in range(poly.size()):
			var p1 = poly[i]
			var p2 = poly[(i + 1) % poly.size()]

			# Skip edges on the board boundary
			if _is_board_edge(p1, p2, board_width_px, board_height_px, edge_threshold):
				continue

			# Draw glow
			var glow_color = Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, GLOW_COLOR.a * pulse_alpha)
			draw_line(p1, p2, glow_color, GLOW_WIDTH, true)

			# Draw dashed line
			_draw_dashed_line(p1, p2, pulse_alpha, march_offset)

	# Label every disjoint exclusion zone so each enemy cluster is annotated.
	for poly in _merged_polygons:
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
	"""Draw a '9\" exclusion' label on the longest non-board edge."""
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

	var direction = (best_p2 - best_p1).normalized()
	var perpendicular = Vector2(-direction.y, direction.x)

	# Offset label outward from polygon center
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
