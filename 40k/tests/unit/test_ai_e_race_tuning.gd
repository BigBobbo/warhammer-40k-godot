extends SceneTree

# RACE-LATE: the contest race (RACE-1, x MOVE_RACE_LOSS_FACTOR) counts enemy
# units that reach the objective within turns_to_reach moves — including the
# ones that can only get there on the SAME turn count as our unit, i.e. after
# our unit already stands on it. Those were measured against our ONE unit's
# OC, so in round 1 the second player's 2-turn trips to its own no-man's-land
# objective were all "lost" (the first player had already moved up): a cheap
# OC 2 character lost half the objective's value while an OC 10 squad did not,
# and the plan pulled squads onto the near objective instead of flipping the
# enemy's (V5 vs V0 benchmark, 11e, seeds 9111/9113/9114: P2's round-1 plan).
# Same-turn arrivals are now measured against what our ARMY can have there by
# then (race_army_oc); enemies there before we arrive still race this unit.
# Run with: godot --headless --path . -s tests/unit/test_ai_e_race_tuning.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

const MOVABLE := ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]
const PX := 40.0  # pixels per inch
const OBJ_A := Vector2(880, 1500)  # our side of no man's land
const OBJ_FAR := Vector2(880, 300)  # far away, nobody's nearest

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== Contest race: same-turn arrivals vs our army (RACE-LATE) ===\n")
	test_same_turn_enemy_does_not_lose_the_race_for_a_cheap_unit()
	test_enemy_there_first_still_loses_the_race()
	test_same_turn_enemy_outnumbering_our_army_still_loses()
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func _snapshot() -> Dictionary:
	var objs = [{"id": "obj_a", "position": OBJ_A, "zone": "no_mans_land"},
		{"id": "obj_far", "position": OBJ_FAR, "zone": "no_mans_land"}]
	return {"battle_round": 1, "meta": {"battle_round": 1},
		"board": {"objectives": objs, "terrain_features": []}, "units": {}}

# A unit of `n` models (OC 2 each, M6) whose centroid is at `pos`.
func _add_unit(snapshot: Dictionary, unit_id: String, owner: int, pos: Vector2, n: int) -> void:
	var models = []
	for i in range(n):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 40,
			"base_type": "circular", "base_dimensions": {},
			"position": Vector2(pos.x + (i - (n - 1) / 2.0) * 50.0, pos.y), "wounds": 3, "current_wounds": 3})
	snapshot.units[unit_id] = {
		"id": unit_id, "owner": owner, "status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"name": unit_id, "points": 100 * n, "stats": {"move": 6, "toughness": 6, "save": 2,
			"wounds": 3, "leadership": 6, "objective_control": 2}, "keywords": ["INFANTRY"], "weapons": []},
		"models": models, "flags": {}}

# Our army (player 2): a 1-model OC 2 character 14" below obj_a (2 turns at
# M6) and two OC 10 squads ~18" below it. Enemy squads (OC 10 each) start
# `enemy_dist` inches above obj_a.
func _candidate(enemy_dist: float, enemy_count: int) -> Dictionary:
	AIDecisionMaker._primary_awareness_p2 = {}
	AIDecisionMaker._secondary_awareness_p2 = {}
	var snap = _snapshot()
	var friendlies = {}
	var enemies = {}
	var movable = {}
	_add_unit(snap, "char", 2, OBJ_A + Vector2(0, 14.0 * PX), 1)
	_add_unit(snap, "squad_a", 2, OBJ_A + Vector2(-300, 15.0 * PX), 5)
	_add_unit(snap, "squad_b", 2, OBJ_A + Vector2(300, 15.0 * PX), 5)
	for uid in ["char", "squad_a", "squad_b"]:
		friendlies[uid] = snap.units[uid]
		movable[uid] = MOVABLE
	for i in range(enemy_count):
		var eid = "theirs_%d" % i
		_add_unit(snap, eid, 1, OBJ_A + Vector2((i - (enemy_count - 1) / 2.0) * 300.0, -enemy_dist * PX), 5)
		enemies[eid] = snap.units[eid]
	var objectives = [OBJ_A, OBJ_FAR]
	var evals = AIDecisionMaker._evaluate_all_objectives(snap, objectives, 2, enemies, friendlies, 1)
	var plan = AIDecisionMaker._assign_units_to_objectives(snap, movable, evals, objectives, enemies, friendlies, 2, 1)
	for uid in plan:
		print("  plan %s: %s %s (%s)" % [uid, plan[uid].get("action", ""), plan[uid].get("objective_id", ""),
			str(plan[uid].get("reason", "")).substr(0, 100)])
	for c in AIDecisionMaker._last_movement_candidates.get("char", []):
		if str(c.get("objective_id", "")) == "obj_a":
			print("  char -> obj_a: turns %d, race_lost %s, enemy OC %d, our OC %d, army OC %d, terms %s" % [
				int(c.get("turns_to_reach", 0)), str(c.get("race_lost", false)), int(c.get("race_enemy_oc", 0)),
				int(c.get("race_our_oc", 0)), int(c.get("race_army_oc", 0)), str(c.get("score_terms", {}).keys())])
			return c
	return {}

func test_same_turn_enemy_does_not_lose_the_race_for_a_cheap_unit() -> void:
	print("\n--- one OC 10 enemy squad 18\" away (2 moves, same turn count as our character) ---")
	var c = _candidate(18.0, 1)
	_assert(not c.is_empty(), "the character has an obj_a candidate")
	_assert(int(c.get("turns_to_reach", 0)) == 2, "obj_a is a 2-turn trip for the character (got %d)" % int(c.get("turns_to_reach", 0)))
	_assert(int(c.get("race_enemy_oc", 0)) >= 10, "the enemy squad counts in the race window (enemy OC %d)" % int(c.get("race_enemy_oc", 0)))
	_assert(not c.get("race_lost", true),
		"an enemy that arrives after our character, against an army with 22 OC there, does not lose the race")
	_assert(not (c.get("score_terms", {}) as Dictionary).has("contest_race"),
		"no contest_race cut on the character's obj_a score")

func test_enemy_there_first_still_loses_the_race() -> void:
	print("\n--- one OC 10 enemy squad 9\" away (1 move: there before our character) ---")
	var c = _candidate(9.0, 1)
	_assert(int(c.get("turns_to_reach", 0)) == 2, "obj_a is still a 2-turn trip for the character")
	_assert(c.get("race_lost", false), "an enemy squad there before the character arrives still wins its race")

func test_same_turn_enemy_outnumbering_our_army_still_loses() -> void:
	print("\n--- three OC 10 enemy squads 18\" away (30 OC vs our army's 22) ---")
	var c = _candidate(18.0, 3)
	_assert(c.get("race_lost", false), "same-turn arrivals that out-OC our whole army still lose the race")
