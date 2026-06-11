extends SceneTree

# ISS-058 (step 1): 11e disembark modes (18.04) + emergency disembark
# (18.05) as MoveType instances. Mode selection is driven by the
# TRANSPORT's move history this phase and is mandatory-if-applicable:
#   normal/ingress move -> rapid (3", no charge)
#   unmoved             -> tactical (3", unit then makes a normal/advance move)
#   advanced/fell back  -> combat (6", hazard per model, battle-shocked, no charge)
#
# Usage: godot --headless --path . -s tests/test_iss058_disembark_11e.gd

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

func _board(transport_flags: Dictionary) -> Dictionary:
	return {"units": {
		"U_CARGO": {"id": "U_CARGO", "owner": 1, "embarked_in": "U_TRUKK", "flags": {},
			"meta": {"keywords": ["INFANTRY"], "stats": {"move": 6}},
			"models": [
				{"id": "m0", "alive": true, "base_mm": 32, "base_type": "circular", "position": null},
				{"id": "m1", "alive": true, "base_mm": 32, "base_type": "circular", "position": null},
				{"id": "m2", "alive": true, "base_mm": 32, "base_type": "circular", "position": null}]},
		"U_TRUKK": {"id": "U_TRUKK", "owner": 1, "flags": transport_flags,
			"meta": {"keywords": ["VEHICLE", "TRANSPORT"], "stats": {"move": 12}},
			"models": [{"id": "t0", "alive": true, "base_mm": 100, "base_type": "circular",
				"position": {"x": 800, "y": 800}}]},
	}, "meta": {}}

func _fx_has(fx: Array, fragment: String) -> bool:
	for f in fx:
		if fragment in str(f.get("path", "")):
			return true
	return false

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss058_disembark_11e ===\n")
	var rules = root.get_node_or_null("RulesEngine")
	var dis: MoveType = MoveTypes.get_type("disembark")
	var em: MoveType = MoveTypes.get_type("emergency_disembark")
	_check("both move types registered", dis != null and em != null)

	print("-- eligibility --")
	GameConstants.edition = 10
	_check("11e-only", not dis.eligible("U_CARGO", _board({})).eligible)
	GameConstants.edition = 11
	_check("embarked unit eligible", dis.eligible("U_CARGO", _board({})).eligible)
	var b = _board({})
	b.units["U_CARGO"].flags["embarked_this_phase"] = true
	_check("cannot disembark the phase it embarked (18.04)",
		not dis.eligible("U_CARGO", b).eligible)
	b = _board({})
	b.units["U_CARGO"].embarked_in = ""
	_check("non-embarked unit not eligible", not dis.eligible("U_CARGO", b).eligible)

	print("\n-- mode selection (transport state, mandatory) --")
	var sel = dis.select_mode("U_CARGO", _board({"moved_this_phase": true}))
	_check("transport normal-moved -> RAPID (mandatory)",
		sel.mode == "rapid" and sel.mandatory, str(sel))
	sel = dis.select_mode("U_CARGO", _board({}))
	_check("transport unmoved -> TACTICAL (mandatory)",
		sel.mode == "tactical" and sel.mandatory, str(sel))
	sel = dis.select_mode("U_CARGO", _board({"moved_this_phase": true, "advanced": true}))
	_check("transport advanced -> COMBAT (mandatory)",
		sel.mode == "combat" and sel.mandatory, str(sel))

	print("\n-- distances + combat hazard --")
	_check("rapid/tactical set-up distance 3\"", dis.setup_distance_inches({"mode": "rapid"}) == 3.0
		and dis.setup_distance_inches({"mode": "tactical"}) == 3.0)
	_check("combat set-up distance 6\"", dis.setup_distance_inches({"mode": "combat"}) == 6.0)
	var ctx = dis.before_moving("U_CARGO", _board({"advanced": true, "moved_this_phase": true}),
		rules.RNGService.new(11), {"mode": "combat"})
	_check("combat disembark: one hazard roll per model (3)",
		ctx.hazard.rolls.size() == 3, str(ctx))
	_check("combat disembark may set up engaged with the transport's foes",
		ctx.get("can_setup_engaged_with_transport_foes", false))
	_check("rapid mode has no hazard rolls",
		dis.before_moving("U_CARGO", _board({"moved_this_phase": true}), rules.RNGService.new(1), {"mode": "rapid"}).is_empty())

	print("\n-- after-effects per mode --")
	var fx = dis.after_moving_effects("U_CARGO", {"mode": "rapid"})
	_check("rapid: cannot charge", _fx_has(fx, "cannot_charge") and not _fx_has(fx, "battle_shocked"))
	fx = dis.after_moving_effects("U_CARGO", {"mode": "tactical"})
	_check("tactical: unit then makes a normal/advance move (pending flag)",
		_fx_has(fx, "pending_post_disembark_move") and not _fx_has(fx, "cannot_charge"))
	fx = dis.after_moving_effects("U_CARGO", {"mode": "combat"})
	_check("combat: battle-shocked AND cannot charge",
		_fx_has(fx, "battle_shocked") and _fx_has(fx, "cannot_charge"))

	print("\n-- emergency disembark (18.05) --")
	var ectx = em.before_moving("U_CARGO", _board({}), rules.RNGService.new(5), {})
	_check("hazard roll per model on emergency disembark", ectx.hazard.rolls.size() == 3)
	_check("set-up distance 6\"", em.setup_distance_inches({}) == 6.0)
	fx = em.after_moving_effects("U_CARGO", {})
	_check("emergency: battle-shocked, cannot charge, unembarked",
		_fx_has(fx, "battle_shocked") and _fx_has(fx, "cannot_charge") and _fx_has(fx, "embarked_in"))

	GameConstants.edition = 10
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
