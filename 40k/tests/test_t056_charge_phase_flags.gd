extends SceneTree

# T-056: ChargePhase._clear_phase_flags erased charged_this_turn / fights_first
# from the local snapshot on phase exit, which corrupted the subsequent Fight
# phase's fight-order computation. The audit asks for the method to be removed
# entirely.
#
# This test confirms:
#  - The method `_clear_phase_flags` no longer exists on ChargePhase.
#  - There is no remaining caller of `_clear_phase_flags` inside the script.
#
# Usage: godot --headless --path . -s tests/test_t056_charge_phase_flags.gd

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
	print("\n=== test_t056_charge_phase_flags ===\n")
	_test_method_removed()
	_test_no_remaining_callers()
	_finish()

func _test_method_removed() -> void:
	print("\n-- T-056a: ChargePhase._clear_phase_flags is gone --")
	var f := FileAccess.open("res://phases/ChargePhase.gd", FileAccess.READ)
	_check("ChargePhase.gd readable", f != null)
	if f == null:
		return
	var src = f.get_as_text()
	f.close()
	# The function definition must be gone
	_check("No `func _clear_phase_flags` definition",
		not src.contains("func _clear_phase_flags"))
	# The two flags must not be erased anywhere in this file
	_check("No 'charged_this_turn' erase in ChargePhase",
		not src.contains("erase(\"charged_this_turn\")"),
		"a residual erase would re-introduce the bug")
	_check("No 'fights_first' erase in ChargePhase",
		not src.contains("erase(\"fights_first\")"))

func _test_no_remaining_callers() -> void:
	print("\n-- T-056b: No callers of _clear_phase_flags inside ChargePhase --")
	var f := FileAccess.open("res://phases/ChargePhase.gd", FileAccess.READ)
	if f == null:
		return
	var src = f.get_as_text()
	f.close()
	_check("No call site to `_clear_phase_flags(` remains",
		not src.contains("_clear_phase_flags("))

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
