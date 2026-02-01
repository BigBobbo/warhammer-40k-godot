extends Node

# Dedicated Server for Warhammer 40K Online Multiplayer
# Runs headless and manages WebSocket connections between players

const GameCodeManager = preload("res://server/GameCodeManager.gd")

# Server configuration
const DEFAULT_PORT = 9080
const MAX_CLIENTS = 100  # 50 games * 2 players

# References
var game_code_manager: Node = null
var ws_peer: WebSocketMultiplayerPeer = null

# Client state tracking
var client_states: Dictionary = {}  # peer_id -> ClientState

class ClientState:
	var peer_id: int = -1
	var game_code: String = ""
	var player_number: int = -1
	var connected_at: float = 0.0
	var is_host: bool = false

	func _init(id: int) -> void:
		peer_id = id
		connected_at = Time.get_unix_time_from_system()

func _ready() -> void:
	print("========================================")
	print(" Warhammer 40K Dedicated Server")
	print("========================================")

	# Initialize game code manager
	game_code_manager = GameCodeManager.new()
	add_child(game_code_manager)
	game_code_manager.game_created.connect(_on_game_created)
	game_code_manager.game_joined.connect(_on_game_joined)
	game_code_manager.game_removed.connect(_on_game_removed)

	# Start WebSocket server
	_start_server()

	# Set up stats timer
	var stats_timer = Timer.new()
	stats_timer.wait_time = 60.0
	stats_timer.timeout.connect(_print_stats)
	stats_timer.autostart = true
	add_child(stats_timer)

func _start_server() -> void:
	var port = _get_port()

	ws_peer = WebSocketMultiplayerPeer.new()
	var error = ws_peer.create_server(port)

	if error != OK:
		push_error("Server: Failed to start on port %d - error %d" % [port, error])
		get_tree().quit(1)
		return

	multiplayer.multiplayer_peer = ws_peer

	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	print("Server: Started on port %d" % port)
	print("Server: Waiting for connections...")

func _get_port() -> int:
	# Check for PORT environment variable (used by Fly.io)
	if OS.has_environment("PORT"):
		return OS.get_environment("PORT").to_int()

	# Check command line arguments
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "--port" and i + 1 < args.size():
			return args[i + 1].to_int()

	return DEFAULT_PORT

func _on_peer_connected(peer_id: int) -> void:
	print("Server: Client connected - peer_id: %d" % peer_id)

	# Create client state
	var state = ClientState.new(peer_id)
	client_states[peer_id] = state

	# Send welcome message
	_send_welcome.rpc_id(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	print("Server: Client disconnected - peer_id: %d" % peer_id)

	# Notify game code manager
	game_code_manager.on_peer_disconnected(peer_id)

	# Clean up client state
	if client_states.has(peer_id):
		var state: ClientState = client_states[peer_id]

		# If this was a host, notify the guest
		if state.is_host and state.game_code != "":
			var session = game_code_manager.get_session(state.game_code)
			if session and session.guest_peer_id != -1:
				_notify_host_disconnected.rpc_id(session.guest_peer_id)

		# If this was a guest, notify the host
		elif not state.is_host and state.game_code != "":
			var session = game_code_manager.get_session(state.game_code)
			if session:
				_notify_guest_disconnected.rpc_id(session.host_peer_id)

		client_states.erase(peer_id)

func _on_game_created(game_code: String, host_peer_id: int) -> void:
	print("Server: Game created - code: %s, host: %d" % [game_code, host_peer_id])

	if client_states.has(host_peer_id):
		var state: ClientState = client_states[host_peer_id]
		state.game_code = game_code
		state.player_number = 1
		state.is_host = true

func _on_game_joined(game_code: String, guest_peer_id: int) -> void:
	print("Server: Guest joined - code: %s, guest: %d" % [game_code, guest_peer_id])

	if client_states.has(guest_peer_id):
		var state: ClientState = client_states[guest_peer_id]
		state.game_code = game_code
		state.player_number = 2
		state.is_host = false

func _on_game_removed(game_code: String) -> void:
	print("Server: Game removed - code: %s" % game_code)

func _print_stats() -> void:
	var stats = game_code_manager.get_stats()
	print("Server Stats: %d connected clients, %d total games (%d waiting, %d playing)" % [
		client_states.size(),
		stats.total_games,
		stats.waiting,
		stats.playing
	])

# ============================================================================
# RPC Functions - Server -> Client
# ============================================================================

@rpc("authority", "call_remote", "reliable")
func _send_welcome() -> void:
	# Sent to newly connected clients
	pass

@rpc("authority", "call_remote", "reliable")
func _send_game_code(code: String) -> void:
	# Sent to client when their game is created
	pass

@rpc("authority", "call_remote", "reliable")
func _send_join_success(host_peer_id: int, game_code: String) -> void:
	# Sent to client when they successfully join a game
	pass

@rpc("authority", "call_remote", "reliable")
func _send_join_error(error: String) -> void:
	# Sent to client when join fails
	pass

@rpc("authority", "call_remote", "reliable")
func _notify_guest_joined(guest_peer_id: int) -> void:
	# Sent to host when a guest joins their game
	pass

@rpc("authority", "call_remote", "reliable")
func _notify_host_disconnected() -> void:
	# Sent to guest when host disconnects
	pass

@rpc("authority", "call_remote", "reliable")
func _notify_guest_disconnected() -> void:
	# Sent to host when guest disconnects
	pass

# ============================================================================
# RPC Functions - Client -> Server
# ============================================================================

@rpc("any_peer", "call_remote", "reliable")
func _request_create_game() -> void:
	"""Client requests to create a new game and get a code."""
	var peer_id = multiplayer.get_remote_sender_id()
	print("Server: Create game request from peer %d" % peer_id)

	var code = game_code_manager.create_game(peer_id)

	if code.is_empty():
		_send_join_error.rpc_id(peer_id, "Could not create game. Server may be full.")
		return

	_send_game_code.rpc_id(peer_id, code)

@rpc("any_peer", "call_remote", "reliable")
func _request_join_game(game_code: String) -> void:
	"""Client requests to join an existing game."""
	var peer_id = multiplayer.get_remote_sender_id()
	print("Server: Join game request from peer %d for code %s" % [peer_id, game_code])

	var result = game_code_manager.join_game(game_code, peer_id)

	if not result.success:
		_send_join_error.rpc_id(peer_id, result.error)
		return

	var host_peer_id = result.host_peer_id

	# Notify the joining client
	_send_join_success.rpc_id(peer_id, host_peer_id, game_code)

	# Notify the host that someone joined
	_notify_guest_joined.rpc_id(host_peer_id, peer_id)

@rpc("any_peer", "call_remote", "reliable")
func _relay_to_peer(target_peer_id: int, message_type: String, data: Dictionary) -> void:
	"""Relay a message from one peer to another in the same game."""
	var sender_id = multiplayer.get_remote_sender_id()

	# Verify both peers are in the same game
	if not client_states.has(sender_id) or not client_states.has(target_peer_id):
		print("Server: Relay failed - unknown peer")
		return

	var sender_state: ClientState = client_states[sender_id]
	var target_state: ClientState = client_states[target_peer_id]

	if sender_state.game_code != target_state.game_code:
		print("Server: Relay failed - peers not in same game")
		return

	# Update game activity
	game_code_manager.update_game_activity(sender_state.game_code)

	# Relay the message
	_receive_relayed_message.rpc_id(target_peer_id, sender_id, message_type, data)

@rpc("authority", "call_remote", "reliable")
func _receive_relayed_message(_sender_id: int, _message_type: String, _data: Dictionary) -> void:
	# This is received by clients - handled in NetworkManager
	pass

@rpc("any_peer", "call_remote", "reliable")
func _relay_game_action(data: Dictionary) -> void:
	"""Relay a game action to the other player in the game."""
	var sender_id = multiplayer.get_remote_sender_id()

	if not client_states.has(sender_id):
		print("Server: Relay action failed - unknown peer")
		return

	var sender_state: ClientState = client_states[sender_id]
	if sender_state.game_code.is_empty():
		print("Server: Relay action failed - peer not in a game")
		return

	var session = game_code_manager.get_session(sender_state.game_code)
	if not session:
		print("Server: Relay action failed - game not found")
		return

	# Determine target peer
	var target_peer_id = -1
	if sender_id == session.host_peer_id:
		target_peer_id = session.guest_peer_id
	else:
		target_peer_id = session.host_peer_id

	if target_peer_id == -1:
		print("Server: Relay action failed - no opponent")
		return

	# Update game activity
	game_code_manager.update_game_activity(sender_state.game_code)

	# Relay the action
	_receive_game_action.rpc_id(target_peer_id, sender_id, data)

@rpc("authority", "call_remote", "reliable")
func _receive_game_action(_sender_id: int, _data: Dictionary) -> void:
	# This is received by clients - handled in NetworkManager
	pass
