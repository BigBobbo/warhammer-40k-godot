extends SceneTree

# COORD-4/5: Persistent movement battle plan tests.
#
# The army-wide unit->objective assignment must be computed once per movement
# phase and CONSUMED as units act — not re-solved before every action — so the
# plan the game log announces is the plan that actually executes. Also covers:
#   * consume/replan: a unit reappearing after acting forces a narrated re-plan
#   * support spreading: leftover units fan out instead of stacking on one marker
#   * projected contest pressure: an "empty" objective one enemy move away
#     sizes its OC need against the incoming enemy, not just current holders
#   * attack conversion: melee seekers announce ATTACK in the plan and free
#     their objective's OC need for backfill
#
# Run with: godot --headless --script tests/test_ai_battle_plan.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== COORD-4/5: AI battle plan tests ===\n")
	_run_tests()
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	if _fail_count > 0:
		print("SOME TESTS FAILED")
	else:
		print("ALL TESTS PASSED")
	quit(1 if _fail_count > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("[PASS] %s" % message)
	else:
		_fail_count += 1
		print("[FAIL] %s" % message)

func _make_snapshot(battle_round: int = 1) -> Dictionary:
	return {
		"battle_round": battle_round,
		"meta": {"battle_round": battle_round},
		"board": {
			"objectives": [
				{"id": "obj_1", "position": Vector2(600, 1400), "zone": "no_mans_land"},
				{"id": "obj_2", "position": Vector2(1600, 1400), "zone": "no_mans_land"},
				{"id": "obj_3", "position": Vector2(1100, 800), "zone": "no_mans_land"},
			],
			"terrain_features": [],
			"deployment_zones": []
		},
		"units": {}
	}

func _add_unit(snapshot: Dictionary, unit_id: String, owner: int, pos: Vector2,
		unit_name: String, oc: int = 2, move: int = 6, num_models: int = 5,
		keywords: Array = ["INFANTRY"], weapons: Array = []) -> void:
	var models = []
	for i in range(num_models):
		models.append({
			"id": "%s_m%d" % [unit_id, i + 1],
			"alive": true,
			"base_mm": 32,
			"base_type": "circular",
			"base_dimensions": {},
			"position": Vector2(pos.x + i * 40, pos.y),
			"wounds": 1,
			"current_wounds": 1
		})
	snapshot.units[unit_id] = {
		"id": unit_id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": unit_name,
			"stats": {"move": move, "toughness": 4, "save": 4, "wounds": 1,
				"leadership": 6, "objective_control": oc, "oc": oc},
			"keywords": keywords,
			"weapons": weapons,
			"points": 80
		},
		"models": models,
		"state": {},
		"flags": {}
	}

func _make_melee_weapon() -> Dictionary:
	return {"name": "Choppa", "type": "Melee", "weapon_skill": "3",
		"strength": "5", "ap": "-1", "damage": "1", "attacks": "3"}

func _movement_actions(unit_ids: Array) -> Array:
	var actions = []
	for uid in unit_ids:
		for t in ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]:
			actions.append({"type": t, "actor_unit_id": uid})
	return actions

func _run_tests():
	test_plan_persists_across_decide_calls()
	test_consumed_unit_reappearing_forces_replan()
	test_new_movable_unit_forces_replan()
	test_support_units_spread_across_objectives()
	test_projected_contest_raises_need()
	test_melee_seeker_announced_as_attack()

# ---------------------------------------------------------------------------

func test_plan_persists_across_decide_calls():
	print("\n--- plan persists across decide() calls ---")
	AIDecisionMaker.reset_caches()
	AIDecisionMaker._current_player = 2
	var snap = _make_snapshot()
	_add_unit(snap, "u1", 2, Vector2(600, 2000), "Boyz A", 2)
	_add_unit(snap, "u2", 2, Vector2(1600, 2000), "Boyz B", 2)
	_add_unit(snap, "u3", 2, Vector2(1100, 2000), "Boyz C", 2)

	var d1 = AIDecisionMaker._decide_movement(snap, _movement_actions(["u1", "u2", "u3"]), 2)
	var plan_after_first = AIDecisionMaker._turn_movement_plan.get(2, {})
	_check(not plan_after_first.is_empty(), "plan stored after first decide")
	var planned_objs = {}
	for uid in plan_after_first.get("assignments", {}):
		planned_objs[uid] = plan_after_first.assignments[uid].get("objective_id", "")

	# Simulate the first unit having acted: remove it from movable and decide again
	var acted_uid = d1.get("actor_unit_id", "")
	_check(acted_uid != "", "first decide returned a unit action (%s)" % d1.get("type", "?"))
	var remaining = ["u1", "u2", "u3"]
	remaining.erase(acted_uid)
	var d2 = AIDecisionMaker._decide_movement(snap, _movement_actions(remaining), 2)
	var plan_after_second = AIDecisionMaker._turn_movement_plan.get(2, {})
	_check(int(plan_after_second.get("replans", 99)) == int(plan_after_first.get("replans", -2)),
		"no re-plan between consecutive unit actions (replans stayed %d)" % int(plan_after_second.get("replans", -1)))
	var d2_uid = d2.get("actor_unit_id", "")
	if plan_after_second.get("assignments", {}).has(d2_uid):
		var still_same = plan_after_second.assignments[d2_uid].get("objective_id", "") == planned_objs.get(d2_uid, "?")
		_check(still_same, "second unit executed its ORIGINAL planned assignment (%s)" % planned_objs.get(d2_uid, "?"))

func test_consumed_unit_reappearing_forces_replan():
	print("\n--- consumed unit reappearing forces a re-plan ---")
	AIDecisionMaker.reset_caches()
	AIDecisionMaker._current_player = 2
	var snap = _make_snapshot()
	_add_unit(snap, "u1", 2, Vector2(600, 2000), "Boyz A", 2)
	var d1 = AIDecisionMaker._decide_movement(snap, _movement_actions(["u1"]), 2)
	var replans_before = int(AIDecisionMaker._turn_movement_plan.get(2, {}).get("replans", -1))
	_check(d1.get("actor_unit_id", "") == "u1", "u1 acted and consumed its plan entry")
	# u1 offered again (like a failed move being re-offered): must re-plan, not replay
	var d2 = AIDecisionMaker._decide_movement(snap, _movement_actions(["u1"]), 2)
	var replans_after = int(AIDecisionMaker._turn_movement_plan.get(2, {}).get("replans", -1))
	_check(replans_after == replans_before + 1, "re-plan triggered (replans %d -> %d)" % [replans_before, replans_after])
	_check(d2.get("actor_unit_id", "") == "u1", "re-planned decision still acts u1")

func test_new_movable_unit_forces_replan():
	print("\n--- new movable unit forces a narrated re-plan ---")
	AIDecisionMaker.reset_caches()
	AIDecisionMaker._current_player = 2
	var snap = _make_snapshot()
	_add_unit(snap, "u1", 2, Vector2(600, 2000), "Boyz A", 2)
	_add_unit(snap, "u2", 2, Vector2(1600, 2000), "Boyz B", 2)
	AIDecisionMaker._decide_movement(snap, _movement_actions(["u1", "u2"]), 2)
	var replans_before = int(AIDecisionMaker._turn_movement_plan.get(2, {}).get("replans", -1))
	# A third unit appears (e.g. disembark) — not in the plan
	_add_unit(snap, "u3", 2, Vector2(1100, 2000), "Disembarked Boyz", 2)
	AIDecisionMaker._decide_movement(snap, _movement_actions(["u2", "u3"]), 2)
	var replans_after = int(AIDecisionMaker._turn_movement_plan.get(2, {}).get("replans", -1))
	_check(replans_after == replans_before + 1, "new unit triggered re-plan (replans %d -> %d)" % [replans_before, replans_after])
	_check(AIDecisionMaker._turn_movement_plan.get(2, {}).get("assignments", {}).has("u3"),
		"re-planned assignments include the new unit")

func test_support_units_spread_across_objectives():
	print("\n--- leftover support units spread instead of stacking ---")
	AIDecisionMaker.reset_caches()
	AIDecisionMaker._current_player = 2
	var snap = _make_snapshot(2)
	# 6 identical units clustered together, 3 objectives, no enemies:
	# needs are 1 OC each, so 3 units get capture slots and 3 are leftovers.
	for i in range(6):
		_add_unit(snap, "u%d" % i, 2, Vector2(900 + i * 60, 2000), "Squad %d" % i, 2)
	var movable = {}
	var unit_ids = []
	for i in range(6):
		movable["u%d" % i] = ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]
		unit_ids.append("u%d" % i)
	var objectives = AIDecisionMaker._get_objectives(snap)
	var friendlies = {}
	for uid in unit_ids:
		friendlies[uid] = snap.units[uid]
	var evals = AIDecisionMaker._evaluate_all_objectives(snap, objectives, 2, {}, friendlies, 2)
	var assignments = AIDecisionMaker._assign_units_to_objectives(snap, movable, evals, objectives, {}, friendlies, 2, 2)
	var per_obj = {}
	for uid in assignments:
		var oid = assignments[uid].get("objective_id", "")
		if oid.begins_with("obj"):
			per_obj[oid] = per_obj.get(oid, 0) + 1
	var max_stack = 0
	for oid in per_obj:
		max_stack = max(max_stack, per_obj[oid])
	print("    distribution: %s" % str(per_obj))
	_check(per_obj.size() >= 3, "all 3 objectives got at least one unit (got %d)" % per_obj.size())
	_check(max_stack <= 3, "no objective got more than 3 of 6 units (max %d)" % max_stack)

func test_projected_contest_raises_need():
	print("\n--- projected enemy pressure raises an empty objective's OC need ---")
	AIDecisionMaker.reset_caches()
	AIDecisionMaker._current_player = 2
	var snap = _make_snapshot(2)
	# Enemy unit 8" from obj_1 (within its 6" move + 2" slack + 1.2" control range)
	_add_unit(snap, "e1", 1, Vector2(600, 1400 - 8 * 40), "Enemy Guard", 2, 6)
	var objectives = AIDecisionMaker._get_objectives(snap)
	var enemies = {"e1": snap.units["e1"]}
	var evals = AIDecisionMaker._evaluate_all_objectives(snap, objectives, 2, enemies, {}, 2)
	var obj1_eval = {}
	for e in evals:
		if e.id == "obj_1":
			obj1_eval = e
			break
	_check(obj1_eval.get("state", "") == "uncontrolled", "obj_1 currently reads uncontrolled")
	_check(obj1_eval.get("projected_enemy_oc", 0) > 0,
		"obj_1 projects incoming enemy OC (%d)" % obj1_eval.get("projected_enemy_oc", 0))

func test_melee_seeker_announced_as_attack():
	print("\n--- melee seeker converted to an announced ATTACK assignment ---")
	AIDecisionMaker.reset_caches()
	AIDecisionMaker._current_player = 2
	var snap = _make_snapshot(2)
	# Pure-melee unit with an enemy ~8" away (well within move+charge reach)
	_add_unit(snap, "boyz", 2, Vector2(600, 1720), "Slugga Boyz", 2, 6, 5, ["INFANTRY"], [_make_melee_weapon()])
	_add_unit(snap, "e1", 1, Vector2(600, 1400), "Enemy Squad", 2, 6)
	var movable = {"boyz": ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]}
	var objectives = AIDecisionMaker._get_objectives(snap)
	var enemies = {"e1": snap.units["e1"]}
	var friendlies = {"boyz": snap.units["boyz"]}
	var evals = AIDecisionMaker._evaluate_all_objectives(snap, objectives, 2, enemies, friendlies, 2)
	var assignments = AIDecisionMaker._assign_units_to_objectives(snap, movable, evals, objectives, enemies, friendlies, 2, 2)
	var a = assignments.get("boyz", {})
	print("    assignment: %s" % str(a))
	_check(a.get("action", "") == "attack", "melee seeker's plan entry is ATTACK (got '%s')" % a.get("action", ""))
	_check(a.get("attack_target_id", "") == "e1", "attack targets the nearby enemy")
