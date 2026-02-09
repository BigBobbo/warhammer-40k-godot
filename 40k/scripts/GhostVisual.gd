extends Node2D
# BaseShape and CircularBase are available via class_name - no preloads needed

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
			# P1: Blue-gray fill (reduced alpha), gold border
			fill_color = Color(0.2, 0.25, 0.45, 0.4)
			border_color = Color(0.83, 0.59, 0.38, 0.6)
		else:
			# P2: Crimson fill (reduced alpha), bone border
			fill_color = Color(0.5, 0.12, 0.1, 0.4)
			border_color = Color(0.85, 0.8, 0.65, 0.6)

	# Check if enhanced mode for gradient ghost fill
	var style = SettingsService.unit_visual_style if SettingsService else "classic"
	if style == "enhanced":
		var ghost_alpha = fill_color.a
		var ghost_base = Color(fill_color.r, fill_color.g, fill_color.b, ghost_alpha)
		if base_shape.get_type() == "circular":
			TokenDrawUtils.draw_gradient_circle(self, Vector2.ZERO, (base_shape as CircularBase).radius, ghost_base)
			# Light border rim
			var rim_color = Color(border_color.r, border_color.g, border_color.b, ghost_alpha * 0.7)
			draw_arc(Vector2.ZERO, (base_shape as CircularBase).radius, 0, TAU, 48, rim_color, 2.0)
		else:
			var poly_points = _get_ghost_polygon()
			TokenDrawUtils.draw_gradient_polygon(self, poly_points, ghost_base)
			# Light border
			var rim_color = Color(border_color.r, border_color.g, border_color.b, ghost_alpha * 0.7)
			var closed = PackedVector2Array()
			for p in poly_points:
				closed.append(p)
			if poly_points.size() > 0:
				closed.append(poly_points[0])
			draw_polyline(closed, rim_color, 2.0)
	else:
		# Original rendering - no silhouette overlays on ghosts for clarity
		base_shape.draw(self, Vector2.ZERO, base_rotation, fill_color, border_color, 2.0)

func set_validity(valid: bool) -> void:
	is_valid_position = valid
	queue_redraw()

func set_model_data(data: Dictionary) -> void:
	print("[GhostVisual] set_model_data called")
	print("[GhostVisual] data keys: ", data.keys())
	model_data = data
	base_shape = Measurement.create_base_shape(data)
	print("[GhostVisual] base_shape created: ", base_shape != null)
	if base_shape:
		print("[GhostVisual] base_shape type: ", base_shape.get_type())
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

func _get_ghost_polygon() -> PackedVector2Array:
	var points = PackedVector2Array()
	var shape_type = base_shape.get_type()

	if shape_type == "rectangular":
		var rect_base = base_shape as RectangularBase
		var hl = rect_base.length / 2.0
		var hw = rect_base.width / 2.0
		var corners = [
			Vector2(-hl, -hw),
			Vector2(hl, -hw),
			Vector2(hl, hw),
			Vector2(-hl, hw)
		]
		for c in corners:
			points.append(base_shape.rotate_point(c, base_rotation))
	elif shape_type == "oval":
		var oval_base = base_shape as OvalBase
		var segments = 32
		for i in range(segments):
			var angle = (float(i) / float(segments)) * TAU
			var local_point = Vector2(
				oval_base.length * cos(angle),
				oval_base.width * sin(angle)
			)
			points.append(base_shape.rotate_point(local_point, base_rotation))
	else:
		# Fallback circle
		var circ = base_shape as CircularBase
		var r = circ.radius if circ else 20.0
		for i in range(32):
			var angle = (float(i) / 32.0) * TAU
			points.append(Vector2(cos(angle), sin(angle)) * r)

	return points
