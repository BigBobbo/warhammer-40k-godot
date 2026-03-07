extends SceneTree

# Test: Model Profiles (MA-1 through MA-8)
# Verifies model_profiles schema, per-model weapon assignment, and weapon filter functions
# Usage: godot --headless --path . -s tests/test_model_profiles.gd

var _passed = 0
var _failed = 0
var _army_data = {}
var _sm_data = {}
var _ran_ma8 = false

func _init():
	print("\n=== Test Model Profiles Schema (MA-1) ===\n")

	# --- Test 1: Load orks.json and verify model_profiles exists on Lootas ---
	print("--- Test 1: model_profiles loaded from orks.json ---")
	_army_data = _load_army_json("orks")
	if _army_data.is_empty():
		print("  FAIL: Could not load orks.json")
		_failed += 1
	else:
		var lootas = _army_data.get("units", {}).get("U_LOOTAS_A", {})
		var meta = lootas.get("meta", {})
		if meta.has("model_profiles"):
			print("  PASS: model_profiles found in U_LOOTAS_A meta")
			_passed += 1
		else:
			print("  FAIL: model_profiles not found in U_LOOTAS_A meta")
			_failed += 1

	# --- Test 2: model_profiles is a Dictionary ---
	print("\n--- Test 2: model_profiles is a Dictionary ---")
	var mp = _army_data.get("units", {}).get("U_LOOTAS_A", {}).get("meta", {}).get("model_profiles", null)
	if mp is Dictionary:
		print("  PASS: model_profiles is a Dictionary")
		_passed += 1
	else:
		print("  FAIL: model_profiles is not a Dictionary (type: %s)" % typeof(mp))
		_failed += 1

	# --- Test 3: Profile keys exist ---
	print("\n--- Test 3: Expected profile keys exist ---")
	if mp is Dictionary and mp.has("loota_deffgun") and mp.has("loota_kmb") and mp.has("spanner"):
		print("  PASS: Found loota_deffgun, loota_kmb, and spanner profiles")
		_passed += 1
	else:
		print("  FAIL: Missing expected profile keys (got: %s)" % str(mp.keys() if mp is Dictionary else "null"))
		_failed += 1

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
			_passed += 1
		else:
			_failed += 1
	else:
		print("  FAIL: model_profiles is not a Dictionary")
		_failed += 1

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
			_passed += 1
		else:
			_failed += 1
	else:
		print("  FAIL: model_profiles is not a Dictionary")
		_failed += 1

	# --- Test 6: Weapon references are valid ---
	print("\n--- Test 6: Weapon references in profiles match meta.weapons ---")
	var weapons_ok = true
	var meta = _army_data.get("units", {}).get("U_LOOTAS_A", {}).get("meta", {})
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
			_passed += 1
		else:
			_failed += 1
	else:
		print("  FAIL: model_profiles is not a Dictionary")
		_failed += 1

	# --- Test 7: Units without model_profiles still work (backward compat) ---
	print("\n--- Test 7: Units without model_profiles work unchanged ---")
	var boyz_unit = _army_data.get("units", {}).get("U_BOYZ_E", {})
	var boyz_meta = boyz_unit.get("meta", {})
	if not boyz_meta.has("model_profiles"):
		# Verify it still has weapons and stats
		if boyz_meta.has("weapons") and boyz_meta.has("stats"):
			print("  PASS: U_BOYZ_E works without model_profiles (has weapons and stats)")
			_passed += 1
		else:
			print("  FAIL: U_BOYZ_E is missing weapons or stats")
			_failed += 1
	else:
		print("  FAIL: U_BOYZ_E should NOT have model_profiles")
		_failed += 1

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
			_passed += 1
		else:
			print("  FAIL: loota_deffgun values incorrect (label=%s, deffgun=%s, ccw=%s, ts=%d)" % [label_ok, has_deffgun, has_ccw, ts])
			_failed += 1
	else:
		print("  FAIL: loota_deffgun profile not found")
		_failed += 1

	# --- Test 9: MA-5 Lootas has 3 model types with correct counts ---
	print("\n--- Test 9: MA-5 Lootas heterogeneous model types ---")
	var lootas_models = _army_data.get("units", {}).get("U_LOOTAS_A", {}).get("models", [])
	var type_counts = {}
	for m in lootas_models:
		var mt = m.get("model_type", "")
		type_counts[mt] = type_counts.get(mt, 0) + 1
	if lootas_models.size() == 11 and type_counts.get("loota_deffgun", 0) == 8 and type_counts.get("loota_kmb", 0) == 2 and type_counts.get("spanner", 0) == 1:
		print("  PASS: 11 models with 8x loota_deffgun, 2x loota_kmb, 1x spanner")
		_passed += 1
	else:
		print("  FAIL: Expected 11 models (8 loota_deffgun, 2 loota_kmb, 1 spanner), got %d models: %s" % [lootas_models.size(), str(type_counts)])
		_failed += 1

	# --- Test 10: MA-5 Spanner profile has BS4+ stats_override ---
	print("\n--- Test 10: MA-5 Spanner profile has stats_override ---")
	var spanner_profile = mp.get("spanner", {}) if mp is Dictionary else {}
	var spanner_bs = spanner_profile.get("stats_override", {}).get("ballistic_skill", null)
	if spanner_bs != null and int(spanner_bs) == 4:
		print("  PASS: spanner profile has ballistic_skill=4 stats_override")
		_passed += 1
	else:
		print("  FAIL: spanner profile stats_override.ballistic_skill expected 4, got %s" % str(spanner_bs))
		_failed += 1

	# --- Test 11: MA-5 loota_kmb profile has KMB weapon ---
	print("\n--- Test 11: MA-5 loota_kmb profile weapons ---")
	var kmb_profile = mp.get("loota_kmb", {}) if mp is Dictionary else {}
	var kmb_weapons = kmb_profile.get("weapons", [])
	if "Kustom mega-blasta" in kmb_weapons and "Close combat weapon" in kmb_weapons:
		print("  PASS: loota_kmb profile has Kustom mega-blasta and Close combat weapon")
		_passed += 1
	else:
		print("  FAIL: loota_kmb weapons expected [Kustom mega-blasta, Close combat weapon], got %s" % str(kmb_weapons))
		_failed += 1

	# --- Test 12: MA-5 Space Marines Intercessors heterogeneous ---
	print("\n--- Test 12: MA-5 Space Marines Intercessor Squad heterogeneous ---")
	_sm_data = _load_army_json("space_marines")
	if _sm_data.is_empty():
		print("  FAIL: Could not load space_marines.json")
		_failed += 1
	else:
		var intercessors = _sm_data.get("units", {}).get("U_INTERCESSORS_A", {})
		var sm_meta = intercessors.get("meta", {})
		var sm_profiles = sm_meta.get("model_profiles", {})
		var sm_models = intercessors.get("models", [])
		var sm_type_counts = {}
		for m in sm_models:
			var mt = m.get("model_type", "")
			sm_type_counts[mt] = sm_type_counts.get(mt, 0) + 1
		if sm_profiles.has("intercessor") and sm_profiles.has("intercessor_sergeant") and sm_type_counts.get("intercessor", 0) == 4 and sm_type_counts.get("intercessor_sergeant", 0) == 1:
			print("  PASS: 5 models with 1x intercessor_sergeant, 4x intercessor")
			_passed += 1
		else:
			print("  FAIL: Expected profiles [intercessor, intercessor_sergeant] with counts 4+1, got profiles=%s counts=%s" % [str(sm_profiles.keys()), str(sm_type_counts)])
			_failed += 1

	# --- Test 13: MA-5 Intercessor Sergeant has Power fist ---
	print("\n--- Test 13: MA-5 Intercessor Sergeant profile weapons ---")
	if not _sm_data.is_empty():
		var sm_profiles2 = _sm_data.get("units", {}).get("U_INTERCESSORS_A", {}).get("meta", {}).get("model_profiles", {})
		var sgt_profile = sm_profiles2.get("intercessor_sergeant", {})
		var sgt_weapons = sgt_profile.get("weapons", [])
		if "Power fist" in sgt_weapons and "Bolt rifle" in sgt_weapons:
			print("  PASS: intercessor_sergeant has Power fist and Bolt rifle")
			_passed += 1
		else:
			print("  FAIL: intercessor_sergeant weapons expected Power fist + Bolt rifle, got %s" % str(sgt_weapons))
			_failed += 1
	else:
		print("  FAIL: space_marines.json not loaded")
		_failed += 1

	# --- Test 14: MA-5 All weapon references valid in SM Intercessors ---
	print("\n--- Test 14: MA-5 SM Intercessor weapon references valid ---")
	if not _sm_data.is_empty():
		var sm_meta2 = _sm_data.get("units", {}).get("U_INTERCESSORS_A", {}).get("meta", {})
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
			_passed += 1
		else:
			_failed += 1
	else:
		print("  FAIL: space_marines.json not loaded")
		_failed += 1

	# MA-8 tests run in _process() after autoloads are initialized

func _process(_delta):
	if _ran_ma8:
		return true  # Returning true from _process signals SceneTree to quit
	_ran_ma8 = true

	# =============================================
	# MA-8: Weapon filter functions per-model tests
	# =============================================
	# These tests verify that get_unit_*_weapons() filter functions
	# correctly return per-model results when model_profiles exist.
	# The filter functions call get_unit_weapons() (updated in MA-6)
	# which already handles per-model weapon assignment, then further
	# filter by keyword (Heavy, Rapid Fire, Pistol, Assault, Torrent).

	print("\n=== MA-8: Weapon Filter Functions Per-Model Tests ===")

	# Build a board dictionary from the army data for RulesEngine calls
	var board = {"units": _army_data.get("units", {})}

	# Get RulesEngine autoload at runtime
	var RE = root.get_node_or_null("RulesEngine")
	if RE == null:
		print("  FAIL: RulesEngine autoload not available")
		_failed += 8
		_print_summary()
		quit(1)
		return true

	# --- Test 15: MA-8 get_unit_heavy_weapons returns deffgun only for deffgun models ---
	print("\n--- Test 15: MA-8 get_unit_heavy_weapons per-model (Lootas) ---")
	var heavy_weapons = RE.get_unit_heavy_weapons("U_LOOTAS_A", board)
	var heavy_ok = true
	var heavy_model_count = heavy_weapons.size()
	# Should have exactly 8 models (m1-m8 are loota_deffgun)
	if heavy_model_count != 8:
		print("  FAIL: Expected 8 models with heavy weapons, got %d" % heavy_model_count)
		heavy_ok = false
	# Verify only deffgun models appear
	for mid in heavy_weapons:
		if mid not in ["m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8"]:
			print("  FAIL: Unexpected model '%s' in heavy weapons (should only be deffgun models)" % mid)
			heavy_ok = false
	# KMB/spanner models (m9, m10, m11) should NOT appear
	if heavy_weapons.has("m9") or heavy_weapons.has("m10") or heavy_weapons.has("m11"):
		print("  FAIL: KMB/spanner models should not have heavy weapons")
		heavy_ok = false
	if heavy_ok:
		print("  PASS: get_unit_heavy_weapons returns deffgun only for 8 deffgun models")
		_passed += 1
	else:
		_failed += 1

	# --- Test 16: MA-8 get_unit_rapid_fire_weapons returns deffgun only for deffgun models ---
	print("\n--- Test 16: MA-8 get_unit_rapid_fire_weapons per-model (Lootas) ---")
	var rf_weapons = RE.get_unit_rapid_fire_weapons("U_LOOTAS_A", board)
	var rf_ok = true
	var rf_model_count = rf_weapons.size()
	if rf_model_count != 8:
		print("  FAIL: Expected 8 models with rapid fire weapons, got %d" % rf_model_count)
		rf_ok = false
	for mid in rf_weapons:
		if mid not in ["m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8"]:
			print("  FAIL: Unexpected model '%s' in rapid fire weapons" % mid)
			rf_ok = false
	if rf_weapons.has("m9") or rf_weapons.has("m10") or rf_weapons.has("m11"):
		print("  FAIL: KMB/spanner models should not have rapid fire weapons")
		rf_ok = false
	if rf_ok:
		print("  PASS: get_unit_rapid_fire_weapons returns deffgun only for 8 deffgun models")
		_passed += 1
	else:
		_failed += 1

	# --- Test 17: MA-8 get_unit_pistol_weapons returns empty for Lootas (no pistol weapons) ---
	print("\n--- Test 17: MA-8 get_unit_pistol_weapons empty for Lootas ---")
	var pistol_weapons = RE.get_unit_pistol_weapons("U_LOOTAS_A", board)
	if pistol_weapons.is_empty():
		print("  PASS: No models have pistol weapons (correct — Lootas have no pistol weapons)")
		_passed += 1
	else:
		print("  FAIL: Expected empty pistol weapons, got %d models" % pistol_weapons.size())
		_failed += 1

	# --- Test 18: MA-8 get_unit_assault_weapons returns empty for Lootas (no assault weapons) ---
	print("\n--- Test 18: MA-8 get_unit_assault_weapons empty for Lootas ---")
	var assault_weapons = RE.get_unit_assault_weapons("U_LOOTAS_A", board)
	if assault_weapons.is_empty():
		print("  PASS: No models have assault weapons (correct — Lootas weapons lack Assault keyword)")
		_passed += 1
	else:
		print("  FAIL: Expected empty assault weapons, got %d models" % assault_weapons.size())
		_failed += 1

	# --- Test 19: MA-8 get_unit_torrent_weapons returns empty for Lootas (no torrent weapons) ---
	print("\n--- Test 19: MA-8 get_unit_torrent_weapons empty for Lootas ---")
	var torrent_weapons = RE.get_unit_torrent_weapons("U_LOOTAS_A", board)
	if torrent_weapons.is_empty():
		print("  PASS: No models have torrent weapons (correct — Lootas have no torrent weapons)")
		_passed += 1
	else:
		print("  FAIL: Expected empty torrent weapons, got %d models" % torrent_weapons.size())
		_failed += 1

	# --- Test 20: MA-8 unit_has_heavy_weapons works per-model (Lootas) ---
	print("\n--- Test 20: MA-8 unit_has_heavy_weapons returns true for Lootas ---")
	var has_heavy = RE.unit_has_heavy_weapons("U_LOOTAS_A", board)
	if has_heavy:
		print("  PASS: unit_has_heavy_weapons correctly returns true (deffgun models have Heavy)")
		_passed += 1
	else:
		print("  FAIL: unit_has_heavy_weapons should return true for Lootas (deffgun is Heavy)")
		_failed += 1

	# --- Test 21: MA-8 Backward compat - unit without model_profiles ---
	print("\n--- Test 21: MA-8 Backward compat - filter functions on unit without model_profiles ---")
	var boyz_weapons = RE.get_unit_weapons("U_BOYZ_E", board)
	var compat_ok = true
	if boyz_weapons.is_empty():
		print("  FAIL: get_unit_weapons should return weapons for U_BOYZ_E (no model_profiles = fallback)")
		compat_ok = false
	else:
		var boyz_models = board.get("units", {}).get("U_BOYZ_E", {}).get("models", [])
		var alive_count = 0
		for bm in boyz_models:
			if bm.get("alive", true):
				alive_count += 1
		if boyz_weapons.size() == alive_count:
			print("  PASS: All %d alive models have weapons assigned (fallback behavior)" % alive_count)
		else:
			print("  FAIL: Expected %d models with weapons, got %d" % [alive_count, boyz_weapons.size()])
			compat_ok = false
	if compat_ok:
		_passed += 1
	else:
		_failed += 1

	# --- Test 22: MA-8 Verify deffgun models get exactly one weapon (deffgun_ranged) ---
	print("\n--- Test 22: MA-8 Deffgun models get exactly deffgun weapon in heavy filter ---")
	var deffgun_check_ok = true
	for mid in heavy_weapons:
		var wlist = heavy_weapons[mid]
		if wlist.size() != 1:
			print("  FAIL: Model %s should have exactly 1 heavy weapon, got %d" % [mid, wlist.size()])
			deffgun_check_ok = false
		elif "deffgun" not in wlist[0].to_lower():
			print("  FAIL: Model %s heavy weapon should be deffgun, got '%s'" % [mid, wlist[0]])
			deffgun_check_ok = false
	if deffgun_check_ok and not heavy_weapons.is_empty():
		print("  PASS: All deffgun models have exactly 1 heavy weapon (deffgun)")
		_passed += 1
	elif heavy_weapons.is_empty():
		print("  FAIL: No heavy weapons to verify")
		_failed += 1
	else:
		_failed += 1

	# --- Summary ---
	_print_summary()
	if _failed > 0:
		quit(1)
	else:
		quit(0)
	return true

func _print_summary():
	print("\n=== Results: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("SOME TESTS FAILED")
	else:
		print("ALL TESTS PASSED")

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
