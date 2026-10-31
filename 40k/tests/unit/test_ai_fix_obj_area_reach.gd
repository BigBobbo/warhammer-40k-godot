extends SceneTree

# FIX_OBJ_AREA_REACH (11e rules audit OC-01, protocol V2-4): the movement
# planner measured every reach / contest gap from the unit's CENTROID to the
# objective MARKER less 3.79" (3" + the 20 mm marker radius), although every
# bench objective is a terrain area. 11e 14.01: "that terrain area is the
# objective ... measure to and from the closest part of it"; 14.02: "A model
# is within range of a terrain objective while it is within that terrain
# area"; 01.04.01: one model within is enough. The engine
# (MissionManager.model_gap_to_objective_range_px) measures base edge to the
# hosting area. A 5-model Custodian Guard squad whose front rank stood 5" from
# an area-large edge (centroid ~12" from the marker) read 2 turns away at M6
# and was missing from the opponent's one-move threat (COORD-5); a squad 13"
# from the area edge (two M6 + 2" moves) was missing from our own contest
# capacity, so an objective we could flip read enemy_strong.
#
# Fix: _obj_gap_px - the nearest alive model's gap to the objective's range
# (hosting area on a terrain objective, base edge to the marker less 3.79" on
# open ground), never the centroid - in the min-moves tables, COORD-5,
# RACE-1 / RACE-ARMY arrival moves, the contest capacity and the candidate
# gap / turns_to_reach (and _capture_arrival).
#
# Guards: a unit beside the area's LONG edge (the area reaches only 3.5" from
# the marker there, less than 3.79") keeps its turn count and stays out of the
# one-move threat; a unit already on the area is unchanged; a unit 9" from the
# area edge (beyond M + 2") is still no one-move threat.
# FIX_OBJ_AREA_REACH = 0 restores the centroid arithmetic exactly.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_fix_obj_area_reach.gd
# (runs once the scene tree is up: the fix reads MissionManager/TerrainManager)

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const GameStateData = preload("res://autoloads/GameState.gd")
# No BEGIN_ADVANCE: RACE-1's long-trip Advance stays out of turns_to_reach.
const WALK := ["BEGIN_NORMAL_MOVE", "REMAIN_STATIONARY"]
const PX := 40.0  # pixels per inch
const OBJ := Vector2(600, 1200)
const HALF := Vector2(140, 230)  # area-large: 7" (x) by 11.5" (y) around the marker
const R40 := 31.5  # 40 mm base radius, px
const ROUND := 2

var _pass_count: int = 0
var _fail_count: int = 0
var _ran := false
var AIDM = null

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func _run_tests():
	if _ran:
		return
	_ran = true
	await process_frame
	print("\n=== FIX_OBJ_AREA_REACH: reach and contest gaps to the hosting area, from the nearest model ===\n")
	var mm = root.get_node_or_null("MissionManager")
	var tm = root.get_node_or_null("TerrainManager")
	_assert(mm != null and tm != null, "MissionManager / TerrainManager autoloads present")
	if mm == null or tm == null:
		print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
		quit(1)
		return
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	var prev_terrain = tm.terrain_features.duplicate(true)
	tm.terrain_features = [{"id": "area_obj", "piece_class": "area", "type": "ruins",
		"height_category": "tall", "polygon": PackedVector2Array([
			OBJ + Vector2(-HALF.x, -HALF.y), OBJ + Vector2(HALF.x, -HALF.y),
			OBJ + Vector2(HALF.x, HALF.y), OBJ + Vector2(-HALF.x, HALF.y)])}]
	AIDM = load(AI_PATH)

	test_front_rank_five_inches_out_reaches_this_turn()
	test_front_rank_counts_in_opponent_one_move_threat()
	test_contest_capacity_reads_two_moves_to_the_area()
	test_param_zero_restores_centroid_arithmetic()
	test_guard_long_edge_unit_unchanged()
	test_guard_unit_on_area_unchanged()
	test_guard_nine_inches_out_is_no_one_move_threat()

	AIDM._config_overrides.erase("FIX_OBJ_AREA_REACH")
	tm.terrain_features = prev_terrain
	GameConstants.edition = prev_edition
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

# --- fixtures ---------------------------------------------------------------

func _snapshot() -> Dictionary:
	var objs = [{"id": "obj_area", "position": OBJ, "zone": "no_mans_land", "source_pieces": ["area_obj"]}]
	return {"battle_round": ROUND, "meta": {"battle_round": ROUND},
		"board": {"objectives": objs, "terrain_features": []}, "units": {}}

func _add_unit(snap: Dictionary, uid: String, owner: int, positions: Array, oc: int, move: int = 6) -> void:
	var models = []
	for i in range(positions.size()):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 40,
			"base_type": "circular", "base_dimensions": {}, "position": positions[i],
			"wounds": 3, "current_wounds": 3})
	snap.units[uid] = {"id": uid, "owner": owner, "status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"name": uid, "points": 150, "stats": {"move": move, "toughness": 6, "save": 2,
			"wounds": 3, "leadership": 6, "objective_control": oc},
			"keywords": ["INFANTRY"], "weapons": []},
		"models": models, "flags": {}}

## A 5-model squad south of the area: a front rank of 3 whose base edges are
## `front_gap_in` from the area's short edge, a back rank of 2 70 px behind
## (centroid 28 px behind the front rank).
func _squad_south(front_gap_in: float) -> Array:
	var fy := OBJ.y + HALF.y + front_gap_in * PX + R40
	return [Vector2(OBJ.x - 80, fy), Vector2(OBJ.x, fy), Vector2(OBJ.x + 80, fy),
		Vector2(OBJ.x - 40, fy + 70), Vector2(OBJ.x + 40, fy + 70)]

func _far_enemy(snap: Dictionary, owner: int) -> void:
	_add_unit(snap, "FAR_%d" % owner, owner, [Vector2(1600, 150 if owner == 2 else 2250)], 1)

func _reset() -> void:
	AIDM.reset_caches()
	AIDM.clear_all_plans()
	AIDM._primary_awareness_p1 = {}
	AIDM._secondary_awareness_p1 = {}
	AIDM._primary_awareness_p2 = {}
	AIDM._secondary_awareness_p2 = {}

func _evals(snap: Dictionary, player: int) -> Array:
	_reset()
	var friendly = AIDM._get_units_for_player(snap, player)
	var enemies = AIDM._get_enemy_units(snap, player)
	return AIDM._evaluate_all_objectives(snap, AIDM._get_objectives(snap), player, enemies, friendly, ROUND)

func _eval_of(evals: Array, oid: String) -> Dictionary:
	for ev in evals:
		if str(ev.get("id", "")) == oid:
			return ev
	return {}

## The planner candidate of `uid` (player 1, the only movable unit) for `oid`.
func _cand(snap: Dictionary, uid: String, oid: String) -> Dictionary:
	_reset()
	var friendly = AIDM._get_units_for_player(snap, 1)
	var enemies = AIDM._get_enemy_units(snap, 1)
	var objectives = AIDM._get_objectives(snap)
	var evals = AIDM._evaluate_all_objectives(snap, objectives, 1, enemies, friendly, ROUND)
	AIDM._assign_units_to_objectives(snap, {uid: WALK}, evals, objectives, enemies, friendly, 1, ROUND)
	for c in AIDM._last_movement_candidates.get(uid, []):
		if str(c.get("objective_id", "")) == oid:
			return c
	return {}

func _arrival_moves(ev: Dictionary, key: String, name: String) -> int:
	for arr in ev.get(key, []):
		if str(arr.get("name", arr.get("unit_id", ""))) == name or str(arr.get("unit_id", "")) == name:
			return int(arr.get("moves", -1))
	return -1

func _set_fix(v: float) -> void:
	AIDM._config_overrides["FIX_OBJ_AREA_REACH"] = v

## Board A: our 5 x OC2 Custodian Guard (P1) with its front rank 5" from the
## area's short edge, centroid 12.2" from the marker; a far P2 unit.
func _board_a() -> Dictionary:
	var snap = _snapshot()
	_add_unit(snap, "CG", 1, _squad_south(5.0), 2)
	_far_enemy(snap, 2)
	return snap

## Board C: the enemy (P2) holds the area with 4 x OC2 = 8, standing on its
## north half; our 5 x OC2 squad's front rank is 13" from the south edge
## (two M6 + 2" moves = 16"), its centroid 20.2" from the marker (> 19.8").
func _board_c() -> Dictionary:
	var snap = _snapshot()
	var hy := OBJ.y - 150
	_add_unit(snap, "HOLDERS", 2, [Vector2(OBJ.x - 90, hy), Vector2(OBJ.x - 30, hy),
		Vector2(OBJ.x + 30, hy), Vector2(OBJ.x + 90, hy)], 2)
	_add_unit(snap, "CG", 1, _squad_south(13.0), 2)
	return snap

# --- tests --------------------------------------------------------------------

func test_front_rank_five_inches_out_reaches_this_turn() -> void:
	print("\n--- (a) front rank 5\" from the area edge, centroid 12.2\" from the marker, M6 ---")
	_set_fix(1.0)
	var c = _cand(_board_a(), "CG", "obj_area")
	print("  CG -> obj_area: turns_to_reach=%s action=%s" % [str(c.get("turns_to_reach", "?")), str(c.get("action", "?"))])
	_assert(int(c.get("turns_to_reach", -1)) == 1,
		"fix on: the front rank is one Normal move (5\" <= 6\") from the area - turns_to_reach 1 (got %s)" % str(c.get("turns_to_reach", "?")))
	var terms: Dictionary = c.get("score_terms", {})
	_assert(float(terms.get("reachability", 0.0)) > 0.0,
		"fix on: it gets the reachable-this-turn bonus (reachability %s)" % str(terms.get("reachability", 0.0)))
	var f_moves := _arrival_moves(_eval_of(_evals(_board_a(), 1), "obj_area"), "friendly_arrivals", "CG")
	_assert(f_moves == 1, "fix on: RACE-ARMY counts the squad in range after 1 move (got %d)" % f_moves)

func test_front_rank_counts_in_opponent_one_move_threat() -> void:
	print("\n--- (a) the same squad from the opponent's seat (P2): COORD-5 one-move threat ---")
	_set_fix(1.0)
	var ev = _eval_of(_evals(_board_a(), 2), "obj_area")
	print("  P2 obj_area: projected_enemy_oc=%s names=%s" % [str(ev.get("projected_enemy_oc", "?")), str(ev.get("projected_names", []))])
	_assert(int(ev.get("projected_enemy_oc", -1)) == 10,
		"fix on: the squad (5 x OC2) is one move (5\" <= 8\") from the area - projected_enemy_oc 10 (got %s)" % str(ev.get("projected_enemy_oc", "?")))
	var e_moves := _arrival_moves(ev, "enemy_arrivals", "CG")
	_assert(e_moves == 1, "fix on: RACE-1 enemy arrival in 1 move (got %d)" % e_moves)

func test_contest_capacity_reads_two_moves_to_the_area() -> void:
	print("\n--- (a) enemy holds with OC 8; our OC 10 squad two moves from the area edge ---")
	_set_fix(1.0)
	var ev = _eval_of(_evals(_board_c(), 1), "obj_area")
	print("  P1 obj_area: state=%s enemy_oc=%s contest_oc=%s" % [str(ev.get("state", "?")), str(ev.get("enemy_oc", "?")), str(ev.get("contest_oc", "?"))])
	_assert(int(ev.get("enemy_oc", -1)) == 8, "the enemy's level of control on the area is 8 (%s)" % str(ev.get("enemy_oc", "?")))
	_assert(int(ev.get("contest_oc", -1)) == 10,
		"fix on: our squad can stand on the area within two moves - contest_oc 10 (got %s)" % str(ev.get("contest_oc", "?")))
	_assert(str(ev.get("state", "")) == "enemy_weak",
		"fix on: 10 > 8, the objective is flippable - enemy_weak (got %s)" % str(ev.get("state", "?")))

func test_param_zero_restores_centroid_arithmetic() -> void:
	print("\n--- (b) FIX_OBJ_AREA_REACH = 0: the centroid-to-marker arithmetic, today's values ---")
	_set_fix(0.0)
	var c = _cand(_board_a(), "CG", "obj_area")
	_assert(int(c.get("turns_to_reach", -1)) == 2,
		"off: centroid 12.2\" - 3.79\" = 8.4\" at M6 - turns_to_reach 2 (got %s)" % str(c.get("turns_to_reach", "?")))
	_assert(not (c.get("score_terms", {}) as Dictionary).has("reachability"),
		"off: no reachability term (got %s)" % str((c.get("score_terms", {}) as Dictionary).get("reachability", "none")))
	# MERGE (main OBJ-GAP-1): with the fix off the reach/contest tables use
	# main's unconditional _unit_gap_to_objective_px — the NEAREST model's
	# centre less 3.79" (this snapshot's area is not on the live board, so the
	# marker radius) — no longer the centroid. The front rank's centre model is
	# within one M6 + 2" move of the marker's range, so these tables now agree
	# with the fix; the candidate's walking gap (above: 2 turns vs 1 on the
	# area) still tells them apart.
	var f_moves := _arrival_moves(_eval_of(_evals(_board_a(), 1), "obj_area"), "friendly_arrivals", "CG")
	_assert(f_moves == 1, "off (main's nearest-model gap): RACE-ARMY arrival moves 1 (got %d)" % f_moves)
	var ev2 = _eval_of(_evals(_board_a(), 2), "obj_area")
	_assert(int(ev2.get("projected_enemy_oc", -1)) == 10,
		"off (main's nearest-model gap): the front rank is one move out - projected_enemy_oc 10 (got %s)" % str(ev2.get("projected_enemy_oc", "?")))
	_assert(_arrival_moves(ev2, "enemy_arrivals", "CG") == 1, "off (main's nearest-model gap): RACE-1 enemy arrival moves 1 (got %d)" % _arrival_moves(ev2, "enemy_arrivals", "CG"))
	var evc = _eval_of(_evals(_board_c(), 1), "obj_area")
	_assert(int(evc.get("contest_oc", -1)) == 10 and str(evc.get("state", "")) == "enemy_weak",
		"off (main's nearest-model gap): contest_oc 10, enemy_weak (got %s, %s)" % [str(evc.get("contest_oc", "?")), str(evc.get("state", "?"))])
	_set_fix(1.0)

func test_guard_long_edge_unit_unchanged() -> void:
	print("\n--- (c) guard: a single model 20\" east of the marker, beside the area's long edge ---")
	for v in [0.0, 1.0]:
		_set_fix(v)
		var snap = _snapshot()
		_add_unit(snap, "LONE", 1, [OBJ + Vector2(20.0 * PX, 0)], 2)
		_far_enemy(snap, 2)
		var c = _cand(snap, "LONE", "obj_area")
		var ev = _eval_of(_evals(snap, 2), "obj_area")
		print("  fix=%.0f: turns_to_reach=%s, P2 projected_enemy_oc=%s" % [v, str(c.get("turns_to_reach", "?")), str(ev.get("projected_enemy_oc", "?"))])
		_assert(int(c.get("turns_to_reach", -1)) == 3,
			"fix=%.0f: 16.2\" (marker) / 15.7\" (area edge) at M6 - turns_to_reach 3 either way (got %s)" % [v, str(c.get("turns_to_reach", "?"))])
		_assert(int(ev.get("projected_enemy_oc", -1)) == 0,
			"fix=%.0f: not a one-move threat either way (got %s)" % [v, str(ev.get("projected_enemy_oc", "?"))])
	_set_fix(1.0)

func test_guard_unit_on_area_unchanged() -> void:
	print("\n--- (c) guard: a squad standing on the area (centroid 4.9\" from the marker) ---")
	for v in [0.0, 1.0]:
		_set_fix(v)
		var snap = _snapshot()
		var y := OBJ.y + 196
		_add_unit(snap, "ON", 1, [Vector2(OBJ.x - 90, y), Vector2(OBJ.x - 30, y), Vector2(OBJ.x + 30, y),
			Vector2(OBJ.x + 90, y)], 2)
		_far_enemy(snap, 2)
		var c = _cand(snap, "ON", "obj_area")
		var ev = _eval_of(_evals(snap, 2), "obj_area")
		print("  fix=%.0f: already_on_obj=%s action=%s turns=%s; P2 enemy_oc=%s projected=%s" % [v, str(c.get("already_on_obj", "?")),
			str(c.get("action", "?")), str(c.get("turns_to_reach", "?")), str(ev.get("enemy_oc", "?")), str(ev.get("projected_enemy_oc", "?"))])
		_assert(bool(c.get("already_on_obj", false)) and str(c.get("action", "")) == "hold" and int(c.get("turns_to_reach", -1)) == 1,
			"fix=%.0f: on the area - hold, turns_to_reach 1" % v)
		_assert(int(ev.get("enemy_oc", -1)) == 8 and int(ev.get("projected_enemy_oc", -1)) == 0,
			"fix=%.0f: P2 counts it in enemy_oc (8), not again as a one-move threat (got %s / %s)" % [v,
				str(ev.get("enemy_oc", "?")), str(ev.get("projected_enemy_oc", "?"))])
	_set_fix(1.0)

func test_guard_nine_inches_out_is_no_one_move_threat() -> void:
	print("\n--- (c) guard: front rank 9\" from the area edge (beyond M6 + 2\") ---")
	for v in [0.0, 1.0]:
		_set_fix(v)
		var snap = _snapshot()
		_add_unit(snap, "CG", 1, _squad_south(9.0), 2)
		_far_enemy(snap, 2)
		var ev = _eval_of(_evals(snap, 2), "obj_area")
		print("  fix=%.0f: P2 projected_enemy_oc=%s, RACE-1 moves=%d" % [v, str(ev.get("projected_enemy_oc", "?")), _arrival_moves(ev, "enemy_arrivals", "CG")])
		_assert(int(ev.get("projected_enemy_oc", -1)) == 0,
			"fix=%.0f: 9\" > 8\" - not a one-move threat (got %s)" % [v, str(ev.get("projected_enemy_oc", "?"))])
		_assert(_arrival_moves(ev, "enemy_arrivals", "CG") == 2,
			"fix=%.0f: two moves either way (got %d)" % [v, _arrival_moves(ev, "enemy_arrivals", "CG")])
	_set_fix(1.0)
