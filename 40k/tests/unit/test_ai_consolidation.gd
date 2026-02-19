extends SceneTree

# Test AI Consolidation Movement — Tests the AI consolidation computation logic
# Run with: godot --headless --script tests/unit/test_ai_consolidation.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== AI Consolidation Movement Tests ===\n")
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
	test_consolidate_engagement_mode_moves_toward_enemy()
	test_consolidate_objective_mode_moves_toward_objective()
	test_consolidate_mode_detection_engagement()
	test_consolidate_mode_detection_objective()
	test_consolidate_mode_detection_none()
	test_consolidate_action_from_decide_fight()
	test_consolidate_respects_3_inch_limit()
	test_consolidate_aircraft_skipped()
	test_consolidate_base_contact_holds_position()
	test_consolidate_empty_when_no_targets()
	test_consolidate_multiple_models_toward_objective()
	test_consolidate_skips_dead_models()

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
# Tests: Consolidation mode detection
# =========================================================================

func test_consolidate_mode_detection_engagement():
	print("\n--- test_consolidate_mode_detection_engagement ---")
	var snapshot = _create_test_snapshot()
	# Place friendly unit 2" from enemy — well within 4" engagement-check range
	_add_unit(snapshot, "friendly_1", 2, Vector2(500, 500), "Assault Marines", 2, 6, 1,
		["INFANTRY"], [_make_melee_weapon()])
	_add_unit(snapshot, "enemy_1", 1, Vector2(580, 500), "Enemy Unit", 2, 6, 1)

	var unit = snapshot.units["friendly_1"]
	var mode = AIDecisionMaker._determine_ai_consolidate_mode(snapshot, unit, 2)
	_assert(mode == "ENGAGEMENT",
		"Mode should be ENGAGEMENT when enemy is within 4\" (2\" away)")


func test_consolidate_mode_detection_objective():
	print("\n--- test_consolidate_mode_detection_objective ---")
	var snapshot = _create_test_snapshot()
	# Place friendly unit 10" from enemy — beyond 4" engagement-check range
	# 10" = 400px
	_add_unit(snapshot, "friendly_1", 2, Vector2(200, 500), "Assault Marines", 2, 6, 1,
		["INFANTRY"], [_make_melee_weapon()])
	_add_unit(snapshot, "enemy_1", 1, Vector2(600, 500), "Enemy Unit", 2, 6, 1)

	var unit = snapshot.units["friendly_1"]
	var mode = AIDecisionMaker._determine_ai_consolidate_mode(snapshot, unit, 2)
	_assert(mode == "OBJECTIVE",
		"Mode should be OBJECTIVE when enemy is beyond 4\" but objectives exist")


func test_consolidate_mode_detection_none():
	print("\n--- test_consolidate_mode_detection_none ---")
	# No enemies, no objectives
	var snapshot = {
		"battle_round": 2,
		"board": {
			"objectives": [],
			"terrain_features": [],
			"deployment_zones": []
		},
		"units": {}
	}
	_add_unit(snapshot, "friendly_1", 2, Vector2(500, 500), "Assault Marines", 2, 6, 1,
		["INFANTRY"], [_make_melee_weapon()])

	var unit = snapshot.units["friendly_1"]
	var mode = AIDecisionMaker._determine_ai_consolidate_mode(snapshot, unit, 2)
	_assert(mode == "NONE",
		"Mode should be NONE when no enemies and no objectives")


# =========================================================================
# Tests: Consolidation movement (engagement mode)
# =========================================================================

func test_consolidate_engagement_mode_moves_toward_enemy():
	print("\n--- test_consolidate_engagement_mode_moves_toward_enemy ---")
	var snapshot = _create_test_snapshot()
	# Place our unit 2" away from enemy (within 4" engagement range)
	# 2" = 80px at 40px/inch
	_add_unit(snapshot, "friendly_1", 2, Vector2(500, 500), "Assault Marines", 2, 6, 1,
		["INFANTRY"], [_make_melee_weapon()])
	_add_unit(snapshot, "enemy_1", 1, Vector2(580, 500), "Enemy Unit", 2, 6, 1)

	var result = AIDecisionMaker._compute_consolidate_action(snapshot, "friendly_1", 2)

	_assert(result.get("type") == "CONSOLIDATE",
		"Action type should be CONSOLIDATE")
	_assert(result.has("movements"),
		"Result should have movements dictionary")

	var movements = result.get("movements", {})
	_assert(movements.size() > 0,
		"Should produce movements when enemy is within engagement reach")

	if movements.has("0"):
		var new_pos = movements["0"]
		var old_pos = Vector2(500, 500)
		var enemy_pos = Vector2(580, 500)
		_assert(new_pos.distance_to(enemy_pos) < old_pos.distance_to(enemy_pos),
			"Model should end closer to enemy after consolidation (engagement mode)")


func test_consolidate_base_contact_holds_position():
	print("\n--- test_consolidate_base_contact_holds_position ---")
	var snapshot = _create_test_snapshot()
	# Place models in base contact (same as pile-in test)
	# 32mm base = ~25.2px diameter, so radius ~12.6px
	# Two 32mm bases in contact: center distance ~25.2px
	_add_unit(snapshot, "friendly_1", 2, Vector2(500, 500), "Assault Marines", 2, 6, 1,
		["INFANTRY"], [_make_melee_weapon()])
	_add_unit(snapshot, "enemy_1", 1, Vector2(526, 500), "Enemy Unit", 2, 6, 1)

	var result = AIDecisionMaker._compute_consolidate_action(snapshot, "friendly_1", 2)
	var movements = result.get("movements", {})

	# Model is already in base contact — should hold position (empty movements)
	_assert(movements.is_empty(),
		"Model already in base contact should not move during consolidation")


# =========================================================================
# Tests: Consolidation movement (objective mode)
# =========================================================================

func test_consolidate_objective_mode_moves_toward_objective():
	print("\n--- test_consolidate_objective_mode_moves_toward_objective ---")
	var snapshot = _create_test_snapshot()
	# Place friendly unit far from enemies (beyond 4") but objective at (880, 1200)
	# 10" = 400px from enemy
	_add_unit(snapshot, "friendly_1", 2, Vector2(200, 500), "Assault Marines", 2, 6, 1,
		["INFANTRY"], [_make_melee_weapon()])
	_add_unit(snapshot, "enemy_1", 1, Vector2(600, 500), "Enemy Unit", 2, 6, 1)

	var result = AIDecisionMaker._compute_consolidate_action(snapshot, "friendly_1", 2)

	_assert(result.get("type") == "CONSOLIDATE",
		"Action type should be CONSOLIDATE")

	var movements = result.get("movements", {})
	_assert(movements.size() > 0,
		"Should produce movements toward objective when enemy is out of reach")

	if movements.has("0"):
		var new_pos = movements["0"]
		var old_pos = Vector2(200, 500)
		var obj_pos = Vector2(880, 1200)  # objective position from snapshot
		_assert(new_pos.distance_to(obj_pos) < old_pos.distance_to(obj_pos),
			"Model should end closer to objective after consolidation (objective mode)")

		# Verify movement distance is within 3"
		var move_dist_inches = old_pos.distance_to(new_pos) / 40.0
		_assert(move_dist_inches <= 3.05,
			"Consolidation movement should not exceed 3\" (moved %.2f\")" % move_dist_inches)


func test_consolidate_multiple_models_toward_objective():
	print("\n--- test_consolidate_multiple_models_toward_objective ---")
	var snapshot = _create_test_snapshot()
	# Place 3 models far from enemies, should all move toward objective
	_add_unit(snapshot, "friendly_1", 2, Vector2(200, 500), "Assault Marines", 2, 6, 3,
		["INFANTRY"], [_make_melee_weapon()], 4, 3, 1, 32, 40.0)
	_add_unit(snapshot, "enemy_1", 1, Vector2(800, 500), "Enemy Unit", 2, 6, 1)

	var result = AIDecisionMaker._compute_consolidate_action(snapshot, "friendly_1", 2)
	var movements = result.get("movements", {})

	_assert(movements.size() >= 1,
		"Multiple models should produce at least some consolidation movements toward objective")

	# All movements should bring models closer to the objective
	var obj_pos = Vector2(880, 1200)
	for model_idx_str in movements:
		var new_pos = movements[model_idx_str]
		var model_idx = int(model_idx_str)
		var old_pos = Vector2(200 + model_idx * 40.0, 500)
		_assert(new_pos.distance_to(obj_pos) < old_pos.distance_to(obj_pos),
			"Model %s should end closer to objective after consolidation" % model_idx_str)


# =========================================================================
# Tests: General consolidation rules
# =========================================================================

func test_consolidate_respects_3_inch_limit():
	print("\n--- test_consolidate_respects_3_inch_limit ---")
	var snapshot = _create_test_snapshot()
	# Place unit 5" from enemy — within 4" check but movement is clamped to 3"
	# 5" = 200px
	_add_unit(snapshot, "friendly_1", 2, Vector2(300, 500), "Assault Marines", 2, 6, 1,
		["INFANTRY"], [_make_melee_weapon()])
	_add_unit(snapshot, "enemy_1", 1, Vector2(500, 500), "Enemy Unit", 2, 6, 1)

	var result = AIDecisionMaker._compute_consolidate_action(snapshot, "friendly_1", 2)
	var movements = result.get("movements", {})

	if movements.has("0"):
		var new_pos = movements["0"]
		var old_pos = Vector2(300, 500)
		var move_dist_inches = old_pos.distance_to(new_pos) / 40.0
		_assert(move_dist_inches <= 3.05,
			"Consolidation should not exceed 3\" (moved %.2f\")" % move_dist_inches)
		_assert_approx(move_dist_inches, 3.0, 0.1,
			"Should move close to the maximum 3\" when enemy is beyond 3\"")
	else:
		_assert(movements.size() > 0, "Should produce a movement for the model")


func test_consolidate_aircraft_skipped():
	print("\n--- test_consolidate_aircraft_skipped ---")
	var snapshot = _create_test_snapshot()
	# Aircraft units cannot consolidate
	_add_unit(snapshot, "friendly_1", 2, Vector2(500, 500), "Stormraven", 2, 20, 1,
		["VEHICLE", "AIRCRAFT", "FLY"], [_make_melee_weapon()])
	_add_unit(snapshot, "enemy_1", 1, Vector2(580, 500), "Enemy Unit", 2, 6, 1)

	var result = AIDecisionMaker._compute_consolidate_action(snapshot, "friendly_1", 2)
	var movements = result.get("movements", {})

	_assert(movements.is_empty(),
		"AIRCRAFT units should not consolidate (empty movements)")
	_assert("AIRCRAFT" in result.get("_ai_description", ""),
		"Description should mention AIRCRAFT skip")


func test_consolidate_empty_when_no_targets():
	print("\n--- test_consolidate_empty_when_no_targets ---")
	# No enemies and no objectives
	var snapshot = {
		"battle_round": 2,
		"board": {
			"objectives": [],
			"terrain_features": [],
			"deployment_zones": []
		},
		"units": {}
	}
	_add_unit(snapshot, "friendly_1", 2, Vector2(500, 500), "Assault Marines", 2, 6, 1,
		["INFANTRY"], [_make_melee_weapon()])

	var result = AIDecisionMaker._compute_consolidate_action(snapshot, "friendly_1", 2)
	var movements = result.get("movements", {})

	_assert(movements.is_empty(),
		"Consolidation should produce no movements when there are no enemies and no objectives")


func test_consolidate_action_from_decide_fight():
	print("\n--- test_consolidate_action_from_decide_fight ---")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "friendly_1", 2, Vector2(500, 500), "Assault Marines", 2, 6, 1,
		["INFANTRY"], [_make_melee_weapon()])
	_add_unit(snapshot, "enemy_1", 1, Vector2(600, 500), "Enemy Unit", 2, 6, 1)

	var available = [
		{"type": "CONSOLIDATE", "unit_id": "friendly_1"},
	]

	var decision = AIDecisionMaker._decide_fight(snapshot, available, 2)

	_assert(decision.get("type") == "CONSOLIDATE",
		"Decision should be CONSOLIDATE when available")
	_assert(decision.get("unit_id") == "friendly_1",
		"CONSOLIDATE action should reference the correct unit")
	_assert(decision.has("movements"),
		"CONSOLIDATE action should contain movements dictionary")
	_assert(decision.get("movements") is Dictionary,
		"movements should be a Dictionary")

	# Enemy is 2.5" away (within 4" engagement reach), so should have movements
	var movements = decision.get("movements", {})
	_assert(movements.size() > 0,
		"CONSOLIDATE should compute movements toward nearby enemy (not hold position)")


func test_consolidate_skips_dead_models():
	print("\n--- test_consolidate_skips_dead_models ---")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "friendly_1", 2, Vector2(500, 500), "Assault Marines", 2, 6, 3,
		["INFANTRY"], [_make_melee_weapon()])
	# Kill the second model
	snapshot.units["friendly_1"]["models"][1]["alive"] = false

	_add_unit(snapshot, "enemy_1", 1, Vector2(600, 500), "Enemy Unit", 2, 6, 1)

	var result = AIDecisionMaker._compute_consolidate_action(snapshot, "friendly_1", 2)
	var movements = result.get("movements", {})

	# Dead model (index 1) should not have a movement
	_assert(not movements.has("1"),
		"Dead model should not have a consolidation movement")
