extends Node2D
# Note: BaseShape and CircularBase are available globally via class_name

var owner_player: int = 1
var is_valid_position: bool = true
var model_data: Dictionary = {}
var base_rotation: float = 0.0
var base_shape: BaseShape = null

func _ready() -> void:
	z_index = 20
	set_process(true)

func _draw() -> void:
	if not base_shape:
		# Fallback to circular if no shape defined
		print("WARNING: GhostVisual._draw() called with null base_shape! Using fallback circle.")
		print("  model_data: ", model_data)
		base_shape = CircularBase.new(20.0)

	var fill_color: Color
	var border_color: Color

	if not is_valid_position:
		fill_color = Color(0.8, 0.2, 0.2, 0.5)
		border_color = Color(1.0, 0.0, 0.0, 0.8)
	else:
		if owner_player == 1:
			fill_color = Color(0.2, 0.2, 0.8, 0.5)
			border_color = Color(0.3, 0.3, 1.0, 0.8)
		else:
			fill_color = Color(0.8, 0.2, 0.2, 0.5)
			border_color = Color(1.0, 0.3, 0.3, 0.8)

	# Use base shape's draw method
	base_shape.draw(self, Vector2.ZERO, base_rotation, fill_color, border_color, 2.0)

func set_validity(valid: bool) -> void:
	is_valid_position = valid
	queue_redraw()

func set_model_data(data: Dictionary) -> void:
	model_data = data
	base_shape = Measurement.create_base_shape(data)
	queue_redraw()

func set_base_rotation(rot: float) -> void:
	base_rotation = rot
	# Don't set Node2D rotation - the shape handles rotation in draw()
	queue_redraw()

func get_base_rotation() -> float:
	"""Get the current rotation of the ghost base"""
	return base_rotation

func rotate_by(angle: float) -> void:
	"""Rotate the ghost by the given angle (in radians)"""
	base_rotation += angle
	# Don't set Node2D rotation - the shape handles rotation in draw()
	queue_redraw()
