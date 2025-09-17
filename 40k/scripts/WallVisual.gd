extends Node2D

class_name WallVisual

var wall_lines: Array = []
const WALL_COLOR = Color(0.8, 0.2, 0.2, 1.0)  # Red for visibility
const WALL_WIDTH = 8.0  # Thicker walls for visibility
const WINDOW_COLOR = Color(0.2, 0.2, 0.8, 0.8)  # Blue for windows
const DOOR_COLOR = Color(0.2, 0.8, 0.2, 0.9)  # Green for doors

func _ready() -> void:
	z_index = 5  # High z-index to ensure visibility
	z_as_relative = false
	visible = true
	name = "WallVisual"
	print("[WallVisual] Ready with z_index: ", z_index)

func add_wall(wall_data: Dictionary) -> void:
	var line = Line2D.new()
	var start_pos = wall_data.get("start", Vector2.ZERO)
	var end_pos = wall_data.get("end", Vector2.ZERO)

	# IMPORTANT: Line2D points must be in local space relative to this WallVisual node
	# Since WallVisual is at (0,0), we use the absolute coordinates directly
	line.add_point(start_pos)
	line.add_point(end_pos)
	line.width = 12.0  # Make even thicker for visibility

	print("[WallVisual] Adding wall from ", start_pos, " to ", end_pos, " type: ", wall_data.get("type", "solid"))

	# Set color based on wall type with FULL OPACITY
	match wall_data.get("type", "solid"):
		"solid":
			line.default_color = Color(1.0, 0.0, 0.0, 1.0)  # Bright red
			line.width = 12.0
		"window":
			line.default_color = Color(0.0, 0.0, 1.0, 1.0)  # Bright blue
			line.width = 10.0
		"door":
			line.default_color = Color(0.0, 1.0, 0.0, 1.0)  # Bright green
			line.width = 8.0

	# Set rendering properties
	line.z_index = 10  # Very high z-index to ensure visibility
	line.z_as_relative = false  # Use absolute z-index
	line.show_behind_parent = false
	line.visible = true

	add_child(line)
	wall_lines.append(line)

	# Debug: print the line's actual properties
	print("  Line added with ", line.get_point_count(), " points, width: ", line.width, ", color: ", line.default_color, ", z_index: ", line.z_index)

func clear_walls() -> void:
	for line in wall_lines:
		if is_instance_valid(line):
			line.queue_free()
	wall_lines.clear()

func highlight_wall(index: int, highlight: bool, color: Color = Color.YELLOW) -> void:
	if index >= 0 and index < wall_lines.size():
		var line = wall_lines[index]
		if is_instance_valid(line):
			if highlight:
				line.default_color = color
				line.width = WALL_WIDTH * 1.5
			else:
				# Restore original color based on type
				match line.get_meta("wall_type", "solid"):
					"solid":
						line.default_color = WALL_COLOR
						line.width = WALL_WIDTH
					"window":
						line.default_color = WINDOW_COLOR
						line.width = WALL_WIDTH * 0.75
					"door":
						line.default_color = DOOR_COLOR
						line.width = WALL_WIDTH * 0.5