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
signal export_completed(file_path: String)
signal export_failed(error: String)
signal import_completed(file_path: String)
signal import_failed(error: String)

const SAVE_EXTENSION = ".w40ksave"
const METADATA_EXTENSION = ".meta"
const BACKUP_EXTENSION = ".backup"
const EXPORT_EXTENSION = ".w40kexport"
const WEB_STORAGE_PREFIX = "w40k_save_"

# SAVE-16: Multiple save slots
const MAX_SAVE_SLOTS = 5

var save_directory: String = "res://saves/"
var autosave_directory: String = "res://saves/autosaves/"
var backup_directory: String = "res://saves/backups/"

# Browser storage mode
var is_web_platform: bool = false

var autosave_enabled: bool = true
var autosave_interval: float = 300.0  # 5 minutes
var max_autosaves: int = 10
var max_backups: int = 5

# P3-112: Event-driven autosave settings
var autosave_on_round_end: bool = true      # Save when a battle round completes
var autosave_on_phase_transition: bool = false  # Save at every phase transition (off by default to avoid spam)

var autosave_timer: Timer = null
var last_save_path: String = ""
var _last_autosave_phase: int = -1  # Track last phase to avoid duplicate saves
var _autosave_deferred_event: String = ""  # SAVE-6: Deferred autosave event tag when AI was thinking
var _autosave_deferred_metadata: Dictionary = {}  # SAVE-6: Deferred autosave metadata

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
	_connect_phase_signals()

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

# P3-112: Connect to PhaseManager signals for event-driven autosave
func _connect_phase_signals() -> void:
	var phase_manager = get_node_or_null("/root/PhaseManager")
	if phase_manager:
		phase_manager.phase_completed.connect(_on_phase_completed_autosave)
		phase_manager.phase_changed.connect(_on_phase_changed_autosave)
		print("SaveLoadManager: Connected to PhaseManager for event-driven autosave")
	else:
		print("SaveLoadManager: PhaseManager not found, event-driven autosave disabled")

	# SAVE-6: Connect to AIPlayer.ai_turn_ended to flush deferred autosaves
	var ai_player = get_node_or_null("/root/AIPlayer")
	if ai_player:
		ai_player.ai_turn_ended.connect(_on_ai_turn_ended_flush_autosave)
		print("SaveLoadManager: Connected to AIPlayer.ai_turn_ended for deferred autosave (SAVE-6)")

# SAVE-6: Check if AI is currently thinking — guards autosave to avoid capturing incomplete state
func _is_ai_thinking() -> bool:
	var ai_player = get_node_or_null("/root/AIPlayer")
	if ai_player and ai_player.has_method("is_thinking"):
		return ai_player.is_thinking()
	return false

# SAVE-6: When AI turn ends, flush any deferred autosave
func _on_ai_turn_ended_flush_autosave(_player: int, _action_summary: Array) -> void:
	if _autosave_deferred_event != "":
		print("SaveLoadManager: SAVE-6 AI turn ended — flushing deferred autosave: %s" % _autosave_deferred_event)
		_perform_event_autosave(_autosave_deferred_event, _autosave_deferred_metadata)
		_autosave_deferred_event = ""
		_autosave_deferred_metadata = {}

# P3-112: Handle phase completion for round-end autosave
func _on_phase_completed_autosave(completed_phase: int) -> void:
	if not autosave_on_round_end:
		return

	# Auto-save at round end: when SCORING phase completes and it's the end of a battle round
	# The round advances when Player 2's scoring completes (active_player switches to 1)
	if completed_phase == GameStateData.Phase.SCORING:
		var current_player = GameState.get_active_player()
		# After scoring completes, ScoringPhase already switched active_player
		# If active_player is now 1, Player 2 just finished → round ended
		if current_player == 1:
			var battle_round = GameState.get_battle_round()
			# battle_round was already incremented by ScoringPhase._handle_end_turn()
			var completed_round = battle_round - 1

			# SAVE-6: Defer autosave if AI is mid-action to avoid capturing incomplete state
			var event_tag = "round_end"
			var event_meta = {"event": "round_end", "battle_round": completed_round}
			if _is_ai_thinking():
				print("SaveLoadManager: SAVE-6 Round %d completed but AI is thinking — deferring autosave" % completed_round)
				_autosave_deferred_event = event_tag
				_autosave_deferred_metadata = event_meta
				return

			print("SaveLoadManager: Round %d completed — performing round-end autosave" % completed_round)
			_perform_event_autosave(event_tag, event_meta)

# P3-112: Handle phase transitions for phase-transition autosave
func _on_phase_changed_autosave(new_phase: int) -> void:
	if not autosave_on_phase_transition:
		return

	# Only autosave for in-game phases (COMMAND through SCORING), not pre-game phases
	var in_game_phases = [
		GameStateData.Phase.COMMAND,
		GameStateData.Phase.MOVEMENT,
		GameStateData.Phase.SHOOTING,
		GameStateData.Phase.CHARGE,
		GameStateData.Phase.FIGHT,
		GameStateData.Phase.SCORING,
	]

	if new_phase not in in_game_phases:
		return

	# Avoid duplicate saves (e.g. if round_end already saved at SCORING completion)
	if new_phase == _last_autosave_phase:
		return
	_last_autosave_phase = new_phase

	var phase_name = GameStateData.Phase.keys()[new_phase] if new_phase < GameStateData.Phase.size() else "UNKNOWN"
	var active_player = GameState.get_active_player()
	var battle_round = GameState.get_battle_round()

	# SAVE-6: Defer autosave if AI is mid-action to avoid capturing incomplete state
	var event_tag = "phase_%s" % phase_name.to_lower()
	var event_meta = {
		"event": "phase_transition",
		"phase": phase_name,
		"active_player": active_player,
		"battle_round": battle_round
	}
	if _is_ai_thinking():
		print("SaveLoadManager: SAVE-6 Phase transition to %s but AI is thinking — deferring autosave" % phase_name)
		_autosave_deferred_event = event_tag
		_autosave_deferred_metadata = event_meta
		return

	print("SaveLoadManager: Phase transition to %s — performing phase autosave" % phase_name)
	_perform_event_autosave(event_tag, event_meta)

# P3-112: Perform an event-driven autosave with a descriptive filename
func _perform_event_autosave(event_tag: String, event_metadata: Dictionary) -> bool:
	if not autosave_enabled:
		print("SaveLoadManager: Autosave disabled, skipping event autosave for: %s" % event_tag)
		return false

	var battle_round = GameState.get_battle_round()
	var active_player = GameState.get_active_player()
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-")

	var autosave_name = "autosave_R%d_P%d_%s_%s" % [battle_round, active_player, event_tag, timestamp]
	var autosave_path = autosave_directory + autosave_name + SAVE_EXTENSION

	var metadata = {
		"type": "autosave",
		"auto_generated": true,
		"trigger": event_tag
	}
	metadata.merge(event_metadata)

	print("SaveLoadManager: Event autosave → %s" % autosave_name)
	var success = _save_game_to_path(autosave_path, metadata)
	if success:
		emit_signal("autosave_completed", autosave_path)
		_manage_autosave_count()

	return success

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

# SAVE-16: Get info about a save slot (empty dict if slot is empty)
func get_slot_info(slot: int) -> Dictionary:
	var save_path = save_directory + "slot_%d%s" % [slot, SAVE_EXTENSION]
	if not FileAccess.file_exists(save_path):
		return {}
	var metadata = _load_metadata(save_path)
	return {
		"slot": slot,
		"file_path": save_path,
		"metadata": metadata,
		"display_name": "slot_%d" % slot
	}

# SAVE-16: Get info for all save slots
func get_all_slot_info() -> Array:
	var slots = []
	for i in range(1, MAX_SAVE_SLOTS + 1):
		slots.append(get_slot_info(i))
	return slots

# SAVE-16: Check if a slot has a save
func slot_has_save(slot: int) -> bool:
	var save_path = save_directory + "slot_%d%s" % [slot, SAVE_EXTENSION]
	return FileAccess.file_exists(save_path)

# SAVE-16: Delete a save slot
func delete_slot(slot: int) -> bool:
	var save_path = save_directory + "slot_%d%s" % [slot, SAVE_EXTENSION]
	var meta_path = save_path.replace(SAVE_EXTENSION, METADATA_EXTENSION)
	var success = true
	if FileAccess.file_exists(save_path):
		var error = DirAccess.remove_absolute(save_path)
		if error != OK:
			success = false
	if FileAccess.file_exists(meta_path):
		DirAccess.remove_absolute(meta_path)
	print("SaveLoadManager: SAVE-16 Deleted slot %d: %s" % [slot, str(success)])
	return success

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

	# SAVE-6: Skip timer-based autosave if AI is mid-action to avoid capturing incomplete state
	if _is_ai_thinking():
		print("SaveLoadManager: SAVE-6 Timer autosave skipped — AI is thinking")
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

# P3-112: Event autosave settings
func set_autosave_on_round_end(enabled: bool) -> void:
	autosave_on_round_end = enabled
	print("SaveLoadManager: autosave_on_round_end = %s" % str(enabled))

func set_autosave_on_phase_transition(enabled: bool) -> void:
	autosave_on_phase_transition = enabled
	print("SaveLoadManager: autosave_on_phase_transition = %s" % str(enabled))

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
		# SAVE-5: Can't check synchronously on web — use check_save_exists_async()
		# or check the cached save list in SaveLoadDialog._save_exists_in_cache()
		print("SaveLoadManager: SAVE-5 save_exists() called on web for '%s' — returning false (use async check instead)" % sanitized_name)
		return false

	var save_path = save_directory + sanitized_name + SAVE_EXTENSION
	return FileAccess.file_exists(save_path)

# SAVE-5: Async save existence check for web platform
# Triggers a cloud list fetch, then emits save_exists_checked with the result
signal save_exists_checked(save_name: String, exists: bool)

func check_save_exists_async(file_name: String) -> void:
	var sanitized_name = _sanitize_filename(file_name)

	if not is_web_platform:
		# Desktop: check synchronously and emit immediately
		var exists = save_exists(sanitized_name)
		emit_signal("save_exists_checked", sanitized_name, exists)
		return

	if not CloudStorage:
		print("SaveLoadManager: SAVE-5 CloudStorage not available for async check")
		emit_signal("save_exists_checked", sanitized_name, false)
		return

	# Request saves list and check when received
	var _check_name = sanitized_name
	var _on_list_received: Callable
	_on_list_received = func(saves: Array) -> void:
		# Disconnect one-shot handler
		if save_files_received.is_connected(_on_list_received):
			save_files_received.disconnect(_on_list_received)
		var found = false
		for save_info in saves:
			var display_name = save_info.get("display_name", "")
			if display_name == _check_name or display_name == _check_name + SAVE_EXTENSION:
				found = true
				break
		print("SaveLoadManager: SAVE-5 Async check for '%s': exists=%s" % [_check_name, str(found)])
		emit_signal("save_exists_checked", _check_name, found)

	save_files_received.connect(_on_list_received)
	CloudStorage.list_saves()

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
	# P2-92: Include AI player info in metadata for save file display
	var game_config = GameState.state.get("meta", {}).get("game_config", {})
	var p1_type = game_config.get("player1_type", "HUMAN")
	var p2_type = game_config.get("player2_type", "HUMAN")
	# SAVE-15: Detect if current game is a multiplayer session
	var game_meta = GameState.state.get("meta", {})
	var is_mp = game_meta.get("from_multiplayer_lobby", false) or game_meta.get("from_web_lobby", false)
	var metadata = {
		"version": StateSerializer.CURRENT_VERSION if StateSerializer else "1.1.0",
		"created_at": Time.get_unix_time_from_system(),
		"game_state": {
			"turn": GameState.get_turn_number(),
			"phase": GameState.get_current_phase(),
			"active_player": GameState.get_active_player(),
			"game_id": GameState.state.get("meta", {}).get("game_id", ""),
			"player1_type": p1_type,
			"player2_type": p2_type,
			# SAVE-13: Include AI difficulty in metadata for save file display
			"player1_difficulty": game_config.get("player1_difficulty", -1) if p1_type == "AI" else -1,
			"player2_difficulty": game_config.get("player2_difficulty", -1) if p2_type == "AI" else -1,
			# SAVE-15: Mark whether this save came from a multiplayer session
			"is_multiplayer": is_mp
		},
		"save_info": {
			"save_type": custom_metadata.get("type", "manual"),
			"description": custom_metadata.get("description", ""),
			"tags": custom_metadata.get("tags", [])
		},
		# SAVE-11: Preview data for save file browser
		"preview": _build_preview_data()
	}

	# Add custom metadata
	for key in custom_metadata:
		if not metadata.has(key):
			metadata[key] = custom_metadata[key]

	return metadata

# SAVE-11: Build preview data from current game state for save file browser
func _build_preview_data() -> Dictionary:
	var preview = {
		"players": {},
		"battle_round": GameState.state.get("meta", {}).get("battle_round", 1)
	}

	# Gather per-player data
	for player_id in ["1", "2"]:
		var player_num = int(player_id)
		var faction_data = GameState.state.get("factions", {}).get(player_id, {})
		var player_data = GameState.state.get("players", {}).get(player_id, {})

		var total_units = 0
		var alive_units = 0
		var total_models = 0
		var alive_models = 0
		var unit_names = []

		for unit_id in GameState.state.get("units", {}):
			var unit = GameState.state.units[unit_id]
			if int(unit.get("owner", 0)) != player_num:
				continue
			total_units += 1
			var unit_alive = false
			var models = unit.get("models", [])
			for model in models:
				total_models += 1
				if model.get("alive", true):
					alive_models += 1
					unit_alive = true
			if unit_alive:
				alive_units += 1
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			unit_names.append(unit_name)

		preview.players[player_id] = {
			"faction": faction_data.get("name", "Unknown"),
			"detachment": faction_data.get("detachment", ""),
			"points": faction_data.get("points", 0),
			"vp": player_data.get("vp", 0),
			"primary_vp": player_data.get("primary_vp", 0),
			"secondary_vp": player_data.get("secondary_vp", 0),
			"cp": player_data.get("cp", 0),
			"total_units": total_units,
			"alive_units": alive_units,
			"total_models": total_models,
			"alive_models": alive_models,
			"unit_names": unit_names
		}

	print("SaveLoadManager: SAVE-11 Built preview data: %s" % str(preview))
	return preview

# SAVE-11: Extract preview data from a save file (for saves without preview metadata)
func extract_preview_from_save(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {}

	var serialized_data = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(serialized_data) != OK:
		return {}

	var data = json.data
	if not data is Dictionary:
		return {}

	var preview = {
		"players": {},
		"battle_round": data.get("meta", {}).get("battle_round", 1)
	}

	var units = data.get("units", {})
	var players = data.get("players", {})
	var factions = data.get("factions", {})

	for player_id in ["1", "2"]:
		var player_num = int(player_id)
		var faction_data = factions.get(player_id, {})
		var player_data = players.get(player_id, {})

		var total_units = 0
		var alive_units = 0
		var total_models = 0
		var alive_models = 0
		var unit_names = []

		for unit_id in units:
			var unit = units[unit_id]
			if int(unit.get("owner", 0)) != player_num:
				continue
			total_units += 1
			var unit_alive = false
			var models = unit.get("models", [])
			for model in models:
				total_models += 1
				if model.get("alive", true):
					alive_models += 1
					unit_alive = true
			if unit_alive:
				alive_units += 1
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			unit_names.append(unit_name)

		preview.players[player_id] = {
			"faction": faction_data.get("name", "Unknown"),
			"detachment": faction_data.get("detachment", ""),
			"points": faction_data.get("points", 0),
			"vp": player_data.get("vp", 0),
			"primary_vp": player_data.get("primary_vp", 0),
			"secondary_vp": player_data.get("secondary_vp", 0),
			"cp": player_data.get("cp", 0),
			"total_units": total_units,
			"alive_units": alive_units,
			"total_models": total_models,
			"alive_models": alive_models,
			"unit_names": unit_names
		}

	return preview

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
		"version": StateSerializer.CURRENT_VERSION if StateSerializer else "1.1.0",
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

# ============================================================================
# SAVE-19: Export/Import — Portable format for sharing save files
# ============================================================================

# Export a save file (or current game) to a portable .w40kexport file.
# The export bundles game data + metadata into a single human-readable JSON
# file that can be shared between players and imported on any machine.
func export_save(export_path: String, source_save_path: String = "") -> bool:
	print("SaveLoadManager: SAVE-19 export_save to: %s (source: %s)" % [export_path, source_save_path])

	var game_state: Dictionary
	var save_metadata: Dictionary

	if source_save_path.is_empty():
		# Export current game state directly
		game_state = GameState.create_snapshot()
		save_metadata = _create_save_metadata({"type": "export"})
	else:
		# Export from an existing save file
		if not FileAccess.file_exists(source_save_path):
			var error = "Source save file not found: %s" % source_save_path
			print("SaveLoadManager: SAVE-19 ERROR — %s" % error)
			emit_signal("export_failed", error)
			return false

		# Read and deserialize the source save
		var file = FileAccess.open(source_save_path, FileAccess.READ)
		if not file:
			var error = "Failed to open source save: %s" % source_save_path
			print("SaveLoadManager: SAVE-19 ERROR — %s" % error)
			emit_signal("export_failed", error)
			return false

		var serialized_data = file.get_as_text()
		file.close()

		game_state = StateSerializer.deserialize_game_state(serialized_data)
		if game_state.is_empty():
			var error = "Failed to deserialize source save"
			print("SaveLoadManager: SAVE-19 ERROR — %s" % error)
			emit_signal("export_failed", error)
			return false

		save_metadata = _load_metadata(source_save_path)
		if save_metadata.is_empty():
			save_metadata = _create_save_metadata({"type": "export"})

	if game_state.is_empty():
		var error = "Game state is empty — nothing to export"
		print("SaveLoadManager: SAVE-19 ERROR — %s" % error)
		emit_signal("export_failed", error)
		return false

	# Build the portable export envelope
	var export_data = {
		"_export": {
			"format": "w40k_portable_save",
			"format_version": "1.0.0",
			"exported_at": Time.get_datetime_string_from_system(),
			"exported_from_version": StateSerializer.CURRENT_VERSION if StateSerializer else "1.1.0",
			"source_file": source_save_path.get_file() if not source_save_path.is_empty() else "live_game"
		},
		"metadata": save_metadata,
		"game_data": StateSerializer.serialize_game_state(game_state)
	}

	# Verify game_data serialized successfully
	if export_data["game_data"].is_empty():
		var error = "Failed to serialize game state for export"
		print("SaveLoadManager: SAVE-19 ERROR — %s" % error)
		emit_signal("export_failed", error)
		return false

	# Write as pretty-printed JSON (always human-readable for portability)
	var export_json = JSON.stringify(export_data, "\t")

	var out_file = FileAccess.open(export_path, FileAccess.WRITE)
	if not out_file:
		var error = "Failed to open export file for writing: %s (Error: %s)" % [export_path, str(FileAccess.get_open_error())]
		print("SaveLoadManager: SAVE-19 ERROR — %s" % error)
		emit_signal("export_failed", error)
		return false

	out_file.store_string(export_json)
	out_file.close()

	print("SaveLoadManager: SAVE-19 Exported save to %s (%d bytes)" % [export_path, export_json.length()])
	emit_signal("export_completed", export_path)
	return true

# Import a portable .w40kexport file and load it into the game.
func import_save(import_path: String) -> bool:
	print("SaveLoadManager: SAVE-19 import_save from: %s" % import_path)

	if not FileAccess.file_exists(import_path):
		var error = "Import file not found: %s" % import_path
		print("SaveLoadManager: SAVE-19 ERROR — %s" % error)
		emit_signal("import_failed", error)
		return false

	var file = FileAccess.open(import_path, FileAccess.READ)
	if not file:
		var error = "Failed to open import file: %s" % import_path
		print("SaveLoadManager: SAVE-19 ERROR — %s" % error)
		emit_signal("import_failed", error)
		return false

	var raw_text = file.get_as_text()
	file.close()

	if raw_text.is_empty():
		var error = "Import file is empty"
		print("SaveLoadManager: SAVE-19 ERROR — %s" % error)
		emit_signal("import_failed", error)
		return false

	# Parse the export envelope
	var json = JSON.new()
	var parse_result = json.parse(raw_text)
	if parse_result != OK:
		var error = "Invalid export file — JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		print("SaveLoadManager: SAVE-19 ERROR — %s" % error)
		emit_signal("import_failed", error)
		return false

	var export_data = json.data
	if not export_data is Dictionary:
		var error = "Invalid export file — root is not a Dictionary"
		print("SaveLoadManager: SAVE-19 ERROR — %s" % error)
		emit_signal("import_failed", error)
		return false

	# Validate export envelope
	if not export_data.has("_export") or not export_data.has("game_data"):
		var error = "Invalid export file — missing _export header or game_data"
		print("SaveLoadManager: SAVE-19 ERROR — %s" % error)
		emit_signal("import_failed", error)
		return false

	var export_header = export_data["_export"]
	if export_header.get("format", "") != "w40k_portable_save":
		var error = "Unknown export format: %s" % export_header.get("format", "(none)")
		print("SaveLoadManager: SAVE-19 ERROR — %s" % error)
		emit_signal("import_failed", error)
		return false

	print("SaveLoadManager: SAVE-19 Export file valid — format_version=%s, exported_at=%s, source=%s" % [
		export_header.get("format_version", "?"),
		export_header.get("exported_at", "?"),
		export_header.get("source_file", "?")
	])

	# The game_data field is the serialized game state string (JSON or compressed)
	var game_data_string = export_data["game_data"]
	if not game_data_string is String or game_data_string.is_empty():
		var error = "Export file has empty or invalid game_data"
		print("SaveLoadManager: SAVE-19 ERROR — %s" % error)
		emit_signal("import_failed", error)
		return false

	# Deserialize using StateSerializer (handles compression, migration, validation)
	var game_state = StateSerializer.deserialize_game_state(game_data_string)
	if game_state.is_empty():
		var error = "Failed to deserialize imported game data"
		print("SaveLoadManager: SAVE-19 ERROR — %s" % error)
		emit_signal("import_failed", error)
		return false

	# Load into GameState
	print("SaveLoadManager: SAVE-19 Loading imported state into GameState...")
	GameState.load_from_snapshot(game_state)

	var metadata = export_data.get("metadata", {})
	emit_signal("import_completed", import_path)
	emit_signal("load_completed", import_path, metadata)
	print("SaveLoadManager: SAVE-19 Import successful from %s" % import_path)

	# Sync with multiplayer clients if in networked game
	if NetworkManager and NetworkManager.is_networked():
		print("SaveLoadManager: SAVE-19 Multiplayer detected — syncing imported state")
		NetworkManager.sync_loaded_state()

	return true

# Export a selected save from the save list to a user-chosen path.
# Convenience method that derives the source save path from a save name.
func export_save_by_name(save_name: String, export_path: String) -> bool:
	var sanitized_name = _sanitize_filename(save_name)
	var source_path = save_directory + sanitized_name + SAVE_EXTENSION
	return export_save(export_path, source_path)

# Get the default export directory (user's Documents or home folder)
func get_default_export_directory() -> String:
	var home = OS.get_environment("HOME")
	if home.is_empty():
		home = OS.get_environment("USERPROFILE")  # Windows fallback
	if home.is_empty():
		return "res://saves/"

	# Prefer Documents folder
	var docs_path = home.path_join("Documents")
	if DirAccess.dir_exists_absolute(docs_path):
		return docs_path
	return home

# Debug methods
func print_save_info() -> void:
	var save_files = get_save_files()
	print("=== Save File Info ===")
	print("Save directory: %s" % save_directory)
	print("Total save files: %d" % save_files.size())
	print("Autosave enabled: %s" % str(autosave_enabled))
	print("Autosave interval: %.1f seconds" % autosave_interval)
	print("Autosave on round end: %s" % str(autosave_on_round_end))
	print("Autosave on phase transition: %s" % str(autosave_on_phase_transition))
	print("Last save: %s" % last_save_path)

	for save_info in save_files:
		print("  - %s (Turn %d, Phase %s)" % [
			save_info.display_name,
			save_info.metadata.get("game_state", {}).get("turn", 0),
			str(save_info.metadata.get("game_state", {}).get("phase", "Unknown"))
		])
