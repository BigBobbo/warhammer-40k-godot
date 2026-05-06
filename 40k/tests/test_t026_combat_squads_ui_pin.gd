extends SceneTree

# T-026: Combat Squads / Patrol Squad UI integration with the existing
# GameState.split_unit_at_deployment helper.
#
# Pins:
# - DeploymentController emits unit_split_completed signal
# - DeploymentController.begin_deploy calls _maybe_offer_combat_squad_split
# - _maybe_offer_combat_squad_split shows a ConfirmationDialog with Split / Deploy as 10
# - Confirmation calls GameState.split_unit_at_deployment and emits the signal
# - Main.gd connects unit_split_completed → refresh_unit_list
#
# Usage: godot --headless --path . -s tests/test_t026_combat_squads_ui_pin.gd

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
	print("\n=== test_t026_combat_squads_ui_pin ===\n")
	_test_helper_present()
	_test_deployment_controller_wired()
	_test_main_gd_listens()
	_finish()


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t = f.get_as_text()
	f.close()
	return t


func _test_helper_present() -> void:
	print("\n-- T-026/A: GameState.split_unit_at_deployment is the canonical splitter --")
	var src = _read("res://autoloads/GameState.gd")
	_check("GameState.gd readable", not src.is_empty())
	_check("split_unit_at_deployment defined",
		"func split_unit_at_deployment(source_unit_id: String) -> String" in src)
	_check("Combat Squads / Patrol Squad eligibility check",
		"\"Combat Squads\", \"Patrol Squad\"" in src or "Combat Squads" in src and "Patrol Squad" in src)
	_check("requires UNDEPLOYED status",
		"UnitStatus.UNDEPLOYED" in src and "split_unit_at_deployment" in src)
	_check("requires 10 alive models",
		"alive_count != 10" in src or "must be exactly 10" in src)


func _test_deployment_controller_wired() -> void:
	print("\n-- T-026/B: DeploymentController offers split before deploy --")
	var src = _read("res://scripts/DeploymentController.gd")
	_check("DeploymentController.gd readable", not src.is_empty())
	_check("unit_split_completed signal declared",
		"signal unit_split_completed(source_unit_id: String, sibling_unit_id: String)" in src)
	_check("begin_deploy calls _maybe_offer_combat_squad_split",
		"_maybe_offer_combat_squad_split(_unit_id)" in src)
	_check("split offer shows ConfirmationDialog",
		"ConfirmationDialog.new()" in src and "Split Unit" in src)
	_check("OK button labelled Split / Cancel labelled Deploy as 10",
		"\"Split\"" in src and "Deploy as 10" in src)
	_check("confirm callback calls GameState.split_unit_at_deployment",
		"GameState.split_unit_at_deployment" in src)
	_check("emits unit_split_completed after split",
		"emit_signal(\"unit_split_completed\"" in src)
	_check("declined units bookkeeping",
		"_split_declined_units" in src)


func _test_main_gd_listens() -> void:
	print("\n-- T-026/C: Main.gd reacts to unit_split_completed --")
	var src = _read("res://scripts/Main.gd")
	_check("Main.gd readable", not src.is_empty())
	_check("unit_split_completed connected",
		"unit_split_completed.connect(_on_unit_split_completed)" in src)
	_check("_on_unit_split_completed handler defined",
		"func _on_unit_split_completed(source_unit_id: String, sibling_unit_id: String)" in src)
	_check("handler refreshes unit list",
		"refresh_unit_list()" in src and "_on_unit_split_completed" in src)


func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
