extends RefCounted
class_name LogMonitor

# Monitors Godot debug log files for multiplayer events
# Parses log output to detect connections, game state changes, and errors

var log_file_path: String = ""
var _file: FileAccess
var _last_position: int = 0
var _monitoring: bool = false
var _monitor_timer: Timer

# Connection state
var is_connected: bool = false
var connected_peers: Array[int] = []
var current_game_state: Dictionary = {}

# Signals for test synchronization
signal connection_detected(peer_id: int, connected: bool)
signal game_state_changed(state: Dictionary)
signal error_detected(error_msg: String)
signal phase_changed(phase_name: String)
signal action_logged(action: String)

# Log patterns to watch for (updated to match actual NetworkManager output)
const PATTERNS = {
	"peer_connected": "NetworkManager: Peer connected - (\\d+)",
	"peer_disconnected": "NetworkManager: Peer disconnected - (\\d+)",
	"host_created": "YOU ARE: PLAYER 1 \\(HOST\\)",
	"client_connected": "YOU ARE: PLAYER 2 \\(CLIENT\\)|TestModeHandler: Client connected",
	"game_started": "Game started|GAME_STARTED",
	"save_loaded": "Save loaded: (.+)",
	"phase_started": "Phase started: (.+)",
	"error": "ERROR: (.+)",
	"warning": "WARNING: (.+)",
	"network_sync": "NetworkManager: Syncing (.+)",
	"action": "ActionLogger: (.+)"
}

func start_monitoring(file_path: String) -> bool:
	log_file_path = file_path

	# Open file for reading
	_file = FileAccess.open(log_file_path, FileAccess.READ)
	if not _file:
		push_error("[LogMonitor] Failed to open log file: %s" % log_file_path)
		return false

	# Start at end of file to avoid old logs
	_file.seek_end()
	_last_position = _file.get_position()

	_monitoring = true

	# Set up polling timer
	_setup_monitor_timer()

	print("[LogMonitor] Started monitoring: %s" % log_file_path)
	return true

func _setup_monitor_timer():
	# Poll log file every 100ms for new content
	_monitor_timer = Timer.new()
	_monitor_timer.wait_time = 0.1
	_monitor_timer.timeout.connect(_check_for_updates)
	_monitor_timer.autostart = true

	# Add to scene tree to make timer work
	if Engine.get_main_loop():
		Engine.get_main_loop().root.add_child(_monitor_timer)

func stop_monitoring():
	_monitoring = false

	if _monitor_timer:
		_monitor_timer.stop()
		_monitor_timer.queue_free()
		_monitor_timer = null

	if _file:
		_file.close()
		_file = null

	print("[LogMonitor] Stopped monitoring: %s" % log_file_path)

func _check_for_updates():
	if not _monitoring or not _file:
		return

	# Reopen file to get latest content
	_file = FileAccess.open(log_file_path, FileAccess.READ)
	if not _file:
		return

	_file.seek(_last_position)

	# Read new lines
	while not _file.eof_reached():
		var line = _file.get_line()
		if not line.is_empty():
			_parse_log_line(line)

	_last_position = _file.get_position()
	_file.close()

func _parse_log_line(line: String):
	# Check for peer connection
	var regex = RegEx.new()

	# Peer connected
	regex.compile(PATTERNS["peer_connected"])
	var result = regex.search(line)
	if result:
		var peer_id = result.get_string(1).to_int()
		connected_peers.append(peer_id)
		is_connected = true
		connection_detected.emit(peer_id, true)
		print("[LogMonitor] Detected peer connection: %d" % peer_id)
		return

	# Peer disconnected
	regex.compile(PATTERNS["peer_disconnected"])
	result = regex.search(line)
	if result:
		var peer_id = result.get_string(1).to_int()
		connected_peers.erase(peer_id)
		is_connected = connected_peers.size() > 0
		connection_detected.emit(peer_id, false)
		print("[LogMonitor] Detected peer disconnection: %d" % peer_id)
		return

	# Host created
	if line.contains("YOU ARE: PLAYER 1 (HOST)"):
		current_game_state["is_host"] = true
		current_game_state["player_number"] = 1
		game_state_changed.emit(current_game_state)
		print("[LogMonitor] Detected host creation")
		return

	# Client connected
	if line.contains("YOU ARE: PLAYER 2 (CLIENT)"):
		current_game_state["is_host"] = false
		current_game_state["player_number"] = 2
		is_connected = true
		game_state_changed.emit(current_game_state)
		print("[LogMonitor] Detected client connection")
		return

	# Game started
	if line.contains("Game started") or line.contains("GAME_STARTED"):
		current_game_state["game_started"] = true
		game_state_changed.emit(current_game_state)
		print("[LogMonitor] Detected game start")
		return

	# Save loaded
	regex.compile(PATTERNS["save_loaded"])
	result = regex.search(line)
	if result:
		var save_name = result.get_string(1)
		current_game_state["current_save"] = save_name
		game_state_changed.emit(current_game_state)
		print("[LogMonitor] Detected save load: %s" % save_name)
		return

	# Phase changes
	regex.compile(PATTERNS["phase_started"])
	result = regex.search(line)
	if result:
		var phase_name = result.get_string(1)
		current_game_state["current_phase"] = phase_name
		phase_changed.emit(phase_name)
		print("[LogMonitor] Detected phase change: %s" % phase_name)
		return

	# Action logging
	if line.contains("ActionLogger:"):
		regex.compile(PATTERNS["action"])
		result = regex.search(line)
		if result:
			var action = result.get_string(1)
			action_logged.emit(action)
			return

	# Errors
	if line.contains("ERROR:"):
		regex.compile(PATTERNS["error"])
		result = regex.search(line)
		if result:
			var error_msg = result.get_string(1)
			error_detected.emit(error_msg)
			push_error("[LogMonitor] Error in game log: %s" % error_msg)
			return

func wait_for_pattern(pattern: String, timeout: float = 10.0) -> bool:
	# Wait for specific pattern to appear in logs
	var start = Time.get_ticks_msec() / 1000.0
	var regex = RegEx.new()
	regex.compile(pattern)

	while (Time.get_ticks_msec() / 1000.0) - start < timeout:
		# Check recent log entries
		_check_for_updates()

		# Would need to track recent lines to check pattern
		# For now, return based on connection state
		if pattern.contains("connect") and is_connected:
			return true

		await Engine.get_main_loop().create_timer(0.5).timeout

	return false

func get_recent_errors(count: int = 10) -> Array[String]:
	# Return recent error messages from log
	# Would track these during monitoring
	return []