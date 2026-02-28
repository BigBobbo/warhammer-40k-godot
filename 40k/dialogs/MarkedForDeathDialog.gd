extends AcceptDialog
class_name MarkedForDeathDialog

# MarkedForDeathDialog - Two-step unit selection for Marked for Death secondary mission
#
# When Player 1 draws Marked for Death, Player 2 must select:
# Step 1: 3 Alpha targets from their own units
# Step 2: 1 Gamma target from remaining units
#
# Fallback: If opponent has fewer than 4 units, adjust selections accordingly

signal marked_for_death_resolved(alpha_targets: Array, gamma_target: String)

var opponent_units: Array = []  # Array of { unit_id, unit_name }
var selected_alpha_targets: Array = []  # Array of unit_id strings
var selected_gamma_target: String = ""
var required_alpha_count: int = 3
var opponent_player: int = 0

# UI references
var step_label: Label
var unit_list_container: VBoxContainer
var info_label: Label
var confirm_btn: Button
var back_btn: Button

func setup(opponent: int, units: Array, details: Dictionary) -> void:
	opponent_player = opponent
	opponent_units = units
	required_alpha_count = details.get("alpha_targets", 3)
	var fallback = details.get("fallback_if_fewer", true)

	# Fallback: if fewer units than required alpha + gamma, adjust
	if fallback and opponent_units.size() < required_alpha_count + 1:
		required_alpha_count = max(0, opponent_units.size() - 1)

	title = "Marked for Death — Player %d Selects Targets" % opponent
	get_ok_button().visible = false

	_build_ui()
	_show_alpha_selection()

func _build_ui() -> void:
	min_size = DialogConstants.MEDIUM
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	# Header
	var header = Label.new()
	header.text = "MARKED FOR DEATH"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.ORANGE)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	# Flavour text
	var flavour = Label.new()
	flavour.text = "Your opponent has drawn Marked for Death.\nYou must designate targets from your own units."
	flavour.add_theme_font_size_override("font_size", 12)
	flavour.add_theme_color_override("font_color", Color.GRAY)
	flavour.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavour.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(flavour)

	main_container.add_child(HSeparator.new())

	# Step indicator
	step_label = Label.new()
	step_label.add_theme_font_size_override("font_size", 14)
	step_label.add_theme_color_override("font_color", Color.CYAN)
	main_container.add_child(step_label)

	# Info label (shows selection count etc.)
	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 12)
	info_label.add_theme_color_override("font_color", Color.LIGHT_GREEN)
	main_container.add_child(info_label)

	# Scroll container for unit list
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 220)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	unit_list_container = VBoxContainer.new()
	unit_list_container.name = "UnitListContainer"
	scroll.add_child(unit_list_container)
	main_container.add_child(scroll)

	main_container.add_child(HSeparator.new())

	# Button row
	var button_row = HBoxContainer.new()

	back_btn = Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(100, 35)
	back_btn.visible = false
	back_btn.pressed.connect(_on_back_pressed)
	button_row.add_child(back_btn)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_row.add_child(spacer)

	confirm_btn = Button.new()
	confirm_btn.text = "Confirm Alpha Targets"
	confirm_btn.custom_minimum_size = Vector2(180, 35)
	confirm_btn.visible = false
	confirm_btn.pressed.connect(_on_confirm_alpha_pressed)
	button_row.add_child(confirm_btn)

	main_container.add_child(button_row)

	add_child(main_container)

func _show_alpha_selection() -> void:
	selected_alpha_targets.clear()
	step_label.text = "Step 1: Select %d Alpha Target(s)" % required_alpha_count
	step_label.add_theme_color_override("font_color", Color.CYAN)
	info_label.text = "Selected: 0 / %d" % required_alpha_count
	back_btn.visible = false
	confirm_btn.visible = false

	# Handle edge case: no alpha targets needed (all units become... nothing needed)
	if required_alpha_count == 0:
		# Skip straight to gamma
		_show_gamma_selection()
		return

	_populate_alpha_list()

func _populate_alpha_list() -> void:
	# Clear existing
	for child in unit_list_container.get_children():
		unit_list_container.remove_child(child)
		child.queue_free()

	if opponent_units.is_empty():
		var no_units = Label.new()
		no_units.text = "No eligible units available."
		no_units.add_theme_color_override("font_color", Color.RED)
		unit_list_container.add_child(no_units)
		return

	for unit_data in opponent_units:
		var unit_id = unit_data.get("unit_id", "")
		var unit_name = unit_data.get("unit_name", unit_id)
		var is_selected = unit_id in selected_alpha_targets

		var btn = Button.new()
		btn.name = "AlphaBtn_%s" % unit_id
		if is_selected:
			btn.text = "[X] %s" % unit_name
			btn.add_theme_color_override("font_color", Color.YELLOW)
		else:
			btn.text = "[ ] %s" % unit_name
		btn.custom_minimum_size = Vector2(460, 35)
		btn.pressed.connect(_on_alpha_unit_toggled.bind(unit_id))
		unit_list_container.add_child(btn)

func _on_alpha_unit_toggled(unit_id: String) -> void:
	if unit_id in selected_alpha_targets:
		selected_alpha_targets.erase(unit_id)
	else:
		if selected_alpha_targets.size() < required_alpha_count:
			selected_alpha_targets.append(unit_id)
		else:
			# Already at max, ignore (or could swap)
			return

	info_label.text = "Selected: %d / %d" % [selected_alpha_targets.size(), required_alpha_count]

	# Show confirm button when enough targets selected
	confirm_btn.visible = selected_alpha_targets.size() == required_alpha_count

	# Refresh list to update checkmarks
	_populate_alpha_list()

	print("MarkedForDeathDialog: Alpha targets selected: %s" % str(selected_alpha_targets))

func _on_confirm_alpha_pressed() -> void:
	print("MarkedForDeathDialog: Alpha targets confirmed: %s" % str(selected_alpha_targets))

	# Check if we need a gamma target
	var remaining_units = []
	for unit_data in opponent_units:
		if unit_data.get("unit_id", "") not in selected_alpha_targets:
			remaining_units.append(unit_data)

	if remaining_units.is_empty():
		# No remaining units for gamma — resolve with empty gamma
		print("MarkedForDeathDialog: No remaining units for gamma target, resolving without gamma")
		_resolve("")
		return

	_show_gamma_selection()

func _show_gamma_selection() -> void:
	step_label.text = "Step 2: Select 1 Gamma Target"
	step_label.add_theme_color_override("font_color", Color.YELLOW)
	info_label.text = "Click a unit to designate as Gamma target"
	back_btn.visible = true
	confirm_btn.visible = false

	# Clear and populate with remaining units
	for child in unit_list_container.get_children():
		unit_list_container.remove_child(child)
		child.queue_free()

	var remaining_units = []
	for unit_data in opponent_units:
		if unit_data.get("unit_id", "") not in selected_alpha_targets:
			remaining_units.append(unit_data)

	if remaining_units.is_empty():
		var no_units = Label.new()
		no_units.text = "No remaining units for Gamma target."
		no_units.add_theme_color_override("font_color", Color.RED)
		unit_list_container.add_child(no_units)
		return

	for unit_data in remaining_units:
		var unit_id = unit_data.get("unit_id", "")
		var unit_name = unit_data.get("unit_name", unit_id)

		var btn = Button.new()
		btn.text = unit_name
		btn.custom_minimum_size = Vector2(460, 35)
		btn.pressed.connect(_on_gamma_unit_selected.bind(unit_id))
		unit_list_container.add_child(btn)

func _on_gamma_unit_selected(unit_id: String) -> void:
	selected_gamma_target = unit_id
	print("MarkedForDeathDialog: Gamma target selected: %s" % unit_id)
	_resolve(unit_id)

func _on_back_pressed() -> void:
	# Go back to alpha selection
	_show_alpha_selection()

func _resolve(gamma_target: String) -> void:
	print("MarkedForDeathDialog: Resolved — Alpha: %s, Gamma: %s" % [str(selected_alpha_targets), gamma_target])
	emit_signal("marked_for_death_resolved", selected_alpha_targets.duplicate(), gamma_target)
	hide()
	queue_free()
