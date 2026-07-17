extends AcceptDialog

const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")

# WeaponOrderDialog - Allows players to order weapons before shooting sequence
# Phase 1 MVP: Basic ordering with up/down arrows, fast roll option

signal weapon_order_confirmed(weapon_order: Array, fast_roll: bool)
# Staged sequential resolution (non-networked): the dialog stays open through the
# hit roll and wound roll of the current weapon, driving these:
signal staged_continue_requested(next_step: String)      # "wounds" or "saves"
signal staged_reroll_requested(stage: String, die_index: int)  # Command Re-roll a hit/wound die
signal staged_fast_finish_requested()                    # "Fast Roll" — resolve the rest with no more pauses

# Weapon ordering data
var weapon_assignments: Array = []  # Original assignments from shooting phase
var weapon_order: Array = []  # Ordered list of weapon_ids
var weapon_data: Dictionary = {}  # weapon_id -> {name, count, damage, etc.}
var current_phase = null  # Reference to ShootingPhase for signal connections
var is_resolving: bool = false  # Track if sequence is currently resolving

# UI Nodes
var vbox: VBoxContainer
var instruction_label: Label
var firing_order_label: Label        # "FIRING ORDER" section header ("WEAPON" when single)
var weapon_scroll: ScrollContainer   # scroll area wrapping weapon_list_container
var weapon_list_container: VBoxContainer
var weapon_items: Array = []  # Array of weapon item panels for reordering
var button_hbox: HBoxContainer
var fast_roll_button: Button
var start_sequence_button: Button
var close_button: Button
var dice_log_rich_text: RichTextLabel

# Staged-resolution UI
var staged_continue_button: Button   # "Roll to Wound ▶" / "Continue to Saving Throws ▶"
var fast_finish_button: Button       # "Fast Roll ⏩" — skip remaining pauses (single-weapon staged)
var reroll_label: Label              # "Command Re-roll available (1 CP)…"
var reroll_row: HBoxContainer        # one button per die to re-roll
var current_stage: String = ""       # "hits" | "wounds" while paused
# When true this dialog was opened for a SINGLE weapon and auto-started the
# step-by-step roll (hit → pause → wound → pause → saves) with no ordering step.
var _single_weapon_staged: bool = false

func _ready() -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	# Stable node name so windowed scenarios can address the dialog + its buttons.
	name = "WeaponOrderDialog"
	# Set dialog properties
	title = "Choose Weapon Order"
	dialog_hide_on_ok = false

	# Set dialog size (increased to accommodate dice log)
	min_size = DialogConstants.LARGE

	# Hide default OK button
	get_ok_button().hide()

	# Create main container
	vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(DialogConstants.LARGE.x - 20, 0)
	add_child(vbox)

	# Instruction label
	instruction_label = Label.new()
	instruction_label.text = "Drag or use arrows to set weapon firing order.\nHigher damage weapons are prioritized by default."
	instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction_label.add_theme_font_size_override("font_size", 12)
	instruction_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	vbox.add_child(instruction_label)

	_add_weapon_order_gold_separator(vbox)

	# Weapon list section
	firing_order_label = Label.new()
	firing_order_label.name = "FiringOrderLabel"
	firing_order_label.text = "FIRING ORDER"
	firing_order_label.add_theme_font_size_override("font_size", 13)
	firing_order_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	vbox.add_child(firing_order_label)

	weapon_scroll = ScrollContainer.new()
	weapon_scroll.name = "WeaponScroll"
	weapon_scroll.custom_minimum_size = Vector2(DialogConstants.LARGE.x - 40, 220)
	vbox.add_child(weapon_scroll)

	weapon_list_container = VBoxContainer.new()
	weapon_list_container.name = "WeaponListContainer"
	weapon_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weapon_scroll.add_child(weapon_list_container)

	_add_weapon_order_gold_separator(vbox)

	# Action buttons
	button_hbox = HBoxContainer.new()
	button_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_hbox)

	fast_roll_button = Button.new()
	fast_roll_button.text = "Fast Roll All"
	fast_roll_button.tooltip_text = "Resolve all weapons simultaneously (skip ordering)"
	fast_roll_button.pressed.connect(_on_fast_roll_pressed)
	fast_roll_button.custom_minimum_size = Vector2(160, 42)
	WhiteDwarfTheme.apply_secondary_button(fast_roll_button)
	button_hbox.add_child(fast_roll_button)

	start_sequence_button = Button.new()
	start_sequence_button.text = "Start Sequence"
	start_sequence_button.tooltip_text = "Resolve weapons one at a time in the order shown"
	start_sequence_button.pressed.connect(_on_start_sequence_pressed)
	start_sequence_button.custom_minimum_size = Vector2(160, 42)
	WhiteDwarfTheme.apply_primary_button(start_sequence_button)
	button_hbox.add_child(start_sequence_button)

	# Staged-resolution continue button ("Roll to Wound ▶" / "Continue to Saving
	# Throws ▶"). This REPLACES the old bare "Close" during staged resolution so
	# the player always knows what the next step actually is.
	staged_continue_button = Button.new()
	staged_continue_button.name = "StagedContinueButton"
	staged_continue_button.text = "Continue ▶"
	staged_continue_button.pressed.connect(_on_staged_continue_pressed)
	staged_continue_button.custom_minimum_size = Vector2(240, 42)
	WhiteDwarfTheme.apply_primary_button(staged_continue_button)
	button_hbox.add_child(staged_continue_button)
	staged_continue_button.visible = false

	# "Fast Roll" escape for the single-weapon step-by-step flow: resolve the rest
	# of the shot at once (skip the remaining hit/wound pauses). Only shown while a
	# single-weapon staged resolution is paused.
	fast_finish_button = Button.new()
	fast_finish_button.name = "FastFinishButton"
	fast_finish_button.text = "Fast Roll ⏩"
	fast_finish_button.tooltip_text = "Resolve the rest of this shot at once (skip the remaining step-by-step pauses)"
	fast_finish_button.pressed.connect(_on_fast_finish_pressed)
	fast_finish_button.custom_minimum_size = Vector2(140, 42)
	WhiteDwarfTheme.apply_secondary_button(fast_finish_button)
	button_hbox.add_child(fast_finish_button)
	fast_finish_button.visible = false

	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close"
	close_button.pressed.connect(_on_close_pressed)
	close_button.custom_minimum_size = Vector2(100, 42)
	close_button.visible = false
	WhiteDwarfTheme.apply_secondary_button(close_button)
	button_hbox.add_child(close_button)

	# NEW: Continue button for mid-sequence progression
	# Make it visible by default so user can always progress
	var continue_button = Button.new()
	continue_button.name = "ContinueButton"
	continue_button.text = "Next Weapon"
	continue_button.pressed.connect(_on_continue_next_weapon_pressed)
	continue_button.custom_minimum_size = Vector2(160, 42)
	WhiteDwarfTheme.apply_primary_button(continue_button)
	button_hbox.add_child(continue_button)
	continue_button.visible = false

	_add_weapon_order_gold_separator(vbox)

	# Command Re-roll affordance (staged resolution): a row of per-die buttons the
	# attacker can click to re-roll a single hit/wound die with Command Re-roll.
	reroll_label = Label.new()
	reroll_label.name = "RerollLabel"
	reroll_label.add_theme_font_size_override("font_size", 12)
	reroll_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	reroll_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reroll_label.visible = false
	vbox.add_child(reroll_label)

	reroll_row = HBoxContainer.new()
	reroll_row.name = "RerollRow"
	reroll_row.visible = false
	var reroll_scroll = ScrollContainer.new()
	reroll_scroll.custom_minimum_size = Vector2(DialogConstants.LARGE.x - 40, 44)
	reroll_scroll.add_child(reroll_row)
	vbox.add_child(reroll_scroll)

	# Dice log section
	var log_label = Label.new()
	log_label.text = "Resolution Log:"
	log_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(log_label)

	dice_log_rich_text = RichTextLabel.new()
	dice_log_rich_text.set_custom_minimum_size(Vector2(DialogConstants.LARGE.x - 40, 120))
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
	# Staged sequential resolution pause signal (hit-roll / wound-roll pauses)
	if current_phase and current_phase.has_signal("shooting_stage_paused"):
		if not current_phase.shooting_stage_paused.is_connected(_on_stage_paused):
			current_phase.shooting_stage_paused.connect(_on_stage_paused)
			print("║ Connected to phase shooting_stage_paused signal")

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

	# SINGLE-WEAPON STEP-BY-STEP: with only one weapon type there is nothing to
	# order, so skip the ordering step entirely and go straight into staged
	# resolution — the attacker immediately sees the to-hit roll, can Command
	# Re-roll, then continues to the wound roll, then saves. Deferred so setup()
	# fully returns before the (synchronous) resolution chain runs.
	if weapon_order.size() == 1 and not NetworkManager.is_networked():
		call_deferred("_auto_start_single_weapon")

func _auto_start_single_weapon() -> void:
	"""Kick off staged step-by-step resolution for a single-weapon shot."""
	if is_resolving:
		return  # guard against a double-trigger
	_single_weapon_staged = true

	# Name the weapon + target(s) so the header reads naturally (ordering is hidden).
	var wid = weapon_order[0]
	var data = weapon_data.get(wid, {})
	var wname = data.get("name", wid)
	var assigns = data.get("assignments", [])
	var tname = _describe_assignment_targets(assigns) if not assigns.is_empty() else ""

	title = "Shooting — %s" % wname

	# Hide the (meaningless) ordering controls for a single weapon.
	fast_roll_button.visible = false
	start_sequence_button.visible = false

	# Start the staged sequence (rolls the hit roll and pauses).
	_on_start_sequence_pressed()

	# Restore a single-weapon-friendly instruction (start overwrote it).
	# A split (one weapon type, several targets) names every slice and says the
	# targets resolve one after another — before this it silently claimed the
	# whole weapon was "firing at <first target>".
	if assigns.size() > 1:
		instruction_label.text = "Split fire: %s at %s.\nEach target resolves in turn — Roll to Hit, then continue to the wound roll. You can Command Re-roll a die at each step." % [wname, tname]
	elif tname != "":
		instruction_label.text = "Firing %s at %s.\nRoll to Hit, then continue to the wound roll. You can Command Re-roll a die at each step." % [wname, tname]
	else:
		instruction_label.text = "Firing %s.\nRoll to Hit, then continue to the wound roll. You can Command Re-roll a die at each step." % wname

func _compare_weapon_damage(a: String, b: String) -> bool:
	"""Compare weapon damage for sorting (used by sort_custom)"""
	return weapon_data[a].total_damage > weapon_data[b].total_damage

func _target_display_name(target_unit_id: String) -> String:
	if current_phase and current_phase.has_method("get_unit"):
		var tunit = current_phase.get_unit(target_unit_id)
		if tunit and not tunit.is_empty():
			var meta = tunit.get("meta", {})
			return meta.get("display_name", meta.get("name", target_unit_id))
	return target_unit_id

# "Ork Boyz" for a single slice, "2× Ork Boyz | 1× Nobz" when the weapon is
# split across targets (model counts shown only when there is a split).
func _describe_assignment_targets(assignments: Array) -> String:
	var bits: Array = []
	for a in assignments:
		var tname = _target_display_name(a.get("target_unit_id", ""))
		if assignments.size() > 1:
			bits.append("%d× %s" % [(a.get("model_ids", []) as Array).size(), tname])
		else:
			bits.append(tname)
	return " | ".join(bits) if not bits.is_empty() else "?"

func _rebuild_weapon_list() -> void:
	"""Rebuild the weapon list UI from current weapon_order"""
	# Clear existing items
	for child in weapon_list_container.get_children():
		child.queue_free()

	weapon_items.clear()

	# With a single weapon there is nothing to reorder — render the row without
	# the position number and up/down arrows (it just shows what is firing).
	var single_weapon = weapon_order.size() == 1

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
		if not single_weapon:
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

		# WHO THIS WEAPON IS SHOOTING AT — the key fact when ordering a
		# multi-target volley. A split weapon lists every slice ("2× Ork Boyz | 1× Nobz").
		var target_label = Label.new()
		target_label.text = "→ " + _describe_assignment_targets(data.assignments)
		target_label.add_theme_font_size_override("font_size", 11)
		target_label.add_theme_color_override("font_color", Color(0.45, 0.95, 0.45))
		info_vbox.add_child(target_label)

		var stats_label = Label.new()
		stats_label.text = "Dmg: %d | Atks: %d | Total Potential: %d" % [
			data.damage,
			data.attacks,
			data.total_damage
		]
		stats_label.add_theme_font_size_override("font_size", 10)
		stats_label.modulate = Color(0.8, 0.8, 0.8)
		info_vbox.add_child(stats_label)

		# Up/Down buttons (only when there is actually an order to change)
		if not single_weapon:
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
	if _single_weapon_staged:
		# Single weapon: there is no order to choose, but the player should still
		# see WHAT is firing. Keep the one-row list visible under a "WEAPON"
		# header (an empty "FIRING ORDER" box here looked like a bug) and shrink
		# the scroll area to fit the single row.
		firing_order_label.text = "WEAPON"
		weapon_scroll.custom_minimum_size = Vector2(DialogConstants.LARGE.x - 40, 74)
	else:
		# Multi-weapon: the order is locked in — hide the ENTIRE ordering section
		# (header + scroll + list), not just the inner container, so no empty
		# "FIRING ORDER" box is left behind during resolution.
		firing_order_label.visible = false
		weapon_scroll.visible = false
		weapon_list_container.visible = false

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
		# Verbose weapon header — the phase now names the weapon + target.
		var message = dice_data.get("message", "")
		_add_to_dice_log("", Color.WHITE)
		_add_to_dice_log("[b]━━━ %s ━━━[/b]" % message, WhiteDwarfTheme.WH_GOLD)
	elif context == "resolution_start":
		var message = dice_data.get("message", "Beginning resolution...")
		_add_to_dice_log(message, Color.CYAN)
	elif context == "reroll_note":
		_add_to_dice_log("[b][color=orange]↻ %s[/color][/b]" % dice_data.get("message", "Re-roll"), Color.ORANGE)
	elif context == "auto_hit":
		# Torrent: automatic hits, no roll.
		var total = dice_data.get("total_attacks", dice_data.get("successes", 0))
		_add_to_dice_log("[b]Rolling to Hit:[/b] [color=cyan]Torrent — %d automatic hits[/color]" % total, Color.WHITE)
	elif context == "to_hit" or context == "to_wound":
		_add_to_dice_log(_format_roll_line(context, dice_data), Color.WHITE)
	else:
		# Fallback for any other dice block.
		var rolls_raw = dice_data.get("rolls_raw", [])
		var rolls_modified = dice_data.get("rolls_modified", [])
		var display_rolls = rolls_modified if not rolls_modified.is_empty() else rolls_raw
		var successes = dice_data.get("successes", -1)
		var line = "[b]%s[/b] (need %s): Rolls: %s" % [context.capitalize().replace("_", " "), dice_data.get("threshold", ""), _dice_str(display_rolls)]
		if successes >= 0:
			line += " → [b][color=green]%d successes[/color][/b]" % successes
		_add_to_dice_log(line, Color.WHITE)

func _format_roll_line(context: String, dice_data: Dictionary) -> String:
	# Verbose, human-readable hit / wound line.
	var threshold = str(dice_data.get("threshold", ""))
	var rolls_raw = dice_data.get("rolls_raw", [])
	var rolls_modified = dice_data.get("rolls_modified", [])
	var display_rolls = rolls_modified if not rolls_modified.is_empty() else rolls_raw
	var total = (display_rolls as Array).size()
	var successes = int(dice_data.get("successes", 0))
	var rerolls = dice_data.get("rerolls", [])
	if (rerolls as Array).is_empty() and context == "to_wound":
		# Wound re-rolls (Stand Vigil / twin-linked etc.) ride a separate key —
		# without this fallback the "(1→X)" annotation silently never renders.
		rerolls = dice_data.get("wound_rerolls", [])

	var label = "Rolling to Hit" if context == "to_hit" else "Rolling to Wound"
	var noun = "hit" if context == "to_hit" else "wound"
	var line = "[b]%s[/b] (need %s): %s" % [label, threshold, _dice_str(display_rolls)]
	if not (rerolls as Array).is_empty():
		line += "  [color=orange]("
		for rr in rerolls:
			line += "%d→%d " % [rr.get("original", 0), rr.get("rerolled_to", 0)]
		line = line.strip_edges() + ")[/color]"
	# "→ 4 hits, 1 miss" (or wounds)
	var fails = max(0, total - successes)
	var success_word = noun if successes == 1 else noun + "s"
	line += " → [b][color=green]%d %s[/color][/b]" % [successes, success_word]
	if context == "to_hit" and total > 0:
		var miss_word = "miss" if fails == 1 else "misses"
		line += "[color=gray], %d %s[/color]" % [fails, miss_word]
	# Crit / sustained annotations
	var crits = int(dice_data.get("critical_hits", dice_data.get("critical_wounds", 0)))
	if crits > 0:
		var crit_kind = "critical hit" if context == "to_hit" else "critical wound"
		line += "  [color=#c8a24a](%d %s%s)[/color]" % [crits, crit_kind, "" if crits == 1 else "s"]
	var sustained = int(dice_data.get("sustained_bonus_hits", 0))
	if context == "to_hit" and sustained > 0:
		line += "  [color=#c8a24a](+%d Sustained)[/color]" % sustained
	return line

func _dice_str(rolls: Array) -> String:
	# Render dice as spaced values, highlighting 6s (gold) and 1s (red).
	if rolls.is_empty():
		return "[color=gray]—[/color]"
	var parts = []
	for r in rolls:
		var v = int(r)
		if v == 6:
			parts.append("[color=#d4af37]6[/color]")
		elif v == 1:
			parts.append("[color=#a04040]1[/color]")
		else:
			parts.append(str(v))
	return "[ " + " ".join(parts) + " ]"

# --- Staged sequential resolution (hit pause / wound pause) -------------------

func _on_stage_paused(stage: String, info: Dictionary) -> void:
	current_stage = stage
	var reroll_available = bool(info.get("reroll_available", false))
	if stage == "hits":
		staged_continue_button.text = "Roll to Wound ▶"
		staged_continue_button.tooltip_text = "Proceed to the wound roll for this weapon"
	elif stage == "wounds":
		staged_continue_button.text = "Continue to Saving Throws ▶"
		staged_continue_button.tooltip_text = "Hand off to the defender to make saving throws"
	staged_continue_button.visible = true
	# Single-weapon step-by-step: offer a Fast Roll escape to resolve the rest at once.
	fast_finish_button.visible = _single_weapon_staged
	close_button.visible = false
	# Command Re-roll affordance
	if reroll_available:
		var rolls = info.get("modified_rolls", [])
		if (rolls as Array).is_empty():
			rolls = info.get("hit_rolls", info.get("wound_rolls", []))
		_populate_reroll_row(stage, rolls, info.get("threshold", ""))
	else:
		reroll_label.visible = false
		reroll_row.visible = false
		_clear_reroll_row()

func _populate_reroll_row(stage: String, rolls: Array, _threshold: String) -> void:
	_clear_reroll_row()
	if rolls.is_empty():
		reroll_label.visible = false
		reroll_row.visible = false
		return
	reroll_label.text = "Command Re-roll (1 CP) — click a %s die to re-roll it (once per phase):" % ("hit" if stage == "hits" else "wound")
	reroll_label.visible = true
	reroll_row.visible = true
	for i in range(rolls.size()):
		var die_btn = Button.new()
		die_btn.text = str(int(rolls[i]))
		die_btn.custom_minimum_size = Vector2(38, 38)
		die_btn.tooltip_text = "Re-roll this die with Command Re-roll (1 CP)"
		_WhiteDwarfTheme.apply_to_button(die_btn)
		die_btn.pressed.connect(_on_reroll_die_pressed.bind(i))
		reroll_row.add_child(die_btn)

func _clear_reroll_row() -> void:
	if not reroll_row:
		return
	for child in reroll_row.get_children():
		child.queue_free()

func _on_reroll_die_pressed(die_index: int) -> void:
	print("WeaponOrderDialog: re-roll %s die %d requested" % [current_stage, die_index])
	# Disable further clicks immediately (once per phase); the phase will confirm.
	reroll_label.visible = false
	reroll_row.visible = false
	_clear_reroll_row()
	emit_signal("staged_reroll_requested", current_stage, die_index)

func _on_staged_continue_pressed() -> void:
	staged_continue_button.visible = false
	fast_finish_button.visible = false
	reroll_label.visible = false
	reroll_row.visible = false
	_clear_reroll_row()
	if current_stage == "hits":
		emit_signal("staged_continue_requested", "wounds")
	elif current_stage == "wounds":
		# Hand off to the defender's saving throws — free the dialog so the
		# wound-allocation overlay underneath becomes interactive.
		emit_signal("staged_continue_requested", "saves")
		hide()
		queue_free()

func _on_fast_finish_pressed() -> void:
	# "Fast Roll": resolve the remaining step(s) of this shot without further
	# pauses, then free the dialog so the saving-throw overlay (or the completion
	# dialog, if no wounds) can take over.
	staged_continue_button.visible = false
	fast_finish_button.visible = false
	reroll_label.visible = false
	reroll_row.visible = false
	_clear_reroll_row()
	emit_signal("staged_fast_finish_requested")
	hide()
	queue_free()

func _add_to_dice_log(text: String, color: Color) -> void:
	"""Add colored text to dice log"""
	if not dice_log_rich_text:
		return

	var color_hex = color.to_html(false)
	dice_log_rich_text.append_text("[color=#%s]%s[/color]\n" % [color_hex, text])

	# The staged flow drives progression via the staged continue button (shown by
	# _on_stage_paused), so we no longer surface a bare "Close" mid-resolution.
	# Fallback: if we are resolving but no stage pause ever arrives (e.g. the
	# networked one-shot path), reveal Close so the player is never stuck.
	if is_resolving and current_stage == "" and not close_button.visible and not staged_continue_button.visible:
		close_button.visible = true


func _add_weapon_order_gold_separator(parent: Control) -> void:
	var sep = ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.color = Color(WhiteDwarfTheme.WH_GOLD.r, WhiteDwarfTheme.WH_GOLD.g, WhiteDwarfTheme.WH_GOLD.b, 0.4)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(sep)
