extends Node2D
class_name HumanMovementPathVisual

# HumanMovementPathVisual - Shows movement path previews during human movement planning
# P3-125: Draws dashed lines with arrowheads from each model's origin to its
# staged/current destination during drag-to-plan movement. Matches the visual
# style of AIMovementPathVisual.gd. Supports two modes:
#   1. "planning" mode: Live preview during drag-to-plan (persistent, no fade)
#   2. "confirmed" mode: Brief hold + fade after unit move confirmed (like AI)

# Animation timing (confirmed mode only)
const HOLD_DURATION := 1.5  # How long to hold the trail visible after confirm
const FADE_DURATION := 0.8  # Fade out time

# Visual settings - matches AIMovementPathVisual colors
const P1_TRAIL_COLOR := Color(0.3, 0.5, 0.9, 0.7)  # Blue for player 1
const P2_TRAIL_COLOR := Color(0.9, 0.3, 0.2, 0.7)  # Red for player 2
const TRAIL_GLOW_COLOR_ALPHA := 0.2  # Glow layer alpha multiplier
const LINE_WIDTH := 2.5
const GLOW_WIDTH := 7.0
const DASH_LENGTH := 8.0
const GAP_LENGTH := 5.0

# Arrowhead settings
const ARROW_HEAD_SIZE := 10.0
const ARROW_HEAD_ANGLE := 0.45  # Radians

# Origin marker settings
const ORIGIN_MARKER_RADIUS := 4.0

# Distance label settings
const LABEL_FONT_SIZE := 13
const LABEL_BG_COLOR := Color(0.1, 0.08, 0.05, 0.85)
const LABEL_BG_PADDING := Vector2(4, 2)

# Marching ants animation (planning mode)
var _march_offset: float = 0.0
const MARCH_SPEED := 30.0  # pixels per second

# State
var _paths: Array = []  # Array of {from: Vector2, to: Vector2, distance: float}
var _owner_player: int = 1
var _move_cap_inches: float = 0.0  # For distance label coloring
var _phase := "idle"  # idle, planning, confirmed_hold, confirmed_fade
var _fade_alpha := 1.0
var _fade_tween: Tween = null
var _hold_timer: Timer = null

var default_font: Font = null

signal animation_finished()

func _ready() -> void:
	z_index = 11  # Between tokens (10) and shooting lines (12)
	_hold_timer = Timer.new()
	_hold_timer.one_shot = true
	_hold_timer.timeout.connect(_start_fade_out)
	add_child(_hold_timer)
	default_font = ThemeDB.fallback_font

func _process(delta: float) -> void:
	if _phase == "idle":
		return
	if _phase == "planning":
		# Animate marching ants for planning mode
		_march_offset += MARCH_SPEED * delta
		var total_segment = DASH_LENGTH + GAP_LENGTH
		if _march_offset >= total_segment:
			_march_offset -= total_segment
		queue_redraw()
	elif _phase == "confirmed_fade":
		queue_redraw()

func _draw() -> void:
	if _phase == "idle":
		return
	if _paths.is_empty():
		return

	var alpha = _fade_alpha
	var base_color = P1_TRAIL_COLOR if _owner_player == 1 else P2_TRAIL_COLOR

	for path in _paths:
		var from_pos: Vector2 = path["from"]
		var to_pos: Vector2 = path["to"]
		var direction = to_pos - from_pos

		if direction.length_squared() < 1.0:
			continue

		var dir_norm = direction.normalized()

		# Glow line (solid, wide, low alpha)
		var glow_color = Color(base_color.r, base_color.g, base_color.b, alpha * TRAIL_GLOW_COLOR_ALPHA)
		draw_line(from_pos, to_pos, glow_color, GLOW_WIDTH)

		# Dashed core line (animated in planning mode)
		var trail_color = Color(base_color.r, base_color.g, base_color.b, alpha * base_color.a)
		if _phase == "planning":
			_draw_dashed_line_animated(from_pos, to_pos, trail_color, LINE_WIDTH)
		else:
			_draw_dashed_line(from_pos, to_pos, trail_color, LINE_WIDTH)

		# Arrowhead at destination
		_draw_arrowhead(to_pos, dir_norm, trail_color)

		# Small circle at origin
		var origin_color = Color(base_color.r, base_color.g, base_color.b, alpha * 0.5)
		draw_circle(from_pos, ORIGIN_MARKER_RADIUS, origin_color)

		# Distance label (planning mode only)
		if _phase == "planning" and path.has("distance"):
			var distance: float = path["distance"]
			if distance > 0.01:
				_draw_distance_label(from_pos, to_pos, distance, base_color, alpha)

func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var direction = to - from
	var total_length = direction.length()
	var dir_norm = direction.normalized()

	var segment_length = DASH_LENGTH + GAP_LENGTH
	var pos = 0.0

	while pos < total_length:
		var dash_end = minf(pos + DASH_LENGTH, total_length)
		var start_point = from + dir_norm * pos
		var end_point = from + dir_norm * dash_end
		draw_line(start_point, end_point, color, width)
		pos += segment_length

func _draw_dashed_line_animated(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	"""Draw a dashed line with marching ants animation between two points"""
	var direction = (to - from).normalized()
	var total_length = from.distance_to(to)
	var segment_length = DASH_LENGTH + GAP_LENGTH

	if total_length < 1.0:
		return

	var pos = -_march_offset
	while pos < total_length:
		var dash_start = max(pos, 0.0)
		var dash_end = min(pos + DASH_LENGTH, total_length)

		if dash_start < dash_end:
			var p1 = from + direction * dash_start
			var p2 = from + direction * dash_end
			draw_line(p1, p2, color, width, true)

		pos += segment_length

func _draw_arrowhead(tip: Vector2, direction: Vector2, color: Color) -> void:
	var p1 = tip - direction.rotated(ARROW_HEAD_ANGLE) * ARROW_HEAD_SIZE
	var p2 = tip - direction.rotated(-ARROW_HEAD_ANGLE) * ARROW_HEAD_SIZE
	var points = PackedVector2Array([tip, p1, p2])
	var colors = PackedColorArray([color, color, color])
	draw_polygon(points, colors)

func _draw_distance_label(from: Vector2, to: Vector2, distance_inches: float, base_color: Color, alpha: float) -> void:
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
		LABEL_FONT_SIZE
	)

	# Draw background rectangle
	var bg_rect = Rect2(
		label_pos - LABEL_BG_PADDING,
		text_size + LABEL_BG_PADDING * 2
	)
	draw_rect(bg_rect, Color(LABEL_BG_COLOR.r, LABEL_BG_COLOR.g, LABEL_BG_COLOR.b, LABEL_BG_COLOR.a * alpha), true)

	# Border and text color based on distance vs cap
	var text_color: Color
	if _move_cap_inches > 0 and distance_inches > _move_cap_inches:
		text_color = Color(1.0, 0.4, 0.2, alpha)  # Red-orange for over cap
	else:
		text_color = Color(base_color.r, base_color.g, base_color.b, alpha)

	var border_color = Color(text_color.r, text_color.g, text_color.b, 0.6 * alpha)
	draw_rect(bg_rect, border_color, false, 1.0)

	draw_string(
		default_font,
		label_pos + Vector2(0, text_size.y * 0.7),
		label_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		LABEL_FONT_SIZE,
		text_color
	)

# --- Public API ---

func update_planning_paths(paths: Array, owner_player: int, move_cap: float = 0.0) -> void:
	"""Update movement path previews during drag-to-plan.
	Each path is {from: Vector2, to: Vector2, distance: float (optional)}."""
	_paths = paths
	_owner_player = owner_player
	_move_cap_inches = move_cap

	if paths.is_empty():
		_phase = "idle"
		visible = false
	else:
		_phase = "planning"
		_fade_alpha = 1.0
		visible = true

	queue_redraw()

func show_confirmed_paths(paths: Array, owner_player: int) -> void:
	"""Show movement trails after unit move confirmed (hold + fade like AI).
	Each path is {from: Vector2, to: Vector2}."""
	_paths = paths
	_owner_player = owner_player

	_phase = "confirmed_hold"
	_fade_alpha = 1.0

	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_hold_timer.stop()
	_hold_timer.start(HOLD_DURATION)

	visible = true
	queue_redraw()
	print("[HumanMovementPathVisual] P3-125: Showing %d confirmed movement trails for player %d" % [paths.size(), owner_player])

func clear_now() -> void:
	"""Immediately clear the visual without fading."""
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_hold_timer.stop()
	_phase = "idle"
	_paths.clear()
	_fade_alpha = 1.0
	visible = false
	queue_redraw()

func _start_fade_out() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_phase = "confirmed_fade"
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "_fade_alpha", 0.0, FADE_DURATION).set_ease(Tween.EASE_IN)
	_fade_tween.tween_callback(_on_fade_complete)

func _on_fade_complete() -> void:
	_phase = "idle"
	visible = false
	_paths.clear()
	animation_finished.emit()
	queue_free()
