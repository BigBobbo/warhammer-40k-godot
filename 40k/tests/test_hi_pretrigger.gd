extends SceneTree

# Test: HEROIC INTERVENTION end-to-end via hi_pretrigger.w40ksave fixture
# Loads fixture, drives the charge sequence, asserts on natural HI trigger emission
# from APPLY_CHARGE_MOVE and effect application.
#
# Usage: godot --headless --path . -s tests/test_hi_pretrigger.gd

const FIXTURE := "hi_pretrigger"

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
	print("\n=== test_hi_pretrigger ===\n")

	var save_mgr = root.get_node("SaveLoadManager")
	var game_state = root.get_node("GameState")
	var phase_mgr = root.get_node("PhaseManager")

	_check("Fixture load", save_mgr.load_game(FIXTURE))
	game_state.state["meta"]["from_save"] = true

	# Saved state: Phase=CHARGE, Warboss at (550, 100), Telemon at (491, 350).
	var warboss_pos = game_state.state["units"]["U_WARBOSS_B"]["models"][0].get("position")
	var telemon_pos = game_state.state["units"]["U_TELEMON_HEAVY_DREADNOUGHT_I"]["models"][0].get("position")
	_check("Warboss B at (550, 100)",
		warboss_pos != null and warboss_pos.x == 550 and warboss_pos.y == 100,
		"got %s" % str(warboss_pos))
	_check("Telemon at (491, 350)",
		telemon_pos != null and telemon_pos.x == 491 and telemon_pos.y == 350,
		"got %s" % str(telemon_pos))
	_check("Phase = CHARGE (9)",
		game_state.state["meta"].get("phase") == 9)
	_check("Active player = 2",
		game_state.state["meta"].get("active_player") == 2)

	phase_mgr.transition_to_phase(9)
	var phase = phase_mgr.get_current_phase_instance()
	_check("ChargePhase instance present",
		phase != null and phase.get_script().resource_path.ends_with("ChargePhase.gd"),
		"got %s" % (str(phase.get_script().resource_path) if phase else "null"))

	if phase == null:
		_finish()
		return

	var cp_before = game_state.state["players"]["1"]["cp"]

	# DECLARE_CHARGE
	phase.execute_action({
		"type": "DECLARE_CHARGE",
		"actor_unit_id": "U_WARBOSS_B",
		"payload": {"target_unit_ids": ["U_CUSTODIAN_GUARD_B"]}
	})
	# (Fire Overwatch is auto-declined by AI logic when no eligible shooter)

	phase.execute_action({"type": "CHARGE_ROLL", "actor_unit_id": "U_WARBOSS_B"})
	phase.execute_action({"type": "DECLINE_COMMAND_REROLL"})

	var apply_result = phase.execute_action({
		"type": "APPLY_CHARGE_MOVE",
		"actor_unit_id": "U_WARBOSS_B",
		"payload": {"per_model_paths": {"m1": [Vector2(550, 100), Vector2(503, 100)]}}
	})

	_check("APPLY_CHARGE_MOVE returned trigger_heroic_intervention",
		apply_result.get("trigger_heroic_intervention") == true,
		"result keys: %s" % str(apply_result.keys()))
	_check("heroic_intervention_player = 1",
		apply_result.get("heroic_intervention_player") == 1)

	var hi_eligible = apply_result.get("heroic_intervention_eligible_units", [])
	var has_telemon = false
	for u in hi_eligible:
		if u.get("unit_id") == "U_TELEMON_HEAVY_DREADNOUGHT_I":
			has_telemon = true
			break
	_check("Telemon listed as HI defender", has_telemon, "got %s" % str(hi_eligible))

	_check("ChargePhase.awaiting_heroic_intervention = true",
		phase.awaiting_heroic_intervention == true)

	# USE_HEROIC_INTERVENTION on Telemon
	var use_result = phase.execute_action({
		"type": "USE_HEROIC_INTERVENTION",
		"unit_id": "U_TELEMON_HEAVY_DREADNOUGHT_I",
		"player": 1
	})

	_check("USE_HEROIC_INTERVENTION succeeded",
		use_result.get("success") == true,
		"errors: %s" % str(use_result.get("errors", [])))

	var cp_after = game_state.state["players"]["1"]["cp"]
	_check("P1 CP -1 deducted (4→3)",
		cp_after == cp_before - 1,
		"before=%d after=%d" % [cp_before, cp_after])

	_check("HI charge dice rolled",
		use_result.get("dice", []).size() > 0,
		"got %s" % str(use_result.get("dice", [])))
	_check("heroic_intervention_unit_id set to Telemon",
		phase.heroic_intervention_unit_id == "U_TELEMON_HEAVY_DREADNOUGHT_I")

	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
