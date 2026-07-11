extends SceneTree

# Test: the AI main loop must never answer a reactive charge-phase window
# (Heroic Intervention / Fire Overwatch) that belongs to a HUMAN player — and
# must answer it AS the owning player when that owner is an AI.
#
# Regression net for the 2026-07-11 report ("P2 AI: Heroic Intervention with
# Stompa" — the Stompa belonged to the human): at the end of the AI's (P2)
# Charge phase the 11e 15.11 HI window opened for the HUMAN defender (P1).
# AIPlayer's main loop picked the window's USE/DECLINE actions out of
# get_available_actions(), evaluated them with the HUMAN's units, submitted
# USE as P2 (validation-rejected), then force-DECLINED the human's window —
# robbing the player of the reaction ~1s after the dialog opened.
#
# The windowed validation is tests/scenarios/sp/hi_window_ai_must_not_hijack_11e.json;
# this headless test is the fast regression net for the same guard.
#
# Usage: godot --headless --path . -s tests/test_ai_reactive_window_guard.gd

const FIXTURE := "hi_pretrigger"
const AIDifficultyConfigData = preload("res://scripts/AIDifficultyConfig.gd")

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

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_ai_reactive_window_guard ===\n")

	var save_mgr = root.get_node("SaveLoadManager")
	var game_state = root.get_node("GameState")
	var phase_mgr = root.get_node("PhaseManager")
	var ai = root.get_node("AIPlayer")

	_check("Fixture load", save_mgr.load_game(FIXTURE))
	game_state.state["meta"]["from_save"] = true
	GameConstants.edition = 11
	root.get_node("RulesEngine").set_test_seed(42)

	phase_mgr.transition_to_phase(9)
	var phase = phase_mgr.get_current_phase_instance()
	_check("ChargePhase instance present",
		phase != null and phase.get_script().resource_path.ends_with("ChargePhase.gd"))
	if phase == null:
		_finish()
		return

	_check("Active player = 2 (the would-be AI)",
		game_state.get_active_player() == 2)

	# END_CHARGE opens the 11e end-of-phase HI window for the DEFENDER (P1).
	var result = phase.execute_action({"type": "END_CHARGE", "player": 2})
	_check("END_CHARGE accepted", result.get("success", false))
	_check("HI window opened for player 1",
		phase.awaiting_heroic_intervention and int(phase.heroic_intervention_player) == 1,
		"awaiting=%s player=%s" % [phase.awaiting_heroic_intervention, phase.heroic_intervention_player])

	var p1_cp_before = game_state.state["players"]["1"]["cp"]
	var p2_cp_before = game_state.state["players"]["2"]["cp"]

	# --- Case 1: window owner is HUMAN — the AI loop must idle ---
	ai.configure({1: "HUMAN", 2: "AI"})
	_check("Helper reports the window owner",
		int(ai._get_pending_reactive_window_player()) == 1)

	ai._evaluate_and_act()

	_check("Human's HI window NOT hijacked (still awaiting)",
		phase.awaiting_heroic_intervention)
	_check("Window still belongs to player 1",
		int(phase.heroic_intervention_player) == 1)
	_check("P1 CP untouched",
		game_state.state["players"]["1"]["cp"] == p1_cp_before)
	_check("P2 CP untouched",
		game_state.state["players"]["2"]["cp"] == p2_cp_before)

	# --- Case 2: the decision maker refuses mismatched windows outright ---
	var snapshot = game_state.create_snapshot()
	var hijack_actions = [
		{"type": "USE_HEROIC_INTERVENTION", "player": 1, "charging_unit_id": "", "description": "Use Heroic Intervention"},
		{"type": "DECLINE_HEROIC_INTERVENTION", "player": 1, "description": "Decline Heroic Intervention"},
	]
	var decision = AIDecisionMaker.decide(
		GameStateData.Phase.CHARGE, snapshot, hijack_actions, 2,
		AIDifficultyConfigData.Difficulty.NORMAL)
	_check("decide() as P2 refuses P1's HI window (empty decision)",
		decision.is_empty(), "got %s" % str(decision))

	var ow_actions = [
		{"type": "DECLINE_FIRE_OVERWATCH", "player": 1, "description": "Decline Fire Overwatch"},
	]
	var ow_decision = AIDecisionMaker.decide(
		GameStateData.Phase.CHARGE, snapshot, ow_actions, 2,
		AIDifficultyConfigData.Difficulty.NORMAL)
	_check("decide() as P2 refuses P1's Overwatch window (empty decision)",
		ow_decision.is_empty(), "got %s" % str(ow_decision))

	# --- Case 3: window owner is an AI — the loop answers AS that player ---
	ai.configure({1: "AI", 2: "AI"})
	ai._evaluate_and_act()

	_check("AI defender's window resolved (no longer awaiting)",
		not phase.awaiting_heroic_intervention)
	_check("P2 (active player) CP untouched by P1's window",
		game_state.state["players"]["2"]["cp"] == p2_cp_before)
	if phase.heroic_intervention_unit_id != "":
		var hi_unit = game_state.state["units"].get(phase.heroic_intervention_unit_id, {})
		_check("HI unit (if used) belongs to the window owner P1",
			int(hi_unit.get("owner", 0)) == 1,
			"unit=%s owner=%s" % [phase.heroic_intervention_unit_id, hi_unit.get("owner")])
		_check("P1 paid the 1 CP for its own Heroic Intervention",
			game_state.state["players"]["1"]["cp"] == p1_cp_before - 1)
	else:
		# Either declined (no CP) or used-and-failed-the-roll (CP already
		# paid — rules-correct). The invariant: only P1's CP may move.
		var p1_cp_now = game_state.state["players"]["1"]["cp"]
		_check("P1's window resolved at P1's expense only",
			p1_cp_now == p1_cp_before or p1_cp_now == p1_cp_before - 1,
			"p1 cp %s -> %s" % [p1_cp_before, p1_cp_now])

	ai.configure({1: "HUMAN", 2: "HUMAN"})
	_finish()

func _finish():
	print("\n=== %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
