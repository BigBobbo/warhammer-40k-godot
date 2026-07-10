extends SceneTree

# COORD-1/2/3: AI movement coordination regression tests.
#
# 1. Incoming OC: a unit that already took its move this phase and is en route
#    to an objective covers that objective's OC need, so the NEXT unit is
#    redirected to another objective (with a narratable coordination_note).
# 2. clear_movement_intent removes the incoming OC (failed moves don't count).
# 3. _finalize_movement_decision associates destinations with objectives
#    correctly (moving toward one = claimed; idling far away = not claimed).
# 4. Phase plan caches are per-player (player 1's built plan must not
#    suppress or leak into player 2's).
#
# Run via: godot --headless --path 40k --script tests/test_ai_movement_coordination.gd

const PPI := 40.0  # pixels per inch


func _initialize():
	await create_timer(0.2).timeout
	_run_tests()


func _make_unit(owner: int, name: String, pos: Vector2, oc: int, models: int = 1) -> Dictionary:
	var model_list = []
	for i in range(models):
		model_list.append({
			"id": "m%d" % (i + 1),
			"alive": true,
			"position": {"x": pos.x + i * 30.0, "y": pos.y},
			"base_mm": 32,
		})
	return {
		"owner": owner,
		"models": model_list,
		"meta": {
			"name": name,
			"points": 80,
			"stats": {"move": 6, "objective_control": oc, "toughness": 4, "save": 5},
			"keywords": ["INFANTRY"],
			"weapons": [],
		},
		"flags": {},
	}


func _make_snapshot() -> Dictionary:
	# 2 uncontrolled NML objectives. P2 is the AI side under test.
	return {
		"meta": {"battle_round": 2, "player1_vp": 0, "player2_vp": 0},
		"battle_round": 2,
		"board": {
			"objectives": [
				{"id": "obj_1", "position": {"x": 600.0, "y": 600.0}, "zone": "no_mans_land"},
				{"id": "obj_2", "position": {"x": 1400.0, "y": 600.0}, "zone": "no_mans_land"},
			],
			"terrain_features": [],
		},
		"units": {
			# The unit that ALREADY moved this phase (not in movable_units),
			# en route to obj_1 but still outside control range (151.5px).
			"U_MOVED": _make_unit(2, "Movin' Boyz", Vector2(1000.0, 900.0), 5),
			# The unit whose assignment we test. 5" from obj_1, 15" from obj_2
			# — without coordination it must pick obj_1.
			"U_NEXT": _make_unit(2, "Next Boyz", Vector2(800.0, 600.0), 2),
			# A distant enemy so evaluation paths run (empty enemies = early out).
			"U_ENEMY": _make_unit(1, "Far Guard", Vector2(1400.0, 1900.0), 1),
		},
	}


func _assign_for(snapshot: Dictionary) -> Dictionary:
	var objectives = AIDecisionMaker._get_objectives(snapshot)
	var enemies = AIDecisionMaker._get_enemy_units(snapshot, 2)
	var friendly = AIDecisionMaker._get_units_for_player(snapshot, 2)
	var evals = AIDecisionMaker._evaluate_all_objectives(snapshot, objectives, 2, enemies, friendly, 2)
	var movable = {"U_NEXT": ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]}
	return AIDecisionMaker._assign_units_to_objectives(
		snapshot, movable, evals, objectives, enemies, friendly, 2, 2, [])


func _record_intent_via_funnel(snapshot: Dictionary) -> void:
	# U_MOVED heads to (640, 600) — 1" from obj_1, well inside the 12" claim
	# band and closer than its current position → intent claims obj_1.
	var decision = {
		"type": "BEGIN_NORMAL_MOVE",
		"actor_unit_id": "U_MOVED",
		"_ai_model_destinations": {"m1": [640.0, 600.0]},
		"_ai_description": "Movin' Boyz moves toward obj_1",
	}
	AIDecisionMaker._finalize_movement_decision(decision, snapshot, 2)


func _run_tests():
	print("\n=== COORD: AI movement coordination tests ===\n")
	var passed = 0
	var failed = 0

	# --- Test 1: baseline (no intents) — U_NEXT takes the closer obj_1 ---
	AIDecisionMaker.reset_caches()
	AIDecisionMaker._current_player = 2
	var snap1 = _make_snapshot()
	var a1 = _assign_for(snap1)
	var t1_obj = a1.get("U_NEXT", {}).get("objective_id", "")
	if t1_obj == "obj_1":
		print("[PASS] baseline: U_NEXT assigned to nearby obj_1 (no intents recorded)")
		passed += 1
	else:
		print("[FAIL] baseline: expected U_NEXT -> obj_1, got '%s' (assignment: %s)" % [t1_obj, str(a1.get("U_NEXT", {}))])
		failed += 1

	# --- Test 2: with U_MOVED's intent en route to obj_1, U_NEXT redirects to obj_2 ---
	AIDecisionMaker.reset_caches()
	AIDecisionMaker._current_player = 2
	var snap2 = _make_snapshot()
	_record_intent_via_funnel(snap2)
	var intents = AIDecisionMaker._get_movement_intents(2)
	if intents.has("U_MOVED") and intents["U_MOVED"].get("objective_id", "") == "obj_1":
		print("[PASS] funnel recorded U_MOVED intent -> obj_1 (oc=%d)" % int(intents["U_MOVED"].get("oc", 0)))
		passed += 1
	else:
		print("[FAIL] funnel intent wrong: %s" % str(intents))
		failed += 1

	var a2 = _assign_for(snap2)
	var t2_obj = a2.get("U_NEXT", {}).get("objective_id", "")
	if t2_obj == "obj_2":
		print("[PASS] coordination: U_NEXT redirected to obj_2 (obj_1 covered by incoming OC)")
		passed += 1
	else:
		print("[FAIL] coordination: expected U_NEXT -> obj_2, got '%s' (assignment: %s)" % [t2_obj, str(a2.get("U_NEXT", {}))])
		failed += 1

	var note = a2.get("U_NEXT", {}).get("coordination_note", "")
	if "obj_1" in note and "obj_2" in note:
		print("[PASS] coordination_note narrates the redirect: '%s'" % note)
		passed += 1
	else:
		print("[FAIL] coordination_note missing/wrong: '%s'" % note)
		failed += 1

	# --- Test 3: clearing the intent (failed move) restores baseline choice ---
	AIDecisionMaker.clear_movement_intent(2, "U_MOVED")
	var a3 = _assign_for(snap2)
	var t3_obj = a3.get("U_NEXT", {}).get("objective_id", "")
	if t3_obj == "obj_1":
		print("[PASS] clear_movement_intent: U_NEXT back to obj_1 after intent cleared")
		passed += 1
	else:
		print("[FAIL] clear_movement_intent: expected obj_1, got '%s'" % t3_obj)
		failed += 1

	# --- Test 4: stationary far from any objective claims nothing ---
	AIDecisionMaker.reset_caches()
	AIDecisionMaker._current_player = 2
	var snap4 = _make_snapshot()
	var idle_decision = {
		"type": "REMAIN_STATIONARY",
		"actor_unit_id": "U_MOVED",
		"_ai_description": "Movin' Boyz holds position",
	}
	AIDecisionMaker._finalize_movement_decision(idle_decision, snap4, 2)
	var idle_intents = AIDecisionMaker._get_movement_intents(2)
	if idle_intents.get("U_MOVED", {}).get("objective_id", "x") == "":
		print("[PASS] stationary unit far from objectives claims no objective")
		passed += 1
	else:
		print("[FAIL] stationary unit claimed '%s'" % str(idle_intents.get("U_MOVED", {})))
		failed += 1

	# --- Test 5: phase plan caches are per-player ---
	AIDecisionMaker.reset_caches()
	AIDecisionMaker._phase_plan[1] = {"charge_target_ids": ["U_ENEMY"], "charge_intent": {"U_X": {"target_id": "U_ENEMY"}}}
	AIDecisionMaker._phase_plan_built[1] = true
	var p2_plan_empty = AIDecisionMaker._get_phase_plan(2).is_empty()
	var p2_not_built = not AIDecisionMaker._phase_plan_built.get(2, false)
	var p2_no_leak = not AIDecisionMaker._is_charge_target("U_ENEMY", 2)
	var p1_sees_own = AIDecisionMaker._is_charge_target("U_ENEMY", 1)
	if p2_plan_empty and p2_not_built and p2_no_leak and p1_sees_own:
		print("[PASS] phase plan is per-player: P1's built plan neither leaks to nor suppresses P2's")
		passed += 1
	else:
		print("[FAIL] phase plan isolation: p2_empty=%s p2_not_built=%s p2_no_leak=%s p1_sees_own=%s" % [
			p2_plan_empty, p2_not_built, p2_no_leak, p1_sees_own])
		failed += 1

	AIDecisionMaker.reset_caches()
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
