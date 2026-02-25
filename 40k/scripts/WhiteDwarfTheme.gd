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
