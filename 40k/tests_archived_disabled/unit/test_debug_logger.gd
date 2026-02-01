extends "res://addons/gut/test.gd"

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
