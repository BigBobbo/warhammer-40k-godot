extends SceneTree

# Test AI Cover Consideration in Target Scoring (T7-31)
# Verifies that _target_has_benefit_of_cover, _weapon_ignores_cover,
# _check_position_has_terrain_cover, _score_shooting_target, and
# _estimate_weapon_damage correctly account for Benefit of Cover.
# Run with: godot --headless --script tests/unit/test_ai_cover_scoring.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")
const EffectPrimitivesData = preload("res://autoloads/EffectPrimitives.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== AI Cover Scoring Tests (T7-31) ===\n")
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
	# _target_has_benefit_of_cover tests
	test_no_cover_no_terrain()
	test_effect_cover_flag()
	test_in_cover_flag()
	test_terrain_cover_ruins_within()
	test_terrain_cover_ruins_behind()
	test_terrain_cover_woods_within()
	test_no_cover_outside_terrain()
	test_no_cover_empty_shooter()

	# _weapon_ignores_cover tests
	test_weapon_ignores_cover_special_rule()
	test_weapon_does_not_ignore_cover()
	test_weapon_ignores_cover_effect_flag()

	# _check_position_has_terrain_cover tests
	test_position_cover_ruins_los_blocked()
	test_position_no_cover_clear_los()
	test_position_cover_area_terrain_within()
	test_position_no_cover_area_terrain_outside()

	# _score_shooting_target integration tests
	test_score_lower_with_cover()
	test_score_unchanged_ignores_cover_weapon()
	test_score_unchanged_no_cover()
	test_score_cover_with_invuln_interaction()
	test_score_cover_cap_at_2_plus()
	test_score_cover_effect_flag()
	test_score_cover_with_ap0()

	# _estimate_weapon_damage integration tests
	test_estimate_damage_lower_with_cover()
	test_estimate_damage_ignores_cover()

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
		weapon_range: int = 24, special_rules: String = "") -> Dictionary:
	return {
		"name": wname,
		"type": "Ranged",
		"ballistic_skill": str(bs),
		"strength": str(strength),
		"ap": "-%d" % ap if ap > 0 else "0",
		"damage": str(damage),
		"attacks": str(attacks),
		"range": str(weapon_range),
		"special_rules": special_rules
	}

func _make_ruins_polygon(center: Vector2, size: float = 200.0) -> PackedVector2Array:
	"""Create a square ruins polygon centered at the given position."""
	var half = size / 2.0
	return PackedVector2Array([
		Vector2(center.x - half, center.y - half),
		Vector2(center.x + half, center.y - half),
		Vector2(center.x + half, center.y + half),
		Vector2(center.x - half, center.y + half)
	])

# =========================================================================
# Tests: _target_has_benefit_of_cover
# =========================================================================

func test_no_cover_no_terrain():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "shooter", 1, Vector2(200, 200))
	_add_unit(snapshot, "target", 2, Vector2(600, 200))
	var result = AIDecisionMaker._target_has_benefit_of_cover(
		snapshot.units["target"], snapshot.units["shooter"], snapshot)
	_assert(result == false, "No cover with no terrain features")

func test_effect_cover_flag():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "shooter", 1, Vector2(200, 200))
	_add_unit(snapshot, "target", 2, Vector2(600, 200), "Target", 1, ["INFANTRY"],
		[], 4, 3, 2, 0, {"effect_cover": true})
	var result = AIDecisionMaker._target_has_benefit_of_cover(
		snapshot.units["target"], snapshot.units["shooter"], snapshot)
	_assert(result == true, "Effect cover flag grants cover (e.g. Go to Ground)")

func test_in_cover_flag():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "shooter", 1, Vector2(200, 200))
	_add_unit(snapshot, "target", 2, Vector2(600, 200), "Target", 1, ["INFANTRY"],
		[], 4, 3, 2, 0, {"in_cover": true})
	var result = AIDecisionMaker._target_has_benefit_of_cover(
		snapshot.units["target"], snapshot.units["shooter"], snapshot)
	_assert(result == true, "in_cover flag grants cover")

func test_terrain_cover_ruins_within():
	var snapshot = _create_test_snapshot()
	# Target is within ruins polygon
	var ruins_center = Vector2(600, 200)
	snapshot.board.terrain_features = [{
		"type": "ruins",
		"polygon": _make_ruins_polygon(ruins_center)
	}]
	_add_unit(snapshot, "shooter", 1, Vector2(200, 200))
	_add_unit(snapshot, "target", 2, ruins_center)  # Target inside ruins
	var result = AIDecisionMaker._target_has_benefit_of_cover(
		snapshot.units["target"], snapshot.units["shooter"], snapshot)
	_assert(result == true, "Target within ruins has cover")

func test_terrain_cover_ruins_behind():
	var snapshot = _create_test_snapshot()
	# Ruins between shooter and target
	var ruins_center = Vector2(400, 200)
	snapshot.board.terrain_features = [{
		"type": "ruins",
		"polygon": _make_ruins_polygon(ruins_center, 100.0)
	}]
	_add_unit(snapshot, "shooter", 1, Vector2(100, 200))
	_add_unit(snapshot, "target", 2, Vector2(700, 200))  # Behind the ruins
	var result = AIDecisionMaker._target_has_benefit_of_cover(
		snapshot.units["target"], snapshot.units["shooter"], snapshot)
	_assert(result == true, "Target behind ruins has cover (LoS crosses terrain)")

func test_terrain_cover_woods_within():
	var snapshot = _create_test_snapshot()
	var woods_center = Vector2(600, 200)
	snapshot.board.terrain_features = [{
		"type": "woods",
		"polygon": _make_ruins_polygon(woods_center)
	}]
	_add_unit(snapshot, "shooter", 1, Vector2(200, 200))
	_add_unit(snapshot, "target", 2, woods_center)  # Target inside woods
	var result = AIDecisionMaker._target_has_benefit_of_cover(
		snapshot.units["target"], snapshot.units["shooter"], snapshot)
	_assert(result == true, "Target within woods has cover")

func test_no_cover_outside_terrain():
	var snapshot = _create_test_snapshot()
	# Terrain exists but target is not within or behind it
	var ruins_center = Vector2(400, 600)  # Far away from the line of fire
	snapshot.board.terrain_features = [{
		"type": "ruins",
		"polygon": _make_ruins_polygon(ruins_center, 100.0)
	}]
	_add_unit(snapshot, "shooter", 1, Vector2(200, 200))
	_add_unit(snapshot, "target", 2, Vector2(600, 200))  # Not in cover
	var result = AIDecisionMaker._target_has_benefit_of_cover(
		snapshot.units["target"], snapshot.units["shooter"], snapshot)
	_assert(result == false, "Target not within or behind terrain has no cover")

func test_no_cover_empty_shooter():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "target", 2, Vector2(600, 200))
	# Empty shooter unit — can't determine terrain cover
	var result = AIDecisionMaker._target_has_benefit_of_cover(
		snapshot.units["target"], {}, snapshot)
	_assert(result == false, "Empty shooter unit: no terrain cover check possible")

# =========================================================================
# Tests: _weapon_ignores_cover
# =========================================================================

func test_weapon_ignores_cover_special_rule():
	var weapon = _make_ranged_weapon("Heavy bolter", 3, 5, 1, 2, 3, 36, "Ignores Cover")
	var result = AIDecisionMaker._weapon_ignores_cover(weapon)
	_assert(result == true, "Weapon with 'Ignores Cover' special rule ignores cover")

func test_weapon_does_not_ignore_cover():
	var weapon = _make_ranged_weapon()
	var result = AIDecisionMaker._weapon_ignores_cover(weapon)
	_assert(result == false, "Weapon without 'Ignores Cover' does not ignore cover")

func test_weapon_ignores_cover_effect_flag():
	var weapon = _make_ranged_weapon()
	var shooter = {
		"flags": {"effect_ignores_cover": true},
		"models": [{"alive": true}],
		"meta": {"stats": {}}
	}
	var result = AIDecisionMaker._weapon_ignores_cover(weapon, shooter)
	_assert(result == true, "Shooter unit with effect_ignores_cover flag ignores cover")

# =========================================================================
# Tests: _check_position_has_terrain_cover
# =========================================================================

func test_position_cover_ruins_los_blocked():
	var terrain_features = [{
		"type": "ruins",
		"polygon": _make_ruins_polygon(Vector2(400, 200), 100.0)
	}]
	var result = AIDecisionMaker._check_position_has_terrain_cover(
		Vector2(700, 200), Vector2(100, 200), terrain_features)
	_assert(result == true, "Position behind ruins has terrain cover (LoS blocked)")

func test_position_no_cover_clear_los():
	var terrain_features = [{
		"type": "ruins",
		"polygon": _make_ruins_polygon(Vector2(400, 600), 100.0)  # Far away
	}]
	var result = AIDecisionMaker._check_position_has_terrain_cover(
		Vector2(700, 200), Vector2(100, 200), terrain_features)
	_assert(result == false, "Position with clear LoS has no terrain cover")

func test_position_cover_area_terrain_within():
	var terrain_features = [{
		"type": "woods",
		"polygon": _make_ruins_polygon(Vector2(400, 200), 200.0)
	}]
	# Target inside woods
	var result = AIDecisionMaker._check_position_has_terrain_cover(
		Vector2(400, 200), Vector2(800, 200), terrain_features)
	_assert(result == true, "Position within woods has terrain cover")

func test_position_no_cover_area_terrain_outside():
	var terrain_features = [{
		"type": "woods",
		"polygon": _make_ruins_polygon(Vector2(400, 200), 100.0)
	}]
	# Target outside woods (behind it) — woods only grant cover when within
	var result = AIDecisionMaker._check_position_has_terrain_cover(
		Vector2(700, 200), Vector2(100, 200), terrain_features)
	_assert(result == false, "Position behind woods but outside has no cover (within only)")

# =========================================================================
# Tests: _score_shooting_target integration with cover
# =========================================================================

func test_score_lower_with_cover():
	var snapshot = _create_test_snapshot()
	# Target with cover (effect flag) should score lower than without
	_add_unit(snapshot, "shooter", 1, Vector2(200, 200))
	_add_unit(snapshot, "target_no_cover", 2, Vector2(600, 200), "No Cover", 5)
	_add_unit(snapshot, "target_cover", 2, Vector2(600, 400), "Cover", 5,
		["INFANTRY"], [], 4, 3, 2, 0, {"effect_cover": true})

	var weapon = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2)

	var score_no_cover = AIDecisionMaker._score_shooting_target(
		weapon, snapshot.units["target_no_cover"], snapshot, snapshot.units["shooter"])
	var score_with_cover = AIDecisionMaker._score_shooting_target(
		weapon, snapshot.units["target_cover"], snapshot, snapshot.units["shooter"])

	_assert(score_with_cover < score_no_cover,
		"Score with cover (%.4f) < score without cover (%.4f)" % [score_with_cover, score_no_cover])

func test_score_unchanged_ignores_cover_weapon():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "shooter", 1, Vector2(200, 200))
	_add_unit(snapshot, "target_no_cover", 2, Vector2(600, 200), "No Cover", 5)
	_add_unit(snapshot, "target_cover", 2, Vector2(600, 400), "Cover", 5,
		["INFANTRY"], [], 4, 3, 2, 0, {"effect_cover": true})

	var weapon = _make_ranged_weapon("Heavy bolter IC", 3, 5, 1, 2, 3, 36, "Ignores Cover")

	var score_no_cover = AIDecisionMaker._score_shooting_target(
		weapon, snapshot.units["target_no_cover"], snapshot, snapshot.units["shooter"])
	var score_with_cover = AIDecisionMaker._score_shooting_target(
		weapon, snapshot.units["target_cover"], snapshot, snapshot.units["shooter"])

	_assert_approx(score_with_cover, score_no_cover, 0.001,
		"Ignores Cover weapon: score identical with/without cover")

func test_score_unchanged_no_cover():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "shooter", 1, Vector2(200, 200))
	_add_unit(snapshot, "target", 2, Vector2(600, 200), "Target", 5)

	var weapon = _make_ranged_weapon()

	var score = AIDecisionMaker._score_shooting_target(
		weapon, snapshot.units["target"], snapshot, snapshot.units["shooter"])
	_assert(score > 0.0, "Score is positive for target without cover (%.4f)" % score)

func test_score_cover_with_invuln_interaction():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "shooter", 1, Vector2(200, 200))
	# Target with 4++ invuln and cover. With AP-3 weapon:
	# Without cover: armour 3+ AP-3 = 6+, invuln 4+ is better -> uses 4+
	# With cover: armour 2+ (cover) AP-3 = 5+, invuln 4+ is better -> uses 4+
	# So cover shouldn't change score when invuln is dominant
	_add_unit(snapshot, "target_no_cover", 2, Vector2(600, 200), "No Cover", 5,
		["INFANTRY"], [], 4, 3, 2, 4)
	_add_unit(snapshot, "target_cover", 2, Vector2(600, 400), "Cover", 5,
		["INFANTRY"], [], 4, 3, 2, 4, {"effect_cover": true})

	var weapon = _make_ranged_weapon("Lascannon", 3, 9, 3, 6, 1)

	var score_no_cover = AIDecisionMaker._score_shooting_target(
		weapon, snapshot.units["target_no_cover"], snapshot, snapshot.units["shooter"])
	var score_with_cover = AIDecisionMaker._score_shooting_target(
		weapon, snapshot.units["target_cover"], snapshot, snapshot.units["shooter"])

	_assert_approx(score_with_cover, score_no_cover, 0.001,
		"Cover irrelevant when invuln save is better (AP-3 vs 4++ invuln)")

func test_score_cover_cap_at_2_plus():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "shooter", 1, Vector2(200, 200))
	# Target with 2+ save and cover — should still be 2+ (not 1+)
	_add_unit(snapshot, "target_cover", 2, Vector2(600, 200), "Terminator", 5,
		["INFANTRY"], [], 5, 2, 3, 0, {"effect_cover": true})
	_add_unit(snapshot, "target_no_cover", 2, Vector2(600, 400), "Terminator NC", 5,
		["INFANTRY"], [], 5, 2, 3, 0)

	# AP 0 weapon: with 2+ save, cover can't improve beyond 2+
	var weapon = _make_ranged_weapon("Boltgun", 3, 4, 0, 1, 2)

	var score_no_cover = AIDecisionMaker._score_shooting_target(
		weapon, snapshot.units["target_no_cover"], snapshot, snapshot.units["shooter"])
	var score_with_cover = AIDecisionMaker._score_shooting_target(
		weapon, snapshot.units["target_cover"], snapshot, snapshot.units["shooter"])

	_assert_approx(score_with_cover, score_no_cover, 0.001,
		"2+ save with cover stays 2+ (can't go below 2+)")

func test_score_cover_effect_flag():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "shooter", 1, Vector2(200, 200))
	# Target with effect_cover from stratagem (Go to Ground / Smokescreen)
	_add_unit(snapshot, "target", 2, Vector2(600, 200), "Target", 5,
		["INFANTRY"], [], 4, 4, 2, 0, {"effect_cover": true})

	var weapon = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2)

	# 4+ save with cover = 3+ effective save
	# Without cover: p_unsaved with 4+ save AP-1 = 1 - save_prob(4, 1) = 1 - (7-5)/6 = 1 - 2/6 = 4/6
	# With cover: p_unsaved with 3+ save AP-1 = 1 - save_prob(3, 1) = 1 - (7-4)/6 = 1 - 3/6 = 3/6
	# Cover should reduce damage by ratio of (3/6) / (4/6) = 0.75
	var score = AIDecisionMaker._score_shooting_target(
		weapon, snapshot.units["target"], snapshot, snapshot.units["shooter"])
	_assert(score > 0.0, "Covered target still has positive score (%.4f)" % score)

func test_score_cover_with_ap0():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "shooter", 1, Vector2(200, 200))
	# Target with 4+ save and cover, weapon has AP 0
	# Without cover: save 4+ -> prob = 3/6, p_unsaved = 3/6
	# With cover: save 3+ -> prob = 4/6, p_unsaved = 2/6
	_add_unit(snapshot, "target_no_cover", 2, Vector2(600, 200), "No Cover", 5,
		["INFANTRY"], [], 4, 4, 2)
	_add_unit(snapshot, "target_cover", 2, Vector2(600, 400), "Cover", 5,
		["INFANTRY"], [], 4, 4, 2, 0, {"effect_cover": true})

	var weapon = _make_ranged_weapon("Shuriken catapult", 3, 4, 0, 1, 2)

	var score_no_cover = AIDecisionMaker._score_shooting_target(
		weapon, snapshot.units["target_no_cover"], snapshot, snapshot.units["shooter"])
	var score_with_cover = AIDecisionMaker._score_shooting_target(
		weapon, snapshot.units["target_cover"], snapshot, snapshot.units["shooter"])

	_assert(score_with_cover < score_no_cover,
		"Cover helps even with AP0: score %.4f < %.4f" % [score_with_cover, score_no_cover])

# =========================================================================
# Tests: _estimate_weapon_damage integration with cover
# =========================================================================

func test_estimate_damage_lower_with_cover():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "shooter", 1, Vector2(200, 200))
	_add_unit(snapshot, "target_no_cover", 2, Vector2(600, 200), "No Cover", 5)
	_add_unit(snapshot, "target_cover", 2, Vector2(600, 400), "Cover", 5,
		["INFANTRY"], [], 4, 3, 2, 0, {"effect_cover": true})

	var weapon = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2)

	var dmg_no_cover = AIDecisionMaker._estimate_weapon_damage(
		weapon, snapshot.units["target_no_cover"], snapshot, snapshot.units["shooter"])
	var dmg_with_cover = AIDecisionMaker._estimate_weapon_damage(
		weapon, snapshot.units["target_cover"], snapshot, snapshot.units["shooter"])

	_assert(dmg_with_cover < dmg_no_cover,
		"_estimate_weapon_damage: damage with cover (%.4f) < without cover (%.4f)" % [dmg_with_cover, dmg_no_cover])

func test_estimate_damage_ignores_cover():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "shooter", 1, Vector2(200, 200))
	_add_unit(snapshot, "target_no_cover", 2, Vector2(600, 200), "No Cover", 5)
	_add_unit(snapshot, "target_cover", 2, Vector2(600, 400), "Cover", 5,
		["INFANTRY"], [], 4, 3, 2, 0, {"effect_cover": true})

	var weapon = _make_ranged_weapon("Sniper", 3, 4, 1, 1, 1, 36, "Ignores Cover")

	var dmg_no_cover = AIDecisionMaker._estimate_weapon_damage(
		weapon, snapshot.units["target_no_cover"], snapshot, snapshot.units["shooter"])
	var dmg_with_cover = AIDecisionMaker._estimate_weapon_damage(
		weapon, snapshot.units["target_cover"], snapshot, snapshot.units["shooter"])

	_assert_approx(dmg_with_cover, dmg_no_cover, 0.001,
		"_estimate_weapon_damage: Ignores Cover weapon treats covered/uncovered same")
