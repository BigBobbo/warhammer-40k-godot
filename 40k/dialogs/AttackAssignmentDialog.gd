extends AcceptDialog
class_name AttackAssignmentDialog

signal attacks_confirmed(assignments: Array)

var unit_id: String = ""
var eligible_targets: Dictionary = {}
var phase_reference = null
var assignments: Array = []
var weapon_list: ItemList = null
var target_list: ItemList = null
var assignments_display: RichTextLabel = null
var extra_attacks_weapons: Array = []  # T3-3: Track Extra Attacks weapons for auto-inclusion
var extra_attacks_target_list: ItemList = null  # T3-3: Target selector for Extra Attacks weapons
var all_to_target_button: Button = null  # T5-UX5: "All to Target" shortcut button

func setup(fighter_id: String, targets: Dictionary, phase) -> void:
	print("[AttackAssignmentDialog] Setup called for unit: ", fighter_id)
	print("[AttackAssignmentDialog] Targets: ", targets.keys())

	unit_id = fighter_id
	eligible_targets = targets
	phase_reference = phase

	var unit = phase.get_unit(unit_id)
	title = "Assign Attacks: %s" % unit.get("meta", {}).get("name", unit_id)

	print("[AttackAssignmentDialog] Building UI...")
	_build_ui()
	print("[AttackAssignmentDialog] UI built successfully")

func _build_ui() -> void:
	min_size = DialogConstants.MEDIUM
	var container = VBoxContainer.new()
	container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	# Get unit's melee weapons from meta
	var unit = phase_reference.get_unit(unit_id)

	# Show eligible model count (per 10e: only models in engagement range can fight)
	var eligible_indices = RulesEngine.get_eligible_melee_model_indices(unit, phase_reference.game_state_snapshot)
	var alive_count = 0
	for model in unit.get("models", []):
		if model.get("alive", true):
			alive_count += 1

	var instruction = Label.new()
	if eligible_indices.size() < alive_count:
		instruction.text = "Models in engagement range: %d/%d" % [eligible_indices.size(), alive_count]
	else:
		instruction.text = "All %d models in engagement range" % alive_count
	container.add_child(instruction)
	var weapons_data = unit.get("meta", {}).get("weapons", [])
	print("[AttackAssignmentDialog] Found %d total weapons" % weapons_data.size())

	# T3-3: Separate melee weapons into regular and Extra Attacks
	var regular_melee_weapons = []
	extra_attacks_weapons = []
	for weapon in weapons_data:
		if weapon.get("type", "").to_lower() == "melee":
			if RulesEngine.weapon_data_has_extra_attacks(weapon):
				extra_attacks_weapons.append(weapon)
				print("[AttackAssignmentDialog] Extra Attacks weapon: ", weapon.get("name", "Unknown"))
			else:
				regular_melee_weapons.append(weapon)
				print("[AttackAssignmentDialog] Regular melee weapon: ", weapon.get("name", "Unknown"))

	print("[AttackAssignmentDialog] Regular melee weapons: %d, Extra Attacks weapons: %d" % [regular_melee_weapons.size(), extra_attacks_weapons.size()])

	# T3-3: Show Extra Attacks weapons info if any exist
	if not extra_attacks_weapons.is_empty():
		var ea_label = Label.new()
		ea_label.text = "Extra Attacks (auto-included with any weapon choice):"
		container.add_child(ea_label)

		var ea_display = RichTextLabel.new()
		ea_display.custom_minimum_size = Vector2(480, 30 + extra_attacks_weapons.size() * 20)
		ea_display.bbcode_enabled = true
		for weapon in extra_attacks_weapons:
			ea_display.append_text("[b]+ %s[/b] (A:%s S:%s AP:%s D:%s) [i][Extra Attacks][/i]\n" % [
				weapon.get("name", "Unknown"),
				weapon.get("attacks", "1"),
				weapon.get("strength", "User"),
				weapon.get("ap", "0"),
				weapon.get("damage", "1")
			])
		container.add_child(ea_display)

		# T3-3: Target selector for Extra Attacks weapons (defaults to first target)
		if eligible_targets.size() > 1:
			var ea_target_label = Label.new()
			ea_target_label.text = "Extra Attacks target:"
			container.add_child(ea_target_label)

			extra_attacks_target_list = ItemList.new()
			extra_attacks_target_list.name = "ExtraAttacksTargetList"
			extra_attacks_target_list.custom_minimum_size = Vector2(480, 60)
			for target_id in eligible_targets:
				var target_data = eligible_targets[target_id]
				extra_attacks_target_list.add_item("%s" % target_data.get("name", target_id))
				extra_attacks_target_list.set_item_metadata(extra_attacks_target_list.item_count - 1, target_id)
			# Default select first target
			if extra_attacks_target_list.item_count > 0:
				extra_attacks_target_list.select(0)
			container.add_child(extra_attacks_target_list)

		var separator = HSeparator.new()
		container.add_child(separator)

	# Weapon selector (regular weapons only)
	var weapon_label = Label.new()
	weapon_label.text = "Select Weapon:"
	container.add_child(weapon_label)

	weapon_list = ItemList.new()
	weapon_list.name = "WeaponList"
	weapon_list.custom_minimum_size = Vector2(480, 100)

	for i in range(regular_melee_weapons.size()):
		var weapon = regular_melee_weapons[i]
		var weapon_name = weapon.get("name", "Unknown")
		# Generate weapon ID from name using RulesEngine to prevent collisions
		var weapon_id = RulesEngine._generate_weapon_id(weapon_name, weapon.get("type", ""))

		weapon_list.add_item("%s (A:%s S:%s AP:%s D:%s)" % [
			weapon_name,
			weapon.get("attacks", "1"),
			weapon.get("strength", "User"),
			weapon.get("ap", "0"),
			weapon.get("damage", "1")
		])
		# Store the weapon ID as metadata for creating the attack action
		weapon_list.set_item_metadata(weapon_list.item_count - 1, weapon_id)
		print("[AttackAssignmentDialog] Weapon '%s' → ID '%s'" % [weapon_name, weapon_id])

	container.add_child(weapon_list)

	# Target selector
	var target_label = Label.new()
	target_label.text = "Target:"
	container.add_child(target_label)

	target_list = ItemList.new()
	target_list.name = "TargetList"
	target_list.custom_minimum_size = Vector2(480, 100)
	for target_id in eligible_targets:
		var target_data = eligible_targets[target_id]
		target_list.add_item("%s (in engagement range)" % target_data.get("name", target_id))
		target_list.set_item_metadata(target_list.item_count - 1, target_id)
	container.add_child(target_list)

	# Button container for assignment actions
	var button_container = HBoxContainer.new()
	button_container.name = "ButtonContainer"

	# Assign button
	var assign_button = Button.new()
	assign_button.text = "Add Assignment"
	assign_button.pressed.connect(_on_assign_pressed)
	button_container.add_child(assign_button)

	# T5-UX5: "All to Target" button — assigns all unassigned weapons to the selected target
	all_to_target_button = Button.new()
	all_to_target_button.text = "All to Target"
	all_to_target_button.tooltip_text = "Assign all unassigned weapons to the selected target"
	all_to_target_button.pressed.connect(_on_all_to_target_pressed)
	button_container.add_child(all_to_target_button)

	container.add_child(button_container)

	# Current assignments display
	var assignments_label = Label.new()
	assignments_label.text = "Assignments:"
	assignments_label.name = "AssignmentsLabel"
	container.add_child(assignments_label)

	assignments_display = RichTextLabel.new()
	assignments_display.custom_minimum_size = Vector2(480, 60)
	assignments_display.name = "AssignmentsDisplay"
	container.add_child(assignments_display)

	add_child(container)

	confirmed.connect(_on_confirmed)

func _on_assign_pressed() -> void:
	print("[AttackAssignmentDialog] Assign button pressed")

	if not weapon_list or not target_list:
		push_error("Weapon or target list not initialized")
		return

	var weapon_idx = weapon_list.get_selected_items()
	var target_idx = target_list.get_selected_items()

	print("[AttackAssignmentDialog] Selected weapon idx: ", weapon_idx)
	print("[AttackAssignmentDialog] Selected target idx: ", target_idx)

	if weapon_idx.is_empty() or target_idx.is_empty():
		push_warning("Select both weapon and target")
		return

	var weapon_id = weapon_list.get_item_metadata(weapon_idx[0])
	var target_id = target_list.get_item_metadata(target_idx[0])

	print("[AttackAssignmentDialog] Assignment: ", weapon_id, " → ", target_id)

	assignments.append({
		"attacker": unit_id,
		"weapon": weapon_id,
		"target": target_id
	})

	print("[AttackAssignmentDialog] Total assignments: ", assignments.size())
	_update_assignments_display()

# T5-UX5: Assign all unassigned weapons to the selected target
func _on_all_to_target_pressed() -> void:
	print("[AttackAssignmentDialog] T5-UX5: 'All to Target' button pressed")

	if not weapon_list or not target_list:
		push_error("Weapon or target list not initialized")
		return

	var target_idx = target_list.get_selected_items()
	if target_idx.is_empty():
		push_warning("Select a target first")
		print("[AttackAssignmentDialog] T5-UX5: No target selected")
		return

	var target_id = target_list.get_item_metadata(target_idx[0])
	var assigned_weapon_ids = _get_assigned_weapon_ids()
	var newly_assigned = 0

	for i in range(weapon_list.item_count):
		var weapon_id = weapon_list.get_item_metadata(i)
		if weapon_id and weapon_id not in assigned_weapon_ids:
			assignments.append({
				"attacker": unit_id,
				"weapon": weapon_id,
				"target": target_id
			})
			newly_assigned += 1
			print("[AttackAssignmentDialog] T5-UX5: Assigned weapon '%s' → '%s'" % [weapon_id, target_id])

	print("[AttackAssignmentDialog] T5-UX5: Assigned %d weapons to target '%s'. Total assignments: %d" % [newly_assigned, target_id, assignments.size()])
	_update_assignments_display()

# T5-UX5: Get set of weapon IDs that are already assigned
func _get_assigned_weapon_ids() -> Dictionary:
	var assigned = {}
	for assignment in assignments:
		assigned[assignment.get("weapon", "")] = true
	return assigned

func _update_assignments_display() -> void:
	if not assignments_display:
		return

	assignments_display.clear()
	for assignment in assignments:
		assignments_display.append_text("- %s → %s\n" % [assignment.weapon, assignment.target])

	# T3-3: Show Extra Attacks auto-assignments preview
	if not extra_attacks_weapons.is_empty():
		var ea_target_id = _get_extra_attacks_target_id()
		for weapon in extra_attacks_weapons:
			var weapon_name = weapon.get("name", "Unknown")
			assignments_display.append_text("- %s → %s [Extra Attacks]\n" % [weapon_name, ea_target_id])

func _on_confirmed() -> void:
	print("[AttackAssignmentDialog] Confirmed button pressed")
	print("[AttackAssignmentDialog] Assignments count: ", assignments.size())

	if assignments.is_empty() and extra_attacks_weapons.is_empty():
		push_warning("No attacks assigned")
		return

	# T3-3: Extra Attacks weapons cannot be used alone — need at least one regular weapon assignment
	if assignments.is_empty() and not extra_attacks_weapons.is_empty():
		push_warning("Extra Attacks weapons must be used IN ADDITION to another weapon — assign a regular weapon first")
		print("[AttackAssignmentDialog] Blocked: Extra Attacks weapons cannot be the only weapon choice")
		return

	# T3-3: Auto-include Extra Attacks weapons in assignments
	if not extra_attacks_weapons.is_empty():
		var ea_target_id = _get_extra_attacks_target_id()
		for weapon in extra_attacks_weapons:
			var weapon_name = weapon.get("name", "Unknown")
			var weapon_id = RulesEngine._generate_weapon_id(weapon_name, weapon.get("type", ""))
			assignments.append({
				"attacker": unit_id,
				"weapon": weapon_id,
				"target": ea_target_id
			})
			print("[AttackAssignmentDialog] T3-3: Auto-added Extra Attacks weapon '%s' → '%s'" % [weapon_name, ea_target_id])

	print("[AttackAssignmentDialog] Emitting attacks_confirmed with ", assignments.size(), " assignments (including Extra Attacks)")
	hide()
	emit_signal("attacks_confirmed", assignments)
	await get_tree().create_timer(0.1).timeout
	queue_free()

# T3-3: Get the target ID for Extra Attacks weapons
func _get_extra_attacks_target_id() -> String:
	# If there's a dedicated Extra Attacks target selector and something is selected, use it
	if extra_attacks_target_list and not extra_attacks_target_list.get_selected_items().is_empty():
		var idx = extra_attacks_target_list.get_selected_items()[0]
		return extra_attacks_target_list.get_item_metadata(idx)

	# If there's only one target, use it
	if eligible_targets.size() == 1:
		return eligible_targets.keys()[0]

	# Fall back to the first assignment's target (most common case)
	if not assignments.is_empty():
		return assignments[0].get("target", eligible_targets.keys()[0])

	# Last resort: first eligible target
	return eligible_targets.keys()[0]
