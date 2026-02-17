extends AcceptDialog

# HeroicInterventionDialog - UI for Heroic Intervention stratagem during opponent's charge
#
# HEROIC INTERVENTION (Core – Strategic Ploy Stratagem, 1 CP)
# WHEN: Your opponent's Charge phase, just after an enemy unit ends a Charge move.
# TARGET: One unit from your army that is within 6" of that enemy unit and that
#         would be eligible to declare a charge (excluding VEHICLE units unless WALKER).
# EFFECT: Your unit can declare a charge that targets only that enemy unit, then
#         make a Charge move.
# RESTRICTION: Once per phase. No charge bonus (+1 to hit).
#
# Shows eligible units with "Use" buttons and a "Decline" button.

signal heroic_intervention_used(unit_id: String, player: int)
signal heroic_intervention_declined(player: int)

var player: int = 0
var charging_unit_id: String = ""  # The enemy unit that just charged
var eligible_units: Array = []  # Array of { unit_id: String, unit_name: String }

func setup(p_player: int, p_charging_unit_id: String, p_eligible_units: Array) -> void:
	player = p_player
	charging_unit_id = p_charging_unit_id
	eligible_units = p_eligible_units

	title = "Heroic Intervention Available - Player %d" % player

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(520, 320)

	# Header
	var header = Label.new()
	header.text = "HEROIC INTERVENTION"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.GOLD)
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
	cp_label.text = "Cost: 1 CP (You have %d CP)" % current_cp
	cp_label.add_theme_font_size_override("font_size", 14)
	cp_label.add_theme_color_override("font_color", Color.CYAN)
	cp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(cp_label)

	main_container.add_child(HSeparator.new())

	# Charging unit info
	var charging_unit = GameState.get_unit(charging_unit_id)
	var charging_name = charging_unit.get("meta", {}).get("name", charging_unit_id)
	var target_label = Label.new()
	target_label.text = "Enemy unit that charged: %s" % charging_name
	target_label.add_theme_font_size_override("font_size", 14)
	target_label.add_theme_color_override("font_color", Color.RED)
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(target_label)

	# Effect description
	var effect_label = Label.new()
	effect_label.text = "Select one of your units to counter-charge the enemy. Your unit will roll 2D6 for charge distance and attempt to reach engagement range. Note: No charge bonus (+1 to hit) is granted."
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect_label.add_theme_font_size_override("font_size", 13)
	main_container.add_child(effect_label)

	main_container.add_child(HSeparator.new())

	# Eligible units section
	var units_label = Label.new()
	units_label.text = "Select a unit to counter-charge:"
	units_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(units_label)

	# Scrollable container for eligible units
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 120)
	var unit_list = VBoxContainer.new()

	for unit_info in eligible_units:
		var unit_container = HBoxContainer.new()

		var name_label = Label.new()
		name_label.text = unit_info.unit_name
		name_label.add_theme_font_size_override("font_size", 13)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		unit_container.add_child(name_label)

		var use_button = Button.new()
		use_button.text = "Counter-Charge (1 CP)"
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
	print("HeroicInterventionDialog: Player %d uses HEROIC INTERVENTION with %s (%s)" % [player, unit_name, unit_id])
	emit_signal("heroic_intervention_used", unit_id, player)
	hide()
	queue_free()

func _on_decline_pressed() -> void:
	print("HeroicInterventionDialog: Player %d declines HEROIC INTERVENTION" % player)
	emit_signal("heroic_intervention_declined", player)
	hide()
	queue_free()
