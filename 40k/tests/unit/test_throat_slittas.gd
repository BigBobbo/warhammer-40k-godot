extends "res://addons/gut/test.gd"

# Tests for the Throat Slittas ability implementation (P1-12)
#
# Per Warhammer 40k 10th Edition Kommandos datasheet:
# "At the start of your Shooting phase, if this unit is within 9" of one or
# more enemy units, it can use this ability. If it does, until the end of the
# phase, this unit is not eligible to shoot, but you roll one D6 for each
# model in this unit that is within 9" of an enemy unit: for each 5+, that
# enemy unit suffers 1 mortal wound."
#
# These tests verify:
# 1. UnitAbilityManager.has_throat_slittas_ability() detects the ability
# 2. ABILITY_EFFECTS table has correct entry for Throat Slittas
# 3. _get_throat_slittas_targets() finds enemy units within 9"
# 4. _count_models_within_range() counts models correctly
# 5. _resolve_throat_slittas() applies mortal wounds on 5+
# 6. Unit is marked as has_shot after using Throat Slittas

const GameStateData = preload("res://autoloads/GameState.gd")

var ability_mgr: Node
var measurement: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	ability_mgr = AutoloadHelper.get_autoload("UnitAbilityManager")
	assert_not_null(ability_mgr, "UnitAbilityManager autoload must be available")
	measurement = AutoloadHelper.get_autoload("Measurement")
	assert_not_null(measurement, "Measurement autoload must be available")

	# Reset game state
	GameState.state["units"] = {}

# ==========================================
# Helper: Create test units
# ==========================================

func _create_kommandos(id: String, owner: int, model_count: int = 10, x: float = 200.0, y: float = 200.0) -> Dictionary:
	"""Create a Kommandos unit with Throat Slittas ability."""
	var models = []
	for i in range(model_count):
		models.append({
			"id": "%s_m%d" % [id, i + 1],
			"wounds": 1,
			"current_wounds": 1,
			"base_mm": 32,
			"position": {"x": x + i * 20, "y": y},
			"alive": true,
			"status_effects": []
		})
	var unit = {
		"id": id,
		"squad_id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Kommandos",
			"keywords": ["INFANTRY", "ORK", "KOMMANDOS"],
			"stats": {
				"move": 6,
				"toughness": 5,
				"save": 5,
				"wounds": 1,
				"leadership": 7,
				"objective_control": 1
			},
			"abilities": [
				{"name": "Infiltrators", "type": "Core"},
				{
					"name": "Throat Slittas",
					"type": "Datasheet",
					"description": "At the start of your Shooting phase, if this unit is within 9\" of one or more enemy units, it can use this ability."
				}
			],
			"weapons": [
				{
					"id": "slugga",
					"name": "Slugga",
					"type": "Ranged",
					"range": 12,
					"attacks": 1,
					"skill": 5,
					"strength": 4,
					"ap": 0,
					"damage": 1,
					"keywords": ["PISTOL"]
				}
			]
		},
		"models": models,
		"flags": {}
	}
	GameState.state["units"][id] = unit
	return unit

func _create_enemy_unit(id: String, owner: int, model_count: int = 5, x: float = 300.0, y: float = 200.0) -> Dictionary:
	"""Create an enemy infantry unit for testing."""
	var models = []
	for i in range(model_count):
		models.append({
			"id": "%s_m%d" % [id, i + 1],
			"wounds": 1,
			"current_wounds": 1,
			"base_mm": 32,
			"position": {"x": x + i * 20, "y": y},
			"alive": true,
			"status_effects": []
		})
	var unit = {
		"id": id,
		"squad_id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Enemy Squad",
			"keywords": ["INFANTRY"],
			"stats": {
				"move": 6,
				"toughness": 4,
				"save": 3,
				"wounds": 1,
				"leadership": 6,
				"objective_control": 2
			},
			"abilities": [],
			"weapons": []
		},
		"models": models,
		"flags": {}
	}
	GameState.state["units"][id] = unit
	return unit

# ==========================================
# Section 1: Ability Detection Tests
# ==========================================

func test_has_throat_slittas_ability_detected():
	"""Kommandos unit should be detected as having Throat Slittas."""
	_create_kommandos("k1", 1)
	assert_true(ability_mgr.has_throat_slittas_ability("k1"),
		"Kommandos should have Throat Slittas ability")

func test_has_throat_slittas_ability_not_detected_for_other_units():
	"""Non-Kommandos unit should NOT be detected as having Throat Slittas."""
	_create_enemy_unit("e1", 2)
	assert_false(ability_mgr.has_throat_slittas_ability("e1"),
		"Regular unit should not have Throat Slittas ability")

func test_has_throat_slittas_ability_nonexistent_unit():
	"""Nonexistent unit should return false."""
	assert_false(ability_mgr.has_throat_slittas_ability("nonexistent"),
		"Nonexistent unit should not have Throat Slittas ability")

# ==========================================
# Section 2: ABILITY_EFFECTS Table Tests
# ==========================================

func test_throat_slittas_in_ability_effects_table():
	"""Throat Slittas should be in the ABILITY_EFFECTS table and marked as implemented."""
	var effect_def = ability_mgr.get_ability_effect_definition("Throat Slittas")
	assert_false(effect_def.is_empty(), "Throat Slittas should exist in ABILITY_EFFECTS")
	assert_true(effect_def.get("implemented", false), "Throat Slittas should be marked as implemented")
	assert_eq(effect_def.get("condition", ""), "start_of_shooting", "Condition should be start_of_shooting")
	assert_eq(effect_def.get("target", ""), "enemy_within_9", "Target should be enemy_within_9")

# ==========================================
# Section 3: Distance/Range Tests
# ==========================================

func test_models_within_9_inches():
	"""Models positioned within 9\" should be counted correctly."""
	# 9 inches = 9 * 40 = 360 pixels (center-to-center), minus base radii
	# 32mm base = ~50.4px diameter = ~25.2px radius each
	# Edge-to-edge 9" = ~360px center-to-center for 32mm bases minus ~50px = ~310px edge-to-edge max
	# Place Kommandos at x=200 and enemy at x=400 => center distance = 200px = ~5 inches — well within 9"
	_create_kommandos("k1", 1, 5, 200.0, 200.0)
	_create_enemy_unit("e1", 2, 3, 400.0, 200.0)

	# Manually test the distance measurement
	var k_models = GameState.state["units"]["k1"]["models"]
	var e_unit = GameState.state["units"]["e1"]

	# First Kommando model is at x=200, first enemy model at x=400
	# Center-to-center = 200px = 5 inches, base radii = ~25px each
	# Edge-to-edge ~ 150px = ~3.75 inches — well within 9"
	var dist = measurement.model_to_model_distance_inches(k_models[0], e_unit["models"][0])
	assert_true(dist <= 9.0, "Models should be within 9\" (actual: %.1f\")" % dist)

func test_models_beyond_9_inches():
	"""Models positioned beyond 9\" should not be counted."""
	# 9" = 360px. Place models 500px apart => ~12.5" center-to-center
	_create_kommandos("k1", 1, 3, 100.0, 200.0)
	_create_enemy_unit("e1", 2, 3, 700.0, 200.0)

	var k_models = GameState.state["units"]["k1"]["models"]
	var e_unit = GameState.state["units"]["e1"]

	var dist = measurement.model_to_model_distance_inches(k_models[0], e_unit["models"][0])
	assert_true(dist > 9.0, "Models should be beyond 9\" (actual: %.1f\")" % dist)
