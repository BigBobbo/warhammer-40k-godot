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
var end_command_button: Button
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
	# Get the main HBox container in bottom HUD
	var main_container = hud_bottom.get_node_or_null("HBoxContainer")
	if not main_container:
		print("ERROR: Cannot find HBoxContainer in HUD_Bottom")
		return
	
	# Check for existing command controls container
	var controls_container = main_container.get_node_or_null("CommandControls")
	if not controls_container:
		controls_container = HBoxContainer.new()
		controls_container.name = "CommandControls"
		main_container.add_child(controls_container)
		
		# Add separator before command controls
		controls_container.add_child(VSeparator.new())
	else:
		# Clear existing children to prevent duplicates
		print("CommandController: Removing existing command controls children (", controls_container.get_children().size(), " children)")
		for child in controls_container.get_children():
			controls_container.remove_child(child)
			child.free()
	
	# Phase label
	var phase_label = Label.new()
	phase_label.text = "COMMAND PHASE"
	phase_label.add_theme_font_size_override("font_size", 18)
	controls_container.add_child(phase_label)
	
	# Separator
	controls_container.add_child(VSeparator.new())
	
	# Phase info
	phase_info_label = Label.new()
	var current_player = GameState.get_active_player()
	var battle_round = GameState.get_battle_round()
	phase_info_label.text = "Player %d - Round %d" % [current_player, battle_round]
	phase_info_label.name = "PhaseInfoLabel"
	controls_container.add_child(phase_info_label)
	
	# Separator
	controls_container.add_child(VSeparator.new())
	
	# End Command Phase button
	end_command_button = Button.new()
	end_command_button.text = "End Command Phase"
	end_command_button.pressed.connect(_on_end_command_pressed)
	end_command_button.add_theme_font_size_override("font_size", 14)
	controls_container.add_child(end_command_button)

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