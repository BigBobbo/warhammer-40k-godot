extends PanelContainer
class_name RollLogPanel

# RollLogPanel — persistent right-side roll log (T35, doc §7).
#
# Subscribes to DiceHistoryPanel.roll_recorded and renders each entry as a
# rich BBCode line via DiceHistoryPanel.format_entry_bbcode(). Hidden when
# no rolls have been recorded yet, so the right column isn't taken up by an
# empty dark box during phases like Deployment / Movement / Command.
#
# Self-installs as /root/Main/RollLogPanel via Main._ready().

const PANEL_WIDTH := 320.0
const PANEL_TOP_OFFSET := 80.0
const MAX_VISIBLE := 30
const ENTRY_FONT_SIZE := 12
const ENTRY_MIN_HEIGHT := 32.0


var _vbox: VBoxContainer = null
var _scroll: ScrollContainer = null


func _ready() -> void:
	name = "RollLogPanel"
	# IGNORE so this passive read-out never eats clicks on whatever sits
	# under the right 320px of the viewport (e.g. HUD_Right's buttons).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	# Hidden until the first roll lands — avoids an empty dark column
	# during phases that don't roll (Deployment / Command / Movement).
	visible = false
	_sync_viewport_size()
	var vp := get_viewport()
	if vp != null and not vp.is_connected("size_changed", _sync_viewport_size):
		vp.connect("size_changed", _sync_viewport_size)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scroll)

	_vbox = VBoxContainer.new()
	_vbox.name = "Entries"
	_vbox.add_theme_constant_override("separation", 2)
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_vbox)

	var dh = get_node_or_null("/root/DiceHistoryPanel")
	if dh != null:
		if dh.has_signal("roll_recorded") and not dh.is_connected("roll_recorded", _on_roll_recorded):
			dh.connect("roll_recorded", _on_roll_recorded)
		# Backfill any history that already exists (e.g. after a load).
		for entry in dh.get_history():
			_append_entry(entry, dh)
		_refresh_visibility()


func _on_roll_recorded(entry: Dictionary) -> void:
	var dh = get_node_or_null("/root/DiceHistoryPanel")
	if dh == null:
		return
	_append_entry(entry, dh)
	# Trim to MAX_VISIBLE
	while _vbox.get_child_count() > MAX_VISIBLE:
		_vbox.get_child(0).queue_free()
	_refresh_visibility()
	call_deferred("_scroll_to_bottom")


func _append_entry(entry: Dictionary, dh) -> void:
	# Use the autoload's BBCode formatter so the line matches the in-game
	# dice log everywhere else (colored dice, R/P/phase header, etc.).
	var bbcode := ""
	if dh != null and dh.has_method("format_entry_bbcode"):
		bbcode = dh.format_entry_bbcode(entry)
	if bbcode.is_empty():
		return  # Skip non-roll contexts (formatter returns "" for filtered noise).
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.scroll_active = false
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("normal_font_size", ENTRY_FONT_SIZE)
	lbl.add_theme_font_size_override("bold_font_size", ENTRY_FONT_SIZE)
	lbl.custom_minimum_size = Vector2(0, ENTRY_MIN_HEIGHT)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.text = bbcode
	_vbox.add_child(lbl)


func _refresh_visibility() -> void:
	visible = _vbox != null and _vbox.get_child_count() > 0


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
