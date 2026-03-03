extends PanelContainer
class_name KeyboardShortcutOverlay

# P3-54: Toggleable keyboard shortcut reference overlay during deployment
# Press ? (Shift+/) to show/hide

var _title_label: Label
var _shortcuts_container: VBoxContainer

func _ready() -> void:
	_build_ui()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	print("[KeyboardShortcutOverlay] Ready")

func _build_ui() -> void:
	# Apply WhiteDwarf theme panel style with slight transparency
	var style = WhiteDwarfTheme.create_panel_style()
	style.bg_color = Color(0.08, 0.07, 0.05, 0.92)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	# Title
	_title_label = Label.new()
	_title_label.text = "DEPLOYMENT CONTROLS"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	WhiteDwarfTheme.apply_to_label(_title_label, true)
	_title_label.add_theme_font_size_override("font_size", 14)
	var bold_font = SystemFont.new()
	bold_font.font_weight = 700
	_title_label.add_theme_font_override("font", bold_font)
	vbox.add_child(_title_label)

	# Separator line
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	sep.add_theme_stylebox_override("separator", _create_separator_style())
	vbox.add_child(sep)

	# Shortcuts container
	_shortcuts_container = VBoxContainer.new()
	_shortcuts_container.add_theme_constant_override("separation", 2)
	vbox.add_child(_shortcuts_container)

	# Add deployment shortcuts (dynamic from KeybindingManager)
	var _rl = KeybindingManager.get_key_display_name("rotate_left") if KeybindingManager else "Q"
	var _rr = KeybindingManager.get_key_display_name("rotate_right") if KeybindingManager else "E"
	_add_shortcut("%s / %s" % [_rl, _rr], "Rotate model 15°")
	_add_shortcut("Mouse Wheel", "Rotate model 15°")
	_add_shortcut("Shift + Click", "Reposition placed model")
	_add_shortcut("Right Click", "Cancel reposition")
	var _undo = KeybindingManager.get_key_display_name("undo_deployment") if KeybindingManager else "Ctrl+Z"
	_add_shortcut(_undo, "Undo last model")

	# Separator before formation section
	var sep2 = HSeparator.new()
	sep2.add_theme_constant_override("separation", 4)
	sep2.add_theme_stylebox_override("separator", _create_separator_style())
	_shortcuts_container.add_child(sep2)

	# Formation modes header
	var formation_header = Label.new()
	formation_header.text = "Formation Modes"
	formation_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	formation_header.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	formation_header.add_theme_font_size_override("font_size", 12)
	_shortcuts_container.add_child(formation_header)

	_add_shortcut("Single", "Place one model at a time")
	_add_shortcut("Spread (2\")", "Formation with 2\" spacing")
	_add_shortcut("Tight", "Compact formation")

	# Separator before general section
	var sep3 = HSeparator.new()
	sep3.add_theme_constant_override("separation", 4)
	sep3.add_theme_stylebox_override("separator", _create_separator_style())
	_shortcuts_container.add_child(sep3)

	# General shortcuts header
	var general_header = Label.new()
	general_header.text = "General"
	general_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	general_header.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	general_header.add_theme_font_size_override("font_size", 12)
	_shortcuts_container.add_child(general_header)

	var _dz = KeybindingManager.get_key_display_name("toggle_deploy_zones") if KeybindingManager else "Z"
	var _tt = KeybindingManager.get_key_display_name("toggle_terrain") if KeybindingManager else "G"
	var _mt = KeybindingManager.get_key_display_name("measuring_tape") if KeybindingManager else "T"
	var _cm = KeybindingManager.get_key_display_name("clear_measurements") if KeybindingManager else "Y"
	var _zu = KeybindingManager.get_key_display_name("zoom_in") if KeybindingManager else "="
	var _zd = KeybindingManager.get_key_display_name("zoom_out") if KeybindingManager else "-"
	var _rb = KeybindingManager.get_key_display_name("rotate_board") if KeybindingManager else "V"
	var _ul = KeybindingManager.get_key_display_name("toggle_unit_labels") if KeybindingManager else "N"
	_add_shortcut(_dz, "Toggle deployment zones")
	_add_shortcut(_tt, "Toggle terrain")
	_add_shortcut(_ul, "Toggle unit labels")
	_add_shortcut("%s (hold)" % _mt, "Measuring tape")
	_add_shortcut(_cm, "Clear measurements")
	_add_shortcut("W/A/S/D", "Pan camera")
	_add_shortcut("%s  /  %s" % [_zu, _zd], "Zoom in/out")
	_add_shortcut(_rb, "Rotate board view")

	# Dismiss hint at bottom
	var sep4 = HSeparator.new()
	sep4.add_theme_constant_override("separation", 4)
	sep4.add_theme_stylebox_override("separator", _create_separator_style())
	_shortcuts_container.add_child(sep4)

	var hint_label = Label.new()
	hint_label.text = "Press ? to close"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45, 0.7))
	hint_label.add_theme_font_size_override("font_size", 11)
	_shortcuts_container.add_child(hint_label)

	add_child(vbox)

func _add_shortcut(key_text: String, description: String) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	# Key label (fixed width, right-aligned)
	var key_label = Label.new()
	key_label.text = key_text
	key_label.custom_minimum_size.x = 110
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	key_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	key_label.add_theme_font_size_override("font_size", 12)
	var mono_font = SystemFont.new()
	mono_font.font_weight = 600
	key_label.add_theme_font_override("font", mono_font)
	hbox.add_child(key_label)

	# Description label
	var desc_label = Label.new()
	desc_label.text = description
	desc_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_PARCHMENT)
	desc_label.add_theme_font_size_override("font_size", 12)
	hbox.add_child(desc_label)

	_shortcuts_container.add_child(hbox)

func _create_separator_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.4, 0.3, 0.2, 0.3)
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	return style

func toggle() -> void:
	visible = not visible
	print("[KeyboardShortcutOverlay] Toggled visibility: %s" % str(visible))
