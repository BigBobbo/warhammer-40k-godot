extends Node2D
class_name ChargeArrowVisual

# ChargeArrowVisual - Animated charge declaration arrow with roll result display
# T7-58: Draws an animated arrow (orange/yellow) from charger to target,
# shows charge roll result prominently. Follows ShootingLineVisual animation
# pattern and PileInMovementVisual arrow head drawing.

# Animation timing
const LINE_DRAW_DURATION := 0.3  # Time for arrow to extend from charger to target
const HOLD_DURATION := 4.0  # How long to hold the arrow visible after animation
const FADE_DURATION := 1.0  # Fade out time
const PULSE_SPEED := 3.0  # Speed of the pulsing glow effect

# Visual settings — charge theme draws from the UIConstants slot table
# (T12): orange = WARNING_ORANGE (charge attempt), green = CONFIRMED_GREEN
# (success), red = INVALID_RED (failure). Initializers are canonical-hex
# fallbacks for headless -s contexts where the autoload is absent (bare
# autoload names don't compile there); _ready() re-resolves them.
var arrow_color: Color = Color(1.0, 0.55, 0.0, 0.9)         # == with_alpha(UIConstants.WARNING_ORANGE, 0.9)
var arrow_success_color: Color = Color(0.2, 0.85, 0.3, 0.9) # == with_alpha(UIConstants.CONFIRMED_GREEN, 0.9)
var arrow_fail_color: Color = Color(0.9, 0.2, 0.2, 0.9)     # == with_alpha(UIConstants.INVALID_RED, 0.9)
var pending_text_color: Color = Color(0.95, 0.85, 0.15, 1.0) # == UIConstants.MARGINAL_YELLOW (roll pending)
const LINE_WIDTH := 3.5
const GLOW_WIDTH := 10.0

# Arrowhead settings
const ARROW_HEAD_SIZE := 16.0
const ARROW_HEAD_ANGLE := 0.45  # Radians, matches PileInMovementVisual

# Charge flash at charger origin — celebratory FX, not a semantic slot
# (documented T12 exception; the warm flash pair is art, not state color).
const CHARGE_FLASH_COLOR := Color(1.0, 0.7, 0.1, 0.9)
const CHARGE_FLASH_CORE_COLOR := Color(1.0, 0.95, 0.7, 1.0)
const CHARGE_FLASH_RADIUS := 16.0

# Roll result label
const LABEL_FONT_SIZE := 16
var label_bg_color: Color = Color(0.1, 0.08, 0.05, 0.9)     # == UIConstants.LABEL_BG_DARK
const LABEL_BG_PADDING := Vector2(6, 4)

# T12: local alpha-override helper (autoload-free so headless -s harnesses
# can still compile this script; Color is by-value so mutating is safe).
static func _alpha(c: Color, a: float) -> Color:
	c.a = a
	return c

# State
var from_pos := Vector2.ZERO  # Charger unit position (world coords)
var to_pos := Vector2.ZERO  # Target unit position (world coords)
var charge_roll_total: int = -1  # -1 means no roll yet
var charge_success: bool = false  # Whether charge succeeded
var _has_result: bool = false  # Whether charge result has been set

var _phase := "idle"  # idle, line_draw, hold, fade
var _elapsed := 0.0
var _line_progress := 0.0  # 0..1 how much of arrow is drawn
var _charge_flash_alpha := 0.0
var _fade_alpha := 1.0
var _fade_tween: Tween = null
var _hold_timer: Timer = null
var _pulse_time := 0.0  # For pulsing glow animation

signal animation_finished()

func _ready() -> void:
	z_index = 12  # Above tokens (10), same layer as shooting lines
	_hold_timer = Timer.new()
	_hold_timer.one_shot = true
	_hold_timer.timeout.connect(_start_fade_out)
	add_child(_hold_timer)
	# T12: re-resolve theme colors from the UIConstants slot table now that
	# the node is in the tree (fallback initializers cover headless -s runs).
	var uic = get_node_or_null("/root/UIConstants")
	if uic != null:
		arrow_color = _alpha(uic.WARNING_ORANGE, 0.9)
		arrow_success_color = _alpha(uic.CONFIRMED_GREEN, 0.9)
		arrow_fail_color = _alpha(uic.INVALID_RED, 0.9)
		pending_text_color = uic.MARGINAL_YELLOW
		label_bg_color = uic.LABEL_BG_DARK

func _process(delta: float) -> void:
	if _phase == "idle":
		return

	if _phase == "hold" or _phase == "fade":
		_pulse_time += delta
		queue_redraw()
		return

	_elapsed += delta

	if _phase == "line_draw":
		_line_progress = clampf(_elapsed / LINE_DRAW_DURATION, 0.0, 1.0)
		# Charge flash peaks at start and fades during line draw
		_charge_flash_alpha = clampf(1.0 - (_elapsed / (LINE_DRAW_DURATION * 0.6)), 0.0, 1.0)

		if _line_progress >= 1.0:
			_phase = "hold"
			_line_progress = 1.0
			_hold_timer.start(HOLD_DURATION)

	queue_redraw()

func _draw() -> void:
	if _phase == "idle":
		return
	if from_pos == Vector2.ZERO or to_pos == Vector2.ZERO:
		return

	var alpha = _fade_alpha
	var direction = (to_pos - from_pos)
	var dir_norm = direction.normalized()

	# Determine color based on charge result
	var base_color = arrow_color
	if _has_result:
		base_color = arrow_success_color if charge_success else arrow_fail_color

	# Calculate draw endpoint based on animation progress
	var draw_end = from_pos.lerp(to_pos, _line_progress)

	# --- Pulsing glow effect during hold ---
	var pulse_factor = 1.0
	if _phase == "hold" or _phase == "fade":
		pulse_factor = 1.0 + 0.15 * sin(_pulse_time * PULSE_SPEED)

	# --- Outer glow line ---
	var glow_color = _alpha(base_color, alpha * 0.25 * pulse_factor)
	draw_line(from_pos, draw_end, glow_color, GLOW_WIDTH)

	# --- Core arrow line ---
	var core_color = _alpha(base_color, alpha * 0.9)
	draw_line(from_pos, draw_end, core_color, LINE_WIDTH)

	# --- Arrowhead at draw_end ---
	if _line_progress > 0.1:
		_draw_arrowhead(draw_end, dir_norm, core_color, alpha)

	# --- Charge flash at charger position ---
	if _charge_flash_alpha > 0.0:
		var flash_alpha = _charge_flash_alpha * alpha
		# Outer glow
		var outer = _alpha(CHARGE_FLASH_COLOR, flash_alpha * 0.4)
		draw_circle(from_pos, CHARGE_FLASH_RADIUS * (1.0 + _charge_flash_alpha * 0.3), outer)
		# Inner core
		var inner = _alpha(CHARGE_FLASH_CORE_COLOR, flash_alpha * 0.7)
		draw_circle(from_pos, CHARGE_FLASH_RADIUS * 0.4, inner)

	# --- Charge roll result label ---
	if charge_roll_total >= 0 and _line_progress >= 1.0:
		_draw_roll_label(alpha)

func _draw_arrowhead(tip: Vector2, direction: Vector2, color: Color, alpha: float) -> void:
	"""Draw a filled arrowhead triangle at the tip position."""
	var head_color = _alpha(color, alpha)
	var p1 = tip - direction.rotated(ARROW_HEAD_ANGLE) * ARROW_HEAD_SIZE
	var p2 = tip - direction.rotated(-ARROW_HEAD_ANGLE) * ARROW_HEAD_SIZE
	var points = PackedVector2Array([tip, p1, p2])
	var colors = PackedColorArray([head_color, head_color, head_color])
	draw_polygon(points, colors)

func _draw_roll_label(alpha: float) -> void:
	"""Draw the charge roll result prominently at the midpoint of the arrow."""
	var font = FactionPalettes.FONT_RAJDHANI_SEMIBOLD
	if not font:
		return

	var mid_point = (from_pos + to_pos) / 2.0

	# Build label text
	var label_text = "Charge: %d\"" % charge_roll_total
	if _has_result:
		label_text += " - %s" % ("SUCCESS" if charge_success else "FAILED")

	var text_size = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)

	# Position label above the line
	var direction = (to_pos - from_pos).normalized()
	var perpendicular = Vector2(-direction.y, direction.x)
	var label_pos = mid_point + perpendicular * 20.0

	# Background rectangle
	var bg_rect = Rect2(
		label_pos - LABEL_BG_PADDING,
		text_size + LABEL_BG_PADDING * 2
	)
	draw_rect(bg_rect, _alpha(label_bg_color, label_bg_color.a * alpha), true)

	# Border color matches arrow state
	var border_color: Color
	if _has_result:
		border_color = arrow_success_color if charge_success else arrow_fail_color
	else:
		border_color = arrow_color
	border_color.a = 0.7 * alpha
	draw_rect(bg_rect, border_color, false, 1.5)

	# Text color
	var text_color: Color
	if _has_result:
		text_color = arrow_success_color if charge_success else arrow_fail_color
	else:
		text_color = pending_text_color  # MARGINAL_YELLOW — roll still pending
	text_color.a = alpha

	draw_string(
		font,
		label_pos + Vector2(0, text_size.y * 0.7),
		label_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		LABEL_FONT_SIZE,
		text_color
	)

# --- Public API ---

func play(charger_pos: Vector2, target_pos: Vector2) -> void:
	"""Start the charge arrow animation from charger to target."""
	from_pos = charger_pos
	to_pos = target_pos
	charge_roll_total = -1
	charge_success = false
	_has_result = false

	_phase = "line_draw"
	_elapsed = 0.0
	_line_progress = 0.0
	_charge_flash_alpha = 1.0
	_fade_alpha = 1.0
	_pulse_time = 0.0

	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_hold_timer.stop()

	visible = true
	queue_redraw()
	print("[ChargeArrowVisual] T7-58: Playing charge arrow %s -> %s" % [str(charger_pos), str(target_pos)])

func show_static(charger_pos: Vector2, target_pos: Vector2) -> void:
	"""Show the arrow immediately without animation."""
	from_pos = charger_pos
	to_pos = target_pos
	charge_roll_total = -1
	charge_success = false
	_has_result = false

	_phase = "hold"
	_line_progress = 1.0
	_charge_flash_alpha = 0.0
	_fade_alpha = 1.0
	_pulse_time = 0.0

	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_hold_timer.stop()
	_hold_timer.start(HOLD_DURATION)

	visible = true
	queue_redraw()

func set_roll_result(roll_total: int, success: bool) -> void:
	"""Update the arrow with the charge roll result. Changes color and shows label."""
	charge_roll_total = roll_total
	charge_success = success
	_has_result = true

	# Restart hold timer so the result stays visible
	if _phase == "hold":
		_hold_timer.stop()
		_hold_timer.start(HOLD_DURATION)

	queue_redraw()
	print("[ChargeArrowVisual] T7-58: Roll result set: %d\" (%s)" % [roll_total, "success" if success else "failed"])

func clear_now() -> void:
	"""Immediately clear the visual without fading."""
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_hold_timer.stop()
	_phase = "idle"
	_line_progress = 0.0
	_charge_flash_alpha = 0.0
	_fade_alpha = 1.0
	charge_roll_total = -1
	charge_success = false
	_has_result = false
	visible = false
	queue_redraw()

func _start_fade_out() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_phase = "fade"
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "_fade_alpha", 0.0, FADE_DURATION).set_ease(Tween.EASE_IN)
	_fade_tween.tween_callback(_on_fade_complete)

func _on_fade_complete() -> void:
	_phase = "idle"
	visible = false
	animation_finished.emit()
	queue_redraw()
