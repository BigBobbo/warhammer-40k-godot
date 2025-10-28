extends GutTest
class_name MultiplayerIntegrationTest

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
var connection_timeout: float = 15.0
var sync_timeout: float = 10.0

func before_each():
	print("\n========================================")
	print("Starting Multiplayer Integration Test")
	print("========================================\n")

	# Ensure test directories exist
	_ensure_test_directories()

	# Clean up any existing instances
	_cleanup_instances()

func after_each():
	print("\n========================================")
	print("Cleaning up Multiplayer Test")
	print("========================================\n")

	# Capture screenshots if test failed
	if _test_failed and capture_screenshots_on_failure:
		_capture_failure_screenshots()

	# Clean up instances
	_cleanup_instances()

	# Reset test state
	_test_failed = false
	_failure_message = ""

func _ensure_test_directories():
	var dir = DirAccess.open("res://")
	if not dir.dir_exists("tests"):
		dir.make_dir("tests")
	if not dir.dir_exists("tests/saves"):
		dir.make_dir("tests/saves")

	dir = DirAccess.open("user://")
	if not dir.dir_exists("test_screenshots"):
		dir.make_dir("test_screenshots")

# ============================================================================
# Instance Management
# ============================================================================

func launch_host_and_client() -> bool:
	print("[Test] Launching host and client instances...")

	# Determine ports
	var host_port = 7777
	var client_port = -1  # Let GameInstance handle it

	if use_dynamic_ports:
		host_port = _get_available_port()

	# Launch host
	host_instance = GameInstance.new("Host", true, host_port)
	if not await host_instance.launch():
		_mark_test_failed("Failed to launch host instance")
		assert_true(false, "Failed to launch host instance")
		return false

	print("[Test] Host instance launched successfully")

	# Wait a moment for host to initialize
	await wait_for_seconds(3.0)

	# Launch client
	client_instance = GameInstance.new("Client", false, client_port)
	if not await client_instance.launch():
		_mark_test_failed("Failed to launch client instance")
		assert_true(false, "Failed to launch client instance")
		return false

	print("[Test] Client instance launched successfully")
	return true

func wait_for_connection() -> bool:
	print("[Test] Waiting for client to connect to host...")

	var start_time = Time.get_ticks_msec() / 1000.0

	# Monitor both instances for connection
	while (Time.get_ticks_msec() / 1000.0) - start_time < connection_timeout:
		# Check host for incoming connection
		if host_instance.log_monitor.connected_peers.size() > 0:
			print("[Test] Host detected client connection!")

			# Verify client also shows connected
			if client_instance.log_monitor.is_connected:
				print("[Test] Client confirmed connection!")
				return true

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

func simulate_host_action(action: String) -> bool:
	print("[Test] Host performing action: %s" % action)
	# Would send action command to host instance
	return true

func simulate_client_action(action: String) -> bool:
	print("[Test] Client performing action: %s" % action)
	# Would send action command to client instance
	return true

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
	await get_tree().create_timer(seconds).timeout

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
	assert_true(
		host_instance.log_monitor.connected_peers.size() > 0,
		message if message else "Host should have connected peers"
	)
	assert_true(
		client_instance.log_monitor.is_connected,
		message if message else "Client should be connected"
	)

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