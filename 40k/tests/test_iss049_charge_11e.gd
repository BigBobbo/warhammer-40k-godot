extends SceneTree

# ISS-049 (step 1): the 11e charge template (11.02/11.04), reproducing the
# pg-37 worked example's semantics: targets are selected AFTER the roll
# from enemies within 12" AND within the rolled distance; the move must
# end engaged with every target and no non-targets; chargers gain the
# Fights First ability.
#
# Usage: godot --headless --path . -s tests/test_iss049_charge_11e.gd

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

func _board() -> Dictionary:
	# Charger at x=400; enemy A at 5", enemy B at 10", enemy C at 20".
	return {"units": {
		"U_CHG": {"id": "U_CHG", "owner": 1, "flags": {},
			"meta": {"keywords": ["INFANTRY"], "stats": {"move": 6}},
			"models": [{"id": "m0", "alive": true, "base_mm": 32, "base_type": "circular",
				"position": {"x": 400, "y": 400}}]},
		"U_A": {"id": "U_A", "owner": 2, "flags": {},
			"meta": {"keywords": ["INFANTRY"], "stats": {}},
			"models": [{"id": "a0", "alive": true, "base_mm": 32, "base_type": "circular",
				"position": {"x": 400 + 5 * 40 + 50, "y": 400}}]},
		"U_B": {"id": "U_B", "owner": 2, "flags": {},
			"meta": {"keywords": ["INFANTRY"], "stats": {}},
			"models": [{"id": "b0", "alive": true, "base_mm": 32, "base_type": "circular",
				"position": {"x": 400, "y": 400 + 10 * 40 + 50}}]},
		"U_C": {"id": "U_C", "owner": 2, "flags": {},
			"meta": {"keywords": ["INFANTRY"], "stats": {}},
			"models": [{"id": "c0", "alive": true, "base_mm": 32, "base_type": "circular",
				"position": {"x": 400 + 20 * 40, "y": 400}}]},
	}, "meta": {}}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss049_charge_11e ===\n")
	var rules = root.get_node_or_null("RulesEngine")
	var chg: MoveType = MoveTypes.get_type("charge")
	_check("charge template registered", chg != null)

	print("-- eligibility (11.02) --")
	GameConstants.edition = 10
	_check("11e-only template", not chg.eligible("U_CHG", _board()).eligible)
	GameConstants.edition = 11
	_check("within 12\" of an enemy, unengaged: eligible", chg.eligible("U_CHG", _board()).eligible)
	var b = _board()
	b.units["U_CHG"].flags["advanced"] = true
	_check("advanced this turn: not eligible", not chg.eligible("U_CHG", b).eligible)
	b = _board()
	b.units["U_CHG"].flags["fell_back"] = true
	_check("fell back this turn: not eligible", not chg.eligible("U_CHG", b).eligible)
	b = _board()
	b.units["U_A"].models[0].position = {"x": 400 + 20 * 40, "y": 800}
	b.units["U_B"].models[0].position = {"x": 400, "y": 400 + 20 * 40}
	_check("no enemy within 12\": not eligible", not chg.eligible("U_CHG", b).eligible)

	print("\n-- roll-then-target selection (11.02) --")
	b = _board()
	# Find a seed producing a 2D6 of 7 so A (5\") is in range, B (10\") is not.
	var seed := -1
	for i in range(200):
		var d = rules.RNGService.new(i).roll_d6(2)
		if d[0] + d[1] == 7:
			seed = i
			break
	var ctx = chg.before_moving("U_CHG", b, rules.RNGService.new(seed), {})
	_check("charge roll is 2D6 and IS the maximum distance",
		ctx.charge_roll == 7 and chg.max_distance_inches(b.units["U_CHG"], ctx) == 7.0)
	_check("pg-37 semantics: A (within roll) selectable, B (10\" > 7) and C (>12\") not",
		ctx.selectable_targets == ["U_A"], str(ctx.selectable_targets))

	print("\n-- after conditions (11.04) --")
	ctx["charge_targets"] = ["U_A"]
	# Not engaged with the target yet: void.
	var cond = chg.after_moving_conditions("U_CHG", b, ctx)
	_check("not engaged with every target: VOID", not cond.ok, str(cond))
	# Move adjacent to A: valid.
	b.units["U_CHG"].models[0].position = {"x": 400 + 5 * 40 + 20, "y": 400}
	cond = chg.after_moving_conditions("U_CHG", b, ctx)
	_check("engaged with all targets, no non-targets: valid", cond.ok, str(cond))
	# Drag B adjacent (non-target engagement): void.
	b.units["U_B"].models[0].position = {"x": 400 + 5 * 40 + 60, "y": 400}
	cond = chg.after_moving_conditions("U_CHG", b, ctx)
	_check("engaged with a NON-target: VOID", not cond.ok, str(cond))

	print("\n-- after effects (11.04 / 24.13) --")
	var fx = chg.after_moving_effects("U_CHG", ctx)
	var ff := false
	for f in fx:
		if "fights_first" in str(f.get("path", "")):
			ff = true
	_check("chargers gain the Fights First ability until end of turn", ff)

	GameConstants.edition = 10
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
