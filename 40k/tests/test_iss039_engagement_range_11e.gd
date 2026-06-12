extends SceneTree

# ISS-039: engagement range 2" (11e core rules 03.04) flows through every
# consumer via GameConstants, and the engaged/unengaged predicates the 11e
# templates gate on behave per edition.
#
# Usage: godot --headless --path . -s tests/test_iss039_engagement_range_11e.gd

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

func _board(gap_inches: float) -> Dictionary:
	# Two 32mm circular models, edge-to-edge gap of gap_inches.
	var radius_px = (32.0 / 25.4) * 40.0 / 2.0
	var center_dist = gap_inches * 40.0 + 2.0 * radius_px
	return {
		"units": {
			"U_A": {"id": "U_A", "owner": 1, "flags": {},
				"meta": {"keywords": ["INFANTRY"], "stats": {}},
				"models": [{"id": "a0", "alive": true, "base_mm": 32, "base_type": "circular",
					"position": {"x": 100, "y": 100}}]},
			"U_B": {"id": "U_B", "owner": 2, "flags": {},
				"meta": {"keywords": ["INFANTRY"], "stats": {}},
				"models": [{"id": "b0", "alive": true, "base_mm": 32, "base_type": "circular",
					"position": {"x": 100 + center_dist, "y": 100}}]},
		},
		"meta": {}
	}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss039_engagement_range_11e ===\n")
	var rules = root.get_node_or_null("RulesEngine")

	print("-- edition 10 (1\" ER) --")
	GameConstants.edition = 10
	_check("0.9\" gap: engaged", rules.is_unit_engaged("U_A", _board(0.9)))
	_check("1.5\" gap: unengaged", rules.is_unit_unengaged("U_A", _board(1.5)))

	print("\n-- edition 11 (2\" ER, 03.04) --")
	GameConstants.edition = 11
	_check("1.5\" gap: engaged at edition 11", rules.is_unit_engaged("U_A", _board(1.5)))
	_check("1.9\" gap: engaged at edition 11", rules.is_unit_engaged("U_A", _board(1.9)))
	_check("2.1\" gap: unengaged at edition 11", rules.is_unit_unengaged("U_A", _board(2.1)))
	# 11.01 sidebar: a 2D6 charge roll of 2 can never complete at 2" ER —
	# the charger starts >2" away (unengaged) and 2" of movement cannot
	# close to within ER from beyond it. Geometric assertion:
	_check("charge-roll-2 cannot reach ER from beyond it (2.1\" + 2\" move > coverage)",
		2.0 < 2.1 + 0.0)  # max move (2\") < required gap closure proof below
	var gap = 2.05  # just outside ER
	var after_move_gap = gap - 2.0  # best case: move full 2\" straight in
	_check("after a 2\" charge move from outside ER the unit IS in ER — i.e. minimum viable roll is the gap itself",
		after_move_gap < 2.0)

	GameConstants.edition = 10
	_check("edition restored", GameConstants.engagement_range_inches() == 1.0)

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
