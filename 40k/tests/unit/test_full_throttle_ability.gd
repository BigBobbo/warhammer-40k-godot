extends SceneTree

# Tests for "Full Throttle" ability implementation (OA-21)
#
# Per Warhammer 40k 10th Edition Stormboyz datasheet:
# "This unit is eligible to declare a charge in a turn in which it
# Advanced or Fell Back."
#
# These tests verify:
# 1. Ability is registered in UnitAbilityManager.ABILITY_EFFECTS
# 2. Ability has both advance_and_charge and fall_back_and_charge effects
# 3. Effect flags allow charging after advancing/falling back
# 4. Units without the flags cannot charge after advancing/falling back
# 5. Stormboyz army data has the Full Throttle ability

const EffectPrimitivesData = preload("res://autoloads/EffectPrimitives.gd")
const UnitAbilityManagerData = preload("res://autoloads/UnitAbilityManager.gd")

var _pass_count := 0
var _fail_count := 0

func _init():
	print("\n=== Test Full Throttle Ability (OA-21) ===\n")

	_test_ability_registered()
	_test_ability_has_correct_effects()
	_test_advance_and_charge_flag()
	_test_fall_back_and_charge_flag()
	_test_no_flags_denies_charge()
	_test_stormboyz_army_data()

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	if _fail_count == 0:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")
	quit()

# ==========================================
# Assertion helpers
# ==========================================

func _assert_true(condition: bool, msg: String) -> void:
	if condition:
		_pass_count += 1
		print("  PASS: %s" % msg)
	else:
		_fail_count += 1
		print("  FAIL: %s" % msg)

func _assert_false(condition: bool, msg: String) -> void:
	_assert_true(not condition, msg)

func _assert_eq(a, b, msg: String) -> void:
	if a == b:
		_pass_count += 1
		print("  PASS: %s" % msg)
	else:
		_fail_count += 1
		print("  FAIL: %s (expected %s, got %s)" % [msg, str(b), str(a)])

# ==========================================
# Tests
# ==========================================

func _test_ability_registered():
	print("--- Test 1: Full Throttle is registered in ABILITY_EFFECTS ---")
	var effects = UnitAbilityManagerData.ABILITY_EFFECTS
	_assert_true(effects.has("Full Throttle"), "Full Throttle exists in ABILITY_EFFECTS")
	_assert_true(effects["Full Throttle"].get("implemented", false), "Full Throttle is marked as implemented")

func _test_ability_has_correct_effects():
	print("\n--- Test 2: Full Throttle has advance_and_charge and fall_back_and_charge effects ---")
	var effect_def = UnitAbilityManagerData.ABILITY_EFFECTS.get("Full Throttle", {})
	var effects = effect_def.get("effects", [])
	_assert_eq(effects.size(), 2, "Full Throttle has exactly 2 effects")

	var has_advance_charge = false
	var has_fall_back_charge = false
	for effect in effects:
		if effect.get("type", "") == "advance_and_charge":
			has_advance_charge = true
		if effect.get("type", "") == "fall_back_and_charge":
			has_fall_back_charge = true

	_assert_true(has_advance_charge, "Full Throttle has advance_and_charge effect")
	_assert_true(has_fall_back_charge, "Full Throttle has fall_back_and_charge effect")
	_assert_eq(effect_def.get("condition", ""), "always", "Condition is 'always' (self-applied)")
	_assert_eq(effect_def.get("target", ""), "unit", "Target is 'unit' (self-targeting)")

func _test_advance_and_charge_flag():
	print("\n--- Test 3: Unit with advance_and_charge flag can charge after advancing ---")
	var unit = {"flags": {EffectPrimitivesData.FLAG_ADVANCE_AND_CHARGE: true, "advanced": true}}
	_assert_true(EffectPrimitivesData.has_effect_advance_and_charge(unit),
		"has_effect_advance_and_charge returns true when flag is set")

func _test_fall_back_and_charge_flag():
	print("\n--- Test 4: Unit with fall_back_and_charge flag can charge after falling back ---")
	var unit = {"flags": {EffectPrimitivesData.FLAG_FALL_BACK_AND_CHARGE: true, "fell_back": true}}
	_assert_true(EffectPrimitivesData.has_effect_fall_back_and_charge(unit),
		"has_effect_fall_back_and_charge returns true when flag is set")

func _test_no_flags_denies_charge():
	print("\n--- Test 5: Unit WITHOUT flags cannot charge after advancing/falling back ---")
	var unit = {"flags": {"advanced": true}}
	_assert_false(EffectPrimitivesData.has_effect_advance_and_charge(unit),
		"has_effect_advance_and_charge returns false without flag")
	_assert_false(EffectPrimitivesData.has_effect_fall_back_and_charge(unit),
		"has_effect_fall_back_and_charge returns false without flag")

func _test_stormboyz_army_data():
	print("\n--- Test 6: Stormboyz army JSON has Full Throttle ability ---")
	var file = FileAccess.open("res://armies/Orks_2000.json", FileAccess.READ)
	if file == null:
		_fail_count += 1
		print("  FAIL: Could not open Orks_2000.json")
		return

	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		_fail_count += 1
		print("  FAIL: Could not parse Orks_2000.json")
		return

	var army_data = json.data
	if army_data is not Dictionary:
		_fail_count += 1
		print("  FAIL: Army data is not a Dictionary")
		return
	var units = army_data.get("units", [])
	var found_stormboyz = false
	var has_full_throttle = false

	for unit in units:
		var meta = unit.get("meta", {})
		if meta.get("name", "") == "Stormboyz":
			found_stormboyz = true
			var abilities = meta.get("abilities", [])
			for ability in abilities:
				if ability.get("name", "") == "Full Throttle":
					has_full_throttle = true
					break
			break

	_assert_true(found_stormboyz, "Stormboyz unit found in Orks_2000.json")
	_assert_true(has_full_throttle, "Stormboyz has Full Throttle ability in army data")
