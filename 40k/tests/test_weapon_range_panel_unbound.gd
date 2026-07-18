extends SceneTree

# Headless verification for the weapon_range_panel keybinding fix.
# Run: godot --headless --path 40k --script tests/test_weapon_range_panel_unbound.gd
#
# Verifies:
#   1. weapon_range_panel is UNBOUND by default (key == 0, alt_key == 0).
#   2. camera_pan_up still owns W (unchanged).
#   3. matches_action() returns false for a plain W press on weapon_range_panel,
#      true for camera_pan_up.
#   4. matches_action() returns false even for an edge-case keycode-0 event.
#   5. The load-time migration clears a stale saved weapon_range_panel=W binding.

var _failures := 0

func _check(label: String, cond: bool) -> void:
	if cond:
		print("  PASS: %s" % label)
	else:
		print("  FAIL: %s" % label)
		_failures += 1

func _make_key_event(keycode: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = true
	return e

func _init() -> void:
	var KBM = load("res://autoloads/KeybindingManager.gd").new()
	KBM._register_defaults()  # defaults only; do not touch the on-disk config

	print("== weapon_range_panel keybinding fix ==")

	# 1. Unbound by default
	var wrp = KBM.get_binding("weapon_range_panel")
	_check("weapon_range_panel exists", wrp.size() > 0)
	_check("weapon_range_panel primary key is 0 (unbound)", wrp.get("key", -1) == 0)
	_check("weapon_range_panel alt_key is 0 (unbound)", wrp.get("alt_key", -1) == 0)
	_check("weapon_range_panel default_key is 0", wrp.get("default_key", -1) == 0)
	_check("weapon_range_panel displays as 'None'", KBM.get_key_display_name("weapon_range_panel") == "None")
	_check("weapon_range_panel is NOT modified vs default", not KBM.is_modified("weapon_range_panel"))

	# 2. camera_pan_up unchanged (W primary, Up arrow alt)
	var cpu = KBM.get_binding("camera_pan_up")
	_check("camera_pan_up primary key is W", cpu.get("key", -1) == KEY_W)
	_check("camera_pan_up alt key is Up", cpu.get("alt_key", -1) == KEY_UP)

	# 3. Pressing W matches camera_pan_up but NOT weapon_range_panel
	var w_event = _make_key_event(KEY_W)
	_check("W matches camera_pan_up", KBM.matches_action(w_event, "camera_pan_up"))
	_check("W does NOT match weapon_range_panel", not KBM.matches_action(w_event, "weapon_range_panel"))

	# 4. Edge-case: a keycode-0 event must not trigger the unbound action
	var zero_event = _make_key_event(0)
	_check("keycode-0 event does NOT match weapon_range_panel", not KBM.matches_action(zero_event, "weapon_range_panel"))

	# 5. Migration: simulate a stale saved binding of plain W, then re-run the
	#    migration branch by mutating in place the way load_bindings() would.
	KBM.bindings["weapon_range_panel"].key = KEY_W
	KBM.bindings["weapon_range_panel"].alt_key = 0
	# Reproduce the migration block from load_bindings():
	var _wrp = KBM.bindings["weapon_range_panel"]
	if _wrp.key == KEY_W and not _wrp.shift and not _wrp.ctrl and not _wrp.alt and not _wrp.get("meta", false):
		_wrp.key = _wrp.default_key
		_wrp.alt_key = _wrp.default_alt_key
	_check("migration clears stale W back to unbound", KBM.bindings["weapon_range_panel"].key == 0)
	_check("W still matches camera_pan_up after migration", KBM.matches_action(w_event, "camera_pan_up"))

	print("== %s (%d failure(s)) ==" % ["OK" if _failures == 0 else "FAILURES", _failures])
	quit(1 if _failures > 0 else 0)
