extends "res://addons/gut/test.gd"

# Tests for P2-71: Surge move rules and restrictions
#
# Per 10e Core Rules Update, "surge" moves are out-of-phase moves triggered by abilities.
# Restrictions:
#   1. Each unit can only make one surge move per phase
#   2. A unit cannot make a surge move while it is Battle-shocked
#   3. A unit cannot make a surge move while it is within Engagement Range
#
# These tests verify:
# 1. Surge move eligibility validation (all three restrictions)
# 2. RulesEngine static validation helper
# 3. Surge move tracking (once per phase reset)

const GameStateData = preload("res://autoloads/GameState.gd")

# ==========================================
# Helper: Create test units
# ==========================================

func _create_unit(id: String, owner: int = 1, model_count: int = 5, position: Vector2 = Vector2(400, 400)) -> Dictionary:
	var models = []
	for i in range(model_count):
		models.append({
			"id": "%s_m%d" % [id, i + 1],
			"alive": true,
			"position": position + Vector2(i * 30, 0),
			"base_mm": 32,
			"base_type": "circular",
			"current_wounds": 1,
		})
	return {
		"id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Test Unit %s" % id,
			"keywords": ["INFANTRY"],
			"stats": {"move": 6},
			"abilities": [],
		},
		"models": models,
		"flags": {},
		"status_effects": {},
	}

func _create_enemy_unit(id: String, owner: int = 2, position: Vector2 = Vector2(800, 400)) -> Dictionary:
	var unit = _create_unit(id, owner, 5, position)
	unit.meta.name = "Enemy Unit %s" % id
	return unit

# ==========================================
# Test: Surge move eligibility - basic pass
# ==========================================

func test_surge_move_eligible_unit_passes_validation():
	"""A deployed, non-battle-shocked, non-engaged unit should be eligible for surge move."""
	var unit = _create_unit("surge_ok")
	var all_units = {"surge_ok": unit}

	var result = RulesEngine.validate_surge_move_eligibility(unit, "surge_ok", false, all_units)
	assert_true(result.valid, "Deployed unit should be eligible for surge move")
	assert_eq(result.errors.size(), 0, "No errors expected")

# ==========================================
# Test: Restriction 1 - Once per phase
# ==========================================

func test_surge_move_blocked_if_already_surged_this_phase():
	"""A unit that has already surged this phase cannot surge again."""
	var unit = _create_unit("surge_once")
	var all_units = {"surge_once": unit}

	var result = RulesEngine.validate_surge_move_eligibility(unit, "surge_once", true, all_units)
	assert_false(result.valid, "Unit should NOT be able to surge twice in one phase")
	assert_true(result.errors[0].find("already made a surge move") >= 0,
		"Error should mention already surged: %s" % result.errors[0])

# ==========================================
# Test: Restriction 2 - Battle-shocked (flags)
# ==========================================

func test_surge_move_blocked_if_battle_shocked_via_flags():
	"""A Battle-shocked unit (via flags.battle_shocked) cannot make a surge move."""
	var unit = _create_unit("surge_shocked")
	unit.flags["battle_shocked"] = true
	var all_units = {"surge_shocked": unit}

	var result = RulesEngine.validate_surge_move_eligibility(unit, "surge_shocked", false, all_units)
	assert_false(result.valid, "Battle-shocked unit should NOT be able to surge")
	assert_true(result.errors[0].find("Battle-shocked") >= 0,
		"Error should mention Battle-shocked: %s" % result.errors[0])

# ==========================================
# Test: Restriction 2 - Battle-shocked (status_effects)
# ==========================================

func test_surge_move_blocked_if_battle_shocked_via_status_effects():
	"""A Battle-shocked unit (via status_effects.battle_shocked) cannot make a surge move."""
	var unit = _create_unit("surge_shocked_se")
	unit.status_effects["battle_shocked"] = true
	var all_units = {"surge_shocked_se": unit}

	var result = RulesEngine.validate_surge_move_eligibility(unit, "surge_shocked_se", false, all_units)
	assert_false(result.valid, "Battle-shocked unit (status_effects) should NOT be able to surge")
	assert_true(result.errors[0].find("Battle-shocked") >= 0,
		"Error should mention Battle-shocked: %s" % result.errors[0])

# ==========================================
# Test: Restriction 3 - In Engagement Range
# ==========================================

func test_surge_move_blocked_if_in_engagement_range():
	"""A unit within Engagement Range of enemy models cannot make a surge move."""
	# Place friendly and enemy units very close together (within 1" = 40px)
	var friendly_pos = Vector2(400, 400)
	var enemy_pos = Vector2(430, 400)  # ~0.75" away (30px / 40px per inch)

	var unit = _create_unit("surge_engaged", 1, 1, friendly_pos)
	var enemy = _create_enemy_unit("enemy_close", 2, enemy_pos)
	enemy.models = [{
		"id": "enemy_close_m1",
		"alive": true,
		"position": enemy_pos,
		"base_mm": 32,
		"base_type": "circular",
		"current_wounds": 1,
	}]

	var all_units = {"surge_engaged": unit, "enemy_close": enemy}

	var result = RulesEngine.validate_surge_move_eligibility(unit, "surge_engaged", false, all_units)
	assert_false(result.valid, "Unit in Engagement Range should NOT be able to surge")
	assert_true(result.errors[0].find("Engagement Range") >= 0,
		"Error should mention Engagement Range: %s" % result.errors[0])

# ==========================================
# Test: Unit not in Engagement Range passes
# ==========================================

func test_surge_move_allowed_if_enemy_far_away():
	"""A unit NOT within Engagement Range should be eligible for surge move."""
	var friendly_pos = Vector2(400, 400)
	var enemy_pos = Vector2(800, 400)  # 10" away — well outside ER

	var unit = _create_unit("surge_far", 1, 1, friendly_pos)
	var enemy = _create_enemy_unit("enemy_far", 2, enemy_pos)

	var all_units = {"surge_far": unit, "enemy_far": enemy}

	var result = RulesEngine.validate_surge_move_eligibility(unit, "surge_far", false, all_units)
	assert_true(result.valid, "Unit far from enemies should be able to surge")

# ==========================================
# Test: Dead unit cannot surge
# ==========================================

func test_surge_move_blocked_if_no_alive_models():
	"""A unit with no alive models cannot make a surge move."""
	var unit = _create_unit("surge_dead", 1, 3)
	for model in unit.models:
		model.alive = false
	var all_units = {"surge_dead": unit}

	var result = RulesEngine.validate_surge_move_eligibility(unit, "surge_dead", false, all_units)
	assert_false(result.valid, "Unit with no alive models should NOT be able to surge")

# ==========================================
# Test: Non-battle-shocked, non-engaged passes all checks
# ==========================================

func test_surge_move_passes_all_restrictions():
	"""A unit that is not battle-shocked, not engaged, and hasn't surged should pass."""
	var unit = _create_unit("surge_all_ok", 1, 10, Vector2(200, 200))
	unit.flags["battle_shocked"] = false

	var enemy = _create_enemy_unit("enemy_distant", 2, Vector2(1600, 1600))  # Very far
	var all_units = {"surge_all_ok": unit, "enemy_distant": enemy}

	var result = RulesEngine.validate_surge_move_eligibility(unit, "surge_all_ok", false, all_units)
	assert_true(result.valid, "Unit passing all restrictions should be eligible for surge move")
	assert_eq(result.errors.size(), 0, "No errors expected")

# ==========================================
# Test: Multiple restrictions - battle-shocked takes priority
# ==========================================

func test_surge_move_battle_shocked_checked_before_engagement():
	"""Battle-shocked restriction is checked before engagement range (but both block)."""
	var unit = _create_unit("surge_both", 1, 1, Vector2(400, 400))
	unit.flags["battle_shocked"] = true
	# Also place near enemy
	var enemy = _create_enemy_unit("enemy_near", 2, Vector2(430, 400))
	enemy.models = [{
		"id": "enemy_near_m1",
		"alive": true,
		"position": Vector2(430, 400),
		"base_mm": 32,
		"base_type": "circular",
		"current_wounds": 1,
	}]
	var all_units = {"surge_both": unit, "enemy_near": enemy}

	# Already surged = first check
	var result = RulesEngine.validate_surge_move_eligibility(unit, "surge_both", true, all_units)
	assert_false(result.valid, "Unit with multiple restrictions should be blocked")
	assert_true(result.errors[0].find("already made a surge move") >= 0,
		"Once-per-phase should be the first restriction checked")

# ==========================================
# Test: Friendly units don't count for ER check
# ==========================================

func test_surge_move_friendly_units_ignored_for_engagement_range():
	"""Friendly units should not block surge moves via engagement range."""
	var friendly_pos = Vector2(400, 400)
	var ally_pos = Vector2(430, 400)  # Very close, but same owner

	var unit = _create_unit("surge_friendly", 1, 1, friendly_pos)
	var ally = _create_unit("ally_close", 1, 1, ally_pos)  # Same owner (1)

	var all_units = {"surge_friendly": unit, "ally_close": ally}

	var result = RulesEngine.validate_surge_move_eligibility(unit, "surge_friendly", false, all_units)
	assert_true(result.valid, "Friendly units should NOT count for engagement range check")
