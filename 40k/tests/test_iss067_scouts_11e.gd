extends SceneTree

# ISS-067 (11e 24.31/24.32): Scouts. (A) after-move distance is >8" from
# enemy units at edition 11 (>9" at 10e); (B) a scout move requires the
# unit wholly within its deployment zone; (C) a Scout unit in strategic
# reserves may set up wholly within its DZ (the new 11e option the phase
# previously rejected outright). Drives the REAL ScoutPhase.
#
# Usage: godot --headless --path . -s tests/test_iss067_scouts_11e.gd

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

func _setup(gs) -> void:
	# Player 1 DZ = left 20" x 60" rectangle (0..800px, 0..2400px).
	gs.state["board"]["deployment_zones"] = [
		{"player": 1, "poly": [{"x": 0, "y": 0}, {"x": 20, "y": 0}, {"x": 20, "y": 60}, {"x": 0, "y": 60}]},
		{"player": 2, "poly": [{"x": 24, "y": 0}, {"x": 44, "y": 0}, {"x": 44, "y": 60}, {"x": 24, "y": 60}]},
	]
	gs.state["units"] = {
		"U_S": {"id": "U_S", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Scouts", "keywords": ["INFANTRY"], "abilities": [{"name": "Scouts 6\""}], "stats": {"move": 6}},
			"models": [{"id": "m0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32, "base_type": "circular", "position": {"x": 400, "y": 400}}]},
		"U_E": {"id": "U_E", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Enemy", "keywords": ["INFANTRY"], "stats": {"move": 6}},
			"models": [{"id": "e0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32, "base_type": "circular", "position": {"x": 1000, "y": 400}}]},
		"U_R": {"id": "U_R", "owner": 1, "status": 7, "reserve_type": "strategic_reserves", "flags": {},
			"meta": {"name": "ReserveScouts", "keywords": ["INFANTRY"], "abilities": [{"name": "Scouts 6\""}], "stats": {"move": 6}},
			"models": [{"id": "r0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32, "base_type": "circular", "position": null}]},
	}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 4

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss067_scouts_11e ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	if gs == null or pm == null:
		_check("autoloads", false); _finish(); return
	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition

	# Build at edition 11 so the SCOUT phase enter collects reserve scouts.
	GameConstants.edition = 11
	_setup(gs)
	pm.transition_to_phase(4)  # SCOUT
	var sp = pm.get_current_phase_instance()

	# ---- (A) after-move distance: >8" (11e) vs >9" (10e) ----
	# Enemy at (1000,400); model at (400,400). 32mm bases -> radii sum 1.26".
	# dest (610,400): edge ~8.5" from enemy. dest (650,400): edge ~7.5".
	print("-- (A) after-move enemy distance --")
	sp.active_scout_moves["U_S"] = {"scout_distance": 12.0, "staged_positions": {}}
	GameConstants.edition = 11
	var d85 = sp._validate_set_scout_model_dest({"unit_id": "U_S", "model_id": "m0", "destination": {"x": 610, "y": 400}})
	_check("e11: dest ~8.5\" from enemy is allowed (>8\")", d85.valid, str(d85))
	var d75 = sp._validate_set_scout_model_dest({"unit_id": "U_S", "model_id": "m0", "destination": {"x": 650, "y": 400}})
	_check("e11: dest ~7.5\" from enemy is rejected (<8\")", not d75.valid, str(d75))
	GameConstants.edition = 10
	var d85_10 = sp._validate_set_scout_model_dest({"unit_id": "U_S", "model_id": "m0", "destination": {"x": 610, "y": 400}})
	_check("e10: same ~8.5\" dest is rejected (10e needs >9\")", not d85_10.valid, str(d85_10))
	GameConstants.edition = 11

	# ---- (B) wholly-within-DZ eligibility ----
	print("\n-- (B) wholly-within-DZ eligibility (24.32) --")
	sp.active_scout_moves.erase("U_S")
	var b_in = sp._validate_begin_scout_move({"unit_id": "U_S"})
	_check("e11: unit wholly in its DZ may begin a scout move", b_in.valid, str(b_in))
	# Move U_S outside its DZ (x=30\" -> 1200px > 800px DZ edge).
	gs.state["units"]["U_S"]["models"][0]["position"] = {"x": 1200, "y": 400}
	var b_out = sp._validate_begin_scout_move({"unit_id": "U_S"})
	_check("e11: unit outside its DZ is rejected (24.32)",
		not b_out.valid and str(b_out.errors).contains("deployment zone"), str(b_out))
	gs.state["units"]["U_S"]["models"][0]["position"] = {"x": 400, "y": 400}

	# ---- (C) strategic-reserves placement (the previously-missing option) ----
	print("\n-- (C) strategic-reserves Scout placement (24.31) --")
	_check("e11: reserve Scout unit is collected as pending",
		"U_R" in sp.scout_reserve_units_pending.get(1, []), str(sp.scout_reserve_units_pending))
	var c_in = sp._validate_scout_reserves_deploy({"unit_id": "U_R", "model_positions": [[300, 600]]})
	_check("e11: deploy wholly within own DZ is allowed", c_in.valid, str(c_in))
	var c_out = sp._validate_scout_reserves_deploy({"unit_id": "U_R", "model_positions": [[1200, 400]]})
	_check("e11: deploy outside own DZ is rejected (24.31)",
		not c_out.valid and str(c_out.errors).contains("deployment zone"), str(c_out))
	# Process the valid placement and confirm the unit deploys.
	var proc = sp._process_scout_reserves_deploy({"unit_id": "U_R", "model_positions": [[300, 600]]})
	_check("e11: process returns the deploy diffs (status -> DEPLOYED, position set)",
		proc.get("success", false) and str(proc.get("changes", [])).contains("status"), str(proc.get("changes")))
	_check("e11: reserve unit removed from pending after deploy",
		not ("U_R" in sp.scout_reserve_units_pending.get(1, [])))

	# Edition 10: the reserves option does not exist.
	GameConstants.edition = 10
	var c_10 = sp._validate_scout_reserves_deploy({"unit_id": "U_R", "model_positions": [[300, 600]]})
	_check("e10: reserves Scout deployment is rejected (11e-only rule)", not c_10.valid, str(c_10))

	gs.state = prev_state
	GameConstants.edition = prev_edition
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
