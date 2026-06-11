extends SceneTree

# ISS-055 (step 1): 11e objective control timing + Secured objectives.
#   A) 14.02: control is determined at the end of EACH PHASE (wired to
#      PhaseManager.phase_completed, edition-gated).
#   B) 14.03: an objective secured by the army stays controlled with no
#      units in range, and breaks when the opponent out-controls it.
#
# Usage: godot --headless --path . -s tests/test_iss055_objectives_11e.gd

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
	print("\n=== test_iss055_objectives_11e ===\n")
	var mm = root.get_node_or_null("MissionManager")
	var pm = root.get_node_or_null("PhaseManager")
	var gs = root.get_node_or_null("GameState")
	var prev_state = gs.state.duplicate(true)
	var prev_ctrl = mm.objective_control_state.duplicate(true)
	var prev_sticky = mm._sticky_objectives.duplicate(true)

	print("-- A: per-phase evaluation wiring (14.02) --")
	_check("MissionManager listens to phase_completed",
		pm.phase_completed.is_connected(mm._on_phase_completed_11e))
	_check("MissionManager listens to turn_ending",
		pm.turn_ending.is_connected(mm._on_turn_ending_11e))

	print("\n-- B: secured objectives (14.03) --")
	# Build a minimal objective list + empty board.
	gs.initialize_default_state()
	gs.state["units"] = {}
	# check_all_objectives reads GameState.state.board.objectives
	gs.state["board"]["objectives"] = [{"id": "OBJ_T", "position": Vector2(800, 800)}]
	mm.objective_control_state = {"OBJ_T": 0}
	mm._sticky_objectives = {}

	# Army-level secure with NO units anywhere
	mm.secure_objective("OBJ_T", 1)
	_check("secure_objective marks it", mm.is_objective_secured("OBJ_T").secured)
	GameConstants.edition = 11
	mm.check_all_objectives()
	_check("secured objective stays controlled with no units in range",
		mm.objective_control_state.get("OBJ_T", 0) == 1,
		str(mm.objective_control_state))

	# Opponent moves a unit with OC onto it: secured lock breaks
	gs.state["units"]["U_FOE"] = {"id": "U_FOE", "owner": 2, "flags": {},
		"status": 2,  # UnitStatus.DEPLOYED (raw int: avoids compile-time autoload dependency)
		"meta": {"keywords": ["INFANTRY"], "stats": {"objective_control": 2}},
		"models": [{"id": "m0", "alive": true, "base_mm": 32, "base_type": "circular",
			"position": {"x": 800, "y": 800}}]}
	mm.check_all_objectives()
	_check("greater enemy control BREAKS the secured lock (14.03)",
		mm.objective_control_state.get("OBJ_T", 0) == 2
		and not mm.is_objective_secured("OBJ_T").secured,
		str(mm.objective_control_state))

	# Battle-shocked units contribute nothing (OC '-')
	gs.state["units"]["U_FOE"]["flags"]["battle_shocked"] = true
	mm._sticky_objectives = {}
	mm.objective_control_state["OBJ_T"] = 0
	mm.check_all_objectives()
	_check("battle-shocked unit exerts no control (OC '-')",
		mm.objective_control_state.get("OBJ_T", 0) == 0,
		str(mm.objective_control_state))

	GameConstants.edition = 10
	gs.state = prev_state
	mm.objective_control_state = prev_ctrl
	mm._sticky_objectives = prev_sticky
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
