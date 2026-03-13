extends "res://addons/gut/test.gd"

# SAVE-19: Tests for save file export/import (portable format for sharing)
# Tests:
# 1. Export current game state to .w40kexport file
# 2. Export from existing save file
# 3. Import exported file round-trip
# 4. Reject invalid export files
# 5. Reject missing files
# 6. Export file structure validation
# 7. Export by name convenience method

var _test_export_path := "/tmp/test_save19_export.w40kexport"
var _test_export_path2 := "/tmp/test_save19_export2.w40kexport"
var _test_export_path3 := "/tmp/test_save19_export_by_name.w40kexport"
var _test_invalid_path := "/tmp/test_save19_invalid.w40kexport"

func after_each():
	# Clean up test files
	for path in [_test_export_path, _test_export_path2, _test_export_path3, _test_invalid_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

func test_export_current_game_state():
	# Export the current game state (default armies are loaded on startup)
	var result = SaveLoadManager.export_save(_test_export_path)
	assert_true(result, "Export should succeed")
	assert_true(FileAccess.file_exists(_test_export_path), "Export file should exist")

	# Read and validate structure
	var file = FileAccess.open(_test_export_path, FileAccess.READ)
	assert_not_null(file, "Should be able to open export file")
	var content = file.get_as_text()
	file.close()

	assert_true(content.length() > 0, "Export file should have content")

	var json = JSON.new()
	assert_eq(json.parse(content), OK, "Export file should be valid JSON")

	var data = json.data
	assert_true(data is Dictionary, "Export data should be a Dictionary")
	assert_has(data, "_export", "Should have _export header")
	assert_has(data, "metadata", "Should have metadata")
	assert_has(data, "game_data", "Should have game_data")

	# Validate export header
	var header = data["_export"]
	assert_eq(header["format"], "w40k_portable_save", "Format should be w40k_portable_save")
	assert_eq(header["format_version"], "1.0.0", "Format version should be 1.0.0")
	assert_has(header, "exported_at", "Should have exported_at timestamp")
	assert_eq(header["source_file"], "live_game", "Source should be live_game")

func test_export_file_contains_valid_game_data():
	var result = SaveLoadManager.export_save(_test_export_path)
	assert_true(result, "Export should succeed")

	var file = FileAccess.open(_test_export_path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()

	var json = JSON.new()
	json.parse(content)
	var data = json.data

	# The game_data field should be a serialized game state string
	var game_data_str = data["game_data"]
	assert_true(game_data_str is String, "game_data should be a string")
	assert_true(game_data_str.length() > 0, "game_data should not be empty")

	# It should be deserializable
	var game_state = StateSerializer.deserialize_game_state(game_data_str)
	assert_true(game_state.size() > 0, "game_data should deserialize to non-empty state")
	assert_has(game_state, "units", "Deserialized state should have units")
	assert_has(game_state, "meta", "Deserialized state should have meta")

func test_import_exported_file():
	# First export
	var units_before = GameState.state.get("units", {}).size()
	var export_result = SaveLoadManager.export_save(_test_export_path)
	assert_true(export_result, "Export should succeed")

	# Then import
	var import_result = SaveLoadManager.import_save(_test_export_path)
	assert_true(import_result, "Import should succeed")

	# Verify units survived the round-trip
	var units_after = GameState.state.get("units", {}).size()
	assert_eq(units_after, units_before, "Unit count should be preserved after import")

func test_import_rejects_invalid_file():
	# Write invalid export file (missing _export header)
	var file = FileAccess.open(_test_invalid_path, FileAccess.WRITE)
	file.store_string('{"not_an_export": true}')
	file.close()

	var result = SaveLoadManager.import_save(_test_invalid_path)
	assert_false(result, "Import should reject invalid export file")

func test_import_rejects_wrong_format():
	# Write file with wrong format identifier
	var file = FileAccess.open(_test_invalid_path, FileAccess.WRITE)
	file.store_string('{"_export": {"format": "wrong_format"}, "game_data": "test"}')
	file.close()

	var result = SaveLoadManager.import_save(_test_invalid_path)
	assert_false(result, "Import should reject wrong format")

func test_import_rejects_missing_file():
	var result = SaveLoadManager.import_save("/tmp/nonexistent_save19.w40kexport")
	assert_false(result, "Import should reject non-existent file")

func test_import_rejects_empty_file():
	var file = FileAccess.open(_test_invalid_path, FileAccess.WRITE)
	file.store_string("")
	file.close()

	var result = SaveLoadManager.import_save(_test_invalid_path)
	assert_false(result, "Import should reject empty file")

func test_import_rejects_invalid_json():
	var file = FileAccess.open(_test_invalid_path, FileAccess.WRITE)
	file.store_string("this is not json {{{")
	file.close()

	var result = SaveLoadManager.import_save(_test_invalid_path)
	assert_false(result, "Import should reject invalid JSON")

func test_export_from_existing_save():
	# Only test if save files exist
	var save_files = SaveLoadManager.get_save_files()
	if save_files.size() == 0:
		pass_test("No save files to test export from — skipping")
		return

	var first_save = save_files[0]
	var source_path = first_save.get("file_path", "")
	var result = SaveLoadManager.export_save(_test_export_path2, source_path)
	assert_true(result, "Export from existing save should succeed")

	# Validate the exported file
	var file = FileAccess.open(_test_export_path2, FileAccess.READ)
	var content = file.get_as_text()
	file.close()

	var json = JSON.new()
	assert_eq(json.parse(content), OK, "Exported file should be valid JSON")

	var data = json.data
	assert_has(data, "_export", "Should have _export header")
	assert_eq(data["_export"]["source_file"], source_path.get_file(), "Should reference source file")

func test_export_by_name():
	var save_files = SaveLoadManager.get_save_files()
	if save_files.size() == 0:
		pass_test("No save files — skipping export_by_name test")
		return

	var display_name = save_files[0].get("display_name", "")
	var result = SaveLoadManager.export_save_by_name(display_name, _test_export_path3)
	assert_true(result, "export_save_by_name should succeed")
	assert_true(FileAccess.file_exists(_test_export_path3), "Export file should exist")

func test_get_default_export_directory():
	var dir = SaveLoadManager.get_default_export_directory()
	assert_true(dir.length() > 0, "Default export directory should not be empty")
	assert_true(DirAccess.dir_exists_absolute(dir), "Default export directory should exist")

func test_export_extension_constant():
	assert_eq(SaveLoadManager.EXPORT_EXTENSION, ".w40kexport", "Export extension should be .w40kexport")
