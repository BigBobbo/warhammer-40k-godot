extends SceneTree

# T13 — Fit-board keybind (F), design doc §1.
#
# Covers the parts of the fit-board camera that do not need a window (the
# windowed scenario tests/scenarios/visual/T13_fit_board.json drives the real F
# key against the running game):
#   - KeybindingManager: F means Fit View to Board and nothing else out of the
#     box. focus_p2_zone, which Main._process polls every frame, used to default
#     to F too and snapped the view onto Player 2's zone over every F press; it
#     is unbound now, and the real load_bindings() migrates a config saved
#     before the change — unless the player moved fit_view_board off F.
#   - BoardFit.free_rect(): the live 1920x1080 HUD (top bar, phase strip, game
#     log, right panel) leaves Rect2(340, 100, 1180, 950) for the board; hidden
#     panels give their space back; a panel moved to the other edge clips that
#     edge; panels off screen are ignored; a layout that leaves nothing falls
#     back to the whole viewport.
#   - BoardFit.fit(): the whole board lands inside the free rect, 32px in on the
#     tighter axis and centred (equal margins) on the other, measured through
#     the same transform Main.update_view_transform() draws with; a
#     quarter-turned view swaps the extents; a rect too small for the margin is
#     filled instead of going negative. The pre-T13 full-window fit put the
#     board's top edge under the 100px top bar — checked so the reason stays
#     on record.
#   - BoardFit.glide_sample(): exact end points, the anchored world point on a
#     straight line and always under the anchor, the zoom monotone at a
#     constant ratio per step (log space).
#
# Usage: godot --headless --path . -s tests/test_fit_board_camera.gd

const BoardFit = preload("res://scripts/BoardFit.gd")

const VIEWPORT := Rect2(0, 0, 1920, 1080)
const BOARD := Vector2(1760, 2400)
# Live HUD rects at 1920x1080 (read from the running game, T13 audit probe).
const TOP_BAR := Rect2(0, 0, 1920, 100)        # HUD_Bottom, anchored to the top
const PHASE_STRIP := Rect2(340, 1050, 1180, 30)
const GAME_LOG := Rect2(0, 105, 340, 975)
const HUD_RIGHT := Rect2(1520, 100, 400, 980)
const CFG_PATH := "user://t13_test_keybindings.cfg"

var passed := 0
var failed := 0


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
	print("=== T13 fit-board camera ===")
	_test_keybindings()
	_test_free_rect()
	_test_fit()
	_test_glide_sample()
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)


# --------------------------------------------------------------- bindings ---

func _new_kbm():
	var kbm = load("res://autoloads/KeybindingManager.gd").new()
	kbm._register_defaults()  # defaults only; never touches the player's config
	return kbm


func _f_event(shift: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_F
	e.shift_pressed = shift
	e.pressed = true
	return e


func _write_cfg(entries: Dictionary) -> void:
	var cfg := ConfigFile.new()
	for action_id in entries:
		var e: Dictionary = entries[action_id]
		cfg.set_value(action_id, "key", e.get("key", 0))
		cfg.set_value(action_id, "alt_key", e.get("alt_key", 0))
		cfg.set_value(action_id, "shift", e.get("shift", false))
		cfg.set_value(action_id, "ctrl", false)
		cfg.set_value(action_id, "alt", false)
		cfg.set_value(action_id, "meta", false)
	cfg.save(CFG_PATH)


func _test_keybindings() -> void:
	print("\n-- KeybindingManager: F is Fit View to Board --")
	var kbm = _new_kbm()
	var fvb: Dictionary = kbm.get_binding("fit_view_board")
	_check("fit_view_board defaults to plain F", fvb.get("key", -1) == KEY_F and not fvb.shift and not fvb.ctrl and not fvb.alt)
	var fpz: Dictionary = kbm.get_binding("focus_p2_zone")
	_check("focus_p2_zone still registered (rebindable in Settings)", fpz.size() > 0)
	_check("focus_p2_zone is unbound by default (key 0, alt 0)", fpz.get("key", -1) == 0 and fpz.get("alt_key", -1) == 0,
		"key=%s alt=%s" % [str(fpz.get("key")), str(fpz.get("alt_key"))])
	_check("focus_p2_zone default is unbound, so it reads as unmodified", fpz.get("default_key", -1) == 0 and not kbm.is_modified("focus_p2_zone"))
	var plain_f: Array = []
	for action_id in kbm.bindings:
		var b: Dictionary = kbm.bindings[action_id]
		if (b.key == KEY_F or b.alt_key == KEY_F) and not b.shift and not b.ctrl and not b.alt and not b.get("meta", false):
			plain_f.append(action_id)
	_check("fit_view_board is the only action on plain F", plain_f == ["fit_view_board"], str(plain_f))
	_check("find_conflict(F) for fit_view_board finds nothing", kbm.find_conflict("fit_view_board", KEY_F, false, false, false, false) == "")
	_check("an F press matches fit_view_board", kbm.matches_action(_f_event(), "fit_view_board"))
	_check("an F press does not match focus_p2_zone", not kbm.matches_action(_f_event(), "focus_p2_zone"))
	_check("Shift+F is still Fit View to Selection, not the board", kbm.matches_action(_f_event(true), "fit_view_selection") and not kbm.matches_action(_f_event(true), "fit_view_board"))
	kbm.free()

	print("\n-- load_bindings() migrates a pre-T13 config --")
	# save_bindings() writes every action, defaults included, so a config saved
	# before T13 holds F on both actions.
	kbm = _new_kbm()
	_write_cfg({"focus_p2_zone": {"key": KEY_F}, "fit_view_board": {"key": KEY_F}})
	kbm.load_bindings(CFG_PATH)
	_check("saved focus_p2_zone=F is cleared to unbound", kbm.get_binding("focus_p2_zone").key == 0)
	_check("saved fit_view_board=F is kept", kbm.get_binding("fit_view_board").key == KEY_F)
	_check("after migration an F press matches fit_view_board only",
		kbm.matches_action(_f_event(), "fit_view_board") and not kbm.matches_action(_f_event(), "focus_p2_zone"))
	kbm.free()

	kbm = _new_kbm()
	_write_cfg({"focus_p2_zone": {"key": KEY_F}, "fit_view_board": {"key": KEY_O}})
	kbm.load_bindings(CFG_PATH)
	_check("fit_view_board moved to O: focus_p2_zone keeps F (no collision)", kbm.get_binding("focus_p2_zone").key == KEY_F)
	_check("fit_view_board moved to O is kept", kbm.get_binding("fit_view_board").key == KEY_O)
	kbm.free()

	kbm = _new_kbm()
	_write_cfg({"focus_p2_zone": {"key": KEY_K, "shift": true}, "fit_view_board": {"key": KEY_F}})
	kbm.load_bindings(CFG_PATH)
	_check("a deliberate focus_p2_zone=Shift+K binding is kept", kbm.get_binding("focus_p2_zone").key == KEY_K and kbm.get_binding("focus_p2_zone").shift)
	kbm.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_PATH))


# -------------------------------------------------------------- free rect ---

func _test_free_rect() -> void:
	print("\n-- BoardFit.free_rect: the screen area the board can be seen in --")
	var live: Rect2 = BoardFit.free_rect(VIEWPORT, [TOP_BAR, PHASE_STRIP, GAME_LOG, HUD_RIGHT])
	_check("live 1920x1080 HUD leaves Rect2(340, 100, 1180, 950)", live.is_equal_approx(Rect2(340, 100, 1180, 950)), str(live))
	var no_log: Rect2 = BoardFit.free_rect(VIEWPORT, [TOP_BAR, PHASE_STRIP, HUD_RIGHT])
	_check("log hidden: the board gets the left side back", no_log.is_equal_approx(Rect2(0, 100, 1520, 950)), str(no_log))
	var bar_at_bottom: Rect2 = BoardFit.free_rect(VIEWPORT, [Rect2(0, 980, 1920, 100), PHASE_STRIP, GAME_LOG, HUD_RIGHT])
	_check("a full-width bar re-anchored to the bottom clips the bottom, not the top", bar_at_bottom.is_equal_approx(Rect2(340, 0, 1180, 980)), str(bar_at_bottom))
	var right_col_left: Rect2 = BoardFit.free_rect(VIEWPORT, [Rect2(0, 0, 400, 1080)])
	_check("a column on the left half clips the left edge", right_col_left.is_equal_approx(Rect2(400, 0, 1520, 1080)), str(right_col_left))
	var off_screen: Rect2 = BoardFit.free_rect(VIEWPORT, [Rect2(2000, 0, 300, 1080), Rect2(0, -200, 1920, 100)])
	_check("panels entirely off screen are ignored", off_screen.is_equal_approx(VIEWPORT), str(off_screen))
	var swallowed: Rect2 = BoardFit.free_rect(VIEWPORT, [Rect2(0, 0, 1000, 1080), Rect2(950, 0, 970, 1080)])
	_check("panels leaving no room fall back to the whole viewport", swallowed.is_equal_approx(VIEWPORT), str(swallowed))
	var ignored: Rect2 = BoardFit.free_rect(VIEWPORT, [TOP_BAR, "not a rect", null])
	_check("non-Rect2 entries are skipped", ignored.is_equal_approx(Rect2(0, 100, 1920, 980)), str(ignored))


# -------------------------------------------------------------------- fit ---

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


func _board_screen_rect(view_offset: Vector2, zoom: float, rotation: float) -> Rect2:
	var t := _view_xform(view_offset, zoom, rotation)
	var r := Rect2(t * Vector2.ZERO, Vector2.ZERO)
	for corner in [Vector2(BOARD.x, 0), Vector2(0, BOARD.y), BOARD]:
		r = r.expand(t * corner)
	return r


func _near(a: float, b: float, tol: float = 0.01) -> bool:
	return absf(a - b) <= tol


func _test_fit() -> void:
	print("\n-- BoardFit.fit: whole board, 32px margin, centred --")
	var view := Rect2(340, 100, 1180, 950)
	var fit: Dictionary = BoardFit.fit(view, BOARD, 0.0, 32.0)
	var z: float = fit["zoom"]
	_check("fit zoom = (950 - 64) / 2400 (height is the tight axis)", _near(z, 886.0 / 2400.0, 1e-6), str(z))
	_check("fit frames the board centre", (fit["center"] as Vector2).is_equal_approx(Vector2(880, 1200)))
	_check("anchor is the middle of the free rect", (fit["anchor"] as Vector2).is_equal_approx(Vector2(930, 575)))
	var vo: Vector2 = fit["view_offset"]
	var t := _view_xform(vo, z, 0.0)
	_check("the board centre lands on the anchor on screen", (t * Vector2(880, 1200)).distance_to(Vector2(930, 575)) < 0.01, str(t * Vector2(880, 1200)))
	var on_screen := _board_screen_rect(vo, z, 0.0)
	var m: Dictionary = BoardFit.margins(on_screen, view)
	_check("whole board inside the free rect", view.encloses(on_screen), "board %s view %s" % [str(on_screen), str(view)])
	_check("top margin 32px", _near(m.top, 32.0), str(m))
	_check("bottom margin 32px", _near(m.bottom, 32.0), str(m))
	_check("left margin == right margin (centred across)", _near(m.left, m.right), str(m))
	_check("left/right margins at least 32px", m.left >= 32.0 - 0.01 and m.right >= 32.0 - 0.01, str(m))

	# The pre-T13 fit used the whole window and a 32 WORLD-pixel pad.
	var old_z: float = minf(VIEWPORT.size.x / (BOARD.x + 64.0), VIEWPORT.size.y / (BOARD.y + 64.0))
	var old_vo: Vector2 = BOARD * 0.5 - VIEWPORT.size / (2.0 * old_z)
	var old_rect := _board_screen_rect(old_vo, old_z, 0.0)
	_check("(why) the pre-T13 full-window fit put the board's top edge under the 100px top bar",
		old_rect.position.y < TOP_BAR.end.y and old_rect.end.y > PHASE_STRIP.position.y, str(old_rect))

	print("\n-- BoardFit.fit: quarter-turned view --")
	var fit90: Dictionary = BoardFit.fit(view, BOARD, PI * 0.5, 32.0)
	var z90: float = fit90["zoom"]
	_check("90 degrees: the long side runs across -> zoom = (1180 - 64) / 2400", _near(z90, 1116.0 / 2400.0, 1e-6), str(z90))
	var r90 := _board_screen_rect(fit90["view_offset"], z90, PI * 0.5)
	var m90: Dictionary = BoardFit.margins(r90, view)
	_check("90 degrees: whole board inside the free rect", view.grow(0.01).encloses(r90), "board %s" % str(r90))
	_check("90 degrees: left/right margins 32px", _near(m90.left, 32.0) and _near(m90.right, 32.0), str(m90))
	_check("90 degrees: top == bottom", _near(m90.top, m90.bottom), str(m90))
	var fit180: Dictionary = BoardFit.fit(view, BOARD, PI, 32.0)
	_check("180 degrees: same zoom as unrotated", _near(float(fit180["zoom"]), z, 1e-6))
	var r180 := _board_screen_rect(fit180["view_offset"], float(fit180["zoom"]), PI)
	_check("180 degrees: whole board inside the free rect", view.grow(0.01).encloses(r180), str(r180))

	print("\n-- BoardFit.fit: rect smaller than the margins --")
	var tiny := Rect2(100, 100, 50, 40)
	var fit_tiny: Dictionary = BoardFit.fit(tiny, BOARD, 0.0, 32.0)
	var zt: float = fit_tiny["zoom"]
	_check("tiny rect: zoom stays positive", zt > 0.0, str(zt))
	var rt := _board_screen_rect(fit_tiny["view_offset"], zt, 0.0)
	_check("tiny rect: the board still fits inside it (margin dropped)", tiny.grow(0.01).encloses(rt), str(rt))


# ------------------------------------------------------------ glide sample --

func _test_glide_sample() -> void:
	print("\n-- BoardFit.glide_sample: anchored pull-back --")
	# From a zoomed-in view of the bottom-left of the board to the live fit.
	var anchor := Vector2(930, 575)
	var from_zoom := 1.2
	var to_zoom := 886.0 / 2400.0
	var from_focus := Vector2(150, 2200)
	var to_focus := Vector2(880, 1200)
	var s0: Dictionary = BoardFit.glide_sample(from_focus, to_focus, from_zoom, to_zoom, anchor, 0.0)
	var s1: Dictionary = BoardFit.glide_sample(from_focus, to_focus, from_zoom, to_zoom, anchor, 1.0)
	_check("e=0 is the start framing", _near(float(s0["zoom"]), from_zoom, 1e-9) and (s0["view_offset"] as Vector2).is_equal_approx(from_focus - anchor / from_zoom))
	_check("e=1 is the fit exactly", _near(float(s1["zoom"]), to_zoom, 1e-9) and (s1["view_offset"] as Vector2).is_equal_approx(to_focus - anchor / to_zoom))
	var prev_zoom := from_zoom
	var ratios: Array = []
	var monotone := true
	var on_line := true
	var under_anchor := true
	for i in range(1, 11):
		var e: float = float(i) / 10.0
		var s: Dictionary = BoardFit.glide_sample(from_focus, to_focus, from_zoom, to_zoom, anchor, e)
		var zz: float = s["zoom"]
		if zz > prev_zoom + 1e-12:
			monotone = false
		ratios.append(zz / prev_zoom)
		prev_zoom = zz
		var f: Vector2 = s["focus"]
		if f.distance_to(from_focus.lerp(to_focus, e)) > 1e-3:
			on_line = false
		# The anchored world point sits under the anchor every frame.
		var screen: Vector2 = (f - (s["view_offset"] as Vector2)) * zz
		if screen.distance_to(anchor) > 1e-3:
			under_anchor = false
	_check("zoom only ever moves toward the fit (no overshoot / bounce)", monotone)
	var even := true
	for r in ratios:
		if absf(float(r) - float(ratios[0])) > 1e-6:
			even = false
	_check("zoom changes by the same ratio each step (log space)", even, str(ratios))
	_check("framed world point travels in a straight line", on_line)
	_check("framed world point stays under the anchor on screen", under_anchor)
	var mid: Dictionary = BoardFit.glide_sample(from_focus, to_focus, from_zoom, to_zoom, anchor, 0.5)
	_check("halfway zoom is the geometric mean", _near(float(mid["zoom"]), sqrt(from_zoom * to_zoom), 1e-9), str(mid["zoom"]))
