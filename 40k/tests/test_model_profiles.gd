extends SceneTree

# Test: MA-1 Model Profiles Schema
# Verifies that model_profiles are correctly loaded from army JSON and accessible
# via GameState.get_unit(unit_id).meta.model_profiles
# Usage: godot --headless --path . -s tests/test_model_profiles.gd

func _init():
	print("\n=== Test Model Profiles Schema (MA-1) ===\n")
	var passed = 0
	var failed = 0

	# --- Test 1: Load orks.json and verify model_profiles exists on Lootas ---
	print("--- Test 1: model_profiles loaded from orks.json ---")
	var army_data = _load_army_json("orks")
	if army_data.is_empty():
		print("  FAIL: Could not load orks.json")
		failed += 1
	else:
		var lootas = army_data.get("units", {}).get("U_LOOTAS_A", {})
		var meta = lootas.get("meta", {})
		if meta.has("model_profiles"):
			print("  PASS: model_profiles found in U_LOOTAS_A meta")
			passed += 1
		else:
			print("  FAIL: model_profiles not found in U_LOOTAS_A meta")
			failed += 1

	# --- Test 2: model_profiles is a Dictionary ---
	print("\n--- Test 2: model_profiles is a Dictionary ---")
	var mp = army_data.get("units", {}).get("U_LOOTAS_A", {}).get("meta", {}).get("model_profiles", null)
	if mp is Dictionary:
		print("  PASS: model_profiles is a Dictionary")
		passed += 1
	else:
		print("  FAIL: model_profiles is not a Dictionary (type: %s)" % typeof(mp))
		failed += 1

	# --- Test 3: Profile keys exist ---
	print("\n--- Test 3: Expected profile keys exist ---")
	if mp is Dictionary and mp.has("loota_deffgun") and mp.has("loota_kmb") and mp.has("spanner"):
		print("  PASS: Found loota_deffgun, loota_kmb, and spanner profiles")
		passed += 1
	else:
		print("  FAIL: Missing expected profile keys (got: %s)" % str(mp.keys() if mp is Dictionary else "null"))
		failed += 1

	# --- Test 4: Profile has required fields ---
	print("\n--- Test 4: Each profile has required fields ---")
	var all_fields_ok = true
	if mp is Dictionary:
		for profile_key in mp:
			var profile = mp[profile_key]
			var required = ["label", "stats_override", "weapons", "transport_slots"]
			for field in required:
				if not profile.has(field):
					print("  FAIL: Profile '%s' missing field '%s'" % [profile_key, field])
					all_fields_ok = false
		if all_fields_ok:
			print("  PASS: All profiles have label, stats_override, weapons, transport_slots")
			passed += 1
		else:
			failed += 1
	else:
		print("  FAIL: model_profiles is not a Dictionary")
		failed += 1

	# --- Test 5: Profile field types are correct ---
	print("\n--- Test 5: Profile field types are correct ---")
	var types_ok = true
	if mp is Dictionary:
		for profile_key in mp:
			var profile = mp[profile_key]
			if not profile.get("label", null) is String:
				print("  FAIL: %s.label is not a String" % profile_key)
				types_ok = false
			if not profile.get("stats_override", null) is Dictionary:
				print("  FAIL: %s.stats_override is not a Dictionary" % profile_key)
				types_ok = false
			if not profile.get("weapons", null) is Array:
				print("  FAIL: %s.weapons is not an Array" % profile_key)
				types_ok = false
			# transport_slots comes from JSON as float, check it's numeric
			var ts = profile.get("transport_slots", null)
			if not (ts is int or ts is float):
				print("  FAIL: %s.transport_slots is not numeric (type: %s)" % [profile_key, typeof(ts)])
				types_ok = false
		if types_ok:
			print("  PASS: All profile field types are correct")
			passed += 1
		else:
			failed += 1
	else:
		print("  FAIL: model_profiles is not a Dictionary")
		failed += 1

	# --- Test 6: Weapon references are valid ---
	print("\n--- Test 6: Weapon references in profiles match meta.weapons ---")
	var weapons_ok = true
	var meta = army_data.get("units", {}).get("U_LOOTAS_A", {}).get("meta", {})
	var weapon_names = []
	for w in meta.get("weapons", []):
		if w is Dictionary:
			weapon_names.append(w.get("name", ""))
	if mp is Dictionary:
		for profile_key in mp:
			var profile = mp[profile_key]
			for weapon_ref in profile.get("weapons", []):
				if weapon_ref not in weapon_names:
					print("  FAIL: %s references unknown weapon '%s'" % [profile_key, weapon_ref])
					weapons_ok = false
		if weapons_ok:
			print("  PASS: All weapon references are valid")
			passed += 1
		else:
			failed += 1
	else:
		print("  FAIL: model_profiles is not a Dictionary")
		failed += 1

	# --- Test 7: Units without model_profiles still work (backward compat) ---
	print("\n--- Test 7: Units without model_profiles work unchanged ---")
	var boyz_unit = army_data.get("units", {}).get("U_BOYZ_E", {})
	var boyz_meta = boyz_unit.get("meta", {})
	if not boyz_meta.has("model_profiles"):
		# Verify it still has weapons and stats
		if boyz_meta.has("weapons") and boyz_meta.has("stats"):
			print("  PASS: U_BOYZ_E works without model_profiles (has weapons and stats)")
			passed += 1
		else:
			print("  FAIL: U_BOYZ_E is missing weapons or stats")
			failed += 1
	else:
		print("  FAIL: U_BOYZ_E should NOT have model_profiles")
		failed += 1

	# --- Test 8: Specific profile values ---
	print("\n--- Test 8: Loota profile has correct values ---")
	if mp is Dictionary and mp.has("loota_deffgun"):
		var loota = mp["loota_deffgun"]
		var label_ok = loota.get("label", "") == "Loota (Deffgun)"
		var weapons_list = loota.get("weapons", [])
		var has_deffgun = "Deffgun" in weapons_list
		var has_ccw = "Close combat weapon" in weapons_list
		var ts = int(loota.get("transport_slots", 0))
		if label_ok and has_deffgun and has_ccw and ts == 1:
			print("  PASS: loota_deffgun profile has correct label, weapons, and transport_slots")
			passed += 1
		else:
			print("  FAIL: loota_deffgun values incorrect (label=%s, deffgun=%s, ccw=%s, ts=%d)" % [label_ok, has_deffgun, has_ccw, ts])
			failed += 1
	else:
		print("  FAIL: loota_deffgun profile not found")
		failed += 1

	# --- Test 9: MA-5 Lootas has 3 model types with correct counts ---
	print("\n--- Test 9: MA-5 Lootas heterogeneous model types ---")
	var lootas_models = army_data.get("units", {}).get("U_LOOTAS_A", {}).get("models", [])
	var type_counts = {}
	for m in lootas_models:
		var mt = m.get("model_type", "")
		type_counts[mt] = type_counts.get(mt, 0) + 1
	if lootas_models.size() == 11 and type_counts.get("loota_deffgun", 0) == 8 and type_counts.get("loota_kmb", 0) == 2 and type_counts.get("spanner", 0) == 1:
		print("  PASS: 11 models with 8x loota_deffgun, 2x loota_kmb, 1x spanner")
		passed += 1
	else:
		print("  FAIL: Expected 11 models (8 loota_deffgun, 2 loota_kmb, 1 spanner), got %d models: %s" % [lootas_models.size(), str(type_counts)])
		failed += 1

	# --- Test 10: MA-5 Spanner profile has BS4+ stats_override ---
	print("\n--- Test 10: MA-5 Spanner profile has stats_override ---")
	var spanner_profile = mp.get("spanner", {}) if mp is Dictionary else {}
	var spanner_bs = spanner_profile.get("stats_override", {}).get("ballistic_skill", null)
	if spanner_bs != null and int(spanner_bs) == 4:
		print("  PASS: spanner profile has ballistic_skill=4 stats_override")
		passed += 1
	else:
		print("  FAIL: spanner profile stats_override.ballistic_skill expected 4, got %s" % str(spanner_bs))
		failed += 1

	# --- Test 11: MA-5 loota_kmb profile has KMB weapon ---
	print("\n--- Test 11: MA-5 loota_kmb profile weapons ---")
	var kmb_profile = mp.get("loota_kmb", {}) if mp is Dictionary else {}
	var kmb_weapons = kmb_profile.get("weapons", [])
	if "Kustom mega-blasta" in kmb_weapons and "Close combat weapon" in kmb_weapons:
		print("  PASS: loota_kmb profile has Kustom mega-blasta and Close combat weapon")
		passed += 1
	else:
		print("  FAIL: loota_kmb weapons expected [Kustom mega-blasta, Close combat weapon], got %s" % str(kmb_weapons))
		failed += 1

	# --- Test 12: MA-5 Space Marines Intercessors heterogeneous ---
	print("\n--- Test 12: MA-5 Space Marines Intercessor Squad heterogeneous ---")
	var sm_data = _load_army_json("space_marines")
	if sm_data.is_empty():
		print("  FAIL: Could not load space_marines.json")
		failed += 1
	else:
		var intercessors = sm_data.get("units", {}).get("U_INTERCESSORS_A", {})
		var sm_meta = intercessors.get("meta", {})
		var sm_profiles = sm_meta.get("model_profiles", {})
		var sm_models = intercessors.get("models", [])
		var sm_type_counts = {}
		for m in sm_models:
			var mt = m.get("model_type", "")
			sm_type_counts[mt] = sm_type_counts.get(mt, 0) + 1
		if sm_profiles.has("intercessor") and sm_profiles.has("intercessor_sergeant") and sm_type_counts.get("intercessor", 0) == 4 and sm_type_counts.get("intercessor_sergeant", 0) == 1:
			print("  PASS: 5 models with 1x intercessor_sergeant, 4x intercessor")
			passed += 1
		else:
			print("  FAIL: Expected profiles [intercessor, intercessor_sergeant] with counts 4+1, got profiles=%s counts=%s" % [str(sm_profiles.keys()), str(sm_type_counts)])
			failed += 1

	# --- Test 13: MA-5 Intercessor Sergeant has Power fist ---
	print("\n--- Test 13: MA-5 Intercessor Sergeant profile weapons ---")
	if not sm_data.is_empty():
		var sm_profiles2 = sm_data.get("units", {}).get("U_INTERCESSORS_A", {}).get("meta", {}).get("model_profiles", {})
		var sgt_profile = sm_profiles2.get("intercessor_sergeant", {})
		var sgt_weapons = sgt_profile.get("weapons", [])
		if "Power fist" in sgt_weapons and "Bolt rifle" in sgt_weapons:
			print("  PASS: intercessor_sergeant has Power fist and Bolt rifle")
			passed += 1
		else:
			print("  FAIL: intercessor_sergeant weapons expected Power fist + Bolt rifle, got %s" % str(sgt_weapons))
			failed += 1
	else:
		print("  FAIL: space_marines.json not loaded")
		failed += 1

	# --- Test 14: MA-5 All weapon references valid in SM Intercessors ---
	print("\n--- Test 14: MA-5 SM Intercessor weapon references valid ---")
	if not sm_data.is_empty():
		var sm_meta2 = sm_data.get("units", {}).get("U_INTERCESSORS_A", {}).get("meta", {})
		var sm_weapon_names = []
		for w in sm_meta2.get("weapons", []):
			if w is Dictionary:
				sm_weapon_names.append(w.get("name", ""))
		var sm_profiles3 = sm_meta2.get("model_profiles", {})
		var sm_weapons_ok = true
		for pk in sm_profiles3:
			for wn in sm_profiles3[pk].get("weapons", []):
				if wn not in sm_weapon_names:
					print("  FAIL: SM profile %s references unknown weapon '%s'" % [pk, wn])
					sm_weapons_ok = false
		if sm_weapons_ok:
			print("  PASS: All SM Intercessor weapon references are valid")
			passed += 1
		else:
			failed += 1
	else:
		print("  FAIL: space_marines.json not loaded")
		failed += 1

	# --- Test 15: MA-11 Boyz unit has model_profiles with weapon_skill overrides ---
	print("\n--- Test 15: MA-11 Boyz unit has model_profiles with weapon_skill overrides ---")
	var boyz_f = army_data.get("units", {}).get("U_BOYZ_F", {})
	var boyz_f_meta = boyz_f.get("meta", {})
	var boyz_f_profiles = boyz_f_meta.get("model_profiles", {})
	if boyz_f_profiles.has("boss_nob") and boyz_f_profiles.has("boy"):
		var nob_ws = boyz_f_profiles["boss_nob"].get("stats_override", {}).get("weapon_skill", null)
		var boy_ws = boyz_f_profiles["boy"].get("stats_override", {}).get("weapon_skill", null)
		if nob_ws != null and int(nob_ws) == 3 and boy_ws != null and int(boy_ws) == 4:
			print("  PASS: boss_nob WS=3, boy WS=4")
			passed += 1
		else:
			print("  FAIL: Expected boss_nob WS=3 boy WS=4, got nob=%s boy=%s" % [str(nob_ws), str(boy_ws)])
			failed += 1
	else:
		print("  FAIL: U_BOYZ_F missing boss_nob or boy profiles (keys: %s)" % str(boyz_f_profiles.keys()))
		failed += 1

	# --- Test 16: MA-11 Boyz models have correct model_type ---
	print("\n--- Test 16: MA-11 Boyz models have correct model_type ---")
	var boyz_f_models = boyz_f.get("models", [])
	var boyz_type_counts = {}
	for m in boyz_f_models:
		var mt = m.get("model_type", "")
		boyz_type_counts[mt] = boyz_type_counts.get(mt, 0) + 1
	if boyz_type_counts.get("boss_nob", 0) == 1 and boyz_type_counts.get("boy", 0) == 19:
		print("  PASS: 1x boss_nob, 19x boy")
		passed += 1
	else:
		print("  FAIL: Expected 1x boss_nob, 19x boy, got %s" % str(boyz_type_counts))
		failed += 1

	# --- Test 17: MA-24 Meganobz unit exists with transport_slots: 2 ---
	print("\n--- Test 17: MA-24 Meganobz unit has transport_slots: 2 ---")
	var meganobz = army_data.get("units", {}).get("U_MEGANOBZ_L", {})
	var mega_meta = meganobz.get("meta", {})
	var mega_profiles = mega_meta.get("model_profiles", {})
	if mega_profiles.has("meganob_klaw") and mega_profiles.has("meganob_saws"):
		var klaw_slots = int(mega_profiles["meganob_klaw"].get("transport_slots", 0))
		var saws_slots = int(mega_profiles["meganob_saws"].get("transport_slots", 0))
		if klaw_slots == 2 and saws_slots == 2:
			print("  PASS: meganob_klaw and meganob_saws both have transport_slots=2")
			passed += 1
		else:
			print("  FAIL: Expected transport_slots=2 for both, got klaw=%d saws=%d" % [klaw_slots, saws_slots])
			failed += 1
	else:
		print("  FAIL: U_MEGANOBZ_L missing meganob_klaw or meganob_saws profiles")
		failed += 1

	# --- Test 18: MA-24 Meganobz has MEGA ARMOUR keyword ---
	print("\n--- Test 18: MA-24 Meganobz has MEGA ARMOUR keyword ---")
	var mega_keywords = mega_meta.get("keywords", [])
	if "MEGA ARMOUR" in mega_keywords:
		print("  PASS: Meganobz has MEGA ARMOUR keyword")
		passed += 1
	else:
		print("  FAIL: Meganobz missing MEGA ARMOUR keyword (got: %s)" % str(mega_keywords))
		failed += 1

	# --- Test 19: MA-24 Meganobz has 5 models with correct types ---
	print("\n--- Test 19: MA-24 Meganobz has 5 models with correct model_type ---")
	var mega_models = meganobz.get("models", [])
	var mega_type_counts = {}
	for m in mega_models:
		var mt = m.get("model_type", "")
		mega_type_counts[mt] = mega_type_counts.get(mt, 0) + 1
	if mega_models.size() == 5 and mega_type_counts.get("meganob_klaw", 0) == 3 and mega_type_counts.get("meganob_saws", 0) == 2:
		print("  PASS: 5 models with 3x meganob_klaw, 2x meganob_saws")
		passed += 1
	else:
		print("  FAIL: Expected 5 models (3 klaw, 2 saws), got %d models: %s" % [mega_models.size(), str(mega_type_counts)])
		failed += 1

	# --- Test 20: MA-24 Regular Boyz profiles have transport_slots: 1 ---
	print("\n--- Test 20: MA-24 Regular Boyz profiles have transport_slots: 1 ---")
	var boyz_profiles = boyz_f_meta.get("model_profiles", {})
	var boyz_slots_ok = true
	for pk in boyz_profiles:
		var ts = int(boyz_profiles[pk].get("transport_slots", 0))
		if ts != 1:
			print("  FAIL: Boyz profile '%s' has transport_slots=%d (expected 1)" % [pk, ts])
			boyz_slots_ok = false
	if boyz_slots_ok and boyz_profiles.size() > 0:
		print("  PASS: All Boyz profiles have transport_slots=1")
		passed += 1
	else:
		if boyz_profiles.size() == 0:
			print("  FAIL: No Boyz profiles found")
		failed += 1

	# --- Test 21: MA-24 Slot-aware counting logic ---
	print("\n--- Test 21: MA-24 Slot-aware counting logic (simulated) ---")
	# Simulate _get_alive_model_count logic for Meganobz (5 models x 2 slots = 10)
	var mega_slot_count = 0
	for m in mega_models:
		if m.get("alive", true):
			var mt = m.get("model_type", "")
			var profile = mega_profiles.get(mt, {})
			mega_slot_count += int(profile.get("transport_slots", 1))
	if mega_slot_count == 10:
		print("  PASS: 5 Meganobz = 10 transport slots")
		passed += 1
	else:
		print("  FAIL: Expected 10 transport slots for 5 Meganobz, got %d" % mega_slot_count)
		failed += 1

	# --- Test 22: MA-24 Mixed unit slot counting ---
	print("\n--- Test 22: MA-24 Mixed slot counting (Boyz vs Meganobz) ---")
	# Boyz: 20 models x 1 slot = 20 slots
	var boyz_slot_count = 0
	for m in boyz_f_models:
		if m.get("alive", true):
			var mt = m.get("model_type", "")
			var profile = boyz_profiles.get(mt, {})
			boyz_slot_count += int(profile.get("transport_slots", 1))
	# Battlewagon has 22 capacity: 20 boyz (20 slots) + 5 meganobz (10 slots) = 30, won't fit
	# But 10 boyz (10 slots) + 5 meganobz (10 slots) = 20, fits in 22
	if boyz_slot_count == 20 and mega_slot_count == 10:
		var combined = boyz_slot_count + mega_slot_count  # 30
		var partial_boyz = 10  # 10 Boyz slots
		if combined > 22 and (partial_boyz + mega_slot_count) <= 22:
			print("  PASS: 20 Boyz + 5 Meganobz = 30 slots (exceeds 22), but 10 Boyz + 5 Meganobz = 20 slots (fits)")
			passed += 1
		else:
			print("  FAIL: Capacity math incorrect")
			failed += 1
	else:
		print("  FAIL: Slot counts wrong (boyz=%d mega=%d)" % [boyz_slot_count, mega_slot_count])
		failed += 1

	# --- Test 23: MA-24 Unit without profiles defaults to 1 slot per model ---
	print("\n--- Test 23: MA-24 Unit without profiles defaults to 1 per model ---")
	var boyz_e_models = army_data.get("units", {}).get("U_BOYZ_E", {}).get("models", [])
	var boyz_e_meta = army_data.get("units", {}).get("U_BOYZ_E", {}).get("meta", {})
	var boyz_e_has_profiles = boyz_e_meta.get("model_profiles", {}).size() > 0
	var boyz_e_slot_count = 0
	for m in boyz_e_models:
		if m.get("alive", true):
			if boyz_e_has_profiles:
				var mt = m.get("model_type", "")
				var profile = boyz_e_meta.get("model_profiles", {}).get(mt, {})
				boyz_e_slot_count += int(profile.get("transport_slots", 1))
			else:
				boyz_e_slot_count += 1
	if not boyz_e_has_profiles and boyz_e_slot_count == boyz_e_models.size():
		print("  PASS: U_BOYZ_E (no profiles) counts 1 per model (%d models = %d slots)" % [boyz_e_models.size(), boyz_e_slot_count])
		passed += 1
	else:
		print("  FAIL: Expected no profiles and 1:1 model:slot ratio")
		failed += 1

	# --- MA-26: Weapon ownership validation in shooting ---
	# These tests verify the weapon ownership logic directly using the data structures,
	# since RulesEngine autoload is not available in headless SceneTree mode.
	# The logic mirrors what validate_shoot does: check model_profiles[model_type].weapons
	# for the assigned weapon name.

	print("\n--- Test 24: MA-26 Assign deffgun to deffgun model — accepted ---")
	var ma26_lootas = army_data.get("units", {}).get("U_LOOTAS_A", {}).duplicate(true)
	var ma26_profiles = ma26_lootas.get("meta", {}).get("model_profiles", {})
	var ma26_models = ma26_lootas.get("models", [])
	# m1 is loota_deffgun — Deffgun should be in its profile weapons
	var ma26_m1 = {}
	for mdl in ma26_models:
		if mdl.get("id", "") == "m1":
			ma26_m1 = mdl
			break
	var ma26_m1_type = ma26_m1.get("model_type", "")
	var ma26_m1_weapons = ma26_profiles.get(ma26_m1_type, {}).get("weapons", [])
	if "Deffgun" in ma26_m1_weapons:
		print("  PASS: Deffgun is in deffgun model (m1, type=%s) profile weapons: %s" % [ma26_m1_type, str(ma26_m1_weapons)])
		passed += 1
	else:
		print("  FAIL: Deffgun NOT in model m1 (type=%s) profile weapons: %s" % [ma26_m1_type, str(ma26_m1_weapons)])
		failed += 1

	# --- Test 25: MA-26 Assign deffgun to mega-blasta model — rejected ---
	print("\n--- Test 25: MA-26 Assign deffgun to mega-blasta model — rejected ---")
	# m9 is loota_kmb — Deffgun should NOT be in its profile weapons
	var ma26_m9 = {}
	for mdl in ma26_models:
		if mdl.get("id", "") == "m9":
			ma26_m9 = mdl
			break
	var ma26_m9_type = ma26_m9.get("model_type", "")
	var ma26_m9_weapons = ma26_profiles.get(ma26_m9_type, {}).get("weapons", [])
	if "Deffgun" not in ma26_m9_weapons:
		print("  PASS: Deffgun correctly NOT in KMB model (m9, type=%s) profile weapons: %s" % [ma26_m9_type, str(ma26_m9_weapons)])
		passed += 1
	else:
		print("  FAIL: Deffgun unexpectedly found in KMB model m9 (type=%s) profile weapons: %s" % [ma26_m9_type, str(ma26_m9_weapons)])
		failed += 1

	# --- Test 26: MA-26 Assign mega-blasta to spanner — accepted ---
	print("\n--- Test 26: MA-26 Assign kustom mega-blasta to spanner — accepted ---")
	# m11 is spanner — Kustom mega-blasta should be in its profile weapons
	var ma26_m11 = {}
	for mdl in ma26_models:
		if mdl.get("id", "") == "m11":
			ma26_m11 = mdl
			break
	var ma26_m11_type = ma26_m11.get("model_type", "")
	var ma26_m11_weapons = ma26_profiles.get(ma26_m11_type, {}).get("weapons", [])
	if "Kustom mega-blasta" in ma26_m11_weapons:
		print("  PASS: Kustom mega-blasta is in spanner model (m11, type=%s) profile weapons: %s" % [ma26_m11_type, str(ma26_m11_weapons)])
		passed += 1
	else:
		print("  FAIL: Kustom mega-blasta NOT in spanner model m11 (type=%s) profile weapons: %s" % [ma26_m11_type, str(ma26_m11_weapons)])
		failed += 1

	# --- Test 27: MA-26 Unit without profiles allows all weapons to all models ---
	print("\n--- Test 27: MA-26 Unit without profiles allows all weapons ---")
	var ma26_noprofile = army_data.get("units", {}).get("U_BOYZ_E", {}).duplicate(true)
	var ma26_noprofile_profiles = ma26_noprofile.get("meta", {}).get("model_profiles", {})
	if ma26_noprofile_profiles.is_empty():
		print("  PASS: Unit without profiles has empty model_profiles — all weapons allowed to all models")
		passed += 1
	else:
		print("  FAIL: Expected empty model_profiles but got: %s" % str(ma26_noprofile_profiles.keys()))
		failed += 1

	# --- Test 28: MA-26 Validation logic matches: weapon_name checked against profile ---
	print("\n--- Test 28: MA-26 Cross-check: deffgun model cannot fire KMB ---")
	# m1 is loota_deffgun — Kustom mega-blasta should NOT be in its profile
	if "Kustom mega-blasta" not in ma26_m1_weapons:
		print("  PASS: KMB correctly NOT in deffgun model (m1) profile weapons: %s" % str(ma26_m1_weapons))
		passed += 1
	else:
		print("  FAIL: KMB unexpectedly found in deffgun model m1 profile weapons: %s" % str(ma26_m1_weapons))
		failed += 1

	# --- Summary ---
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)

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
