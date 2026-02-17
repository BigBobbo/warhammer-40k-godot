extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# ReplayManager - Combined game recording and replay playback system
#
# RECORDING: Hooks into GameManager.result_applied and PhaseManager.phase_changed
# to capture every action with its resulting diffs. Takes snapshots at phase
# transitions for efficient backward navigation.
#
# PLAYBACK: Applies recorded diffs to GameState to step through a game.
# Uses phase-transition snapshots to enable instant backward navigation.

# ============================================================================
# Signals
# ============================================================================

signal replay_loaded(metadata: Dictionary)
signal playback_started()
signal playback_paused()
signal playback_stopped()
signal playback_position_changed(position: int, total: int)
signal replay_event_applied(event: Dictionary)
signal replay_error(error: String)
signal recording_started()
signal recording_stopped(file_path: String)

# ============================================================================
# Enums
# ============================================================================

enum PlaybackState { STOPPED, PLAYING, PAUSED }
enum Mode { IDLE, RECORDING, PLAYBACK }

# ============================================================================
# Recording State
# ============================================================================

var is_recording: bool = false
var auto_record_ai: bool = true  # Auto-record AI vs AI games
var _recording_initial_state: Dictionary = {}
var _recording_events: Array = []
var _recording_snapshots: Array = []  # Array of {event_index, state}
var _recording_meta: Dictionary = {}
var _recording_event_index: int = 0
var _stable_replay_path: String = ""  # Stable file path for per-turn incremental saves

# ============================================================================
# Playback State
# ============================================================================

var current_replay_data: Dictionary = {}
var replay_events: Array = []
var replay_snapshots: Array = []
var initial_state: Dictionary = {}
var current_position: int = -1  # -1 means at initial state (before any events)
var playback_state: PlaybackState = PlaybackState.STOPPED
var playback_speed: float = 1.0
var auto_advance_timer: Timer = null
var current_mode: Mode = Mode.IDLE

# Noisy internal actions to skip during replay (same as GameEventLog)
const FILTERED_ACTIONS = [
	"STAGE_MODEL_MOVE",
	"UNDO_MODEL_MOVE",
	"RESET_UNIT_MOVE",
	"SELECT_UNIT",
	"DESELECT_UNIT",
]

const PHASE_NAMES = {
	GameStateData.Phase.DEPLOYMENT: "Deployment",
	GameStateData.Phase.COMMAND: "Command",
	GameStateData.Phase.MOVEMENT: "Movement",
	GameStateData.Phase.SHOOTING: "Shooting",
	GameStateData.Phase.CHARGE: "Charge",
	GameStateData.Phase.FIGHT: "Fight",
	GameStateData.Phase.SCORING: "Scoring",
	GameStateData.Phase.MORALE: "Morale",
}

const REPLAY_VERSION = "1.0.0"
const REPLAY_DIR = "user://replays/"

# ============================================================================
# Initialization
# ============================================================================

func _ready() -> void:
	_setup_auto_advance_timer()
	_ensure_replay_dir()
	_connect_recording_signals()
	print("ReplayManager: Ready (auto_record_ai=%s)" % auto_record_ai)

func _setup_auto_advance_timer() -> void:
	auto_advance_timer = Timer.new()
	auto_advance_timer.wait_time = 1.0 / playback_speed
	auto_advance_timer.one_shot = false
	auto_advance_timer.timeout.connect(_on_auto_advance_timeout)
	add_child(auto_advance_timer)

func _ensure_replay_dir() -> void:
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("replays"):
		dir.make_dir("replays")
		print("ReplayManager: Created replays directory")

func _connect_recording_signals() -> void:
	# Connect to GameManager for action results with diffs (multiplayer path)
	if has_node("/root/GameManager"):
		var game_manager = get_node("/root/GameManager")
		game_manager.result_applied.connect(_on_result_applied_for_recording)
		print("ReplayManager: Connected to GameManager.result_applied")

	# Connect to PhaseManager for phase transitions AND single-player actions
	# In single-player, actions go through BasePhase.execute_action() → PhaseManager,
	# bypassing GameManager entirely. So we also listen to phase_action_taken which
	# carries diffs attached by BasePhase as _replay_diffs.
	if has_node("/root/PhaseManager"):
		var phase_manager = get_node("/root/PhaseManager")
		phase_manager.phase_changed.connect(_on_phase_changed_for_recording)
		phase_manager.phase_action_taken.connect(_on_phase_action_taken_for_recording)
		# Listen for phase_completed to detect game end and auto-stop recording
		phase_manager.phase_completed.connect(_on_phase_completed_for_recording)
		print("ReplayManager: Connected to PhaseManager.phase_changed, phase_action_taken, phase_completed")

# ============================================================================
# Recording - Start/Stop
# ============================================================================

func start_recording() -> void:
	if is_recording:
		print("ReplayManager: Already recording")
		return

	if current_mode == Mode.PLAYBACK:
		print("ReplayManager: Cannot record during playback")
		return

	is_recording = true
	current_mode = Mode.RECORDING
	_recording_events.clear()
	_recording_snapshots.clear()
	_recording_event_index = 0

	# Capture initial state
	_recording_initial_state = GameState.create_snapshot()

	# Capture metadata
	var game_config = GameState.state.get("meta", {}).get("game_config", {})
	_recording_meta = {
		"replay_id": _generate_replay_id(),
		"created_at": Time.get_unix_time_from_system(),
		"version": REPLAY_VERSION,
		"game_id": GameState.state.get("meta", {}).get("game_id", ""),
		"game_config": game_config,
		"player1_type": game_config.get("player1_type", "HUMAN"),
		"player2_type": game_config.get("player2_type", "HUMAN"),
		"player1_faction": GameState.get_faction_name(1),
		"player2_faction": GameState.get_faction_name(2),
	}

	# Take initial snapshot at event index 0
	_recording_snapshots.append({
		"event_index": -1,
		"state": _recording_initial_state.duplicate(true)
	})

	# Build a stable file path based on game_id so per-turn saves overwrite the same file
	_stable_replay_path = _build_stable_replay_path()

	print("ReplayManager: Recording started (game_id=%s)" % _recording_meta.get("game_id", ""))
	DebugLogger.info("ReplayManager: Recording started", _recording_meta)
	emit_signal("recording_started")

func stop_recording() -> void:
	if not is_recording:
		return

	is_recording = false

	# Finalize metadata
	_recording_meta["total_events"] = _recording_events.size()
	_recording_meta["total_snapshots"] = _recording_snapshots.size()
	_recording_meta["finished_at"] = Time.get_unix_time_from_system()

	# Capture final score
	_recording_meta["final_score"] = {
		"p1_vp": GameState.state.get("players", {}).get("1", {}).get("vp", 0),
		"p2_vp": GameState.state.get("players", {}).get("2", {}).get("vp", 0),
	}
	_recording_meta["final_round"] = GameState.get_battle_round()
	_recording_meta["status"] = "complete"

	# Save to file (reuses stable path so final save overwrites incremental)
	var file_path = _save_replay_to_file()

	current_mode = Mode.IDLE
	print("ReplayManager: Recording stopped (%d events, %d snapshots)" % [
		_recording_events.size(), _recording_snapshots.size()])
	DebugLogger.info("ReplayManager: Recording stopped", {
		"events": _recording_events.size(),
		"snapshots": _recording_snapshots.size(),
		"file": file_path
	})
	emit_signal("recording_stopped", file_path)

func should_auto_record() -> bool:
	"""Check if we should auto-start recording based on player types."""
	if not auto_record_ai:
		return false
	var game_config = GameState.state.get("meta", {}).get("game_config", {})
	var p1_type = game_config.get("player1_type", "HUMAN")
	var p2_type = game_config.get("player2_type", "HUMAN")
	return p1_type == "AI" and p2_type == "AI"

func _is_multiplayer_client() -> bool:
	"""Returns true if we're a client in a multiplayer game (not host)."""
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.is_networked() and not network_manager.is_host():
		return true
	return false

# ============================================================================
# Recording - Event Capture
# ============================================================================

func _on_result_applied_for_recording(result: Dictionary) -> void:
	"""Captures actions that go through GameManager (multiplayer path).
	In single-player, GameManager is bypassed so this won't fire."""
	if not is_recording:
		return

	# In multiplayer, only record on the host to avoid duplicate events
	if _is_multiplayer_client():
		return

	# In single-player, actions go through the phase system, not GameManager.
	# We record those via _on_phase_action_taken_for_recording instead.
	# If NetworkManager is not networked, skip this path to avoid potential double-recording.
	var network_manager = get_node_or_null("/root/NetworkManager")
	if not network_manager or not network_manager.is_networked():
		return

	_record_action_event(result.get("action_type", ""), result.get("action_data", {}),
		result.get("diffs", result.get("changes", [])), result)

func _on_phase_action_taken_for_recording(action: Dictionary) -> void:
	"""Captures actions that go through the phase system (single-player path).
	In multiplayer, we use _on_result_applied_for_recording instead."""
	if not is_recording:
		return

	# In multiplayer, skip this path — we record via GameManager.result_applied instead
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.is_networked():
		return

	var action_type = action.get("type", "")

	# Skip noisy internal actions that don't meaningfully change state
	if action_type in FILTERED_ACTIONS:
		return

	# Get diffs attached by BasePhase.execute_action()
	var diffs = action.get("_replay_diffs", [])
	_record_action_event(action_type, action, diffs, action)

func _record_action_event(action_type: String, action_data: Dictionary, diffs: Array, source: Dictionary) -> void:
	"""Common recording logic used by both the GameManager and phase action paths."""
	if action_type in FILTERED_ACTIONS:
		return

	# Build the replay event
	var event = {
		"index": _recording_event_index,
		"type": "action",
		"action_type": action_type,
		"action_data": action_data.duplicate(true),
		"diffs": diffs.duplicate(true),
		"timestamp": Time.get_unix_time_from_system(),
		"phase": GameState.get_current_phase(),
		"battle_round": GameState.get_battle_round(),
		"active_player": GameState.get_active_player(),
		"description": _build_event_description(action_type, action_data, source),
	}

	# Include log text if available
	if source.has("log_text"):
		event["log_text"] = source["log_text"]
	elif action_data.has("_log_text"):
		event["log_text"] = action_data["_log_text"]

	_recording_events.append(event)
	_recording_event_index += 1

func _on_phase_changed_for_recording(new_phase: GameStateData.Phase) -> void:
	if not is_recording:
		return

	# In multiplayer, only record on the host to avoid duplicate events
	if _is_multiplayer_client():
		return

	# Record phase change event
	var event = {
		"index": _recording_event_index,
		"type": "phase_change",
		"action_type": "PHASE_CHANGE",
		"new_phase": new_phase,
		"phase_name": PHASE_NAMES.get(new_phase, "Unknown"),
		"diffs": [],  # Phase transitions are handled by the game engine
		"timestamp": Time.get_unix_time_from_system(),
		"battle_round": GameState.get_battle_round(),
		"active_player": GameState.get_active_player(),
		"description": "--- %s Phase (Round %d, P%d) ---" % [
			PHASE_NAMES.get(new_phase, "Unknown"),
			GameState.get_battle_round(),
			GameState.get_active_player()
		],
	}

	_recording_events.append(event)

	# Take a snapshot at every phase transition for backward navigation
	_recording_snapshots.append({
		"event_index": _recording_event_index,
		"state": GameState.create_snapshot()
	})

	_recording_event_index += 1

func _on_phase_completed_for_recording(phase: GameStateData.Phase) -> void:
	"""Auto-stop recording when the game ends, and save incrementally after each turn."""
	if not is_recording:
		return
	var phase_manager = get_node_or_null("/root/PhaseManager")
	if phase_manager and phase_manager.game_ended:
		print("ReplayManager: Game ended detected, auto-stopping recording")
		stop_recording()
		return

	# Save incrementally after each Scoring phase (i.e. end of each player's turn)
	# so that even incomplete games have replay data available
	if phase == GameStateData.Phase.SCORING:
		save_replay_incremental()

func save_replay_incremental() -> void:
	"""Save the current recording to disk without stopping. Used for per-turn saves
	so that incomplete games still have replay data available."""
	if not is_recording:
		return

	# Update metadata with current state (but keep status as in_progress)
	_recording_meta["total_events"] = _recording_events.size()
	_recording_meta["total_snapshots"] = _recording_snapshots.size()
	_recording_meta["last_saved_at"] = Time.get_unix_time_from_system()
	_recording_meta["status"] = "in_progress"
	_recording_meta["final_score"] = {
		"p1_vp": GameState.state.get("players", {}).get("1", {}).get("vp", 0),
		"p2_vp": GameState.state.get("players", {}).get("2", {}).get("vp", 0),
	}
	_recording_meta["final_round"] = GameState.get_battle_round()

	var replay_data = {
		"version": REPLAY_VERSION,
		"meta": _recording_meta,
		"initial_state": _recording_initial_state,
		"events": _recording_events,
		"snapshots": _recording_snapshots,
	}

	if _stable_replay_path == "":
		_stable_replay_path = _build_stable_replay_path()

	var file = FileAccess.open(_stable_replay_path, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(replay_data)
		file.store_string(json_string)
		file.close()
		print("ReplayManager: Incremental save to %s (%d events, round %s)" % [
			_stable_replay_path, _recording_events.size(), str(_recording_meta.get("final_round", "?"))])
		DebugLogger.info("ReplayManager: Incremental replay save", {
			"path": _stable_replay_path,
			"events": _recording_events.size(),
			"round": _recording_meta.get("final_round", "?")
		})
	else:
		push_error("ReplayManager: Failed incremental save to: " + _stable_replay_path)
		DebugLogger.error("ReplayManager: Failed incremental save", {"path": _stable_replay_path})

func _build_stable_replay_path() -> String:
	"""Build a stable replay file path based on game_id so incremental saves overwrite the same file."""
	var game_id = _recording_meta.get("game_id", "")
	if game_id == "":
		game_id = _generate_replay_id()
	# Sanitize game_id for use in filename
	game_id = game_id.replace("/", "_").replace("\\", "_").replace(" ", "_")
	var p1_faction = _recording_meta.get("player1_faction", "P1").replace(" ", "_")
	var p2_faction = _recording_meta.get("player2_faction", "P2").replace(" ", "_")
	return REPLAY_DIR + "replay_%s_%s_vs_%s.json" % [game_id, p1_faction, p2_faction]

func _build_event_description(action_type: String, action_data: Dictionary, result: Dictionary) -> String:
	"""Build a human-readable description of the event."""
	var player = action_data.get("player", GameState.get_active_player())
	var prefix = "P%d: " % player

	# Prefer AI description when present
	var ai_desc = action_data.get("_ai_description", "")
	if ai_desc != "":
		return prefix + ai_desc

	# Use log_text from result if available
	var log_text = result.get("log_text", action_data.get("_log_text", ""))
	if log_text != "":
		return prefix + log_text

	# Build description from action type
	var unit_id = action_data.get("unit_id", action_data.get("actor_unit_id", ""))
	var unit_name = _get_unit_name(unit_id)

	match action_type:
		"DEPLOY_UNIT":
			return prefix + "Deployed %s" % unit_name
		"CONFIRM_UNIT_MOVE":
			return prefix + "%s moved" % unit_name
		"REMAIN_STATIONARY":
			return prefix + "%s remained stationary" % unit_name
		"SHOOT":
			var target_name = _get_unit_name(action_data.get("target_unit_id", action_data.get("target_id", "")))
			return prefix + "%s shot at %s" % [unit_name, target_name]
		"FIGHT":
			var target_name = _get_unit_name(action_data.get("target_unit_id", action_data.get("target_id", "")))
			return prefix + "%s fought %s" % [unit_name, target_name]
		"CHARGE_ROLL":
			var target_name = _get_unit_name(action_data.get("target_unit_id", ""))
			return prefix + "%s charged %s" % [unit_name, target_name]
		"END_DEPLOYMENT": return prefix + "Ended Deployment Phase"
		"END_MOVEMENT": return prefix + "Ended Movement Phase"
		"END_SHOOTING": return prefix + "Ended Shooting Phase"
		"END_CHARGE": return prefix + "Ended Charge Phase"
		"END_FIGHT": return prefix + "Ended Fight Phase"
		"END_COMMAND": return prefix + "Ended Command Phase"
		"END_SCORING": return prefix + "Ended Scoring Phase"
		"END_MORALE": return prefix + "Ended Morale Phase"
		"SKIP_UNIT", "SKIP_CHARGE":
			return prefix + "Skipped %s" % unit_name
		_:
			if unit_name != "Unknown":
				return prefix + "%s: %s" % [action_type, unit_name]
			return prefix + action_type

func _get_unit_name(unit_id: String) -> String:
	if unit_id == "":
		return "Unknown"
	var units = GameState.state.get("units", {})
	var unit = units.get(unit_id, {})
	var meta = unit.get("meta", {})
	var unit_name = meta.get("name", unit.get("name", ""))
	if unit_name != "":
		return unit_name
	return unit_id

# ============================================================================
# Recording - Save to File
# ============================================================================

func _save_replay_to_file() -> String:
	var replay_data = {
		"version": REPLAY_VERSION,
		"meta": _recording_meta,
		"initial_state": _recording_initial_state,
		"events": _recording_events,
		"snapshots": _recording_snapshots,
	}

	# Reuse the stable path if we already have one (overwrites incremental saves)
	var file_path = _stable_replay_path
	if file_path == "":
		file_path = _build_stable_replay_path()

	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(replay_data)
		file.store_string(json_string)
		file.close()
		print("ReplayManager: Saved replay to %s" % file_path)
		DebugLogger.info("ReplayManager: Saved replay", {"path": file_path, "events": _recording_events.size()})
		return file_path
	else:
		var error = "Failed to save replay to: " + file_path
		push_error("ReplayManager: " + error)
		DebugLogger.error("ReplayManager: " + error, {})
		return ""

func _generate_replay_id() -> String:
	return "%08x-%04x-%04x" % [randi(), randi() & 0xFFFF, randi() & 0xFFFF]

# ============================================================================
# Replay File Management
# ============================================================================

func get_available_replays() -> Array:
	"""Returns an array of {file_name, file_path, meta} for all saved replays."""
	var replays = []
	var dir = DirAccess.open(REPLAY_DIR)
	if not dir:
		print("ReplayManager: No replays directory found")
		return replays

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json") and file_name.begins_with("replay_"):
			var file_path = REPLAY_DIR + file_name
			var meta = _read_replay_metadata(file_path)
			if not meta.is_empty():
				replays.append({
					"file_name": file_name,
					"file_path": file_path,
					"meta": meta,
				})
		file_name = dir.get_next()
	dir.list_dir_end()

	# Sort by creation date descending (newest first)
	replays.sort_custom(func(a, b):
		return a.meta.get("created_at", 0) > b.meta.get("created_at", 0)
	)

	return replays

func _read_replay_metadata(file_path: String) -> Dictionary:
	"""Read just the metadata from a replay file without loading everything."""
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {}

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_string) != OK:
		return {}

	var data = json.data
	if data is Dictionary and data.has("meta"):
		return data["meta"]
	return {}

func delete_replay(file_path: String) -> bool:
	var dir = DirAccess.open(REPLAY_DIR)
	if dir:
		var file_name = file_path.get_file()
		var err = dir.remove(file_name)
		if err == OK:
			print("ReplayManager: Deleted replay: %s" % file_path)
			return true
	push_error("ReplayManager: Failed to delete replay: %s" % file_path)
	return false

# ============================================================================
# Playback - Loading
# ============================================================================

func load_replay_from_file(file_path: String) -> bool:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		emit_signal("replay_error", "Failed to open replay file: " + file_path)
		return false

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_string) != OK:
		emit_signal("replay_error", "Failed to parse replay JSON")
		return false

	var replay_data = json.data
	if not replay_data is Dictionary:
		emit_signal("replay_error", "Invalid replay data format")
		return false

	return load_replay_from_data(replay_data)

func load_replay_from_data(replay_data: Dictionary) -> bool:
	if not _validate_replay_data(replay_data):
		return false

	# Stop any existing recording
	if is_recording:
		stop_recording()

	current_replay_data = replay_data
	initial_state = replay_data.get("initial_state", {})
	replay_events = replay_data.get("events", [])
	replay_snapshots = replay_data.get("snapshots", [])

	# Reset playback
	current_position = -1  # Before first event
	playback_state = PlaybackState.STOPPED
	current_mode = Mode.PLAYBACK

	var meta = replay_data.get("meta", {})
	print("ReplayManager: Loaded replay with %d events, %d snapshots" % [
		replay_events.size(), replay_snapshots.size()])
	emit_signal("replay_loaded", meta)
	return true

func _validate_replay_data(replay_data: Dictionary) -> bool:
	if not replay_data.has("initial_state"):
		emit_signal("replay_error", "Missing initial_state in replay data")
		return false
	if not replay_data.has("events"):
		emit_signal("replay_error", "Missing events in replay data")
		return false
	return true

# ============================================================================
# Playback - Controls
# ============================================================================

func start_playback() -> void:
	if replay_events.is_empty():
		emit_signal("replay_error", "No replay data loaded")
		return

	playback_state = PlaybackState.PLAYING
	auto_advance_timer.wait_time = 1.0 / playback_speed
	auto_advance_timer.start()
	emit_signal("playback_started")
	print("ReplayManager: Playback started (speed=%.1fx)" % playback_speed)

func pause_playback() -> void:
	if playback_state == PlaybackState.PLAYING:
		playback_state = PlaybackState.PAUSED
		auto_advance_timer.stop()
		emit_signal("playback_paused")
		print("ReplayManager: Playback paused at position %d" % current_position)

func toggle_playback() -> void:
	if playback_state == PlaybackState.PLAYING:
		pause_playback()
	else:
		start_playback()

func stop_playback() -> void:
	playback_state = PlaybackState.STOPPED
	auto_advance_timer.stop()
	current_mode = Mode.IDLE
	emit_signal("playback_stopped")
	print("ReplayManager: Playback stopped")

func step_forward() -> bool:
	"""Advance one event. Returns true if there was an event to apply."""
	var next_pos = current_position + 1
	if next_pos >= replay_events.size():
		# Reached the end
		if playback_state == PlaybackState.PLAYING:
			pause_playback()
		return false

	var event = replay_events[next_pos]

	# Apply diffs from this event to GameState
	var diffs = event.get("diffs", [])
	for diff in diffs:
		GameManager.apply_diff(diff)

	current_position = next_pos
	emit_signal("playback_position_changed", current_position, replay_events.size())
	emit_signal("replay_event_applied", event)
	return true

func step_backward() -> bool:
	"""Go back one event. Uses snapshots for efficiency."""
	if current_position < 0:
		return false

	var target_position = current_position - 1
	_restore_to_position(target_position)
	return true

func jump_to_position(position: int) -> void:
	"""Jump to any event position. Uses nearest snapshot."""
	position = clampi(position, -1, replay_events.size() - 1)
	if position == current_position:
		return

	_restore_to_position(position)

func jump_to_turn(battle_round: int) -> void:
	"""Jump to the first event of a specific battle round."""
	for i in range(replay_events.size()):
		var event = replay_events[i]
		if event.get("battle_round", 0) == battle_round and event.get("type", "") == "phase_change":
			jump_to_position(i)
			return

func jump_to_phase_event(battle_round: int, phase: int) -> void:
	"""Jump to a specific phase in a specific round."""
	for i in range(replay_events.size()):
		var event = replay_events[i]
		if event.get("type", "") == "phase_change" and event.get("new_phase", -1) == phase and event.get("battle_round", 0) == battle_round:
			jump_to_position(i)
			return

# ============================================================================
# Playback - State Reconstruction
# ============================================================================

func _restore_to_position(target_position: int) -> void:
	"""Restore GameState to the state at a given event position.
	Uses snapshots for efficiency: finds nearest snapshot before target,
	loads it, then replays diffs forward to the target."""

	# Find nearest snapshot at or before target_position
	var best_snapshot_idx = 0  # Index 0 is always the initial state snapshot
	for i in range(replay_snapshots.size()):
		var snap_event_idx = replay_snapshots[i].get("event_index", -1)
		if snap_event_idx <= target_position:
			best_snapshot_idx = i
		else:
			break

	# Load the snapshot state into GameState
	var snapshot = replay_snapshots[best_snapshot_idx]
	var snapshot_state = snapshot.get("state", {})
	var snapshot_event_idx = snapshot.get("event_index", -1)

	# Deep copy the snapshot into GameState
	GameState.state = GameState._deep_copy_dict(snapshot_state)

	# Apply diffs from snapshot position to target position
	var start_idx = snapshot_event_idx + 1
	for i in range(start_idx, target_position + 1):
		if i >= 0 and i < replay_events.size():
			var event = replay_events[i]
			var diffs = event.get("diffs", [])
			for diff in diffs:
				GameManager.apply_diff(diff)

	current_position = target_position
	emit_signal("playback_position_changed", current_position, replay_events.size())

	# Emit the event at the current position (if valid)
	if target_position >= 0 and target_position < replay_events.size():
		emit_signal("replay_event_applied", replay_events[target_position])
	else:
		emit_signal("replay_event_applied", {"type": "initial_state", "description": "Game start"})

func apply_initial_state() -> void:
	"""Load the initial state into GameState for starting playback."""
	GameState.state = GameState._deep_copy_dict(initial_state)
	current_position = -1
	emit_signal("playback_position_changed", current_position, replay_events.size())
	emit_signal("replay_event_applied", {"type": "initial_state", "description": "Game start"})

# ============================================================================
# Playback - Speed Control
# ============================================================================

func set_playback_speed(speed: float) -> void:
	playback_speed = clampf(speed, 0.25, 8.0)
	auto_advance_timer.wait_time = 1.0 / playback_speed
	print("ReplayManager: Playback speed set to %.2fx" % playback_speed)

func get_playback_speed() -> float:
	return playback_speed

func cycle_speed() -> float:
	"""Cycle through common playback speeds: 1x -> 2x -> 4x -> 0.5x -> 1x"""
	if playback_speed < 0.75:
		set_playback_speed(1.0)
	elif playback_speed < 1.5:
		set_playback_speed(2.0)
	elif playback_speed < 3.0:
		set_playback_speed(4.0)
	else:
		set_playback_speed(0.5)
	return playback_speed

# ============================================================================
# Playback - Query
# ============================================================================

func get_current_event() -> Dictionary:
	if current_position >= 0 and current_position < replay_events.size():
		return replay_events[current_position]
	return {"type": "initial_state", "description": "Game start"}

func get_event_at(position: int) -> Dictionary:
	if position >= 0 and position < replay_events.size():
		return replay_events[position]
	return {}

func get_total_events() -> int:
	return replay_events.size()

func get_current_position() -> int:
	return current_position

func get_playback_state() -> PlaybackState:
	return playback_state

func is_replay_loaded() -> bool:
	return not replay_events.is_empty()

func is_at_start() -> bool:
	return current_position <= -1

func is_at_end() -> bool:
	return current_position >= replay_events.size() - 1

func get_replay_metadata() -> Dictionary:
	return current_replay_data.get("meta", {})

func get_phase_transitions() -> Array:
	"""Get all phase change events with their indices, for jump-to-phase UI."""
	var transitions = []
	for i in range(replay_events.size()):
		var event = replay_events[i]
		if event.get("type", "") == "phase_change":
			transitions.append({
				"index": i,
				"phase": event.get("new_phase", -1),
				"phase_name": event.get("phase_name", "Unknown"),
				"battle_round": event.get("battle_round", 1),
				"description": event.get("description", ""),
			})
	return transitions

func get_replay_statistics() -> Dictionary:
	var stats = {
		"total_events": replay_events.size(),
		"total_snapshots": replay_snapshots.size(),
		"actions_by_type": {},
		"max_battle_round": 1,
	}

	for event in replay_events:
		var action_type = event.get("action_type", "unknown")
		if not stats.actions_by_type.has(action_type):
			stats.actions_by_type[action_type] = 0
		stats.actions_by_type[action_type] += 1

		var br = event.get("battle_round", 1)
		if br > stats.max_battle_round:
			stats.max_battle_round = br

	return stats

# ============================================================================
# Timer Callback
# ============================================================================

func _on_auto_advance_timeout() -> void:
	if playback_state == PlaybackState.PLAYING:
		if not step_forward():
			pause_playback()

# ============================================================================
# Cleanup
# ============================================================================

func cleanup() -> void:
	"""Reset all state for a fresh start."""
	if is_recording:
		stop_recording()
	if playback_state != PlaybackState.STOPPED:
		stop_playback()

	current_replay_data = {}
	replay_events = []
	replay_snapshots = []
	initial_state = {}
	current_position = -1
	current_mode = Mode.IDLE

	_recording_events = []
	_recording_snapshots = []
	_recording_initial_state = {}
	_recording_meta = {}
	_recording_event_index = 0
	_stable_replay_path = ""
