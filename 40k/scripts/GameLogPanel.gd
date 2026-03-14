extends PanelContainer
class_name GameLogPanel

## GameLogPanel — Self-contained card-based game event log UI.
## Combines: xBfRG's self-contained architecture + f4dOz's collapsible combat cards,
## animations, icon badges, and category refinement + xBfRG's AI filter toggle.

# --- Configuration ---
const PANEL_WIDTH := 340.0
const CARD_GAP := 3
const CARD_CORNER_RADIUS := 4
const CARD_PADDING := 6
const MAX_CARDS := 200

# --- Entry Categories ---
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
	COMBAT,
}

# --- Color Palette ---
const COLOR_BG := Color(0.08, 0.08, 0.12, 0.85)
const COLOR_GOLD := Color(0.833, 0.588, 0.376)

# Card accent colors per category (left border)
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
	EntryCategory.COMBAT: "X",
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
var _current_combat_card: PanelContainer = null
var _current_combat_details_text: String = ""
var _current_combat_details_container: VBoxContainer = null
var _current_combat_details_label: RichTextLabel = null
var _current_combat_toggle_button: Button = null
var _current_combat_summary_label: Label = null
var _current_combat_details_visible: bool = false

# Regex for dice roll styling (compiled once)
var _dice_regex: RegEx

func _ready() -> void:
	_dice_regex = RegEx.new()
	_dice_regex.compile("\\[([0-9, ]+)\\]")

func setup(parent: Node, hud_bottom: HBoxContainer = null, offset_top: float = 105.0, offset_bottom: float = 0.0) -> void:
	name = "GameLogPanel"
	parent.add_child(self)

	# Anchor to left side, full height
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_right = PANEL_WIDTH
	self.offset_top = offset_top
	self.offset_bottom = offset_bottom

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
		# Populate existing entries (no animation for backfill)
		for entry in GameEventLog.get_all_entries():
			_create_card(entry.text, entry.type, false)

	print("GameLogPanel: Setup complete")

func get_toggle_button() -> Button:
	return _toggle_button

# ==========================================================================
# Card creation — entry point
# ==========================================================================

func _on_entry_added(text: String, entry_type: String) -> void:
	_create_card(text, entry_type, true)
	# Auto-scroll to bottom
	if _scroll:
		await get_tree().process_frame
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

func _create_card(text: String, entry_type: String, animate: bool = true) -> void:
	match entry_type:
		"combat_header":
			_start_combat_card(text, animate)
		"combat_detail":
			_append_combat_detail(text, animate)
		"combat_result":
			_finalize_combat_card(text, animate)
		_:
			_create_simple_card(text, entry_type, animate)

	# Trim old cards if over limit
	if _card_count > MAX_CARDS:
		_trim_old_cards(50)

# ==========================================================================
# Combat card — collapsible header + details + result (from f4dOz)
# ==========================================================================

func _start_combat_card(header_text: String, animate: bool) -> void:
	# Determine if melee or shooting from header text
	var is_melee = "fights" in header_text.to_lower() or "fight" in header_text.to_lower()
	var category = EntryCategory.MELEE if is_melee else EntryCategory.SHOOTING

	var card = PanelContainer.new()
	var style = _make_card_style(
		Color(0.1, 0.1, 0.15, 0.95),
		BORDER_COLORS[category],
		4
	)
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = Vector2(0, 28)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var card_vbox = VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 2)
	card.add_child(card_vbox)

	# Top row: [Icon] [Header text]
	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 6)
	card_vbox.add_child(header_hbox)

	var icon = _create_icon(category)
	header_hbox.add_child(icon)

	var header_label = RichTextLabel.new()
	header_label.bbcode_enabled = true
	header_label.fit_content = true
	header_label.scroll_active = false
	header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_label.add_theme_font_size_override("normal_font_size", 11)
	header_label.add_theme_font_size_override("bold_font_size", 12)
	header_label.append_text("[b][color=#E8C477]%s[/color][/b]" % header_text)
	header_hbox.add_child(header_label)

	# Summary label (shown after combat resolves)
	_current_combat_summary_label = Label.new()
	_current_combat_summary_label.add_theme_font_size_override("font_size", 10)
	_current_combat_summary_label.add_theme_color_override("font_color", Color(0.47, 0.8, 0.47))
	_current_combat_summary_label.visible = false
	_current_combat_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	card_vbox.add_child(_current_combat_summary_label)

	# Toggle button for details
	_current_combat_toggle_button = Button.new()
	_current_combat_toggle_button.text = "  Show details"
	_current_combat_toggle_button.add_theme_font_size_override("font_size", 9)
	_current_combat_toggle_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_current_combat_toggle_button.flat = true
	_current_combat_toggle_button.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
	_current_combat_toggle_button.add_theme_color_override("font_hover_color", Color(0.7, 0.8, 0.9))
	_current_combat_toggle_button.visible = false
	# Store references for the toggle closure
	var toggle_btn = _current_combat_toggle_button
	card_vbox.add_child(toggle_btn)

	# Collapsible details container
	_current_combat_details_container = VBoxContainer.new()
	_current_combat_details_container.visible = false
	card_vbox.add_child(_current_combat_details_container)

	# Details RichTextLabel
	_current_combat_details_label = RichTextLabel.new()
	_current_combat_details_label.bbcode_enabled = true
	_current_combat_details_label.fit_content = true
	_current_combat_details_label.scroll_active = false
	_current_combat_details_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_current_combat_details_label.add_theme_font_size_override("normal_font_size", 10)
	_current_combat_details_label.add_theme_font_size_override("bold_font_size", 11)
	_current_combat_details_container.add_child(_current_combat_details_label)

	# Wire up toggle — capture references for the closure
	var details_cont = _current_combat_details_container
	toggle_btn.pressed.connect(func():
		details_cont.visible = !details_cont.visible
		toggle_btn.text = "  Hide details" if details_cont.visible else "  Show details"
	)

	_current_combat_card = card
	_current_combat_details_text = ""
	_current_combat_details_visible = false

	_card_container.add_child(card)
	_card_count += 1

	if animate:
		_animate_card_in(card)

func _append_combat_detail(text: String, animate: bool) -> void:
	if _current_combat_card and is_instance_valid(_current_combat_card) and _current_combat_details_label:
		# Append to current combat card's collapsible section
		if _current_combat_details_text != "":
			_current_combat_details_text += "\n"
		_current_combat_details_text += _style_combat_detail(text.strip_edges())
		_current_combat_details_label.text = ""
		_current_combat_details_label.append_text("[color=#B0B8C0]%s[/color]" % _current_combat_details_text)
	else:
		# Orphaned detail — create standalone card
		var card = _make_simple_entry_card(text, "combat_detail", EntryCategory.COMBAT)
		_card_container.add_child(card)
		_card_count += 1
		if animate:
			_animate_card_in(card)

func _finalize_combat_card(text: String, animate: bool) -> void:
	if _current_combat_card and is_instance_valid(_current_combat_card) and _current_combat_summary_label:
		# Set result summary
		var summary = text.strip_edges()
		if summary.begins_with("Result: "):
			summary = summary.substr(8)
		_current_combat_summary_label.text = summary
		_current_combat_summary_label.visible = true

		# Color the summary based on outcome
		var has_casualties = "destroyed" in text and "No models" not in text and "0 model" not in text
		if has_casualties:
			_current_combat_summary_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42))
		else:
			_current_combat_summary_label.add_theme_color_override("font_color", Color(0.47, 0.8, 0.47))

		# Show toggle button now that there are details
		if _current_combat_toggle_button:
			_current_combat_toggle_button.visible = true

		_current_combat_card = null
		_current_combat_details_label = null
		_current_combat_toggle_button = null
		_current_combat_summary_label = null
		_current_combat_details_container = null
	else:
		# Orphaned result — create standalone card
		var card = _make_combat_result_card(text)
		_card_container.add_child(card)
		_card_count += 1
		if animate:
			_animate_card_in(card)

# ==========================================================================
# Simple card creation (non-combat entries)
# ==========================================================================

func _create_simple_card(text: String, entry_type: String, animate: bool) -> void:
	var category = _categorize_entry_type(entry_type)
	# Refine category based on text content for player actions
	category = _refine_category_from_text(text, category)

	var card: PanelContainer

	match entry_type:
		"phase_header":
			card = _make_phase_card(text)
		"overwatch":
			card = _make_simple_entry_card(text, entry_type, EntryCategory.OVERWATCH)
		"ai_thinking":
			card = _make_simple_entry_card(text, entry_type, EntryCategory.AI_THINKING)
		_:
			card = _make_simple_entry_card(text, entry_type, category)

	_card_container.add_child(card)
	_card_count += 1

	# Track AI cards for filtering
	if entry_type == "ai_thinking":
		_ai_cards.append(card)
		card.visible = _show_ai_thinking

	if animate:
		_animate_card_in(card)

# ==========================================================================
# Card builders
# ==========================================================================

func _make_card_style(bg_color: Color, accent_color: Color, accent_width: int = 3) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg_color
	s.corner_radius_top_left = 2
	s.corner_radius_top_right = CARD_CORNER_RADIUS
	s.corner_radius_bottom_left = 2
	s.corner_radius_bottom_right = CARD_CORNER_RADIUS
	s.border_width_left = accent_width
	s.border_color = accent_color
	s.content_margin_left = CARD_PADDING + accent_width
	s.content_margin_right = CARD_PADDING
	s.content_margin_top = CARD_PADDING
	s.content_margin_bottom = CARD_PADDING
	return s

func _make_phase_card(text: String) -> PanelContainer:
	var card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.12, 0.08, 0.95)
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

	var clean_text = text.strip_edges().trim_prefix("---").trim_suffix("---").strip_edges()

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	card.add_child(hbox)

	var icon = _create_icon(EntryCategory.PHASE)
	hbox.add_child(icon)

	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", 13)
	label.add_theme_font_size_override("bold_font_size", 13)
	label.append_text("[b][color=#D49761]%s[/color][/b]" % clean_text)
	hbox.add_child(label)

	return card

func _make_simple_entry_card(text: String, entry_type: String, category: int) -> PanelContainer:
	var accent = BORDER_COLORS.get(category, Color.GRAY)
	var bg_color = Color(0.1, 0.1, 0.14, 0.9)
	var accent_width = 3

	if entry_type == "ai_thinking":
		bg_color = Color(0.08, 0.08, 0.11, 0.7)
		accent_width = 2
	elif entry_type == "overwatch":
		bg_color = Color(0.15, 0.1, 0.05, 0.95)
		accent_width = 4

	var card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style(bg_color, accent, accent_width))
	card.custom_minimum_size = Vector2(0, 28)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	card.add_child(hbox)

	# Icon badge
	var icon = _create_icon(category)
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

	return card

func _make_combat_result_card(text: String) -> PanelContainer:
	var has_casualties = "destroyed" in text and "No models" not in text and "0 model" not in text
	var accent = Color(1.0, 0.42, 0.42) if has_casualties else Color(0.47, 0.8, 0.47)
	var text_color = "#FF6B6B" if has_casualties else "#77CC77"

	var card = PanelContainer.new()
	var style = _make_card_style(Color(0.1, 0.1, 0.15, 0.95), accent, 4)
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

# ==========================================================================
# Icon badge (from f4dOz)
# ==========================================================================

func _create_icon(category: int) -> PanelContainer:
	var icon_panel = PanelContainer.new()
	icon_panel.custom_minimum_size = Vector2(22, 22)

	var border_color = BORDER_COLORS.get(category, Color.GRAY)
	var icon_style = StyleBoxFlat.new()
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
	icon_label.text = ICON_CHARS.get(category, "?")
	icon_label.add_theme_font_size_override("font_size", 9)
	icon_label.add_theme_color_override("font_color", border_color)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon_panel.add_child(icon_label)

	return icon_panel

# ==========================================================================
# Animation (from f4dOz)
# ==========================================================================

func _animate_card_in(card: Control) -> void:
	card.modulate.a = 0.0
	var original_pos = card.position.y
	card.position.y += 15.0

	var tween = card.create_tween()
	tween.set_parallel(true)
	tween.tween_property(card, "modulate:a", 1.0, 0.25).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "position:y", original_pos, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

# ==========================================================================
# Text formatting
# ==========================================================================

func _format_entry_text(text: String, entry_type: String) -> String:
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

# ==========================================================================
# Category mapping & refinement (from f4dOz)
# ==========================================================================

func _categorize_entry_type(entry_type: String) -> int:
	match entry_type:
		"phase_header":
			return EntryCategory.PHASE
		"p1_action", "p2_action":
			return EntryCategory.MOVEMENT
		"ai_thinking":
			return EntryCategory.AI_THINKING
		"overwatch":
			return EntryCategory.OVERWATCH
		"combat_header", "combat_detail", "combat_result":
			return EntryCategory.COMBAT
		"info":
			return EntryCategory.INFO
		_:
			return EntryCategory.INFO

func _refine_category_from_text(text: String, current_category: int) -> int:
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

# ==========================================================================
# Combat detail styling (dice rolls, keywords)
# ==========================================================================

func _style_combat_detail(text: String) -> String:
	var styled = text

	# Highlight dice roll arrays [1, 3, 5, 6]
	var dice_results = _dice_regex.search_all(styled)
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
# Card trimming
# ==========================================================================

func _trim_old_cards(count: int) -> void:
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
# Filter & visibility (AI toggle from xBfRG)
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
			_ai_filter_button.tooltip_text = "AI thinking visible - click to hide"
		else:
			_ai_filter_button.modulate = Color(1, 1, 1, 0.4)
			_ai_filter_button.tooltip_text = "AI thinking hidden - click to show"

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
