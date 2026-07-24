class_name ShootingResolutionDock
extends ResolutionDockBase

## B2 (audit 2026-07): docked resolution panel for the shooting phase.
##
## Lives in the right HUD in place of the declaration widgets while a unit's
## shooting resolves. Replaces the single-player WeaponOrderDialog +
## NextWeaponDialog chain with ONE surface: a reorderable weapon queue, a
## single primary button that is always in the same place ("Roll to Hit ▶" →
## "Roll to Wound ▶" → "Continue to Saving Throws ▶" → "Next Weapon ▶" →
## "Complete Shooting"), Command Re-roll die chips at the staged pauses, and a
## Fast Roll escape. Dice detail streams to the DICE LOG (the "Dice Log" tab of
## the left-hand game log panel); the battlefield stays visible the whole time.
##
## The staged hit/wound rhythm, reroll chips, pause policy and queue rendering
## live in ResolutionDockBase — shared with the fight phase's
## FightResolutionDock so ranged and melee resolution stay consistent.

# States: idle | queued | staged_hits | staged_wounds | awaiting_saves |
#         between | complete_ready
var active_shooter_id: String = ""

# ---------------------------------------------------------------------------
# Base hooks
# ---------------------------------------------------------------------------

func _pause_signal_name() -> String:
	return "shooting_stage_paused"

func _reroll_action_type() -> String:
	return "USE_SHOOTING_REROLL"

func _click_through_terminal_states() -> Array:
	return ["complete_ready"]

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func activate(p_assignments: Array, p_phase, p_controller, shooter_id: String) -> void:
	_activate_common(p_assignments, p_phase, p_controller)
	active_shooter_id = shooter_id
	state = "queued"

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
	active_shooter_id = ""
	super.deactivate()

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

# B5 (audit 2026-07): pending rows carry the expected damage for THIS slice
# against THIS target (full modifier chain in the tooltip) — the split-fire
# decision is informed, not bookkeeping. Done rows show their result note.
func _decorate_pending_row(text: Label, a: Dictionary) -> void:
	var fc := _forecast(a)
	if not fc.is_empty():
		text.text += "  ~%.1f dmg" % float(fc.get("expected_damage", 0.0))
		text.tooltip_text = _forecast_tooltip(fc)
		text.mouse_filter = Control.MOUSE_FILTER_STOP

# Reorder arrows only make sense before the sequence starts.
func _append_row_extras(row: HBoxContainer, i: int) -> void:
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

func _primary_pressed_other(current_state: String) -> void:
	match current_state:
		"queued":
			emit_signal("action_requested", {
				"type": "RESOLVE_WEAPON_SEQUENCE",
				"payload": {"weapon_order": _clean_order(), "fast_roll": false}
			})
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
