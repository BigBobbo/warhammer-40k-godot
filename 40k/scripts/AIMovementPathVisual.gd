extends Node2D
class_name AIMovementPathVisual

# AIMovementPathVisual - Shows brief movement trails during AI movement
# T7-21: Draws dashed lines with arrowheads from each model's origin to its
# destination after AI movement, then fades out after a brief hold period.
# Follows ChargeArrowVisual animation pattern.

# Animation timing
const HOLD_DURATION := 2.5  # How long to hold the trail visible
const FADE_DURATION := 1.0  # Fade out time

# Visual settings — trails are per-PLAYER indicators, so they use the
# UIConstants player-slot colors (T12/T41): P1 teal, P2 magenta. This
# replaces the old ad-hoc blue/red pair. Initializers are canonical-hex
# fallbacks for headless -s contexts where the autoload is absent (bare
# autoload names don't compile there); _ready() re-resolves them.
var p1_trail_color: Color = Color(0.00, 0.70, 0.70, 0.7)  # == with_alpha(UIConstants.FRIENDLY_PLAYER_TEAL, 0.7)
var p2_trail_color: Color = Color(0.90, 0.20, 0.70, 0.7)  # == with_alpha(UIConstants.ENEMY_PLAYER_MAGENTA, 0.7)
const TRAIL_GLOW_COLOR_ALPHA := 0.2  # Glow layer alpha multiplier

# T12: local alpha-override helper (autoload-free so headless -s harnesses
# can still compile this script; Color is by-value so mutating is safe).
static func _alpha(c: Color, a: float) -> Color:
	c.a = a
	return c
const LINE_WIDTH := 2.5
const GLOW_WIDTH := 7.0
const DASH_LENGTH := 8.0
const GAP_LENGTH := 5.0

# Arrowhead settings
const ARROW_HEAD_SIZE := 10.0
const ARROW_HEAD_ANGLE := 0.45  # Radians

# Origin marker settings
const ORIGIN_MARKER_RADIUS := 4.0

# State
var _paths: Array = []  # Array of {from: Vector2, to: Vector2}
var _owner_player: int = 1
var _phase := "idle"  # idle, hold, fade
var _fade_alpha := 1.0
var _fade_tween: Tween = null
var _hold_timer: Timer = null

signal animation_finished()

func _ready() -> void:
	z_index = 11  # Between tokens (10) and shooting lines (12)
	_hold_timer = Timer.new()
	_hold_timer.one_shot = true
	_hold_timer.timeout.connect(_start_fade_out)
	add_child(_hold_timer)
	# T12/T41: re-resolve trail colors from the UIConstants player slots now
	# that the node is in the tree (fallbacks cover headless -s runs).
	var uic = get_node_or_null("/root/UIConstants")
	if uic != null:
		p1_trail_color = _alpha(uic.player_slot_color(1), 0.7)
		p2_trail_color = _alpha(uic.player_slot_color(2), 0.7)

func _process(_delta: float) -> void:
	if _phase == "fade":
		queue_redraw()

func _draw() -> void:
	if _phase == "idle":
		return
	if _paths.is_empty():
		return

	var alpha = _fade_alpha
	var base_color = p1_trail_color if _owner_player == 1 else p2_trail_color

	for path in _paths:
		var from_pos: Vector2 = path["from"]
		var to_pos: Vector2 = path["to"]
		var direction = to_pos - from_pos

		if direction.length_squared() < 1.0:
			continue

		var dir_norm = direction.normalized()

		# Glow line (solid, wide, low alpha)
		var glow_color = _alpha(base_color, alpha * TRAIL_GLOW_COLOR_ALPHA)
		draw_line(from_pos, to_pos, glow_color, GLOW_WIDTH)

		# Dashed core line
		var trail_color = _alpha(base_color, alpha * base_color.a)
		_draw_dashed_line(from_pos, to_pos, trail_color, LINE_WIDTH)

		# Arrowhead at destination
		_draw_arrowhead(to_pos, dir_norm, trail_color)

		# Small circle at origin
		var origin_color = _alpha(base_color, alpha * 0.5)
		draw_circle(from_pos, ORIGIN_MARKER_RADIUS, origin_color)

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

func _draw_arrowhead(tip: Vector2, direction: Vector2, color: Color) -> void:
	var p1 = tip - direction.rotated(ARROW_HEAD_ANGLE) * ARROW_HEAD_SIZE
	var p2 = tip - direction.rotated(-ARROW_HEAD_ANGLE) * ARROW_HEAD_SIZE
	var points = PackedVector2Array([tip, p1, p2])
	var colors = PackedColorArray([color, color, color])
	draw_polygon(points, colors)

# --- Public API ---

func show_paths(paths: Array, owner_player: int) -> void:
	"""Show movement trails for the given paths. Each path is {from: Vector2, to: Vector2}."""
	_paths = paths
	_owner_player = owner_player

	_phase = "hold"
	_fade_alpha = 1.0

	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_hold_timer.stop()
	_hold_timer.start(HOLD_DURATION)

	visible = true
	queue_redraw()
	print("[AIMovementPathVisual] T7-21: Showing %d movement trails for player %d" % [paths.size(), owner_player])

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
	_phase = "fade"
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "_fade_alpha", 0.0, FADE_DURATION).set_ease(Tween.EASE_IN)
	_fade_tween.tween_callback(_on_fade_complete)

func _on_fade_complete() -> void:
	_phase = "idle"
	visible = false
	_paths.clear()
	animation_finished.emit()
	queue_free()
