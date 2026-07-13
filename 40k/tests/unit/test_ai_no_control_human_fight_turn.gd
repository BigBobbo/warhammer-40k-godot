extends SceneTree

# Regression: the AI must NOT act for the HUMAN during the Fight phase.
#
# Reported bug: while playing against the AI, after the AI charged one of the
# player's units, the player had no control of piling in — the AI moved the
# player's unit for them. Root cause: on the AI's own turn, the Fight phase
# alternates between both players in each of its steps (12.02 Pile In, 12.04
# Fight, 12.07 Consolidate), but AIPlayer._evaluate_and_act defaulted the
# acting player to the active AI, so during the human's half the active AI
# resolved the human's units (get_available_actions offers that half's units;
# the pile-in validator only checks unit ownership, so it accepted the move).
#
# The fix adds AIPlayer._human_fight_turn_pending(): the Fight-phase analogue
# of the Charge-phase reactive-window owner check. When it reports a human,
# _evaluate_and_act idles. This test drives the REAL FightPhase pile-in step
# and asserts the helper (and the acting-player decision it gates) across:
#   - the AI's own half  -> AI acts (helper returns 0)
#   - the human's half   -> AI waits (helper returns the human)
#   - the Fight step: human's turn to select -> wait; fight over -> don't wait
#   - the Consolidate step: human's half -> wait; AI's half -> act
#
# Usage: godot --headless --path 40k -s tests/unit/test_ai_no_control_human_fight_turn.gd

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
	create_timer(0.1).timeout.connect(_run)

func _board(gs) -> void:
	# U_A (P1, human) engaged with U_B (P2, AI): ~0.5" apart. The AI (P2) has
	# charged, so both units are engaged and eligible to pile in.
	gs.state["units"] = {
		"U_A": {"id": "U_A", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Human Fighters", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [
				{"id": "m0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 25, "base_type": "circular", "position": {"x": 500, "y": 500}},
			]},
		"U_B": {"id": "U_B", "owner": 2, "status": 2, "flags": {"charged_this_turn": true},
			"meta": {"name": "AI Chargers", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [
				{"id": "e0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 25, "base_type": "circular", "position": {"x": 560, "y": 500}},
			]},
	}
	gs.state["meta"]["active_player"] = 2   # the AI's turn
	gs.state["meta"]["phase"] = 10

# Replicate the acting-player determination in _evaluate_and_act (including the
# new human-turn guard) and report whether the AI would ACT this tick.
func _ai_would_act(ai, gs) -> bool:
	var active_player = gs.get_active_player()
	var acting_player = active_player
	var fight_player = ai._get_fight_phase_selecting_player()
	if fight_player > 0 and fight_player != active_player and ai.is_ai_player(fight_player):
		acting_player = fight_player
	if ai._human_fight_turn_pending() > 0:
		return false  # the guard idles the AI
	return ai.is_ai_player(acting_player)

func _run():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_ai_no_control_human_fight_turn ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var ai = root.get_node_or_null("AIPlayer")
	if gs == null or pm == null or ai == null:
		_check("autoloads present", false, "gs=%s pm=%s ai=%s" % [gs, pm, ai]); _finish(); return

	var prev_edition = GameConstants.edition
	var prev_enabled = ai.enabled
	var prev_players = ai.ai_players.duplicate(true)
	GameConstants.edition = 11
	ai.enabled = true
	ai.ai_players = {1: false, 2: true}  # P1 human, P2 AI

	_board(gs)
	pm.transition_to_phase(10)  # FIGHT
	var fp = pm.get_current_phase_instance()

	print("-- 12.02 Pile In step opens with the ACTIVE player (P2, the AI) --")
	_check("Pile In step ACTIVE", fp.pile_in_step_11e == fp.PileInStep11e.ACTIVE)
	_check("P2 (AI) piles in first", fp.piling_in_player_11e == 2, "player=%d" % fp.piling_in_player_11e)
	_check("AI's own half: helper reports no human pending (AI acts)",
		ai._human_fight_turn_pending() == 0, "got %d" % ai._human_fight_turn_pending())
	_check("AI's own half: AI would act", _ai_would_act(ai, gs))

	print("\n-- AI ends its half; the human's (P1) half begins --")
	var r_end2 = fp.execute_action({"type": "END_PILE_IN", "player": 2})
	_check("P2 END_PILE_IN succeeds", r_end2.get("success", false), str(r_end2))
	_check("step now on P1 (human) half",
		fp.pile_in_step_11e == fp.PileInStep11e.ACTIVE and fp.piling_in_player_11e == 1,
		"step=%s player=%d" % [str(fp.pile_in_step_11e), fp.piling_in_player_11e])
	_check("FIX: human's pile-in half -> helper reports human (1)",
		ai._human_fight_turn_pending() == 1, "got %d" % ai._human_fight_turn_pending())
	_check("FIX: the AI does NOT act during the human's pile-in half",
		not _ai_would_act(ai, gs))

	# Sanity: the human's unit is untouched (the AI did not pile it in).
	_check("human's unit U_A model has not been moved by the AI",
		gs.state["units"]["U_A"]["models"][0]["position"]["x"] == 500.0,
		str(gs.state["units"]["U_A"]["models"][0]["position"]))

	print("\n-- the human plays their half; both done -> the Fight step (12.04) begins --")
	# Human piles in their own unit (as the dialog would). U_A is P1's only
	# eligible unit, so the engine auto-passes P1's half the moment it resolves
	# (see test_global_pile_in_11e.gd), completing the step.
	var r_a = fp.execute_action({"type": "PILE_IN", "unit_id": "U_A", "movements": {"0": Vector2(515, 500)}, "player": 1})
	_check("human's own PILE_IN applies", r_a.get("success", false), str(r_a))
	_check("human's unit U_A ended where the PLAYER moved it (515, not the AI's 505)",
		gs.state["units"]["U_A"]["models"][0]["position"]["x"] == 515.0,
		str(gs.state["units"]["U_A"]["models"][0]["position"]))
	_check("Pile In step DONE — Fight step begins", fp.pile_in_step_11e == fp.PileInStep11e.DONE)

	# The Fight step alternates starting with the ACTIVE player (P2, AI).
	var sel = fp.sequencer_11e.peek_selection(gs.state)
	_check("Fight step: AI (P2) picks first — helper reports no human pending",
		int(sel.get("player", 0)) == 2 and ai._human_fight_turn_pending() == 0,
		"peek.player=%s helper=%d" % [str(sel.get("player")), ai._human_fight_turn_pending()])
	_check("Fight step, AI's turn to select: AI would act", _ai_would_act(ai, gs))

	# Mark the AI's unit fought -> it becomes the human's turn to select U_A.
	fp.sequencer_11e.mark_fought("U_B")
	var sel2 = fp.sequencer_11e.peek_selection(gs.state)
	_check("Fight step: after AI's unit fights, P1 (human) is offered U_A",
		int(sel2.get("player", 0)) == 1, "peek.player=%s cands=%s" % [str(sel2.get("player")), str(sel2.get("candidates"))])
	_check("FIX: human's turn to select a fighter -> helper reports human (1)",
		ai._human_fight_turn_pending() == 1, "got %d" % ai._human_fight_turn_pending())
	_check("FIX: the AI does NOT select/fight the human's fighter",
		not _ai_would_act(ai, gs))

	print("\n-- END_FIGHT edge: once the fight step is over, the active AI may end it --")
	fp.sequencer_11e.mark_fought("U_A")  # nobody eligible now
	_check("fight step over: helper reports 0 (does not block the active player's END_FIGHT)",
		ai._human_fight_turn_pending() == 0, "got %d" % ai._human_fight_turn_pending())
	_check("fight step over: the active AI would act (to submit END_FIGHT)", _ai_would_act(ai, gs))

	print("\n-- 12.07 Consolidate step: the human's half also belongs to the player --")
	# Drive the fields the helper reads (full consolidation flow is covered
	# elsewhere; here we only assert the ownership gate).
	fp.pile_in_step_11e = fp.PileInStep11e.DONE
	fp.consolidation_step_11e = fp.ConsolidationStep11e.ACTIVE
	fp.consolidating_player_11e = 1  # human's half
	_check("FIX: human's consolidate half -> helper reports human (1)",
		ai._human_fight_turn_pending() == 1, "got %d" % ai._human_fight_turn_pending())
	_check("FIX: the AI does NOT consolidate the human's units", not _ai_would_act(ai, gs))
	fp.consolidating_player_11e = 2  # the AI's half
	_check("AI's consolidate half -> helper reports 0 (AI acts)",
		ai._human_fight_turn_pending() == 0, "got %d" % ai._human_fight_turn_pending())
	_check("AI's consolidate half: AI would act", _ai_would_act(ai, gs))

	GameConstants.edition = prev_edition
	ai.enabled = prev_enabled
	ai.ai_players = prev_players
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
