extends SceneTree

# 11e (GDM 2026) Force Disposition primary missions — source:
# docs/rules/11th_edition_missions_gdm2026.md.
#  - 5 dispositions; each player's card = own deck paired vs opponent's
#    disposition (25-card table, PrimaryMissionData11e).
#  - Command conditions score at end of your Command phase R1-4, switching
#    to end of turn in R5; EOT every turn; EOG once at game end.
#  - Caps: 45 primary total, 15 per turn.
#
# Usage: godot --headless --path . -s tests/test_primary_missions_11e.gd

var passed := 0
var failed := 0
var gs = null
var mgr = null

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

func _find_obj_by_zone(zone: String) -> String:
	for obj in gs.state.board.get("objectives", []):
		if obj.get("zone", "") == zone:
			return obj.get("id", "")
	return ""

func _reset_vp(_m) -> void:
	for pk in ["1", "2"]:
		gs.state.players[pk]["vp"] = 0
		gs.state.players[pk]["primary_vp"] = 0
	mgr._primary_vp_this_turn = {"1": 0, "2": 0}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_primary_missions_11e ===\n")
	mgr = root.get_node_or_null("MissionManager")
	gs = root.get_node_or_null("GameState")
	_check("autoloads present", mgr != null and gs != null)

	print("-- pairing table --")
	var cards = PrimaryMissionData11e.get_all_cards()
	_check("25 primary mission cards", cards.size() == 25, str(cards.size()))
	var ids = {}
	var complete = true
	for own in PrimaryMissionData11e.DISPOSITIONS:
		for opp in PrimaryMissionData11e.DISPOSITIONS:
			var card = PrimaryMissionData11e.get_card(own, opp)
			if card.is_empty():
				complete = false
			else:
				ids[card["id"]] = true
	_check("all 25 disposition pairings resolve", complete)
	_check("all card ids unique", ids.size() == 25, str(ids.size()))
	_check("TH vs TH is Battlefield Dominance",
		PrimaryMissionData11e.get_card("take_and_hold", "take_and_hold").get("id", "") == "battlefield_dominance")
	_check("DI vs PF is Delaying Action",
		PrimaryMissionData11e.get_card("disruption", "purge_the_foe").get("id", "") == "delaying_action")
	_check("approximate rows are flagged",
		PrimaryMissionData11e.get_card_by_id("smoke_and_mirrors").get("approximate", false)
		and PrimaryMissionData11e.get_card_by_id("gather_intel").get("approximate", false))

	print("\n-- disposition initialization --")
	GameConstants.edition = 11
	mgr.initialize_dispositions_11e("take_and_hold", "disruption")
	_check("P1 (TH vs DI) plays Determined Acquisition",
		mgr.get_primary_mission_for_player(1).get("id", "") == "determined_acquisition")
	_check("P2 (DI vs TH) plays Death Trap",
		mgr.get_primary_mission_for_player(2).get("id", "") == "death_trap")
	_check("dispositions stored in meta",
		gs.state.meta.get("dispositions_11e", {}).get("1", "") == "take_and_hold")
	mgr.initialize_dispositions_11e("bogus", "priority_assets")
	_check("unknown disposition falls back to take_and_hold",
		mgr.get_primary_mission_for_player(1).get("id", "") == "inescapable_dominion")

	print("\n-- command scoring: Battlefield Dominance --")
	mgr.initialize_dispositions_11e("take_and_hold", "take_and_hold")
	var home1 = _find_obj_by_zone("player1")
	var home2 = _find_obj_by_zone("player2")
	var nml = _find_obj_by_zone("no_mans_land")
	_check("board has home + NML objectives", home1 != "" and home2 != "" and nml != "")
	gs.state.meta["battle_round"] = 2
	gs.state.meta["active_player"] = 1
	_reset_vp(null)
	for obj_id in mgr.objective_control_state:
		mgr.objective_control_state[obj_id] = 0
	mgr.objective_control_state[home1] = 1
	mgr.objective_control_state[nml] = 1
	mgr.score_primary_objectives()
	# R2: hold_more (2VP, P1 holds 2 vs 0) + per_objective 3VP x2 = 8
	_check("R2 command: 2 (hold more) + 3x2 objectives = 8 VP",
		int(gs.state.players["1"]["primary_vp"]) == 8, str(gs.state.players["1"]["primary_vp"]))

	print("\n-- caps: 15/turn and 45 total --")
	_reset_vp(null)
	mgr._award_primary_vp_11e(1, 12, "test", "command")
	mgr._award_primary_vp_11e(1, 9, "test", "command")
	_check("second award clipped to the 15/turn window",
		int(gs.state.players["1"]["primary_vp"]) == 15, str(gs.state.players["1"]["primary_vp"]))
	mgr.on_turn_start_11e(1)
	_check("turn window resets on turn start", int(mgr._primary_vp_this_turn["1"]) == 0)
	gs.state.players["1"]["primary_vp"] = 44
	mgr._award_primary_vp_11e(1, 10, "test", "command")
	_check("45 total cap respected", int(gs.state.players["1"]["primary_vp"]) == 45,
		str(gs.state.players["1"]["primary_vp"]))

	print("\n-- Round 5: command scoring switches to end of turn --")
	mgr.initialize_dispositions_11e("take_and_hold", "take_and_hold")
	gs.state.meta["battle_round"] = 5
	_reset_vp(null)
	mgr.score_primary_objectives()
	_check("R5 Command phase awards nothing", int(gs.state.players["1"]["primary_vp"]) == 0,
		str(gs.state.players["1"]["primary_vp"]))
	mgr.score_primary_eot_11e(1)
	# R5 EOT: hold_more window is R1-2 (skipped); per_objective 3x2 = 6
	_check("R5 EOT scores the command conditions (3x2 = 6 VP)",
		int(gs.state.players["1"]["primary_vp"]) == 6, str(gs.state.players["1"]["primary_vp"]))

	print("\n-- EOT kill conditions: Delaying Action --")
	mgr.initialize_dispositions_11e("disruption", "purge_the_foe")
	gs.state.meta["battle_round"] = 3
	_reset_vp(null)
	mgr.kills_per_round["3"] = {"1": 2, "2": 0}
	mgr._kills_this_round = {"1": 0, "2": 0}
	for obj_id in mgr.objective_control_state:
		mgr.objective_control_state[obj_id] = 0
	mgr.score_primary_eot_11e(1)
	_check("EOT: 2 VP per destroyed unit x2 = 4 VP",
		int(gs.state.players["1"]["primary_vp"]) == 4, str(gs.state.players["1"]["primary_vp"]))
	mgr.kills_per_round.clear()

	print("\n-- hold_new: Unstoppable Force --")
	mgr.initialize_dispositions_11e("purge_the_foe", "take_and_hold")
	gs.state.meta["battle_round"] = 2
	_reset_vp(null)
	mgr._kills_this_round = {"1": 0, "2": 0}
	for obj_id in mgr.objective_control_state:
		mgr.objective_control_state[obj_id] = 0
	mgr._control_at_turn_start["1"] = []
	mgr.objective_control_state[nml] = 1
	mgr.score_primary_objectives()
	# hold_min 1 non-home (4) + hold_new non-home (3) = 7
	_check("newly captured NML objective: 4 (hold) + 3 (new) = 7 VP",
		int(gs.state.players["1"]["primary_vp"]) == 7, str(gs.state.players["1"]["primary_vp"]))
	_reset_vp(null)
	mgr._control_at_turn_start["1"] = [nml]
	mgr.score_primary_objectives()
	_check("already-held objective: hold only (4 VP)",
		int(gs.state.players["1"]["primary_vp"]) == 4, str(gs.state.players["1"]["primary_vp"]))

	print("\n-- EOG conditions: enemy home (Inescapable Dominion) --")
	mgr.initialize_dispositions_11e("take_and_hold", "priority_assets")
	gs.state.meta["battle_round"] = 5
	_reset_vp(null)
	for obj_id in mgr.objective_control_state:
		mgr.objective_control_state[obj_id] = 0
	mgr.objective_control_state[home2] = 1
	mgr.score_primary_eog_11e()
	_check("EOG: 5 VP for holding the enemy home objective",
		int(gs.state.players["1"]["primary_vp"]) == 5, str(gs.state.players["1"]["primary_vp"]))
	mgr.score_primary_eog_11e()
	_check("EOG scoring is idempotent",
		int(gs.state.players["1"]["primary_vp"]) == 5, str(gs.state.players["1"]["primary_vp"]))

	print("\n-- Outmanoeuvre escalation --")
	mgr.initialize_dispositions_11e("disruption", "disruption")
	mgr._eog_primary_scored = false
	for obj_id in mgr.objective_control_state:
		mgr.objective_control_state[obj_id] = 0
	mgr.objective_control_state[nml] = 1
	gs.state.meta["battle_round"] = 1
	_reset_vp(null)
	mgr.score_primary_objectives()
	_check("R1: 4 VP per non-home objective", int(gs.state.players["1"]["primary_vp"]) == 4,
		str(gs.state.players["1"]["primary_vp"]))
	gs.state.meta["battle_round"] = 4
	_reset_vp(null)
	mgr.score_primary_objectives()
	_check("R4: escalates to 6 VP per non-home objective",
		int(gs.state.players["1"]["primary_vp"]) == 6, str(gs.state.players["1"]["primary_vp"]))

	print("\n-- 10e regression: dispatch unchanged --")
	GameConstants.edition = 10
	gs.state.meta["battle_round"] = 2
	_reset_vp(null)
	mgr.initialize_mission("take_and_hold")
	for obj_id in mgr.objective_control_state:
		mgr.objective_control_state[obj_id] = 0
	mgr.objective_control_state[nml] = 1
	mgr.score_primary_objectives()
	_check("10e Take and Hold still scores 5 VP/objective",
		int(gs.state.players["1"]["primary_vp"]) == 5, str(gs.state.players["1"]["primary_vp"]))

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
