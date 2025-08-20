extends SceneTree

# GUT Command Line Runner
# Simplified implementation for running tests from command line

var test_directories = ["res://tests"]
var test_pattern = "test_*.gd"
var xml_output_file = ""
var exit_on_completion = false
var specific_test = ""

func _init():
	parse_command_line_args()
	run_tests()

func parse_command_line_args():
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		var arg = args[i]
		match arg:
			"-gdir":
				if i + 1 < args.size():
					test_directories = [args[i + 1]]
			"-gtest":
				if i + 1 < args.size():
					specific_test = args[i + 1]
			"-gxmlfile":
				if i + 1 < args.size():
					xml_output_file = args[i + 1]
			"-gexit":
				exit_on_completion = true
			"-gpattern":
				if i + 1 < args.size():
					test_pattern = args[i + 1]

func run_tests():
	print("=== GUT Test Runner ===")
	
	var test_files = []
	
	if specific_test != "":
		test_files = [specific_test]
	else:
		test_files = find_test_files()
	
	var total_tests = 0
	var passed_tests = 0
	var failed_tests = 0
	var test_results = []
	
	for test_file in test_files:
		print("Running tests in: " + test_file)
		var results = run_test_file(test_file)
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
	
	# SceneTree doesn't have add_child, so we'll work with the test instance directly
	
	# Run test lifecycle
	test_instance.before_all()
	
	var test_methods = []
	for method in test_instance.get_method_list():
		if method.name.begins_with("test_"):
			test_methods.append(method.name)
	
	var results = []
	for test_method in test_methods:
		test_instance._current_test = test_method
		test_instance.before_each()
		
		print("  Running: " + test_method)
		test_instance.call(test_method)
		
		test_instance.after_each()
		
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