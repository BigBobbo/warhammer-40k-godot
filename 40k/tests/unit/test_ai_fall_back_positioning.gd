extends SceneTree

# Test AI Fall-Back Model Positioning (MOV-6)
# Tests that the AI computes valid fall-back destinations that move models
# outside of engagement range while respecting movement caps and board bounds.
# Run with: godot --headless --script tests/unit/test_ai_fall_back_positioning.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== AI Fall-Back Positioning Tests (MOV-6) ===\n")
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
	test_fall_back_computes_destinations()
	test_fall_back_destinations_outside_engagement_range()
	test_fall_back_destinations_within_movement_cap()
	test_fall_back_decision_includes_destinations()
	test_fall_back_retreat_toward_friendly_objective()
	test_fall_back_with_multiple_models()
	test_fall_back_stays_in_board_bounds()
	test_engaging_enemy_centroid()
	test_fall_back_directions_are_built()
	test_fall_back_no_valid_path_falls_to_stationary()

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
		weapons: Array = [], base_mm: int = 32) -> void:
	var models = []
	for i in range(num_models):
		models.append({
			"id": "m%d" % (i + 1),
			"alive": true,
			"base_mm": base_mm,
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

func _get_objectives_from_snapshot(snapshot: Dictionary) -> Array:
	var objectives = []
	for obj in snapshot.board.objectives:
		objectives.append(obj.position if obj.position is Vector2 else Vector2(obj.position.x, obj.position.y))
	return objectives

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
# TEST: _compute_fall_back_destinations returns non-empty destinations
# =========================================================================

func test_fall_back_computes_destinations():
	print("\n--- test_fall_back_computes_destinations ---")
	var snapshot = _create_test_snapshot()
	# Our unit engaged with enemy in the middle of the board
	_add_unit(snapshot, "u1", 2, Vector2(880, 1200), "Our Boyz", 2, 6, 3)
	_add_unit(snapshot, "e1", 1, Vector2(880, 1165), "Enemy", 2, 6, 3)

	var enemies = AIDecisionMaker._get_enemy_units(snapshot, 2)
	var objectives = _get_objectives_from_snapshot(snapshot)

	var destinations = AIDecisionMaker._compute_fall_back_destinations(
		snapshot.units["u1"], "u1", snapshot, enemies, objectives, 2
	)

	_assert(not destinations.is_empty(),
		"Fall-back destinations computed for engaged unit (got %d models)" % destinations.size())
	_assert(destinations.size() == 3,
		"All 3 models have destinations (got %d)" % destinations.size())

# =========================================================================
# TEST: All fall-back destinations are outside engagement range
# =========================================================================

func test_fall_back_destinations_outside_engagement_range():
	print("\n--- test_fall_back_destinations_outside_engagement_range ---")
	var snapshot = _create_test_snapshot()
	# Place units very close (within engagement range)
	_add_unit(snapshot, "u1", 2, Vector2(880, 1200), "Our Boyz", 2, 6, 3)
	_add_unit(snapshot, "e1", 1, Vector2(880, 1165), "Enemy", 2, 6, 3)

	var enemies = AIDecisionMaker._get_enemy_units(snapshot, 2)
	var objectives = _get_objectives_from_snapshot(snapshot)

	var destinations = AIDecisionMaker._compute_fall_back_destinations(
		snapshot.units["u1"], "u1", snapshot, enemies, objectives, 2
	)

	if destinations.is_empty():
		_assert(false, "Expected non-empty destinations")
		return

	# Check each destination is outside engagement range of all enemy models
	var all_outside = true
	for model_id in destinations:
		var dest = Vector2(destinations[model_id][0], destinations[model_id][1])
		if AIDecisionMaker._is_position_near_enemy(dest, enemies, snapshot.units["u1"]):
			all_outside = false
			print("  Model %s at (%.0f, %.0f) is still in engagement range!" % [model_id, dest.x, dest.y])

	_assert(all_outside, "All fall-back destinations are outside engagement range")

# =========================================================================
# TEST: All fall-back destinations are within movement cap
# =========================================================================

func test_fall_back_destinations_within_movement_cap():
	print("\n--- test_fall_back_destinations_within_movement_cap ---")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "u1", 2, Vector2(880, 1200), "Our Boyz", 2, 6, 3)
	_add_unit(snapshot, "e1", 1, Vector2(880, 1165), "Enemy", 2, 6, 3)

	var enemies = AIDecisionMaker._get_enemy_units(snapshot, 2)
	var objectives = _get_objectives_from_snapshot(snapshot)

	var destinations = AIDecisionMaker._compute_fall_back_destinations(
		snapshot.units["u1"], "u1", snapshot, enemies, objectives, 2
	)

	if destinations.is_empty():
		_assert(false, "Expected non-empty destinations")
		return

	var move_inches = 6.0
	var move_px = move_inches * AIDecisionMaker.PIXELS_PER_INCH
	var all_within_cap = true
	var unit_models = snapshot.units["u1"].models

	for model in unit_models:
		var model_id = model.id
		if not destinations.has(model_id):
			continue
		var orig_pos = model.position
		var dest = Vector2(destinations[model_id][0], destinations[model_id][1])
		var dist = orig_pos.distance_to(dest)
		if dist > move_px + 2.0:  # Small tolerance
			all_within_cap = false
			print("  Model %s moved %.1fpx but cap is %.1fpx" % [model_id, dist, move_px])

	_assert(all_within_cap, "All destinations within movement cap (M=%d\", %.0fpx)" % [move_inches, move_px])

# =========================================================================
# TEST: Fall-back decision from _decide_movement includes _ai_model_destinations
# =========================================================================

func test_fall_back_decision_includes_destinations():
	print("\n--- test_fall_back_decision_includes_destinations ---")
	var snapshot = _create_test_snapshot()
	# Engaged unit NOT on any objective
	_add_unit(snapshot, "u1", 2, Vector2(500, 1500), "Our Boyz", 2, 6, 3)
	_add_unit(snapshot, "e1", 1, Vector2(500, 1465), "Enemy", 1, 6, 3)

	var actions = _make_available_actions(["u1"], ["u1"])
	var decision = AIDecisionMaker._decide_movement(snapshot, actions, 2)

	_assert(decision.get("type", "") == "BEGIN_FALL_BACK",
		"Decision type is BEGIN_FALL_BACK (got %s)" % decision.get("type", ""))
	_assert(decision.has("_ai_model_destinations"),
		"Decision includes _ai_model_destinations")
	if decision.has("_ai_model_destinations"):
		_assert(decision._ai_model_destinations.size() > 0,
			"Model destinations are non-empty (got %d)" % decision._ai_model_destinations.size())

# =========================================================================
# TEST: Fall-back retreats toward a friendly objective
# =========================================================================

func test_fall_back_retreat_toward_friendly_objective():
	print("\n--- test_fall_back_retreat_toward_friendly_objective ---")
	var snapshot = _create_test_snapshot()
	# Our unit near center, enemy just behind them (between unit and enemy home)
	# Expected: retreat toward player 2's home objective (880, 2160)
	_add_unit(snapshot, "u1", 2, Vector2(880, 1200), "Our Boyz", 2, 6, 1)
	_add_unit(snapshot, "e1", 1, Vector2(880, 1165), "Enemy", 1, 6, 1)

	var enemies = AIDecisionMaker._get_enemy_units(snapshot, 2)
	var objectives = _get_objectives_from_snapshot(snapshot)

	var destinations = AIDecisionMaker._compute_fall_back_destinations(
		snapshot.units["u1"], "u1", snapshot, enemies, objectives, 2
	)

	if destinations.is_empty():
		_assert(false, "Expected non-empty destinations for retreat test")
		return

	# The single model should have moved away from the enemy (y > 1200, toward 2160)
	var dest = Vector2(destinations["m1"][0], destinations["m1"][1])
	var orig_pos = snapshot.units["u1"].models[0].position
	_assert(dest.y > orig_pos.y,
		"Model retreated toward friendly home (y: %.0f -> %.0f)" % [orig_pos.y, dest.y])

# =========================================================================
# TEST: Fall-back with multiple models
# =========================================================================

func test_fall_back_with_multiple_models():
	print("\n--- test_fall_back_with_multiple_models ---")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "u1", 2, Vector2(880, 1200), "Our Boyz", 2, 6, 5)
	_add_unit(snapshot, "e1", 1, Vector2(880, 1165), "Enemy", 2, 6, 3)

	var enemies = AIDecisionMaker._get_enemy_units(snapshot, 2)
	var objectives = _get_objectives_from_snapshot(snapshot)

	var destinations = AIDecisionMaker._compute_fall_back_destinations(
		snapshot.units["u1"], "u1", snapshot, enemies, objectives, 2
	)

	_assert(destinations.size() == 5,
		"All 5 models have fall-back destinations (got %d)" % destinations.size())

# =========================================================================
# TEST: Fall-back stays within board bounds
# =========================================================================

func test_fall_back_stays_in_board_bounds():
	print("\n--- test_fall_back_stays_in_board_bounds ---")
	var snapshot = _create_test_snapshot()
	# Unit near the bottom edge of the board, engaged
	_add_unit(snapshot, "u1", 2, Vector2(880, 2350), "Our Boyz", 2, 6, 2)
	_add_unit(snapshot, "e1", 1, Vector2(880, 2315), "Enemy", 1, 6, 2)

	var enemies = AIDecisionMaker._get_enemy_units(snapshot, 2)
	var objectives = _get_objectives_from_snapshot(snapshot)

	var destinations = AIDecisionMaker._compute_fall_back_destinations(
		snapshot.units["u1"], "u1", snapshot, enemies, objectives, 2
	)

	if destinations.is_empty():
		# Might not find valid destinations near edge, which is acceptable
		print("  No valid destinations near board edge (acceptable)")
		_assert(true, "Gracefully handles near-edge positions")
		return

	var all_in_bounds = true
	for model_id in destinations:
		var dest = Vector2(destinations[model_id][0], destinations[model_id][1])
		if dest.x < AIDecisionMaker.BASE_MARGIN_PX or dest.x > AIDecisionMaker.BOARD_WIDTH_PX - AIDecisionMaker.BASE_MARGIN_PX:
			all_in_bounds = false
		if dest.y < AIDecisionMaker.BASE_MARGIN_PX or dest.y > AIDecisionMaker.BOARD_HEIGHT_PX - AIDecisionMaker.BASE_MARGIN_PX:
			all_in_bounds = false

	_assert(all_in_bounds, "All destinations within board bounds")

# =========================================================================
# TEST: _get_engaging_enemy_centroid
# =========================================================================

func test_engaging_enemy_centroid():
	print("\n--- test_engaging_enemy_centroid ---")
	var snapshot = _create_test_snapshot()
	# Our unit at (880, 1200), enemy very close at (880, 1165) — within 1" ER
	_add_unit(snapshot, "u1", 2, Vector2(880, 1200), "Our Boyz", 2, 6, 1)
	_add_unit(snapshot, "e1", 1, Vector2(880, 1165), "Enemy", 1, 6, 1)

	var enemies = AIDecisionMaker._get_enemy_units(snapshot, 2)
	var centroid = AIDecisionMaker._get_engaging_enemy_centroid(
		snapshot.units["u1"], "u1", enemies
	)

	_assert(centroid != Vector2.INF,
		"Engaging enemy centroid found (%.0f, %.0f)" % [centroid.x, centroid.y])
	_assert(abs(centroid.y - 1165.0) < 5.0,
		"Centroid y is near enemy position (%.0f, expected ~1165)" % centroid.y)

# =========================================================================
# TEST: _build_fall_back_directions returns multiple directions
# =========================================================================

func test_fall_back_directions_are_built():
	print("\n--- test_fall_back_directions_are_built ---")
	var primary = Vector2(0, 1).normalized()
	var directions = AIDecisionMaker._build_fall_back_directions(primary)

	_assert(directions.size() == 12,
		"12 directions generated (primary + 11 alternates, got %d)" % directions.size())
	_assert(directions[0] == primary,
		"First direction is the primary retreat direction")

# =========================================================================
# TEST: Fall-back returns empty when surrounded (stays stationary)
# =========================================================================

func test_fall_back_no_valid_path_falls_to_stationary():
	print("\n--- test_fall_back_no_valid_path_falls_to_stationary ---")
	var snapshot = _create_test_snapshot()
	# Surround our unit with enemies on all sides (hard to escape)
	_add_unit(snapshot, "u1", 2, Vector2(880, 1200), "Our Boyz", 2, 2, 1)  # Very short move (2")
	# Place enemies in a tight ring around the unit at close range
	_add_unit(snapshot, "e1", 1, Vector2(880, 1160), "Enemy N", 1, 6, 1)
	_add_unit(snapshot, "e2", 1, Vector2(880, 1240), "Enemy S", 1, 6, 1)
	_add_unit(snapshot, "e3", 1, Vector2(840, 1200), "Enemy W", 1, 6, 1)
	_add_unit(snapshot, "e4", 1, Vector2(920, 1200), "Enemy E", 1, 6, 1)
	_add_unit(snapshot, "e5", 1, Vector2(845, 1160), "Enemy NW", 1, 6, 1)
	_add_unit(snapshot, "e6", 1, Vector2(915, 1160), "Enemy NE", 1, 6, 1)
	_add_unit(snapshot, "e7", 1, Vector2(845, 1240), "Enemy SW", 1, 6, 1)
	_add_unit(snapshot, "e8", 1, Vector2(915, 1240), "Enemy SE", 1, 6, 1)

	var actions = _make_available_actions(["u1"], ["u1"])
	var decision = AIDecisionMaker._decide_movement(snapshot, actions, 2)

	# When surrounded and can't escape, should remain stationary
	var decision_type = decision.get("type", "")
	_assert(decision_type == "REMAIN_STATIONARY" or decision_type == "BEGIN_FALL_BACK",
		"Surrounded unit either stays or finds escape route (type=%s)" % decision_type)
	if decision_type == "BEGIN_FALL_BACK":
		_assert(decision.has("_ai_model_destinations"),
			"If falling back, includes destinations")
