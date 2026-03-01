extends AcceptDialog

# DeepStrikePlacementDialog - UI for choosing between Deep Strike and Strategic Reserves placement
#
# BALANCE DATASLATE RULE:
# "If a unit with Deep Strike arrives from Strategic Reserves, the player can choose
#  to set up using Strategic Reserves OR Deep Strike rules."
#
# Deep Strike rules: anywhere on the board >9" from enemies
# Strategic Reserves rules: within 6" of board edge, >9" from enemies,
#                           cannot be in opponent's deployment zone on Turn 2

signal placement_chosen(unit_id: String, placement_type: String)

var unit_id: String = ""
var unit_name: String = ""

func setup(p_unit_id: String, p_unit_name: String) -> void:
	unit_id = p_unit_id
	unit_name = p_unit_name

	title = "Choose Placement Type - %s" % unit_name

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	min_size = DialogConstants.SMALL
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(DialogConstants.SMALL.x - 20, 0)

	# Header
	var header = Label.new()
	header.text = "REINFORCEMENT PLACEMENT"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color.GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	# Unit name
	var name_label = Label.new()
	name_label.text = unit_name
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(name_label)

	# Separator
	var sep = HSeparator.new()
	main_container.add_child(sep)

	# Explanation
	var desc = Label.new()
	desc.text = "This unit has Deep Strike and was placed in Strategic Reserves.\nChoose which placement rules to use:"
	desc.add_theme_font_size_override("font_size", 12)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_container.add_child(desc)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	main_container.add_child(spacer)

	# Deep Strike button
	var ds_button = Button.new()
	ds_button.text = "Deep Strike (anywhere >9\" from enemies)"
	ds_button.add_theme_font_size_override("font_size", 14)
	ds_button.custom_minimum_size = Vector2(0, 40)
	ds_button.pressed.connect(_on_deep_strike_chosen)
	main_container.add_child(ds_button)

	# Strategic Reserves button
	var sr_button = Button.new()
	sr_button.text = "Strategic Reserves (within 6\" of board edge)"
	sr_button.add_theme_font_size_override("font_size", 14)
	sr_button.custom_minimum_size = Vector2(0, 40)
	sr_button.pressed.connect(_on_strategic_reserves_chosen)
	main_container.add_child(sr_button)

	add_child(main_container)

func _on_deep_strike_chosen() -> void:
	print("DeepStrikePlacementDialog: Player chose Deep Strike placement for %s" % unit_name)
	emit_signal("placement_chosen", unit_id, "deep_strike")
	hide()
	queue_free()

func _on_strategic_reserves_chosen() -> void:
	print("DeepStrikePlacementDialog: Player chose Strategic Reserves placement for %s" % unit_name)
	emit_signal("placement_chosen", unit_id, "strategic_reserves")
	hide()
	queue_free()
