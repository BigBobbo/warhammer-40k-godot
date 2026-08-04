extends PanelContainer
class_name ReservesPanel

# ReservesPanel — tier 3 of the reserves UI: detail on demand, and the place
# you actually act from.
#
# The tray chips are deliberately terse (they have ~180px of gutter to live
# in). This is where the full picture goes: both players side by side, every
# unit with its model count, points, arrival rule and what it is carrying,
# plus the round-3 deadline spelled out.
#
# During your own Movement phase from battle round 2 it doubles as the arrival
# launcher — previously the only way to bring a unit in was a scroll box in
# HUD_Right that showed 3 of 9 reserve units at a time.
#
# Opened by the top-bar Reserves button, the badge, or the toggle_reserves_panel
# keybinding (default P). Modelled on ArmyPanel: full-screen dim + centred card,
# created on demand and freed on close.
#
# Public API for scenarios:
#   refresh()
#   get_row_texts(player) -> Array
#   get_row(player, unit_id) -> Control
#   t_activate_row(unit_id) -> bool
#   t_bring_in(unit_id) -> bool

const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")
const _ReservesData = preload("res://scripts/ReservesData.gd")

signal panel_closed
signal bring_in_requested(unit_id: String)

var _columns: Dictionary = {}      # player:int -> VBoxContainer holding rows
var _row_texts: Dictionary = {1: [], 2: []}
var _rows: Dictionary = {}         # "<player>:<unit_id>" -> Control


func _ready() -> void:
	name = "ReservesPanel"
	_build_ui()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var overlay_style := StyleBoxFlat.new()
	overlay_style.bg_color = Color(0.0, 0.0, 0.0, 0.75)
	add_theme_stylebox_override("panel", overlay_style)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(900, 560)
	_WhiteDwarfTheme.apply_to_panel(card)
	center.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "Body"
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.name = "Title"
	title.text = "RESERVES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	vbox.add_child(title)

	var deadline := Label.new()
	deadline.name = "DeadlineNote"
	deadline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	deadline.add_theme_font_size_override("font_size", 14)
	vbox.add_child(deadline)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", _WhiteDwarfTheme.WH_GOLD)
	vbox.add_child(sep)

	var cols := HBoxContainer.new()
	cols.name = "Columns"
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 12)
	vbox.add_child(cols)

	for player in [1, 2]:
		if player == 2:
			var vsep := VSeparator.new()
			vsep.add_theme_color_override("separator", _WhiteDwarfTheme.BORDER_GOLD_ACCENT)
			cols.add_child(vsep)
		cols.add_child(_build_column(player))

	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("separator", _WhiteDwarfTheme.WH_GOLD)
	vbox.add_child(sep2)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "Close (P)"
	close_btn.custom_minimum_size = Vector2(140, 36)
	_WhiteDwarfTheme.apply_to_button(close_btn)
	close_btn.pressed.connect(_on_close)
	btn_row.add_child(close_btn)

	refresh()


func _build_column(player: int) -> Control:
	var col := VBoxContainer.new()
	col.name = "Column_P%d" % player
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.name = "Header"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", _WhiteDwarfTheme.get_player_label_color(player))
	col.add_child(header)

	var totals := Label.new()
	totals.name = "Totals"
	totals.add_theme_font_size_override("font_size", 14)
	totals.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
	col.add_child(totals)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	_columns[player] = rows

	return col


func refresh() -> void:
	if _columns.is_empty():
		return
	_rows.clear()

	var battle_round := GameState.get_battle_round()
	var any_reserves := false
	for player in [1, 2]:
		any_reserves = any_reserves or not _ReservesData.collect(player).is_empty()

	var note := get_node_or_null("CenterContainer/Card/MarginContainer/Body/DeadlineNote")
	if note == null:
		# CenterContainer/PanelContainer/MarginContainer node names are
		# auto-generated; walk by type instead of guessing the path.
		note = _find_descendant("DeadlineNote")
	if note != null:
		if not any_reserves:
			note.text = "Neither army has units in Reserves."
			note.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
		elif battle_round >= _ReservesData.DEADLINE_ROUND:
			note.text = "Battle Round %d — anything still in Reserves when this round ends is DESTROYED." % battle_round
			note.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
		elif battle_round < _ReservesData.EARLIEST_ARRIVAL_ROUND:
			note.text = "Reserves cannot arrive until Battle Round %d. All must be on the battlefield by the end of Round %d." % [
				_ReservesData.EARLIEST_ARRIVAL_ROUND, _ReservesData.DEADLINE_ROUND]
			note.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
		else:
			note.text = "All Reserves must arrive by the end of Battle Round %d or they are destroyed." % _ReservesData.DEADLINE_ROUND
			note.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)

	for player in [1, 2]:
		_refresh_column(player)


func _find_descendant(node_name: String, from: Node = null) -> Node:
	var root: Node = from if from != null else self
	for child in root.get_children():
		if child.name == node_name:
			return child
		var found := _find_descendant(node_name, child)
		if found != null:
			return found
	return null


func _refresh_column(player: int) -> void:
	var rows: VBoxContainer = _columns.get(player, null)
	if rows == null:
		return
	for c in rows.get_children():
		# Detach immediately — queue_free() alone would leave the previous rows
		# in the tree for the rest of the frame, so a refresh mid-phase would
		# briefly render each unit twice.
		rows.remove_child(c)
		c.queue_free()
	_row_texts[player] = []

	var col := rows.get_parent().get_parent()
	var faction = GameState.state.get("factions", {}).get(str(player), {}).get("name", "")
	var viewer := _ReservesData.viewing_player()
	var header: Label = col.get_node_or_null("Header")
	if header != null:
		header.text = "Player %d — %s%s" % [
			player, faction if faction != "" else "Unknown", "  (YOU)" if player == viewer else ""]

	var s := _ReservesData.summary(player)
	var totals: Label = col.get_node_or_null("Totals")
	if totals != null:
		totals.text = "%d unit%s · %s pts · %d model%s in Reserves" % [
			int(s["count"]), "" if int(s["count"]) == 1 else "s",
			_ReservesData.format_points(int(s["points"])),
			int(s["models"]), "" if int(s["models"]) == 1 else "s"]

	var entries := _ReservesData.collect(player)
	if entries.is_empty():
		var empty := Label.new()
		empty.name = "EmptyNote"
		empty.text = "  Nothing in Reserves — the whole army is on the battlefield."
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		empty.add_theme_font_size_override("font_size", 14)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(empty)
		return

	var can_act := _ReservesData.can_arrive_now(player) and player == viewer
	for e in entries:
		var row := _make_row(e, can_act)
		rows.add_child(row)
		_rows["%d:%s" % [player, e["unit_id"]]] = row
		_row_texts[player].append(_row_text(e))


func _row_text(e: Dictionary) -> String:
	var txt := "[%s] %s — %d model%s · %s pts" % [
		e["type_short"], e["name"], int(e["models_alive"]),
		"" if int(e["models_alive"]) == 1 else "s",
		_ReservesData.format_points(int(e["points"]))]
	for r in e["riders"]:
		txt += " + %s" % str(r)
	for p in e["passengers"]:
		txt += " ⤷ %s" % str(p)
	return txt


func _make_row(entry: Dictionary, can_act: bool) -> PanelContainer:
	var unit_id := str(entry["unit_id"])
	var row := PanelContainer.new()
	row.name = "Row_%s" % unit_id
	row.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.13, 0.11, 0.9)
	style.border_color = entry["color"]
	style.set_border_width_all(1)
	style.border_width_left = 5
	style.set_corner_radius_all(3)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	row.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)

	var info := VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	hbox.add_child(info)

	var name_lbl := Label.new()
	name_lbl.name = "Name"
	name_lbl.text = str(entry["name"])
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.add_theme_font_size_override("font_size", 17)
	name_lbl.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
	info.add_child(name_lbl)

	var detail := Label.new()
	detail.name = "Detail"
	detail.text = "%s · %d model%s · %s pts" % [
		entry["type_label"], int(entry["models_alive"]),
		"" if int(entry["models_alive"]) == 1 else "s",
		_ReservesData.format_points(int(entry["points"]))]
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.add_theme_font_size_override("font_size", 13)
	detail.add_theme_color_override("font_color",
		Color(1.0, 0.72, 0.35) if entry["reserve_type"] == "deep_strike" else Color(0.55, 0.75, 1.0))
	info.add_child(detail)

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = str(entry["type_hint"])
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(hint)

	var extras: Array = []
	for r in entry["riders"]:
		extras.append("Led by %s" % str(r))
	for p in entry["passengers"]:
		extras.append("Carrying %s" % str(p))
	if not extras.is_empty():
		var extra_lbl := Label.new()
		extra_lbl.name = "Extras"
		extra_lbl.text = " · ".join(extras)
		extra_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		extra_lbl.add_theme_font_size_override("font_size", 12)
		extra_lbl.add_theme_color_override("font_color", Color(0.62, 0.72, 0.6))
		extra_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(extra_lbl)

	if can_act:
		var bring_btn := Button.new()
		bring_btn.name = "BringInButton"
		bring_btn.text = "Bring in ▸"
		bring_btn.custom_minimum_size = Vector2(110, 32)
		bring_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bring_btn.tooltip_text = "Start placing %s on the battlefield" % entry["name"]
		_WhiteDwarfTheme.apply_primary_button(bring_btn)
		bring_btn.pressed.connect(_on_bring_in.bind(unit_id))
		hbox.add_child(bring_btn)

	row.tooltip_text = "Click for the %s datasheet" % entry["name"]
	row.gui_input.connect(_on_row_gui_input.bind(unit_id))
	return row


func _on_row_gui_input(event: InputEvent, unit_id: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_open_datasheet(unit_id)
		accept_event()


func _open_datasheet(unit_id: String) -> void:
	var main = get_parent()
	var ds = main.get_node_or_null("DatasheetModal") if main != null else null
	if ds != null and ds.has_method("open_for"):
		ds.open_for(unit_id)


func _on_bring_in(unit_id: String) -> void:
	bring_in_requested.emit(unit_id)
	var main = get_parent()
	# Close first: the placement flow drives the board and the unit card in
	# HUD_Right, both of which are behind this overlay.
	_on_close()
	if main != null and main.has_method("_begin_reinforcement_placement"):
		DebugLogger.info("ReservesPanel: bring in %s from Reserves" % unit_id)
		main._begin_reinforcement_placement(unit_id)


func _on_close() -> void:
	panel_closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or KeybindingManager.matches_action(event, "toggle_reserves_panel"):
			_on_close()
			get_viewport().set_input_as_handled()


# --- scenario seams -------------------------------------------------------

func get_row_texts(player: int) -> Array:
	return _row_texts.get(player, []).duplicate()


func get_row(player: int, unit_id: String) -> Control:
	return _rows.get("%d:%s" % [player, unit_id], null)


func t_activate_row(unit_id: String) -> bool:
	for player in [1, 2]:
		if _rows.has("%d:%s" % [player, unit_id]):
			_open_datasheet(unit_id)
			return true
	return false


func t_bring_in(unit_id: String) -> bool:
	for player in [1, 2]:
		var row = _rows.get("%d:%s" % [player, unit_id], null)
		if row == null:
			continue
		if row.get_node_or_null("HBoxContainer/BringInButton") == null and _find_descendant("BringInButton", row) == null:
			return false
		_on_bring_in(unit_id)
		return true
	return false
