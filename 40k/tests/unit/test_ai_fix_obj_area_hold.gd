extends SceneTree

# FIX_OBJ_AREA_HOLD (11e rules audit OC-04, protocol V2-4): the hold /
# charge-off / fall-back / chase gates read "on objective" as the unit
# CENTROID within 3.79" of the MARKER and summed OC without the hosting area
# (model CENTRES within 3.79" of the marker); _decide_engaged_unit summed OC
# around the unit's own centroid, not the objective. 11e 14.02: the level of
# control adds the OC of every model within range of the objective, and a
# model is within range of a terrain objective while it is within that
# terrain area (MissionManager: any base overlap). Bench check: at fixture
# start U_CUSTODIAN_GUARD_F has all 5 models on area-large-14 (engine OC 10)
# but CH-LEAVE counted OC 2 (the one model whose centre is 3.78" from the
# marker), and the chase gate read it as off the objective (centroid 4.95").
#
# Fix: CH-LEAVE (_charge_leaves_held_objective) and _pick_fall_back_target sum
# OC with MissionManager's range test (FIX-HELD-DUP's board entry + mm) and
# CH-LEAVE tests the target with OC-03's _unit_on_objective;
# _decide_engaged_unit finds the objective the unit really stands on and sums
# friendly / enemy / own OC AT that objective; _melee_chase_gate and the
# support pass (_find_best_remaining_objective) use _unit_on_objective.
#
# Guards: a charger off every objective / a target on the same objective
# leave CH-LEAVE as it was; a unit off the area, or on it with no enemy on
# the objective, chases the same; an engaged unit off every objective falls
# back the same, and one standing round the marker reads the same OC; an
# objective nobody holds stays the fall-back target; a unit off the area
# keeps "move" in the support pass. FIX_OBJ_AREA_HOLD = 0 restores the old
# reads.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_fix_obj_area_hold.gd
# (runs once the scene tree is up: the fix reads MissionManager/TerrainManager)

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const GameStateData = preload("res://autoloads/GameState.gd")
const PX := 40.0  # pixels per inch
const OBJ := Vector2(600, 1200)
const HALF := Vector2(140, 230)  # area-large: 7" (x) by 11.5" (y) around the marker
const R40 := 31.5  # 40 mm base radius, px
const SPEAR := {"name": "Guardian spear", "type": "Melee", "range": "Melee", "attacks": "5", "weapon_skill": "2",
	"strength": "7", "ap": "-2", "damage": "2", "special_rules": ""}
const SHANK := {"name": "Shank", "type": "Melee", "range": "Melee", "attacks": "1", "weapon_skill": "5",
	"strength": "2", "ap": "0", "damage": "1", "special_rules": ""}
# U_CUSTODIAN_GUARD_F's geometry on its home area: every model on the area,
# one centre (m4) 3.78" from the marker, centroid 4.75" from it.
const CG_OFFSETS := [Vector2(-92, 216), Vector2(80, 212), Vector2(12, 224), Vector2(0, 151.16), Vector2(-80, 144)]

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
	print("\n=== FIX_OBJ_AREA_HOLD: hold / charge-off / fall-back / chase gates read the hosting area ===\n")
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

	test_ch_leave_counts_every_model_on_the_area()
	test_ch_leave_counts_area_only_friends()
	test_chase_gate_reads_area_holder_on_contested_objective()
	test_engaged_area_holder_sums_oc_at_the_objective()
	test_fall_back_target_reads_enemy_area_holders()
	test_support_pass_holds_on_the_area()
	test_param_zero_restores_old_reads()
	test_guard_ch_leave_unchanged()
	test_guard_chase_gate_unchanged()
	test_guard_engaged_unchanged()
	test_guard_fall_back_empty_objective_unchanged()
	test_guard_support_off_area_unchanged()

	AIDM._config_overrides.erase("FIX_OBJ_AREA_HOLD")
	tm.terrain_features = prev_terrain
	GameConstants.edition = prev_edition
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

# --- fixtures ---------------------------------------------------------------

func _snapshot(battle_round: int = 3, extra_objs: Array = []) -> Dictionary:
	var objs = [{"id": "obj_area", "position": OBJ, "zone": "no_mans_land", "source_pieces": ["area_obj"]}]
	objs.append_array(extra_objs)
	return {"battle_round": battle_round, "meta": {"battle_round": battle_round},
		"board": {"objectives": objs, "terrain_features": []}, "units": {}}

func _add(snap: Dictionary, uid: String, owner: int, positions: Array, oc: int = 2,
		weapons: Array = [SPEAR], toughness: int = 6, wounds: int = 3) -> Dictionary:
	var models = []
	for i in range(positions.size()):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 40,
			"base_type": "circular", "base_dimensions": {}, "position": positions[i],
			"wounds": wounds, "current_wounds": wounds})
	var u = {"id": uid, "owner": owner, "status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"name": uid, "points": 170, "stats": {"move": 6, "toughness": toughness, "save": 2,
			"wounds": wounds, "leadership": 6, "objective_control": oc},
			"keywords": ["INFANTRY"], "weapons": weapons},
		"models": models, "flags": {}}
	snap.units[uid] = u
	return u

func _offsets(base: Vector2, offsets: Array) -> Array:
	var out: Array = []
	for o in offsets:
		out.append(base + o)
	return out

## Our Custodian Guard (P1, 5 x OC2) on the south half of the area.
func _add_cg(snap: Dictionary) -> Dictionary:
	return _add(snap, "CG", 1, _offsets(OBJ, CG_OFFSETS))

## The enemy (P2, 3 x OC2) on the north half of the area, every centre > 3.79"
## from the marker.
func _add_rival(snap: Dictionary) -> Dictionary:
	return _add(snap, "RIVAL", 2, _offsets(OBJ, [Vector2(-80, -180), Vector2(0, -184), Vector2(80, -180)]))

## Our second squad (P1, 4 x OC2) whose bases overlap the area's east edge
## (centres 4.1-4.9" from the marker).
func _add_pal(snap: Dictionary) -> Dictionary:
	return _add(snap, "PAL", 1, _offsets(OBJ, [Vector2(165, -105), Vector2(165, -35), Vector2(165, 35), Vector2(165, 105)]))

## A charge target 10" east of the area (P2).
func _add_target(snap: Dictionary) -> Dictionary:
	var x := HALF.x + 10.0 * PX
	return _add(snap, "TGT", 2, _offsets(OBJ, [Vector2(x, -40), Vector2(x, 40)]))

func _set_fix(v: float) -> void:
	AIDM._config_overrides["FIX_OBJ_AREA_HOLD"] = v

func _reset() -> void:
	AIDM.reset_caches()
	AIDM.clear_all_plans()

func _leave(snap: Dictionary, target_id: String) -> Dictionary:
	_reset()
	return AIDM._charge_leaves_held_objective("CG", snap.units["CG"], snap.units[target_id], snap, 1)

func _gate(snap: Dictionary, action: String) -> Dictionary:
	_reset()
	var assignment = {"action": action, "objective_id": "obj_area", "objective_pos": OBJ}
	var enemies = AIDM._get_enemy_units(snap, 1)
	var friendly = AIDM._get_units_for_player(snap, 1)
	return AIDM._melee_chase_gate(snap.units["CG"], "CG", assignment, enemies, friendly, snap, 1)

func _engaged(snap: Dictionary, uid: String) -> Dictionary:
	_reset()
	var enemies = AIDM._get_enemy_units(snap, 1)
	return AIDM._decide_engaged_unit(snap.units[uid], uid, uid, ["BEGIN_FALL_BACK", "REMAIN_STATIONARY"],
		AIDM._get_objectives(snap), enemies, snap, 1)

# --- (a) the mismatch cases ----------------------------------------------------

func test_ch_leave_counts_every_model_on_the_area() -> void:
	print("\n--- (a) CH-LEAVE: our squad holds the area alone (5 x OC2), the enemy has 3 x OC2 on it ---")
	_set_fix(1.0)
	var snap = _snapshot()
	_add_cg(snap)
	_add_rival(snap)
	_add_target(snap)
	var leave = _leave(snap, "TGT")
	print("  leave: %s" % str(leave))
	_assert(int(leave.get("mine", -1)) == 10,
		"fix on: the charger's OC on the area is 10 (every model), as objective control counts it (got %s)" % str(leave.get("mine", "?")))
	_assert(int(leave.get("enemy", -1)) == 6, "fix on: the enemy's 3 models on the area count (6) (got %s)" % str(leave.get("enemy", "?")))

func test_ch_leave_counts_area_only_friends() -> void:
	print("\n--- (a) CH-LEAVE: a second squad of ours (4 x OC2) also stands on the area ---")
	_set_fix(1.0)
	var snap = _snapshot()
	_add_cg(snap)
	_add_rival(snap)
	_add_pal(snap)
	_add_target(snap)
	var leave = _leave(snap, "TGT")
	print("  leave: %s" % str(leave))
	_assert(leave.is_empty(), "fix on: 18 - 10 = 8 > 6 - the objective stays ours without the charger, no CH-LEAVE cost (got %s)" % str(leave))

func test_chase_gate_reads_area_holder_on_contested_objective() -> void:
	print("\n--- (a) chase gate: hold-assigned squad on the area, enemy on the same area, round 3 ---")
	_set_fix(1.0)
	var snap = _snapshot(3)
	_add_cg(snap)
	_add_rival(snap)
	var gate = _gate(snap, "hold")
	print("  gate: %s" % str(gate))
	_assert(gate.is_empty(), "fix on: on a contested objective - stays (the gate returns no chase) (got %s)" % str(gate))

func test_engaged_area_holder_sums_oc_at_the_objective() -> void:
	print("\n--- (a) engaged squad on the area (centroid 4.75\" from the marker), enemy 3 x OC2 on the area ---")
	_set_fix(1.0)
	var snap = _snapshot(3)
	_add_cg(snap)
	_add_rival(snap)
	# The engaging enemy: one weak model base to base with m3, off the area.
	_add(snap, "BITER", 2, [OBJ + Vector2(12, 224 + 64)], 1, [SHANK], 3, 1)
	var d = _engaged(snap, "CG")
	print("  decision: %s / %s" % [str(d.get("type", "")), str(d.get("_ai_description", ""))])
	_assert(str(d.get("type", "")) == "REMAIN_STATIONARY" and str(d.get("_ai_description", "")).contains("OC 10 vs 6"),
		"fix on: holds the objective, OC summed AT the objective (10 vs 6) (got %s)" % str(d.get("_ai_description", "")))

func test_fall_back_target_reads_enemy_area_holders() -> void:
	print("\n--- (a) fall-back target: the nearer, better aligned objective has enemy models on its area ---")
	_set_fix(1.0)
	var r = _fall_back_case(true)
	print("  target: %s (A = %s, B = %s)" % [str(r.target), str(OBJ), str(r.b)])
	_assert(r.target.distance_to(r.b) < 1.0, "fix on: retreats toward the open objective B, not the enemy-held A (got %s)" % str(r.target))

func test_support_pass_holds_on_the_area() -> void:
	print("\n--- (a) support pass: a spare squad standing on the area ---")
	_set_fix(1.0)
	var best = _support_case(true)
	print("  best: %s / %s" % [str(best.get("action", "")), str(best.get("reason", ""))])
	_assert(str(best.get("action", "")) == "hold", "fix on: already at the objective - hold (got %s)" % str(best.get("action", "")))

# --- (b) param 0 ---------------------------------------------------------------

func test_param_zero_restores_old_reads() -> void:
	print("\n--- (b) FIX_OBJ_AREA_HOLD = 0: centre / centroid reads, today's values ---")
	_set_fix(0.0)
	var snap = _snapshot()
	_add_cg(snap)
	_add_rival(snap)
	_add_target(snap)
	var leave = _leave(snap, "TGT")
	_assert(int(leave.get("mine", -1)) == 2 and int(leave.get("friendly", -1)) == 2 and int(leave.get("enemy", -1)) == 0,
		"off: CH-LEAVE counts the one model whose centre is within 3.79\" (mine 2, ours 2, theirs 0) (got %s)" % str(leave))
	var snap2 = _snapshot()
	_add_cg(snap2)
	_add_rival(snap2)
	_add_pal(snap2)
	_add_target(snap2)
	var leave2 = _leave(snap2, "TGT")
	_assert(not leave2.is_empty(), "off: with our second squad on the area CH-LEAVE still charges the cost (got %s)" % str(leave2))
	var snap3 = _snapshot(3)
	_add_cg(snap3)
	_add_rival(snap3)
	var gate = _gate(snap3, "hold")
	_assert(not gate.is_empty(), "off: the chase gate reads the squad as off the objective and chases (got %s)" % str(gate))
	var snap4 = _snapshot(3)
	_add_cg(snap4)
	_add_rival(snap4)
	_add(snap4, "BITER", 2, [OBJ + Vector2(12, 224 + 64)], 1, [SHANK], 3, 1)
	var d = _engaged(snap4, "CG")
	print("  engaged off: %s / %s" % [str(d.get("type", "")), str(d.get("_ai_description", ""))])
	_assert(not str(d.get("_ai_description", "")).contains("OC 10 vs 6") and str(d.get("_ai_description", "")).contains("not on objective"),
		"off: the engaged squad reads 'not on objective' (got %s)" % str(d.get("_ai_description", "")))
	var r = _fall_back_case(true)
	_assert(r.target.distance_to(OBJ) < 1.0, "off: the enemy area holders are not counted - retreats toward A (got %s)" % str(r.target))
	var best = _support_case(true)
	_assert(str(best.get("action", "")) == "move", "off: support pass reads it as not at the objective - move (got %s)" % str(best.get("action", "")))
	_set_fix(1.0)

# --- (c) guards ------------------------------------------------------------------

func test_guard_ch_leave_unchanged() -> void:
	print("\n--- (c) guard: CH-LEAVE with the charger off every objective / the target on the same objective ---")
	for v in [0.0, 1.0]:
		_set_fix(v)
		var snap = _snapshot()
		_add(snap, "CG", 1, _offsets(OBJ, [Vector2(-60, 480), Vector2(0, 480), Vector2(60, 480)]))
		_add_rival(snap)
		_add_target(snap)
		_assert(_leave(snap, "TGT").is_empty(), "fix=%.0f: a charger 6\" off the area leaves no objective" % v)
		var snap2 = _snapshot()
		_add_cg(snap2)
		_add(snap2, "TGT2", 2, _offsets(OBJ, [Vector2(-40, 0), Vector2(40, 0)]))
		_assert(_leave(snap2, "TGT2").is_empty(), "fix=%.0f: charging a target on the same objective costs nothing" % v)
	_set_fix(1.0)

func test_guard_chase_gate_unchanged() -> void:
	print("\n--- (c) guard: chase gate off the area / on it with no enemy on the objective ---")
	for v in [0.0, 1.0]:
		_set_fix(v)
		var snap = _snapshot(3)
		_add(snap, "CG", 1, _offsets(OBJ, [Vector2(-60, 420), Vector2(0, 420), Vector2(60, 420)]))
		_add_rival(snap)
		var gate = _gate(snap, "move")
		_assert(not gate.is_empty(), "fix=%.0f: off the area - chases the enemy (got %s)" % [v, str(gate)])
		var snap2 = _snapshot(3)
		_add_cg(snap2)
		var x := HALF.x + 3.0 * PX + R40
		_add(snap2, "NEAR", 2, _offsets(OBJ, [Vector2(x, -40), Vector2(x, 40)]))
		var gate2 = _gate(snap2, "hold")
		_assert(not gate2.is_empty(), "fix=%.0f: on the area but no enemy on the objective - still chases the enemy 9\" away (got %s)" % [v, str(gate2)])
	_set_fix(1.0)

func test_guard_engaged_unchanged() -> void:
	print("\n--- (c) guard: engaged off every objective / standing round the marker ---")
	for v in [0.0, 1.0]:
		_set_fix(v)
		var snap = _snapshot(3)
		_add(snap, "CG", 1, _offsets(OBJ, [Vector2(-60, 480), Vector2(0, 480), Vector2(60, 480)]))
		_add(snap, "BITER", 2, [OBJ + Vector2(0, 480 + 64)], 1, [SHANK], 3, 1)
		var d = _engaged(snap, "CG")
		_assert(str(d.get("_ai_description", "")).contains("not on objective") or str(d.get("type", "")) == "BEGIN_FALL_BACK",
			"fix=%.0f: off every objective - falls back (%s)" % [v, str(d.get("_ai_description", ""))])
		var snap2 = _snapshot(3)
		_add(snap2, "RING", 1, _offsets(OBJ, [Vector2(-64, 0), Vector2(64, 0), Vector2(0, -64), Vector2(0, 64)]))
		_add(snap2, "E2", 2, _offsets(OBJ, [Vector2(-132, 0), Vector2(132, 0)]), 2, [SHANK], 3, 1)
		var d2 = _engaged(snap2, "RING")
		print("  fix=%.0f ring: %s / %s" % [v, str(d2.get("type", "")), str(d2.get("_ai_description", ""))])
		_assert(str(d2.get("type", "")) == "REMAIN_STATIONARY" and str(d2.get("_ai_description", "")).contains("OC 8 vs 4"),
			"fix=%.0f: round the marker - holds with the same OC (8 vs 4) (%s)" % [v, str(d2.get("_ai_description", ""))])
	_set_fix(1.0)

func test_guard_fall_back_empty_objective_unchanged() -> void:
	print("\n--- (c) guard: fall-back target when nobody stands on A ---")
	for v in [0.0, 1.0]:
		_set_fix(v)
		var r = _fall_back_case(false)
		_assert(r.target.distance_to(OBJ) < 1.0, "fix=%.0f: retreats toward A (nearer, better aligned) (got %s)" % [v, str(r.target)])
	_set_fix(1.0)

func test_guard_support_off_area_unchanged() -> void:
	print("\n--- (c) guard: support pass with the squad 6\" off the area ---")
	for v in [0.0, 1.0]:
		_set_fix(v)
		var best = _support_case(false)
		_assert(str(best.get("action", "")) == "move", "fix=%.0f: move (got %s)" % [v, str(best.get("action", ""))])
	_set_fix(1.0)

# --- shared cases ----------------------------------------------------------------

## The falling-back unit at C with its engaging enemy 2.5" north; objective A
## (the area at OBJ) 10" away 30 deg off straight-away, objective B (open
## ground) 10" away 40 deg off. Scores: A -400 + 260, B -400 + 230, each +100
## when it reads uncontrolled — so A wins unless it reads enemy-held.
func _fall_back_case(enemy_on_a: bool) -> Dictionary:
	_reset()
	var c := OBJ - Vector2(200, 346.41)
	var b := c + Vector2(-400.0 * sin(deg_to_rad(40.0)), 400.0 * cos(deg_to_rad(40.0)))
	var snap = _snapshot(3, [{"id": "obj_b", "position": b, "zone": "no_mans_land"}])
	_add(snap, "RUNNER", 1, [c + Vector2(-40, 0), c + Vector2(40, 0)])
	_add(snap, "ENG", 2, [c + Vector2(0, -100)])
	if enemy_on_a:
		_add(snap, "HOLD2", 2, [OBJ + Vector2(0, 190), OBJ + Vector2(0, -190)])
	var enemies = AIDM._get_enemy_units(snap, 1)
	var target: Vector2 = AIDM._pick_fall_back_target(c, c + Vector2(0, -100), AIDM._get_objectives(snap), enemies, 1, snap)
	return {"target": target, "b": b}

func _support_case(on_area: bool) -> Dictionary:
	_reset()
	var snap = _snapshot(3)
	var unit: Dictionary
	if on_area:
		unit = _add_cg(snap)
	else:
		unit = _add(snap, "CG", 1, _offsets(OBJ, [Vector2(-60, 500), Vector2(0, 500), Vector2(60, 500)]))
	var evals = [{"id": "obj_area", "position": OBJ, "priority": 5.0, "state": "held_safe", "enemy_nearby": 0}]
	return AIDM._find_best_remaining_objective(AIDM._get_unit_centroid(unit), evals, {}, unit, snap, 1)
