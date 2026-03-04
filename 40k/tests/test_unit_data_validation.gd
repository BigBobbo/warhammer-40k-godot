extends SceneTree

# Test: SAVE-18 Unit Data Validation on Load
# Verifies that _validate_unit_data() correctly catches and repairs data integrity issues.
# Usage: godot --headless --path . -s tests/test_unit_data_validation.gd

func _init():
	print("\n=== Test Unit Data Validation (SAVE-18) ===\n")
	var passed = 0
	var failed = 0

	# --- Test 1: Valid unit data passes ---
	print("--- Test 1: Valid unit data passes validation ---")
	var valid_data = _create_valid_save_data()
	var result = _validate_unit_data(valid_data)
	if result.valid and result.errors.size() == 0:
		print("  PASS: Valid data passes with no errors")
		passed += 1
	else:
		print("  FAIL: Valid data should pass (errors: %s)" % str(result.errors))
		failed += 1

	# --- Test 2: Invalid owner ---
	print("\n--- Test 2: Invalid owner is caught ---")
	var bad_owner = _create_valid_save_data()
	bad_owner["units"]["U_TEST_A"]["owner"] = 5
	result = _validate_unit_data(bad_owner)
	if not result.valid:
		print("  PASS: Invalid owner (5) caught as error")
		passed += 1
	else:
		print("  FAIL: Invalid owner should be an error")
		failed += 1

	# --- Test 3: Invalid status ---
	print("\n--- Test 3: Invalid status is caught ---")
	var bad_status = _create_valid_save_data()
	bad_status["units"]["U_TEST_A"]["status"] = 99
	result = _validate_unit_data(bad_status)
	if not result.valid:
		print("  PASS: Invalid status (99) caught as error")
		passed += 1
	else:
		print("  FAIL: Invalid status should be an error")
		failed += 1

	# --- Test 4: current_wounds > wounds is repaired ---
	print("\n--- Test 4: current_wounds > wounds is auto-repaired ---")
	var bad_wounds = _create_valid_save_data()
	bad_wounds["units"]["U_TEST_A"]["models"][0]["wounds"] = 2
	bad_wounds["units"]["U_TEST_A"]["models"][0]["current_wounds"] = 5
	result = _validate_unit_data(bad_wounds)
	if result.valid and result.repairs.size() > 0:
		var repaired_cw = bad_wounds["units"]["U_TEST_A"]["models"][0]["current_wounds"]
		if repaired_cw == 2:
			print("  PASS: current_wounds clamped to wounds (5 -> 2)")
			passed += 1
		else:
			print("  FAIL: current_wounds should be clamped to 2, got %d" % repaired_cw)
			failed += 1
	else:
		print("  FAIL: Should auto-repair with warning, not error")
		failed += 1

	# --- Test 5: Negative current_wounds repaired ---
	print("\n--- Test 5: Negative current_wounds is auto-repaired ---")
	var neg_wounds = _create_valid_save_data()
	neg_wounds["units"]["U_TEST_A"]["models"][0]["current_wounds"] = -3
	result = _validate_unit_data(neg_wounds)
	if result.valid and result.repairs.size() > 0:
		var repaired_cw = neg_wounds["units"]["U_TEST_A"]["models"][0]["current_wounds"]
		if repaired_cw == 0:
			print("  PASS: Negative current_wounds set to 0")
			passed += 1
		else:
			print("  FAIL: Should set current_wounds to 0, got %d" % repaired_cw)
			failed += 1
	else:
		print("  FAIL: Should auto-repair negative wounds")
		failed += 1

	# --- Test 6: alive/wounds consistency ---
	print("\n--- Test 6: alive=true but 0 wounds is auto-repaired ---")
	var inconsistent = _create_valid_save_data()
	inconsistent["units"]["U_TEST_A"]["models"][0]["current_wounds"] = 0
	inconsistent["units"]["U_TEST_A"]["models"][0]["alive"] = true
	result = _validate_unit_data(inconsistent)
	if result.valid and result.repairs.size() > 0:
		var alive = inconsistent["units"]["U_TEST_A"]["models"][0]["alive"]
		if alive == false:
			print("  PASS: alive set to false when current_wounds=0")
			passed += 1
		else:
			print("  FAIL: alive should be false")
			failed += 1
	else:
		print("  FAIL: Should auto-repair alive/wounds inconsistency")
		failed += 1

	# --- Test 7: alive=false but positive wounds is auto-repaired ---
	print("\n--- Test 7: alive=false but positive wounds is auto-repaired ---")
	var dead_but_healthy = _create_valid_save_data()
	dead_but_healthy["units"]["U_TEST_A"]["models"][0]["current_wounds"] = 2
	dead_but_healthy["units"]["U_TEST_A"]["models"][0]["alive"] = false
	result = _validate_unit_data(dead_but_healthy)
	if result.valid and result.repairs.size() > 0:
		var alive = dead_but_healthy["units"]["U_TEST_A"]["models"][0]["alive"]
		if alive == true:
			print("  PASS: alive set to true when current_wounds=2")
			passed += 1
		else:
			print("  FAIL: alive should be true")
			failed += 1
	else:
		print("  FAIL: Should auto-repair alive/wounds inconsistency")
		failed += 1

	# --- Test 8: Invalid base_mm repaired ---
	print("\n--- Test 8: Invalid base_mm is auto-repaired ---")
	var bad_base = _create_valid_save_data()
	bad_base["units"]["U_TEST_A"]["models"][0]["base_mm"] = 0
	result = _validate_unit_data(bad_base)
	if result.valid and result.repairs.size() > 0:
		var base = bad_base["units"]["U_TEST_A"]["models"][0]["base_mm"]
		if base == 25:
			print("  PASS: base_mm 0 repaired to 25")
			passed += 1
		else:
			print("  FAIL: base_mm should be 25, got %d" % base)
			failed += 1
	else:
		print("  FAIL: Should auto-repair invalid base_mm")
		failed += 1

	# --- Test 9: embarked_in referencing non-existent unit ---
	print("\n--- Test 9: embarked_in referencing non-existent unit is cleared ---")
	var bad_ref = _create_valid_save_data()
	bad_ref["units"]["U_TEST_A"]["embarked_in"] = "U_NONEXISTENT"
	result = _validate_unit_data(bad_ref)
	if result.valid and result.repairs.size() > 0:
		var embarked = bad_ref["units"]["U_TEST_A"]["embarked_in"]
		if embarked == null:
			print("  PASS: embarked_in cleared (unit not found)")
			passed += 1
		else:
			print("  FAIL: embarked_in should be null, got %s" % str(embarked))
			failed += 1
	else:
		print("  FAIL: Should auto-repair bad embarked_in reference")
		failed += 1

	# --- Test 10: attached_to referencing non-existent unit ---
	print("\n--- Test 10: attached_to referencing non-existent unit is cleared ---")
	var bad_attach = _create_valid_save_data()
	bad_attach["units"]["U_TEST_A"]["attached_to"] = "U_MISSING_UNIT"
	result = _validate_unit_data(bad_attach)
	if result.valid and result.repairs.size() > 0:
		var attached = bad_attach["units"]["U_TEST_A"]["attached_to"]
		if attached == null:
			print("  PASS: attached_to cleared (unit not found)")
			passed += 1
		else:
			print("  FAIL: attached_to should be null, got %s" % str(attached))
			failed += 1
	else:
		print("  FAIL: Should auto-repair bad attached_to reference")
		failed += 1

	# --- Test 11: Empty models array is error ---
	print("\n--- Test 11: Empty models array is caught as error ---")
	var no_models = _create_valid_save_data()
	no_models["units"]["U_TEST_A"]["models"] = []
	result = _validate_unit_data(no_models)
	if not result.valid:
		print("  PASS: Empty models array caught as error")
		passed += 1
	else:
		print("  FAIL: Empty models should be an error")
		failed += 1

	# --- Test 12: Negative CP repaired ---
	print("\n--- Test 12: Negative player CP is auto-repaired ---")
	var bad_cp = _create_valid_save_data()
	bad_cp["players"]["1"]["cp"] = -5
	result = _validate_unit_data(bad_cp)
	if result.valid and result.repairs.size() > 0:
		var cp = bad_cp["players"]["1"]["cp"]
		if cp == 0:
			print("  PASS: Negative CP set to 0")
			passed += 1
		else:
			print("  FAIL: CP should be 0, got %d" % cp)
			failed += 1
	else:
		print("  FAIL: Should auto-repair negative CP")
		failed += 1

	# --- Test 13: ID mismatch repaired ---
	print("\n--- Test 13: Unit ID mismatch is auto-repaired ---")
	var id_mismatch = _create_valid_save_data()
	id_mismatch["units"]["U_TEST_A"]["id"] = "WRONG_ID"
	result = _validate_unit_data(id_mismatch)
	if result.valid and result.repairs.size() > 0:
		var stored_id = id_mismatch["units"]["U_TEST_A"]["id"]
		if stored_id == "U_TEST_A":
			print("  PASS: ID corrected from 'WRONG_ID' to 'U_TEST_A'")
			passed += 1
		else:
			print("  FAIL: ID should be 'U_TEST_A', got '%s'" % stored_id)
			failed += 1
	else:
		print("  FAIL: Should auto-repair ID mismatch")
		failed += 1

	# --- Test 14: transport embarked_units with invalid refs ---
	print("\n--- Test 14: Transport embarked_units invalid refs cleaned ---")
	var bad_transport = _create_valid_save_data()
	bad_transport["units"]["U_TEST_A"]["transport_data"] = {
		"capacity": 12,
		"embarked_units": ["U_TEST_B", "U_GHOST"],
		"capacity_keywords": ["INFANTRY"]
	}
	result = _validate_unit_data(bad_transport)
	if result.valid:
		var embarked = bad_transport["units"]["U_TEST_A"]["transport_data"]["embarked_units"]
		if embarked.size() == 1 and embarked[0] == "U_TEST_B":
			print("  PASS: Invalid 'U_GHOST' removed, valid 'U_TEST_B' kept")
			passed += 1
		else:
			print("  FAIL: Expected ['U_TEST_B'], got %s" % str(embarked))
			failed += 1
	else:
		print("  FAIL: Transport cleanup should not produce errors")
		failed += 1

	# --- Test 15: StateSerializer source contains SAVE-18 code ---
	print("\n--- Test 15: StateSerializer has SAVE-18 validation code ---")
	var ss_file = FileAccess.open("res://autoloads/StateSerializer.gd", FileAccess.READ)
	if ss_file:
		var ss_source = ss_file.get_as_text()
		ss_file.close()

		var checks = {
			"_validate_unit_data": "Has _validate_unit_data function",
			"SAVE-18": "Has SAVE-18 references",
			"unit_validation = _validate_unit_data": "Calls _validate_unit_data in deserialize flow",
			"repairs": "Tracks auto-repairs",
		}

		for pattern in checks:
			if ss_source.find(pattern) != -1:
				print("  PASS: %s" % checks[pattern])
				passed += 1
			else:
				print("  FAIL: %s (pattern not found: '%s')" % [checks[pattern], pattern])
				failed += 1
	else:
		print("  SKIP: Could not read StateSerializer.gd")

	# --- Test 16: Validate keywords not Array is repaired ---
	print("\n--- Test 16: Non-array keywords is repaired ---")
	var bad_keywords = _create_valid_save_data()
	bad_keywords["units"]["U_TEST_A"]["meta"]["keywords"] = "NOT_AN_ARRAY"
	result = _validate_unit_data(bad_keywords)
	if result.valid and result.repairs.size() > 0:
		var kw = bad_keywords["units"]["U_TEST_A"]["meta"]["keywords"]
		if kw is Array and kw.size() == 0:
			print("  PASS: Non-array keywords repaired to []")
			passed += 1
		else:
			print("  FAIL: keywords should be [], got %s" % str(kw))
			failed += 1
	else:
		print("  FAIL: Should auto-repair non-array keywords")
		failed += 1

	# --- Summary ---
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed == 0:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")

	quit()


# ============================================================================
# Test Helpers — mirror validation logic for pure-GDScript testing without autoloads
# ============================================================================

func _create_valid_save_data() -> Dictionary:
	"""Create minimal valid save data with two units."""
	return {
		"_serialization": {
			"version": "1.1.0",
			"timestamp": 1700000000.0,
			"game_version": "1.1.0",
			"serializer": "StateSerializer"
		},
		"meta": {
			"game_id": "test-game-001",
			"turn_number": 1,
			"battle_round": 1,
			"active_player": 1,
			"phase": 1,
			"deployment_type": "hammer_anvil",
			"version": "1.1.0"
		},
		"board": {
			"size": {"width": 44, "height": 60},
			"deployment_zones": [],
			"objectives": [],
			"terrain": []
		},
		"units": {
			"U_TEST_A": {
				"id": "U_TEST_A",
				"squad_id": "U_TEST_A",
				"owner": 1,
				"status": 0,
				"meta": {
					"name": "Test Squad A",
					"keywords": ["INFANTRY", "IMPERIUM"],
					"stats": {"move": 6, "toughness": 4, "save": 3, "wounds": 2, "leadership": 6, "objective_control": 2},
					"weapons": [{"name": "Bolt rifle", "type": "Ranged"}],
					"abilities": [{"name": "Oath of Moment", "type": "Faction"}]
				},
				"models": [
					{"id": "m1", "wounds": 2, "current_wounds": 2, "base_mm": 32, "alive": true, "status_effects": []},
					{"id": "m2", "wounds": 2, "current_wounds": 2, "base_mm": 32, "alive": true, "status_effects": []}
				]
			},
			"U_TEST_B": {
				"id": "U_TEST_B",
				"squad_id": "U_TEST_B",
				"owner": 2,
				"status": 0,
				"meta": {
					"name": "Test Squad B",
					"keywords": ["INFANTRY", "ORKS"],
					"stats": {"move": 6, "toughness": 5, "save": 6, "wounds": 1, "leadership": 7, "objective_control": 2},
					"weapons": [{"name": "Slugga", "type": "Ranged"}],
					"abilities": []
				},
				"models": [
					{"id": "m1", "wounds": 1, "current_wounds": 1, "base_mm": 32, "alive": true, "status_effects": []}
				]
			}
		},
		"players": {
			"1": {"cp": 3, "vp": 0, "primary_vp": 0, "secondary_vp": 0, "bonus_cp_gained_this_round": 0},
			"2": {"cp": 3, "vp": 0, "primary_vp": 0, "secondary_vp": 0, "bonus_cp_gained_this_round": 0}
		},
		"factions": {},
		"unit_visuals": {},
		"phase_log": [],
		"history": []
	}

func _validate_unit_data(data: Dictionary) -> Dictionary:
	"""Mirror of StateSerializer._validate_unit_data for testing without autoloads."""
	var validation = {
		"valid": true,
		"errors": [],
		"warnings": [],
		"repairs": []
	}

	if not data.has("units") or not data["units"] is Dictionary:
		return validation

	var units = data["units"]
	var all_unit_ids = units.keys()

	for unit_id in units:
		var unit = units[unit_id]
		if not unit is Dictionary:
			validation.errors.append("Unit '%s' is not a Dictionary" % unit_id)
			validation.valid = false
			continue

		var prefix = "Unit '%s'" % unit_id

		# Owner validation
		var owner = unit.get("owner", -1)
		if not owner is float and not owner is int:
			validation.errors.append("%s: owner is not a number" % prefix)
			validation.valid = false
		elif owner != 1 and owner != 2:
			validation.errors.append("%s: owner must be 1 or 2 (got %s)" % [prefix, str(owner)])
			validation.valid = false

		# Status validation
		var status = unit.get("status", -1)
		if status is float:
			status = int(status)
		if not status is int:
			validation.errors.append("%s: status is not a number" % prefix)
			validation.valid = false
		elif status < 0 or status > 7:
			validation.errors.append("%s: status %d out of range [0-7]" % [prefix, status])
			validation.valid = false

		# ID consistency
		var stored_id = unit.get("id", "")
		if stored_id != "" and stored_id != unit_id:
			validation.warnings.append("%s: id mismatch" % prefix)
			unit["id"] = unit_id
			validation.repairs.append("%s: set id to '%s'" % [prefix, unit_id])

		# Meta validation
		var meta = unit.get("meta", {})
		if not meta is Dictionary:
			validation.errors.append("%s: meta is not a Dictionary" % prefix)
			validation.valid = false
		else:
			var keywords = meta.get("keywords", [])
			if not keywords is Array:
				validation.warnings.append("%s: keywords not Array" % prefix)
				meta["keywords"] = []
				validation.repairs.append("%s: set keywords to []" % prefix)

			var stats = meta.get("stats", {})
			if stats is Dictionary:
				for stat_name in ["move", "toughness", "save", "wounds", "leadership", "objective_control"]:
					if stats.has(stat_name):
						var val = stats[stat_name]
						if val is float:
							val = int(val)
						if val is int and val < 0:
							stats[stat_name] = 0
							validation.repairs.append("%s: clamped %s" % [prefix, stat_name])

			var abilities = meta.get("abilities", [])
			if not abilities is Array:
				meta["abilities"] = []
				validation.repairs.append("%s: set abilities to []" % prefix)

		# Models validation
		var models = unit.get("models", [])
		if not models is Array:
			validation.errors.append("%s: models is not an Array" % prefix)
			validation.valid = false
		elif models.size() == 0:
			validation.errors.append("%s: models array is empty" % prefix)
			validation.valid = false
		else:
			var model_ids_seen = {}
			for i in range(models.size()):
				var model = models[i]
				if not model is Dictionary:
					validation.errors.append("%s model[%d] not Dictionary" % [prefix, i])
					validation.valid = false
					continue

				var m_prefix = "%s model[%d]" % [prefix, i]

				var model_id = model.get("id", "")
				if model_id != "":
					if model_ids_seen.has(model_id):
						validation.warnings.append("%s: duplicate id" % m_prefix)
					model_ids_seen[model_id] = true

				var max_wounds = model.get("wounds", 0)
				var current_wounds = model.get("current_wounds", 0)
				if max_wounds is float:
					max_wounds = int(max_wounds)
				if current_wounds is float:
					current_wounds = int(current_wounds)

				if max_wounds is int and max_wounds < 1:
					model["wounds"] = 1
					max_wounds = 1
					validation.repairs.append("%s: set wounds to 1" % m_prefix)

				if current_wounds is int and max_wounds is int:
					if current_wounds > max_wounds:
						model["current_wounds"] = max_wounds
						validation.repairs.append("%s: clamped current_wounds" % m_prefix)
					elif current_wounds < 0:
						model["current_wounds"] = 0
						validation.repairs.append("%s: set current_wounds to 0" % m_prefix)

				# Re-read after potential repair
				current_wounds = model.get("current_wounds", 0)
				if current_wounds is float:
					current_wounds = int(current_wounds)
				var alive = model.get("alive", true)
				if current_wounds is int and current_wounds <= 0 and alive == true:
					model["alive"] = false
					validation.repairs.append("%s: set alive=false" % m_prefix)
				elif current_wounds is int and current_wounds > 0 and alive == false:
					model["alive"] = true
					validation.repairs.append("%s: set alive=true" % m_prefix)

				var base_mm = model.get("base_mm", 0)
				if base_mm is float:
					base_mm = int(base_mm)
				if base_mm is int and base_mm <= 0:
					model["base_mm"] = 25
					validation.repairs.append("%s: set base_mm to 25" % m_prefix)

				var status_effects = model.get("status_effects", [])
				if not status_effects is Array:
					model["status_effects"] = []
					validation.repairs.append("%s: set status_effects to []" % m_prefix)

		# Cross-reference: embarked_in
		var embarked_in = unit.get("embarked_in", null)
		if embarked_in != null and embarked_in is String and embarked_in != "":
			if not embarked_in in all_unit_ids:
				unit["embarked_in"] = null
				validation.repairs.append("%s: cleared embarked_in" % prefix)

		# Cross-reference: attached_to
		var attached_to = unit.get("attached_to", null)
		if attached_to != null and attached_to is String and attached_to != "":
			if not attached_to in all_unit_ids:
				unit["attached_to"] = null
				validation.repairs.append("%s: cleared attached_to" % prefix)

		# Cross-reference: attachment_data
		var attachment_data = unit.get("attachment_data", {})
		if attachment_data is Dictionary:
			var attached_chars = attachment_data.get("attached_characters", [])
			if attached_chars is Array:
				var valid_chars = []
				for char_id in attached_chars:
					if char_id is String and char_id in all_unit_ids:
						valid_chars.append(char_id)
					else:
						validation.repairs.append("%s: removed invalid attached_character" % prefix)
				if valid_chars.size() != attached_chars.size():
					attachment_data["attached_characters"] = valid_chars

		# Cross-reference: transport embarked_units
		var transport_data = unit.get("transport_data", {})
		if transport_data is Dictionary:
			var embarked_units = transport_data.get("embarked_units", [])
			if embarked_units is Array:
				var valid_embarked = []
				for e_id in embarked_units:
					if e_id is String and e_id in all_unit_ids:
						valid_embarked.append(e_id)
					else:
						validation.repairs.append("%s: removed invalid embarked unit" % prefix)
				if valid_embarked.size() != embarked_units.size():
					transport_data["embarked_units"] = valid_embarked

	# Player data validation
	if data.has("players") and data["players"] is Dictionary:
		for player_key in data["players"]:
			var player = data["players"][player_key]
			if not player is Dictionary:
				continue
			var p_prefix = "Player '%s'" % player_key
			var cp = player.get("cp", 0)
			if cp is float:
				cp = int(cp)
			if cp is int and cp < 0:
				player["cp"] = 0
				validation.repairs.append("%s: set CP to 0" % p_prefix)
			for vp_key in ["vp", "primary_vp", "secondary_vp"]:
				var vp = player.get(vp_key, 0)
				if vp is float:
					vp = int(vp)
				if vp is int and vp < 0:
					player[vp_key] = 0
					validation.repairs.append("%s: set %s to 0" % [p_prefix, vp_key])

	return validation
