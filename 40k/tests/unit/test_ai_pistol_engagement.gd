extends SceneTree

# Test T7-48: AI Pistol Usage in Engagement Range
# Verifies that:
# 1. AI fires pistol weapons when a unit is in engagement range
# 2. AI only targets enemies within engagement range with pistols
# 3. Non-pistol weapons are filtered out for engaged non-MV units
# 4. Monster/Vehicle units can still use all weapons (Big Guns Never Tire)
# Run with: godot --headless --script tests/unit/test_ai_pistol_engagement.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== T7-48: AI Pistol Engagement Range Tests ===\n")
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
	test_is_weapon_dict_pistol_true()
	test_is_weapon_dict_pistol_false()
	test_is_weapon_dict_pistol_no_keywords()
	test_focus_fire_plan_filters_non_pistol_in_engagement()
	test_focus_fire_plan_includes_pistol_in_engagement()
	test_focus_fire_plan_monster_vehicle_keeps_all_weapons()
	test_pistol_only_targets_enemies_in_engagement_range()
	test_pistol_ignores_distant_enemies_in_engagement()
	test_decide_shooting_filters_weapons_for_engaged_unit()
	test_decide_shooting_engaged_unit_with_pistol_shoots()

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
		wounds: int = 2, in_engagement: bool = false) -> void:
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
				"objective_control": 2
			},
			"keywords": keywords,
			"weapons": weapons
		},
		"models": models,
		"flags": {"in_engagement": in_engagement}
	}

func _make_pistol_weapon(wname: String = "Plasma Pistol", bs: int = 3,
		strength: int = 7, ap: int = 3, damage: int = 1, attacks: int = 1,
		weapon_range: int = 12) -> Dictionary:
	return {
		"name": wname,
		"type": "Ranged",
		"ballistic_skill": str(bs),
		"strength": str(strength),
		"ap": "-%d" % ap if ap > 0 else "0",
		"damage": str(damage),
		"attacks": str(attacks),
		"range": str(weapon_range),
		"keywords": ["PISTOL"]
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
# Tests: _is_weapon_dict_pistol helper
# =========================================================================

func test_is_weapon_dict_pistol_true():
	var weapon = _make_pistol_weapon()
	_assert(AIDecisionMaker._is_weapon_dict_pistol(weapon),
		"Plasma pistol detected as PISTOL weapon")

func test_is_weapon_dict_pistol_false():
	var weapon = _make_ranged_weapon()
	_assert(not AIDecisionMaker._is_weapon_dict_pistol(weapon),
		"Bolt rifle is NOT detected as PISTOL weapon")

func test_is_weapon_dict_pistol_no_keywords():
	var weapon = {"name": "Test", "type": "Ranged"}
	_assert(not AIDecisionMaker._is_weapon_dict_pistol(weapon),
		"Weapon with no keywords is NOT detected as PISTOL")

# =========================================================================
# Tests: Focus fire plan engagement range filtering
# =========================================================================

func test_focus_fire_plan_filters_non_pistol_in_engagement():
	"""Engaged infantry unit should not include bolt rifle in focus fire plan"""
	_reset_focus_fire_state()
	var snapshot = _create_test_snapshot()

	var weapons = [_make_ranged_weapon("Bolt rifle"), _make_pistol_weapon("Plasma Pistol")]
	# Place engaged shooter very close to enemy (within 1" = 40px edge-to-edge)
	_add_unit(snapshot, "shooter", 1, Vector2(100, 100), "Intercessor", 1, ["INFANTRY"],
		weapons, 4, 3, 2, true)
	# Enemy within engagement range (models with 32mm bases = ~12.6px radius,
	# so centers at 100 and 126 gives edge-to-edge ~0.65")
	_add_unit(snapshot, "enemy", 2, Vector2(126, 100), "Ork Boy", 5, ["INFANTRY"],
		[], 5, 6, 1)

	var plan = AIDecisionMaker._build_focus_fire_plan(snapshot, ["shooter"], 1)

	if plan.has("shooter"):
		var assignments = plan["shooter"]
		var has_bolt_rifle = false
		var has_pistol = false
		for a in assignments:
			if "bolt_rifle" in a.get("weapon_id", ""):
				has_bolt_rifle = true
			if "plasma_pistol" in a.get("weapon_id", ""):
				has_pistol = true
		_assert(not has_bolt_rifle, "Bolt rifle filtered out for engaged infantry unit")
		_assert(has_pistol, "Plasma pistol included for engaged infantry unit")
	else:
		# Plan might be empty if enemy is out of pistol range (edge case)
		# But with models so close it should have assignments
		_assert(false, "Focus fire plan should have assignments for engaged shooter with pistol")

func test_focus_fire_plan_includes_pistol_in_engagement():
	"""Engaged unit with pistol should have pistol weapon assigned in focus fire plan"""
	_reset_focus_fire_state()
	var snapshot = _create_test_snapshot()

	var weapons = [_make_pistol_weapon("Slugga", 5, 4, 0, 1, 1, 12)]
	_add_unit(snapshot, "shooter", 1, Vector2(100, 100), "Ork Boy", 5, ["INFANTRY"],
		weapons, 5, 6, 1, true)
	_add_unit(snapshot, "enemy", 2, Vector2(126, 100), "Marine", 5, ["INFANTRY"],
		[], 4, 3, 2)

	var plan = AIDecisionMaker._build_focus_fire_plan(snapshot, ["shooter"], 1)
	_assert(plan.has("shooter"), "Engaged unit with pistol has assignments in focus fire plan")
	if plan.has("shooter"):
		var assignments = plan["shooter"]
		_assert(assignments.size() > 0, "Pistol weapon assigned to target in engagement range")

func test_focus_fire_plan_monster_vehicle_keeps_all_weapons():
	"""Monster/Vehicle in engagement keeps all ranged weapons (Big Guns Never Tire)"""
	_reset_focus_fire_state()
	var snapshot = _create_test_snapshot()

	var weapons = [_make_ranged_weapon("Heavy bolter", 3, 5, 1, 1, 3, 36)]
	_add_unit(snapshot, "shooter", 1, Vector2(100, 100), "Dreadnought", 1,
		["VEHICLE"], weapons, 6, 3, 8, true)
	_add_unit(snapshot, "enemy", 2, Vector2(126, 100), "Marine", 5, ["INFANTRY"],
		[], 4, 3, 2)

	var plan = AIDecisionMaker._build_focus_fire_plan(snapshot, ["shooter"], 1)
	_assert(plan.has("shooter"), "Vehicle in engagement has assignments (Big Guns Never Tire)")
	if plan.has("shooter"):
		var assignments = plan["shooter"]
		var has_heavy_bolter = false
		for a in assignments:
			if "heavy_bolter" in a.get("weapon_id", ""):
				has_heavy_bolter = true
		_assert(has_heavy_bolter, "Vehicle keeps heavy bolter in engagement (BGNT)")

# =========================================================================
# Tests: Pistol targeting restrictions in engagement
# =========================================================================

func test_pistol_only_targets_enemies_in_engagement_range():
	"""Pistol from engaged unit should target nearby enemy, not distant one"""
	_reset_focus_fire_state()
	var snapshot = _create_test_snapshot()

	var weapons = [_make_pistol_weapon("Plasma Pistol")]
	_add_unit(snapshot, "shooter", 1, Vector2(100, 100), "Marine", 1, ["INFANTRY"],
		weapons, 4, 3, 2, true)
	# Close enemy within engagement range
	_add_unit(snapshot, "close_enemy", 2, Vector2(126, 100), "Close Ork", 3, ["INFANTRY"],
		[], 5, 6, 1)
	# Distant enemy NOT in engagement range (10" away)
	_add_unit(snapshot, "far_enemy", 2, Vector2(500, 100), "Far Ork", 5, ["INFANTRY"],
		[], 5, 6, 1)

	var plan = AIDecisionMaker._build_focus_fire_plan(snapshot, ["shooter"], 1)
	if plan.has("shooter"):
		var assignments = plan["shooter"]
		var targets_close = false
		var targets_far = false
		for a in assignments:
			if a.get("target_unit_id", "") == "close_enemy":
				targets_close = true
			if a.get("target_unit_id", "") == "far_enemy":
				targets_far = true
		_assert(targets_close, "Pistol targets close enemy in engagement range")
		_assert(not targets_far, "Pistol does NOT target distant enemy when in engagement")
	else:
		_assert(false, "Should have focus fire plan for engaged shooter with pistol")

func test_pistol_ignores_distant_enemies_in_engagement():
	"""When engaged, damage matrix should be 0 for enemies outside engagement range"""
	_reset_focus_fire_state()
	var snapshot = _create_test_snapshot()

	var weapons = [_make_pistol_weapon("Slugga", 5, 4, 0, 1, 1, 12)]
	_add_unit(snapshot, "shooter", 1, Vector2(100, 100), "Boy", 1, ["INFANTRY"],
		weapons, 5, 6, 1, true)
	# Only a far enemy — no valid pistol target
	_add_unit(snapshot, "far_enemy", 2, Vector2(500, 100), "Far Marine", 5, ["INFANTRY"],
		[], 4, 3, 2)

	var plan = AIDecisionMaker._build_focus_fire_plan(snapshot, ["shooter"], 1)
	# Expect no plan entry because the only enemy is too far for engagement-range pistol fire
	var has_plan = plan.has("shooter")
	_assert(not has_plan, "No plan for engaged unit when only enemies are outside engagement range")

# =========================================================================
# Tests: _decide_shooting integration
# =========================================================================

func test_decide_shooting_filters_weapons_for_engaged_unit():
	"""_decide_shooting should filter to pistol weapons for engaged infantry"""
	_reset_focus_fire_state()
	var snapshot = _create_test_snapshot()

	var weapons = [_make_ranged_weapon("Bolt rifle"), _make_pistol_weapon("Bolt Pistol", 3, 4, 0, 1, 1, 12)]
	_add_unit(snapshot, "shooter", 1, Vector2(100, 100), "Marine", 5, ["INFANTRY"],
		weapons, 4, 3, 2, true)
	_add_unit(snapshot, "enemy", 2, Vector2(126, 100), "Ork", 5, ["INFANTRY"],
		[], 5, 6, 1)

	var available_actions = [{
		"type": "SELECT_SHOOTER",
		"actor_unit_id": "shooter"
	}]

	var result = AIDecisionMaker._decide_shooting(snapshot, available_actions, 1)
	_assert(result.get("type", "") == "SHOOT", "Engaged unit with pistol produces SHOOT action (got: %s)" % result.get("type", ""))
	if result.get("type", "") == "SHOOT":
		var assignments = result.get("payload", {}).get("assignments", [])
		var has_bolt_rifle = false
		var has_bolt_pistol = false
		for a in assignments:
			if "bolt_rifle" in a.get("weapon_id", ""):
				has_bolt_rifle = true
			if "bolt_pistol" in a.get("weapon_id", ""):
				has_bolt_pistol = true
		_assert(not has_bolt_rifle, "Bolt rifle not assigned for engaged infantry")
		_assert(has_bolt_pistol, "Bolt pistol assigned for engaged infantry")

func test_decide_shooting_engaged_unit_with_pistol_shoots():
	"""Engaged unit with only pistol weapons should still shoot"""
	_reset_focus_fire_state()
	var snapshot = _create_test_snapshot()

	var weapons = [_make_pistol_weapon("Slugga", 5, 4, 0, 1, 1, 12)]
	_add_unit(snapshot, "shooter", 1, Vector2(100, 100), "Ork Boy", 5, ["INFANTRY"],
		weapons, 5, 6, 1, true)
	_add_unit(snapshot, "enemy", 2, Vector2(126, 100), "Marine", 5, ["INFANTRY"],
		[], 4, 3, 2)

	var available_actions = [{
		"type": "SELECT_SHOOTER",
		"actor_unit_id": "shooter"
	}]

	var result = AIDecisionMaker._decide_shooting(snapshot, available_actions, 1)
	_assert(result.get("type", "") == "SHOOT",
		"Engaged unit with slugga pistol produces SHOOT action (got: %s)" % result.get("type", ""))
	if result.get("type", "") == "SHOOT":
		var assignments = result.get("payload", {}).get("assignments", [])
		_assert(assignments.size() > 0, "Pistol weapon assigned when in engagement range")
		var targets_enemy = false
		for a in assignments:
			if a.get("target_unit_id", "") == "enemy":
				targets_enemy = true
		_assert(targets_enemy, "Pistol targets the enemy in engagement range")
