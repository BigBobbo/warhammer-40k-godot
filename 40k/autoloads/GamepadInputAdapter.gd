extends Node

# GamepadInputAdapter — Phase 0 skeleton.
#
# Goal: provide a single seam where gamepad / Steam-Input events are
# translated into the same semantic actions the mouse + keyboard paths
# already fire. Phase 0 ships the infrastructure only — no controllers
# subscribe yet, so behaviour is unchanged for existing users.
#
# Activation: gated by SettingsService["input/gamepad_enabled"] (off by
# default) AND the `gamepad` feature being present, OR a joypad being
# physically connected. Activation is observable via the
# `enabled_changed(now: bool)` signal.
#
# Vocabulary (matches the design doc; do NOT rename without updating it):
#   - "action"   : a semantic verb the game cares about, e.g.
#                  "confirm", "cancel", "cycle_unit_next", "rotate_left",
#                  "end_phase", "open_radial". Always a String.
#   - "binding"  : a (button | axis+sign) tuple that fires an action.
#   - "device"   : Godot joypad device index (0 = first pad).
#
# Subscribers connect to `action_pressed(action: String)` and
# `action_released(action: String)`. Stick/axis input is exposed as a
# pollable Vector2 via `get_stick(stick_name)` — adapters that need it
# (virtual cursor, camera pan) read it each frame.

signal enabled_changed(now: bool)
signal action_pressed(action: String, device: int)
signal action_released(action: String, device: int)
signal stick_moved(stick_name: String, value: Vector2, device: int)

# --- Bindings ---------------------------------------------------------------
# button_bindings[button_index] = action_id
# Default mapping is Xbox/Deck-style face buttons. Steam Input action sets
# will override per phase at the OS layer; this adapter is the fallback for
# raw joypad input on non-Steam launches.
const DEFAULT_BUTTON_BINDINGS := {
	JOY_BUTTON_A:              "confirm",
	JOY_BUTTON_B:              "cancel",
	JOY_BUTTON_X:              "context_action",
	JOY_BUTTON_Y:              "open_radial",
	JOY_BUTTON_LEFT_SHOULDER:  "cycle_unit_prev",
	JOY_BUTTON_RIGHT_SHOULDER: "cycle_unit_next",
	JOY_BUTTON_LEFT_STICK:     "snap_cursor_to_unit",
	JOY_BUTTON_RIGHT_STICK:    "toggle_measure",
	JOY_BUTTON_BACK:           "open_menu",
	JOY_BUTTON_START:          "end_phase",
	JOY_BUTTON_DPAD_UP:        "focus_up",
	JOY_BUTTON_DPAD_DOWN:      "focus_down",
	JOY_BUTTON_DPAD_LEFT:      "focus_left",
	JOY_BUTTON_DPAD_RIGHT:     "focus_right",
}

# Axes are polled, not edge-triggered.
const STICK_DEADZONE := 0.18

var enabled: bool = false
var _button_bindings: Dictionary = DEFAULT_BUTTON_BINDINGS.duplicate()
var _last_button_seen: Dictionary = {}  # device -> last button int (debug)
var _left_stick: Vector2 = Vector2.ZERO
var _right_stick: Vector2 = Vector2.ZERO

func _ready() -> void:
	set_process(true)
	set_process_input(true)
	_refresh_enabled()
	# Hot-plug
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	print("[GamepadInputAdapter] ready (enabled=%s, joypads=%s)" % [
		str(enabled), str(Input.get_connected_joypads())
	])

func _refresh_enabled() -> void:
	var wanted := _resolve_enabled_flag()
	if wanted == enabled:
		return
	enabled = wanted
	emit_signal("enabled_changed", enabled)
	print("[GamepadInputAdapter] enabled -> %s" % str(enabled))

func _resolve_enabled_flag() -> bool:
	# Off unless either: a SettingsService flag flips it on, OR a feature
	# tag is present in the export ("gamepad" / "deck"). Phase 0 ships
	# OFF-by-default so no existing user is affected.
	var settings = get_node_or_null("/root/SettingsService")
	if settings != null and settings.has_method("get_value"):
		var v = settings.get_value("input/gamepad_enabled", null)
		if v != null:
			return bool(v)
	if OS.has_feature("gamepad") or OS.has_feature("deck"):
		return true
	return false

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	print("[GamepadInputAdapter] joy %d connected=%s" % [device, str(connected)])
	_refresh_enabled()

# --- Input pump -------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventJoypadButton:
		_handle_button(event as InputEventJoypadButton)
	# Axis motion is read in _process via Input.get_joy_axis() rather than
	# event-driven, because we need a stable per-frame value for cursor /
	# camera integration. Phase 0 still emits a debug stick_moved signal
	# below for observability.

func _handle_button(ev: InputEventJoypadButton) -> void:
	_last_button_seen[ev.device] = ev.button_index
	var action: String = String(_button_bindings.get(ev.button_index, ""))
	if action == "":
		return  # unbound button: ignored, not consumed
	if ev.pressed:
		emit_signal("action_pressed", action, ev.device)
	else:
		emit_signal("action_released", action, ev.device)

func _process(_dt: float) -> void:
	if not enabled:
		return
	var devs := Input.get_connected_joypads()
	if devs.is_empty():
		return
	# Phase 0: only watch device 0. Multi-pad / per-player support arrives
	# in Phase 2 when we wire selection cycling.
	var dev: int = int(devs[0])
	var lx := Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
	var ly := Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)
	var rx := Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y)
	var ls := _apply_deadzone(Vector2(lx, ly))
	var rs := _apply_deadzone(Vector2(rx, ry))
	if not ls.is_equal_approx(_left_stick):
		_left_stick = ls
		emit_signal("stick_moved", "left", ls, dev)
	if not rs.is_equal_approx(_right_stick):
		_right_stick = rs
		emit_signal("stick_moved", "right", rs, dev)

func _apply_deadzone(v: Vector2) -> Vector2:
	if v.length() < STICK_DEADZONE:
		return Vector2.ZERO
	return v

# --- Public API -------------------------------------------------------------

func get_stick(stick_name: String) -> Vector2:
	match stick_name:
		"left":  return _left_stick
		"right": return _right_stick
		_:       return Vector2.ZERO

func is_action_bound(action: String) -> bool:
	for v in _button_bindings.values():
		if String(v) == action:
			return true
	return false

# For tests & the scenario runner: surface what the adapter last saw on a
# device so a scenario can assert "yes, the joypad event reached the seam".
func get_last_button(device: int = 0) -> int:
	return int(_last_button_seen.get(device, -1))

func set_enabled_for_tests(v: bool) -> void:
	# Bypass SettingsService for headless scenarios.
	if v == enabled:
		return
	enabled = v
	emit_signal("enabled_changed", enabled)
	print("[GamepadInputAdapter] enabled (test override) -> %s" % str(enabled))
