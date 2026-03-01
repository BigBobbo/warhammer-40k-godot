extends PanelContainer
class_name OpponentActionFeed

# OpponentActionFeed - Live scrolling feed showing opponent actions in real-time (P3-119)
# Anchored to the upper-right corner. Listens to GameEventLog for entries from the
# non-local player and displays them with color-coding and auto-fade.

const WhiteDwarfThemeData = preload("res://scripts/WhiteDwarfTheme.gd")

# Layout constants
const OVERLAY_WIDTH: float = 300.0
const OVERLAY_MAX_HEIGHT: float = 180.0
const OVERLAY_MARGIN_RIGHT: float = 10.0
const OVERLAY_MARGIN_TOP: float = 110.0  # Below the top HUD bar
const FONT_SIZE: int = 11
const HEADER_FONT_SIZE: int = 12
const MAX_VISIBLE_ENTRIES: int = 25

# Timing constants
const FADE_OUT_DELAY: float = 10.0  # Seconds before overlay fades when no new entries
const FADE_OUT_DURATION: float = 1.5
const SHOW_FADE_IN_DURATION: float = 0.3

# Color constants
const COLOR_P1_ACTION: Color = Color(0.4, 0.6, 0.85)   # Blue for Player 1
const COLOR_P2_ACTION: Color = Color(0.85, 0.4, 0.4)    # Red for Player 2
const COLOR_PHASE_HEADER: Color = Color(0.833, 0.588, 0.376)  # Gold
const COLOR_INFO: Color = Color(0.7, 0.7, 0.7)

# Internal state
var _scroll_container: ScrollContainer
var _log_label: RichTextLabel
var _header_label: Label
var _fade_tween: Tween
var _fade_timer: float = 0.0
var _has_entries: bool = false
var _entry_count: int = 0
var _local_player: int = 1  # Which player is "us" — opponent entries are the other player

func _ready() -> void:
	_build_ui()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Connect to GameEventLog to receive all formatted entries
	if GameEventLog:
		GameEventLog.entry_added.connect(_on_log_entry_added)

	print("[OpponentActionFeed] P3-119: Ready")

func _build_ui() -> void:
	name = "OpponentActionFeed"

	# Anchor to upper-right corner
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -(OVERLAY_WIDTH + OVERLAY_MARGIN_RIGHT)
	offset_right = -OVERLAY_MARGIN_RIGHT
	offset_top = OVERLAY_MARGIN_TOP
	offset_bottom = OVERLAY_MARGIN_TOP + OVERLAY_MAX_HEIGHT

	# Dark semi-transparent background with gold accent
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
	_header_label.text = "Opponent Actions"
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
	_scroll_container.name = "FeedScroll"
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_scroll_container)

	# RichTextLabel for color-coded BBCode entries
	_log_label = RichTextLabel.new()
	_log_label.name = "FeedLabel"
	_log_label.bbcode_enabled = true
	_log_label.fit_content = true
	_log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_label.scroll_active = false
	_log_label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	_log_label.add_theme_font_size_override("bold_font_size", FONT_SIZE + 1)
	_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll_container.add_child(_log_label)

func _process(delta: float) -> void:
	if not _has_entries or not visible:
		return

	_fade_timer += delta
	if _fade_timer >= FADE_OUT_DELAY and _fade_tween == null:
		_start_fade_out()

# ── Public API ────────────────────────────────────────────────────────────

func set_local_player(player: int) -> void:
	"""Set which player is the local (human) player. Opponent entries are the other."""
	_local_player = player
	print("[OpponentActionFeed] P3-119: Local player set to %d" % player)

func _on_log_entry_added(text: String, entry_type: String) -> void:
	"""Called when GameEventLog emits a new entry. Filter for opponent actions only."""
	# Determine if this entry is from the opponent
	var is_opponent_entry = false

	match entry_type:
		"p1_action":
			is_opponent_entry = (_local_player != 1)
		"p2_action":
			is_opponent_entry = (_local_player != 2)
		"phase_header":
			# Show phase headers when they belong to the opponent's turn
			# Phase headers contain "P1" or "P2" — check if it's the opponent's phase
			if "P%d" % (3 - _local_player) in text:
				_add_phase_header(text)
			return
		"info":
			# Show info entries (VP scoring, etc.) always
			_add_info_entry(text)
			return
		_:
			return

	if not is_opponent_entry:
		return

	_add_opponent_entry(text, entry_type)

func _add_opponent_entry(text: String, entry_type: String) -> void:
	"""Add an opponent action entry to the feed."""
	_show_overlay()

	_entry_count += 1
	if _entry_count > MAX_VISIBLE_ENTRIES:
		_trim_old_entries()

	var color_hex = ""
	if entry_type == "p1_action":
		color_hex = COLOR_P1_ACTION.to_html(false)
	else:
		color_hex = COLOR_P2_ACTION.to_html(false)

	var bbcode = "[color=#%s]%s[/color]\n" % [color_hex, text]
	_log_label.append_text(bbcode)
	_auto_scroll()

func _add_phase_header(text: String) -> void:
	"""Add a phase header to the feed."""
	_show_overlay()

	_entry_count += 1
	if _entry_count > MAX_VISIBLE_ENTRIES:
		_trim_old_entries()

	var color_hex = COLOR_PHASE_HEADER.to_html(false)
	var bbcode = "[b][color=#%s]%s[/color][/b]\n" % [color_hex, text]
	_log_label.append_text(bbcode)
	_auto_scroll()

func _add_info_entry(text: String) -> void:
	"""Add an info entry to the feed (VP scoring, mission events)."""
	_show_overlay()

	_entry_count += 1
	if _entry_count > MAX_VISIBLE_ENTRIES:
		_trim_old_entries()

	var color_hex = COLOR_INFO.to_html(false)
	var bbcode = "[color=#%s]%s[/color]\n" % [color_hex, text]
	_log_label.append_text(bbcode)
	_auto_scroll()

func clear_feed() -> void:
	"""Clear all feed entries."""
	if _log_label:
		_log_label.clear()
	_entry_count = 0
	_has_entries = false

# ── Private Helpers ───────────────────────────────────────────────────────

func _show_overlay() -> void:
	"""Show the overlay and reset fade timer."""
	_has_entries = true
	_fade_timer = 0.0
	_cancel_fade()

	if not visible:
		visible = true
		modulate.a = 0.0
		var tween = create_tween()
		tween.tween_property(self, "modulate:a", 1.0, SHOW_FADE_IN_DURATION)
	elif modulate.a < 1.0:
		_cancel_fade()
		modulate.a = 1.0

func _auto_scroll() -> void:
	"""Scroll to the bottom of the feed."""
	if not _scroll_container:
		return
	call_deferred("_do_scroll")

func _do_scroll() -> void:
	if _scroll_container and is_instance_valid(_scroll_container):
		_scroll_container.scroll_vertical = int(_scroll_container.get_v_scroll_bar().max_value)

func _trim_old_entries() -> void:
	"""Clear old entries when count exceeds the limit."""
	if _log_label:
		_log_label.clear()
		var info_hex = COLOR_INFO.to_html(false)
		_log_label.append_text("[color=#%s](older entries trimmed)[/color]\n" % info_hex)
		_entry_count = 1

func _start_fade_out() -> void:
	"""Fade out the overlay after inactivity."""
	if _fade_tween and _fade_tween.is_valid():
		return

	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_DURATION)
	_fade_tween.tween_callback(_on_fade_complete)

func _on_fade_complete() -> void:
	visible = false
	modulate.a = 1.0
	_fade_tween = null
	clear_feed()
	print("[OpponentActionFeed] P3-119: Feed faded out and cleared")

func _cancel_fade() -> void:
	"""Cancel any in-progress fade-out."""
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
		_fade_tween = null
		modulate.a = 1.0
