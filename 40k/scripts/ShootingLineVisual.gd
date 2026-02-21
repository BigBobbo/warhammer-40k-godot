extends Node2D
class_name ShootingLineVisual

# ShootingLineVisual - Animated shooting line with tracer effects
# T5-V2: Draws an animated line from shooter to target with muzzle flash
# and a traveling tracer pulse. Used for both local and remote player feedback.

# Animation timing
const LINE_DRAW_DURATION := 0.25  # Time for line to extend from shooter to target
const TRACER_DURATION := 0.35  # Time for tracer pulse to travel along line
const MUZZLE_FLASH_DURATION := 0.15  # Duration of muzzle flash
const HOLD_DURATION := 3.0  # How long to hold the line visible after animation
const FADE_DURATION := 0.8  # Fade out time

# Visual settings
const LINE_COLOR := Color(1.0, 0.5, 0.0, 0.8)  # Orange (matches SHOOTING_LINE_COLOR)
const LINE_WIDTH := 3.0
const TRACER_COLOR := Color(1.0, 0.9, 0.3, 1.0)  # Bright yellow-white tracer
const TRACER_GLOW_COLOR := Color(1.0, 0.7, 0.2, 0.4)  # Outer glow
const TRACER_LENGTH := 40.0  # Length of the tracer pulse in pixels
const TRACER_WIDTH := 5.0  # Width of the bright core
const MUZZLE_FLASH_COLOR := Color(1.0, 0.85, 0.3, 0.9)  # Bright yellow flash
const MUZZLE_FLASH_RADIUS := 18.0  # Radius of the muzzle flash
const IMPACT_FLASH_COLOR := Color(1.0, 0.4, 0.1, 0.8)  # Orange-red impact
const IMPACT_FLASH_RADIUS := 12.0

# State
var from_pos := Vector2.ZERO  # Shooter position (world coords)
var to_pos := Vector2.ZERO  # Target position (world coords)
var weapon_name := ""  # Weapon label text

var _phase := "idle"  # idle, line_draw, tracer, hold, fade
var _elapsed := 0.0
var _line_progress := 0.0  # 0..1 how much of line is drawn
var _tracer_progress := 0.0  # 0..1 tracer position along line
var _muzzle_flash_alpha := 0.0
var _impact_flash_alpha := 0.0
var _fade_alpha := 1.0
var _fade_tween: Tween = null
var _hold_timer: Timer = null

# T7-38: AI shooting line customization
var custom_line_color: Color = Color.TRANSPARENT  # Override line color if set (non-transparent)
var custom_hold_duration: float = -1.0  # Override hold duration if >= 0
var auto_cleanup: bool = false  # Auto queue_free after animation completes

signal animation_finished()

func _ready() -> void:
	z_index = 12  # Above tokens (10), below measuring tape (15)
	_hold_timer = Timer.new()
	_hold_timer.one_shot = true
	_hold_timer.timeout.connect(_start_fade_out)
	add_child(_hold_timer)

func _process(delta: float) -> void:
	if _phase == "idle" or _phase == "hold" or _phase == "fade":
		return

	_elapsed += delta

	if _phase == "line_draw":
		_line_progress = clampf(_elapsed / LINE_DRAW_DURATION, 0.0, 1.0)
		# Muzzle flash peaks at start and fades during line draw
		_muzzle_flash_alpha = clampf(1.0 - (_elapsed / MUZZLE_FLASH_DURATION), 0.0, 1.0)

		if _line_progress >= 1.0:
			_phase = "tracer"
			_elapsed = 0.0
			_line_progress = 1.0

	elif _phase == "tracer":
		_tracer_progress = clampf(_elapsed / TRACER_DURATION, 0.0, 1.0)
		# Impact flash appears when tracer reaches end
		if _tracer_progress >= 0.9:
			_impact_flash_alpha = clampf((1.0 - _tracer_progress) / 0.1, 0.0, 1.0)
		if _tracer_progress >= 1.0:
			_impact_flash_alpha = 0.0
			_phase = "hold"
			var hold_time = custom_hold_duration if custom_hold_duration >= 0 else HOLD_DURATION
			_hold_timer.start(hold_time)

	queue_redraw()

func _get_line_color() -> Color:
	# T7-38: Return custom color if set, otherwise default
	if custom_line_color.a > 0.0:
		return custom_line_color
	return LINE_COLOR

func _draw() -> void:
	if _phase == "idle":
		return
	if from_pos == Vector2.ZERO or to_pos == Vector2.ZERO:
		return

	var alpha = _fade_alpha
	var effective_color = _get_line_color()  # T7-38: Support custom line color
	var direction = (to_pos - from_pos)
	var line_length = direction.length()
	var dir_norm = direction.normalized()

	# --- Draw the shooting line (extends during line_draw phase) ---
	var draw_end = from_pos.lerp(to_pos, _line_progress)

	# Outer glow line
	var glow_color = Color(effective_color.r, effective_color.g, effective_color.b, alpha * 0.3)
	draw_line(from_pos, draw_end, glow_color, LINE_WIDTH + 4.0)

	# Core line
	var core_color = Color(effective_color, alpha)
	draw_line(from_pos, draw_end, core_color, LINE_WIDTH)

	# --- Muzzle flash at shooter position ---
	if _muzzle_flash_alpha > 0.0:
		var flash_alpha = _muzzle_flash_alpha * alpha
		# Outer glow
		var outer_color = Color(MUZZLE_FLASH_COLOR.r, MUZZLE_FLASH_COLOR.g, MUZZLE_FLASH_COLOR.b, flash_alpha * 0.4)
		draw_circle(from_pos, MUZZLE_FLASH_RADIUS * (1.0 + _muzzle_flash_alpha * 0.5), outer_color)
		# Inner bright core
		var inner_color = Color(1.0, 1.0, 0.9, flash_alpha * 0.8)
		draw_circle(from_pos, MUZZLE_FLASH_RADIUS * 0.4, inner_color)

	# --- Tracer pulse traveling along the line ---
	if _phase == "tracer" or (_phase == "hold" and _tracer_progress < 1.0):
		var tracer_center = from_pos.lerp(to_pos, _tracer_progress)
		var tracer_half_len = TRACER_LENGTH * 0.5

		# Tracer head and tail positions (clamped to line)
		var tracer_tail_t = clampf(_tracer_progress - (tracer_half_len / line_length), 0.0, 1.0)
		var tracer_head_t = clampf(_tracer_progress + (tracer_half_len / line_length), 0.0, 1.0)
		var tracer_tail = from_pos.lerp(to_pos, tracer_tail_t)
		var tracer_head = from_pos.lerp(to_pos, tracer_head_t)

		# Outer glow
		var tracer_glow = Color(TRACER_GLOW_COLOR, alpha * TRACER_GLOW_COLOR.a)
		draw_line(tracer_tail, tracer_head, tracer_glow, TRACER_WIDTH + 6.0)

		# Bright core
		var tracer_core = Color(TRACER_COLOR, alpha)
		draw_line(tracer_tail, tracer_head, tracer_core, TRACER_WIDTH)

	# --- Impact flash at target position ---
	if _impact_flash_alpha > 0.0:
		var impact_alpha = _impact_flash_alpha * alpha
		var impact_color = Color(IMPACT_FLASH_COLOR.r, IMPACT_FLASH_COLOR.g, IMPACT_FLASH_COLOR.b, impact_alpha * 0.6)
		draw_circle(to_pos, IMPACT_FLASH_RADIUS * (1.0 + _impact_flash_alpha * 0.3), impact_color)
		var inner_impact = Color(1.0, 0.8, 0.3, impact_alpha * 0.9)
		draw_circle(to_pos, IMPACT_FLASH_RADIUS * 0.3, inner_impact)

	# --- Weapon name label at midpoint ---
	if not weapon_name.is_empty() and _line_progress >= 1.0:
		_draw_weapon_label(alpha)

func _draw_weapon_label(alpha: float) -> void:
	var mid_point = (from_pos + to_pos) / 2
	var font = ThemeDB.fallback_font
	var font_size = 12
	var text_size = font.get_string_size(weapon_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

	# Background for readability
	var bg_rect = Rect2(
		mid_point + Vector2(-text_size.x * 0.5 - 3, -text_size.y - 5),
		text_size + Vector2(6, 4)
	)
	draw_rect(bg_rect, Color(0, 0, 0, 0.6 * alpha))

	# Text
	var effective_color = _get_line_color()  # T7-38: Support custom line color
	var text_color = Color(effective_color.r, effective_color.g, effective_color.b, alpha)
	draw_string(
		font,
		mid_point + Vector2(-text_size.x * 0.5, -5),
		weapon_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		text_color
	)

func play(shooter_pos: Vector2, target_pos: Vector2, weapon: String = "") -> void:
	"""Start the shooting line animation from shooter_pos to target_pos."""
	from_pos = shooter_pos
	to_pos = target_pos
	weapon_name = weapon

	_phase = "line_draw"
	_elapsed = 0.0
	_line_progress = 0.0
	_tracer_progress = 0.0
	_muzzle_flash_alpha = 1.0
	_impact_flash_alpha = 0.0
	_fade_alpha = 1.0

	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_hold_timer.stop()

	visible = true
	queue_redraw()
	print("[ShootingLineVisual] T5-V2: Playing animation %s → %s (%s)" % [str(shooter_pos), str(target_pos), weapon])

func show_static(shooter_pos: Vector2, target_pos: Vector2, weapon: String = "") -> void:
	"""Show the line immediately without animation (for remote assignment preview)."""
	from_pos = shooter_pos
	to_pos = target_pos
	weapon_name = weapon

	_phase = "hold"
	_line_progress = 1.0
	_tracer_progress = 1.0
	_muzzle_flash_alpha = 0.0
	_impact_flash_alpha = 0.0
	_fade_alpha = 1.0

	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_hold_timer.stop()

	visible = true
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
	# T7-38: Auto-cleanup for AI shooting lines (not tracked in shooting_line_visuals)
	if auto_cleanup:
		queue_free()

func clear_now() -> void:
	"""Immediately clear the visual without fading."""
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_hold_timer.stop()
	_phase = "idle"
	_line_progress = 0.0
	_tracer_progress = 0.0
	_muzzle_flash_alpha = 0.0
	_impact_flash_alpha = 0.0
	_fade_alpha = 1.0
	visible = false
	queue_redraw()
