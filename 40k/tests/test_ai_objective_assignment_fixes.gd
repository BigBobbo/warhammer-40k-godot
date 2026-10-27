extends SceneTree

# OBJ-HOLD-1/2, OBJ-ASSIGN-1, OBJ-EXPLAIN-1: objective-assignment regressions.
#
# 1. A spread squad with a model on the marker but its centroid > 3.79" away
#    is "on" the objective and HOLDS it (was: treated as off-objective, moved).
# 2. Two units on the same held objective: exactly ONE stays (was: both left).
# 3. A meaningfully closer unit scoring nearly as well takes the objective
#    ahead of the farther unit the score-only greedy order would send.
# 4. The displaced unit's coordination_note names who took its top objective.
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

	# --- 3/4: U_FAR (M12, 11" away, reachable) outscores U_NEAR (M6, 6.5")
	# for obj_1 by less than the margin; U_NEAR is 4.5" closer and takes it. ---
	var s3 = _snapshot({
		"U_FAR": _unit(2, "Far Bikers", [Vector2(600.0, 600.0 + 11.0 * PPI)], 2, 12),
		"U_NEAR": _unit(2, "Near Squad", [Vector2(600.0 - 6.5 * PPI, 600.0)], 2, 6),
	})
	var a3 = _assign(s3, ["U_FAR", "U_NEAR"])
	for uid in ["U_FAR", "U_NEAR"]:
		for c in AIDecisionMaker._last_movement_candidates.get(uid, []):
			print("    %s -> %s score=%.2f dist=%.1f\" action=%s" % [uid, c.objective_id, c.score, c.distance / PPI, c.action])
	var near_obj = a3.get("U_NEAR", {}).get("objective_id", "")
	var far_obj = a3.get("U_FAR", {}).get("objective_id", "")
	_check("closer unit takes obj_1", near_obj == "obj_1" and far_obj == "obj_2",
		"NEAR->%s (%s), FAR->%s" % [near_obj, a3.get("U_NEAR", {}).get("reason", ""), far_obj])
	var note := str(a3.get("U_FAR", {}).get("coordination_note", ""))
	_check("displaced unit's note names the taker", "obj_1" in note and "Near Squad" in note, "note='%s'" % note)

	AIDecisionMaker.reset_caches()
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
