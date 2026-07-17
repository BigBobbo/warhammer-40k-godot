extends SceneTree

# Fight-selection dialog data: a Fights First unit must appear ONLY in the
# FIGHTS_FIRST list, never duplicated into the REMAINING_COMBATS list (12.04
# display). Regression for the reported bug: units with Fights First (charged
# units and ability carriers alike) were listed under BOTH sections of the
# "Select Unit to Fight" dialog, reading as if they fought twice.
#
# The sequencer's eligible_units(..., only_fights_first=false) intentionally
# returns ALL eligible units (rules semantics — a FF unit may still be picked
# in the remaining step); the phase's _remaining_units_11e() display helper is
# what must filter FF units out. This drives the REAL FightPhase pipeline
# (transition + END_PILE_IN) and asserts on the emitted dialog data.
#
# Usage: godot --headless --path . -s tests/test_fight_selection_no_dupe_ff_11e.gd

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
	create_timer(0.1).timeout.connect(_run_tests)

func _mk_unit(id: String, owner: int, x: float, y: float, flags: Dictionary = {}, abilities: Array = []) -> Dictionary:
	return {"id": id, "owner": owner, "status": 2, "flags": flags,
		"meta": {"name": id, "keywords": ["INFANTRY"], "abilities": abilities,
			"stats": {"move": 6, "toughness": 4, "save": 4, "wounds": 2}},
		"models": [
			{"id": id + "_m0", "alive": true, "wounds": 2, "current_wounds": 2,
				"base_mm": 25, "base_type": "circular", "position": {"x": x, "y": y}},
		]}

func _board(gs) -> void:
	# 40px = 1"; 25mm base radius ~19.7px — 60px apart is ~0.52" edge-to-edge,
	# well inside engagement range. Two engaged pairs:
	#   U_FF_CHARGER (P1, fights_first via charge flags)  <-> U_DEFENDER   (P2, normal)
	#   U_FF_ABILITY (P1, "Fights First" datasheet ability) <-> U_DEFENDER2 (P2, normal)
	gs.state["units"] = {
		"U_FF_CHARGER": _mk_unit("U_FF_CHARGER", 1, 500, 500,
			{"charged_this_turn": true, "fights_first": true}),
		"U_DEFENDER": _mk_unit("U_DEFENDER", 2, 560, 500),
		"U_FF_ABILITY": _mk_unit("U_FF_ABILITY", 1, 500, 900, {}, ["Fights First"]),
		"U_DEFENDER2": _mk_unit("U_DEFENDER2", 2, 560, 900),
	}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 10

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_fight_selection_no_dupe_ff_11e ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	if gs == null or pm == null:
		_check("autoloads", false); _finish(); return
	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition

	GameConstants.edition = 11
	_board(gs)
	pm.transition_to_phase(10)  # FIGHT
	var fp = pm.get_current_phase_instance()

	# Open the phase past the global Pile In step so the Fight step is running.
	fp.execute_action({"type": "END_PILE_IN", "player": 1})
	fp.execute_action({"type": "END_PILE_IN", "player": 2})
	_check("Fight step running", fp.pile_in_step_11e == fp.PileInStep11e.DONE)

	print("\n-- all four units are eligible to fight --")
	for uid in ["U_FF_CHARGER", "U_FF_ABILITY", "U_DEFENDER", "U_DEFENDER2"]:
		_check("%s eligible" % uid, fp.sequencer_11e.eligible_to_fight(uid, gs.state))

	print("\n-- dialog data partitions FF and remaining cleanly --")
	var data = fp._build_fight_selection_dialog_data_internal()
	var ff = data.get("fights_first_units", {})
	var rem = data.get("remaining_units", {})
	_check("FIGHTS_FIRST lists the charged unit", "U_FF_CHARGER" in ff.get("1", []), str(ff))
	_check("FIGHTS_FIRST lists the ability carrier", "U_FF_ABILITY" in ff.get("1", []), str(ff))
	_check("REMAINING does NOT repeat the charged FF unit (the reported bug)",
		"U_FF_CHARGER" not in rem.get("1", []), str(rem))
	_check("REMAINING does NOT repeat the ability FF unit",
		"U_FF_ABILITY" not in rem.get("1", []), str(rem))
	_check("REMAINING still lists P2's normal units",
		"U_DEFENDER" in rem.get("2", []) and "U_DEFENDER2" in rem.get("2", []), str(rem))
	_check("FIGHTS_FIRST does not list P2's normal units", ff.get("2", []).is_empty(), str(ff))
	var overlap := []
	for pk in ["1", "2"]:
		for uid in ff.get(pk, []):
			if uid in rem.get(pk, []):
				overlap.append(uid)
	_check("no unit appears in BOTH sections", overlap.is_empty(), str(overlap))

	print("\n-- after the FF units fight, they drop out of both lists --")
	fp.sequencer_11e.mark_fought("U_FF_CHARGER")
	fp.sequencer_11e.mark_fought("U_FF_ABILITY")
	data = fp._build_fight_selection_dialog_data_internal()
	ff = data.get("fights_first_units", {})
	rem = data.get("remaining_units", {})
	_check("fought FF units leave FIGHTS_FIRST", ff.get("1", []).is_empty(), str(ff))
	_check("fought FF units do not resurface in REMAINING",
		"U_FF_CHARGER" not in rem.get("1", []) and "U_FF_ABILITY" not in rem.get("1", []), str(rem))
	_check("P2's normal units remain offered",
		"U_DEFENDER" in rem.get("2", []) and "U_DEFENDER2" in rem.get("2", []), str(rem))

	# Restore
	GameConstants.edition = prev_edition
	gs.state = prev_state
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
