extends SceneTree

# Pin test for the "game freezes waiting for opponent's Heroic Intervention
# decision" bug (branch: game-freeze-heroic-intervention).
#
# ROOT CAUSE: Main.gd's reactive-stratagem overlay uses MOUSE_FILTER_STOP to
# block ALL input while a reactive window (Heroic Intervention, Fire Overwatch,
# Counter-Offensive, Rapid Ingress...) is open. It was hidden ONLY by the
# controller that owned the decision dialog (e.g. ChargeController on a Heroic
# Intervention decline/use). If that callback was orphaned — the phase advanced
# and tore the controller down while the window was still up — the overlay
# stayed visible forever and permanently blocked input, even though the game
# logic had moved on (observed stuck across a whole battle round).
#
# FIX (Main.gd): two independent safety nets, both anchored below:
#   1. A one-shot safety Timer that force-hides the overlay a few seconds after
#      every reactive window's own auto-decline elapses.
#   2. _on_phase_changed() force-hides any overlay still up on a phase change —
#      a reactive window never legitimately spans a phase transition.
#
# This is a source-shape regression net (per the project's "pin tests are not
# validation" note); the live end-to-end validation was done against the running
# windowed UI. This test just catches a silent revert of the safety nets.
#
# Usage: godot --headless --path . -s tests/test_reactive_overlay_freeze_pin.gd

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
	print("\n=== test_reactive_overlay_freeze_pin ===\n")
	_run_tests()
	print("\n=== %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _read(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var src = f.get_as_text()
	f.close()
	return src

func _run_tests():
	var src = _read("res://scripts/Main.gd")
	_check("Main.gd is readable", src != "")

	# 1. Safety timer must exist, be armed on show, and stopped on hide.
	_check("safety timer field declared",
		"_reactive_stratagem_safety_timer" in src)
	_check("safety timeout constant declared",
		"REACTIVE_STRATAGEM_SAFETY_SECONDS" in src)
	_check("safety timer created in setup",
		"ReactiveStratagemSafetyTimer" in src)
	_check("safety timeout handler defined",
		"func _on_reactive_stratagem_safety_timeout" in src)
	_check("handler force-hides the overlay",
		"_on_reactive_stratagem_safety_timeout" in src
		and "hide_reactive_stratagem_waiting()" in src)

	# The show path must (re)arm the timer; the hide path must stop it.
	var show_idx = src.find("func show_reactive_stratagem_waiting")
	var hide_idx = src.find("func hide_reactive_stratagem_waiting")
	var timeout_idx = src.find("func _on_reactive_stratagem_safety_timeout")
	_check("show/hide functions present", show_idx != -1 and hide_idx != -1)
	if show_idx != -1 and hide_idx != -1:
		var show_body = src.substr(show_idx, hide_idx - show_idx)
		_check("show arms safety timer",
			"_reactive_stratagem_safety_timer.start" in show_body,
			"show_reactive_stratagem_waiting must (re)arm the safety timer")
		var hide_end = timeout_idx if timeout_idx > hide_idx else src.length()
		var hide_body = src.substr(hide_idx, hide_end - hide_idx)
		_check("hide stops safety timer",
			"_reactive_stratagem_safety_timer.stop" in hide_body,
			"hide_reactive_stratagem_waiting must cancel the safety timer")

	# 2. Phase change must clear a lingering overlay.
	var pc_idx = src.find("func _on_phase_changed")
	_check("_on_phase_changed present", pc_idx != -1)
	if pc_idx != -1:
		# grab a generous slice of the handler body
		var pc_body = src.substr(pc_idx, 3000)
		_check("phase change clears pending overlay",
			"_reactive_stratagem_pending" in pc_body
			and "hide_reactive_stratagem_waiting()" in pc_body,
			"_on_phase_changed must force-hide a still-pending reactive overlay")
