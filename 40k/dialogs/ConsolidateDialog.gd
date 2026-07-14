extends AcceptDialog
class_name ConsolidateDialog

signal consolidate_confirmed(movements: Dictionary)
signal consolidate_skipped()

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

	var unit = phase.get_unit(unit_id)
	var _cd_meta = unit.get("meta", {})
	title = "Consolidate: %s" % _cd_meta.get("display_name", _cd_meta.get("name", unit_id))

	_build_ui()

func _build_ui() -> void:
	var container = VBoxContainer.new()
	container.name = "Content"
	container.add_theme_constant_override("separation", 8)

	# Heading — gold, to match the gold section headers used across the menus.
	var instruction = Label.new()
	instruction.name = "Instruction"
	# Determine consolidate mode
	var mode_text = _get_consolidate_mode_text()
	instruction.text = mode_text
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

	# Reset button
	reset_button = Button.new()
	reset_button.name = "ResetButton"
	reset_button.text = "Reset Positions"
	reset_button.custom_minimum_size = Vector2(0, 36)
	reset_button.pressed.connect(_on_reset_pressed)
	button_container.add_child(reset_button)

	# FGT-1 / P2-78: Consolidation is mandatory at unit level per FAQ, but
	# individual model movement is optional. This button confirms the step
	# with no models electing to move (not "skipping" consolidation).
	var no_move_button = Button.new()
	no_move_button.name = "SkipButton"
	no_move_button.text = "Confirm (No Models Move)"
	no_move_button.custom_minimum_size = Vector2(0, 36)
	no_move_button.pressed.connect(_on_skip_pressed)
	button_container.add_child(no_move_button)

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
	info.text = "• Green arrow = valid (closer to enemy, within 3\")\n• Red arrow = invalid (too far or wrong direction)\n• Dashed line = movement path with distance\n• Green dots = unit coherency maintained"
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

	# Check if unit can reach engagement range
	var unit = phase_reference.get_unit(unit_id)
	var can_reach_engagement = phase_reference._can_unit_reach_engagement_range(unit) if phase_reference.has_method("_can_unit_reach_engagement_range") else true

	if can_reach_engagement:
		return "Consolidate: Move up to %.1f\"\n• Must end closer to closest enemy\n• Must end in base contact if possible\n• Must remain in Engagement Range" % max_distance
	else:
		# Too far from enemies - objective mode
		return "Consolidate: Move up to %.1f\"\n• Move toward closest objective marker\n• At least one model must end within 3\" of objective\n• Must maintain Unit Coherency" % max_distance

func _is_unit_in_engagement_range(unit: Dictionary) -> bool:
	"""Check if unit is currently in engagement range with any enemy"""
	if not phase_reference or not phase_reference.has_method("_find_enemies_in_engagement_range"):
		return true  # Assume in engagement if we can't check

	var enemies = phase_reference._find_enemies_in_engagement_range(unit)
	return not enemies.is_empty()

func _on_confirmed() -> void:
	"""Confirm consolidate movements - validate before submitting"""
	print("[ConsolidateDialog] Confirm button pressed")
	print("[ConsolidateDialog] Current movements: ", model_movements)

	# T5-MP2: Validate movements before confirming to give client-side feedback
	if not model_movements.is_empty():
		var validation = _validate_movements()
		if not validation.valid:
			var error_text = validation.errors[0] if validation.errors.size() > 0 else "Invalid movement"
			print("[ConsolidateDialog] T5-MP2: Blocking confirm — validation failed: ", error_text)
			status_label.text = "✗ Cannot confirm: %s" % error_text
			status_label.add_theme_color_override("font_color", Color.RED)
			ToastManager.show_error("Consolidate rejected: %s" % error_text)
			return  # Don't dismiss — let the player fix the movement

	print("[ConsolidateDialog] Emitting consolidate_confirmed signal")
	hide()
	emit_signal("consolidate_confirmed", model_movements)
	await get_tree().create_timer(0.1).timeout
	queue_free()
