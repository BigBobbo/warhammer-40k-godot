extends SceneTree

# Test: OA-40 Blastajet Attack Run for Wazbom Blastajet
# Verifies that:
# 1. has_blastajet_attack_run() returns true for unit with the ability
# 2. has_blastajet_attack_run() returns false for unit without the ability
# 3. Re-roll scope is "ones" when target does NOT have FLY keyword
# 4. Re-roll scope is "" when target HAS FLY keyword
# Usage: godot --headless --path . -s tests/test_oa40_blastajet_attack_run.gd

var _re = null

func _initialize():
	await create_timer(0.1).timeout
	_re = root.get_node("RulesEngine")
	if _re == null:
		print("FAIL: Could not get RulesEngine autoload")
		quit(1)
		return
	_run_tests()

func _run_tests():
	print("\n=== Test OA-40: Blastajet Attack Run for Wazbom Blastajet ===\n")
	var passed = 0
	var failed = 0

	# --- Test 1: has_blastajet_attack_run() returns true for unit with ability ---
	print("--- Test 1: has_blastajet_attack_run() returns true for unit with ability ---")
	var blastajet = _make_wazbom_blastajet()
	if _re.has_blastajet_attack_run(blastajet):
		print("  PASS: has_blastajet_attack_run() returns true")
		passed += 1
	else:
		print("  FAIL: has_blastajet_attack_run() should return true for Wazbom Blastajet")
		failed += 1

	# --- Test 2: has_blastajet_attack_run() returns false for unit without ability ---
	print("\n--- Test 2: has_blastajet_attack_run() returns false for unit without ability ---")
	var boyz = _make_boyz_unit()
	if not _re.has_blastajet_attack_run(boyz):
		print("  PASS: has_blastajet_attack_run() returns false")
		passed += 1
	else:
		print("  FAIL: has_blastajet_attack_run() should return false for Boyz unit")
		failed += 1

	# --- Test 3: Re-roll scope is "ones" when target does NOT have FLY ---
	print("\n--- Test 3: Re-roll 1s vs non-FLY target ---")
	var non_fly_target = _make_infantry_target()
	var scope = _re.get_blastajet_attack_run_reroll_scope(blastajet, non_fly_target)
	if scope == "ones":
		print("  PASS: Re-roll scope is 'ones' vs non-FLY target")
		passed += 1
	else:
		print("  FAIL: Expected scope 'ones', got '%s'" % scope)
		failed += 1

	# --- Test 4: No re-roll when target HAS FLY keyword ---
	print("\n--- Test 4: No re-roll vs FLY target ---")
	var fly_target = _make_fly_target()
	var scope_fly = _re.get_blastajet_attack_run_reroll_scope(blastajet, fly_target)
	if scope_fly == "":
		print("  PASS: Re-roll scope is '' vs FLY target (no re-roll)")
		passed += 1
	else:
		print("  FAIL: Expected scope '', got '%s'" % scope_fly)
		failed += 1

	# --- Test 5: No re-roll for unit without the ability ---
	print("\n--- Test 5: No re-roll for unit without ability ---")
	var scope_no_ability = _re.get_blastajet_attack_run_reroll_scope(boyz, non_fly_target)
	if scope_no_ability == "":
		print("  PASS: Re-roll scope is '' for unit without ability")
		passed += 1
	else:
		print("  FAIL: Expected scope '', got '%s'" % scope_no_ability)
		failed += 1

	# --- Test 6: Ability with string format (not dict) ---
	print("\n--- Test 6: Ability detection with string format ---")
	var string_ability_unit = _make_unit_with_string_ability()
	if _re.has_blastajet_attack_run(string_ability_unit):
		print("  PASS: has_blastajet_attack_run() works with string ability format")
		passed += 1
	else:
		print("  FAIL: has_blastajet_attack_run() should work with string ability format")
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

# Helper: Create a Wazbom Blastajet unit with Blastajet Attack Run ability
func _make_wazbom_blastajet() -> Dictionary:
	return {
		"id": "U_WAZBOM_TEST",
		"meta": {
			"name": "Wazbom Blastajet",
			"keywords": ["WAZBOM BLASTAJET", "ORKS", "AIRCRAFT", "VEHICLE", "SPEED FREEKS", "FLY"],
			"stats": {
				"move": 20,
				"toughness": 9,
				"save": 3,
				"wounds": 12,
				"leadership": 7,
				"objective_control": 0,
				"invulnerable_save": 6
			},
			"abilities": [
				{"name": "Blastajet Attack Run", "type": "Datasheet", "description": "Re-roll Hit rolls of 1 vs non-FLY targets"}
			]
		},
		"models": [
			{"id": "m1", "wounds": 12, "current_wounds": 12, "alive": true, "status_effects": []}
		]
	}

# Helper: Create a Boyz unit without the ability
func _make_boyz_unit() -> Dictionary:
	return {
		"id": "U_BOYZ_TEST",
		"meta": {
			"name": "Boyz",
			"keywords": ["BOYZ", "ORKS", "INFANTRY"],
			"stats": {"move": 6, "toughness": 5, "save": 5, "wounds": 1},
			"abilities": [
				{"name": "Waaagh!", "type": "Faction", "description": "Waaagh! faction ability"}
			]
		},
		"models": [
			{"id": "m1", "wounds": 1, "current_wounds": 1, "alive": true, "status_effects": []}
		]
	}

# Helper: Create a non-FLY infantry target
func _make_infantry_target() -> Dictionary:
	return {
		"id": "U_INFANTRY_TARGET",
		"meta": {
			"name": "Space Marine Intercessors",
			"keywords": ["INFANTRY", "IMPERIUM", "ADEPTUS ASTARTES"],
			"stats": {"move": 6, "toughness": 4, "save": 3, "wounds": 2},
			"abilities": []
		},
		"models": [
			{"id": "m1", "wounds": 2, "current_wounds": 2, "alive": true, "status_effects": []}
		]
	}

# Helper: Create a FLY target
func _make_fly_target() -> Dictionary:
	return {
		"id": "U_FLY_TARGET",
		"meta": {
			"name": "Inceptor Squad",
			"keywords": ["INFANTRY", "IMPERIUM", "ADEPTUS ASTARTES", "FLY"],
			"stats": {"move": 10, "toughness": 5, "save": 3, "wounds": 3},
			"abilities": []
		},
		"models": [
			{"id": "m1", "wounds": 3, "current_wounds": 3, "alive": true, "status_effects": []}
		]
	}

# Helper: Create a unit with ability as plain string (not dict)
func _make_unit_with_string_ability() -> Dictionary:
	return {
		"id": "U_STRING_ABILITY_TEST",
		"meta": {
			"name": "Test Unit",
			"keywords": ["ORKS"],
			"stats": {"move": 6, "toughness": 4, "save": 3, "wounds": 1},
			"abilities": ["Blastajet Attack Run"]
		},
		"models": [
			{"id": "m1", "wounds": 1, "current_wounds": 1, "alive": true, "status_effects": []}
		]
	}
