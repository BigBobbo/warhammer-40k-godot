extends SceneTree

# Regression: TestModeHandler must not double-execute a single command file.
#
# Background: the handler runs `_check_for_commands` every 100ms. Each command
# handler can internally `await` (e.g. `_handle_use_grenade_stratagem` calls
# into the stratagem flow which yields to NetworkManager / signal handlers).
# During that await the command file still sits on disk because deletion
# happens after the await returns. Without de-dup, the next 100ms scanner
# tick re-picks up the same file and runs the same handler a second time
# — by which point the active phase has been torn down, so the duplicate
# clobbers the legitimate result with a "No active phase instance" failure.
#
# Trace excerpt (from /tmp/mp_run4.log) showing the bug pre-fix:
#
#   TestModeHandler: Processing command file host_40793_cmd_004.json   <- 1st
#   TestModeHandler: Executing action: use_grenade_stratagem
#   ShootingPhase: Matched USE_GRENADE_STRATAGEM
#   StratagemManager: GRENADE rolled [...] — 1 mortal wound(s)         <- real run
#   TestModeHandler: Processing command file host_40793_cmd_004.json   <- 2nd (race)
#   [PhaseManager] get_current_phase_instance returning: null
#   TestModeHandler: Result written to: host_40793_cmd_004_result.json <- writes fail
#   [Test] Action completed: success=false, message=No active phase instance
#
# Fix: in-flight set keyed by command filename. `_check_for_commands` skips
# any filename already in the set; `_execute_command_file` adds on entry and
# removes after the result is on disk and the file is deleted.
#
# What this test pins:
#   1. _commands_in_flight is the right shape (Dictionary).
#   2. While a long-running handler is awaiting, `_check_for_commands` does
#      NOT re-enter for the same filename — the in-flight marker blocks it.
#   3. A second, distinct command file run AFTER the first completes is not
#      blocked (the cleanup step actually erases the marker).
#   4. The early-return path on a malformed JSON command file also clears
#      the in-flight marker (defensive — otherwise a parse failure would
#      permanently wedge that filename).
#
# Usage: godot --headless --path . -s tests/test_test_mode_handler_command_dedupe.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_test_mode_handler_command_dedupe ===\n")

	_test_in_flight_dictionary_exists()
	_test_scanner_skips_in_flight_filename()
	_test_marker_cleared_after_completion()
	_test_marker_cleared_on_parse_failure()

	_finish()

# ---------------------------------------------------------------------------
# 1. _commands_in_flight must exist on the autoload as a Dictionary.
# ---------------------------------------------------------------------------
func _test_in_flight_dictionary_exists() -> void:
	print("\n-- _commands_in_flight existence + shape --")
	var test_handler = root.get_node("TestModeHandler")
	_check("TestModeHandler autoload present", test_handler != null)
	if test_handler == null:
		return
	_check("TestModeHandler exposes _commands_in_flight",
		"_commands_in_flight" in test_handler,
		"missing field — fix not applied")
	_check("_commands_in_flight is a Dictionary",
		typeof(test_handler._commands_in_flight) == TYPE_DICTIONARY,
		"got typeof=%d" % typeof(test_handler._commands_in_flight))

# ---------------------------------------------------------------------------
# 2. While a filename is marked in-flight, _check_for_commands must not
#    invoke _execute_command_file again for that same filename. We can't
#    easily intercept _execute_command_file from outside the autoload, but
#    we CAN observe the side effect: if the scanner attempted re-entry,
#    _commands_in_flight[file_name] would still be true (no double-entry
#    guard would erase it between the two runs); but the more direct way
#    is to verify the early-skip behavior by reading the loop directly.
#
#    We simulate the race by:
#      - Pre-marking a fake filename as in-flight
#      - Manually placing a real command file with that filename on disk
#      - Calling _check_for_commands once
#      - Asserting that the file is still on disk (scanner skipped it)
#        and that _commands_in_flight still contains it (we put it there
#        and the scanner's skip path does not erase it).
# ---------------------------------------------------------------------------
func _test_scanner_skips_in_flight_filename() -> void:
	print("\n-- scanner skips in-flight filename --")
	var test_handler = root.get_node("TestModeHandler")
	if test_handler == null:
		return

	# Ensure command directories are set up (autoload normally does this in
	# _ready, but the test environment may not have triggered the test-mode
	# branch). We need to be careful: only set up if not already initialized,
	# and only run the scanner if the dirs are real.
	if test_handler._command_dir == "":
		test_handler._setup_command_directories()

	var file_name := "test_dedupe_race_001.json"
	var file_path: String = test_handler._command_dir + "/" + file_name

	# Write a synthetic command file that, IF executed, would call
	# get_game_state (a known handler) — but we never want execution to
	# happen here, so the dedupe guard is what we're testing.
	var f = FileAccess.open(file_path, FileAccess.WRITE)
	if f == null:
		_check("could open synthetic command file at %s" % file_path, false,
			"FileAccess.open returned null — cannot complete test")
		return
	f.store_string(JSON.stringify({
		"sequence": 999,
		"command": {"action": "get_game_state", "parameters": {}}
	}))
	f.close()

	# Pre-mark this filename as in-flight so the scanner's guard fires.
	test_handler._commands_in_flight[file_name] = true

	# Run the scanner. With the guard in place, this MUST NOT call
	# _execute_command_file for our pre-marked filename. If the guard is
	# missing, _execute_command_file would run, write a result, and delete
	# the command file.
	test_handler._check_for_commands()

	# Verify the command file is still present (scanner skipped it).
	var still_present := FileAccess.file_exists(file_path)
	_check("command file still present after in-flight scan",
		still_present,
		"file was deleted — scanner did NOT skip; race fix not in place")

	# Verify the in-flight marker is still set (we set it; the skip path
	# must NOT erase it — only the completion path in _execute_command_file does).
	_check("_commands_in_flight still has filename after skip",
		test_handler._commands_in_flight.has(file_name),
		"marker erased by scanner — cleanup ran on the wrong path")

	# Cleanup: erase the marker and remove the synthetic file.
	test_handler._commands_in_flight.erase(file_name)
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)

# ---------------------------------------------------------------------------
# 3. After a real handler invocation completes, the in-flight marker must
#    be erased so a subsequent request with a DIFFERENT filename can run,
#    and the SAME filename (if a fresh request reuses it) is not blocked.
#    We drive a synthetic command end-to-end through _execute_command_file
#    and assert the marker clears.
# ---------------------------------------------------------------------------
func _test_marker_cleared_after_completion() -> void:
	print("\n-- marker cleared after handler completes --")
	var test_handler = root.get_node("TestModeHandler")
	if test_handler == null:
		return

	if test_handler._command_dir == "":
		test_handler._setup_command_directories()

	var file_name := "test_dedupe_complete_001.json"
	var file_path: String = test_handler._command_dir + "/" + file_name

	var f = FileAccess.open(file_path, FileAccess.WRITE)
	if f == null:
		_check("could open synthetic command file", false)
		return
	f.store_string(JSON.stringify({
		"sequence": 1000,
		"command": {"action": "get_game_state", "parameters": {}}
	}))
	f.close()

	# Sanity: marker not set before run.
	_check("marker not set before run",
		not test_handler._commands_in_flight.has(file_name))

	# Drive the file through the handler. This synchronously enters the
	# function, executes get_game_state (fast, non-awaiting in normal cases),
	# writes the result, deletes the command file, and erases the marker.
	await test_handler._execute_command_file(file_name)

	# After completion, the marker MUST be cleared so future invocations
	# (or a re-issued command of the same filename) are not blocked.
	_check("marker erased after completion",
		not test_handler._commands_in_flight.has(file_name),
		"marker still set — cleanup path did not run")

	# Sanity: command file deleted.
	_check("command file deleted by handler",
		not FileAccess.file_exists(file_path))

	# Cleanup the result file the handler produced (we don't care about its
	# contents, just don't leave litter).
	var result_file: String = test_handler._result_dir + "/" + file_name.replace(".json", "_result.json")
	if FileAccess.file_exists(result_file):
		DirAccess.remove_absolute(result_file)

# ---------------------------------------------------------------------------
# 4. The early-return paths (failed FileAccess.open, JSON parse failure)
#    must also clear the in-flight marker — otherwise a single corrupted
#    command file would permanently wedge that filename.
# ---------------------------------------------------------------------------
func _test_marker_cleared_on_parse_failure() -> void:
	print("\n-- marker cleared on parse failure --")
	var test_handler = root.get_node("TestModeHandler")
	if test_handler == null:
		return

	if test_handler._command_dir == "":
		test_handler._setup_command_directories()

	var file_name := "test_dedupe_parsefail_001.json"
	var file_path: String = test_handler._command_dir + "/" + file_name

	# Write garbage that will fail JSON parse.
	var f = FileAccess.open(file_path, FileAccess.WRITE)
	if f == null:
		_check("could open synthetic command file", false)
		return
	f.store_string("{not valid json")
	f.close()

	_check("marker not set before parse-fail run",
		not test_handler._commands_in_flight.has(file_name))

	await test_handler._execute_command_file(file_name)

	_check("marker erased after parse failure",
		not test_handler._commands_in_flight.has(file_name),
		"marker still set after parse failure — early-return cleanup missing")

	# Best-effort cleanup of the synthetic file.
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)

# ---------------------------------------------------------------------------

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
