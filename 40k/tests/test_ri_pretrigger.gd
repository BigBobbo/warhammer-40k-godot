extends SceneTree

# Test: RAPID INGRESS end-to-end via ri_pretrigger.w40ksave fixture
# Loads fixture, dispatches END_MOVEMENT, asserts on natural RI trigger emission
# from MovementPhase._continue_end_movement_after_grot_oiler.
#
# 11e (migrated): RAPID INGRESS 15.07 — "WHEN: End of your opponent's Movement
# phase." The suite runs at edition 11 (set after the first frame, asserted).
# It used to fail 7 checks at 11e because rapid_ingress_11e was timed for the
# Shooting phase. The decline path then hands over to the movement_phase_end
# stratagem window (FIRE OVERWATCH 15.08) for the same non-active player.
#
# Usage: godot --headless --path . -s tests/test_ri_pretrigger.gd

const FIXTURE := "ri_pretrigger"

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
	print("\n=== test_ri_pretrigger ===\n")

	var save_mgr = root.get_node("SaveLoadManager")
	var game_state = root.get_node("GameState")
	var phase_mgr = root.get_node("PhaseManager")

	_check("Fixture load", save_mgr.load_game(FIXTURE))
	game_state.state["meta"]["from_save"] = true
	# Written AFTER the first frame + the load (SettingsService / the load
	# re-apply the boot edition).
	GameConstants.edition = 11
	_check("suite runs at edition 11", GameConstants.edition == 11, str(GameConstants.edition))

	_check("Phase = MOVEMENT (7)",
		game_state.state["meta"].get("phase") == 7)
	_check("Active player = 2",
		game_state.state["meta"].get("active_player") == 2)
	_check("Battle round = 2",
		game_state.state["meta"].get("battle_round") == 2)

	# Caladius should be in reserves (from baseline_postdeploy)
	_check("Caladius in reserves",
		game_state.state["units"]["U_CALADIUS_GRAV-TANK_E"].get("status") == 7,
		"got status=%s" % str(game_state.state["units"]["U_CALADIUS_GRAV-TANK_E"].get("status")))

	phase_mgr.transition_to_phase(7)
	var phase = phase_mgr.get_current_phase_instance()
	_check("MovementPhase instance present",
		phase != null and phase.get_script().resource_path.ends_with("MovementPhase.gd"),
		"got %s" % (str(phase.get_script().resource_path) if phase else "null"))

	if phase == null:
		_finish()
		return
	_decline_movement_start_windows(phase)

	var cp_before = game_state.state["players"]["1"]["cp"]

	# Dispatch END_MOVEMENT — should fire RI trigger for P1 (defender)
	# Edition-neutral: both editions offer RAPID INGRESS here — 10e "End of your
	# opponent's Movement phase." and 11e 15.07 "WHEN: End of your opponent's
	# Movement phase." (docs/rules/40k_11th_edition_core_rules.txt). Round 2, so
	# the 11e restriction "cannot use this stratagem during the first battle
	# round" does not apply, and the Caladius (VEHICLE, not AIRCRAFT) is in
	# strategic reserves (11e TARGET: "in strategic reserves (excluding AIRCRAFT)").
	var end_result = phase.execute_action({"type": "END_MOVEMENT"})

	_check("END_MOVEMENT returned trigger_rapid_ingress",
		end_result.get("trigger_rapid_ingress") == true,
		"result keys: %s" % str(end_result.keys()))
	_check("rapid_ingress_player = 1",
		end_result.get("rapid_ingress_player") == 1)

	var ri_eligible = end_result.get("rapid_ingress_eligible_units", [])
	var has_caladius = false
	for u in ri_eligible:
		if u.get("unit_id") == "U_CALADIUS_GRAV-TANK_E":
			has_caladius = true
			break
	_check("Caladius listed as RI eligible reserve",
		has_caladius, "got %s" % str(ri_eligible))

	_check("MovementPhase._awaiting_rapid_ingress = true",
		phase._awaiting_rapid_ingress == true)

	# USE_RAPID_INGRESS on Caladius
	var use_result = phase.execute_action({
		"type": "USE_RAPID_INGRESS",
		"unit_id": "U_CALADIUS_GRAV-TANK_E",
		"player": 1
	})

	_check("USE_RAPID_INGRESS succeeded",
		use_result.get("success") == true,
		"errors: %s" % str(use_result.get("errors", [])))

	var cp_after = game_state.state["players"]["1"]["cp"]
	_check("P1 CP -1 deducted",
		cp_after == cp_before - 1,
		"before=%d after=%d" % [cp_before, cp_after])

	_check("_rapid_ingress_unit_id = Caladius",
		phase._rapid_ingress_unit_id == "U_CALADIUS_GRAV-TANK_E")
	_check("_awaiting_rapid_ingress cleared",
		phase._awaiting_rapid_ingress == false)
	_check("the phase still holds for the placement (no force-complete online)",
		phase.has_pending_end_of_phase_prompt() and game_state.get_current_phase() == 7)

	# Decline path: the end-of-Movement stratagem window follows.
	_check("Fixture reload (decline path)", save_mgr.load_game(FIXTURE))
	GameConstants.edition = 11
	phase_mgr.transition_to_phase(7)
	phase = phase_mgr.get_current_phase_instance()
	_decline_movement_start_windows(phase)
	var end2 = phase.execute_action({"type": "END_MOVEMENT"})
	_check("decline path: RAPID INGRESS offered again", end2.get("trigger_rapid_ingress") == true)
	var dec = phase.execute_action({"type": "DECLINE_RAPID_INGRESS", "player": 1})
	_check("DECLINE_RAPID_INGRESS succeeded", dec.get("success") == true, str(dec.get("error", "")))
	_check("no CP spent on the decline", game_state.state["players"]["1"]["cp"] == cp_before,
		"before=%d after=%d" % [cp_before, game_state.state["players"]["1"]["cp"]])
	_check("the prompt is closed", not phase.has_pending_end_of_phase_prompt())
	var still_movement: bool = game_state.get_current_phase() == 7
	var window_open: bool = phase.has_pending_stratagem_window()
	_check("…the phase then either waits on a movement_phase_end window or has ended",
		(still_movement and window_open) or game_state.get_current_phase() == 8,
		"phase=%d window=%s" % [game_state.get_current_phase(), str(window_open)])

	_finish()

## Codex: Orks (11e): the fixture's Weirdboy offers Da Jump in the Orks'
## movement_phase_start window (WP-O34/WP-O6), which holds the phase until
## answered — the same window the windowed scenarios on this fixture decline
## (RETIRED_TESTS.md, WP-O6). Decline only start-of-Movement windows, so the
## end-of-phase RAPID INGRESS flow under test is untouched.
func _decline_movement_start_windows(phase) -> void:
	var declined: Array = []
	for _i in range(4):
		if phase == null or not phase.has_pending_stratagem_window():
			break
		var w: Dictionary = phase.get_pending_stratagem_window()
		if str(w.get("window_id", "")) != "movement_phase_start":
			break
		declined.append("P%d %s" % [int(w.get("player", 0)), str(w.get("window_id", ""))])
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.get("player", 1)), "window_id": str(w.get("window_id", ""))})
	print("test_ri_pretrigger: declined start-of-Movement window(s): %s" % str(declined))
	_check("no stratagem window pending before END_MOVEMENT", phase != null and not phase.has_pending_stratagem_window(),
		str(phase.get_pending_stratagem_window() if phase != null and phase.has_pending_stratagem_window() else {}))

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
