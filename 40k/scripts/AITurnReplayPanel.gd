extends PanelContainer
class_name AITurnReplayPanel

# AITurnReplayPanel - In-game panel to review past AI actions (T7-56)
# Accessible from the game menu (R key) to review what the AI did in previous turns.
# Displays actions organized by turn/round with phase headers and color-coded entries.

const WhiteDwarfThemeData = preload("res://scripts/WhiteDwarfTheme.gd")
const GameStateData = preload("res://autoloads/GameState.gd")

# Layout constants
const PANEL_WIDTH: float = 420.0
const PANEL_MAX_HEIGHT: float = 500.0
const PANEL_MARGIN: float = 20.0
const FONT_SIZE: int = 12
const HEADER_FONT_SIZE: int = 14
const TITLE_FONT_SIZE: int = 16

# Color constants
const COLOR_P1: Color = Color(0.4, 0.6, 0.85)
const COLOR_P2: Color = Color(0.85, 0.4, 0.4)
const COLOR_PHASE: Color = Color(0.833, 0.588, 0.376)  # Gold
const COLOR_ROUND: Color = Color(0.9, 0.78, 0.5)  # Warm gold
const COLOR_INFO: Color = Color(0.7, 0.7, 0.7)
const COLOR_EMPTY: Color = Color(0.5, 0.5, 0.5)

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

# UI nodes
var _title_label: Label
var _close_button: Button
var _turn_nav_container: HBoxContainer
var _prev_button: Button
var _next_button: Button
var _turn_label: Label
var _scroll_container: ScrollContainer
var _log_label: RichTextLabel
var _empty_label: Label

# State
var _current_turn_index: int = -1  # Index into the turn list (-1 = show all)
var _turn_entries: Array = []  # Cached turn history from AIPlayer

func _ready() -> void:
	_build_ui()
	visible = false
	print("[AITurnReplayPanel] T7-56: Ready")

func _build_ui() -> void:
	name = "AITurnReplayPanel"

	# Center the panel
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -PANEL_WIDTH / 2.0
	offset_right = PANEL_WIDTH / 2.0
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
	_title_label.text = "AI Turn Replay"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_title_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	title_bar.add_child(_title_label)

	_close_button = Button.new()
	_close_button.text = "X"
	_close_button.custom_minimum_size = Vector2(28, 28)
	_close_button.pressed.connect(_on_close_pressed)
	WhiteDwarfThemeData.apply_to_button(_close_button)
	title_bar.add_child(_close_button)

	# Separator
	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Turn navigation bar
	_turn_nav_container = HBoxContainer.new()
	_turn_nav_container.name = "TurnNav"
	_turn_nav_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_turn_nav_container)

	_prev_button = Button.new()
	_prev_button.text = "<"
	_prev_button.custom_minimum_size = Vector2(32, 28)
	_prev_button.pressed.connect(_on_prev_turn)
	WhiteDwarfThemeData.apply_to_button(_prev_button)
	_turn_nav_container.add_child(_prev_button)

	_turn_label = Label.new()
	_turn_label.text = "All Turns"
	_turn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_label.add_theme_font_size_override("font_size", HEADER_FONT_SIZE)
	_turn_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	_turn_nav_container.add_child(_turn_label)

	_next_button = Button.new()
	_next_button.text = ">"
	_next_button.custom_minimum_size = Vector2(32, 28)
	_next_button.pressed.connect(_on_next_turn)
	WhiteDwarfThemeData.apply_to_button(_next_button)
	_turn_nav_container.add_child(_next_button)

	# Second separator
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	# Scroll container for action log
	_scroll_container = ScrollContainer.new()
	_scroll_container.name = "ActionLogScroll"
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll_container)

	# RichTextLabel for color-coded BBCode entries
	_log_label = RichTextLabel.new()
	_log_label.name = "ActionLogLabel"
	_log_label.bbcode_enabled = true
	_log_label.fit_content = true
	_log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_label.scroll_active = false  # ScrollContainer handles scrolling
	_log_label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	_log_label.add_theme_font_size_override("bold_font_size", FONT_SIZE + 1)
	_scroll_container.add_child(_log_label)

	# Empty state label (shown when no history)
	_empty_label = Label.new()
	_empty_label.text = "No AI actions recorded yet.\nAI actions will appear here after the AI takes its turn."
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.add_theme_color_override("font_color", COLOR_EMPTY)
	_empty_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_empty_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_label.visible = false
	vbox.add_child(_empty_label)

# ── Public API ──────────────────────────────────────────────────────────

func toggle_panel() -> void:
	"""Toggle the panel visibility. Refreshes content when shown."""
	if visible:
		hide_panel()
	else:
		show_panel()

func show_panel() -> void:
	"""Show the panel and refresh its content."""
	_refresh_turn_data()
	_render_current_view()
	visible = true
	print("[AITurnReplayPanel] T7-56: Panel shown (%d turn entries)" % _turn_entries.size())

func hide_panel() -> void:
	"""Hide the panel."""
	visible = false
	print("[AITurnReplayPanel] T7-56: Panel hidden")

func refresh() -> void:
	"""Refresh the displayed data without changing visibility."""
	if visible:
		_refresh_turn_data()
		_render_current_view()

# ── Navigation ──────────────────────────────────────────────────────────

func _on_prev_turn() -> void:
	if _turn_entries.is_empty():
		return
	if _current_turn_index <= 0:
		_current_turn_index = -1  # Go to "All Turns"
	else:
		_current_turn_index -= 1
	_render_current_view()

func _on_next_turn() -> void:
	if _turn_entries.is_empty():
		return
	if _current_turn_index < _turn_entries.size() - 1:
		_current_turn_index += 1
	_render_current_view()

func _on_close_pressed() -> void:
	hide_panel()

# ── Data & Rendering ────────────────────────────────────────────────────

func _refresh_turn_data() -> void:
	"""Pull the latest turn history from AIPlayer."""
	var ai_player = Engine.get_singleton("AIPlayer") if Engine.has_singleton("AIPlayer") else null
	if not ai_player:
		# Try node path
		ai_player = _get_ai_player_node()
	if ai_player and ai_player.has_method("get_turn_history"):
		_turn_entries = ai_player.get_turn_history()
	else:
		_turn_entries = []

	# Clamp current index
	if _turn_entries.is_empty():
		_current_turn_index = -1
	elif _current_turn_index >= _turn_entries.size():
		_current_turn_index = _turn_entries.size() - 1

func _get_ai_player_node() -> Node:
	"""Get AIPlayer autoload via node tree."""
	var root = get_tree().root if get_tree() else null
	if root:
		return root.get_node_or_null("AIPlayer")
	return null

func _render_current_view() -> void:
	"""Render the action log for the current turn selection."""
	if _turn_entries.is_empty():
		_show_empty_state()
		return

	_empty_label.visible = false
	_scroll_container.visible = true
	_log_label.clear()

	# Update navigation label and button states
	_update_nav_state()

	if _current_turn_index == -1:
		# Show all turns
		_render_all_turns()
	else:
		# Show specific turn
		_render_single_turn(_current_turn_index)

	# Scroll to top
	call_deferred("_scroll_to_top")

func _show_empty_state() -> void:
	_scroll_container.visible = false
	_empty_label.visible = true
	_turn_label.text = "No AI Turns"
	_prev_button.disabled = true
	_next_button.disabled = true

func _update_nav_state() -> void:
	if _current_turn_index == -1:
		_turn_label.text = "All Turns (%d)" % _turn_entries.size()
		_prev_button.disabled = true
		_next_button.disabled = _turn_entries.is_empty()
	else:
		var entry = _turn_entries[_current_turn_index]
		var round_num = entry.get("battle_round", 1)
		var player = entry.get("player", 0)
		_turn_label.text = "Round %d - P%d (%d/%d)" % [round_num, player, _current_turn_index + 1, _turn_entries.size()]
		_prev_button.disabled = false
		_next_button.disabled = _current_turn_index >= _turn_entries.size() - 1

func _render_all_turns() -> void:
	"""Render all turns with round headers."""
	var last_round = -1
	for i in range(_turn_entries.size()):
		var entry = _turn_entries[i]
		var round_num = entry.get("battle_round", 1)

		# Round header
		if round_num != last_round:
			var round_hex = COLOR_ROUND.to_html(false)
			_log_label.append_text("\n[b][color=#%s]=== Battle Round %d ===[/color][/b]\n" % [round_hex, round_num])
			last_round = round_num

		# Turn sub-header
		var player = entry.get("player", 0)
		var player_color = COLOR_P1 if player == 1 else COLOR_P2
		var player_hex = player_color.to_html(false)
		var action_count = entry.get("actions", []).size()
		_log_label.append_text("[b][color=#%s]Player %d (%d actions)[/color][/b]\n" % [player_hex, player, action_count])

		# Actions (abbreviated in "All" view)
		_render_turn_actions(entry, true)

func _render_single_turn(index: int) -> void:
	"""Render a single turn's complete action list."""
	if index < 0 or index >= _turn_entries.size():
		return

	var entry = _turn_entries[index]
	var round_num = entry.get("battle_round", 1)
	var player = entry.get("player", 0)
	var player_color = COLOR_P1 if player == 1 else COLOR_P2
	var player_hex = player_color.to_html(false)
	var round_hex = COLOR_ROUND.to_html(false)

	_log_label.append_text("[b][color=#%s]Battle Round %d[/color][/b]\n" % [round_hex, round_num])
	_log_label.append_text("[b][color=#%s]Player %d Actions[/color][/b]\n\n" % [player_hex, player])

	_render_turn_actions(entry, false)

func _render_turn_actions(entry: Dictionary, abbreviated: bool) -> void:
	"""Render the actions for a single turn entry."""
	var actions = entry.get("actions", [])
	if actions.is_empty():
		var empty_hex = COLOR_EMPTY.to_html(false)
		_log_label.append_text("[color=#%s]  (no actions)[/color]\n" % empty_hex)
		return

	var last_phase = -1
	var rendered_count = 0
	var max_in_abbreviated = 8  # Show at most 8 actions per turn in "All" view

	for action in actions:
		var phase = action.get("phase", -1)
		var description = action.get("description", action.get("action_type", "Unknown"))
		var action_player = action.get("player", entry.get("player", 0))

		# Phase header when phase changes
		if phase != last_phase:
			var phase_name = PHASE_NAMES.get(phase, "Phase %d" % phase)
			var phase_hex = COLOR_PHASE.to_html(false)
			_log_label.append_text("  [color=#%s]-- %s --[/color]\n" % [phase_hex, phase_name])
			last_phase = phase

		# Action entry
		var color = COLOR_P1 if action_player == 1 else COLOR_P2
		var color_hex = color.to_html(false)
		_log_label.append_text("  [color=#%s]%s[/color]\n" % [color_hex, description])

		rendered_count += 1
		if abbreviated and rendered_count >= max_in_abbreviated and actions.size() > max_in_abbreviated:
			var info_hex = COLOR_INFO.to_html(false)
			var remaining = actions.size() - rendered_count
			_log_label.append_text("  [color=#%s]... +%d more actions[/color]\n" % [info_hex, remaining])
			break

	_log_label.append_text("\n")

func _scroll_to_top() -> void:
	if _scroll_container and is_instance_valid(_scroll_container):
		_scroll_container.scroll_vertical = 0
