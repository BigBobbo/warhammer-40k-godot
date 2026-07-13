extends SceneTree

# Regression: the AI must not attempt an ILLEGAL consolidation move that the
# 12.08 validator rejects, spamming the player's log with
# "consolidate failed — skipping movement" / "no movement (validation failed)".
#
# Reported bug: a unit killed the enemy it was fighting; there was no other enemy
# within 3" and no objective within 3", so per 12.08 it had NO legal
# consolidation move. But AIDecisionMaker._determine_ai_consolidate_mode returned
# OBJECTIVE whenever ANY objective existed anywhere on the board (and ENGAGEMENT
# for enemies up to 4" away), so the AI computed a 3" move toward an out-of-range
# objective. FightPhase._validate_consolidate_11e correctly rejected it (mode ""),
# the AI retried empty, and the player saw a scary "failed" for every such unit.
#
# The fix makes the AI defer to the authoritative ConsolidationMove.select_mode
# gate, so it holds position (empty movements) when no legal move exists — which
# validates as a clean no-op.
#
# Usage: godot --headless --path 40k -s tests/unit/test_ai_consolidate_no_illegal_move.gd

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

func _px(inches: float) -> float:
	return root.get_node("/root/Measurement").inches_to_px(inches)

func _unit(id: String, owner: int, x: float, y: float, alive := true) -> Dictionary:
	return {
		"id": id, "owner": owner, "status": 2,
		"flags": {"was_eligible_to_fight": true},
		"meta": {"name": id, "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 2}},
		"models": [
			{"id": "m1", "alive": alive, "wounds": 2, "current_wounds": (2 if alive else 0),
			 "base_mm": 32, "base_type": "circular", "position": {"x": x, "y": y}},
		]
	}

# Drive the real FightPhase to P2's half of the 12.07 Consolidate step so the
# validator (not a stub) judges the AI's action. In the live flow
# _begin_consolidation_step_11e stamps was_eligible_to_fight on every unit that
# fought; the phase transition clears that stamp, so re-apply it here for the
# P2 unit that (in the reported scenario) killed its enemy and so was eligible.
func _enter_p2_consolidate(fp, gs) -> void:
	fp.consolidation_step_11e = fp.ConsolidationStep11e.ACTIVE
	fp.consolidating_player_11e = 2
	fp.consolidation_done_players_11e = {}
	fp.units_that_consolidated_11e = {}
	for uid in gs.state["units"]:
		if int(gs.state["units"][uid].get("owner", 0)) == 2:
			gs.state["units"][uid]["flags"]["was_eligible_to_fight"] = true

func _run():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_ai_consolidate_no_illegal_move ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var ADM = load("res://scripts/AIDecisionMaker.gd")
	var MoveTypes = load("res://scripts/rules/movetypes/MoveTypes.gd")
	var tmpl = MoveTypes.get_type("consolidation")
	if gs == null or pm == null:
		_check("autoloads present", false); _finish(); return

	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11

	var bx := 1000.0
	var by := 1000.0

	# ---------------------------------------------------------------------
	# Scenario 1 (the bug): killed the only enemy, nearest objective 12" away.
	# ---------------------------------------------------------------------
	gs.state["units"] = {
		"AI_BOYZ": _unit("AI_BOYZ", 2, bx, by),
		"DEAD_FOE": _unit("DEAD_FOE", 1, bx + 40, by, false),  # wiped out
	}
	gs.state["board"] = {"objectives": [
		{"id": "FAR", "position": {"x": bx + _px(12.0), "y": by}}
	]}
	gs.state["meta"]["active_player"] = 2
	gs.state["meta"]["phase"] = 10
	gs.state["meta"]["battle_round"] = 2

	pm.transition_to_phase(10)
	var fp = pm.get_current_phase_instance()
	_enter_p2_consolidate(fp, gs)

	_check("precondition: no legal consolidation mode (nothing within 3\")",
		str(tmpl.select_mode("AI_BOYZ", gs.state).mode) == "",
		"mode=%s" % str(tmpl.select_mode("AI_BOYZ", gs.state).mode))

	var action = ADM._compute_consolidate_action(gs.state, "AI_BOYZ", 2)
	_check("FIX: AI holds position (empty movements) instead of moving toward the 12\" objective",
		action.get("movements", {}).is_empty(),
		"movements=%s desc=%s" % [str(action.get("movements")), str(action.get("_ai_description"))])

	# The action the AI actually submits must pass the real validator (no
	# "consolidate failed" churn). action.player is required by the phase.
	action["player"] = 2
	var res = fp.execute_action(action)
	_check("AI's consolidation action is ACCEPTED by FightPhase (no validation failure)",
		res.get("success", false), str(res))

	# ---------------------------------------------------------------------
	# Scenario 2 (control): objective genuinely within range -> AI still moves.
	# ---------------------------------------------------------------------
	gs.state["units"] = {
		"AI_BOYZ": _unit("AI_BOYZ", 2, bx, by),
		"DEAD_FOE": _unit("DEAD_FOE", 1, bx + 40, by, false),
	}
	gs.state["board"] = {"objectives": [
		{"id": "NEAR", "position": {"x": bx + _px(2.0), "y": by}}
	]}
	_enter_p2_consolidate(fp, gs)
	var mode2 = ADM._determine_ai_consolidate_mode(gs.state, gs.state["units"]["AI_BOYZ"], 2)
	_check("control: objective within 3\" -> AI still selects OBJECTIVE (valid consolidations unaffected)",
		mode2 == "OBJECTIVE", "mode=%s" % mode2)

	# ---------------------------------------------------------------------
	# Scenario 3 (control): live enemy within 3" -> AI engages (mandatory).
	# ---------------------------------------------------------------------
	gs.state["units"] = {
		"AI_BOYZ": _unit("AI_BOYZ", 2, bx, by),
		"LIVE_FOE": _unit("LIVE_FOE", 1, bx + _px(2.0), by, true),  # ~0.7" edge -> engaged
	}
	gs.state["board"] = {"objectives": []}
	_enter_p2_consolidate(fp, gs)
	var mode3 = ADM._determine_ai_consolidate_mode(gs.state, gs.state["units"]["AI_BOYZ"], 2)
	_check("control: enemy within 3\" -> AI selects ENGAGEMENT",
		mode3 == "ENGAGEMENT", "mode=%s" % mode3)

	GameConstants.edition = prev_edition
	gs.state = prev_state
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
