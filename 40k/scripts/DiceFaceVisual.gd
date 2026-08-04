extends Control
class_name DiceFaceVisual

# DiceFaceVisual — a Control that draws a single LARGE D6 face with pips, themed
# to match the parchment/gold White Dwarf styling. `value` (1-6) drives the pip
# layout; `highlight` tints the face for winner/loser/tie states.
#
# Extracted from RollOffDialog's inner `DiceFace` class so the dramatic
# centre-stage dice can be reused by any flow that rolls in front of the player
# (the pre-deployment / first-turn roll-offs and the Command-phase Battle-shock
# roll call). RollOffDialog keeps a `const DiceFace = preload(...)` alias so all
# of its existing call sites read unchanged.
#
# NOT to be confused with DiceFaceIcons (small ImageTextures for inline
# RichTextLabel embedding) or DiceRollVisual (the many-dice results strip).

enum Highlight { NONE, WINNER, LOSER, TIE }

var value: int = 1:
	set(v):
		value = clampi(v, 1, 6)
		queue_redraw()
var highlight: int = Highlight.NONE:
	set(h):
		highlight = h
		queue_redraw()

func _draw() -> void:
	var sz := size
	var rect := Rect2(Vector2.ZERO, sz)

	# Face colour + border depend on highlight state.
	var face_color := Color(0.922, 0.882, 0.780)   # WH_PARCHMENT
	var border_color := Color(0.833, 0.588, 0.376)  # WH_GOLD
	var border_w := 3.0
	match highlight:
		Highlight.WINNER:
			face_color = Color(1.0, 0.93, 0.74)
			border_color = Color(1.0, 0.78, 0.30)
			border_w = 6.0
		Highlight.LOSER:
			face_color = Color(0.78, 0.75, 0.66)
			border_color = Color(0.55, 0.50, 0.42)
		Highlight.TIE:
			border_color = Color(0.604, 0.067, 0.082)  # WH_RED
			border_w = 5.0

	# Soft drop shadow for depth.
	var shadow_rect := Rect2(rect.position + Vector2(4, 5), rect.size)
	_draw_round_rect(shadow_rect, Color(0, 0, 0, 0.35), 14.0)
	# Die body + border.
	_draw_round_rect(rect, face_color, 14.0)
	_draw_round_rect_outline(rect, border_color, 14.0, border_w)

	# Pips.
	var pip_color := Color(0.12, 0.10, 0.09)
	var pip_r: float = min(sz.x, sz.y) * 0.085
	for p in _pip_positions(value):
		draw_circle(Vector2(p.x * sz.x, p.y * sz.y), pip_r, pip_color)

# Normalised pip positions (0..1) for each die value.
func _pip_positions(v: int) -> Array:
	var c := Vector2(0.5, 0.5)
	var tl := Vector2(0.28, 0.28)
	var tr := Vector2(0.72, 0.28)
	var bl := Vector2(0.28, 0.72)
	var br := Vector2(0.72, 0.72)
	var ml := Vector2(0.28, 0.5)
	var mr := Vector2(0.72, 0.5)
	match v:
		1: return [c]
		2: return [tl, br]
		3: return [tl, c, br]
		4: return [tl, tr, bl, br]
		5: return [tl, tr, c, bl, br]
		6: return [tl, tr, ml, mr, bl, br]
	return [c]

func _draw_round_rect(rect: Rect2, color: Color, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(radius))
	draw_style_box(sb, rect)

func _draw_round_rect_outline(rect: Rect2, color: Color, radius: float, width: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_corner_radius_all(int(radius))
	sb.set_border_width_all(int(width))
	sb.border_color = color
	draw_style_box(sb, rect)
