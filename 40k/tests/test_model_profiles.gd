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
