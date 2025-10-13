# Debug Logging System

## Overview
The DebugLogger provides a centralized logging system that writes to both console and file, making it easy for Claude to read debug output.

## Basic Usage

### Simple Logging
```gdscript
# Instead of: print("Hello")
DebugLogger.info("Hello")

# Instead of: push_warning("Something odd")
DebugLogger.warn("Something odd")

# Instead of: push_error("Critical error")
DebugLogger.error("Critical error")

# Debug messages (can be filtered out)
DebugLogger.debug("Detailed debug info")
```

### Logging with Context
```gdscript
DebugLogger.info("Unit moved", {
	"unit_id": unit.id,
	"from": from_position,
	"to": to_position,
	"distance": distance
})
```

### Configuration
```gdscript
# Set minimum log level (filter out DEBUG messages)
DebugLogger.set_log_level(DebugLogger.LogLevel.INFO)

# Disable logging temporarily
DebugLogger.set_enabled(false)

# Get log file location
print(DebugLogger.get_real_log_file_path())

# Open logs directory in file browser
DebugLogger.open_log_directory()
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
1. Ask user for log location: `DebugLogger.get_real_log_file_path()`
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
DebugLogger.info("Game started")
DebugLogger.warn("Low memory")
DebugLogger.error("Failed to load")
```

**Note**: Original `print()` statements still work! The logger is additive.

## Performance

- Logs are buffered (20 messages before write)
- Auto-flush every 5 seconds
- File rotation at 10MB
- Minimal overhead (~0.1ms per log entry)
