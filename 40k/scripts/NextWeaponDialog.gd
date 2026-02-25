extends AcceptDialog

const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")

# NextWeaponDialog - Enhanced to show last weapon's results before continuing
# Displays attack summary, dice details, and remaining weapons

signal continue_confirmed(weapon_order: Array, fast_roll: bool)
signal shooting_complete_confirmed  # NEW: Signals shooting is complete (no more weapons)

var remaining_weapons: Array = []
var current_index: int = 0
var last_weapon_result: Dictionary = {}

# UI Elements
var main_vbox: VBoxContainer
var weapon_name_label: Label
var attack_summary_panel: PanelContainer
var summary_grid: GridContainer
var dice_details_button: Button
var dice_details_panel: PanelContainer
var dice_details_log: RichTextLabel
var remaining_weapons_list: ItemList
var continue_button: Button

func _ready() -> void:
	title = "Weapon Resolution Complete"
	dialog_hide_on_ok = false
	min_size = Vector2(600, 500)

	# CRITICAL: Don't hide OK button - we'll repurpose it
	# AcceptDialog needs at least one button to work properly
	get_ok_button().text = "Continue to Next Weapon"
	get_ok_button().custom_minimum_size = Vector2(300, 50)

	# Connect the OK button to our handler
	if not get_ok_button().pressed.is_connected(_on_continue_pressed):
		get_ok_button().pressed.connect(_on_continue_pressed)

	_create_ui()

func _create_ui() -> void:
	main_vbox = VBoxContainer.new()
	main_vbox.custom_minimum_size = Vector2(580, 480)
	add_child(main_vbox)

	# Last weapon header
	weapon_name_label = Label.new()
	weapon_name_label.add_theme_font_size_override("font_size", 16)
	weapon_name_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	weapon_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(weapon_name_label)

	main_vbox.add_child(HSeparator.new())

	# Attack Summary Section
	var summary_label = Label.new()
	summary_label.text = "ATTACK SUMMARY"
	summary_label.add_theme_font_size_override("font_size", 14)
	main_vbox.add_child(summary_label)

	attack_summary_panel = PanelContainer.new()
	attack_summary_panel.custom_minimum_size = Vector2(560, 120)
	main_vbox.add_child(attack_summary_panel)

	summary_grid = GridContainer.new()
	summary_grid.columns = 2
	attack_summary_panel.add_child(summary_grid)

	# Dice Details Toggle
	dice_details_button = Button.new()
	dice_details_button.text = "▼ Show Detailed Dice Rolls"
	dice_details_button.flat = true
	dice_details_button.pressed.connect(_on_toggle_dice_details)
	_WhiteDwarfTheme.apply_to_button(dice_details_button)
	main_vbox.add_child(dice_details_button)

	# Dice Details Panel (collapsible)
	dice_details_panel = PanelContainer.new()
	dice_details_panel.visible = false
	dice_details_panel.custom_minimum_size = Vector2(560, 100)
	main_vbox.add_child(dice_details_panel)

	dice_details_log = RichTextLabel.new()
	dice_details_log.bbcode_enabled = true
	dice_details_log.fit_content = true
	dice_details_panel.add_child(dice_details_log)

	main_vbox.add_child(HSeparator.new())

	# Remaining Weapons Section
	var remaining_label = Label.new()
	remaining_label.text = "Remaining Weapons:"
	remaining_label.add_theme_font_size_override("font_size", 14)
	main_vbox.add_child(remaining_label)

	remaining_weapons_list = ItemList.new()
	remaining_weapons_list.custom_minimum_size = Vector2(560, 100)
	main_vbox.add_child(remaining_weapons_list)

	# Note: Continue button is the built-in OK button, configured in _ready()

func setup(weapons: Array, index: int, last_result: Dictionary) -> void:
	remaining_weapons = weapons
	current_index = index
	last_weapon_result = last_result

	_populate_last_weapon_summary()
	_populate_remaining_weapons()

func _populate_last_weapon_summary() -> void:
	if last_weapon_result.is_empty():
		weapon_name_label.text = "No weapon data available"
		return

	var weapon_name = last_weapon_result.get("weapon_name", "Unknown")
	var target_name = last_weapon_result.get("target_unit_name", "Unknown")
	weapon_name_label.text = "Last Weapon: %s → %s" % [weapon_name, target_name]

	# Check if weapon was skipped
	if last_weapon_result.get("skipped", false):
		var skip_reason = last_weapon_result.get("skip_reason", "Unknown reason")
		_show_skipped_message(skip_reason)
		return

	# Clear summary grid
	for child in summary_grid.get_children():
		summary_grid.remove_child(child)
		child.queue_free()

	var hits = last_weapon_result.get("hits", 0)
	var total_attacks = last_weapon_result.get("total_attacks", 0)
	var wounds = last_weapon_result.get("wounds", 0)
	var saves_failed = last_weapon_result.get("saves_failed", 0)
	var casualties = last_weapon_result.get("casualties", 0)

	# Hit Rolls Row
	_add_summary_row("🎲 Hit Rolls:", "%d hits / %d shots" % [hits, total_attacks],
		Color.GREEN if hits > 0 else Color.RED)

	# Wound Rolls Row (only if hits > 0)
	if hits > 0:
		_add_summary_row("🎯 Wound Rolls:", "%d wounds / %d hits" % [wounds, hits],
			Color.GREEN if wounds > 0 else Color.YELLOW)

	# Saves Row (only if wounds > 0)
	if wounds > 0:
		_add_summary_row("🛡️ Saves:", "%d failed / %d wounds" % [saves_failed, wounds],
			Color.ORANGE if saves_failed > 0 else Color.GREEN)

	# Casualties Row
	_add_summary_row("☠️  Casualties:", "%d destroyed" % casualties,
		Color.RED if casualties > 0 else Color.GRAY)

	# Populate dice details
	_populate_dice_details()

func _add_summary_row(label_text: String, value_text: String, color: Color) -> void:
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 14)
	summary_grid.add_child(label)

	var value = Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 14)
	value.add_theme_color_override("font_color", color)
	summary_grid.add_child(value)

func _show_skipped_message(reason: String) -> void:
	# Clear summary grid
	for child in summary_grid.get_children():
		summary_grid.remove_child(child)
		child.queue_free()

	var message = Label.new()
	message.text = "⚠️ Weapon Skipped: %s" % reason
	message.add_theme_font_size_override("font_size", 14)
	message.add_theme_color_override("font_color", Color.YELLOW)
	summary_grid.add_child(message)

	# Hide dice details for skipped weapons
	dice_details_button.visible = false

func _populate_dice_details() -> void:
	if not dice_details_log:
		return

	dice_details_log.clear()

	var dice_rolls = last_weapon_result.get("dice_rolls", [])
	if dice_rolls.is_empty():
		dice_details_log.add_text("No dice roll data available")
		return

	for dice_block in dice_rolls:
		var context = dice_block.get("context", "Unknown")
		var rolls_raw = dice_block.get("rolls_raw", [])
		var rolls_modified = dice_block.get("rolls_modified", [])
		var successes = dice_block.get("successes", 0)
		var threshold = dice_block.get("threshold", "")
		var rerolls = dice_block.get("rerolls", [])

		# Format context name
		var display_context = context.capitalize().replace("_", " ")
		dice_details_log.append_text("[b]%s[/b] (need %s):\n" % [display_context, threshold])

		# Show rerolls if any
		if not rerolls.is_empty():
			dice_details_log.append_text("  [color=yellow]Re-rolled:[/color] ")
			for reroll in rerolls:
				dice_details_log.append_text("[s]%d[/s]→%d " % [reroll.original, reroll.rerolled_to])
			dice_details_log.append_text("\n")

		# Show rolls
		var display_rolls = rolls_modified if not rolls_modified.is_empty() else rolls_raw
		dice_details_log.append_text("  Rolls: %s\n" % str(display_rolls))
		dice_details_log.append_text("  → [b][color=green]%d successes[/color][/b]\n\n" % successes)

func _populate_remaining_weapons() -> void:
	if not remaining_weapons_list:
		return

	remaining_weapons_list.clear()

	if remaining_weapons.is_empty():
		remaining_weapons_list.add_item("No remaining weapons")
		get_ok_button().text = "Complete Shooting"
		return

	for i in range(remaining_weapons.size()):
		var weapon_assignment = remaining_weapons[i]
		var weapon_id = weapon_assignment.get("weapon_id", "")

		if weapon_id == "":
			push_error("NextWeaponDialog: Weapon at index %d has EMPTY weapon_id!" % i)
			continue

		var weapon_profile = RulesEngine.get_weapon_profile(weapon_id)
		var weapon_name = weapon_profile.get("name", weapon_id)
		var target_unit_id = weapon_assignment.get("target_unit_id", "")
		var target_unit = GameState.get_unit(target_unit_id)
		var target_name = target_unit.get("meta", {}).get("name", target_unit_id)

		remaining_weapons_list.add_item("%d. %s → %s" % [i + 1, weapon_name, target_name])
		remaining_weapons_list.set_item_metadata(i, weapon_assignment)

func _on_toggle_dice_details() -> void:
	dice_details_panel.visible = not dice_details_panel.visible
	if dice_details_panel.visible:
		dice_details_button.text = "▲ Hide Detailed Dice Rolls"
	else:
		dice_details_button.text = "▼ Show Detailed Dice Rolls"

func _on_continue_pressed() -> void:
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ NEXT WEAPON DIALOG: CONTINUE PRESSED")
	print("║ remaining_weapons.size(): ", remaining_weapons.size())
	print("║ current_index: ", current_index)

	if remaining_weapons.is_empty():
		# No weapons remaining - this is the completion case
		print("║ No remaining weapons - completing shooting")
		print("║ Emitting shooting_complete_confirmed signal")
		print("╚═══════════════════════════════════════════════════════════════")

		# Emit signal to complete shooting (ShootingController will handle)
		emit_signal("shooting_complete_confirmed")
		hide()
		queue_free()
	else:
		# More weapons remain - continue sequence
		print("║ %d weapons remaining - continuing sequence" % remaining_weapons.size())
		print("║ Emitting continue_confirmed signal with:")
		print("║   - remaining_weapons array (size %d)" % remaining_weapons.size())
		print("║   - fast_roll = false")
		for i in range(min(3, remaining_weapons.size())):
			var weapon = remaining_weapons[i]
			print("║   Weapon %d: %s" % [i, weapon.get("weapon_id", "UNKNOWN")])
		if remaining_weapons.size() > 3:
			print("║   ... and %d more weapons" % (remaining_weapons.size() - 3))
		print("╚═══════════════════════════════════════════════════════════════")

		# Emit with fast_roll = false to continue sequential mode
		emit_signal("continue_confirmed", remaining_weapons, false)
		hide()
		queue_free()
