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


static func draw_fought_overlay(canvas: CanvasItem, center: Vector2, radius: float, shape_type: String, poly_points: PackedVector2Array = PackedVector2Array()) -> void:
	# Dimmed overlay + checkmark for units that have fought this turn
	# Semi-transparent dark wash to visually "grey out" the token
	var dim_color = Color(0.0, 0.0, 0.0, 0.45)
	if shape_type == "circular":
		canvas.draw_circle(center, radius - 1.0, dim_color)
	else:
		if poly_points.size() > 0:
			# Inset slightly so overlay sits inside the rim
			var poly_center = Vector2.ZERO
			for p in poly_points:
				poly_center += p
			poly_center /= float(poly_points.size())
			var inset_points = PackedVector2Array()
			for p in poly_points:
				inset_points.append(poly_center + (p - poly_center) * 0.95)
			canvas.draw_colored_polygon(inset_points, dim_color)

	# Draw checkmark in bottom-right quadrant
	var check_size = max(5.0, radius * 0.28)
	var check_center = center + Vector2(radius * 0.35, radius * 0.35)
	# Checkmark background circle
	canvas.draw_circle(check_center, check_size + 1.0, Color(0.0, 0.0, 0.0, 0.6))
	canvas.draw_circle(check_center, check_size, Color(0.15, 0.5, 0.15, 0.9))
	# Checkmark strokes (short leg then long leg)
	var check_color = Color(1.0, 1.0, 1.0, 0.95)
	var stroke_width = max(1.5, check_size * 0.25)
	var p1 = check_center + Vector2(-check_size * 0.4, 0.0)
	var p2 = check_center + Vector2(-check_size * 0.1, check_size * 0.35)
	var p3 = check_center + Vector2(check_size * 0.45, -check_size * 0.35)
	canvas.draw_line(p1, p2, check_color, stroke_width)
	canvas.draw_line(p2, p3, check_color, stroke_width)


static func draw_engaged_indicator(canvas: CanvasItem, center: Vector2, radius: float, fight_priority: int = 1) -> void:
	# Crossed swords badge in top-left quadrant for engaged units
	# fight_priority: 0 = Fights First (red/gold), 1 = Normal (white), 2 = Fights Last (gray)
	var badge_size = max(5.0, radius * 0.28)
	var badge_center = center + Vector2(-radius * 0.35, -radius * 0.35)

	# Badge background circle
	var bg_color: Color
	var icon_color: Color
	match fight_priority:
		0:  # Fights First — red background, gold icon
			bg_color = Color(0.7, 0.15, 0.1, 0.9)
			icon_color = Color(1.0, 0.85, 0.3, 0.95)
		2:  # Fights Last — dark gray background, dim icon
			bg_color = Color(0.3, 0.3, 0.3, 0.85)
			icon_color = Color(0.65, 0.65, 0.65, 0.9)
		_:  # Normal — dark background, white icon
			bg_color = Color(0.15, 0.15, 0.15, 0.85)
			icon_color = Color(1.0, 1.0, 1.0, 0.95)

	canvas.draw_circle(badge_center, badge_size + 1.0, Color(0.0, 0.0, 0.0, 0.6))
	canvas.draw_circle(badge_center, badge_size, bg_color)

	# Draw crossed swords (two diagonal lines crossing at badge center)
	var stroke_width = max(1.5, badge_size * 0.22)
	var sword_len = badge_size * 0.55

	# Sword 1: top-left to bottom-right (\)
	var s1_start = badge_center + Vector2(-sword_len, -sword_len)
	var s1_end = badge_center + Vector2(sword_len, sword_len)
	canvas.draw_line(s1_start, s1_end, icon_color, stroke_width)

	# Sword 2: top-right to bottom-left (/)
	var s2_start = badge_center + Vector2(sword_len, -sword_len)
	var s2_end = badge_center + Vector2(-sword_len, sword_len)
	canvas.draw_line(s2_start, s2_end, icon_color, stroke_width)

	# Cross-guards (short horizontal lines on each sword near center)
	var guard_len = badge_size * 0.25
	var guard_offset = badge_size * 0.15
	# Guard on sword 1 (perpendicular to \ at slight offset from center)
	var g1_center = badge_center + Vector2(-guard_offset, -guard_offset)
	canvas.draw_line(
		g1_center + Vector2(-guard_len, guard_len * 0.5),
		g1_center + Vector2(guard_len, -guard_len * 0.5),
		icon_color, stroke_width * 0.8
	)
	# Guard on sword 2 (perpendicular to / at slight offset from center)
	var g2_center = badge_center + Vector2(guard_offset, -guard_offset)
	canvas.draw_line(
		g2_center + Vector2(-guard_len, -guard_len * 0.5),
		g2_center + Vector2(guard_len, guard_len * 0.5),
		icon_color, stroke_width * 0.8
	)


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
	# Static version - delegates to animated with t=0
	draw_infantry_silhouette_animated(canvas, center, radius, color, 0.0)


static func draw_vehicle_silhouette(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	# Static version - delegates to animated with t=0
	draw_vehicle_silhouette_animated(canvas, center, radius, color, 0.0)


static func draw_monster_silhouette(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	# Static version - delegates to animated with t=0
	draw_monster_silhouette_animated(canvas, center, radius, color, 0.0)


# --- Animated silhouettes ---
# These accept an animation_time parameter that drives subtle procedural animations.
# When animation_time is 0.0, they render identically to the original static versions.

static func draw_infantry_silhouette_animated(canvas: CanvasItem, center: Vector2, radius: float, color: Color, animation_time: float) -> void:
	# Helmet profile with visor slit + shoulder pad + idle breathing/weapon sway
	var s = radius * 0.45

	# Idle animation offsets
	var bob = sin(animation_time * 2.0) * s * 0.03       # Subtle vertical breathing bob
	var weapon_sway = sin(animation_time * 1.5) * 0.04   # Weapon angle oscillation
	var shoulder_shift = sin(animation_time * 1.8) * s * 0.015  # Slight shoulder movement

	# Helmet (rounded shape) - bobs with body
	canvas.draw_circle(center + Vector2(0, -s * 0.55 + bob), s * 0.32, color)
	# Visor slit (dark horizontal line across helmet)
	var visor_color = Color(color.r * 0.3, color.g * 0.3, color.b * 0.3, color.a * 0.8)
	canvas.draw_line(
		center + Vector2(-s * 0.2, -s * 0.58 + bob),
		center + Vector2(s * 0.15, -s * 0.58 + bob),
		visor_color, 2.0
	)

	# Shoulder pad (right side, angled trapezoid) - shifts with breathing
	var shoulder = PackedVector2Array([
		center + Vector2(s * 0.15 + shoulder_shift, -s * 0.4 + bob),
		center + Vector2(s * 0.55 + shoulder_shift, -s * 0.45 + bob),
		center + Vector2(s * 0.55 + shoulder_shift, -s * 0.15 + bob),
		center + Vector2(s * 0.2 + shoulder_shift, -s * 0.1 + bob),
	])
	canvas.draw_colored_polygon(shoulder, color)

	# Torso (tapered body) - bobs with breathing
	var body = PackedVector2Array([
		center + Vector2(-s * 0.3, -s * 0.25 + bob),
		center + Vector2(s * 0.15, -s * 0.25 + bob),
		center + Vector2(s * 0.25, s * 0.2 + bob * 0.5),
		center + Vector2(-s * 0.25, s * 0.25 + bob * 0.5),
	])
	canvas.draw_colored_polygon(body, color)

	# Weapon (bolter held diagonally) - sways subtly
	var weapon_base = center + Vector2(s * 0.1, -s * 0.15 + bob)
	var weapon_tip_x = s * 0.7 + weapon_sway * s
	var weapon_tip_y = -s * 0.55 + bob + weapon_sway * s * 0.3
	canvas.draw_line(
		weapon_base,
		center + Vector2(weapon_tip_x, weapon_tip_y),
		color, 2.5
	)
	# Barrel tip
	var barrel_x = s * 0.85 + weapon_sway * s * 1.2
	var barrel_y = -s * 0.6 + bob + weapon_sway * s * 0.4
	canvas.draw_line(
		center + Vector2(weapon_tip_x, weapon_tip_y),
		center + Vector2(barrel_x, barrel_y),
		color, 1.5
	)


static func draw_vehicle_silhouette_animated(canvas: CanvasItem, center: Vector2, radius: float, color: Color, animation_time: float) -> void:
	# Top-down tank hull with rotating turret + rumbling tracks
	var s = radius * 0.45

	# Idle animation: turret slow scan rotation, hull vibration
	var turret_angle = sin(animation_time * 0.6) * 0.25  # Slow turret sweep
	var hull_vibrate = sin(animation_time * 8.0) * s * 0.008  # Engine rumble

	# Hull body (hexagonal with angled front) - vibrates slightly
	var hull = PackedVector2Array([
		center + Vector2(-s * 0.7, -s * 0.5 + hull_vibrate),
		center + Vector2(-s * 1.1, hull_vibrate),
		center + Vector2(-s * 0.7, s * 0.5 + hull_vibrate),
		center + Vector2(s * 0.7, s * 0.5 + hull_vibrate),
		center + Vector2(s * 1.1, hull_vibrate),
		center + Vector2(s * 0.7, -s * 0.5 + hull_vibrate),
	])
	canvas.draw_colored_polygon(hull, color)

	# Track lines (left side) - with track detail animation
	var track_color = Color(color.r * 0.6, color.g * 0.6, color.b * 0.6, color.a * 0.7)
	canvas.draw_line(
		center + Vector2(-s * 0.85, -s * 0.55 + hull_vibrate),
		center + Vector2(-s * 0.85, s * 0.55 + hull_vibrate),
		track_color, 3.0
	)
	# Track hash marks (animated rolling)
	var track_offset = fmod(animation_time * s * 0.5, s * 0.2)
	for i in range(5):
		var ty = -s * 0.4 + i * s * 0.2 + track_offset + hull_vibrate
		if ty > -s * 0.55 and ty < s * 0.55:
			canvas.draw_line(
				center + Vector2(-s * 0.92, ty),
				center + Vector2(-s * 0.78, ty),
				track_color, 1.0
			)
	# Track lines (right side)
	canvas.draw_line(
		center + Vector2(s * 0.85, -s * 0.55 + hull_vibrate),
		center + Vector2(s * 0.85, s * 0.55 + hull_vibrate),
		track_color, 3.0
	)
	for i in range(5):
		var ty = -s * 0.4 + i * s * 0.2 + track_offset + hull_vibrate
		if ty > -s * 0.55 and ty < s * 0.55:
			canvas.draw_line(
				center + Vector2(s * 0.78, ty),
				center + Vector2(s * 0.92, ty),
				track_color, 1.0
			)

	# Turret ring (rotates)
	var turret_center = center + Vector2(0, -s * 0.05 + hull_vibrate)
	var turret_color = Color(color.r, color.g, color.b, color.a * 0.85)
	canvas.draw_circle(turret_center, s * 0.35, turret_color)
	canvas.draw_arc(turret_center, s * 0.35, 0, TAU, 24, color.lightened(0.15), 1.5)

	# Gun barrel (rotates with turret)
	var barrel_dir = Vector2(sin(turret_angle), cos(turret_angle))
	var barrel_end = turret_center + barrel_dir * s * 0.9
	canvas.draw_line(turret_center, barrel_end, color, 2.5)
	# Barrel tip widening (perpendicular to barrel direction)
	var barrel_perp = Vector2(barrel_dir.y, -barrel_dir.x)
	var tip_pos = turret_center + barrel_dir * s * 0.85
	canvas.draw_line(tip_pos - barrel_perp * s * 0.06, tip_pos + barrel_perp * s * 0.06, color, 2.0)


static func draw_monster_silhouette_animated(canvas: CanvasItem, center: Vector2, radius: float, color: Color, animation_time: float) -> void:
	# Hunched oval body with animated claws + breathing
	var s = radius * 0.45

	# Idle animation offsets
	var breathe = sin(animation_time * 1.5) * s * 0.04     # Torso heave
	var claw_flex = sin(animation_time * 2.0) * 0.06       # Claw open/close
	var head_bob = sin(animation_time * 1.8 + 0.5) * s * 0.02  # Head nod

	# Hunched body (oval) - breathes/pulses
	var body_points = PackedVector2Array()
	var breathe_scale = 1.0 + sin(animation_time * 1.5) * 0.03
	for i in range(24):
		var angle = (float(i) / 24.0) * TAU
		var px = s * 0.65 * breathe_scale * cos(angle)
		var py = s * 0.45 * breathe_scale * sin(angle) + s * 0.1 + breathe * 0.5
		body_points.append(center + Vector2(px, py))
	canvas.draw_colored_polygon(body_points, color)

	# Horned head - subtle nod
	canvas.draw_circle(center + Vector2(0, -s * 0.5 + head_bob), s * 0.25, color)
	# Left horn
	canvas.draw_line(
		center + Vector2(-s * 0.15, -s * 0.7 + head_bob),
		center + Vector2(-s * 0.4, -s * 1.0 + head_bob),
		color, 2.0
	)
	# Right horn
	canvas.draw_line(
		center + Vector2(s * 0.15, -s * 0.7 + head_bob),
		center + Vector2(s * 0.4, -s * 1.0 + head_bob),
		color, 2.0
	)

	# Left claw - flexes open and closed
	var l_claw_spread = claw_flex * s
	canvas.draw_line(
		center + Vector2(-s * 0.55, breathe * 0.5),
		center + Vector2(-s * 1.0 - l_claw_spread, -s * 0.35 + breathe * 0.3),
		color, 2.5
	)
	canvas.draw_line(
		center + Vector2(-s * 1.0 - l_claw_spread, -s * 0.35 + breathe * 0.3),
		center + Vector2(-s * 1.15 - l_claw_spread * 0.5, -s * 0.15 + breathe * 0.3),
		color, 2.0
	)
	canvas.draw_line(
		center + Vector2(-s * 1.0 - l_claw_spread, -s * 0.35 + breathe * 0.3),
		center + Vector2(-s * 1.2 - l_claw_spread * 0.8, -s * 0.45 + breathe * 0.3),
		color, 1.5
	)

	# Right claw - flexes opposite to left
	var r_claw_spread = -claw_flex * s
	canvas.draw_line(
		center + Vector2(s * 0.55, breathe * 0.5),
		center + Vector2(s * 1.0 - r_claw_spread, -s * 0.35 + breathe * 0.3),
		color, 2.5
	)
	canvas.draw_line(
		center + Vector2(s * 1.0 - r_claw_spread, -s * 0.35 + breathe * 0.3),
		center + Vector2(s * 1.15 - r_claw_spread * 0.5, -s * 0.15 + breathe * 0.3),
		color, 2.0
	)
	canvas.draw_line(
		center + Vector2(s * 1.0 - r_claw_spread, -s * 0.35 + breathe * 0.3),
		center + Vector2(s * 1.2 - r_claw_spread * 0.8, -s * 0.45 + breathe * 0.3),
		color, 1.5
	)


# --- Pixel Art Silhouettes (Retro Mode) ---
# These draw chunky pixel-art-style unit representations using grid-snapped rectangles.
# Each pixel block is drawn as a small filled rect, creating a deliberate 8-bit aesthetic.

static func _px(canvas: CanvasItem, center: Vector2, grid: float, gx: int, gy: int, color: Color) -> void:
	# Draw a single "pixel" block at grid position (gx, gy) relative to center
	var pos = center + Vector2(gx * grid, gy * grid)
	canvas.draw_rect(Rect2(pos, Vector2(grid, grid)), color)


static func _px_row(canvas: CanvasItem, center: Vector2, grid: float, gx_start: int, gx_end: int, gy: int, color: Color) -> void:
	# Draw a horizontal row of pixel blocks
	for gx in range(gx_start, gx_end + 1):
		_px(canvas, center, grid, gx, gy, color)


static func draw_infantry_pixel(canvas: CanvasItem, center: Vector2, radius: float, color: Color, animation_time: float) -> void:
	# Pixel art Space Marine - 8x12 grid, chunky bolter and helmet
	# Max extent is ~5.5 grid cells from center; grid sized so sprite fills ~90% of base
	var grid = radius * 0.17
	var bob_frame = int(animation_time * 2.0) % 4
	var bob_y = 0 if (bob_frame == 0 or bob_frame == 2) else (1 if bob_frame == 1 else -1)
	var c = center + Vector2(-grid * 0.5, bob_y * grid * 0.3)  # Center offset

	# Darker shade for depth
	var dark = Color(color.r * 0.6, color.g * 0.6, color.b * 0.6, color.a)
	var visor = Color(0.2, 0.8, 1.0, color.a)  # Cyan visor glow
	var gun_color = Color(color.r * 0.4, color.g * 0.4, color.b * 0.4, color.a)

	# Helmet (3 wide, 2 tall)
	_px_row(canvas, c, grid, -1, 1, -5, color)
	_px_row(canvas, c, grid, -1, 1, -4, color)
	# Visor slit
	_px_row(canvas, c, grid, -1, 1, -4, visor)

	# Neck
	_px(canvas, c, grid, 0, -3, dark)

	# Shoulder pads (wide)
	_px_row(canvas, c, grid, -3, -2, -3, color)
	_px_row(canvas, c, grid, 2, 3, -3, color)
	_px_row(canvas, c, grid, -3, -2, -2, color)
	_px_row(canvas, c, grid, 2, 3, -2, color)

	# Torso
	_px_row(canvas, c, grid, -2, 2, -2, dark)
	_px_row(canvas, c, grid, -2, 2, -1, color)
	_px_row(canvas, c, grid, -1, 1, 0, color)

	# Belt / waist
	_px_row(canvas, c, grid, -1, 1, 1, dark)

	# Legs
	_px(canvas, c, grid, -1, 2, color)
	_px(canvas, c, grid, 1, 2, color)
	_px(canvas, c, grid, -1, 3, color)
	_px(canvas, c, grid, 1, 3, color)

	# Boots
	_px_row(canvas, c, grid, -2, -1, 4, dark)
	_px_row(canvas, c, grid, 1, 2, 4, dark)

	# Bolter (right side, animated weapon sway)
	var weapon_frame = int(animation_time * 1.5) % 3
	var wx = 3 + (1 if weapon_frame == 1 else 0)
	_px(canvas, c, grid, wx, -2, gun_color)
	_px(canvas, c, grid, wx, -3, gun_color)
	_px(canvas, c, grid, wx, -4, gun_color)
	_px(canvas, c, grid, wx + 1, -4, gun_color)  # Barrel tip


static func draw_vehicle_pixel(canvas: CanvasItem, center: Vector2, radius: float, color: Color, animation_time: float) -> void:
	# Pixel art tank - top-down view, 12x8 grid
	# Max extent is ~6 grid cells from center; grid sized so sprite fills ~90% of base
	var grid = radius * 0.15
	var c = center + Vector2(-grid * 0.5, 0)

	var dark = Color(color.r * 0.6, color.g * 0.6, color.b * 0.6, color.a)
	var track_color = Color(color.r * 0.35, color.g * 0.35, color.b * 0.35, color.a)
	var turret_color = Color(color.r * 0.8, color.g * 0.8, color.b * 0.8, color.a)

	# Engine rumble animation
	var rumble = int(animation_time * 8.0) % 2
	var ry = rumble * 1  # Subtle vertical jitter

	# Left track
	for ty in range(-3, 4):
		_px(canvas, c, grid, -5, ty + ry, track_color)
		_px(canvas, c, grid, -4, ty + ry, track_color)
	# Right track
	for ty in range(-3, 4):
		_px(canvas, c, grid, 4, ty + ry, track_color)
		_px(canvas, c, grid, 5, ty + ry, track_color)

	# Track detail marks (animated rolling)
	var track_anim = int(animation_time * 3.0) % 3
	for i in range(3):
		var mark_y = -2 + i * 2 + track_anim
		if mark_y >= -3 and mark_y <= 3:
			_px(canvas, c, grid, -5, mark_y + ry, dark)
			_px(canvas, c, grid, 5, mark_y + ry, dark)

	# Hull body
	_px_row(canvas, c, grid, -3, 3, -3 + ry, dark)  # Front armor
	for hy in range(-2, 4):
		_px_row(canvas, c, grid, -3, 3, hy + ry, color)
	_px_row(canvas, c, grid, -3, 3, -3 + ry, dark)  # Rear armor

	# Turret (centered square) - rotates slowly
	var turret_frame = int(animation_time * 0.5) % 4
	_px_row(canvas, c, grid, -1, 1, -1 + ry, turret_color)
	_px_row(canvas, c, grid, -1, 1, 0 + ry, turret_color)
	_px_row(canvas, c, grid, -1, 1, 1 + ry, turret_color)

	# Gun barrel (direction based on turret_frame)
	match turret_frame:
		0:  # Pointing up
			_px(canvas, c, grid, 0, -2 + ry, turret_color)
			_px(canvas, c, grid, 0, -3 + ry, turret_color)
			_px(canvas, c, grid, 0, -4 + ry, turret_color)
		1:  # Pointing right
			_px(canvas, c, grid, 2, 0 + ry, turret_color)
			_px(canvas, c, grid, 3, 0 + ry, turret_color)
			_px(canvas, c, grid, 4, 0 + ry, turret_color)
		2:  # Pointing down
			_px(canvas, c, grid, 0, 2 + ry, turret_color)
			_px(canvas, c, grid, 0, 3 + ry, turret_color)
			_px(canvas, c, grid, 0, 4 + ry, turret_color)
		3:  # Pointing left
			_px(canvas, c, grid, -2, 0 + ry, turret_color)
			_px(canvas, c, grid, -3, 0 + ry, turret_color)
			_px(canvas, c, grid, -4, 0 + ry, turret_color)


static func draw_monster_pixel(canvas: CanvasItem, center: Vector2, radius: float, color: Color, animation_time: float) -> void:
	# Pixel art Tyranid-like monster - hunched body with claws, 10x12 grid
	# Max extent is ~7 grid cells from center (claws); grid sized so body fills ~90% of base
	var grid = radius * 0.13
	var c = center + Vector2(-grid * 0.5, 0)

	var dark = Color(color.r * 0.55, color.g * 0.55, color.b * 0.55, color.a)
	var claw_color = Color(color.r * 0.8, color.g * 0.8, color.b * 0.8, color.a)
	var eye_color = Color(1.0, 0.2, 0.1, color.a)  # Red eyes

	# Breathing animation
	var breathe_frame = int(animation_time * 1.5) % 4
	var breathe_expand = 1 if (breathe_frame == 1 or breathe_frame == 2) else 0

	# Claw animation
	var claw_frame = int(animation_time * 2.0) % 3
	var claw_offset = claw_frame - 1  # -1, 0, 1

	# Horns
	_px(canvas, c, grid, -2, -6, color)
	_px(canvas, c, grid, 2, -6, color)
	_px(canvas, c, grid, -1, -5, color)
	_px(canvas, c, grid, 1, -5, color)

	# Head
	_px_row(canvas, c, grid, -1, 1, -4, color)
	_px_row(canvas, c, grid, -1, 1, -3, color)
	# Eyes
	_px(canvas, c, grid, -1, -3, eye_color)
	_px(canvas, c, grid, 1, -3, eye_color)

	# Neck / upper body
	_px_row(canvas, c, grid, -1, 1, -2, dark)

	# Torso (expands with breathing)
	var torso_w = 2 + breathe_expand
	_px_row(canvas, c, grid, -torso_w, torso_w, -1, color)
	_px_row(canvas, c, grid, -torso_w, torso_w, 0, color)
	_px_row(canvas, c, grid, -torso_w, torso_w, 1, dark)

	# Lower body / tail
	_px_row(canvas, c, grid, -1, 1, 2, color)
	_px(canvas, c, grid, 0, 3, color)
	_px(canvas, c, grid, 0, 4, dark)  # Tail tip

	# Legs
	_px(canvas, c, grid, -2, 2, dark)
	_px(canvas, c, grid, -3, 3, dark)
	_px(canvas, c, grid, 2, 2, dark)
	_px(canvas, c, grid, 3, 3, dark)

	# Left claw arm (animated)
	_px(canvas, c, grid, -3 + claw_offset, -2, claw_color)
	_px(canvas, c, grid, -4 + claw_offset, -3, claw_color)
	_px(canvas, c, grid, -5 + claw_offset, -4, claw_color)
	# Claw pincer
	_px(canvas, c, grid, -6 + claw_offset, -5, claw_color)
	_px(canvas, c, grid, -5 + claw_offset, -5, claw_color)

	# Right claw arm (animated, opposite phase)
	_px(canvas, c, grid, 3 - claw_offset, -2, claw_color)
	_px(canvas, c, grid, 4 - claw_offset, -3, claw_color)
	_px(canvas, c, grid, 5 - claw_offset, -4, claw_color)
	# Claw pincer
	_px(canvas, c, grid, 6 - claw_offset, -5, claw_color)
	_px(canvas, c, grid, 5 - claw_offset, -5, claw_color)
