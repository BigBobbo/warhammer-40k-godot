extends Node2D
class_name CardActionOverlay

# CardActionOverlay - Renders the 11e GDM card-action badges that live on
# TERRAIN features: Booby Traps (Death Trap) and the shared Extract Relic /
# Locate and Deny operation markers. Objective-anchored badges are drawn by
# ObjectiveVisual.set_card_action_badges; this layer covers the rest of the
# board state a player otherwise cannot see.

const BADGE_TRAP_COLOR = Color(1.0, 0.45, 0.25, 1.0)
const BADGE_RELIC_COLOR = Color(0.55, 0.9, 1.0, 1.0)

# Candidate-area highlight (Booby Trap target picking). A terrain AREA is the
# marked footprint the scenery stands in — players could not tell which one a
# raw id like "area-trapezoid-3" meant, so the dialog lights them up on the
# board while it is open.
const HIGHLIGHT_COLOR = Color(1.0, 0.55, 0.2, 1.0)
# The board renders at ~0.3 scale, so these are deliberately heavy: at the
# original 3px/0.16 they survived the zoom-out as barely a pixel of tint and
# the candidate areas read as ordinary terrain.
const HIGHLIGHT_FILL_ALPHA = 0.22
const HIGHLIGHT_FILL_ALPHA_FOCUS = 0.40
const HIGHLIGHT_WIDTH = 5.0
const HIGHLIGHT_WIDTH_FOCUS = 10.0

var _highlight_ids: Array = []
var _focus_id: String = ""

func _ready() -> void:
	name = "CardActionOverlay"
	z_index = 40
	var mm = get_node_or_null("/root/MissionManager")
	if mm and mm.has_signal("card_action_state_changed") \
			and not mm.card_action_state_changed.is_connected(refresh):
		mm.card_action_state_changed.connect(refresh)
	refresh()

## Outline these terrain areas on the board. `focus_id` (optional) is drawn
## brighter — the dialog passes the row the player is hovering.
func highlight_terrain_areas(ids: Array, focus_id: String = "") -> void:
	_highlight_ids = []
	for i in ids:
		_highlight_ids.append(str(i))
	_focus_id = str(focus_id)
	refresh()

func clear_terrain_area_highlights() -> void:
	if _highlight_ids.is_empty() and _focus_id == "":
		return
	_highlight_ids = []
	_focus_id = ""
	refresh()

func refresh() -> void:
	# remove_child BEFORE queue_free: a queued-but-still-parented child keeps
	# its name reserved for the rest of the frame, so re-adding "Badge_<id>"
	# in the same refresh would silently land as "@Label@1234" and every
	# lookup by name (scenarios, callers) would miss it.
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if GameConstants.edition < 11:
		return
	var mm = get_node_or_null("/root/MissionManager")
	var tm = get_node_or_null("/root/TerrainManager")
	if mm == null or tm == null:
		return

	# Candidate outlines first so the badge labels below stay legible on top.
	for feature in tm.terrain_features:
		var hid = str(feature.get("id", ""))
		if hid == "" or not hid in _highlight_ids:
			continue
		var polygon = feature.get("polygon", PackedVector2Array())
		if polygon.size() < 3:
			continue
		var focused: bool = hid == _focus_id

		var fill = Polygon2D.new()
		fill.name = "Highlight_%s" % hid
		fill.polygon = polygon
		fill.color = Color(HIGHLIGHT_COLOR.r, HIGHLIGHT_COLOR.g, HIGHLIGHT_COLOR.b,
			HIGHLIGHT_FILL_ALPHA_FOCUS if focused else HIGHLIGHT_FILL_ALPHA)
		add_child(fill)

		var outline = Line2D.new()
		outline.name = "HighlightEdge_%s" % hid
		var closed = PackedVector2Array(polygon)
		closed.append(polygon[0])
		outline.points = closed
		outline.width = HIGHLIGHT_WIDTH_FOCUS if focused else HIGHLIGHT_WIDTH
		outline.default_color = HIGHLIGHT_COLOR
		add_child(outline)

	for feature in tm.terrain_features:
		var fid = str(feature.get("id", ""))
		if fid == "":
			continue
		var lines: Array = mm.get_terrain_badges_11e(fid)
		if lines.is_empty():
			continue
		var label = Label.new()
		label.name = "Badge_%s" % fid
		label.text = " · ".join(PackedStringArray(lines))
		label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_constant_override("outline_size", 3)
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
		label.add_theme_color_override("font_color",
			BADGE_TRAP_COLOR if "BOOBY TRAP" in label.text else BADGE_RELIC_COLOR)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size = Vector2(180, 20)
		var fpos = feature.get("position", Vector2.ZERO)
		if fpos is Dictionary:
			fpos = Vector2(fpos.get("x", 0), fpos.get("y", 0))
		label.position = fpos + Vector2(-90, -10)
		add_child(label)
