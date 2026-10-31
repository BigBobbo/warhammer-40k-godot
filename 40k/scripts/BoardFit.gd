extends RefCounted

# BoardFit — the pure math behind the fit-board camera (T13, design doc §1).
#
# Main.fit_view_to_board() (the F key) frames the whole battlefield in the part
# of the window the board can actually be seen in, with a 32px margin, and
# glides there instead of cutting. Everything here is static and side-effect
# free so the headless test (tests/test_fit_board_camera.gd) can check the
# numbers without a running battle scene; Main gathers the live inputs (the
# viewport rect, the HUD panel rects, the board size, the view rotation) and
# applies the result to view_offset / view_zoom.
#
# Screen <-> world, as Main.update_view_transform() draws it:
#     screen = view_zoom * rot_about_board_centre(world) - view_offset * view_zoom
# so the (rotated-space) world point under a screen point S is
#     view_offset + S / view_zoom
# and the board centre, which the rotation leaves where it is, lands on screen
# point A exactly when  view_offset = board_centre - A / view_zoom.

const MARGIN_PX := 32.0


# The part of the viewport the board can be framed in: the viewport minus the
# HUD panels drawn over it. Each panel rect is classed by its shape — wider than
# tall is a bar across the top or bottom (the top bar, the phase strip), taller
# than wide is a column down a side (the game log, the right-hand panel) — and
# by which half of the screen its centre sits in, so a panel that is moved to
# the other edge still clips the right side. Falls back to the whole viewport
# when the panels would leave less than 2px either way (a tiny window, or a
# layout pass that has not run yet).
static func free_rect(viewport_rect: Rect2, panel_rects: Array) -> Rect2:
	var left: float = viewport_rect.position.x
	var top: float = viewport_rect.position.y
	var right: float = viewport_rect.end.x
	var bottom: float = viewport_rect.end.y
	var mid: Vector2 = viewport_rect.get_center()
	for r in panel_rects:
		if typeof(r) != TYPE_RECT2:
			continue
		var rect: Rect2 = (r as Rect2).abs().intersection(viewport_rect)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		if rect.size.x >= rect.size.y:
			if rect.get_center().y < mid.y:
				top = maxf(top, rect.end.y)
			else:
				bottom = minf(bottom, rect.position.y)
		else:
			if rect.get_center().x < mid.x:
				left = maxf(left, rect.end.x)
			else:
				right = minf(right, rect.position.x)
	if right - left < 2.0 or bottom - top < 2.0:
		return viewport_rect
	return Rect2(left, top, right - left, bottom - top)


# Zoom and pan that put the whole board inside `view_rect`, `margin` screen
# pixels in from its edges on the tighter axis and centred on the other.
# A quarter-turned view (Main.rotate_board_view) shows the board's long side
# across the screen, so the extents swap. Returns:
#   zoom        — the view zoom
#   center      — the board centre (world), what the camera frames
#   anchor      — the screen point the board centre lands on (view_rect's middle)
#   view_rect   — the rect that was fitted into
#   view_offset — Main.view_offset for that framing
static func fit(view_rect: Rect2, board_size: Vector2, rotation: float = 0.0, margin: float = MARGIN_PX) -> Dictionary:
	var on_screen: Vector2 = board_size
	var quarter_turns: int = int(round(rotation / (PI * 0.5)))
	if posmod(quarter_turns, 2) == 1:
		on_screen = Vector2(board_size.y, board_size.x)
	var inner: Rect2 = view_rect.grow(-margin)
	if inner.size.x < 1.0 or inner.size.y < 1.0:
		# Too small for the margin: fill the rect rather than go negative.
		inner = view_rect
	var zoom: float = maxf(0.01, minf(inner.size.x / maxf(on_screen.x, 1.0), inner.size.y / maxf(on_screen.y, 1.0)))
	var center: Vector2 = board_size * 0.5
	var anchor: Vector2 = view_rect.get_center()
	return {
		"zoom": zoom,
		"center": center,
		"anchor": anchor,
		"view_rect": view_rect,
		"view_offset": center - anchor / zoom,
	}


# One frame of the fit glide at eased progress `e` (0..1). The world point under
# the fixed screen `anchor` travels in a straight line from `from_focus` to
# `to_focus`, and the zoom changes by the same ratio per step (interpolated in
# log space), so a big zoom-out reads as an even pull-back rather than a lurch
# at one end. Interpolating view_offset directly instead (what the LB/RB unit
# glide does at a near-constant zoom) swings the frame sideways whenever the
# zoom changes a lot. e = 0 and e = 1 give the start and end framings exactly.
static func glide_sample(from_focus: Vector2, to_focus: Vector2, from_zoom: float, to_zoom: float, anchor: Vector2, e: float) -> Dictionary:
	var zoom: float
	if from_zoom > 0.0 and to_zoom > 0.0:
		zoom = from_zoom * pow(to_zoom / from_zoom, e)
	else:
		zoom = lerpf(from_zoom, to_zoom, e)
	if e >= 1.0:
		zoom = to_zoom
	elif e <= 0.0:
		zoom = from_zoom
	zoom = maxf(zoom, 0.0001)
	var focus: Vector2 = from_focus.lerp(to_focus, clampf(e, 0.0, 1.0))
	return {"zoom": zoom, "focus": focus, "view_offset": focus - anchor / zoom}


# Screen-space margins between the board's rect on screen and `view_rect`
# (positive = clear of that edge). Used by the scenario and the headless test to
# check the fit leaves the board whole and evenly framed.
static func margins(board_screen_rect: Rect2, view_rect: Rect2) -> Dictionary:
	return {
		"left": board_screen_rect.position.x - view_rect.position.x,
		"right": view_rect.end.x - board_screen_rect.end.x,
		"top": board_screen_rect.position.y - view_rect.position.y,
		"bottom": view_rect.end.y - board_screen_rect.end.y,
	}
