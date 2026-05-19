extends PanelContainer

# DatasheetModal — read-only full datasheet view (T39, doc §8).
#
# Bound to KEY_I from Main._input. Opens the datasheet for the
# currently-selected unit (or, for tests, an explicit unit_id passed to
# open_for). ESC dismisses.
#
# Public API:
#   open_for(unit_id) -> bool
#   close()
#   visible: bool (built-in Control prop)
#
# Self-installs as /root/Main/DatasheetModal via Main._ready(); starts
# hidden — only opened by `i` keypress or open_for() call.

const PANEL_WIDTH := 480.0
const PANEL_HEIGHT := 600.0

var _vbox: VBoxContainer = null
var current_unit_id: String = ""


func _ready() -> void:
	name = "DatasheetModal"
	visible = false  # never auto-opens
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)

	# Centered on viewport.
	set_anchors_preset(Control.PRESET_CENTER)
	_sync_position()
	var vp := get_viewport()
	if vp != null and not vp.is_connected("size_changed", _sync_position):
		vp.connect("size_changed", _sync_position)

	_vbox = VBoxContainer.new()
	_vbox.name = "Body"
	_vbox.add_theme_constant_override("separation", 6)
	add_child(_vbox)


func _sync_position() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vp_size := vp.get_visible_rect().size
	position = Vector2(
		(vp_size.x - PANEL_WIDTH) * 0.5,
		(vp_size.y - PANEL_HEIGHT) * 0.5,
	)
	size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)


func open_for(unit_id: String) -> bool:
	if unit_id == "":
		return false
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return false
	var unit = gs.get_unit(unit_id)
	if typeof(unit) != TYPE_DICTIONARY or unit.is_empty():
		return false
	current_unit_id = unit_id
	_render(unit)
	visible = true
	return true


func close() -> void:
	visible = false
	current_unit_id = ""


# T39 test seam: synthesize 'i' keypress; returns visible.
func t39_synthesize_i_press(unit_id: String = "") -> bool:
	# Use explicit unit_id if provided; otherwise fall back to selection
	# from controller autoloads.
	var id := unit_id
	if id == "":
		var m = get_parent()
		if m != null and m.has_method("_selected_unit_id_or_empty"):
			id = m._selected_unit_id_or_empty()
	if id == "":
		return false
	return open_for(id)


func t39_synthesize_escape() -> bool:
	close()
	return visible


func _render(unit: Dictionary) -> void:
	for c in _vbox.get_children():
		c.queue_free()

	var meta: Dictionary = unit.get("meta", {})
	var name_str: String = str(meta.get("name", unit.get("name", current_unit_id)))
	var title := Label.new()
	title.name = "Title"
	title.text = name_str
	title.add_theme_font_size_override("font_size", 22)
	_vbox.add_child(title)

	var stats: Dictionary = meta.get("stats", unit.get("stats", {}))
	var stats_label := Label.new()
	stats_label.name = "Stats"
	stats_label.text = _format_stats(stats)
	stats_label.add_theme_font_size_override("font_size", 14)
	_vbox.add_child(stats_label)

	var weapons_label := Label.new()
	weapons_label.name = "Weapons"
	weapons_label.text = _format_weapons(meta.get("weapons", unit.get("weapons", [])))
	weapons_label.add_theme_font_size_override("font_size", 12)
	weapons_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(weapons_label)

	var keywords_label := Label.new()
	keywords_label.name = "Keywords"
	keywords_label.text = "KEYWORDS: " + ", ".join(_to_str_array(meta.get("keywords", unit.get("keywords", []))))
	keywords_label.add_theme_font_size_override("font_size", 11)
	keywords_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(keywords_label)

	var abilities_label := Label.new()
	abilities_label.name = "Abilities"
	abilities_label.text = _format_abilities(meta.get("abilities", unit.get("abilities", [])))
	abilities_label.add_theme_font_size_override("font_size", 11)
	abilities_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(abilities_label)


func _format_stats(stats: Dictionary) -> String:
	var parts: Array = []
	# Use canonical short labels per the doc (M/T/Sv/W/Ld/OC).
	parts.append("M %s" % str(stats.get("move", "—")))
	parts.append("T %s" % str(stats.get("toughness", "—")))
	parts.append("Sv %s+" % str(stats.get("save", "—")))
	parts.append("W %s" % str(stats.get("wounds", "—")))
	parts.append("Ld %s+" % str(stats.get("leadership", "—")))
	parts.append("OC %s" % str(stats.get("objective_control", "—")))
	return "  ".join(parts)


func _format_weapons(weapons) -> String:
	if typeof(weapons) != TYPE_ARRAY or weapons.is_empty():
		return "WEAPONS: —"
	var lines: Array = ["WEAPONS:"]
	for w in weapons:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var wname: String = str(w.get("name", "?"))
		var rng: String = str(w.get("range", "?"))
		var a: String = str(w.get("attacks", "?"))
		var bs: String = str(w.get("ballistic_skill", w.get("bs", "?")))
		var s: String = str(w.get("strength", "?"))
		var ap: String = str(w.get("ap", "?"))
		var d: String = str(w.get("damage", "?"))
		lines.append("  %s — Rng %s · A %s · BS %s · S %s · AP %s · D %s" %
			[wname, rng, a, bs, s, ap, d])
	return "\n".join(lines)


func _format_abilities(abilities) -> String:
	if typeof(abilities) != TYPE_ARRAY or abilities.is_empty():
		return "ABILITIES: —"
	var lines: Array = ["ABILITIES:"]
	for ab in abilities:
		if typeof(ab) == TYPE_DICTIONARY:
			lines.append("  • %s" % str(ab.get("name", "?")))
		else:
			lines.append("  • %s" % str(ab))
	return "\n".join(lines)


func _to_str_array(arr) -> Array:
	var out: Array = []
	if typeof(arr) != TYPE_ARRAY:
		return out
	for x in arr:
		out.append(str(x))
	return out
