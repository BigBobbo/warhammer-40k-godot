extends "res://addons/gut/test.gd"

# Tests for the TANK HUNTERS ability implementation (OA-11)
#
# Per Warhammer 40k 10th Edition Tankbustas datasheet:
# "Each time a model in this unit makes a ranged attack that targets a
# MONSTER or VEHICLE unit, add 1 to the Hit roll and add 1 to the Wound roll."
#
# These tests verify:
# 1. has_tank_hunters_vs_target() detects Tank Hunters ability + MONSTER/VEHICLE target
# 2. has_tank_hunters_vs_target() returns false for non-MONSTER/VEHICLE targets
# 3. has_tank_hunters_vs_target() returns false for units without the ability
# 4. Tank Hunters ability is defined in UnitAbilityManager.ABILITY_EFFECTS

var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

# ==========================================
# Helper: Create a unit with Tank Hunters ability
# ==========================================

func _make_tankbustas_unit() -> Dictionary:
	return {
		"id": "U_TANKBUSTAS_TEST",
		"meta": {
			"name": "Tankbustas",
			"keywords": ["ORKS", "INFANTRY", "TANKBUSTAS"],
			"abilities": [
				{"name": "Tank Hunters", "type": "Datasheet", "description": "+1 Hit/Wound vs MONSTER/VEHICLE"}
			]
		}
	}

func _make_vehicle_target() -> Dictionary:
	return {
		"id": "U_VEHICLE_TARGET",
		"meta": {
			"name": "Leman Russ",
			"keywords": ["IMPERIUM", "VEHICLE", "LEMAN RUSS"]
		}
	}

func _make_monster_target() -> Dictionary:
	return {
		"id": "U_MONSTER_TARGET",
		"meta": {
			"name": "Hive Tyrant",
			"keywords": ["TYRANIDS", "MONSTER", "CHARACTER"]
		}
	}

func _make_infantry_target() -> Dictionary:
	return {
		"id": "U_INFANTRY_TARGET",
		"meta": {
			"name": "Tactical Marines",
			"keywords": ["IMPERIUM", "INFANTRY", "ADEPTUS ASTARTES"]
		}
	}

func _make_unit_without_tank_hunters() -> Dictionary:
	return {
		"id": "U_BOYZ_TEST",
		"meta": {
			"name": "Boyz",
			"keywords": ["ORKS", "INFANTRY"],
			"abilities": [
				{"name": "Waaagh!", "type": "Faction"}
			]
		}
	}

# ==========================================
# has_tank_hunters_vs_target() Tests
# ==========================================

func test_tank_hunters_vs_vehicle_target():
	"""Tank Hunters should return true when attacking a VEHICLE unit."""
	var actor = _make_tankbustas_unit()
	var target = _make_vehicle_target()
	assert_true(rules_engine.has_tank_hunters_vs_target(actor, target),
		"Tank Hunters should apply vs VEHICLE target")

func test_tank_hunters_vs_monster_target():
	"""Tank Hunters should return true when attacking a MONSTER unit."""
	var actor = _make_tankbustas_unit()
	var target = _make_monster_target()
	assert_true(rules_engine.has_tank_hunters_vs_target(actor, target),
		"Tank Hunters should apply vs MONSTER target")

func test_tank_hunters_vs_infantry_target():
	"""Tank Hunters should NOT apply when attacking an INFANTRY unit (no MONSTER/VEHICLE)."""
	var actor = _make_tankbustas_unit()
	var target = _make_infantry_target()
	assert_false(rules_engine.has_tank_hunters_vs_target(actor, target),
		"Tank Hunters should NOT apply vs INFANTRY target")

func test_no_tank_hunters_ability():
	"""Unit without Tank Hunters ability should not get the bonus."""
	var actor = _make_unit_without_tank_hunters()
	var target = _make_vehicle_target()
	assert_false(rules_engine.has_tank_hunters_vs_target(actor, target),
		"Unit without Tank Hunters should not get bonus vs VEHICLE")

func test_no_tank_hunters_vs_infantry():
	"""Unit without Tank Hunters should not get bonus vs infantry."""
	var actor = _make_unit_without_tank_hunters()
	var target = _make_infantry_target()
	assert_false(rules_engine.has_tank_hunters_vs_target(actor, target),
		"Unit without Tank Hunters should not get bonus vs INFANTRY")

# ==========================================
# Tank Hunters ability string format
# ==========================================

func test_tank_hunters_string_format():
	"""Tank Hunters as a simple string in abilities array should be detected."""
	var actor = {
		"id": "U_STRING_TEST",
		"meta": {
			"name": "Tankbustas",
			"keywords": ["ORKS", "INFANTRY", "TANKBUSTAS"],
			"abilities": ["Tank Hunters"]
		}
	}
	var target = _make_vehicle_target()
	assert_true(rules_engine.has_tank_hunters_vs_target(actor, target),
		"Tank Hunters as string ability should be detected")

# ==========================================
# Keyword case variations for target
# ==========================================

func test_tank_hunters_vs_lowercase_vehicle():
	"""Tank Hunters should work with lowercase 'vehicle' keyword on target."""
	var actor = _make_tankbustas_unit()
	var target = {
		"id": "U_LC_VEHICLE",
		"meta": {
			"name": "Tank",
			"keywords": ["vehicle"]
		}
	}
	assert_true(rules_engine.has_tank_hunters_vs_target(actor, target),
		"Tank Hunters should apply vs lowercase 'vehicle' keyword")

func test_tank_hunters_vs_lowercase_monster():
	"""Tank Hunters should work with lowercase 'monster' keyword on target."""
	var actor = _make_tankbustas_unit()
	var target = {
		"id": "U_LC_MONSTER",
		"meta": {
			"name": "Beast",
			"keywords": ["monster"]
		}
	}
	assert_true(rules_engine.has_tank_hunters_vs_target(actor, target),
		"Tank Hunters should apply vs lowercase 'monster' keyword")

# ==========================================
# ABILITY_EFFECTS definition test
# ==========================================

func test_tank_hunters_in_ability_effects():
	"""Tank Hunters should be defined in UnitAbilityManager.ABILITY_EFFECTS."""
	var unit_ability_manager = AutoloadHelper.get_autoload("UnitAbilityManager")
	if unit_ability_manager == null:
		gut.p("UnitAbilityManager autoload not available — skipping")
		pending("UnitAbilityManager autoload not available")
		return

	var effect_def = unit_ability_manager.ABILITY_EFFECTS.get("Tank Hunters", {})
	assert_false(effect_def.is_empty(), "Tank Hunters should be in ABILITY_EFFECTS")
	assert_true(effect_def.get("implemented", false), "Tank Hunters should be marked as implemented")
	assert_eq(effect_def.get("attack_type", ""), "ranged", "Tank Hunters should be ranged only")
	assert_eq(effect_def.get("condition", ""), "target_has_keyword", "Tank Hunters should have target_has_keyword condition")

	var target_keywords = effect_def.get("target_keywords", [])
	assert_true("MONSTER" in target_keywords, "Tank Hunters should list MONSTER as target keyword")
	assert_true("VEHICLE" in target_keywords, "Tank Hunters should list VEHICLE as target keyword")
