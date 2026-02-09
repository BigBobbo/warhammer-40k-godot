extends RefCounted
class_name TokenDrawUtils

# Static utility class with shared drawing helpers for enhanced token rendering.
# All methods are static so they can be called without instantiation.


static func draw_gradient_circle(canvas: CanvasItem, center: Vector2, radius: float, base_color: Color) -> void:
	# 4 concentric circles: darker edge to lighter center
	var layers = 4
	for i in range(layers):
		var t = float(i) / float(layers - 1)  # 0.0 (outer) to 1.0 (inner)
		var layer_radius = radius * (1.0 - t * 0.7)  # Outer ring to 30% radius
		var layer_color = base_color.lerp(base_color.lightened(0.25), t)
		canvas.draw_circle(center, layer_radius, layer_color)


static func draw_gradient_polygon(canvas: CanvasItem, points: PackedVector2Array, base_color: Color) -> void:
	# Inset polygon layers for rectangular/oval gradient effect
	var center = Vector2.ZERO
	for p in points:
		center += p
	center /= float(points.size())

	var layers = 4
	for i in range(layers):
		var t = float(i) / float(layers - 1)
		var inset_factor = 1.0 - t * 0.5  # Shrink toward center
		var layer_color = base_color.lerp(base_color.lightened(0.25), t)
		var inset_points = PackedVector2Array()
		for p in points:
			inset_points.append(center + (p - center) * inset_factor)
		canvas.draw_colored_polygon(inset_points, layer_color)


static func draw_metallic_rim(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	# Double-ring raised edge effect for circles
	# Outer glow ring (wider, semi-transparent)
	var glow_color = Color(color.r, color.g, color.b, 0.3)
	canvas.draw_arc(center, radius + 1.5, 0, TAU, 64, glow_color, 4.0)
	# Inner crisp ring
	canvas.draw_arc(center, radius, 0, TAU, 64, color, 2.5)
	# Highlight arc on top edge (simulates light reflection)
	var highlight = color.lightened(0.4)
	highlight.a = 0.5
	canvas.draw_arc(center, radius - 1.0, -PI * 0.8, -PI * 0.2, 16, highlight, 1.5)


static func draw_metallic_rim_polygon(canvas: CanvasItem, points: PackedVector2Array, color: Color) -> void:
	# Double-ring raised edge effect for non-circular bases
	var center = Vector2.ZERO
	for p in points:
		center += p
	center /= float(points.size())

	# Outer glow (slightly expanded polygon)
	var glow_color = Color(color.r, color.g, color.b, 0.3)
	var outer_points = PackedVector2Array()
	for p in points:
		var dir = (p - center).normalized()
		outer_points.append(p + dir * 1.5)
	outer_points.append(outer_points[0])
	canvas.draw_polyline(outer_points, glow_color, 4.0)

	# Inner crisp border
	var closed_points = PackedVector2Array()
	for p in points:
		closed_points.append(p)
	closed_points.append(points[0])
	canvas.draw_polyline(closed_points, color, 2.5)

	# Highlight on top edge
	var highlight = color.lightened(0.4)
	highlight.a = 0.5
	# Draw highlight on top segment(s) only
	if points.size() >= 2:
		canvas.draw_line(points[0], points[1], highlight, 1.5)


static func draw_wound_pips(canvas: CanvasItem, center: Vector2, radius: float, total_wounds: int, current_wounds: int) -> void:
	# Colored dots around inner ring showing wound status
	if total_wounds <= 1:
		return

	var pip_radius = max(2.5, radius * 0.06)
	var ring_radius = radius * 0.78
	# Cap display to 12 pips max for readability
	var display_wounds = min(total_wounds, 12)

	for i in range(display_wounds):
		# Distribute evenly around bottom half of circle
		var angle = PI * 0.3 + (PI * 1.4) * (float(i) / float(display_wounds))
		var pip_pos = center + Vector2(cos(angle), sin(angle)) * ring_radius

		if i < current_wounds:
			# Remaining wound: bright green
			canvas.draw_circle(pip_pos, pip_radius, Color(0.3, 0.85, 0.3, 0.9))
		else:
			# Lost wound: dark red
			canvas.draw_circle(pip_pos, pip_radius, Color(0.6, 0.15, 0.1, 0.7))

	# If total > 12, draw a small number indicator
	if total_wounds > 12:
		var font = ThemeDB.fallback_font
		var wound_text = "%d/%d" % [current_wounds, total_wounds]
		var text_size = font.get_string_size(wound_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
		var text_pos = center + Vector2(-text_size.x / 2, radius * 0.85)
		canvas.draw_string(font, text_pos + Vector2(1, 1), wound_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0, 0, 0, 0.7))
		canvas.draw_string(font, text_pos, wound_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.9, 0.9, 0.3, 0.9))


static func draw_status_tick(canvas: CanvasItem, center: Vector2, radius: float, flags: Dictionary) -> void:
	# Small colored bar at base bottom showing action state
	var tick_width = radius * 0.5
	var tick_height = max(3.0, radius * 0.08)
	var tick_y = center.y + radius + 3.0

	# Determine color from flags
	var tick_color = Color(0.5, 0.5, 0.5, 0.0)  # Invisible by default

	if flags.get("has_fought", false):
		tick_color = Color(0.85, 0.2, 0.2, 0.9)  # Red - fought
	elif flags.get("has_charged", false) or flags.get("charged_this_turn", false):
		tick_color = Color(0.9, 0.5, 0.1, 0.9)  # Orange - charged
	elif flags.get("has_shot", false):
		tick_color = Color(0.2, 0.6, 0.9, 0.9)  # Blue - shot
	elif flags.get("moved", false) or flags.get("advanced", false) or flags.get("fell_back", false):
		tick_color = Color(0.3, 0.8, 0.3, 0.9)  # Green - moved
	else:
		return  # No action taken, don't draw anything

	var rect = Rect2(
		center.x - tick_width / 2,
		tick_y,
		tick_width,
		tick_height
	)
	canvas.draw_rect(rect, tick_color)


static func draw_leader_chevron(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	# Small chevron/crown marker above token for CHARACTER models
	var chevron_y = center.y - radius - 6.0
	var size = max(4.0, radius * 0.2)

	var chevron = PackedVector2Array([
		Vector2(center.x - size, chevron_y + size * 0.5),
		Vector2(center.x - size * 0.5, chevron_y - size * 0.3),
		Vector2(center.x, chevron_y + size * 0.2),
		Vector2(center.x + size * 0.5, chevron_y - size * 0.3),
		Vector2(center.x + size, chevron_y + size * 0.5),
	])
	canvas.draw_polyline(chevron, color, 2.0)


static func draw_faction_ring(canvas: CanvasItem, center: Vector2, radius: float, faction_color: Color) -> void:
	# Thin ring at 70% radius in faction accent color
	canvas.draw_arc(center, radius * 0.7, 0, TAU, 48, faction_color, 1.5)


static func draw_faction_ring_polygon(canvas: CanvasItem, points: PackedVector2Array, faction_color: Color) -> void:
	# Inset faction ring for non-circular bases
	var center = Vector2.ZERO
	for p in points:
		center += p
	center /= float(points.size())

	var ring_points = PackedVector2Array()
	for p in points:
		ring_points.append(center + (p - center) * 0.7)
	ring_points.append(ring_points[0])
	canvas.draw_polyline(ring_points, faction_color, 1.5)


# --- Enhanced silhouettes ---

static func draw_infantry_silhouette(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	# Helmet profile with visor slit + shoulder pad
	var s = radius * 0.45

	# Helmet (rounded shape)
	canvas.draw_circle(center + Vector2(0, -s * 0.55), s * 0.32, color)
	# Visor slit (dark horizontal line across helmet)
	var visor_color = Color(color.r * 0.3, color.g * 0.3, color.b * 0.3, color.a * 0.8)
	canvas.draw_line(
		center + Vector2(-s * 0.2, -s * 0.58),
		center + Vector2(s * 0.15, -s * 0.58),
		visor_color, 2.0
	)

	# Shoulder pad (right side, angled trapezoid)
	var shoulder = PackedVector2Array([
		center + Vector2(s * 0.15, -s * 0.4),
		center + Vector2(s * 0.55, -s * 0.45),
		center + Vector2(s * 0.55, -s * 0.15),
		center + Vector2(s * 0.2, -s * 0.1),
	])
	canvas.draw_colored_polygon(shoulder, color)

	# Torso (tapered body)
	var body = PackedVector2Array([
		center + Vector2(-s * 0.3, -s * 0.25),
		center + Vector2(s * 0.15, -s * 0.25),
		center + Vector2(s * 0.25, s * 0.2),
		center + Vector2(-s * 0.25, s * 0.25),
	])
	canvas.draw_colored_polygon(body, color)

	# Weapon (bolter held diagonally)
	canvas.draw_line(
		center + Vector2(s * 0.1, -s * 0.15),
		center + Vector2(s * 0.7, -s * 0.55),
		color, 2.5
	)
	# Barrel tip
	canvas.draw_line(
		center + Vector2(s * 0.7, -s * 0.55),
		center + Vector2(s * 0.85, -s * 0.6),
		color, 1.5
	)


static func draw_vehicle_silhouette(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	# Top-down tank hull with angled front + turret + tracks
	var s = radius * 0.45

	# Hull body (hexagonal with angled front)
	var hull = PackedVector2Array([
		center + Vector2(-s * 0.7, -s * 0.5),   # Rear left
		center + Vector2(-s * 1.1, 0),            # Mid left
		center + Vector2(-s * 0.7, s * 0.5),      # Front left
		center + Vector2(s * 0.7, s * 0.5),       # Front right
		center + Vector2(s * 1.1, 0),              # Mid right
		center + Vector2(s * 0.7, -s * 0.5),      # Rear right
	])
	canvas.draw_colored_polygon(hull, color)

	# Track lines (left side)
	var track_color = Color(color.r * 0.6, color.g * 0.6, color.b * 0.6, color.a * 0.7)
	canvas.draw_line(center + Vector2(-s * 0.85, -s * 0.55), center + Vector2(-s * 0.85, s * 0.55), track_color, 3.0)
	# Track lines (right side)
	canvas.draw_line(center + Vector2(s * 0.85, -s * 0.55), center + Vector2(s * 0.85, s * 0.55), track_color, 3.0)

	# Turret ring
	var turret_color = Color(color.r, color.g, color.b, color.a * 0.85)
	canvas.draw_circle(center + Vector2(0, -s * 0.05), s * 0.35, turret_color)
	# Turret outline
	canvas.draw_arc(center + Vector2(0, -s * 0.05), s * 0.35, 0, TAU, 24, color.lightened(0.15), 1.5)

	# Gun barrel
	canvas.draw_line(center + Vector2(0, -s * 0.05), center + Vector2(0, s * 0.85), color, 2.5)
	# Barrel tip widening
	canvas.draw_line(center + Vector2(-s * 0.06, s * 0.8), center + Vector2(s * 0.06, s * 0.8), color, 2.0)


static func draw_monster_silhouette(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	# Hunched oval body with radiating claws + horned head
	var s = radius * 0.45

	# Hunched body (oval)
	var body_points = PackedVector2Array()
	for i in range(24):
		var angle = (float(i) / 24.0) * TAU
		var px = s * 0.65 * cos(angle)
		var py = s * 0.45 * sin(angle) + s * 0.1
		body_points.append(center + Vector2(px, py))
	canvas.draw_colored_polygon(body_points, color)

	# Horned head
	canvas.draw_circle(center + Vector2(0, -s * 0.5), s * 0.25, color)
	# Left horn
	canvas.draw_line(center + Vector2(-s * 0.15, -s * 0.7), center + Vector2(-s * 0.4, -s * 1.0), color, 2.0)
	# Right horn
	canvas.draw_line(center + Vector2(s * 0.15, -s * 0.7), center + Vector2(s * 0.4, -s * 1.0), color, 2.0)

	# Left claw (radiating lines)
	canvas.draw_line(center + Vector2(-s * 0.55, 0), center + Vector2(-s * 1.0, -s * 0.35), color, 2.5)
	canvas.draw_line(center + Vector2(-s * 1.0, -s * 0.35), center + Vector2(-s * 1.15, -s * 0.15), color, 2.0)
	canvas.draw_line(center + Vector2(-s * 1.0, -s * 0.35), center + Vector2(-s * 1.2, -s * 0.45), color, 1.5)

	# Right claw
	canvas.draw_line(center + Vector2(s * 0.55, 0), center + Vector2(s * 1.0, -s * 0.35), color, 2.5)
	canvas.draw_line(center + Vector2(s * 1.0, -s * 0.35), center + Vector2(s * 1.15, -s * 0.15), color, 2.0)
	canvas.draw_line(center + Vector2(s * 1.0, -s * 0.35), center + Vector2(s * 1.2, -s * 0.45), color, 1.5)
