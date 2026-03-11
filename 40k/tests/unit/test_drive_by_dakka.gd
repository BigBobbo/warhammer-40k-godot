extends "res://addons/gut/test.gd"

# Tests for the DRIVE-BY DAKKA ability implementation (OA-13)
#
# Per Warhammer 40k 10th Edition rules:
# Each time a model in this unit makes a ranged attack that targets a unit
# within 9", improve the Armour Penetration characteristic of that attack by 1.
#
# Applies to: Warbikers, Wartrakks
#
# These tests verify:
# 1. has_drive_by_dakka() correctly detects the ability
# 2. is_target_within_range_inches() checks distance correctly
# 3. get_drive_by_dakka_ap_bonus() returns correct AP bonus
# 4. Dead models are skipped in distance checks
# 5. Ability is in UnitAbilityManager.ABILITY_EFFECTS

var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

# ==========================================
# has_drive_by_dakka() Tests
# ==========================================

func test_has_drive_by_dakka_dict_format():
	"""Drive-by Dakka as a dictionary ability should be detected."""
	var unit = {
		"meta": {
			"abilities": [{"name": "Drive-by Dakka", "type": "Datasheet", "description": "..."}]
		}
	}
	assert_true(rules_engine.has_drive_by_dakka(unit), "Should detect Drive-by Dakka as dictionary ability")

func test_has_drive_by_dakka_string_format():
	"""Drive-by Dakka as a simple string should be detected."""
	var unit = {
		"meta": {
			"abilities": ["Drive-by Dakka"]
		}
	}
	assert_true(rules_engine.has_drive_by_dakka(unit), "Should detect Drive-by Dakka as string ability")

func test_has_drive_by_dakka_returns_false_without_ability():
	"""Unit without Drive-by Dakka should return false."""
	var unit = {
		"meta": {
			"abilities": [{"name": "Ramshackle", "type": "Datasheet"}]
		}
	}
	assert_false(rules_engine.has_drive_by_dakka(unit), "Should not detect Drive-by Dakka when absent")

func test_has_drive_by_dakka_returns_false_empty_abilities():
	"""Unit with empty abilities should return false."""
	var unit = {"meta": {"abilities": []}}
	assert_false(rules_engine.has_drive_by_dakka(unit), "Should return false for empty abilities")

func test_has_drive_by_dakka_returns_false_no_meta():
	"""Unit with no meta should return false."""
	var unit = {}
	assert_false(rules_engine.has_drive_by_dakka(unit), "Should return false for unit with no meta")

# ==========================================
# is_target_within_range_inches() Tests
# ==========================================

func test_target_within_9_inches():
	"""Target at ~4.37\" should be within 9\"."""
	# 200px apart with 32mm bases. PX_PER_INCH = 40.0, base radius ~0.63"
	# Edge-to-edge: 200/40 - 2*0.63 = 5.0 - 1.26 = 3.74"
	var attacker = {"models": [
		{"alive": true, "position": Vector2(0, 0), "base_mm": 32}
	]}
	var target = {"models": [
		{"alive": true, "position": Vector2(200, 0), "base_mm": 32}
	]}
	assert_true(rules_engine.is_target_within_range_inches(attacker, target, 9.0),
		"Target ~3.74\" away should be within 9\"")

func test_target_beyond_9_inches():
	"""Target at ~14.37\" should be beyond 9\"."""
	# 600px apart with 32mm bases
	# Edge-to-edge: 600/40 - 1.26 = 13.74"
	var attacker = {"models": [
		{"alive": true, "position": Vector2(0, 0), "base_mm": 32}
	]}
	var target = {"models": [
		{"alive": true, "position": Vector2(600, 0), "base_mm": 32}
	]}
	assert_false(rules_engine.is_target_within_range_inches(attacker, target, 9.0),
		"Target ~13.74\" away should be beyond 9\"")

func test_dead_attacker_models_skipped():
	"""Dead attacker models should not count for distance check."""
	var attacker = {"models": [
		{"alive": false, "position": Vector2(0, 0), "base_mm": 32}
	]}
	var target = {"models": [
		{"alive": true, "position": Vector2(200, 0), "base_mm": 32}
	]}
	assert_false(rules_engine.is_target_within_range_inches(attacker, target, 9.0),
		"Dead attacker model should not be used in distance check")

func test_dead_target_models_skipped():
	"""Dead target models should not count for distance check."""
	var attacker = {"models": [
		{"alive": true, "position": Vector2(0, 0), "base_mm": 32}
	]}
	var target = {"models": [
		{"alive": false, "position": Vector2(200, 0), "base_mm": 32}
	]}
	assert_false(rules_engine.is_target_within_range_inches(attacker, target, 9.0),
		"Dead target model should not be used in distance check")

func test_multiple_models_closest_within_range():
	"""If ANY attacker model is within range of ANY target model, returns true."""
	var attacker = {"models": [
		{"alive": true, "position": Vector2(0, 0), "base_mm": 32},
		{"alive": true, "position": Vector2(800, 0), "base_mm": 32}  # Far away
	]}
	var target = {"models": [
		{"alive": true, "position": Vector2(200, 0), "base_mm": 32}  # Close to first attacker
	]}
	assert_true(rules_engine.is_target_within_range_inches(attacker, target, 9.0),
		"Should return true if at least one model pair is within range")

# ==========================================
# get_drive_by_dakka_ap_bonus() Tests
# ==========================================

func test_ap_bonus_within_9_inches():
	"""Should return 1 AP bonus when attacker has ability and target within 9\"."""
	var attacker = {"meta": {"abilities": [{"name": "Drive-by Dakka"}]}, "models": [
		{"alive": true, "position": Vector2(0, 0), "base_mm": 32}
	]}
	var target = {"models": [
		{"alive": true, "position": Vector2(200, 0), "base_mm": 32}
	]}
	assert_eq(rules_engine.get_drive_by_dakka_ap_bonus(attacker, target), 1,
		"AP bonus should be 1 within 9\"")

func test_no_ap_bonus_beyond_9_inches():
	"""Should return 0 AP bonus when target is beyond 9\"."""
	var attacker = {"meta": {"abilities": [{"name": "Drive-by Dakka"}]}, "models": [
		{"alive": true, "position": Vector2(0, 0), "base_mm": 32}
	]}
	var target = {"models": [
		{"alive": true, "position": Vector2(600, 0), "base_mm": 32}
	]}
	assert_eq(rules_engine.get_drive_by_dakka_ap_bonus(attacker, target), 0,
		"AP bonus should be 0 beyond 9\"")

func test_no_ap_bonus_without_ability():
	"""Should return 0 AP bonus when attacker doesn't have Drive-by Dakka."""
	var attacker = {"meta": {"abilities": []}, "models": [
		{"alive": true, "position": Vector2(0, 0), "base_mm": 32}
	]}
	var target = {"models": [
		{"alive": true, "position": Vector2(200, 0), "base_mm": 32}
	]}
	assert_eq(rules_engine.get_drive_by_dakka_ap_bonus(attacker, target), 0,
		"AP bonus should be 0 without ability")

# ==========================================
# UnitAbilityManager Integration Tests
# ==========================================

func test_ability_in_effects_dictionary():
	"""Drive-by Dakka should be registered in ABILITY_EFFECTS."""
	var effects = UnitAbilityManager.ABILITY_EFFECTS
	assert_true(effects.has("Drive-by Dakka"), "Drive-by Dakka should be in ABILITY_EFFECTS")

func test_ability_marked_implemented():
	"""Drive-by Dakka should be marked as implemented."""
	var effects = UnitAbilityManager.ABILITY_EFFECTS
	var entry = effects.get("Drive-by Dakka", {})
	assert_true(entry.get("implemented", false), "Drive-by Dakka should be marked as implemented")

func test_ability_is_ranged_only():
	"""Drive-by Dakka should be ranged attack type only."""
	var effects = UnitAbilityManager.ABILITY_EFFECTS
	var entry = effects.get("Drive-by Dakka", {})
	assert_eq(entry.get("attack_type", ""), "ranged", "Drive-by Dakka should be ranged only")

func test_ability_has_improve_ap_effect():
	"""Drive-by Dakka should have improve_ap effect."""
	var effects = UnitAbilityManager.ABILITY_EFFECTS
	var entry = effects.get("Drive-by Dakka", {})
	var effect_list = entry.get("effects", [])
	assert_true(effect_list.size() > 0, "Should have at least one effect")
	assert_eq(effect_list[0].get("type", ""), "improve_ap", "First effect should be improve_ap")
	assert_eq(effect_list[0].get("value", 0), 1, "AP improvement should be 1")
