extends SceneTree

# Test AI Invulnerable Save Integration in Target Scoring
# Verifies that _save_probability, _get_target_invulnerable_save,
# _score_shooting_target, and _estimate_melee_damage correctly account
# for invulnerable saves from models, meta stats, and effect flags.
# Run with: godot --headless --script tests/unit/test_ai_invulnerable_save_scoring.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== AI Invulnerable Save Scoring Tests ===\n")
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
		print("PASS: %s (got %.4f, expected %.4f)" % [message, actual, expected])
	else:
		_fail_count += 1
		print("FAIL: %s (got %.4f, expected %.4f, diff %.4f > tolerance %.4f)" % [message, actual, expected, diff, tolerance])

func _run_tests():
	# _save_probability tests
	test_save_probability_no_invuln()
	test_save_probability_invuln_better_than_modified_save()
	test_save_probability_armour_better_than_invuln()
	test_save_probability_invuln_saves_from_ap_wipeout()
	test_save_probability_invuln_zero_means_no_invuln()

	# _get_target_invulnerable_save tests
	test_get_invuln_from_model()
	test_get_invuln_from_meta_stats()
	test_get_invuln_from_effect_flags()
	test_get_invuln_effect_overrides_worse_model_invuln()
	test_get_invuln_model_better_than_effect()
	test_get_invuln_no_invuln_returns_zero()
	test_get_invuln_string_type_handling()

	# _score_shooting_target integration tests
	test_shooting_score_lower_with_invuln()
	test_shooting_score_unchanged_when_invuln_worse_than_armour()
	test_shooting_score_with_high_ap_and_invuln()

	# _estimate_melee_damage integration tests
	test_melee_damage_lower_with_invuln()
	test_melee_damage_unchanged_when_invuln_worse()

	# _estimate_weapon_damage integration tests
	test_weapon_damage_accounts_for_invuln()

# =========================================================================
# Helpers
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
		name: String = "Test Unit", num_models: int = 1, keywords: Array = ["INFANTRY"],
		weapons: Array = [], toughness: int = 4, save_val: int = 3,
		wounds: int = 2, invuln: int = 0, flags: Dictionary = {}) -> void:
	var models = []
	for i in range(num_models):
		var model = {
			"id": "m%d" % (i + 1),
			"alive": true,
			"base_mm": 32,
			"base_type": "circular",
			"base_dimensions": {},
			"position": Vector2(pos.x + i * 40, pos.y),
			"wounds": wounds,
			"current_wounds": wounds
		}
		if invuln > 0:
			model["invuln"] = invuln
		models.append(model)
	var stats = {
		"move": 6,
		"toughness": toughness,
		"save": save_val,
		"wounds": wounds,
		"leadership": 6,
		"objective_control": 2
	}
	snapshot.units[unit_id] = {
		"id": unit_id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": name,
			"stats": stats,
			"keywords": keywords,
			"weapons": weapons
		},
		"models": models,
		"flags": flags
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
		"special_rules": ""
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
		"range": "Melee",
		"special_rules": ""
	}

# =========================================================================
# Tests: _save_probability with invulnerable save
# =========================================================================

func test_save_probability_no_invuln():
	# Save 3+, AP-2 -> modified save = 5+ -> prob = 2/6
	var prob = AIDecisionMaker._save_probability(3, 2, 0)
	_assert_approx(prob, 2.0 / 6.0, 0.001, "_save_probability with no invuln: 3+ save, AP-2 = 5+ (2/6)")

func test_save_probability_invuln_better_than_modified_save():
	# Save 3+, AP-3 -> modified save = 6+ but invuln 4+ is better -> uses 4+ -> prob = 3/6
	var prob = AIDecisionMaker._save_probability(3, 3, 4)
	_assert_approx(prob, 3.0 / 6.0, 0.001, "_save_probability: 3+ save AP-3 (6+) but 4++ invuln -> uses 4+ (3/6)")

func test_save_probability_armour_better_than_invuln():
	# Save 3+, AP 0 -> modified save = 3+ which is better than 4++ -> uses 3+ -> prob = 4/6
	var prob = AIDecisionMaker._save_probability(3, 0, 4)
	_assert_approx(prob, 4.0 / 6.0, 0.001, "_save_probability: 3+ save AP0 (3+) vs 4++ invuln -> uses armour (4/6)")

func test_save_probability_invuln_saves_from_ap_wipeout():
	# Save 4+, AP-4 -> modified save = 8+ (no save!) but invuln 5+ rescues -> prob = 2/6
	var prob = AIDecisionMaker._save_probability(4, 4, 5)
	_assert_approx(prob, 2.0 / 6.0, 0.001, "_save_probability: 4+ save AP-4 (no save) but 5++ invuln -> 5+ (2/6)")

func test_save_probability_invuln_zero_means_no_invuln():
	# invuln = 0 should behave identically to not passing invuln
	var prob_with = AIDecisionMaker._save_probability(3, 2, 0)
	var prob_without = AIDecisionMaker._save_probability(3, 2)
	_assert_approx(prob_with, prob_without, 0.0001, "_save_probability: invuln=0 behaves same as no invuln")

# =========================================================================
# Tests: _get_target_invulnerable_save
# =========================================================================

func test_get_invuln_from_model():
	# Model has invuln = 4
	var unit = {
		"models": [{"alive": true, "invuln": 4}],
		"meta": {"stats": {}},
		"flags": {}
	}
	var invuln = AIDecisionMaker._get_target_invulnerable_save(unit)
	_assert(invuln == 4, "_get_target_invulnerable_save reads invuln from model (got %d)" % invuln)

func test_get_invuln_from_meta_stats():
	# Models don't have invuln, but meta.stats does
	var unit = {
		"models": [{"alive": true}],
		"meta": {"stats": {"invuln": 5}},
		"flags": {}
	}
	var invuln = AIDecisionMaker._get_target_invulnerable_save(unit)
	_assert(invuln == 5, "_get_target_invulnerable_save reads invuln from meta.stats (got %d)" % invuln)

func test_get_invuln_from_effect_flags():
	# No native invuln, but effect-granted 6+ (Go to Ground)
	var unit = {
		"models": [{"alive": true}],
		"meta": {"stats": {}},
		"flags": {"effect_invuln": 6}
	}
	var invuln = AIDecisionMaker._get_target_invulnerable_save(unit)
	_assert(invuln == 6, "_get_target_invulnerable_save reads invuln from effect flags (got %d)" % invuln)

func test_get_invuln_effect_overrides_worse_model_invuln():
	# Model has 6+ invuln, but effect grants 4+ (better) -> should use 4+
	var unit = {
		"models": [{"alive": true, "invuln": 6}],
		"meta": {"stats": {}},
		"flags": {"effect_invuln": 4}
	}
	var invuln = AIDecisionMaker._get_target_invulnerable_save(unit)
	_assert(invuln == 4, "_get_target_invulnerable_save: effect 4++ overrides model 6++ (got %d)" % invuln)

func test_get_invuln_model_better_than_effect():
	# Model has 3+ invuln, effect grants 5+ (worse) -> should keep 3+
	var unit = {
		"models": [{"alive": true, "invuln": 3}],
		"meta": {"stats": {}},
		"flags": {"effect_invuln": 5}
	}
	var invuln = AIDecisionMaker._get_target_invulnerable_save(unit)
	_assert(invuln == 3, "_get_target_invulnerable_save: model 3++ beats effect 5++ (got %d)" % invuln)

func test_get_invuln_no_invuln_returns_zero():
	var unit = {
		"models": [{"alive": true}],
		"meta": {"stats": {}},
		"flags": {}
	}
	var invuln = AIDecisionMaker._get_target_invulnerable_save(unit)
	_assert(invuln == 0, "_get_target_invulnerable_save: no invuln returns 0 (got %d)" % invuln)

func test_get_invuln_string_type_handling():
	# Model invuln stored as string (edge case from data loading)
	var unit = {
		"models": [{"alive": true, "invuln": "4"}],
		"meta": {"stats": {}},
		"flags": {}
	}
	var invuln = AIDecisionMaker._get_target_invulnerable_save(unit)
	_assert(invuln == 4, "_get_target_invulnerable_save handles string invuln value (got %d)" % invuln)

# =========================================================================
# Tests: _score_shooting_target integration
# =========================================================================

func test_shooting_score_lower_with_invuln():
	# A target with 4++ invuln should score lower than the same target without
	# when hit by a high-AP weapon (where invuln matters)
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Lascannon", 3, 12, 3, 6, 1, 48)

	# Target without invuln: save 3+, AP-3 -> modified 6+ -> p_unsaved = 5/6
	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [weapon])
	_add_unit(snapshot, "target_no_invuln", 2, Vector2(400, 0), "Target", 1, ["INFANTRY"], [], 4, 3, 2, 0)
	# Target with 4++ invuln: save 3+, AP-3 -> modified 6+ BUT invuln 4+ -> p_unsaved = 3/6
	_add_unit(snapshot, "target_with_invuln", 2, Vector2(400, 100), "Target Invuln", 1, ["INFANTRY"], [], 4, 3, 2, 4)

	var shooter = snapshot.units["shooter"]
	var score_no_invuln = AIDecisionMaker._score_shooting_target(weapon, snapshot.units["target_no_invuln"], snapshot, shooter)
	var score_with_invuln = AIDecisionMaker._score_shooting_target(weapon, snapshot.units["target_with_invuln"], snapshot, shooter)

	_assert(score_with_invuln < score_no_invuln,
		"Shooting score lower with 4++ invuln vs high AP weapon (no_invuln=%.2f, with_invuln=%.2f)" % [score_no_invuln, score_with_invuln])

func test_shooting_score_unchanged_when_invuln_worse_than_armour():
	# Target with 6+ invuln and 3+ save at AP0: armour (3+) is better than invuln (6+)
	# So invuln should have no effect on the score
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Bolter", 3, 4, 0, 1, 2, 24)

	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [weapon])
	_add_unit(snapshot, "target_no_invuln", 2, Vector2(400, 0), "Target", 1, ["INFANTRY"], [], 4, 3, 2, 0)
	_add_unit(snapshot, "target_with_invuln", 2, Vector2(400, 100), "Target Invuln", 1, ["INFANTRY"], [], 4, 3, 2, 6)

	var shooter = snapshot.units["shooter"]
	var score_no_invuln = AIDecisionMaker._score_shooting_target(weapon, snapshot.units["target_no_invuln"], snapshot, shooter)
	var score_with_invuln = AIDecisionMaker._score_shooting_target(weapon, snapshot.units["target_with_invuln"], snapshot, shooter)

	_assert_approx(score_with_invuln, score_no_invuln, 0.001,
		"Shooting score unchanged when 6++ invuln is worse than 3+ armour at AP0")

func test_shooting_score_with_high_ap_and_invuln():
	# Lascannon (AP-3) vs 4+ save with 4++ invuln
	# Without invuln: modified save = 7+ -> no save -> p_unsaved = 1.0
	# With invuln: uses 4++ -> p_unsaved = 3/6 = 0.5
	# The score with invuln should be roughly half the score without
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Lascannon", 3, 12, 3, 6, 1, 48)

	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [weapon])
	_add_unit(snapshot, "target_no_invuln", 2, Vector2(400, 0), "Target NoInv", 1, ["INFANTRY"], [], 4, 4, 2, 0)
	_add_unit(snapshot, "target_with_invuln", 2, Vector2(400, 100), "Target Inv", 1, ["INFANTRY"], [], 4, 4, 2, 4)

	var shooter = snapshot.units["shooter"]
	var score_no_invuln = AIDecisionMaker._score_shooting_target(weapon, snapshot.units["target_no_invuln"], snapshot, shooter)
	var score_with_invuln = AIDecisionMaker._score_shooting_target(weapon, snapshot.units["target_with_invuln"], snapshot, shooter)

	# Without invuln: p_unsaved = 1.0, with invuln: p_unsaved = 0.5
	# So score_with should be roughly half of score_no
	var ratio = score_with_invuln / score_no_invuln if score_no_invuln > 0 else 0.0
	_assert_approx(ratio, 0.5, 0.05,
		"Score with 4++ invuln is ~50%% of score without when AP negates armour (ratio=%.3f)" % ratio)

# =========================================================================
# Tests: _estimate_melee_damage integration
# =========================================================================

func test_melee_damage_lower_with_invuln():
	# Melee weapon with AP-3 vs 3+ save: without invuln modified save = 6+
	# With 4++ invuln: uses 4+ instead of 6+
	var snapshot = _create_test_snapshot()
	var melee = _make_melee_weapon("Power fist", 3, 8, 3, 2, 3)

	_add_unit(snapshot, "attacker", 1, Vector2(0, 0), "Attacker", 1, ["INFANTRY"], [melee])
	_add_unit(snapshot, "defender_no_invuln", 2, Vector2(100, 0), "Defender", 1, ["INFANTRY"], [], 4, 3, 2, 0)
	_add_unit(snapshot, "defender_with_invuln", 2, Vector2(100, 100), "Defender Inv", 1, ["INFANTRY"], [], 4, 3, 2, 4)

	var dmg_no_invuln = AIDecisionMaker._estimate_melee_damage(
		snapshot.units["attacker"], snapshot.units["defender_no_invuln"])
	var dmg_with_invuln = AIDecisionMaker._estimate_melee_damage(
		snapshot.units["attacker"], snapshot.units["defender_with_invuln"])

	_assert(dmg_with_invuln < dmg_no_invuln,
		"Melee damage lower with 4++ invuln vs AP-3 weapon (no_invuln=%.2f, with_invuln=%.2f)" % [dmg_no_invuln, dmg_with_invuln])

func test_melee_damage_unchanged_when_invuln_worse():
	# Melee weapon with AP0 vs 3+ save: armour save = 3+, invuln 5+ is worse
	var snapshot = _create_test_snapshot()
	var melee = _make_melee_weapon("Chainsword", 4, 4, 0, 1, 3)

	_add_unit(snapshot, "attacker", 1, Vector2(0, 0), "Attacker", 1, ["INFANTRY"], [melee])
	_add_unit(snapshot, "defender_no_invuln", 2, Vector2(100, 0), "Defender", 1, ["INFANTRY"], [], 4, 3, 2, 0)
	_add_unit(snapshot, "defender_with_invuln", 2, Vector2(100, 100), "Defender Inv", 1, ["INFANTRY"], [], 4, 3, 2, 5)

	var dmg_no_invuln = AIDecisionMaker._estimate_melee_damage(
		snapshot.units["attacker"], snapshot.units["defender_no_invuln"])
	var dmg_with_invuln = AIDecisionMaker._estimate_melee_damage(
		snapshot.units["attacker"], snapshot.units["defender_with_invuln"])

	_assert_approx(dmg_with_invuln, dmg_no_invuln, 0.001,
		"Melee damage unchanged when 5++ invuln is worse than 3+ armour at AP0")

# =========================================================================
# Tests: _estimate_weapon_damage integration
# =========================================================================

func test_weapon_damage_accounts_for_invuln():
	# _estimate_weapon_damage (used in focus fire) should also consider invuln
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Lascannon", 3, 12, 3, 6, 1, 48)

	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [weapon])
	_add_unit(snapshot, "target_no_invuln", 2, Vector2(400, 0), "Target", 1, ["INFANTRY"], [], 4, 4, 2, 0)
	_add_unit(snapshot, "target_with_invuln", 2, Vector2(400, 100), "Target Inv", 1, ["INFANTRY"], [], 4, 4, 2, 4)

	var dmg_no_invuln = AIDecisionMaker._estimate_weapon_damage(
		weapon, snapshot.units["target_no_invuln"], snapshot, snapshot.units["shooter"])
	var dmg_with_invuln = AIDecisionMaker._estimate_weapon_damage(
		weapon, snapshot.units["target_with_invuln"], snapshot, snapshot.units["shooter"])

	_assert(dmg_with_invuln < dmg_no_invuln,
		"_estimate_weapon_damage lower with 4++ invuln (no_invuln=%.2f, with_invuln=%.2f)" % [dmg_no_invuln, dmg_with_invuln])
