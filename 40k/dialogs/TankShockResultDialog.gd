extends AcceptDialog
class_name TankShockResultDialog

# TankShockResultDialog - Shows the results of a TANK SHOCK stratagem roll
# Displays D6 results (variable count based on Toughness) with successes (5+) highlighted

signal result_acknowledged()

func setup(result: Dictionary) -> void:
	title = "TANK SHOCK Result"
	min_size = DialogConstants.SMALL
	get_ok_button().text = "OK"
	get_ok_button().pressed.connect(_on_ok)

	var dice_rolls = result.get("dice_rolls", [])
	var mortal_wounds = result.get("mortal_wounds", 0)
	var casualties = result.get("casualties", 0)
	var toughness = result.get("toughness", 0)
	var dice_count = result.get("dice_count", 0)
	var vehicle_unit_id = result.get("vehicle_unit_id", "")
	var target_unit_id = result.get("target_unit_id", "")

	var vehicle_unit = GameState.get_unit(vehicle_unit_id)
	var target_unit = GameState.get_unit(target_unit_id)
	var vehicle_name = vehicle_unit.get("meta", {}).get("name", vehicle_unit_id)
	var target_name = target_unit.get("meta", {}).get("name", target_unit_id)

	var main = VBoxContainer.new()
	main.custom_minimum_size = Vector2(DialogConstants.SMALL.x - 20, 0)

	# Header
	var header = Label.new()
	header.text = "TANK SHOCK"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.ORANGE_RED)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(header)

	# Unit info
	var info = Label.new()
	info.text = "%s rammed into %s!" % [vehicle_name, target_name]
	info.add_theme_font_size_override("font_size", 13)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(info)

	main.add_child(HSeparator.new())

	# Dice display
	var dice_label = Label.new()
	dice_label.text = "Roll %dD6 (Toughness %d, 5+ = mortal wound):" % [dice_count, toughness]
	dice_label.add_theme_font_size_override("font_size", 13)
	main.add_child(dice_label)

	# Dice icons row
	var dice_row = HBoxContainer.new()
	dice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	dice_row.add_theme_constant_override("separation", 10)

	for roll in dice_rolls:
		var die = Label.new()
		die.text = "[%d]" % roll
		die.add_theme_font_size_override("font_size", 24)
		die.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		die.custom_minimum_size = Vector2(45, 40)

		if roll >= 5:
			die.add_theme_color_override("font_color", Color.GREEN)
		else:
			die.add_theme_color_override("font_color", Color.RED)

		dice_row.add_child(die)

	main.add_child(dice_row)

	main.add_child(HSeparator.new())

	# Results
	var results_label = Label.new()
	if mortal_wounds > 0:
		results_label.text = "%d mortal wound%s dealt!" % [mortal_wounds, "s" if mortal_wounds != 1 else ""]
		results_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		results_label.text = "No mortal wounds dealt."
		results_label.add_theme_color_override("font_color", Color.GRAY)
	results_label.add_theme_font_size_override("font_size", 16)
	results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(results_label)

	if casualties > 0:
		var cas_label = Label.new()
		cas_label.text = "%d model%s destroyed" % [casualties, "s" if casualties != 1 else ""]
		cas_label.add_theme_font_size_override("font_size", 14)
		cas_label.add_theme_color_override("font_color", Color.ORANGE_RED)
		cas_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		main.add_child(cas_label)

	add_child(main)

func _on_ok() -> void:
	emit_signal("result_acknowledged")
	hide()
	queue_free()
