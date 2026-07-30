extends AcceptDialog
class_name AttackAssignmentDialog

signal attacks_confirmed(assignments: Array)
# Escape hatch: emitted when the dialog opened with NO eligible targets and
# the player ends the fight instead (the controller submits SKIP_UNIT).
# FightPhase normally auto-ends a no-target activation before this dialog is
# requested, so this only fires on unforeseen paths — but without it the
# dialog is un-completable (nothing to assign) and the game self-locks.
signal skip_fight_requested(unit_id: String)
# Pad (controller): emitted with the unit_id of the target_list row the D-pad
# ◀ ▶ cursor now sits on, so the FightController can bracket it on the board
# with the shared gold reticle. Also fires once on open (auto-arm) when the pad
# is the active device.
signal pad_target_focus_changed(target_id: String)

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
var _pad_hint_label: Label = null  # Controller hint row (shown only when a pad is active)

# MA-LOADOUT: the unit's melee reality, one entry per weapon that at least one
# ELIGIBLE model actually carries:
#   {weapon_id, name, weapon (datasheet dict), models: [model index], roles: [String]}
#
# This used to be `meta.weapons` — the datasheet's whole option MENU — which made
# the dialog claim every Ork Boy carried a Choppa AND a Close combat weapon AND
# (via the Boss Nob's row) a Big choppa AND a Power klaw, and offered "max ≈30
# attacks" for each of them. Those are mutually-exclusive wargear options: the
# mob is 9 Boyz with choppas and 1 Boss Nob with a big choppa.
#
# 11e Fight — Select Weapons: "For each model in the attacking unit, select which
# weapons that model will make attacks with … you must select one melee weapon
# THAT MODEL HAS." Per MODEL, not per unit — so the Boss Nob can swing his big
# choppa in the same activation the Boyz swing choppas. Each group therefore
# carries its own model list and gets its own assignment.
var melee_groups: Array = []
var extra_attacks_groups: Array = []
var clear_button: Button = null

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

	# MA-LOADOUT: what the models ACTUALLY carry, not the datasheet's option menu.
	_build_melee_groups(unit, eligible_indices)
	# Kept in sync for the _on_confirmed guards, which only need the profiles.
	extra_attacks_weapons = []
	for g in extra_attacks_groups:
		extra_attacks_weapons.append(g.weapon)

	print("[AttackAssignmentDialog] Regular melee weapons: %d, Extra Attacks weapons: %d" % [melee_groups.size(), extra_attacks_weapons.size()])

	# T3-3: Show Extra Attacks weapons info if any exist
	if not extra_attacks_groups.is_empty():
		var ea_label = Label.new()
		ea_label.text = "Extra Attacks (auto-included with any weapon choice):"
		container.add_child(ea_label)

		var ea_display = RichTextLabel.new()
		ea_display.custom_minimum_size = Vector2(480, 30 + extra_attacks_groups.size() * 20)
		ea_display.bbcode_enabled = true
		for g in extra_attacks_groups:
			var weapon = g.weapon
			ea_display.append_text("[b]+ %s[/b] ×%d %s (A:%s S:%s AP:%s D:%s) [i][Extra Attacks][/i]\n" % [
				weapon.get("name", "Unknown"),
				g.models.size(),
				_role_summary(g),
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
	# 11e core rules (Fight — Select Weapons): each MODEL makes its attacks with
	# one melee weapon THAT MODEL HAS. Different models may pick different
	# weapons, so each row below is a weapon plus the models carrying it, and a
	# row can be assigned without cancelling the others.
	var weapon_label = Label.new()
	if melee_groups.size() > 1:
		weapon_label.text = "Weapons carried (each model swings ONE — different models may swing different weapons):"
	else:
		weapon_label.text = "Weapon carried (each model fights with one melee weapon):"
	weapon_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	weapon_label.custom_minimum_size = Vector2(480, 0)
	container.add_child(weapon_label)

	weapon_list = ItemList.new()
	weapon_list.name = "WeaponList"
	weapon_list.custom_minimum_size = Vector2(480, 100)

	for g in melee_groups:
		var weapon = g.weapon
		var weapon_name = str(g.name)
		var weapon_max_attacks: float = _group_max_attacks(g)

		weapon_list.add_item("%s — %d× %s (A:%s S:%s AP:%s D:%s, max ≈%s)" % [
			weapon_name,
			g.models.size(),
			_role_summary(g),
			weapon.get("attacks", "1"),
			weapon.get("strength", "User"),
			weapon.get("ap", "0"),
			weapon.get("damage", "1"),
			_fmt_num(weapon_max_attacks)
		])
		# Store the weapon ID as metadata for creating the attack action
		weapon_list.set_item_metadata(weapon_list.item_count - 1, str(g.weapon_id))
		print("[AttackAssignmentDialog] Weapon '%s' → ID '%s' carried by %d eligible model(s) %s (max attacks ≈%.1f)" % [
			weapon_name, str(g.weapon_id), g.models.size(), str(g.models), weapon_max_attacks])

	# Pre-select the first weapon so a default choice is always visible
	if weapon_list.item_count > 0:
		weapon_list.select(0)

	# T-093: max-cap label. Every eligible model swings its OWN weapon, so the
	# cap is the sum over models of their best carried weapon — not one weapon
	# times the whole unit (which is what the datasheet-menu version reported).
	var max_cap_label = Label.new()
	max_cap_label.name = "MaxCapLabel"
	max_cap_label.text = "Max total attacks (cap): ≈%s across %d eligible models, each swinging the weapon it carries" % [
		_fmt_num(_unit_max_attacks(eligible_indices)),
		eligible_indices.size()
	]
	max_cap_label.add_theme_font_size_override("font_size", 12)
	max_cap_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	max_cap_label.custom_minimum_size = Vector2(480, 0)
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

	# Assign button — the SELECTED weapon, swung by the models that carry it.
	var assign_button = Button.new()
	assign_button.name = "AssignButton"
	assign_button.text = "Add Assignment"
	assign_button.tooltip_text = "Send the selected weapon's models at the selected target. Other weapons keep their own assignments — different models may swing different weapons."
	assign_button.pressed.connect(_on_assign_pressed)
	button_container.add_child(assign_button)

	# T5-UX5 (reworked for per-model loadouts): one-click shortcut that sends
	# EVERY carried weapon at the selected target — the Boss Nob's big choppa and
	# the Boyz' choppas in the same activation, each swung only by its own models.
	# Node name is kept as AllToTargetButton — windowed scenarios click it by path.
	all_to_target_button = Button.new()
	all_to_target_button.name = "AllToTargetButton"
	all_to_target_button.text = "Weapon to Target" if melee_groups.size() <= 1 else "All Weapons to Target"
	all_to_target_button.tooltip_text = "Assign every weapon the unit carries to the selected target — each weapon swung only by the models that have it"
	all_to_target_button.pressed.connect(_on_all_to_target_pressed)
	button_container.add_child(all_to_target_button)

	# Undo: with several weapon groups a mis-click would otherwise lock a model
	# into the wrong weapon for the whole activation.
	clear_button = Button.new()
	clear_button.name = "ClearAssignmentsButton"
	clear_button.text = "Clear"
	clear_button.tooltip_text = "Clear all weapon assignments and start again"
	clear_button.pressed.connect(_on_clear_assignments_pressed)
	button_container.add_child(clear_button)

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

	# Pad (controller) hint row — the melee twin of the shooting phase's target
	# ring, spelled out for a controller. Shown only when the pad is the active
	# device; a mouse player never sees it. See _pad_handle_input.
	_pad_hint_label = Label.new()
	_pad_hint_label.name = "PadHintLabel"
	_pad_hint_label.text = "▲▼ Weapon   ·   ◀▶ Target   ·   Ⓐ Assign   ·   Ⓨ All weapons   ·   ☰ Fight!   ·   Ⓑ Skip"
	_pad_hint_label.add_theme_font_size_override("font_size", 12)
	_pad_hint_label.modulate = Color(1, 1, 1, 0.75)
	_pad_hint_label.visible = InputDeviceManager.is_pad_active()
	container.add_child(_pad_hint_label)

	add_child(container)

	confirmed.connect(_on_confirmed)

	# Pad: the ItemLists are driven by the D-pad through window_input (below), so
	# demote them out of the focus chain — otherwise the dialog watcher / native
	# ui_up-down would fight our stepping. Buttons keep focus for A-fallthrough.
	for lst in [weapon_list, target_list, extra_attacks_target_list]:
		if lst != null:
			lst.focus_mode = Control.FOCUS_CLICK
	window_input.connect(_pad_handle_input)
	# Auto-arm the board reticle on the first shown frame when a pad is active,
	# so ◀ ▶ / A have a visible target from the very first press.
	about_to_popup.connect(_pad_arm_on_popup)


# Pad: arm the reticle for the initially-selected target (index 0) when the
# dialog pops with a pad active. Deferred a frame so the dialog is on-screen and
# the FightController's connection is live.
func _pad_arm_on_popup() -> void:
	if _pad_hint_label != null:
		_pad_hint_label.visible = InputDeviceManager.is_pad_active()
	if not InputDeviceManager.is_pad_active():
		return
	call_deferred("_pad_emit_current_target")


func _pad_emit_current_target() -> void:
	var tid := _pad_current_target_id()
	if tid != "":
		pad_target_focus_changed.emit(tid)


func _pad_current_target_id() -> String:
	if target_list == null or target_list.item_count == 0:
		return ""
	var sel := target_list.get_selected_items()
	var idx: int = sel[0] if not sel.is_empty() else 0
	return str(target_list.get_item_metadata(idx))


# Pad navigation for the whole attack dialog, handled on the dialog's own
# window_input so it never fights PadRouter (an exclusive AcceptDialog is its
# own viewport). Mirrors the shooting phase's controller mapping exactly:
#   ▲ ▼   step the weapon list   (each row = a weapon + the models carrying it)
#   ◀ ▶   step the target list   (updates the board reticle via the signal)
#   Ⓐ     Add Assignment          (assign the selected weapon → target)
#   Ⓨ     All Weapons to Target   (every carried weapon → the selected target)
#   ☰      Fight!                  (confirm + resolve — the phase-action button)
#   Ⓑ     Skip / cancel           (ends the activation when a Skip button exists)
func _pad_handle_input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton) or not event.pressed:
		return
	# Settings › Controller remaps: match on the canonical button of the role
	# the pressed physical button carries.
	match PadBindings.canonical(event.button_index):
		JOY_BUTTON_DPAD_UP:
			_pad_step_list(weapon_list, -1)
			set_input_as_handled()
		JOY_BUTTON_DPAD_DOWN:
			_pad_step_list(weapon_list, 1)
			set_input_as_handled()
		JOY_BUTTON_DPAD_LEFT:
			if _pad_step_list(target_list, -1):
				_pad_emit_current_target()
			set_input_as_handled()
		JOY_BUTTON_DPAD_RIGHT:
			if _pad_step_list(target_list, 1):
				_pad_emit_current_target()
			set_input_as_handled()
		JOY_BUTTON_A:
			_pad_assign()
			set_input_as_handled()
		JOY_BUTTON_Y:
			# Ⓨ = All Weapons to Target — the whole unit at the highlighted enemy,
			# each weapon swung only by the models that carry it. Saves a pad
			# player stepping every weapon row of a mixed mob.
			_on_all_to_target_pressed()
			var toast_all := get_node_or_null("/root/ToastManager")
			if toast_all != null:
				toast_all.show_toast("✓ All weapons assigned — ☰ to Fight!")
			set_input_as_handled()
		JOY_BUTTON_START:
			_on_confirmed()
			set_input_as_handled()
		JOY_BUTTON_B:
			# End the fight when the dialog offers it (no-targets escape hatch);
			# otherwise leave B for the dialog's own cancel/close.
			var skip_btn := _find_child_button("SkipFightButton")
			if skip_btn != null and skip_btn.visible and not skip_btn.disabled:
				_on_skip_fight_pressed()
				set_input_as_handled()


# Step an ItemList's single selection with wrap; returns true when it moved.
func _pad_step_list(lst: ItemList, dir: int) -> bool:
	if lst == null or lst.item_count == 0:
		return false
	var sel := lst.get_selected_items()
	var cur: int = sel[0] if not sel.is_empty() else (0 if dir > 0 else lst.item_count - 1)
	var nxt := wrapi(cur + dir, 0, lst.item_count)
	if nxt == cur:
		return false
	lst.select(nxt)
	lst.ensure_current_is_visible()
	return true


# Pad Ⓐ = Add Assignment: assign the selected weapon to the selected target,
# with a toast so a controller player (who can't see the mouse-only display
# refresh at a glance) gets confirmation and knows ☰ resolves the fight.
func _pad_assign() -> void:
	if weapon_list == null or target_list == null:
		return
	if weapon_list.item_count == 0 or target_list.item_count == 0:
		return
	_on_assign_pressed()
	var wsel := weapon_list.get_selected_items()
	var tsel := target_list.get_selected_items()
	if wsel.is_empty() or tsel.is_empty():
		return
	var wname := str(weapon_list.get_item_text(wsel[0])).split(" (")[0]
	var tname := str(target_list.get_item_text(tsel[0])).split(" (")[0]
	var toast := get_node_or_null("/root/ToastManager")
	if toast != null:
		toast.show_toast("✓ %s → %s — ☰ to Fight!" % [wname, tname])


func _find_child_button(node_name: String) -> Button:
	var q: Array = [self]
	while not q.is_empty():
		var n = q.pop_front()
		if n is Button and str(n.name) == node_name:
			return n
		for c in n.get_children():
			q.append(c)
	return null

# =============================================================================
# MA-LOADOUT: per-model melee groups
# =============================================================================

# Build `melee_groups` / `extra_attacks_groups` from what each model ACTUALLY
# carries. RulesEngine.get_unit_melee_weapons resolves the per-model loadout —
# from the roster's wargear where it says something, otherwise from the
# datasheet's default kit per model role — and returns {model key: [weapon name]}.
# Only ELIGIBLE models (in engagement range) can swing, so only they are counted.
func _build_melee_groups(unit: Dictionary, eligible_indices: Array) -> void:
	melee_groups.clear()
	extra_attacks_groups.clear()

	var board = phase_reference.game_state_snapshot if phase_reference != null else {}
	var per_model = RulesEngine.get_unit_melee_weapons(unit_id, board)
	print("[AttackAssignmentDialog] Per-model melee loadouts for %s: %s" % [unit_id, str(per_model)])

	var weapons_by_name := {}
	for w in unit.get("meta", {}).get("weapons", []):
		if str(w.get("type", "")).to_lower() == "melee":
			weapons_by_name[str(w.get("name", ""))] = w

	var order: Array = []
	var carriers := {}
	var roles := {}
	var models = unit.get("models", [])
	var model_profiles = unit.get("meta", {}).get("model_profiles", {})
	for model_key in per_model:
		var idx := _model_key_to_index(str(model_key))
		if idx < 0 or not idx in eligible_indices:
			continue
		var role := ""
		if idx < models.size():
			var mt = str(models[idx].get("model_type", ""))
			if mt != "" and model_profiles.has(mt):
				role = str(model_profiles[mt].get("label", mt))
			elif mt != "":
				role = mt
		for wname in per_model[model_key]:
			var n := str(wname)
			if not carriers.has(n):
				carriers[n] = []
				roles[n] = []
				order.append(n)
			carriers[n].append(idx)
			if role != "" and role not in roles[n]:
				roles[n].append(role)

	for n in order:
		var weapon = weapons_by_name.get(n, {})
		if weapon.is_empty():
			print("[AttackAssignmentDialog] WARNING: model carries '%s' but the datasheet has no such melee profile — skipped" % n)
			continue
		var group := {
			"weapon_id": RulesEngine.generate_weapon_id(n, "Melee"),
			"name": n,
			"weapon": weapon,
			"models": carriers[n],
			"roles": roles[n],
		}
		if RulesEngine.weapon_data_has_extra_attacks(weapon):
			extra_attacks_groups.append(group)
		else:
			melee_groups.append(group)

	# Safety net: never leave a unit unable to fight because the per-model lookup
	# came back empty (an unusual roster, a unit with no model entries). Fall back
	# to the datasheet menu with every eligible model, i.e. the old behaviour.
	if melee_groups.is_empty() and extra_attacks_groups.is_empty():
		print("[AttackAssignmentDialog] No per-model melee data for %s — falling back to the datasheet weapon list" % unit_id)
		for wname in weapons_by_name:
			var weapon = weapons_by_name[wname]
			var group := {
				"weapon_id": RulesEngine.generate_weapon_id(str(wname), "Melee"),
				"name": str(wname),
				"weapon": weapon,
				"models": eligible_indices.duplicate(),
				"roles": [],
			}
			if RulesEngine.weapon_data_has_extra_attacks(weapon):
				extra_attacks_groups.append(group)
			else:
				melee_groups.append(group)


# RulesEngine.get_unit_melee_weapons keys models as "m<index>"; tolerate a bare
# index too. -1 when the key is neither.
func _model_key_to_index(key: String) -> int:
	if key.begins_with("m") and key.substr(1).is_valid_int():
		return key.substr(1).to_int()
	if key.is_valid_int():
		return key.to_int()
	return -1


func _group_for_weapon(weapon_id: String) -> Dictionary:
	for g in melee_groups:
		if str(g.weapon_id) == weapon_id:
			return g
	for g in extra_attacks_groups:
		if str(g.weapon_id) == weapon_id:
			return g
	return {}


# Model indices already committed to a regular melee weapon this activation.
func _committed_model_indices() -> Dictionary:
	var out := {}
	for assignment in assignments:
		for ref in assignment.get("models", []):
			out[int(str(ref))] = true
	return out


# Model refs in the form the fight engine matches: index strings.
func _model_refs(indices: Array) -> Array:
	var out: Array = []
	for idx in indices:
		out.append(str(idx))
	return out


# "Boss Nob" / "Boy" / "models" — who is holding this weapon.
func _role_summary(group: Dictionary) -> String:
	var roles = group.get("roles", [])
	if roles.is_empty():
		return "model" if group.get("models", []).size() == 1 else "models"
	return ", ".join(PackedStringArray(roles))


func _group_max_attacks(group: Dictionary) -> float:
	var avg: float = _average_dice_notation(str(group.weapon.get("attacks", "1")))
	return avg * float(group.get("models", []).size())


# The unit's attack ceiling: every eligible model swings the best weapon IT
# carries (plus any Extra Attacks weapon, which is used in addition). Summing
# per model is the whole point — one weapon's A × the whole unit was the old,
# wrong figure.
func _unit_max_attacks(eligible_indices: Array) -> float:
	var best_per_model := {}
	for idx in eligible_indices:
		best_per_model[idx] = 0.0
	for g in melee_groups:
		var avg: float = _average_dice_notation(str(g.weapon.get("attacks", "1")))
		for idx in g.models:
			if best_per_model.has(idx):
				best_per_model[idx] = maxf(float(best_per_model[idx]), avg)
	var total: float = 0.0
	for idx in best_per_model:
		total += float(best_per_model[idx])
	for g in extra_attacks_groups:
		total += _group_max_attacks(g)
	return total


func _fmt_num(v: float) -> String:
	return "%.1f" % v if v != floor(v) else "%d" % int(v)


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

	var weapon_id = str(weapon_list.get_item_metadata(weapon_idx[0]))
	var target_id = str(target_list.get_item_metadata(target_idx[0]))

	_assign_weapon_to_target(weapon_id, target_id)

# 11e Fight — Select Weapons: the choice is per MODEL, so an assignment covers a
# weapon and the models that carry it. Re-assigning a weapon already in the list
# just re-targets it; a DIFFERENT weapon claims the carriers that have not
# committed to one yet, so the Boss Nob's big choppa and the Boyz' choppas both
# swing (a model still fights with exactly ONE melee weapon).
#
# `allow_switch` covers the other case: when every carrier is ALREADY swinging
# something else, an explicit "assign THIS weapon" is a change of mind (a lone
# Warboss picking his power klaw over his big choppa), so those models are taken
# off their current weapon. The bulk "All Weapons to Target" path passes false —
# it fills the gaps and must never cannibalise the groups it just assigned.
# Returns true when something was assigned/re-targeted.
func _assign_weapon_to_target(weapon_id: String, target_id: String, allow_switch: bool = true) -> bool:
	var group = _group_for_weapon(weapon_id)
	if group.is_empty():
		push_warning("No models carry %s" % weapon_id)
		print("[AttackAssignmentDialog] No eligible model carries '%s' — nothing to assign" % weapon_id)
		return false

	for assignment in assignments:
		if str(assignment.get("weapon", "")) == weapon_id:
			print("[AttackAssignmentDialog] Re-targeting %s: %s → %s" % [
				weapon_id, str(assignment.get("target", "?")), target_id])
			assignment["target"] = target_id
			_update_assignments_display()
			return true

	var committed = _committed_model_indices()
	var claimed: Array = []
	for idx in group.models:
		if not committed.has(idx):
			claimed.append(idx)

	if claimed.is_empty():
		if not allow_switch:
			print("[AttackAssignmentDialog] '%s' skipped — all %d carrier(s) already assigned another melee weapon" % [
				str(group.name), group.models.size()])
			return false
		# Switch: take the carriers off whatever they were swinging.
		claimed = group.models.duplicate()
		_release_models(claimed)
		print("[AttackAssignmentDialog] One weapon per model: %d model(s) switched to '%s'" % [
			claimed.size(), str(group.name)])

	assignments.append({
		"attacker": unit_id,
		"weapon": weapon_id,
		"target": target_id,
		# Model INDEX strings — the form RulesEngine._resolve_melee_assignment_hits
		# matches (`str(model_index) in attacking_models`), so only these models
		# swing this weapon instead of the whole unit.
		"models": _model_refs(claimed)
	})
	print("[AttackAssignmentDialog] Assignment: %s → %s (%d model(s) %s)" % [
		weapon_id, target_id, claimed.size(), str(claimed)])
	print("[AttackAssignmentDialog] Total assignments: ", assignments.size())
	_update_assignments_display()
	return true


# Drop `indices` from every existing assignment, discarding assignments left with
# no models (that weapon is no longer being swung by anyone).
func _release_models(indices: Array) -> void:
	var drop := {}
	for idx in indices:
		drop[str(idx)] = true
	var kept: Array = []
	for assignment in assignments:
		var remaining: Array = []
		for ref in assignment.get("models", []):
			if not drop.has(str(ref)):
				remaining.append(ref)
		if remaining.is_empty():
			print("[AttackAssignmentDialog] Dropped assignment %s → %s (no models left on it)" % [
				str(assignment.get("weapon", "?")), str(assignment.get("target", "?"))])
			continue
		assignment["models"] = remaining
		kept.append(assignment)
	assignments = kept

# T5-UX5 (reworked for per-model loadouts): send EVERY weapon the unit carries at
# the selected target in one click. Previously this assigned a single weapon to
# the whole unit, which made a 9-choppa mob swing 10 power klaws.
func _on_all_to_target_pressed() -> void:
	print("[AttackAssignmentDialog] T5-UX5: 'All Weapons to Target' button pressed")

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

	var target_id = str(target_list.get_item_metadata(target_idx[0]))

	# Selected weapon first so its models are claimed before any overlapping
	# group takes them — a player who picked a row expects that row to be used.
	var order: Array = []
	var weapon_idx = weapon_list.get_selected_items()
	if not weapon_idx.is_empty():
		order.append(str(weapon_list.get_item_metadata(weapon_idx[0])))
	for g in melee_groups:
		if str(g.weapon_id) not in order:
			order.append(str(g.weapon_id))

	var assigned := 0
	for wid in order:
		# allow_switch = false: filling every group must not steal models back off
		# a group assigned a moment earlier in this same loop.
		if _assign_weapon_to_target(wid, target_id, false):
			assigned += 1
	print("[AttackAssignmentDialog] T5-UX5: %d of %d weapon group(s) assigned → '%s'" % [
		assigned, melee_groups.size(), target_id])

func _on_clear_assignments_pressed() -> void:
	print("[AttackAssignmentDialog] Clearing %d assignment(s)" % assignments.size())
	assignments.clear()
	_update_assignments_display()

func _update_assignments_display() -> void:
	if not assignments_display:
		return

	assignments_display.clear()
	var total_expected_damage: float = 0.0
	var assigned_models := {}
	for assignment in assignments:
		var wid := str(assignment.get("weapon", ""))
		var n_models: int = assignment.get("models", []).size()
		for ref in assignment.get("models", []):
			assigned_models[str(ref)] = true
		var g = _group_for_weapon(wid)
		var wname := str(g.get("name", wid)) if not g.is_empty() else wid
		var ed: float = _estimate_expected_damage(wid, str(assignment.get("target", "")), n_models)
		total_expected_damage += ed
		# T-093: include expected damage estimate per assignment
		assignments_display.append_text("- %s ×%d → %s [E[D]≈%.1f]\n" % [
			wname, n_models, str(assignment.get("target", "")), ed])

	# T3-3: Show Extra Attacks auto-assignments preview
	if not extra_attacks_groups.is_empty():
		var ea_target_id = _get_extra_attacks_target_id()
		for g in extra_attacks_groups:
			var ed: float = _estimate_expected_damage(str(g.weapon_id), ea_target_id, g.models.size())
			total_expected_damage += ed
			assignments_display.append_text("- %s ×%d → %s [Extra Attacks, E[D]≈%.1f]\n" % [
				str(g.name), g.models.size(), ea_target_id, ed])
	if total_expected_damage > 0.0:
		assignments_display.append_text("[b]Total expected damage: %.1f[/b]\n" % total_expected_damage)

	# Nudge when models are still standing around with nothing to swing at — with
	# per-model weapons an unassigned model simply does not attack.
	var carriers := {}
	for g in melee_groups:
		for idx in g.models:
			carriers[str(idx)] = true
	var idle := 0
	for ref in carriers:
		if not assigned_models.has(ref):
			idle += 1
	if idle > 0 and not assignments.is_empty():
		assignments_display.append_text("[i]%d model(s) still unassigned — they will not attack.[/i]\n" % idle)


# T-093: analytic expected-damage estimator for AttackAssignmentDialog preview.
# Uses standard Warhammer 10e math: E[D] = A * Phit * Pwound * Punsaved * D
# where probability functions parse weapon profile + defender stats.
# `model_count` is how many models actually swing this weapon (-1 = every alive
# model, the pre-per-model-loadout behaviour kept for any other caller).
func _estimate_expected_damage(weapon_id: String, target_id: String, model_count: int = -1) -> float:
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
	# Total attacks = per-weapon-attacks × the models that ACTUALLY carry this
	# weapon (MA-LOADOUT). It used to be every alive model for every weapon, so a
	# 9-choppa mob's power-klaw row previewed 10 klaw attacks.
	var swinging_count: int = model_count
	if swinging_count < 0:
		swinging_count = 0
		for m in attacker_unit.get("models", []):
			if m.get("alive", true):
				swinging_count += 1
	# Treat per-model A as a single shooter; UI is a preview not a simulation
	var total_attacks: float = attacks_avg * float(max(1, swinging_count))
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

	# T3-3: Auto-include Extra Attacks weapons in assignments — restricted to the
	# models that carry them, like every other weapon (MA-LOADOUT).
	if not extra_attacks_groups.is_empty():
		var ea_target_id = _get_extra_attacks_target_id()
		for g in extra_attacks_groups:
			assignments.append({
				"attacker": unit_id,
				"weapon": str(g.weapon_id),
				"target": ea_target_id,
				"models": _model_refs(g.models)
			})
			print("[AttackAssignmentDialog] T3-3: Auto-added Extra Attacks weapon '%s' → '%s' (%d model(s) %s)" % [
				str(g.name), ea_target_id, g.models.size(), str(g.models)])

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
