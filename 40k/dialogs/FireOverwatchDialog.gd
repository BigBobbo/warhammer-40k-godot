extends AcceptDialog

# FireOverwatchDialog - UI for Fire Overwatch stratagem during opponent's movement/charge
#
# FIRE OVERWATCH (Core – Strategic Ploy Stratagem, 1 CP)
# WHEN: Your opponent's Movement or Charge phase, just after an enemy unit is set up
#       or when an enemy unit starts or ends a Normal, Advance, or Fall Back move.
# TARGET: One unit from your army that is within 24" of that enemy unit and that
#         would be eligible to shoot.
# EFFECT: Your unit can shoot that enemy unit as if it were your Shooting phase,
#         but its attacks can only hit on unmodified Hit rolls of 6.
# RESTRICTION: Once per turn.
#
# Shows eligible units with "Use" buttons and a "Decline" button.

signal fire_overwatch_used(shooter_unit_id: String, player: int)
signal fire_overwatch_declined(player: int)

var player: int = 0
var target_unit_id: String = ""  # The enemy unit that just moved/charged
var eligible_units: Array = []  # Array of { unit_id: String, unit_name: String }

func setup(p_player: int, p_target_unit_id: String, p_eligible_units: Array) -> void:
	player = p_player
	target_unit_id = p_target_unit_id
	eligible_units = p_eligible_units

	title = "Fire Overwatch Available - Player %d" % player

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(520, 320)

	# Header
	var header = Label.new()
	header.text = "FIRE OVERWATCH"
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
	cp_label.text = "Cost: 1 CP (You have %d CP)" % current_cp
	cp_label.add_theme_font_size_override("font_size", 14)
	cp_label.add_theme_color_override("font_color", Color.CYAN)
	cp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(cp_label)

	main_container.add_child(HSeparator.new())

	# Target info
	var target_unit = GameState.get_unit(target_unit_id)
	var target_name = target_unit.get("meta", {}).get("name", target_unit_id)
	var target_label = Label.new()
	target_label.text = "Enemy unit: %s" % target_name
	target_label.add_theme_font_size_override("font_size", 14)
	target_label.add_theme_color_override("font_color", Color.RED)
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(target_label)

	# Effect description
	var effect_label = Label.new()
	effect_label.text = "Select one of your units to shoot at the enemy. Only unmodified hit rolls of 6 will hit. This uses your unit's normal ranged weapons."
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect_label.add_theme_font_size_override("font_size", 13)
	main_container.add_child(effect_label)

	main_container.add_child(HSeparator.new())

	# Eligible units section
	var units_label = Label.new()
	units_label.text = "Select a unit to fire overwatch:"
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
		use_button.text = "Fire Overwatch (1 CP)"
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

func _on_use_pressed(shooter_unit_id: String) -> void:
	var unit_name = ""
	for unit_info in eligible_units:
		if unit_info.unit_id == shooter_unit_id:
			unit_name = unit_info.unit_name
			break
	print("FireOverwatchDialog: Player %d uses FIRE OVERWATCH with %s (%s)" % [player, unit_name, shooter_unit_id])
	emit_signal("fire_overwatch_used", shooter_unit_id, player)
	hide()
	queue_free()

func _on_decline_pressed() -> void:
	print("FireOverwatchDialog: Player %d declines FIRE OVERWATCH" % player)
	emit_signal("fire_overwatch_declined", player)
	hide()
	queue_free()
