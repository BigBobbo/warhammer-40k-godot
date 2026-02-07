extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# NetworkManager - Multiplayer networking for Warhammer 40K game
# Note: No class_name since this is an autoload singleton

# Signals
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal connection_failed(reason: String)
signal game_started()
signal action_rejected(action_type: String, reason: String)  # Emitted when an action is rejected
signal game_code_received(code: String)  # Emitted when server assigns a game code

# Network modes
enum NetworkMode { OFFLINE, HOST, CLIENT, DEDICATED_SERVER }

# Transport types
enum TransportType { ENET, WEBSOCKET, WEB_RELAY }

# State
var network_mode: NetworkMode = NetworkMode.OFFLINE
var transport_type: TransportType = TransportType.ENET
var peer_to_player_map: Dictionary = {}  # peer_id -> player_number
var game_manager: GameManager = null
var game_state: GameStateData = null

# Online game state
var is_online_host: bool = false  # True if this client created the online game (player 1)

# Game code for online matchmaking
var current_game_code: String = ""

# Reference to TransportFactory autoload
var transport_factory: Node = null

# Web Relay mode - uses WebSocketRelay for transport instead of Godot RPCs
var web_relay: Node = null
var web_relay_mode: bool = false

# Turn timer (Phase 3)
var turn_timer: Timer = null
const TURN_TIMEOUT_SECONDS: float = 90.0

# RNG determinism (Phase 4)
var rng_seed_counter: int = 0
var game_session_id: String = ""

func _ready() -> void:
	if not FeatureFlags.MULTIPLAYER_ENABLED:
		print("NetworkManager: Multiplayer disabled via feature flag")
		return

	# Get references to other autoloads (use get_node_or_null for safety)
	game_manager = get_node_or_null("/root/GameManager")
	game_state = get_node_or_null("/root/GameState")
	transport_factory = get_node_or_null("/root/TransportFactory")

	if not game_manager:
		push_warning("NetworkManager: GameManager not available at startup")
	if not game_state:
		push_warning("NetworkManager: GameState not available at startup")
	if not transport_factory:
		push_warning("NetworkManager: TransportFactory not available at startup")

	# Connect to multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)

	# Create turn timer
	turn_timer = Timer.new()
	turn_timer.one_shot = true
	turn_timer.timeout.connect(_on_turn_timeout)
	add_child(turn_timer)

	# Initialize RNG session ID
	game_session_id = str(Time.get_unix_time_from_system())

	print("NetworkManager: Initialized (platform: %s)" % ("web" if _is_web_platform() else "desktop"))

# ============================================================================
# PHASE 1: CORE SYNC - Connection and State Synchronization
# ============================================================================

func _is_web_platform() -> bool:
	"""Check if running in a web browser."""
	return OS.has_feature("web")

func create_host(port: int = 7777) -> int:
	"""Create a host for LAN play using ENet. Not available on web platform."""
	if _is_web_platform():
		push_error("NetworkManager: Cannot host LAN game on web platform. Use online matchmaking.")
		return ERR_UNAVAILABLE

	var peer: MultiplayerPeer
	if transport_factory:
		peer = transport_factory.create_server_peer(port)
	else:
		# Fallback if TransportFactory not available
		peer = ENetMultiplayerPeer.new()
		var error = peer.create_server(port, 1)
		if error != OK:
			print("NetworkManager: Failed to create host - ", error)
			return error

	if not peer:
		return ERR_CANT_CREATE

	multiplayer.multiplayer_peer = peer
	network_mode = NetworkMode.HOST
	transport_type = TransportType.ENET
	peer_to_player_map[1] = 1  # Host is player 1

	# Update window title to show player number
	DisplayServer.window_set_title("40k Game - PLAYER 1 (HOST)")

	print("========================================")
	print("   YOU ARE: PLAYER 1 (HOST)")
	print("   Hosting on port: ", port)
	print("========================================")
	return OK

func join_as_client(url_or_ip: String, port: int = 7777) -> int:
	"""Join a game as client. Supports both ENet (LAN) and WebSocket (online)."""
	var peer: MultiplayerPeer
	var use_websocket = _should_use_websocket(url_or_ip)

	if transport_factory:
		peer = transport_factory.create_client_peer(url_or_ip, port)
	else:
		# Fallback if TransportFactory not available
		if use_websocket:
			peer = WebSocketMultiplayerPeer.new()
			var ws_url = url_or_ip if url_or_ip.begins_with("ws") else "ws://%s:%d" % [url_or_ip, port]
			var error = peer.create_client(ws_url)
			if error != OK:
				print("NetworkManager: Failed to connect via WebSocket to ", ws_url, " - ", error)
				return error
		else:
			peer = ENetMultiplayerPeer.new()
			var error = peer.create_client(url_or_ip, port)
			if error != OK:
				print("NetworkManager: Failed to connect to ", url_or_ip, ":", port, " - ", error)
				return error

	if not peer:
		return ERR_CANT_CREATE

	multiplayer.multiplayer_peer = peer
	network_mode = NetworkMode.CLIENT
	transport_type = TransportType.WEBSOCKET if use_websocket else TransportType.ENET

	var connection_info = url_or_ip if use_websocket else "%s:%d" % [url_or_ip, port]
	print("NetworkManager: Connecting to ", connection_info, " via ", "WebSocket" if use_websocket else "ENet")
	return OK

func _should_use_websocket(url_or_ip: String) -> bool:
	"""Determine if WebSocket should be used based on platform and URL."""
	# Always use WebSocket on web platform
	if _is_web_platform():
		return true
	# Use WebSocket if URL starts with ws:// or wss://
	if url_or_ip.begins_with("ws://") or url_or_ip.begins_with("wss://"):
		return true
	return false

func join_online_game(game_code: String) -> int:
	"""Join an online game using a game code via WebSocket server."""
	if not transport_factory:
		push_error("NetworkManager: TransportFactory required for online games")
		return ERR_UNCONFIGURED

	var server_url = transport_factory.get_production_server_url()
	if server_url.is_empty():
		push_error("NetworkManager: No server URL configured")
		return ERR_UNCONFIGURED

	current_game_code = game_code
	is_online_host = false  # Joining player is player 2
	print("NetworkManager: Joining online game with code: ", game_code)

	# Connect to the WebSocket server
	var result = join_as_client(server_url)
	if result != OK:
		current_game_code = ""
		return result

	# Game code will be sent after connection is established
	return OK

func create_online_game() -> int:
	"""Create a new online game and get a game code from the server."""
	if not transport_factory:
		push_error("NetworkManager: TransportFactory required for online games")
		return ERR_UNCONFIGURED

	var server_url = transport_factory.get_production_server_url()
	if server_url.is_empty():
		push_error("NetworkManager: No server URL configured")
		return ERR_UNCONFIGURED

	print("NetworkManager: Creating online game via server: ", server_url)
	is_online_host = true  # Game creator is player 1

	# Connect to the WebSocket server as host
	var result = join_as_client(server_url)
	if result != OK:
		is_online_host = false
		return result

	# Server will assign a game code after connection
	# We'll receive it via _receive_game_code RPC
	return OK

@rpc("authority", "call_remote", "reliable")
func _receive_game_code(code: String) -> void:
	"""Called by server to assign a game code to this session."""
	current_game_code = code
	print("NetworkManager: Received game code: ", code)
	game_code_received.emit(code)

@rpc("any_peer", "call_remote", "reliable")
func _request_join_game(code: String) -> void:
	"""Called by client to request joining a specific game code."""
	# This is handled by the dedicated server
	pass

func get_current_game_code() -> String:
	"""Get the current game code for sharing."""
	return current_game_code

func is_online_game() -> bool:
	"""Check if this is an online (WebSocket or Web Relay) game."""
	return transport_type == TransportType.WEBSOCKET or transport_type == TransportType.WEB_RELAY

func is_host() -> bool:
	# In web relay mode, use is_online_host flag
	if web_relay_mode:
		return is_online_host
	return network_mode == NetworkMode.HOST

func is_networked() -> bool:
	# Web relay mode is always networked
	if web_relay_mode:
		return true
	return network_mode != NetworkMode.OFFLINE

func get_local_player() -> int:
	"""Get the player number for this local client.
	Returns 1 for host/game creator, 2 for client/joiner, or -1 if not in a networked game.
	In single-player, returns the active player (effectively always your turn)."""
	if not is_networked():
		# Single player - return active player so turn checks pass
		if game_state:
			return game_state.get_active_player()
		return 1

	# For web relay mode and online (WebSocket) games, use is_online_host flag
	if web_relay_mode or is_online_game():
		return 1 if is_online_host else 2

	# For LAN (ENet) games, use peer_to_player_map
	var local_peer_id = multiplayer.get_unique_id()
	return peer_to_player_map.get(local_peer_id, -1)

func is_local_player_turn() -> bool:
	"""Check if it's the local player's turn."""
	if not is_networked():
		return true  # Single player - always your turn

	var local_player = get_local_player()
	if local_player == -1:
		return false  # Not properly connected

	if game_state:
		return local_player == game_state.get_active_player()
	return false

# ============================================================================
# WEB RELAY MODE - Bridge between WebSocketRelay and NetworkManager
# ============================================================================

func enter_web_relay_mode(is_game_host: bool, game_code: String = "") -> void:
	"""Enter web relay mode for online multiplayer via WebSocketRelay.
	This bridges the WebSocketRelay transport with NetworkManager's action handling."""
	print("NetworkManager: Entering web relay mode (is_host=%s, code=%s)" % [is_game_host, game_code])

	# Get WebSocketRelay reference
	web_relay = get_node_or_null("/root/WebSocketRelay")
	if not web_relay:
		push_error("NetworkManager: WebSocketRelay not found - cannot enter web relay mode")
		return

	# Set up state
	web_relay_mode = true
	is_online_host = is_game_host
	current_game_code = game_code
	transport_type = TransportType.WEB_RELAY

	# In web relay mode, we don't use Godot's multiplayer peer system
	# Instead we route actions through WebSocketRelay
	network_mode = NetworkMode.HOST if is_game_host else NetworkMode.CLIENT

	# Connect to relay messages
	if not web_relay.message_received.is_connected(_on_web_relay_message):
		web_relay.message_received.connect(_on_web_relay_message)

	# Set up player mapping (host is player 1, guest is player 2)
	# Both sides need the full map - host validates guest actions using peer_id=2
	peer_to_player_map.clear()
	peer_to_player_map[1] = 1  # Host is player 1
	peer_to_player_map[2] = 2  # Guest is player 2

	print("NetworkManager: Web relay mode active")
	print("NetworkManager:   is_host() = ", is_host())
	print("NetworkManager:   is_networked() = ", is_networked())
	print("NetworkManager:   get_local_player() = ", get_local_player())

	# Update window title to show player number
	if is_game_host:
		DisplayServer.window_set_title("40k Game - PLAYER 1 (HOST) - Code: %s" % game_code)
		print("========================================")
		print("   YOU ARE: PLAYER 1 (HOST)")
		print("   Game Code: %s" % game_code)
		print("========================================")
	else:
		DisplayServer.window_set_title("40k Game - PLAYER 2 (CLIENT) - Code: %s" % game_code)
		print("========================================")
		print("   YOU ARE: PLAYER 2 (CLIENT)")
		print("   Game Code: %s" % game_code)
		print("========================================")

	# Emit game_started signal
	emit_signal("game_started")

func _on_web_relay_message(data: Dictionary) -> void:
	"""Handle incoming game messages from WebSocketRelay."""
	var msg_type = data.get("msg_type", "")

	match msg_type:
		"game_action":
			# Received an action from the other player
			var action = data.get("action", {})
			print("NetworkManager: Received game action via relay: ", action.get("type", "UNKNOWN"))
			_handle_relayed_action(action)

		"action_result":
			# Received a result broadcast from host
			var result = data.get("result", {})
			print("NetworkManager: Received action result via relay")
			_handle_relayed_result(result)

		"action_rejected":
			# Action was rejected by host
			var action_type = data.get("action_type", "")
			var reason = data.get("reason", "Unknown")
			print("NetworkManager: Action rejected via relay: ", reason)
			action_rejected.emit(action_type, reason)

		"initial_state":
			# Received initial game state from host
			var snapshot = data.get("snapshot", {})
			print("NetworkManager: Received initial state via relay")
			print("NetworkManager: Snapshot has %d units" % snapshot.get("units", {}).size())
			if game_state:
				game_state.load_from_snapshot(snapshot)
				print("NetworkManager: State loaded, triggering UI refresh")
				# Trigger UI refresh via state_changed signal
				if game_state.has_signal("state_changed"):
					game_state.emit_signal("state_changed")
				emit_signal("game_started")

func _handle_relayed_action(action: Dictionary) -> void:
	"""Handle an action received from the other player via relay."""
	if not is_host():
		# Only host processes actions
		print("NetworkManager: Ignoring relayed action - not host")
		return

	# Validate the action (use player 2's ID since it came from the guest)
	var peer_id = 2
	var validation = validate_action(action, peer_id)

	if not validation.valid:
		var reason = validation.get("reason", "Validation failed")
		if reason == "Validation failed" and validation.has("errors") and validation.errors.size() > 0:
			reason = validation.errors[0]
		print("NetworkManager: REJECTING relayed action: ", reason)

		# Send rejection back via relay
		_send_via_relay({
			"msg_type": "action_rejected",
			"action_type": action.get("type", ""),
			"reason": reason
		})
		return

	# Execute the action
	print("NetworkManager: Relayed action VALIDATED, applying via GameManager")
	var result = game_manager.apply_action(action)

	if result.success:
		_update_phase_snapshot()

		# Broadcast result to guest via relay
		print("NetworkManager: Broadcasting result via relay")
		_send_via_relay({
			"msg_type": "action_result",
			"result": result
		})
	else:
		var fail_msg = result.get("error", result.get("message", "Unknown"))
		print("NetworkManager: GameManager returned failure: ", fail_msg)
		print("NetworkManager: Full result: ", result)

func _handle_relayed_result(result: Dictionary) -> void:
	"""Handle an action result received from host via relay."""
	if is_host():
		# Host doesn't need to process results - it already applied them
		return

	if not result.get("success", false):
		print("NetworkManager: Ignoring failed result")
		return

	# Apply the result to local state
	print("NetworkManager: Client applying relayed result with %d diffs" % result.get("diffs", []).size())
	game_manager.apply_result(result)

	_update_phase_snapshot()

	# Emit visual updates
	_emit_client_visual_updates(result)

	print("NetworkManager: Client finished applying relayed result")

func _send_via_relay(data: Dictionary) -> void:
	"""Send data to the other player via WebSocketRelay."""
	if not web_relay:
		push_error("NetworkManager: Cannot send via relay - no relay connection")
		return

	if not web_relay.is_connected:
		push_error("NetworkManager: Cannot send via relay - not connected")
		return

	# Sanitize data for JSON serialization (Vector2/Vector3 etc. are not JSON-safe)
	var safe_data = _sanitize_for_json(data)
	web_relay.send_game_data(safe_data)

func _sanitize_for_json(value) -> Variant:
	"""Recursively convert Godot types (Vector2, Vector3, etc.) to JSON-safe types."""
	if value is Vector2:
		return {"x": value.x, "y": value.y}
	elif value is Vector3:
		return {"x": value.x, "y": value.y, "z": value.z}
	elif value is Color:
		return {"r": value.r, "g": value.g, "b": value.b, "a": value.a}
	elif value is Dictionary:
		var result = {}
		for key in value:
			result[key] = _sanitize_for_json(value[key])
		return result
	elif value is Array:
		var result = []
		for item in value:
			result.append(_sanitize_for_json(item))
		return result
	else:
		return value

func send_initial_state_via_relay() -> void:
	"""Send the current game state to the guest via relay (host only)."""
	if not is_host():
		return

	if not game_state:
		push_error("NetworkManager: Cannot send initial state - no game state")
		return

	var snapshot = game_state.create_snapshot()
	print("NetworkManager: Sending initial state via relay")
	_send_via_relay({
		"msg_type": "initial_state",
		"snapshot": snapshot
	})

func disconnect_network() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	# Clean up web relay mode
	if web_relay_mode and web_relay:
		if web_relay.message_received.is_connected(_on_web_relay_message):
			web_relay.message_received.disconnect(_on_web_relay_message)

	network_mode = NetworkMode.OFFLINE
	transport_type = TransportType.ENET
	web_relay_mode = false
	web_relay = null
	peer_to_player_map.clear()
	is_online_host = false
	current_game_code = ""
	print("NetworkManager: Disconnected")

# Action submission and routing
func submit_action(action: Dictionary) -> void:
	print("NetworkManager: submit_action called for type: ", action.get("type"))
	print("NetworkManager: is_networked() = ", is_networked())
	print("NetworkManager: web_relay_mode = ", web_relay_mode)

	if not is_networked():
		# Single player mode - apply directly
		print("NetworkManager: Single-player mode - applying directly")
		game_manager.apply_action(action)
		return

	# Web relay mode - use WebSocketRelay for transport
	if web_relay_mode:
		_submit_action_via_relay(action)
		return

	if is_host():
		print("NetworkManager: Host mode - validating and applying")
		# Host validates and applies
		var peer_id = 1  # Host's own peer ID
		var validation = validate_action(action, peer_id)

		if not validation.valid:
			# Get error message from either "reason" or first "errors" entry
			var error_msg = validation.get("reason", "Validation failed")
			if error_msg == "Validation failed" and validation.has("errors") and validation.errors.size() > 0:
				error_msg = validation.errors[0]
			print("NetworkManager: Host validation failed: ", error_msg)
			print("NetworkManager: Full validation result: ", validation)
			push_error("NetworkManager: Host action rejected: %s" % error_msg)

			# Notify UI of validation failure
			if has_node("/root/Main"):
				var main = get_node("/root/Main")
				if main.has_method("show_error_toast"):
					main.call_deferred("show_error_toast", error_msg)

			return

		# Execute via GameManager
		var result = game_manager.apply_action(action)
		print("NetworkManager: Host applied action, result.success = ", result.success)

		# CRITICAL LOGGING: Check if result contains sequential_pause for APPLY_SAVES
		if action.get("type") == "APPLY_SAVES":
			print("╔═══════════════════════════════════════════════════════════════")
			print("║ HOST APPLIED OWN APPLY_SAVES - CHECKING RESULT")
			print("║ result.success: ", result.success)
			print("║ result.sequential_pause: ", result.get("sequential_pause", false))
			print("║ result.remaining_weapons: ", result.get("remaining_weapons", []).size() if result.has("remaining_weapons") else "MISSING")
			print("║ result.current_weapon_index: ", result.get("current_weapon_index", -1))
			print("╚═══════════════════════════════════════════════════════════════")

		if result.success:
			# Broadcast the result to client
			print("NetworkManager: Broadcasting result to clients")
			_broadcast_result.rpc(result)
	else:
		print("NetworkManager: Client mode - sending to host")
		# Client sends to host
		_send_action_to_host.rpc_id(1, action)

func _submit_action_via_relay(action: Dictionary) -> void:
	"""Submit an action via WebSocketRelay (web relay mode only)."""
	print("NetworkManager: Submitting action via web relay: ", action.get("type"))

	if is_host():
		# Host validates and applies locally
		print("NetworkManager: Host (relay) - validating and applying")
		var peer_id = 1  # Host's own player ID
		var validation = validate_action(action, peer_id)

		if not validation.valid:
			var error_msg = validation.get("reason", "Validation failed")
			if error_msg == "Validation failed" and validation.has("errors") and validation.errors.size() > 0:
				error_msg = validation.errors[0]
			print("NetworkManager: Host validation failed: ", error_msg)
			push_error("NetworkManager: Host action rejected: %s" % error_msg)

			if has_node("/root/Main"):
				var main = get_node("/root/Main")
				if main.has_method("show_error_toast"):
					main.call_deferred("show_error_toast", error_msg)
			return

		# Execute via GameManager
		var result = game_manager.apply_action(action)
		print("NetworkManager: Host applied action via relay, result.success = ", result.success)

		if result.success:
			_update_phase_snapshot()

			# Broadcast result to guest via relay
			print("NetworkManager: Broadcasting result via relay")
			_send_via_relay({
				"msg_type": "action_result",
				"result": result
			})
	else:
		# Client sends action to host via relay
		print("NetworkManager: Client (relay) - sending action to host")
		_send_via_relay({
			"msg_type": "game_action",
			"action": action
		})

@rpc("any_peer", "call_remote", "reliable")
func _send_action_to_host(action: Dictionary) -> void:
	if not is_host():
		print("NetworkManager: _send_action_to_host called on non-host, ignoring")
		return

	# Get sender peer ID
	var peer_id = multiplayer.get_remote_sender_id()
	print("NetworkManager: Host received action from client peer %d: %s" % [peer_id, action.get("type")])
	print("NetworkManager: Action details: ", action)

	# Phase 2: Validate action
	var validation = validate_action(action, peer_id)
	print("NetworkManager: Validation result: ", validation)

	if not validation.valid:
		# Get reason from either "reason" field or first error in "errors" array
		var reason = validation.get("reason", "Unknown validation error")
		if reason == "Unknown validation error" and validation.has("errors") and validation.errors.size() > 0:
			reason = validation.errors[0]
		print("NetworkManager: REJECTING action: ", reason)
		print("NetworkManager: Full validation result: ", validation)
		_reject_action.rpc_id(peer_id, action.get("type", ""), reason)
		return

	print("NetworkManager: Action VALIDATED, applying via GameManager")
	# Execute via GameManager - this applies the state changes AND emits result_applied signal
	var result = game_manager.apply_action(action)
	print("NetworkManager: Host applied client action, result.success = ", result.success)

	# CRITICAL LOGGING: Check if result contains sequential_pause for APPLY_SAVES
	if action.get("type") == "APPLY_SAVES":
		print("╔═══════════════════════════════════════════════════════════════")
		print("║ HOST APPLIED CLIENT APPLY_SAVES - CHECKING RESULT")
		print("║ result.success: ", result.success)
		print("║ result.sequential_pause: ", result.get("sequential_pause", false))
		print("║ result.remaining_weapons: ", result.get("remaining_weapons", []).size() if result.has("remaining_weapons") else "MISSING")
		print("║ result.current_weapon_index: ", result.get("current_weapon_index", -1))
		print("╚═══════════════════════════════════════════════════════════════")

	if result.success:
		# Update phase snapshot so next validation sees the changes
		_update_phase_snapshot()

		# Broadcast the result to all clients (but not back to host since it already applied)
		print("NetworkManager: Host broadcasting client action result to all clients")
		_broadcast_result.rpc(result)
	else:
		print("NetworkManager: GameManager returned failure: ", result.get("error", "Unknown"))

@rpc("authority", "call_remote", "reliable")
func _broadcast_result(result: Dictionary) -> void:
	print("NetworkManager: _broadcast_result received, is_host = ", is_host())
	print("NetworkManager: Result keys: ", result.keys())
	print("NetworkManager: Action type: ", result.get("action_type", "NONE"))
	print("NetworkManager: Has save_data_list: ", result.has("save_data_list"))
	if result.has("save_data_list"):
		print("NetworkManager: save_data_list size: ", result.get("save_data_list", []).size())

	if is_host():
		return  # Host already applied locally

	# Client applies the result (with diffs already computed by host)
	print("NetworkManager: Client applying result with %d diffs" % result.get("diffs", []).size())
	game_manager.apply_result(result)

	# Update phase snapshot so it stays in sync with GameState
	_update_phase_snapshot()

	# MULTIPLAYER FIX: Re-emit phase-specific signals for client visual updates
	# When host applies actions, it emits signals that update visuals
	# Clients need to emit the same signals after applying results
	print("NetworkManager: Client calling _emit_client_visual_updates")
	_emit_client_visual_updates(result)

	print("NetworkManager: Client finished applying result")

func _emit_client_visual_updates(result: Dictionary) -> void:
	"""Emit phase-specific signals on client after applying result for visual updates"""
	print("NetworkManager: _emit_client_visual_updates START")
	var action_type = result.get("action_type", "")
	var action_data = result.get("action_data", {})
	print("NetworkManager:   action_type = ", action_type)

	# Get current phase instance
	var phase_manager = get_node_or_null("/root/PhaseManager")
	if not phase_manager:
		print("NetworkManager:   ERROR - PhaseManager not found!")
		return
	if not phase_manager.current_phase_instance:
		print("NetworkManager:   ERROR - No current_phase_instance!")
		return

	var phase = phase_manager.current_phase_instance
	print("NetworkManager:   phase = ", phase)
	print("NetworkManager:   phase has saves_required signal: ", phase.has_signal("saves_required"))

	# Handle movement phase visual updates
	if action_type == "STAGE_MODEL_MOVE":
		if phase.has_signal("model_drop_committed"):
			var unit_id = action_data.get("actor_unit_id", "")
			var model_id = action_data.get("payload", {}).get("model_id", "")
			var dest = action_data.get("payload", {}).get("dest", [])

			if unit_id != "" and model_id != "" and dest.size() == 2:
				var dest_vec = Vector2(dest[0], dest[1])
				print("NetworkManager: Client emitting model_drop_committed for ", unit_id, "/", model_id, " at ", dest_vec)
				phase.emit_signal("model_drop_committed", unit_id, model_id, dest_vec)

	# Handle shooting phase SELECT_SHOOTER visual updates
	if action_type == "SELECT_SHOOTER":
		if phase.has_signal("unit_selected_for_shooting"):
			var unit_id = action_data.get("actor_unit_id", "")
			if unit_id != "":
				print("NetworkManager: Client emitting unit_selected_for_shooting for ", unit_id)
				phase.emit_signal("unit_selected_for_shooting", unit_id)

				# Also emit targets_available with eligible targets
				if phase.has_signal("targets_available"):
					var eligible_targets = RulesEngine.get_eligible_targets(unit_id, GameState.create_snapshot())
					print("NetworkManager: Client emitting targets_available with %d targets" % eligible_targets.size())
					phase.emit_signal("targets_available", unit_id, eligible_targets)

	# Handle shooting phase weapon_order_required signal
	# This happens when CONFIRM_TARGETS detects multiple weapon types
	print("NetworkManager:   Checking for weapon_order_required...")
	if action_type == "CONFIRM_TARGETS":
		var weapon_order_required = result.get("weapon_order_required", false)
		print("NetworkManager:   weapon_order_required = ", weapon_order_required)

		if weapon_order_required and phase.has_signal("weapon_order_required"):
			var confirmed_assignments = result.get("confirmed_assignments", [])
			print("NetworkManager: ✅ Client re-emitting weapon_order_required signal with %d assignments" % confirmed_assignments.size())
			phase.emit_signal("weapon_order_required", confirmed_assignments)

			# Also update the client's phase resolution_state
			if "resolution_state" in phase:
				phase.resolution_state = {
					"phase": "awaiting_weapon_order",
					"assignments": confirmed_assignments
				}
				print("NetworkManager: ✅ Client updated resolution_state")

	# Handle next_weapon_confirmation_required signal for sequential mode
	# This happens when APPLY_SAVES completes OR when RESOLVE_WEAPON_SEQUENCE has no wounds (miss) OR when CONTINUE_SEQUENCE needs next weapon
	# OR when CONFIRM_TARGETS resolves a single weapon that misses (no saves needed)
	print("NetworkManager:   Checking for sequential_pause...")
	if action_type == "APPLY_SAVES" or action_type == "RESOLVE_WEAPON_SEQUENCE" or action_type == "CONTINUE_SEQUENCE" or action_type == "CONFIRM_TARGETS":
		var sequential_pause = result.get("sequential_pause", false)
		print("NetworkManager:   sequential_pause = ", sequential_pause)

		if sequential_pause and phase.has_signal("next_weapon_confirmation_required"):
			var remaining_weapons = result.get("remaining_weapons", [])
			var current_index = result.get("current_weapon_index", 0)
			var last_weapon_result = result.get("last_weapon_result", {})

			print("╔═══════════════════════════════════════════════════════════════")
			print("║ CLIENT RE-EMITTING next_weapon_confirmation_required")
			print("║ Action type: ", action_type)
			print("║ remaining_weapons.size(): ", remaining_weapons.size())
			print("║ current_index: ", current_index)
			print("║ last_weapon_result.size(): ", last_weapon_result.size())
			print("║ last_weapon_result.weapon_name: ", last_weapon_result.get("weapon_name", "MISSING"))
			print("║ Local peer: ", multiplayer.get_unique_id())
			print("║ Local player: ", peer_to_player_map.get(multiplayer.get_unique_id(), -1))
			print("║ Active player: ", game_state.get_active_player() if game_state else -1)

			# Validate remaining weapons
			for i in range(remaining_weapons.size()):
				var weapon = remaining_weapons[i]
				print("║   Weapon %d: %s" % [i, weapon.get("weapon_id", "MISSING")])

			print("╚═══════════════════════════════════════════════════════════════")

			print("NetworkManager: ✅ Client re-emitting next_weapon_confirmation_required with %d remaining weapons" % remaining_weapons.size())
			phase.emit_signal("next_weapon_confirmation_required", remaining_weapons, current_index, last_weapon_result)
		else:
			if not sequential_pause:
				print("NetworkManager: ℹ️ No sequential_pause in result - NOT re-emitting signal")
			elif not phase.has_signal("next_weapon_confirmation_required"):
				print("NetworkManager: ⚠️ Phase doesn't have next_weapon_confirmation_required signal!")

	# Handle dice_rolled signal - re-emit dice data so attacker sees updates
	# This happens when actions contain dice data (hits, wounds, etc.)
	print("NetworkManager:   Checking for dice data...")
	var dice_data = result.get("dice", [])
	if not dice_data.is_empty() and phase.has_signal("dice_rolled"):
		print("NetworkManager: ✅ Client re-emitting dice_rolled signals for %d dice blocks" % dice_data.size())
		for dice_block in dice_data:
			phase.emit_signal("dice_rolled", dice_block)

	# Handle saves_required signal (for both shooting and fight phases)
	# This happens when shooting or melee attacks generate wounds that need saves
	print("NetworkManager:   Checking for saves_required...")
	print("NetworkManager:   action_type == CONFIRM_TARGETS: ", action_type == "CONFIRM_TARGETS")
	print("NetworkManager:   action_type == RESOLVE_SHOOTING: ", action_type == "RESOLVE_SHOOTING")
	print("NetworkManager:   action_type == RESOLVE_WEAPON_SEQUENCE: ", action_type == "RESOLVE_WEAPON_SEQUENCE")
	print("NetworkManager:   action_type == APPLY_SAVES: ", action_type == "APPLY_SAVES")
	print("NetworkManager:   action_type == ROLL_DICE (fight): ", action_type == "ROLL_DICE")
	print("NetworkManager:   action_type == CONFIRM_AND_RESOLVE_ATTACKS (fight): ", action_type == "CONFIRM_AND_RESOLVE_ATTACKS")

	# Check for both shooting and fight phase action types
	var is_shooting_action = action_type in ["CONFIRM_TARGETS", "RESOLVE_SHOOTING", "RESOLVE_WEAPON_SEQUENCE", "APPLY_SAVES"]
	var is_fight_action = action_type in ["ROLL_DICE", "CONFIRM_AND_RESOLVE_ATTACKS"]

	if is_shooting_action or is_fight_action:
		var save_data_list = result.get("save_data_list", [])

		if not save_data_list.is_empty() and phase.has_signal("saves_required"):
			# NEW: Only re-emit if local player is the defender
			var first_save_data = save_data_list[0]
			var target_unit_id = first_save_data.get("target_unit_id", "")

			if target_unit_id != "":
				var target_unit = GameState.get_unit(target_unit_id)
				var defender_player = target_unit.get("owner", -1)

				var local_peer_id = multiplayer.get_unique_id()
				var local_player = peer_to_player_map.get(local_peer_id, -1)

				print("NetworkManager:   Defender check: local=%d, defender=%d" % [local_player, defender_player])

				if local_player == defender_player:
					# LOGGING: Track NetworkManager re-emission
					var timestamp = Time.get_ticks_msec()
					var weapon = first_save_data.get("weapon_name", "unknown")
					var wounds = first_save_data.get("wounds_to_save", 0)

					print("╔═══════════════════════════════════════════════════════════════")
					print("║ SAVES_REQUIRED RE-EMISSION (from NetworkManager)")
					print("║ Timestamp: ", timestamp)
					print("║ Source: NetworkManager._emit_client_visual_updates")
					print("║ Action Type: ", action_type)
					print("║ Local peer ID: ", local_peer_id)
					print("║ Local player: ", local_player)
					print("║ Defender player: ", defender_player)
					print("║ Target: ", target_unit_id)
					print("║ Weapon: ", weapon)
					print("║ Wounds: ", wounds)
					print("║ Save data list size: ", save_data_list.size())
					print("╚═══════════════════════════════════════════════════════════════")

					print("NetworkManager: ✅ Client (defender) re-emitting saves_required signal")
					phase.emit_signal("saves_required", save_data_list)

					# Also store the pending_save_data on the client's phase instance
					if "pending_save_data" in phase:
						phase.pending_save_data = save_data_list
						print("NetworkManager: ✅ Client stored pending_save_data")
				else:
					print("NetworkManager: ℹ️ Client (attacker) skipping saves_required re-emission - local=%d is not defender=%d" % [local_player, defender_player])
			else:
				print("NetworkManager:   ⚠️ No target_unit_id, skipping saves_required check")

	# Handle fight selection dialog trigger (for multiplayer sync after CONSOLIDATE)
	if result.get("trigger_fight_selection", false):
		print("NetworkManager: Result has trigger_fight_selection flag")
		var dialog_data = result.get("fight_selection_data", {})
		if not dialog_data.is_empty() and phase.has_signal("fight_selection_required"):
			print("NetworkManager: Client re-emitting fight_selection_required with subphase: %s, player: %d" % [
				dialog_data.get("current_subphase", "UNKNOWN"),
				dialog_data.get("selecting_player", -1)
			])
			# Update client's local subphase state to match host
			if "current_subphase" in dialog_data and "current_subphase" in phase:
				var subphase_name = dialog_data["current_subphase"]
				# Convert string to enum value
				if subphase_name == "FIGHTS_FIRST":
					phase.current_subphase = phase.Subphase.FIGHTS_FIRST
				elif subphase_name == "REMAINING_COMBATS":
					phase.current_subphase = phase.Subphase.REMAINING_COMBATS
				print("NetworkManager: Updated client current_subphase to: %s" % subphase_name)

			# Update client's selecting player to match host
			if "selecting_player" in dialog_data and "current_selecting_player" in phase:
				phase.current_selecting_player = dialog_data["selecting_player"]
				print("NetworkManager: Updated client current_selecting_player to: %d" % dialog_data["selecting_player"])

			# Emit the signal with the host's dialog data
			phase.emit_signal("fight_selection_required", dialog_data)
		else:
			print("NetworkManager: ⚠️ Missing fight_selection_data or phase doesn't support signal")

	# Handle pile_in_required signal (after SELECT_FIGHTER)
	if result.get("trigger_pile_in", false):
		print("NetworkManager: Result has trigger_pile_in flag")
		var unit_id = result.get("pile_in_unit_id", "")
		var distance = result.get("pile_in_distance", 3.0)
		if phase.has_signal("pile_in_required") and unit_id != "":
			print("NetworkManager: Client re-emitting pile_in_required for unit %s" % unit_id)
			phase.emit_signal("pile_in_required", unit_id, distance)
		else:
			print("NetworkManager: ⚠️ Phase doesn't support pile_in_required or missing unit_id")

	# Handle attack_assignment_required signal (after PILE_IN)
	if result.get("trigger_attack_assignment", false):
		print("NetworkManager: Result has trigger_attack_assignment flag")
		var unit_id = result.get("attack_unit_id", "")
		var targets = result.get("attack_targets", [])
		if phase.has_signal("attack_assignment_required") and unit_id != "":
			print("NetworkManager: Client re-emitting attack_assignment_required for unit %s, targets: %s" % [unit_id, str(targets)])
			phase.emit_signal("attack_assignment_required", unit_id, targets)
		else:
			print("NetworkManager: ⚠️ Phase doesn't support attack_assignment_required or missing unit_id")

	# Handle consolidate_required signal (after ROLL_DICE)
	if result.get("trigger_consolidate", false):
		print("NetworkManager: Result has trigger_consolidate flag")
		var unit_id = result.get("consolidate_unit_id", "")
		var distance = result.get("consolidate_distance", 3.0)
		if phase.has_signal("consolidate_required") and unit_id != "":
			print("NetworkManager: Client re-emitting consolidate_required for unit %s" % unit_id)
			phase.emit_signal("consolidate_required", unit_id, distance)
		else:
			print("NetworkManager: ⚠️ Phase doesn't support consolidate_required or missing unit_id")

	print("NetworkManager: _emit_client_visual_updates END")

# Initial state sync when client joins
@rpc("authority", "call_remote", "reliable")
func _send_initial_state(snapshot: Dictionary) -> void:
	print("NetworkManager: Receiving initial state from host")

	# Replace local state with host's state
	game_state.load_from_snapshot(snapshot)

	print("NetworkManager: State synchronized")
	emit_signal("game_started")

# ============================================================================
# LOAD SYNCHRONIZATION - State sync after host loads a saved game
# ============================================================================

@rpc("authority", "call_remote", "reliable")
func _send_loaded_state(snapshot: Dictionary, save_name: String) -> void:
	"""
	Called by host to synchronize loaded game state to clients.
	Similar to _send_initial_state() but used for mid-game loads.
	"""
	print("NetworkManager: ========================================")
	print("NetworkManager: CLIENT RECEIVED LOADED STATE RPC")
	print("NetworkManager: ========================================")
	print("NetworkManager: Save name: ", save_name)
	print("NetworkManager: Snapshot keys: ", snapshot.keys())
	print("NetworkManager: Snapshot has ", snapshot.get("units", {}).size(), " units")
	print("NetworkManager: Snapshot turn: ", snapshot.get("meta", {}).get("turn_number", "unknown"))

	# Replace local state with host's loaded state
	print("NetworkManager: Applying loaded state to GameState...")
	game_state.load_from_snapshot(snapshot)
	print("NetworkManager: State applied, GameState now has ", game_state.state.get("units", {}).size(), " units")

	# Trigger UI refresh on client side
	print("NetworkManager: Triggering UI refresh on client...")
	_refresh_client_ui_after_load(snapshot)

	print("NetworkManager: Loaded state synchronized")
	print("NetworkManager: ========================================")

func _refresh_client_ui_after_load(snapshot: Dictionary) -> void:
	"""
	Triggers UI refresh on client after receiving loaded state.
	Notifies Main scene to refresh all game elements.
	"""
	# Get Main scene if it exists
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("_refresh_after_load"):
		print("NetworkManager: Triggering client UI refresh")
		main_scene._refresh_after_load()

		# Show notification to client
		if main_scene.has_method("_show_save_notification"):
			var turn = snapshot.get("meta", {}).get("turn_number", 0)
			var phase = snapshot.get("meta", {}).get("phase", "Unknown")
			main_scene._show_save_notification(
				"Host loaded game (Turn %d, %s)" % [turn, phase],
				Color.CYAN
			)
	else:
		print("NetworkManager: Warning - Could not trigger client UI refresh")

func sync_loaded_state() -> void:
	"""
	Called by SaveLoadManager after host loads a game.
	Broadcasts the loaded state to all connected clients.
	"""
	if not is_networked():
		print("NetworkManager: Not in multiplayer, skipping load sync")
		return

	if not is_host():
		push_error("NetworkManager: Only host can sync loaded state!")
		return

	print("NetworkManager: ========================================")
	print("NetworkManager: SYNCING LOADED STATE TO CLIENTS")
	print("NetworkManager: ========================================")

	# Create snapshot of current (newly loaded) state
	var snapshot = game_state.create_snapshot()
	print("NetworkManager: Created snapshot with keys: ", snapshot.keys())
	print("NetworkManager: Snapshot has ", snapshot.get("units", {}).size(), " units")
	print("NetworkManager: Snapshot turn: ", snapshot.get("meta", {}).get("turn_number", "unknown"))

	# Get save name from metadata if available
	var save_name = snapshot.get("meta", {}).get("save_name", "Unknown")

	# Check if we have connected peers
	var peer_count = multiplayer.get_peers().size()
	print("NetworkManager: Broadcasting to ", peer_count, " connected peers")
	print("NetworkManager: Connected peer IDs: ", multiplayer.get_peers())

	# Broadcast to all clients
	_send_loaded_state.rpc(snapshot, save_name)

	print("NetworkManager: Loaded state sync RPC sent")
	print("NetworkManager: ========================================")

# Initiates game start for both host and all clients
@rpc("authority", "call_local", "reliable")
func start_multiplayer_game() -> void:
	print("NetworkManager: Starting multiplayer game - transitioning to Main scene")
	print("NetworkManager: Units in GameState BEFORE scene change: ", game_state.state.get("units", {}).size())

	# DEBUG: Show unit IDs
	if game_state.state.has("units"):
		print("NetworkManager: Unit IDs: ", game_state.state.units.keys())

	# This runs on both host and client due to call_local
	var error = get_tree().change_scene_to_file("res://scenes/Main.tscn")
	if error != OK:
		push_error("NetworkManager: Failed to load Main scene: %d" % error)
		# Fallback: return to lobby
		get_tree().change_scene_to_file("res://scenes/MultiplayerLobby.tscn")
		return

	# Emit local signal for any cleanup
	emit_signal("game_started")

# ============================================================================
# PHASE 2: VALIDATION - Action Validation and Authority
# ============================================================================

func validate_action(action: Dictionary, peer_id: int) -> Dictionary:
	print("NetworkManager: Validating action type=%s from peer_id=%d" % [action.get("type"), peer_id])

	# Layer 1: Schema validation
	if not action.has("type"):
		print("NetworkManager: VALIDATION FAILED - missing type")
		return {"valid": false, "reason": "Invalid action schema - missing type"}

	# Check if this is a phase control action or reactive action that bypasses player/turn validation
	var action_type = action.get("type", "")
	var exempt_actions = [
		"END_DEPLOYMENT",
		"END_PHASE",
		"EMBARK_UNITS_DEPLOYMENT",
		"APPLY_SAVES",  # Reactive action - defender responds during attacker's turn
		# Fight Phase actions - players alternate during active player's turn
		"SELECT_FIGHTER",
		"SELECT_MELEE_WEAPON",
		"PILE_IN",
		"ASSIGN_ATTACKS",
		"CONFIRM_AND_RESOLVE_ATTACKS",
		"ROLL_DICE",
		"CONSOLIDATE",
		"SKIP_UNIT",
		"HEROIC_INTERVENTION",
		"END_FIGHT"
	]
	var is_exempt = action_type in exempt_actions

	if is_exempt:
		print("NetworkManager: Exempt action '%s' - skipping turn validation (allows reactive/cross-turn actions)" % action_type)
		# Skip turn validation for exempt actions - go straight to game rules validation
		# EMBARK_UNITS_DEPLOYMENT: part of the deployment action that just switched turns
		# APPLY_SAVES: reactive action where defender responds during attacker's turn
		# Fight Phase actions: cross-turn actions where players alternate activating units during active player's turn
		#   - Once a player selects a unit, ALL subsequent actions for that activation occur during opponent's turn

		# Still validate player authority (that the peer is who they claim to be)
		if action_type == "APPLY_SAVES":
			var claimed_player = action.get("player", -1)
			var peer_player = peer_to_player_map.get(peer_id, -1)
			print("NetworkManager: APPLY_SAVES authority check - claimed=%d, peer=%d" % [claimed_player, peer_player])
			if claimed_player != peer_player:
				print("NetworkManager: VALIDATION FAILED - player mismatch for APPLY_SAVES")
				return {"valid": false, "reason": "Player ID mismatch (claimed=%d, expected=%d)" % [claimed_player, peer_player]}
	else:
		# Layer 2: Authority validation (only for player-specific actions)
		var claimed_player = action.get("player", -1)
		var peer_player = peer_to_player_map.get(peer_id, -1)
		print("NetworkManager: claimed_player=%d, peer_player=%d (from peer_to_player_map)" % [claimed_player, peer_player])
		print("NetworkManager: peer_to_player_map = ", peer_to_player_map)
		if claimed_player != peer_player:
			print("NetworkManager: VALIDATION FAILED - player mismatch")
			return {"valid": false, "reason": "Player ID mismatch (claimed=%d, expected=%d)" % [claimed_player, peer_player]}

		# Layer 3: Turn validation (only for player-specific actions)
		var active_player = game_state.get_active_player()
		print("NetworkManager: active_player=%d" % active_player)
		if claimed_player != active_player:
			print("NetworkManager: VALIDATION FAILED - not player's turn")
			return {"valid": false, "reason": "Not your turn"}

	# Layer 4: Game rules validation (delegate to phase)
	var phase_mgr = get_node_or_null("/root/PhaseManager")
	print("NetworkManager: phase_mgr = ", phase_mgr)
	if not phase_mgr:
		push_warning("NetworkManager: PhaseManager not available for validation")
		return {"valid": true, "reason": "No phase validation available"}

	var phase = phase_mgr.get_current_phase_instance()
	print("NetworkManager: current_phase_instance = ", phase)
	if phase:
		print("NetworkManager: phase class = ", phase.get_class())
		print("NetworkManager: phase has validate_action? ", phase.has_method("validate_action"))
	if phase and phase.has_method("validate_action"):
		print("NetworkManager: Calling phase.validate_action()")
		var phase_validation = phase.validate_action(action)
		print("NetworkManager: Phase validation result = ", phase_validation)
		return phase_validation
	else:
		print("NetworkManager: No phase or no validate_action method")

	print("NetworkManager: VALIDATION PASSED (no phase validation)")
	return {"valid": true}

@rpc("authority", "call_remote", "reliable")
func _reject_action(action_type: String, reason: String) -> void:
	push_error("NetworkManager: Action rejected: %s - %s" % [action_type, reason])
	# Emit signal so UI can display rejection reason to player
	action_rejected.emit(action_type, reason)
	print("NetworkManager: Emitted action_rejected signal - type=%s, reason=%s" % [action_type, reason])

# ============================================================================
# PHASE 3: TURN TIMER - Timeout Enforcement
# ============================================================================

func start_turn_timer() -> void:
	if not is_networked() or not is_host():
		return

	turn_timer.start(TURN_TIMEOUT_SECONDS)
	print("NetworkManager: Turn timer started - ", TURN_TIMEOUT_SECONDS, " seconds")

func stop_turn_timer() -> void:
	if turn_timer:
		turn_timer.stop()

func _on_turn_timeout() -> void:
	if not is_host():
		return

	print("NetworkManager: Turn timeout!")
	var current_player = game_state.get_active_player()
	var winner = 3 - current_player  # Other player wins (1->2, 2->1)

	_broadcast_game_over.rpc(winner, "turn_timeout")

@rpc("authority", "call_remote", "reliable")
func _broadcast_game_over(winner: int, reason: String) -> void:
	print("NetworkManager: Game over! Winner: Player %d (%s)" % [winner, reason])
	# TODO: Show game over UI with winner and reason

# Hook into phase changes to restart timer
func _on_phase_changed(new_phase: GameStateData.Phase) -> void:
	if not is_networked():
		return

	# Restart timer on each phase change
	if is_host():
		start_turn_timer()

# ============================================================================
# PHASE 4: DETERMINISTIC RNG - Seed Generation
# ============================================================================

func get_next_rng_seed() -> int:
	if not is_networked():
		return -1  # Single player - non-deterministic

	if not is_host():
		push_error("NetworkManager: Only host can generate RNG seeds!")
		return -1

	rng_seed_counter += 1
	var seed_value = hash([game_session_id, rng_seed_counter, game_state.get_turn_number()])
	print("NetworkManager: Generated RNG seed: ", seed_value)
	return seed_value

# ============================================================================
# CONNECTION EVENTS
# ============================================================================

func _on_peer_connected(peer_id: int) -> void:
	print("NetworkManager: Peer connected - ", peer_id)

	if is_host():
		# Assign player 2 to new peer
		peer_to_player_map[peer_id] = 2

		# Send full game state to joining client
		var snapshot = game_state.create_snapshot()
		_send_initial_state.rpc_id(peer_id, snapshot)

		emit_signal("peer_connected", peer_id)
		emit_signal("game_started")
	else:
		# Client successfully connected to host
		# The peer_id here is the server (always 1)
		print("NetworkManager: Successfully connected to host")
		# Client is always player 2
		var my_peer_id = multiplayer.get_unique_id()
		peer_to_player_map[my_peer_id] = 2
		print("NetworkManager: Client set peer_to_player_map[%d] = 2" % my_peer_id)

		# Update window title to show player number
		DisplayServer.window_set_title("40k Game - PLAYER 2 (CLIENT)")

		print("========================================")
		print("   YOU ARE: PLAYER 2 (CLIENT)")
		print("   Connected to host")
		print("========================================")

		emit_signal("peer_connected", peer_id)
		emit_signal("game_started")

func _on_peer_disconnected(peer_id: int) -> void:
	print("NetworkManager: Peer disconnected - ", peer_id)

	if peer_to_player_map.has(peer_id):
		peer_to_player_map.erase(peer_id)

	emit_signal("peer_disconnected", peer_id)

	# MVP: End game on disconnect
	push_error("Player disconnected - game ending")
	get_tree().quit()

func _on_connection_failed() -> void:
	print("NetworkManager: Connection failed")
	emit_signal("connection_failed", "Could not connect to host")
	network_mode = NetworkMode.OFFLINE

# ============================================================================
# PHASE SNAPSHOT MANAGEMENT
# ============================================================================

func _update_phase_snapshot() -> void:
	"""Update the current phase's snapshot after applying state changes"""
	var phase_manager = get_node_or_null("/root/PhaseManager")
	if not phase_manager:
		return

	var current_phase = phase_manager.get_current_phase_instance()
	if not current_phase:
		return

	# Create fresh snapshot from current GameState
	var new_snapshot = game_state.create_snapshot()

	# Update phase's internal snapshot
	if current_phase.has_method("update_local_state"):
		current_phase.update_local_state(new_snapshot)
		print("NetworkManager: Updated phase snapshot with ", new_snapshot.get("units", {}).size(), " units")
