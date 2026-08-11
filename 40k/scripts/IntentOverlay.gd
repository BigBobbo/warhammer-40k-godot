extends Node2D
class_name IntentOverlay

# PM-6 — the board half of the intent painter: a badge over every earmarked
# unit, and a line from the unit to the objective its intent is about.
#
# Deliberately NOT built on AIMovementPathVisual or AIUnitHighlight. Those are
# transient: AIMovementPathVisual holds for 2.5s and fades over 1s
# (AIMovementPathVisual.gd:10-12), and AIUnitHighlight is a text-less pulsing
# ring. An intent badge is a persistent annotation the author reads while they
# work, so it needs its own lifecycle — it redraws on demand and never fades.
# Only the drawing STYLE (dashed line, player-themed colour) is borrowed.

const BADGE_HEIGHT: float = 26.0
const BADGE_PAD_X: float = 8.0
const BADGE_OFFSET_Y: float = -46.0     # above the unit's centroid
const BADGE_FONT_SIZE: int = 15
const LINE_WIDTH: float = 2.5
const DASH_LENGTH: float = 10.0
const GAP_LENGTH: float = 7.0

const BADGE_BG := Color(0.10, 0.08, 0.04, 0.92)
const BADGE_BORDER := Color(1.0, 0.84, 0.35, 0.95)
const BADGE_TEXT := Color(1.0, 0.92, 0.72, 1.0)
const LINK_COLOR := Color(1.0, 0.84, 0.35, 0.55)

# [{text: String, at: Vector2 (board px), link_to: Vector2 or null}]
var _badges: Array = []


func _ready() -> void:
	# Above tokens (10) and the AI trail layer (11) so a badge is never buried
	# under the models it annotates.
	z_index = 14


func set_badges(badges: Array) -> void:
	_badges = badges
	queue_redraw()


func clear_badges() -> void:
	_badges = []
	queue_redraw()


func badge_count() -> int:
	return _badges.size()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for badge in _badges:
		if not (badge is Dictionary):
			continue
		var at: Vector2 = badge.get("at", Vector2.ZERO)
		var text: String = str(badge.get("text", ""))

		var link = badge.get("link_to", null)
		if link != null and link is Vector2:
			_draw_dashed_line(at, link, LINK_COLOR)
			draw_circle(link, 5.0, LINK_COLOR)

		var text_size: Vector2 = font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_FONT_SIZE)
		var box := Rect2(
			at.x - text_size.x * 0.5 - BADGE_PAD_X,
			at.y + BADGE_OFFSET_Y - BADGE_HEIGHT * 0.5,
			text_size.x + BADGE_PAD_X * 2.0,
			BADGE_HEIGHT)
		draw_rect(box, BADGE_BG, true)
		draw_rect(box, BADGE_BORDER, false, 2.0)
		draw_string(font,
			Vector2(box.position.x + BADGE_PAD_X, box.position.y + BADGE_HEIGHT * 0.72),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_FONT_SIZE, BADGE_TEXT)


func _draw_dashed_line(from: Vector2, to: Vector2, color: Color) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 0.001:
		return
	var dir := delta / length
	var travelled := 0.0
	while travelled < length:
		var seg_end: float = minf(travelled + DASH_LENGTH, length)
		draw_line(from + dir * travelled, from + dir * seg_end, color, LINE_WIDTH)
		travelled = seg_end + GAP_LENGTH
