extends Node2D
class_name CommandController

# CommandController - Handles UI interactions for the Command Phase
# Currently a placeholder phase that will be expanded with command point functionality

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

func _exit_tree() -> void:
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
	info_label.text = "Battle Round: %d\nActive Player: %d\n\nThis is a placeholder command phase.\n\nFuture features:\n• Command Points management\n• Strategic abilities\n• Battle tactics\n\nClick 'End Command Phase' to proceed to Movement." % [battle_round, current_player]
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	command_panel.add_child(info_label)
	
	command_panel.add_child(HSeparator.new())
	
	# Placeholder for future command point display
	var cp_label = Label.new()
	cp_label.text = "Command Points: Not Implemented"
	cp_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	command_panel.add_child(cp_label)
	
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

func set_phase(phase: BasePhase) -> void:
	current_phase = phase
	print("DEBUG: CommandController.set_phase called with phase type: ", phase.get_class() if phase else "null")
	
	if phase:
		# Update UI elements with current game state
		_refresh_ui()
		show()
	else:
		hide()

func _refresh_ui() -> void:
	# Update phase info label
	if phase_info_label:
		var current_player = GameState.get_active_player()
		var battle_round = GameState.get_battle_round()
		phase_info_label.text = "Player %d - Round %d" % [current_player, battle_round]

func _on_end_command_pressed() -> void:
	print("CommandController: End Command Phase button pressed")
	emit_signal("command_action_requested", {"type": "END_COMMAND"})