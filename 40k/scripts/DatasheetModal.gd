extends PanelContainer
class_name DatasheetModal

# DatasheetModal — read-only full datasheet view (T39, doc §8).
#
# Bound to KEY_I from Main._input (rebindable) and to pad-Y via PadRouter.
# Opens the datasheet for the currently-selected unit (or, for tests, an
# explicit unit_id passed to open_for). ESC dismisses.
#
# Layout (2026-07 reformat): the card is laid out like a printed 40k
# datasheet — a header bar, a row of stat boxes, RANGED / MELEE weapon
# TABLES with proper columns, abilities, and a keywords footer. The card
# sizes itself to its content up to max_panel_height and is centred both
# ways on the viewport; anything taller scrolls inside the card instead of
# running off the bottom of the screen (the old build used a fixed 600px
# box that the content overflowed).
#
# Public API:
#   open_for(unit_id) -> bool
#   close()
#   visible: bool (built-in Control prop)
#
# Plain-text mirrors of each section (stats_text / weapons_text /
# keywords_text / abilities_text) are kept in sync by _render so scenarios
# can assert on content without walking the table's control tree.
#
# Self-installs as /root/Main/DatasheetModal via Main._ready(); starts
# hidden — only opened by the datasheet key / pad-Y / open_for().

const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")

const PANEL_WIDTH := 720.0
const DEFAULT_MAX_PANEL_HEIGHT := 760.0
const MIN_PANEL_HEIGHT := 200.0
const SCREEN_MARGIN := 32.0
const STAT_COL_WIDTH := 52.0

# Card palette — dark gothic parchment, matching UnitStatsCardPopup.
const COL_CARD_BG := Color(0.07, 0.065, 0.05, 0.98)
const COL_HEADER_BG := Color(0.14, 0.11, 0.075, 1.0)
const COL_STATS_BG := Color(0.16, 0.13, 0.085, 1.0)
const COL_ROW_A := Color(0.10, 0.09, 0.07, 1.0)
const COL_ROW_B := Color(0.13, 0.115, 0.085, 1.0)
const COL_RANGED_HDR := Color(0.11, 0.135, 0.20, 1.0)
const COL_MELEE_HDR := Color(0.19, 0.10, 0.08, 1.0)
const COL_ABILITY_HDR := Color(0.15, 0.12, 0.08, 1.0)
const COL_RULES := Color(0.62, 0.76, 0.95)
const COL_DIM := Color(0.78, 0.74, 0.66)

# Tallest the card may grow before its body starts scrolling. A var (not a
# const) so scenarios can shrink it and exercise the overflow path without
# needing a datasheet that happens to be 760px tall.
var max_panel_height: float = DEFAULT_MAX_PANEL_HEIGHT

var _vbox: VBoxContainer = null       # "Body" — header + stats + scroll + footer
var _scroll: ScrollContainer = null
var _sections: VBoxContainer = null   # scrolling content (weapons + abilities)
var current_unit_id: String = ""

# Plain-text mirrors, refreshed on every _render (test/assert seam).
var stats_text: String = ""
var weapons_text: String = ""
var keywords_text: String = ""
var abilities_text: String = ""


func _ready() -> void:
	name = "DatasheetModal"
	visible = false  # never auto-opens
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	# Main.UI_MODAL_Z — the card is an overlay, so it must draw above HUD
	# panels and the board hover tooltip (UI_OVERLAY_Z = 1000), which used to
	# punch through it.
	z_index = 2000

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = COL_CARD_BG
	card_style.border_color = _WhiteDwarfTheme.WH_GOLD
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", card_style)

	_vbox = VBoxContainer.new()
	_vbox.name = "Body"
	_vbox.add_theme_constant_override("separation", 0)
	add_child(_vbox)

	custom_minimum_size = Vector2(PANEL_WIDTH, 0)

	var vp := get_viewport()
	if vp != null and not vp.is_connected("size_changed", _fit_and_center):
		vp.connect("size_changed", _fit_and_center)


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
	# A board tooltip left over from the hover/click that opened the card would
	# sit behind it (Main suppresses new ones while we are visible, but it only
	# re-evaluates on mouse motion).
	var m = get_parent()
	if m != null and m.has_method("_hide_token_hover"):
		m._hide_token_hover()
	_render(unit)
	visible = true
	_fit_and_center()
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


# ── Sizing / centring ───────────────────────────────────────────────
#
# The card grows with its content up to max_panel_height (or the viewport
# minus a margin, whichever is smaller) and is then centred. Wrapped labels
# only report a correct minimum height once they know their final width, so
# the fit runs once synchronously (no flicker on open) and again after a
# layout pass has settled the wrapping.
func _fit_and_center() -> void:
	if not is_inside_tree():
		return
	_apply_fit()
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_apply_fit()


func _apply_fit() -> void:
	var vp := get_viewport()
	if vp == null or _scroll == null:
		return
	var vp_size := vp.get_visible_rect().size
	var w: float = minf(PANEL_WIDTH, maxf(320.0, vp_size.x - 2.0 * SCREEN_MARGIN))
	var max_h: float = minf(max_panel_height, maxf(MIN_PANEL_HEIGHT, vp_size.y - 2.0 * SCREEN_MARGIN))

	custom_minimum_size = Vector2(w, 0)

	# Measure the card without the scroll region, then give the scroll region
	# whatever height is left (capped) so `size` == the height we want.
	_scroll.custom_minimum_size = Vector2(0, 0)
	var chrome_h := get_combined_minimum_size().y
	var content_h := _sections.get_combined_minimum_size().y if _sections != null else 0.0
	var target_h: float = clampf(chrome_h + content_h, MIN_PANEL_HEIGHT, max_h)
	_scroll.custom_minimum_size = Vector2(0, maxf(0.0, target_h - chrome_h))

	size = Vector2(w, target_h)
	position = Vector2(
		roundf((vp_size.x - w) * 0.5),
		roundf((vp_size.y - target_h) * 0.5),
	)


# ── Render ──────────────────────────────────────────────────────────

func _render(unit: Dictionary) -> void:
	for c in _vbox.get_children():
		_vbox.remove_child(c)
		c.queue_free()
	_scroll = null
	_sections = null

	var meta: Dictionary = unit.get("meta", {})

	_build_header(unit, meta)
	_build_stats_row(meta)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vbox.add_child(_scroll)

	_sections = VBoxContainer.new()
	_sections.name = "Sections"
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.add_theme_constant_override("separation", 0)
	_scroll.add_child(_sections)

	_build_weapons(unit)
	_build_abilities(meta, unit)
	_build_footer(unit, meta)


# ── Header ──────────────────────────────────────────────────────────

func _build_header(unit: Dictionary, meta: Dictionary) -> void:
	var header := PanelContainer.new()
	header.name = "Header"
	header.add_theme_stylebox_override("panel", _bar_style(COL_HEADER_BG, 10, 8))
	_vbox.add_child(header)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	header.add_child(col)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)

	var title := Label.new()
	title.name = "Title"
	title.text = str(meta.get("name", unit.get("name", current_unit_id))).to_upper()
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)

	if meta.get("is_warlord", false) == true:
		row.add_child(_badge("WARLORD", Color(1.0, 0.85, 0.3)))

	var points := _to_int(meta.get("points", 0))
	if points > 0:
		row.add_child(_badge("%d PTS" % points, _WhiteDwarfTheme.WH_BONE))

	var enhancements := _to_str_array(meta.get("enhancements", []))
	if not enhancements.is_empty():
		var enh := Label.new()
		enh.name = "Enhancements"
		enh.text = "Enhancement: " + ", ".join(enhancements)
		enh.add_theme_font_size_override("font_size", 11)
		enh.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
		enh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(enh)


func _badge(text: String, color: Color) -> Control:
	var badge := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.045, 0.035, 1.0)
	style.border_color = Color(color, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	badge.add_theme_stylebox_override("panel", style)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", color)
	badge.add_child(label)
	return badge


# ── Stats row ───────────────────────────────────────────────────────

func _build_stats_row(meta: Dictionary) -> void:
	var stats: Dictionary = meta.get("stats", {})

	var bar := PanelContainer.new()
	bar.name = "StatsRow"
	bar.add_theme_stylebox_override("panel", _bar_style(COL_STATS_BG, 10, 6))
	_vbox.add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)

	# [key, label, suffix] — canonical short labels per the doc.
	var defs := [
		["move", "M", "\""],
		["toughness", "T", ""],
		["save", "Sv", "+"],
		["wounds", "W", ""],
		["leadership", "Ld", "+"],
		["objective_control", "OC", ""],
	]
	var text_parts: Array = []
	for d in defs:
		var raw = stats.get(d[0], null)
		var value := "—" if raw == null or str(raw) == "" else _fmt_num(raw) + str(d[2])
		row.add_child(_stat_box(str(d[1]), value, _WhiteDwarfTheme.WH_PARCHMENT))
		text_parts.append("%s %s" % [str(d[1]), value])

	# Invulnerable save / Feel No Pain get their own boxes when present —
	# they are the two numbers players most often go looking for.
	var invuln := _to_int(stats.get("invuln", stats.get("invulnerable_save", 0)))
	if invuln > 0:
		row.add_child(_stat_box("INV", "%d+" % invuln, Color(0.62, 0.78, 1.0)))
		text_parts.append("INV %d+" % invuln)
	var fnp := _to_int(stats.get("fnp", stats.get("feel_no_pain", 0)))
	if fnp > 0:
		row.add_child(_stat_box("FNP", "%d+" % fnp, Color(0.6, 0.95, 0.6)))
		text_parts.append("FNP %d+" % fnp)

	# Spacer so the boxes stay left-aligned at any card width.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	stats_text = "  ".join(text_parts)


func _stat_box(label_text: String, value_text: String, value_color: Color) -> Control:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.055, 0.045, 1.0)
	style.border_color = Color(_WhiteDwarfTheme.WH_GOLD, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 2
	style.content_margin_bottom = 3
	box.add_theme_stylebox_override("panel", style)
	box.custom_minimum_size = Vector2(STAT_COL_WIDTH, 0)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	box.add_child(col)

	var caption := Label.new()
	caption.text = label_text.to_upper()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 10)
	caption.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	col.add_child(caption)

	var value := Label.new()
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", 19)
	value.add_theme_color_override("font_color", value_color)
	col.add_child(value)

	return box


# ── Weapons ─────────────────────────────────────────────────────────

func _build_weapons(unit: Dictionary) -> void:
	# Only the weapons this unit is actually equipped with — meta.weapons is
	# the datasheet's full option MENU (a Battlewagon lists a killkannon and a
	# zzap gun it never took).
	var weapons = UnitLoadoutResolver.get_equipped_weapons(unit)
	var ranged: Array = []
	var melee: Array = []
	if typeof(weapons) == TYPE_ARRAY:
		for w in weapons:
			if typeof(w) != TYPE_DICTIONARY:
				continue
			if str(w.get("type", "")).to_lower() == "melee" or str(w.get("range", "")).to_lower() == "melee":
				melee.append(w)
			else:
				ranged.append(w)

	var lines: Array = ["WEAPONS:"]
	if ranged.is_empty() and melee.is_empty():
		var none := Label.new()
		none.name = "NoWeapons"
		none.text = "No weapons"
		none.add_theme_font_size_override("font_size", 12)
		none.add_theme_color_override("font_color", COL_DIM)
		var pad := _padded(none, 12, 6)
		pad.name = "Weapons"
		_sections.add_child(pad)
		lines.append("  —")
		weapons_text = "\n".join(lines)
		return

	if not ranged.is_empty():
		_build_weapon_table("RANGED WEAPONS", "BS", ranged, COL_RANGED_HDR, "RangedWeapons")
		for w in ranged:
			lines.append(_weapon_line(w, "BS"))
	if not melee.is_empty():
		_build_weapon_table("MELEE WEAPONS", "WS", melee, COL_MELEE_HDR, "MeleeWeapons")
		for w in melee:
			lines.append(_weapon_line(w, "WS"))
	weapons_text = "\n".join(lines)


func _build_weapon_table(title: String, skill_label: String, weapons: Array, header_color: Color, node_name: String) -> void:
	var section := VBoxContainer.new()
	section.name = node_name
	section.add_theme_constant_override("separation", 0)
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.add_child(section)

	var grid := GridContainer.new()
	grid.name = "Table"
	grid.columns = 7
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	section.add_child(grid)

	# Column header row — the section title doubles as the name column head,
	# exactly like the printed datasheet.
	_add_cell(grid, _cell_label(title, 12, _WhiteDwarfTheme.WH_GOLD, HORIZONTAL_ALIGNMENT_LEFT), header_color, true)
	for head in ["RANGE", "A", skill_label, "S", "AP", "D"]:
		_add_cell(grid, _cell_label(head, 11, _WhiteDwarfTheme.WH_GOLD, HORIZONTAL_ALIGNMENT_CENTER), header_color, false)

	var idx := 0
	for w in weapons:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var bg := COL_ROW_A if idx % 2 == 0 else COL_ROW_B
		idx += 1

		# Name cell: weapon name plus its special rules underneath.
		var name_box := VBoxContainer.new()
		name_box.add_theme_constant_override("separation", 0)
		name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var wname := Label.new()
		wname.text = str(w.get("name", "?"))
		wname.add_theme_font_size_override("font_size", 13)
		wname.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
		wname.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_box.add_child(wname)
		var rules := _format_rules(w.get("special_rules", ""))
		if rules != "":
			var rules_label := Label.new()
			rules_label.text = "[%s]" % rules
			rules_label.add_theme_font_size_override("font_size", 10)
			rules_label.add_theme_color_override("font_color", COL_RULES)
			rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			name_box.add_child(rules_label)
		_add_cell(grid, name_box, bg, true)

		var skill_key := "weapon_skill" if skill_label == "WS" else "ballistic_skill"
		var rng := str(w.get("range", "—"))
		if skill_label == "WS":
			rng = "Melee"
		elif rng != "" and rng != "—" and not rng.ends_with("\""):
			rng += "\""
		var values := [
			rng,
			_stat_or_dash(w, "attacks"),
			_skill_value(w, skill_key),
			_stat_or_dash(w, "strength"),
			_ap_value(w),
			_stat_or_dash(w, "damage"),
		]
		for v in values:
			_add_cell(grid, _cell_label(str(v), 13, _WhiteDwarfTheme.WH_BONE, HORIZONTAL_ALIGNMENT_CENTER), bg, false)


func _add_cell(grid: GridContainer, content: Control, bg: Color, expand: bool) -> void:
	var cell := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(_WhiteDwarfTheme.WH_GOLD, 0.18)
	style.border_width_bottom = 1
	style.content_margin_left = 8 if expand else 2
	style.content_margin_right = 8 if expand else 2
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	cell.add_theme_stylebox_override("panel", style)
	if expand:
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		cell.custom_minimum_size = Vector2(STAT_COL_WIDTH, 0)
	cell.add_child(content)
	grid.add_child(cell)


func _cell_label(text: String, font_size: int, color: Color, align: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _stat_or_dash(w: Dictionary, key: String) -> String:
	var s := _fmt_num(w.get(key, ""))
	return "—" if s == "" or s == "null" else s


func _skill_value(w: Dictionary, key: String) -> String:
	var s := _fmt_num(w.get(key, w.get("bs", "")))
	if s == "" or s == "null":
		return "—"
	if s.to_upper() == "N/A":
		return "N/A"
	return s if s.ends_with("+") else s + "+"


func _ap_value(w: Dictionary) -> String:
	var s := _fmt_num(w.get("ap", ""))
	if s == "" or s == "null":
		return "0"
	# Datasheets print AP as a negative modifier (0, -1, -2 …); army JSON
	# stores it either way, so normalise to the printed form.
	if s.begins_with("-") or s == "0":
		return s
	var n := int(s)
	return str(-n) if n > 0 else s


func _format_rules(raw) -> String:
	var s := str(raw).strip_edges()
	if s == "" or s == "null":
		return ""
	var parts: Array = []
	for chunk in s.split(",", false):
		var c := str(chunk).strip_edges()
		if c == "":
			continue
		parts.append(_titlecase(c))
	return ", ".join(parts)


func _titlecase(s: String) -> String:
	var out: Array = []
	for word in s.split(" ", false):
		var w := str(word)
		if w.length() == 0:
			continue
		# Leave things like "4+" and "D6" alone; capitalise real words.
		if w[0].to_upper() == w[0].to_lower():
			out.append(w)
		else:
			out.append(w.substr(0, 1).to_upper() + w.substr(1))
	return " ".join(out)


func _weapon_line(w: Dictionary, skill_label: String) -> String:
	var skill_key := "weapon_skill" if skill_label == "WS" else "ballistic_skill"
	return "  %s — Rng %s · A %s · %s %s · S %s · AP %s · D %s" % [
		str(w.get("name", "?")),
		("Melee" if skill_label == "WS" else _stat_or_dash(w, "range")),
		_stat_or_dash(w, "attacks"),
		skill_label,
		_skill_value(w, skill_key),
		_stat_or_dash(w, "strength"),
		_ap_value(w),
		_stat_or_dash(w, "damage"),
	]


# ── Abilities ───────────────────────────────────────────────────────

func _build_abilities(meta: Dictionary, unit: Dictionary) -> void:
	var abilities = meta.get("abilities", unit.get("abilities", []))
	var lines: Array = ["ABILITIES:"]
	if typeof(abilities) != TYPE_ARRAY or abilities.is_empty():
		abilities_text = "ABILITIES: —"
		return

	var section := VBoxContainer.new()
	section.name = "Abilities"
	section.add_theme_constant_override("separation", 0)
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.add_child(section)
	section.add_child(_section_header("ABILITIES", COL_ABILITY_HDR))

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	section.add_child(_padded(body, 12, 6))

	# Core / Faction abilities are one-liners on the printed sheet; datasheet
	# abilities get their full rules text.
	var core: Array = []
	var faction: Array = []
	var detailed: Array = []
	for ab in abilities:
		if typeof(ab) != TYPE_DICTIONARY:
			detailed.append({"name": str(ab)})
			continue
		match str(ab.get("type", "")):
			"Core":
				core.append(ab)
			"Faction":
				faction.append(ab)
			_:
				detailed.append(ab)

	if not core.is_empty():
		var names := _ability_names(core)
		if not names.is_empty():
			body.add_child(_kv_line("CORE", ", ".join(names)))
			lines.append("  CORE: " + ", ".join(names))
	if not faction.is_empty():
		var fnames := _ability_names(faction)
		if not fnames.is_empty():
			body.add_child(_kv_line("FACTION", ", ".join(fnames)))
			lines.append("  FACTION: " + ", ".join(fnames))

	for ab in detailed:
		var aname := str(ab.get("name", "?"))
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 1)
		body.add_child(entry)

		var name_label := Label.new()
		name_label.text = aname
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.add_child(name_label)
		lines.append("  • %s" % aname)

		var desc := str(ab.get("description", "")).strip_edges()
		if desc != "":
			var desc_label := Label.new()
			desc_label.text = desc
			desc_label.add_theme_font_size_override("font_size", 11)
			desc_label.add_theme_color_override("font_color", COL_DIM)
			desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			entry.add_child(desc_label)

	abilities_text = "\n".join(lines)


func _ability_names(abilities: Array) -> Array:
	var names: Array = []
	for ab in abilities:
		var n := str(ab.get("name", "")).strip_edges()
		if n != "" and n != "Core" and n != "Faction":
			names.append(n)
	return names


func _kv_line(key: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var key_label := Label.new()
	key_label.text = key + ":"
	key_label.add_theme_font_size_override("font_size", 11)
	key_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	row.add_child(key_label)

	var value_label := Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 11)
	value_label.add_theme_color_override("font_color", COL_DIM)
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value_label)
	return row


# ── Footer (keywords + live unit status + close hint) ───────────────

func _build_footer(unit: Dictionary, meta: Dictionary) -> void:
	var footer := PanelContainer.new()
	footer.name = "Footer"
	var style := _bar_style(COL_HEADER_BG, 10, 6)
	style.border_width_bottom = 0
	style.border_width_top = 1
	footer.add_theme_stylebox_override("panel", style)
	_vbox.add_child(footer)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	footer.add_child(col)

	var keywords := _to_str_array(meta.get("keywords", unit.get("keywords", [])))
	keywords_text = "KEYWORDS: " + (", ".join(keywords) if not keywords.is_empty() else "—")
	col.add_child(_kv_line("KEYWORDS", ", ".join(keywords) if not keywords.is_empty() else "—"))

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 14)
	col.add_child(status_row)

	var models = unit.get("models", [])
	if typeof(models) == TYPE_ARRAY and not models.is_empty():
		var alive := 0
		var cur_w := 0
		var max_w := 0
		for m in models:
			if typeof(m) != TYPE_DICTIONARY:
				continue
			var mw := maxi(1, _to_int(m.get("wounds", 1)))
			max_w += mw
			if m.get("alive", true) != false:
				alive += 1
				cur_w += _to_int(m.get("current_wounds", mw))
		var intact: bool = alive == models.size() and cur_w == max_w
		var status_color := Color(0.6, 0.9, 0.6) if intact else Color(0.92, 0.55, 0.5)
		status_row.add_child(_status_label("Models %d/%d" % [alive, models.size()], status_color))
		status_row.add_child(_status_label("Wounds %d/%d" % [cur_w, max_w], status_color))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(spacer)

	status_row.add_child(_status_label(_close_hint(), Color(_WhiteDwarfTheme.WH_BONE, 0.75)))


# Pad players close the card with Y (PadRouter._toggle_datasheet); keyboard
# players with ESC. Show whichever matches the device in hand.
func _close_hint() -> String:
	var idm = get_node_or_null("/root/InputDeviceManager")
	if idm != null and idm.has_method("is_pad_active") and idm.is_pad_active():
		return "[Y] to close"
	return "ESC to close"


func _status_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	return label


# ── Small builders ──────────────────────────────────────────────────

func _section_header(title: String, bg: Color) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bar_style(bg, 12, 4))
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	panel.add_child(label)
	return panel


func _padded(content: Control, h: int, v: int) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COL_ROW_A
	style.content_margin_left = h
	style.content_margin_right = h
	style.content_margin_top = v
	style.content_margin_bottom = v
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(content)
	return panel


func _bar_style(bg: Color, h: int, v: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(_WhiteDwarfTheme.WH_GOLD, 0.65)
	style.border_width_bottom = 1
	style.content_margin_left = h
	style.content_margin_right = h
	style.content_margin_top = v
	style.content_margin_bottom = v
	return style


# Saves round-trip every stat through JSON, so a Move of 6 comes back as the
# float 6.0 — printing that raw gave the old card its `6.0"` / `4.0+` look.
func _fmt_num(v) -> String:
	if v == null:
		return ""
	if typeof(v) == TYPE_FLOAT:
		if is_equal_approx(v, roundf(v)):
			return str(int(roundf(v)))
		return String.num(v, 2).rstrip("0").rstrip(".")
	return str(v)


func _to_int(v) -> int:
	match typeof(v):
		TYPE_INT:
			return int(v)
		TYPE_FLOAT:
			return int(v)
		TYPE_BOOL:
			return 1 if v else 0
		TYPE_STRING, TYPE_STRING_NAME:
			return int(str(v)) if str(v).is_valid_int() else 0
		_:
			return 0


func _to_str_array(arr) -> Array:
	var out: Array = []
	if typeof(arr) != TYPE_ARRAY:
		return out
	for x in arr:
		out.append(str(x))
	return out
