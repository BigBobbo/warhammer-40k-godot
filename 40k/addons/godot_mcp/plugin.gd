@tool
extends EditorPlugin

# Godot MCP editor plugin entry point.
#
# Two pieces:
#   1. The runtime autoload `MCPServer` (declared directly in project.godot)
#      starts a TCP server on port 9080 inside the running game. It exposes
#      screenshot, input simulation, scene state, and WH40K commands.
#   2. This editor plugin starts a small editor-side bridge on port 9081 that
#      handles commands needing `EditorInterface` — play_scene, stop_scene,
#      list_scenes, etc.
#
# Keeping the runtime autoload in `project.godot` (rather than registering it
# here via `add_autoload_singleton`) lets the runtime server work even when
# this editor plugin is disabled, and avoids double-registration during a
# plugin enable/disable cycle.

var _editor_bridge: Node = null


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		var EditorBridgeScript := load("res://addons/godot_mcp/editor_bridge.gd")
		if EditorBridgeScript:
			_editor_bridge = EditorBridgeScript.new()
			_editor_bridge.editor_plugin = self
			add_child(_editor_bridge)
			_editor_bridge.start()
			print("[GodotMCP] Editor bridge started")


func _exit_tree() -> void:
	if _editor_bridge:
		_editor_bridge.stop()
		_editor_bridge.queue_free()
		_editor_bridge = null
