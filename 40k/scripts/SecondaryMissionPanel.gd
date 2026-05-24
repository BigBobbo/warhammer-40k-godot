extends PanelContainer

# SecondaryMissionPanel - Persistent, collapsible overlay showing active secondary missions
# Visible across all phases. Toggle with 'M' key or click the header.

const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")
const SecondaryMissionData = preload("res://scripts/data/SecondaryMissionData.gd")

var is_collapsed: bool = true
var tween: Tween

# Internal UI references
var header_button: Button
var content_container: VBoxContainer
var scroll_container: ScrollContainer

const PANEL_WIDTH := 300
const HEADER_HEIGHT := 32
const EXPANDED_HEIGHT := 320

func _ready() -> void:
	name = "SecondaryMissionPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Anchored to the TOP-LEFT corner of the screen so it owns the top
	# slot of the left-side panel column (GameLogPanel starts just
	# below it). Visible by default — the player toggles only the
	# expanded/collapsed state via the header button or the 'M' key.
	visible = true
	_sync_panel_position()
	var vp := get_viewport()
	if vp != null and not vp.is_connected("size_changed", _sync_panel_position):
		vp.connect("size_changed", _sync_panel_position)
	custom_minimum_size = Vector2(PANEL_WIDTH, HEADER_HEIGHT)

	# Apply gothic panel style
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.07, 0.06, 0.92)
	panel_style.border_color = _WhiteDwarfTheme.WH_GOLD
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", panel_style)

	_build_ui()
	_connect_signals()

	# Start collapsed
	set_collapsed(true)
	print("SecondaryMissionPanel: Ready (collapsed)")

func _build_ui() -> void:
	var vbox = VBoxContainer.new()
	vbox.name = "PanelVBox"
	add_child(vbox)

	# Header toggle button
	header_button = Button.new()
	header_button.text = "▶ Secondary Missions [M]"
	header_button.custom_minimum_size = Vector2(0, HEADER_HEIGHT)
	header_button.add_theme_font_size_override("font_size", 12)
	header_button.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	_WhiteDwarfTheme.apply_to_button(header_button)
	header_button.pressed.connect(_on_header_pressed)
	vbox.add_child(header_button)

	# Scrollable content area
	scroll_container = ScrollContainer.new()
	scroll_container.name = "MissionScroll"
	scroll_container.custom_minimum_size = Vector2(0, EXPANDED_HEIGHT - HEADER_HEIGHT)
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.visible = false
	vbox.add_child(scroll_container)

	content_container = VBoxContainer.new()
	content_container.name = "MissionContent"
	content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_container.add_theme_constant_override("separation", 4)
	scroll_container.add_child(content_container)

func _connect_signals() -> void:
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if not secondary_mgr:
		print("SecondaryMissionPanel: SecondaryMissionManager not found — will retry on refresh")
		return

	if secondary_mgr.has_signal("mission_drawn"):
		if not secondary_mgr.mission_drawn.is_connected(_on_mission_event):
			secondary_mgr.mission_drawn.connect(_on_mission_event)
	if secondary_mgr.has_signal("mission_achieved"):
		if not secondary_mgr.mission_achieved.is_connected(_on_mission_scored):
			secondary_mgr.mission_achieved.connect(_on_mission_scored)
	if secondary_mgr.has_signal("mission_discarded"):
		if not secondary_mgr.mission_discarded.is_connected(_on_mission_discard_event):
			secondary_mgr.mission_discarded.connect(_on_mission_discard_event)
	if secondary_mgr.has_signal("secondary_vp_scored"):
		if not secondary_mgr.secondary_vp_scored.is_connected(_on_vp_scored):
			secondary_mgr.secondary_vp_scored.connect(_on_vp_scored)
	print("SecondaryMissionPanel: Connected to SecondaryMissionManager signals")

func _exit_tree() -> void:
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if not secondary_mgr:
		return
	if secondary_mgr.has_signal("mission_drawn") and secondary_mgr.mission_drawn.is_connected(_on_mission_event):
		secondary_mgr.mission_drawn.disconnect(_on_mission_event)
	if secondary_mgr.has_signal("mission_achieved") and secondary_mgr.mission_achieved.is_connected(_on_mission_scored):
		secondary_mgr.mission_achieved.disconnect(_on_mission_scored)
	if secondary_mgr.has_signal("mission_discarded") and secondary_mgr.mission_discarded.is_connected(_on_mission_discard_event):
		secondary_mgr.mission_discarded.disconnect(_on_mission_discard_event)
	if secondary_mgr.has_signal("secondary_vp_scored") and secondary_mgr.secondary_vp_scored.is_connected(_on_vp_scored):
		secondary_mgr.secondary_vp_scored.disconnect(_on_vp_scored)

# ============================================================================
# TOGGLE / COLLAPSE
# ============================================================================

func _on_header_pressed() -> void:
	toggle()

func toggle() -> void:
	set_collapsed(!is_collapsed)

func set_collapsed(collapsed: bool) -> void:
	is_collapsed = collapsed

	if scroll_container:
		scroll_container.visible = !collapsed

	if header_button:
		header_button.text = ("▶ Secondary Missions [M]" if collapsed
			else "▼ Secondary Missions [M]")

	# Animate height
	if tween:
		tween.kill()
	tween = create_tween()
	var target_h = HEADER_HEIGHT if collapsed else EXPANDED_HEIGHT
	tween.tween_property(self, "offset_bottom", offset_top + target_h, 0.2)
	tween.parallel().tween_property(self, "custom_minimum_size:y", target_h, 0.2)

	if not collapsed:
		refresh()


func toggle_visible() -> void:
	visible = not visible
	if visible:
		set_collapsed(false)


func _sync_panel_position() -> void:
	# Top-LEFT corner. The left-side panel column reserves the first
	# 340px of the viewport: this panel owns y=8..40 (collapsed) and
	# expands DOWN over GameLogPanel when opened. Width matches the
	# GameLogPanel column (PANEL_WIDTH=300, fitting inside 340px col).
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	offset_left = 8
	offset_top = 8
	offset_right = offset_left + PANEL_WIDTH
	offset_bottom = offset_top + (HEADER_HEIGHT if is_collapsed else EXPANDED_HEIGHT)

# ============================================================================
# CONTENT REFRESH
# ============================================================================

func refresh() -> void:
	if not content_container:
		return

	# Clear old content
	for child in content_container.get_children():
		child.queue_free()

	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if not secondary_mgr:
		_add_label(content_container, "Secondary mission system not available", 11, Color(0.5, 0.5, 0.5))
		return

	# Reconnect signals if needed (handles late autoload)
	_connect_signals()

	var current_player = GameState.get_active_player()

	if not secondary_mgr.is_initialized(current_player):
		_add_label(content_container, "Missions not yet initialized\n(set up in Command Phase or pre-game)", 11, Color(0.5, 0.5, 0.5))
		return

	# Summary bar
	_build_summary(content_container, secondary_mgr, current_player)

	# Active missions for current player
	_add_label(content_container, "Player %d — Active Missions" % current_player, 12, _WhiteDwarfTheme.WH_GOLD)
	_build_player_missions(content_container, secondary_mgr, current_player)

	# Opponent summary (collapsed)
	var opponent = 2 if current_player == 1 else 1
	if secondary_mgr.is_initialized(opponent):
		var _gsep1 = ColorRect.new()
		_gsep1.custom_minimum_size = Vector2(0, 2)
		_gsep1.color = Color(_WhiteDwarfTheme.WH_GOLD.r, _WhiteDwarfTheme.WH_GOLD.g, _WhiteDwarfTheme.WH_GOLD.b, 0.4)
		_gsep1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_container.add_child(_gsep1)
		_add_label(content_container, "Player %d — %d Secondary VP" % [
			opponent, secondary_mgr.get_secondary_vp(opponent)], 11, Color(0.6, 0.6, 0.6))
		var opp_active = secondary_mgr.get_active_missions(opponent)
		if opp_active.size() > 0:
			for m in opp_active:
				_add_label(content_container, "  - %s (%s)" % [
					m.get("name", "?"), m.get("category", "")], 10, Color(0.55, 0.55, 0.55))
		else:
			_add_label(content_container, "  No active missions", 10, Color(0.45, 0.45, 0.45))

func _build_summary(parent: VBoxContainer, mgr, player: int) -> void:
	var secondary_vp = mgr.get_secondary_vp(player)
	var is_fixed = mgr.is_fixed_mode(player)

	var summary = Label.new()
	if is_fixed:
		summary.text = "Mode: FIXED  |  VP: %d/40" % secondary_vp
	else:
		var deck_size = mgr.get_deck_size(player)
		var discard_size = mgr.get_discard_size(player)
		summary.text = "Deck: %d  |  Discard: %d  |  VP: %d/40" % [deck_size, discard_size, secondary_vp]
	summary.add_theme_font_size_override("font_size", 11)
	summary.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
	parent.add_child(summary)
	var _gsep2 = ColorRect.new()
	_gsep2.custom_minimum_size = Vector2(0, 2)
	_gsep2.color = Color(_WhiteDwarfTheme.WH_GOLD.r, _WhiteDwarfTheme.WH_GOLD.g, _WhiteDwarfTheme.WH_GOLD.b, 0.4)
	_gsep2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(_gsep2)

func _build_player_missions(parent: VBoxContainer, mgr, player: int) -> void:
	var active_missions = mgr.get_active_missions(player)

	if active_missions.size() == 0:
		_add_label(parent, "No active missions — draw in Command Phase", 11, Color(0.5, 0.5, 0.5))
		return

	# Get live progress data for all active missions
	var progress_data = mgr.evaluate_mission_progress(player)
	var progress_by_id = {}
	for p in progress_data:
		progress_by_id[p["mission_id"]] = p

	for mission in active_missions:
		var mission_progress = progress_by_id.get(mission.get("id", ""), {})
		_build_mission_card(parent, mission, mission_progress)

func _build_mission_card(parent: VBoxContainer, mission: Dictionary, progress: Dictionary = {}) -> void:
	var card = PanelContainer.new()
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.1, 0.09, 0.07, 0.95)
	var best_vp = progress.get("best_vp_available", 0)
	if best_vp > 0:
		card_style.border_color = Color(0.3, 0.8, 0.3)
		card_style.set_border_width_all(2)
	else:
		card_style.border_color = Color(0.4, 0.35, 0.15)
		card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(4)
	card_style.content_margin_left = 8
	card_style.content_margin_right = 8
	card_style.content_margin_top = 6
	card_style.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", card_style)
	parent.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)

	# Top row: category icon + mission name + VP badge
	var top_row = HBoxContainer.new()
	top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_theme_constant_override("separation", 6)
	vbox.add_child(top_row)

	var cat_icon = Label.new()
	var category = mission.get("category", "")
	cat_icon.text = _get_category_icon(category)
	cat_icon.add_theme_font_size_override("font_size", 16)
	cat_icon.add_theme_color_override("font_color", _get_category_color(category))
	cat_icon.custom_minimum_size = Vector2(20, 0)
	top_row.add_child(cat_icon)

	var name_label = Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text = mission.get("name", "Unknown Mission")
	name_label.add_theme_font_size_override("font_size", 13)
	if FactionPalettes:
		name_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	if best_vp > 0:
		name_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	else:
		name_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	top_row.add_child(name_label)

	if best_vp > 0:
		var vp_badge = Label.new()
		vp_badge.text = "+%dVP" % best_vp
		vp_badge.add_theme_font_size_override("font_size", 13)
		vp_badge.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))
		if FactionPalettes:
			vp_badge.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
		top_row.add_child(vp_badge)

	# Category + scoring timing on one line
	var scoring = mission.get("scoring", {})
	var timing_text = _get_timing_display(scoring.get("when", ""))
	var cat_label = Label.new()
	cat_label.text = "%s  |  %s" % [category, timing_text]
	cat_label.add_theme_font_size_override("font_size", 10)
	cat_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	vbox.add_child(cat_label)

	# Condition progress tracking with checkmark/cross indicators
	var condition_progress = progress.get("conditions", [])
	if condition_progress.size() > 0:
		for cond in condition_progress:
			var met = cond.get("met", false)
			var vp = cond.get("vp", 0)
			var desc = cond.get("description", cond.get("check", "?"))
			var cond_row = HBoxContainer.new()
			cond_row.add_theme_constant_override("separation", 4)
			var icon_lbl = Label.new()
			icon_lbl.custom_minimum_size = Vector2(16, 0)
			icon_lbl.add_theme_font_size_override("font_size", 12)
			if met:
				icon_lbl.text = "+"
				icon_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
			else:
				icon_lbl.text = "-"
				icon_lbl.add_theme_color_override("font_color", Color(0.6, 0.3, 0.3))
			cond_row.add_child(icon_lbl)
			var cond_label = Label.new()
			if met:
				cond_label.text = "%dVP  %s" % [vp, desc]
				cond_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
			else:
				cond_label.text = "%dVP  %s" % [vp, desc]
				cond_label.add_theme_color_override("font_color", Color(0.5, 0.4, 0.4))
			cond_label.add_theme_font_size_override("font_size", 11)
			cond_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cond_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cond_row.add_child(cond_label)
			vbox.add_child(cond_row)
	else:
		var conditions = scoring.get("conditions", [])
		for c in conditions:
			var vp = c.get("vp", 0)
			var check = c.get("check", "")
			var cond_row = HBoxContainer.new()
			cond_row.add_theme_constant_override("separation", 4)
			var icon_lbl = Label.new()
			icon_lbl.text = "-"
			icon_lbl.custom_minimum_size = Vector2(16, 0)
			icon_lbl.add_theme_font_size_override("font_size", 12)
			icon_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			cond_row.add_child(icon_lbl)
			var cond_label = Label.new()
			cond_label.text = "%dVP  %s" % [vp, _humanize_check(check)]
			cond_label.add_theme_font_size_override("font_size", 11)
			cond_label.add_theme_color_override("font_color", Color(0.5, 0.75, 0.5))
			cond_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cond_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cond_row.add_child(cond_label)
			vbox.add_child(cond_row)

	# VP scored so far
	var vp_scored = mission.get("vp_scored", 0)
	if vp_scored > 0:
		var scored_label = Label.new()
		# Show VP cap for fixed missions
		var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
		var current_player = GameState.get_active_player()
		if secondary_mgr and secondary_mgr.is_fixed_mode(current_player):
			scored_label.text = "Scored: %d/20 VP" % vp_scored
		else:
			scored_label.text = "Scored: %d VP" % vp_scored
		scored_label.add_theme_font_size_override("font_size", 10)
		scored_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
		vbox.add_child(scored_label)

	# Pending interaction
	if mission.get("pending_interaction", false):
		var pending = Label.new()
		pending.text = "AWAITING INTERACTION"
		pending.add_theme_font_size_override("font_size", 10)
		pending.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
		vbox.add_child(pending)
	else:
		# Show resolved interaction data if available
		var mission_data = mission.get("mission_data", {})
		if mission.get("id", "") == "marked_for_death" and not mission_data.get("alpha_targets", []).is_empty():
			var targets_label = Label.new()
			var alpha_names = []
			for target_id in mission_data.get("alpha_targets", []):
				var unit = GameState.get_unit(target_id)
				alpha_names.append(unit.get("meta", {}).get("name", target_id) if not unit.is_empty() else target_id)
			var gamma_id = mission_data.get("gamma_target", "")
			var gamma_name = ""
			if gamma_id != "":
				var gamma_unit = GameState.get_unit(gamma_id)
				gamma_name = gamma_unit.get("meta", {}).get("name", gamma_id) if not gamma_unit.is_empty() else gamma_id
			targets_label.text = "Alpha: %s" % ", ".join(alpha_names)
			if gamma_name != "":
				targets_label.text += "\nGamma: %s" % gamma_name
			targets_label.add_theme_font_size_override("font_size", 9)
			targets_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.4))
			targets_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vbox.add_child(targets_label)

		elif mission.get("id", "") == "a_tempting_target" and mission_data.get("tempting_target_id", "") != "":
			var obj_label = Label.new()
			var obj_id = mission_data.get("tempting_target_id", "")
			obj_label.text = "Target: %s" % obj_id.replace("obj_", "Objective ").to_upper()
			obj_label.add_theme_font_size_override("font_size", 9)
			obj_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.4))
			vbox.add_child(obj_label)

# ============================================================================
# SIGNAL HANDLERS
# ============================================================================

func _on_mission_event(_player: int, _mission_id: String) -> void:
	refresh()
	_flash_header()

func _on_mission_scored(_player: int, _mission_id: String, _vp: int) -> void:
	refresh()
	_flash_header()

func _on_mission_discard_event(_player: int, _mission_id: String, _reason: String) -> void:
	refresh()

func _on_vp_scored(_player: int, _vp: int, _mission_id: String) -> void:
	refresh()
	_flash_header()

# ============================================================================
# HELPERS
# ============================================================================

func _flash_header() -> void:
	if not header_button:
		return
	var flash_tween = create_tween()
	flash_tween.tween_property(header_button, "modulate", Color(1.5, 1.2, 0.5), 0.15)
	flash_tween.tween_property(header_button, "modulate", Color.WHITE, 0.4)

func _add_label(parent: Control, text: String, font_size: int, color: Color) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _get_timing_display(timing: String) -> String:
	match timing:
		"end_of_your_turn":
			return "End of your turn"
		"end_of_either_turn":
			return "End of either turn"
		"end_of_opponent_turn":
			return "End of opponent's turn"
		"while_active":
			return "While active"
		_:
			return timing

func _humanize_check(check: String) -> String:
	return check.replace("_", " ").capitalize()

func _get_category_icon(category: String) -> String:
	match category.to_lower():
		"tactical": return "T"
		"strategic": return "S"
		"fixed": return "F"
		"shadow operations": return "X"
		"no mercy": return "!"
		"battlefield supremacy": return "B"
		"purge the enemy": return "P"
		_: return "?"

func _get_category_color(category: String) -> Color:
	match category.to_lower():
		"tactical": return Color(0.4, 0.7, 1.0)
		"strategic": return Color(0.8, 0.6, 1.0)
		"fixed": return Color(1.0, 0.85, 0.3)
		"shadow operations": return Color(0.6, 0.8, 0.5)
		"no mercy": return Color(1.0, 0.4, 0.3)
		"battlefield supremacy": return Color(0.3, 0.9, 0.7)
		"purge the enemy": return Color(1.0, 0.5, 0.2)
		_: return Color(0.6, 0.6, 0.6)
