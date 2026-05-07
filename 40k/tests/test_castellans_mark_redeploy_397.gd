extends SceneTree

# Issue #397: validate the resolution-side Castellan's Mark API on
# DeploymentPhase. The API supports two redeploy actions per unit:
#   1) TO_RESERVES — place unit into Strategic Reserves (bypass cap)
#   2) REPLACE_POSITION — assign new model positions on the table
# Callers may submit at most 2 entries (Wahapedia "up to two" cap).
#
# Run via: godot --headless --path 40k --script tests/test_castellans_mark_redeploy_397.gd

var _gs = null
var _dp = null


func _initialize():
	await create_timer(0.1).timeout
	_gs = root.get_node_or_null("GameState")
	if _gs == null:
		print("FAIL: GameState autoload missing")
		quit(1)
		return
	var DeploymentPhaseScript = load("res://phases/DeploymentPhase.gd")
	_dp = DeploymentPhaseScript.new()
	root.add_child(_dp)
	_run_tests()


func _run_tests():
	print("\n=== Issue #397: Castellan's Mark resolution-side redeploy API ===\n")
	var passed = 0
	var failed = 0

	# --- Setup: 4 Custodes units, 1 with Castellan's Mark, 1 Anathema Psykana, 1 Ork ---
	_seed_state()

	# --- Test 1: find_castellan_mark_bearer_player returns the Custodes player ---
	print("--- Test 1: find_castellan_mark_bearer_player → 1 ---")
	var bearer = _dp.find_castellan_mark_bearer_player()
	if bearer == 1:
		print("[PASS] bearer = 1")
		passed += 1
	else:
		print("[FAIL] expected 1, got %d" % bearer)
		failed += 1

	# --- Test 2: get_castellan_eligible_units excludes Anathema and other player ---
	print("\n--- Test 2: eligible units excludes Anathema Psykana, ork, undeployed ---")
	var eligible = _dp.get_castellan_eligible_units(1)
	var has_guard = "U_GUARD" in eligible
	var has_blade = "U_BLADE_CHAMPION" in eligible
	var has_witch = "U_WITCHSEEKERS" in eligible  # Anathema Psykana — should be excluded
	var has_ork = "U_BOYZ" in eligible  # other player — excluded
	var has_undeployed = "U_RESERVED_GUARD" in eligible  # not deployed — excluded
	if has_guard and has_blade and not has_witch and not has_ork and not has_undeployed:
		print("[PASS] eligible = %s" % str(eligible))
		passed += 1
	else:
		print("[FAIL] eligible incorrect: %s" % str(eligible))
		failed += 1

	# --- Test 3: execute redeploy: 1 to Reserves, 1 to new position ---
	print("\n--- Test 3: redeploy U_GUARD→Reserves and U_BLADE_CHAMPION→new pos ---")
	var redeploys = [
		{"unit_id": "U_GUARD", "action": "TO_RESERVES"},
		{"unit_id": "U_BLADE_CHAMPION", "action": "REPLACE_POSITION", "positions": [{"x": 100, "y": 100}]}
	]
	var result = _dp.execute_castellan_redeploy(1, redeploys)
	if result.success and result.applied.size() == 2:
		print("[PASS] both redeploys applied")
		passed += 1
	else:
		print("[FAIL] result=%s" % str(result))
		failed += 1

	# Verify state mutations
	var guard = _gs.state.units.U_GUARD
	if guard.status == GameStateData.UnitStatus.IN_RESERVES and guard.get("reserve_type", "") == "strategic_reserves":
		print("[PASS] U_GUARD status=IN_RESERVES, reserve_type=strategic_reserves")
		passed += 1
	else:
		print("[FAIL] U_GUARD status=%d reserve_type=%s" % [guard.status, str(guard.get("reserve_type", ""))])
		failed += 1
	# Models should not have positions
	var has_pos = false
	for m in guard.models:
		if m.has("position"):
			has_pos = true
			break
	if not has_pos:
		print("[PASS] U_GUARD model positions cleared")
		passed += 1
	else:
		print("[FAIL] U_GUARD models still have positions")
		failed += 1

	var blade = _gs.state.units.U_BLADE_CHAMPION
	if blade.models[0].position.x == 100 and blade.models[0].position.y == 100:
		print("[PASS] U_BLADE_CHAMPION model[0] at (100, 100)")
		passed += 1
	else:
		print("[FAIL] U_BLADE_CHAMPION model[0] at (%s, %s)" % [str(blade.models[0].position.x), str(blade.models[0].position.y)])
		failed += 1

	# --- Test 4: more than 2 redeploys is rejected ---
	print("\n--- Test 4: >2 redeploys rejected ---")
	_seed_state()  # reset
	var too_many = [
		{"unit_id": "U_GUARD", "action": "TO_RESERVES"},
		{"unit_id": "U_BLADE_CHAMPION", "action": "TO_RESERVES"},
		{"unit_id": "U_BIKES", "action": "TO_RESERVES"}
	]
	var r4 = _dp.execute_castellan_redeploy(1, too_many)
	if not r4.success and r4.errors.size() > 0:
		print("[PASS] rejected (%s)" % str(r4.errors))
		passed += 1
	else:
		print("[FAIL] should have rejected")
		failed += 1

	# --- Test 5: ineligible unit (Anathema Psykana) is rejected ---
	print("\n--- Test 5: Anathema Psykana redeploy is rejected ---")
	var bad = [{"unit_id": "U_WITCHSEEKERS", "action": "TO_RESERVES"}]
	var r5 = _dp.execute_castellan_redeploy(1, bad)
	if not r5.success and r5.errors.size() > 0:
		print("[PASS] Anathema rejected: %s" % str(r5.errors))
		passed += 1
	else:
		print("[FAIL] Anathema should have been rejected; result=%s" % str(r5))
		failed += 1

	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		quit(1)
	else:
		quit(0)


func _seed_state():
	var units = {
		"U_SHIELD_CAPTAIN": _make_unit("U_SHIELD_CAPTAIN", 1, ["ADEPTUS CUSTODES", "INFANTRY", "CHARACTER"], GameStateData.UnitStatus.DEPLOYED, [{"name": "Castellan's Mark"}]),
		"U_GUARD": _make_unit("U_GUARD", 1, ["ADEPTUS CUSTODES", "INFANTRY"], GameStateData.UnitStatus.DEPLOYED, []),
		"U_BLADE_CHAMPION": _make_unit("U_BLADE_CHAMPION", 1, ["ADEPTUS CUSTODES", "INFANTRY", "CHARACTER"], GameStateData.UnitStatus.DEPLOYED, []),
		"U_BIKES": _make_unit("U_BIKES", 1, ["ADEPTUS CUSTODES", "MOUNTED"], GameStateData.UnitStatus.DEPLOYED, []),
		"U_WITCHSEEKERS": _make_unit("U_WITCHSEEKERS", 1, ["ADEPTUS CUSTODES", "ANATHEMA PSYKANA", "INFANTRY"], GameStateData.UnitStatus.DEPLOYED, []),
		"U_BOYZ": _make_unit("U_BOYZ", 2, ["ORKS", "INFANTRY"], GameStateData.UnitStatus.DEPLOYED, []),
		"U_RESERVED_GUARD": _make_unit("U_RESERVED_GUARD", 1, ["ADEPTUS CUSTODES", "INFANTRY"], GameStateData.UnitStatus.IN_RESERVES, [])
	}
	_gs.state.units = units
	_gs.state.meta = {"phase": GameStateData.Phase.DEPLOYMENT, "active_player": 1, "battle_round": 0}


func _make_unit(unit_id: String, owner: int, keywords: Array, status: int, enhancements: Array) -> Dictionary:
	return {
		"id": unit_id,
		"owner": owner,
		"status": status,
		"meta": {
			"name": unit_id,
			"keywords": keywords,
			"enhancements": enhancements,
			"stats": {"move": 6, "toughness": 5, "save": 3, "wounds": 3, "objective_control": 1},
			"weapons": [],
			"abilities": []
		},
		"models": [{"id": "m1", "alive": true, "wounds": 3, "current_wounds": 3, "position": {"x": 50, "y": 50}, "base_mm": 32}],
		"flags": {}
	}
