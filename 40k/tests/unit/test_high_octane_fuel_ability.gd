extends SceneTree

# Tests for "High-octane Fuel" ability implementation (OA-22)
#
# Per Warhammer 40k 10th Edition Warboss On Warbike datasheet:
# "Each time this model's unit Advances, do not make an Advance roll
# for it. Instead, until the end of the phase, add 6" to the Move
# characteristic of models in this model's unit."
#
# These tests verify:
# 1. Ability is registered in UnitAbilityManager.ABILITY_EFFECTS
# 2. Ability has correct flat_advance effect
# 3. Effect flag correctly indicates flat advance
# 4. Units without the flag do NOT get flat advance
# 5. Fuel-mixa Grot (Deffkilla Wartrike) has same effect
# 6. Deffkilla Wartrike army data has Fuel-mixa Grot ability
# 7. Condition is "while_leading" (applies when leading a unit)

const EffectPrimitivesData = preload("res://autoloads/EffectPrimitives.gd")
const UnitAbilityManagerData = preload("res://autoloads/UnitAbilityManager.gd")

var _pass_count := 0
var _fail_count := 0

func _init():
	print("\n=== Test High-octane Fuel Ability (OA-22) ===\n")

	_test_ability_registered()
	_test_ability_has_correct_effects()
	_test_flat_advance_flag()
	_test_no_flag_no_flat_advance()
	_test_fuel_mixa_grot_same_effect()
	_test_wartrike_army_data()
	_test_condition_while_leading()

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
	print("--- Test 1: High-octane Fuel is registered in ABILITY_EFFECTS ---")
	var effects = UnitAbilityManagerData.ABILITY_EFFECTS
	_assert_true(effects.has("High-octane Fuel"), "High-octane Fuel exists in ABILITY_EFFECTS")
	_assert_true(effects["High-octane Fuel"].get("implemented", false), "High-octane Fuel is marked as implemented")

func _test_ability_has_correct_effects():
	print("\n--- Test 2: High-octane Fuel has flat_advance effect ---")
	var effect_def = UnitAbilityManagerData.ABILITY_EFFECTS.get("High-octane Fuel", {})
	var effects = effect_def.get("effects", [])
	_assert_eq(effects.size(), 1, "High-octane Fuel has exactly 1 effect")

	var has_flat_advance = false
	for effect in effects:
		if effect.get("type", "") == "flat_advance":
			has_flat_advance = true

	_assert_true(has_flat_advance, "High-octane Fuel has flat_advance effect")

func _test_flat_advance_flag():
	print("\n--- Test 3: Unit with flat_advance flag gets flat advance ---")
	var unit = {"flags": {EffectPrimitivesData.FLAG_FLAT_ADVANCE: true}}
	_assert_true(EffectPrimitivesData.has_effect_flat_advance(unit),
		"has_effect_flat_advance returns true when flag is set")

func _test_no_flag_no_flat_advance():
	print("\n--- Test 4: Unit WITHOUT flat_advance flag does NOT get flat advance ---")
	var unit = {"flags": {}}
	_assert_false(EffectPrimitivesData.has_effect_flat_advance(unit),
		"has_effect_flat_advance returns false without flag")
	# Also test with no flags dict at all
	var unit_no_flags = {}
	_assert_false(EffectPrimitivesData.has_effect_flat_advance(unit_no_flags),
		"has_effect_flat_advance returns false when no flags dict exists")

func _test_fuel_mixa_grot_same_effect():
	print("\n--- Test 5: Fuel-mixa Grot (Deffkilla Wartrike) has same flat_advance effect ---")
	var effects = UnitAbilityManagerData.ABILITY_EFFECTS
	_assert_true(effects.has("Fuel-mixa Grot"), "Fuel-mixa Grot exists in ABILITY_EFFECTS")
	_assert_true(effects["Fuel-mixa Grot"].get("implemented", false), "Fuel-mixa Grot is marked as implemented")

	var fuel_mixa_effects = effects["Fuel-mixa Grot"].get("effects", [])
	var has_flat_advance = false
	for effect in fuel_mixa_effects:
		if effect.get("type", "") == "flat_advance":
			has_flat_advance = true
	_assert_true(has_flat_advance, "Fuel-mixa Grot has flat_advance effect")

func _test_wartrike_army_data():
	print("\n--- Test 6: Deffkilla Wartrike army JSON has Fuel-mixa Grot ability ---")
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
	var units = army_data.get("units", {})
	var found_wartrike = false
	var has_fuel_mixa = false

	for unit_id in units:
		var unit = units[unit_id]
		var meta = unit.get("meta", {})
		if meta.get("name", "") == "Deffkilla Wartrike":
			found_wartrike = true
			var abilities = meta.get("abilities", [])
			for ability in abilities:
				if ability.get("name", "") == "Fuel-mixa Grot":
					has_fuel_mixa = true
					break
			break

	_assert_true(found_wartrike, "Deffkilla Wartrike unit found in Orks_2000.json")
	_assert_true(has_fuel_mixa, "Deffkilla Wartrike has Fuel-mixa Grot ability in army data")

func _test_condition_while_leading():
	print("\n--- Test 7: High-octane Fuel condition is 'while_leading' ---")
	var effect_def = UnitAbilityManagerData.ABILITY_EFFECTS.get("High-octane Fuel", {})
	_assert_eq(effect_def.get("condition", ""), "while_leading", "Condition is 'while_leading'")
	_assert_eq(effect_def.get("target", ""), "led_unit", "Target is 'led_unit'")
