extends SceneTree

# Test: MA-14 Rapid Fire bonus per-weapon-per-model
# Verifies that:
# 1. RF bonus only counts models from the assignment's model_ids (not all unit models)
# 2. Mixed-weapon unit: bolter models count for bolt rifle RF, plasma models don't
# 3. Same behavior in auto-resolve path
# 4. Units without model_profiles (backward compat) still work correctly
# Usage: godot --headless --path . -s tests/test_ma14_rapid_fire_per_weapon.gd

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
	print("\n=== Test MA-14: Rapid Fire bonus per-weapon-per-model ===\n")
	var passed = 0
	var failed = 0

	# --- Test 1: RF bonus counts only assigned models (5 of 10) ---
	print("--- Test 1: RF bonus counts only 5 bolter models (not all 10) ---")
	var board = _make_mixed_weapon_board()
	var bolter_model_ids = ["m1", "m2", "m3", "m4", "m5"]
	var action_bolter = {
		"actor_unit_id": "U_MIXED",
		"payload": {"assignments": [{
			"weapon_id": "bolt_rifle_ranged",
			"target_unit_id": "U_TARGET",
			"model_ids": bolter_model_ids
		}]}
	}
	# Run many trials — RF adds 1 attack per model in half range
	# With 5 models, each with 2 base attacks + 1 RF = 15 total attacks per trial
	var bolter_total_attacks = 0
	var num_trials = 50
	for trial in range(num_trials):
		var rng = _re.RNGService.new(trial)
		var result = _re._resolve_assignment_until_wounds(
			action_bolter["payload"]["assignments"][0],
			"U_MIXED", board, rng
		)
		for dice_entry in result.get("dice", []):
			if dice_entry.get("context", "") == "to_hit":
				bolter_total_attacks += dice_entry.get("rolls_raw", []).size()
	var avg_attacks = float(bolter_total_attacks) / float(num_trials)
	# 5 models * (2 base + 1 RF) = 15 attacks per trial
	if avg_attacks >= 14.5 and avg_attacks <= 15.5:
		print("  PASS: avg attacks = %.1f (expected 15 = 5 models * 3 attacks)" % avg_attacks)
		passed += 1
	else:
		print("  FAIL: avg attacks = %.1f (expected 15 = 5 models * 3 attacks)" % avg_attacks)
		failed += 1

	# --- Test 2: Wrong assignment (all 10 models for bolter) gives 30 attacks ---
	print("\n--- Test 2: All 10 models assigned to bolter → 30 attacks (incorrect scenario) ---")
	var all_model_ids = ["m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8", "m9", "m10"]
	var action_all = {
		"actor_unit_id": "U_MIXED",
		"payload": {"assignments": [{
			"weapon_id": "bolt_rifle_ranged",
			"target_unit_id": "U_TARGET",
			"model_ids": all_model_ids
		}]}
	}
	var all_total_attacks = 0
	for trial in range(num_trials):
		var rng = _re.RNGService.new(trial)
		var result = _re._resolve_assignment_until_wounds(
			action_all["payload"]["assignments"][0],
			"U_MIXED", board, rng
		)
		for dice_entry in result.get("dice", []):
			if dice_entry.get("context", "") == "to_hit":
				all_total_attacks += dice_entry.get("rolls_raw", []).size()
	var avg_all = float(all_total_attacks) / float(num_trials)
	# 10 models * (2 base + 1 RF) = 30 attacks — this is what happens with wrong assignment
	if avg_all >= 29.5 and avg_all <= 30.5:
		print("  PASS: avg attacks = %.1f (confirms 10 * 3 = 30 when all models assigned)" % avg_all)
		passed += 1
	else:
		print("  FAIL: avg attacks = %.1f (expected 30)" % avg_all)
		failed += 1

	# --- Test 3: Correct per-weapon assignment has fewer attacks than wrong one ---
	print("\n--- Test 3: Bolter-only (15) < all-models (30) confirms filtering works ---")
	if avg_attacks < avg_all:
		print("  PASS: bolter-only (%.1f) < all-models (%.1f)" % [avg_attacks, avg_all])
		passed += 1
	else:
		print("  FAIL: bolter-only (%.1f) not < all-models (%.1f)" % [avg_attacks, avg_all])
		failed += 1

	# --- Test 4: Non-RF weapon (plasma) gets 0 RF bonus regardless ---
	print("\n--- Test 4: Plasma gun (not RF) gets 0 RF bonus ---")
	var plasma_model_ids = ["m6", "m7", "m8", "m9", "m10"]
	var action_plasma = {
		"actor_unit_id": "U_MIXED",
		"payload": {"assignments": [{
			"weapon_id": "plasma_gun_ranged",
			"target_unit_id": "U_TARGET",
			"model_ids": plasma_model_ids
		}]}
	}
	var plasma_total_attacks = 0
	for trial in range(num_trials):
		var rng = _re.RNGService.new(trial)
		var result = _re._resolve_assignment_until_wounds(
			action_plasma["payload"]["assignments"][0],
			"U_MIXED", board, rng
		)
		for dice_entry in result.get("dice", []):
			if dice_entry.get("context", "") == "to_hit":
				plasma_total_attacks += dice_entry.get("rolls_raw", []).size()
	var avg_plasma = float(plasma_total_attacks) / float(num_trials)
	# 5 models * 1 base attack = 5 attacks (no RF)
	if avg_plasma >= 4.5 and avg_plasma <= 5.5:
		print("  PASS: avg plasma attacks = %.1f (expected 5 = 5 models * 1 attack, no RF)" % avg_plasma)
		passed += 1
	else:
		print("  FAIL: avg plasma attacks = %.1f (expected 5)" % avg_plasma)
		failed += 1

	# --- Test 5: Auto-resolve path — same RF filtering ---
	print("\n--- Test 5: Auto-resolve path uses per-assignment model_ids for RF ---")
	var auto_bolter_attacks = 0
	for trial in range(num_trials):
		var rng = _re.RNGService.new(trial + 1000)
		var result = _re._resolve_assignment(
			{"weapon_id": "bolt_rifle_ranged", "target_unit_id": "U_TARGET", "model_ids": bolter_model_ids},
			"U_MIXED", board, rng
		)
		for dice_entry in result.get("dice", []):
			if dice_entry.get("context", "") == "to_hit":
				auto_bolter_attacks += dice_entry.get("rolls_raw", []).size()
	var avg_auto = float(auto_bolter_attacks) / float(num_trials)
	if avg_auto >= 14.5 and avg_auto <= 15.5:
		print("  PASS: auto-resolve avg attacks = %.1f (expected 15)" % avg_auto)
		passed += 1
	else:
		print("  FAIL: auto-resolve avg attacks = %.1f (expected 15)" % avg_auto)
		failed += 1

	# --- Test 6: Backward compat — unit without model_profiles still works ---
	print("\n--- Test 6: Backward compat — unit without model_profiles ---")
	var legacy_board = _make_legacy_board()
	var legacy_model_ids = ["m1", "m2", "m3", "m4", "m5"]
	var action_legacy = {
		"actor_unit_id": "U_LEGACY",
		"payload": {"assignments": [{
			"weapon_id": "bolt_rifle_ranged",
			"target_unit_id": "U_TARGET",
			"model_ids": legacy_model_ids
		}]}
	}
	var legacy_total_attacks = 0
	for trial in range(num_trials):
		var rng = _re.RNGService.new(trial + 2000)
		var result = _re._resolve_assignment_until_wounds(
			action_legacy["payload"]["assignments"][0],
			"U_LEGACY", legacy_board, rng
		)
		for dice_entry in result.get("dice", []):
			if dice_entry.get("context", "") == "to_hit":
				legacy_total_attacks += dice_entry.get("rolls_raw", []).size()
	var avg_legacy = float(legacy_total_attacks) / float(num_trials)
	# 5 models * (2 base + 1 RF) = 15 attacks
	if avg_legacy >= 14.5 and avg_legacy <= 15.5:
		print("  PASS: legacy avg attacks = %.1f (expected 15)" % avg_legacy)
		passed += 1
	else:
		print("  FAIL: legacy avg attacks = %.1f (expected 15)" % avg_legacy)
		failed += 1

	# --- Summary ---
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)

# Mixed-weapon unit: 5 bolter models (RF1) + 5 plasma models (no RF)
# All models within half range of target (close together)
func _make_mixed_weapon_board() -> Dictionary:
	var models = []
	# 5 bolter models
	for i in range(5):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": 1, "current_wounds": 1, "alive": true,
			"model_type": "bolter_marine",
			"position": Vector2(200, 100),  # ~2.5" from target
			"base_mm": 32
		})
	# 5 plasma models
	for i in range(5):
		models.append({
			"id": "m%d" % (i + 6),
			"wounds": 1, "current_wounds": 1, "alive": true,
			"model_type": "plasma_marine",
			"position": Vector2(200, 100),  # same position, also in half range
			"base_mm": 32
		})

	var target_models = []
	for i in range(5):
		target_models.append({
			"id": "t%d" % (i + 1),
			"wounds": 2, "current_wounds": 2, "alive": true,
			"position": Vector2(300, 100),  # ~2.5" from shooters
			"base_mm": 32
		})

	return {"units": {
		"U_MIXED": {
			"id": "U_MIXED",
			"meta": {
				"name": "Mixed Intercessors",
				"weapons": [
					{"name": "Bolt rifle", "type": "Ranged", "range": "24", "attacks": "2", "strength": "4", "ap": "-1", "damage": "1", "ballistic_skill": "3", "special_rules": "rapid fire 1"},
					{"name": "Plasma gun", "type": "Ranged", "range": "24", "attacks": "1", "strength": "7", "ap": "-2", "damage": "1", "ballistic_skill": "3", "special_rules": ""},
					{"name": "Close combat weapon", "type": "Melee", "range": "Melee", "attacks": "3", "strength": "4", "ap": "0", "damage": "1", "weapon_skill": "3"}
				],
				"model_profiles": {
					"bolter_marine": {"label": "Intercessor (Bolt Rifle)", "stats_override": {}, "weapons": ["Bolt rifle", "Close combat weapon"], "transport_slots": 1},
					"plasma_marine": {"label": "Intercessor (Plasma)", "stats_override": {}, "weapons": ["Plasma gun", "Close combat weapon"], "transport_slots": 1}
				},
				"stats": {"move": 6, "toughness": 4, "save": 3, "wounds": 1}
			},
			"models": models
		},
		"U_TARGET": {
			"id": "U_TARGET",
			"meta": {
				"name": "Target Squad",
				"weapons": [],
				"stats": {"move": 6, "toughness": 4, "save": 4, "wounds": 2}
			},
			"models": target_models
		}
	}}

# Legacy unit without model_profiles — all models have all weapons
func _make_legacy_board() -> Dictionary:
	var models = []
	for i in range(5):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": 1, "current_wounds": 1, "alive": true,
			"position": Vector2(200, 100),
			"base_mm": 32
		})

	var target_models = []
	for i in range(5):
		target_models.append({
			"id": "t%d" % (i + 1),
			"wounds": 2, "current_wounds": 2, "alive": true,
			"position": Vector2(300, 100),
			"base_mm": 32
		})

	return {"units": {
		"U_LEGACY": {
			"id": "U_LEGACY",
			"meta": {
				"name": "Legacy Intercessors",
				"weapons": [
					{"name": "Bolt rifle", "type": "Ranged", "range": "24", "attacks": "2", "strength": "4", "ap": "-1", "damage": "1", "ballistic_skill": "3", "special_rules": "rapid fire 1"}
				],
				"stats": {"move": 6, "toughness": 4, "save": 3, "wounds": 1}
			},
			"models": models
		},
		"U_TARGET": {
			"id": "U_TARGET",
			"meta": {
				"name": "Target Squad",
				"weapons": [],
				"stats": {"move": 6, "toughness": 4, "save": 4, "wounds": 2}
			},
			"models": target_models
		}
	}}
