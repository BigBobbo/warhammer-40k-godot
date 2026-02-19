extends SceneTree

# Test AI Weapon Range Checking in Target Scoring
# Verifies that _score_shooting_target returns 0 for out-of-range targets
# and positive scores for in-range targets.
# Run with: godot --headless --script tests/unit/test_ai_weapon_range_scoring.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== AI Weapon Range Scoring Tests ===\n")
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
	test_get_weapon_range_inches_standard()
	test_get_weapon_range_inches_melee()
	test_get_weapon_range_inches_zero()
	test_get_weapon_range_inches_invalid()
	test_score_zero_for_out_of_range_target()
	test_score_positive_for_in_range_target()
	test_score_positive_at_exact_range()
	test_score_without_shooter_unit_skips_range_check()
	test_score_with_different_weapon_ranges()
	test_decide_shooting_skips_out_of_range_targets()
	test_decide_shooting_assigns_in_range_target()

# =========================================================================
# Helper: Create a test snapshot
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
		wounds: int = 2) -> void:
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

func _make_melee_weapon(wname: String = "Close combat weapon") -> Dictionary:
	return {
		"name": wname,
		"type": "Melee",
		"weapon_skill": "3",
		"strength": "4",
		"ap": "0",
		"damage": "1",
		"attacks": "3",
		"range": "Melee",
	}

# =========================================================================
# Tests: _get_weapon_range_inches
# =========================================================================

func test_get_weapon_range_inches_standard():
	var weapon = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2, 24)
	var range_inches = AIDecisionMaker._get_weapon_range_inches(weapon)
	_assert_approx(range_inches, 24.0, 0.01, "_get_weapon_range_inches returns 24 for bolt rifle")

func test_get_weapon_range_inches_melee():
	var weapon = _make_melee_weapon()
	var range_inches = AIDecisionMaker._get_weapon_range_inches(weapon)
	_assert_approx(range_inches, 0.0, 0.01, "_get_weapon_range_inches returns 0 for melee weapon")

func test_get_weapon_range_inches_zero():
	var weapon = {"range": "0"}
	var range_inches = AIDecisionMaker._get_weapon_range_inches(weapon)
	_assert_approx(range_inches, 0.0, 0.01, "_get_weapon_range_inches returns 0 for range '0'")

func test_get_weapon_range_inches_invalid():
	var weapon = {"range": "N/A"}
	var range_inches = AIDecisionMaker._get_weapon_range_inches(weapon)
	_assert_approx(range_inches, 0.0, 0.01, "_get_weapon_range_inches returns 0 for invalid range string")

# =========================================================================
# Tests: _score_shooting_target range checking
# =========================================================================

func test_score_zero_for_out_of_range_target():
	# Weapon range: 24". Place shooter and target 30" apart (1200px / 40px per inch = 30")
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2, 24)

	# Shooter at origin, target 30" away (1200px)
	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [weapon])
	_add_unit(snapshot, "target", 2, Vector2(1200, 0), "Target", 1, ["INFANTRY"], [], 4, 3, 2)

	var shooter_unit = snapshot.units["shooter"]
	var target_unit = snapshot.units["target"]
	var score = AIDecisionMaker._score_shooting_target(weapon, target_unit, snapshot, shooter_unit)
	_assert(score == 0.0, "Score is 0 for target at 30\" when weapon range is 24\"")

func test_score_positive_for_in_range_target():
	# Weapon range: 24". Place shooter and target 20" apart (800px)
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2, 24)

	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [weapon])
	_add_unit(snapshot, "target", 2, Vector2(800, 0), "Target", 1, ["INFANTRY"], [], 4, 3, 2)

	var shooter_unit = snapshot.units["shooter"]
	var target_unit = snapshot.units["target"]
	var score = AIDecisionMaker._score_shooting_target(weapon, target_unit, snapshot, shooter_unit)
	_assert(score > 0.0, "Score is positive for target at 20\" when weapon range is 24\" (got %.2f)" % score)

func test_score_positive_at_exact_range():
	# Weapon range: 24". Place shooter and target exactly 24" apart (960px)
	# Note: edge-to-edge distance will be slightly less than 24" due to base radii
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2, 24)

	# 24" = 960px center-to-center. With 32mm bases (radius ~25.2px each), edge-to-edge is about 22.7"
	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [weapon])
	_add_unit(snapshot, "target", 2, Vector2(960, 0), "Target", 1, ["INFANTRY"], [], 4, 3, 2)

	var shooter_unit = snapshot.units["shooter"]
	var target_unit = snapshot.units["target"]
	var score = AIDecisionMaker._score_shooting_target(weapon, target_unit, snapshot, shooter_unit)
	_assert(score > 0.0, "Score is positive at edge-to-edge distance near 24\" (got %.2f)" % score)

func test_score_without_shooter_unit_skips_range_check():
	# When no shooter_unit is provided, range check should be skipped (backward compatibility)
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2, 24)

	_add_unit(snapshot, "target", 2, Vector2(2000, 0), "Target", 1, ["INFANTRY"], [], 4, 3, 2)

	var target_unit = snapshot.units["target"]
	# Call without shooter_unit — should NOT check range
	var score = AIDecisionMaker._score_shooting_target(weapon, target_unit, snapshot)
	_assert(score > 0.0, "Score is positive when no shooter_unit provided (backward compat, got %.2f)" % score)

func test_score_with_different_weapon_ranges():
	# Short range weapon (12") should score 0 at 20", but long range weapon (48") should score > 0
	var snapshot = _create_test_snapshot()
	var pistol = _make_ranged_weapon("Bolt pistol", 3, 4, 0, 1, 1, 12)
	var heavy = _make_ranged_weapon("Lascannon", 3, 12, 3, 6, 1, 48)

	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [pistol, heavy])
	_add_unit(snapshot, "target", 2, Vector2(800, 0), "Target", 1, ["VEHICLE"], [], 10, 3, 12)

	var shooter_unit = snapshot.units["shooter"]
	var target_unit = snapshot.units["target"]

	var pistol_score = AIDecisionMaker._score_shooting_target(pistol, target_unit, snapshot, shooter_unit)
	var heavy_score = AIDecisionMaker._score_shooting_target(heavy, target_unit, snapshot, shooter_unit)

	_assert(pistol_score == 0.0, "Bolt pistol (12\") scores 0 at 20\" distance (got %.2f)" % pistol_score)
	_assert(heavy_score > 0.0, "Lascannon (48\") scores positive at 20\" distance (got %.2f)" % heavy_score)

# =========================================================================
# Tests: _decide_shooting integration with range checking
# =========================================================================

func test_decide_shooting_skips_out_of_range_targets():
	# Place a shooter with 24" weapon and only an enemy at 40" away
	# AI should skip the unit since no valid targets are in range
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2, 24)

	_add_unit(snapshot, "shooter", 2, Vector2(0, 0), "AI Shooter", 5, ["INFANTRY"], [weapon])
	_add_unit(snapshot, "enemy", 1, Vector2(1600, 0), "Enemy", 5, ["INFANTRY"], [], 4, 3, 2)

	var available = [
		{"type": "SELECT_SHOOTER", "actor_unit_id": "shooter"}
	]

	var decision = AIDecisionMaker._decide_shooting(snapshot, available, 2)
	_assert(decision.get("type", "") == "SKIP_UNIT", "AI skips shooter when all targets are out of range (got type: %s)" % decision.get("type", ""))
	_assert("no valid targets" in decision.get("_ai_description", "").to_lower(), "Skip description mentions no valid targets")

func test_decide_shooting_assigns_in_range_target():
	# Place a shooter with 24" weapon and an enemy at 20" away
	# AI should produce a SHOOT action with an assignment
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2, 24)

	_add_unit(snapshot, "shooter", 2, Vector2(0, 0), "AI Shooter", 5, ["INFANTRY"], [weapon])
	_add_unit(snapshot, "enemy", 1, Vector2(800, 0), "Enemy", 5, ["INFANTRY"], [], 4, 3, 2)

	var available = [
		{"type": "SELECT_SHOOTER", "actor_unit_id": "shooter"}
	]

	var decision = AIDecisionMaker._decide_shooting(snapshot, available, 2)
	_assert(decision.get("type", "") == "SHOOT", "AI produces SHOOT action for in-range target (got type: %s)" % decision.get("type", ""))

	var assignments = decision.get("payload", {}).get("assignments", [])
	_assert(assignments.size() > 0, "SHOOT action has at least one weapon assignment")
	if assignments.size() > 0:
		_assert(assignments[0].get("target_unit_id", "") == "enemy", "Assignment targets the enemy unit")
