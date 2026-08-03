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
# COMPAT: `weapon_list` is the FOCUSED loadout group's weapon ItemList. Before
# the group rework there was exactly one list for the whole unit; single-model
# units (the common scenario fixture) still produce exactly one group, so
# `weapon_list.item_count` / `.select(i)` keep meaning what they always did.
var weapon_list: ItemList = null
var target_list: ItemList = null
var assignments_display: RichTextLabel = null
var extra_attacks_weapons: Array = []  # T3-3: Track Extra Attacks weapons for auto-inclusion
var extra_attacks_target_list: ItemList = null  # T3-3: Target selector for Extra Attacks weapons
var all_to_target_button: Button = null  # T5-UX5: "All to Target" shortcut button
var best_krump_button: Button = null  # Auto-assign the best weapon per group
var _pad_hint_label: Label = null  # Controller hint row (shown only when a pad is active)

# MA-LOADOUT (melee): who can swing what. `_eligible_indices` is every model
# that may fight this activation; `_weapon_carriers` maps a weapon id to the
# subset of those models actually equipped with it (RulesEngine applies the same
# filter when the attacks resolve). Before this the dialog offered the unit's
# whole datasheet menu to every model, so picking the Boss Nob's Power klaw gave
# all ten Boyz one.
var _eligible_indices: Array = []
var _weapon_carriers: Dictionary = {}   # weapon_id -> Array[int] model indices
var _weapon_by_id: Dictionary = {}      # weapon_id -> weapon profile dictionary

# ── LOADOUT GROUPS (Option B) ───────────────────────────────────────────────
# The unit is partitioned into groups of models that carry the SAME set of melee
# weapons — a Boyz mob becomes "Boy x9" (Choppa / Close combat weapon) and
# "Boss Nob x1" (Big choppa / Choppa / Power klaw). Each group picks its own
# weapon and its own target, which is what makes "nine Boyz on choppas, the Nob
# on his Power klaw" expressible at all.
#
# Before this, ONE weapon pick drove the whole unit: its carriers swung it and
# every other model was silently auto-assigned a statically-scored "best"
# weapon. That reached only 4 of the 6 whole-group combinations for a Boyz mob,
# never split a group, and never sent two groups at different targets — and it
# never told the player any of that was happening.
#
# Each group carries a `lines` plan: [{weapon, count, target}]. Un-split groups
# hold exactly one line covering every model in the group; "Split" mode expands
# that to one line per weapon the group carries, with per-line model counts that
# always sum to the group size (models inside a group are interchangeable — same
# profile, same weapons — so only the COUNT is a real decision, never *which*).
var _groups: Array = []
var _focused_group: int = 0
var _groups_box: VBoxContainer = null
var _updating_spins: bool = false  # re-entrancy guard for split SpinBox rebalancing

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
	min_size = DialogConstants.LARGE
	var container = VBoxContainer.new()
	container.name = "Content"
	container.custom_minimum_size = Vector2(DialogConstants.LARGE.x - 20, 0)

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

	# MA-LOADOUT (melee): work out who carries what before listing anything, and
	# drop weapons no eligible model is equipped with — the menu used to be the
	# unit's whole datasheet, so a mob was offered its Boss Nob's Power klaw as
	# though every model had one.
	_eligible_indices = eligible_indices
	_weapon_carriers = {}
	_weapon_by_id = {}
	var carried_melee_weapons: Array = []
	for weapon in regular_melee_weapons:
		var wid = RulesEngine.generate_weapon_id(weapon.get("name", ""), weapon.get("type", ""))
		# A weapon the roster never bought is on no model at all. The datasheet
		# lists it because it is an OPTION — an Ork mob's Power klaw and Close
		# combat weapon are alternatives to the choppas it actually took — and
		# offering them let a player swing weapons the unit does not own.
		# (Before a unit's loadout can be resolved every model reports the whole
		# menu, so this hides nothing.)
		if not RulesEngine.unit_has_melee_weapon(unit, wid):
			print("[AttackAssignmentDialog] '%s' is a datasheet option this unit did not take — omitted" % weapon.get("name", "?"))
			continue
		var carriers = RulesEngine.get_melee_weapon_swingers(unit, wid, eligible_indices, [])
		# The engine falls back to "everyone" for a weapon it cannot attribute;
		# that is the unresolvable case, and listing it is still correct.
		if carriers.is_empty():
			print("[AttackAssignmentDialog] '%s' has no eligible carrier — omitted" % weapon.get("name", "?"))
			continue
		_weapon_carriers[wid] = carriers
		_weapon_by_id[wid] = weapon
		carried_melee_weapons.append(weapon)
	regular_melee_weapons = carried_melee_weapons

	# Partition the eligible models into same-loadout groups before any UI is
	# built — the group list IS the shape of the rest of the dialog.
	_build_groups(unit)

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

	# 11e core rules (Fight — Select Melee Weapon): each model makes its attacks
	# with ONE selected melee weapon — the choice below is exclusive PER GROUP.
	var weapon_label = Label.new()
	weapon_label.name = "GroupsHeader"
	if _groups.size() > 1:
		weapon_label.text = "Each section picks ONE melee weapon (a model only fights with one):"
	else:
		weapon_label.text = "Select ONE Weapon (a model only fights with one melee weapon):"
	container.add_child(weapon_label)

	# Group sections live in a scroll box so a mob with several loadouts (or a
	# split group) cannot push the buttons off the bottom of the dialog.
	var groups_scroll = ScrollContainer.new()
	groups_scroll.name = "GroupsScroll"
	groups_scroll.custom_minimum_size = Vector2(DialogConstants.LARGE.x - 40, 260)
	groups_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_groups_box = VBoxContainer.new()
	_groups_box.name = "GroupsBox"
	_groups_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	groups_scroll.add_child(_groups_box)
	container.add_child(groups_scroll)

	for gi in range(_groups.size()):
		_groups_box.add_child(_build_group_section(gi))

	# COMPAT: the focused group's list doubles as the historic `weapon_list`.
	_set_focused_group(0)

	# Target selector — the SHARED "currently selected target". Group rows point
	# at their own target; this list is what Assign / All to Target / the pad's
	# ◀ ▶ (and the board reticle) act on.
	var target_label = Label.new()
	target_label.text = "Target:"
	container.add_child(target_label)

	target_list = ItemList.new()
	target_list.name = "TargetList"
	target_list.custom_minimum_size = Vector2(480, 70)
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

	# Auto-assign: give every group the weapon with the best expected damage
	# against the selected target. This is the "don't drown me in options" path —
	# the dialog already opens on this plan, and the button restores it after any
	# manual fiddling.
	best_krump_button = Button.new()
	best_krump_button.name = "BestKrumpButton"
	best_krump_button.text = "Best Krump ✨"
	best_krump_button.tooltip_text = "Auto-pick the best melee weapon for each group against the selected target"
	best_krump_button.pressed.connect(_on_best_krump_pressed)
	button_container.add_child(best_krump_button)

	# Assign button
	var assign_button = Button.new()
	assign_button.name = "AssignButton"
	assign_button.text = "Add Assignment"
	assign_button.tooltip_text = "Point the highlighted section's selected weapon at the selected target"
	assign_button.pressed.connect(_on_assign_pressed)
	button_container.add_child(assign_button)

	# T5-UX5 (reworked again for loadout groups): one-click shortcut that points
	# EVERY group at the selected target, each keeping the weapon it has chosen.
	# Node name is kept as AllToTargetButton — windowed scenarios click it by path.
	all_to_target_button = Button.new()
	all_to_target_button.name = "AllToTargetButton"
	all_to_target_button.text = "All to Target"
	all_to_target_button.tooltip_text = "Send every section at the selected target (each keeps its own weapon)"
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

	# No eligible targets: nothing can ever be assigned, so the buttons above are
	# dead ends — offer the one legal move (ending the fight) instead of
	# soft-locking the player in an un-completable dialog.
	if eligible_targets.is_empty():
		assign_button.disabled = true
		all_to_target_button.disabled = true
		best_krump_button.disabled = true
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
	assignments_display.custom_minimum_size = Vector2(480, 70)
	assignments_display.name = "AssignmentsDisplay"
	assignments_display.bbcode_enabled = true
	container.add_child(assignments_display)

	# Pad (controller) hint row — the melee twin of the shooting phase's target
	# ring, spelled out for a controller. Shown only when the pad is the active
	# device; a mouse player never sees it. See _pad_handle_input.
	_pad_hint_label = Label.new()
	_pad_hint_label.name = "PadHintLabel"
	if _groups.size() > 1:
		_pad_hint_label.text = "▲▼ Weapon   ·   ◀▶ Target   ·   LB/RB Section   ·   Ⓐ Assign   ·   ☰ Fight!   ·   Ⓑ Skip"
	else:
		_pad_hint_label.text = "▲▼ Weapon   ·   ◀▶ Target   ·   Ⓐ Assign   ·   ☰ Fight!   ·   Ⓑ Skip"
	_pad_hint_label.add_theme_font_size_override("font_size", 16)
	_pad_hint_label.modulate = Color(1, 1, 1, 0.75)
	_pad_hint_label.visible = InputDeviceManager.is_pad_active()
	container.add_child(_pad_hint_label)

	add_child(container)

	# Open on the auto-assigned plan so "open → Fight!" is a legal, sensible
	# activation with no clicks in between (the old dialog opened with NOTHING
	# assigned and rejected the confirm until the player clicked a weapon).
	if not eligible_targets.is_empty():
		_apply_best_plan(_selected_target_id())

	confirmed.connect(_on_confirmed)

	# Pad: the ItemLists are driven by the D-pad through window_input (below), so
	# demote them out of the focus chain — otherwise the dialog watcher / native
	# ui_up-down would fight our stepping. Buttons keep focus for A-fallthrough.
	var lists: Array = [target_list, extra_attacks_target_list]
	for g in _groups:
		lists.append(g.get("list", null))
	for lst in lists:
		if lst != null:
			lst.focus_mode = Control.FOCUS_CLICK
	window_input.connect(_pad_handle_input)
	# Auto-arm the board reticle on the first shown frame when a pad is active,
	# so ◀ ▶ / A have a visible target from the very first press.
	about_to_popup.connect(_pad_arm_on_popup)


# ── loadout grouping ────────────────────────────────────────────────────────

# Partition `_eligible_indices` by the SET of regular melee weapons each model
# carries. Membership is read back out of `_weapon_carriers`, which is built from
# RulesEngine.get_melee_weapon_swingers — so the dialog's idea of "who carries
# what" is by construction the same one the engine applies when the attacks
# resolve, including its conservative "cannot attribute → everyone" fallback.
func _build_groups(unit: Dictionary) -> void:
	_groups = []
	var models: Array = unit.get("models", [])
	var by_signature: Dictionary = {}

	for idx in _eligible_indices:
		var carried: Array = []
		for wid in _weapon_carriers:
			if idx in _weapon_carriers[wid]:
				carried.append(wid)
		if carried.is_empty():
			# An eligible model with no melee weapon we can attribute simply has
			# nothing to swing — it drops out rather than being given someone
			# else's weapon.
			print("[AttackAssignmentDialog] Model %d carries no listed melee weapon — not grouped" % idx)
			continue
		carried.sort()
		var signature: String = "|".join(carried)
		if not by_signature.has(signature):
			by_signature[signature] = {
				"key": signature,
				"weapons": carried,
				"models": [],
				"labels": [],
			}
		by_signature[signature].models.append(idx)
		# Label from the datasheet's model_profiles when it names this model type
		# ("Boss Nob" / "Boy"); several types with an identical weapon set share
		# one section and the label lists them.
		var label := _model_type_label(unit, models[idx] if idx < models.size() else {})
		if label != "" and not label in by_signature[signature].labels:
			by_signature[signature].labels.append(label)

	# Biggest section first — a mob reads as "9 Boyz, then the Nob", and it makes
	# group 0 (the pad's initial focus, and the compat `weapon_list`) the one a
	# player most likely wants.
	var sigs: Array = by_signature.keys()
	sigs.sort_custom(func(a, b):
		var ga = by_signature[a]
		var gb = by_signature[b]
		if ga.models.size() != gb.models.size():
			return ga.models.size() > gb.models.size()
		return str(ga.key) < str(gb.key))

	for sig in sigs:
		var g: Dictionary = by_signature[sig]
		g["label"] = " / ".join(g.labels) if not g.labels.is_empty() else "Models"
		g["split"] = false
		g["lines"] = []          # [{weapon, count, target}] — the group's plan
		g["list"] = null
		g["target_button"] = null
		g["split_button"] = null
		g["summary"] = null
		g["split_box"] = null
		g["spins"] = {}
		g["line_target_buttons"] = {}
		_groups.append(g)
		print("[AttackAssignmentDialog] Group '%s' x%d — weapons: %s" % [
			g.label, g.models.size(), str(g.weapons)])


func _model_type_label(unit: Dictionary, model: Dictionary) -> String:
	var model_type := str(model.get("model_type", ""))
	if model_type == "":
		return ""
	var profiles: Dictionary = unit.get("meta", {}).get("model_profiles", {})
	if profiles.has(model_type):
		return str(profiles[model_type].get("label", model_type.capitalize()))
	return model_type.capitalize()


# ── group UI ────────────────────────────────────────────────────────────────

func _build_group_section(gi: int) -> Control:
	var g: Dictionary = _groups[gi]
	var panel := PanelContainer.new()
	panel.name = "Group%d" % gi
	var box := VBoxContainer.new()
	box.name = "Body"
	panel.add_child(box)

	# Header: "Boy ×9" plus the per-group controls (target cycle, split toggle).
	var header := HBoxContainer.new()
	header.name = "Header"
	var title_label := Label.new()
	title_label.name = "GroupLabel"
	title_label.text = "%s ×%d" % [g.label, g.models.size()]
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	# Per-group target. A cycle BUTTON rather than a dropdown on purpose: the
	# windowed-scenario harness cannot click inside popup windows, and a pad has
	# no pointer — a button is drivable by both.
	var tgt_button := Button.new()
	tgt_button.name = "GroupTargetButton"
	tgt_button.tooltip_text = "Click to send this section at a different target"
	tgt_button.pressed.connect(_on_group_target_cycle.bind(gi))
	tgt_button.disabled = eligible_targets.size() < 2
	header.add_child(tgt_button)
	g["target_button"] = tgt_button

	# Split is only meaningful when there are several models AND several weapons
	# to divide them between.
	if g.models.size() > 1 and g.weapons.size() > 1:
		var split_button := Button.new()
		split_button.name = "SplitButton"
		split_button.text = "Split…"
		split_button.tooltip_text = "Divide this section between several weapons"
		split_button.pressed.connect(_on_split_toggled.bind(gi))
		header.add_child(split_button)
		g["split_button"] = split_button

	box.add_child(header)

	# Un-split mode: one weapon list for the whole group.
	var list := ItemList.new()
	list.name = "WeaponList"
	list.custom_minimum_size = Vector2(DialogConstants.LARGE.x - 90, 26 * min(4, max(1, g.weapons.size())) + 8)
	for wid in g.weapons:
		var w: Dictionary = _weapon_by_id.get(wid, {})
		list.add_item("%s (A:%s S:%s AP:%s D:%s)" % [
			w.get("name", wid),
			w.get("attacks", "1"),
			w.get("strength", "User"),
			w.get("ap", "0"),
			w.get("damage", "1")
		])
		list.set_item_metadata(list.item_count - 1, wid)
	list.item_selected.connect(_on_group_weapon_selected.bind(gi))
	box.add_child(list)
	g["list"] = list

	# Split mode: one count row per weapon. Built now, hidden until toggled.
	var split_box := VBoxContainer.new()
	split_box.name = "SplitBox"
	split_box.visible = false
	for wid in g.weapons:
		var w: Dictionary = _weapon_by_id.get(wid, {})
		var row := HBoxContainer.new()
		row.name = "SplitRow_%s" % wid
		var name_label := Label.new()
		name_label.text = str(w.get("name", wid))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var spin := SpinBox.new()
		spin.name = "Count_%s" % wid
		spin.min_value = 0
		spin.max_value = g.models.size()
		spin.step = 1
		spin.value = 0
		spin.value_changed.connect(_on_split_count_changed.bind(gi, wid))
		row.add_child(spin)
		g.spins[wid] = spin

		var line_tgt := Button.new()
		line_tgt.name = "LineTarget_%s" % wid
		line_tgt.tooltip_text = "Click to send this weapon's models at a different target"
		line_tgt.pressed.connect(_on_line_target_cycle.bind(gi, wid))
		line_tgt.disabled = eligible_targets.size() < 2
		row.add_child(line_tgt)
		g.line_target_buttons[wid] = line_tgt

		split_box.add_child(row)
	box.add_child(split_box)
	g["split_box"] = split_box

	# Per-group summary (attack count + expected damage).
	var summary := Label.new()
	summary.name = "GroupSummary"
	summary.add_theme_font_size_override("font_size", 15)
	summary.modulate = Color(1, 1, 1, 0.8)
	box.add_child(summary)
	g["summary"] = summary

	return panel


# ── plan helpers ────────────────────────────────────────────────────────────

func _selected_target_id() -> String:
	if target_list != null and target_list.item_count > 0:
		var sel := target_list.get_selected_items()
		var idx: int = sel[0] if not sel.is_empty() else 0
		return str(target_list.get_item_metadata(idx))
	if not eligible_targets.is_empty():
		return str(eligible_targets.keys()[0])
	return ""


# Give every group the weapon with the highest expected damage against
# `target_id`, un-split, all pointed at that target.
func _apply_best_plan(target_id: String) -> void:
	if target_id == "":
		return
	for gi in range(_groups.size()):
		var g: Dictionary = _groups[gi]
		g.split = false
		var best := _best_weapon_for_group(gi, target_id)
		if best == "":
			continue
		g.lines = [{"weapon": best, "count": g.models.size(), "target": target_id}]
	_sync_group_widgets()
	_rebuild_assignments()


# The weapon a group should swing against `target_id`: the highest expected
# damage across the whole group. Target-aware on purpose — a Power klaw is the
# right answer against Custodes and the wrong one against Gretchin, which a
# fixed attacks x damage score could never tell apart.
func _best_weapon_for_group(gi: int, target_id: String) -> String:
	var g: Dictionary = _groups[gi]
	var best_id := ""
	var best_score := -1.0
	for wid in g.weapons:
		var score := _estimate_expected_damage(wid, target_id, g.models.size())
		if score > best_score:
			best_score = score
			best_id = wid
	return best_id


# Rebuild `assignments` from the group plans. Every model appears at most once
# (lines inside a group take disjoint slices of the group's model list, and
# groups are disjoint by construction), which is exactly what FightPhase's
# one-weapon-per-model validator checks.
func _rebuild_assignments() -> void:
	assignments = []
	var merged: Dictionary = {}  # "weapon|target" -> assignment dict
	for g in _groups:
		var cursor := 0
		for line in g.lines:
			var count: int = int(line.get("count", 0))
			if count <= 0:
				continue
			var wid := str(line.get("weapon", ""))
			var tid := str(line.get("target", ""))
			if wid == "" or tid == "":
				continue
			var picked: Array = []
			for i in range(count):
				if cursor >= g.models.size():
					break
				picked.append(str(g.models[cursor]))
				cursor += 1
			if picked.is_empty():
				continue
			# Two groups can legitimately land on the same weapon and target
			# (a Nob and his Boyz both on Choppas); merge so the batch stays one
			# ASSIGN_ATTACKS per weapon/target pair rather than one per group.
			var key := "%s|%s" % [wid, tid]
			if merged.has(key):
				merged[key].models.append_array(picked)
			else:
				var entry := {
					"attacker": unit_id,
					"weapon": wid,
					"target": tid,
					"models": picked
				}
				merged[key] = entry
				assignments.append(entry)

	for a in assignments:
		print("[AttackAssignmentDialog] Assignment: %s → %s (%d model(s): %s)" % [
			a.weapon, a.target, a.models.size(), str(a.models)])
	print("[AttackAssignmentDialog] Total assignments: ", assignments.size())
	_update_assignments_display()


# Push the group plans back onto their widgets (list selection, spin counts,
# target button captions, summary line). Guarded so the SpinBox writes do not
# re-enter the rebalancer.
func _sync_group_widgets() -> void:
	_updating_spins = true
	for gi in range(_groups.size()):
		var g: Dictionary = _groups[gi]
		var lst: ItemList = g.get("list", null)
		var split_box: VBoxContainer = g.get("split_box", null)
		if lst != null:
			lst.visible = not g.split
		if split_box != null:
			split_box.visible = g.split
		if g.get("split_button", null) != null:
			g.split_button.text = "Merge" if g.split else "Split…"

		if not g.split:
			# One line: reflect its weapon as the list selection.
			var wid := str(g.lines[0].get("weapon", "")) if not g.lines.is_empty() else ""
			if lst != null:
				for i in range(lst.item_count):
					if str(lst.get_item_metadata(i)) == wid:
						lst.select(i)
						# Scroll the chosen weapon into view — a Boss Nob's list
						# is taller than its box, and an off-screen selection
						# reads as "it picked the top one".
						lst.ensure_current_is_visible()
						break
		else:
			for wid in g.weapons:
				var spin: SpinBox = g.spins.get(wid, null)
				if spin != null:
					spin.value = _line_count(g, wid)
				var btn: Button = g.line_target_buttons.get(wid, null)
				if btn != null:
					btn.text = "→ %s" % _target_name(_line_target(g, wid))

		# Group target caption: one target for the whole group, or "(mixed)".
		var tb: Button = g.get("target_button", null)
		if tb != null:
			var tids: Array = []
			for line in g.lines:
				if int(line.get("count", 0)) > 0 and not str(line.get("target", "")) in tids:
					tids.append(str(line.get("target", "")))
			if tids.size() == 1:
				tb.text = "→ %s" % _target_name(tids[0])
			elif tids.is_empty():
				tb.text = "→ —"
			else:
				tb.text = "→ (mixed)"

		# Highlight the focused section so ▲▼ / Add Assignment have a visible subject.
		var panel := _groups_box.get_child(gi) if _groups_box != null and gi < _groups_box.get_child_count() else null
		if panel != null:
			panel.modulate = Color(1, 1, 1, 1.0) if gi == _focused_group else Color(1, 1, 1, 0.75)

		# Summary: attacks + expected damage for this group's lines.
		var summary: Label = g.get("summary", null)
		if summary != null:
			var atks := 0.0
			var ed := 0.0
			for line in g.lines:
				var count: int = int(line.get("count", 0))
				if count <= 0:
					continue
				var w: Dictionary = _weapon_by_id.get(str(line.get("weapon", "")), {})
				atks += _average_dice_notation(str(w.get("attacks", "1"))) * float(count)
				ed += _estimate_expected_damage(str(line.get("weapon", "")), str(line.get("target", "")), count)
			summary.text = "≈%s attacks · E[D]≈%.1f" % [
				("%.1f" % atks) if atks != floor(atks) else ("%d" % int(atks)), ed]
	_updating_spins = false


func _line_count(g: Dictionary, weapon_id: String) -> int:
	for line in g.lines:
		if str(line.get("weapon", "")) == weapon_id:
			return int(line.get("count", 0))
	return 0


func _line_target(g: Dictionary, weapon_id: String) -> String:
	for line in g.lines:
		if str(line.get("weapon", "")) == weapon_id:
			return str(line.get("target", ""))
	return _selected_target_id()


func _target_name(target_id: String) -> String:
	if target_id == "" or not eligible_targets.has(target_id):
		return "—"
	return str(eligible_targets[target_id].get("name", target_id))


func _set_focused_group(gi: int) -> void:
	if _groups.is_empty():
		weapon_list = null
		return
	_focused_group = clampi(gi, 0, _groups.size() - 1)
	# COMPAT: `weapon_list` always points at the focused group's list.
	weapon_list = _groups[_focused_group].get("list", null)


# ── group interactions ──────────────────────────────────────────────────────

# Selecting a weapon row IS the assignment — no "Add" click required. The old
# dialog made the player select-then-Add for a choice that can only ever be one
# weapon per group, so the extra click bought nothing.
func _on_group_weapon_selected(index: int, gi: int) -> void:
	var g: Dictionary = _groups[gi]
	var lst: ItemList = g.get("list", null)
	if lst == null or index < 0 or index >= lst.item_count:
		return
	_set_focused_group(gi)
	var wid := str(lst.get_item_metadata(index))
	var tid := _line_target(g, wid)
	if tid == "":
		tid = _selected_target_id()
	g.split = false
	g.lines = [{"weapon": wid, "count": g.models.size(), "target": tid}]
	print("[AttackAssignmentDialog] Group '%s' → %s (%d model(s))" % [g.label, wid, g.models.size()])
	_sync_group_widgets()
	_rebuild_assignments()


func _on_group_target_cycle(gi: int) -> void:
	var g: Dictionary = _groups[gi]
	var keys: Array = eligible_targets.keys()
	if keys.size() < 2:
		return
	var current := ""
	for line in g.lines:
		if int(line.get("count", 0)) > 0:
			current = str(line.get("target", ""))
			break
	var next_idx := (keys.find(current) + 1) % keys.size()
	var next_id := str(keys[next_idx])
	for line in g.lines:
		line["target"] = next_id
	print("[AttackAssignmentDialog] Group '%s' now targets %s" % [g.label, next_id])
	_sync_group_widgets()
	_rebuild_assignments()


func _on_line_target_cycle(gi: int, weapon_id: String) -> void:
	var g: Dictionary = _groups[gi]
	var keys: Array = eligible_targets.keys()
	if keys.size() < 2:
		return
	for line in g.lines:
		if str(line.get("weapon", "")) == weapon_id:
			var next_idx := (keys.find(str(line.get("target", ""))) + 1) % keys.size()
			line["target"] = str(keys[next_idx])
			print("[AttackAssignmentDialog] Group '%s' / %s now targets %s" % [g.label, weapon_id, line.target])
			break
	_sync_group_widgets()
	_rebuild_assignments()


# Split mode seeds every weapon with a line so the SpinBoxes have something to
# hold, keeping the group's current weapon as the one that starts with all the
# models (so toggling Split and toggling it straight back is a no-op plan).
func _on_split_toggled(gi: int) -> void:
	var g: Dictionary = _groups[gi]
	_set_focused_group(gi)
	if g.split:
		# Merge back: the weapon holding the most models wins the whole group.
		var best_wid := ""
		var best_count := -1
		for line in g.lines:
			if int(line.get("count", 0)) > best_count:
				best_count = int(line.get("count", 0))
				best_wid = str(line.get("weapon", ""))
		var tid := _line_target(g, best_wid)
		g.split = false
		g.lines = [{"weapon": best_wid, "count": g.models.size(), "target": tid}]
		print("[AttackAssignmentDialog] Group '%s' merged onto %s" % [g.label, best_wid])
	else:
		var current_wid := str(g.lines[0].get("weapon", "")) if not g.lines.is_empty() else str(g.weapons[0])
		var tid := _line_target(g, current_wid)
		var new_lines: Array = []
		for wid in g.weapons:
			new_lines.append({
				"weapon": wid,
				"count": g.models.size() if wid == current_wid else 0,
				"target": tid
			})
		g.split = true
		g.lines = new_lines
		print("[AttackAssignmentDialog] Group '%s' split across %d weapon(s)" % [g.label, g.weapons.size()])
	_sync_group_widgets()
	_rebuild_assignments()


# Counts always sum to the group size, so the player can never build an illegal
# or half-assigned plan: raising one weapon takes models from the others (from
# the bottom up), lowering it hands the remainder back to the first other line.
func _on_split_count_changed(value: float, gi: int, weapon_id: String) -> void:
	if _updating_spins:
		return
	var g: Dictionary = _groups[gi]
	var size: int = g.models.size()
	for line in g.lines:
		if str(line.get("weapon", "")) == weapon_id:
			line["count"] = clampi(int(value), 0, size)
			break

	var total := 0
	for line in g.lines:
		total += int(line.get("count", 0))

	if total > size:
		var excess := total - size
		for i in range(g.lines.size() - 1, -1, -1):
			if excess <= 0:
				break
			var line = g.lines[i]
			if str(line.get("weapon", "")) == weapon_id:
				continue
			var take: int = min(excess, int(line.get("count", 0)))
			line["count"] = int(line.get("count", 0)) - take
			excess -= take
	elif total < size:
		var remainder := size - total
		var placed := false
		for line in g.lines:
			if str(line.get("weapon", "")) == weapon_id:
				continue
			line["count"] = int(line.get("count", 0)) + remainder
			placed = true
			break
		if not placed:
			for line in g.lines:
				if str(line.get("weapon", "")) == weapon_id:
					line["count"] = int(line.get("count", 0)) + remainder
					break

	_set_focused_group(gi)
	_sync_group_widgets()
	_rebuild_assignments()


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
#   ▲ ▼   step the FOCUSED section's weapon list   (one melee weapon per model — 11e)
#   ◀ ▶   step the target list   (updates the board reticle via the signal)
#   LB RB  move between loadout sections (Boyz ↔ Boss Nob) — multi-group units only
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
		JOY_BUTTON_LEFT_SHOULDER:
			_pad_step_group(-1)
			set_input_as_handled()
		JOY_BUTTON_RIGHT_SHOULDER:
			_pad_step_group(1)
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


# Pad LB/RB: move the focus between loadout sections, with a toast naming the
# one now under ▲▼ (a controller player has no pointer to show them).
func _pad_step_group(dir: int) -> void:
	if _groups.size() < 2:
		return
	_set_focused_group(wrapi(_focused_group + dir, 0, _groups.size()))
	_sync_group_widgets()
	var toast := get_node_or_null("/root/ToastManager")
	if toast != null:
		var g: Dictionary = _groups[_focused_group]
		toast.show_toast("◆ %s ×%d — ▲▼ picks its weapon" % [g.label, g.models.size()])


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
	# ItemList.select() does NOT emit item_selected, so mirror the click path —
	# otherwise the pad would move the highlight without changing the plan.
	if lst == weapon_list:
		_on_group_weapon_selected(nxt, _focused_group)
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

# "Add Assignment": point the FOCUSED section's selected weapon at the selected
# target. Other sections keep their own plan — that is the whole point of the
# group rework, and why this no longer clears `assignments` first.
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

	var g: Dictionary = _groups[_focused_group]
	g.split = false
	g.lines = [{"weapon": weapon_id, "count": g.models.size(), "target": target_id}]
	print("[AttackAssignmentDialog] Group '%s' assigned %s → %s (%d model(s))" % [
		g.label, weapon_id, target_id, g.models.size()])
	_sync_group_widgets()
	_rebuild_assignments()


# "All to Target": send EVERY section at the selected target, each keeping the
# weapon it already has. Previously this assigned one weapon for the whole unit;
# with per-group weapons the useful bulk action is the target, not the weapon.
func _on_all_to_target_pressed() -> void:
	print("[AttackAssignmentDialog] 'All to Target' button pressed")

	if not target_list:
		push_error("Target list not initialized")
		return

	var target_idx = target_list.get_selected_items()
	if target_idx.is_empty():
		push_warning("Select a target first")
		print("[AttackAssignmentDialog] No target selected")
		return

	var target_id = str(target_list.get_item_metadata(target_idx[0]))
	for gi in range(_groups.size()):
		var g: Dictionary = _groups[gi]
		if g.lines.is_empty():
			var best := _best_weapon_for_group(gi, target_id)
			if best != "":
				g.lines = [{"weapon": best, "count": g.models.size(), "target": target_id}]
			continue
		for line in g.lines:
			line["target"] = target_id
	print("[AttackAssignmentDialog] All %d section(s) → %s" % [_groups.size(), target_id])
	_sync_group_widgets()
	_rebuild_assignments()


# "Best Krump": re-derive the whole plan — best weapon per section against the
# selected target, splits merged. The one-click way back to a sane default after
# manual fiddling, and the plan the dialog already opens on.
func _on_best_krump_pressed() -> void:
	var target_id := _selected_target_id()
	print("[AttackAssignmentDialog] Best Krump: auto-assigning %d section(s) vs %s" % [_groups.size(), target_id])
	_apply_best_plan(target_id)
	var toast := get_node_or_null("/root/ToastManager")
	if toast != null:
		toast.show_toast("✨ Best weapon picked for each section")


func _update_assignments_display() -> void:
	if not assignments_display:
		return

	assignments_display.clear()
	var total_expected_damage: float = 0.0
	for assignment in assignments:
		# Each line is one weapon and the models that actually swing it, so name
		# the count — "Power klaw (1 model)" next to "Choppa (9 models)" is the
		# whole point of the plan.
		var swinging: int = (assignment.get("models", []) as Array).size()
		var ed: float = _estimate_expected_damage(assignment.weapon, assignment.target, swinging)
		total_expected_damage += ed
		var w: Dictionary = _weapon_by_id.get(str(assignment.weapon), {})
		assignments_display.append_text("- %s → %s (%d model%s) [E[D]≈%.1f]\n" % [
			w.get("name", assignment.weapon), _target_name(str(assignment.target)),
			swinging, "" if swinging == 1 else "s", ed])

	# T3-3: Show Extra Attacks auto-assignments preview
	if not extra_attacks_weapons.is_empty():
		var ea_target_id = _get_extra_attacks_target_id()
		for weapon in extra_attacks_weapons:
			var weapon_name = weapon.get("name", "Unknown")
			var weapon_id = RulesEngine.generate_weapon_id(weapon_name, weapon.get("type", ""))
			var ea_carriers: Array = RulesEngine.get_melee_weapon_swingers(
				phase_reference.get_unit(unit_id), weapon_id, _eligible_indices, [])
			var ed: float = _estimate_expected_damage(weapon_id, ea_target_id, ea_carriers.size())
			total_expected_damage += ed
			assignments_display.append_text("- %s → %s (%d model%s) [Extra Attacks, E[D]≈%.1f]\n" % [
				weapon_name, _target_name(str(ea_target_id)), ea_carriers.size(),
				"" if ea_carriers.size() == 1 else "s", ed])
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
	# Total attacks = per-weapon attacks x the models actually swinging it.
	# MA-LOADOUT: the caller passes that count (the assignment's model list), so
	# the preview no longer multiplies a one-model Power klaw by the whole mob.
	# Fall back to the eligible-and-equipped count when it is not supplied.
	var swinging: int = swinging_models
	if swinging < 0:
		swinging = RulesEngine.get_melee_weapon_swingers(
			attacker_unit, weapon_id, _eligible_indices, []).size()
	var total_attacks: float = attacks_avg * float(max(1, swinging))
	# Hit probability from WS/BS (weapon's accuracy attribute). `weapon_skill` is
	# the key the army JSONs actually use — without it every melee weapon scored
	# as WS4+, which made the auto-pick blind to a Nob's WS3 Choppa vs his WS4
	# Power klaw.
	var skill_int: int = _parse_stat_int(str(weapon.get("skill",
		weapon.get("weapon_skill", weapon.get("ws", weapon.get("bs", "4"))))))
	var p_hit: float = clampf(float(7 - skill_int) / 6.0, 1.0/6.0, 5.0/6.0)
	# Wound probability vs target T
	var target_T: int = _parse_stat_int(str(target_unit.get("meta", {}).get("stats", {}).get("toughness", 4)))
	var p_wound: float = _wound_probability(strength_int, target_T)
	# Unsaved probability: target save - AP, capped invuln
	var target_save: int = _parse_stat_int(str(target_unit.get("meta", {}).get("stats", {}).get("save", 5)))
	var target_invuln: int = _parse_stat_int(str(target_unit.get("meta", {}).get("stats", {}).get("invuln", 7)))
	# AP WORSENS a save, and the army JSONs store it negative ("-2"). The old
	# `target_save - max(0, ap_int)` clamped every negative AP to 0, so AP was
	# silently ignored — which made the preview flatter than reality and, now
	# that the auto-pick is driven by this number, would have handed a Boss Nob
	# his Big choppa over the AP-2 Power klaw against 2+ armour. Take the
	# magnitude and add it; 7+ means no save at all.
	var ap_penalty: int = abs(ap_int)
	var modified_save: int = min(7, target_save + ap_penalty)
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
	# GameState stores defender stats as JSON numbers, which come back as FLOATS
	# — so str(toughness) is "6.0", not "6". is_valid_int() rejects that, and the
	# whole estimator silently fell back to the default 4: every expected-damage
	# preview was computed against T4 / Sv4+ no matter who the defender actually
	# was. That also made the auto-pick target-blind (it handed a Boss Nob his
	# Big choppa against 2+ armour the Power klaw is for).
	if s.is_valid_float():
		return int(round(s.to_float()))
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
