extends AcceptDialog
class_name MarkedForDeathDialog

# MarkedForDeathDialog - Two-step unit selection for Marked for Death secondary mission
#
# Per Chapter Approved 2025-26 rules:
# Step 1: The OPPONENT (non-card-holder) selects 3 Alpha targets from their own units
# Step 2: The CARD HOLDER (player who drew) selects 1 Gamma target from opponent's remaining units
#
# Fallback: If opponent has fewer than 3 units, adjust selections accordingly

signal marked_for_death_resolved(alpha_targets: Array, gamma_target: String)

var opponent_units: Array = []  # Array of { unit_id, unit_name }
var selected_alpha_targets: Array = []  # Array of unit_id strings
var selected_gamma_target: String = ""
var required_alpha_count: int = 2
var opponent_player: int = 0
var drawing_player: int = 0  # The player who drew the card (card holder)
var _gamma_only_mode: bool = false  # True when alpha targets were pre-selected by AI

# UI references
var step_label: Label
var player_indicator: Label
var unit_list_container: VBoxContainer
var info_label: Label
var confirm_btn: Button
var back_btn: Button
var flavour_label: Label

func setup(drawing: int, opponent: int, units: Array, details: Dictionary) -> void:
	drawing_player = drawing
	opponent_player = opponent
	opponent_units = units
	required_alpha_count = details.get("alpha_targets", 2)
	var fallback = details.get("fallback_if_fewer", true)

	# Fallback: if fewer units than required alpha + gamma, adjust
	if fallback and opponent_units.size() < required_alpha_count + 1:
		required_alpha_count = max(0, opponent_units.size() - 1)

	title = "Marked for Death"
	get_ok_button().visible = false

	_build_ui()
	_show_alpha_selection()

func setup_gamma_only(drawing: int, opponent: int, units: Array, pre_selected_alphas: Array) -> void:
	"""Setup dialog with pre-selected alpha targets (chosen by AI opponent).
	Skips straight to gamma selection for the human card holder."""
	drawing_player = drawing
	opponent_player = opponent
	opponent_units = units
	selected_alpha_targets = pre_selected_alphas.duplicate()
	required_alpha_count = pre_selected_alphas.size()
	_gamma_only_mode = true

	title = "Marked for Death"
	get_ok_button().visible = false

	_build_ui()
	# Skip alpha selection — go straight to gamma
	_show_gamma_selection()

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

	# Player indicator — shows which player should be selecting
	player_indicator = Label.new()
	player_indicator.add_theme_font_size_override("font_size", 14)
	player_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(player_indicator)

	# Flavour text
	flavour_label = Label.new()
	flavour_label.add_theme_font_size_override("font_size", 12)
	flavour_label.add_theme_color_override("font_color", Color.GRAY)
	flavour_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavour_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(flavour_label)

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

	# Step 1 is for the OPPONENT — they pick Alpha targets from their own units
	player_indicator.text = "Player %d (Opponent) — Select Alpha Targets" % opponent_player
	player_indicator.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	flavour_label.text = "Player %d has drawn Marked for Death.\nPlayer %d: select %d of your units as Alpha targets (5 VP each if destroyed)." % [
		drawing_player, opponent_player, required_alpha_count]

	# Handle edge case: no alpha targets needed
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
			btn.text = "[ALPHA] %s" % unit_name
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
			# Already at max, ignore
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
	# Step 2 is for the CARD HOLDER — they pick the Gamma target
	step_label.text = "Select 1 Gamma Target"
	step_label.add_theme_color_override("font_color", Color.YELLOW)
	player_indicator.text = "Player %d (Card Holder) — Select Gamma Target" % drawing_player
	player_indicator.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))

	# Build alpha target names for display
	var alpha_names = []
	for unit_data in opponent_units:
		if unit_data.get("unit_id", "") in selected_alpha_targets:
			alpha_names.append(unit_data.get("unit_name", unit_data.get("unit_id", "")))
	var alpha_display = ", ".join(alpha_names) if not alpha_names.is_empty() else "None"

	flavour_label.text = "Alpha targets: %s\nSelect 1 remaining opponent unit as the Gamma target (2 VP if destroyed, when no Alpha destroyed)." % alpha_display
	info_label.text = "Click a unit to designate as Gamma target"
	# Only show back button if alpha selection was manual (not pre-selected by AI)
	back_btn.visible = required_alpha_count > 0 and not _gamma_only_mode
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
