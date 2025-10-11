extends Node

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

	print("DEBUG Measurement.create_base_shape:")
	print("  base_type: ", base_type)
	print("  base_mm: ", base_mm)
	print("  base_dimensions: ", base_dimensions)

	match base_type:
		"circular":
			var radius = base_radius_px(base_mm)
			print("  Creating CircularBase with radius: ", radius, "px (from ", base_mm, "mm)")
			return CircularBase.new(radius)
		"rectangular":
			var length_mm = base_dimensions.get("length", base_mm)
			var width_mm = base_dimensions.get("width", base_mm * 0.6)
			var length_px = mm_to_px(length_mm)
			var width_px = mm_to_px(width_mm)
			print("  Creating RectangularBase: ", length_px, "px x ", width_px, "px")
			return RectangularBase.new(length_px, width_px)
		"oval":
			var length_mm = base_dimensions.get("length", base_mm)
			var width_mm = base_dimensions.get("width", base_mm * 0.6)
			var length_px = mm_to_px(length_mm)
			var width_px = mm_to_px(width_mm)
			print("  Creating OvalBase: ", length_px, "px x ", width_px, "px")
			return OvalBase.new(length_px, width_px)
		_:
			# Default to circular
			var radius = base_radius_px(base_mm)
			print("  FALLBACK: Creating CircularBase with radius: ", radius, "px")
			return CircularBase.new(radius)

func model_to_model_distance_px(model1: Dictionary, model2: Dictionary) -> float:
	var pos1 = model1.get("position", Vector2.ZERO)
	var pos2 = model2.get("position", Vector2.ZERO)

	# Handle position as Dictionary or Vector2
	if pos1 is Dictionary:
		pos1 = Vector2(pos1.get("x", 0), pos1.get("y", 0))
	if pos2 is Dictionary:
		pos2 = Vector2(pos2.get("x", 0), pos2.get("y", 0))

	var rotation1 = model1.get("rotation", 0.0)
	var rotation2 = model2.get("rotation", 0.0)

	var shape1 = create_base_shape(model1)
	var shape2 = create_base_shape(model2)

	# Get the closest edge points between the two shapes
	var edge1 = shape1.get_closest_edge_point(pos2, pos1, rotation1)
	var edge2 = shape2.get_closest_edge_point(pos1, pos2, rotation2)

	return edge1.distance_to(edge2)

func model_to_model_distance_inches(model1: Dictionary, model2: Dictionary) -> float:
	return px_to_inches(model_to_model_distance_px(model1, model2))

func models_overlap(model1: Dictionary, model2: Dictionary) -> bool:
	# Check if two models' bases overlap
	var pos1 = model1.get("position", Vector2.ZERO)
	var pos2 = model2.get("position", Vector2.ZERO)

	# Handle position as Dictionary or Vector2
	if pos1 is Dictionary:
		pos1 = Vector2(pos1.get("x", 0), pos1.get("y", 0))
	if pos2 is Dictionary:
		pos2 = Vector2(pos2.get("x", 0), pos2.get("y", 0))

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
