extends SceneTree

# Mid-move "take to the skies" toggle (SET_TAKE_TO_SKIES) — Deffkopta /
# dense-terrain fix.
#
# Bug: the drag flow auto-begins a NORMAL move the moment a unit is selected
# (BEGIN_NORMAL_MOVE with no payload), BEFORE the take-to-the-skies checkbox
# can be ticked. Ticking it afterwards did nothing: the 13.06 dense-terrain
# gate kept refusing the path ("Dense terrain blocks this model's path
# (13.06): [catwalk-58]") and the -2" cap was never applied, even though the
# UI showed the box checked.
#
# Covers the new SET_TAKE_TO_SKIES action end-to-end at the phase level:
#   ▪ default-begun move is grounded → wall crossing refused, message cites
#     "rule 13.06" and tells FLY units about the checkbox;
#   ▪ SET true mid-move: took_to_skies flips, cap re-derives (M-2, +roll on
#     Advance, -0 with HOVER), GameState flags follow, crossing now stages;
#   ▪ SET false is refused while staged moves exist (paths may rely on
#     flying), allowed on a clean move;
#   ▪ SET true is refused when a model already moved beyond the reduced cap;
#   ▪ non-FLY units and edition 10 are rejected.
#
# Usage: godot --headless --path . -s tests/test_take_to_skies_toggle.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, ("  --  " + detail) if detail != "" else ""])

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.2).timeout.connect(_run_tests)

const KOPTA_KW := ["DEFFKOPTAS", "FLY", "GRENADES", "ORKS", "SPEED FREEKS", "VEHICLE"]

func _seed_unit(gs, keywords: Array, base_mm: int, pos_px: Vector2, move: int, name: String) -> void:
	gs.state["units"] = {
		"U_TEST": {"id": "U_TEST", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": name, "keywords": keywords.duplicate(), "abilities": [],
				"stats": {"move": move, "toughness": 6, "save": 4, "wounds": 4, "objective_control": 1}},
			"models": [
				{"id": "m0", "alive": true, "wounds": 4, "current_wounds": 4,
				 "base_mm": base_mm, "base_type": "circular",
				 "position": {"x": pos_px.x, "y": pos_px.y}},
			]},
	}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = GameStateData.Phase.MOVEMENT
	# No CP: keeps BEGIN_ADVANCE from pausing on the Command Re-roll offer.
	for p in gs.state.get("players", {}):
		gs.state["players"][p]["cp"] = 0

func _begin(pm, action_type: String, payload: Dictionary = {}) -> Object:
	pm.transition_to_phase(GameStateData.Phase.MOVEMENT)
	var phase = pm.get_current_phase_instance()
	phase.execute_action({"type": action_type, "actor_unit_id": "U_TEST", "player": 1, "payload": payload})
	return phase

func _set_skies(phase, on: bool) -> Dictionary:
	return phase.execute_action({"type": "SET_TAKE_TO_SKIES", "actor_unit_id": "U_TEST",
		"player": 1, "payload": {"take_to_skies": on}})

func _stage(phase, dest: Vector2) -> Dictionary:
	return phase.execute_action({"type": "STAGE_MODEL_MOVE", "actor_unit_id": "U_TEST",
		"player": 1, "payload": {"model_id": "m0", "dest": [dest.x, dest.y]}})

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_take_to_skies_toggle (SET_TAKE_TO_SKIES mid-move) ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var tm = root.get_node_or_null("TerrainManager")
	var meas = root.get_node_or_null("Measurement")
	if gs == null or pm == null or tm == null or meas == null:
		_check("autoloads reachable", false)
		_finish(); return

	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition
	var prev_terrain = tm.terrain_features.duplicate(true)
	GameConstants.edition = 11
	tm.load_terrain_layout("take_and_hold_mirror_1")
	var ppi: float = meas.PX_PER_INCH

	# Geometry (board inches): the 5"-tall dense wall corner-ruin-balanced-left-46
	# (vertical stroke x 26.83..27.33, y 25.38..30.38). A 75mm Deffkopta-style
	# base starting east of it, crossing west to open ground inside the
	# enterable trapezoid area.
	var wall_id := "corner-ruin-balanced-left-46"
	var start := Vector2(29.5, 28.0) * ppi
	var across := Vector2(25.0, 28.0) * ppi   # 4.5" west, fully clear of the wall
	# Open lane (nothing within base reach): x=30.5, y 33 -> 44
	var lane_a := Vector2(30.5, 33.0) * ppi
	var lane_b := Vector2(30.5, 44.0) * ppi   # 11" — legal at M12, over the flying 10" cap

	print("-- T1: default-begun move is grounded — wall refusal + guidance --")
	_seed_unit(gs, KOPTA_KW, 75, start, 12, "Deffkoptas")
	var phase = _begin(pm, "BEGIN_NORMAL_MOVE")
	_check("auto-begun move has took_to_skies=false",
		phase.active_moves["U_TEST"].get("took_to_skies", true) == false)
	var r1 = _stage(phase, across)
	_check("grounded VEHICLE crossing the 5\" wall is refused", not r1.get("success", true), str(r1))
	_check("refusal names the wall", str(r1.get("errors", [])).contains(wall_id), str(r1))
	_check("refusal reads as a rules reference ('rule 13.06'), not inches",
		str(r1.get("errors", [])).contains("rule 13.06"), str(r1))
	_check("refusal tells FLY units about 'Take to the skies'",
		str(r1.get("errors", [])).contains("Take to the skies"), str(r1))

	print("\n-- T2: SET_TAKE_TO_SKIES true mid-move — cap -2\", crossing allowed --")
	var r2 = _set_skies(phase, true)
	_check("toggle accepted", r2.get("success", false), str(r2))
	_check("took_to_skies now true", phase.active_moves["U_TEST"].get("took_to_skies", false) == true)
	_check("move cap re-derived to 10\" (M12 - 2\")",
		abs(phase.active_moves["U_TEST"].get("move_cap_inches", 0.0) - 10.0) < 0.01,
		str(phase.active_moves["U_TEST"].get("move_cap_inches")))
	_check("GameState flags.move_cap_inches follows",
		abs(float(gs.get_unit("U_TEST").get("flags", {}).get("move_cap_inches", 0.0)) - 10.0) < 0.01)
	var r2b = _stage(phase, across)
	_check("same wall crossing now stages successfully", r2b.get("success", false), str(r2b))

	print("\n-- T3: SET false with staged moves is refused; clean move may land --")
	var r3 = _set_skies(phase, false)
	_check("un-tick with a staged move is refused", not r3.get("success", true), str(r3))
	_check("refusal says to reset first", str(r3.get("errors", [])).contains("Reset"), str(r3))
	# RESET_UNIT_MOVE erases the active move entirely; the UI then has the
	# player re-select the unit, which re-begins a fresh (grounded) move.
	phase.execute_action({"type": "RESET_UNIT_MOVE", "actor_unit_id": "U_TEST", "player": 1, "payload": {}})
	_check("reset erased the active move", not phase.active_moves.has("U_TEST"))
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_TEST", "player": 1, "payload": {}})
	var r3a = _set_skies(phase, true)
	_check("fresh move: tick accepted again", r3a.get("success", false), str(r3a))
	var r3b = _set_skies(phase, false)
	_check("un-tick on a clean move (nothing staged) is accepted", r3b.get("success", false), str(r3b))
	_check("cap restored to 12\"", abs(phase.active_moves["U_TEST"].get("move_cap_inches", 0.0) - 12.0) < 0.01,
		str(phase.active_moves["U_TEST"].get("move_cap_inches")))

	print("\n-- T4: SET true refused when a model already moved past the reduced cap --")
	_seed_unit(gs, KOPTA_KW, 75, lane_a, 12, "Deffkoptas")
	phase = _begin(pm, "BEGIN_NORMAL_MOVE")
	var r4a = _stage(phase, lane_b)
	_check("11\" open-ground stage is legal at M12", r4a.get("success", false), str(r4a))
	var r4b = _set_skies(phase, true)
	_check("tick refused — 11\" already moved > 10\" flying cap", not r4b.get("success", true), str(r4b))
	_check("refusal explains the cap and Reset Unit", str(r4b.get("errors", [])).contains("Reset Unit"), str(r4b))
	_check("took_to_skies unchanged after refusal",
		phase.active_moves["U_TEST"].get("took_to_skies", true) == false)

	print("\n-- T5: ADVANCE — cap tracks M-2+roll on, M+roll off --")
	_seed_unit(gs, KOPTA_KW, 75, lane_a, 12, "Deffkoptas")
	phase = _begin(pm, "BEGIN_ADVANCE")
	var roll: int = phase.active_moves["U_TEST"].get("advance_roll", 0)
	_check("advance produced a roll and an active move", roll >= 1 and roll <= 6, str(roll))
	var base_cap: float = phase.active_moves["U_TEST"].get("move_cap_inches", 0.0)
	_check("advance cap = 12 + roll", abs(base_cap - (12.0 + roll)) < 0.01, str(base_cap))
	var r5 = _set_skies(phase, true)
	_check("toggle accepted on an Advance", r5.get("success", false), str(r5))
	_check("advance cap re-derived to 10 + roll",
		abs(phase.active_moves["U_TEST"].get("move_cap_inches", 0.0) - (10.0 + roll)) < 0.01,
		str(phase.active_moves["U_TEST"].get("move_cap_inches")))
	var r5b = _set_skies(phase, false)
	_check("un-tick (no models moved) restores 12 + roll",
		r5b.get("success", false) and abs(phase.active_moves["U_TEST"].get("move_cap_inches", 0.0) - (12.0 + roll)) < 0.01,
		str(phase.active_moves["U_TEST"].get("move_cap_inches")))

	print("\n-- T6: HOVER — flying with no cap penalty --")
	_seed_unit(gs, ["ORKS", "VEHICLE", "FLY", "HOVER"], 75, start, 12, "Hover Kopta")
	phase = _begin(pm, "BEGIN_NORMAL_MOVE")
	var r6 = _set_skies(phase, true)
	_check("toggle accepted", r6.get("success", false), str(r6))
	_check("HOVER keeps the full 12\" cap",
		abs(phase.active_moves["U_TEST"].get("move_cap_inches", 0.0) - 12.0) < 0.01,
		str(phase.active_moves["U_TEST"].get("move_cap_inches")))
	var r6b = _stage(phase, across)
	_check("hovering unit crosses the wall", r6b.get("success", false), str(r6b))

	print("\n-- T7: guards — non-FLY refused, edition 10 inert --")
	_seed_unit(gs, ["ORKS", "VEHICLE"], 75, start, 12, "Trukk")
	phase = _begin(pm, "BEGIN_NORMAL_MOVE")
	var r7 = _set_skies(phase, true)
	_check("non-FLY unit cannot take to the skies", not r7.get("success", true), str(r7))
	GameConstants.edition = 10
	_seed_unit(gs, KOPTA_KW, 75, start, 12, "Deffkoptas")
	phase = _begin(pm, "BEGIN_NORMAL_MOVE")
	var r7b = _set_skies(phase, true)
	_check("edition 10: action refused (11e-only rule)", not r7b.get("success", true), str(r7b))
	GameConstants.edition = 11

	gs.state = prev_state
	GameConstants.edition = prev_edition
	tm.terrain_features = prev_terrain
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
