extends Button

# EndPhaseButton — canonical bottom-right End-Phase action (T23, doc §3/§4).
#
# Single button living at /root/Main/EndPhaseButton, anchored to a fixed
# bottom-right pixel position so the player's eye always lands here
# regardless of which phase is active. Clicking emits end_phase_requested;
# downstream listeners (PhaseManager / per-phase scripts) handle the
# semantic action. Position constants are documented so reviewers and
# scenarios can assert against them.

signal end_phase_requested()

const REFERENCE_OFFSET_FROM_RIGHT := 200
const REFERENCE_OFFSET_FROM_BOTTOM := 60


func _ready() -> void:
	name = "EndPhaseButton"
	text = "End Phase"
	custom_minimum_size = Vector2(160, 40)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_sync_position()
	var vp := get_viewport()
	if vp != null and not vp.is_connected("size_changed", _sync_position):
		vp.connect("size_changed", _sync_position)
	pressed.connect(_on_pressed)


func _sync_position() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vp_size: Vector2 = vp.get_visible_rect().size
	position = Vector2(
		vp_size.x - float(REFERENCE_OFFSET_FROM_RIGHT),
		vp_size.y - float(REFERENCE_OFFSET_FROM_BOTTOM),
	)


func _on_pressed() -> void:
	emit_signal("end_phase_requested")
	var pm = get_node_or_null("/root/PhaseManager")
	if pm != null and pm.has_method("advance_phase"):
		pm.advance_phase()
	elif pm != null and pm.has_method("end_current_phase"):
		pm.end_current_phase()


# T23 audit helper: returns the offset from viewport bottom-right.
func t23_anchor_offset() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2.ZERO
	var vp_size: Vector2 = vp.get_visible_rect().size
	return Vector2(vp_size.x - position.x, vp_size.y - position.y)
