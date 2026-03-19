extends "res://addons/gut/test.gd"

# Tests for the UNIFIED RANGE-CONDITIONAL ABILITY RESOLVER
#
# UnitAbilityManager.resolve_ranged_ability_bonuses() is a generic resolver that
# replaces hardcoded per-ability functions (get_drive_by_dakka_ap_bonus,
# get_wall_of_dakka_hit_bonus) with a data-driven approach.
#
# It scans unit abilities, looks each up in ABILITY_EFFECTS, checks range
# conditions (target_within_range, target_within_half_range), and returns
# aggregated bonuses.
#
# These tests verify:
# 1. Drive-by Dakka AP bonus via the unified resolver
# 2. Wall of Dakka hit bonus via the unified resolver
# 3. Multiple abilities stacking correctly
# 4. Conditions not met return zero bonuses
# 5. Unimplemented abilities are skipped
# 6. Dead model handling in range checks

var ability_manager: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	ability_manager = AutoloadHelper.get_unit_ability_manager()
	assert_not_null(ability_manager, "UnitAbilityManager autoload must be available")

# ==========================================
# Helper: Create unit with abilities and positioned models
# ==========================================

func _make_unit(abilities: Array, model_positions: Array = [Vector2(0, 0)], base_mm: int = 32) -> Dictionary:
	var models = []
	for pos in model_positions:
		models.append({"alive": true, "position": pos, "base_mm": base_mm})
	return {
		"meta": {"abilities": abilities},
		"models": models
	}

func _make_weapon(weapon_range: int = 18, ap: int = 0) -> Dictionary:
	return {
		"name": "Test Weapon",
		"range": weapon_range,
		"attacks": 3,
		"strength": 5,
		"ap": ap,
		"damage": 1,
		"ballistic_skill": 5
	}

# ==========================================
# Drive-by Dakka (target_within_range) Tests
# ==========================================

func test_drive_by_dakka_ap_bonus_within_range():
	"""Drive-by Dakka should give +1 AP when target within 9\"."""
	# 200px apart with 32mm bases → ~3.74\" edge-to-edge (well within 9\")
	var actor = _make_unit([{"name": "Drive-by Dakka", "type": "Datasheet"}], [Vector2(0, 0)])
	var target = _make_unit([], [Vector2(200, 0)])
	var weapon = _make_weapon()
	var result = UnitAbilityManager.resolve_ranged_ability_bonuses(actor, target, weapon)
	assert_eq(result.ap_bonus, 1, "Drive-by Dakka should give +1 AP within 9\"")
	assert_true("Drive-by Dakka" in result.abilities_applied, "Should list Drive-by Dakka as applied")

func test_drive_by_dakka_no_bonus_beyond_range():
	"""Drive-by Dakka should give 0 AP when target beyond 9\"."""
	# 500px apart with 32mm bases → ~11.24\" edge-to-edge (beyond 9\")
	var actor = _make_unit([{"name": "Drive-by Dakka", "type": "Datasheet"}], [Vector2(0, 0)])
	var target = _make_unit([], [Vector2(500, 0)])
	var weapon = _make_weapon()
	var result = UnitAbilityManager.resolve_ranged_ability_bonuses(actor, target, weapon)
	assert_eq(result.ap_bonus, 0, "Drive-by Dakka should give 0 AP beyond 9\"")
	assert_eq(result.abilities_applied.size(), 0, "No abilities should be listed")

func test_drive_by_dakka_string_format():
	"""Drive-by Dakka as a string ability name should work."""
	var actor = _make_unit(["Drive-by Dakka"], [Vector2(0, 0)])
	var target = _make_unit([], [Vector2(200, 0)])
	var weapon = _make_weapon()
	var result = UnitAbilityManager.resolve_ranged_ability_bonuses(actor, target, weapon)
	assert_eq(result.ap_bonus, 1, "String format ability should resolve correctly")

# ==========================================
# Wall of Dakka (target_within_half_range) Tests
# ==========================================

func test_wall_of_dakka_hit_bonus_within_half_range():
	"""Wall of Dakka should give +1 hit when target within half weapon range."""
	# Weapon range 24\", half = 12\". 200px / 40 = 5\" center-to-center, well within 12\"
	var actor = _make_unit([{"name": "Wall of Dakka", "type": "Datasheet"}], [Vector2(0, 0)])
	var target = _make_unit([], [Vector2(200, 0)])
	var weapon = _make_weapon(24)
	var result = UnitAbilityManager.resolve_ranged_ability_bonuses(actor, target, weapon)
	assert_eq(result.hit_bonus, 1, "Wall of Dakka should give +1 hit within half range")
	assert_true("Wall of Dakka" in result.abilities_applied, "Should list Wall of Dakka as applied")

func test_wall_of_dakka_no_bonus_beyond_half_range():
	"""Wall of Dakka should give 0 hit when target beyond half weapon range."""
	# Weapon range 18\", half = 9\". 500px / 40 = 12.5\" center, well beyond 9\"
	var actor = _make_unit([{"name": "Wall of Dakka", "type": "Datasheet"}], [Vector2(0, 0)])
	var target = _make_unit([], [Vector2(500, 0)])
	var weapon = _make_weapon(18)
	var result = UnitAbilityManager.resolve_ranged_ability_bonuses(actor, target, weapon)
	assert_eq(result.hit_bonus, 0, "Wall of Dakka should give 0 hit beyond half range")

# ==========================================
# Multiple Abilities Stacking Tests
# ==========================================

func test_both_abilities_stack():
	"""Unit with both Drive-by Dakka and Wall of Dakka should get both bonuses."""
	# Within both 9\" and half of 24\" (12\")
	var actor = _make_unit([
		{"name": "Drive-by Dakka", "type": "Datasheet"},
		{"name": "Wall of Dakka", "type": "Datasheet"}
	], [Vector2(0, 0)])
	var target = _make_unit([], [Vector2(200, 0)])
	var weapon = _make_weapon(24)
	var result = UnitAbilityManager.resolve_ranged_ability_bonuses(actor, target, weapon)
	assert_eq(result.ap_bonus, 1, "Should get AP bonus from Drive-by Dakka")
	assert_eq(result.hit_bonus, 1, "Should get hit bonus from Wall of Dakka")
	assert_eq(result.abilities_applied.size(), 2, "Both abilities should be listed")

# ==========================================
# Edge Cases
# ==========================================

func test_no_abilities_returns_zero():
	"""Unit with no abilities should return zero bonuses."""
	var actor = _make_unit([], [Vector2(0, 0)])
	var target = _make_unit([], [Vector2(200, 0)])
	var weapon = _make_weapon()
	var result = UnitAbilityManager.resolve_ranged_ability_bonuses(actor, target, weapon)
	assert_eq(result.ap_bonus, 0, "No abilities means 0 AP bonus")
	assert_eq(result.hit_bonus, 0, "No abilities means 0 hit bonus")
	assert_eq(result.abilities_applied.size(), 0, "No abilities applied")

func test_unimplemented_ability_skipped():
	"""Abilities marked as not implemented should be skipped."""
	# "Supa-kannon" is in ABILITY_EFFECTS with implemented: false
	var actor = _make_unit([{"name": "Supa-kannon", "type": "Datasheet"}], [Vector2(0, 0)])
	var target = _make_unit([], [Vector2(200, 0)])
	var weapon = _make_weapon()
	var result = UnitAbilityManager.resolve_ranged_ability_bonuses(actor, target, weapon)
	assert_eq(result.ap_bonus, 0, "Unimplemented abilities should give no bonus")
	assert_eq(result.hit_bonus, 0, "Unimplemented abilities should give no bonus")

func test_melee_only_ability_skipped_for_ranged():
	"""Abilities with attack_type 'melee' should not apply to ranged resolution."""
	var actor = _make_unit([{"name": "Might is Right", "type": "Leader"}], [Vector2(0, 0)])
	var target = _make_unit([], [Vector2(200, 0)])
	var weapon = _make_weapon()
	var result = UnitAbilityManager.resolve_ranged_ability_bonuses(actor, target, weapon)
	assert_eq(result.ap_bonus, 0, "Melee-only abilities should not apply to ranged")
	assert_eq(result.hit_bonus, 0, "Melee-only abilities should not apply to ranged")

func test_dead_attacker_models_skipped():
	"""Dead models in attacker unit should be excluded from range checks."""
	var actor = {
		"meta": {"abilities": [{"name": "Drive-by Dakka", "type": "Datasheet"}]},
		"models": [
			{"alive": false, "position": Vector2(0, 0), "base_mm": 32},
			{"alive": true, "position": Vector2(500, 0), "base_mm": 32}  # Only alive model is far
		]
	}
	var target = _make_unit([], [Vector2(50, 0)])  # Close to dead model but far from alive
	var weapon = _make_weapon()
	var result = UnitAbilityManager.resolve_ranged_ability_bonuses(actor, target, weapon)
	assert_eq(result.ap_bonus, 0, "Dead models should not count for range check")

func test_dead_target_models_skipped():
	"""Dead models in target unit should be excluded from range checks."""
	var actor = _make_unit([{"name": "Drive-by Dakka", "type": "Datasheet"}], [Vector2(0, 0)])
	var target = {
		"meta": {"abilities": []},
		"models": [
			{"alive": false, "position": Vector2(100, 0), "base_mm": 32},
			{"alive": true, "position": Vector2(500, 0), "base_mm": 32}  # Only alive model is far
		]
	}
	var weapon = _make_weapon()
	var result = UnitAbilityManager.resolve_ranged_ability_bonuses(actor, target, weapon)
	assert_eq(result.ap_bonus, 0, "Dead target models should not count for range check")

func test_no_weapon_profile_for_half_range():
	"""Wall of Dakka with empty weapon profile should give no bonus."""
	var actor = _make_unit([{"name": "Wall of Dakka", "type": "Datasheet"}], [Vector2(0, 0)])
	var target = _make_unit([], [Vector2(200, 0)])
	var result = UnitAbilityManager.resolve_ranged_ability_bonuses(actor, target, {})
	assert_eq(result.hit_bonus, 0, "No weapon profile means no half-range check possible")

func test_melee_weapon_ignored_for_half_range():
	"""Wall of Dakka with melee weapon should give no bonus."""
	var actor = _make_unit([{"name": "Wall of Dakka", "type": "Datasheet"}], [Vector2(0, 0)])
	var target = _make_unit([], [Vector2(200, 0)])
	var weapon = {"name": "Choppa", "range": "Melee", "attacks": 3, "strength": 4, "ap": 0, "damage": 1}
	var result = UnitAbilityManager.resolve_ranged_ability_bonuses(actor, target, weapon)
	assert_eq(result.hit_bonus, 0, "Melee weapons should not trigger half-range check")

# ==========================================
# Static helper tests
# ==========================================

func test_extract_ability_name_from_string():
	"""Static name extraction should work for string format."""
	assert_eq(UnitAbilityManager._extract_ability_name_static("Drive-by Dakka"), "Drive-by Dakka")

func test_extract_ability_name_from_dict():
	"""Static name extraction should work for dictionary format."""
	assert_eq(UnitAbilityManager._extract_ability_name_static({"name": "Wall of Dakka"}), "Wall of Dakka")

func test_extract_ability_name_from_empty():
	"""Static name extraction should return empty for invalid input."""
	assert_eq(UnitAbilityManager._extract_ability_name_static(42), "")

func test_is_target_in_range_static_within():
	"""Static range check should return true when models are within range."""
	var actor = _make_unit([], [Vector2(0, 0)])
	var target = _make_unit([], [Vector2(200, 0)])
	# 200px / 40 = 5\" center-to-center, minus base radii ≈ 3.74\" edge-to-edge
	assert_true(UnitAbilityManager._is_target_in_range_static(actor, target, 9.0))

func test_is_target_in_range_static_beyond():
	"""Static range check should return false when models are beyond range."""
	var actor = _make_unit([], [Vector2(0, 0)])
	var target = _make_unit([], [Vector2(500, 0)])
	# 500px / 40 = 12.5\" center-to-center, well beyond 9\"
	assert_true(not UnitAbilityManager._is_target_in_range_static(actor, target, 5.0))
