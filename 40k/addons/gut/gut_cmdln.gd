extends SceneTree

# GUT Command Line Runner
# Simplified implementation for running tests from command line

var test_directories = ["res://tests"]
var test_pattern = "test_*.gd"
var xml_output_file = ""
var exit_on_completion = false
var specific_test_file = ""
var specific_test_method = ""

func _init():
	parse_command_line_args()

func _initialize():
	# _initialize() is called after the SceneTree is fully set up
	# This ensures autoloads are loaded and Engine.get_main_loop() works
	run_tests_deferred.call_deferred()

func run_tests_deferred():
	# Run tests after the first frame to ensure everything is initialized
	await run_tests()

func parse_command_line_args():
	# Get both regular and user args
	var args = OS.get_cmdline_args()
	var user_args = OS.get_cmdline_user_args()

	# Combine them for processing
	var all_args = args + user_args

	print("DEBUG: System args: ", args)
	print("DEBUG: User args: ", user_args)
	print("DEBUG: Combined args: ", all_args)

	for i in range(all_args.size()):
		var arg = all_args[i]
		print("DEBUG: Processing arg[%d]: '%s'" % [i, arg])

		# Handle both "-gdir value" and "-gdir=value" styles
		if arg.begins_with("-gdir="):
			test_directories = [arg.substr(6)]
		elif arg == "-gdir" and i + 1 < all_args.size():
			test_directories = [all_args[i + 1]]
		elif arg.begins_with("-gfile="):
			specific_test_file = arg.substr(7)
		elif arg == "-gfile" and i + 1 < all_args.size():
			specific_test_file = all_args[i + 1]
		elif arg.begins_with("-gtest="):
			specific_test_method = arg.substr(7)
		elif arg == "-gtest" and i + 1 < all_args.size():
			specific_test_method = all_args[i + 1]
		elif arg.begins_with("-gxmlfile="):
			xml_output_file = arg.substr(10)
		elif arg == "-gxmlfile" and i + 1 < all_args.size():
			xml_output_file = all_args[i + 1]
		elif arg == "-gexit":
			exit_on_completion = true
		elif arg.begins_with("-gprefix="):
			test_pattern = arg.substr(9) + "*.gd"
		elif arg == "-gprefix" and i + 1 < all_args.size():
			test_pattern = all_args[i + 1] + "*.gd"
		elif arg.begins_with("-gpattern="):
			test_pattern = arg.substr(10)
		elif arg == "-gpattern" and i + 1 < all_args.size():
			test_pattern = all_args[i + 1]

func run_tests():
	print("=== GUT Test Runner ===")
	print("DEBUG: specific_test_file = '%s'" % specific_test_file)
	print("DEBUG: specific_test_method = '%s'" % specific_test_method)

	var test_files = []

	if specific_test_file != "":
		# Use specific file, resolve path if needed
		var file_path = specific_test_file
		if not file_path.begins_with("res://"):
			# Try to find the file in test directories
			for dir in test_directories:
				var full_path = dir + "/" + file_path
				if FileAccess.file_exists(full_path):
					file_path = full_path
					break
		test_files = [file_path]
		print("DEBUG: Using specific file: %s" % file_path)
	else:
		test_files = find_test_files()
		print("DEBUG: Found %d test files" % test_files.size())

	var total_tests = 0
	var passed_tests = 0
	var failed_tests = 0
	var test_results = []

	for test_file in test_files:
		print("Running tests in: " + test_file)
		var results = await run_test_file(test_file)
		test_results.append_array(results)

		for result in results:
			total_tests += 1
			if result.passed:
				passed_tests += 1
			else:
				failed_tests += 1

	print("\n=== Test Results ===")
	print("Total: %d, Passed: %d, Failed: %d" % [total_tests, passed_tests, failed_tests])

	if xml_output_file != "":
		write_xml_results(test_results)

	if exit_on_completion:
		quit(failed_tests)

func find_test_files() -> Array:
	var files = []
	for dir_path in test_directories:
		_find_files_recursive(dir_path, files)
	return files

func _find_files_recursive(path: String, files: Array):
	var dir = DirAccess.open(path)
	if dir != null:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			var full_path = path + "/" + file_name
			
			if dir.current_is_dir() and not file_name.begins_with("."):
				_find_files_recursive(full_path, files)
			elif file_name.ends_with(".gd") and file_name.match(test_pattern):
				files.append(full_path)
			
			file_name = dir.get_next()

func run_test_file(file_path: String) -> Array:
	var script = load(file_path)
	if script == null:
		print("Failed to load test file: " + file_path)
		return []

	var test_instance = script.new()
	if not test_instance.has_method("before_all"):
		print("Test file does not extend GutTest: " + file_path)
		return []

	# Add test instance to the scene tree so get_tree() works
	root.add_child(test_instance)
	
	# Run test lifecycle
	test_instance.before_all()
	
	var test_methods = []
	for method in test_instance.get_method_list():
		if method.name.begins_with("test_"):
			# Filter by specific test method if specified
			if specific_test_method == "" or method.name == specific_test_method:
				test_methods.append(method.name)

	var results = []
	for test_method in test_methods:
		test_instance._current_test = test_method
		test_instance.before_each()

		print("  Running: " + test_method)

		# Call the test method and handle both sync and async tests
		var test_result = test_instance.call(test_method)

		# If the test returns a coroutine (async), wait for it to complete
		if test_result is Signal:
			await test_result

		test_instance.after_each()
		if test_instance.has_method("_post_test_cleanup"):
			test_instance._post_test_cleanup()

		# Get results from this test
		for result in test_instance._test_results:
			if result.test == test_method:
				results.append({
					"test_file": file_path,
					"test_method": test_method,
					"passed": result.passed,
					"message": result.message
				})
	
	test_instance.after_all()
	test_instance.queue_free()
	
	return results

func write_xml_results(results: Array):
	var file = FileAccess.open(xml_output_file, FileAccess.WRITE)
	if file == null:
		print("Failed to create XML output file: " + xml_output_file)
		return
	
	file.store_string('<?xml version="1.0" encoding="UTF-8"?>\n')
	file.store_string('<testsuites>\n')
	
	var current_suite = ""
	var suite_tests = []
	
	for result in results:
		if result.test_file != current_suite:
			if suite_tests.size() > 0:
				write_xml_test_suite(file, current_suite, suite_tests)
			current_suite = result.test_file
			suite_tests = []
		suite_tests.append(result)
	
	if suite_tests.size() > 0:
		write_xml_test_suite(file, current_suite, suite_tests)
	
	file.store_string('</testsuites>\n')
	file.close()
	print("XML results written to: " + xml_output_file)

func write_xml_test_suite(file: FileAccess, suite_name: String, tests: Array):
	var passed = 0
	var failed = 0
	for test in tests:
		if test.passed:
			passed += 1
		else:
			failed += 1
	
	file.store_string('  <testsuite name="%s" tests="%d" failures="%d" errors="0">\n' % [suite_name, tests.size(), failed])
	
	for test in tests:
		file.store_string('    <testcase name="%s" classname="%s"' % [test.test_method, suite_name])
		if test.passed:
			file.store_string('/>\n')
		else:
			file.store_string('>\n')
			file.store_string('      <failure message="%s"/>\n' % test.message.xml_escape())
			file.store_string('    </testcase>\n')
	
	file.store_string('  </testsuite>\n')
