extends SceneTree

# ISS-050 (step 1): the 11e fight-phase engine layer.
#  - PileInMove (12.02-12.03): eligibility (engaged / charged / overrun),
#    target selection (engaged -> ALL engaged; else within 5" — the pg-39
#    charge-survivor case), base-contact lock, closer-to-closest rule,
#    after conditions (engaged + started-engaged pairs maintained)
#  - ConsolidationMove (12.07-12.08): mandatory modes in order (ongoing /
#    engaging / objective — the pg-43 example), per-mode WHILE/AFTER,
#    engaging-consolidation forced fights
#  - FightSequencer (12.04-12.06): Fights First alternation with pass
#    rules, return-to-FF, overrun fight types — reproducing the pg-41
#    worked example's full selection sequence (monster kills transport,
#    charge-survivor overruns the emergency-disembarked unit, which then
#    fights back)
#
# Usage: godot --headless --path . -s tests/test_iss050_fight_phase_11e.gd

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

func _unit(id: String, owner: int, x: float, y: float, flags: Dictionary = {}, n_models: int = 1, keywords: Array = ["INFANTRY"]) -> Dictionary:
	var models = []
	for i in range(n_models):
		models.append({"id": "%s_m%d" % [id, i], "alive": true, "wounds": 2,
			"current_wounds": 2, "base_mm": 32, "base_type": "circular",
			"position": {"x": x + float(i * 50), "y": y}})
	return {"id": id, "owner": owner, "flags": flags,
		"meta": {"name": id, "keywords": keywords, "stats": {"toughness": 4, "save": 4, "wounds": 2}},
		"models": models}

## pg-41 layout: RED_MONSTER engaged with BLUE_TRANSPORT; RED_SQUAD (FF,
## charged) also engaged with the transport; BLUE_SQUAD (the future
## emergency-disembarkers) nearby but unengaged.
func _pg41_board() -> Dictionary:
	var b = {"units": {}, "meta": {}}
	b.units["RED_MONSTER"] = _unit("RED_MONSTER", 1, 400, 400, {"charged_this_turn": true, "fights_first": true}, 1, ["MONSTER"])
	b.units["RED_SQUAD"] = _unit("RED_SQUAD", 1, 400, 480, {"charged_this_turn": true, "fights_first": true})
	b.units["BLUE_TRANSPORT"] = _unit("BLUE_TRANSPORT", 2, 460, 440, {}, 1, ["VEHICLE", "TRANSPORT"])
	b.units["BLUE_SQUAD"] = _unit("BLUE_SQUAD", 2, 700, 440)
	return b

func _kill(board: Dictionary, unit_id: String) -> void:
	for m in board.units[unit_id].models:
		m["alive"] = false

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss050_fight_phase_11e ===\n")
	var rules = root.get_node_or_null("RulesEngine")
	_check("RulesEngine present", rules != null)
	GameConstants.edition = 11

	var pile: PileInMove = MoveTypes.get_type("pile_in")
	var cons: ConsolidationMove = MoveTypes.get_type("consolidation")
	_check("pile_in + consolidation registered as move types", pile != null and cons != null)

	print("-- pile-in (12.03) --")
	GameConstants.edition = 10
	_check("11e-only", not pile.eligible("RED_MONSTER", _pg41_board()).eligible)
	GameConstants.edition = 11
	var b = _pg41_board()
	_check("engaged unit eligible", pile.eligible("RED_MONSTER", b).eligible)
	_check("max distance 3\"", pile.max_distance_inches({}, {}) == 3.0)
	# pg-39: a charge-survivor whose target died is still eligible
	# (charged this turn) even though unengaged.
	var b39 = _pg41_board()
	_kill(b39, "BLUE_TRANSPORT")
	_check("pg-39: unengaged charger still eligible (charged_this_turn)",
		pile.eligible("RED_MONSTER", b39).eligible)
	_check("unengaged non-charger not eligible",
		not pile.eligible("BLUE_SQUAD", _pg41_board()).eligible)
	var ctx = pile.before_moving("RED_MONSTER", b, null, {})
	_check("engaged: pile-in targets = EVERY engaged enemy unit",
		ctx.pile_in_targets == ["BLUE_TRANSPORT"], str(ctx))
	# pg-39 target rule: unengaged charger selects targets within 5".
	b39.units["BLUE_SQUAD"].models[0].position = {"x": 560, "y": 400}  # 4" away
	ctx = pile.before_moving("RED_MONSTER", b39, null, {})
	_check("pg-39: unengaged charger selects pile-in targets within 5\"",
		ctx.pile_in_targets == ["BLUE_SQUAD"], str(ctx))
	# WHILE: closer-to-closest-target; base-contact lock.
	var mv = pile.model_move_allowed("RED_MONSTER", b39.units["RED_MONSTER"].models[0],
		{"x": 480, "y": 400}, b39, ctx)
	_check("moved model ending closer to closest target: allowed", mv.allowed, str(mv))
	mv = pile.model_move_allowed("RED_MONSTER", b39.units["RED_MONSTER"].models[0],
		{"x": 300, "y": 400}, b39, ctx)
	_check("moved model ending farther: refused (12.03)", not mv.allowed)
	var bc = _pg41_board()
	bc.units["RED_MONSTER"].models[0].position = {"x": 400, "y": 440}
	bc.units["BLUE_TRANSPORT"].models[0].position = {"x": 450, "y": 440}  # ~base contact (50px ≈ 1.25", radii 1.26")
	var ctx_bc = pile.before_moving("RED_MONSTER", bc, null, {})
	mv = pile.model_move_allowed("RED_MONSTER", bc.units["RED_MONSTER"].models[0],
		{"x": 410, "y": 440}, bc, ctx_bc)
	_check("model in base-contact with an enemy cannot be moved", not mv.allowed, str(mv))
	# AFTER: must end engaged; started-engaged pairs maintained.
	var ba = _pg41_board()
	var ctx_a = pile.before_moving("RED_MONSTER", ba, null, {})
	_check("after: engaged unit passes", pile.after_moving_conditions("RED_MONSTER", ba, ctx_a).ok)
	ba.units["RED_MONSTER"].models[0].position = {"x": 2000, "y": 2000}
	var ac = pile.after_moving_conditions("RED_MONSTER", ba, ctx_a)
	_check("after: ending unengaged / dropping a started-engaged pair VOIDS the move",
		not ac.ok, str(ac))

	print("\n-- consolidation (12.08) modes --")
	b = _pg41_board()
	b.units["RED_MONSTER"].flags["was_eligible_to_fight"] = true
	b.units["BLUE_SQUAD"].flags["was_eligible_to_fight"] = true
	_check("eligible iff the unit was eligible to fight this phase",
		cons.eligible("RED_MONSTER", b).eligible and not cons.eligible("BLUE_TRANSPORT", b).eligible)
	var sel = cons.select_mode("RED_MONSTER", b)
	_check("engaged -> ONGOING (mandatory)", sel.mode == "ongoing" and sel.mandatory, str(sel))
	# Unengaged with enemies within 3": engaging.
	var be = _pg41_board()
	be.units["BLUE_SQUAD"].flags["was_eligible_to_fight"] = true
	be.units["BLUE_SQUAD"].models[0].position = {"x": 400, "y": 631}  # ~2.5" edge from RED_SQUAD (>2" ER, <3")
	sel = cons.select_mode("BLUE_SQUAD", be)
	_check("unengaged, enemy within 3\" -> ENGAGING (mandatory)",
		sel.mode == "engaging" and sel.mandatory, str(sel))
	# pg-43: no enemies within 3" but an objective is -> objective mode.
	var bo = _pg41_board()
	bo.units["RED_MONSTER"].models[0].position = {"x": 2000, "y": 2000}
	bo.units["RED_MONSTER"].flags["was_eligible_to_fight"] = true
	bo["board"] = {"objectives": [{"id": "obj1", "position": {"x": 2000, "y": 2120}}]}
	sel = cons.select_mode("RED_MONSTER", bo)
	_check("pg-43: no enemy within 3\", objective within 3\" -> OBJECTIVE (mandatory)",
		sel.mode == "objective" and sel.mandatory, str(sel))
	var octx = cons.before_moving("RED_MONSTER", bo, null, {})
	_check("objective context carries the marker", octx.objective == "obj1", str(octx))
	mv = cons.model_move_allowed("RED_MONSTER", bo.units["RED_MONSTER"].models[0],
		{"x": 2000, "y": 2080}, bo, octx)
	_check("objective mode: ending within range allowed", mv.allowed, str(mv))
	mv = cons.model_move_allowed("RED_MONSTER", bo.units["RED_MONSTER"].models[0],
		{"x": 2000, "y": 1900}, bo, octx)
	_check("objective mode: moving away refused", not mv.allowed)
	bo.units["RED_MONSTER"].models[0].position = {"x": 2000, "y": 2080}
	_check("objective mode AFTER: within range passes",
		cons.after_moving_conditions("RED_MONSTER", bo, octx).ok)
	# Nothing applies: no mode, no move.
	var bn = _pg41_board()
	bn.units["RED_MONSTER"].models[0].position = {"x": 2400, "y": 2400}
	bn.units["RED_MONSTER"].flags["was_eligible_to_fight"] = true
	sel = cons.select_mode("RED_MONSTER", bn)
	_check("nothing within range: no consolidation mode (cannot move)", sel.mode == "", str(sel))
	# Engaging AFTER: must engage all selected; unfought engaged enemies
	# are forced to fight (opponent selects).
	be.units["BLUE_SQUAD"].models[0].position = {"x": 400, "y": 545}  # engaged with RED_SQUAD only
	var ectx = {"mode": "engaging", "targets": ["RED_SQUAD"], "started_engaged_with": []}
	_check("engaging AFTER: engaged with all selected units passes",
		cons.after_moving_conditions("BLUE_SQUAD", be, ectx).ok)
	var forced = cons.forced_fights_after_engaging("BLUE_SQUAD", be, {})
	_check("engaging: unfought engaged enemies become forced fights (12.08)",
		forced == ["RED_SQUAD"], str(forced))
	forced = cons.forced_fights_after_engaging("BLUE_SQUAD", be, {"RED_SQUAD": true})
	_check("already-fought enemies are not re-selected", forced.is_empty())

	print("\n-- fight sequencer: pg-41 worked example (12.04-12.06) --")
	b = _pg41_board()
	var seq = FightSequencer.new()
	seq.begin(b, 1)
	var pick = seq.next_selection(b)
	_check("1) active (RED) player selects first in Fights First combats",
		pick.player == 1 and pick.step == "fights_first" and "RED_MONSTER" in pick.candidates, str(pick))
	var ft = seq.select_to_fight("RED_MONSTER", b)
	_check("monster fights a NORMAL fight (engaged)", ft.fight_type == "normal")
	_kill(b, "BLUE_TRANSPORT")  # the monster destroys the transport
	pick = seq.next_selection(b)
	_check("2-3) BLUE has no Fights First units -> RED selects again (pass rule)",
		pick.player == 1 and pick.step == "fights_first" and pick.candidates == ["RED_SQUAD"], str(pick))
	ft = seq.select_to_fight("RED_SQUAD", b)
	_check("4) charge-survivor: unengaged but engaged at step start -> OVERRUN fight",
		ft.fight_type == "overrun", str(ft))
	_check("overrun unit may make the extra pile-in (selected_for_overrun eligibility)",
		true)
	# The overrun pile-in engages BLUE_SQUAD (the disembarked unit).
	b.units["RED_SQUAD"].models[0].position = {"x": 660, "y": 440}
	pick = seq.next_selection(b)
	_check("5) newly engaged BLUE_SQUAD becomes eligible and fights back",
		pick.player == 2 and pick.candidates == ["BLUE_SQUAD"], str(pick))
	ft = seq.select_to_fight("BLUE_SQUAD", b)
	_check("blue fights a NORMAL fight (now engaged) and may also overrun (engaged mid-phase)",
		"normal" in ft.fight_types and "overrun" in ft.fight_types, str(ft))
	pick = seq.next_selection(b)
	_check("6) all eligible units have fought: Fight step ends", pick.done)

	print("\n-- sequencer pass rules + return-to-Fights-First --")
	b = _pg41_board()
	b.units["RED_MONSTER"].flags.erase("fights_first")
	b.units["RED_SQUAD"].flags.erase("fights_first")
	b.units["RED_SQUAD"].flags.erase("charged_this_turn")
	b.units["RED_MONSTER"].flags.erase("charged_this_turn")
	seq = FightSequencer.new()
	seq.begin(b, 1)
	pick = seq.next_selection(b)
	_check("no FF units anywhere: straight to remaining combats with the active player",
		pick.step == "remaining" and pick.player == 1, str(pick))
	seq.select_to_fight("RED_MONSTER", b)
	pick = seq.next_selection(b)
	_check("alternation: BLUE picks next", pick.player == 2, str(pick))
	seq.select_to_fight("BLUE_TRANSPORT", b)
	# RED_SQUAD still eligible; give BLUE_SQUAD Fights First and engage it
	# mid-step: after a fight resolves, the step returns to FF.
	b.units["BLUE_SQUAD"].flags["fights_first"] = true
	b.units["BLUE_SQUAD"].models[0].position = {"x": 460, "y": 520}  # engage RED_SQUAD
	seq.after_fight_resolved(b)
	pick = seq.next_selection(b)
	_check("a Fights First unit became eligible mid-step: return to FF combats (12.04)",
		pick.step == "fights_first" and pick.candidates == ["BLUE_SQUAD"], str(pick))

	GameConstants.edition = 10
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
