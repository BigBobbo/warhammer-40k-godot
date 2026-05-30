extends RefCounted

# Generic in-game testing tools.
#
# These methods all run inside the running game's main scene tree, so
# `host.get_tree()` and `host.get_viewport()` are valid. The MCP server
# autoload calls these via `await router.dispatch(...)` so they can yield
# on `process_frame`, timers, and `RenderingServer.frame_post_draw`.

var host: Node = null


# --- Screenshot -----------------------------------------------------------

func capture_screenshot(params: Dictionary) -> Dictionary:
	var label: String = params.get("label", "capture_%d" % Time.get_ticks_msec())
	var include_base64: bool = params.get("include_base64", true)
	var include_path: bool = params.get("include_path", true)
	# Default to 1280px on the long side. Claude's vision pipeline downscales
	# anything larger, so transmitting full 1920+ wastes tokens. Pass 0 to
	# disable scaling.
	var max_dim: int = int(params.get("max_dim", 1280))
	if host == null:
		return {"status": "error", "message": "MCP host not ready"}

	# Wait for the next post-draw with a timeout — frame_post_draw may never
	# fire if the window is unfocused and the renderer is throttled.
	var got_frame := false
	var _on_frame := func(): got_frame = true
	RenderingServer.frame_post_draw.connect(_on_frame, CONNECT_ONE_SHOT)
	for _i in range(30):  # ~0.5s at 60fps
		if got_frame:
			break
		if host.get_tree():
			await host.get_tree().process_frame
		else:
			break
	if not got_frame and RenderingServer.frame_post_draw.is_connected(_on_frame):
		RenderingServer.frame_post_draw.disconnect(_on_frame)

	var viewport := host.get_viewport()
	if viewport == null:
		return {"status": "error", "message": "No viewport available"}
	var texture := viewport.get_texture()
	if texture == null:
		return {"status": "error", "message": "No texture on viewport"}
	var image := texture.get_image()
	if image == null:
		return {"status": "error", "message": "Failed to read viewport image"}

	var orig_size := [image.get_width(), image.get_height()]

	# Save the full-resolution PNG to disk before any resizing, so callers
	# can still inspect the original if needed.
	var result := {
		"status": "ok",
		"size": orig_size,
	}
	if include_path:
		DirAccess.make_dir_recursive_absolute("user://test_screenshots")
		var path := "user://test_screenshots/%s.png" % label
		var save_err := image.save_png(path)
		if save_err == OK:
			result["path"] = path
			result["absolute_path"] = ProjectSettings.globalize_path(path)

	if include_base64:
		# Downscale only the inline copy. Image.resize is in-place so we
		# duplicate first to keep the on-disk file at full res.
		var inline_image := image
		if max_dim > 0:
			var w := image.get_width()
			var h := image.get_height()
			var long := max(w, h)
			if long > max_dim:
				inline_image = image.duplicate()
				var scale := float(max_dim) / float(long)
				var new_w := int(round(w * scale))
				var new_h := int(round(h * scale))
				inline_image.resize(new_w, new_h, Image.INTERPOLATE_BILINEAR)
				result["inline_size"] = [new_w, new_h]
		var buffer := inline_image.save_png_to_buffer()
		result["image_base64"] = Marshalls.raw_to_base64(buffer)
		result["image_mime_type"] = "image/png"

	return result


# --- Input simulation ----------------------------------------------------

func simulate_click(params: Dictionary) -> Dictionary:
	if not params.has("x") or not params.has("y"):
		return {"status": "error", "message": "Missing 'x' or 'y'"}
	var pos := Vector2(float(params["x"]), float(params["y"]))
	var button: int = int(params.get("button", MOUSE_BUTTON_LEFT))
	var double_click: bool = params.get("double_click", false)

	var press := InputEventMouseButton.new()
	press.button_index = button
	press.position = pos
	press.global_position = pos
	press.pressed = true
	press.double_click = double_click
	press.button_mask = _button_mask_for(button)
	Input.parse_input_event(press)

	# Yield a frame so the press is processed before release.
	if host and host.get_tree():
		await host.get_tree().process_frame

	var release := InputEventMouseButton.new()
	release.button_index = button
	release.position = pos
	release.global_position = pos
	release.pressed = false
	release.button_mask = 0
	Input.parse_input_event(release)

	if host and host.get_tree():
		await host.get_tree().process_frame

	return {
		"status": "ok",
		"position": [pos.x, pos.y],
		"button": button,
	}


func simulate_mouse_move(params: Dictionary) -> Dictionary:
	if not params.has("x") or not params.has("y"):
		return {"status": "error", "message": "Missing 'x' or 'y'"}
	var pos := Vector2(float(params["x"]), float(params["y"]))
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	motion.relative = Vector2.ZERO
	Input.parse_input_event(motion)
	if host and host.get_tree():
		await host.get_tree().process_frame
	return {"status": "ok", "position": [pos.x, pos.y]}


func simulate_drag(params: Dictionary) -> Dictionary:
	# Press at start, move through optional waypoints to end, release.
	if not params.has("from_x") or not params.has("from_y") \
			or not params.has("to_x") or not params.has("to_y"):
		return {"status": "error", "message": "Missing from_x/from_y/to_x/to_y"}
	var start := Vector2(float(params["from_x"]), float(params["from_y"]))
	var end := Vector2(float(params["to_x"]), float(params["to_y"]))
	var steps: int = int(params.get("steps", 10))
	var button: int = int(params.get("button", MOUSE_BUTTON_LEFT))

	var press := InputEventMouseButton.new()
	press.button_index = button
	press.position = start
	press.global_position = start
	press.pressed = true
	press.button_mask = _button_mask_for(button)
	Input.parse_input_event(press)
	if host and host.get_tree():
		await host.get_tree().process_frame

	var prev := start
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var here := start.lerp(end, t)
		var motion := InputEventMouseMotion.new()
		motion.position = here
		motion.global_position = here
		motion.relative = here - prev
		motion.button_mask = _button_mask_for(button)
		Input.parse_input_event(motion)
		prev = here
		if host and host.get_tree():
			await host.get_tree().process_frame

	var release := InputEventMouseButton.new()
	release.button_index = button
	release.position = end
	release.global_position = end
	release.pressed = false
	release.button_mask = 0
	Input.parse_input_event(release)
	if host and host.get_tree():
		await host.get_tree().process_frame

	return {
		"status": "ok",
		"from": [start.x, start.y],
		"to": [end.x, end.y],
		"steps": steps,
	}


func simulate_key_press(params: Dictionary) -> Dictionary:
	if not params.has("keycode"):
		return {"status": "error", "message": "Missing 'keycode'"}
	var keycode: int = int(params["keycode"])
	var duration: float = float(params.get("duration", 0.05))

	var press := InputEventKey.new()
	press.keycode = keycode
	press.physical_keycode = keycode
	press.pressed = true
	Input.parse_input_event(press)

	if host and host.get_tree():
		await host.get_tree().create_timer(duration).timeout

	var release := InputEventKey.new()
	release.keycode = keycode
	release.physical_keycode = keycode
	release.pressed = false
	Input.parse_input_event(release)

	return {"status": "ok", "keycode": keycode, "duration": duration}


func simulate_action(params: Dictionary) -> Dictionary:
	var action: String = params.get("action", "")
	if action == "":
		return {"status": "error", "message": "Missing 'action'"}
	if not InputMap.has_action(action):
		return {"status": "error", "message": "Action not in InputMap: %s" % action}
	var duration: float = float(params.get("duration", 0.1))
	Input.action_press(action)
	if host and host.get_tree():
		await host.get_tree().create_timer(duration).timeout
	Input.action_release(action)
	return {"status": "ok", "action": action, "duration": duration}


# --- Scene state inspection ----------------------------------------------

func get_scene_state(params: Dictionary) -> Dictionary:
	if host == null or host.get_tree() == null:
		return {"status": "error", "message": "No scene tree"}
	var max_depth: int = int(params.get("max_depth", 10))
	var include_props: bool = params.get("include_script_properties", true)
	var include_invisible: bool = params.get("include_invisible", true)
	var root_path: String = params.get("root", "")

	var root_node: Node
	if root_path == "":
		root_node = host.get_tree().current_scene
		if root_node == null:
			root_node = host.get_tree().root
	else:
		# get_node_or_null accepts both absolute ("/root/...") and relative paths.
		root_node = host.get_node_or_null(NodePath(root_path))
		if root_node == null:
			return {"status": "error", "message": "Root not found: %s" % root_path}

	return {
		"status": "ok",
		"scene_tree": _collect_state(root_node, 0, max_depth, include_props, include_invisible),
	}


func _collect_state(node: Node, depth: int, max_depth: int,
		include_props: bool, include_invisible: bool) -> Dictionary:
	var info := {
		"name": node.name,
		"type": node.get_class(),
		"path": String(node.get_path()),
	}
	if node is Node2D:
		info["position"] = [node.global_position.x, node.global_position.y]
		info["visible"] = node.visible
		info["rotation"] = node.rotation
		info["scale"] = [node.scale.x, node.scale.y]
	elif node is Control:
		info["position"] = [node.global_position.x, node.global_position.y]
		info["size"] = [node.size.x, node.size.y]
		info["visible"] = node.visible
	elif node is Node3D:
		info["position"] = [node.global_position.x, node.global_position.y, node.global_position.z]
		info["visible"] = node.visible

	if node is Sprite2D or node is AnimatedSprite2D:
		if node.has_method("get_frame"):
			info["frame"] = node.frame

	if include_props:
		var props := []
		for prop in node.get_property_list():
			var usage: int = int(prop.get("usage", 0))
			if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var pname: String = prop.get("name", "")
			if pname == "" or pname.begins_with("_"):
				continue
			var value = node.get(pname)
			props.append({"name": pname, "value": _serialize(value)})
		if props.size() > 0:
			info["script_properties"] = props

	if depth < max_depth:
		var children := []
		for child in node.get_children():
			if not include_invisible and child is CanvasItem and not child.visible:
				continue
			children.append(_collect_state(child, depth + 1, max_depth,
				include_props, include_invisible))
		info["children"] = children
	else:
		info["children_truncated"] = node.get_child_count()

	return info


func _serialize(value):
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
				out[str(k)] = _serialize(value[k])
			return out
		TYPE_ARRAY:
			var out_arr := []
			for v in value:
				out_arr.append(_serialize(v))
			return out_arr
		_:
			return value


# --- Script execution ---------------------------------------------------

func execute_script(params: Dictionary) -> Dictionary:
	# Evaluate GDScript against an optional target node.
	#
	# Two modes:
	#   * Single-line expression (default) — uses Godot's Expression, fast and
	#     sandboxed; the target node is visible as `self`. Back-compat path.
	#   * Multi-line / statement mode — when the code spans multiple lines, or
	#     the caller passes `multiline: true`, the snippet is compiled into a
	#     throwaway GDScript so full statements work: `var`, `if`, `for`,
	#     `return`, calling methods, and reaching autoloads (GameState,
	#     PhaseManager, …) by their global names. The resolved node is the
	#     `node` parameter; `return <value>` to send a result back.
	var code: String = params.get("code", "")
	if code == "":
		return {"status": "error", "message": "Missing 'code'"}
	var node_path: String = params.get("node_path", "/root")

	var target: Object = null
	if host and host.get_tree():
		# Absolute and relative paths both resolve via get_node_or_null.
		target = host.get_node_or_null(NodePath(node_path))
	if target == null:
		return {"status": "error", "message": "Node not found: %s" % node_path}

	var multiline: bool = params.get("multiline", code.find("\n") != -1)
	if multiline:
		return _execute_script_compiled(code, target)

	# --- Expression path (single-line, back-compat) ---
	var input_names: Array = params.get("input_names", [])
	var input_values: Array = params.get("input_values", [])
	var expression := Expression.new()
	var parse_err := expression.parse(code, PackedStringArray(input_names))
	if parse_err != OK:
		return {"status": "error", "error_type": "parse", "message": expression.get_error_text()}
	var result = expression.execute(input_values, target, true)
	if expression.has_execute_failed():
		return {"status": "error", "error_type": "runtime", "message": "Execution failed: %s" % expression.get_error_text()}
	return {"status": "ok", "result": _serialize(result)}


func _execute_script_compiled(code: String, target: Object) -> Dictionary:
	# Wrap the user code in a function body so multi-line statements compile.
	# The wrapper extends RefCounted (no tree mutation), so the snippet gets the
	# context it needs via parameters rather than `self`:
	#   * `node` — the resolved target node
	#   * `tree` — the SceneTree (so `tree.get_node_count()`, `tree.root` work)
	# Autoloads are reachable by their global names. Node methods must be called
	# on `node` (e.g. `node.get_node(...)`), not bare. `return <value>` to send a
	# result back; with no return the result is null.
	var indented := ""
	for line in code.split("\n"):
		indented += "\t" + line + "\n"
	if indented.strip_edges() == "":
		indented = "\treturn null\n"
	var src := "extends RefCounted\nfunc _run(node, tree):\n" + indented

	var script := GDScript.new()
	script.source_code = src
	var reload_err := script.reload()
	if reload_err != OK:
		return {
			"status": "error",
			"error_type": "parse",
			"message": "GDScript compile failed (error %d). Note: call node methods on `node`/`tree`, not bare. Check syntax/indentation." % reload_err,
			"source": src,
		}
	var instance = script.new()
	if instance == null or not instance.has_method("_run"):
		return {"status": "error", "error_type": "parse", "message": "Failed to instantiate compiled snippet"}
	# Runtime errors inside the snippet cannot be caught in GDScript; they push
	# an error to the debug log (read it back with read_debug_log) and return
	# null. The return value is surfaced here either way.
	var scene_tree = host.get_tree() if host else null
	var result = instance.call("_run", target, scene_tree)
	return {"status": "ok", "result": _serialize(result), "multiline": true}


# --- Debug log inspection -----------------------------------------------

func read_debug_log(params: Dictionary) -> Dictionary:
	# Return the latest debug log bucketed into errors / warnings / info / debug
	# so callers can assert "no errors fired" without grepping raw text.
	#   path         absolute or user:// path (default: newest user://logs/debug_*.log)
	#   tail         only keep the last N non-empty lines (default 200; 0 = all)
	#   since_marker keep only lines after this marker's LAST occurrence
	#   levels       filter returned `lines` to these levels (e.g. ["ERROR"])
	#   include_lines  include the (possibly filtered) raw lines (default true)
	#
	# Flushes DebugLogger's in-memory buffer first so the freshest output is on
	# disk before reading.
	if host and host.get_tree():
		var dl := host.get_tree().root.get_node_or_null("DebugLogger")
		if dl and dl.has_method("_flush_buffer"):
			dl._flush_buffer()

	var path: String = params.get("path", "")
	if path == "":
		path = latest_log_path()
	if path == "":
		return {"status": "error", "message": "No debug log found under user://logs/"}

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"status": "error", "message": "Cannot open log: %s" % path}
	var text := f.get_as_text()
	f.close()

	var lines: Array = []
	for l in text.split("\n"):
		lines.append(l)

	var since_marker: String = params.get("since_marker", "")
	if since_marker != "":
		var last_idx := -1
		for i in range(lines.size()):
			if String(lines[i]).find(since_marker) != -1:
				last_idx = i
		if last_idx >= 0:
			lines = lines.slice(last_idx + 1)

	var tail: int = int(params.get("tail", 200))
	if tail > 0 and lines.size() > tail:
		lines = lines.slice(lines.size() - tail)

	var summary := categorize_log_lines(lines)
	var result := {
		"status": "ok",
		"log_path": ProjectSettings.globalize_path(path),
		"lines_scanned": lines.size(),
		"counts": summary["counts"],
		"errors": summary["errors"],
		"warnings": summary["warnings"],
		"has_errors": int(summary["counts"]["error"]) > 0,
	}

	var include_lines: bool = params.get("include_lines", true)
	if include_lines:
		var level_filter: Array = params.get("levels", [])
		if level_filter.is_empty():
			var raw_lines: Array = []
			for entry in summary["classified"]:
				raw_lines.append(entry["line"])
			result["lines"] = raw_lines
		else:
			var upper: Array = []
			for lv in level_filter:
				upper.append(String(lv).to_upper())
			var filtered: Array = []
			for entry in summary["classified"]:
				if upper.has(entry["level"]):
					filtered.append(entry["line"])
			result["lines"] = filtered
	return result


static func latest_log_path() -> String:
	# Newest non-archived debug log. Names are debug_YYYYMMDD_HHMMSS.log so a
	# lexicographic max equals the most recent session.
	var dir := DirAccess.open("user://logs")
	if dir == null:
		return ""
	var best := ""
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.begins_with("debug_") \
				and entry.ends_with(".log") and not entry.ends_with("_archived.log"):
			if entry > best:
				best = entry
		entry = dir.get_next()
	dir.list_dir_end()
	if best == "":
		return ""
	return "user://logs/" + best


static func categorize_log_lines(lines: Array) -> Dictionary:
	# Bucket log lines by level. Understands the DebugLogger format
	# "[timestamp] [LEVEL ] message" and falls back to raw engine markers
	# (ERROR:, SCRIPT ERROR, WARNING:).
	var counts := {"error": 0, "warning": 0, "info": 0, "debug": 0, "other": 0}
	var errors: Array = []
	var warnings: Array = []
	var classified: Array = []
	for raw in lines:
		var line := String(raw)
		if line.strip_edges() == "":
			continue
		var level := _classify_log_line(line)
		match level:
			"ERROR":
				counts["error"] += 1
				errors.append(line)
			"WARNING":
				counts["warning"] += 1
				warnings.append(line)
			"INFO":
				counts["info"] += 1
			"DEBUG":
				counts["debug"] += 1
			_:
				counts["other"] += 1
		classified.append({"level": level, "line": line})
	return {"counts": counts, "errors": errors, "warnings": warnings, "classified": classified}


static func _classify_log_line(line: String) -> String:
	# Prefer the DebugLogger level token (the SECOND bracketed group).
	var first := line.find("] [")
	if first != -1:
		var start := first + 3
		var end := line.find("]", start)
		if end != -1:
			var token := line.substr(start, end - start).strip_edges().to_upper()
			if token.begins_with("ERROR"):
				return "ERROR"
			if token.begins_with("WARN"):
				return "WARNING"
			if token.begins_with("INFO"):
				return "INFO"
			if token.begins_with("DEBUG"):
				return "DEBUG"
	# Fall back to raw engine output markers.
	var upper := line.strip_edges().to_upper()
	if upper.begins_with("ERROR:") or upper.find("SCRIPT ERROR") != -1:
		return "ERROR"
	if upper.begins_with("WARNING:") or upper.begins_with("WARN:"):
		return "WARNING"
	return "OTHER"


# --- Scene snapshots / diffing ------------------------------------------

func scene_snapshot(params: Dictionary) -> Dictionary:
	# Capture a compact, diff-friendly index of the scene tree (path -> type,
	# position, visibility, size, script properties) and persist it to
	# user://mcp_snapshots/<label>.json so a later diff_snapshot can reference
	# it by label. Use before/after a change to prove only the intended nodes
	# moved.
	var label: String = params.get("label", "snapshot_%d" % Time.get_ticks_msec())
	var max_depth: int = int(params.get("max_depth", 12))
	var index = _capture_index(params.get("root", ""), max_depth)
	if index == null:
		return {"status": "error", "message": "No scene tree (or root not found)"}

	var snapshot := {"label": label, "captured_ms": Time.get_ticks_msec(), "index": index}
	DirAccess.make_dir_recursive_absolute("user://mcp_snapshots")
	var path := "user://mcp_snapshots/%s.json" % label
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(snapshot))
		f.close()
	return {
		"status": "ok",
		"label": label,
		"node_count": index.size(),
		"path": ProjectSettings.globalize_path(path),
	}


func diff_snapshot(params: Dictionary) -> Dictionary:
	# Compare two snapshots and report added / removed / changed nodes.
	#   before  required snapshot label (loaded from disk)
	#   after   snapshot label, OR omit / "__live__" to diff against the live tree
	var before = _load_snapshot_index(params.get("before", ""))
	if before == null:
		return {"status": "error", "message": "Could not load 'before' snapshot (pass a label captured via scene_snapshot)"}
	var after_arg: String = params.get("after", "")
	var after
	if after_arg == "" or after_arg == "__live__":
		after = _capture_index(params.get("root", ""), int(params.get("max_depth", 12)))
	else:
		after = _load_snapshot_index(after_arg)
	if after == null:
		return {"status": "error", "message": "Could not load 'after' snapshot / capture live tree"}

	var added: Array = []
	var removed: Array = []
	var changed: Array = []
	for p in after.keys():
		if not before.has(p):
			added.append(p)
	for p in before.keys():
		if not after.has(p):
			removed.append(p)
		else:
			var d := _diff_entry(before[p], after[p])
			if not d.is_empty():
				changed.append({"path": p, "changes": d})
	return {
		"status": "ok",
		"added": added,
		"removed": removed,
		"changed": changed,
		"summary": {"added": added.size(), "removed": removed.size(), "changed": changed.size()},
	}


func _capture_index(root_path: String, max_depth: int):
	if host == null or host.get_tree() == null:
		return null
	var root_node: Node
	if root_path == "":
		root_node = host.get_tree().current_scene
		if root_node == null:
			root_node = host.get_tree().root
	else:
		root_node = host.get_node_or_null(NodePath(root_path))
		if root_node == null:
			return null
	var index := {}
	_index_node(root_node, 0, max_depth, index)
	return index


func _index_node(node: Node, depth: int, max_depth: int, index: Dictionary) -> void:
	var entry := {"type": node.get_class()}
	if node is Node2D:
		entry["position"] = [snappedf(node.global_position.x, 0.01), snappedf(node.global_position.y, 0.01)]
		entry["visible"] = node.visible
		entry["rotation"] = snappedf(node.rotation, 0.0001)
	elif node is Control:
		entry["position"] = [snappedf(node.global_position.x, 0.01), snappedf(node.global_position.y, 0.01)]
		entry["size"] = [snappedf(node.size.x, 0.01), snappedf(node.size.y, 0.01)]
		entry["visible"] = node.visible
	elif node is CanvasItem:
		entry["visible"] = node.visible
	var props := {}
	for prop in node.get_property_list():
		var usage: int = int(prop.get("usage", 0))
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var pname: String = prop.get("name", "")
		if pname == "" or pname.begins_with("_"):
			continue
		props[pname] = _serialize(node.get(pname))
	if not props.is_empty():
		entry["props"] = props
	index[String(node.get_path())] = entry
	if depth < max_depth:
		for child in node.get_children():
			_index_node(child, depth + 1, max_depth, index)


func _load_snapshot_index(label: String):
	if label == "":
		return null
	var path := "user://mcp_snapshots/%s.json" % label
	if not FileAccess.file_exists(path):
		# Allow passing an absolute/user path too.
		path = label
		if not FileAccess.file_exists(path):
			return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return parsed.get("index", null)


func _diff_entry(before: Dictionary, after: Dictionary) -> Dictionary:
	# Field-level diff of two snapshot entries (type/position/visible/size/
	# rotation and each script property). Returns {field: [old, new]}.
	var changes := {}
	for key in ["type", "position", "visible", "size", "rotation"]:
		if before.get(key, null) != after.get(key, null):
			if before.has(key) or after.has(key):
				changes[key] = [before.get(key, null), after.get(key, null)]
	var bp: Dictionary = before.get("props", {})
	var ap: Dictionary = after.get("props", {})
	var prop_changes := {}
	for k in bp.keys():
		if bp[k] != ap.get(k, null):
			prop_changes[k] = [bp[k], ap.get(k, null)]
	for k in ap.keys():
		if not bp.has(k):
			prop_changes[k] = [null, ap[k]]
	if not prop_changes.is_empty():
		changes["props"] = prop_changes
	return changes


# --- Adversarial self-check ---------------------------------------------

func chain_verify(params: Dictionary) -> Dictionary:
	# Anti-overconfidence gate (mirrors the project's "pin tests aren't
	# validation" rule). Given a `claim` describing what you believe you
	# delivered, return challenge questions plus automated evidence (live log
	# error counts) the agent must reconcile before closing the task.
	var claim: String = params.get("claim", "")
	if claim == "":
		return {"status": "error", "message": "Missing 'claim' describing what you think you delivered"}

	var questions := [
		"Did you DRIVE the feature live (dispatch_action / simulate_click / panel toggle), or only assert that code text is present?",
		"Did you capture a screenshot showing the feature's EFFECT (not the default game screen)?",
		"Did any ERROR or SCRIPT ERROR appear in the debug log while exercising '%s'?" % claim,
		"If '%s' has a UI affordance, can a player actually reach it, or only the engine?" % claim,
		"What is the strongest reason a reviewer would say '%s' is NOT done — and have you ruled it out with evidence?" % claim,
	]

	var evidence := {}
	var log_res := read_debug_log({"tail": 300})
	if log_res.get("status", "") == "ok":
		evidence["log_error_count"] = log_res["counts"]["error"]
		evidence["log_warning_count"] = log_res["counts"]["warning"]
		var errs: Array = log_res.get("errors", [])
		evidence["recent_errors"] = errs.slice(maxi(0, errs.size() - 5))

	return {
		"status": "ok",
		"claim": claim,
		"questions": questions,
		"evidence": evidence,
		"verdict_hint": "Answer every question with concrete evidence before declaring '%s' verified." % claim,
	}


# --- Frame / time waits --------------------------------------------------

func wait_frames(params: Dictionary) -> Dictionary:
	var frames: int = int(params.get("frames", 1))
	if host == null or host.get_tree() == null:
		return {"status": "error", "message": "No scene tree"}
	for i in range(frames):
		await host.get_tree().process_frame
	return {"status": "ok", "frames_waited": frames}


func wait_seconds(params: Dictionary) -> Dictionary:
	var seconds: float = float(params.get("seconds", 1.0))
	if host == null or host.get_tree() == null:
		return {"status": "error", "message": "No scene tree"}
	await host.get_tree().create_timer(seconds).timeout
	return {"status": "ok", "seconds_waited": seconds}


func get_log_path(_params: Dictionary) -> Dictionary:
	# Convenience: returns the absolute logs dir so callers can tail the
	# debug log alongside command results.
	return {
		"status": "ok",
		"logs_dir": ProjectSettings.globalize_path("user://logs/"),
		"screenshots_dir": ProjectSettings.globalize_path("user://test_screenshots/"),
	}


# --- Helpers --------------------------------------------------------------

func _button_mask_for(button_index: int) -> int:
	match button_index:
		MOUSE_BUTTON_LEFT:
			return MOUSE_BUTTON_MASK_LEFT
		MOUSE_BUTTON_RIGHT:
			return MOUSE_BUTTON_MASK_RIGHT
		MOUSE_BUTTON_MIDDLE:
			return MOUSE_BUTTON_MASK_MIDDLE
		_:
			return 0
