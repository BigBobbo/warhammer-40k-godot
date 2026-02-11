extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# SaveLoadManager - High-level interface for game save and load operations
# Provides comprehensive save file management with metadata and validation
# Desktop: file system saves, Web: cloud storage via CloudStorage autoload

signal save_completed(file_path: String, metadata: Dictionary)
signal load_completed(file_path: String, metadata: Dictionary)
signal save_failed(error: String)
signal load_failed(error: String)
signal autosave_completed(file_path: String)
signal save_files_received(save_files: Array)
signal delete_completed(save_name: String)

const SAVE_EXTENSION = ".w40ksave"
const METADATA_EXTENSION = ".meta"
const BACKUP_EXTENSION = ".backup"
const WEB_STORAGE_PREFIX = "w40k_save_"

var save_directory: String = "res://saves/"
var autosave_directory: String = "res://saves/autosaves/"
var backup_directory: String = "res://saves/backups/"

# Browser storage mode
var is_web_platform: bool = false

var autosave_enabled: bool = true
var autosave_interval: float = 300.0  # 5 minutes
var max_autosaves: int = 10
var max_backups: int = 5

var autosave_timer: Timer = null
var last_save_path: String = ""

func _ready() -> void:
	is_web_platform = OS.has_feature("web")

	if is_web_platform:
		print("SaveLoadManager: Running on web platform - using cloud storage")
		# On web, we use cloud storage instead of file system
		save_directory = "cloud://"
		autosave_directory = "cloud://autosaves/"
		backup_directory = "cloud://backups/"
		# Connect to CloudStorage signals
		_connect_cloud_signals()
	else:
		_initialize_directories()

	_setup_autosave_timer()

func _connect_cloud_signals() -> void:
	if not CloudStorage:
		print("SaveLoadManager: WARNING - CloudStorage autoload not available")
		return

	CloudStorage.save_uploaded.connect(_on_cloud_save_uploaded)
	CloudStorage.save_downloaded.connect(_on_cloud_save_downloaded)
	CloudStorage.saves_list_received.connect(_on_cloud_saves_list_received)
	CloudStorage.save_deleted.connect(_on_cloud_save_deleted)
	CloudStorage.request_failed.connect(_on_cloud_request_failed)
	print("SaveLoadManager: Connected to CloudStorage signals")

func _initialize_directories() -> void:
	# Create directories in the project folder (res://)
	var dir = DirAccess.open("res://")
	if dir:
		print("SaveLoadManager: Current res:// directory: ", dir.get_current_dir())
		print("SaveLoadManager: Project directory path: ", ProjectSettings.globalize_path("res://"))

		if not dir.dir_exists("saves"):
			var result = dir.make_dir("saves")
			print("SaveLoadManager: Creating saves directory, result: ", result)

		if not dir.dir_exists("saves/autosaves"):
			var result = dir.make_dir_recursive("saves/autosaves")
			print("SaveLoadManager: Creating autosaves directory, result: ", result)

		if not dir.dir_exists("saves/backups"):
			var result = dir.make_dir_recursive("saves/backups")
			print("SaveLoadManager: Creating backups directory, result: ", result)

		print("SaveLoadManager: Initialized save directories in project folder")
		print("SaveLoadManager: Save files will be stored at: ", ProjectSettings.globalize_path("res://saves/"))
	else:
		print("SaveLoadManager: ERROR - Could not open res:// directory")

func _setup_autosave_timer() -> void:
	autosave_timer = Timer.new()
	autosave_timer.wait_time = autosave_interval
	autosave_timer.timeout.connect(_on_autosave_timer_timeout)
	autosave_timer.autostart = false
	add_child(autosave_timer)

# Main save/load interface
func save_game(file_name: String, metadata: Dictionary = {}) -> bool:
	var sanitized_name = _sanitize_filename(file_name)

	if is_web_platform:
		_save_game_to_cloud(sanitized_name, metadata)
		# Returns true to indicate the async operation was initiated
		return true

	var save_path = save_directory + sanitized_name + SAVE_EXTENSION
	return _save_game_to_path(save_path, metadata)

func load_game(file_name: String, owner_id: String = "") -> bool:
	var sanitized_name = _sanitize_filename(file_name)

	if is_web_platform:
		_load_game_from_cloud(sanitized_name, owner_id)
		# Returns true to indicate the async operation was initiated
		return true

	var save_path = save_directory + sanitized_name + SAVE_EXTENSION
	return _load_game_from_path(save_path)

func save_game_to_slot(slot: int, metadata: Dictionary = {}) -> bool:
	var save_path = save_directory + "slot_%d%s" % [slot, SAVE_EXTENSION]
	return _save_game_to_path(save_path, metadata)

func load_game_from_slot(slot: int) -> bool:
	var save_path = save_directory + "slot_%d%s" % [slot, SAVE_EXTENSION]
	return _load_game_from_path(save_path)

func quick_save() -> bool:
	if is_web_platform:
		_save_game_to_cloud("quicksave", {"type": "quicksave"})
		return true

	var save_path = save_directory + "quicksave" + SAVE_EXTENSION
	print("SaveLoadManager: Attempting quick save to: ", save_path)
	print("SaveLoadManager: Full path: ", ProjectSettings.globalize_path(save_path))
	var metadata = {"type": "quicksave"}
	return _save_game_to_path(save_path, metadata)

func quick_load() -> bool:
	if is_web_platform:
		_load_game_from_cloud("quicksave")
		return true

	var save_path = save_directory + "quicksave" + SAVE_EXTENSION
	return _load_game_from_path(save_path)

# Core save/load implementation
func _save_game_to_path(file_path: String, metadata: Dictionary = {}) -> bool:
	print("SaveLoadManager: _save_game_to_path called with: ", file_path)

	# Create backup if file exists
	if FileAccess.file_exists(file_path):
		_create_backup(file_path)

	# Prepare metadata
	var save_metadata = _create_save_metadata(metadata)
	print("SaveLoadManager: Save metadata: ", save_metadata)

	# Get current game state
	var game_state = GameState.create_snapshot()
	print("SaveLoadManager: Game state size: ", game_state.size())
	if game_state.is_empty():
		print("SaveLoadManager: ERROR - Game state is empty")
		emit_signal("save_failed", "Failed to get game state")
		return false

	# Serialize using StateSerializer
	if not StateSerializer:
		print("SaveLoadManager: ERROR - StateSerializer not available")
		emit_signal("save_failed", "StateSerializer not available")
		return false

	print("SaveLoadManager: Calling StateSerializer.serialize_game_state")
	var serialized_data = StateSerializer.serialize_game_state(game_state)
	print("SaveLoadManager: Serialized data length: ", serialized_data.length())
	if serialized_data.is_empty():
		print("SaveLoadManager: ERROR - Failed to serialize game state")
		emit_signal("save_failed", "Failed to serialize game state")
		return false

	# Write save file
	print("SaveLoadManager: Opening file for writing: ", file_path)
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		var error = "Failed to open save file for writing: " + file_path + " (Error: " + str(FileAccess.get_open_error()) + ")"
		print("SaveLoadManager: ERROR - ", error)
		emit_signal("save_failed", error)
		return false

	print("SaveLoadManager: Writing serialized data to file")
	file.store_string(serialized_data)
	file.close()

	# Write metadata file
	_save_metadata(file_path, save_metadata)

	last_save_path = file_path
	emit_signal("save_completed", file_path, save_metadata)
	print("SaveLoadManager: Game saved successfully to %s" % file_path)
	return true

func _load_game_from_path(file_path: String) -> bool:
	print("SaveLoadManager: _load_game_from_path called with: ", file_path)
	print("SaveLoadManager: Full path: ", ProjectSettings.globalize_path(file_path))

	if not FileAccess.file_exists(file_path):
		print("SaveLoadManager: ERROR - Save file not found: ", file_path)
		emit_signal("load_failed", "Save file not found: " + file_path)
		return false

	print("SaveLoadManager: Save file exists, loading metadata...")

	# Load and validate metadata
	var metadata = _load_metadata(file_path)
	if metadata.is_empty():
		print("SaveLoadManager: WARNING - No metadata found, continuing anyway")
		# Don't fail if metadata is missing, just warn
		metadata = {"type": "unknown"}
	else:
		print("SaveLoadManager: Metadata loaded: ", metadata)

		var validation = _validate_save_metadata(metadata)
		if not validation.valid:
			print("SaveLoadManager: WARNING - Metadata validation failed: ", str(validation.errors))
			# Continue anyway for debugging

	# Read save file
	print("SaveLoadManager: Opening save file for reading...")
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print("SaveLoadManager: ERROR - Failed to open save file: ", FileAccess.get_open_error())
		emit_signal("load_failed", "Failed to open save file for reading: " + file_path)
		return false

	var serialized_data = file.get_as_text()
	file.close()
	print("SaveLoadManager: Read ", serialized_data.length(), " bytes from save file")

	# Deserialize using StateSerializer
	if not StateSerializer:
		print("SaveLoadManager: ERROR - StateSerializer not available")
		emit_signal("load_failed", "StateSerializer not available")
		return false

	print("SaveLoadManager: Deserializing game state...")
	var game_state = StateSerializer.deserialize_game_state(serialized_data)
	if game_state.is_empty():
		print("SaveLoadManager: ERROR - Failed to deserialize save data")
		emit_signal("load_failed", "Failed to deserialize save data")
		return false

	print("SaveLoadManager: Deserialized state keys: ", game_state.keys())
	if game_state.has("meta"):
		print("SaveLoadManager: Loaded game meta: ", game_state["meta"])

	# Load state into GameState
	print("SaveLoadManager: Loading snapshot into GameState...")
	print("SaveLoadManager: Snapshot has units: ", game_state.has("units"))
	if game_state.has("units"):
		print("SaveLoadManager: Units in snapshot: %d" % game_state["units"].size())
		print("SaveLoadManager: Unit IDs in snapshot: %s" % str(game_state["units"].keys()))

	GameState.load_from_snapshot(game_state)

	# Verify the load worked
	print("SaveLoadManager: Verifying load...")
	var current_state = GameState.create_snapshot()
	if current_state.has("meta"):
		print("SaveLoadManager: Current game meta after load: ", current_state["meta"])
	if current_state.has("units"):
		print("SaveLoadManager: Units in GameState after load: %d" % current_state["units"].size())
		print("SaveLoadManager: Unit IDs in GameState after load: %s" % str(current_state["units"].keys()))

	emit_signal("load_completed", file_path, metadata)
	print("SaveLoadManager: Game loaded successfully from %s" % file_path)

	# Sync state with multiplayer clients if in networked game
	print("SaveLoadManager: Checking for multiplayer...")
	print("SaveLoadManager: NetworkManager exists: ", NetworkManager != null)
	if NetworkManager:
		print("SaveLoadManager: is_networked(): ", NetworkManager.is_networked())
		print("SaveLoadManager: is_host(): ", NetworkManager.is_host())

	if NetworkManager and NetworkManager.is_networked():
		print("SaveLoadManager: *** MULTIPLAYER DETECTED - SYNCING LOADED STATE ***")
		NetworkManager.sync_loaded_state()
		print("SaveLoadManager: *** SYNC CALL COMPLETED ***")
	else:
		print("SaveLoadManager: Single-player mode or not connected - skipping sync")

	return true

# ============================================================================
# Cloud Storage Methods (Web Platform)
# ============================================================================

func _save_game_to_cloud(save_name: String, metadata: Dictionary) -> void:
	print("SaveLoadManager: [CLOUD] Saving game: ", save_name)

	# Prepare metadata
	var save_metadata = _create_save_metadata(metadata)

	# Get current game state
	var game_state = GameState.create_snapshot()
	if game_state.is_empty():
		emit_signal("save_failed", "Failed to get game state")
		return

	# Serialize
	if not StateSerializer:
		emit_signal("save_failed", "StateSerializer not available")
		return

	var serialized_data = StateSerializer.serialize_game_state(game_state)
	if serialized_data.is_empty():
		emit_signal("save_failed", "Failed to serialize game state")
		return

	# Upload to cloud
	if CloudStorage:
		CloudStorage.put_save(save_name, save_metadata, serialized_data)
		# Completion handled by _on_cloud_save_uploaded signal
	else:
		emit_signal("save_failed", "CloudStorage not available")

func _load_game_from_cloud(save_name: String, owner_id: String = "") -> void:
	print("SaveLoadManager: [CLOUD] Loading game: ", save_name, " (owner_id: ", owner_id, ")")

	# Request save from cloud
	if CloudStorage:
		if not owner_id.is_empty() and owner_id != CloudStorage.player_id:
			# Loading a shared save from another player
			CloudStorage.get_shared_save(save_name, owner_id)
		else:
			CloudStorage.get_save(save_name)
		# Completion handled by _on_cloud_save_downloaded signal
	else:
		emit_signal("load_failed", "CloudStorage not available")

func _on_cloud_save_uploaded(save_name: String) -> void:
	print("SaveLoadManager: [CLOUD] Save uploaded successfully: ", save_name)
	last_save_path = "cloud://" + save_name
	var save_metadata = _create_save_metadata({})
	emit_signal("save_completed", last_save_path, save_metadata)

func _on_cloud_save_downloaded(save_name: String, metadata: Dictionary, game_data: String) -> void:
	print("SaveLoadManager: [CLOUD] Save downloaded: ", save_name)
	print("SaveLoadManager: [CLOUD] Game data length: ", game_data.length())

	if game_data.is_empty():
		emit_signal("load_failed", "Downloaded save data is empty")
		return

	# Deserialize
	if not StateSerializer:
		emit_signal("load_failed", "StateSerializer not available")
		return

	var game_state = StateSerializer.deserialize_game_state(game_data)
	if game_state.is_empty():
		emit_signal("load_failed", "Failed to deserialize cloud save data")
		return

	print("SaveLoadManager: [CLOUD] Deserialized state keys: ", game_state.keys())

	# Load into GameState
	GameState.load_from_snapshot(game_state)

	emit_signal("load_completed", "cloud://" + save_name, metadata)
	print("SaveLoadManager: [CLOUD] Game loaded successfully: ", save_name)

	# Sync state with multiplayer clients if in networked game
	if NetworkManager and NetworkManager.is_networked():
		print("SaveLoadManager: [CLOUD] Multiplayer detected - syncing loaded state")
		NetworkManager.sync_loaded_state()

func _on_cloud_saves_list_received(saves: Array) -> void:
	print("SaveLoadManager: [CLOUD] Received %d saves from cloud" % saves.size())

	# Convert cloud save format to standard save_files format
	var save_files = []
	for save in saves:
		var metadata = save.get("metadata", {})
		if metadata is String:
			var json = JSON.new()
			if json.parse(metadata) == OK and json.data is Dictionary:
				metadata = json.data
			else:
				metadata = {}

		var save_info = {
			"file_name": save.get("save_name", "") + SAVE_EXTENSION,
			"display_name": save.get("save_name", ""),
			"file_path": "cloud://" + save.get("save_name", ""),
			"metadata": metadata,
			"ownership": save.get("ownership", "own"),
			"owner_id": save.get("owner_id", "")
		}
		save_files.append(save_info)

	# Sort by modification time (newest first)
	save_files.sort_custom(_compare_save_info_times)
	emit_signal("save_files_received", save_files)

func _on_cloud_save_deleted(save_name: String) -> void:
	print("SaveLoadManager: [CLOUD] Save deleted: ", save_name)
	emit_signal("delete_completed", save_name)

func _on_cloud_request_failed(operation: String, error: String) -> void:
	print("SaveLoadManager: [CLOUD] Request failed - %s: %s" % [operation, error])
	match operation:
		"put_save":
			emit_signal("save_failed", "Cloud save failed: " + error)
		"get_save":
			emit_signal("load_failed", "Cloud load failed: " + error)
		"list_saves":
			emit_signal("save_files_received", [])
		"delete_save":
			emit_signal("save_failed", "Cloud delete failed: " + error)

# Autosave functionality
func enable_autosave() -> void:
	autosave_enabled = true
	if autosave_timer:
		autosave_timer.start()

func disable_autosave() -> void:
	autosave_enabled = false
	if autosave_timer:
		autosave_timer.stop()

func set_autosave_interval(seconds: float) -> void:
	autosave_interval = max(60.0, seconds)  # Minimum 1 minute
	if autosave_timer:
		autosave_timer.wait_time = autosave_interval

func perform_autosave() -> bool:
	if not autosave_enabled:
		return false

	var timestamp = Time.get_datetime_string_from_system().replace(":", "-")
	var autosave_path = autosave_directory + "autosave_%s%s" % [timestamp, SAVE_EXTENSION]

	var metadata = {
		"type": "autosave",
		"auto_generated": true
	}

	var success = _save_game_to_path(autosave_path, metadata)
	if success:
		emit_signal("autosave_completed", autosave_path)
		_manage_autosave_count()

	return success

func _manage_autosave_count() -> void:
	var autosave_files = _get_autosave_files()
	if autosave_files.size() > max_autosaves:
		# Sort by modification time and remove oldest
		autosave_files.sort_custom(_compare_file_times)
		var files_to_remove = autosave_files.size() - max_autosaves

		for i in range(files_to_remove):
			var file_path = autosave_directory + autosave_files[i]
			DirAccess.remove_absolute(file_path)
			DirAccess.remove_absolute(file_path.replace(SAVE_EXTENSION, METADATA_EXTENSION))

func _get_autosave_files() -> Array:
	var files = []
	var dir = DirAccess.open(autosave_directory)

	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(SAVE_EXTENSION):
				files.append(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

	return files

# Save file management
func get_save_files() -> Array:
	if is_web_platform:
		# On web, trigger async cloud list and return empty
		# Callers should connect to save_files_received signal
		if CloudStorage:
			CloudStorage.list_saves()
		return []

	var save_files = []
	var dir = DirAccess.open(save_directory)

	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(SAVE_EXTENSION):
				var save_info = {
					"file_name": file_name,
					"display_name": file_name.replace(SAVE_EXTENSION, ""),
					"file_path": save_directory + file_name,
					"metadata": _load_metadata(save_directory + file_name)
				}
				save_files.append(save_info)
			file_name = dir.get_next()
		dir.list_dir_end()

	# Sort by modification time (newest first)
	save_files.sort_custom(_compare_save_info_times)
	return save_files

func delete_save_file(file_name: String) -> bool:
	var sanitized_name = _sanitize_filename(file_name)

	if is_web_platform:
		if CloudStorage:
			CloudStorage.delete_save(sanitized_name)
			# Completion handled by _on_cloud_save_deleted signal
			return true
		return false

	var save_path = save_directory + sanitized_name + SAVE_EXTENSION
	var meta_path = save_path.replace(SAVE_EXTENSION, METADATA_EXTENSION)

	var success = true

	# Delete save file
	if FileAccess.file_exists(save_path):
		var error = DirAccess.remove_absolute(save_path)
		if error != OK:
			success = false

	# Delete metadata file
	if FileAccess.file_exists(meta_path):
		DirAccess.remove_absolute(meta_path)

	return success

func save_exists(file_name: String) -> bool:
	var sanitized_name = _sanitize_filename(file_name)

	if is_web_platform:
		# Can't check synchronously on web - return false
		# PUT uses upsert semantics so overwriting is handled transparently
		return false

	var save_path = save_directory + sanitized_name + SAVE_EXTENSION
	return FileAccess.file_exists(save_path)

func get_save_info(file_name: String) -> Dictionary:
	var sanitized_name = _sanitize_filename(file_name)
	var save_path = save_directory + sanitized_name + SAVE_EXTENSION

	if not FileAccess.file_exists(save_path):
		return {}

	var metadata = _load_metadata(save_path)
	var file_size = FileAccess.get_file_as_bytes(save_path).size()

	return {
		"file_name": sanitized_name + SAVE_EXTENSION,
		"file_path": save_path,
		"file_size": file_size,
		"metadata": metadata,
		"exists": true
	}

# Metadata management
func _create_save_metadata(custom_metadata: Dictionary = {}) -> Dictionary:
	var metadata = {
		"version": "1.0.0",
		"created_at": Time.get_unix_time_from_system(),
		"game_state": {
			"turn": GameState.get_turn_number(),
			"phase": GameState.get_current_phase(),
			"active_player": GameState.get_active_player(),
			"game_id": GameState.state.get("meta", {}).get("game_id", "")
		},
		"save_info": {
			"save_type": custom_metadata.get("type", "manual"),
			"description": custom_metadata.get("description", ""),
			"tags": custom_metadata.get("tags", [])
		}
	}

	# Add custom metadata
	for key in custom_metadata:
		if not metadata.has(key):
			metadata[key] = custom_metadata[key]

	return metadata

func _save_metadata(save_path: String, metadata: Dictionary) -> void:
	var meta_path = save_path.replace(SAVE_EXTENSION, METADATA_EXTENSION)
	var file = FileAccess.open(meta_path, FileAccess.WRITE)

	if file:
		var json_string = JSON.stringify(metadata, "\t")
		file.store_string(json_string)
		file.close()

func _load_metadata(save_path: String) -> Dictionary:
	var meta_path = save_path.replace(SAVE_EXTENSION, METADATA_EXTENSION)

	if not FileAccess.file_exists(meta_path):
		# Try to create metadata from game state if save exists
		if FileAccess.file_exists(save_path):
			return _create_default_metadata(save_path)
		return {}

	var file = FileAccess.open(meta_path, FileAccess.READ)
	if not file:
		return {}

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_string)

	if parse_result != OK:
		return {}

	return json.data if json.data is Dictionary else {}

func _create_default_metadata(save_path: String) -> Dictionary:
	var file_time = FileAccess.get_modified_time(save_path)
	return {
		"version": "1.0.0",
		"created_at": file_time,
		"game_state": {
			"turn": 0,
			"phase": GameStateData.Phase.DEPLOYMENT,
			"active_player": 1,
			"game_id": "unknown"
		},
		"save_info": {
			"save_type": "unknown",
			"description": "Legacy save file",
			"tags": []
		}
	}

func _validate_save_metadata(metadata: Dictionary) -> Dictionary:
	var validation = {
		"valid": true,
		"errors": [],
		"warnings": []
	}

	# Check required fields
	var required_fields = ["version", "created_at", "game_state"]
	for field in required_fields:
		if not metadata.has(field):
			validation.errors.append("Missing required field: " + field)
			validation.valid = false

	return validation

# Backup management
func _create_backup(file_path: String) -> void:
	var backup_name = file_path.get_file().replace(SAVE_EXTENSION, "")
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-")
	var backup_path = backup_directory + "%s_%s%s" % [backup_name, timestamp, BACKUP_EXTENSION]

	var original_file = FileAccess.open(file_path, FileAccess.READ)
	var backup_file = FileAccess.open(backup_path, FileAccess.WRITE)

	if original_file and backup_file:
		backup_file.store_string(original_file.get_as_text())
		backup_file.close()
		original_file.close()

		_manage_backup_count()

func _manage_backup_count() -> void:
	var backup_files = []
	var dir = DirAccess.open(backup_directory)

	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(BACKUP_EXTENSION):
				backup_files.append(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

	if backup_files.size() > max_backups:
		backup_files.sort_custom(_compare_file_times)
		var files_to_remove = backup_files.size() - max_backups

		for i in range(files_to_remove):
			DirAccess.remove_absolute(backup_directory + backup_files[i])

# Utility methods
func _sanitize_filename(filename: String) -> String:
	# Remove invalid filename characters
	var sanitized = filename.strip_edges()
	var invalid_chars = ["<", ">", ":", "\"", "|", "?", "*", "/", "\\"]

	for char in invalid_chars:
		sanitized = sanitized.replace(char, "_")

	return sanitized

func _compare_file_times(a: String, b: String) -> bool:
	var time_a = FileAccess.get_modified_time(autosave_directory + a)
	var time_b = FileAccess.get_modified_time(autosave_directory + b)
	return time_a < time_b

func _compare_save_info_times(a: Dictionary, b: Dictionary) -> bool:
	var time_a = a.metadata.get("created_at", 0)
	var time_b = b.metadata.get("created_at", 0)
	return time_a > time_b  # Newest first

# Event handlers
func _on_autosave_timer_timeout() -> void:
	perform_autosave()

# Settings
func set_max_autosaves(count: int) -> void:
	max_autosaves = max(1, count)

func set_max_backups(count: int) -> void:
	max_backups = max(1, count)

func get_save_directory() -> String:
	return save_directory

func get_autosave_directory() -> String:
	return autosave_directory

func get_last_save_path() -> String:
	return last_save_path

# Debug methods
func print_save_info() -> void:
	var save_files = get_save_files()
	print("=== Save File Info ===")
	print("Save directory: %s" % save_directory)
	print("Total save files: %d" % save_files.size())
	print("Autosave enabled: %s" % str(autosave_enabled))
	print("Autosave interval: %.1f seconds" % autosave_interval)
	print("Last save: %s" % last_save_path)

	for save_info in save_files:
		print("  - %s (Turn %d, Phase %s)" % [
			save_info.display_name,
			save_info.metadata.get("game_state", {}).get("turn", 0),
			str(save_info.metadata.get("game_state", {}).get("phase", "Unknown"))
		])
