extends SceneTree

# 11e score-or-hold (Event Companion, End of Turn): "if you met the conditions
# on one or more Secondary Missions, you CAN gain the VP specified on that
# card. If you do ... discard that Secondary Mission – it is achieved."
#  - offer_secondary_scoring_choices() marks met cards pending WITHOUT scoring
#  - a HELD card scores nothing and stays active (can score bigger later)
#  - an undecided card scores by default at resolve (End Turn)
#  - ScoringPhase defers for a HUMAN Tactical player and resolves at END_TURN
#  - AI players still score immediately on phase entry
#
# Usage: godot --headless --path . -s tests/test_secondary_score_or_hold_11e.gd

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

# Display of Might's timing shape (2 VP your turn / 5 VP opponent's), gated on
# a kill so the test controls "conditions met" without board geometry.
func _timed_card(mgr, card_id: String) -> Dictionary:
	var m = mgr._create_active_mission(SecondaryMissionData.get_mission_by_id("display_of_might"))
	m["id"] = card_id
	m["name"] = card_id
	m["scoring"] = {
		"when": SecondaryMissionData.TIMING_END_OF_EITHER_TURN,
		"conditions": [
			{"check": "enemy_unit_destroyed", "params": {}, "vp": 2, "timing": "your_turn"},
			{"check": "enemy_unit_destroyed", "params": {}, "vp": 5, "timing": "opponent_turn"},
		]}
	return m

func _reset(mgr, gs) -> Dictionary:
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["battle_round"] = 2
	gs.state["players"]["1"]["vp"] = 0
	gs.state["players"]["1"]["secondary_vp"] = 0
	mgr.initialize_for_game()
	mgr.setup_tactical_deck(1)
	mgr.setup_tactical_deck(2)
	var s1 = mgr._player_state["1"]
	s1["active"] = [_timed_card(mgr, "card_a"), _timed_card(mgr, "card_b")]
	s1["secondary_vp"] = 0
	s1["secondary_vp_this_turn"] = 0
	mgr._player_state["2"]["active"] = []
	mgr._units_destroyed_this_turn.clear()
	mgr._units_destroyed_this_turn.append({"unit_id": "U_ENEMY", "owner": 2})
	return s1

func _ids(state: Dictionary) -> Array:
	return state["active"].map(func(m): return m["id"])

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_secondary_score_or_hold_11e ===\n")
	var mgr = root.get_node_or_null("SecondaryMissionManager")
	var gs = root.get_node_or_null("GameState")
	_check("autoloads present", mgr != null and gs != null)
	GameConstants.edition = 11
	if not gs.state["meta"].has("game_config"):
		gs.state["meta"]["game_config"] = {}
	gs.state["meta"]["game_config"]["player1_type"] = "HUMAN"
	gs.state["meta"]["game_config"]["player2_type"] = "HUMAN"

	print("-- manager: offer does not score --")
	var s1 = _reset(mgr, gs)
	var offers = mgr.offer_secondary_scoring_choices(1)
	_check("both met cards offered", offers.size() == 2, str(offers))
	_check("offer is the your-turn payout (2 VP)", offers.size() == 2 and offers[0]["vp"] == 2)
	_check("no VP awarded by the offer", int(s1["secondary_vp"]) == 0, str(s1["secondary_vp"]))
	_check("both cards still active", _ids(s1).size() == 2)
	_check("pending list exposes both", mgr.get_pending_secondary_scores(1).size() == 2)

	print("-- manager: hold one, default-score the other --")
	var hold_res = mgr.set_secondary_score_held(1, "card_a", true)
	_check("hold accepted", hold_res.get("success", false), str(hold_res))
	_check("hold rejected for a card with nothing pending",
		not mgr.set_secondary_score_held(1, "nope", true).get("success", false))
	var results = mgr.resolve_pending_secondary_scores(1)
	_check("only the undecided card scored", results.size() == 1 and results[0]["mission_id"] == "card_b", str(results))
	_check("2 VP awarded", int(s1["secondary_vp"]) == 2, str(s1["secondary_vp"]))
	_check("held card still active, scored card discarded", _ids(s1) == ["card_a"], str(_ids(s1)))
	_check("pending offer cleared", mgr.get_pending_secondary_scores(1).is_empty())
	_check("held card never marked achieved", not s1["active"][0].get("achieved", false))
	_check("held card can still be discarded for CP", mgr.can_voluntarily_discard(1, 0)["allowed"])

	print("-- held card scores the bigger payout at end of opponent's turn --")
	mgr.on_turn_start(2)
	mgr._units_destroyed_this_turn.append({"unit_id": "U_ENEMY2", "owner": 2})
	gs.state["meta"]["active_player"] = 2
	var opp_results = mgr.score_secondary_missions_for_player(1)
	_check("held card scores 5 VP at end of opponent's turn",
		opp_results.size() == 1 and opp_results[0]["vp_earned"] == 5, str(opp_results))
	_check("total 7 VP (2 + 5)", int(s1["secondary_vp"]) == 7, str(s1["secondary_vp"]))

	print("-- un-hold restores scoring --")
	s1 = _reset(mgr, gs)
	mgr.offer_secondary_scoring_choices(1)
	mgr.set_secondary_score_held(1, "card_a", true)
	mgr.set_secondary_score_held(1, "card_a", false)
	_check("un-held card scores at resolve", mgr.resolve_pending_secondary_scores(1).size() == 2)

	print("-- stale offers never survive a new turn --")
	s1 = _reset(mgr, gs)
	mgr.offer_secondary_scoring_choices(1)
	mgr.on_turn_start(2)
	_check("on_turn_start clears offers", mgr.get_pending_secondary_scores(1).is_empty())

	print("-- ScoringPhase: human Tactical defers, END_TURN resolves --")
	s1 = _reset(mgr, gs)
	var phase = preload("res://phases/ScoringPhase.gd").new()
	root.add_child(phase)
	phase.game_state_snapshot = gs.create_snapshot()
	phase._on_phase_enter()
	_check("phase entry scored nothing (human)", int(s1["secondary_vp"]) == 0, str(s1["secondary_vp"]))
	var holds = phase.get_available_actions().filter(func(a): return a["type"] == "HOLD_SECONDARY")
	_check("HOLD_SECONDARY offered per met card", holds.size() == 2, str(holds))
	var v = phase.validate_action({"type": "HOLD_SECONDARY", "mission_id": "card_a", "hold": true})
	_check("HOLD_SECONDARY validates", v["valid"], str(v))
	var r = phase.process_action({"type": "HOLD_SECONDARY", "mission_id": "card_a", "hold": true})
	_check("HOLD_SECONDARY succeeds", r.get("success", false), str(r))
	_check("HOLD_SECONDARY rejected for unknown card",
		not phase.validate_action({"type": "HOLD_SECONDARY", "mission_id": "zzz"})["valid"])
	phase._resolve_pending_secondary_scores(1)
	_check("END_TURN resolve scored only the unheld card", int(s1["secondary_vp"]) == 2, str(s1["secondary_vp"]))
	_check("held card survives END_TURN", _ids(s1) == ["card_a"], str(_ids(s1)))

	print("-- ScoringPhase: AI still scores on entry --")
	gs.state["meta"]["game_config"]["player1_type"] = "AI"
	s1 = _reset(mgr, gs)
	phase.game_state_snapshot = gs.create_snapshot()
	phase._on_phase_enter()
	_check("AI scored both cards on entry", int(s1["secondary_vp"]) == 4, str(s1["secondary_vp"]))
	_check("AI gets no pending offers", mgr.get_pending_secondary_scores(1).is_empty())
	gs.state["meta"]["game_config"]["player1_type"] = "HUMAN"
	phase.queue_free()

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
