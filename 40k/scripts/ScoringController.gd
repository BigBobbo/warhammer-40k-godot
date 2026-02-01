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
	var scoring_controls = get_node_or_null("/root/Main/HUD_Bottom/HBoxContainer/ScoringControls")
	if scoring_controls and is_instance_valid(scoring_controls):
		scoring_controls.queue_free()
	
	# Clean up right panel elements
	var container = get_node_or_null("/root/Main/HUD_Right/VBoxContainer")
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
	hud_bottom = get_node_or_null("/root/Main/HUD_Bottom")
	hud_right = get_node_or_null("/root/Main/HUD_Right")
	
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

	# Battle round info
	battle_round_label = Label.new()
	battle_round_label.text = "Battle Round " + str(GameState.get_battle_round())
	battle_round_label.name = "BattleRoundLabel"
	battle_round_label.add_theme_font_size_override("font_size", 14)
	controls_container.add_child(battle_round_label)

	# Separator
	controls_container.add_child(VSeparator.new())

	# Turn info
	turn_info_label = Label.new()
	var current_player = GameState.get_active_player()
	turn_info_label.text = "Player %d Turn" % current_player
	turn_info_label.name = "TurnInfoLabel"
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
	
	# Title
	var title = Label.new()
	title.text = "Scoring Phase"
	title.add_theme_font_size_override("font_size", 16)
	scoring_panel.add_child(title)
	
	scoring_panel.add_child(HSeparator.new())
	
	# Game status info
	var game_status_label = Label.new()
	var battle_round = GameState.get_battle_round()
	var current_player = GameState.get_active_player()
	var total_rounds = 5
	game_status_label.text = "Battle Round: %d/%d\nActive Player: %d\n\nThis is a placeholder scoring phase.\nClick 'End Turn' to switch to the next player." % [battle_round, total_rounds, current_player]
	game_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scoring_panel.add_child(game_status_label)
	
	scoring_panel.add_child(HSeparator.new())
	
	# Game end check
	if GameState.get_battle_round() > 5:
		var game_end_label = Label.new()
		game_end_label.text = "[color=red][b]GAME COMPLETE![/b][/color]\n5 Battle Rounds finished!"
		game_end_label.bbcode_enabled = true
		game_end_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		scoring_panel.add_child(game_end_label)
	else:
		# Turn instructions
		var instruction_label = Label.new()
		instruction_label.text = "Player %d, you may now:\n• Score objectives (not implemented)\n• Check victory conditions\n• End your turn" % current_player
		instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		scoring_panel.add_child(instruction_label)

func set_phase(phase: BasePhase) -> void:
	current_phase = phase
	
	if phase:
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
