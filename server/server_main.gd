extends Node

# Dedicated Server for Warhammer 40K Online Multiplayer
# Uses plain WebSocket with JSON messages (not Godot RPC)

const GameCodeManagerScript = preload("res://server/GameCodeManager.gd")

# Server configuration
const DEFAULT_PORT = 9080

# References
var game_code_manager: Node = null
var tcp_server: TCPServer = null
var websocket_peers: Dictionary = {}  # peer_id -> WebSocketPeer

# Client state tracking
var client_states: Dictionary = {}  # peer_id -> ClientState
var next_peer_id: int = 1

class ClientState:
	var peer_id: int = -1
	var game_code: String = ""
	var is_host: bool = false
	var connected_at: float = 0.0

	func _init(id: int) -> void:
		peer_id = id
		connected_at = Time.get_unix_time_from_system()

func _ready() -> void:
	print("========================================")
	print(" Warhammer 40K Dedicated Server")
	print("========================================")

	# Initialize game code manager
	game_code_manager = GameCodeManagerScript.new()
	add_child(game_code_manager)

	# Start server
	_start_server()

	# Set up stats timer
	var stats_timer = Timer.new()
	stats_timer.wait_time = 60.0
	stats_timer.timeout.connect(_print_stats)
	stats_timer.autostart = true
	add_child(stats_timer)

func _start_server() -> void:
	var port = _get_port()

	tcp_server = TCPServer.new()
	var err = tcp_server.listen(port)

	if err != OK:
		push_error("Server: Failed to start on port %d - error %d" % [port, err])
		get_tree().quit(1)
		return

	print("Server: Listening on port %d" % port)
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

func _process(_delta: float) -> void:
	# Accept new connections
	while tcp_server and tcp_server.is_connection_available():
		var tcp_peer = tcp_server.take_connection()
		var ws_peer = WebSocketPeer.new()
		ws_peer.accept_stream(tcp_peer)

		var peer_id = next_peer_id
		next_peer_id += 1

		websocket_peers[peer_id] = ws_peer
		client_states[peer_id] = ClientState.new(peer_id)

		print("Server: New connection, assigned peer_id: %d" % peer_id)

	# Process existing connections
	var peers_to_remove: Array[int] = []

	for peer_id in websocket_peers:
		var ws: WebSocketPeer = websocket_peers[peer_id]
		ws.poll()

		var state = ws.get_ready_state()

		match state:
			WebSocketPeer.STATE_OPEN:
				# Process incoming messages
				while ws.get_available_packet_count() > 0:
					var packet = ws.get_packet()
					_handle_message(peer_id, packet)

			WebSocketPeer.STATE_CLOSING:
				pass

			WebSocketPeer.STATE_CLOSED:
				print("Server: Peer %d disconnected" % peer_id)
				peers_to_remove.append(peer_id)

	# Remove disconnected peers
	for peer_id in peers_to_remove:
		_on_peer_disconnected(peer_id)

func _handle_message(peer_id: int, packet: PackedByteArray) -> void:
	var text = packet.get_string_from_utf8()

	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		print("Server: Failed to parse message from peer %d: %s" % [peer_id, text])
		return

	var msg = json.data
	if not msg is Dictionary:
		return

	var msg_type = msg.get("type", "")
	print("Server: Received '%s' from peer %d" % [msg_type, peer_id])

	match msg_type:
		"create":
			_handle_create_game(peer_id)
		"join":
			var code = msg.get("code", "")
			_handle_join_game(peer_id, code)
		"relay":
			var data = msg.get("data", {})
			_handle_relay(peer_id, data)

func _handle_create_game(peer_id: int) -> void:
	var code = game_code_manager.create_game(peer_id)

	if code.is_empty():
		_send_message(peer_id, {"type": "error", "message": "Could not create game"})
		return

	var state = client_states.get(peer_id)
	if state:
		state.game_code = code
		state.is_host = true

	_send_message(peer_id, {"type": "created", "code": code})
	print("Server: Created game %s for peer %d" % [code, peer_id])

func _handle_join_game(peer_id: int, code: String) -> void:
	var result = game_code_manager.join_game(code, peer_id)

	if not result.success:
		_send_message(peer_id, {"type": "error", "message": result.error})
		return

	var state = client_states.get(peer_id)
	if state:
		state.game_code = code
		state.is_host = false

	# Notify the joining player
	_send_message(peer_id, {"type": "joined", "code": code})

	# Notify the host that someone joined
	var host_peer_id = result.host_peer_id
	_send_message(host_peer_id, {"type": "guest_joined"})

	print("Server: Peer %d joined game %s (host: %d)" % [peer_id, code, host_peer_id])

func _handle_relay(peer_id: int, data: Dictionary) -> void:
	var state = client_states.get(peer_id)
	if not state or state.game_code.is_empty():
		return

	var session = game_code_manager.get_session(state.game_code)
	if not session:
		return

	# Determine the target peer (the other player)
	var target_peer_id = -1
	if peer_id == session.host_peer_id:
		target_peer_id = session.guest_peer_id
	else:
		target_peer_id = session.host_peer_id

	if target_peer_id == -1:
		return

	# Relay the message
	_send_message(target_peer_id, {"type": "relay", "data": data})

	# Update activity
	game_code_manager.update_game_activity(state.game_code)

func _on_peer_disconnected(peer_id: int) -> void:
	var state = client_states.get(peer_id)

	if state and not state.game_code.is_empty():
		var session = game_code_manager.get_session(state.game_code)
		if session:
			# Notify the other player
			var other_peer_id = -1
			if peer_id == session.host_peer_id:
				other_peer_id = session.guest_peer_id
			else:
				other_peer_id = session.host_peer_id

			if other_peer_id != -1:
				_send_message(other_peer_id, {"type": "opponent_disconnected"})

		# Clean up from game code manager
		game_code_manager.on_peer_disconnected(peer_id)

	# Remove from tracking
	websocket_peers.erase(peer_id)
	client_states.erase(peer_id)

func _send_message(peer_id: int, msg: Dictionary) -> void:
	var ws = websocket_peers.get(peer_id)
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	var json = JSON.stringify(msg)
	ws.send_text(json)

func _print_stats() -> void:
	var stats = game_code_manager.get_stats()
	print("Server Stats: %d connected clients, %d total games (%d waiting, %d playing)" % [
		websocket_peers.size(),
		stats.total_games,
		stats.waiting,
		stats.playing
	])
