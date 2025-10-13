extends Node2D

var owner_player: int = 1
var is_preview: bool = false
var model_number: int = 1
var debug_mode: bool = false
var base_shape: BaseShape = null
var model_data: Dictionary = {}

func _ready() -> void:
	z_index = 10

func _draw() -> void:
	if not base_shape:
		# Fallback to circular if no shape defined
		base_shape = CircularBase.new(20.0)

	var fill_color: Color
	var border_color: Color
	var border_width: float = 3.0

	# Color logic (existing)
	if debug_mode:
		# Use distinct debug colors (bright yellow/orange)
		fill_color = Color(1.0, 0.8, 0.0, 0.9)  # Yellow
		border_color = Color(1.0, 0.5, 0.0, 1.0)  # Orange
		border_width = 4.0  # Thicker border in debug mode

		# Draw additional debug indicator ring
		draw_arc(Vector2.ZERO, base_shape.get_bounds().size.x / 2.0 + 4, 0, TAU, 32, Color(1.0, 1.0, 0.0, 0.5), 2.0)
	elif owner_player == 1:
		fill_color = Color(0.2, 0.2, 0.8, 0.8 if is_preview else 1.0)
		border_color = Color(0.1, 0.1, 0.6, 1.0)
	else:
		fill_color = Color(0.8, 0.2, 0.2, 0.8 if is_preview else 1.0)
		border_color = Color(0.6, 0.1, 0.1, 1.0)

	# Get rotation from model data (defaults to 0.0 for circular bases)
	var rotation = model_data.get("rotation", 0.0)

	# Use base shape's draw method with rotation
	base_shape.draw(self, Vector2.ZERO, rotation, fill_color, border_color, border_width)

	# Draw model number
	var font = ThemeDB.fallback_font
	var text = str(model_number)
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
	var text_pos = Vector2(-text_size.x / 2, text_size.y / 4)

	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color.WHITE)

func set_preview(preview: bool) -> void:
	is_preview = preview
	queue_redraw()

func set_debug_mode(active: bool) -> void:
	debug_mode = active
	queue_redraw()

func set_model_data(data: Dictionary) -> void:
	model_data = data
	base_shape = Measurement.create_base_shape(data)
	queue_redraw()

	# Set model number if available
	var model_id = data.get("id", "")
	if model_id.begins_with("m"):
		var num_str = model_id.substr(1)
		if num_str.is_valid_int():
			model_number = num_str.to_int()