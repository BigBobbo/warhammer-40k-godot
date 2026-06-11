extends SceneTree

# ISS-040: the 11e move-type framework (core rules 03.01, 09.04-09.07).
#
# Contract tests over the four foundational instances:
#   A) Registry + eligibility matrix per engagement state.
#   B) Advance: D6 roll added to M, deterministic, flags set; 11e adds the
#      cannot_start_action flag.
#   C) Fall back 11e modes: ordered retreat selectable when unshocked
#      (not mandatory), desperate escape mandatory when battle-shocked;
#      desperate escape rolls one hazard roll per model and requires a
#      follow-up battle-shock roll; 10e has no modes.
#   D) After-move conditions: normal/advance/fall-back must end unengaged;
#      coherency is a universal end condition; remain-stationary skips all
#      end-of-move checks (09.04).
#
# Usage: godot --headless --path . -s tests/test_iss040_move_types.gd

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

func _board(gap_inches: float, shocked: bool = false) -> Dictionary:
	var radius_px = (32.0 / 25.4) * 40.0 / 2.0
	var center_dist = gap_inches * 40.0 + 2.0 * radius_px
	return {
		"units": {
			"U_ME": {"id": "U_ME", "owner": 1, "flags": {"battle_shocked": shocked},
				"meta": {"keywords": ["INFANTRY"], "stats": {"move": 6, "leadership": 7}},
				"models": [
					{"id": "m0", "alive": true, "base_mm": 32, "base_type": "circular", "position": {"x": 300, "y": 300}},
					{"id": "m1", "alive": true, "base_mm": 32, "base_type": "circular", "position": {"x": 340, "y": 300}},
				]},
			"U_FOE": {"id": "U_FOE", "owner": 2, "flags": {},
				"meta": {"keywords": ["INFANTRY"], "stats": {"move": 6}},
				"models": [{"id": "e0", "alive": true, "base_mm": 32, "base_type": "circular",
					"position": {"x": 300 + center_dist, "y": 300}}]},
		},
		"meta": {}
	}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss040_move_types ===\n")
	var rules = root.get_node_or_null("RulesEngine")
	GameConstants.edition = 10

	print("-- A: registry + eligibility matrix --")
	_check("registry has the foundational types (and grows with 11e instances)",
		MoveTypes.all_ids().size() >= 4 and MoveTypes.get_type("advance") != null
		and MoveTypes.get_type("ingress") != null)
	var far = _board(6.0)   # unengaged
	var near = _board(0.5)  # engaged at 1\" ER
	_check("unengaged: stationary/normal/advance available, fall back not",
		MoveTypes.available_for("U_ME", far) == ["remain_stationary", "normal", "advance"],
		str(MoveTypes.available_for("U_ME", far)))
	_check("engaged: stationary + fall back only",
		MoveTypes.available_for("U_ME", near) == ["remain_stationary", "fall_back"],
		str(MoveTypes.available_for("U_ME", near)))

	print("\n-- B: advance mechanics --")
	var adv: MoveType = MoveTypes.get_type("advance")
	var ctx = adv.before_moving("U_ME", far, rules.RNGService.new(7), {})
	_check("advance roll is a D6", ctx.advance_roll >= 1 and ctx.advance_roll <= 6)
	_check("advance roll deterministic with seed",
		adv.before_moving("U_ME", far, rules.RNGService.new(7), {}).advance_roll == ctx.advance_roll)
	_check("max distance = M + roll",
		adv.max_distance_inches(far.units["U_ME"], ctx) == 6.0 + ctx.advance_roll)
	GameConstants.edition = 10
	var fx10 = adv.after_moving_effects("U_ME", ctx)
	GameConstants.edition = 11
	var fx11 = adv.after_moving_effects("U_ME", ctx)
	GameConstants.edition = 10
	var has_action_flag_10 := false
	for f in fx10:
		if "cannot_start_action" in str(f.get("path", "")):
			has_action_flag_10 = true
	var has_action_flag_11 := false
	for f in fx11:
		if "cannot_start_action" in str(f.get("path", "")):
			has_action_flag_11 = true
	_check("11e advance blocks starting actions; 10e flag set unchanged",
		not has_action_flag_10 and has_action_flag_11)

	print("\n-- C: fall-back modes (11e 09.07) --")
	var fb: MoveType = MoveTypes.get_type("fall_back")
	GameConstants.edition = 10
	_check("10e: no fall-back modes", fb.mode_ids().is_empty())
	GameConstants.edition = 11
	_check("11e: two modes in assessment order",
		fb.mode_ids() == ["ordered_retreat", "desperate_escape"])
	var sel = fb.select_mode("U_ME", near)
	_check("unshocked: ordered retreat default, NOT mandatory, both available",
		sel.mode == "ordered_retreat" and sel.mandatory == false and sel.available.size() == 2, str(sel))
	var near_shocked = _board(0.5, true)
	sel = fb.select_mode("U_ME", near_shocked)
	_check("battle-shocked: desperate escape mandatory",
		sel.mode == "desperate_escape" and sel.mandatory == true, str(sel))
	var de_ctx = fb.before_moving("U_ME", near_shocked, rules.RNGService.new(3), {"mode": "desperate_escape"})
	_check("desperate escape: one hazard roll per model (2 models)",
		de_ctx.hazard.rolls.size() == 2, str(de_ctx))
	_check("desperate escape: may move through enemies",
		de_ctx.get("can_move_through_enemies", false))
	var de_fx = fb.after_moving_effects("U_ME", {"mode": "desperate_escape"})
	var pending_bs := false
	for f in de_fx:
		if "pending_battleshock_roll" in str(f.get("path", "")):
			pending_bs = true
	_check("desperate escape requires a follow-up battle-shock roll", pending_bs)
	GameConstants.edition = 10

	print("\n-- D: after-move conditions --")
	var nm: MoveType = MoveTypes.get_type("normal")
	var cond = nm.after_moving_conditions("U_ME", near, {})
	_check("normal move ending engaged is VOID", not cond.ok, str(cond))
	cond = nm.after_moving_conditions("U_ME", far, {})
	_check("normal move ending unengaged + coherent is valid", cond.ok, str(cond))
	# Break coherency: move m1 far from m0
	var split = _board(6.0)
	split.units["U_ME"].models[1].position = {"x": 900, "y": 900}
	cond = nm.after_moving_conditions("U_ME", split, {})
	_check("coherency is a universal end condition", not cond.ok, str(cond))
	var rs: MoveType = MoveTypes.get_type("remain_stationary")
	cond = rs.after_moving_conditions("U_ME", split, {})
	_check("remain stationary skips end-of-move checks (09.04)", cond.ok)

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
