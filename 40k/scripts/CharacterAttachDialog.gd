extends AcceptDialog
const GameStateData = preload("res://autoloads/GameState.gd")

# CharacterAttachDialog - Modal dialog for attaching CHARACTER leaders during deployment
# Mirrors TransportEmbarkDialog pattern

signal characters_selected(character_ids: Array)

var bodyguard_id: String
var bodyguard_name: String = ""
var available_characters: Array = []
var selected_characters: Array = []
var checkboxes: Dictionary = {}

# UI Nodes
var vbox: VBoxContainer
var info_label: Label
var unit_container: VBoxContainer

func _ready() -> void:
	# Set dialog properties
	title = "Attach Leader"
	dialog_hide_on_ok = false
	get_ok_button().text = "Attach Leader"
	get_ok_button().pressed.connect(_on_confirm_pressed)

	# Add "Skip" button
	var cancel_button = add_cancel_button("Deploy Without Leader")
	canceled.connect(_on_skip_pressed)

	# Create main container
	vbox = VBoxContainer.new()
	vbox.set_custom_minimum_size(Vector2(400, 250))
	add_child(vbox)

	# Create info label
	info_label = Label.new()
	vbox.add_child(info_label)

	# Add separator
	var separator = HSeparator.new()
	vbox.add_child(separator)

	# Create scrollable container for characters
	var scroll = ScrollContainer.new()
	scroll.set_custom_minimum_size(Vector2(380, 150))
	vbox.add_child(scroll)

	unit_container = VBoxContainer.new()
	scroll.add_child(unit_container)

	print("CharacterAttachDialog initialized")

func setup(p_bodyguard_id: String) -> void:
	bodyguard_id = p_bodyguard_id
	var bodyguard = GameState.get_unit(bodyguard_id)

	DebugLogger.info("CharacterAttachDialog.setup called", {
		"bodyguard_id": bodyguard_id,
		"bodyguard_exists": not bodyguard.is_empty()
	})

	if bodyguard.is_empty():
		print("ERROR: Invalid bodyguard unit: ", bodyguard_id)
		queue_free()
		return

	bodyguard_name = bodyguard.get("meta", {}).get("name", bodyguard_id)
	title = "Attach Leader to %s?" % bodyguard_name

	# Ensure UI is ready before updating
	if not is_node_ready():
		await ready

	# Get available character units
	var player = bodyguard.get("owner", 0)
	available_characters = CharacterAttachmentManager.get_attachable_characters(bodyguard_id, player)

	DebugLogger.info("Available characters for attachment", {
		"bodyguard_id": bodyguard_id,
		"player": player,
		"available_count": available_characters.size()
	})

	# Update info label
	if info_label:
		info_label.text = "Select a CHARACTER leader to attach to %s.\nThe leader will join this unit and be protected by bodyguard models." % bodyguard_name

	# Create checkboxes for each available character
	_create_character_checkboxes()

func _create_character_checkboxes() -> void:
	# Clear existing checkboxes
	for child in unit_container.get_children():
		child.queue_free()
	checkboxes.clear()
	selected_characters.clear()

	if available_characters.is_empty():
		var no_chars_label = Label.new()
		no_chars_label.text = "No eligible CHARACTER leaders available"
		unit_container.add_child(no_chars_label)
		return

	for char_unit in available_characters:
		var hbox = HBoxContainer.new()

		var checkbox = CheckBox.new()
		var char_name = char_unit.get("meta", {}).get("name", char_unit.get("id", "Unknown"))
		var char_wounds = char_unit.get("meta", {}).get("stats", {}).get("wounds", 1)
		var weapon_names = []
		for weapon in char_unit.get("meta", {}).get("weapons", []):
			weapon_names.append(weapon.get("name", "Unknown"))
		var weapons_str = ", ".join(weapon_names) if not weapon_names.is_empty() else "No weapons"

		checkbox.text = "%s (W%d | %s)" % [char_name, char_wounds, weapons_str]
		checkbox.toggled.connect(_on_character_toggled.bind(char_unit.get("id", "")))

		checkboxes[char_unit.get("id", "")] = checkbox
		hbox.add_child(checkbox)

		unit_container.add_child(hbox)

func _on_character_toggled(pressed: bool, character_id: String) -> void:
	if pressed:
		# Only allow one character attachment (deselect others)
		for other_id in checkboxes:
			if other_id != character_id and checkboxes[other_id].button_pressed:
				checkboxes[other_id].set_pressed_no_signal(false)
				selected_characters.erase(other_id)

		selected_characters.append(character_id)
	else:
		selected_characters.erase(character_id)

func _on_confirm_pressed() -> void:
	DebugLogger.info("Character attachment confirmed", {
		"bodyguard_id": bodyguard_id,
		"selected_characters": selected_characters,
		"count": selected_characters.size()
	})
	emit_signal("characters_selected", selected_characters)
	hide()
	queue_free()

func _on_skip_pressed() -> void:
	DebugLogger.info("User skipped character attachment", {
		"bodyguard_id": bodyguard_id
	})
	emit_signal("characters_selected", [])
	hide()
	queue_free()
