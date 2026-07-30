extends SceneTree

# Input-mode policy regression net (owner report 2026-07-27).
#
# The game used to follow whatever device was touched LAST. On a Steam Deck the
# trackpads / back paddles / gyro surface as mouse or keyboard events, so a
# stray thumb flipped the UI out of controller mode — and because the pad text
# boost multiplies the canvas content scale, the whole screen visibly resized
# mid-game. InputDeviceManager now resolves the device ONCE at launch and locks
# it, with a player-facing override in Settings › Controller › Input Mode.
#
# Checks:
#   A) Policy resolution: pad/kbm pin their mode, auto defers to the platform
#      detector, dynamic means "no lock", garbage is rejected.
#   B) Platform detection: Steam Deck signals -> PAD, desktop/web -> KBM, and
#      the reason string is populated so the menu can show WHY.
#   C) The lock actually holds: under a locked policy no device claim (the very
#      path PadRouter/VirtualCursor and the _input observers use) can change the
#      active mode, and a controller unplug does not either. Under 'dynamic' the
#      legacy behaviour still works.
#   D) SettingsService persists/validates the policy and drives InputDeviceManager.
#   E) The automated harness keeps the legacy dynamic default (every pad_*
#      scenario synthesises joypad events and asserts is_pad_active()).
#
# The live player path is covered by the windowed scenario
# tests/scenarios/sp/input_mode_policy_lock.json; this is the fast net underneath.
#
# Usage: godot --headless --path . -s tests/test_input_mode_policy.gd

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


func _idm() -> Node:
	return root.get_node_or_null("/root/InputDeviceManager")


func _svc() -> Node:
	return root.get_node_or_null("/root/SettingsService")


func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_input_mode_policy ===\n")

	var idm := _idm()
	if idm == null:
		print("  FAIL: InputDeviceManager autoload missing")
		quit(1)
		return

	var original_policy: String = str(idm.mode_policy)
	var original_saved: String = str(_svc().input_mode_policy) if _svc() != null else "auto"

	_test_harness_default(idm)
	_test_policy_resolution(idm)
	_test_platform_detection(idm)
	_test_lock_holds(idm)
	_test_settings_service(idm)

	# Leave the process (and user://settings.cfg) as we found it.
	if _svc() != null:
		_svc().set_input_mode_policy(original_saved)
	idm.apply_mode_policy(original_policy)

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)


# A/E: the harness carve-out ---------------------------------------------------

func _test_harness_default(idm: Node) -> void:
	print("-- harness default --")
	# This file runs via `-s`, which InputDeviceManager treats as the automated
	# harness: the ~65 pad_* windowed scenarios drive the pad by synthesising
	# joypad events and would all break under a launch-time lock.
	_check("harness pins the policy to 'dynamic'", str(idm.mode_policy) == "dynamic",
		"got %s" % str(idm.mode_policy))
	_check("dynamic is not locked", not idm.is_mode_locked())


# A: policy resolution ---------------------------------------------------------

func _test_policy_resolution(idm: Node) -> void:
	print("-- policy resolution --")
	_check("POLICIES lists all four", idm.POLICIES == ["auto", "pad", "kbm", "dynamic"],
		str(idm.POLICIES))
	_check("'pad' resolves to PAD", idm.resolve_policy_mode("pad") == idm.InputMode.PAD)
	_check("'kbm' resolves to KBM", idm.resolve_policy_mode("kbm") == idm.InputMode.KBM)
	_check("'dynamic' resolves to -1 (no lock)", idm.resolve_policy_mode("dynamic") == -1)
	_check("'auto' defers to the platform detector",
		idm.resolve_policy_mode("auto") == idm.detect_platform_mode())

	var before: String = str(idm.mode_policy)
	idm.apply_mode_policy("nonsense")
	_check("an unknown policy is ignored", str(idm.mode_policy) == before,
		"policy became %s" % str(idm.mode_policy))


# B: platform detection --------------------------------------------------------

func _test_platform_detection(idm: Node) -> void:
	print("-- platform detection --")
	var had_env := OS.get_environment("SteamDeck")

	OS.set_environment("SteamDeck", "")
	_check("a plain desktop is not a Steam Deck", idm.steam_deck_reason() == "",
		"reason: %s" % idm.steam_deck_reason())
	_check("desktop auto-detects mouse & keyboard",
		idm.detect_platform_mode() == idm.InputMode.KBM)
	_check("the detection reason is populated", str(idm.detected_platform) != "")

	# Steam exports SteamDeck=1 into the game's environment on Deck hardware.
	OS.set_environment("SteamDeck", "1")
	_check("SteamDeck=1 is recognised", idm.steam_deck_reason() == "SteamDeck=1",
		"reason: %s" % idm.steam_deck_reason())
	_check("a Steam Deck auto-detects the controller",
		idm.detect_platform_mode() == idm.InputMode.PAD)
	_check("the Deck reason reaches the UI string",
		str(idm.detected_platform).contains("Steam Deck"), str(idm.detected_platform))

	OS.set_environment("SteamDeck", had_env)
	idm.detect_platform_mode()  # restore detected_platform to the real value


# C: the lock actually holds ---------------------------------------------------

func _test_lock_holds(idm: Node) -> void:
	print("-- lock behaviour --")

	idm.apply_mode_policy("pad")
	_check("'pad' locks the mode", idm.is_mode_locked())
	_check("'pad' activates the controller layout", idm.is_pad_active())
	# _claim is what BOTH the _input observers (mouse motion / key press) and the
	# explicit claim_pad() call sites funnel through.
	idm._claim(idm.InputMode.KBM)
	_check("a KBM claim cannot break the pad lock", idm.is_pad_active())
	idm._on_joy_connection_changed(0, false)
	_check("unplugging the last pad cannot break the pad lock", idm.is_pad_active())

	idm.apply_mode_policy("kbm")
	_check("'kbm' locks to mouse & keyboard", not idm.is_pad_active())
	idm.claim_pad()
	_check("a pad claim cannot break the KBM lock", not idm.is_pad_active())

	idm.apply_mode_policy("dynamic")
	_check("'dynamic' unlocks", not idm.is_mode_locked())
	idm.claim_pad()
	_check("'dynamic' still follows a pad claim", idm.is_pad_active())
	idm._claim(idm.InputMode.KBM)
	_check("'dynamic' still follows a KBM claim", not idm.is_pad_active())


# D: SettingsService wiring ----------------------------------------------------

func _test_settings_service(idm: Node) -> void:
	print("-- SettingsService --")
	var svc := _svc()
	if svc == null:
		_check("SettingsService autoload present", false)
		return

	svc.set_input_mode_policy("pad")
	_check("the setting drives InputDeviceManager", str(idm.mode_policy) == "pad",
		str(idm.mode_policy))
	_check("the setting is stored", str(svc.input_mode_policy) == "pad")

	svc.set_input_mode_policy("garbage")
	_check("an invalid setting is rejected", str(svc.input_mode_policy) == "pad")

	# Round-trip through the config file the same way a relaunch would.
	svc.set_input_mode_policy("kbm")
	var cfg := ConfigFile.new()
	var err := cfg.load(svc.SETTINGS_FILE_PATH)
	_check("settings.cfg is readable", err == OK, "error %d" % err)
	_check("the policy is persisted",
		str(cfg.get_value("controls", "input_mode_policy", "")) == "kbm",
		str(cfg.get_value("controls", "input_mode_policy", "")))
