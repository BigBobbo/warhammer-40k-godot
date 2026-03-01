extends PanelContainer
class_name SettingsMenu

# P3-111: Settings Menu — Audio controls, visual settings, UI scale, animation speed, colorblind mode
# Can be opened from MainMenu (Settings button) or in-game (Escape key)
# Uses the WhiteDwarfTheme for consistent styling

const WhiteDwarfThemeData = preload("res://scripts/WhiteDwarfTheme.gd")

signal settings_closed

# UI references (built dynamically)
var _master_volume_slider: HSlider
var _music_volume_slider: HSlider
var _sfx_volume_slider: HSlider
var _mute_checkbox: CheckBox
var _master_volume_label: Label
var _music_volume_label: Label
var _sfx_volume_label: Label

var _visual_style_dropdown: OptionButton
var _retro_mode_checkbox: CheckBox
var _ui_scale_slider: HSlider
var _ui_scale_label: Label
var _animation_speed_slider: HSlider
var _animation_speed_label: Label
var _colorblind_dropdown: OptionButton

var _close_button: Button
var _return_to_menu_button: Button

# Whether to show "Return to Main Menu" button (only in-game)
var show_return_to_menu: bool = false

func _ready() -> void:
	_build_ui()
	_load_current_settings()
	_connect_signals()
	print("[SettingsMenu] P3-111: Ready")

func _build_ui() -> void:
	name = "SettingsMenu"

	# Full-screen semi-transparent overlay
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0

	# Dark overlay background
	var overlay_style = StyleBoxFlat.new()
	overlay_style.bg_color = Color(0.0, 0.0, 0.0, 0.75)
	add_theme_stylebox_override("panel", overlay_style)

	# Center container for the settings panel
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Main settings panel
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(650, 550)
	WhiteDwarfThemeData.apply_to_panel(panel)
	center.add_child(panel)

	# Margin container for padding
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	panel.add_child(margin)

	# Main vertical layout
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	vbox.add_child(title)

	# Separator
	var sep1 = HSeparator.new()
	sep1.add_theme_color_override("separator", WhiteDwarfThemeData.WH_GOLD)
	vbox.add_child(sep1)

	# Scrollable content area
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)

	# ── Audio Section ──
	_add_section_header(content, "Audio")
	_master_volume_slider = _add_slider_row(content, "Master Volume:", 0.0, 1.0, 0.05, "_on_master_volume_changed")
	_master_volume_label = _get_last_value_label()
	_music_volume_slider = _add_slider_row(content, "Music Volume:", 0.0, 1.0, 0.05, "_on_music_volume_changed")
	_music_volume_label = _get_last_value_label()
	_sfx_volume_slider = _add_slider_row(content, "SFX Volume:", 0.0, 1.0, 0.05, "_on_sfx_volume_changed")
	_sfx_volume_label = _get_last_value_label()
	_mute_checkbox = _add_checkbox_row(content, "Mute All Audio", "_on_mute_toggled")

	# ── Visual Section ──
	_add_section_header(content, "Visual")
	_visual_style_dropdown = _add_dropdown_row(content, "Unit Style:", ["Enhanced", "Silhouettes", "Faction Glyphs", "Classic"], "_on_visual_style_changed")
	_retro_mode_checkbox = _add_checkbox_row(content, "Retro CRT Mode", "_on_retro_mode_toggled")
	_ui_scale_slider = _add_slider_row(content, "UI Scale:", 0.5, 2.0, 0.1, "_on_ui_scale_changed")
	_ui_scale_label = _get_last_value_label()
	_animation_speed_slider = _add_slider_row(content, "Animation Speed:", 0.25, 3.0, 0.25, "_on_animation_speed_changed")
	_animation_speed_label = _get_last_value_label()
	_colorblind_dropdown = _add_dropdown_row(content, "Colorblind Mode:", ["None", "Protanopia (Red-Green)", "Deuteranopia (Green-Red)", "Tritanopia (Blue-Yellow)"], "_on_colorblind_changed")

	# Bottom separator
	var sep2 = HSeparator.new()
	sep2.add_theme_color_override("separator", WhiteDwarfThemeData.WH_GOLD)
	vbox.add_child(sep2)

	# Button row
	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 15)
	vbox.add_child(btn_row)

	# Return to Main Menu button (only in-game)
	_return_to_menu_button = Button.new()
	_return_to_menu_button.text = "Return to Main Menu"
	_return_to_menu_button.custom_minimum_size = Vector2(200, 40)
	_return_to_menu_button.visible = show_return_to_menu
	WhiteDwarfThemeData.apply_to_button(_return_to_menu_button)
	_return_to_menu_button.pressed.connect(_on_return_to_menu_pressed)
	btn_row.add_child(_return_to_menu_button)

	# Close button
	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.custom_minimum_size = Vector2(150, 40)
	WhiteDwarfThemeData.apply_to_button(_close_button)
	_close_button.pressed.connect(_on_close_pressed)
	btn_row.add_child(_close_button)

# Track the last value label created by _add_slider_row
var _last_value_label: Label = null

func _get_last_value_label() -> Label:
	return _last_value_label

# ============================================================================
# UI Builder Helpers
# ============================================================================

func _add_section_header(parent: VBoxContainer, text: String) -> void:
	var header = Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	parent.add_child(header)

func _add_slider_row(parent: VBoxContainer, label_text: String, min_val: float, max_val: float, step: float, callback: String) -> HSlider:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(160, 0)
	label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	row.add_child(label)

	var slider = HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(200, 0)
	row.add_child(slider)

	var value_label = Label.new()
	value_label.custom_minimum_size = Vector2(50, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	row.add_child(value_label)

	_last_value_label = value_label
	slider.value_changed.connect(Callable(self, callback))

	return slider

func _add_checkbox_row(parent: VBoxContainer, label_text: String, callback: String) -> CheckBox:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(160, 0)
	row.add_child(spacer)

	var checkbox = CheckBox.new()
	checkbox.text = label_text
	checkbox.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	checkbox.toggled.connect(Callable(self, callback))
	row.add_child(checkbox)

	return checkbox

func _add_dropdown_row(parent: VBoxContainer, label_text: String, items: Array, callback: String) -> OptionButton:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(160, 0)
	label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	row.add_child(label)

	var dropdown = OptionButton.new()
	dropdown.custom_minimum_size = Vector2(250, 0)
	for item in items:
		dropdown.add_item(item)
	dropdown.item_selected.connect(Callable(self, callback))
	row.add_child(dropdown)

	return dropdown

# ============================================================================
# Load current settings into UI
# ============================================================================

func _load_current_settings() -> void:
	if not SettingsService:
		return

	# Audio
	_master_volume_slider.value = SettingsService.master_volume
	_music_volume_slider.value = SettingsService.music_volume
	_sfx_volume_slider.value = SettingsService.sfx_volume
	_mute_checkbox.button_pressed = SettingsService.audio_muted
	_update_volume_label(_master_volume_label, SettingsService.master_volume)
	_update_volume_label(_music_volume_label, SettingsService.music_volume)
	_update_volume_label(_sfx_volume_label, SettingsService.sfx_volume)

	# Visual
	var style_index = ["enhanced", "style_a", "style_b", "classic"].find(SettingsService.unit_visual_style)
	if style_index >= 0:
		_visual_style_dropdown.selected = style_index
	_retro_mode_checkbox.button_pressed = SettingsService.retro_mode
	_ui_scale_slider.value = SettingsService.ui_scale
	_update_scale_label(_ui_scale_label, SettingsService.ui_scale)
	_animation_speed_slider.value = SettingsService.animation_speed
	_update_speed_label(_animation_speed_label, SettingsService.animation_speed)
	var cb_index = ["none", "protanopia", "deuteranopia", "tritanopia"].find(SettingsService.colorblind_mode)
	if cb_index >= 0:
		_colorblind_dropdown.selected = cb_index

func _connect_signals() -> void:
	# Update return to menu button visibility
	_return_to_menu_button.visible = show_return_to_menu

# ============================================================================
# Value label formatters
# ============================================================================

func _update_volume_label(label: Label, value: float) -> void:
	label.text = "%d%%" % int(value * 100)

func _update_scale_label(label: Label, value: float) -> void:
	label.text = "%.1fx" % value

func _update_speed_label(label: Label, value: float) -> void:
	label.text = "%.2fx" % value

# ============================================================================
# Audio Callbacks
# ============================================================================

func _on_master_volume_changed(value: float) -> void:
	SettingsService.set_master_volume(value)
	_update_volume_label(_master_volume_label, value)

func _on_music_volume_changed(value: float) -> void:
	SettingsService.set_music_volume(value)
	_update_volume_label(_music_volume_label, value)

func _on_sfx_volume_changed(value: float) -> void:
	SettingsService.set_sfx_volume(value)
	_update_volume_label(_sfx_volume_label, value)

func _on_mute_toggled(pressed: bool) -> void:
	SettingsService.set_audio_muted(pressed)

# ============================================================================
# Visual Callbacks
# ============================================================================

func _on_visual_style_changed(index: int) -> void:
	var styles = ["enhanced", "style_a", "style_b", "classic"]
	if index >= 0 and index < styles.size():
		SettingsService.set_unit_visual_style_setting(styles[index])

func _on_retro_mode_toggled(pressed: bool) -> void:
	SettingsService.set_retro_mode(pressed)

func _on_ui_scale_changed(value: float) -> void:
	SettingsService.set_ui_scale(value)
	_update_scale_label(_ui_scale_label, value)

func _on_animation_speed_changed(value: float) -> void:
	SettingsService.set_animation_speed(value)
	_update_speed_label(_animation_speed_label, value)

func _on_colorblind_changed(index: int) -> void:
	var modes = ["none", "protanopia", "deuteranopia", "tritanopia"]
	if index >= 0 and index < modes.size():
		SettingsService.set_colorblind_mode(modes[index])

# ============================================================================
# Button Callbacks
# ============================================================================

func _on_close_pressed() -> void:
	print("[SettingsMenu] Closed")
	settings_closed.emit()
	queue_free()

func _on_return_to_menu_pressed() -> void:
	print("[SettingsMenu] Returning to main menu")
	settings_closed.emit()
	queue_free()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

# ============================================================================
# Input handling — Escape to close
# ============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()
