extends SceneTree

# 11e 12.02 — REGRESSION guard for the AIPlayer AUTOLOAD trigger.
#
# The AI decision ladder (AIDecisionMaker._decide_fight producing a PILE_IN) was
# already covered by test_ai_pile_in.gd / test_global_consolidation_ai_11e.gd,
# but those drive the decision maker DIRECTLY and never exercise the autoload
# trigger. The reported bug lived in the trigger: during the AI's OWN half of the
# global Pile In step, AIPlayer._human_fight_turn_pending() fell through the
# (correct) Pile-In branch into the 12.04 Fight-step sequencer branch, which
# peeks the FIRST fighter — the active human — and reported "the human owns this
# turn". So _evaluate_and_act idled ("fight-phase turn belongs to human, AI
# waits") and the AI opponent never piled in; the global step stalled on its
# half. This test pins _human_fight_turn_pending()'s return across both halves.
#
# Usage: godot --headless --path . -s tests/test_ai_pile_in_autoload_trigger_11e.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + str(detail) if str(detail) != "" else ""])

func _init():
	create_timer(0.1).timeout.connect(_run)

func _board(gs) -> void:
	# P1 (human) charged into P2 (AI); both engaged (25mm bases, 60px apart
	# center ~= 0.5" edge-to-edge). Mirrors the reported screenshot.
	gs.state["units"] = {
		"U_A": {"id": "U_A", "owner": 1, "status": 2, "flags": {"charged_this_turn": true},
			"meta": {"name": "P1 charger", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [{"id": "m0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 25, "base_type": "circular", "position": {"x": 500, "y": 500}}]},
		"U_B": {"id": "U_B", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "P2 AI target", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [{"id": "e0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 25, "base_type": "circular", "position": {"x": 560, "y": 500}}]},
	}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 10

func _run():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_ai_pile_in_autoload_trigger_11e ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var ai = root.get_node_or_null("AIPlayer")
	if gs == null or pm == null or ai == null:
		_check("autoloads present (GameState/PhaseManager/AIPlayer)", false)
		return _finish()
	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition

	GameConstants.edition = 11
	ai.configure({1: "HUMAN", 2: "AI"})
	# Keep the test deterministic: drive the fight steps ourselves rather than
	# racing the autoload's frame-paced _process (the trigger's return value is
	# what we assert; the end-to-end autoload path is covered by the live
	# windowed bridge run).
	ai.set_process(false)
	_board(gs)
	pm.transition_to_phase(10)
	var fp = pm.get_current_phase_instance()

	_check("phase opens on the global Pile In step, active human (P1) first",
		fp.pile_in_step_11e == fp.PileInStep11e.ACTIVE and fp.piling_in_player_11e == 1,
		"step=%s player=%s" % [fp.pile_in_step_11e, fp.piling_in_player_11e])
	_check("both units are eligible to pile in (engaged)",
		fp._pile_in_eligible_units_11e(1) == ["U_A"] and fp._pile_in_eligible_units_11e(2) == ["U_B"])

	# During the HUMAN's half the AI must idle and yield to the human.
	_check("during the HUMAN's pile-in half, _human_fight_turn_pending() == 1 (yield to human)",
		ai._human_fight_turn_pending() == 1, ai._human_fight_turn_pending())

	# Human ends their half -> the AI's half begins.
	var r = fp.execute_action({"type": "END_PILE_IN", "player": 1})
	_check("END_PILE_IN(player 1) succeeds", r.get("success", false), r)
	_check("the AI (P2) now owns the pile-in half",
		fp.piling_in_player_11e == 2 and fp.pile_in_step_11e == fp.PileInStep11e.ACTIVE,
		"step=%s player=%s" % [fp.pile_in_step_11e, fp.piling_in_player_11e])

	# THE REGRESSION: during the AI's OWN half the trigger must NOT report a
	# human. Pre-fix this returned 1 (fell through to the fight sequencer, which
	# peeked P1 as the first fighter) and the AI idled forever.
	_check("during the AI's pile-in half, _human_fight_turn_pending() == 0 (nobody-human blocks the AI)",
		ai._human_fight_turn_pending() == 0, ai._human_fight_turn_pending())
	_check("_is_any_ai_player_active() is TRUE so the AI (and watchdog) will act",
		ai._is_any_ai_player_active() == true)

	# And the AI can actually play + complete its half from the offered actions.
	var guard := 0
	while fp.pile_in_step_11e == fp.PileInStep11e.ACTIVE and guard < 8:
		var acts = fp.get_available_actions()
		if acts.is_empty():
			break
		var d = AIDecisionMaker._decide_fight(gs.state, acts, fp.current_selecting_player)
		if d.is_empty():
			_check("AI produced a decision for its offered pile-in actions", false, str(acts))
			break
		var rr = fp.execute_action(d)
		if not rr.get("success", false) and d.get("type", "") == "PILE_IN" and not d.get("movements", {}).is_empty():
			d["movements"] = {}
			rr = fp.execute_action(d)
		if not rr.get("success", false):
			_check("AI action %s executed" % d.get("type", "?"), false, str(rr))
			break
		guard += 1
	_check("Pile In step completes and the Fight step begins (no stall)",
		fp.pile_in_step_11e == fp.PileInStep11e.DONE, "step=%s guard=%d" % [fp.pile_in_step_11e, guard])
	_check("the AI's unit U_B actually piled in",
		fp.units_that_piled_in.has("U_B"), fp.units_that_piled_in.keys())
	var ub_x = float(gs.state["units"]["U_B"]["models"][0]["position"]["x"])
	_check("U_B physically moved toward the enemy (x < 560, was 560)",
		ub_x < 559.5, "x=%.2f" % ub_x)

	gs.state = prev_state
	GameConstants.edition = prev_edition
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
