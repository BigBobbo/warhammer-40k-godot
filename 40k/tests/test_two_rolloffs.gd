extends SceneTree

# Validates the 10th-edition TWO independent pre-battle roll-offs:
#   1. RollOffPhase (pre-deployment): winner CHOOSES who deploys first
#      (Attacker/Defender). Sets meta.attacker / meta.defender. Must NOT set
#      meta.first_turn_player.
#   2. FirstTurnRollOffPhase (post-deployment): winner TAKES the first turn,
#      no choice. Sets meta.first_turn_player.
#
# Also checks the standard phase sequence now routes
# REDEPLOYMENT -> FIRST_TURN_ROLLOFF -> SCOUT.
#
# Usage: godot --headless --path . -s tests/test_two_rolloffs.gd

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
	create_timer(0.1).timeout.connect(_run)

func _run():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_two_rolloffs ===\n")
	_test_deploy_rolloff_sets_roles_only()
	_test_deploy_rolloff_choice_both_ways()
	_test_first_turn_rolloff_winner_goes_first()
	_test_phase_sequence()
	_finish()

# --- Roll-off #1: deployment order only --------------------------------------
func _test_deploy_rolloff_sets_roles_only() -> void:
	print("\n-- Deploy roll-off sets Attacker/Defender ONLY (no first turn) --")
	var DeployRollOff = load("res://phases/RollOffPhase.gd")
	var phase = DeployRollOff.new()
	phase._on_phase_enter()

	# P1 wins (5 vs 3).
	var roll = phase.process_action({"type": "ROLL_OFF_DEPLOYMENT", "dice_roll": [5, 3]})
	_check("Deploy roll-off [5,3] → P1 wins", roll.get("winner", 0) == 1,
		"winner=%s" % str(roll.get("winner")))

	# P1 chooses to DEPLOY SECOND (Attacker). So P2 is Defender (deploys first).
	var choice = phase.process_action({"type": "CHOOSE_DEPLOYMENT", "choice": "second"})
	_check("Winner deploy 'second' → winner is Attacker", choice.get("attacker", 0) == 1)
	_check("Winner deploy 'second' → opponent is Defender (deploys first)",
		choice.get("defender", 0) == 2)

	# The change set must touch attacker/defender but NOT first_turn_player.
	var paths := {}
	for c in choice.get("changes", []):
		paths[c.get("path", "")] = c.get("value")
	_check("changes set meta.attacker", paths.has("meta.attacker") and paths["meta.attacker"] == 1)
	_check("changes set meta.defender", paths.has("meta.defender") and paths["meta.defender"] == 2)
	_check("deploy roll-off does NOT set meta.first_turn_player",
		not paths.has("meta.first_turn_player"),
		"paths=%s" % str(paths.keys()))

func _test_deploy_rolloff_choice_both_ways() -> void:
	print("\n-- Deploy roll-off: 'deploy first' makes the winner the Defender --")
	var DeployRollOff = load("res://phases/RollOffPhase.gd")
	var phase = DeployRollOff.new()
	phase._on_phase_enter()
	phase.process_action({"type": "ROLL_OFF_DEPLOYMENT", "dice_roll": [6, 2]})  # P1 wins
	var choice = phase.process_action({"type": "CHOOSE_DEPLOYMENT", "choice": "first"})
	_check("Winner deploy 'first' → winner is Defender", choice.get("defender", 0) == 1)
	_check("Winner deploy 'first' → opponent is Attacker", choice.get("attacker", 0) == 2)

# --- Roll-off #2: first turn, no choice --------------------------------------
func _test_first_turn_rolloff_winner_goes_first() -> void:
	print("\n-- First-turn roll-off: winner takes the first turn, no choice --")
	var FirstTurn = load("res://phases/FirstTurnRollOffPhase.gd")
	var phase = FirstTurn.new()
	phase._on_phase_enter()

	# P2 wins (3 vs 5) → P2 takes the first turn.
	var roll = phase.process_action({"type": "ROLL_OFF_FIRST_TURN", "dice_roll": [3, 5]})
	_check("First-turn roll-off [3,5] → P2 wins", roll.get("winner", 0) == 2)
	_check("Winner takes first turn → first_turn_player = 2",
		roll.get("first_turn_player", 0) == 2)

	var paths := {}
	for c in roll.get("changes", []):
		paths[c.get("path", "")] = c.get("value")
	_check("changes set meta.first_turn_player = 2",
		paths.get("meta.first_turn_player", 0) == 2)
	_check("changes seat winner as active_player = 2",
		paths.get("meta.active_player", 0) == 2)

	# There is NO choice action — only an acknowledgement completes the phase.
	var avail = phase.get_available_actions()
	var types := []
	for a in avail:
		types.append(a.get("type", ""))
	_check("after roll, only CONFIRM_FIRST_TURN is offered (no choice)",
		types == ["CONFIRM_FIRST_TURN"], "types=%s" % str(types))
	_check("phase not complete until confirmed", not phase._should_complete_phase())
	phase.process_action({"type": "CONFIRM_FIRST_TURN"})
	_check("phase completes after CONFIRM_FIRST_TURN", phase._should_complete_phase())

	# Tie → re-roll (no winner yet).
	var phase2 = FirstTurn.new()
	phase2._on_phase_enter()
	var tie = phase2.process_action({"type": "ROLL_OFF_FIRST_TURN", "dice_roll": [4, 4]})
	_check("First-turn tie → tied=true, re-roll", tie.get("tied", false) == true)

# --- Phase sequence ----------------------------------------------------------
func _test_phase_sequence() -> void:
	print("\n-- Standard sequence routes REDEPLOYMENT -> FIRST_TURN_ROLLOFF -> SCOUT --")
	var pm = root.get_node("PhaseManager")
	_check("REDEPLOYMENT -> FIRST_TURN_ROLLOFF",
		pm._get_next_phase(GSD.Phase.REDEPLOYMENT) == GSD.Phase.FIRST_TURN_ROLLOFF)
	_check("FIRST_TURN_ROLLOFF -> SCOUT",
		pm._get_next_phase(GSD.Phase.FIRST_TURN_ROLLOFF) == GSD.Phase.SCOUT)
	_check("FORMATIONS -> ROLL_OFF (deploy roll-off still first)",
		pm._get_next_phase(GSD.Phase.FORMATIONS) == GSD.Phase.ROLL_OFF)
	_check("ROLL_OFF -> DEPLOYMENT",
		pm._get_next_phase(GSD.Phase.ROLL_OFF) == GSD.Phase.DEPLOYMENT)

func _finish() -> void:
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
