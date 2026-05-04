extends SceneTree

# Test: RAPID INGRESS end-to-end via ri_pretrigger.w40ksave fixture
# Loads fixture, dispatches END_MOVEMENT, asserts on natural RI trigger emission
# from MovementPhase._continue_end_movement_after_grot_oiler.
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

	var cp_before = game_state.state["players"]["1"]["cp"]

	# Dispatch END_MOVEMENT — should fire RI trigger for P1 (defender)
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

	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
