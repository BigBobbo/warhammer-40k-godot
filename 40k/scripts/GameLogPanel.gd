extends PanelContainer
class_name GameLogPanel

## GameLogPanel — Card-based game event log UI
## Each log entry is rendered as its own styled PanelContainer card
## inside a scrollable VBoxContainer.

# --- Configuration ---
const PANEL_WIDTH := 340.0
const CARD_GAP := 4
const CARD_CORNER_RADIUS := 4
const CARD_PADDING := 6
const MAX_CARDS := 200  # Trim oldest cards when exceeded

# --- Color Palette ---
const COLOR_BG := Color(0.08, 0.08, 0.12, 0.85)
const COLOR_GOLD := Color(0.833, 0.588, 0.376)
const COLOR_GOLD_BRIGHT := Color(0.91, 0.77, 0.47)
const COLOR_P1_BLUE := Color(0.4, 0.6, 0.8)
const COLOR_P2_RED := Color(0.8, 0.4, 0.4)
const COLOR_AI_THINKING := Color(0.53, 0.6, 0.67)
const COLOR_INFO := Color(0.67, 0.67, 0.67)
const COLOR_OVERWATCH := Color(1.0, 0.4, 0.0)
const COLOR_COMBAT_BG := Color(0.1, 0.1, 0.15, 0.95)
const COLOR_COMBAT_DETAIL_BG := Color(0.09, 0.09, 0.13, 0.9)
const COLOR_COMBAT_RESULT_GREEN := Color(0.47, 0.8, 0.47)
const COLOR_COMBAT_RESULT_RED := Color(1.0, 0.42, 0.42)
const COLOR_PHASE_BG := Color(0.14, 0.12, 0.08, 0.95)
const COLOR_CARD_BG := Color(0.1, 0.1, 0.14, 0.9)
const COLOR_CARD_BORDER := Color(0.2, 0.2, 0.25, 0.6)

# Card accent colors per type (left border)
const ACCENT_COLORS := {
	"phase_header": Color(0.833, 0.588, 0.376),    # Gold
	"p1_action": Color(0.4, 0.6, 0.8),              # Blue
	"p2_action": Color(0.8, 0.4, 0.4),              # Red
	"ai_thinking": Color(0.53, 0.6, 0.67, 0.5),     # Muted grey-blue
	"info": Color(0.5, 0.5, 0.55),                   # Grey
	"overwatch": Color(1.0, 0.4, 0.0),               # Orange
	"combat_header": Color(0.91, 0.77, 0.47),        # Bright gold
	"combat_detail": Color(0.35, 0.35, 0.4),         # Dark grey
	"combat_result": Color(0.47, 0.8, 0.47),         # Green (overridden for casualties)
}

# --- State ---
var _scroll: ScrollContainer
var _card_container: VBoxContainer
var _toggle_button: Button
var _collapse_button: Button
var _ai_filter_button: Button
var _show_ai_thinking: bool = true
var _ai_cards: Array[PanelContainer] = []
var _card_count: int = 0
var _is_visible: bool = true

# Regex for dice roll styling (compiled once)
var _dice_regex: RegEx

func _ready() -> void:
	_dice_regex = RegEx.new()
	_dice_regex.compile("\\[([0-9, ]+)\\]")

func setup(parent: Node, hud_bottom: HBoxContainer = null, offset_top: float = 105.0, offset_bottom: float = 0.0) -> void:
	"""Initialize the panel, add to parent, and wire up signals."""
	name = "GameLogPanel"
	parent.add_child(self)

	# Anchor to left side, full height
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_right = PANEL_WIDTH
	offset_top = offset_top
	offset_bottom = offset_bottom

	# Panel background style
	var style = StyleBoxFlat.new()
	style.bg_color = COLOR_BG
	style.border_width_right = 2
	style.border_color = Color(COLOR_GOLD.r, COLOR_GOLD.g, COLOR_GOLD.b, 0.6)
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	add_theme_stylebox_override("panel", style)

	# Main layout
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	add_child(vbox)

	# --- Header row ---
	var header = HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 28)
	vbox.add_child(header)

	var title = Label.new()
	title.text = "Game Log"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	# AI filter toggle
	_ai_filter_button = Button.new()
	_ai_filter_button.text = "AI"
	_ai_filter_button.tooltip_text = "Toggle AI thinking entries"
	_ai_filter_button.custom_minimum_size = Vector2(36, 24)
	_ai_filter_button.add_theme_font_size_override("font_size", 10)
	_ai_filter_button.pressed.connect(_on_ai_filter_pressed)
	header.add_child(_ai_filter_button)
	_update_ai_filter_button()

	# Collapse button
	_collapse_button = Button.new()
	_collapse_button.text = "X"
	_collapse_button.custom_minimum_size = Vector2(28, 24)
	_collapse_button.add_theme_font_size_override("font_size", 12)
	_collapse_button.pressed.connect(_on_collapse_pressed)
	header.add_child(_collapse_button)

	# Separator
	var sep = HSeparator.new()
	vbox.add_child(sep)

	# --- Scroll area with card container ---
	_scroll = ScrollContainer.new()
	_scroll.name = "LogScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)

	_card_container = VBoxContainer.new()
	_card_container.name = "CardContainer"
	_card_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_container.add_theme_constant_override("separation", CARD_GAP)
	_scroll.add_child(_card_container)

	# --- Toggle button in HUD ---
	if hud_bottom:
		_toggle_button = Button.new()
		_toggle_button.name = "GameLogToggle"
		_toggle_button.text = "Hide Log"
		_toggle_button.pressed.connect(_on_toggle_pressed)
		hud_bottom.add_child(_toggle_button)
		hud_bottom.move_child(_toggle_button, 1)

	# Connect to GameEventLog
	if GameEventLog:
		GameEventLog.entry_added.connect(_on_entry_added)
		print("GameLogPanel: Connected to GameEventLog.entry_added")
		# Populate existing entries
		for entry in GameEventLog.get_all_entries():
			_create_card(entry.text, entry.type)

	print("GameLogPanel: Setup complete")

func get_toggle_button() -> Button:
	return _toggle_button

# ==========================================================================
# Card creation
# ==========================================================================

func _on_entry_added(text: String, entry_type: String) -> void:
	_create_card(text, entry_type)
	# Auto-scroll to bottom
	if _scroll:
		await get_tree().process_frame
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

func _create_card(text: String, entry_type: String) -> void:
	var card: PanelContainer

	match entry_type:
		"phase_header":
			card = _make_phase_card(text)
		"combat_header":
			card = _make_combat_header_card(text)
		"combat_detail":
			card = _make_combat_detail_card(text)
		"combat_result":
			card = _make_combat_result_card(text)
		"overwatch":
			card = _make_overwatch_card(text)
		"ai_thinking":
			card = _make_ai_thinking_card(text)
		"p1_action":
			card = _make_action_card(text, 1)
		"p2_action":
			card = _make_action_card(text, 2)
		"info":
			card = _make_info_card(text)
		_:
			card = _make_info_card(text)

	_card_container.add_child(card)
	_card_count += 1

	# Track AI cards for filtering
	if entry_type == "ai_thinking":
		_ai_cards.append(card)
		card.visible = _show_ai_thinking

	# Trim old cards if over limit
	if _card_count > MAX_CARDS:
		_trim_old_cards(50)

func _trim_old_cards(count: int) -> void:
	"""Remove the oldest N cards."""
	for i in range(count):
		if _card_container.get_child_count() == 0:
			break
		var old_card = _card_container.get_child(0)
		if old_card in _ai_cards:
			_ai_cards.erase(old_card)
		_card_container.remove_child(old_card)
		old_card.queue_free()
		_card_count -= 1

# ==========================================================================
# Card builders
# ==========================================================================

func _make_card_style(bg_color: Color, accent_color: Color, accent_width: int = 3) -> StyleBoxFlat:
	"""Create a StyleBoxFlat for a card with left accent border."""
	var s = StyleBoxFlat.new()
	s.bg_color = bg_color
	s.corner_radius_top_left = CARD_CORNER_RADIUS
	s.corner_radius_top_right = CARD_CORNER_RADIUS
	s.corner_radius_bottom_left = CARD_CORNER_RADIUS
	s.corner_radius_bottom_right = CARD_CORNER_RADIUS
	s.border_width_left = accent_width
	s.border_color = accent_color
	s.content_margin_left = CARD_PADDING + accent_width
	s.content_margin_right = CARD_PADDING
	s.content_margin_top = CARD_PADDING
	s.content_margin_bottom = CARD_PADDING
	return s

func _make_phase_card(text: String) -> PanelContainer:
	"""Full-width banner card for phase transitions."""
	var card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = COLOR_PHASE_BG
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.border_width_left = 4
	style.border_width_right = 4
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = COLOR_GOLD
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", style)

	# Parse phase info from "--- Phase Name (Round X, PY) ---"
	var clean_text = text.strip_edges().trim_prefix("---").trim_suffix("---").strip_edges()

	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", 13)
	label.add_theme_font_size_override("bold_font_size", 13)
	label.append_text("[center][b][color=#D49761]%s[/color][/b][/center]" % clean_text)
	card.add_child(label)

	return card

func _make_combat_header_card(text: String) -> PanelContainer:
	"""Card for combat sequence header (e.g. 'P1: Intercessors shoots at Boyz')."""
	var card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style(
		COLOR_COMBAT_BG, ACCENT_COLORS["combat_header"], 4
	))

	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", 11)
	label.add_theme_font_size_override("bold_font_size", 12)
	label.append_text("[b][color=#E8C477]%s[/color][/b]" % text)
	card.add_child(label)

	return card

func _make_combat_detail_card(text: String) -> PanelContainer:
	"""Card for combat detail step (dice rolls, modifiers, etc.)."""
	var card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style(
		COLOR_COMBAT_DETAIL_BG, ACCENT_COLORS["combat_detail"], 2
	))

	var styled = _style_combat_detail(text.strip_edges())

	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", 10)
	label.add_theme_font_size_override("bold_font_size", 11)
	label.append_text("[color=#B0B8C0]%s[/color]" % styled)
	card.add_child(label)

	return card

func _make_combat_result_card(text: String) -> PanelContainer:
	"""Card for combat result summary."""
	var has_casualties = "destroyed" in text and "No models" not in text and "0 model" not in text
	var accent = COLOR_COMBAT_RESULT_RED if has_casualties else COLOR_COMBAT_RESULT_GREEN
	var text_color = "#FF6B6B" if has_casualties else "#77CC77"

	var card = PanelContainer.new()
	var style = _make_card_style(COLOR_COMBAT_BG, accent, 4)
	# Add a subtle top border for emphasis
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_width_right = 1
	card.add_theme_stylebox_override("panel", style)

	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", 11)
	label.add_theme_font_size_override("bold_font_size", 12)
	label.append_text("[b][color=%s]%s[/color][/b]" % [text_color, text.strip_edges()])
	card.add_child(label)

	return card

func _make_overwatch_card(text: String) -> PanelContainer:
	"""Card for overwatch events."""
	var card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style(
		Color(0.15, 0.1, 0.05, 0.95), ACCENT_COLORS["overwatch"], 4
	))

	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", 11)
	label.add_theme_font_size_override("bold_font_size", 12)
	label.append_text("[b][color=#FF6600]%s[/color][/b]" % text)
	card.add_child(label)

	return card

func _make_ai_thinking_card(text: String) -> PanelContainer:
	"""Card for AI thinking/reasoning entries."""
	var card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style(
		Color(0.08, 0.08, 0.11, 0.7), ACCENT_COLORS["ai_thinking"], 2
	))

	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", 10)
	label.append_text("[i][color=#8899AA]%s[/color][/i]" % text)
	card.add_child(label)

	return card

func _make_action_card(text: String, player: int) -> PanelContainer:
	"""Card for player actions (movement, deployment, etc.)."""
	var accent = ACCENT_COLORS["p1_action"] if player == 1 else ACCENT_COLORS["p2_action"]
	var text_color = "#6699CC" if player == 1 else "#CC6666"

	var card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style(COLOR_CARD_BG, accent, 3))

	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", 11)
	label.append_text("[color=%s]%s[/color]" % [text_color, text])
	card.add_child(label)

	return card

func _make_info_card(text: String) -> PanelContainer:
	"""Card for general info entries (VP, CP, mission status)."""
	var card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style(
		Color(0.09, 0.09, 0.12, 0.8), ACCENT_COLORS["info"], 2
	))

	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", 10)
	label.append_text("[color=#AAAAAA]%s[/color]" % text)
	card.add_child(label)

	return card

# ==========================================================================
# Combat detail styling (dice rolls, keywords)
# ==========================================================================

func _style_combat_detail(text: String) -> String:
	"""Apply inline styling to combat detail text — highlight dice rolls, thresholds, keywords."""
	var styled = text

	# Highlight dice roll arrays [1, 3, 5, 6]
	var dice_results = _dice_regex.search_all(styled)
	# Process in reverse to preserve positions
	for i in range(dice_results.size() - 1, -1, -1):
		var m = dice_results[i]
		var inner = m.get_string(1)
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

	return styled

# ==========================================================================
# Filter & visibility
# ==========================================================================

func _on_ai_filter_pressed() -> void:
	_show_ai_thinking = !_show_ai_thinking
	for card in _ai_cards:
		if is_instance_valid(card):
			card.visible = _show_ai_thinking
	_update_ai_filter_button()

func _update_ai_filter_button() -> void:
	if _ai_filter_button:
		if _show_ai_thinking:
			_ai_filter_button.modulate = Color(1, 1, 1, 1)
			_ai_filter_button.tooltip_text = "AI thinking visible — click to hide"
		else:
			_ai_filter_button.modulate = Color(1, 1, 1, 0.4)
			_ai_filter_button.tooltip_text = "AI thinking hidden — click to show"

func _on_collapse_pressed() -> void:
	_is_visible = false
	visible = false
	if _toggle_button:
		_toggle_button.text = "Show Log"

func _on_toggle_pressed() -> void:
	_is_visible = !_is_visible
	visible = _is_visible
	if _toggle_button:
		_toggle_button.text = "Hide Log" if _is_visible else "Show Log"

func set_panel_visible(v: bool) -> void:
	_is_visible = v
	visible = v
	if _toggle_button:
		_toggle_button.text = "Hide Log" if v else "Show Log"

func is_panel_visible() -> bool:
	return _is_visible
