extends BaseShape
class_name CircularBase

# Circular base implementation
# Used for standard round bases

var radius: float = 20.0

func _init(radius_value: float = 20.0) -> void:
	radius = radius_value

func get_type() -> String:
	return "circular"

func get_bounds() -> Rect2:
	return Rect2(-radius, -radius, radius * 2, radius * 2)

func draw(canvas: CanvasItem, position: Vector2, rotation: float, color: Color, border_color: Color, border_width: float = 3.0) -> void:
	# Draw filled circle
	canvas.draw_circle(position, radius, color)

	# Draw border
	canvas.draw_arc(position, radius, 0, TAU, 64, border_color, border_width)

func contains_point(point: Vector2, position: Vector2, rotation: float) -> bool:
	# Rotation doesn't matter for circles
	return point.distance_to(position) <= radius

func get_edge_point(from: Vector2, to: Vector2, position: Vector2, rotation: float) -> Vector2:
	# Find intersection of line from->to with circle edge
	var direction = (to - from).normalized()
	if direction.length() == 0:
		return position

	# Ray from position in direction of from->to line
	var to_from = from - position
	var projection = to_from.project(direction)
	var closest_on_line = from - projection

	# If line passes through circle center, use direct approach
	if closest_on_line.distance_to(position) < 0.01:
		return position + direction * radius

	# Otherwise find intersection point
	var center_to_from = from - position
	return position + center_to_from.normalized() * radius

func get_closest_edge_point(from: Vector2, position: Vector2, rotation: float) -> Vector2:
	# For a circle, closest edge point is always along the line from center to point
	var direction = from - position
	if direction.length() == 0:
		return position + Vector2(radius, 0)  # Default to right edge if point is at center

	return position + direction.normalized() * radius

func needs_pivot_cost() -> bool:
	# Circular bases don't need pivot cost
	return false

func overlaps_with(other: BaseShape, my_position: Vector2, my_rotation: float, other_position: Vector2, other_rotation: float) -> bool:
	if other.get_type() == "circular":
		# Circle-circle collision is simple distance check
		var other_circle = other as CircularBase
		var distance = my_position.distance_to(other_position)
		return distance < (radius + other_circle.radius)
	else:
		# For circle vs other shapes, check if circle center is within shape
		# or if any point on circle edge is within shape
		if other.contains_point(my_position, other_position, other_rotation):
			return true

		# Check 8 points around the circle edge
		for i in range(8):
			var angle = (i * TAU) / 8
			var edge_point = my_position + Vector2(cos(angle), sin(angle)) * radius
			if other.contains_point(edge_point, other_position, other_rotation):
				return true

		# Also check if other shape's closest edge point is inside this circle
		var closest = other.get_closest_edge_point(my_position, other_position, other_rotation)
		if closest.distance_to(my_position) < radius:
			return true

		return false