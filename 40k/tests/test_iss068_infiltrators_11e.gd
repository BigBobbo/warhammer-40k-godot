extends SceneTree

# ISS-068 (11e 24.20): Infiltrators deploy >8" horizontally from the enemy
# deployment zone and all enemy units at edition 11 (>9" at 10e). Drives
# the REAL DeploymentPhase._validate_infiltrators_position at the boundary.
#
# Usage: godot --headless --path . -s tests/test_iss068_infiltrators_11e.gd

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
	# Enemy (player 2) DZ far away (bottom strip) so only the enemy-MODEL
	# distance check is exercised by positions near (600-650, 400).
	gs.state["board"]["deployment_zones"] = [
		{"player": 1, "poly": [{"x": 0, "y": 0}, {"x": 44, "y": 0}, {"x": 44, "y": 14}, {"x": 0, "y": 14}]},
		{"player": 2, "poly": [{"x": 0, "y": 46}, {"x": 44, "y": 46}, {"x": 44, "y": 60}, {"x": 0, "y": 60}]},
	]
	gs.state["units"] = {
		"U_INF": {"id": "U_INF", "owner": 1, "status": 0, "flags": {},
			"meta": {"name": "Infiltrators", "keywords": ["INFANTRY"], "abilities": [{"name": "Infiltrators"}], "stats": {}},
			"models": [{"id": "m0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32, "base_type": "circular", "position": null}]},
		"U_E": {"id": "U_E", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Enemy", "keywords": ["INFANTRY"], "stats": {}},
			"models": [{"id": "e0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32, "base_type": "circular", "position": {"x": 1000, "y": 400}}]},
	}
	gs.state["meta"]["active_player"] = 1

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss068_infiltrators_11e ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	if gs == null or pm == null:
		_check("autoloads", false); _finish(); return
	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition

	_setup(gs)
	pm.transition_to_phase(1)  # DEPLOYMENT
	var dp = pm.get_current_phase_instance()
	var unit = gs.state["units"]["U_INF"]

	# Enemy model at (1000,400); 32mm bases -> radii sum 1.26".
	# (610,400): edge ~8.5"; (650,400): edge ~7.5".
	print("-- enemy-model distance boundary --")
	GameConstants.edition = 11
	var v85 = dp._validate_infiltrators_position(Vector2(610, 400), unit, 0, 1, 0.0)
	_check("e11: ~8.5\" from enemy model is allowed (>8\")", v85.valid, str(v85))
	var v75 = dp._validate_infiltrators_position(Vector2(650, 400), unit, 0, 1, 0.0)
	_check("e11: ~7.5\" from enemy model is rejected (<8\")", not v75.valid, str(v75))

	GameConstants.edition = 10
	var v85_10 = dp._validate_infiltrators_position(Vector2(610, 400), unit, 0, 1, 0.0)
	_check("e10: same ~8.5\" position rejected (10e needs >9\")", not v85_10.valid, str(v85_10))
	var v95_10 = dp._validate_infiltrators_position(Vector2(570, 400), unit, 0, 1, 0.0)
	# (570,400): edge ~9.5" -> allowed at 10e.
	_check("e10: ~9.0\"+ position allowed at 10e", v95_10.valid, str(v95_10))

	gs.state = prev_state
	GameConstants.edition = prev_edition
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
