extends PanelContainer
class_name VisionMapPanel

# VisionMapPanel — the unit selector for VisionMapOverlay.
#
# The vision map is deliberately unit-by-unit (a multi-unit overlay is soup),
# so the tool needs an explicit "whose eyes?" picker that works in EVERY phase
# — during deployment the interesting unit is usually an ENEMY one, which the
# phase UI offers no way to select. An ItemList (not an OptionButton) so a
# single click switches units while browsing, and so windowed scenarios can
# drive it with real clicks (click_item_list).

signal close_requested

const ROW_OFF_LABEL := "— Off —"
const P1_COLOR := Color(0.45, 0.65, 1.0)
const P2_COLOR := Color(1.0, 0.45, 0.4)
const POLL_SEC := 0.5

var overlay: VisionMapOverlay = null

var unit_list: ItemList = null
var status_label: Label = null
var _poll_accum: float = 0.0
var _roster_sig: int = 0

func _ready() -> void:
	name = "VisionMapPanel"
	custom_minimum_size = Vector2(280, 0)

	# Stable node names so windowed scenarios can target children by NodePath.
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	var header := HBoxContainer.new()
	header.name = "Header"
	vbox.add_child(header)
	var title := Label.new()
	title.text = "👁 Vision Map"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "✕"
	close_btn.tooltip_text = "Close (clears the shading)"
	close_btn.pressed.connect(func(): emit_signal("close_requested"))
	header.add_child(close_btn)

	var info := Label.new()
	info.text = "Shades every spot the chosen unit can see — any range, terrain only. Pick a unit:"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 14)
	info.modulate = Color(1, 1, 1, 0.75)
	vbox.add_child(info)

	unit_list = ItemList.new()
	unit_list.name = "UnitList"
	unit_list.custom_minimum_size = Vector2(0, 300)
	unit_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	unit_list.add_theme_font_size_override("font_size", 15)
	unit_list.item_selected.connect(_on_row_selected)
	vbox.add_child(unit_list)

	_add_legend_row(vbox, VisionMapOverlay.COLOR_VISIBLE, "Seen by the unit")
	_add_legend_row(vbox, VisionMapOverlay.COLOR_HIDDEN, "Hidden from the unit")

	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.text = "Off — pick a unit"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(status_label)

	var footnote := Label.new()
	footnote.text = "Cell precision 1\"; a base edge can peek past a corner from the last hidden cell."
	footnote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footnote.add_theme_font_size_override("font_size", 12)
	footnote.modulate = Color(1, 1, 1, 0.5)
	vbox.add_child(footnote)

	rebuild_unit_list()

func _add_legend_row(vbox: VBoxContainer, color: Color, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var swatch := ColorRect.new()
	# Legend swatches show the wash at full readability, not board alpha.
	swatch.color = Color(color.r, color.g, color.b, 0.85)
	swatch.custom_minimum_size = Vector2(18, 18)
	row.add_child(swatch)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	row.add_child(lbl)
	vbox.add_child(row)

func _process(delta: float) -> void:
	if not visible:
		return
	_poll_accum += delta
	if _poll_accum < POLL_SEC:
		_update_status()
		return
	_poll_accum = 0.0
	var sig := _compute_roster_sig()
	if sig != _roster_sig:
		rebuild_unit_list()
	_update_status()

# ── unit roster ──

## Units that have vision to map: at least one alive model actually standing on
## the board (undeployed, reserves and embarked units see nothing yet).
func _on_board_units() -> Array:
	var rows: Array = []
	var units: Dictionary = GameState.state.get("units", {})
	for uid in units:
		var u = units[uid]
		if typeof(u) != TYPE_DICTIONARY:
			continue
		var status := int(u.get("status", 0))
		if status == GameStateData.UnitStatus.UNDEPLOYED or status == GameStateData.UnitStatus.IN_RESERVES:
			continue
		if u.get("embarked_in", null) != null:
			continue
		var positioned := false
		for m in u.get("models", []):
			if typeof(m) != TYPE_DICTIONARY or not m.get("alive", true):
				continue
			if VisionMapOverlay._model_pos(m) != Vector2.ZERO:
				positioned = true
				break
		if not positioned:
			continue
		rows.append({
			"uid": str(uid),
			"owner": int(u.get("owner", 0)),
			"name": str(u.get("meta", {}).get("name", uid)),
		})
	rows.sort_custom(func(a, b):
		if a.owner != b.owner:
			return a.owner < b.owner
		if a.name != b.name:
			return a.name < b.name
		return a.uid < b.uid)
	return rows

func _compute_roster_sig() -> int:
	var parts: Array = []
	for row in _on_board_units():
		parts.append(row.uid)
	return hash(parts)

func rebuild_unit_list() -> void:
	var rows := _on_board_units()
	_roster_sig = _compute_roster_sig()
	unit_list.clear()
	unit_list.add_item(ROW_OFF_LABEL)
	unit_list.set_item_metadata(0, "")
	var selected_idx := 0
	for row in rows:
		var idx := unit_list.add_item("P%d · %s" % [row.owner, row.name])
		unit_list.set_item_metadata(idx, row.uid)
		unit_list.set_item_custom_fg_color(idx, P1_COLOR if row.owner == 1 else P2_COLOR)
		if overlay and overlay.source_unit_id == row.uid:
			selected_idx = idx
	unit_list.select(selected_idx)
	# The overlay may be shading a unit that just left the board (died/undo) —
	# selection falls back to Off, and the overlay clears itself via its own
	# signature poll; nothing to force here.

func _on_row_selected(idx: int) -> void:
	if overlay == null:
		return
	var uid := str(unit_list.get_item_metadata(idx))
	if uid == "":
		overlay.clear_map()
	else:
		overlay.show_for_unit(uid)
	_update_status()

# ── status line ──

func _update_status() -> void:
	if overlay == null or not overlay.is_active():
		status_label.text = "Off — pick a unit"
		return
	if overlay.status_reason() != "":
		status_label.text = overlay.status_reason()
		return
	if not overlay.is_compute_done():
		status_label.text = "Mapping vision… %d%%" % int(overlay.compute_progress() * 100.0)
		return
	status_label.text = "%d\" cells seen: %d · hidden: %d" % [
		int(VisionMapOverlay.CELL_INCHES), overlay.visible_cell_count(), overlay.hidden_cell_count()]
