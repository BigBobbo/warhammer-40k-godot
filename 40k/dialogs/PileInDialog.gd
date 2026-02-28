extends AcceptDialog
class_name PileInDialog

signal pile_in_confirmed(movements: Dictionary)
signal pile_in_skipped()

var unit_id: String = ""
var max_distance: float = 3.0
var phase_reference = null
var controller_reference = null  # FightController reference
var model_movements: Dictionary = {}

# UI elements
var status_label: Label = null
var reset_button: Button = null

func setup(fighter_id: String, max_dist: float, phase, controller = null) -> void:
	unit_id = fighter_id
	max_distance = max_dist
	phase_reference = phase
	controller_reference = controller

	var unit = phase.get_unit(unit_id)
	title = "Pile In: %s" % unit.get("meta", {}).get("name", unit_id)

	_build_ui()

func _build_ui() -> void:
	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 10)

	var instruction = Label.new()
	instruction.text = "Drag models on the battlefield to pile in\nUp to %.1f\" toward closest enemy" % max_distance
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(instruction)

	# Status label to show validation feedback
	status_label = Label.new()
	status_label.text = "Ready - Click and drag models to move them"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color.GRAY)
	container.add_child(status_label)

	# Button container
	var button_container = HBoxContainer.new()
	button_container.add_theme_constant_override("separation", 10)

	# Reset button
	reset_button = Button.new()
	reset_button.text = "Reset Positions"
	reset_button.pressed.connect(_on_reset_pressed)
	button_container.add_child(reset_button)

	# Skip pile in button
	var skip_button = Button.new()
	skip_button.text = "Skip (No Movement)"
	skip_button.pressed.connect(_on_skip_pressed)
	button_container.add_child(skip_button)

	container.add_child(button_container)

	# Info label
	var info = Label.new()
	info.text = "• Green arrow = valid (closer to enemy, within 3\")\n• Red arrow = invalid (too far or wrong direction)\n• Dashed line = movement path with distance\n• Green dots = unit coherency maintained\n• Red X (B2B) = model in base contact, cannot move"
	info.add_theme_font_size_override("font_size", 11)
	info.add_theme_color_override("font_color", Color.DARK_GRAY)
	container.add_child(info)

	add_child(container)

	confirmed.connect(_on_confirmed)

	# Set minimum size for dialog
	min_size = DialogConstants.SMALL

	# CRITICAL: Allow input to pass through to the battlefield
	exclusive = false
	unresizable = false

func update_movements(movements: Dictionary) -> void:
	"""Called by FightController when user drags models"""
	model_movements = movements
	_update_status()

func _update_status() -> void:
	"""Update status label based on current movements"""
	if not status_label:
		return

	if model_movements.is_empty():
		status_label.text = "No models moved yet"
		status_label.add_theme_color_override("font_color", Color.GRAY)
		return

	# Validate movements
	var validation = _validate_movements()

	if validation.valid:
		status_label.text = "✓ Movement valid - %d model(s) moved" % model_movements.size()
		status_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		var error_text = validation.errors[0] if validation.errors.size() > 0 else "Invalid movement"
		status_label.text = "✗ %s" % error_text
		status_label.add_theme_color_override("font_color", Color.RED)

func _validate_movements() -> Dictionary:
	"""Validate current movements using FightPhase validation"""
	if not phase_reference or model_movements.is_empty():
		return {"valid": true, "errors": []}

	# Create action to validate
	var action = {
		"unit_id": unit_id,
		"movements": model_movements
	}

	# Use FightPhase validation
	if phase_reference.has_method("_validate_pile_in"):
		return phase_reference._validate_pile_in(action)

	return {"valid": true, "errors": []}

func _on_reset_pressed() -> void:
	"""Reset all model positions to original"""
	if controller_reference and controller_reference.has_method("reset_pile_in_movements"):
		controller_reference.reset_pile_in_movements()
		model_movements.clear()
		_update_status()

func _on_skip_pressed() -> void:
	hide()
	emit_signal("pile_in_skipped")
	await get_tree().create_timer(0.1).timeout
	queue_free()

func _on_confirmed() -> void:
	"""Confirm pile-in movements - validate before submitting"""
	print("[PileInDialog] Confirm button pressed")
	print("[PileInDialog] Current movements: ", model_movements)

	# T5-MP2: Validate movements before confirming to give client-side feedback
	if not model_movements.is_empty():
		var validation = _validate_movements()
		if not validation.valid:
			var error_text = validation.errors[0] if validation.errors.size() > 0 else "Invalid movement"
			print("[PileInDialog] T5-MP2: Blocking confirm — validation failed: ", error_text)
			status_label.text = "✗ Cannot confirm: %s" % error_text
			status_label.add_theme_color_override("font_color", Color.RED)
			ToastManager.show_error("Pile-in rejected: %s" % error_text)
			return  # Don't dismiss — let the player fix the movement

	print("[PileInDialog] Emitting pile_in_confirmed signal")
	hide()
	emit_signal("pile_in_confirmed", model_movements)
	await get_tree().create_timer(0.1).timeout
	queue_free()
