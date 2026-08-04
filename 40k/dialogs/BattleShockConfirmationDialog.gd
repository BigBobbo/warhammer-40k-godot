extends AcceptDialog

# BattleShockConfirmationDialog - P3-94: Confirmation before auto-resolving battle-shock tests
#
# Shows a warning when the player attempts to end the Command phase while there
# are units that haven't taken their battle-shock tests yet. Lists the untested
# units and offers the choice the old dialog never did: ROLL THEM, one unit at a
# time, in front of the player (the Battle-shock roll call), instead of having
# them auto-resolved into the game log where nobody reads them.
#
# Three ways out, in order of prominence:
#   Roll them now ▶      — open the roll call, then end the phase (default)
#   Auto-resolve & end   — the historical behaviour, now an explicit choice
#   Back                 — return to the Command phase

signal end_command_confirmed()
signal end_command_cancelled()
signal roll_tests_requested()

var untested_units: Array = []

func setup(p_untested_units: Array) -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	untested_units = p_untested_units

	title = "End Command Phase?"
	min_size = DialogConstants.SMALL

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(DialogConstants.SMALL.x - 20, 0)

	# Warning header
	var header = Label.new()
	header.text = "WARNING"
	header.add_theme_font_size_override("font_size", 23)
	header.add_theme_color_override("font_color", Color.ORANGE)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	main_container.add_child(HSeparator.new())

	# Warning message
	var warning_label = Label.new()
	warning_label.text = "%d unit(s) have not taken their Battle-shock test.\nRoll them one at a time, or let them auto-resolve into the game log." % untested_units.size()
	warning_label.add_theme_font_size_override("font_size", 18)
	warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(warning_label)

	main_container.add_child(HSeparator.new())

	# Untested units list header
	var units_header = Label.new()
	units_header.text = "Units with untaken Battle-shock tests:"
	units_header.add_theme_font_size_override("font_size", 17)
	units_header.add_theme_color_override("font_color", Color.YELLOW)
	main_container.add_child(units_header)

	# Scrollable unit list
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(DialogConstants.SMALL.x - 20, 100)
	var unit_list = VBoxContainer.new()

	for unit_info in untested_units:
		var unit_label = Label.new()
		unit_label.text = "  P%d - %s (Ld %d)" % [unit_info.player, unit_info.unit_name, unit_info.leadership]
		unit_label.add_theme_font_size_override("font_size", 16)
		var player_color = Color.CORNFLOWER_BLUE if unit_info.player == 1 else Color.INDIAN_RED
		unit_label.add_theme_color_override("font_color", player_color)
		unit_list.add_child(unit_label)

	scroll.add_child(unit_list)
	main_container.add_child(scroll)

	main_container.add_child(HSeparator.new())

	# Buttons — "roll them" is the primary, widest action.
	var roll_container = HBoxContainer.new()
	roll_container.alignment = BoxContainer.ALIGNMENT_CENTER

	var roll_button = Button.new()
	roll_button.name = "RollTestsButton"
	roll_button.text = "▶  Roll them now"
	roll_button.tooltip_text = "Step through each test: the camera moves to the unit and the dice are rolled on screen."
	roll_button.custom_minimum_size = Vector2(320, 42)
	WhiteDwarfTheme.apply_primary_button(roll_button)
	roll_button.add_theme_font_size_override("font_size", 18)
	roll_button.pressed.connect(_on_roll_pressed)
	roll_container.add_child(roll_button)
	main_container.add_child(roll_container)

	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER

	var cancel_button = Button.new()
	cancel_button.name = "CancelButton"
	cancel_button.text = "Back"
	cancel_button.custom_minimum_size = Vector2(150, 40)
	cancel_button.pressed.connect(_on_cancel_pressed)
	button_container.add_child(cancel_button)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	button_container.add_child(spacer)

	var confirm_button = Button.new()
	confirm_button.name = "AutoResolveEndButton"
	confirm_button.text = "Auto-resolve & end"
	confirm_button.tooltip_text = "Resolve every outstanding test at once. Results go to the game log only."
	confirm_button.custom_minimum_size = Vector2(150, 40)
	confirm_button.add_theme_color_override("font_color", Color.ORANGE)
	confirm_button.pressed.connect(_on_confirm_pressed)
	button_container.add_child(confirm_button)

	main_container.add_child(button_container)

	add_child(main_container)

func _on_roll_pressed() -> void:
	print("BattleShockConfirmationDialog: Player chose to roll %d battle-shock test(s) on screen" % untested_units.size())
	emit_signal("roll_tests_requested")
	hide()
	queue_free()

func _on_confirm_pressed() -> void:
	print("BattleShockConfirmationDialog: Player confirmed ending command phase with %d untested units" % untested_units.size())
	emit_signal("end_command_confirmed")
	hide()
	queue_free()

func _on_cancel_pressed() -> void:
	print("BattleShockConfirmationDialog: Player cancelled ending command phase")
	emit_signal("end_command_cancelled")
	hide()
	queue_free()
