@tool
extends Node

# Editor-side bridge. Runs only inside the Godot editor (not the running game).
# Hosts a tiny TCP server on a different port and provides commands that need
# EditorInterface — e.g. play / stop scene, list project scenes, get the
# currently edited scene path.
#
# The runtime autoload (mcp_server.gd) listens on port 9080 inside the running
# game; this editor bridge listens on 9081 in the editor. The Node.js MCP
# bridge picks the correct port per command.

const DEFAULT_PORT := 9081

var editor_plugin: EditorPlugin = null

var _server: TCPServer = null
var _port: int = DEFAULT_PORT
var _connections: Array = []
var _running := false


func start() -> void:
	if _running:
		return
	var env_port := OS.get_environment("GODOT_MCP_EDITOR_PORT")
	if env_port != "":
		var parsed := int(env_port)
		if parsed > 0:
			_port = parsed
	_server = TCPServer.new()
	var err := _server.listen(_port, "127.0.0.1")
	if err != OK:
		push_warning("[GodotMCP] Editor bridge failed to listen on %d: %s" % [_port, error_string(err)])
		_server = null
		return
	_running = true
	set_process(true)
	print("[GodotMCP] Editor bridge listening on 127.0.0.1:%d" % _port)


func stop() -> void:
	_running = false
	set_process(false)
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
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer:
			peer.set_no_delay(true)
			_connections.append({"peer": peer, "buffer": PackedByteArray()})
	for i in range(_connections.size() - 1, -1, -1):
		var conn = _connections[i]
		var peer: StreamPeerTCP = conn.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_connections.remove_at(i)
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			var got := peer.get_data(available)
			if got[0] == OK:
				var buf: PackedByteArray = conn.buffer
				buf.append_array(got[1])
				conn.buffer = buf
		_drain(conn)


func _drain(conn: Dictionary) -> void:
	var buf: PackedByteArray = conn.buffer
	while true:
		var nl := buf.find(0x0A)
		if nl == -1:
			conn.buffer = buf
			return
		var line := buf.slice(0, nl)
		buf = buf.slice(nl + 1)
		conn.buffer = buf
		var text := line.get_string_from_utf8().strip_edges()
		if text == "":
			continue
		_handle(conn.peer, text)


func _handle(peer: StreamPeerTCP, text: String) -> void:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_reply(peer, null, {"status": "error", "message": "Invalid JSON"})
		return
	var msg: Dictionary = parsed
	var msg_id = msg.get("id", null)
	var command := str(msg.get("command", ""))
	var params: Dictionary = msg.get("params", {}) if typeof(msg.get("params", {})) == TYPE_DICTIONARY else {}
	var result: Dictionary
	match command:
		"ping":
			result = {"status": "ok", "where": "editor", "engine_version": Engine.get_version_info()}
		"play_scene":
			result = _cmd_play_scene(params)
		"play_main_scene":
			result = _cmd_play_main_scene()
		"stop_scene":
			result = _cmd_stop_scene()
		"get_edited_scene":
			result = _cmd_get_edited_scene()
		"list_scenes":
			result = _cmd_list_scenes(params)
		"reload_scripts":
			result = _cmd_reload_scripts()
		_:
			result = {"status": "error", "message": "Unknown editor command: %s" % command}
	_reply(peer, msg_id, result)


func _reply(peer: StreamPeerTCP, msg_id, result: Dictionary) -> void:
	var envelope := {"id": msg_id, "result": result}
	var bytes := (JSON.stringify(envelope) + "\n").to_utf8_buffer()
	peer.put_data(bytes)


# --- Editor commands -----------------------------------------------------

func _cmd_play_scene(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	if path == "":
		EditorInterface.play_main_scene()
		return {"status": "ok", "played": "main_scene"}
	if not FileAccess.file_exists(path):
		return {"status": "error", "message": "Scene not found: %s" % path}
	EditorInterface.play_custom_scene(path)
	return {"status": "ok", "played": path}


func _cmd_play_main_scene() -> Dictionary:
	EditorInterface.play_main_scene()
	return {"status": "ok"}


func _cmd_stop_scene() -> Dictionary:
	EditorInterface.stop_playing_scene()
	return {"status": "ok"}


func _cmd_get_edited_scene() -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return {"status": "ok", "scene": null}
	return {
		"status": "ok",
		"scene": {
			"name": root.name,
			"type": root.get_class(),
			"path": root.scene_file_path,
		},
	}


func _cmd_list_scenes(params: Dictionary) -> Dictionary:
	var dir_path: String = params.get("path", "res://scenes")
	var results := []
	_walk_scenes(dir_path, results)
	return {"status": "ok", "scenes": results}


func _walk_scenes(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := path
		if not full.ends_with("/"):
			full += "/"
		full += entry
		if dir.current_is_dir():
			_walk_scenes(full, out)
		elif entry.ends_with(".tscn") or entry.ends_with(".scn"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _cmd_reload_scripts() -> Dictionary:
	var rfs := EditorInterface.get_resource_filesystem()
	if rfs:
		rfs.scan()
	return {"status": "ok"}
