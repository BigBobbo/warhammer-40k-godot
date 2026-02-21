extends SceneTree

# Test AI Charge Decisions - Tests the AI charge declaration and feasibility evaluation
# Run with: godot --headless --script tests/unit/test_ai_charge_decisions.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== AI Charge Decision Tests ===\n")
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
	test_charge_probability_guaranteed()
	test_charge_probability_impossible()
	test_charge_probability_seven()
	test_charge_probability_edges()
	test_evaluate_charge_close_target()
	test_evaluate_charge_far_target_skipped()
	test_evaluate_charge_prefers_closer_target()
	test_charge_roll_action_returned()
	test_complete_unit_charge_action()
	test_decline_reactions()
	test_skip_when_no_targets()
	test_end_charge_when_no_actions()
	test_melee_damage_estimation()
	test_charge_target_scoring()
	test_unit_has_melee_weapons()
	test_closest_model_distance()
	test_charge_move_computation()
	# T7-51: Overwatch risk assessment tests
	test_overwatch_risk_no_cp()
	test_overwatch_risk_no_ranged_enemies()
	test_overwatch_risk_with_dangerous_shooter()
	test_overwatch_risk_out_of_range()
	test_overwatch_unit_damage_estimation()

# =========================================================================
# Helper: Create a test snapshot
# =========================================================================

func _create_test_snapshot(player: int = 2) -> Dictionary:
	return {
		"battle_round": 2,
		"board": {
			"objectives": [
				{"id": "obj_center", "position": Vector2(880, 1200), "zone": "no_mans_land"},
			],
			"terrain_features": [],
			"deployment_zones": []
		},
		"units": {}
	}

func _add_unit(snapshot: Dictionary, unit_id: String, owner: int, pos: Vector2,
		name: String = "Test Unit", oc: int = 2, move: int = 6,
		num_models: int = 5, keywords: Array = ["INFANTRY"],
		weapons: Array = [], toughness: int = 4, save_val: int = 3,
		wounds: int = 1) -> void:
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
			"name": name,
			"stats": {
				"move": move,
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

func _make_melee_weapon(wname: String = "Power sword", ws: int = 3,
		strength: int = 5, ap: int = 2, damage: int = 1, attacks: int = 3) -> Dictionary:
	return {
		"name": wname,
		"type": "Melee",
		"weapon_skill": str(ws),
		"strength": str(strength),
		"ap": "-%d" % ap if ap > 0 else "0",
		"damage": str(damage),
		"attacks": str(attacks),
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

func _make_charge_available_actions(charger_id: String, target_ids: Array, include_skip: bool = true) -> Array:
	var actions = []
	for tid in target_ids:
		actions.append({
			"type": "DECLARE_CHARGE",
			"actor_unit_id": charger_id,
			"payload": {"target_unit_ids": [tid]},
		})
	if include_skip:
		actions.append({
			"type": "SKIP_CHARGE",
			"actor_unit_id": charger_id,
		})
	actions.append({"type": "END_CHARGE"})
	return actions

# =========================================================================
# Tests: Charge probability
# =========================================================================

func test_charge_probability_guaranteed():
	# 2D6 always >= 2, so distance <= 2 is guaranteed
	var prob = AIDecisionMaker._charge_success_probability(2.0)
	_assert(prob == 1.0, "Charge probability for distance 2.0 should be 1.0, got %.3f" % prob)

	prob = AIDecisionMaker._charge_success_probability(0.0)
	_assert(prob == 1.0, "Charge probability for distance 0.0 should be 1.0, got %.3f" % prob)

	prob = AIDecisionMaker._charge_success_probability(1.5)
	_assert(prob == 1.0, "Charge probability for distance 1.5 should be 1.0, got %.3f" % prob)

func test_charge_probability_impossible():
	# Need > 12 is impossible
	var prob = AIDecisionMaker._charge_success_probability(13.0)
	_assert(prob == 0.0, "Charge probability for distance 13.0 should be 0.0, got %.3f" % prob)

func test_charge_probability_seven():
	# Need 7: outcomes that sum >= 7
	# (1,6)(2,5)(2,6)(3,4)(3,5)(3,6)(4,3)(4,4)(4,5)(4,6)(5,2)(5,3)(5,4)(5,5)(5,6)(6,1)(6,2)(6,3)(6,4)(6,5)(6,6) = 21/36
	var prob = AIDecisionMaker._charge_success_probability(7.0)
	_assert(abs(prob - 21.0 / 36.0) < 0.01, "Charge probability for 7 should be ~0.583, got %.3f" % prob)

func test_charge_probability_edges():
	# Need 12: only (6,6) = 1/36
	var prob12 = AIDecisionMaker._charge_success_probability(12.0)
	_assert(abs(prob12 - 1.0 / 36.0) < 0.01, "Charge probability for 12 should be ~0.028, got %.3f" % prob12)

	# Need 2: all outcomes = 36/36
	var prob2 = AIDecisionMaker._charge_success_probability(2.0)
	_assert(prob2 == 1.0, "Charge probability for 2 should be 1.0, got %.3f" % prob2)

	# Need 3: all except (1,1) = 35/36
	var prob3 = AIDecisionMaker._charge_success_probability(3.0)
	_assert(abs(prob3 - 35.0 / 36.0) < 0.01, "Charge probability for 3 should be ~0.972, got %.3f" % prob3)

# =========================================================================
# Tests: Charge target evaluation
# =========================================================================

func test_evaluate_charge_close_target():
	var snapshot = _create_test_snapshot(2)
	var melee_weapons = [_make_melee_weapon()]
	_add_unit(snapshot, "charger", 2, Vector2(880, 1400), "Assault Marines", 2, 6, 5, ["INFANTRY"], melee_weapons)
	# Target 5" away (200 px / 40 px per inch = 5")
	_add_unit(snapshot, "target", 1, Vector2(880, 1200), "Guardsmen", 1, 6, 10, ["INFANTRY"])

	var actions = _make_charge_available_actions("charger", ["target"])
	var decision = AIDecisionMaker._decide_charge(snapshot, actions, 2)

	_assert(decision.get("type") == "DECLARE_CHARGE", "Should declare charge against close target, got: %s" % decision.get("type", ""))
	if decision.get("type") == "DECLARE_CHARGE":
		var targets = decision.get("payload", {}).get("target_unit_ids", [])
		_assert("target" in targets, "Should target the enemy unit")

func test_evaluate_charge_far_target_skipped():
	var snapshot = _create_test_snapshot(2)
	var melee_weapons = [_make_melee_weapon()]
	_add_unit(snapshot, "charger", 2, Vector2(880, 1800), "Assault Marines", 2, 6, 5, ["INFANTRY"], melee_weapons)
	# Target 14" away (560 px / 40 = 14") - beyond charge range
	_add_unit(snapshot, "target", 1, Vector2(880, 1240), "Guardsmen", 1, 6, 10, ["INFANTRY"])

	# The target would be out of 12" charge range, so DECLARE_CHARGE won't be available
	# Test with actions that have no DECLARE_CHARGE (simulating no eligible targets)
	var actions = [
		{"type": "SKIP_CHARGE", "actor_unit_id": "charger"},
		{"type": "END_CHARGE"}
	]
	var decision = AIDecisionMaker._decide_charge(snapshot, actions, 2)

	_assert(decision.get("type") == "SKIP_CHARGE" or decision.get("type") == "END_CHARGE",
		"Should skip or end when no targets in range, got: %s" % decision.get("type", ""))

func test_evaluate_charge_prefers_closer_target():
	var snapshot = _create_test_snapshot(2)
	var melee_weapons = [_make_melee_weapon()]
	_add_unit(snapshot, "charger", 2, Vector2(880, 1400), "Assault Marines", 2, 6, 5, ["INFANTRY"], melee_weapons)
	# Close target: 3" away
	_add_unit(snapshot, "close_target", 1, Vector2(880, 1280), "Close Squad", 1, 6, 5, ["INFANTRY"])
	# Far target: 10" away
	_add_unit(snapshot, "far_target", 1, Vector2(880, 1000), "Far Squad", 1, 6, 5, ["INFANTRY"])

	var actions = _make_charge_available_actions("charger", ["close_target", "far_target"])
	var decision = AIDecisionMaker._decide_charge(snapshot, actions, 2)

	_assert(decision.get("type") == "DECLARE_CHARGE", "Should declare charge, got: %s" % decision.get("type", ""))
	if decision.get("type") == "DECLARE_CHARGE":
		var targets = decision.get("payload", {}).get("target_unit_ids", [])
		_assert("close_target" in targets, "Should prefer closer target for higher probability")

func test_charge_roll_action_returned():
	var snapshot = _create_test_snapshot(2)
	_add_unit(snapshot, "charger", 2, Vector2(880, 1400), "Marines", 2, 6, 5)

	var actions = [
		{"type": "CHARGE_ROLL", "actor_unit_id": "charger"},
		{"type": "END_CHARGE"}
	]
	var decision = AIDecisionMaker._decide_charge(snapshot, actions, 2)

	_assert(decision.get("type") == "CHARGE_ROLL", "Should roll charge dice when available, got: %s" % decision.get("type", ""))
	_assert(decision.get("actor_unit_id") == "charger", "Should be for the correct unit")

func test_complete_unit_charge_action():
	var snapshot = _create_test_snapshot(2)
	_add_unit(snapshot, "charger", 2, Vector2(880, 1400), "Marines", 2, 6, 5)

	var actions = [
		{"type": "COMPLETE_UNIT_CHARGE", "actor_unit_id": "charger"},
		{"type": "END_CHARGE"}
	]
	var decision = AIDecisionMaker._decide_charge(snapshot, actions, 2)

	_assert(decision.get("type") == "COMPLETE_UNIT_CHARGE", "Should complete charge when available, got: %s" % decision.get("type", ""))

func test_decline_reactions():
	var snapshot = _create_test_snapshot(2)

	# Test DECLINE_COMMAND_REROLL
	var actions_reroll = [
		{"type": "USE_COMMAND_REROLL"},
		{"type": "DECLINE_COMMAND_REROLL"},
	]
	var decision = AIDecisionMaker._decide_charge(snapshot, actions_reroll, 2)
	_assert(decision.get("type") == "DECLINE_COMMAND_REROLL", "Should decline command reroll, got: %s" % decision.get("type", ""))

	# Test DECLINE_FIRE_OVERWATCH
	var actions_ow = [
		{"type": "USE_FIRE_OVERWATCH"},
		{"type": "DECLINE_FIRE_OVERWATCH"},
	]
	decision = AIDecisionMaker._decide_charge(snapshot, actions_ow, 2)
	_assert(decision.get("type") == "DECLINE_FIRE_OVERWATCH", "Should decline fire overwatch, got: %s" % decision.get("type", ""))

	# Test DECLINE_HEROIC_INTERVENTION
	var actions_hi = [
		{"type": "USE_HEROIC_INTERVENTION"},
		{"type": "DECLINE_HEROIC_INTERVENTION"},
	]
	decision = AIDecisionMaker._decide_charge(snapshot, actions_hi, 2)
	_assert(decision.get("type") == "DECLINE_HEROIC_INTERVENTION", "Should decline heroic intervention, got: %s" % decision.get("type", ""))

	# Test DECLINE_TANK_SHOCK
	var actions_ts = [
		{"type": "USE_TANK_SHOCK"},
		{"type": "DECLINE_TANK_SHOCK"},
	]
	decision = AIDecisionMaker._decide_charge(snapshot, actions_ts, 2)
	_assert(decision.get("type") == "DECLINE_TANK_SHOCK", "Should decline tank shock, got: %s" % decision.get("type", ""))

func test_skip_when_no_targets():
	var snapshot = _create_test_snapshot(2)
	_add_unit(snapshot, "charger", 2, Vector2(880, 1400), "Marines", 2, 6, 5)

	# No DECLARE_CHARGE actions, only SKIP_CHARGE
	var actions = [
		{"type": "SKIP_CHARGE", "actor_unit_id": "charger"},
		{"type": "END_CHARGE"}
	]
	var decision = AIDecisionMaker._decide_charge(snapshot, actions, 2)
	_assert(decision.get("type") == "SKIP_CHARGE", "Should skip when no targets available, got: %s" % decision.get("type", ""))

func test_end_charge_when_no_actions():
	var snapshot = _create_test_snapshot(2)

	var actions = [{"type": "END_CHARGE"}]
	var decision = AIDecisionMaker._decide_charge(snapshot, actions, 2)
	_assert(decision.get("type") == "END_CHARGE", "Should end charge when only END_CHARGE available, got: %s" % decision.get("type", ""))

# =========================================================================
# Tests: Melee damage estimation
# =========================================================================

func test_melee_damage_estimation():
	var snapshot = _create_test_snapshot(2)
	var power_sword = _make_melee_weapon("Power sword", 3, 5, 2, 1, 3)
	_add_unit(snapshot, "attacker", 2, Vector2(100, 100), "Assault Marines", 2, 6, 5, ["INFANTRY"], [power_sword])
	_add_unit(snapshot, "defender", 1, Vector2(200, 100), "Guardsmen", 1, 6, 10, ["INFANTRY"], [], 3, 5, 1)

	var attacker = snapshot.units["attacker"]
	var defender = snapshot.units["defender"]
	var damage = AIDecisionMaker._estimate_melee_damage(attacker, defender)

	# WS3+ = 4/6 hit, S5 vs T3 = 4/6 wound, save 5+ modified by -2 = 7+ = 0/6 save = 100% unsaved
	# 3 attacks * 5 models * 4/6 * 4/6 * 1.0 * 1 damage = 3 * 5 * 0.667 * 0.667 * 1 = 6.67
	_assert(damage > 5.0, "Expected damage > 5.0 with power swords vs guardsmen, got: %.2f" % damage)
	_assert(damage < 10.0, "Expected damage < 10.0, got: %.2f" % damage)

# =========================================================================
# Tests: Charge target scoring
# =========================================================================

func test_charge_target_scoring():
	var snapshot = _create_test_snapshot(2)
	var melee_weapons = [_make_melee_weapon()]
	_add_unit(snapshot, "charger", 2, Vector2(100, 100), "Marines", 2, 6, 5, ["INFANTRY"], melee_weapons)
	_add_unit(snapshot, "weak_target", 1, Vector2(200, 100), "Weak Squad", 1, 6, 3, ["INFANTRY"], [], 3, 5, 1)
	_add_unit(snapshot, "tough_target", 1, Vector2(300, 100), "Tough Squad", 1, 6, 5, ["INFANTRY", "VEHICLE"], [], 10, 2, 10)

	var charger = snapshot.units["charger"]
	var weak = snapshot.units["weak_target"]
	var tough = snapshot.units["tough_target"]

	var weak_score = AIDecisionMaker._score_charge_target(charger, weak, snapshot, 2)
	var tough_score = AIDecisionMaker._score_charge_target(charger, tough, snapshot, 2)

	_assert(weak_score > tough_score, "Should prefer weak target (score %.1f) over tough target (score %.1f)" % [weak_score, tough_score])

# =========================================================================
# Tests: Melee weapon detection
# =========================================================================

func test_unit_has_melee_weapons():
	var with_melee = {"meta": {"weapons": [_make_melee_weapon()]}}
	var without_melee = {"meta": {"weapons": [_make_ranged_weapon()]}}
	var empty = {"meta": {"weapons": []}}

	_assert(AIDecisionMaker._unit_has_melee_weapons(with_melee) == true, "Unit with melee weapon should be detected")
	_assert(AIDecisionMaker._unit_has_melee_weapons(without_melee) == false, "Unit without melee weapon should not be detected")
	_assert(AIDecisionMaker._unit_has_melee_weapons(empty) == false, "Unit with no weapons should not be detected")

# =========================================================================
# Tests: Closest model distance
# =========================================================================

func test_closest_model_distance():
	# Two units 5" apart (200px center-to-center, 32mm bases)
	var unit_a = {
		"models": [{
			"id": "m1", "alive": true, "position": Vector2(100, 100),
			"base_mm": 32, "base_type": "circular", "base_dimensions": {}
		}]
	}
	var unit_b = {
		"models": [{
			"id": "m1", "alive": true, "position": Vector2(300, 100),
			"base_mm": 32, "base_type": "circular", "base_dimensions": {}
		}]
	}

	var dist = AIDecisionMaker._get_closest_model_distance_inches(unit_a, unit_b)
	# 200px center-to-center, minus 2 * (32/2 * 40/25.4) = 200 - 2 * 25.2 = 149.6 px edge-to-edge
	# 149.6 / 40 = 3.74 inches
	_assert(dist > 3.0, "Distance should be > 3.0, got: %.2f" % dist)
	_assert(dist < 6.0, "Distance should be < 6.0, got: %.2f" % dist)

# =========================================================================
# Tests: Charge move computation
# =========================================================================

func test_charge_move_computation():
	var snapshot = _create_test_snapshot(2)
	var melee_weapons = [_make_melee_weapon()]
	# Charger 5" away from target (center-to-center 200px)
	_add_unit(snapshot, "charger", 2, Vector2(880, 1400), "Assault Marines", 2, 6, 1, ["INFANTRY"], melee_weapons)
	_add_unit(snapshot, "target", 1, Vector2(880, 1200), "Guardsmen", 1, 6, 1, ["INFANTRY"])

	# Simulate a charge roll of 8 (more than enough)
	var result = AIDecisionMaker._compute_charge_move(snapshot, "charger", 8, ["target"], 2)

	_assert(result.get("type") == "APPLY_CHARGE_MOVE", "Should return APPLY_CHARGE_MOVE, got: %s" % result.get("type", ""))
	_assert(result.get("actor_unit_id") == "charger", "Should be for the charger unit")

	var per_model_paths = result.get("payload", {}).get("per_model_paths", {})
	_assert(not per_model_paths.is_empty(), "Should have per_model_paths")

	# Check that the model moved closer to the target
	if per_model_paths.has("m1"):
		var path = per_model_paths["m1"]
		_assert(path.size() == 2, "Path should have start and end points")
		if path.size() == 2:
			var start_y = path[0][1]
			var end_y = path[1][1]
			# Target is at y=1200, charger starts at y=1400
			# After charge, should be closer to y=1200
			_assert(end_y < start_y, "Model should have moved toward target (lower Y)")
			_assert(end_y > 1160 and end_y < 1400, "Model should be near engagement range of target")

# =========================================================================
# Tests: T7-51 Overwatch risk assessment
# =========================================================================

func test_overwatch_risk_no_cp():
	# If defending player has no CP, overwatch risk should be "none"
	var snapshot = _create_test_snapshot(2)
	snapshot["players"] = {"1": {"cp": 0}, "2": {"cp": 5}}  # Player 1 (defender) has 0 CP
	var melee_weapons = [_make_melee_weapon()]
	_add_unit(snapshot, "charger", 2, Vector2(880, 1400), "Assault Marines", 2, 6, 5, ["INFANTRY"], melee_weapons)
	# Add an enemy with ranged weapons nearby
	var ranged_weapons = [_make_ranged_weapon("Heavy bolter", 3, 5, 1, 2, 3, 36)]
	_add_unit(snapshot, "enemy_shooter", 1, Vector2(880, 1200), "Devastators", 1, 6, 5, ["INFANTRY"], ranged_weapons)

	var risk = AIDecisionMaker._estimate_overwatch_risk(snapshot.units["charger"], snapshot, 2)
	_assert(risk.risk_level == "none", "Risk should be 'none' when defender has 0 CP, got: %s" % risk.risk_level)
	_assert(risk.expected_damage == 0.0, "Expected damage should be 0.0 with no CP, got: %.2f" % risk.expected_damage)
	_assert(risk.score_penalty == 1.0, "Score penalty should be 1.0, got: %.2f" % risk.score_penalty)

func test_overwatch_risk_no_ranged_enemies():
	# If enemies have no ranged weapons, overwatch risk should be low/none
	var snapshot = _create_test_snapshot(2)
	snapshot["players"] = {"1": {"cp": 5}, "2": {"cp": 5}}
	var melee_weapons = [_make_melee_weapon()]
	_add_unit(snapshot, "charger", 2, Vector2(880, 1400), "Assault Marines", 2, 6, 5, ["INFANTRY"], melee_weapons)
	# Enemy with only melee weapons
	_add_unit(snapshot, "enemy_melee", 1, Vector2(880, 1200), "Berzerkers", 1, 6, 5, ["INFANTRY"], [_make_melee_weapon("Chainaxe")])

	var risk = AIDecisionMaker._estimate_overwatch_risk(snapshot.units["charger"], snapshot, 2)
	_assert(risk.expected_damage == 0.0, "Expected damage should be 0.0 from melee-only enemies, got: %.2f" % risk.expected_damage)
	_assert(risk.risk_level == "low" or risk.risk_level == "none", "Risk should be low/none, got: %s" % risk.risk_level)

func test_overwatch_risk_with_dangerous_shooter():
	# A unit with many ranged shots nearby should produce moderate/high overwatch risk
	var snapshot = _create_test_snapshot(2)
	snapshot["players"] = {"1": {"cp": 5}, "2": {"cp": 5}}
	# Charger: 5 assault marines with melee weapons, T4, 3+ save, 1W
	var melee_weapons = [_make_melee_weapon()]
	_add_unit(snapshot, "charger", 2, Vector2(880, 1400), "Assault Marines", 2, 6, 5, ["INFANTRY"], melee_weapons)
	# Enemy: 10 Guardsmen with lasguns (BS4, S3, AP0, D1, A1) — lots of shots but weak
	var lasguns = [_make_ranged_weapon("Lasgun", 4, 3, 0, 1, 1, 24)]
	_add_unit(snapshot, "enemy_guards", 1, Vector2(880, 1200), "Guardsmen", 1, 6, 10, ["INFANTRY"], lasguns, 3, 5)

	var risk = AIDecisionMaker._estimate_overwatch_risk(snapshot.units["charger"], snapshot, 2)
	# 10 shots * 1/6 hit * ~1/6 wound (S3 vs T4 = 5+) * (1 - save_prob(3+, AP0)) = 10 * 0.167 * 0.333 * 0.333 = ~0.185
	_assert(risk.expected_damage > 0.0, "Expected damage should be > 0 from ranged enemies, got: %.2f" % risk.expected_damage)
	_assert(risk.expected_damage < 1.0, "10 lasguns overwatch should deal < 1.0 dmg (weak weapons), got: %.2f" % risk.expected_damage)
	print("  T7-51: Guardsmen overwatch risk: %.3f dmg, level=%s, penalty=%.2f" % [risk.expected_damage, risk.risk_level, risk.score_penalty])

	# Now test with a dangerous shooter: 5 models with heavy bolters (BS3, S5, AP-1, D2, A3)
	var snapshot2 = _create_test_snapshot(2)
	snapshot2["players"] = {"1": {"cp": 5}, "2": {"cp": 5}}
	_add_unit(snapshot2, "charger2", 2, Vector2(880, 1400), "Assault Marines", 2, 6, 5, ["INFANTRY"], melee_weapons)
	var heavy_bolters = [_make_ranged_weapon("Heavy bolter", 3, 5, 1, 2, 3, 36)]
	_add_unit(snapshot2, "enemy_devs", 1, Vector2(880, 1200), "Devastators", 1, 6, 5, ["INFANTRY"], heavy_bolters, 4, 3)

	var risk2 = AIDecisionMaker._estimate_overwatch_risk(snapshot2.units["charger2"], snapshot2, 2)
	# 15 shots * 1/6 hit * 4/6 wound (S5 vs T4) * (1 - save(3+1=4+)) * min(2,1) = 15 * 0.167 * 0.667 * 0.5 * 1 = ~0.83
	_assert(risk2.expected_damage > risk.expected_damage, "Heavy bolters should do more overwatch dmg than lasguns, got: %.2f vs %.2f" % [risk2.expected_damage, risk.expected_damage])
	_assert(risk2.score_penalty <= 1.0, "Score penalty should be <= 1.0, got: %.2f" % risk2.score_penalty)
	print("  T7-51: Devastators overwatch risk: %.3f dmg, level=%s, penalty=%.2f" % [risk2.expected_damage, risk2.risk_level, risk2.score_penalty])

func test_overwatch_risk_out_of_range():
	# Enemy shooter beyond 24" should not contribute to overwatch risk
	var snapshot = _create_test_snapshot(2)
	snapshot["players"] = {"1": {"cp": 5}, "2": {"cp": 5}}
	var melee_weapons = [_make_melee_weapon()]
	_add_unit(snapshot, "charger", 2, Vector2(100, 100), "Assault Marines", 2, 6, 5, ["INFANTRY"], melee_weapons)
	# Enemy far away (>24"): at 1200px away = 30 inches
	var ranged_weapons = [_make_ranged_weapon("Heavy bolter", 3, 5, 1, 2, 3, 36)]
	_add_unit(snapshot, "enemy_far", 1, Vector2(1300, 100), "Far Shooters", 1, 6, 5, ["INFANTRY"], ranged_weapons, 4, 3)

	var risk = AIDecisionMaker._estimate_overwatch_risk(snapshot.units["charger"], snapshot, 2)
	_assert(risk.expected_damage == 0.0, "Expected damage should be 0 for out-of-range shooter, got: %.2f" % risk.expected_damage)
	_assert(risk.score_penalty == 1.0, "Score penalty should be 1.0 for out-of-range, got: %.2f" % risk.score_penalty)

func test_overwatch_unit_damage_estimation():
	# Test _estimate_unit_overwatch_damage directly
	# Shooter: 5 models, Heavy bolter (BS3, S5, AP-1, D2, A3)
	var shooter = {
		"meta": {
			"name": "Devastators",
			"stats": {"toughness": 4, "save": 3, "wounds": 1},
			"keywords": ["INFANTRY"],
			"weapons": [_make_ranged_weapon("Heavy bolter", 3, 5, 1, 2, 3, 36)]
		},
		"models": [],
		"flags": {}
	}
	for i in range(5):
		shooter.models.append({"id": "m%d" % (i+1), "alive": true, "base_mm": 32, "position": Vector2(100 + i*40, 100)})

	# Target: T4, 3+ save, no invuln, 1W per model
	var damage = AIDecisionMaker._estimate_unit_overwatch_damage(shooter, 4, 3, 0, 1)
	# 15 attacks * (1/6 hit) * (4/6 wound for S5vsT4) * (1 - (7-4)/6 save for 3+1=4+) * min(2,1)=1
	# = 15 * 0.1667 * 0.6667 * 0.5 * 1.0 = ~0.833
	_assert(damage > 0.5, "Heavy bolter overwatch damage should be > 0.5, got: %.3f" % damage)
	_assert(damage < 1.5, "Heavy bolter overwatch damage should be < 1.5, got: %.3f" % damage)
	print("  T7-51: Unit overwatch damage estimate: %.3f (expected ~0.83)" % damage)
