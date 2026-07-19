extends CanvasLayer

# M4 pad action bar (PRPs/steam_deck_controller_support.md §4.3 Movement):
# a bottom-center strip of selectable action chips shown when the pad player
# presses A on a selected unit and that unit still has a decision to make
# (Movement: Normal / Advance / Fall Back / Remain Stationary / special
# actions). PadRouter owns all input routing while the bar is open — this
# node is deliberately dumb UI: open() / close() / move_highlight() /
# activate(). Sits above the hint bar (layer 90) and below the virtual
# cursor (layer 95). Hidden the moment the player switches back to KBM,
# matching PadHintBar.

const GlyphDB := preload("res://scripts/input/GlyphDB.gd")
const _UIConstants := preload("res://autoloads/UIConstants.gd")

var _panel: PanelContainer
var _column: VBoxContainer
var _title_label: Label
var _row: HBoxContainer
# Array of {id: String, label: String} in display order.
var _options: Array = []
var _highlight: int = 0


func _ready() -> void:
	layer = 92
	_build()
	_panel.visible = false
	InputDeviceManager.device_changed.connect(_on_device_changed)


func is_open() -> bool:
	return _panel.visible


func open(title: String, options: Array) -> void:
	if options.is_empty():
		return
	_options = options
	_highlight = 0
	_title_label.text = title
	_title_label.visible = title != ""
	_rebuild_chips()
	_panel.visible = InputDeviceManager.is_pad_active()


func close() -> void:
	_panel.visible = false
	_options = []
	_highlight = 0


func move_highlight(dir: int) -> void:
	if _options.is_empty():
		return
	_highlight = wrapi(_highlight + dir, 0, _options.size())
	_rebuild_chips()


func highlighted_id() -> String:
	if _options.is_empty() or _highlight >= _options.size():
		return ""
	return str(_options[_highlight].get("id", ""))


# Close the bar and return the highlighted option's id ("" when nothing open).
func activate() -> String:
	var id := highlighted_id()
	close()
	return id


func _on_device_changed(mode: int) -> void:
	if mode != InputDeviceManager.InputMode.PAD:
		close()


func _rebuild_chips() -> void:
	for child in _row.get_children():
		child.queue_free()
	for i in range(_options.size()):
		_row.add_child(_make_option_chip(str(_options[i].get("label", "")), i == _highlight))


func _make_option_chip(label_text: String, highlighted: bool) -> Control:
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	# Same chrome family as GlyphDB.make_chip; the highlighted chip gets the
	# bright border + lifted background so the selection reads at Deck size.
	if highlighted:
		style.bg_color = Color(0.25, 0.22, 0.10, 0.95)
		style.border_color = Color(0.95, 0.85, 0.35, 0.95)
		style.set_border_width_all(2)
	else:
		style.bg_color = Color(0.08, 0.08, 0.08, 0.85)
		style.border_color = Color(0.95, 0.95, 0.95, 0.35)
		style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	badge.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 15)
	var color: Color = _UIConstants.NEUTRAL_UI_PALE_WHITE
	label.add_theme_color_override("font_color", color if highlighted else Color(color, 0.75))
	badge.add_child(label)
	return badge


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "PadActionBarPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", style)
	# Sits directly above PadHintBar's strip (same bottom-center anchor,
	# larger inset so the two never overlap).
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 52)
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_panel)

	_column = VBoxContainer.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_theme_constant_override("separation", 4)
	_panel.add_child(_column)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 12)
	_title_label.add_theme_color_override("font_color", Color(_UIConstants.NEUTRAL_UI_PALE_WHITE, 0.6))
	_column.add_child(_title_label)

	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", 10)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.add_child(_row)
