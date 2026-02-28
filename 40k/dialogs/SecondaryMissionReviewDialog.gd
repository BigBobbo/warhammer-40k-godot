extends AcceptDialog
class_name SecondaryMissionReviewDialog

# SecondaryMissionReviewDialog - Shows newly drawn secondary missions to the player
# and offers the option to spend 1 CP to replace one of them.
# The replaced mission goes back into the deck (not discard pile).

signal mission_replacement_requested(mission_id: String)
signal review_completed()

var _player: int = 0
var _drawn_missions: Array = []
var _player_cp: int = 0
var _deck_size: int = 0
var _can_replace: bool = false
var _replacement_used: bool = false

func setup(player: int, drawn_missions: Array, player_cp: int, deck_size: int) -> void:
	_player = player
	_drawn_missions = drawn_missions
	_player_cp = player_cp
	_deck_size = deck_size
	_can_replace = player_cp >= 1 and deck_size > 0

	var faction_name = GameState.get_faction_name(player)
	title = "Secondary Missions Drawn - Player %d (%s)" % [player, faction_name]

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	# Prevent closing via X button without completing
	close_requested.connect(_on_done_pressed)

	_build_ui()

func _build_ui() -> void:
	min_size = DialogConstants.MEDIUM
	var main_container = VBoxContainer.new()
	main_container.name = "MainContainer"
	main_container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	# Header
	var header = Label.new()
	header.text = "NEW SECONDARY MISSIONS"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	# Subheader
	var subheader = Label.new()
	subheader.text = "Your secondary objectives for this turn"
	subheader.add_theme_font_size_override("font_size", 12)
	subheader.add_theme_color_override("font_color", Color.GRAY)
	subheader.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(subheader)

	main_container.add_child(HSeparator.new())

	# Show each drawn mission
	for i in range(_drawn_missions.size()):
		var mission = _drawn_missions[i]
		_add_mission_card(main_container, mission, i)

	main_container.add_child(HSeparator.new())

	# Replacement info
	var replace_info = Label.new()
	if _can_replace:
		replace_info.text = "You may spend 1 CP to replace one mission (it returns to your deck).\nYou have %d CP | Deck: %d cards remaining" % [_player_cp, _deck_size]
		replace_info.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	else:
		if _player_cp < 1:
			replace_info.text = "Not enough CP to replace a mission (need 1 CP, have %d)" % _player_cp
		elif _deck_size == 0:
			replace_info.text = "Deck is empty - cannot replace a mission"
		else:
			replace_info.text = "Cannot replace missions at this time"
		replace_info.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	replace_info.add_theme_font_size_override("font_size", 11)
	replace_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	replace_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(replace_info)

	main_container.add_child(HSeparator.new())

	# Done button
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	main_container.add_child(button_container)

	var done_btn = Button.new()
	done_btn.name = "DoneButton"
	done_btn.text = "Continue"
	done_btn.custom_minimum_size = Vector2(160, 40)
	done_btn.pressed.connect(_on_done_pressed)
	button_container.add_child(done_btn)

	add_child(main_container)

func _add_mission_card(parent: VBoxContainer, mission: Dictionary, index: int) -> void:
	"""Add a single mission card display with optional replace button."""
	var card_container = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.18, 0.95)
	style.border_color = Color(0.5, 0.4, 0.15)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	card_container.add_theme_stylebox_override("panel", style)
	parent.add_child(card_container)

	var card_vbox = VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 4)
	card_container.add_child(card_vbox)

	# Mission name
	var name_label = Label.new()
	name_label.text = mission.get("name", "Unknown Mission")
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	card_vbox.add_child(name_label)

	# Category
	var cat_label = Label.new()
	cat_label.text = mission.get("category", "")
	cat_label.add_theme_font_size_override("font_size", 11)
	cat_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	card_vbox.add_child(cat_label)

	# Scoring info
	var scoring = mission.get("scoring", {})
	var conditions = scoring.get("conditions", [])
	for condition in conditions:
		var vp = condition.get("vp", 0)
		var check = condition.get("check", "")
		var condition_label = Label.new()
		condition_label.text = "  %d VP - %s" % [vp, _format_condition(check)]
		condition_label.add_theme_font_size_override("font_size", 11)
		condition_label.add_theme_color_override("font_color", Color(0.4, 0.85, 0.4))
		card_vbox.add_child(condition_label)

	# Scoring timing
	var when_text = _get_timing_display(scoring.get("when", ""))
	var timing_label = Label.new()
	timing_label.text = "Scored: %s" % when_text
	timing_label.add_theme_font_size_override("font_size", 10)
	timing_label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9))
	card_vbox.add_child(timing_label)

	# Pending interaction indicator
	if mission.get("pending_interaction", false):
		var pending_label = Label.new()
		pending_label.text = "AWAITING OPPONENT INTERACTION"
		pending_label.add_theme_font_size_override("font_size", 11)
		pending_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
		card_vbox.add_child(pending_label)

	# Replace button
	if _can_replace:
		var replace_btn = Button.new()
		replace_btn.name = "ReplaceButton_%d" % index
		replace_btn.text = "Replace this mission (1 CP)"
		replace_btn.custom_minimum_size = Vector2(0, 30)
		replace_btn.add_theme_font_size_override("font_size", 12)
		replace_btn.tooltip_text = "Spend 1 CP to put this mission back in your deck and draw a different one"
		var mission_id = mission.get("id", "")
		replace_btn.pressed.connect(_on_replace_pressed.bind(mission_id))
		card_vbox.add_child(replace_btn)

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

func _format_condition(check: String) -> String:
	"""Convert condition check ID to human-readable text."""
	return check.replace("_", " ").capitalize()

func _on_replace_pressed(mission_id: String) -> void:
	if _replacement_used:
		print("SecondaryMissionReviewDialog: Replacement already used this draw")
		return
	_replacement_used = true
	print("SecondaryMissionReviewDialog: Player %d wants to replace mission %s" % [_player, mission_id])
	emit_signal("mission_replacement_requested", mission_id)
	hide()
	queue_free()

func _on_done_pressed() -> void:
	print("SecondaryMissionReviewDialog: Player %d accepted drawn missions" % _player)
	emit_signal("review_completed")
	hide()
	queue_free()
