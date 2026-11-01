extends SceneTree

# RACE-ARMY: RACE-SKIP (do not send a unit on a 3+ turn trip to a race the
# enemy wins by 2x) compared the enemy's whole reachable OC with ONE unit (plus
# units already sent). In a mirror both armies are equally close to the centre,
# so both skipped it and stacked on side objectives (old-vs-new benchmark,
# 2026-10-29, seed 9102). The race is now army against army, and a unit that
# is not sent only supports objectives the army holds, contests or is taking.
# Run with: godot --headless --path . -s tests/unit/test_ai_race_army.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

const MOVABLE := ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]
const CENTRE := Vector2(880, 1200)
const PX := 40.0  # pixels per inch

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== Race army against army (RACE-ARMY) ===\n")
	test_mirror_centre_is_contested()
	test_lone_unit_still_skips_a_lost_race()
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

const SIDE_L := Vector2(60, 1200)
const SIDE_R := Vector2(1700, 1200)

func _snapshot() -> Dictionary:
	# Side objectives ~31" from both armies, so the centre (24") is every
	# unit's nearest objective.
	var objs = [{"id": "obj_center", "position": CENTRE, "zone": "no_mans_land"},
		{"id": "obj_side_l", "position": SIDE_L, "zone": "no_mans_land"},
		{"id": "obj_side_r", "position": SIDE_R, "zone": "no_mans_land"}]
	return {"battle_round": 1, "meta": {"battle_round": 1},
		"board": {"objectives": objs, "terrain_features": []}, "units": {}}

func _add_unit(snapshot: Dictionary, unit_id: String, owner: int, pos: Vector2) -> void:
	var models = []
	for i in range(3):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 40,
			"base_type": "circular", "base_dimensions": {},
			"position": Vector2(pos.x + (i - 1) * 50, pos.y), "wounds": 3, "current_wounds": 3})
	snapshot.units[unit_id] = {
		"id": unit_id, "owner": owner, "status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"name": unit_id, "points": 100, "stats": {"move": 6, "toughness": 6, "save": 2,
			"wounds": 3, "leadership": 6, "objective_control": 2}, "keywords": ["INFANTRY"], "weapons": []},
		"models": models, "flags": {}}

func _plan(our_count: int, enemy_count: int, enemy_on_side: bool = false) -> Dictionary:
	AIDecisionMaker._primary_awareness_p2 = {}
	AIDecisionMaker._secondary_awareness_p2 = {}
	var snap = _snapshot()
	var friendlies = {}
	var enemies = {}
	var movable = {}
	# 24" from the centre: gap 20.2" to control range = 3 turns at M6 even
	# Advancing every turn (4 walking) — a trip RACE-SKIP judges.
	for i in range(our_count):
		var uid = "ours_%d" % i
		_add_unit(snap, uid, 2, CENTRE + Vector2((i - our_count / 2.0) * 200.0, 24.0 * PX))
		friendlies[uid] = snap.units[uid]
		movable[uid] = MOVABLE
	for i in range(enemy_count):
		var eid = "theirs_%d" % i
		_add_unit(snap, eid, 1, CENTRE + Vector2((i - enemy_count / 2.0) * 200.0, -24.0 * PX))
		enemies[eid] = snap.units[eid]
	if enemy_on_side:
		_add_unit(snap, "their_holder", 1, SIDE_R)
		enemies["their_holder"] = snap.units["their_holder"]
	var objectives = [CENTRE, SIDE_L, SIDE_R]
	var evals = AIDecisionMaker._evaluate_all_objectives(snap, objectives, 2, enemies, friendlies, 1)
	return AIDecisionMaker._assign_units_to_objectives(snap, movable, evals, objectives, enemies, friendlies, 2, 1)

func _count_to(plan: Dictionary, oid: String) -> int:
	var n := 0
	for uid in plan:
		if str(plan[uid].get("objective_id", "")) == oid:
			n += 1
	return n

func test_mirror_centre_is_contested() -> void:
	print("\n--- mirror: 4 vs 4, both 3 turns from the centre ---")
	var plan = _plan(4, 4)
	for uid in plan:
		print("  %s: %s %s (%s)" % [uid, plan[uid].get("action", ""), plan[uid].get("objective_id", ""), str(plan[uid].get("reason", "")).substr(0, 90)])
	_assert(_count_to(plan, "obj_center") >= 1, "the army contests the centre in a mirror (%d unit(s) sent)" % _count_to(plan, "obj_center"))

func test_lone_unit_still_skips_a_lost_race() -> void:
	print("\n--- 1 vs 4: the enemy has 4x our army's OC there first ---")
	var plan = _plan(1, 4, true)
	for uid in plan:
		print("  %s: %s %s (%s)" % [uid, plan[uid].get("action", ""), plan[uid].get("objective_id", ""), str(plan[uid].get("reason", "")).substr(0, 90)])
	_assert(_count_to(plan, "obj_center") == 0, "a lone unit is not sent into a race the enemy army wins 4 to 1")
	_assert(_count_to(plan, "obj_side_r") == 0, "the skipped unit does not walk to an enemy-held objective nobody is taking")
