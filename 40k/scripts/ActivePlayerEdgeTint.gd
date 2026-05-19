extends Control
class_name ActivePlayerEdgeTint

# ActivePlayerEdgeTint — outer 4px frame of the play area tinted in the
# active player's UIConstants slot color (T25, doc §4).
#
# Implemented as a Control covering the full viewport with a 4px ring
# drawn in _draw. Listens to PhaseManager.phase_changed; when no signal
# exists for player flips, phase transitions cover the practical case
# (active_player changes on phase 12 -> 6).
#
# Self-installs as a child of /root/Main via Main._ready().

const FRAME_THICKNESS := 4.0

var _current_color: Color = Color(1, 1, 1, 1)


func _ready() -> void:
	name = "EdgeTint"
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # never block input
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Parents that are CanvasLayer (Main is) don't propagate a layout size to
	# children, so set size explicitly and follow viewport resizes.
	_sync_viewport_size()
	var vp := get_viewport()
	if vp != null and not vp.is_connected("size_changed", _sync_viewport_size):
		vp.connect("size_changed", _sync_viewport_size)

	# Listen for transitions. Repaint runs on every phase change because the
	# project has no dedicated active_player_changed signal.
	var pm = get_node_or_null("/root/PhaseManager")
	if pm != null and pm.has_signal("phase_changed"):
		if not pm.is_connected("phase_changed", _on_phase_changed):
			pm.connect("phase_changed", _on_phase_changed)
	_refresh_color()


func _sync_viewport_size() -> void:
	var vp := get_viewport()
	if vp != null:
		size = vp.get_visible_rect().size
		queue_redraw()


func _on_phase_changed(_new_phase) -> void:
	_refresh_color()


func _refresh_color() -> void:
	var uic = get_node_or_null("/root/UIConstants")
	var gs = get_node_or_null("/root/GameState")
	if uic == null or gs == null:
		_current_color = Color(1, 1, 1, 1)
		queue_redraw()
		return
	var active: int = int(gs.state.get("meta", {}).get("active_player", 1))
	_current_color = uic.FRIENDLY_PLAYER_TEAL if active == 1 else uic.ENEMY_PLAYER_MAGENTA
	# Mirror the swatch onto modulate so scenarios can assert it directly.
	modulate = _current_color
	queue_redraw()


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	# Top
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, FRAME_THICKNESS)),
		_current_color, true)
	# Bottom
	draw_rect(Rect2(Vector2(rect.position.x, rect.size.y - FRAME_THICKNESS),
		Vector2(rect.size.x, FRAME_THICKNESS)), _current_color, true)
	# Left
	draw_rect(Rect2(rect.position, Vector2(FRAME_THICKNESS, rect.size.y)),
		_current_color, true)
	# Right
	draw_rect(Rect2(Vector2(rect.size.x - FRAME_THICKNESS, rect.position.y),
		Vector2(FRAME_THICKNESS, rect.size.y)), _current_color, true)
