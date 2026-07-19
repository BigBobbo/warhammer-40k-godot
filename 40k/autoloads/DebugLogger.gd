extends Node

# DebugLogger - Custom logging system that writes to both console and file
# Purpose: Allow Claude to read debug output directly from log files
# Usage: Logger.info("message"), Logger.warn("message"), Logger.error("message")

signal log_written(level: String, message: String)

# Configuration
var enabled: bool = true
var log_to_file: bool = true
var log_to_console: bool = true
var min_log_level: LogLevel = LogLevel.DEBUG

# Log levels
enum LogLevel {
	DEBUG = 0,
	INFO = 1,
	WARNING = 2,
	ERROR = 3
}

# File management
var log_file_path: String = ""
var session_id: String = ""
# MEM-7: on web, user:// is a RAM-backed filesystem (MEMFS synced to
# IndexedDB) — every log byte is tab memory, and old sessions' files are
# mounted back into RAM on the next visit. Keep the same logging calls but
# bound the bytes: 5 MB rolling file on web, 50 MB on desktop.
var max_log_size: int = (5 * 1024 * 1024) if OS.has_feature("web") else (50 * 1024 * 1024)
var current_log_size: int = 0
var _is_rotating: bool = false
# MEM-7: how many previous sessions' debug_*.log files to keep at startup.
var _max_old_log_files: int = 1 if OS.has_feature("web") else 3

# Performance optimization
var log_buffer: Array[String] = []
var buffer_size: int = 20  # Write every 20 messages
var auto_flush_timer: Timer = null

func _ready() -> void:
	_initialize_logger()
	_setup_auto_flush()

func _initialize_logger() -> void:
	# Generate session ID
	session_id = _generate_session_id()

	# Create logs directory
	var logs_dir = "user://logs/"
	DirAccess.open("user://").make_dir_recursive("logs")

	# MEM-7: prune previous sessions' log files BEFORE creating this session's —
	# they were never deleted, so on web they accumulated in IndexedDB and were
	# mounted back into tab RAM on every later visit.
	_prune_old_logs(logs_dir)

	# Set up log file path
	log_file_path = logs_dir + "debug_%s.log" % session_id

	# Write header
	_write_log_header()

	info("DebugLogger initialized - Session: %s" % session_id)
	info("Log file: %s" % log_file_path)
	info("Real path: %s" % ProjectSettings.globalize_path(log_file_path))

func _generate_session_id() -> String:
	var time = Time.get_datetime_dict_from_system()
	return "%04d%02d%02d_%02d%02d%02d" % [
		time.year, time.month, time.day,
		time.hour, time.minute, time.second
	]

func _write_log_header() -> void:
	var time = Time.get_datetime_dict_from_system()
	var header = """
================================================================================
DEBUG LOG SESSION
================================================================================
Session ID: %s
Start Time: %04d-%02d-%02d %02d:%02d:%02d
Project: Warhammer 40k Game
Godot Version: %s
Platform: %s
================================================================================

""" % [
		session_id,
		time.year, time.month, time.day,
		time.hour, time.minute, time.second,
		Engine.get_version_info().string,
		OS.get_name()
	]

	_write_to_file_immediate(header)

func _setup_auto_flush() -> void:
	auto_flush_timer = Timer.new()
	auto_flush_timer.wait_time = 5.0  # Flush every 5 seconds
	auto_flush_timer.timeout.connect(_flush_buffer)
	auto_flush_timer.autostart = true
	add_child(auto_flush_timer)

# Public API - Main logging functions
func debug(message: String, context: Dictionary = {}) -> void:
	_log(LogLevel.DEBUG, message, context)

func info(message: String, context: Dictionary = {}) -> void:
	_log(LogLevel.INFO, message, context)

func warn(message: String, context: Dictionary = {}) -> void:
	_log(LogLevel.WARNING, message, context)

func error(message: String, context: Dictionary = {}) -> void:
	_log(LogLevel.ERROR, message, context)

# Core logging function
func _log(level: LogLevel, message: String, context: Dictionary = {}) -> void:
	if not enabled:
		return

	if level < min_log_level:
		return

	# Format log entry
	var log_entry = _format_log_entry(level, message, context)

	# Output to console
	if log_to_console:
		_output_to_console(level, log_entry)

	# Buffer for file output
	if log_to_file:
		log_buffer.append(log_entry)

		# Flush if buffer is full
		if log_buffer.size() >= buffer_size:
			_flush_buffer()

	# Emit signal
	emit_signal("log_written", _level_to_string(level), message)

func _format_log_entry(level: LogLevel, message: String, context: Dictionary) -> String:
	var timestamp = _get_timestamp()
	var level_str = _level_to_string(level).to_upper().pad_decimals(7)

	var entry = "[%s] [%s] %s" % [timestamp, level_str, message]

	# Add context if provided
	if not context.is_empty():
		entry += " | Context: %s" % JSON.stringify(context)

	return entry

func _get_timestamp() -> String:
	var time = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		time.year, time.month, time.day,
		time.hour, time.minute, time.second
	]

func _level_to_string(level: LogLevel) -> String:
	match level:
		LogLevel.DEBUG: return "DEBUG"
		LogLevel.INFO: return "INFO"
		LogLevel.WARNING: return "WARNING"
		LogLevel.ERROR: return "ERROR"
		_: return "UNKNOWN"

func _output_to_console(level: LogLevel, message: String) -> void:
	match level:
		LogLevel.DEBUG, LogLevel.INFO:
			print(message)
		LogLevel.WARNING:
			push_warning(message)
		LogLevel.ERROR:
			push_error(message)

# File operations
func _flush_buffer() -> void:
	if log_buffer.is_empty():
		return

	var content = "\n".join(log_buffer) + "\n"
	_write_to_file_immediate(content)

	log_buffer.clear()

func _write_to_file_immediate(content: String) -> void:
	if _is_rotating:
		return
	if current_log_size > max_log_size:
		_rotate_log()

	# Check if file exists, use appropriate mode
	var file_exists = FileAccess.file_exists(log_file_path)
	var mode = FileAccess.READ_WRITE if file_exists else FileAccess.WRITE

	var file = FileAccess.open(log_file_path, mode)
	if file:
		if file_exists:
			file.seek_end()
		file.store_string(content)
		current_log_size = file.get_length()
		file = null  # Close file
	else:
		push_error("DebugLogger: Failed to open log file: " + log_file_path)

func _rotate_log() -> void:
	# MEM-7: rotate by RENAMING the file instead of reading it back into a
	# String. The old implementation did get_as_text() on the full log — at the
	# 50 MB cap that was a ~200 MB transient String (4 bytes/char), enough to
	# OOM a WASM heap on its own — and then wrote a second full copy.
	_is_rotating = true
	var archived_path = log_file_path.replace(".log", "_archived.log")

	var dir = DirAccess.open("user://logs/")
	if dir:
		if dir.file_exists(archived_path.get_file()):
			dir.remove(archived_path.get_file())
		var err = dir.rename(log_file_path.get_file(), archived_path.get_file())
		if err != OK:
			# Rename failed (shouldn't happen on any supported FS) — fall back
			# to plain truncation so the live log stays bounded regardless.
			var truncated = FileAccess.open(log_file_path, FileAccess.WRITE)
			if truncated:
				truncated = null
	current_log_size = 0
	log_buffer.clear()
	_is_rotating = false
	_write_log_header()
	print("Log rotated - Previous log archived to: %s" % archived_path)

# MEM-7: delete log files from previous sessions beyond the newest N
# (debug_*.log including *_archived.log). Never touches the file that is about
# to be created for the current session (session_id is unique per boot).
func _prune_old_logs(logs_dir: String) -> void:
	var dir = DirAccess.open(logs_dir)
	if dir == null:
		return
	var candidates: Array = []
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.begins_with("debug_") and fname.ends_with(".log"):
			candidates.append({
				"name": fname,
				"mtime": FileAccess.get_modified_time(logs_dir + fname)
			})
		fname = dir.get_next()
	dir.list_dir_end()
	if candidates.size() <= _max_old_log_files:
		return
	candidates.sort_custom(func(a, b): return a["mtime"] > b["mtime"])  # newest first
	for i in range(_max_old_log_files, candidates.size()):
		dir.remove(candidates[i]["name"])

# Utility functions
func get_log_file_path() -> String:
	return log_file_path

func get_real_log_file_path() -> String:
	return ProjectSettings.globalize_path(log_file_path)

func print_log_location() -> void:
	print("Debug log location: %s" % get_real_log_file_path())

func set_log_level(level: LogLevel) -> void:
	min_log_level = level
	info("Log level changed to: %s" % _level_to_string(level))

func set_enabled(enable: bool) -> void:
	enabled = enable
	if enabled:
		info("DebugLogger enabled")
	else:
		print("DebugLogger disabled")

func open_log_directory() -> void:
	var path = ProjectSettings.globalize_path("user://logs/")
	OS.shell_open(path)

# Cleanup
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_flush_buffer()
		info("DebugLogger shutting down - Session: %s" % session_id)
		# Final flush
		var separator = "=" .repeat(80)
		_write_to_file_immediate("\n" + separator + "\n" + "SESSION END: %s\n" % _get_timestamp() + separator + "\n")
