extends Control
class_name ReservesTray

# ReservesTray — tier 2 of the reserves UI: the "second table".
#
# On a physical table the models you are holding back sit in a tray beside the
# board where BOTH players can see them. The digital game had lost that: the
# only reserves affordance was the active player's Movement-phase unit list.
# This puts them back, as two rails in the empty gutters that flank the board.
#
# Deliberately SCREEN space, not board space. The camera zooms 0.1–3.0 and
# pans freely; a Node2D under BoardRoot would scroll and scale off the screen.
# As a Control anchored to the viewport the rails hold still, and the layout
# pass below folds them away when the board (or a narrow window) would collide
# with them, rather than drawing over the battlefield.
#
# Rails are pinned to players (P1 left, P2 right) rather than to "you"/"enemy",
# so hot-seat turn changes never swap the contents out from under the player;
# the viewer's own rail is marked YOU and given a brighter border instead.
#
# Public API for scenarios:
#   refresh()
#   toggle_visible()
#   rail_for(player) -> PanelContainer
#   visible_unit_ids_for(player) -> Array
#   is_rail_showing(player) -> bool
#   t_click_chip(unit_id) -> bool     (test seam — same path as a real click)

const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")
const _ReservesData = preload("res://scripts/ReservesData.gd")

# Below this the rail can't render a legible unit name, so it folds away and
# the badge + panel carry the information instead.
const MIN_RAIL_WIDTH := 132.0
const MAX_RAIL_WIDTH := 210.0
const GUTTER_MARGIN := 8.0
const TOP_BAR_FALLBACK := 100.0

signal chip_activated(unit_id: String, player: int)

var enabled: bool = true

var _rails: Dictionary = {}          # player:int -> PanelContainer
var _chip_boxes: Dictionary = {}     # player:int -> VBoxContainer
var _headers: Dictionary = {}        # player:int -> Dictionary of Labels
var _visible_ids: Dictionary = {1: [], 2: []}
var _wants_visible: Dictionary = {1: false, 2: false}  # has content AND tray enabled
var _last_layout: Dictionary = {}    # player:int -> Rect2 (skip no-op re-layouts)


func _ready() -> void:
	name = "ReservesTray"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The tray covers the whole viewport so it can place rails anywhere, but
	# it must never eat clicks meant for the board underneath. Only the chips
	# themselves take input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	for player in [1, 2]:
		_build_rail(player)

	_connect_refresh_signals()
	call_deferred("refresh")


func _build_rail(player: int) -> void:
	var rail := PanelContainer.new()
	rail.name = "Rail_P%d" % player
	rail.mouse_filter = Control.MOUSE_FILTER_PASS
	rail.visible = false
	add_child(rail)
	_rails[player] = rail

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	rail.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_theme_constant_override("separation", 3)
	margin.add_child(vbox)

	var title := Label.new()
	title.name = "Title"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.clip_text = true
	vbox.add_child(title)

	var totals := Label.new()
	totals.name = "Totals"
	totals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	totals.add_theme_font_size_override("font_size", 12)
	totals.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
	totals.clip_text = true
	vbox.add_child(totals)

	var timing := Label.new()
	timing.name = "Timing"
	timing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timing.add_theme_font_size_override("font_size", 11)
	timing.add_theme_color_override("font_color", Color(0.72, 0.68, 0.6))
	timing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(timing)

	_headers[player] = {"title": title, "totals": totals, "timing": timing}

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", _WhiteDwarfTheme.BORDER_GOLD_ACCENT)
	vbox.add_child(sep)

	# Long Ork reserve lists overflow the rail height; scroll rather than
	# silently truncating (a hidden reserve unit is the exact bug being fixed).
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var chips := VBoxContainer.new()
	chips.name = "Chips"
	chips.mouse_filter = Control.MOUSE_FILTER_PASS
	chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chips.add_theme_constant_override("separation", 3)
	scroll.add_child(chips)
	_chip_boxes[player] = chips


func _connect_refresh_signals() -> void:
	var pm = get_node_or_null("/root/PhaseManager")
	if pm != null:
		for sig in ["phase_changed", "phase_action_taken", "battle_round_started", "turn_started"]:
			if pm.has_signal(sig) and not pm.is_connected(sig, _on_game_event):
				pm.connect(sig, _on_game_event)
	var vp := get_viewport()
	if vp != null and not vp.is_connected("size_changed", _on_game_event):
		vp.connect("size_changed", _on_game_event)


func _on_game_event(_a = null) -> void:
	refresh()


# The board moves under the camera every frame the player pans or zooms, so
# the gutters have to be recomputed continuously. _sync_layout early-outs on
# an unchanged rect, so the steady-state cost is two Rect2 comparisons.
func _process(_delta: float) -> void:
	_sync_layout()


func toggle_visible() -> void:
	enabled = not enabled
	refresh()


func rail_for(player: int) -> PanelContainer:
	return _rails.get(player, null)


func is_rail_showing(player: int) -> bool:
	var rail = _rails.get(player, null)
	return rail != null and rail.visible


func visible_unit_ids_for(player: int) -> Array:
	return _visible_ids.get(player, []).duplicate()


func refresh() -> void:
	for player in [1, 2]:
		_refresh_rail(player)
	_last_layout.clear()
	_sync_layout()


func _refresh_rail(player: int) -> void:
	var rail: PanelContainer = _rails.get(player, null)
	if rail == null:
		return
	var entries := _ReservesData.collect(player)
	_visible_ids[player] = []

	var chips: VBoxContainer = _chip_boxes[player]
	for c in chips.get_children():
		# Detach before freeing: queue_free() leaves the node in the tree until
		# the end of the frame, and _content_height would then measure the old
		# chips plus the new ones and size the rail to roughly double.
		chips.remove_child(c)
		c.queue_free()

	# A player with nothing off-table gets no rail at all — an empty box
	# labelled "0 units" is clutter that never changes.
	if not enabled or entries.is_empty():
		_wants_visible[player] = false
		rail.visible = false
		return
	_wants_visible[player] = true

	var viewer := _ReservesData.viewing_player()
	var is_viewer := player == viewer
	_style_rail(rail, player, is_viewer)

	var faction = GameState.state.get("factions", {}).get(str(player), {}).get("name", "")
	var hdr: Dictionary = _headers[player]
	hdr["title"].text = "P%d RESERVES%s" % [player, "  (YOU)" if is_viewer else ""]
	hdr["title"].tooltip_text = "Player %d — %s" % [player, faction if faction != "" else "unknown faction"]

	var s := _ReservesData.summary(player)
	hdr["totals"].text = "%d unit%s · %s pts · %d model%s" % [
		int(s["count"]), "" if int(s["count"]) == 1 else "s",
		_ReservesData.format_points(int(s["points"])),
		int(s["models"]), "" if int(s["models"]) == 1 else "s"]

	var timing := _ReservesData.timing_text(player)
	hdr["timing"].text = timing
	hdr["timing"].add_theme_color_override("font_color",
		Color(1.0, 0.45, 0.35) if bool(s["final_call"]) else Color(0.72, 0.68, 0.6))

	var can_act := _ReservesData.can_arrive_now(player)
	for e in entries:
		_visible_ids[player].append(e["unit_id"])
		chips.add_child(_make_chip(e, player, can_act))

	# Actual visibility is settled by _place_rail, which also has to decide
	# whether the rail still fits in the gutter at the current camera zoom.


func _style_rail(rail: PanelContainer, player: int, is_viewer: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.085, 0.075, 0.93)
	style.border_color = _WhiteDwarfTheme.get_player_label_color(player)
	# The viewer's own rail gets a heavier border so "mine vs theirs" reads
	# before the text does.
	style.set_border_width_all(2 if is_viewer else 1)
	style.set_corner_radius_all(4)
	rail.add_theme_stylebox_override("panel", style)


func _make_chip(entry: Dictionary, player: int, can_act: bool) -> PanelContainer:
	var unit_id := str(entry["unit_id"])
	var chip := PanelContainer.new()
	chip.name = "Chip_%s" % unit_id
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.15, 0.13, 0.95)
	style.border_color = entry["color"]
	style.set_border_width_all(1)
	style.border_width_left = 4     # colour spine matches the on-board token
	style.set_corner_radius_all(3)
	style.content_margin_left = 6
	style.content_margin_right = 5
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 0)
	chip.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.name = "Name"
	name_lbl.text = str(entry["name"])
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(name_lbl)

	var meta_row := HBoxContainer.new()
	meta_row.name = "Meta"
	meta_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta_row.add_theme_constant_override("separation", 6)
	vbox.add_child(meta_row)

	var type_lbl := Label.new()
	type_lbl.name = "Type"
	type_lbl.text = str(entry["type_short"])
	type_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	type_lbl.add_theme_font_size_override("font_size", 11)
	# Deep Strike lands anywhere >9" away; Strategic Reserves are pinned to a
	# board edge. Different colours because they threaten very different places.
	type_lbl.add_theme_color_override("font_color",
		Color(1.0, 0.72, 0.35) if entry["reserve_type"] == "deep_strike" else Color(0.55, 0.75, 1.0))
	meta_row.add_child(type_lbl)

	var count_lbl := Label.new()
	count_lbl.name = "Count"
	count_lbl.text = "%d mdl · %s pts" % [int(entry["models_alive"]), _ReservesData.format_points(int(entry["points"]))]
	count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_lbl.add_theme_font_size_override("font_size", 11)
	count_lbl.add_theme_color_override("font_color", Color(0.68, 0.65, 0.58))
	meta_row.add_child(count_lbl)

	# Riders and passengers are off-table too — surface them so a Battlewagon
	# in reserve doesn't hide 20 Boyz.
	var extras: Array = []
	for r in entry["riders"]:
		extras.append("+ " + str(r))
	for p in entry["passengers"]:
		extras.append("⤷ " + str(p))
	if not extras.is_empty():
		var extra_lbl := Label.new()
		extra_lbl.name = "Extras"
		extra_lbl.text = "\n".join(extras)
		extra_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		extra_lbl.add_theme_font_size_override("font_size", 11)
		extra_lbl.add_theme_color_override("font_color", Color(0.62, 0.72, 0.6))
		extra_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(extra_lbl)

	var action_hint := "Click to bring in from Reserves" if can_act else "Click to open datasheet"
	chip.tooltip_text = "%s\n%s — %s\n%d models · %s pts\n\n%s" % [
		entry["name"], entry["type_label"], entry["type_hint"],
		int(entry["models_alive"]), _ReservesData.format_points(int(entry["points"])),
		action_hint]

	chip.gui_input.connect(_on_chip_gui_input.bind(unit_id, player))
	return chip


func _on_chip_gui_input(event: InputEvent, unit_id: String, player: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	_activate_chip(unit_id, player)
	accept_event()


func _activate_chip(unit_id: String, player: int) -> void:
	chip_activated.emit(unit_id, player)
	var main = get_parent()

	# Own unit, own Movement phase, round 2+: the chip IS the arrival control.
	if _ReservesData.can_arrive_now(player) and player == _ReservesData.viewing_player():
		if main != null and main.has_method("_begin_reinforcement_placement"):
			DebugLogger.info("ReservesTray: chip %s → begin reinforcement placement" % unit_id)
			main._begin_reinforcement_placement(unit_id)
			return

	# Otherwise it is an information affordance — including for every enemy
	# chip, which is the whole point of showing them.
	var ds = main.get_node_or_null("DatasheetModal") if main != null else null
	if ds != null and ds.has_method("open_for"):
		DebugLogger.info("ReservesTray: chip %s → open datasheet" % unit_id)
		ds.open_for(unit_id)


# Test seam: drives the same handler a real click reaches.
func t_click_chip(unit_id: String) -> bool:
	for player in [1, 2]:
		if unit_id in _visible_ids.get(player, []):
			_activate_chip(unit_id, player)
			return true
	return false


# ---------------------------------------------------------------------------
# Layout: fit each rail into the dead space between the side HUD panels and
# the board's rendered rect. Everything here is measured live, because the
# game log is collapsible, HUD_Right can be hidden, the window is resizable,
# and the board's on-screen size follows the camera.
# ---------------------------------------------------------------------------
func _sync_layout() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vp_size := vp.get_visible_rect().size
	var main = get_parent()
	if main == null:
		return

	var top := TOP_BAR_FALLBACK
	var top_bar = main.get_node_or_null("HUD_Bottom")   # named HUD_Bottom, anchored top
	if top_bar != null and top_bar is Control and top_bar.visible:
		top = top_bar.size.y
	top += GUTTER_MARGIN
	var bottom := vp_size.y - GUTTER_MARGIN

	# Inner edges of the permanent side panels.
	var left_edge := 0.0
	var log_panel = main.get_node_or_null("GameLogPanel")
	if log_panel != null and log_panel is Control and log_panel.visible:
		left_edge = log_panel.global_position.x + log_panel.size.x

	var right_edge := vp_size.x
	var hud_right = main.get_node_or_null("HUD_Right")
	if hud_right != null and hud_right is Control and hud_right.visible:
		right_edge = hud_right.global_position.x

	var board := _board_screen_rect(main)
	# Clamp the board rect into the free band so a zoomed-out board (which can
	# be narrower than the band) still yields sane gutters.
	var board_left: float = clamp(board.position.x, left_edge, right_edge)
	var board_right: float = clamp(board.end.x, left_edge, right_edge)

	_place_rail(1, left_edge + GUTTER_MARGIN, board_left - GUTTER_MARGIN, top, bottom)
	_place_rail(2, board_right + GUTTER_MARGIN, right_edge - GUTTER_MARGIN, top, bottom)


func _place_rail(player: int, x_from: float, x_to: float, top: float, bottom: float) -> void:
	var rail: PanelContainer = _rails.get(player, null)
	if rail == null:
		return
	# "Should this rail exist at all" (tray enabled + this player has reserves)
	# is decided by _refresh_rail; "does it fit" is decided here. They have to
	# stay separate: keying the fit check off rail.visible meant that once a
	# rail folded away for a narrow gutter, zooming back out could never bring
	# it back, because the check that would restore it was behind the same flag.
	if not _wants_visible.get(player, false):
		rail.visible = false
		return

	var width: float = x_to - x_from
	if width < MIN_RAIL_WIDTH:
		# The board has eaten the gutter (zoomed in), or the window is too
		# narrow. Fold away rather than cover the battlefield — the badge and
		# the panel still carry the information.
		rail.visible = false
		_last_layout.erase(player)
		return
	width = min(width, MAX_RAIL_WIDTH)
	rail.visible = true

	# Width first, height second: the chip labels autowrap, so their minimum
	# height is only meaningful once the rail is as wide as it is going to be.
	if absf(rail.size.x - width) > 0.5:
		rail.size.x = width

	var available: float = max(0.0, bottom - top)
	# Height follows the chip list rather than filling the gutter — a rail with
	# one unit in it should be one unit tall, not a full-height empty box.
	# Long lists cap at the gutter and scroll.
	var height: float = min(available, _content_height(player))
	var rect := Rect2(Vector2(x_from, top), Vector2(width, height))
	if _last_layout.get(player, Rect2()) == rect:
		return
	_last_layout[player] = rect
	rail.position = rect.position
	rail.size = rect.size


# Natural height of a rail: header block + every chip + separations/margins.
# Measured rather than estimated, because chip names wrap to two lines at
# narrow rail widths and a fixed per-chip guess would clip them.
func _content_height(player: int) -> float:
	var rail: PanelContainer = _rails.get(player, null)
	if rail == null:
		return 0.0
	var vbox := rail.get_node_or_null("Margin/VBox") as VBoxContainer
	if vbox == null:
		return 0.0
	var separation: float = float(vbox.get_theme_constant("separation"))
	var total := 0.0
	for child in vbox.get_children():
		if child is ScrollContainer:
			continue
		if child is Control:
			total += (child as Control).get_combined_minimum_size().y + separation
	var chips: VBoxContainer = _chip_boxes.get(player, null)
	if chips != null:
		total += chips.get_combined_minimum_size().y
	# Margin container padding (5 top + 5 bottom) plus the panel's own border.
	return total + 16.0


# Where the battlefield currently sits on screen. BoardRoot holds the Camera2D,
# so its canvas transform already carries pan and zoom.
func _board_screen_rect(main: Node) -> Rect2:
	var board_root = main.get_node_or_null("BoardRoot")
	if board_root == null or not (board_root is Node2D):
		return Rect2()
	var w := 1760.0
	var h := 2400.0
	var settings = get_node_or_null("/root/SettingsService")
	if settings != null:
		w = settings.get_board_width_px()
		h = settings.get_board_height_px()
	var xf: Transform2D = (board_root as Node2D).get_global_transform_with_canvas()
	var top_left: Vector2 = xf * Vector2.ZERO
	var bottom_right: Vector2 = xf * Vector2(w, h)
	return Rect2(top_left, bottom_right - top_left).abs()
