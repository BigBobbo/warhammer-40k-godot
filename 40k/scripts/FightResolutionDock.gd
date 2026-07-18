class_name FightResolutionDock
extends ResolutionDockBase

## Docked resolution panel for the FIGHT phase — the melee twin of the
## shooting phase's ShootingResolutionDock (same base class, same rhythm).
##
## Replaces the single-player FightSequenceDialog bottom pop-up: the staged
## melee sequence (hit roll → wound roll → saves, weapon by weapon) now runs
## in the right HUD with the SAME surface shooting uses — a weapon queue with
## ▶ / ✔ progress and result notes, ONE primary button in a fixed spot
## ("Roll to Wound ▶" → "Continue to Saving Throws ▶" → … → "Done ✔"),
## per-die Command Re-roll chips, a Fast Roll escape and the shared pause
## policy. Dice detail streams to the COMBAT LOG below the dock, and the
## battlefield — where the melee actually is — stays visible the whole time.
##
## Differences from shooting, by design of the melee flow:
##  - the hit roll for the first weapon fires as soon as attacks are
##    confirmed ("Fight!"), so the dock activates into `rolling` and receives
##    the first staged pause immediately (no `queued` reorder state);
##  - weapons advance automatically after saves (no "Next Weapon ▶" step);
##  - the terminal `complete` pause shows the casualty summary; "Done ✔" just
##    dismisses the dock (the activation already ended engine-side).

# States: idle | rolling | staged_hits | staged_wounds | awaiting_saves | complete
var active_fighter_id: String = ""

# Per-assignment hit/wound tallies observed at the staged pauses — stamped
# onto queue rows as "(2H 1W)" result notes when the sequence moves on.
var _tallies: Dictionary = {}
# Names from the last pause that carried them — reroll re-pauses come with a
# minimal info dict, so remember context for status lines.
var _last_weapon_name: String = ""
var _last_target_name: String = ""

# ---------------------------------------------------------------------------
# Base hooks
# ---------------------------------------------------------------------------

func _pause_signal_name() -> String:
	return "fight_stage_paused"

func _reroll_action_type() -> String:
	return "USE_FIGHT_REROLL"

func _click_through_terminal_states() -> Array:
	return ["complete"]

# The melee pauses carry `modified_rolls` when hit modifiers applied — show
# the die the player would actually be re-rolling (same as the old dialog).
func _chip_rolls(_stage: String, info: Dictionary) -> Array:
	var rolls: Array = info.get("modified_rolls", [])
	if rolls.is_empty():
		rolls = info.get("hit_rolls", info.get("wound_rolls", []))
	return rolls

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func activate(p_assignments: Array, p_phase, p_controller, fighter_id: String) -> void:
	_activate_common(p_assignments, p_phase, p_controller)
	active_fighter_id = fighter_id
	_tallies = {}
	_last_weapon_name = ""
	_last_target_name = ""
	state = "rolling"

	# Name the defender(s) too — "who is being hit" must never be implicit
	# (same clarity rule as the shooting save overlay's attacker line).
	var fighter_name := _unit_display_name(fighter_id)
	var target_names := _distinct_target_names()
	if target_names.is_empty():
		header_label.text = "MELEE RESOLUTION — %s" % fighter_name
	else:
		header_label.text = "MELEE RESOLUTION — %s vs %s" % [fighter_name, ", ".join(target_names)]

	primary_button.disabled = true
	primary_button.text = "Rolling to hit…"
	fast_button.visible = false
	status_label.text = "Resolving melee attacks…"
	_clear_reroll_chips()
	_rebuild_queue()

func deactivate() -> void:
	active_fighter_id = ""
	_tallies = {}
	super.deactivate()

func _unit_display_name(unit_id: String) -> String:
	if phase and phase.has_method("get_unit"):
		var u = phase.get_unit(unit_id)
		if u and not u.is_empty():
			var meta = u.get("meta", {})
			return meta.get("display_name", meta.get("name", unit_id))
	return unit_id

func _distinct_target_names() -> Array:
	var names: Array = []
	var seen: Array = []
	for a in assignments:
		var tid = str(a.get("target", ""))
		if tid == "" or tid in seen:
			continue
		seen.append(tid)
		names.append(_unit_display_name(tid))
	return names

# ---------------------------------------------------------------------------
# Queue rendering
# ---------------------------------------------------------------------------

func _assignment_label(a: Dictionary) -> String:
	var wid = a.get("weapon", "")
	var wname = RulesEngine.get_weapon_profile(wid).get("name", wid)
	var tname = _unit_display_name(str(a.get("target", "")))
	var count = (a.get("models", []) as Array).size()
	var count_str = "%d× " % count if count > 1 else ""
	return "%s%s → %s" % [count_str, wname, tname]

# ---------------------------------------------------------------------------
# Staged pauses
# ---------------------------------------------------------------------------

# Remember per-weapon tallies (and name context) BEFORE the base renders the
# pause. Reroll re-pauses omit weapon/target names and current_index — enrich
# the info dict from the remembered context so status lines stay specific.
func _record_stage_tally(stage: String, info: Dictionary) -> void:
	if info.has("weapon_name"):
		_last_weapon_name = str(info.get("weapon_name"))
	elif _last_weapon_name != "":
		info["weapon_name"] = _last_weapon_name
	if info.has("target_name"):
		_last_target_name = str(info.get("target_name"))
	elif _last_target_name != "":
		info["target_name"] = _last_target_name

	if current_index >= 0:
		# A hits pause for a NEW weapon — stamp every earlier row's note first.
		if stage == "hits":
			for i in range(current_index):
				_stamp_result_note(i)
		var t: Dictionary = _tallies.get(current_index, {})
		if stage == "hits":
			t["hits"] = int(info.get("hits", t.get("hits", 0)))
		else:
			t["wounds"] = int(info.get("wounds", t.get("wounds", 0)))
		_tallies[current_index] = t

func _stamp_result_note(idx: int) -> void:
	if idx < 0 or idx >= assignments.size():
		return
	if assignments[idx].get("_result_note", "") != "":
		return
	var t: Dictionary = _tallies.get(idx, {})
	if t.is_empty():
		return
	assignments[idx]["_result_note"] = "(%dH %dW)" % [int(t.get("hits", 0)), int(t.get("wounds", 0))]
	assignments[idx]["_done"] = true

func _handle_complete(info: Dictionary) -> void:
	state = "complete"
	_fast_finishing = false
	for i in range(assignments.size()):
		_stamp_result_note(i)
		assignments[i]["_done"] = true
	current_index = -1
	_clear_reroll_chips()
	var casualties = int(info.get("casualties", 0))
	var cas_label = "model" if casualties == 1 else "models"
	status_label.text = "Melee attacks resolved — %d enemy %s destroyed." % [casualties, cas_label]
	primary_button.disabled = false
	primary_button.text = "Done ✔"
	fast_button.visible = false
	_rebuild_queue()

# ---------------------------------------------------------------------------
# Buttons
# ---------------------------------------------------------------------------

func _primary_pressed_other(current_state: String) -> void:
	if current_state == "complete":
		# The activation already ended engine-side — Done just dismisses the
		# summary (the next fighter pick lives in the selection panel above).
		deactivate()

func _on_fast_pressed() -> void:
	# Dock-side fast-finish: auto-continue this and every later staged pause.
	# The engine keeps pausing (same actions as manual play) — the dock just
	# answers immediately, so no separate engine fast-path is needed.
	if state in ["staged_hits", "staged_wounds"]:
		_fast_finishing = true
		var stage = "hits" if state == "staged_hits" else "wounds"
		primary_button.disabled = true
		primary_button.text = "Fast rolling…"
		fast_button.visible = false
		status_label.text = "Fast rolling…"
		_clear_reroll_chips()
		_auto_continue_stage(stage)
