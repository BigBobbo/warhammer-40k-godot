extends Node2D
class_name AIThoughtLinkVisual

## Draws one AI decision's considered options on the board: the deciding unit,
## a solid green arrow to the CHOSEN option and faded red arrows to the
## REJECTED ones, each labelled with its score. Driven by the AI thinking
## cards in GameLogPanel (hover to preview, click to pin).
## Coordinates are board px — this node lives under BoardRoot, the same space
## tokens and objectives use.

const COLOR_CHOSEN := Color(0.35, 0.85, 0.45, 0.95)
const COLOR_REJECTED := Color(0.85, 0.35, 0.35, 0.55)
const COLOR_UNIT_RING := Color(0.55, 0.75, 1.0, 0.9)
const LINE_WIDTH_CHOSEN := 4.0
const LINE_WIDTH_REJECTED := 2.5
const ARROW_SIZE := 14.0
const UNIT_RING_RADIUS := 26.0
const LABEL_FONT_SIZE := 13

var _context: Dictionary = {}

func _ready() -> void:
	name = "AIThoughtLinkVisual"
	z_index = 900  # Above tokens/terrain, below transient dialogs
	visible = false

func show_links(context: Dictionary) -> void:
	"""Display the option arrows for one decision context:
	{unit_name, unit_pos: [x,y], candidates: [{label, score, pos: [x,y], chosen}]}"""
	_context = context if context != null else {}
	visible = not _context.is_empty()
	queue_redraw()

func clear_links() -> void:
	_context = {}
	visible = false
	queue_redraw()

func is_active() -> bool:
	return visible and not _context.is_empty()

func get_link_count() -> int:
	return _context.get("candidates", []).size()

func _draw() -> void:
	if _context.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var unit_pos_arr = _context.get("unit_pos", [])
	var has_origin: bool = unit_pos_arr is Array and unit_pos_arr.size() == 2
	var origin := Vector2.ZERO
	if has_origin:
		origin = Vector2(float(unit_pos_arr[0]), float(unit_pos_arr[1]))
		# Ring + name on the deciding unit's recorded position
		draw_arc(origin, UNIT_RING_RADIUS, 0.0, TAU, 40, COLOR_UNIT_RING, 3.0, true)
		var unit_name = str(_context.get("unit_name", ""))
		if unit_name != "":
			_draw_label(font, origin + Vector2(-UNIT_RING_RADIUS, -UNIT_RING_RADIUS - 8.0), unit_name, COLOR_UNIT_RING)

	# Draw rejected arrows first so the chosen one renders on top
	for pass_chosen in [false, true]:
		for cand in _context.get("candidates", []):
			if bool(cand.get("chosen", false)) != pass_chosen:
				continue
			var pos_arr = cand.get("pos", [])
			if not (pos_arr is Array and pos_arr.size() == 2):
				continue
			var target := Vector2(float(pos_arr[0]), float(pos_arr[1]))
			var color: Color = COLOR_CHOSEN if pass_chosen else COLOR_REJECTED
			var width: float = LINE_WIDTH_CHOSEN if pass_chosen else LINE_WIDTH_REJECTED

			if has_origin and origin.distance_to(target) > 1.0:
				var dir := (target - origin).normalized()
				var start := origin + dir * UNIT_RING_RADIUS
				var tip := target - dir * 10.0
				if pass_chosen:
					draw_line(start, tip, color, width, true)
				else:
					_draw_dashed(start, tip, color, width)
				# Arrowhead
				var left := tip - dir.rotated(0.45) * ARROW_SIZE
				var right := tip - dir.rotated(-0.45) * ARROW_SIZE
				draw_colored_polygon(PackedVector2Array([tip, left, right]), color)
			else:
				# No origin — mark the option position alone
				draw_arc(target, 16.0, 0.0, TAU, 24, color, width, true)

			# Score tag near the option
			var score := float(cand.get("score", 0.0))
			var tag := "✓ %.1f" % score if pass_chosen else "✗ %.1f" % score
			_draw_label(font, target + Vector2(14.0, -10.0), tag, color)

func _draw_dashed(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var seg := 14.0
	var gap := 8.0
	var dir := (to - from).normalized()
	var total := from.distance_to(to)
	var t := 0.0
	while t < total:
		var a := from + dir * t
		var b := from + dir * minf(t + seg, total)
		draw_line(a, b, color, width, true)
		t += seg + gap

func _draw_label(font: Font, pos: Vector2, text: String, color: Color) -> void:
	# Dark backing so labels stay readable over any board art
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
	draw_rect(Rect2(pos - Vector2(3, size.y - 3), size + Vector2(6, 4)), Color(0.05, 0.05, 0.08, 0.75))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, color)
