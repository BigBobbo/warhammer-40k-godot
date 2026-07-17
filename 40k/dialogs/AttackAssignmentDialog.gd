extends AcceptDialog
class_name AttackAssignmentDialog

signal attacks_confirmed(assignments: Array)
# Escape hatch: emitted when the dialog opened with NO eligible targets and
# the player ends the fight instead (the controller submits SKIP_UNIT).
# FightPhase normally auto-ends a no-target activation before this dialog is
# requested, so this only fires on unforeseen paths — but without it the
# dialog is un-completable (nothing to assign) and the game self-locks.
signal skip_fight_requested(unit_id: String)

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
	WhiteDwarfTheme.apply_to_dialog(self)
	print("[AttackAssignmentDialog] Setup called for unit: ", fighter_id)
	print("[AttackAssignmentDialog] Targets: ", targets.keys())

	unit_id = fighter_id
	eligible_targets = targets
	phase_reference = phase

	var unit = phase.get_unit(unit_id)
	var _aad_meta = unit.get("meta", {})
	title = "Assign Attacks: %s" % _aad_meta.get("display_name", _aad_meta.get("name", unit_id))

	print("[AttackAssignmentDialog] Building UI...")
	_build_ui()
	print("[AttackAssignmentDialog] UI built successfully")

func _build_ui() -> void:
	min_size = DialogConstants.MEDIUM
	var container = VBoxContainer.new()
	container.name = "Content"
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
	# 11e core rules (Fight — Select Melee Weapon): each model makes its attacks
	# with ONE selected melee weapon — the choice below is exclusive.
	var weapon_label = Label.new()
	weapon_label.text = "Select ONE Weapon (a model only fights with one melee weapon):"
	container.add_child(weapon_label)

	weapon_list = ItemList.new()
	weapon_list.name = "WeaponList"
	weapon_list.custom_minimum_size = Vector2(480, 100)

	# T-093: Compute max-cap. One-weapon rule: only ONE regular melee weapon
	# swings per activation, so the cap is the best single weapon — not the sum.
	var unit_max_attacks_best: float = 0.0
	for i in range(regular_melee_weapons.size()):
		var weapon = regular_melee_weapons[i]
		var weapon_name = weapon.get("name", "Unknown")
		# Generate weapon ID from name using RulesEngine to prevent collisions
		var weapon_id = RulesEngine.generate_weapon_id(weapon_name, weapon.get("type", ""))

		var avg_attacks: float = _average_dice_notation(str(weapon.get("attacks", "1")))
		var weapon_max_attacks: float = avg_attacks * float(max(1, eligible_indices.size()))
		unit_max_attacks_best = maxf(unit_max_attacks_best, weapon_max_attacks)

		weapon_list.add_item("%s (A:%s S:%s AP:%s D:%s, max ≈%s)" % [
			weapon_name,
			weapon.get("attacks", "1"),
			weapon.get("strength", "User"),
			weapon.get("ap", "0"),
			weapon.get("damage", "1"),
			"%.1f" % weapon_max_attacks if weapon_max_attacks != floor(weapon_max_attacks) else "%d" % int(weapon_max_attacks)
		])
		# Store the weapon ID as metadata for creating the attack action
		weapon_list.set_item_metadata(weapon_list.item_count - 1, weapon_id)
		print("[AttackAssignmentDialog] Weapon '%s' → ID '%s' (max attacks ≈%.1f)" % [weapon_name, weapon_id, weapon_max_attacks])

	# Pre-select the first weapon so a default choice is always visible
	if weapon_list.item_count > 0:
		weapon_list.select(0)

	# T-093: max-cap label (best single weapon — one melee weapon per model)
	var max_cap_label = Label.new()
	max_cap_label.text = "Max total attacks (cap): ≈%s across %d eligible models with the strongest single weapon" % [
		"%.1f" % unit_max_attacks_best if unit_max_attacks_best != floor(unit_max_attacks_best) else "%d" % int(unit_max_attacks_best),
		eligible_indices.size()
	]
	max_cap_label.add_theme_font_size_override("font_size", 12)
	container.add_child(max_cap_label)

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
	# Pre-select the first target so "All to Target" works immediately
	if target_list.item_count > 0:
		target_list.select(0)
	container.add_child(target_list)

	# Button container for assignment actions
	var button_container = HBoxContainer.new()
	button_container.name = "ButtonContainer"

	# Assign button
	var assign_button = Button.new()
	assign_button.name = "AssignButton"
	assign_button.text = "Add Assignment"
	assign_button.pressed.connect(_on_assign_pressed)
	button_container.add_child(assign_button)

	# T5-UX5 (reworked for the 11e one-weapon rule): one-click shortcut that
	# assigns the selected weapon to the selected target. Node name is kept as
	# AllToTargetButton — windowed scenarios click it by path.
	all_to_target_button = Button.new()
	all_to_target_button.name = "AllToTargetButton"
	all_to_target_button.text = "Weapon to Target"
	all_to_target_button.tooltip_text = "Assign the selected melee weapon to the selected target (each model fights with one melee weapon)"
	all_to_target_button.pressed.connect(_on_all_to_target_pressed)
	button_container.add_child(all_to_target_button)

	# Explicit confirm button with a stable path (the built-in AcceptDialog
	# OK button lives under auto-named internal containers)
	var confirm_attacks_button = Button.new()
	confirm_attacks_button.name = "ConfirmButton"
	confirm_attacks_button.text = "Fight!"
	confirm_attacks_button.pressed.connect(_on_confirmed)
	button_container.add_child(confirm_attacks_button)

	# Hide the built-in OK button: it duplicated "Fight!" (both fired
	# _on_confirmed) and, unlike "Fight!", auto-hid the dialog even when the
	# confirm was rejected for having no assignments.
	get_ok_button().visible = false

	# No eligible targets: nothing can ever be assigned, so the three buttons
	# above are dead ends — offer the one legal move (ending the fight)
	# instead of soft-locking the player in an un-completable dialog.
	if eligible_targets.is_empty():
		assign_button.disabled = true
		all_to_target_button.disabled = true
		confirm_attacks_button.disabled = true

		var no_targets_label = Label.new()
		no_targets_label.name = "NoTargetsLabel"
		no_targets_label.text = "No enemy units within Engagement Range — this unit cannot make melee attacks."
		no_targets_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		container.add_child(no_targets_label)

		var skip_button = Button.new()
		skip_button.name = "SkipFightButton"
		skip_button.text = "End Fight (No Targets)"
		skip_button.tooltip_text = "End this unit's activation — it has no one to attack"
		skip_button.pressed.connect(_on_skip_fight_pressed)
		button_container.add_child(skip_button)

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

	_set_single_weapon_assignment(weapon_id, target_id)

# 11e one-weapon rule: dialog assignments always cover the whole unit, so
# there is only ever ONE regular melee weapon assignment — setting a new one
# replaces the previous choice instead of stacking a second weapon.
func _set_single_weapon_assignment(weapon_id: String, target_id: String) -> void:
	if not assignments.is_empty():
		var previous = assignments[0]
		print("[AttackAssignmentDialog] One-weapon rule: replacing assignment %s → %s with %s → %s" % [
			previous.get("weapon", "?"), previous.get("target", "?"), weapon_id, target_id])
	assignments.clear()

	print("[AttackAssignmentDialog] Assignment: ", weapon_id, " → ", target_id)

	assignments.append({
		"attacker": unit_id,
		"weapon": weapon_id,
		"target": target_id
	})

	print("[AttackAssignmentDialog] Total assignments: ", assignments.size())
	_update_assignments_display()

# T5-UX5 (reworked for the 11e one-weapon rule): assign the selected weapon —
# defaulting to the first — to the selected target in a single click.
# Previously this assigned ALL unassigned weapons, which let one model fight
# with every weapon it carries; that is illegal (Fight — Select Melee Weapon).
func _on_all_to_target_pressed() -> void:
	print("[AttackAssignmentDialog] T5-UX5: 'Weapon to Target' button pressed")

	if not weapon_list or not target_list:
		push_error("Weapon or target list not initialized")
		return

	var target_idx = target_list.get_selected_items()
	if target_idx.is_empty():
		push_warning("Select a target first")
		print("[AttackAssignmentDialog] T5-UX5: No target selected")
		return

	if weapon_list.item_count == 0:
		push_warning("No melee weapons available")
		return

	var weapon_idx = weapon_list.get_selected_items()
	var weapon_item: int = weapon_idx[0] if not weapon_idx.is_empty() else 0
	var weapon_id = weapon_list.get_item_metadata(weapon_item)
	var target_id = target_list.get_item_metadata(target_idx[0])

	print("[AttackAssignmentDialog] T5-UX5: Assigning weapon '%s' → '%s' (one weapon per model)" % [weapon_id, target_id])
	_set_single_weapon_assignment(weapon_id, target_id)

func _update_assignments_display() -> void:
	if not assignments_display:
		return

	assignments_display.clear()
	var total_expected_damage: float = 0.0
	for assignment in assignments:
		var ed: float = _estimate_expected_damage(assignment.weapon, assignment.target)
		total_expected_damage += ed
		# T-093: include expected damage estimate per assignment
		assignments_display.append_text("- %s → %s [E[D]≈%.1f]\n" % [assignment.weapon, assignment.target, ed])

	# T3-3: Show Extra Attacks auto-assignments preview
	if not extra_attacks_weapons.is_empty():
		var ea_target_id = _get_extra_attacks_target_id()
		for weapon in extra_attacks_weapons:
			var weapon_name = weapon.get("name", "Unknown")
			var weapon_id = RulesEngine.generate_weapon_id(weapon_name, weapon.get("type", ""))
			var ed: float = _estimate_expected_damage(weapon_id, ea_target_id)
			total_expected_damage += ed
			assignments_display.append_text("- %s → %s [Extra Attacks, E[D]≈%.1f]\n" % [weapon_name, ea_target_id, ed])
	if total_expected_damage > 0.0:
		assignments_display.append_text("[b]Total expected damage: %.1f[/b]\n" % total_expected_damage)


# T-093: analytic expected-damage estimator for AttackAssignmentDialog preview.
# Uses standard Warhammer 10e math: E[D] = A * Phit * Pwound * Punsaved * D
# where probability functions parse weapon profile + defender stats.
func _estimate_expected_damage(weapon_id: String, target_id: String) -> float:
	if phase_reference == null or unit_id == "" or target_id == "":
		return 0.0
	var attacker_unit = phase_reference.get_unit(unit_id)
	var target_unit = phase_reference.get_unit(target_id)
	if attacker_unit.is_empty() or target_unit.is_empty():
		return 0.0
	# Find weapon
	var weapon: Dictionary = {}
	for w in attacker_unit.get("meta", {}).get("weapons", []):
		var wname = w.get("name", "")
		var wid = RulesEngine.generate_weapon_id(wname, w.get("type", ""))
		if wid == weapon_id or wname == weapon_id:
			weapon = w
			break
	if weapon.is_empty():
		return 0.0
	# Parse weapon stats — strip dice notation by averaging
	var attacks_str: String = str(weapon.get("attacks", "1"))
	var strength_int: int = _parse_stat_int(str(weapon.get("strength", "4")))
	var ap_int: int = _parse_stat_int(str(weapon.get("ap", "0")))
	var damage_str: String = str(weapon.get("damage", "1"))
	var attacks_avg: float = _average_dice_notation(attacks_str)
	var damage_avg: float = _average_dice_notation(damage_str)
	# Total attacks = per-weapon-attacks * number of models in attacker that have this weapon
	# Approximation: assume 1 model wields it; refine if multi-wielders evident
	var alive_count: int = 0
	for m in attacker_unit.get("models", []):
		if m.get("alive", true):
			alive_count += 1
	# Treat per-model A as a single shooter; UI is a preview not a simulation
	var total_attacks: float = attacks_avg * float(max(1, alive_count))
	# Hit probability from WS/BS (weapon's accuracy attribute)
	var skill_int: int = _parse_stat_int(str(weapon.get("skill", weapon.get("ws", weapon.get("bs", "4")))))
	var p_hit: float = clampf(float(7 - skill_int) / 6.0, 1.0/6.0, 5.0/6.0)
	# Wound probability vs target T
	var target_T: int = _parse_stat_int(str(target_unit.get("meta", {}).get("stats", {}).get("toughness", 4)))
	var p_wound: float = _wound_probability(strength_int, target_T)
	# Unsaved probability: target save - AP, capped invuln
	var target_save: int = _parse_stat_int(str(target_unit.get("meta", {}).get("stats", {}).get("save", 5)))
	var target_invuln: int = _parse_stat_int(str(target_unit.get("meta", {}).get("stats", {}).get("invuln", 7)))
	var modified_save: int = max(2, target_save - max(0, ap_int))  # unmodified save min 2+
	var effective_save: int = min(modified_save, target_invuln)
	var p_unsaved: float = clampf(float(effective_save - 1) / 6.0, 0.0, 1.0)
	# FNP not factored (would need to read defender flags); coarse preview.
	return total_attacks * p_hit * p_wound * p_unsaved * damage_avg


func _parse_stat_int(s: String) -> int:
	# Accept "4", "4+", "S", numeric; defaults to 4 on parse failure
	s = s.strip_edges()
	if s.is_empty():
		return 4
	if s == "S" or s == "U" or s == "User":
		return 4
	# Strip trailing + for save/skill formats
	if s.ends_with("+"):
		s = s.substr(0, s.length() - 1)
	if s.is_valid_int():
		return int(s)
	return 4


func _average_dice_notation(s: String) -> float:
	# Handles "1", "3", "D6", "2D3", "D6+1", "2D6"
	s = s.strip_edges().to_upper().replace(" ", "")
	if s.is_empty():
		return 1.0
	if s.is_valid_int():
		return float(int(s))
	# Look for NDX or NDX+M pattern
	var plus_idx = s.find("+")
	var bonus: float = 0.0
	if plus_idx >= 0:
		var after = s.substr(plus_idx + 1)
		if after.is_valid_int():
			bonus = float(int(after))
		s = s.substr(0, plus_idx)
	var d_idx = s.find("D")
	if d_idx < 0:
		return 1.0 + bonus
	var n_str = s.substr(0, d_idx)
	var x_str = s.substr(d_idx + 1)
	var n: int = int(n_str) if n_str.is_valid_int() else 1
	var x: int = int(x_str) if x_str.is_valid_int() else 6
	# Average of 1 die of size x is (x+1)/2
	return float(n) * (float(x) + 1.0) / 2.0 + bonus


func _wound_probability(s: int, t: int) -> float:
	# 10e wound chart
	if s >= t * 2:
		return 5.0 / 6.0
	if s > t:
		return 4.0 / 6.0
	if s == t:
		return 3.0 / 6.0
	if s * 2 <= t:
		return 1.0 / 6.0
	return 2.0 / 6.0

func _on_skip_fight_pressed() -> void:
	print("[AttackAssignmentDialog] Skip fight pressed (no eligible targets) for unit: ", unit_id)
	hide()
	emit_signal("skip_fight_requested", unit_id)
	queue_free()

func _on_confirmed() -> void:
	print("[AttackAssignmentDialog] Confirmed button pressed")
	print("[AttackAssignmentDialog] Assignments count: ", assignments.size())

	if assignments.is_empty() and extra_attacks_weapons.is_empty():
		push_warning("No attacks assigned")
		if not visible:
			# A `confirmed`-signal accept auto-hides the dialog before this
			# validation runs — re-show so the fight flow can't strand.
			show()
		return

	# T3-3: Extra Attacks weapons cannot be used alone — need at least one regular weapon assignment
	if assignments.is_empty() and not extra_attacks_weapons.is_empty():
		push_warning("Extra Attacks weapons must be used IN ADDITION to another weapon — assign a regular weapon first")
		print("[AttackAssignmentDialog] Blocked: Extra Attacks weapons cannot be the only weapon choice")
		if not visible:
			show()
		return

	# T3-3: Auto-include Extra Attacks weapons in assignments
	if not extra_attacks_weapons.is_empty():
		var ea_target_id = _get_extra_attacks_target_id()
		for weapon in extra_attacks_weapons:
			var weapon_name = weapon.get("name", "Unknown")
			var weapon_id = RulesEngine.generate_weapon_id(weapon_name, weapon.get("type", ""))
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
