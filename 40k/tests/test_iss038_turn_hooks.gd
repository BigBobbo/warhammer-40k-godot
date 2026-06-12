extends SceneTree

# ISS-038: 11e battle-round / turn step events (core rules 07).
#
# Checks:
#   A) End-of-turn hooks run in 07.03 order (non-mission before mission,
#      registration order within class) before the switch, and turn_ending
#      fires after them.
#   B) Driving ScoringPhase END_TURN runs the hooks and, for player 2,
#      emits battle_round_ending and advances the round.
#   C) Entering COMMAND emits turn_started (and battle_round_started once
#      per round).
#
# Usage: godot --headless --path . -s tests/test_iss038_turn_hooks.gd

var passed := 0
var failed := 0
var events: Array = []

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
	print("\n=== test_iss038_turn_hooks ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var prev = gs.state.duplicate(true)
	gs.initialize_default_state()
	gs.state["meta"]["active_player"] = 2
	gs.state["meta"]["battle_round"] = 1

	print("-- A: hook ordering (07.03) --")
	var mission_cb = func(p): events.append("mission")
	var rule_cb = func(p): events.append("rule")
	var rule2_cb = func(p): events.append("rule2")
	pm.register_turn_ending_hook(mission_cb, true)   # registered FIRST but mission
	pm.register_turn_ending_hook(rule_cb, false)
	pm.register_turn_ending_hook(rule2_cb, false)
	pm.turn_ending.connect(func(p): events.append("signal:%d" % p))
	pm.battle_round_ending.connect(func(r): events.append("round_ending:%d" % r))
	pm.run_turn_ending_hooks(2)
	_check("non-mission rules run before mission rules, then signal",
		events == ["rule", "rule2", "mission", "signal:2"], str(events))

	print("\n-- B: ScoringPhase END_TURN drives the boundary --")
	events.clear()
	var phase = load("res://phases/ScoringPhase.gd").new()
	root.add_child(phase)
	phase.game_state_snapshot = gs.create_snapshot()
	var result = phase.execute_action({"type": "END_TURN", "player": 2})
	_check("END_TURN succeeded", result.get("success", false), str(result))
	_check("hooks + round_ending fired in order",
		events == ["rule", "rule2", "mission", "signal:2", "round_ending:1"], str(events))
	_check("battle round advanced", gs.get_battle_round() == 2)
	_check("active player switched to 1", gs.get_active_player() == 1)
	root.remove_child(phase)
	phase.free()

	print("\n-- C: COMMAND entry emits turn/round started --")
	events.clear()
	pm.turn_started.connect(func(p): events.append("turn_started:%d" % p))
	pm.battle_round_started.connect(func(r): events.append("round_started:%d" % r))
	pm.transition_to_phase(6)  # COMMAND
	_check("round_started then turn_started on first COMMAND of the round",
		events == ["round_started:2", "turn_started:1"], str(events))
	events.clear()
	pm.transition_to_phase(6)  # COMMAND again, same round
	_check("round_started fires once per round", events == ["turn_started:1"], str(events))

	pm.unregister_turn_ending_hook(mission_cb)
	pm.unregister_turn_ending_hook(rule_cb)
	pm.unregister_turn_ending_hook(rule2_cb)
	gs.state = prev
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
