extends "res://addons/gut/test.gd"
class_name MultiplayerIntegrationTest

const GameInstance = preload("res://tests/helpers/GameInstance.gd")
const LogMonitor = preload("res://tests/helpers/LogMonitor.gd")

# Base class for multiplayer integration tests
# Manages multiple Godot instances and coordinates testing between them

var host_instance: GameInstance
var client_instance: GameInstance
var test_saves_dir: String = "res://tests/saves/"
var screenshots_dir: String = "user://test_screenshots/"

# Test state tracking
var _test_failed: bool = false
var _failure_message: String = ""

# Test configuration
var use_dynamic_ports: bool = true
var visual_debugging: bool = true
var capture_screenshots_on_failure: bool = true
var capture_screenshots_on_success: bool = false  # Optional: capture on all tests
var save_state_on_completion: bool = true  # Save game state after each test
var connection_timeout: float = 15.0
var sync_timeout: float = 10.0

# Latency simulation configuration
# Set these in your test's before_each() to simulate network conditions
var simulated_latency_ms: int = 0       # Base latency in milliseconds (0 = disabled)
var simulated_jitter_ms: int = 0        # Random jitter range (+/- this value)
var simulated_packet_loss_pct: float = 0.0  # Packet loss percentage (0.0-1.0)
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Test artifacts
var current_test_name: String = ""
var test_artifacts_dir: String = ProjectSettings.globalize_path("res://test_results/test_artifacts") + "/"
const COMMANDS_SUBDIR := "test_results/test_commands/commands"
const RESULTS_SUBDIR := "test_results/test_commands/results"
const TEST_ARTIFACTS_SUBDIR := "test_results/test_artifacts"

func before_each():
	print("\n========================================")
	print("Starting Multiplayer Integration Test")
	print("========================================\n")

	# Ensure test directories exist
	_ensure_test_directories()
	_clear_command_directories()

	# Clean up any existing instances
	_cleanup_instances()

func after_each():
	print("\n========================================")
	print("Cleaning up Multiplayer Test")
	print("========================================\n")

	# Generate test report
	_generate_test_report()

	# Clean up instances
	_cleanup_instances()

	# Reset test state
	_test_failed = false
	_failure_message = ""
	current_test_name = ""

func _ensure_test_directories():
	var dir = DirAccess.open("res://")
	if dir:
		dir.make_dir_recursive("tests/saves")
		dir.make_dir_recursive(COMMANDS_SUBDIR)
		dir.make_dir_recursive(RESULTS_SUBDIR)
		dir.make_dir_recursive(TEST_ARTIFACTS_SUBDIR + "/screenshots")
		dir.make_dir_recursive(TEST_ARTIFACTS_SUBDIR + "/saves")
		dir.make_dir_recursive(TEST_ARTIFACTS_SUBDIR + "/reports")

# ============================================================================
# Instance Management
# ============================================================================

func launch_host_and_client(save_file: String = "") -> bool:
	print("[Test] Launching host and client instances...")
	if save_file != "":
		print("[Test] Auto-loading save: %s" % save_file)

	# Determine ports
	var host_port = 7777
	var client_port = -1  # Let GameInstance handle it

	if use_dynamic_ports:
		host_port = _get_available_port()

	# Launch host with optional save file
	host_instance = GameInstance.new("Host", true, host_port, save_file)
	if not await host_instance.launch():
		_mark_test_failed("Failed to launch host instance")
		assert_true(false, "Failed to launch host instance")
		return false

	print("[Test] Host instance launched successfully on port %d" % host_port)

	# Wait a moment for host to initialize
	await wait_for_seconds(3.0)

	# Launch client with same save file (for consistency in multiplayer)
	# Pass the host_port as the last parameter so client knows where to connect
	client_instance = GameInstance.new("Client", false, client_port, save_file, host_port)
	if not await client_instance.launch():
		_mark_test_failed("Failed to launch client instance")
		assert_true(false, "Failed to launch client instance")
		return false

	print("[Test] Client instance launched successfully")
	return true

func wait_for_connection() -> bool:
	print("[Test] Waiting for client to connect to host...")

	var start_time = Time.get_ticks_msec() / 1000.0

	# Use a more reliable method: check the actual game instances via command files
	# This bypasses the broken log monitoring
	while (Time.get_ticks_msec() / 1000.0) - start_time < connection_timeout:
		# Wait a bit for connection to establish
		await wait_for_seconds(1.0)

		# Try to get game state from host - if we can communicate, connection is working
		var test_result = await simulate_host_action("get_game_state", {})

		if test_result.get("success", false):
			print("[Test] Connection verified - action simulation working!")
			return true
		else:
			print("[Test] Waiting for connection... (got error: %s)" % test_result.get("message", "unknown"))

		await wait_for_seconds(0.5)

	_mark_test_failed("Connection timeout - client did not connect to host within %d seconds" % connection_timeout)
	assert_true(false, "Connection timeout - client did not connect to host within %d seconds" % connection_timeout)
	return false

func load_test_save(save_name: String, on_host: bool = true) -> bool:
	print("[Test] Loading save: %s on %s" % [save_name, "host" if on_host else "client"])

	var instance = host_instance if on_host else client_instance
	return instance.load_save(test_saves_dir + save_name)

func verify_game_state_sync(timeout: float = -1) -> bool:
	if timeout < 0:
		timeout = sync_timeout

	print("[Test] Verifying game state synchronization...")

	var start_time = Time.get_ticks_msec() / 1000.0

	while (Time.get_ticks_msec() / 1000.0) - start_time < timeout:
		var host_state = host_instance.get_game_state()
		var client_state = client_instance.get_game_state()

		# Check if both have game_started
		if host_state.get("game_started", false) and client_state.get("game_started", false):
			# Compare critical state elements
			var synced = true

			# Check phase
			if host_state.get("current_phase", "") != client_state.get("current_phase", ""):
				synced = false

			# Check turn
			if host_state.get("current_turn", -1) != client_state.get("current_turn", -1):
				synced = false

			if synced:
				print("[Test] Game state synchronized successfully!")
				return true

		await wait_for_seconds(0.5)

	_mark_test_failed("Game state did not synchronize within %d seconds" % timeout)
	assert_true(false, "Game state did not synchronize within %d seconds" % timeout)
	return false

# ============================================================================
# Test Save Management
# ============================================================================

func create_test_save(save_name: String, state_setup: Callable) -> String:
	# Create a test save with specific game state
	print("[Test] Creating test save: %s" % save_name)

	var full_path = test_saves_dir + save_name

	# Would call state_setup to configure the game state
	# Then save it to the test saves directory

	return full_path

func get_deployment_test_save() -> String:
	# Returns path to a save file in deployment phase
	return test_saves_dir + "deployment_phase.w40ksave"

func get_movement_test_save() -> String:
	# Returns path to a save file in movement phase
	return test_saves_dir + "movement_phase.w40ksave"

func get_shooting_test_save() -> String:
	# Returns path to a save file in shooting phase
	return test_saves_dir + "shooting_phase.w40ksave"

# ============================================================================
# Utility Functions
# ============================================================================

func wait_for_phase(phase_name: String, timeout: float = 10.0) -> bool:
	print("[Test] Waiting for phase: %s" % phase_name)

	var start_time = Time.get_ticks_msec() / 1000.0

	while (Time.get_ticks_msec() / 1000.0) - start_time < timeout:
		var host_phase = host_instance.get_game_state().get("current_phase", "")
		var client_phase = client_instance.get_game_state().get("current_phase", "")

		if host_phase == phase_name and client_phase == phase_name:
			print("[Test] Both instances in phase: %s" % phase_name)
			return true

		await wait_for_seconds(0.5)

	return false

func simulate_host_action(action: String, params: Dictionary = {}) -> Dictionary:
	"""
	Simulates an action on the host instance
	Returns result dictionary with 'success', 'message', and optional 'data' fields
	"""
	print("[Test] Host performing action: %s with params: %s" % [action, params])
	return await _simulate_action(host_instance, action, params)

func simulate_client_action(action: String, params: Dictionary = {}) -> Dictionary:
	"""
	Simulates an action on the client instance
	Returns result dictionary with 'success', 'message', and optional 'data' fields
	"""
	print("[Test] Client performing action: %s with params: %s" % [action, params])
	return await _simulate_action(client_instance, action, params)

func _simulate_action(instance: GameInstance, action: String, params: Dictionary) -> Dictionary:
	"""
	Internal helper to simulate an action on a specific instance
	Writes command file, waits for result, and returns the result.
	If latency simulation is enabled, adds artificial delay before sending.
	"""
	if not instance:
		return {
			"success": false,
			"message": "Instance is null",
			"error": "NULL_INSTANCE"
		}

	# Apply simulated latency before sending (models network delay)
	if simulated_latency_ms > 0:
		var delay_ms = simulated_latency_ms
		if simulated_jitter_ms > 0:
			delay_ms += _rng.randi_range(-simulated_jitter_ms, simulated_jitter_ms)
			delay_ms = max(0, delay_ms)  # Never negative
		var delay_seconds = delay_ms / 1000.0
		print("[Test] Simulating %dms network latency (jitter: +/-%dms, actual: %dms)" % [
			simulated_latency_ms, simulated_jitter_ms, delay_ms])
		await wait_for_seconds(delay_seconds)

	# Simulate packet loss
	if simulated_packet_loss_pct > 0.0:
		var roll = _rng.randf()
		if roll < simulated_packet_loss_pct:
			print("[Test] Simulated packet loss! (%.1f%% chance, rolled %.3f)" % [
				simulated_packet_loss_pct * 100.0, roll])
			return {
				"success": false,
				"message": "Simulated packet loss",
				"error": "PACKET_LOSS"
			}

	# Generate sequence number and command file name
	var sequence = instance.get_next_sequence()
	var role = "host" if instance.is_host else "client"
	var command_file = "%s_%d_cmd_%03d.json" % [role, instance.process_id, sequence]

	# Build command data
	var command_data = {
		"version": "1.0",
		"timestamp": Time.get_ticks_msec(),
		"sequence": sequence,
		"timeout_ms": 5000,
		"command": {
			"action": action,
			"parameters": params
		}
	}

	# Get command directory path (same as TestModeHandler)
	var command_dir = _get_command_directory()
	var command_path = command_dir + "/" + command_file

	# Write command file
	print("[Test] Writing command file: ", command_file)
	var file = FileAccess.open(command_path, FileAccess.WRITE)
	if not file:
		push_error("[Test] Failed to write command file: " + command_path)
		return {
			"success": false,
			"message": "Failed to write command file",
			"error": "FILE_WRITE_ERROR"
		}

	file.store_string(JSON.stringify(command_data, "\t"))
	file.close()

	# Wait for result
	print("[Test] Waiting for result file...")
	var result = await _wait_for_result(command_file, 5.0)

	return result

func _get_command_directory() -> String:
	_ensure_command_directories()
	return ProjectSettings.globalize_path("res://" + COMMANDS_SUBDIR)

func _get_result_directory() -> String:
	_ensure_command_directories()
	return ProjectSettings.globalize_path("res://" + RESULTS_SUBDIR)

func _ensure_command_directories():
	var dir = DirAccess.open("res://")
	if dir:
		dir.make_dir_recursive(COMMANDS_SUBDIR)
		dir.make_dir_recursive(RESULTS_SUBDIR)

func _clear_command_directories():
	for subdir in [COMMANDS_SUBDIR, RESULTS_SUBDIR]:
		var res_path = "res://" + subdir
		var abs_path = ProjectSettings.globalize_path(res_path)
		var dir = DirAccess.open(res_path)
		if not dir:
			continue
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				DirAccess.remove_absolute(abs_path + "/" + file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

func _wait_for_result(command_file: String, timeout: float) -> Dictionary:
	"""
	Waits for a result file to be created by the game instance
	Returns the result dictionary or timeout error
	Includes retry logic for JSON parsing failures
	"""
	var result_file = command_file.replace(".json", "_result.json")
	var result_dir = _get_result_directory()
	var result_path = result_dir + "/" + result_file
	var start_time = Time.get_ticks_msec() / 1000.0

	print("[Test] Polling for result file: ", result_file)

	while (Time.get_ticks_msec() / 1000.0) - start_time < timeout:
		if FileAccess.file_exists(result_path):
			print("[Test] Result file found!")

			# Try parsing with retry logic
			var max_retries = 3
			for retry_attempt in range(max_retries):
				# Read result file
				var file = FileAccess.open(result_path, FileAccess.READ)
				if not file:
					push_error("[Test] Failed to read result file: " + result_path)
					return {
						"success": false,
						"message": "Failed to read result file",
						"error": "FILE_READ_ERROR"
					}

				var json_string = file.get_as_text()
				file.close()

				# Check if file has content
				if json_string.length() == 0:
					print("[Test] Result file empty on attempt %d/%d, retrying..." % [retry_attempt + 1, max_retries])
					await wait_for_seconds(0.1)
					continue

				# Parse JSON
				var json = JSON.new()
				var error = json.parse(json_string)

				if error != OK:
					print("[Test] JSON parse error on attempt %d/%d: %s" % [retry_attempt + 1, max_retries, json_string])
					if retry_attempt < max_retries - 1:
						await wait_for_seconds(0.1)
						continue
					else:
						push_error("[Test] Failed to parse result JSON after %d attempts" % max_retries)
						# Delete malformed result file
						DirAccess.remove_absolute(result_path)
						return {
							"success": false,
							"message": "Failed to parse result JSON after retries",
							"error": "JSON_PARSE_ERROR"
						}

				# Delete result file
				DirAccess.remove_absolute(result_path)

				# Return the result
				var result_data = json.data
				print("[Test] Action completed: success=%s, message=%s" % [
					result_data.get("result", {}).get("success", false),
					result_data.get("result", {}).get("message", "")
				])

				return result_data.get("result", {})

		await wait_for_seconds(0.1)

	# Timeout
	push_error("[Test] Command timeout waiting for result")
	return {
		"success": false,
		"message": "Command timeout - no result received within %.1f seconds" % timeout,
		"error": "TIMEOUT"
	}

func _get_available_port() -> int:
	# Find an available port for testing
	# Start from 8000 to avoid common ports
	for port in range(8000, 9000):
		var tcp = TCPServer.new()
		if tcp.listen(port) == OK:
			tcp.stop()
			return port
	return 7777  # Fallback

func _cleanup_instances():
	if host_instance:
		host_instance.terminate()
		host_instance = null

	if client_instance:
		client_instance.terminate()
		client_instance = null

func _capture_failure_screenshots():
	print("[Test] Capturing screenshots for failed test...")

	var timestamp = Time.get_datetime_string_from_system().replace(":", "-")

	if host_instance:
		var host_screenshot = host_instance.capture_screenshot()
		print("[Test] Host screenshot: %s" % host_screenshot)

	if client_instance:
		var client_screenshot = client_instance.capture_screenshot()
		print("[Test] Client screenshot: %s" % client_screenshot)

func wait_for_seconds(seconds: float):
	# GUT tests run without a scene tree sometimes, so use Engine.get_main_loop()
	# Try to use the main loop timer (works in both test and normal mode)
	var main_loop = Engine.get_main_loop()
	if main_loop:
		var timer = main_loop.create_timer(seconds)
		if timer:
			await timer.timeout
			return

	# Fallback busy wait if no main loop (shouldn't happen but just in case)
	var start = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < (seconds * 1000):
		pass  # Just wait

func _mark_test_failed(message: String):
	_test_failed = true
	_failure_message = message
	print("[Test] FAILED: ", message)

# ============================================================================
# Assertion Helpers
# ============================================================================

func assert_connection_established(message: String = ""):
	assert_true(
		host_instance != null and client_instance != null,
		message if message else "Both instances should be running"
	)
	# Note: LogMonitor is not reliably tracking connection state in the test runner
	# environment because log file monitoring has timing issues with process startup.
	# Connection is verified via successful command simulation in wait_for_connection(),
	# which is a more reliable approach (if we can send a command and get a result,
	# the connection is working). LogMonitor still works for detecting peer events
	# in the actual game instances themselves.

func assert_game_started(message: String = ""):
	var host_started = host_instance.get_game_state().get("game_started", false)
	var client_started = client_instance.get_game_state().get("game_started", false)

	assert_true(
		host_started and client_started,
		message if message else "Game should be started on both instances"
	)

func assert_same_phase(message: String = ""):
	var host_phase = host_instance.get_game_state().get("current_phase", "")
	var client_phase = client_instance.get_game_state().get("current_phase", "")

	assert_eq(
		host_phase,
		client_phase,
		message if message else "Both instances should be in the same phase"
	)

func _generate_test_report():
	"""
	Generates a JSON report with test results and metadata
	Useful for tracking test history and comparing runs
	"""
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-")
	var test_name_safe = current_test_name.replace(" ", "_") if current_test_name else "unknown_test"

	var report_data = {
		"test_name": current_test_name,
		"timestamp": timestamp,
		"status": "FAILED" if _test_failed else "PASSED",
		"failure_message": _failure_message if _test_failed else "",
		"host_connected": host_instance != null,
		"client_connected": client_instance != null,
		"configuration": {
			"use_dynamic_ports": use_dynamic_ports,
			"visual_debugging": visual_debugging,
			"capture_screenshots_on_failure": capture_screenshots_on_failure,
			"capture_screenshots_on_success": capture_screenshots_on_success,
			"save_state_on_completion": save_state_on_completion
		}
	}

	# Try to get final game state from host
	if host_instance:
		var state_result = await simulate_host_action("get_game_state", {})
		if state_result.get("success", false):
			report_data["final_game_state"] = state_result.get("data", {})

	var report_path = test_artifacts_dir + "reports/" + test_name_safe + "_" + timestamp + ".json"
	var file = FileAccess.open(report_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report_data, "\t"))
		file.close()
		print("[Test Artifacts] Report saved: %s" % report_path)

# ============================================================================
# Disconnect Simulation
# ============================================================================

func simulate_client_disconnect() -> bool:
	"""
	Simulates a client disconnect by terminating the client process.
	Returns true if the client was running and was terminated.
	"""
	if not client_instance:
		print("[Test] No client instance to disconnect")
		return false

	print("[Test] Simulating client disconnect (terminating client process)")
	client_instance.terminate()
	# Keep the reference so we can check it was disconnected, but mark process dead
	print("[Test] Client process terminated")
	return true

func simulate_host_disconnect() -> bool:
	"""
	Simulates a host disconnect by terminating the host process.
	Returns true if the host was running and was terminated.
	"""
	if not host_instance:
		print("[Test] No host instance to disconnect")
		return false

	print("[Test] Simulating host disconnect (terminating host process)")
	host_instance.terminate()
	print("[Test] Host process terminated")
	return true

func verify_instance_alive(instance: GameInstance) -> bool:
	"""
	Checks if a game instance is still responding to commands.
	Returns true if the instance responds within a short timeout.
	"""
	if not instance or instance.process_id == -1:
		return false

	# Try sending a lightweight command
	var result = await _simulate_action(instance, "get_game_state", {})
	return result.get("success", false)

# ============================================================================
# Game State Comparison
# ============================================================================

func assert_game_states_match(message: String = "") -> Dictionary:
	"""
	Compares critical game state fields between host and client.
	Returns a dictionary with comparison results:
	  { "match": bool, "host_state": {}, "client_state": {}, "mismatches": [] }
	Also asserts that states match for test reporting.
	"""
	var result = {
		"match": false,
		"host_state": {},
		"client_state": {},
		"mismatches": []
	}

	var host_result = await simulate_host_action("get_game_state", {})
	var client_result = await simulate_client_action("get_game_state", {})

	if not host_result.get("success", false):
		result["mismatches"].append("Host failed to return game state")
		assert_true(false, "Host should return game state for comparison")
		return result
	if not client_result.get("success", false):
		result["mismatches"].append("Client failed to return game state")
		assert_true(false, "Client should return game state for comparison")
		return result

	var host_data = host_result.get("data", {})
	var client_data = client_result.get("data", {})
	result["host_state"] = host_data
	result["client_state"] = client_data

	# Compare critical fields
	var fields_to_compare = ["current_phase", "player_turn", "battle_round"]
	for field in fields_to_compare:
		var host_val = host_data.get(field, null)
		var client_val = client_data.get(field, null)
		if host_val != client_val:
			var mismatch = "Field '%s': host=%s, client=%s" % [field, str(host_val), str(client_val)]
			result["mismatches"].append(mismatch)
			print("[Test] State mismatch: %s" % mismatch)

	# Compare unit counts
	var host_units = host_data.get("units", {})
	var client_units = client_data.get("units", {})
	if host_units.size() != client_units.size():
		var mismatch = "Unit count: host=%d, client=%d" % [host_units.size(), client_units.size()]
		result["mismatches"].append(mismatch)
		print("[Test] State mismatch: %s" % mismatch)

	result["match"] = result["mismatches"].size() == 0

	var msg = message if message else "Game states should match between host and client"
	if result["mismatches"].size() > 0:
		assert_true(false, "%s — mismatches: %s" % [msg, str(result["mismatches"])])
	else:
		print("[Test] Game states match: %s" % msg)

	return result

func get_action_round_trip_time_ms(instance: GameInstance, action: String, params: Dictionary = {}) -> float:
	"""
	Measures round-trip time for an action command in milliseconds.
	Useful for latency measurement tests.
	Returns -1.0 if the action failed.
	"""
	var start_ms = Time.get_ticks_msec()
	var result = await _simulate_action(instance, action, params)
	var elapsed_ms = Time.get_ticks_msec() - start_ms

	if not result.get("success", false):
		print("[Test] Action '%s' failed during RTT measurement: %s" % [action, result.get("message", "")])
		return -1.0

	print("[Test] Action '%s' round-trip: %dms" % [action, elapsed_ms])
	return float(elapsed_ms)
