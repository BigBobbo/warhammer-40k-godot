extends SceneTree

# Test: Model Profiles (MA-1, MA-5, MA-10, MA-11, MA-24, MA-26, MA-30, MA-31)
# Verifies model_profiles schema, per-model weapon assignment, and combat resolution.
# MA-31 tests: mixed BS/WS, rapid fire counting, per-model saves, hazardous, one-shot tracking
# Usage: godot --headless --path . -s tests/test_model_profiles.gd

func _init():
	print("\n=== Test Model Profiles (MA-1, MA-5, MA-10, MA-11, MA-24, MA-26, MA-30, MA-31) ===\n")
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

	# ═══════════════════════════════════════════════════════════════════════
	# MA-30: Unit tests for per-model weapon assignment
	# These tests mirror the RulesEngine weapon assignment logic directly,
	# since RulesEngine can't be preloaded in headless SceneTree mode
	# (it depends on Measurement autoload at compile time).
	# ═══════════════════════════════════════════════════════════════════════

	# Build board dicts
	var ork_board = {"units": army_data.get("units", {})}

	# --- Test 29: get_unit_weapons with model_profiles (Lootas) ---
	print("\n--- Test 29: MA-30 get_unit_weapons with model_profiles (Lootas) ---")
	var t29_weapons = _get_unit_ranged_weapons("U_LOOTAS_A", ork_board)
	var t29_ok = true
	# m1-m8 are loota_deffgun → should get deffgun_ranged only
	for mid in ["m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8"]:
		if not t29_weapons.has(mid) or "deffgun_ranged" not in t29_weapons[mid]:
			print("  FAIL: %s missing deffgun_ranged (got: %s)" % [mid, str(t29_weapons.get(mid, []))])
			t29_ok = false
		if t29_weapons.has(mid) and "kustom_mega_blasta_ranged" in t29_weapons[mid]:
			print("  FAIL: %s should NOT have kustom_mega_blasta_ranged" % mid)
			t29_ok = false
	# m9-m10 are loota_kmb → should get kustom_mega_blasta_ranged only
	for mid in ["m9", "m10"]:
		if not t29_weapons.has(mid) or "kustom_mega_blasta_ranged" not in t29_weapons[mid]:
			print("  FAIL: %s missing kustom_mega_blasta_ranged (got: %s)" % [mid, str(t29_weapons.get(mid, []))])
			t29_ok = false
		if t29_weapons.has(mid) and "deffgun_ranged" in t29_weapons[mid]:
			print("  FAIL: %s should NOT have deffgun_ranged" % mid)
			t29_ok = false
	# m11 is spanner → should get kustom_mega_blasta_ranged only
	if not t29_weapons.has("m11") or "kustom_mega_blasta_ranged" not in t29_weapons["m11"]:
		print("  FAIL: m11 (spanner) missing kustom_mega_blasta_ranged (got: %s)" % str(t29_weapons.get("m11", [])))
		t29_ok = false
	if t29_weapons.has("m11") and "deffgun_ranged" in t29_weapons["m11"]:
		print("  FAIL: m11 (spanner) should NOT have deffgun_ranged")
		t29_ok = false
	if t29_ok:
		print("  PASS: Each Loota model gets correct profiled ranged weapons")
		passed += 1
	else:
		failed += 1

	# --- Test 30: get_unit_weapons without model_profiles (regression) ---
	print("\n--- Test 30: MA-30 get_unit_weapons without model_profiles (U_BOYZ_E) ---")
	var t30_weapons = _get_unit_ranged_weapons("U_BOYZ_E", ork_board)
	var t30_ok = true
	var t30_expected_ranged = ["big_shoota_ranged", "kombi_weapon_ranged", "rokkit_launcha_ranged", "shoota_ranged", "slugga_ranged"]
	# All 20 models should get ALL ranged weapons (no profile restriction)
	if t30_weapons.size() != 20:
		print("  FAIL: Expected 20 model entries, got %d" % t30_weapons.size())
		t30_ok = false
	for mid in ["m1", "m2", "m10", "m20"]:
		if not t30_weapons.has(mid):
			print("  FAIL: %s not found in weapons dict" % mid)
			t30_ok = false
			continue
		for expected_wid in t30_expected_ranged:
			if expected_wid not in t30_weapons[mid]:
				print("  FAIL: %s missing %s (got: %s)" % [mid, expected_wid, str(t30_weapons[mid])])
				t30_ok = false
	if t30_ok:
		print("  PASS: All models get all ranged weapons (no profiles = no restriction)")
		passed += 1
	else:
		failed += 1

	# --- Test 31: get_unit_melee_weapons with model_profiles (Boyz_F) ---
	print("\n--- Test 31: MA-30 get_unit_melee_weapons with model_profiles (Boyz_F) ---")
	var t31_melee = _get_unit_melee_weapons("U_BOYZ_F", ork_board)
	var t31_ok = true
	# NOTE: get_unit_melee_weapons uses "m" + str(index) for model IDs (0-indexed)
	# Model index 0 = boss_nob (JSON id "m1"), index 1-19 = boy (JSON id "m2"-"m20")
	# boss_nob melee profile: Big choppa, Choppa, Power klaw
	if not t31_melee.has("m0"):
		print("  FAIL: m0 (boss_nob) not found in melee weapons")
		t31_ok = false
	else:
		var nob_melee = t31_melee["m0"]
		for expected_w in ["Big choppa", "Choppa", "Power klaw"]:
			if expected_w not in nob_melee:
				print("  FAIL: boss_nob (m0) missing melee weapon '%s' (got: %s)" % [expected_w, str(nob_melee)])
				t31_ok = false
		# Close combat weapon is NOT in boss_nob melee profile
		if "Close combat weapon" in nob_melee:
			print("  FAIL: boss_nob (m0) should NOT have 'Close combat weapon'")
			t31_ok = false
	# boy melee profile: Choppa, Close combat weapon
	if not t31_melee.has("m1"):
		print("  FAIL: m1 (boy) not found in melee weapons")
		t31_ok = false
	else:
		var boy_melee = t31_melee["m1"]
		for expected_w in ["Choppa", "Close combat weapon"]:
			if expected_w not in boy_melee:
				print("  FAIL: boy (m1) missing melee weapon '%s' (got: %s)" % [expected_w, str(boy_melee)])
				t31_ok = false
		# Boys should NOT have Big choppa or Power klaw
		for unexpected_w in ["Big choppa", "Power klaw"]:
			if unexpected_w in boy_melee:
				print("  FAIL: boy (m1) should NOT have '%s'" % unexpected_w)
				t31_ok = false
	if t31_ok:
		print("  PASS: Melee weapons correctly assigned per model profile")
		passed += 1
	else:
		failed += 1

	# --- Test 32: get_unit_weapons with attached character (composite IDs) ---
	print("\n--- Test 32: MA-30 get_unit_weapons with attached character on profiled unit ---")
	var t32_lootas = army_data.get("units", {}).get("U_LOOTAS_A", {}).duplicate(true)
	t32_lootas["attachment_data"] = {"attached_characters": ["CHAR_WARBOSS"]}
	var t32_char = {
		"id": "CHAR_WARBOSS",
		"meta": {
			"weapons": [
				{"name": "Kombi-rokkit", "type": "Ranged", "range": "24", "attacks": "1", "ballistic_skill": "5", "strength": "9", "ap": "-2", "damage": "3", "special_rules": "blast"}
			]
		},
		"models": [
			{"id": "m1", "alive": true, "wounds": 4, "current_wounds": 4}
		]
	}
	var t32_board = {"units": {"U_LOOTAS_A": t32_lootas, "CHAR_WARBOSS": t32_char}}
	var t32_weapons = _get_unit_ranged_weapons("U_LOOTAS_A", t32_board)
	var t32_ok = true
	# Regular Loota models should still get their profiled weapons
	if not t32_weapons.has("m1") or "deffgun_ranged" not in t32_weapons["m1"]:
		print("  FAIL: Loota m1 should still have deffgun_ranged (got: %s)" % str(t32_weapons.get("m1", [])))
		t32_ok = false
	# Character should appear with composite ID
	var t32_composite = "CHAR_WARBOSS:m1"
	if not t32_weapons.has(t32_composite):
		print("  FAIL: Character composite ID '%s' not found in weapons dict (keys: %s)" % [t32_composite, str(t32_weapons.keys())])
		t32_ok = false
	else:
		if "kombi_rokkit_ranged" not in t32_weapons[t32_composite]:
			print("  FAIL: Character weapons missing kombi_rokkit_ranged (got: %s)" % str(t32_weapons[t32_composite]))
			t32_ok = false
	if t32_ok:
		print("  PASS: Attached character weapons use composite IDs correctly")
		passed += 1
	else:
		failed += 1

	# --- Test 33: Pistol filter with profiled unit (Boyz_F) ---
	print("\n--- Test 33: MA-30 Pistol filter with profiled unit (Boyz_F) ---")
	var t33_pistol = _filter_unit_weapons("U_BOYZ_F", "pistol", ork_board)
	var t33_ok = true
	# boss_nob (m1) has Slugga (pistol) in profile
	if not t33_pistol.has("m1") or "slugga_ranged" not in t33_pistol["m1"]:
		print("  FAIL: boss_nob (m1) should have slugga_ranged as pistol (got: %s)" % str(t33_pistol.get("m1", [])))
		t33_ok = false
	# boys (m2+) have Slugga (pistol) in profile
	if not t33_pistol.has("m2") or "slugga_ranged" not in t33_pistol["m2"]:
		print("  FAIL: boy (m2) should have slugga_ranged as pistol (got: %s)" % str(t33_pistol.get("m2", [])))
		t33_ok = false
	# Check that non-pistol weapons don't appear in pistol results
	for mid in t33_pistol:
		for wid in t33_pistol[mid]:
			if wid != "slugga_ranged":
				print("  FAIL: Unexpected pistol weapon '%s' for %s" % [wid, mid])
				t33_ok = false
	if t33_ok:
		print("  PASS: Pistol filter returns only Slugga for profiled Boyz")
		passed += 1
	else:
		failed += 1

	# --- Test 34: Heavy filter with profiled unit (Lootas) ---
	print("\n--- Test 34: MA-30 Heavy filter with profiled unit (Lootas) ---")
	var t34_heavy = _filter_unit_weapons("U_LOOTAS_A", "heavy", ork_board)
	var t34_ok = true
	# m1-m8 (loota_deffgun) have Deffgun (heavy) → should appear
	for mid in ["m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8"]:
		if not t34_heavy.has(mid) or "deffgun_ranged" not in t34_heavy[mid]:
			print("  FAIL: %s should have deffgun_ranged as heavy (got: %s)" % [mid, str(t34_heavy.get(mid, []))])
			t34_ok = false
	# m9-m10 (loota_kmb) should NOT appear (KMB is hazardous, not heavy)
	for mid in ["m9", "m10"]:
		if t34_heavy.has(mid):
			print("  FAIL: %s (loota_kmb) should NOT have heavy weapons (got: %s)" % [mid, str(t34_heavy[mid])])
			t34_ok = false
	# m11 (spanner) should NOT appear
	if t34_heavy.has("m11"):
		print("  FAIL: m11 (spanner) should NOT have heavy weapons (got: %s)" % str(t34_heavy["m11"]))
		t34_ok = false
	if t34_ok:
		print("  PASS: Heavy filter returns Deffgun only for deffgun-profiled models")
		passed += 1
	else:
		failed += 1

	# --- Test 35: Rapid fire filter with profiled unit (Lootas) ---
	print("\n--- Test 35: MA-30 Rapid fire filter with profiled unit (Lootas) ---")
	var t35_rf = _filter_unit_weapons("U_LOOTAS_A", "rapid fire", ork_board)
	var t35_ok = true
	# Deffgun has "rapid fire 1" → only deffgun models should appear
	for mid in ["m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8"]:
		if not t35_rf.has(mid) or "deffgun_ranged" not in t35_rf[mid]:
			print("  FAIL: %s should have deffgun_ranged as rapid fire (got: %s)" % [mid, str(t35_rf.get(mid, []))])
			t35_ok = false
	# KMB models should NOT appear (hazardous, not rapid fire)
	for mid in ["m9", "m10", "m11"]:
		if t35_rf.has(mid):
			print("  FAIL: %s should NOT have rapid fire weapons (got: %s)" % [mid, str(t35_rf[mid])])
			t35_ok = false
	if t35_ok:
		print("  PASS: Rapid fire filter returns Deffgun only for deffgun-profiled models")
		passed += 1
	else:
		failed += 1

	# --- Test 36: Assault filter with profiled unit (Intercessors) ---
	print("\n--- Test 36: MA-30 Assault filter with profiled unit ---")
	var t36_ok = true
	if not sm_data.is_empty():
		var t36_int = sm_data.get("units", {}).get("U_INTERCESSORS_A", {}).duplicate(true)
		t36_int["id"] = "U_INT_TEST"
		var t36_board = {"units": {"U_INT_TEST": t36_int}}
		var t36_assault = _filter_unit_weapons("U_INT_TEST", "assault", t36_board)
		# Both profiles include Bolt rifle (assault, heavy) → all 5 models get it
		if t36_assault.size() != 5:
			print("  FAIL: Expected 5 models with assault weapons, got %d" % t36_assault.size())
			t36_ok = false
		# Bolt pistol (pistol only) should NOT appear in assault filter
		for mid in t36_assault:
			if "bolt_pistol_ranged" in t36_assault[mid]:
				print("  FAIL: %s has bolt_pistol_ranged in assault filter (should be pistol only)" % mid)
				t36_ok = false
			if "bolt_rifle_ranged" not in t36_assault[mid]:
				print("  FAIL: %s missing bolt_rifle_ranged in assault filter" % mid)
				t36_ok = false
	else:
		print("  FAIL: space_marines.json not loaded")
		t36_ok = false
	if t36_ok:
		print("  PASS: Assault filter returns only assault-keyword weapons per profile")
		passed += 1
	else:
		failed += 1

	# --- Test 37: Torrent filter with profiled unit (negative test) ---
	print("\n--- Test 37: MA-30 Torrent filter with profiled unit (no torrent weapons) ---")
	var t37_torrent = _filter_unit_weapons("U_LOOTAS_A", "torrent", ork_board)
	if t37_torrent.is_empty():
		print("  PASS: Torrent filter correctly returns empty for Lootas (no torrent weapons)")
		passed += 1
	else:
		print("  FAIL: Expected empty torrent weapons for Lootas, got: %s" % str(t37_torrent))
		failed += 1

	# ═══════════════════════════════════════════════════════════════════════
	# MA-31: Unit tests for per-model combat resolution
	# These tests verify that combat resolution uses per-model stats correctly.
	# Since RulesEngine can't be loaded in headless SceneTree mode, we mirror
	# the relevant static functions directly.
	# ═══════════════════════════════════════════════════════════════════════

	# --- Test 38: MA-31 Mixed BS shooting — spanner BS4+ vs loota BS6+ ---
	print("\n--- Test 38: MA-31 Mixed BS shooting (Lootas: spanner BS4+, deffgun BS6+, KMB BS5+) ---")
	var t38_ok = true
	# Build weapon profile for Deffgun (bs=6 from JSON ballistic_skill:"6")
	var t38_deffgun_profile = {"bs": 6, "ws": 4}
	# Build weapon profile for KMB (bs=5 from JSON ballistic_skill:"5")
	var t38_kmb_profile = {"bs": 5, "ws": 4}
	var t38_lootas = army_data.get("units", {}).get("U_LOOTAS_A", {})
	var t38_models = t38_lootas.get("models", [])
	# Check each model's effective BS for the Deffgun
	for m in t38_models:
		var model_type = m.get("model_type", "")
		var effective_bs = _get_model_effective_bs(m, t38_lootas, t38_deffgun_profile)
		if model_type == "spanner":
			# Spanner has stats_override.ballistic_skill=4, overrides weapon BS6
			if effective_bs != 4:
				print("  FAIL: spanner model %s should have effective BS=4 for Deffgun, got %d" % [m.get("id", ""), effective_bs])
				t38_ok = false
		elif model_type == "loota_deffgun":
			# loota_deffgun has empty stats_override, uses weapon BS=6
			if effective_bs != 6:
				print("  FAIL: loota_deffgun model %s should have effective BS=6 for Deffgun, got %d" % [m.get("id", ""), effective_bs])
				t38_ok = false
		elif model_type == "loota_kmb":
			# loota_kmb has empty stats_override, uses weapon BS=6 for Deffgun
			# (they shouldn't fire Deffgun per profile, but testing BS resolution)
			if effective_bs != 6:
				print("  FAIL: loota_kmb model %s should have effective BS=6 for Deffgun, got %d" % [m.get("id", ""), effective_bs])
				t38_ok = false
	# Also check KMB weapon profile BS for spanner (should override to 4)
	for m in t38_models:
		var model_type = m.get("model_type", "")
		if model_type == "spanner":
			var eff_bs_kmb = _get_model_effective_bs(m, t38_lootas, t38_kmb_profile)
			if eff_bs_kmb != 4:
				print("  FAIL: spanner should have effective BS=4 for KMB too, got %d" % eff_bs_kmb)
				t38_ok = false
		elif model_type == "loota_kmb":
			var eff_bs_kmb = _get_model_effective_bs(m, t38_lootas, t38_kmb_profile)
			if eff_bs_kmb != 5:
				print("  FAIL: loota_kmb should have effective BS=5 for KMB (weapon default), got %d" % eff_bs_kmb)
				t38_ok = false
	if t38_ok:
		print("  PASS: Mixed BS correctly resolved — spanner BS4+, loota_deffgun BS6+, loota_kmb BS5+ (weapon default)")
		passed += 1
	else:
		failed += 1

	# --- Test 39: MA-31 bs_per_attack array built correctly for mixed BS ---
	print("\n--- Test 39: MA-31 bs_per_attack array for mixed-BS Deffgun assignment ---")
	var t39_ok = true
	# Simulate resolve_shooting_assignment: build bs_per_attack for Deffgun
	# Only deffgun-profiled models (m1-m8) fire Deffgun; spanner has override BS4
	# Deffgun: attacks=2 per model, so 8 deffgun models + (spanner doesn't have Deffgun per profile)
	# But spanner DOES have KMB, not Deffgun — so only m1-m8 fire Deffgun
	var t39_deffgun_models = []
	var t39_bs_per_attack = []
	for m in t38_models:
		var mt = m.get("model_type", "")
		var profile_weapons = mp.get(mt, {}).get("weapons", []) if mp is Dictionary else []
		if "Deffgun" in profile_weapons and m.get("alive", true):
			t39_deffgun_models.append(m.get("id", ""))
			var model_bs = _get_model_effective_bs(m, t38_lootas, t38_deffgun_profile)
			# Deffgun has attacks=2, so 2 entries per model
			for _j in range(2):
				t39_bs_per_attack.append(model_bs)
	# Should be 8 models x 2 attacks = 16 entries, all with BS6
	if t39_deffgun_models.size() != 8:
		print("  FAIL: Expected 8 Deffgun models, got %d" % t39_deffgun_models.size())
		t39_ok = false
	if t39_bs_per_attack.size() != 16:
		print("  FAIL: Expected 16 bs_per_attack entries, got %d" % t39_bs_per_attack.size())
		t39_ok = false
	for bs_val in t39_bs_per_attack:
		if bs_val != 6:
			print("  FAIL: All Deffgun bs_per_attack should be 6, found %d" % bs_val)
			t39_ok = false
			break
	# Now simulate KMB assignment (m9, m10, m11) — m11 spanner gets BS4 override
	var t39_kmb_bs = []
	var t39_kmb_models = []
	for m in t38_models:
		var mt = m.get("model_type", "")
		var profile_weapons = mp.get(mt, {}).get("weapons", []) if mp is Dictionary else []
		if "Kustom mega-blasta" in profile_weapons and m.get("alive", true):
			t39_kmb_models.append(m.get("id", ""))
			var model_bs = _get_model_effective_bs(m, t38_lootas, t38_kmb_profile)
			# KMB has attacks=3, so 3 entries per model
			for _j in range(3):
				t39_kmb_bs.append(model_bs)
	# Should be 3 models (m9, m10 loota_kmb BS5; m11 spanner BS4) x 3 attacks = 9 entries
	if t39_kmb_models.size() != 3:
		print("  FAIL: Expected 3 KMB models, got %d (%s)" % [t39_kmb_models.size(), str(t39_kmb_models)])
		t39_ok = false
	# Count BS values: 2 models x BS5 x 3 attacks = 6 entries with BS5; 1 model x BS4 x 3 = 3 entries with BS4
	var t39_bs5_count = 0
	var t39_bs4_count = 0
	for bs_val in t39_kmb_bs:
		if bs_val == 5:
			t39_bs5_count += 1
		elif bs_val == 4:
			t39_bs4_count += 1
	if t39_bs5_count != 6:
		print("  FAIL: Expected 6 BS5 entries for KMB loota models, got %d" % t39_bs5_count)
		t39_ok = false
	if t39_bs4_count != 3:
		print("  FAIL: Expected 3 BS4 entries for KMB spanner model, got %d" % t39_bs4_count)
		t39_ok = false
	if t39_ok:
		print("  PASS: bs_per_attack correctly built — Deffgun: 16x BS6; KMB: 6x BS5 + 3x BS4")
		passed += 1
	else:
		failed += 1

	# --- Test 40: MA-31 Mixed WS melee (Boyz: boss_nob WS3+ vs boy WS4+) ---
	print("\n--- Test 40: MA-31 Mixed WS melee (Boyz_F: boss_nob WS3+, boy WS4+) ---")
	var t40_ok = true
	var t40_boyz = army_data.get("units", {}).get("U_BOYZ_F", {})
	var t40_models = t40_boyz.get("models", [])
	# Choppa weapon: ws=3 in JSON (weapon_skill:"3") for boss_nob-level,
	# but the weapon WS comes from the JSON weapon data
	# Let's check the weapon_skill for Choppa in the Boyz_F meta
	var t40_choppa_ws = 4  # default
	for w in t40_boyz.get("meta", {}).get("weapons", []):
		if w.get("name", "") == "Choppa" and w.get("type", "").to_lower() == "melee":
			var ws_str = w.get("weapon_skill", "4")
			t40_choppa_ws = int(ws_str) if ws_str.is_valid_int() else 4
			break
	var t40_choppa_profile = {"ws": t40_choppa_ws, "bs": 4}
	# boss_nob (model index 0, model_type="boss_nob") has WS3 override
	# boy (model indices 1-19, model_type="boy") has WS4 override
	var t40_ws_per_attack = []
	for m in t40_models:
		if not m.get("alive", true):
			continue
		var model_ws = _get_model_effective_ws(m, t40_boyz, t40_choppa_profile)
		# Choppa attacks = 3 per model
		for _j in range(3):
			t40_ws_per_attack.append(model_ws)
	# Check: 1 boss_nob x WS3 x 3 attacks = 3 entries; 19 boys x WS4 x 3 attacks = 57 entries
	var t40_ws3_count = 0
	var t40_ws4_count = 0
	for ws_val in t40_ws_per_attack:
		if ws_val == 3:
			t40_ws3_count += 1
		elif ws_val == 4:
			t40_ws4_count += 1
	if t40_ws3_count != 3:
		print("  FAIL: Expected 3 WS3 entries for boss_nob Choppa, got %d" % t40_ws3_count)
		t40_ok = false
	if t40_ws4_count != 57:
		print("  FAIL: Expected 57 WS4 entries for boy Choppa, got %d" % t40_ws4_count)
		t40_ok = false
	if t40_ok:
		print("  PASS: ws_per_attack correctly built — boss_nob: 3x WS3; boys: 57x WS4")
		passed += 1
	else:
		failed += 1

	# --- Test 41: MA-31 WS override only applies to models with matching model_type ---
	print("\n--- Test 41: MA-31 Unit without profiles uses weapon WS for all models ---")
	var t41_ok = true
	var t41_boyz_e = army_data.get("units", {}).get("U_BOYZ_E", {})
	var t41_models_e = t41_boyz_e.get("models", [])
	var t41_choppa_profile = {"ws": t40_choppa_ws, "bs": 4}
	# U_BOYZ_E has no model_profiles — all models should use weapon default WS
	for m in t41_models_e:
		if not m.get("alive", true):
			continue
		var ws = _get_model_effective_ws(m, t41_boyz_e, t41_choppa_profile)
		if ws != t40_choppa_ws:
			print("  FAIL: U_BOYZ_E model %s should use weapon WS=%d (no profiles), got %d" % [m.get("id", ""), t40_choppa_ws, ws])
			t41_ok = false
			break
	if t41_ok:
		print("  PASS: Unit without profiles uses weapon WS=%d for all models" % t40_choppa_ws)
		passed += 1
	else:
		failed += 1

	# --- Test 42: MA-31 Rapid Fire bonus only counts models with RF weapon ---
	print("\n--- Test 42: MA-31 Rapid Fire bonus only counts deffgun models (not KMB) ---")
	var t42_ok = true
	# Deffgun has "rapid fire 1" — only models with Deffgun in their profile should count
	# for rapid fire bonus. KMB models (m9, m10) and spanner (m11 — has KMB, not Deffgun) don't count.
	var t42_rf_model_count = 0
	var t42_non_rf_model_count = 0
	for m in t38_models:
		if not m.get("alive", true):
			continue
		var mt = m.get("model_type", "")
		var profile_weapons = mp.get(mt, {}).get("weapons", []) if mp is Dictionary else []
		if "Deffgun" in profile_weapons:
			t42_rf_model_count += 1
		else:
			t42_non_rf_model_count += 1
	# Only 8 deffgun models should count for RF, 3 models (2 KMB + 1 spanner) should not
	if t42_rf_model_count != 8:
		print("  FAIL: Expected 8 models with Deffgun (rapid fire eligible), got %d" % t42_rf_model_count)
		t42_ok = false
	if t42_non_rf_model_count != 3:
		print("  FAIL: Expected 3 models without Deffgun, got %d" % t42_non_rf_model_count)
		t42_ok = false
	# Verify KMB weapon does NOT have rapid fire keyword
	var t42_kmb_has_rf = false
	for w in t38_lootas.get("meta", {}).get("weapons", []):
		if w.get("name", "") == "Kustom mega-blasta":
			var sr = w.get("special_rules", "").to_lower()
			if "rapid fire" in sr:
				t42_kmb_has_rf = true
	if t42_kmb_has_rf:
		print("  FAIL: KMB should NOT have rapid fire keyword")
		t42_ok = false
	# Verify Deffgun DOES have rapid fire keyword
	var t42_deffgun_has_rf = false
	for w in t38_lootas.get("meta", {}).get("weapons", []):
		if w.get("name", "") == "Deffgun":
			var sr = w.get("special_rules", "").to_lower()
			if "rapid fire" in sr:
				t42_deffgun_has_rf = true
	if not t42_deffgun_has_rf:
		print("  FAIL: Deffgun should have rapid fire keyword")
		t42_ok = false
	if t42_ok:
		print("  PASS: Rapid Fire bonus only applies to 8 Deffgun models; 3 KMB/spanner excluded")
		passed += 1
	else:
		failed += 1

	# --- Test 43: MA-31 Rapid Fire model count matches per-model weapon assignment ---
	print("\n--- Test 43: MA-31 RF model count from weapon assignment matches ---")
	var t43_ok = true
	# Using the existing t35 rapid fire filter from MA-30, verify model count
	# t35_rf should only contain m1-m8 (the deffgun models), not m9-m11
	var t43_rf_weapons = _filter_unit_weapons("U_LOOTAS_A", "rapid fire", ork_board)
	if t43_rf_weapons.size() != 8:
		print("  FAIL: Expected 8 models with rapid fire weapons, got %d (keys: %s)" % [t43_rf_weapons.size(), str(t43_rf_weapons.keys())])
		t43_ok = false
	# Verify these are m1-m8
	for mid in ["m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8"]:
		if not t43_rf_weapons.has(mid):
			print("  FAIL: Model %s should be in RF weapon set" % mid)
			t43_ok = false
	for mid in ["m9", "m10", "m11"]:
		if t43_rf_weapons.has(mid):
			print("  FAIL: Model %s should NOT be in RF weapon set" % mid)
			t43_ok = false
	if t43_ok:
		print("  PASS: RF weapon assignment matches per-model profile (8 deffgun models only)")
		passed += 1
	else:
		failed += 1

	# --- Test 44: MA-31 Per-model save characteristics in wound allocation ---
	print("\n--- Test 44: MA-31 Per-model save characteristics ---")
	var t44_ok = true
	# Current implementation: base_save comes from unit.meta.stats.save (unit-level)
	# stats_override currently supports ballistic_skill, weapon_skill — save override
	# would follow the same pattern if/when added.
	# Test: verify save resolution uses unit base_save, and model_save_profiles
	# are built per-model (each model gets its own save entry)
	var t44_lootas_save = t38_lootas.get("meta", {}).get("stats", {}).get("save", 7)
	if t44_lootas_save != 5:
		print("  FAIL: Lootas base save should be 5+, got %d" % t44_lootas_save)
		t44_ok = false
	# Build model_save_profiles like prepare_save_resolution does
	var t44_save_profiles = []
	for i in range(t38_models.size()):
		var m = t38_models[i]
		if not m.get("alive", true):
			continue
		var model_type = m.get("model_type", "")
		# Check if model has a save override in stats_override
		var model_save = t44_lootas_save  # default to unit save
		var model_profile = mp.get(model_type, {}) if mp is Dictionary else {}
		var save_override = model_profile.get("stats_override", {}).get("save", -1)
		if save_override > 0:
			model_save = int(save_override)
		t44_save_profiles.append({
			"model_id": m.get("id", "m%d" % i),
			"model_type": model_type,
			"save": model_save
		})
	# All Lootas currently have unit save=5 (no save override in profiles)
	var t44_all_save_5 = true
	for sp in t44_save_profiles:
		if sp.save != 5:
			print("  FAIL: Model %s (type=%s) expected save=5, got %d" % [sp.model_id, sp.model_type, sp.save])
			t44_all_save_5 = false
			t44_ok = false
	if t44_save_profiles.size() != 11:
		print("  FAIL: Expected 11 save profiles, got %d" % t44_save_profiles.size())
		t44_ok = false
	if t44_ok:
		print("  PASS: 11 model_save_profiles built, all using unit base save=5+ (no save overrides in current profiles)")
		passed += 1
	else:
		failed += 1

	# --- Test 45: MA-31 Per-model save with hypothetical save override ---
	print("\n--- Test 45: MA-31 Per-model save with hypothetical save override ---")
	var t45_ok = true
	# Simulate: if spanner had stats_override.save=4, verify it would be used
	var t45_test_profiles = {
		"loota_deffgun": {"stats_override": {}, "weapons": ["Deffgun"]},
		"loota_kmb": {"stats_override": {}, "weapons": ["Kustom mega-blasta"]},
		"spanner": {"stats_override": {"ballistic_skill": 4, "save": 4}, "weapons": ["Kustom mega-blasta"]}
	}
	var t45_save_results = []
	for m in t38_models:
		var mt = m.get("model_type", "")
		var model_save = 5  # unit default
		var profile = t45_test_profiles.get(mt, {})
		var so = profile.get("stats_override", {}).get("save", -1)
		if so > 0:
			model_save = int(so)
		t45_save_results.append({"model_type": mt, "save": model_save})
	# Count: 8 deffgun save=5, 2 KMB save=5, 1 spanner save=4
	var t45_save5_count = 0
	var t45_save4_count = 0
	for sr in t45_save_results:
		if sr.save == 5:
			t45_save5_count += 1
		elif sr.save == 4:
			t45_save4_count += 1
	if t45_save5_count != 10:
		print("  FAIL: Expected 10 models with save=5, got %d" % t45_save5_count)
		t45_ok = false
	if t45_save4_count != 1:
		print("  FAIL: Expected 1 model (spanner) with save=4, got %d" % t45_save4_count)
		t45_ok = false
	if t45_ok:
		print("  PASS: Hypothetical save override correctly applied — spanner save=4+, others save=5+")
		passed += 1
	else:
		failed += 1

	# --- Test 46: MA-31 Hazardous weapon resolution — only KMB models risk hazardous ---
	print("\n--- Test 46: MA-31 Hazardous resolution — only KMB-carrying models risk hazardous ---")
	var t46_ok = true
	# KMB has "hazardous" in special_rules, Deffgun does not
	var t46_kmb_is_hazardous = false
	var t46_deffgun_is_hazardous = false
	for w in t38_lootas.get("meta", {}).get("weapons", []):
		var sr = w.get("special_rules", "").to_lower()
		if w.get("name", "") == "Kustom mega-blasta" and "hazardous" in sr:
			t46_kmb_is_hazardous = true
		if w.get("name", "") == "Deffgun" and "hazardous" in sr:
			t46_deffgun_is_hazardous = true
	if not t46_kmb_is_hazardous:
		print("  FAIL: KMB should have hazardous keyword")
		t46_ok = false
	if t46_deffgun_is_hazardous:
		print("  FAIL: Deffgun should NOT have hazardous keyword")
		t46_ok = false
	# Count which models would trigger hazardous checks:
	# Only models whose profile includes KMB fire it, so only they risk hazardous
	var t46_hazardous_models = []
	var t46_safe_models = []
	for m in t38_models:
		var mt = m.get("model_type", "")
		var profile_weapons = mp.get(mt, {}).get("weapons", []) if mp is Dictionary else []
		if "Kustom mega-blasta" in profile_weapons:
			t46_hazardous_models.append(m.get("id", ""))
		else:
			t46_safe_models.append(m.get("id", ""))
	# 3 models fire KMB (m9, m10 loota_kmb + m11 spanner) → 3 hazardous checks
	if t46_hazardous_models.size() != 3:
		print("  FAIL: Expected 3 models with hazardous KMB, got %d (%s)" % [t46_hazardous_models.size(), str(t46_hazardous_models)])
		t46_ok = false
	# 8 deffgun models are safe (no hazardous)
	if t46_safe_models.size() != 8:
		print("  FAIL: Expected 8 safe models (deffgun), got %d" % t46_safe_models.size())
		t46_ok = false
	if t46_ok:
		print("  PASS: Only 3 KMB models (m9, m10, m11) risk hazardous; 8 Deffgun models safe")
		passed += 1
	else:
		failed += 1

	# --- Test 47: MA-31 Hazardous allocation target prioritizes KMB-carrying models ---
	print("\n--- Test 47: MA-31 Hazardous allocation targets model with hazardous weapon ---")
	var t47_ok = true
	# Per Balance Dataslate v3.3, hazardous mortal wounds go to models that
	# have the hazardous weapon. For Lootas, that's KMB models (m9, m10, m11).
	# The _find_hazardous_allocation_target logic checks if each model has a
	# hazardous weapon. Deffgun models should NOT be allocation targets.
	# Simulate: check which models "have" a hazardous weapon
	var t47_kmb_weapon_id = _gen_weapon_id("Kustom mega-blasta", "Ranged")
	var t47_models_with_hazardous = []
	var t47_models_without_hazardous = []
	for m in t38_models:
		var mt = m.get("model_type", "")
		var profile_weapons = mp.get(mt, {}).get("weapons", []) if mp is Dictionary else []
		if "Kustom mega-blasta" in profile_weapons:
			t47_models_with_hazardous.append(m.get("id", ""))
		else:
			t47_models_without_hazardous.append(m.get("id", ""))
	# Allocation should go to a model WITH the hazardous weapon (m9, m10, or m11)
	if t47_models_with_hazardous.size() != 3:
		print("  FAIL: Expected 3 models with hazardous weapon, got %d" % t47_models_with_hazardous.size())
		t47_ok = false
	if t47_models_without_hazardous.size() != 8:
		print("  FAIL: Expected 8 models without hazardous weapon, got %d" % t47_models_without_hazardous.size())
		t47_ok = false
	# Verify the deffgun models would NOT be allocated hazardous wounds
	for mid in t47_models_without_hazardous:
		if mid in ["m9", "m10", "m11"]:
			print("  FAIL: Model %s should be in hazardous group, not safe group" % mid)
			t47_ok = false
	if t47_ok:
		print("  PASS: Hazardous allocation correctly targets KMB models (m9/m10/m11), not Deffgun models")
		passed += 1
	else:
		failed += 1

	# --- Test 48: MA-31 One-shot tracking with per-model weapons ---
	print("\n--- Test 48: MA-31 One-shot tracking per model ---")
	var t48_ok = true
	# One-shot weapons are tracked per model in unit.flags.one_shot_fired = { model_id: [weapon_ids] }
	# Test: marking one model's one-shot as fired doesn't affect other models
	var t48_unit = {
		"id": "TEST_UNIT",
		"flags": {},
		"models": [
			{"id": "m1", "alive": true, "model_type": "type_a"},
			{"id": "m2", "alive": true, "model_type": "type_a"},
			{"id": "m3", "alive": true, "model_type": "type_b"}
		]
	}
	var t48_weapon_id = "test_oneshot_ranged"
	# Initially no one-shot fired
	if _has_fired_one_shot(t48_unit, "m1", t48_weapon_id):
		print("  FAIL: m1 should NOT have fired one-shot initially")
		t48_ok = false
	if _has_fired_one_shot(t48_unit, "m2", t48_weapon_id):
		print("  FAIL: m2 should NOT have fired one-shot initially")
		t48_ok = false
	# Mark m1 as having fired
	_mark_one_shot_fired(t48_unit, "m1", t48_weapon_id)
	# m1 should now be marked, m2 and m3 should not
	if not _has_fired_one_shot(t48_unit, "m1", t48_weapon_id):
		print("  FAIL: m1 SHOULD have fired one-shot after marking")
		t48_ok = false
	if _has_fired_one_shot(t48_unit, "m2", t48_weapon_id):
		print("  FAIL: m2 should NOT have fired one-shot (only m1 was marked)")
		t48_ok = false
	if _has_fired_one_shot(t48_unit, "m3", t48_weapon_id):
		print("  FAIL: m3 should NOT have fired one-shot (only m1 was marked)")
		t48_ok = false
	if t48_ok:
		print("  PASS: One-shot tracking is per-model — marking m1 doesn't affect m2/m3")
		passed += 1
	else:
		failed += 1

	# --- Test 49: MA-31 One-shot filter removes fired weapons per model ---
	print("\n--- Test 49: MA-31 One-shot filter removes fired weapons per model ---")
	var t49_ok = true
	# Build a weapons dict like get_unit_weapons returns
	var t49_weapons = {
		"m1": ["test_oneshot_ranged", "regular_weapon_ranged"],
		"m2": ["test_oneshot_ranged", "regular_weapon_ranged"],
		"m3": ["other_weapon_ranged"]
	}
	# Filter with unit from test 48 (m1 has fired one-shot)
	var t49_filtered = _filter_fired_one_shot_weapons(t49_weapons, t48_unit, t48_weapon_id)
	# m1 should have one-shot removed, m2 should keep it
	if "test_oneshot_ranged" in t49_filtered.get("m1", []):
		print("  FAIL: m1 should have one-shot weapon removed after firing")
		t49_ok = false
	if "regular_weapon_ranged" not in t49_filtered.get("m1", []):
		print("  FAIL: m1 should still have regular weapon")
		t49_ok = false
	if "test_oneshot_ranged" not in t49_filtered.get("m2", []):
		print("  FAIL: m2 should still have one-shot weapon (hasn't fired)")
		t49_ok = false
	if "regular_weapon_ranged" not in t49_filtered.get("m2", []):
		print("  FAIL: m2 should still have regular weapon")
		t49_ok = false
	if "other_weapon_ranged" not in t49_filtered.get("m3", []):
		print("  FAIL: m3 should still have its weapon (not one-shot)")
		t49_ok = false
	if t49_ok:
		print("  PASS: One-shot filter correctly removes fired weapon from m1 only, m2 keeps it")
		passed += 1
	else:
		failed += 1

	# --- Test 50: MA-31 BS override with empty model (fallback to weapon BS) ---
	print("\n--- Test 50: MA-31 BS override fallback — empty model uses weapon BS ---")
	var t50_ok = true
	# _get_model_effective_bs with empty model should return weapon default
	var t50_empty_bs = _get_model_effective_bs({}, t38_lootas, t38_deffgun_profile)
	if t50_empty_bs != 6:
		print("  FAIL: Empty model should fallback to weapon BS=6, got %d" % t50_empty_bs)
		t50_ok = false
	# Model with empty model_type should also fallback
	var t50_no_type_bs = _get_model_effective_bs({"id": "mx", "model_type": ""}, t38_lootas, t38_deffgun_profile)
	if t50_no_type_bs != 6:
		print("  FAIL: Model with empty model_type should fallback to weapon BS=6, got %d" % t50_no_type_bs)
		t50_ok = false
	if t50_ok:
		print("  PASS: BS fallback works — empty model and empty model_type use weapon BS")
		passed += 1
	else:
		failed += 1

	# --- Test 51: MA-31 WS override with empty model (fallback to weapon WS) ---
	print("\n--- Test 51: MA-31 WS override fallback — empty model uses weapon WS ---")
	var t51_ok = true
	var t51_choppa_profile = {"ws": 4, "bs": 4}
	var t51_empty_ws = _get_model_effective_ws({}, t40_boyz, t51_choppa_profile)
	if t51_empty_ws != 4:
		print("  FAIL: Empty model should fallback to weapon WS=4, got %d" % t51_empty_ws)
		t51_ok = false
	var t51_no_type_ws = _get_model_effective_ws({"id": "mx", "model_type": ""}, t40_boyz, t51_choppa_profile)
	if t51_no_type_ws != 4:
		print("  FAIL: Model with empty model_type should fallback to weapon WS=4, got %d" % t51_no_type_ws)
		t51_ok = false
	if t51_ok:
		print("  PASS: WS fallback works — empty model and empty model_type use weapon WS")
		passed += 1
	else:
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

# ═══════════════════════════════════════════════════════════════════════
# MA-30 Helper functions — mirror RulesEngine weapon assignment logic
# (RulesEngine can't be preloaded due to compile-time Measurement dependency)
# ═══════════════════════════════════════════════════════════════════════

# Mirrors RulesEngine._generate_weapon_id
func _gen_weapon_id(weapon_name: String, weapon_type: String = "") -> String:
	var wid = weapon_name.to_lower()
	wid = wid.replace(" ", "_")
	wid = wid.replace("-", "_")
	wid = wid.replace("–", "_")
	wid = wid.replace("'", "")
	if weapon_type != "":
		wid += "_" + weapon_type.to_lower()
	return wid

# Mirrors RulesEngine._get_model_weapon_ids
func _get_model_weapon_ids(unit: Dictionary, model: Dictionary, type_filter: String) -> Array:
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
		if wtype.to_lower() != type_filter.to_lower():
			continue
		var wname = weapon.get("name", "")
		if use_profile and wname not in allowed_weapon_names:
			continue
		var weapon_id = _gen_weapon_id(wname, wtype)
		if weapon_id not in weapon_ids:
			weapon_ids.append(weapon_id)
	return weapon_ids

# Mirrors RulesEngine.get_unit_weapons (ranged only, with attached characters)
func _get_unit_ranged_weapons(unit_id: String, board: Dictionary) -> Dictionary:
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	if unit.is_empty():
		return {}
	var result = {}
	for model in unit.get("models", []):
		var model_id = model.get("id", "")
		if model_id != "" and model.get("alive", true):
			result[model_id] = _get_model_weapon_ids(unit, model, "Ranged")
	# Include attached character weapons with composite IDs
	var attached_chars = unit.get("attachment_data", {}).get("attached_characters", [])
	for char_id in attached_chars:
		var char_unit = units.get(char_id, {})
		if char_unit.is_empty():
			continue
		for char_model in char_unit.get("models", []):
			var char_model_id = char_model.get("id", "")
			if char_model_id != "" and char_model.get("alive", true):
				var composite_id = "%s:%s" % [char_id, char_model_id]
				result[composite_id] = _get_model_weapon_ids(char_unit, char_model, "Ranged")
	return result

# Mirrors RulesEngine.get_unit_melee_weapons
func _get_unit_melee_weapons(unit_id: String, board: Dictionary) -> Dictionary:
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	if unit.is_empty():
		return {}
	var weapons_data = unit.get("meta", {}).get("weapons", [])
	var model_profiles = unit.get("meta", {}).get("model_profiles", {})
	var all_melee = []
	for w in weapons_data:
		if w.get("type", "").to_lower() == "melee":
			var wn = w.get("name", "Unknown Weapon")
			if wn not in all_melee:
				all_melee.append(wn)
	var result = {}
	var models = unit.get("models", [])
	for i in range(models.size()):
		var model = models[i]
		if not model.get("alive", true):
			continue
		var model_id = "m" + str(i)
		var model_type = model.get("model_type", "")
		if not model_profiles.is_empty() and model_type != "" and model_profiles.has(model_type):
			var prof_weapons = model_profiles[model_type].get("weapons", [])
			var model_melee = []
			for w in weapons_data:
				if w.get("type", "").to_lower() == "melee" and w.get("name", "") in prof_weapons:
					var wn = w.get("name", "Unknown Weapon")
					if wn not in model_melee:
						model_melee.append(wn)
			if not model_melee.is_empty():
				result[model_id] = model_melee
		else:
			if not all_melee.is_empty():
				result[model_id] = all_melee.duplicate()
	return result

# Check if a weapon's special_rules contains a keyword (case-insensitive substring)
func _weapon_has_keyword(weapon_id: String, keyword: String, board: Dictionary) -> bool:
	var units = board.get("units", {})
	for uid in units:
		for w in units[uid].get("meta", {}).get("weapons", []):
			var wname = w.get("name", "")
			var wtype = w.get("type", "")
			if _gen_weapon_id(wname, wtype) == weapon_id:
				var sr = w.get("special_rules", "").to_lower()
				if keyword.to_lower() in sr:
					return true
				return false
	return false

# Filter a unit's ranged weapons by keyword (mirrors get_unit_pistol/assault/heavy_weapons)
func _filter_unit_weapons(unit_id: String, keyword: String, board: Dictionary) -> Dictionary:
	var result = {}
	var unit_weapons = _get_unit_ranged_weapons(unit_id, board)
	for model_id in unit_weapons:
		var filtered = []
		for wid in unit_weapons[model_id]:
			if _weapon_has_keyword(wid, keyword, board):
				filtered.append(wid)
		if not filtered.is_empty():
			result[model_id] = filtered
	return result

# ═══════════════════════════════════════════════════════════════════════
# MA-31 Helper functions — mirror RulesEngine combat resolution logic
# ═══════════════════════════════════════════════════════════════════════

# Mirrors RulesEngine._get_model_effective_bs
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

# Mirrors RulesEngine._get_model_effective_ws
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

# Mirrors RulesEngine.has_fired_one_shot
func _has_fired_one_shot(unit: Dictionary, model_id: String, weapon_id: String) -> bool:
	var fired = unit.get("flags", {}).get("one_shot_fired", {})
	var model_fired = fired.get(model_id, [])
	return weapon_id in model_fired

# Mirrors RulesEngine.mark_one_shot_fired_diffs (mutates unit in-place for test simplicity)
func _mark_one_shot_fired(unit: Dictionary, model_id: String, weapon_id: String) -> void:
	if not unit.has("flags"):
		unit["flags"] = {}
	var flags = unit["flags"]
	if not flags.has("one_shot_fired"):
		flags["one_shot_fired"] = {}
	var one_shot_fired = flags["one_shot_fired"]
	if not one_shot_fired.has(model_id):
		one_shot_fired[model_id] = [weapon_id]
	elif weapon_id not in one_shot_fired[model_id]:
		one_shot_fired[model_id].append(weapon_id)

# Mirrors RulesEngine.filter_fired_one_shot_weapons (simplified — checks one specific weapon_id)
func _filter_fired_one_shot_weapons(weapons_dict: Dictionary, unit: Dictionary, one_shot_weapon_id: String) -> Dictionary:
	var result = {}
	for model_id in weapons_dict:
		var weapons = weapons_dict[model_id]
		var filtered = []
		for wid in weapons:
			# If this weapon is the one-shot and model has fired it, skip
			if wid == one_shot_weapon_id and _has_fired_one_shot(unit, model_id, wid):
				continue
			filtered.append(wid)
		result[model_id] = filtered
	return result
