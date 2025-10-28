extends AcceptDialog
class_name ConsolidateDialog

signal consolidate_confirmed(movements: Dictionary)
signal consolidate_skipped()

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
	title = "Consolidate: %s" % unit.get("meta", {}).get("name", unit_id)

	_build_ui()

func _build_ui() -> void:
	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 10)

	var instruction = Label.new()
	# Determine consolidate mode
	var mode_text = _get_consolidate_mode_text()
	instruction.text = mode_text
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

	# Skip consolidate button
	var skip_button = Button.new()
	skip_button.text = "Skip (No Movement)"
	skip_button.pressed.connect(_on_skip_pressed)
	button_container.add_child(skip_button)

	container.add_child(button_container)

	# Info label
	var info = Label.new()
	info.text = "• Green line = valid movement\n• Red line = invalid (too far or wrong direction)\n• Green dots = unit coherency maintained"
	info.add_theme_font_size_override("font_size", 11)
	info.add_theme_color_override("font_color", Color.DARK_GRAY)
	container.add_child(info)

	add_child(container)

	confirmed.connect(_on_confirmed)

	# Set minimum size for dialog
	min_size = Vector2(400, 200)

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

	# Use FightPhase validation (consolidate uses same rules as pile-in)
	if phase_reference.has_method("_validate_consolidate"):
		return phase_reference._validate_consolidate(action)

	return {"valid": true, "errors": []}

func _on_reset_pressed() -> void:
	"""Reset all model positions to original"""
	if controller_reference and controller_reference.has_method("reset_pile_in_movements"):
		controller_reference.reset_pile_in_movements()
		model_movements.clear()
		_update_status()

func _on_skip_pressed() -> void:
	hide()
	emit_signal("consolidate_skipped")
	await get_tree().create_timer(0.1).timeout
	queue_free()

func _get_consolidate_mode_text() -> String:
	"""Determine what consolidate mode is available and return instruction text"""
	if not phase_reference:
		return "Drag models on the battlefield to consolidate\nUp to %.1f\" toward closest enemy" % max_distance

	# Check if unit is currently in engagement range
	var unit = phase_reference.get_unit(unit_id)
	var in_engagement = _is_unit_in_engagement_range(unit)

	if in_engagement:
		return "Consolidate: Move up to %.1f\"\n• Must end closer to closest enemy\n• Must end in base contact if possible\n• Must remain in Engagement Range" % max_distance
	else:
		# Not in engagement - would need objective fallback
		return "Consolidate: Move up to %.1f\"\n• Move toward closest objective marker\n• Must end within range of objective\n(Objective mode - not fully implemented)" % max_distance

func _is_unit_in_engagement_range(unit: Dictionary) -> bool:
	"""Check if unit is currently in engagement range with any enemy"""
	if not phase_reference or not phase_reference.has_method("_find_enemies_in_engagement_range"):
		return true  # Assume in engagement if we can't check

	var enemies = phase_reference._find_enemies_in_engagement_range(unit)
	return not enemies.is_empty()

func _on_confirmed() -> void:
	"""Confirm consolidate movements - let FightPhase handle final validation"""
	print("[ConsolidateDialog] Confirm button pressed")
	print("[ConsolidateDialog] Current movements: ", model_movements)

	# Don't validate here - let FightPhase do it when processing the action
	# This avoids issues with active_fighter_id timing
	print("[ConsolidateDialog] Emitting consolidate_confirmed signal")
	hide()
	emit_signal("consolidate_confirmed", model_movements)
	await get_tree().create_timer(0.1).timeout
	queue_free()
