extends AcceptDialog
class_name AcrobaticEscapeDialog

# AcrobaticEscapeDialog - Offers the Acrobatic Escape ability at the end of the Fight phase
#
# Callidus Assassin ability:
# "At the end of the Fight phase, if this model is within Engagement Range of one or
#  more enemy units, it can make a Fall Back move of up to D6\"."

signal acrobatic_escape_accepted(movements: Dictionary)
signal acrobatic_escape_declined()

var unit_id: String = ""
var unit_name: String = ""
var move_distance: float = 1.0  # D6 result
var phase_reference = null
var controller_reference = null
var model_movements: Dictionary = {}

# UI elements
var status_label: Label = null
var reset_button: Button = null

func setup(p_unit_id: String, p_move_distance: float, phase, controller = null) -> void:
	unit_id = p_unit_id
	move_distance = p_move_distance
	phase_reference = phase
	controller_reference = controller

	var unit = phase.get_unit(unit_id) if phase else {}
	unit_name = unit.get("meta", {}).get("name", unit_id)

	title = "Acrobatic Escape: %s" % unit_name

	_build_ui()

func _build_ui() -> void:
	# Disable default OK button — we use custom buttons
	get_ok_button().visible = false

	var main_container = VBoxContainer.new()
	main_container.add_theme_constant_override("separation", 8)
	main_container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	# Ability header with golden styling
	var header = Label.new()
	header.text = "ACROBATIC ESCAPE"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(0.8, 0.2, 0.8))  # Purple for assassin
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	# D6 roll result badge
	var badge = Label.new()
	badge.text = "[ D6 ROLL: %d ]" % int(move_distance)
	badge.add_theme_font_size_override("font_size", 14)
	badge.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))  # Gold
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(badge)

	main_container.add_child(HSeparator.new())

	# Move type description
	var desc_label = Label.new()
	desc_label.text = "%s is within Engagement Range of enemy units.\nThis model may make a Fall Back move of up to %d\"." % [unit_name, int(move_distance)]
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(desc_label)

	main_container.add_child(HSeparator.new())

	# Status label for movement feedback
	status_label = Label.new()
	status_label.text = "Drag the model on the battlefield to move it"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color.GRAY)
	main_container.add_child(status_label)

	# Button container
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_theme_constant_override("separation", 10)

	# Decline button
	var decline_button = Button.new()
	decline_button.text = "Decline"
	decline_button.custom_minimum_size = Vector2(120, 40)
	decline_button.pressed.connect(_on_decline_pressed)
	button_container.add_child(decline_button)

	# Reset button
	reset_button = Button.new()
	reset_button.text = "Reset"
	reset_button.custom_minimum_size = Vector2(100, 40)
	reset_button.pressed.connect(_on_reset_pressed)
	button_container.add_child(reset_button)

	# Confirm button
	var confirm_button = Button.new()
	confirm_button.text = "Confirm Fall Back"
	confirm_button.custom_minimum_size = Vector2(140, 40)
	confirm_button.add_theme_color_override("font_color", Color(0.8, 0.2, 0.8))  # Purple
	confirm_button.pressed.connect(_on_confirm_pressed)
	button_container.add_child(confirm_button)

	main_container.add_child(button_container)

	# Info text
	var info = Label.new()
	info.text = "Fall Back: Move up to %d\" — must end outside Engagement Range" % int(move_distance)
	info.add_theme_font_size_override("font_size", 11)
	info.add_theme_color_override("font_color", Color.DARK_GRAY)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_container.add_child(info)

	add_child(main_container)

	# CRITICAL: Allow input to pass through to the battlefield for model dragging
	exclusive = false
	unresizable = false
	min_size = DialogConstants.MEDIUM

func update_movements(movements: Dictionary) -> void:
	"""Called by FightController when user drags models"""
	model_movements = movements
	_update_status()

func _update_status() -> void:
	if not status_label:
		return

	if model_movements.is_empty():
		status_label.text = "No model moved yet"
		status_label.add_theme_color_override("font_color", Color.GRAY)
		return

	var move_count = model_movements.size()
	status_label.text = "Model repositioned"
	status_label.add_theme_color_override("font_color", Color.GREEN)

func _on_reset_pressed() -> void:
	if controller_reference and controller_reference.has_method("reset_pile_in_movements"):
		controller_reference.reset_pile_in_movements()
		model_movements.clear()
		_update_status()

func _on_confirm_pressed() -> void:
	print("[AcrobaticEscapeDialog] Confirm pressed with movements: ", model_movements)
	hide()
	emit_signal("acrobatic_escape_accepted", model_movements)
	await get_tree().create_timer(0.1).timeout
	queue_free()

func _on_decline_pressed() -> void:
	print("[AcrobaticEscapeDialog] Declined Acrobatic Escape for %s" % unit_id)
	hide()
	emit_signal("acrobatic_escape_declined")
	await get_tree().create_timer(0.1).timeout
	queue_free()
