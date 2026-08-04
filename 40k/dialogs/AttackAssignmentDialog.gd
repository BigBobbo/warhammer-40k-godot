extends AcceptDialog
class_name AttackAssignmentDialog

signal attacks_confirmed(assignments: Array)
# Escape hatch: emitted when the dialog opened with NO eligible targets and
# the player ends the fight instead (the controller submits SKIP_UNIT).
# FightPhase normally auto-ends a no-target activation before this dialog is
# requested, so this only fires on unforeseen paths — but without it the
# dialog is un-completable (nothing to assign) and the game self-locks.
signal skip_fight_requested(unit_id: String)
# The player backed out of this activation before assigning anything — the
# controller submits CANCEL_FIGHTER_SELECTION, which un-picks the unit and puts
# the fighter-selection panel back. Emitted by the "◀ Back — Pick Another Unit"
# button AND by every native dismissal (Escape, the window ✕, pad Ⓑ), which
# previously just hid the dialog and stranded the phase with no way to fight or
# re-pick.
signal selection_cancelled(unit_id: String)
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
# Collapsible "where does E[D] come from?" table. Folded away by default: the
# assignment rows only ever showed a bare `E[D]≈8.3`, so a player comparing two
# Vaultswords profiles had to take the number on faith (and, reading it as
# "8.3 dead models", could be badly misled — a D3 weapon wastes two thirds of
# its damage on 1-wound Stormboyz). Expanding it shows the whole hit → wound →
# save → damage chain per assignment, plus the models it actually kills.
var _breakdown_toggle: Button = null
var _breakdown_scroll: ScrollContainer = null
var _breakdown_display: RichTextLabel = null

# MA-LOADOUT (melee): who can swing what. `_eligible_models` is every model
# that may fight this activation; `_weapon_carriers` maps a weapon id to the
# subset of those models actually equipped with it (RulesEngine applies the same
# filter when the attacks resolve). Before this the dialog offered the unit's
# whole datasheet menu to every model, so picking the Boss Nob's Power klaw gave
# all ten Boyz one.
# 19.03 — ONE dialog for the whole ATTACHED unit. A CHARACTER attached to a
# bodyguard fights in the SAME activation, so the models here span more than one
# unit dict. Each is addressed by a MODEL KEY "<unit_id>#<model index>"; the
# index alone is ambiguous once two components are in play (the Warboss's only
# model is index 0 just as the first Boy is). Assignments are split back out per
# component in _rebuild_assignments, because RulesEngine resolves each against
# its own `attacker` — that is what keeps the leader's stats, abilities and
# weapon profile his own instead of his bodyguard's.
var _eligible_models: Array = []        # Array[String] model keys
var _weapon_carriers: Dictionary = {}   # weapon_id -> Array[String] model keys
var _model_key_unit: Dictionary = {}    # model key -> owning component unit id
var _group_unit_ids: Array = []         # component unit ids, bodyguard first

# component unit id -> Array[target_id] this component may legally swing at.
#
# `eligible_targets` is the ACTIVATION's list, measured across the whole
# Attached unit (19.03). Each COMPONENT can only attack what its own models
# have reached — 11e Fight, "Select Targets": each target must be engaged with
# the model that has that weapon. A Custodian Guard locked with one Ork mob and
# its attached Blade Champion locked with another share this dialog, and the
# activation may attack both mobs, but neither component may attack both.
#
# Reported bug: every section was offered the whole activation's list, so
# "Best Weapons ✨" (which points EVERY section at the ONE selected target)
# produced a plan the engine then rejected with "not within engagement range"
# — on a unit plainly still in combat, with no way to tell which half was the
# problem. Filled by _build_component_targets, and every path that sets a
# section's target clamps through _targets_for_group / _clamp_target_for_group.
var _component_targets: Dictionary = {}

# "<unit_id>#<index>" — see _eligible_models.
static func _mk(owner_id: String, model_index: int) -> String:
	return "%s#%d" % [owner_id, model_index]

static func _mk_unit(model_key: String) -> String:
	var sep := model_key.rfind("#")
	return model_key.substr(0, sep) if sep > 0 else model_key

static func _mk_index(model_key: String) -> String:
	var sep := model_key.rfind("#")
	return model_key.substr(sep + 1) if sep > 0 else model_key
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
	# 19.03: name the whole ATTACHED unit ("Boyz + Warboss") — this one dialog
	# assigns the attacks of every component, so titling it with the bodyguard
	# alone hid that the leader swings here too.
	title = "Assign Attacks: %s" % (phase._fight_attached_display_name(unit_id) if phase.has_method("_fight_attached_display_name") \
else str(_aad_meta.get("display_name", _aad_meta.get("name", unit_id))))

	print("[AttackAssignmentDialog] Building UI...")
	_build_ui()
	print("[AttackAssignmentDialog] UI built successfully")

func _build_ui() -> void:
	min_size = DialogConstants.LARGE
	var container = VBoxContainer.new()
	container.name = "Content"
	container.custom_minimum_size = Vector2(DialogConstants.LARGE.x - 20, 0)

	# 19.03: the activation covers the whole ATTACHED unit — the bodyguard AND
	# every CHARACTER attached to it. Everything below walks the components.
	_group_unit_ids = RulesEngine.attached_unit_component_ids(unit_id, phase_reference.game_state_snapshot)
	var unit = phase_reference.get_unit(unit_id)
	_build_component_targets()

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
	# span the Attached unit's components; a weapon named by two of them is ONE
	# entry (its carriers are collected from both below).
	var regular_melee_weapons = []
	extra_attacks_weapons = []
	var seen_weapon_ids := {}
	for member_id in _group_unit_ids:
		for weapon in phase_reference.get_unit(member_id).get("meta", {}).get("weapons", []):
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
		# A weapon the roster never bought is on no model at all. The datasheet
		# lists it because it is an OPTION — an Ork mob's Power klaw and Close
		# combat weapon are alternatives to the choppas it actually took — and
		# offering them let a player swing weapons the unit does not own.
		# (Before a unit's loadout can be resolved every model reports the whole
		# menu, so this hides nothing.)
		# 19.03: asked of each component in turn, so the Warboss's Power klaw is
		# listed as HIS even though his Boyz name it only as an option.
		var carriers: Array = []
		for member_id in _group_unit_ids:
			var member = phase_reference.get_unit(member_id)
			if not RulesEngine.unit_has_melee_weapon(member, wid):
				continue
			var member_eligible: Array = []
			for key in _eligible_models:
				if _model_key_unit.get(key, "") == member_id:
					member_eligible.append(int(_mk_index(str(key))))
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
	# Sized to what the sections actually need, capped at the old fixed 260 so a
	# mob with several loadouts still scrolls rather than growing without bound.
	# It used to reserve 260px unconditionally, which for a single-model, single-
	# weapon fighter (a Warboss with just his Power klaw) was ~150px of empty box
	# — and on a 1080p screen that was exactly the room the damage-breakdown
	# section below needed, so the new table opened half off the bottom edge.
	var groups_needed := 0.0
	for g in _groups:
		groups_needed += 40.0 + float(26 * min(4, max(1, g.weapons.size())) + 8) + 26.0
	groups_scroll.custom_minimum_size = Vector2(DialogConstants.LARGE.x - 40, clampf(groups_needed, 90.0, 260.0))
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

	# 19.03 + 11e "Select Targets": when this Attached unit's components are
	# locked with DIFFERENT enemies, no single target is legal for every
	# section — say so up front, because the bulk buttons below will then send
	# some sections elsewhere and a silent redirect reads as a bug.
	if _components_disagree_on_targets():
		var split_note = Label.new()
		split_note.name = "SplitEngagementNote"
		split_note.text = "This unit's sections are locked with different enemies — each can only attack what IT is in Engagement Range of, so a section may not follow the target picked above."
		split_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		split_note.add_theme_font_size_override("font_size", 14)
		split_note.modulate = Color(1, 0.85, 0.5)
		container.add_child(split_note)

	# Button container for assignment actions
	var button_container = HBoxContainer.new()
	button_container.name = "ButtonContainer"

	# Auto-assign: give every group the weapon with the best expected damage
	# against the selected target. This is the "don't drown me in options" path —
	# the dialog already opens on this plan, and the button restores it after any
	# manual fiddling.
	best_krump_button = Button.new()
	best_krump_button.name = "BestKrumpButton"
	# Label is plain English for the same reason as the back button below — the
	# node name / handler keep the "best_krump" spelling because windowed
	# scenarios click this by path and coverage tags key off it.
	best_krump_button.text = "Best Weapons ✨"
	best_krump_button.tooltip_text = "Auto-pick the best melee weapon for each section against the selected target"
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

	# THE WAY BACK. Selecting a fighter retires the right-hand fighter-selection
	# panel, so before this button the only exits from here were "Fight!" and a
	# silent dismissal (Escape / ✕ / pad Ⓑ) that hid the dialog and stranded the
	# whole phase — the activation stayed open with no UI to finish or change it,
	# and END_FIGHT (forfeiting every remaining swing) was all that was left.
	# Backing out un-picks the unit and puts the picker back, so a mis-clicked
	# activation costs nothing.
	var back_button = Button.new()
	back_button.name = "BackToSelectionButton"
	# Plain English, not Ork slang: this dialog is faction-agnostic chrome — a
	# Custodes player has no reason to read "Pick Anuvver Unit" (reported). The
	# Ork voice belongs to the tutorial narrator cards, not to the buttons.
	back_button.text = "◀ Back — Pick Another Unit"
	back_button.tooltip_text = "Un-pick this unit and choose a different one to fight (nothing is assigned yet)"
	back_button.pressed.connect(_on_back_to_selection_pressed)
	button_container.add_child(back_button)

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

	# The E[D] figures above are the whole basis for "Best Weapons" and for any
	# manual weapon comparison, but until now they arrived with no working shown.
	# This folds the derivation away by default (it is a lot of rows for a mob
	# with several sections) and expands it on demand.
	_breakdown_toggle = Button.new()
	_breakdown_toggle.name = "BreakdownToggleButton"
	_breakdown_toggle.text = "▶ Show damage breakdown"
	_breakdown_toggle.tooltip_text = "Show how each E[D] figure is built: attacks → hits → wounds → failed saves → damage → models slain"
	_breakdown_toggle.flat = true
	_breakdown_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_breakdown_toggle.add_theme_font_size_override("font_size", 15)
	_breakdown_toggle.pressed.connect(_on_breakdown_toggled)
	container.add_child(_breakdown_toggle)

	# Bounded height: a 3-section plan renders three tables, and letting them
	# grow the dialog freely pushes "Fight!" off the bottom of the screen.
	_breakdown_scroll = ScrollContainer.new()
	_breakdown_scroll.name = "BreakdownScroll"
	_breakdown_scroll.custom_minimum_size = Vector2(DialogConstants.LARGE.x - 40, 220)
	_breakdown_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_breakdown_scroll.visible = false
	_breakdown_display = RichTextLabel.new()
	_breakdown_display.name = "BreakdownDisplay"
	_breakdown_display.bbcode_enabled = true
	_breakdown_display.fit_content = true
	_breakdown_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_breakdown_scroll.add_child(_breakdown_display)
	container.add_child(_breakdown_scroll)

	# Pad (controller) hint row — the melee twin of the shooting phase's target
	# ring, spelled out for a controller. Shown only when the pad is the active
	# device; a mouse player never sees it. See _pad_handle_input.
	_pad_hint_label = Label.new()
	_pad_hint_label.name = "PadHintLabel"
	if _groups.size() > 1:
		_pad_hint_label.text = "▲▼ Weapon   ·   ◀▶ Target   ·   LB/RB Section   ·   Ⓐ Assign   ·   ☰ Fight!   ·   Ⓑ Back"
	else:
		_pad_hint_label.text = "▲▼ Weapon   ·   ◀▶ Target   ·   Ⓐ Assign   ·   ☰ Fight!   ·   Ⓑ Back"
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
	# EVERY dismissal route is the back-out action, never a silent hide.
	# AcceptDialog emits `canceled` for Escape, the window ✕ and pad Ⓑ (
	# PadBindingManager points ui_cancel at the pad's Back button), and its
	# default handling only calls hide() — which left the activation open with
	# no UI at all. See _on_back_to_selection_pressed.
	canceled.connect(_on_back_to_selection_pressed)
	close_requested.connect(_on_back_to_selection_pressed)

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

# Partition `_eligible_models` by the SET of regular melee weapons each model
# carries. Membership is read back out of `_weapon_carriers`, which is built from
# RulesEngine.get_melee_weapon_swingers — so the dialog's idea of "who carries
# what" is by construction the same one the engine applies when the attacks
# resolve, including its conservative "cannot attribute → everyone" fallback.
# 19.03: the partition is per COMPONENT as well as per loadout. Two components
# can carry an identical weapon set (a Warboss and a Boss Nob both on Big
# choppas) and must still be separate sections — their models are indices into
# different unit dicts, and each resolves against its own profile.
func _build_groups(_unit: Dictionary) -> void:
	_groups = []
	var by_signature: Dictionary = {}

	for key in _eligible_models:
		var owner_id: String = _model_key_unit.get(key, unit_id)
		var idx: int = int(_mk_index(str(key)))
		var carried: Array = []
		for wid in _weapon_carriers:
			if key in _weapon_carriers[wid]:
				carried.append(wid)
		if carried.is_empty():
			# An eligible model with no melee weapon we can attribute simply has
			# nothing to swing — it drops out rather than being given someone
			# else's weapon.
			print("[AttackAssignmentDialog] Model %s carries no listed melee weapon — not grouped" % str(key))
			continue
		carried.sort()
		var signature: String = "%s|%s" % [owner_id, "|".join(carried)]
		if not by_signature.has(signature):
			by_signature[signature] = {
				"key": signature,
				"owner": owner_id,
				"weapons": carried,
				"models": [],
				"labels": [],
			}
		by_signature[signature].models.append(str(key))
		# Label from the datasheet's model_profiles when it names this model type
		# ("Boss Nob" / "Boy"); several types with an identical weapon set share
		# one section and the label lists them.
		var owner_unit: Dictionary = phase_reference.get_unit(owner_id)
		var owner_models: Array = owner_unit.get("models", [])
		var label := _model_type_label(owner_unit, owner_models[idx] if idx < owner_models.size() else {})
		if label == "" and _group_unit_ids.size() > 1:
			# An attached leader usually has no model_profiles of his own —
			# name the section after his unit so "Warboss ×1" reads plainly.
			var om = owner_unit.get("meta", {})
			label = str(om.get("display_name", om.get("name", owner_id)))
		if label != "" and not label in by_signature[signature].labels:
			by_signature[signature].labels.append(label)

	# Sections follow MODEL ORDER — the order the datasheet and the roster list
	# them, so a mob reads "Boss Nob, then the Boyz" exactly as its unit
	# composition does. Ordering by size instead (biggest first) also reorders the
	# submitted assignments, and because a fixed RNG seed consumes dice in
	# assignment order that silently re-rolls every seeded fight: it wiped the
	# Custodian Guard the T6 tutorial needs alive to demonstrate swinging back.
	# 19.03: components first (bodyguard, then its attached characters in
	# attachment order), then model order inside each — so a mob reads
	# "Boss Nob, Boyz, then the Warboss who joined them".
	var order_of := {}
	for i in range(_group_unit_ids.size()):
		order_of[str(_group_unit_ids[i])] = i
	var sigs: Array = by_signature.keys()
	sigs.sort_custom(func(a, b):
		var ga = by_signature[a]
		var gb = by_signature[b]
		var ua: int = int(order_of.get(str(ga.owner), 1 << 30))
		var ub: int = int(order_of.get(str(gb.owner), 1 << 30))
		if ua != ub:
			return ua < ub
		var fa: int = int(_mk_index(str(ga.models[0]))) if not ga.models.is_empty() else 1 << 30
		var fb: int = int(_mk_index(str(gb.models[0]))) if not gb.models.is_empty() else 1 << 30
		if fa != fb:
			return fa < fb
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
	# Cycling is limited to what THIS section has reached, so the tooltip names
	# them — otherwise a section stuck on one target reads as a broken button.
	var reachable_names: Array = []
	for tid in _targets_for_group(gi):
		reachable_names.append(_target_name(str(tid)))
	tgt_button.tooltip_text = "Click to send this section at a different target (in Engagement Range of it: %s)" % ", ".join(reachable_names)
	tgt_button.pressed.connect(_on_group_target_cycle.bind(gi))
	tgt_button.disabled = _targets_for_group(gi).size() < 2
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
		line_tgt.disabled = _targets_for_group(gi).size() < 2
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


# Model keys of every eligible model across the Attached unit that carries
# weapon_id. Used for weapons that are not in `_weapon_carriers` (the
# [EXTRA ATTACKS] previews), which is built from the regular list only.
#
# [EXTRA ATTACKS] needs the datasheet fallback below: loadout resolution keeps
# only the ONE melee weapon a model fights with, so an extra-attacks weapon is
# NOT in any model's resolved loadout and unit_has_melee_weapon reports false
# for it. Attributing by datasheet instead keeps the Warboss's attack squig on
# the Warboss.
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


# ── plan helpers ────────────────────────────────────────────────────────────

func _selected_target_id() -> String:
	if target_list != null and target_list.item_count > 0:
		var sel := target_list.get_selected_items()
		var idx: int = sel[0] if not sel.is_empty() else 0
		return str(target_list.get_item_metadata(idx))
	if not eligible_targets.is_empty():
		return str(eligible_targets.keys()[0])
	return ""


# ── per-component reach (11e "Select Targets") ──────────────────────────────

# Narrow the activation's target list to what each COMPONENT has actually
# reached. FightPhase.melee_targets_for_component measures exactly what
# _validate_assign_attacks measures, so a plan built from these lists can never
# be rejected for engagement range. See _component_targets.
func _build_component_targets() -> void:
	_component_targets = {}
	var candidates: Array = eligible_targets.keys()
	for member_id in _group_unit_ids:
		var reachable: Array = []
		if phase_reference != null and phase_reference.has_method("melee_targets_for_component"):
			reachable = phase_reference.melee_targets_for_component(str(member_id), candidates)
		else:
			# No phase to ask (unit tests constructing the dialog bare): fall
			# back to the activation's list rather than blanking every section.
			reachable = candidates.duplicate()
		_component_targets[str(member_id)] = reachable
		print("[AttackAssignmentDialog] Component '%s' may attack %s (activation offers %s)" % [
			member_id, str(reachable), str(candidates)])


# The targets section `gi` may be pointed at. Only falls back to the whole
# activation's list when this component was never measured (no phase to ask) —
# a component measured as reaching NOTHING must stay empty, or the fallback
# would hand it the very targets the engine is about to reject.
func _targets_for_group(gi: int) -> Array:
	if gi < 0 or gi >= _groups.size():
		return eligible_targets.keys()
	var owner_id := str(_groups[gi].get("owner", unit_id))
	if not _component_targets.has(owner_id):
		return eligible_targets.keys()
	return _component_targets[owner_id]


# True when section `gi` is within Engagement Range of `target_id`.
func _group_can_reach(gi: int, target_id: String) -> bool:
	return target_id != "" and target_id in _targets_for_group(gi)


# `preferred` when this section can reach it, otherwise the reachable target it
# expects to do the most damage to. Never returns an unreachable target — that
# is the whole point: the plan this dialog submits must be legal by
# construction, not legal by luck of geometry.
func _clamp_target_for_group(gi: int, preferred: String) -> String:
	if _group_can_reach(gi, preferred):
		return preferred
	var reachable := _targets_for_group(gi)
	if reachable.is_empty():
		return preferred
	var best_id := str(reachable[0])
	var best_score := -1.0
	var g: Dictionary = _groups[gi]
	for tid in reachable:
		var wid := _best_weapon_for_group(gi, str(tid))
		if wid == "":
			continue
		var score := _estimate_expected_damage(wid, str(tid), g.models.size(), str(g.get("owner", "")))
		if score > best_score:
			best_score = score
			best_id = str(tid)
	if preferred != "":
		print("[AttackAssignmentDialog] Section '%s' is not engaged with %s — swinging at %s instead" % [
			g.label, _target_name(preferred), _target_name(best_id)])
	return best_id


# Component-level twin of _clamp_target_for_group, for assignments that are not
# built from a section (the [EXTRA ATTACKS] auto-adds on confirm).
func _clamp_target_for_component(component_id: String, preferred: String) -> String:
	if not _component_targets.has(component_id):
		return preferred
	var reachable: Array = _component_targets[component_id]
	if reachable.is_empty() or preferred in reachable:
		return preferred
	return str(reachable[0])


# The target this component's regular (non-EXTRA ATTACKS) assignment is already
# pointed at, or "" when it has none.
func _component_regular_target(component_id: String) -> String:
	for a in assignments:
		if str(a.get("attacker", "")) == component_id and str(a.get("target", "")) != "":
			return str(a.get("target", ""))
	return ""


# True when some section cannot reach the dialog's selected target, i.e. the
# bulk actions had to send it somewhere else.
func _plan_has_redirected_sections() -> bool:
	var selected := _selected_target_id()
	if selected == "":
		return false
	for gi in range(_groups.size()):
		if not _group_can_reach(gi, selected):
			return true
	return false


# True when no single target is legal for every section — the components of
# this Attached unit have reached different enemies. Drives the warning note.
func _components_disagree_on_targets() -> bool:
	if _groups.size() < 2:
		return false
	for tid in eligible_targets:
		var reachable_by_all := true
		for gi in range(_groups.size()):
			if not _group_can_reach(gi, str(tid)):
				reachable_by_all = false
				break
		if reachable_by_all:
			return false
	return true


# Give every group the weapon with the highest expected damage against
# `target_id`, un-split, all pointed at that target — or, for a section that is
# not in Engagement Range of it, at the best target that section HAS reached
# (19.03: an Attached unit's components stand apart, and 11e requires each
# target to be engaged with the model swinging at it).
func _apply_best_plan(target_id: String) -> void:
	if target_id == "":
		return
	for gi in range(_groups.size()):
		var g: Dictionary = _groups[gi]
		g.split = false
		var tid := _clamp_target_for_group(gi, target_id)
		var best := _best_weapon_for_group(gi, tid)
		if best == "":
			continue
		g.lines = [{"weapon": best, "count": g.models.size(), "target": tid}]
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
		var score := _estimate_expected_damage(wid, target_id, g.models.size(), str(g.get("owner", "")))
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
			# 19.03: split the picked MODEL KEYS back out per component and file
			# each slice under the unit that owns it — RulesEngine resolves an
			# assignment against its own `attacker`, so the Warboss's power klaw
			# must not be filed under his Boyz (they would swing it, at his
			# profile's expense).
			var by_owner: Dictionary = {}
			for mk in picked:
				var owner_id: String = _mk_unit(str(mk))
				if not by_owner.has(owner_id):
					by_owner[owner_id] = []
				by_owner[owner_id].append(_mk_index(str(mk)))
			# Two groups of the SAME component can legitimately land on the same
			# weapon and target (a Nob and his Boyz both on Choppas); merge so
			# the batch stays one ASSIGN_ATTACKS per attacker/weapon/target
			# rather than one per group.
			for owner_id in by_owner:
				var key := "%s|%s|%s" % [owner_id, wid, tid]
				if merged.has(key):
					merged[key].models.append_array(by_owner[owner_id])
				else:
					var entry := {
						"attacker": owner_id,
						"weapon": wid,
						"target": tid,
						"models": by_owner[owner_id]
					}
					merged[key] = entry
					assignments.append(entry)

	for a in assignments:
		print("[AttackAssignmentDialog] Assignment: %s swings %s → %s (%d model(s): %s)" % [
			a.attacker, a.weapon, a.target, a.models.size(), str(a.models)])
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
				ed += _estimate_expected_damage(str(line.get("weapon", "")), str(line.get("target", "")), count,
					str(g.get("owner", "")))
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
	tid = _clamp_target_for_group(gi, tid)
	g.split = false
	g.lines = [{"weapon": wid, "count": g.models.size(), "target": tid}]
	print("[AttackAssignmentDialog] Group '%s' → %s (%d model(s))" % [g.label, wid, g.models.size()])
	_sync_group_widgets()
	_rebuild_assignments()


# Cycling walks THIS section's reachable targets, not the activation's — a
# section can only ever be pointed at an enemy its own models have reached.
func _on_group_target_cycle(gi: int) -> void:
	var g: Dictionary = _groups[gi]
	var keys: Array = _targets_for_group(gi)
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
	var keys: Array = _targets_for_group(gi)
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
			# otherwise Ⓑ is "back to fighter selection". It used to fall through
			# to AcceptDialog's ui_cancel default, which merely HID the dialog and
			# left the activation open with no UI — the reported T6 soft-lock.
			var skip_btn := _find_child_button("SkipFightButton")
			if skip_btn != null and skip_btn.visible and not skip_btn.disabled:
				_on_skip_fight_pressed()
			else:
				_on_back_to_selection_pressed()
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
	# The selected target may be one only ANOTHER component of this Attached
	# unit has reached — send this section at something it is actually engaged
	# with rather than building a plan the engine will reject.
	var clamped_id := _clamp_target_for_group(_focused_group, target_id)
	if clamped_id != target_id:
		_notify_redirect(g, target_id, clamped_id)
	g.split = false
	g.lines = [{"weapon": weapon_id, "count": g.models.size(), "target": clamped_id}]
	print("[AttackAssignmentDialog] Group '%s' assigned %s → %s (%d model(s))" % [
		g.label, weapon_id, clamped_id, g.models.size()])
	_sync_group_widgets()
	_rebuild_assignments()


# Tell the player when a bulk action could not honour their target pick. Silent
# redirection is how the old behaviour hid the problem in the first place.
func _notify_redirect(g: Dictionary, wanted: String, used: String) -> void:
	var toast := get_node_or_null("/root/ToastManager")
	if toast != null and toast.has_method("show_toast"):
		toast.show_toast("%s is not in Engagement Range of %s — swinging at %s" % [
			g.get("label", "Section"), _target_name(wanted), _target_name(used)])


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
	var redirected := 0
	for gi in range(_groups.size()):
		var g: Dictionary = _groups[gi]
		# Sections of an Attached unit stand in different places — one may not
		# have reached this target at all (11e: each target must be engaged
		# with the model swinging at it). Send those at what they CAN hit.
		var clamped_id := _clamp_target_for_group(gi, target_id)
		if clamped_id != target_id:
			redirected += 1
			_notify_redirect(g, target_id, clamped_id)
		if g.lines.is_empty():
			var best := _best_weapon_for_group(gi, clamped_id)
			if best != "":
				g.lines = [{"weapon": best, "count": g.models.size(), "target": clamped_id}]
			continue
		for line in g.lines:
			line["target"] = clamped_id
	print("[AttackAssignmentDialog] All %d section(s) → %s (%d redirected — not engaged with it)" % [
		_groups.size(), target_id, redirected])
	_sync_group_widgets()
	_rebuild_assignments()


# "Best Weapons": re-derive the whole plan — best weapon per section against the
# selected target, splits merged. The one-click way back to a sane default after
# manual fiddling, and the plan the dialog already opens on.
func _on_best_krump_pressed() -> void:
	var target_id := _selected_target_id()
	print("[AttackAssignmentDialog] Best Weapons: auto-assigning %d section(s) vs %s" % [_groups.size(), target_id])
	var redirected := _plan_has_redirected_sections()
	_apply_best_plan(target_id)
	var toast := get_node_or_null("/root/ToastManager")
	if toast != null:
		# A section not in Engagement Range of the selected target gets the best
		# target it HAS reached — say so, rather than letting the assignment
		# list quietly disagree with the target the player clicked.
		if redirected:
			toast.show_toast("✨ Best weapon per section — some are locked with a different enemy and swing at that instead")
		else:
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
		var ed: float = _estimate_expected_damage(assignment.weapon, assignment.target, swinging,
			str(assignment.get("attacker", "")))
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
			# 19.03: count carriers across every component of the Attached unit
			# (the Warboss's attack squig swings with his Boyz).
			var ea_carriers: Array = _carriers_across_group(weapon_id)
			var ed: float = _estimate_expected_damage(weapon_id, ea_target_id, ea_carriers.size())
			total_expected_damage += ed
			assignments_display.append_text("- %s → %s (%d model%s) [Extra Attacks, E[D]≈%.1f]\n" % [
				weapon_name, _target_name(str(ea_target_id)), ea_carriers.size(),
				"" if ea_carriers.size() == 1 else "s", ed])
	if total_expected_damage > 0.0:
		assignments_display.append_text("[b]Total expected damage: %.1f[/b]\n" % total_expected_damage)

	_render_breakdown()
	# Swapping a weapon with the section open changes how many rows it holds —
	# re-fit so the last footnote never ends up half under the dialog edge.
	if _breakdown_scroll != null and _breakdown_scroll.visible:
		_refit_breakdown()


# ── damage breakdown table ──────────────────────────────────────────────────

func _on_breakdown_toggled() -> void:
	if _breakdown_scroll == null or _breakdown_toggle == null:
		return
	_breakdown_scroll.visible = not _breakdown_scroll.visible
	_breakdown_toggle.text = "▼ Hide damage breakdown" if _breakdown_scroll.visible \
		else "▶ Show damage breakdown"
	print("[AttackAssignmentDialog] Damage breakdown %s" % ("expanded" if _breakdown_scroll.visible else "collapsed"))
	_render_breakdown()
	_refit_breakdown()


# Size the section to the tables it actually holds (bounded, so a five-section
# plan still scrolls rather than growing without limit), let the dialog re-fit
# around it, and keep the result on screen. Deferred a frame because a
# RichTextLabel only knows its content height once it has laid the tables out.
func _refit_breakdown() -> void:
	if _breakdown_scroll == null or not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree() or _breakdown_scroll == null or _breakdown_display == null:
		return
	if _breakdown_scroll.visible:
		_breakdown_scroll.custom_minimum_size.y = clampf(
			_breakdown_display.get_content_height() + 12.0, 120.0, 320.0)
		await get_tree().process_frame
		if not is_inside_tree():
			return
	reset_size()
	_keep_on_screen()


# An expanded breakdown can push the dialog past the bottom of the window, where
# the very rows the player opened it to read are the ones that fall off. Clamp
# the height to the viewport and slide the dialog back up to fit.
func _keep_on_screen() -> void:
	# Only meaningful for an embedded subwindow, where `position` is in the
	# parent viewport's coordinates. As a native OS window it is in screen
	# space and the window manager already places it.
	if not is_embedded():
		return
	var vp: Vector2 = get_tree().root.get_visible_rect().size
	if vp.y <= 0.0:
		return
	var max_h := int(vp.y - 16.0)
	if size.y > max_h:
		size = Vector2i(size.x, max_h)
	var max_y := int(max(8.0, vp.y - float(size.y) - 8.0))
	position = Vector2i(position.x, clampi(position.y, 8, max_y))


# The same rows the assignments display lists, as
# {weapon, target, models, owner, extra} — one source of truth so a table row
# can never describe an assignment that is not in the plan.
func _breakdown_rows() -> Array:
	var rows: Array = []
	for a in assignments:
		rows.append({
			"weapon": str(a.get("weapon", "")),
			"target": str(a.get("target", "")),
			"models": (a.get("models", []) as Array).size(),
			"owner": str(a.get("attacker", "")),
			"extra": false,
		})
	if not extra_attacks_weapons.is_empty():
		var ea_target_id := str(_get_extra_attacks_target_id())
		for weapon in extra_attacks_weapons:
			var wid: String = RulesEngine.generate_weapon_id(str(weapon.get("name", "")), str(weapon.get("type", "")))
			var carriers: Array = _carriers_across_group(wid)
			rows.append({
				"weapon": wid,
				"target": ea_target_id,
				"models": carriers.size(),
				"owner": _mk_unit(str(carriers[0])) if not carriers.is_empty() else "",
				"extra": true,
			})
	return rows


# One table per assignment: the hit → wound → save → damage chain, each step
# showing what it needs, how likely it is and what is left after it. The final
# DAMAGE row is by construction the same `E[D]` printed on the assignment row
# above, so the table explains that number rather than competing with it.
func _render_breakdown() -> void:
	if _breakdown_display == null:
		return
	_breakdown_display.clear()

	var rows: Array = _breakdown_rows()
	if rows.is_empty():
		_breakdown_display.append_text("[i]Nothing assigned yet — pick a weapon for a section above.[/i]")
		return

	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var bd: Dictionary = _damage_breakdown(str(row.weapon), str(row.target), int(row.models), str(row.owner))
		if bd.is_empty():
			continue
		if i > 0:
			_breakdown_display.append_text("\n")
		_breakdown_display.append_text("[bgcolor=#2a2314][b][color=#E8C477] ⚔ %s → %s · %d model%s%s [/color][/b][/bgcolor]\n" % [
			bd.weapon_name, _target_name(str(row.target)), int(row.models),
			"" if int(row.models) == 1 else "s",
			" · Extra Attacks" if row.extra else ""])
		_render_breakdown_table(bd)
		_render_breakdown_footnotes(bd)


func _render_breakdown_table(bd: Dictionary) -> void:
	var rtl := _breakdown_display
	rtl.push_table(4)
	rtl.set_table_column_expand(0, false)
	rtl.set_table_column_expand(1, true)
	rtl.set_table_column_expand(2, false)
	rtl.set_table_column_expand(3, false)

	_bd_header_cell("STEP")
	_bd_header_cell("NEEDS")
	_bd_header_cell("CHANCE")
	_bd_header_cell("EXPECTED")

	_bd_row("ATTACKS", Color(0.30, 0.34, 0.40),
		"%s each × %d model%s" % [bd.attacks_str, int(bd.models), "" if int(bd.models) == 1 else "s"],
		"—",
		"[b]%s[/b] attacks" % _bd_num(bd.total_attacks))

	_bd_row("HIT", Color(0.16, 0.38, 0.62),
		"WS %d+" % int(bd.skill),
		"%.0f%%" % (float(bd.p_hit) * 100.0),
		"[b]%s[/b] hits" % _bd_num(bd.expected_hits))

	_bd_row("WOUND", Color(0.66, 0.38, 0.12),
		"S%d vs T%d → %d+" % [int(bd.strength), int(bd.toughness), int(bd.wound_need)],
		"%.0f%%" % (float(bd.p_wound) * 100.0),
		"[b]%s[/b] wounds" % _bd_num(bd.expected_wounds))

	# Which save the defender actually gets, and why. An invulnerable save
	# ignores AP entirely, so naming the one in use is the difference between
	# "AP-3 strips their armour" and "AP-3 does nothing, they have a 4++".
	var save_text := ""
	if int(bd.effective_save) >= 7:
		save_text = "Sv %d+ %s → no save" % [int(bd.target_save), _bd_ap(int(bd.ap))]
	elif bd.uses_invuln:
		save_text = "%d++ invuln (ignores %s)" % [int(bd.target_invuln), _bd_ap(int(bd.ap))]
	else:
		save_text = "Sv %d+ %s → %d+" % [int(bd.target_save), _bd_ap(int(bd.ap)), int(bd.modified_save)]
	_bd_row("SAVE", Color(0.44, 0.30, 0.66),
		save_text,
		"%.0f%% fail" % (float(bd.p_unsaved) * 100.0),
		"[b]%s[/b] unsaved" % _bd_num(bd.expected_unsaved))

	_bd_row("DAMAGE", Color(0.58, 0.48, 0.10),
		"%s per unsaved wound" % str(bd.damage_str),
		"—",
		"[b]%s[/b] damage" % _bd_num(bd.expected_damage / max(0.0001, float(bd.p_damage_through))))

	if int(bd.fnp) >= 2 and int(bd.fnp) <= 6:
		_bd_row("FNP", Color(0.10, 0.52, 0.34),
			"Feel No Pain %d+" % int(bd.fnp),
			"%.0f%% ignored" % ((1.0 - float(bd.p_damage_through)) * 100.0),
			"[b]%s[/b] damage" % _bd_num(bd.expected_damage))

	_bd_row("SLAIN", Color(0.55, 0.16, 0.16),
		"%d wound%s per model" % [int(bd.wounds_per_model), "" if int(bd.wounds_per_model) == 1 else "s"],
		"—",
		"[b]≈%s[/b] of %d slain" % [_bd_num(bd.expected_slain), int(bd.alive_models)])

	rtl.pop()  # table
	# A table is an INLINE element: without this the footnotes below render on
	# the table's own line, i.e. floating to the right of the header row.
	rtl.append_text("\n")


# Notes under the table: the two things a raw E[D] number hides.
func _render_breakdown_footnotes(bd: Dictionary) -> void:
	var rtl := _breakdown_display
	if float(bd.wasted_damage) >= 0.05:
		rtl.append_text("[font_size=13][color=#C98A8A]  ⚠ %s damage per wound vs %d-wound models — ≈%s of the %s damage is lost to overkill.[/color][/font_size]\n" % [
			str(bd.damage_str), int(bd.wounds_per_model), _bd_num(bd.wasted_damage), _bd_num(bd.expected_damage)])
	var caveats: Array = (bd.get("unmodelled", []) as Array).duplicate()
	caveats.append("re-rolls / modifiers / cover / stratagems")
	rtl.append_text("[font_size=13][color=#8F9AA8]  Not modelled: %s.[/color][/font_size]\n" % ", ".join(caveats))


func _bd_header_cell(text: String) -> void:
	var rtl := _breakdown_display
	rtl.push_cell()
	rtl.set_cell_padding(Rect2(6, 2, 6, 2))
	rtl.append_text("[font_size=12][color=#8F9AA8][b]%s[/b][/color][/font_size]" % text)
	rtl.pop()


# One step row: a solid colored chip in the fixed left column (the same step
# colors the Dice Log uses, so both read as one language), then the plain-text
# columns.
func _bd_row(chip: String, chip_bg: Color, needs: String, chance: String, leaves: String) -> void:
	var rtl := _breakdown_display
	rtl.push_cell()
	rtl.set_cell_row_background_color(chip_bg, chip_bg)
	rtl.set_cell_padding(Rect2(6, 2, 6, 2))
	rtl.append_text("[font_size=12][b]%s[/b][/font_size]" % chip)
	rtl.pop()
	for text in [needs, chance, leaves]:
		rtl.push_cell()
		rtl.set_cell_padding(Rect2(6, 2, 6, 2))
		rtl.append_text("[font_size=14]%s[/font_size]" % text)
		rtl.pop()


# Whole numbers stay whole ("5 attacks", not "5.0 attacks"); everything else
# keeps one decimal, which is the precision the assignment rows already print.
static func _bd_num(v: float) -> String:
	if is_equal_approx(v, round(v)):
		return "%d" % int(round(v))
	return "%.1f" % v


static func _bd_ap(ap: int) -> String:
	return "AP0" if ap == 0 else "AP-%d" % abs(ap)


# T-093: analytic expected-damage estimator for AttackAssignmentDialog preview.
# Uses standard Warhammer 10e/11e math: E[D] = A * Phit * Pwound * Punsaved * D
# where probability functions parse weapon profile + defender stats.
#
# This single float is what the group summaries, the assignment rows and the
# "Best Weapons" auto-pick all score on. `damage_breakdown()` below is the SAME
# computation with every intermediate kept, so the collapsible table can show a
# player where the number comes from and still add up to exactly this figure.
func _estimate_expected_damage(weapon_id: String, target_id: String, swinging_models: int = -1, prefer_unit_id: String = "") -> float:
	var bd := _damage_breakdown(weapon_id, target_id, swinging_models, prefer_unit_id)
	return float(bd.get("expected_damage", 0.0))


# Resolve the weapon profile and the defender off the live board, then hand the
# pure math to `damage_breakdown()`. Returns {} when either side is unresolvable.
func _damage_breakdown(weapon_id: String, target_id: String, swinging_models: int = -1, prefer_unit_id: String = "") -> Dictionary:
	if phase_reference == null or unit_id == "" or target_id == "":
		return {}
	var target_unit = phase_reference.get_unit(target_id)
	if target_unit.is_empty():
		return {}
	# Find weapon. 19.03: search every component of the Attached unit — the
	# attached leader's power klaw is not on his bodyguard's datasheet, and
	# without this its forecast row silently read 0 (and the "best weapon"
	# auto-plan would never pick it). The component that ACTUALLY swings it is
	# searched first: a Warboss and his Boss Nob can both carry a "Power klaw"
	# with different stats, and scoring his swing on the mob's profile is wrong
	# by ~40% — the same trap Mathhammer.resolve_weapon_profile documents.
	var search_order: Array = []
	if prefer_unit_id != "":
		search_order.append(prefer_unit_id)
	for member_id in (_group_unit_ids if not _group_unit_ids.is_empty() else [unit_id]):
		if not member_id in search_order:
			search_order.append(member_id)
	var weapon: Dictionary = {}
	for member_id in search_order:
		for w in phase_reference.get_unit(member_id).get("meta", {}).get("weapons", []):
			var wname = w.get("name", "")
			var wid = RulesEngine.generate_weapon_id(wname, w.get("type", ""))
			if wid == weapon_id or wname == weapon_id:
				weapon = w
				break
		if not weapon.is_empty():
			break
	if weapon.is_empty():
		return {}
	# Total attacks = per-weapon attacks x the models actually swinging it.
	# MA-LOADOUT: the caller passes that count (the assignment's model list), so
	# the preview no longer multiplies a one-model Power klaw by the whole mob.
	# Fall back to the eligible-and-equipped count when it is not supplied.
	var swinging: int = swinging_models
	if swinging < 0:
		swinging = _carriers_across_group(weapon_id).size()
	# FNP is passed in rather than read inside `damage_breakdown`: the real value
	# can be granted by an effect (not just the datasheet), and only RulesEngine
	# knows about those — keeping that lookup out here is what lets the math stay
	# a pure, board-free static function.
	var bd := damage_breakdown(weapon, target_unit, swinging, RulesEngine.get_unit_fnp(target_unit))
	bd["target_name"] = _target_name(target_id)
	return bd


# Weapon abilities that bend the hit → wound → save chain but which the forecast
# below does NOT apply, mapped to the label the table footnote prints. Naming
# them is the honest half of showing the working: a player reading a Sustained
# Hits 1 profile's `E[D]≈3.1` should know the real figure is higher, rather than
# trusting a number the resolution step will not reproduce.
const _UNMODELLED_ABILITIES := {
	"sustained_hits": "Sustained Hits",
	"lethal_hits": "Lethal Hits",
	"devastating_wounds": "Devastating Wounds",
	"twin_linked": "Twin-linked",
	"anti": "Anti-X",
	"lance": "Lance",
	"melta": "Melta",
	"blast": "Blast",
}


# The whole chain for `swinging_models` models swinging `weapon` at
# `target_unit`, with every intermediate value kept so the breakdown table can
# show its working. Static and board-free (the caller resolves both dictionaries)
# so the math is testable headless.
#
# Deliberately coarse — `unmodelled` names what it skips. It models exactly what
# the assignment rows have always shown, so the table's DAMAGE row is the same
# `E[D]` figure printed next to the assignment; nothing new is invented for the
# table and no forecast changes because it was opened.
static func damage_breakdown(weapon: Dictionary, target_unit: Dictionary, swinging_models: int, fnp_override: int = -1) -> Dictionary:
	if weapon.is_empty() or target_unit.is_empty():
		return {}

	var stats: Dictionary = target_unit.get("meta", {}).get("stats", {})
	var models: int = max(1, swinging_models)

	# ATTACKS
	var attacks_str: String = str(weapon.get("attacks", "1"))
	var attacks_avg: float = _average_dice_notation(attacks_str)
	var total_attacks: float = attacks_avg * float(models)

	# HIT — from WS/BS (the weapon's accuracy attribute). `weapon_skill` is the
	# key the army JSONs actually use — without it every melee weapon scored as
	# WS4+, which made the auto-pick blind to a Nob's WS3 Choppa vs his WS4
	# Power klaw.
	var skill_int: int = _parse_stat_int(str(weapon.get("skill",
		weapon.get("weapon_skill", weapon.get("ws", weapon.get("bs", "4"))))))
	var p_hit: float = clampf(float(7 - skill_int) / 6.0, 1.0/6.0, 5.0/6.0)
	var expected_hits: float = total_attacks * p_hit

	# WOUND — the 10e/11e S-vs-T chart.
	var strength_int: int = _parse_stat_int(str(weapon.get("strength", "4")))
	var target_T: int = max(1, _parse_stat_int(str(stats.get("toughness", 4))))
	var wound_need: int = _wound_threshold(strength_int, target_T)
	var p_wound: float = float(7 - wound_need) / 6.0
	var expected_wounds: float = expected_hits * p_wound

	# SAVE — AP WORSENS a save, and the army JSONs store it negative ("-2"). The
	# old `target_save - max(0, ap_int)` clamped every negative AP to 0, so AP was
	# silently ignored — which made the preview flatter than reality and, now that
	# the auto-pick is driven by this number, would have handed a Boss Nob his Big
	# choppa over the AP-2 Power klaw against 2+ armour. Take the magnitude and
	# add it; 7+ means no save at all. An invulnerable save is never modified by
	# AP, so the defender uses whichever of the two is better.
	var ap_int: int = _parse_stat_int(str(weapon.get("ap", "0")))
	var ap_penalty: int = abs(ap_int)
	var target_save: int = _parse_stat_int(str(stats.get("save", 5)))
	if target_save <= 0:
		target_save = 7
	var target_invuln: int = _parse_stat_int(str(stats.get("invuln", 7)))
	# A datasheet with no invuln stores 0, not 7 — reading that literally gave an
	# "effective save 0+", i.e. a 0% chance of any damage getting through.
	if target_invuln <= 0:
		target_invuln = 7
	var modified_save: int = min(7, target_save + ap_penalty)
	var effective_save: int = min(modified_save, target_invuln)
	var p_unsaved: float = clampf(float(effective_save - 1) / 6.0, 0.0, 1.0)
	var expected_unsaved: float = expected_wounds * p_unsaved

	# DAMAGE
	var damage_str: String = str(weapon.get("damage", "1"))
	var damage_avg: float = _average_dice_notation(damage_str)

	# FEEL NO PAIN — rolled per point of damage, so it scales the whole total.
	# It applies identically to every weapon against the same defender, so
	# folding it in cannot re-order "Best Weapons"; it just stops the forecast
	# over-promising against a 5+++ target.
	var fnp: int = fnp_override if fnp_override >= 0 else _parse_stat_int(str(stats.get("fnp", 0)))
	var p_damage_through: float = 1.0
	if fnp >= 2 and fnp <= 6:
		p_damage_through = clampf(float(fnp - 1) / 6.0, 0.0, 1.0)
	var expected_damage: float = expected_unsaved * damage_avg * p_damage_through

	# MODELS SLAIN — the number the player is usually really after, and NOT the
	# same as expected damage: damage spilling past a model's last wound is lost
	# (10e/11e), so a D3 weapon throws away two thirds of every hit on 1-wound
	# Stormboyz. Reporting only E[D] made a 5A/D3 profile look nearly three times
	# better than a 9A/D1 one that actually kills more of them.
	var alive_models: int = 0
	var wounds_per_model: int = 0
	for m in target_unit.get("models", []):
		if not m.get("alive", true):
			continue
		alive_models += 1
		wounds_per_model = max(wounds_per_model, int(m.get("wounds", 1)))
	if wounds_per_model <= 0:
		wounds_per_model = max(1, _parse_stat_int(str(stats.get("wounds", 1))))
	if alive_models <= 0:
		alive_models = max(1, target_unit.get("models", []).size())
	var damage_per_wound: float = min(damage_avg, float(wounds_per_model)) * p_damage_through
	var expected_slain: float = min(
		float(alive_models),
		expected_unsaved * damage_per_wound / float(wounds_per_model))
	var wasted_damage: float = max(0.0, expected_unsaved * (damage_avg - float(wounds_per_model)) * p_damage_through)

	var unmodelled: Array = []
	for ability in weapon.get("abilities", []):
		var aid := ""
		if typeof(ability) == TYPE_DICTIONARY:
			aid = str(ability.get("id", ""))
		elif typeof(ability) == TYPE_STRING:
			aid = str(ability)
		if _UNMODELLED_ABILITIES.has(aid) and not _UNMODELLED_ABILITIES[aid] in unmodelled:
			unmodelled.append(_UNMODELLED_ABILITIES[aid])

	return {
		"weapon_name": str(weapon.get("name", "?")),
		"target_name": str(target_unit.get("meta", {}).get("name", "target")),
		"models": models,
		"attacks_str": attacks_str,
		"attacks_avg": attacks_avg,
		"total_attacks": total_attacks,
		"skill": skill_int,
		"p_hit": p_hit,
		"expected_hits": expected_hits,
		"strength": strength_int,
		"toughness": target_T,
		"wound_need": wound_need,
		"p_wound": p_wound,
		"expected_wounds": expected_wounds,
		"ap": ap_int,
		"target_save": target_save,
		"target_invuln": target_invuln,
		"modified_save": modified_save,
		"effective_save": effective_save,
		"uses_invuln": target_invuln < modified_save,
		"p_unsaved": p_unsaved,
		"expected_unsaved": expected_unsaved,
		"damage_str": damage_str,
		"damage_avg": damage_avg,
		"fnp": fnp,
		"p_damage_through": p_damage_through,
		"expected_damage": expected_damage,
		"wounds_per_model": wounds_per_model,
		"alive_models": alive_models,
		"expected_slain": expected_slain,
		"wasted_damage": wasted_damage,
		"unmodelled": unmodelled,
	}


static func _parse_stat_int(s: String) -> int:
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


static func _average_dice_notation(s: String) -> float:
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


# The roll a wound needs on the 10e/11e S-vs-T chart. Split out of
# `_wound_probability` so the breakdown table can print "S6 vs T5 → 3+" rather
# than only the resulting percentage.
static func _wound_threshold(s: int, t: int) -> int:
	if s >= t * 2:
		return 2
	if s > t:
		return 3
	if s == t:
		return 4
	if s * 2 <= t:
		return 6
	return 5


static func _wound_probability(s: int, t: int) -> float:
	return float(7 - _wound_threshold(s, t)) / 6.0

func _on_skip_fight_pressed() -> void:
	print("[AttackAssignmentDialog] Skip fight pressed (no eligible targets) for unit: ", unit_id)
	hide()
	emit_signal("skip_fight_requested", unit_id)
	queue_free()

# Back out of the activation entirely: nothing has been assigned, so the unit is
# un-picked and the fighter-selection panel comes back. Guarded against
# re-entry — `canceled`, `close_requested` and the button can all fire for one
# dismissal, and hide() below can itself re-emit close_requested.
var _cancelling: bool = false

func _on_back_to_selection_pressed() -> void:
	if _cancelling:
		return
	_cancelling = true
	print("[AttackAssignmentDialog] Back to fighter selection requested for unit: ", unit_id)
	hide()
	emit_signal("selection_cancelled", unit_id)
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
	# 19.03: attribute each one to the component that actually CARRIES it. The
	# Warboss's attack squig is not on his Boyz' datasheet, and filing it under
	# the bodyguard handed the whole mob one — RulesEngine falls back to "every
	# model" for a weapon it cannot attribute to the named unit.
	if not extra_attacks_weapons.is_empty():
		var ea_target_id = _get_extra_attacks_target_id()
		for weapon in extra_attacks_weapons:
			var weapon_name = weapon.get("name", "Unknown")
			var weapon_id = RulesEngine.generate_weapon_id(weapon_name, weapon.get("type", ""))
			var ea_by_owner: Dictionary = {}
			for mk in _carriers_across_group(weapon_id):
				var owner_id: String = _mk_unit(str(mk))
				if not ea_by_owner.has(owner_id):
					ea_by_owner[owner_id] = []
				ea_by_owner[owner_id].append(_mk_index(str(mk)))
			if ea_by_owner.is_empty():
				# Unattributable — keep the historical whole-unit form and let
				# the engine narrow it.
				assignments.append({
					"attacker": unit_id,
					"weapon": weapon_id,
					"target": ea_target_id
				})
				print("[AttackAssignmentDialog] T3-3: Auto-added Extra Attacks weapon '%s' → '%s' (whole unit)" % [weapon_name, ea_target_id])
				continue
			for owner_id in ea_by_owner:
				# The Extra Attacks target selector is activation-level, but
				# these attacks come from ONE component's models and are gated
				# per component like any other (11e: each target must be
				# engaged with the model that has that weapon). Send them at
				# whatever that component's regular weapon is already swinging
				# at — the Warboss's attack squig hits what his klaw hits — and
				# fall back to the nearest legal target for it.
				var ea_owner_target := _component_regular_target(str(owner_id))
				if ea_owner_target == "":
					ea_owner_target = _clamp_target_for_component(str(owner_id), ea_target_id)
				assignments.append({
					"attacker": owner_id,
					"weapon": weapon_id,
					"target": ea_owner_target,
					"models": ea_by_owner[owner_id]
				})
				print("[AttackAssignmentDialog] T3-3: Auto-added Extra Attacks weapon '%s' for %s (%d model(s)) → '%s'" % [
					weapon_name, owner_id, ea_by_owner[owner_id].size(), ea_owner_target])

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
