extends RefCounted

# Generic Godot tools — project info, scene tree, node properties, scripts.
# Every public method (no leading underscore) is auto-registered as a command.

var host: Node = null


# --- Project --------------------------------------------------------------

func get_project_info(_params: Dictionary) -> Dictionary:
	return {
		"status": "ok",
		"project_name": ProjectSettings.get_setting("application/config/name", ""),
		"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
		"engine_version": Engine.get_version_info(),
		"viewport_size": [
			ProjectSettings.get_setting("display/window/size/viewport_width", 0),
			ProjectSettings.get_setting("display/window/size/viewport_height", 0),
		],
		"feature_flags": OS.get_cmdline_args(),
	}


func get_project_setting(params: Dictionary) -> Dictionary:
	var key: String = params.get("key", "")
	if key == "":
		return {"status": "error", "message": "Missing 'key'"}
	return {
		"status": "ok",
		"key": key,
		"value": ProjectSettings.get_setting(key, null),
	}


func list_files(params: Dictionary) -> Dictionary:
	# List files under a `res://` directory. Useful for discovering scenes/scripts.
	var path: String = params.get("path", "res://")
	var pattern: String = params.get("pattern", "")
	var recursive: bool = params.get("recursive", false)
	var results: Array = []
	_walk(path, pattern, recursive, results)
	return {"status": "ok", "path": path, "files": results}


func list_scenes(params: Dictionary) -> Dictionary:
	# Recursively enumerate `*.tscn` scene files under the given root. Default
	# root is `res://`. Implemented runtime-side so it works from a running
	# game without needing the editor bridge.
	var path: String = params.get("path", "res://")
	var results: Array = []
	_walk(path, "*.tscn", true, results)
	return {"status": "ok", "path": path, "scenes": results}


func _walk(dir_path: String, pattern: String, recursive: bool, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := dir_path
		if not full.ends_with("/"):
			full += "/"
		full += entry
		if dir.current_is_dir():
			if recursive:
				_walk(full, pattern, recursive, out)
		else:
			if pattern == "" or entry.matchn(pattern):
				out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


# --- Scene tree -----------------------------------------------------------

func get_current_scene(_params: Dictionary) -> Dictionary:
	if host == null or host.get_tree() == null:
		return {"status": "error", "message": "No scene tree available"}
	var scene := host.get_tree().current_scene
	if scene == null:
		return {"status": "ok", "scene": null}
	return {
		"status": "ok",
		"scene": {
			"name": scene.name,
			"type": scene.get_class(),
			"path": scene.scene_file_path,
		},
	}


func get_node_info(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	if path == "":
		return {"status": "error", "message": "Missing 'path'"}
	var node := _resolve_node(path)
	if node == null:
		return {"status": "error", "message": "Node not found: %s" % path}
	return {"status": "ok", "node": _node_summary(node)}


func get_node_property(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	var prop: String = params.get("property", "")
	if path == "" or prop == "":
		return {"status": "error", "message": "Missing 'path' or 'property'"}
	var node := _resolve_node(path)
	if node == null:
		return {"status": "error", "message": "Node not found: %s" % path}
	return {"status": "ok", "value": _to_serializable(node.get(prop))}


func set_node_property(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	var prop: String = params.get("property", "")
	if path == "" or prop == "":
		return {"status": "error", "message": "Missing 'path' or 'property'"}
	if not params.has("value"):
		return {"status": "error", "message": "Missing 'value'"}
	var node := _resolve_node(path)
	if node == null:
		return {"status": "error", "message": "Node not found: %s" % path}
	node.set(prop, params["value"])
	return {"status": "ok", "value": _to_serializable(node.get(prop))}


func call_node_method(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	var method: String = params.get("method", "")
	# `args` may arrive as a real JSON Array, as a JSON-encoded String (some
	# clients/bridges stringify nested arrays), or as a single scalar value.
	# Normalize all three shapes so a strict-typed Array assignment never
	# silently fails (see issue #333).
	var raw_args = params.get("args", [])
	var args: Array = []
	if raw_args is Array:
		args = raw_args
	elif raw_args is String:
		var parsed = JSON.parse_string(raw_args)
		if parsed is Array:
			args = parsed
		elif parsed == null and raw_args == "":
			args = []
		else:
			# Either a JSON scalar (e.g. "\"foo\"") or a bare string that
			# isn't valid JSON. Treat the raw value as a single positional arg.
			args = [parsed if parsed != null else raw_args]
	else:
		# Numbers, bools, dicts, null, etc. — wrap as a single positional arg.
		args = [raw_args]
	if path == "" or method == "":
		return {"status": "error", "message": "Missing 'path' or 'method'"}
	var node := _resolve_node(path)
	if node == null:
		return {"status": "error", "message": "Node not found: %s" % path}
	if not node.has_method(method):
		return {"status": "error", "message": "Node has no method '%s'" % method}
	var result = node.callv(method, args)
	return {"status": "ok", "result": _to_serializable(result)}


# --- Scripts --------------------------------------------------------------

func read_script(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	if path == "":
		return {"status": "error", "message": "Missing 'path'"}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"status": "error", "message": "Cannot open file: %s" % path}
	var content := f.get_as_text()
	f.close()
	return {"status": "ok", "path": path, "content": content}


func write_script(params: Dictionary) -> Dictionary:
	# Guarded write. The addon's threat model is trusted-localhost, but two
	# cheap guards (borrowed from godot-mcp-enhanced's security model) prevent
	# the most common foot-guns:
	#   * res:// confinement + optional GODOT_MCP_ALLOWED_WRITE_PATHS allow-list
	#     (mirrors ALLOWED_PROJECT_PATHS — when unset, all res:// paths allowed).
	#   * overwrite confirmation: refuse to clobber an existing file unless the
	#     caller passes overwrite:true (the "confirmation token for destructive
	#     operations" pattern). Overwriting source is the main destructive risk
	#     this bridge exposes.
	var path: String = params.get("path", "")
	var content: String = params.get("content", "")
	if path == "" or not path.begins_with("res://"):
		return {"status": "error", "message": "Path must be under res://"}

	var allow_env := OS.get_environment("GODOT_MCP_ALLOWED_WRITE_PATHS")
	if allow_env != "":
		var allowed := false
		for prefix in allow_env.split(",", false):
			var p := prefix.strip_edges()
			if p != "" and path.begins_with(p):
				allowed = true
				break
		if not allowed:
			return {"status": "error", "message": "Path %s is outside GODOT_MCP_ALLOWED_WRITE_PATHS" % path}

	var exists := FileAccess.file_exists(path)
	if exists and not bool(params.get("overwrite", false)):
		return {
			"status": "error",
			"message": "Refusing to overwrite existing file without overwrite:true — %s" % path,
			"exists": true,
		}

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"status": "error", "message": "Cannot open file for writing: %s" % path}
	f.store_string(content)
	f.close()
	return {"status": "ok", "path": path, "bytes_written": content.length(), "overwritten": exists}


# --- Helpers --------------------------------------------------------------

func _resolve_node(path: String) -> Node:
	if host == null:
		return null
	var tree := host.get_tree()
	if tree == null:
		return null
	var root := tree.root
	if root == null:
		return null
	# `get_node_or_null` accepts both absolute paths ("/root/...") and
	# relative paths. For absolute paths we resolve from any node in the
	# tree; for unrooted paths we treat them as relative to the current scene.
	if path.begins_with("/"):
		return host.get_node_or_null(NodePath(path))
	var current := tree.current_scene
	if current == null:
		return null
	return current.get_node_or_null(NodePath(path))


func _node_summary(node: Node) -> Dictionary:
	var info := {
		"name": node.name,
		"type": node.get_class(),
		"path": String(node.get_path()),
		"child_count": node.get_child_count(),
		"children": [],
	}
	for child in node.get_children():
		info["children"].append({
			"name": child.name,
			"type": child.get_class(),
		})
	if node is Node2D:
		info["position"] = [node.global_position.x, node.global_position.y]
		info["visible"] = node.visible
		info["rotation"] = node.rotation
	if node is Control:
		info["position"] = [node.global_position.x, node.global_position.y]
		info["size"] = [node.size.x, node.size.y]
		info["visible"] = node.visible
	return info


func _to_serializable(value):
	# JSON.stringify can serialize most primitives; convert exotic types here.
	match typeof(value):
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [value.x, value.y, value.z]
		TYPE_RECT2, TYPE_RECT2I:
			return {
				"position": [value.position.x, value.position.y],
				"size": [value.size.x, value.size.y],
			}
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		TYPE_NODE_PATH:
			return String(value)
		TYPE_OBJECT:
			if value == null:
				return null
			return "<%s>" % value.get_class()
		TYPE_DICTIONARY:
			var out := {}
			for k in value.keys():
				out[str(k)] = _to_serializable(value[k])
			return out
		TYPE_ARRAY:
			var out_arr := []
			for v in value:
				out_arr.append(_to_serializable(v))
			return out_arr
		_:
			return value
