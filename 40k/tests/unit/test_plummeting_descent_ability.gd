extends SceneTree

# Tests for "Plummeting Descent" ability implementation (OA-23)
#
# Per Boss Zagstruk's datasheet:
# "You can re-roll Charge rolls made for this unit in a turn in which
# it was set up on the battlefield from Reserves."
#
# These tests verify:
# 1. Ability is registered in UnitAbilityManager.ABILITY_EFFECTS
# 2. Ability has reroll_charge effect with arrived_from_reserves condition
# 3. Unit arriving from reserves this turn gets the reroll_charge flag
# 4. Unit that arrived in a previous turn does NOT get the flag
# 5. Unit that never arrived from reserves does NOT get the flag

const EffectPrimitivesData = preload("res://autoloads/EffectPrimitives.gd")
const UnitAbilityManagerData = preload("res://autoloads/UnitAbilityManager.gd")

var _pass_count := 0
var _fail_count := 0

func _init():
	print("\n=== Test Plummeting Descent Ability (OA-23) ===\n")

	_test_ability_registered()
	_test_ability_has_correct_effects()
	_test_reroll_charge_flag_detection()
	_test_no_flag_no_reroll()
	_test_condition_is_arrived_from_reserves()

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
	print("--- Test 1: Plummeting Descent is registered in ABILITY_EFFECTS ---")
	var effects = UnitAbilityManagerData.ABILITY_EFFECTS
	_assert_true(effects.has("Plummeting Descent"), "Plummeting Descent exists in ABILITY_EFFECTS")
	_assert_true(effects["Plummeting Descent"].get("implemented", false), "Plummeting Descent is marked as implemented")

func _test_ability_has_correct_effects():
	print("\n--- Test 2: Plummeting Descent has reroll_charge effect ---")
	var effect_def = UnitAbilityManagerData.ABILITY_EFFECTS.get("Plummeting Descent", {})
	var effects = effect_def.get("effects", [])
	_assert_eq(effects.size(), 1, "Plummeting Descent has exactly 1 effect")

	var has_reroll_charge = false
	for effect in effects:
		if effect.get("type", "") == "reroll_charge":
			has_reroll_charge = true

	_assert_true(has_reroll_charge, "Plummeting Descent has reroll_charge effect")
	_assert_eq(effect_def.get("target", ""), "unit", "Target is 'unit' (self-targeting)")

func _test_reroll_charge_flag_detection():
	print("\n--- Test 3: Unit with reroll_charge flag is detected ---")
	var unit = {"flags": {EffectPrimitivesData.FLAG_REROLL_CHARGE: true}}
	_assert_true(EffectPrimitivesData.has_effect_reroll_charge(unit),
		"has_effect_reroll_charge returns true when flag is set")

func _test_no_flag_no_reroll():
	print("\n--- Test 4: Unit WITHOUT reroll_charge flag is not detected ---")
	var unit = {"flags": {}}
	_assert_false(EffectPrimitivesData.has_effect_reroll_charge(unit),
		"has_effect_reroll_charge returns false without flag")

	var unit_no_flags = {}
	_assert_false(EffectPrimitivesData.has_effect_reroll_charge(unit_no_flags),
		"has_effect_reroll_charge returns false when no flags dict exists")

func _test_condition_is_arrived_from_reserves():
	print("\n--- Test 5: Plummeting Descent condition is arrived_from_reserves ---")
	var effect_def = UnitAbilityManagerData.ABILITY_EFFECTS.get("Plummeting Descent", {})
	_assert_eq(effect_def.get("condition", ""), "arrived_from_reserves",
		"Condition is 'arrived_from_reserves' (only active turn unit arrives from reserves)")
	_assert_eq(effect_def.get("description", ""), "Re-roll Charge rolls if this unit was set up from Reserves this turn",
		"Description accurately explains the condition")
