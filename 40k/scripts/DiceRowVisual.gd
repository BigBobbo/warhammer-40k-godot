extends Control
class_name DiceRowVisual

# DiceRowVisual - Static inline dice row for embedding inside the game log.
# Mirrors the color-coding of DiceRollVisual (gold=6, red=1, green=success,
# gray=fail) but renders a single static frame: no animation, no fade, no sound.

const DIE_SIZE := 18.0
const DIE_MARGIN := 3.0
const DIE_CORNER_RADIUS := 3.0
const ROW_SPACING := 3.0
const MAX_DICE_PER_ROW := 10

const COLOR_CRITICAL := Color(1.0, 0.84, 0.0)
const COLOR_FUMBLE := Color(0.9, 0.15, 0.15)
const COLOR_SUCCESS := Color(0.2, 0.75, 0.2)
const COLOR_FAIL := Color(0.35, 0.35, 0.4)
const COLOR_DIE_TEXT := Color(1.0, 1.0, 1.0)
const COLOR_DIE_TEXT_DARK := Color(0.1, 0.1, 0.1)
const COLOR_DIE_NEUTRAL := Color(0.25, 0.45, 0.7)

var _rolls: Array = []
var _threshold: int = 0
var _use_threshold_colors: bool = true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_dice(rolls: Array, threshold: int = 0, use_threshold_colors: bool = true) -> void:
	_rolls.clear()
	for r in rolls:
		_rolls.append(int(r))
	_threshold = threshold
	_use_threshold_colors = use_threshold_colors
	_update_min_size()
	queue_redraw()

func _update_min_size() -> void:
	if _rolls.is_empty():
		custom_minimum_size = Vector2(0, 0)
		return
	var n: int = _rolls.size()
	var cols: int = mini(n, MAX_DICE_PER_ROW)
	var rows: int = int(ceil(float(n) / float(MAX_DICE_PER_ROW)))
	var w: float = cols * DIE_SIZE + maxf(0.0, (cols - 1)) * DIE_MARGIN
	var h: float = rows * DIE_SIZE + maxf(0.0, (rows - 1)) * ROW_SPACING
	custom_minimum_size = Vector2(w, h)

func _get_die_color(value: int) -> Color:
	if value == 6:
		return COLOR_CRITICAL
	if value == 1:
		return COLOR_FUMBLE
	if _use_threshold_colors and _threshold > 0:
		if value >= _threshold:
			return COLOR_SUCCESS
		return COLOR_FAIL
	return COLOR_DIE_NEUTRAL

func _draw() -> void:
	if _rolls.is_empty():
		return

	for i in range(_rolls.size()):
		var value: int = _rolls[i]
		var col: int = i % MAX_DICE_PER_ROW
		var row: int = i / MAX_DICE_PER_ROW
		var x: float = col * (DIE_SIZE + DIE_MARGIN)
		var y: float = row * (DIE_SIZE + ROW_SPACING)
		var rect := Rect2(x, y, DIE_SIZE, DIE_SIZE)
		var bg := _get_die_color(value)

		# Drop shadow
		var shadow_rect := Rect2(x + 1, y + 1, DIE_SIZE, DIE_SIZE)
		var shadow_style := StyleBoxFlat.new()
		shadow_style.bg_color = Color(0.0, 0.0, 0.0, 0.3)
		shadow_style.set_corner_radius_all(DIE_CORNER_RADIUS)
		draw_style_box(shadow_style, shadow_rect)

		# Subtle glow for natural 6s
		if value == 6:
			var glow_rect := Rect2(x - 2, y - 2, DIE_SIZE + 4, DIE_SIZE + 4)
			var glow_style := StyleBoxFlat.new()
			glow_style.bg_color = Color(1.0, 0.84, 0.0, 0.25)
			glow_style.set_corner_radius_all(DIE_CORNER_RADIUS + 2)
			draw_style_box(glow_style, glow_rect)

		# Die face
		var style := StyleBoxFlat.new()
		style.bg_color = bg
		style.set_corner_radius_all(DIE_CORNER_RADIUS)
		style.set_border_width_all(1)
		style.border_color = Color(0.0, 0.0, 0.0, 0.6)
		draw_style_box(style, rect)

		# Pips
		var pip_color: Color = COLOR_DIE_TEXT_DARK if value == 6 else COLOR_DIE_TEXT
		_draw_pips(x, y, value, pip_color)

		# Strike-through X for natural 1s
		if value == 1:
			var line_color := Color(1.0, 1.0, 1.0, 0.35)
			draw_line(Vector2(x + 3, y + 3), Vector2(x + DIE_SIZE - 3, y + DIE_SIZE - 3), line_color, 1.0)
			draw_line(Vector2(x + DIE_SIZE - 3, y + 3), Vector2(x + 3, y + DIE_SIZE - 3), line_color, 1.0)

func _draw_pips(x: float, y: float, value: int, color: Color) -> void:
	var pip_radius: float = 2.0
	var cx: float = x + DIE_SIZE * 0.5
	var cy: float = y + DIE_SIZE * 0.5
	var off: float = DIE_SIZE * 0.27

	if value == 1 or value == 3 or value == 5:
		draw_circle(Vector2(cx, cy), pip_radius, color)
	if value >= 2:
		draw_circle(Vector2(cx - off, cy - off), pip_radius, color)
		draw_circle(Vector2(cx + off, cy + off), pip_radius, color)
	if value >= 4:
		draw_circle(Vector2(cx + off, cy - off), pip_radius, color)
		draw_circle(Vector2(cx - off, cy + off), pip_radius, color)
	if value == 6:
		draw_circle(Vector2(cx - off, cy), pip_radius, color)
		draw_circle(Vector2(cx + off, cy), pip_radius, color)
