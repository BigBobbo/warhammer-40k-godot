extends SceneTree

# Test: P3-117 - DiceHistoryPanel autoload
# Validates that dice roll history recording and formatting work correctly
# Run with: godot --headless --script res://tests/test_dice_history_panel.gd

const DiceHistoryPanelScript = preload("res://autoloads/DiceHistoryPanel.gd")

var tests_passed := 0
var tests_failed := 0
var panel: Node = null

func _init() -> void:
	print("=== DiceHistoryPanel Test Suite ===\n")

	# Create a standalone instance for testing (not relying on autoload)
	panel = DiceHistoryPanelScript.new()
	root.add_child(panel)

	await process_frame
	await process_frame

	_test_initialization()
	_test_record_standard_roll()
	_test_record_charge_roll()
	_test_record_fnp_roll()
	_test_record_save_roll()
	_test_record_auto_hit()
	_test_record_variable_damage()
	_test_skip_non_roll_contexts()
	_test_clear()
	_test_max_history_limit()
	_test_format_entry_bbcode()
	_test_signal_emission()

	print("\n=== Results: %d passed, %d failed ===" % [tests_passed, tests_failed])

	if tests_failed > 0:
		print("SOME TESTS FAILED!")
	else:
		print("ALL TESTS PASSED!")

	panel.queue_free()
	quit()

func _assert(condition: bool, test_name: String) -> void:
	if condition:
		tests_passed += 1
		print("  PASS: %s" % test_name)
	else:
		tests_failed += 1
		print("  FAIL: %s" % test_name)

func _test_initialization() -> void:
	print("\n--- Test: Initialization ---")
	_assert(panel != null, "DiceHistoryPanel instance exists")
	_assert(panel.history is Array, "history is an Array")
	_assert(panel.history.size() == 0, "history starts empty")
	_assert(panel.MAX_HISTORY_ENTRIES == 500, "MAX_HISTORY_ENTRIES is 500")

func _test_record_standard_roll() -> void:
	print("\n--- Test: Record Standard Roll ---")
	panel.clear()

	var dice_data = {
		"context": "to_hit",
		"rolls_raw": [3, 5, 2, 6, 1, 4],
		"threshold": "3+",
		"successes": 4,
		"weapon": "bolt_rifle"
	}
	panel.record_roll(dice_data, "Shooting")

	_assert(panel.history.size() == 1, "history has 1 entry after recording")

	var entry = panel.history[0]
	_assert(entry.phase == "Shooting", "entry phase is Shooting")
	_assert(entry.context == "to_hit", "entry context is to_hit")
	_assert(entry.data.rolls_raw.size() == 6, "entry has 6 dice")
	_assert(entry.has("timestamp"), "entry has timestamp")
	_assert(entry.has("round"), "entry has round number")
	_assert(entry.has("player"), "entry has player number")

func _test_record_charge_roll() -> void:
	print("\n--- Test: Record Charge Roll ---")
	panel.clear()

	var dice_data = {
		"context": "charge_roll",
		"rolls": [4, 5],
		"total": 9,
		"unit_name": "Boyz",
		"charge_failed": false
	}
	panel.record_roll(dice_data, "Charge")

	_assert(panel.history.size() == 1, "history has 1 entry after charge roll")
	_assert(panel.history[0].context == "charge_roll", "entry context is charge_roll")
	_assert(panel.history[0].phase == "Charge", "entry phase is Charge")

func _test_record_fnp_roll() -> void:
	print("\n--- Test: Record Feel No Pain Roll ---")
	panel.clear()

	var dice_data = {
		"context": "feel_no_pain",
		"rolls_raw": [2, 5, 6, 1, 3],
		"fnp_value": 5,
		"wounds_prevented": 2,
		"wounds_remaining": 3,
		"total_wounds": 5
	}
	panel.record_roll(dice_data, "Shooting")

	_assert(panel.history.size() == 1, "history has 1 entry after FNP roll")
	_assert(panel.history[0].context == "feel_no_pain", "entry context is feel_no_pain")

func _test_record_save_roll() -> void:
	print("\n--- Test: Record Save Roll ---")
	panel.clear()

	var dice_data = {
		"context": "save_roll",
		"rolls_raw": [2, 4, 6, 1],
		"threshold": "3+",
		"failed": 2,
		"using_invuln": true
	}
	panel.record_roll(dice_data, "Shooting")

	_assert(panel.history.size() == 1, "history has 1 entry after save roll")
	_assert(panel.history[0].data.using_invuln == true, "save roll tracks invuln flag")

func _test_record_auto_hit() -> void:
	print("\n--- Test: Record Auto Hit (Torrent) ---")
	panel.clear()

	var dice_data = {
		"context": "auto_hit",
		"successes": 6,
		"message": "Torrent: 6 automatic hits"
	}
	panel.record_roll(dice_data, "Shooting")

	_assert(panel.history.size() == 1, "history has 1 entry after auto hit")

func _test_record_variable_damage() -> void:
	print("\n--- Test: Record Variable Damage ---")
	panel.clear()

	var dice_data = {
		"context": "variable_damage",
		"notation": "D6",
		"total_damage": 4,
		"rolls": [{"value": 4}]
	}
	panel.record_roll(dice_data, "Shooting")

	_assert(panel.history.size() == 1, "history has 1 entry after variable damage")

func _test_skip_non_roll_contexts() -> void:
	print("\n--- Test: Skip Non-Roll Contexts ---")
	panel.clear()

	var resolution_data = {"context": "resolution_start", "message": "Starting..."}
	panel.record_roll(resolution_data, "Shooting")
	_assert(panel.history.size() == 0, "resolution_start is skipped")

	var weapon_data = {"context": "weapon_progress", "message": "Bolt rifle"}
	panel.record_roll(weapon_data, "Shooting")
	_assert(panel.history.size() == 0, "weapon_progress is skipped")

func _test_clear() -> void:
	print("\n--- Test: Clear History ---")
	panel.record_roll({"context": "to_hit", "rolls_raw": [4], "threshold": "3+", "successes": 1}, "Shooting")
	panel.record_roll({"context": "to_wound", "rolls_raw": [5], "threshold": "4+", "successes": 1}, "Shooting")
	_assert(panel.history.size() > 0, "history is not empty before clear")

	panel.clear()
	_assert(panel.history.size() == 0, "history is empty after clear")

func _test_max_history_limit() -> void:
	print("\n--- Test: Max History Limit ---")
	panel.clear()

	# Add more than MAX_HISTORY_ENTRIES
	for i in range(panel.MAX_HISTORY_ENTRIES + 50):
		panel.record_roll({"context": "to_hit", "rolls_raw": [i % 6 + 1], "threshold": "3+", "successes": 1}, "Shooting")

	_assert(panel.history.size() == panel.MAX_HISTORY_ENTRIES, "history capped at MAX_HISTORY_ENTRIES (%d)" % panel.MAX_HISTORY_ENTRIES)
	panel.clear()

func _test_format_entry_bbcode() -> void:
	print("\n--- Test: Format Entry BBCode ---")
	panel.clear()

	# Test hit roll formatting
	var dice_data = {
		"context": "to_hit",
		"rolls_raw": [3, 5, 2, 6, 1],
		"threshold": "3+",
		"successes": 3,
		"critical_hits": 1
	}
	panel.record_roll(dice_data, "Shooting")
	var entry = panel.history[0]
	var bbcode = panel.format_entry_bbcode(entry)

	_assert(bbcode.length() > 0, "BBCode output is not empty")
	_assert("Hit" in bbcode, "BBCode contains 'Hit' label")
	_assert("3+" in bbcode, "BBCode contains threshold")
	_assert("crit" in bbcode, "BBCode contains critical hit info")

	# Test charge roll formatting
	panel.clear()
	var charge_data = {
		"context": "charge_roll",
		"rolls": [4, 5],
		"total": 9,
		"unit_name": "Boyz",
		"charge_failed": false
	}
	panel.record_roll(charge_data, "Charge")
	var charge_entry = panel.history[0]
	var charge_bbcode = panel.format_entry_bbcode(charge_entry)

	_assert("Charge" in charge_bbcode, "Charge BBCode contains 'Charge' label")
	_assert("Boyz" in charge_bbcode, "Charge BBCode contains unit name")
	_assert("SUCCESS" in charge_bbcode, "Charge BBCode contains SUCCESS")

	# Test failed charge formatting
	panel.clear()
	var failed_charge = {
		"context": "charge_roll",
		"rolls": [1, 2],
		"total": 3,
		"unit_name": "Kommandos",
		"charge_failed": true
	}
	panel.record_roll(failed_charge, "Charge")
	var failed_bbcode = panel.format_entry_bbcode(panel.history[0])
	_assert("FAILED" in failed_bbcode, "Failed charge BBCode contains FAILED")

	# Test save roll formatting
	panel.clear()
	var save_data = {
		"context": "save_roll",
		"rolls_raw": [2, 4],
		"threshold": "3+",
		"failed": 1,
		"using_invuln": true
	}
	panel.record_roll(save_data, "Shooting")
	var save_entry = panel.history[0]
	var save_bbcode = panel.format_entry_bbcode(save_entry)

	_assert("Save" in save_bbcode, "Save BBCode contains 'Save' label")
	_assert("inv" in save_bbcode, "Save BBCode contains invuln indicator")
	_assert("failed" in save_bbcode, "Save BBCode contains failure info")

	# Test FNP formatting
	panel.clear()
	var fnp_data = {
		"context": "feel_no_pain",
		"rolls_raw": [5, 6, 2],
		"fnp_value": 5,
		"wounds_prevented": 2,
		"wounds_remaining": 1
	}
	panel.record_roll(fnp_data, "Fight")
	var fnp_entry = panel.history[0]
	var fnp_bbcode = panel.format_entry_bbcode(fnp_entry)

	_assert("FNP" in fnp_bbcode, "FNP BBCode contains 'FNP' label")
	_assert("prevented" in fnp_bbcode, "FNP BBCode contains prevented info")

	# Test Torrent formatting
	panel.clear()
	var torrent_data = {
		"context": "auto_hit",
		"successes": 8,
		"message": "Torrent: 8 automatic hits"
	}
	panel.record_roll(torrent_data, "Shooting")
	var torrent_bbcode = panel.format_entry_bbcode(panel.history[0])
	_assert("Torrent" in torrent_bbcode, "Torrent BBCode contains 'Torrent'")
	_assert("auto-hits" in torrent_bbcode, "Torrent BBCode contains 'auto-hits'")

	# Test Variable Damage formatting
	panel.clear()
	var dmg_data = {
		"context": "variable_damage",
		"notation": "D6",
		"total_damage": 4,
		"rolls": [{"value": 4}]
	}
	panel.record_roll(dmg_data, "Shooting")
	var dmg_bbcode = panel.format_entry_bbcode(panel.history[0])
	_assert("Damage" in dmg_bbcode, "Damage BBCode contains 'Damage'")
	_assert("D6" in dmg_bbcode, "Damage BBCode contains notation")

	panel.clear()

func _test_signal_emission() -> void:
	print("\n--- Test: Signal Emission ---")
	panel.clear()

	# Use array/dict to work around GDScript lambda capture-by-value for primitives
	var state = {"received": false, "entry": {}}

	var callback = func(entry: Dictionary) -> void:
		state["received"] = true
		state["entry"] = entry

	panel.roll_recorded.connect(callback)

	panel.record_roll({"context": "to_hit", "rolls_raw": [4, 5], "threshold": "3+", "successes": 2}, "Shooting")

	_assert(state["received"] == true, "roll_recorded signal was emitted")
	_assert(state["entry"].context == "to_hit", "signal carried correct entry data")

	panel.roll_recorded.disconnect(callback)
