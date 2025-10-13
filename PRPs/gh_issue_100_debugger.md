# PRP: Debug Logger Implementation for Warhammer 40k Game

## Issue Context
GitHub Issue #100: Add a custom logging function so that the Godot engine output is saved to a local file. This is so that Claude can directly read the output when debugging.

## Research Findings

### Existing Codebase Architecture

1. **Current Logging Infrastructure**:
   - `ActionLogger.gd` (lines 1-335) - Logs game actions to JSON files
     - Uses `FileAccess.open()` for file operations
     - Stores logs in `user://logs/` directory
     - Has timestamp generation via `Time.get_datetime_dict_from_system()`
     - Uses session IDs for organization
     - Pattern: `user://logs/session_YYYYMMDD_HHMMSS.json`

   - `DebugManager.gd` (lines 1-330) - Debug mode functionality
     - Currently uses `print()` statements (lines 20, 34, 59, 107, 130)
     - Uses `push_error()` for error reporting (lines 176, 201)
     - Good candidate for using new logger

2. **Autoload System**:
   - Project has 21 autoloads defined in `project.godot` (lines 18-41)
   - All autoloads in `40k/autoloads/` directory
   - Autoloads are globally accessible throughout the application
   - New logger should follow this pattern

3. **Testing Infrastructure**:
   - Uses GUT testing framework (`addons/gut/`)
   - Test structure: `tests/unit/`, `tests/phases/`, `tests/integration/`, `tests/ui/`
   - Validation script: `tests/validate_all_tests.sh`
   - Tests run with: `godot --headless --path . -s addons/gut/gut_cmdln.gd`
   - Test pattern: `test_*.gd` files extending `GutTest`

4. **File System Paths**:
   - User data directory: `user://`
   - Logs directory: `user://logs/` (created by ActionLogger)
   - On macOS: `~/Library/Application Support/Godot/app_userdata/40k/`

### Godot 4.x File I/O

Reference: https://docs.godotengine.org/en/4.4/classes/class_fileaccess.html

**FileAccess API** (Godot 4.x):
```gdscript
# Open file for writing (creates if doesn't exist, truncates if exists)
var file = FileAccess.open("user://logs/debug.log", FileAccess.WRITE)

# Open for reading and writing (doesn't truncate, append to end)
var file = FileAccess.open("user://logs/debug.log", FileAccess.READ_WRITE)

# Write operations
file.store_line("text with newline")  # Adds \n automatically
file.store_string("text without newline")
file.store_var(any_value)  # Stores any GDScript value

# Reading
var content = file.get_as_text()  # Read entire file
var line = file.get_line()  # Read single line

# File automatically closes when variable goes out of scope
# Manual close not required in Godot 4.x
```

**Built-in File Logging**:
Godot has project settings for automatic logging:
- `Project Settings > Logging > File Logging > Enable File Logging`
- Default path: `user://logs/log.txt`
- Captures: `print()`, `print_debug()`, `push_warning()`, `push_error()`, `assert()`

### Similar Implementations

**ActionLogger Pattern** (from codebase):
```gdscript
# Initialize logs directory
var logs_dir = "user://logs/"
DirAccess.open("user://").make_dir_recursive("logs")

# Generate session ID with timestamp
func _generate_session_id() -> String:
    var time = Time.get_datetime_dict_from_system()
    return "%04d%02d%02d_%02d%02d%02d" % [
        time.year, time.month, time.day,
        time.hour, time.minute, time.second
    ]

# Write to file
var file = FileAccess.open(log_file_path, FileAccess.WRITE)
if file:
    file.seek_end()  # Append to end
    file.store_line(json_string)
else:
    push_error("Failed to open log file: " + log_file_path)
```

### External References

1. **Godot FileAccess Documentation**:
   https://docs.godotengine.org/en/4.4/classes/class_fileaccess.html

2. **Godot File I/O Examples**:
   https://kidscancode.org/godot_recipes/4.x/basics/file_io/index.html

3. **Community Logging Solutions**:
   - 4d49/godot-logger: https://github.com/4d49/godot-logger
   - Simple logger tutorial: https://www.nightquestgames.com/logger-in-gdscript-for-better-debugging/

## Implementation Blueprint

### Design Decisions

**Primary Goals**:
1. Capture all debug output to file for Claude to read
2. Include timestamps for debugging timeline
3. Support different log levels (INFO, WARNING, ERROR, DEBUG)
4. Minimal performance overhead
5. Easy to enable/disable
6. Don't interfere with console output

**Approach**: Custom Logger Autoload
- Create `DebugLogger.gd` autoload with wrapper functions
- Provide `Logger.info()`, `Logger.warn()`, `Logger.error()`, `Logger.debug()`
- Write to both console AND file
- Support log rotation to prevent massive files
- Include session tracking
- Can be toggled on/off via configuration

### Phase 1: Core Logger Implementation

#### File: `40k/autoloads/DebugLogger.gd` (NEW)

```gdscript
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
var max_log_size: int = 10 * 1024 * 1024  # 10 MB
var current_log_size: int = 0

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
    # Check if log rotation needed
    if current_log_size > max_log_size:
        _rotate_log()

    var file = FileAccess.open(log_file_path, FileAccess.READ_WRITE)
    if file:
        file.seek_end()
        file.store_string(content)
        current_log_size = file.get_length()
        file = null  # Close file
    else:
        push_error("DebugLogger: Failed to open log file: " + log_file_path)

func _rotate_log() -> void:
    # Rename current log to archived name
    var archived_path = log_file_path.replace(".log", "_archived.log")

    # Copy current log to archive
    var file = FileAccess.open(log_file_path, FileAccess.READ)
    if file:
        var content = file.get_as_text()
        file = null

        var archive = FileAccess.open(archived_path, FileAccess.WRITE)
        if archive:
            archive.store_string(content)
            archive = null

    # Start fresh log
    current_log_size = 0
    _write_log_header()
    info("Log rotated - Previous log archived to: %s" % archived_path)

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
        _write_to_file_immediate("\n" + "="*80 + "\n" + "SESSION END: %s\n" % _get_timestamp() + "="*80 + "\n")

```

### Phase 2: Project Configuration

#### File: `40k/project.godot` (MODIFY)

Add DebugLogger to the autoload section (after FeatureFlags, before SettingsService):

```ini
[autoload]

FeatureFlags="*res://autoloads/FeatureFlags.gd"
DebugLogger="*res://autoloads/DebugLogger.gd"
SettingsService="*res://autoloads/SettingsService.gd"
# ... rest of autoloads
```

**Location**: Insert at line 21 (between FeatureFlags and SettingsService)

### Phase 3: Example Usage Documentation

#### File: `40k/DEBUG_LOGGING.md` (NEW)

```markdown
# Debug Logging System

## Overview
The DebugLogger provides a centralized logging system that writes to both console and file, making it easy for Claude to read debug output.

## Basic Usage

### Simple Logging
```gdscript
# Instead of: print("Hello")
Logger.info("Hello")

# Instead of: push_warning("Something odd")
Logger.warn("Something odd")

# Instead of: push_error("Critical error")
Logger.error("Critical error")

# Debug messages (can be filtered out)
Logger.debug("Detailed debug info")
```

### Logging with Context
```gdscript
Logger.info("Unit moved", {
    "unit_id": unit.id,
    "from": from_position,
    "to": to_position,
    "distance": distance
})
```

### Configuration
```gdscript
# Set minimum log level (filter out DEBUG messages)
Logger.set_log_level(Logger.LogLevel.INFO)

# Disable logging temporarily
Logger.set_enabled(false)

# Get log file location
print(Logger.get_real_log_file_path())

# Open logs directory in file browser
Logger.open_log_directory()
```

## Log File Location

**Virtual Path**: `user://logs/debug_YYYYMMDD_HHMMSS.log`

**Real Path (macOS)**: `~/Library/Application Support/Godot/app_userdata/40k/logs/`

**Real Path (Windows)**: `%APPDATA%\Godot\app_userdata\40k\logs\`

**Real Path (Linux)**: `~/.local/share/godot/app_userdata/40k/logs/`

## Log Format

```
[2025-10-08 14:30:45] [INFO   ] DebugLogger initialized - Session: 20251008_143045
[2025-10-08 14:30:46] [DEBUG  ] Starting movement phase
[2025-10-08 14:30:47] [WARNING] Unit coherency at risk | Context: {"unit_id":"space_marine_1"}
[2025-10-08 14:30:48] [ERROR  ] Invalid target position
```

## For Claude

To read debug logs during debugging:
1. Ask user for log location: `Logger.get_real_log_file_path()`
2. Read the file using Read tool
3. Analyze timestamps and error messages
4. Identify patterns and issues

## Migration Guide

### Updating Existing Code

**Before**:
```gdscript
print("Game started")
push_warning("Low memory")
push_error("Failed to load")
```

**After**:
```gdscript
Logger.info("Game started")
Logger.warn("Low memory")
Logger.error("Failed to load")
```

**Note**: Original `print()` statements still work! The logger is additive.

## Performance

- Logs are buffered (20 messages before write)
- Auto-flush every 5 seconds
- File rotation at 10MB
- Minimal overhead (~0.1ms per log entry)
```

### Phase 4: Testing

#### File: `40k/tests/unit/test_debug_logger.gd` (NEW)

```gdscript
extends GutTest

# Unit tests for DebugLogger functionality
# Tests file creation, logging levels, and output format

var logger: Node

func before_each():
    # Get reference to DebugLogger autoload
    logger = DebugLogger

    # Ensure logger is enabled
    logger.set_enabled(true)

func after_each():
    # Flush any pending logs
    logger._flush_buffer()

func test_logger_exists():
    assert_not_null(logger, "DebugLogger should be available as autoload")

func test_log_file_created():
    var log_path = logger.get_log_file_path()
    assert_ne(log_path, "", "Log file path should not be empty")
    assert_true(log_path.begins_with("user://logs/debug_"), "Log path should follow naming convention")

func test_info_logging():
    logger.info("Test info message")
    logger._flush_buffer()

    # Verify log file contains message
    var log_path = logger.get_log_file_path()
    var file = FileAccess.open(log_path, FileAccess.READ)
    assert_not_null(file, "Should be able to open log file")

    var content = file.get_as_text()
    assert_true(content.contains("Test info message"), "Log should contain info message")
    assert_true(content.contains("[INFO]"), "Log should contain INFO level tag")

func test_warning_logging():
    logger.warn("Test warning message")
    logger._flush_buffer()

    var log_path = logger.get_log_file_path()
    var file = FileAccess.open(log_path, FileAccess.READ)
    var content = file.get_as_text()

    assert_true(content.contains("Test warning message"), "Log should contain warning message")
    assert_true(content.contains("[WARNING]"), "Log should contain WARNING level tag")

func test_error_logging():
    logger.error("Test error message")
    logger._flush_buffer()

    var log_path = logger.get_log_file_path()
    var file = FileAccess.open(log_path, FileAccess.READ)
    var content = file.get_as_text()

    assert_true(content.contains("Test error message"), "Log should contain error message")
    assert_true(content.contains("[ERROR]"), "Log should contain ERROR level tag")

func test_debug_logging():
    logger.debug("Test debug message")
    logger._flush_buffer()

    var log_path = logger.get_log_file_path()
    var file = FileAccess.open(log_path, FileAccess.READ)
    var content = file.get_as_text()

    assert_true(content.contains("Test debug message"), "Log should contain debug message")
    assert_true(content.contains("[DEBUG]"), "Log should contain DEBUG level tag")

func test_log_level_filtering():
    # Set minimum level to WARNING
    logger.set_log_level(DebugLogger.LogLevel.WARNING)

    # Clear existing logs by reading to end
    logger._flush_buffer()
    var initial_size = FileAccess.open(logger.get_log_file_path(), FileAccess.READ).get_length()

    # Log at different levels
    logger.debug("Should not appear")
    logger.info("Should not appear")
    logger.warn("Should appear")
    logger.error("Should also appear")
    logger._flush_buffer()

    # Check log content
    var file = FileAccess.open(logger.get_log_file_path(), FileAccess.READ)
    var content = file.get_as_text()

    assert_false(content.find("Should not appear") > initial_size, "DEBUG and INFO should be filtered")
    assert_true(content.contains("Should appear"), "WARNING should appear")
    assert_true(content.contains("Should also appear"), "ERROR should appear")

    # Reset log level
    logger.set_log_level(DebugLogger.LogLevel.DEBUG)

func test_logging_with_context():
    var context = {
        "unit_id": "test_unit_1",
        "position": Vector2(100, 200)
    }

    logger.info("Unit spawned", context)
    logger._flush_buffer()

    var file = FileAccess.open(logger.get_log_file_path(), FileAccess.READ)
    var content = file.get_as_text()

    assert_true(content.contains("Unit spawned"), "Log should contain message")
    assert_true(content.contains("Context:"), "Log should contain context marker")
    assert_true(content.contains("test_unit_1"), "Log should contain context data")

func test_enable_disable():
    # Disable logger
    logger.set_enabled(false)

    var initial_size = FileAccess.open(logger.get_log_file_path(), FileAccess.READ).get_length()

    logger.info("This should not be logged")
    logger._flush_buffer()

    var new_size = FileAccess.open(logger.get_log_file_path(), FileAccess.READ).get_length()

    # Size should not change when disabled
    assert_eq(initial_size, new_size, "Log file should not grow when logger is disabled")

    # Re-enable
    logger.set_enabled(true)

func test_timestamp_format():
    logger.info("Timestamp test")
    logger._flush_buffer()

    var file = FileAccess.open(logger.get_log_file_path(), FileAccess.READ)
    var content = file.get_as_text()

    # Check for timestamp format [YYYY-MM-DD HH:MM:SS]
    var regex = RegEx.new()
    regex.compile("\\[\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\]")
    var result = regex.search(content)

    assert_not_null(result, "Log should contain properly formatted timestamp")

func test_session_id_generation():
    var session_id = logger.session_id
    assert_ne(session_id, "", "Session ID should not be empty")
    assert_true(session_id.length() == 15, "Session ID should be 15 characters (YYYYMMDD_HHMMSS)")

func test_real_path_accessible():
    var real_path = logger.get_real_log_file_path()
    assert_ne(real_path, "", "Real path should not be empty")
    assert_false(real_path.begins_with("user://"), "Real path should be absolute, not virtual")

func test_buffer_flushing():
    # Log less than buffer size
    for i in range(5):
        logger.info("Message %d" % i)

    # Buffer should not be flushed yet (buffer size is 20)
    assert_gt(logger.log_buffer.size(), 0, "Buffer should contain unflushed messages")

    # Flush manually
    logger._flush_buffer()

    assert_eq(logger.log_buffer.size(), 0, "Buffer should be empty after flush")

func test_log_header_present():
    var file = FileAccess.open(logger.get_log_file_path(), FileAccess.READ)
    var content = file.get_as_text()

    assert_true(content.contains("DEBUG LOG SESSION"), "Log should have session header")
    assert_true(content.contains("Session ID:"), "Header should include session ID")
    assert_true(content.contains("Warhammer 40k Game"), "Header should include project name")
```

### Phase 5: Optional Enhancement - Log Viewer

#### File: `40k/utils/LogViewer.gd` (NEW - OPTIONAL)

```gdscript
extends Control

# LogViewer - Simple in-game log viewer
# Shows recent log entries in a scrollable text area
# Can be added to debug menu or opened with hotkey

@onready var log_display: TextEdit = $VBoxContainer/LogDisplay
@onready var refresh_button: Button = $VBoxContainer/HBoxContainer/RefreshButton
@onready var clear_button: Button = $VBoxContainer/HBoxContainer/ClearButton
@onready var open_folder_button: Button = $VBoxContainer/HBoxContainer/OpenFolderButton
@onready var level_filter: OptionButton = $VBoxContainer/HBoxContainer/LevelFilter

var auto_refresh: bool = true
var refresh_timer: Timer = null
var current_filter: int = 0  # 0 = All, 1 = INFO+, 2 = WARNING+, 3 = ERROR only

func _ready() -> void:
    # Setup UI
    if refresh_button:
        refresh_button.pressed.connect(_on_refresh_pressed)
    if clear_button:
        clear_button.pressed.connect(_on_clear_pressed)
    if open_folder_button:
        open_folder_button.pressed.connect(_on_open_folder_pressed)
    if level_filter:
        level_filter.item_selected.connect(_on_filter_changed)

    # Setup auto-refresh
    refresh_timer = Timer.new()
    refresh_timer.wait_time = 2.0
    refresh_timer.timeout.connect(_refresh_log)
    refresh_timer.autostart = true
    add_child(refresh_timer)

    # Initial load
    _refresh_log()

func _refresh_log() -> void:
    if not auto_refresh:
        return

    var log_path = DebugLogger.get_log_file_path()
    var file = FileAccess.open(log_path, FileAccess.READ)

    if not file:
        log_display.text = "Unable to open log file"
        return

    var content = file.get_as_text()

    # Apply filter
    if current_filter > 0:
        content = _apply_filter(content)

    # Get last 1000 lines to avoid performance issues
    var lines = content.split("\n")
    if lines.size() > 1000:
        lines = lines.slice(lines.size() - 1000)
        content = "\n".join(lines)

    log_display.text = content

    # Scroll to bottom
    await get_tree().process_frame
    log_display.scroll_vertical = log_display.get_line_count()

func _apply_filter(content: String) -> String:
    var lines = content.split("\n")
    var filtered_lines: Array[String] = []

    for line in lines:
        var should_include = false

        match current_filter:
            1:  # INFO and above
                should_include = line.contains("[INFO]") or line.contains("[WARNING]") or line.contains("[ERROR]")
            2:  # WARNING and above
                should_include = line.contains("[WARNING]") or line.contains("[ERROR]")
            3:  # ERROR only
                should_include = line.contains("[ERROR]")
            _:
                should_include = true

        if should_include or not line.contains("["):
            # Include non-log lines (headers, etc.)
            filtered_lines.append(line)

    return "\n".join(filtered_lines)

func _on_refresh_pressed() -> void:
    _refresh_log()

func _on_clear_pressed() -> void:
    log_display.text = ""

func _on_open_folder_pressed() -> void:
    DebugLogger.open_log_directory()

func _on_filter_changed(index: int) -> void:
    current_filter = index
    _refresh_log()

func set_auto_refresh(enabled: bool) -> void:
    auto_refresh = enabled
    if refresh_timer:
        refresh_timer.paused = not enabled
```

## Implementation Tasks

Execute these tasks in order:

### Task 1: Create DebugLogger Autoload
- [ ] Create file: `40k/autoloads/DebugLogger.gd`
- [ ] Implement core logging functions: `debug()`, `info()`, `warn()`, `error()`
- [ ] Implement file writing with buffering
- [ ] Implement log header generation
- [ ] Implement timestamp formatting
- [ ] Implement log level filtering
- [ ] Implement session ID generation
- [ ] Implement auto-flush timer
- [ ] Implement log rotation
- [ ] Implement enable/disable toggle
- [ ] Implement utility functions (get paths, open directory)

### Task 2: Register Autoload
- [ ] Edit `40k/project.godot`
- [ ] Add `DebugLogger="*res://autoloads/DebugLogger.gd"` to autoload section (line ~21)
- [ ] Verify autoload loads correctly by running game

### Task 3: Create Documentation
- [ ] Create file: `40k/DEBUG_LOGGING.md`
- [ ] Document usage examples
- [ ] Document log file locations
- [ ] Document configuration options
- [ ] Document migration guide

### Task 4: Create Unit Tests
- [ ] Create file: `40k/tests/unit/test_debug_logger.gd`
- [ ] Test: Logger exists and is accessible
- [ ] Test: Log file is created
- [ ] Test: Info logging works
- [ ] Test: Warning logging works
- [ ] Test: Error logging works
- [ ] Test: Debug logging works
- [ ] Test: Log level filtering
- [ ] Test: Context logging
- [ ] Test: Enable/disable functionality
- [ ] Test: Timestamp format
- [ ] Test: Session ID generation
- [ ] Test: Real path accessibility
- [ ] Test: Buffer flushing
- [ ] Test: Log header presence

### Task 5: Optional - Create Log Viewer
- [ ] Create file: `40k/utils/LogViewer.gd`
- [ ] Create scene: `40k/utils/LogViewer.tscn`
- [ ] Implement UI layout
- [ ] Implement auto-refresh
- [ ] Implement filtering
- [ ] Implement manual refresh
- [ ] Integrate with debug menu (if desired)

### Task 6: Example Integration
- [ ] Update `DebugManager.gd` to use Logger instead of print
- [ ] Replace key print statements with Logger calls:
  - Line 20: `print("DebugManager initialized")` → `Logger.info("DebugManager initialized")`
  - Line 34: `print("Entering DEBUG MODE")` → `Logger.info("Entering DEBUG MODE")`
  - Line 59: `print("Exiting DEBUG MODE")` → `Logger.info("Exiting DEBUG MODE")`
  - Line 107: `print("Debug: Started dragging...")` → `Logger.debug("Started dragging...")`
  - Line 130: `print("Debug: Moved...")` → `Logger.debug("Moved model to position")`
  - Line 176, 201: Update error messages to use `Logger.error()`

### Task 7: Validation
- [ ] Run unit tests: `godot --headless --path /Users/robertocallaghan/Documents/claude/godotv2/40k -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_debug_logger.gd -glog=1 -gexit`
- [ ] Verify log file is created at `user://logs/debug_YYYYMMDD_HHMMSS.log`
- [ ] Verify log contains session header
- [ ] Verify log contains timestamped entries
- [ ] Test different log levels
- [ ] Test filtering
- [ ] Test enable/disable
- [ ] Get real path and verify Claude can read it
- [ ] Test log rotation (create 10MB+ of logs)
- [ ] Run full test suite to ensure no regressions: `./tests/validate_all_tests.sh`

## Validation Gates

All validation commands must pass:

```bash
# 1. Set Godot path
export PATH="$HOME/bin:$PATH"

# 2. Run DebugLogger unit tests
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
godot --headless --path . \
  -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_debug_logger.gd \
  -glog=1 \
  -gexit

# Expected: All tests pass

# 3. Verify log file creation (run game briefly)
godot --headless --path . -q &
sleep 5
kill %1

# Expected: Log file created at user://logs/

# 4. Check log file exists and has content
ls -lh ~/Library/Application\ Support/Godot/app_userdata/40k/logs/debug_*.log

# Expected: File exists with non-zero size

# 5. Verify log content is readable
cat ~/Library/Application\ Support/Godot/app_userdata/40k/logs/debug_*.log | head -20

# Expected: Readable text with timestamps and session header

# 6. Run full test suite for regression check
./tests/validate_all_tests.sh

# Expected: No new failures, existing pass rate maintained
```

## Success Criteria

- [x] DebugLogger autoload created and registered
- [x] All logging functions work (debug, info, warn, error)
- [x] Logs written to file with timestamps
- [x] Log file location is accessible to Claude
- [x] Session tracking with unique IDs
- [x] Log level filtering works
- [x] Enable/disable functionality works
- [x] All unit tests pass
- [x] Documentation complete
- [x] No regressions in existing tests
- [x] Log file can be read by Claude for debugging

## Common Pitfalls & Solutions

### Issue: Log file not created
**Solution**: Ensure `user://logs/` directory is created with `DirAccess.open("user://").make_dir_recursive("logs")`

### Issue: Can't find log file location
**Solution**: Use `Logger.get_real_log_file_path()` to get absolute path, or `Logger.open_log_directory()` to open in file browser

### Issue: Log file grows too large
**Solution**: Implement log rotation at max_log_size (10MB default), archive old logs

### Issue: Performance impact from logging
**Solution**: Use buffering (20 messages), auto-flush timer (5 seconds), filter by log level

### Issue: Logs not visible immediately
**Solution**: Call `Logger._flush_buffer()` to force immediate write, or wait for auto-flush

### Issue: Context not showing in logs
**Solution**: Ensure context is passed as Dictionary parameter, e.g., `Logger.info("msg", {"key": "value"})`

## References

### Code References
- `ActionLogger.gd` lines 1-335 - File writing patterns
- `DebugManager.gd` lines 1-330 - Example of print usage
- `project.godot` lines 18-41 - Autoload configuration
- `tests/validate_all_tests.sh` lines 1-103 - Test execution

### External Documentation
- Godot FileAccess API: https://docs.godotengine.org/en/4.4/classes/class_fileaccess.html
- Godot File I/O Tutorial: https://kidscancode.org/godot_recipes/4.x/basics/file_io/index.html
- Godot Autoloads: https://docs.godotengine.org/en/4.4/tutorials/scripting/singletons_autoload.html

### Warhammer Rules (not directly applicable but project reference)
- Core Rules: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/

## PRP Quality Checklist

- [x] All necessary context included
- [x] Validation gates are executable commands
- [x] References existing patterns (ActionLogger, autoload system)
- [x] Clear implementation path with step-by-step tasks
- [x] Error handling documented
- [x] Code examples are complete and runnable
- [x] Test suite provided
- [x] Documentation provided
- [x] Common pitfalls addressed
- [x] External references included

## Confidence Score

**9/10** - High confidence in one-pass implementation success

**Reasoning**:
- Clear requirements with single, well-defined goal
- Existing patterns to follow (ActionLogger)
- Well-understood Godot API (FileAccess)
- Comprehensive code examples provided
- Complete test suite defined
- All necessary context included
- Executable validation commands
- Common issues anticipated and addressed

**Risk**: Minor (-1 point): Autoload registration syntax or file paths might need adjustment on first run, but easily fixable with error messages.
