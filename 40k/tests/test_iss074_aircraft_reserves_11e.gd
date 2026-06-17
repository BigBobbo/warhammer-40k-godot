extends SceneTree

# ISS-074 (11e 23.01/23.02): AIRCRAFT reserve cycle.
#   23.01 — AIRCRAFT must START the battle in Strategic Reserves; they may
#           not be set up on the battlefield during deployment.
#   23.02 — at the END of a turn, that player's AIRCRAFT still on the board
#           streak away and return to Strategic Reserves (ingress-only), so
#           they can arrive again on a later turn.
# Both are edition-gated and AIRCRAFT-keyword-gated, so they are completely
# inert without aircraft datasheets (none exist in the current armies).
#
# Drives the REAL GameState helpers, the REAL
# DeploymentPhase._validate_deploy_unit_action, and the REAL
# TurnManager._on_phase_completed(MORALE) end-of-turn hook with a synthetic
# AIRCRAFT unit.
#
# Usage: godot --headless --path . -s tests/test_iss074_aircraft_reserves_11e.gd

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

func _seed_board(gs) -> void:
	# Synthetic AIRCRAFT unit (player 1) + a plain INFANTRY unit (player 1) +
	# an enemy AIRCRAFT (player 2). The aircraft start ON the board (DEPLOYED)
	# so the 23.02 end-of-turn return cycle has something to act on.
	gs.state["units"] = {
		"U_AIR": {"id": "U_AIR", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Fighter", "keywords": ["VEHICLE", "AIRCRAFT", "FLY"], "stats": {}},
			"models": [{"id": "a0", "alive": true, "wounds": 10, "current_wounds": 10, "base_mm": 80, "position": {"x": 500, "y": 500}}]},
		"U_FOOT": {"id": "U_FOOT", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Troops", "keywords": ["INFANTRY"], "stats": {}},
			"models": [{"id": "f0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": {"x": 300, "y": 300}}]},
		"U_ENEMY_AIR": {"id": "U_ENEMY_AIR", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Enemy Jet", "keywords": ["VEHICLE", "AIRCRAFT", "FLY"], "stats": {}},
			"models": [{"id": "z0", "alive": true, "wounds": 10, "current_wounds": 10, "base_mm": 80, "position": {"x": 1500, "y": 1500}}]},
	}
	gs.state["meta"]["active_player"] = 1

func _status(gs, uid: String) -> int:
	return int(gs.state["units"][uid].get("status", -1))

func _has_reserves_error(res: Dictionary) -> bool:
	for e in res.get("errors", []):
		if "Strategic Reserves" in str(e):
			return true
	return false

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss074_aircraft_reserves_11e ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var tm = root.get_node_or_null("TurnManager")
	if gs == null or pm == null or tm == null:
		_check("autoloads reachable", false); _finish(); return

	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition
	var IN_RESERVES := 7  # GameState.UnitStatus.IN_RESERVES

	# ---------------------------------------------------------------------
	print("-- helper: unit_is_aircraft / unit_must_start_in_reserves --")
	gs.state = prev_state.duplicate(true)
	_seed_board(gs)
	GameConstants.edition = 11
	_check("AIRCRAFT keyword detected", gs.unit_is_aircraft("U_AIR"))
	_check("non-AIRCRAFT not detected", not gs.unit_is_aircraft("U_FOOT"))
	_check("e11: AIRCRAFT must start in reserves", gs.unit_must_start_in_reserves("U_AIR"))
	_check("e11: non-AIRCRAFT need not start in reserves", not gs.unit_must_start_in_reserves("U_FOOT"))
	GameConstants.edition = 10
	_check("e10: AIRCRAFT reserve requirement is inert", not gs.unit_must_start_in_reserves("U_AIR"))

	# ---------------------------------------------------------------------
	print("\n-- deployment: AIRCRAFT cannot be set up on the board (23.01) --")
	GameConstants.edition = 11
	gs.state = prev_state.duplicate(true)
	_seed_board(gs)
	# Reset the aircraft to UNDEPLOYED so the deploy validation is meaningful.
	gs.state["units"]["U_AIR"]["status"] = 0
	gs.state["units"]["U_FOOT"]["status"] = 0
	gs.state["board"]["deployment_zones"] = [
		{"player": 1, "poly": [{"x": 0, "y": 0}, {"x": 44, "y": 0}, {"x": 44, "y": 30}, {"x": 0, "y": 30}]},
		{"player": 2, "poly": [{"x": 0, "y": 30}, {"x": 44, "y": 30}, {"x": 44, "y": 60}, {"x": 0, "y": 60}]},
	]
	pm.transition_to_phase(1)  # DEPLOYMENT
	var dp = pm.get_current_phase_instance()

	var deploy_air = {"type": "DEPLOY_UNIT", "unit_id": "U_AIR",
		"model_positions": [Vector2(400, 400)], "model_rotations": [0.0]}
	var v_air_11 = dp._validate_deploy_unit_action(deploy_air)
	_check("e11: deploying AIRCRAFT on the board is rejected", not v_air_11.get("valid", true))
	_check("e11: rejection cites the Strategic Reserves rule (our guard fired)",
		_has_reserves_error(v_air_11), str(v_air_11.get("errors", [])))

	var deploy_foot = {"type": "DEPLOY_UNIT", "unit_id": "U_FOOT",
		"model_positions": [Vector2(300, 300)], "model_rotations": [0.0]}
	var v_foot_11 = dp._validate_deploy_unit_action(deploy_foot)
	_check("e11: deploying a non-AIRCRAFT unit is NOT blocked by the aircraft guard",
		not _has_reserves_error(v_foot_11), str(v_foot_11.get("errors", [])))

	# Placing the AIRCRAFT into Strategic Reserves IS allowed.
	var reserve_air = {"type": "PLACE_IN_RESERVES", "unit_id": "U_AIR", "reserve_type": "strategic_reserves"}
	var v_reserve = dp._validate_place_in_reserves(reserve_air)
	_check("e11: AIRCRAFT MAY be placed in Strategic Reserves", v_reserve.get("valid", false), str(v_reserve))

	# e10 sensitivity: the aircraft guard is inert.
	GameConstants.edition = 10
	var v_air_10 = dp._validate_deploy_unit_action(deploy_air)
	_check("e10: aircraft deploy guard is inert (no Strategic Reserves error)",
		not _has_reserves_error(v_air_10), str(v_air_10.get("errors", [])))

	# ---------------------------------------------------------------------
	print("\n-- end-of-turn return cycle (23.02) --")
	GameConstants.edition = 11
	gs.state = prev_state.duplicate(true)
	_seed_board(gs)
	# Kill the foot unit's only model — it must NOT be touched by the cycle.
	var on_board = gs.get_aircraft_on_board_for_player(1)
	_check("on-board AIRCRAFT for P1 is found", "U_AIR" in on_board, str(on_board))
	_check("non-AIRCRAFT not reported as on-board aircraft", not ("U_FOOT" in on_board))
	_check("enemy AIRCRAFT not reported for P1", not ("U_ENEMY_AIR" in on_board))

	var returned = gs.return_aircraft_to_reserves(1)
	_check("P1 AIRCRAFT returned to reserves", "U_AIR" in returned, str(returned))
	_check("U_AIR status is now IN_RESERVES", _status(gs, "U_AIR") == IN_RESERVES)
	_check("U_AIR reserve_type set to strategic_reserves",
		str(gs.state["units"]["U_AIR"].get("reserve_type", "")) == "strategic_reserves")
	_check("non-AIRCRAFT U_FOOT untouched (still on board)", _status(gs, "U_FOOT") == 2)
	_check("enemy AIRCRAFT untouched by P1's end-of-turn", _status(gs, "U_ENEMY_AIR") == 2)

	# Already-in-reserves aircraft are not re-processed.
	var returned_again = gs.return_aircraft_to_reserves(1)
	_check("aircraft already in reserves are not returned again", returned_again.is_empty(), str(returned_again))

	# e10 sensitivity: the return cycle is a no-op.
	GameConstants.edition = 10
	gs.state = prev_state.duplicate(true)
	_seed_board(gs)
	var returned_10 = gs.return_aircraft_to_reserves(1)
	_check("e10: end-of-turn return cycle is inert", returned_10.is_empty(), str(returned_10))
	_check("e10: U_AIR remains on the board", _status(gs, "U_AIR") == 2)

	# ---------------------------------------------------------------------
	print("\n-- TurnManager MORALE hook drives the cycle (integration) --")
	GameConstants.edition = 11
	gs.state = prev_state.duplicate(true)
	_seed_board(gs)
	gs.state["meta"]["active_player"] = 1
	tm._on_phase_completed(12)  # GameState.Phase.MORALE = 12 (end of turn)
	_check("MORALE hook returned P1's on-board AIRCRAFT to reserves",
		_status(gs, "U_AIR") == IN_RESERVES, "status=%d" % _status(gs, "U_AIR"))
	_check("MORALE hook left the non-AIRCRAFT unit on the board",
		_status(gs, "U_FOOT") == 2)

	gs.state = prev_state
	GameConstants.edition = prev_edition
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
