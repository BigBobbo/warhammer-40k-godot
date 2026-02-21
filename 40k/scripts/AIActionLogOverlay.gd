extends PanelContainer
class_name AIActionLogOverlay

# AIActionLogOverlay - Small scrolling text overlay showing real-time AI actions (T7-54)
# Anchored to the bottom-right corner. Displays AI actions as they happen, with
# color-coded entries that auto-scroll and fade out old entries after a timeout.

const WhiteDwarfThemeData = preload("res://scripts/WhiteDwarfTheme.gd")

# Layout constants
const OVERLAY_WIDTH: float = 320.0
const OVERLAY_MAX_HEIGHT: float = 200.0
const OVERLAY_MARGIN_RIGHT: float = 10.0
const OVERLAY_MARGIN_BOTTOM: float = 310.0  # Above the bottom stats panel
const FONT_SIZE: int = 11
const HEADER_FONT_SIZE: int = 12
const MAX_VISIBLE_ENTRIES: int = 30  # Max entries before trimming old ones

# Timing constants
const FADE_OUT_DELAY: float = 8.0  # Seconds before overlay fades when AI stops acting (non-spectator)
const SPECTATOR_FADE_OUT_DELAY: float = 30.0  # Longer fade delay in spectator mode
const FADE_OUT_DURATION: float = 1.5  # Duration of the fade-out animation
const SHOW_FADE_IN_DURATION: float = 0.3  # Duration of the fade-in when overlay appears

# Color constants (matching the game log panel color scheme)
const COLOR_P1_ACTION: Color = Color(0.4, 0.6, 0.85)   # Blue for Player 1
const COLOR_P2_ACTION: Color = Color(0.85, 0.4, 0.4)    # Red for Player 2
const COLOR_PHASE_HEADER: Color = Color(0.833, 0.588, 0.376)  # Gold for phase headers
const COLOR_INFO: Color = Color(0.7, 0.7, 0.7)          # Grey for info

# T7-55: Spectator summary colors
const COLOR_SUMMARY_HEADER: Color = Color(0.9, 0.78, 0.5)  # Warm gold for summary headers
const COLOR_SUMMARY_STAT: Color = Color(0.75, 0.85, 0.75)  # Light green for stats

# Internal state
var _scroll_container: ScrollContainer
var _log_label: RichTextLabel
var _header_label: Label
var _fade_tween: Tween
var _fade_timer: float = 0.0
var _is_active: bool = false  # Whether AI is currently acting
var _entry_count: int = 0
var _is_spectator_mode: bool = false  # T7-55: cached spectator mode flag

func _ready() -> void:
	_build_ui()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	print("[AIActionLogOverlay] T7-54: Ready")

func _build_ui() -> void:
	name = "AIActionLogOverlay"

	# Anchor to bottom-right corner
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -(OVERLAY_WIDTH + OVERLAY_MARGIN_RIGHT)
	offset_right = -OVERLAY_MARGIN_RIGHT
	offset_top = -(OVERLAY_MAX_HEIGHT + OVERLAY_MARGIN_BOTTOM)
	offset_bottom = -OVERLAY_MARGIN_BOTTOM

	# Dark semi-transparent background with gold accent (matching game theme)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.09, 0.82)
	style.border_width_left = 2
	style.border_width_right = 0
	style.border_width_top = 0
	style.border_width_bottom = 0
	style.border_color = Color(WhiteDwarfThemeData.WH_GOLD, 0.5)
	style.corner_radius_top_left = 4
	style.corner_radius_bottom_left = 4
	style.set_content_margin_all(6)
	add_theme_stylebox_override("panel", style)

	# Main VBox
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vbox)

	# Header label
	_header_label = Label.new()
	_header_label.text = "AI Actions"
	_header_label.add_theme_font_size_override("font_size", HEADER_FONT_SIZE)
	_header_label.add_theme_color_override("font_color", COLOR_PHASE_HEADER)
	_header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_header_label)

	# Thin separator
	var sep = HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	# Scroll container for log entries
	_scroll_container = ScrollContainer.new()
	_scroll_container.name = "LogScroll"
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_scroll_container)

	# RichTextLabel for color-coded BBCode entries
	_log_label = RichTextLabel.new()
	_log_label.name = "LogLabel"
	_log_label.bbcode_enabled = true
	_log_label.fit_content = true
	_log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_label.scroll_active = false  # We use ScrollContainer for scrolling
	_log_label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	_log_label.add_theme_font_size_override("bold_font_size", FONT_SIZE + 1)
	_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll_container.add_child(_log_label)

func _process(delta: float) -> void:
	# Handle auto-fade after AI stops acting
	if _is_active or not visible:
		return

	_fade_timer += delta
	var fade_delay = SPECTATOR_FADE_OUT_DELAY if _is_spectator_mode else FADE_OUT_DELAY
	if _fade_timer >= fade_delay and _fade_tween == null:
		_start_fade_out()

# ── Public API ────────────────────────────────────────────────────────────

func on_ai_turn_started(_player: int) -> void:
	"""Called when AI begins thinking — show the overlay and reset fade timer."""
	_is_active = true
	_fade_timer = 0.0
	_cancel_fade()

	if not visible:
		visible = true
		modulate.a = 0.0
		var tween = create_tween()
		tween.tween_property(self, "modulate:a", 1.0, SHOW_FADE_IN_DURATION)

	print("[AIActionLogOverlay] T7-54: AI turn started, overlay shown")

func on_ai_turn_ended(_player: int, _action_summary: Array) -> void:
	"""Called when AI finishes thinking — start fade-out countdown."""
	_is_active = false
	_fade_timer = 0.0
	print("[AIActionLogOverlay] T7-54: AI turn ended, fade timer started")

func add_action_entry(player: int, _action: Dictionary, description: String) -> void:
	"""Add a real-time AI action entry to the overlay."""
	if description == "":
		return

	# Show overlay if hidden (e.g., reactive stratagem during human turn)
	if not visible:
		visible = true
		modulate.a = 1.0
		_is_active = true

	# Reset fade timer on new entries
	_fade_timer = 0.0
	_cancel_fade()

	# Trim old entries if we've exceeded the limit
	_entry_count += 1
	if _entry_count > MAX_VISIBLE_ENTRIES:
		_trim_old_entries()

	# Color-code based on player
	var color_hex = ""
	if player == 1:
		color_hex = COLOR_P1_ACTION.to_html(false)
	else:
		color_hex = COLOR_P2_ACTION.to_html(false)

	# Format: "P{player}: {description}" with player color
	var bbcode = "[color=#%s]P%d: %s[/color]\n" % [color_hex, player, description]
	_log_label.append_text(bbcode)

	# Auto-scroll to bottom after appending
	_auto_scroll()

func add_phase_header(phase_name: String, round_num: int, player: int) -> void:
	"""Add a phase header separator when AI enters a new phase."""
	var color_hex = COLOR_PHASE_HEADER.to_html(false)
	var bbcode = "[b][color=#%s]── %s (Rd %d, P%d) ──[/color][/b]\n" % [color_hex, phase_name, round_num, player]
	_log_label.append_text(bbcode)
	_entry_count += 1
	_auto_scroll()

func set_spectator_mode(is_spectator: bool) -> void:
	"""T7-55: Set whether we're in spectator mode (longer fade, always visible)."""
	_is_spectator_mode = is_spectator
	print("[AIActionLogOverlay] T7-55: Spectator mode set to %s" % is_spectator)

func add_phase_summary(player: int, phase_name: String, summary: Dictionary) -> void:
	"""T7-55: Add a phase summary block showing what a player did in the completed phase."""
	if summary.is_empty():
		return

	# Show overlay if hidden
	if not visible:
		visible = true
		modulate.a = 1.0
		_is_active = true

	_fade_timer = 0.0
	_cancel_fade()

	# Build summary text
	var player_color_hex = (COLOR_P1_ACTION if player == 1 else COLOR_P2_ACTION).to_html(false)
	var header_hex = COLOR_SUMMARY_HEADER.to_html(false)
	var stat_hex = COLOR_SUMMARY_STAT.to_html(false)

	var bbcode = "[b][color=#%s]P%d %s Summary:[/color][/b]\n" % [header_hex, player, phase_name]

	# Format each stat from the summary dictionary
	var stat_lines = _format_summary_stats(summary)
	for line in stat_lines:
		bbcode += "  [color=#%s]%s[/color]\n" % [stat_hex, line]

	_log_label.append_text(bbcode)
	_entry_count += stat_lines.size() + 1
	_auto_scroll()

func _format_summary_stats(summary: Dictionary) -> Array:
	"""T7-55: Format summary dictionary into readable stat lines."""
	var lines = []

	# Define display order and labels
	var stat_labels = {
		"units_deployed": "Units deployed",
		"units_moved": "Units moved",
		"units_advanced": "Units advanced",
		"units_fell_back": "Units fell back",
		"units_stationary": "Units stationary",
		"units_shot": "Units fired",
		"charges_declared": "Charges declared",
		"units_fought": "Units fought",
		"stratagems_used": "Stratagems used",
		"units_skipped": "Units skipped",
		"reinforcements": "Reinforcements arrived"
	}

	var display_order = [
		"units_deployed", "units_moved", "units_advanced", "units_fell_back",
		"units_stationary", "reinforcements", "units_shot", "charges_declared",
		"units_fought", "stratagems_used", "units_skipped"
	]

	for key in display_order:
		if summary.has(key) and summary[key] > 0:
			var label = stat_labels.get(key, key)
			lines.append("%s: %d" % [label, summary[key]])

	# Any remaining keys not in display_order
	for key in summary:
		if key not in display_order and summary[key] > 0:
			lines.append("%s: %d" % [key, summary[key]])

	return lines

func clear_log() -> void:
	"""Clear all log entries."""
	if _log_label:
		_log_label.clear()
	_entry_count = 0

# ── Private Helpers ───────────────────────────────────────────────────────

func _auto_scroll() -> void:
	"""Scroll to the bottom of the log after the current frame processes layout."""
	if not _scroll_container:
		return
	# Defer scroll to next frame so layout is updated first
	call_deferred("_do_scroll")

func _do_scroll() -> void:
	if _scroll_container and is_instance_valid(_scroll_container):
		_scroll_container.scroll_vertical = int(_scroll_container.get_v_scroll_bar().max_value)

func _trim_old_entries() -> void:
	"""Clear and re-populate with a 'trimmed' notice when entries exceed the limit."""
	# RichTextLabel doesn't support removing individual lines easily,
	# so we clear and show a notice. New entries will continue appending.
	if _log_label:
		_log_label.clear()
		var info_hex = COLOR_INFO.to_html(false)
		_log_label.append_text("[color=#%s](older entries trimmed)[/color]\n" % info_hex)
		_entry_count = 1

func _start_fade_out() -> void:
	"""Fade out the overlay after inactivity."""
	if _fade_tween and _fade_tween.is_valid():
		return  # Already fading

	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_DURATION)
	_fade_tween.tween_callback(_on_fade_complete)

func _on_fade_complete() -> void:
	visible = false
	modulate.a = 1.0
	_fade_tween = null
	# Clear log entries when overlay fully fades — fresh for next AI turn
	clear_log()
	print("[AIActionLogOverlay] T7-54: Overlay faded out and cleared")

func _cancel_fade() -> void:
	"""Cancel any in-progress fade-out."""
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
		_fade_tween = null
		modulate.a = 1.0
