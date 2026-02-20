extends SceneTree

# Test script for T7-18: AI terrain-aware deployment
# Run: godot --headless --script tests/unit/test_ai_terrain_deployment.gd

var pass_count: int = 0
var fail_count: int = 0

func _assert(condition: bool, test_name: String) -> void:
	if condition:
		print("PASS: %s" % test_name)
		pass_count += 1
	else:
		print("FAIL: %s" % test_name)
		fail_count += 1

func _init():
	print("=== T7-18: AI Terrain-Aware Deployment Tests ===")

	# -------------------------------------------------------
	# Test 1: _classify_deployment_role — CHARACTER
	# -------------------------------------------------------
	var character_unit = {
		"meta": {
			"keywords": ["INFANTRY", "CHARACTER"],
			"stats": {"toughness": 4, "save": 3, "wounds": 5},
			"weapons": [{"type": "ranged", "range": "24", "attacks": "4", "damage": "2"}]
		}
	}
	var role = AIDecisionMaker._classify_deployment_role(character_unit)
	_assert(role == "character", "CHARACTER unit classified as 'character' (got '%s')" % role)

	# -------------------------------------------------------
	# Test 2: _classify_deployment_role — pure melee
	# -------------------------------------------------------
	var melee_unit = {
		"meta": {
			"keywords": ["INFANTRY"],
			"stats": {"toughness": 5, "save": 3, "wounds": 2},
			"weapons": [{"type": "melee", "attacks": "4", "damage": "2"}]
		}
	}
	role = AIDecisionMaker._classify_deployment_role(melee_unit)
	_assert(role == "melee", "Pure melee unit classified as 'melee' (got '%s')" % role)

	# -------------------------------------------------------
	# Test 3: _classify_deployment_role — fragile shooter
	# -------------------------------------------------------
	var fragile_shooter = {
		"meta": {
			"keywords": ["INFANTRY"],
			"stats": {"toughness": 3, "save": 5, "wounds": 1},
			"weapons": [{"type": "ranged", "range": "24", "attacks": "1", "damage": "1"}]
		}
	}
	role = AIDecisionMaker._classify_deployment_role(fragile_shooter)
	_assert(role == "fragile_shooter", "T3/5+/1W ranged unit classified as 'fragile_shooter' (got '%s')" % role)

	# -------------------------------------------------------
	# Test 4: _classify_deployment_role — durable shooter
	# -------------------------------------------------------
	var durable_shooter = {
		"meta": {
			"keywords": ["VEHICLE"],
			"stats": {"toughness": 10, "save": 2, "wounds": 12},
			"weapons": [{"type": "ranged", "range": "48", "attacks": "2", "damage": "6"}]
		}
	}
	role = AIDecisionMaker._classify_deployment_role(durable_shooter)
	_assert(role == "durable_shooter", "T10/2+/12W vehicle classified as 'durable_shooter' (got '%s')" % role)

	# -------------------------------------------------------
	# Test 5: _classify_deployment_role — no weapons = general
	# -------------------------------------------------------
	var no_weapons_unit = {
		"meta": {
			"keywords": ["INFANTRY"],
			"stats": {"toughness": 4, "save": 4, "wounds": 1},
			"weapons": []
		}
	}
	role = AIDecisionMaker._classify_deployment_role(no_weapons_unit)
	_assert(role == "general", "Unit with no weapons classified as 'general' (got '%s')" % role)

	# -------------------------------------------------------
	# Test 6: _score_terrain_for_role — character prefers LoS blockers
	# -------------------------------------------------------
	var tall_ruins = {"type": "ruins", "height_category": "tall"}
	var zone_bounds = {"min_x": 40.0, "max_x": 1720.0, "min_y": 10.0, "max_y": 470.0}
	var pos = Vector2(400, 200)

	var char_score = AIDecisionMaker._score_terrain_for_role(tall_ruins, "character", pos, zone_bounds, true)
	var melee_score = AIDecisionMaker._score_terrain_for_role(tall_ruins, "melee", pos, zone_bounds, true)
	_assert(char_score > 0.0, "Character gets positive score from tall ruins (got %.2f)" % char_score)
	_assert(char_score > melee_score, "Character values tall ruins more than melee (%.2f > %.2f)" % [char_score, melee_score])

	# -------------------------------------------------------
	# Test 7: _score_terrain_for_role — cover terrain scores
	# -------------------------------------------------------
	var woods = {"type": "woods", "height_category": "low"}
	var fragile_score = AIDecisionMaker._score_terrain_for_role(woods, "fragile_shooter", pos, zone_bounds, true)
	_assert(fragile_score > 0.0, "Fragile shooter gets positive score from woods (got %.2f)" % fragile_score)

	# -------------------------------------------------------
	# Test 8: _score_terrain_for_role — impassable terrain = 0
	# -------------------------------------------------------
	var impassable = {"type": "impassable", "height_category": "tall"}
	var impassable_score = AIDecisionMaker._score_terrain_for_role(impassable, "character", pos, zone_bounds, true)
	_assert(impassable_score == 0.0, "Impassable terrain scores 0.0 (got %.2f)" % impassable_score)

	# -------------------------------------------------------
	# Test 9: _find_terrain_aware_position — with terrain in zone
	# -------------------------------------------------------
	var baseline = Vector2(400, 300)
	var terrain_features = [
		{
			"type": "ruins",
			"height_category": "tall",
			"position": Vector2(500, 250),
			"size": Vector2(120, 120),
			"polygon": PackedVector2Array([Vector2(440,190), Vector2(560,190), Vector2(560,310), Vector2(440,310)]),
			"can_move_through": {"INFANTRY": true, "VEHICLE": false, "MONSTER": false}
		}
	]
	var objectives = [Vector2(880, 1200)]
	var snapshot = {"board": {"terrain_features": terrain_features}, "units": {}}

	var result_pos = AIDecisionMaker._find_terrain_aware_position(
		baseline, "character", terrain_features, zone_bounds, true, objectives, snapshot, 1
	)
	_assert(result_pos != baseline, "Character position adjusted toward terrain (baseline=%.0f,%.0f result=%.0f,%.0f)" % [baseline.x, baseline.y, result_pos.x, result_pos.y])
	# Should still be within zone bounds
	_assert(result_pos.x >= zone_bounds.min_x and result_pos.x <= zone_bounds.max_x,
		"Result X within zone bounds (%.0f in [%.0f, %.0f])" % [result_pos.x, zone_bounds.min_x, zone_bounds.max_x])
	_assert(result_pos.y >= zone_bounds.min_y and result_pos.y <= zone_bounds.max_y,
		"Result Y within zone bounds (%.0f in [%.0f, %.0f])" % [result_pos.y, zone_bounds.min_y, zone_bounds.max_y])

	# -------------------------------------------------------
	# Test 10: _find_terrain_aware_position — no terrain = baseline
	# -------------------------------------------------------
	var no_terrain_pos = AIDecisionMaker._find_terrain_aware_position(
		baseline, "character", [], zone_bounds, true, objectives, snapshot, 1
	)
	_assert(no_terrain_pos == baseline, "No terrain returns baseline position")

	# -------------------------------------------------------
	# Test 11: _find_terrain_aware_position — terrain outside zone is ignored
	# -------------------------------------------------------
	var far_terrain = [
		{
			"type": "ruins",
			"height_category": "tall",
			"position": Vector2(880, 1200),  # Far from player 1's zone
			"size": Vector2(120, 120),
			"polygon": PackedVector2Array([Vector2(820,1140), Vector2(940,1140), Vector2(940,1260), Vector2(820,1260)]),
			"can_move_through": {"INFANTRY": true, "VEHICLE": false, "MONSTER": false}
		}
	]
	var far_result = AIDecisionMaker._find_terrain_aware_position(
		baseline, "character", far_terrain, zone_bounds, true, objectives, snapshot, 1
	)
	_assert(far_result == baseline, "Terrain outside deployment zone is ignored (returns baseline)")

	# -------------------------------------------------------
	# Test 12: _classify_deployment_role — mixed weapons melee-leaning
	# -------------------------------------------------------
	var mixed_melee = {
		"meta": {
			"keywords": ["INFANTRY"],
			"stats": {"toughness": 5, "save": 3, "wounds": 2},
			"weapons": [
				{"type": "melee", "attacks": "4", "damage": "2"},
				{"type": "ranged", "range": "12", "attacks": "1", "damage": "1"}
			]
		}
	}
	role = AIDecisionMaker._classify_deployment_role(mixed_melee)
	# Has ranged weapons + T5/3+/2W = not fragile, so durable_shooter
	_assert(role == "durable_shooter", "Mixed weapons T5/3+ unit classified as 'durable_shooter' (got '%s')" % role)

	# -------------------------------------------------------
	# Test 13: _score_terrain_for_role — melee prefers front edge terrain
	# -------------------------------------------------------
	var front_pos = Vector2(400, 450)  # Near front edge (max_y=470 for top zone)
	var back_pos = Vector2(400, 50)    # Near back edge (min_y=10 for top zone)
	var melee_front_score = AIDecisionMaker._score_terrain_for_role(tall_ruins, "melee", front_pos, zone_bounds, true)
	var melee_back_score = AIDecisionMaker._score_terrain_for_role(tall_ruins, "melee", back_pos, zone_bounds, true)
	_assert(melee_front_score > melee_back_score, "Melee prefers front-edge terrain (front=%.2f > back=%.2f)" % [melee_front_score, melee_back_score])

	# -------------------------------------------------------
	# Test 14: Full deployment integration — _decide_deployment with terrain
	# -------------------------------------------------------
	var full_snapshot = {
		"board": {
			"terrain_features": terrain_features,
			"objectives": [{"position": {"x": 880, "y": 1200}}],
			"deployment_zones": [
				{"player": 1, "vertices": [
					{"x": 40, "y": 10}, {"x": 1720, "y": 10},
					{"x": 1720, "y": 470}, {"x": 40, "y": 470}
				]},
				{"player": 2, "vertices": [
					{"x": 40, "y": 1930}, {"x": 1720, "y": 1930},
					{"x": 1720, "y": 2390}, {"x": 40, "y": 2390}
				]}
			]
		},
		"units": {
			"unit_1": {
				"owner": 1,
				"status": 0,  # UNDEPLOYED
				"meta": {
					"name": "Test Guardsmen",
					"keywords": ["INFANTRY"],
					"stats": {"toughness": 3, "save": 5, "wounds": 1},
					"weapons": [{"type": "ranged", "range": "24", "attacks": "1", "damage": "1"}],
					"points": 60
				},
				"models": [
					{"id": "m1", "alive": true, "base_mm": 25},
					{"id": "m2", "alive": true, "base_mm": 25},
					{"id": "m3", "alive": true, "base_mm": 25},
					{"id": "m4", "alive": true, "base_mm": 25},
					{"id": "m5", "alive": true, "base_mm": 25}
				]
			}
		}
	}
	var actions = [{"type": "DEPLOY_UNIT", "unit_id": "unit_1"}]
	var result = AIDecisionMaker._decide_deployment(full_snapshot, actions, 1)
	_assert(result.get("type") == "DEPLOY_UNIT", "Full deployment returns DEPLOY_UNIT action")
	_assert(result.get("unit_id") == "unit_1", "Full deployment targets correct unit")
	_assert(result.get("model_positions", []).size() == 5, "Full deployment returns 5 model positions")
	var desc = result.get("_ai_description", "")
	_assert("fragile_shooter" in desc, "Description mentions terrain role (got '%s')" % desc)

	# -------------------------------------------------------
	print("\n=== Results: %d passed, %d failed ===" % [pass_count, fail_count])
	if fail_count > 0:
		print("SOME TESTS FAILED")
	else:
		print("ALL TESTS PASSED")
	quit()
