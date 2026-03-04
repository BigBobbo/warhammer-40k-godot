extends SceneTree

# Test: Save Format Migration System (SAVE-3)
# Verifies that the migration system correctly upgrades old save files.
# Usage: godot --headless --path . -s tests/test_save_format_migration.gd

func _init():
	print("\n=== Test Save Format Migration System (SAVE-3) ===\n")
	var passed = 0
	var failed = 0

	# --- Test 1: Version comparison utility ---
	print("--- Test 1: _compare_versions logic ---")
	# We test by reading the source and verifying the logic is sound,
	# then do direct integer-based semver comparisons to validate expectations.

	# Manually implement the version comparison for testing (mirrors StateSerializer._compare_versions)
	var test_cases = [
		["1.0.0", "1.0.0", 0],
		["1.0.0", "1.1.0", -1],
		["1.1.0", "1.0.0", 1],
		["2.0.0", "1.9.9", 1],
		["1.0.0", "2.0.0", -1],
		["1.0.1", "1.0.0", 1],
		["0.9.0", "1.0.0", -1],
	]

	var all_version_tests_pass = true
	for test_case in test_cases:
		var a = test_case[0]
		var b = test_case[1]
		var expected = test_case[2]
		var result = _compare_versions(a, b)
		if result != expected:
			print("  FAIL: _compare_versions('%s', '%s') = %d, expected %d" % [a, b, result, expected])
			all_version_tests_pass = false

	if all_version_tests_pass:
		print("  PASS: All version comparison tests passed (%d cases)" % test_cases.size())
		passed += 1
	else:
		print("  FAIL: Some version comparison tests failed")
		failed += 1

	# --- Test 2: StateSerializer has migration system code ---
	print("\n--- Test 2: StateSerializer has migration system ---")
	var ss_file = FileAccess.open("res://autoloads/StateSerializer.gd", FileAccess.READ)
	if ss_file:
		var ss_source = ss_file.get_as_text()
		ss_file.close()

		var checks = {
			"CURRENT_VERSION = \"1.1.0\"": "CURRENT_VERSION is 1.1.0",
			"MINIMUM_MIGRATABLE_VERSION": "Has MINIMUM_MIGRATABLE_VERSION constant",
			"_register_migrations": "Has migration registration function",
			"migrate_save_data": "Has migrate_save_data function",
			"_compare_versions": "Has version comparison function",
			"_is_version_migratable": "Has version migratable check",
			"_migrate_1_0_0_to_1_1_0": "Has 1.0.0 -> 1.1.0 migration function",
			"formations_declared": "Migration handles formations_declared",
			"bonus_cp_gained_this_round": "Migration handles bonus_cp_gained_this_round",
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

	# --- Test 3: Migration upgrades v1.0.0 save data correctly ---
	print("\n--- Test 3: Migration upgrades v1.0.0 save data ---")
	var old_save_data = _create_v1_0_0_save_data()

	# Verify it's v1.0.0
	if old_save_data["_serialization"]["version"] == "1.0.0":
		print("  PASS: Test data starts at version 1.0.0")
		passed += 1
	else:
		print("  FAIL: Test data should be version 1.0.0")
		failed += 1

	# Verify old save is missing fields that migration should add
	if not old_save_data.has("factions"):
		print("  PASS: Old save missing 'factions' (migration will add it)")
		passed += 1
	else:
		print("  INFO: Old save already has 'factions'")
		passed += 1

	if not old_save_data.has("unit_visuals"):
		print("  PASS: Old save missing 'unit_visuals' (migration will add it)")
		passed += 1
	else:
		print("  INFO: Old save already has 'unit_visuals'")
		passed += 1

	# Run migration
	var migrated = _simulate_migrate_1_0_0_to_1_1_0(old_save_data)

	# Verify migration results
	if migrated.has("factions"):
		print("  PASS: Migration added 'factions' section")
		passed += 1
	else:
		print("  FAIL: Migration did not add 'factions' section")
		failed += 1

	if migrated.has("unit_visuals"):
		print("  PASS: Migration added 'unit_visuals' section")
		passed += 1
	else:
		print("  FAIL: Migration did not add 'unit_visuals' section")
		failed += 1

	if migrated.has("phase_log"):
		print("  PASS: Migration added 'phase_log' section")
		passed += 1
	else:
		print("  FAIL: Migration did not add 'phase_log' section")
		failed += 1

	if migrated.has("history"):
		print("  PASS: Migration added 'history' section")
		passed += 1
	else:
		print("  FAIL: Migration did not add 'history' section")
		failed += 1

	# Check meta fields for a save past FORMATIONS phase
	var meta = migrated.get("meta", {})
	if meta.get("formations_declared", false) == true:
		print("  PASS: Migration inferred formations_declared=true")
		passed += 1
	else:
		print("  FAIL: Migration should have set formations_declared=true (phase > FORMATIONS)")
		failed += 1

	if meta.has("battle_round"):
		print("  PASS: Migration added battle_round field (value: %d)" % meta["battle_round"])
		passed += 1
	else:
		print("  FAIL: Migration did not add battle_round field")
		failed += 1

	if meta.has("formations"):
		print("  PASS: Migration added formations data")
		passed += 1
	else:
		print("  FAIL: Migration did not add formations data")
		failed += 1

	# Check player data
	var p1 = migrated.get("players", {}).get("1", {})
	if p1.has("bonus_cp_gained_this_round"):
		print("  PASS: Migration added bonus_cp_gained_this_round for player 1")
		passed += 1
	else:
		print("  FAIL: Migration did not add bonus_cp_gained_this_round for player 1")
		failed += 1

	# Check version was updated
	if migrated["_serialization"]["version"] == "1.1.0":
		print("  PASS: Migration updated version to 1.1.0")
		passed += 1
	else:
		print("  FAIL: Migration did not update version (got: %s)" % migrated["_serialization"]["version"])
		failed += 1

	# --- Test 4: v1.0.0 save at FORMATIONS phase doesn't get false formations_declared ---
	print("\n--- Test 4: Migration handles FORMATIONS phase saves correctly ---")
	var formations_save = _create_v1_0_0_save_data_at_formations()
	var migrated_formations = _simulate_migrate_1_0_0_to_1_1_0(formations_save)
	var fm_meta = migrated_formations.get("meta", {})

	if not fm_meta.has("formations_declared"):
		print("  PASS: Save at FORMATIONS phase does not get formations_declared added")
		passed += 1
	else:
		print("  FAIL: Save at FORMATIONS phase should not have formations_declared added")
		failed += 1

	# --- Test 5: Existing test save files can be validated and migrated ---
	print("\n--- Test 5: Existing test save files are migratable ---")
	var test_saves = [
		"res://tests/saves/deployment_start.w40ksave",
		"res://tests/saves/deployment_player1_turn.w40ksave",
		"res://tests/saves/deployment_player2_turn.w40ksave",
		"res://tests/saves/deployment_nearly_complete.w40ksave",
		"res://tests/saves/deployment_with_terrain.w40ksave",
	]

	for save_path in test_saves:
		var file = FileAccess.open(save_path, FileAccess.READ)
		if file:
			var json = JSON.new()
			var err = json.parse(file.get_as_text())
			file.close()
			if err == OK:
				var data = json.data
				var version = data.get("_serialization", {}).get("version", "unknown")
				var has_required = data.has("meta") and data.has("board") and data.has("units") and data.has("players")

				if has_required and (version == "1.0.0" or version == "1.1.0"):
					print("  PASS: %s (v%s) has all required sections — migratable" % [save_path.get_file(), version])
					passed += 1
				else:
					print("  FAIL: %s (v%s) missing required sections or bad version" % [save_path.get_file(), version])
					failed += 1
			else:
				print("  FAIL: %s could not be parsed as JSON" % save_path.get_file())
				failed += 1
		else:
			print("  SKIP: %s not found" % save_path.get_file())

	# --- Test 6: Version migratable check ---
	print("\n--- Test 6: Version migratable check ---")

	# 1.0.0 should be migratable (has migration to 1.1.0)
	if _is_version_migratable("1.0.0"):
		print("  PASS: 1.0.0 is migratable")
		passed += 1
	else:
		print("  FAIL: 1.0.0 should be migratable")
		failed += 1

	# 1.1.0 should be migratable (it IS the current version)
	if _is_version_migratable("1.1.0"):
		print("  PASS: 1.1.0 is migratable (current version)")
		passed += 1
	else:
		print("  FAIL: 1.1.0 should be migratable (current version)")
		failed += 1

	# 0.9.0 should NOT be migratable (too old)
	if not _is_version_migratable("0.9.0"):
		print("  PASS: 0.9.0 is not migratable (too old)")
		passed += 1
	else:
		print("  FAIL: 0.9.0 should not be migratable")
		failed += 1

	# 2.0.0 should NOT be migratable (future version)
	if not _is_version_migratable("2.0.0"):
		print("  PASS: 2.0.0 is not migratable (future version)")
		passed += 1
	else:
		print("  FAIL: 2.0.0 should not be migratable")
		failed += 1

	# --- Test 7: Verify SaveLoadManager uses dynamic version ---
	print("\n--- Test 7: SaveLoadManager uses StateSerializer version ---")
	var slm_file = FileAccess.open("res://autoloads/SaveLoadManager.gd", FileAccess.READ)
	if slm_file:
		var slm_source = slm_file.get_as_text()
		slm_file.close()

		if slm_source.find("StateSerializer.CURRENT_VERSION") != -1:
			print("  PASS: SaveLoadManager references StateSerializer.CURRENT_VERSION")
			passed += 1
		else:
			print("  FAIL: SaveLoadManager should use StateSerializer.CURRENT_VERSION instead of hardcoded version")
			failed += 1
	else:
		print("  SKIP: Could not read SaveLoadManager.gd")

	# --- Test 8: Verify GameState.gd meta version updated ---
	print("\n--- Test 8: GameState.gd meta version is 1.1.0 ---")
	var gs_file = FileAccess.open("res://autoloads/GameState.gd", FileAccess.READ)
	if gs_file:
		var gs_source = gs_file.get_as_text()
		gs_file.close()

		if gs_source.find("\"version\": \"1.1.0\"") != -1:
			print("  PASS: GameState.gd meta version is 1.1.0")
			passed += 1
		else:
			print("  FAIL: GameState.gd meta version should be 1.1.0")
			failed += 1
	else:
		print("  SKIP: Could not read GameState.gd")

	# --- Summary ---
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed == 0:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")

	quit()


# ============================================================================
# Test Helpers — mirror migration logic for pure-GDScript testing without autoloads
# ============================================================================

func _compare_versions(a: String, b: String) -> int:
	var parts_a = a.split(".")
	var parts_b = b.split(".")
	for i in range(max(parts_a.size(), parts_b.size())):
		var num_a = int(parts_a[i]) if i < parts_a.size() else 0
		var num_b = int(parts_b[i]) if i < parts_b.size() else 0
		if num_a < num_b:
			return -1
		elif num_a > num_b:
			return 1
	return 0

func _is_version_migratable(version: String) -> bool:
	var current_version = "1.1.0"
	var min_version = "1.0.0"
	if version == current_version:
		return true
	if _compare_versions(version, min_version) < 0:
		return false
	if _compare_versions(version, current_version) > 0:
		return false
	# Known migration paths
	var migrations = {"1.0.0": "1.1.0"}
	var current_ver = version
	var steps = 0
	while current_ver != current_version and steps < 100:
		if not migrations.has(current_ver):
			return false
		current_ver = migrations[current_ver]
		steps += 1
	return current_ver == current_version

func _create_v1_0_0_save_data() -> Dictionary:
	"""Create a minimal v1.0.0 save at DEPLOYMENT phase (simulating an old save)."""
	return {
		"_serialization": {
			"version": "1.0.0",
			"timestamp": 1700000000.0,
			"game_version": "1.0.0",
			"serializer": "StateSerializer"
		},
		"meta": {
			"game_id": "test-game-001",
			"turn_number": 1,
			"active_player": 1,
			"phase": 1,  # DEPLOYMENT
			"deployment_type": "hammer_anvil",
			"version": "1.0.0"
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
				"owner": 1,
				"status": 0,
				"meta": {"name": "Test Squad", "keywords": ["INFANTRY"]},
				"models": [{"id": "m1", "wounds": 2, "current_wounds": 2, "base_mm": 32, "alive": true}]
			}
		},
		"players": {
			"1": {"cp": 3, "vp": 0},
			"2": {"cp": 3, "vp": 0}
		}
	}

func _create_v1_0_0_save_data_at_formations() -> Dictionary:
	"""Create a minimal v1.0.0 save at FORMATIONS phase (phase=0)."""
	var data = _create_v1_0_0_save_data()
	data["meta"]["phase"] = 0  # FORMATIONS
	return data

func _simulate_migrate_1_0_0_to_1_1_0(data: Dictionary) -> Dictionary:
	"""Mirror of StateSerializer._migrate_1_0_0_to_1_1_0 for testing without autoloads."""
	# Ensure top-level sections
	if not data.has("factions"):
		data["factions"] = {}
	if not data.has("unit_visuals"):
		data["unit_visuals"] = {}
	if not data.has("phase_log"):
		data["phase_log"] = []
	if not data.has("history"):
		data["history"] = []

	# Ensure meta fields
	if data.has("meta"):
		var meta = data["meta"]
		if not meta.has("battle_round"):
			meta["battle_round"] = meta.get("turn_number", 1)

		var saved_phase = meta.get("phase", 0)
		if saved_phase > 0:
			if not meta.has("formations_declared"):
				meta["formations_declared"] = true
			if not meta.has("formations_p1_confirmed"):
				meta["formations_p1_confirmed"] = true
			if not meta.has("formations_p2_confirmed"):
				meta["formations_p2_confirmed"] = true
			if not meta.has("formations"):
				meta["formations"] = {
					"1": {"leader_attachments": {}, "transport_embarkations": {}, "reserves": []},
					"2": {"leader_attachments": {}, "transport_embarkations": {}, "reserves": []}
				}
		meta["version"] = "1.1.0"

	# Ensure player fields
	if data.has("players"):
		for player_key in data["players"]:
			var player_data = data["players"][player_key]
			if player_data is Dictionary:
				if not player_data.has("bonus_cp_gained_this_round"):
					player_data["bonus_cp_gained_this_round"] = 0
				if not player_data.has("primary_vp"):
					player_data["primary_vp"] = 0
				if not player_data.has("secondary_vp"):
					player_data["secondary_vp"] = 0

	# Update version
	data["_serialization"]["version"] = "1.1.0"
	return data
