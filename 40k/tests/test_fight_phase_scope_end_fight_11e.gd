extends SceneTree

# END_FIGHT in the 11e Fight step — fighting is MANDATORY (12.04).
#
# 12.04: "Players resolve the following sequence until all eligible units have
# been selected to fight and their attacks have been resolved." A player can
# not decline an eligible fight. The ONLY exception is core rules p.74
# "Eligible to fight, but unable to fight": when the sequence returns to a
# player and ALL of their eligible units are more than 5" from all enemy
# units, they may PASS; the sequence returns to their opponent. If both
# players pass in succession, or one passes when their opponent has no
# remaining eligible units, the Fight step ends. A pass is not a forfeit —
# the passing player is asked again once their opponent has selected a unit.
#
# Regression for the audit finding (P0-2): END_FIGHT was accepted
# unconditionally and marked the ending player's remaining eligible units as
# fought, letting a player strategically skip mandatory fights.
#
# Drives the REAL FightPhase pipeline (execute_action / get_available_actions)
# and the FightSequencer, and asserts:
#   A. engaged units on both sides: END_FIGHT is not offered and is rejected
#      for BOTH players; nobody is marked fought.
#   B. once every eligible unit has fought, END_FIGHT enters the Consolidate
#      step.
#   C. a player whose only eligible unit is >5" from every enemy may pass;
#      with no opponent units eligible the Fight step ends.
#   D. both players pass in succession -> the Fight step ends.
#   E. a pass is not a forfeit: once the opponent selects a unit, the passing
#      player is offered their unit again.
#   F. a unit within 5" of an enemy blocks the pass (must fight).
#
# Usage: godot --headless --path . -s tests/test_fight_phase_scope_end_fight_11e.gd

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
	create_timer(0.1).timeout.connect(_run_tests)

# 40px = 1"; 25mm base radius ~19.7px.
func _unit(id: String, owner: int, x: float, y: float, flags: Dictionary = {}) -> Dictionary:
	return {"id": id, "owner": owner, "status": 2, "flags": flags,
		"meta": {"name": id, "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 2}},
		"models": [
			{"id": id + "_m0", "alive": true, "wounds": 2, "current_wounds": 2, "base_mm": 25, "base_type": "circular", "position": {"x": x, "y": y}},
		]}

func _start_fight_step(gs, pm, units: Dictionary):
	gs.state["units"] = units
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 10
	pm.transition_to_phase(10)  # FIGHT
	var fp = pm.get_current_phase_instance()
	fp.execute_action({"type": "END_PILE_IN", "player": 1})
	fp.execute_action({"type": "END_PILE_IN", "player": 2})
	return fp

func _end_fight_actions(fp) -> Array:
	var out: Array = []
	for a in fp.get_available_actions():
		if a.get("type", "") == "END_FIGHT":
			out.append(a)
	return out

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_fight_phase_scope_end_fight_11e ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	if gs == null or pm == null:
		_check("autoloads", false); _finish(); return
	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11

	print("\n-- A: engaged units on both sides — END_FIGHT is rejected for both players --")
	# U_ORK (P1) engaged with U_PROS (P2) at ~0.5" edge-to-edge.
	var fp = _start_fight_step(gs, pm, {
		"U_ORK": _unit("U_ORK", 1, 500, 500),
		"U_PROS": _unit("U_PROS", 2, 560, 500),
	})
	_check("Fight step running", fp.pile_in_step_11e == fp.PileInStep11e.DONE)
	_check("Ork (P1) eligible", fp.sequencer_11e.eligible_to_fight("U_ORK", gs.state))
	_check("Prosecutors (P2) eligible", fp.sequencer_11e.eligible_to_fight("U_PROS", gs.state))
	_check("END_FIGHT not offered while fights are owed", _end_fight_actions(fp).is_empty(), str(_end_fight_actions(fp)))
	var status = fp.get_end_fight_status()
	_check("status: step not over, P1 selects, cannot pass",
		not status.step_over and status.selecting_player == 1 and not status.can_pass, str(status))
	var r1 = fp.execute_action({"type": "END_FIGHT", "player": 1})
	_check("END_FIGHT by the selecting player (P1) is REJECTED", not r1.get("success", false), str(r1))
	_check("rejection names the unit still to fight", str(r1).find("U_ORK") >= 0, str(r1))
	var r2 = fp.execute_action({"type": "END_FIGHT", "player": 2})
	_check("END_FIGHT by the non-selecting player (P2) is REJECTED", not r2.get("success", false), str(r2))
	_check("Ork NOT marked fought", fp.sequencer_11e.eligible_to_fight("U_ORK", gs.state))
	_check("Prosecutors NOT marked fought", fp.sequencer_11e.eligible_to_fight("U_PROS", gs.state))
	_check("no has_fought flag written", not gs.state.units["U_ORK"].flags.get("has_fought", false))
	_check("still in the Fight step", fp.consolidation_step_11e == fp.ConsolidationStep11e.NOT_STARTED)

	print("\n-- B: once everyone has fought, END_FIGHT enters the Consolidate step --")
	fp.sequencer_11e.mark_fought("U_ORK")
	fp.sequencer_11e.mark_fought("U_PROS")
	_check("END_FIGHT offered once the step is over", _end_fight_actions(fp).size() == 1)
	var r3 = fp.execute_action({"type": "END_FIGHT", "player": 1})
	_check("END_FIGHT succeeds", r3.get("success", false), str(r3))
	_check("Consolidate step now ACTIVE",
		fp.consolidation_step_11e == fp.ConsolidationStep11e.ACTIVE, str(fp.consolidation_step_11e))

	print("\n-- C: unable to fight (>5\" from every enemy) — the selecting player may pass --")
	# U_CHG (P1) charged but its target is gone; nearest enemy 20"+ away. The
	# P2 unit is not eligible (not engaged, did not charge).
	fp = _start_fight_step(gs, pm, {
		"U_CHG": _unit("U_CHG", 1, 200, 200, {"charged_this_turn": true}),
		"U_FAR": _unit("U_FAR", 2, 1200, 1200),
	})
	_check("charged unit eligible", fp.sequencer_11e.eligible_to_fight("U_CHG", gs.state))
	status = fp.get_end_fight_status()
	_check("status: P1 selecting and may pass", not status.step_over and status.selecting_player == 1 and status.can_pass, str(status))
	var efa = _end_fight_actions(fp)
	_check("END_FIGHT offered as a pass for P1",
		efa.size() == 1 and efa[0].get("pass", false) and int(efa[0].get("player", 0)) == 1, str(efa))
	var r4 = fp.execute_action({"type": "END_FIGHT", "player": 1})
	_check("P1 pass succeeds", r4.get("success", false), str(r4))
	_check("opponent has nothing eligible -> Fight step ends (Consolidate ACTIVE)",
		fp.consolidation_step_11e == fp.ConsolidationStep11e.ACTIVE, str(fp.consolidation_step_11e))

	print("\n-- D: both players pass in succession — the Fight step ends --")
	fp = _start_fight_step(gs, pm, {
		"U_CHG": _unit("U_CHG", 1, 200, 200, {"charged_this_turn": true}),
		"U_HI": _unit("U_HI", 2, 1200, 1200, {"charged_this_turn": true}),
	})
	var r5 = fp.execute_action({"type": "END_FIGHT", "player": 1})
	_check("P1 pass succeeds", r5.get("success", false), str(r5))
	_check("Fight step still running after one pass",
		fp.consolidation_step_11e == fp.ConsolidationStep11e.NOT_STARTED, str(fp.consolidation_step_11e))
	_check("selection handed to P2", fp.current_selecting_player == 2 and r5.get("trigger_fight_selection", false), str(r5))
	_check("P1's passed unit is still eligible (not forfeited)", fp.sequencer_11e.eligible_to_fight("U_CHG", gs.state))
	var r6 = fp.execute_action({"type": "END_FIGHT", "player": 1})
	_check("P1 cannot pass again out of turn", not r6.get("success", false), str(r6))
	var r7 = fp.execute_action({"type": "END_FIGHT", "player": 2})
	_check("P2 pass succeeds", r7.get("success", false), str(r7))
	_check("both passed in succession -> Fight step ends (Consolidate ACTIVE)",
		fp.consolidation_step_11e == fp.ConsolidationStep11e.ACTIVE, str(fp.consolidation_step_11e))

	print("\n-- E: a pass is not a forfeit — the passer is asked again after the opponent selects --")
	# P1: U_CHG far away (can pass) + U_DONE already fought. P2: U_ENG engaged
	# with U_DONE (owed a fight).
	fp = _start_fight_step(gs, pm, {
		"U_CHG": _unit("U_CHG", 1, 200, 200, {"charged_this_turn": true}),
		"U_DONE": _unit("U_DONE", 1, 900, 900),
		"U_ENG": _unit("U_ENG", 2, 960, 900),
	})
	fp.sequencer_11e.mark_fought("U_DONE")
	status = fp.get_end_fight_status()
	_check("P1 selects first and may pass", status.selecting_player == 1 and status.can_pass, str(status))
	var r8 = fp.execute_action({"type": "END_FIGHT", "player": 1})
	_check("P1 pass succeeds", r8.get("success", false), str(r8))
	var sel = fp.sequencer_11e.peek_selection(gs.state)
	_check("P2 now selects U_ENG", sel.player == 2 and "U_ENG" in sel.candidates, str(sel))
	fp.sequencer_11e.select_to_fight("U_ENG", gs.state)
	sel = fp.sequencer_11e.peek_selection(gs.state)
	_check("after P2 selects, the sequence returns to P1 with U_CHG offered again",
		not sel.done and sel.player == 1 and "U_CHG" in sel.candidates, str(sel))

	print("\n-- F: a unit within 5\" of an enemy blocks the pass --")
	# U_NEAR (P1) charged, 4" from U_E2 (not engaged — 2" ER).
	fp = _start_fight_step(gs, pm, {
		"U_NEAR": _unit("U_NEAR", 1, 400, 400, {"charged_this_turn": true}),
		"U_E2": _unit("U_E2", 2, 400 + 39.4 + 160, 400),
	})
	_check("U_NEAR not engaged but eligible (charged)",
		not root.get_node("RulesEngine").is_unit_engaged("U_NEAR", gs.state) and fp.sequencer_11e.eligible_to_fight("U_NEAR", gs.state))
	status = fp.get_end_fight_status()
	_check("cannot pass with a unit 4\" from an enemy", not status.can_pass, str(status))
	var r9 = fp.execute_action({"type": "END_FIGHT", "player": 1})
	_check("END_FIGHT rejected", not r9.get("success", false), str(r9))

	# Restore
	GameConstants.edition = prev_edition
	gs.state = prev_state
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
