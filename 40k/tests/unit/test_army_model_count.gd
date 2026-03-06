extends SceneTree

# MA-37: Test that army JSON parsing creates correct model counts for multi-model squads
# Run: godot --headless --script tests/unit/test_army_model_count.gd

var pass_count: int = 0
var fail_count: int = 0

func _assert(condition: bool, test_name: String) -> void:
	if condition:
		print("PASS: %s" % test_name)
		pass_count += 1
	else:
		print("FAIL: %s" % test_name)
		fail_count += 1

func _init():
	print("=== MA-37: Army Model Count Test ===")
	call_deferred("_run_tests")

func _run_tests():
	await root.get_tree().process_frame
	await root.get_tree().process_frame

	var army_list_manager = root.get_node_or_null("/root/ArmyListManager")
	_assert(army_list_manager != null, "ArmyListManager autoload exists")
	if army_list_manager == null:
		print("\n=== Results: %d passed, %d failed ===" % [pass_count, fail_count])
		print("ABORTED: ArmyListManager not found")
		quit()
		return

	# --- Test: Load Orks_2000 army and verify model counts ---
	print("\n--- Test: Orks_2000 army model counts ---")
	var army_data = army_list_manager.load_army_list("Orks_2000", 1)
	_assert(not army_data.is_empty(), "Orks_2000 army loaded successfully")

	if army_data.is_empty():
		print("\n=== Results: %d passed, %d failed ===" % [pass_count, fail_count])
		print("ABORTED: Could not load Orks_2000")
		quit()
		return

	# Burna Boyz should have 5 models (1 Spanner + 4 Burna Boyz)
	var burna_a = army_data.units.get("U_BURNA_BOYZ_A", {})
	_assert(burna_a.has("models"), "U_BURNA_BOYZ_A has models array")
	_assert(burna_a.get("models", []).size() == 5, "U_BURNA_BOYZ_A has 5 models (got %d)" % burna_a.get("models", []).size())

	var burna_b = army_data.units.get("U_BURNA_BOYZ_B", {})
	_assert(burna_b.get("models", []).size() == 5, "U_BURNA_BOYZ_B has 5 models (got %d)" % burna_b.get("models", []).size())

	# Lootas should have 10 models (2 Spanners + 8 Lootas)
	var lootas_a = army_data.units.get("U_LOOTAS_A", {})
	_assert(lootas_a.get("models", []).size() == 10, "U_LOOTAS_A has 10 models (got %d)" % lootas_a.get("models", []).size())

	# Beast Snagga Boyz should have 10 models (already correct)
	var bsb = army_data.units.get("U_BEAST_SNAGGA_BOYZ_A", {})
	_assert(bsb.get("models", []).size() == 10, "U_BEAST_SNAGGA_BOYZ_A has 10 models (got %d)" % bsb.get("models", []).size())

	# Single-model units should still have 1 model
	var beastboss = army_data.units.get("U_BEASTBOSS_A", {})
	_assert(beastboss.get("models", []).size() == 1, "U_BEASTBOSS_A has 1 model (got %d)" % beastboss.get("models", []).size())

	# Gretchin should have 22 models (2 Runtherds + 20 Gretchin)
	var gretchin = army_data.units.get("U_GRETCHIN_A", {})
	_assert(gretchin.get("models", []).size() == 22, "U_GRETCHIN_A has 22 models (got %d)" % gretchin.get("models", []).size())

	# Verify model data integrity
	print("\n--- Test: Model data integrity ---")
	for model in burna_a.get("models", []):
		_assert(model.has("id"), "Model has id")
		_assert(model.has("wounds"), "Model has wounds")
		_assert(model.has("base_mm"), "Model has base_mm")
		_assert(model.has("alive"), "Model has alive")
		_assert(model.get("alive", false) == true, "Model is alive")
		_assert(model.get("wounds", 0) == 1, "Model wounds == 1 (got %d)" % model.get("wounds", 0))
		_assert(model.get("base_mm", 0) == 32, "Model base_mm == 32 (got %d)" % model.get("base_mm", 0))

	# Verify unique model IDs
	var ids = []
	for model in burna_a.get("models", []):
		_assert(not model.get("id", "") in ids, "Model ID '%s' is unique" % model.get("id", ""))
		ids.append(model.get("id", ""))

	# --- Test: Load adeptus_custodes and verify ---
	print("\n--- Test: adeptus_custodes army model counts ---")
	var custodes_data = army_list_manager.load_army_list("adeptus_custodes", 2)
	_assert(not custodes_data.is_empty(), "adeptus_custodes army loaded successfully")

	if not custodes_data.is_empty():
		# Custodian Guard should have 4 models (minimum from unit_composition)
		var cg = custodes_data.units.get("U_CUSTODIAN_GUARD_B", {})
		_assert(cg.get("models", []).size() >= 4, "U_CUSTODIAN_GUARD_B has >= 4 models (got %d)" % cg.get("models", []).size())

		# Witchseekers should have 4 models (1 Superior + 3 Witchseekers)
		var ws = custodes_data.units.get("U_WITCHSEEKERS_C", {})
		_assert(ws.get("models", []).size() >= 4, "U_WITCHSEEKERS_C has >= 4 models (got %d)" % ws.get("models", []).size())

	print("\n=== Results: %d passed, %d failed ===" % [pass_count, fail_count])
	if fail_count == 0:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")
	quit()
