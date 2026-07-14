extends SceneTree

# Fight-phase scope of END_FIGHT (12.04). Ending your OWN fights must not
# forfeit the opponent's — when one player stops selecting, the other player
# still gets to fight all of their remaining eligible units before the phase
# moves on to the Consolidate step.
#
# Regression for the reported bug: the Ork (active) player clicked "End Fight
# Phase" and the enemy Prosecutors (owed a Remaining-Combats fight) were cut
# out of the phase instead of getting to fight.
#
# Drives the REAL FightPhase pipeline (execute_action) and asserts:
#   1. get_unfought_eligible_units(player) lists only that player's units.
#   2. Active player's END_FIGHT forfeits only their own units; the opponent
#      stays eligible and the Fight step is handed over to them (no jump to
#      the Consolidate step, fight_selection_required re-emitted for them).
#   3. Once the opponent has also finished, END_FIGHT enters the Consolidate
#      step as before.
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

func _board(gs) -> void:
	# 40px = 1"; 25mm base radius ~19.7px. U_ORK (P1) engaged with U_PROS (P2)
	# at 60px edge-to-edge (~0.52"). Both are eligible to fight (Remaining
	# Combats — neither has Fights First). P1 is the active player.
	gs.state["units"] = {
		"U_ORK": {"id": "U_ORK", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Warbikers", "keywords": ["INFANTRY", "MOUNTED"], "stats": {"move": 12, "wounds": 3}},
			"models": [
				{"id": "w0", "alive": true, "wounds": 3, "current_wounds": 3, "base_mm": 25, "base_type": "circular", "position": {"x": 500, "y": 500}},
			]},
		"U_PROS": {"id": "U_PROS", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Prosecutors", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 2}},
			"models": [
				{"id": "p0", "alive": true, "wounds": 2, "current_wounds": 2, "base_mm": 25, "base_type": "circular", "position": {"x": 560, "y": 500}},
			]},
	}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 10

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
	_board(gs)
	pm.transition_to_phase(10)  # FIGHT
	var fp = pm.get_current_phase_instance()

	# Open the phase past the global Pile In step so the Fight step is running.
	fp.execute_action({"type": "END_PILE_IN", "player": 1})
	fp.execute_action({"type": "END_PILE_IN", "player": 2})
	_check("Fight step running", fp.pile_in_step_11e == fp.PileInStep11e.DONE)

	print("\n-- both units are owed a fight --")
	_check("Ork (P1) eligible", fp.sequencer_11e.eligible_to_fight("U_ORK", gs.state))
	_check("Prosecutors (P2) eligible", fp.sequencer_11e.eligible_to_fight("U_PROS", gs.state))

	print("\n-- get_unfought_eligible_units filters by player --")
	var all_unfought = fp.get_unfought_eligible_units()
	_check("no filter lists both units", all_unfought.size() == 2, str(all_unfought))
	var p1_unfought = fp.get_unfought_eligible_units(1)
	_check("player 1 filter lists only the Ork unit",
		p1_unfought.size() == 1 and p1_unfought[0].unit_id == "U_ORK", str(p1_unfought))
	var p2_unfought = fp.get_unfought_eligible_units(2)
	_check("player 2 filter lists only the Prosecutors",
		p2_unfought.size() == 1 and p2_unfought[0].unit_id == "U_PROS", str(p2_unfought))

	print("\n-- active player (P1) ends their fights: opponent still fights --")
	var r_end = fp.execute_action({"type": "END_FIGHT", "player": 1})
	_check("END_FIGHT succeeds", r_end.get("success", false), str(r_end))
	_check("Ork (P1) forfeited its own fight", not fp.sequencer_11e.eligible_to_fight("U_ORK", gs.state))
	_check("Prosecutors (P2) are STILL eligible (not forfeited)",
		fp.sequencer_11e.eligible_to_fight("U_PROS", gs.state))
	_check("phase did NOT jump to the Consolidate step",
		fp.consolidation_step_11e == fp.ConsolidationStep11e.NOT_STARTED,
		str(fp.consolidation_step_11e))
	_check("Fight step handed over to Player 2", fp.current_selecting_player == 2)
	_check("END_FIGHT re-opened fight selection for the opponent",
		r_end.get("trigger_fight_selection", false), str(r_end))
	var sel_data = r_end.get("fight_selection_data", {})
	_check("the opponent's selection offers the Prosecutors",
		sel_data.get("selecting_player", 0) == 2 and sel_data.get("eligible_units", {}).has("U_PROS"),
		str(sel_data))

	print("\n-- once the opponent has fought, END_FIGHT enters the Consolidate step --")
	# Simulate the opponent fighting their Prosecutors (flow-level attack
	# coverage lives in the windowed scenario; the bookkeeping is what matters).
	fp.sequencer_11e.mark_fought("U_PROS")
	var r_end2 = fp.execute_action({"type": "END_FIGHT", "player": 1})
	_check("second END_FIGHT succeeds", r_end2.get("success", false), str(r_end2))
	_check("Consolidate step now ACTIVE",
		fp.consolidation_step_11e == fp.ConsolidationStep11e.ACTIVE, str(fp.consolidation_step_11e))

	# Restore
	GameConstants.edition = prev_edition
	gs.state = prev_state
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
