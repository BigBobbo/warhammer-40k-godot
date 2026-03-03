extends Node2D
class_name ChargeTrajectoryPreview

# ChargeTrajectoryPreview - Shows expected charge paths when declaring charges
# P3-127: Draws dashed trajectory lines from each model in the charging unit
# to the closest enemy model in the target unit(s), with distance labels and
# a minimum charge roll indicator. Appears during target selection, before
# the charge is declared.
#
# Visual style follows HumanMovementPathVisual (dashed lines, arrowheads)
# but uses the charge-themed orange color from ChargeArrowVisual.

# Visual settings - orange charge theme (matches ChargeArrowVisual)
const TRAJECTORY_COLOR := Color(1.0, 0.6, 0.0, 0.6)  # Orange, semi-transparent
const TRAJECTORY_GLOW_ALPHA := 0.15  # Glow layer alpha multiplier
const LINE_WIDTH := 2.0
const GLOW_WIDTH := 6.0
const DASH_LENGTH := 8.0
const GAP_LENGTH := 5.0

# Arrowhead settings
const ARROW_HEAD_SIZE := 9.0
const ARROW_HEAD_ANGLE := 0.45  # Radians

# Origin marker
const ORIGIN_MARKER_RADIUS := 3.5

# Marching ants animation
var _march_offset: float = 0.0
const MARCH_SPEED := 25.0  # pixels per second

# Minimum roll summary label
const SUMMARY_FONT_SIZE := 14
const SUMMARY_BG_COLOR := Color(0.1, 0.08, 0.05, 0.9)
const SUMMARY_BG_PADDING := Vector2(6, 4)
const SUMMARY_GOOD_COLOR := Color(0.3, 1.0, 0.4, 0.95)  # Green - easy charge
const SUMMARY_MID_COLOR := Color(1.0, 0.85, 0.3, 0.95)   # Yellow - average
const SUMMARY_HARD_COLOR := Color(1.0, 0.4, 0.2, 0.95)   # Red-orange - hard

# Per-model distance label
const LABEL_FONT_SIZE := 11
const LABEL_BG_COLOR := Color(0.1, 0.08, 0.05, 0.8)
const LABEL_BG_PADDING := Vector2(3, 2)

# State
var _trajectories: Array = []  # Array of {from: Vector2, to: Vector2, distance_inches: float}
var _min_charge_needed: float = 0.0  # Minimum inches needed to reach engagement
var _charger_center: Vector2 = Vector2.ZERO  # For summary label positioning
var _active: bool = false

var default_font: Font = null

func _ready() -> void:
	z_index = 11  # Same layer as movement trails (between tokens=10 and arrows=12)
	name = "ChargeTrajectoryPreview"
	default_font = FactionPalettes.FONT_RAJDHANI_SEMIBOLD
	visible = false
	print("[ChargeTrajectoryPreview] P3-127: Initialized")

func _process(delta: float) -> void:
	if not _active:
		return
	# Animate marching ants
	_march_offset += MARCH_SPEED * delta
	var total_segment = DASH_LENGTH + GAP_LENGTH
	if _march_offset >= total_segment:
		_march_offset -= total_segment
	queue_redraw()

func _draw() -> void:
	if not _active or _trajectories.is_empty():
		return

	for traj in _trajectories:
		var from_pos: Vector2 = traj["from"]
		var to_pos: Vector2 = traj["to"]
		var direction = to_pos - from_pos

		if direction.length_squared() < 1.0:
			continue

		var dir_norm = direction.normalized()

		# Glow line (solid, wide, low alpha)
		var glow_color = Color(TRAJECTORY_COLOR.r, TRAJECTORY_COLOR.g, TRAJECTORY_COLOR.b, TRAJECTORY_GLOW_ALPHA)
		draw_line(from_pos, to_pos, glow_color, GLOW_WIDTH)

		# Dashed core line with marching ants
		var trail_color = Color(TRAJECTORY_COLOR.r, TRAJECTORY_COLOR.g, TRAJECTORY_COLOR.b, TRAJECTORY_COLOR.a)
		_draw_dashed_line_animated(from_pos, to_pos, trail_color, LINE_WIDTH)

		# Arrowhead at destination
		_draw_arrowhead(to_pos, dir_norm, trail_color)

		# Origin marker circle
		var origin_color = Color(TRAJECTORY_COLOR.r, TRAJECTORY_COLOR.g, TRAJECTORY_COLOR.b, 0.4)
		draw_circle(from_pos, ORIGIN_MARKER_RADIUS, origin_color)

		# Per-model distance label
		var dist_inches: float = traj.get("distance_inches", 0.0)
		if dist_inches > 0.01:
			_draw_distance_label(from_pos, to_pos, dist_inches)

	# Draw minimum charge roll summary near the charger center
	if _min_charge_needed > 0 and _charger_center != Vector2.ZERO:
		_draw_min_roll_summary()

func _draw_dashed_line_animated(from: Vector2, to: Vector2, color: Color, width: float) -> void:
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

func _draw_distance_label(from: Vector2, to: Vector2, distance_inches: float) -> void:
	if not default_font:
		return

	var midpoint = (from + to) / 2.0
	var label_text = "%.1f\"" % distance_inches

	# Position label perpendicular to the trajectory line
	var direction = (to - from).normalized()
	var perpendicular = Vector2(-direction.y, direction.x)
	var label_pos = midpoint + perpendicular * 14.0

	var text_size = default_font.get_string_size(
		label_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		LABEL_FONT_SIZE
	)

	# Background rectangle
	var bg_rect = Rect2(
		label_pos - LABEL_BG_PADDING,
		text_size + LABEL_BG_PADDING * 2
	)
	draw_rect(bg_rect, LABEL_BG_COLOR, true)

	# Border
	var border_color = Color(TRAJECTORY_COLOR.r, TRAJECTORY_COLOR.g, TRAJECTORY_COLOR.b, 0.5)
	draw_rect(bg_rect, border_color, false, 1.0)

	# Text in orange charge color
	var text_color = Color(TRAJECTORY_COLOR.r, TRAJECTORY_COLOR.g, TRAJECTORY_COLOR.b, 0.9)
	draw_string(
		default_font,
		label_pos + Vector2(0, text_size.y * 0.7),
		label_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		LABEL_FONT_SIZE,
		text_color
	)

func _draw_min_roll_summary() -> void:
	if not default_font:
		return

	# Position summary label above the charger unit center
	var label_pos = _charger_center + Vector2(-40, -50)

	var roll_needed = ceili(_min_charge_needed)
	var label_text: String
	if _min_charge_needed <= 1.0:
		label_text = "Min roll: 2 (auto)"
		roll_needed = 2
	else:
		label_text = "Min roll: %d  (%.1f\")" % [roll_needed, _min_charge_needed]

	var text_size = default_font.get_string_size(
		label_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		SUMMARY_FONT_SIZE
	)

	# Background
	var bg_rect = Rect2(
		label_pos - SUMMARY_BG_PADDING,
		text_size + SUMMARY_BG_PADDING * 2
	)
	draw_rect(bg_rect, SUMMARY_BG_COLOR, true)

	# Color-code based on difficulty (2D6 averages 7)
	var text_color: Color
	if roll_needed <= 5:
		text_color = SUMMARY_GOOD_COLOR
	elif roll_needed <= 8:
		text_color = SUMMARY_MID_COLOR
	else:
		text_color = SUMMARY_HARD_COLOR

	# Border matches difficulty color
	var border_color = Color(text_color.r, text_color.g, text_color.b, 0.6)
	draw_rect(bg_rect, border_color, false, 1.5)

	draw_string(
		default_font,
		label_pos + Vector2(0, text_size.y * 0.7),
		label_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		SUMMARY_FONT_SIZE,
		text_color
	)

# --- Public API ---

func update_trajectories(trajectories: Array, min_charge_inches: float, charger_center: Vector2) -> void:
	"""Update the charge trajectory preview.
	Each trajectory is {from: Vector2, to: Vector2, distance_inches: float}.
	min_charge_inches is the minimum distance needed to reach engagement range.
	charger_center is the center of the charging unit (for summary label positioning)."""
	_trajectories = trajectories
	_min_charge_needed = min_charge_inches
	_charger_center = charger_center

	if trajectories.is_empty():
		_active = false
		visible = false
	else:
		_active = true
		visible = true

	queue_redraw()

func clear_now() -> void:
	"""Immediately clear the preview."""
	_active = false
	_trajectories.clear()
	_min_charge_needed = 0.0
	_charger_center = Vector2.ZERO
	visible = false
	queue_redraw()
