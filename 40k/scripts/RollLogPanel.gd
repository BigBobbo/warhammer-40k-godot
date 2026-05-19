extends PanelContainer

# RollLogPanel — persistent right-side roll log (T35, doc §7).
#
# Subscribes to DiceHistoryPanel.roll_recorded and renders each entry in a
# scrolling VBox. Always visible by default (the spec calls for persistent
# visibility, no toggle).
#
# Format: <timestamp> · <attacker> → <target> · <result>
#
# Self-installs as /root/Main/RollLogPanel via Main._ready().

const PANEL_WIDTH := 320.0
const PANEL_TOP_OFFSET := 80.0
const MAX_VISIBLE := 30


var _vbox: VBoxContainer = null
var _scroll: ScrollContainer = null


func _ready() -> void:
	name = "RollLogPanel"
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_sync_viewport_size()
	var vp := get_viewport()
	if vp != null and not vp.is_connected("size_changed", _sync_viewport_size):
		vp.connect("size_changed", _sync_viewport_size)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_vbox = VBoxContainer.new()
	_vbox.name = "Entries"
	_vbox.add_theme_constant_override("separation", 2)
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_vbox)

	var dh = get_node_or_null("/root/DiceHistoryPanel")
	if dh != null:
		if dh.has_signal("roll_recorded") and not dh.is_connected("roll_recorded", _on_roll_recorded):
			dh.connect("roll_recorded", _on_roll_recorded)
		# Backfill from existing entries.
		for entry in dh.entries:
			_append_entry_label(entry)


func _on_roll_recorded(_raw: Dictionary) -> void:
	# Re-pull the latest structured entry from the autoload — the raw
	# dict has phase-specific keys; entries[-1] is the normalized view.
	var dh = get_node_or_null("/root/DiceHistoryPanel")
	if dh == null or dh.entries.is_empty():
		return
	_append_entry_label(dh.entries[-1])
	# Trim to MAX_VISIBLE
	while _vbox.get_child_count() > MAX_VISIBLE:
		_vbox.get_child(0).queue_free()
	# Defer scroll-to-bottom to next frame after layout.
	call_deferred("_scroll_to_bottom")


func _append_entry_label(entry: Dictionary) -> void:
	var lbl := Label.new()
	lbl.text = "%d · %s → %s · %s" % [
		int(entry.get("timestamp", 0)),
		str(entry.get("attacker", "—")),
		str(entry.get("target", "—")),
		str(entry.get("result", "")),
	]
	lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(lbl)


func _scroll_to_bottom() -> void:
	if _scroll == null:
		return
	var vbar := _scroll.get_v_scroll_bar()
	if vbar != null:
		_scroll.scroll_vertical = int(vbar.max_value)


func _sync_viewport_size() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vp_size := vp.get_visible_rect().size
	position = Vector2(vp_size.x - PANEL_WIDTH, PANEL_TOP_OFFSET)
	size = Vector2(PANEL_WIDTH, vp_size.y - PANEL_TOP_OFFSET)
	if _scroll != null:
		_scroll.custom_minimum_size = size
