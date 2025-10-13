extends AcceptDialog

# NextWeaponDialog - Shown to attacker to confirm continuing to next weapon in sequential mode
# Allows optional reordering of remaining weapons

signal continue_confirmed(weapon_order: Array)

var remaining_weapons: Array = []
var current_index: int = 0
var weapon_list: ItemList

func _ready() -> void:
	title = "Next Weapon"
	dialog_text = "Weapon resolved! Continue to next weapon?"

	# Create weapon list display
	var content_container = VBoxContainer.new()

	var label = Label.new()
	label.text = "Remaining weapons:"
	content_container.add_child(label)

	weapon_list = ItemList.new()
	weapon_list.custom_minimum_size = Vector2(300, 150)
	content_container.add_child(weapon_list)

	var hint_label = Label.new()
	hint_label.text = "(Reordering not yet implemented - weapons will fire in order shown)"
	hint_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	content_container.add_child(hint_label)

	add_child(content_container)

	# Configure dialog buttons
	get_ok_button().text = "Continue"
	get_ok_button().pressed.connect(_on_continue_pressed)

	# Make dialog modal and exclusive
	exclusive = true
	popup_window = true

func setup(weapons: Array, index: int) -> void:
	remaining_weapons = weapons
	current_index = index

	_populate_weapon_list()

func _populate_weapon_list() -> void:
	if not weapon_list:
		return

	weapon_list.clear()

	for i in range(remaining_weapons.size()):
		var weapon_assignment = remaining_weapons[i]
		var weapon_id = weapon_assignment.get("weapon_id", "")
		var weapon_profile = RulesEngine.get_weapon_profile(weapon_id)
		var weapon_name = weapon_profile.get("name", weapon_id)

		weapon_list.add_item("%d. %s" % [i + 1, weapon_name])
		weapon_list.set_item_metadata(i, weapon_assignment)

func _on_continue_pressed() -> void:
	print("NextWeaponDialog: Continue pressed")

	# For now, just return the weapons in current order
	# TODO: Add drag-and-drop reordering functionality
	emit_signal("continue_confirmed", remaining_weapons)

	hide()
	queue_free()
