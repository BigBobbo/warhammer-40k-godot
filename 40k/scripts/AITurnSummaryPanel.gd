extends PanelContainer
class_name AITurnSummaryPanel

# AITurnSummaryPanel - Post-turn summary popup showing what the AI did (T7-19)
# Appears after each AI turn ends, consuming the ai_turn_ended signal and the
# _action_log from AIPlayer. Displays a categorized summary: units moved,
# shooting results, charge results, fight results, stratagems used, etc.
# The panel auto-shows when the AI finishes a thinking sequence and can be
# dismissed with a button click or the Escape key.

const WhiteDwarfThemeData = preload("res://scripts/WhiteDwarfTheme.gd")
const GameStateData = preload("res://autoloads/GameState.gd")

# Layout constants
const PANEL_WIDTH: float = 380.0
const PANEL_MAX_HEIGHT: float = 420.0
const FONT_SIZE: int = 12
const HEADER_FONT_SIZE: int = 14
const TITLE_FONT_SIZE: int = 16
const CATEGORY_FONT_SIZE: int = 13

# Auto-dismiss timer (seconds) — panel hides itself after this duration
const AUTO_DISMISS_DELAY: float = 12.0

# Color constants (matching existing panel themes)
const COLOR_P1: Color = Color(0.4, 0.6, 0.85)
const COLOR_P2: Color = Color(0.85, 0.4, 0.4)
const COLOR_GOLD: Color = Color(0.833, 0.588, 0.376)
const COLOR_PARCHMENT: Color = Color(0.922, 0.882, 0.780)
const COLOR_CATEGORY: Color = Color(0.9, 0.78, 0.5)
const COLOR_STAT: Color = Color(0.75, 0.85, 0.75)
const COLOR_EMPTY: Color = Color(0.5, 0.5, 0.5)

# Phase name lookup
const PHASE_NAMES = {
	GameStateData.Phase.DEPLOYMENT: "Deployment",
	GameStateData.Phase.ROLL_OFF: "Roll-Off",
	GameStateData.Phase.COMMAND: "Command",
	GameStateData.Phase.MOVEMENT: "Movement",
	GameStateData.Phase.SHOOTING: "Shooting",
	GameStateData.Phase.CHARGE: "Charge",
	GameStateData.Phase.FIGHT: "Fight",
	GameStateData.Phase.SCORING: "Scoring",
	GameStateData.Phase.MORALE: "Morale",
}

# UI nodes (built procedurally in _build_ui)
var _title_label: Label
var _close_button: Button
var _scroll_container: ScrollContainer
var _summary_label: RichTextLabel
var _dismiss_button: Button

# State
var _auto_dismiss_timer: float = 0.0
var _is_counting_down: bool = false

func _ready() -> void:
	_build_ui()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP  # Block clicks through to game
	print("[AITurnSummaryPanel] T7-19: Ready")

func _build_ui() -> void:
	name = "AITurnSummaryPanel"

	# Anchor to right side of screen, vertically centered
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -(PANEL_WIDTH + 15.0)
	offset_right = -15.0
	offset_top = -PANEL_MAX_HEIGHT / 2.0
	offset_bottom = PANEL_MAX_HEIGHT / 2.0

	# Dark background with gold border — WhiteDwarf style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.95)
	style.border_color = Color(WhiteDwarfThemeData.WH_GOLD, 0.8)
	style.set_border_width_all(2)
	style.border_width_top = 3
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)

	# Main VBox
	var vbox = VBoxContainer.new()
	vbox.name = "MainVBox"
	add_child(vbox)

	# Title bar with close button
	var title_bar = HBoxContainer.new()
	title_bar.name = "TitleBar"
	vbox.add_child(title_bar)

	_title_label = Label.new()
	_title_label.text = "AI Turn Summary"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_title_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	title_bar.add_child(_title_label)

	_close_button = Button.new()
	_close_button.text = "X"
	_close_button.custom_minimum_size = Vector2(28, 28)
	_close_button.pressed.connect(_dismiss)
	WhiteDwarfThemeData.apply_to_button(_close_button)
	title_bar.add_child(_close_button)

	# Separator
	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Scroll container for summary content
	_scroll_container = ScrollContainer.new()
	_scroll_container.name = "SummaryScroll"
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll_container)

	# RichTextLabel for color-coded BBCode summary
	_summary_label = RichTextLabel.new()
	_summary_label.name = "SummaryLabel"
	_summary_label.bbcode_enabled = true
	_summary_label.fit_content = true
	_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary_label.scroll_active = false  # ScrollContainer handles scrolling
	_summary_label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	_summary_label.add_theme_font_size_override("bold_font_size", FONT_SIZE + 1)
	_scroll_container.add_child(_summary_label)

	# Bottom separator
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	# Dismiss button at bottom
	_dismiss_button = Button.new()
	_dismiss_button.text = "Dismiss"
	_dismiss_button.custom_minimum_size = Vector2(0, 32)
	_dismiss_button.pressed.connect(_dismiss)
	WhiteDwarfThemeData.apply_to_button(_dismiss_button)
	vbox.add_child(_dismiss_button)

func _process(delta: float) -> void:
	if not visible or not _is_counting_down:
		return
	_auto_dismiss_timer += delta
	if _auto_dismiss_timer >= AUTO_DISMISS_DELAY:
		_dismiss()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_dismiss()
		get_viewport().set_input_as_handled()

# ── Public API ──────────────────────────────────────────────────────────

func show_summary(player: int, action_summary: Array) -> void:
	"""Called when ai_turn_ended fires. Builds and displays the turn summary."""
	if action_summary.is_empty():
		print("[AITurnSummaryPanel] T7-19: No actions to summarize for player %d" % player)
		return

	_build_summary_content(player, action_summary)

	# Show the panel with a fade-in
	visible = true
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.3)

	# Start auto-dismiss countdown
	_auto_dismiss_timer = 0.0
	_is_counting_down = true

	print("[AITurnSummaryPanel] T7-19: Showing summary for player %d (%d actions)" % [player, action_summary.size()])

func hide_summary() -> void:
	"""Hide the panel immediately."""
	_dismiss()

# ── Private ─────────────────────────────────────────────────────────────

func _dismiss() -> void:
	_is_counting_down = false
	if visible:
		var tween = create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 0.2)
		tween.tween_callback(func(): visible = false; modulate.a = 1.0)
		print("[AITurnSummaryPanel] T7-19: Dismissed")

func _build_summary_content(player: int, action_summary: Array) -> void:
	"""Parse the action log and build a categorized summary."""
	_summary_label.clear()

	var player_color = COLOR_P1 if player == 1 else COLOR_P2
	var player_hex = player_color.to_html(false)
	var gold_hex = COLOR_GOLD.to_html(false)
	var cat_hex = COLOR_CATEGORY.to_html(false)
	var stat_hex = COLOR_STAT.to_html(false)
	var parchment_hex = COLOR_PARCHMENT.to_html(false)

	# Header
	var faction_name = ""
	var game_state = _get_game_state()
	if game_state:
		faction_name = game_state.get_faction_name(player)
	var header_text = "Player %d" % player
	if faction_name != "":
		header_text += " (%s)" % faction_name
	_summary_label.append_text("[b][color=#%s]%s[/color][/b]\n" % [player_hex, header_text])

	# Round info
	var battle_round = 0
	if game_state:
		battle_round = game_state.get_battle_round()
	if battle_round > 0:
		_summary_label.append_text("[color=#%s]Battle Round %d[/color]\n\n" % [gold_hex, battle_round])

	# Categorize actions by phase, then by type within each phase
	var phase_actions = _categorize_by_phase(action_summary)

	if phase_actions.is_empty():
		_summary_label.append_text("[color=#%s]No significant actions taken.[/color]\n" % COLOR_EMPTY.to_html(false))
		return

	# Render each phase's summary
	for phase_id in phase_actions:
		var phase_name = PHASE_NAMES.get(phase_id, "Phase %d" % phase_id)
		var actions = phase_actions[phase_id]
		var counts = _count_action_categories(actions)

		if counts.is_empty():
			continue

		# Phase header
		_summary_label.append_text("[b][color=#%s]%s[/color][/b]\n" % [cat_hex, phase_name])

		# Category stats
		for entry in _format_category_counts(counts):
			_summary_label.append_text("  [color=#%s]%s[/color]\n" % [stat_hex, entry.text])

		# Show notable action descriptions (up to 3 per phase)
		var notable = _get_notable_actions(actions)
		if not notable.is_empty():
			for desc in notable:
				_summary_label.append_text("  [color=#%s]> %s[/color]\n" % [parchment_hex, desc])

		_summary_label.append_text("\n")

	# Scroll to top
	call_deferred("_scroll_to_top")

func _categorize_by_phase(actions: Array) -> Dictionary:
	"""Group actions by their phase ID, preserving phase order."""
	var result: Dictionary = {}  # phase_id -> Array of actions
	var phase_order: Array = []  # Track insertion order
	for action in actions:
		var phase_id = action.get("phase", -1)
		if not result.has(phase_id):
			result[phase_id] = []
			phase_order.append(phase_id)
		result[phase_id].append(action)

	# Return in order of appearance (Dictionary insertion order is preserved in Godot 4)
	var ordered: Dictionary = {}
	for pid in phase_order:
		ordered[pid] = result[pid]
	return ordered

func _count_action_categories(actions: Array) -> Dictionary:
	"""Count actions by category within a phase."""
	var counts: Dictionary = {}
	for action in actions:
		var action_type = action.get("action_type", "")
		var category = _categorize_action(action_type)
		if category != "":
			counts[category] = counts.get(category, 0) + 1
	return counts

func _categorize_action(action_type: String) -> String:
	"""Map action types to readable summary categories (matches AIPlayer._categorize_action)."""
	match action_type:
		"DEPLOY_UNIT":
			return "units_deployed"
		"REMAIN_STATIONARY":
			return "units_stationary"
		"CONFIRM_UNIT_MOVE", "BEGIN_NORMAL_MOVE":
			return "units_moved"
		"BEGIN_ADVANCE":
			return "units_advanced"
		"BEGIN_FALL_BACK":
			return "units_fell_back"
		"SHOOT":
			return "units_shot"
		"DECLARE_CHARGE":
			return "charges_declared"
		"SELECT_FIGHTER", "ASSIGN_ATTACKS":
			return "units_fought"
		"USE_REACTIVE_STRATAGEM", "USE_FIRE_OVERWATCH", "USE_COUNTER_OFFENSIVE", \
		"USE_HEROIC_INTERVENTION", "USE_TANK_SHOCK", "USE_GRENADE_STRATAGEM", \
		"USE_COMMAND_REROLL":
			return "stratagems_used"
		"SKIP_UNIT", "SKIP_CHARGE":
			return "units_skipped"
		"PLACE_REINFORCEMENT":
			return "reinforcements"
		"CONFIRM_SCOUT_MOVE":
			return "scouts_moved"
		"END_MOVEMENT", "END_SHOOTING", "END_CHARGE", "END_FIGHT", "END_SCORING":
			return ""  # Phase-ending actions are not shown
		_:
			return ""

func _format_category_counts(counts: Dictionary) -> Array:
	"""Format category counts into display entries with labels and icons."""
	var entries: Array = []

	# Define display order and labels
	var display_config = [
		{"key": "units_deployed", "label": "Units deployed", "icon": "+"},
		{"key": "scouts_moved", "label": "Scout moves", "icon": ">"},
		{"key": "units_moved", "label": "Units moved", "icon": ">"},
		{"key": "units_advanced", "label": "Units advanced", "icon": ">>"},
		{"key": "units_fell_back", "label": "Units fell back", "icon": "<"},
		{"key": "units_stationary", "label": "Units remained stationary", "icon": "-"},
		{"key": "reinforcements", "label": "Reinforcements arrived", "icon": "+"},
		{"key": "units_shot", "label": "Units fired", "icon": "*"},
		{"key": "charges_declared", "label": "Charges declared", "icon": "!"},
		{"key": "units_fought", "label": "Units fought", "icon": "x"},
		{"key": "stratagems_used", "label": "Stratagems used", "icon": "#"},
		{"key": "units_skipped", "label": "Units skipped", "icon": "~"},
	]

	for config in display_config:
		var key = config.key
		if counts.has(key) and counts[key] > 0:
			entries.append({
				"text": "%s %s: %d" % [config.icon, config.label, counts[key]]
			})

	return entries

func _get_notable_actions(actions: Array) -> Array:
	"""Extract notable action descriptions for display (charges, stratagems, key fights)."""
	var notable: Array = []
	var notable_types = [
		"DECLARE_CHARGE", "USE_REACTIVE_STRATAGEM", "USE_FIRE_OVERWATCH",
		"USE_COUNTER_OFFENSIVE", "USE_HEROIC_INTERVENTION", "USE_TANK_SHOCK",
		"USE_GRENADE_STRATAGEM", "USE_COMMAND_REROLL", "PLACE_REINFORCEMENT"
	]
	var max_notable = 4

	for action in actions:
		if notable.size() >= max_notable:
			break
		var action_type = action.get("action_type", "")
		if action_type in notable_types:
			var desc = action.get("description", "")
			if desc != "":
				notable.append(desc)

	return notable

func _scroll_to_top() -> void:
	if _scroll_container and is_instance_valid(_scroll_container):
		_scroll_container.scroll_vertical = 0

func _get_game_state() -> Node:
	"""Get GameState autoload via node tree."""
	var root = get_tree().root if get_tree() else null
	if root:
		return root.get_node_or_null("GameState")
	return null
