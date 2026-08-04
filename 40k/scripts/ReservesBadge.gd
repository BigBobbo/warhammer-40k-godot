extends PanelContainer
class_name ReservesBadge

# ReservesBadge — tier 1 of the reserves UI: the always-on glance.
#
# Sits in the top bar (HUD_Bottom/HBoxContainer) and answers, without any
# input from the player, the two questions that were previously unanswerable
# mid-game: "how much does my opponent still have off-table?" and "how long
# have I got before mine die?". Clicking it opens the full detail panel.
#
# Hides itself entirely when neither player has anything in Reserves, so armies
# that deploy everything never see it.
#
# Public API for scenarios:
#   refresh()
#   get_summary_text() -> String   (flat, assertable form of what's rendered)
#   is_showing() -> bool

const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")
const _ReservesData = preload("res://scripts/ReservesData.gd")

signal badge_pressed
signal tray_toggle_requested

var _title: Label = null
var _p1_label: Label = null
var _p2_label: Label = null
var _deadline: Label = null


func _ready() -> void:
	name = "ReservesBadge"
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Units waiting in Reserves — click for the full breakdown"

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.11, 0.09, 0.9)
	style.border_color = _WhiteDwarfTheme.WH_GOLD
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	_title = _make_label("TitleLabel", "RESERVES", _WhiteDwarfTheme.WH_GOLD, 14)
	row.add_child(_title)

	_p1_label = _make_label("P1Label", "", _WhiteDwarfTheme.get_player_label_color(1), 16)
	row.add_child(_p1_label)

	_p2_label = _make_label("P2Label", "", _WhiteDwarfTheme.get_player_label_color(2), 16)
	row.add_child(_p2_label)

	_deadline = _make_label("DeadlineLabel", "", _WhiteDwarfTheme.WH_PARCHMENT, 14)
	row.add_child(_deadline)

	gui_input.connect(_on_gui_input)
	_connect_refresh_signals()
	# GameState is populated by the scene-load / save-restore path that runs
	# after _ready, so build the first render a frame later.
	call_deferred("refresh")


func _make_label(node_name: String, text: String, color: Color, font_size: int) -> Label:
	var lbl := Label.new()
	lbl.name = node_name
	lbl.text = text
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lbl


func _connect_refresh_signals() -> void:
	var pm = get_node_or_null("/root/PhaseManager")
	if pm == null:
		return
	# Reserves change on arrival (a phase action), on phase/round boundaries
	# (the round-3 destruction step, and aircraft streaking back off-table).
	for sig in ["phase_changed", "phase_action_taken", "battle_round_started", "turn_started"]:
		if pm.has_signal(sig) and not pm.is_connected(sig, _on_game_event):
			pm.connect(sig, _on_game_event)


func _on_game_event(_a = null) -> void:
	refresh()


func _on_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		# Shift-click folds the off-board rails away. The badge doubles as
		# their toggle so the top bar doesn't need a second button — it was
		# already overflowing behind the End Phase button.
		if mb.shift_pressed:
			tray_toggle_requested.emit()
		else:
			badge_pressed.emit()
		accept_event()


func is_showing() -> bool:
	return visible


func refresh() -> void:
	if _p1_label == null:
		return
	var s1 := _ReservesData.summary(1)
	var s2 := _ReservesData.summary(2)

	# Nothing off-table for either side — the badge is pure noise, so go away.
	if int(s1["count"]) == 0 and int(s2["count"]) == 0:
		visible = false
		return
	visible = true

	var viewer := _ReservesData.viewing_player()
	_p1_label.text = _segment_text(1, s1, viewer)
	_p2_label.text = _segment_text(2, s2, viewer)
	_p1_label.visible = int(s1["count"]) > 0
	_p2_label.visible = int(s2["count"]) > 0

	var battle_round := int(s1["battle_round"])
	if battle_round < _ReservesData.EARLIEST_ARRIVAL_ROUND:
		_deadline.text = "R%d+" % _ReservesData.EARLIEST_ARRIVAL_ROUND
		_deadline.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
	elif battle_round >= _ReservesData.DEADLINE_ROUND:
		# End of round 3 destroys whatever is left — this is the last chance.
		_deadline.text = "!! LAST ROUND"
		_deadline.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	else:
		_deadline.text = "by R%d" % _ReservesData.DEADLINE_ROUND
		_deadline.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)

	tooltip_text = _build_tooltip(s1, s2)


# Deliberately terse: the top bar already carries phase, CP, score, three
# toggles and the End Phase button, and an earlier long-form version
# ("P1 1 unit · 215 pts") pushed the row under the End Phase button. The
# tooltip and the panel carry the full wording.
func _segment_text(player: int, s: Dictionary, viewer: int) -> String:
	if int(s["count"]) == 0:
		return ""
	var who := "You" if player == viewer else "P%d" % player
	return "%s %d·%s" % [who, int(s["count"]), _ReservesData.format_points(int(s["points"]))]


func _build_tooltip(s1: Dictionary, s2: Dictionary) -> String:
	var lines: Array = ["Units still in Reserves:"]
	for player in [1, 2]:
		var s = s1 if player == 1 else s2
		if int(s["count"]) == 0:
			continue
		var faction = GameState.state.get("factions", {}).get(str(player), {}).get("name", "Player %d" % player)
		lines.append("")
		lines.append("Player %d — %s (%s pts)" % [player, faction, _ReservesData.format_points(int(s["points"]))])
		for e in _ReservesData.collect(player):
			lines.append("  • [%s] %s (%d models, %s pts)" % [
				e["type_short"], e["name"], int(e["models_alive"]),
				_ReservesData.format_points(int(e["points"]))])
	lines.append("")
	lines.append("Anything still in Reserves at the end of Battle Round %d is destroyed." % _ReservesData.DEADLINE_ROUND)
	lines.append("Click to open the Reserves panel (P). Shift-click hides the off-board tray.")
	return "\n".join(lines)


# Flat, assertable version of everything the badge is showing. Windowed
# scenarios read this instead of scraping four separate Label nodes.
func get_summary_text() -> String:
	if not visible:
		return ""
	var parts: Array = []
	for lbl in [_p1_label, _p2_label, _deadline]:
		if lbl != null and lbl.visible and lbl.text != "":
			parts.append(lbl.text)
	return "  ".join(parts)
