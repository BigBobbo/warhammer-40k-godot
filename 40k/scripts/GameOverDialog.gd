extends AcceptDialog

# GameOverDialog - Shows game over screen with winner, reason, and VP summary
# Follows the same pattern as FormationsDeclarationDialog.gd

signal return_to_menu_requested()

var winner_player: int = 0
var game_over_reason: String = ""
var local_player: int = 0

func _init():
	title = "Game Over"
	min_size = Vector2(500, 350)

func setup(winner: int, reason: String, local_player_num: int = 0) -> void:
	winner_player = winner
	game_over_reason = reason
	local_player = local_player_num

	ok_button_text = "Return to Menu"

	# Connect signals
	confirmed.connect(_on_confirmed)

	# Build the UI
	_build_ui()

func _build_ui() -> void:
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	add_child(main_vbox)

	# Winner banner
	var winner_label = Label.new()
	winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	winner_label.add_theme_font_size_override("font_size", 24)

	if local_player > 0:
		# Networked game — show win/loss relative to local player
		if winner_player == local_player:
			winner_label.text = "VICTORY!"
			winner_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
		else:
			winner_label.text = "DEFEAT"
			winner_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	elif winner_player > 0:
		winner_label.text = "Player %d Wins!" % winner_player
		winner_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	else:
		winner_label.text = "Game Over — Draw!"
		winner_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	main_vbox.add_child(winner_label)

	# Reason
	var reason_label = Label.new()
	reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason_label.add_theme_font_size_override("font_size", 14)
	reason_label.text = _get_reason_text()
	reason_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	main_vbox.add_child(reason_label)

	main_vbox.add_child(HSeparator.new())

	# VP Summary
	_build_vp_summary(main_vbox)

func _build_vp_summary(parent: VBoxContainer) -> void:
	var vp_title = Label.new()
	vp_title.text = "Victory Points"
	vp_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vp_title.add_theme_font_size_override("font_size", 16)
	parent.add_child(vp_title)

	if not MissionManager:
		return

	var vp_summary = MissionManager.get_vp_summary()

	# Player 1 VP
	var p1_label = Label.new()
	p1_label.text = "Player 1: %d VP (Primary: %d, Secondary: %d)" % [
		vp_summary["player1"]["total"],
		vp_summary["player1"]["primary"],
		vp_summary["player1"]["secondary"],
	]
	p1_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p1_label.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
	parent.add_child(p1_label)

	# Player 2 VP
	var p2_label = Label.new()
	p2_label.text = "Player 2: %d VP (Primary: %d, Secondary: %d)" % [
		vp_summary["player2"]["total"],
		vp_summary["player2"]["primary"],
		vp_summary["player2"]["secondary"],
	]
	p2_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p2_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	parent.add_child(p2_label)

	# Battle rounds
	parent.add_child(HSeparator.new())
	var rounds_label = Label.new()
	var battle_round = GameState.get_battle_round()
	# If game completed normally the round counter will be > 5
	var display_round = mini(battle_round, 5)
	rounds_label.text = "Battle Rounds Completed: %d / 5" % display_round
	rounds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rounds_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	parent.add_child(rounds_label)

func _get_reason_text() -> String:
	match game_over_reason:
		"turn_timeout":
			return "Player %d ran out of time" % (3 - winner_player)
		"disconnect":
			return "Opponent disconnected"
		"surrender":
			return "Player %d surrendered" % (3 - winner_player)
		"rounds_complete":
			return "All 5 battle rounds completed"
		_:
			return game_over_reason if game_over_reason != "" else "Game concluded"

func _on_confirmed() -> void:
	print("GameOverDialog: Return to menu requested")
	return_to_menu_requested.emit()
	queue_free()
