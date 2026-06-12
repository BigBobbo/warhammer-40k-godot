extends SceneTree

# ISS-013: phase signal registry on PhaseControllerBase.
#
# Checks:
#   A) attach_phase connects every signal declared in phase_signal_map that
#      the phase exposes; detach_phase removes them all (count returns to
#      baseline — no leaks).
#   B) 10 attach/detach cycles leave connection counts stable (the leak the
#      old manual disconnect blocks could miss).
#   C) Re-attaching without detaching does not create duplicates.
#   D) Main.gd no longer contains a per-signal phase disconnect block.
#
# Usage: godot --headless --path . -s tests/test_iss013_signal_registry.gd

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

func _total_connections(phase, sigs: Array) -> int:
	var n := 0
	for sig in sigs:
		if phase.has_signal(sig):
			n += phase.get_signal_connection_list(sig).size()
	return n

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss013_signal_registry ===\n")

	var phase = load("res://phases/ShootingPhase.gd").new()
	root.add_child(phase)
	var controller = load("res://scripts/ShootingController.gd").new()
	root.add_child(controller)

	var map = controller.phase_signal_map()
	_check("ShootingController declares a non-trivial signal map", map.size() >= 10, str(map.size()))
	var sigs = map.keys()
	var baseline = _total_connections(phase, sigs)

	# A: attach connects, detach restores baseline
	controller.attach_phase(phase)
	var attached = _total_connections(phase, sigs)
	_check("attach_phase connected declared signals", attached >= baseline + 10,
		"baseline=%d attached=%d" % [baseline, attached])
	controller.detach_phase()
	_check("detach_phase restores baseline (no leak)",
		_total_connections(phase, sigs) == baseline)

	# B: 10 cycles stable
	for i in range(10):
		controller.attach_phase(phase)
		controller.detach_phase()
	_check("10 attach/detach cycles leave counts stable",
		_total_connections(phase, sigs) == baseline)

	# C: double attach without detach -> no duplicates
	controller.attach_phase(phase)
	controller.attach_phase(phase)
	_check("re-attach does not duplicate connections",
		_total_connections(phase, sigs) == attached,
		"now=%d expected=%d" % [_total_connections(phase, sigs), attached])
	controller.detach_phase()

	# D: Main has no per-signal phase disconnect block left
	var main_src = FileAccess.get_file_as_string("res://scripts/Main.gd")
	_check("Main.gd uses detach_phase for shooting teardown",
		main_src.find("shooting_controller.detach_phase()") != -1)
	_check("Main.gd per-signal disconnect block removed",
		main_src.find("phase_instance.unit_selected_for_shooting.disconnect") == -1)

	root.remove_child(controller)
	controller.free()
	root.remove_child(phase)
	phase.free()

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
