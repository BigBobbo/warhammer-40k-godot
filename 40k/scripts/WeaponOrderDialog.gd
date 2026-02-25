extends AcceptDialog

const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")

# WeaponOrderDialog - Allows players to order weapons before shooting sequence
# Phase 1 MVP: Basic ordering with up/down arrows, fast roll option

signal weapon_order_confirmed(weapon_order: Array, fast_roll: bool)

# Weapon ordering data
var weapon_assignments: Array = []  # Original assignments from shooting phase
var weapon_order: Array = []  # Ordered list of weapon_ids
var weapon_data: Dictionary = {}  # weapon_id -> {name, count, damage, etc.}
var current_phase = null  # Reference to ShootingPhase for signal connections
var is_resolving: bool = false  # Track if sequence is currently resolving

# UI Nodes
var vbox: VBoxContainer
var instruction_label: Label
var weapon_list_container: VBoxContainer
var weapon_items: Array = []  # Array of weapon item panels for reordering
var button_hbox: HBoxContainer
var fast_roll_button: Button
var start_sequence_button: Button
var close_button: Button
var dice_log_rich_text: RichTextLabel

func _ready() -> void:
	# Set dialog properties
	title = "Choose Weapon Order"
	dialog_hide_on_ok = false

	# Set dialog size (increased to accommodate dice log)
	min_size = Vector2(500, 600)

	# Hide default OK button
	get_ok_button().hide()

	# Create main container
	vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(480, 580)
	add_child(vbox)

	# Instruction label
	instruction_label = Label.new()
	instruction_label.text = "Choose the order to resolve your weapons.\nHigher damage weapons are prioritized by default.\nUse arrows to reorder."
	instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(instruction_label)

	vbox.add_child(HSeparator.new())

	# Weapon list section
	var list_label = Label.new()
	list_label.text = "Weapon Firing Order:"
	list_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(list_label)

	var scroll_container = ScrollContainer.new()
	scroll_container.custom_minimum_size = Vector2(460, 220)
	vbox.add_child(scroll_container)

	weapon_list_container = VBoxContainer.new()
	weapon_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(weapon_list_container)

	vbox.add_child(HSeparator.new())

	# Action buttons
	button_hbox = HBoxContainer.new()
	button_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_hbox)

	fast_roll_button = Button.new()
	fast_roll_button.text = "Fast Roll All (Skip Order)"
	fast_roll_button.pressed.connect(_on_fast_roll_pressed)
	fast_roll_button.custom_minimum_size = Vector2(200, 40)
	_WhiteDwarfTheme.apply_to_button(fast_roll_button)
	button_hbox.add_child(fast_roll_button)

	start_sequence_button = Button.new()
	start_sequence_button.text = "Start Sequence"
	start_sequence_button.pressed.connect(_on_start_sequence_pressed)
	start_sequence_button.custom_minimum_size = Vector2(150, 40)
	_WhiteDwarfTheme.apply_to_button(start_sequence_button)
	button_hbox.add_child(start_sequence_button)

	close_button = Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(_on_close_pressed)
	close_button.custom_minimum_size = Vector2(100, 40)
	close_button.visible = false  # Hidden until sequence complete or fast roll
	_WhiteDwarfTheme.apply_to_button(close_button)
	button_hbox.add_child(close_button)

	# NEW: Continue button for mid-sequence progression
	# Make it visible by default so user can always progress
	var continue_button = Button.new()
	continue_button.name = "ContinueButton"
	continue_button.text = "Continue to Next Weapon"
	continue_button.pressed.connect(_on_continue_next_weapon_pressed)
	continue_button.custom_minimum_size = Vector2(220, 40)
	_WhiteDwarfTheme.apply_to_button(continue_button)
	# Make this button prominent with green color
	continue_button.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
	button_hbox.add_child(continue_button)
	continue_button.visible = false  # Hidden - users should use "Start Sequence" or "Fast Roll All"

	vbox.add_child(HSeparator.new())

	# Dice log section
	var log_label = Label.new()
	log_label.text = "Resolution Log:"
	log_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(log_label)

	dice_log_rich_text = RichTextLabel.new()
	dice_log_rich_text.set_custom_minimum_size(Vector2(460, 120))
	dice_log_rich_text.bbcode_enabled = true
	dice_log_rich_text.scroll_following = true
	vbox.add_child(dice_log_rich_text)

	print("WeaponOrderDialog initialized")

func setup(assignments: Array, phase = null) -> void:
	"""Setup the dialog with weapon assignments from shooting phase"""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ WeaponOrderDialog.setup() CALLED")
	print("║ Assignments count: %d" % assignments.size())

	weapon_assignments = assignments.duplicate(true)
	weapon_order.clear()
	weapon_data.clear()
	weapon_items.clear()
	current_phase = phase
	is_resolving = false

	# NEW: Validate assignments
	if assignments.is_empty():
		push_error("WeaponOrderDialog: Received EMPTY assignments array!")
		print("║ ❌ ERROR: No assignments provided")
		print("╚═══════════════════════════════════════════════════════════════")

		# Show error in dialog
		instruction_label.text = "ERROR: No weapons provided!\nThis is a bug - please report."
		instruction_label.add_theme_color_override("font_color", Color.RED)
		return

	# Connect to phase signals if available
	if current_phase and current_phase.has_signal("dice_rolled"):
		if not current_phase.dice_rolled.is_connected(_on_dice_rolled):
			current_phase.dice_rolled.connect(_on_dice_rolled)
			print("║ Connected to phase dice_rolled signal")

	# Group assignments by weapon type
	var weapon_groups = {}
	var skipped_count = 0  # NEW: Track skipped weapons

	for assignment in weapon_assignments:
		var weapon_id = assignment.get("weapon_id", "")

		# NEW: Log each assignment
		print("║ Processing assignment:")
		print("║   weapon_id: '%s'" % weapon_id)
		print("║   target_unit_id: '%s'" % assignment.get("target_unit_id", ""))
		print("║   model_ids: %s" % str(assignment.get("model_ids", [])))

		if weapon_id == "":
			skipped_count += 1
			push_error("WeaponOrderDialog: Assignment has EMPTY weapon_id, skipping!")
			print("║   ❌ SKIPPED (empty weapon_id)")
			print("║   Full assignment: %s" % str(assignment))
			continue

		if not weapon_groups.has(weapon_id):
			weapon_groups[weapon_id] = {
				"assignments": [],
				"count": 0,
				"total_damage": 0,
				"weapon_profile": RulesEngine.get_weapon_profile(weapon_id)
			}

		weapon_groups[weapon_id].assignments.append(assignment)
		weapon_groups[weapon_id].count += assignment.get("model_ids", []).size()
		print("║   ✓ Added to group '%s' (count: %d)" % [weapon_id, weapon_groups[weapon_id].count])

	# NEW: Check if all weapons were skipped
	if weapon_groups.is_empty():
		push_error("WeaponOrderDialog: All weapons were SKIPPED due to empty weapon_id!")
		print("║ ❌ ERROR: No valid weapons found (skipped %d)" % skipped_count)
		print("║ This likely means weapon_order in ShootingPhase is corrupted")
		print("╚═══════════════════════════════════════════════════════════════")

		# Show error in dialog
		instruction_label.text = "ERROR: All weapons have missing IDs!\nweapon_order may be corrupted.\nThis is a bug - please report."
		instruction_label.add_theme_color_override("font_color", Color.RED)
		return

	# Calculate total damage potential for each weapon
	for weapon_id in weapon_groups:
		var group = weapon_groups[weapon_id]
		var profile = group.weapon_profile
		var damage = profile.get("damage", 1)
		var attacks = profile.get("attacks", 1)
		group.total_damage = attacks * damage * group.count

		weapon_data[weapon_id] = {
			"name": profile.get("name", weapon_id),
			"count": group.count,
			"damage": damage,
			"attacks": attacks,
			"total_damage": group.total_damage,
			"range": profile.get("range", 0),
			"strength": profile.get("strength", 0),
			"ap": profile.get("ap", 0),
			"assignments": group.assignments
		}

	# Sort weapons by total damage (highest first) - DEFAULT ORDER
	var weapon_ids = weapon_groups.keys()
	weapon_ids.sort_custom(_compare_weapon_damage)

	weapon_order = weapon_ids

	# Build UI
	_rebuild_weapon_list()

	print("║ Total weapon types: %d" % weapon_order.size())
	print("║ Skipped assignments: %d" % skipped_count)
	print("╚═══════════════════════════════════════════════════════════════")

func _compare_weapon_damage(a: String, b: String) -> bool:
	"""Compare weapon damage for sorting (used by sort_custom)"""
	return weapon_data[a].total_damage > weapon_data[b].total_damage

func _rebuild_weapon_list() -> void:
	"""Rebuild the weapon list UI from current weapon_order"""
	# Clear existing items
	for child in weapon_list_container.get_children():
		child.queue_free()

	weapon_items.clear()

	# Create UI item for each weapon in order
	for i in range(weapon_order.size()):
		var weapon_id = weapon_order[i]
		var data = weapon_data[weapon_id]

		# Create panel for this weapon
		var panel = PanelContainer.new()
		panel.custom_minimum_size = Vector2(440, 60)

		var hbox = HBoxContainer.new()
		panel.add_child(hbox)

		# Position indicator
		var position_label = Label.new()
		position_label.text = str(i + 1) + "."
		position_label.custom_minimum_size = Vector2(30, 0)
		position_label.add_theme_font_size_override("font_size", 16)
		hbox.add_child(position_label)

		# Weapon info
		var info_vbox = VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(info_vbox)

		var name_label = Label.new()
		name_label.text = "%s (x%d)" % [data.name, data.count]
		name_label.add_theme_font_size_override("font_size", 14)
		info_vbox.add_child(name_label)

		var stats_label = Label.new()
		stats_label.text = "Dmg: %d | Atks: %d | Total Potential: %d" % [
			data.damage,
			data.attacks,
			data.total_damage
		]
		stats_label.add_theme_font_size_override("font_size", 10)
		stats_label.modulate = Color(0.8, 0.8, 0.8)
		info_vbox.add_child(stats_label)

		# Up/Down buttons
		var button_vbox = VBoxContainer.new()
		button_vbox.custom_minimum_size = Vector2(60, 0)
		hbox.add_child(button_vbox)

		var up_button = Button.new()
		up_button.text = "▲"
		up_button.custom_minimum_size = Vector2(50, 25)
		up_button.disabled = (i == 0)  # Can't move first item up
		up_button.pressed.connect(_on_move_up_pressed.bind(i))
		_WhiteDwarfTheme.apply_to_button(up_button)
		button_vbox.add_child(up_button)

		var down_button = Button.new()
		down_button.text = "▼"
		down_button.custom_minimum_size = Vector2(50, 25)
		down_button.disabled = (i == weapon_order.size() - 1)  # Can't move last item down
		down_button.pressed.connect(_on_move_down_pressed.bind(i))
		_WhiteDwarfTheme.apply_to_button(down_button)
		button_vbox.add_child(down_button)

		weapon_list_container.add_child(panel)
		weapon_items.append({
			"panel": panel,
			"weapon_id": weapon_id,
			"position": i
		})

func _on_move_up_pressed(index: int) -> void:
	"""Move weapon at index up in the order"""
	if index <= 0 or index >= weapon_order.size():
		return

	# Swap with previous
	var temp = weapon_order[index - 1]
	weapon_order[index - 1] = weapon_order[index]
	weapon_order[index] = temp

	# Rebuild UI
	_rebuild_weapon_list()

	print("Moved weapon at position %d up" % (index + 1))

func _on_move_down_pressed(index: int) -> void:
	"""Move weapon at index down in the order"""
	if index < 0 or index >= weapon_order.size() - 1:
		return

	# Swap with next
	var temp = weapon_order[index + 1]
	weapon_order[index + 1] = weapon_order[index]
	weapon_order[index] = temp

	# Rebuild UI
	_rebuild_weapon_list()

	print("Moved weapon at position %d down" % (index + 1))

func _on_fast_roll_pressed() -> void:
	"""Fast roll all weapons at once (existing behavior)"""
	print("WeaponOrderDialog: Fast roll selected")

	# Return all assignments in original order (order doesn't matter for fast roll)
	var all_assignments = []
	for weapon_id in weapon_data:
		all_assignments.append_array(weapon_data[weapon_id].assignments)

	emit_signal("weapon_order_confirmed", all_assignments, true)
	hide()
	queue_free()

func _on_start_sequence_pressed() -> void:
	"""Start sequential weapon resolution"""
	print("WeaponOrderDialog: Sequential resolution selected")
	print("Weapon order: ", weapon_order)

	# Build ordered assignments based on weapon_order
	var ordered_assignments = []
	for weapon_id in weapon_order:
		ordered_assignments.append_array(weapon_data[weapon_id].assignments)

	# Mark as resolving
	is_resolving = true

	# Disable ordering buttons
	fast_roll_button.disabled = true
	start_sequence_button.disabled = true
	weapon_list_container.visible = false  # Hide weapon list during resolution

	# Update instruction label
	instruction_label.text = "Resolving weapons sequentially...\nWatch the Resolution Log below for dice rolls and results."

	# Add initial log message
	_add_to_dice_log("Starting sequential weapon resolution...", Color.YELLOW)

	# Emit signal but DON'T close the dialog
	emit_signal("weapon_order_confirmed", ordered_assignments, false)

func _on_continue_next_weapon_pressed() -> void:
	"""Continue to next weapon in sequential mode (mid-sequence)"""
	print("WeaponOrderDialog: Continue to next weapon pressed")

	# Build ordered assignments based on current weapon_order
	var ordered_assignments = []
	for weapon_id in weapon_order:
		ordered_assignments.append_array(weapon_data[weapon_id].assignments)

	# Emit with fast_roll = false to continue sequential
	emit_signal("weapon_order_confirmed", ordered_assignments, false)
	hide()
	queue_free()

func _on_close_pressed() -> void:
	"""Close the dialog"""
	print("WeaponOrderDialog: Close button pressed")
	hide()
	queue_free()

func _on_dice_rolled(dice_data: Dictionary) -> void:
	"""Handle dice_rolled signal from ShootingPhase"""
	if not is_resolving:
		return  # Ignore if not in resolution mode

	# Check context
	var context = dice_data.get("context", "")

	if context == "weapon_progress":
		# Weapon progress message
		var message = dice_data.get("message", "")
		_add_to_dice_log("[b]>>> %s <<<[/b]" % message, Color.YELLOW)
	elif context == "resolution_start":
		# Resolution starting
		var message = dice_data.get("message", "Beginning resolution...")
		_add_to_dice_log(message, Color.CYAN)
	else:
		# Dice roll results
		var rolls_raw = dice_data.get("rolls_raw", [])
		var rolls_modified = dice_data.get("rolls_modified", [])
		var rerolls = dice_data.get("rerolls", [])
		var successes = dice_data.get("successes", -1)
		var threshold = dice_data.get("threshold", "")

		# Format the display text
		var log_text = "[b]%s[/b] (need %s): " % [context.capitalize().replace("_", " "), threshold]

		# Show re-rolls if any
		if not rerolls.is_empty():
			log_text += "[color=orange]Re-rolled:[/color] "
			for reroll in rerolls:
				log_text += "[s]%d[/s]→%d " % [reroll.original, reroll.rerolled_to]
			log_text += "| "

		# Show rolls
		var display_rolls = rolls_modified if not rolls_modified.is_empty() else rolls_raw
		log_text += "Rolls: %s" % str(display_rolls)

		# Show successes
		if successes >= 0:
			log_text += " → [b][color=green]%d successes[/color][/b]" % successes

		_add_to_dice_log(log_text, Color.WHITE)

func _add_to_dice_log(text: String, color: Color) -> void:
	"""Add colored text to dice log"""
	if not dice_log_rich_text:
		return

	var color_hex = color.to_html(false)
	dice_log_rich_text.append_text("[color=#%s]%s[/color]\n" % [color_hex, text])

	# Check if sequence is complete (ShootingPhase will emit shooting_resolved or saves_required)
	# For now, we'll show the close button after the first weapon progress
	# A more robust solution would be to connect to shooting_resolved signal
	if is_resolving and not close_button.visible:
		# Show close button after first dice roll (user can close anytime during resolution)
		close_button.visible = true
