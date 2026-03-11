extends "res://addons/gut/test.gd"

# Tests for the DAT'S OUR LOOT! ability implementation (OA-12)
#
# Per Warhammer 40k 10th Edition Lootas datasheet:
# "Each time a model in this unit makes a ranged attack, re-roll a Hit roll
# of 1. If that attack targets a unit that is within range of an objective
# marker, you can re-roll the Hit roll instead."
#
# These tests verify:
# 1. has_dats_our_loot() detects the ability on Lootas units
# 2. has_dats_our_loot() returns false for units without the ability
# 3. is_unit_near_any_objective() correctly checks proximity to objective markers
# 4. get_dats_our_loot_reroll_scope() returns correct scope based on target proximity
# 5. Ability is defined in UnitAbilityManager.ABILITY_EFFECTS

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

func _make_lootas_unit() -> Dictionary:
	return {
		"id": "U_LOOTAS_TEST",
		"owner": 1,
		"meta": {
			"name": "Lootas",
			"keywords": ["ORKS", "INFANTRY", "LOOTAS"],
			"abilities": [
				{"name": "Dat's Our Loot!", "type": "Datasheet", "description": "Re-roll 1s to hit; full re-roll if target near objective"}
			]
		},
		"models": [
			{"alive": true, "position": {"x": 200.0, "y": 200.0}, "base_mm": 32}
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

func _make_target_near_objective() -> Dictionary:
	"""Target unit placed at (400, 300), within range of objective at (400, 300)."""
	return {
		"id": "U_TARGET_NEAR",
		"owner": 2,
		"meta": {
			"name": "Tactical Marines",
			"keywords": ["IMPERIUM", "INFANTRY", "ADEPTUS ASTARTES"]
		},
		"models": [
			{"alive": true, "position": {"x": 400.0, "y": 300.0}, "base_mm": 32}
		]
	}

func _make_target_far_from_objectives() -> Dictionary:
	"""Target unit placed very far from any objective."""
	return {
		"id": "U_TARGET_FAR",
		"owner": 2,
		"meta": {
			"name": "Scouts",
			"keywords": ["IMPERIUM", "INFANTRY"]
		},
		"models": [
			{"alive": true, "position": {"x": 2000.0, "y": 2000.0}, "base_mm": 32}
		]
	}

func _make_board_with_objectives() -> Dictionary:
	"""Board with objectives at known positions."""
	return {
		"board": {
			"objectives": [
				{"id": "obj_1", "position": {"x": 400.0, "y": 300.0}},
				{"id": "obj_2", "position": {"x": 800.0, "y": 600.0}}
			]
		}
	}

func _make_board_without_objectives() -> Dictionary:
	return {"board": {"objectives": []}}

# ==========================================
# has_dats_our_loot() Tests
# ==========================================

func test_has_dats_our_loot_with_ability():
	"""has_dats_our_loot should return true for Lootas with the ability."""
	var actor = _make_lootas_unit()
	assert_true(rules_engine.has_dats_our_loot(actor),
		"Lootas with Dat's Our Loot! should be detected")

func test_has_dats_our_loot_without_ability():
	"""has_dats_our_loot should return false for units without the ability."""
	var actor = _make_unit_without_ability()
	assert_false(rules_engine.has_dats_our_loot(actor),
		"Unit without Dat's Our Loot! should not be detected")

func test_has_dats_our_loot_string_format():
	"""has_dats_our_loot should detect string format ability."""
	var actor = {
		"id": "U_STRING_TEST",
		"meta": {
			"name": "Lootas",
			"keywords": ["ORKS", "INFANTRY", "LOOTAS"],
			"abilities": ["Dat's Our Loot!"]
		}
	}
	assert_true(rules_engine.has_dats_our_loot(actor),
		"Dat's Our Loot! as string ability should be detected")

# ==========================================
# is_unit_near_any_objective() Tests
# ==========================================

func test_unit_near_objective():
	"""Unit placed on top of an objective should be detected as near."""
	var target = _make_target_near_objective()
	var board = _make_board_with_objectives()
	assert_true(rules_engine.is_unit_near_any_objective(target, board),
		"Unit at objective position should be within range")

func test_unit_far_from_objectives():
	"""Unit placed far from all objectives should NOT be detected as near."""
	var target = _make_target_far_from_objectives()
	var board = _make_board_with_objectives()
	assert_false(rules_engine.is_unit_near_any_objective(target, board),
		"Unit 2000px from objectives should not be within range")

func test_unit_near_no_objectives():
	"""Board with no objectives should return false."""
	var target = _make_target_near_objective()
	var board = _make_board_without_objectives()
	assert_false(rules_engine.is_unit_near_any_objective(target, board),
		"No objectives on board should return false")

func test_unit_near_objective_edge_of_range():
	"""Unit at the edge of objective control range (3.787\" = ~151.5px) should be detected."""
	# Control range = 3.78740157 * 40 = 151.496px
	# Model base radius for 32mm = (32/25.4) * 40 / 2 = 25.197px
	# So center-to-center = 151.496 + 25.197 = 176.693px should be at the edge
	var target = {
		"id": "U_EDGE_TARGET",
		"owner": 2,
		"meta": {"name": "Edge Test", "keywords": []},
		"models": [
			{"alive": true, "position": {"x": 576.0, "y": 300.0}, "base_mm": 32}
		]
	}
	var board = _make_board_with_objectives()  # obj at (400, 300)
	# Distance = 576 - 400 = 176px; edge = 176 - 25.197 = 150.8px < 151.5px
	assert_true(rules_engine.is_unit_near_any_objective(target, board),
		"Unit at edge of objective control range should be within range")

func test_unit_just_outside_objective_range():
	"""Unit just outside objective control range should NOT be detected."""
	# Need edge distance > 151.496px, so center distance > 151.496 + 25.197 = 176.693px
	var target = {
		"id": "U_OUTSIDE_TARGET",
		"owner": 2,
		"meta": {"name": "Outside Test", "keywords": []},
		"models": [
			{"alive": true, "position": {"x": 580.0, "y": 300.0}, "base_mm": 32}
		]
	}
	var board = _make_board_with_objectives()  # obj at (400, 300)
	# Distance = 580 - 400 = 180px; edge = 180 - 25.197 = 154.8px > 151.5px
	assert_false(rules_engine.is_unit_near_any_objective(target, board),
		"Unit just outside objective control range should not be within range")

func test_dead_models_not_counted():
	"""Dead models should not count for objective proximity check."""
	var target = {
		"id": "U_DEAD_TARGET",
		"owner": 2,
		"meta": {"name": "Dead Test", "keywords": []},
		"models": [
			{"alive": false, "position": {"x": 400.0, "y": 300.0}, "base_mm": 32},
			{"alive": true, "position": {"x": 2000.0, "y": 2000.0}, "base_mm": 32}
		]
	}
	var board = _make_board_with_objectives()  # obj at (400, 300)
	# Dead model is on the objective but shouldn't count; alive model is far
	assert_false(rules_engine.is_unit_near_any_objective(target, board),
		"Dead models should not count for objective proximity")

# ==========================================
# get_dats_our_loot_reroll_scope() Tests
# ==========================================

func test_reroll_scope_full_near_objective():
	"""Full re-roll (\"failed\") when target is near an objective marker."""
	var actor = _make_lootas_unit()
	var target = _make_target_near_objective()
	var board = _make_board_with_objectives()
	var scope = rules_engine.get_dats_our_loot_reroll_scope(actor, target, board)
	assert_eq(scope, "failed",
		"Should get full re-roll when target is near objective")

func test_reroll_scope_ones_far_from_objective():
	"""Re-roll 1s (\"ones\") when target is NOT near an objective marker."""
	var actor = _make_lootas_unit()
	var target = _make_target_far_from_objectives()
	var board = _make_board_with_objectives()
	var scope = rules_engine.get_dats_our_loot_reroll_scope(actor, target, board)
	assert_eq(scope, "ones",
		"Should get re-roll 1s when target is not near objective")

func test_reroll_scope_empty_no_ability():
	"""No re-roll (\"\") when unit doesn't have the ability."""
	var actor = _make_unit_without_ability()
	var target = _make_target_near_objective()
	var board = _make_board_with_objectives()
	var scope = rules_engine.get_dats_our_loot_reroll_scope(actor, target, board)
	assert_eq(scope, "",
		"Unit without ability should get no re-roll scope")

func test_reroll_scope_ones_no_objectives_on_board():
	"""Re-roll 1s when board has no objectives (target can't be near any)."""
	var actor = _make_lootas_unit()
	var target = _make_target_near_objective()
	var board = _make_board_without_objectives()
	var scope = rules_engine.get_dats_our_loot_reroll_scope(actor, target, board)
	assert_eq(scope, "ones",
		"Should get re-roll 1s when no objectives exist")

# ==========================================
# ABILITY_EFFECTS definition test
# ==========================================

func test_dats_our_loot_in_ability_effects():
	"""Dat's Our Loot! should be defined in UnitAbilityManager.ABILITY_EFFECTS."""
	var unit_ability_manager = AutoloadHelper.get_autoload("UnitAbilityManager")
	if unit_ability_manager == null:
		gut.p("UnitAbilityManager autoload not available — skipping")
		pending("UnitAbilityManager autoload not available")
		return

	var effect_def = unit_ability_manager.ABILITY_EFFECTS.get("Dat's Our Loot!", {})
	assert_false(effect_def.is_empty(), "Dat's Our Loot! should be in ABILITY_EFFECTS")
	assert_true(effect_def.get("implemented", false), "Dat's Our Loot! should be marked as implemented")
	assert_eq(effect_def.get("attack_type", ""), "ranged", "Dat's Our Loot! should be ranged only")
	assert_eq(effect_def.get("condition", ""), "target_near_objective", "Dat's Our Loot! should have target_near_objective condition")

# ==========================================
# Live army data test (Lootas from orks.json)
# ==========================================

func test_live_lootas_has_ability():
	"""Lootas from orks.json should have the Dat's Our Loot! ability."""
	var army_list_manager = AutoloadHelper.get_autoload("ArmyListManager")
	if army_list_manager == null:
		gut.p("ArmyListManager not available — skipping")
		pending("ArmyListManager not available")
		return

	var game_state = AutoloadHelper.get_autoload("GameState")
	if game_state == null:
		gut.p("GameState not available — skipping")
		pending("GameState not available")
		return

	# Load Orks army
	var army_path = "res://armies/orks.json"
	if not FileAccess.file_exists(army_path):
		gut.p("orks.json not found at %s — skipping" % army_path)
		pending("orks.json not found")
		return

	army_list_manager.load_army(army_path, 1)
	await get_tree().process_frame

	# Find a Lootas unit
	var found_lootas = false
	var all_units = game_state.state.get("units", {})
	for unit_id in all_units:
		var unit = all_units[unit_id]
		if unit.get("meta", {}).get("name", "") == "Lootas":
			assert_true(rules_engine.has_dats_our_loot(unit),
				"Live Lootas unit should have Dat's Our Loot! ability")
			found_lootas = true
			break

	if not found_lootas:
		gut.p("No Lootas unit found in orks.json army — skipping")
		pending("No Lootas unit found")
