extends SceneTree

# Shooting-phase keyboard shortcut registration (added 2026-05-05).
#
# Pins three contracts:
#
#   1. KeybindingManager registers all five `shoot_*` action ids with the
#      defaults documented in the task (Space/Enter, Esc, Tab, N, E).
#   2. KeybindingManager.matches_action() returns true for synthetic
#      InputEventKey events carrying the registered keycodes, AND the
#      get_*_display_name helpers return non-empty strings (so the
#      KeyboardShortcutOverlay can render them).
#   3. ShootingController._handle_shooting_keyboard_shortcut() dispatches
#      each event to the correct controller method. We use a thin subclass
#      that overrides the action callbacks to record which one fired,
#      which lets us verify the dispatch table without needing the full
#      UI scene tree.
#
# Usage: godot --headless --path . -s tests/test_shooting_phase_shortcuts.gd

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
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_shooting_phase_shortcuts ===\n")

	_test_actions_registered_with_defaults()
	_test_matches_action_fires_for_registered_keys()
	_test_display_names_render_for_overlay()
	_test_controller_dispatches_each_action()

	_finish()

func _finish() -> void:
	print("\n--- Result: %d passed, %d failed ---" % [passed, failed])
	if failed > 0:
		quit(1)
	else:
		quit(0)

# ---------------------------------------------------------------------------
# 1. KeybindingManager has the five shoot_* actions with default keycodes.
# ---------------------------------------------------------------------------
func _test_actions_registered_with_defaults() -> void:
	print("\n-- shoot_* actions registered with documented defaults --")
	var kbm = root.get_node("KeybindingManager")
	_check("KeybindingManager autoload available", kbm != null)
	if kbm == null:
		return

	var expected = [
		{"id": "shoot_confirm_targets",      "key": KEY_SPACE,  "alt_key": KEY_ENTER},
		{"id": "shoot_cancel_target",        "key": KEY_ESCAPE, "alt_key": 0},
		{"id": "shoot_cycle_eligible_unit",  "key": KEY_TAB,    "alt_key": 0},
		{"id": "shoot_skip_unit",            "key": KEY_N,      "alt_key": 0},
		{"id": "shoot_end_phase",            "key": KEY_E,      "alt_key": 0},
	]

	for spec in expected:
		var b = kbm.get_binding(spec["id"])
		_check("'%s' is registered" % spec["id"],
			not b.is_empty(),
			"binding dict was empty for %s" % spec["id"])
		if b.is_empty():
			continue
		_check("'%s' default key is %s" % [spec["id"], OS.get_keycode_string(spec["key"])],
			int(b.get("key", 0)) == int(spec["key"]),
			"got %d, expected %d" % [int(b.get("key", 0)), int(spec["key"])])
		_check("'%s' default alt_key is %s" % [spec["id"], OS.get_keycode_string(spec["alt_key"]) if spec["alt_key"] != 0 else "<none>"],
			int(b.get("alt_key", -1)) == int(spec["alt_key"]),
			"got %d, expected %d" % [int(b.get("alt_key", -1)), int(spec["alt_key"])])
		# All shoot_* default to no modifiers
		_check("'%s' has no default modifiers" % spec["id"],
			not bool(b.get("shift", false)) and not bool(b.get("ctrl", false)) and not bool(b.get("alt", false)),
			"got shift=%s ctrl=%s alt=%s" % [str(b.get("shift", false)), str(b.get("ctrl", false)), str(b.get("alt", false))])

# ---------------------------------------------------------------------------
# 2. matches_action() correctly identifies synthetic events.
# ---------------------------------------------------------------------------
func _test_matches_action_fires_for_registered_keys() -> void:
	print("\n-- matches_action() fires for registered keys --")
	var kbm = root.get_node("KeybindingManager")
	if kbm == null:
		return

	# shoot_confirm_targets matches both Space and Enter (alt_key)
	var ev_space = _make_event(KEY_SPACE)
	_check("Space matches shoot_confirm_targets",
		kbm.matches_action(ev_space, "shoot_confirm_targets"))
	var ev_enter = _make_event(KEY_ENTER)
	_check("Enter (alt) matches shoot_confirm_targets",
		kbm.matches_action(ev_enter, "shoot_confirm_targets"))
	# Enter does NOT match shoot_skip_unit
	_check("Enter does not match shoot_skip_unit",
		not kbm.matches_action(ev_enter, "shoot_skip_unit"))

	var ev_esc = _make_event(KEY_ESCAPE)
	_check("Escape matches shoot_cancel_target",
		kbm.matches_action(ev_esc, "shoot_cancel_target"))

	var ev_tab = _make_event(KEY_TAB)
	_check("Tab matches shoot_cycle_eligible_unit",
		kbm.matches_action(ev_tab, "shoot_cycle_eligible_unit"))

	var ev_n = _make_event(KEY_N)
	_check("N matches shoot_skip_unit",
		kbm.matches_action(ev_n, "shoot_skip_unit"))

	var ev_e = _make_event(KEY_E)
	_check("E matches shoot_end_phase",
		kbm.matches_action(ev_e, "shoot_end_phase"))

	# Negative: a modifier on a no-modifier action should NOT match
	var ev_ctrl_e = _make_event(KEY_E)
	ev_ctrl_e.ctrl_pressed = true
	_check("Ctrl+E does not match shoot_end_phase (modifier mismatch)",
		not kbm.matches_action(ev_ctrl_e, "shoot_end_phase"))

# ---------------------------------------------------------------------------
# 3. Display names render so the overlay can list them.
# ---------------------------------------------------------------------------
func _test_display_names_render_for_overlay() -> void:
	print("\n-- get_key_display_name returns rendable strings --")
	var kbm = root.get_node("KeybindingManager")
	if kbm == null:
		return

	for action_id in [
		"shoot_confirm_targets",
		"shoot_cancel_target",
		"shoot_cycle_eligible_unit",
		"shoot_skip_unit",
		"shoot_end_phase",
	]:
		var name = kbm.get_key_display_name(action_id)
		_check("'%s' display name non-empty: '%s'" % [action_id, str(name)],
			str(name) != "" and str(name) != "???")

	# shoot_confirm_targets specifically should show both Space AND Enter
	var combined = kbm.get_key_display_name("shoot_confirm_targets")
	_check("shoot_confirm_targets shows Space + Enter alt: '%s'" % combined,
		"Space" in combined and "Enter" in combined,
		"got '%s'" % combined)

# ---------------------------------------------------------------------------
# 4. ShootingController dispatches each shortcut to its callback.
#    We use an inline subclass that overrides the five callbacks to record
#    invocations, sidestepping the controller's UI-heavy _ready().
# ---------------------------------------------------------------------------
func _test_controller_dispatches_each_action() -> void:
	print("\n-- ShootingController._handle_shooting_keyboard_shortcut dispatches --")

	# The stub script extends ShootingController and overrides the action
	# callbacks. Loaded as a separate .gd file under tests/ so its source is
	# obvious to anyone reading the test.
	var StubScript = load("res://tests/helpers/shooting_shortcut_stub.gd")
	if StubScript == null:
		_check("stub script loads", false, "load returned null")
		return
	_check("stub script loads", true)

	var ctrl = StubScript.new()
	# Pre-conditions for the dispatch checks: confirm needs an active shooter
	# AND non-empty weapon_assignments; skip needs an active shooter; cancel
	# needs an active shooter; cycle and end_phase have no precondition.
	ctrl.active_shooter_id = "U_FAKE"
	ctrl.weapon_assignments = {"some_weapon": "U_TARGET"}

	# 4a. Space → _on_confirm_pressed
	ctrl._reset_recorded()
	var fired_confirm = ctrl._handle_shooting_keyboard_shortcut(_make_event(KEY_SPACE))
	_check("Space dispatch returns true", fired_confirm)
	_check("Space invokes _on_confirm_pressed",
		ctrl.recorded == "confirm",
		"got '%s'" % ctrl.recorded)

	# 4b. Enter (alt key) → _on_confirm_pressed
	ctrl._reset_recorded()
	ctrl._handle_shooting_keyboard_shortcut(_make_event(KEY_ENTER))
	_check("Enter (alt) invokes _on_confirm_pressed",
		ctrl.recorded == "confirm",
		"got '%s'" % ctrl.recorded)

	# 4c. Escape → _keyboard_deselect_shooter
	ctrl._reset_recorded()
	var fired_cancel = ctrl._handle_shooting_keyboard_shortcut(_make_event(KEY_ESCAPE))
	_check("Escape dispatch returns true", fired_cancel)
	_check("Escape invokes _keyboard_deselect_shooter",
		ctrl.recorded == "deselect",
		"got '%s'" % ctrl.recorded)

	# 4d. Tab → _keyboard_cycle_units
	ctrl._reset_recorded()
	var fired_cycle = ctrl._handle_shooting_keyboard_shortcut(_make_event(KEY_TAB))
	_check("Tab dispatch returns true", fired_cycle)
	_check("Tab invokes _keyboard_cycle_units",
		ctrl.recorded == "cycle",
		"got '%s'" % ctrl.recorded)

	# 4e. N → _keyboard_skip_unit
	ctrl._reset_recorded()
	var fired_skip = ctrl._handle_shooting_keyboard_shortcut(_make_event(KEY_N))
	_check("N dispatch returns true", fired_skip)
	_check("N invokes _keyboard_skip_unit",
		ctrl.recorded == "skip",
		"got '%s'" % ctrl.recorded)

	# 4f. E → _on_end_phase_pressed
	ctrl._reset_recorded()
	var fired_end = ctrl._handle_shooting_keyboard_shortcut(_make_event(KEY_E))
	_check("E dispatch returns true", fired_end)
	_check("E invokes _on_end_phase_pressed",
		ctrl.recorded == "end_phase",
		"got '%s'" % ctrl.recorded)

	# 4g. Confirm gating: with no weapon_assignments, Space should NOT fire
	ctrl.weapon_assignments = {}
	ctrl._reset_recorded()
	ctrl._handle_shooting_keyboard_shortcut(_make_event(KEY_SPACE))
	_check("Space without weapon_assignments does not fire confirm",
		ctrl.recorded == "",
		"got '%s'" % ctrl.recorded)

	# 4h. Skip gating: with no active_shooter_id, N should NOT fire
	ctrl.active_shooter_id = ""
	ctrl._reset_recorded()
	ctrl._handle_shooting_keyboard_shortcut(_make_event(KEY_N))
	_check("N without active_shooter_id does not fire skip",
		ctrl.recorded == "",
		"got '%s'" % ctrl.recorded)

	# 4i. End phase: NO precondition → fires regardless of shooter state
	ctrl._reset_recorded()
	ctrl._handle_shooting_keyboard_shortcut(_make_event(KEY_E))
	_check("E fires end_phase even without active shooter",
		ctrl.recorded == "end_phase",
		"got '%s'" % ctrl.recorded)

	ctrl.free()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _make_event(keycode: int) -> InputEventKey:
	var ev = InputEventKey.new()
	ev.pressed = true
	ev.keycode = keycode
	return ev
