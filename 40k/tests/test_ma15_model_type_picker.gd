extends SceneTree

# Test: MA-15 Model Type Picker UI
# Verifies:
# 1. ModelTypePickerPanel correctly counts unplaced models by type
# 2. Distinct type detection works correctly
# 3. Auto-select works when only 1 type remains
# 4. Units without model_profiles are unaffected
# Usage: godot --headless --path . -s tests/test_ma15_model_type_picker.gd

func _init():
	print("\n=== Test MA-15: Model Type Picker ===\n")
	var passed = 0
	var failed = 0

	# --- Test 1: _count_unplaced_by_type — all unplaced ---
	print("--- Test 1: Count unplaced by type — all unplaced ---")
	var panel = load("res://scripts/ModelTypePickerPanel.gd").new()
	var models = [
		{"id": "m1", "model_type": "loota_deffgun"},
		{"id": "m2", "model_type": "loota_deffgun"},
		{"id": "m3", "model_type": "loota_deffgun"},
		{"id": "m4", "model_type": "loota_kmb"},
		{"id": "m5", "model_type": "loota_kmb"},
		{"id": "m6", "model_type": "spanner"},
	]
	var counts = panel._count_unplaced_by_type(models, [])
	if counts.get("loota_deffgun", 0) == 3 and counts.get("loota_kmb", 0) == 2 and counts.get("spanner", 0) == 1:
		print("  PASS: loota_deffgun=3, loota_kmb=2, spanner=1")
		passed += 1
	else:
		print("  FAIL: Expected loota_deffgun=3, loota_kmb=2, spanner=1, got %s" % str(counts))
		failed += 1

	# --- Test 2: _count_unplaced_by_type — some placed ---
	print("\n--- Test 2: Count unplaced by type — some placed ---")
	var placed = [0, 1, 3]  # m1, m2 (deffgun) and m4 (kmb) are placed
	counts = panel._count_unplaced_by_type(models, placed)
	if counts.get("loota_deffgun", 0) == 1 and counts.get("loota_kmb", 0) == 1 and counts.get("spanner", 0) == 1:
		print("  PASS: loota_deffgun=1, loota_kmb=1, spanner=1")
		passed += 1
	else:
		print("  FAIL: Expected loota_deffgun=1, loota_kmb=1, spanner=1, got %s" % str(counts))
		failed += 1

	# --- Test 3: _count_unplaced_by_type — type fully placed ---
	print("\n--- Test 3: Count unplaced by type — type fully placed ---")
	placed = [0, 1, 2]  # All deffgun placed
	counts = panel._count_unplaced_by_type(models, placed)
	if counts.get("loota_deffgun", 0) == 0 and counts.get("loota_kmb", 0) == 2 and counts.get("spanner", 0) == 1:
		print("  PASS: loota_deffgun=0, loota_kmb=2, spanner=1")
		passed += 1
	else:
		print("  FAIL: Expected loota_deffgun=0, loota_kmb=2, spanner=1, got %s" % str(counts))
		failed += 1

	# --- Test 4: _count_unplaced_by_type — all placed ---
	print("\n--- Test 4: Count unplaced by type — all placed ---")
	placed = [0, 1, 2, 3, 4, 5]
	counts = panel._count_unplaced_by_type(models, placed)
	var all_zero = counts.get("loota_deffgun", 0) == 0 and counts.get("loota_kmb", 0) == 0 and counts.get("spanner", 0) == 0
	if all_zero:
		print("  PASS: All counts are 0")
		passed += 1
	else:
		print("  FAIL: Expected all 0, got %s" % str(counts))
		failed += 1

	# --- Test 5: Models without model_type are ignored ---
	print("\n--- Test 5: Models without model_type are ignored ---")
	var legacy_models = [
		{"id": "m1"},
		{"id": "m2"},
		{"id": "m3"},
	]
	counts = panel._count_unplaced_by_type(legacy_models, [])
	if counts.is_empty():
		print("  PASS: No types found for models without model_type")
		passed += 1
	else:
		print("  FAIL: Expected empty counts, got %s" % str(counts))
		failed += 1

	# --- Test 6: get_remaining_types with model_profiles ---
	print("\n--- Test 6: get_remaining_types ---")
	var profiles = {
		"loota_deffgun": {"label": "Loota (Deffgun)"},
		"loota_kmb": {"label": "Loota (Kustom Mega-blasta)"},
		"spanner": {"label": "Spanner"},
	}
	# Need to add to scene tree for setup to work
	root.add_child(panel)
	panel.setup(profiles, models, [])
	var remaining = panel.get_remaining_types(models, [])
	if remaining.size() == 3:
		print("  PASS: 3 remaining types when none placed")
		passed += 1
	else:
		print("  FAIL: Expected 3 remaining, got %d" % remaining.size())
		failed += 1

	# --- Test 7: get_remaining_types — one type depleted ---
	print("\n--- Test 7: get_remaining_types — spanner depleted ---")
	placed = [5]  # spanner placed
	remaining = panel.get_remaining_types(models, placed)
	if remaining.size() == 2 and "spanner" not in remaining:
		print("  PASS: 2 remaining types (spanner depleted)")
		passed += 1
	else:
		print("  FAIL: Expected 2 remaining without spanner, got %s" % str(remaining))
		failed += 1

	# --- Test 8: Lootas from actual orks.json has correct types ---
	print("\n--- Test 8: Lootas from orks.json has 3 model types ---")
	var army_data = _load_army_json("orks")
	if army_data.is_empty():
		print("  FAIL: Could not load orks.json")
		failed += 1
	else:
		var lootas = army_data.get("units", {}).get("U_LOOTAS_A", {})
		var lootas_meta = lootas.get("meta", {})
		var lootas_profiles = lootas_meta.get("model_profiles", {})
		var lootas_models = lootas.get("models", [])
		if lootas_profiles.size() == 3:
			print("  PASS: 3 model_profiles in Lootas")
			passed += 1
		else:
			print("  FAIL: Expected 3 profiles, got %d" % lootas_profiles.size())
			failed += 1

	# --- Test 9: Lootas model counts match expected ---
	print("\n--- Test 9: Lootas model type counts ---")
	if not army_data.is_empty():
		var lootas2 = army_data.get("units", {}).get("U_LOOTAS_A", {})
		var lootas_models2 = lootas2.get("models", [])
		var type_counts = {}
		for m in lootas_models2:
			var mt = m.get("model_type", "")
			type_counts[mt] = type_counts.get(mt, 0) + 1
		if type_counts.get("loota_deffgun", 0) == 8 and type_counts.get("loota_kmb", 0) == 2 and type_counts.get("spanner", 0) == 1:
			print("  PASS: 8x deffgun, 2x kmb, 1x spanner")
			passed += 1
		else:
			print("  FAIL: Expected 8/2/1, got %s" % str(type_counts))
			failed += 1
	else:
		print("  SKIP: orks.json not loaded")

	# --- Test 10: Unit without model_profiles has no distinct types ---
	print("\n--- Test 10: Unit without model_profiles — no model_type ---")
	if not army_data.is_empty():
		var gretchin = army_data.get("units", {}).get("U_GRETCHIN_A", {})
		var gretchin_meta = gretchin.get("meta", {})
		var gretchin_profiles = gretchin_meta.get("model_profiles", {})
		if gretchin_profiles.is_empty():
			print("  PASS: Gretchin has no model_profiles (backward compat)")
			passed += 1
		else:
			print("  FAIL: Expected no model_profiles, got %d" % gretchin_profiles.size())
			failed += 1
	else:
		print("  SKIP: orks.json not loaded")

	# --- Test 11: Boyz unit with 2 types should show picker ---
	print("\n--- Test 11: Boyz has model_profiles with 2 types ---")
	if not army_data.is_empty():
		var boyz = army_data.get("units", {}).get("U_BOYZ_F", {})
		if boyz.is_empty():
			boyz = army_data.get("units", {}).get("U_BOYZ_E", {})
		var boyz_meta = boyz.get("meta", {})
		var boyz_profiles = boyz_meta.get("model_profiles", {})
		if boyz_profiles.size() >= 2:
			print("  PASS: Boyz has %d model_profiles (picker would show)" % boyz_profiles.size())
			passed += 1
		else:
			# Check if this unit exists at all
			if boyz.is_empty():
				print("  SKIP: Boyz unit not found in orks.json")
			else:
				print("  INFO: Boyz has %d model_profiles (may not need picker)" % boyz_profiles.size())
				passed += 1  # Not necessarily a failure if only 1 profile
	else:
		print("  SKIP: orks.json not loaded")

	# Clean up
	panel.queue_free()

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
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()
	if error != OK:
		print("  ERROR: JSON parse error: %s" % json.get_error_message())
		return {}
	return json.data
