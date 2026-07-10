extends SceneTree

# Test: MA-24 Transport capacity respects per-model transport_slots
# Verifies the slot-aware counting logic used by TransportManager
# and the army JSON data for Meganobz transport_slots.
# Usage: godot --headless --path . -s tests/test_transport_slots.gd

func _init():
	print("\n=== Test Transport Slots (MA-24) ===\n")
	var passed = 0
	var failed = 0

	# --- Test 1: Meganob model returns transport_slots=2 ---
	print("--- Test 1: _get_model_transport_slots for Meganobz ---")
	var mega_unit = _make_meganobz_unit(5)
	var slots_m1 = _get_model_transport_slots(mega_unit, mega_unit.models[0])
	if slots_m1 == 2:
		print("  PASS: Meganob model transport_slots = 2")
		passed += 1
	else:
		print("  FAIL: Expected 2, got %d" % slots_m1)
		failed += 1

	# --- Test 2: Regular Boy model returns transport_slots=1 ---
	print("\n--- Test 2: _get_model_transport_slots for regular Boyz ---")
	var boyz_unit = _make_boyz_unit(10)
	var slots_boy = _get_model_transport_slots(boyz_unit, boyz_unit.models[0])
	if slots_boy == 1:
		print("  PASS: Boy model transport_slots = 1")
		passed += 1
	else:
		print("  FAIL: Expected 1, got %d" % slots_boy)
		failed += 1

	# --- Test 3: Unit without profiles returns transport_slots=1 ---
	print("\n--- Test 3: _get_model_transport_slots for unit without profiles ---")
	var no_profile_unit = _make_unit_no_profiles(5)
	var slots_np = _get_model_transport_slots(no_profile_unit, no_profile_unit.models[0])
	if slots_np == 1:
		print("  PASS: No-profile model transport_slots = 1")
		passed += 1
	else:
		print("  FAIL: Expected 1, got %d" % slots_np)
		failed += 1

	# --- Test 4: 5 Meganobz = 10 transport slots ---
	print("\n--- Test 4: _get_alive_model_count for 5 Meganobz = 10 slots ---")
	var count_mega = _get_alive_model_count(mega_unit)
	if count_mega == 10:
		print("  PASS: 5 Meganobz = 10 transport slots")
		passed += 1
	else:
		print("  FAIL: Expected 10, got %d" % count_mega)
		failed += 1

	# --- Test 5: 10 Boyz = 10 transport slots ---
	print("\n--- Test 5: _get_alive_model_count for 10 Boyz = 10 slots ---")
	var count_boyz = _get_alive_model_count(boyz_unit)
	if count_boyz == 10:
		print("  PASS: 10 Boyz = 10 transport slots")
		passed += 1
	else:
		print("  FAIL: Expected 10, got %d" % count_boyz)
		failed += 1

	# --- Test 6: 5 models without profiles = 5 slots ---
	print("\n--- Test 6: _get_alive_model_count for unit without profiles ---")
	var count_np = _get_alive_model_count(no_profile_unit)
	if count_np == 5:
		print("  PASS: 5 models without profiles = 5 transport slots")
		passed += 1
	else:
		print("  FAIL: Expected 5, got %d" % count_np)
		failed += 1

	# --- Test 7: Dead Meganobz don't count ---
	print("\n--- Test 7: Dead Meganobz don't count ---")
	var mega_with_dead = _make_meganobz_unit(5)
	mega_with_dead.models[0]["alive"] = false
	mega_with_dead.models[1]["alive"] = false
	var count_dead = _get_alive_model_count(mega_with_dead)
	if count_dead == 6:
		print("  PASS: 3 alive Meganobz = 6 transport slots (2 dead don't count)")
		passed += 1
	else:
		print("  FAIL: Expected 6, got %d" % count_dead)
		failed += 1

	# --- Test 8: Battlewagon scenario - 10 Boyz + 5 Meganobz = 20 slots (fits in 22) ---
	print("\n--- Test 8: Battlewagon capacity scenario ---")
	var capacity = 22
	var boyz_10 = _get_alive_model_count(_make_boyz_unit(10))  # 10 slots
	var mega_5 = _get_alive_model_count(_make_meganobz_unit(5))  # 10 slots
	var total_1 = boyz_10 + mega_5  # 20 slots
	if total_1 <= capacity:
		print("  PASS: 10 Boyz (10) + 5 Meganobz (10) = 20 slots fits in 22")
		passed += 1
	else:
		print("  FAIL: Expected %d <= %d" % [total_1, capacity])
		failed += 1

	# --- Test 9: +1 Meganob (2 more slots = 22) fits exactly at capacity ---
	print("\n--- Test 9: +1 Meganob fits exactly at capacity ---")
	var extra_mega = _get_alive_model_count(_make_meganobz_unit(1))  # 2 slots
	var total_2 = total_1 + extra_mega  # 22
	if total_2 <= capacity:
		print("  PASS: Adding 1 Meganob (2 slots) to 20 = 22 fits exactly in 22")
		passed += 1
	else:
		print("  FAIL: Expected %d <= %d" % [total_2, capacity])
		failed += 1

	# --- Test 10: +2 Meganobz (4 more slots = 24) exceeds capacity ---
	print("\n--- Test 10: +2 Meganobz exceeds capacity ---")
	var extra_mega2 = _get_alive_model_count(_make_meganobz_unit(2))  # 4 slots
	var total_3 = total_1 + extra_mega2  # 24
	if total_3 > capacity:
		print("  PASS: Adding 2 Meganobz (4 slots) to 20 = 24 exceeds 22 capacity")
		passed += 1
	else:
		print("  FAIL: Expected %d > %d" % [total_3, capacity])
		failed += 1

	# --- Test 11: Army JSON Meganobz unit has transport_slots=2 ---
	print("\n--- Test 11: Army JSON Meganobz has transport_slots=2 ---")
	var army_data = _load_army_json("orks")
	var mega_json = army_data.get("units", {}).get("U_MEGANOBZ_L", {})
	var mega_profiles = mega_json.get("meta", {}).get("model_profiles", {})
	var klaw_slots = int(mega_profiles.get("meganob_klaw", {}).get("transport_slots", 0))
	var saws_slots = int(mega_profiles.get("meganob_saws", {}).get("transport_slots", 0))
	if klaw_slots == 2 and saws_slots == 2:
		print("  PASS: JSON meganob_klaw and meganob_saws both have transport_slots=2")
		passed += 1
	else:
		print("  FAIL: Expected 2/2, got klaw=%d saws=%d" % [klaw_slots, saws_slots])
		failed += 1

	# --- Test 12: Army JSON Meganobz has MEGA ARMOUR keyword ---
	print("\n--- Test 12: Army JSON Meganobz has MEGA ARMOUR keyword ---")
	var mega_keywords = mega_json.get("meta", {}).get("keywords", [])
	if "MEGA ARMOUR" in mega_keywords:
		print("  PASS: Meganobz has MEGA ARMOUR keyword")
		passed += 1
	else:
		print("  FAIL: Missing MEGA ARMOUR keyword")
		failed += 1

	# --- Test 13: Army JSON slot count from loaded Meganobz models ---
	print("\n--- Test 13: Loaded Meganobz slot count from JSON ---")
	var mega_models_json = mega_json.get("models", [])
	var json_slot_count = 0
	for m in mega_models_json:
		var mt = m.get("model_type", "")
		var profile = mega_profiles.get(mt, {})
		json_slot_count += int(profile.get("transport_slots", 1))
	if json_slot_count == 10:
		print("  PASS: 5 Meganobz from JSON = 10 transport slots")
		passed += 1
	else:
		print("  FAIL: Expected 10, got %d" % json_slot_count)
		failed += 1

	# --- Test 14: Army JSON Battlewagon has capacity 22 ---
	print("\n--- Test 14: Battlewagon transport ability has capacity 22 ---")
	var bw = army_data.get("units", {}).get("U_BATTLEWAGON_G", {})
	var bw_abilities = bw.get("meta", {}).get("abilities", [])
	var found_capacity = false
	for ability in bw_abilities:
		if ability.get("name", "") == "TRANSPORT":
			var desc = ability.get("description", "")
			if "capacity of 22" in desc:
				found_capacity = true
	if found_capacity:
		print("  PASS: Battlewagon TRANSPORT ability has capacity of 22")
		passed += 1
	else:
		print("  FAIL: Battlewagon TRANSPORT ability missing or no 'capacity of 22'")
		failed += 1

	# --- Test 15: Battlewagon description mentions MEGA ARMOUR = 2 models ---
	print("\n--- Test 15: Battlewagon transport mentions MEGA ARMOUR rule ---")
	var found_mega_rule = false
	for ability in bw_abilities:
		if ability.get("name", "") == "TRANSPORT":
			var desc = ability.get("description", "")
			if "MEGA ARMOUR" in desc and "2 models" in desc:
				found_mega_rule = true
	if found_mega_rule:
		print("  PASS: Battlewagon transport description mentions MEGA ARMOUR taking 2 models")
		passed += 1
	else:
		print("  FAIL: Battlewagon transport description missing MEGA ARMOUR rule")
		failed += 1

	# --- Summary ---
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)


# --- Replicated TransportManager logic for testing ---
# These mirror the actual TransportManager functions to test the logic

func _get_model_transport_slots(unit: Dictionary, model: Dictionary) -> int:
	var model_type = model.get("model_type", null)
	if model_type == null or model_type == "":
		return 1
	var model_profiles = unit.get("meta", {}).get("model_profiles", {})
	if model_profiles.is_empty():
		return 1
	var profile = model_profiles.get(model_type, {})
	return int(profile.get("transport_slots", 1))

func _get_alive_model_count(unit: Dictionary) -> int:
	var count = 0
	if unit.has("models"):
		var has_profiles = unit.get("meta", {}).get("model_profiles", {}).size() > 0
		for model in unit.models:
			if model.get("alive", true):
				if has_profiles:
					count += _get_model_transport_slots(unit, model)
				else:
					count += 1
	return count


# --- Helper functions to create test units ---

func _make_meganobz_unit(count: int) -> Dictionary:
	var models = []
	for i in range(count):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": 3,
			"current_wounds": 3,
			"base_mm": 40,
			"position": null,
			"alive": true,
			"status_effects": [],
			"model_type": "meganob_klaw"
		})
	return {
		"id": "test_meganobz",
		"owner": 1,
		"status": "UNDEPLOYED",
		"meta": {
			"name": "Meganobz",
			"keywords": ["INFANTRY", "MEGA ARMOUR", "ORKS", "MEGANOBZ"],
			"stats": {"move": 5, "toughness": 6, "save": 2, "wounds": 3, "leadership": 7, "objective_control": 1},
			"model_profiles": {
				"meganob_klaw": {
					"label": "Meganob (Power Klaw)",
					"stats_override": {},
					"weapons": ["Kustom shoota", "Power klaw"],
					"transport_slots": 2
				},
				"meganob_saws": {
					"label": "Meganob (Killsaws)",
					"stats_override": {},
					"weapons": ["Kustom shoota", "Killsaws"],
					"transport_slots": 2
				}
			}
		},
		"models": models
	}

func _make_boyz_unit(count: int) -> Dictionary:
	var models = []
	for i in range(count):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": 1,
			"current_wounds": 1,
			"base_mm": 32,
			"position": null,
			"alive": true,
			"status_effects": [],
			"model_type": "boy"
		})
	return {
		"id": "test_boyz",
		"owner": 1,
		"status": "UNDEPLOYED",
		"meta": {
			"name": "Boyz",
			"keywords": ["INFANTRY", "ORKS", "BOYZ"],
			"stats": {"move": 6, "toughness": 5, "save": 5, "wounds": 1, "leadership": 7, "objective_control": 2},
			"model_profiles": {
				"boy": {
					"label": "Boy",
					"stats_override": {},
					"weapons": ["Slugga", "Choppa"],
					"transport_slots": 1
				}
			}
		},
		"models": models
	}

func _make_unit_no_profiles(count: int) -> Dictionary:
	var models = []
	for i in range(count):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": 1,
			"current_wounds": 1,
			"base_mm": 32,
			"position": null,
			"alive": true,
			"status_effects": []
		})
	return {
		"id": "test_no_profiles",
		"owner": 1,
		"status": "UNDEPLOYED",
		"meta": {
			"name": "Generic Unit",
			"keywords": ["INFANTRY"],
			"stats": {"move": 6, "toughness": 4, "save": 4, "wounds": 1}
		},
		"models": models
	}

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
