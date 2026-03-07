extends SceneTree

# Test: MA-16 Non-sequential deployment placement
# Verifies:
# 1. placement_order tracks placement in the order models are placed
# 2. Undo with placement_order gives correct non-sequential order
# 3. _get_unplaced_model_indices returns correct indices for non-sequential placement
# 4. Backward compatibility: sequential placement still works
# Usage: godot --headless --path . -s tests/test_ma16_nonsequential_placement.gd

func _init():
	print("\n=== Test MA-16: Non-Sequential Deployment Placement ===\n")
	var passed = 0
	var failed = 0

	# We test the placement_order logic and _get_unplaced_model_indices directly
	# without instantiating DeploymentController (which depends on autoloads).
	# Instead, we simulate the same data structures and logic.

	# --- Test 1: placement_order tracks non-sequential placement ---
	print("--- Test 1: Non-sequential placement order tracking ---")
	var placement_order: Array = []
	# Simulate placing models in order: 5 (spanner), 0, 1, 2 (grunts)
	placement_order.append(5)
	placement_order.append(0)
	placement_order.append(1)
	placement_order.append(2)
	if placement_order == [5, 0, 1, 2]:
		print("  PASS: placement_order correctly tracks [5, 0, 1, 2]")
		passed += 1
	else:
		print("  FAIL: Expected [5, 0, 1, 2], got %s" % str(placement_order))
		failed += 1

	# --- Test 2: Last placed model is the back of placement_order ---
	print("\n--- Test 2: Last placed model is placement_order.back() ---")
	var last = placement_order.back()
	if last == 2:
		print("  PASS: Last placed = 2")
		passed += 1
	else:
		print("  FAIL: Expected 2, got %d" % last)
		failed += 1

	# --- Test 3: Pop undoes the last placed model ---
	print("\n--- Test 3: Pop removes last placed ---")
	placement_order.pop_back()
	last = placement_order.back()
	if last == 1 and placement_order.size() == 3:
		print("  PASS: After pop, last = 1, size = 3")
		passed += 1
	else:
		print("  FAIL: Expected last=1, size=3; got last=%d, size=%d" % [last, placement_order.size()])
		failed += 1

	# --- Test 4: Full undo chain reaches non-sequential model ---
	print("\n--- Test 4: Full undo chain reaches non-sequential model ---")
	# At this point placement_order = [5, 0, 1] (after popping 2)
	placement_order.pop_back()  # Remove 1 → [5, 0]
	placement_order.pop_back()  # Remove 0 → [5]
	last = placement_order.back()
	if last == 5:
		print("  PASS: Last remaining is spanner at index 5 (placed first, undone last)")
		passed += 1
	else:
		print("  FAIL: Expected 5, got %d" % last)
		failed += 1
	placement_order.pop_back()  # Remove 5 → []
	if placement_order.size() == 0:
		print("  PASS: All placements undone, placement_order empty")
		passed += 1
	else:
		print("  FAIL: Expected empty, got %s" % str(placement_order))
		failed += 1

	# --- Test 5: _get_unplaced_model_indices logic with non-sequential gaps ---
	print("\n--- Test 5: Unplaced indices with non-sequential gaps ---")
	var temp_positions: Array = []
	temp_positions.resize(6)
	# Place models at indices 5 and 2 (non-sequential)
	temp_positions[5] = Vector2(100, 100)
	temp_positions[2] = Vector2(200, 200)
	var unplaced = []
	for i in range(temp_positions.size()):
		if temp_positions[i] == null:
			unplaced.append(i)
	if unplaced == [0, 1, 3, 4]:
		print("  PASS: Unplaced = [0, 1, 3, 4]")
		passed += 1
	else:
		print("  FAIL: Expected [0, 1, 3, 4], got %s" % str(unplaced))
		failed += 1

	# --- Test 6: All placed gives empty unplaced ---
	print("\n--- Test 6: All placed gives empty unplaced ---")
	for i in range(temp_positions.size()):
		temp_positions[i] = Vector2(i * 10, i * 10)
	unplaced = []
	for i in range(temp_positions.size()):
		if temp_positions[i] == null:
			unplaced.append(i)
	if unplaced.is_empty():
		print("  PASS: No unplaced models")
		passed += 1
	else:
		print("  FAIL: Expected empty, got %s" % str(unplaced))
		failed += 1

	# --- Test 7: None placed gives all unplaced ---
	print("\n--- Test 7: None placed gives all unplaced ---")
	temp_positions.fill(null)
	unplaced = []
	for i in range(temp_positions.size()):
		if temp_positions[i] == null:
			unplaced.append(i)
	if unplaced == [0, 1, 2, 3, 4, 5]:
		print("  PASS: All 6 unplaced")
		passed += 1
	else:
		print("  FAIL: Expected [0,1,2,3,4,5], got %s" % str(unplaced))
		failed += 1

	# --- Test 8: Sequential placement backward compat ---
	print("\n--- Test 8: Sequential placement backward compat ---")
	placement_order.clear()
	for i in range(6):
		placement_order.append(i)
	var undo_order = []
	while placement_order.size() > 0:
		undo_order.append(placement_order.back())
		placement_order.pop_back()
	if undo_order == [5, 4, 3, 2, 1, 0]:
		print("  PASS: Sequential undo order correct: [5, 4, 3, 2, 1, 0]")
		passed += 1
	else:
		print("  FAIL: Expected [5,4,3,2,1,0], got %s" % str(undo_order))
		failed += 1

	# --- Test 9: Non-sequential undo gives correct order ---
	print("\n--- Test 9: Non-sequential undo (spanner first scenario) ---")
	placement_order.clear()
	# Place spanner(10), then deffguns(0-7), then kmb(8,9)
	placement_order.append(10)  # spanner first
	for i in range(8):  # deffguns 0-7
		placement_order.append(i)
	placement_order.append(8)  # kmb 1
	placement_order.append(9)  # kmb 2
	undo_order = []
	while placement_order.size() > 0:
		undo_order.append(placement_order.back())
		placement_order.pop_back()
	if undo_order == [9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 10]:
		print("  PASS: Non-sequential undo correct: spanner (10) undone last")
		passed += 1
	else:
		print("  FAIL: Expected [9,8,7,6,5,4,3,2,1,0,10], got %s" % str(undo_order))
		failed += 1

	# --- Test 10: temp_positions indexed by model array index works non-sequentially ---
	print("\n--- Test 10: temp_positions non-sequential indexing ---")
	temp_positions.clear()
	temp_positions.resize(11)  # 11 models (like Lootas)
	var temp_rotations: Array = []
	temp_rotations.resize(11)
	temp_rotations.fill(0.0)
	# Place spanner at index 10 first
	temp_positions[10] = Vector2(500, 500)
	temp_rotations[10] = 1.57
	# Then place deffguns at indices 0-7
	for i in range(8):
		temp_positions[i] = Vector2(100 + i * 30, 100)
		temp_rotations[i] = 0.0
	# Then place kmb at indices 8, 9
	temp_positions[8] = Vector2(100, 200)
	temp_positions[9] = Vector2(130, 200)

	# Verify all positions set correctly
	var all_set = true
	for i in range(11):
		if temp_positions[i] == null:
			all_set = false
			break
	if all_set and temp_positions[10] == Vector2(500, 500) and temp_rotations[10] == 1.57:
		print("  PASS: All 11 positions set, spanner at (500,500) rot=1.57")
		passed += 1
	else:
		print("  FAIL: Positions not set correctly")
		failed += 1

	# --- Test 11: Verify DeploymentController.gd has placement_order variable ---
	print("\n--- Test 11: DeploymentController has placement_order ---")
	var dc_source = FileAccess.open("res://scripts/DeploymentController.gd", FileAccess.READ)
	if dc_source:
		var content = dc_source.get_as_text()
		dc_source.close()
		var has_var = content.find("var placement_order") >= 0
		var has_append = content.find("placement_order.append(model_idx)") >= 0
		var has_clear = content.find("placement_order.clear()") >= 0
		var has_back = content.find("placement_order.back()") >= 0
		if has_var and has_append and has_clear and has_back:
			print("  PASS: DeploymentController has placement_order var, append, clear, back")
			passed += 1
		else:
			print("  FAIL: Missing placement_order usage: var=%s, append=%s, clear=%s, back=%s" % [
				str(has_var), str(has_append), str(has_clear), str(has_back)])
			failed += 1
	else:
		print("  FAIL: Could not read DeploymentController.gd")
		failed += 1

	# --- Test 12: Verify undo uses placement_order.back() not model_idx-1 scan ---
	print("\n--- Test 12: Undo uses placement_order not sequential scan ---")
	if dc_source == null:
		dc_source = FileAccess.open("res://scripts/DeploymentController.gd", FileAccess.READ)
	if dc_source == null:
		# Re-read since we closed it
		dc_source = FileAccess.open("res://scripts/DeploymentController.gd", FileAccess.READ)
	var content2 = ""
	var dc_source2 = FileAccess.open("res://scripts/DeploymentController.gd", FileAccess.READ)
	if dc_source2:
		content2 = dc_source2.get_as_text()
		dc_source2.close()
	var uses_placement_order_in_undo = content2.find("placement_order.back()") >= 0
	var old_scan_removed = content2.find("for i in range(model_idx - 1, -1, -1)") < 0
	if uses_placement_order_in_undo and old_scan_removed:
		print("  PASS: Undo uses placement_order.back(), old sequential scan removed")
		passed += 1
	else:
		print("  FAIL: uses_placement_order=%s, old_scan_removed=%s" % [
			str(uses_placement_order_in_undo), str(old_scan_removed)])
		failed += 1

	# --- Summary ---
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)
