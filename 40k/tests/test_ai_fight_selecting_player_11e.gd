extends SceneTree

# ai:AIR-1 — AI fight-phase stall: AIPlayer._get_fight_phase_selecting_player()
# must agree with FightPhase's 12.04 FightSequencer, which is the selection
# AUTHORITY (FightPhase.get_available_actions offers exactly its candidates,
# tagged with the picking player).
#
# Deterministic reproduction of the state the AI bench hit in
# ai_eng_shootaboyz_o1 seed 3008 (round 2, Fight, Custodes P2's turn): during
# the 12.07 Consolidate step a unit that had never fought (there: an UNLEASH THE
# LIONS split unit created mid-phase) ended up engaged, so a 12.08 forced fight
# was pending (_forced_fights_pending_11e() true). get_available_actions then
# skipped the Consolidate branch and offered SELECT_FIGHTER for Player 2, but
# AIPlayer skipped its consolidation override (forced fights pending) and fell
# back to the stale current_selecting_player = 1. The AI was asked to decide
# for P1, made no decision ("No decision made for player 1" x142) and the game
# stalled until the 200-action fallback (or the bench's 90 s stall detector).
#
# Usage: godot --headless --path . -s tests/test_ai_fight_selecting_player_11e.gd

var AIDecisionMakerScript = null

var passed := 0
var failed := 0


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _initialize() -> void:
	await create_timer(0.2).timeout
	_run()
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _model(mid: String, x: float, y: float) -> Dictionary:
	return {"id": mid, "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 25,
		"base_type": "circular", "position": {"x": x, "y": y}}


func _unit(uid: String, owner: int, name: String, models: Array) -> Dictionary:
	return {"id": uid, "owner": owner, "status": 2, "flags": {},
		"meta": {"name": name, "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1, "toughness": 4, "save": 4},
			"weapons": [{"name": "Close combat weapon", "type": "Melee", "attacks": "2", "weapon_skill": "3",
				"strength": "4", "ap": "0", "damage": "1"}]},
		"models": models}


func _run() -> void:
	print("\n=== test_ai_fight_selecting_player_11e (ai:AIR-1) ===\n")
	var gs = root.get_node("GameState")
	var pm = root.get_node("PhaseManager")
	var aip = root.get_node("AIPlayer")
	AIDecisionMakerScript = load("res://scripts/AIDecisionMaker.gd")
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	aip.enabled = false
	aip.ai_players = {1: true, 2: true}

	# P2's turn (as in the stalled game). U_A (P1) engaged with U_B (P2);
	# U_C (P2) starts far away — it never fights in the Fight step.
	gs.state["units"] = {
		"U_A": _unit("U_A", 1, "Boyz", [_model("m0", 500, 500)]),
		"U_B": _unit("U_B", 2, "Custodian Guard", [_model("e0", 560, 500)]),
		"U_C": _unit("U_C", 2, "Allarus Custodians (Lion 3)", [_model("l0", 1500, 1500)]),
	}
	gs.state["meta"]["active_player"] = 2
	gs.state["meta"]["phase"] = 10
	pm.transition_to_phase(10)
	var fp = pm.get_current_phase_instance()
	if fp.phase_completed.is_connected(pm._on_phase_completed):
		fp.phase_completed.disconnect(pm._on_phase_completed)
	for _i in range(2):
		if int(fp.pile_in_step_11e) != int(fp.PileInStep11e.ACTIVE):
			break
		fp.execute_action({"type": "END_PILE_IN", "player": int(fp.piling_in_player_11e)})
	_check("set-up: the Pile In step is over", int(fp.pile_in_step_11e) != int(fp.PileInStep11e.ACTIVE))
	fp.sequencer_11e.mark_fought("U_A")
	fp.sequencer_11e.mark_fought("U_B")
	var r_end = fp.execute_action({"type": "END_FIGHT", "player": 2})
	_check("set-up: END_FIGHT enters the Consolidate step", r_end.get("success", false)
		and int(fp.consolidation_step_11e) == int(fp.ConsolidationStep11e.ACTIVE), str(r_end.get("error", "")))

	# The never-fought P2 unit is now engaged with the P1 Boyz (the split
	# Allarus unit after its consolidation): a 12.08 forced fight is pending.
	gs.state["units"]["U_C"]["models"][0]["position"] = {"x": 500, "y": 440}
	# The stale value observed in the log ('fight phase selecting player
	# override {acting_player:1, active_player:2}').
	fp.current_selecting_player = 1
	_check("forced fight pending (12.08) during the Consolidate step", fp._forced_fights_pending_11e())
	var sel: Dictionary = fp.sequencer_11e.peek_selection(gs.state)
	_check("the sequencer offers U_C to Player 2", not sel.get("done", true) and int(sel.get("player", 0)) == 2 and "U_C" in sel.get("candidates", []), str(sel))
	var offered_for := -1
	for a in fp.get_available_actions():
		if str(a.get("type", "")) == "SELECT_FIGHTER" and str(a.get("unit_id", "")) == "U_C":
			offered_for = int(a.get("player", -1))
	_check("get_available_actions offers SELECT_FIGHTER U_C for Player 2", offered_for == 2, str(offered_for))

	# The AI's acting player must be the sequencer's picker, not the stale value.
	var acting: int = aip._get_fight_phase_selecting_player()
	_check("AIPlayer acts as Player 2 (the sequencer's picker), not the stale Player 1", acting == 2, "acting=%d" % acting)
	var stale_decision: Dictionary = AIDecisionMakerScript._decide_fight(gs.state, fp.get_available_actions(), 1)
	_check("(why it stalled) deciding as Player 1 yields no SELECT_FIGHTER for P2's unit",
		str(stale_decision.get("type", "")) != "SELECT_FIGHTER" or str(stale_decision.get("unit_id", "")) != "U_C", str(stale_decision))
	var decision: Dictionary = AIDecisionMakerScript._decide_fight(gs.state, fp.get_available_actions(), acting)
	_check("deciding as the acting player selects U_C to fight", str(decision.get("type", "")) == "SELECT_FIGHTER" and str(decision.get("unit_id", "")) == "U_C", str(decision))
	if not decision.has("player"):
		decision["player"] = acting
	var res = fp.execute_action(decision)
	_check("the phase accepts the AI's SELECT_FIGHTER (no stall)", res.get("success", false) and str(fp.active_fighter_id) == "U_C", str(res.get("error", "")))

	# Ordinary 12.04 alternation outside the Consolidate step: after a fight the
	# picker passes to the opponent even if current_selecting_player lags.
	gs.state["units"] = {
		"U_A": _unit("U_A", 1, "Boyz", [_model("m0", 500, 500)]),
		"U_B": _unit("U_B", 2, "Custodian Guard", [_model("e0", 560, 500)]),
		"U_D": _unit("U_D", 1, "Nobz", [_model("n0", 900, 900)]),
		"U_E": _unit("U_E", 2, "Prosecutors", [_model("p0", 960, 900)]),
	}
	gs.state["meta"]["active_player"] = 2
	pm.transition_to_phase(6)
	pm.transition_to_phase(10)
	fp = pm.get_current_phase_instance()
	if fp.phase_completed.is_connected(pm._on_phase_completed):
		fp.phase_completed.disconnect(pm._on_phase_completed)
	for _i in range(2):
		if int(fp.pile_in_step_11e) != int(fp.PileInStep11e.ACTIVE):
			break
		fp.execute_action({"type": "END_PILE_IN", "player": int(fp.piling_in_player_11e)})
	var sel2: Dictionary = fp.sequencer_11e.peek_selection(gs.state)
	fp.current_selecting_player = 2 if int(sel2.get("player", 1)) == 1 else 1  # stale
	_check("Fight step: AIPlayer follows the sequencer's picker (P%d) over a stale current_selecting_player" % int(sel2.get("player", 0)),
		aip._get_fight_phase_selecting_player() == int(sel2.get("player", 0)), "sel=%s acting=%d" % [str(sel2), aip._get_fight_phase_selecting_player()])

	aip.ai_players = {1: false, 2: false}
	GameConstants.edition = prev_edition
