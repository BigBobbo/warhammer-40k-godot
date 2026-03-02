extends PanelContainer
class_name SettingsMenu

# P3-111: Settings Menu — Audio controls, visual settings, UI scale, animation speed, colorblind mode
# Can be opened from MainMenu (Settings button) or in-game (Escape key)
# Uses the WhiteDwarfTheme for consistent styling
# Now includes a Controls tab for keybinding remapping

const WhiteDwarfThemeData = preload("res://scripts/WhiteDwarfTheme.gd")

signal settings_closed
signal save_load_requested

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
var _save_load_button: Button

# Tab system
var _tab_buttons: Array[Button] = []
var _tab_containers: Array[Control] = []
var _active_tab: int = 0

# Controls tab — keybinding capture state
var _capturing_action_id: String = ""
var _capturing_button: Button = null
var _keybinding_buttons: Dictionary = {}  # action_id -> Button
var _keybinding_reset_buttons: Dictionary = {}  # action_id -> Button

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
	panel.custom_minimum_size = Vector2(700, 600)
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

	# Tab bar
	var tab_bar = HBoxContainer.new()
	tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_bar.add_theme_constant_override("separation", 5)
	vbox.add_child(tab_bar)

	var tab_names = ["Audio", "Visual", "Controls"]
	for i in range(tab_names.size()):
		var tab_btn = Button.new()
		tab_btn.text = tab_names[i]
		tab_btn.custom_minimum_size = Vector2(120, 32)
		tab_btn.toggle_mode = true
		tab_btn.button_pressed = (i == 0)
		WhiteDwarfThemeData.apply_to_button(tab_btn)
		tab_btn.pressed.connect(_on_tab_pressed.bind(i))
		tab_bar.add_child(tab_btn)
		_tab_buttons.append(tab_btn)

	# Separator below tabs
	var sep1 = HSeparator.new()
	sep1.add_theme_color_override("separator", WhiteDwarfThemeData.WH_GOLD)
	vbox.add_child(sep1)

	# Tab content area (shared scroll container)
	var content_area = Control.new()
	content_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(content_area)

	# ── Audio Tab ──
	var audio_scroll = _create_tab_scroll()
	content_area.add_child(audio_scroll)
	_tab_containers.append(audio_scroll)

	var audio_content = audio_scroll.get_child(0) as VBoxContainer
	_add_section_header(audio_content, "Audio")
	_master_volume_slider = _add_slider_row(audio_content, "Master Volume:", 0.0, 1.0, 0.05, "_on_master_volume_changed")
	_master_volume_label = _get_last_value_label()
	_music_volume_slider = _add_slider_row(audio_content, "Music Volume:", 0.0, 1.0, 0.05, "_on_music_volume_changed")
	_music_volume_label = _get_last_value_label()
	_sfx_volume_slider = _add_slider_row(audio_content, "SFX Volume:", 0.0, 1.0, 0.05, "_on_sfx_volume_changed")
	_sfx_volume_label = _get_last_value_label()
	_mute_checkbox = _add_checkbox_row(audio_content, "Mute All Audio", "_on_mute_toggled")

	# ── Visual Tab ──
	var visual_scroll = _create_tab_scroll()
	visual_scroll.visible = false
	content_area.add_child(visual_scroll)
	_tab_containers.append(visual_scroll)

	var visual_content = visual_scroll.get_child(0) as VBoxContainer
	_add_section_header(visual_content, "Visual")
	_visual_style_dropdown = _add_dropdown_row(visual_content, "Unit Style:", ["Enhanced", "Silhouettes", "Faction Glyphs", "Classic"], "_on_visual_style_changed")
	_retro_mode_checkbox = _add_checkbox_row(visual_content, "Retro CRT Mode", "_on_retro_mode_toggled")
	_ui_scale_slider = _add_slider_row(visual_content, "UI Scale:", 0.5, 2.0, 0.1, "_on_ui_scale_changed")
	_ui_scale_label = _get_last_value_label()
	_animation_speed_slider = _add_slider_row(visual_content, "Animation Speed:", 0.25, 3.0, 0.25, "_on_animation_speed_changed")
	_animation_speed_label = _get_last_value_label()
	_colorblind_dropdown = _add_dropdown_row(visual_content, "Colorblind Mode:", ["None", "Protanopia (Red-Green)", "Deuteranopia (Green-Red)", "Tritanopia (Blue-Yellow)"], "_on_colorblind_changed")

	# ── Controls Tab ──
	var controls_scroll = _create_tab_scroll()
	controls_scroll.visible = false
	content_area.add_child(controls_scroll)
	_tab_containers.append(controls_scroll)

	var controls_content = controls_scroll.get_child(0) as VBoxContainer
	_build_controls_tab(controls_content)

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

	# Save / Load button (only in-game)
	_save_load_button = Button.new()
	_save_load_button.text = "Save / Load"
	_save_load_button.custom_minimum_size = Vector2(150, 40)
	_save_load_button.visible = show_return_to_menu
	WhiteDwarfThemeData.apply_to_button(_save_load_button)
	_save_load_button.pressed.connect(_on_save_load_pressed)
	btn_row.add_child(_save_load_button)

	# Close button
	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.custom_minimum_size = Vector2(150, 40)
	WhiteDwarfThemeData.apply_to_button(_close_button)
	_close_button.pressed.connect(_on_close_pressed)
	btn_row.add_child(_close_button)

func _create_tab_scroll() -> ScrollContainer:
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)

	return scroll

# ============================================================================
# Tab switching
# ============================================================================

func _on_tab_pressed(tab_index: int) -> void:
	# Cancel any active key capture when switching tabs
	if _capturing_button:
		_cancel_capture()

	_active_tab = tab_index
	for i in range(_tab_buttons.size()):
		_tab_buttons[i].button_pressed = (i == tab_index)
		_tab_containers[i].visible = (i == tab_index)
	print("[SettingsMenu] Switched to tab %d" % tab_index)

# ============================================================================
# Controls Tab — Keybinding UI
# ============================================================================

func _build_controls_tab(parent: VBoxContainer) -> void:
	if not KeybindingManager:
		var err_label = Label.new()
		err_label.text = "KeybindingManager not available"
		err_label.add_theme_color_override("font_color", Color.RED)
		parent.add_child(err_label)
		return

	for category in KeybindingManager.get_categories():
		_add_section_header(parent, category)

		var actions = KeybindingManager.get_actions_in_category(category)
		for action_id in actions:
			_add_keybinding_row(parent, action_id)

	# Reset All Defaults button
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	parent.add_child(spacer)

	var reset_all_btn = Button.new()
	reset_all_btn.text = "Reset All Defaults"
	reset_all_btn.custom_minimum_size = Vector2(200, 36)
	WhiteDwarfThemeData.apply_to_button(reset_all_btn)
	reset_all_btn.pressed.connect(_on_reset_all_pressed)

	var center_row = HBoxContainer.new()
	center_row.alignment = BoxContainer.ALIGNMENT_CENTER
	center_row.add_child(reset_all_btn)
	parent.add_child(center_row)

func _add_keybinding_row(parent: VBoxContainer, action_id: String) -> void:
	var binding = KeybindingManager.get_binding(action_id)
	if binding.size() == 0:
		return

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	# Action name label
	var name_label = Label.new()
	name_label.text = binding.display_name
	name_label.custom_minimum_size = Vector2(180, 0)
	name_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	row.add_child(name_label)

	# Key binding button (click to rebind)
	var key_btn = Button.new()
	key_btn.text = KeybindingManager.get_key_display_name(action_id)
	key_btn.custom_minimum_size = Vector2(160, 30)
	key_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	WhiteDwarfThemeData.apply_to_button(key_btn)
	key_btn.pressed.connect(_on_keybinding_button_pressed.bind(action_id))
	row.add_child(key_btn)
	_keybinding_buttons[action_id] = key_btn

	# Reset button (only visible if binding differs from default)
	var reset_btn = Button.new()
	reset_btn.text = "Reset"
	reset_btn.custom_minimum_size = Vector2(60, 30)
	WhiteDwarfThemeData.apply_to_button(reset_btn)
	reset_btn.pressed.connect(_on_reset_binding_pressed.bind(action_id))
	reset_btn.visible = KeybindingManager.is_modified(action_id)
	row.add_child(reset_btn)
	_keybinding_reset_buttons[action_id] = reset_btn

func _on_keybinding_button_pressed(action_id: String) -> void:
	# If already capturing for another button, cancel that first
	if _capturing_button and _capturing_action_id != action_id:
		_cancel_capture()

	# Enter capture mode
	_capturing_action_id = action_id
	_capturing_button = _keybinding_buttons[action_id]
	_capturing_button.text = "Press a key..."
	_capturing_button.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	print("[SettingsMenu] Capturing key for '%s'" % action_id)

func _cancel_capture() -> void:
	if _capturing_button and _capturing_action_id != "":
		_capturing_button.text = KeybindingManager.get_key_display_name(_capturing_action_id)
		_capturing_button.remove_theme_color_override("font_color")
		WhiteDwarfThemeData.apply_to_button(_capturing_button)
	_capturing_action_id = ""
	_capturing_button = null

func _on_reset_binding_pressed(action_id: String) -> void:
	KeybindingManager.reset_binding(action_id)
	_update_keybinding_display(action_id)
	print("[SettingsMenu] Reset binding for '%s'" % action_id)

func _on_reset_all_pressed() -> void:
	KeybindingManager.reset_all()
	# Update all displayed bindings
	for action_id in _keybinding_buttons:
		_update_keybinding_display(action_id)
	print("[SettingsMenu] Reset all bindings to defaults")

func _update_keybinding_display(action_id: String) -> void:
	if _keybinding_buttons.has(action_id):
		_keybinding_buttons[action_id].text = KeybindingManager.get_key_display_name(action_id)
	if _keybinding_reset_buttons.has(action_id):
		_keybinding_reset_buttons[action_id].visible = KeybindingManager.is_modified(action_id)

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
	# Update in-game-only button visibility
	_return_to_menu_button.visible = show_return_to_menu
	_save_load_button.visible = show_return_to_menu

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

func _on_save_load_pressed() -> void:
	print("[SettingsMenu] Save/Load requested")
	save_load_requested.emit()
	settings_closed.emit()
	queue_free()

func _on_return_to_menu_pressed() -> void:
	print("[SettingsMenu] Returning to main menu")
	settings_closed.emit()
	queue_free()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

# ============================================================================
# Input handling — Escape to close, key capture for Controls tab
# ============================================================================

func _unhandled_input(event: InputEvent) -> void:
	# Key capture mode for controls tab
	if _capturing_action_id != "" and event is InputEventKey and event.pressed:
		# Escape cancels capture
		if event.keycode == KEY_ESCAPE:
			_cancel_capture()
			get_viewport().set_input_as_handled()
			return

		# Ignore bare modifier keys (Shift, Ctrl, Alt alone)
		if event.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
			return

		var new_key = event.keycode
		var new_shift = event.shift_pressed
		var new_ctrl = event.ctrl_pressed
		var new_alt = event.alt_pressed

		# Check for conflicts
		var conflict_id = KeybindingManager.find_conflict(_capturing_action_id, new_key, new_shift, new_ctrl, new_alt)
		if conflict_id != "":
			# Auto-swap: clear the conflicting binding by setting it to KEY_NONE (0)
			KeybindingManager.set_binding(conflict_id, 0, false, false, false)
			_update_keybinding_display(conflict_id)
			print("[SettingsMenu] Conflict resolved: cleared '%s'" % conflict_id)

		# Apply the new binding
		KeybindingManager.set_binding(_capturing_action_id, new_key, new_shift, new_ctrl, new_alt)
		_update_keybinding_display(_capturing_action_id)

		# Exit capture mode
		_capturing_button.remove_theme_color_override("font_color")
		WhiteDwarfThemeData.apply_to_button(_capturing_button)
		_capturing_action_id = ""
		_capturing_button = null

		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()
