extends AcceptDialog

# CommandRerollDialog - UI for Command Re-roll stratagem
#
# COMMAND RE-ROLL (Core – Battle Tactic Stratagem, 1 CP)
# WHEN: Any phase, just after you make a roll for a unit from your army.
# TARGET: That unit or model from your army.
# EFFECT: You re-roll that roll, test or saving throw.
# RESTRICTION: Once per phase.
#
# Shows the original roll and lets the player choose to re-roll or keep it.

signal command_reroll_used(unit_id: String, player: int)
signal command_reroll_declined(unit_id: String, player: int)

var unit_id: String = ""
var player: int = 0
var unit_name: String = ""
var roll_type: String = ""
var original_rolls: Array = []
var roll_total: int = 0
var roll_context_text: String = ""

func setup(p_unit_id: String, p_player: int, p_roll_type: String, p_original_rolls: Array, p_context_text: String = "") -> void:
	unit_id = p_unit_id
	player = p_player
	roll_type = p_roll_type
	original_rolls = p_original_rolls
	roll_context_text = p_context_text

	roll_total = 0
	for r in original_rolls:
		roll_total += r

	var unit = GameState.get_unit(unit_id)
	unit_name = unit.get("meta", {}).get("name", unit_id)

	title = "Command Re-roll Available - Player %d" % player
	min_size = DialogConstants.SMALL

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(DialogConstants.SMALL.x - 20, 0)

	# Header
	var header = Label.new()
	header.text = "COMMAND RE-ROLL"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	# Subheader
	var subheader = Label.new()
	subheader.text = "Core - Battle Tactic Stratagem"
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

	# Roll info
	var roll_label = Label.new()
	var roll_type_display = _get_roll_type_display()
	roll_label.text = "%s: %s" % [unit_name, roll_type_display]
	roll_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(roll_label)

	# Dice display
	var dice_container = HBoxContainer.new()
	dice_container.alignment = BoxContainer.ALIGNMENT_CENTER

	var dice_label = Label.new()
	dice_label.text = "Rolled: "
	dice_label.add_theme_font_size_override("font_size", 16)
	dice_container.add_child(dice_label)

	for i in range(original_rolls.size()):
		var die_label = Label.new()
		die_label.text = " [%d] " % original_rolls[i]
		die_label.add_theme_font_size_override("font_size", 18)
		die_label.add_theme_color_override("font_color", Color.ORANGE)
		dice_container.add_child(die_label)

	var total_label = Label.new()
	total_label.text = " = %d" % roll_total
	total_label.add_theme_font_size_override("font_size", 18)
	total_label.add_theme_color_override("font_color", Color.WHITE)
	dice_container.add_child(total_label)

	main_container.add_child(dice_container)

	# Context text (e.g., "Need 7+ to pass" or "Need 5 to reach target")
	if roll_context_text != "":
		var context_label = Label.new()
		context_label.text = roll_context_text
		context_label.add_theme_font_size_override("font_size", 12)
		context_label.add_theme_color_override("font_color", Color.LIGHT_GRAY)
		context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		main_container.add_child(context_label)

	main_container.add_child(HSeparator.new())

	# Action buttons
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER

	var use_button = Button.new()
	use_button.text = "Re-roll (1 CP)"
	use_button.custom_minimum_size = Vector2(160, 40)
	use_button.pressed.connect(_on_use_pressed)
	button_container.add_child(use_button)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	button_container.add_child(spacer)

	var decline_button = Button.new()
	decline_button.text = "Keep Roll"
	decline_button.custom_minimum_size = Vector2(120, 40)
	decline_button.pressed.connect(_on_decline_pressed)
	button_container.add_child(decline_button)

	main_container.add_child(button_container)

	add_child(main_container)

func _get_roll_type_display() -> String:
	match roll_type:
		"charge_roll":
			return "Charge Roll (2D6)"
		"battle_shock_test":
			return "Battle-shock Test (2D6)"
		"advance_roll":
			return "Advance Roll (D6)"
		"hit_roll":
			return "Hit Roll"
		"wound_roll":
			return "Wound Roll"
		"save_roll":
			return "Saving Throw"
		"damage_roll":
			return "Damage Roll"
		_:
			return roll_type

func _on_use_pressed() -> void:
	print("CommandRerollDialog: Player %d uses COMMAND RE-ROLL on %s (%s)" % [player, unit_name, roll_type])
	emit_signal("command_reroll_used", unit_id, player)
	hide()
	queue_free()

func _on_decline_pressed() -> void:
	print("CommandRerollDialog: Player %d keeps original roll for %s (%s)" % [player, unit_name, roll_type])
	emit_signal("command_reroll_declined", unit_id, player)
	hide()
	queue_free()
