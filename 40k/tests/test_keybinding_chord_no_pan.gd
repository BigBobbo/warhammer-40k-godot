extends SceneTree

# LIVE-13: Ctrl+A ("select_all") shares KEY_A with the polled camera_pan_left
# binding, so holding Ctrl+A to select every model also panned the camera
# (~330 px in the live run, dragging the board out from under the models).
# KeybindingManager.is_action_pressed must not report a bare-key binding as
# held while Ctrl / Cmd is down (a chord is a different shortcut).
#
# Usage: godot --headless --path 40k --script tests/test_keybinding_chord_no_pan.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _initialize() -> void:
	await create_timer(0.2).timeout
	await _run()
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _key(kc: int, pressed: bool, ctrl: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = kc
	ev.physical_keycode = kc
	ev.pressed = pressed
	ev.ctrl_pressed = ctrl
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func _run() -> void:
	print("\n=== test_keybinding_chord_no_pan ===\n")
	var kbm = root.get_node_or_null("KeybindingManager")
	_check("KeybindingManager autoload present", kbm != null)
	if kbm == null:
		return
	if kbm.has_method("reset_to_defaults"):
		kbm.reset_to_defaults()
	_check("camera_pan_left is bound to A (precondition)", int(kbm.bindings["camera_pan_left"].key) == KEY_A, str(kbm.bindings.get("camera_pan_left", {})))
	_check("select_all is Ctrl+A (precondition)", int(kbm.bindings["select_all"].key) == KEY_A and kbm.bindings["select_all"].ctrl)
	# Bare A held -> the camera pans.
	_key(KEY_A, true)
	await process_frame
	_check("A held: camera_pan_left is pressed", kbm.is_action_pressed("camera_pan_left"))
	_key(KEY_A, false)
	await process_frame
	_check("A released: not pressed", not kbm.is_action_pressed("camera_pan_left"))
	# Ctrl held, then A (select all) -> no camera pan.
	_key(KEY_CTRL, true, true)
	_key(KEY_A, true, true)
	await process_frame
	_check("Ctrl+A held: camera_pan_left is NOT pressed (no pan while selecting all)", not kbm.is_action_pressed("camera_pan_left"))
	_check("Ctrl+A held: Ctrl-chord held bindings still read as pressed", kbm.is_action_pressed("select_all"))
	_key(KEY_A, false, true)
	_key(KEY_CTRL, false)
	await process_frame
	# Ctrl released, A pressed again -> pans again.
	_key(KEY_A, true)
	await process_frame
	_check("Ctrl released + A held: camera pans again", kbm.is_action_pressed("camera_pan_left"))
	_key(KEY_A, false)
	await process_frame
