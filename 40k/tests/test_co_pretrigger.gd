extends SceneTree

# Test: COUNTER-OFFENSIVE end-to-end via co_pretrigger.w40ksave fixture
# Loads the fixture, drives the fight sequence, asserts on natural trigger emission
# and effect application.
#
# Usage: godot --headless --path . -s tests/test_co_pretrigger.gd

const FIXTURE := "co_pretrigger"

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
	# Defer the actual test until autoloads have run their _ready (next idle frame).
	root.connect("ready", Callable(self, "_run_tests"))
	# Belt-and-suspenders: also call after one process tick.
	create_timer(0.1).timeout.connect(_run_tests)

func _run_tests():
	if passed > 0 or failed > 0:
		return  # already ran
	print("\n=== test_co_pretrigger ===\n")

	var save_mgr = root.get_node("SaveLoadManager")
	var game_state = root.get_node("GameState")
	var phase_mgr = root.get_node("PhaseManager")

	# 1) Load fixture
	_check("Fixture load",
		save_mgr.load_game(FIXTURE),
		"SaveLoadManager.load_game returned false")
	game_state.state["meta"]["from_save"] = true

	# 2) Verify saved positions + phase state
	var warboss_pos = game_state.state["units"]["U_WARBOSS_B"]["models"][0].get("position")
	_check("Warboss B at (503, 100)",
		warboss_pos != null and warboss_pos.x == 503 and warboss_pos.y == 100,
		"got %s" % str(warboss_pos))

	_check("Phase = FIGHT (10)",
		game_state.state["meta"].get("phase") == 10)
	_check("Active player = 2",
		game_state.state["meta"].get("active_player") == 2)
	_check("Warboss flagged charged_this_turn",
		game_state.state["units"]["U_WARBOSS_B"]["flags"].get("charged_this_turn") == true)

	# 3) Make sure the FightPhase instance is current
	if phase_mgr.has_method("transition_to_phase"):
		phase_mgr.transition_to_phase(10)

	var phase = phase_mgr.get_current_phase_instance()
	_check("FightPhase instance present",
		phase != null and phase.get_script().resource_path.ends_with("FightPhase.gd"),
		"got %s" % (str(phase.get_script().resource_path) if phase else "null"))

	if phase == null:
		print("Aborting — no phase instance")
		_finish()
		return

	# 4) Drive SELECT_FIGHTER → DECLINE_EPIC_CHALLENGE → CONSOLIDATE
	var cp_before = game_state.state["players"]["1"]["cp"]

	phase.execute_action({"type": "SELECT_FIGHTER", "unit_id": "U_WARBOSS_B"})
	phase.execute_action({"type": "DECLINE_EPIC_CHALLENGE"})
	phase.execute_action({"type": "PILE_IN", "unit_id": "U_WARBOSS_B", "actor_unit_id": "U_WARBOSS_B", "payload": {"per_model_paths": {}}})
	var consolidate_result = phase.execute_action({"type": "CONSOLIDATE", "unit_id": "U_WARBOSS_B", "actor_unit_id": "U_WARBOSS_B"})

	# 5) Assert natural trigger emission
	_check("CONSOLIDATE returned trigger_counter_offensive",
		consolidate_result.get("trigger_counter_offensive") == true)
	_check("counter_offensive_player = 1",
		consolidate_result.get("counter_offensive_player") == 1)

	var eligible = consolidate_result.get("counter_offensive_eligible_units", [])
	var has_custodian_guard = false
	for u in eligible:
		if u.get("unit_id") == "U_CUSTODIAN_GUARD_B":
			has_custodian_guard = true
			break
	_check("Custodian Guard listed as eligible defender",
		has_custodian_guard,
		"got %s" % str(eligible))

	_check("FightPhase.awaiting_counter_offensive = true",
		phase.awaiting_counter_offensive == true)

	# 6) Drive USE_COUNTER_OFFENSIVE
	var use_result = phase.execute_action({
		"type": "USE_COUNTER_OFFENSIVE",
		"unit_id": "U_CUSTODIAN_GUARD_B",
		"player": 1
	})

	_check("USE_COUNTER_OFFENSIVE succeeded",
		use_result.get("success") == true,
		"errors: %s" % str(use_result.get("errors", [])))

	var cp_after = game_state.state["players"]["1"]["cp"]
	_check("P1 CP -2 deducted (4→2)",
		cp_after == cp_before - 2,
		"before=%d after=%d" % [cp_before, cp_after])

	_check("active_fighter_id switched to Custodian Guard",
		phase.active_fighter_id == "U_CUSTODIAN_GUARD_B")
	_check("current_selecting_player = 1",
		phase.current_selecting_player == 1)
	_check("awaiting_counter_offensive cleared",
		phase.awaiting_counter_offensive == false)

	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
