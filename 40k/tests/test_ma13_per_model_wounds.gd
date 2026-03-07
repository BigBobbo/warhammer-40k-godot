extends SceneTree

# Test: MA-13 Per-model wounds from stats_override
# Verifies that:
# 1. stats_override.wounds sets model max wounds correctly at load time
# 2. Mismatched JSON wounds are corrected by _apply_model_profile_wounds
# 3. Wargear bonuses (e.g. Praesidium Shield +1W) stack on top of profile wounds
# 4. Units without model_profiles are unaffected (backward compat)
# 5. Models without stats_override.wounds keep their JSON wounds value
# Usage: godot --headless --path . -s tests/test_ma13_per_model_wounds.gd

var _alm = null

func _initialize():
	await create_timer(0.1).timeout
	_alm = root.get_node("ArmyListManager")
	if _alm == null:
		print("FAIL: Could not get ArmyListManager autoload")
		quit(1)
		return
	_run_tests()

func _run_tests():
	print("\n=== Test MA-13: Per-model wounds from stats_override ===\n")
	var passed = 0
	var failed = 0

	# --- Test 1: stats_override.wounds=3 sets model wounds correctly ---
	print("--- Test 1: stats_override.wounds=3 sets model wounds to 3 ---")
	var unit = _make_mixed_wounds_unit()
	_alm._apply_model_profile_wounds("U_TEST", unit)
	var nob_model = unit["models"][0]
	if int(nob_model.get("wounds", 0)) == 3:
		print("  PASS: nob model wounds = 3")
		passed += 1
	else:
		print("  FAIL: Expected wounds=3, got %d" % int(nob_model.get("wounds", 0)))
		failed += 1

	# --- Test 2: stats_override.wounds=3 also updates current_wounds for undamaged model ---
	print("\n--- Test 2: current_wounds updated for undamaged model ---")
	if int(nob_model.get("current_wounds", 0)) == 3:
		print("  PASS: nob model current_wounds = 3")
		passed += 1
	else:
		print("  FAIL: Expected current_wounds=3, got %d" % int(nob_model.get("current_wounds", 0)))
		failed += 1

	# --- Test 3: Model without stats_override.wounds keeps JSON value ---
	print("\n--- Test 3: Model without stats_override.wounds keeps JSON wounds ---")
	var boy_model = unit["models"][1]
	if int(boy_model.get("wounds", 0)) == 1:
		print("  PASS: boy model wounds = 1 (unchanged)")
		passed += 1
	else:
		print("  FAIL: Expected wounds=1, got %d" % int(boy_model.get("wounds", 0)))
		failed += 1

	# --- Test 4: Mismatched JSON wounds are corrected ---
	print("\n--- Test 4: Mismatched JSON wounds corrected to stats_override value ---")
	var unit2 = _make_mismatched_wounds_unit()
	_alm._apply_model_profile_wounds("U_TEST2", unit2)
	var mismatched_model = unit2["models"][0]
	if int(mismatched_model.get("wounds", 0)) == 3:
		print("  PASS: mismatched model wounds corrected from 1 to 3")
		passed += 1
	else:
		print("  FAIL: Expected wounds=3 after correction, got %d" % int(mismatched_model.get("wounds", 0)))
		failed += 1

	# --- Test 5: current_wounds corrected for undamaged mismatched model ---
	print("\n--- Test 5: current_wounds corrected for undamaged mismatched model ---")
	if int(mismatched_model.get("current_wounds", 0)) == 3:
		print("  PASS: mismatched model current_wounds corrected to 3")
		passed += 1
	else:
		print("  FAIL: Expected current_wounds=3, got %d" % int(mismatched_model.get("current_wounds", 0)))
		failed += 1

	# --- Test 6: Damaged model's current_wounds not overwritten ---
	print("\n--- Test 6: Damaged model's current_wounds preserved ---")
	var unit3 = _make_damaged_model_unit()
	_alm._apply_model_profile_wounds("U_TEST3", unit3)
	var damaged_model = unit3["models"][0]
	# Model has wounds=3 matching override, but current_wounds=1 (damaged)
	if int(damaged_model.get("current_wounds", 0)) == 1:
		print("  PASS: damaged model current_wounds=1 preserved")
		passed += 1
	else:
		print("  FAIL: Expected current_wounds=1 (preserved), got %d" % int(damaged_model.get("current_wounds", 0)))
		failed += 1

	# --- Test 7: Wargear bonus stacks on top of profile wounds ---
	print("\n--- Test 7: Wargear bonus (+1W) stacks on profile wounds ---")
	var unit4 = _make_wargear_wounds_unit()
	# Apply profile wounds first, then wargear
	_alm._apply_model_profile_wounds("U_TEST4", unit4)
	_alm._apply_wargear_stat_bonuses("U_TEST4", unit4)
	var wargear_model = unit4["models"][0]
	# stats_override.wounds=3, then Praesidium Shield +1W = 4
	if int(wargear_model.get("wounds", 0)) == 4:
		print("  PASS: wargear stacked: profile wounds 3 + Praesidium Shield +1 = 4")
		passed += 1
	else:
		print("  FAIL: Expected wounds=4 (3+1), got %d" % int(wargear_model.get("wounds", 0)))
		failed += 1

	# --- Test 8: Wargear current_wounds also stacks ---
	print("\n--- Test 8: Wargear current_wounds also stacks ---")
	if int(wargear_model.get("current_wounds", 0)) == 4:
		print("  PASS: wargear stacked current_wounds = 4")
		passed += 1
	else:
		print("  FAIL: Expected current_wounds=4, got %d" % int(wargear_model.get("current_wounds", 0)))
		failed += 1

	# --- Test 9: Unit without model_profiles is unaffected ---
	print("\n--- Test 9: Unit without model_profiles is unaffected ---")
	var unit5 = _make_no_profiles_unit()
	_alm._apply_model_profile_wounds("U_TEST5", unit5)
	var plain_model = unit5["models"][0]
	if int(plain_model.get("wounds", 0)) == 2:
		print("  PASS: no-profile model wounds=2 unchanged")
		passed += 1
	else:
		print("  FAIL: Expected wounds=2 unchanged, got %d" % int(plain_model.get("wounds", 0)))
		failed += 1

	# --- Test 10: Model with model_type but no stats_override.wounds ---
	print("\n--- Test 10: Model with profile but empty stats_override is unaffected ---")
	var unit6 = _make_empty_override_unit()
	_alm._apply_model_profile_wounds("U_TEST6", unit6)
	var empty_override_model = unit6["models"][0]
	if int(empty_override_model.get("wounds", 0)) == 2:
		print("  PASS: empty stats_override model wounds=2 unchanged")
		passed += 1
	else:
		print("  FAIL: Expected wounds=2, got %d" % int(empty_override_model.get("wounds", 0)))
		failed += 1

	# --- Test 11: validate_army_structure catches wounds mismatch ---
	print("\n--- Test 11: validate_army_structure detects wounds mismatch ---")
	var army_data = _make_army_with_wounds_mismatch()
	var validation = _alm.validate_army_structure(army_data)
	var found_wounds_error = false
	for err in validation.get("errors", []):
		if "stats_override.wounds" in str(err):
			found_wounds_error = true
			break
	if found_wounds_error:
		print("  PASS: validate_army_structure detected wounds mismatch")
		passed += 1
	else:
		print("  FAIL: Expected wounds mismatch error, got errors: %s" % str(validation.get("errors", [])))
		failed += 1

	# --- Summary ---
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)

# ============================================================================
# Test data builders
# ============================================================================

func _make_mixed_wounds_unit() -> Dictionary:
	"""Unit where nob has stats_override.wounds=3 and boy has no wounds override."""
	return {
		"id": "U_TEST",
		"meta": {
			"name": "Test Mixed Wounds",
			"keywords": ["INFANTRY"],
			"stats": {"wounds": 1, "toughness": 4, "save": 5},
			"weapons": [],
			"model_profiles": {
				"nob": {"label": "Nob", "stats_override": {"wounds": 3}, "weapons": [], "transport_slots": 1},
				"boy": {"label": "Boy", "stats_override": {}, "weapons": [], "transport_slots": 1}
			}
		},
		"models": [
			{"id": "m1", "wounds": 3, "current_wounds": 3, "base_mm": 32, "position": null, "alive": true, "status_effects": [], "model_type": "nob"},
			{"id": "m2", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": [], "model_type": "boy"}
		]
	}

func _make_mismatched_wounds_unit() -> Dictionary:
	"""Unit where model JSON wounds=1 but stats_override.wounds=3 — should be corrected."""
	return {
		"id": "U_TEST2",
		"meta": {
			"name": "Test Mismatched Wounds",
			"keywords": ["INFANTRY"],
			"stats": {"wounds": 1, "toughness": 4, "save": 5},
			"weapons": [],
			"model_profiles": {
				"nob": {"label": "Nob", "stats_override": {"wounds": 3}, "weapons": [], "transport_slots": 1}
			}
		},
		"models": [
			{"id": "m1", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": [], "model_type": "nob"}
		]
	}

func _make_damaged_model_unit() -> Dictionary:
	"""Unit where model has correct wounds=3 but is damaged (current_wounds=1)."""
	return {
		"id": "U_TEST3",
		"meta": {
			"name": "Test Damaged Model",
			"keywords": ["INFANTRY"],
			"stats": {"wounds": 3, "toughness": 4, "save": 5},
			"weapons": [],
			"model_profiles": {
				"nob": {"label": "Nob", "stats_override": {"wounds": 3}, "weapons": [], "transport_slots": 1}
			}
		},
		"models": [
			{"id": "m1", "wounds": 3, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": [], "model_type": "nob"}
		]
	}

func _make_wargear_wounds_unit() -> Dictionary:
	"""Unit with stats_override.wounds=3 and Praesidium Shield wargear (+1W). Final should be 4."""
	return {
		"id": "U_TEST4",
		"meta": {
			"name": "Test Wargear Stack",
			"keywords": ["INFANTRY"],
			"stats": {"wounds": 3, "toughness": 4, "save": 5},
			"weapons": [],
			"abilities": [
				{"name": "Praesidium Shield", "type": "Wargear", "description": "+1 Wounds to bearer"}
			],
			"model_profiles": {
				"guardian": {"label": "Guardian", "stats_override": {"wounds": 3}, "weapons": [], "transport_slots": 1}
			}
		},
		"models": [
			{"id": "m1", "wounds": 3, "current_wounds": 3, "base_mm": 40, "position": null, "alive": true, "status_effects": [], "model_type": "guardian"}
		]
	}

func _make_no_profiles_unit() -> Dictionary:
	"""Unit without model_profiles (backward compat — should be unaffected)."""
	return {
		"id": "U_TEST5",
		"meta": {
			"name": "Test No Profiles",
			"keywords": ["INFANTRY"],
			"stats": {"wounds": 2, "toughness": 4, "save": 3},
			"weapons": []
		},
		"models": [
			{"id": "m1", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []}
		]
	}

func _make_empty_override_unit() -> Dictionary:
	"""Unit with model_profiles but empty stats_override (no wounds override)."""
	return {
		"id": "U_TEST6",
		"meta": {
			"name": "Test Empty Override",
			"keywords": ["INFANTRY"],
			"stats": {"wounds": 2, "toughness": 4, "save": 3},
			"weapons": [],
			"model_profiles": {
				"marine": {"label": "Marine", "stats_override": {}, "weapons": [], "transport_slots": 1}
			}
		},
		"models": [
			{"id": "m1", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": [], "model_type": "marine"}
		]
	}

func _make_army_with_wounds_mismatch() -> Dictionary:
	"""Army data where model wounds doesn't match stats_override.wounds — for validate_army_structure."""
	return {
		"units": {
			"U_MISMATCH": {
				"id": "U_MISMATCH",
				"meta": {
					"name": "Test Mismatch",
					"keywords": ["INFANTRY"],
					"stats": {"wounds": 1},
					"weapons": [],
					"model_profiles": {
						"nob": {"label": "Nob", "stats_override": {"wounds": 3}, "weapons": [], "transport_slots": 1}
					}
				},
				"models": [
					{"id": "m1", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": [], "model_type": "nob"}
				]
			}
		}
	}
