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