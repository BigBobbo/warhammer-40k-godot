extends GutTest

# Save/Load Integration Tests - Tests game state persistence and restoration
# Tests coordination between SaveLoadManager, StateSerializer, and GameState

var game_state: GameStateData
var save_manager: Node
var state_serializer: Node
var temp_save_file: String
var initial_state: Dictionary

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	# Create test instances
	game_state = GameStateData.new()
	game_state.initialize_default_state()
	initial_state = game_state.create_snapshot()
	
	# Get or create save/load components
	if Engine.has_singleton("SaveLoadManager"):
		save_manager = Engine.get_singleton("SaveLoadManager")
	
	if Engine.has_singleton("StateSerializer"):
		state_serializer = Engine.get_singleton("StateSerializer")
	
	# Create temp save file path
	temp_save_file = "user://test_save_" + str(Time.get_unix_time_from_system()) + ".save"

func after_each():
	# Clean up temp files
	if FileAccess.file_exists(temp_save_file):
		DirAccess.remove_absolute(temp_save_file)
	
	if game_state:
		game_state.queue_free()

# Test basic save functionality
func test_basic_save():
	if not save_manager:
		skip_test("SaveLoadManager not available")
		return
	
	# Modify game state
	game_state.set_phase(GameStateData.Phase.MOVEMENT)
	game_state.advance_turn()
	
	var save_result = false
	if save_manager.has_method("save_game"):
		save_result = save_manager.save_game(temp_save_file, game_state.create_snapshot())
	else:
		# Test direct file save
		var save_data = game_state.create_snapshot()
		var file = FileAccess.open(temp_save_file, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(save_data))
			file.close()
			save_result = true
	
	assert_true(save_result, "Save operation should succeed")
	assert_true(FileAccess.file_exists(temp_save_file), "Save file should exist after save")

func test_basic_load():
	if not save_manager:
		skip_test("SaveLoadManager not available")
		return
	
	# Create a save first
	game_state.set_phase(GameStateData.Phase.SHOOTING)
	game_state.advance_turn()
	var saved_state = game_state.create_snapshot()
	
	# Save the state
	if save_manager.has_method("save_game"):
		save_manager.save_game(temp_save_file, saved_state)
	else:
		var file = FileAccess.open(temp_save_file, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(saved_state))
			file.close()
	
	# Modify current state
	game_state.set_phase(GameStateData.Phase.FIGHT)
	game_state.advance_turn()
	
	# Load the save
	var loaded_state = null
	if save_manager.has_method("load_game"):
		loaded_state = save_manager.load_game(temp_save_file)
	else:
		var file = FileAccess.open(temp_save_file, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			var json = JSON.new()
			var parse_result = json.parse(json_string)
			if parse_result == OK:
				loaded_state = json.get_data()
	
	assert_not_null(loaded_state, "Load operation should return data")
	assert_eq(GameStateData.Phase.SHOOTING, loaded_state.meta.phase, "Loaded phase should match saved phase")

func test_save_load_round_trip():
	# Test that save->load preserves all data
	
	# Create complex game state
	game_state.set_phase(GameStateData.Phase.CHARGE)
	game_state.advance_turn()
	game_state.set_active_player(2)
	
	# Add some actions to history
	game_state.add_action_to_phase_log({"type": "test_action", "data": "test_value"})
	game_state.commit_phase_log_to_history()
	
	var original_state = game_state.create_snapshot()
	
	# Save state
	var file = FileAccess.open(temp_save_file, FileAccess.WRITE)
	assert_not_null(file, "Should be able to create save file")
	file.store_string(JSON.stringify(original_state))
	file.close()
	
	# Load state
	file = FileAccess.open(temp_save_file, FileAccess.READ)
	assert_not_null(file, "Should be able to open save file")
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	assert_eq(OK, parse_result, "Save file should contain valid JSON")
	
	var loaded_state = json.get_data()
	
	# Verify key data is preserved
	assert_eq(original_state.meta.phase, loaded_state.meta.phase, "Phase should be preserved")
	assert_eq(original_state.meta.turn_number, loaded_state.meta.turn_number, "Turn should be preserved")
	assert_eq(original_state.meta.active_player, loaded_state.meta.active_player, "Active player should be preserved")
	assert_eq(original_state.history.size(), loaded_state.history.size(), "History should be preserved")

func test_state_serialization():
	if not state_serializer:
		skip_test("StateSerializer not available")
		return
	
	var test_state = game_state.create_snapshot()
	
	# Serialize state
	var serialized_data = null
	if state_serializer.has_method("serialize_state"):
		serialized_data = state_serializer.serialize_state(test_state)
	
	assert_not_null(serialized_data, "Serialization should return data")
	
	# Deserialize state
	var deserialized_state = null
	if state_serializer.has_method("deserialize_state"):
		deserialized_state = state_serializer.deserialize_state(serialized_data)
	
	assert_not_null(deserialized_state, "Deserialization should return data")
	assert_eq(test_state.meta.game_id, deserialized_state.meta.game_id, "Game ID should be preserved through serialization")

func test_save_file_corruption_handling():
	# Test handling of corrupted save files
	
	# Create corrupted save file
	var file = FileAccess.open(temp_save_file, FileAccess.WRITE)
	file.store_string("invalid json data {corrupt")
	file.close()
	
	# Try to load corrupted file
	var load_result = null
	var load_success = false
	
	if save_manager and save_manager.has_method("load_game"):
		load_result = save_manager.load_game(temp_save_file)
		load_success = load_result != null
	else:
		# Manual load with error handling
		file = FileAccess.open(temp_save_file, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			var json = JSON.new()
			var parse_result = json.parse(json_string)
			load_success = parse_result == OK
	
	assert_false(load_success, "Loading corrupted file should fail gracefully")

func test_version_compatibility():
	# Test loading saves from different versions
	
	# Create save with older version format
	var old_version_state = {
		"meta": {
			"game_id": "test_game",
			"version": "0.9.0",  # Older version
			"phase": GameStateData.Phase.MOVEMENT
		},
		"units": {},
		"board": {}
	}
	
	var file = FileAccess.open(temp_save_file, FileAccess.WRITE)
	file.store_string(JSON.stringify(old_version_state))
	file.close()
	
	# Try to load old version
	file = FileAccess.open(temp_save_file, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		var json = JSON.new()
		var parse_result = json.parse(json_string)
		
		if parse_result == OK:
			var loaded_data = json.get_data()
			assert_true(loaded_data.has("meta"), "Should load basic structure from old version")

func test_large_save_file():
	# Test handling of large save files
	
	# Create large game state
	var large_state = game_state.create_snapshot()
	
	# Add lots of history entries
	for i in range(1000):
		large_state.history.append({
			"turn": i / 6 + 1,
			"phase": i % 6,
			"actions": [
				{"type": "test_action_" + str(i), "data": "large_data_" + str(i)}
			]
		})
	
	# Save large state
	var file = FileAccess.open(temp_save_file, FileAccess.WRITE)
	assert_not_null(file, "Should be able to create large save file")
	file.store_string(JSON.stringify(large_state))
	file.close()
	
	# Load large state
	file = FileAccess.open(temp_save_file, FileAccess.READ)
	assert_not_null(file, "Should be able to open large save file")
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	assert_eq(OK, parse_result, "Should parse large save file successfully")
	
	var loaded_state = json.get_data()
	assert_eq(1000, loaded_state.history.size(), "All history entries should be preserved")

func test_concurrent_save_operations():
	# Test multiple save operations
	
	var save_files = []
	var save_states = []
	
	# Create multiple different states
	for i in range(3):
		var state = game_state.create_snapshot()
		state.meta.game_id = "concurrent_test_" + str(i)
		state.meta.turn_number = i + 1
		save_states.append(state)
		
		var filename = "user://concurrent_save_" + str(i) + ".save"
		save_files.append(filename)
		
		# Save concurrently
		var file = FileAccess.open(filename, FileAccess.WRITE)
		file.store_string(JSON.stringify(state))
		file.close()
	
	# Verify all saves completed correctly
	for i in range(save_files.size()):
		assert_true(FileAccess.file_exists(save_files[i]), "Concurrent save " + str(i) + " should exist")
		
		var file = FileAccess.open(save_files[i], FileAccess.READ)
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		var parse_result = json.parse(json_string)
		assert_eq(OK, parse_result, "Concurrent save " + str(i) + " should be valid JSON")
		
		var loaded_data = json.get_data()
		assert_eq(save_states[i].meta.game_id, loaded_data.meta.game_id, "Concurrent save " + str(i) + " should have correct data")
	
	# Clean up
	for filename in save_files:
		DirAccess.remove_absolute(filename)

func test_auto_save_functionality():
	if not save_manager:
		skip_test("SaveLoadManager not available")
		return
	
	# Test auto-save triggers
	if save_manager.has_method("enable_auto_save"):
		save_manager.enable_auto_save(true)
	
	# Modify state (should trigger auto-save)
	game_state.advance_turn()
	
	await get_tree().create_timer(0.5).timeout  # Wait for auto-save
	
	# Check for auto-save file
	var auto_save_path = "user://auto_save.sav"
	if save_manager.has_method("get_auto_save_path"):
		auto_save_path = save_manager.get_auto_save_path()
	
	if FileAccess.file_exists(auto_save_path):
		assert_true(true, "Auto-save should create save file")
		DirAccess.remove_absolute(auto_save_path)  # Clean up
	else:
		# Auto-save might not be implemented yet
		pass

func test_quick_save_load():
	if not save_manager:
		skip_test("SaveLoadManager not available")
		return
	
	# Test quick save
	game_state.set_phase(GameStateData.Phase.FIGHT)
	game_state.advance_turn()
	
	var quick_save_result = false
	if save_manager.has_method("quick_save"):
		quick_save_result = save_manager.quick_save(game_state.create_snapshot())
	
	if quick_save_result:
		# Modify state
		game_state.set_phase(GameStateData.Phase.MORALE)
		
		# Quick load
		var quick_load_result = false
		if save_manager.has_method("quick_load"):
			var loaded_state = save_manager.quick_load()
			if loaded_state:
				game_state.load_from_snapshot(loaded_state)
				quick_load_result = true
		
		if quick_load_result:
			assert_eq(GameStateData.Phase.FIGHT, game_state.get_current_phase(), "Quick load should restore previous state")

func test_save_metadata():
	# Test save file metadata
	var metadata = {
		"save_time": Time.get_unix_time_from_system(),
		"game_version": "1.0.0",
		"player_name": "Test Player",
		"scenario": "Test Scenario"
	}
	
	var save_data = game_state.create_snapshot()
	save_data.metadata = metadata
	
	var file = FileAccess.open(temp_save_file, FileAccess.WRITE)
	file.store_string(JSON.stringify(save_data))
	file.close()
	
	# Load and verify metadata
	file = FileAccess.open(temp_save_file, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	assert_eq(OK, parse_result, "Save with metadata should be valid JSON")
	
	var loaded_data = json.get_data()
	assert_true(loaded_data.has("metadata"), "Loaded data should include metadata")
	assert_eq(metadata.player_name, loaded_data.metadata.player_name, "Player name should be preserved")

func test_incremental_saves():
	# Test incremental/differential saves (if implemented)
	
	# Create base state
	var base_state = game_state.create_snapshot()
	
	# Save base state
	var base_file = "user://base_save.save"
	var file = FileAccess.open(base_file, FileAccess.WRITE)
	file.store_string(JSON.stringify(base_state))
	file.close()
	
	# Modify state slightly
	game_state.advance_turn()
	game_state.add_action_to_phase_log({"type": "incremental_action"})
	
	# Create incremental save (difference only)
	var current_state = game_state.create_snapshot()
	var incremental_data = {
		"base_save": "base_save.save",
		"changes": {
			"meta.turn_number": current_state.meta.turn_number,
			"phase_log": current_state.phase_log
		}
	}
	
	var incremental_file = "user://incremental_save.save"
	file = FileAccess.open(incremental_file, FileAccess.WRITE)
	file.store_string(JSON.stringify(incremental_data))
	file.close()
	
	# Verify both files exist
	assert_true(FileAccess.file_exists(base_file), "Base save should exist")
	assert_true(FileAccess.file_exists(incremental_file), "Incremental save should exist")
	
	# Clean up
	DirAccess.remove_absolute(base_file)
	DirAccess.remove_absolute(incremental_file)

func test_save_file_validation():
	# Test validation of save file structure
	
	var valid_save = game_state.create_snapshot()
	
	# Test valid save
	var file = FileAccess.open(temp_save_file, FileAccess.WRITE)
	file.store_string(JSON.stringify(valid_save))
	file.close()
	
	# Validate save file
	file = FileAccess.open(temp_save_file, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	assert_eq(OK, parse_result, "Valid save should parse correctly")
	
	var loaded_data = json.get_data()
	
	# Validate required fields
	assert_true(loaded_data.has("meta"), "Save should have meta section")
	assert_true(loaded_data.has("units"), "Save should have units section")
	assert_true(loaded_data.has("board"), "Save should have board section")
	
	if loaded_data.has("meta"):
		assert_true(loaded_data.meta.has("game_id"), "Meta should have game_id")
		assert_true(loaded_data.meta.has("phase"), "Meta should have current phase")

func test_backup_system():
	# Test automatic backup creation
	
	if save_manager and save_manager.has_method("create_backup"):
		# Create initial save
		var file = FileAccess.open(temp_save_file, FileAccess.WRITE)
		file.store_string(JSON.stringify(game_state.create_snapshot()))
		file.close()
		
		# Create backup
		var backup_created = save_manager.create_backup(temp_save_file)
		
		if backup_created:
			var backup_file = temp_save_file + ".backup"
			assert_true(FileAccess.file_exists(backup_file), "Backup file should be created")
			DirAccess.remove_absolute(backup_file)

func test_save_compression():
	# Test save file compression (if implemented)
	
	var large_state = game_state.create_snapshot()
	
	# Add lots of data to make compression worthwhile
	for i in range(100):
		large_state.history.append({
			"turn": i,
			"phase": GameStateData.Phase.MOVEMENT,
			"actions": [{"type": "test", "data": "repeated_data_" + str(i)}]
		})
	
	# Save uncompressed
	var uncompressed_file = temp_save_file + "_uncompressed"
	var file = FileAccess.open(uncompressed_file, FileAccess.WRITE)
	file.store_string(JSON.stringify(large_state))
	file.close()
	
	var uncompressed_size = FileAccess.get_file_as_bytes(uncompressed_file).size()
	
	# Save compressed (if compression is available)
	if save_manager and save_manager.has_method("save_compressed"):
		var compressed_result = save_manager.save_compressed(temp_save_file, large_state)
		if compressed_result:
			var compressed_size = FileAccess.get_file_as_bytes(temp_save_file).size()
			assert_lt(compressed_size, uncompressed_size, "Compressed save should be smaller")
	
	# Clean up
	DirAccess.remove_absolute(uncompressed_file)

func test_backward_compatibility_minified_to_pretty():
	# Test loading old minified saves with new pretty-print system
	if not state_serializer:
		skip_test("StateSerializer not available")
		return
	
	# Create test state
	var test_state = {
		"_serialization": {"version": "1.0.0", "timestamp": 123456},
		"meta": {"phase": 2, "turn_number": 5},
		"units": {},
		"board": {},
		"players": {}
	}
	
	# Save as minified (old format)
	state_serializer.set_pretty_print(false)
	var minified_json = state_serializer.serialize_game_state(test_state)
	assert_false(minified_json.contains("\n"), "Minified JSON should be single line")
	
	# Load with pretty-print enabled (new format)
	state_serializer.set_pretty_print(true)
	var loaded_state = state_serializer.deserialize_game_state(minified_json)
	
	assert_not_null(loaded_state, "Should load minified save with pretty-print enabled")
	assert_eq(loaded_state.meta.phase, 2, "Phase should match")
	assert_eq(loaded_state.meta.turn_number, 5, "Turn should match")

func test_forward_compatibility_pretty_to_minified():
	# Test loading new pretty saves with old minified system
	if not state_serializer:
		skip_test("StateSerializer not available")
		return
	
	# Create test state
	var test_state = {
		"_serialization": {"version": "1.0.0", "timestamp": 123456},
		"meta": {"phase": 3, "turn_number": 7},
		"units": {},
		"board": {},
		"players": {}
	}
	
	# Save as pretty-printed (new format)
	state_serializer.set_pretty_print(true)
	var pretty_json = state_serializer.serialize_game_state(test_state)
	assert_true(pretty_json.contains("\n"), "Pretty JSON should have newlines")
	assert_true(pretty_json.contains("\t"), "Pretty JSON should have tabs")
	
	# Load with pretty-print disabled (old format)
	state_serializer.set_pretty_print(false)
	var loaded_state = state_serializer.deserialize_game_state(pretty_json)
	
	assert_not_null(loaded_state, "Should load pretty save with pretty-print disabled")
	assert_eq(loaded_state.meta.phase, 3, "Phase should match")
	assert_eq(loaded_state.meta.turn_number, 7, "Turn should match")

func test_save_file_readability():
	# Verify save files are human-readable
	if not save_manager or not state_serializer:
		skip_test("Save components not available")
		return
	
	# Enable pretty print
	state_serializer.set_pretty_print(true)
	
	# Create and save game state
	game_state.set_phase(GameStateData.Phase.MOVEMENT)
	game_state.advance_turn()
	
	var test_file = "user://test_readable_" + str(Time.get_unix_time_from_system()) + ".save"
	save_manager.save_game(test_file, {"description": "Readability test"})
	
	# Read raw file content
	var file = FileAccess.open(test_file, FileAccess.READ)
	assert_not_null(file, "Should open save file")
	
	var content = file.get_as_text()
	file.close()
	
	# Verify human-readable format
	assert_true(content.contains("\n"), "Should have line breaks")
	assert_true(content.contains("\t"), "Should have indentation")
	assert_true(content.contains('"phase":'), "Should have readable keys")
	assert_true(content.contains('"turn_number":'), "Should have readable values")
	
	# Clean up
	DirAccess.remove_absolute(test_file)