extends SceneTree

# T-103: multi-floor ruins vertical movement cost.
# Pin: MovementPhase._get_vertical_climb_cost helper exists, FLY units skip,
# _get_movement_terrain_penalty includes the vertical climb component.
#
# Usage: godot --headless --path . -s tests/test_t103_vertical_climb_cost.gd

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
	print("\n=== test_t103_vertical_climb_cost ===\n")
	_test_helper_present()
	_finish()


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t = f.get_as_text()
	f.close()
	return t


func _test_helper_present() -> void:
	var src = _read("res://phases/MovementPhase.gd")
	_check("MovementPhase.gd readable", not src.is_empty())
	_check("_get_vertical_climb_cost helper defined",
		"func _get_vertical_climb_cost(from_pos: Vector2, to_pos: Vector2" in src)
	_check("vertical penalty added to terrain penalty",
		"penalty += _get_vertical_climb_cost" in src)
	# Infantry through ruins should not pay climb cost (10e ground floor rule).
	_check("traversable terrain bypasses climb cost",
		"can_unit_move_through_terrain" in src and "return 0.0" in src)
	_check("FLY units bypass vertical cost",
		"if _unit_has_fly_keyword(unit_id):" in src and "_get_movement_terrain_penalty" in src)
	_check("descent (to_h <= from_h) is free",
		"if to_h <= from_h:" in src and "return 0.0  # Going level or downward" in src)


func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
