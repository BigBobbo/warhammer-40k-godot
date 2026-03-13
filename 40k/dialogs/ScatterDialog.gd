extends AcceptDialog

# ScatterDialog - UI for Scatter! ability (OA-42 — Grot Tanks)
#
# SCATTER! (Grot Tanks Datasheet Ability)
# Once per turn, when an enemy unit ends a Normal, Advance or Fall Back move
# within 9" of this unit, if this unit is not within Engagement Range of one
# or more enemy units, it can make a Normal move of up to 6".
#
# Shows eligible units with "Scatter! (6\" move)" buttons and a "Decline" button.

signal scatter_used(unit_id: String, player: int)
signal scatter_declined(player: int)

var player: int = 0
var eligible_units: Array = []  # Array of { unit_id: String, unit_name: String }
var trigger_unit_id: String = ""

func setup(p_player: int, p_eligible_units: Array, p_trigger_unit_id: String) -> void:
	player = p_player
	eligible_units = p_eligible_units
	trigger_unit_id = p_trigger_unit_id

	title = "Scatter! Available - Player %d" % player

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	min_size = DialogConstants.MEDIUM
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	# Header
	var header = Label.new()
	header.text = "SCATTER!"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.YELLOW_GREEN)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	# Subheader
	var subheader = Label.new()
	subheader.text = "Grot Tanks - Datasheet Ability"
	subheader.add_theme_font_size_override("font_size", 12)
	subheader.add_theme_color_override("font_color", Color.GRAY)
	subheader.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(subheader)

	main_container.add_child(HSeparator.new())

	# Effect description
	var trigger_name = ""
	var trigger_unit = GameState.get_unit(trigger_unit_id)
	if not trigger_unit.is_empty():
		trigger_name = trigger_unit.get("meta", {}).get("name", trigger_unit_id)
	else:
		trigger_name = trigger_unit_id

	var effect_label = Label.new()
	effect_label.text = "Enemy unit %s just ended a move within 9\". Select one of your units to make a Normal move of up to 6\" (no CP cost)." % trigger_name
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect_label.add_theme_font_size_override("font_size", 13)
	main_container.add_child(effect_label)

	main_container.add_child(HSeparator.new())

	# Eligible units section
	var units_label = Label.new()
	units_label.text = "Select a unit to scatter:"
	units_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(units_label)

	# Scrollable container for eligible units
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 120)
	var unit_list = VBoxContainer.new()

	for unit_info in eligible_units:
		var unit_container = HBoxContainer.new()

		var name_label = Label.new()
		name_label.text = unit_info.unit_name
		name_label.add_theme_font_size_override("font_size", 13)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		unit_container.add_child(name_label)

		var use_button = Button.new()
		use_button.text = "Scatter! (6\" move)"
		use_button.custom_minimum_size = Vector2(170, 30)
		use_button.pressed.connect(_on_use_pressed.bind(unit_info.unit_id))
		unit_container.add_child(use_button)

		unit_list.add_child(unit_container)

	scroll.add_child(unit_list)
	main_container.add_child(scroll)

	main_container.add_child(HSeparator.new())

	# Decline button
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER

	var decline_button = Button.new()
	decline_button.text = "Decline"
	decline_button.custom_minimum_size = Vector2(200, 40)
	decline_button.pressed.connect(_on_decline_pressed)
	button_container.add_child(decline_button)

	main_container.add_child(button_container)

	add_child(main_container)

func _on_use_pressed(unit_id: String) -> void:
	var unit_name = ""
	for unit_info in eligible_units:
		if unit_info.unit_id == unit_id:
			unit_name = unit_info.unit_name
			break
	print("ScatterDialog: Player %d uses SCATTER! with %s (%s)" % [player, unit_name, unit_id])
	emit_signal("scatter_used", unit_id, player)
	hide()
	queue_free()

func _on_decline_pressed() -> void:
	print("ScatterDialog: Player %d declines SCATTER!" % player)
	emit_signal("scatter_declined", player)
	hide()
	queue_free()
