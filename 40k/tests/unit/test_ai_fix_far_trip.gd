extends SceneTree

# FAR-TRIP (FIX_FAR_TRIP): no unit — durable ones too — is sent on a trip of 2+
# turns to capture an objective it would fight for alone and lose: the enemy OC
# there by the time it arrives beats both what our army can have there and what
# the plan puts there, and the other units that could join it in time bring
# less OC than it does. LLM-critic cluster far_trip (value-checked, 2026-10-30):
# a 3-model Custodian Guard squad (OC 9) sent alone on a 2-turn race the Orks
# win 56 to 9, another on a 2-turn race lost 13 to 9 while the centre (where the
# army could join it) was open, and — as a pass-2 leftover or a COORD-4 backfill
# — on 4-turn trips to the enemy-held home objective. LONE-TRIP only covers
# FRAGILE units and RACE-SKIP only 3+ turn trips at 2x odds.
# Trips the unit or the army wins, uncontested trips, and lost races other
# units can join are kept.
# Run with: godot --headless --path 40k -s tests/unit/test_ai_fix_far_trip.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

const MOVABLE := ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]
const PX := 40.0  # pixels per inch
const OBJ_X := Vector2(880, 1200)     # the far objective the enemy races for
const OBJ_NEAR := Vector2(300, 1900)  # a quiet objective next to our units
const POS_A := Vector2(300, 2100)     # 5" from obj_near — takes it this turn
# MERGE (main OBJ-GAP-1 + ADV-ODDS-1): squad b moved 1.5" further from obj_x
# (was (560, 1700)). Measured from its nearest model the old spot was a 10.2"
# gap, which an Advance closes on a 4+ — ADV-ODDS-1 then plans it as a
# this-turn arrival (turns 1) and there is no 2-turn race to judge. From here
# the gap is ~11.7" (a 5+, 33%): still 2 turns, the race FAR-TRIP is about.
const POS_B := Vector2(528, 1751)     # ~7" from obj_near, 2 turns at M7 from obj_x

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== Durable units on lone, lost trips (FAR-TRIP) ===\n")
	AIDecisionMaker._config_overrides["FIX_FAR_TRIP"] = 1.0  # the fix may be off by default; the checks switch it on
	test_durable_squad_not_sent_alone_on_lost_race()
	test_durable_squad_not_sent_on_leftover_lost_trip()
	test_lost_race_kept_when_other_units_can_join()
	test_uncontested_long_trip_kept()
	test_race_the_unit_wins_alone_kept()
	test_long_trip_judged_on_who_is_near()
	test_long_trip_kept_when_no_enemy_near()
	test_param_zero_restores_base()
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func _snapshot(with_near: bool = true) -> Dictionary:
	var objs = [{"id": "obj_x", "position": OBJ_X, "zone": "no_mans_land"}]
	if with_near:
		objs.append({"id": "obj_near", "position": OBJ_NEAR, "zone": "no_mans_land"})
	return {"battle_round": 2, "meta": {"battle_round": 2},
		"board": {"objectives": objs, "terrain_features": []}, "units": {}}

# `n` models (OC 2 each) whose centroid is at `pos`.
func _add_unit(snapshot: Dictionary, unit_id: String, owner: int, pos: Vector2, n: int,
		toughness: int, wounds: int, move: int = 7, keywords: Array = ["INFANTRY"]) -> void:
	var models = []
	for i in range(n):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 32,
			"base_type": "circular", "base_dimensions": {},
			"position": Vector2(pos.x + (i - (n - 1) / 2.0) * 45.0, pos.y), "wounds": wounds, "current_wounds": wounds})
	snapshot.units[unit_id] = {
		"id": unit_id, "owner": owner, "status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"name": unit_id, "points": 200, "stats": {"move": move, "toughness": toughness, "save": 2,
			"wounds": wounds, "leadership": 6, "objective_control": 2}, "keywords": keywords, "weapons": []},
		"models": models, "flags": {}}

# A durable squad: 4 models, T7, 5 wounds each (OC 8) — not LONE-TRIP fragile.
func _add_durable(snap: Dictionary, unit_id: String, pos: Vector2) -> void:
	_add_unit(snap, unit_id, 2, pos, 4, 7, 5)

# `squads` x 5-model OC 2 enemy squads 18" above obj_x: 2 moves to its control
# range at M6 (+2" slack), so they race for it (10 OC each).
func _add_enemies(snap: Dictionary, enemies: Dictionary, squads: int = 2, models: int = 5) -> void:
	for i in range(squads):
		var eid = "theirs_%d" % i
		_add_unit(snap, eid, 1, OBJ_X + Vector2((i - (squads - 1) / 2.0) * 300.0, -18.0 * PX), models, 4, 2, 6)
		enemies[eid] = snap.units[eid]

func _plan(snap: Dictionary, movable_ids: Array, enemies: Dictionary) -> Dictionary:
	AIDecisionMaker._primary_awareness_p2 = {}
	AIDecisionMaker._secondary_awareness_p2 = {}
	var friendlies = {}
	var movable = {}
	for uid in snap.units:
		if int(snap.units[uid].owner) == 2:
			friendlies[uid] = snap.units[uid]
	for uid in movable_ids:
		movable[uid] = MOVABLE
	var objectives = []
	for o in snap.board.objectives:
		objectives.append(o.position)
	var evals = AIDecisionMaker._evaluate_all_objectives(snap, objectives, 2, enemies, friendlies, 2)
	var plan = AIDecisionMaker._assign_units_to_objectives(snap, movable, evals, objectives, enemies, friendlies, 2, 2)
	for uid in plan:
		print("  %s: %s %s [%s] (%s) %s" % [uid, plan[uid].get("action", ""), plan[uid].get("objective_id", ""),
			plan[uid].get("assign_pass", ""), str(plan[uid].get("reason", "")).substr(0, 110),
			str(plan[uid].get("coordination_note", "")).substr(0, 110)])
	for c in AIDecisionMaker._last_movement_candidates.get("b", []):
		if str(c.get("objective_id", "")) == "obj_x":
			print("  b -> obj_x: turns %d, race_lost %s, race enemy OC %d, our %d, army %d" % [
				int(c.get("turns_to_reach", 0)), str(c.get("race_lost", false)), int(c.get("race_enemy_oc", 0)),
				int(c.get("race_our_oc", 0)), int(c.get("race_army_oc", 0))])
	return plan

func _goes_to(plan: Dictionary, uid: String, oid: String) -> bool:
	var a: Dictionary = plan.get(uid, {})
	return str(a.get("objective_id", "")) == oid and str(a.get("action", "")) in ["move", "advance"]

func test_durable_squad_not_sent_alone_on_lost_race() -> void:
	print("\n--- durable squad 2 turns from obj_x, 20 enemy OC 2 moves away, nobody else near ---")
	var snap = _snapshot(false)
	var enemies = {}
	_add_durable(snap, "b", POS_B)
	_add_enemies(snap, enemies)
	var plan = _plan(snap, ["b"], enemies)
	_assert(not _goes_to(plan, "b", "obj_x"), "a durable squad (OC 8) is not sent alone on a 2-turn race the enemy wins 20 to 8")
	_assert(str(plan.get("b", {}).get("coordination_note", "")).begins_with("not going alone to obj_x"),
		"its card says why (%s)" % str(plan.get("b", {}).get("coordination_note", "")))

func test_durable_squad_not_sent_on_leftover_lost_trip() -> void:
	print("\n--- obj_near taken by squad a; squad b's leftover is the lost race to obj_x ---")
	var snap = _snapshot()
	var enemies = {}
	_add_durable(snap, "a", POS_A)
	_add_durable(snap, "b", POS_B)
	_add_enemies(snap, enemies)
	var plan = _plan(snap, ["a", "b"], enemies)
	_assert(_goes_to(plan, "a", "obj_near"), "squad a takes obj_near")
	_assert(not _goes_to(plan, "b", "obj_x"), "squad b is not sent on the 2-turn trip it would fight alone and lose")
	_assert(_goes_to(plan, "b", "obj_near") and str(plan.get("b", {}).get("assign_pass", "")) == "support",
		"squad b supports obj_near, where the army is going (%s %s [%s])" % [
			str(plan.get("b", {}).get("action", "")), str(plan.get("b", {}).get("objective_id", "")),
			str(plan.get("b", {}).get("assign_pass", ""))])

func test_lost_race_kept_when_other_units_can_join() -> void:
	print("\n--- same leftover, but a friendly squad 10\" from obj_x can join it next move ---")
	var snap = _snapshot()
	var enemies = {}
	_add_durable(snap, "a", POS_A)
	_add_durable(snap, "b", POS_B)
	_add_durable(snap, "c", OBJ_X + Vector2(0, 10.0 * PX))  # not moving this phase
	_add_enemies(snap, enemies)
	var plan = _plan(snap, ["a", "b"], enemies)
	_assert(_goes_to(plan, "b", "obj_x"), "a race the army can join (20 vs 8 + 8 that can arrive in time) is still run — contest_race prices it")

func test_uncontested_long_trip_kept() -> void:
	print("\n--- no enemy can reach obj_x in time ---")
	var snap = _snapshot()
	var enemies = {}
	_add_durable(snap, "a", POS_A)
	_add_durable(snap, "b", POS_B)
	_add_unit(snap, "far_enemy", 1, Vector2(1600, 300), 5, 4, 2, 6)
	enemies["far_enemy"] = snap.units["far_enemy"]
	var plan = _plan(snap, ["a", "b"], enemies)
	_assert(_goes_to(plan, "b", "obj_x"), "an uncontested 2-turn trip is kept")

func test_race_the_unit_wins_alone_kept() -> void:
	print("\n--- only 4 enemy OC can race for obj_x ---")
	var snap = _snapshot()
	var enemies = {}
	_add_durable(snap, "a", POS_A)
	_add_durable(snap, "b", POS_B)
	_add_enemies(snap, enemies, 1, 2)
	var plan = _plan(snap, ["a", "b"], enemies)
	_assert(_goes_to(plan, "b", "obj_x"), "a race the unit wins alone (8 vs 4) is kept")

# A 3-turn trip (30" at M7, Advancing) to obj_x; three friendly squads that are
# not moving stand 27-29" (3 moves) from obj_x on the far side.
const POS_LONG := Vector2(160, 2160)
const ARMY_FAR := [Vector2(1480, 2140), Vector2(1300, 2200), Vector2(1640, 2050)]

func test_long_trip_judged_on_who_is_near() -> void:
	print("\n--- 3-turn trip; 20 enemy OC 6\" from obj_x; our army 3 moves out, nobody near it ---")
	var snap = _snapshot(false)
	var enemies = {}
	_add_durable(snap, "b", POS_LONG)
	for i in range(ARMY_FAR.size()):
		_add_durable(snap, "army_%d" % i, ARMY_FAR[i])
	for i in range(2):
		var eid = "near_%d" % i
		_add_unit(snap, eid, 1, OBJ_X + Vector2((i - 0.5) * 300.0, -6.0 * PX), 5, 4, 2, 6)
		enemies[eid] = snap.units[eid]
	var plan = _plan(snap, ["b"], enemies)
	_assert(not _goes_to(plan, "b", "obj_x"),
		"a long trip to where the enemy stands and none of our units are near is not run (the far army 'arriving in time' is busy elsewhere)")

func test_long_trip_kept_when_no_enemy_near() -> void:
	print("\n--- same 3-turn trip; a 10-OC enemy squad 26\" from obj_x (3 moves: a lost race, not a hopeless one) ---")
	var snap = _snapshot(false)
	var enemies = {}
	_add_durable(snap, "b", POS_LONG)
	_add_unit(snap, "far_0", 1, OBJ_X + Vector2(0, -26.0 * PX), 5, 4, 2, 6)
	enemies["far_0"] = snap.units["far_0"]
	var plan = _plan(snap, ["b"], enemies)
	_assert(_goes_to(plan, "b", "obj_x") and str(plan.get("b", {}).get("assign_pass", "")) == "capture",
		"a long trip to an objective no enemy is near is still a capture (the army does not turn passive)")

func test_param_zero_restores_base() -> void:
	print("\n--- FIX_FAR_TRIP = 0 ---")
	AIDecisionMaker._config_overrides["FIX_FAR_TRIP"] = 0.0
	var snap = _snapshot()
	var enemies = {}
	_add_durable(snap, "a", POS_A)
	_add_durable(snap, "b", POS_B)
	_add_enemies(snap, enemies)
	var plan = _plan(snap, ["a", "b"], enemies)
	AIDecisionMaker._config_overrides["FIX_FAR_TRIP"] = 1.0  # the fix may be off by default; the checks switch it on
	_assert(_goes_to(plan, "b", "obj_x"), "with the fix off squad b is sent on the lost trip to obj_x as before")
