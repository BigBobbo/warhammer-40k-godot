extends Node2D
class_name ScoringController

const BasePhase = preload("res://phases/BasePhase.gd")


# ScoringController - Handles UI interactions for the Scoring Phase
# Manages turn switching and battle round display

signal scoring_action_requested(action: Dictionary)
signal ui_update_requested()

# Scoring state
var current_phase = null  # Can be ScoringPhase or null

# UI References
var hud_bottom: Control
var hud_right: Control

# UI Elements
var battle_round_label: Label
var turn_info_label: Label

func _ready() -> void:
	_setup_ui_references()
	print("ScoringController ready")

func _exit_tree() -> void:
	# Clean up UI containers
	var scoring_controls = SceneRefs.main_path("HUD_Bottom/HBoxContainer/ScoringControls")
	if scoring_controls and is_instance_valid(scoring_controls):
		scoring_controls.queue_free()
	
	# Clean up right panel elements
	var container = SceneRefs.hud_right_vbox()
	if container and is_instance_valid(container):
		var scoring_elements = ["ScoringPanel", "ScoringScrollContainer"]
		for element in scoring_elements:
			var node = container.get_node_or_null(element)
			if node and is_instance_valid(node):
				print("ScoringController: Removing element: ", element)
				container.remove_child(node)
				node.queue_free()

func _setup_ui_references() -> void:
	# Get references to UI nodes
	hud_bottom = SceneRefs.hud_bottom()
	hud_right = SceneRefs.hud_right()
	
	# Setup scoring-specific UI elements
	if hud_bottom:
		_setup_bottom_hud()
	if hud_right:
		_setup_right_panel()

func _setup_bottom_hud() -> void:
	# NOTE: Main.gd now handles the phase action button (End Turn)
	# ScoringController only manages scoring-specific UI in the right panel

	# Get the main HBox container in bottom HUD for labels
	var main_container = hud_bottom.get_node_or_null("HBoxContainer")
	if not main_container:
		print("ERROR: Cannot find HBoxContainer in HUD_Bottom")
		return

	# Check for existing scoring controls container (for info labels only)
	var controls_container = main_container.get_node_or_null("ScoringControls")
	if not controls_container:
		controls_container = HBoxContainer.new()
		controls_container.name = "ScoringControls"
		main_container.add_child(controls_container)

		# Add separator before scoring controls
		controls_container.add_child(VSeparator.new())
	else:
		# Clear existing children to prevent duplicates
		print("ScoringController: Removing existing scoring controls children (", controls_container.get_children().size(), " children)")
		for child in controls_container.get_children():
			controls_container.remove_child(child)
			child.free()

	# Battle round info — styled
	battle_round_label = Label.new()
	battle_round_label.text = "Round " + str(GameState.get_battle_round()) + "/5"
	battle_round_label.name = "BattleRoundLabel"
	battle_round_label.add_theme_font_size_override("font_size", 13)
	battle_round_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes:
		battle_round_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	controls_container.add_child(battle_round_label)

	# Separator
	controls_container.add_child(VSeparator.new())

	# Turn info — show faction name
	turn_info_label = Label.new()
	var current_player = GameState.get_active_player()
	var faction = GameState.get_faction_name(current_player)
	if faction == "":
		faction = "Player %d" % current_player
	turn_info_label.text = "%s Turn" % faction
	turn_info_label.name = "TurnInfoLabel"
	turn_info_label.add_theme_font_size_override("font_size", 13)
	var player_color = FactionPalettes.get_player_border_color(current_player) if FactionPalettes else WhiteDwarfTheme.WH_PARCHMENT
	turn_info_label.add_theme_color_override("font_color", player_color)
	if FactionPalettes:
		turn_info_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_SEMIBOLD)
	controls_container.add_child(turn_info_label)

func _setup_right_panel() -> void:
	# Check for existing VBoxContainer in HUD_Right
	var container = hud_right.get_node_or_null("VBoxContainer")
	if not container:
		container = VBoxContainer.new()
		container.name = "VBoxContainer"
		hud_right.add_child(container)

	# Create scroll container for scoring panel
	var scroll_container = ScrollContainer.new()
	scroll_container.name = "ScoringScrollContainer"
	scroll_container.custom_minimum_size = Vector2(250, 400)
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(scroll_container)

	var scoring_panel = VBoxContainer.new()
	scoring_panel.name = "ScoringPanel"
	scoring_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(scoring_panel)

	# Title — uppercase gold gothic header
	var title = Label.new()
	title.text = "SCORING PHASE"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes:
		title.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scoring_panel.add_child(title)

	_add_gold_separator(scoring_panel)

	var battle_round = GameState.get_battle_round()
	var current_player = GameState.get_active_player()
	var total_rounds = 5

	# Round indicator
	var round_label = Label.new()
	round_label.text = "BATTLE ROUND %d/%d" % [battle_round, total_rounds]
	round_label.add_theme_font_size_override("font_size", 13)
	round_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes:
		round_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scoring_panel.add_child(round_label)

	scoring_panel.add_child(_create_spacer(4))

	# VP Summary — visual scoreboard with bars
	var vp_summary = MissionManager.get_vp_summary()
	_build_vp_scoreboard(scoring_panel, vp_summary)

	_add_gold_separator(scoring_panel)

	# Objective Control display
	_build_objective_control_section(scoring_panel, current_player)

	# 11e GDM card-action marker state — make the players' picks reviewable
	# off-board (Triangulated/Decoys/traps/Condemned/...)
	if GameConstants.edition >= 11 and MissionManager and MissionManager.has_method("get_card_action_summary_11e"):
		for p in [1, 2]:
			var marker_lines: Array = MissionManager.get_card_action_summary_11e(p)
			if marker_lines.is_empty():
				continue
			var marker_label = Label.new()
			marker_label.name = "P%dCardActionState" % p
			var line_strs = []
			for l in marker_lines:
				line_strs.append(str(l))
			marker_label.text = "P%d markers — %s" % [p, " | ".join(PackedStringArray(line_strs))]
			marker_label.add_theme_font_size_override("font_size", 11)
			marker_label.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
			marker_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			scoring_panel.add_child(marker_label)

	_add_gold_separator(scoring_panel)

	# Secondary Missions display with discard buttons and progress tracking
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if secondary_mgr and secondary_mgr.is_initialized(current_player):
		var missions_title = Label.new()
		missions_title.text = "ACTIVE SECONDARY MISSIONS"
		missions_title.add_theme_font_size_override("font_size", 13)
		missions_title.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
		if FactionPalettes:
			missions_title.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
		scoring_panel.add_child(missions_title)

		var active_missions = secondary_mgr.get_active_missions(current_player)
		# Get live progress data for all active missions
		var progress_data = secondary_mgr.evaluate_mission_progress(current_player)
		var progress_by_id = {}
		for p in progress_data:
			progress_by_id[p["mission_id"]] = p

		if active_missions.size() == 0:
			var no_missions = Label.new()
			no_missions.text = "  No active secondary missions"
			scoring_panel.add_child(no_missions)
		else:
			for i in range(active_missions.size()):
				var mission = active_missions[i]
				var mission_progress = progress_by_id.get(mission.get("id", ""), {})
				_add_mission_card(scoring_panel, mission, i, mission_progress)

		# Deck info
		var deck_label = Label.new()
		deck_label.text = "Deck: %d remaining | Discarded: %d" % [
			secondary_mgr.get_deck_size(current_player),
			secondary_mgr.get_discard_size(current_player)]
		deck_label.add_theme_font_size_override("font_size", 11)
		deck_label.add_theme_color_override("font_color", Color(0.55, 0.52, 0.45))
		scoring_panel.add_child(deck_label)

		_add_gold_separator(scoring_panel)

	# Game end check
	if GameState.get_battle_round() > 5:
		var game_end_label = Label.new()
		game_end_label.text = "GAME COMPLETE!"
		game_end_label.add_theme_font_size_override("font_size", 18)
		game_end_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
		if FactionPalettes:
			game_end_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
		game_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		game_end_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		scoring_panel.add_child(game_end_label)
		var sub_label = Label.new()
		sub_label.text = "5 Battle Rounds finished"
		sub_label.add_theme_font_size_override("font_size", 12)
		sub_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_PARCHMENT)
		sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		scoring_panel.add_child(sub_label)
	else:
		var instruction_label = Label.new()
		var cp_note = "+1 CP" if GameState.can_gain_bonus_cp(GameState.get_active_player()) else "+0 CP (cap reached)"
		instruction_label.text = "Discard a secondary for %s, or End Turn." % cp_note
		instruction_label.add_theme_font_size_override("font_size", 11)
		instruction_label.add_theme_color_override("font_color", Color(0.55, 0.52, 0.45))
		instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		scoring_panel.add_child(instruction_label)

func _build_objective_control_section(panel: VBoxContainer, _current_player: int) -> void:
	var obj_title = Label.new()
	obj_title.text = "OBJECTIVE CONTROL"
	obj_title.add_theme_font_size_override("font_size", 13)
	obj_title.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes:
		obj_title.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	panel.add_child(obj_title)

	var objectives = GameState.state.board.get("objectives", [])
	var control_state = MissionManager.objective_control_state

	if objectives.size() == 0:
		var no_obj = Label.new()
		no_obj.text = "No objectives on the board"
		no_obj.add_theme_font_size_override("font_size", 11)
		no_obj.add_theme_color_override("font_color", Color(0.55, 0.52, 0.45))
		panel.add_child(no_obj)
		return

	var p1_controlled = 0
	var p2_controlled = 0
	var contested = 0
	var p1_color = FactionPalettes.get_player_border_color(1) if FactionPalettes else Color(0.4, 0.6, 1.0)
	var p2_color = FactionPalettes.get_player_border_color(2) if FactionPalettes else Color(1.0, 0.4, 0.4)

	for obj in objectives:
		var obj_id = obj.get("id", "unknown")
		var zone = obj.get("zone", "unknown")
		var controller = control_state.get(obj_id, 0)

		var controller_text = "Contested"
		var obj_color = Color(0.8, 0.8, 0.3)
		if controller == 1:
			controller_text = GameState.get_faction_name(1) if GameState.get_faction_name(1) != "" else "Player 1"
			p1_controlled += 1
			obj_color = p1_color
		elif controller == 2:
			controller_text = GameState.get_faction_name(2) if GameState.get_faction_name(2) != "" else "Player 2"
			p2_controlled += 1
			obj_color = p2_color
		else:
			contested += 1

		var zone_text = ""
		match zone:
			"player1": zone_text = "P1"
			"player2": zone_text = "P2"
			"no_mans_land": zone_text = "NML"
			_: zone_text = zone

		var display_id = obj_id.replace("obj_", "").to_upper().replace("_", " ")
		var obj_label = Label.new()
		obj_label.text = "%s [%s]: %s" % [display_id, zone_text, controller_text]
		obj_label.add_theme_font_size_override("font_size", 11)
		obj_label.add_theme_color_override("font_color", obj_color)
		panel.add_child(obj_label)

	# Summary line with faction colors
	panel.add_child(_create_spacer(2))
	var summary_hbox = HBoxContainer.new()
	summary_hbox.add_theme_constant_override("separation", 8)
	var p1_sum = Label.new()
	p1_sum.text = "P1: %d" % p1_controlled
	p1_sum.add_theme_font_size_override("font_size", 12)
	p1_sum.add_theme_color_override("font_color", p1_color)
	if FactionPalettes:
		p1_sum.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	summary_hbox.add_child(p1_sum)
	var p2_sum = Label.new()
	p2_sum.text = "P2: %d" % p2_controlled
	p2_sum.add_theme_font_size_override("font_size", 12)
	p2_sum.add_theme_color_override("font_color", p2_color)
	if FactionPalettes:
		p2_sum.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	summary_hbox.add_child(p2_sum)
	if contested > 0:
		var cont_sum = Label.new()
		cont_sum.text = "Contested: %d" % contested
		cont_sum.add_theme_font_size_override("font_size", 12)
		cont_sum.add_theme_color_override("font_color", Color(0.8, 0.8, 0.3))
		summary_hbox.add_child(cont_sum)
	panel.add_child(summary_hbox)

	# Mission info — at e11 (GDM 2026) each player scores their OWN
	# disposition-paired primary card, so show both instead of the shared
	# 10e mission name. "~" marks cards built from approximate source rows.
	if GameConstants.edition >= 11 and not MissionManager.player_primary_missions.is_empty():
		for p in [1, 2]:
			var card = MissionManager.get_primary_mission_for_player(p)
			var disp = MissionManager.player_dispositions.get(str(p), "")
			var card_label = Label.new()
			card_label.name = "P%dPrimaryMissionLabel" % p
			card_label.text = "P%d Primary: %s%s (%s)" % [
				p, card.get("name", "?"),
				" ~" if card.get("approximate", false) else "",
				PrimaryMissionData11e.get_disposition_name(disp)]
			card_label.add_theme_font_size_override("font_size", 11)
			card_label.add_theme_color_override("font_color", Color(0.55, 0.52, 0.45))
			panel.add_child(card_label)
	else:
		var mission_name = MissionManager.get_current_mission_name()
		var mission_info = Label.new()
		mission_info.text = "Mission: %s" % mission_name
		mission_info.add_theme_font_size_override("font_size", 11)
		mission_info.add_theme_color_override("font_color", Color(0.55, 0.52, 0.45))
		panel.add_child(mission_info)

func _add_gold_separator(parent: VBoxContainer) -> void:
	var sep = ColorRect.new()
	sep.color = Color(WhiteDwarfTheme.WH_GOLD, 0.3)
	sep.custom_minimum_size = Vector2(0, 1)
	parent.add_child(sep)
	parent.add_child(_create_spacer(2))

func _create_spacer(height: float) -> Control:
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer

func _build_vp_scoreboard(parent: VBoxContainer, vp_summary: Dictionary) -> void:
	var p1_total = vp_summary["player1"]["total"]
	var p1_primary = vp_summary["player1"]["primary"]
	var p1_secondary = vp_summary["player1"]["secondary"]
	var p2_total = vp_summary["player2"]["total"]
	var p2_primary = vp_summary["player2"]["primary"]
	var p2_secondary = vp_summary["player2"]["secondary"]

	var p1_color = FactionPalettes.get_player_border_color(1) if FactionPalettes else Color(0.4, 0.6, 1.0)
	var p2_color = FactionPalettes.get_player_border_color(2) if FactionPalettes else Color(1.0, 0.4, 0.4)
	var p1_faction = GameState.get_faction_name(1) if GameState else "Player 1"
	var p2_faction = GameState.get_faction_name(2) if GameState else "Player 2"
	if p1_faction == "": p1_faction = "Player 1"
	if p2_faction == "": p2_faction = "Player 2"

	var vp_title = Label.new()
	vp_title.text = "VP SUMMARY"
	vp_title.add_theme_font_size_override("font_size", 12)
	vp_title.add_theme_color_override("font_color", Color(WhiteDwarfTheme.WH_GOLD, 0.7))
	if FactionPalettes:
		vp_title.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	parent.add_child(vp_title)

	_add_vp_player_row(parent, p1_faction, p1_total, p1_primary, p1_secondary, p1_color)
	_add_vp_player_row(parent, p2_faction, p2_total, p2_primary, p2_secondary, p2_color)

func _add_vp_player_row(parent: VBoxContainer, faction: String, total: int, primary: int, secondary: int, color: Color) -> void:
	var card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.08)
	style.border_color = Color(color.r, color.g, color.b, 0.3)
	style.border_width_left = 3
	style.set_corner_radius_all(3)
	style.set_content_margin_all(4)
	style.content_margin_left = 8
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)

	# NOTE: the hbox is parented at the END, inside the vbox. It used to be
	# added to `card` here and then re-added to the vbox WITHOUT reparenting
	# — add_child failed ("already has a parent") and the faction/VP labels
	# were silently orphaned from the panel.
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)

	var name_label = Label.new()
	name_label.text = faction
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", color)
	if FactionPalettes:
		name_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_label)

	var vp_label = Label.new()
	vp_label.text = "%d VP" % total
	vp_label.add_theme_font_size_override("font_size", 16)
	vp_label.add_theme_color_override("font_color", color)
	if FactionPalettes:
		vp_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	hbox.add_child(vp_label)

	# VP breakdown below the main row
	var breakdown = Label.new()
	breakdown.text = "Primary: %d | Secondary: %d" % [primary, secondary]
	breakdown.add_theme_font_size_override("font_size", 10)
	breakdown.add_theme_color_override("font_color", Color(color.r, color.g, color.b, 0.6))
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	vbox.add_child(hbox)
	vbox.add_child(breakdown)
	card.add_child(vbox)

func _add_mission_card(parent: VBoxContainer, mission: Dictionary, index: int, progress: Dictionary = {}) -> void:
	var card_container = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.9)
	style.border_color = Color(0.4, 0.35, 0.15)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	card_container.add_theme_stylebox_override("panel", style)
	parent.add_child(card_container)

	var card_vbox = VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 2)
	card_container.add_child(card_vbox)

	# Mission name + best VP indicator
	var name_label = Label.new()
	var best_vp = progress.get("best_vp_available", 0)
	if best_vp > 0:
		name_label.text = "%s [%d VP ready]" % [mission.get("name", "Unknown Mission"), best_vp]
		name_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	else:
		name_label.text = mission.get("name", "Unknown Mission")
		name_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	name_label.add_theme_font_size_override("font_size", 13)
	card_vbox.add_child(name_label)

	# Category
	var cat_label = Label.new()
	cat_label.text = mission.get("category", "").capitalize()
	cat_label.add_theme_font_size_override("font_size", 10)
	cat_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	card_vbox.add_child(cat_label)

	# Scoring info
	var scoring = mission.get("scoring", {})
	var timing = scoring.get("when", "")
	var timing_text = _get_timing_display(timing)
	var conditions = scoring.get("conditions", [])
	var max_vp = 0
	for c in conditions:
		max_vp = max(max_vp, c.get("vp", 0))
	var scoring_label = Label.new()
	scoring_label.text = "Up to %d VP | %s" % [max_vp, timing_text]
	scoring_label.add_theme_font_size_override("font_size", 10)
	scoring_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	card_vbox.add_child(scoring_label)

	# VP scored so far
	var vp_scored = mission.get("vp_scored", 0)
	if vp_scored > 0:
		var scored_label = Label.new()
		scored_label.text = "Scored: %d VP" % vp_scored
		scored_label.add_theme_font_size_override("font_size", 10)
		scored_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
		card_vbox.add_child(scored_label)

	# Condition progress tracking
	var condition_progress = progress.get("conditions", [])
	if condition_progress.size() > 0:
		for cond in condition_progress:
			var cond_label = Label.new()
			var met = cond.get("met", false)
			var vp = cond.get("vp", 0)
			var desc = cond.get("description", cond.get("check", "?"))
			if met:
				cond_label.text = "  [MET] %d VP - %s" % [vp, desc]
				cond_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
			else:
				cond_label.text = "  [---] %d VP - %s" % [vp, desc]
				cond_label.add_theme_color_override("font_color", Color(0.6, 0.4, 0.4))
			cond_label.add_theme_font_size_override("font_size", 10)
			cond_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			card_vbox.add_child(cond_label)

	# Pending interaction indicator
	if mission.get("pending_interaction", false):
		var pending_label = Label.new()
		pending_label.text = "AWAITING INTERACTION"
		pending_label.add_theme_font_size_override("font_size", 10)
		pending_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
		card_vbox.add_child(pending_label)

	# Discard button — styled with WhiteDwarf theme
	var discard_btn = Button.new()
	var can_gain_cp = GameState.can_gain_bonus_cp(GameState.get_active_player())
	var cp_label_text = "+1 CP" if can_gain_cp else "+0 CP (cap)"
	discard_btn.text = "Discard (%s)" % cp_label_text
	discard_btn.custom_minimum_size = Vector2(0, 26)
	discard_btn.add_theme_font_size_override("font_size", 11)
	WhiteDwarfTheme.apply_secondary_button(discard_btn)
	var tooltip = "Voluntarily discard this mission and gain 1 CP." if can_gain_cp else "Voluntarily discard this mission (bonus CP cap reached this round — no CP gained)."
	discard_btn.tooltip_text = tooltip
	discard_btn.pressed.connect(_on_discard_pressed.bind(index))
	card_vbox.add_child(discard_btn)

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

func _on_discard_pressed(mission_index: int) -> void:
	if GameState.is_game_complete():
		print("ScoringController: Game is already complete, cannot discard")
		return

	var current_player = GameState.get_active_player()
	print("ScoringController: Discard requested for mission index %d by player %d" % [mission_index, current_player])
	emit_signal("scoring_action_requested", {
		"type": "DISCARD_SECONDARY",
		"mission_index": mission_index,
		"player": current_player,
	})

func _rebuild_right_panel() -> void:
	if not hud_right:
		return

	# Remove existing scoring panel elements
	var container = hud_right.get_node_or_null("VBoxContainer")
	if container and is_instance_valid(container):
		var scoring_elements = ["ScoringScrollContainer"]
		for element in scoring_elements:
			var node = container.get_node_or_null(element)
			if node and is_instance_valid(node):
				container.remove_child(node)
				node.queue_free()

	# Rebuild the panel with fresh data
	_setup_right_panel()

func set_phase(phase: BasePhase) -> void:
	current_phase = phase

	if phase:
		# Connect Acrobatic Escape vanish signal
		if phase.has_signal("acrobatic_escape_vanish_available") and not phase.acrobatic_escape_vanish_available.is_connected(_on_acrobatic_escape_vanish_available):
			phase.acrobatic_escape_vanish_available.connect(_on_acrobatic_escape_vanish_available)

		# Connect end-of-turn redeploy signal (From Golden Light, etc.)
		if phase.has_signal("end_turn_redeploy_available") and not phase.end_turn_redeploy_available.is_connected(_on_end_turn_redeploy_available):
			phase.end_turn_redeploy_available.connect(_on_end_turn_redeploy_available)

		# Connect 03.03 out-of-coherency removal choice (audit #16)
		if phase.has_signal("coherency_removal_required") and not phase.coherency_removal_required.is_connected(_on_coherency_removal_required):
			phase.coherency_removal_required.connect(_on_coherency_removal_required)

		# Connect 11e GDM primary card-action target choice
		if phase.has_signal("card_action_choice_required") and not phase.card_action_choice_required.is_connected(_on_card_action_choice_required):
			phase.card_action_choice_required.connect(_on_card_action_choice_required)

		# Belt-and-braces for the signal-timing gap: if the phase is already
		# awaiting a card-action choice (e.g. controller rebuilt while the
		# gate is up), re-show the dialog from the pending state.
		if phase.get("_awaiting_card_action"):
			var pending_ca = phase.get("_card_action_pending")
			if pending_ca is Dictionary and not pending_ca.is_empty():
				call_deferred("_show_card_action_dialog", pending_ca, int(pending_ca.get("player", GameState.get_active_player())))

		# Update UI elements with current game state
		_refresh_ui()
		show()
	else:
		hide()

func _refresh_ui() -> void:
	# Update battle round label
	if battle_round_label:
		battle_round_label.text = "Battle Round " + str(GameState.get_battle_round())

	# Update turn info label
	if turn_info_label:
		var current_player = GameState.get_active_player()
		turn_info_label.text = "Player %d Turn" % current_player

	# Rebuild right panel to reflect current mission state
	_rebuild_right_panel()

	# Check if game is complete
	if GameState.is_game_complete():
		# Main.gd will handle disabling the phase action button
		print("ScoringController: Game is complete after 5 battle rounds!")

func _on_end_turn_pressed() -> void:
	if GameState.is_game_complete():
		print("ScoringController: Game is already complete, cannot end turn")
		return

	print("ScoringController: End Turn button pressed")
	emit_signal("scoring_action_requested", {"type": "END_TURN"})

# ============================================================================
# 03.03 OUT-OF-COHERENCY REMOVAL (End of Turn, audit #16)
# ============================================================================

func _on_coherency_removal_required(pending: Array, _player: int) -> void:
	"""11e 03.03: the player chooses which model(s) to remove from
	out-of-coherency units before the turn can end."""
	print("[ScoringController] 03.03 coherency removal required for %d unit(s)" % pending.size())
	_show_coherency_removal_dialog(pending)

func _show_coherency_removal_dialog(pending: Array) -> void:
	var dialog = AcceptDialog.new()
	dialog.name = "CoherencyRemovalDialog"
	dialog.title = "Out of Coherency — Remove Models (03.03)"
	dialog.min_size = DialogConstants.MEDIUM
	dialog.get_ok_button().visible = false
	WhiteDwarfTheme.apply_to_dialog(dialog)

	var content = VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 8)
	content.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	var header = Label.new()
	header.text = "REGAINING COHERENCY"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(header)
	content.add_child(HSeparator.new())

	var desc = Label.new()
	desc.text = "These units end the turn out of unit coherency. Choose a model to remove (destroyed, no on-death rules) until each unit is coherent."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(desc)

	for entry in pending:
		content.add_child(HSeparator.new())
		var unit_label = Label.new()
		unit_label.text = "%s (Player %d)" % [entry.unit_name, entry.player]
		unit_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
		content.add_child(unit_label)
		var row = HBoxContainer.new()
		row.name = "Row_%s" % str(entry.unit_id)
		row.add_theme_constant_override("separation", 6)
		for model_id in entry.offenders:
			var btn = Button.new()
			btn.name = "Remove_%s_%s" % [str(entry.unit_id), str(model_id)]
			btn.text = "Remove %s" % str(model_id)
			var uid: String = str(entry.unit_id)
			var mid: String = str(model_id)
			btn.pressed.connect(func():
				emit_signal("scoring_action_requested", {
					"type": "REMOVE_MODEL_FOR_COHERENCY",
					"unit_id": uid,
					"model_id": mid,
				})
				dialog.queue_free()
				call_deferred("_recheck_coherency_removal"))
			row.add_child(btn)
		content.add_child(row)

	dialog.add_child(content)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()

func _recheck_coherency_removal() -> void:
	# After each removal: re-open the dialog while units remain incoherent;
	# when the phase clears the gate, finish the turn the player asked for.
	if current_phase and is_instance_valid(current_phase) \
			and current_phase.get("_awaiting_coherency_removal"):
		_show_coherency_removal_dialog(current_phase.get("_coherency_removal_pending"))
	else:
		print("[ScoringController] 03.03 coherency restored — re-dispatching END_TURN")
		emit_signal("scoring_action_requested", {"type": "END_TURN"})

# ============================================================================
# 11e GDM PRIMARY CARD ACTION CHOICE (End of Turn)
# ============================================================================

func _on_card_action_choice_required(pending: Dictionary, player: int) -> void:
	"""The active player's primary mission card grants an optional end-of-turn
	action (Triangulate, Decoy, Booby Trap, ...) — let them pick the targets."""
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(player):
		# Should not happen (the phase gate skips AI players) — backstop only.
		print("[ScoringController] Card action choice for AI P%d — skipping dialog" % player)
		return
	print("[ScoringController] 11e card action choice for P%d: %s (%d targets)" % [
		player, pending.get("action_name", "?"), pending.get("targets", []).size()])
	_show_card_action_dialog(pending, player)

func _show_card_action_dialog(pending: Dictionary, player: int) -> void:
	# A just-queue_free'd dialog still occupies the name for a frame — treat
	# it as absent so a legitimate re-show is never suppressed.
	var existing = get_tree().root.get_node_or_null("CardActionDialog")
	if existing != null and not existing.is_queued_for_deletion():
		return
	var dialog = AcceptDialog.new()
	dialog.name = "CardActionDialog"
	dialog.title = "%s — %s" % [pending.get("card_name", "Primary Mission"), pending.get("action_name", "Card Action")]
	dialog.min_size = DialogConstants.MEDIUM
	dialog.get_ok_button().visible = false
	WhiteDwarfTheme.apply_to_dialog(dialog)

	var content = VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 8)
	content.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	var header = Label.new()
	header.text = str(pending.get("action_name", "CARD ACTION")).to_upper()
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(header)
	content.add_child(HSeparator.new())

	var desc = Label.new()
	desc.text = str(pending.get("description", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(desc)
	content.add_child(HSeparator.new())

	# Double-fire guard shared by target buttons / confirm / skip / cancel
	var resolved = [false]
	var multi_mode: bool = str(pending.get("mode", "single")) == "multi"
	var checkboxes: Array = []

	for target in pending.get("targets", []):
		var tid: String = str(target.get("id", ""))
		var tlabel: String = str(target.get("label", tid))
		if multi_mode:
			var check = CheckBox.new()
			check.name = "Check_%s" % tid
			check.text = tlabel
			# Default all-selected mirrors the auto-resolve (Decoy/Extract
			# Intelligence place on every eligible objective).
			check.button_pressed = true
			check.set_meta("target_id", tid)
			content.add_child(check)
			checkboxes.append(check)
		else:
			var btn = Button.new()
			btn.name = "Pick_%s" % tid
			btn.text = tlabel
			btn.pressed.connect(func():
				if resolved[0]:
					return
				resolved[0] = true
				emit_signal("scoring_action_requested", {
					"type": "RESOLVE_CARD_ACTION",
					"targets": [tid],
					"player": player,
				})
				dialog.queue_free()
				call_deferred("_recheck_card_action"))
			content.add_child(btn)

	content.add_child(HSeparator.new())
	var button_row = HBoxContainer.new()
	button_row.name = "Actions"
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 12)

	if multi_mode:
		var confirm_btn = Button.new()
		confirm_btn.name = "ConfirmCardAction"
		confirm_btn.text = "Confirm Selection"
		confirm_btn.custom_minimum_size = Vector2(170, 36)
		confirm_btn.pressed.connect(func():
			if resolved[0]:
				return
			resolved[0] = true
			var picks = []
			for check in checkboxes:
				if is_instance_valid(check) and check.button_pressed:
					picks.append(str(check.get_meta("target_id")))
			emit_signal("scoring_action_requested", {
				"type": "RESOLVE_CARD_ACTION",
				"targets": picks,
				"player": player,
			})
			dialog.queue_free()
			call_deferred("_recheck_card_action"))
		button_row.add_child(confirm_btn)

	var skip_btn = Button.new()
	skip_btn.name = "SkipCardAction"
	skip_btn.text = "Skip (no action this turn)"
	skip_btn.custom_minimum_size = Vector2(190, 36)
	skip_btn.pressed.connect(func():
		if resolved[0]:
			return
		resolved[0] = true
		emit_signal("scoring_action_requested", {
			"type": "SKIP_CARD_ACTION",
			"player": player,
		})
		dialog.queue_free()
		call_deferred("_recheck_card_action"))
	button_row.add_child(skip_btn)
	content.add_child(button_row)

	# Escape/close is never a dead end: treat it as Skip so END_TURN can finish.
	dialog.canceled.connect(func():
		if resolved[0]:
			return
		resolved[0] = true
		emit_signal("scoring_action_requested", {
			"type": "SKIP_CARD_ACTION",
			"player": player,
		})
		dialog.queue_free()
		call_deferred("_recheck_card_action"))

	dialog.add_child(content)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()

func _recheck_card_action() -> void:
	# After resolve/skip the gate should be down — finish the turn the player
	# asked for. If the phase still awaits (resolve rejected), re-show.
	if current_phase and is_instance_valid(current_phase) \
			and current_phase.get("_awaiting_card_action"):
		var pending = current_phase.get("_card_action_pending")
		if pending is Dictionary and not pending.is_empty():
			_show_card_action_dialog(pending, int(pending.get("player", GameState.get_active_player())))
	else:
		print("[ScoringController] 11e card action resolved — re-dispatching END_TURN")
		emit_signal("scoring_action_requested", {"type": "END_TURN"})

# ============================================================================
# ACROBATIC ESCAPE VANISH (End of opponent's turn)
# ============================================================================

func _on_acrobatic_escape_vanish_available(unit_id: String, unit_name: String, player: int) -> void:
	"""Show dialog offering to remove the Callidus from the battlefield."""
	print("[ScoringController] Acrobatic Escape vanish available for %s (player %d)" % [unit_name, player])

	# Skip dialog for AI players
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(player):
		print("[ScoringController] Skipping Acrobatic Escape vanish dialog for AI player %d" % player)
		return

	var dialog = AcceptDialog.new()
	dialog.title = "Acrobatic Escape: %s" % unit_name
	dialog.min_size = DialogConstants.MEDIUM
	dialog.get_ok_button().visible = false
	WhiteDwarfTheme.apply_to_dialog(dialog)

	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	var header = Label.new()
	header.text = "ACROBATIC ESCAPE"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(header)

	content.add_child(HSeparator.new())

	var desc = Label.new()
	desc.text = "%s is not within 3\" of any enemy units.\n\nRemove this model from the battlefield?\nIt will return in the Reinforcements step of your next Movement phase (more than 9\" from all enemies).\n\nWARNING: If the battle ends while this model is off the battlefield, it is destroyed." % unit_name
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(desc)

	content.add_child(HSeparator.new())

	var timer_label = Label.new()
	timer_label.text = "Auto-declining in 15 seconds..."
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 12)
	timer_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	content.add_child(timer_label)

	# Track whether dialog has been resolved to prevent double-fire
	var resolved = [false]

	var on_confirmed = func():
		if resolved[0]:
			return
		resolved[0] = true
		print("[ScoringController] Acrobatic Escape vanish confirmed for %s" % unit_id)
		emit_signal("scoring_action_requested", {
			"type": "ACROBATIC_ESCAPE_VANISH",
			"unit_id": unit_id,
			"player": player,
		})
		dialog.hide()
		dialog.queue_free()

	var on_declined = func():
		if resolved[0]:
			return
		resolved[0] = true
		print("[ScoringController] Acrobatic Escape vanish declined for %s" % unit_id)
		emit_signal("scoring_action_requested", {
			"type": "DECLINE_ACROBATIC_ESCAPE_VANISH",
			"unit_id": unit_id,
			"player": player,
		})
		dialog.hide()
		dialog.queue_free()

	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER

	var vanish_button = Button.new()
	vanish_button.text = "Vanish"
	vanish_button.custom_minimum_size = Vector2(180, 45)
	vanish_button.pressed.connect(on_confirmed)
	button_container.add_child(vanish_button)

	var btn_spacer = Control.new()
	btn_spacer.custom_minimum_size = Vector2(20, 0)
	button_container.add_child(btn_spacer)

	var stay_button = Button.new()
	stay_button.text = "Stay"
	stay_button.custom_minimum_size = Vector2(150, 45)
	stay_button.pressed.connect(on_declined)
	button_container.add_child(stay_button)

	content.add_child(button_container)
	dialog.add_child(content)

	get_tree().root.add_child(dialog)
	dialog.popup_centered()

	# 60-second countdown timer
	var time_remaining = [60.0]
	var countdown_timer = Timer.new()
	countdown_timer.wait_time = 1.0
	countdown_timer.autostart = true
	countdown_timer.timeout.connect(func():
		time_remaining[0] -= 1.0
		if timer_label and is_instance_valid(timer_label):
			if time_remaining[0] <= 5:
				timer_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
			timer_label.text = "Auto-declining in %d seconds..." % int(time_remaining[0])
		if time_remaining[0] <= 0:
			countdown_timer.stop()
			print("[ScoringController] Timer expired — auto-declining vanish for %s" % unit_id)
			on_declined.call()
	)
	dialog.add_child(countdown_timer)

# ============================================================================
# END-OF-TURN REDEPLOY (From Golden Light, Guerrilla Tactics, etc.)
# ============================================================================

func _on_end_turn_redeploy_available(unit_id: String, unit_name: String, player: int, ability_name: String) -> void:
	print("[ScoringController] End-of-turn redeploy available for %s (player %d) via %s" % [unit_name, player, ability_name])

	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(player):
		print("[ScoringController] Skipping end-of-turn redeploy dialog for AI player %d" % player)
		return

	var dialog = AcceptDialog.new()
	dialog.title = "%s: %s" % [ability_name, unit_name]
	dialog.min_size = DialogConstants.MEDIUM
	dialog.get_ok_button().visible = false
	WhiteDwarfTheme.apply_to_dialog(dialog)

	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	var header = Label.new()
	header.text = ability_name.to_upper()
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(header)

	content.add_child(HSeparator.new())

	var desc = Label.new()
	desc.text = "%s is not within Engagement Range of any enemy units.\n\nRemove this unit from the battlefield and place into Strategic Reserves?\nIt will return in the Reinforcements step of your next Movement phase (more than 9\" from all enemies).\n\nThis ability can only be used once per battle." % unit_name
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(desc)

	content.add_child(HSeparator.new())

	var timer_label = Label.new()
	timer_label.text = "Auto-declining in 15 seconds..."
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 12)
	timer_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	content.add_child(timer_label)

	var resolved = [false]

	var on_confirmed = func():
		if resolved[0]:
			return
		resolved[0] = true
		print("[ScoringController] End-of-turn redeploy confirmed for %s via %s" % [unit_id, ability_name])
		emit_signal("scoring_action_requested", {
			"type": "END_TURN_REDEPLOY",
			"unit_id": unit_id,
			"player": player,
		})
		dialog.hide()
		dialog.queue_free()

	var on_declined = func():
		if resolved[0]:
			return
		resolved[0] = true
		print("[ScoringController] End-of-turn redeploy declined for %s" % unit_id)
		emit_signal("scoring_action_requested", {
			"type": "DECLINE_END_TURN_REDEPLOY",
			"unit_id": unit_id,
			"player": player,
		})
		dialog.hide()
		dialog.queue_free()

	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER

	var redeploy_button = Button.new()
	redeploy_button.text = "Redeploy to Reserves"
	redeploy_button.custom_minimum_size = Vector2(200, 45)
	redeploy_button.pressed.connect(on_confirmed)
	button_container.add_child(redeploy_button)

	var btn_spacer = Control.new()
	btn_spacer.custom_minimum_size = Vector2(20, 0)
	button_container.add_child(btn_spacer)

	var stay_button = Button.new()
	stay_button.text = "Stay on Battlefield"
	stay_button.custom_minimum_size = Vector2(180, 45)
	stay_button.pressed.connect(on_declined)
	button_container.add_child(stay_button)

	content.add_child(button_container)
	dialog.add_child(content)

	get_tree().root.add_child(dialog)
	dialog.popup_centered()

	var time_remaining = [60.0]
	var countdown_timer = Timer.new()
	countdown_timer.wait_time = 1.0
	countdown_timer.autostart = true
	countdown_timer.timeout.connect(func():
		time_remaining[0] -= 1.0
		if timer_label and is_instance_valid(timer_label):
			if time_remaining[0] <= 5:
				timer_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
			timer_label.text = "Auto-declining in %d seconds..." % int(time_remaining[0])
		if time_remaining[0] <= 0:
			countdown_timer.stop()
			print("[ScoringController] Timer expired — auto-declining redeploy for %s" % unit_id)
			on_declined.call()
	)
	dialog.add_child(countdown_timer)
