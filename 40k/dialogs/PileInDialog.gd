extends AcceptDialog
class_name PileInDialog

signal pile_in_confirmed(movements: Dictionary)
signal pile_in_skipped()

# Shared muted tones so the neutral status line and the legend read the same
# way the other White Dwarf menus do (readable, but subordinate to the gold).
const _NEUTRAL_STATUS := Color(0.7, 0.7, 0.8)
const _LEGEND_COLOR := Color(0.7, 0.7, 0.8)

var unit_id: String = ""
var max_distance: float = 3.0
var phase_reference = null
var controller_reference = null  # FightController reference
var model_movements: Dictionary = {}
var model_rotations: Dictionary = {}  # model_id -> rotation (radians) for pivoting bikes/vehicles

# UI elements
var status_label: Label = null
var reset_button: Button = null

func setup(fighter_id: String, max_dist: float, phase, controller = null) -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	unit_id = fighter_id
	max_distance = max_dist
	phase_reference = phase
	controller_reference = controller

	# 19.03: the attached characters pile in as part of this unit — title the
	# move as the Attached unit ("Custodian Guard + Blade Champion").
	if phase != null and phase.has_method("_fight_attached_display_name"):
		title = "Pile In: %s" % phase._fight_attached_display_name(unit_id)
	else:
		var unit = phase.get_unit(unit_id)
		var _pid_meta = unit.get("meta", {})
		title = "Pile In: %s" % _pid_meta.get("display_name", _pid_meta.get("name", unit_id))

	_build_ui()

func _build_ui() -> void:
	var container = VBoxContainer.new()
	container.name = "Content"
	container.add_theme_constant_override("separation", 8)

	# Heading — gold, to match the gold section headers used across the menus.
	var instruction = Label.new()
	instruction.name = "Instruction"
	instruction.text = "Drag models to pile in — or hit \"Auto Pile In\"\nUp to %.1f\" toward the closest enemy" % max_distance
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.add_theme_font_size_override("font_size", 15)
	instruction.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	container.add_child(instruction)

	# Status label to show validation feedback
	status_label = Label.new()
	status_label.name = "Status"
	status_label.text = "Ready — click and drag models to move them"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", _NEUTRAL_STATUS)
	container.add_child(status_label)

	WhiteDwarfTheme.add_gold_separator(container)

	# Button container — centered, evenly spaced action row like the other menus.
	var button_container = HBoxContainer.new()
	button_container.name = "Buttons"
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_theme_constant_override("separation", 10)

	# Auto pile-in button — let the computer move every model toward the closest
	# enemy (up to 3", legally) so the player doesn't have to drag each one. Fills
	# in the move as a preview; the player still reviews it and hits Confirm.
	var auto_button = Button.new()
	auto_button.name = "AutoButton"
	auto_button.text = "Auto Pile In"
	auto_button.tooltip_text = "Move every model toward the closest enemy automatically (up to 3\"). Review the preview, then Confirm."
	auto_button.custom_minimum_size = Vector2(0, 36)
	auto_button.pressed.connect(_on_auto_pile_in_pressed)
	button_container.add_child(auto_button)

	# Reset button
	reset_button = Button.new()
	reset_button.name = "ResetButton"
	reset_button.text = "Reset Positions"
	reset_button.custom_minimum_size = Vector2(0, 36)
	reset_button.pressed.connect(_on_reset_pressed)
	button_container.add_child(reset_button)

	# Skip pile in button
	var skip_button = Button.new()
	skip_button.name = "SkipButton"
	skip_button.text = "Skip (No Movement)"
	skip_button.custom_minimum_size = Vector2(0, 36)
	skip_button.pressed.connect(_on_skip_pressed)
	button_container.add_child(skip_button)

	# Explicit confirm button with a stable path (the built-in AcceptDialog
	# OK button lives under auto-named internal containers). Styled as the
	# primary (red) action so it reads as the main affordance like Start Game.
	var confirm_button = Button.new()
	confirm_button.name = "ConfirmButton"
	confirm_button.text = "Confirm Move"
	confirm_button.custom_minimum_size = Vector2(0, 36)
	confirm_button.pressed.connect(_on_confirmed)
	button_container.add_child(confirm_button)
	WhiteDwarfTheme.apply_primary_button(confirm_button)

	container.add_child(button_container)

	WhiteDwarfTheme.add_gold_separator(container)

	# Legend — muted but readable. (Was Color.DARK_GRAY, near-invisible on the
	# dark parchment-on-black dialog background.)
	var info = Label.new()
	info.name = "Legend"
	info.text = "• Green arrow = valid (closer to enemy, within 3\")\n• Red arrow = invalid (too far or wrong direction)\n• Dashed line = movement path with distance\n• Green dots = unit coherency maintained\n• Red X (B2B) = model in base contact, cannot move"
	info.add_theme_font_size_override("font_size", 11)
	info.add_theme_color_override("font_color", _LEGEND_COLOR)
	container.add_child(info)

	add_child(container)

	confirmed.connect(_on_confirmed)

	# Redundant with the explicit "Confirm Move" button and out of keeping with
	# the menu-style action row — hide the built-in AcceptDialog OK button.
	# (Enter still confirms via the `confirmed` signal above.)
	get_ok_button().visible = false

	# Set minimum size for dialog
	min_size = DialogConstants.SMALL

	# CRITICAL: Allow input to pass through to the battlefield
	exclusive = false
	unresizable = false

func update_movements(movements: Dictionary) -> void:
	"""Called by FightController when user drags models"""
	model_movements = movements
	_update_status()

func update_rotations(rotations: Dictionary) -> void:
	"""Called by FightController when the user pivots a model (non-circular base)"""
	model_rotations = rotations
	_update_status()

func _update_status() -> void:
	"""Update status label based on current movements"""
	if not status_label:
		return

	if model_movements.is_empty():
		status_label.text = "No models moved yet"
		status_label.add_theme_color_override("font_color", _NEUTRAL_STATUS)
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
		"movements": model_movements,
		"rotations": model_rotations
	}

	# Use FightPhase validation
	if phase_reference.has_method("_validate_pile_in"):
		return phase_reference._validate_pile_in(action)

	return {"valid": true, "errors": []}

func _on_auto_pile_in_pressed() -> void:
	"""Have the computer pile every model in toward the closest enemy, then let
	the player review and Confirm (or Reset). Reuses the AI pile-in solver via the
	FightController so the move follows the same legal rules."""
	print("[PileInDialog] Auto Pile In pressed")
	if not controller_reference or not controller_reference.has_method("auto_pile_in_movements"):
		print("[PileInDialog] No controller / auto_pile_in_movements — cannot auto pile in")
		return

	model_movements = controller_reference.auto_pile_in_movements()
	print("[PileInDialog] Auto pile-in produced movements: ", model_movements)

	if not status_label:
		return
	if model_movements.is_empty():
		status_label.text = "Auto pile-in: no legal move (models already in base contact or no enemy in reach)"
		status_label.add_theme_color_override("font_color", _NEUTRAL_STATUS)
	else:
		# _update_status() re-validates via FightPhase and shows the ✓/✗ result
		_update_status()

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
