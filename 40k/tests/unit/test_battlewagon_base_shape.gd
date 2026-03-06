extends SceneTree

# MA-34: Test that Battlewagon renders with rectangular base, not small circular
# Run: godot --headless --script tests/unit/test_battlewagon_base_shape.gd

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
	print("=== MA-34: Battlewagon Base Shape Test ===")
	call_deferred("_run_tests")

func _run_tests():
	await root.get_tree().process_frame
	await root.get_tree().process_frame

	var measurement = root.get_node_or_null("/root/Measurement")
	var army_list_manager = root.get_node_or_null("/root/ArmyListManager")

	_assert(measurement != null, "Measurement autoload exists")
	_assert(army_list_manager != null, "ArmyListManager autoload exists")
	if measurement == null or army_list_manager == null:
		print("\n=== Results: %d passed, %d failed ===" % [pass_count, fail_count])
		print("ABORTED: Required autoloads not found")
		quit()
		return

	# --- Test 1: Measurement.create_base_shape with rectangular model data ---
	print("\n--- Test 1: create_base_shape with rectangular data ---")
	var rect_model = {
		"id": "m1",
		"base_mm": 180,
		"base_type": "rectangular",
		"base_dimensions": {"length": 180, "width": 110}
	}
	var shape = measurement.create_base_shape(rect_model)
	_assert(shape != null, "create_base_shape returns non-null for rectangular model")
	_assert(shape.get_type() == "rectangular", "Shape type is 'rectangular' (got: %s)" % shape.get_type())

	# Check dimensions are correct (180mm and 110mm converted to px)
	var expected_length_px = measurement.mm_to_px(180)
	var expected_width_px = measurement.mm_to_px(110)
	var bounds = shape.get_bounds()
	_assert(abs(bounds.size.x - expected_length_px) < 1.0, "Rectangular shape length is ~%.1f px (got: %.1f)" % [expected_length_px, bounds.size.x])
	_assert(abs(bounds.size.y - expected_width_px) < 1.0, "Rectangular shape width is ~%.1f px (got: %.1f)" % [expected_width_px, bounds.size.y])

	# --- Test 2: Measurement.create_base_shape falls back to circular when no base_type ---
	print("\n--- Test 2: create_base_shape default circular fallback ---")
	var circular_model = {
		"id": "m1",
		"base_mm": 32
	}
	var circ_shape = measurement.create_base_shape(circular_model)
	_assert(circ_shape != null, "create_base_shape returns non-null for circular model")
	_assert(circ_shape.get_type() == "circular", "Shape type is 'circular' for model without base_type")

	# --- Test 3: Load orks.json and verify Battlewagon model data ---
	print("\n--- Test 3: Verify Battlewagon in orks.json ---")
	var orks_army = army_list_manager.load_army_list("orks", 2)
	_assert(not orks_army.is_empty(), "orks.json loaded successfully")

	if orks_army.has("units") and orks_army.units.has("U_BATTLEWAGON_G"):
		var bw_unit = orks_army.units["U_BATTLEWAGON_G"]
		var bw_models = bw_unit.get("models", [])
		_assert(bw_models.size() > 0, "Battlewagon has at least 1 model")

		if bw_models.size() > 0:
			var bw_model = bw_models[0]
			_assert(bw_model.has("base_type"), "Battlewagon model has base_type field")
			_assert(str(bw_model.get("base_type", "")) == "rectangular", "Battlewagon base_type is 'rectangular'")
			_assert(bw_model.has("base_dimensions"), "Battlewagon model has base_dimensions field")

			var bw_dims = bw_model.get("base_dimensions", {})
			_assert(int(bw_dims.get("length", 0)) == 180, "Battlewagon base_dimensions.length is 180")
			_assert(int(bw_dims.get("width", 0)) == 110, "Battlewagon base_dimensions.width is 110")
			_assert(int(bw_model.get("base_mm", 0)) == 180, "Battlewagon base_mm is 180 (not 32)")

			# Verify shape creation from loaded data
			var bw_shape = measurement.create_base_shape(bw_model)
			_assert(bw_shape.get_type() == "rectangular", "Battlewagon creates rectangular shape from loaded data")
	else:
		print("FAIL: U_BATTLEWAGON_G not found in orks.json")
		fail_count += 1

	# --- Test 4: Load Orks_2000.json and verify Battlewagon models ---
	print("\n--- Test 4: Verify Battlewagons in Orks_2000.json ---")
	var orks2k_army = army_list_manager.load_army_list("Orks_2000", 1)
	_assert(not orks2k_army.is_empty(), "Orks_2000.json loaded successfully")

	for bw_id in ["U_BATTLEWAGON_A", "U_BATTLEWAGON_B"]:
		if orks2k_army.has("units") and orks2k_army.units.has(bw_id):
			var bw_unit = orks2k_army.units[bw_id]
			var bw_models = bw_unit.get("models", [])
			if bw_models.size() > 0:
				var bw_model = bw_models[0]
				_assert(bw_model.has("base_type"), "%s model has base_type field" % bw_id)
				_assert(str(bw_model.get("base_type", "")) == "rectangular", "%s base_type is 'rectangular'" % bw_id)
				_assert(int(bw_model.get("base_mm", 0)) == 180, "%s base_mm is 180" % bw_id)

				var bw_shape = measurement.create_base_shape(bw_model)
				_assert(bw_shape.get_type() == "rectangular", "%s creates rectangular shape" % bw_id)
		else:
			print("FAIL: %s not found in Orks_2000.json" % bw_id)
			fail_count += 1

	# --- Test 5: Oval base (Caladius Grav-tank) ---
	print("\n--- Test 5: Verify Caladius Grav-tank oval base ---")
	var ac_army = army_list_manager.load_army_list("adeptus_custodes", 1)
	if not ac_army.is_empty() and ac_army.has("units"):
		var found_caladius = false
		for uid in ac_army.units:
			var unit = ac_army.units[uid]
			if unit.get("meta", {}).get("name", "") == "Caladius Grav-tank":
				found_caladius = true
				var models = unit.get("models", [])
				if models.size() > 0:
					var model = models[0]
					_assert(str(model.get("base_type", "")) == "oval", "Caladius base_type is 'oval'")
					var oval_shape = measurement.create_base_shape(model)
					_assert(oval_shape.get_type() == "oval", "Caladius creates oval shape")
				break
		_assert(found_caladius, "Caladius Grav-tank found in adeptus_custodes.json")

	# --- Print results ---
	print("\n=== Results: %d passed, %d failed ===" % [pass_count, fail_count])
	if fail_count == 0:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")

	quit()
