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

enum State { IDLE, PENDING, LEFT_DOWN, RIGHT_DOWN, SCROLLING, GESTURE }

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

# Counters for live validation (read via the MCP bridge).
var stats := {"taps": 0, "drags": 0, "long_presses": 0, "pans": 0, "zooms": 0, "scrolls": 0, "back": 0}

var _toolbar_layer: CanvasLayer = null
var _toolbar: PanelContainer = null
var _rclick_button: Button = null


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
	if on:
		_ensure_toolbar()
	if _toolbar_layer:
		_toolbar_layer.visible = on and _in_battle_scene()
	print("[TouchInputAdapter] touch mode %s (engine mouse emulation %s)"
		% ["ENABLED" if on else "disabled", "off" if on else "on"])
	touch_mode_changed.emit(on)


func _reset_state() -> void:
	_touches.clear()
	_primary_index = -1
	state = State.IDLE
	_scroll_target = null


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
			_begin_gesture()
		return

	# Released.
	_touches.erase(ev.index)
	if state == State.GESTURE:
		if _touches.is_empty():
			print("[TouchInputAdapter] gesture end")
			state = State.IDLE
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
	_reset_state()


func _on_drag(ev: InputEventScreenDrag) -> void:
	if not _touches.has(ev.index):
		return
	_touches[ev.index] = ev.position
	if state == State.GESTURE:
		_update_gesture()
		return
	if ev.index != _primary_index:
		return
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


func _process(_delta: float) -> void:
	if not enabled:
		return
	if _toolbar_layer:
		var want := _in_battle_scene()
		if _toolbar_layer.visible != want:
			_toolbar_layer.visible = want
	if state == State.PENDING and _touches.size() == 1 \
			and _now() - _start_time >= LONG_PRESS_SEC \
			and _last_pos.distance_to(_start_pos) < DRAG_SLOP_PX:
		state = State.RIGHT_DOWN
		stats.long_presses += 1
		Input.vibrate_handheld(25)
		_emit_button(MOUSE_BUTTON_RIGHT, true, _start_pos)
		print("[TouchInputAdapter] long-press -> right press at %s" % str(_start_pos))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and enabled:
		# Android back: behave like Esc (close dialog / open pause menu) rather
		# than killing the app mid-battle (quit_on_go_back is off in project.godot).
		stats.back += 1
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
	state = State.GESTURE
	var pts := _two_points()
	_gesture_centroid = (pts[0] + pts[1]) * 0.5
	_gesture_distance = maxf(pts[0].distance_to(pts[1]), 1.0)
	_gesture_over_ui = get_viewport().gui_get_hovered_control() != null
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
	var st := get_viewport().get_screen_transform()
	_sync_cursor(st * pos)
	var m := InputEventMouseMotion.new()
	m.position = st * pos
	m.global_position = st * pos
	m.relative = st.basis_xform(rel)
	m.button_mask = mask
	Input.parse_input_event(m)


func _emit_button(button: MouseButton, pressed: bool, pos: Vector2, double := false) -> void:
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


## Canvas position of a toolbar button's centre (scenario helper).
func toolbar_button_center(button_name: String) -> Vector2:
	if _toolbar == null:
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
	_tap_key(int(b.key) as Key, bool(b.get("shift", false)), bool(b.get("ctrl", false)))
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


func _find_scroll_container_at(pos: Vector2) -> ScrollContainer:
	var c := get_viewport().gui_get_hovered_control()
	while c:
		if c is ScrollContainer:
			return c as ScrollContainer
		c = c.get_parent() as Control
	return null


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

func _ensure_toolbar() -> void:
	if _toolbar_layer:
		return
	_toolbar_layer = CanvasLayer.new()
	_toolbar_layer.name = "TouchToolbarLayer"
	_toolbar_layer.layer = 90
	add_child(_toolbar_layer)

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
	_toolbar_layer.add_child(_toolbar)

	var col := HBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_toolbar.add_child(col)

	_add_tool(col, "+", "Zoom in", func(): _zoom_step(true))
	_add_tool(col, "−", "Zoom out", func(): _zoom_step(false))
	_add_tool(col, "Fit", "Fit the whole board on screen", func(): trigger_action("fit_view_board"))
	_add_tool(col, "Tape", "Measuring tape (tap again to close)", func(): trigger_action("measuring_tape"))
	_add_tool(col, "⟲", "Rotate model left (Q)", func(): trigger_action("rotate_left"))
	_add_tool(col, "⟳", "Rotate model right (E)", func(): trigger_action("rotate_right"))
	_add_tool(col, "Undo", "Undo last deployed model (Ctrl+Z)", func(): trigger_action("undo_deployment"))
	_rclick_button = _add_tool(col, "R-tap", "Right-click mode: your next touch is a right-click / right-drag (same as long-press)", Callable())
	_rclick_button.toggle_mode = true
	_rclick_button.toggled.connect(func(on: bool):
		right_click_mode = on
		print("[TouchInputAdapter] right-click mode %s" % ("ON" if on else "off")))
	_add_tool(col, "Esc", "Back / close dialog", func(): _tap_key(KEY_ESCAPE))
	_toolbar_layer.visible = enabled and _in_battle_scene()


func _add_tool(parent: Control, text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(62, 54)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22)
	b.name = "Touch_" + text.replace(" ", "_")
	if cb.is_valid():
		b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _zoom_step(zoom_in: bool) -> void:
	var main := _battle_main()
	if main:
		var center := get_viewport().get_visible_rect().size * 0.5
		main.zoom_camera_notch(zoom_in, center)
