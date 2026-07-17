extends AcceptDialog
class_name FightSelectionDialog

signal fighter_selected(unit_id: String)

var phase_reference = null
var dialog_data: Dictionary = {}
var selected_unit_id: String = ""

func setup(data: Dictionary, phase) -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	dialog_data = data
	phase_reference = phase

	title = "Select Unit to Fight - Player %d" % data.selecting_player

	_build_ui()

func _build_ui() -> void:
	min_size = DialogConstants.MEDIUM
	# Main container (stable name so windowed scenarios can address buttons)
	var main_container = VBoxContainer.new()
	main_container.name = "Content"
	main_container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	# NEW: Player turn indicator with color
	var turn_indicator = Panel.new()
	turn_indicator.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 40)
	var player_color = Color.BLUE if dialog_data.selecting_player == 1 else Color.RED
	turn_indicator.add_theme_stylebox_override("panel", _create_colored_panel(player_color))

	var turn_label = Label.new()
	turn_label.text = "PLAYER %d'S TURN TO SELECT" % dialog_data.selecting_player
	turn_label.add_theme_font_size_override("font_size", 20)
	turn_label.add_theme_color_override("font_color", Color.WHITE)
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_indicator.add_child(turn_label)
	main_container.add_child(turn_indicator)

	main_container.add_child(HSeparator.new())

	# Current subphase header
	var subphase_label = Label.new()
	subphase_label.text = "Current: %s Subphase" % dialog_data.current_subphase
	subphase_label.add_theme_font_size_override("font_size", 18)
	main_container.add_child(subphase_label)

	main_container.add_child(HSeparator.new())

	# Scroll container for unit list
	var scroll = ScrollContainer.new()
	scroll.name = "UnitScroll"
	scroll.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 300)

	var units_container = VBoxContainer.new()
	units_container.name = "UnitList"

	# Show all units organized by subphase
	_add_subphase_units(units_container, "FIGHTS_FIRST", dialog_data.fights_first_units)
	_add_subphase_units(units_container, "REMAINING_COMBATS", dialog_data.remaining_units)
	if dialog_data.has("fights_last_units"):
		_add_subphase_units(units_container, "FIGHTS_LAST", dialog_data.fights_last_units)

	scroll.add_child(units_container)
	main_container.add_child(scroll)

	# Instructions with alternation explanation
	var instructions = Label.new()
	var other_player = 2 if dialog_data.selecting_player == 1 else 1

	# Check if other player has units remaining
	var other_player_key = str(other_player)
	var current_source = dialog_data.fights_first_units
	if dialog_data.current_subphase == "REMAINING_COMBATS":
		current_source = dialog_data.remaining_units
	elif dialog_data.current_subphase == "FIGHTS_LAST" and dialog_data.has("fights_last_units"):
		current_source = dialog_data.fights_last_units
	var other_player_has_units = false
	for unit_id in current_source.get(other_player_key, []):
		if unit_id not in dialog_data.units_that_fought:
			other_player_has_units = true
			break

	if other_player_has_units:
		instructions.text = "Select a unit to activate. After this unit fights, Player %d will select." % other_player
	else:
		instructions.text = "Player %d has no eligible units. Select all remaining units in turn." % other_player

	instructions.add_theme_color_override("font_color", Color.YELLOW)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_container.add_child(instructions)

	add_child(main_container)

	# Hide the built-in OK button: picking a unit is a single click on its
	# button, so OK had nothing to confirm — clicking it just dismissed the
	# picker with no unit selected and stalled the fight sequence.
	get_ok_button().visible = false
	confirmed.connect(_on_confirmed)

func _add_subphase_units(container: VBoxContainer, subphase_name: String, units_by_player: Dictionary) -> void:
	var subphase_header = Label.new()
	subphase_header.text = "=== %s ===" % subphase_name
	subphase_header.add_theme_font_size_override("font_size", 16)

	# Highlight if this is current subphase
	var is_current = subphase_name == dialog_data.current_subphase
	if is_current:
		subphase_header.add_theme_color_override("font_color", Color.GREEN)
	else:
		subphase_header.add_theme_color_override("font_color", Color.GRAY)

	container.add_child(subphase_header)

	# Add units for each player
	for player in ["1", "2"]:
		var player_units = units_by_player.get(player, [])
		if player_units.is_empty():
			continue

		var player_label = Label.new()
		player_label.text = "  Player %s:" % player
		container.add_child(player_label)

		for unit_id in player_units:
			var has_fought = unit_id in dialog_data.units_that_fought
			var is_eligible = dialog_data.eligible_units.has(unit_id)

			var unit_button = Button.new()
			unit_button.name = "Fight_%s" % unit_id
			# Resolve through GameState's display-name helper (Alpha/Beta
			# suffixes) so same-named squads are tellable apart, matching the
			# labels used everywhere else. eligible_units only carries the
			# SELECTING player's units, so its name lookup left every other
			# unit rendering as a raw unit id. setup() runs before this dialog
			# enters the tree — resolve the autoload via the main loop.
			var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
			var unit_name = gs.get_unit_display_name(unit_id) if gs != null \
				else dialog_data.eligible_units.get(unit_id, {}).get("name", unit_id)

			unit_button.text = "    %s%s" % [
				unit_name,
				" (Fought)" if has_fought else ""
			]

			# Multiplayer: this dialog is shown on BOTH peers for visibility,
			# but only the selecting player may pick. Without this gate the
			# other player saw enabled buttons whose clicks were then rejected
			# by the host ("Player ID mismatch") — confusing dead UI.
			var is_local_players_pick = true
			# NOTE: setup() runs before this dialog enters the tree, so
			# get_node_or_null("/root/...") would return null — resolve the
			# autoload through the main loop instead.
			var nm = Engine.get_main_loop().root.get_node_or_null("NetworkManager")
			if nm and nm.is_networked():
				is_local_players_pick = (nm.get_local_player() == int(dialog_data.selecting_player))

			# Style based on state
			if has_fought:
				unit_button.disabled = true
				unit_button.modulate = Color.GRAY
			elif not is_eligible:
				unit_button.disabled = true
			elif not is_local_players_pick:
				unit_button.disabled = true
				unit_button.tooltip_text = "Player %d is selecting" % int(dialog_data.selecting_player)
			elif is_current:
				unit_button.modulate = Color.LIGHT_GREEN

			if is_eligible and not has_fought and is_local_players_pick:
				unit_button.pressed.connect(_on_unit_selected.bind(unit_id))

			container.add_child(unit_button)

	container.add_child(HSeparator.new())

func _on_unit_selected(unit_id: String) -> void:
	selected_unit_id = unit_id
	print("DEBUG: FightSelectionDialog - Unit selected: ", unit_id)

	# Immediately emit and close (single-click operation)
	hide()
	emit_signal("fighter_selected", selected_unit_id)
	print("DEBUG: FightSelectionDialog - Emitted fighter_selected signal for: ", unit_id)
	# Delay queue_free slightly to allow signal to process
	await get_tree().create_timer(0.1).timeout
	queue_free()

func _on_confirmed() -> void:
	# Only reachable via a programmatic `confirmed` emission now that the
	# built-in OK button is hidden (unit buttons select-and-close directly)
	if selected_unit_id.is_empty():
		push_warning("No unit selected - please click on a unit")
		if not visible:
			# `confirmed` auto-hides the dialog before this validation runs —
			# re-show so the selecting player isn't left without a picker.
			show()
		return

	# Close dialog first to avoid exclusive child window error
	hide()
	emit_signal("fighter_selected", selected_unit_id)
	print("DEBUG: FightSelectionDialog - Emitted fighter_selected via confirm for: ", selected_unit_id)
	# Delay queue_free slightly to allow signal to process
	await get_tree().create_timer(0.1).timeout
	queue_free()

# Helper function to create colored panel for turn indicator
func _create_colored_panel(color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = color.lightened(0.2)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	return style
