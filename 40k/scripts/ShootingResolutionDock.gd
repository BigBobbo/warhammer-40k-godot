class_name ShootingResolutionDock
extends VBoxContainer

## B2 (audit 2026-07): docked resolution panel for the shooting phase.
##
## Lives in the right HUD in place of the declaration widgets while a unit's
## shooting resolves. Replaces the single-player WeaponOrderDialog +
## NextWeaponDialog chain with ONE surface: a reorderable weapon queue, a
## single primary button that is always in the same place ("Roll to Hit ▶" →
## "Roll to Wound ▶" → "Continue to Saving Throws ▶" → "Next Weapon ▶" →
## "Complete Shooting"), Command Re-roll die chips at the staged pauses, and a
## Fast Roll escape. Dice detail streams to the DICE LOG right below the dock;
## the battlefield stays visible the whole time.
##
## The dock never talks to the phase directly — every step emits
## `action_requested` and the controller routes it through the normal
## shoot_action_requested pipeline (same actions the dialogs used).

signal action_requested(action: Dictionary)

const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")

# idle | queued | staged_hits | staged_wounds | awaiting_saves | between | complete_ready
var state: String = "idle"
var assignments: Array = []          # ordered (weapon,target) assignment dicts
var current_index: int = -1          # index of the assignment being resolved
var active_shooter_id: String = ""
var controller = null                # ShootingController (chip letters/colors)
var phase = null                     # ShootingPhase (stage-pause signal)

var header_label: Label
var queue_box: VBoxContainer
var status_label: Label
var reroll_label: Label
var reroll_row: HBoxContainer
var primary_button: Button
var fast_button: Button
var pause_policy_option: OptionButton

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)

	header_label = Label.new()
	header_label.name = "DockHeader"
	header_label.text = "WEAPON RESOLUTION"
	header_label.add_theme_font_size_override("font_size", 13)
	header_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	add_child(header_label)

	queue_box = VBoxContainer.new()
	queue_box.name = "DockQueue"
	queue_box.add_theme_constant_override("separation", 2)
	add_child(queue_box)

	status_label = Label.new()
	status_label.name = "DockStatus"
	status_label.text = ""
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	add_child(status_label)

	# Command Re-roll chips (one button per die at a staged pause)
	reroll_label = Label.new()
	reroll_label.name = "DockRerollLabel"
	reroll_label.add_theme_font_size_override("font_size", 11)
	reroll_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	reroll_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reroll_label.visible = false
	add_child(reroll_label)

	var reroll_scroll := ScrollContainer.new()
	reroll_scroll.name = "DockRerollScroll"
	reroll_scroll.custom_minimum_size = Vector2(230, 40)
	reroll_scroll.visible = false
	reroll_row = HBoxContainer.new()
	reroll_row.name = "DockRerollRow"
	reroll_scroll.add_child(reroll_row)
	add_child(reroll_scroll)

	# THE primary button — same position every step of every weapon.
	primary_button = Button.new()
	primary_button.name = "DockPrimaryButton"
	primary_button.custom_minimum_size = Vector2(230, 42)
	primary_button.pressed.connect(_on_primary_pressed)
	_WhiteDwarfTheme.apply_primary_button(primary_button)
	add_child(primary_button)

	fast_button = Button.new()
	fast_button.name = "DockFastButton"
	fast_button.custom_minimum_size = Vector2(230, 30)
	fast_button.pressed.connect(_on_fast_pressed)
	_WhiteDwarfTheme.apply_secondary_button(fast_button)
	add_child(fast_button)

	# B3 (audit 2026-07): pause policy — how often the staged sequence stops.
	var policy_row := HBoxContainer.new()
	policy_row.name = "DockPolicyRow"
	var policy_label := Label.new()
	policy_label.text = "Pauses:"
	policy_label.add_theme_font_size_override("font_size", 11)
	policy_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	policy_row.add_child(policy_label)
	pause_policy_option = OptionButton.new()
	pause_policy_option.name = "DockPausePolicy"
	pause_policy_option.add_item("Every step", 0)
	pause_policy_option.add_item("Only decisions", 1)
	pause_policy_option.add_item("Never", 2)
	pause_policy_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pause_policy_option.item_selected.connect(_on_policy_selected)
	policy_row.add_child(pause_policy_option)
	add_child(policy_row)
	_sync_policy_option()

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func activate(p_assignments: Array, p_phase, p_controller, shooter_id: String) -> void:
	assignments = p_assignments.duplicate(true)
	phase = p_phase
	controller = p_controller
	active_shooter_id = shooter_id
	current_index = -1
	state = "queued"
	visible = true

	# Stage pauses come straight from the phase (same signal the dialog used).
	if phase and phase.has_signal("shooting_stage_paused"):
		if not phase.shooting_stage_paused.is_connected(_on_stage_paused):
			phase.shooting_stage_paused.connect(_on_stage_paused)

	var shooter_name := shooter_id
	if phase and phase.has_method("get_unit"):
		var u = phase.get_unit(shooter_id)
		if u and not u.is_empty():
			var meta = u.get("meta", {})
			shooter_name = meta.get("display_name", meta.get("name", shooter_id))
	header_label.text = "WEAPON RESOLUTION — %s" % shooter_name

	_rebuild_queue()
	_set_state_queued()

func deactivate() -> void:
	state = "idle"
	visible = false
	assignments.clear()
	current_index = -1
	_clear_reroll_chips()
	if phase and phase.has_signal("shooting_stage_paused") and phase.shooting_stage_paused.is_connected(_on_stage_paused):
		phase.shooting_stage_paused.disconnect(_on_stage_paused)
	phase = null

func is_active() -> bool:
	return state != "idle"

# ---------------------------------------------------------------------------
# Queue rendering
# ---------------------------------------------------------------------------

func _assignment_label(a: Dictionary) -> String:
	var wid = a.get("weapon_id", "")
	var tid = a.get("target_unit_id", "")
	var wname = RulesEngine.get_weapon_profile(wid).get("name", wid)
	var tname = tid
	if phase and phase.has_method("get_unit"):
		var tu = phase.get_unit(tid)
		if tu and not tu.is_empty():
			var tmeta = tu.get("meta", {})
			tname = tmeta.get("display_name", tmeta.get("name", tid))
	var prefix := ""
	if controller and controller.has_method("_chip_prefix"):
		prefix = controller._chip_prefix(tid)
	var count = (a.get("model_ids", []) as Array).size()
	var count_str = "%d× " % count if count > 1 else ""
	return "%s%s → %s%s" % [count_str, wname, prefix, tname]

func _row_color(a: Dictionary) -> Color:
	if controller and controller.has_method("_chip_color"):
		return controller._chip_color(a.get("target_unit_id", ""))
	return Color(0.8, 0.8, 0.8)

# B5: expected-value forecast for one assignment slice (reuses the
# controller's P3-114 math with a bearer-count override).
func _forecast(a: Dictionary) -> Dictionary:
	if controller == null or not controller.has_method("_calc_weapon_expected_damage"):
		return {}
	var slice_count = (a.get("model_ids", []) as Array).size()
	if slice_count <= 0:
		return {}
	return controller._calc_weapon_expected_damage(a.get("weapon_id", ""), a.get("target_unit_id", ""), slice_count)

# B5: full staged chain in the tooltip — never show a preview that silently
# omits the save stage.
func _forecast_tooltip(fc: Dictionary) -> String:
	var tags: Array = fc.get("active_tags", [])
	var tag_line = ("\nModifiers: " + ", ".join(tags)) if not tags.is_empty() else ""
	return "Expected vs %s (T%d, best save %s):\n%.1f attacks → %.1f hits (%s) → %.1f wounds (%s) → %.1f unsaved → ~%.1f damage%s" % [
		str(fc.get("target_name", "?")),
		int(fc.get("toughness", 0)),
		str(fc.get("best_save", "?")),
		float(fc.get("total_attacks", 0.0)),
		float(fc.get("expected_hits", 0.0)),
		str(fc.get("hit_display", "?")),
		float(fc.get("expected_wounds", 0.0)),
		str(fc.get("wound_display", "?")),
		float(fc.get("expected_unsaved", 0.0)),
		float(fc.get("expected_damage", 0.0)),
		tag_line
	]

func _rebuild_queue() -> void:
	for child in queue_box.get_children():
		queue_box.remove_child(child)
		child.free()
	for i in range(assignments.size()):
		var a = assignments[i]
		var row := HBoxContainer.new()
		row.name = "QueueRow%d" % i

		var glyph := Label.new()
		glyph.name = "Glyph"
		glyph.custom_minimum_size = Vector2(20, 0)
		glyph.add_theme_font_size_override("font_size", 12)
		var note: String = str(a.get("_result_note", ""))
		if a.get("_done", false):
			glyph.text = "✔"
			glyph.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
		elif i == current_index:
			glyph.text = "▶"
			glyph.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
		else:
			glyph.text = "•"
			glyph.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		row.add_child(glyph)

		var text := Label.new()
		text.name = "RowText"
		var row_text := _assignment_label(a) + (("  " + note) if note != "" else "")
		# B5 (audit 2026-07): pending rows carry the expected damage for THIS
		# slice against THIS target (full modifier chain in the tooltip) — the
		# split-fire decision is informed, not bookkeeping. Done rows show
		# their real result note instead.
		if not a.get("_done", false):
			var fc := _forecast(a)
			if not fc.is_empty():
				row_text += "  ~%.1f dmg" % float(fc.get("expected_damage", 0.0))
				text.tooltip_text = _forecast_tooltip(fc)
				text.mouse_filter = Control.MOUSE_FILTER_STOP
		text.text = row_text
		text.add_theme_font_size_override("font_size", 12)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col := _row_color(a)
		if a.get("_done", false):
			col = col.darkened(0.35)
		text.add_theme_color_override("font_color", col)
		row.add_child(text)

		# Reorder arrows only make sense before the sequence starts.
		if state == "queued" and assignments.size() > 1:
			var up := Button.new()
			up.name = "Up%d" % i
			up.text = "▲"
			up.custom_minimum_size = Vector2(26, 22)
			up.disabled = (i == 0)
			up.pressed.connect(_on_move_row.bind(i, -1))
			row.add_child(up)
			var down := Button.new()
			down.name = "Down%d" % i
			down.text = "▼"
			down.custom_minimum_size = Vector2(26, 22)
			down.disabled = (i == assignments.size() - 1)
			down.pressed.connect(_on_move_row.bind(i, 1))
			row.add_child(down)

		queue_box.add_child(row)

func _on_move_row(index: int, delta: int) -> void:
	var j = index + delta
	if j < 0 or j >= assignments.size():
		return
	var tmp = assignments[index]
	assignments[index] = assignments[j]
	assignments[j] = tmp
	_rebuild_queue()

# ---------------------------------------------------------------------------
# State transitions (driven by the controller from phase signals)
# ---------------------------------------------------------------------------

func _set_state_queued() -> void:
	state = "queued"
	primary_button.disabled = false
	primary_button.text = "Roll to Hit ▶"
	fast_button.visible = true
	fast_button.text = "Fast Roll All ⏩"
	status_label.text = "Weapons fire in the order shown — reorder with ▲▼."
	_clear_reroll_chips()
	_rebuild_queue()

# B3: pause policy plumbing --------------------------------------------------

func _pause_policy() -> String:
	var ss = get_node_or_null("/root/SettingsService")
	if ss and "shooting_pause_policy" in ss:
		return str(ss.shooting_pause_policy)
	return "every_step"

func _sync_policy_option() -> void:
	if pause_policy_option == null:
		return
	match _pause_policy():
		"decisions":
			pause_policy_option.select(1)
		"never":
			pause_policy_option.select(2)
		_:
			pause_policy_option.select(0)

func _on_policy_selected(index: int) -> void:
	var policy = ["every_step", "decisions", "never"][clampi(index, 0, 2)]
	var ss = get_node_or_null("/root/SettingsService")
	if ss and ss.has_method("set_shooting_pause_policy"):
		ss.set_shooting_pause_policy(policy)

# Should this staged pause actually stop, per the policy? "decisions" pauses
# only when a Command Re-roll is genuinely usable (available AND at least one
# die failed — nothing to re-roll otherwise).
func _pause_should_stop(info: Dictionary) -> bool:
	match _pause_policy():
		"never":
			return false
		"decisions":
			if not info.get("reroll_available", false):
				return false
			var rolls: Array = info.get("hit_rolls", info.get("wound_rolls", []))
			var successes = int(info.get("hits", info.get("wounds", 0)))
			return successes < rolls.size()
		_:
			return true

func _auto_continue_stage(stage: String) -> void:
	if state == "idle":
		return
	if stage == "hits":
		emit_signal("action_requested", {"type": "CONTINUE_TO_WOUNDS"})
	else:
		emit_signal("action_requested", {"type": "CONTINUE_TO_SAVES"})

# -----------------------------------------------------------------------------

func _on_stage_paused(stage: String, info: Dictionary) -> void:
	if state == "idle":
		return
	current_index = int(info.get("current_index", current_index))
	_mark_done_below(current_index)
	# B3: skip pauses the policy doesn't want. Deferred — this signal fires
	# while the phase is still processing the action that produced the pause.
	if not _pause_should_stop(info):
		status_label.text = "Auto-continuing (%s)…" % ("no decision to make" if _pause_policy() == "decisions" else "pauses off")
		_rebuild_queue()
		call_deferred("_auto_continue_stage", stage)
		return
	if stage == "hits":
		state = "staged_hits"
		primary_button.text = "Roll to Wound ▶"
		status_label.text = "%s hit roll: %d hit(s)." % [str(info.get("weapon_name", "Weapon")), int(info.get("hits", 0))]
	else:
		state = "staged_wounds"
		primary_button.text = "Continue to Saving Throws ▶"
		status_label.text = "%d wound(s) caused — %s will make saves." % [int(info.get("wounds", 0)), str(info.get("target_name", "the target"))]
	primary_button.disabled = false
	fast_button.visible = true
	fast_button.text = "Fast Roll ⏩"
	_populate_reroll_chips(stage, info)
	_rebuild_queue()

func on_weapon_progress(dice_block: Dictionary) -> void:
	if state == "idle":
		return
	var idx = int(dice_block.get("current_index", -1))
	if idx >= 0:
		current_index = idx
		_mark_done_below(idx)
		_rebuild_queue()

func on_saves_pending(target_name: String) -> void:
	if state == "idle":
		return
	state = "awaiting_saves"
	primary_button.disabled = true
	primary_button.text = "Resolving saves…"
	fast_button.visible = false
	status_label.text = "%s is making saving throws (overlay on the board)." % target_name
	_clear_reroll_chips()

func on_next_weapon(remaining: Array, next_index: int, last_result: Dictionary) -> void:
	if state == "idle":
		return
	current_index = -1
	_mark_done_below(next_index)
	_stamp_result_note(next_index - 1, last_result)
	_clear_reroll_chips()
	primary_button.disabled = false
	fast_button.visible = false
	if remaining.is_empty():
		state = "complete_ready"
		primary_button.text = "Complete Shooting"
		var cas = int(last_result.get("casualties", 0))
		status_label.text = "All weapons resolved." + ((" Last weapon slew %d." % cas) if cas > 0 else "")
	else:
		state = "between"
		primary_button.text = "Next Weapon ▶"
		var nxt = remaining[0]
		status_label.text = "Next: %s" % _assignment_label(nxt)
	_rebuild_queue()

func _mark_done_below(idx: int) -> void:
	for i in range(assignments.size()):
		if i < idx:
			assignments[i]["_done"] = true

func _stamp_result_note(idx: int, last_result: Dictionary) -> void:
	if idx < 0 or idx >= assignments.size() or last_result.is_empty():
		return
	var hits = int(last_result.get("hits", 0))
	var wounds = int(last_result.get("wounds", 0))
	var cas = int(last_result.get("casualties", 0))
	var bits: Array = []
	bits.append("%dH" % hits)
	bits.append("%dW" % wounds)
	if cas > 0:
		bits.append("%d slain" % cas)
	assignments[idx]["_result_note"] = "(%s)" % " ".join(bits)
	assignments[idx]["_done"] = true

# ---------------------------------------------------------------------------
# Buttons
# ---------------------------------------------------------------------------

func _clean_order() -> Array:
	# Strip dock-internal keys before handing assignments back to the engine.
	var out: Array = []
	for a in assignments:
		var c = a.duplicate(true)
		c.erase("_done")
		c.erase("_result_note")
		out.append(c)
	return out

func _on_primary_pressed() -> void:
	match state:
		"queued":
			emit_signal("action_requested", {
				"type": "RESOLVE_WEAPON_SEQUENCE",
				"payload": {"weapon_order": _clean_order(), "fast_roll": false}
			})
		"staged_hits":
			emit_signal("action_requested", {"type": "CONTINUE_TO_WOUNDS"})
		"staged_wounds":
			emit_signal("action_requested", {"type": "CONTINUE_TO_SAVES"})
		"between":
			emit_signal("action_requested", {"type": "CONTINUE_SEQUENCE"})
		"complete_ready":
			emit_signal("action_requested", {
				"type": "COMPLETE_SHOOTING_FOR_UNIT",
				"actor_unit_id": active_shooter_id
			})

func _on_fast_pressed() -> void:
	match state:
		"queued":
			emit_signal("action_requested", {
				"type": "RESOLVE_WEAPON_SEQUENCE",
				"payload": {"weapon_order": _clean_order(), "fast_roll": true}
			})
		"staged_hits", "staged_wounds":
			emit_signal("action_requested", {"type": "FAST_FINISH_SHOOTING"})

# ---------------------------------------------------------------------------
# Command Re-roll chips
# ---------------------------------------------------------------------------

func _populate_reroll_chips(stage: String, info: Dictionary) -> void:
	_clear_reroll_chips()
	if not info.get("reroll_available", false):
		return
	var rolls: Array = info.get("hit_rolls", info.get("wound_rolls", []))
	if rolls.is_empty():
		return
	reroll_label.text = "Command Re-roll (1 CP) — click a %s die to re-roll it:" % ("hit" if stage == "hits" else "wound")
	reroll_label.visible = true
	reroll_row.get_parent().visible = true
	for i in range(rolls.size()):
		var die := Button.new()
		die.name = "DockDie%d" % i
		die.text = str(int(rolls[i]))
		die.custom_minimum_size = Vector2(30, 30)
		die.pressed.connect(_on_reroll_die.bind(stage, i))
		reroll_row.add_child(die)

func _on_reroll_die(stage: String, die_index: int) -> void:
	emit_signal("action_requested", {
		"type": "USE_SHOOTING_REROLL",
		"payload": {"stage": stage, "die_index": die_index}
	})
	# One Command Re-roll per phase — chips vanish; the pause stays until the
	# player continues (the phase re-emits an updated pause with new rolls).
	_clear_reroll_chips()

func _clear_reroll_chips() -> void:
	reroll_label.visible = false
	if reroll_row:
		reroll_row.get_parent().visible = false
		for child in reroll_row.get_children():
			reroll_row.remove_child(child)
			child.free()
