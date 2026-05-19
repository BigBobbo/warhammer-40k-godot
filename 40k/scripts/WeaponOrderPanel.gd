extends PanelContainer

# WeaponOrderPanel — side-anchored variant of WeaponOrderDialog (T06, doc §3).
#
# The existing WeaponOrderDialog extends AcceptDialog and centers itself,
# covering the board. This Control is the side-panel alternative: anchored
# to the right column at anchor_left >= 0.6 so the board stays visible.
#
# Public API (mirrors the dialog's contract enough for tests):
#   open_for(weapon_assignments: Array, weapon_data: Dictionary)
#   close()
#   signal weapon_order_confirmed(weapon_order, fast_roll)
#
# Self-installs as /root/Main/WeaponOrderPanel via Main._ready().

signal weapon_order_confirmed(weapon_order: Array, fast_roll: bool)

const PANEL_WIDTH := 360.0

var weapon_assignments: Array = []
var weapon_data: Dictionary = {}
var weapon_order: Array = []
var _vbox: VBoxContainer = null
var _list_vbox: VBoxContainer = null


func _ready() -> void:
	name = "WeaponOrderPanel"
	visible = false
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_sync_viewport_size()
	var vp := get_viewport()
	if vp != null and not vp.is_connected("size_changed", _sync_viewport_size):
		vp.connect("size_changed", _sync_viewport_size)

	_vbox = VBoxContainer.new()
	_vbox.name = "Body"
	_vbox.add_theme_constant_override("separation", 6)
	add_child(_vbox)

	var title := Label.new()
	title.name = "Title"
	title.text = "Weapon Order"
	title.add_theme_font_size_override("font_size", 18)
	_vbox.add_child(title)

	_list_vbox = VBoxContainer.new()
	_list_vbox.name = "WeaponList"
	_vbox.add_child(_list_vbox)

	var btns := HBoxContainer.new()
	btns.name = "Buttons"
	_vbox.add_child(btns)
	var start := Button.new()
	start.name = "StartSequence"
	start.text = "Start Sequence"
	start.pressed.connect(_on_start_pressed)
	btns.add_child(start)
	var cancel := Button.new()
	cancel.name = "Cancel"
	cancel.text = "Cancel"
	cancel.pressed.connect(close)
	btns.add_child(cancel)


func _sync_viewport_size() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vp_size := vp.get_visible_rect().size
	# Anchor against right edge with offset_top below the phase bar.
	position = Vector2(vp_size.x - PANEL_WIDTH, 100.0)
	size = Vector2(PANEL_WIDTH, vp_size.y - 200.0)


func open_for(assignments: Array, data: Dictionary) -> void:
	weapon_assignments = assignments.duplicate()
	weapon_data = data.duplicate(true)
	weapon_order = []
	for c in _list_vbox.get_children():
		c.queue_free()
	for a in assignments:
		var wid: String = ""
		if typeof(a) == TYPE_DICTIONARY:
			wid = str(a.get("weapon_id", a.get("id", "")))
		else:
			wid = str(a)
		weapon_order.append(wid)
		var row := Label.new()
		row.name = "Row_%s" % wid
		row.text = str(data.get(wid, {}).get("name", wid))
		_list_vbox.add_child(row)
	visible = true


func close() -> void:
	visible = false


func _on_start_pressed() -> void:
	emit_signal("weapon_order_confirmed", weapon_order, false)
	close()


# Test seam — gives the anchor_left equivalent for a Control that's
# explicitly positioned. Tier A uses position.x / viewport.size.x to derive
# the same notion ("panel lives in the right 40%").
func t06_anchor_left_ratio() -> float:
	var vp := get_viewport()
	if vp == null:
		return 0.0
	var vp_w := vp.get_visible_rect().size.x
	if vp_w <= 0.0:
		return 0.0
	return position.x / vp_w


func t06_panel_rect() -> Rect2:
	return Rect2(position, size)
