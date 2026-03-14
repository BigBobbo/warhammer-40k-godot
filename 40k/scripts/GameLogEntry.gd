extends PanelContainer
class_name GameLogEntry

## A card-style panel representing a single event in the game log.
## Features: colored left border accent, icon, collapsible combat details, slide+fade animation.

# Entry type constants matching GameEventLog types
enum EntryCategory {
	PHASE,
	MOVEMENT,
	SHOOTING,
	MELEE,
	OVERWATCH,
	CHARGE,
	AI_THINKING,
	INFO,
	SCORING,
	COMBAT,  # Grouped combat sequence (header + details + result)
}

# Color scheme for left border accents by category
const BORDER_COLORS = {
	EntryCategory.PHASE: Color(0.833, 0.588, 0.376),      # Gold
	EntryCategory.MOVEMENT: Color(0.4, 0.6, 1.0),          # Blue
	EntryCategory.SHOOTING: Color(1.0, 0.4, 0.3),          # Red-orange
	EntryCategory.MELEE: Color(0.7, 0.3, 0.8),             # Purple
	EntryCategory.OVERWATCH: Color(1.0, 0.4, 0.0),         # Orange
	EntryCategory.CHARGE: Color(0.9, 0.8, 0.2),            # Yellow
	EntryCategory.AI_THINKING: Color(0.53, 0.6, 0.67),     # Muted blue-gray
	EntryCategory.INFO: Color(0.6, 0.6, 0.6),              # Gray
	EntryCategory.SCORING: Color(0.3, 0.8, 0.4),           # Green
	EntryCategory.COMBAT: Color(0.91, 0.77, 0.47),         # Gold (combat header)
}

# Icon characters for each category
const ICON_CHARS = {
	EntryCategory.PHASE: "P",
	EntryCategory.MOVEMENT: "M",
	EntryCategory.SHOOTING: "S",
	EntryCategory.MELEE: "F",
	EntryCategory.OVERWATCH: "O",
	EntryCategory.CHARGE: "C",
	EntryCategory.AI_THINKING: "AI",
	EntryCategory.INFO: "i",
	EntryCategory.SCORING: "VP",
	EntryCategory.COMBAT: "X",  # Will be set to S or F based on combat type
}

var category: int = EntryCategory.INFO
var is_combat_card: bool = false
var _details_visible: bool = false
var _details_container: VBoxContainer = null
var _details_label: RichTextLabel = null
var _toggle_button: Button = null
var _summary_label: Label = null
var _header_label: RichTextLabel = null
var _combat_details_text: String = ""
var _combat_result_text: String = ""

# ============================================================================
# Factory Methods
# ============================================================================

static func create_simple_entry(text: String, entry_type: String) -> GameLogEntry:
	"""Create a simple one-line log entry card."""
	var entry = GameLogEntry.new()
	entry.category = _categorize_entry_type(entry_type)
	entry._build_simple_card(text, entry_type)
	return entry

static func create_combat_card(header_text: String) -> GameLogEntry:
	"""Create a combat card with collapsible detail section."""
	var entry = GameLogEntry.new()
	entry.is_combat_card = true
	entry.category = EntryCategory.COMBAT
	entry._build_combat_card(header_text)
	return entry

# ============================================================================
# Combat Card Methods
# ============================================================================

func append_combat_detail(text: String) -> void:
	"""Append a detail line to the combat card's collapsible section."""
	if not is_combat_card:
		return
	if _combat_details_text != "":
		_combat_details_text += "\n"
	_combat_details_text += _style_combat_detail(text)
	if _details_label:
		_details_label.text = ""
		_details_label.append_text(_combat_details_text)

func set_combat_result(text: String) -> void:
	"""Set the combat result summary shown on the card."""
	if not is_combat_card:
		return
	_combat_result_text = text
	if _summary_label:
		# Extract the key result info for the summary line
		_summary_label.text = _extract_summary(text)
		_summary_label.visible = true
	if _toggle_button:
		_toggle_button.visible = true

func set_combat_icon_type(is_melee: bool) -> void:
	"""Set the combat icon to melee (F) or shooting (S)."""
	if is_melee:
		category = EntryCategory.MELEE
	else:
		category = EntryCategory.SHOOTING
	# Update the border color
	var style = get("theme_override_styles/panel") as StyleBoxFlat
	if style:
		style.border_color = BORDER_COLORS.get(category, Color.GRAY)

# ============================================================================
# Build Methods
# ============================================================================

func _build_simple_card(text: String, entry_type: String) -> void:
	# Configure the panel style
	var style = _create_card_style()
	add_theme_stylebox_override("panel", style)

	custom_minimum_size = Vector2(0, 28)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Main HBox: [Icon] [Text]
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	add_child(hbox)

	# Icon
	var icon = _create_icon()
	hbox.add_child(icon)

	# Text label
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", 11)
	label.add_theme_font_size_override("bold_font_size", 12)
	label.append_text(_format_entry_text(text, entry_type))
	hbox.add_child(label)

func _build_combat_card(header_text: String) -> void:
	# Configure the panel style
	var style = _create_card_style()
	add_theme_stylebox_override("panel", style)

	custom_minimum_size = Vector2(0, 28)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Main VBox for the card content
	var card_vbox = VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 2)
	add_child(card_vbox)

	# Top row: [Icon] [Header text]
	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 6)
	card_vbox.add_child(header_hbox)

	var icon = _create_icon()
	header_hbox.add_child(icon)

	_header_label = RichTextLabel.new()
	_header_label.bbcode_enabled = true
	_header_label.fit_content = true
	_header_label.scroll_active = false
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_label.add_theme_font_size_override("normal_font_size", 11)
	_header_label.add_theme_font_size_override("bold_font_size", 12)
	_header_label.append_text("[b][color=#E8C477]%s[/color][/b]" % header_text)
	header_hbox.add_child(_header_label)

	# Summary label (shown after combat resolves, always visible)
	_summary_label = Label.new()
	_summary_label.add_theme_font_size_override("font_size", 10)
	_summary_label.add_theme_color_override("font_color", Color(0.47, 0.8, 0.47))
	_summary_label.visible = false
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	card_vbox.add_child(_summary_label)

	# Toggle button for details
	_toggle_button = Button.new()
	_toggle_button.text = "  Show details"
	_toggle_button.add_theme_font_size_override("font_size", 9)
	_toggle_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_toggle_button.flat = true
	_toggle_button.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
	_toggle_button.add_theme_color_override("font_hover_color", Color(0.7, 0.8, 0.9))
	_toggle_button.visible = false
	_toggle_button.pressed.connect(_on_toggle_details)
	card_vbox.add_child(_toggle_button)

	# Collapsible details container
	_details_container = VBoxContainer.new()
	_details_container.visible = false
	card_vbox.add_child(_details_container)

	# Details RichTextLabel
	_details_label = RichTextLabel.new()
	_details_label.bbcode_enabled = true
	_details_label.fit_content = true
	_details_label.scroll_active = false
	_details_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_label.add_theme_font_size_override("normal_font_size", 10)
	_details_label.add_theme_font_size_override("bold_font_size", 11)
	_details_container.add_child(_details_label)

# ============================================================================
# Animation
# ============================================================================

func animate_in() -> void:
	"""Slide up and fade in animation for new entries."""
	modulate.a = 0.0
	var original_pos = position.y
	position.y += 15.0

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.25).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", original_pos, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

# ============================================================================
# Style Helpers
# ============================================================================

func _create_card_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.14, 0.9)
	# Left border accent
	style.border_width_left = 3
	style.border_width_right = 0
	style.border_width_top = 0
	style.border_width_bottom = 0
	style.border_color = BORDER_COLORS.get(category, Color.GRAY)
	# Rounded corners
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 4
	# Padding
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

func _create_icon() -> PanelContainer:
	"""Create a small colored circle with an icon character."""
	var icon_panel = PanelContainer.new()
	icon_panel.custom_minimum_size = Vector2(22, 22)

	var icon_style = StyleBoxFlat.new()
	var border_color = BORDER_COLORS.get(category, Color.GRAY)
	icon_style.bg_color = Color(border_color.r, border_color.g, border_color.b, 0.25)
	icon_style.corner_radius_top_left = 11
	icon_style.corner_radius_top_right = 11
	icon_style.corner_radius_bottom_left = 11
	icon_style.corner_radius_bottom_right = 11
	icon_style.content_margin_left = 0
	icon_style.content_margin_right = 0
	icon_style.content_margin_top = 0
	icon_style.content_margin_bottom = 0
	icon_panel.add_theme_stylebox_override("panel", icon_style)

	var icon_label = Label.new()
	var icon_char = ICON_CHARS.get(category, "?")
	icon_label.text = icon_char
	icon_label.add_theme_font_size_override("font_size", 9)
	icon_label.add_theme_color_override("font_color", border_color)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon_panel.add_child(icon_label)

	return icon_panel

func _format_entry_text(text: String, entry_type: String) -> String:
	"""Format entry text with BBCode based on entry type."""
	match entry_type:
		"phase_header":
			return "[b][color=#D49761]%s[/color][/b]" % text
		"p1_action":
			return "[color=#6699CC]%s[/color]" % text
		"p2_action":
			return "[color=#CC6666]%s[/color]" % text
		"ai_thinking":
			return "[i][color=#8899AA]%s[/color][/i]" % text
		"overwatch":
			return "[b][color=#FF6600]%s[/color][/b]" % text
		"combat_result":
			if "destroyed" in text and "No models" not in text:
				return "[b][color=#FF6B6B]%s[/color][/b]" % text
			else:
				return "[b][color=#77CC77]%s[/color][/b]" % text
		_:
			return "[color=#AAAAAA]%s[/color]" % text

static func _categorize_entry_type(entry_type: String) -> int:
	"""Map entry_type string to EntryCategory."""
	match entry_type:
		"phase_header":
			return EntryCategory.PHASE
		"p1_action", "p2_action":
			return EntryCategory.MOVEMENT  # Default; will be refined by text content
		"ai_thinking":
			return EntryCategory.AI_THINKING
		"overwatch":
			return EntryCategory.OVERWATCH
		"combat_header":
			return EntryCategory.COMBAT
		"combat_detail":
			return EntryCategory.COMBAT
		"combat_result":
			return EntryCategory.COMBAT
		"info":
			return EntryCategory.INFO
		_:
			return EntryCategory.INFO

static func refine_category_from_text(text: String, current_category: int) -> int:
	"""Refine the category based on text content for player actions."""
	if current_category != EntryCategory.MOVEMENT:
		return current_category

	var lower_text = text.to_lower()
	if "shot" in lower_text or "shoots" in lower_text or "shooting" in lower_text:
		return EntryCategory.SHOOTING
	elif "fought" in lower_text or "fights" in lower_text or "fight" in lower_text:
		return EntryCategory.MELEE
	elif "charged" in lower_text or "charge" in lower_text or "pile" in lower_text or "consolidat" in lower_text:
		return EntryCategory.CHARGE
	elif "score" in lower_text or "vp" in lower_text or "point" in lower_text:
		return EntryCategory.SCORING
	elif "overwatch" in lower_text:
		return EntryCategory.OVERWATCH
	return current_category

func _on_toggle_details() -> void:
	_details_visible = !_details_visible
	if _details_container:
		_details_container.visible = _details_visible
	if _toggle_button:
		_toggle_button.text = "  Hide details" if _details_visible else "  Show details"

func _extract_summary(result_text: String) -> String:
	"""Extract a compact summary from the result text."""
	# Remove leading whitespace and "Result: " prefix
	var summary = result_text.strip_edges()
	if summary.begins_with("Result: "):
		summary = summary.substr(8)
	return summary

func _style_combat_detail(text: String) -> String:
	"""Apply inline styling to combat detail text — highlight dice rolls, thresholds, and keywords."""
	var styled = text

	# Highlight dice roll arrays [1, 3, 5, 6] in cyan
	var dice_regex = RegEx.new()
	dice_regex.compile("\\[([0-9, ]+)\\]")
	var dice_results = dice_regex.search_all(styled)
	# Process in reverse order to preserve positions
	for i in range(dice_results.size() - 1, -1, -1):
		var m = dice_results[i]
		var inner = m.get_string(1)
		# Color individual dice: 6s in gold, 1s in red, others in cyan
		var dice_parts = inner.split(", ")
		var colored_dice = []
		for d in dice_parts:
			var dval = d.strip_edges()
			if dval == "6":
				colored_dice.append("[color=#FFD700]6[/color]")
			elif dval == "1":
				colored_dice.append("[color=#FF4444]1[/color]")
			else:
				colored_dice.append("[color=#66CCEE]%s[/color]" % dval)
		var replacement = "[color=#888888][[/color]%s[color=#888888]][/color]" % ", ".join(colored_dice)
		styled = styled.substr(0, m.get_start()) + replacement + styled.substr(m.get_end())

	# Highlight keywords
	styled = styled.replace("DEVASTATING WOUNDS", "[color=#FF4444]DEVASTATING WOUNDS[/color]")
	styled = styled.replace("DEVASTATING", "[color=#FF4444]DEVASTATING[/color]")
	styled = styled.replace("Lethal Hits", "[color=#FF8844]Lethal Hits[/color]")
	styled = styled.replace("Sustained Hits", "[color=#EEDD44]Sustained Hits[/color]")
	styled = styled.replace("Feel No Pain", "[color=#44CC88]Feel No Pain[/color]")
	styled = styled.replace("Invulnerable Save", "[color=#BB88FF]Invulnerable Save[/color]")
	styled = styled.replace("Re-rolls:", "[color=#88BBFF]Re-rolls:[/color]")
	styled = styled.replace("Torrent", "[color=#FF8844]Torrent[/color]")

	return "[color=#B0B8C0]%s[/color]" % styled
