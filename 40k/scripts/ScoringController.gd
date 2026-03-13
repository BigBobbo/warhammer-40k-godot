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

	# Objective Control display
	_build_objective_control_section(scoring_panel, current_player)

	scoring_panel.add_child(HSeparator.new())

	# Secondary Missions display with discard buttons and progress tracking
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if secondary_mgr and secondary_mgr.is_initialized(current_player):
		var missions_title = Label.new()
		missions_title.text = "Player %d - Active Secondary Missions" % current_player
		missions_title.add_theme_font_size_override("font_size", 14)
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
		var cp_note = "+1 CP" if GameState.can_gain_bonus_cp(GameState.get_active_player()) else "+0 CP (bonus cap reached)"
		instruction_label.text = "Press a Discard button above to discard\na secondary for %s, or End Turn below." % cp_note
		instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		scoring_panel.add_child(instruction_label)

func _build_objective_control_section(panel: VBoxContainer, _current_player: int) -> void:
	var obj_title = Label.new()
	obj_title.text = "Objective Control"
	obj_title.add_theme_font_size_override("font_size", 14)
	panel.add_child(obj_title)

	var objectives = GameState.state.board.get("objectives", [])
	var control_state = MissionManager.objective_control_state

	if objectives.size() == 0:
		var no_obj = Label.new()
		no_obj.text = "  No objectives on the board"
		panel.add_child(no_obj)
		return

	var p1_controlled = 0
	var p2_controlled = 0
	var contested = 0

	for obj in objectives:
		var obj_id = obj.get("id", "unknown")
		var zone = obj.get("zone", "unknown")
		var controller = control_state.get(obj_id, 0)

		var controller_text = "Contested"
		if controller == 1:
			controller_text = "Player 1"
			p1_controlled += 1
		elif controller == 2:
			controller_text = "Player 2"
			p2_controlled += 1
		else:
			contested += 1

		var zone_text = ""
		match zone:
			"player1": zone_text = "P1 Zone"
			"player2": zone_text = "P2 Zone"
			"no_mans_land": zone_text = "NML"
			_: zone_text = zone

		var obj_label = Label.new()
		obj_label.text = "  %s [%s]: %s" % [obj_id, zone_text, controller_text]
		panel.add_child(obj_label)

	# Summary line
	var summary = Label.new()
	summary.text = "\n  P1: %d | P2: %d | Contested: %d" % [p1_controlled, p2_controlled, contested]
	panel.add_child(summary)

	# Show current mission scoring info
	var mission_name = MissionManager.get_current_mission_name()
	var mission_info = Label.new()
	mission_info.text = "  Mission: %s" % mission_name
	panel.add_child(mission_info)

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

	# Discard button — show CP gain status based on bonus CP cap
	var discard_btn = Button.new()
	var can_gain_cp = GameState.can_gain_bonus_cp(GameState.get_active_player())
	var cp_label = "+1 CP" if can_gain_cp else "+0 CP (cap)"
	discard_btn.text = "Discard \"%s\" (%s)" % [mission.get("name", "?"), cp_label]
	discard_btn.custom_minimum_size = Vector2(0, 28)
	discard_btn.add_theme_font_size_override("font_size", 11)
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

	var dialog = ConfirmationDialog.new()
	dialog.title = "Acrobatic Escape: %s" % unit_name
	dialog.dialog_text = "ACROBATIC ESCAPE\n\n%s is not within 3\" of any enemy units.\n\nRemove this model from the battlefield?\nIt will return in the Reinforcements step of your next Movement phase (more than 9\" from all enemies).\n\nWARNING: If the battle ends while this model is off the battlefield, it is destroyed." % unit_name
	dialog.ok_button_text = "Vanish"
	dialog.cancel_button_text = "Stay"
	dialog.min_size = DialogConstants.MEDIUM

	dialog.confirmed.connect(func():
		print("[ScoringController] Acrobatic Escape vanish confirmed for %s" % unit_id)
		emit_signal("scoring_action_requested", {
			"type": "ACROBATIC_ESCAPE_VANISH",
			"unit_id": unit_id,
			"player": player,
		})
		dialog.queue_free()
	)
	dialog.canceled.connect(func():
		print("[ScoringController] Acrobatic Escape vanish declined for %s" % unit_id)
		emit_signal("scoring_action_requested", {
			"type": "DECLINE_ACROBATIC_ESCAPE_VANISH",
			"unit_id": unit_id,
			"player": player,
		})
		dialog.queue_free()
	)

	get_tree().root.add_child(dialog)
	dialog.popup_centered()
