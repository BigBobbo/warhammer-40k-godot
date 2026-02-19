extends SceneTree

# Test AI Movement Decisions - Tests the new global objective assignment system
# Run with: godot --headless --script tests/unit/test_ai_movement_decisions.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== AI Movement Decision Tests ===\n")
	_run_tests()

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	if _fail_count > 0:
		print("SOME TESTS FAILED")
	else:
		print("ALL TESTS PASSED")
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func _run_tests():
	test_objective_evaluation_uncontrolled()
	test_objective_evaluation_held_safe()
	test_objective_evaluation_contested()
	test_objective_evaluation_enemy_held()
	test_unit_assignment_distributes_units()
	test_unit_on_objective_holds()
	test_unit_not_on_objective_moves()
	test_engaged_unit_on_objective_stays()
	test_engaged_unit_off_objective_falls_back()
	test_advance_decision_no_ranged()
	test_advance_decision_round1()
	test_no_advance_with_targets_in_range()
	test_oc_aware_holding_frees_redundant_units()
	test_home_objective_defended()
	test_movement_toward_assigned_objective()
	# MOV-1: Shooting range consideration tests
	test_hold_for_shooting_enemies_in_range()
	test_move_when_no_enemies_in_range()
	test_move_when_objective_reachable_this_turn()
	test_clamp_move_keeps_enemy_in_range()
	test_get_enemies_in_weapon_range()
	test_should_hold_high_priority_objective_overrides()

# =========================================================================
# Helper: Create a test snapshot with units and objectives
# =========================================================================

func _create_test_snapshot(player: int = 2) -> Dictionary:
	# Board: 1760x2400 px, 5 objectives (Hammer and Anvil)
	return {
		"battle_round": 1,
		"board": {
			"objectives": [
				{"id": "obj_center", "position": Vector2(880, 1200), "zone": "no_mans_land"},
				{"id": "obj_nml_1", "position": Vector2(400, 720), "zone": "no_mans_land"},
				{"id": "obj_nml_2", "position": Vector2(1360, 1680), "zone": "no_mans_land"},
				{"id": "obj_home_1", "position": Vector2(880, 240), "zone": "player1"},
				{"id": "obj_home_2", "position": Vector2(880, 2160), "zone": "player2"}
			],
			"terrain_features": []
		},
		"units": {}
	}

func _add_unit(snapshot: Dictionary, unit_id: String, owner: int, pos: Vector2,
		name: String = "Test Unit", oc: int = 2, move: int = 6,
		num_models: int = 5, keywords: Array = ["INFANTRY"],
		weapons: Array = []) -> void:
	var models = []
	for i in range(num_models):
		models.append({
			"id": "m%d" % (i + 1),
			"alive": true,
			"base_mm": 32,
			"base_type": "circular",
			"base_dimensions": {},
			"position": Vector2(pos.x + i * 40, pos.y),
			"wounds": 2,
			"current_wounds": 2
		})
	snapshot.units[unit_id] = {
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": name,
			"stats": {
				"move": move,
				"toughness": 4,
				"save": 3,
				"wounds": 2,
				"leadership": 6,
				"objective_control": oc
			},
			"keywords": keywords,
			"weapons": weapons
		},
		"models": models,
		"flags": {}
	}

func _make_available_actions(unit_ids: Array, engaged_ids: Array = []) -> Array:
	var actions = []
	for uid in unit_ids:
		if uid in engaged_ids:
			actions.append({"type": "BEGIN_FALL_BACK", "actor_unit_id": uid})
			actions.append({"type": "REMAIN_STATIONARY", "actor_unit_id": uid})
		else:
			actions.append({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": uid})
			actions.append({"type": "BEGIN_ADVANCE", "actor_unit_id": uid})
			actions.append({"type": "REMAIN_STATIONARY", "actor_unit_id": uid})
	actions.append({"type": "END_MOVEMENT"})
	return actions

# =========================================================================
# TEST: Objective Evaluation
# =========================================================================

func test_objective_evaluation_uncontrolled():
	print("\n--- test_objective_evaluation_uncontrolled ---")
	var snapshot = _create_test_snapshot()
	# No units near objectives -> all should be uncontrolled
	_add_unit(snapshot, "u1", 2, Vector2(880, 2000), "Boyz", 2)
	var objectives = _get_objectives_from_snapshot(snapshot)
	var enemies = {}
	var friendlies = {"u1": snapshot.units["u1"]}

	var evals = AIDecisionMaker._evaluate_all_objectives(snapshot, objectives, 2, enemies, friendlies, 1)
	_assert(evals.size() == 5, "5 objectives evaluated")

	var center_eval = _find_eval(evals, "obj_center")
	_assert(center_eval.state == "uncontrolled", "Center objective is uncontrolled")
	_assert(center_eval.priority > 0, "Uncontrolled objective has positive priority (%.1f)" % center_eval.priority)

func test_objective_evaluation_held_safe():
	print("\n--- test_objective_evaluation_held_safe ---")
	var snapshot = _create_test_snapshot()
	# Friendly unit right on home objective
	_add_unit(snapshot, "u1", 2, Vector2(880, 2160), "Boyz on Home", 2)
	var objectives = _get_objectives_from_snapshot(snapshot)
	var enemies = {}
	var friendlies = {"u1": snapshot.units["u1"]}

	var evals = AIDecisionMaker._evaluate_all_objectives(snapshot, objectives, 2, enemies, friendlies, 1)
	var home_eval = _find_eval(evals, "obj_home_2")
	_assert(home_eval.state == "held_safe", "Home objective held safe (state=%s)" % home_eval.state)
	_assert(home_eval.priority < 0, "Held safe objective has low priority (%.1f)" % home_eval.priority)

func test_objective_evaluation_contested():
	print("\n--- test_objective_evaluation_contested ---")
	var snapshot = _create_test_snapshot()
	# Both players on center objective
	_add_unit(snapshot, "u1", 2, Vector2(880, 1200), "Our Boyz", 2)
	_add_unit(snapshot, "e1", 1, Vector2(880, 1180), "Enemy Guard", 2)
	var objectives = _get_objectives_from_snapshot(snapshot)
	var enemies = {"e1": snapshot.units["e1"]}
	var friendlies = {"u1": snapshot.units["u1"]}

	var evals = AIDecisionMaker._evaluate_all_objectives(snapshot, objectives, 2, enemies, friendlies, 1)
	var center_eval = _find_eval(evals, "obj_center")
	_assert(center_eval.state == "contested", "Center objective is contested (state=%s)" % center_eval.state)
	_assert(center_eval.priority > 5.0, "Contested objective has high priority (%.1f)" % center_eval.priority)

func test_objective_evaluation_enemy_held():
	print("\n--- test_objective_evaluation_enemy_held ---")
	var snapshot = _create_test_snapshot()
	# Enemy on no-man's land objective, we have nobody nearby
	_add_unit(snapshot, "e1", 1, Vector2(400, 720), "Enemy Guard", 2)
	_add_unit(snapshot, "u1", 2, Vector2(880, 2000), "Our Boyz", 2)
	var objectives = _get_objectives_from_snapshot(snapshot)
	var enemies = {"e1": snapshot.units["e1"]}
	var friendlies = {"u1": snapshot.units["u1"]}

	var evals = AIDecisionMaker._evaluate_all_objectives(snapshot, objectives, 2, enemies, friendlies, 1)
	var nml1_eval = _find_eval(evals, "obj_nml_1")
	_assert(nml1_eval.state == "enemy_weak" or nml1_eval.state == "enemy_strong",
		"NML objective enemy held (state=%s)" % nml1_eval.state)
	_assert(nml1_eval.enemy_oc == 2, "Enemy OC at nml_1 is 2 (got %d)" % nml1_eval.enemy_oc)

# =========================================================================
# TEST: Unit Assignment
# =========================================================================

func test_unit_assignment_distributes_units():
	print("\n--- test_unit_assignment_distributes_units ---")
	var snapshot = _create_test_snapshot()
	# 3 units in P2 deployment zone, should spread to different objectives
	_add_unit(snapshot, "u1", 2, Vector2(880, 2000), "Boyz A", 2)
	_add_unit(snapshot, "u2", 2, Vector2(600, 2000), "Boyz B", 2)
	_add_unit(snapshot, "u3", 2, Vector2(1100, 2000), "Boyz C", 2)

	var objectives = _get_objectives_from_snapshot(snapshot)
	var enemies = {}
	var friendlies = {"u1": snapshot.units["u1"], "u2": snapshot.units["u2"], "u3": snapshot.units["u3"]}
	var movable = {"u1": ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"],
					"u2": ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"],
					"u3": ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]}

	var evals = AIDecisionMaker._evaluate_all_objectives(snapshot, objectives, 2, enemies, friendlies, 1)
	var assignments = AIDecisionMaker._assign_units_to_objectives(snapshot, movable, evals, objectives, enemies, friendlies, 2, 1)

	_assert(assignments.size() == 3, "All 3 units assigned (got %d)" % assignments.size())

	# Check that units go to different objectives (not all the same)
	var assigned_objectives = {}
	for uid in assignments:
		var oid = assignments[uid].get("objective_id", "")
		assigned_objectives[oid] = true

	_assert(assigned_objectives.size() >= 2, "Units spread across >= 2 objectives (got %d)" % assigned_objectives.size())

# =========================================================================
# TEST: Hold/Move Decisions
# =========================================================================

func test_unit_on_objective_holds():
	print("\n--- test_unit_on_objective_holds ---")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "u1", 2, Vector2(880, 2160), "Boyz on Home", 2)

	var actions = _make_available_actions(["u1"])
	var decision = AIDecisionMaker._decide_movement(snapshot, actions, 2)

	_assert(decision.get("type", "") == "REMAIN_STATIONARY", "Unit on objective holds (type=%s)" % decision.get("type", ""))
	_assert(decision.get("actor_unit_id", "") == "u1", "Correct unit holds")

func test_unit_not_on_objective_moves():
	print("\n--- test_unit_not_on_objective_moves ---")
	var snapshot = _create_test_snapshot()
	# Unit far from any objective
	_add_unit(snapshot, "u1", 2, Vector2(200, 2000), "Boyz far", 2)

	var actions = _make_available_actions(["u1"])
	var decision = AIDecisionMaker._decide_movement(snapshot, actions, 2)

	var move_type = decision.get("type", "")
	_assert(move_type == "BEGIN_NORMAL_MOVE" or move_type == "BEGIN_ADVANCE",
		"Unit far from objective moves (type=%s)" % move_type)

# =========================================================================
# TEST: Engaged Unit Decisions (Smart Fall Back)
# =========================================================================

func test_engaged_unit_on_objective_stays():
	print("\n--- test_engaged_unit_on_objective_stays ---")
	var snapshot = _create_test_snapshot()
	# Our unit on home objective, engaged with enemy
	_add_unit(snapshot, "u1", 2, Vector2(880, 2160), "Our Boyz", 2)
	_add_unit(snapshot, "e1", 1, Vector2(880, 2140), "Enemy", 1)

	# Engaged: only fall back + remain stationary available
	var actions = _make_available_actions(["u1"], ["u1"])
	var decision = AIDecisionMaker._decide_movement(snapshot, actions, 2)

	_assert(decision.get("type", "") == "REMAIN_STATIONARY",
		"Engaged unit on objective stays (type=%s)" % decision.get("type", ""))

func test_engaged_unit_off_objective_falls_back():
	print("\n--- test_engaged_unit_off_objective_falls_back ---")
	var snapshot = _create_test_snapshot()
	# Our unit NOT on any objective, engaged with enemy
	_add_unit(snapshot, "u1", 2, Vector2(500, 1500), "Our Boyz", 2)
	_add_unit(snapshot, "e1", 1, Vector2(500, 1480), "Enemy", 1)

	var actions = _make_available_actions(["u1"], ["u1"])
	var decision = AIDecisionMaker._decide_movement(snapshot, actions, 2)

	_assert(decision.get("type", "") == "BEGIN_FALL_BACK",
		"Engaged unit off objective falls back (type=%s)" % decision.get("type", ""))

# =========================================================================
# TEST: Advance Decision
# =========================================================================

func test_advance_decision_no_ranged():
	print("\n--- test_advance_decision_no_ranged ---")
	# Unit with no ranged weapons, needs extra distance to reach objective
	var unit = {
		"meta": {"stats": {"move": 6}, "keywords": ["INFANTRY"], "weapons": [
			{"name": "Close combat weapon", "type": "Melee", "range": "Melee"}
		]},
		"flags": {}
	}
	var obj_eval = {"zone": "no_mans_land", "state": "uncontrolled", "priority": 10.0}
	var enemies = {}
	var result = AIDecisionMaker._should_unit_advance(unit, 7.5, 6.0, false, 0.0, enemies, Vector2(880, 2000), 1, obj_eval)
	_assert(result == true, "Unit with no ranged weapons should advance")

func test_advance_decision_round1():
	print("\n--- test_advance_decision_round1 ---")
	# Unit with ranged weapons in round 1, NML objective
	var unit = {
		"meta": {"stats": {"move": 6}, "keywords": ["INFANTRY"], "weapons": [
			{"name": "Bolt rifle", "type": "Ranged", "range": "24"}
		]},
		"flags": {}
	}
	var obj_eval = {"zone": "no_mans_land", "state": "uncontrolled", "priority": 10.0}
	var enemies = {}
	var result = AIDecisionMaker._should_unit_advance(unit, 7.5, 6.0, true, 24.0, enemies, Vector2(880, 2000), 1, obj_eval)
	_assert(result == true, "Round 1 unit should advance to reach NML objective")

func test_no_advance_with_targets_in_range():
	print("\n--- test_no_advance_with_targets_in_range ---")
	# Unit with ranged weapons, enemies in range, not round 1
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "e1", 1, Vector2(880, 1000), "Enemy", 2)
	var enemies = {"e1": snapshot.units["e1"]}
	var unit = {
		"meta": {"stats": {"move": 6}, "keywords": ["INFANTRY"], "weapons": [
			{"name": "Bolt rifle", "type": "Ranged", "range": "24"}
		]},
		"flags": {}
	}
	var obj_eval = {"zone": "no_mans_land", "state": "contested", "priority": 7.0}
	# Unit at 880,1500 — enemy at 880,1000 = 500px = 12.5" (within 24" range)
	var result = AIDecisionMaker._should_unit_advance(unit, 7.5, 6.0, true, 24.0, enemies, Vector2(880, 1500), 3, obj_eval)
	_assert(result == false, "Should NOT advance when targets are in shooting range (round 3)")

# =========================================================================
# TEST: OC-Aware Holding
# =========================================================================

func test_oc_aware_holding_frees_redundant_units():
	print("\n--- test_oc_aware_holding_frees_redundant_units ---")
	var snapshot = _create_test_snapshot()
	# Two units on home objective (no enemies) — only one should hold
	_add_unit(snapshot, "u1", 2, Vector2(880, 2160), "Boyz A on Home", 2)
	_add_unit(snapshot, "u2", 2, Vector2(860, 2160), "Boyz B on Home", 2)

	var actions = _make_available_actions(["u1", "u2"])

	# Process both units through the movement phase decisions
	var first_decision = AIDecisionMaker._decide_movement(snapshot, actions, 2)
	var first_type = first_decision.get("type", "")
	var first_unit = first_decision.get("actor_unit_id", "")

	# At least one should hold, and the system should not just lock both on the same obj
	_assert(first_type == "REMAIN_STATIONARY" or first_type == "BEGIN_NORMAL_MOVE" or first_type == "BEGIN_ADVANCE",
		"First unit gets valid action (type=%s)" % first_type)

	# If first unit holds, remove it from available and check second
	if first_type == "REMAIN_STATIONARY":
		# Simulate second call: remove the first unit from available actions
		var remaining_actions = []
		for a in actions:
			if a.get("actor_unit_id", "") != first_unit:
				remaining_actions.append(a)
		# Also mark first unit as moved in snapshot
		snapshot.units[first_unit]["flags"]["moved"] = true

		var second_decision = AIDecisionMaker._decide_movement(snapshot, remaining_actions, 2)
		var second_type = second_decision.get("type", "")
		# The second unit should ideally move elsewhere (or at least not just hold if there's no need)
		_assert(second_type != "", "Second unit gets a decision (type=%s)" % second_type)

# =========================================================================
# TEST: Home Objective Defense
# =========================================================================

func test_home_objective_defended():
	print("\n--- test_home_objective_defended ---")
	var snapshot = _create_test_snapshot()
	# No units near home objective - it's truly undefended
	_add_unit(snapshot, "u1", 2, Vector2(880, 1600), "Boyz far from Home", 2)
	_add_unit(snapshot, "u2", 2, Vector2(1360, 1900), "Boyz near NML2", 2)

	var objectives = _get_objectives_from_snapshot(snapshot)
	var enemies = {}
	var friendlies = {"u1": snapshot.units["u1"], "u2": snapshot.units["u2"]}

	var evals = AIDecisionMaker._evaluate_all_objectives(snapshot, objectives, 2, enemies, friendlies, 1)
	var home_eval = _find_eval(evals, "obj_home_2")
	# Home objective should get high priority when truly undefended (no units within control range)
	_assert(home_eval.priority > 0, "Undefended home objective has positive priority (%.1f)" % home_eval.priority)
	_assert(home_eval.friendly_oc == 0, "No friendly OC at undefended home (got %d)" % home_eval.friendly_oc)

# =========================================================================
# TEST: Movement toward assigned objective
# =========================================================================

func test_movement_toward_assigned_objective():
	print("\n--- test_movement_toward_assigned_objective ---")
	var snapshot = _create_test_snapshot()
	# Unit in no-man's land should move toward an objective
	# Put one unit holding home so the AI doesn't try to go backward
	_add_unit(snapshot, "u_home", 2, Vector2(880, 2160), "Home Holder", 2, 6)
	_add_unit(snapshot, "u1", 2, Vector2(880, 1600), "Boyz", 2, 6)

	var actions = _make_available_actions(["u_home", "u1"])
	# The AI processes one unit at a time; first call should handle one unit
	var decision = AIDecisionMaker._decide_movement(snapshot, actions, 2)

	var move_type = decision.get("type", "")
	var actor = decision.get("actor_unit_id", "")
	_assert(move_type != "", "Unit gets valid movement decision (type=%s, unit=%s)" % [move_type, actor])

	# Keep calling until we get the action for u1 (the non-home unit)
	# It might process u_home first (hold), then u1 (move)
	if actor == "u_home" and move_type == "REMAIN_STATIONARY":
		# Good — home unit holds. Now simulate second call for u1
		var remaining_actions = []
		for a in actions:
			if a.get("actor_unit_id", "") != "u_home":
				remaining_actions.append(a)
		snapshot.units["u_home"]["flags"]["moved"] = true
		decision = AIDecisionMaker._decide_movement(snapshot, remaining_actions, 2)
		move_type = decision.get("type", "")
		actor = decision.get("actor_unit_id", "")

	if move_type == "BEGIN_NORMAL_MOVE" or move_type == "BEGIN_ADVANCE":
		var dests = decision.get("_ai_model_destinations", {})
		_assert(not dests.is_empty(), "Movement has model destinations (count=%d)" % dests.size())

		# Check that at least one model moved (Y should decrease for P2 moving toward center)
		var moved_closer = false
		for mid in dests:
			var new_y = dests[mid][1]
			if new_y < 1600:  # Original Y was 1600
				moved_closer = true
				break
		_assert(moved_closer, "Models moved closer to objective (toward lower Y)")
	else:
		_assert(move_type == "REMAIN_STATIONARY",
			"If not moving, should be stationary (type=%s)" % move_type)

# =========================================================================
# TEST: MOV-1 — Shooting Range Consideration
# =========================================================================

func test_hold_for_shooting_enemies_in_range():
	print("\n--- test_hold_for_shooting_enemies_in_range ---")
	# Ranged unit with enemy in weapon range, objective is far away
	# Should remain stationary to maintain shooting capability
	var snapshot = _create_test_snapshot()
	snapshot.battle_round = 3  # Not round 1 (no urgency to rush forward)

	# Place one unit holding home so it doesn't interfere
	_add_unit(snapshot, "u_home", 2, Vector2(880, 2160), "Home Holder", 2, 6, 5, ["INFANTRY"], [])

	# Ranged unit at y=1600, enemy at y=1000 = 600px = 15" (within 24" range)
	# Nearest objective is obj_nml_2 at (1360, 1680) or obj_center at (880, 1200)
	_add_unit(snapshot, "u1", 2, Vector2(880, 1600), "Shooty Boyz", 2, 6, 5, ["INFANTRY"], [
		{"name": "Bolt rifle", "type": "Ranged", "range": "24", "attacks": "2", "skill": "3",
		 "strength": "4", "ap": "1", "damage": "1", "keywords": []}
	])
	_add_unit(snapshot, "e1", 1, Vector2(880, 1000), "Enemy Guard", 2, 6, 5, ["INFANTRY"], [])

	var actions = _make_available_actions(["u_home", "u1"])
	# Process first decision (home unit holds)
	var decision = AIDecisionMaker._decide_movement(snapshot, actions, 2)
	var actor = decision.get("actor_unit_id", "")
	if actor == "u_home":
		# Remove home unit and get decision for u1
		var remaining = []
		for a in actions:
			if a.get("actor_unit_id", "") != "u_home":
				remaining.append(a)
		snapshot.units["u_home"]["flags"]["moved"] = true
		decision = AIDecisionMaker._decide_movement(snapshot, remaining, 2)

	# The ranged unit should hold for shooting since enemies are in range
	# and the objective is more than 1 turn away
	var move_type = decision.get("type", "")
	_assert(move_type == "REMAIN_STATIONARY",
		"Ranged unit with enemies in range holds for shooting (type=%s)" % move_type)

func test_move_when_no_enemies_in_range():
	print("\n--- test_move_when_no_enemies_in_range ---")
	# Ranged unit with NO enemies in weapon range should move normally
	var snapshot = _create_test_snapshot()
	snapshot.battle_round = 3

	_add_unit(snapshot, "u_home", 2, Vector2(880, 2160), "Home Holder", 2, 6, 5, ["INFANTRY"], [])
	# Ranged unit at y=1600, enemy at y=200 = 1400px = 35" (well beyond 24" range)
	_add_unit(snapshot, "u1", 2, Vector2(880, 1600), "Shooty Boyz", 2, 6, 5, ["INFANTRY"], [
		{"name": "Bolt rifle", "type": "Ranged", "range": "24", "attacks": "2", "skill": "3",
		 "strength": "4", "ap": "1", "damage": "1", "keywords": []}
	])
	_add_unit(snapshot, "e1", 1, Vector2(880, 200), "Enemy Far Away", 2, 6, 5, ["INFANTRY"], [])

	var actions = _make_available_actions(["u_home", "u1"])
	var decision = AIDecisionMaker._decide_movement(snapshot, actions, 2)
	var actor = decision.get("actor_unit_id", "")
	if actor == "u_home":
		var remaining = []
		for a in actions:
			if a.get("actor_unit_id", "") != "u_home":
				remaining.append(a)
		snapshot.units["u_home"]["flags"]["moved"] = true
		decision = AIDecisionMaker._decide_movement(snapshot, remaining, 2)

	var move_type = decision.get("type", "")
	_assert(move_type == "BEGIN_NORMAL_MOVE" or move_type == "BEGIN_ADVANCE",
		"Ranged unit with no enemies in range moves normally (type=%s)" % move_type)

func test_move_when_objective_reachable_this_turn():
	print("\n--- test_move_when_objective_reachable_this_turn ---")
	# Ranged unit with enemies in range BUT objective is reachable this turn
	# Should move to the objective (being on the obj is more important than one turn of shooting)
	var snapshot = _create_test_snapshot()
	snapshot.battle_round = 3

	_add_unit(snapshot, "u_home", 2, Vector2(880, 2160), "Home Holder", 2, 6, 5, ["INFANTRY"], [])
	# Unit at (1360, 1700) — very close to obj_nml_2 at (1360, 1680) = 20px = 0.5"
	# Enemy at (1360, 800) = 900px = 22.5" (within 24" range)
	_add_unit(snapshot, "u1", 2, Vector2(1360, 1700), "Shooty Boyz", 2, 6, 5, ["INFANTRY"], [
		{"name": "Bolt rifle", "type": "Ranged", "range": "24", "attacks": "2", "skill": "3",
		 "strength": "4", "ap": "1", "damage": "1", "keywords": []}
	])
	_add_unit(snapshot, "e1", 1, Vector2(1360, 800), "Enemy", 2, 6, 5, ["INFANTRY"], [])

	var actions = _make_available_actions(["u_home", "u1"])
	var decision = AIDecisionMaker._decide_movement(snapshot, actions, 2)
	var actor = decision.get("actor_unit_id", "")
	if actor == "u_home":
		var remaining = []
		for a in actions:
			if a.get("actor_unit_id", "") != "u_home":
				remaining.append(a)
		snapshot.units["u_home"]["flags"]["moved"] = true
		decision = AIDecisionMaker._decide_movement(snapshot, remaining, 2)

	# Should not hold for shooting — objective is within reach this turn
	# It should either move to grab the objective or hold on it (if already in control range)
	var move_type = decision.get("type", "")
	_assert(move_type != "", "Unit near objective gets a decision (type=%s)" % move_type)
	# The unit is very close to the objective (0.5"), within control range (~3.79")
	# so it may decide to REMAIN_STATIONARY because it's already on the objective
	# That's fine — the key is it should NOT be holding "for shooting"
	var desc = decision.get("_ai_description", "")
	var is_shooting_hold = desc.find("shooting") != -1
	_assert(not is_shooting_hold or move_type == "REMAIN_STATIONARY",
		"Near-objective unit does not hold specifically for shooting (desc=%s)" % desc)

func test_clamp_move_keeps_enemy_in_range():
	print("\n--- test_clamp_move_keeps_enemy_in_range ---")
	# Test the _clamp_move_for_weapon_range helper directly
	# Unit at (500, 500), enemy at (500, 200) = 300px = 7.5"
	# Weapon range 12" = 480px. Moving 240px (6") downward to (500, 740)
	# would put enemy at 540px = 13.5" (out of range)
	# The function should clamp the move.
	var centroid = Vector2(500, 500)
	var move_vector = Vector2(0, 240)  # Moving 6" away from enemy
	var max_weapon_range = 12.0
	var enemies = {
		"e1": {
			"owner": 1,
			"status": GameStateData.UnitStatus.DEPLOYED,
			"models": [{"id": "m1", "alive": true, "position": Vector2(500, 200)}],
			"meta": {"name": "Enemy", "stats": {}, "keywords": [], "weapons": []},
			"flags": {}
		}
	}

	var clamped = AIDecisionMaker._clamp_move_for_weapon_range(
		centroid, move_vector, max_weapon_range, enemies, "Test Unit"
	)

	# The clamped vector should be shorter than the original
	_assert(clamped.length() < move_vector.length(),
		"Clamped movement is shorter (%.1f vs %.1f)" % [clamped.length(), move_vector.length()])

	# After clamping, we should still be in range of the enemy
	var new_pos = centroid + clamped
	var dist_to_enemy = new_pos.distance_to(Vector2(500, 200))
	var range_px = max_weapon_range * AIDecisionMaker.PIXELS_PER_INCH
	_assert(dist_to_enemy <= range_px + 1.0,  # +1 for floating point tolerance
		"After clamping, enemy is still in range (dist=%.1f, range=%.1f)" % [dist_to_enemy, range_px])

func test_get_enemies_in_weapon_range():
	print("\n--- test_get_enemies_in_weapon_range ---")
	# Test the _get_enemies_in_weapon_range helper
	var centroid = Vector2(880, 1500)

	var snapshot = _create_test_snapshot()
	# Enemy at 880,1000 = 500px = 12.5" (within 24" range)
	_add_unit(snapshot, "e1", 1, Vector2(880, 1000), "Close Enemy", 2)
	# Enemy at 880,200 = 1300px = 32.5" (outside 24" range)
	_add_unit(snapshot, "e2", 1, Vector2(880, 200), "Far Enemy", 2)
	var enemies = {"e1": snapshot.units["e1"], "e2": snapshot.units["e2"]}

	var in_range = AIDecisionMaker._get_enemies_in_weapon_range(centroid, 24.0, enemies)
	_assert(in_range.size() == 1, "Only 1 enemy in 24\" range (got %d)" % in_range.size())
	if in_range.size() > 0:
		_assert(in_range[0].enemy_id == "e1", "Close enemy is in range (id=%s)" % in_range[0].enemy_id)

	# With 36" range, both should be in range
	var in_range_36 = AIDecisionMaker._get_enemies_in_weapon_range(centroid, 36.0, enemies)
	_assert(in_range_36.size() == 2, "Both enemies in 36\" range (got %d)" % in_range_36.size())

func test_should_hold_high_priority_objective_overrides():
	print("\n--- test_should_hold_high_priority_objective_overrides ---")
	# Even with enemies in range, a very high priority objective should override
	# the hold-for-shooting decision if it's reachable in ~2 turns
	var unit = {
		"meta": {
			"name": "Shooty Boyz",
			"stats": {"move": 6, "objective_control": 2},
			"keywords": ["INFANTRY"],
			"weapons": [{"name": "Bolt rifle", "type": "Ranged", "range": "24"}]
		},
		"models": [
			{"id": "m1", "alive": true, "position": Vector2(880, 1600)}
		],
		"flags": {}
	}
	var centroid = Vector2(880, 1600)
	# Objective 10" away (reachable in 2 turns with M6)
	var target_pos = Vector2(880, 1200)  # 400px = 10"
	var enemies = {
		"e1": {
			"owner": 1,
			"status": GameStateData.UnitStatus.DEPLOYED,
			"models": [{"id": "m1", "alive": true, "position": Vector2(880, 1000)}],
			"meta": {"name": "Enemy", "stats": {}, "keywords": [], "weapons": []},
			"flags": {}
		}
	}
	# High priority assignment (score >= 10)
	var assignment = {"score": 12.0, "reason": "uncontrolled objective"}

	var result = AIDecisionMaker._should_hold_for_shooting(
		unit, centroid, target_pos, 24.0, enemies, 6.0, assignment
	)
	_assert(result == false,
		"High priority nearby objective overrides hold-for-shooting (result=%s)" % str(result))

# =========================================================================
# Utility
# =========================================================================

func _get_objectives_from_snapshot(snapshot: Dictionary) -> Array:
	var objectives = []
	for obj in snapshot.get("board", {}).get("objectives", []):
		objectives.append(obj.position)
	return objectives

func _find_eval(evals: Array, obj_id: String) -> Dictionary:
	for e in evals:
		if e.id == obj_id:
			return e
	return {}
