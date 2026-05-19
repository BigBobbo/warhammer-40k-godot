extends Node2D
class_name MovementRangeVisual

# MovementRangeVisual — two-layer range shading for a selected unit (T28,
# doc §5).
#
# Inner layer: filled disc at the unit's M radius, 12% alpha, drawn in
#   UIConstants.CONFIRMED_GREEN.
# Outer layer: thin outline ring at (M + selected_weapon_range_inches),
#   drawn in UIConstants.MARGINAL_YELLOW.
#
# Public state for scenarios:
#   inner_fill_radius_px : float
#   outer_outline_radius_px : float
#   set_from(unit_id, weapon_range_inches)
#
# Self-installs under /root/Main/BoardRoot via Main._ready().

var inner_fill_radius_px: float = 0.0
var outer_outline_radius_px: float = 0.0
var _unit_id: String = ""


func _ready() -> void:
	name = "MovementRangeVisual"
	z_index = 3


func set_from(unit_id: String, weapon_range_inches: float = 0.0) -> bool:
	_unit_id = unit_id
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return false
	var unit = gs.get_unit(unit_id)
	if typeof(unit) != TYPE_DICTIONARY or unit.is_empty():
		return false
	var move_inches: float = float(unit.get("meta", {}).get("stats", {}).get("move", 6.0))
	var px_per_inch: float = float(Measurement.PX_PER_INCH)
	inner_fill_radius_px = move_inches * px_per_inch
	outer_outline_radius_px = (move_inches + weapon_range_inches) * px_per_inch
	# Anchor on the unit's first model position.
	for m in unit.get("models", []):
		var pos = m.get("position", null)
		if typeof(pos) == TYPE_VECTOR2:
			position = pos
			break
		if typeof(pos) == TYPE_DICTIONARY and pos.has("x") and pos.has("y"):
			position = Vector2(float(pos.x), float(pos.y))
			break
	queue_redraw()
	return true


func clear() -> void:
	_unit_id = ""
	inner_fill_radius_px = 0.0
	outer_outline_radius_px = 0.0
	queue_redraw()


func _draw() -> void:
	if inner_fill_radius_px <= 0.0:
		return
	var uic = get_node_or_null("/root/UIConstants")
	var green: Color = (uic.CONFIRMED_GREEN if uic != null else Color(0.2, 0.85, 0.3, 1.0))
	var yellow: Color = (uic.MARGINAL_YELLOW if uic != null else Color(0.95, 0.85, 0.15, 1.0))
	var fill := green
	fill.a = 0.12
	draw_circle(Vector2.ZERO, inner_fill_radius_px, fill)
	if outer_outline_radius_px > inner_fill_radius_px:
		draw_arc(Vector2.ZERO, outer_outline_radius_px, 0.0, TAU, 64, yellow, 2.0, true)
