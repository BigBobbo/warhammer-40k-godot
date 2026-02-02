extends Node

# WebSocketRelay - Handles connection to the relay server for online multiplayer
# Uses simple JSON messages instead of Godot's RPC system

signal connected()
signal disconnected()
signal connection_error(message: String)
signal game_created(code: String)
signal game_joined(code: String)
signal guest_joined()
signal opponent_disconnected()
signal message_received(data: Dictionary)

var socket: WebSocketPeer = null
var server_url: String = ""
var is_connected: bool = false
var is_host: bool = false
var game_code: String = ""

func _ready() -> void:
	# Load server URL from TransportFactory
	var transport = get_node_or_null("/root/TransportFactory")
	if transport:
		server_url = transport.get_production_server_url()
	else:
		server_url = "wss://warhammer-40k-godot.fly.dev"

	print("WebSocketRelay: Initialized with server URL: ", server_url)

func _process(_delta: float) -> void:
	if socket == null:
		return

	socket.poll()

	var state = socket.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not is_connected:
				is_connected = true
				print("WebSocketRelay: Connected to server")
				connected.emit()

			# Process incoming messages
			while socket.get_available_packet_count() > 0:
				var packet = socket.get_packet()
				_handle_packet(packet)

		WebSocketPeer.STATE_CLOSING:
			pass

		WebSocketPeer.STATE_CLOSED:
			if is_connected:
				is_connected = false
				var code = socket.get_close_code()
				var reason = socket.get_close_reason()
				print("WebSocketRelay: Disconnected (code: %d, reason: %s)" % [code, reason])
				disconnected.emit()
			socket = null

func connect_to_server() -> int:
	if socket != null:
		socket.close()

	socket = WebSocketPeer.new()
	var err = socket.connect_to_url(server_url)

	if err != OK:
		print("WebSocketRelay: Failed to connect to ", server_url, " error: ", err)
		connection_error.emit("Failed to connect to server")
		return err

	print("WebSocketRelay: Connecting to ", server_url)
	return OK

func disconnect_from_server() -> void:
	if socket != null:
		socket.close()
		socket = null
	is_connected = false
	is_host = false
	game_code = ""

func create_game() -> void:
	if not is_connected:
		connection_error.emit("Not connected to server")
		return

	is_host = true
	_send_message({"type": "create"})

func join_game(code: String) -> void:
	if not is_connected:
		connection_error.emit("Not connected to server")
		return

	is_host = false
	_send_message({"type": "join", "code": code})

func send_game_data(data: Dictionary) -> void:
	if not is_connected:
		return

	_send_message({"type": "relay", "data": data})

func _send_message(msg: Dictionary) -> void:
	if socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	var json = JSON.stringify(msg)
	socket.send_text(json)

func _handle_packet(packet: PackedByteArray) -> void:
	var text = packet.get_string_from_utf8()

	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		print("WebSocketRelay: Failed to parse message: ", text)
		return

	var msg = json.data
	if not msg is Dictionary:
		return

	var msg_type = msg.get("type", "")

	match msg_type:
		"created":
			game_code = msg.get("code", "")
			print("WebSocketRelay: Game created with code: ", game_code)
			game_created.emit(game_code)

		"joined":
			game_code = msg.get("code", "")
			print("WebSocketRelay: Joined game: ", game_code)
			game_joined.emit(game_code)

		"guest_joined":
			print("WebSocketRelay: Guest joined the game")
			guest_joined.emit()

		"opponent_disconnected":
			print("WebSocketRelay: Opponent disconnected")
			opponent_disconnected.emit()

		"relay":
			var data = msg.get("data", {})
			message_received.emit(data)

		"error":
			var error_msg = msg.get("message", "Unknown error")
			print("WebSocketRelay: Error from server: ", error_msg)
			connection_error.emit(error_msg)

func get_game_code() -> String:
	return game_code

func is_game_host() -> bool:
	return is_host
