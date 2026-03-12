extends "res://addons/gut/test.gd"

# Tests for the SPLAT! ability implementation (OA-38)
#
# Per Warhammer 40k 10th Edition datasheets:
# Big Gunz: "Each time a model in this unit makes a ranged attack that targets
# a unit that contains 10 or more models, re-roll a Hit roll of 1."
# Mek Gunz: "Each time a model in this unit makes a ranged attack, if this unit
# is at its Starting Strength and the target does not have the MONSTER or VEHICLE
# keyword, re-roll a Hit roll of 1."
#
# These tests verify:
# 1. has_splat() detects the ability on Big Gunz and Mek Gunz units
# 2. has_splat() returns false for units without the ability
# 3. is_unit_at_starting_strength() correctly checks if all models are alive
# 4. get_splat_reroll_scope() returns correct scope based on unit-specific criteria
# 5. Ability is defined in UnitAbilityManager.ABILITY_EFFECTS

var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

# ==========================================
# Helper: Create test units
# ==========================================

func _make_big_gunz_unit() -> Dictionary:
	return {
		"id": "U_BIG_GUNZ_TEST",
		"owner": 1,
		"meta": {
			"name": "Big Gunz",
			"keywords": ["ORKS", "BIG GUNZ"],
			"abilities": [
				{"name": "Splat!", "type": "Datasheet", "description": "Re-roll hit 1s vs 10+ model targets"}
			]
		},
		"models": [
			{"alive": true, "position": {"x": 200.0, "y": 200.0}, "base_mm": 32},
			{"alive": true, "position": {"x": 220.0, "y": 200.0}, "base_mm": 32},
			{"alive": true, "position": {"x": 240.0, "y": 200.0}, "base_mm": 32}
		]
	}

func _make_mek_gunz_unit() -> Dictionary:
	return {
		"id": "U_MEK_GUNZ_TEST",
		"owner": 1,
		"meta": {
			"name": "Mek Gunz",
			"keywords": ["ORKS", "MEK GUNZ"],
			"abilities": [
				{"name": "Splat!", "type": "Datasheet", "description": "Re-roll hit 1s at Starting Strength vs non-MONSTER/VEHICLE"}
			]
		},
		"models": [
			{"alive": true, "position": {"x": 200.0, "y": 200.0}, "base_mm": 32}
		]
	}

func _make_mek_gunz_damaged() -> Dictionary:
	var unit = _make_mek_gunz_unit()
	# Add a second model that is dead (below starting strength)
	unit["models"].append({"alive": false, "position": {"x": 220.0, "y": 200.0}, "base_mm": 32})
	return unit

func _make_unit_without_ability() -> Dictionary:
	return {
		"id": "U_BOYZ_TEST",
		"owner": 1,
		"meta": {
			"name": "Boyz",
			"keywords": ["ORKS", "INFANTRY"],
			"abilities": [{"name": "Waaagh!", "type": "Faction"}]
		},
		"models": [
			{"alive": true, "position": {"x": 200.0, "y": 200.0}, "base_mm": 32}
		]
	}

func _make_target_with_models(count: int) -> Dictionary:
	"""Create a target unit with the specified number of alive models."""
	var models = []
	for i in range(count):
		models.append({"alive": true, "position": {"x": 400.0 + i * 20.0, "y": 300.0}, "base_mm": 32})
	return {
		"id": "U_TARGET_MODELS",
		"owner": 2,
		"meta": {
			"name": "Gretchin",
			"keywords": ["ORKS", "INFANTRY", "GRETCHIN"]
		},
		"models": models
	}

func _make_monster_target() -> Dictionary:
	return {
		"id": "U_MONSTER_TARGET",
		"owner": 2,
		"meta": {
			"name": "Carnifex",
			"keywords": ["TYRANIDS", "MONSTER", "CARNIFEX"]
		},
		"models": [
			{"alive": true, "position": {"x": 400.0, "y": 300.0}, "base_mm": 50}
		]
	}

func _make_vehicle_target() -> Dictionary:
	return {
		"id": "U_VEHICLE_TARGET",
		"owner": 2,
		"meta": {
			"name": "Leman Russ",
			"keywords": ["IMPERIUM", "VEHICLE", "LEMAN RUSS"]
		},
		"models": [
			{"alive": true, "position": {"x": 400.0, "y": 300.0}, "base_mm": 50}
		]
	}

func _make_infantry_target() -> Dictionary:
	return {
		"id": "U_INFANTRY_TARGET",
		"owner": 2,
		"meta": {
			"name": "Tactical Marines",
			"keywords": ["IMPERIUM", "INFANTRY", "ADEPTUS ASTARTES"]
		},
		"models": [
			{"alive": true, "position": {"x": 400.0, "y": 300.0}, "base_mm": 32}
		]
	}

# ==========================================
# Test: has_splat()
# ==========================================

func test_has_splat_big_gunz():
	"""Big Gunz with Splat! ability should be detected."""
	var unit = _make_big_gunz_unit()
	assert_true(RulesEngine.has_splat(unit), "Big Gunz should have Splat! ability")

func test_has_splat_mek_gunz():
	"""Mek Gunz with Splat! ability should be detected."""
	var unit = _make_mek_gunz_unit()
	assert_true(RulesEngine.has_splat(unit), "Mek Gunz should have Splat! ability")

func test_has_splat_returns_false_for_unit_without_ability():
	"""Units without Splat! should return false."""
	var unit = _make_unit_without_ability()
	assert_false(RulesEngine.has_splat(unit), "Boyz should not have Splat! ability")

func test_has_splat_string_ability():
	"""Splat! specified as a string (not dict) should be detected."""
	var unit = {
		"meta": {
			"name": "Big Gunz",
			"abilities": ["Waaagh!", "Splat!"]
		},
		"models": [{"alive": true}]
	}
	assert_true(RulesEngine.has_splat(unit), "Splat! as string ability should be detected")

# ==========================================
# Test: is_unit_at_starting_strength()
# ==========================================

func test_at_starting_strength_all_alive():
	"""Unit with all models alive should be at starting strength."""
	var unit = _make_mek_gunz_unit()
	assert_true(RulesEngine.is_unit_at_starting_strength(unit), "Fully alive unit should be at starting strength")

func test_not_at_starting_strength_model_dead():
	"""Unit with a dead model should NOT be at starting strength."""
	var unit = _make_mek_gunz_damaged()
	assert_false(RulesEngine.is_unit_at_starting_strength(unit), "Unit with dead model should not be at starting strength")

func test_at_starting_strength_big_gunz():
	"""Big Gunz with all models alive should be at starting strength."""
	var unit = _make_big_gunz_unit()
	assert_true(RulesEngine.is_unit_at_starting_strength(unit), "Big Gunz with all alive should be at starting strength")

# ==========================================
# Test: get_splat_reroll_scope() — Big Gunz
# ==========================================

func test_big_gunz_splat_vs_10_plus_models():
	"""Big Gunz should get re-roll 1s when targeting units with 10+ models."""
	var actor = _make_big_gunz_unit()
	var target = _make_target_with_models(10)
	var scope = RulesEngine.get_splat_reroll_scope(actor, target)
	assert_eq(scope, "ones", "Big Gunz should re-roll 1s vs 10+ model target")

func test_big_gunz_splat_vs_11_models():
	"""Big Gunz should get re-roll 1s when targeting units with 11 models."""
	var actor = _make_big_gunz_unit()
	var target = _make_target_with_models(11)
	var scope = RulesEngine.get_splat_reroll_scope(actor, target)
	assert_eq(scope, "ones", "Big Gunz should re-roll 1s vs 11 model target")

func test_big_gunz_splat_vs_9_models():
	"""Big Gunz should NOT get re-roll 1s when targeting units with fewer than 10 models."""
	var actor = _make_big_gunz_unit()
	var target = _make_target_with_models(9)
	var scope = RulesEngine.get_splat_reroll_scope(actor, target)
	assert_eq(scope, "", "Big Gunz should NOT re-roll 1s vs 9 model target")

func test_big_gunz_splat_vs_1_model():
	"""Big Gunz should NOT get re-roll 1s when targeting a single model."""
	var actor = _make_big_gunz_unit()
	var target = _make_target_with_models(1)
	var scope = RulesEngine.get_splat_reroll_scope(actor, target)
	assert_eq(scope, "", "Big Gunz should NOT re-roll 1s vs 1 model target")

# ==========================================
# Test: get_splat_reroll_scope() — Mek Gunz
# ==========================================

func test_mek_gunz_splat_at_strength_vs_infantry():
	"""Mek Gunz at starting strength should get re-roll 1s vs non-MONSTER/VEHICLE."""
	var actor = _make_mek_gunz_unit()
	var target = _make_infantry_target()
	var scope = RulesEngine.get_splat_reroll_scope(actor, target)
	assert_eq(scope, "ones", "Mek Gunz at starting strength should re-roll 1s vs infantry")

func test_mek_gunz_splat_at_strength_vs_monster():
	"""Mek Gunz at starting strength should NOT get re-roll 1s vs MONSTER."""
	var actor = _make_mek_gunz_unit()
	var target = _make_monster_target()
	var scope = RulesEngine.get_splat_reroll_scope(actor, target)
	assert_eq(scope, "", "Mek Gunz should NOT re-roll 1s vs MONSTER target")

func test_mek_gunz_splat_at_strength_vs_vehicle():
	"""Mek Gunz at starting strength should NOT get re-roll 1s vs VEHICLE."""
	var actor = _make_mek_gunz_unit()
	var target = _make_vehicle_target()
	var scope = RulesEngine.get_splat_reroll_scope(actor, target)
	assert_eq(scope, "", "Mek Gunz should NOT re-roll 1s vs VEHICLE target")

func test_mek_gunz_splat_damaged_vs_infantry():
	"""Mek Gunz below starting strength should NOT get re-roll 1s, even vs infantry."""
	var actor = _make_mek_gunz_damaged()
	var target = _make_infantry_target()
	var scope = RulesEngine.get_splat_reroll_scope(actor, target)
	assert_eq(scope, "", "Damaged Mek Gunz should NOT re-roll 1s")

# ==========================================
# Test: No re-roll for units without Splat!
# ==========================================

func test_no_splat_unit_vs_10_plus_models():
	"""Units without Splat! should never get re-roll scope."""
	var actor = _make_unit_without_ability()
	var target = _make_target_with_models(10)
	var scope = RulesEngine.get_splat_reroll_scope(actor, target)
	assert_eq(scope, "", "Unit without Splat! should not get re-roll scope")

# ==========================================
# Test: Ability definition in UnitAbilityManager
# ==========================================

func test_splat_ability_defined():
	"""Splat! should be defined in UnitAbilityManager.ABILITY_EFFECTS."""
	assert_true(
		UnitAbilityManager.ABILITY_EFFECTS.has("Splat!"),
		"Splat! should be defined in ABILITY_EFFECTS"
	)

func test_splat_ability_is_implemented():
	"""Splat! should be marked as implemented."""
	var ability = UnitAbilityManager.ABILITY_EFFECTS.get("Splat!", {})
	assert_true(ability.get("implemented", false), "Splat! should be marked as implemented")

func test_splat_ability_is_ranged():
	"""Splat! should apply to ranged attacks only."""
	var ability = UnitAbilityManager.ABILITY_EFFECTS.get("Splat!", {})
	assert_eq(ability.get("attack_type", ""), "ranged", "Splat! should be ranged only")
