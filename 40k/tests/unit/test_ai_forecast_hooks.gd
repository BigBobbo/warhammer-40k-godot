extends SceneTree

# The AI's uses of the game forecast (AIForecast.gd), on synthetic states:
#
#  * AIForecast.build_from_snapshot — objective classes (home / expansion side
#    by the nearer home / central), turn order and the "next_turn" roll-over,
#    observed kill rate blended with the prior, battle over -> {}.
#  * FORECAST_SECONDARIES — a kill card whose targets are all dead is swapped
#    (New Orders pick) and discarded for CP; a live card is kept; no CP worth
#    in the last round.
#  * FORECAST_TEMPO — the calibration (A + B * margin + SEAT) is applied and
#    the cached forecast is reused within a turn.
#  * FORECAST_HORIZON — holding an objective has a positive swing; the
#    priority gain is weight x swing / rounds left; off = untouched.
#  * FORECAST_SURVIVAL — state -> hold chance mapping.
#  * position look-ahead — snapshot -> AIPositionSim world, plan -> intents,
#    and a move onto an empty objective priced above standing still.
#  * FORECAST_PLAN — the ownership projection: a unit leaving drops its OC,
#    an arrival this turn adds it, one arriving next turn does not.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_forecast_hooks.gd

const FC = preload("res://scripts/AIForecast.gd")
const AI_PATH := "res://scripts/AIDecisionMaker.gd"

var _pass := 0
var _fail := 0
var _ran := false
var AIDM = null
var _sm = null

func _init():
	create_timer(0.1).timeout.connect(_run)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("PASS: %s" % msg)
	else:
		_fail += 1
		print("FAIL: %s" % msg)

func _run():
	if _ran:
		return
	_ran = true
	await process_frame
	print("\n=== AI forecast hooks ===\n")
	AIDM = load(AI_PATH)
	_sm = root.get_node_or_null("SecondaryMissionManager")
	_check(_sm != null, "SecondaryMissionManager autoload present")
	test_builder()
	test_survival_mapping()
	test_plan_projection()
	test_position_lookahead()
	test_horizon()
	test_tempo_calibration()
	if _sm != null:
		test_secondary_swap_and_discard()
	AIDM._config_overrides.clear()
	print("\n=== Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

# --- synthetic snapshot ------------------------------------------------------

func _unit(owner: int, n: int, keywords: Array, wounds: int = 1, alive: int = -1) -> Dictionary:
	var models: Array = []
	for i in range(n):
		models.append({"id": "m%d" % i, "alive": alive < 0 or i < alive, "wounds": wounds, "current_wounds": wounds,
			"position": {"x": 100.0 * i, "y": 100.0}})
	return {"owner": owner, "status": 2, "models": models,
		"meta": {"keywords": keywords, "stats": {"wounds": wounds, "objective_control": 2}, "name": "u"}}

func _snapshot(round_: int, active: int, phase: int = 6, control: Dictionary = {}) -> Dictionary:
	return {
		"meta": {"battle_round": round_, "active_player": active, "first_turn_player": 1, "phase": phase},
		"players": {"1": {"vp": 10, "primary_vp": 6, "secondary_vp": 4, "cp": 3},
			"2": {"vp": 8, "primary_vp": 5, "secondary_vp": 3, "cp": 3}},
		"board": {"objectives": [
			{"id": "obj_home_1", "designation": "home", "zone": "player1", "position": "(700.0, 470.4)"},
			{"id": "obj_home_2", "designation": "home", "zone": "player2", "position": "(1060.0, 1929.6)"},
			{"id": "obj_nml_1", "designation": "expansion", "zone": "no_mans_land", "position": "(1500.0, 750.0)"},
			{"id": "obj_nml_2", "designation": "expansion", "zone": "no_mans_land", "position": "(260.0, 1650.0)"},
			{"id": "obj_center", "designation": "central", "zone": "no_mans_land", "position": "(880.0, 1200.0)"}]},
		"mission_manager": {
			"objective_control_state": control if not control.is_empty() else {"obj_home_1": 1, "obj_home_2": 2, "obj_nml_1": 1, "obj_nml_2": 2, "obj_center": 0},
			"player_primary_missions": {"1": {"name": "Immovable Object"}, "2": {"name": "Battlefield Dominance"}},
			"kills_per_round": {"1": {"1": 2, "2": 0}},
		},
		"secondary_missions": {"player_state": {
			"1": {"mode": "tactical", "initialized": true, "active": [{"id": "assassination", "name": "Assassination"}],
				"discard": ["no_prisoners"], "deck": ["outflank", "beacon", "centre_ground", "cleanse"]},
			"2": {"mode": "tactical", "initialized": true, "active": [], "discard": [], "deck": ["outflank", "beacon"]}}},
		"units": {
			"A1": _unit(1, 10, ["INFANTRY"]), "A2": _unit(1, 1, ["CHARACTER", "INFANTRY"], 5),
			"B1": _unit(2, 10, ["INFANTRY"]), "B2": _unit(2, 1, ["CHARACTER"], 5, 0), "B3": _unit(2, 1, ["VEHICLE"], 12)},
	}

func test_builder() -> void:
	var snap := _snapshot(2, 2)
	var P: Dictionary = FC.build_from_snapshot(snap, {"trials": 50})
	_check(not P.is_empty(), "builder returns inputs mid-game")
	var cls := {}
	for o in P.objectives:
		cls[o.id] = "%s/%d" % [o.cls, int(o.side)]
	_check(cls.get("obj_home_1") == "home/1" and cls.get("obj_home_2") == "home/2", "home objectives keep their side (%s)" % str(cls))
	_check(cls.get("obj_nml_1") == "exp/1" and cls.get("obj_nml_2") == "exp/2", "expansions belong to the nearer home's half (%s)" % str(cls))
	_check(cls.get("obj_center") == "central/0", "centre is central")
	_check(int(P.start_round) == 2 and int(P.start_turn) == 1 and bool(P.start_after_draw), "this_turn: R2, second player's turn, after the draw")
	var Pn: Dictionary = FC.build_from_snapshot(snap, {"from": "next_turn"})
	_check(int(Pn.start_round) == 3 and int(Pn.start_turn) == 0 and not bool(Pn.start_after_draw), "next_turn after the second player's turn = R3 first turn, draws")
	_check(FC.build_from_snapshot(_snapshot(5, 2), {"from": "next_turn"}).is_empty(), "next_turn after the last turn of R5 = battle over")
	# P1 has finished 2 turns (R1, R2 first) by P2's R2 turn: (1.3*2 + 2 kills) / (2 + 2)
	_check(absf(float(P.players[1].kill_rate) - 4.6 / 4.0) < 0.001, "P1 kill rate blends 2 observed kills over 2 turns with the prior (%.3f)" % float(P.players[1].kill_rate))
	_check(P.players[2].start.destroyed == ["B2"], "a unit with no live model is destroyed (%s)" % str(P.players[2].start.destroyed))
	_check(P.players[1].start.hand == ["assassination"] and P.players[1].start.deck.size() == 4, "hand and remaining deck come from the secondary state")
	_check(str(P.players[1].mission) == "Immovable Object", "primary card name read from the mission manager")
	_check(bool(P.skip_command_primary) == false and bool(FC.build_from_snapshot(_snapshot(2, 2, 7)).skip_command_primary),
		"the Command-phase primary is skipped only once the Command phase is over")

func test_survival_mapping() -> void:
	AIDM._config_overrides = {"FORECAST_SURVIVAL": 1.0}
	_check(AIDM._forecast_state_conf("held_safe", false) == AIDM.FORECAST_SAFE_HOLD
		and AIDM._forecast_state_conf("held_threatened", false) == AIDM.FORECAST_THREAT_HOLD
		and AIDM._forecast_state_conf("enemy_weak", false) == AIDM.FORECAST_THREAT_HOLD
		and AIDM._forecast_state_conf("contested", false) == 0.5, "survival on: hold chance follows the threat state")
	AIDM._config_overrides = {"FORECAST_SURVIVAL": 0.0}
	_check(AIDM._forecast_state_conf("held_threatened", true) == 0.95
		and AIDM._forecast_state_conf("held_threatened", false) == AIDM.FORECAST_HOLD_CONFIDENCE, "survival off: home 0.95, other the flat confidence")
	_check(AIDM._forecast_state_owner("held_safe", 2) == 2 and AIDM._forecast_state_owner("enemy_strong", 2) == 1
		and AIDM._forecast_state_owner("contested", 2) == 0, "state -> projected owner")

func test_plan_projection() -> void:
	AIDM._config_overrides = {"FORECAST_SURVIVAL": 1.0}
	var evals := [
		{"id": "o1", "friendly_oc": 4, "enemy_oc": 3, "projected_enemy_oc": 0},
		{"id": "o2", "friendly_oc": 0, "enemy_oc": 2, "projected_enemy_oc": 0},
		{"id": "o3", "friendly_oc": 0, "enemy_oc": 0, "projected_enemy_oc": 4}]
	AIDM._last_movement_candidates = {
		"U1": [{"objective_id": "o1", "unit_oc": 4, "already_on_obj": true}, {"objective_id": "o2", "unit_oc": 4, "already_on_obj": false}],
		"U2": [{"objective_id": "o3", "unit_oc": 2, "already_on_obj": false}]}
	var hold := {"U1": {"objective_id": "o1", "action": "hold", "already_on_obj": true, "unit_oc": 4},
		"U2": {"objective_id": "o3", "action": "move", "turns_to_reach": 2, "unit_oc": 2}}
	var pr: Dictionary = AIDM._forecast_plan_projection(evals, hold, 1)
	_check(int(pr.cells.o1) == 1 and int(pr.cells.o2) == 2 and int(pr.cells.o3) == 0, "hold plan: o1 ours, o2 theirs, o3 nobody's this turn (%s)" % str(pr.cells))
	var leave := {"U1": {"objective_id": "o2", "action": "move", "turns_to_reach": 1, "unit_oc": 4, "already_on_obj": false},
		"U2": {"objective_id": "o3", "action": "move", "turns_to_reach": 1, "unit_oc": 2}}
	var pr2: Dictionary = AIDM._forecast_plan_projection(evals, leave, 1)
	_check(int(pr2.cells.o1) == 2, "U1 leaving o1 leaves the enemy's 3 OC in control (%s)" % str(pr2.cells))
	_check(int(pr2.cells.o2) == 1, "U1 arriving on o2 this turn (4 OC vs 2) takes it")
	_check(int(pr2.cells.o3) == 1 and float(pr2.conf.o3) == AIDM.FORECAST_THREAT_HOLD,
		"U2 takes o3 this turn but the enemy can bring 4 OC: a threatened hold (%.2f)" % float(pr2.conf.o3))
	AIDM._last_movement_candidates = {}

func test_position_lookahead() -> void:
	# _possim_world: units in inches with OC, wounds and spread; current and
	# secured control carried over; units with no models on the table left out
	var snap := _snapshot(2, 1, 7)
	snap.units["A1"] = _unit_at(1, 5, Vector2(880, 1500))   # 7.5 in below the centre
	snap.units["A2"] = _unit_at(1, 5, Vector2(700, 470))    # on its home objective
	snap.units["B1"] = _unit_at(2, 5, Vector2(1060, 1930))  # on its home objective
	snap.units.erase("B2")
	snap.units.erase("B3")
	snap.mission_manager["sticky_objectives"] = {"obj_nml_2": {"player": 2, "source_unit_id": ""}}
	var world: Dictionary = AIDM._possim_world(snap)
	_check(world.units.size() == 3 and int(world.round) == 2 and int(world.active) == 1 and int(world.first) == 1,
		"world: 3 units on the table, round 2, P1 to move")
	var a1: Dictionary = world.units.A1
	_check(absf((a1.pos as Vector2).x - 22.0) < 0.01 and absf((a1.pos as Vector2).y - 37.5) < 0.01 and float(a1.oc) == 10.0 and float(a1.wounds) == 5.0,
		"a unit: centre in inches (%.1f, %.1f), OC x models (%d), wounds left (%d)" % [(a1.pos as Vector2).x, (a1.pos as Vector2).y, int(a1.oc), int(a1.wounds)])
	_check(int(world.control.get("obj_home_1", 0)) == 1 and int(world.secured.get("obj_nml_2", 0)) == 2,
		"current control and secured objectives are carried in")
	# intents
	var mv: Dictionary = AIDM._possim_intent(snap, {"action": "advance", "objective_id": "obj_center", "objective_pos": Vector2(880, 1200)})
	_check(str(mv.mode) == "advance" and str(mv.goal_obj) == "obj_center" and (mv.goal as Vector2) == Vector2(22, 30), "an advance to an objective -> advance toward it (inches)")
	_check(str(AIDM._possim_intent(snap, {"action": "hold", "objective_id": "obj_home_1"}).mode) == "stay", "a hold -> stay")
	var at: Dictionary = AIDM._possim_intent(snap, {"action": "attack", "attack_target_id": "B1", "objective_id": "obj_center"})
	_check(str(at.get("target", "")) == "B1" and str(at.mode) == "move", "an attack -> move at the target")
	# pricing: walking onto the empty centre beats standing still, over the window
	var P: Dictionary = AIDM._forecast_base_P(snap, 300)
	var go: Dictionary = AIDM._possim_margin(snap, world, {"A1": mv, "A2": {"mode": "stay", "goal_obj": ""}}, 1, P)
	var stay: Dictionary = AIDM._possim_margin(snap, world, {"A1": {"mode": "stay", "goal_obj": ""}, "A2": {"mode": "stay", "goal_obj": ""}}, 1, P, {"policy": false})
	var go_np: Dictionary = AIDM._possim_margin(snap, world, {"A1": mv, "A2": {"mode": "stay", "goal_obj": ""}}, 1, P, {"policy": false})
	_check(float(go_np.margin) > float(stay.margin) + 1.0,
		"taking the centre (Immovable Object) is worth VP by the end of next round (%+.1f vs %+.1f)" % [float(go_np.margin), float(stay.margin)])
	_check(go.sim.turns.size() == 4 and float(go.sim.turns[0].own_end.obj_center[0]) > 0.5,
		"the window is this round and the next (4 player turns) and the centre is ours at the end of this turn")
	_check(AIDM.FORECAST_PLAN == 1.0 and AIDM.FORECAST_POSSIM == 1.0 and AIDM.FORECAST_POSSIM_TURNS == 1 and AIDM.FORECAST_POSSIM_DAMAGE == 0.0,
		"shipped: plan swaps priced by the look-ahead, this turn only, reach only (the full window lost 8 VP a game)")

func _unit_at(owner: int, n: int, at: Vector2) -> Dictionary:
	var u := _unit(owner, n, ["INFANTRY"])
	for i in range(n):
		u.models[i]["position"] = {"x": at.x + 20.0 * (i - n / 2), "y": at.y}
	u.meta.stats["move"] = 6
	return u

func test_horizon() -> void:
	var snap := _snapshot(2, 1)
	var evals := [
		{"id": "obj_home_1", "state": "held_safe", "is_home": true, "priority": 10.0},
		{"id": "obj_home_2", "state": "enemy_strong", "is_enemy_home": true, "priority": 10.0},
		{"id": "obj_nml_1", "state": "held_threatened", "priority": 10.0},
		{"id": "obj_nml_2", "state": "enemy_weak", "priority": 10.0},
		{"id": "obj_center", "state": "uncontrolled", "priority": 10.0}]
	AIDM._config_overrides = {"FORECAST_HORIZON_WEIGHT": 0.0}
	var off := evals.duplicate(true)
	AIDM._apply_forecast_horizon(snap, off, 1, 2)
	_check(float(off[2].priority) == 10.0 and not off[2].has("forecast_swing"), "weight 0: priorities untouched")
	AIDM._config_overrides = {"FORECAST_HORIZON_WEIGHT": 0.6, "FORECAST_HORIZON_TRIALS": 400}
	AIDM._forecast_horizon_cache.clear()
	var on := evals.duplicate(true)
	AIDM._apply_forecast_horizon(snap, on, 1, 2)
	var all_pos := true
	for ev in on:
		all_pos = all_pos and float(ev.get("forecast_swing", -1.0)) > 0.0
	_check(all_pos, "holding any objective from now on beats the opponent holding it (swings %s)" % str(on.map(func(e): return snappedf(float(e.get("forecast_swing", 0.0)), 0.1))))
	# P1 plays Immovable Object (5 VP per NON-home objective from R2): a
	# non-home objective must swing more than its own home
	_check(float(on[2].forecast_swing) > float(on[0].forecast_swing),
		"Immovable Object: an NML objective (%.1f) swings more than its own home (%.1f)" % [float(on[2].forecast_swing), float(on[0].forecast_swing)])
	var expect: float = 10.0 + 0.6 * float(on[2].forecast_swing) / 4.0
	_check(absf(float(on[2].priority) - expect) < 0.001, "priority gain = weight x swing / rounds left (%.2f)" % float(on[2].priority))
	var before := Time.get_ticks_msec()
	AIDM._forecast_objective_swings(snap, evals, 1, 2)
	_check(Time.get_ticks_msec() - before < 20, "swings are cached for the rest of the turn")

func test_tempo_calibration() -> void:
	var snap := _snapshot(3, 1)
	var late := _snapshot(4, 1)
	AIDM._forecast_tempo_cache.clear()
	_check(AIDM.FORECAST_CAL_A == 0.0 and AIDM.FORECAST_CAL_B == 1.5 and AIDM.FORECAST_CAL_SEAT == 9.4, "shipped calibration = the 2026-11-20 mirror fit")
	AIDM._config_overrides = {"FORECAST_CAL_A": 0.0, "FORECAST_CAL_B": 1.0, "FORECAST_CAL_SEAT": 0.0}
	var raw: Dictionary = AIDM._forecast_game(snap, 1)
	_check(absf(float(raw.margin) - float(raw.raw_margin)) < 0.001, "identity calibration: margin = raw forecast margin (%.1f)" % float(raw.margin))
	AIDM._config_overrides = {"FORECAST_CAL_A": 2.0, "FORECAST_CAL_B": 0.5, "FORECAST_CAL_SEAT": 3.0}
	var cal: Dictionary = AIDM._forecast_game(snap, 1)
	_check(absf(float(cal.margin) - (2.0 + 0.5 * float(cal.raw_margin) + 3.0)) < 0.001, "calibrated margin = A + B*raw + SEAT (first player) (%.1f)" % float(cal.margin))
	var cal2: Dictionary = AIDM._forecast_game(snap, 2)
	_check(absf(float(cal2.margin) - (2.0 + 0.5 * float(cal2.raw_margin) - 3.0)) < 0.001, "second player gets -SEAT")
	var cal4: Dictionary = AIDM._forecast_game(late, 1)
	_check(absf(float(cal4.margin) - (2.0 + 0.5 * float(cal4.raw_margin))) < 0.001, "no seat term after FORECAST_CAL_SEAT_LAST_ROUND (round 4)")
	_check((float(cal.margin) > 0.0) == (float(cal.cal_p_win) > 0.5), "calibrated win chance sits on the calibrated margin's side (%.2f)" % float(cal.cal_p_win))
	AIDM._config_overrides = {"FORECAST_TEMPO": 1.0}
	AIDM._forecast_tempo_cache.clear()
	var m1: float = AIDM._calculate_tempo_modifier(snap, 1)
	var t0 := Time.get_ticks_msec()
	var m2: float = AIDM._calculate_tempo_modifier(snap, 1)
	_check(m1 == m2 and Time.get_ticks_msec() - t0 < 20, "tempo forecast cached within the turn (%.2f)" % m1)

func test_secondary_swap_and_discard() -> void:
	var saved: Dictionary = _sm.get_save_data()
	var snap := _snapshot(2, 1)
	# P1 holds Assassination; P2's only CHARACTER (B2) is dead -> worthless
	var st := {"player_state": {
		"1": {"mode": "tactical", "initialized": true, "deck": ["outflank", "beacon", "centre_ground", "cleanse", "secure_no_mans_land"],
			"active": [{"id": "assassination", "name": "Assassination", "scoring": {}}], "discard": [], "secondary_vp": 0},
		"2": {"mode": "tactical", "initialized": true, "deck": ["outflank"], "active": [], "discard": [], "secondary_vp": 0}}}
	_sm.load_save_data(st)
	snap["secondary_missions"] = st
	AIDM._config_overrides = {"FORECAST_SECONDARIES": 1.0}
	var pick: Dictionary = AIDM._forecast_pick_swap(snap, 1, [{"index": 0, "id": "assassination", "name": "Assassination"}], "New Orders")
	_check(int(pick.index) == 0 and float(pick.keep) < 0.1 and float(pick.draw) > 2.0,
		"a kill card with no target left is swapped (keep %.2f, draw %.2f)" % [float(pick.keep), float(pick.draw)])
	# B2 alive again -> the card is live and kept
	snap.units["B2"] = _unit(2, 1, ["CHARACTER"], 5)
	var keep: Dictionary = AIDM._forecast_pick_swap(snap, 1, [{"index": 0, "id": "assassination", "name": "Assassination"}], "New Orders")
	var live_keep: float = float(keep.scored[0].score_breakdown.forecast_keep_vp)
	_check(int(keep.index) == -1 and live_keep > float(keep.draw) - AIDM.FORECAST_CP_VP - AIDM.FORECAST_SWAP_MARGIN,
		"a live Assassination is kept (keep %.2f vs draw %.2f)" % [live_keep, float(keep.draw)])
	_check(AIDM._forecast_cp_value(_snapshot(5, 1), 1, true) == 0.0 and AIDM._forecast_cp_value(_snapshot(4, 2), 2, true) > 0.0,
		"a CP gained at the end of R5 is worth nothing; at the end of R4 it is")
	_sm.load_save_data(saved)
