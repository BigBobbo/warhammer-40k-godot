extends PanelContainer
class_name ArmyPanel

# Army overview panel showing all units for both players.
# Each row: color swatch (clickable) | unit name | editable label | type tag
# Grouped by player with faction name headers.
# Hotkey: KEY_U — wired in Main.gd _input()

const WhiteDwarfThemeData = preload("res://scripts/WhiteDwarfTheme.gd")

signal panel_closed
signal unit_visual_changed(unit_id: String)

var _label_edits: Dictionary = {}  # unit_id -> LineEdit


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	name = "ArmyPanel"

	# Full-screen semi-transparent overlay
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0

	var overlay_style = StyleBoxFlat.new()
	overlay_style.bg_color = Color(0.0, 0.0, 0.0, 0.75)
	add_theme_stylebox_override("panel", overlay_style)

	# Center container
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Main panel
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(650, 500)
	WhiteDwarfThemeData.apply_to_panel(panel)
	center.add_child(panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "ARMY OVERVIEW"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	vbox.add_child(title)

	var sep = HSeparator.new()
	sep.add_theme_color_override("separator", WhiteDwarfThemeData.WH_GOLD)
	vbox.add_child(sep)

	# Scroll area for unit rows
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	scroll.add_child(content)

	# Build rows for each player
	for player in [1, 2]:
		_build_player_section(content, player)

	# Close button
	var sep2 = HSeparator.new()
	sep2.add_theme_color_override("separator", WhiteDwarfThemeData.WH_GOLD)
	vbox.add_child(sep2)

	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var close_btn = Button.new()
	close_btn.text = "Close (U)"
	close_btn.custom_minimum_size = Vector2(120, 36)
	WhiteDwarfThemeData.apply_to_button(close_btn)
	close_btn.pressed.connect(_on_close)
	btn_row.add_child(close_btn)


func _build_player_section(parent: VBoxContainer, player: int) -> void:
	var faction_name = GameState.state.get("factions", {}).get(str(player), {}).get("name", "Player %d" % player)

	# Player header
	var header = Label.new()
	header.text = "Player %d — %s" % [player, faction_name]
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	parent.add_child(header)

	# Get units for this player (include destroyed units in army overview)
	var player_units = GameState.get_units_for_player(player, true)
	if player_units.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "  No units"
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		parent.add_child(empty_lbl)
		return

	for uid in player_units:
		_build_unit_row(parent, uid, player_units[uid])

	# Small spacer between players
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	parent.add_child(spacer)


func _build_unit_row(parent: VBoxContainer, uid: String, unit_data: Dictionary) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	# Color swatch button
	var current_color = GameState.get_unit_color(uid)
	if current_color == Color.TRANSPARENT:
		current_color = GameState.auto_assign_unit_color(uid)

	var swatch = Button.new()
	swatch.custom_minimum_size = Vector2(24, 24)
	var swatch_style = StyleBoxFlat.new()
	swatch_style.bg_color = current_color
	swatch_style.corner_radius_top_left = 4
	swatch_style.corner_radius_top_right = 4
	swatch_style.corner_radius_bottom_left = 4
	swatch_style.corner_radius_bottom_right = 4
	swatch.add_theme_stylebox_override("normal", swatch_style)
	swatch.add_theme_stylebox_override("hover", swatch_style)
	swatch.add_theme_stylebox_override("pressed", swatch_style)
	swatch.tooltip_text = "Click to change color"
	swatch.pressed.connect(_on_swatch_pressed.bind(uid, swatch))
	row.add_child(swatch)

	# Unit name (prefer display_name which includes Greek suffix for duplicates)
	var meta = unit_data.get("meta", {})
	var unit_name = meta.get("display_name", meta.get("name", "Unknown"))
	var name_lbl = Label.new()
	name_lbl.text = unit_name
	name_lbl.custom_minimum_size = Vector2(180, 0)
	name_lbl.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	name_lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(name_lbl)

	# Editable label LineEdit
	var label_edit = LineEdit.new()
	label_edit.text = GameState.get_unit_label(uid)
	label_edit.placeholder_text = "auto"
	label_edit.custom_minimum_size = Vector2(80, 24)
	label_edit.max_length = 6
	label_edit.add_theme_font_size_override("font_size", 12)
	label_edit.text_submitted.connect(_on_label_changed.bind(uid))
	row.add_child(label_edit)
	_label_edits[uid] = label_edit

	# Unit type tag
	var keywords = unit_data.get("meta", {}).get("keywords", [])
	var type_tag = "INF"
	for kw in keywords:
		var upper = str(kw).to_upper()
		if upper == "VEHICLE":
			type_tag = "VEH"
			break
		elif upper == "MONSTER":
			type_tag = "MON"
			break
		elif upper == "CHARACTER":
			type_tag = "CHAR"

	var tag_lbl = Label.new()
	tag_lbl.text = type_tag
	tag_lbl.custom_minimum_size = Vector2(40, 0)
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_lbl.add_theme_font_size_override("font_size", 11)
	tag_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	row.add_child(tag_lbl)


func _on_swatch_pressed(uid: String, swatch_button: Button) -> void:
	# Show color picker popup near the swatch
	var existing = get_node_or_null("ArmyPanelColorPicker")
	if existing:
		existing.queue_free()

	var picker = UnitColorPickerPopup.new()
	picker.name = "ArmyPanelColorPicker"
	add_child(picker)
	var popup_pos = swatch_button.global_position + Vector2(swatch_button.size.x + 8, 0)
	picker.setup(uid, popup_pos)
	picker.color_changed.connect(_on_color_changed_from_picker.bind(swatch_button))


func _on_color_changed_from_picker(uid: String, color: Color, swatch_button: Button) -> void:
	# Update the swatch's color
	var new_style = StyleBoxFlat.new()
	new_style.bg_color = color
	new_style.corner_radius_top_left = 4
	new_style.corner_radius_top_right = 4
	new_style.corner_radius_bottom_left = 4
	new_style.corner_radius_bottom_right = 4
	swatch_button.add_theme_stylebox_override("normal", new_style)
	swatch_button.add_theme_stylebox_override("hover", new_style)
	swatch_button.add_theme_stylebox_override("pressed", new_style)
	unit_visual_changed.emit(uid)


func _on_label_changed(new_text: String, uid: String) -> void:
	GameState.set_unit_label(uid, new_text)
	unit_visual_changed.emit(uid)


func _on_close() -> void:
	panel_closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_U:
			_on_close()
			get_viewport().set_input_as_handled()
