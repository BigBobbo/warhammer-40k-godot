extends SceneTree

# 11e secondary mission deck — official launch data from the 40kdc dataset
# (@alpaca-software/40kdc-data 1.0.19, extracted under 40k/data/40kdc/).
#  - 18-card deck: four fixed-eligible cards + returning tacticals + the new
#    launch cards; retired 10e cards are absent.
#  - Official award semantics: vp_per counts (clamped to vp_max), cumulative
#    bonus rows, fixed/tactical mode splits, per-condition turn timing,
#    when-drawn replace/redraw deck operations.
#  - Tactical: draw 2/turn, no hand limit, card capped at 5 VP per scoring.
#  - Fixed: only Assassination / A Grievous Blow / Bring it Down /
#    Engage on All Fronts; 20 VP cap per card.
#  - Caps: 45 VP secondary total, 15 VP per turn (10e: 40 total).
#
# Usage: godot --headless --path . -s tests/test_secondary_deck_11e.gd

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

# Find a condition in a scoring block by check id (and optional extra key match).
func _find_cond(scoring: Dictionary, check: String, extra: Dictionary = {}) -> Dictionary:
	for c in scoring.get("conditions", []):
		if c.get("check", "") != check:
			continue
		var ok := true
		for k in extra:
			if c.get(k, null) != extra[k]:
				ok = false
				break
		if ok:
			return c
	return {}

# Build a dead enemy (P2) unit and report it destroyed to the manager.
func _kill_enemy_unit(gs, mgr, unit_id: String, wounds_per_model: Array, keywords: Array = []) -> void:
	var models = []
	for i in range(wounds_per_model.size()):
		models.append({"id": "m%d" % i, "alive": false, "wounds": wounds_per_model[i],
			"current_wounds": 0, "base_mm": 32, "base_type": "circular",
			"position": {"x": 500 + i * 30, "y": 500}})
	gs.state["units"][unit_id] = {"id": unit_id, "owner": 2,
		"status": 2,  # UnitStatus.DEPLOYED
		"meta": {"name": unit_id, "keywords": keywords, "points": 100, "stats": {}},
		"models": models}
	mgr.check_and_report_unit_destroyed(unit_id)

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_secondary_deck_11e ===\n")
	var mgr = root.get_node_or_null("SecondaryMissionManager")
	var gs = root.get_node_or_null("GameState")
	var mission_mgr = root.get_node_or_null("MissionManager")
	_check("autoloads present", mgr != null and gs != null and mission_mgr != null)

	print("-- deck composition --")
	var deck = SecondaryMissionData.get_mission_ids_for_deck_11e()
	_check("11e tactical deck has 18 cards", deck.size() == 18, str(deck))
	for nid in ["a_grievous_blow", "forward_position", "burden_of_trust", "centre_ground", "beacon", "outflank", "plunder"]:
		_check("new card %s present with data" % nid,
			nid in deck and not SecondaryMissionData.get_mission_by_id(nid).is_empty())
	for gone in ["area_denial", "extend_battle_lines", "storm_hostile_objective", "cull_the_horde", "marked_for_death", "establish_locus", "deploy_teleport_homer"]:
		_check("retired 10e card %s absent" % gone, not gone in deck)
	# Official data now specifies these cards fully — no longer approximate.
	for exact in ["forward_position", "centre_ground", "outflank", "plunder", "a_grievous_blow"]:
		_check("official card %s not flagged approximate" % exact,
			not SecondaryMissionData.get_mission_by_id(exact).get("approximate", false))
	# Beacon designation and Burden of Trust guard selection are now REAL
	# interactions (when-drawn unit pick / per-objective guard assignment).
	# Beacon keeps the approximate flag only for the territory-as-board-half
	# approximation; Burden of Trust is fully modelled.
	_check("beacon keeps approximate flag (territory approximation only)",
		SecondaryMissionData.get_mission_by_id("beacon").get("approximate", false))
	_check("burden_of_trust no longer approximate (real guard selection)",
		not SecondaryMissionData.get_mission_by_id("burden_of_trust").get("approximate", false))
	_check("beacon when-drawn requires drawer unit designation",
		SecondaryMissionData.get_when_drawn(SecondaryMissionData.get_mission_by_id("beacon")).get("condition", "") == "drawer_selects_unit")

	print("\n-- 10e deck leak fix --")
	var deck10 = SecondaryMissionData.get_mission_ids_for_deck(false)
	_check("10e deck has exactly 18 cards", deck10.size() == 18, str(deck10.size()))
	var leak := false
	for id in deck10:
		if int(SecondaryMissionData.get_mission_by_id(id).get("edition", 10)) >= 11:
			leak = true
	_check("no edition-11 cards leak into the 10e deck", not leak, str(deck10))

	print("\n-- official award data pins (11e) --")
	GameConstants.edition = 11
	# Behind Enemy Lines: 3 VP PER unit wholly in opponent DZ, max 5.
	var bel = SecondaryMissionData.get_scoring(SecondaryMissionData.get_mission_by_id("behind_enemy_lines"))
	var bel_c = _find_cond(bel, "units_wholly_in_opponent_deployment_zone")
	_check("behind_enemy_lines: 3 VP per unit, max 5",
		bel.get("conditions", []).size() == 1 and bel_c.get("per_count", false)
		and bel_c.get("vp", 0) == 3 and bel_c.get("vp_max", 0) == 5, str(bel))
	# No Prisoners: end of either turn, 2 VP per enemy unit destroyed, max 5.
	var np = SecondaryMissionData.get_scoring(SecondaryMissionData.get_mission_by_id("no_prisoners"))
	var np_c = _find_cond(np, "enemy_units_destroyed_this_turn")
	_check("no_prisoners: either turn, 2 VP per kill, max 5",
		np.get("when", "") == SecondaryMissionData.TIMING_END_OF_EITHER_TURN
		and np_c.get("per_count", false) and np_c.get("vp", 0) == 2 and np_c.get("vp_max", 0) == 5, str(np))
	# Overwhelming Force: 3 VP per enemy unit destroyed near an objective, max 5.
	var owf = SecondaryMissionData.get_scoring(SecondaryMissionData.get_mission_by_id("overwhelming_force"))
	var owf_c = _find_cond(owf, "enemy_units_destroyed_near_objective_this_turn")
	_check("overwhelming_force: 3 VP per kill near objective, max 5",
		owf_c.get("vp", 0) == 3 and owf_c.get("vp_max", 0) == 5
		and owf.get("when", "") == SecondaryMissionData.TIMING_END_OF_EITHER_TURN, str(owf))
	# Bring it Down: per-MODEL W10+ — fixed 4 uncapped, tactical 5 capped 5.
	var bid_data = SecondaryMissionData.get_mission_by_id("bring_it_down")
	var bid = SecondaryMissionData.get_scoring(bid_data)
	var bid_f = _find_cond(bid, "enemy_models_wounds_10_plus_destroyed_this_turn", {"mode": "fixed"})
	var bid_t = _find_cond(bid, "enemy_models_wounds_10_plus_destroyed_this_turn", {"mode": "tactical"})
	_check("bring_it_down fixed: 4 VP per W10+ model, uncapped",
		bid_f.get("vp", 0) == 4 and not bid_f.has("vp_max"), str(bid_f))
	_check("bring_it_down tactical: 5 VP per W10+ model, max 5",
		bid_t.get("vp", 0) == 5 and bid_t.get("vp_max", 0) == 5, str(bid_t))
	_check("bring_it_down 11e when-drawn: replace if no 10+W enemy",
		SecondaryMissionData.get_when_drawn(bid_data).get("condition", "") == "no_enemy_model_wounds_10_plus")
	# Assassination: fixed 3/model + cumulative 1/W4+ model; tactical flat 5.
	var asn = SecondaryMissionData.get_scoring(SecondaryMissionData.get_mission_by_id("assassination"))
	var asn_base = _find_cond(asn, "enemy_character_models_destroyed_this_turn", {"mode": "fixed"})
	var asn_bonus = _find_cond(asn, "enemy_character_models_destroyed_this_turn", {"cumulative": true})
	var asn_tac = _find_cond(asn, "character_models_destroyed_this_turn", {"mode": "tactical"})
	_check("assassination fixed: 3 VP per CHARACTER model", asn_base.get("vp", 0) == 3 and asn_base.get("per_count", false), str(asn_base))
	_check("assassination fixed bonus: cumulative 1 VP per W4+ CHARACTER",
		asn_bonus.get("vp", 0) == 1 and asn_bonus.get("params", {}).get("min_wounds", 0) == 4, str(asn_bonus))
	_check("assassination tactical: flat 5 VP", asn_tac.get("vp", 0) == 5, str(asn_tac))
	# A Grievous Blow: 13+ model units — fixed 4 uncapped, tactical 5 max 5.
	var agb_data = SecondaryMissionData.get_mission_by_id("a_grievous_blow")
	var agb = SecondaryMissionData.get_scoring(agb_data)
	var agb_f = _find_cond(agb, "enemy_units_13_plus_destroyed_this_turn", {"mode": "fixed"})
	var agb_t = _find_cond(agb, "enemy_units_13_plus_destroyed_this_turn", {"mode": "tactical"})
	_check("a_grievous_blow fixed 4 / tactical 5 (max 5)",
		agb_f.get("vp", 0) == 4 and not agb_f.has("vp_max")
		and agb_t.get("vp", 0) == 5 and agb_t.get("vp_max", 0) == 5, str(agb))
	_check("a_grievous_blow when-drawn: replace if no 13+ model enemy unit",
		SecondaryMissionData.get_when_drawn(agb_data).get("condition", "") == "no_enemy_unit_13_plus_models")
	# Engage on All Fronts: fixed 2/4, tactical 3/5 (3 and 4 quarters).
	var eng = SecondaryMissionData.get_scoring(SecondaryMissionData.get_mission_by_id("engage_on_all_fronts"))
	var eng_f3 = _find_cond(eng, "presence_in_table_quarters", {"mode": "fixed", "vp": 2})
	var eng_f4 = _find_cond(eng, "presence_in_table_quarters", {"mode": "fixed", "vp": 4})
	var eng_t3 = _find_cond(eng, "presence_in_table_quarters", {"mode": "tactical", "vp": 3})
	var eng_t4 = _find_cond(eng, "presence_in_table_quarters", {"mode": "tactical", "vp": 5})
	_check("engage_on_all_fronts: fixed 2(3q)/4(4q), tactical 3(3q)/5(4q)",
		eng_f3.get("params", {}).get("count", 0) == 3 and eng_f4.get("params", {}).get("count", 0) == 4
		and eng_t3.get("params", {}).get("count", 0) == 3 and eng_t4.get("params", {}).get("count", 0) == 4, str(eng))
	# Display of Might: 2 VP end of your turn / 5 VP end of opponent turn.
	var dom = SecondaryMissionData.get_scoring(SecondaryMissionData.get_mission_by_id("display_of_might"))
	var dom_y = _find_cond(dom, "more_units_wholly_in_no_mans_land_than_opponent", {"timing": "your_turn"})
	var dom_o = _find_cond(dom, "more_units_wholly_in_no_mans_land_than_opponent", {"timing": "opponent_turn"})
	_check("display_of_might: 2 VP your turn / 5 VP opponent turn",
		dom_y.get("vp", 0) == 2 and dom_o.get("vp", 0) == 5
		and dom.get("when", "") == SecondaryMissionData.TIMING_END_OF_EITHER_TURN, str(dom))
	# Burden of Trust: 2 VP per guarded objective, max 5, end of opponent turn.
	var bot = SecondaryMissionData.get_scoring(SecondaryMissionData.get_mission_by_id("burden_of_trust"))
	var bot_c = _find_cond(bot, "guarded_objectives")
	_check("burden_of_trust: end of opponent turn, 2 VP per objective, max 5",
		bot.get("when", "") == SecondaryMissionData.TIMING_END_OF_OPPONENT_TURN
		and bot_c.get("vp", 0) == 2 and bot_c.get("vp_max", 0) == 5, str(bot))
	# Defend Stronghold: opponent turn round 2+, 3 VP home + cumulative 2 VP.
	var ds_data = SecondaryMissionData.get_mission_by_id("defend_stronghold")
	var ds = SecondaryMissionData.get_scoring(ds_data)
	var ds_home = _find_cond(ds, "control_objectives_in_own_deployment_zone")
	var ds_bonus = _find_cond(ds, "no_enemy_units_wholly_in_own_deployment_zone")
	_check("defend_stronghold: opp turn r2+, 3 VP home + cumulative 2 VP",
		ds.get("when", "") == SecondaryMissionData.TIMING_END_OF_OPPONENT_TURN
		and ds.get("min_round", 0) == 2 and ds_home.get("vp", 0) == 3
		and ds_bonus.get("vp", 0) == 2 and ds_bonus.get("cumulative", false), str(ds))
	_check("defend_stronghold 11e when-drawn: redraw round 1",
		SecondaryMissionData.get_when_drawn(ds_data).get("condition", "") == "first_battle_round")
	# Forward Position: flat 5 VP (opponent home OR an expansion); redraw round 1.
	var fp_data = SecondaryMissionData.get_mission_by_id("forward_position")
	var fp = SecondaryMissionData.get_scoring(fp_data)
	_check("forward_position: flat 5 VP, redraw round 1",
		_find_cond(fp, "holds_enemy_home_objective").get("vp", 0) == 5
		and SecondaryMissionData.get_when_drawn(fp_data).get("condition", "") == "first_battle_round"
		and SecondaryMissionData.get_when_drawn(fp_data).get("effect", "") == SecondaryMissionData.EFFECT_MANDATORY_SHUFFLE_BACK, str(fp))
	# Centre Ground: friendly within 3" — 3 VP (no enemy 3") / 5 VP (no enemy 6").
	var cg = SecondaryMissionData.get_scoring(SecondaryMissionData.get_mission_by_id("centre_ground"))
	var cg3 = _find_cond(cg, "units_within_center_no_enemies_within", {"vp": 3})
	var cg5 = _find_cond(cg, "units_within_center_no_enemies_within", {"vp": 5})
	_check("centre_ground: 3\" friendly; tiers no-enemy-3\"=3VP / no-enemy-6\"=5VP",
		cg3.get("params", {}).get("friendly_range", 0) == 3.0 and cg3.get("params", {}).get("enemy_range", 0) == 3.0
		and cg5.get("params", {}).get("friendly_range", 0) == 3.0 and cg5.get("params", {}).get("enemy_range", 0) == 6.0, str(cg))
	# Outflank: 3 VP edge unit outside territory / 5 VP opposite edges.
	var ofl = SecondaryMissionData.get_scoring(SecondaryMissionData.get_mission_by_id("outflank"))
	var ofl3 = _find_cond(ofl, "units_near_board_edges", {"vp": 3})
	var ofl5 = _find_cond(ofl, "units_near_board_edges", {"vp": 5})
	_check("outflank: 3 VP (edge, outside territory) / 5 VP (opposite edges)",
		ofl3.get("params", {}).get("outside_own_territory", false)
		and ofl5.get("params", {}).get("opposite_edges", false), str(ofl))
	# Beacon: end of opponent turn — 3 VP outside DZ / 5 VP outside territory.
	var bcn = SecondaryMissionData.get_scoring(SecondaryMissionData.get_mission_by_id("beacon"))
	_check("beacon: opp turn, 3 VP outside DZ / 5 VP outside territory",
		bcn.get("when", "") == SecondaryMissionData.TIMING_END_OF_OPPONENT_TURN
		and _find_cond(bcn, "unit_outside_own_dz").get("vp", 0) == 3
		and _find_cond(bcn, "unit_outside_own_territory").get("vp", 0) == 5, str(bcn))
	# Plunder: flat 5 VP for the Plunder action; mutual redraw with Cleanse.
	var pl_data = SecondaryMissionData.get_mission_by_id("plunder")
	var pl = SecondaryMissionData.get_scoring(pl_data)
	_check("plunder: flat 5 VP on Plunder action completed",
		_find_cond(pl, "action_completed_this_turn").get("vp", 0) == 5, str(pl))
	_check("plunder <-> cleanse mutual redraw wired",
		SecondaryMissionData.get_when_drawn(pl_data).get("details", {}).get("mission_id", "") == "cleanse"
		and SecondaryMissionData.get_when_drawn(SecondaryMissionData.get_mission_by_id("cleanse")).get("details", {}).get("mission_id", "") == "plunder")
	# Secure No Man's Land: flat 5 VP for 2+ NML objectives.
	var snml = SecondaryMissionData.get_scoring(SecondaryMissionData.get_mission_by_id("secure_no_mans_land"))
	_check("secure_no_mans_land: single 5 VP tier at 2+ NML objectives",
		snml.get("conditions", []).size() == 1
		and _find_cond(snml, "control_objectives_in_no_mans_land").get("vp", 0) == 5
		and _find_cond(snml, "control_objectives_in_no_mans_land").get("params", {}).get("count", 0) == 2, str(snml))
	# A Tempting Target: scored end of YOUR turn at 11e.
	var att = SecondaryMissionData.get_scoring(SecondaryMissionData.get_mission_by_id("a_tempting_target"))
	_check("a_tempting_target: end of YOUR turn at 11e",
		att.get("when", "") == SecondaryMissionData.TIMING_END_OF_YOUR_TURN, str(att))

	print("\n-- instructions text (11e) --")
	var missing_instructions = []
	for id in deck:
		if SecondaryMissionData.get_mission_instructions(id) == "":
			missing_instructions.append(id)
	_check("all 18 deck cards have 11e instruction text", missing_instructions.is_empty(), str(missing_instructions))

	print("\n-- draw rules: 2/turn, no hand limit (11e) --")
	GameConstants.edition = 11
	mgr.initialize_for_game()
	mgr.setup_tactical_deck(1)
	var st = mgr._player_state["1"]
	_check("deck built with 18 cards at e11", st["deck"].size() == 18, str(st["deck"].size()))
	mgr.draw_missions_to_hand(1)
	_check("first draw: 2 cards in hand", st["active"].size() == 2, str(st["active"].size()))
	mgr.draw_missions_to_hand(1)
	_check("second draw: hand grows to 4 (no hand limit)", st["active"].size() == 4, str(st["active"].size()))
	GameConstants.edition = 10
	mgr.initialize_for_game()
	mgr.setup_tactical_deck(1)
	var st10 = mgr._player_state["1"]
	mgr.draw_missions_to_hand(1)
	mgr.draw_missions_to_hand(1)
	_check("10e unchanged: hand capped at 2", st10["active"].size() == 2, str(st10["active"].size()))

	print("\n-- fixed eligibility (11e) --")
	GameConstants.edition = 11
	mgr.initialize_for_game()
	var bad = mgr.setup_fixed_missions(1, ["no_prisoners", "assassination"])
	_check("11e fixed: non-eligible card rejected", not bad.get("success", true), str(bad))
	var good = mgr.setup_fixed_missions(1, ["assassination", "a_grievous_blow"])
	_check("11e fixed: two fixed-eligible cards accepted", good.get("success", false), str(good))

	print("\n-- caps: 15/turn and 45 total (11e) --")
	mgr.initialize_for_game()
	mgr.setup_tactical_deck(1)
	var award1 = mgr._award_secondary_vp(1, 14, "test_a")
	var award2 = mgr._award_secondary_vp(1, 5, "test_b")
	_check("14 VP awarded freely", award1 == 14, str(award1))
	_check("next 5 VP clipped to 1 by the 15/turn cap", award2 == 1, str(award2))
	mgr.on_turn_start(1)
	var s1 = mgr._player_state["1"]
	_check("turn window resets on turn start", int(s1.get("secondary_vp_this_turn", -1)) == 0)
	# Pump to the 45 total cap in 15-per-turn windows.
	for _t in range(2):
		mgr._award_secondary_vp(1, 15, "test_c")
		mgr.on_turn_start(1)
	# Windows so far: 15 (turn 1) + 15 + 15 = 45 — the total cap is reached.
	var final_award = mgr._award_secondary_vp(1, 15, "test_d")
	_check("45 total cap: nothing awarded beyond it", final_award == 0, str(final_award))
	mgr.on_turn_start(1)
	var over_cap = mgr._award_secondary_vp(1, 5, "test_e")
	_check("fresh turn window does not bypass the total cap", over_cap == 0, str(over_cap))
	_check("secondary_vp settled at exactly 45", int(s1["secondary_vp"]) == 45, str(s1["secondary_vp"]))

	print("\n-- official kill scoring (fixed vs tactical) --")
	GameConstants.edition = 11
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["battle_round"] = 2
	mgr.initialize_for_game()
	mgr.setup_tactical_deck(1)
	mgr._units_destroyed_this_turn.clear()
	# Enemy losses this turn: a 2-model W12 unit, two CHARACTERs (W5, W3),
	# and two 13-model hordes.
	_kill_enemy_unit(gs, mgr, "U_TITAN", [12, 12], ["VEHICLE", "TITANIC"])
	_kill_enemy_unit(gs, mgr, "U_CHAR_A", [5], ["CHARACTER"])
	_kill_enemy_unit(gs, mgr, "U_CHAR_B", [3], ["CHARACTER"])
	var horde_wounds := []
	for _i in range(13):
		horde_wounds.append(1)
	_kill_enemy_unit(gs, mgr, "U_HORDE_A", horde_wounds, ["INFANTRY"])
	_kill_enemy_unit(gs, mgr, "U_HORDE_B", horde_wounds, ["INFANTRY"])

	var m_bid = mgr._create_active_mission(SecondaryMissionData.get_mission_by_id("bring_it_down"))
	var m_asn = mgr._create_active_mission(SecondaryMissionData.get_mission_by_id("assassination"))
	var m_agb = mgr._create_active_mission(SecondaryMissionData.get_mission_by_id("a_grievous_blow"))
	var m_np = mgr._create_active_mission(SecondaryMissionData.get_mission_by_id("no_prisoners"))

	# Tactical mode (setup_tactical_deck above set mode = "tactical")
	_check("tactical bring_it_down: 2x W12 models -> 10 clamped to 5",
		mgr._evaluate_mission_conditions(1, m_bid) == 5, str(mgr._evaluate_mission_conditions(1, m_bid)))
	_check("tactical assassination: flat 5 when 1+ CHARACTER died",
		mgr._evaluate_mission_conditions(1, m_asn) == 5)
	_check("tactical a_grievous_blow: 2 hordes -> 10 clamped to 5",
		mgr._evaluate_mission_conditions(1, m_agb) == 5)
	_check("tactical no_prisoners: 5 kills -> 10 clamped to vp_max 5",
		mgr._evaluate_mission_conditions(1, m_np) == 5)

	# Fixed mode: per-model/per-unit values, uncapped where official says so.
	mgr._player_state["1"]["mode"] = "fixed"
	_check("fixed bring_it_down: 4 VP x 2 W12 models = 8 (uncapped)",
		mgr._evaluate_mission_conditions(1, m_bid) == 8, str(mgr._evaluate_mission_conditions(1, m_bid)))
	_check("fixed assassination: 3x2 CHARACTERs + 1 (W4+) = 7",
		mgr._evaluate_mission_conditions(1, m_asn) == 7, str(mgr._evaluate_mission_conditions(1, m_asn)))
	_check("fixed a_grievous_blow: 4 VP x 2 hordes = 8 (uncapped)",
		mgr._evaluate_mission_conditions(1, m_agb) == 8)
	mgr._player_state["1"]["mode"] = "tactical"

	# Counter helpers directly
	_check("count W10+ models destroyed == 2", mgr._count_enemy_models_destroyed_with_wounds(1, 10) == 2)
	_check("count CHARACTER models destroyed == 2", mgr._count_enemy_character_models_destroyed(1, {}) == 2)
	_check("count CHARACTER W4+ models destroyed == 1", mgr._count_enemy_character_models_destroyed(1, {"min_wounds": 4}) == 1)
	_check("count 13+ strong units destroyed == 2", mgr._count_enemy_units_destroyed(1, {"min_models": 13}) == 2)
	_check("own losses never counted", mgr._count_enemy_units_destroyed(2, {}) == 0)

	print("\n-- per-condition timing + cumulative + tactical cap --")
	# Timing gate (Display of Might pattern): 2 VP your turn / 5 VP opponent's.
	var fake_timed = {"id": "fake_timed", "name": "FakeTimed", "scoring": {
		"when": SecondaryMissionData.TIMING_END_OF_EITHER_TURN,
		"conditions": [
			{"check": "enemy_unit_destroyed", "params": {}, "vp": 2, "timing": "your_turn"},
			{"check": "enemy_unit_destroyed", "params": {}, "vp": 5, "timing": "opponent_turn"},
		]}}
	gs.state["meta"]["active_player"] = 1
	_check("timing gate: your-turn row scores on your turn (2 VP)",
		mgr._evaluate_mission_conditions(1, fake_timed) == 2)
	gs.state["meta"]["active_player"] = 2
	_check("timing gate: opponent-turn row scores on their turn (5 VP)",
		mgr._evaluate_mission_conditions(1, fake_timed) == 5)
	gs.state["meta"]["active_player"] = 1
	# Cumulative row adds on top of the exclusive winner.
	var fake_cum = {"id": "fake_cum", "name": "FakeCum", "scoring": {
		"when": SecondaryMissionData.TIMING_END_OF_EITHER_TURN,
		"conditions": [
			{"check": "enemy_unit_destroyed", "params": {}, "vp": 3},
			{"check": "enemy_unit_destroyed", "params": {}, "vp": 2, "cumulative": true},
		]}}
	_check("cumulative row sums with base (3+2=5)", mgr._evaluate_mission_conditions(1, fake_cum) == 5)
	# 11e tactical per-scoring cap (5) applies to uncapped totals.
	var fake_big = {"id": "fake_big", "name": "FakeBig", "scoring": {
		"when": SecondaryMissionData.TIMING_END_OF_EITHER_TURN,
		"conditions": [
			{"check": "enemy_units_destroyed_this_turn", "per_count": true, "params": {}, "vp": 3},
		]}}
	_check("11e tactical per-scoring cap clips 15 -> 5", mgr._evaluate_mission_conditions(1, fake_big) == 5)
	mgr._player_state["1"]["mode"] = "fixed"
	_check("fixed mode is not clipped by the tactical cap", mgr._evaluate_mission_conditions(1, fake_big) == 15)
	mgr._player_state["1"]["mode"] = "tactical"

	print("\n-- objective-based official scoring --")
	# Inject a small objective layout + control state.
	var saved_objectives = gs.state["board"].get("objectives", [])
	var saved_control = mission_mgr.objective_control_state
	gs.state["board"]["objectives"] = [
		{"id": "obj_home_p1", "zone": "player1", "position": {"x": 200, "y": 200}},
		{"id": "obj_home_p2", "zone": "player2", "position": {"x": 2000, "y": 2000}},
		{"id": "obj_nml_1", "zone": "no_mans_land", "position": {"x": 900, "y": 900}},
		{"id": "obj_nml_2", "zone": "no_mans_land", "position": {"x": 1200, "y": 900}},
	]
	mission_mgr.objective_control_state = {"obj_home_p1": 1, "obj_nml_1": 1, "obj_nml_2": 1, "obj_home_p2": 2}
	var m_snml = mgr._create_active_mission(SecondaryMissionData.get_mission_by_id("secure_no_mans_land"))
	_check("secure_no_mans_land: 2 NML objectives -> 5 VP", mgr._evaluate_mission_conditions(1, m_snml) == 5)
	var m_bot = mgr._create_active_mission(SecondaryMissionData.get_mission_by_id("burden_of_trust"))
	_check("burden_of_trust: 3 guarded objectives -> 6 clamped to 5",
		mgr._evaluate_mission_conditions(1, m_bot) == 5, str(mgr._count_guarded_objectives(1, {})))
	mission_mgr.objective_control_state = {"obj_home_p1": 1, "obj_nml_1": 1}
	_check("burden_of_trust: 2 guarded objectives -> 4 VP", mgr._evaluate_mission_conditions(1, m_bot) == 4)
	# Defend Stronghold: hold home + no enemies wholly in DZ (all enemy units
	# in state are destroyed, so the bonus row passes) = 3 + 2.
	var m_ds = mgr._create_active_mission(SecondaryMissionData.get_mission_by_id("defend_stronghold"))
	_check("defend_stronghold: home held + clear DZ -> 3+2=5", mgr._evaluate_mission_conditions(1, m_ds) == 5,
		str(mgr._evaluate_mission_conditions(1, m_ds)))
	# Forward Position: control opponent home objective -> 5.
	var m_fp = mgr._create_active_mission(SecondaryMissionData.get_mission_by_id("forward_position"))
	mission_mgr.objective_control_state = {"obj_home_p2": 1}
	_check("forward_position: opponent home held -> 5 VP", mgr._evaluate_mission_conditions(1, m_fp) == 5)
	mission_mgr.objective_control_state = saved_control
	gs.state["board"]["objectives"] = saved_objectives

	print("\n-- when-drawn deck operations (11e) --")
	gs.state["meta"]["battle_round"] = 2
	mgr.initialize_for_game()
	mgr.setup_tactical_deck(1)
	# Board currently has only DESTROYED enemy units -> both replace-cards go.
	var bid_wd = mgr._handle_when_drawn(1, SecondaryMissionData.get_mission_by_id("bring_it_down"))
	_check("bring_it_down replaced when opponent lacks 10+W models",
		bid_wd.get("action", "") == "discard_and_draw", str(bid_wd))
	var agb_wd = mgr._handle_when_drawn(1, SecondaryMissionData.get_mission_by_id("a_grievous_blow"))
	_check("a_grievous_blow replaced when opponent lacks 13+ model units",
		agb_wd.get("action", "") == "discard_and_draw", str(agb_wd))
	# Give the opponent a live 10+W model and a live 13-model unit.
	gs.state["units"]["U_LIVE_TANK"] = {"id": "U_LIVE_TANK", "owner": 2, "status": 2,
		"meta": {"name": "LiveTank", "keywords": ["VEHICLE"], "points": 150, "stats": {}},
		"models": [{"id": "m1", "alive": true, "wounds": 11, "current_wounds": 11,
			"base_mm": 100, "base_type": "circular", "position": {"x": 600, "y": 600}}]}
	var live_horde_models = []
	for i in range(13):
		live_horde_models.append({"id": "m%d" % i, "alive": true, "wounds": 1, "current_wounds": 1,
			"base_mm": 25, "base_type": "circular", "position": {"x": 700 + i * 26, "y": 700}})
	gs.state["units"]["U_LIVE_HORDE"] = {"id": "U_LIVE_HORDE", "owner": 2, "status": 2,
		"meta": {"name": "LiveHorde", "keywords": ["INFANTRY"], "points": 120, "stats": {}},
		"models": live_horde_models}
	bid_wd = mgr._handle_when_drawn(1, SecondaryMissionData.get_mission_by_id("bring_it_down"))
	_check("bring_it_down kept when a 10+W enemy model exists",
		bid_wd.get("action", "") == "add_to_active", str(bid_wd))
	agb_wd = mgr._handle_when_drawn(1, SecondaryMissionData.get_mission_by_id("a_grievous_blow"))
	_check("a_grievous_blow kept when a 13+ model enemy unit exists",
		agb_wd.get("action", "") == "add_to_active", str(agb_wd))
	# Plunder/Cleanse mutual redraw.
	var pl_wd = mgr._handle_when_drawn(1, SecondaryMissionData.get_mission_by_id("plunder"))
	_check("plunder kept when cleanse is not active", pl_wd.get("action", "") == "add_to_active", str(pl_wd))
	mgr._player_state["1"]["active"].append(mgr._create_active_mission(SecondaryMissionData.get_mission_by_id("cleanse")))
	pl_wd = mgr._handle_when_drawn(1, SecondaryMissionData.get_mission_by_id("plunder"))
	_check("plunder shuffled back while cleanse is active", pl_wd.get("action", "") == "shuffle_back", str(pl_wd))
	var cl_wd = mgr._handle_when_drawn(1, SecondaryMissionData.get_mission_by_id("cleanse"))
	_check("cleanse kept when plunder is not active", cl_wd.get("action", "") == "add_to_active", str(cl_wd))
	mgr._player_state["1"]["active"].append(mgr._create_active_mission(SecondaryMissionData.get_mission_by_id("plunder")))
	cl_wd = mgr._handle_when_drawn(1, SecondaryMissionData.get_mission_by_id("cleanse"))
	_check("cleanse shuffled back while plunder is active", cl_wd.get("action", "") == "shuffle_back", str(cl_wd))
	# Round-1 redraw cards.
	gs.state["meta"]["battle_round"] = 1
	for redraw_id in ["behind_enemy_lines", "forward_position", "defend_stronghold"]:
		var wd = mgr._handle_when_drawn(1, SecondaryMissionData.get_mission_by_id(redraw_id))
		_check("%s shuffled back in round 1" % redraw_id, wd.get("action", "") == "shuffle_back", str(wd))
	gs.state["meta"]["battle_round"] = 2

	print("\n-- fixed mission dialog filtering --")
	# load() at runtime (not a compile-time class reference): the -s harness
	# parses this test before autoloads register, and the dialog's dependency
	# chain (WhiteDwarfTheme -> FactionPalettes) needs autoload globals.
	var dlg_script = load("res://dialogs/FixedMissionSelectionDialog.gd")
	var dlg = dlg_script.new()
	dlg.setup(1)
	var offered_11e = dlg._mission_checkboxes.keys()
	offered_11e.sort()
	var expected_11e = SecondaryMissionData.get_fixed_eligible_11e().duplicate()
	expected_11e.sort()
	_check("11e fixed dialog offers exactly the 4 fixed-eligible cards",
		offered_11e == expected_11e, str(offered_11e))
	dlg.free()
	GameConstants.edition = 10
	var dlg10 = dlg_script.new()
	dlg10.setup(1)
	_check("10e fixed dialog offers the 18 10e cards only",
		dlg10._mission_checkboxes.size() == 18, str(dlg10._mission_checkboxes.size()))
	var dlg10_leak := false
	for mid in dlg10._mission_checkboxes:
		if int(SecondaryMissionData.get_mission_by_id(mid).get("edition", 10)) >= 11:
			dlg10_leak = true
	_check("10e fixed dialog has no 11e-only cards", not dlg10_leak)
	dlg10.free()

	print("\n-- legacy checker retained --")
	GameConstants.edition = 11
	gs.state["units"]["U_HV"] = {"id": "U_HV", "owner": 2,
		"meta": {"name": "BigThing", "keywords": ["VEHICLE"], "points": 180, "stats": {}},
		"models": [{"id": "m1", "alive": false, "wounds": 12, "current_wounds": 0,
			"base_mm": 100, "base_type": "circular", "position": {"x": 500, "y": 500}}]}
	mgr._units_destroyed_this_turn.clear()
	mgr.check_and_report_unit_destroyed("U_HV")
	_check("high-value kill detected (180 pts / 12W model)",
		mgr._check_high_value_unit_destroyed(1, {"min_points": 100, "min_wounds": 10}))
	_check("high-value threshold respected",
		not mgr._check_high_value_unit_destroyed(1, {"min_points": 500, "min_wounds": 20}))
	_check("destroyed record carries per-model wounds",
		mgr._units_destroyed_this_turn[0].get("model_wounds", []) == [12])
	gs.state.units.erase("U_HV")
	for uid in ["U_TITAN", "U_CHAR_A", "U_CHAR_B", "U_HORDE_A", "U_HORDE_B", "U_LIVE_TANK", "U_LIVE_HORDE"]:
		gs.state.units.erase(uid)
	mgr._units_destroyed_this_turn.clear()
	mgr.initialize_for_game()

	GameConstants.edition = 10
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
