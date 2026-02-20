extends Node2D

# PileInMovementVisual - Enhanced visual feedback for pile-in/consolidate movement
# T5-V8: Renders directional arrows to closest enemy, dashed movement paths,
# distance labels, and animated marching ants pattern.
#
# This replaces the plain Line2D direction lines with richer visuals:
# - Direction arrow: from current model pos to closest enemy (green/red based on validity)
# - Movement path: dashed animated line from original pos to current pos
# - Distance label: shows inches moved on the movement path

const FONT_SIZE: int = 13
const LABEL_BG_COLOR: Color = Color(0.1, 0.08, 0.05, 0.85)
const LABEL_BG_PADDING: Vector2 = Vector2(4, 2)

# Arrow settings
const ARROW_HEAD_SIZE: float = 14.0
const ARROW_HEAD_ANGLE: float = 0.45
const DIRECTION_LINE_WIDTH: float = 2.5
const MOVEMENT_PATH_WIDTH: float = 2.0

# Dashed line settings
const DASH_LENGTH: float = 10.0
const GAP_LENGTH: float = 6.0

# Marching ants animation
var _march_offset: float = 0.0
const MARCH_SPEED: float = 40.0  # pixels per second

# Colors
const COLOR_VALID: Color = Color(0.2, 1.0, 0.2, 0.9)       # Bright green
const COLOR_INVALID: Color = Color(1.0, 0.2, 0.2, 0.9)     # Bright red
const COLOR_MOVEMENT_PATH: Color = Color(1.0, 0.9, 0.3, 0.8)  # Yellow-gold for movement trail
const COLOR_MOVEMENT_VALID: Color = Color(0.3, 1.0, 0.5, 0.8)  # Green movement path
const COLOR_MOVEMENT_OVER: Color = Color(1.0, 0.4, 0.2, 0.8)   # Red-orange for over 3"

# Data set by FightController
var model_data: Dictionary = {}  # model_id -> { original_pos, current_pos, closest_enemy, is_valid, move_distance }

var default_font: Font = null

func _ready() -> void:
	z_index = 101  # Above pile-in visuals container
	name = "PileInMovementVisual"
	default_font = ThemeDB.fallback_font
	print("[PileInMovementVisual] Initialized")

func _process(delta: float) -> void:
	# Animate marching ants offset
	_march_offset += MARCH_SPEED * delta
	var total_segment = DASH_LENGTH + GAP_LENGTH
	if _march_offset >= total_segment:
		_march_offset -= total_segment
	queue_redraw()

func _draw() -> void:
	for model_id in model_data:
		var data = model_data[model_id]
		var original_pos: Vector2 = data.get("original_pos", Vector2.ZERO)
		var current_pos: Vector2 = data.get("current_pos", Vector2.ZERO)
		var closest_enemy: Vector2 = data.get("closest_enemy", Vector2.ZERO)
		var is_valid: bool = data.get("is_valid", false)
		var move_distance: float = data.get("move_distance", 0.0)

		# 1. Draw movement path (original -> current) if model has moved
		if original_pos.distance_to(current_pos) > 2.0:  # Minimum pixel threshold
			_draw_movement_path(original_pos, current_pos, move_distance, is_valid)

		# 2. Draw direction arrow (current -> closest enemy)
		if closest_enemy != Vector2.ZERO:
			_draw_direction_arrow(current_pos, closest_enemy, is_valid)

func _draw_direction_arrow(from: Vector2, to: Vector2, is_valid: bool) -> void:
	"""Draw an arrow from model's current position pointing toward the closest enemy"""
	var color = COLOR_VALID if is_valid else COLOR_INVALID
	var direction = (to - from).normalized()
	var distance = from.distance_to(to)

	# Don't draw if too close
	if distance < 5.0:
		return

	# Draw the main line
	draw_line(from, to, color, DIRECTION_LINE_WIDTH, true)

	# Draw arrowhead at the 'to' end
	var arrow_p1 = to - direction.rotated(ARROW_HEAD_ANGLE) * ARROW_HEAD_SIZE
	var arrow_p2 = to - direction.rotated(-ARROW_HEAD_ANGLE) * ARROW_HEAD_SIZE
	# Filled arrowhead triangle
	var arrow_points = PackedVector2Array([to, arrow_p1, arrow_p2])
	var arrow_colors = PackedColorArray([color, color, color])
	draw_polygon(arrow_points, arrow_colors)

func _draw_movement_path(from: Vector2, to: Vector2, move_distance: float, is_valid: bool) -> void:
	"""Draw an animated dashed line from original position to current position with distance label"""
	var distance_ok = move_distance <= 3.0
	var path_color: Color
	if is_valid and distance_ok:
		path_color = COLOR_MOVEMENT_VALID
	elif not distance_ok:
		path_color = COLOR_MOVEMENT_OVER
	else:
		path_color = COLOR_MOVEMENT_PATH

	# Draw dashed line with marching ants animation
	_draw_dashed_line(from, to, path_color, MOVEMENT_PATH_WIDTH)

	# Draw small circle at original position (start marker)
	draw_circle(from, 4.0, Color(path_color.r, path_color.g, path_color.b, 0.5))

	# Draw distance label
	if move_distance > 0.01:
		_draw_distance_label(from, to, move_distance, path_color, distance_ok)

func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	"""Draw a dashed line with marching ants animation between two points"""
	var direction = (to - from).normalized()
	var total_length = from.distance_to(to)
	var segment_length = DASH_LENGTH + GAP_LENGTH

	if total_length < 1.0:
		return

	# Iterate with negative offset to create marching ants animation effect
	var pos = -_march_offset
	while pos < total_length:
		var dash_start = max(pos, 0.0)
		var dash_end = min(pos + DASH_LENGTH, total_length)

		if dash_start < dash_end:
			var p1 = from + direction * dash_start
			var p2 = from + direction * dash_end
			draw_line(p1, p2, color, width, true)

		pos += segment_length

func _draw_distance_label(from: Vector2, to: Vector2, distance_inches: float, color: Color, distance_ok: bool) -> void:
	"""Draw a distance label at the midpoint of the movement path"""
	if not default_font:
		return

	var midpoint = (from + to) / 2.0
	var label_text = "%.1f\"" % distance_inches

	# Position label perpendicular to the movement line
	var direction = (to - from).normalized()
	var perpendicular = Vector2(-direction.y, direction.x)
	var label_pos = midpoint + perpendicular * 16.0

	# Get text dimensions
	var text_size = default_font.get_string_size(
		label_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE
	)

	# Draw background rectangle
	var bg_rect = Rect2(
		label_pos - LABEL_BG_PADDING,
		text_size + LABEL_BG_PADDING * 2
	)
	draw_rect(bg_rect, LABEL_BG_COLOR, true)

	# Draw a thin border matching the color
	var border_color = Color(color.r, color.g, color.b, 0.6)
	draw_rect(bg_rect, border_color, false, 1.0)

	# Text color: use green or red based on distance validity
	var text_color = color
	if not distance_ok:
		text_color = COLOR_MOVEMENT_OVER

	# Draw the text
	draw_string(
		default_font,
		label_pos + Vector2(0, text_size.y * 0.7),
		label_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE,
		text_color
	)

func update_model(model_id: String, original_pos: Vector2, current_pos: Vector2, closest_enemy: Vector2, is_valid: bool, move_distance: float) -> void:
	"""Update data for a single model. Called by FightController."""
	model_data[model_id] = {
		"original_pos": original_pos,
		"current_pos": current_pos,
		"closest_enemy": closest_enemy,
		"is_valid": is_valid,
		"move_distance": move_distance
	}

func clear_model(model_id: String) -> void:
	"""Remove a model's visual data"""
	model_data.erase(model_id)

func clear_all() -> void:
	"""Clear all model data"""
	model_data.clear()
