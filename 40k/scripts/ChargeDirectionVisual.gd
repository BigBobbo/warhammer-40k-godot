extends Node2D

# ChargeDirectionVisual - Live direction validation feedback during charge movement
# P3-99: Renders visual indicators showing whether the model is ending closer to
# at least one charge target (satisfying the direction constraint).
#
# Shows:
# - Arrow from drag position to the closest charge target (green=closer, red=farther)
# - Distance delta label showing how much closer/farther the model is
# - Small status text near the model

const FONT_SIZE: int = 12
const LABEL_BG_COLOR: Color = Color(0.1, 0.08, 0.05, 0.85)
const LABEL_BG_PADDING: Vector2 = Vector2(4, 2)

# Arrow settings
const ARROW_HEAD_SIZE: float = 12.0
const ARROW_HEAD_ANGLE: float = 0.45
const DIRECTION_LINE_WIDTH: float = 2.5
const ARROW_MAX_LENGTH: float = 120.0  # Max arrow length in pixels (visual only)

# Colors
const COLOR_CLOSER: Color = Color(0.2, 1.0, 0.2, 0.7)        # Green - moving closer
const COLOR_FARTHER: Color = Color(1.0, 0.3, 0.2, 0.7)       # Red - moving farther
const COLOR_NEUTRAL: Color = Color(1.0, 1.0, 0.4, 0.5)       # Yellow - same distance
const COLOR_STATUS_BG: Color = Color(0.05, 0.05, 0.05, 0.8)

# State
var _drag_pos: Vector2 = Vector2.ZERO
var _original_pos: Vector2 = Vector2.ZERO
var _closest_target_pos: Vector2 = Vector2.ZERO
var _is_closer: bool = false
var _distance_delta: float = 0.0  # Negative = closer, positive = farther (in inches)
var _active: bool = false

var default_font: Font = null

func _ready() -> void:
	z_index = 102  # Above other movement visuals
	name = "ChargeDirectionVisual"
	default_font = FactionPalettes.FONT_RAJDHANI_SEMIBOLD
	visible = false
	print("[ChargeDirectionVisual] P3-99: Initialized")

func _draw() -> void:
	if not _active:
		return

	if _closest_target_pos == Vector2.ZERO:
		return

	# Draw direction arrow from drag position toward closest target
	_draw_direction_arrow(_drag_pos, _closest_target_pos, _is_closer)

	# Draw status indicator near the drag position
	_draw_status_label(_drag_pos, _is_closer, _distance_delta)

func _draw_direction_arrow(from: Vector2, to: Vector2, is_closer: bool) -> void:
	var color = COLOR_CLOSER if is_closer else COLOR_FARTHER
	var direction = (to - from).normalized()
	var distance = from.distance_to(to)

	if distance < 5.0:
		return

	# Clamp arrow length for visual clarity
	var arrow_end: Vector2
	if distance > ARROW_MAX_LENGTH:
		arrow_end = from + direction * ARROW_MAX_LENGTH
	else:
		arrow_end = to

	# Draw the main line (dashed for visual distinction from movement line)
	_draw_dashed_direction_line(from, arrow_end, color)

	# Draw arrowhead
	var arrow_dir = (arrow_end - from).normalized()
	var arrow_p1 = arrow_end - arrow_dir.rotated(ARROW_HEAD_ANGLE) * ARROW_HEAD_SIZE
	var arrow_p2 = arrow_end - arrow_dir.rotated(-ARROW_HEAD_ANGLE) * ARROW_HEAD_SIZE
	var arrow_points = PackedVector2Array([arrow_end, arrow_p1, arrow_p2])
	var arrow_colors = PackedColorArray([color, color, color])
	draw_polygon(arrow_points, arrow_colors)

func _draw_dashed_direction_line(from: Vector2, to: Vector2, color: Color) -> void:
	var direction = (to - from).normalized()
	var total_length = from.distance_to(to)
	var dash_length = 8.0
	var gap_length = 5.0

	if total_length < 1.0:
		return

	var pos = 0.0
	while pos < total_length:
		var dash_start = pos
		var dash_end = min(pos + dash_length, total_length)

		if dash_start < dash_end:
			var p1 = from + direction * dash_start
			var p2 = from + direction * dash_end
			draw_line(p1, p2, color, DIRECTION_LINE_WIDTH, true)

		pos += dash_length + gap_length

func _draw_status_label(drag_pos: Vector2, is_closer: bool, delta_inches: float) -> void:
	if not default_font:
		return

	# Position label offset from drag position (below and to the right)
	var label_pos = drag_pos + Vector2(20, -30)

	var label_text: String
	var text_color: Color
	if is_closer:
		label_text = "Closer (%.1f\")" % abs(delta_inches)
		text_color = COLOR_CLOSER
	elif abs(delta_inches) < 0.05:
		label_text = "Same distance"
		text_color = COLOR_NEUTRAL
	else:
		label_text = "Farther (+%.1f\")" % abs(delta_inches)
		text_color = COLOR_FARTHER

	var text_size = default_font.get_string_size(
		label_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE
	)

	# Draw background
	var bg_rect = Rect2(
		label_pos - LABEL_BG_PADDING,
		text_size + LABEL_BG_PADDING * 2
	)
	draw_rect(bg_rect, COLOR_STATUS_BG, true)

	# Draw border
	var border_color = Color(text_color.r, text_color.g, text_color.b, 0.6)
	draw_rect(bg_rect, border_color, false, 1.0)

	# Draw text
	draw_string(
		default_font,
		label_pos + Vector2(0, text_size.y * 0.7),
		label_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE,
		text_color
	)

## Update the visual with new drag data.
## Called by ChargeController during _update_model_drag.
func update_direction(drag_pos: Vector2, original_pos: Vector2, charge_targets: Array) -> void:
	_drag_pos = drag_pos
	_original_pos = original_pos
	_active = true
	visible = true

	# Find the closest charge target model that the model is closest to
	# AND determine if the direction constraint is satisfied
	var best_delta: float = INF  # Best (most negative = closest approach)
	var best_target_pos: Vector2 = Vector2.ZERO
	var satisfies_constraint: bool = false

	for target_id in charge_targets:
		var target_unit = GameState.get_unit(target_id)
		if target_unit.is_empty():
			continue
		for target_model in target_unit.get("models", []):
			if not target_model.get("alive", true):
				continue
			var target_pos = _get_model_position(target_model)
			if target_pos == null or target_pos == Vector2.ZERO:
				continue

			var original_dist = original_pos.distance_to(target_pos)
			var current_dist = drag_pos.distance_to(target_pos)
			var delta = current_dist - original_dist  # Negative = closer

			if delta < 0:
				satisfies_constraint = true

			# Track the target with the best (most negative) delta
			if delta < best_delta:
				best_delta = delta
				best_target_pos = target_pos

	_closest_target_pos = best_target_pos
	_is_closer = satisfies_constraint
	_distance_delta = Measurement.px_to_inches(best_delta) if best_delta != INF else 0.0

	queue_redraw()

## Deactivate the visual (hide and stop drawing).
func deactivate() -> void:
	_active = false
	visible = false
	_closest_target_pos = Vector2.ZERO
	queue_redraw()

func _get_model_position(model: Dictionary) -> Vector2:
	var pos = model.get("position")
	if pos == null:
		return Vector2.ZERO
	if pos is Dictionary:
		return Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO
