extends Node2D
class_name PadTargetReticle

## Board-space marker for THE unit the pad's next A press applies to.
##
## The shared visual language for controller target-stepping across phases
## (shooting D-pad ◀ ▶ ring, charge D-pad ▲ ▼ rows): every alive model of the
## stepped enemy unit gets pulsing gold corner brackets OUTSIDE the steady
## per-phase eligibility rings, and the unit's anchor model carries a
## "▶ TARGET n/m: NAME" banner. Gold deliberately matches
## AttackContextVisual.TARGET_COLOR — the game already teaches "gold = the
## unit being hit" during wound allocation.
##
## Positions/radii arrive pre-converted to board px, so this script has NO
## autoload dependencies and keeps compiling in bare headless harness runs.

const RETICLE_COLOR := Color(0.94, 0.78, 0.31, 0.95)  # gold — matches the charge row tint
const BRACKET_WIDTH := 3.5
const BRACKET_GAP := 9.0       # px outside the base edge — clears the +4px eligible rings
const BRACKET_SWEEP_DEG := 38.0  # arc length of each of the 4 corner brackets
const BANNER_FONT_SIZE := 13

# [{pos: Vector2, radius_px: float}, ...] — one per alive model.
var marks: Array = []
# Banner text, e.g. "▶ TARGET 2/3: WITCHSEEKERS". Empty = no banner.
var banner_text: String = ""

var _pulse: float = 1.0


func show_for_marks(p_marks: Array, p_banner: String) -> void:
	marks = p_marks
	banner_text = p_banner
	visible = true
	queue_redraw()


func clear() -> void:
	marks = []
	banner_text = ""
	visible = false
	queue_redraw()


func is_showing() -> bool:
	return visible and not marks.is_empty()


func _process(_delta: float) -> void:
	if not is_showing():
		return
	# Gentle ~1.5 Hz pulse — reads as "live cursor", distinct from the steady
	# eligibility rings underneath.
	var t = Time.get_ticks_msec() / 1000.0
	_pulse = lerp(0.55, 1.0, (sin(t * 3.0) + 1.0) / 2.0)
	queue_redraw()


func _draw() -> void:
	if marks.is_empty():
		return
	var color := RETICLE_COLOR
	color.a *= _pulse

	var topmost := Vector2.INF
	var topmost_radius := 0.0
	for m in marks:
		var pos: Vector2 = m.pos
		var radius: float = m.radius_px + BRACKET_GAP
		_draw_corner_brackets(pos, radius, color)
		if pos.y < topmost.y:
			topmost = pos
			topmost_radius = radius

	if banner_text == "" or topmost == Vector2.INF:
		return
	var font: Font = ThemeDB.fallback_font
	var text_size := font.get_string_size(banner_text, HORIZONTAL_ALIGNMENT_CENTER, -1, BANNER_FONT_SIZE)
	var text_pos := topmost + Vector2(-text_size.x / 2.0, -(topmost_radius + 12.0))
	var bg := Rect2(text_pos.x - 6, text_pos.y - BANNER_FONT_SIZE - 2, text_size.x + 12, BANNER_FONT_SIZE + 9)
	draw_rect(bg, Color(0.05, 0.05, 0.05, 0.85), true)
	draw_rect(bg, Color(RETICLE_COLOR, 0.9), false, 1.5)
	draw_string(font, text_pos + Vector2(0.5, 0.5), banner_text, HORIZONTAL_ALIGNMENT_CENTER, -1, BANNER_FONT_SIZE, Color(0, 0, 0, 0.7))
	draw_string(font, text_pos, banner_text, HORIZONTAL_ALIGNMENT_CENTER, -1, BANNER_FONT_SIZE, Color(1.0, 0.92, 0.75, 1.0))


# Four arc segments at the NE/SE/SW/NW diagonals with gaps between — a
# targeting bracket that cannot be mistaken for the full-circle rings the
# phases already draw (green eligible / gold allocation).
func _draw_corner_brackets(center: Vector2, radius: float, color: Color) -> void:
	var sweep := deg_to_rad(BRACKET_SWEEP_DEG)
	for i in range(4):
		var mid := deg_to_rad(45.0 + 90.0 * i)
		draw_arc(center, radius, mid - sweep / 2.0, mid + sweep / 2.0, 10, color, BRACKET_WIDTH, true)
	# Small cardinal ticks make the bracket read as a reticle at a glance.
	for i in range(4):
		var dir := Vector2.RIGHT.rotated(deg_to_rad(90.0 * i))
		draw_line(center + dir * (radius - 3.0), center + dir * (radius + 3.0), color, BRACKET_WIDTH * 0.75, true)
