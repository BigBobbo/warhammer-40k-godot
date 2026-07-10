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

# Visual settings — charge theme draws from the UIConstants slot table
# (T12). The initializers below are canonical-hex fallbacks for headless -s
# contexts where the autoload is absent (bare autoload names don't compile
# there); _ready() re-resolves them from /root/UIConstants. Keep in sync
# with doc §9.
var trajectory_color: Color = Color(1.0, 0.55, 0.0, 0.6)  # == with_alpha(UIConstants.WARNING_ORANGE, 0.6)
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

# Minimum roll summary label (colors slot-sourced in _ready, see above)
const SUMMARY_FONT_SIZE := 14
var summary_bg_color: Color = Color(0.1, 0.08, 0.05, 0.9)    # == UIConstants.LABEL_BG_DARK
const SUMMARY_BG_PADDING := Vector2(6, 4)
var summary_good_color: Color = Color(0.2, 0.85, 0.3, 0.95)  # == with_alpha(UIConstants.CONFIRMED_GREEN, 0.95)
var summary_mid_color: Color = Color(0.95, 0.85, 0.15, 0.95) # == with_alpha(UIConstants.MARGINAL_YELLOW, 0.95)
var summary_hard_color: Color = Color(0.9, 0.2, 0.2, 0.95)   # == with_alpha(UIConstants.INVALID_RED, 0.95)

# Per-model distance label
const LABEL_FONT_SIZE := 11
var label_bg_color: Color = Color(0.1, 0.08, 0.05, 0.8)      # == with_alpha(UIConstants.LABEL_BG_DARK, 0.8)
const LABEL_BG_PADDING := Vector2(3, 2)

# T12: local alpha-override helper (autoload-free so headless -s harnesses
# can still compile this script; Color is by-value so mutating is safe).
static func _alpha(c: Color, a: float) -> Color:
	c.a = a
	return c

# State
var _trajectories: Array = []  # Array of {from: Vector2, to: Vector2, distance_inches: float}
var _min_charge_needed: float = 0.0  # Minimum inches needed to reach engagement
var _charger_center: Vector2 = Vector2.ZERO  # For summary label positioning
var _active: bool = false

# T30: dashed/solid charge rings exposed for scenarios.
# Schema: [{radius_px: float, label: String, style: String}]
# label is "max" / "expected" / "rolled"
# style is "dashed" / "solid"
var rings: Array = []
const T30_MAX_CHARGE_INCHES := 12.0
const T30_EXPECTED_CHARGE_INCHES := 7.0


# T30: switch to declaration state — two dashed rings (max + expected).
func t30_declare_charge_rings() -> void:
	var px_per_inch: float = float(Measurement.PX_PER_INCH)
	rings = [
		{
			"radius_px": T30_MAX_CHARGE_INCHES * px_per_inch,
			"label": "max",
			"style": "dashed",
		},
		{
			"radius_px": T30_EXPECTED_CHARGE_INCHES * px_per_inch,
			"label": "expected",
			"style": "dashed",
		},
	]


# T30: switch to rolled state — single solid ring at the rolled distance.
func t30_set_rolled_ring(rolled_inches: float) -> void:
	var px_per_inch: float = float(Measurement.PX_PER_INCH)
	rings = [
		{
			"radius_px": rolled_inches * px_per_inch,
			"label": "rolled",
			"style": "solid",
		},
	]


func t30_clear_rings() -> void:
	rings = []


var default_font: Font = null

func _ready() -> void:
	z_index = 11  # Same layer as movement trails (between tokens=10 and arrows=12)
	name = "ChargeTrajectoryPreview"
	default_font = FactionPalettes.FONT_RAJDHANI_SEMIBOLD
	visible = false
	# T12: re-resolve theme colors from the UIConstants slot table now that
	# the node is in the tree (fallback initializers cover headless -s runs).
	var uic = get_node_or_null("/root/UIConstants")
	if uic != null:
		trajectory_color = _alpha(uic.WARNING_ORANGE, 0.6)
		summary_bg_color = uic.LABEL_BG_DARK
		summary_good_color = _alpha(uic.CONFIRMED_GREEN, 0.95)
		summary_mid_color = _alpha(uic.MARGINAL_YELLOW, 0.95)
		summary_hard_color = _alpha(uic.INVALID_RED, 0.95)
		label_bg_color = _alpha(uic.LABEL_BG_DARK, 0.8)
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
		var glow_color = _alpha(trajectory_color, TRAJECTORY_GLOW_ALPHA)
		draw_line(from_pos, to_pos, glow_color, GLOW_WIDTH)

		# Dashed core line with marching ants
		var trail_color = trajectory_color
		_draw_dashed_line_animated(from_pos, to_pos, trail_color, LINE_WIDTH)

		# Arrowhead at destination
		_draw_arrowhead(to_pos, dir_norm, trail_color)

		# Origin marker circle
		var origin_color = _alpha(trajectory_color, 0.4)
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
	draw_rect(bg_rect, label_bg_color, true)

	# Border
	var border_color = _alpha(trajectory_color, 0.5)
	draw_rect(bg_rect, border_color, false, 1.0)

	# Text in orange charge color
	var text_color = _alpha(trajectory_color, 0.9)
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
	draw_rect(bg_rect, summary_bg_color, true)

	# Color-code based on difficulty (2D6 averages 7)
	var text_color: Color
	if roll_needed <= 5:
		text_color = summary_good_color
	elif roll_needed <= 8:
		text_color = summary_mid_color
	else:
		text_color = summary_hard_color

	# Border matches difficulty color
	var border_color = _alpha(text_color, 0.6)
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
