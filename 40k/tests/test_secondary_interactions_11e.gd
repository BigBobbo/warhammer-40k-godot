extends SceneTree

# 11e secondary-mission interaction & action UX machinery (engine layer):
#  - A Tempting Target: when the drawer's OPPONENT is human, nothing may
#    auto-resolve; the pending interaction is exposed for the dialog and the
#    AI wait-gate. resolve_tempting_target() completes it and fires
#    interaction_resolved.
#  - Beacon: when-drawn requires the DRAWER's unit designation;
#    resolve_beacon_unit() records it, flags the unit, and scoring counts ONLY
#    the designated unit.
#  - Burden of Trust: guards auto-assign (one distinct unit per objective);
#    scoring counts a guarded objective only while the guard is alive, in
#    range, and the objective is controlled.
#  - Plunder: ShootingPhase exposes a PERFORM_SECONDARY_ACTION option for a
#    unit inside forward terrain, once per turn, and the completed action
#    scores 5 VP.
#  - Cleanse (11e): home objectives excluded; distinct objectives counted;
#    completion requires control at end of turn.
#  - Final-round clause: end-of-opponent-turn cards with final_round_clause
#    also score for the ACTIVE player on the game's final turn.
#
# Usage: godot --headless --path . -s tests/test_secondary_interactions_11e.gd

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

func _mk_unit(gs, unit_id: String, owner: int, pos: Vector2, count: int = 3, keywords: Array = ["INFANTRY"], oc: int = 2) -> void:
	var models = []
	for i in range(count):
		models.append({"id": "m%d" % i, "alive": true, "wounds": 2, "current_wounds": 2,
			"base_mm": 32, "base_type": "circular",
			"position": {"x": pos.x + i * 25, "y": pos.y}})
	gs.state["units"][unit_id] = {"id": unit_id, "owner": owner,
		"status": 2,  # UnitStatus.DEPLOYED
		"flags": {},
		"meta": {"name": unit_id, "keywords": keywords, "points": 100, "stats": {"objective_control": oc}},
		"models": models}

var _meas = null

func _px(inches: float) -> float:
	if _meas == null:
		_meas = root.get_node("Measurement")
	return _meas.inches_to_px(inches)

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_secondary_interactions_11e ===\n")
	var mgr = root.get_node_or_null("SecondaryMissionManager")
	var gs = root.get_node_or_null("GameState")
	var mission_mgr = root.get_node_or_null("MissionManager")
	var ai = root.get_node_or_null("AIPlayer")
	_check("autoloads present", mgr != null and gs != null and mission_mgr != null and ai != null)

	GameConstants.edition = 11
	gs.state["meta"]["active_player"] = 2
	gs.state["meta"]["battle_round"] = 2
	# P1 human, P2 AI — the shape of the reported bug (AI draws, human decides)
	if not gs.state["meta"].has("game_config"):
		gs.state["meta"]["game_config"] = {}
	gs.state["meta"]["game_config"]["player1_type"] = "HUMAN"
	gs.state["meta"]["game_config"]["player2_type"] = "AI"

	# Board: 44x60, NML objectives + home objectives, simple DZs
	gs.state["board"]["size"] = {"width": 44, "height": 60}
	gs.state["board"]["objectives"] = [
		{"id": "obj_home_p1", "zone": "player1", "position": Vector2(_px(22), _px(5))},
		{"id": "obj_home_p2", "zone": "player2", "position": Vector2(_px(22), _px(55))},
		{"id": "obj_nml_1", "zone": "no_mans_land", "position": Vector2(_px(10), _px(30))},
		{"id": "obj_nml_2", "zone": "no_mans_land", "position": Vector2(_px(34), _px(30))},
		{"id": "obj_nml_3", "zone": "no_mans_land", "position": Vector2(_px(22), _px(30))},
	]
	gs.state["board"]["deployment_zones"] = [
		{"player": 1, "poly": [{"x": 0, "y": 0}, {"x": 44, "y": 0}, {"x": 44, "y": 12}, {"x": 0, "y": 12}]},
		{"player": 2, "poly": [{"x": 0, "y": 48}, {"x": 44, "y": 48}, {"x": 44, "y": 60}, {"x": 0, "y": 60}]},
	]
	gs.state["units"] = {}

	print("-- A Tempting Target: human opponent keeps the pick --")
	mgr.initialize_for_game()
	mgr.setup_tactical_deck(2)
	var state2 = mgr._player_state["2"]
	# Force-draw a_tempting_target for AI P2 by stacking the deck
	state2["deck"] = ["a_tempting_target"]
	state2["active"] = []
	var drawn = mgr.draw_missions_to_hand(2, 1)
	_check("AI P2 drew A Tempting Target", drawn.size() == 1 and drawn[0]["id"] == "a_tempting_target", str(drawn))
	var att_mission = state2["active"][0] if state2["active"].size() > 0 else {}
	_check("card is pending interaction (NOT auto-resolved by AIPlayer)",
		att_mission.get("pending_interaction", false) == true,
		"pending=%s data=%s" % [str(att_mission.get("pending_interaction")), str(att_mission.get("mission_data", {}))])
	_check("no tempting_target_id was set behind the human's back",
		str(att_mission.get("mission_data", {}).get("tempting_target_id", "")) == "")
	var pendings = mgr.get_pending_interactions()
	_check("pending interaction exposed for the dialog/AI gate", pendings.size() == 1
		and pendings[0]["mission_id"] == "a_tempting_target", str(pendings))
	_check("responder is the human opponent P1", pendings.size() == 1 and int(pendings[0]["responder"]) == 1, str(pendings))
	_check("AIPlayer wait-gate reports a pending human interaction",
		ai._human_secondary_interaction_pending() == true)

	# Human resolves via the manager (the dialog path dispatches RESOLVE_TEMPTING_TARGET)
	var resolved_signal = [false]
	mgr.interaction_resolved.connect(func(_p, _m): resolved_signal[0] = true, CONNECT_ONE_SHOT)
	mgr.resolve_tempting_target(2, "obj_nml_2")
	_check("resolution stores the human's objective pick",
		str(att_mission.get("mission_data", {}).get("tempting_target_id", "")) == "obj_nml_2")
	_check("pending flag cleared", att_mission.get("pending_interaction", true) == false)
	_check("interaction_resolved signal fired (AI resumes)", resolved_signal[0])
	_check("AI wait-gate releases", ai._human_secondary_interaction_pending() == false)

	print("\n-- A Tempting Target: AI opponent picks (heuristic, not random) --")
	# Reverse roles: human P1 draws, AI P2 is the opponent chooser.
	gs.state["meta"]["game_config"]["player1_type"] = "HUMAN"
	gs.state["meta"]["game_config"]["player2_type"] = "AI"
	_mk_unit(gs, "U_P1_NEAR", 1, Vector2(_px(10), _px(26)))   # P1 sits near obj_nml_1
	_mk_unit(gs, "U_P2_NEAR", 2, Vector2(_px(34), _px(33)))   # P2 sits near obj_nml_2
	mission_mgr.objective_control_state["obj_nml_2"] = 2
	var pick = ai._pick_tempting_target_objective(1, 2)
	_check("AI chooser avoids the drawer's closest marker; prefers its own",
		pick == "obj_nml_2", pick)
	mission_mgr.objective_control_state.erase("obj_nml_2")

	print("\n-- Beacon: drawer designates; scoring tracks ONLY that unit --")
	mgr.initialize_for_game()
	mgr.setup_tactical_deck(1)
	gs.state["meta"]["active_player"] = 1
	var state1 = mgr._player_state["1"]
	state1["deck"] = ["beacon"]
	state1["active"] = []
	gs.state["units"] = {}
	_mk_unit(gs, "U_BEACON_FWD", 1, Vector2(_px(22), _px(40)))  # forward: outside P1 DZ + territory (P1 territory = top half)
	_mk_unit(gs, "U_HOME", 1, Vector2(_px(22), _px(5)))         # sitting in P1's DZ
	mgr.draw_missions_to_hand(1, 1)
	var bcn_mission = state1["active"][0] if state1["active"].size() > 0 else {}
	_check("beacon drawn pending designation", bcn_mission.get("pending_interaction", false) == true, str(bcn_mission))
	var eligible = mgr.get_beacon_eligible_units(1)
	_check("both friendly units eligible for designation", eligible.size() == 2, str(eligible))
	# Human designates the HOME unit (deliberately the bad pick)
	mgr.resolve_beacon_unit(1, "U_HOME")
	_check("designation stored", str(bcn_mission.get("mission_data", {}).get("beacon_unit_id", "")) == "U_HOME")
	_check("beacon flag set for the token badge",
		gs.state["units"]["U_HOME"].get("flags", {}).get("beacon", false) == true)
	# Scoring: home unit is inside own DZ -> no VP even though U_BEACON_FWD is forward
	var bcn_vp = mgr._evaluate_mission_conditions(1, bcn_mission)
	_check("designated-at-home beacon scores 0 (forward NON-beacon unit ignored)", bcn_vp == 0, str(bcn_vp))
	# Re-designate the forward unit: outside DZ AND outside own half -> 5 VP tier
	bcn_mission["mission_data"]["beacon_unit_id"] = "U_BEACON_FWD"
	bcn_vp = mgr._evaluate_mission_conditions(1, bcn_mission)
	_check("designated forward beacon scores the 5 VP tier", bcn_vp == 5, str(bcn_vp))
	# Dead beacon scores nothing
	for m in gs.state["units"]["U_BEACON_FWD"]["models"]:
		m["alive"] = false
	bcn_vp = mgr._evaluate_mission_conditions(1, bcn_mission)
	_check("destroyed beacon unit scores 0", bcn_vp == 0, str(bcn_vp))
	# AI auto-pick prefers a living forward unit
	for m in gs.state["units"]["U_BEACON_FWD"]["models"]:
		m["alive"] = true
	var ai_pick = ai._pick_beacon_unit(1)
	_check("AI beacon auto-pick prefers the forward unit", ai_pick == "U_BEACON_FWD", ai_pick)

	print("\n-- Burden of Trust: guards auto-assign + guarded scoring --")
	mgr.initialize_for_game()
	mgr.setup_tactical_deck(1)
	state1 = mgr._player_state["1"]
	state1["deck"] = ["burden_of_trust"]
	state1["active"] = []
	gs.state["units"] = {}
	_mk_unit(gs, "U_G1", 1, Vector2(_px(10), _px(30)))  # on obj_nml_1
	_mk_unit(gs, "U_G2", 1, Vector2(_px(34), _px(30)))  # on obj_nml_2
	mission_mgr.objective_control_state.clear()
	mission_mgr.objective_control_state["obj_nml_1"] = 1
	mission_mgr.objective_control_state["obj_nml_2"] = 1
	mgr.draw_missions_to_hand(1, 1)
	var bot_mission = state1["active"][0] if state1["active"].size() > 0 else {}
	_check("burden of trust drawn active (no blocking interaction)",
		bot_mission.get("id", "") == "burden_of_trust" and not bot_mission.get("pending_interaction", true), str(bot_mission))
	var guards = bot_mission.get("mission_data", {}).get("guards", {})
	_check("guards auto-assigned to both in-range objectives",
		guards.size() == 2 and guards.get("obj_nml_1", "") != "" and guards.get("obj_nml_2", "") != "", str(guards))
	_check("distinct units guard distinct objectives", guards.get("obj_nml_1", "") != guards.get("obj_nml_2", ""), str(guards))
	_check("revision window pending for the human prompt",
		bot_mission.get("mission_data", {}).get("guards_prompt_pending", false) == true)
	var pending_choice = mgr.get_pending_guard_choice(1)
	# Per the card, SELECTION is NOT range-limited: every objective is offered a
	# row and every friendly unit on the battlefield is eligible for each of them.
	# (Range only annotates which picks would score right now and gates scoring.)
	# Board here has 5 objectives, so all 5 are exposed even though only two have
	# a unit sitting on them.
	var pc_objectives = pending_choice.get("objectives", [])
	_check("pending guard choice exposes EVERY objective, not just in-range ones",
		pc_objectives.size() == 5, str(pc_objectives.size()))
	var nml1_ids := {}
	var g1_in_range_on_nml1 := false
	var g2_in_range_on_nml1 := false
	for o in pc_objectives:
		if str(o.get("objective_id", "")) == "obj_nml_1":
			for e in o.get("eligible", []):
				nml1_ids[str(e.get("unit_id", ""))] = true
				if str(e.get("unit_id", "")) == "U_G1":
					g1_in_range_on_nml1 = bool(e.get("in_range", false))
				if str(e.get("unit_id", "")) == "U_G2":
					g2_in_range_on_nml1 = bool(e.get("in_range", false))
	_check("every friendly unit is eligible for an objective regardless of range",
		nml1_ids.has("U_G1") and nml1_ids.has("U_G2"), str(nml1_ids.keys()))
	_check("in_range flag marks the unit on obj_nml_1 (U_G1) but not the far unit (U_G2)",
		g1_in_range_on_nml1 and not g2_in_range_on_nml1,
		"g1=%s g2=%s" % [str(g1_in_range_on_nml1), str(g2_in_range_on_nml1)])
	var count_guarded = mgr._count_guarded_objectives(1, {}, bot_mission)
	_check("both guarded objectives count while controlled + in range", count_guarded == 2, str(count_guarded))
	# Guard dies -> its objective is no longer guarded
	for m in gs.state["units"][guards["obj_nml_1"]]["models"]:
		m["alive"] = false
	count_guarded = mgr._count_guarded_objectives(1, {}, bot_mission)
	_check("dead guard drops its objective from the count", count_guarded == 1, str(count_guarded))
	# Losing control also drops it
	mission_mgr.objective_control_state["obj_nml_2"] = 2
	count_guarded = mgr._count_guarded_objectives(1, {}, bot_mission)
	_check("lost control drops the objective from the count", count_guarded == 0, str(count_guarded))
	# resolve_burden_guards rejects duplicate unit picks (keeps first)
	mission_mgr.objective_control_state["obj_nml_2"] = 1
	var res_guards = mgr.resolve_burden_guards(1, {"obj_nml_1": "U_G2", "obj_nml_2": "U_G2"})
	_check("duplicate guard collapsed to one objective", res_guards.get("guards", {}).size() == 1, str(res_guards))
	_check("guard prompt closed after resolution",
		bot_mission.get("mission_data", {}).get("guards_prompt_pending", true) == false)

	print("\n-- Final-round clause: active player scores opp-turn cards at game end --")
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["battle_round"] = 5
	mission_mgr.objective_control_state["obj_nml_2"] = 1
	for m in gs.state["units"]["U_G1"]["models"]:
		m["alive"] = true
	bot_mission["mission_data"]["guards"] = {"obj_nml_1": "U_G1", "obj_nml_2": "U_G2"}
	mission_mgr.objective_control_state["obj_nml_1"] = 1
	var normal_results = mgr.score_secondary_missions_for_player(1, false)
	var found_bot := false
	for r in normal_results:
		if r["mission_id"] == "burden_of_trust":
			found_bot = true
	_check("no opp-turn scoring on your own turn without the clause call", not found_bot, str(normal_results))
	var final_results = mgr.score_secondary_missions_for_player(1, true)
	found_bot = false
	var bot_vp := 0
	for r in final_results:
		if r["mission_id"] == "burden_of_trust":
			found_bot = true
			bot_vp = r["vp_earned"]
	_check("final-turn call scores Burden of Trust for the active player", found_bot, str(final_results))
	_check("2 guarded objectives = 4 VP", bot_vp == 4, str(bot_vp))

	print("\n-- Plunder: shooting-phase option + once per turn + scoring --")
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["battle_round"] = 2
	mgr.initialize_for_game()
	mgr.setup_tactical_deck(1)
	state1 = mgr._player_state["1"]
	state1["deck"] = []
	state1["active"] = [mgr._create_active_mission(SecondaryMissionData.get_mission_by_id("plunder"))]
	gs.state["units"] = {}
	# P1 territory = top half (DZ at top). Forward terrain sits in the BOTTOM half.
	_mk_unit(gs, "U_RAIDER", 1, Vector2(_px(22), _px(43)))
	_mk_unit(gs, "U_STAYHOME", 1, Vector2(_px(22), _px(5)))
	var terrain_mgr = root.get_node_or_null("TerrainManager")
	terrain_mgr.terrain_features = [
		{"id": "ruins_fwd", "type": "ruins", "polygon": PackedVector2Array([
			Vector2(_px(18), _px(40)), Vector2(_px(28), _px(40)), Vector2(_px(28), _px(46)), Vector2(_px(18), _px(46))])},
		{"id": "ruins_home", "type": "ruins", "polygon": PackedVector2Array([
			Vector2(_px(18), _px(2)), Vector2(_px(28), _px(2)), Vector2(_px(28), _px(8)), Vector2(_px(18), _px(8))])},
	]
	var shooting_phase = load("res://phases/ShootingPhase.gd").new()
	root.add_child(shooting_phase)
	shooting_phase.game_state_snapshot = gs.create_snapshot()
	var options_fwd = shooting_phase._get_secondary_action_options("U_RAIDER")
	_check("forward unit gets a Plunder option", options_fwd.size() == 1
		and options_fwd[0].get("action_name", "") == "Plunder"
		and options_fwd[0].get("vp_value", 0) == 5, str(options_fwd))
	var options_home = shooting_phase._get_secondary_action_options("U_STAYHOME")
	_check("unit in home-half terrain gets NO Plunder option (territory rule)",
		options_home.is_empty(), str(options_home))
	# Perform it
	var pl_result = shooting_phase.process_action({"type": "PERFORM_SECONDARY_ACTION",
		"actor_unit_id": "U_RAIDER", "payload": {"action_name": "Plunder", "location": "terrain", "mission_id": "plunder"}})
	_check("PERFORM_SECONDARY_ACTION Plunder succeeds", pl_result.get("success", false), str(pl_result))
	_check("plunder recorded with the terrain id",
		mgr._active_actions["1"].size() == 1 and str(mgr._active_actions["1"][0].get("terrain_id", "")) == "ruins_fwd",
		str(mgr._active_actions["1"]))
	# Once per turn: the second unit inside forward terrain gets no option now
	_mk_unit(gs, "U_RAIDER2", 1, Vector2(_px(24), _px(43)))
	var options_second = shooting_phase._get_secondary_action_options("U_RAIDER2")
	_check("once per turn: no second Plunder option", options_second.is_empty(), str(options_second))
	var validate_second = shooting_phase.validate_action({"type": "PERFORM_SECONDARY_ACTION",
		"actor_unit_id": "U_RAIDER2", "payload": {"action_name": "Plunder"}})
	_check("validator refuses a second Plunder this turn", not validate_second.get("valid", true), str(validate_second))
	# Scoring: flat 5 VP at end of your turn
	var pl_mission = state1["active"][0]
	var pl_vp = mgr._evaluate_mission_conditions(1, pl_mission)
	_check("completed Plunder scores 5 VP", pl_vp == 5, str(pl_vp))

	print("\n-- Cleanse (11e): non-home only, distinct objectives, control gate --")
	mgr.initialize_for_game()
	mgr.setup_tactical_deck(1)
	state1 = mgr._player_state["1"]
	state1["deck"] = []
	state1["active"] = [mgr._create_active_mission(SecondaryMissionData.get_mission_by_id("cleanse"))]
	gs.state["units"] = {}
	_mk_unit(gs, "U_CL_HOME", 1, Vector2(_px(22), _px(5)))    # on P1 home objective
	_mk_unit(gs, "U_CL_NML", 1, Vector2(_px(10), _px(30)))    # on obj_nml_1
	_mk_unit(gs, "U_CL_NML2", 1, Vector2(_px(10.5), _px(30.5)))  # ALSO near obj_nml_1
	shooting_phase.game_state_snapshot = gs.create_snapshot()
	var cl_home_opts = shooting_phase._get_secondary_action_options("U_CL_HOME")
	_check("home objective is NOT cleansable at 11e", cl_home_opts.is_empty(), str(cl_home_opts))
	var cl_opts = shooting_phase._get_secondary_action_options("U_CL_NML")
	_check("NML objective IS cleansable", cl_opts.size() == 1 and str(cl_opts[0].get("objective_id", "")) == "obj_nml_1", str(cl_opts))
	# Two units cleanse the SAME objective -> only 1 distinct objective counts
	mission_mgr.objective_control_state.clear()
	mission_mgr.objective_control_state["obj_nml_1"] = 1
	shooting_phase.process_action({"type": "PERFORM_SECONDARY_ACTION",
		"actor_unit_id": "U_CL_NML", "payload": {"action_name": "Cleanse", "location": "objective", "mission_id": "cleanse"}})
	# Force the second unit to record the same objective (bypass the fresh-objective steering)
	mgr.on_action_completed(1, {"action_name": "Cleanse", "completed": true, "unit_id": "U_CL_NML2", "objective_id": "obj_nml_1"})
	var cl_mission = state1["active"][0]
	var cl_vp = mgr._evaluate_mission_conditions(1, cl_mission)
	_check("duplicate-objective cleanses count once (2 VP tier)", cl_vp == 2, str(cl_vp))
	# Losing control of the objective voids the cleanse at end of turn (11e)
	mission_mgr.objective_control_state["obj_nml_1"] = 2
	cl_vp = mgr._evaluate_mission_conditions(1, cl_mission)
	_check("cleanse does not complete if the objective is lost", cl_vp == 0, str(cl_vp))

	shooting_phase.queue_free()

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
