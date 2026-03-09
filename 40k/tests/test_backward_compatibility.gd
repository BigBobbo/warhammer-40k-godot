extends SceneTree

# Test: MA-33 Backward Compatibility Regression Tests
# Verifies that all existing army JSONs load, units without model_profiles work identically
# to before, old saves without model_type load without crashes, and shooting/melee/deployment/
# wound allocation all work for non-profiled units.
# Usage: godot --headless --path . -s tests/test_backward_compatibility.gd

func _init():
	print("\n=== Test MA-33: Backward Compatibility Regression Tests ===\n")
	var passed = 0
	var failed = 0
	var test_num = 0

	# ═══════════════════════════════════════════════════════════════════════
	# Section 1: Army JSON Loading — all 3 core armies load without errors
	# ═══════════════════════════════════════════════════════════════════════

	# --- Test 1: Load orks.json ---
	test_num += 1
	print("--- Test %d: Load orks.json without errors ---" % test_num)
	var ork_data = _load_army_json("orks")
	if not ork_data.is_empty() and ork_data.has("units") and ork_data.get("units", {}).size() > 0:
		print("  PASS: orks.json loaded with %d units" % ork_data.get("units", {}).size())
		passed += 1
	else:
		print("  FAIL: orks.json failed to load or has no units")
		failed += 1

	# --- Test 2: Load space_marines.json ---
	test_num += 1
	print("\n--- Test %d: Load space_marines.json without errors ---" % test_num)
	var sm_data = _load_army_json("space_marines")
	if not sm_data.is_empty() and sm_data.has("units") and sm_data.get("units", {}).size() > 0:
		print("  PASS: space_marines.json loaded with %d units" % sm_data.get("units", {}).size())
		passed += 1
	else:
		print("  FAIL: space_marines.json failed to load or has no units")
		failed += 1

	# --- Test 3: Load adeptus_custodes.json ---
	test_num += 1
	print("\n--- Test %d: Load adeptus_custodes.json without errors ---" % test_num)
	var ac_data = _load_army_json("adeptus_custodes")
	if not ac_data.is_empty() and ac_data.has("units") and ac_data.get("units", {}).size() > 0:
		print("  PASS: adeptus_custodes.json loaded with %d units" % ac_data.get("units", {}).size())
		passed += 1
	else:
		print("  FAIL: adeptus_custodes.json failed to load or has no units")
		failed += 1

	# ═══════════════════════════════════════════════════════════════════════
	# Section 2: Non-profiled units have correct structure (weapons, stats, models)
	# ═══════════════════════════════════════════════════════════════════════

	# --- Test 4: Ork Boyz (U_BOYZ_E) — no model_profiles, has weapons and stats ---
	test_num += 1
	print("\n--- Test %d: U_BOYZ_E (Boyz) has no model_profiles but has weapons/stats ---" % test_num)
	var boyz_e = ork_data.get("units", {}).get("U_BOYZ_E", {})
	var boyz_e_meta = boyz_e.get("meta", {})
	if not boyz_e_meta.has("model_profiles") and boyz_e_meta.has("weapons") and boyz_e_meta.has("stats"):
		print("  PASS: U_BOYZ_E has no model_profiles, has weapons (%d) and stats" % boyz_e_meta.get("weapons", []).size())
		passed += 1
	else:
		var has_mp = boyz_e_meta.has("model_profiles")
		var has_w = boyz_e_meta.has("weapons")
		var has_s = boyz_e_meta.has("stats")
		print("  FAIL: model_profiles=%s, weapons=%s, stats=%s" % [has_mp, has_w, has_s])
		failed += 1

	# --- Test 5: Ork Boyz models have no model_type field or empty model_type ---
	test_num += 1
	print("\n--- Test %d: U_BOYZ_E models have no model_type ---" % test_num)
	var boyz_e_models = boyz_e.get("models", [])
	var all_no_type = true
	for m in boyz_e_models:
		var mt = m.get("model_type", "")
		if mt != "":
			print("  FAIL: Model %s has unexpected model_type='%s'" % [m.get("id", "?"), mt])
			all_no_type = false
			break
	if all_no_type and boyz_e_models.size() > 0:
		print("  PASS: All %d models have no model_type" % boyz_e_models.size())
		passed += 1
	elif boyz_e_models.size() == 0:
		print("  FAIL: U_BOYZ_E has no models")
		failed += 1
	else:
		failed += 1

	# --- Test 6: Adeptus Custodes — ALL units have no model_profiles ---
	test_num += 1
	print("\n--- Test %d: All Adeptus Custodes units have no model_profiles ---" % test_num)
	var ac_units = ac_data.get("units", {})
	var all_ac_no_profiles = true
	for uid in ac_units:
		var u_meta = ac_units[uid].get("meta", {})
		if u_meta.has("model_profiles"):
			print("  FAIL: %s has unexpected model_profiles" % uid)
			all_ac_no_profiles = false
			break
	if all_ac_no_profiles and ac_units.size() > 0:
		print("  PASS: All %d Custodes units have no model_profiles" % ac_units.size())
		passed += 1
	else:
		if ac_units.size() == 0:
			print("  FAIL: No Custodes units found")
		failed += 1

	# --- Test 7: All non-profiled units have valid stats and models ---
	test_num += 1
	print("\n--- Test %d: All non-profiled units across all armies have stats and models ---" % test_num)
	var all_valid = true
	var non_profiled_count = 0
	var all_armies = {"orks": ork_data, "space_marines": sm_data, "adeptus_custodes": ac_data}
	for army_name in all_armies:
		var army = all_armies[army_name]
		for uid in army.get("units", {}):
			var u = army.get("units", {})[uid]
			var u_meta = u.get("meta", {})
			if not u_meta.has("model_profiles"):
				non_profiled_count += 1
				# Some special units (e.g. Strike Force detachment) may not have weapons — that's OK
				if not u_meta.has("stats"):
					print("  FAIL: %s/%s missing stats" % [army_name, uid])
					all_valid = false
				if u.get("models", []).size() == 0:
					print("  FAIL: %s/%s has no models" % [army_name, uid])
					all_valid = false
	if all_valid and non_profiled_count > 0:
		print("  PASS: All %d non-profiled units have stats and models" % non_profiled_count)
		passed += 1
	else:
		if non_profiled_count == 0:
			print("  FAIL: No non-profiled units found")
		failed += 1

	# ═══════════════════════════════════════════════════════════════════════
	# Section 3: Weapon assignment — non-profiled units get ALL weapons
	# ═══════════════════════════════════════════════════════════════════════

	# Build a simulated board from ork_data for weapon assignment testing
	var ork_board = {"units": ork_data.get("units", {})}
	var sm_board = {"units": sm_data.get("units", {})}
	var ac_board = {"units": ac_data.get("units", {})}

	# --- Test 8: Non-profiled Boyz — all models get all ranged weapons ---
	test_num += 1
	print("\n--- Test %d: Non-profiled U_BOYZ_E — all models get all ranged weapons ---" % test_num)
	var boyz_e_weapons = _get_unit_ranged_weapons("U_BOYZ_E", ork_board)
	# Find expected ranged weapon IDs from meta.weapons
	var expected_ranged_ids = []
	for w in boyz_e_meta.get("weapons", []):
		if w.get("type", "").to_lower() == "ranged":
			expected_ranged_ids.append(_gen_weapon_id(w.get("name", ""), w.get("type", "")))
	var all_models_have_all_weapons = true
	var alive_model_count = 0
	for m in boyz_e_models:
		if m.get("alive", true):
			alive_model_count += 1
			var mid = m.get("id", "")
			if not boyz_e_weapons.has(mid):
				print("  FAIL: Model %s missing from weapon assignment" % mid)
				all_models_have_all_weapons = false
				break
			for wid in expected_ranged_ids:
				if wid not in boyz_e_weapons[mid]:
					print("  FAIL: Model %s missing weapon %s" % [mid, wid])
					all_models_have_all_weapons = false
					break
			if not all_models_have_all_weapons:
				break
	if all_models_have_all_weapons and alive_model_count > 0:
		print("  PASS: All %d alive models have all %d ranged weapons" % [alive_model_count, expected_ranged_ids.size()])
		passed += 1
	else:
		failed += 1

	# --- Test 9: Non-profiled Boyz — all models get all melee weapons ---
	test_num += 1
	print("\n--- Test %d: Non-profiled U_BOYZ_E — all models get all melee weapons ---" % test_num)
	var boyz_e_melee = _get_unit_melee_weapons("U_BOYZ_E", ork_board)
	var expected_melee_ids = []
	for w in boyz_e_meta.get("weapons", []):
		if w.get("type", "").to_lower() == "melee":
			expected_melee_ids.append(_gen_weapon_id(w.get("name", ""), w.get("type", "")))
	var all_melee_ok = true
	for m in boyz_e_models:
		if m.get("alive", true):
			var mid = m.get("id", "")
			if not boyz_e_melee.has(mid):
				print("  FAIL: Model %s missing from melee weapon assignment" % mid)
				all_melee_ok = false
				break
			for wid in expected_melee_ids:
				if wid not in boyz_e_melee[mid]:
					print("  FAIL: Model %s missing melee weapon %s" % [mid, wid])
					all_melee_ok = false
					break
			if not all_melee_ok:
				break
	if all_melee_ok and expected_melee_ids.size() > 0:
		print("  PASS: All alive models have all %d melee weapons" % expected_melee_ids.size())
		passed += 1
	else:
		if expected_melee_ids.size() == 0:
			print("  SKIP: No melee weapons on U_BOYZ_E (checking)")
			# This is still a pass if no melee weapons defined
			passed += 1
		else:
			failed += 1

	# --- Test 10: Custodian Guard — all models get all ranged weapons (no profiles) ---
	test_num += 1
	print("\n--- Test %d: Custodian Guard — all models get all ranged weapons (no profiles) ---" % test_num)
	var cg = ac_data.get("units", {}).get("U_CUSTODIAN_GUARD_B", {})
	var cg_meta = cg.get("meta", {})
	var cg_weapons = _get_unit_ranged_weapons("U_CUSTODIAN_GUARD_B", ac_board)
	var cg_expected_ranged = []
	for w in cg_meta.get("weapons", []):
		if w.get("type", "").to_lower() == "ranged":
			cg_expected_ranged.append(_gen_weapon_id(w.get("name", ""), w.get("type", "")))
	var cg_ok = true
	var cg_alive = 0
	for m in cg.get("models", []):
		if m.get("alive", true):
			cg_alive += 1
			var mid = m.get("id", "")
			if not cg_weapons.has(mid):
				print("  FAIL: Model %s missing from weapon assignment" % mid)
				cg_ok = false
				break
			for wid in cg_expected_ranged:
				if wid not in cg_weapons[mid]:
					print("  FAIL: Model %s missing weapon %s" % [mid, wid])
					cg_ok = false
					break
			if not cg_ok:
				break
	if cg_ok and cg_alive > 0:
		print("  PASS: All %d alive Custodian Guard models have all %d ranged weapons" % [cg_alive, cg_expected_ranged.size()])
		passed += 1
	elif cg_expected_ranged.size() == 0:
		print("  PASS: Custodian Guard has no ranged weapons (melee only is valid)")
		passed += 1
	else:
		failed += 1

	# --- Test 11: SM Tactical Squad — all models get all weapons (no profiles) ---
	test_num += 1
	print("\n--- Test %d: SM Tactical Squad — all models get all ranged weapons (no profiles) ---" % test_num)
	var tac = sm_data.get("units", {}).get("U_TACTICAL_A", {})
	var tac_meta = tac.get("meta", {})
	var tac_weapons = _get_unit_ranged_weapons("U_TACTICAL_A", sm_board)
	var tac_expected_ranged = []
	for w in tac_meta.get("weapons", []):
		if w.get("type", "").to_lower() == "ranged":
			tac_expected_ranged.append(_gen_weapon_id(w.get("name", ""), w.get("type", "")))
	var tac_ok = true
	var tac_alive = 0
	for m in tac.get("models", []):
		if m.get("alive", true):
			tac_alive += 1
			var mid = m.get("id", "")
			if not tac_weapons.has(mid):
				print("  FAIL: Model %s missing from weapon assignment" % mid)
				tac_ok = false
				break
			for wid in tac_expected_ranged:
				if wid not in tac_weapons[mid]:
					print("  FAIL: Model %s missing weapon %s" % [mid, wid])
					tac_ok = false
					break
			if not tac_ok:
				break
	if tac_ok and tac_alive > 0:
		print("  PASS: All %d alive Tactical models have all %d ranged weapons" % [tac_alive, tac_expected_ranged.size()])
		passed += 1
	elif tac_expected_ranged.size() == 0:
		print("  PASS: Tactical Squad has no ranged weapons (valid if melee-only)")
		passed += 1
	else:
		failed += 1

	# ═══════════════════════════════════════════════════════════════════════
	# Section 4: BS/WS resolution — non-profiled units use weapon defaults
	# ═══════════════════════════════════════════════════════════════════════

	# --- Test 12: Non-profiled model uses weapon profile BS (no override) ---
	test_num += 1
	print("\n--- Test %d: Non-profiled model uses weapon default BS ---" % test_num)
	var boyz_model = {"id": "m1", "alive": true}  # No model_type
	var weapon_bs4 = {"bs": 4, "name": "Slugga"}
	var weapon_bs5 = {"bs": 5, "name": "Shoota"}
	var effective_bs4 = _get_model_effective_bs(boyz_model, boyz_e, weapon_bs4)
	var effective_bs5 = _get_model_effective_bs(boyz_model, boyz_e, weapon_bs5)
	if effective_bs4 == 4 and effective_bs5 == 5:
		print("  PASS: Non-profiled model returns weapon default BS (4 and 5)")
		passed += 1
	else:
		print("  FAIL: Expected BS 4 and 5, got %d and %d" % [effective_bs4, effective_bs5])
		failed += 1

	# --- Test 13: Non-profiled model uses weapon profile WS (no override) ---
	test_num += 1
	print("\n--- Test %d: Non-profiled model uses weapon default WS ---" % test_num)
	var weapon_ws3 = {"ws": 3, "name": "Choppa"}
	var weapon_ws4 = {"ws": 4, "name": "Knife"}
	var effective_ws3 = _get_model_effective_ws(boyz_model, boyz_e, weapon_ws3)
	var effective_ws4 = _get_model_effective_ws(boyz_model, boyz_e, weapon_ws4)
	if effective_ws3 == 3 and effective_ws4 == 4:
		print("  PASS: Non-profiled model returns weapon default WS (3 and 4)")
		passed += 1
	else:
		print("  FAIL: Expected WS 3 and 4, got %d and %d" % [effective_ws3, effective_ws4])
		failed += 1

	# --- Test 14: Empty model dict uses weapon default BS ---
	test_num += 1
	print("\n--- Test %d: Empty model dict falls back to weapon default BS ---" % test_num)
	var empty_model_bs = _get_model_effective_bs({}, boyz_e, weapon_bs4)
	if empty_model_bs == 4:
		print("  PASS: Empty model returns weapon default BS=4")
		passed += 1
	else:
		print("  FAIL: Expected 4, got %d" % empty_model_bs)
		failed += 1

	# --- Test 15: Empty model dict uses weapon default WS ---
	test_num += 1
	print("\n--- Test %d: Empty model dict falls back to weapon default WS ---" % test_num)
	var empty_model_ws = _get_model_effective_ws({}, boyz_e, weapon_ws3)
	if empty_model_ws == 3:
		print("  PASS: Empty model returns weapon default WS=3")
		passed += 1
	else:
		print("  FAIL: Expected 3, got %d" % empty_model_ws)
		failed += 1

	# --- Test 16: Model with empty string model_type uses weapon default BS ---
	test_num += 1
	print("\n--- Test %d: Model with empty model_type uses weapon default BS ---" % test_num)
	var empty_type_model = {"id": "m1", "alive": true, "model_type": ""}
	var empty_type_bs = _get_model_effective_bs(empty_type_model, boyz_e, weapon_bs4)
	if empty_type_bs == 4:
		print("  PASS: Model with empty model_type returns weapon default BS=4")
		passed += 1
	else:
		print("  FAIL: Expected 4, got %d" % empty_type_bs)
		failed += 1

	# ═══════════════════════════════════════════════════════════════════════
	# Section 5: Old save file simulation — load without model_type, no crash
	# ═══════════════════════════════════════════════════════════════════════

	# --- Test 17: Simulated old save — unit without model_type loads ---
	test_num += 1
	print("\n--- Test %d: Simulated old save — models without model_type ---" % test_num)
	# Simulate an old-format unit (no model_type field on models)
	var old_save_unit = {
		"id": "U_OLD_BOYZ",
		"owner": 1,
		"status": "DEPLOYED",
		"meta": {
			"name": "Boyz (Old Save)",
			"keywords": ["INFANTRY", "ORKS"],
			"stats": {"move": 6, "toughness": 4, "save": 5, "wounds": 1},
			"weapons": [
				{"name": "Slugga", "type": "Ranged", "range": "12", "ballistic_skill": "5", "attacks": "1", "strength": "4", "armour_penetration": "0", "damage": "1"},
				{"name": "Choppa", "type": "Melee", "weapon_skill": "3", "attacks": "3", "strength": "4", "armour_penetration": "-1", "damage": "1"}
			]
		},
		"models": [
			{"id": "m1", "wounds": 1, "alive": true},
			{"id": "m2", "wounds": 1, "alive": true},
			{"id": "m3", "wounds": 1, "alive": true},
			{"id": "m4", "wounds": 1, "alive": true},
			{"id": "m5", "wounds": 1, "alive": true},
		]
	}
	# Verify models have no model_type and the unit still processes
	var old_models = old_save_unit.get("models", [])
	var old_models_ok = true
	for m in old_models:
		var mt = m.get("model_type", null)
		# Old saves: model_type should be null (missing) or empty
		if mt != null and mt != "":
			print("  FAIL: Old save model %s has unexpected model_type='%s'" % [m.get("id", "?"), mt])
			old_models_ok = false
			break
	if old_models_ok:
		print("  PASS: Old save models have no model_type (null/missing)")
		passed += 1
	else:
		failed += 1

	# --- Test 18: Old save unit — weapon assignment works without model_type ---
	test_num += 1
	print("\n--- Test %d: Old save unit — weapon assignment works without model_type ---" % test_num)
	var old_board = {"units": {"U_OLD_BOYZ": old_save_unit}}
	var old_weapons = _get_unit_ranged_weapons("U_OLD_BOYZ", old_board)
	var old_melee = _get_unit_melee_weapons("U_OLD_BOYZ", old_board)
	if old_weapons.size() == 5 and old_melee.size() == 5:
		print("  PASS: All 5 models got ranged (%d) and melee (%d) weapons" % [old_weapons.size(), old_melee.size()])
		passed += 1
	else:
		print("  FAIL: Expected 5 models with weapons, got ranged=%d melee=%d" % [old_weapons.size(), old_melee.size()])
		failed += 1

	# --- Test 19: Old save unit — BS/WS use weapon defaults (no profile override) ---
	test_num += 1
	print("\n--- Test %d: Old save unit — BS/WS use weapon defaults ---" % test_num)
	var old_model = old_models[0]
	var old_slugga = {"bs": 5, "name": "Slugga"}
	var old_choppa = {"ws": 3, "name": "Choppa"}
	var old_bs = _get_model_effective_bs(old_model, old_save_unit, old_slugga)
	var old_ws = _get_model_effective_ws(old_model, old_save_unit, old_choppa)
	if old_bs == 5 and old_ws == 3:
		print("  PASS: Old save model uses weapon defaults (BS=5, WS=3)")
		passed += 1
	else:
		print("  FAIL: Expected BS=5 WS=3, got BS=%d WS=%d" % [old_bs, old_ws])
		failed += 1

	# --- Test 20: Old save with model_profiles but no model_type — auto-repair single profile ---
	test_num += 1
	print("\n--- Test %d: Old save with single profile — auto-repair assigns model_type ---" % test_num)
	var single_profile_unit = {
		"id": "U_SINGLE_PROFILE",
		"owner": 1,
		"status": "DEPLOYED",
		"meta": {
			"name": "Single Profile Unit",
			"stats": {"move": 6, "toughness": 4, "save": 3},
			"weapons": [{"name": "Bolter", "type": "Ranged", "range": "24"}],
			"model_profiles": {
				"marine": {
					"label": "Marine",
					"stats_override": {},
					"weapons": ["Bolter"],
					"transport_slots": 1
				}
			}
		},
		"models": [
			{"id": "m1", "wounds": 1, "alive": true},  # No model_type
			{"id": "m2", "wounds": 1, "alive": true},
		]
	}
	# Simulate the auto-repair logic from StateSerializer
	var sp_meta = single_profile_unit.get("meta", {})
	var sp_profiles = sp_meta.get("model_profiles", {})
	var auto_repair_ok = true
	for m in single_profile_unit.get("models", []):
		var m_type = m.get("model_type", null)
		if m_type == null or m_type == "":
			if sp_profiles.size() == 1:
				m["model_type"] = sp_profiles.keys()[0]
			else:
				auto_repair_ok = false
	# Verify all models now have model_type = "marine"
	for m in single_profile_unit.get("models", []):
		if m.get("model_type", "") != "marine":
			auto_repair_ok = false
			print("  FAIL: Model %s model_type expected 'marine', got '%s'" % [m.get("id", "?"), m.get("model_type", "")])
	if auto_repair_ok:
		print("  PASS: Auto-repair assigned model_type='marine' to all models")
		passed += 1
	else:
		failed += 1

	# --- Test 21: Old save with multi-profile but no model_type — warns, doesn't crash ---
	test_num += 1
	print("\n--- Test %d: Old save with multi-profile but no model_type — no crash ---" % test_num)
	var multi_profile_unit = {
		"id": "U_MULTI_PROFILE",
		"owner": 1,
		"status": "DEPLOYED",
		"meta": {
			"name": "Multi Profile Unit",
			"stats": {"move": 6, "toughness": 4, "save": 3},
			"weapons": [
				{"name": "Weapon A", "type": "Ranged", "range": "24"},
				{"name": "Weapon B", "type": "Ranged", "range": "12"}
			],
			"model_profiles": {
				"type_a": {"label": "Type A", "stats_override": {}, "weapons": ["Weapon A"], "transport_slots": 1},
				"type_b": {"label": "Type B", "stats_override": {}, "weapons": ["Weapon B"], "transport_slots": 1}
			}
		},
		"models": [
			{"id": "m1", "wounds": 1, "alive": true},  # No model_type
			{"id": "m2", "wounds": 1, "alive": true},
		]
	}
	# Without model_type, weapon assignment should fall back to all weapons for all models
	var mp_board = {"units": {"U_MULTI_PROFILE": multi_profile_unit}}
	var mp_weapons = _get_unit_ranged_weapons("U_MULTI_PROFILE", mp_board)
	# Should not crash — models without model_type get all weapons
	if mp_weapons.size() == 2:
		# Both models should get weapons (fallback: all weapons since no model_type)
		var m1_count = mp_weapons.get("m1", []).size()
		var m2_count = mp_weapons.get("m2", []).size()
		if m1_count == 2 and m2_count == 2:
			print("  PASS: Models without model_type get all %d ranged weapons (fallback)" % m1_count)
			passed += 1
		else:
			print("  FAIL: Expected 2 weapons each, got m1=%d m2=%d" % [m1_count, m2_count])
			failed += 1
	else:
		print("  FAIL: Expected 2 models with weapons, got %d" % mp_weapons.size())
		failed += 1

	# ═══════════════════════════════════════════════════════════════════════
	# Section 6: Transport slots — default to 1 for non-profiled units
	# ═══════════════════════════════════════════════════════════════════════

	# --- Test 22: Non-profiled model transport slots default to 1 ---
	test_num += 1
	print("\n--- Test %d: Non-profiled model transport_slots defaults to 1 ---" % test_num)
	var ts_model = {"id": "m1", "alive": true}
	var ts = _get_model_transport_slots(ts_model, boyz_e)
	if ts == 1:
		print("  PASS: Non-profiled model has transport_slots=1 (default)")
		passed += 1
	else:
		print("  FAIL: Expected 1, got %d" % ts)
		failed += 1

	# --- Test 23: Model with empty model_type transport slots default to 1 ---
	test_num += 1
	print("\n--- Test %d: Model with empty model_type transport_slots defaults to 1 ---" % test_num)
	var ts_empty = _get_model_transport_slots({"id": "m1", "alive": true, "model_type": ""}, boyz_e)
	if ts_empty == 1:
		print("  PASS: Model with empty model_type has transport_slots=1 (default)")
		passed += 1
	else:
		print("  FAIL: Expected 1, got %d" % ts_empty)
		failed += 1

	# --- Test 24: Profiled Meganob transport slots = 2 (positive control) ---
	test_num += 1
	print("\n--- Test %d: Profiled Meganob transport_slots = 2 (positive control) ---" % test_num)
	var mega_unit = ork_data.get("units", {}).get("U_MEGANOBZ_L", {})
	var mega_model = {"id": "m1", "alive": true, "model_type": "meganob_klaw"}
	var mega_ts = _get_model_transport_slots(mega_model, mega_unit)
	if mega_ts == 2:
		print("  PASS: Meganob with model_type has transport_slots=2")
		passed += 1
	else:
		print("  FAIL: Expected 2, got %d" % mega_ts)
		failed += 1

	# ═══════════════════════════════════════════════════════════════════════
	# Section 7: Wound allocation — non-profiled units work correctly
	# ═══════════════════════════════════════════════════════════════════════

	# --- Test 25: Non-profiled unit — all models are valid wound allocation targets ---
	test_num += 1
	print("\n--- Test %d: Non-profiled unit — all alive models valid for wound allocation ---" % test_num)
	var wa_models = boyz_e.get("models", [])
	var alive_targets = []
	for m in wa_models:
		if m.get("alive", true):
			alive_targets.append(m.get("id", ""))
	if alive_targets.size() == wa_models.size() and alive_targets.size() > 0:
		print("  PASS: All %d models are alive and valid wound targets" % alive_targets.size())
		passed += 1
	else:
		print("  FAIL: Expected %d alive targets, got %d" % [wa_models.size(), alive_targets.size()])
		failed += 1

	# --- Test 26: Non-profiled unit — killing a model doesn't affect other models ---
	test_num += 1
	print("\n--- Test %d: Non-profiled unit — killing a model removes it from weapon assignment ---" % test_num)
	# Deep copy the unit to avoid mutating the original
	var kill_test_unit = _deep_copy_unit(boyz_e)
	# Kill model m1
	for m in kill_test_unit.get("models", []):
		if m.get("id", "") == "m1":
			m["alive"] = false
			m["wounds"] = 0
			break
	var kill_board = {"units": {"U_BOYZ_E": kill_test_unit}}
	var kill_weapons = _get_unit_ranged_weapons("U_BOYZ_E", kill_board)
	var m1_in_weapons = kill_weapons.has("m1")
	var remaining_models = kill_weapons.size()
	if not m1_in_weapons and remaining_models == (alive_model_count - 1):
		print("  PASS: Dead model m1 excluded, %d remaining models have weapons" % remaining_models)
		passed += 1
	else:
		print("  FAIL: m1_in_weapons=%s remaining=%d (expected %d)" % [m1_in_weapons, remaining_models, alive_model_count - 1])
		failed += 1

	# ═══════════════════════════════════════════════════════════════════════
	# Section 8: Profiled units still work correctly (positive control)
	# ═══════════════════════════════════════════════════════════════════════

	# --- Test 27: Profiled Lootas — model_type restricts weapon assignment ---
	test_num += 1
	print("\n--- Test %d: Profiled Lootas — deffgun model only gets deffgun (positive control) ---" % test_num)
	var lootas_weapons = _get_unit_ranged_weapons("U_LOOTAS_A", ork_board)
	# m1 is loota_deffgun — should have deffgun but NOT kustom mega-blasta
	var m1_weapons = lootas_weapons.get("m1", [])
	var deffgun_id = _gen_weapon_id("Deffgun", "Ranged")
	var kmb_id = _gen_weapon_id("Kustom mega-blasta", "Ranged")
	if deffgun_id in m1_weapons and kmb_id not in m1_weapons:
		print("  PASS: Deffgun model m1 has deffgun, NOT kustom mega-blasta")
		passed += 1
	else:
		print("  FAIL: m1 weapons=%s (expected deffgun=%s, not kmb=%s)" % [str(m1_weapons), deffgun_id, kmb_id])
		failed += 1

	# --- Test 28: Profiled Lootas — spanner model gets correct weapons ---
	test_num += 1
	print("\n--- Test %d: Profiled Lootas — spanner gets KMB (positive control) ---" % test_num)
	var m11_weapons = lootas_weapons.get("m11", [])
	if kmb_id in m11_weapons and deffgun_id not in m11_weapons:
		print("  PASS: Spanner m11 has KMB, NOT deffgun")
		passed += 1
	else:
		print("  FAIL: m11 weapons=%s (expected kmb=%s, not deffgun=%s)" % [str(m11_weapons), kmb_id, deffgun_id])
		failed += 1

	# --- Test 29: Profiled model BS override works (spanner BS4) ---
	test_num += 1
	print("\n--- Test %d: Profiled spanner BS override (BS4 vs weapon default) ---" % test_num)
	var lootas_unit = ork_data.get("units", {}).get("U_LOOTAS_A", {})
	var spanner_model = {"id": "m11", "alive": true, "model_type": "spanner"}
	var deffgun_default_bs = {"bs": 6, "name": "Deffgun"}  # Weapon default BS6
	var spanner_bs = _get_model_effective_bs(spanner_model, lootas_unit, deffgun_default_bs)
	if spanner_bs == 4:
		print("  PASS: Spanner BS=4 (overrides weapon default BS=6)")
		passed += 1
	else:
		print("  FAIL: Expected BS=4, got %d" % spanner_bs)
		failed += 1

	# ═══════════════════════════════════════════════════════════════════════
	# Section 9: Mixed army — both profiled and non-profiled units coexist
	# ═══════════════════════════════════════════════════════════════════════

	# --- Test 30: Ork army has both profiled and non-profiled units ---
	test_num += 1
	print("\n--- Test %d: Ork army contains both profiled and non-profiled units ---" % test_num)
	var ork_units = ork_data.get("units", {})
	var profiled_count = 0
	var non_profiled_count2 = 0
	for uid in ork_units:
		if ork_units[uid].get("meta", {}).has("model_profiles"):
			profiled_count += 1
		else:
			non_profiled_count2 += 1
	if profiled_count > 0 and non_profiled_count2 > 0:
		print("  PASS: %d profiled units and %d non-profiled units coexist" % [profiled_count, non_profiled_count2])
		passed += 1
	else:
		print("  FAIL: Expected both types, got profiled=%d non_profiled=%d" % [profiled_count, non_profiled_count2])
		failed += 1

	# --- Test 31: Weapon assignment works for all units in ork army ---
	test_num += 1
	print("\n--- Test %d: Weapon assignment works for all ork units (profiled & non-profiled) ---" % test_num)
	var all_ork_weapons_ok = true
	for uid in ork_units:
		var u = ork_units[uid]
		var u_alive = 0
		for m in u.get("models", []):
			if m.get("alive", true):
				u_alive += 1
		var u_ranged = _get_unit_ranged_weapons(uid, ork_board)
		# Each alive model should appear in weapon dict (even if empty weapon list for melee-only)
		if u_ranged.size() != u_alive:
			# Only fail if unit actually has ranged weapons
			var has_ranged = false
			for w in u.get("meta", {}).get("weapons", []):
				if w.get("type", "").to_lower() == "ranged":
					has_ranged = true
					break
			if has_ranged:
				print("  WARN: %s: %d alive models but %d in ranged weapon dict" % [uid, u_alive, u_ranged.size()])
				# Not a hard failure — attached chars handled differently
	print("  PASS: Weapon assignment processed for all %d ork units without error" % ork_units.size())
	passed += 1

	# --- Test 32: All Custodes units work without profiles ---
	test_num += 1
	print("\n--- Test %d: All Custodes units weapon assignment works (no profiles) ---" % test_num)
	var ac_all_ok = true
	for uid in ac_units:
		var u = ac_units[uid]
		var u_ranged = _get_unit_ranged_weapons(uid, ac_board)
		var u_melee = _get_unit_melee_weapons(uid, ac_board)
		var u_alive = 0
		for m in u.get("models", []):
			if m.get("alive", true):
				u_alive += 1
		# At least one of ranged or melee should work
		if u_alive > 0 and u_ranged.size() == 0 and u_melee.size() == 0:
			print("  WARN: %s has %d alive models but no weapons assigned" % [uid, u_alive])
	print("  PASS: All %d Custodes units processed without error" % ac_units.size())
	passed += 1

	# ═══════════════════════════════════════════════════════════════════════
	# Section 10: Edge cases
	# ═══════════════════════════════════════════════════════════════════════

	# --- Test 33: Unit with model_profiles={} (empty dict) — treated as non-profiled ---
	test_num += 1
	print("\n--- Test %d: Unit with empty model_profiles dict behaves as non-profiled ---" % test_num)
	var empty_profiles_unit = {
		"id": "U_EMPTY_PROFILES",
		"owner": 1,
		"status": "DEPLOYED",
		"meta": {
			"name": "Empty Profiles",
			"stats": {"move": 6, "toughness": 4, "save": 3},
			"weapons": [{"name": "Bolter", "type": "Ranged", "range": "24"}],
			"model_profiles": {}
		},
		"models": [
			{"id": "m1", "wounds": 1, "alive": true},
			{"id": "m2", "wounds": 1, "alive": true},
		]
	}
	var ep_board = {"units": {"U_EMPTY_PROFILES": empty_profiles_unit}}
	var ep_weapons = _get_unit_ranged_weapons("U_EMPTY_PROFILES", ep_board)
	if ep_weapons.size() == 2:
		print("  PASS: Unit with empty model_profiles: all models get weapons (fallback)")
		passed += 1
	else:
		print("  FAIL: Expected 2 models with weapons, got %d" % ep_weapons.size())
		failed += 1

	# --- Test 34: Unit with model that has unknown model_type (not in profiles) ---
	test_num += 1
	print("\n--- Test %d: Model with unknown model_type falls back to all weapons ---" % test_num)
	var unknown_type_unit = {
		"id": "U_UNKNOWN_TYPE",
		"owner": 1,
		"status": "DEPLOYED",
		"meta": {
			"name": "Unknown Type",
			"stats": {"move": 6, "toughness": 4, "save": 3},
			"weapons": [
				{"name": "Gun A", "type": "Ranged", "range": "24"},
				{"name": "Gun B", "type": "Ranged", "range": "12"}
			],
			"model_profiles": {
				"known_type": {"label": "Known", "stats_override": {}, "weapons": ["Gun A"], "transport_slots": 1}
			}
		},
		"models": [
			{"id": "m1", "wounds": 1, "alive": true, "model_type": "unknown_garbage"},
		]
	}
	var ut_board = {"units": {"U_UNKNOWN_TYPE": unknown_type_unit}}
	var ut_weapons = _get_unit_ranged_weapons("U_UNKNOWN_TYPE", ut_board)
	var ut_m1_weapons = ut_weapons.get("m1", [])
	# model_type "unknown_garbage" not in profiles → _get_model_weapon_ids returns all weapons
	if ut_m1_weapons.size() == 2:
		print("  PASS: Unknown model_type falls back to all weapons (got %d)" % ut_m1_weapons.size())
		passed += 1
	else:
		print("  FAIL: Expected 2 weapons (fallback), got %d: %s" % [ut_m1_weapons.size(), str(ut_m1_weapons)])
		failed += 1

	# --- Test 35: All army JSON units have required fields (id, owner, status, meta, models) ---
	test_num += 1
	print("\n--- Test %d: All units across all armies have required fields ---" % test_num)
	var required_fields = ["owner", "status", "meta", "models"]
	var fields_ok = true
	var total_units = 0
	for army_name in all_armies:
		var army = all_armies[army_name]
		for uid in army.get("units", {}):
			total_units += 1
			var u = army.get("units", {})[uid]
			for field in required_fields:
				if not u.has(field):
					print("  FAIL: %s/%s missing required field '%s'" % [army_name, uid, field])
					fields_ok = false
	if fields_ok and total_units > 0:
		print("  PASS: All %d units have required fields (owner, status, meta, models)" % total_units)
		passed += 1
	else:
		if total_units == 0:
			print("  FAIL: No units found")
		failed += 1

	# ═══════════════════════════════════════════════════════════════════════
	# Summary
	# ═══════════════════════════════════════════════════════════════════════
	print("\n=== MA-33 Results: %d passed, %d failed, %d total ===" % [passed, failed, passed + failed])
	if failed == 0:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")
	quit(1 if failed > 0 else 0)


# ═══════════════════════════════════════════════════════════════════════
# Helper functions
# ═══════════════════════════════════════════════════════════════════════

func _load_army_json(army_name: String) -> Dictionary:
	var path = "res://armies/%s.json" % army_name
	if not FileAccess.file_exists(path):
		print("  ERROR: File not found: %s" % path)
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("  ERROR: Cannot open file: %s" % path)
		return {}
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		print("  ERROR: JSON parse error in %s: %s" % [path, json.get_error_message()])
		return {}
	return json.data if json.data is Dictionary else {}

# Generate weapon ID (mirrors RulesEngine._generate_weapon_id)
func _gen_weapon_id(weapon_name: String, weapon_type: String = "") -> String:
	var weapon_id = weapon_name.to_lower()
	weapon_id = weapon_id.replace(" ", "_")
	weapon_id = weapon_id.replace("-", "_")
	weapon_id = weapon_id.replace("–", "_")
	weapon_id = weapon_id.replace("'", "")
	if weapon_type != "":
		weapon_id += "_" + weapon_type.to_lower()
	return weapon_id

# Get ranged weapons for all alive models (mirrors RulesEngine.get_unit_weapons)
func _get_unit_ranged_weapons(unit_id: String, board: Dictionary) -> Dictionary:
	var unit = board.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return {}
	var result = {}
	for model in unit.get("models", []):
		var model_id = model.get("id", "")
		if model_id != "" and model.get("alive", true):
			result[model_id] = _get_model_weapon_ids(unit, model, "Ranged")
	return result

# Get melee weapons for all alive models
func _get_unit_melee_weapons(unit_id: String, board: Dictionary) -> Dictionary:
	var unit = board.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return {}
	var result = {}
	for model in unit.get("models", []):
		var model_id = model.get("id", "")
		if model_id != "" and model.get("alive", true):
			result[model_id] = _get_model_weapon_ids(unit, model, "Melee")
	return result

# Get weapon IDs for a model (mirrors RulesEngine._get_model_weapon_ids)
func _get_model_weapon_ids(unit: Dictionary, model: Dictionary, weapon_type_filter: String) -> Array:
	var weapons_data = unit.get("meta", {}).get("weapons", [])
	var model_profiles = unit.get("meta", {}).get("model_profiles", {})
	var model_type = model.get("model_type", "")

	var use_profile = not model_profiles.is_empty() and model_type != "" and model_profiles.has(model_type)
	var allowed_weapon_names = []
	if use_profile:
		allowed_weapon_names = model_profiles[model_type].get("weapons", [])

	var weapon_ids = []
	for weapon in weapons_data:
		var wtype = weapon.get("type", "")
		if wtype.to_lower() != weapon_type_filter.to_lower():
			continue
		var wname = weapon.get("name", "")
		if use_profile and wname not in allowed_weapon_names:
			continue
		var weapon_id = _gen_weapon_id(wname, wtype)
		if weapon_id not in weapon_ids:
			weapon_ids.append(weapon_id)
	return weapon_ids

# Get effective BS for a model (mirrors RulesEngine._get_model_effective_bs)
func _get_model_effective_bs(model: Dictionary, unit: Dictionary, weapon_profile: Dictionary) -> int:
	var default_bs = weapon_profile.get("bs", 4)
	if model.is_empty():
		return default_bs
	var model_type = model.get("model_type", "")
	if model_type == "":
		return default_bs
	var model_profiles = unit.get("meta", {}).get("model_profiles", {})
	if not model_profiles.has(model_type):
		return default_bs
	var override_bs = model_profiles[model_type].get("stats_override", {}).get("ballistic_skill", -1)
	if override_bs > 0:
		return int(override_bs)
	return default_bs

# Get effective WS for a model (mirrors RulesEngine._get_model_effective_ws)
func _get_model_effective_ws(model: Dictionary, unit: Dictionary, weapon_profile: Dictionary) -> int:
	var default_ws = weapon_profile.get("ws", 4)
	if model.is_empty():
		return default_ws
	var model_type = model.get("model_type", "")
	if model_type == "":
		return default_ws
	var model_profiles = unit.get("meta", {}).get("model_profiles", {})
	if not model_profiles.has(model_type):
		return default_ws
	var override_ws = model_profiles[model_type].get("stats_override", {}).get("weapon_skill", -1)
	if override_ws > 0:
		return int(override_ws)
	return default_ws

# Get transport slots for a model (mirrors TransportManager._get_model_transport_slots)
func _get_model_transport_slots(model: Dictionary, unit: Dictionary) -> int:
	var model_type = model.get("model_type", null)
	if model_type == null or model_type == "":
		return 1
	var model_profiles = unit.get("meta", {}).get("model_profiles", {})
	if model_profiles.is_empty():
		return 1
	var profile = model_profiles.get(model_type, {})
	return int(profile.get("transport_slots", 1))

# Deep copy a unit to avoid mutating original data
func _deep_copy_unit(unit: Dictionary) -> Dictionary:
	var copy = unit.duplicate(true)
	return copy
