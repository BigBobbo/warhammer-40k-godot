extends AcceptDialog
class_name SweepingAdvanceDialog

# SweepingAdvanceDialog - Offers the Sweeping Advance ability at the end of the Fight phase
#
# Shield-captain On Dawneagle Jetbike ability:
# "Once per battle, at the end of the Fight phase, if this model's unit has fought
#  this phase, if it is within Engagement Range of one or more enemy units, it can
#  make a Fall Back move or, if it is not within Engagement Range of one or more
#  enemy units, it can make a Normal move"

signal sweeping_advance_accepted(movements: Dictionary)
signal sweeping_advance_declined()

var unit_id: String = ""
var unit_name: String = ""
var in_engagement: bool = false
var move_distance: float = 6.0
var phase_reference = null
var controller_reference = null
var model_movements: Dictionary = {}

# UI elements
var status_label: Label = null
var reset_button: Button = null

func setup(p_unit_id: String, p_in_engagement: bool, p_move_distance: float, phase, controller = null) -> void:
	unit_id = p_unit_id
	in_engagement = p_in_engagement
	move_distance = p_move_distance
	phase_reference = phase
	controller_reference = controller

	var unit = phase.get_unit(unit_id) if phase else {}
	unit_name = unit.get("meta", {}).get("name", unit_id)

	title = "Sweeping Advance: %s" % unit_name

	_build_ui()

func _build_ui() -> void:
	# Disable default OK button — we use custom buttons
	get_ok_button().visible = false

	var main_container = VBoxContainer.new()
	main_container.add_theme_constant_override("separation", 8)
	main_container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	# Ability header with golden styling
	var header = Label.new()
	header.text = "SWEEPING ADVANCE"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))  # Gold
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	# "Once per battle" badge
	var badge = Label.new()
	badge.text = "[ ONCE PER BATTLE ]"
	badge.add_theme_font_size_override("font_size", 11)
	badge.add_theme_color_override("font_color", Color.ORANGE)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(badge)

	main_container.add_child(HSeparator.new())

	# Move type description
	var move_type_label = Label.new()
	if in_engagement:
		move_type_label.text = "%s is within Engagement Range of enemy units.\nThis unit may make a Fall Back move (up to %.0f\")." % [unit_name, move_distance]
	else:
		move_type_label.text = "%s is not within Engagement Range of any enemy.\nThis unit may make a Normal Move (up to %.0f\")." % [unit_name, move_distance]
	move_type_label.add_theme_font_size_override("font_size", 14)
	move_type_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	move_type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(move_type_label)

	main_container.add_child(HSeparator.new())

	# Status label for movement feedback
	status_label = Label.new()
	status_label.text = "Drag models on the battlefield to move them"
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
	var move_type_text = "Fall Back" if in_engagement else "Move"
	confirm_button.text = "Confirm %s" % move_type_text
	confirm_button.custom_minimum_size = Vector2(140, 40)
	confirm_button.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))  # Gold
	confirm_button.pressed.connect(_on_confirm_pressed)
	button_container.add_child(confirm_button)

	main_container.add_child(button_container)

	# Info text
	var info = Label.new()
	if in_engagement:
		info.text = "Fall Back: Move up to %.0f\" — must end outside Engagement Range" % move_distance
	else:
		info.text = "Normal Move: Move up to %.0f\" — cannot move within Engagement Range of enemies" % move_distance
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
		status_label.text = "No models moved yet"
		status_label.add_theme_color_override("font_color", Color.GRAY)
		return

	# Show movement count and distances
	var move_count = model_movements.size()
	status_label.text = "✓ %d model(s) repositioned" % move_count
	status_label.add_theme_color_override("font_color", Color.GREEN)

func _on_reset_pressed() -> void:
	if controller_reference and controller_reference.has_method("reset_pile_in_movements"):
		controller_reference.reset_pile_in_movements()
		model_movements.clear()
		_update_status()

func _on_confirm_pressed() -> void:
	print("[SweepingAdvanceDialog] Confirm pressed with movements: ", model_movements)
	hide()
	emit_signal("sweeping_advance_accepted", model_movements)
	await get_tree().create_timer(0.1).timeout
	queue_free()

func _on_decline_pressed() -> void:
	print("[SweepingAdvanceDialog] Declined Sweeping Advance for %s" % unit_id)
	hide()
	emit_signal("sweeping_advance_declined")
	await get_tree().create_timer(0.1).timeout
	queue_free()
