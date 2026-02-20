extends PanelContainer
class_name FightPhaseStateBanner

# T5-V10: Fight Phase State Banner
# Persistent banner shown during the Fight Phase displaying:
# - Current subphase (FIGHTS FIRST / REMAINING COMBATS / FIGHTS LAST)
# - Whose turn to select a fighter
# - Number of units remaining in the current subphase
# Animates on subphase transitions with distinct color schemes.

const BANNER_HEIGHT := 52.0
const TRANSITION_OVERLAY_DURATION := 1.8  # seconds for transition overlay
const TRANSITION_SLIDE_DURATION := 0.3

# Subphase color schemes
const SUBPHASE_COLORS := {
	"FIGHTS_FIRST": {
		"bg": Color(0.35, 0.12, 0.08, 0.95),   # Deep crimson
		"accent": Color(0.95, 0.35, 0.2),        # Bright orange-red
		"text": Color(0.95, 0.9, 0.8),           # Warm white
		"icon": "\u2694"                          # Crossed swords
	},
	"REMAINING_COMBATS": {
		"bg": Color(0.1, 0.15, 0.3, 0.95),      # Dark navy
		"accent": Color(0.4, 0.6, 0.9),          # Steel blue
		"text": Color(0.9, 0.92, 0.98),          # Cool white
		"icon": "\u2620"                          # Skull
	},
	"FIGHTS_LAST": {
		"bg": Color(0.2, 0.12, 0.28, 0.95),     # Dark purple
		"accent": Color(0.65, 0.4, 0.85),        # Light purple
		"text": Color(0.92, 0.88, 0.95),         # Lavender white
		"icon": "\u231B"                          # Hourglass
	},
	"COMPLETE": {
		"bg": Color(0.1, 0.18, 0.1, 0.95),      # Dark green
		"accent": Color(0.4, 0.75, 0.4),         # Muted green
		"text": Color(0.88, 0.95, 0.88),         # Light green white
		"icon": "\u2714"                          # Checkmark
	}
}

# Subphase display names
const SUBPHASE_DISPLAY := {
	"FIGHTS_FIRST": "FIGHTS FIRST",
	"REMAINING_COMBATS": "REMAINING COMBATS",
	"FIGHTS_LAST": "FIGHTS LAST",
	"COMPLETE": "COMPLETE"
}

# Internal UI elements
var _subphase_label: Label
var _player_label: Label
var _units_label: Label
var _accent_line_top: ColorRect
var _accent_line_bottom: ColorRect
var _bg_style: StyleBoxFlat

# Transition overlay elements
var _transition_overlay: ColorRect
var _transition_label: Label
var _transition_tween: Tween = null

# State
var _current_subphase: String = ""
var _is_visible: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	# Set size
	custom_minimum_size = Vector2(0, BANNER_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Background style
	_bg_style = StyleBoxFlat.new()
	_bg_style.bg_color = SUBPHASE_COLORS["FIGHTS_FIRST"]["bg"]
	_bg_style.set_border_width_all(0)
	_bg_style.set_content_margin_all(0)
	add_theme_stylebox_override("panel", _bg_style)

	# Top accent line
	_accent_line_top = ColorRect.new()
	_accent_line_top.color = WhiteDwarfTheme.WH_GOLD
	_accent_line_top.custom_minimum_size = Vector2(0, 2)
	_accent_line_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_accent_line_top.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Bottom accent line
	_accent_line_bottom = ColorRect.new()
	_accent_line_bottom.color = WhiteDwarfTheme.WH_GOLD
	_accent_line_bottom.custom_minimum_size = Vector2(0, 2)
	_accent_line_bottom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_accent_line_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Main layout: VBox with accent lines sandwiching the content
	var outer_vbox = VBoxContainer.new()
	outer_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(outer_vbox)

	outer_vbox.add_child(_accent_line_top)

	# Content row: subphase label (left), player turn (center), units remaining (right)
	var content_hbox = HBoxContainer.new()
	content_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 12)
	outer_vbox.add_child(content_hbox)

	# Left spacer
	var left_spacer = Control.new()
	left_spacer.custom_minimum_size = Vector2(8, 0)
	left_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_hbox.add_child(left_spacer)

	# Subphase label (left-aligned, prominent)
	_subphase_label = Label.new()
	_subphase_label.text = "\u2694  FIGHTS FIRST"
	_subphase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_subphase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subphase_label.add_theme_font_size_override("font_size", 20)
	_subphase_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_PARCHMENT)
	_subphase_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_subphase_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_subphase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_hbox.add_child(_subphase_label)

	# Separator
	var sep = VSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sep.add_theme_constant_override("separation", 2)
	content_hbox.add_child(sep)

	# Player turn label (center)
	_player_label = Label.new()
	_player_label.text = "Player 1 Selects"
	_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_player_label.add_theme_font_size_override("font_size", 15)
	_player_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	_player_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_player_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_hbox.add_child(_player_label)

	# Separator
	var sep2 = VSeparator.new()
	sep2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sep2.add_theme_constant_override("separation", 2)
	content_hbox.add_child(sep2)

	# Units remaining label (right)
	_units_label = Label.new()
	_units_label.text = "0 units remaining"
	_units_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_units_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_units_label.add_theme_font_size_override("font_size", 14)
	_units_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_PARCHMENT)
	_units_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_units_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_units_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_hbox.add_child(_units_label)

	# Right spacer
	var right_spacer = Control.new()
	right_spacer.custom_minimum_size = Vector2(8, 0)
	right_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_hbox.add_child(right_spacer)

	outer_vbox.add_child(_accent_line_bottom)

	# Transition overlay (full-width, used for subphase change animation)
	_transition_overlay = ColorRect.new()
	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_overlay.visible = false
	_transition_overlay.color = Color(0, 0, 0, 0.85)
	_transition_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_transition_overlay)

	_transition_label = Label.new()
	_transition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_transition_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_transition_label.add_theme_font_size_override("font_size", 22)
	_transition_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	_transition_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_transition_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_overlay.add_child(_transition_label)

	print("FightPhaseStateBanner: Initialized")


func update_state(data: Dictionary) -> void:
	"""Update the banner with current fight phase state data.
	data should contain: current_subphase, selecting_player, eligible_units,
	fights_first_units, remaining_units, fights_last_units, units_that_fought"""
	var subphase = data.get("current_subphase", "FIGHTS_FIRST")
	var selecting_player = data.get("selecting_player", 1)
	var eligible_units = data.get("eligible_units", {})
	var units_fought = data.get("units_that_fought", [])

	# Count total remaining units in current subphase (both players)
	var total_remaining := 0
	var source_key := ""
	match subphase:
		"FIGHTS_FIRST":
			source_key = "fights_first_units"
		"REMAINING_COMBATS":
			source_key = "remaining_units"
		"FIGHTS_LAST":
			source_key = "fights_last_units"

	if source_key != "":
		var source = data.get(source_key, {})
		for player_key in source:
			for unit_id in source[player_key]:
				if unit_id not in units_fought:
					total_remaining += 1

	# Update subphase display
	var colors = SUBPHASE_COLORS.get(subphase, SUBPHASE_COLORS["FIGHTS_FIRST"])
	var display_name = SUBPHASE_DISPLAY.get(subphase, subphase)
	var icon = colors.get("icon", "\u2694")

	_subphase_label.text = "%s  %s" % [icon, display_name]
	_subphase_label.add_theme_color_override("font_color", colors["text"])

	# Update player turn
	_player_label.text = "Player %d Selects" % selecting_player
	# Color code by player
	if selecting_player == 1:
		_player_label.add_theme_color_override("font_color", Color(0.5, 0.65, 1.0))  # Blue tint
	else:
		_player_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))  # Red tint

	# Update units remaining
	_units_label.text = "%d unit%s remaining" % [total_remaining, "" if total_remaining == 1 else "s"]
	_units_label.add_theme_color_override("font_color", colors["text"])

	# Update background and accent colors
	_bg_style.bg_color = colors["bg"]
	_accent_line_top.color = colors["accent"]
	_accent_line_bottom.color = colors["accent"]

	_current_subphase = subphase

	# Show if not already visible
	if not visible:
		_show_banner()

	print("FightPhaseStateBanner: Updated — %s | Player %d | %d remaining" % [display_name, selecting_player, total_remaining])


func show_subphase_transition(from_subphase: String, to_subphase: String) -> void:
	"""Animate a brief transition overlay when subphase changes."""
	var from_display = SUBPHASE_DISPLAY.get(from_subphase, from_subphase)
	var to_display = SUBPHASE_DISPLAY.get(to_subphase, to_subphase)
	var to_colors = SUBPHASE_COLORS.get(to_subphase, SUBPHASE_COLORS["REMAINING_COMBATS"])

	_transition_label.text = "%s COMPLETE \u2192 %s" % [from_display, to_display]
	_transition_overlay.color = Color(to_colors["bg"].r, to_colors["bg"].g, to_colors["bg"].b, 0.95)
	_transition_overlay.visible = true
	_transition_overlay.modulate = Color(1, 1, 1, 0)

	# Kill any existing transition tween
	if _transition_tween and _transition_tween.is_valid():
		_transition_tween.kill()

	_transition_tween = create_tween()

	# Fade in overlay
	_transition_tween.tween_property(_transition_overlay, "modulate", Color(1, 1, 1, 1), 0.2).set_ease(Tween.EASE_OUT)

	# Hold
	_transition_tween.tween_interval(TRANSITION_OVERLAY_DURATION - 0.4)

	# Fade out overlay
	_transition_tween.tween_property(_transition_overlay, "modulate", Color(1, 1, 1, 0), 0.2).set_ease(Tween.EASE_IN)

	# Hide overlay when done
	_transition_tween.tween_callback(func(): _transition_overlay.visible = false)

	print("FightPhaseStateBanner: Transition %s -> %s" % [from_subphase, to_subphase])


func show_complete() -> void:
	"""Show the banner in COMPLETE state (all units have fought)."""
	var colors = SUBPHASE_COLORS["COMPLETE"]
	_subphase_label.text = "%s  ALL COMBATS RESOLVED" % colors["icon"]
	_subphase_label.add_theme_color_override("font_color", colors["text"])
	_player_label.text = "End Fight Phase"
	_player_label.add_theme_color_override("font_color", colors["accent"])
	_units_label.text = "0 units remaining"
	_units_label.add_theme_color_override("font_color", colors["text"])
	_bg_style.bg_color = colors["bg"]
	_accent_line_top.color = colors["accent"]
	_accent_line_bottom.color = colors["accent"]
	_current_subphase = "COMPLETE"

	if not visible:
		_show_banner()

	print("FightPhaseStateBanner: All combats resolved")


func _show_banner() -> void:
	"""Slide the banner in from the top."""
	visible = true
	modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), TRANSITION_SLIDE_DURATION).set_ease(Tween.EASE_OUT)
	_is_visible = true


func hide_banner() -> void:
	"""Fade out and hide the banner."""
	if not visible:
		return

	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), TRANSITION_SLIDE_DURATION).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		visible = false
		_is_visible = false
	)

	# Kill transition overlay too
	if _transition_tween and _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_overlay.visible = false

	print("FightPhaseStateBanner: Banner hidden")
