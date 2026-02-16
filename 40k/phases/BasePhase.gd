extends Node
class_name BasePhase

const GameStateData = preload("res://autoloads/GameState.gd")


# BasePhase - Abstract base class for all game phases
# Defines the standard interface that all phases must implement

signal phase_completed()
signal action_taken(action: Dictionary)

var game_state_snapshot: Dictionary = {}
var phase_type: GameStateData.Phase

# Abstract methods that must be implemented by concrete phases
func enter_phase(state_snapshot: Dictionary) -> void:
	game_state_snapshot = state_snapshot
	_on_phase_enter()

func exit_phase() -> void:
	_on_phase_exit()

	# Clear debug visualizations on any phase exit
	_clear_debug_visualizations()

# Helper method to clear debug visualizations safely
func _clear_debug_visualizations() -> void:
	# Try to get the main scene root
	var main_loop = Engine.get_main_loop()
	if not main_loop or not main_loop is SceneTree:
		return

	var root = main_loop.current_scene
	if not root:
		return

	# Navigate to the LoSDebugVisual node
	var board_root = root.get_node_or_null("BoardRoot")
	if not board_root:
		return

	var los_debug = board_root.get_node_or_null("LoSDebugVisual")
	if los_debug and is_instance_valid(los_debug) and los_debug.has_method("clear_all_debug_visuals"):
		los_debug.clear_all_debug_visuals()

func _on_phase_enter() -> void:
	# Override in concrete phases for phase-specific setup
	pass

func _on_phase_exit() -> void:
	# Override in concrete phases for phase-specific cleanup
	pass

# Validate if an action is legal in this phase
func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	# Debug mode bypasses normal validation
	if action_type == "DEBUG_MOVE":
		# Only allow if debug mode is active
		if DebugManager and DebugManager.is_debug_active():
			return {"valid": true}
		else:
			return {"valid": false, "reason": "Debug mode not active", "errors": ["Debug mode must be active to use DEBUG_MOVE"]}

	# Override in concrete phases for phase-specific validation
	return {"valid": true, "errors": []}

# Get list of available actions for current game state
func get_available_actions() -> Array:
	# Override in concrete phases to return available actions
	return []

# Process a validated action and return state changes
func process_action(action: Dictionary) -> Dictionary:
	# Override in concrete phases for action processing
	return {"success": false, "error": "Not implemented"}

# Execute an action (validate + process + apply)
func execute_action(action: Dictionary) -> Dictionary:
	print("[BasePhase] Executing action: ", action.get("type", "UNKNOWN"))
	print("[BasePhase] For unit: ", action.get("unit_id", "N/A"))

	var validation = validate_action(action)
	if not validation.valid:
		print("[BasePhase] Action validation failed: ", validation.errors)
		return {"success": false, "errors": validation.errors}

	var result = process_action(action)
	if result.success:
		print("[BasePhase] Action processed successfully")
		# Apply the state changes if they exist
		if result.has("changes") and result.changes is Array:
			PhaseManager.apply_state_changes(result.changes)

			# CRITICAL: Update our local snapshot after applying changes
			# Otherwise get_unit() will read stale data from the old snapshot
			game_state_snapshot = GameState.create_snapshot()
			print("[BasePhase] Refreshed game_state_snapshot after applying changes")

		# Attach human-readable log_text from result to the action dict
		if result.has("log_text") and result.log_text != "":
			action["_log_text"] = result.log_text

		# Record the action
		print("[BasePhase] Emitting action_taken signal")
		emit_signal("action_taken", action)

		# Check if this action completes the phase
		if _should_complete_phase():
			emit_signal("phase_completed")
	else:
		print("[BasePhase] Action processing failed")

	return result

# Check if the phase should be completed
func _should_complete_phase() -> bool:
	# Override in concrete phases for phase-specific completion logic
	return false

# Utility methods for interacting with game state
func get_current_player() -> int:
	# Always get the current active player from live GameState, not the snapshot
	# This ensures we see updates made by TurnManager
	return GameState.get_active_player()

func get_turn_number() -> int:
	return game_state_snapshot.get("meta", {}).get("turn_number", 1)

func get_units_for_player(player: int) -> Dictionary:
	var player_units = {}
	var units = game_state_snapshot.get("units", {})
	
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) == player:
			player_units[unit_id] = unit
	
	return player_units

func get_unit(unit_id: String) -> Dictionary:
	var units = game_state_snapshot.get("units", {})
	return units.get(unit_id, {})

func get_deployment_zone_for_player(player: int) -> Dictionary:
	var zones = game_state_snapshot.get("board", {}).get("deployment_zones", [])
	for zone in zones:
		if zone.get("player", 0) == player:
			return zone
	return {}

# Create a standardized action dictionary
func create_action(action_type: String, parameters: Dictionary = {}) -> Dictionary:
	var action = {
		"type": action_type,
		"phase": phase_type,
		"player": get_current_player(),
		"turn": get_turn_number(),
		"timestamp": Time.get_unix_time_from_system()
	}
	
	# Add parameters
	for key in parameters:
		action[key] = parameters[key]
	
	return action

# Create a standardized result dictionary
func create_result(success: bool, changes: Array = [], error: String = "") -> Dictionary:
	var result = {
		"success": success,
		"phase": phase_type,
		"timestamp": Time.get_unix_time_from_system()
	}
	
	if success:
		result["changes"] = changes
	else:
		result["error"] = error
	
	return result

# Update local game state snapshot (call this after applying changes)
func update_local_state(new_snapshot: Dictionary) -> void:
	game_state_snapshot = new_snapshot

# Log a message for this phase
func log_phase_message(message: String, level: String = "INFO") -> void:
	print("[%s][%s] %s" % [str(phase_type), level, message])
