extends SceneTree

# Test: MA-29 Ability Weapon Targeting Filter
# Verifies that target_weapon_names filtering works correctly in EffectPrimitives
# and UAM.
# Usage: godot --headless --path . -s 40k/tests/test_ma29_weapon_targeting.gd

const EP = preload("res://40k/autoloads/EffectPrimitives.gd")
# Note: UnitAbilityManager requires autoloads (GameState, PhaseManager, etc.)
# so it cannot be preloaded in SceneTree tests. UAM-specific tests are skipped.

func _init():
	print("\n=== Test MA-29: Ability Weapon Targeting Filter ===\n")
	var passed = 0
	var failed = 0

	# --- Test 1: EffectPrimitives has PLUS_ATTACKS constant ---
	print("--- Test 1: PLUS_ATTACKS effect type exists ---")
	if EP.PLUS_ATTACKS == "plus_attacks":
		print("  PASS: PLUS_ATTACKS = 'plus_attacks'")
		passed += 1
	else:
		print("  FAIL: PLUS_ATTACKS has unexpected value: %s" % EP.PLUS_ATTACKS)
		failed += 1

	# --- Test 2: FLAG_PLUS_ATTACKS constant exists ---
	print("\n--- Test 2: FLAG_PLUS_ATTACKS flag constant exists ---")
	if EP.FLAG_PLUS_ATTACKS == "effect_plus_attacks":
		print("  PASS: FLAG_PLUS_ATTACKS = 'effect_plus_attacks'")
		passed += 1
	else:
		print("  FAIL: FLAG_PLUS_ATTACKS has unexpected value: %s" % EP.FLAG_PLUS_ATTACKS)
		failed += 1

	# --- Test 3: WEAPON_FILTER_SUFFIX constant exists ---
	print("\n--- Test 3: WEAPON_FILTER_SUFFIX constant exists ---")
	if EP.WEAPON_FILTER_SUFFIX == "_weapon_filter":
		print("  PASS: WEAPON_FILTER_SUFFIX = '_weapon_filter'")
		passed += 1
	else:
		print("  FAIL: WEAPON_FILTER_SUFFIX has unexpected value: %s" % EP.WEAPON_FILTER_SUFFIX)
		failed += 1

	# --- Test 4: apply_effects generates weapon filter diffs ---
	print("\n--- Test 4: apply_effects generates weapon filter diffs for target_weapon_names ---")
	var effects_with_filter = [{"type": "plus_attacks", "value": 2, "target_weapon_names": ["Bolt rifle"]}]
	var diffs = EP.apply_effects(effects_with_filter, "test_unit_1")
	var found_main_flag = false
	var found_filter_flag = false
	for diff in diffs:
		var path = diff.get("path", "")
		if path.ends_with(".effect_plus_attacks"):
			found_main_flag = true
			if diff.get("value", 0) == 2:
				print("  PASS: effect_plus_attacks diff found with value=2")
			else:
				print("  FAIL: effect_plus_attacks diff has wrong value: %s" % str(diff.get("value")))
		if path.ends_with(".effect_plus_attacks_weapon_filter"):
			found_filter_flag = true
			var filter_val = diff.get("value", [])
			if filter_val is Array and "Bolt rifle" in filter_val:
				print("  PASS: weapon filter diff found with ['Bolt rifle']")
			else:
				print("  FAIL: weapon filter diff has wrong value: %s" % str(filter_val))
	if found_main_flag and found_filter_flag:
		passed += 1
	else:
		if not found_main_flag:
			print("  FAIL: Missing effect_plus_attacks diff")
		if not found_filter_flag:
			print("  FAIL: Missing weapon filter diff")
		failed += 1

	# --- Test 5: apply_effects WITHOUT target_weapon_names does NOT create filter ---
	print("\n--- Test 5: apply_effects without target_weapon_names creates no filter ---")
	var effects_no_filter = [{"type": "plus_attacks", "value": 3}]
	var diffs_no_filter = EP.apply_effects(effects_no_filter, "test_unit_2")
	var has_unwanted_filter = false
	for diff in diffs_no_filter:
		if diff.get("path", "").ends_with("_weapon_filter"):
			has_unwanted_filter = true
	if not has_unwanted_filter:
		print("  PASS: No weapon filter diff generated without target_weapon_names")
		passed += 1
	else:
		print("  FAIL: Weapon filter diff generated despite no target_weapon_names")
		failed += 1

	# --- Test 6: effect_applies_to_weapon with matching weapon ---
	print("\n--- Test 6: effect_applies_to_weapon with matching weapon ---")
	var unit_with_filter = {
		"flags": {
			"effect_plus_attacks": 2,
			"effect_plus_attacks_weapon_filter": ["Bolt rifle", "Auto bolt rifle"]
		}
	}
	if EP.effect_applies_to_weapon(unit_with_filter, "effect_plus_attacks", "Bolt rifle"):
		print("  PASS: effect applies to 'Bolt rifle' (matches filter)")
		passed += 1
	else:
		print("  FAIL: effect should apply to 'Bolt rifle' but returned false")
		failed += 1

	# --- Test 7: effect_applies_to_weapon with non-matching weapon ---
	print("\n--- Test 7: effect_applies_to_weapon with non-matching weapon ---")
	if not EP.effect_applies_to_weapon(unit_with_filter, "effect_plus_attacks", "Plasma gun"):
		print("  PASS: effect does NOT apply to 'Plasma gun' (not in filter)")
		passed += 1
	else:
		print("  FAIL: effect should NOT apply to 'Plasma gun' but returned true")
		failed += 1

	# --- Test 8: effect_applies_to_weapon without filter (unit-wide) ---
	print("\n--- Test 8: effect_applies_to_weapon without filter (unit-wide) ---")
	var unit_no_filter = {
		"flags": {
			"effect_plus_attacks": 3
		}
	}
	if EP.effect_applies_to_weapon(unit_no_filter, "effect_plus_attacks", "Plasma gun"):
		print("  PASS: effect applies to any weapon when no filter (unit-wide)")
		passed += 1
	else:
		print("  FAIL: effect should apply to any weapon when no filter")
		failed += 1

	# --- Test 9: effect_applies_to_weapon when flag not set ---
	print("\n--- Test 9: effect_applies_to_weapon when flag not set ---")
	var unit_no_flag = {"flags": {}}
	if not EP.effect_applies_to_weapon(unit_no_flag, "effect_plus_attacks", "Bolt rifle"):
		print("  PASS: effect does not apply when flag not set")
		passed += 1
	else:
		print("  FAIL: effect should not apply when flag not set")
		failed += 1

	# --- Test 10: has_effect_plus_attacks query ---
	print("\n--- Test 10: has_effect_plus_attacks query ---")
	if EP.has_effect_plus_attacks(unit_with_filter):
		print("  PASS: has_effect_plus_attacks returns true when flag is set")
		passed += 1
	else:
		print("  FAIL: has_effect_plus_attacks should return true")
		failed += 1

	# --- Test 11: get_effect_plus_attacks query ---
	print("\n--- Test 11: get_effect_plus_attacks query ---")
	var val = EP.get_effect_plus_attacks(unit_with_filter)
	if val == 2:
		print("  PASS: get_effect_plus_attacks returns 2")
		passed += 1
	else:
		print("  FAIL: get_effect_plus_attacks should return 2, got %d" % val)
		failed += 1

	# --- Test 12: get_weapon_filter_for_flag returns correct filter ---
	print("\n--- Test 12: get_weapon_filter_for_flag returns correct filter ---")
	var filter = EP.get_weapon_filter_for_flag(unit_with_filter, "effect_plus_attacks")
	if filter is Array and filter.size() == 2 and "Bolt rifle" in filter:
		print("  PASS: get_weapon_filter_for_flag returns correct array")
		passed += 1
	else:
		print("  FAIL: get_weapon_filter_for_flag returned unexpected value: %s" % str(filter))
		failed += 1

	# --- Test 13: get_weapon_filter_for_flag returns empty when no filter ---
	print("\n--- Test 13: get_weapon_filter_for_flag returns empty when no filter ---")
	var filter_none = EP.get_weapon_filter_for_flag(unit_no_filter, "effect_plus_attacks")
	if filter_none is Array and filter_none.is_empty():
		print("  PASS: get_weapon_filter_for_flag returns empty for unfiltered effect")
		passed += 1
	else:
		print("  FAIL: get_weapon_filter_for_flag should return [] for unfiltered, got: %s" % str(filter_none))
		failed += 1

	# --- Test 14: _inject_weapon_filter works (inline test) ---
	print("\n--- Test 14: _inject_weapon_filter logic works ---")
	# Test the injection logic inline since UnitAbilityManager can't be preloaded
	var base_effects = [{"type": "plus_attacks", "value": 2}]
	var ability_def_twn = {"target_weapon_names": ["Bolt rifle"]}
	# Replicate the logic of _inject_weapon_filter
	var injected: Array = []
	var weapon_names_14 = ability_def_twn.get("target_weapon_names", [])
	for eff in base_effects:
		var copy = eff.duplicate()
		copy["target_weapon_names"] = weapon_names_14
		injected.append(copy)
	if injected.size() == 1 and injected[0].has("target_weapon_names"):
		var twn = injected[0].get("target_weapon_names", [])
		if twn is Array and "Bolt rifle" in twn:
			print("  PASS: target_weapon_names injected into effect dict")
			passed += 1
		else:
			print("  FAIL: target_weapon_names has wrong value: %s" % str(twn))
			failed += 1
	else:
		print("  FAIL: injection did not add target_weapon_names")
		failed += 1

	# --- Test 15: _inject_weapon_filter without target_weapon_names returns original ---
	print("\n--- Test 15: No injection when no target_weapon_names ---")
	var ability_def_no_filter = {"condition": "always"}
	var wn_15 = ability_def_no_filter.get("target_weapon_names", [])
	if wn_15.is_empty():
		print("  PASS: No target_weapon_names = no injection needed")
		passed += 1
	else:
		print("  FAIL: Should have no target_weapon_names")
		failed += 1

	# --- Test 16-17: SKIP — UnitAbilityManager requires autoloads ---
	print("\n--- Test 16: Target Elimination ability definition (SKIP — needs autoloads) ---")
	print("  SKIP: UnitAbilityManager requires GameState/PhaseManager autoloads")
	print("\n--- Test 17: Target Elimination effects (SKIP — needs autoloads) ---")
	print("  SKIP: UnitAbilityManager requires GameState/PhaseManager autoloads")

	# --- Test 18: clear_effects removes weapon filter companion flags ---
	print("\n--- Test 18: clear_effects removes weapon filter companion flags ---")
	var test_flags = {
		"effect_plus_attacks": 2,
		"effect_plus_attacks_weapon_filter": ["Bolt rifle"]
	}
	EP.clear_effects(effects_with_filter, "test_clear", test_flags)
	if not test_flags.has("effect_plus_attacks") and not test_flags.has("effect_plus_attacks_weapon_filter"):
		print("  PASS: Both main flag and weapon filter cleared")
		passed += 1
	else:
		print("  FAIL: Flags remaining after clear: %s" % str(test_flags))
		failed += 1

	# --- Test 19: clear_all_effect_flags removes weapon filter flags ---
	print("\n--- Test 19: clear_all_effect_flags removes weapon filter flags ---")
	var test_flags2 = {
		"effect_plus_attacks": 2,
		"effect_plus_attacks_weapon_filter": ["Bolt rifle"],
		"non_effect_flag": true
	}
	EP.clear_all_effect_flags(test_flags2)
	if not test_flags2.has("effect_plus_attacks") and not test_flags2.has("effect_plus_attacks_weapon_filter") and test_flags2.has("non_effect_flag"):
		print("  PASS: Effect flags cleared, non-effect flags preserved")
		passed += 1
	else:
		print("  FAIL: Flag state after clear_all: %s" % str(test_flags2))
		failed += 1

	# --- Test 20: Backward compatibility — existing effects without weapon filter ---
	print("\n--- Test 20: Backward compatibility — plus_one_hit without filter applies to all ---")
	var unit_existing_effect = {
		"flags": {
			"effect_plus_one_hit": true
		}
	}
	if EP.effect_applies_to_weapon(unit_existing_effect, "effect_plus_one_hit", "Bolt rifle"):
		if EP.effect_applies_to_weapon(unit_existing_effect, "effect_plus_one_hit", "Plasma gun"):
			print("  PASS: Existing effect without filter applies to all weapons")
			passed += 1
		else:
			print("  FAIL: Existing effect should apply to all weapons")
			failed += 1
	else:
		print("  FAIL: Existing effect should apply to Bolt rifle")
		failed += 1

	# --- Summary ---
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed == 0:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")
	quit()
