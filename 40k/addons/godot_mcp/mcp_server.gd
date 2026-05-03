extends Node

# Runtime autoload. Starts a TCP server on a configurable port and dispatches
# incoming JSON-RPC-style commands to the command router. Each line on the
# socket is a single JSON message terminated by '\n'. Responses are also one
# JSON object per line.
#
# This autoload is registered by the editor plugin in addons/godot_mcp/plugin.gd.
# It does nothing if disabled via the GODOT_MCP_DISABLED env var.
#
# The server is intentionally line-delimited JSON (NDJSON) over TCP rather than
# WebSocket. WebSocket framing adds complexity for no benefit on localhost where
# the only client is a trusted MCP bridge process. The bridge translates between
# stdio MCP protocol and this NDJSON socket.

const CommandRouter := preload("res://addons/godot_mcp/command_router.gd")

const DEFAULT_PORT := 9080
const RECV_BUF_LIMIT := 8 * 1024 * 1024  # 8 MB safety cap on per-connection buffer

var _server: TCPServer = null
var _port: int = DEFAULT_PORT
var _connections: Array = []  # Array of { peer: StreamPeerTCP, buffer: PackedByteArray }
var _router: RefCounted = null
var _enabled := true


func _ready() -> void:
	if OS.has_feature("editor") == false and OS.get_environment("GODOT_MCP_DISABLED") == "1":
		_enabled = false
		print("[GodotMCP] Disabled via GODOT_MCP_DISABLED=1")
		return

	# Allow the port to be overridden via env or project setting for CI.
	var env_port := OS.get_environment("GODOT_MCP_PORT")
	if env_port != "":
		var parsed := int(env_port)
		if parsed > 0:
			_port = parsed

	_router = CommandRouter.new()
	_router.host = self
	_start_server()
	set_process(true)


func _exit_tree() -> void:
	_stop_server()


func _start_server() -> void:
	_server = TCPServer.new()
	var err := _server.listen(_port, "127.0.0.1")
	if err != OK:
		push_warning("[GodotMCP] Failed to listen on port %d: %s" % [_port, error_string(err)])
		_server = null
		return
	print("[GodotMCP] Listening on 127.0.0.1:%d" % _port)


func _stop_server() -> void:
	if _server:
		_server.stop()
		_server = null
	for conn in _connections:
		var peer: StreamPeerTCP = conn.peer
		if peer:
			peer.disconnect_from_host()
	_connections.clear()


func _process(_delta: float) -> void:
	if _server == null:
		return

	# Accept new connections.
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer:
			peer.set_no_delay(true)
			_connections.append({"peer": peer, "buffer": PackedByteArray()})
			print("[GodotMCP] Client connected from %s" % str(peer.get_connected_host()))

	# Service existing connections.
	for i in range(_connections.size() - 1, -1, -1):
		var conn = _connections[i]
		var peer: StreamPeerTCP = conn.peer
		peer.poll()
		var status := peer.get_status()
		if status != StreamPeerTCP.STATUS_CONNECTED:
			print("[GodotMCP] Client disconnected (status=%d)" % status)
			_connections.remove_at(i)
			continue

		# Drain available bytes into the per-connection buffer.
		# PackedByteArray inside a Dictionary is copy-on-write, so we extract
		# the buffer, mutate it locally, then re-assign.
		var available := peer.get_available_bytes()
		if available > 0:
			var chunk := peer.get_data(available)
			if chunk[0] == OK:
				var buf: PackedByteArray = conn.buffer
				buf.append_array(chunk[1])
				conn.buffer = buf
				if buf.size() > RECV_BUF_LIMIT:
					_send_error(peer, null, "Buffer overflow; closing connection")
					peer.disconnect_from_host()
					_connections.remove_at(i)
					continue

		# Process any complete (newline-terminated) messages in buffer.
		_process_buffer(conn)


func _process_buffer(conn: Dictionary) -> void:
	var buffer: PackedByteArray = conn.buffer
	while true:
		var newline := buffer.find(0x0A)  # \n
		if newline == -1:
			break
		var line := buffer.slice(0, newline)
		buffer = buffer.slice(newline + 1)
		conn.buffer = buffer
		var text := line.get_string_from_utf8()
		text = text.strip_edges()
		if text == "":
			continue
		_handle_message(conn.peer, text)


func _handle_message(peer: StreamPeerTCP, text: String) -> void:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_send_error(peer, null, "Invalid JSON or not an object")
		return
	var msg: Dictionary = parsed
	var msg_id = msg.get("id", null)
	var command = msg.get("command", "")
	var params = msg.get("params", {})
	if typeof(params) != TYPE_DICTIONARY:
		_send_error(peer, msg_id, "params must be an object")
		return
	if typeof(command) != TYPE_STRING or command == "":
		_send_error(peer, msg_id, "command must be a non-empty string")
		return
	# Route asynchronously so handlers can `await`.
	_dispatch_async(peer, msg_id, command, params)


func _dispatch_async(peer: StreamPeerTCP, msg_id, command: String, params: Dictionary) -> void:
	var result = await _router.dispatch(command, params)
	if typeof(result) != TYPE_DICTIONARY:
		result = {"status": "ok", "value": result}
	var envelope := {
		"id": msg_id,
		"command": command,
		"result": result,
	}
	_send_json(peer, envelope)


func _send_json(peer: StreamPeerTCP, obj: Dictionary) -> void:
	if peer == null:
		return
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var text := JSON.stringify(obj) + "\n"
	var bytes := text.to_utf8_buffer()
	peer.put_data(bytes)


func _send_error(peer: StreamPeerTCP, msg_id, message: String) -> void:
	_send_json(peer, {
		"id": msg_id,
		"result": {"status": "error", "message": message},
	})
