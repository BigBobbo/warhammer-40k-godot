extends AcceptDialog

# ShootingPhaseSummaryDialog - T5-UX9: Shooting summary before ending phase
#
# Shows aggregated total shots / hits / wounds / saves-failed / casualties per
# target unit, plus phase-wide totals, before the player ends the Shooting
# phase.
#
# LAYOUT (2026-08-01): the panel used to be a stack of indented Labels reading
# "1 hits  |  1 wounds  |  0 failed saves  |  0 casualties" per target — a text
# blob with nothing to scan down. It is now built like a battle-report table:
#
#   SHOOTING PHASE SUMMARY                       (gold headline bar)
#   "4 models slain across 3 enemy units"        (plain-English verdict)
#   3 units shot · 5 weapon resolutions          (context line)
#   ┌ 12 ─┬ 7 ──┬ 5 ─────┬ 4 ───┐                (KPI strip)
#   │SHOTS│HITS │WOUNDS  │SLAIN │
#   Target            Shots Hits Wounds Failed Slain   (zebra table)
#   Witchseekers        6     3     2      2     2
#     Big shoota — Battlewagon Alpha
#   ...
#   TOTAL              12     7     5      2     4
#
# The numbers all live in right-aligned columns so the eye runs straight down
# a stat instead of re-reading a sentence per row, casualties are the accent
# colour (the one number a player actually acts on), and the per-weapon
# drill-down is demoted to a dim sub-line under the target name.
#
# Data shape consumed (as produced by ShootingPhase.get_phase_shooting_summary):
#   {
#     "by_target": { tid: { target_unit_name, hits, total_attacks, wounds,
#                           saves_failed, casualties, shooters: [name,...] } },
#     "totals":     { hits, total_attacks, wounds, saves_failed, casualties },
#     "shooters_count": int,
#     "targets_count":  int,
#     "weapon_entries": int,
#     "raw_entries":    Array
#   }

signal shooting_confirmed()
signal shooting_cancelled()

var summary_data: Dictionary = {}

# Table geometry. The target column flexes; every stat column is the same fixed
# width so the digits line up in a true column even across rows of wildly
# different name lengths.
const _COL_TITLES := ["Target", "Shots", "Hits", "Wounds", "Failed saves", "Slain"]
const _NAME_COL_MIN := 210.0
const _STAT_COL_MIN := 78.0

# Row tints. Kept low-alpha so the zebra reads as banding, not as boxes.
const _ROW_TINT_EVEN := Color(1.0, 1.0, 1.0, 0.035)
const _ROW_TINT_ODD := Color(0.0, 0.0, 0.0, 0.0)
const _ROW_TINT_KILLS := Color(0.62, 0.10, 0.10, 0.20)
const _HEAD_BG := Color(0.17, 0.14, 0.09, 1.0)

# Number colours: casualties are the one stat a player acts on, so they get the
# accent; a zero in any column drops to a dim ink so the eye skips it.
const _INK := Color(0.922, 0.882, 0.780)   # WH_PARCHMENT
const _INK_DIM := Color(0.56, 0.53, 0.47)
const _INK_KILL := Color(1.0, 0.45, 0.42)

func setup(p_summary_data: Dictionary) -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	# apply_to_dialog styles the Window frame but never the AcceptDialog's own
	# `panel`, so the body of this dialog rendered in Godot's default washed
	# grey — the single biggest reason it read as "not part of this game" next
	# to the near-black/gold panels everywhere else. Paint it with the shared
	# White Dwarf panel chrome.
	var body = WhiteDwarfTheme.create_panel_style()
	body.bg_color = Color(0.1, 0.09, 0.07, 0.98)
	body.set_border_width_all(0)
	body.set_content_margin_all(12)
	add_theme_stylebox_override("panel", body)
	summary_data = p_summary_data

	title = "Shooting Phase Summary"

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	# Width is fixed (six columns need the room); height is left to the content
	# so a two-target phase doesn't open a half-empty 500px panel and a
	# ten-target one still scrolls instead of overflowing.
	min_size = Vector2(DialogConstants.LARGE.x, 0)
	var main_container = VBoxContainer.new()
	main_container.name = "Content"
	main_container.add_theme_constant_override("separation", 8)
	main_container.custom_minimum_size = Vector2(DialogConstants.LARGE.x - 20, 0)

	# Header
	var header = Label.new()
	header.name = "Title"
	header.text = "SHOOTING PHASE SUMMARY"
	header.add_theme_font_size_override("font_size", 23)
	header.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	_add_gold_rule(main_container)

	var by_target = summary_data.get("by_target", {})
	var totals = summary_data.get("totals", {})
	var shooters_count = int(summary_data.get("shooters_count", 0))
	var targets_count = int(summary_data.get("targets_count", 0))
	var weapon_entries = int(summary_data.get("weapon_entries", 0))

	if weapon_entries == 0 or targets_count == 0:
		_build_empty_state(main_container)
	else:
		_build_headline(main_container, totals, shooters_count, targets_count, weapon_entries)
		_build_kpi_strip(main_container, totals)
		_build_target_table(main_container, by_target, totals)

	_add_gold_rule(main_container)

	# Buttons
	var button_container = HBoxContainer.new()
	button_container.name = "Actions"
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_theme_constant_override("separation", 20)

	var cancel_button = Button.new()
	cancel_button.name = "GoBackButton"
	cancel_button.text = "Go Back"
	cancel_button.custom_minimum_size = Vector2(150, 40)
	cancel_button.pressed.connect(_on_cancel_pressed)
	button_container.add_child(cancel_button)

	var confirm_button = Button.new()
	confirm_button.name = "ConfirmEndShooting"
	confirm_button.text = "End Shooting Phase"
	confirm_button.custom_minimum_size = Vector2(200, 40)
	confirm_button.add_theme_color_override("font_color", Color.GREEN)
	confirm_button.pressed.connect(_on_confirm_pressed)
	button_container.add_child(confirm_button)

	main_container.add_child(button_container)

	add_child(main_container)

# ---------------------------------------------------------------------------
# Sections
# ---------------------------------------------------------------------------

func _build_empty_state(parent: VBoxContainer) -> void:
	var empty_label = Label.new()
	empty_label.name = "EmptyState"
	empty_label.text = "No shooting was resolved this phase."
	empty_label.add_theme_font_size_override("font_size", 18)
	empty_label.add_theme_color_override("font_color", _INK_DIM)
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(empty_label)

# The verdict line: what the phase actually achieved, in a sentence a player
# reads once. Casualties lead because that is the number the next decision
# (charge? move on?) hangs off.
func _build_headline(parent: VBoxContainer, totals: Dictionary, shooters_count: int, targets_count: int, weapon_entries: int) -> void:
	var casualties = int(totals.get("casualties", 0))

	var headline = Label.new()
	headline.name = "Headline"
	if casualties > 0:
		headline.text = "%s slain across %s" % [
			_plural(casualties, "model", "models"),
			_plural(targets_count, "enemy unit", "enemy units")]
		headline.add_theme_color_override("font_color", _INK_KILL)
	else:
		headline.text = "No models slain — %s under fire" % _plural(targets_count, "enemy unit", "enemy units")
		headline.add_theme_color_override("font_color", _INK)
	headline.add_theme_font_size_override("font_size", 20)
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(headline)

	var subhead = Label.new()
	subhead.name = "Subhead"
	subhead.text = "%s shot · %s" % [
		_plural(shooters_count, "unit", "units"),
		_plural(weapon_entries, "weapon resolution", "weapon resolutions")]
	subhead.add_theme_font_size_override("font_size", 15)
	subhead.add_theme_color_override("font_color", _INK_DIM)
	subhead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(subhead)

# Four big numbers across the top: the whole phase at a glance, before the eye
# ever reaches the per-target rows.
func _build_kpi_strip(parent: VBoxContainer, totals: Dictionary) -> void:
	var strip = HBoxContainer.new()
	strip.name = "KPIStrip"
	strip.add_theme_constant_override("separation", 8)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(strip)

	_add_kpi_tile(strip, "Shots", int(totals.get("total_attacks", 0)), false)
	_add_kpi_tile(strip, "Hits", int(totals.get("hits", 0)), false)
	_add_kpi_tile(strip, "Wounds", int(totals.get("wounds", 0)), false)
	_add_kpi_tile(strip, "Slain", int(totals.get("casualties", 0)), true)

func _add_kpi_tile(strip: HBoxContainer, caption: String, value: int, is_accent: bool) -> void:
	var tile = PanelContainer.new()
	tile.name = "KPI_%s" % caption
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.12, 0.09, 1.0)
	style.border_color = Color(WhiteDwarfTheme.WH_GOLD, 0.55 if (is_accent and value > 0) else 0.28)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(8)
	tile.add_theme_stylebox_override("panel", style)
	strip.add_child(tile)

	var box = VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 0)
	tile.add_child(box)

	var number = Label.new()
	number.name = "Value"
	number.text = str(value)
	number.add_theme_font_size_override("font_size", 28)
	if is_accent and value > 0:
		number.add_theme_color_override("font_color", _INK_KILL)
	elif value > 0:
		number.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	else:
		number.add_theme_color_override("font_color", _INK_DIM)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(number)

	var cap = Label.new()
	cap.name = "Caption"
	cap.text = caption.to_upper()
	cap.add_theme_font_size_override("font_size", 13)
	cap.add_theme_color_override("font_color", _INK_DIM)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cap)

# The table proper. One GridContainer, six columns, every row exactly six cells
# so the columns cannot drift: header row, one row per target unit (most
# casualties first), then a TOTAL row.
func _build_target_table(parent: VBoxContainer, by_target: Dictionary, totals: Dictionary) -> void:
	# Size the viewport to the rows we actually have (up to a cap) so a
	# two-target phase doesn't leave a dead band under the table and a
	# ten-target one scrolls instead of pushing the buttons off-screen.
	var wanted_h: float = 38.0 + float(by_target.size()) * 52.0 + 42.0
	var scroll = ScrollContainer.new()
	scroll.name = "TargetScroll"
	scroll.custom_minimum_size = Vector2(DialogConstants.LARGE.x - 40, clampf(wanted_h, 110.0, 280.0))
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)

	var table = GridContainer.new()
	table.name = "TargetTable"
	table.columns = _COL_TITLES.size()
	# Zero separation: each cell paints its own background, so the row tint
	# reads as one continuous band rather than six detached chips.
	table.add_theme_constant_override("h_separation", 0)
	table.add_theme_constant_override("v_separation", 0)
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(table)

	_add_header_row(table)

	# Stable display order: targets with most casualties first, then most
	# wounds, then name — the worst-hit unit is always the top row.
	var ordered_keys = by_target.keys()
	ordered_keys.sort_custom(func(a, b):
		var ba = by_target[a]
		var bb = by_target[b]
		if int(ba.casualties) != int(bb.casualties):
			return int(ba.casualties) > int(bb.casualties)
		if int(ba.wounds) != int(bb.wounds):
			return int(ba.wounds) > int(bb.wounds)
		return String(ba.target_unit_name) < String(bb.target_unit_name)
	)

	var row_index := 0
	for tid in ordered_keys:
		var bucket = by_target[tid]
		_add_target_row(table, tid, bucket, row_index)
		row_index += 1

	_add_totals_row(table, totals)

func _add_header_row(table: GridContainer) -> void:
	for i in range(_COL_TITLES.size()):
		var cell = _make_cell(_row_style("header"))
		var label = Label.new()
		label.name = "HeaderCell%d" % i
		label.text = _COL_TITLES[i]
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i == 0:
			label.custom_minimum_size = Vector2(_NAME_COL_MIN, 0)
		else:
			label.custom_minimum_size = Vector2(_STAT_COL_MIN, 0)
		cell.add_child(label)
		table.add_child(cell)

func _add_target_row(table: GridContainer, tid: String, bucket: Dictionary, row_index: int) -> void:
	var target_name = _display_name(tid, str(bucket.get("target_unit_name", tid)))
	var shots = int(bucket.get("total_attacks", 0))
	var hits = int(bucket.get("hits", 0))
	var wounds = int(bucket.get("wounds", 0))
	var saves_failed = int(bucket.get("saves_failed", 0))
	var casualties = int(bucket.get("casualties", 0))

	var kind := "kills" if casualties > 0 else ("even" if row_index % 2 == 0 else "odd")
	var style = _row_style(kind)

	# Column 0: the unit name plus a dim drill-down of which weapon (and which
	# shooter) actually did the work. Nested in the cell so the row still
	# occupies exactly one grid row.
	var name_cell = _make_cell(style)
	var name_box = VBoxContainer.new()
	name_box.name = "Name"
	name_box.add_theme_constant_override("separation", 1)
	name_box.custom_minimum_size = Vector2(_NAME_COL_MIN, 0)
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_cell.add_child(name_box)

	var name_label = Label.new()
	name_label.name = "TargetName"
	name_label.text = str(target_name)
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", _INK_KILL if casualties > 0 else _INK)
	name_box.add_child(name_label)

	for detail in _detail_lines(tid, bucket):
		var detail_label = Label.new()
		detail_label.text = detail
		detail_label.add_theme_font_size_override("font_size", 13)
		detail_label.add_theme_color_override("font_color", _INK_DIM)
		name_box.add_child(detail_label)

	table.add_child(name_cell)

	_add_stat_cell(table, style, shots, false)
	_add_stat_cell(table, style, hits, false)
	_add_stat_cell(table, style, wounds, false)
	_add_stat_cell(table, style, saves_failed, false)
	_add_stat_cell(table, style, casualties, true)

func _add_totals_row(table: GridContainer, totals: Dictionary) -> void:
	var style = _row_style("totals")

	var label_cell = _make_cell(style)
	var label = Label.new()
	label.name = "TotalsLabel"
	label.text = "TOTAL"
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	label.custom_minimum_size = Vector2(_NAME_COL_MIN, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_cell.add_child(label)
	table.add_child(label_cell)

	_add_stat_cell(table, style, int(totals.get("total_attacks", 0)), false, 17)
	_add_stat_cell(table, style, int(totals.get("hits", 0)), false, 17)
	_add_stat_cell(table, style, int(totals.get("wounds", 0)), false, 17)
	_add_stat_cell(table, style, int(totals.get("saves_failed", 0)), false, 17)
	_add_stat_cell(table, style, int(totals.get("casualties", 0)), true, 17)

# ---------------------------------------------------------------------------
# Cell helpers
# ---------------------------------------------------------------------------

func _make_cell(style: StyleBoxFlat) -> PanelContainer:
	var cell = PanelContainer.new()
	cell.add_theme_stylebox_override("panel", style)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return cell

func _add_stat_cell(table: GridContainer, style: StyleBoxFlat, value: int, is_accent: bool, font_size: int = 17) -> void:
	var cell = _make_cell(style)
	var label = Label.new()
	label.text = str(value)
	label.add_theme_font_size_override("font_size", font_size)
	if value == 0:
		label.add_theme_color_override("font_color", _INK_DIM)
	elif is_accent:
		label.add_theme_color_override("font_color", _INK_KILL)
	else:
		label.add_theme_color_override("font_color", _INK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.custom_minimum_size = Vector2(_STAT_COL_MIN, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_child(label)
	table.add_child(cell)

func _row_style(kind: String) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	match kind:
		"header":
			style.bg_color = _HEAD_BG
			style.border_color = Color(WhiteDwarfTheme.WH_GOLD, 0.5)
			style.border_width_bottom = 2
		"totals":
			style.bg_color = _HEAD_BG
			style.border_color = Color(WhiteDwarfTheme.WH_GOLD, 0.5)
			style.border_width_top = 2
		"kills":
			style.bg_color = _ROW_TINT_KILLS
		"even":
			style.bg_color = _ROW_TINT_EVEN
		_:
			style.bg_color = _ROW_TINT_ODD
	return style

# Which weapons hit this target, and from whom. One line per weapon when the
# target was shot by more than one; otherwise a single "Weapon — Shooter" line,
# so the common case stays a one-liner instead of a bulleted list of one.
func _detail_lines(tid: String, bucket: Dictionary) -> Array:
	var lines: Array = []
	var raw_entries = summary_data.get("raw_entries", [])
	for re in raw_entries:
		if re.get("target_unit_id", "") != tid:
			continue
		var weapon_name = str(re.get("weapon_name", "?"))
		var shooter = _display_name(str(re.get("shooter_unit_id", "")), str(re.get("shooter_unit_name", "")))
		var line = weapon_name if shooter == "" else "%s — %s" % [weapon_name, shooter]
		if line not in lines:
			lines.append(line)
	if lines.is_empty():
		var shooters = bucket.get("shooters", [])
		if not shooters.is_empty():
			lines.append("Shot by %s" % ", ".join(shooters))
	return lines

# The phase log stores meta.name, so two Boyz mobs both render as "Boyz" and a
# player cannot tell which one he just gutted. Everywhere else in the game (the
# resolution dock, the unit list) prefers meta.display_name — resolve the same
# way here, falling back to whatever the log captured if the unit is gone.
func _display_name(unit_id: String, fallback: String) -> String:
	if unit_id == "":
		return fallback
	var unit = GameState.get_unit(unit_id)
	if unit == null or unit.is_empty():
		# Wiped units can leave the state entirely — keep whatever the phase log
		# captured rather than falling back to a raw unit id.
		return fallback
	return GameState.get_unit_display_name(unit_id)

func _add_gold_rule(parent: Control) -> void:
	var rule = ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 2)
	rule.color = Color(WhiteDwarfTheme.WH_GOLD, 0.4)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(rule)

func _plural(count: int, singular: String, plural: String) -> String:
	return "%d %s" % [count, singular if count == 1 else plural]

# ---------------------------------------------------------------------------
# Buttons
# ---------------------------------------------------------------------------

func _on_confirm_pressed() -> void:
	print("ShootingPhaseSummaryDialog: Player confirmed ending shooting phase")
	emit_signal("shooting_confirmed")
	hide()
	queue_free()

func _on_cancel_pressed() -> void:
	print("ShootingPhaseSummaryDialog: Player cancelled ending shooting phase")
	emit_signal("shooting_cancelled")
	hide()
	queue_free()
