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

	# 19.03: the attached characters consolidate as part of this unit — title
	# the move as the Attached unit ("Custodian Guard + Blade Champion").
	if phase != null and phase.has_method("_fight_attached_display_name"):
		title = "Consolidate: %s" % phase._fight_attached_display_name(unit_id)
	else:
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
	instruction.add_theme_font_size_override("font_size", 19)
	instruction.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	container.add_child(instruction)

	# Status label to show validation feedback
	status_label = Label.new()
	status_label.name = "Status"
	status_label.text = "Ready — click and drag models to move them"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", _NEUTRAL_STATUS)
	container.add_child(status_label)

	WhiteDwarfTheme.add_gold_separator(container)

	# Button container — centered, evenly spaced action row like the other menus.
	var button_container = HBoxContainer.new()
	button_container.name = "Buttons"
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_theme_constant_override("separation", 10)

	# Auto consolidate button — let the computer move every model toward the
	# closest enemy (or objective, per the 12.08 mode) up to 3", legally, so the
	# player doesn't have to drag each one. Fills in a preview; the player still
	# reviews it and hits Confirm.
	var auto_button = Button.new()
	auto_button.name = "AutoButton"
	auto_button.text = "Auto Consolidate"
	auto_button.tooltip_text = "Move every model toward the closest enemy (or objective) automatically (up to 3\"). Review the preview, then Confirm."
	auto_button.custom_minimum_size = Vector2(0, 36)
	auto_button.pressed.connect(_on_auto_consolidate_pressed)
	button_container.add_child(auto_button)

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
	# The arrows point wherever the mandatory mode says the models must go — the
	# selected objective in Objective mode, the closest enemy otherwise.
	var arrow_target = "the objective" if str(_consolidate_context().get("mode", "")) == "objective" else "enemy"
	info.text = "• Green arrow = valid (closer to %s, within 3\")\n• Red arrow = invalid (too far or wrong direction)\n• Dashed line = movement path with distance\n• Green dots = unit coherency maintained" % arrow_target
	info.add_theme_font_size_override("font_size", 16)
	info.add_theme_color_override("font_color", _LEGEND_COLOR)
	container.add_child(info)

	# Pad (controller) hint row — shown only when the pad is the active device.
	# Consolidating on a controller uses Auto Consolidate (Ⓨ) then Confirm (☰);
	# manual per-model drag stays a mouse affordance.
	var pad_hint := Label.new()
	pad_hint.name = "PadHintLabel"
	pad_hint.text = "Ⓨ Auto Consolidate   ·   ☰ Confirm   ·   Ⓑ Skip"
	pad_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pad_hint.add_theme_font_size_override("font_size", 16)
	pad_hint.modulate = Color(1, 1, 1, 0.8)
	pad_hint.visible = InputDeviceManager.is_pad_active()
	container.add_child(pad_hint)

	add_child(container)

	confirmed.connect(_on_confirmed)

	# Redundant with the explicit "Confirm Move" button and out of keeping with
	# the menu-style action row — hide the built-in AcceptDialog OK button.
	# (Enter still confirms via the `confirmed` signal above.)
	get_ok_button().visible = false

	# Set minimum size for dialog
	min_size = DialogConstants.SMALL

	# CRITICAL: Allow input to pass through to the battlefield. MUST stay inside
	# _build_ui() (a pile-in-dialog revision once orphaned this below a function
	# def, leaving the dialog modal and blocking the board drag).
	exclusive = false
	unresizable = false

	# Pad: drive the action row off the dialog's own window_input (mirrors the
	# Pile-In dialog) — ☰ Confirm, Ⓑ Skip, Ⓨ Auto Consolidate.
	window_input.connect(_pad_handle_input)
	about_to_popup.connect(_pad_refresh_hint)

# Pad: keep the hint row in sync with the active device when the dialog pops.
func _pad_refresh_hint() -> void:
	var h := get_node_or_null("Content/PadHintLabel")
	if h != null:
		h.visible = InputDeviceManager.is_pad_active()

# Pad navigation for the Consolidate step dialog: ☰ Confirms, Ⓑ Skips, Ⓨ runs
# Auto Consolidate (the no-drag fast path). Manual per-model drag stays a mouse
# affordance (the on-screen cursor click can't press-and-hold to drag a model).
func _pad_handle_input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton) or not event.pressed:
		return
	# Settings › Controller remaps: match on the canonical button of the role
	# the pressed physical button carries.
	match PadBindings.canonical(event.button_index):
		JOY_BUTTON_START:
			_pad_press("ConfirmButton")
			set_input_as_handled()
		JOY_BUTTON_B:
			_pad_press("SkipButton")
			set_input_as_handled()
		JOY_BUTTON_Y:
			_pad_press("AutoButton")
			set_input_as_handled()

func _pad_press(button_name: String) -> void:
	var q: Array = [self]
	while not q.is_empty():
		var n = q.pop_front()
		if n is Button and str(n.name) == button_name and n.visible and not n.disabled:
			n.emit_signal("pressed")
			return
		for c in n.get_children():
			q.append(c)

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

func _on_auto_consolidate_pressed() -> void:
	"""Have the computer consolidate every model toward the closest enemy (or
	objective), then let the player review and Confirm (or Reset). Reuses the AI
	consolidate solver via the FightController so the move is always legal."""
	print("[ConsolidateDialog] Auto Consolidate pressed")
	if not controller_reference or not controller_reference.has_method("auto_consolidate_movements"):
		print("[ConsolidateDialog] No controller / auto_consolidate_movements — cannot auto consolidate")
		return

	model_movements = controller_reference.auto_consolidate_movements()
	print("[ConsolidateDialog] Auto consolidate produced movements: ", model_movements)

	if not status_label:
		return
	if model_movements.is_empty():
		status_label.text = "Auto consolidate: no legal move (no enemy or objective in reach, or already in base contact)"
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
	emit_signal("consolidate_skipped")
	await get_tree().create_timer(0.1).timeout
	queue_free()

func _consolidate_context() -> Dictionary:
	"""The unit's 12.08 BEFORE MOVING context — mandatory mode plus its selected
	enemy targets or objective. Comes from the phase (the same call the drag
	validation and CONSOLIDATE validation make), never re-derived here."""
	if controller_reference != null and not controller_reference.consolidate_context_11e.is_empty():
		return controller_reference.consolidate_context_11e
	if phase_reference != null and phase_reference.has_method("get_consolidation_context_11e"):
		return phase_reference.get_consolidation_context_11e(unit_id)
	return {}

func _get_consolidate_mode_text() -> String:
	"""Instruction text for the unit's mandatory 12.08 consolidation mode.

	This used to gate on FightPhase._can_unit_reach_engagement_range() — a 10e
	heuristic for 'could this unit reach engagement range within its 3" move'
	(3" + 2" engagement range = 5"), which is NOT the 12.08 mode order. A unit
	3-5" from an enemy and within 3" of an objective was shown the enemy rules
	('must end closer to closest enemy') for a move the rules say is an
	Objective Consolidation."""
	var ctx = _consolidate_context()
	match str(ctx.get("mode", "")):
		"ongoing":
			return "Ongoing Consolidation: Move up to %.1f\"\n• Models in base contact with an enemy cannot move\n• Each model moved must end closer to the closest selected enemy unit\n• Must still be engaged with every unit it started engaged with" % max_distance
		"engaging":
			return "Engaging Consolidation: Move up to %.1f\"\n• Each model moved must end closer to the closest selected enemy unit\n• The unit must end engaged with every selected enemy unit\n• Enemy units it engages that have not fought will be selected to fight" % max_distance
		"objective":
			var obj_name = str(ctx.get("objective", ""))
			var obj_suffix = " (%s)" % obj_name if obj_name != "" else ""
			return "Objective Consolidation: Move up to %.1f\" toward the objective%s\n• Each model moved must end within range of the objective, or closer to it\n• The unit must end within range of the objective\n• Must maintain Unit Coherency" % [max_distance, obj_suffix]
		_:
			return "Consolidate: no mode applies from here (12.08)\n• Not engaged, no enemy unit within 3\", no objective within 3\"\n• Confirm without moving to complete this unit's step"

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
