extends SceneTree

# AIPositionSim — the position look-ahead that feeds the game forecast —
# on small synthetic worlds (no game needed: pure data in, pure data out):
#
#  * reach: a unit one Move away controls the objective at the end of this
#    turn; two Moves away, not until its next turn; an Advance gets there sooner.
#  * ownership: more OC wins (a narrow lead is a lean), equal OC is mostly
#    nobody's; an empty objective stays with its last controller most of the
#    time and for certain when secured, until the other side out-OCs it.
#  * damage: a shooter in range wears its target down (expected kills > 0 and
#    the target's OC share falls); out of range, or with damage off, nothing.
#  * charges: P(2D6 >= d); a charger in reach fights and is fought back.
#  * policy: a free unit walks to the nearest objective its side does not
#    already out-OC; a unit alone on an objective keeps it, and of two sharing
#    one the nearer keeps it while the other moves on; policy off = stay.
#  * AIForecast turn_plan: holding an objective from the sim's rows is worth
#    more VP than not holding it, over the same window, on common random numbers.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_position_sim.gd

const PS = preload("res://scripts/AIPositionSim.gd")
const FC = preload("res://scripts/AIForecast.gd")

var _pass := 0
var _fail := 0
var _ran := false

func _init():
	create_timer(0.1).timeout.connect(_run)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("PASS: %s" % msg)
	else:
		_fail += 1
		print("FAIL: %s" % msg)

func _u(side: int, pos: Vector2, oc: float = 5.0, move: float = 6.0, wounds: float = 10.0) -> Dictionary:
	return {"side": side, "pos": pos, "move": move, "oc": oc, "wounds": wounds, "radius": 1.0,
		"seeker": false, "charger": false, "shoot": {}, "melee": {}}

func _world(units: Dictionary, active: int = 1) -> Dictionary:
	return {"units": units, "objectives": [{"id": "obj_a", "pos": Vector2(20, 20)}, {"id": "obj_b", "pos": Vector2(20, 50)}],
		"first": 1, "active": active, "round": 2}

func _run():
	if _ran:
		return
	_ran = true
	await process_frame

	# --- reach (unit spread 1.0: counts fully within 2.5 in, not at all past 8.5 in)
	var w := _world({"A": _u(1, Vector2(20, 30)), "E": _u(2, Vector2(40, 58))})
	var go := {"A": {"mode": "move", "goal": Vector2(20, 20), "goal_obj": "obj_a"}}
	var r: Dictionary = PS.run(w, go, {"damage": false, "policy": false})
	_check(r.turns.size() == 4 and int(r.turns[0].side) == 1 and int(r.turns[1].side) == 2 and int(r.turns[2].round) == 3,
		"two rounds from P1's turn = 4 player turns in play order")
	_check(float(r.turns[0].own_start.obj_a[0]) == 0.0 and float(r.turns[0].own_end.obj_a[0]) > 0.6,
		"10 in away, Move 6: holds the objective at the end of this turn (%.2f)" % float(r.turns[0].own_end.obj_a[0]))
	_check(float(r.turns[2].own_end.obj_a[0]) > float(r.turns[0].own_end.obj_a[0]),
		"and more surely once it has closed in on its next turn (%.2f)" % float(r.turns[2].own_end.obj_a[0]))
	var w_far := _world({"A": _u(1, Vector2(20, 38)), "E": _u(2, Vector2(40, 58))})
	var r_far: Dictionary = PS.run(w_far, go, {"damage": false, "policy": false})
	_check(float(r_far.turns[0].own_end.obj_a[0]) < 0.05 and float(r_far.turns[2].own_end.obj_a[0]) > 0.6,
		"18 in away: not this turn (%.2f), there after its next turn (%.2f)" % [float(r_far.turns[0].own_end.obj_a[0]), float(r_far.turns[2].own_end.obj_a[0])])
	var w_adv := _world({"A": _u(1, Vector2(20, 34.5)), "E": _u(2, Vector2(40, 58))})
	var r_mv: Dictionary = PS.run(w_adv, go, {"damage": false, "policy": false})
	var r_ad: Dictionary = PS.run(w_adv, {"A": {"mode": "advance", "goal": Vector2(20, 20), "goal_obj": "obj_a"}}, {"damage": false, "policy": false})
	_check(float(r_ad.turns[0].own_end.obj_a[0]) > float(r_mv.turns[0].own_end.obj_a[0]) + 0.2,
		"an Advance gets a hold a turn sooner than a Normal move (%.2f vs %.2f)" % [float(r_ad.turns[0].own_end.obj_a[0]), float(r_mv.turns[0].own_end.obj_a[0])])
	var r_stay: Dictionary = PS.run(w, {"A": {"mode": "stay", "goal_obj": ""}}, {"damage": false, "policy": false})
	_check(float(r_stay.turns[3].own_end.obj_a[0]) == 0.0, "a unit told to stay 10 in away, with policy off, never takes it")
	_check((w.units.A.pos as Vector2) == Vector2(20, 30), "the world passed in is not modified")

	# --- ownership
	var own: Dictionary = PS.ownership({"A": _u(1, Vector2(20, 20), 12.0), "B": _u(2, Vector2(21, 20), 2.0)}, w.objectives, {})
	_check(float(own.obj_a[0]) > 0.9 and float(own.obj_a[1]) < 0.05, "OC 12 vs 2: the bigger side controls it (%.2f / %.2f)" % [float(own.obj_a[0]), float(own.obj_a[1])])
	var own_close: Dictionary = PS.ownership({"A": _u(1, Vector2(20, 20), 6.0), "B": _u(2, Vector2(21, 20), 4.0)}, w.objectives, {})
	_check(float(own_close.obj_a[0]) > float(own_close.obj_a[1]) and float(own_close.obj_a[0]) < float(own.obj_a[0]),
		"a narrow OC lead is a lean, not a certainty (%.2f / %.2f)" % [float(own_close.obj_a[0]), float(own_close.obj_a[1])])
	own = PS.ownership({"A": _u(1, Vector2(20, 20), 4.0), "B": _u(2, Vector2(21, 20), 4.0)}, w.objectives, {})
	_check(float(own.obj_a[0]) < 0.3 and absf(float(own.obj_a[0]) - float(own.obj_a[1])) < 0.01, "equal OC: mostly nobody's (%.2f each)" % float(own.obj_a[0]))
	_check(float(own.obj_b[0]) == 0.0 and float(own.obj_b[1]) == 0.0, "nothing near and never held: nobody")
	_check(PS.oc_weight(_u(1, Vector2(20, 22)), Vector2(20, 20)) == 1.0 and PS.oc_weight(_u(1, Vector2(20, 30)), Vector2(20, 20)) == 0.0,
		"OC counts in control range and not well outside it")
	_check(PS.oc_weight(_u(1, Vector2(20, 26)), Vector2(20, 20)) > 0.0 and PS.oc_weight(_u(1, Vector2(20, 26)), Vector2(20, 20)) < 1.0,
		"a unit strung out toward an objective holds it with part of its models")
	# nobody there now: it stays with the last controller most of the time,
	# and for certain when that side has it secured (11e 14.03)
	var far := {"A": _u(1, Vector2(40, 40))}
	var kept: Dictionary = PS.ownership(far, w.objectives, {}, {"obj_a": [1.0, 0.0]})
	_check(absf(float(kept.obj_a[0]) - PS.DEFAULTS.stick) < 0.001 and float(kept.obj_a[1]) == 0.0,
		"an empty objective stays with its last controller %d%% of the time" % int(PS.DEFAULTS.stick * 100.0))
	var sec: Dictionary = PS.ownership(far, w.objectives, {}, {"obj_a": [1.0, 0.0]}, {"obj_a": 1})
	_check(float(sec.obj_a[0]) == 1.0, "a secured objective stays for certain")
	var taken: Dictionary = PS.ownership({"B": _u(2, Vector2(20, 20), 10.0)}, w.objectives, {}, {"obj_a": [1.0, 0.0]}, {"obj_a": 1})
	_check(float(taken.obj_a[1]) > 0.9 and float(taken.obj_a[0]) < 0.1, "until the other side out-OCs it (%.2f theirs)" % float(taken.obj_a[1]))
	var wc := _world({"A": _u(1, Vector2(40, 40)), "E": _u(2, Vector2(40, 58))})
	wc["control"] = {"obj_a": 1}
	var r_c0: Dictionary = PS.run(wc, {}, {"damage": false, "policy": false})
	_check(float(r_c0.turns[0].own_start.obj_a[0]) == 1.0 and float(r_c0.turns[1].own_end.obj_a[0]) < float(r_c0.turns[0].own_end.obj_a[0]),
		"current control is carried into the sim and fades turn by turn while nobody is there")

	# --- damage
	var sh := _u(1, Vector2(20, 40))
	sh.shoot = {"E": [[24.0, 8.0]]}
	var w_sh := _world({"S": sh, "E": _u(2, Vector2(20, 51), 5.0, 6.0, 10.0)})
	var stay := {"S": {"mode": "stay", "goal_obj": ""}}
	var r_d: Dictionary = PS.run(w_sh, stay, {"damage": true, "policy": false, "los": 1.0, "lethality": 1.0})
	_check(float(r_d.turns[0].lam[1]) > 0.1 and float(r_d.units.E.x) > 0.7,
		"a shooter in range wears the target down (damage ratio %.2f, expected kills %.2f)" % [float(r_d.units.E.x), float(r_d.turns[0].lam[1])])
	_check(float(r_d.turns[0].own_end.obj_b[1]) > 0.0 and PS.alive(r_d.units.E) < 0.3,
		"and the target has little left to hold its objective with (%.2f of its strength)" % PS.alive(r_d.units.E))
	var r_half: Dictionary = PS.run(w_sh, stay, {"damage": true, "policy": false, "los": 1.0, "lethality": 0.5, "end_round": 2})
	var r_full: Dictionary = PS.run(w_sh, stay, {"damage": true, "policy": false, "los": 1.0, "lethality": 1.0, "end_round": 2})
	_check(absf(float(r_half.units.E.x) * 2.0 - float(r_full.units.E.x)) < 0.001, "lethality scales all damage")
	var r_nd: Dictionary = PS.run(w_sh, stay, {"damage": false, "policy": false})
	_check(float(r_nd.units.E.x) == 0.0 and not r_nd.turns[0].has("lam"), "damage off: nobody is hurt and the forecast keeps its own kill rates")
	sh.shoot = {"E": [[6.0, 8.0]]}
	var r_oor: Dictionary = PS.run(_world({"S": sh, "E": _u(2, Vector2(20, 51))}), stay, {"damage": true, "policy": false, "los": 1.0})
	_check(float(r_oor.units.E.x) == 0.0, "out of range: no damage")
	_check(PS.p_dead(0.0) == 0.0 and PS.p_dead(1.0) == 0.5 and PS.p_dead(2.0) == 1.0, "p_dead: 0 unhurt, a coin flip at expected damage = wounds, certain at double")

	# --- charges
	_check(PS.charge_p(2.0) == 1.0 and absf(PS.charge_p(7.0) - 21.0 / 36.0) < 0.001 and PS.charge_p(13.0) == 0.0, "charge odds are 2D6 >= distance")
	var ch := _u(1, Vector2(20, 40))
	ch.charger = true
	ch.melee = {"E": 9.0}
	var tgt := _u(2, Vector2(20, 46))
	tgt.melee = {"C": 3.0}
	var r_c: Dictionary = PS.run(_world({"C": ch, "E": tgt}), {"C": {"mode": "stay", "goal_obj": ""}}, {"damage": true, "policy": false})
	_check(float(r_c.units.E.x) > 0.5 and float(r_c.units.C.x) > 0.0,
		"a charger in reach fights (target %.2f) and is fought back (%.2f)" % [float(r_c.units.E.x), float(r_c.units.C.x)])
	_check((r_c.units.C.pos as Vector2).distance_to(r_c.units.E.pos) < 5.0, "and ends in contact with its target")

	# --- policy
	var w_p := _world({"A": _u(1, Vector2(20, 38)), "H": _u(1, Vector2(20, 20), 10.0), "E": _u(2, Vector2(40, 58))}, 2)
	var r_p: Dictionary = PS.run(w_p, {}, {"damage": false, "policy": true})
	_check((r_p.units.A.pos as Vector2).distance_to(Vector2(20, 50)) < 4.0,
		"a free unit walks to the objective its side does not already hold, not the nearer one that is covered")
	_check((r_p.units.H.pos as Vector2) == Vector2(20, 20), "a unit alone on an objective keeps it")
	var r_np: Dictionary = PS.run(w_p, {}, {"damage": false, "policy": false})
	_check((r_np.units.A.pos as Vector2) == Vector2(20, 38), "policy off: it stays")
	var w_k := _world({"K1": _u(1, Vector2(20, 20)), "K2": _u(1, Vector2(20, 21.5)), "E": _u(2, Vector2(40, 58))}, 2)
	var r_k: Dictionary = PS.run(w_k, {}, {"damage": false, "policy": true})
	_check((r_k.units.K1.pos as Vector2) == Vector2(20, 20) and (r_k.units.K2.pos as Vector2).distance_to(Vector2(20, 50)) < (w_k.units.K2.pos as Vector2).distance_to(Vector2(20, 50)),
		"two units sharing an objective: the nearer one keeps it, the other moves on")

	# --- this turn only (sim_turns = 1): later turns hold ownership as it stands
	var w_t := _world({"A": _u(1, Vector2(20, 30)), "E": _u(2, Vector2(20, 60))})
	var r_t1: Dictionary = PS.run(w_t, go, {"damage": false, "policy": true, "sim_turns": 1})
	var r_all: Dictionary = PS.run(w_t, go, {"damage": false, "policy": true})
	_check(r_t1.turns.size() == 4 and str(r_t1.turns[1].own_end) == str(r_t1.turns[0].own_end) and str(r_t1.turns[3].own_end) == str(r_t1.turns[0].own_end),
		"sim_turns 1: still 4 rows for the window, ownership frozen after this turn")
	_check(str(r_t1.turns[0].own_end) == str(r_all.turns[0].own_end), "and this turn is played exactly as in the full look-ahead")
	_check((r_t1.units.E.pos as Vector2) == Vector2(20, 60) and (r_all.units.E.pos as Vector2) != Vector2(20, 60),
		"the enemy's reply is not played (it is in the full look-ahead)")
	var sh2 := _u(1, Vector2(20, 40))
	sh2.shoot = {"E": [[24.0, 8.0]]}
	var r_t1d: Dictionary = PS.run(_world({"S": sh2, "E": _u(2, Vector2(20, 51))}), {"S": {"mode": "stay", "goal_obj": ""}}, {"damage": true, "policy": false, "sim_turns": 1})
	_check(r_t1d.turns[0].has("lam") and not r_t1d.turns[1].has("lam"), "expected kills are given for the played turn only; later turns keep the forecast's own rates")

	# --- into the forecast
	var objs := [{"id": "obj_a", "cls": "central", "side": 0}, {"id": "obj_b", "cls": "home", "side": 2}]
	var army := FC.army_profile([{"name": "X", "models": 5, "characters": 0, "characters_w4": 0, "w10": 0, "ss13": false, "aircraft": false}])
	var P := {"players": {
			1: {"mission": "Immovable Object", "mode": "tactical", "army": army, "start": {"hand": [], "used": []}},
			2: {"mission": "Immovable Object", "mode": "tactical", "army": army, "start": {"hand": [], "used": []}}},
		"objectives": objs, "plan": {}, "first": 1, "start_round": 2, "start_turn": 0, "start_after_draw": true,
		"skip_command_primary": true, "trials": 300, "seed": 5, "crn": true, "end_round": 3}
	var Pg: Dictionary = P.duplicate()
	Pg["turn_plan"] = r.turns
	var Ps: Dictionary = P.duplicate()
	Ps["turn_plan"] = r_stay.turns
	var fg: Dictionary = FC.forecast(Pg)
	var fs: Dictionary = FC.forecast(Ps)
	_check(float(fg.mean[1]) > float(fs.mean[1]) + 3.0,
		"taking the centre this turn is worth VP over the two-round window (%.1f vs %.1f)" % [float(fg.mean[1]), float(fs.mean[1])])
	_check(absf(float(fg.mean[2]) - float(fs.mean[2])) < 1.5, "and the other player's score barely moves on common random numbers (%.1f vs %.1f)" % [float(fg.mean[2]), float(fs.mean[2])])
	var fst: Dictionary = FC.forecast(Ps)
	_check(float(fst.mean[2]) == float(fs.mean[2]), "common random numbers: the same plan gives the same score twice")
	var fg2: Dictionary = FC.forecast(Pg)
	_check(float(fg2.mean[1]) == float(fg.mean[1]), "same inputs, same answer")
	var Pfull: Dictionary = Pg.duplicate()
	Pfull.erase("end_round")
	_check(float(FC.forecast(Pfull).mean[1]) > float(fg.mean[1]), "end_round stops the count at the window; without it the game runs to round 5")

	print("\n%d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
