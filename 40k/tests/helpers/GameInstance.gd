extends RefCounted
class_name GameInstance

const LogMonitor = preload("res://tests/helpers/LogMonitor.gd")

# Manages a single Godot game instance for multiplayer testing
# Handles process launching, log monitoring, and window positioning

var process_id: int = -1
var instance_name: String = ""
var port: int = 7777
var host_port: int = 7777  # Port the host is listening on (for client to connect to)
var log_file_path: String = ""
var log_monitor: LogMonitor
var window_position: Vector2i
var is_host: bool = false
var save_file: String = ""  # Optional save file to auto-load
var user_home_path: String = ""

# Process management
var _process: int = -1
var _start_time: float = 0.0

# Command simulation
var _command_sequence: int = 0

signal instance_ready()
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal game_started()
signal save_loaded(save_name: String)
signal connection_established()

func _init(name: String, host: bool = false, custom_port: int = -1, auto_load_save: String = "", connect_to_port: int = 7777):
	instance_name = name
	is_host = host
	save_file = auto_load_save
	host_port = connect_to_port  # Port to connect to (for clients)

	# Dynamic port allocation if not specified
	if custom_port > 0:
		port = custom_port
	elif not is_host:
		port = 7778  # Client uses different port for local testing

	# Set window position based on role (side by side for visual debugging)
	if is_host:
		window_position = Vector2i(100, 100)
	else:
		window_position = Vector2i(800, 100)

	# Record current user data directory for log monitoring
	user_home_path = OS.get_user_data_dir()

	# Initialize log monitor
	log_monitor = LogMonitor.new()
	log_monitor.connection_detected.connect(_on_connection_detected)
	log_monitor.game_state_changed.connect(_on_game_state_changed)

func launch() -> bool:
	print("[GameInstance] Launching %s instance on port %d" % [instance_name, port])

	# Prepare command line arguments
	var args = PackedStringArray()

	# IMPORTANT: Add project path first - this must come before other arguments
	# Get the project root directory (where project.godot is located)
	var project_path = ProjectSettings.globalize_path("res://")
	args.append("--path")
	args.append(project_path)
	print("[GameInstance] Using project path: %s" % project_path)

	# Add test mode flag
	args.append("--test-mode")

	# Set window position and size for visual debugging
	args.append("--position=%d,%d" % [window_position.x, window_position.y])
	args.append("--resolution=600x480")

	# Set instance role
	if is_host:
		args.append("--auto-host")
		args.append("--port=%d" % port)
	else:
		args.append("--auto-join")
		args.append("--host-ip=127.0.0.1")
		args.append("--host-port=%d" % host_port)  # Connect to the actual host port

	# Add instance identifier for logging
	args.append("--instance-name=%s" % instance_name)

	# Add save file if specified
	if save_file != "":
		args.append("--auto-load-save=%s" % save_file)
		print("[GameInstance] Auto-loading save file: %s" % save_file)

	# Get godot executable path
	var godot_path = OS.get_executable_path()
	if godot_path.is_empty():
		godot_path = "$HOME/bin/godot"  # Fallback to your standard location

	# Launch the process
	_start_time = Time.get_ticks_msec() / 1000.0
	_process = OS.create_process(godot_path, args)

	if _process == -1:
		push_error("[GameInstance] Failed to launch Godot instance: %s" % instance_name)
		return false

	process_id = _process

	# Start monitoring logs after a short delay
	await _wait_for_seconds(2.0)
	_setup_log_monitoring()

	print("[GameInstance] Successfully launched %s (PID: %d)" % [instance_name, process_id])
	return true

func _setup_log_monitoring():
	# Determine log file path based on instance start time
	var log_dir = user_home_path + "/logs"

	# Find the most recent log file created after our start time
	var dir = DirAccess.open(log_dir)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		var newest_file = ""
		var newest_time = 0

		while file_name != "":
			if file_name.begins_with("debug_") and file_name.ends_with(".log"):
				var full_path = log_dir + "/" + file_name
				var file = FileAccess.open(full_path, FileAccess.READ)
				if file:
					var modified_time = file.get_modified_time(full_path)
					if modified_time > _start_time and modified_time > newest_time:
						newest_time = modified_time
						newest_file = full_path
					file.close()
			file_name = dir.get_next()

		if not newest_file.is_empty():
			log_file_path = newest_file
			log_monitor.start_monitoring(log_file_path)
			print("[GameInstance] Monitoring log file: %s" % log_file_path)
		else:
			push_warning("[GameInstance] No log file found for instance: %s" % instance_name)

func click_button(button_text: String) -> bool:
	# Send button click command via IPC or automation
	# For MVP, we'll use the auto-host/auto-join flags instead
	print("[GameInstance] Would click button: %s" % button_text)
	return true

func load_save(save_name: String) -> bool:
	# Trigger save loading via command
	print("[GameInstance] Loading save: %s" % save_name)
	# This would be implemented via IPC or file watching
	save_loaded.emit(save_name)
	return true

func wait_for_connection(timeout: float = 10.0) -> bool:
	print("[GameInstance] Waiting for connection (timeout: %.1fs)" % timeout)

	var start = Time.get_ticks_msec() / 1000.0
	while (Time.get_ticks_msec() / 1000.0) - start < timeout:
		if log_monitor.is_connected:
			connection_established.emit()
			return true
		await _wait_for_seconds(0.5)

	push_error("[GameInstance] Connection timeout for instance: %s" % instance_name)
	return false

func get_game_state() -> Dictionary:
	# Parse current game state from logs or IPC
	return log_monitor.current_game_state

func capture_screenshot() -> String:
	# Capture screenshot of this instance's window
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-")
	var screenshot_path = "user://test_screenshots/%s_%s.png" % [instance_name, timestamp]

	# This would use OS-specific window capture
	# For now, return the path where it would be saved
	print("[GameInstance] Screenshot would be saved to: %s" % screenshot_path)
	return screenshot_path

func terminate():
	print("[GameInstance] Terminating instance: %s" % instance_name)

	if log_monitor:
		log_monitor.stop_monitoring()

	if _process != -1:
		OS.kill(_process)
		_process = -1

	process_id = -1

func _wait_for_seconds(seconds: float):
	var main_loop = Engine.get_main_loop()
	if main_loop:
		var timer = main_loop.create_timer(seconds)
		if timer:
			await timer.timeout
		else:
			# Fallback busy wait if timer creation fails
			var start = Time.get_ticks_msec()
			while Time.get_ticks_msec() - start < (seconds * 1000):
				pass
	else:
		# Fallback busy wait if no main loop
		var start = Time.get_ticks_msec()
		while Time.get_ticks_msec() - start < (seconds * 1000):
			pass

func _on_connection_detected(peer_id: int, connected: bool):
	if connected:
		peer_connected.emit(peer_id)
	else:
		peer_disconnected.emit(peer_id)

func _on_game_state_changed(state: Dictionary):
	if state.has("game_started") and state["game_started"]:
		game_started.emit()

func get_next_sequence() -> int:
	_command_sequence += 1
	return _command_sequence
