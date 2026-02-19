extends SceneTree

# Test AI Focus Fire System
# Verifies that the AI coordinates weapon assignments across units to
# concentrate fire on kill thresholds rather than spreading damage.
# Run with: godot --headless --script tests/unit/test_ai_focus_fire.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== AI Focus Fire System Tests ===\n")
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

func _assert_approx(actual: float, expected: float, tolerance: float, message: String) -> void:
	var diff = abs(actual - expected)
	if diff <= tolerance:
		_pass_count += 1
		print("PASS: %s (got %.2f, expected %.2f)" % [message, actual, expected])
	else:
		_fail_count += 1
		print("FAIL: %s (got %.2f, expected %.2f, diff %.4f > tolerance %.4f)" % [message, actual, expected, diff, tolerance])

func _run_tests():
	# Reset focus fire state before each test group
	test_calculate_kill_threshold_single_model()
	test_calculate_kill_threshold_multi_model()
	test_calculate_kill_threshold_wounded_models()
	test_calculate_target_value_character_bonus()
	test_calculate_target_value_vehicle_bonus()
	test_calculate_target_value_below_half_health()
	test_estimate_weapon_damage_basic()
	test_estimate_weapon_damage_out_of_range()
	test_estimate_weapon_damage_scales_by_model_count()
	test_build_focus_fire_plan_single_unit_single_target()
	test_build_focus_fire_plan_concentrates_on_killable_target()
	test_build_focus_fire_plan_redirects_excess()
	test_decide_shooting_uses_focus_fire_plan()
	test_decide_shooting_populates_model_ids()
	test_focus_fire_plan_reset_on_phase_change()
	test_build_unit_assignments_fallback_populates_model_ids()
	test_get_alive_model_ids()

# =========================================================================
# Helper: Create test data
# =========================================================================

func _create_test_snapshot() -> Dictionary:
	return {
		"battle_round": 2,
		"board": {
			"objectives": [],
			"terrain_features": [],
			"deployment_zones": []
		},
		"units": {}
	}

func _add_unit(snapshot: Dictionary, unit_id: String, owner: int, pos: Vector2,
		uname: String = "Test Unit", num_models: int = 1, keywords: Array = ["INFANTRY"],
		weapons: Array = [], toughness: int = 4, save_val: int = 3,
		wounds: int = 2, oc: int = 2) -> void:
	var models = []
	for i in range(num_models):
		models.append({
			"id": "m%d" % (i + 1),
			"alive": true,
			"base_mm": 32,
			"base_type": "circular",
			"base_dimensions": {},
			"position": Vector2(pos.x + i * 40, pos.y),
			"wounds": wounds,
			"current_wounds": wounds
		})
	snapshot.units[unit_id] = {
		"id": unit_id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": uname,
			"stats": {
				"move": 6,
				"toughness": toughness,
				"save": save_val,
				"wounds": wounds,
				"leadership": 6,
				"objective_control": oc
			},
			"keywords": keywords,
			"weapons": weapons
		},
		"models": models,
		"flags": {}
	}

func _add_wounded_unit(snapshot: Dictionary, unit_id: String, owner: int, pos: Vector2,
		uname: String, num_alive: int, num_dead: int, current_wounds: int,
		max_wounds: int, keywords: Array = ["INFANTRY"],
		weapons: Array = [], toughness: int = 4, save_val: int = 3) -> void:
	var models = []
	for i in range(num_alive):
		models.append({
			"id": "m%d" % (i + 1),
			"alive": true,
			"base_mm": 32,
			"base_type": "circular",
			"base_dimensions": {},
			"position": Vector2(pos.x + i * 40, pos.y),
			"wounds": max_wounds,
			"current_wounds": current_wounds
		})
	for i in range(num_dead):
		models.append({
			"id": "m%d" % (num_alive + i + 1),
			"alive": false,
			"base_mm": 32,
			"base_type": "circular",
			"base_dimensions": {},
			"position": Vector2(pos.x + (num_alive + i) * 40, pos.y),
			"wounds": max_wounds,
			"current_wounds": 0
		})
	snapshot.units[unit_id] = {
		"id": unit_id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": uname,
			"stats": {
				"move": 6,
				"toughness": toughness,
				"save": save_val,
				"wounds": max_wounds,
				"leadership": 6,
				"objective_control": 2
			},
			"keywords": keywords,
			"weapons": weapons
		},
		"models": models,
		"flags": {}
	}

func _make_ranged_weapon(wname: String = "Bolt rifle", bs: int = 3,
		strength: int = 4, ap: int = 1, damage: int = 1, attacks: int = 2,
		weapon_range: int = 24) -> Dictionary:
	return {
		"name": wname,
		"type": "Ranged",
		"ballistic_skill": str(bs),
		"strength": str(strength),
		"ap": "-%d" % ap if ap > 0 else "0",
		"damage": str(damage),
		"attacks": str(attacks),
		"range": str(weapon_range),
	}

func _reset_focus_fire_state() -> void:
	AIDecisionMaker._focus_fire_plan_built = false
	AIDecisionMaker._focus_fire_plan.clear()

# =========================================================================
# Tests: _calculate_kill_threshold
# =========================================================================

func test_calculate_kill_threshold_single_model():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "target", 2, Vector2(0, 0), "Single Model", 1, ["VEHICLE"], [], 10, 3, 12)
	var threshold = AIDecisionMaker._calculate_kill_threshold(snapshot.units["target"])
	_assert_approx(threshold, 12.0, 0.01, "Kill threshold for single 12W model is 12")

func test_calculate_kill_threshold_multi_model():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "target", 2, Vector2(0, 0), "Squad", 5, ["INFANTRY"], [], 4, 3, 2)
	var threshold = AIDecisionMaker._calculate_kill_threshold(snapshot.units["target"])
	_assert_approx(threshold, 10.0, 0.01, "Kill threshold for 5x 2W models is 10")

func test_calculate_kill_threshold_wounded_models():
	var snapshot = _create_test_snapshot()
	# 3 alive with 1 wound remaining each, 2 dead
	_add_wounded_unit(snapshot, "target", 2, Vector2(0, 0), "Wounded Squad",
		3, 2, 1, 2, ["INFANTRY"])
	var threshold = AIDecisionMaker._calculate_kill_threshold(snapshot.units["target"])
	_assert_approx(threshold, 3.0, 0.01, "Kill threshold for 3 alive models with 1W each is 3")

# =========================================================================
# Tests: _calculate_target_value
# =========================================================================

func test_calculate_target_value_character_bonus():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "char", 2, Vector2(0, 0), "Captain", 1, ["CHARACTER", "INFANTRY"])
	_add_unit(snapshot, "grunt", 2, Vector2(200, 0), "Grunt", 1, ["INFANTRY"])
	var char_value = AIDecisionMaker._calculate_target_value(snapshot.units["char"], snapshot, 1)
	var grunt_value = AIDecisionMaker._calculate_target_value(snapshot.units["grunt"], snapshot, 1)
	_assert(char_value > grunt_value, "CHARACTER target has higher value than non-CHARACTER (%.2f > %.2f)" % [char_value, grunt_value])

func test_calculate_target_value_vehicle_bonus():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "vehicle", 2, Vector2(0, 0), "Tank", 1, ["VEHICLE"], [], 10, 3, 12)
	_add_unit(snapshot, "grunt", 2, Vector2(200, 0), "Grunt", 1, ["INFANTRY"])
	var vehicle_value = AIDecisionMaker._calculate_target_value(snapshot.units["vehicle"], snapshot, 1)
	var grunt_value = AIDecisionMaker._calculate_target_value(snapshot.units["grunt"], snapshot, 1)
	_assert(vehicle_value > grunt_value, "VEHICLE target has higher value than INFANTRY (%.2f > %.2f)" % [vehicle_value, grunt_value])

func test_calculate_target_value_below_half_health():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "healthy", 2, Vector2(0, 0), "Healthy Squad", 5, ["INFANTRY"])
	_add_wounded_unit(snapshot, "wounded", 2, Vector2(200, 0), "Wounded Squad",
		2, 3, 2, 2, ["INFANTRY"])
	var healthy_value = AIDecisionMaker._calculate_target_value(snapshot.units["healthy"], snapshot, 1)
	var wounded_value = AIDecisionMaker._calculate_target_value(snapshot.units["wounded"], snapshot, 1)
	_assert(wounded_value > healthy_value, "Below-half-health target has higher value (%.2f > %.2f)" % [wounded_value, healthy_value])

# =========================================================================
# Tests: _estimate_weapon_damage
# =========================================================================

func test_estimate_weapon_damage_basic():
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2, 24)
	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [weapon])
	_add_unit(snapshot, "target", 2, Vector2(400, 0), "Target", 5, ["INFANTRY"], [], 4, 3, 2)

	var dmg = AIDecisionMaker._estimate_weapon_damage(weapon, snapshot.units["target"], snapshot, snapshot.units["shooter"])
	_assert(dmg > 0.0, "Basic weapon damage estimate is positive (got %.3f)" % dmg)
	# 2 attacks * (4/6 hit) * (3/6 wound) * (1 - 2/6 save) * 1 damage * 1 model = ~0.333 raw
	# With AP-1: save is 3+1=4+, so save probability = 3/6 = 0.5, p_unsaved = 0.5
	# 2 * 4/6 * 3/6 * 0.5 * 1 = 0.333
	# Bolt rifle = ANTI_INFANTRY, Target (5x 2W) = ELITE, efficiency = GOOD_MATCH (1.15)
	# 0.333 * 1.15 = ~0.383
	_assert_approx(dmg, 0.383, 0.06, "Expected ~0.38 damage for bolt rifle vs T4/3+ (AP-1) with efficiency")

func test_estimate_weapon_damage_out_of_range():
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2, 24)
	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [weapon])
	_add_unit(snapshot, "target", 2, Vector2(1200, 0), "Target", 5, ["INFANTRY"], [], 4, 3, 2)

	var dmg = AIDecisionMaker._estimate_weapon_damage(weapon, snapshot.units["target"], snapshot, snapshot.units["shooter"])
	_assert_approx(dmg, 0.0, 0.001, "Weapon damage is 0 for out-of-range target")

func test_estimate_weapon_damage_scales_by_model_count():
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2, 24)
	_add_unit(snapshot, "shooter1", 1, Vector2(0, 0), "1 Model", 1, ["INFANTRY"], [weapon])
	_add_unit(snapshot, "shooter5", 1, Vector2(0, 100), "5 Models", 5, ["INFANTRY"], [weapon])
	_add_unit(snapshot, "target", 2, Vector2(400, 0), "Target", 5, ["INFANTRY"], [], 4, 3, 2)

	var dmg1 = AIDecisionMaker._estimate_weapon_damage(weapon, snapshot.units["target"], snapshot, snapshot.units["shooter1"])
	var dmg5 = AIDecisionMaker._estimate_weapon_damage(weapon, snapshot.units["target"], snapshot, snapshot.units["shooter5"])
	_assert_approx(dmg5, dmg1 * 5.0, 0.01, "5-model unit does 5x damage of 1-model unit (%.2f vs %.2f)" % [dmg5, dmg1])

# =========================================================================
# Tests: _build_focus_fire_plan
# =========================================================================

func test_build_focus_fire_plan_single_unit_single_target():
	_reset_focus_fire_state()
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2, 24)
	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Squad A", 5, ["INFANTRY"], [weapon])
	_add_unit(snapshot, "enemy", 2, Vector2(400, 0), "Enemy", 5, ["INFANTRY"], [], 4, 3, 2)

	var plan = AIDecisionMaker._build_focus_fire_plan(snapshot, ["shooter"], 1)
	_assert(plan.has("shooter"), "Plan includes the shooter unit")
	if plan.has("shooter"):
		_assert(plan["shooter"].size() > 0, "Shooter has at least one assignment")
		var first_assignment = plan["shooter"][0]
		_assert(first_assignment.get("target_unit_id", "") == "enemy", "Assignment targets the enemy unit")

func test_build_focus_fire_plan_concentrates_on_killable_target():
	_reset_focus_fire_state()
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2, 24)
	var lascannon = _make_ranged_weapon("Lascannon", 3, 12, 3, 6, 1, 48)

	# Two shooter units
	_add_unit(snapshot, "squad_a", 1, Vector2(0, 0), "Squad A", 5, ["INFANTRY"], [weapon])
	_add_unit(snapshot, "squad_b", 1, Vector2(0, 100), "Squad B", 5, ["INFANTRY"], [weapon, lascannon])

	# Two enemies: weak one (easy to kill) and strong one
	_add_wounded_unit(snapshot, "weak_enemy", 2, Vector2(400, 0), "Weak Enemy",
		2, 3, 1, 1, ["INFANTRY"], [], 4, 5)  # 2 alive with 1W each = 2HP total
	_add_unit(snapshot, "strong_enemy", 2, Vector2(400, 100), "Strong Enemy",
		5, ["INFANTRY"], [], 4, 3, 2)  # 5 alive with 2W each = 10HP total

	var plan = AIDecisionMaker._build_focus_fire_plan(snapshot, ["squad_a", "squad_b"], 1)

	# At least some weapons should target the weak enemy for a likely kill
	var weak_damage_allocated = 0.0
	var strong_damage_allocated = 0.0
	for uid in plan:
		for assignment in plan[uid]:
			var tid = assignment.get("target_unit_id", "")
			if tid == "weak_enemy":
				weak_damage_allocated += 1.0
			elif tid == "strong_enemy":
				strong_damage_allocated += 1.0

	_assert(weak_damage_allocated > 0, "At least some weapons target the weak enemy (got %.0f assignments)" % weak_damage_allocated)
	# The plan should have assignments for both units
	_assert(plan.size() > 0, "Focus fire plan has assignments for at least one unit")

func test_build_focus_fire_plan_redirects_excess():
	_reset_focus_fire_state()
	var snapshot = _create_test_snapshot()
	var heavy_weapon = _make_ranged_weapon("Lascannon", 3, 12, 3, 6, 1, 48)

	# Three shooter units with heavy weapons
	_add_unit(snapshot, "squad_a", 1, Vector2(0, 0), "Squad A", 5, ["INFANTRY"], [heavy_weapon])
	_add_unit(snapshot, "squad_b", 1, Vector2(0, 100), "Squad B", 5, ["INFANTRY"], [heavy_weapon])
	_add_unit(snapshot, "squad_c", 1, Vector2(0, 200), "Squad C", 5, ["INFANTRY"], [heavy_weapon])

	# One weak enemy (only 2HP), should not absorb all 3 squads
	_add_wounded_unit(snapshot, "weak", 2, Vector2(400, 0), "Weak",
		2, 0, 1, 1, ["INFANTRY"], [], 4, 5)
	_add_unit(snapshot, "strong", 2, Vector2(400, 200), "Strong",
		5, ["INFANTRY"], [], 4, 3, 2)

	var plan = AIDecisionMaker._build_focus_fire_plan(snapshot, ["squad_a", "squad_b", "squad_c"], 1)

	# Count assignments per target
	var target_counts = {}
	for uid in plan:
		for assignment in plan[uid]:
			var tid = assignment.get("target_unit_id", "")
			if not target_counts.has(tid):
				target_counts[tid] = 0
			target_counts[tid] += 1

	# With overkill tolerance, not all 3 squads should shoot the 2HP target
	var weak_count = target_counts.get("weak", 0)
	var strong_count = target_counts.get("strong", 0)
	_assert(strong_count > 0, "Some weapons redirected to strong target (got %d assignments)" % strong_count)
	print("  Info: %d assignments to weak, %d to strong" % [weak_count, strong_count])

# =========================================================================
# Tests: _decide_shooting integration
# =========================================================================

func test_decide_shooting_uses_focus_fire_plan():
	_reset_focus_fire_state()
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2, 24)

	_add_unit(snapshot, "shooter", 2, Vector2(0, 0), "AI Shooter", 5, ["INFANTRY"], [weapon])
	_add_unit(snapshot, "enemy", 1, Vector2(400, 0), "Enemy", 5, ["INFANTRY"], [], 4, 3, 2)

	var available = [
		{"type": "SELECT_SHOOTER", "actor_unit_id": "shooter"}
	]

	var decision = AIDecisionMaker._decide_shooting(snapshot, available, 2)
	_assert(decision.get("type", "") == "SHOOT", "AI produces SHOOT action with focus fire (got type: %s)" % decision.get("type", ""))
	_assert("focus fire" in decision.get("_ai_description", "").to_lower(), "Description mentions focus fire")

	# Verify the plan was built
	_assert(AIDecisionMaker._focus_fire_plan_built, "Focus fire plan was built")

func test_decide_shooting_populates_model_ids():
	_reset_focus_fire_state()
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2, 24)

	_add_unit(snapshot, "shooter", 2, Vector2(0, 0), "AI Shooter", 5, ["INFANTRY"], [weapon])
	_add_unit(snapshot, "enemy", 1, Vector2(400, 0), "Enemy", 5, ["INFANTRY"], [], 4, 3, 2)

	var available = [
		{"type": "SELECT_SHOOTER", "actor_unit_id": "shooter"}
	]

	var decision = AIDecisionMaker._decide_shooting(snapshot, available, 2)
	_assert(decision.get("type", "") == "SHOOT", "AI produces SHOOT action")

	var assignments = decision.get("payload", {}).get("assignments", [])
	_assert(assignments.size() > 0, "SHOOT action has assignments")
	if assignments.size() > 0:
		var model_ids = assignments[0].get("model_ids", [])
		_assert(model_ids.size() == 5, "Assignment has 5 model_ids for 5-model unit (got %d)" % model_ids.size())
		if model_ids.size() > 0:
			_assert(model_ids[0] == "m1", "First model_id is m1 (got %s)" % model_ids[0])

func test_focus_fire_plan_reset_on_phase_change():
	_reset_focus_fire_state()
	AIDecisionMaker._focus_fire_plan_built = true
	AIDecisionMaker._focus_fire_plan = {"some_unit": []}

	# Calling decide with a non-shooting phase should reset the plan
	var snapshot = _create_test_snapshot()
	# Use a phase that returns quickly (COMMAND phase with END_COMMAND action)
	var available = [{"type": "END_COMMAND"}]
	AIDecisionMaker.decide(GameStateData.Phase.COMMAND, snapshot, available, 1)

	_assert(not AIDecisionMaker._focus_fire_plan_built, "Focus fire plan reset when entering non-shooting phase")
	_assert(AIDecisionMaker._focus_fire_plan.is_empty(), "Focus fire plan data cleared on phase change")

# =========================================================================
# Tests: _build_unit_assignments_fallback
# =========================================================================

func test_build_unit_assignments_fallback_populates_model_ids():
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2, 24)

	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 5, ["INFANTRY"], [weapon])
	_add_unit(snapshot, "enemy", 2, Vector2(400, 0), "Enemy", 5, ["INFANTRY"], [], 4, 3, 2)

	var enemies = AIDecisionMaker._get_enemy_units(snapshot, 1)
	var unit = snapshot.units["shooter"]
	var ranged_weapons = [weapon]

	var assignments = AIDecisionMaker._build_unit_assignments_fallback(unit, ranged_weapons, enemies, snapshot)
	_assert(assignments.size() > 0, "Fallback produces at least one assignment")
	if assignments.size() > 0:
		var model_ids = assignments[0].get("model_ids", [])
		_assert(model_ids.size() == 5, "Fallback assignment has 5 model_ids (got %d)" % model_ids.size())

# =========================================================================
# Tests: _get_alive_model_ids
# =========================================================================

func test_get_alive_model_ids():
	var snapshot = _create_test_snapshot()
	_add_wounded_unit(snapshot, "unit", 1, Vector2(0, 0), "Mixed",
		3, 2, 2, 2, ["INFANTRY"])

	var ids = AIDecisionMaker._get_alive_model_ids(snapshot.units["unit"])
	_assert(ids.size() == 3, "_get_alive_model_ids returns 3 for 3 alive / 2 dead (got %d)" % ids.size())
	_assert("m1" in ids, "Alive model m1 is in the list")
	_assert("m4" not in ids, "Dead model m4 is not in the list")
