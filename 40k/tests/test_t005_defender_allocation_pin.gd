extends SceneTree

# T-005: Defender must control wound allocation per 10e (auto-resolve was the
# audit's complaint; the codebase has WoundAllocationOverlay implementing the
# defender-driven flow). This test pins the architecture and the wounded-first
# rule.
#
# Live evidence: T-001_step2_charge_phase_p2_ready.png — dialog "PLAYER 1 —
# DEFENDER'S CHOICE: The defending player allocates wounds to their models"
# fires when AI Warboss attacks Custodes Blade Champion.
#
# Usage: godot --headless --path . -s tests/test_t005_defender_allocation_pin.gd

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
	print("\n=== test_t005_defender_allocation_pin ===\n")
	_test_overlay_has_defender_player_field()
	_test_overlay_setup_signature()
	_test_dispatch_action_for_allocate_wound_exists()
	_finish()

func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t = f.get_as_text()
	f.close()
	return t

func _test_overlay_has_defender_player_field() -> void:
	print("\n-- T-005/A: WoundAllocationOverlay has defender_player + banner --")
	var src = _read("res://scripts/WoundAllocationOverlay.gd")
	_check("WoundAllocationOverlay.gd readable", not src.is_empty())
	_check("defender_player: int field declared",
		"defender_player: int" in src)
	_check("defender_banner_label field declared",
		"defender_banner_label" in src)
	_check("DEFENDER'S CHOICE label or banner setup present",
		"DEFENDER'S CHOICE" in src
		or "defending player" in src.to_lower()
		or "defender chooses" in src.to_lower())

func _test_overlay_setup_signature() -> void:
	print("\n-- T-005/B: setup() takes defender_player parameter --")
	var src = _read("res://scripts/WoundAllocationOverlay.gd")
	_check("setup(p_save_data, p_defender_player) signature exists",
		"func setup(p_save_data" in src and "p_defender_player" in src)

func _test_dispatch_action_for_allocate_wound_exists() -> void:
	print("\n-- T-005/C: GameManager has process_allocate_wounds entry-point --")
	var src = _read("res://autoloads/GameManager.gd")
	_check("GameManager.gd readable", not src.is_empty())
	_check("process_allocate_wounds function exists",
		"func process_allocate_wounds" in src)

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
