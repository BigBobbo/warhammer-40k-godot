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
var _unit_color_display_dropdown: OptionButton
var _ui_scale_slider: HSlider
var _ui_scale_label: Label
var _animation_speed_slider: HSlider
var _animation_speed_label: Label
var _menu_scroll_speed_slider: HSlider
var _menu_scroll_speed_label: Label
var _drag_clamp_checkbox: CheckBox
var _placement_clamp_checkbox: CheckBox
var _colorblind_dropdown: OptionButton
var _board_style_dropdown: OptionButton
var _ruins_style_dropdown: OptionButton
var _terrain_debug_checkbox: CheckBox
var _terrain_scatter_checkbox: CheckBox
var _terrain_cover_checkbox: CheckBox
var _los_debug_out_of_range_checkbox: CheckBox

var _auto_allocate_checkbox: CheckBox
var _hotseat_handoff_checkbox: CheckBox
var _tutorial_language_dropdown: OptionButton
# Dropdown index -> SettingsService.tutorial_language value.
const TUTORIAL_LANGUAGES: Array[String] = ["standard", "orky"]
var _window_mode_dropdown: OptionButton
var _resolution_dropdown: OptionButton
var _vsync_checkbox: CheckBox

const WINDOW_MODES := ["fullscreen", "exclusive", "windowed"]
const WINDOW_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
]
var _autosave_phase_start_checkbox: CheckBox
var _controller_text_boost_checkbox: CheckBox
var _input_mode_dropdown: OptionButton
var _input_mode_status_label: Label
# Dropdown index -> SettingsService.input_mode_policy value (see the Input Mode
# section of the Controller tab).
const INPUT_MODE_POLICIES: Array[String] = ["auto", "pad", "kbm", "dynamic"]
var _pad_invert_y_checkbox: CheckBox
var _pad_swap_sticks_checkbox: CheckBox
var _pad_magnetism_checkbox: CheckBox
var _pad_hover_card_checkbox: CheckBox
var _pad_camera_sens_slider: HSlider
var _pad_camera_sens_label: Label
var _pad_cursor_sens_slider: HSlider
var _pad_cursor_sens_label: Label
const GlyphDB = preload("res://scripts/input/GlyphDB.gd")

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

# Controller tab — pad-button capture state (Settings › Controller layout)
var _pad_capturing_role: String = ""
var _pad_capturing_button: Button = null
var _pad_role_buttons: Dictionary = {}  # role_id -> Button
var _pad_role_reset_buttons: Dictionary = {}  # role_id -> Button
var _pad_reference_box: VBoxContainer = null

# Whether to show "Return to Main Menu" button (only in-game)
var show_return_to_menu: bool = false

# ── Controller (D-pad) focus support ──────────────────────────────────
# This menu is a full-screen plain Control overlay, so — exactly like the
# Save/Load dialog and the 11e allocation overlay — Godot does NOT confine
# keyboard/pad focus to it. Verified live: with the menu open and a pad active,
# a D-pad press in ANY direction walks focus OUT to the ~26 focusable controls
# drawn BEHIND it (MainMenu buttons, or the in-game HUD). Mirroring those two
# modals we (1) join the "pad_native_nav_modal" group so PadRouter keeps its
# board handlers off us and Main ignores the Start (End-Phase) press while
# we're open, and (2) confine focus to our own subtree while a pad is active
# (external focusables demoted to FOCUS_NONE, restored on close / device
# switch). Keyboard/mouse behaviour is deliberately untouched: no confinement
# unless the pad is the active device.
const PAD_MODAL_GROUP := "pad_native_nav_modal"
var _pad_focus_confined: bool = false
var _pad_confined_controls: Array = []

func _ready() -> void:
	# Join before building so PadRouter/Main see the membership immediately.
	add_to_group(PAD_MODAL_GROUP)
	_build_ui()
	_load_current_settings()
	_connect_signals()
	# M0 controller foundations: land pad focus somewhere visible so D-pad
	# navigation works the moment the overlay opens.
	_close_button.grab_focus()
	# Controller: trap directional focus inside the menu (pad only) so the
	# D-pad can't walk into the UI behind it, and follow device switches.
	var idm := _idm()
	if idm != null and idm.has_signal("device_changed") and not idm.device_changed.is_connected(_on_pad_device_changed):
		idm.device_changed.connect(_on_pad_device_changed)
	if _pad_active():
		_confine_pad_focus()
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
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	vbox.add_child(title)

	# Tab bar
	var tab_bar = HBoxContainer.new()
	tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_bar.add_theme_constant_override("separation", 5)
	vbox.add_child(tab_bar)

	var tab_names = ["Audio", "Visual", "Gameplay", "Controls", "Controller"]
	for i in range(tab_names.size()):
		var tab_btn = Button.new()
		tab_btn.text = tab_names[i]
		tab_btn.name = "SettingsTab" + tab_names[i]
		tab_btn.custom_minimum_size = Vector2(110, 32)
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
	if not OS.has_feature("web"):
		_add_section_header(visual_content, "Display")
		_window_mode_dropdown = _add_dropdown_row(visual_content, "Window Mode:", ["Fullscreen", "Exclusive Fullscreen", "Windowed"], "_on_window_mode_changed")
		_resolution_dropdown = _add_dropdown_row(visual_content, "Window Size:", WINDOW_RESOLUTIONS.map(func(r): return "%d x %d" % [r.x, r.y]), "_on_window_resolution_changed")
		_vsync_checkbox = _add_checkbox_row(visual_content, "V-Sync", "_on_vsync_toggled")
	_add_section_header(visual_content, "Visual")
	_board_style_dropdown = _add_dropdown_row(visual_content, "Board Texture:", ["Grass", "Mud", "Desert", "Stone", "Felt", "Tilepack", "None (Solid)"], "_on_board_style_changed")
	_ruins_style_dropdown = _add_dropdown_row(visual_content, "Ruins Texture:", ["Concrete", "Marble", "Brick", "Weathered Stone", "None (Solid)"], "_on_ruins_style_changed")
	_visual_style_dropdown = _add_dropdown_row(visual_content, "Unit Style:", ["Letter (Default)", "Enhanced", "Silhouettes", "Faction Glyphs", "Classic"], "_on_visual_style_changed")
	_unit_color_display_dropdown = _add_dropdown_row(visual_content, "Unit Color:", ["Full Base", "Ring Only"], "_on_unit_color_display_changed")
	_ui_scale_slider = _add_slider_row(visual_content, "UI Scale:", 0.5, 2.0, 0.1, "_on_ui_scale_changed")
	_ui_scale_label = _get_last_value_label()
	_animation_speed_slider = _add_slider_row(visual_content, "Animation Speed:", 0.25, 3.0, 0.25, "_on_animation_speed_changed")
	_animation_speed_label = _get_last_value_label()
	_colorblind_dropdown = _add_dropdown_row(visual_content, "Colorblind Mode:", ["None", "Protanopia (Red-Green)", "Deuteranopia (Green-Red)", "Tritanopia (Blue-Yellow)"], "_on_colorblind_changed")
	_terrain_debug_checkbox = _add_checkbox_row(visual_content, "Terrain Debug Labels (internal ids + LoS badges)", "_on_terrain_debug_labels_toggled")
	_terrain_scatter_checkbox = _add_checkbox_row(visual_content, "Terrain Scatter Props (crates, sandbags, trees)", "_on_terrain_scatter_toggled")
	_terrain_cover_checkbox = _add_checkbox_row(visual_content, "Terrain Cover Labels (LB / +2 / +1 chips on terrain)", "_on_terrain_cover_labels_toggled")
	_los_debug_out_of_range_checkbox = _add_checkbox_row(visual_content, "LoS Debug: include units out of weapon range", "_on_los_debug_out_of_range_toggled")
	var los_range_help = Label.new()
	los_range_help.text = "Affects the line-of-sight overlay (hold L). On by default: enemies no weapon in the selected unit could reach are still checked and drawn dashed amber, labelled \"is out of range\" — that is what explains a squad you can plainly see but cannot select. Turn it off to skip them entirely, for a quieter board and a faster overlay on a crowded one."
	los_range_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	los_range_help.custom_minimum_size = Vector2(620, 0)
	los_range_help.add_theme_font_size_override("font_size", 16)
	los_range_help.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	visual_content.add_child(los_range_help)

	# ── Gameplay Tab ──
	var gameplay_scroll = _create_tab_scroll()
	gameplay_scroll.visible = false
	content_area.add_child(gameplay_scroll)
	_tab_containers.append(gameplay_scroll)

	var gameplay_content = gameplay_scroll.get_child(0) as VBoxContainer
	_add_section_header(gameplay_content, "Wound Allocation")
	_auto_allocate_checkbox = _add_checkbox_row(gameplay_content, "Computer allocates wounds (auto-remove models)", "_on_auto_allocate_wounds_toggled")
	var auto_alloc_help = Label.new()
	auto_alloc_help.text = "When enabled, the computer chooses which wounded models are removed instead of asking you to click each one. The defending player normally makes this choice."
	auto_alloc_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	auto_alloc_help.custom_minimum_size = Vector2(620, 0)
	auto_alloc_help.add_theme_font_size_override("font_size", 16)
	auto_alloc_help.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	gameplay_content.add_child(auto_alloc_help)

	_add_section_header(gameplay_content, "Play and Pass (local 2-player)")
	_hotseat_handoff_checkbox = _add_checkbox_row(gameplay_content, "Show \"Pass the device\" screen between player turns", "_on_hotseat_handoff_toggled")
	var handoff_help = Label.new()
	handoff_help.text = "On by default. In local Human-vs-Human games, hides the board and asks the next player to take the controls at each turn change (and before secret battle-formation picks). Has no effect in online or vs-AI games."
	handoff_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	handoff_help.custom_minimum_size = Vector2(620, 0)
	handoff_help.add_theme_font_size_override("font_size", 16)
	handoff_help.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	gameplay_content.add_child(handoff_help)

	_add_section_header(gameplay_content, "Tutorial")
	_tutorial_language_dropdown = _add_dropdown_row(gameplay_content, "Tutorial Language",
		["Plain English", "Orky (Da Boss)"], "_on_tutorial_language_selected")
	var tutorial_lang_help = Label.new()
	tutorial_lang_help.text = "How the tutorial instructor talks. Plain English (default) keeps the lessons easy to follow; Orky is Da Boss's own dialect for the full greenskin experience. Applies immediately, mid-lesson too."
	tutorial_lang_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_lang_help.custom_minimum_size = Vector2(620, 0)
	tutorial_lang_help.add_theme_font_size_override("font_size", 16)
	tutorial_lang_help.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	gameplay_content.add_child(tutorial_lang_help)

	_add_section_header(gameplay_content, "Auto-Save")
	_autosave_phase_start_checkbox = _add_checkbox_row(gameplay_content, "Auto-save at the start of each phase", "_on_autosave_phase_start_toggled")
	var autosave_help = Label.new()
	autosave_help.text = "On by default. Saves the game automatically at the start of every phase, named after the two armies and the phase that is starting (e.g. \"Space Marines vs Orks - Movement\"). Works in the browser build on itch.io too."
	autosave_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	autosave_help.custom_minimum_size = Vector2(620, 0)
	autosave_help.add_theme_font_size_override("font_size", 16)
	autosave_help.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	gameplay_content.add_child(autosave_help)

	# ── Controls Tab ──
	var controls_scroll = _create_tab_scroll()
	controls_scroll.visible = false
	content_area.add_child(controls_scroll)
	_tab_containers.append(controls_scroll)

	var controls_content = controls_scroll.get_child(0) as VBoxContainer
	_build_controls_tab(controls_content)

	# ── Controller Tab (pad / Steam Deck layout) ──
	var controller_scroll = _create_tab_scroll()
	controller_scroll.visible = false
	content_area.add_child(controller_scroll)
	_tab_containers.append(controller_scroll)

	var controller_content = controller_scroll.get_child(0) as VBoxContainer
	_build_controller_tab(controller_content)

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

	# Quit to Desktop — always available; without it an in-game player has to
	# go back to the main menu and scroll below the fold to find Quit. Not on
	# web (browsers own the tab lifecycle; Godot quit is a no-op there).
	if not OS.has_feature("web"):
		var quit_button = Button.new()
		quit_button.text = "Quit to Desktop"
		quit_button.custom_minimum_size = Vector2(170, 40)
		WhiteDwarfThemeData.apply_to_button(quit_button)
		quit_button.pressed.connect(_on_quit_to_desktop_pressed)
		btn_row.add_child(quit_button)

func _create_tab_scroll() -> ScrollContainer:
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
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
	# Cancel any active key / pad-button capture when switching tabs
	if _capturing_button:
		_cancel_capture()
	if _pad_capturing_button:
		_cancel_pad_capture()

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

	# Mouse controls — informational (the wheel isn't a rebindable key, so it
	# has no capture button; listed here so players know it exists).
	_add_section_header(parent, "Mouse")
	_add_mouse_info_row(parent, "Zoom In / Out", "Mouse Wheel")

	# Over-range drag clamping on mouse & keyboard. Without it a drag past the
	# reach circle just turns red and is rejected on drop, so squeezing out the
	# last inch of a move means landing the cursor on the circle by hand.
	_drag_clamp_checkbox = _add_checkbox_row(parent, "Stop model drags at their maximum move range", "_on_drag_clamp_toggled")
	var drag_clamp_help = Label.new()
	drag_clamp_help.text = "On: dragging a model further than it can move holds it on its green range circle, so you drag roughly the right direction and it takes the full legal distance. Off: the drag follows the cursor past the circle and the over-range drop is rejected. Controller carries are always clamped."
	drag_clamp_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	drag_clamp_help.custom_minimum_size = Vector2(620, 0)
	drag_clamp_help.add_theme_font_size_override("font_size", 16)
	drag_clamp_help.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	parent.add_child(drag_clamp_help)

	# The same idea pointed the other way, for reserves arriving from off-table:
	# without it, dropping a model at exactly 9" from the enemy means finding an
	# invisible line with the cursor.
	_placement_clamp_checkbox = _add_checkbox_row(parent, "Hold Deep Strike placement outside the 9\" exclusion zone", "_on_placement_clamp_toggled")
	var placement_clamp_help = Label.new()
	placement_clamp_help.text = "On: aiming a Deep Strike / Reserves / Infiltrators drop inside the 9\" enemy exclusion zone parks the model on the boundary — as close to the enemy as the rules allow — with a dashed line back to your cursor. Off: the ghost follows the cursor into the zone, turns red, and the drop is rejected. Controller placement is always clamped."
	placement_clamp_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	placement_clamp_help.custom_minimum_size = Vector2(620, 0)
	placement_clamp_help.add_theme_font_size_override("font_size", 16)
	placement_clamp_help.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	parent.add_child(placement_clamp_help)

	# Menu scroll speed — how fast the wheel / trackpad scrolls menus and panels
	# (a fraction of Godot's default). Lower = slower.
	_menu_scroll_speed_slider = _add_slider_row(parent, "Menu Scroll Speed:", 0.1, 1.0, 0.05, "_on_menu_scroll_speed_changed")
	_menu_scroll_speed_label = _get_last_value_label()
	var scroll_help = Label.new()
	scroll_help.text = "Speed of mouse-wheel / trackpad scrolling in menus, lists and panels (100% = default). Does not affect board zoom."
	scroll_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll_help.custom_minimum_size = Vector2(620, 0)
	scroll_help.add_theme_font_size_override("font_size", 16)
	scroll_help.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	parent.add_child(scroll_help)

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

func _add_mouse_info_row(parent: VBoxContainer, action_text: String, key_text: String) -> void:
	# Read-only row mirroring the keybinding-row layout (action name on the left,
	# the control on the right) for mouse actions that can't be rebound.
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var name_label = Label.new()
	name_label.text = action_text
	name_label.custom_minimum_size = Vector2(180, 0)
	name_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	row.add_child(name_label)

	var key_label = Label.new()
	key_label.text = key_text
	key_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	row.add_child(key_label)

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

# ============================================================================
# Controller Tab — pad layout rebinding (Settings › Controller)
# ============================================================================

func _pad_bindings() -> Node:
	# Lazy autoload lookup, same reasoning as _idm(): bare headless harnesses
	# instantiate this menu without the autoload set.
	return get_node_or_null("/root/PadBindings")


# Input Mode (owner request 2026-07-27). The game used to flip between the
# controller and the mouse/keyboard presentation on every input — on a Steam
# Deck a trackpad or back-paddle press reads as mouse/keyboard, so the UI (and
# with the controller text boost, the whole canvas scale) jumped around
# mid-game. The device is now resolved once at launch and locked; this section
# is where a player overrides that choice. Lives at the TOP of the Controller
# tab so it is the first thing a Deck player finds, and it is fully operable
# with the pad (focusable dropdown, D-pad + A).
func _build_input_mode_section(parent: VBoxContainer) -> void:
	_add_section_header(parent, "Input Mode")

	_input_mode_dropdown = _add_dropdown_row(parent, "Input Mode:", [
		"Auto-detect (Steam Deck / PC)",
		"Controller / Steam Deck",
		"Mouse & Keyboard",
		"Follow last input used",
	], "_on_input_mode_policy_selected")
	_input_mode_dropdown.name = "InputModeDropdown"
	WhiteDwarfThemeData.apply_to_button(_input_mode_dropdown)

	var help = Label.new()
	help.text = "The game no longer switches between the controller and mouse/keyboard layouts while you play — pick one here and it sticks. Auto-detect chooses the controller layout on a Steam Deck and the mouse & keyboard layout on a PC or in the browser (itch.io)."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(620, 0)
	help.add_theme_font_size_override("font_size", 16)
	help.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	parent.add_child(help)

	_input_mode_status_label = Label.new()
	# Distinct from MainMenu's own "InputModeStatus" label so a scenario/selector
	# naming either one is unambiguous.
	_input_mode_status_label.name = "InputModeStatusLabel"
	_input_mode_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_input_mode_status_label.custom_minimum_size = Vector2(620, 0)
	_input_mode_status_label.add_theme_font_size_override("font_size", 16)
	_input_mode_status_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	parent.add_child(_input_mode_status_label)
	_update_input_mode_status()


func _update_input_mode_status() -> void:
	if _input_mode_status_label == null or not is_instance_valid(_input_mode_status_label):
		return
	var idm := _idm()
	if idm == null or not idm.has_method("mode_status_text"):
		_input_mode_status_label.text = ""
		return
	_input_mode_status_label.text = "Currently using: %s" % idm.mode_status_text()


func _on_input_mode_policy_selected(index: int) -> void:
	if index < 0 or index >= INPUT_MODE_POLICIES.size():
		return
	if SettingsService:
		SettingsService.set_input_mode_policy(INPUT_MODE_POLICIES[index])
	_update_input_mode_status()
	print("[SettingsMenu] Input mode policy set to %s" % INPUT_MODE_POLICIES[index])


func _build_controller_tab(parent: VBoxContainer) -> void:
	var pb := _pad_bindings()

	_build_input_mode_section(parent)

	_add_section_header(parent, "Controller Buttons")
	var rebind_help = Label.new()
	rebind_help.text = "Click a control, then press the controller button you want for it. If another control already uses that button, the two swap places. The D-pad, sticks, triggers and Steam Deck back paddles keep their jobs and cannot be reassigned."
	rebind_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rebind_help.custom_minimum_size = Vector2(620, 0)
	rebind_help.add_theme_font_size_override("font_size", 16)
	rebind_help.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	parent.add_child(rebind_help)

	if pb == null:
		var err_label = Label.new()
		err_label.text = "PadBindings not available"
		err_label.add_theme_color_override("font_color", Color.RED)
		parent.add_child(err_label)
	else:
		for role_id in pb.get_role_ids():
			_add_pad_role_row(parent, role_id)

		var reset_all_row = HBoxContainer.new()
		reset_all_row.alignment = BoxContainer.ALIGNMENT_CENTER
		var reset_all_btn = Button.new()
		reset_all_btn.name = "PadResetAllButton"
		reset_all_btn.text = "Reset Controller Layout"
		reset_all_btn.custom_minimum_size = Vector2(220, 36)
		WhiteDwarfThemeData.apply_to_button(reset_all_btn)
		reset_all_btn.pressed.connect(_on_pad_reset_all_pressed)
		reset_all_row.add_child(reset_all_btn)
		parent.add_child(reset_all_row)

		if not pb.pad_binding_changed.is_connected(_on_pad_binding_changed):
			pb.pad_binding_changed.connect(_on_pad_binding_changed)

	# P0 Steam Deck legibility: opt-out for the controller text boost (larger UI
	# while a gamepad is the active device). On by default; a desktop player on a
	# big screen may prefer it off.
	_add_section_header(parent, "Controller Options")
	_controller_text_boost_checkbox = _add_checkbox_row(parent, "Larger UI text on controller / Steam Deck", "_on_controller_text_boost_toggled")
	var boost_help = Label.new()
	boost_help.text = "Boosts on-screen text and buttons while a controller is in use so they stay readable on the Steam Deck's screen. Mouse & keyboard are unaffected."
	boost_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	boost_help.custom_minimum_size = Vector2(620, 0)
	boost_help.add_theme_font_size_override("font_size", 16)
	boost_help.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	parent.add_child(boost_help)

	# P1 controller options — pad only; mouse & keyboard are unaffected.
	_pad_invert_y_checkbox = _add_checkbox_row(parent, "Invert camera Y (right stick up / down)", "_on_pad_invert_y_toggled")
	_pad_swap_sticks_checkbox = _add_checkbox_row(parent, "Swap sticks (cursor on right stick, camera on left)", "_on_pad_swap_sticks_toggled")
	_pad_magnetism_checkbox = _add_checkbox_row(parent, "Cursor magnetism (cursor eases onto nearby models)", "_on_pad_magnetism_toggled")
	# The board hover card is OFF on the pad by default: the virtual cursor sits on
	# the model being placed, so the card covers the spot the player is aiming at
	# (reported during charge moves). R4 / L4 peek at it on demand instead.
	_pad_hover_card_checkbox = _add_checkbox_row(parent, "Always show model stats card on hover", "_on_pad_hover_stats_card_toggled")
	var hover_help = Label.new()
	hover_help.text = "Off by default on controller: hold R4 or L4 to peek at the hovered model's stats card, so it never covers the spot you are moving or charging to. Turn on to keep the card up whenever the cursor rests on a model. Mouse & keyboard always show it."
	hover_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hover_help.custom_minimum_size = Vector2(620, 0)
	hover_help.add_theme_font_size_override("font_size", 16)
	hover_help.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	parent.add_child(hover_help)
	_pad_camera_sens_slider = _add_slider_row(parent, "Camera Sensitivity:", 0.3, 2.0, 0.1, "_on_pad_camera_sens_changed")
	_pad_camera_sens_label = _get_last_value_label()
	_pad_cursor_sens_slider = _add_slider_row(parent, "Cursor Sensitivity:", 0.3, 2.0, 0.1, "_on_pad_cursor_sens_changed")
	_pad_cursor_sens_label = _get_last_value_label()

	# Read-only reference of the whole pad scheme, drawn with the in-game glyph
	# chips — the chips render the button each role is CURRENTLY on, so this
	# reference follows the player's remaps live (rebuilt on pad_binding_changed).
	_add_section_header(parent, "Controller Reference")
	_pad_reference_box = VBoxContainer.new()
	_pad_reference_box.add_theme_constant_override("separation", 6)
	parent.add_child(_pad_reference_box)
	_add_controller_reference(_pad_reference_box)


func _add_pad_role_row(parent: VBoxContainer, role_id: String) -> void:
	var pb := _pad_bindings()
	var role: Dictionary = pb.get_role(role_id)
	if role.is_empty():
		return

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var name_label = Label.new()
	name_label.text = str(role.display_name)
	name_label.custom_minimum_size = Vector2(220, 0)
	name_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	row.add_child(name_label)

	var btn = Button.new()
	btn.name = "PadBind_" + role_id
	btn.text = pb.button_full_name(pb.get_button(role_id))
	btn.custom_minimum_size = Vector2(160, 30)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	WhiteDwarfThemeData.apply_to_button(btn)
	btn.pressed.connect(_on_pad_role_button_pressed.bind(role_id))
	row.add_child(btn)
	_pad_role_buttons[role_id] = btn

	var reset_btn = Button.new()
	reset_btn.text = "Reset"
	reset_btn.custom_minimum_size = Vector2(60, 30)
	WhiteDwarfThemeData.apply_to_button(reset_btn)
	reset_btn.pressed.connect(_on_pad_reset_role_pressed.bind(role_id))
	reset_btn.visible = pb.is_modified(role_id)
	row.add_child(reset_btn)
	_pad_role_reset_buttons[role_id] = reset_btn


func _on_pad_role_button_pressed(role_id: String) -> void:
	# A second click on the row being captured cancels the capture.
	if _pad_capturing_role == role_id:
		_cancel_pad_capture()
		return
	# Only one capture of either kind at a time.
	if _capturing_button:
		_cancel_capture()
	if _pad_capturing_button:
		_cancel_pad_capture()
	_pad_capturing_role = role_id
	_pad_capturing_button = _pad_role_buttons[role_id]
	_pad_capturing_button.text = "Press a controller button..."
	_pad_capturing_button.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	print("[SettingsMenu] Capturing controller button for '%s'" % role_id)


func _cancel_pad_capture() -> void:
	if _pad_capturing_button and _pad_capturing_role != "":
		var pb := _pad_bindings()
		if pb != null:
			_pad_capturing_button.text = pb.button_full_name(pb.get_button(_pad_capturing_role))
		_pad_capturing_button.remove_theme_color_override("font_color")
		WhiteDwarfThemeData.apply_to_button(_pad_capturing_button)
	_pad_capturing_role = ""
	_pad_capturing_button = null


func _on_pad_reset_role_pressed(role_id: String) -> void:
	var pb := _pad_bindings()
	if pb != null:
		pb.reset_role(role_id)
	print("[SettingsMenu] Reset controller binding for '%s'" % role_id)


func _on_pad_reset_all_pressed() -> void:
	_cancel_pad_capture()
	var pb := _pad_bindings()
	if pb != null:
		pb.reset_all()
	print("[SettingsMenu] Reset controller layout to defaults")


func _on_pad_binding_changed(role_id: String) -> void:
	_update_pad_role_display(role_id)
	# The read-only reference chips render role glyphs — rebuild so they follow.
	if _pad_reference_box != null and is_instance_valid(_pad_reference_box):
		for child in _pad_reference_box.get_children():
			child.queue_free()
		_add_controller_reference(_pad_reference_box)


func _update_pad_role_display(role_id: String) -> void:
	var pb := _pad_bindings()
	if pb == null:
		return
	if _pad_role_buttons.has(role_id) and _pad_capturing_role != role_id:
		_pad_role_buttons[role_id].text = pb.button_full_name(pb.get_button(role_id))
	if _pad_role_reset_buttons.has(role_id):
		_pad_role_reset_buttons[role_id].visible = pb.is_modified(role_id)


# Pad-button capture runs in _input (NOT _unhandled_input): the press must be
# swallowed BEFORE the GUI focus layer sees it, or capturing A/B would activate
# the focused control / close the menu instead of assigning the button.
func _input(event: InputEvent) -> void:
	if _pad_capturing_role == "" or not (event is InputEventJoypadButton) or not event.pressed:
		return
	var pb := _pad_bindings()
	if pb == null:
		_cancel_pad_capture()
		return
	if not pb.is_button_assignable(event.button_index):
		# Reserved (D-pad / Guide): tell the player and keep listening.
		if _pad_capturing_button:
			_pad_capturing_button.text = "Reserved — press another button"
		get_viewport().set_input_as_handled()
		return
	var role := _pad_capturing_role
	var capturing_btn := _pad_capturing_button
	_pad_capturing_role = ""
	_pad_capturing_button = null
	if capturing_btn:
		capturing_btn.remove_theme_color_override("font_color")
		WhiteDwarfThemeData.apply_to_button(capturing_btn)
	pb.set_button(role, event.button_index)
	_update_pad_role_display(role)
	get_viewport().set_input_as_handled()

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
	header.add_theme_font_size_override("font_size", 20)
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
	var board_style_index = ["grass", "mud", "desert", "stone", "felt", "tilepack", "none"].find(SettingsService.board_style)
	if board_style_index >= 0:
		_board_style_dropdown.selected = board_style_index
	var ruins_style_index = ["concrete", "marble", "brick", "weathered_stone", "none"].find(SettingsService.ruins_style)
	if ruins_style_index >= 0:
		_ruins_style_dropdown.selected = ruins_style_index
	var style_index = ["letter", "enhanced", "style_a", "style_b", "classic"].find(SettingsService.unit_visual_style)
	if style_index >= 0:
		_visual_style_dropdown.selected = style_index
	if _unit_color_display_dropdown:
		var color_mode_index = ["full", "ring"].find(SettingsService.unit_color_display_mode)
		if color_mode_index >= 0:
			_unit_color_display_dropdown.selected = color_mode_index
	_ui_scale_slider.value = SettingsService.ui_scale
	_update_scale_label(_ui_scale_label, SettingsService.ui_scale)
	_animation_speed_slider.value = SettingsService.animation_speed
	_update_speed_label(_animation_speed_label, SettingsService.animation_speed)
	var cb_index = ["none", "protanopia", "deuteranopia", "tritanopia"].find(SettingsService.colorblind_mode)
	if cb_index >= 0:
		_colorblind_dropdown.selected = cb_index
	if _terrain_debug_checkbox:
		_terrain_debug_checkbox.button_pressed = SettingsService.terrain_debug_labels
	if _terrain_scatter_checkbox:
		_terrain_scatter_checkbox.button_pressed = SettingsService.show_terrain_scatter
	if _terrain_cover_checkbox:
		_terrain_cover_checkbox.button_pressed = SettingsService.show_terrain_cover_labels
	if _los_debug_out_of_range_checkbox:
		_los_debug_out_of_range_checkbox.button_pressed = SettingsService.los_debug_check_out_of_range

	# Gameplay
	if _auto_allocate_checkbox:
		_auto_allocate_checkbox.button_pressed = SettingsService.auto_allocate_wounds
	if _hotseat_handoff_checkbox:
		_hotseat_handoff_checkbox.button_pressed = SettingsService.hotseat_handoff_enabled
	if _tutorial_language_dropdown:
		# Show what is actually in force (get_ folds in the harness pin).
		var lang_index := TUTORIAL_LANGUAGES.find(str(SettingsService.get_tutorial_language()))
		if lang_index >= 0:
			_tutorial_language_dropdown.selected = lang_index

	# Display
	if _window_mode_dropdown:
		_window_mode_dropdown.selected = maxi(0, WINDOW_MODES.find(SettingsService.window_mode))
	if _resolution_dropdown:
		var res_idx := WINDOW_RESOLUTIONS.find(SettingsService.window_resolution)
		_resolution_dropdown.selected = res_idx if res_idx >= 0 else WINDOW_RESOLUTIONS.find(Vector2i(1920, 1080))
	if _vsync_checkbox:
		_vsync_checkbox.button_pressed = SettingsService.vsync_enabled
	if _autosave_phase_start_checkbox:
		_autosave_phase_start_checkbox.button_pressed = SettingsService.autosave_on_phase_start

	# Controls
	if _menu_scroll_speed_slider:
		_menu_scroll_speed_slider.value = SettingsService.menu_scroll_speed
		_update_scroll_speed_label(_menu_scroll_speed_label, SettingsService.menu_scroll_speed)
	if _drag_clamp_checkbox:
		_drag_clamp_checkbox.button_pressed = SettingsService.drag_clamp_to_max_range
	if _placement_clamp_checkbox:
		_placement_clamp_checkbox.button_pressed = SettingsService.placement_clamp_to_exclusion
	if _input_mode_dropdown:
		var policy_index := INPUT_MODE_POLICIES.find(str(SettingsService.input_mode_policy))
		# A run whose policy came from --input-mode= (or the harness pin) can be
		# out of step with the saved value — show what is actually in force.
		var idm := _idm()
		if idm != null and str(idm.get("mode_policy")) in INPUT_MODE_POLICIES:
			policy_index = INPUT_MODE_POLICIES.find(str(idm.get("mode_policy")))
		if policy_index >= 0:
			_input_mode_dropdown.selected = policy_index
		_update_input_mode_status()
	if _controller_text_boost_checkbox:
		_controller_text_boost_checkbox.button_pressed = SettingsService.controller_text_boost
	if _pad_invert_y_checkbox:
		_pad_invert_y_checkbox.button_pressed = SettingsService.pad_invert_camera_y
	if _pad_swap_sticks_checkbox:
		_pad_swap_sticks_checkbox.button_pressed = SettingsService.pad_swap_sticks
	if _pad_magnetism_checkbox:
		_pad_magnetism_checkbox.button_pressed = SettingsService.pad_cursor_magnetism
	if _pad_hover_card_checkbox:
		_pad_hover_card_checkbox.button_pressed = SettingsService.pad_hover_stats_card
	if _pad_camera_sens_slider:
		_pad_camera_sens_slider.value = SettingsService.pad_camera_sensitivity
		if _pad_camera_sens_label:
			_pad_camera_sens_label.text = "%.1fx" % SettingsService.pad_camera_sensitivity
	if _pad_cursor_sens_slider:
		_pad_cursor_sens_slider.value = SettingsService.pad_cursor_sensitivity
		if _pad_cursor_sens_label:
			_pad_cursor_sens_label.text = "%.1fx" % SettingsService.pad_cursor_sensitivity

func _connect_signals() -> void:
	# Update in-game-only button visibility
	_return_to_menu_button.visible = show_return_to_menu
	_save_load_button.visible = show_return_to_menu

	# SAVE-8: Update button text for non-host multiplayer clients
	if show_return_to_menu and NetworkManager and NetworkManager.is_networked() and not NetworkManager.is_host():
		_save_load_button.text = "Save Game"
		print("[SettingsMenu] SAVE-8: Non-host client — changed button to 'Save Game'")

# ============================================================================
# Value label formatters
# ============================================================================

func _update_volume_label(label: Label, value: float) -> void:
	label.text = "%d%%" % int(value * 100)

func _update_scale_label(label: Label, value: float) -> void:
	label.text = "%.1fx" % value

func _update_speed_label(label: Label, value: float) -> void:
	label.text = "%.2fx" % value

func _update_scroll_speed_label(label: Label, value: float) -> void:
	label.text = "%d%%" % int(round(value * 100.0))

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

func _on_board_style_changed(index: int) -> void:
	var styles = ["grass", "mud", "desert", "stone", "felt", "tilepack", "none"]
	if index >= 0 and index < styles.size():
		SettingsService.set_board_style(styles[index])

func _on_ruins_style_changed(index: int) -> void:
	var styles = ["concrete", "marble", "brick", "weathered_stone", "none"]
	if index >= 0 and index < styles.size():
		SettingsService.set_ruins_style(styles[index])

func _on_visual_style_changed(index: int) -> void:
	var styles = ["letter", "enhanced", "style_a", "style_b", "classic"]
	if index >= 0 and index < styles.size():
		SettingsService.set_unit_visual_style_setting(styles[index])

func _on_unit_color_display_changed(index: int) -> void:
	var modes = ["full", "ring"]
	if index >= 0 and index < modes.size():
		SettingsService.set_unit_color_display_mode(modes[index])

func _on_ui_scale_changed(value: float) -> void:
	SettingsService.set_ui_scale(value)
	_update_scale_label(_ui_scale_label, value)

func _on_animation_speed_changed(value: float) -> void:
	SettingsService.set_animation_speed(value)
	_update_speed_label(_animation_speed_label, value)

func _on_menu_scroll_speed_changed(value: float) -> void:
	SettingsService.set_menu_scroll_speed(value)
	_update_scroll_speed_label(_menu_scroll_speed_label, value)

func _on_drag_clamp_toggled(pressed: bool) -> void:
	# MovementController re-reads this on every drag motion event, so the change
	# applies to the very next drag — no reload, no re-select.
	SettingsService.set_drag_clamp_to_max_range(pressed)

func _on_placement_clamp_toggled(pressed: bool) -> void:
	# DeploymentController re-reads this every frame it updates the placement
	# ghost, so the change applies to the placement already in progress.
	SettingsService.set_placement_clamp_to_exclusion(pressed)

func _on_controller_text_boost_toggled(pressed: bool) -> void:
	SettingsService.set_controller_text_boost(pressed)

func _on_pad_invert_y_toggled(pressed: bool) -> void:
	SettingsService.set_pad_invert_camera_y(pressed)

func _on_pad_swap_sticks_toggled(pressed: bool) -> void:
	SettingsService.set_pad_swap_sticks(pressed)

func _on_pad_magnetism_toggled(pressed: bool) -> void:
	SettingsService.set_pad_cursor_magnetism(pressed)

func _on_pad_hover_stats_card_toggled(pressed: bool) -> void:
	# PadRouter listens on pad_hover_stats_card_changed: turning the card ON hands
	# R4 / L4 back to their model-hop meaning (and vice versa), and the hint bar
	# refreshes with it.
	SettingsService.set_pad_hover_stats_card(pressed)
	# The Controller Reference names R4 / L4's live meaning — redraw it.
	if _pad_reference_box != null and is_instance_valid(_pad_reference_box):
		for child in _pad_reference_box.get_children():
			child.queue_free()
		_add_controller_reference(_pad_reference_box)

func _on_pad_camera_sens_changed(value: float) -> void:
	SettingsService.set_pad_camera_sensitivity(value)
	if _pad_camera_sens_label:
		_pad_camera_sens_label.text = "%.1fx" % value

func _on_pad_cursor_sens_changed(value: float) -> void:
	SettingsService.set_pad_cursor_sensitivity(value)
	if _pad_cursor_sens_label:
		_pad_cursor_sens_label.text = "%.1fx" % value

func _add_controller_reference(parent: VBoxContainer) -> void:
	# A compact, accurate map of the whole pad scheme, rendered with the same glyph
	# chips the in-game hint bar uses (GlyphDB). Read-only — the face-button routing
	# is context-dependent, so this documents rather than rebinds it.
	var rows := [
		["ls", "Move the on-screen cursor / point at the board"],
		["rs", "Move the camera  ·  click (R3) = precision (slow) mode"],
		["lb", "Cycle to the previous unit / target"],
		["rb", "Cycle to the next unit / target"],
		["a", "Select  ·  confirm  ·  pick up a model"],
		["b", "Cancel  ·  back to the board"],
		["x", "Skip  ·  undo the last model"],
		["y", "Show the unit's datasheet"],
		["dpad", "Menus, movement options & weapon / target rows"],
	]
	# R4 / L4 gain their hold-to-peek meaning only while the hover card is
	# suppressed (see PadRouter._handle_stats_peek), so say which is live.
	if SettingsService.pad_hover_stats_card:
		rows.append(["l4", "Previous model in the unit while moving (Steam Deck back paddle)"])
		rows.append(["r4", "Next model in the unit while moving (Steam Deck back paddle)"])
	else:
		rows.append(["l4", "Tap: previous model  ·  Hold: the hovered model's stats card"])
		rows.append(["r4", "Tap: next model  ·  Hold: the hovered model's stats card"])
	rows.append_array([
		["l5", "Previous model in the unit while moving (Steam Deck back paddle)"],
		["r5", "Next model in the unit while moving (Steam Deck back paddle)"],
		["lt", "Zoom out"],
		["rt", "Zoom in"],
		["menu", "End phase / confirm  (Start)"],
		["view", "Pause menu  (View / Select)"],
	])
	for r in rows:
		var chip: Control = GlyphDB.make_chip(str(r[0]), str(r[1]))
		parent.add_child(chip)

func _on_colorblind_changed(index: int) -> void:
	var modes = ["none", "protanopia", "deuteranopia", "tritanopia"]
	if index >= 0 and index < modes.size():
		SettingsService.set_colorblind_mode(modes[index])

func _on_terrain_debug_labels_toggled(pressed: bool) -> void:
	SettingsService.set_terrain_debug_labels(pressed)

func _on_terrain_scatter_toggled(pressed: bool) -> void:
	SettingsService.set_show_terrain_scatter(pressed)

func _on_terrain_cover_labels_toggled(pressed: bool) -> void:
	SettingsService.set_show_terrain_cover_labels(pressed)

func _on_los_debug_out_of_range_toggled(pressed: bool) -> void:
	SettingsService.set_los_debug_check_out_of_range(pressed)

# ============================================================================
# Gameplay Callbacks
# ============================================================================

func _on_auto_allocate_wounds_toggled(pressed: bool) -> void:
	SettingsService.set_auto_allocate_wounds(pressed)

func _on_hotseat_handoff_toggled(pressed: bool) -> void:
	SettingsService.set_hotseat_handoff_enabled(pressed)

func _on_tutorial_language_selected(index: int) -> void:
	if index >= 0 and index < TUTORIAL_LANGUAGES.size():
		SettingsService.set_tutorial_language(TUTORIAL_LANGUAGES[index])

# ============================================================================
# Display Callbacks
# ============================================================================

func _on_window_mode_changed(index: int) -> void:
	SettingsService.set_window_mode(WINDOW_MODES[clampi(index, 0, WINDOW_MODES.size() - 1)])

func _on_window_resolution_changed(index: int) -> void:
	SettingsService.set_window_resolution(WINDOW_RESOLUTIONS[clampi(index, 0, WINDOW_RESOLUTIONS.size() - 1)])

func _on_vsync_toggled(pressed: bool) -> void:
	SettingsService.set_vsync_enabled(pressed)

func _on_autosave_phase_start_toggled(pressed: bool) -> void:
	SettingsService.set_autosave_on_phase_start(pressed)

# ============================================================================
# Button Callbacks
# ============================================================================

func _on_close_pressed() -> void:
	print("[SettingsMenu] Closed")
	# Restore focus modes BEFORE emitting: a settings_closed handler that
	# re-focuses the opener (e.g. MainMenu's Settings button) must find it
	# focusable again. _exit_tree's release would run only at end-of-frame.
	_release_pad_focus_confinement()
	settings_closed.emit()
	queue_free()

func _on_save_load_pressed() -> void:
	print("[SettingsMenu] Save/Load requested")
	# Release FIRST so the handoff hands SaveLoadDialog a clean, all-focusable
	# baseline to run its OWN confinement against — otherwise our end-of-frame
	# _exit_tree restore would re-enable the controls SaveLoadDialog just
	# demoted, breaking its focus trap.
	_release_pad_focus_confinement()
	save_load_requested.emit()
	settings_closed.emit()
	queue_free()

func _on_quit_to_desktop_pressed() -> void:
	print("[SettingsMenu] Quit to Desktop")
	get_tree().quit()

func _on_return_to_menu_pressed() -> void:
	print("[SettingsMenu] Returning to main menu")
	_release_pad_focus_confinement()
	settings_closed.emit()
	queue_free()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

# ============================================================================
# Input handling — Escape to close, key capture for Controls tab
# ============================================================================

func _unhandled_input(event: InputEvent) -> void:
	# Escape cancels an active controller-button capture (joypad presses are
	# handled — and consumed — in _input above).
	if _pad_capturing_role != "" and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_pad_capture()
		get_viewport().set_input_as_handled()
		return

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
		var new_meta = event.meta_pressed

		# Check for conflicts
		var conflict_id = KeybindingManager.find_conflict(_capturing_action_id, new_key, new_shift, new_ctrl, new_alt, new_meta)
		if conflict_id != "":
			# Auto-swap: clear the conflicting binding by setting it to KEY_NONE (0)
			KeybindingManager.set_binding(conflict_id, 0, false, false, false, false)
			_update_keybinding_display(conflict_id)
			print("[SettingsMenu] Conflict resolved: cleared '%s'" % conflict_id)

		# Apply the new binding
		KeybindingManager.set_binding(_capturing_action_id, new_key, new_shift, new_ctrl, new_alt, new_meta)
		_update_keybinding_display(_capturing_action_id)

		# Exit capture mode
		_capturing_button.remove_theme_color_override("font_color")
		WhiteDwarfThemeData.apply_to_button(_capturing_button)
		_capturing_action_id = ""
		_capturing_button = null

		get_viewport().set_input_as_handled()
		return

	# Close on ui_cancel so both Escape and the pad's B button work (M1).
	if event.is_action_pressed("ui_cancel"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()


# ============================================================================
# Controller (D-pad) focus support — see the PAD_MODAL_GROUP block near the top.
# Mirrors AllocationGroupOverlay / SaveLoadDialog so every full-screen modal
# traps the pad the same way.
# ============================================================================

func _idm() -> Node:
	# Lazy autoload lookup (autoload ids are not compile-time resolvable in the
	# bare headless harness runs this menu must keep compiling under).
	return get_node_or_null("/root/InputDeviceManager")


func _pad_active() -> bool:
	var idm := _idm()
	return idm != null and idm.has_method("is_pad_active") and idm.is_pad_active()


func _on_pad_device_changed(_mode: int) -> void:
	# Player switched device while the menu is open. On the pad, confine and
	# keep focus in the menu; back on KBM, release so keyboard focus is not
	# trapped.
	if not is_inside_tree():
		return
	# Keep the Input Mode readout ("Currently using: …") truthful while open.
	_update_input_mode_status()
	if _pad_active():
		if not _pad_focus_confined:
			_confine_pad_focus()
		if _close_button != null and is_instance_valid(_close_button):
			_close_button.grab_focus()
	else:
		_release_pad_focus_confinement()


# Trap directional focus inside this menu: demote every focusable Control
# OUTSIDE our subtree to FOCUS_NONE (restored on close / KBM). Idempotent —
# guarded by _pad_focus_confined.
func _confine_pad_focus() -> void:
	if _pad_focus_confined:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	_pad_confined_controls.clear()
	var queue: Array = [scene]
	while not queue.is_empty():
		var n: Node = queue.pop_front()
		if n == self:
			continue  # skip our own subtree — its controls must stay focusable
		if n is Control and n.focus_mode == Control.FOCUS_ALL:
			_pad_confined_controls.append(n)
			n.focus_mode = Control.FOCUS_NONE
		for child in n.get_children():
			queue.append(child)
	_pad_focus_confined = true
	print("[SettingsMenu] pad focus confined (%d external controls demoted)" % _pad_confined_controls.size())


func _release_pad_focus_confinement() -> void:
	if not _pad_focus_confined:
		return
	for c in _pad_confined_controls:
		if is_instance_valid(c):
			c.focus_mode = Control.FOCUS_ALL
	_pad_confined_controls.clear()
	_pad_focus_confined = false
	print("[SettingsMenu] pad focus confinement released")


func _exit_tree() -> void:
	# Belt-and-braces: restore focus modes and drop the device hook if any close
	# path was missed (idempotent — the flag guards a double release).
	_release_pad_focus_confinement()
	var idm := _idm()
	if idm != null and idm.has_signal("device_changed") and idm.device_changed.is_connected(_on_pad_device_changed):
		idm.device_changed.disconnect(_on_pad_device_changed)
