extends SceneTree

# ISS-060 (step 1): the 11e INGRESS move (20.04) + Deep Strike relaxation
# (24.09), as a MoveType instance.
#
# Usage: godot --headless --path . -s tests/test_iss060_ingress_11e.gd

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
	return {"units": {
		"U_RES": {"id": "U_RES", "owner": 1, "status": 7, "flags": {"in_reserves": true},
			"meta": {"keywords": ["INFANTRY"], "stats": {"move": 6}},
			"models": [{"id": "m0", "alive": true, "base_mm": 32, "base_type": "circular", "position": null}]},
		"U_FOE": {"id": "U_FOE", "owner": 2, "status": 2, "flags": {},
			"meta": {"keywords": ["INFANTRY"], "stats": {"move": 6}},
			"models": [{"id": "e0", "alive": true, "base_mm": 32, "base_type": "circular",
				"position": {"x": 880, "y": 1200}}]},  # board center
		"U_ON_FIELD": {"id": "U_ON_FIELD", "owner": 1, "status": 2, "flags": {},
			"meta": {"keywords": ["INFANTRY"], "stats": {"move": 6}},
			"models": [{"id": "f0", "alive": true, "base_mm": 32, "base_type": "circular",
				"position": {"x": 400, "y": 400}}]},
	}, "meta": {}}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss060_ingress_11e ===\n")
	var ingress: MoveType = MoveTypes.get_type("ingress")
	_check("ingress registered", ingress != null)
	var board = _board()

	print("-- eligibility (20.04) --")
	GameConstants.edition = 10
	_check("not an option at edition 10", not ingress.eligible("U_RES", board).eligible)
	GameConstants.edition = 11
	_check("reserves unit eligible at 11e", ingress.eligible("U_RES", board).eligible)
	_check("on-battlefield unit not eligible", not ingress.eligible("U_ON_FIELD", board).eligible)
	_check("ingress NOT in normal availability for on-field units",
		not MoveTypes.available_for("U_ON_FIELD", board).has("ingress"))

	print("\n-- placement validation --")
	# Board 44x60 inches = 1760x2400 px. Enemy at (880,1200).
	var ctx = {"battle_round": 2, "deep_strike": false,
		"opponent_zone": PackedVector2Array([Vector2(0, 0), Vector2(1760, 0), Vector2(1760, 480), Vector2(0, 480)]),
		"board_size_inches": Vector2(44, 60)}
	# Legal: 4" from the left edge (x=160), far from enemy + outside DZ.
	var v = ingress.validate_setup("U_RES", board, [Vector2(160, 1200)], ctx)
	_check("wholly within 6\" of an edge, >8\" from enemies: legal", v.valid, str(v.errors))
	# Too central: 10" from every edge.
	v = ingress.validate_setup("U_RES", board, [Vector2(400, 1200)], ctx)
	_check("more than 6\" from every edge: illegal", not v.valid)
	# Near the enemy: 6" away.
	v = ingress.validate_setup("U_RES", board, [Vector2(880 + 6 * 40, 2360)], ctx)
	# that point is near bottom edge but place near enemy instead:
	v = ingress.validate_setup("U_RES", board, [Vector2(880, 1200 + 6 * 40)], ctx)
	_check("within 8\" of an enemy: illegal", not v.valid)
	# Opponent DZ before round 3 (DZ = top strip; point near top edge).
	v = ingress.validate_setup("U_RES", board, [Vector2(880, 100)], ctx)
	_check("inside opponent DZ before round 3: illegal", not v.valid)
	ctx.battle_round = 3
	v = ingress.validate_setup("U_RES", board, [Vector2(880, 100)], ctx)
	_check("same spot legal from round 3", v.valid, str(v.errors))

	print("\n-- deep strike (24.09) --")
	ctx.battle_round = 2
	ctx.deep_strike = true
	v = ingress.validate_setup("U_RES", board, [Vector2(700, 1800)], ctx)
	_check("deep strike: anywhere >8\" from enemies is legal", v.valid, str(v.errors))
	v = ingress.validate_setup("U_RES", board, [Vector2(880, 1200 + 7 * 40)], ctx)
	_check("deep strike still respects the 8\" enemy bubble", not v.valid)

	print("\n-- after-effects (20.04) --")
	var fx = ingress.after_moving_effects("U_RES", {})
	var has_charge_lock := false
	for f in fx:
		if "no_moves_until_charge_phase" in str(f.get("path", "")):
			has_charge_lock = true
	_check("locked out of further moves until the Charge phase (charging allowed)", has_charge_lock)

	GameConstants.edition = 10
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
