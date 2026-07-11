extends SceneTree

# Battle-round tracking when Player 2 takes the FIRST turn of each round.
#
# Bug: ScoringPhase/GameManager advanced meta.battle_round whenever Player 2
# ended a turn, assuming P1 always went first. When the first-turn roll-off
# gave P2 the first turn, Round 1 "ended" after a single player turn — so
# Player 1's FIRST turn of the game ran as Battle Round 2, which (among other
# things) unlocked PLACE_REINFORCEMENT and made the AI suggest bringing units
# in from Deep Strike on turn one.
#
# Checks:
#   A) GameState.get_first_turn_player / is_last_turn_of_round helpers,
#      including the fallback (missing meta key -> Player 1 first).
#   B) P2-first: P2's END_TURN does NOT advance the round; P1's does.
#   C) P2-first: MovementPhase offers no PLACE_REINFORCEMENT during P1's
#      first turn (still Round 1) even with units in reserves, and offers
#      them once Round 2 genuinely starts.
#   D) P2-first: at MAX_BATTLE_ROUNDS the game ends after P1's turn (the
#      round's second player), not after P2's.
#
# Usage: godot --headless --path . -s tests/test_p2_first_turn_round_advance.gd

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

func _end_turn_via_scoring(gs, player: int) -> Dictionary:
	var phase = load("res://phases/ScoringPhase.gd").new()
	root.add_child(phase)
	phase.game_state_snapshot = gs.create_snapshot()
	var result = phase.execute_action({"type": "END_TURN", "player": player})
	root.remove_child(phase)
	phase.free()
	return result

func _movement_reinforcement_actions(gs) -> Array:
	var phase = load("res://phases/MovementPhase.gd").new()
	root.add_child(phase)
	phase.game_state_snapshot = gs.create_snapshot()
	var out := []
	for a in phase.get_available_actions():
		if a.get("type", "") == "PLACE_REINFORCEMENT":
			out.append(a)
	root.remove_child(phase)
	phase.free()
	return out

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_p2_first_turn_round_advance ===\n")
	var gs = root.get_node_or_null("GameState")
	var prev = gs.state.duplicate(true)

	print("-- A: first-turn helpers --")
	gs.initialize_default_state()
	_check("fallback: no meta.first_turn_player -> P1 first", gs.get_first_turn_player() == 1)
	_check("fallback: P2 closes the round", gs.is_last_turn_of_round(2) and not gs.is_last_turn_of_round(1))
	gs.state["meta"]["first_turn_player"] = 2
	_check("roll-off winner P2 -> P2 first", gs.get_first_turn_player() == 2)
	_check("P2-first: P1 closes the round", gs.is_last_turn_of_round(1) and not gs.is_last_turn_of_round(2))

	print("\n-- B: P2-first round advance --")
	gs.initialize_default_state()
	gs.state["meta"]["first_turn_player"] = 2
	gs.state["meta"]["active_player"] = 2
	gs.state["meta"]["battle_round"] = 1
	var r1 = _end_turn_via_scoring(gs, 2)
	_check("P2 END_TURN succeeded", r1.get("success", false), str(r1))
	_check("round did NOT advance after P2 (first) turn", gs.get_battle_round() == 1,
		"round=%d" % gs.get_battle_round())
	_check("active player switched to 1", gs.get_active_player() == 1)
	var r2 = _end_turn_via_scoring(gs, 1)
	_check("P1 END_TURN succeeded", r2.get("success", false), str(r2))
	_check("round advanced after P1 (second) turn", gs.get_battle_round() == 2,
		"round=%d" % gs.get_battle_round())
	_check("active player switched back to 2", gs.get_active_player() == 2)

	print("\n-- C: no reinforcements on P1's first turn (P2-first) --")
	gs.initialize_default_state()
	gs.state["meta"]["first_turn_player"] = 2
	gs.state["meta"]["battle_round"] = 1
	gs.state["meta"]["active_player"] = 2
	# Minimal armies: one deployed unit each + one P1 unit in Deep Strike reserves
	gs.state["units"] = {
		"U_P1_LINE": {
			"owner": 1, "status": 2,  # UnitStatus.DEPLOYED
			"meta": {"name": "P1 Line", "stats": {"move": 6}},
			"models": [{"id": "m1", "alive": true, "base_mm": 32, "position": {"x": 400, "y": 2200}, "wounds": 1, "current_wounds": 1}],
			"flags": {}
		},
		"U_P1_DEEPSTRIKER": {
			"owner": 1, "status": 7,  # UnitStatus.IN_RESERVES
			"reserve_type": "deep_strike",
			"meta": {"name": "P1 Deep Striker", "stats": {"move": 12},
				"abilities": [{"name": "Deep Strike"}]},
			"models": [{"id": "m1", "alive": true, "base_mm": 40, "position": null, "wounds": 2, "current_wounds": 2}],
			"flags": {}
		},
		"U_P2_LINE": {
			"owner": 2, "status": 2,  # UnitStatus.DEPLOYED
			"meta": {"name": "P2 Line", "stats": {"move": 6}},
			"models": [{"id": "m1", "alive": true, "base_mm": 32, "position": {"x": 400, "y": 200}, "wounds": 1, "current_wounds": 1}],
			"flags": {}
		},
	}
	var end_p2 = _end_turn_via_scoring(gs, 2)
	_check("P2 (first) END_TURN succeeded", end_p2.get("success", false), str(end_p2))
	_check("still Round 1 for P1's first turn", gs.get_battle_round() == 1,
		"round=%d" % gs.get_battle_round())
	gs.state["meta"]["phase"] = 7  # Phase.MOVEMENT
	var reinf_r1 = _movement_reinforcement_actions(gs)
	_check("no PLACE_REINFORCEMENT during P1's first turn", reinf_r1.is_empty(),
		"got %d reinforcement actions" % reinf_r1.size())
	# End P1's turn -> Round 2 genuinely starts -> reinforcements unlock for P2's turn,
	# and P1's next movement phase offers the deep striker.
	gs.state["meta"]["phase"] = 11  # Phase.SCORING
	var end_p1 = _end_turn_via_scoring(gs, 1)
	_check("P1 (second) END_TURN succeeded", end_p1.get("success", false), str(end_p1))
	_check("Round 2 after both turns", gs.get_battle_round() == 2, "round=%d" % gs.get_battle_round())
	gs.state["meta"]["phase"] = 7  # Phase.MOVEMENT
	gs.state["meta"]["active_player"] = 1
	var reinf_r2 = _movement_reinforcement_actions(gs)
	_check("PLACE_REINFORCEMENT offered in Round 2", reinf_r2.size() == 1,
		"got %d reinforcement actions" % reinf_r2.size())

	print("\n-- D: game end on the round's second player at max rounds --")
	gs.initialize_default_state()
	gs.state["meta"]["first_turn_player"] = 2
	gs.state["meta"]["active_player"] = 2
	gs.state["meta"]["battle_round"] = gs.MAX_BATTLE_ROUNDS
	var end_p2_final = _end_turn_via_scoring(gs, 2)
	_check("P2's final-round turn does not end the game", not end_p2_final.get("game_ended", false),
		str(end_p2_final))
	_check("game not flagged ended yet", not gs.state["meta"].get("game_ended", false))
	var end_p1_final = _end_turn_via_scoring(gs, 1)
	_check("P1's final-round turn ends the game", end_p1_final.get("game_ended", false),
		str(end_p1_final))
	_check("meta.game_ended set", gs.state["meta"].get("game_ended", false))

	print("\n-- E: round-boundary helpers agree for the DEFAULT (P1-first) case --")
	# Regression guard: with no first_turn_player set (legacy games), the fix
	# must behave EXACTLY like the old hardcoded 'Player 2 closes the round' /
	# 'Player 1 opens the round' logic. get_first_turn_player() falls back to 1.
	gs.initialize_default_state()
	_check("default first-turn player is 1", gs.get_first_turn_player() == 1)
	_check("default: P1 opens the round (is_last_turn_of_round(1) == false)",
		gs.is_last_turn_of_round(1) == false)
	_check("default: P2 closes the round (is_last_turn_of_round(2) == true)",
		gs.is_last_turn_of_round(2) == true)
	# Equivalence with the old hardcoded checks these call sites used:
	#   CommandPhase per-round reset: old `current_player == 1` == new `== get_first_turn_player()`
	#   TurnManager/SaveLoadManager round-end: same
	#   ScoringPhase/GameManager round advance: old `current_player == 2` == new `is_last_turn_of_round`
	_check("default: reset gate matches old 'current_player == 1'",
		(1 == gs.get_first_turn_player()) == true and (2 == gs.get_first_turn_player()) == false)
	_check("default: advance gate matches old 'current_player == 2'",
		gs.is_last_turn_of_round(2) == true and gs.is_last_turn_of_round(1) == false)

	gs.state = prev
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
