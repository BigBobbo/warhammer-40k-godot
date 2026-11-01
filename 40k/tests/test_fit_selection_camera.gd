extends SceneTree

# T14 — Fit-selection keybind (Shift+F), design doc §1.
#
# Covers the parts of the fit-selection camera that do not need a window (the
# windowed scenario tests/scenarios/visual/T14_fit_selection.json selects a unit
# with a real click, pans away and presses the real Shift+F against the running
# game):
#   - KeybindingManager: Shift+F means Fit View to Selection and nothing else;
#     plain F stays Fit View to Board.
#   - BoardFit.footprint(): the union of a circle round each model with its
#     base radius — the box the fit must keep whole on screen.
#   - BoardFit.fit_box(): the box's centre lands on the middle of the free rect
#     (the viewport minus the HUD, BoardFit.free_rect at 1920x1080 with the live
#     panels), measured through the same transform Main.update_view_transform()
#     draws with; a small unit stops at the 1.2x cap; a big one zooms out until
#     the box plus 5" (200 px) of table fits, so it is never cropped; units
#     within those 5" are in frame; a quarter-turned view swaps the extents and
#     still centres. The pre-T14 math (whole window, model centres only) put a
#     wide unit under the game log and the right panel and a lone model 46 px
#     off the middle of the free area — checked so the reason stays on record.
#   - BoardFit.point_glide_sample(): exact end points, the unit's centre on a
#     straight screen line into the anchor and always getting closer, the zoom
#     at a constant ratio per step. The T13 anchored sample swings a unit
#     outwards on a big zoom-in — the reason the selection glide has its own.
#
# Usage: godot --headless --path . -s tests/test_fit_selection_camera.gd

const BoardFit = preload("res://scripts/BoardFit.gd")

const VIEWPORT := Rect2(0, 0, 1920, 1080)
const BOARD := Vector2(1760, 2400)
# Live HUD rects at 1920x1080 (as in tests/test_fit_board_camera.gd).
const TOP_BAR := Rect2(0, 0, 1920, 100)        # HUD_Bottom, anchored to the top
const PHASE_STRIP := Rect2(340, 1050, 1180, 30)
const GAME_LOG := Rect2(0, 105, 340, 975)
const HUD_RIGHT := Rect2(1520, 100, 400, 980)

var passed := 0
var failed := 0
var free_rect := Rect2()


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _init():
	create_timer(0.1).timeout.connect(_run_tests)


func _run_tests() -> void:
	print("=== T14 fit-selection camera ===")
	free_rect = BoardFit.free_rect(VIEWPORT, [TOP_BAR, PHASE_STRIP, GAME_LOG, HUD_RIGHT])
	_check("free rect at 1920x1080 is Rect2(340, 100, 1180, 950)", free_rect.is_equal_approx(Rect2(340, 100, 1180, 950)), str(free_rect))
	_test_keybindings()
	_test_footprint()
	_test_fit_box()
	_test_rotation()
	_test_point_glide_sample()
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)


# --------------------------------------------------------------- helpers ---

# Screen transform exactly as Main.update_view_transform() builds BoardRoot's.
func _view_xform(view_offset: Vector2, zoom: float, rotation: float) -> Transform2D:
	var c: Vector2 = BOARD * 0.5
	var t := Transform2D()
	t = t.translated(-c)
	t = t.rotated(rotation)
	t = t.translated(c)
	t = t.scaled(Vector2(zoom, zoom))
	t.origin += -view_offset * zoom
	return t


# A world rect's bounding rect on screen through the view transform.
func _screen_rect(world: Rect2, view_offset: Vector2, zoom: float, rotation: float) -> Rect2:
	var t := _view_xform(view_offset, zoom, rotation)
	var r := Rect2(t * world.position, Vector2.ZERO)
	for corner in [Vector2(world.end.x, world.position.y), Vector2(world.position.x, world.end.y), world.end]:
		r = r.expand(t * corner)
	return r


func _fit_screen_rect(fit: Dictionary, rotation: float = 0.0) -> Rect2:
	return _screen_rect(fit["box"], fit["view_offset"], float(fit["zoom"]), rotation)


func _near(a: float, b: float, tol: float = 0.01) -> bool:
	return absf(a - b) <= tol


func _clearance(inner: Rect2, outer: Rect2) -> Dictionary:
	return {
		"left": inner.position.x - outer.position.x,
		"right": outer.end.x - inner.end.x,
		"top": inner.position.y - outer.position.y,
		"bottom": outer.end.y - inner.end.y,
	}


# --------------------------------------------------------------- bindings ---

func _f_event(shift: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_F
	e.shift_pressed = shift
	e.pressed = true
	return e


func _test_keybindings() -> void:
	print("\n-- KeybindingManager: Shift+F is Fit View to Selection --")
	var kbm = load("res://autoloads/KeybindingManager.gd").new()
	kbm._register_defaults()  # defaults only; never touches the player's config
	var b: Dictionary = kbm.get_binding("fit_view_selection")
	_check("fit_view_selection defaults to Shift+F", b.get("key", -1) == KEY_F and b.shift and not b.ctrl and not b.alt and not b.get("meta", false), str(b))
	_check("a Shift+F press matches fit_view_selection", kbm.matches_action(_f_event(true), "fit_view_selection"))
	_check("a Shift+F press does not match fit_view_board", not kbm.matches_action(_f_event(true), "fit_view_board"))
	_check("a plain F press does not match fit_view_selection", not kbm.matches_action(_f_event(false), "fit_view_selection"))
	var shift_f: Array = []
	for action_id in kbm.bindings:
		var a: Dictionary = kbm.bindings[action_id]
		if (a.key == KEY_F or a.alt_key == KEY_F) and a.shift and not a.ctrl and not a.alt and not a.get("meta", false):
			shift_f.append(action_id)
	_check("fit_view_selection is the only action on Shift+F", shift_f == ["fit_view_selection"], str(shift_f))
	_check("find_conflict(Shift+F) for fit_view_selection finds nothing", kbm.find_conflict("fit_view_selection", KEY_F, true, false, false, false) == "")
	kbm.free()


# -------------------------------------------------------------- footprint ---

func _test_footprint() -> void:
	print("\n-- BoardFit.footprint: models with their bases --")
	var box: Rect2 = BoardFit.footprint([Vector2(100, 100), Vector2(300, 150), Vector2(200, 400)], [10.0, 20.0, 5.0])
	_check("union of the base circles: x 90..320, y 90..405", box.is_equal_approx(Rect2(90, 90, 230, 315)), str(box))
	var one: Rect2 = BoardFit.footprint([Vector2(500, 600)], [19.685])
	_check("one model: its base circle's box (has area)", one.has_area() and one.get_center().is_equal_approx(Vector2(500, 600)) and _near(one.size.x, 39.37, 0.001), str(one))
	_check("no models: no area", not BoardFit.footprint([], []).has_area())
	var skipped: Rect2 = BoardFit.footprint([Vector2(0, 0), null, "x", Vector2(10, 10)], [1.0, 50.0, 50.0, 1.0])
	_check("non-Vector2 entries are skipped (their radius does not count)", skipped.is_equal_approx(Rect2(-1, -1, 12, 12)), str(skipped))
	var no_radius: Rect2 = BoardFit.footprint([Vector2(0, 0), Vector2(10, 0)], [3.0])
	_check("a missing radius counts as 0", no_radius.is_equal_approx(Rect2(-3, -3, 13, 6)), str(no_radius))
	var negative: Rect2 = BoardFit.footprint([Vector2(5, 5)], [-4.0])
	_check("a negative radius counts as 0", negative.position.is_equal_approx(Vector2(5, 5)) and negative.size.is_equal_approx(Vector2.ZERO), str(negative))


# ---------------------------------------------------------------- fit box ---

func _test_fit_box() -> void:
	print("\n-- BoardFit.fit_box: a small unit stops at the 1.2x cap, centred --")
	var anchor: Vector2 = free_rect.get_center()
	_check("the anchor is the middle of the free rect (930, 575)", anchor.is_equal_approx(Vector2(930, 575)), str(anchor))
	# A Gretchin-sized mob: 22 models on 25mm bases, 420 x 180 px of footprint.
	var mob := Rect2(600, 20, 420, 180)
	var fit: Dictionary = BoardFit.fit_box(free_rect, mob, BOARD, 0.0)
	var z: float = fit["zoom"]
	_check("small unit: zoom is the 1.2x cap", _near(z, BoardFit.SELECTION_MAX_ZOOM, 1e-9), str(z))
	_check("the cap is 1.2 and the context 200 px (5\")", _near(BoardFit.SELECTION_MAX_ZOOM, 1.2, 1e-9) and _near(BoardFit.SELECTION_CONTEXT_PX, 200.0, 1e-9))
	_check("fit frames the box centre", (fit["center"] as Vector2).is_equal_approx(Vector2(810, 110)), str(fit["center"]))
	_check("unrotated, focus == centre", (fit["focus"] as Vector2).is_equal_approx(fit["center"]))
	_check("anchor and view_rect are reported", (fit["anchor"] as Vector2).is_equal_approx(anchor) and (fit["view_rect"] as Rect2).is_equal_approx(free_rect))
	var t := _view_xform(fit["view_offset"], z, 0.0)
	_check("the box centre lands on the anchor on screen", (t * Vector2(810, 110)).distance_to(anchor) < 0.01, str(t * Vector2(810, 110)))
	var on_screen := _fit_screen_rect(fit)
	_check("the whole box is inside the free rect", free_rect.encloses(on_screen), "box %s free %s" % [str(on_screen), str(free_rect)])
	var c := _clearance(on_screen, free_rect)
	_check("centred: left == right and top == bottom", _near(c.left, c.right) and _near(c.top, c.bottom), str(c))
	_check("at the cap, more than 5\" (200 px * zoom) of table on every side", minf(minf(c.left, c.right), minf(c.top, c.bottom)) > 200.0 * z, str(c))
	# A neighbour 4.5" (180 px) left of the mob's footprint, on a 32mm base.
	var neighbour := Rect2(600 - 180 - 25, 110 - 25, 50, 50)
	_check("a neighbour 4.5\" from the footprint is fully in frame", free_rect.encloses(_screen_rect(neighbour, fit["view_offset"], z, 0.0)))

	print("\n-- BoardFit.fit_box: a big unit zooms out instead of being cropped --")
	var wide := Rect2(100, 1000, 1400, 300)
	var fw: Dictionary = BoardFit.fit_box(free_rect, wide, BOARD, 0.0)
	var zw: float = fw["zoom"]
	_check("wide unit: zoom = 1180 / (1400 + 400)", _near(zw, 1180.0 / 1800.0, 1e-9), str(zw))
	var rw := _fit_screen_rect(fw)
	var cw := _clearance(rw, free_rect)
	_check("wide unit: whole box inside the free rect", free_rect.grow(0.01).encloses(rw), str(rw))
	_check("wide unit: exactly 5\" of table each side across (200 px * zoom)", _near(cw.left, 200.0 * zw) and _near(cw.right, 200.0 * zw), str(cw))
	_check("wide unit: centred top/bottom", _near(cw.top, cw.bottom), str(cw))
	var tall := Rect2(700, 200, 300, 1500)
	var ft: Dictionary = BoardFit.fit_box(free_rect, tall, BOARD, 0.0)
	var zt: float = ft["zoom"]
	var rt := _fit_screen_rect(ft)
	var ct := _clearance(rt, free_rect)
	_check("tall unit: zoom = 950 / (1500 + 400)", _near(zt, 0.5, 1e-9), str(zt))
	_check("tall unit: whole box inside, 5\" above and below", free_rect.grow(0.01).encloses(rt) and _near(ct.top, 100.0) and _near(ct.bottom, 100.0), str(ct))
	var whole := Rect2(Vector2.ZERO, BOARD)
	var fb: Dictionary = BoardFit.fit_box(free_rect, whole, BOARD, 0.0)
	_check("a unit spanning the whole board still fits whole", free_rect.grow(0.01).encloses(_fit_screen_rect(fb)), str(_fit_screen_rect(fb)))
	var point := Rect2(500, 500, 0, 0)
	var fp: Dictionary = BoardFit.fit_box(free_rect, point, BOARD, 0.0)
	_check("a zero-size box: capped zoom, centred on the anchor", _near(float(fp["zoom"]), 1.2, 1e-9) and (_view_xform(fp["view_offset"], 1.2, 0.0) * Vector2(500, 500)).distance_to(anchor) < 0.01)
	var other_context: Dictionary = BoardFit.fit_box(free_rect, wide, BOARD, 0.0, 0.0, 10.0)
	_check("context and cap are parameters (0 context: box fills the width)", _near(float(other_context["zoom"]), 1180.0 / 1400.0, 1e-9), str(other_context["zoom"]))

	print("\n-- (why) the pre-T14 math: whole window, model centres only --")
	# A firing line of models 1100 px wide (centres 300..1400 at y 1200, 32mm bases).
	var old_bw := 1100.0
	var old_bh := 1.0
	var old_z: float = minf(minf(1920.0 / (old_bw + 400.0), 1080.0 / (old_bh + 400.0)), 1.2)
	var old_left: float = 960.0 - (old_bw * 0.5 + 25.0) * old_z
	var old_right: float = 960.0 + (old_bw * 0.5 + 25.0) * old_z
	_check("(why) old fit put the line's ends under the game log and the right panel",
		old_left < GAME_LOG.end.x and old_right > HUD_RIGHT.position.x, "screen x %.0f..%.0f" % [old_left, old_right])
	var new_box: Rect2 = BoardFit.footprint([Vector2(300, 1200), Vector2(1400, 1200)], [25.0, 25.0])
	var fn: Dictionary = BoardFit.fit_box(free_rect, new_box, BOARD, 0.0)
	_check("the same line now fits inside the free rect", free_rect.grow(0.01).encloses(_fit_screen_rect(fn)), str(_fit_screen_rect(fn)))
	_check("(why) old fit centred a lone model on the window (960, 540), 46 px off the free area's middle",
		_near(Vector2(960, 540).distance_to(anchor), 46.1, 0.1), str(Vector2(960, 540).distance_to(anchor)))


# --------------------------------------------------------------- rotation ---

func _test_rotation() -> void:
	print("\n-- BoardFit.fit_box: rotated views --")
	var anchor: Vector2 = free_rect.get_center()
	var wide := Rect2(100, 1000, 1400, 300)
	var f90: Dictionary = BoardFit.fit_box(free_rect, wide, BOARD, PI * 0.5)
	var z90: float = f90["zoom"]
	_check("90 degrees: the extents swap -> zoom = 950 / (1400 + 400)", _near(z90, 950.0 / 1800.0, 1e-9), str(z90))
	var r90 := _fit_screen_rect(f90, PI * 0.5)
	_check("90 degrees: whole box inside the free rect", free_rect.grow(0.01).encloses(r90), str(r90))
	var c90 := _clearance(r90, free_rect)
	_check("90 degrees: 5\" above and below, centred across", _near(c90.top, 200.0 * z90) and _near(c90.bottom, 200.0 * z90) and _near(c90.left, c90.right), str(c90))
	var t90 := _view_xform(f90["view_offset"], z90, PI * 0.5)
	_check("90 degrees: the box centre lands on the anchor", (t90 * wide.get_center()).distance_to(anchor) < 0.01, str(t90 * wide.get_center()))
	_check("90 degrees: centre stays the world point, focus is it turned", (f90["center"] as Vector2).is_equal_approx(wide.get_center()) and not (f90["focus"] as Vector2).is_equal_approx(wide.get_center()))
	var f180: Dictionary = BoardFit.fit_box(free_rect, wide, BOARD, PI)
	var z0: float = BoardFit.fit_box(free_rect, wide, BOARD, 0.0)["zoom"]
	_check("180 degrees: same zoom as unrotated", _near(float(f180["zoom"]), z0, 1e-9))
	_check("180 degrees: the box centre lands on the anchor",
		(_view_xform(f180["view_offset"], float(f180["zoom"]), PI) * wide.get_center()).distance_to(anchor) < 0.01)
	var round_trip := true
	for p in [Vector2(0, 0), Vector2(1760, 2400), Vector2(120, 2300), Vector2(880, 1200)]:
		for rot in [0.0, PI * 0.5, PI, PI * 1.5]:
			var q: Vector2 = BoardFit.rotate_about_board(p, BOARD, rot)
			if BoardFit.unrotate_about_board(q, BOARD, rot).distance_to(p) > 1e-3:
				round_trip = false
			# rotate_about_board is what update_view_transform does before zoom/pan.
			if (_view_xform(Vector2.ZERO, 1.0, rot) * p).distance_to(q) > 1e-3:
				round_trip = false
	_check("rotate/unrotate_about_board are inverses and match the view transform", round_trip)
	_check("the board centre does not move under rotation", BoardFit.rotate_about_board(BOARD * 0.5, BOARD, PI * 0.5).is_equal_approx(BOARD * 0.5))


# ------------------------------------------------------------ point glide ---

func _test_point_glide_sample() -> void:
	print("\n-- BoardFit.point_glide_sample: the unit heads straight for the middle --")
	# The T14 scenario's move: looking at the bottom edge at 0.6x, Shift+F on a
	# mob at the top edge (off screen above), framed at 1.2x.
	var anchor: Vector2 = free_rect.get_center()
	var target := Vector2(810, 110)
	var from_zoom := 0.6
	var to_zoom := 1.2
	var from_offset := Vector2(880, 2250) - Vector2(960, 540) / from_zoom
	var to_offset: Vector2 = target - anchor / to_zoom
	var from_screen: Vector2 = (target - from_offset) * from_zoom
	_check("start: the unit is off screen above the window", from_screen.y < 0.0, str(from_screen))
	var s0: Dictionary = BoardFit.point_glide_sample(target, from_screen, anchor, from_zoom, to_zoom, 0.0)
	var s1: Dictionary = BoardFit.point_glide_sample(target, from_screen, anchor, from_zoom, to_zoom, 1.0)
	_check("e=0 is the start framing", _near(float(s0["zoom"]), from_zoom, 1e-9) and (s0["view_offset"] as Vector2).distance_to(from_offset) < 1e-3, str(s0))
	_check("e=1 is the fit exactly", _near(float(s1["zoom"]), to_zoom, 1e-9) and (s1["view_offset"] as Vector2).distance_to(to_offset) < 1e-3, str(s1))
	var prev_zoom := from_zoom
	var prev_dist: float = from_screen.distance_to(anchor)
	var ratios: Array = []
	var monotone := true
	var on_line := true
	var closer := true
	for i in range(1, 11):
		var e: float = float(i) / 10.0
		var s: Dictionary = BoardFit.point_glide_sample(target, from_screen, anchor, from_zoom, to_zoom, e)
		var zz: float = s["zoom"]
		if zz < prev_zoom - 1e-12:
			monotone = false
		ratios.append(zz / prev_zoom)
		prev_zoom = zz
		# Where the unit's centre really is on screen this frame.
		var screen: Vector2 = (target - (s["view_offset"] as Vector2)) * zz
		if screen.distance_to(from_screen.lerp(anchor, e)) > 1e-3:
			on_line = false
		var d: float = screen.distance_to(anchor)
		if d > prev_dist + 1e-6:
			closer = false
		prev_dist = d
	_check("zoom only ever moves toward the fit (no overshoot / bounce)", monotone)
	var even := true
	for r in ratios:
		if absf(float(r) - float(ratios[0])) > 1e-6:
			even = false
	_check("zoom changes by the same ratio each step (log space)", even, str(ratios))
	_check("the unit's centre travels a straight line on screen", on_line)
	_check("the unit's centre gets closer to the middle every step", closer)

	print("\n-- (why) the T13 anchored sample swings a unit out on a big zoom-in --")
	var z_lo := 0.12
	var z_hi := 1.2
	var start_offset := Vector2(400, 1500) - anchor / z_lo
	var start_screen: Vector2 = (target - start_offset) * z_lo
	var start_dist: float = start_screen.distance_to(anchor)
	var from_focus: Vector2 = start_offset + anchor / z_lo
	var worst_anchored := 0.0
	var worst_point := 0.0
	for i in range(1, 20):
		var e: float = float(i) / 20.0
		var a: Dictionary = BoardFit.glide_sample(from_focus, target, z_lo, z_hi, anchor, e)
		worst_anchored = maxf(worst_anchored, ((target - (a["view_offset"] as Vector2)) * float(a["zoom"])).distance_to(anchor))
		var p: Dictionary = BoardFit.point_glide_sample(target, start_screen, anchor, z_lo, z_hi, e)
		worst_point = maxf(worst_point, ((target - (p["view_offset"] as Vector2)) * float(p["zoom"])).distance_to(anchor))
	_check("(why) 10x zoom-in: the anchored sample takes the unit 1.5x+ further out than it started",
		worst_anchored > start_dist * 1.5, "start %.0f, worst %.0f" % [start_dist, worst_anchored])
	_check("the point sample never takes it further out than it started", worst_point <= start_dist + 1e-3, "start %.0f, worst %.0f" % [start_dist, worst_point])
