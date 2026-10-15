extends AcceptDialog

# EndFightConfirmationDialog - confirmation for the p.74 PASS ("Eligible to
# fight, but unable to fight").
#
# Fighting is mandatory (12.04): the Fight step cannot be ended while units are
# still eligible. The one exception is a pass — when ALL of the selecting
# player's eligible units are more than 5" from every enemy unit they may pass
# the selection back to their opponent. This dialog lists those units and asks
# the player to confirm the pass. (Node/button names kept for scenarios.)

signal end_fight_confirmed()
signal end_fight_cancelled()

var unfought_units: Array = []

func setup(p_unfought_units: Array) -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	unfought_units = p_unfought_units

	title = "Pass?"
	min_size = DialogConstants.SMALL

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.name = "Content"
	main_container.custom_minimum_size = Vector2(DialogConstants.SMALL.x - 20, 0)

	# Warning header
	var header = Label.new()
	header.text = "UNABLE TO FIGHT"
	header.add_theme_font_size_override("font_size", 23)
	header.add_theme_color_override("font_color", Color.ORANGE)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	main_container.add_child(HSeparator.new())

	# Warning message
	var warning_label = Label.new()
	warning_label.text = "%d unit(s) are eligible to fight but more than 5\" from every enemy unit. Pass the selection to your opponent? If both players pass, or your opponent has no units left to fight, the Fight step ends and these units do not fight." % unfought_units.size()
	warning_label.add_theme_font_size_override("font_size", 18)
	warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(warning_label)

	main_container.add_child(HSeparator.new())

	# Unfought units list (scrollable)
	var units_header = Label.new()
	units_header.text = "Units unable to fight:"
	units_header.add_theme_font_size_override("font_size", 17)
	units_header.add_theme_color_override("font_color", Color.YELLOW)
	main_container.add_child(units_header)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(DialogConstants.SMALL.x - 20, 100)
	var unit_list = VBoxContainer.new()

	for unit_info in unfought_units:
		var unit_label = Label.new()
		unit_label.text = "  P%d - %s (%s)" % [unit_info.player, unit_info.unit_name, unit_info.subphase]
		unit_label.add_theme_font_size_override("font_size", 16)
		var player_color = Color.CORNFLOWER_BLUE if unit_info.player == 1 else Color.INDIAN_RED
		unit_label.add_theme_color_override("font_color", player_color)
		unit_list.add_child(unit_label)

	scroll.add_child(unit_list)
	main_container.add_child(scroll)

	main_container.add_child(HSeparator.new())

	# Buttons
	var button_container = HBoxContainer.new()
	button_container.name = "Actions"
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER

	var cancel_button = Button.new()
	cancel_button.name = "CancelEndFight"
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(150, 40)
	cancel_button.pressed.connect(_on_cancel_pressed)
	button_container.add_child(cancel_button)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	button_container.add_child(spacer)

	var confirm_button = Button.new()
	confirm_button.name = "ConfirmEndFight"
	confirm_button.text = "Pass"
	confirm_button.custom_minimum_size = Vector2(150, 40)
	confirm_button.add_theme_color_override("font_color", Color.ORANGE)
	confirm_button.pressed.connect(_on_confirm_pressed)
	button_container.add_child(confirm_button)

	main_container.add_child(button_container)

	add_child(main_container)

func _on_confirm_pressed() -> void:
	print("EndFightConfirmationDialog: Player confirmed ending fight phase with %d unfought units" % unfought_units.size())
	emit_signal("end_fight_confirmed")
	hide()
	queue_free()

func _on_cancel_pressed() -> void:
	print("EndFightConfirmationDialog: Player cancelled ending fight phase")
	emit_signal("end_fight_cancelled")
	hide()
	queue_free()
