extends Node2D

# LoSDebugVisual - Visual debugging for Line of Sight mechanics
# Shows LoS lines and highlights terrain that blocks or provides cover

signal los_check_performed(from_pos: Vector2, to_pos: Vector2, blocked: bool, terrain_hit: Array)

var los_lines: Array = []  # Array of LoS line data
var highlighted_terrain: Dictionary = {}  # terrain_id -> original_color
var debug_enabled: bool = true
var terrain_visual_ref: Node2D = null

# Visual settings
const LOS_COLOR_CLEAR = Color.GREEN
const LOS_COLOR_BLOCKED = Color.RED
const LOS_COLOR_PARTIAL = Color.YELLOW  # For cover but not blocked
const LOS_LINE_WIDTH = 3.0
const TERRAIN_HIGHLIGHT_COLOR = Color(1.0, 0.5, 0.0, 0.8)  # Orange
const TERRAIN_BLOCKED_COLOR = Color(1.0, 0.0, 0.0, 0.8)  # Red
const TERRAIN_COVER_COLOR = Color(1.0, 1.0, 0.0, 0.8)  # Yellow

func _ready() -> void:
	z_index = 10  # Above most things for visibility
	name = "LoSDebugVisual"
	print("[LoSDebugVisual] Initialized")

func _draw() -> void:
	if not debug_enabled:
		return
	
	# Draw all LoS lines
	for los_data in los_lines:
		var from_pos = los_data.from
		var to_pos = los_data.to
		var color = los_data.color
		var width = los_data.get("width", LOS_LINE_WIDTH)
		
		# Draw main line
		draw_line(from_pos, to_pos, color, width)
		
		# Draw endpoints
		draw_circle(from_pos, width * 2, color)
		draw_circle(to_pos, width * 2, color)
		
		# Draw arrow at target end
		var direction = (to_pos - from_pos).normalized()
		var arrow_size = 15
		var arrow_angle = 0.5
		var arrow_point1 = to_pos - direction.rotated(arrow_angle) * arrow_size
		var arrow_point2 = to_pos - direction.rotated(-arrow_angle) * arrow_size
		draw_line(to_pos, arrow_point1, color, width)
		draw_line(to_pos, arrow_point2, color, width)
		
		# Draw intersection points if any
		if los_data.has("intersections"):
			for intersection in los_data.intersections:
				draw_circle(intersection, width * 1.5, Color.WHITE)
				draw_circle(intersection, width, color)

func check_and_visualize_los(from_pos: Vector2, to_pos: Vector2, board: Dictionary) -> Dictionary:
	# Perform LoS check and visualize results
	var result = {
		"has_los": true,
		"blocked_by": [],
		"provides_cover": [],
		"intersections": []
	}
	
	# Get terrain features
	var terrain_features = board.get("terrain_features", [])
	if terrain_features.is_empty() and TerrainManager:
		terrain_features = TerrainManager.terrain_features
	
	# Check each terrain piece
	for terrain in terrain_features:
		var polygon = terrain.get("polygon", PackedVector2Array())
		if polygon.is_empty():
			continue
		
		# Check if LoS crosses this terrain
		if _check_line_intersects_terrain(from_pos, to_pos, polygon):
			var terrain_id = terrain.get("id", "unknown")
			var height_cat = terrain.get("height_category", "")
			
			# Find intersection points for visualization
			var intersections = _get_line_polygon_intersections(from_pos, to_pos, polygon)
			result.intersections.append_array(intersections)
			
			# Check if both points are inside terrain
			var from_inside = _point_in_polygon(from_pos, polygon)
			var to_inside = _point_in_polygon(to_pos, polygon)
			
			if height_cat == "tall" and not from_inside and not to_inside:
				# Tall terrain blocks LoS if both models are outside
				result.has_los = false
				result.blocked_by.append(terrain_id)
				_highlight_terrain(terrain_id, TERRAIN_BLOCKED_COLOR)
			else:
				# Provides cover but doesn't block
				result.provides_cover.append(terrain_id)
				_highlight_terrain(terrain_id, TERRAIN_COVER_COLOR)
	
	# Add visualization line
	var line_color = LOS_COLOR_CLEAR
	if not result.has_los:
		line_color = LOS_COLOR_BLOCKED
	elif result.provides_cover.size() > 0:
		line_color = LOS_COLOR_PARTIAL
	
	add_los_line(from_pos, to_pos, line_color, result.intersections)
	
	# Emit signal for other systems
	emit_signal("los_check_performed", from_pos, to_pos, not result.has_los, result.blocked_by + result.provides_cover)
	
	return result

func add_los_line(from: Vector2, to: Vector2, color: Color = LOS_COLOR_CLEAR, intersections: Array = []) -> void:
	# Add a LoS line to be drawn
	los_lines.append({
		"from": from,
		"to": to,
		"color": color,
		"intersections": intersections,
		"timestamp": Time.get_ticks_msec()
	})
	
	# Keep only recent lines (last 5 seconds)
	var current_time = Time.get_ticks_msec()
	los_lines = los_lines.filter(func(line): return current_time - line.timestamp < 5000)
	
	queue_redraw()

func clear_los_lines() -> void:
	los_lines.clear()
	queue_redraw()

func _highlight_terrain(terrain_id: String, color: Color) -> void:
	# Highlight a terrain piece
	if not terrain_visual_ref:
		terrain_visual_ref = get_node_or_null("/root/Main/BoardRoot/TerrainVisual")
	
	if terrain_visual_ref and terrain_visual_ref.has_method("highlight_terrain"):
		terrain_visual_ref.highlight_terrain(terrain_id, true, color)
		
		# Store for later restoration
		if not highlighted_terrain.has(terrain_id):
			highlighted_terrain[terrain_id] = color
		
		# Auto-clear after 3 seconds
		get_tree().create_timer(3.0).timeout.connect(func(): _restore_terrain_highlight(terrain_id))

func _restore_terrain_highlight(terrain_id: String) -> void:
	if terrain_visual_ref and terrain_visual_ref.has_method("highlight_terrain"):
		terrain_visual_ref.highlight_terrain(terrain_id, false)
		highlighted_terrain.erase(terrain_id)

func clear_all_highlights() -> void:
	# Clear all terrain highlights
	for terrain_id in highlighted_terrain:
		_restore_terrain_highlight(terrain_id)
	highlighted_terrain.clear()

func _check_line_intersects_terrain(from: Vector2, to: Vector2, polygon: PackedVector2Array) -> bool:
	# Check if line segment intersects polygon
	for i in range(polygon.size()):
		var edge_start = polygon[i]
		var edge_end = polygon[(i + 1) % polygon.size()]
		
		if Geometry2D.segment_intersects_segment(from, to, edge_start, edge_end):
			return true
	
	return false

func _get_line_polygon_intersections(from: Vector2, to: Vector2, polygon: PackedVector2Array) -> Array:
	# Get all intersection points between line and polygon
	var intersections = []
	
	for i in range(polygon.size()):
		var edge_start = polygon[i]
		var edge_end = polygon[(i + 1) % polygon.size()]
		
		var intersection = Geometry2D.segment_intersects_segment(from, to, edge_start, edge_end)
		if intersection:
			intersections.append(intersection)
	
	return intersections

func _point_in_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	return Geometry2D.is_point_in_polygon(point, polygon)

func set_debug_enabled(enabled: bool) -> void:
	debug_enabled = enabled
	if not enabled:
		clear_los_lines()
		clear_all_highlights()
	queue_redraw()

func toggle_debug() -> void:
	set_debug_enabled(not debug_enabled)

# Helper function to test LoS between units
func test_los_between_units(shooter_id: String, target_id: String) -> void:
	var units = GameState.get_units()
	var shooter = units.get(shooter_id, {})
	var target = units.get(target_id, {})
	
	if shooter.is_empty() or target.is_empty():
		print("[LoSDebugVisual] Units not found")
		return
	
	# Get average positions
	var shooter_pos = _get_unit_center(shooter)
	var target_pos = _get_unit_center(target)
	
	if shooter_pos == Vector2.ZERO or target_pos == Vector2.ZERO:
		print("[LoSDebugVisual] Could not determine unit positions")
		return
	
	# Check and visualize
	var board = GameState.create_snapshot()
	var result = check_and_visualize_los(shooter_pos, target_pos, board)
	
	print("[LoSDebugVisual] LoS from %s to %s: %s" % [
		shooter.get("meta", {}).get("name", shooter_id),
		target.get("meta", {}).get("name", target_id),
		"CLEAR" if result.has_los else "BLOCKED"
	])
	
	if result.blocked_by.size() > 0:
		print("  Blocked by: ", result.blocked_by)
	if result.provides_cover.size() > 0:
		print("  Cover from: ", result.provides_cover)

func _get_unit_center(unit: Dictionary) -> Vector2:
	# Get average position of all alive models
	var positions = []
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		
		var pos = model.get("position")
		if pos == null:
			continue
		
		if pos is Dictionary:
			positions.append(Vector2(pos.get("x", 0), pos.get("y", 0)))
		elif pos is Vector2:
			positions.append(pos)
	
	if positions.is_empty():
		return Vector2.ZERO
	
	var center = Vector2.ZERO
	for pos in positions:
		center += pos
	center /= positions.size()
	
	return center

# ===== ENHANCED LINE OF SIGHT VISUALIZATION =====

# Visualize enhanced LoS checking with shape-aware sight lines and sample points
func visualize_enhanced_los(shooter_model: Dictionary, target_model: Dictionary, board: Dictionary) -> void:
	if not debug_enabled:
		return

	var result = EnhancedLineOfSight.check_enhanced_visibility(shooter_model, target_model, board)

	if result.has_los:
		# Draw successful sight line in green
		add_los_line(result.sight_line[0], result.sight_line[1], LOS_COLOR_CLEAR)

		# Draw base shapes to show sample areas
		_draw_base_outline(shooter_model, Color.GREEN)
		_draw_base_outline(target_model, Color.GREEN)

		# Show sample points that were generated
		_draw_sample_points_for_model(shooter_model, Color.CYAN)
		_draw_sample_points_for_model(target_model, Color.YELLOW)

		print("[LoSDebugVisual] Enhanced LoS: CLEAR via %s" % result.method)
	else:
		# Draw blocked attempts in red, show blocking terrain
		_draw_blocked_sight_attempts(result.attempted_lines, result.blocking_terrain)

		# Draw base shapes in red to show they're blocked
		_draw_base_outline(shooter_model, Color.RED)
		_draw_base_outline(target_model, Color.RED)

		# Show sample points that were attempted
		_draw_sample_points_for_model(shooter_model, Color(1.0, 0.5, 0.5))  # Light red
		_draw_sample_points_for_model(target_model, Color(1.0, 0.8, 0.8))   # Lighter red

		print("[LoSDebugVisual] Enhanced LoS: BLOCKED by %s" % str(result.blocking_terrain))

	queue_redraw()

# Draw shape-aware base outline to show sampling area
func _draw_base_outline(model: Dictionary, color: Color) -> void:
	var pos = _get_model_position_from_dict(model)
	if pos == Vector2.ZERO:
		return

	var rotation = model.get("rotation", 0.0)
	var shape = Measurement.create_base_shape(model)

	if shape == null:
		# Fallback to circular for missing shape data
		var radius = Measurement.base_radius_px(model.get("base_mm", 32))
		_draw_circular_base_outline(pos, radius, rotation, color)
		return

	# Draw shape-specific outline
	match shape.get_type():
		"circular":
			_draw_circular_base_outline(pos, shape.radius, rotation, color)
		"rectangular":
			_draw_rectangular_base_outline(pos, shape, rotation, color)
		"oval":
			_draw_oval_base_outline(pos, shape, rotation, color)
		_:
			# Unknown shape - fallback to circular
			var radius = Measurement.base_radius_px(model.get("base_mm", 32))
			_draw_circular_base_outline(pos, radius, rotation, color)

# Draw circular base outline
func _draw_circular_base_outline(pos: Vector2, radius: float, rotation: float, color: Color) -> void:
	var outline = Node2D.new()
	outline.position = pos
	outline.rotation = rotation
	outline.set_meta("base_color", color)
	outline.set_meta("base_radius", radius)

	var script_source = """
extends Node2D

func _ready():
	queue_redraw()

func _draw():
	var color = get_meta("base_color", Color.GREEN)
	var radius = get_meta("base_radius", 30.0)

	# Draw base circle outline
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, color, 2.0, true)

	# Draw cross at center
	var cross_size = 5.0
	draw_line(Vector2(-cross_size, 0), Vector2(cross_size, 0), color, 2.0)
	draw_line(Vector2(0, -cross_size), Vector2(0, cross_size), color, 2.0)
"""
	outline.set_script(GDScript.new())
	outline.get_script().source_code = script_source
	outline.get_script().reload()

	add_child(outline)
	_auto_remove_after_delay(outline, 3.0)

# Draw rectangular base outline
func _draw_rectangular_base_outline(pos: Vector2, shape: RectangularBase, rotation: float, color: Color) -> void:
	var outline = Node2D.new()
	outline.position = pos
	outline.rotation = rotation
	outline.set_meta("base_color", color)
	outline.set_meta("base_length", shape.length)
	outline.set_meta("base_width", shape.width)

	var script_source = """
extends Node2D

func _ready():
	queue_redraw()

func _draw():
	var color = get_meta("base_color", Color.GREEN)
	var length = get_meta("base_length", 60.0)
	var width = get_meta("base_width", 40.0)

	var half_length = length / 2
	var half_width = width / 2

	# Draw rectangle outline
	var rect_points = PackedVector2Array([
		Vector2(-half_length, -half_width),
		Vector2(half_length, -half_width),
		Vector2(half_length, half_width),
		Vector2(-half_length, half_width),
		Vector2(-half_length, -half_width)  # Close the shape
	])

	draw_polyline(rect_points, color, 2.0)

	# Draw cross at center
	var cross_size = 5.0
	draw_line(Vector2(-cross_size, 0), Vector2(cross_size, 0), color, 2.0)
	draw_line(Vector2(0, -cross_size), Vector2(0, cross_size), color, 2.0)

	# Draw orientation arrow (forward direction)
	var arrow_start = Vector2(0, -half_width - 10)
	var arrow_end = Vector2(0, -half_width - 20)
	draw_line(arrow_start, arrow_end, color, 3.0)
	draw_line(arrow_end, arrow_end + Vector2(-3, 3), color, 2.0)
	draw_line(arrow_end, arrow_end + Vector2(3, 3), color, 2.0)
"""
	outline.set_script(GDScript.new())
	outline.get_script().source_code = script_source
	outline.get_script().reload()

	add_child(outline)
	_auto_remove_after_delay(outline, 3.0)

# Draw oval base outline
func _draw_oval_base_outline(pos: Vector2, shape: OvalBase, rotation: float, color: Color) -> void:
	var outline = Node2D.new()
	outline.position = pos
	outline.rotation = rotation
	outline.set_meta("base_color", color)
	outline.set_meta("base_length", shape.length)
	outline.set_meta("base_width", shape.width)

	var script_source = """
extends Node2D

func _ready():
	queue_redraw()

func _draw():
	var color = get_meta("base_color", Color.GREEN)
	var length = get_meta("base_length", 42.5)  # Half-length
	var width = get_meta("base_width", 26.25)   # Half-width

	# Generate ellipse points
	var points = PackedVector2Array()
	var segments = 32

	for i in range(segments + 1):
		var angle = (i * TAU) / segments
		var point = Vector2(
			length * cos(angle),
			width * sin(angle)
		)
		points.append(point)

	# Draw oval outline
	draw_polyline(points, color, 2.0)

	# Draw cross at center
	var cross_size = 5.0
	draw_line(Vector2(-cross_size, 0), Vector2(cross_size, 0), color, 2.0)
	draw_line(Vector2(0, -cross_size), Vector2(0, cross_size), color, 2.0)

	# Draw major axis indicator
	draw_line(Vector2(-length, 0), Vector2(-length + 10, 0), color, 3.0)
	draw_line(Vector2(length - 10, 0), Vector2(length, 0), color, 3.0)
"""
	outline.set_script(GDScript.new())
	outline.get_script().source_code = script_source
	outline.get_script().reload()

	add_child(outline)
	_auto_remove_after_delay(outline, 3.0)

# Helper function to auto-remove nodes after delay
func _auto_remove_after_delay(node: Node, delay: float) -> void:
	get_tree().create_timer(delay).timeout.connect(func():
		if is_instance_valid(node):
			node.queue_free()
	)

# Draw sample points for a model based on its shape type
func _draw_sample_points_for_model(model: Dictionary, color: Color) -> void:
	var pos = _get_model_position_from_dict(model)
	if pos == Vector2.ZERO:
		return

	var rotation = model.get("rotation", 0.0)
	var shape = Measurement.create_base_shape(model)

	if shape == null:
		return

	# Generate sample points using the same logic as the LoS system
	var distance_to_screen_center = pos.distance_to(Vector2(960, 600))  # Approximate screen center
	var distance_inches = Measurement.px_to_inches(distance_to_screen_center)
	var dummy_shape = CircularBase.new(20.0)  # For density calculation
	var density = EnhancedLineOfSight._determine_sample_density_enhanced(distance_inches, shape, dummy_shape)

	var sample_points = EnhancedLineOfSight._generate_shape_sample_points(shape, pos, rotation, density)

	# Draw each sample point
	for point in sample_points:
		_draw_sample_point(point, color)

# Draw a single sample point with a small circle and label
func _draw_sample_point(point: Vector2, color: Color) -> void:
	var point_visual = Node2D.new()
	point_visual.position = point
	point_visual.set_meta("point_color", color)

	var script_source = """
extends Node2D

func _ready():
	queue_redraw()

func _draw():
	var color = get_meta("point_color", Color.CYAN)

	# Draw small filled circle
	draw_circle(Vector2.ZERO, 3.0, color)

	# Draw border
	draw_arc(Vector2.ZERO, 3.0, 0, TAU, 8, Color.WHITE, 1.0, true)
"""
	point_visual.set_script(GDScript.new())
	point_visual.get_script().source_code = script_source
	point_visual.get_script().reload()

	add_child(point_visual)
	_auto_remove_after_delay(point_visual, 4.0)  # Keep sample points a bit longer

# Enhanced visualization function that shows all sample points and attempted lines
func visualize_enhanced_los_detailed(shooter_model: Dictionary, target_model: Dictionary, board: Dictionary) -> void:
	if not debug_enabled:
		return

	var result = EnhancedLineOfSight.check_enhanced_visibility(shooter_model, target_model, board)

	# Always draw base outlines
	_draw_base_outline(shooter_model, Color.BLUE)
	_draw_base_outline(target_model, Color.GREEN)

	# Always draw sample points
	_draw_sample_points_for_model(shooter_model, Color.CYAN)
	_draw_sample_points_for_model(target_model, Color.YELLOW)

	# Draw all attempted lines with different colors
	if result.has("attempted_lines"):
		for line_data in result.attempted_lines:
			var line_color = LOS_COLOR_CLEAR if not line_data.blocked else Color(1.0, 0.5, 0.5, 0.3)
			add_los_line(line_data.from, line_data.to, line_color)

	# Highlight the successful line if any
	if result.has_los and result.has("sight_line") and result.sight_line.size() >= 2:
		add_los_line(result.sight_line[0], result.sight_line[1], Color.GREEN, [])  # Successful line in bright green

	# Show blocking terrain
	if result.has("blocking_terrain"):
		for terrain_id in result.blocking_terrain:
			_highlight_terrain(terrain_id, TERRAIN_BLOCKED_COLOR)

	queue_redraw()

	print("[LoSDebugVisual] Detailed Enhanced LoS: %s via %s" % [
		"CLEAR" if result.has_los else "BLOCKED",
		result.get("method", "unknown")
	])

# Draw blocked sight attempts to show why LoS failed
func _draw_blocked_sight_attempts(attempted_lines: Array, blocking_terrain: Array) -> void:
	for line_data in attempted_lines:
		if line_data.blocked:
			# Draw blocked lines in red
			add_los_line(line_data.from, line_data.to, LOS_COLOR_BLOCKED)
		else:
			# Draw clear lines in dim green
			add_los_line(line_data.from, line_data.to, Color(0.5, 1.0, 0.5, 0.5))
	
	# Highlight blocking terrain
	for terrain_id in blocking_terrain:
		_highlight_terrain(terrain_id, TERRAIN_BLOCKED_COLOR)

# Helper function to get model position from dictionary
func _get_model_position_from_dict(model: Dictionary) -> Vector2:
	var pos = model.get("position")
	if pos == null:
		return Vector2.ZERO
	if pos is Dictionary:
		return Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO

# Test enhanced LoS between specific models
func test_enhanced_los_between_models(shooter_unit_id: String, shooter_model_id: String, target_unit_id: String, target_model_id: String) -> void:
	var units = GameState.get_units()
	var shooter_unit = units.get(shooter_unit_id, {})
	var target_unit = units.get(target_unit_id, {})
	
	if shooter_unit.is_empty() or target_unit.is_empty():
		print("[LoSDebugVisual] Units not found")
		return
	
	# Find specific models
	var shooter_model = {}
	var target_model = {}
	
	for model in shooter_unit.get("models", []):
		if model.get("id", "") == shooter_model_id:
			shooter_model = model
			break
	
	for model in target_unit.get("models", []):
		if model.get("id", "") == target_model_id:
			target_model = model
			break
	
	if shooter_model.is_empty() or target_model.is_empty():
		print("[LoSDebugVisual] Models not found")
		return
	
	# Visualize enhanced LoS
	var board = GameState.create_snapshot()
	visualize_enhanced_los(shooter_model, target_model, board)
	
	print("[LoSDebugVisual] Enhanced LoS test: %s.%s → %s.%s" % [
		shooter_unit_id, shooter_model_id, target_unit_id, target_model_id
	])

# Add method to compare legacy vs enhanced LoS for debugging
func compare_legacy_vs_enhanced_los(shooter_model: Dictionary, target_model: Dictionary, board: Dictionary) -> void:
	if not debug_enabled:
		return
	
	var shooter_pos = _get_model_position_from_dict(shooter_model)
	var target_pos = _get_model_position_from_dict(target_model)
	
	# Legacy check
	var legacy_result = RulesEngine._check_legacy_line_of_sight(shooter_pos, target_pos, board)
	
	# Enhanced check
	var enhanced_result = EnhancedLineOfSight.check_enhanced_visibility(shooter_model, target_model, board)
	
	print("[LoSDebugVisual] Legacy LoS: %s | Enhanced LoS: %s" % [
		"CLEAR" if legacy_result else "BLOCKED",
		"CLEAR" if enhanced_result.has_los else "BLOCKED"
	])
	
	# Visualize both
	if legacy_result:
		add_los_line(shooter_pos, target_pos, Color.CYAN)  # Cyan for legacy clear
	else:
		add_los_line(shooter_pos, target_pos, Color.MAGENTA)  # Magenta for legacy blocked
	
	visualize_enhanced_los(shooter_model, target_model, board)
