extends Node2D
class_name TerrainCoverOverlay

# TerrainCoverOverlay — renders a small shield glyph + cover-type label at
# the centroid of every terrain piece (T07, doc §6).
#
# Each icon is a child Node2D named `TerrainCoverIcon_<terrain_id>` so
# scenarios can assert its position and label via NodePath.
#
# Cover type derivation (matches 10e rules):
#   - "obscuring" trait OR height_category == "tall"  -> "LB"  (line block)
#   - height_category == "medium"                     -> "+2"  (heavy)
#   - everything else                                 -> "+1"  (light)
#
# Self-installs as a child of /root/Main/BoardRoot via a one-line bootstrap
# in Main._ready().

const ICON_SIZE := 28.0


func _ready() -> void:
	name = "TerrainCoverOverlay"
	z_index = 50  # Above terrain polygons, below tokens.
	_build_icons()
	var tm = get_node_or_null("/root/TerrainManager")
	if tm != null and tm.has_signal("terrain_loaded"):
		if not tm.is_connected("terrain_loaded", _on_terrain_loaded):
			tm.connect("terrain_loaded", _on_terrain_loaded)


func _on_terrain_loaded(_features: Array) -> void:
	_rebuild_icons()


func _rebuild_icons() -> void:
	for child in get_children():
		child.queue_free()
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
		var centroid: Vector2 = _centroid(piece)
		var label_text: String = _cover_label(piece)
		var icon := _make_icon(id_str, centroid, label_text)
		add_child(icon)


func _centroid(piece: Dictionary) -> Vector2:
	# Prefer the explicit center position; fall back to polygon centroid.
	if piece.has("position") and typeof(piece["position"]) == TYPE_VECTOR2:
		return piece["position"]
	var poly = piece.get("polygon", [])
	if typeof(poly) != TYPE_ARRAY or poly.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for p in poly:
		if typeof(p) == TYPE_VECTOR2:
			sum += p
	return sum / float(poly.size())


func _cover_label(piece: Dictionary) -> String:
	var traits = piece.get("traits", [])
	var height = str(piece.get("height_category", ""))
	if typeof(traits) == TYPE_ARRAY and traits.has("obscuring"):
		return "LB"
	if height == "tall":
		return "LB"
	if height == "medium":
		return "+2"
	return "+1"


func _make_icon(terrain_id: String, world_pos: Vector2, label_text: String) -> Node2D:
	var icon := Node2D.new()
	icon.name = "TerrainCoverIcon_%s" % terrain_id
	icon.position = world_pos
	icon.modulate = Color(1, 1, 1, 0.9)

	# A simple high-contrast background so the label is readable on terrain.
	# Use a Polygon2D shield approximation (rectangle with chamfered top).
	var bg := Polygon2D.new()
	bg.name = "Shield"
	var half := ICON_SIZE * 0.5
	bg.polygon = PackedVector2Array([
		Vector2(-half, -half * 0.6),
		Vector2( half, -half * 0.6),
		Vector2( half,  half * 0.4),
		Vector2(    0,  half),
		Vector2(-half,  half * 0.4),
	])
	bg.color = Color(0.05, 0.05, 0.08, 0.85)
	icon.add_child(bg)

	var label := Label.new()
	label.name = "Label"
	label.text = label_text
	label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
	label.add_theme_font_size_override("font_size", 14)
	# Center the label on the icon. Labels are Controls; position is top-left.
	label.position = Vector2(-half + 4, -half * 0.55)
	label.size = Vector2(ICON_SIZE - 8, ICON_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_child(label)

	return icon
