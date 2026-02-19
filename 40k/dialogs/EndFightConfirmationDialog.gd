extends AcceptDialog

# EndFightConfirmationDialog - T5-UX7: Confirmation before ending the Fight phase
#
# Shows a warning when the player attempts to end the Fight phase while there
# are eligible units that haven't fought yet. Lists the unfought units and
# asks for confirmation.

signal end_fight_confirmed()
signal end_fight_cancelled()

var unfought_units: Array = []

func setup(p_unfought_units: Array) -> void:
	unfought_units = p_unfought_units

	title = "End Fight Phase?"

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(500, 250)

	# Warning header
	var header = Label.new()
	header.text = "WARNING"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.ORANGE)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	main_container.add_child(HSeparator.new())

	# Warning message
	var warning_label = Label.new()
	warning_label.text = "%d unit(s) have not yet fought. Are you sure you want to end the Fight Phase?" % unfought_units.size()
	warning_label.add_theme_font_size_override("font_size", 14)
	warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(warning_label)

	main_container.add_child(HSeparator.new())

	# Unfought units list (scrollable)
	var units_header = Label.new()
	units_header.text = "Units that haven't fought:"
	units_header.add_theme_font_size_override("font_size", 13)
	units_header.add_theme_color_override("font_color", Color.YELLOW)
	main_container.add_child(units_header)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 100)
	var unit_list = VBoxContainer.new()

	for unit_info in unfought_units:
		var unit_label = Label.new()
		unit_label.text = "  P%d - %s (%s)" % [unit_info.player, unit_info.unit_name, unit_info.subphase]
		unit_label.add_theme_font_size_override("font_size", 12)
		var player_color = Color.CORNFLOWER_BLUE if unit_info.player == 1 else Color.INDIAN_RED
		unit_label.add_theme_color_override("font_color", player_color)
		unit_list.add_child(unit_label)

	scroll.add_child(unit_list)
	main_container.add_child(scroll)

	main_container.add_child(HSeparator.new())

	# Buttons
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER

	var cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(150, 40)
	cancel_button.pressed.connect(_on_cancel_pressed)
	button_container.add_child(cancel_button)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	button_container.add_child(spacer)

	var confirm_button = Button.new()
	confirm_button.text = "End Fight Phase"
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
