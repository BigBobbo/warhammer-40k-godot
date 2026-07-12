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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_pad_bindings()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		print("[InputDeviceManager] Joypad(s) present at startup: %s" % str(pads))
	print("[InputDeviceManager] Ready — %d pad actions registered, mode=KBM" % registered_actions.size())


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


# ============================================================================
# Active-device tracking
# ============================================================================

func _input(event: InputEvent) -> void:
	# Observe only — never consumes. Runs before scene handlers (autoload order).
	if event is InputEventJoypadButton and event.pressed:
		_claim(InputMode.PAD)
	elif event is InputEventJoypadMotion and absf(event.axis_value) >= PAD_AXIS_CLAIM:
		_claim(InputMode.PAD)
	elif event is InputEventKey and event.pressed:
		_claim(InputMode.KBM)
	elif event is InputEventMouseButton and event.pressed:
		_claim(InputMode.KBM)
	elif event is InputEventMouseMotion:
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
