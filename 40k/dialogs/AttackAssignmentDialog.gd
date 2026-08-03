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

# MA-LOADOUT (melee): who can swing what. `_eligible_models` is every model
# that may fight this activation; `_weapon_carriers` maps a weapon id to the
# subset of those models actually equipped with it (RulesEngine applies the same
# filter when the attacks resolve). Before this the dialog offered the unit's
# whole datasheet menu to every model, so picking the Boss Nob's Power klaw gave
# all ten Boyz one.
#
# 19.03 — ONE dialog for the whole ATTACHED unit. A CHARACTER attached to a
# bodyguard fights in the SAME activation, so the models here span more than one
# unit dict. Each is addressed by a MODEL KEY "<unit_id>#<model index>"; the
# index alone is ambiguous once two components are in play (the Warboss's only
# model is index 0 just as the first Boy is). Assignments are split back out per
# component on the way to the phase, because RulesEngine resolves each against
# its own `attacker` — that is what keeps the leader's stats, abilities and
# weapon profile his own instead of his bodyguard's.
var _eligible_models: Array = []        # Array[String] model keys
var _weapon_carriers: Dictionary = {}   # weapon_id -> Array[String] model keys
var _weapon_by_id: Dictionary = {}      # weapon_id -> weapon profile dictionary
var _model_key_unit: Dictionary = {}    # model key -> owning component unit id
var _group_unit_ids: Array = []         # component unit ids, bodyguard first

# "<unit_id>#<index>" — see _eligible_models.
static func _mk(unit_id: String, model_index: int) -> String:
	return "%s#%d" % [unit_id, model_index]

static func _mk_unit(model_key: String) -> String:
	var sep := model_key.rfind("#")
	return model_key.substr(0, sep) if sep > 0 else model_key

static func _mk_index(model_key: String) -> String:
	var sep := model_key.rfind("#")
	return model_key.substr(sep + 1) if sep > 0 else model_key

func setup(fighter_id: String, targets: Dictionary, phase) -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	print("[AttackAssignmentDialog] Setup called for unit: ", fighter_id)
	print("[AttackAssignmentDialog] Targets: ", targets.keys())

	unit_id = fighter_id
	eligible_targets = targets
	phase_reference = phase

	# 19.03: name the whole ATTACHED unit ("Boyz + Warboss") — this one dialog
	# assigns the attacks of every component, so titling it with the bodyguard
	# alone hid the fact that the leader swings here too.
	var _aad_meta = phase.get_unit(unit_id).get("meta", {})
	var _aad_name = str(_aad_meta.get("display_name", _aad_meta.get("name", unit_id)))
	if phase.has_method("_fight_attached_display_name"):
		_aad_name = phase._fight_attached_display_name(unit_id)
	title = "Assign Attacks: %s" % _aad_name

	print("[AttackAssignmentDialog] Building UI...")
	_build_ui()
	print("[AttackAssignmentDialog] UI built successfully")

func _build_ui() -> void:
	min_size = DialogConstants.MEDIUM
	var container = VBoxContainer.new()
	container.name = "Content"
	container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	# 19.03: the activation covers the whole ATTACHED unit — the bodyguard AND
	# every CHARACTER attached to it. Everything below walks the components.
	_group_unit_ids = RulesEngine.attached_unit_component_ids(unit_id, phase_reference.game_state_snapshot)
	var unit = phase_reference.get_unit(unit_id)

	# Show eligible model count (per 10e: only models in engagement range can
	# fight) across the whole Attached unit.
	_eligible_models = []
	_model_key_unit = {}
	var alive_count = 0
	for member_id in _group_unit_ids:
		var member = phase_reference.get_unit(member_id)
		for idx in RulesEngine.get_eligible_melee_model_indices(member, phase_reference.game_state_snapshot):
			var key := _mk(member_id, int(idx))
			_eligible_models.append(key)
			_model_key_unit[key] = member_id
		for model in member.get("models", []):
			if model.get("alive", true):
				alive_count += 1

	var instruction = Label.new()
	if _eligible_models.size() < alive_count:
		instruction.text = "Models in engagement range: %d/%d" % [_eligible_models.size(), alive_count]
	else:
		instruction.text = "All %d models in engagement range" % alive_count
	container.add_child(instruction)

	# T3-3: Separate melee weapons into regular and Extra Attacks. Both lists
	# span the Attached unit's components.
	var regular_melee_weapons = []
	extra_attacks_weapons = []
	var seen_weapon_ids := {}   # two components listing the same weapon is ONE row
	for member_id in _group_unit_ids:
		var member = phase_reference.get_unit(member_id)
		for weapon in member.get("meta", {}).get("weapons", []):
			if weapon.get("type", "").to_lower() != "melee":
				continue
			var seen_id = RulesEngine.generate_weapon_id(weapon.get("name", ""), weapon.get("type", ""))
			if seen_weapon_ids.has(seen_id):
				continue
			seen_weapon_ids[seen_id] = true
			if RulesEngine.weapon_data_has_extra_attacks(weapon):
				extra_attacks_weapons.append(weapon)
				print("[AttackAssignmentDialog] Extra Attacks weapon: ", weapon.get("name", "Unknown"))
			else:
				regular_melee_weapons.append(weapon)
				print("[AttackAssignmentDialog] Regular melee weapon: ", weapon.get("name", "Unknown"))

	print("[AttackAssignmentDialog] Regular melee weapons: %d, Extra Attacks weapons: %d" % [regular_melee_weapons.size(), extra_attacks_weapons.size()])

	# MA-LOADOUT (melee): work out who carries what before listing anything, and
	# drop weapons no eligible model is equipped with — the menu used to be the
	# unit's whole datasheet, so a mob was offered its Boss Nob's Power klaw as
	# though every model had one.
	_weapon_carriers = {}
	_weapon_by_id = {}
	var carried_melee_weapons: Array = []
	for weapon in regular_melee_weapons:
		var wid = RulesEngine.generate_weapon_id(weapon.get("name", ""), weapon.get("type", ""))
		if _weapon_carriers.has(wid):
			continue  # already collected from an earlier component
		# A weapon the roster never bought is on no model at all. The datasheet
		# lists it because it is an OPTION — an Ork mob's Power klaw and Close
		# combat weapon are alternatives to the choppas it actually took — and
		# offering them let a player swing weapons the unit does not own.
		# (Before a unit's loadout can be resolved every model reports the whole
		# menu, so this hides nothing.)
		var carriers: Array = []
		for member_id in _group_unit_ids:
			var member = phase_reference.get_unit(member_id)
			if not RulesEngine.unit_has_melee_weapon(member, wid):
				continue
			var member_eligible: Array = []
			for key in _eligible_models:
				if _model_key_unit.get(key, "") == member_id:
					member_eligible.append(int(_mk_index(key)))
			# The engine falls back to "everyone" for a weapon it cannot
			# attribute; that is the unresolvable case, and listing it is still
			# correct.
			for idx in RulesEngine.get_melee_weapon_swingers(member, wid, member_eligible, []):
				carriers.append(_mk(member_id, int(idx)))
		if carriers.is_empty():
			print("[AttackAssignmentDialog] '%s' has no eligible carrier — omitted" % weapon.get("name", "?"))
			continue
		_weapon_carriers[wid] = carriers
		_weapon_by_id[wid] = weapon
		carried_melee_weapons.append(weapon)
	regular_melee_weapons = carried_melee_weapons

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
	# swings per activation, so the cap is the best single choice — not the sum.
	# MA-LOADOUT: "attacks with this weapon" is now the CARRIERS' attacks, and a
	# choice also sweeps every other eligible model into the weapon it does
	# carry (see _set_single_weapon_assignment), so the cap is the best whole
	# plan rather than one weapon times the whole unit.
	var unit_max_attacks_best: float = 0.0
	for i in range(regular_melee_weapons.size()):
		var weapon = regular_melee_weapons[i]
		var weapon_name = weapon.get("name", "Unknown")
		# Generate weapon ID from name using RulesEngine to prevent collisions
		var weapon_id = RulesEngine.generate_weapon_id(weapon_name, weapon.get("type", ""))

		var carriers: Array = _weapon_carriers.get(weapon_id, [])
		var avg_attacks: float = _average_dice_notation(str(weapon.get("attacks", "1")))
		var weapon_max_attacks: float = avg_attacks * float(carriers.size())
		unit_max_attacks_best = maxf(unit_max_attacks_best, _plan_total_attacks(weapon_id))

		# 19.03: with an Attached unit the list mixes both components' weapons,
		# so name whose it is — "Power klaw … [Warboss]" next to the Boyz'
		# choppas. Read the owner off the actual CARRIERS, not the datasheet:
		# an Ork mob lists a Power klaw as a wargear OPTION it did not take, so
		# "which datasheet mentions it first" names the wrong unit. A lone unit
		# keeps its old, shorter row.
		var owner_suffix := ""
		if _group_unit_ids.size() > 1:
			var owner_id := ""
			for key in carriers:
				var carrier_unit: String = _mk_unit(str(key))
				if owner_id == "":
					owner_id = carrier_unit
				elif owner_id != carrier_unit:
					owner_id = ""   # carried across components — no single owner
					break
			if owner_id != "" and owner_id != unit_id:
				var owner_meta = phase_reference.get_unit(owner_id).get("meta", {})
				owner_suffix = " [%s]" % str(owner_meta.get("display_name", owner_meta.get("name", owner_id)))

		weapon_list.add_item("%s (A:%s S:%s AP:%s D:%s — %s, ≈%s attacks)%s" % [
			weapon_name,
			weapon.get("attacks", "1"),
			weapon.get("strength", "User"),
			weapon.get("ap", "0"),
			weapon.get("damage", "1"),
			"%d model%s" % [carriers.size(), "" if carriers.size() == 1 else "s"],
			"%.1f" % weapon_max_attacks if weapon_max_attacks != floor(weapon_max_attacks) else "%d" % int(weapon_max_attacks),
			owner_suffix
		])
		# Store the weapon ID as metadata for creating the attack action
		weapon_list.set_item_metadata(weapon_list.item_count - 1, weapon_id)
		print("[AttackAssignmentDialog] Weapon '%s' → ID '%s' (%d carrier(s), ≈%.1f attacks)" % [
			weapon_name, weapon_id, carriers.size(), weapon_max_attacks])

	# Pre-select the first weapon so a default choice is always visible
	if weapon_list.item_count > 0:
		weapon_list.select(0)

	# T-093: max-cap label (best whole plan — one melee weapon per model)
	var max_cap_label = Label.new()
	max_cap_label.text = "Max total attacks (cap): ≈%s across %d eligible models, each swinging a weapon it carries" % [
		"%.1f" % unit_max_attacks_best if unit_max_attacks_best != floor(unit_max_attacks_best) else "%d" % int(unit_max_attacks_best),
		_eligible_models.size()
	]
	max_cap_label.add_theme_font_size_override("font_size", 16)
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

	# Pad (controller) hint row — the melee twin of the shooting phase's target
	# ring, spelled out for a controller. Shown only when the pad is the active
	# device; a mouse player never sees it. See _pad_handle_input.
	_pad_hint_label = Label.new()
	_pad_hint_label.name = "PadHintLabel"
	_pad_hint_label.text = "▲▼ Weapon   ·   ◀▶ Target   ·   Ⓐ Assign   ·   ☰ Fight!   ·   Ⓑ Skip"
	_pad_hint_label.add_theme_font_size_override("font_size", 16)
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
#   ▲ ▼   step the weapon list   (one melee weapon per model — 11e)
#   ◀ ▶   step the target list   (updates the board reticle via the signal)
#   Ⓐ     Add Assignment          (assign the selected weapon → target)
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

# 11e one-weapon rule: every model fights with ONE melee weapon, and it has to
# be one that model is equipped with. Picking a weapon therefore sets the whole
# unit's plan, not one assignment: its CARRIERS swing it, and every other
# eligible model swings the best weapon it does carry, at the same target. A new
# pick replaces the whole plan.
#
# Previously this appended a single weapon assignment with no model list, which
# the engine then applied to every eligible model — the Boss Nob's Power klaw in
# all ten Boyz' hands. Model lists are index strings, which is what
# RulesEngine's `attacking_models` and FightPhase's one-weapon-rule validator
# both expect (disjoint lists per weapon, so they never conflict).
func _set_single_weapon_assignment(weapon_id: String, target_id: String) -> void:
	if not assignments.is_empty():
		var previous = assignments[0]
		print("[AttackAssignmentDialog] One-weapon rule: replacing plan %s → %s with %s → %s" % [
			previous.get("weapon", "?"), previous.get("target", "?"), weapon_id, target_id])
	assignments.clear()

	# 19.03: one plan for the whole Attached unit, emitted as one assignment per
	# (component, weapon) — the engine resolves each against its own `attacker`,
	# and the models in it are indices into THAT component's model list.
	for entry in _build_weapon_plan(weapon_id):
		var by_unit := {}
		for key in entry.models:
			var owner_id: String = _mk_unit(str(key))
			if not by_unit.has(owner_id):
				by_unit[owner_id] = []
			by_unit[owner_id].append(_mk_index(str(key)))
		for owner_id in by_unit:
			assignments.append({
				"attacker": owner_id,
				"weapon": entry.weapon,
				"target": target_id,
				"models": by_unit[owner_id]
			})
			print("[AttackAssignmentDialog] Assignment: %s swings %s → %s (%d model(s): %s)" % [
				owner_id, entry.weapon, target_id, by_unit[owner_id].size(), str(by_unit[owner_id])])

	print("[AttackAssignmentDialog] Total assignments: ", assignments.size())
	_update_assignments_display()


# The per-weapon groups a choice of `weapon_id` produces:
# [{weapon: String, models: Array[String]}], chosen weapon first, where models
# are MODEL KEYS spanning the Attached unit. Every eligible model appears
# exactly once — carriers of the pick get it, the rest get their own best melee
# weapon (an unarmed model simply drops out). That "rest" is how an attached
# CHARACTER joins the swing when the player picks his bodyguard's weapon: the
# Warboss is not a Choppa carrier, so he swings his power klaw in the same
# activation instead of being left out of it.
func _build_weapon_plan(weapon_id: String) -> Array:
	var chosen_carriers: Array = _weapon_carriers.get(weapon_id, [])
	var plan: Array = []
	var covered: Dictionary = {}
	if not chosen_carriers.is_empty():
		var chosen_models: Array = []
		for key in chosen_carriers:
			chosen_models.append(str(key))
			covered[str(key)] = true
		plan.append({"weapon": weapon_id, "models": chosen_models})

	# Everyone else swings what they have. Group by weapon so the batch stays
	# one ASSIGN_ATTACKS per weapon rather than one per model.
	var leftovers: Dictionary = {}  # weapon_id -> Array[String] model keys
	for key in _eligible_models:
		if covered.has(str(key)):
			continue
		var best := _best_weapon_for_model(str(key), weapon_id)
		if best == "":
			continue
		if not leftovers.has(best):
			leftovers[best] = []
		leftovers[best].append(str(key))
	for wid in leftovers:
		plan.append({"weapon": wid, "models": leftovers[wid]})
	return plan


# Total attacks a choice of `weapon_id` would produce across the whole unit —
# the chosen weapon's carriers plus everyone else on their own weapon. Drives
# the "Max total attacks (cap)" line so it reflects the real plan.
func _plan_total_attacks(weapon_id: String) -> float:
	var total: float = 0.0
	for entry in _build_weapon_plan(weapon_id):
		var w: Dictionary = _weapon_by_id.get(entry.weapon, {})
		total += _average_dice_notation(str(w.get("attacks", "1"))) * float(entry.models.size())
	return total


# The melee weapon a model should swing when the player's pick is not one it
# carries: the highest average attacks x damage it has, strength breaking ties.
# Deterministic, so the same mob always resolves the same way.
# Model keys of every eligible model across the Attached unit that carries
# weapon_id. Used for weapons that are not in `_weapon_carriers` (the
# [EXTRA ATTACKS] previews), which is built from the regular list only.
#
# [EXTRA ATTACKS] needs the datasheet fallback below: loadout resolution keeps
# only the ONE melee weapon a model fights with, so an extra-attacks weapon is
# NOT in any model's resolved loadout and unit_has_melee_weapon reports false
# for it. Attributing by datasheet instead keeps the Warboss's attack squig on
# the Warboss — filed under his Boyz it would have been handed to all ten of
# them, because the engine falls back to "every eligible model" for a weapon it
# cannot attribute to the named unit.
func _carriers_across_group(weapon_id: String) -> Array:
	if _weapon_carriers.has(weapon_id):
		return _weapon_carriers[weapon_id]
	var out: Array = []
	for member_id in _group_unit_ids:
		var member = phase_reference.get_unit(member_id)
		var member_eligible: Array = []
		for key in _eligible_models:
			if _model_key_unit.get(key, "") == member_id:
				member_eligible.append(int(_mk_index(str(key))))
		if member_eligible.is_empty():
			continue
		if RulesEngine.unit_has_melee_weapon(member, weapon_id):
			for idx in RulesEngine.get_melee_weapon_swingers(member, weapon_id, member_eligible, []):
				out.append(_mk(member_id, int(idx)))
			continue
		if not _unit_datasheet_lists_weapon(member, weapon_id):
			continue
		for idx in member_eligible:
			out.append(_mk(member_id, int(idx)))
	return out

# True when this component's datasheet names weapon_id at all — see
# _carriers_across_group for why the resolved loadout is not enough.
func _unit_datasheet_lists_weapon(unit: Dictionary, weapon_id: String) -> bool:
	for w in unit.get("meta", {}).get("weapons", []):
		if RulesEngine.generate_weapon_id(w.get("name", ""), w.get("type", "")) == weapon_id:
			return true
	return false


func _best_weapon_for_model(model_key: String, exclude_weapon_id: String) -> String:
	var best_id := ""
	var best_score := -1.0
	for wid in _weapon_carriers:
		if wid == exclude_weapon_id:
			continue
		if not model_key in _weapon_carriers[wid]:
			continue
		var w: Dictionary = _weapon_by_id.get(wid, {})
		var score: float = _average_dice_notation(str(w.get("attacks", "1"))) \
			* _average_dice_notation(str(w.get("damage", "1"))) * 100.0 \
			+ float(_parse_stat_int(str(w.get("strength", "0"))))
		if score > best_score:
			best_score = score
			best_id = wid
	return best_id

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
		# MA-LOADOUT: each line is one weapon and the models that actually carry
		# it, so name the count — "Power klaw (1 model)" next to "Choppa
		# (9 models)" is the whole point of the plan.
		var swinging: int = (assignment.get("models", []) as Array).size()
		var ed: float = _estimate_expected_damage(assignment.weapon, assignment.target, swinging)
		total_expected_damage += ed
		# T-093: include expected damage estimate per assignment
		assignments_display.append_text("- %s → %s (%d model%s) [E[D]≈%.1f]\n" % [
			assignment.weapon, assignment.target, swinging, "" if swinging == 1 else "s", ed])

	# T3-3: Show Extra Attacks auto-assignments preview
	if not extra_attacks_weapons.is_empty():
		var ea_target_id = _get_extra_attacks_target_id()
		for weapon in extra_attacks_weapons:
			var weapon_name = weapon.get("name", "Unknown")
			var weapon_id = RulesEngine.generate_weapon_id(weapon_name, weapon.get("type", ""))
			# 19.03: count the [EXTRA ATTACKS] carriers across every component of
			# the Attached unit (the Warboss's attack squig swings with his Boyz).
			var ea_carriers: Array = _carriers_across_group(weapon_id)
			var ed: float = _estimate_expected_damage(weapon_id, ea_target_id, ea_carriers.size())
			total_expected_damage += ed
			assignments_display.append_text("- %s → %s (%d model%s) [Extra Attacks, E[D]≈%.1f]\n" % [
				weapon_name, ea_target_id, ea_carriers.size(), "" if ea_carriers.size() == 1 else "s", ed])
	if total_expected_damage > 0.0:
		assignments_display.append_text("[b]Total expected damage: %.1f[/b]\n" % total_expected_damage)


# T-093: analytic expected-damage estimator for AttackAssignmentDialog preview.
# Uses standard Warhammer 10e math: E[D] = A * Phit * Pwound * Punsaved * D
# where probability functions parse weapon profile + defender stats.
func _estimate_expected_damage(weapon_id: String, target_id: String, swinging_models: int = -1) -> float:
	if phase_reference == null or unit_id == "" or target_id == "":
		return 0.0
	var attacker_unit = phase_reference.get_unit(unit_id)
	var target_unit = phase_reference.get_unit(target_id)
	if attacker_unit.is_empty() or target_unit.is_empty():
		return 0.0
	# Find weapon. 19.03: search every component of the Attached unit — the
	# attached leader's power klaw is not on his bodyguard's datasheet, and
	# without this its forecast row silently read 0.
	var weapon: Dictionary = {}
	for member_id in (_group_unit_ids if not _group_unit_ids.is_empty() else [unit_id]):
		var member = phase_reference.get_unit(member_id)
		for w in member.get("meta", {}).get("weapons", []):
			var wname = w.get("name", "")
			var wid = RulesEngine.generate_weapon_id(wname, w.get("type", ""))
			if wid == weapon_id or wname == weapon_id:
				weapon = w
				break
		if not weapon.is_empty():
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
	# Total attacks = per-weapon attacks x the models actually swinging it.
	# MA-LOADOUT: the caller passes that count (the assignment's model list), so
	# the preview no longer multiplies a one-model Power klaw by the whole mob.
	# Fall back to the eligible-and-equipped count when it is not supplied.
	var swinging: int = swinging_models
	if swinging < 0:
		swinging = _carriers_across_group(weapon_id).size()
	var total_attacks: float = attacks_avg * float(max(1, swinging))
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


# Handles "1", "3", "D6", "2D3", "D6+1", "2D6". Delegates to the engine so the
# dialog's weapon ranking and FightPhase's auto-pick for an attached component
# cannot drift apart.
func _average_dice_notation(s: String) -> float:
	return RulesEngine.average_dice_notation(s)


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

	# T3-3: Auto-include Extra Attacks weapons in assignments.
	# 19.03: attribute each one to the component that actually CARRIES it. The
	# Warboss's attack squig is not on his Boyz' datasheet, and filing it under
	# the bodyguard handed the whole mob one — RulesEngine falls back to "every
	# model" for a weapon it cannot attribute to the named unit.
	if not extra_attacks_weapons.is_empty():
		var ea_target_id = _get_extra_attacks_target_id()
		for weapon in extra_attacks_weapons:
			var weapon_name = weapon.get("name", "Unknown")
			var weapon_id = RulesEngine.generate_weapon_id(weapon_name, weapon.get("type", ""))
			var by_unit := {}
			for key in _carriers_across_group(weapon_id):
				var owner_id: String = _mk_unit(str(key))
				if not by_unit.has(owner_id):
					by_unit[owner_id] = []
				by_unit[owner_id].append(_mk_index(str(key)))
			if by_unit.is_empty():
				# Unattributable — keep the historical whole-unit form and let
				# the engine narrow it.
				assignments.append({
					"attacker": unit_id,
					"weapon": weapon_id,
					"target": ea_target_id
				})
				print("[AttackAssignmentDialog] T3-3: Auto-added Extra Attacks weapon '%s' → '%s' (whole unit)" % [weapon_name, ea_target_id])
				continue
			for owner_id in by_unit:
				assignments.append({
					"attacker": owner_id,
					"weapon": weapon_id,
					"target": ea_target_id,
					"models": by_unit[owner_id]
				})
				print("[AttackAssignmentDialog] T3-3: Auto-added Extra Attacks weapon '%s' for %s (%d model(s)) → '%s'" % [
					weapon_name, owner_id, by_unit[owner_id].size(), ea_target_id])

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
