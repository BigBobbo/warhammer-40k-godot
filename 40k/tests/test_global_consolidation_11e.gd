extends SceneTree

# 11e 12.07-12.08 — the GLOBAL Consolidate step. At edition 11 consolidation
# is no longer the tail of a unit's activation: after ALL fighting, both
# players make consolidation moves with the eligible units they choose
# (active player first, one move per unit, optional per unit), and an
# Engaging Consolidation that tags unfought enemies forces them to fight
# (12.08 AFTER MOVING) before the step continues. Drives the REAL
# FightPhase action pipeline (execute_action) and asserts:
#   1. flags.was_eligible_to_fight is stamped in production (engaged /
#      charged units yes; bystanders no).
#   2. CONSOLIDATE during the Fight step is rejected (12.07).
#   3. END_FIGHT enters the Consolidate step (active player first) instead
#      of completing the phase.
#   4. One consolidation move per unit (12.07): second CONSOLIDATE rejected.
#   5. Engaging Consolidation into an unfought enemy forces it to fight
#      (12.08); consolidation/END_CONSOLIDATION are blocked meanwhile.
#   6. After the forced fight resolves, the step resumes; halves pass
#      active player -> opponent; dead units are not offered.
#   7. END_CONSOLIDATION by the second player completes the phase (via the
#      end-of-fight-phase triggers).
#   8. 10e sensitivity: the legacy per-fighter consolidate flow unchanged.
#
# Usage: godot --headless --path . -s tests/test_global_consolidation_11e.gd

var passed := 0
var failed := 0
var _phase_completed_count := 0
var _step_at_completion := -1

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
	# Single-model 25mm units. 40px = 1"; 25mm base radius ~19.7px.
	# U_A (P1) at 500,500 engaged with U_B (P2) at 560,500  (edge ~0.52")
	# U_C (P1) bystander far away — never eligible to fight.
	# U_E (P1) charged this turn but unengaged, 139px (~2.49" edge) from
	#          U_D (P2) — inside the 3" engaging-consolidation band but
	#          outside the 2" engagement range.
	# U_D (P2) unengaged, never fights — until U_E's engaging consolidation
	#          tags it (12.08 forced fight).
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
		"U_C": {"id": "U_C", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Bystanders", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [
				{"id": "c0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 25, "base_type": "circular", "position": {"x": 200, "y": 200}},
			]},
		"U_E": {"id": "U_E", "owner": 1, "status": 2, "flags": {"charged_this_turn": true},
			"meta": {"name": "Chargers", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [
				{"id": "g0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 25, "base_type": "circular", "position": {"x": 800, "y": 800}},
			]},
		"U_D": {"id": "U_D", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Loiterers", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [
				{"id": "d0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 25, "base_type": "circular", "position": {"x": 939, "y": 800}},
			]},
	}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 10

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_global_consolidation_11e ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	if gs == null or pm == null:
		_check("autoloads", false); _finish(); return
	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition

	GameConstants.edition = 11
	_board()
	pm.transition_to_phase(10)  # FIGHT
	var fp = pm.get_current_phase_instance()

	# The phase now OPENS with the global Pile In step (12.02) — pass both
	# halves so the Fight step begins (pile-in coverage lives in
	# test_global_pile_in_11e).
	fp.execute_action({"type": "END_PILE_IN", "player": 1})
	fp.execute_action({"type": "END_PILE_IN", "player": 2})
	_check("Pile In step passed — Fight step running", fp.pile_in_step_11e == fp.PileInStep11e.DONE)

	print("-- 12.08 eligibility stamps (was_eligible_to_fight) --")
	var u = gs.state["units"]
	_check("engaged unit U_A stamped", u["U_A"].get("flags", {}).get("was_eligible_to_fight", false))
	_check("engaged enemy U_B stamped", u["U_B"].get("flags", {}).get("was_eligible_to_fight", false))
	_check("unengaged charger U_E stamped", u["U_E"].get("flags", {}).get("was_eligible_to_fight", false))
	_check("bystander U_C NOT stamped", not u["U_C"].get("flags", {}).get("was_eligible_to_fight", false))
	_check("loiterer U_D NOT stamped (yet)", not u["U_D"].get("flags", {}).get("was_eligible_to_fight", false))

	print("\n-- CONSOLIDATE is rejected during the Fight step (12.07) --")
	var v_early = fp._validate_consolidate({"unit_id": "U_A", "movements": {}})
	_check("consolidate before the Consolidate step is rejected with a 12.07 reason",
		not v_early.valid and str(v_early.errors).contains("12.07"), str(v_early))

	print("\n-- END_FIGHT enters the Consolidate step (active player first) --")
	# All owed fights resolved (flow-level attack coverage lives in the
	# windowed scenario; here the sequencer bookkeeping is what matters).
	fp.sequencer_11e.mark_fought("U_A")
	fp.sequencer_11e.mark_fought("U_B")
	fp.sequencer_11e.mark_fought("U_E")
	var offered = []
	for a in fp.get_available_actions():
		offered.append(a.get("type", ""))
	_check("END_FIGHT offered once the sequencer reports the fight step done", "END_FIGHT" in offered, str(offered))

	var r_end = fp.execute_action({"type": "END_FIGHT", "player": 1})
	_check("END_FIGHT succeeds", r_end.get("success", false), str(r_end))
	_check("Consolidate step is ACTIVE (phase did not complete)",
		fp.consolidation_step_11e == fp.ConsolidationStep11e.ACTIVE)
	_check("active player (1) consolidates first (12.07)", fp.consolidating_player_11e == 1)
	_check("END_FIGHT result carries the consolidation-selection trigger",
		r_end.get("trigger_consolidation_selection", false), str(r_end))
	var data = r_end.get("consolidation_selection_data", {})
	var data_units = data.get("eligible_units", {}).keys()
	_check("P1's eligible units are U_A and U_E (not bystander U_C)",
		"U_A" in data_units and "U_E" in data_units and not ("U_C" in data_units), str(data_units))

	var step_offers = fp.get_available_actions()
	var step_types = {}
	for a in step_offers:
		step_types[a.get("type", "")] = step_types.get(a.get("type", ""), 0) + 1
	_check("step offers one CONSOLIDATE per eligible unit + END_CONSOLIDATION",
		step_types.get("CONSOLIDATE", 0) == 2 and step_types.get("END_CONSOLIDATION", 0) == 1, str(step_types))
	_check("END_FIGHT is not offered during the step", not step_types.has("END_FIGHT"), str(step_types))

	print("\n-- one consolidation move per unit (12.07) --")
	var r_a = fp.execute_action({"type": "CONSOLIDATE", "unit_id": "U_A", "movements": {"0": Vector2(518, 500)}, "player": 1})
	_check("U_A's ongoing consolidation toward the engaged enemy succeeds", r_a.get("success", false), str(r_a))
	_check("U_A's model actually moved", gs.state["units"]["U_A"]["models"][0]["position"]["x"] == 518.0,
		str(gs.state["units"]["U_A"]["models"][0]["position"]))
	var v_again = fp._validate_consolidate({"unit_id": "U_A", "movements": {}})
	_check("second consolidation for U_A is rejected (one move per unit, 12.07)",
		not v_again.valid and str(v_again.errors).contains("12.07"), str(v_again))
	var v_theirs = fp._validate_consolidate({"unit_id": "U_B", "movements": {}})
	_check("opponent's unit cannot consolidate during P1's half",
		not v_theirs.valid, str(v_theirs))

	print("\n-- Engaging Consolidation forces the tagged enemy to fight (12.08) --")
	var r_e = fp.execute_action({"type": "CONSOLIDATE", "unit_id": "U_E", "movements": {"0": Vector2(860, 800)}, "player": 1})
	_check("U_E's engaging consolidation into U_D succeeds", r_e.get("success", false), str(r_e))
	_check("forced fight triggered (fight selection re-opened for the opponent)",
		r_e.get("trigger_fight_selection", false) and r_e.get("forced_by_consolidation", false), str(r_e))
	_check("U_D became eligible (stamped) by being tagged",
		u["U_D"].get("flags", {}).get("was_eligible_to_fight", false))
	_check("forced fights pending", fp._forced_fights_pending_11e())
	var v_mid = fp._validate_consolidate({"unit_id": "U_B", "movements": {}})
	_check("consolidation is blocked while the forced fight is unresolved (12.08)",
		not v_mid.valid and str(v_mid.errors).contains("12.08"), str(v_mid))
	var v_pass_mid = fp._validate_end_consolidation({"type": "END_CONSOLIDATION", "player": 1})
	_check("END_CONSOLIDATION is blocked while the forced fight is unresolved (12.08)",
		not v_pass_mid.valid and str(v_pass_mid.errors).contains("12.08"), str(v_pass_mid))

	# Resolve the forced fight (skip = forfeits its attacks but completes
	# the selection; the windowed scenario covers a real forced attack).
	var r_skip = fp.execute_action({"type": "SKIP_UNIT", "unit_id": "U_D", "player": 2})
	_check("forced unit's fight resolves (skipped)", r_skip.get("success", false), str(r_skip))
	_check("step resumed and passed to Player 2 (P1 had no units left)",
		fp.consolidation_step_11e == fp.ConsolidationStep11e.ACTIVE and fp.consolidating_player_11e == 2,
		"step=%s player=%d" % [str(fp.consolidation_step_11e), fp.consolidating_player_11e])
	var p2_units = fp._consolidation_eligible_units_11e(2)
	_check("P2's half offers U_B and the newly-tagged U_D", "U_B" in p2_units and "U_D" in p2_units, str(p2_units))

	print("\n-- dead units are not offered --")
	gs.state["units"]["U_B"]["models"][0]["alive"] = false
	var p2_after = fp._consolidation_eligible_units_11e(2)
	_check("destroyed U_B disappears from the eligible list", not ("U_B" in p2_after) and "U_D" in p2_after, str(p2_after))

	print("\n-- END_CONSOLIDATION completes the step and the phase --")
	fp.phase_completed.connect(func():
		_phase_completed_count += 1
		_step_at_completion = fp.consolidation_step_11e
	)
	var r_pass = fp.execute_action({"type": "END_CONSOLIDATION", "player": 2})
	_check("P2's END_CONSOLIDATION succeeds", r_pass.get("success", false), str(r_pass))
	_check("phase completed after both halves", _phase_completed_count == 1)
	_check("Consolidate step was DONE at completion", _step_at_completion == fp.ConsolidationStep11e.DONE)

	print("\n-- 10e sensitivity: legacy per-fighter consolidate flow unchanged --")
	GameConstants.edition = 10
	gs.state = prev_state.duplicate(true)
	_board()
	pm.transition_to_phase(10)
	var fp10 = pm.get_current_phase_instance()
	fp10.active_fighter_id = "U_A"
	fp10.pending_attacks.clear()
	var v10 = fp10._validate_consolidate({"unit_id": "U_A", "movements": {}})
	_check("e10: active fighter's empty consolidate is accepted mid-activation (legacy flow)",
		v10.valid, str(v10))
	var offered10 = []
	for a in fp10.get_available_actions():
		offered10.append(a.get("type", ""))
	_check("e10: per-fighter CONSOLIDATE still offered for the active fighter", "CONSOLIDATE" in offered10, str(offered10))

	gs.state = prev_state
	GameConstants.edition = prev_edition
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
