extends Node2D
class_name CommandController

const BasePhase = preload("res://phases/BasePhase.gd")


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
	var command_controls = get_node_or_null("/root/Main/HUD_Bottom/HBoxContainer/CommandControls")
	if command_controls and is_instance_valid(command_controls):
		command_controls.queue_free()

	# Clean up right panel elements
	var container = get_node_or_null("/root/Main/HUD_Right/VBoxContainer")
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
	hud_bottom = get_node_or_null("/root/Main/HUD_Bottom")
	hud_right = get_node_or_null("/root/Main/HUD_Right")
	
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
		var command_panel = get_node_or_null("/root/Main/HUD_Right/VBoxContainer/CommandScrollContainer/CommandPanel")
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
	title.text = "Command Phase"
	title.add_theme_font_size_override("font_size", 16)
	command_panel.add_child(title)
	
	command_panel.add_child(HSeparator.new())
	
	# Phase information
	var info_label = Label.new()
	var current_player = GameState.get_active_player()
	var battle_round = GameState.get_battle_round()
	var faction_name = GameState.get_faction_name(current_player)
	info_label.text = "Battle Round: %d\nActive Player: %d (%s)" % [battle_round, current_player, faction_name]
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	command_panel.add_child(info_label)

	command_panel.add_child(HSeparator.new())

	# Command Points display
	var cp_section = VBoxContainer.new()
	cp_section.name = "CPSection"
	command_panel.add_child(cp_section)

	var cp_title = Label.new()
	cp_title.text = "Command Points"
	cp_title.add_theme_font_size_override("font_size", 14)
	cp_section.add_child(cp_title)

	var p1_cp = GameState.state.get("players", {}).get("1", {}).get("cp", 0)
	var p2_cp = GameState.state.get("players", {}).get("2", {}).get("cp", 0)

	var p1_cp_label = Label.new()
	p1_cp_label.name = "P1CPLabel"
	p1_cp_label.text = "Player 1 (%s): %d CP" % [GameState.get_faction_name(1), p1_cp]
	p1_cp_label.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
	cp_section.add_child(p1_cp_label)

	var p2_cp_label = Label.new()
	p2_cp_label.name = "P2CPLabel"
	p2_cp_label.text = "Player 2 (%s): %d CP" % [GameState.get_faction_name(2), p2_cp]
	p2_cp_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	cp_section.add_child(p2_cp_label)

	var cp_note = Label.new()
	cp_note.text = "+1 CP generated this phase"
	cp_note.add_theme_font_size_override("font_size", 11)
	cp_note.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	cp_section.add_child(cp_note)
	
	# Add objective status section
	command_panel.add_child(HSeparator.new())
	
	var objectives_section = VBoxContainer.new()
	objectives_section.name = "ObjectivesSection"
	command_panel.add_child(objectives_section)
	
	var obj_title = Label.new()
	obj_title.text = "Objectives"
	obj_title.add_theme_font_size_override("font_size", 14)
	objectives_section.add_child(obj_title)
	
	# Show objective control status
	if MissionManager:
		var control_summary = MissionManager.get_objective_control_summary()
		for obj_id in control_summary.objectives:
			var obj_label = Label.new()
			var controller = control_summary.objectives[obj_id]
			var control_text = "Uncontrolled"
			var text_color = Color(0.7, 0.7, 0.7)
			if controller == 1:
				control_text = "Player 1"
				text_color = Color(0.4, 0.6, 1.0)  # Blue
			elif controller == 2:
				control_text = "Player 2"
				text_color = Color(1.0, 0.4, 0.4)  # Red
			else:
				control_text = "Contested"
				text_color = Color(1.0, 1.0, 0.5)  # Yellow
			
			obj_label.text = "%s: %s" % [obj_id.replace("obj_", "").to_upper(), control_text]
			obj_label.add_theme_color_override("font_color", text_color)
			objectives_section.add_child(obj_label)
	
	# Battle-shock tests and Stratagems section
	_setup_battle_shock_section(command_panel)

	# Faction abilities section (Oath of Moment, etc.)
	_setup_faction_abilities_section(command_panel)

	# Show VP status
	command_panel.add_child(HSeparator.new())

	var vp_section = VBoxContainer.new()
	vp_section.name = "VPSection"
	command_panel.add_child(vp_section)

	var vp_title = Label.new()
	vp_title.text = "Victory Points"
	vp_title.add_theme_font_size_override("font_size", 14)
	vp_section.add_child(vp_title)

	if MissionManager:
		var vp_summary = MissionManager.get_vp_summary()

		var p1_vp_label = Label.new()
		p1_vp_label.text = "Player 1: %d VP (Primary: %d)" % [
			vp_summary.player1.total,
			vp_summary.player1.primary
		]
		p1_vp_label.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
		vp_section.add_child(p1_vp_label)

		var p2_vp_label = Label.new()
		p2_vp_label.text = "Player 2: %d VP (Primary: %d)" % [
			vp_summary.player2.total,
			vp_summary.player2.primary
		]
		p2_vp_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		vp_section.add_child(p2_vp_label)

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

	command_panel.add_child(HSeparator.new())

	var section = VBoxContainer.new()
	section.name = "SecondaryMissionsSection"
	section.add_theme_constant_override("separation", 4)
	command_panel.add_child(section)

	# Section header
	var section_title = Label.new()
	section_title.text = "Secondary Missions"
	section_title.add_theme_font_size_override("font_size", 14)
	section_title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3))
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

	# Pending interaction indicator
	if mission.get("pending_interaction", false):
		var pending_label = Label.new()
		pending_label.text = "AWAITING INTERACTION"
		pending_label.add_theme_font_size_override("font_size", 10)
		pending_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
		card_vbox.add_child(pending_label)

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
	WhiteDwarfTheme.apply_to_button(discard_btn)
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

	parent.add_child(HSeparator.new())

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

	command_panel.add_child(HSeparator.new())

	var shock_section = VBoxContainer.new()
	shock_section.name = "BattleShockSection"
	command_panel.add_child(shock_section)

	var shock_title = Label.new()
	shock_title.text = "Battle-shock Tests"
	shock_title.add_theme_font_size_override("font_size", 14)
	shock_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
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
		WhiteDwarfTheme.apply_to_button(test_btn)
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
			unit_box.add_child(strat_btn)

		unit_box.add_child(HSeparator.new())

func _setup_faction_abilities_section(command_panel: VBoxContainer) -> void:
	"""Build faction abilities display (Oath of Moment target selection, etc.)."""
	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	if not faction_mgr:
		return

	var current_player = GameState.get_active_player()
	if not faction_mgr.player_has_ability(current_player, "Oath of Moment"):
		return

	command_panel.add_child(HSeparator.new())

	var section = VBoxContainer.new()
	section.name = "FactionAbilitiesSection"
	section.add_theme_constant_override("separation", 4)
	command_panel.add_child(section)

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
			WhiteDwarfTheme.apply_to_button(btn)
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

func set_phase(phase: BasePhase) -> void:
	current_phase = phase
	print("DEBUG: CommandController.set_phase called with phase type: ", phase.get_class() if phase else "null")

	if phase:
		# Connect command_reroll_opportunity signal if available
		if phase.has_signal("command_reroll_opportunity"):
			if not phase.command_reroll_opportunity.is_connected(_on_command_reroll_opportunity):
				phase.command_reroll_opportunity.connect(_on_command_reroll_opportunity)

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

		# Update UI elements with current game state
		_refresh_ui()
		show()

		# Show review dialog for newly drawn secondary missions
		_show_drawn_missions_review_dialog()
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
	var command_panel = get_node_or_null("/root/Main/HUD_Right/VBoxContainer/CommandScrollContainer/CommandPanel")
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

		# Rebuild the faction abilities section to reflect Oath of Moment changes
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
	var player_cp = GameState.state.get("players", {}).get(str(current_player), {}).get("cp", 0)

	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	var deck_size = 0
	if secondary_mgr:
		deck_size = secondary_mgr.get_deck_size(current_player)

	print("CommandController: Showing secondary mission review dialog for player %d (%d missions drawn, %d CP, %d deck)" % [
		current_player, drawn_missions.size(), player_cp, deck_size])

	var dialog = SecondaryMissionReviewDialog.new()
	dialog.setup(current_player, drawn_missions, player_cp, deck_size)
	dialog.mission_replacement_requested.connect(_on_mission_replacement_requested)
	dialog.review_completed.connect(_on_mission_review_completed)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()

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

func _on_mission_review_completed() -> void:
	"""Handle player accepting drawn missions without replacement."""
	print("CommandController: Player accepted drawn missions without replacement")
	if current_phase and current_phase.has_method("clear_newly_drawn_missions"):
		current_phase.clear_newly_drawn_missions()

# ============================================================================
# SECONDARY MISSION INTERACTION HANDLERS
# ============================================================================

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
		_:
			push_error("CommandController: Unknown interaction type: %s" % interaction_type)

func _show_marked_for_death_dialog(drawing_player: int, opponent: int, details: Dictionary) -> void:
	"""Show Marked for Death dialog for the opponent to select targets."""
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if not secondary_mgr:
		push_error("CommandController: SecondaryMissionManager not found")
		return

	# Get opponent's alive, deployed units
	var opponent_unit_ids = secondary_mgr._get_opponent_units_on_battlefield(drawing_player)
	var opponent_units = []
	for unit_id in opponent_unit_ids:
		var unit = GameState.get_unit(unit_id)
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		opponent_units.append({"unit_id": unit_id, "unit_name": unit_name})

	if opponent_units.is_empty():
		print("CommandController: No opponent units for Marked for Death — skipping dialog")
		return

	var dialog = MarkedForDeathDialog.new()
	dialog.setup(opponent, opponent_units, details)
	dialog.marked_for_death_resolved.connect(_on_marked_for_death_resolved.bind(drawing_player))
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	print("CommandController: Marked for Death dialog shown for player %d to select targets" % opponent)

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

func _show_tempting_target_dialog(drawing_player: int, opponent: int, details: Dictionary) -> void:
	"""Show A Tempting Target dialog for the opponent to select an objective."""
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
	dialog.setup(opponent, nml_objectives)
	dialog.tempting_target_resolved.connect(_on_tempting_target_resolved.bind(drawing_player))
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
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
