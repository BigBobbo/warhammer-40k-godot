class_name ResolutionDockBase
extends VBoxContainer

## Shared right-panel dock for STAGED attack resolution (hit roll → wound roll
## → saves → next weapon), used by both the Shooting phase
## (ShootingResolutionDock) and the Fight phase (FightResolutionDock) so the
## two phases present dice rolls with ONE consistent surface:
##
##  - lives in the right HUD, never covering the battlefield;
##  - a reorderable/annotated weapon queue with ▶ / ✔ progress glyphs;
##  - ONE primary button that is always in the same place ("Roll to Wound ▶" →
##    "Continue to Saving Throws ▶" → …), driven by the phase's staged pauses;
##  - Command Re-roll die chips (shared DiceFaceIcons faces) at the pauses;
##  - a Fast Roll escape and the shared "Pauses" policy dropdown;
##  - dice detail streams to the phase's right-panel DICE/COMBAT LOG below the
##    dock — the dock itself never embeds a duplicate log.
##
## The dock never talks to the phase directly — every step emits
## `action_requested` and the owning controller routes it through the normal
## phase action pipeline. Subclasses bind the phase-specific signal + actions.

signal action_requested(action: Dictionary)

const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")
# Shared d6 face textures so Command Re-roll chips show dice icons (pips), not
# raw numbers — consistent with the DICE LOG and every other dice surface.
const _DiceFaceIcons = preload("res://scripts/DiceFaceIcons.gd")

# Chip size shared by BOTH phases (was 34px shooting / 44px fight — split the
# difference so the dice read the same everywhere).
const CHIP_SIZE := Vector2(36, 36)

# Common states: idle | staged_hits | staged_wounds | awaiting_saves.
# Subclasses add their own (shooting: queued/between/complete_ready,
# fight: rolling/complete).
var state: String = "idle"
var assignments: Array = []          # ordered (weapon,target) assignment dicts
var current_index: int = -1          # index of the assignment being resolved
var controller = null                # owning phase controller
var phase = null                     # phase instance (stage-pause signal)

# Fast-finish: once true, every later staged pause auto-continues (dock-side
# equivalent of the engine's fast-roll paths). Cleared on (de)activation.
var _fast_finishing: bool = false

var header_label: Label
var queue_box: VBoxContainer
var status_label: Label
var reroll_label: Label
var reroll_row: HBoxContainer
var primary_button: Button
var fast_button: Button
var pause_policy_option: OptionButton

# ---------------------------------------------------------------------------
# Subclass hooks
# ---------------------------------------------------------------------------

## Name of the phase signal that emits (stage: String, info: Dictionary).
func _pause_signal_name() -> String:
	return ""

## Action type for a per-die Command Re-roll at a staged pause.
func _reroll_action_type() -> String:
	return ""

## Which rolls the Command Re-roll chips show at this pause.
func _chip_rolls(_stage: String, info: Dictionary) -> Array:
	return info.get("hit_rolls", info.get("wound_rolls", []))

## Primary button pressed in a state the base doesn't own.
func _primary_pressed_other(_state: String) -> void:
	pass

## Fast button pressed — subclass decides what "fast" means for its phase.
func _on_fast_pressed() -> void:
	pass

## The "complete" staged pause (phases that emit one).
func _handle_complete(_info: Dictionary) -> void:
	pass

## Per-pause bookkeeping before the pause is (maybe) skipped — e.g. remember
## hit/wound tallies for queue result notes.
func _record_stage_tally(_stage: String, _info: Dictionary) -> void:
	pass

## Row text for one assignment.
func _assignment_label(_a: Dictionary) -> String:
	return ""

## Row color for one assignment.
func _row_color(_a: Dictionary) -> Color:
	return Color(0.8, 0.8, 0.8)

## Decorate a pending (not-done) row's text label (forecasts, tooltips, …).
func _decorate_pending_row(_text: Label, _a: Dictionary) -> void:
	pass

## Extra per-row widgets (e.g. shooting's ▲▼ reorder arrows in queued state).
func _append_row_extras(_row: HBoxContainer, _index: int) -> void:
	pass

## States debug_click_through must stop AT (summary shown) instead of pressing
## the primary button again.
func _click_through_terminal_states() -> Array:
	return []

# ---------------------------------------------------------------------------
# UI skeleton
# ---------------------------------------------------------------------------

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)

	header_label = Label.new()
	header_label.name = "DockHeader"
	header_label.text = "RESOLUTION"
	header_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	reroll_scroll.custom_minimum_size = Vector2(230, CHIP_SIZE.y + 6)
	reroll_scroll.visible = false
	reroll_row = HBoxContainer.new()
	reroll_row.name = "DockRerollRow"
	reroll_scroll.add_child(reroll_row)
	add_child(reroll_scroll)

	# THE primary button — same position every step of every weapon, in every
	# phase that stages its rolls.
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

	# Pause policy — how often the staged sequence stops. One shared setting
	# governs shooting AND fight so the rhythm is consistent across phases.
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

## Store the shared fields and connect the phase's stage-pause signal.
func _activate_common(p_assignments: Array, p_phase, p_controller) -> void:
	assignments = p_assignments.duplicate(true)
	phase = p_phase
	controller = p_controller
	current_index = -1
	_fast_finishing = false
	visible = true
	# The policy is shared across phases — the other dock may have changed it.
	_sync_policy_option()
	var sig := _pause_signal_name()
	if phase and sig != "" and phase.has_signal(sig):
		if not phase.is_connected(sig, _on_stage_paused):
			phase.connect(sig, _on_stage_paused)

func deactivate() -> void:
	state = "idle"
	visible = false
	assignments.clear()
	current_index = -1
	_fast_finishing = false
	_clear_reroll_chips()
	var sig := _pause_signal_name()
	if phase and sig != "" and phase.has_signal(sig) and phase.is_connected(sig, _on_stage_paused):
		phase.disconnect(sig, _on_stage_paused)
	phase = null

func is_active() -> bool:
	return state != "idle"

# ---------------------------------------------------------------------------
# Queue rendering
# ---------------------------------------------------------------------------

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
		text.text = _assignment_label(a) + (("  " + note) if note != "" else "")
		text.add_theme_font_size_override("font_size", 12)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col := _row_color(a)
		if a.get("_done", false):
			col = col.darkened(0.35)
		text.add_theme_color_override("font_color", col)
		if not a.get("_done", false):
			_decorate_pending_row(text, a)
		row.add_child(text)

		_append_row_extras(row, i)
		queue_box.add_child(row)

func _mark_done_below(idx: int) -> void:
	for i in range(assignments.size()):
		if i < idx:
			assignments[i]["_done"] = true

# ---------------------------------------------------------------------------
# Pause policy (shared setting: SettingsService.shooting_pause_policy governs
# every staged resolution dock, not just shooting)
# ---------------------------------------------------------------------------

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
# die failed — nothing to re-roll otherwise). A live fast-finish skips all.
func _pause_should_stop(info: Dictionary) -> bool:
	if _fast_finishing:
		return false
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

# ---------------------------------------------------------------------------
# Staged pauses — the shared hit/wound rhythm both phases follow
# ---------------------------------------------------------------------------

func _on_stage_paused(stage: String, info: Dictionary) -> void:
	if state == "idle":
		return
	if stage == "complete":
		_handle_complete(info)
		return
	current_index = int(info.get("current_index", current_index))
	_mark_done_below(current_index)
	_record_stage_tally(stage, info)
	# Skip pauses the policy doesn't want. Deferred — this signal fires while
	# the phase is still processing the action that produced the pause.
	if not _pause_should_stop(info):
		if _fast_finishing:
			status_label.text = "Fast rolling…"
		else:
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

func on_saves_pending(target_name: String) -> void:
	if state == "idle":
		return
	state = "awaiting_saves"
	primary_button.disabled = true
	primary_button.text = "Resolving saves…"
	fast_button.visible = false
	status_label.text = "%s is making saving throws (overlay on the board)." % target_name
	_clear_reroll_chips()

func on_weapon_progress(dice_block: Dictionary) -> void:
	if state == "idle":
		return
	var idx = int(dice_block.get("current_index", -1))
	if idx >= 0:
		current_index = idx
		_mark_done_below(idx)
		_rebuild_queue()

# ---------------------------------------------------------------------------
# Buttons
# ---------------------------------------------------------------------------

func _on_primary_pressed() -> void:
	match state:
		"staged_hits":
			emit_signal("action_requested", {"type": "CONTINUE_TO_WOUNDS"})
		"staged_wounds":
			emit_signal("action_requested", {"type": "CONTINUE_TO_SAVES"})
		_:
			_primary_pressed_other(state)

# ---------------------------------------------------------------------------
# Command Re-roll chips
# ---------------------------------------------------------------------------

func _populate_reroll_chips(stage: String, info: Dictionary) -> void:
	_clear_reroll_chips()
	if not info.get("reroll_available", false):
		return
	var rolls: Array = _chip_rolls(stage, info)
	if rolls.is_empty():
		return
	reroll_label.text = "Command Re-roll (1 CP) — click a %s die to re-roll it:" % ("hit" if stage == "hits" else "wound")
	reroll_label.visible = true
	reroll_row.get_parent().visible = true
	# Colour by threshold when the pause carries one (pass green / fail red);
	# otherwise fall back to value-based (crit gold, 1 red, else neutral).
	var thr_str := str(info.get("threshold", "")).strip_edges().replace("+", "")
	var threshold_num := thr_str.to_int() if thr_str.is_valid_int() else 0
	for i in range(rolls.size()):
		var v := int(rolls[i])
		var die := Button.new()
		die.name = "DockDie%d" % i
		# d6 face icon (pips) instead of a number — same textures as the DICE LOG.
		var bg := _DiceFaceIcons.color_for(v, threshold_num, threshold_num > 0, 6)
		die.icon = _DiceFaceIcons.get_face(v, bg)
		die.expand_icon = true
		die.custom_minimum_size = CHIP_SIZE
		die.tooltip_text = "Re-roll this %d with Command Re-roll (1 CP)" % v
		die.pressed.connect(_on_reroll_die.bind(stage, i))
		reroll_row.add_child(die)

func _on_reroll_die(stage: String, die_index: int) -> void:
	emit_signal("action_requested", {
		"type": _reroll_action_type(),
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

# ---------------------------------------------------------------------------
# Windowed-scenario helper
# ---------------------------------------------------------------------------

## ScenarioRunner's execute_script is Expression-only (no loops/statements), so
## the "click continue until the sequence completes" loop lives here. Presses
## the primary button through the staged pauses and stops at a terminal state
## (summary shown) without pressing its final button. Returns a status string.
func debug_click_through(max_clicks: int = 12) -> String:
	var clicks = 0
	var terminals := _click_through_terminal_states()
	while clicks < max_clicks and state != "idle" and not (state in terminals):
		if primary_button.visible and not primary_button.disabled:
			_on_primary_pressed()
		else:
			break
		clicks += 1
	if state in terminals:
		return "complete after %d step(s)" % clicks
	return "not complete after %d step(s) (state=%s)" % [clicks, state]
