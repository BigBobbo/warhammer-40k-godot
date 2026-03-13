extends "res://addons/gut/test.gd"

# Tests for the PYROMANIAKS ability implementation (OA-14)
#
# Per Warhammer 40k 10th Edition Burna Boyz datasheet:
# "Each time a model in this unit makes a ranged attack with a burna that
# targets an enemy unit within 6", re-roll a Wound roll of 1. If the target
# of that attack is also within range of an objective marker, you can re-roll
# the Wound roll instead."
#
# These tests verify:
# 1. has_pyromaniaks() detects the ability on Burna Boyz units
# 2. has_pyromaniaks() returns false for units without the ability
# 3. get_pyromaniaks_reroll_scope() checks weapon is Torrent
# 4. get_pyromaniaks_reroll_scope() checks target is within 6"
# 5. get_pyromaniaks_reroll_scope() returns "failed" if target also near objective
# 6. Ability is defined in UnitAbilityManager.ABILITY_EFFECTS

var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

# ==========================================
# Helper: Create test units and board
# ==========================================

func _make_burna_boyz_unit(position: Dictionary = {"x": 200.0, "y": 200.0}) -> Dictionary:
	return {
		"id": "U_BURNA_BOYZ_TEST",
		"owner": 1,
		"meta": {
			"name": "Burna Boyz",
			"keywords": ["ORKS", "INFANTRY", "BURNA BOYZ"],
			"abilities": [
				{"name": "Pyromaniaks", "type": "Datasheet", "description": "Re-roll wound 1s with Torrent weapons vs enemies within 6\"; full re-roll if also near objective"}
			],
			"weapons": [
				{"name": "Burna", "type": "Ranged", "range": "12", "attacks": "D6", "strength": "4", "ap": "0", "damage": "1", "special_rules": "ignores cover, torrent"},
				{"name": "Slugga", "type": "Ranged", "range": "12", "attacks": "1", "strength": "4", "ap": "0", "damage": "1", "special_rules": "pistol"}
			]
		},
		"models": [
			{"alive": true, "position": position, "base_mm": 32}
		]
	}

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

func _make_target_within_6_inches(near_objective: bool = false) -> Dictionary:
	"""Target unit within 6\" (240px) of the attacker at (200, 200).
	Place target at (400, 200) = 200px = 5\" away."""
	var pos = {"x": 400.0, "y": 200.0}
	if near_objective:
		# Place on the objective at (400, 200)
		pos = {"x": 400.0, "y": 200.0}
	return {
		"id": "U_TARGET_NEAR",
		"owner": 2,
		"meta": {
			"name": "Tactical Marines",
			"keywords": ["IMPERIUM", "INFANTRY", "ADEPTUS ASTARTES"]
		},
		"models": [
			{"alive": true, "position": pos, "base_mm": 32}
		]
	}

func _make_target_beyond_6_inches() -> Dictionary:
	"""Target unit beyond 6\" (240px) of the attacker at (200, 200).
	Place target at (600, 200) = 400px = 10\" away."""
	return {
		"id": "U_TARGET_FAR",
		"owner": 2,
		"meta": {
			"name": "Scouts",
			"keywords": ["IMPERIUM", "INFANTRY"]
		},
		"models": [
			{"alive": true, "position": {"x": 600.0, "y": 200.0}, "base_mm": 32}
		]
	}

func _make_board(objectives: Array = []) -> Dictionary:
	"""Board with optional objectives. Units must be added to board['units'] separately."""
	return {
		"units": {},
		"board": {
			"objectives": objectives
		}
	}

# ==========================================
# has_pyromaniaks() Tests
# ==========================================

func test_has_pyromaniaks_with_ability():
	"""has_pyromaniaks should return true for Burna Boyz with the ability."""
	var actor = _make_burna_boyz_unit()
	assert_true(rules_engine.has_pyromaniaks(actor),
		"Burna Boyz with Pyromaniaks should be detected")

func test_has_pyromaniaks_without_ability():
	"""has_pyromaniaks should return false for units without the ability."""
	var actor = _make_unit_without_ability()
	assert_false(rules_engine.has_pyromaniaks(actor),
		"Unit without Pyromaniaks should not be detected")

func test_has_pyromaniaks_string_format():
	"""has_pyromaniaks should detect string format ability."""
	var actor = {
		"id": "U_STRING_TEST",
		"meta": {
			"name": "Burna Boyz",
			"keywords": ["ORKS", "INFANTRY", "BURNA BOYZ"],
			"abilities": ["Pyromaniaks"]
		}
	}
	assert_true(rules_engine.has_pyromaniaks(actor),
		"Pyromaniaks as string ability should be detected")

# ==========================================
# get_pyromaniaks_reroll_scope() Tests
# ==========================================

func test_reroll_scope_ones_torrent_within_6():
	"""Re-roll 1s when using Torrent weapon against target within 6\" (no objective)."""
	var actor = _make_burna_boyz_unit()
	var target = _make_target_within_6_inches()
	var board = _make_board()
	board["units"]["U_BURNA_BOYZ_TEST"] = actor
	board["units"]["U_TARGET_NEAR"] = target
	# weapon_id = "burna_ranged" matches _generate_weapon_id("Burna", "Ranged")
	var scope = rules_engine.get_pyromaniaks_reroll_scope(actor, target, "burna_ranged", board)
	assert_eq(scope, "ones",
		"Should get re-roll 1s with Torrent weapon vs target within 6\"")

func test_reroll_scope_failed_torrent_within_6_near_objective():
	"""Full re-roll when using Torrent weapon against target within 6\" AND near objective."""
	var actor = _make_burna_boyz_unit()
	var target = _make_target_within_6_inches(true)
	# Objective at target's position
	var board = _make_board([
		{"id": "obj_1", "position": {"x": 400.0, "y": 200.0}}
	])
	board["units"]["U_BURNA_BOYZ_TEST"] = actor
	board["units"]["U_TARGET_NEAR"] = target
	var scope = rules_engine.get_pyromaniaks_reroll_scope(actor, target, "burna_ranged", board)
	assert_eq(scope, "failed",
		"Should get full re-roll with Torrent weapon vs target within 6\" near objective")

func test_reroll_scope_empty_non_torrent_weapon():
	"""No re-roll when using a non-Torrent weapon (Slugga)."""
	var actor = _make_burna_boyz_unit()
	var target = _make_target_within_6_inches()
	var board = _make_board()
	board["units"]["U_BURNA_BOYZ_TEST"] = actor
	board["units"]["U_TARGET_NEAR"] = target
	# weapon_id = "slugga_ranged" matches _generate_weapon_id("Slugga", "Ranged")
	var scope = rules_engine.get_pyromaniaks_reroll_scope(actor, target, "slugga_ranged", board)
	assert_eq(scope, "",
		"Non-Torrent weapon should not trigger Pyromaniaks")

func test_reroll_scope_empty_target_beyond_6():
	"""No re-roll when target is beyond 6\" even with Torrent weapon."""
	var actor = _make_burna_boyz_unit()
	var target = _make_target_beyond_6_inches()
	var board = _make_board()
	board["units"]["U_BURNA_BOYZ_TEST"] = actor
	board["units"]["U_TARGET_FAR"] = target
	var scope = rules_engine.get_pyromaniaks_reroll_scope(actor, target, "burna_ranged", board)
	assert_eq(scope, "",
		"Target beyond 6\" should not trigger Pyromaniaks even with Torrent weapon")

func test_reroll_scope_empty_no_ability():
	"""No re-roll when unit doesn't have the ability."""
	var actor = _make_unit_without_ability()
	var target = _make_target_within_6_inches()
	var board = _make_board()
	board["units"]["U_BOYZ_TEST"] = actor
	board["units"]["U_TARGET_NEAR"] = target
	var scope = rules_engine.get_pyromaniaks_reroll_scope(actor, target, "burna_ranged", board)
	assert_eq(scope, "",
		"Unit without Pyromaniaks should get no re-roll scope")

# ==========================================
# ABILITY_EFFECTS definition test
# ==========================================

func test_pyromaniaks_in_ability_effects():
	"""Pyromaniaks should be defined in UnitAbilityManager.ABILITY_EFFECTS."""
	var unit_ability_manager = AutoloadHelper.get_autoload("UnitAbilityManager")
	if unit_ability_manager == null:
		gut.p("UnitAbilityManager autoload not available — skipping")
		pending("UnitAbilityManager autoload not available")
		return

	var effect_def = unit_ability_manager.ABILITY_EFFECTS.get("Pyromaniaks", {})
	assert_false(effect_def.is_empty(), "Pyromaniaks should be in ABILITY_EFFECTS")
	assert_true(effect_def.get("implemented", false), "Pyromaniaks should be marked as implemented")
	assert_eq(effect_def.get("attack_type", ""), "ranged", "Pyromaniaks should be ranged only")
	assert_eq(effect_def.get("condition", ""), "target_within_range", "Pyromaniaks should have target_within_range condition")
	assert_eq(effect_def.get("weapon_filter", ""), "torrent", "Pyromaniaks should filter to Torrent weapons")
