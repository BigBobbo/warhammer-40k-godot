extends SceneTree

# ISS-061 (step 1): the 11e SURGE move (21.02 — reproducing the pg 70
# worked example's semantics) and the FLY take-to-the-skies distance
# modifier (21.03 / HOVER 24.17).
#
# Usage: godot --headless --path . -s tests/test_iss061_surge_fly_11e.gd

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

func _board(shocked := false, moved := false) -> Dictionary:
	# Unit B (the surger) with two enemies: C close (8"), D far (15").
	return {"units": {
		"U_B": {"id": "U_B", "owner": 1, "flags": {"battle_shocked": shocked, "moved_this_phase": moved},
			"meta": {"keywords": ["INFANTRY"], "stats": {"move": 6}},
			"models": [{"id": "b0", "alive": true, "base_mm": 32, "base_type": "circular",
				"position": {"x": 400, "y": 400}}]},
		"U_C": {"id": "U_C", "owner": 2, "flags": {},
			"meta": {"keywords": ["INFANTRY"], "stats": {"move": 6}},
			"models": [{"id": "c0", "alive": true, "base_mm": 32, "base_type": "circular",
				"position": {"x": 400 + 8 * 40, "y": 400}}]},
		"U_D": {"id": "U_D", "owner": 2, "flags": {},
			"meta": {"keywords": ["INFANTRY"], "stats": {"move": 6}},
			"models": [{"id": "d0", "alive": true, "base_mm": 32, "base_type": "circular",
				"position": {"x": 400, "y": 400 + 15 * 40}}]},
	}, "meta": {}}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss061_surge_fly_11e ===\n")
	var rules = root.get_node_or_null("RulesEngine")
	var surge: MoveType = MoveTypes.get_type("surge")
	_check("surge registered", surge != null)

	print("-- eligibility (21.02) --")
	GameConstants.edition = 10
	_check("not available at edition 10", not surge.eligible("U_B", _board()).eligible)
	GameConstants.edition = 11
	_check("eligible: unengaged, unshocked, unmoved", surge.eligible("U_B", _board()).eligible)
	_check("battle-shocked cannot surge", not surge.eligible("U_B", _board(true)).eligible)
	_check("already-moved cannot surge", not surge.eligible("U_B", _board(false, true)).eligible)

	print("\n-- target selection + distance --")
	var board = _board()
	var ctx = surge.before_moving("U_B", board, rules.RNGService.new(1), {})
	_check("the CLOSEST enemy becomes the surge target (C at 8\", not D at 15\")",
		ctx.surge_target == "U_C", str(ctx))
	ctx["max_inches"] = 4.0
	_check("max distance comes from the triggering rule (D6=4 -> 4\")",
		surge.max_distance_inches(board.units["U_B"], ctx) == 4.0)

	print("\n-- after conditions (21.02) --")
	# Move the surger adjacent to D (the NON-target): violation.
	board.units["U_B"].models[0].position = {"x": 400, "y": 400 + 15 * 40 - 30}
	var cond = surge.after_moving_conditions("U_B", board, ctx)
	_check("ending engaged with a non-target unit is VOID", not cond.ok, str(cond))
	# Adjacent to C (the target): fine.
	board.units["U_B"].models[0].position = {"x": 400 + 8 * 40 - 30, "y": 400}
	cond = surge.after_moving_conditions("U_B", board, ctx)
	_check("ending engaged with the surge target is valid", cond.ok, str(cond))
	var fx = surge.after_moving_effects("U_B", ctx)
	var locked := false
	for f in fx:
		if "moved_this_phase" in str(f.get("path", "")):
			locked = true
	_check("cannot move again this phase", locked)

	print("\n-- FLY take to the skies (21.03 / 24.17) --")
	var flyer = {"meta": {"keywords": ["FLY"]}}
	var hover = {"meta": {"keywords": ["FLY", "HOVER"]}}
	var walker = {"meta": {"keywords": ["INFANTRY"]}}
	_check("FLY: -2\" when taking to the skies (16\" advance -> 14\", pg 71)",
		MoveType.take_to_skies_modifier(flyer) == -2.0)
	_check("HOVER: no penalty", MoveType.take_to_skies_modifier(hover) == 0.0)
	_check("non-FLY: no modifier", MoveType.take_to_skies_modifier(walker) == 0.0)
	GameConstants.edition = 10
	_check("edition 10: inert", MoveType.take_to_skies_modifier(flyer) == 0.0)

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
