extends SceneTree

# Test AI Pile-In Movement — Tests the AI pile-in computation logic
# Run with: godot --headless --script tests/unit/test_ai_pile_in.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== AI Pile-In Movement Tests ===\n")
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

func _assert_approx(a: float, b: float, tolerance: float, message: String) -> void:
	if abs(a - b) <= tolerance:
		_pass_count += 1
		print("PASS: %s (%.2f ~= %.2f)" % [message, a, b])
	else:
		_fail_count += 1
		print("FAIL: %s (%.2f != %.2f, tolerance=%.2f)" % [message, a, b, tolerance])

func _run_tests():
	test_pile_in_moves_toward_enemy()
	test_pile_in_base_contact_holds_position()
	test_pile_in_respects_3_inch_limit()
	test_pile_in_empty_when_no_enemies()
	test_pile_in_action_returned_from_decide_fight()
	test_pile_in_skips_dead_models()
	test_pile_in_multiple_models()
	test_pile_in_model_index_mapping()
	test_find_model_index_in_unit()
	test_pile_in_far_model_clamps_to_3_inches()

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
		num_models: int = 1, keywords: Array = ["INFANTRY"],
		weapons: Array = [], toughness: int = 4, save_val: int = 3,
		wounds: int = 1, base_mm: int = 32, model_spacing: float = 40.0) -> void:
	var models = []
	for i in range(num_models):
		models.append({
			"id": "m%d" % (i + 1),
			"alive": true,
			"base_mm": base_mm,
			"base_type": "circular",
			"base_dimensions": {},
			"position": Vector2(pos.x + i * model_spacing, pos.y),
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

# =========================================================================
# Tests: Pile-in movement computation
# =========================================================================

func test_pile_in_moves_toward_enemy():
	print("\n--- test_pile_in_moves_toward_enemy ---")
	var snapshot = _create_test_snapshot()
	# Place our unit 2" away from enemy (within 3" pile-in range)
	# 2" = 80px at 40px/inch
	_add_unit(snapshot, "friendly_1", 2, Vector2(500, 500), "Assault Marines", 2, 6, 1,
		["INFANTRY"], [_make_melee_weapon()])
	_add_unit(snapshot, "enemy_1", 1, Vector2(580, 500), "Enemy Unit", 2, 6, 1)

	var movements = AIDecisionMaker._compute_pile_in_movements(snapshot, "friendly_1",
		snapshot.units["friendly_1"], 2)

	# Model should move toward the enemy
	_assert(movements.size() > 0, "Pile-in should produce movements when enemy is nearby")

	if movements.has("0"):
		var new_pos = movements["0"]
		var old_pos = Vector2(500, 500)
		var enemy_pos = Vector2(580, 500)
		# New position should be closer to enemy than old position
		_assert(new_pos.distance_to(enemy_pos) < old_pos.distance_to(enemy_pos),
			"Model should end closer to enemy after pile-in")
		# Movement should be along the X axis (enemy is directly right)
		_assert_approx(new_pos.y, 500.0, 1.0,
			"Model should not drift vertically when enemy is directly horizontal")
	else:
		_assert(false, "Expected movement for model index 0")


func test_pile_in_base_contact_holds_position():
	print("\n--- test_pile_in_base_contact_holds_position ---")
	var snapshot = _create_test_snapshot()
	# Place models with bases practically touching
	# 32mm base = ~25.2px diameter, so radius ~12.6px
	# Two 32mm bases in contact: center distance ~25.2px
	# Edge-to-edge = 0
	# Place centers 26px apart for near-base-contact (within 0.25" = 10px tolerance)
	_add_unit(snapshot, "friendly_1", 2, Vector2(500, 500), "Assault Marines", 2, 6, 1,
		["INFANTRY"], [_make_melee_weapon()])
	_add_unit(snapshot, "enemy_1", 1, Vector2(526, 500), "Enemy Unit", 2, 6, 1)

	var movements = AIDecisionMaker._compute_pile_in_movements(snapshot, "friendly_1",
		snapshot.units["friendly_1"], 2)

	# Model is already in base contact — should hold position (empty movements)
	_assert(movements.is_empty(),
		"Model already in base contact should not move (movements should be empty)")


func test_pile_in_respects_3_inch_limit():
	print("\n--- test_pile_in_respects_3_inch_limit ---")
	var snapshot = _create_test_snapshot()
	# Place unit 5" away from enemy (beyond 3" pile-in range)
	# 5" = 200px
	_add_unit(snapshot, "friendly_1", 2, Vector2(300, 500), "Assault Marines", 2, 6, 1,
		["INFANTRY"], [_make_melee_weapon()])
	_add_unit(snapshot, "enemy_1", 1, Vector2(500, 500), "Enemy Unit", 2, 6, 1)

	var movements = AIDecisionMaker._compute_pile_in_movements(snapshot, "friendly_1",
		snapshot.units["friendly_1"], 2)

	if movements.has("0"):
		var new_pos = movements["0"]
		var old_pos = Vector2(300, 500)
		var move_dist_px = old_pos.distance_to(new_pos)
		var move_dist_inches = move_dist_px / 40.0
		_assert(move_dist_inches <= 3.05,
			"Pile-in movement should not exceed 3\" (moved %.2f\")" % move_dist_inches)
		# Should move exactly 3" (120px) toward enemy
		_assert_approx(move_dist_inches, 3.0, 0.1,
			"Pile-in should move the maximum 3\" when enemy is far away")
	else:
		_assert(movements.size() > 0, "Should produce a movement for the model")


func test_pile_in_empty_when_no_enemies():
	print("\n--- test_pile_in_empty_when_no_enemies ---")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "friendly_1", 2, Vector2(500, 500), "Assault Marines", 2, 6, 1,
		["INFANTRY"], [_make_melee_weapon()])
	# No enemy units

	var movements = AIDecisionMaker._compute_pile_in_movements(snapshot, "friendly_1",
		snapshot.units["friendly_1"], 2)

	_assert(movements.is_empty(),
		"Pile-in should produce no movements when there are no enemies")


func test_pile_in_action_returned_from_decide_fight():
	print("\n--- test_pile_in_action_returned_from_decide_fight ---")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "friendly_1", 2, Vector2(500, 500), "Assault Marines", 2, 6, 1,
		["INFANTRY"], [_make_melee_weapon()])
	_add_unit(snapshot, "enemy_1", 1, Vector2(600, 500), "Enemy Unit", 2, 6, 1)

	var available = [
		{"type": "PILE_IN", "unit_id": "friendly_1"},
		{"type": "ASSIGN_ATTACKS_UI", "unit_id": "friendly_1"},
	]

	var decision = AIDecisionMaker._decide_fight(snapshot, available, 2)

	_assert(decision.get("type") == "PILE_IN",
		"Decision should be PILE_IN when available")
	_assert(decision.get("unit_id") == "friendly_1",
		"PILE_IN action should reference the correct unit")
	_assert(decision.has("movements"),
		"PILE_IN action should contain movements dictionary")
	_assert(decision.get("movements") is Dictionary,
		"movements should be a Dictionary")

	# With an enemy 2.5" away, we should have actual movements (not empty)
	var movements = decision.get("movements", {})
	_assert(movements.size() > 0,
		"PILE_IN should compute movements toward nearby enemy (not hold position)")


func test_pile_in_skips_dead_models():
	print("\n--- test_pile_in_skips_dead_models ---")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "friendly_1", 2, Vector2(500, 500), "Assault Marines", 2, 6, 3,
		["INFANTRY"], [_make_melee_weapon()])
	# Kill the second model
	snapshot.units["friendly_1"]["models"][1]["alive"] = false

	_add_unit(snapshot, "enemy_1", 1, Vector2(600, 500), "Enemy Unit", 2, 6, 1)

	var movements = AIDecisionMaker._compute_pile_in_movements(snapshot, "friendly_1",
		snapshot.units["friendly_1"], 2)

	# Dead model (index 1) should not have a movement
	_assert(not movements.has("1"),
		"Dead model should not have a pile-in movement")


func test_pile_in_multiple_models():
	print("\n--- test_pile_in_multiple_models ---")
	var snapshot = _create_test_snapshot()
	# 3 models spread out, with enemy 2" to the right of the first model
	_add_unit(snapshot, "friendly_1", 2, Vector2(500, 500), "Assault Marines", 2, 6, 3,
		["INFANTRY"], [_make_melee_weapon()], 4, 3, 1, 32, 40.0)
	_add_unit(snapshot, "enemy_1", 1, Vector2(600, 500), "Enemy Unit", 2, 6, 1)

	var movements = AIDecisionMaker._compute_pile_in_movements(snapshot, "friendly_1",
		snapshot.units["friendly_1"], 2)

	# At least some models should move (those not in base contact)
	_assert(movements.size() >= 1,
		"Multiple models should produce at least some pile-in movements")

	# All movements should bring models closer to the enemy
	var enemy_pos = Vector2(600, 500)
	for model_idx_str in movements:
		var new_pos = movements[model_idx_str]
		var model_idx = int(model_idx_str)
		var old_pos = Vector2(500 + model_idx * 40.0, 500)
		_assert(new_pos.distance_to(enemy_pos) < old_pos.distance_to(enemy_pos),
			"Model %s should end closer to enemy after pile-in" % model_idx_str)


func test_pile_in_model_index_mapping():
	print("\n--- test_pile_in_model_index_mapping ---")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "friendly_1", 2, Vector2(500, 500), "Assault Marines", 2, 6, 2,
		["INFANTRY"], [_make_melee_weapon()])
	_add_unit(snapshot, "enemy_1", 1, Vector2(620, 500), "Enemy Unit", 2, 6, 1)

	var movements = AIDecisionMaker._compute_pile_in_movements(snapshot, "friendly_1",
		snapshot.units["friendly_1"], 2)

	# Verify that model indices are string keys matching the models array indices
	for key in movements:
		_assert(key.is_valid_int(), "Movement key '%s' should be a valid integer string" % key)
		var idx = int(key)
		_assert(idx >= 0 and idx < 2,
			"Movement key '%s' should be within model array bounds [0, 1]" % key)


func test_find_model_index_in_unit():
	print("\n--- test_find_model_index_in_unit ---")
	var unit = {
		"models": [
			{"id": "m1", "alive": true},
			{"id": "m2", "alive": true},
			{"id": "m3", "alive": true},
		]
	}

	_assert(AIDecisionMaker._find_model_index_in_unit(unit, "m1") == 0,
		"Model m1 should be at index 0")
	_assert(AIDecisionMaker._find_model_index_in_unit(unit, "m2") == 1,
		"Model m2 should be at index 1")
	_assert(AIDecisionMaker._find_model_index_in_unit(unit, "m3") == 2,
		"Model m3 should be at index 2")
	_assert(AIDecisionMaker._find_model_index_in_unit(unit, "m99") == -1,
		"Non-existent model should return -1")

	# Test fallback with numeric string
	_assert(AIDecisionMaker._find_model_index_in_unit(unit, "0") == 0,
		"Numeric string '0' should match index 0 as fallback")
	_assert(AIDecisionMaker._find_model_index_in_unit(unit, "2") == 2,
		"Numeric string '2' should match index 2 as fallback")


func test_pile_in_far_model_clamps_to_3_inches():
	print("\n--- test_pile_in_far_model_clamps_to_3_inches ---")
	var snapshot = _create_test_snapshot()
	# Place model 10" away from enemy — well beyond 3" pile-in
	# 10" = 400px
	_add_unit(snapshot, "friendly_1", 2, Vector2(200, 500), "Assault Marines", 2, 6, 1,
		["INFANTRY"], [_make_melee_weapon()])
	_add_unit(snapshot, "enemy_1", 1, Vector2(600, 500), "Enemy Unit", 2, 6, 1)

	var movements = AIDecisionMaker._compute_pile_in_movements(snapshot, "friendly_1",
		snapshot.units["friendly_1"], 2)

	if movements.has("0"):
		var new_pos = movements["0"]
		var old_pos = Vector2(200, 500)
		var move_dist_px = old_pos.distance_to(new_pos)
		var move_dist_inches = move_dist_px / 40.0
		# Should clamp to exactly 3"
		_assert(move_dist_inches <= 3.01,
			"Model 10\" away should pile in at most 3\" (moved %.2f\")" % move_dist_inches)
		_assert_approx(move_dist_inches, 3.0, 0.1,
			"Model should move the maximum 3\" toward far enemy")
		# Should move rightward (toward enemy at x=600)
		_assert(new_pos.x > old_pos.x,
			"Model should move toward enemy (rightward)")
	else:
		_assert(movements.has("0"), "Should produce movement for model when enemy is far away")
