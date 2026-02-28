extends AcceptDialog
class_name TankShockDialog

# TankShockDialog - UI for the TANK SHOCK stratagem
#
# TANK SHOCK (Core – Strategic Ploy Stratagem, 1 CP)
# WHEN: Your Charge phase, just after a VEHICLE unit ends a Charge move.
# TARGET: That VEHICLE unit.
# EFFECT: Select one enemy unit within Engagement Range. Roll a number of D6
#         equal to the Toughness characteristic of that VEHICLE model (max 6).
#         For each 5+, that enemy unit suffers 1 mortal wound.
# RESTRICTION: Once per phase.
#
# Single-step selection: pick which enemy unit in Engagement Range to ram.

signal tank_shock_used(target_unit_id: String, player: int)
signal tank_shock_declined(player: int)

var player: int = 0
var vehicle_unit_id: String = ""
var eligible_targets: Array = []  # Array of { unit_id, unit_name, model_count }

func setup(p_player: int, p_vehicle_unit_id: String, p_eligible_targets: Array) -> void:
	player = p_player
	vehicle_unit_id = p_vehicle_unit_id
	eligible_targets = p_eligible_targets

	title = "Tank Shock Available - Player %d" % player

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	min_size = DialogConstants.MEDIUM
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	# Header
	var header = Label.new()
	header.text = "TANK SHOCK"
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

	# Vehicle info
	var vehicle_unit = GameState.get_unit(vehicle_unit_id)
	var vehicle_name = vehicle_unit.get("meta", {}).get("name", vehicle_unit_id)
	var toughness = int(vehicle_unit.get("meta", {}).get("toughness", 4))
	var dice_count = mini(toughness, 6)

	var vehicle_label = Label.new()
	vehicle_label.text = "Vehicle: %s (Toughness %d)" % [vehicle_name, toughness]
	vehicle_label.add_theme_font_size_override("font_size", 14)
	vehicle_label.add_theme_color_override("font_color", Color.LIGHT_GREEN)
	vehicle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(vehicle_label)

	# Effect description
	var effect_label = Label.new()
	effect_label.text = "Select an enemy unit within Engagement Range. Roll %dD6 (Toughness %d, max 6): each 5+ = 1 mortal wound." % [dice_count, toughness]
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect_label.add_theme_font_size_override("font_size", 13)
	main_container.add_child(effect_label)

	main_container.add_child(HSeparator.new())

	# Target selection section
	var targets_label = Label.new()
	targets_label.text = "Select an enemy unit to ram:"
	targets_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(targets_label)

	# Scrollable container for eligible targets
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 120)
	var target_list = VBoxContainer.new()

	for target_data in eligible_targets:
		var target_container = HBoxContainer.new()

		var name_label = Label.new()
		name_label.text = "%s (%d models)" % [target_data.unit_name, target_data.model_count]
		name_label.add_theme_font_size_override("font_size", 13)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		target_container.add_child(name_label)

		var use_button = Button.new()
		use_button.text = "Tank Shock (1 CP)"
		use_button.custom_minimum_size = Vector2(170, 30)
		use_button.pressed.connect(_on_use_pressed.bind(target_data.unit_id))
		target_container.add_child(use_button)

		target_list.add_child(target_container)

	scroll.add_child(target_list)
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

func _on_use_pressed(target_unit_id: String) -> void:
	var target_name = ""
	for target_data in eligible_targets:
		if target_data.unit_id == target_unit_id:
			target_name = target_data.unit_name
			break
	print("TankShockDialog: Player %d uses TANK SHOCK targeting %s (%s)" % [player, target_name, target_unit_id])
	emit_signal("tank_shock_used", target_unit_id, player)
	hide()
	queue_free()

func _on_decline_pressed() -> void:
	print("TankShockDialog: Player %d declines TANK SHOCK" % player)
	emit_signal("tank_shock_declined", player)
	hide()
	queue_free()
