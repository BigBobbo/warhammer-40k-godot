extends SceneTree

# AIPositionSim — the position look-ahead that feeds the game forecast —
# on small synthetic worlds (no game needed: pure data in, pure data out):
#
#  * reach: a unit one Move away controls the objective at the end of this
#    turn; two Moves away, not until its next turn; an Advance gets there sooner.
#  * ownership: more OC wins, equal OC is mostly nobody's, nothing near = [0, 0].
#  * damage: a shooter in range wears its target down (expected kills > 0 and
#    the target's OC share falls); out of range, or with damage off, nothing.
#  * charges: P(2D6 >= d); a charger in reach fights and is fought back.
#  * policy: a free unit walks to the nearest objective its side does not
#    already out-OC; with policy off it stays.
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
	return {"side": side, "pos": pos, "move": move, "oc": oc, "wounds": wounds, "radius": 1.5,
		"seeker": false, "charger": false, "shoot": {}, "melee": {}}

func _world(units: Dictionary, active: int = 1) -> Dictionary:
	return {"units": units, "objectives": [{"id": "obj_a", "pos": Vector2(20, 20)}, {"id": "obj_b", "pos": Vector2(20, 50)}],
		"first": 1, "active": active, "round": 2}

func _run():
	if _ran:
		return
	_ran = true
	await process_frame

	# --- reach
	var w := _world({"A": _u(1, Vector2(20, 28)), "E": _u(2, Vector2(40, 58))})
	var go := {"A": {"mode": "move", "goal": Vector2(20, 20), "goal_obj": "obj_a"}}
	var r: Dictionary = PS.run(w, go, {"damage": false, "policy": false})
	_check(r.turns.size() == 4 and int(r.turns[0].side) == 1 and int(r.turns[1].side) == 2 and int(r.turns[2].round) == 3,
		"two rounds from P1's turn = 4 player turns in play order")
	_check(float(r.turns[0].own_start.obj_a[0]) == 0.0 and float(r.turns[0].own_end.obj_a[0]) > 0.9,
		"8 in away, Move 6: on the objective (3 in control range) at the end of this turn (%.2f)" % float(r.turns[0].own_end.obj_a[0]))
	var w_far := _world({"A": _u(1, Vector2(20, 36)), "E": _u(2, Vector2(40, 58))})
	var r_far: Dictionary = PS.run(w_far, go, {"damage": false, "policy": false})
	_check(float(r_far.turns[0].own_end.obj_a[0]) < 0.1 and float(r_far.turns[2].own_end.obj_a[0]) > 0.9,
		"16 in away: not this turn (%.2f), there after its next turn (%.2f)" % [float(r_far.turns[0].own_end.obj_a[0]), float(r_far.turns[2].own_end.obj_a[0])])
	var w_adv := _world({"A": _u(1, Vector2(20, 34)), "E": _u(2, Vector2(40, 58))})
	var r_mv: Dictionary = PS.run(w_adv, go, {"damage": false, "policy": false})
	var r_ad: Dictionary = PS.run(w_adv, {"A": {"mode": "advance", "goal": Vector2(20, 20), "goal_obj": "obj_a"}}, {"damage": false, "policy": false})
	_check(float(r_ad.turns[0].own_end.obj_a[0]) > float(r_mv.turns[0].own_end.obj_a[0]) + 0.3,
		"an Advance arrives a turn sooner than a Normal move (%.2f vs %.2f)" % [float(r_ad.turns[0].own_end.obj_a[0]), float(r_mv.turns[0].own_end.obj_a[0])])
	var r_stay: Dictionary = PS.run(w, {"A": {"mode": "stay", "goal_obj": ""}}, {"damage": false, "policy": false})
	_check(float(r_stay.turns[3].own_end.obj_a[0]) == 0.0, "a unit told to stay, with policy off, never takes it")
	_check((w.units.A.pos as Vector2) == Vector2(20, 28), "the world passed in is not modified")

	# --- ownership
	var own: Dictionary = PS.ownership({"A": _u(1, Vector2(20, 20), 6.0), "B": _u(2, Vector2(21, 20), 2.0)}, w.objectives, {})
	_check(float(own.obj_a[0]) > 0.8 and float(own.obj_a[1]) < 0.1, "OC 6 vs 2: the bigger side controls it (%.2f / %.2f)" % [float(own.obj_a[0]), float(own.obj_a[1])])
	own = PS.ownership({"A": _u(1, Vector2(20, 20), 4.0), "B": _u(2, Vector2(21, 20), 4.0)}, w.objectives, {})
	_check(float(own.obj_a[0]) < 0.3 and absf(float(own.obj_a[0]) - float(own.obj_a[1])) < 0.01, "equal OC: mostly nobody's (%.2f each)" % float(own.obj_a[0]))
	_check(float(own.obj_b[0]) == 0.0 and float(own.obj_b[1]) == 0.0, "nothing near: nobody")
	_check(PS.oc_weight(_u(1, Vector2(20, 23.5)), Vector2(20, 20)) == 1.0 and PS.oc_weight(_u(1, Vector2(20, 30)), Vector2(20, 20)) == 0.0,
		"OC counts in control range and not well outside it")

	# --- damage
	var sh := _u(1, Vector2(20, 40))
	sh.shoot = {"E": [[24.0, 8.0]]}
	var w_sh := _world({"S": sh, "E": _u(2, Vector2(20, 51), 5.0, 6.0, 10.0)})
	var stay := {"S": {"mode": "stay", "goal_obj": ""}}
	var r_d: Dictionary = PS.run(w_sh, stay, {"damage": true, "policy": false, "los": 1.0})
	_check(float(r_d.turns[0].lam[1]) > 0.1 and float(r_d.units.E.x) > 0.7,
		"a shooter in range wears the target down (damage ratio %.2f, expected kills %.2f)" % [float(r_d.units.E.x), float(r_d.turns[0].lam[1])])
	_check(float(r_d.turns[0].own_end.obj_b[1]) < float(r_d.turns[0].own_start.obj_b[1]),
		"and the target's hold on its objective weakens (%.2f -> %.2f)" % [float(r_d.turns[0].own_start.obj_b[1]), float(r_d.turns[0].own_end.obj_b[1])])
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
	var r_np: Dictionary = PS.run(w_p, {}, {"damage": false, "policy": false})
	_check((r_np.units.A.pos as Vector2) == Vector2(20, 38), "policy off: it stays")

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
	var fg2: Dictionary = FC.forecast(Pg)
	_check(float(fg2.mean[1]) == float(fg.mean[1]), "same inputs, same answer")
	var Pfull: Dictionary = Pg.duplicate()
	Pfull.erase("end_round")
	_check(float(FC.forecast(Pfull).mean[1]) > float(fg.mean[1]), "end_round stops the count at the window; without it the game runs to round 5")

	print("\n%d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
