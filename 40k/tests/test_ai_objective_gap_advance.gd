extends SceneTree

# OBJ-GAP-1 / ADV-ODDS-1: objective distance + Advance odds in the AI's
# movement planner.
#
# 1. 11e terrain objective: the gap is base edge -> hosting AREA (a model is on
#    it once any part of its base touches the area), not centroid -> marker
#    centre less 3.79". A squad 6.9" from the ruin's edge reads as 6.9".
# 2. Advance odds: chance an Advance (M + D6) closes the gap this turn —
#    1.0 within M+1, 5/6 at M+2 ... 1/6 at M+6, 0 beyond; flat-6 units certain.
# 3. A guaranteed Advance (gap <= M+1) plans ADVANCE, counts as arriving this
#    turn (turns_to_reach 1, reachability bonus) — the old "dist <= M+2" test
#    on the centroid read this as 2 turns away.
# 4. A ranged unit with targets in range does NOT gamble its shooting on a
#    1-in-6 Advance; a unit with nothing to shoot takes any chance.
# 5. OBJ-ASSIGN-1: a unit that arrives this turn on a sure Advance takes the
#    objective from a higher-scoring unit that needs two Moves.
#
# Run via: godot --headless --path 40k --script tests/test_ai_objective_gap_advance.gd

const PPI := 40.0
const MOVE_ALL := ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]

var passed := 0
var failed := 0


func _initialize():
	await create_timer(0.2).timeout
	_run_tests()


func _unit(owner: int, name: String, positions: Array, oc: int, move: int = 6, base_mm: int = 32) -> Dictionary:
	var models = []
	for i in range(positions.size()):
		models.append({"id": "m%d" % (i + 1), "alive": true,
			"position": {"x": positions[i].x, "y": positions[i].y}, "base_mm": base_mm})
	return {"owner": owner, "models": models, "flags": {}, "status": 2,
		"meta": {"name": name, "points": 80, "keywords": ["INFANTRY"], "weapons": [],
			"stats": {"move": move, "objective_control": oc, "toughness": 4, "save": 5}}}


func _snapshot(units: Dictionary, objectives: Array) -> Dictionary:
	units["U_ENEMY"] = _unit(1, "Far Guard", [Vector2(1700.0, 2350.0)], 1)
	return {
		"meta": {"battle_round": 2, "player1_vp": 0, "player2_vp": 0},
		"battle_round": 2,
		"board": {"terrain_features": [], "objectives": objectives},
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


func _cand(uid: String, oid: String) -> Dictionary:
	for c in AIDecisionMaker._last_movement_candidates.get(uid, []):
		if c.objective_id == oid:
			return c
	return {}


func _check(name: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
		print("[PASS] %s — %s" % [name, detail])
	else:
		failed += 1
		print("[FAIL] %s — %s" % [name, detail])


func _run_tests():
	print("\n=== Objective gap + Advance odds ===\n")
	var gs = root.get_node("GameState")
	var tm = root.get_node("TerrainManager")
	var saved_objs = gs.state.get("board", {}).get("objectives", []).duplicate(true)
	var saved_edition = GameConstants.edition
	GameConstants.edition = 11

	# --- 1: terrain-hosted objective (legacy_fallback_mirror_1: obj_nml_1 IS
	# area-large-2, x 3"-10", y 13"-24.5"). Squad of 32mm bases, front model's
	# edge 6.9" right of the area's x=10" edge. ---
	tm.load_terrain_layout("legacy_fallback_mirror_1")
	var nml1_pos := Vector2(6.5 * PPI, 18.75 * PPI)
	gs.state["board"]["objectives"] = [{"id": "obj_nml_1", "position": nml1_pos,
		"radius_mm": 40, "zone": "no_mans_land", "source_pieces": ["area-large-2"]}]
	var r32 := 16.0 / 25.4 * PPI
	var front_x := 10.0 * PPI + 6.9 * PPI + r32
	var line := []
	for i in range(4):
		line.append(Vector2(front_x + i * 45.0, 900.0))
	var squad = _unit(2, "Squad", line, 1, 6)
	var gap_in = AIDecisionMaker._unit_gap_to_objective_px(squad, nml1_pos) / PPI
	var centroid_in = (front_x + 67.5 - nml1_pos.x) / PPI
	_check("terrain objective gap is edge -> area", absf(gap_in - 6.9) < 0.05,
		"gap %.2f\" (centroid -> marker %.1f\", legacy 'less 3.79\"' = %.1f\")" % [gap_in, centroid_in, centroid_in - 3.79])
	var touching = squad.duplicate(true)
	touching.models[0].position = {"x": 10.0 * PPI + r32 - 2.0, "y": 900.0}
	_check("base touching the area is ON the objective",
		AIDecisionMaker._unit_has_model_in_control_range(touching, nml1_pos)
			and AIDecisionMaker._unit_gap_to_objective_px(touching, nml1_pos) == 0.0,
		"model centre %.1f\" from the marker" % ((10.0 * PPI + r32 - 2.0 - nml1_pos.x) / PPI))

	# OBJ-PATH-1: the squad stands level with the area (y 900 inside its 520-980
	# span), so the shortest way on is straight left (-x) — not diagonally at
	# the marker dot (260, 750).
	var approach = AIDecisionMaker._objective_approach_target(squad, nml1_pos)
	var cen = AIDecisionMaker._get_unit_centroid(squad)
	var head = (approach - cen).normalized()
	var to_marker = (nml1_pos - cen).normalized()
	_check("heads straight at the area's nearest edge", head.x < -0.999 and absf(head.y) < 0.01,
		"heading (%.3f, %.3f); marker-centre heading was (%.3f, %.3f)" % [head.x, head.y, to_marker.x, to_marker.y])

	# --- 2: Advance odds ---
	var u = _unit(2, "U", [Vector2.ZERO], 1, 8)
	var odds := [
		[7.5, 1.0], [8.9, 1.0], [9.5, 5.0 / 6.0], [11.0, 4.0 / 6.0], [12.0, 0.5], [14.0, 1.0 / 6.0], [14.5, 0.0]]
	var odds_ok := true
	var odds_txt := []
	for o in odds:
		var ch = AIDecisionMaker._advance_reach_chance(u, o[0], 8.0)
		odds_txt.append("%.1f\"=%.2f" % [o[0], ch])
		if absf(ch - o[1]) > 0.001:
			odds_ok = false
	_check("Advance odds at M8", odds_ok, ", ".join(odds_txt))
	var rush = _unit(2, "Rush", [Vector2.ZERO], 1, 8)
	rush.flags["effect_boardin_rush"] = true
	_check("flat-6 Advance is certain within M+6", AIDecisionMaker._advance_reach_chance(rush, 13.9, 8.0) == 1.0,
		"%.2f" % AIDecisionMaker._advance_reach_chance(rush, 13.9, 8.0))

	# Remaining checks use bare snapshot positions (open-ground markers).
	gs.state["board"]["objectives"] = []

	# --- 3: M8 unit, 8.9" gap (centroid 12.7" from the marker): plans ADVANCE,
	# arrives this turn. ---
	var obj_a := {"id": "obj_1", "position": {"x": 900.0, "y": 1200.0}, "zone": "no_mans_land"}
	var obj_b := {"id": "obj_2", "position": {"x": 300.0, "y": 2300.0}, "zone": "no_mans_land"}
	var adv_y := 1200.0 + 8.9 * PPI + AIDecisionMaker.OBJECTIVE_CONTROL_RANGE_PX
	var s3 = _snapshot({"U_ADV": _unit(2, "Sentinels", [Vector2(900.0, adv_y)], 2, 8)}, [obj_a, obj_b])
	var a3 = _assign(s3, ["U_ADV"])
	var c3 = _cand("U_ADV", "obj_1")
	_check("sure Advance is planned and counts as this turn",
		a3.get("U_ADV", {}).get("objective_id", "") == "obj_1" and a3.get("U_ADV", {}).get("action", "") == "advance"
			and int(c3.get("turns_to_reach", 0)) == 1 and float(c3.get("score_terms", {}).get("reachability", 0.0)) > 0.0,
		"-> %s %s, turns %s, gap %.1f\", chance %.2f, reason '%s'" % [
			a3.get("U_ADV", {}).get("action", ""), a3.get("U_ADV", {}).get("objective_id", ""),
			str(c3.get("turns_to_reach", "?")), float(c3.get("gap_inches", -1)), float(c3.get("adv_chance", -1)),
			a3.get("U_ADV", {}).get("reason", "")])

	# --- 4: risk. A shooter with an enemy in range keeps its shots over a 1/6
	# gamble; with nothing to shoot it takes the chance. ---
	var shooter = _unit(2, "Shooter", [Vector2(900.0, 1000.0)], 1, 6)
	var near_enemy = {"U_E": _unit(1, "E", [Vector2(900.0, 1400.0)], 1)}
	var eval_obj := {"zone": "no_mans_land", "state": "uncontrolled", "priority": 9.0}
	var keep_shots = AIDecisionMaker._should_unit_advance(shooter, 11.5, 6.0, true, 24.0,
		near_enemy, Vector2(900.0, 1000.0), 1, eval_obj, 1.0 / 6.0)
	var free_adv = AIDecisionMaker._should_unit_advance(shooter, 11.5, 6.0, true, 24.0,
		{}, Vector2(900.0, 1000.0), 1, eval_obj, 1.0 / 6.0)
	var likely_adv = AIDecisionMaker._should_unit_advance(shooter, 7.5, 6.0, true, 24.0,
		near_enemy, Vector2(900.0, 1000.0), 1, eval_obj, 5.0 / 6.0)
	_check("1-in-6 gamble does not cost a shooter its shots", keep_shots == false, "advance=%s" % keep_shots)
	_check("nothing to shoot: any chance is worth it", free_adv == true, "advance=%s" % free_adv)
	_check("likely roll to a high-priority objective: advance", likely_adv == true, "advance=%s" % likely_adv)

	# --- 5: the user's case. U_TELE (M10, 2 OC/model x 2 models) scores
	# higher but needs 2 Moves (12.5" gap); U_SENT (M8) is 8.9" away — a sure
	# Advance. Sentinels take obj_1. ---
	var tele_x := 900.0 + 12.5 * PPI + AIDecisionMaker.OBJECTIVE_CONTROL_RANGE_PX
	var s5 = _snapshot({
		"U_SENT": _unit(2, "Sentinels", [Vector2(900.0, adv_y)], 1, 8),
		"U_TELE": _unit(2, "Telemon", [Vector2(tele_x, 1200.0), Vector2(tele_x + 30.0, 1200.0)], 2, 10),
	}, [obj_a, obj_b])
	var a5 = _assign(s5, ["U_SENT", "U_TELE"])
	var ts = _cand("U_TELE", "obj_1")
	var ss = _cand("U_SENT", "obj_1")
	_check("sure Advance beats a two-Move unit to the objective",
		a5.get("U_SENT", {}).get("objective_id", "") == "obj_1" and a5.get("U_SENT", {}).get("action", "") == "advance",
		"SENT->%s %s (score %.1f), TELE->%s (obj_1 score %.1f) — '%s'" % [
			a5.get("U_SENT", {}).get("action", ""), a5.get("U_SENT", {}).get("objective_id", ""), float(ss.get("score", 0.0)),
			a5.get("U_TELE", {}).get("objective_id", ""), float(ts.get("score", 0.0)), a5.get("U_SENT", {}).get("reason", "")])
	var arr = AIDecisionMaker._capture_arrival(ss)
	_check("capture arrival: sure Advance = 1 expected phase", absf(float(arr.expected) - 1.0) < 0.001,
		str(arr))

	gs.state["board"]["objectives"] = saved_objs
	GameConstants.edition = saved_edition
	AIDecisionMaker.reset_caches()
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
