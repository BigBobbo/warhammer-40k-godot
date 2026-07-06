extends PanelContainer
class_name GameLogPanel

const DiceRowVisualScript := preload("res://scripts/DiceRowVisual.gd")

## GameLogPanel — Self-contained card-based game event log UI.
## Combines: xBfRG's self-contained architecture + f4dOz's collapsible combat cards,
## animations, icon badges, and category refinement + xBfRG's AI filter toggle.

# --- Configuration ---
const PANEL_WIDTH := 340.0
const CARD_GAP := 3
const CARD_CORNER_RADIUS := 5
const CARD_PADDING := 8
const MAX_CARDS := 300

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
# Board-linked thinking cards (carry ai_link_context metadata) + pin state
var _linked_ai_cards: Array[PanelContainer] = []
var _pinned_link_card: PanelContainer = null
var _thought_link_visual: Node2D = null
var _card_count: int = 0
var _is_visible: bool = true
var _current_combat_card: PanelContainer = null
var _current_combat_details_text: String = ""
var _current_combat_details_container: VBoxContainer = null
var _current_combat_details_label: RichTextLabel = null
var _current_combat_toggle_button: Button = null
var _current_combat_summary_label: Label = null
var _current_combat_details_visible: bool = false
var _current_combat_dice_summary: RichTextLabel = null  # Visible dice roll summary (legacy / unused after inline-graphics refactor)
var _current_combat_dice_container: VBoxContainer = null  # Container of per-roll HBoxes with DiceRowVisual graphics

# Regex for dice roll styling (compiled once)
var _dice_regex: RegEx
var _threshold_regex: RegEx

func _ready() -> void:
	_dice_regex = RegEx.new()
	_dice_regex.compile("\\[([0-9, ]+)\\]")
	_threshold_regex = RegEx.new()
	_threshold_regex.compile("(?:needed |Save |Pain |vs )(\\d+)\\+")

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
	var sep = ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.color = Color(COLOR_GOLD.r, COLOR_GOLD.g, COLOR_GOLD.b, 0.4)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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

	# Connect to GameEventLog (accessed via scene tree since autoloads aren't available at class_name parse time)
	var game_event_log = Engine.get_main_loop().root.get_node_or_null("GameEventLog") if Engine.get_main_loop() else null
	if game_event_log:
		game_event_log.entry_added.connect(_on_entry_added)
		print("GameLogPanel: Connected to GameEventLog.entry_added")
		# Populate existing entries (no animation for backfill)
		for entry in game_event_log.get_all_entries():
			_create_card(entry.text, entry.type, false)

	# Connect to DiceHistoryPanel for real-time dice display
	var dice_history = Engine.get_main_loop().root.get_node_or_null("DiceHistoryPanel") if Engine.get_main_loop() else null
	if dice_history:
		dice_history.roll_recorded.connect(_on_dice_roll_recorded)
		print("GameLogPanel: Connected to DiceHistoryPanel.roll_recorded for real-time dice")

	print("GameLogPanel: Setup complete")

func get_toggle_button() -> Button:
	return _toggle_button

func get_ai_card_count() -> int:
	"""Live AI thinking cards currently in the panel (scenario assertions)."""
	var n := 0
	for c in _ai_cards:
		if is_instance_valid(c):
			n += 1
	return n

# ==========================================================================
# Board-linked thinking — hover/click a card to see the options on the board
# ==========================================================================

func _get_thought_link_visual() -> Node2D:
	"""Lazily create the AIThoughtLinkVisual under Main/BoardRoot so arrows
	draw in board space alongside tokens."""
	if _thought_link_visual != null and is_instance_valid(_thought_link_visual):
		return _thought_link_visual
	var main = get_parent()
	if main == null:
		return null
	var board_root = main.get_node_or_null("BoardRoot")
	if board_root == null:
		return null
	_thought_link_visual = board_root.get_node_or_null("AIThoughtLinkVisual")
	if _thought_link_visual == null:
		_thought_link_visual = preload("res://scripts/AIThoughtLinkVisual.gd").new()
		board_root.add_child(_thought_link_visual)
		print("GameLogPanel: Created AIThoughtLinkVisual in BoardRoot")
	return _thought_link_visual

func _show_thought_links(context: Dictionary) -> void:
	var visual = _get_thought_link_visual()
	if visual:
		visual.show_links(context)

func _hide_thought_links() -> void:
	if _thought_link_visual != null and is_instance_valid(_thought_link_visual):
		_thought_link_visual.clear_links()

func _toggle_thought_link_pin(card: PanelContainer) -> void:
	"""Click behaviour: pin this card's option arrows on the board; clicking
	the pinned card again (or another linked card) unpins/switches."""
	if _pinned_link_card == card:
		_pinned_link_card = null
		_hide_thought_links()
		return
	_pinned_link_card = card
	_show_thought_links(card.get_meta("ai_link_context", {}))

func activate_latest_ai_link() -> bool:
	"""Pin the most recent board-linked thinking card — same path as clicking
	it. Used by windowed scenarios to validate the feature end-to-end."""
	for i in range(_linked_ai_cards.size() - 1, -1, -1):
		var card = _linked_ai_cards[i]
		if is_instance_valid(card):
			_toggle_thought_link_pin(card)
			return _pinned_link_card == card
	return false

func get_linked_ai_card_count() -> int:
	var n := 0
	for c in _linked_ai_cards:
		if is_instance_valid(c):
			n += 1
	return n

# ==========================================================================
# Card creation — entry point
# ==========================================================================

func _on_entry_added(text: String, entry_type: String) -> void:
	_create_card(text, entry_type, true)
	# Auto-scroll to bottom
	if _scroll:
		await get_tree().process_frame
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

func _on_dice_roll_recorded(entry: Dictionary) -> void:
	"""Handle real-time dice roll from DiceHistoryPanel — append a graphical row to the current combat card."""
	if not _current_combat_card or not is_instance_valid(_current_combat_card):
		return
	if not _current_combat_dice_container or not is_instance_valid(_current_combat_dice_container):
		return

	var data = entry.get("data", {})
	var context = data.get("context", "")

	# Skip non-roll contexts
	if context in ["resolution_start", "weapon_progress"]:
		return

	var row := _build_realtime_dice_row(data, context)
	if row == null:
		return

	_current_combat_dice_container.add_child(row)
	_current_combat_dice_container.visible = true

	# Auto-scroll to bottom
	if _scroll:
		await get_tree().process_frame
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

func dice_row_has_visual(row_index: int) -> bool:
	# Test introspection helper: returns true if the dice-container row at
	# `row_index` contains a DiceRowVisual child. Used by windowed scenarios
	# that validate inline dice graphics are mounted.
	if not _current_combat_dice_container or not is_instance_valid(_current_combat_dice_container):
		return false
	if row_index < 0 or row_index >= _current_combat_dice_container.get_child_count():
		return false
	var row = _current_combat_dice_container.get_child(row_index)
	for c in row.get_children():
		if c is DiceRowVisualScript:
			return true
	return false

func combat_detail_row_has_visual(row_index: int) -> bool:
	# Test introspection helper: returns true if the collapsible details row at
	# `row_index` contains a DiceRowVisual child (i.e. the dice array was rendered
	# as grouped icons instead of inline number badges).
	if not _current_combat_details_container or not is_instance_valid(_current_combat_details_container):
		return false
	if row_index < 0 or row_index >= _current_combat_details_container.get_child_count():
		return false
	var row = _current_combat_details_container.get_child(row_index)
	if row is DiceRowVisualScript:
		return true
	for c in row.get_children():
		if c is DiceRowVisualScript:
			return true
	return false

func _node_has_dice_visual(node: Node) -> bool:
	# Recursively search a node subtree for a DiceRowVisual instance.
	if node is DiceRowVisualScript:
		return true
	for c in node.get_children():
		if _node_has_dice_visual(c):
			return true
	return false

func last_simple_card_has_dice_visual() -> bool:
	# Test introspection helper: true if the most recently added card in the main
	# card container renders dice icons (e.g. an advance/charge roll line).
	if _card_container == null or _card_container.get_child_count() == 0:
		return false
	var last = _card_container.get_child(_card_container.get_child_count() - 1)
	return _node_has_dice_visual(last)

func _build_realtime_dice_row(data: Dictionary, context: String) -> Control:
	"""Build an HBox row containing prefix label + graphical dice + suffix label."""
	var rolls_raw = data.get("rolls_raw", [])
	var threshold_str = str(data.get("threshold", ""))
	var threshold_int = int(threshold_str.replace("+", "")) if threshold_str != "" and threshold_str != "0" else 0

	match context:
		"to_hit":
			var successes = data.get("successes", 0)
			var total = rolls_raw.size()
			return _make_dice_row(
				"[color=#AACCEE][b]Hit[/b] (%s):[/color]" % threshold_str,
				rolls_raw, threshold_int, true,
				"[color=#AACCEE]— %d/%d[/color]" % [successes, total]
			)
		"to_wound":
			var successes = data.get("successes", 0)
			var total = rolls_raw.size()
			return _make_dice_row(
				"[color=#EEAA77][b]Wound[/b] (%s):[/color]" % threshold_str,
				rolls_raw, threshold_int, true,
				"[color=#EEAA77]— %d/%d[/color]" % [successes, total]
			)
		"save_roll":
			var failed = data.get("failed", 0)
			var using_invuln = data.get("using_invuln", false)
			var label = "Inv Save" if using_invuln else "Save"
			var result_color = "#FF6B6B" if failed > 0 else "#77CC77"
			return _make_dice_row(
				"[color=#BB88FF][b]%s[/b] (%s):[/color]" % [label, threshold_str],
				rolls_raw, threshold_int, true,
				"[color=%s]— %d failed[/color]" % [result_color, failed]
			)
		"feel_no_pain":
			var prevented = data.get("wounds_prevented", 0)
			var fnp_val = data.get("fnp_value", 0)
			return _make_dice_row(
				"[color=#44CC88][b]FNP[/b] (%d+):[/color]" % fnp_val,
				rolls_raw, fnp_val, true,
				"[color=#44CC88]— %d prevented[/color]" % prevented
			)
		"auto_hit":
			# No dice — text-only line via dice-less row.
			var hits = data.get("successes", 0)
			return _make_dice_row(
				"[color=#FF8844][b]Torrent[/b]:[/color]",
				[], 0, true,
				"[color=#88EE88]%d auto-hits[/color]" % hits
			)
		"charge_roll":
			var rolls = data.get("rolls", data.get("rolls_raw", []))
			var total = data.get("total", 0)
			var charge_failed = data.get("charge_failed", false)
			var result_color = "#FF6B6B" if charge_failed else "#77CC77"
			var result_text = "FAILED" if charge_failed else "SUCCESS"
			return _make_dice_row(
				"[color=#E6CC33][b]Charge[/b]:[/color]",
				rolls, 0, false,
				"[color=%s]= %d\" %s[/color]" % [result_color, total, result_text]
			)
		"variable_damage":
			var dmg_rolls = data.get("rolls", [])
			var total_dmg = data.get("total_damage", 0)
			var roll_values = []
			for r in dmg_rolls:
				roll_values.append(r.get("value", 0))
			return _make_dice_row(
				"[color=#CCAA55][b]Damage[/b]:[/color]",
				roll_values, 0, false,
				"[color=#CCAA55]= %d[/color]" % total_dmg
			)
		_:
			return null

func _make_dice_row(prefix_bbcode: String, rolls: Array, threshold: int, use_threshold_colors: bool, suffix_bbcode: String, normal_size: int = 10, bold_size: int = 11) -> Control:
	"""Build a single HBox row: [prefix RichTextLabel] [DiceRowVisual] [suffix RichTextLabel]."""
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var prefix := RichTextLabel.new()
	prefix.bbcode_enabled = true
	prefix.fit_content = true
	prefix.scroll_active = false
	# The prefix is non-expanding, so leaving autowrap on lets it collapse to a
	# 1px-wide column and grow absurdly tall. Disable autowrap so it sizes to its
	# natural single-line width.
	prefix.autowrap_mode = TextServer.AUTOWRAP_OFF
	prefix.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	prefix.add_theme_font_size_override("normal_font_size", normal_size)
	prefix.add_theme_font_size_override("bold_font_size", bold_size)
	prefix.append_text(prefix_bbcode)
	hbox.add_child(prefix)

	if not rolls.is_empty():
		var dice := DiceRowVisualScript.new()
		dice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dice.set_dice(rolls, threshold, use_threshold_colors)
		hbox.add_child(dice)

	var suffix := RichTextLabel.new()
	suffix.bbcode_enabled = true
	suffix.fit_content = true
	suffix.scroll_active = false
	suffix.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	suffix.add_theme_font_size_override("normal_font_size", normal_size)
	suffix.add_theme_font_size_override("bold_font_size", bold_size)
	suffix.append_text(suffix_bbcode)
	hbox.add_child(suffix)

	return hbox

func _format_dice_badges(rolls: Array, threshold: int) -> String:
	"""Format an array of dice values as colored inline badges with good spacing."""
	var badges = []
	for r in rolls:
		var val = int(r)
		badges.append(_make_die_badge(val, threshold))
	return "".join(badges)

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

	# Visible dice summary — VBox of per-roll rows, each row = prefix label + DiceRowVisual + suffix label
	_current_combat_dice_container = VBoxContainer.new()
	_current_combat_dice_container.add_theme_constant_override("separation", 2)
	_current_combat_dice_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_current_combat_dice_container.visible = false
	card_vbox.add_child(_current_combat_dice_container)
	_current_combat_dice_summary = null  # legacy field; kept declared for type-safety, unused at runtime

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

	# Collapsible details container — holds one row Control per detail line
	# (text-only or a grouped DiceRowVisual row). Populated by _append_combat_detail.
	_current_combat_details_container = VBoxContainer.new()
	_current_combat_details_container.add_theme_constant_override("separation", 2)
	_current_combat_details_container.visible = false
	card_vbox.add_child(_current_combat_details_container)
	_current_combat_details_label = null  # legacy single-label model retired; rows added directly

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
	if _current_combat_card and is_instance_valid(_current_combat_card) and _current_combat_details_container and is_instance_valid(_current_combat_details_container):
		# Append a per-line row to the current combat card's collapsible section.
		# Lines containing a dice array [..] render the dice as grouped icons via
		# DiceRowVisual; other lines render as styled text.
		var row := _build_combat_detail_line(text.strip_edges())
		_current_combat_details_container.add_child(row)
	else:
		# Orphaned detail — create standalone card
		var card = _make_simple_entry_card(text, "combat_detail", EntryCategory.COMBAT)
		_card_container.add_child(card)
		_card_count += 1
		if animate:
			_animate_card_in(card)

func _build_combat_detail_line(text: String) -> Control:
	"""Build a Control for one combat-detail line. If the line contains a dice
	array (e.g. 'rolled [1, 1, 2, 6]'), render the array as a grouped DiceRowVisual
	(one die icon per value + xN count); otherwise render styled text."""
	return _build_dice_aware_line(text, "#B0B8C0", 10, 11)

func line_has_dice_array(text: String) -> bool:
	"""True if a log line contains a [n, n, ...] dice array that should render as
	dice icons. Used to route simple cards through the dice-aware builder."""
	return _dice_regex.search(text) != null

func _build_dice_aware_line(text: String, color_hex: String, normal_size: int, bold_size: int) -> Control:
	"""Generic builder shared by combat details and simple cards. A line with a
	dice array renders as [prefix label][grouped DiceRowVisual][suffix label];
	otherwise it renders as a single styled label. Keyword highlighting and the
	supplied text color/font size are applied to the surrounding text either way."""
	var dice_match = _dice_regex.search(text)
	if dice_match == null:
		var label := RichTextLabel.new()
		label.bbcode_enabled = true
		label.fit_content = true
		label.scroll_active = false
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("normal_font_size", normal_size)
		label.add_theme_font_size_override("bold_font_size", bold_size)
		label.append_text("[color=%s]%s[/color]" % [color_hex, _highlight_keywords(text)])
		return label

	# Split the line around the dice array: [prefix] [dice icons] [suffix]
	var threshold := _extract_threshold(text)
	var prefix_text := text.substr(0, dice_match.get_start()).strip_edges()
	var suffix_text := text.substr(dice_match.get_end()).strip_edges()

	var rolls := []
	for d in dice_match.get_string(1).split(","):
		var dval := d.strip_edges()
		if dval != "":
			rolls.append(int(dval))

	var prefix_bbcode := "[color=%s]%s[/color]" % [color_hex, _highlight_keywords(prefix_text)] if prefix_text != "" else ""
	var suffix_bbcode := "[color=%s]%s[/color]" % [color_hex, _highlight_keywords(suffix_text)] if suffix_text != "" else ""
	return _make_dice_row(prefix_bbcode, rolls, threshold, threshold > 0, suffix_bbcode, normal_size, bold_size)

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
		_current_combat_dice_summary = null
		_current_combat_dice_container = null
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
		"ai_thinking_block":
			# Board-link context (unit + candidate positions) travels alongside
			# the entry — read it synchronously from the emitting autoload.
			var block_context: Dictionary = {}
			var gel = Engine.get_main_loop().root.get_node_or_null("GameEventLog") if Engine.get_main_loop() else null
			if gel and gel.has_method("get_last_entry_context"):
				block_context = gel.get_last_entry_context()
			card = _make_ai_thinking_block_card(text, block_context)
		_:
			card = _make_simple_entry_card(text, entry_type, category)

	_card_container.add_child(card)
	_card_count += 1

	# Track AI cards for filtering
	if entry_type == "ai_thinking" or entry_type == "ai_thinking_block":
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
	var phase_border = _get_player_color_from_text(text)
	style.border_color = phase_border
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
	var color_hex = phase_border.to_html(false)
	label.append_text("[b][color=#%s]%s[/color][/b]" % [color_hex, clean_text])
	hbox.add_child(label)

	return card

func _get_player_color_from_text(text: String) -> Color:
	var lower = text.to_lower()
	if "player 1" in lower or "p1" in lower:
		return FactionPalettes.get_player_border_color(1)
	elif "player 2" in lower or "p2" in lower:
		return FactionPalettes.get_player_border_color(2)
	return COLOR_GOLD

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
	card.custom_minimum_size = Vector2(0, 24)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	card.add_child(hbox)

	# Icon badge
	var icon = _create_icon(category)
	hbox.add_child(icon)

	# Dice-bearing lines (e.g. advance/charge/overwatch rolls) render their
	# dice array as grouped icons instead of plain numbers — same treatment as
	# combat details, but tinted to the entry's color.
	if line_has_dice_array(text):
		var dice_content = _build_dice_aware_line(text, _entry_text_color(entry_type), 11, 12)
		hbox.add_child(dice_content)
		return card

	# Text label — truncate long entries with expand on click
	var display_text = text
	var is_truncated = false
	var max_chars = 120
	if entry_type != "phase_header" and text.length() > max_chars:
		display_text = text.substr(0, max_chars).strip_edges() + "..."
		is_truncated = true

	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", 11)
	label.add_theme_font_size_override("bold_font_size", 12)
	label.append_text(_format_entry_text(display_text, entry_type))

	if is_truncated:
		var full_text = text
		var fmt_type = entry_type
		label.meta_clicked.connect(func(_meta): pass)
		label.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				label.text = ""
				label.append_text(_format_entry_text(full_text, fmt_type))
		)
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		label.tooltip_text = "Click to expand"

	hbox.add_child(label)

	return card

func _make_ai_thinking_block_card(text: String, link_context: Dictionary = {}) -> PanelContainer:
	"""Collapsible card for one AI decision's verbose reasoning.
	First line of `text` is the headline; remaining lines are the considered
	options / rejections, hidden behind a 'considerations' toggle so heavy
	verbosity stays scannable. When `link_context` carries board positions,
	the card becomes interactive: hover previews the considered options as
	arrows on the board (chosen green, rejected red); click pins them."""
	var lines = text.split("\n")
	var header_text = lines[0] if lines.size() > 0 else text
	var detail_lines: Array = []
	for i in range(1, lines.size()):
		detail_lines.append(lines[i])

	var is_linked: bool = not link_context.is_empty() and not link_context.get("candidates", []).is_empty()
	var accent = BORDER_COLORS[EntryCategory.AI_THINKING]
	if is_linked:
		# Brighter accent signals "hover me — I draw on the board"
		accent = Color(0.45, 0.65, 0.9)
	var card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style(Color(0.08, 0.08, 0.11, 0.7), accent, 3 if is_linked else 2))
	card.custom_minimum_size = Vector2(0, 24)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_linked:
		card.set_meta("ai_link_context", link_context)
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.tooltip_text = "Hover: show this decision's options on the board. Click: pin/unpin."
		card.mouse_entered.connect(func():
			if _pinned_link_card == null:
				_show_thought_links(link_context))
		card.mouse_exited.connect(func():
			if _pinned_link_card == null:
				_hide_thought_links())
		card.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_toggle_thought_link_pin(card))
		_linked_ai_cards.append(card)

	var card_vbox = VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 2)
	card.add_child(card_vbox)

	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 6)
	card_vbox.add_child(header_hbox)

	var icon = _create_icon(EntryCategory.AI_THINKING)
	header_hbox.add_child(icon)

	var header_label = RichTextLabel.new()
	header_label.bbcode_enabled = true
	header_label.fit_content = true
	header_label.scroll_active = false
	header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_label.add_theme_font_size_override("normal_font_size", 11)
	header_label.add_theme_font_size_override("bold_font_size", 12)
	header_label.append_text("[i][color=#8899AA]%s[/color][/i]" % header_text)
	# Let the card itself receive hover/click for the board-link interaction
	header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_hbox.add_child(header_label)

	if detail_lines.is_empty():
		return card

	var toggle_btn = Button.new()
	toggle_btn.text = "  %d considerations…" % detail_lines.size()
	toggle_btn.add_theme_font_size_override("font_size", 9)
	toggle_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle_btn.flat = true
	toggle_btn.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
	toggle_btn.add_theme_color_override("font_hover_color", Color(0.7, 0.8, 0.9))
	card_vbox.add_child(toggle_btn)

	var details = RichTextLabel.new()
	details.bbcode_enabled = true
	details.fit_content = true
	details.scroll_active = false
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_font_size_override("normal_font_size", 10)
	details.visible = false
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for line in detail_lines:
		var l = str(line)
		# Rejections get a dim red tint so declined options stand out from
		# chosen/analysis lines when the block is expanded
		if l.strip_edges().begins_with("✗") or "rejected" in l.to_lower() or "declined" in l.to_lower() or "holding" in l.to_lower():
			details.append_text("[color=#A07070]%s[/color]\n" % l)
		else:
			details.append_text("[color=#8899AA]%s[/color]\n" % l)
	card_vbox.add_child(details)

	var detail_count = detail_lines.size()
	toggle_btn.pressed.connect(func():
		details.visible = !details.visible
		toggle_btn.text = ("  hide considerations" if details.visible else "  %d considerations…" % detail_count)
	)

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

func _entry_text_color(entry_type: String) -> String:
	"""Base text color (hex with leading #) used for a simple-card entry type.
	Mirrors the colors in _format_entry_text so dice-aware lines stay on-palette."""
	match entry_type:
		"phase_header":
			return "#D49761"
		"p1_action":
			return "#6699CC"
		"p2_action":
			return "#CC6666"
		"ai_thinking":
			return "#8899AA"
		"overwatch":
			return "#FF6600"
		_:
			return "#B0B8C0"

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
			return _format_by_content(text)

func _format_by_content(text: String) -> String:
	var lower = text.to_lower()
	if "score" in lower or "vp" in lower or "victory" in lower:
		return "[color=#4DCC66]%s[/color]" % text
	elif "move" in lower or "advance" in lower or "fall back" in lower:
		return "[color=#6699EE]%s[/color]" % text
	elif "shoot" in lower or "hit" in lower or "wound" in lower:
		return "[color=#EE7766]%s[/color]" % text
	elif "charge" in lower or "pile in" in lower or "consolidat" in lower:
		return "[color=#E6CC33]%s[/color]" % text
	elif "fight" in lower or "melee" in lower:
		return "[color=#BB66DD]%s[/color]" % text
	elif "deploy" in lower or "placed" in lower:
		return "[color=#88BBDD]%s[/color]" % text
	elif "destroyed" in lower or "slain" in lower or "killed" in lower:
		return "[b][color=#FF6B6B]%s[/color][/b]" % text
	elif "stratagem" in lower or "cp" in lower:
		return "[color=#DDAA44]%s[/color]" % text
	return "[color=#BBBBBB]%s[/color]" % text

# ==========================================================================
# Category mapping & refinement (from f4dOz)
# ==========================================================================

func _categorize_entry_type(entry_type: String) -> int:
	match entry_type:
		"phase_header":
			return EntryCategory.PHASE
		"p1_action", "p2_action":
			return EntryCategory.MOVEMENT
		"ai_thinking", "ai_thinking_block":
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

	# Extract threshold from line context (e.g. "needed 3+", "Save 4+", "Pain 5+")
	var threshold := _extract_threshold(text)

	# Replace dice roll arrays [1, 3, 5, 6] with colored dice badges
	var dice_results = _dice_regex.search_all(styled)
	for i in range(dice_results.size() - 1, -1, -1):
		var m = dice_results[i]
		var inner = m.get_string(1)
		var dice_parts = inner.split(", ")
		var dice_badges = []
		for d in dice_parts:
			var dval = d.strip_edges()
			var num = int(dval)
			dice_badges.append(_make_die_badge(num, threshold))
		var replacement = " ".join(dice_badges)
		styled = styled.substr(0, m.get_start()) + replacement + styled.substr(m.get_end())

	return _highlight_keywords(styled)

func _extract_threshold(text: String) -> int:
	"""Pull the success threshold out of a detail line (e.g. 'needed 3+' -> 3)."""
	var threshold_match = _threshold_regex.search(text)
	if threshold_match:
		return int(threshold_match.get_string(1))
	return 0

func _highlight_keywords(text: String) -> String:
	"""Apply BBCode color highlights to combat keywords (no dice substitution)."""
	var styled = text
	styled = styled.replace("DEVASTATING WOUNDS", "[color=#FF4444]DEVASTATING WOUNDS[/color]")
	styled = styled.replace("DEVASTATING", "[color=#FF4444]DEVASTATING[/color]")
	styled = styled.replace("Lethal Hits", "[color=#FF8844]Lethal Hits[/color]")
	styled = styled.replace("Sustained Hits", "[color=#EEDD44]Sustained Hits[/color]")
	styled = styled.replace("Feel No Pain", "[color=#44CC88]Feel No Pain[/color]")
	styled = styled.replace("Invulnerable Save", "[color=#BB88FF]Invulnerable Save[/color]")
	styled = styled.replace("Re-rolls:", "[color=#88BBFF]Re-rolls:[/color]")
	styled = styled.replace("Torrent", "[color=#FF8844]Torrent[/color]")
	return styled

func _make_die_badge(value: int, threshold: int) -> String:
	"""Create a colored dice badge using BBCode bgcolor.
	Natural 6 = gold, natural 1 = red, else success (green) or failure (dark red) based on threshold."""
	var bg_color: String
	var text_color: String

	if value == 6:
		# Critical success — gold
		bg_color = "#7A6520"
		text_color = "#FFD700"
	elif value == 1:
		# Critical failure — red
		bg_color = "#6B2222"
		text_color = "#FF4444"
	elif threshold > 0 and value >= threshold:
		# Success — green
		bg_color = "#2B5B2B"
		text_color = "#88EE88"
	elif threshold > 0 and value < threshold:
		# Failure — dark muted
		bg_color = "#4A2222"
		text_color = "#AA6666"
	else:
		# No threshold context — neutral cyan
		bg_color = "#1A3A4A"
		text_color = "#66CCEE"

	# Compact dice badge with single-space padding
	return "[font_size=10][bgcolor=%s][color=%s] %d [/color][/bgcolor][/font_size] " % [bg_color, text_color, value]

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
		if old_card in _linked_ai_cards:
			_linked_ai_cards.erase(old_card)
		if old_card == _pinned_link_card:
			_pinned_link_card = null
			_hide_thought_links()
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
		WhiteDwarfTheme.apply_tab_button(_toggle_button, _is_visible)

func set_panel_visible(v: bool) -> void:
	_is_visible = v
	visible = v
	if _toggle_button:
		_toggle_button.text = "Hide Log" if v else "Show Log"
		WhiteDwarfTheme.apply_tab_button(_toggle_button, v)

func is_panel_visible() -> bool:
	return _is_visible
