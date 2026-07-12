extends SceneTree

# Regression test for DeepStrikeExclusionVisual cluster merging.
#
# Bug (fixed): when enemy models formed several physically-separate clusters,
# the exclusion overlay merged every circle into one running polygon and kept
# only the LARGEST result after each pairwise merge — silently dropping the
# exclusion zone of every cluster that was not connected to the largest one.
# The player saw a red "9\" exclusion" zone around one enemy group and nothing
# around the others (see the reported top-vs-bottom screenshot).
#
# This is a pure-geometry check (no window needed): it drives show_exclusion()
# and asserts _merged_polygons contains one polygon per connected cluster.
#
# Usage: godot --headless --path 40k -s tests/test_deep_strike_exclusion_clusters.gd

var passed := 0
var failed := 0

const PX_PER_INCH := 40.0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init() -> void:
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _make_visual() -> Node2D:
	var v: Node2D = load("res://scripts/DeepStrikeExclusionVisual.gd").new()
	root.add_child(v)
	return v

func _model(x: float, y: float, base_mm: int = 32) -> Dictionary:
	return {"x": x, "y": y, "base_mm": base_mm}

func _poly_count(v: Node2D, positions: Array) -> int:
	v.show_exclusion(positions)
	return v._merged_polygons.size()

func _run_tests() -> void:
	if passed > 0 or failed > 0:
		return  # guard against double invocation (ready signal + timer)
	print("\n=== test_deep_strike_exclusion_clusters ===\n")

	var v := _make_visual()

	# A single enemy model -> exactly one exclusion polygon.
	print("-- single model --")
	_check("one model -> 1 polygon", _poly_count(v, [_model(880, 1200)]) == 1)

	# Two models whose 9\" bubbles overlap (close together) -> one merged polygon.
	print("-- one tight cluster --")
	_check("two overlapping models -> 1 polygon",
		_poly_count(v, [_model(880, 1200), _model(920, 1200)]) == 1)

	# Two clusters far apart (top vs bottom of a 44x60\" board) -> TWO polygons.
	# This is the exact regression: before the fix only the larger one survived.
	print("-- two separated clusters (the reported bug) --")
	var top_bottom := [
		_model(880, 160), _model(940, 160), _model(1000, 160),   # top row cluster
		_model(880, 2240), _model(940, 2240), _model(1000, 2240), # bottom row cluster
	]
	_check("top + bottom clusters -> 2 polygons", _poly_count(v, top_bottom) == 2,
		"got %d" % v._merged_polygons.size())

	# Three separated clusters (top, bottom-left, bottom-right) -> THREE polygons.
	print("-- three separated clusters --")
	var three := [
		_model(880, 160), _model(940, 160),        # top
		_model(160, 2240), _model(220, 2240),      # bottom-left
		_model(1600, 2240), _model(1660, 2240),    # bottom-right
	]
	_check("three clusters -> 3 polygons", _poly_count(v, three) == 3,
		"got %d" % v._merged_polygons.size())

	# Empty input -> no polygons, no crash.
	print("-- empty --")
	_check("no models -> 0 polygons", _poly_count(v, []) == 0)

	v.queue_free()

	print("\n=== RESULT: %d passed, %d failed ===\n" % [passed, failed])
	quit(1 if failed > 0 else 0)
