extends RefCounted

# BoardFit — the pure math behind the fit-board camera (T13, design doc §1)
# and the fit-selection camera (T14, Shift+F; see "fit selection" below).
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


# --------------------------------------------------------- fit selection --
# T14 (design doc §1): Shift+F frames the selected unit. Same screen <-> world
# model as the board fit above; the unit's footprint takes the board's place.

# Board kept in view around a framed selection, on its tighter axis: 5" (200 px
# at 40 px per inch). Neighbouring units within that distance of the unit's
# bases are always in frame; at the zoom cap there is more.
const SELECTION_CONTEXT_PX := 200.0
# Closest the selection fit zooms in. A lone model is framed with the table
# around it instead of being blown up to fill the screen.
const SELECTION_MAX_ZOOM := 1.2


# World-space footprint of a set of models: the union of a circle round each
# centre with its radius (Measurement.base_extent_px: the circumscribed radius,
# so an oval or rectangular base fits inside whatever way it is turned).
# Rect2() (no area) when there are no points.
static func footprint(centres: Array, radii: Array) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var any := false
	for i in range(centres.size()):
		if typeof(centres[i]) != TYPE_VECTOR2:
			continue
		var p: Vector2 = centres[i]
		var r: float = 0.0
		if i < radii.size():
			r = maxf(float(radii[i]), 0.0)
		lo = Vector2(minf(lo.x, p.x - r), minf(lo.y, p.y - r))
		hi = Vector2(maxf(hi.x, p.x + r), maxf(hi.y, p.y + r))
		any = true
	if not any:
		return Rect2()
	return Rect2(lo, hi - lo)


# Where Main.update_view_transform() puts world point `p` before zoom and pan:
# the board turned `rotation` about its centre (the "rotated space" that
# view_offset lives in). unrotate_about_board() is the inverse.
static func rotate_about_board(p: Vector2, board_size: Vector2, rotation: float) -> Vector2:
	var c: Vector2 = board_size * 0.5
	return (p - c).rotated(rotation) + c


static func unrotate_about_board(q: Vector2, board_size: Vector2, rotation: float) -> Vector2:
	var c: Vector2 = board_size * 0.5
	return (q - c).rotated(-rotation) + c


# Zoom and pan that frame world rect `box` (a selection's footprint) in
# `view_rect`: the box's centre on the rect's middle, with `context` world px of
# board around it on the tighter axis, zooming no closer than `max_zoom`. The
# context only ever lowers the zoom, so the whole box is always inside
# view_rect, `context * zoom` screen px clear of its edges on the tight axis and
# more on the other. A quarter-turned view swaps the box's extents. Returns:
#   zoom        — the view zoom
#   center      — the box centre (world), what the camera frames
#   focus       — that centre in rotated space (== center when unrotated)
#   anchor      — the screen point the centre lands on (view_rect's middle)
#   view_rect   — the rect that was fitted into
#   view_offset — Main.view_offset for that framing
#   box         — the box that was framed
static func fit_box(view_rect: Rect2, box: Rect2, board_size: Vector2, rotation: float = 0.0,
		context: float = SELECTION_CONTEXT_PX, max_zoom: float = SELECTION_MAX_ZOOM) -> Dictionary:
	var on_screen: Vector2 = box.size
	var quarter_turns: int = int(round(rotation / (PI * 0.5)))
	if posmod(quarter_turns, 2) == 1:
		on_screen = Vector2(box.size.y, box.size.x)
	var pad: float = maxf(context, 0.0) * 2.0
	var zx: float = view_rect.size.x / maxf(on_screen.x + pad, 1.0)
	var zy: float = view_rect.size.y / maxf(on_screen.y + pad, 1.0)
	var zoom: float = maxf(0.01, minf(minf(zx, zy), max_zoom))
	var center: Vector2 = box.get_center()
	var focus: Vector2 = rotate_about_board(center, board_size, rotation)
	var anchor: Vector2 = view_rect.get_center()
	return {
		"zoom": zoom,
		"center": center,
		"focus": focus,
		"anchor": anchor,
		"view_rect": view_rect,
		"view_offset": focus - anchor / zoom,
		"box": box,
	}


# One frame of the fit-selection glide at eased progress `e` (0..1). The
# selection's centre (`focus`, rotated space) slides across the screen in a
# straight line from where it was (`from_screen`) to `anchor`, while the zoom
# changes by the same ratio per step. The unit heads straight for the middle of
# the view as it grows. glide_sample() above holds the anchor's world point on
# a straight line instead, which on a big zoom-IN swings the unit outwards
# before it comes back (by 60% of its start distance for a 10x zoom). e = 0 and
# e = 1 give the start and end framings exactly.
static func point_glide_sample(focus: Vector2, from_screen: Vector2, anchor: Vector2, from_zoom: float, to_zoom: float, e: float) -> Dictionary:
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
	var screen: Vector2 = from_screen.lerp(anchor, clampf(e, 0.0, 1.0))
	return {"zoom": zoom, "screen": screen, "view_offset": focus - screen / zoom}


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
