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

	# Position: top-left, offset from edges to avoid overlap with HUD
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	offset_left = 8
	offset_top = 8
	offset_right = 8 + PANEL_WIDTH
	offset_bottom = 8 + HEADER_HEIGHT
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
		_add_label(content_container, "Missions not yet drawn\n(initialized in Command Phase)", 11, Color(0.5, 0.5, 0.5))
		return

	# Summary bar
	_build_summary(content_container, secondary_mgr, current_player)

	# Active missions for current player
	_add_label(content_container, "Player %d — Active Missions" % current_player, 12, _WhiteDwarfTheme.WH_GOLD)
	_build_player_missions(content_container, secondary_mgr, current_player)

	# Opponent summary (collapsed)
	var opponent = 2 if current_player == 1 else 1
	if secondary_mgr.is_initialized(opponent):
		content_container.add_child(HSeparator.new())
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
	var deck_size = mgr.get_deck_size(player)
	var discard_size = mgr.get_discard_size(player)
	var secondary_vp = mgr.get_secondary_vp(player)

	var summary = Label.new()
	summary.text = "Deck: %d  |  Discard: %d  |  VP: %d/40" % [deck_size, discard_size, secondary_vp]
	summary.add_theme_font_size_override("font_size", 11)
	summary.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_PARCHMENT)
	parent.add_child(summary)
	parent.add_child(HSeparator.new())

func _build_player_missions(parent: VBoxContainer, mgr, player: int) -> void:
	var active_missions = mgr.get_active_missions(player)

	if active_missions.size() == 0:
		_add_label(parent, "No active missions — draw in Command Phase", 11, Color(0.5, 0.5, 0.5))
		return

	for mission in active_missions:
		_build_mission_card(parent, mission)

func _build_mission_card(parent: VBoxContainer, mission: Dictionary) -> void:
	var card = PanelContainer.new()
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.12, 0.11, 0.09, 0.95)
	card_style.border_color = Color(0.4, 0.35, 0.15)
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(3)
	card_style.set_content_margin_all(6)
	card.add_theme_stylebox_override("panel", card_style)
	parent.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	card.add_child(vbox)

	# Mission name
	var name_label = Label.new()
	name_label.text = mission.get("name", "Unknown Mission")
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	vbox.add_child(name_label)

	# Category + scoring timing
	var scoring = mission.get("scoring", {})
	var timing_text = _get_timing_display(scoring.get("when", ""))
	var cat_label = Label.new()
	cat_label.text = "%s  —  %s" % [mission.get("category", ""), timing_text]
	cat_label.add_theme_font_size_override("font_size", 10)
	cat_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	vbox.add_child(cat_label)

	# VP conditions
	var conditions = scoring.get("conditions", [])
	for c in conditions:
		var vp = c.get("vp", 0)
		var check = c.get("check", "")
		var cond_label = Label.new()
		cond_label.text = "  %d VP — %s" % [vp, _humanize_check(check)]
		cond_label.add_theme_font_size_override("font_size", 10)
		cond_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
		cond_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(cond_label)

	# VP scored so far
	var vp_scored = mission.get("vp_scored", 0)
	if vp_scored > 0:
		var scored_label = Label.new()
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

# ============================================================================
# SIGNAL HANDLERS
# ============================================================================

func _on_mission_event(_player: int, _mission_id: String) -> void:
	if not is_collapsed:
		refresh()

func _on_mission_scored(_player: int, _mission_id: String, _vp: int) -> void:
	if not is_collapsed:
		refresh()

func _on_mission_discard_event(_player: int, _mission_id: String, _reason: String) -> void:
	if not is_collapsed:
		refresh()

func _on_vp_scored(_player: int, _vp: int, _mission_id: String) -> void:
	if not is_collapsed:
		refresh()

# ============================================================================
# HELPERS
# ============================================================================

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
	# Convert snake_case condition IDs into readable text
	return check.replace("_", " ").capitalize()
