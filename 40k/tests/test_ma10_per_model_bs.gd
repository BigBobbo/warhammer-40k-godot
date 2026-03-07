extends SceneTree

# Test: MA-10 Per-model BS in ranged hit resolution
# Verifies that:
# 1. _get_model_effective_bs() returns correct BS per model type
# 2. Spanner (BS4+) uses BS 4 while regular Lootas use weapon profile BS
# 3. Units without model_profiles use weapon profile BS (backward compat)
# 4. Hit resolution with mixed-BS models produces correct results
# Usage: godot --headless --path . -s tests/test_ma10_per_model_bs.gd

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
	print("\n=== Test MA-10: Per-model BS in ranged hit resolution ===\n")
	var passed = 0
	var failed = 0

	# --- Test 1: _get_model_effective_bs — spanner gets BS4 ---
	print("--- Test 1: _get_model_effective_bs — spanner model returns BS 4 ---")
	var board = _make_lootas_board()
	var unit = board["units"]["U_LOOTAS"]
	var weapon_profile = {"bs": 5, "name": "Kustom mega-blasta"}
	var spanner_model = unit["models"][10]  # spanner
	var spanner_bs = _re._get_model_effective_bs(spanner_model, unit, weapon_profile)
	if spanner_bs == 4:
		print("  PASS: spanner effective BS = 4")
		passed += 1
	else:
		print("  FAIL: Expected BS 4, got %d" % spanner_bs)
		failed += 1

	# --- Test 2: _get_model_effective_bs — regular loota gets weapon BS ---
	print("\n--- Test 2: _get_model_effective_bs — loota_kmb returns weapon BS 5 ---")
	var kmb_model = unit["models"][8]  # loota_kmb
	var kmb_bs = _re._get_model_effective_bs(kmb_model, unit, weapon_profile)
	if kmb_bs == 5:
		print("  PASS: loota_kmb effective BS = 5 (weapon default)")
		passed += 1
	else:
		print("  FAIL: Expected BS 5, got %d" % kmb_bs)
		failed += 1

	# --- Test 3: _get_model_effective_bs — deffgun loota gets weapon BS ---
	print("\n--- Test 3: _get_model_effective_bs — loota_deffgun returns weapon BS ---")
	var deffgun_profile = {"bs": 6, "name": "Deffgun"}
	var deffgun_model = unit["models"][0]  # loota_deffgun
	var deffgun_bs = _re._get_model_effective_bs(deffgun_model, unit, deffgun_profile)
	if deffgun_bs == 6:
		print("  PASS: loota_deffgun effective BS = 6 (weapon default)")
		passed += 1
	else:
		print("  FAIL: Expected BS 6, got %d" % deffgun_bs)
		failed += 1

	# --- Test 4: _get_model_effective_bs — model without model_type ---
	print("\n--- Test 4: _get_model_effective_bs — model without model_type returns weapon BS ---")
	var basic_model = {"id": "m1", "wounds": 1, "current_wounds": 1, "alive": true}
	var basic_unit = {"meta": {"weapons": []}, "models": [basic_model]}
	var basic_bs = _re._get_model_effective_bs(basic_model, basic_unit, weapon_profile)
	if basic_bs == 5:
		print("  PASS: model without model_type gets weapon BS = 5")
		passed += 1
	else:
		print("  FAIL: Expected BS 5, got %d" % basic_bs)
		failed += 1

	# --- Test 5: _get_model_effective_bs — empty model returns weapon BS ---
	print("\n--- Test 5: _get_model_effective_bs — empty model returns weapon BS ---")
	var empty_bs = _re._get_model_effective_bs({}, unit, weapon_profile)
	if empty_bs == 5:
		print("  PASS: empty model gets weapon BS = 5")
		passed += 1
	else:
		print("  FAIL: Expected BS 5, got %d" % empty_bs)
		failed += 1

	# --- Test 6: Hit resolution — spanner attacks use BS4+ threshold ---
	# Fire KMB with just the spanner (BS4+). All rolls of 4+ should hit.
	print("\n--- Test 6: Hit resolution — spanner-only KMB assignment uses BS 4+ ---")
	var shoot_board = _make_shooting_board()
	var spanner_only_action = {
		"actor_unit_id": "U_LOOTAS",
		"payload": {"assignments": [{
			"weapon_id": "kustom_mega_blasta_ranged",
			"target_unit_id": "U_TARGET",
			"model_ids": ["m11"]  # spanner only
		}]}
	}
	# Run multiple trials to verify spanner hits on 4+
	var spanner_hits_total = 0
	var spanner_attacks_total = 0
	var num_trials = 200
	for trial in range(num_trials):
		var rng = _re.RNGService.new(trial)
		var result = _re.resolve_shoot(spanner_only_action, shoot_board, rng)
		for dice_entry in result.get("dice", []):
			if dice_entry.get("context", "") == "to_hit":
				spanner_hits_total += dice_entry.get("successes", 0)
				spanner_attacks_total += dice_entry.get("rolls_raw", []).size()
	var spanner_hit_rate = float(spanner_hits_total) / float(spanner_attacks_total) if spanner_attacks_total > 0 else 0.0
	# BS4+ = 50% hit rate (3/6), expect ~0.50. Allow range 0.35-0.65
	if spanner_attacks_total > 0 and spanner_hit_rate >= 0.35 and spanner_hit_rate <= 0.65:
		print("  PASS: spanner hit rate = %.2f (expected ~0.50 for BS4+), %d hits / %d attacks" % [spanner_hit_rate, spanner_hits_total, spanner_attacks_total])
		passed += 1
	else:
		print("  FAIL: spanner hit rate = %.2f, expected ~0.50 for BS4+ (%d hits / %d attacks)" % [spanner_hit_rate, spanner_hits_total, spanner_attacks_total])
		failed += 1

	# --- Test 7: Hit resolution — loota_kmb attacks use BS5+ threshold ---
	print("\n--- Test 7: Hit resolution — loota_kmb KMB assignment uses BS 5+ ---")
	var kmb_only_action = {
		"actor_unit_id": "U_LOOTAS",
		"payload": {"assignments": [{
			"weapon_id": "kustom_mega_blasta_ranged",
			"target_unit_id": "U_TARGET",
			"model_ids": ["m9"]  # loota_kmb only
		}]}
	}
	var kmb_hits_total = 0
	var kmb_attacks_total = 0
	for trial in range(num_trials):
		var rng = _re.RNGService.new(trial)
		var result = _re.resolve_shoot(kmb_only_action, shoot_board, rng)
		for dice_entry in result.get("dice", []):
			if dice_entry.get("context", "") == "to_hit":
				kmb_hits_total += dice_entry.get("successes", 0)
				kmb_attacks_total += dice_entry.get("rolls_raw", []).size()
	var kmb_hit_rate = float(kmb_hits_total) / float(kmb_attacks_total) if kmb_attacks_total > 0 else 0.0
	# BS5+ = 33% hit rate (2/6), expect ~0.33. Allow range 0.20-0.46
	if kmb_attacks_total > 0 and kmb_hit_rate >= 0.20 and kmb_hit_rate <= 0.46:
		print("  PASS: loota_kmb hit rate = %.2f (expected ~0.33 for BS5+), %d hits / %d attacks" % [kmb_hit_rate, kmb_hits_total, kmb_attacks_total])
		passed += 1
	else:
		print("  FAIL: loota_kmb hit rate = %.2f, expected ~0.33 for BS5+ (%d hits / %d attacks)" % [kmb_hit_rate, kmb_hits_total, kmb_attacks_total])
		failed += 1

	# --- Test 8: Spanner should have higher hit rate than regular loota ---
	print("\n--- Test 8: Spanner hit rate > loota_kmb hit rate ---")
	if spanner_hit_rate > kmb_hit_rate:
		print("  PASS: spanner (%.2f) > loota_kmb (%.2f)" % [spanner_hit_rate, kmb_hit_rate])
		passed += 1
	else:
		print("  FAIL: spanner (%.2f) not greater than loota_kmb (%.2f)" % [spanner_hit_rate, kmb_hit_rate])
		failed += 1

	# --- Test 9: Mixed assignment — both spanner and loota_kmb fire KMB ---
	print("\n--- Test 9: Mixed assignment — spanner + loota_kmb fire KMB together ---")
	var mixed_action = {
		"actor_unit_id": "U_LOOTAS",
		"payload": {"assignments": [{
			"weapon_id": "kustom_mega_blasta_ranged",
			"target_unit_id": "U_TARGET",
			"model_ids": ["m9", "m11"]  # loota_kmb + spanner
		}]}
	}
	var mixed_hits_total = 0
	var mixed_attacks_total = 0
	for trial in range(num_trials):
		var rng = _re.RNGService.new(trial)
		var result = _re.resolve_shoot(mixed_action, shoot_board, rng)
		for dice_entry in result.get("dice", []):
			if dice_entry.get("context", "") == "to_hit":
				mixed_hits_total += dice_entry.get("successes", 0)
				mixed_attacks_total += dice_entry.get("rolls_raw", []).size()
	var mixed_hit_rate = float(mixed_hits_total) / float(mixed_attacks_total) if mixed_attacks_total > 0 else 0.0
	# Mixed: 3 attacks at BS5+ (33%) + 3 attacks at BS4+ (50%) = weighted avg ~41.7%
	# Allow range 0.28-0.55
	if mixed_attacks_total > 0 and mixed_hit_rate >= 0.28 and mixed_hit_rate <= 0.55:
		print("  PASS: mixed hit rate = %.2f (expected ~0.42 weighted), %d hits / %d attacks" % [mixed_hit_rate, mixed_hits_total, mixed_attacks_total])
		passed += 1
	else:
		print("  FAIL: mixed hit rate = %.2f, expected ~0.42 (%d hits / %d attacks)" % [mixed_hit_rate, mixed_hits_total, mixed_attacks_total])
		failed += 1

	# --- Test 10: Auto-resolve path also uses per-model BS ---
	print("\n--- Test 10: Auto-resolve path — spanner BS override applies ---")
	var auto_spanner_hits = 0
	var auto_spanner_attacks = 0
	var auto_kmb_hits = 0
	var auto_kmb_attacks = 0
	for trial in range(num_trials):
		var rng_s = _re.RNGService.new(trial + 5000)
		var result_s = _re._resolve_assignment(
			{"weapon_id": "kustom_mega_blasta_ranged", "target_unit_id": "U_TARGET", "model_ids": ["m11"]},
			"U_LOOTAS", shoot_board, rng_s
		)
		for dice_entry in result_s.get("dice", []):
			if dice_entry.get("context", "") == "to_hit":
				auto_spanner_hits += dice_entry.get("successes", 0)
				auto_spanner_attacks += dice_entry.get("rolls_raw", []).size()
		var rng_k = _re.RNGService.new(trial + 5000)
		var result_k = _re._resolve_assignment(
			{"weapon_id": "kustom_mega_blasta_ranged", "target_unit_id": "U_TARGET", "model_ids": ["m9"]},
			"U_LOOTAS", shoot_board, rng_k
		)
		for dice_entry in result_k.get("dice", []):
			if dice_entry.get("context", "") == "to_hit":
				auto_kmb_hits += dice_entry.get("successes", 0)
				auto_kmb_attacks += dice_entry.get("rolls_raw", []).size()
	var auto_s_rate = float(auto_spanner_hits) / float(auto_spanner_attacks) if auto_spanner_attacks > 0 else 0.0
	var auto_k_rate = float(auto_kmb_hits) / float(auto_kmb_attacks) if auto_kmb_attacks > 0 else 0.0
	if auto_spanner_attacks > 0 and auto_s_rate > auto_k_rate:
		print("  PASS: auto-resolve spanner rate (%.2f) > loota_kmb rate (%.2f)" % [auto_s_rate, auto_k_rate])
		passed += 1
	else:
		print("  FAIL: auto-resolve spanner rate (%.2f) not > loota_kmb rate (%.2f)" % [auto_s_rate, auto_k_rate])
		failed += 1

	# --- Summary ---
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)

func _make_lootas_board() -> Dictionary:
	var models = []
	for i in range(8):
		models.append({"id": "m%d" % (i + 1), "wounds": 1, "current_wounds": 1, "alive": true, "model_type": "loota_deffgun"})
	for i in range(2):
		models.append({"id": "m%d" % (i + 9), "wounds": 1, "current_wounds": 1, "alive": true, "model_type": "loota_kmb"})
	models.append({"id": "m11", "wounds": 1, "current_wounds": 1, "alive": true, "model_type": "spanner"})

	return {"units": {"U_LOOTAS": {
		"id": "U_LOOTAS",
		"meta": {
			"name": "Lootas",
			"weapons": [
				{"name": "Deffgun", "type": "Ranged", "range": "48", "attacks": "2", "strength": "8", "ap": "-1", "damage": "2", "ballistic_skill": "6", "special_rules": "heavy, rapid fire 1"},
				{"name": "Kustom mega-blasta", "type": "Ranged", "range": "24", "attacks": "3", "strength": "9", "ap": "-2", "damage": "D6", "ballistic_skill": "5", "special_rules": "hazardous"},
				{"name": "Close combat weapon", "type": "Melee", "range": "Melee", "attacks": "2", "strength": "4", "ap": "0", "damage": "1", "weapon_skill": "3"}
			],
			"model_profiles": {
				"loota_deffgun": {"label": "Loota (Deffgun)", "stats_override": {}, "weapons": ["Deffgun", "Close combat weapon"], "transport_slots": 1},
				"loota_kmb": {"label": "Loota (KMB)", "stats_override": {}, "weapons": ["Kustom mega-blasta", "Close combat weapon"], "transport_slots": 1},
				"spanner": {"label": "Spanner", "stats_override": {"ballistic_skill": 4}, "weapons": ["Kustom mega-blasta", "Close combat weapon"], "transport_slots": 1}
			},
			"stats": {"move": 6, "toughness": 5, "save": 5, "wounds": 1}
		},
		"models": models
	}}}

func _make_shooting_board() -> Dictionary:
	# Build a board with Lootas and a target unit for hit resolution
	var lootas_board = _make_lootas_board()
	# Add positions for models (needed for shooting)
	for model in lootas_board["units"]["U_LOOTAS"]["models"]:
		model["position"] = Vector2(100, 100)
		model["base_mm"] = 32

	# Add a target unit
	var target_models = []
	for i in range(5):
		target_models.append({
			"id": "t%d" % (i + 1),
			"wounds": 2,
			"current_wounds": 2,
			"alive": true,
			"position": Vector2(400, 100),
			"base_mm": 32
		})
	lootas_board["units"]["U_TARGET"] = {
		"id": "U_TARGET",
		"meta": {
			"name": "Target Squad",
			"weapons": [],
			"stats": {"move": 6, "toughness": 4, "save": 4, "wounds": 2}
		},
		"models": target_models
	}
	return lootas_board
