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

	var battle_round = GameState.get_battle_round()
	var current_player = GameState.get_active_player()
	var total_rounds = 5

	# VP Summary
	var vp_summary = MissionManager.get_vp_summary()
	var vp_label = Label.new()
	vp_label.text = "Battle Round: %d/%d\n\nVP Summary:\n  Player 1: %d VP (Primary: %d, Secondary: %d)\n  Player 2: %d VP (Primary: %d, Secondary: %d)" % [
		battle_round, total_rounds,
		vp_summary["player1"]["total"], vp_summary["player1"]["primary"], vp_summary["player1"]["secondary"],
		vp_summary["player2"]["total"], vp_summary["player2"]["primary"], vp_summary["player2"]["secondary"],
	]
	vp_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scoring_panel.add_child(vp_label)

	scoring_panel.add_child(HSeparator.new())

	# Secondary Missions display
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if secondary_mgr and secondary_mgr.is_initialized(current_player):
		var missions_title = Label.new()
		missions_title.text = "Player %d - Active Secondary Missions" % current_player
		missions_title.add_theme_font_size_override("font_size", 14)
		scoring_panel.add_child(missions_title)

		var active_missions = secondary_mgr.get_active_missions(current_player)
		if active_missions.size() == 0:
			var no_missions = Label.new()
			no_missions.text = "  No active secondary missions"
			scoring_panel.add_child(no_missions)
		else:
			for i in range(active_missions.size()):
				var mission = active_missions[i]
				var mission_label = Label.new()
				var timing = mission.get("scoring", {}).get("when", "")
				var timing_text = ""
				match timing:
					"end_of_your_turn": timing_text = "End of your turn"
					"end_of_either_turn": timing_text = "End of either turn"
					"end_of_opponent_turn": timing_text = "End of opponent's turn"
					"while_active": timing_text = "While active"

				mission_label.text = "  [%d] %s\n      Category: %s | Scores: %s" % [
					i + 1, mission["name"], mission["category"].capitalize(), timing_text]
				if mission.get("pending_interaction", false):
					mission_label.text += "\n      (Awaiting opponent interaction)"
				mission_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				scoring_panel.add_child(mission_label)

		# Deck info
		var deck_label = Label.new()
		deck_label.text = "\n  Deck: %d cards remaining | Discarded: %d" % [
			secondary_mgr.get_deck_size(current_player),
			secondary_mgr.get_discard_size(current_player)]
		scoring_panel.add_child(deck_label)

		scoring_panel.add_child(HSeparator.new())

	# Game end check
	if GameState.get_battle_round() > 5:
		var game_end_label = Label.new()
		game_end_label.text = "GAME COMPLETE!\n5 Battle Rounds finished!"
		game_end_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		scoring_panel.add_child(game_end_label)
	else:
		var instruction_label = Label.new()
		instruction_label.text = "Player %d, you may:\n- Discard a secondary mission (gain 1 CP)\n- End your turn" % current_player
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
