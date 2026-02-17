extends AcceptDialog
class_name GrenadeTargetDialog

# GrenadeTargetDialog - UI for the GRENADE stratagem
#
# Two-step selection process:
# 1. Select which friendly GRENADES unit throws the grenade
# 2. Select which enemy unit within 8" is the target
#
# After selection, displays dice roll results (6D6, 4+ = mortal wound)

signal grenade_confirmed(grenade_unit_id: String, target_unit_id: String)
signal grenade_cancelled()

var eligible_units: Array = []  # Array of { unit_id, unit_name }
var eligible_targets: Array = []  # Array of { unit_id, unit_name, model_count }
var selected_grenade_unit_id: String = ""
var selected_target_unit_id: String = ""
var player: int = 0

# UI references
var unit_list_container: VBoxContainer
var target_list_container: VBoxContainer
var step_label: Label
var cp_label: Label
var confirm_btn: Button
var back_btn: Button

func setup(active_player: int, units: Array) -> void:
	player = active_player
	eligible_units = units

	title = "GRENADE Stratagem (1 CP)"
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(500, 350)

	# Header
	var header = Label.new()
	header.text = "GRENADE"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.ORANGE)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	# Type label
	var type_label = Label.new()
	type_label.text = "Core – Wargear Stratagem (1 CP)"
	type_label.add_theme_font_size_override("font_size", 12)
	type_label.add_theme_color_override("font_color", Color.GRAY)
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(type_label)

	# CP display
	cp_label = Label.new()
	cp_label.text = "CP Available: %d" % StratagemManager.get_player_cp(player)
	cp_label.add_theme_font_size_override("font_size", 14)
	cp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(cp_label)

	# Description
	var desc = Label.new()
	desc.text = "Select a GRENADES unit, then an enemy within 8\". Roll 6D6: each 4+ = 1 mortal wound."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	main_container.add_child(desc)

	main_container.add_child(HSeparator.new())

	# Step indicator
	step_label = Label.new()
	step_label.text = "Step 1: Select GRENADES unit"
	step_label.add_theme_font_size_override("font_size", 14)
	step_label.add_theme_color_override("font_color", Color.CYAN)
	main_container.add_child(step_label)

	# Scroll container for lists
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 180)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Unit list container (shown in step 1)
	unit_list_container = VBoxContainer.new()
	unit_list_container.name = "UnitListContainer"
	_populate_unit_list()

	# Target list container (shown in step 2, initially hidden)
	target_list_container = VBoxContainer.new()
	target_list_container.name = "TargetListContainer"
	target_list_container.visible = false

	var content = VBoxContainer.new()
	content.add_child(unit_list_container)
	content.add_child(target_list_container)
	scroll.add_child(content)
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

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 35)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	button_row.add_child(cancel_btn)

	main_container.add_child(button_row)

	add_child(main_container)

func _populate_unit_list() -> void:
	# Clear existing
	for child in unit_list_container.get_children():
		unit_list_container.remove_child(child)
		child.queue_free()

	if eligible_units.is_empty():
		var no_units = Label.new()
		no_units.text = "No eligible GRENADES units available."
		no_units.add_theme_color_override("font_color", Color.RED)
		unit_list_container.add_child(no_units)
		return

	for unit_data in eligible_units:
		var unit_id = unit_data.get("unit_id", "")
		var unit_name = unit_data.get("unit_name", unit_id)

		var btn = Button.new()
		btn.text = unit_name
		btn.custom_minimum_size = Vector2(460, 35)
		btn.pressed.connect(_on_grenade_unit_selected.bind(unit_id))
		unit_list_container.add_child(btn)

func _on_grenade_unit_selected(unit_id: String) -> void:
	selected_grenade_unit_id = unit_id
	print("GrenadeTargetDialog: Selected grenade unit: %s" % unit_id)

	# Get eligible targets within 8" of this unit
	var board = GameState.create_snapshot()
	eligible_targets = RulesEngine.get_grenade_eligible_targets(unit_id, board)

	if eligible_targets.is_empty():
		# No valid targets - show message
		step_label.text = "No enemy units within 8\" of this unit!"
		step_label.add_theme_color_override("font_color", Color.RED)
		back_btn.visible = true
		unit_list_container.visible = false
		target_list_container.visible = false
		return

	# Switch to step 2
	_show_target_selection()

func _show_target_selection() -> void:
	step_label.text = "Step 2: Select enemy target (within 8\")"
	step_label.add_theme_color_override("font_color", Color.YELLOW)
	back_btn.visible = true
	unit_list_container.visible = false
	target_list_container.visible = true

	# Clear and populate targets
	for child in target_list_container.get_children():
		target_list_container.remove_child(child)
		child.queue_free()

	var grenade_unit = GameState.get_unit(selected_grenade_unit_id)
	var grenade_name = grenade_unit.get("meta", {}).get("name", selected_grenade_unit_id)

	var info = Label.new()
	info.text = "Throwing with: %s" % grenade_name
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", Color.LIGHT_GREEN)
	target_list_container.add_child(info)

	for target_data in eligible_targets:
		var target_id = target_data.get("unit_id", "")
		var target_name = target_data.get("unit_name", target_id)
		var model_count = target_data.get("model_count", 0)

		var btn = Button.new()
		btn.text = "%s (%d models)" % [target_name, model_count]
		btn.custom_minimum_size = Vector2(460, 35)
		btn.pressed.connect(_on_target_selected.bind(target_id))
		target_list_container.add_child(btn)

func _on_target_selected(target_id: String) -> void:
	selected_target_unit_id = target_id
	print("GrenadeTargetDialog: Selected target: %s" % target_id)

	emit_signal("grenade_confirmed", selected_grenade_unit_id, selected_target_unit_id)
	hide()
	queue_free()

func _on_back_pressed() -> void:
	# Go back to step 1
	selected_grenade_unit_id = ""
	step_label.text = "Step 1: Select GRENADES unit"
	step_label.add_theme_color_override("font_color", Color.CYAN)
	back_btn.visible = false
	unit_list_container.visible = true
	target_list_container.visible = false

func _on_cancel_pressed() -> void:
	print("GrenadeTargetDialog: Cancelled")
	emit_signal("grenade_cancelled")
	hide()
	queue_free()
