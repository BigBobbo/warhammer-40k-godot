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
	var container = VBoxContainer.new()
	container.custom_minimum_size = Vector2(500, 300)

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

	# Filter for melee weapons
	var melee_weapons = []
	for weapon in weapons_data:
		if weapon.get("type", "").to_lower() == "melee":
			melee_weapons.append(weapon)
			print("[AttackAssignmentDialog] Added melee weapon: ", weapon.get("name", "Unknown"))

	print("[AttackAssignmentDialog] Total melee weapons: %d" % melee_weapons.size())

	# Weapon selector
	var weapon_label = Label.new()
	weapon_label.text = "Weapon:"
	container.add_child(weapon_label)

	weapon_list = ItemList.new()
	weapon_list.name = "WeaponList"
	weapon_list.custom_minimum_size = Vector2(480, 100)

	for i in range(melee_weapons.size()):
		var weapon = melee_weapons[i]
		var weapon_name = weapon.get("name", "Unknown")
		# Generate weapon ID from name (same format as RulesEngine)
		var weapon_id = weapon_name.to_lower().replace(" ", "_").replace("-", "_").replace("–", "_").replace("'", "")

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

	# Assign button
	var assign_button = Button.new()
	assign_button.text = "Add Assignment"
	assign_button.pressed.connect(_on_assign_pressed)
	container.add_child(assign_button)

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

func _update_assignments_display() -> void:
	if not assignments_display:
		return

	assignments_display.clear()
	for assignment in assignments:
		assignments_display.append_text("- %s → %s\n" % [assignment.weapon, assignment.target])

func _on_confirmed() -> void:
	print("[AttackAssignmentDialog] Confirmed button pressed")
	print("[AttackAssignmentDialog] Assignments count: ", assignments.size())

	if assignments.is_empty():
		push_warning("No attacks assigned")
		return

	print("[AttackAssignmentDialog] Emitting attacks_confirmed with ", assignments.size(), " assignments")
	hide()
	emit_signal("attacks_confirmed", assignments)
	await get_tree().create_timer(0.1).timeout
	queue_free()
