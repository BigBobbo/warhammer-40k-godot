extends Node2D
class_name TerrainCoverOverlay

# TerrainCoverOverlay — renders a small shield glyph + cover-type label at
# the centroid of every terrain piece (T07, doc §6).
#
# Each icon is a child Node2D named `TerrainCoverIcon_<terrain_id>`, placed at
# the piece's polygon centroid (board px), with a `Shield` Polygon2D and a
# `Label` child, so scenarios can assert its position and text via NodePath.
#
# Cover type: TerrainManager.cover_type_of(piece) — the piece's 11e terrain
# category (core rules 13.02-13.05) on the doc's light/heavy/blocking ladder:
#   exposed -> "+1"   light -> "+2"   dense -> "LB"
#
# Screen-space size: the board is drawn through BoardRoot's transform (camera
# zoom 0.1-3.0 plus 90-degree board rotations), so an icon sized in board px
# shrank to a few unreadable pixels at the fitted whole-board view. Each icon
# is counter-scaled and counter-rotated whenever that transform changes, so
# the glyph keeps the same upright on-screen size at every zoom while its
# position stays pinned to the centroid.
#
# Draw order: z_index 2 puts the icons above the terrain art (TerrainVisual,
# z -8 with children up to +4) and the deployment zones (-5), but below every
# gameplay overlay (movement ranges 3, threat 4, engagement 5) and the tokens
# (10), so a glyph never hides a model or a range ring.
#
# Self-installs as a child of /root/Main/BoardRoot via
# Main._install_design_guidelines_overlays().

## On-screen shield size in pixels (constant at every camera zoom).
const ICON_WIDTH := 30.0
const ICON_HEIGHT := 34.0
const LABEL_FONT_SIZE := 17
const ICON_ALPHA := 0.95

var _applied_scale := -1.0
var _applied_rotation := 0.0


func _ready() -> void:
	name = "TerrainCoverOverlay"
	z_index = 2  # Above terrain art and deployment zones, below overlays + tokens.
	_build_icons()
	var tm = get_node_or_null("/root/TerrainManager")
	if tm != null and tm.has_signal("terrain_loaded"):
		if not tm.is_connected("terrain_loaded", _on_terrain_loaded):
			tm.connect("terrain_loaded", _on_terrain_loaded)

	# The cover glyph chips (LB / +2 / +1) are OFF by default — they add a lot of
	# on-board clutter. A player opts in via Settings > Visual > "Terrain Cover
	# Labels", which flips SettingsService.show_terrain_cover_labels and fires the
	# signal below so the whole overlay shows/hides live without a board reload.
	var ss = get_node_or_null("/root/SettingsService")
	if ss != null:
		visible = ss.show_terrain_cover_labels
		if ss.has_signal("terrain_cover_labels_changed"):
			if not ss.is_connected("terrain_cover_labels_changed", _on_cover_labels_changed):
				ss.connect("terrain_cover_labels_changed", _on_cover_labels_changed)


func _process(_delta: float) -> void:
	# Only the on-screen transform needs per-frame care, and only while shown.
	if is_visible_in_tree():
		_sync_screen_transform()


func _on_cover_labels_changed(enabled: bool) -> void:
	visible = enabled
	if enabled:
		_sync_screen_transform(true)
	print("[TerrainCoverOverlay] cover labels %s (%d icons)" % ["shown" if enabled else "hidden", get_child_count()])


func _on_terrain_loaded(_features: Array) -> void:
	_rebuild_icons()


func _rebuild_icons() -> void:
	# Free the old icons NOW (not queue_free): the new ones reuse the same
	# TerrainCoverIcon_<id> names, and a still-queued sibling would push them
	# onto an auto-renamed "@Node2D@N" path that scenarios cannot address.
	for child in get_children():
		remove_child(child)
		child.free()
	_build_icons()


func _build_icons() -> void:
	var tm = get_node_or_null("/root/TerrainManager")
	if tm == null:
		return
	var features: Array = tm.terrain_features
	for piece in features:
		if typeof(piece) != TYPE_DICTIONARY:
			continue
		var id_str: String = str(piece.get("id", ""))
		if id_str == "":
			continue
		var centroid: Vector2 = centroid_of(piece)
		var label_text: String = tm.cover_type_of(piece)
		var icon := _make_icon(id_str, centroid, label_text)
		add_child(icon)
	# New icons start at scale 1 — re-apply the screen transform next sync.
	_applied_scale = -1.0
	if is_inside_tree() and is_visible_in_tree():
		_sync_screen_transform(true)
	print("[TerrainCoverOverlay] built %d cover icons" % get_child_count())


## Geometric centre of a terrain footprint: the polygon's AREA centroid
## (shoelace), which is what the converted layouts author as `position`.
## The plain vertex average is NOT the centroid of an L-shaped corner ruin or
## a trapezoid (up to ~1.2" off on the 11e layouts), so it is used only as
## the last resort for a degenerate (zero-area) polygon.
static func centroid_of(piece: Dictionary) -> Vector2:
	var pts := PackedVector2Array()
	var poly = piece.get("polygon", [])
	if poly is PackedVector2Array:
		pts = poly
	elif poly is Array:
		for p in poly:
			if p is Vector2:
				pts.append(p)
			elif p is Dictionary:
				pts.append(Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0))))
	if pts.size() >= 3:
		var twice_area := 0.0
		var acc := Vector2.ZERO
		for i in range(pts.size()):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			var cross := a.x * b.y - b.x * a.y
			twice_area += cross
			acc += (a + b) * cross
		if absf(twice_area) > 0.0001:
			return acc / (3.0 * twice_area)
	var pos = piece.get("position", null)
	if pos is Vector2:
		return pos
	if pts.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for p in pts:
		sum += p
	return sum / float(pts.size())


## Keep every icon the same upright size on screen: undo BoardRoot's zoom and
## rotation on the icon itself (its position — the centroid — is untouched).
func _sync_screen_transform(force: bool = false) -> void:
	var xf := get_global_transform_with_canvas()
	var screen_scale := absf(xf.get_scale().x)
	var screen_rotation := xf.get_rotation()
	if screen_scale < 0.0001:
		return
	if not force and is_equal_approx(screen_scale, _applied_scale) and is_equal_approx(screen_rotation, _applied_rotation):
		return
	_applied_scale = screen_scale
	_applied_rotation = screen_rotation
	var inv := 1.0 / screen_scale
	for icon in get_children():
		if icon is Node2D:
			icon.scale = Vector2(inv, inv)
			icon.rotation = -screen_rotation


func _make_icon(terrain_id: String, world_pos: Vector2, label_text: String) -> Node2D:
	var icon := Node2D.new()
	icon.name = "TerrainCoverIcon_%s" % terrain_id
	icon.position = world_pos
	icon.modulate = Color(1, 1, 1, ICON_ALPHA)
	icon.set_meta("cover_type", label_text)

	# Neutral UI slot (doc §9), looked up at runtime: a compile-time reference
	# to the autoload breaks `godot -s` test scripts that load this class
	# before the autoloads are registered.
	var ink := Color(0.95, 0.95, 0.95, 1.0)
	var uic = get_node_or_null("/root/UIConstants")
	if uic != null:
		ink = uic.NEUTRAL_UI_PALE_WHITE
	var hw := ICON_WIDTH * 0.5
	var hh := ICON_HEIGHT * 0.5
	var chamfer := 3.0
	# Heater shield: flat top with chamfered corners, straight sides to just
	# below the middle, then tapering to a point.
	var outline := PackedVector2Array([
		Vector2(-hw, -hh + chamfer),
		Vector2(-hw + chamfer, -hh),
		Vector2( hw - chamfer, -hh),
		Vector2( hw, -hh + chamfer),
		Vector2( hw,  hh * 0.18),
		Vector2(  0,  hh),
		Vector2(-hw,  hh * 0.18),
	])

	# Dark plate so the glyph reads on every terrain texture.
	var bg := Polygon2D.new()
	bg.name = "Shield"
	bg.polygon = outline
	bg.color = Color(0.06, 0.06, 0.09, 0.92)
	icon.add_child(bg)

	# Pale rim: separates the plate from dark ruins and from the board.
	var rim := Line2D.new()
	rim.name = "Rim"
	rim.points = outline
	rim.closed = true
	rim.width = 2.0
	rim.default_color = Color(ink.r, ink.g, ink.b, 0.85)
	rim.joint_mode = Line2D.LINE_JOINT_ROUND
	icon.add_child(rim)

	var label := Label.new()
	label.name = "Label"
	label.text = label_text
	label.add_theme_color_override("font_color", ink)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	# Labels are Controls (position = top-left): centre the text on the
	# shield's broad upper part rather than on its bounding box.
	label.position = Vector2(-hw, -hh)
	label.size = Vector2(ICON_WIDTH, ICON_HEIGHT * 0.82)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_child(label)

	return icon
