extends RefCounted
class_name WhiteDwarfTheme

# White Dwarf Battle Report Theme - Gothic red/black/gold UI chrome
# All styles are procedural StyleBoxFlat resources (no .tres files needed)

# ── Core Palette ──────────────────────────────────────────────
const WH_RED = Color(0.604, 0.067, 0.082)        # #9A1115
const WH_BLACK = Color(0.1, 0.09, 0.07)           # Near-black warm
const WH_GOLD = Color(0.833, 0.588, 0.376)        # #D49761
const WH_PARCHMENT = Color(0.922, 0.882, 0.780)   # #EBE1C7
const WH_BONE = Color(0.85, 0.8, 0.65)            # Bone/ivory

# Player colors
const P1_FILL = Color(0.2, 0.25, 0.45)            # Dark blue-gray
const P1_BORDER = Color(0.83, 0.59, 0.38)         # Gold
const P2_FILL = Color(0.5, 0.12, 0.1)             # Deep crimson
const P2_BORDER = Color(0.85, 0.8, 0.65)          # Bone

# Board colors
const FELT_GREEN = Color(0.15, 0.35, 0.12)
const GRID_GREEN = Color(0.2, 0.45, 0.2, 0.2)
const BORDER_WOOD = Color(0.35, 0.28, 0.15)
const BORDER_GOLD_ACCENT = Color(0.83, 0.59, 0.38, 0.6)

# ── Factory Methods ───────────────────────────────────────────

static func create_panel_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.09, 0.07, 0.95)
	style.border_color = WH_GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	return style

static func create_header_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.12, 0.08, 0.95)
	style.border_color = WH_GOLD
	style.border_width_bottom = 2
	style.set_corner_radius_all(2)
	style.set_content_margin_all(6)
	return style

static func create_button_normal() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.13, 0.1, 0.9)
	style.border_color = WH_GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(8)
	return style

static func create_button_hover() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = WH_RED
	style.border_color = WH_GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(8)
	return style

static func create_button_pressed() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.45, 0.05, 0.06)  # Darker red
	style.border_color = WH_PARCHMENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(8)
	return style

static func create_button_disabled() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.09, 0.07, 0.7)
	style.border_color = Color(0.4, 0.3, 0.2, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(8)
	return style

static func create_button_focus() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.13, 0.1, 0.9)
	style.border_color = WH_PARCHMENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(8)
	return style

static func create_item_list_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.05, 0.9)
	style.border_color = Color(0.4, 0.3, 0.2, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(4)
	return style

# ── Applicator Methods ────────────────────────────────────────

static func apply_to_panel(panel: PanelContainer) -> void:
	if not panel:
		return
	panel.add_theme_stylebox_override("panel", create_panel_style())

static func apply_to_button(button: Button) -> void:
	if not button:
		return
	button.add_theme_stylebox_override("normal", create_button_normal())
	button.add_theme_stylebox_override("hover", create_button_hover())
	button.add_theme_stylebox_override("pressed", create_button_pressed())
	button.add_theme_stylebox_override("disabled", create_button_disabled())
	button.add_theme_stylebox_override("focus", create_button_focus())
	button.add_theme_color_override("font_color", WH_PARCHMENT)
	button.add_theme_color_override("font_hover_color", WH_PARCHMENT)
	button.add_theme_color_override("font_pressed_color", WH_GOLD)
	button.add_theme_color_override("font_disabled_color", Color(0.5, 0.45, 0.35, 0.6))

static func apply_to_label(label: Label, is_header: bool = false) -> void:
	if not label:
		return
	if is_header:
		label.add_theme_color_override("font_color", WH_GOLD)
		label.add_theme_font_size_override("font_size", 16)
	else:
		label.add_theme_color_override("font_color", WH_PARCHMENT)

static func apply_to_item_list(item_list: ItemList) -> void:
	if not item_list:
		return
	item_list.add_theme_stylebox_override("panel", create_item_list_style())
	item_list.add_theme_color_override("font_color", WH_PARCHMENT)
	item_list.add_theme_color_override("font_selected_color", WH_GOLD)
	# Selected item background
	var selected_style = StyleBoxFlat.new()
	selected_style.bg_color = Color(0.3, 0.15, 0.1, 0.8)
	selected_style.set_corner_radius_all(2)
	item_list.add_theme_stylebox_override("selected", selected_style)
	item_list.add_theme_stylebox_override("selected_focus", selected_style)

# Populate the shared White Dwarf control chrome (buttons, labels, option
# buttons, separators, item lists) into a Theme. Used by both apply_to_dialog
# (Window-based AcceptDialogs) and apply_to_control_theme (Control-based
# overlays) so every modal shares one visual language.
static func _apply_common_theme_entries(theme: Theme) -> void:
	# Button styles for dialog buttons (OK, Cancel, etc.)
	theme.set_stylebox("normal", "Button", create_button_normal())
	theme.set_stylebox("hover", "Button", create_button_hover())
	theme.set_stylebox("pressed", "Button", create_button_pressed())
	theme.set_stylebox("disabled", "Button", create_button_disabled())
	theme.set_stylebox("focus", "Button", create_button_focus())
	theme.set_color("font_color", "Button", WH_PARCHMENT)
	theme.set_color("font_hover_color", "Button", WH_PARCHMENT)
	theme.set_color("font_pressed_color", "Button", WH_GOLD)
	theme.set_color("font_disabled_color", "Button", Color(0.5, 0.45, 0.35, 0.5))
	# Label colors
	theme.set_color("font_color", "Label", WH_PARCHMENT)
	# CheckBox styling
	theme.set_color("font_color", "CheckBox", WH_PARCHMENT)
	theme.set_color("font_hover_color", "CheckBox", WH_GOLD)
	theme.set_color("font_pressed_color", "CheckBox", WH_GOLD)
	# OptionButton styling
	theme.set_stylebox("normal", "OptionButton", create_button_normal())
	theme.set_stylebox("hover", "OptionButton", create_button_hover())
	theme.set_stylebox("pressed", "OptionButton", create_button_pressed())
	theme.set_stylebox("focus", "OptionButton", create_button_focus())
	theme.set_color("font_color", "OptionButton", WH_PARCHMENT)
	theme.set_color("font_hover_color", "OptionButton", WH_PARCHMENT)
	theme.set_color("font_pressed_color", "OptionButton", WH_GOLD)
	# HSeparator styling
	var sep_style = StyleBoxFlat.new()
	sep_style.bg_color = Color(WH_GOLD, 0.3)
	sep_style.content_margin_top = 1
	sep_style.content_margin_bottom = 1
	theme.set_stylebox("separator", "HSeparator", sep_style)
	# ItemList styling
	theme.set_stylebox("panel", "ItemList", create_item_list_style())
	theme.set_color("font_color", "ItemList", WH_PARCHMENT)
	theme.set_color("font_selected_color", "ItemList", WH_GOLD)
	var item_selected_style = StyleBoxFlat.new()
	item_selected_style.bg_color = Color(0.3, 0.15, 0.1, 0.8)
	item_selected_style.set_corner_radius_all(2)
	theme.set_stylebox("selected", "ItemList", item_selected_style)
	theme.set_stylebox("selected_focus", "ItemList", item_selected_style)

static func apply_to_dialog(dialog: Window) -> void:
	if not dialog:
		return
	# Style the dialog window background and chrome
	var theme = Theme.new()
	# Window panel background
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.09, 0.07, 0.97)
	panel_style.border_color = WH_GOLD
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(4)
	panel_style.set_content_margin_all(10)
	theme.set_stylebox("embedded_border", "Window", panel_style)
	# Title font color
	theme.set_color("title_color", "Window", WH_GOLD)
	_apply_common_theme_entries(theme)
	dialog.theme = theme

	# Safety net: if this dialog ever opens larger than the viewport (e.g. a tall
	# autowrap Label ballooned its minimum height), clamp it back on-screen so its
	# action buttons can never end up unreachable. Only fires on actual overflow,
	# so correctly-sized dialogs are untouched.
	DialogUtils.arm_overflow_guard(dialog)

# Apply the White Dwarf chrome to a Control-based overlay (not a Window).
# Cascades to every Button / Label / OptionButton / ItemList descendant so a
# hand-built overlay matches the AcceptDialog-based dialogs without theming
# each widget individually. Per-widget overrides still win where an accent is
# wanted (gold headers, primary/red action buttons).
static func apply_to_control_theme(control: Control) -> void:
	if not control:
		return
	var theme = Theme.new()
	_apply_common_theme_entries(theme)
	control.theme = theme

static func apply_to_overlay_panel(panel: PanelContainer) -> void:
	if not panel:
		return
	var style = create_panel_style()
	style.bg_color = Color(0.1, 0.09, 0.07, 0.97)
	panel.add_theme_stylebox_override("panel", style)

# Shared gold accent separator — a thin translucent-gold bar between sections.
# Matches the divider used across the shooting dialogs so every modal breaks
# its sections up the same way.
static func add_gold_separator(parent: Control) -> void:
	if not parent:
		return
	var sep = ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.color = Color(WH_GOLD.r, WH_GOLD.g, WH_GOLD.b, 0.4)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(sep)

# ── Color Helpers for BBCode ─────────────────────────────────────────
# Hex color strings for use in RichTextLabel BBCode

static func create_primary_button_normal() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.6, 0.07, 0.08, 0.95)
	style.border_color = WH_GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	return style

static func create_primary_button_hover() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.75, 0.1, 0.1, 0.95)
	style.border_color = WH_PARCHMENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	return style

static func apply_primary_button(button: Button) -> void:
	if not button:
		return
	button.add_theme_stylebox_override("normal", create_primary_button_normal())
	button.add_theme_stylebox_override("hover", create_primary_button_hover())
	button.add_theme_stylebox_override("pressed", create_button_pressed())
	button.add_theme_stylebox_override("disabled", create_button_disabled())
	button.add_theme_stylebox_override("focus", create_button_focus())
	button.add_theme_color_override("font_color", WH_PARCHMENT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", WH_GOLD)
	button.add_theme_color_override("font_disabled_color", Color(0.5, 0.45, 0.35, 0.6))
	button.add_theme_font_size_override("font_size", 16)

static func apply_secondary_button(button: Button) -> void:
	if not button:
		return
	apply_to_button(button)
	button.add_theme_font_size_override("font_size", 13)

static func create_tab_button_inactive() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.08, 0.6)
	style.border_color = Color(WH_GOLD, 0.15)
	style.set_border_width_all(1)
	style.border_width_bottom = 2
	style.border_color = Color(WH_GOLD, 0.2)
	style.set_corner_radius_all(3)
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.set_content_margin_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style

static func create_tab_button_active() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.14, 0.1, 0.85)
	style.border_color = WH_GOLD
	style.set_border_width_all(1)
	style.border_width_bottom = 3
	style.set_corner_radius_all(3)
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.set_content_margin_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style

static func apply_tab_button(button: Button, is_active: bool = false) -> void:
	if not button:
		return
	if is_active:
		button.add_theme_stylebox_override("normal", create_tab_button_active())
		button.add_theme_stylebox_override("hover", create_tab_button_active())
		button.add_theme_color_override("font_color", WH_GOLD)
		button.add_theme_color_override("font_hover_color", WH_GOLD)
	else:
		button.add_theme_stylebox_override("normal", create_tab_button_inactive())
		var hover_style = create_tab_button_inactive()
		hover_style.bg_color = Color(0.16, 0.13, 0.1, 0.75)
		hover_style.border_color = Color(WH_GOLD, 0.5)
		button.add_theme_stylebox_override("hover", hover_style)
		button.add_theme_color_override("font_color", Color(WH_PARCHMENT, 0.7))
		button.add_theme_color_override("font_hover_color", WH_PARCHMENT)
	button.add_theme_stylebox_override("pressed", create_tab_button_active())
	button.add_theme_color_override("font_pressed_color", WH_GOLD)
	button.add_theme_font_size_override("font_size", 12)

static func create_player_panel_style(player: int) -> StyleBoxFlat:
	var style = create_panel_style()
	var border_color = FactionPalettes.get_player_border_color(player)
	style.border_color = border_color
	return style

static func get_player_label_color(player: int) -> Color:
	return FactionPalettes.get_player_border_color(player)

static func gold_hex() -> String:
	return WH_GOLD.to_html(false)

static func parchment_hex() -> String:
	return WH_PARCHMENT.to_html(false)

static func apply_section_header(label: Label) -> void:
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", WH_GOLD)
	if FactionPalettes:
		label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)

static func apply_subsection_header(label: Label) -> void:
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", WH_PARCHMENT)
	if FactionPalettes:
		label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_SEMIBOLD)

static func apply_body_text(label: Label) -> void:
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))

static func apply_caption_text(label: Label) -> void:
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))

static func bone_hex() -> String:
	return WH_BONE.to_html(false)

static func p1_hex() -> String:
	return P1_BORDER.to_html(false)

static func p2_hex() -> String:
	return P2_BORDER.to_html(false)
