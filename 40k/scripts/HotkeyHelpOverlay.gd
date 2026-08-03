extends PanelContainer
class_name HotkeyHelpOverlay

# HotkeyHelpOverlay — the "Keyboard Shortcuts" card (Shift+/ or ?).
#
# 2026-08-02 reformat: this used to be a bare PanelContainer built inline in
# Main._toggle_hotkey_help_overlay() with the stock Godot theme — no card
# chrome, no section grouping, uncoloured key labels — and it listed only 15
# of the 71 registered bindings. It now renders like the datasheet card
# (DatasheetModal): gold-bordered card, header bar, tinted section headers,
# alternating rows, keycap chips, footer bar, and it sizes itself to its
# content and centres on the viewport.
#
# The list is built LIVE from KeybindingManager, so:
#   * every registered action appears (see missing_action_ids(), which the
#     windowed scenario asserts is empty), and
#   * mid-game rebinds in Settings › Controls show up the next time it opens.
# A leading "Universal & Mouse" section covers the inputs that are hardcoded
# rather than registered (Enter, Esc, the mouse buttons/wheel).
#
# Public API:
#   toggle() / open() / close()
#   missing_action_ids() -> Array   (registered actions with no rendered row)
#   shortcuts_text: String          (plain-text mirror for scenario asserts)
#   row_count: int
#
# Node names other code depends on: "PadRouteHint" (tut_t1_basics asserts on
# its exact text).

const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")

const SCREEN_MARGIN := 32.0
const MIN_PANEL_HEIGHT := 200.0
# Card width per column count. 4 columns is the 1080p case — it fits all 79
# rows without scrolling, which is the whole point of a reference card; the
# narrower tiers keep it usable down to a 1280x720 window.
const WIDTH_4_COL := 1540.0
const WIDTH_3_COL := 1180.0
const WIDTH_2_COL := 840.0
const WIDTH_1_COL := 470.0

# Rough characters-per-line in the description column, used to charge a wrapped
# row its extra height when balancing the columns. Counting rows alone put the
# four two-line "Deployment: …" rows in one column and overflowed it.
const DESC_CHARS_PER_LINE := 30

# Card palette — same dark gothic parchment as DatasheetModal / UnitStatsCardPopup.
const COL_CARD_BG := Color(0.07, 0.065, 0.05, 0.98)
const COL_HEADER_BG := Color(0.14, 0.11, 0.075, 1.0)
const COL_ROW_A := Color(0.10, 0.09, 0.07, 1.0)
const COL_ROW_B := Color(0.13, 0.115, 0.085, 1.0)
const COL_DIM := Color(0.78, 0.74, 0.66)
const COL_UNBOUND := Color(0.62, 0.58, 0.5)

# Section header tints — one per group, so the eye can find a group by colour
# the way the datasheet separates RANGED (blue) from MELEE (red).
const COL_SEC_UNIVERSAL := Color(0.16, 0.13, 0.085, 1.0)
const COL_SEC_CAMERA := Color(0.11, 0.135, 0.20, 1.0)
const COL_SEC_BOARD := Color(0.10, 0.155, 0.115, 1.0)
const COL_SEC_SAVE := Color(0.15, 0.13, 0.09, 1.0)
const COL_SEC_PHASE := Color(0.19, 0.10, 0.08, 1.0)
const COL_SEC_MODEL := Color(0.15, 0.11, 0.18, 1.0)
const COL_SEC_PANELS := Color(0.15, 0.12, 0.08, 1.0)
const COL_SEC_AI := Color(0.09, 0.16, 0.17, 1.0)
const COL_SEC_DEBUG := Color(0.18, 0.10, 0.10, 1.0)
const COL_SEC_REPLAY := Color(0.12, 0.12, 0.16, 1.0)

# Inputs that are hardcoded in Main/_input rather than registered in
# KeybindingManager — they have no rebind row in Settings, but a player still
# needs to see them, so they lead the card.
const UNIVERSAL_ENTRIES := [
	["Enter", "Advance phase / confirm action"],
	["Esc", "Settings menu / close top overlay"],
	["Left Click", "Select unit / place model"],
	["Right Click", "Unit context menu / cancel"],
	["Left Drag", "Move / Charge: drag a model"],
	["Mouse Wheel", "Zoom in / out (on cursor)"],
	["Shift + Click", "Deployment: lift a placed model"],
	["Mouse Wheel", "Deployment: rotate model 15°"],
]

# Curated grouping. KeybindingManager's own "Gameplay" category is 27 entries
# of unrelated things (measuring, save slots, shooting) — splitting it reads
# far better on a reference card. Anything NOT named here still gets rendered
# by _build_sections()'s catch-all pass, so the card cannot silently drop a
# newly-registered binding.
const SECTION_DEFS := [
	{"title": "Camera & View", "color": COL_SEC_CAMERA, "actions": [
		"camera_pan_up", "camera_pan_down", "camera_pan_left", "camera_pan_right",
		"zoom_in", "zoom_out", "rotate_board",
		"fit_view_board", "fit_view_selection", "focus_p2_zone",
	]},
	{"title": "Board & Measuring", "color": COL_SEC_BOARD, "actions": [
		"toggle_deploy_zones", "toggle_terrain", "toggle_grid_overlay",
		"toggle_unit_labels", "toggle_aura_rings",
		"measuring_tape", "clear_measurements", "ruler_tool",
		"threat_overlay", "los_check", "los_debug",
	]},
	{"title": "Model & Deployment", "color": COL_SEC_MODEL, "actions": [
		"rotate_left", "rotate_right", "undo_deployment", "select_all",
	]},
	{"title": "Phase Actions", "color": COL_SEC_PHASE, "actions": [
		"shoot_confirm_targets", "shoot_cancel_target", "shoot_cycle_eligible_unit",
		"shoot_skip_unit", "shoot_end_phase", "toggle_take_to_skies",
	]},
	{"title": "Panels & Overlays", "color": COL_SEC_PANELS, "actions": []},
	{"title": "AI", "color": COL_SEC_AI, "actions": []},
	{"title": "Replay Playback", "color": COL_SEC_REPLAY, "actions": []},
	# Ordered after the smaller blocks on purpose: the columns are split at
	# section boundaries, and putting this 12-row block next to the 14-row
	# Panels block forces one very tall column.
	{"title": "Save & Load", "color": COL_SEC_SAVE, "actions": [
		"quick_save", "quick_load",
		"save_slot_1", "save_slot_2", "save_slot_3", "save_slot_4", "save_slot_5",
		"load_slot_1", "load_slot_2", "load_slot_3", "load_slot_4", "load_slot_5",
	]},
	{"title": "Debug", "color": COL_SEC_DEBUG, "actions": []},
]

# KeybindingManager category -> the section its leftovers land in. Any category
# not listed here gets its own section appended at the end.
const CATEGORY_SECTION := {
	"Camera": "Camera & View",
	"Gameplay": "Board & Measuring",
	"Model": "Model & Deployment",
	"Panels & Overlays": "Panels & Overlays",
	"AI": "AI",
	"Debug": "Debug",
	"Replay Playback": "Replay Playback",
}

# A few registered display_names are terse to the point of being ambiguous on a
# reference card ("Sight-Line Overlay (hold)" — of what?). Only these are
# rewritten; everything else uses the registered display name verbatim so the
# card and Settings › Controls stay recognisably the same list.
const DESC_OVERRIDES := {
	"hotkey_help": "Show / hide this card",
	"shortcut_overlay": "Deployment quick-reference card",
	"los_debug": "Sight lines — green clear / red blocked (hold)",
	"los_check": "What can see the cursor position (hold)",
	"toggle_grid_overlay": "Toggle 1\" tactical grid overlay",
	"toggle_visual_style": "Cycle unit visuals (letter / enhanced)",
	"toggle_take_to_skies": "FLY: take to the skies (Movement)",
	"toggle_missions_panel": "Show secondary missions",
	"weapon_range_panel": "Weapon range comparison panel",
	"ai_suggestion": "AI suggestion + reasoning (vs AI)",
	"objective_check": "Print objective control to the game log",
	"datasheet_modal": "Open the selected unit's datasheet",
}

var _body: VBoxContainer = null
var _scroll: ScrollContainer = null
var _columns: HBoxContainer = null
var _columns_used: int = 0

# Plain-text mirror + bookkeeping (test/assert seam, same idea as
# DatasheetModal.stats_text).
var shortcuts_text: String = ""
var row_count: int = 0
var _rendered_actions: Dictionary = {}


func _ready() -> void:
	name = "HotkeyHelpOverlay"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	z_index = 2000  # above HUD panels and the board hover tooltip

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = COL_CARD_BG
	card_style.border_color = _WhiteDwarfTheme.WH_GOLD
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", card_style)

	_render()
	_fit_and_center()

	var vp := get_viewport()
	if vp != null and not vp.is_connected("size_changed", _on_viewport_resized):
		vp.connect("size_changed", _on_viewport_resized)
	print("[HotkeyHelpOverlay] Ready — %d shortcut rows across %d columns" % [row_count, _columns_used])


func open() -> void:
	visible = true
	_render()
	_fit_and_center()


func close() -> void:
	visible = false


func toggle() -> void:
	visible = not visible
	if visible:
		_render()
		_fit_and_center()
	print("[HotkeyHelpOverlay] Toggled visibility: %s" % str(visible))


## Registered actions that got no row — must stay empty (asserted by the
## hotkey_help_overlay scenario) so a new binding can never go unlisted.
func missing_action_ids() -> Array:
	var missing: Array = []
	var kbm = get_node_or_null("/root/KeybindingManager")
	if kbm == null:
		return missing
	for action_id in kbm.bindings.keys():
		if not _rendered_actions.has(action_id):
			missing.append(str(action_id))
	return missing


# ── Sizing / centring ───────────────────────────────────────────────
#
# Same approach as DatasheetModal: grow with the content up to the viewport
# minus a margin, then centre. Wrapped labels only report a correct minimum
# height once they know their width, so fit once synchronously (no flicker)
# and again after a layout pass.
func _on_viewport_resized() -> void:
	if not visible:
		return
	# A resize can change how many columns fit, so re-render, don't just re-fit.
	_render()
	_fit_and_center()


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
	var w: float = minf(_target_width(), maxf(320.0, vp_size.x - 2.0 * SCREEN_MARGIN))
	var max_h: float = maxf(MIN_PANEL_HEIGHT, vp_size.y - 2.0 * SCREEN_MARGIN)

	custom_minimum_size = Vector2(w, 0)

	_scroll.custom_minimum_size = Vector2(0, 0)
	var chrome_h := get_combined_minimum_size().y
	var content_h := _columns.get_combined_minimum_size().y if _columns != null else 0.0
	var target_h: float = clampf(chrome_h + content_h, MIN_PANEL_HEIGHT, max_h)
	_scroll.custom_minimum_size = Vector2(0, maxf(0.0, target_h - chrome_h))

	size = Vector2(w, target_h)
	position = Vector2(
		roundf((vp_size.x - w) * 0.5),
		roundf((vp_size.y - target_h) * 0.5),
	)


func _target_width() -> float:
	match _columns_used:
		4: return WIDTH_4_COL
		3: return WIDTH_3_COL
		2: return WIDTH_2_COL
		_: return WIDTH_1_COL


func _column_count_for_viewport() -> int:
	var vp := get_viewport()
	var avail: float = 1920.0 if vp == null else vp.get_visible_rect().size.x - 2.0 * SCREEN_MARGIN
	if avail >= WIDTH_4_COL:
		return 4
	if avail >= WIDTH_3_COL:
		return 3
	if avail >= WIDTH_2_COL:
		return 2
	return 1


# ── Render ──────────────────────────────────────────────────────────

func _render() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_scroll = null
	_columns = null
	row_count = 0
	_rendered_actions.clear()

	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.add_theme_constant_override("separation", 0)
	add_child(_body)

	var sections := _build_sections()
	_columns_used = _column_count_for_viewport()

	_build_header(sections)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_scroll)

	_columns = HBoxContainer.new()
	_columns.name = "Columns"
	_columns.add_theme_constant_override("separation", 10)
	_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_columns)

	_lay_out_sections(sections)
	_build_footer()


## [{title, color, rows: [[key, desc, action_id_or_empty, unbound]]}] in card order.
func _build_sections() -> Array:
	var kbm = get_node_or_null("/root/KeybindingManager")
	var sections: Array = []
	var used: Dictionary = {}

	var universal := {"title": "Universal & Mouse", "color": COL_SEC_UNIVERSAL, "rows": []}
	for e in UNIVERSAL_ENTRIES:
		universal.rows.append([str(e[0]), str(e[1]), "", false])
	sections.append(universal)

	if kbm == null:
		return sections

	# Curated sections first, in SECTION_DEFS order.
	var by_title: Dictionary = {}
	for def in SECTION_DEFS:
		var sec := {"title": str(def.title), "color": def.color, "rows": []}
		for action_id in def.actions:
			if not kbm.bindings.has(action_id):
				continue  # binding was renamed/removed — catch-all pass handles the rest
			sec.rows.append(_row_for(kbm, str(action_id)))
			used[action_id] = true
		by_title[sec.title] = sec
		sections.append(sec)

	# Catch-all: every registered action not placed above lands in the section
	# mapped to its category (creating one if the category is new). This is what
	# makes the card self-maintaining — register a binding and it shows up here.
	for category in kbm.get_categories():
		for action_id in kbm.get_actions_in_category(category):
			if used.has(action_id):
				continue
			var title: String = str(CATEGORY_SECTION.get(category, category))
			if not by_title.has(title):
				var extra := {"title": title, "color": COL_SEC_PANELS, "rows": []}
				by_title[title] = extra
				sections.append(extra)
			by_title[title].rows.append(_row_for(kbm, str(action_id)))
			used[action_id] = true

	# Anything registered under a category get_categories() doesn't list.
	for action_id in kbm.bindings.keys():
		if used.has(action_id):
			continue
		var title := "Other"
		if not by_title.has(title):
			var extra2 := {"title": title, "color": COL_SEC_PANELS, "rows": []}
			by_title[title] = extra2
			sections.append(extra2)
		by_title[title].rows.append(_row_for(kbm, str(action_id)))
		used[action_id] = true

	# Drop sections that ended up empty (e.g. a curated list whose actions were
	# all renamed) so the card never shows a header with nothing under it.
	var out: Array = []
	for s in sections:
		if not s.rows.is_empty():
			out.append(s)
	return out


func _row_for(kbm, action_id: String) -> Array:
	var b: Dictionary = kbm.get_binding(action_id)
	var unbound: bool = int(b.get("key", 0)) == 0 and int(b.get("alt_key", 0)) == 0
	var key_text: String = "Unbound" if unbound else kbm.get_key_display_name(action_id)
	var desc: String = str(DESC_OVERRIDES.get(action_id, b.get("display_name", action_id)))
	return [key_text, desc, action_id, unbound]


func _lay_out_sections(sections: Array) -> void:
	# Balance the sections across the columns by rendered LINE count (a header
	# costs roughly two lines, and a description that wraps costs an extra line
	# per wrap), filling left-to-right so the reading order is preserved down
	# each column.
	var weights: Array = []
	var total := 0
	for s in sections:
		var w := 2
		for r in s.rows:
			w += 1 + int(str(r[1]).length() / DESC_CHARS_PER_LINE)
		weights.append(w)
		total += w
	var target: float = float(total) / float(maxi(1, _columns_used))

	var assign := _column_assignment(weights, target)
	_columns_used = 0
	for a in assign:
		_columns_used = maxi(_columns_used, int(a) + 1)

	var cols: Array = []
	for i in range(_columns_used):
		var col := VBoxContainer.new()
		col.name = "Col%d" % i
		col.add_theme_constant_override("separation", 8)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_columns.add_child(col)
		cols.append(col)

	var lines: Array = []
	for i in range(sections.size()):
		var s = sections[i]
		cols[int(assign[i])].add_child(_build_section(s))
		lines.append("[%s]" % str(s.title))
		for r in s.rows:
			lines.append("  %s — %s" % [str(r[0]), str(r[1])])
	shortcuts_text = "\n".join(lines)


## Which column each section goes in. Splits the (ordered) sections into
## CONTIGUOUS runs, minimising the tallest column — binary search on the
## capacity plus a greedy feasibility check. Filling each column "up to the
## average" instead, as this did originally, overflowed column 1 at three
## columns: the average ignores that a run can only break between sections.
func _column_assignment(weights: Array, _target: float) -> Array:
	var k: int = maxi(1, mini(_columns_used, weights.size()))
	var lo := 0
	var hi := 0
	for w in weights:
		lo = maxi(lo, int(w))
		hi += int(w)
	while lo < hi:
		@warning_ignore("integer_division")
		var mid: int = (lo + hi) / 2
		if _packs_into(weights, k, mid):
			hi = mid
		else:
			lo = mid + 1

	var assign: Array = []
	var col := 0
	var acc := 0
	for i in range(weights.size()):
		var w := int(weights[i])
		# Break when the run is full, but never strand a trailing column empty —
		# an empty column would leave a visible gutter in the card.
		var must_break: bool = acc > 0 and acc + w > lo
		var sections_left: int = weights.size() - i
		var cols_left: int = k - col
		if col < k - 1 and (must_break or sections_left <= cols_left - 1):
			col += 1
			acc = 0
		assign.append(col)
		acc += w
	return assign


func _packs_into(weights: Array, k: int, cap: int) -> bool:
	var cols := 1
	var acc := 0
	for w in weights:
		if acc + int(w) > cap:
			cols += 1
			acc = 0
			if cols > k:
				return false
		acc += int(w)
	return true


func _build_section(section: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.name = "Section_" + str(section.title).replace(" ", "").replace("&", "")
	box.add_theme_constant_override("separation", 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header := PanelContainer.new()
	header.name = "Header"
	header.add_theme_stylebox_override("panel", _bar_style(section.color, 10, 3))
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 6)
	header.add_child(hrow)

	var title := Label.new()
	title.name = "Title"
	title.text = str(section.title).to_upper()
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(title)

	var count := Label.new()
	count.text = str(section.rows.size())
	count.add_theme_font_size_override("font_size", 16)
	count.add_theme_color_override("font_color", Color(_WhiteDwarfTheme.WH_GOLD, 0.55))
	hrow.add_child(count)
	box.add_child(header)

	# A 2-column grid keeps every keycap cell in the section the same width, so
	# the descriptions line up without hand-tuned pixel widths.
	var grid := GridContainer.new()
	grid.name = "Rows"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	box.add_child(grid)

	var idx := 0
	for r in section.rows:
		var bg: Color = COL_ROW_A if idx % 2 == 0 else COL_ROW_B
		idx += 1
		row_count += 1
		var action_id := str(r[2])
		if action_id != "":
			_rendered_actions[action_id] = true

		var keycap_holder := HBoxContainer.new()
		keycap_holder.alignment = BoxContainer.ALIGNMENT_END
		keycap_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		keycap_holder.add_child(_keycap(str(r[0]), bool(r[3])))
		_add_cell(grid, keycap_holder, bg, false)

		var desc := Label.new()
		desc.text = str(r[1])
		desc.add_theme_font_size_override("font_size", 16)
		desc.add_theme_color_override("font_color", COL_UNBOUND if bool(r[3]) else _WhiteDwarfTheme.WH_PARCHMENT)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_add_cell(grid, desc, bg, true)

	return box


## Key rendered as a physical keycap — a bordered chip, like the datasheet's
## stat boxes, rather than a bare word in the default font.
func _keycap(text: String, unbound: bool) -> Control:
	var cap := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.045, 0.035, 1.0) if not unbound else Color(0.07, 0.065, 0.06, 1.0)
	style.border_color = Color(_WhiteDwarfTheme.WH_GOLD, 0.20 if unbound else 0.60)
	style.set_border_width_all(1)
	style.border_width_bottom = 2 if not unbound else 1
	style.set_corner_radius_all(3)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	cap.add_theme_stylebox_override("panel", style)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", COL_UNBOUND if unbound else _WhiteDwarfTheme.WH_GOLD)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var cap_font := SystemFont.new()
	cap_font.font_weight = 600
	label.add_theme_font_override("font", cap_font)
	cap.add_child(label)
	return cap


func _add_cell(grid: GridContainer, content: Control, bg: Color, expand: bool) -> void:
	var cell := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(_WhiteDwarfTheme.WH_GOLD, 0.14)
	style.border_width_bottom = 1
	style.content_margin_left = 8 if expand else 6
	style.content_margin_right = 8 if expand else 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	cell.add_theme_stylebox_override("panel", style)
	if expand:
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_child(content)
	grid.add_child(cell)


# ── Header / footer bars ────────────────────────────────────────────

func _build_header(sections: Array) -> void:
	var bound := 0
	for s in sections:
		for r in s.rows:
			if not bool(r[3]):
				bound += 1

	var header := PanelContainer.new()
	header.name = "Header"
	header.add_theme_stylebox_override("panel", _bar_style(COL_HEADER_BG, 12, 8))
	_body.add_child(header)

	# Named containers so scenarios can address Body/Header/Col/Row/Title
	# instead of walking the tree looking for a Label.
	var col := VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override("separation", 2)
	header.add_child(col)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)

	var title := Label.new()
	title.name = "Title"
	title.text = "KEYBOARD SHORTCUTS"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)

	row.add_child(_badge("%d SHORTCUTS" % bound, _WhiteDwarfTheme.WH_BONE))
	row.add_child(_badge("%s TO CLOSE" % _help_key_display(), Color(1.0, 0.85, 0.3)))

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "Every key bound in this build, read live from your bindings — rebind any of them in Settings (Esc) › Controls."
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", COL_DIM)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(subtitle)


func _build_footer() -> void:
	var footer := PanelContainer.new()
	footer.name = "Footer"
	var style := _bar_style(COL_HEADER_BG, 12, 6)
	style.border_width_bottom = 0
	style.border_width_top = 1
	footer.add_theme_stylebox_override("panel", style)
	_body.add_child(footer)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 14)
	footer.add_child(row)

	# Controller route to the same information. This help screen is keyboard-only
	# by nature (and Shift+/ is unpressable on a Steam Deck in Game Mode), so
	# always point pad players at the Controller tab, which lists every pad
	# button and lets them remap it. Glyph comes from PadBindings so a remapped
	# Pause Menu role shows the button it is actually on now.
	var pad_hint := Label.new()
	pad_hint.name = "PadRouteHint"
	pad_hint.text = "On a controller: %s (Pause Menu) → Settings → Controller lists every pad button" % _pause_button_glyph()
	pad_hint.add_theme_font_size_override("font_size", 16)
	pad_hint.add_theme_color_override("font_color", COL_DIM)
	pad_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pad_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pad_hint)

	var close_hint := Label.new()
	close_hint.name = "CloseHint"
	close_hint.text = "%s or ESC to close" % _help_key_display()
	close_hint.add_theme_font_size_override("font_size", 16)
	close_hint.add_theme_color_override("font_color", Color(_WhiteDwarfTheme.WH_BONE, 0.8))
	row.add_child(close_hint)


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
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	badge.add_child(label)
	return badge


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


func _help_key_display() -> String:
	var kbm = get_node_or_null("/root/KeybindingManager")
	if kbm != null and kbm.bindings.has("hotkey_help"):
		return kbm.get_key_display_name("hotkey_help")
	return "Shift+/"


# Same lookup as Main._pause_button_glyph — kept here so the card can render
# standalone (scenarios instance it directly), falling back to Main's helper
# when it is parented there.
func _pause_button_glyph() -> String:
	var parent := get_parent()
	if parent != null and parent.has_method("_pause_button_glyph"):
		return str(parent._pause_button_glyph())
	var pb := get_node_or_null("/root/PadBindings")
	if pb != null and pb.has_method("button_full_name") and pb.has_method("get_button"):
		var g: String = str(pb.button_full_name(pb.get_button("pad_pause")))
		if g != "":
			return g
	return "⧉ View (Select)"
