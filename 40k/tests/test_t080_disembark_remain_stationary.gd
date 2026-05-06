extends SceneTree

# T-080: Disembarked units choosing Remain Stationary must NOT receive the Heavy
# weapon bonus. Per 10e, disembarking counts as movement for the purposes of
# Remained Stationary, so picking RS shouldn't qualify the unit for Heavy bonus.
#
# Already implemented as T3-15: `_process_remain_stationary` reads
# `disembarked_this_phase` and stores `flags.remained_stationary = not
# is_disembarked`. This test pins the behaviour.
#
# Usage: godot --headless --path . -s tests/test_t080_disembark_remain_stationary.gd

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
	print("\n=== test_t080_disembark_remain_stationary ===\n")
	_test_disembarked_rs_no_heavy_bonus()
	_test_normal_rs_grants_remained_stationary()
	_finish()

func _setup_state(disembarked: bool) -> void:
	var gs = root.get_node("GameState")
	gs.state = {
		"meta": {"phase": GameStateData.Phase.MOVEMENT, "active_player": 1, "battle_round": 1, "turn_number": 1},
		"units": {
			"U_TROOP": {
				"id": "U_TROOP", "owner": 1,
				"status": GameStateData.UnitStatus.DEPLOYED,
				"flags": {},
				"meta": {"name": "Troop", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
				"models": [{"id": "m1", "alive": true, "current_wounds": 1, "wounds": 1, "position": {"x": 0, "y": 0}}],
				"disembarked_this_phase": disembarked,
			},
		},
		"players": {"1": {"cp": 3, "vp": 0}, "2": {"cp": 3, "vp": 0}},
	}

func _test_disembarked_rs_no_heavy_bonus() -> void:
	print("\n-- T-080a: Disembarked unit Remain Stationary → remained_stationary=false --")
	_setup_state(true)
	var phase = load("res://phases/MovementPhase.gd").new()
	phase.game_state_snapshot = root.get_node("GameState").state
	var result = phase._process_remain_stationary({"actor_unit_id": "U_TROOP"})
	_check("Action returns success", result.get("success", false))

	# Find the change to remained_stationary
	var found_value = null
	for change in result.get("changes", []):
		if str(change.get("path", "")).ends_with("flags.remained_stationary"):
			found_value = change.get("value")
			break
	_check("remained_stationary set to false (Heavy bonus blocked)",
		found_value == false, "got %s" % str(found_value))
	phase.queue_free()

func _test_normal_rs_grants_remained_stationary() -> void:
	print("\n-- T-080b: Non-disembarked unit Remain Stationary → remained_stationary=true (Heavy OK) --")
	_setup_state(false)
	var phase = load("res://phases/MovementPhase.gd").new()
	phase.game_state_snapshot = root.get_node("GameState").state
	var result = phase._process_remain_stationary({"actor_unit_id": "U_TROOP"})
	_check("Action returns success", result.get("success", false))

	var found_value = null
	for change in result.get("changes", []):
		if str(change.get("path", "")).ends_with("flags.remained_stationary"):
			found_value = change.get("value")
			break
	_check("remained_stationary set to true (Heavy bonus permitted)",
		found_value == true, "got %s" % str(found_value))
	phase.queue_free()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
