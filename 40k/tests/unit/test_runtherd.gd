extends "res://addons/gut/test.gd"

# Tests for OA-48: Runtherd ability for Gretchin
#
# Per Warhammer 40k 10th Edition rules (Gretchin datasheet):
#
# "Runtherd":
#   While this unit contains one or more Gretchin models, each time an attack
#   targets this unit, Runtherd models in this unit have a Toughness characteristic of 2.
#
# Implementation notes:
# - When Gretchin models are alive: Runtherd models use T2 (same as unit base T — no change)
# - When all Gretchin die: Runtherd models revert to T4 (from model_profiles stats_override)
# - Implemented in RulesEngine.get_runtherd_toughness_override()
# - Hooked into all 4 toughness resolution points (overwatch, shooting, auto-resolve, melee)
#
# These tests verify:
# 1. _unit_has_runtherd_ability() correctly identifies units with the ability
# 2. get_runtherd_toughness_override() returns -1 (no override) while Gretchin are alive
# 3. get_runtherd_toughness_override() returns T4 when all Gretchin are dead
# 4. get_runtherd_toughness_override() returns -1 for units without the Runtherd ability
# 5. get_runtherd_toughness_override() returns -1 when no Runtherd models are alive
# 6. "Runtherd" is registered in UnitAbilityManager.ABILITY_EFFECTS as implemented

var ability_mgr: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available")
		return
	ability_mgr = AutoloadHelper.get_autoload("UnitAbilityManager")
	assert_not_null(ability_mgr, "UnitAbilityManager must be available")

func _create_gretchin_unit(unit_id: String = "U_GRETCHIN_A") -> Dictionary:
	"""Create a full Gretchin unit with 2 Runtherds and 20 Gretchin, all alive."""
	var models = []
	# m1, m2 = Runtherds
	for i in range(1, 3):
		models.append({
			"id": "m%d" % i,
			"wounds": 1,
			"current_wounds": 1,
			"base_mm": 25,
			"position": null,
			"alive": true,
			"status_effects": [],
			"model_type": "runtherd"
		})
	# m3-m22 = Gretchin
	for i in range(3, 23):
		models.append({
			"id": "m%d" % i,
			"wounds": 1,
			"current_wounds": 1,
			"base_mm": 25,
			"position": null,
			"alive": true,
			"status_effects": [],
			"model_type": "gretchin"
		})
	return {
		"id": unit_id,
		"squad_id": unit_id,
		"owner": 1,
		"status": "DEPLOYED",
		"meta": {
			"name": "Gretchin",
			"keywords": ["ORKS", "INFANTRY", "GROTS", "GRETCHIN"],
			"stats": {"move": 6, "toughness": 2, "save": 7, "wounds": 1, "leadership": 8, "objective_control": 2},
			"abilities": [
				{"name": "Runtherd", "type": "Datasheet",
				 "description": "While this unit contains one or more Gretchin models, each time an attack targets this unit, Runtherd models in this unit have a Toughness characteristic of 2."}
			],
			"model_profiles": {
				"runtherd": {
					"label": "Runtherd",
					"stats_override": {"toughness": 4, "weapon_skill": 3},
					"weapons": ["Runtherd tools", "Slugga"],
					"transport_slots": 1
				},
				"gretchin": {
					"label": "Gretchin",
					"stats_override": {"toughness": 2, "weapon_skill": 5},
					"weapons": ["Grot blasta", "Close combat weapon"],
					"transport_slots": 1
				}
			}
		},
		"flags": {},
		"models": models
	}

func _create_boyz_unit(unit_id: String = "U_BOYZ_A") -> Dictionary:
	"""Create a regular Boyz unit without the Runtherd ability."""
	return {
		"id": unit_id,
		"squad_id": unit_id,
		"owner": 1,
		"status": "DEPLOYED",
		"meta": {
			"name": "Boyz",
			"keywords": ["ORKS", "INFANTRY"],
			"stats": {"move": 6, "toughness": 4, "save": 6, "wounds": 1, "leadership": 6, "objective_control": 2},
			"abilities": [
				{"name": "Waaagh!", "type": "Faction", "description": "Waaagh! faction ability"}
			]
		},
		"flags": {},
		"models": [
			{"id": "m1", "wounds": 1, "current_wounds": 1, "base_mm": 32,
			 "position": null, "alive": true, "status_effects": []}
		]
	}

# ============================================================================
# Test: ABILITY_EFFECTS table registration
# ============================================================================

func test_runtherd_in_ability_effects():
	"""Runtherd should be registered in ABILITY_EFFECTS."""
	assert_true(ability_mgr.ABILITY_EFFECTS.has("Runtherd"),
		"'Runtherd' should be in ABILITY_EFFECTS")

func test_runtherd_marked_implemented():
	"""Runtherd should be marked as implemented."""
	var entry = ability_mgr.ABILITY_EFFECTS.get("Runtherd", {})
	assert_true(entry.get("implemented", false),
		"'Runtherd' should be marked as implemented")

# ============================================================================
# Test: _unit_has_runtherd_ability()
# ============================================================================

func test_has_runtherd_ability_true_for_gretchin():
	"""Gretchin unit with Runtherd ability is correctly identified."""
	var unit = _create_gretchin_unit()
	var result = RulesEngine._unit_has_runtherd_ability(unit)
	assert_true(result, "Gretchin unit should have Runtherd ability")

func test_has_runtherd_ability_false_for_boyz():
	"""Boyz unit without Runtherd ability is correctly identified."""
	var unit = _create_boyz_unit()
	var result = RulesEngine._unit_has_runtherd_ability(unit)
	assert_false(result, "Boyz unit should not have Runtherd ability")

func test_has_runtherd_ability_false_for_empty_unit():
	"""Unit with no abilities is correctly identified."""
	var unit = {"meta": {"abilities": []}, "models": []}
	var result = RulesEngine._unit_has_runtherd_ability(unit)
	assert_false(result, "Unit with no abilities should not have Runtherd ability")

# ============================================================================
# Test: get_runtherd_toughness_override() — Gretchin alive (ability active)
# ============================================================================

func test_override_returns_minus1_while_gretchin_alive():
	"""No toughness override while Gretchin models are alive (T2 unchanged)."""
	var unit = _create_gretchin_unit()
	var result = RulesEngine.get_runtherd_toughness_override(unit)
	assert_eq(result, -1,
		"Should return -1 (no override) while Gretchin models are alive")

func test_override_returns_minus1_with_one_gretchin_alive():
	"""No override even with only one Gretchin alive."""
	var unit = _create_gretchin_unit()
	# Kill all Gretchin except m3
	for model in unit.models:
		if model.model_type == "gretchin" and model.id != "m3":
			model.alive = false
	var result = RulesEngine.get_runtherd_toughness_override(unit)
	assert_eq(result, -1,
		"Should return -1 while at least one Gretchin model is alive")

# ============================================================================
# Test: get_runtherd_toughness_override() — All Gretchin dead (ability reverts)
# ============================================================================

func test_override_returns_t4_when_all_gretchin_dead():
	"""Returns T4 when all Gretchin models are dead."""
	var unit = _create_gretchin_unit()
	# Kill all Gretchin (m3-m22)
	for model in unit.models:
		if model.model_type == "gretchin":
			model.alive = false
	var result = RulesEngine.get_runtherd_toughness_override(unit)
	assert_eq(result, 4,
		"Should return T4 when all Gretchin are dead (Runtherds revert to base T)")

func test_override_t4_uses_model_profile_toughness():
	"""Toughness override comes from model_profiles.runtherd.stats_override.toughness."""
	var unit = _create_gretchin_unit()
	# Kill all Gretchin
	for model in unit.models:
		if model.model_type == "gretchin":
			model.alive = false
	# Verify it reads from model_profiles
	var profile_t = unit.meta.model_profiles.runtherd.stats_override.toughness
	var result = RulesEngine.get_runtherd_toughness_override(unit)
	assert_eq(result, profile_t,
		"Toughness override should match model_profiles.runtherd.stats_override.toughness")

# ============================================================================
# Test: get_runtherd_toughness_override() — Edge cases
# ============================================================================

func test_override_minus1_for_unit_without_ability():
	"""Units without Runtherd ability are not affected."""
	var unit = _create_boyz_unit()
	var result = RulesEngine.get_runtherd_toughness_override(unit)
	assert_eq(result, -1,
		"Boyz unit without Runtherd ability should return -1")

func test_override_minus1_when_all_runtherds_dead():
	"""Returns -1 when all Runtherd models are dead (ability irrelevant)."""
	var unit = _create_gretchin_unit()
	# Kill all Runtherds
	for model in unit.models:
		if model.model_type == "runtherd":
			model.alive = false
	var result = RulesEngine.get_runtherd_toughness_override(unit)
	assert_eq(result, -1,
		"Should return -1 when no Runtherd models are alive")

func test_override_minus1_when_entire_unit_dead():
	"""Returns -1 when the entire unit is wiped out."""
	var unit = _create_gretchin_unit()
	for model in unit.models:
		model.alive = false
	var result = RulesEngine.get_runtherd_toughness_override(unit)
	assert_eq(result, -1,
		"Should return -1 when entire unit is dead")

func test_override_defaults_to_t4_without_model_profiles():
	"""Defaults to T4 if model_profiles is missing (fallback)."""
	var unit = _create_gretchin_unit()
	# Remove model_profiles from meta
	unit.meta.erase("model_profiles")
	# Kill all Gretchin
	for model in unit.models:
		if model.model_type == "gretchin":
			model.alive = false
	var result = RulesEngine.get_runtherd_toughness_override(unit)
	assert_eq(result, 4,
		"Should default to T4 when model_profiles is missing")
