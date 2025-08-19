extends Node

# ReplayManager - Handles game replay functionality
# Provides playback controls and analysis tools for reviewing games

signal replay_loaded(metadata: Dictionary)
signal playback_started()
signal playback_paused()
signal playback_stopped()
signal playback_position_changed(position: int, total: int)
signal replay_error(error: String)
signal state_reconstructed(state: Dictionary)

enum PlaybackState { STOPPED, PLAYING, PAUSED }

var current_replay_data: Dictionary = {}
var initial_state: Dictionary = {}
var replay_actions: Array = []
var current_position: int = 0
var playback_state: PlaybackState = PlaybackState.STOPPED
var playback_speed: float = 1.0
var auto_advance_timer: Timer = null

# State reconstruction cache for performance
var state_cache: Dictionary = {}
var cache_enabled: bool = true
var max_cache_size: int = 100

func _ready() -> void:
	_setup_auto_advance_timer()

func _setup_auto_advance_timer() -> void:
	auto_advance_timer = Timer.new()
	auto_advance_timer.wait_time = 1.0 / playback_speed
	auto_advance_timer.timeout.connect(_on_auto_advance_timeout)
	add_child(auto_advance_timer)

# Loading and initialization
func load_replay_from_file(file_path: String) -> bool:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		emit_signal("replay_error", "Failed to open replay file: " + file_path)
		return false
	
	var json_string = file.get_as_text()
	file.close()
	
	return load_replay_from_json(json_string)

func load_replay_from_json(json_string: String) -> bool:
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
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
	
	current_replay_data = replay_data.duplicate(true)
	
	# Extract components
	var metadata = current_replay_data.get("metadata", {})
	initial_state = current_replay_data.get("metadata", {}).get("initial_state", {})
	replay_actions = current_replay_data.get("actions", [])
	
	# Reset state
	current_position = 0
	playback_state = PlaybackState.STOPPED
	_clear_cache()
	
	emit_signal("replay_loaded", metadata)
	print("ReplayManager: Loaded replay with %d actions" % replay_actions.size())
	return true

func load_replay_from_action_logger() -> bool:
	if not ActionLogger:
		emit_signal("replay_error", "ActionLogger not available")
		return false
	
	var replay_data = ActionLogger.create_replay_data()
	return load_replay_from_data(replay_data)

# Playback controls
func start_playback() -> void:
	if replay_actions.is_empty():
		emit_signal("replay_error", "No replay data loaded")
		return
	
	playback_state = PlaybackState.PLAYING
	auto_advance_timer.start()
	emit_signal("playback_started")

func pause_playback() -> void:
	if playback_state == PlaybackState.PLAYING:
		playback_state = PlaybackState.PAUSED
		auto_advance_timer.stop()
		emit_signal("playback_paused")

func stop_playback() -> void:
	playback_state = PlaybackState.STOPPED
	auto_advance_timer.stop()
	current_position = 0
	emit_signal("playback_stopped")
	emit_signal("playback_position_changed", current_position, replay_actions.size())

func step_forward() -> void:
	if current_position < replay_actions.size():
		current_position += 1
		_update_playback_position()

func step_backward() -> void:
	if current_position > 0:
		current_position -= 1
		_update_playback_position()

func jump_to_position(position: int) -> void:
	if position < 0 or position > replay_actions.size():
		return
	
	current_position = position
	_update_playback_position()

func jump_to_turn(turn: int) -> void:
	for i in range(replay_actions.size()):
		var action = replay_actions[i]
		var game_context = action.get("game_context", {})
		if game_context.get("turn", -1) == turn:
			jump_to_position(i)
			break

func jump_to_phase(turn: int, phase: GameStateData.Phase) -> void:
	for i in range(replay_actions.size()):
		var action = replay_actions[i]
		var game_context = action.get("game_context", {})
		if game_context.get("turn", -1) == turn and game_context.get("phase", -1) == phase:
			jump_to_position(i)
			break

# Speed control
func set_playback_speed(speed: float) -> void:
	playback_speed = max(0.1, min(10.0, speed))  # Clamp between 0.1x and 10x
	auto_advance_timer.wait_time = 1.0 / playback_speed

func get_playback_speed() -> float:
	return playback_speed

# State reconstruction
func get_state_at_position(position: int) -> Dictionary:
	if position < 0 or position > replay_actions.size():
		return {}
	
	# Check cache first
	if cache_enabled and state_cache.has(position):
		return state_cache[position].duplicate(true)
	
	# Find nearest cached state
	var nearest_cached_position = _find_nearest_cached_position(position)
	var start_state = {}
	var start_position = 0
	
	if nearest_cached_position >= 0 and nearest_cached_position <= position:
		start_state = state_cache[nearest_cached_position].duplicate(true)
		start_position = nearest_cached_position
	else:
		start_state = initial_state.duplicate(true)
		start_position = 0
	
	# Replay actions from start position to target position
	var current_state = start_state
	for i in range(start_position, position):
		if i < replay_actions.size():
			current_state = _apply_action_to_state(replay_actions[i], current_state)
	
	# Cache the result
	if cache_enabled:
		_cache_state(position, current_state)
	
	return current_state

func get_current_state() -> Dictionary:
	return get_state_at_position(current_position)

func _apply_action_to_state(action: Dictionary, state: Dictionary) -> Dictionary:
	# This is a simplified implementation
	# In practice, you'd need to implement the full action processing logic
	var new_state = state.duplicate(true)
	
	# Apply changes based on action type
	var action_type = action.get("type", "")
	match action_type:
		"DEPLOY_UNIT":
			_apply_deploy_unit_action(action, new_state)
		"PHASE_CHANGE":
			_apply_phase_change_action(action, new_state)
		_:
			# Handle other action types as needed
			pass
	
	return new_state

func _apply_deploy_unit_action(action: Dictionary, state: Dictionary) -> void:
	var unit_id = action.get("unit_id", "")
	var model_positions = action.get("model_positions", [])
	
	if unit_id != "" and state.has("units") and state.units.has(unit_id):
		var unit = state.units[unit_id]
		var models = unit.get("models", [])
		
		for i in range(min(model_positions.size(), models.size())):
			if model_positions[i] != null:
				models[i]["position"] = model_positions[i]
		
		unit["status"] = GameStateData.UnitStatus.DEPLOYED

func _apply_phase_change_action(action: Dictionary, state: Dictionary) -> void:
	var new_phase = action.get("phase", -1)
	if new_phase >= 0 and state.has("meta"):
		state.meta["phase"] = new_phase

# Analysis and statistics
func get_replay_statistics() -> Dictionary:
	var stats = {
		"total_actions": replay_actions.size(),
		"total_turns": 0,
		"actions_by_type": {},
		"actions_by_player": {},
		"actions_by_phase": {},
		"duration_seconds": 0
	}
	
	if replay_actions.is_empty():
		return stats
	
	var first_timestamp = replay_actions[0].get("timestamp", 0)
	var last_timestamp = replay_actions[-1].get("timestamp", 0)
	stats.duration_seconds = last_timestamp - first_timestamp
	
	var max_turn = 0
	
	for action in replay_actions:
		var action_type = action.get("type", "unknown")
		var player = action.get("player", -1)
		var phase = action.get("phase", -1)
		var game_context = action.get("game_context", {})
		var turn = game_context.get("turn", 0)
		
		max_turn = max(max_turn, turn)
		
		# Count by type
		if not stats.actions_by_type.has(action_type):
			stats.actions_by_type[action_type] = 0
		stats.actions_by_type[action_type] += 1
		
		# Count by player
		if player > 0:
			if not stats.actions_by_player.has(player):
				stats.actions_by_player[player] = 0
			stats.actions_by_player[player] += 1
		
		# Count by phase
		if phase >= 0:
			if not stats.actions_by_phase.has(phase):
				stats.actions_by_phase[phase] = 0
			stats.actions_by_phase[phase] += 1
	
	stats.total_turns = max_turn
	return stats

func get_turn_actions(turn: int) -> Array:
	var turn_actions = []
	for action in replay_actions:
		var game_context = action.get("game_context", {})
		if game_context.get("turn", -1) == turn:
			turn_actions.append(action)
	return turn_actions

func get_player_actions(player: int) -> Array:
	var player_actions = []
	for action in replay_actions:
		if action.get("player", -1) == player:
			player_actions.append(action)
	return player_actions

# Branching functionality
func create_branch_from_position(position: int) -> Dictionary:
	if position < 0 or position > replay_actions.size():
		return {}
	
	var branch_state = get_state_at_position(position)
	var branch_actions = replay_actions.slice(0, position)
	
	return {
		"initial_state": branch_state,
		"actions": branch_actions,
		"branch_point": position,
		"metadata": {
			"branched_from": current_replay_data.get("metadata", {}),
			"created_at": Time.get_unix_time_from_system()
		}
	}

func apply_branch_to_game_state(branch_data: Dictionary) -> bool:
	if not branch_data.has("initial_state"):
		return false
	
	var branch_state = branch_data.initial_state
	GameState.load_from_snapshot(branch_state)
	return true

# Cache management
func _cache_state(position: int, state: Dictionary) -> void:
	if not cache_enabled:
		return
	
	state_cache[position] = state.duplicate(true)
	
	# Manage cache size
	if state_cache.size() > max_cache_size:
		_trim_cache()

func _trim_cache() -> void:
	var positions = state_cache.keys()
	positions.sort()
	
	# Remove oldest cache entries
	var to_remove = state_cache.size() - max_cache_size
	for i in range(to_remove):
		state_cache.erase(positions[i])

func _find_nearest_cached_position(target_position: int) -> int:
	var nearest = -1
	for position in state_cache.keys():
		if position <= target_position and position > nearest:
			nearest = position
	return nearest

func _clear_cache() -> void:
	state_cache.clear()

# Validation
func _validate_replay_data(replay_data: Dictionary) -> bool:
	if not replay_data.has("metadata"):
		emit_signal("replay_error", "Missing metadata section")
		return false
	
	if not replay_data.has("actions"):
		emit_signal("replay_error", "Missing actions section")
		return false
	
	var metadata = replay_data.metadata
	if not metadata.has("initial_state"):
		emit_signal("replay_error", "Missing initial state in metadata")
		return false
	
	return true

# Event handlers
func _on_auto_advance_timeout() -> void:
	if playback_state == PlaybackState.PLAYING:
		if current_position < replay_actions.size():
			step_forward()
		else:
			stop_playback()

func _update_playback_position() -> void:
	emit_signal("playback_position_changed", current_position, replay_actions.size())
	
	# Reconstruct and emit current state
	var current_state = get_current_state()
	emit_signal("state_reconstructed", current_state)

# Utility methods
func is_replay_loaded() -> bool:
	return not replay_actions.is_empty()

func get_current_position() -> int:
	return current_position

func get_total_actions() -> int:
	return replay_actions.size()

func get_playback_state() -> PlaybackState:
	return playback_state

func set_cache_enabled(enabled: bool) -> void:
	cache_enabled = enabled
	if not enabled:
		_clear_cache()

func set_max_cache_size(size: int) -> void:
	max_cache_size = max(10, size)
	if state_cache.size() > max_cache_size:
		_trim_cache()

# Export functionality
func export_current_branch(file_path: String, position: int = -1) -> bool:
	var export_position = position if position >= 0 else current_position
	var branch_data = create_branch_from_position(export_position)
	
	if branch_data.is_empty():
		return false
	
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		emit_signal("replay_error", "Failed to create export file: " + file_path)
		return false
	
	var json_string = JSON.stringify(branch_data, "\t")
	file.store_string(json_string)
	file.close()
	
	print("ReplayManager: Exported branch to %s" % file_path)
	return true

# Debug methods
func print_replay_info() -> void:
	if not is_replay_loaded():
		print("No replay loaded")
		return
	
	var stats = get_replay_statistics()
	print("=== Replay Info ===")
	print("Total actions: %d" % stats.total_actions)
	print("Total turns: %d" % stats.total_turns)
	print("Duration: %.1f seconds" % stats.duration_seconds)
	print("Current position: %d/%d" % [current_position, replay_actions.size()])
	print("Playback state: %s" % str(playback_state))
	print("Cache entries: %d" % state_cache.size())