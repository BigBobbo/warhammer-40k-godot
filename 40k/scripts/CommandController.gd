extends Node2D
class_name CommandController

const BasePhase = preload("res://phases/BasePhase.gd")
const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")


# CommandController - Handles UI interactions for the Command Phase
# Displays CP totals, objective control status, and victory points

signal command_action_requested(action: Dictionary)
signal ui_update_requested()

# Command state
var current_phase = null  # Can be CommandPhase or null

# UI References
var hud_bottom: Control
var hud_right: Control

# UI Elements
var phase_info_label: Label
var dice_roll_visual: DiceRollVisual  # P3-118: Dice roll visualization for reroll comparisons
var _active_review_dialog: SecondaryMissionReviewDialog = null

func _ready() -> void:
	_setup_ui_references()
	print("CommandController ready")
	# Schedule a deferred refresh to catch any timing edge cases where
	# secondary missions were initialized after initial UI build
	call_deferred("_deferred_secondary_refresh")

func _exit_tree() -> void:
	# Disconnect SecondaryMissionManager signals
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if secondary_mgr:
		if secondary_mgr.has_signal("when_drawn_requires_interaction"):
			if secondary_mgr.when_drawn_requires_interaction.is_connected(_on_when_drawn_requires_interaction):
				secondary_mgr.when_drawn_requires_interaction.disconnect(_on_when_drawn_requires_interaction)
		if secondary_mgr.has_signal("mission_drawn"):
			if secondary_mgr.mission_drawn.is_connected(_on_mission_drawn):
				secondary_mgr.mission_drawn.disconnect(_on_mission_drawn)
		if secondary_mgr.has_signal("mission_discarded"):
			if secondary_mgr.mission_discarded.is_connected(_on_mission_discarded):
				secondary_mgr.mission_discarded.disconnect(_on_mission_discarded)

	# Clean up UI containers
	var command_controls = SceneRefs.main_path("HUD_Bottom/HBoxContainer/CommandControls")
	if command_controls and is_instance_valid(command_controls):
		command_controls.queue_free()

	# Clean up the secondary mission review dialog if still open
	if _active_review_dialog and is_instance_valid(_active_review_dialog):
		print("CommandController: Cleaning up orphaned SecondaryMissionReviewDialog on exit")
		_active_review_dialog.hide()
		_active_review_dialog.queue_free()
		_active_review_dialog = null

	# Clean up right panel elements
	var container = SceneRefs.hud_right_vbox()
	if container and is_instance_valid(container):
		var command_elements = ["CommandPanel", "CommandScrollContainer"]
		for element in command_elements:
			var node = container.get_node_or_null(element)
			if node and is_instance_valid(node):
				print("CommandController: Removing element: ", element)
				container.remove_child(node)
				node.queue_free()

func _setup_ui_references() -> void:
	# Get references to UI nodes
	hud_bottom = SceneRefs.hud_bottom()
	hud_right = SceneRefs.hud_right()
	
	# Setup command-specific UI elements
	if hud_bottom:
		_setup_bottom_hud()
	if hud_right:
		_setup_right_panel()

func _deferred_secondary_refresh() -> void:
	"""Deferred refresh to ensure secondary missions are displayed after initialization."""
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	var current_player = GameState.get_active_player()
	if secondary_mgr and secondary_mgr.is_initialized(current_player):
		var command_panel = SceneRefs.main_path("HUD_Right/VBoxContainer/CommandScrollContainer/CommandPanel")
		if command_panel:
			var existing_section = command_panel.get_node_or_null("SecondaryMissionsSection")
			if not existing_section:
				print("CommandController: Deferred refresh — secondary missions section missing, rebuilding")
				_setup_secondary_missions_section(command_panel)
			else:
				print("CommandController: Deferred refresh — secondary missions section already present")

func _setup_bottom_hud() -> void:
	# NOTE: Main.gd now handles the phase action button
	# CommandController only needs to set up phase-specific info if needed
	pass

func _setup_right_panel() -> void:
	# Check for existing VBoxContainer in HUD_Right
	var container = hud_right.get_node_or_null("VBoxContainer")
	if not container:
		container = VBoxContainer.new()
		container.name = "VBoxContainer"
		hud_right.add_child(container)
	
	# Create scroll container for command panel
	var scroll_container = ScrollContainer.new()
	scroll_container.name = "CommandScrollContainer"
	scroll_container.custom_minimum_size = Vector2(250, 400)
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(scroll_container)
	
	var command_panel = VBoxContainer.new()
	command_panel.name = "CommandPanel"
	command_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(command_panel)
	
	# Title
	var title = Label.new()
	title.text = "COMMAND PHASE"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if FactionPalettes.FONT_RAJDHANI_BOLD:
		title.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	command_panel.add_child(title)

	# T-096: Phase progress indicator showing 1/3 → 3/3 sub-steps
	var phase_progress_label = Label.new()
	phase_progress_label.name = "PhaseProgressLabel"
	phase_progress_label.text = _compute_command_phase_progress()
	phase_progress_label.add_theme_font_size_override("font_size", 12)
	phase_progress_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.4, 1.0))
	if FactionPalettes.FONT_RAJDHANI_SEMIBOLD:
		phase_progress_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_SEMIBOLD)
	command_panel.add_child(phase_progress_label)

	# End Command Phase button — prominent CTA near the top of the panel
	var end_phase_btn = Button.new()
	end_phase_btn.name = "EndCommandPhaseButton"
	end_phase_btn.text = "End Command Phase  [Enter]"
	end_phase_btn.custom_minimum_size = Vector2(230, 40)
	end_phase_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_WhiteDwarfTheme.apply_primary_button(end_phase_btn)
	end_phase_btn.add_theme_font_size_override("font_size", 14)
	end_phase_btn.pressed.connect(_on_end_command_pressed)
	command_panel.add_child(end_phase_btn)

	_add_command_gold_separator(command_panel)

	# Phase information
	var current_player = GameState.get_active_player()
	var battle_round = GameState.get_battle_round()
	var faction_name = GameState.get_faction_name(current_player)

	var round_label = Label.new()
	round_label.text = "BATTLE ROUND %d" % battle_round
	round_label.add_theme_font_size_override("font_size", 13)
	round_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes.FONT_RAJDHANI_BOLD:
		round_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	command_panel.add_child(round_label)

	var player_label = Label.new()
	player_label.text = "Active: Player %d (%s)" % [current_player, faction_name]
	player_label.add_theme_font_size_override("font_size", 12)
	player_label.add_theme_color_override("font_color", FactionPalettes.get_player_color(current_player))
	if FactionPalettes.FONT_RAJDHANI_SEMIBOLD:
		player_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_SEMIBOLD)
	command_panel.add_child(player_label)

	_add_command_gold_separator(command_panel)

	# Command Points display
	var cp_header = Label.new()
	cp_header.text = "COMMAND POINTS"
	cp_header.add_theme_font_size_override("font_size", 13)
	cp_header.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes.FONT_RAJDHANI_BOLD:
		cp_header.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	command_panel.add_child(cp_header)

	var cp_section = VBoxContainer.new()
	cp_section.name = "CPSection"
	command_panel.add_child(cp_section)

	var p1_cp = GameState.state.get("players", {}).get("1", {}).get("cp", 0)
	var p2_cp = GameState.state.get("players", {}).get("2", {}).get("cp", 0)

	var p1_cp_label = Label.new()
	p1_cp_label.name = "P1CPLabel"
	p1_cp_label.text = "Player 1 (%s): %d CP" % [GameState.get_faction_name(1), p1_cp]
	p1_cp_label.add_theme_color_override("font_color", FactionPalettes.get_player_color(1))
	if FactionPalettes.FONT_RAJDHANI_SEMIBOLD:
		p1_cp_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_SEMIBOLD)
	cp_section.add_child(p1_cp_label)

	var p2_cp_label = Label.new()
	p2_cp_label.name = "P2CPLabel"
	p2_cp_label.text = "Player 2 (%s): %d CP" % [GameState.get_faction_name(2), p2_cp]
	p2_cp_label.add_theme_color_override("font_color", FactionPalettes.get_player_color(2))
	if FactionPalettes.FONT_RAJDHANI_SEMIBOLD:
		p2_cp_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_SEMIBOLD)
	cp_section.add_child(p2_cp_label)

	var cp_note = Label.new()
	cp_note.text = "+1 CP generated this phase"
	cp_note.add_theme_font_size_override("font_size", 11)
	cp_note.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	cp_section.add_child(cp_note)

	_add_command_gold_separator(command_panel)

	# Objective control section
	var obj_header = Label.new()
	obj_header.text = "OBJECTIVE CONTROL"
	obj_header.add_theme_font_size_override("font_size", 13)
	obj_header.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes.FONT_RAJDHANI_BOLD:
		obj_header.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	command_panel.add_child(obj_header)

	var objectives_section = VBoxContainer.new()
	objectives_section.name = "ObjectivesSection"
	command_panel.add_child(objectives_section)

	if MissionManager:
		var control_summary = MissionManager.get_objective_control_summary()
		for obj_id in control_summary.objectives:
			var obj_label = Label.new()
			var controller = control_summary.objectives[obj_id]
			# Controller 0 is only "Contested" on a genuine OC tie; an empty
			# marker reads "Uncontrolled" (mek-contested bug).
			var control_text = "Uncontrolled"
			var text_color = Color(0.7, 0.7, 0.7)
			if controller == 1:
				control_text = GameState.get_faction_name(1)
				text_color = FactionPalettes.get_player_color(1)
			elif controller == 2:
				control_text = GameState.get_faction_name(2)
				text_color = FactionPalettes.get_player_color(2)
			elif MissionManager.is_objective_contested(obj_id):
				control_text = "Contested"
				text_color = Color(1.0, 1.0, 0.5)

			obj_label.text = "%s: %s" % [obj_id.replace("obj_", "").to_upper(), control_text]
			obj_label.add_theme_color_override("font_color", text_color)
			if FactionPalettes.FONT_RAJDHANI_SEMIBOLD:
				obj_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_SEMIBOLD)
			objectives_section.add_child(obj_label)
	
	# Battle-shock tests and Stratagems section
	_setup_battle_shock_section(command_panel)

	# Faction abilities section (Oath of Moment, Waaagh!, etc.)
	_setup_faction_abilities_section(command_panel)

	# Show VP status
	_add_command_gold_separator(command_panel)

	var vp_header = Label.new()
	vp_header.text = "VICTORY POINTS"
	vp_header.add_theme_font_size_override("font_size", 13)
	vp_header.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes.FONT_RAJDHANI_BOLD:
		vp_header.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	command_panel.add_child(vp_header)

	var vp_section = VBoxContainer.new()
	vp_section.name = "VPSection"
	command_panel.add_child(vp_section)

	if MissionManager:
		var vp_summary = MissionManager.get_vp_summary()

		var p1_vp_label = Label.new()
		p1_vp_label.text = "Player 1: %d VP (Primary: %d)" % [
			vp_summary.player1.total,
			vp_summary.player1.primary
		]
		p1_vp_label.add_theme_color_override("font_color", FactionPalettes.get_player_color(1))
		if FactionPalettes.FONT_RAJDHANI_SEMIBOLD:
			p1_vp_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_SEMIBOLD)
		vp_section.add_child(p1_vp_label)

		var p2_vp_label = Label.new()
		p2_vp_label.text = "Player 2: %d VP (Primary: %d)" % [
			vp_summary.player2.total,
			vp_summary.player2.primary
		]
		p2_vp_label.add_theme_color_override("font_color", FactionPalettes.get_player_color(2))
		if FactionPalettes.FONT_RAJDHANI_SEMIBOLD:
			p2_vp_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_SEMIBOLD)
		vp_section.add_child(p2_vp_label)

	# P3-118: Add dice roll visual for reroll comparisons
	dice_roll_visual = DiceRollVisual.new()
	dice_roll_visual.custom_minimum_size = Vector2(200, 0)
	dice_roll_visual.visible = false
	command_panel.add_child(dice_roll_visual)

	# Secondary Missions section
	_setup_secondary_missions_section(command_panel)

func _setup_secondary_missions_section(command_panel: VBoxContainer) -> void:
	"""Build the secondary missions display with discard and New Orders controls."""
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if not secondary_mgr:
		print("CommandController: SecondaryMissionManager not found - skipping secondary missions section")
		return

	var current_player = GameState.get_active_player()
	print("CommandController: _setup_secondary_missions_section called for player %d, initialized=%s" % [
		current_player, str(secondary_mgr.is_initialized(current_player))])
	if not secondary_mgr.is_initialized(current_player):
		print("CommandController: Secondary missions not initialized for player %d - skipping section" % current_player)
		return

	_add_command_gold_separator(command_panel)

	var section = VBoxContainer.new()
	section.name = "SecondaryMissionsSection"
	section.add_theme_constant_override("separation", 4)
	command_panel.add_child(section)

	# Section header
	var section_title = Label.new()
	section_title.text = "SECONDARY MISSIONS"
	section_title.add_theme_font_size_override("font_size", 13)
	section_title.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes.FONT_RAJDHANI_BOLD:
		section_title.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	section.add_child(section_title)

	# Deck info
	var deck_size = secondary_mgr.get_deck_size(current_player)
	var discard_size = secondary_mgr.get_discard_size(current_player)
	var secondary_vp = secondary_mgr.get_secondary_vp(current_player)

	var deck_info = Label.new()
	deck_info.text = "Deck: %d | Discard: %d | Secondary VP: %d" % [deck_size, discard_size, secondary_vp]
	deck_info.add_theme_font_size_override("font_size", 11)
	deck_info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	section.add_child(deck_info)

	# Active missions
	var active_missions = secondary_mgr.get_active_missions(current_player)

	if active_missions.size() == 0:
		var no_missions_label = Label.new()
		no_missions_label.text = "No active secondary missions"
		no_missions_label.add_theme_font_size_override("font_size", 11)
		no_missions_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		section.add_child(no_missions_label)
	else:
		for i in range(active_missions.size()):
			var mission = active_missions[i]
			_add_mission_card_ui(section, mission, i, current_player)

	# New Orders stratagem button
	_add_new_orders_button(section, current_player, active_missions)

func _add_mission_card_ui(parent: VBoxContainer, mission: Dictionary, index: int, player: int) -> void:
	"""Add a single mission card display with voluntary discard button."""
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

	# Mission name
	var name_label = Label.new()
	name_label.text = mission.get("name", "Unknown Mission")
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	card_vbox.add_child(name_label)

	# Category
	var cat_label = Label.new()
	cat_label.text = mission.get("category", "")
	cat_label.add_theme_font_size_override("font_size", 10)
	cat_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	card_vbox.add_child(cat_label)

	# Scoring info
	var scoring = mission.get("scoring", {})
	var conditions = scoring.get("conditions", [])
	var max_vp = 0
	for c in conditions:
		max_vp = max(max_vp, c.get("vp", 0))
	var when_text = _get_timing_display(scoring.get("when", ""))
	var scoring_label = Label.new()
	scoring_label.text = "Up to %d VP | %s" % [max_vp, when_text]
	scoring_label.add_theme_font_size_override("font_size", 10)
	scoring_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	card_vbox.add_child(scoring_label)

	# Pending interaction indicator or resolved interaction data
	if mission.get("pending_interaction", false):
		var pending_label = Label.new()
		pending_label.text = "AWAITING INTERACTION"
		pending_label.add_theme_font_size_override("font_size", 10)
		pending_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
		card_vbox.add_child(pending_label)
	else:
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
				targets_label.text += " | Gamma: %s" % gamma_name
			targets_label.add_theme_font_size_override("font_size", 9)
			targets_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.4))
			targets_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			card_vbox.add_child(targets_label)
		elif mission.get("id", "") == "a_tempting_target" and mission_data.get("tempting_target_id", "") != "":
			var obj_label = Label.new()
			var obj_id = mission_data.get("tempting_target_id", "")
			obj_label.text = "Target: %s" % obj_id.replace("obj_", "Objective ").to_upper()
			obj_label.add_theme_font_size_override("font_size", 9)
			obj_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.4))
			card_vbox.add_child(obj_label)

	# VP scored so far from this card
	var vp_scored = mission.get("vp_scored", 0)
	if vp_scored > 0:
		var vp_label = Label.new()
		vp_label.text = "VP scored: %d" % vp_scored
		vp_label.add_theme_font_size_override("font_size", 10)
		vp_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
		card_vbox.add_child(vp_label)

	# Voluntary Discard button
	var discard_btn = Button.new()
	discard_btn.text = "Discard (+1 CP)"
	discard_btn.custom_minimum_size = Vector2(0, 24)
	discard_btn.add_theme_font_size_override("font_size", 11)
	discard_btn.tooltip_text = "Voluntarily discard this mission. Gain 1 CP if it's your turn."
	discard_btn.pressed.connect(_on_voluntary_discard_pressed.bind(index))
	_WhiteDwarfTheme.apply_to_button(discard_btn)
	card_vbox.add_child(discard_btn)

func _add_new_orders_button(parent: VBoxContainer, player: int, active_missions: Array) -> void:
	"""Add the New Orders stratagem button if available."""
	if active_missions.size() == 0:
		return

	var strat_manager = get_node_or_null("/root/StratagemManager")
	if not strat_manager:
		return

	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if not secondary_mgr:
		return

	# Check if New Orders can be used
	var can_use = strat_manager.can_use_stratagem(player, "new_orders")
	var player_cp = strat_manager.get_player_cp(player)
	var deck_empty = secondary_mgr.get_deck_size(player) == 0

	_add_command_gold_separator(parent)

	var orders_container = VBoxContainer.new()
	orders_container.add_theme_constant_override("separation", 2)
	parent.add_child(orders_container)

	var orders_title = Label.new()
	orders_title.text = "NEW ORDERS (Stratagem - 1 CP)"
	orders_title.add_theme_font_size_override("font_size", 12)
	orders_title.add_theme_color_override("font_color", Color(0.8, 0.6, 1.0))
	orders_container.add_child(orders_title)

	var orders_desc = Label.new()
	orders_desc.text = "Discard a mission and draw a new one.\nOnce per battle."
	orders_desc.add_theme_font_size_override("font_size", 10)
	orders_desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	orders_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	orders_container.add_child(orders_desc)

	# One button per active mission for New Orders
	for i in range(active_missions.size()):
		var mission = active_missions[i]
		var btn = Button.new()
		btn.text = "New Orders: Discard \"%s\"" % mission.get("name", "?")
		btn.custom_minimum_size = Vector2(0, 26)
		btn.add_theme_font_size_override("font_size", 11)
		WhiteDwarfTheme.apply_to_button(btn)

		# Disable if can't use
		if not can_use.get("can_use", false):
			btn.disabled = true
			btn.tooltip_text = can_use.get("reason", "Cannot use New Orders")
		elif deck_empty:
			btn.disabled = true
			btn.tooltip_text = "Deck is empty — no cards to draw"
		elif player_cp < 1:
			btn.disabled = true
			btn.tooltip_text = "Not enough CP (need 1)"
		else:
			btn.tooltip_text = "Spend 1 CP to discard this mission and draw a new one"
			btn.pressed.connect(_on_new_orders_pressed.bind(i))

		_WhiteDwarfTheme.apply_to_button(btn)
		orders_container.add_child(btn)

func _get_timing_display(timing: String) -> String:
	"""Convert timing constant to human-readable text."""
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

func _on_voluntary_discard_pressed(mission_index: int) -> void:
	"""Handle voluntary discard button press."""
	print("CommandController: Voluntary discard requested for mission index %d" % mission_index)
	emit_signal("command_action_requested", {
		"type": "VOLUNTARY_DISCARD",
		"mission_index": mission_index,
	})

func _on_new_orders_pressed(mission_index: int) -> void:
	"""Handle New Orders stratagem button press."""
	print("CommandController: New Orders requested for mission index %d" % mission_index)
	emit_signal("command_action_requested", {
		"type": "USE_NEW_ORDERS",
		"mission_index": mission_index,
	})

func _setup_battle_shock_section(command_panel: VBoxContainer) -> void:
	# Show battle-shock tests and stratagem options
	if not current_phase:
		return

	# Get available actions from the phase to see if there are battle-shock tests
	var available_actions = []
	if current_phase.has_method("get_available_actions"):
		available_actions = current_phase.get_available_actions()

	# Filter to battle-shock and stratagem actions
	var shock_tests = []
	var stratagem_actions = []
	for action in available_actions:
		if action.get("type", "") == "BATTLE_SHOCK_TEST":
			shock_tests.append(action)
		elif action.get("type", "") == "USE_STRATAGEM":
			stratagem_actions.append(action)

	if shock_tests.size() == 0:
		return

	_add_command_gold_separator(command_panel)

	var shock_section = VBoxContainer.new()
	shock_section.name = "BattleShockSection"
	command_panel.add_child(shock_section)

	var shock_title = Label.new()
	shock_title.text = "BATTLE-SHOCK TESTS"
	shock_title.add_theme_font_size_override("font_size", 13)
	shock_title.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes.FONT_RAJDHANI_BOLD:
		shock_title.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	shock_section.add_child(shock_title)

	var shock_note = Label.new()
	shock_note.text = "%d unit(s) below half-strength" % shock_tests.size()
	shock_note.add_theme_font_size_override("font_size", 11)
	shock_note.add_theme_color_override("font_color", Color(0.8, 0.6, 0.2))
	shock_section.add_child(shock_note)

	for test_action in shock_tests:
		var unit_id = test_action.get("unit_id", "")
		var unit = GameState.state.get("units", {}).get(unit_id, {})
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var ld = unit.get("meta", {}).get("stats", {}).get("leadership", 7)

		# Unit container
		var unit_box = VBoxContainer.new()
		unit_box.add_theme_constant_override("separation", 2)
		shock_section.add_child(unit_box)

		# Roll test button
		var test_btn = Button.new()
		test_btn.text = "Roll Battle-shock: %s (Ld %d)" % [unit_name, ld]
		test_btn.custom_minimum_size = Vector2(230, 28)
		test_btn.pressed.connect(_on_battle_shock_test_pressed.bind(unit_id))
		_WhiteDwarfTheme.apply_to_button(test_btn)
		unit_box.add_child(test_btn)

		# Check for Insane Bravery stratagem availability
		var has_insane_bravery = false
		for strat_action in stratagem_actions:
			if strat_action.get("stratagem_id", "") == "insane_bravery" and strat_action.get("target_unit_id", "") == unit_id:
				has_insane_bravery = true
				break

		if has_insane_bravery:
			var strat_btn = Button.new()
			strat_btn.text = "INSANE BRAVERY (1 CP) - Auto-pass"
			strat_btn.custom_minimum_size = Vector2(230, 28)
			WhiteDwarfTheme.apply_to_button(strat_btn)
			strat_btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
			strat_btn.pressed.connect(_on_insane_bravery_pressed.bind(unit_id))
			_WhiteDwarfTheme.apply_to_button(strat_btn)
			strat_btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
			unit_box.add_child(strat_btn)

		_add_command_gold_separator(unit_box)

func _setup_faction_abilities_section(command_panel: VBoxContainer) -> void:
	"""Build faction abilities display (Oath of Moment, Waaagh!, etc.)."""
	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	if not faction_mgr:
		return

	var current_player = GameState.get_active_player()
	var has_oath = faction_mgr.player_has_ability(current_player, "Oath of Moment")
	var has_waaagh = faction_mgr.is_waaagh_available(current_player) or faction_mgr.is_waaagh_active(current_player) \
		or faction_mgr.is_boss_watchin_waaagh_available(current_player)
	var plant_eligible = faction_mgr.get_plant_waaagh_banner_eligible_units(current_player) if faction_mgr.has_method("get_plant_waaagh_banner_eligible_units") else []

	if not has_oath and not has_waaagh and plant_eligible.size() == 0:
		return

	_add_command_gold_separator(command_panel)

	var section = VBoxContainer.new()
	section.name = "FactionAbilitiesSection"
	section.add_theme_constant_override("separation", 4)
	command_panel.add_child(section)

	# --- WAAAGH! (Orks) ---
	if has_waaagh:
		_setup_waaagh_subsection(section, faction_mgr, current_player)

	# --- Plant the Waaagh! Banner (OA-46) ---
	if plant_eligible.size() > 0:
		_setup_plant_waaagh_banner_subsection(section, plant_eligible, current_player)

	# --- Oath of Moment (Space Marines) ---
	if has_oath:
		_setup_oath_of_moment_subsection(section, faction_mgr, current_player)

func _setup_waaagh_subsection(section: VBoxContainer, faction_mgr, current_player: int) -> void:
	"""Build the Waaagh! activation UI for Ork players."""
	var header = Label.new()
	header.text = "WAAAGH!"
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.2, 0.9, 0.2))
	section.add_child(header)

	var desc = Label.new()
	desc.text = "Once per battle. All Ork units gain: Advance and Charge, +1 Strength and +1 Attack (melee), 5+ invulnerable save."
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(desc)

	if faction_mgr.is_waaagh_active(current_player):
		var active_label = Label.new()
		active_label.text = "WAAAGH! IS ACTIVE"
		active_label.add_theme_font_size_override("font_size", 12)
		active_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
		section.add_child(active_label)
	elif faction_mgr.is_waaagh_available(current_player):
		var btn = Button.new()
		btn.text = "CALL DA WAAAGH!"
		btn.custom_minimum_size = Vector2(230, 34)
		btn.add_theme_font_size_override("font_size", 13)
		_WhiteDwarfTheme.apply_to_button(btn)
		btn.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
		btn.tooltip_text = "Declare a Waaagh! — all Ork units gain advance+charge, +1 S/A melee, 5+ invuln this turn"
		btn.pressed.connect(_on_call_waaagh_pressed)
		section.add_child(btn)
	elif faction_mgr.has_method("is_boss_watchin_waaagh_available") and faction_mgr.is_boss_watchin_waaagh_available(current_player):
		# Da Boss Is Watchin' (Bully Boyz): a second Waaagh!, scoped to
		# WARBOSS / NOBZ / MEGANOBZ units. Same CALL_WAAAGH action — the
		# phase routes to the scoped activation when the first is spent.
		var bw_btn = Button.new()
		bw_btn.name = "BossWatchinWaaaghButton"
		bw_btn.text = "DA BOSS IS WATCHIN' — WAAAGH AGAIN!"
		bw_btn.custom_minimum_size = Vector2(230, 34)
		bw_btn.add_theme_font_size_override("font_size", 12)
		_WhiteDwarfTheme.apply_to_button(bw_btn)
		bw_btn.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
		bw_btn.tooltip_text = "Bully Boyz: call a Waaagh! a second time this battle — only Warboss, Nobz and Meganobz units gain the effects"
		bw_btn.pressed.connect(_on_call_waaagh_pressed)
		section.add_child(bw_btn)

	_add_command_gold_separator(section)

func _setup_plant_waaagh_banner_subsection(section: VBoxContainer, plant_eligible: Array, current_player: int) -> void:
	"""Build the Plant the Waaagh! Banner UI for eligible Nob units."""
	var header = Label.new()
	header.text = "PLANT DA WAAAGH! BANNER"
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.2, 0.9, 0.2))
	section.add_child(header)

	var desc = Label.new()
	desc.text = "Once per battle per unit. Grants Waaagh! effects, 4+ invuln, OC 5."
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(desc)

	for target in plant_eligible:
		var btn = Button.new()
		btn.text = "Plant Banner: %s" % target.unit_name
		btn.custom_minimum_size = Vector2(230, 30)
		btn.add_theme_font_size_override("font_size", 11)
		_WhiteDwarfTheme.apply_to_button(btn)
		btn.add_theme_color_override("font_color", Color(0.2, 0.9, 0.2))
		btn.tooltip_text = "Plant the Waaagh! Banner with %s" % target.unit_name
		btn.pressed.connect(_on_plant_waaagh_banner_pressed.bind(target.unit_id))
		section.add_child(btn)

	_add_command_gold_separator(section)

func _setup_oath_of_moment_subsection(section: VBoxContainer, faction_mgr, current_player: int) -> void:
	"""Build the Oath of Moment target selection UI for Space Marines."""
	# Section header
	var section_title = Label.new()
	section_title.text = "OATH OF MOMENT"
	section_title.add_theme_font_size_override("font_size", 14)
	section_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	section.add_child(section_title)

	var desc_label = Label.new()
	desc_label.text = "Select one enemy unit. Re-roll hit and wound rolls of 1 against it."
	desc_label.add_theme_font_size_override("font_size", 10)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(desc_label)

	# Show current target
	var current_target_id = faction_mgr.get_oath_of_moment_target(current_player)
	if current_target_id != "":
		var target_unit = GameState.state.get("units", {}).get(current_target_id, {})
		var target_name = target_unit.get("meta", {}).get("name", current_target_id)
		var current_label = Label.new()
		current_label.text = "Current target: %s" % target_name
		current_label.add_theme_font_size_override("font_size", 12)
		current_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))
		section.add_child(current_label)

	# Show eligible targets as buttons
	var eligible_targets = faction_mgr.get_eligible_oath_targets(current_player)

	if eligible_targets.size() == 0:
		var no_targets = Label.new()
		no_targets.text = "No eligible enemy targets"
		no_targets.add_theme_font_size_override("font_size", 11)
		no_targets.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		section.add_child(no_targets)
	else:
		for target_info in eligible_targets:
			var is_current = (target_info.unit_id == current_target_id)
			var btn = Button.new()
			btn.text = "%s%s" % [target_info.unit_name, " (SELECTED)" if is_current else ""]
			btn.custom_minimum_size = Vector2(230, 26)
			btn.add_theme_font_size_override("font_size", 11)
			_WhiteDwarfTheme.apply_to_button(btn)
			if is_current:
				btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
				btn.tooltip_text = "Currently targeted by Oath of Moment"
			else:
				btn.tooltip_text = "Mark %s for Oath of Moment" % target_info.unit_name
			btn.pressed.connect(_on_oath_target_pressed.bind(target_info.unit_id))
			section.add_child(btn)

func _on_oath_target_pressed(target_unit_id: String) -> void:
	"""Handle Oath of Moment target selection button press."""
	print("CommandController: Oath of Moment target selected: %s" % target_unit_id)
	emit_signal("command_action_requested", {
		"type": "SELECT_OATH_TARGET",
		"target_unit_id": target_unit_id
	})

func _on_call_waaagh_pressed() -> void:
	"""Handle Waaagh! activation button press."""
	print("CommandController: WAAAGH! called by human player")
	emit_signal("command_action_requested", {
		"type": "CALL_WAAAGH",
		"player": GameState.get_active_player()
	})

func _on_plant_waaagh_banner_pressed(unit_id: String) -> void:
	"""Handle Plant the Waaagh! Banner button press."""
	print("CommandController: Plant the Waaagh! Banner requested for %s" % unit_id)
	emit_signal("command_action_requested", {
		"type": "PLANT_WAAAGH_BANNER",
		"unit_id": unit_id,
		"player": GameState.get_active_player()
	})

func _on_battle_shock_test_pressed(unit_id: String) -> void:
	print("CommandController: Battle-shock test requested for %s" % unit_id)
	emit_signal("command_action_requested", {
		"type": "BATTLE_SHOCK_TEST",
		"unit_id": unit_id
	})

func _on_insane_bravery_pressed(unit_id: String) -> void:
	print("CommandController: Insane Bravery stratagem requested for %s" % unit_id)
	emit_signal("command_action_requested", {
		"type": "USE_STRATAGEM",
		"stratagem_id": "insane_bravery",
		"target_unit_id": unit_id
	})

func _add_command_gold_separator(parent: Control) -> void:
	var sep = ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.color = Color(_WhiteDwarfTheme.WH_GOLD.r, _WhiteDwarfTheme.WH_GOLD.g, _WhiteDwarfTheme.WH_GOLD.b, 0.4)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(sep)

func set_phase(phase: BasePhase) -> void:
	current_phase = phase
	print("DEBUG: CommandController.set_phase called with phase type: ", phase.get_class() if phase else "null")

	if phase:
		# Connect command_reroll_opportunity signal if available
		if phase.has_signal("command_reroll_opportunity"):
			if not phase.command_reroll_opportunity.is_connected(_on_command_reroll_opportunity):
				phase.command_reroll_opportunity.connect(_on_command_reroll_opportunity)
		# P3-118: Connect reroll completed signal for visualization
		if phase.has_signal("command_reroll_completed"):
			if not phase.command_reroll_completed.is_connected(_on_command_reroll_completed):
				phase.command_reroll_completed.connect(_on_command_reroll_completed)

		# Connect SecondaryMissionManager signals for reactive UI updates
		var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
		if secondary_mgr:
			if secondary_mgr.has_signal("when_drawn_requires_interaction"):
				if not secondary_mgr.when_drawn_requires_interaction.is_connected(_on_when_drawn_requires_interaction):
					secondary_mgr.when_drawn_requires_interaction.connect(_on_when_drawn_requires_interaction)
					print("CommandController: Connected to SecondaryMissionManager.when_drawn_requires_interaction")
			if secondary_mgr.has_signal("mission_drawn"):
				if not secondary_mgr.mission_drawn.is_connected(_on_mission_drawn):
					secondary_mgr.mission_drawn.connect(_on_mission_drawn)
					print("CommandController: Connected to SecondaryMissionManager.mission_drawn")
			if secondary_mgr.has_signal("mission_discarded"):
				if not secondary_mgr.mission_discarded.is_connected(_on_mission_discarded):
					secondary_mgr.mission_discarded.connect(_on_mission_discarded)
					print("CommandController: Connected to SecondaryMissionManager.mission_discarded")

		# Connect AIPlayer signal for when AI opponent selects alpha targets but human needs to pick gamma
		var ai_player_node = get_node_or_null("/root/AIPlayer")
		if ai_player_node and ai_player_node.has_signal("ai_alpha_targets_selected"):
			if not ai_player_node.ai_alpha_targets_selected.is_connected(_on_ai_alpha_targets_selected):
				ai_player_node.ai_alpha_targets_selected.connect(_on_ai_alpha_targets_selected)
				print("CommandController: Connected to AIPlayer.ai_alpha_targets_selected")

		# Update UI elements with current game state
		_refresh_ui()
		show()

		# Show review dialog for newly drawn secondary missions
		_show_drawn_missions_review_dialog()

		# Check for pending interactions that were created during draw_missions_to_hand()
		# BEFORE this signal handler was connected (signal timing gap fix)
		if secondary_mgr:
			_check_pending_interactions(secondary_mgr)

		# 11e Punishment: offer the human owner the chance to revise the
		# auto-Condemn picks made at turn start (same timing-gap pattern —
		# on_turn_start_11e ran during phase entry, before this controller
		# existed).
		_check_pending_condemn_prompt()

		# 11e Extract Relic / Locate and Deny: the Disruption player may
		# revise the auto-picked marker terrain in their first Command phase.
		_check_pending_relic_setup()

		# 11e Burden of Trust: the holder may revise the auto-assigned guard
		# units at the start of each of their turns.
		_check_pending_guard_prompt()
	else:
		hide()

func _refresh_ui() -> void:
	print("CommandController: _refresh_ui() called")
	# Update phase info label
	if phase_info_label:
		var current_player = GameState.get_active_player()
		var battle_round = GameState.get_battle_round()
		phase_info_label.text = "Player %d - Round %d" % [current_player, battle_round]

	# Update CP labels if they exist
	var command_panel = SceneRefs.main_path("HUD_Right/VBoxContainer/CommandScrollContainer/CommandPanel")
	if not command_panel:
		print("CommandController: _refresh_ui() — command_panel not found at expected path")
		return
	if command_panel:
		var cp_section = command_panel.get_node_or_null("CPSection")
		if cp_section:
			var p1_label = cp_section.get_node_or_null("P1CPLabel")
			var p2_label = cp_section.get_node_or_null("P2CPLabel")
			var p1_cp = GameState.state.get("players", {}).get("1", {}).get("cp", 0)
			var p2_cp = GameState.state.get("players", {}).get("2", {}).get("cp", 0)
			if p1_label:
				p1_label.text = "Player 1 (%s): %d CP" % [GameState.get_faction_name(1), p1_cp]
			if p2_label:
				p2_label.text = "Player 2 (%s): %d CP" % [GameState.get_faction_name(2), p2_cp]

		# Rebuild the faction abilities section to reflect Oath of Moment / Waaagh! changes
		var old_faction_section = command_panel.get_node_or_null("FactionAbilitiesSection")
		if old_faction_section:
			var fa_idx = old_faction_section.get_index()
			if fa_idx > 0:
				var fa_prev = command_panel.get_child(fa_idx - 1)
				if fa_prev is HSeparator:
					command_panel.remove_child(fa_prev)
					fa_prev.queue_free()
			command_panel.remove_child(old_faction_section)
			old_faction_section.queue_free()
		_setup_faction_abilities_section(command_panel)

		# Rebuild the secondary missions section to reflect changes
		var old_section = command_panel.get_node_or_null("SecondaryMissionsSection")
		if old_section:
			# Find the separator before it and remove both
			var idx = old_section.get_index()
			if idx > 0:
				var prev = command_panel.get_child(idx - 1)
				if prev is HSeparator:
					command_panel.remove_child(prev)
					prev.queue_free()
			command_panel.remove_child(old_section)
			old_section.queue_free()
		_setup_secondary_missions_section(command_panel)

func _on_end_command_pressed() -> void:
	print("CommandController: End Command Phase button pressed")
	emit_signal("command_action_requested", {"type": "END_COMMAND"})

# ============================================================================
# COMMAND RE-ROLL HANDLERS
# ============================================================================

func _on_command_reroll_opportunity(unit_id: String, player: int, roll_context: Dictionary) -> void:
	"""Handle Command Re-roll opportunity for a battle-shock test."""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ CommandController: COMMAND RE-ROLL OPPORTUNITY (Battle-shock)")
	print("║ Unit: %s (player %d)" % [roll_context.get("unit_name", unit_id), player])
	print("║ Original rolls: %s = %d vs Ld %d" % [
		str(roll_context.get("original_rolls", [])),
		roll_context.get("total", 0),
		roll_context.get("leadership", 0)
	])
	print("╚═══════════════════════════════════════════════════════════════")

	# Skip dialog for AI players — AIPlayer handles the decision via signal
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(player):
		print("CommandController: Skipping command reroll dialog for AI player %d" % player)
		return

	# Load and show the dialog
	var dialog_script = load("res://dialogs/CommandRerollDialog.gd")
	if not dialog_script:
		push_error("Failed to load CommandRerollDialog.gd")
		_on_command_reroll_declined(unit_id, player)
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(
		unit_id,
		player,
		roll_context.get("roll_type", "battle_shock_test"),
		roll_context.get("original_rolls", []),
		roll_context.get("context_text", "")
	)
	dialog.command_reroll_used.connect(_on_command_reroll_used)
	dialog.command_reroll_declined.connect(_on_command_reroll_declined)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	print("CommandController: Command Re-roll dialog shown for player %d" % player)

func _on_command_reroll_used(unit_id: String, player: int) -> void:
	"""Handle player choosing to use Command Re-roll for battle-shock."""
	print("CommandController: Command Re-roll USED for %s battle-shock" % unit_id)
	emit_signal("command_action_requested", {
		"type": "USE_COMMAND_REROLL",
		"unit_id": unit_id,
	})

func _on_command_reroll_declined(unit_id: String, player: int) -> void:
	"""Handle player declining Command Re-roll for battle-shock."""
	print("CommandController: Command Re-roll DECLINED for %s battle-shock" % unit_id)
	emit_signal("command_action_requested", {
		"type": "DECLINE_COMMAND_REROLL",
		"unit_id": unit_id,
	})

func _on_command_reroll_completed(original_rolls: Array, new_rolls: Array, context: String) -> void:
	"""P3-118: Show reroll comparison visualization when Command Re-roll completes."""
	print("CommandController: Reroll comparison — %s → %s (%s)" % [str(original_rolls), str(new_rolls), context])
	if dice_roll_visual and is_instance_valid(dice_roll_visual):
		dice_roll_visual.show_reroll_comparison(original_rolls, new_rolls, context)

# ============================================================================
# SECONDARY MISSION REVIEW (show drawn missions with replace option)
# ============================================================================

func _show_drawn_missions_review_dialog() -> void:
	"""Show a dialog displaying newly drawn secondary missions with option to replace one (1 CP)."""
	if not current_phase:
		return
	if not current_phase.has_method("get_newly_drawn_missions"):
		return

	var drawn_missions = current_phase.get_newly_drawn_missions()
	if drawn_missions.size() == 0:
		print("CommandController: No newly drawn missions to review")
		return

	var current_player = GameState.get_active_player()

	# Skip dialog for AI players — they don't need a review panel
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(current_player):
		print("CommandController: Skipping drawn missions review dialog for AI player %d" % current_player)
		if current_phase and current_phase.has_method("clear_newly_drawn_missions"):
			current_phase.clear_newly_drawn_missions()
		return
	var player_cp = GameState.state.get("players", {}).get(str(current_player), {}).get("cp", 0)

	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	var deck_size = 0
	if secondary_mgr:
		deck_size = secondary_mgr.get_deck_size(current_player)

	print("CommandController: Showing secondary mission review dialog for player %d (%d missions drawn, %d CP, %d deck)" % [
		current_player, drawn_missions.size(), player_cp, deck_size])

	var dialog = SecondaryMissionReviewDialog.new()
	dialog.name = "SecondaryMissionReviewDialog"
	dialog.setup(current_player, drawn_missions, player_cp, deck_size)
	dialog.mission_replacement_requested.connect(_on_mission_replacement_requested)
	dialog.review_completed.connect(_on_mission_review_completed)
	_active_review_dialog = dialog
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	# Cap dialog to viewport so the Continue button stays reachable
	var vp_size = get_tree().root.size
	var max_h = vp_size.y - 40
	if dialog.size.y > max_h:
		dialog.size = Vector2i(dialog.size.x, max_h)
		dialog.position = Vector2i(dialog.position.x, 20)

func _on_mission_replacement_requested(mission_id: String) -> void:
	"""Handle player requesting to replace a drawn mission (spend 1 CP)."""
	print("CommandController: Mission replacement requested for mission %s" % mission_id)

	# Find the correct active index for this mission ID
	var current_player = GameState.get_active_player()
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	var mission_index = -1
	if secondary_mgr:
		var active_missions = secondary_mgr.get_active_missions(current_player)
		for i in range(active_missions.size()):
			if active_missions[i].get("id", "") == mission_id:
				mission_index = i
				break

	if mission_index == -1:
		push_error("CommandController: Could not find mission %s in active missions" % mission_id)
		return

	print("CommandController: Mission %s is at active index %d" % [mission_id, mission_index])
	emit_signal("command_action_requested", {
		"type": "REPLACE_SECONDARY_MISSION",
		"mission_index": mission_index,
	})
	# Clear the newly drawn list so the dialog doesn't re-show
	if current_phase and current_phase.has_method("clear_newly_drawn_missions"):
		current_phase.clear_newly_drawn_missions()

	# Update the dialog to show the new missions instead of closing it
	if _active_review_dialog and is_instance_valid(_active_review_dialog) and secondary_mgr:
		var updated_missions = secondary_mgr.get_active_missions(current_player)
		print("CommandController: Updating review dialog with %d missions after replacement" % updated_missions.size())
		_active_review_dialog.update_after_replacement(updated_missions)

func _on_mission_review_completed() -> void:
	"""Handle player accepting drawn missions without replacement."""
	print("CommandController: Player accepted drawn missions without replacement")
	_active_review_dialog = null
	if current_phase and current_phase.has_method("clear_newly_drawn_missions"):
		current_phase.clear_newly_drawn_missions()

# ============================================================================
# SECONDARY MISSION INTERACTION HANDLERS
# ============================================================================

func _check_pending_interactions(secondary_mgr) -> void:
	"""Check for pending interactions that were created during draw_missions_to_hand()
	before the signal handler was connected. This fixes the signal timing gap where
	when_drawn_requires_interaction fires during _on_phase_enter() but CommandController
	isn't connected until set_phase() is called later."""
	var current_player = GameState.get_active_player()
	var player_key = str(current_player)
	var state = secondary_mgr._player_state.get(player_key, {})

	# Let the player read the drawn-missions review dialog first — two
	# exclusive popups in the same frame trip the engine's exclusive-child
	# guard. Re-check once the review closes (same pattern as Condemn).
	if _active_review_dialog and is_instance_valid(_active_review_dialog):
		if not _active_review_dialog.tree_exited.is_connected(_on_review_closed_recheck_condemn):
			_active_review_dialog.tree_exited.connect(_on_review_closed_recheck_condemn)
		return

	for mission in state.get("active", []):
		if not mission.get("pending_interaction", false):
			continue
		var mission_id = mission.get("id", "")
		var interaction_type = mission.get("interaction_type", "")
		var details = mission.get("interaction_details", {})

		print("CommandController: Found pending interaction from draw phase — Player %d, Mission: %s, Type: %s" % [
			current_player, mission_id, interaction_type])

		var opponent = 2 if current_player == 1 else 1

		match interaction_type:
			"opponent_selects_units":
				_show_marked_for_death_dialog(current_player, opponent, details)
			"opponent_selects_objective":
				_show_tempting_target_dialog(current_player, opponent, details)
			"drawer_selects_unit":
				_show_beacon_dialog(current_player)
			_:
				print("CommandController: Unknown pending interaction type: %s" % interaction_type)

# ============================================================================
# 11e GDM PUNISHMENT — CONDEMN CHOICE (turn start)
# ============================================================================

func _check_pending_condemn_prompt() -> void:
	"""11e Punishment: _auto_condemn_11e picked up to 3 enemy units at Command
	entry (backstop). Offer a human owner the dialog to revise those picks."""
	var current_player = GameState.get_active_player()
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(current_player):
		return  # AI keeps the auto picks
	var pending = MissionManager.get_pending_condemn_choice_11e(current_player)
	if pending.is_empty():
		return
	# Let the player read the drawn-missions review dialog first: two
	# exclusive popups in the same frame trip the engine's exclusive-child
	# guard and the condemn dialog would cover the review. Re-check once
	# the review closes.
	if _active_review_dialog and is_instance_valid(_active_review_dialog):
		if not _active_review_dialog.tree_exited.is_connected(_on_review_closed_recheck_condemn):
			_active_review_dialog.tree_exited.connect(_on_review_closed_recheck_condemn)
		return
	print("CommandController: 11e Condemn choice pending for P%d (%d eligible, auto picks %s)" % [
		current_player, pending.get("eligible", []).size(), str(pending.get("current", []))])
	_show_condemn_dialog(pending, current_player)

func _on_review_closed_recheck_condemn() -> void:
	if not is_instance_valid(self) or not is_inside_tree():
		return
	call_deferred("_check_pending_condemn_prompt")
	call_deferred("_check_pending_relic_setup")
	# Secondary-card prompts queued behind the review dialog (Beacon
	# designation, Tempting Target pick, Burden of Trust guards).
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if secondary_mgr:
		call_deferred("_check_pending_interactions", secondary_mgr)
	call_deferred("_check_pending_guard_prompt")

func _show_condemn_dialog(pending: Dictionary, player: int) -> void:
	var existing = get_tree().root.get_node_or_null("CondemnChoiceDialog")
	if existing != null and not existing.is_queued_for_deletion():
		return
	var dialog = AcceptDialog.new()
	dialog.name = "CondemnChoiceDialog"
	dialog.title = "%s — Condemn" % pending.get("card_name", "Punishment")
	dialog.min_size = DialogConstants.MEDIUM
	dialog.get_ok_button().visible = false
	WhiteDwarfTheme.apply_to_dialog(dialog)

	var content = VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 8)
	content.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	var header = Label.new()
	header.text = "CONDEMN UP TO 3 ENEMY UNITS"
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

	var max_picks: int = int(pending.get("max_picks", 3))
	var current_picks: Array = pending.get("current", [])
	var resolved = [false]
	var checkboxes: Array = []

	for entry in pending.get("eligible", []):
		var uid: String = str(entry.get("id", ""))
		var check = CheckBox.new()
		check.name = "Check_%s" % uid
		check.text = str(entry.get("label", uid))
		check.button_pressed = uid in current_picks
		check.set_meta("unit_id", uid)
		# Enforce the up-to-3 cap: reject a toggle-on past the cap.
		check.toggled.connect(func(pressed: bool):
			if not pressed:
				return
			var checked = 0
			for c in checkboxes:
				if is_instance_valid(c) and c.button_pressed:
					checked += 1
			if checked > max_picks:
				check.button_pressed = false)
		content.add_child(check)
		checkboxes.append(check)

	content.add_child(HSeparator.new())
	var button_row = HBoxContainer.new()
	button_row.name = "Actions"
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 12)

	var confirm_btn = Button.new()
	confirm_btn.name = "ConfirmCondemn"
	confirm_btn.text = "Confirm Condemned Units"
	confirm_btn.custom_minimum_size = Vector2(190, 36)
	confirm_btn.pressed.connect(func():
		if resolved[0]:
			return
		resolved[0] = true
		var picks = []
		for c in checkboxes:
			if is_instance_valid(c) and c.button_pressed:
				picks.append(str(c.get_meta("unit_id")))
		emit_signal("command_action_requested", {
			"type": "RESOLVE_CONDEMN",
			"player": player,
			"unit_ids": picks,
		})
		dialog.queue_free())
	button_row.add_child(confirm_btn)

	var skip_btn = Button.new()
	skip_btn.name = "SkipCondemn"
	skip_btn.text = "Keep Current Picks"
	skip_btn.custom_minimum_size = Vector2(160, 36)
	skip_btn.pressed.connect(func():
		if resolved[0]:
			return
		resolved[0] = true
		emit_signal("command_action_requested", {
			"type": "DISMISS_CONDEMN",
			"player": player,
		})
		dialog.queue_free())
	button_row.add_child(skip_btn)
	content.add_child(button_row)

	# Escape/close keeps the auto picks — never a dead end.
	dialog.canceled.connect(func():
		if resolved[0]:
			return
		resolved[0] = true
		emit_signal("command_action_requested", {
			"type": "DISMISS_CONDEMN",
			"player": player,
		})
		dialog.queue_free())

	dialog.add_child(content)
	get_tree().root.add_child(dialog)
	# Cap to the viewport so the dynamic Punishment description can't push the
	# confirm/skip buttons off-screen (see DialogUtils.popup_centered_capped).
	DialogUtils.popup_centered_capped(dialog)

# ============================================================================
# 11e GDM EXTRACT RELIC / LOCATE AND DENY — MARKER SETUP CHOICE
# ============================================================================

func _check_pending_relic_setup() -> void:
	"""The Disruption player chooses the five marked terrain areas (real
	card: at mission start). The auto-pick stands as backstop; offer a human
	DI player the revision dialog in their Command phase."""
	var current_player = GameState.get_active_player()
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(current_player):
		return  # AI keeps the auto picks
	var pending = MissionManager.get_pending_relic_setup_11e(current_player)
	if pending.is_empty():
		return
	# Let the drawn-missions review dialog close first (exclusive popups)
	if _active_review_dialog and is_instance_valid(_active_review_dialog):
		if not _active_review_dialog.tree_exited.is_connected(_on_review_closed_recheck_condemn):
			_active_review_dialog.tree_exited.connect(_on_review_closed_recheck_condemn)
		return
	# One prompt at a time — the condemn dialog cannot coexist (different
	# cards), but guard against any open exclusive sibling.
	if get_tree().root.get_node_or_null("CondemnChoiceDialog") != null:
		return
	print("CommandController: 11e relic-marker setup pending for P%d (%d eligible, auto %s)" % [
		current_player, pending.get("eligible", []).size(), str(pending.get("current", []))])
	_show_relic_setup_dialog(pending, current_player)

func _show_relic_setup_dialog(pending: Dictionary, player: int) -> void:
	var existing = get_tree().root.get_node_or_null("RelicSetupDialog")
	if existing != null and not existing.is_queued_for_deletion():
		return
	var dialog = AcceptDialog.new()
	dialog.name = "RelicSetupDialog"
	dialog.title = "Operation Markers — Disruption Setup"
	dialog.min_size = DialogConstants.MEDIUM
	dialog.get_ok_button().visible = false
	WhiteDwarfTheme.apply_to_dialog(dialog)

	var content = VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 8)
	content.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	var header = Label.new()
	header.text = "MARK %d TERRAIN AREAS" % int(pending.get("required_picks", 5))
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

	var required: int = int(pending.get("required_picks", 5))
	var current_picks: Array = pending.get("current", [])
	var resolved = [false]
	var checkboxes: Array = []

	var scroll = ScrollContainer.new()
	scroll.name = "EligibleScroll"
	scroll.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 40, 220)
	var check_list = VBoxContainer.new()
	check_list.name = "EligibleList"
	for entry in pending.get("eligible", []):
		var fid: String = str(entry.get("id", ""))
		var check = CheckBox.new()
		check.name = "Check_%s" % fid
		check.text = str(entry.get("label", fid))
		check.button_pressed = fid in current_picks
		check.set_meta("feature_id", fid)
		check.toggled.connect(func(pressed: bool):
			if not pressed:
				return
			var checked = 0
			for c in checkboxes:
				if is_instance_valid(c) and c.button_pressed:
					checked += 1
			if checked > required:
				check.button_pressed = false)
		check_list.add_child(check)
		checkboxes.append(check)
	scroll.add_child(check_list)
	content.add_child(scroll)

	var status = Label.new()
	status.name = "StatusLabel"
	status.text = ""
	status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	content.add_child(status)

	content.add_child(HSeparator.new())
	var button_row = HBoxContainer.new()
	button_row.name = "Actions"
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 12)

	var confirm_btn = Button.new()
	confirm_btn.name = "ConfirmRelicSetup"
	confirm_btn.text = "Place Markers"
	confirm_btn.custom_minimum_size = Vector2(160, 36)
	confirm_btn.pressed.connect(func():
		if resolved[0]:
			return
		var picks = []
		for c in checkboxes:
			if is_instance_valid(c) and c.button_pressed:
				picks.append(str(c.get_meta("feature_id")))
		if picks.size() != required:
			status.text = "Select exactly %d terrain areas (%d selected)" % [required, picks.size()]
			return
		resolved[0] = true
		emit_signal("command_action_requested", {
			"type": "RESOLVE_RELIC_SETUP",
			"player": player,
			"feature_ids": picks,
		})
		dialog.queue_free())
	button_row.add_child(confirm_btn)

	var skip_btn = Button.new()
	skip_btn.name = "SkipRelicSetup"
	skip_btn.text = "Keep Current Locations"
	skip_btn.custom_minimum_size = Vector2(180, 36)
	skip_btn.pressed.connect(func():
		if resolved[0]:
			return
		resolved[0] = true
		emit_signal("command_action_requested", {
			"type": "DISMISS_RELIC_SETUP",
			"player": player,
		})
		dialog.queue_free())
	button_row.add_child(skip_btn)
	content.add_child(button_row)

	# Escape/close keeps the auto picks — never a dead end.
	dialog.canceled.connect(func():
		if resolved[0]:
			return
		resolved[0] = true
		emit_signal("command_action_requested", {
			"type": "DISMISS_RELIC_SETUP",
			"player": player,
		})
		dialog.queue_free())

	dialog.add_child(content)
	get_tree().root.add_child(dialog)
	# Cap to the viewport so the relic description can't push the confirm/skip
	# buttons off-screen (see DialogUtils.popup_centered_capped).
	DialogUtils.popup_centered_capped(dialog)

func _on_mission_drawn(player: int, mission_id: String) -> void:
	"""Handle SecondaryMissionManager mission_drawn signal — rebuild the secondary missions UI."""
	print("CommandController: mission_drawn signal received — Player %d drew %s, refreshing UI" % [player, mission_id])
	_refresh_ui()

func _on_mission_discarded(player: int, mission_id: String, reason: String) -> void:
	"""Handle SecondaryMissionManager mission_discarded signal — rebuild the secondary missions UI."""
	print("CommandController: mission_discarded signal received — Player %d discarded %s (%s), refreshing UI" % [player, mission_id, reason])
	_refresh_ui()

func _on_when_drawn_requires_interaction(player: int, mission_id: String, interaction_type: String, details: Dictionary) -> void:
	"""Handle SecondaryMissionManager requesting opponent interaction for a drawn mission."""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ CommandController: SECONDARY MISSION REQUIRES INTERACTION")
	print("║ Player: %d, Mission: %s, Type: %s" % [player, mission_id, interaction_type])
	print("╚═══════════════════════════════════════════════════════════════")

	var opponent = 2 if player == 1 else 1

	match interaction_type:
		"opponent_selects_units":
			_show_marked_for_death_dialog(player, opponent, details)
		"opponent_selects_objective":
			_show_tempting_target_dialog(player, opponent, details)
		"drawer_selects_unit":
			_show_beacon_dialog(player)
		_:
			push_error("CommandController: Unknown interaction type: %s" % interaction_type)

func _show_marked_for_death_dialog(drawing_player: int, opponent: int, details: Dictionary) -> void:
	"""Show Marked for Death dialog — opponent selects Alpha targets, card holder selects Gamma."""
	# Skip dialog when AI is involved — AIPlayer handles via _on_secondary_requires_interaction
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(opponent):
		if ai_player_node.is_ai_player(drawing_player):
			# Both AI — fully handled by AIPlayer
			print("CommandController: Skipping Marked for Death dialog — both players are AI")
		else:
			# AI opponent will select alphas and emit ai_alpha_targets_selected signal
			# which triggers _on_ai_alpha_targets_selected to show gamma-only dialog
			print("CommandController: Skipping full Marked for Death dialog — AI opponent P%d will select alphas, then human P%d picks gamma" % [opponent, drawing_player])
		return

	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if not secondary_mgr:
		push_error("CommandController: SecondaryMissionManager not found")
		return

	# Get opponent's alive, deployed units (excluding leaders in attached units per FAQ)
	var opponent_unit_ids = secondary_mgr._get_opponent_units_on_battlefield(drawing_player)
	var opponent_units = []
	for unit_id in opponent_unit_ids:
		var unit = GameState.get_unit(unit_id)
		if unit.is_empty():
			continue
		# Per FAQ: Leaders within Attached units cannot be selected for Marked for Death
		var attachment = unit.get("attachment_data", {})
		if attachment.get("is_leader_attached", false):
			print("CommandController: Skipping attached leader %s for Marked for Death eligibility" % unit_id)
			continue
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		opponent_units.append({"unit_id": unit_id, "unit_name": unit_name})

	if opponent_units.is_empty():
		print("CommandController: No eligible opponent units for Marked for Death — skipping dialog")
		return

	var dialog = MarkedForDeathDialog.new()
	dialog.setup(drawing_player, opponent, opponent_units, details)
	dialog.marked_for_death_resolved.connect(_on_marked_for_death_resolved.bind(drawing_player))
	get_tree().root.add_child(dialog)
	DialogUtils.popup_centered_capped(dialog)
	print("CommandController: Marked for Death dialog shown — P%d (opponent) selects Alpha, P%d (card holder) selects Gamma" % [opponent, drawing_player])

func _on_marked_for_death_resolved(alpha_targets: Array, gamma_target: String, drawing_player: int) -> void:
	"""Handle Marked for Death target selection from dialog."""
	print("CommandController: Marked for Death resolved — Alpha: %s, Gamma: %s (drawing player: %d)" % [
		str(alpha_targets), gamma_target, drawing_player])
	emit_signal("command_action_requested", {
		"type": "RESOLVE_MARKED_FOR_DEATH",
		"player": drawing_player,
		"alpha_targets": alpha_targets,
		"gamma_target": gamma_target,
	})

func _on_ai_alpha_targets_selected(drawing_player: int, alpha_targets: Array, eligible_units: Array) -> void:
	"""Handle AI opponent's alpha target selection — show gamma-only dialog for human card holder."""
	print("CommandController: AI selected alpha targets %s, showing gamma selection dialog for human P%d" % [
		str(alpha_targets), drawing_player])

	var opponent = 2 if drawing_player == 1 else 1

	# Build unit list for the dialog (excluding alpha-selected units)
	var remaining_units = []
	for eu in eligible_units:
		if eu.get("id", "") not in alpha_targets:
			var unit = GameState.get_unit(eu.get("id", ""))
			var unit_name = eu.get("name", eu.get("id", ""))
			remaining_units.append({"unit_id": eu.get("id", ""), "unit_name": unit_name})

	if remaining_units.is_empty():
		# No remaining units for gamma — resolve with empty gamma
		print("CommandController: No remaining units for gamma target after AI alpha selection")
		emit_signal("command_action_requested", {
			"type": "RESOLVE_MARKED_FOR_DEATH",
			"player": drawing_player,
			"alpha_targets": alpha_targets,
			"gamma_target": "",
		})
		return

	# Build the full opponent_units list (for display of alpha selections in dialog)
	var all_opponent_units = []
	for eu in eligible_units:
		all_opponent_units.append({"unit_id": eu.get("id", ""), "unit_name": eu.get("name", eu.get("id", ""))})

	var dialog = MarkedForDeathDialog.new()
	dialog.setup_gamma_only(drawing_player, opponent, all_opponent_units, alpha_targets)
	dialog.marked_for_death_resolved.connect(_on_marked_for_death_resolved.bind(drawing_player))
	get_tree().root.add_child(dialog)
	DialogUtils.popup_centered_capped(dialog)
	print("CommandController: Marked for Death gamma-only dialog shown for P%d (card holder)" % drawing_player)

func _show_tempting_target_dialog(drawing_player: int, opponent: int, details: Dictionary) -> void:
	"""Show A Tempting Target dialog for the opponent to select an objective."""
	# Skip dialog for AI players — AIPlayer handles via _on_secondary_requires_interaction
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(opponent):
		print("CommandController: Skipping Tempting Target dialog for AI player %d" % opponent)
		return

	# Dedup: the direct signal AND the set_phase pending-recheck can both fire
	var existing = get_tree().root.get_node_or_null("TemptingTargetDialog")
	if existing != null and not existing.is_queued_for_deletion():
		return

	# Get objectives in No Man's Land
	var all_objectives = GameState.state.get("board", {}).get("objectives", [])
	var nml_objectives = []
	for obj in all_objectives:
		if obj.get("zone", "") == "no_mans_land":
			nml_objectives.append(obj)

	if nml_objectives.is_empty():
		print("CommandController: No NML objectives for A Tempting Target — skipping dialog")
		return

	var dialog = TemptingTargetDialog.new()
	dialog.name = "TemptingTargetDialog"
	dialog.setup(opponent, nml_objectives)
	dialog.tempting_target_resolved.connect(_on_tempting_target_resolved.bind(drawing_player))
	get_tree().root.add_child(dialog)
	DialogUtils.popup_centered_capped(dialog)
	print("CommandController: A Tempting Target dialog shown for player %d to select objective" % opponent)

func _on_tempting_target_resolved(objective_id: String, drawing_player: int) -> void:
	"""Handle Tempting Target objective selection from dialog."""
	print("CommandController: A Tempting Target resolved — Objective: %s (drawing player: %d)" % [
		objective_id, drawing_player])
	emit_signal("command_action_requested", {
		"type": "RESOLVE_TEMPTING_TARGET",
		"player": drawing_player,
		"objective_id": objective_id,
	})

# ============================================================================
# 11e BEACON — DRAWER DESIGNATES THE BEACON UNIT
# ============================================================================

func _show_beacon_dialog(drawing_player: int) -> void:
	"""11e Beacon: the DRAWER designates one friendly unit on the battlefield
	(or embarked in a TRANSPORT on the battlefield) as their beacon unit."""
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(drawing_player):
		print("CommandController: Skipping Beacon dialog for AI player %d" % drawing_player)
		return

	var existing = get_tree().root.get_node_or_null("BeaconUnitDialog")
	if existing != null and not existing.is_queued_for_deletion():
		return

	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if not secondary_mgr:
		return
	var eligible = secondary_mgr.get_beacon_eligible_units(drawing_player)
	if eligible.is_empty():
		print("CommandController: No eligible Beacon units for player %d — skipping dialog" % drawing_player)
		return

	var dialog = AcceptDialog.new()
	dialog.name = "BeaconUnitDialog"
	dialog.title = "Beacon — Designate Your Beacon Unit"
	dialog.min_size = DialogConstants.MEDIUM
	dialog.get_ok_button().visible = false
	WhiteDwarfTheme.apply_to_dialog(dialog)

	var content = VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 8)
	content.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	var header = Label.new()
	header.text = "BEACON"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(header)

	var desc = Label.new()
	desc.text = "Designate one friendly unit as your beacon unit.\nScore at the end of your opponent's turn: 3 VP if it is on the battlefield and not within your deployment zone, 5 VP if it is not within your territory."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color.GRAY)
	content.add_child(desc)
	content.add_child(HSeparator.new())

	var scroll = ScrollContainer.new()
	scroll.name = "UnitScroll"
	scroll.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 220)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var unit_list = VBoxContainer.new()
	unit_list.name = "UnitList"
	unit_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(unit_list)
	content.add_child(scroll)

	var resolved = [false]
	for entry in eligible:
		var unit_id: String = str(entry.get("unit_id", ""))
		var label: String = str(entry.get("unit_name", unit_id))
		if entry.get("embarked", false):
			label += " (embarked)"
		var btn = Button.new()
		btn.name = "Pick_%s" % unit_id
		btn.text = label
		btn.custom_minimum_size = Vector2(410, 36)
		btn.pressed.connect(func():
			if resolved[0]:
				return
			resolved[0] = true
			emit_signal("command_action_requested", {
				"type": "RESOLVE_BEACON_UNIT",
				"player": drawing_player,
				"unit_id": unit_id,
			})
			dialog.queue_free())
		unit_list.add_child(btn)

	# Closing without picking is not a dead end — the card just stays pending
	# and the prompt reopens on the next Command phase entry.
	dialog.add_child(content)
	get_tree().root.add_child(dialog)
	DialogUtils.popup_centered_capped(dialog)
	print("CommandController: Beacon designation dialog shown for player %d (%d eligible units)" % [drawing_player, eligible.size()])

# ============================================================================
# 11e BURDEN OF TRUST — GUARD SELECTION PROMPT
# ============================================================================

func _check_pending_guard_prompt() -> void:
	"""11e Burden of Trust: guards were auto-assigned when drawn / at turn
	start. Offer the HUMAN holder a dialog to revise them."""
	var current_player = GameState.get_active_player()
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(current_player):
		return  # AI keeps the auto picks
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if not secondary_mgr or not secondary_mgr.has_method("get_pending_guard_choice"):
		return
	var pending = secondary_mgr.get_pending_guard_choice(current_player)
	if pending.is_empty():
		return
	# Sequence behind the drawn-missions review dialog (exclusive popups).
	if _active_review_dialog and is_instance_valid(_active_review_dialog):
		if not _active_review_dialog.tree_exited.is_connected(_on_review_closed_recheck_condemn):
			_active_review_dialog.tree_exited.connect(_on_review_closed_recheck_condemn)
		return
	_show_guard_dialog(pending, current_player)

func _show_guard_dialog(pending: Dictionary, player: int) -> void:
	var existing = get_tree().root.get_node_or_null("GuardSelectionDialog")
	if existing != null and not existing.is_queued_for_deletion():
		return
	var objectives: Array = pending.get("objectives", [])
	if objectives.is_empty():
		# Nothing in range of any marker — keep the (empty) auto picks quietly.
		emit_signal("command_action_requested", {"type": "DISMISS_GUARDS", "player": player})
		return

	var current_guards: Dictionary = pending.get("guards", {})

	var dialog = AcceptDialog.new()
	dialog.name = "GuardSelectionDialog"
	dialog.title = "Burden of Trust — Assign Guards"
	dialog.min_size = DialogConstants.MEDIUM
	dialog.get_ok_button().visible = false
	WhiteDwarfTheme.apply_to_dialog(dialog)

	var content = VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 8)
	content.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	var header = Label.new()
	header.text = "SELECT ONE FRIENDLY UNIT PER OBJECTIVE TO GUARD IT"
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(header)

	var desc = Label.new()
	desc.text = "Pick any friendly unit to guard each objective (units in range now are marked). At the end of your opponent's turn you score 2 VP (max 5) for each guarded objective you control while its guard is within range of it."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color.GRAY)
	content.add_child(desc)
	content.add_child(HSeparator.new())

	var scroll = ScrollContainer.new()
	scroll.name = "ObjectiveScroll"
	# Keep a modest minimum so the objective list can shrink (and the fixed
	# Confirm / Keep buttons stay on-screen) when the dialog is capped to a
	# small viewport; SIZE_EXPAND_FILL still grows it on roomier screens.
	scroll.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 160)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rows = VBoxContainer.new()
	rows.name = "ObjectiveRows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	content.add_child(scroll)

	var pickers: Array = []  # [{objective_id, option_button, unit_ids}]
	for entry in objectives:
		var obj_id: String = str(entry.get("objective_id", ""))
		var row = HBoxContainer.new()
		row.name = "Row_%s" % obj_id
		row.add_theme_constant_override("separation", 8)
		var obj_label = Label.new()
		obj_label.text = obj_id.replace("obj_", "Objective ").replace("_", " ").capitalize()
		obj_label.custom_minimum_size = Vector2(150, 0)
		row.add_child(obj_label)

		var picker = OptionButton.new()
		picker.name = "Guard_%s" % obj_id
		picker.custom_minimum_size = Vector2(230, 32)
		picker.add_item("— No guard —")
		picker.set_item_metadata(0, "")
		var unit_ids := [""]
		var idx := 1
		for eu in entry.get("eligible", []):
			var uid: String = str(eu.get("unit_id", ""))
			# Any friendly unit can be picked; annotate the ones that are actually
			# in range now (they score) or embarked (they can't score until they
			# disembark and get in range) so the choice is informed.
			var item_label: String = str(eu.get("unit_name", uid))
			if eu.get("embarked", false):
				item_label += " (embarked)"
			elif eu.get("in_range", false):
				item_label += " (in range)"
			picker.add_item(item_label)
			picker.set_item_metadata(idx, uid)
			unit_ids.append(uid)
			if str(current_guards.get(obj_id, "")) == uid:
				picker.select(idx)
			idx += 1
		row.add_child(picker)
		rows.add_child(row)
		pickers.append({"objective_id": obj_id, "picker": picker})

	content.add_child(HSeparator.new())
	var status = Label.new()
	status.name = "StatusLabel"
	status.text = ""
	status.add_theme_color_override("font_color", Color.ORANGE)
	content.add_child(status)

	var button_row = HBoxContainer.new()
	button_row.name = "Actions"
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 12)

	var resolved = [false]
	var confirm_btn = Button.new()
	confirm_btn.name = "ConfirmGuards"
	confirm_btn.text = "Confirm Guards"
	confirm_btn.custom_minimum_size = Vector2(170, 36)
	confirm_btn.pressed.connect(func():
		if resolved[0]:
			return
		# One distinct unit per objective — refuse duplicate picks in place.
		var picks: Dictionary = {}
		var used: Dictionary = {}
		for p in pickers:
			var picker: OptionButton = p["picker"]
			var uid = str(picker.get_item_metadata(picker.selected)) if picker.selected >= 0 else ""
			if uid == "":
				continue
			if used.has(uid):
				status.text = "Each unit can guard only one objective."
				return
			used[uid] = true
			picks[p["objective_id"]] = uid
		resolved[0] = true
		emit_signal("command_action_requested", {
			"type": "RESOLVE_GUARDS",
			"player": player,
			"guards": picks,
		})
		dialog.queue_free())
	button_row.add_child(confirm_btn)

	var skip_btn = Button.new()
	skip_btn.name = "KeepAutoGuards"
	skip_btn.text = "Keep Auto Picks"
	skip_btn.custom_minimum_size = Vector2(150, 36)
	skip_btn.pressed.connect(func():
		if resolved[0]:
			return
		resolved[0] = true
		emit_signal("command_action_requested", {"type": "DISMISS_GUARDS", "player": player})
		dialog.queue_free())
	button_row.add_child(skip_btn)
	content.add_child(button_row)

	# Escape/close keeps the auto picks — never a dead end.
	dialog.canceled.connect(func():
		if resolved[0]:
			return
		resolved[0] = true
		emit_signal("command_action_requested", {"type": "DISMISS_GUARDS", "player": player})
		dialog.queue_free())

	dialog.add_child(content)
	get_tree().root.add_child(dialog)

	# Cap the dialog to the viewport so the Confirm / Keep buttons can never be
	# pushed off the bottom of the screen. The autowrap description Label reports
	# a very tall minimum height during the initial popup_centered() (before it
	# has been laid out to a width), which previously sized the AcceptDialog
	# window to thousands of pixels tall and scrolled the action buttons
	# off-screen — the player could see the objective pickers but had no way to
	# confirm. Height grows with the objective count but never past 90% of the
	# viewport; the inner ObjectiveScroll absorbs any overflow.
	DialogUtils.popup_centered_capped(dialog, DialogConstants.MEDIUM, 230.0 + float(objectives.size()) * 40.0)
	print("CommandController: Burden of Trust guard dialog shown for player %d (%d objectives)" % [player, objectives.size()])


# T-096: compute command phase sub-step progress (1/3 → 3/3)
# Steps:
#   1/3 — CP Generation (auto, runs on entry)
#   2/3 — Battle Mastery selection (Adeptus Custodes only)
#   3/3 — Stratagems / End Phase
func _compute_command_phase_progress() -> String:
	if not GameState:
		return "Step ?/3"
	var active_player = GameState.get_active_player()
	var faction = GameState.get_faction_name(active_player)
	# Step 1: CP generated (always done by phase entry — assume past step 1)
	# Step 2: Battle Mastery still needs selection?
	var meta = GameState.state.get("meta", {})
	var selected_mastery = meta.get("martial_mastery_choice_p%d" % active_player, "")
	var requires_mastery = (faction == "Adeptus Custodes")
	if requires_mastery and selected_mastery == "":
		return "Step 2/3 — Choose Martial Mastery"
	# Step 3: stratagems / end phase
	return "Step 3/3 — Stratagems / End Phase"
