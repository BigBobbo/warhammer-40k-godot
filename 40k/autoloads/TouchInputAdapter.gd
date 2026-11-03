extends Node

## TouchInputAdapter — phone/tablet controls (Android MVP, v1.69.0).
##
## The game was built for mouse + keyboard: left-drag moves models, RIGHT-drag
## rotates them / right-click cancels, the WHEEL zooms, and ~30 hotkeys drive
## tools. Godot's built-in touch->mouse emulation only produces LEFT clicks and
## fires the press the instant a finger lands, so a two-finger pinch would start
## dragging whatever model was under the first finger.
##
## When active this autoload turns OFF Godot's emulation and does its own:
##
##   Gesture                         -> Synthetic mouse / camera action
##   ------------------------------- -------------------------------------------
##   tap                             -> left click (double-tap = double click)
##   1-finger drag                   -> left press at the touch-down point, then
##                                      left-drag (move a model, box-select, ...)
##   1-finger drag over a scroll list-> scrolls that list (ScrollContainer)
##   long-press (hold still ~0.45 s) -> RIGHT press; keep holding + drag = right-
##                                      drag (rotate a model), lift = right click
##   2-finger drag                   -> pan the board camera (scroll over a list)
##   2-finger pinch                  -> zoom the board camera about the fingers
##   Android back button             -> Esc (close dialog / menu) instead of quit
##
## Plus a small on-screen toolbar in the battle scene for the hotkeys a phone
## has no keys for (zoom, fit view, measuring tape, rotate Q/E, undo, and a
## "right-click mode" toggle as an alternative to long-press).
##
## Activation: automatically on a touchscreen mobile device (Android/iOS). For
## desktop testing: `--touch` on the command line, or set_enabled(true) from the
## MCP bridge (and feed InputEventScreenTouch/ScreenDrag via parse_input_event).
## On desktop it is inert — mouse input is untouched.

signal touch_mode_changed(enabled: bool)

const LONG_PRESS_SEC := 0.45
## Movement (logical px) before a held finger counts as a drag, not a tap/hold.
const DRAG_SLOP_PX := 14.0
const DOUBLE_TAP_SEC := 0.35
const DOUBLE_TAP_PX := 40.0

enum State { IDLE, PENDING, LEFT_DOWN, RIGHT_DOWN, SCROLLING, GESTURE, HOVER_PLACE, ROTATE_GRAB, ROTATE_HOLD }

## Long-press-and-slide rotation: horizontal finger travel per 15° step
## (slide right = clockwise, left = anticlockwise).
const ROTATE_STEP_PX := 24.0

## Toolbar label shown for a KeybindingManager action — the tutorial renders
## {key:<action>} tokens with these on touch so "press [Ctrl+A]" becomes
## "tap [All]". Actions missing here keep their key name.
const TOUCH_LABELS := {
	"zoom_in": "+", "zoom_out": "−", "fit_view_board": "Fit",
	"rotate_board": "Board", "measuring_tape": "Tape",
	"rotate_left": "⟲", "rotate_right": "⟳", "select_all": "All",
	"undo_deployment": "Undo", "datasheet_modal": "Info", "hotkey_help": "?",
}

var enabled := false
var state: int = State.IDLE
## When true the next single-finger touch is delivered as the RIGHT button
## (toolbar toggle — an alternative to long-press). Auto-clears after one use.
var right_click_mode := false

# Per-touch-index current position (logical / canvas coords).
var _touches: Dictionary = {}
var _primary_index := -1
var _start_pos := Vector2.ZERO
var _last_pos := Vector2.ZERO
var _start_time := 0.0
var _scroll_target: ScrollContainer = null
var _last_tap_time := -10.0
var _last_tap_pos := Vector2.ZERO
# Two-finger gesture baseline.
var _gesture_centroid := Vector2.ZERO
var _gesture_distance := 0.0
var _gesture_over_ui := false
var _wheel_accum := 0.0
# A second finger tapping a toolbar button while the first holds a model
# (desktop parity: hold the hull + press Q/E). -1 = none.
var _toolbar_touch_index := -1
var _toolbar_touch_button: Button = null

# Counters for live validation (read via the MCP bridge).
var stats := {"rotate_grabs": 0, "rotate_steps": 0, "taps": 0, "drags": 0, "long_presses": 0, "pans": 0, "zooms": 0, "scrolls": 0, "back": 0, "hover_places": 0, "pickups": 0, "toolbar_second_finger": 0}

var _toolbar: PanelContainer = null
var _rclick_button: Button = null
var _help_layer: CanvasLayer = null
var _multi_button: Button = null
var _collapse_button: Button = null
## Sticky Ctrl ("Multi" toolbar toggle): taps add to a selection — charge
## several targets, Ctrl+click extra models — the phone's Ctrl+click.
var multi_mode := false
## Pointer parking: a touch leaves the (invisible) pointer where the finger
## lifted, so tooltips and hover cards would pop up and stay over the board.
## Shortly after the last finger lifts the pointer is moved off-screen.
const PARK_DELAY_SEC := 0.35
const PARK_POS := Vector2(-4000, -4000)
var _park_at := 0.0
var parked := false
var _placement_centered_for := ""
# Motion emitted in the same frame as a button event is held back one frame
# (see _emit_motion).
var _last_button_frame := -1
var _rotate_kind := ""        # "movement" / "charge" while a long-press rotation is live
var _rotate_grab_frame := -1
var _rotate_anchor_x := 0.0
var _rotate_drop_pos := Vector2.ZERO  # canvas centre of the held model
var _pending_motion: Array = []  # [pos, rel, mask]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var force := false
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a == "--touch":
			force = true
	var mobile := OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]
	var auto := mobile and DisplayServer.is_touchscreen_available()
	print("[TouchInputAdapter] ready: os=%s mobile=%s touchscreen=%s force=%s"
		% [OS.get_name(), str(mobile), str(DisplayServer.is_touchscreen_available()), str(force)])
	get_tree().root.window_input.connect(_on_root_window_input)
	if auto or force:
		set_enabled(true)


func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	# Our own emulation replaces Godot's: with both on, every touch would
	# arrive twice (once as an instant left press from the engine).
	Input.emulate_mouse_from_touch = not on
	_reset_state()
	if is_instance_valid(_toolbar):
		_toolbar.visible = on
	print("[TouchInputAdapter] touch mode %s (engine mouse emulation %s)"
		% ["ENABLED" if on else "disabled", "off" if on else "on"])
	touch_mode_changed.emit(on)


func _reset_state() -> void:
	_touches.clear()
	_primary_index = -1
	state = State.IDLE
	_scroll_target = null
	_toolbar_touch_index = -1
	_toolbar_touch_button = null
	_rotate_kind = ""


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

## Touch is read from the ROOT WINDOW's window_input signal, not _input():
## while an embedded popup / dialog Window is open (unit context menu, reactive
## stratagem dialog, AcceptDialog...) the root viewport forwards every event
## straight into that sub-window BEFORE any _input() runs, so an autoload
## _input() never sees the finger lift — the adapter stuck in RIGHT_DOWN and
## every dialog was untouchable. window_input fires first, for every event.
## Its positions are WINDOW pixels; convert to canvas space up front so the
## rest of the adapter matches what _input handlers see.
func _on_root_window_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		var t := (event as InputEventScreenTouch).duplicate() as InputEventScreenTouch
		t.position = _to_canvas(t.position)
		_on_touch(t)
	elif event is InputEventScreenDrag:
		var d := (event as InputEventScreenDrag).duplicate() as InputEventScreenDrag
		d.position = _to_canvas(d.position)
		_on_drag(d)


func _to_canvas(window_pos: Vector2) -> Vector2:
	return get_viewport().get_screen_transform().affine_inverse() * window_pos


func _on_touch(ev: InputEventScreenTouch) -> void:
	if ev.pressed:
		_touches[ev.index] = ev.position
		if _touches.size() == 1 and state == State.IDLE:
			_primary_index = ev.index
			_park_at = 0.0
			parked = false
			_start_pos = ev.position
			_last_pos = ev.position
			_start_time = _now()
			state = State.PENDING
			# Hover-move first so hover-driven UI (stats card, highlights)
			# updates and gui_get_hovered_control() reflects this spot.
			_emit_motion(ev.position, Vector2.ZERO, 0)
			_scroll_target = null
			if right_click_mode:
				_set_right_click_mode(false)
				_emit_button(MOUSE_BUTTON_RIGHT, true, ev.position)
				state = State.RIGHT_DOWN
				stats.long_presses += 1
		elif _touches.size() == 2:
			var tb := _toolbar_button_at(ev.position)
			if tb != null and state != State.GESTURE:
				# Keep the first finger's hold alive; this finger is a button tap.
				_toolbar_touch_index = ev.index
				_toolbar_touch_button = tb
				return
			_begin_gesture()
		return

	# Released.
	_touches.erase(ev.index)
	if ev.index == _toolbar_touch_index:
		var tb := _toolbar_touch_button
		_toolbar_touch_index = -1
		_toolbar_touch_button = null
		if is_instance_valid(tb) and tb.get_global_rect().has_point(ev.position):
			stats.toolbar_second_finger += 1
			print("[TouchInputAdapter] second-finger toolbar tap: %s" % tb.name)
			if tb.toggle_mode:
				tb.button_pressed = not tb.button_pressed
			else:
				tb.pressed.emit()
		return
	if state == State.GESTURE:
		if _touches.is_empty():
			print("[TouchInputAdapter] gesture end")
			state = State.IDLE
			_park_at = _now() + PARK_DELAY_SEC
		return
	if ev.index != _primary_index:
		return
	match state:
		State.PENDING:
			var dbl := (_now() - _last_tap_time) < DOUBLE_TAP_SEC \
				and ev.position.distance_to(_last_tap_pos) < DOUBLE_TAP_PX
			_emit_button(MOUSE_BUTTON_LEFT, true, ev.position, dbl)
			_emit_button(MOUSE_BUTTON_LEFT, false, ev.position)
			_last_tap_time = -10.0 if dbl else _now()
			_last_tap_pos = ev.position
			stats.taps += 1
			print("[TouchInputAdapter] tap at %s%s" % [str(ev.position), " (double)" if dbl else ""])
		State.LEFT_DOWN:
			_emit_button(MOUSE_BUTTON_LEFT, false, ev.position)
			print("[TouchInputAdapter] drag end at %s" % str(ev.position))
		State.RIGHT_DOWN:
			_emit_button(MOUSE_BUTTON_RIGHT, false, ev.position)
			print("[TouchInputAdapter] right release at %s" % str(ev.position))
		State.SCROLLING:
			print("[TouchInputAdapter] scroll end")
		State.ROTATE_GRAB, State.ROTATE_HOLD:
			# Drop the model exactly where it stands: controllers put the model's
			# CENTRE at the release point, so release on its centre — not where
			# the finger touched the hull — and only its facing changes.
			_emit_button(MOUSE_BUTTON_LEFT, false, _rotate_drop_pos if state == State.ROTATE_HOLD else _start_pos)
			print("[TouchInputAdapter] rotate done (%d steps) — dropped in place" % stats.rotate_steps)
		State.HOVER_PLACE:
			# The ghost followed the finger; the drop happens HERE, on lift.
			_emit_button(MOUSE_BUTTON_LEFT, true, ev.position)
			_emit_button(MOUSE_BUTTON_LEFT, false, ev.position)
			stats.hover_places += 1
			print("[TouchInputAdapter] placement drop on lift at %s" % str(ev.position))
	_reset_state()
	_park_at = _now() + PARK_DELAY_SEC


func _on_drag(ev: InputEventScreenDrag) -> void:
	if not _touches.has(ev.index):
		return
	_touches[ev.index] = ev.position
	if state == State.GESTURE:
		_update_gesture()
		return
	if ev.index != _primary_index:
		return  # includes a second finger resting on a toolbar button
	var rel := ev.position - _last_pos
	_last_pos = ev.position
	match state:
		State.PENDING:
			var moved := ev.position - _start_pos
			if moved.length() < DRAG_SLOP_PX:
				return
			# Resolved now, not at touch-down: parse_input_event is buffered, so
			# the hover-move only lands a frame later.
			_scroll_target = _find_scroll_container_at(_start_pos)
			if _scroll_target and absf(moved.y) >= absf(moved.x) and _can_scroll_v(_scroll_target):
				state = State.SCROLLING
				stats.scrolls += 1
				_scroll_target.scroll_vertical -= int(moved.y)
				print("[TouchInputAdapter] scrolling %s" % _scroll_target.name)
				return
			# Ghost placement (deployment / disembark / reserves arrival): the
			# held finger only AIMS — no button goes out until it lifts, so a
			# model is never dropped mid-drag. Dragging a model of this unit
			# that is already down picks it up again (desktop: Shift+click).
			var pm := _placement_mode_at(_start_pos)
			if pm != "":
				state = State.HOVER_PLACE
				if pm == "pickup":
					stats.pickups += 1
					_tap_key_down(KEY_SHIFT, true)
					_emit_button(MOUSE_BUTTON_LEFT, true, _start_pos)
					_emit_button(MOUSE_BUTTON_LEFT, false, _start_pos)
					_tap_key_down(KEY_SHIFT, false)
					print("[TouchInputAdapter] placement: picked up placed model at %s" % str(_start_pos))
				else:
					print("[TouchInputAdapter] placement: aiming (drop on lift)")
				_emit_motion(ev.position, moved, 0)
				return
			# Press where the finger first landed so the drag picks up the
			# model under it, then catch up to the finger.
			state = State.LEFT_DOWN
			stats.drags += 1
			_emit_button(MOUSE_BUTTON_LEFT, true, _start_pos)
			_emit_motion(ev.position, moved, MOUSE_BUTTON_MASK_LEFT)
			print("[TouchInputAdapter] drag start at %s" % str(_start_pos))
		State.LEFT_DOWN:
			_emit_motion(ev.position, rel, MOUSE_BUTTON_MASK_LEFT)
		State.RIGHT_DOWN:
			_emit_motion(ev.position, rel, MOUSE_BUTTON_MASK_RIGHT)
		State.SCROLLING:
			if is_instance_valid(_scroll_target):
				_scroll_target.scroll_vertical -= int(rel.y)
		State.HOVER_PLACE:
			_emit_motion(ev.position, rel, 0)
		State.ROTATE_HOLD:
			# No motion goes out: the model stays where it is and only turns.
			var dx := ev.position.x - _rotate_anchor_x
			while absf(dx) >= ROTATE_STEP_PX:
				var cw := dx > 0.0
				trigger_action("rotate_right" if cw else "rotate_left")
				stats.rotate_steps += 1
				_rotate_anchor_x += ROTATE_STEP_PX if cw else -ROTATE_STEP_PX
				dx = ev.position.x - _rotate_anchor_x


func _process(_delta: float) -> void:
	if not enabled:
		return
	_flush_pending_motion()
	if state == State.IDLE and _touches.is_empty():
		_tick_parking()
	# The toolbar lives INSIDE the battle scene (built per scene, see
	# _build_toolbar) so it is rebuilt whenever a new battle scene loads.
	var bm := _battle_main()
	if bm != null and (not is_instance_valid(_toolbar) or _toolbar.get_parent() != bm):
		_build_toolbar(bm)
	if state == State.ROTATE_GRAB and Engine.get_process_frames() > _rotate_grab_frame + 1:
		if _is_holding_model(_rotate_kind):
			state = State.ROTATE_HOLD
			_rotate_anchor_x = _last_pos.x
			_rotate_drop_pos = _held_model_centre_canvas(_rotate_kind)
			stats.rotate_grabs += 1
			print("[TouchInputAdapter] rotate mode: slide left/right to turn (%d px per 15 deg)" % int(ROTATE_STEP_PX))
		else:
			# Nothing got picked up (e.g. the move hasn't started): undo the
			# press and behave like a plain long-press (right-click).
			_emit_button(MOUSE_BUTTON_LEFT, false, _start_pos)
			_emit_button(MOUSE_BUTTON_RIGHT, true, _start_pos)
			state = State.RIGHT_DOWN
			print("[TouchInputAdapter] rotate grab found nothing held -> right-click")
	if state == State.PENDING and _touches.size() == 1 \
			and _now() - _start_time >= LONG_PRESS_SEC \
			and _last_pos.distance_to(_start_pos) < DRAG_SLOP_PX \
			and _placement_mode_at(_start_pos) == "":
		# (No long-press while aiming a placement ghost: players rest a finger
		# on the board while they line a model up.)
		var rk := _rotate_grab_target(_start_pos)
		if rk != "":
			# A model that can turn (vehicle / non-round base) of the unit being
			# moved or charged: grab it with a LEFT press — rotation in every
			# controller only acts on a HELD model — then slide to turn it.
			# Desktop equivalent: hold the model + Q/E (or left+right drag).
			state = State.ROTATE_GRAB
			_rotate_kind = rk
			_rotate_grab_frame = Engine.get_process_frames()
			stats.long_presses += 1
			Input.vibrate_handheld(25)
			_emit_button(MOUSE_BUTTON_LEFT, true, _start_pos)
			print("[TouchInputAdapter] long-press on a turnable %s model -> grab at %s" % [rk, str(_start_pos)])
			return
		state = State.RIGHT_DOWN
		stats.long_presses += 1
		Input.vibrate_handheld(25)
		_emit_button(MOUSE_BUTTON_RIGHT, true, _start_pos)
		print("[TouchInputAdapter] long-press -> right press at %s" % str(_start_pos))


func _tick_parking() -> void:
	var main := _battle_main()
	# A placement ghost follows the pointer: when a unit is picked from the
	# list the pointer is over the panel (or parked), so the ghost would sit
	# hidden under the HUD. Bring it to the middle of the screen once per unit
	# so the player sees it and can turn it before aiming with a finger.
	var placing_uid := _placement_session_unit(main)
	if placing_uid == "":
		_placement_centered_for = ""
	elif placing_uid != _placement_centered_for:
		_placement_centered_for = placing_uid
		_park_at = 0.0
		if parked or get_viewport().gui_get_hovered_control() != null:
			parked = false
			var c := get_viewport().get_visible_rect().size * 0.5
			_emit_motion(c, Vector2.ZERO, 0)
			print("[TouchInputAdapter] placement ghost brought to screen centre %s" % str(c))
		return
	if _park_at <= 0.0 or _now() < _park_at:
		return
	_park_at = 0.0
	if placing_uid != "" or _tape_active():
		return  # the ghost / tape preview follows the pointer: leave it be
	parked = true
	_emit_motion(PARK_POS, Vector2.ZERO, 0)


## Unit id of an active placement session (deployment / reserves / disembark)
## — "" when none. Unlike _placement_mode_at this ignores what is under the
## finger: it is "is a ghost following the pointer at all".
func _placement_session_unit(main: Node) -> String:
	if main == null:
		return ""
	var dc = main.get("deployment_controller")
	if dc != null and dc.has_method("is_placing") and dc.is_placing():
		return "deploy:" + str(dc.get("unit_id"))
	var br: Node = main.get_node_or_null("BoardRoot")
	if br != null:
		for c in br.get_children():
			var scr = c.get_script()
			if scr != null and "DisembarkController" in str(scr.resource_path) \
					and c.is_processing_unhandled_input():
				return "disembark:" + str(c.get_instance_id())
	return ""


func _tape_active() -> bool:
	var mtm = get_node_or_null("/root/MeasuringTapeManager")
	return mtm != null and bool(mtm.get("measure_mode_active"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and enabled:
		# Android back: behave like Esc (close dialog / open pause menu) rather
		# than killing the app mid-battle (quit_on_go_back is off in project.godot).
		stats.back += 1
		if is_touch_help_visible():
			toggle_touch_help()
			return
		print("[TouchInputAdapter] back button -> Esc")
		_tap_key(KEY_ESCAPE)


# ---------------------------------------------------------------------------
# Two-finger pan / pinch
# ---------------------------------------------------------------------------

func _begin_gesture() -> void:
	# Abandon whatever the first finger was doing. A press that already went
	# out must be released, or the controller would stay mid-drag.
	match state:
		State.LEFT_DOWN:
			_emit_button(MOUSE_BUTTON_LEFT, false, _last_pos)
		State.RIGHT_DOWN:
			_emit_button(MOUSE_BUTTON_RIGHT, false, _last_pos)
		State.ROTATE_GRAB:
			_emit_button(MOUSE_BUTTON_LEFT, false, _start_pos)
		State.ROTATE_HOLD:
			_emit_button(MOUSE_BUTTON_LEFT, false, _rotate_drop_pos)
	state = State.GESTURE
	var pts := _two_points()
	_gesture_centroid = (pts[0] + pts[1]) * 0.5
	_gesture_distance = maxf(pts[0].distance_to(pts[1]), 1.0)
	# Two fingers only scroll when they are over something SCROLLABLE; over
	# anything else (board, a static panel, a transient overlay) they pan /
	# zoom the camera.
	_gesture_over_ui = _scrollable_under_pointer()
	_wheel_accum = 0.0
	print("[TouchInputAdapter] gesture start centroid=%s dist=%.0f over_ui=%s"
		% [str(_gesture_centroid), _gesture_distance, str(_gesture_over_ui)])


func _update_gesture() -> void:
	if _touches.size() < 2:
		return
	var pts := _two_points()
	var c: Vector2 = (pts[0] + pts[1]) * 0.5
	var d: float = maxf(pts[0].distance_to(pts[1]), 1.0)
	var dc := c - _gesture_centroid
	var main := _battle_main()
	if _gesture_over_ui:
		# Two-finger drag over a panel = mouse wheel, so every scrollable
		# Control (lists, logs, dialogs) works without per-widget code.
		_wheel_accum += dc.y
		while absf(_wheel_accum) >= 40.0:
			var up := _wheel_accum > 0.0
			_emit_wheel(c, up)
			_wheel_accum -= 40.0 if up else -40.0
	elif main:
		if dc.length() > 0.0:
			main.touch_pan(dc)
			stats.pans += 1
		var ratio := d / _gesture_distance
		if absf(ratio - 1.0) > 0.002:
			main.touch_zoom(ratio, c)
			stats.zooms += 1
	_gesture_centroid = c
	_gesture_distance = d


func _two_points() -> Array:
	var vals := _touches.values()
	return [vals[0], vals[1]]


# ---------------------------------------------------------------------------
# Synthetic events (same screen-space convention as VirtualCursor: emit
# st * pos so Godot's screen->canvas transform delivers `pos` to handlers).
# ---------------------------------------------------------------------------

## ~48 call sites poll get_viewport().get_mouse_position() instead of reading
## event.position (deployment placement, hover cards, ghosts...). On Android
## that reads Input's position, which the parsed events below update; on a
## desktop the OS cursor is the source, so move it too (VirtualCursor does the
## same). Guarded: Android has no warp and would warn on every call.
func _sync_cursor(window_pos: Vector2) -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE_WARP):
		Input.warp_mouse(window_pos)


func _emit_motion(pos: Vector2, rel: Vector2, mask: int) -> void:
	# parse_input_event is BUFFERED but warp_mouse is immediate: a press and
	# a burst of drags in one frame would leave the OS cursor at the END of
	# the burst before the press is handled, and handlers that poll
	# get_mouse_position() (deployment pick-up, placement) would look in the
	# wrong place. So motion queued in the same frame as a button event waits
	# for the next frame (coalesced). One frame of lag is invisible.
	if Engine.get_process_frames() == _last_button_frame:
		if _pending_motion.is_empty():
			_pending_motion = [pos, rel, mask]
		else:
			_pending_motion = [pos, _pending_motion[1] + rel, mask]
		return
	_emit_motion_now(pos, rel, mask)


func _flush_pending_motion() -> void:
	if _pending_motion.is_empty() or Engine.get_process_frames() == _last_button_frame:
		return
	var pm := _pending_motion
	_pending_motion = []
	_emit_motion_now(pm[0], pm[1], pm[2])


func _emit_motion_now(pos: Vector2, rel: Vector2, mask: int) -> void:
	var st := get_viewport().get_screen_transform()
	_sync_cursor(st * pos)
	var m := InputEventMouseMotion.new()
	m.position = st * pos
	m.global_position = st * pos
	m.relative = st.basis_xform(rel)
	m.button_mask = mask
	m.ctrl_pressed = multi_mode
	Input.parse_input_event(m)


func _emit_button(button: MouseButton, pressed: bool, pos: Vector2, double := false) -> void:
	if not pressed:
		_pending_motion = []  # the release carries its own (final) position
	_last_button_frame = Engine.get_process_frames()
	var st := get_viewport().get_screen_transform()
	_sync_cursor(st * pos)
	var b := InputEventMouseButton.new()
	b.position = st * pos
	b.global_position = st * pos
	b.button_index = button
	b.pressed = pressed
	b.double_click = double
	var mask := 0
	if pressed:
		mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	b.button_mask = mask
	b.ctrl_pressed = multi_mode
	Input.parse_input_event(b)


func _emit_wheel(pos: Vector2, up: bool) -> void:
	for pressed in [true, false]:
		var st := get_viewport().get_screen_transform()
		var b := InputEventMouseButton.new()
		b.position = st * pos
		b.global_position = st * pos
		b.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		b.pressed = pressed
		b.factor = 1.0
		Input.parse_input_event(b)


func _tap_key_down(keycode: Key, pressed: bool) -> void:
	var k := InputEventKey.new()
	k.keycode = keycode
	k.physical_keycode = keycode
	k.pressed = pressed
	k.shift_pressed = pressed and keycode == KEY_SHIFT
	k.ctrl_pressed = pressed and keycode == KEY_CTRL
	Input.parse_input_event(k)


func _tap_key(keycode: Key, shift := false, ctrl := false) -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = keycode
		k.physical_keycode = keycode
		k.pressed = pressed
		k.shift_pressed = shift
		k.ctrl_pressed = ctrl
		Input.parse_input_event(k)


## Test seams for windowed scenarios / the MCP bridge: inject REAL screen-touch
## events (they travel the same DisplayServer -> root window_input path as a
## finger). Positions are canvas coords (what _input handlers see); converted
## to window pixels here so they are correct at any content scale.
func inject_touch(index: int, canvas_pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = get_viewport().get_screen_transform() * canvas_pos
	e.pressed = pressed
	Input.parse_input_event(e)


func inject_drag(index: int, canvas_pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = get_viewport().get_screen_transform() * canvas_pos
	Input.parse_input_event(e)


func inject_tap(canvas_pos: Vector2) -> void:
	inject_touch(0, canvas_pos, true)
	inject_touch(0, canvas_pos, false)


## Tap the centre of a Control by node path (handles embedded dialog Windows).
func inject_tap_node(node_path: String) -> bool:
	var c := get_tree().root.get_node_or_null(NodePath(node_path)) as Control
	if c == null or not c.is_visible_in_tree():
		push_warning("[TouchInputAdapter] inject_tap_node: %s missing/hidden" % node_path)
		return false
	var r := c.get_global_rect()
	var p := r.position + r.size * 0.5
	var w := c.get_viewport()
	if w is Window and w != get_tree().root:
		p += Vector2((w as Window).position)
	inject_tap(p)
	return true


## One finger from `a` to `b` in `steps` drag events; lift at `b` if `lift`.
func inject_swipe(a: Vector2, b: Vector2, steps: int = 10, lift: bool = true, index: int = 0) -> void:
	inject_touch(index, a, true)
	for k in range(1, steps + 1):
		inject_drag(index, a.lerp(b, float(k) / steps))
	if lift:
		inject_touch(index, b, false)


## Tap the first visible, enabled button whose text matches (exact, or
## contains when exact=false) — game UI and dialog Windows, not the toolbar.
func inject_tap_text(text: String, exact: bool = true) -> bool:
	for b in get_tree().root.find_children("*", "BaseButton", true, false):
		var bb := b as BaseButton
		if not bb.is_visible_in_tree() or bb.disabled or not ("text" in bb):
			continue
		if is_instance_valid(_toolbar) and _toolbar.is_ancestor_of(bb):
			continue
		var t := str(bb.get("text"))
		if (exact and t == text) or (not exact and text in t):
			var r := bb.get_global_rect()
			var p := r.position + r.size * 0.5
			var w := bb.get_viewport()
			if w is Window and w != get_tree().root:
				p += Vector2((w as Window).position)
			inject_tap(p)
			return true
	push_warning("[TouchInputAdapter] inject_tap_text: no button '%s'" % text)
	return false


## Two fingers from c0/c1 moving by d0/d1 over `steps` drags, then lifted.
func inject_two_finger(c0: Vector2, c1: Vector2, d0: Vector2, d1: Vector2, steps: int = 8) -> void:
	inject_touch(0, c0, true)
	inject_touch(1, c1, true)
	for k in range(1, steps + 1):
		var f := float(k) / steps
		inject_drag(0, c0 + d0 * f)
		inject_drag(1, c1 + d1 * f)
	inject_touch(0, c0 + d0, false)
	inject_touch(1, c1 + d1, false)


## Canvas position of a toolbar button's centre (scenario helper).
func toolbar_button_center(button_name: String) -> Vector2:
	if not is_instance_valid(_toolbar):
		return Vector2(-1, -1)
	var b := _toolbar.find_child(button_name, true, false) as Control
	if b == null:
		return Vector2(-1, -1)
	var r := b.get_global_rect()
	return r.position + r.size * 0.5


## Fire a KeybindingManager action as if its bound key were pressed, so the
## toolbar follows the player's rebinds and every existing handler just works.
func trigger_action(action_id: String) -> bool:
	var b: Dictionary = KeybindingManager.get_binding(action_id)
	if b.is_empty() or int(b.get("key", 0)) == 0:
		push_warning("[TouchInputAdapter] action '%s' has no key binding" % action_id)
		return false
	print("[TouchInputAdapter] toolbar -> action %s" % action_id)
	# A held sticky Ctrl would turn e.g. F into Ctrl+F and miss the binding.
	if multi_mode:
		_tap_key_down(KEY_CTRL, false)
	_tap_key(int(b.key) as Key, bool(b.get("shift", false)), bool(b.get("ctrl", false)))
	if multi_mode:
		_tap_key_down(KEY_CTRL, true)
	return true


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _battle_main() -> Node:
	var cs := get_tree().current_scene
	if cs and cs.has_method("touch_pan"):
		return cs
	return null


func _in_battle_scene() -> bool:
	return _battle_main() != null


## "" (normal input), "hover" (a placement ghost is following the pointer:
## aim with the finger, drop on lift) or "pickup" (deployment: the finger
## landed on a model of the unit being placed that is already down).
## Never a placement when the finger started on a panel/button.
func _placement_mode_at(canvas_pos: Vector2) -> String:
	var main := _battle_main()
	if main == null:
		return ""
	if get_viewport().gui_get_hovered_control() != null:
		return ""
	var dc = main.get("deployment_controller")
	if dc != null and dc.has_method("is_placing") and dc.is_placing():
		if not bool(dc.get("repositioning_model")) and dc.has_method("_get_deployed_model_at_position"):
			var br: Node2D = main.get_node_or_null("BoardRoot")
			if br != null:
				var world := br.get_global_transform_with_canvas().affine_inverse() * canvas_pos
				if not dc._get_deployed_model_at_position(world).is_empty():
					return "pickup"
		return "hover"
	var br2: Node = main.get_node_or_null("BoardRoot")
	if br2 != null:
		for c in br2.get_children():
			var scr = c.get_script()
			if scr != null and "DisembarkController" in str(scr.resource_path) \
					and c.is_processing_unhandled_input():
				return "hover"
	return ""


## "movement" / "charge" when a long-press at canvas_pos lands on a model that
## can turn and belongs to the unit currently being moved / charged; "" else
## (round-base infantry, enemy units, no active move: long-press stays a
## right-click — unit menu, cancel tape...).
func _rotate_grab_target(canvas_pos: Vector2) -> String:
	var main := _battle_main()
	if main == null or _tape_active() or get_viewport().gui_get_hovered_control() != null:
		return ""
	var br: Node2D = main.get_node_or_null("BoardRoot")
	if br == null:
		return ""
	var world := br.get_global_transform_with_canvas().affine_inverse() * canvas_pos
	var phase := int(GameState.get_current_phase())
	if phase == GameStateData.Phase.MOVEMENT:
		var mc = main.get("movement_controller")
		if mc == null or str(mc.get("active_unit_id")) == "":
			return ""
		var m: Dictionary = mc._get_model_at_position(world)
		if m.is_empty() or not mc._is_model_in_active_unit_group(str(m.get("unit_id", ""))):
			return ""
		return "movement" if mc._model_can_pivot(m) else ""
	if phase == GameStateData.Phase.CHARGE:
		var cc = main.get("charge_controller")
		if cc == null or str(cc.get("active_unit_id")) == "":
			return ""
		var cm: Dictionary = cc._get_model_at_position(world)
		return "charge" if not cm.is_empty() and _base_can_pivot(cm) else ""
	return ""


## Same rule as MovementController._model_can_pivot (any non-round base, or a
## >32mm round base with a flying stem).
func _base_can_pivot(model: Dictionary) -> bool:
	if str(model.get("base_type", "circular")) != "circular":
		return true
	return int(model.get("base_mm", 32)) > 32 and bool(model.get("flying_stem", false))


## Canvas position of the held model's centre (its current, staged position).
func _held_model_centre_canvas(kind: String) -> Vector2:
	var main := _battle_main()
	var br: Node2D = main.get_node_or_null("BoardRoot") if main else null
	if br == null:
		return _start_pos
	var world = null
	match kind:
		"movement":
			var mc = main.get("movement_controller")
			var pos = mc.selected_model.get("position") if mc else null
			if pos is Vector2:
				world = pos
			elif pos is Dictionary:
				world = Vector2(pos.get("x", 0.0), pos.get("y", 0.0))
		"charge":
			var cc = main.get("charge_controller")
			if cc and cc.dragging_model is Dictionary:
				var key = cc._charge_model_key(cc.dragging_model_source_unit_id, str(cc.dragging_model.get("id", "")))
				world = cc.moved_models.get(key, cc._get_model_position(cc.dragging_model))
	if world is Vector2:
		return br.get_global_transform_with_canvas() * world
	return _start_pos


func _is_holding_model(kind: String) -> bool:
	var main := _battle_main()
	if main == null:
		return false
	match kind:
		"movement":
			var mc = main.get("movement_controller")
			return mc != null and bool(mc.get("dragging_model"))
		"charge":
			var cc = main.get("charge_controller")
			return cc != null and cc.get("dragging_model") != null
	return false


func _toolbar_button_at(canvas_pos: Vector2) -> Button:
	if not is_instance_valid(_toolbar) or not _toolbar.is_visible_in_tree():
		return null
	for b in _toolbar.find_children("*", "Button", true, false):
		if (b as Control).is_visible_in_tree() and (b as Control).get_global_rect().has_point(canvas_pos):
			return b as Button
	return null


## Tutorial helper: the toolbar label for an action, or "" if none.
func touch_label_for(action_id: String) -> String:
	return str(TOUCH_LABELS.get(action_id, ""))


func _find_scroll_container_at(pos: Vector2) -> ScrollContainer:
	var c := get_viewport().gui_get_hovered_control()
	while c:
		if c is ScrollContainer:
			return c as ScrollContainer
		c = c.get_parent() as Control
	return null


func _scrollable_under_pointer() -> bool:
	var c := get_viewport().gui_get_hovered_control()
	while c:
		if c is ScrollContainer or c is ItemList or c is Tree or c is TextEdit:
			return true
		if c is RichTextLabel and (c as RichTextLabel).scroll_active:
			return true
		c = c.get_parent() as Control
	return false


func _can_scroll_v(sc: ScrollContainer) -> bool:
	var bar := sc.get_v_scroll_bar()
	return bar != null and bar.max_value - bar.page > 1.0


func _set_right_click_mode(on: bool) -> void:
	right_click_mode = on
	if _rclick_button:
		_rclick_button.button_pressed = on


# ---------------------------------------------------------------------------
# On-screen toolbar (battle scene only)
# ---------------------------------------------------------------------------

## Built as a child of the battle scene (Main is canvas layer 1, which holds
## the board, the HUD and every in-game overlay), placed right after BoardRoot
## so it draws ABOVE the board but BELOW the panels and pop-ups added after it:
## any game card that overlaps the strip (save allocation, dialogs) is drawn
## on top and gets the tap. On its own high CanvasLayer it covered the
## allocation card's "Confirm Order & Roll Saves" button.
func _build_toolbar(main: Node) -> void:
	if is_instance_valid(_toolbar):
		_toolbar.queue_free()
	_toolbar = PanelContainer.new()
	_toolbar.name = "TouchToolbar"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.1, 0.72)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(6)
	_toolbar.add_theme_stylebox_override("panel", sb)
	# Bottom-centre strip just above the phase-progress bar: the side panels
	# own the left/right edges, the board owns the middle.
	_toolbar.anchor_left = 0.5
	_toolbar.anchor_right = 0.5
	_toolbar.anchor_top = 1.0
	_toolbar.anchor_bottom = 1.0
	_toolbar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toolbar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toolbar.offset_bottom = -40
	_toolbar.mouse_filter = Control.MOUSE_FILTER_PASS
	main.add_child(_toolbar)
	var br := main.get_node_or_null("BoardRoot")
	if br != null:
		main.move_child(_toolbar, br.get_index() + 1)

	var col := HBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_toolbar.add_child(col)

	_collapse_button = _add_tool(col, "▾", "Hide the touch toolbar (tap again to bring it back)", func(): set_toolbar_collapsed(not toolbar_collapsed))
	_collapse_button.name = "Touch_Collapse"
	_add_tool(col, "+", "Zoom in", func(): _zoom_step(true))
	_add_tool(col, "−", "Zoom out", func(): _zoom_step(false))
	_add_tool(col, "Fit", "Fit the whole board on screen", func(): trigger_action("fit_view_board"))
	_add_tool(col, "Board", "Rotate the board view 90°", func(): _rotate_board())
	_add_tool(col, "Tape", "Measuring tape (tap again to close)", func(): trigger_action("measuring_tape"))
	_add_tool(col, "⟲", "Rotate model left 15° (hold the model, or have it selected)", func(): _rotate_model("rotate_left"))
	_add_tool(col, "⟳", "Rotate model right 15° (hold the model, or have it selected)", func(): _rotate_model("rotate_right"))
	_add_tool(col, "All", "Select every model in the active unit (Ctrl+A)", func(): trigger_action("select_all"))
	_multi_button = _add_tool(col, "Multi", "Sticky Ctrl: while on, each tap ADDS to the selection — charge several targets, pick extra models (Ctrl+click)", Callable())
	_multi_button.toggle_mode = true
	_multi_button.toggled.connect(func(on: bool): set_multi_mode(on))
	_add_tool(col, "Undo", "Undo last deployed model (Ctrl+Z)", func(): trigger_action("undo_deployment"))
	_add_tool(col, "Info", "Open the selected unit's datasheet", func(): trigger_action("datasheet_modal"))
	_rclick_button = _add_tool(col, "R-tap", "Right-click mode: your next touch is a right-click / right-drag (same as long-press)", Callable())
	_rclick_button.toggle_mode = true
	_rclick_button.toggled.connect(func(on: bool):
		right_click_mode = on
		print("[TouchInputAdapter] right-click mode %s" % ("ON" if on else "off")))
	_add_tool(col, "?", "Touch controls cheat sheet", func(): toggle_touch_help())
	_add_tool(col, "Esc", "Back / close dialog", func(): _tap_key(KEY_ESCAPE))
	_toolbar.visible = enabled
	if toolbar_collapsed:
		set_toolbar_collapsed(true)
	if multi_mode and _multi_button:
		_multi_button.set_pressed_no_signal(true)
	print("[TouchInputAdapter] toolbar built in %s at index %d" % [main.name, _toolbar.get_index()])


func _add_tool(parent: Control, text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(54, 54)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22)
	b.name = "Touch_" + {"?": "Help", "+": "ZoomIn", "−": "ZoomOut", "⟲": "RotL", "⟳": "RotR"}.get(text, text.replace(" ", "_").replace("-", "_"))
	if cb.is_valid():
		b.pressed.connect(cb)
	parent.add_child(b)
	return b


## The Board button calls the camera directly: its V key is ALSO bound to
## toggle_vp_timeline, which Main._input checks first, so a synthesized V
## opens the VP timeline instead of turning the board.
func _rotate_board() -> void:
	var main := _battle_main()
	if main and main.has_method("rotate_board_view"):
		main.rotate_board_view(PI / 2.0)


## Rotate keys go out as Q/E so every controller (deploy, move, charge, fight)
## handles them as usual — except in the Shooting phase, where E is also
## "End Shooting Phase" and nothing can be turned anyway.
func _rotate_model(action_id: String) -> void:
	if int(GameState.get_current_phase()) == GameStateData.Phase.SHOOTING:
		print("[TouchInputAdapter] %s ignored in the Shooting phase (E = End Shooting Phase)" % action_id)
		return
	trigger_action(action_id)


func _zoom_step(zoom_in: bool) -> void:
	var main := _battle_main()
	if main:
		var center := get_viewport().get_visible_rect().size * 0.5
		main.zoom_camera_notch(zoom_in, center)


# ---------------------------------------------------------------------------
# Touch cheat sheet ("?" button) — the phone's answer to the hotkey overlay.
# ---------------------------------------------------------------------------

const TOUCH_HELP_TEXT := """[b]TOUCH CONTROLS[/b]

[b]Tap[/b] — click a unit, button or spot
[b]Drag a model[/b] — move it (select its unit first)
[b]Hold + drag while placing[/b] — the model follows your finger and drops when you lift
[b]Drag a model you already placed[/b] — pick it up again
[b]Long-press[/b] — right-click: unit menu, cancel the tape
[b]Turn a vehicle[/b] — long-press it until it buzzes, then slide left / right (15° a step); lift to drop it in place.
    Or hold it (touch + slide a little) and tap ⟲ ⟳ with another finger
[b]Two fingers[/b] — drag to pan, pinch to zoom (drag over a list to scroll it)
[b]Back button[/b] — Esc

[b]Toolbar[/b]
[b]+ / −[/b] zoom   [b]Fit[/b] whole board   [b]Board[/b] rotate view 90°
[b]Tape[/b] measure   [b]⟲ ⟳[/b] turn a model 15° (works with a second finger while you hold it)
[b]All[/b] select the whole unit   [b]Undo[/b] last placed model   [b]Info[/b] datasheet
[b]Multi[/b] (sticky Ctrl) taps add to a selection — charge several targets, Ctrl+click
[b]R-tap[/b] next touch is a right-click   [b]Esc[/b] back / close   [b]▾[/b] hide the toolbar"""


func is_touch_help_visible() -> bool:
	return _help_layer != null and _help_layer.visible


func toggle_touch_help() -> void:
	if _help_layer == null:
		_help_layer = CanvasLayer.new()
		_help_layer.name = "TouchHelpLayer"
		_help_layer.layer = 95
		add_child(_help_layer)
		var panel := PanelContainer.new()
		panel.name = "TouchHelpPanel"
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.07, 0.07, 0.09, 0.96)
		sb.border_color = Color(0.85, 0.6, 0.25)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(10)
		sb.set_content_margin_all(18)
		panel.add_theme_stylebox_override("panel", sb)
		panel.set_anchors_preset(Control.PRESET_CENTER)
		panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		_help_layer.add_child(panel)
		var vb := VBoxContainer.new()
		vb.name = "VBox"
		vb.add_theme_constant_override("separation", 12)
		panel.add_child(vb)
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		rt.custom_minimum_size = Vector2(760, 0)
		rt.add_theme_font_size_override("normal_font_size", 20)
		rt.add_theme_font_size_override("bold_font_size", 20)
		rt.text = TOUCH_HELP_TEXT
		vb.add_child(rt)
		var close := Button.new()
		close.name = "TouchHelpClose"
		close.text = "Close"
		close.custom_minimum_size = Vector2(160, 54)
		close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		close.add_theme_font_size_override("font_size", 22)
		close.focus_mode = Control.FOCUS_NONE
		close.pressed.connect(func(): toggle_touch_help())
		vb.add_child(close)
		_help_layer.visible = false
	_help_layer.visible = not _help_layer.visible
	var hp := _help_layer.get_node_or_null("TouchHelpPanel") as Control
	if hp:
		hp.visible = _help_layer.visible  # so is_visible_in_tree() tracks it
	print("[TouchInputAdapter] touch help %s" % ("shown" if _help_layer.visible else "hidden"))


# ---------------------------------------------------------------------------
# Multi (sticky Ctrl) and toolbar collapse
# ---------------------------------------------------------------------------

func set_multi_mode(on: bool) -> void:
	if on == multi_mode:
		return
	multi_mode = on
	_tap_key_down(KEY_CTRL, on)
	if _multi_button and _multi_button.button_pressed != on:
		_multi_button.set_pressed_no_signal(on)
	print("[TouchInputAdapter] multi (sticky Ctrl) %s" % ("ON" if on else "off"))


var toolbar_collapsed := false


## Collapse the toolbar to its handle so it never hides bottom-centre game UI
## (save-allocation card, dialogs). The handle stays; tap it to expand.
func set_toolbar_collapsed(on: bool) -> void:
	toolbar_collapsed = on
	if not is_instance_valid(_toolbar):
		return
	for b in _toolbar.find_children("*", "Button", true, false):
		if b != _collapse_button:
			(b as Control).visible = not on
	if _collapse_button:
		_collapse_button.text = "▴ Tools" if on else "▾"
		_collapse_button.custom_minimum_size = Vector2(110 if on else 54, 54)
	_toolbar.reset_size()
	_recentre_toolbar.call_deferred()
	print("[TouchInputAdapter] toolbar %s" % ("collapsed" if on else "expanded"))


func _recentre_toolbar() -> void:
	if not is_instance_valid(_toolbar):
		return
	var w := _toolbar.get_combined_minimum_size().x
	_toolbar.offset_left = -w * 0.5
	_toolbar.offset_right = w * 0.5
