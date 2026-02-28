extends AcceptDialog

# FiringDeckDialog - Modal dialog for selecting which embarked models shoot through transport's firing deck
# Allows selection of up to X models based on transport's firing deck capacity

signal models_selected(selected_weapons: Array)

var transport_id: String
var transport_name: String = ""
var firing_deck_capacity: int = 0
var embarked_unit_ids: Array = []
var available_weapons: Array = []  # Array of {unit_id, unit_name, model_idx, weapon_name}
var selected_weapons: Array = []
var checkboxes: Dictionary = {}

# UI Nodes
var vbox: VBoxContainer
var capacity_label: Label
var weapons_container: VBoxContainer

func _ready() -> void:
	# Set dialog properties
	title = "Select Firing Deck Models"
	min_size = DialogConstants.MEDIUM
	dialog_hide_on_ok = false
	get_ok_button().text = "Confirm Selection"
	get_ok_button().pressed.connect(_on_confirm_pressed)

	# Create main container
	vbox = VBoxContainer.new()
	vbox.set_custom_minimum_size(Vector2(DialogConstants.MEDIUM.x - 20, 0))
	add_child(vbox)

	# Create capacity label
	capacity_label = Label.new()
	vbox.add_child(capacity_label)

	# Add separator
	var separator = HSeparator.new()
	vbox.add_child(separator)

	# Instructions
	var instructions = Label.new()
	instructions.text = "Select which embarked models will shoot through the transport's firing deck:"
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(instructions)

	# Create scrollable container for weapons
	var scroll = ScrollContainer.new()
	scroll.set_custom_minimum_size(Vector2(DialogConstants.MEDIUM.x - 20, 250))
	vbox.add_child(scroll)

	weapons_container = VBoxContainer.new()
	scroll.add_child(weapons_container)

	print("FiringDeckDialog initialized")

func setup(p_transport_id: String, p_embarked_unit_ids: Array, p_firing_deck_capacity: int) -> void:
	transport_id = p_transport_id
	embarked_unit_ids = p_embarked_unit_ids
	firing_deck_capacity = p_firing_deck_capacity

	var transport = GameState.get_unit(transport_id)
	if transport:
		transport_name = transport.meta.get("name", transport_id)
		title = "Firing Deck - %s" % transport_name

	# Populate available weapons from embarked units
	_populate_available_weapons()

	# Update UI
	_update_capacity_label()
	_create_weapon_checkboxes()

func _populate_available_weapons() -> void:
	available_weapons.clear()

	for unit_id in embarked_unit_ids:
		var unit = GameState.get_unit(unit_id)
		if not unit:
			continue

		# Skip if unit has already shot
		if unit.get("flags", {}).get("has_shot", false):
			continue

		var unit_name = unit.meta.get("name", unit_id)

		# Get weapons for this unit from RulesEngine
		var weapon_profiles = RulesEngine.get_unit_weapon_profiles(unit_id)

		# For each model in the unit
		for model_idx in range(unit.models.size()):
			var model = unit.models[model_idx]
			if not model.alive:
				continue

			# Add each weapon the model can use
			for weapon_name in weapon_profiles:
				available_weapons.append({
					"unit_id": unit_id,
					"unit_name": unit_name,
					"model_idx": model_idx,
					"model_id": model.id,
					"weapon_name": weapon_name,
					"weapon_profile": weapon_profiles[weapon_name]
				})

func _create_weapon_checkboxes() -> void:
	# Clear existing checkboxes
	for child in weapons_container.get_children():
		child.queue_free()
	checkboxes.clear()
	selected_weapons.clear()

	if available_weapons.is_empty():
		var no_weapons_label = Label.new()
		no_weapons_label.text = "No eligible models available for firing deck"
		no_weapons_label.text += "\n(All embarked units have already shot)"
		weapons_container.add_child(no_weapons_label)
		get_ok_button().disabled = true
		return

	# Group weapons by unit for better organization
	var weapons_by_unit = {}
	for weapon_data in available_weapons:
		var unit_id = weapon_data.unit_id
		if not weapons_by_unit.has(unit_id):
			weapons_by_unit[unit_id] = []
		weapons_by_unit[unit_id].append(weapon_data)

	# Create checkboxes organized by unit
	for unit_id in weapons_by_unit:
		var unit_weapons = weapons_by_unit[unit_id]
		if unit_weapons.is_empty():
			continue

		# Unit header
		var unit_header = Label.new()
		unit_header.text = "\n%s:" % unit_weapons[0].unit_name
		unit_header.add_theme_font_size_override("font_size", 14)
		unit_header.add_theme_color_override("font_color", Color(0.8, 0.8, 1.0))
		weapons_container.add_child(unit_header)

		# Create checkbox for each weapon
		for weapon_data in unit_weapons:
			var hbox = HBoxContainer.new()

			var checkbox = CheckBox.new()
			var weapon_profile = weapon_data.weapon_profile
			var weapon_text = "Model %s - %s" % [weapon_data.model_id, weapon_data.weapon_name]

			# Add weapon stats if available
			if weapon_profile:
				weapon_text += " (R:%s\" A:%s BS:%s+ S:%s AP:%s D:%s)" % [
					weapon_profile.get("range", "?"),
					weapon_profile.get("attacks", "?"),
					weapon_profile.get("ballistic_skill", "?"),
					weapon_profile.get("strength", "?"),
					weapon_profile.get("ap", "0"),
					weapon_profile.get("damage", "1")
				]

			checkbox.text = weapon_text
			checkbox.toggled.connect(_on_weapon_toggled.bind(weapon_data))

			var checkbox_id = "%s_%d_%s" % [unit_id, weapon_data.model_idx, weapon_data.weapon_name]
			checkboxes[checkbox_id] = checkbox
			hbox.add_child(checkbox)

			weapons_container.add_child(hbox)

func _on_weapon_toggled(pressed: bool, weapon_data: Dictionary) -> void:
	if pressed:
		# Check capacity
		if selected_weapons.size() >= firing_deck_capacity:
			# Revert the toggle
			var checkbox_id = "%s_%d_%s" % [weapon_data.unit_id, weapon_data.model_idx, weapon_data.weapon_name]
			checkboxes[checkbox_id].set_pressed_no_signal(false)

			# Show warning
			var warning_dialog = AcceptDialog.new()
			warning_dialog.title = "Firing Deck Capacity"
			warning_dialog.dialog_text = "Maximum firing deck capacity reached.\nOnly %d models can shoot through the firing deck." % firing_deck_capacity
			get_tree().root.add_child(warning_dialog)
			warning_dialog.popup_centered()
			warning_dialog.confirmed.connect(func(): warning_dialog.queue_free())
			return

		selected_weapons.append(weapon_data)
	else:
		# Remove from selected
		for i in range(selected_weapons.size() - 1, -1, -1):
			var selected = selected_weapons[i]
			if selected.unit_id == weapon_data.unit_id and \
			   selected.model_idx == weapon_data.model_idx and \
			   selected.weapon_name == weapon_data.weapon_name:
				selected_weapons.remove_at(i)
				break

	_update_capacity_label()

func _update_capacity_label() -> void:
	capacity_label.text = "Firing Deck Capacity: %d / %d models selected" % [selected_weapons.size(), firing_deck_capacity]

	# Color code based on selection
	if selected_weapons.size() == 0:
		capacity_label.modulate = Color.WHITE
	elif selected_weapons.size() < firing_deck_capacity:
		capacity_label.modulate = Color.GREEN
	elif selected_weapons.size() == firing_deck_capacity:
		capacity_label.modulate = Color.YELLOW
	else:
		capacity_label.modulate = Color.RED

func _on_confirm_pressed() -> void:
	if selected_weapons.size() == 0:
		# Show warning
		var warning_dialog = AcceptDialog.new()
		warning_dialog.title = "No Selection"
		warning_dialog.dialog_text = "Please select at least one model to shoot through the firing deck."
		get_tree().root.add_child(warning_dialog)
		warning_dialog.popup_centered()
		warning_dialog.confirmed.connect(func(): warning_dialog.queue_free())
		return

	emit_signal("models_selected", selected_weapons)
	hide()
	queue_free()