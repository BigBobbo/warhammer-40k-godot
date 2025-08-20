@tool
extends EditorPlugin

# GUT Plugin for Godot Editor
# Simplified implementation for basic test running

func _enter_tree():
	print("GUT: Plugin activated")

func _exit_tree():
	print("GUT: Plugin deactivated")

func get_plugin_name():
	return "Gut"