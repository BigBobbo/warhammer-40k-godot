extends Node2D
class_name RulerTool

# RulerTool — standalone ruler bound to KEY_R (T31, doc §5).
#
# Press R to enter ruler mode. Click+drag draws a line; the distance in
# inches updates live near the cursor. ESC exits. By default the ruler is
# "public" (broadcast to peers in multiplayer); Shift+R toggles private.
#
# Public state for scenarios:
#   active : bool
#   is_private : bool
#   current_line : {from: Vector2, to: Vector2, distance_inches: float}
#
# Self-installs under /root/Main/BoardRoot via Main._ready() so it shares
# the board's transform.

var active: bool = false
var is_private: bool = false
var current_line: Dictionary = {}

var _drag_start: Vector2 = Vector2.ZERO
var _is_dragging: bool = false
var _label: Label = null
var _line2d: Line2D = null


func _ready() -> void:
	name = "RulerTool"
	z_index = 60

	_line2d = Line2D.new()
	_line2d.name = "Line"
	_line2d.width = 3.0
	_line2d.default_color = Color(0.95, 0.95, 0.95, 1.0)  # NEUTRAL_UI_PALE_WHITE
	_line2d.visible = false
	add_child(_line2d)

	_label = Label.new()
	_label.name = "Label"
	_label.visible = false
	_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
	_label.add_theme_font_size_override("font_size", 16)
	add_child(_label)


# T31 test seam: synthesize the R-key press path. Returns active.
func t31_synthesize_r_press(shift: bool = false) -> bool:
	if not active:
		set_active(true)
	is_private = shift
	return active


func t31_synthesize_escape() -> bool:
	set_active(false)
	return active


# Public path so callers can drive the ruler without going through input.
func set_active(value: bool) -> void:
	active = value
	if not active:
		_is_dragging = false
		current_line = {}
		_line2d.visible = false
		_label.visible = false


func begin_drag(world_pos: Vector2) -> void:
	if not active:
		return
	_is_dragging = true
	_drag_start = world_pos
	current_line = {
		"from": world_pos,
		"to": world_pos,
		"distance_inches": 0.0,
	}
	_render()


func update_drag(world_pos: Vector2) -> void:
	if not active or not _is_dragging:
		return
	var dist_px := _drag_start.distance_to(world_pos)
	var dist_inches := dist_px / float(Measurement.PX_PER_INCH)
	current_line = {
		"from": _drag_start,
		"to": world_pos,
		"distance_inches": dist_inches,
	}
	_render()


func end_drag() -> void:
	_is_dragging = false


func _render() -> void:
	if current_line.is_empty():
		_line2d.visible = false
		_label.visible = false
		return
	_line2d.points = PackedVector2Array([current_line.from, current_line.to])
	# Style: dashed look for private (gap pattern via texture), solid for
	# public. Line2D doesn't natively support dashes; we approximate by
	# modulating alpha differently so reviewers can distinguish in Tier B.
	if is_private:
		_line2d.default_color = Color(0.95, 0.95, 0.95, 0.6)
		_line2d.width = 2.0
	else:
		_line2d.default_color = Color(0.95, 0.95, 0.95, 1.0)
		_line2d.width = 3.0
	_line2d.visible = true
	_label.text = "%.1f\"" % float(current_line.distance_inches)
	_label.position = current_line.to + Vector2(8, -8)
	_label.visible = true
