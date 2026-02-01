extends Resource
class_name BaseShape

# Abstract base class for model base shapes
# Provides interface for different base types (circular, rectangular, oval)

func get_type() -> String:
	push_error("BaseShape.get_type() must be overridden")
	return ""

func get_bounds() -> Rect2:
	push_error("BaseShape.get_bounds() must be overridden")
	return Rect2()

func draw(canvas: CanvasItem, position: Vector2, rotation: float, color: Color, border_color: Color, border_width: float = 3.0) -> void:
	push_error("BaseShape.draw() must be overridden")

func contains_point(point: Vector2, position: Vector2, rotation: float) -> bool:
	push_error("BaseShape.contains_point() must be overridden")
	return false

func get_edge_point(from: Vector2, to: Vector2, position: Vector2, rotation: float) -> Vector2:
	push_error("BaseShape.get_edge_point() must be overridden")
	return Vector2.ZERO

func get_closest_edge_point(from: Vector2, position: Vector2, rotation: float) -> Vector2:
	push_error("BaseShape.get_closest_edge_point() must be overridden")
	return position

func needs_pivot_cost() -> bool:
	# Override for shapes that require pivot cost
	return false

# Helper function to rotate a point around origin
func rotate_point(point: Vector2, angle: float) -> Vector2:
	var cos_angle = cos(angle)
	var sin_angle = sin(angle)
	return Vector2(
		point.x * cos_angle - point.y * sin_angle,
		point.x * sin_angle + point.y * cos_angle
	)

# Helper to transform a local point to world space
func to_world_space(local_point: Vector2, position: Vector2, rotation: float) -> Vector2:
	return position + rotate_point(local_point, rotation)

# Helper to transform a world point to local space
func to_local_space(world_point: Vector2, position: Vector2, rotation: float) -> Vector2:
	var relative = world_point - position
	return rotate_point(relative, -rotation)

# Check if this shape overlaps with another shape
func overlaps_with(other: BaseShape, my_position: Vector2, my_rotation: float, other_position: Vector2, other_rotation: float) -> bool:
	push_error("BaseShape.overlaps_with() must be overridden")
	return false

# Check if shape overlaps with a line segment (for wall collision)
func overlaps_with_segment(position: Vector2, rotation: float, seg_start: Vector2, seg_end: Vector2) -> bool:
	push_error("BaseShape.overlaps_with_segment() must be overridden")
	return false
