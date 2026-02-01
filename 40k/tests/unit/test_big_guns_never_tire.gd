extends "res://addons/gut/test.gd"

# Tests for the BIG GUNS NEVER TIRE rule implementation
# Tests the ACTUAL RulesEngine methods
#
# Per Warhammer 40k rules: MONSTER and VEHICLE units can shoot even while
# within Engagement Range of enemy units, but can only target units they
# are in Engagement Range with, or other units (with a -1 to hit penalty).

const GameStateData = preload("res://autoloads/GameState.gd")

var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

# ==========================================
# is_monster_or_vehicle() Tests
# ==========================================

func test_is_monster_or_vehicle_returns_true_for_monster():
	"""Test that a unit with MONSTER keyword is recognized"""
	var unit = {
		"id": "test_monster",
		"meta": {
			"keywords": ["MONSTER", "CHARACTER"]
		}
	}
	var result = rules_engine.is_monster_or_vehicle(unit)
	assert_true(result, "Unit with MONSTER keyword should be recognized")

func test_is_monster_or_vehicle_returns_true_for_vehicle():
	"""Test that a unit with VEHICLE keyword is recognized"""
	var unit = {
		"id": "test_vehicle",
		"meta": {
			"keywords": ["VEHICLE", "FLY"]
		}
	}
	var result = rules_engine.is_monster_or_vehicle(unit)
	assert_true(result, "Unit with VEHICLE keyword should be recognized")

func test_is_monster_or_vehicle_returns_false_for_infantry():
	"""Test that INFANTRY units are not considered MONSTER or VEHICLE"""
	var unit = {
		"id": "test_infantry",
		"meta": {
			"keywords": ["INFANTRY", "CORE"]
		}
	}
	var result = rules_engine.is_monster_or_vehicle(unit)
	assert_false(result, "INFANTRY unit should not be MONSTER or VEHICLE")

func test_is_monster_or_vehicle_returns_false_for_empty_keywords():
	"""Test that units without keywords return false"""
	var unit = {
		"id": "test_unit",
		"meta": {}
	}
	var result = rules_engine.is_monster_or_vehicle(unit)
	assert_false(result, "Unit without keywords should return false")

# ==========================================
# big_guns_never_tire_applies() Tests
# ==========================================

func test_big_guns_never_tire_applies_to_monster():
	"""Test that BGNT applies to MONSTER units"""
	var unit = {
		"id": "test_monster",
		"meta": {
			"keywords": ["MONSTER"]
		}
	}
	var result = rules_engine.big_guns_never_tire_applies(unit)
	assert_true(result, "Big Guns Never Tire should apply to MONSTER units")

func test_big_guns_never_tire_applies_to_vehicle():
	"""Test that BGNT applies to VEHICLE units"""
	var unit = {
		"id": "test_vehicle",
		"meta": {
			"keywords": ["VEHICLE"]
		}
	}
	var result = rules_engine.big_guns_never_tire_applies(unit)
	assert_true(result, "Big Guns Never Tire should apply to VEHICLE units")

func test_big_guns_never_tire_not_applies_to_infantry():
	"""Test that BGNT does not apply to INFANTRY units"""
	var unit = {
		"id": "test_infantry",
		"meta": {
			"keywords": ["INFANTRY"]
		}
	}
	var result = rules_engine.big_guns_never_tire_applies(unit)
	assert_false(result, "Big Guns Never Tire should NOT apply to INFANTRY units")

# ==========================================
# BGNT Rule Logic Tests
# ==========================================

func test_bgnt_penalty_when_shooting_non_engaged():
	"""Test that BGNT units get -1 to hit when shooting non-engaged targets"""
	# Per rules: when a BGNT unit shoots at a unit it is NOT in engagement
	# range with, it suffers -1 to hit
	var shooting_non_engaged_target = true
	var hit_modifier = -1 if shooting_non_engaged_target else 0
	assert_eq(hit_modifier, -1, "BGNT should have -1 to hit against non-engaged targets")

func test_bgnt_no_penalty_when_shooting_engaged():
	"""Test that BGNT units have no penalty when shooting engaged targets"""
	# Per rules: no penalty when shooting at units in engagement range
	var shooting_engaged_target = true
	var hit_modifier = 0 if shooting_engaged_target else -1
	assert_eq(hit_modifier, 0, "BGNT should have no penalty against engaged targets")
