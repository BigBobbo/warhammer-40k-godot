extends SceneTree

# Test: MA-11 Per-model WS in melee hit resolution
# Verifies that:
# 1. _get_model_effective_ws() returns correct WS per model type
# 2. Boss Nob (WS3+) and Boyz (WS4+) resolve correct hit thresholds per model
# 3. Units without model_profiles use weapon profile WS (backward compat)
# 4. Hit resolution with mixed-WS models produces correct results
# Usage: godot --headless --path . -s tests/test_ma11_per_model_ws.gd

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
	print("\n=== Test MA-11: Per-model WS in melee hit resolution ===\n")
	var passed = 0
	var failed = 0

	# --- Test 1: _get_model_effective_ws — boss_nob gets WS3 ---
	print("--- Test 1: _get_model_effective_ws — boss_nob returns WS 3 ---")
	var board = _make_boyz_board()
	var unit = board["units"]["U_BOYZ"]
	var weapon_profile = {"ws": 3, "name": "Choppa"}
	var nob_model = unit["models"][0]  # boss_nob
	var nob_ws = _re._get_model_effective_ws(nob_model, unit, weapon_profile)
	if nob_ws == 3:
		print("  PASS: boss_nob effective WS = 3")
		passed += 1
	else:
		print("  FAIL: Expected WS 3, got %d" % nob_ws)
		failed += 1

	# --- Test 2: _get_model_effective_ws — boy gets WS4 (overrides weapon WS3) ---
	print("\n--- Test 2: _get_model_effective_ws — boy returns WS 4 (override) ---")
	var boy_model = unit["models"][1]  # boy
	var boy_ws = _re._get_model_effective_ws(boy_model, unit, weapon_profile)
	if boy_ws == 4:
		print("  PASS: boy effective WS = 4 (overridden from weapon WS 3)")
		passed += 1
	else:
		print("  FAIL: Expected WS 4, got %d" % boy_ws)
		failed += 1

	# --- Test 3: _get_model_effective_ws — model without model_type ---
	print("\n--- Test 3: _get_model_effective_ws — model without model_type returns weapon WS ---")
	var basic_model = {"id": "m1", "wounds": 1, "current_wounds": 1, "alive": true}
	var basic_unit = {"meta": {"weapons": []}, "models": [basic_model]}
	var basic_ws = _re._get_model_effective_ws(basic_model, basic_unit, weapon_profile)
	if basic_ws == 3:
		print("  PASS: model without model_type gets weapon WS = 3")
		passed += 1
	else:
		print("  FAIL: Expected WS 3, got %d" % basic_ws)
		failed += 1

	# --- Test 4: _get_model_effective_ws — empty model returns weapon WS ---
	print("\n--- Test 4: _get_model_effective_ws — empty model returns weapon WS ---")
	var empty_ws = _re._get_model_effective_ws({}, unit, weapon_profile)
	if empty_ws == 3:
		print("  PASS: empty model gets weapon WS = 3")
		passed += 1
	else:
		print("  FAIL: Expected WS 3, got %d" % empty_ws)
		failed += 1

	# --- Test 5: _get_model_effective_ws — unit without model_profiles ---
	print("\n--- Test 5: _get_model_effective_ws — unit without model_profiles returns weapon WS ---")
	var no_profiles_unit = {"meta": {}}
	var no_profiles_ws = _re._get_model_effective_ws(boy_model, no_profiles_unit, weapon_profile)
	if no_profiles_ws == 3:
		print("  PASS: unit without model_profiles falls back to weapon WS = 3")
		passed += 1
	else:
		print("  FAIL: Expected WS 3, got %d" % no_profiles_ws)
		failed += 1

	# --- Test 6: Melee hit resolution — boss_nob attacks use WS3+ threshold ---
	print("\n--- Test 6: Melee resolution — boss_nob-only uses WS 3+ ---")
	var melee_board = _make_melee_board()
	var nob_hits_total = 0
	var nob_attacks_total = 0
	var num_trials = 200
	for trial in range(num_trials):
		var rng = _re.RNGService.new(trial)
		var assignment = {
			"attacker": "U_BOYZ",
			"target": "U_TARGET",
			"weapon": "choppa_melee",
			"models": ["0"]  # boss_nob only (index 0)
		}
		var result = _re._resolve_melee_assignment(assignment, "U_BOYZ", melee_board, rng)
		for dice_entry in result.get("dice", []):
			if dice_entry.get("context", "") == "hit_roll_melee":
				nob_hits_total += dice_entry.get("successes", 0)
				nob_attacks_total += dice_entry.get("rolls_raw", []).size()
	var nob_hit_rate = float(nob_hits_total) / float(nob_attacks_total) if nob_attacks_total > 0 else 0.0
	# WS3+ = 67% hit rate (4/6), expect ~0.67. Allow range 0.52-0.82
	if nob_attacks_total > 0 and nob_hit_rate >= 0.52 and nob_hit_rate <= 0.82:
		print("  PASS: boss_nob hit rate = %.2f (expected ~0.67 for WS3+), %d hits / %d attacks" % [nob_hit_rate, nob_hits_total, nob_attacks_total])
		passed += 1
	else:
		print("  FAIL: boss_nob hit rate = %.2f, expected ~0.67 for WS3+ (%d hits / %d attacks)" % [nob_hit_rate, nob_hits_total, nob_attacks_total])
		failed += 1

	# --- Test 7: Melee hit resolution — boy attacks use WS4+ threshold ---
	print("\n--- Test 7: Melee resolution — boy-only uses WS 4+ ---")
	var boy_hits_total = 0
	var boy_attacks_total = 0
	for trial in range(num_trials):
		var rng = _re.RNGService.new(trial)
		var assignment = {
			"attacker": "U_BOYZ",
			"target": "U_TARGET",
			"weapon": "choppa_melee",
			"models": ["1"]  # boy only (index 1)
		}
		var result = _re._resolve_melee_assignment(assignment, "U_BOYZ", melee_board, rng)
		for dice_entry in result.get("dice", []):
			if dice_entry.get("context", "") == "hit_roll_melee":
				boy_hits_total += dice_entry.get("successes", 0)
				boy_attacks_total += dice_entry.get("rolls_raw", []).size()
	var boy_hit_rate = float(boy_hits_total) / float(boy_attacks_total) if boy_attacks_total > 0 else 0.0
	# WS4+ = 50% hit rate (3/6), expect ~0.50. Allow range 0.35-0.65
	if boy_attacks_total > 0 and boy_hit_rate >= 0.35 and boy_hit_rate <= 0.65:
		print("  PASS: boy hit rate = %.2f (expected ~0.50 for WS4+), %d hits / %d attacks" % [boy_hit_rate, boy_hits_total, boy_attacks_total])
		passed += 1
	else:
		print("  FAIL: boy hit rate = %.2f, expected ~0.50 for WS4+ (%d hits / %d attacks)" % [boy_hit_rate, boy_hits_total, boy_attacks_total])
		failed += 1

	# --- Test 8: Boss nob should have higher hit rate than boy ---
	print("\n--- Test 8: Boss nob hit rate > boy hit rate ---")
	if nob_hit_rate > boy_hit_rate:
		print("  PASS: boss_nob (%.2f) > boy (%.2f)" % [nob_hit_rate, boy_hit_rate])
		passed += 1
	else:
		print("  FAIL: boss_nob (%.2f) not greater than boy (%.2f)" % [nob_hit_rate, boy_hit_rate])
		failed += 1

	# --- Test 9: Mixed melee — all models fight together (empty models = all eligible) ---
	print("\n--- Test 9: Mixed melee — all eligible models fight together ---")
	var mixed_hits_total = 0
	var mixed_attacks_total = 0
	for trial in range(num_trials):
		var rng = _re.RNGService.new(trial)
		var assignment = {
			"attacker": "U_BOYZ",
			"target": "U_TARGET",
			"weapon": "choppa_melee",
			"models": []  # empty = all eligible models fight
		}
		var result = _re._resolve_melee_assignment(assignment, "U_BOYZ", melee_board, rng)
		for dice_entry in result.get("dice", []):
			if dice_entry.get("context", "") == "hit_roll_melee":
				mixed_hits_total += dice_entry.get("successes", 0)
				mixed_attacks_total += dice_entry.get("rolls_raw", []).size()
	var mixed_hit_rate = float(mixed_hits_total) / float(mixed_attacks_total) if mixed_attacks_total > 0 else 0.0
	# Mixed: nob WS3+ (67%) + boys WS4+ (50%) — weighted avg depends on eligible count
	# With 6 eligible (1 nob + 5 boys), avg = (0.67 + 5*0.50) / 6 ≈ 0.53
	# Allow broad range 0.40-0.70
	if mixed_attacks_total > 0 and mixed_hit_rate >= 0.40 and mixed_hit_rate <= 0.70:
		print("  PASS: mixed hit rate = %.2f, %d hits / %d attacks" % [mixed_hit_rate, mixed_hits_total, mixed_attacks_total])
		passed += 1
	else:
		print("  FAIL: mixed hit rate = %.2f (%d hits / %d attacks)" % [mixed_hit_rate, mixed_hits_total, mixed_attacks_total])
		failed += 1

	# --- Test 10: Backward compat — unit without model_profiles uses weapon WS ---
	print("\n--- Test 10: Backward compat — no model_profiles uses weapon WS ---")
	var compat_board = _make_compat_board()
	var compat_hits_total = 0
	var compat_attacks_total = 0
	for trial in range(num_trials):
		var rng = _re.RNGService.new(trial)
		var assignment = {
			"attacker": "U_PLAIN",
			"target": "U_TARGET",
			"weapon": "choppa_melee",
			"models": ["0"]
		}
		var result = _re._resolve_melee_assignment(assignment, "U_PLAIN", compat_board, rng)
		for dice_entry in result.get("dice", []):
			if dice_entry.get("context", "") == "hit_roll_melee":
				compat_hits_total += dice_entry.get("successes", 0)
				compat_attacks_total += dice_entry.get("rolls_raw", []).size()
	var compat_hit_rate = float(compat_hits_total) / float(compat_attacks_total) if compat_attacks_total > 0 else 0.0
	# WS3+ from weapon = 67%, expect ~0.67
	if compat_attacks_total > 0 and compat_hit_rate >= 0.52 and compat_hit_rate <= 0.82:
		print("  PASS: compat hit rate = %.2f (expected ~0.67 for weapon WS3+), %d hits / %d attacks" % [compat_hit_rate, compat_hits_total, compat_attacks_total])
		passed += 1
	else:
		print("  FAIL: compat hit rate = %.2f, expected ~0.67 (%d hits / %d attacks)" % [compat_hit_rate, compat_hits_total, compat_attacks_total])
		failed += 1

	# --- Summary ---
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)

func _make_boyz_board() -> Dictionary:
	# Position models very close together so they are within engagement range (1")
	# 40px = 1 inch. 32mm base = ~50px diameter. Place models nearly touching.
	var models = []
	# Boss Nob (index 0) — WS3+
	models.append({"id": "m1", "wounds": 1, "current_wounds": 1, "alive": true, "model_type": "boss_nob", "position": Vector2(200, 200), "base_mm": 32})
	# Boyz (indices 1-9) — WS4+
	for i in range(9):
		models.append({"id": "m%d" % (i + 2), "wounds": 1, "current_wounds": 1, "alive": true, "model_type": "boy", "position": Vector2(200 + (i + 1) * 52, 200), "base_mm": 32})

	return {"units": {"U_BOYZ": {
		"id": "U_BOYZ",
		"owner": 2,
		"meta": {
			"name": "Boyz",
			"keywords": ["INFANTRY", "ORKS"],
			"weapons": [
				{"name": "Choppa", "type": "Melee", "range": "Melee", "attacks": "3", "weapon_skill": "3", "strength": "4", "ap": "-1", "damage": "1"},
				{"name": "Close combat weapon", "type": "Melee", "range": "Melee", "attacks": "2", "weapon_skill": "3", "strength": "4", "ap": "0", "damage": "1"},
				{"name": "Slugga", "type": "Ranged", "range": "12", "attacks": "1", "ballistic_skill": "5", "strength": "4", "ap": "0", "damage": "1", "special_rules": "pistol"}
			],
			"model_profiles": {
				"boss_nob": {"label": "Boss Nob", "stats_override": {"weapon_skill": 3}, "weapons": ["Choppa", "Slugga"], "transport_slots": 1},
				"boy": {"label": "Boy", "stats_override": {"weapon_skill": 4}, "weapons": ["Choppa", "Close combat weapon", "Slugga"], "transport_slots": 1}
			},
			"stats": {"move": 6, "toughness": 5, "save": 5, "wounds": 1},
			"abilities": []
		},
		"models": models
	}}}

func _make_melee_board() -> Dictionary:
	var board = _make_boyz_board()

	# Add a target unit — place models overlapping with attackers for guaranteed engagement range
	# Each target model at same Y, very close X (within 1" = 40px edge-to-edge)
	var target_models = []
	for i in range(5):
		target_models.append({
			"id": "t%d" % (i + 1),
			"wounds": 2,
			"current_wounds": 2,
			"alive": true,
			"position": Vector2(200 + i * 52, 252),  # 52px apart, 52px from closest attacker
			"base_mm": 32
		})
	board["units"]["U_TARGET"] = {
		"id": "U_TARGET",
		"owner": 1,
		"meta": {
			"name": "Target Squad",
			"keywords": ["INFANTRY"],
			"weapons": [],
			"stats": {"move": 6, "toughness": 4, "save": 4, "wounds": 2},
			"abilities": []
		},
		"models": target_models
	}
	return board

func _make_compat_board() -> Dictionary:
	# Board with a unit that has NO model_profiles (backward compat test)
	var models = []
	for i in range(5):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": 1,
			"current_wounds": 1,
			"alive": true,
			"position": Vector2(200 + i * 52, 200),
			"base_mm": 32
		})

	var target_models = []
	for i in range(5):
		target_models.append({
			"id": "t%d" % (i + 1),
			"wounds": 2,
			"current_wounds": 2,
			"alive": true,
			"position": Vector2(200 + i * 52, 252),
			"base_mm": 32
		})

	return {"units": {
		"U_PLAIN": {
			"id": "U_PLAIN",
			"owner": 2,
			"meta": {
				"name": "Plain Unit",
				"keywords": ["INFANTRY"],
				"weapons": [
					{"name": "Choppa", "type": "Melee", "range": "Melee", "attacks": "3", "weapon_skill": "3", "strength": "4", "ap": "-1", "damage": "1"}
				],
				"stats": {"move": 6, "toughness": 5, "save": 5, "wounds": 1},
				"abilities": []
			},
			"models": models
		},
		"U_TARGET": {
			"id": "U_TARGET",
			"owner": 1,
			"meta": {
				"name": "Target Squad",
				"keywords": ["INFANTRY"],
				"weapons": [],
				"stats": {"move": 6, "toughness": 4, "save": 4, "wounds": 2},
				"abilities": []
			},
			"models": target_models
		}
	}}
