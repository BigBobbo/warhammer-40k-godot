extends Node
class_name NetworkIntegration

## NetworkIntegration - Utility for routing game actions through multiplayer or local execution
##
## This class provides a single entry point for all game actions, automatically
## routing them through NetworkManager if multiplayer is active, or executing
## them locally for single-player games.

# Route an action through the appropriate channel (network or local)
static func route_action(action: Dictionary) -> Dictionary:
	"""
	Routes a game action through the appropriate execution path.

	In multiplayer mode:
	  - Actions are sent through NetworkManager for validation and synchronization
	  - Host validates and broadcasts results
	  - Clients send to host for processing

	In single-player mode:
	  - Actions are executed directly through the phase system

	Args:
		action: Dictionary with keys:
			- type: String (required) - Action type (e.g., "DEPLOY_UNIT")
			- player: int (optional) - Player ID, added automatically if missing
			- timestamp: float (optional) - Unix timestamp, added automatically if missing
			- ... other action-specific fields

	Returns:
		Dictionary with keys:
			- success: bool - Whether action succeeded
			- pending: bool (multiplayer only) - True if waiting for network response
			- error: String (optional) - Error message if failed
			- errors: Array (optional) - Validation errors if failed
	"""

	# Validate action has required fields
	if not action.has("type"):
		push_error("[NetworkIntegration] Action missing required 'type' field")
		return {"success": false, "error": "Action missing 'type' field"}

	# Get NetworkManager reference (used for both player ID and routing)
	var network_manager = Engine.get_main_loop().root.get_node_or_null("/root/NetworkManager")

	# Add player and timestamp if not present
	if not action.has("player"):
		# In multiplayer, use the local player ID (not the active turn player)
		# NetworkManager will validate if this player is allowed to take this action
		if network_manager and network_manager.is_networked():
			# Multiplayer: Use local player's ID
			var local_peer_id = Engine.get_main_loop().root.get_tree().get_multiplayer().get_unique_id()
			action["player"] = network_manager.peer_to_player_map.get(local_peer_id, GameState.get_active_player())
			print("[NetworkIntegration] Using local player ID for action: peer=%d -> player=%d" % [local_peer_id, action["player"]])
		else:
			# Single-player: Use active player (current turn)
			action["player"] = GameState.get_active_player()
	if not action.has("timestamp"):
		action["timestamp"] = Time.get_unix_time_from_system()

	# Check if multiplayer is active
	if network_manager and network_manager.is_networked():
		print("[NetworkIntegration] Routing action through NetworkManager: ", action.get("type"))

		# Route through network layer
		network_manager.submit_action(action)

		# In multiplayer, the result comes back asynchronously via RPC
		# The action will be executed when the RPC arrives
		# For now, return a pending status
		return {"success": true, "pending": true, "message": "Action submitted to network"}

	else:
		# Single-player mode - execute through phase directly
		print("[NetworkIntegration] Executing action locally: ", action.get("type"))
		var phase_manager = Engine.get_main_loop().root.get_node_or_null("/root/PhaseManager")

		if not phase_manager:
			push_error("[NetworkIntegration] PhaseManager not found")
			return {"success": false, "error": "PhaseManager not available"}

		if not phase_manager.current_phase_instance:
			push_error("[NetworkIntegration] No active phase instance")
			return {"success": false, "error": "No active phase"}

		# Execute action through phase
		var result = phase_manager.current_phase_instance.execute_action(action)
		return result

# Check if multiplayer mode is active
static func is_multiplayer_active() -> bool:
	var network_manager = Engine.get_main_loop().root.get_node_or_null("/root/NetworkManager")
	return network_manager != null and network_manager.is_networked()

# Get current player (for action construction)
static func get_current_player() -> int:
	return GameState.get_active_player()
