extends AcceptDialog

# CounterOffensiveDialog - UI for Counter-Offensive stratagem during Fight phase
#
# COUNTER-OFFENSIVE (Core – Strategic Ploy Stratagem, 2 CP)
# WHEN: Fight phase, just after an enemy unit has fought.
# TARGET: One unit from your army that is within Engagement Range of one or more
#         enemy units and that has not already been selected to fight this phase.
# EFFECT: Your unit fights next.
# RESTRICTION: Once per phase.
#
# Shows eligible units with "Use" buttons and a "Decline" button.

signal counter_offensive_used(unit_id: String, player: int)
signal counter_offensive_declined(player: int)

var player: int = 0
var eligible_units: Array = []  # Array of { unit_id: String, unit_name: String }

func setup(p_player: int, p_eligible_units: Array) -> void:
	player = p_player
	eligible_units = p_eligible_units

	title = "Counter-Offensive Available - Player %d" % player

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(500, 300)

	# Header
	var header = Label.new()
	header.text = "COUNTER-OFFENSIVE"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.ORANGE_RED)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	# Subheader
	var subheader = Label.new()
	subheader.text = "Core - Strategic Ploy Stratagem"
	subheader.add_theme_font_size_override("font_size", 12)
	subheader.add_theme_color_override("font_color", Color.GRAY)
	subheader.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(subheader)

	main_container.add_child(HSeparator.new())

	# CP info
	var cp_label = Label.new()
	var current_cp = StratagemManager.get_player_cp(player)
	cp_label.text = "Cost: 2 CP (You have %d CP)" % current_cp
	cp_label.add_theme_font_size_override("font_size", 14)
	cp_label.add_theme_color_override("font_color", Color.CYAN)
	cp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(cp_label)

	main_container.add_child(HSeparator.new())

	# Effect description
	var effect_label = Label.new()
	effect_label.text = "An enemy unit has just fought. You may select one of your eligible units to fight next, overriding the normal alternation."
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect_label.add_theme_font_size_override("font_size", 13)
	main_container.add_child(effect_label)

	main_container.add_child(HSeparator.new())

	# Eligible units section
	var units_label = Label.new()
	units_label.text = "Select a unit to fight next:"
	units_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(units_label)

	# Scrollable container for eligible units
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 120)
	var unit_list = VBoxContainer.new()

	for unit_info in eligible_units:
		var unit_container = HBoxContainer.new()

		var name_label = Label.new()
		name_label.text = unit_info.unit_name
		name_label.add_theme_font_size_override("font_size", 13)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		unit_container.add_child(name_label)

		var use_button = Button.new()
		use_button.text = "Fight Next (2 CP)"
		use_button.custom_minimum_size = Vector2(150, 30)
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
	print("CounterOffensiveDialog: Player %d uses COUNTER-OFFENSIVE on %s (%s)" % [player, unit_name, unit_id])
	emit_signal("counter_offensive_used", unit_id, player)
	hide()
	queue_free()

func _on_decline_pressed() -> void:
	print("CounterOffensiveDialog: Player %d declines COUNTER-OFFENSIVE" % player)
	emit_signal("counter_offensive_declined", player)
	hide()
	queue_free()
