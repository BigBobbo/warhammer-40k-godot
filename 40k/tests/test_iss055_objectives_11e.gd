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

	print("\n-- C: terrain objectives (14.01) --")
	var tm = root.get_node_or_null("TerrainManager")
	var prev_terrain = tm.terrain_features.duplicate(true)
	# A ruin area covering the objective point: x 600-1000, y 600-1000.
	tm.terrain_features = [{"id": "obj_ruin", "type": "ruins",
		"polygon": PackedVector2Array([Vector2(600, 600), Vector2(880, 600),
			Vector2(880, 1000), Vector2(600, 1000)]),
		"height_category": "tall"}]
	GameConstants.edition = 11
	mm._sticky_objectives = {}
	mm.objective_control_state["OBJ_T"] = 0
	# Model INSIDE the area but ~6" from the marker point: counts (14.01).
	gs.state["units"]["U_FOE"]["flags"].erase("battle_shocked")
	gs.state["units"]["U_FOE"]["models"][0]["position"] = {"x": 620, "y": 620}
	mm.check_all_objectives()
	_check("model within the terrain area controls the terrain objective (even >3\" from the point)",
		mm.objective_control_state.get("OBJ_T", 0) == 2,
		str(mm.objective_control_state))
	# Model OUTSIDE the area but within 3\" of the point: does NOT count.
	mm._sticky_objectives = {}
	mm.objective_control_state["OBJ_T"] = 0
	gs.state["units"]["U_FOE"]["models"][0]["position"] = {"x": 920, "y": 800}
	mm.check_all_objectives()
	_check("model outside the area exerts no control on a terrain objective (14.02)",
		mm.objective_control_state.get("OBJ_T", 0) == 0,
		str(mm.objective_control_state))
	# 10e unchanged: marker radius applies.
	GameConstants.edition = 10
	mm._sticky_objectives = {}
	mm.objective_control_state["OBJ_T"] = 0
	mm.check_all_objectives()
	_check("10e: marker radius unchanged (the 920,800 model is within 3\"+radius)",
		mm.objective_control_state.get("OBJ_T", 0) == 2,
		str(mm.objective_control_state))
	tm.terrain_features = prev_terrain

	print("\n-- D: partial base overlap + contested vs uncontrolled (mek-contested bug) --")
	tm.terrain_features = [{"id": "obj_ruin", "type": "ruins",
		"polygon": PackedVector2Array([Vector2(600, 600), Vector2(880, 600),
			Vector2(880, 1000), Vector2(600, 1000)]),
		"height_category": "tall"}]
	GameConstants.edition = 11
	mm._sticky_objectives = {}
	mm.objective_control_state["OBJ_T"] = 0
	# Model centre OUTSIDE the area (x=900 > 880) but its 32mm base
	# (radius ~25.2px) overlaps the right edge by ~5px: must count.
	gs.state["units"]["U_FOE"]["models"][0]["position"] = {"x": 900, "y": 800}
	mm.check_all_objectives()
	_check("base partially on the area (centre outside) controls the terrain objective",
		mm.objective_control_state.get("OBJ_T", 0) == 2,
		str(mm.objective_control_state))
	_check("one-sided control is NOT flagged contested",
		not mm.is_objective_contested("OBJ_T"))
	# Same centre-outside position, but base short of the edge: no control.
	gs.state["units"]["U_FOE"]["models"][0]["position"] = {"x": 910, "y": 800}
	mm.check_all_objectives()
	_check("base short of the area edge exerts no control",
		mm.objective_control_state.get("OBJ_T", 0) == 0,
		str(mm.objective_control_state))
	# Nobody in range at all -> uncontrolled, NOT contested.
	gs.state["units"]["U_FOE"]["models"][0]["position"] = {"x": 1500, "y": 300}
	mm.check_all_objectives()
	_check("empty objective is uncontrolled (controller 0)",
		mm.objective_control_state.get("OBJ_T", 0) == 0,
		str(mm.objective_control_state))
	_check("empty objective is NOT flagged contested",
		not mm.is_objective_contested("OBJ_T"))
	# Equal, nonzero OC from both sides -> genuinely contested.
	gs.state["units"]["U_FOE"]["models"][0]["position"] = {"x": 700, "y": 800}
	gs.state["units"]["U_ALLY"] = {"id": "U_ALLY", "owner": 1, "flags": {},
		"status": 2,
		"meta": {"keywords": ["INFANTRY"], "stats": {"objective_control": 2}},
		"models": [{"id": "m0", "alive": true, "base_mm": 32, "base_type": "circular",
			"position": {"x": 640, "y": 800}}]}
	mm.check_all_objectives()
	_check("equal nonzero OC on both sides -> controller 0",
		mm.objective_control_state.get("OBJ_T", 0) == 0,
		str(mm.objective_control_state))
	_check("equal nonzero OC on both sides IS flagged contested",
		mm.is_objective_contested("OBJ_T"))
	tm.terrain_features = prev_terrain

	GameConstants.edition = 10
	gs.state = prev_state
	mm.objective_control_state = prev_ctrl
	mm._sticky_objectives = prev_sticky
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
