extends SceneTree

# Regression test: the pre-deployment roll-off result must actually decide
# who takes the first turn.
#
# Bug: RollOffPhase correctly computed meta.first_turn_player, but nothing
# applied it as the active player when battle round 1 began. The active
# player was left over from deployment alternation (which tends to default
# to Player 1), so "Player 1 always went first" regardless of the roll-off.
#
# Fix: TurnManager._on_phase_completed(SCOUT) (and SCOUT_MOVES) now call
# _apply_first_turn_player(), which sets the active player to
# meta.first_turn_player.
#
# Usage: godot --headless --path . -s tests/test_roll_off_first_turn_applied.gd

const GSD = preload("res://autoloads/GameState.gd")

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
	print("\n=== test_roll_off_first_turn_applied ===\n")

	_test_rolloff_phase_computes_first_turn()
	_test_scout_complete_applies_first_turn()
	_test_fallback_when_no_rolloff()

	_finish()

# ----------------------------------------------------------------------------
# RollOffPhase: a P2 win followed by "go first" must set first_turn_player = 2
# ----------------------------------------------------------------------------
func _test_rolloff_phase_computes_first_turn() -> void:
	print("\n-- RollOffPhase computes first_turn_player from the dice --")
	var RollOffPhase = load("res://phases/RollOffPhase.gd")
	var phase = RollOffPhase.new()
	phase._on_phase_enter()

	# Force P2 to win the roll (3 vs 5).
	var roll_result = phase.process_action({"type": "ROLL_FOR_FIRST_TURN", "dice_roll": [3, 5]})
	_check("Roll-off with [3,5] → P2 wins",
		roll_result.get("winner", 0) == 2,
		"winner=%s" % str(roll_result.get("winner")))

	# Winner chooses to go first (attacker / deploy second).
	var choice_result = phase.process_action({"type": "CHOOSE_TURN_ORDER", "choice": "first"})
	_check("Winner P2 chooses 'first' → first_turn_player = 2",
		choice_result.get("first_turn_player", 0) == 2,
		"first_turn_player=%s" % str(choice_result.get("first_turn_player")))

	# The emitted changes must set meta.first_turn_player = 2.
	var changes = choice_result.get("changes", [])
	var found_ftp := false
	for c in changes:
		if c.get("path", "") == "meta.first_turn_player":
			found_ftp = c.get("value", -1) == 2
	_check("changes set meta.first_turn_player = 2", found_ftp)

# ----------------------------------------------------------------------------
# TurnManager: when SCOUT completes, the active player becomes
# meta.first_turn_player (the roll-off winner), not the deployment leftover.
# ----------------------------------------------------------------------------
func _test_scout_complete_applies_first_turn() -> void:
	print("\n-- Scout completion applies the roll-off first-turn player --")
	var game_state = root.get_node("GameState")
	var turn_mgr = root.get_node("TurnManager")

	# Roll-off decided Player 2 goes first.
	game_state.state["meta"]["first_turn_player"] = 2
	# Simulate the "Player 1 leftover" deployment state the bug produced.
	game_state.set_active_player(1)
	_check("Pre-condition: active player is the leftover P1",
		game_state.get_active_player() == 1)

	# Scout phase finishing is the last gate before battle round 1.
	turn_mgr._on_phase_completed(GSD.Phase.SCOUT)
	_check("After SCOUT complete → active player is the roll-off winner (P2)",
		game_state.get_active_player() == 2,
		"active=%s" % str(game_state.get_active_player()))

	# And it must work the other way too (P1 won the roll-off).
	game_state.state["meta"]["first_turn_player"] = 1
	game_state.set_active_player(2)
	turn_mgr._on_phase_completed(GSD.Phase.SCOUT)
	_check("Roll-off winner P1 → active player becomes P1",
		game_state.get_active_player() == 1,
		"active=%s" % str(game_state.get_active_player()))

# ----------------------------------------------------------------------------
# Safety: if the roll-off never ran (no meta.first_turn_player), fall back to P1.
# ----------------------------------------------------------------------------
func _test_fallback_when_no_rolloff() -> void:
	print("\n-- Missing first_turn_player falls back to P1 --")
	var game_state = root.get_node("GameState")
	var turn_mgr = root.get_node("TurnManager")

	game_state.state["meta"].erase("first_turn_player")
	game_state.set_active_player(2)
	turn_mgr._on_phase_completed(GSD.Phase.SCOUT)
	_check("No first_turn_player → active player defaults to P1",
		game_state.get_active_player() == 1,
		"active=%s" % str(game_state.get_active_player()))

func _finish() -> void:
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
