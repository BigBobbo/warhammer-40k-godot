extends SceneTree

# 11e 12.07 — the AI must be able to play the GLOBAL Consolidate step to
# completion using its real decision ladder: after END_FIGHT enters the
# step, AIDecisionMaker._decide_fight is fed the phase's own
# get_available_actions() for each half (CONSOLIDATE per eligible unit,
# then END_CONSOLIDATION) and every decision is executed through the real
# action pipeline until the phase completes. Guards against the
# AI-stall/deadlock failure mode (fallbacks submitting mid-activation
# CONSOLIDATE, END_CONSOLIDATION never chosen, step never finishing).
#
# Usage: godot --headless --path . -s tests/test_global_consolidation_ai_11e.gd

var passed := 0
var failed := 0
var _phase_completed := false
var _rejected_moves := 0  # engine rejections of AI-computed movements (b2b knife-edge bug)

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

func _board() -> void:
	var gs = root.get_node("GameState")
	gs.state["units"] = {
		"U_A": {"id": "U_A", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Fighters", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [
				{"id": "m0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 25, "base_type": "circular", "position": {"x": 500, "y": 500}},
			]},
		"U_B": {"id": "U_B", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Enemy", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [
				{"id": "e0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 25, "base_type": "circular", "position": {"x": 560, "y": 500}},
			]},
	}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 10

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_global_consolidation_ai_11e ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	if gs == null or pm == null:
		_check("autoloads", false); _finish(); return
	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition

	GameConstants.edition = 11
	_board()
	pm.transition_to_phase(10)
	var fp = pm.get_current_phase_instance()
	fp.phase_completed.connect(func(): _phase_completed = true)

	# The phase opens with the global Pile In step (12.02) — the AI ladder
	# plays it too (PILE_IN per offered unit with the production
	# empty-retry fallback, then END_PILE_IN or auto-pass).
	print("-- AI plays the Pile In step --")
	var pi_steps := 0
	while fp.pile_in_step_11e == fp.PileInStep11e.ACTIVE and pi_steps < 10:
		var pi_actions = fp.get_available_actions()
		if pi_actions.is_empty():
			break
		var pi_decision = AIDecisionMaker._decide_fight(gs.state, pi_actions, fp.current_selecting_player)
		if pi_decision.is_empty():
			_check("AI produced a pile-in decision for the offered actions", false, str(pi_actions))
			break
		print("  AI (P%d) -> %s %s" % [fp.current_selecting_player, pi_decision.get("type", "?"), pi_decision.get("unit_id", "")])
		var pi_res = fp.execute_action(pi_decision)
		if not pi_res.get("success", false) and pi_decision.get("type", "") == "PILE_IN" \
				and not pi_decision.get("movements", {}).is_empty():
			_rejected_moves += 1
			print("  AI (P%d) -> PILE_IN %s retry with no movement (was: %s)" % [
				fp.current_selecting_player, pi_decision.get("unit_id", ""), str(pi_res.get("errors", []))])
			pi_decision["movements"] = {}
			pi_res = fp.execute_action(pi_decision)
		_check("AI pile-in action %s succeeded" % pi_decision.get("type", "?"), pi_res.get("success", false), str(pi_res))
		if not pi_res.get("success", false):
			break
		pi_steps += 1
	_check("AI played the Pile In step to completion",
		fp.pile_in_step_11e == fp.PileInStep11e.DONE, "pi_steps=%d" % pi_steps)

	# Fight step resolved (attack-flow AI coverage lives elsewhere) —
	# enter the Consolidate step the way the AI does (END_FIGHT from the
	# offered actions).
	fp.sequencer_11e.mark_fought("U_A")
	fp.sequencer_11e.mark_fought("U_B")
	var r_end = fp.execute_action({"type": "END_FIGHT", "player": 1})
	_check("END_FIGHT enters the Consolidate step", r_end.get("success", false)
		and fp.consolidation_step_11e == fp.ConsolidationStep11e.ACTIVE, str(r_end))

	# Both halves are played by the AI ladder from the phase's own action
	# menu. 10 iterations is far more than the 2 units + 2 passes need —
	# if the loop hits the cap, the AI stalled.
	var steps_taken := 0
	while not _phase_completed and steps_taken < 10:
		var snapshot = gs.state
		var actions = fp.get_available_actions()
		if actions.is_empty():
			break
		var acting_player = fp.current_selecting_player
		var decision = AIDecisionMaker._decide_fight(snapshot, actions, acting_player)
		if decision.is_empty():
			_check("AI produced a decision for the offered actions", false, str(actions))
			break
		print("  AI (P%d) -> %s %s" % [acting_player, decision.get("type", "?"), decision.get("unit_id", "")])
		var res = fp.execute_action(decision)
		if not res.get("success", false) and decision.get("type", "") == "CONSOLIDATE" \
				and not decision.get("movements", {}).is_empty():
			# Production behavior: AIPlayer retries a rejected CONSOLIDATE
			# with empty movements (AIPlayer.gd T12-4 fallback) — the unit
			# forgoes its move rather than stalling the step.
			_rejected_moves += 1
			print("  AI (P%d) -> CONSOLIDATE %s retry with no movement (was: %s)" % [
				acting_player, decision.get("unit_id", ""), str(res.get("errors", []))])
			decision["movements"] = {}
			res = fp.execute_action(decision)
		_check("AI action %s succeeded" % decision.get("type", "?"), res.get("success", false), str(res))
		if not res.get("success", false):
			break
		steps_taken += 1

	_check("AI played the Consolidate step to phase completion", _phase_completed,
		"steps_taken=%d step=%s" % [steps_taken, str(fp.consolidation_step_11e)])
	_check("both units consolidated by the AI (it moves everything it can)",
		fp.units_that_consolidated_11e.has("U_A") and fp.units_that_consolidated_11e.has("U_B"),
		str(fp.units_that_consolidated_11e))
	_check("no AI stall (well under the iteration cap)", steps_taken < 10, str(steps_taken))
	# AI_B2B_GAP_PX regression: the engine must ACCEPT the AI's computed
	# movements — b2b placements used to sit on the strict-overlap knife
	# edge, every move was rejected, and the fallback made the AI fully
	# passive in both global steps.
	_check("no AI movement was rejected by the engine (b2b placements accepted)",
		_rejected_moves == 0, "rejected=%d" % _rejected_moves)
	# And the AI actually MOVED: U_A's model piled in from x=500 to base
	# contact with the enemy at x=560 (center distance = sum radii + gap
	# ~= 39.9px -> x ~= 520.1).
	var ua_x = float(gs.state["units"]["U_A"]["models"][0]["position"]["x"])
	_check("U_A's model physically piled in to base contact (x ~520, was 500)",
		ua_x > 518.0 and ua_x < 523.0, "x=%.2f" % ua_x)

	gs.state = prev_state
	GameConstants.edition = prev_edition
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
