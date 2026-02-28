extends AcceptDialog

# GameOverDialog - Shows game over screen with winner, reason, VP summary,
# and AI post-game performance analysis (T7-57)
# Follows the same pattern as FormationsDeclarationDialog.gd

signal return_to_menu_requested()

var winner_player: int = 0
var game_over_reason: String = ""
var local_player: int = 0

func _init():
	title = "Game Over"
	min_size = DialogConstants.MEDIUM

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

	# T7-57: AI Performance Summary (only when AI players are present)
	if AIPlayer and AIPlayer.enabled:
		var ai_summary = AIPlayer.get_performance_summary()
		if not ai_summary.is_empty():
			main_vbox.add_child(HSeparator.new())
			_build_ai_performance_summary(main_vbox, ai_summary)

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

# =============================================================================
# T7-57: AI Performance Summary
# =============================================================================

func _build_ai_performance_summary(parent: VBoxContainer, ai_summary: Dictionary) -> void:
	var section_title = Label.new()
	section_title.text = "AI Performance Analysis"
	section_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	section_title.add_theme_font_size_override("font_size", 16)
	section_title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3))
	parent.add_child(section_title)

	# Scrollable content for potentially long AI summaries
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 30, 200)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)

	var scroll_vbox = VBoxContainer.new()
	scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(scroll_vbox)

	# Build summary for each AI player
	var sorted_players = ai_summary.keys()
	sorted_players.sort()
	for player in sorted_players:
		var data = ai_summary[player]
		_build_player_ai_card(scroll_vbox, player, data)

	print("GameOverDialog: T7-57 Built AI performance summary for %d player(s)" % ai_summary.size())

func _build_player_ai_card(parent: VBoxContainer, player: int, data: Dictionary) -> void:
	var player_color = Color(0.4, 0.6, 1.0) if player == 1 else Color(1.0, 0.4, 0.4)
	var dim_color = Color(0.65, 0.65, 0.65)

	# Player header
	var header = Label.new()
	var faction = data.get("faction", "Player %d" % player)
	var difficulty = data.get("difficulty", "Normal")
	header.text = "Player %d — %s (AI: %s)" % [player, faction, difficulty]
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", player_color)
	parent.add_child(header)

	# Stats grid
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 2)
	parent.add_child(grid)

	# VP scored
	_add_stat_row(grid, "Total VP:", "%d (Primary: %d, Secondary: %d)" % [
		data.get("vp_total", 0), data.get("vp_primary", 0), data.get("vp_secondary", 0)
	], dim_color)

	# Units killed vs lost
	_add_stat_row(grid, "Units Killed:", str(data.get("units_killed", 0)), dim_color)
	_add_stat_row(grid, "Units Lost:", str(data.get("units_lost", 0)), dim_color)
	_add_stat_row(grid, "Units Remaining:", "%d (%d/%d models)" % [
		data.get("units_remaining", 0),
		data.get("models_remaining", 0),
		data.get("models_starting", 0),
	], dim_color)

	# CP management
	_add_stat_row(grid, "CP Spent:", str(data.get("cp_spent", 0)), dim_color)
	_add_stat_row(grid, "CP Remaining:", str(data.get("cp_remaining", 0)), dim_color)

	# Objectives held per round
	var obj_per_round = data.get("objectives_per_round", {})
	if not obj_per_round.is_empty():
		var obj_text = ""
		var rounds = obj_per_round.keys()
		rounds.sort()
		for r in rounds:
			if obj_text != "":
				obj_text += ", "
			obj_text += "R%s: %d" % [str(r), obj_per_round[r]]
		_add_stat_row(grid, "Objectives Held:", obj_text, dim_color)

	# Key moments
	var key_moments = data.get("key_moments", [])
	if not key_moments.is_empty():
		parent.add_child(HSeparator.new())
		var moments_label = Label.new()
		moments_label.text = "Key Moments:"
		moments_label.add_theme_font_size_override("font_size", 12)
		moments_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.4))
		parent.add_child(moments_label)

		# Show up to 8 key moments to keep it readable
		var max_moments = mini(key_moments.size(), 8)
		for i in range(max_moments):
			var moment = key_moments[i]
			var moment_label = Label.new()
			moment_label.text = "  R%d: %s" % [moment.get("round", 0), moment.get("text", "")]
			moment_label.add_theme_font_size_override("font_size", 11)
			moment_label.add_theme_color_override("font_color", dim_color)
			moment_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			parent.add_child(moment_label)

		if key_moments.size() > max_moments:
			var more_label = Label.new()
			more_label.text = "  ... and %d more" % (key_moments.size() - max_moments)
			more_label.add_theme_font_size_override("font_size", 11)
			more_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			parent.add_child(more_label)

	# Separator between player cards
	parent.add_child(HSeparator.new())

func _add_stat_row(grid: GridContainer, label_text: String, value_text: String, value_color: Color) -> void:
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	grid.add_child(label)

	var value = Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 12)
	value.add_theme_color_override("font_color", value_color)
	grid.add_child(value)

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
