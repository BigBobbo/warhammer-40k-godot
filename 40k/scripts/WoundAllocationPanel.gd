extends PanelContainer

# WoundAllocationPanel — side-anchored variant of WoundAllocationOverlay
# (T21, doc §3). Same pattern as T06/T20.
#
# Public API:
#   open_for(target_unit_id, wounds_to_allocate)
#   close()
#   signal allocation_committed(unit_id, allocations)
#
# Self-installs as /root/Main/WoundAllocationPanel.

signal allocation_committed(unit_id: String, allocations: Array)

const PANEL_WIDTH := 340.0

var target_unit_id: String = ""
var wounds_to_allocate: int = 0
var _vbox: VBoxContainer = null
var _summary_label: Label = null


func _ready() -> void:
	name = "WoundAllocationPanel"
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
	title.text = "Allocate Wounds"
	title.add_theme_font_size_override("font_size", 18)
	_vbox.add_child(title)

	_summary_label = Label.new()
	_summary_label.name = "Summary"
	_summary_label.text = ""
	_vbox.add_child(_summary_label)

	var btns := HBoxContainer.new()
	btns.name = "Buttons"
	_vbox.add_child(btns)
	var commit_btn := Button.new()
	commit_btn.name = "Commit"
	commit_btn.text = "Allocate"
	commit_btn.pressed.connect(_on_commit_pressed)
	btns.add_child(commit_btn)


func _sync_viewport_size() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vp_size := vp.get_visible_rect().size
	position = Vector2(vp_size.x - PANEL_WIDTH, 100.0)
	size = Vector2(PANEL_WIDTH, 320.0)


func open_for(unit_id: String, wounds: int) -> void:
	target_unit_id = unit_id
	wounds_to_allocate = wounds
	_summary_label.text = "Target: %s\nWounds: %d" % [unit_id, wounds]
	visible = true


func close() -> void:
	visible = false


func _on_commit_pressed() -> void:
	emit_signal("allocation_committed", target_unit_id, [])
	close()


func t21_anchor_left_ratio() -> float:
	var vp := get_viewport()
	if vp == null:
		return 0.0
	var vp_w := vp.get_visible_rect().size.x
	if vp_w <= 0.0:
		return 0.0
	return position.x / vp_w
