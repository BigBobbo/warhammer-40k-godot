extends SceneTree

# 11e 12.02-12.03 + 12.05/12.06 — the GLOBAL Pile In step and the distinct
# OVERRUN fight. At edition 11 the fight phase OPENS with the Pile In step:
# both players make pile-in moves with the eligible units they choose
# (active player first, one move per unit, optional per unit) BEFORE any
# unit is selected to fight. During the Fight step, a normal fight (12.05)
# gets NO pile-in; only an overrun fight (12.06 — unengaged, or engaged now
# but unengaged at the start of the Fight step) gets ONE additional pile-in
# move. Drives the REAL FightPhase action pipeline and asserts:
#   1. Phase entry activates the step (active player first) with the right
#      eligible lists (engaged + charged; not bystanders).
#   2. SELECT_FIGHTER is rejected while the step runs (12.02).
#   3. Wrong-half and second pile-ins are rejected; a legal 12.03 move
#      applies; a step pile-in that engages a new enemy makes it
#      fight-eligible (and stamps 12.08 consolidation eligibility).
#   4. Halves pass active -> opponent; both done -> fight selection begins.
#   5. Overrun: the mid-step-engaged unit is offered the additional
#      pile-in on selection; an engaged-from-start unit goes straight to
#      attack assignment.
#   6. Edition 10 unchanged (no step; per-activation pile-in intact).
#
# Usage: godot --headless --path . -s tests/test_global_pile_in_11e.gd

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

func _board() -> void:
	var gs = root.get_node("GameState")
	# 40px = 1"; 25mm base radius ~19.7px.
	# U_A (P1) engaged with U_B (P2): 60px apart (~0.52" edge).
	# U_C (P1) bystander far away.
	# U_E (P1) charged this turn, unengaged, ~2.49" edge from U_D (P2) —
	#   outside the 2" ER, inside the 5" pile-in target-select band.
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
	print("\n=== test_global_pile_in_11e ===\n")
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

	print("-- the fight phase opens with the Pile In step (12.02) --")
	_check("Pile In step is ACTIVE on phase entry",
		fp.pile_in_step_11e == fp.PileInStep11e.ACTIVE)
	_check("active player (1) piles in first (12.02)", fp.piling_in_player_11e == 1)
	var pending = fp.get_pending_pile_in_step_data()
	var pend_units = pending.get("eligible_units", {}).keys()
	_check("pending step data lists P1's engaged + charged units (not the bystander)",
		"U_A" in pend_units and "U_E" in pend_units and not ("U_C" in pend_units), str(pend_units))

	var sel = fp.validate_action({"type": "SELECT_FIGHTER", "unit_id": "U_A"})
	_check("SELECT_FIGHTER is rejected during the step (12.02)",
		not sel.valid and str(sel.errors).contains("12.02"), str(sel))

	print("\n-- 12.02/12.03: whose half, one move per unit, legal geometry --")
	var v_theirs = fp._validate_pile_in({"unit_id": "U_B", "movements": {}})
	_check("opponent's unit cannot pile in during P1's half", not v_theirs.valid, str(v_theirs))
	var r_a = fp.execute_action({"type": "PILE_IN", "unit_id": "U_A", "movements": {"0": Vector2(510, 500)}, "player": 1})
	_check("U_A's pile-in toward the engaged enemy succeeds", r_a.get("success", false), str(r_a))
	_check("U_A's model actually moved", gs.state["units"]["U_A"]["models"][0]["position"]["x"] == 510.0,
		str(gs.state["units"]["U_A"]["models"][0]["position"]))
	var v_again = fp._validate_pile_in({"unit_id": "U_A", "movements": {}})
	_check("second pile-in for U_A is rejected (one move per unit, 12.02)",
		not v_again.valid and str(v_again.errors).contains("12.02"), str(v_again))

	print("\n-- a step pile-in can engage a new enemy (charged unit, 5\" targets) --")
	var r_e = fp.execute_action({"type": "PILE_IN", "unit_id": "U_E", "movements": {"0": Vector2(860, 800)}, "player": 1})
	_check("charged U_E piles into U_D (5\" target select, 12.03)", r_e.get("success", false), str(r_e))
	_check("U_E is now engaged", root.get_node("RulesEngine").is_unit_engaged("U_E", gs.state))
	_check("newly-engaged U_D became fight-eligible (stamped for 12.08 too)",
		gs.state["units"]["U_D"].get("flags", {}).get("was_eligible_to_fight", false))

	print("\n-- halves pass active -> opponent; both done -> Fight step --")
	# Both of P1's eligible units have piled in, so the engine auto-passed
	# P1's half the moment U_E's move resolved.
	_check("P1 auto-passed once all their units piled in — step passed to Player 2",
		fp.pile_in_step_11e == fp.PileInStep11e.ACTIVE and fp.piling_in_player_11e == 2,
		"step=%s player=%d" % [str(fp.pile_in_step_11e), fp.piling_in_player_11e])
	var p2_eligible = fp._pile_in_eligible_units_11e(2)
	_check("P2's half offers U_B and the newly-engaged U_D", "U_B" in p2_eligible and "U_D" in p2_eligible, str(p2_eligible))
	var r_end2 = fp.execute_action({"type": "END_PILE_IN", "player": 2})
	_check("P2's END_PILE_IN succeeds", r_end2.get("success", false), str(r_end2))
	_check("Pile In step DONE — the Fight step begins", fp.pile_in_step_11e == fp.PileInStep11e.DONE)
	_check("fight selection was offered when the step finished",
		r_end2.get("trigger_fight_selection", false), str(r_end2))

	print("\n-- 12.06: overrun fight gets the additional pile-in; normal fight does not --")
	# U_E was UNENGAGED at the start of the Fight step snapshot (phase
	# entry) and became engaged via its step pile-in -> overrun-eligible.
	var r_sel_e = fp.execute_action({"type": "SELECT_FIGHTER", "unit_id": "U_E", "player": 1})
	_check("U_E selected to fight", r_sel_e.get("success", false), str(r_sel_e))
	_check("U_E's selection offers the overrun additional pile-in (12.06)",
		r_sel_e.get("trigger_pile_in", false), str(r_sel_e))
	_check("overrun flag stamped for the 12.03 template gate",
		gs.state["units"]["U_E"].get("flags", {}).get("selected_for_overrun_fight", false))
	var overrun_offers = []
	for a in fp.get_available_actions():
		overrun_offers.append(a.get("type", ""))
	_check("PILE_IN offered mid-activation only for the overrun unit", "PILE_IN" in overrun_offers, str(overrun_offers))
	var r_op = fp.execute_action({"type": "PILE_IN", "unit_id": "U_E", "movements": {}, "player": 1})
	_check("overrun pile-in (declined, empty) succeeds and moves on to attacks",
		r_op.get("success", false) and r_op.get("trigger_attack_assignment", false), str(r_op))
	var r_skip_e = fp.execute_action({"type": "SKIP_UNIT", "unit_id": "U_E", "player": 1})
	_check("U_E's activation skipped (attack flow covered windowed)", r_skip_e.get("success", false), str(r_skip_e))

	var r_sel_b = fp.execute_action({"type": "SELECT_FIGHTER", "unit_id": "U_B", "player": 2})
	_check("U_B selected to fight", r_sel_b.get("success", false), str(r_sel_b))
	_check("engaged-from-start U_B makes a NORMAL fight — no pile-in, straight to attack assignment (12.05)",
		r_sel_b.get("trigger_attack_assignment", false) and not r_sel_b.get("trigger_pile_in", false), str(r_sel_b))
	var normal_offers = []
	for a in fp.get_available_actions():
		normal_offers.append(a.get("type", ""))
	_check("no PILE_IN offered during a normal fight's activation", not ("PILE_IN" in normal_offers), str(normal_offers))

	print("\n-- 10e sensitivity: no step; per-activation pile-in intact --")
	GameConstants.edition = 10
	gs.state = prev_state.duplicate(true)
	_board()
	pm.transition_to_phase(10)
	var fp10 = pm.get_current_phase_instance()
	_check("e10: no Pile In step on entry", fp10.pile_in_step_11e == fp10.PileInStep11e.NOT_STARTED)
	# 10e selection order: the DEFENDING player picks first.
	var r10 = fp10.execute_action({"type": "SELECT_FIGHTER", "unit_id": "U_B"})
	_check("e10: SELECT_FIGHTER works immediately", r10.get("success", false), str(r10))
	_check("e10: selection still triggers the per-activation pile-in",
		r10.get("trigger_pile_in", false), str(r10))

	gs.state = prev_state
	GameConstants.edition = prev_edition
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
