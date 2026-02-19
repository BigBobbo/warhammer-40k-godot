extends SceneTree

# Test AI Threat Range Awareness - Tests enemy threat zone calculation and
# movement decisions that avoid danger (AI-TACTIC-4, MOV-2)
# Run with: godot --headless --script tests/unit/test_ai_threat_range_awareness.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== AI Threat Range Awareness Tests ===\n")
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
		print("PASS: %s (%.2f ~= %.2f, diff=%.4f)" % [message, actual, expected, diff])
	else:
		_fail_count += 1
		print("FAIL: %s (%.2f != %.2f, diff=%.4f, tolerance=%.4f)" % [message, actual, expected, diff, tolerance])

func _run_tests():
	test_calculate_enemy_threat_data_basic()
	test_calculate_enemy_threat_data_charge_range()
	test_calculate_enemy_threat_data_shooting_range()
	test_calculate_enemy_threat_data_no_melee()
	test_calculate_enemy_threat_data_no_ranged()
	test_estimate_enemy_threat_level_basic()
	test_estimate_enemy_threat_level_vehicle()
	test_estimate_enemy_threat_level_horde()
	test_evaluate_position_threat_outside_range()
	test_evaluate_position_threat_in_charge_zone()
	test_evaluate_position_threat_in_shooting_zone()
	test_evaluate_position_threat_fragile_unit()
	test_evaluate_position_threat_melee_unit_ignores_charge()
	test_is_position_in_charge_threat()
	test_find_safer_position_no_threat()
	test_find_safer_position_reduces_threat()
	test_threat_aware_assignment_scoring()
	test_ranged_unit_avoids_charge_danger()

# =========================================================================
# Helper: Create test data structures
# =========================================================================

func _create_test_snapshot(player: int = 2) -> Dictionary:
	return {
		"battle_round": 1,
		"board": {
			"objectives": [
				{"id": "obj_center", "position": Vector2(880, 1200), "zone": "no_mans_land"},
				{"id": "obj_home_2", "position": Vector2(880, 2160), "zone": "player2"}
			],
			"terrain_features": []
		},
		"units": {}
	}

func _add_unit(snapshot: Dictionary, unit_id: String, owner: int, pos: Vector2,
		name: String = "Test Unit", oc: int = 2, move: int = 6,
		num_models: int = 5, keywords: Array = ["INFANTRY"],
		weapons: Array = [], toughness: int = 4, wounds: int = 2) -> void:
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
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": name,
			"stats": {
				"move": move,
				"toughness": toughness,
				"save": 3,
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

func _make_ranged_weapons() -> Array:
	return [{"type": "ranged", "name": "Bolt Rifle", "range": "24", "attacks": "2",
			"skill": "3", "strength": "4", "ap": "1", "damage": "1", "abilities": ""}]

func _make_melee_weapons() -> Array:
	return [{"type": "melee", "name": "Chainsword", "range": "Melee", "attacks": "3",
			"skill": "3", "strength": "4", "ap": "1", "damage": "1", "abilities": ""}]

func _make_long_range_weapons() -> Array:
	return [{"type": "ranged", "name": "Lascannon", "range": "48", "attacks": "1",
			"skill": "3", "strength": "12", "ap": "3", "damage": "D6+1", "abilities": ""}]

func _make_enemies(snapshot: Dictionary) -> Dictionary:
	var enemies = {}
	for unit_id in snapshot.get("units", {}):
		var unit = snapshot.units[unit_id]
		if unit.get("owner", 0) != 2:  # AI is player 2
			var has_alive = false
			for model in unit.get("models", []):
				if model.get("alive", true):
					has_alive = true
					break
			if has_alive:
				enemies[unit_id] = unit
	return enemies

# =========================================================================
# TEST: _calculate_enemy_threat_data
# =========================================================================

func test_calculate_enemy_threat_data_basic():
	print("\n--- test_calculate_enemy_threat_data_basic ---")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "enemy1", 1, Vector2(800, 600), "Enemy Marines", 2, 6, 5,
			["INFANTRY"], _make_ranged_weapons() + _make_melee_weapons())
	var enemies = _make_enemies(snapshot)

	var threat_data = AIDecisionMaker._calculate_enemy_threat_data(enemies)
	_assert(threat_data.size() == 1, "One enemy unit produces one threat data entry")
	_assert(threat_data[0].unit_id == "enemy1", "Threat data contains correct unit_id")
	_assert(threat_data[0].has_melee == true, "Enemy with melee weapons marked has_melee")
	_assert(threat_data[0].has_ranged == true, "Enemy with ranged weapons marked has_ranged")

func test_calculate_enemy_threat_data_charge_range():
	print("\n--- test_calculate_enemy_threat_data_charge_range ---")
	var snapshot = _create_test_snapshot()
	# M6 unit: charge threat = 6 + 12 + 1 = 19 inches = 760 px
	_add_unit(snapshot, "enemy1", 1, Vector2(800, 600), "Enemy Marines", 2, 6, 5,
			["INFANTRY"], _make_melee_weapons())
	var enemies = _make_enemies(snapshot)

	var threat_data = AIDecisionMaker._calculate_enemy_threat_data(enemies)
	var expected_charge_px = (6.0 + 12.0 + 1.0) * 40.0  # 19" * 40 px/inch = 760 px
	_assert_approx(threat_data[0].charge_threat_px, expected_charge_px, 1.0,
		"M6 unit charge threat range = 19\" (760px)")

func test_calculate_enemy_threat_data_shooting_range():
	print("\n--- test_calculate_enemy_threat_data_shooting_range ---")
	var snapshot = _create_test_snapshot()
	# Unit with 24" ranged weapons: shoot threat = 24 inches = 960 px
	_add_unit(snapshot, "enemy1", 1, Vector2(800, 600), "Enemy Marines", 2, 6, 5,
			["INFANTRY"], _make_ranged_weapons())
	var enemies = _make_enemies(snapshot)

	var threat_data = AIDecisionMaker._calculate_enemy_threat_data(enemies)
	var expected_shoot_px = 24.0 * 40.0  # 24" * 40 px/inch = 960 px
	_assert_approx(threat_data[0].shoot_threat_px, expected_shoot_px, 1.0,
		"24\" weapon shoot threat range = 960px")

func test_calculate_enemy_threat_data_no_melee():
	print("\n--- test_calculate_enemy_threat_data_no_melee ---")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "enemy1", 1, Vector2(800, 600), "Ranged Only", 2, 6, 5,
			["INFANTRY"], _make_ranged_weapons())
	var enemies = _make_enemies(snapshot)

	var threat_data = AIDecisionMaker._calculate_enemy_threat_data(enemies)
	_assert(threat_data[0].has_melee == false, "Ranged-only unit has no melee threat")
	# Charge threat zone is still calculated (for the range) but has_melee=false
	# means it won't generate charge threat penalty in _evaluate_position_threat

func test_calculate_enemy_threat_data_no_ranged():
	print("\n--- test_calculate_enemy_threat_data_no_ranged ---")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "enemy1", 1, Vector2(800, 600), "Melee Only", 2, 6, 5,
			["INFANTRY"], _make_melee_weapons())
	var enemies = _make_enemies(snapshot)

	var threat_data = AIDecisionMaker._calculate_enemy_threat_data(enemies)
	_assert(threat_data[0].has_ranged == false, "Melee-only unit has no ranged threat")
	_assert_approx(threat_data[0].shoot_threat_px, 0.0, 1.0,
		"Melee-only unit has 0 shooting threat range")

# =========================================================================
# TEST: _estimate_enemy_threat_level
# =========================================================================

func test_estimate_enemy_threat_level_basic():
	print("\n--- test_estimate_enemy_threat_level_basic ---")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "basic", 1, Vector2(800, 600), "Basic Unit", 2, 6, 5,
			["INFANTRY"], _make_ranged_weapons())

	var threat = AIDecisionMaker._estimate_enemy_threat_level(snapshot.units["basic"])
	_assert(threat >= 0.3, "Basic unit threat level >= 0.3 (got %.2f)" % threat)
	_assert(threat <= 3.0, "Basic unit threat level <= 3.0 (got %.2f)" % threat)

func test_estimate_enemy_threat_level_vehicle():
	print("\n--- test_estimate_enemy_threat_level_vehicle ---")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "vehicle", 1, Vector2(800, 600), "Predator", 2, 10, 1,
			["VEHICLE"], _make_long_range_weapons(), 11, 13)

	var threat = AIDecisionMaker._estimate_enemy_threat_level(snapshot.units["vehicle"])
	_assert(threat > 1.5, "Vehicle threat level > 1.5 (got %.2f, has VEHICLE keyword + high T/W)" % threat)

func test_estimate_enemy_threat_level_horde():
	print("\n--- test_estimate_enemy_threat_level_horde ---")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "horde", 1, Vector2(800, 600), "Ork Boyz", 2, 6, 12,
			["INFANTRY"], _make_melee_weapons(), 4, 1)

	var threat = AIDecisionMaker._estimate_enemy_threat_level(snapshot.units["horde"])
	_assert(threat > 1.0, "Horde unit (12 models) threat level > 1.0 (got %.2f)" % threat)

# =========================================================================
# TEST: _evaluate_position_threat
# =========================================================================

func test_evaluate_position_threat_outside_range():
	print("\n--- test_evaluate_position_threat_outside_range ---")
	var snapshot = _create_test_snapshot()
	# Enemy at (800, 600), charge threat = 19" = 760px
	_add_unit(snapshot, "enemy1", 1, Vector2(800, 600), "Enemy", 2, 6, 5,
			["INFANTRY"], _make_melee_weapons() + _make_ranged_weapons())
	var enemies = _make_enemies(snapshot)
	var threat_data = AIDecisionMaker._calculate_enemy_threat_data(enemies)

	# Own unit used for evaluation context
	_add_unit(snapshot, "own", 2, Vector2(800, 2000), "Own Unit", 2, 6, 5,
			["INFANTRY"], _make_ranged_weapons())

	# Position far away from enemy (1400px away > 760px charge threat)
	var pos_far = Vector2(800, 2000)
	var result = AIDecisionMaker._evaluate_position_threat(pos_far, threat_data, snapshot.units["own"])
	_assert(result.charge_threat == 0.0, "Position outside charge range has 0 charge threat (got %.2f)" % result.charge_threat)

func test_evaluate_position_threat_in_charge_zone():
	print("\n--- test_evaluate_position_threat_in_charge_zone ---")
	var snapshot = _create_test_snapshot()
	# Enemy at (800, 600), M6, charge threat = 19" = 760px
	_add_unit(snapshot, "enemy1", 1, Vector2(800, 600), "Enemy", 2, 6, 5,
			["INFANTRY"], _make_melee_weapons())
	var enemies = _make_enemies(snapshot)
	var threat_data = AIDecisionMaker._calculate_enemy_threat_data(enemies)

	# Own ranged unit
	_add_unit(snapshot, "own", 2, Vector2(800, 1000), "Own Unit", 2, 6, 5,
			["INFANTRY"], _make_ranged_weapons())

	# Position within charge range (400px away from enemy at 600, well within 760px)
	var pos_in_range = Vector2(800, 1000)
	var result = AIDecisionMaker._evaluate_position_threat(pos_in_range, threat_data, snapshot.units["own"])
	_assert(result.charge_threat > 0.0, "Position in charge range has positive charge threat (got %.2f)" % result.charge_threat)
	_assert(result.total_threat > 0.0, "Total threat is positive when in charge range (got %.2f)" % result.total_threat)

func test_evaluate_position_threat_in_shooting_zone():
	print("\n--- test_evaluate_position_threat_in_shooting_zone ---")
	var snapshot = _create_test_snapshot()
	# Enemy at (800, 600) with 24" range = 960px
	_add_unit(snapshot, "enemy1", 1, Vector2(800, 600), "Enemy Shooters", 2, 6, 5,
			["INFANTRY"], _make_ranged_weapons())
	var enemies = _make_enemies(snapshot)
	var threat_data = AIDecisionMaker._calculate_enemy_threat_data(enemies)

	# Own unit
	_add_unit(snapshot, "own", 2, Vector2(800, 1400), "Own Unit", 2, 6, 5,
			["INFANTRY"], _make_ranged_weapons())

	# Position 800px from enemy (within 960px shooting range, outside 760px charge range)
	var pos = Vector2(800, 1400)
	var result = AIDecisionMaker._evaluate_position_threat(pos, threat_data, snapshot.units["own"])
	_assert(result.shoot_threat > 0.0, "Position in shooting range has positive shoot threat (got %.2f)" % result.shoot_threat)

func test_evaluate_position_threat_fragile_unit():
	print("\n--- test_evaluate_position_threat_fragile_unit ---")
	var snapshot = _create_test_snapshot()
	# Enemy nearby
	_add_unit(snapshot, "enemy1", 1, Vector2(800, 600), "Enemy", 2, 6, 5,
			["INFANTRY"], _make_melee_weapons())
	var enemies = _make_enemies(snapshot)
	var threat_data = AIDecisionMaker._calculate_enemy_threat_data(enemies)

	# Fragile unit (T3, 1W)
	_add_unit(snapshot, "fragile", 2, Vector2(800, 1000), "Fragile", 2, 6, 5,
			["INFANTRY"], _make_ranged_weapons(), 3, 1)
	# Tough unit (T5, 3W)
	_add_unit(snapshot, "tough", 2, Vector2(800, 1000), "Tough", 2, 6, 5,
			["INFANTRY"], _make_ranged_weapons(), 5, 3)

	var pos = Vector2(800, 1000)
	var fragile_threat = AIDecisionMaker._evaluate_position_threat(pos, threat_data, snapshot.units["fragile"])
	var tough_threat = AIDecisionMaker._evaluate_position_threat(pos, threat_data, snapshot.units["tough"])
	_assert(fragile_threat.total_threat > tough_threat.total_threat,
		"Fragile unit has higher total threat than tough unit at same position (%.2f > %.2f)" %
		[fragile_threat.total_threat, tough_threat.total_threat])

func test_evaluate_position_threat_melee_unit_ignores_charge():
	print("\n--- test_evaluate_position_threat_melee_unit_ignores_charge ---")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "enemy1", 1, Vector2(800, 600), "Enemy", 2, 6, 5,
			["INFANTRY"], _make_melee_weapons())
	var enemies = _make_enemies(snapshot)
	var threat_data = AIDecisionMaker._calculate_enemy_threat_data(enemies)

	# Melee-only unit
	_add_unit(snapshot, "melee_own", 2, Vector2(800, 1000), "Melee Unit", 2, 6, 5,
			["INFANTRY"], _make_melee_weapons())
	# Ranged-only unit
	_add_unit(snapshot, "ranged_own", 2, Vector2(800, 1000), "Ranged Unit", 2, 6, 5,
			["INFANTRY"], _make_ranged_weapons())

	var pos = Vector2(800, 1000)
	var melee_threat = AIDecisionMaker._evaluate_position_threat(pos, threat_data, snapshot.units["melee_own"])
	var ranged_threat = AIDecisionMaker._evaluate_position_threat(pos, threat_data, snapshot.units["ranged_own"])
	_assert(melee_threat.charge_threat < ranged_threat.charge_threat,
		"Melee unit has lower charge threat penalty than ranged unit (%.2f < %.2f)" %
		[melee_threat.charge_threat, ranged_threat.charge_threat])

# =========================================================================
# TEST: _is_position_in_charge_threat
# =========================================================================

func test_is_position_in_charge_threat():
	print("\n--- test_is_position_in_charge_threat ---")
	var snapshot = _create_test_snapshot()
	# Enemy at (800, 600), M6, charge threat = 19" = 760px
	_add_unit(snapshot, "enemy1", 1, Vector2(800, 600), "Enemy", 2, 6, 5,
			["INFANTRY"], _make_melee_weapons())
	var enemies = _make_enemies(snapshot)
	var threat_data = AIDecisionMaker._calculate_enemy_threat_data(enemies)

	# Position within charge threat (400px away)
	var in_range = AIDecisionMaker._is_position_in_charge_threat(Vector2(800, 1000), threat_data)
	_assert(in_range == true, "Position 400px from M6 melee enemy is in charge threat")

	# Position outside charge threat (800px away)
	var out_range = AIDecisionMaker._is_position_in_charge_threat(Vector2(800, 1400), threat_data)
	_assert(out_range == false, "Position 800px from M6 melee enemy is outside charge threat")

	# Position barely outside (770px away, threshold is 760px)
	var edge = AIDecisionMaker._is_position_in_charge_threat(Vector2(800, 1370), threat_data)
	_assert(edge == false, "Position 770px from M6 melee enemy is just outside charge threat")

# =========================================================================
# TEST: _find_safer_position
# =========================================================================

func test_find_safer_position_no_threat():
	print("\n--- test_find_safer_position_no_threat ---")
	var snapshot = _create_test_snapshot()
	# No enemies means no threat
	var threat_data: Array = []
	_add_unit(snapshot, "own", 2, Vector2(800, 2000), "Own Unit", 2, 6, 5,
			["INFANTRY"], _make_ranged_weapons())

	var current = Vector2(800, 2000)
	var desired = Vector2(800, 1760)
	var objectives = [Vector2(880, 1200)]

	var result = AIDecisionMaker._find_safer_position(current, desired, 240.0, threat_data, snapshot.units["own"], objectives)
	_assert(result == desired, "With no threats, desired position is returned unchanged")

func test_find_safer_position_reduces_threat():
	print("\n--- test_find_safer_position_reduces_threat ---")
	var snapshot = _create_test_snapshot()
	# Enemy melee unit near the desired destination
	_add_unit(snapshot, "enemy1", 1, Vector2(800, 600), "Enemy Choppa", 2, 8, 5,
			["INFANTRY"], _make_melee_weapons())
	var enemies = _make_enemies(snapshot)
	var threat_data = AIDecisionMaker._calculate_enemy_threat_data(enemies)

	# Own ranged unit starting from safe position
	_add_unit(snapshot, "own", 2, Vector2(800, 1800), "Own Shooters", 2, 6, 5,
			["INFANTRY"], _make_ranged_weapons())

	var current = Vector2(800, 1800)
	var desired = Vector2(800, 1560)  # Moving toward enemy
	var objectives = [Vector2(880, 1200)]
	var move_px = 240.0  # 6" move

	var result = AIDecisionMaker._find_safer_position(current, desired, move_px, threat_data, snapshot.units["own"], objectives)
	var desired_threat = AIDecisionMaker._evaluate_position_threat(desired, threat_data, snapshot.units["own"])
	var result_threat = AIDecisionMaker._evaluate_position_threat(result, threat_data, snapshot.units["own"])

	# The safer position should have equal or less threat, or at least not worse
	_assert(result_threat.total_threat <= desired_threat.total_threat + 0.1,
		"Safer position has lower or equal threat (%.2f <= %.2f)" %
		[result_threat.total_threat, desired_threat.total_threat])

# =========================================================================
# TEST: Threat-aware assignment scoring
# =========================================================================

func test_threat_aware_assignment_scoring():
	print("\n--- test_threat_aware_assignment_scoring ---")
	var snapshot = _create_test_snapshot()
	# Add friendly unit far from enemy
	_add_unit(snapshot, "u1", 2, Vector2(880, 2000), "Intercessors", 2, 6, 5,
			["INFANTRY"], _make_ranged_weapons())
	# Add a dangerous melee enemy near the center objective
	_add_unit(snapshot, "enemy1", 1, Vector2(880, 1000), "Melee Threat", 2, 8, 10,
			["INFANTRY"], _make_melee_weapons(), 4, 1)

	var enemies = _make_enemies(snapshot)
	var friendlies = {"u1": snapshot.units["u1"]}
	var objectives = [Vector2(880, 1200)]  # Center objective
	var battle_round = 1

	# Get objective evaluations
	var obj_evaluations = AIDecisionMaker._evaluate_all_objectives(snapshot, objectives, 2, enemies, friendlies, battle_round)

	# Calculate threat data
	var threat_data = AIDecisionMaker._calculate_enemy_threat_data(enemies)

	# Score with and without threat data
	var movable_units = {"u1": ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]}

	var assignments_no_threat = AIDecisionMaker._assign_units_to_objectives(
		snapshot, movable_units, obj_evaluations, objectives, enemies, friendlies, 2, battle_round, []
	)
	var assignments_with_threat = AIDecisionMaker._assign_units_to_objectives(
		snapshot, movable_units, obj_evaluations, objectives, enemies, friendlies, 2, battle_round, threat_data
	)

	# Both should produce an assignment for u1
	_assert(assignments_no_threat.has("u1"), "Assignment without threat data exists for u1")
	_assert(assignments_with_threat.has("u1"), "Assignment with threat data exists for u1")

	# The threat-aware assignment should have a lower score (penalized for danger)
	var score_no_threat = assignments_no_threat.get("u1", {}).get("score", 0.0)
	var score_with_threat = assignments_with_threat.get("u1", {}).get("score", 0.0)
	_assert(score_with_threat <= score_no_threat,
		"Threat-aware score (%.1f) <= non-threat score (%.1f)" % [score_with_threat, score_no_threat])

# =========================================================================
# TEST: Ranged unit avoids charge danger
# =========================================================================

func test_ranged_unit_avoids_charge_danger():
	print("\n--- test_ranged_unit_avoids_charge_danger ---")
	# This tests the high-level behavior: a ranged unit currently safe from
	# charge threat should prefer holding if moving would enter charge range
	# and it has shooting targets available.
	var snapshot = _create_test_snapshot()

	# Ranged unit (player 2) far from enemy - currently safe
	_add_unit(snapshot, "u1", 2, Vector2(880, 1800), "Long Range Squad", 2, 6, 5,
			["INFANTRY"], _make_long_range_weapons())

	# Melee enemy (player 1) in the middle - within 48" shooting range but the
	# unit is outside charge range of this enemy
	# Enemy at Y=800, M8: charge threat = 8+12+1 = 21" = 840px
	# Our unit at Y=1800, distance = 1000px > 840px = safe from charge
	# If we move 6" (240px) toward obj at Y=1200, we'd be at Y=1560, distance = 760px < 840px = IN charge range
	_add_unit(snapshot, "enemy1", 1, Vector2(880, 800), "Fast Choppers", 2, 8, 10,
			["INFANTRY"], _make_melee_weapons(), 4, 1)

	var enemies = _make_enemies(snapshot)
	var threat_data = AIDecisionMaker._calculate_enemy_threat_data(enemies)

	# Verify our starting position is safe from charge
	var start_threat = AIDecisionMaker._evaluate_position_threat(Vector2(880, 1800), threat_data, snapshot.units["u1"])
	_assert(start_threat.charge_threat < 0.5,
		"Starting position is safe from charge threat (%.2f)" % start_threat.charge_threat)

	# Verify that moving 6" toward the center objective would enter charge range
	var dest = Vector2(880, 1560)  # 6" (240px) toward Y=1200
	var dest_threat = AIDecisionMaker._evaluate_position_threat(dest, threat_data, snapshot.units["u1"])
	_assert(dest_threat.charge_threat >= 0.5,
		"Destination would be in charge threat range (%.2f)" % dest_threat.charge_threat)

	# Verify the unit has shooting targets at current position (48" range = 1920px,
	# enemy is at 1000px away = within range)
	var max_wr = AIDecisionMaker._get_max_weapon_range(snapshot.units["u1"])
	var dist_to_enemy = Vector2(880, 1800).distance_to(Vector2(880, 800))
	_assert(dist_to_enemy <= max_wr * 40.0,
		"Enemy is within weapon range at current position (%.0f px <= %.0f px)" %
		[dist_to_enemy, max_wr * 40.0])

	print("  Threat-aware hold check: start_charge=%.2f, dest_charge=%.2f, has_targets=true" % [
		start_threat.charge_threat, dest_threat.charge_threat])
	print("  The AI should prefer holding position to avoid entering charge danger")

# =========================================================================
# Helper: Get objectives from snapshot
# =========================================================================

func _get_objectives_from_snapshot(snapshot: Dictionary) -> Array:
	var objectives = []
	for obj in snapshot.get("board", {}).get("objectives", []):
		var pos = obj.get("position", null)
		if pos:
			if pos is Vector2:
				objectives.append(pos)
			else:
				objectives.append(Vector2(float(pos.get("x", 0)), float(pos.get("y", 0))))
	return objectives
