extends SceneTree

# Issue #392: validate VIGILANCE ETERNAL sticky-objective behaviour.
#
# Test 1: with effect_sticky_objective_control = obj_id on an alive friendly
#         unit AND no OC presence, the controller is the locking player.
# Test 2: when the opponent has OC presence on the same objective, control
#         transfers to them AND the flag is cleared.
# Test 3: find_nearest_controlled_objective returns the right id when the
#         unit overlaps a controlled objective, "" when no overlap.
# Test 4: lock_objective_via_stratagem refuses to lock an objective the
#         player doesn't currently control.
#
# Run via: godot --headless --path 40k --script tests/test_vigilance_eternal_sticky_392.gd

var _mm = null
var _gs = null


func _initialize():
	await create_timer(0.1).timeout
	_mm = root.get_node_or_null("MissionManager")
	_gs = root.get_node_or_null("GameState")
	if _mm == null or _gs == null:
		print("FAIL: missing MissionManager or GameState autoload")
		quit(1)
		return
	_run_tests()


func _run_tests():
	print("\n=== Issue #392: VIGILANCE ETERNAL sticky-objective behaviour ===\n")
	var passed = 0
	var failed = 0

	# --- Setup: stub out an objective and units ---
	var obj_pos = Vector2(500, 500)
	var objective = {
		"id": "obj_test",
		"position": {"x": 500, "y": 500}
	}

	# Custodes Battleline unit (Player 1) far from objective
	var custodes_unit = _make_unit("U_CUSTGUARD_TEST", 1, Vector2(2000, 2000), 1)
	# Make Player 1's unit hold the sticky lock
	custodes_unit.flags["effect_sticky_objective_control"] = "obj_test"
	# Ork unit (Player 2), far from objective initially
	var ork_unit = _make_unit("U_ORK_TEST", 2, Vector2(3000, 3000), 5)

	# Seed GameState (the new flag-check loop reads from here)
	_gs.state.units = {"U_CUSTGUARD_TEST": custodes_unit, "U_ORK_TEST": ork_unit}
	_gs.state.board = {"objectives": [objective]}
	_mm.objective_control_state = {"obj_test": 1}

	# --- Test 1: sticky flag holds objective when no OC presence ---
	print("--- Test 1: sticky flag = obj_test holds objective for Player 1 (no OC presence) ---")
	var c1 = _mm._check_objective_control(_pos_obj(objective), _gs.state.units)
	if c1 == 1:
		print("[PASS] sticky flag retains Player 1 control (returned %d)" % c1)
		passed += 1
	else:
		print("[FAIL] expected 1, got %d" % c1)
		failed += 1

	# --- Test 2: opponent OC takes control AND clears flag ---
	print("\n--- Test 2: Ork unit moves into range with OC=5; control transfers, flag cleared ---")
	# Move Ork model on top of objective to trigger OC presence
	ork_unit.models[0].position = {"x": 500, "y": 500}
	var c2 = _mm._check_objective_control(_pos_obj(objective), _gs.state.units)
	if c2 == 2:
		print("[PASS] control transferred to Player 2 via OC presence (returned %d)" % c2)
		passed += 1
	else:
		print("[FAIL] expected 2, got %d" % c2)
		failed += 1
	if not custodes_unit.flags.has("effect_sticky_objective_control"):
		print("[PASS] effect_sticky_objective_control flag cleared from U_CUSTGUARD_TEST")
		passed += 1
	else:
		print("[FAIL] flag still present on U_CUSTGUARD_TEST: %s" % str(custodes_unit.flags))
		failed += 1

	# --- Test 3: find_nearest_controlled_objective ---
	print("\n--- Test 3: find_nearest_controlled_objective returns correct id ---")
	# Put Custodes in range of objective, owner controls it.
	custodes_unit.models[0].position = {"x": 510, "y": 500}
	# Reset flag for this test (was cleared in test 2)
	custodes_unit.flags = {}
	# Reset Ork pos so it doesn't claim OC
	ork_unit.models[0].position = {"x": 3000, "y": 3000}
	_mm.objective_control_state = {"obj_test": 1}
	var found = _mm.find_nearest_controlled_objective("U_CUSTGUARD_TEST")
	if found == "obj_test":
		print("[PASS] found = '%s'" % found)
		passed += 1
	else:
		print("[FAIL] expected 'obj_test', got '%s'" % found)
		failed += 1

	# Out of range: 5" away (way beyond 3.78" control radius)
	custodes_unit.models[0].position = {"x": 1500, "y": 500}
	var found_oor = _mm.find_nearest_controlled_objective("U_CUSTGUARD_TEST")
	if found_oor == "":
		print("[PASS] out-of-range returns empty string")
		passed += 1
	else:
		print("[FAIL] out-of-range expected '', got '%s'" % found_oor)
		failed += 1

	# --- Test 4: lock_objective_via_stratagem refuses non-controlled objective ---
	print("\n--- Test 4: lock_objective_via_stratagem refuses to lock a non-controlled objective ---")
	_mm._sticky_objectives.clear()
	_mm.objective_control_state = {"obj_test": 2}  # Ork player controls
	var locked = _mm.lock_objective_via_stratagem("obj_test", 1, "U_CUSTGUARD_TEST")
	if not locked:
		print("[PASS] refused to lock obj_test for Player 1 (controlled by 2)")
		passed += 1
	else:
		print("[FAIL] should not have locked")
		failed += 1
	if not _mm._sticky_objectives.has("obj_test"):
		print("[PASS] _sticky_objectives unchanged")
		passed += 1
	else:
		print("[FAIL] _sticky_objectives now has obj_test")
		failed += 1

	# --- Summary ---
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		quit(1)
	else:
		quit(0)


func _make_unit(unit_id: String, owner: int, pos: Vector2, oc: int) -> Dictionary:
	return {
		"id": unit_id,
		"owner": owner,
		"status": 2,  # DEPLOYED — required for OC contribution
		"meta": {
			"name": unit_id,
			"keywords": [],
			"stats": {"objective_control": oc, "move": 6, "toughness": 4, "save": 4, "wounds": 1}
		},
		"models": [
			{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1, "position": {"x": pos.x, "y": pos.y}, "base_mm": 32}
		],
		"flags": {}
	}


func _pos_obj(o: Dictionary) -> Dictionary:
	# _check_objective_control reads `objective.position` as a Vector2.
	var copy = o.duplicate(true)
	copy.position = Vector2(o.position.x, o.position.y)
	return copy
