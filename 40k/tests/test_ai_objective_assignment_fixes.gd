extends SceneTree

# OBJ-HOLD-1/2, OBJ-ASSIGN-1, OBJ-EXPLAIN-1: objective-assignment regressions.
#
# 1. A spread squad with a model on the marker but its centroid > 3.79" away
#    is "on" the objective and HOLDS it (was: treated as off-objective, moved).
# 2. Two units on the same held objective: exactly ONE stays (was: both left).
# 3. A faster unit farther away in inches but closer IN MOVES keeps the objective.
# 4. A unit meaningfully closer in moves, scoring nearly as well, takes the
#    objective ahead of the unit the score-only greedy order would send.
# 6. A unit arriving in fewer Movement phases keeps the objective even when a
#    slower unit is nearer after one move (M12 at 24" beats M4 at 12").
# 5. The displaced unit's coordination_note names who took its top objective.
#
# Run via: godot --headless --path 40k --script tests/test_ai_objective_assignment_fixes.gd

const PPI := 40.0
const MOVE_ALL := ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]

var passed := 0
var failed := 0


func _initialize():
	await create_timer(0.2).timeout
	_run_tests()


func _unit(owner: int, name: String, positions: Array, oc: int, move: int = 6) -> Dictionary:
	var models = []
	for i in range(positions.size()):
		models.append({"id": "m%d" % (i + 1), "alive": true,
			"position": {"x": positions[i].x, "y": positions[i].y}, "base_mm": 32})
	return {"owner": owner, "models": models, "flags": {},
		"meta": {"name": name, "points": 80, "keywords": ["INFANTRY"], "weapons": [],
			"stats": {"move": move, "objective_control": oc, "toughness": 4, "save": 5}}}


func _snapshot(units: Dictionary) -> Dictionary:
	units["U_ENEMY"] = _unit(1, "Far Guard", [Vector2(1400.0, 2300.0)], 1)
	return {
		"meta": {"battle_round": 2, "player1_vp": 0, "player2_vp": 0},
		"battle_round": 2,
		"board": {"terrain_features": [], "objectives": [
			{"id": "obj_1", "position": {"x": 600.0, "y": 600.0}, "zone": "no_mans_land"},
			{"id": "obj_2", "position": {"x": 1600.0, "y": 600.0}, "zone": "no_mans_land"},
		]},
		"units": units,
	}


func _assign(snapshot: Dictionary, movable_ids: Array) -> Dictionary:
	AIDecisionMaker.reset_caches()
	AIDecisionMaker._current_player = 2
	var objectives = AIDecisionMaker._get_objectives(snapshot)
	var enemies = AIDecisionMaker._get_enemy_units(snapshot, 2)
	var friendly = AIDecisionMaker._get_units_for_player(snapshot, 2)
	var evals = AIDecisionMaker._evaluate_all_objectives(snapshot, objectives, 2, enemies, friendly, 2)
	var movable = {}
	for uid in movable_ids:
		movable[uid] = MOVE_ALL
	return AIDecisionMaker._assign_units_to_objectives(
		snapshot, movable, evals, objectives, enemies, friendly, 2, 2, [])


func _dump(uids: Array) -> void:
	for uid in uids:
		for c in AIDecisionMaker._last_movement_candidates.get(uid, []):
			print("    %s -> %s score=%.2f dist=%.1f\" M%d action=%s" % [uid, c.objective_id, c.score, c.distance / PPI, int(c.move_inches), c.action])


func _check(name: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
		print("[PASS] %s — %s" % [name, detail])
	else:
		failed += 1
		print("[FAIL] %s — %s" % [name, detail])


func _run_tests():
	print("\n=== Objective assignment fixes ===\n")

	# --- 1: spread squad, model 1 is 2.5" from obj_1, centroid 4.0" away ---
	var line := []
	for i in range(5):
		line.append(Vector2(700.0 + i * 30.0, 600.0))
	var s1 = _snapshot({"U_SPREAD": _unit(2, "Spread Squad", line, 2)})
	var a1 = _assign(s1, ["U_SPREAD"])
	var r1: Dictionary = a1.get("U_SPREAD", {})
	_check("spread squad holds", r1.get("action", "") == "hold" and r1.get("objective_id", "") == "obj_1",
		"centroid %.1f\" away, got %s %s (%s)" % [160.0 / PPI, r1.get("action", ""), r1.get("objective_id", ""), r1.get("reason", "")])

	# --- 2: two units on obj_1 (held, no more OC needed): exactly one stays ---
	var s2 = _snapshot({
		"U_A": _unit(2, "Squad A", [Vector2(600.0, 600.0)], 2),
		"U_B": _unit(2, "Squad B", [Vector2(640.0, 600.0)], 2),
	})
	var a2 = _assign(s2, ["U_A", "U_B"])
	var holders := 0
	for uid in ["U_A", "U_B"]:
		if a2.get(uid, {}).get("action", "") == "hold" and a2.get(uid, {}).get("objective_id", "") == "obj_1":
			holders += 1
	_check("one of two stays", holders == 1, "A=%s %s, B=%s %s" % [
		a2.get("U_A", {}).get("action", ""), a2.get("U_A", {}).get("objective_id", ""),
		a2.get("U_B", {}).get("action", ""), a2.get("U_B", {}).get("objective_id", "")])

	# --- 3: movement counts. U_FAR (M12, 11" away) outscores U_NEAR (M6, 6.5")
	# and, although 4.5" farther, arrives with 1" spare vs 0.5" short — it KEEPS
	# obj_1 (the old raw-distance rule handed it to U_NEAR). ---
	var s3 = _snapshot({
		"U_FAR": _unit(2, "Far Bikers", [Vector2(600.0, 600.0 + 11.0 * PPI)], 2, 12),
		"U_NEAR": _unit(2, "Near Squad", [Vector2(600.0 - 6.5 * PPI, 600.0)], 2, 6),
	})
	var a3 = _assign(s3, ["U_FAR", "U_NEAR"])
	_dump(["U_FAR", "U_NEAR"])
	_check("faster unit keeps obj_1 despite being farther in inches",
		a3.get("U_FAR", {}).get("objective_id", "") == "obj_1" and a3.get("U_NEAR", {}).get("objective_id", "") == "obj_2",
		"FAR->%s, NEAR->%s" % [a3.get("U_FAR", {}).get("objective_id", ""), a3.get("U_NEAR", {}).get("objective_id", "")])

	# --- 4/5: U_SLOW (M6, OC 2/model, 5.5") outscores U_QUICK (M10, OC 1, 5.0")
	# on OC efficiency. Only 0.5" closer in inches, but U_QUICK is 4.5" closer
	# in moves (-5" vs -0.5" left after a move), so it takes obj_1. ---
	var s4 = _snapshot({
		"U_SLOW": _unit(2, "Slow Squad", [Vector2(600.0, 600.0 + 5.5 * PPI)], 2, 6),
		"U_QUICK": _unit(2, "Quick Squad", [Vector2(600.0 - 5.0 * PPI, 600.0)], 1, 10),
	})
	var a4 = _assign(s4, ["U_SLOW", "U_QUICK"])
	_dump(["U_SLOW", "U_QUICK"])
	var q_obj = a4.get("U_QUICK", {}).get("objective_id", "")
	var sl_obj = a4.get("U_SLOW", {}).get("objective_id", "")
	_check("quicker unit takes obj_1", q_obj == "obj_1" and sl_obj == "obj_2",
		"QUICK->%s (%s), SLOW->%s" % [q_obj, a4.get("U_QUICK", {}).get("reason", ""), sl_obj])
	var note := str(a4.get("U_SLOW", {}).get("coordination_note", ""))
	_check("displaced unit's note names the taker", "obj_1" in note and "Quick Squad" in note, "note='%s'" % note)

	# --- 6: whole turns matter. U_FAST (M12, 24") vs U_PLOD (M4, 12"): after
	# one move U_PLOD is nearer (8" vs 12" short), but U_FAST arrives on its 2nd
	# move and U_PLOD needs a 3rd — U_FAST keeps obj_1. ---
	var s6 = _snapshot({
		"U_FAST": _unit(2, "Fast Bikers", [Vector2(600.0, 600.0 + 24.0 * PPI)], 2, 12),
		"U_PLOD": _unit(2, "Plodding Squad", [Vector2(600.0 - 12.0 * PPI, 600.0)], 2, 4),
	})
	var a6 = _assign(s6, ["U_FAST", "U_PLOD"])
	_dump(["U_FAST", "U_PLOD"])
	# TOO-LATE (9c32f2e): obj_2 is 37" from the M4 squad (5 turns), past the last
	# battle round, so U_PLOD is no longer sent there; it reinforces obj_1 instead (not as its capturer).
	# What this case tests is unchanged: U_FAST, not U_PLOD, takes the capture.
	var plod6: Dictionary = a6.get("U_PLOD", {})
	var plod_ok: bool = plod6.get("objective_id", "") == "obj_2" \
		or not ("capturing" in str(plod6.get("reason", "")))
	_check("unit arriving in fewer turns keeps obj_1",
		a6.get("U_FAST", {}).get("objective_id", "") == "obj_1" and plod_ok,
		"FAST->%s, PLOD->%s (%s)" % [a6.get("U_FAST", {}).get("objective_id", ""), plod6.get("objective_id", ""), plod6.get("reason", "")])
	var arr_fast = AIDecisionMaker._capture_arrival({"distance": 24.0 * PPI, "move_inches": 12.0})
	var arr_plod = AIDecisionMaker._capture_arrival({"distance": 12.0 * PPI, "move_inches": 4.0})
	_check("arrival turns: M12 at 24\" = 2, M4 at 12\" = 3", arr_fast.phases == 2 and arr_plod.phases == 3,
		"fast=%s plod=%s" % [str(arr_fast), str(arr_plod)])

	AIDecisionMaker.reset_caches()
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
