extends SceneTree

# T2.M6: Base-touching regression (#321/#327)
#
# Two 32mm-base models placed exactly 50px apart center-to-center represent
# a perfect base-to-base contact. Sub-pixel rounding of mm→px (32mm → 50.394px
# diameter) means strict-`<` collision treats this as overlap. The fix adds a
# 0.5px OVERLAP_TOLERANCE in MovementPhase._is_touching_within_tolerance.
#
# This regression test verifies:
#   1. Measurement.models_overlap still flags the boundary case as "overlap"
#      (the underlying bug surface — needed so the tolerance isn't masking it)
#   2. MovementPhase._is_touching_within_tolerance recognises the boundary
#      case and returns true (so the caller can `continue` instead of
#      reporting overlap)
#   3. Full path: _position_overlaps_other_models with two adjacent same-unit
#      models at touching distance returns false
#
# Usage: godot --headless --path . -s tests/test_m6_base_touching_regression.gd

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
	print("\n=== test_m6_base_touching_regression ===\n")

	var measurement = root.get_node("Measurement")
	var radius_32 = measurement.base_radius_px(32)
	var diameter_32 = radius_32 * 2.0
	print("32mm base radius: %.4f px (diameter %.4f px)" % [radius_32, diameter_32])
	# Confirm the rounding scenario is still present.
	_check("32mm diameter is between 50px and 51px (sub-pixel rounding present)",
		diameter_32 > 50.0 and diameter_32 < 51.0,
		"got %.4f" % diameter_32)

	# Step 1 — direct Measurement.models_overlap exercises the bug surface
	var m1 = {"id": "m1", "position": Vector2(100, 100), "base_mm": 32, "base_type": "circular", "alive": true}
	var m2 = {"id": "m2", "position": Vector2(150, 100), "base_mm": 32, "base_type": "circular", "alive": true}
	_check("Measurement.models_overlap reports overlap at exactly 50px apart (boundary)",
		measurement.models_overlap(m1, m2),
		"if false: rounding fixed in Measurement layer — re-evaluate the test")

	# Step 2 — MovementPhase._is_touching_within_tolerance accepts the boundary
	var MovementPhaseScript = load("res://phases/MovementPhase.gd")
	var mp = MovementPhaseScript.new()
	_check("Touching: helper returns true at exact 50px",
		mp._is_touching_within_tolerance(m1, m2))

	# Tighter overlap (10px gap into each other) should still be rejected
	var m3 = {"id": "m3", "position": Vector2(140, 100), "base_mm": 32, "base_type": "circular", "alive": true}
	_check("Real overlap: helper returns false when actually overlapping",
		not mp._is_touching_within_tolerance(m1, m3),
		"m1=(100,100) m3=(140,100) — 10px overlap")

	# Non-circular bases: helper should not apply tolerance
	var rect_a = {"id": "ra", "position": Vector2(100, 100), "base_mm": 32, "base_type": "rectangular", "alive": true}
	var rect_b = {"id": "rb", "position": Vector2(150, 100), "base_mm": 32, "base_type": "rectangular", "alive": true}
	_check("Non-circular: tolerance helper returns false (strict behaviour)",
		not mp._is_touching_within_tolerance(rect_a, rect_b))

	# Step 3 — full path through _position_overlaps_other_models
	var test_unit = {
		"id": "U_TEST",
		"owner": 1,
		"meta": {"keywords": ["INFANTRY"]},
		"models": [
			{"id": "m1", "position": Vector2(100, 100), "base_mm": 32, "base_type": "circular", "alive": true},
			{"id": "m2", "position": Vector2(0, 0), "base_mm": 32, "base_type": "circular", "alive": true}
		]
	}
	# ISS-024: the phase snapshot is a live view — seed the unit into
	# GameState (and restore after the probe below).
	var _prev_units_m6 = root.get_node("GameState").state.get("units", {})
	root.get_node("GameState").state["units"] = {"U_TEST": test_unit}
	mp.active_moves = {}

	var pos_touching = Vector2(150.0, 100.0)
	var overlaps = mp._position_overlaps_other_models("U_TEST", "m2", pos_touching,
		{"id": "m2", "base_mm": 32, "base_type": "circular", "alive": true})
	_check("Full path: staging m2 at touching distance from committed m1 → no overlap (#321/#327)",
		not overlaps,
		"_position_overlaps_other_models returned true")

	# Sanity: staging m2 at clearly-overlapping distance still returns true
	var pos_overlap = Vector2(120.0, 100.0)  # 20px from m1 — clear overlap
	var overlaps_clearly = mp._position_overlaps_other_models("U_TEST", "m2", pos_overlap,
		{"id": "m2", "base_mm": 32, "base_type": "circular", "alive": true})
	_check("Full path: real overlap (20px) still rejected",
		overlaps_clearly,
		"_position_overlaps_other_models returned false")
	root.get_node("GameState").state["units"] = _prev_units_m6

	mp.queue_free()
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
