extends SceneTree

# Test: MA-7 get_unit_melee_weapons() per-model profile support
# Verifies that:
# 1. Units with model_profiles assign per-model melee weapons based on model_type
# 2. Units without model_profiles still assign all melee weapons to all models
# 3. Dead models are excluded
# 4. Ranged weapons are not included
# Usage: godot --headless --path . -s tests/test_ma7_melee_weapons.gd

var _re = null

func _initialize():
	# Wait one frame for autoloads to be ready
	await create_timer(0.1).timeout
	_re = root.get_node("RulesEngine")
	if _re == null:
		print("FAIL: Could not get RulesEngine autoload")
		quit(1)
		return
	_run_tests()

func _run_tests():
	print("\n=== Test get_unit_melee_weapons() per-model profiles (MA-7) ===\n")
	var passed = 0
	var failed = 0

	# --- Test 1: Sergeant gets Power fist only (per profile) ---
	print("--- Test 1: Sergeant gets Power fist only ---")
	var board = _make_intercessor_board()
	var result = _re.get_unit_melee_weapons("U_INTER", board)
	# m0 = index 0 = sergeant
	if result.has("m0") and "Power fist" in result["m0"] and "Close combat weapon" not in result["m0"]:
		print("  PASS: Sergeant (m0) has Power fist, no Close combat weapon")
		passed += 1
	else:
		print("  FAIL: Sergeant (m0) weapons: %s" % str(result.get("m0", [])))
		failed += 1

	# --- Test 2: Regular intercessors get Close combat weapon only ---
	print("\n--- Test 2: Regular intercessors get Close combat weapon only ---")
	if result.has("m1") and "Close combat weapon" in result["m1"] and "Power fist" not in result["m1"]:
		print("  PASS: Intercessor (m1) has Close combat weapon, no Power fist")
		passed += 1
	else:
		print("  FAIL: Intercessor (m1) weapons: %s" % str(result.get("m1", [])))
		failed += 1

	# --- Test 3: Second regular intercessor also gets Close combat weapon ---
	print("\n--- Test 3: Second regular intercessor correct ---")
	if result.has("m2") and "Close combat weapon" in result["m2"] and "Power fist" not in result["m2"]:
		print("  PASS: Intercessor (m2) has Close combat weapon, no Power fist")
		passed += 1
	else:
		print("  FAIL: Intercessor (m2) weapons: %s" % str(result.get("m2", [])))
		failed += 1

	# --- Test 4: Dead model excluded ---
	print("\n--- Test 4: Dead model excluded ---")
	if not result.has("m3"):
		print("  PASS: Dead model (m3) not in results")
		passed += 1
	else:
		print("  FAIL: Dead model (m3) should not be in results, got: %s" % str(result.get("m3", [])))
		failed += 1

	# --- Test 5: Ranged weapons excluded ---
	print("\n--- Test 5: Ranged weapons excluded from melee results ---")
	var ranged_found = false
	for model_id in result:
		if "Bolt rifle" in result[model_id] or "Bolt pistol" in result[model_id]:
			ranged_found = true
			break
	if not ranged_found:
		print("  PASS: No ranged weapons in melee results")
		passed += 1
	else:
		print("  FAIL: Found ranged weapons in melee results")
		failed += 1

	# --- Test 6: Fallback — unit without model_profiles gets all melee weapons ---
	print("\n--- Test 6: Unit without model_profiles gets all melee weapons ---")
	var basic_board = _make_basic_board()
	var basic_result = _re.get_unit_melee_weapons("U_BASIC", basic_board)
	var all_ok = basic_result.size() == 3
	for model_id in basic_result:
		if "Close combat weapon" not in basic_result[model_id]:
			all_ok = false
		if "Power sword" not in basic_result[model_id]:
			all_ok = false
	if all_ok:
		print("  PASS: All 3 alive models have both melee weapons")
		passed += 1
	else:
		print("  FAIL: Expected 3 models with [Close combat weapon, Power sword], got: %s" % str(basic_result))
		failed += 1

	# --- Test 7: Lootas — all model types get Close combat weapon ---
	print("\n--- Test 7: Lootas — all profiles have Close combat weapon ---")
	var lootas_board = _make_lootas_board()
	var lootas_result = _re.get_unit_melee_weapons("U_LOOTAS", lootas_board)
	var lootas_ok = lootas_result.size() == 4  # 4 alive, 1 dead
	for model_id in lootas_result:
		if "Close combat weapon" not in lootas_result[model_id]:
			lootas_ok = false
		# Ranged weapons should NOT appear
		if "Deffgun" in lootas_result[model_id] or "Kustom mega-blasta" in lootas_result[model_id]:
			lootas_ok = false
	if lootas_ok:
		print("  PASS: 4 alive Lootas models each have Close combat weapon only")
		passed += 1
	else:
		print("  FAIL: Lootas melee results: %s" % str(lootas_result))
		failed += 1

	# --- Test 8: Empty unit returns empty ---
	print("\n--- Test 8: Nonexistent unit returns empty ---")
	var empty_result = _re.get_unit_melee_weapons("NONEXISTENT", basic_board)
	if empty_result.is_empty():
		print("  PASS: Nonexistent unit returns empty dict")
		passed += 1
	else:
		print("  FAIL: Expected empty, got: %s" % str(empty_result))
		failed += 1

	# --- Test 9: Model with no model_type in profiled unit gets fallback ---
	print("\n--- Test 9: Model without model_type in profiled unit gets all melee ---")
	var mixed_board = _make_mixed_board()
	var mixed_result = _re.get_unit_melee_weapons("U_MIXED", mixed_board)
	# m0 = typed model (type_a) -> only WeaponA_melee
	# m1 = untyped model -> all melee weapons (fallback)
	var m0_ok = mixed_result.has("m0") and "WeaponA_melee" in mixed_result["m0"] and "WeaponB_melee" not in mixed_result["m0"]
	var m1_ok = mixed_result.has("m1") and "WeaponA_melee" in mixed_result["m1"] and "WeaponB_melee" in mixed_result["m1"]
	if m0_ok and m1_ok:
		print("  PASS: Typed model gets profile weapons, untyped gets all melee")
		passed += 1
	else:
		print("  FAIL: m0=%s, m1=%s" % [str(mixed_result.get("m0", [])), str(mixed_result.get("m1", []))])
		failed += 1

	# --- Test 10: Live army data — Intercessors from space_marines.json ---
	print("\n--- Test 10: Live army data — SM Intercessors melee weapons ---")
	var sm_data = _load_army_json("space_marines")
	if sm_data.is_empty():
		print("  FAIL: Could not load space_marines.json")
		failed += 1
	else:
		var sm_board = {"units": sm_data.get("units", {})}
		var sm_result = _re.get_unit_melee_weapons("U_INTERCESSORS_A", sm_board)
		# m0 = sergeant (intercessor_sergeant) -> Power fist
		# m1-m4 = intercessors -> Close combat weapon
		var sgt_ok = sm_result.has("m0") and "Power fist" in sm_result["m0"] and "Close combat weapon" not in sm_result["m0"]
		var troops_ok = true
		for i in range(1, 5):
			var mid = "m" + str(i)
			if not sm_result.has(mid) or "Close combat weapon" not in sm_result[mid] or "Power fist" in sm_result[mid]:
				troops_ok = false
		if sgt_ok and troops_ok:
			print("  PASS: SM Sergeant has Power fist, 4 Intercessors have Close combat weapon")
			passed += 1
		else:
			print("  FAIL: SM melee weapons: %s" % str(sm_result))
			failed += 1

	# --- Summary ---
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)

func _make_intercessor_board() -> Dictionary:
	return {"units": {"U_INTER": {
		"id": "U_INTER",
		"meta": {
			"name": "Intercessor Squad",
			"weapons": [
				{"name": "Bolt rifle", "type": "Ranged", "range": "24", "attacks": "2", "strength": "4", "ap": "-1", "damage": "1"},
				{"name": "Bolt pistol", "type": "Ranged", "range": "12", "attacks": "1", "strength": "4", "ap": "0", "damage": "1"},
				{"name": "Close combat weapon", "type": "Melee", "range": "Melee", "attacks": "3", "strength": "4", "ap": "0", "damage": "1"},
				{"name": "Power fist", "type": "Melee", "range": "Melee", "attacks": "3", "strength": "8", "ap": "-2", "damage": "2"}
			],
			"model_profiles": {
				"intercessor": {"label": "Intercessor", "weapons": ["Bolt rifle", "Bolt pistol", "Close combat weapon"]},
				"intercessor_sergeant": {"label": "Intercessor Sergeant", "weapons": ["Bolt rifle", "Bolt pistol", "Power fist"]}
			}
		},
		"models": [
			{"id": "m1", "wounds": 2, "current_wounds": 2, "alive": true, "model_type": "intercessor_sergeant"},
			{"id": "m2", "wounds": 2, "current_wounds": 2, "alive": true, "model_type": "intercessor"},
			{"id": "m3", "wounds": 2, "current_wounds": 2, "alive": true, "model_type": "intercessor"},
			{"id": "m4", "wounds": 2, "current_wounds": 2, "alive": false, "model_type": "intercessor"}
		]
	}}}

func _make_basic_board() -> Dictionary:
	return {"units": {"U_BASIC": {
		"id": "U_BASIC",
		"meta": {
			"name": "Basic Squad",
			"weapons": [
				{"name": "Bolt rifle", "type": "Ranged", "range": "30", "attacks": "2", "strength": "4", "ap": "-1", "damage": "1"},
				{"name": "Close combat weapon", "type": "Melee", "range": "Melee", "attacks": "3", "strength": "4", "ap": "0", "damage": "1"},
				{"name": "Power sword", "type": "Melee", "range": "Melee", "attacks": "3", "strength": "5", "ap": "-2", "damage": "1"}
			]
		},
		"models": [
			{"id": "m1", "wounds": 2, "current_wounds": 2, "alive": true},
			{"id": "m2", "wounds": 2, "current_wounds": 2, "alive": true},
			{"id": "m3", "wounds": 2, "current_wounds": 2, "alive": true}
		]
	}}}

func _make_lootas_board() -> Dictionary:
	return {"units": {"U_LOOTAS": {
		"id": "U_LOOTAS",
		"meta": {
			"name": "Lootas",
			"weapons": [
				{"name": "Deffgun", "type": "Ranged", "range": "48", "attacks": "2", "strength": "8", "ap": "-1", "damage": "2"},
				{"name": "Kustom mega-blasta", "type": "Ranged", "range": "24", "attacks": "3", "strength": "9", "ap": "-2", "damage": "D6"},
				{"name": "Close combat weapon", "type": "Melee", "range": "Melee", "attacks": "2", "strength": "4", "ap": "0", "damage": "1"}
			],
			"model_profiles": {
				"loota_deffgun": {"label": "Loota (Deffgun)", "weapons": ["Deffgun", "Close combat weapon"]},
				"loota_kmb": {"label": "Loota (KMB)", "weapons": ["Kustom mega-blasta", "Close combat weapon"]},
				"spanner": {"label": "Spanner", "weapons": ["Kustom mega-blasta", "Close combat weapon"]}
			}
		},
		"models": [
			{"id": "m1", "wounds": 1, "current_wounds": 1, "alive": true, "model_type": "loota_deffgun"},
			{"id": "m2", "wounds": 1, "current_wounds": 1, "alive": true, "model_type": "loota_deffgun"},
			{"id": "m3", "wounds": 1, "current_wounds": 1, "alive": true, "model_type": "loota_kmb"},
			{"id": "m4", "wounds": 1, "current_wounds": 1, "alive": true, "model_type": "spanner"},
			{"id": "m5", "wounds": 1, "current_wounds": 1, "alive": false, "model_type": "loota_deffgun"}
		]
	}}}

func _make_mixed_board() -> Dictionary:
	return {"units": {"U_MIXED": {
		"id": "U_MIXED",
		"meta": {
			"name": "Mixed Unit",
			"weapons": [
				{"name": "WeaponA_melee", "type": "Melee", "range": "Melee", "attacks": "2", "strength": "4", "ap": "0", "damage": "1"},
				{"name": "WeaponB_melee", "type": "Melee", "range": "Melee", "attacks": "3", "strength": "5", "ap": "-1", "damage": "1"},
				{"name": "Ranged_gun", "type": "Ranged", "range": "24", "attacks": "1", "strength": "4", "ap": "0", "damage": "1"}
			],
			"model_profiles": {
				"type_a": {"label": "Type A", "weapons": ["WeaponA_melee", "Ranged_gun"]}
			}
		},
		"models": [
			{"id": "m1", "wounds": 1, "current_wounds": 1, "alive": true, "model_type": "type_a"},
			{"id": "m2", "wounds": 1, "current_wounds": 1, "alive": true}
		]
	}}}

func _load_army_json(army_name: String) -> Dictionary:
	var file_path = "res://armies/%s.json" % army_name
	if not FileAccess.file_exists(file_path):
		print("  ERROR: File not found: %s" % file_path)
		return {}
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print("  ERROR: Could not open file: %s" % file_path)
		return {}
	var json_string = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(json_string)
	if err != OK:
		print("  ERROR: JSON parse error: %s" % json.get_error_message())
		return {}
	return json.data
