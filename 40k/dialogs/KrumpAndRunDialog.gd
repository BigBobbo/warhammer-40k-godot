extends AcceptDialog

# KrumpAndRunDialog - UI for Krump and Run stratagem (OA-8)
#
# KRUMP AND RUN (Freebooter Krew – Strategic Ploy Stratagem, 1 CP)
# WHEN: Your opponent's Movement phase, just after an enemy unit falls back.
# TARGET: One ORKS unit from your army that was within engagement range of that
#         enemy unit at the start of the phase and is not within engagement range
#         of one or more enemy units.
# EFFECT: Your unit can make a Normal move of up to 6".
#
# Shows eligible ORKS units with "Use (1 CP)" buttons and a "Decline" button.

signal krump_and_run_used(unit_id: String, player: int)
signal krump_and_run_declined(player: int)

var player: int = 0
var eligible_units: Array = []  # Array of { unit_id: String, unit_name: String }
var fell_back_unit_id: String = ""

func setup(p_player: int, p_eligible_units: Array, p_fell_back_unit_id: String) -> void:
	player = p_player
	eligible_units = p_eligible_units
	fell_back_unit_id = p_fell_back_unit_id

	title = "Krump and Run Available - Player %d" % player

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	min_size = DialogConstants.MEDIUM
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	# Header
	var header = Label.new()
	header.text = "KRUMP AND RUN"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.ORANGE_RED)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	# Subheader
	var subheader = Label.new()
	subheader.text = "Freebooter Krew - Strategic Ploy Stratagem"
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

	# Effect description
	var fell_back_name = ""
	var fell_back_unit = GameState.get_unit(fell_back_unit_id)
	if not fell_back_unit.is_empty():
		fell_back_name = fell_back_unit.get("meta", {}).get("name", fell_back_unit_id)
	else:
		fell_back_name = fell_back_unit_id

	var effect_label = Label.new()
	effect_label.text = "Enemy unit %s just fell back. Select one of your freed ORKS units to make a Normal move of up to 6\"." % fell_back_name
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect_label.add_theme_font_size_override("font_size", 13)
	main_container.add_child(effect_label)

	main_container.add_child(HSeparator.new())

	# Eligible units section
	var units_label = Label.new()
	units_label.text = "Select an ORKS unit to move:"
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
		use_button.text = "Move 6\" (1 CP)"
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
	print("KrumpAndRunDialog: Player %d uses KRUMP AND RUN with %s (%s)" % [player, unit_name, unit_id])
	emit_signal("krump_and_run_used", unit_id, player)
	hide()
	queue_free()

func _on_decline_pressed() -> void:
	print("KrumpAndRunDialog: Player %d declines KRUMP AND RUN" % player)
	emit_signal("krump_and_run_declined", player)
	hide()
	queue_free()
