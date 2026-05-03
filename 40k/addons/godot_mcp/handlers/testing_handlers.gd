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

	# Wait until the next post-draw so we capture the most recent frame.
	await RenderingServer.frame_post_draw

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
	# Parse a one-line GDScript expression and evaluate it against an optional
	# target node. Useful for poking at game state from the bridge without
	# adding a dedicated tool.
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

	var input_names: Array = params.get("input_names", [])
	var input_values: Array = params.get("input_values", [])
	var expression := Expression.new()
	var parse_err := expression.parse(code, PackedStringArray(input_names))
	if parse_err != OK:
		return {"status": "error", "message": expression.get_error_text()}
	var result = expression.execute(input_values, target, true)
	if expression.has_execute_failed():
		return {"status": "error", "message": "Execution failed: %s" % expression.get_error_text()}
	return {"status": "ok", "result": _serialize(result)}


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
