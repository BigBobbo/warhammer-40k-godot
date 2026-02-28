extends Control
class_name PlayerTurnBorder

# P2-44: Player Turn Screen-Edge Color Indicator
# Draws a colored border around the screen edge matching the active player's color.
# Blue for Player 1, red for Player 2. Flashes briefly on turn swap.

const BORDER_THICKNESS := 6.0
const FLASH_PEAK_THICKNESS := 18.0
const FLASH_DURATION := 0.6
const STEADY_ALPHA := 0.65
const FLASH_PEAK_ALPHA := 0.95

# Player colors — vivid blue for P1, vivid red for P2
const P1_COLOR := Color(0.2, 0.45, 0.9)   # Blue
const P2_COLOR := Color(0.9, 0.15, 0.1)   # Red

var _current_color: Color = P1_COLOR
var _current_thickness: float = BORDER_THICKNESS
var _current_alpha: float = STEADY_ALPHA
var _flash_tween: Tween = null

# Four border ColorRects (top, bottom, left, right)
var _top: ColorRect
var _bottom: ColorRect
var _left: ColorRect
var _right: ColorRect

func _ready() -> void:
	name = "PlayerTurnBorder"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_top = _create_edge()
	_bottom = _create_edge()
	_left = _create_edge()
	_right = _create_edge()

	add_child(_top)
	add_child(_bottom)
	add_child(_left)
	add_child(_right)

	# Start with Player 1 color
	_apply_color(P1_COLOR)
	_layout_edges()
	print("PlayerTurnBorder: Initialized with Player 1 color")

func _create_edge() -> ColorRect:
	var edge = ColorRect.new()
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return edge

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_edges()

func _layout_edges() -> void:
	var vp_size = get_viewport_rect().size
	if vp_size == Vector2.ZERO:
		return

	var t = _current_thickness

	# Top edge
	_top.position = Vector2.ZERO
	_top.size = Vector2(vp_size.x, t)

	# Bottom edge
	_bottom.position = Vector2(0, vp_size.y - t)
	_bottom.size = Vector2(vp_size.x, t)

	# Left edge (between top and bottom)
	_left.position = Vector2(0, t)
	_left.size = Vector2(t, vp_size.y - 2 * t)

	# Right edge (between top and bottom)
	_right.position = Vector2(vp_size.x - t, t)
	_right.size = Vector2(t, vp_size.y - 2 * t)

func _apply_color(base_color: Color) -> void:
	_current_color = base_color
	var c = Color(base_color, _current_alpha)
	_top.color = c
	_bottom.color = c
	_left.color = c
	_right.color = c

func set_active_player(player: int) -> void:
	var new_color = P1_COLOR if player == 1 else P2_COLOR
	_current_color = new_color
	_apply_color(new_color)
	print("PlayerTurnBorder: Updated to Player %d color" % player)

func flash_turn_swap(player: int) -> void:
	# Flash: briefly expand thickness and increase alpha, then settle back
	var new_color = P1_COLOR if player == 1 else P2_COLOR
	_current_color = new_color

	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()

	_flash_tween = create_tween()

	# Phase 1: Expand to peak (fast)
	_flash_tween.tween_method(_set_flash_state.bind(new_color), 0.0, 1.0, FLASH_DURATION * 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# Phase 2: Hold at peak briefly
	_flash_tween.tween_interval(FLASH_DURATION * 0.15)

	# Phase 3: Settle back to steady state
	_flash_tween.tween_method(_set_flash_state.bind(new_color), 1.0, 0.0, FLASH_DURATION * 0.55).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

	print("PlayerTurnBorder: Flash animation for Player %d" % player)

func _set_flash_state(t: float, base_color: Color) -> void:
	# t goes from 0 (steady) to 1 (peak flash) and back to 0
	_current_thickness = lerpf(BORDER_THICKNESS, FLASH_PEAK_THICKNESS, t)
	_current_alpha = lerpf(STEADY_ALPHA, FLASH_PEAK_ALPHA, t)
	_apply_color(base_color)
	_layout_edges()
