extends BaseShape
class_name RectangularBase

# Note: CircularBase and OvalBase are available globally via class_name
# Removed preloads to fix circular dependency causing web export failures


# Rectangular base implementation
# Used for vehicles like the Ork Battlewagon

var length: float = 100.0  # Length along local X axis
var width: float = 60.0    # Width along local Y axis

func _init(length_value: float = 100.0, width_value: float = 60.0) -> void:
	length = length_value
	width = width_value

func get_type() -> String:
	return "rectangular"

func get_bounds() -> Rect2:
	return Rect2(-length/2, -width/2, length, width)

func draw(canvas: CanvasItem, position: Vector2, rotation: float, color: Color, border_color: Color, border_width: float = 3.0) -> void:
	# Calculate rectangle corners in local space
	var half_length = length / 2
	var half_width = width / 2

	var corners_local = [
		Vector2(-half_length, -half_width),  # Top-left
		Vector2(half_length, -half_width),   # Top-right
		Vector2(half_length, half_width),    # Bottom-right
		Vector2(-half_length, half_width)    # Bottom-left
	]

	# Transform to world space
	var corners_world = PackedVector2Array()
	for corner in corners_local:
		corners_world.append(to_world_space(corner, position, rotation))

	# Draw filled rectangle
	canvas.draw_colored_polygon(corners_world, color)

	# Draw border
	corners_world.append(corners_world[0])  # Close the shape
	canvas.draw_polyline(corners_world, border_color, border_width)

func contains_point(point: Vector2, position: Vector2, rotation: float) -> bool:
	# Transform point to local space
	var local_point = to_local_space(point, position, rotation)

	# Check if point is within rectangle bounds
	return abs(local_point.x) <= length/2 and abs(local_point.y) <= width/2

func get_edge_point(from: Vector2, to: Vector2, position: Vector2, rotation: float) -> Vector2:
	# Transform to local space
	var local_from = to_local_space(from, position, rotation)
	var local_to = to_local_space(to, position, rotation)

	var direction = local_to - local_from
	if direction.length() == 0:
		return position

	# Find intersection with rectangle edges
	var half_length = length / 2
	var half_width = width / 2

	var t_min = 0.0
	var t_max = 1.0
	var edge_point = local_from

	# Check intersection with each edge
	var edges = [
		{"normal": Vector2(1, 0), "distance": half_length},   # Right
		{"normal": Vector2(-1, 0), "distance": half_length},  # Left
		{"normal": Vector2(0, 1), "distance": half_width},    # Bottom
		{"normal": Vector2(0, -1), "distance": half_width}    # Top
	]

	for edge in edges:
		var denominator = direction.dot(edge.normal)
		if abs(denominator) > 0.001:
			var t = (edge.distance - local_from.dot(edge.normal)) / denominator
			if t >= 0 and t <= 1:
				var intersection = local_from + direction * t
				# Verify the intersection is on the rectangle
				if abs(intersection.x) <= half_length + 0.01 and abs(intersection.y) <= half_width + 0.01:
					edge_point = intersection
					t_max = min(t_max, t)

	# Transform back to world space
	return to_world_space(edge_point, position, rotation)

func get_closest_edge_point(from: Vector2, position: Vector2, rotation: float) -> Vector2:
	# Transform to local space
	var local_point = to_local_space(from, position, rotation)

	var half_length = length / 2
	var half_width = width / 2

	# Clamp to rectangle bounds
	var closest_local = Vector2(
		clamp(local_point.x, -half_length, half_length),
		clamp(local_point.y, -half_width, half_width)
	)

	# If point is inside, project to nearest edge
	if abs(local_point.x) < half_length and abs(local_point.y) < half_width:
		# Find distances to each edge
		var dist_right = half_length - local_point.x
		var dist_left = local_point.x + half_length
		var dist_bottom = half_width - local_point.y
		var dist_top = local_point.y + half_width

		var min_dist = min(dist_right, min(dist_left, min(dist_bottom, dist_top)))

		if min_dist == dist_right:
			closest_local.x = half_length
		elif min_dist == dist_left:
			closest_local.x = -half_length
		elif min_dist == dist_bottom:
			closest_local.y = half_width
		else:
			closest_local.y = -half_width

	# Transform back to world space
	return to_world_space(closest_local, position, rotation)

func needs_pivot_cost() -> bool:
	# Rectangular bases need pivot cost for vehicles/monsters
	return true

func overlaps_with(other: BaseShape, my_position: Vector2, my_rotation: float, other_position: Vector2, other_rotation: float) -> bool:
	# Get my corners
	var my_corners = _get_world_corners(my_position, my_rotation)

	if other.get_type() == "circular":
		# Check if any corner is inside the circle
		var other_circle = other as CircularBase
		for corner in my_corners:
			if corner.distance_to(other_position) < other_circle.radius:
				return true

		# Check if circle center is inside rectangle
		if contains_point(other_position, my_position, my_rotation):
			return true

		# Check if circle intersects any edge
		for i in range(4):
			var start = my_corners[i]
			var end = my_corners[(i + 1) % 4]
			if _segment_intersects_circle(start, end, other_position, other_circle.radius):
				return true

		return false
	elif other.get_type() == "rectangular":
		# Rectangle-rectangle: use SAT (Separating Axis Theorem)
		var other_corners = (other as RectangularBase)._get_world_corners(other_position, other_rotation)
		return _rectangles_overlap_sat(my_corners, other_corners)
	else:
		# For rectangle vs oval, check sample points
		# Check if any corner is inside the other shape
		for corner in my_corners:
			if other.contains_point(corner, other_position, other_rotation):
				return true

		# Check if center is inside other shape
		if other.contains_point(my_position, other_position, other_rotation):
			return true

		# Sample points along edges
		for i in range(4):
			var start = my_corners[i]
			var end = my_corners[(i + 1) % 4]
			for t in range(1, 4):  # Check 3 points along each edge
				var point = start.lerp(end, t / 4.0)
				if other.contains_point(point, other_position, other_rotation):
					return true

		# Also check if other shape has points inside this rectangle
		# Sample points from the other shape
		if other.get_type() == "oval":
			for i in range(16):
				var angle = (i * TAU) / 16
				var oval = other as OvalBase
				var local_point = Vector2(
					oval.length * cos(angle),
					oval.width * sin(angle)
				)
				var world_point = other.to_world_space(local_point, other_position, other_rotation)
				if contains_point(world_point, my_position, my_rotation):
					return true

		return false

func _get_world_corners(position: Vector2, rotation: float) -> Array:
	var half_length = length / 2
	var half_width = width / 2

	var corners_local = [
		Vector2(-half_length, -half_width),
		Vector2(half_length, -half_width),
		Vector2(half_length, half_width),
		Vector2(-half_length, half_width)
	]

	var corners_world = []
	for corner in corners_local:
		corners_world.append(to_world_space(corner, position, rotation))

	return corners_world

func _segment_intersects_circle(seg_start: Vector2, seg_end: Vector2, circle_center: Vector2, radius: float) -> bool:
	# Find closest point on segment to circle center
	var seg_vec = seg_end - seg_start
	var to_center = circle_center - seg_start
	var t = clamp(to_center.dot(seg_vec) / seg_vec.length_squared(), 0.0, 1.0)
	var closest_point = seg_start + seg_vec * t
	return closest_point.distance_to(circle_center) <= radius

func _rectangles_overlap_sat(corners1: Array, corners2: Array) -> bool:
	# Separating Axis Theorem for convex polygons
	var all_corners = corners1 + corners2

	# Check all potential separating axes (perpendicular to each edge)
	for corners in [corners1, corners2]:
		for i in range(4):
			var edge = corners[(i + 1) % 4] - corners[i]
			var axis = Vector2(-edge.y, edge.x).normalized()

			# Project all corners onto this axis
			var min1 = INF
			var max1 = -INF
			var min2 = INF
			var max2 = -INF

			for corner in corners1:
				var projection = corner.dot(axis)
				min1 = min(min1, projection)
				max1 = max(max1, projection)

			for corner in corners2:
				var projection = corner.dot(axis)
				min2 = min(min2, projection)
				max2 = max(max2, projection)

			# Check if projections are separated
			if max1 < min2 or max2 < min1:
				return false  # Found a separating axis

	return true  # No separating axis found, shapes overlap

func overlaps_with_segment(position: Vector2, rotation: float, seg_start: Vector2, seg_end: Vector2) -> bool:
	# Get rectangle corners
	var corners = _get_world_corners(position, rotation)

	# Check if segment endpoints are inside rectangle
	if contains_point(seg_start, position, rotation) or contains_point(seg_end, position, rotation):
		return true

	# Check if segment intersects any edge of the rectangle
	for i in range(4):
		var corner1 = corners[i]
		var corner2 = corners[(i + 1) % 4]

		# Check if segment intersects this edge
		var intersection = Geometry2D.segment_intersects_segment(seg_start, seg_end, corner1, corner2)
		if intersection != null:
			return true

	return false
