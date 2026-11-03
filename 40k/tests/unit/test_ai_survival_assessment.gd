extends SceneTree

# Test AI Engaged Unit Survival Assessment (T7-27)
# Tests that the AI estimates fight-phase damage to inform hold/fall-back decisions.
# Run with: godot --headless --script tests/unit/test_ai_survival_assessment.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== AI Engaged Unit Survival Assessment Tests (T7-27) ===\n")
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
	test_survival_assessment_low_threat()
	test_survival_assessment_lethal_threat()
	test_survival_assessment_severe_threat()
	test_get_engaging_enemy_units()
	test_estimate_incoming_melee_damage()
	test_estimate_unit_remaining_wounds()
	test_engaged_on_objective_lethal_falls_back_when_others_hold()
	test_engaged_on_objective_lethal_stays_when_sole_holder()
	test_engaged_on_objective_safe_stays()
	test_engaged_off_objective_still_falls_back()

# =========================================================================
# Helper: Create a test snapshot
# =========================================================================

func _create_test_snapshot() -> Dictionary:
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
		weapons: Array = [], toughness: int = 4, save: int = 3,
		wounds: int = 2, base_mm: int = 32) -> void:
	var models = []
	for i in range(num_models):
		models.append({
			"id": "m%d" % (i + 1),
			"alive": true,
			"base_mm": base_mm,
			"base_type": "circular",
			"base_dimensions": {},
			"position": Vector2(pos.x + i * 40, pos.y),
			"wounds": wounds,
			"current_wounds": wounds
		})
	snapshot.units[unit_id] = {
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": name,
			"stats": {
				"move": move,
				"toughness": toughness,
				"save": save,
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

func _get_objectives_from_snapshot(snapshot: Dictionary) -> Array:
	var objectives = []
	for obj in snapshot.board.objectives:
		objectives.append(obj.position if obj.position is Vector2 else Vector2(obj.position.x, obj.position.y))
	return objectives

func _get_enemy_units(snapshot: Dictionary, player: int) -> Dictionary:
	var enemies = {}
	for uid in snapshot.units:
		if snapshot.units[uid].owner != player:
			enemies[uid] = snapshot.units[uid]
	return enemies

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
# TEST: _assess_engaged_unit_survival with low threat (weak enemy)
# =========================================================================

func test_survival_assessment_low_threat():
	print("\n--- test_survival_assessment_low_threat ---")
	var snapshot = _create_test_snapshot()
	# Our unit: 5 models, T4, Sv3+, 2W each = 10 wounds total
	_add_unit(snapshot, "u1", 2, Vector2(880, 1200), "Our Boyz", 2, 6, 5)
	# Weak enemy: 1 model, no melee weapons (just default close combat weapon)
	_add_unit(snapshot, "e1", 1, Vector2(880, 1165), "Weak Enemy", 1, 6, 1)

	var enemies = _get_enemy_units(snapshot, 2)
	var unit = snapshot.units["u1"]
	var result = AIDecisionMaker._assess_engaged_unit_survival(unit, "u1", "Our Boyz", enemies)

	_assert(result.remaining_wounds == 10.0,
		"Remaining wounds correct (%.1f)" % result.remaining_wounds)
	_assert(result.expected_damage < 1.0,
		"Expected damage from 1 weak model is low (%.2f)" % result.expected_damage)
	_assert(result.damage_ratio < 0.25,
		"Damage ratio is low (%.2f)" % result.damage_ratio)
	_assert(result.is_lethal == false,
		"Not lethal (ratio=%.2f)" % result.damage_ratio)
	_assert(result.is_severe == false,
		"Not severe (ratio=%.2f)" % result.damage_ratio)
	_assert(result.recommendation == "hold",
		"Recommends hold (got %s)" % result.recommendation)

# =========================================================================
# TEST: _assess_engaged_unit_survival with lethal threat (powerful enemy)
# =========================================================================

func test_survival_assessment_lethal_threat():
	print("\n--- test_survival_assessment_lethal_threat ---")
	var snapshot = _create_test_snapshot()
	# Our unit: 5 models, T4, Sv3+, 1W each = 5 wounds total (squishy)
	_add_unit(snapshot, "u1", 2, Vector2(880, 1200), "Squishy Guard", 2, 6, 5,
		["INFANTRY"], [], 3, 5, 1)  # T3, Sv5+, 1W

	# Powerful melee enemy: 5 models with nasty melee weapons
	var power_fist = {
		"name": "Power fist", "type": "Melee",
		"attacks": "3", "weapon_skill": "3", "strength": "8",
		"ap": "-2", "damage": "2"
	}
	_add_unit(snapshot, "e1", 1, Vector2(880, 1165), "Terminators", 1, 5, 5,
		["INFANTRY"], [power_fist], 5, 2, 3)

	var enemies = _get_enemy_units(snapshot, 2)
	var unit = snapshot.units["u1"]
	var result = AIDecisionMaker._assess_engaged_unit_survival(unit, "u1", "Squishy Guard", enemies)

	_assert(result.remaining_wounds == 5.0,
		"Remaining wounds correct (%.1f)" % result.remaining_wounds)
	_assert(result.expected_damage > 3.0,
		"Expected damage from Terminators is high (%.2f)" % result.expected_damage)
	_assert(result.is_lethal == true,
		"Is lethal (ratio=%.2f, threshold=%.2f)" % [result.damage_ratio, AIDecisionMaker.SURVIVAL_LETHAL_THRESHOLD])
	_assert(result.recommendation == "fall_back",
		"Recommends fall_back (got %s)" % result.recommendation)

# =========================================================================
# TEST: _assess_engaged_unit_survival with moderate threat (severe)
# =========================================================================

func test_survival_assessment_severe_threat():
	print("\n--- test_survival_assessment_severe_threat ---")
	var snapshot = _create_test_snapshot()
	# Our unit: 5 models, T4, Sv3+, 2W each = 10 wounds total
	_add_unit(snapshot, "u1", 2, Vector2(880, 1200), "Intercessors", 2, 6, 5)

	# Moderate enemy: 5 models with decent melee weapons
	var chainsword = {
		"name": "Chainsword", "type": "Melee",
		"attacks": "3", "weapon_skill": "3", "strength": "4",
		"ap": "-1", "damage": "1"
	}
	_add_unit(snapshot, "e1", 1, Vector2(880, 1165), "Assault Marines", 1, 6, 5,
		["INFANTRY"], [chainsword])

	var enemies = _get_enemy_units(snapshot, 2)
	var unit = snapshot.units["u1"]
	var result = AIDecisionMaker._assess_engaged_unit_survival(unit, "u1", "Intercessors", enemies)

	_assert(result.remaining_wounds == 10.0,
		"Remaining wounds correct (%.1f)" % result.remaining_wounds)
	# 5 models * 3A * (4+ hit = 0.667) * (S4 vs T4 = 0.5) * (3+ save -1AP = save on 4+ = 0.5 unsaved) * 1D = 2.5
	_assert(result.expected_damage > 1.0,
		"Expected damage is moderate (%.2f)" % result.expected_damage)
	print("  Damage ratio: %.2f (severe threshold: %.2f)" % [result.damage_ratio, AIDecisionMaker.SURVIVAL_SEVERE_THRESHOLD])

# =========================================================================
# TEST: _get_engaging_enemy_units
# =========================================================================

func test_get_engaging_enemy_units():
	print("\n--- test_get_engaging_enemy_units ---")
	var snapshot = _create_test_snapshot()
	# Our unit in the middle
	_add_unit(snapshot, "u1", 2, Vector2(880, 1200), "Our Boyz")
	# Close enemy (within engagement range)
	_add_unit(snapshot, "e1", 1, Vector2(880, 1165), "Close Enemy")
	# Far enemy (NOT within engagement range)
	_add_unit(snapshot, "e2", 1, Vector2(200, 200), "Far Enemy")

	var enemies = _get_enemy_units(snapshot, 2)
	var unit = snapshot.units["u1"]
	var engaging = AIDecisionMaker._get_engaging_enemy_units(unit, "u1", enemies)

	_assert(engaging.size() == 1,
		"Only 1 enemy unit is engaging (got %d)" % engaging.size())
	_assert(engaging[0].enemy_id == "e1",
		"Engaging enemy is e1 (got %s)" % engaging[0].enemy_id)

# =========================================================================
# TEST: _estimate_incoming_melee_damage
# =========================================================================

func test_estimate_incoming_melee_damage():
	print("\n--- test_estimate_incoming_melee_damage ---")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "u1", 2, Vector2(880, 1200), "Our Boyz")

	# Enemy with explicit melee weapon
	var chainsword = {
		"name": "Chainsword", "type": "Melee",
		"attacks": "4", "weapon_skill": "3", "strength": "4",
		"ap": "-1", "damage": "1"
	}
	_add_unit(snapshot, "e1", 1, Vector2(880, 1165), "Choppy Enemy", 1, 6, 3,
		["INFANTRY"], [chainsword])

	var enemies = _get_enemy_units(snapshot, 2)
	var unit = snapshot.units["u1"]
	var damage = AIDecisionMaker._estimate_incoming_melee_damage(unit, enemies, "u1")

	_assert(damage > 0.0,
		"Incoming melee damage is positive (%.2f)" % damage)
	# 3 models * 4A * (3+ hit = 0.667) * (S4 vs T4 = 0.5) * (3+ save -1AP = 0.5 unsaved) * 1D = 2.0
	_assert(damage > 1.0 and damage < 5.0,
		"Incoming damage is reasonable (%.2f, expected ~2.0)" % damage)

# =========================================================================
# TEST: _estimate_unit_remaining_wounds
# =========================================================================

func test_estimate_unit_remaining_wounds():
	print("\n--- test_estimate_unit_remaining_wounds ---")
	var snapshot = _create_test_snapshot()
	# 5 models * 2W = 10 wounds
	_add_unit(snapshot, "u1", 2, Vector2(880, 1200), "Our Boyz", 2, 6, 5)

	var unit = snapshot.units["u1"]
	var remaining = AIDecisionMaker._estimate_unit_remaining_wounds(unit)
	_assert(remaining == 10.0,
		"5 models * 2W = 10 wounds (got %.1f)" % remaining)

	# Test with a partially damaged model
	unit.models[0].current_wounds = 1
	remaining = AIDecisionMaker._estimate_unit_remaining_wounds(unit)
	_assert(remaining == 9.0,
		"4 full + 1 damaged = 9 wounds (got %.1f)" % remaining)

	# Test with a dead model
	unit.models[1].alive = false
	remaining = AIDecisionMaker._estimate_unit_remaining_wounds(unit)
	_assert(remaining == 7.0,
		"3 full + 1 damaged + 1 dead = 7 wounds (got %.1f)" % remaining)

# =========================================================================
# TEST: Engaged on objective, lethal threat — falls back when others can hold
# =========================================================================

func test_engaged_on_objective_lethal_falls_back_when_others_hold():
	print("\n--- test_engaged_on_objective_lethal_falls_back_when_others_hold ---")
	var snapshot = _create_test_snapshot()
	# Our squishy unit on home objective, engaged with lethal enemy
	_add_unit(snapshot, "u1", 2, Vector2(880, 2160), "Squishy Guard", 2, 6, 5,
		["INFANTRY"], [], 3, 5, 1)  # T3, Sv5+, 1W

	# Another friendly unit ALSO on the same objective (can hold without us)
	_add_unit(snapshot, "u2", 2, Vector2(840, 2160), "Backup Squad", 3, 6, 5)

	# Powerful melee enemy engaging u1
	var power_fist = {
		"name": "Power fist", "type": "Melee",
		"attacks": "3", "weapon_skill": "3", "strength": "8",
		"ap": "-2", "damage": "2"
	}
	_add_unit(snapshot, "e1", 1, Vector2(880, 2125), "Terminators", 1, 5, 5,
		["INFANTRY"], [power_fist], 5, 2, 3)

	var actions = _make_available_actions(["u1", "u2"], ["u1"])
	var decision = AIDecisionMaker._decide_movement(snapshot, actions, 2)

	# The squishy unit should fall back because it would be destroyed,
	# and u2 can still hold the objective
	_assert(decision.get("type", "") == "BEGIN_FALL_BACK",
		"Squishy unit on objective falls back when facing lethal threat and others can hold (type=%s)" % decision.get("type", ""))

# =========================================================================
# TEST: Engaged on objective, lethal threat — stays when sole holder
# =========================================================================

func test_engaged_on_objective_lethal_stays_when_sole_holder():
	print("\n--- test_engaged_on_objective_lethal_stays_when_sole_holder ---")
	var snapshot = _create_test_snapshot()
	# Our squishy unit on home objective, SOLE holder, engaged with lethal enemy
	_add_unit(snapshot, "u1", 2, Vector2(880, 2160), "Squishy Guard", 2, 6, 5,
		["INFANTRY"], [], 3, 5, 1)

	# Powerful melee enemy
	var power_fist = {
		"name": "Power fist", "type": "Melee",
		"attacks": "3", "weapon_skill": "3", "strength": "8",
		"ap": "-2", "damage": "2"
	}
	_add_unit(snapshot, "e1", 1, Vector2(880, 2125), "Terminators", 1, 5, 5,
		["INFANTRY"], [power_fist], 5, 2, 3)

	var actions = _make_available_actions(["u1"], ["u1"])
	var decision = AIDecisionMaker._decide_movement(snapshot, actions, 2)

	# Should stay even though it will die — it's the only holder
	_assert(decision.get("type", "") == "REMAIN_STATIONARY",
		"Sole holder stays on objective even facing lethal threat (type=%s)" % decision.get("type", ""))

# =========================================================================
# TEST: Engaged on objective, safe — stays (existing behavior preserved)
# =========================================================================

func test_engaged_on_objective_safe_stays():
	print("\n--- test_engaged_on_objective_safe_stays ---")
	var snapshot = _create_test_snapshot()
	# Our unit on home objective
	_add_unit(snapshot, "u1", 2, Vector2(880, 2160), "Our Boyz", 2)
	# Weak enemy
	_add_unit(snapshot, "e1", 1, Vector2(880, 2125), "Weak Enemy", 1, 6, 1)

	var actions = _make_available_actions(["u1"], ["u1"])
	var decision = AIDecisionMaker._decide_movement(snapshot, actions, 2)

	_assert(decision.get("type", "") == "REMAIN_STATIONARY",
		"Unit on objective with low threat stays (type=%s)" % decision.get("type", ""))

# =========================================================================
# TEST: Engaged off objective — still falls back (no regression)
# =========================================================================

func test_engaged_off_objective_still_falls_back():
	print("\n--- test_engaged_off_objective_still_falls_back ---")
	var snapshot = _create_test_snapshot()
	# Our unit NOT on any objective
	_add_unit(snapshot, "u1", 2, Vector2(500, 1500), "Our Boyz", 2)
	# Enemy
	_add_unit(snapshot, "e1", 1, Vector2(500, 1465), "Enemy", 1)

	var actions = _make_available_actions(["u1"], ["u1"])
	var decision = AIDecisionMaker._decide_movement(snapshot, actions, 2)

	_assert(decision.get("type", "") == "BEGIN_FALL_BACK",
		"Engaged unit off objective falls back regardless of survival (type=%s)" % decision.get("type", ""))
