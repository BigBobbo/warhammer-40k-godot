extends Node

# M0 controller foundations (PRPs/steam_deck_controller_support.md §5/§6):
# one place that (a) registers the pad-facing InputMap bindings at runtime and
# (b) tracks which device the player used last, so glyphs / hint bar / cursor
# visibility can all key off a single `device_changed` signal.
#
# Stock Godot 4.4 ships ui_accept with NO joypad event (verified against the
# live engine — see the PRP §3.1), so without the ui_accept/ui_cancel
# additions below a pad can move focus but never press anything.
#
# The pad_* actions registered here are read by Main._process (right-stick
# camera pan, trigger zoom). They live in code rather than project.godot so
# there is one auditable registry; the KeybindingManager → InputMap migration
# (PRP §5.2.2, milestone M4) will fold both into a single rebindable table.

signal device_changed(mode: int)  # emits an InputMode value
signal pad_connection_changed(connected: bool)

enum InputMode { KBM, PAD }

var input_mode: int = InputMode.KBM

# Actions this manager registered at runtime (asserted by windowed scenarios).
var registered_actions: Array[String] = []

# Hysteresis: tiny mouse jitter (or the cursor warp from a synthetic click)
# must not steal the mode back from the pad mid-navigation. Mouse motion only
# claims KBM after this much accumulated travel; sticks only claim PAD past
# this deflection.
const MOUSE_CLAIM_PX := 12.0
const PAD_AXIS_CLAIM := 0.4

var _mouse_travel := 0.0

# Synthetic-mouse handshake (M1): the VirtualCursor drives the REAL pointer
# (warp + parsed events), and warp_mouse also makes the OS emit a genuine
# motion event. Without this window the device tracker would read the
# cursor's own output as "the player touched the mouse" and instantly park
# it. Real mouse use outlasts the window (no warps happen without stick
# input), so a human grabbing the mouse still takes over within ~0.15 s.
var _ignore_mouse_until_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_pad_bindings()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	get_tree().node_added.connect(_on_tree_node_added)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		print("[InputDeviceManager] Joypad(s) present at startup: %s" % str(pads))
	print("[InputDeviceManager] Ready — %d pad actions registered, mode=KBM" % registered_actions.size())


func note_synthetic_mouse(window_ms: int = 150) -> void:
	_ignore_mouse_until_ms = Time.get_ticks_msec() + window_ms


func is_pad_active() -> bool:
	return input_mode == InputMode.PAD


# Scenario/verify seam: proves the focus-press bindings exist (windowed
# scenario pad_m0_camera asserts this).
func has_joy_ui_accept() -> bool:
	for ev in InputMap.action_get_events("ui_accept"):
		if ev is InputEventJoypadButton:
			return true
	return false


# ============================================================================
# Binding registration
# ============================================================================

func _register_pad_bindings() -> void:
	# Focus navigation: ui_up/down/left/right already carry D-pad + left stick
	# by default; only the press/cancel halves are missing.
	_add_joy_button_to_action("ui_accept", JOY_BUTTON_A)
	_add_joy_button_to_action("ui_cancel", JOY_BUTTON_B)

	# Camera: right stick pans, triggers zoom (consumed in Main._process).
	_register_axis_action("pad_camera_left", JOY_AXIS_RIGHT_X, -1.0, 0.2)
	_register_axis_action("pad_camera_right", JOY_AXIS_RIGHT_X, 1.0, 0.2)
	_register_axis_action("pad_camera_up", JOY_AXIS_RIGHT_Y, -1.0, 0.2)
	_register_axis_action("pad_camera_down", JOY_AXIS_RIGHT_Y, 1.0, 0.2)
	_register_axis_action("pad_zoom_out", JOY_AXIS_TRIGGER_LEFT, 1.0, 0.1)
	_register_axis_action("pad_zoom_in", JOY_AXIS_TRIGGER_RIGHT, 1.0, 0.1)

	# Virtual cursor: left stick (consumed in VirtualCursor._process). M1.
	_register_axis_action("pad_cursor_left", JOY_AXIS_LEFT_X, -1.0, 0.15)
	_register_axis_action("pad_cursor_right", JOY_AXIS_LEFT_X, 1.0, 0.15)
	_register_axis_action("pad_cursor_up", JOY_AXIS_LEFT_Y, -1.0, 0.15)
	_register_axis_action("pad_cursor_down", JOY_AXIS_LEFT_Y, 1.0, 0.15)

	# Menu (Start) = phase action with confirm (consumed in Main._input). M1.
	_register_button_action("pad_phase_action", JOY_BUTTON_START)

	# Probe action for propagation-proof device detection: bound to EVERY
	# joypad button. Input action states update when an event is parsed,
	# regardless of who consumes it (scene _input runs BEFORE autoloads and
	# may set_input_as_handled; exclusive dialog Windows route events into
	# their own viewport) — so _process polls this instead of trusting
	# _input propagation. Not a player-facing action.
	if not InputMap.has_action("pad_probe_buttons"):
		InputMap.add_action("pad_probe_buttons")
		for b in range(JOY_BUTTON_A, JOY_BUTTON_MAX):
			var ev := InputEventJoypadButton.new()
			ev.device = -1
			ev.button_index = b as JoyButton
			InputMap.action_add_event("pad_probe_buttons", ev)


func _add_joy_button_to_action(action: String, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		print("[InputDeviceManager] WARNING: action '%s' missing, cannot add joypad button" % action)
		return
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and ev.button_index == button:
			return  # already bound
	var ev := InputEventJoypadButton.new()
	ev.device = -1
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _register_axis_action(action: String, axis: JoyAxis, direction: float, deadzone: float) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, deadzone)
	var ev := InputEventJoypadMotion.new()
	ev.device = -1
	ev.axis = axis
	ev.axis_value = direction
	InputMap.action_add_event(action, ev)
	registered_actions.append(action)


func _register_button_action(action: String, button: JoyButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventJoypadButton.new()
	ev.device = -1
	ev.button_index = button
	InputMap.action_add_event(action, ev)
	registered_actions.append(action)


# ============================================================================
# Active-device tracking
# ============================================================================

func _process(_delta: float) -> void:
	# Propagation-proof PAD claim (see pad_probe_buttons above). just_pressed
	# catches a press+release that lives inside a single frame; the axis
	# checks catch held sticks/triggers.
	if input_mode == InputMode.PAD:
		return
	if not InputMap.has_action("pad_probe_buttons"):
		return
	if Input.is_action_just_pressed("pad_probe_buttons") or Input.is_action_pressed("pad_probe_buttons"):
		_claim(InputMode.PAD)
		return
	if Input.get_vector("pad_cursor_left", "pad_cursor_right", "pad_cursor_up", "pad_cursor_down").length() >= PAD_AXIS_CLAIM:
		_claim(InputMode.PAD)
		return
	if Input.get_vector("pad_camera_left", "pad_camera_right", "pad_camera_up", "pad_camera_down").length() >= PAD_AXIS_CLAIM:
		_claim(InputMode.PAD)
		return
	if Input.get_action_strength("pad_zoom_in") >= PAD_AXIS_CLAIM or Input.get_action_strength("pad_zoom_out") >= PAD_AXIS_CLAIM:
		_claim(InputMode.PAD)


func _input(event: InputEvent) -> void:
	# Observe only — never consumes. Runs before scene handlers (autoload order).
	if event is InputEventJoypadButton and event.pressed:
		_claim(InputMode.PAD)
	elif event is InputEventJoypadMotion and absf(event.axis_value) >= PAD_AXIS_CLAIM:
		_claim(InputMode.PAD)
	elif event is InputEventKey and event.pressed:
		_claim(InputMode.KBM)
	elif event is InputEventMouseButton and event.pressed:
		if Time.get_ticks_msec() >= _ignore_mouse_until_ms:
			_claim(InputMode.KBM)
	elif event is InputEventMouseMotion:
		if Time.get_ticks_msec() >= _ignore_mouse_until_ms:
			_mouse_travel += event.relative.length()
			if _mouse_travel >= MOUSE_CLAIM_PX:
				_claim(InputMode.KBM)


func _claim(mode: int) -> void:
	_mouse_travel = 0.0
	if mode == input_mode:
		return
	input_mode = mode
	print("[InputDeviceManager] Input mode -> %s" % ("PAD" if mode == InputMode.PAD else "KBM"))
	device_changed.emit(mode)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	print("[InputDeviceManager] Joypad %d %s" % [device, "connected" if connected else "disconnected"])
	pad_connection_changed.emit(connected)
	if not connected and Input.get_connected_joypads().is_empty() and input_mode == InputMode.PAD:
		_claim(InputMode.KBM)


# ============================================================================
# Dialog focus watcher (M1): every AcceptDialog that pops while the pad is
# active gets its confirm button focused, so A confirms and B (ui_cancel)
# dismisses without touching the mouse. Many dialogs hide the native OK in
# favour of custom buttons (§3.4 of the PRP) — fall back to the first
# focusable visible button. KBM behaviour is deliberately untouched: no
# focus is grabbed unless the pad is the active device.
# ============================================================================

func _on_tree_node_added(node: Node) -> void:
	if node is AcceptDialog:
		node.about_to_popup.connect(_on_dialog_about_to_popup.bind(node))


func _on_dialog_about_to_popup(dialog: AcceptDialog) -> void:
	if not is_pad_active():
		return
	VirtualCursor.park()
	_focus_dialog_deferred.call_deferred(dialog)


func _focus_dialog_deferred(dialog: AcceptDialog) -> void:
	# Give the _process poll a frame to claim PAD when this dialog was opened
	# by the very first pad press of the session (the press that opened it
	# may have been consumed before _input observers saw it).
	await get_tree().process_frame
	# Guard against chained activation: the A press that confirmed the
	# PREVIOUS dialog must not leak its release (or a held ui_accept) into
	# this one. Withhold focus until ui_accept is fully released.
	var guard := 0.0
	while Input.is_action_pressed("ui_accept") and guard < 0.6:
		await get_tree().process_frame
		guard += get_process_delta_time()
	if not is_instance_valid(dialog) or not dialog.visible or not is_pad_active():
		return
	var ok := dialog.get_ok_button()
	if ok != null and ok.visible:
		ok.grab_focus()
		return
	var btn := _find_confirm_button(dialog)
	if btn != null:
		btn.grab_focus()


# Prefer the confirm-ish custom button so pad-A means "proceed" — many
# dialogs order their buttons [Go Back, Confirm...] and focusing the first
# button would make A cancel. Falls back to the first focusable button.
const _CONFIRM_WORDS := ["ok", "confirm", "end", "continue", "yes", "accept", "done", "close", "roll"]

func _find_confirm_button(root: Node) -> Button:
	var candidates: Array = []
	var queue: Array = [root]
	while not queue.is_empty():
		var n: Node = queue.pop_front()
		if n is Button and n.visible and n.focus_mode != Control.FOCUS_NONE and not n.disabled:
			candidates.append(n)
		for child in n.get_children():
			queue.append(child)
	if candidates.is_empty():
		return null
	for b in candidates:
		var t := str(b.text).to_lower()
		for w in _CONFIRM_WORDS:
			if t.begins_with(w):
				return b
	return candidates[0]
