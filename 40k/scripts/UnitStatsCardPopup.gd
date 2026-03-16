extends PanelContainer
class_name UnitStatsCardPopup

# Floating datasheet card that shows a unit's full profile when right-clicking
# and selecting "Unit Stats". Styled after the official Warhammer 40K datasheet
# format with stats row, weapons tables, and abilities list.

const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")

const MAX_WIDTH := 480
const MAX_HEIGHT := 520

var _unit_id: String = ""


func setup(uid: String, popup_position: Vector2) -> void:
	_unit_id = uid
	name = "UnitStatsCardPopup"

	var unit = GameState.get_unit(uid)
	if unit.is_empty():
		queue_free()
		return

	var meta = unit.get("meta", {})

	# Panel style — dark gothic card with gold border
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.07, 0.05, 0.97)
	panel_style.border_color = _WhiteDwarfTheme.WH_GOLD
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", panel_style)

	custom_minimum_size = Vector2(MAX_WIDTH, 0)

	# Scroll container so tall datasheets don't overflow the screen
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(MAX_WIDTH, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 0)
	scroll.add_child(content)

	# ── Header: Unit Name + Keywords ──
	_build_header(content, unit, meta)

	# ── Stats Row ──
	_build_stats_row(content, meta)

	# ── Weapons Tables ──
	_build_weapons_section(content, meta)

	# ── Abilities ──
	_build_abilities_section(content, unit)

	# ── Footer: Model/Wound Status ──
	_build_footer(content, unit)

	# Position & z-order
	z_index = 1000
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Defer positioning so the panel has its final size
	await get_tree().process_frame
	_clamp_to_screen(popup_position)


# ── Header ──────────────────────────────────────────────────────

func _build_header(parent: VBoxContainer, unit: Dictionary, meta: Dictionary) -> void:
	var header_panel = PanelContainer.new()
	var header_style = StyleBoxFlat.new()
	header_style.bg_color = Color(0.12, 0.10, 0.07, 1.0)
	header_style.border_color = _WhiteDwarfTheme.WH_GOLD
	header_style.border_width_bottom = 1
	header_style.content_margin_left = 12
	header_style.content_margin_right = 12
	header_style.content_margin_top = 8
	header_style.content_margin_bottom = 8
	header_panel.add_theme_stylebox_override("panel", header_style)
	parent.add_child(header_panel)

	var header_vbox = VBoxContainer.new()
	header_vbox.add_theme_constant_override("separation", 2)
	header_panel.add_child(header_vbox)

	# Title row: name + badges
	var title_row = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	header_vbox.add_child(title_row)

	var name_label = Label.new()
	name_label.text = meta.get("name", "Unknown Unit").to_upper()
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(name_label)

	# Badges
	if meta.get("is_warlord", false):
		var wl_label = Label.new()
		wl_label.text = "WARLORD"
		wl_label.add_theme_font_size_override("font_size", 10)
		wl_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		title_row.add_child(wl_label)

	var points = meta.get("points", 0)
	if points > 0:
		var pts_label = Label.new()
		pts_label.text = "%dpts" % points
		pts_label.add_theme_font_size_override("font_size", 11)
		pts_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_BONE)
		title_row.add_child(pts_label)

	# Keywords line
	var keywords = meta.get("keywords", [])
	if not keywords.is_empty():
		var kw_label = Label.new()
		kw_label.text = ", ".join(keywords)
		kw_label.add_theme_font_size_override("font_size", 10)
		kw_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_BONE)
		kw_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		header_vbox.add_child(kw_label)

	# Enhancements
	var enhancements = meta.get("enhancements", [])
	if not enhancements.is_empty():
		var enh_label = Label.new()
		enh_label.text = "Enhancements: " + ", ".join(enhancements)
		enh_label.add_theme_font_size_override("font_size", 10)
		enh_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
		enh_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		header_vbox.add_child(enh_label)


# ── Stats Row ───────────────────────────────────────────────────

func _build_stats_row(parent: VBoxContainer, meta: Dictionary) -> void:
	var stats = meta.get("stats", {})
	if stats.is_empty():
		return

	var stats_panel = PanelContainer.new()
	var stats_style = StyleBoxFlat.new()
	stats_style.bg_color = Color(0.15, 0.12, 0.08, 1.0)
	stats_style.border_color = _WhiteDwarfTheme.WH_GOLD
	stats_style.border_width_bottom = 1
	stats_style.content_margin_left = 12
	stats_style.content_margin_right = 12
	stats_style.content_margin_top = 6
	stats_style.content_margin_bottom = 6
	stats_panel.add_theme_stylebox_override("panel", stats_style)
	parent.add_child(stats_panel)

	var grid = GridContainer.new()
	grid.columns = 6
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_panel.add_child(grid)

	# Stat definitions: [key, label, suffix]
	var stat_defs = [
		["move", "M", "\""],
		["toughness", "T", ""],
		["save", "Sv", "+"],
		["wounds", "W", ""],
		["leadership", "Ld", "+"],
		["objective_control", "OC", ""],
	]

	# Header row
	for def in stat_defs:
		var header = Label.new()
		header.text = def[1]
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_theme_font_size_override("font_size", 11)
		header.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
		header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(header)

	# Value row
	for def in stat_defs:
		var value_label = Label.new()
		var val = stats.get(def[0], "-")
		value_label.text = str(val) + def[2] if val != null and str(val) != "" else "-"
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value_label.add_theme_font_size_override("font_size", 16)
		value_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(value_label)

	# FNP / Invuln if present
	var fnp = stats.get("fnp", 0)
	var invuln = stats.get("invulnerable_save", 0)
	if fnp > 0 or invuln > 0:
		var special_row = HBoxContainer.new()
		special_row.add_theme_constant_override("separation", 16)
		special_row.alignment = BoxContainer.ALIGNMENT_CENTER
		# Can't add directly to grid; add after the stats panel
		if invuln > 0:
			var inv_label = Label.new()
			inv_label.text = "Invulnerable Save: %d+" % invuln
			inv_label.add_theme_font_size_override("font_size", 11)
			inv_label.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
			special_row.add_child(inv_label)
		if fnp > 0:
			var fnp_label = Label.new()
			fnp_label.text = "Feel No Pain: %d+" % fnp
			fnp_label.add_theme_font_size_override("font_size", 11)
			fnp_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
			special_row.add_child(fnp_label)
		parent.add_child(special_row)


# ── Weapons ─────────────────────────────────────────────────────

func _build_weapons_section(parent: VBoxContainer, meta: Dictionary) -> void:
	var weapons = meta.get("weapons", [])
	if weapons.is_empty():
		return

	var ranged: Array = []
	var melee: Array = []
	for w in weapons:
		if w.get("type", "") == "Ranged":
			ranged.append(w)
		elif w.get("type", "") == "Melee":
			melee.append(w)

	if not ranged.is_empty():
		_build_weapon_table(parent, "RANGED WEAPONS", ranged, true)
	if not melee.is_empty():
		_build_weapon_table(parent, "MELEE WEAPONS", melee, false)


func _build_weapon_table(parent: VBoxContainer, title: String, weapons: Array, is_ranged: bool) -> void:
	var section = VBoxContainer.new()
	section.add_theme_constant_override("separation", 0)
	parent.add_child(section)

	# Section header
	var header_panel = PanelContainer.new()
	var hdr_style = StyleBoxFlat.new()
	if is_ranged:
		hdr_style.bg_color = Color(0.12, 0.14, 0.20, 1.0)  # Slight blue tint for ranged
	else:
		hdr_style.bg_color = Color(0.20, 0.10, 0.08, 1.0)  # Slight red tint for melee
	hdr_style.border_color = _WhiteDwarfTheme.WH_GOLD
	hdr_style.border_width_bottom = 1
	hdr_style.content_margin_left = 12
	hdr_style.content_margin_right = 12
	hdr_style.content_margin_top = 4
	hdr_style.content_margin_bottom = 4
	header_panel.add_theme_stylebox_override("panel", hdr_style)
	section.add_child(header_panel)

	var title_label = Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 12)
	if is_ranged:
		title_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	else:
		title_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.35))
	header_panel.add_child(title_label)

	# Table content
	var table_panel = PanelContainer.new()
	var tbl_style = StyleBoxFlat.new()
	tbl_style.bg_color = Color(0.09, 0.08, 0.06, 1.0)
	tbl_style.border_color = Color(_WhiteDwarfTheme.WH_GOLD, 0.3)
	tbl_style.border_width_bottom = 1
	tbl_style.content_margin_left = 12
	tbl_style.content_margin_right = 12
	tbl_style.content_margin_top = 4
	tbl_style.content_margin_bottom = 4
	table_panel.add_theme_stylebox_override("panel", tbl_style)
	section.add_child(table_panel)

	var table_vbox = VBoxContainer.new()
	table_vbox.add_theme_constant_override("separation", 2)
	table_panel.add_child(table_vbox)

	# Each weapon as a row
	for weapon in weapons:
		_build_weapon_row(table_vbox, weapon, is_ranged)


func _build_weapon_row(parent: VBoxContainer, weapon: Dictionary, is_ranged: bool) -> void:
	var row_vbox = VBoxContainer.new()
	row_vbox.add_theme_constant_override("separation", 1)
	parent.add_child(row_vbox)

	# Weapon name
	var name_label = Label.new()
	name_label.text = weapon.get("name", "Unknown")
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
	row_vbox.add_child(name_label)

	# Stats line
	var stats_line: String
	if is_ranged:
		stats_line = "Range %s\"  A%s  BS%s+  S%s  AP%s  D%s" % [
			weapon.get("range", "-"),
			weapon.get("attacks", "-"),
			weapon.get("ballistic_skill", "-"),
			weapon.get("strength", "-"),
			weapon.get("ap", "0"),
			weapon.get("damage", "-"),
		]
	else:
		stats_line = "Melee  A%s  WS%s+  S%s  AP%s  D%s" % [
			weapon.get("attacks", "-"),
			weapon.get("weapon_skill", "-"),
			weapon.get("strength", "-"),
			weapon.get("ap", "0"),
			weapon.get("damage", "-"),
		]

	var stats_label = Label.new()
	stats_label.text = stats_line
	stats_label.add_theme_font_size_override("font_size", 10)
	stats_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_BONE)
	row_vbox.add_child(stats_label)

	# Special rules
	var special = weapon.get("special_rules", "")
	if special != "":
		var special_label = Label.new()
		special_label.text = "[%s]" % special
		special_label.add_theme_font_size_override("font_size", 9)
		special_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
		special_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row_vbox.add_child(special_label)

	# Thin separator between weapons
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	var sep_style = StyleBoxFlat.new()
	sep_style.bg_color = Color(_WhiteDwarfTheme.WH_GOLD, 0.1)
	sep_style.content_margin_top = 0
	sep_style.content_margin_bottom = 0
	sep.add_theme_stylebox_override("separator", sep_style)
	parent.add_child(sep)


# ── Abilities ───────────────────────────────────────────────────

func _build_abilities_section(parent: VBoxContainer, unit: Dictionary) -> void:
	var meta = unit.get("meta", {})
	var abilities = meta.get("abilities", [])
	if abilities.is_empty():
		return

	# Section header
	var header_panel = PanelContainer.new()
	var hdr_style = StyleBoxFlat.new()
	hdr_style.bg_color = Color(0.12, 0.10, 0.07, 1.0)
	hdr_style.border_color = _WhiteDwarfTheme.WH_GOLD
	hdr_style.border_width_bottom = 1
	hdr_style.content_margin_left = 12
	hdr_style.content_margin_right = 12
	hdr_style.content_margin_top = 4
	hdr_style.content_margin_bottom = 4
	header_panel.add_theme_stylebox_override("panel", hdr_style)
	parent.add_child(header_panel)

	var title_label = Label.new()
	title_label.text = "ABILITIES"
	title_label.add_theme_font_size_override("font_size", 12)
	title_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	header_panel.add_child(title_label)

	# Abilities content
	var content_panel = PanelContainer.new()
	var cnt_style = StyleBoxFlat.new()
	cnt_style.bg_color = Color(0.09, 0.08, 0.06, 1.0)
	cnt_style.border_color = Color(_WhiteDwarfTheme.WH_GOLD, 0.3)
	cnt_style.border_width_bottom = 1
	cnt_style.content_margin_left = 12
	cnt_style.content_margin_right = 12
	cnt_style.content_margin_top = 6
	cnt_style.content_margin_bottom = 6
	content_panel.add_theme_stylebox_override("panel", cnt_style)
	parent.add_child(content_panel)

	var abilities_vbox = VBoxContainer.new()
	abilities_vbox.add_theme_constant_override("separation", 4)
	content_panel.add_child(abilities_vbox)

	# Group abilities by type
	var core_abilities: Array = []
	var faction_abilities: Array = []
	var datasheet_abilities: Array = []
	var other_abilities: Array = []

	for ability in abilities:
		var ability_type = ability.get("type", "")
		match ability_type:
			"Core":
				core_abilities.append(ability)
			"Faction":
				faction_abilities.append(ability)
			"Datasheet":
				datasheet_abilities.append(ability)
			_:
				other_abilities.append(ability)

	# Core abilities — compact single line
	if not core_abilities.is_empty():
		var core_names: Array = []
		for a in core_abilities:
			var aname = a.get("name", "")
			if aname != "" and aname != "Core":
				core_names.append(aname)
		if not core_names.is_empty():
			var core_label = Label.new()
			core_label.text = "Core: " + ", ".join(core_names)
			core_label.add_theme_font_size_override("font_size", 10)
			core_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_BONE)
			core_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			abilities_vbox.add_child(core_label)

	# Faction abilities
	for ability in faction_abilities:
		_build_ability_entry(abilities_vbox, ability, Color(0.8, 0.5, 0.2))

	# Datasheet abilities
	for ability in datasheet_abilities:
		_build_ability_entry(abilities_vbox, ability, _WhiteDwarfTheme.WH_PARCHMENT)

	# Other abilities
	for ability in other_abilities:
		_build_ability_entry(abilities_vbox, ability, _WhiteDwarfTheme.WH_PARCHMENT)


func _build_ability_entry(parent: VBoxContainer, ability: Dictionary, name_color: Color) -> void:
	var entry = VBoxContainer.new()
	entry.add_theme_constant_override("separation", 1)
	parent.add_child(entry)

	var name_label = Label.new()
	var display_name = ability.get("name", "Unknown")
	var ability_type = ability.get("type", "")
	if ability_type != "":
		display_name += " [%s]" % ability_type
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", name_color)
	entry.add_child(name_label)

	var desc = ability.get("description", "")
	if desc != "":
		var desc_label = Label.new()
		desc_label.text = desc
		desc_label.add_theme_font_size_override("font_size", 9)
		desc_label.add_theme_color_override("font_color", Color(_WhiteDwarfTheme.WH_PARCHMENT, 0.7))
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.add_child(desc_label)


# ── Footer ──────────────────────────────────────────────────────

func _build_footer(parent: VBoxContainer, unit: Dictionary) -> void:
	var models = unit.get("models", [])
	if models.is_empty():
		return

	var footer_panel = PanelContainer.new()
	var ftr_style = StyleBoxFlat.new()
	ftr_style.bg_color = Color(0.12, 0.10, 0.07, 1.0)
	ftr_style.border_color = _WhiteDwarfTheme.WH_GOLD
	ftr_style.border_width_top = 1
	ftr_style.content_margin_left = 12
	ftr_style.content_margin_right = 12
	ftr_style.content_margin_top = 6
	ftr_style.content_margin_bottom = 6
	footer_panel.add_theme_stylebox_override("panel", ftr_style)
	parent.add_child(footer_panel)

	var footer_row = HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 16)
	footer_panel.add_child(footer_row)

	# Model count
	var alive_count := 0
	var total_count := models.size()
	var total_wounds := 0
	var current_wounds := 0
	for model in models:
		if model.get("alive", true):
			alive_count += 1
			current_wounds += model.get("current_wounds", model.get("wounds", 1))
		total_wounds += model.get("wounds", 1)

	var models_label = Label.new()
	models_label.text = "Models: %d/%d" % [alive_count, total_count]
	models_label.add_theme_font_size_override("font_size", 11)
	if alive_count == total_count:
		models_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	else:
		models_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))
	footer_row.add_child(models_label)

	# Total wounds
	var wounds_label = Label.new()
	wounds_label.text = "Wounds: %d/%d" % [current_wounds, total_wounds]
	wounds_label.add_theme_font_size_override("font_size", 11)
	if current_wounds == total_wounds:
		wounds_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	else:
		wounds_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))
	footer_row.add_child(wounds_label)

	# Status flags
	var flags = unit.get("flags", {})
	var status_parts: Array = []
	if flags.get("moved", false):
		status_parts.append("MOVED")
	if flags.get("advanced", false):
		status_parts.append("ADV")
	if flags.get("fell_back", false):
		status_parts.append("FELL BACK")
	if flags.get("shot", false):
		status_parts.append("SHOT")
	if flags.get("charged", false):
		status_parts.append("CHARGED")
	if flags.get("fought", false):
		status_parts.append("FOUGHT")

	if not status_parts.is_empty():
		var status_label = Label.new()
		status_label.text = "[" + ", ".join(status_parts) + "]"
		status_label.add_theme_font_size_override("font_size", 10)
		status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		footer_row.add_child(status_label)


# ── Positioning ─────────────────────────────────────────────────

func _clamp_to_screen(desired_pos: Vector2) -> void:
	var viewport_size = get_viewport_rect().size
	var card_size = size

	# Clamp height
	if card_size.y > MAX_HEIGHT:
		custom_minimum_size.y = MAX_HEIGHT
		size.y = MAX_HEIGHT

	var final_pos = desired_pos
	# Keep within screen bounds with 8px margin
	final_pos.x = clampf(final_pos.x, 8.0, viewport_size.x - card_size.x - 8.0)
	final_pos.y = clampf(final_pos.y, 8.0, viewport_size.y - min(card_size.y, MAX_HEIGHT) - 8.0)
	position = final_pos


# ── Input Handling ──────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		queue_free()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if not get_global_rect().has_point(event.global_position):
			queue_free()
