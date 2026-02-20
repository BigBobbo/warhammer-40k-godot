extends SceneTree

# Test script for DiceRollVisual (T5-V1)
# Run with: godot --headless --script res://tests/test_dice_roll_visual.gd

const DiceRollVisualScript = preload("res://scripts/DiceRollVisual.gd")

func _init():
	print("=== DiceRollVisual Test Suite ===")
	var pass_count := 0
	var fail_count := 0

	# Test 1: Instantiation
	var visual = DiceRollVisualScript.new()
	if visual != null:
		print("PASS: DiceRollVisual instantiated")
		pass_count += 1
	else:
		print("FAIL: DiceRollVisual failed to instantiate")
		fail_count += 1

	# Need to add to tree for timer to work
	root.add_child(visual)

	# Give frame for _ready
	await process_frame

	# Test 2: Initial state - should be invisible with no dice
	if not visual.visible:
		print("PASS: Initially invisible")
		pass_count += 1
	else:
		print("FAIL: Should be initially invisible")
		fail_count += 1

	# Test 3: Show dice roll with hit roll data
	var hit_data = {
		"context": "to_hit",
		"rolls_raw": [1, 3, 4, 5, 6, 2],
		"threshold": "3+",
		"successes": 4,
	}
	visual.show_dice_roll(hit_data)

	if visual.visible:
		print("PASS: Visible after show_dice_roll()")
		pass_count += 1
	else:
		print("FAIL: Should be visible after show_dice_roll()")
		fail_count += 1

	if visual._dice_data.size() == 6:
		print("PASS: Correct dice count (6)")
		pass_count += 1
	else:
		print("FAIL: Expected 6 dice, got %d" % visual._dice_data.size())
		fail_count += 1

	if visual._threshold == 3:
		print("PASS: Threshold parsed correctly (3)")
		pass_count += 1
	else:
		print("FAIL: Expected threshold 3, got %d" % visual._threshold)
		fail_count += 1

	if visual._is_animating:
		print("PASS: Animation started")
		pass_count += 1
	else:
		print("FAIL: Animation should be running")
		fail_count += 1

	if visual._context_label == "Hit Rolls (need 3+)":
		print("PASS: Context label correct")
		pass_count += 1
	else:
		print("FAIL: Expected 'Hit Rolls (need 3+)', got '%s'" % visual._context_label)
		fail_count += 1

	# Test 4: Color coding
	# 6 should be gold (critical)
	var color_6 = visual._get_die_color(6)
	if color_6 == DiceRollVisualScript.COLOR_CRITICAL:
		print("PASS: 6 is gold (critical)")
		pass_count += 1
	else:
		print("FAIL: 6 should be gold")
		fail_count += 1

	# 1 should be red (fumble)
	var color_1 = visual._get_die_color(1)
	if color_1 == DiceRollVisualScript.COLOR_FUMBLE:
		print("PASS: 1 is red (fumble)")
		pass_count += 1
	else:
		print("FAIL: 1 should be red")
		fail_count += 1

	# 4 (>= threshold 3) should be green
	var color_4 = visual._get_die_color(4)
	if color_4 == DiceRollVisualScript.COLOR_SUCCESS:
		print("PASS: 4 is green (success, >= 3)")
		pass_count += 1
	else:
		print("FAIL: 4 should be green")
		fail_count += 1

	# 2 (< threshold 3) should be gray
	var color_2 = visual._get_die_color(2)
	if color_2 == DiceRollVisualScript.COLOR_FAIL:
		print("PASS: 2 is gray (fail, < 3)")
		pass_count += 1
	else:
		print("FAIL: 2 should be gray")
		fail_count += 1

	# Test 5: Skip non-roll contexts
	visual.clear_display()
	var skip_data = {
		"context": "resolution_start",
		"message": "Test",
	}
	visual.show_dice_roll(skip_data)
	if not visual.visible:
		print("PASS: Skipped resolution_start context")
		pass_count += 1
	else:
		print("FAIL: Should skip resolution_start")
		fail_count += 1

	# Test 6: Wound roll
	var wound_data = {
		"context": "to_wound",
		"rolls_raw": [2, 5, 6],
		"threshold": "5+",
		"successes": 2,
	}
	visual.show_dice_roll(wound_data)
	if visual._context_label == "Wound Rolls (need 5+)":
		print("PASS: Wound roll context label")
		pass_count += 1
	else:
		print("FAIL: Wound roll label wrong: '%s'" % visual._context_label)
		fail_count += 1

	if visual._threshold == 5:
		print("PASS: Wound threshold correct (5)")
		pass_count += 1
	else:
		print("FAIL: Wound threshold wrong: %d" % visual._threshold)
		fail_count += 1

	# Test 7: Save roll
	var save_data = {
		"context": "save_roll",
		"rolls_raw": [1, 2, 3, 4, 5, 6],
		"threshold": "4+",
		"successes": 3,
		"failed": 3,
	}
	visual.show_dice_roll(save_data)
	if visual._context_label == "Save Rolls (need 4+)":
		print("PASS: Save roll context label")
		pass_count += 1
	else:
		print("FAIL: Save roll label wrong: '%s'" % visual._context_label)
		fail_count += 1

	# Test 8: Charge roll (no threshold)
	var charge_data = {
		"context": "charge_roll",
		"rolls_raw": [3, 5],
		"threshold": "",
	}
	visual.show_dice_roll(charge_data)
	if visual._context_label == "Charge Roll (2D6)":
		print("PASS: Charge roll context label")
		pass_count += 1
	else:
		print("FAIL: Charge roll label wrong: '%s'" % visual._context_label)
		fail_count += 1

	if visual._threshold == 0:
		print("PASS: Charge roll has no threshold (0)")
		pass_count += 1
	else:
		print("FAIL: Charge threshold should be 0, got %d" % visual._threshold)
		fail_count += 1

	# Test 9: Neutral coloring for charge (threshold=0)
	# Value 3 with threshold=0 should be neutral blue, not success/fail
	var charge_color_3 = visual._get_die_color(3)
	if charge_color_3 != DiceRollVisualScript.COLOR_SUCCESS and charge_color_3 != DiceRollVisualScript.COLOR_FAIL:
		print("PASS: Charge die uses neutral color (not success/fail)")
		pass_count += 1
	else:
		print("FAIL: Charge die should use neutral color")
		fail_count += 1

	# Test 10: Feel No Pain
	var fnp_data = {
		"context": "feel_no_pain",
		"rolls_raw": [2, 4, 5, 6],
		"threshold": "5+",
		"fnp_value": 5,
	}
	visual.show_dice_roll(fnp_data)
	if visual._context_label == "Feel No Pain (5+)":
		print("PASS: FNP context label")
		pass_count += 1
	else:
		print("FAIL: FNP label wrong: '%s'" % visual._context_label)
		fail_count += 1

	if visual._threshold == 5:
		print("PASS: FNP threshold correct (5)")
		pass_count += 1
	else:
		print("FAIL: FNP threshold wrong: %d" % visual._threshold)
		fail_count += 1

	# Test 11: Clear display
	visual.clear_display()
	if not visual.visible and visual._dice_data.is_empty():
		print("PASS: Clear display works")
		pass_count += 1
	else:
		print("FAIL: Clear display didn't work")
		fail_count += 1

	# Test 12: Empty rolls_raw should be skipped
	var empty_data = {
		"context": "to_hit",
		"rolls_raw": [],
		"threshold": "3+",
	}
	visual.show_dice_roll(empty_data)
	if not visual.visible:
		print("PASS: Empty rolls skipped")
		pass_count += 1
	else:
		print("FAIL: Empty rolls should be skipped")
		fail_count += 1

	# Test 13: Height calculation for multiple rows
	var many_dice = {
		"context": "to_hit",
		"rolls_raw": [1, 2, 3, 4, 5, 6, 1, 2, 3, 4, 5, 6, 1, 2, 3],  # 15 dice = 3 rows
		"threshold": "4+",
	}
	visual.show_dice_roll(many_dice)
	var expected_rows = 3  # ceil(15/7) = 3
	var expected_height = 16.0 + expected_rows * DiceRollVisualScript.ROW_HEIGHT + 4.0
	if visual.custom_minimum_size.y == expected_height:
		print("PASS: Height correct for %d dice (%d rows)" % [15, expected_rows])
		pass_count += 1
	else:
		print("FAIL: Height wrong: expected %.1f got %.1f" % [expected_height, visual.custom_minimum_size.y])
		fail_count += 1

	# Cleanup
	visual.queue_free()

	print("\n=== Results: %d passed, %d failed ===" % [pass_count, fail_count])
	if fail_count > 0:
		print("SOME TESTS FAILED!")
	else:
		print("ALL TESTS PASSED!")

	quit()
