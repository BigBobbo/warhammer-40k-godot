extends SceneTree

# Reproduction: does a REAL new game actually pass through ROLL_OFF, and does
# the roll-off winner end up active for the first Command phase? Drives the
# live PhaseManager autoload from FORMATIONS the way Main._ready() does and
# logs every phase it lands in.
#
# Usage: godot --headless --path . -s tests/test_new_game_reaches_rolloff.gd

const GSD = preload("res://autoloads/GameState.gd")

var phases_seen: Array = []

func _init():
	create_timer(0.2).timeout.connect(_run)

func _run():
	var gs = root.get_node("GameState")
	var pm = root.get_node("PhaseManager")

	# Fresh new game, exactly like MainMenu does.
	gs.initialize_default_state("dawn_of_war")
	print("After init: phase=%s active=%d" % [_pname(gs.get_current_phase()), gs.get_active_player()])

	pm.phase_changed.connect(func(p): phases_seen.append(p); print("  -> phase_changed: %s (active=%d)" % [_pname(p), gs.get_active_player()]))

	# Boot the first phase the way Main._ready() does for a new game.
	pm.transition_to_phase(GSD.Phase.FORMATIONS)

	# Now advance phase-by-phase the way the engine does on each phase_completed,
	# stopping when we first reach COMMAND (battle round 1, turn 1).
	var guard := 0
	while gs.get_current_phase() != GSD.Phase.COMMAND and guard < 20:
		guard += 1
		var before = gs.get_current_phase()
		pm.advance_to_next_phase()
		var after = gs.get_current_phase()
		if after == before:
			print("  (no advance from %s — stuck)" % _pname(before))
			break

	print("\nPhases seen: %s" % str(phases_seen.map(func(p): return _pname(p))))
	var saw_rolloff := phases_seen.has(GSD.Phase.ROLL_OFF)
	print("Reached ROLL_OFF in a new game: %s" % str(saw_rolloff))
	print("Final phase: %s, active_player=%d" % [_pname(gs.get_current_phase()), gs.get_active_player()])

	# Emit a runner-compatible result line.
	if saw_rolloff:
		print("\n=== Result: 1 passed, 0 failed ===")
	else:
		print("  FAIL: new game did not pass through ROLL_OFF")
		print("\n=== Result: 0 passed, 1 failed ===")
	quit(0 if saw_rolloff else 1)

func _pname(p) -> String:
	return GSD.Phase.keys()[p]
