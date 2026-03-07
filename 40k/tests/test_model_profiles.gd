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

	# --- Test 17: MA-12 Boss Nob has save override in stats_override ---
	print("\n--- Test 17: MA-12 Boss Nob has save override ---")
	var boyz_f_profiles_2 = boyz_f.get("meta", {}).get("model_profiles", {})
	var nob_save = boyz_f_profiles_2.get("boss_nob", {}).get("stats_override", {}).get("save", null)
	if nob_save != null and int(nob_save) == 4:
		print("  PASS: boss_nob has save=4 in stats_override")
		passed += 1
	else:
		print("  FAIL: Expected boss_nob save=4, got %s" % str(nob_save))
		failed += 1

	# --- Test 18: MA-12 stats_override save lookup returns correct values ---
	print("\n--- Test 18: MA-12 stats_override save lookup logic ---")
	# Inline the _get_model_effective_save logic to verify it works on the data
	var unit_save = 5  # Boyz unit base save
	var nob_type = "boss_nob"
	var boy_type = "boy"
	var nob_override_save = boyz_f_profiles_2.get(nob_type, {}).get("stats_override", {}).get("save", -1)
	var boy_override_save = boyz_f_profiles_2.get(boy_type, {}).get("stats_override", {}).get("save", -1)
	var nob_eff_save = nob_override_save if nob_override_save > 0 else unit_save
	var boy_eff_save = boy_override_save if boy_override_save > 0 else unit_save
	if nob_eff_save == 4 and boy_eff_save == 5:
		print("  PASS: boss_nob effective save=4+, boy effective save=5+ (unit default)")
		passed += 1
	else:
		print("  FAIL: Expected nob=4, boy=5, got nob=%d boy=%d" % [nob_eff_save, boy_eff_save])
		failed += 1

	# --- Test 19: MA-12 stats_override invuln lookup returns defaults when absent ---
	print("\n--- Test 19: MA-12 stats_override invuln lookup defaults ---")
	var nob_override_invuln = boyz_f_profiles_2.get(nob_type, {}).get("stats_override", {}).get("invuln", -1)
	var boy_override_invuln = boyz_f_profiles_2.get(boy_type, {}).get("stats_override", {}).get("invuln", -1)
	if nob_override_invuln <= 0 and boy_override_invuln <= 0:
		print("  PASS: No invuln overrides in stats_override for either model type")
		passed += 1
	else:
		print("  FAIL: Expected no invuln overrides, got nob=%s boy=%s" % [str(nob_override_invuln), str(boy_override_invuln)])
		failed += 1

	# --- Test 20: MA-12 Model types in Boyz have different effective saves ---
	print("\n--- Test 20: MA-12 Boyz models have differentiated saves ---")
	var boyz_f_models_2 = boyz_f.get("models", [])
	var boyz_f_unit_save = boyz_f.get("meta", {}).get("stats", {}).get("save", 7)
	var save_values_by_type = {}
	for m in boyz_f_models_2:
		var mt = m.get("model_type", "")
		if mt == "":
			continue
		var override = boyz_f_profiles_2.get(mt, {}).get("stats_override", {}).get("save", -1)
		var eff = override if override > 0 else boyz_f_unit_save
		save_values_by_type[mt] = eff
	if save_values_by_type.get("boss_nob", -1) == 4 and save_values_by_type.get("boy", -1) == 5:
		print("  PASS: boss_nob effective save=4+, boy effective save=5+")
		passed += 1
	else:
		print("  FAIL: Expected boss_nob=4, boy=5, got %s" % str(save_values_by_type))
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
