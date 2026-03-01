extends Node
const BaseShape = preload("res://scripts/bases/BaseShape.gd")
const CircularBase = preload("res://scripts/bases/CircularBase.gd")
const RectangularBase = preload("res://scripts/bases/RectangularBase.gd")
const OvalBase = preload("res://scripts/bases/OvalBase.gd")

const PX_PER_INCH: float = 40.0
const MM_PER_INCH: float = 25.4

func inches_to_px(inches: float) -> float:
	return inches * PX_PER_INCH

func px_to_inches(pixels: float) -> float:
	return pixels / PX_PER_INCH

func mm_to_px(mm: float) -> float:
	var inches = mm / MM_PER_INCH
	return inches_to_px(inches)

func px_to_mm(pixels: float) -> float:
	var inches = px_to_inches(pixels)
	return inches * MM_PER_INCH

func base_radius_px(base_mm: int) -> float:
	return mm_to_px(base_mm) / 2.0

func distance_inches(pos1: Vector2, pos2: Vector2) -> float:
	var dist_px = pos1.distance_to(pos2)
	return px_to_inches(dist_px)

func distance_px(pos1: Vector2, pos2: Vector2) -> float:
	return pos1.distance_to(pos2)

func distance_polyline_px(points: Array) -> float:
	# Calculate total distance along a polyline path
	if points.size() < 2:
		return 0.0
	
	var total_distance = 0.0
	for i in range(1, points.size()):
		if points[i] is Vector2 and points[i-1] is Vector2:
			total_distance += points[i-1].distance_to(points[i])
	
	return total_distance

func distance_polyline_inches(points: Array) -> float:
	return px_to_inches(distance_polyline_px(points))

func edge_to_edge_distance_px(pos1: Vector2, radius1: float, pos2: Vector2, radius2: float) -> float:
	# Calculate edge-to-edge distance between two circles
	var center_distance = pos1.distance_to(pos2)
	return max(0.0, center_distance - radius1 - radius2)

func edge_to_edge_distance_inches(pos1: Vector2, radius1_mm: float, pos2: Vector2, radius2_mm: float) -> float:
	var r1_px = base_radius_px(radius1_mm)
	var r2_px = base_radius_px(radius2_mm)
	return px_to_inches(edge_to_edge_distance_px(pos1, r1_px, pos2, r2_px))

# Shape-aware distance calculations
func create_base_shape(model: Dictionary) -> BaseShape:
	var base_type = model.get("base_type", "circular")
	var base_mm = model.get("base_mm", 32)
	var base_dimensions = model.get("base_dimensions", {})

	match base_type:
		"circular":
			var radius = base_radius_px(base_mm)
			return CircularBase.new(radius)
		"rectangular":
			var length_mm = base_dimensions.get("length", base_mm)
			var width_mm = base_dimensions.get("width", base_mm * 0.6)
			var length_px = mm_to_px(length_mm)
			var width_px = mm_to_px(width_mm)
			return RectangularBase.new(length_px, width_px)
		"oval":
			var length_mm = base_dimensions.get("length", base_mm)
			var width_mm = base_dimensions.get("width", base_mm * 0.6)
			var length_px = mm_to_px(length_mm)
			var width_px = mm_to_px(width_mm)
			return OvalBase.new(length_px, width_px)
		_:
			# Default to circular
			var radius = base_radius_px(base_mm)
			return CircularBase.new(radius)

func model_edge_to_point_distance_px(model: Dictionary, point: Vector2) -> float:
	# Shape-aware distance from the nearest edge of a model's base to a point.
	# This correctly handles oval and rectangular bases, unlike base_radius_px()
	# which assumes a circular base.
	var pos = model.get("position", Vector2.ZERO)
	if pos is Dictionary:
		pos = Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos == null:
		pos = Vector2.ZERO

	var rotation = model.get("rotation", 0.0)
	var shape = create_base_shape(model)
	var closest_edge = shape.get_closest_edge_point(point, pos, rotation)
	return closest_edge.distance_to(point)

func model_to_model_distance_px(model1: Dictionary, model2: Dictionary) -> float:
	var pos1 = model1.get("position", Vector2.ZERO)
	var pos2 = model2.get("position", Vector2.ZERO)

	# Handle position as Dictionary or Vector2
	if pos1 is Dictionary:
		pos1 = Vector2(pos1.get("x", 0), pos1.get("y", 0))
	elif pos1 == null:
		pos1 = Vector2.ZERO

	if pos2 is Dictionary:
		pos2 = Vector2(pos2.get("x", 0), pos2.get("y", 0))
	elif pos2 == null:
		pos2 = Vector2.ZERO

	var rotation1 = model1.get("rotation", 0.0)
	var rotation2 = model2.get("rotation", 0.0)

	var shape1 = create_base_shape(model1)
	var shape2 = create_base_shape(model2)

	# Use iterative closest-point refinement to find the minimum distance
	# between two convex shapes. Start by finding each shape's closest edge
	# point to the other shape's center, then iteratively refine by finding
	# each shape's closest point to the other's previous closest point.
	# This converges to the true minimum distance for convex shapes.
	var edge1 = shape1.get_closest_edge_point(pos2, pos1, rotation1)
	var edge2 = shape2.get_closest_edge_point(edge1, pos2, rotation2)

	# Iterate to refine - converges quickly for convex shapes
	for i in range(4):
		var new_edge1 = shape1.get_closest_edge_point(edge2, pos1, rotation1)
		var new_edge2 = shape2.get_closest_edge_point(new_edge1, pos2, rotation2)
		# Check for convergence
		if new_edge1.distance_to(edge1) < 0.1 and new_edge2.distance_to(edge2) < 0.1:
			edge1 = new_edge1
			edge2 = new_edge2
			break
		edge1 = new_edge1
		edge2 = new_edge2

	return edge1.distance_to(edge2)

func model_to_model_distance_inches(model1: Dictionary, model2: Dictionary) -> float:
	return px_to_inches(model_to_model_distance_px(model1, model2))

func model_vertical_distance_inches(model1: Dictionary, model2: Dictionary) -> float:
	"""Returns the vertical (elevation) distance between two models in inches.
	Models store elevation in an 'elevation' field (defaults to 0.0 for ground floor)."""
	var elev1 = model1.get("elevation", 0.0)
	var elev2 = model2.get("elevation", 0.0)
	return abs(elev1 - elev2)

func is_within_coherency(model1: Dictionary, model2: Dictionary) -> bool:
	"""Check if two models satisfy the 10th Edition coherency requirement:
	within 2\" horizontally (edge-to-edge) AND within 5\" vertically."""
	var horizontal = model_to_model_distance_inches(model1, model2)
	if horizontal > 2.0:
		return false
	var vertical = model_vertical_distance_inches(model1, model2)
	return vertical <= 5.0

func models_overlap(model1: Dictionary, model2: Dictionary) -> bool:
	# Check if two models' bases overlap
	var pos1 = model1.get("position", Vector2.ZERO)
	var pos2 = model2.get("position", Vector2.ZERO)

	# Handle position as Dictionary or Vector2
	if pos1 is Dictionary:
		pos1 = Vector2(pos1.get("x", 0), pos1.get("y", 0))
	elif pos1 == null:
		pos1 = Vector2.ZERO

	if pos2 is Dictionary:
		pos2 = Vector2(pos2.get("x", 0), pos2.get("y", 0))
	elif pos2 == null:
		pos2 = Vector2.ZERO

	var rotation1 = model1.get("rotation", 0.0)
	var rotation2 = model2.get("rotation", 0.0)

	var shape1 = create_base_shape(model1)
	var shape2 = create_base_shape(model2)

	# Use the shape's overlaps_with method for proper collision detection
	return shape1.overlaps_with(shape2, pos1, rotation1, pos2, rotation2)

# New function to check if a model overlaps with a wall
func model_overlaps_wall(model: Dictionary, wall: Dictionary) -> bool:
	var pos = model.get("position", Vector2.ZERO)

	# Handle position as Dictionary or Vector2
	if pos is Dictionary:
		pos = Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos == null:
		pos = Vector2.ZERO

	var rotation = model.get("rotation", 0.0)
	var shape = create_base_shape(model)

	var wall_start = wall.get("start", Vector2.ZERO)
	var wall_end = wall.get("end", Vector2.ZERO)

	# Delegate to shape-specific collision check
	return shape.overlaps_with_segment(pos, rotation, wall_start, wall_end)

# Check if model overlaps with any walls in terrain
func model_overlaps_any_wall(model: Dictionary) -> bool:
	for terrain in TerrainManager.terrain_features:
		var walls = terrain.get("walls", [])
		for wall in walls:
			if model_overlaps_wall(model, wall):
				return true
	return false

# Shape-aware engagement range check
# This is the recommended function for all engagement range checks throughout the codebase
func is_in_engagement_range_shape_aware(model1: Dictionary, model2: Dictionary, er_inches: float = 1.0) -> bool:
	var distance_px = model_to_model_distance_px(model1, model2)
	var er_px = inches_to_px(er_inches)
	return distance_px <= er_px

# ── Polygon geometry helpers (single source of truth) ──────────────
# Used by DeploymentPhase, DeploymentController, and any other code
# that needs to check if a model base is wholly within a polygon.

## Minimum distance from [param point] to the line segment from
## [param line_start] to [param line_end].
func point_to_line_distance(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	var line_vec = line_end - line_start
	var point_vec = point - line_start
	var line_len = line_vec.length()

	if line_len == 0:
		return point_vec.length()

	var t = max(0, min(1, point_vec.dot(line_vec) / (line_len * line_len)))
	var projection = line_start + t * line_vec

	return point.distance_to(projection)

## Returns [code]true[/code] if the circle at [param center] with the
## given [param radius] is wholly inside [param polygon].
func circle_wholly_in_polygon(center: Vector2, radius: float, polygon: PackedVector2Array) -> bool:
	if not Geometry2D.is_point_in_polygon(center, polygon):
		return false

	for i in range(polygon.size()):
		var p1 = polygon[i]
		var p2 = polygon[(i + 1) % polygon.size()]
		var dist = point_to_line_distance(center, p1, p2)
		if dist < radius:
			return false

	return true

var _last_zone_debug_center: Vector2 = Vector2.INF

## Returns [code]true[/code] if the model base described by [param model_data]
## placed at [param center] with the given [param rotation] is wholly inside
## [param polygon].  Handles circular, oval, and rectangular bases.
func shape_wholly_in_polygon(center: Vector2, model_data: Dictionary, rotation: float, polygon: PackedVector2Array) -> bool:
	# Create the base shape
	var shape = create_base_shape(model_data)
	if not shape:
		return false

	# For circular, use existing method
	if shape.get_type() == "circular":
		var circular = shape as CircularBase
		return circle_wholly_in_polygon(center, circular.radius, polygon)

	# For non-circular shapes, we need to check multiple points around the edge
	var _should_log = center.distance_to(_last_zone_debug_center) > 1.0
	if _should_log:
		_last_zone_debug_center = center
		print("\n=== DEBUG: Zone Validation for %s ===" % shape.get_type())
		print("Center: ", center)
		print("Rotation: %.2f degrees (%.4f radians)" % [rad_to_deg(rotation), rotation])

	# Generate sample points around the shape's edge
	var sample_points = []

	if shape.get_type() == "oval":
		# For ovals, sample points around the ellipse perimeter
		var oval = shape as OvalBase
		var num_samples = 16  # Check 16 points around the ellipse
		if _should_log:
			print("Oval shape - length: %.2f, width: %.2f" % [oval.length, oval.width])

		for i in range(num_samples):
			var angle = (i * TAU) / num_samples
			# Points on ellipse: (a*cos(θ), b*sin(θ))
			var local_point = Vector2(
				oval.length * cos(angle),
				oval.width * sin(angle)
			)
			sample_points.append(local_point)
	elif shape.get_type() == "rectangular":
		# For rectangles, check the 4 corners
		var bounds = shape.get_bounds()
		var half_width = bounds.size.x / 2.0
		var half_height = bounds.size.y / 2.0

		sample_points = [
			Vector2(-half_width, -half_height),
			Vector2(half_width, -half_height),
			Vector2(half_width, half_height),
			Vector2(-half_width, half_height)
		]
	else:
		# Fallback: use bounding box corners
		var bounds = shape.get_bounds()
		var half_width = bounds.size.x / 2.0
		var half_height = bounds.size.y / 2.0

		sample_points = [
			Vector2(-half_width, -half_height),
			Vector2(half_width, -half_height),
			Vector2(half_width, half_height),
			Vector2(-half_width, half_height)
		]

	if _should_log:
		print("Checking %d sample points" % sample_points.size())

	# Transform sample points to world space and check if in polygon
	var point_idx = 0
	for local_point in sample_points:
		var world_point = shape.to_world_space(local_point, center, rotation)
		var in_poly = Geometry2D.is_point_in_polygon(world_point, polygon)

		if _should_log and (point_idx < 4 or not in_poly):  # Only print first 4 and failures
			print("Point %d: local=%s -> world=%s, in_polygon=%s" % [point_idx, local_point, world_point, in_poly])

		if not in_poly:
			print("❌ FAILED: Point outside polygon")
			return false

		point_idx += 1

	if _should_log:
		print("✅ SUCCESS: All %d points in polygon" % sample_points.size())
	return true
