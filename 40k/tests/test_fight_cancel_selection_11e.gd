extends SceneTree

# CANCEL_FIGHTER_SELECTION — backing out of a fight activation before any
# attacks are assigned (12.04).
#
# The reported soft-lock (tutorial T6 "Krumpin'", step 4): selecting a unit to
# fight retires the right-hand fighter-selection panel and opens the
# AttackAssignmentDialog. That dialog is an AcceptDialog, so Escape / the window
# ✕ / pad Ⓑ (PadBindingManager points ui_cancel at the pad's Back button) merely
# HID it — FightPhase.active_fighter_id stayed set, no picker was on screen, and
# END_FIGHT (forfeiting every unswung unit) was the only reachable action.
#
# The engine half of the fix is asserted here: FightSequencer.unselect_to_fight
# is the exact inverse of select_to_fight, and the phase's
# CANCEL_FIGHTER_SELECTION action un-picks the unit, re-offers it and refuses
# once anything has actually been committed. The player path (dialog button,
# Ⓑ, Escape, the picker coming back) is covered by the windowed scenario
# tests/scenarios/sp/tut_t6_wrong_fighter_backout.json.
#
# Usage: godot --headless --path . -s tests/test_fight_cancel_selection_11e.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _unit(id: String, owner: int, x: float, y: float, flags: Dictionary = {}) -> Dictionary:
	return {
		"id": id, "owner": owner, "flags": flags,
		"meta": {"name": id, "keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4, "wounds": 2}},
		"models": [{"id": "%s_m1" % id, "alive": true, "wounds": 2, "current_wounds": 2,
			"base_mm": 32, "base_type": "circular", "position": {"x": x, "y": y}}],
	}

## Two engaged Fights First units of player 1 (both charged — the tutorial's
## Boyz + Warboss shape) plus the enemy they are in combat with.
func _board() -> Dictionary:
	var b = {"units": {}, "meta": {}}
	b.units["BOYZ"] = _unit("BOYZ", 1, 400, 400, {"charged_this_turn": true, "fights_first": true})
	b.units["WARBOSS"] = _unit("WARBOSS", 1, 400, 440, {"charged_this_turn": true, "fights_first": true})
	b.units["GUARD"] = _unit("GUARD", 2, 430, 420)
	return b

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_fight_cancel_selection_11e ===\n")
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11

	print("-- FightSequencer.unselect_to_fight is the inverse of select_to_fight --")
	var b = _board()
	var seq := FightSequencer.new()
	seq.begin(b, 1)
	var before_picker: int = seq.picker
	_check("player 1 picks first", before_picker == 1, "picker=%d" % seq.picker)
	_check("both Fights First units are offered",
		seq.eligible_units(b, 1, true) == ["BOYZ", "WARBOSS"], str(seq.eligible_units(b, 1, true)))

	seq.select_to_fight("WARBOSS", b)
	_check("selecting the Warboss takes him off the offer",
		not seq.eligible_to_fight("WARBOSS", b))
	_check("selecting hands the pick to the other player", seq.picker == 2, "picker=%d" % seq.picker)

	seq.unselect_to_fight("WARBOSS", b)
	_check("un-selecting puts the Warboss back on the offer",
		seq.eligible_to_fight("WARBOSS", b))
	_check("un-selecting hands the pick back to his owner",
		seq.picker == before_picker, "picker=%d" % seq.picker)
	_check("both units are offered again, as before the pick",
		seq.eligible_units(b, 1, true) == ["BOYZ", "WARBOSS"], str(seq.eligible_units(b, 1, true)))
	_check("the peek agrees — player 1 chooses from both",
		seq.peek_selection(b).player == 1 and seq.peek_selection(b).candidates.size() == 2,
		str(seq.peek_selection(b)))

	# The un-picked unit really can be selected again, and the OTHER unit is
	# still available after it fights — a cancel must not cost a swing.
	seq.select_to_fight("BOYZ", b)
	_check("after the cancel a DIFFERENT unit can be selected instead",
		not seq.eligible_to_fight("BOYZ", b) and seq.eligible_to_fight("WARBOSS", b))

	var b2 = _board()
	var seq2 := FightSequencer.new()
	seq2.begin(b2, 1)
	seq2.unselect_to_fight("GUARD", b2)
	_check("un-selecting a unit that was never selected is a safe no-op",
		seq2.eligible_to_fight("BOYZ", b2) and seq2.eligible_to_fight("GUARD", b2))

	print("\n-- FightPhase.CANCEL_FIGHTER_SELECTION --")
	# Autoloads are only reachable through the tree here — naming them at parse
	# time forces an eager compile before they register.
	var game_state = root.get_node_or_null("GameState")
	if game_state == null:
		_check("GameState autoload reachable", false)
		print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
		quit(1)
		return
	game_state.state = {
		"meta": {"phase": GameStateData.Phase.FIGHT, "active_player": 1, "battle_round": 1, "turn": 1},
		"units": _board().units,
		"board": {"size": {"width": 44, "height": 60}},
		"players": {"1": {"cp": 3}, "2": {"cp": 3}},
	}
	var phase = load("res://phases/FightPhase.gd").new()
	root.add_child(phase)
	phase.enter_phase(game_state.state)

	# Drive the phase past its 12.02 global Pile In step to the Fight step,
	# then take the selection the sequencer is actually offering.
	phase.execute_action({"type": "END_PILE_IN", "player": 1})
	phase.execute_action({"type": "END_PILE_IN", "player": 2})

	var offer = phase.sequencer_11e.peek_selection(game_state.state)
	_check("the Fight step is offering a selection", not offer.get("done", true), str(offer))

	var cancel_before = phase.validate_action({"type": "CANCEL_FIGHTER_SELECTION", "unit_id": "WARBOSS"})
	_check("cancel is REFUSED with nothing activated", not cancel_before.valid, str(cancel_before))

	var sel = phase.execute_action({"type": "SELECT_FIGHTER", "unit_id": "WARBOSS", "player": 1})
	_check("SELECT_FIGHTER accepted", sel.get("success", false), str(sel.get("error", "")))
	_check("the phase has an activation open", str(phase.active_fighter_id) == "WARBOSS",
		"active='%s'" % str(phase.active_fighter_id))
	_check("the Boyz are NOT offered while the Warboss is activated",
		_action_types(phase.get_available_actions(), "SELECT_FIGHTER").is_empty())
	_check("but the way BACK is offered",
		_action_types(phase.get_available_actions(), "CANCEL_FIGHTER_SELECTION").size() == 1,
		str(phase.get_available_actions()))

	_check("cancelling the WRONG unit is refused",
		not phase.validate_action({"type": "CANCEL_FIGHTER_SELECTION", "unit_id": "BOYZ"}).valid)

	var got_signal := [false]
	phase.fighter_selection_cancelled.connect(func(uid): got_signal[0] = (uid == "WARBOSS"))
	var cancelled = phase.execute_action({"type": "CANCEL_FIGHTER_SELECTION", "unit_id": "WARBOSS", "player": 1})
	_check("CANCEL_FIGHTER_SELECTION accepted", cancelled.get("success", false), str(cancelled.get("error", "")))
	_check("it emits fighter_selection_cancelled for the unit", got_signal[0])
	_check("no activation is left open", str(phase.active_fighter_id) == "",
		"active='%s'" % str(phase.active_fighter_id))
	_check("nothing is staged", phase.pending_attacks.is_empty() and phase.confirmed_attacks.is_empty())
	_check("the unit has NOT been marked as having fought",
		"WARBOSS" not in phase.units_that_fought, str(phase.units_that_fought))

	# THE FIX: both units are selectable again, so the mis-pick cost nothing.
	var reoffered = _action_types(phase.get_available_actions(), "SELECT_FIGHTER")
	var reoffered_ids := []
	for a in reoffered:
		reoffered_ids.append(str(a.get("unit_id", "")))
	reoffered_ids.sort()
	_check("BOTH units are offered again after the cancel",
		reoffered_ids == ["BOYZ", "WARBOSS"], str(reoffered_ids))

	var resel = phase.execute_action({"type": "SELECT_FIGHTER", "unit_id": "BOYZ", "player": 1})
	_check("a different unit can now be activated", resel.get("success", false)
		and str(phase.active_fighter_id) == "BOYZ", "active='%s'" % str(phase.active_fighter_id))

	# Once attacks are staged the back-out closes: the resolution path owns the
	# activation from there (SKIP_UNIT / the dice dock), not a silent undo.
	phase.pending_attacks.append({"attacker": "BOYZ", "weapon": "choppa_melee", "target": "GUARD"})
	_check("cancel is REFUSED once attacks are assigned",
		not phase.validate_action({"type": "CANCEL_FIGHTER_SELECTION", "unit_id": "BOYZ"}).valid)
	_check("and it is no longer offered",
		_action_types(phase.get_available_actions(), "CANCEL_FIGHTER_SELECTION").is_empty())
	phase.pending_attacks.clear()
	phase.staged_fight_state = {"stage": "hits_pending"}
	_check("cancel is REFUSED once the dice are being resolved",
		not phase.validate_action({"type": "CANCEL_FIGHTER_SELECTION", "unit_id": "BOYZ"}).valid)
	phase.staged_fight_state = {}

	phase.queue_free()
	GameConstants.edition = prev_edition
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _action_types(actions: Array, want: String) -> Array:
	var out: Array = []
	for a in actions:
		if str(a.get("type", "")) == want:
			out.append(a)
	return out
