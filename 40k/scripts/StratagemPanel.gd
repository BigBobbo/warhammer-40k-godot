extends AcceptDialog
class_name StratagemPanel

# T-023: Pre-game stratagems UI shell — list all eligible stratagems for the
# active phase / player with CP cost, faction/core/detachment grouping, and
# active state.
#
# Triggered from a HUD button (or the "S" hotkey). Iterates
# StratagemManager.stratagems and renders rows. Greyed-out for ineligible
# (off-phase, insufficient CP, once-per-X exhausted).

signal stratagem_use_requested(stratagem_id: String)

var _player: int = 1
var _phase_id: int = 0
var _list_container: VBoxContainer = null
var _empty_label: Label = null


func _ready() -> void:
	title = "Stratagems"
	min_size = Vector2(560, 480)
	WhiteDwarfTheme.apply_to_dialog(self)
	var ok_btn = get_ok_button()
	ok_btn.text = "Close"
	WhiteDwarfTheme.apply_secondary_button(ok_btn)
	_build_ui()


func _build_ui() -> void:
	if _list_container != null:
		return
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 420)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var vb = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	scroll.add_child(vb)
	_list_container = vb
	_empty_label = Label.new()
	_empty_label.text = "No stratagems available."
	_empty_label.add_theme_color_override("font_color", Color(0.55, 0.52, 0.45))
	_empty_label.visible = false
	_list_container.add_child(_empty_label)


func populate(player: int, phase_id: int = -1) -> void:
	_player = player
	_phase_id = phase_id
	_build_ui()
	# Clear previous rows (keep _empty_label)
	for child in _list_container.get_children():
		if child == _empty_label:
			continue
		child.queue_free()

	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager == null:
		_empty_label.text = "StratagemManager not available."
		_empty_label.visible = true
		return

	var cp = 0
	if strat_manager.has_method("get_player_cp"):
		cp = strat_manager.get_player_cp(player)
	var faction_name = GameState.get_faction_name(player)
	title = "Stratagems — Player %d (%s) — %d CP" % [player, faction_name, cp]

	var stratagems_dict: Dictionary = strat_manager.get("stratagems")
	if stratagems_dict == null or stratagems_dict.is_empty():
		_empty_label.text = "No stratagems loaded."
		_empty_label.visible = true
		return
	_empty_label.visible = false

	# Group by source: core / faction / detachment.
	var groups = {"Core": [], "Faction": [], "Detachment": []}
	for sid in stratagems_dict.keys():
		var strat = stratagems_dict[sid]
		var source = strat.get("source", "Core")
		var bucket = "Core"
		var src_lower = String(source).to_lower()
		if "detachment" in src_lower:
			bucket = "Detachment"
		elif strat_manager.has_method("is_faction_stratagem") and strat_manager.is_faction_stratagem(sid):
			bucket = "Faction"
		groups[bucket].append(sid)

	for group_name in ["Core", "Faction", "Detachment"]:
		var ids = groups[group_name]
		if ids.is_empty():
			continue
		_add_stratagem_gold_separator(_list_container)
		var header = Label.new()
		header.text = group_name.to_upper()
		header.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
		header.add_theme_font_size_override("font_size", 14)
		if FactionPalettes.FONT_RAJDHANI_BOLD:
			header.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list_container.add_child(header)
		for sid in ids:
			var strat = stratagems_dict[sid]
			# Ownership filter: faction stratagems only show for owning player.
			if strat_manager.has_method("get_stratagem_owner"):
				var owner_id = strat_manager.get_stratagem_owner(sid)
				if owner_id != 0 and owner_id != player:
					continue
			_list_container.add_child(_build_row(strat_manager, sid, strat, cp))


func _build_row(strat_manager: Node, sid: String, strat: Dictionary, current_cp: int) -> Control:
	var card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.10, 0.95)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", style)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var validation = {"can_use": false, "reason": ""}
	if strat_manager.has_method("can_use_stratagem"):
		validation = strat_manager.can_use_stratagem(_player, sid)
	var can_use = bool(validation.get("can_use", false))

	style.border_color = Color(WhiteDwarfTheme.WH_GOLD.r, WhiteDwarfTheme.WH_GOLD.g, WhiteDwarfTheme.WH_GOLD.b, 0.3 if not can_use else 0.6)
	style.set_border_width_all(1)

	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(row)

	var name_label = Label.new()
	var display = strat.get("name", sid)
	var cost = int(strat.get("cp_cost", strat.get("cost", 0)))
	name_label.text = "%s (%d CP)" % [display, cost]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if FactionPalettes.FONT_RAJDHANI_SEMIBOLD:
		name_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_SEMIBOLD)
	name_label.add_theme_font_size_override("font_size", 13)
	row.add_child(name_label)

	var status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 11)
	if can_use:
		status_label.text = "ELIGIBLE"
		name_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_PARCHMENT)
		status_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
		if FactionPalettes.FONT_RAJDHANI_BOLD:
			status_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	else:
		var reason = String(validation.get("reason", "ineligible"))
		status_label.text = reason
		var grey = Color(0.45, 0.42, 0.38)
		name_label.add_theme_color_override("font_color", grey)
		status_label.add_theme_color_override("font_color", grey)
	status_label.custom_minimum_size = Vector2(180, 0)
	row.add_child(status_label)

	var use_btn = Button.new()
	use_btn.text = "Use"
	use_btn.disabled = not can_use or current_cp < cost
	use_btn.pressed.connect(func(): emit_signal("stratagem_use_requested", sid))
	WhiteDwarfTheme.apply_primary_button(use_btn)
	use_btn.custom_minimum_size = Vector2(60, 28)
	row.add_child(use_btn)

	return card


func _add_stratagem_gold_separator(parent: Control) -> void:
	var sep = ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.color = Color(WhiteDwarfTheme.WH_GOLD.r, WhiteDwarfTheme.WH_GOLD.g, WhiteDwarfTheme.WH_GOLD.b, 0.4)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(sep)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and visible:
			hide()
