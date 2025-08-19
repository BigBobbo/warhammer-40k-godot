extends Node

# ActionLogger - Records all game actions for replay, debugging, and audit trails
# Works with the modular GameState system to provide comprehensive action tracking

signal action_logged(action: Dictionary)
signal action_batch_logged(actions: Array)

var log_file_path: String = ""
var current_session_id: String = ""
var action_sequence: int = 0
var session_actions: Array = []
var auto_save_enabled: bool = true
var max_memory_actions: int = 1000  # Limit memory usage

func _ready() -> void:
	_initialize_session()
	
	# Connect to PhaseManager if available
	if PhaseManager:
		PhaseManager.phase_action_taken.connect(_on_phase_action_taken)
		PhaseManager.phase_changed.connect(_on_phase_changed)

func _initialize_session() -> void:
	current_session_id = _generate_session_id()
	action_sequence = 0
	session_actions.clear()
	
	# Set up log file path
	var logs_dir = "user://logs/"
	DirAccess.open("user://").make_dir_recursive("logs")
	log_file_path = logs_dir + "session_%s.json" % current_session_id
	
	print("ActionLogger: Started session %s" % current_session_id)

func _generate_session_id() -> String:
	var time = Time.get_datetime_dict_from_system()
	return "%04d%02d%02d_%02d%02d%02d" % [
		time.year, time.month, time.day,
		time.hour, time.minute, time.second
	]

# Main logging interface
func log_action(action: Dictionary) -> void:
	var enriched_action = _enrich_action(action)
	
	# Add to memory
	session_actions.append(enriched_action)
	
	# Manage memory usage
	if session_actions.size() > max_memory_actions:
		var excess = session_actions.size() - max_memory_actions
		session_actions = session_actions.slice(excess)
	
	# Auto-save to file if enabled
	if auto_save_enabled:
		_append_to_file(enriched_action)
	
	emit_signal("action_logged", enriched_action)

func log_action_batch(actions: Array) -> void:
	var enriched_actions = []
	
	for action in actions:
		var enriched_action = _enrich_action(action)
		enriched_actions.append(enriched_action)
		session_actions.append(enriched_action)
	
	# Manage memory usage
	if session_actions.size() > max_memory_actions:
		var excess = session_actions.size() - max_memory_actions
		session_actions = session_actions.slice(excess)
	
	# Auto-save to file if enabled
	if auto_save_enabled:
		_append_batch_to_file(enriched_actions)
	
	emit_signal("action_batch_logged", enriched_actions)

func _enrich_action(action: Dictionary) -> Dictionary:
	var enriched = action.duplicate(true)
	
	# Add logging metadata
	enriched["_log_metadata"] = {
		"session_id": current_session_id,
		"sequence": action_sequence,
		"logged_at": Time.get_unix_time_from_system(),
		"game_state_version": GameState.state.get("meta", {}).get("version", "unknown")
	}
	
	action_sequence += 1
	
	# Add game context if not present
	if not enriched.has("game_context"):
		enriched["game_context"] = _capture_game_context()
	
	return enriched

func _capture_game_context() -> Dictionary:
	return {
		"turn": GameState.get_turn_number(),
		"phase": GameState.get_current_phase(),
		"active_player": GameState.get_active_player(),
		"game_id": GameState.state.get("meta", {}).get("game_id", "unknown")
	}

# File operations
func _append_to_file(action: Dictionary) -> void:
	var file = FileAccess.open(log_file_path, FileAccess.WRITE)
	if file:
		file.seek_end()
		var json_string = JSON.stringify(action)
		file.store_line(json_string)
		file.close()
	else:
		push_error("ActionLogger: Failed to open log file for writing: " + log_file_path)

func _append_batch_to_file(actions: Array) -> void:
	var file = FileAccess.open(log_file_path, FileAccess.WRITE)
	if file:
		file.seek_end()
		for action in actions:
			var json_string = JSON.stringify(action)
			file.store_line(json_string)
		file.close()
	else:
		push_error("ActionLogger: Failed to open log file for writing: " + log_file_path)

func save_session_to_file(file_path: String = "") -> bool:
	var target_path = file_path if file_path != "" else log_file_path
	
	var session_data = {
		"session_metadata": {
			"session_id": current_session_id,
			"created_at": Time.get_unix_time_from_system(),
			"total_actions": session_actions.size(),
			"game_version": "1.0.0"
		},
		"actions": session_actions
	}
	
	var file = FileAccess.open(target_path, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(session_data, "\t")
		file.store_string(json_string)
		file.close()
		print("ActionLogger: Saved session to %s" % target_path)
		return true
	else:
		push_error("ActionLogger: Failed to save session to " + target_path)
		return false

func load_session_from_file(file_path: String) -> Dictionary:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("ActionLogger: Failed to open file for reading: " + file_path)
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		push_error("ActionLogger: Failed to parse JSON from " + file_path)
		return {}
	
	return json.data

# Query and retrieval methods
func get_actions_by_phase(phase: GameStateData.Phase) -> Array:
	var filtered_actions = []
	for action in session_actions:
		if action.get("phase", -1) == phase:
			filtered_actions.append(action)
	return filtered_actions

func get_actions_by_player(player: int) -> Array:
	var filtered_actions = []
	for action in session_actions:
		if action.get("player", -1) == player:
			filtered_actions.append(action)
	return filtered_actions

func get_actions_by_turn(turn: int) -> Array:
	var filtered_actions = []
	for action in session_actions:
		var game_context = action.get("game_context", {})
		if game_context.get("turn", -1) == turn:
			filtered_actions.append(action)
	return filtered_actions

func get_actions_by_type(action_type: String) -> Array:
	var filtered_actions = []
	for action in session_actions:
		if action.get("type", "") == action_type:
			filtered_actions.append(action)
	return filtered_actions

func get_recent_actions(count: int) -> Array:
	var start_idx = max(0, session_actions.size() - count)
	return session_actions.slice(start_idx)

func get_all_session_actions() -> Array:
	return session_actions.duplicate()

func get_session_statistics() -> Dictionary:
	var stats = {
		"session_id": current_session_id,
		"total_actions": session_actions.size(),
		"action_sequence": action_sequence,
		"actions_by_type": {},
		"actions_by_phase": {},
		"actions_by_player": {}
	}
	
	# Count actions by type, phase, and player
	for action in session_actions:
		var action_type = action.get("type", "unknown")
		var phase = action.get("phase", -1)
		var player = action.get("player", -1)
		
		# Count by type
		if not stats.actions_by_type.has(action_type):
			stats.actions_by_type[action_type] = 0
		stats.actions_by_type[action_type] += 1
		
		# Count by phase
		if not stats.actions_by_phase.has(phase):
			stats.actions_by_phase[phase] = 0
		stats.actions_by_phase[phase] += 1
		
		# Count by player
		if not stats.actions_by_player.has(player):
			stats.actions_by_player[player] = 0
		stats.actions_by_player[player] += 1
	
	return stats

# Replay functionality
func create_replay_data() -> Dictionary:
	return {
		"metadata": {
			"session_id": current_session_id,
			"created_at": Time.get_unix_time_from_system(),
			"total_actions": session_actions.size(),
			"initial_state": GameState.create_snapshot()
		},
		"actions": session_actions.duplicate()
	}

func export_replay_to_file(file_path: String) -> bool:
	var replay_data = create_replay_data()
	
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(replay_data, "\t")
		file.store_string(json_string)
		file.close()
		print("ActionLogger: Exported replay to %s" % file_path)
		return true
	else:
		push_error("ActionLogger: Failed to export replay to " + file_path)
		return false

# Event handlers
func _on_phase_action_taken(action: Dictionary) -> void:
	log_action(action)

func _on_phase_changed(new_phase: GameStateData.Phase) -> void:
	var phase_change_action = {
		"type": "PHASE_CHANGE",
		"phase": new_phase,
		"timestamp": Time.get_unix_time_from_system(),
		"game_context": _capture_game_context()
	}
	log_action(phase_change_action)

# Settings and configuration
func set_auto_save(enabled: bool) -> void:
	auto_save_enabled = enabled

func set_max_memory_actions(max_actions: int) -> void:
	max_memory_actions = max_actions
	
	# Trim current actions if needed
	if session_actions.size() > max_memory_actions:
		var excess = session_actions.size() - max_memory_actions
		session_actions = session_actions.slice(excess)

func clear_session() -> void:
	session_actions.clear()
	action_sequence = 0
	print("ActionLogger: Cleared session actions")

func get_log_file_path() -> String:
	return log_file_path

# Debug and diagnostic methods
func print_session_summary() -> void:
	var stats = get_session_statistics()
	print("=== Action Logger Session Summary ===")
	print("Session ID: %s" % stats.session_id)
	print("Total Actions: %d" % stats.total_actions)
	print("Actions by Type:")
	for type in stats.actions_by_type:
		print("  %s: %d" % [type, stats.actions_by_type[type]])
	print("Actions by Phase:")
	for phase in stats.actions_by_phase:
		print("  %s: %d" % [str(phase), stats.actions_by_phase[phase]])
	print("Actions by Player:")
	for player in stats.actions_by_player:
		print("  Player %d: %d" % [player, stats.actions_by_player[player]])

func validate_action_integrity() -> Dictionary:
	var validation = {
		"valid": true,
		"errors": [],
		"warnings": []
	}
	
	var expected_sequence = 0
	for i in range(session_actions.size()):
		var action = session_actions[i]
		var metadata = action.get("_log_metadata", {})
		var sequence = metadata.get("sequence", -1)
		
		if sequence != expected_sequence:
			validation.valid = false
			validation.errors.append("Sequence mismatch at index %d: expected %d, got %d" % [i, expected_sequence, sequence])
		
		expected_sequence += 1
	
	return validation