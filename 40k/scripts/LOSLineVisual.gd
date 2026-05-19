extends Node2D
class_name LOSLineVisual

# LOSLineVisual — single LOS line between shooter and target with color
# coded by visibility state (T11, doc §6).
#
# compute_line(shooter_id, target_id) -> Dictionary returns:
#   {from: Vector2, to: Vector2, color_slot: String, los_state: String}
# color_slot is one of CONFIRMED_GREEN / MARGINAL_YELLOW / INVALID_RED.
# los_state is "clear" / "obscured" / "blocked".
#
# Stored on current_line; null when nothing valid is hovered. Renders a
# single Line2D child between the two centers.

var current_line = null

var _line2d: Line2D = null


func _ready() -> void:
	name = "LOSLineVisual"
	z_index = 6  # Above tokens, below dialogs.
	_line2d = Line2D.new()
	_line2d.name = "Line"
	_line2d.width = 2.0
	_line2d.visible = false
	add_child(_line2d)


func compute_line(shooter_id: String, target_id: String) -> Variant:
	current_line = null
	_line2d.visible = false
	var gs = get_node_or_null("/root/GameState")
	var uic = get_node_or_null("/root/UIConstants")
	if gs == null or uic == null:
		return null
	var shooter = gs.get_unit(shooter_id)
	var target = gs.get_unit(target_id)
	if typeof(shooter) != TYPE_DICTIONARY or shooter.is_empty():
		return null
	if typeof(target) != TYPE_DICTIONARY or target.is_empty():
		return null

	var from_pt: Vector2 = _first_model_position(shooter)
	var to_pt: Vector2 = _first_model_position(target)
	if from_pt == Vector2.INF or to_pt == Vector2.INF:
		return null

	var los_state := _resolve_los_state(shooter_id, target_id, from_pt, to_pt)
	var color_slot: String
	var color: Color
	match los_state:
		"clear":
			color_slot = "CONFIRMED_GREEN"
			color = uic.CONFIRMED_GREEN
		"obscured":
			color_slot = "MARGINAL_YELLOW"
			color = uic.MARGINAL_YELLOW
		_:
			color_slot = "INVALID_RED"
			color = uic.INVALID_RED

	current_line = {
		"from": from_pt,
		"to": to_pt,
		"color_slot": color_slot,
		"los_state": los_state,
	}
	_line2d.points = PackedVector2Array([from_pt, to_pt])
	_line2d.default_color = color
	_line2d.visible = true
	return current_line


func clear_line() -> void:
	current_line = null
	_line2d.visible = false


# T11: best-effort LOS lookup. Walks (in priority order):
#   - EnhancedLineOfSight.check_line_of_sight(...) if available
#   - LineOfSightManager.check_los(from, to) if available
# Returns "clear" / "obscured" / "blocked".
func _resolve_los_state(shooter_id: String, target_id: String,
		from_pt: Vector2, to_pt: Vector2) -> String:
	var elos = get_node_or_null("/root/EnhancedLineOfSight")
	if elos != null and elos.has_method("check_line_of_sight"):
		var r = elos.check_line_of_sight(shooter_id, target_id)
		if typeof(r) == TYPE_DICTIONARY:
			if r.get("blocked", false):
				return "blocked"
			if r.get("obscured", r.get("has_cover", false)):
				return "obscured"
			return "clear"
		if typeof(r) == TYPE_BOOL:
			return "clear" if r else "blocked"
	var losmgr = get_node_or_null("/root/LineOfSightManager")
	if losmgr != null and losmgr.has_method("check_los"):
		if losmgr.check_los(from_pt, to_pt):
			# Check terrain between for "obscured" via TerrainManager.
			if _has_cover_terrain_between(from_pt, to_pt):
				return "obscured"
			return "clear"
		return "blocked"
	# No LOS systems available — fall back to a geometric check against
	# terrain pieces with "obscuring" trait or height == "tall".
	if _has_blocking_terrain_between(from_pt, to_pt):
		return "blocked"
	if _has_cover_terrain_between(from_pt, to_pt):
		return "obscured"
	return "clear"


func _has_blocking_terrain_between(from_pt: Vector2, to_pt: Vector2) -> bool:
	var tm = get_node_or_null("/root/TerrainManager")
	if tm == null:
		return false
	for piece in tm.terrain_features:
		if typeof(piece) != TYPE_DICTIONARY:
			continue
		var traits = piece.get("traits", [])
		var height = str(piece.get("height_category", ""))
		var blocks = (typeof(traits) == TYPE_ARRAY and traits.has("obscuring")) \
			or height == "tall"
		if not blocks:
			continue
		if _segment_intersects_polygon(from_pt, to_pt, piece.get("polygon", [])):
			return true
	return false


func _has_cover_terrain_between(from_pt: Vector2, to_pt: Vector2) -> bool:
	var tm = get_node_or_null("/root/TerrainManager")
	if tm == null:
		return false
	for piece in tm.terrain_features:
		if typeof(piece) != TYPE_DICTIONARY:
			continue
		var traits = piece.get("traits", [])
		var height = str(piece.get("height_category", ""))
		if (typeof(traits) == TYPE_ARRAY and traits.has("obscuring")) or height == "tall":
			continue  # blocking handled separately
		if _segment_intersects_polygon(from_pt, to_pt, piece.get("polygon", [])):
			return true
	return false


func _segment_intersects_polygon(a: Vector2, b: Vector2, poly) -> bool:
	if typeof(poly) != TYPE_ARRAY or poly.size() < 2:
		return false
	for i in range(poly.size()):
		var p0 = poly[i]
		var p1 = poly[(i + 1) % poly.size()]
		if typeof(p0) != TYPE_VECTOR2 or typeof(p1) != TYPE_VECTOR2:
			continue
		if Geometry2D.segment_intersects_segment(a, b, p0, p1) != null:
			return true
	return false


func _first_model_position(unit: Dictionary) -> Vector2:
	for m in unit.get("models", []):
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var pos = m.get("position", null)
		if typeof(pos) == TYPE_VECTOR2:
			return pos
		if typeof(pos) == TYPE_DICTIONARY and pos.has("x") and pos.has("y"):
			return Vector2(float(pos.x), float(pos.y))
	return Vector2.INF
