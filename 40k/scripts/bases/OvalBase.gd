extends BaseShape
class_name OvalBase

# Oval/Ellipse base implementation
# Used for vehicles like the Caladius Grav-tank

var length: float = 85.0  # Major axis (half-length)
var width: float = 52.5   # Minor axis (half-width)

func _init(length_value: float = 85.0, width_value: float = 52.5) -> void:
	# Store half-values for easier calculations
	length = length_value / 2.0
	width = width_value / 2.0

func get_type() -> String:
	return "oval"

func get_bounds() -> Rect2:
	return Rect2(-length, -width, length * 2, width * 2)

func draw(canvas: CanvasItem, position: Vector2, rotation: float, color: Color, border_color: Color, border_width: float = 3.0) -> void:
	# Generate points for the ellipse
	var points = PackedVector2Array()
	var segments = 64

	for i in range(segments + 1):
		var angle = (i * TAU) / segments
		var local_point = Vector2(
			length * cos(angle),
			width * sin(angle)
		)
		points.append(to_world_space(local_point, position, rotation))

	# Draw filled oval
	canvas.draw_colored_polygon(points, color)

	# Draw border
	canvas.draw_polyline(points, border_color, border_width)

func contains_point(point: Vector2, position: Vector2, rotation: float) -> bool:
	# Transform point to local space
	var local_point = to_local_space(point, position, rotation)

	# Check if point is within ellipse equation: (x/a)^2 + (y/b)^2 <= 1
	var normalized_x = local_point.x / length
	var normalized_y = local_point.y / width

	return (normalized_x * normalized_x + normalized_y * normalized_y) <= 1.0

func get_edge_point(from: Vector2, to: Vector2, position: Vector2, rotation: float) -> Vector2:
	# Transform to local space
	var local_from = to_local_space(from, position, rotation)
	var local_to = to_local_space(to, position, rotation)

	var direction = local_to - local_from
	if direction.length() == 0:
		return position

	direction = direction.normalized()

	# Find intersection of ray with ellipse
	# Using parametric equation of line: P = local_from + t * direction
	# Ellipse equation: (x/a)^2 + (y/b)^2 = 1

	var a = length
	var b = width
	var dx = direction.x
	var dy = direction.y
	var px = local_from.x
	var py = local_from.y

	# Quadratic equation coefficients
	var A = (dx * dx) / (a * a) + (dy * dy) / (b * b)
	var B = 2.0 * ((px * dx) / (a * a) + (py * dy) / (b * b))
	var C = (px * px) / (a * a) + (py * py) / (b * b) - 1.0

	var discriminant = B * B - 4.0 * A * C

	if discriminant < 0:
		# No intersection, return center
		return position

	# Calculate intersection points
	var t1 = (-B - sqrt(discriminant)) / (2.0 * A)
	var t2 = (-B + sqrt(discriminant)) / (2.0 * A)

	# Choose the first positive intersection
	var t = -1.0
	if t1 >= 0:
		t = t1
	elif t2 >= 0:
		t = t2

	if t < 0:
		return position

	var edge_point = local_from + direction * t

	# Transform back to world space
	return to_world_space(edge_point, position, rotation)

func get_closest_edge_point(from: Vector2, position: Vector2, rotation: float) -> Vector2:
	# Transform to local space
	var local_point = to_local_space(from, position, rotation)

	# For ellipse, find the point on the edge closest to the given point
	# This involves solving for the point on the ellipse that minimizes distance

	# If point is at center, default to right edge
	if local_point.length() < 0.01:
		return to_world_space(Vector2(length, 0), position, rotation)

	# Normalize the direction from center to point
	var angle = atan2(local_point.y / width, local_point.x / length)

	# Calculate point on ellipse edge at this angle
	var edge_local = Vector2(
		length * cos(angle),
		width * sin(angle)
	)

	# Transform back to world space
	return to_world_space(edge_local, position, rotation)

func needs_pivot_cost() -> bool:
	# Oval bases need pivot cost for vehicles/monsters
	return true

func overlaps_with(other: BaseShape, my_position: Vector2, my_rotation: float, other_position: Vector2, other_rotation: float) -> bool:
	if other.get_type() == "circular":
		# Check if circle center is inside oval
		if contains_point(other_position, my_position, my_rotation):
			return true

		# Check sample points on circle edge
		var other_circle = other as CircularBase
		for i in range(16):
			var angle = (i * TAU) / 16
			var edge_point = other_position + Vector2(cos(angle), sin(angle)) * other_circle.radius
			if contains_point(edge_point, my_position, my_rotation):
				return true

		# Check if oval edge points are inside circle
		for i in range(16):
			var angle = (i * TAU) / 16
			var local_point = Vector2(length * cos(angle), width * sin(angle))
			var world_point = to_world_space(local_point, my_position, my_rotation)
			if world_point.distance_to(other_position) < other_circle.radius:
				return true

		return false
	elif other.get_type() == "oval":
		# Oval-oval: sample points along both ovals
		var other_oval = other as OvalBase

		# Check if centers are inside each other
		if contains_point(other_position, my_position, my_rotation):
			return true
		if other.contains_point(my_position, other_position, other_rotation):
			return true

		# Sample points along my edge
		for i in range(24):
			var angle = (i * TAU) / 24
			var local_point = Vector2(length * cos(angle), width * sin(angle))
			var world_point = to_world_space(local_point, my_position, my_rotation)
			if other.contains_point(world_point, other_position, other_rotation):
				return true

		# Sample points along other edge
		for i in range(24):
			var angle = (i * TAU) / 24
			var local_point = Vector2(
				other_oval.length * cos(angle),
				other_oval.width * sin(angle)
			)
			var world_point = other.to_world_space(local_point, other_position, other_rotation)
			if contains_point(world_point, my_position, my_rotation):
				return true

		return false
	else:
		# Oval vs rectangle
		# Check if any rectangle corner is inside oval
		var rect = other as RectangularBase
		var corners = rect._get_world_corners(other_position, other_rotation)
		for corner in corners:
			if contains_point(corner, my_position, my_rotation):
				return true

		# Check if rectangle center is inside oval
		if contains_point(other_position, my_position, my_rotation):
			return true

		# Sample points along oval edge
		for i in range(24):
			var angle = (i * TAU) / 24
			var local_point = Vector2(length * cos(angle), width * sin(angle))
			var world_point = to_world_space(local_point, my_position, my_rotation)
			if other.contains_point(world_point, other_position, other_rotation):
				return true

		return false

func overlaps_with_segment(position: Vector2, rotation: float, seg_start: Vector2, seg_end: Vector2) -> bool:
	# Check if segment endpoints are inside oval
	if contains_point(seg_start, position, rotation) or contains_point(seg_end, position, rotation):
		return true

	# Transform segment to local space
	var local_start = to_local_space(seg_start, position, rotation)
	var local_end = to_local_space(seg_end, position, rotation)

	# Check for intersection using line-ellipse intersection algorithm
	var seg_vec = local_end - local_start
	if seg_vec.length_squared() == 0:
		return contains_point(seg_start, position, rotation)

	# Parametric line equation: P = local_start + t * seg_vec (0 <= t <= 1)
	# Ellipse equation: (x/a)^2 + (y/b)^2 = 1
	var a = length
	var b = width
	var dx = seg_vec.x
	var dy = seg_vec.y
	var px = local_start.x
	var py = local_start.y

	# Quadratic equation coefficients
	# Use slightly shrunk ellipse (1px clearance) to avoid false positives from floating point errors
	var clearance_px = 1.0
	var a_shrunk = max(a - clearance_px, 1.0)
	var b_shrunk = max(b - clearance_px, 1.0)

	var A = (dx * dx) / (a_shrunk * a_shrunk) + (dy * dy) / (b_shrunk * b_shrunk)
	var B = 2.0 * ((px * dx) / (a_shrunk * a_shrunk) + (py * dy) / (b_shrunk * b_shrunk))
	var C = (px * px) / (a_shrunk * a_shrunk) + (py * py) / (b_shrunk * b_shrunk) - 1.0

	var discriminant = B * B - 4.0 * A * C

	if discriminant < 0:
		return false  # No intersection

	# Calculate intersection parameters
	var t1 = (-B - sqrt(discriminant)) / (2.0 * A)
	var t2 = (-B + sqrt(discriminant)) / (2.0 * A)

	# Check if any intersection is within the segment (0 <= t <= 1)
	return (t1 >= 0.0 and t1 <= 1.0) or (t2 >= 0.0 and t2 <= 1.0)