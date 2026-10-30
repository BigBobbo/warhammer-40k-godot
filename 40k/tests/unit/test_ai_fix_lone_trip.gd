extends SceneTree

# LONE-TRIP (FIX_LONE_TRIP): a FRAGILE unit (T3 or less, 1 wound per model, or
# a lone character) is not sent to capture an objective that the enemy wins
# army against army when the OC the plan actually has there is outnumbered by
# the hopeless ratio. LLM-critic cluster lone_trip (value-checked, 2026-10-30):
# a 4-model Prosecutor squad sent alone into an 18-OC centre, Burna Boyz on a
# 3-turn trip into 25 enemy OC, a lone Chaplain on Bike into 8 OC, a 6-model
# Lootas unit into 48 OC — RACE-SKIP only judged 3+ turn trips, and nothing
# priced a 1-turn trip into an objective the enemy floods next move.
# Durable units keep these trips, and fragile units still go where the plan
# (or the army) can actually contest.
# Run with: godot --headless --path 40k -s tests/unit/test_ai_fix_lone_trip.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

const MOVABLE := ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]
const PX := 40.0  # pixels per inch
const OBJ_X := Vector2(880, 1200)    # the contested objective
const OBJ_SIDE := Vector2(200, 1700) # a quiet objective on our side, nobody near it

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== Fragile units on lone trips (LONE-TRIP) ===\n")
	test_fragile_squad_not_sent_into_next_move_flood()
	test_durable_squad_keeps_the_trip()
	test_fragile_squad_not_sent_on_lost_two_turn_race()
	test_lone_character_not_sent_alone()
	test_fragile_squad_still_reinforces_a_held_objective()
	test_fragile_squad_still_goes_when_the_army_can_contest()
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

# with_side: a second, quiet objective the unit can take instead of obj_x.
func _snapshot(with_side: bool = true) -> Dictionary:
	var objs = [{"id": "obj_x", "position": OBJ_X, "zone": "no_mans_land"}]
	if with_side:
		objs.append({"id": "obj_side", "position": OBJ_SIDE, "zone": "no_mans_land"})
	return {"battle_round": 2, "meta": {"battle_round": 2},
		"board": {"objectives": objs, "terrain_features": []}, "units": {}}

# `n` models (OC 2 each) whose centroid is at `pos`.
func _add_unit(snapshot: Dictionary, unit_id: String, owner: int, pos: Vector2, n: int,
		toughness: int, wounds: int, move: int = 6, keywords: Array = ["INFANTRY"]) -> void:
	var models = []
	for i in range(n):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 32,
			"base_type": "circular", "base_dimensions": {},
			"position": Vector2(pos.x + (i - (n - 1) / 2.0) * 45.0, pos.y), "wounds": wounds, "current_wounds": wounds})
	snapshot.units[unit_id] = {
		"id": unit_id, "owner": owner, "status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"name": unit_id, "points": 200, "stats": {"move": move, "toughness": toughness, "save": 3,
			"wounds": wounds, "leadership": 6, "objective_control": 2}, "keywords": keywords, "weapons": []},
		"models": models, "flags": {}}

# Two 5-model OC 2 enemy squads `enemy_dist` inches above obj_x (20 OC).
func _add_enemies(snap: Dictionary, enemies: Dictionary, enemy_dist: float) -> void:
	for i in range(2):
		var eid = "theirs_%d" % i
		_add_unit(snap, eid, 1, OBJ_X + Vector2((i - 0.5) * 300.0, -enemy_dist * PX), 5, 4, 2)
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
		print("  %s: %s %s [%s] (%s)" % [uid, plan[uid].get("action", ""), plan[uid].get("objective_id", ""),
			plan[uid].get("assign_pass", ""), str(plan[uid].get("reason", "")).substr(0, 110)])
	return plan

func _goes_to(plan: Dictionary, uid: String, oid: String) -> bool:
	var a: Dictionary = plan.get(uid, {})
	return str(a.get("objective_id", "")) == oid and str(a.get("action", "")) in ["move", "advance"]

func test_fragile_squad_not_sent_into_next_move_flood() -> void:
	print("\n--- fragile 4-model squad 8\" from obj_x, 20 enemy OC one move away ---")
	var snap = _snapshot()
	var enemies = {}
	_add_unit(snap, "fragile", 2, OBJ_X + Vector2(0, 8.0 * PX), 4, 3, 1)
	_add_enemies(snap, enemies, 10.0)
	var plan = _plan(snap, ["fragile"], enemies)
	_assert(not _goes_to(plan, "fragile", "obj_x"), "the fragile squad is not sent alone into 20 enemy OC (8 OC of its own)")
	_assert(str(plan.get("fragile", {}).get("coordination_note", "")).begins_with("not going alone to obj_x"),
		"its card says why (%s)" % str(plan.get("fragile", {}).get("coordination_note", "")))

func test_durable_squad_keeps_the_trip() -> void:
	print("\n--- same board, a durable squad (T6, 3 wounds per model) ---")
	var snap = _snapshot()
	var enemies = {}
	_add_unit(snap, "durable", 2, OBJ_X + Vector2(0, 8.0 * PX), 4, 6, 3)
	_add_enemies(snap, enemies, 10.0)
	var plan = _plan(snap, ["durable"], enemies)
	_assert(_goes_to(plan, "durable", "obj_x"), "a durable squad still takes obj_x (contest_race / threat terms price it)")

func test_fragile_squad_not_sent_on_lost_two_turn_race() -> void:
	print("\n--- fragile M7 squad 16\" out (2 turns), 20 enemy OC 2 moves away, obj_x the only objective ---")
	var snap = _snapshot(false)
	var enemies = {}
	_add_unit(snap, "fragile", 2, OBJ_X + Vector2(0, 16.0 * PX), 4, 3, 1, 7)
	_add_enemies(snap, enemies, 18.0)
	var plan = _plan(snap, ["fragile"], enemies)
	for c in AIDecisionMaker._last_movement_candidates.get("fragile", []):
		if str(c.get("objective_id", "")) == "obj_x":
			print("  fragile -> obj_x: turns %d, race_lost %s, race enemy OC %d" % [
				int(c.get("turns_to_reach", 0)), str(c.get("race_lost", false)), int(c.get("race_enemy_oc", 0))])
	_assert(not _goes_to(plan, "fragile", "obj_x"), "a 2-turn race the enemy wins 20 to 8 is not a fragile unit's trip (RACE-SKIP only judges 3+ turns)")

func test_lone_character_not_sent_alone() -> void:
	print("\n--- a lone character (1 model, T5, 5 wounds) 8\" from obj_x ---")
	var snap = _snapshot()
	var enemies = {}
	_add_unit(snap, "hero", 2, OBJ_X + Vector2(0, 8.0 * PX), 1, 5, 5, 6, ["INFANTRY", "CHARACTER"])
	_add_enemies(snap, enemies, 10.0)
	var plan = _plan(snap, ["hero"], enemies)
	_assert(not _goes_to(plan, "hero", "obj_x"), "a lone character is not sent into 20 enemy OC with its 2 OC")

func test_fragile_squad_still_reinforces_a_held_objective() -> void:
	print("\n--- obj_x held by a squad that is not moving (OC 10); fragile squad can reinforce ---")
	var snap = _snapshot()
	var enemies = {}
	_add_unit(snap, "holder", 2, OBJ_X, 5, 6, 3)
	_add_unit(snap, "fragile", 2, OBJ_X + Vector2(0, 8.0 * PX), 4, 3, 1)
	_add_enemies(snap, enemies, 10.0)
	var plan = _plan(snap, ["fragile"], enemies)
	_assert(_goes_to(plan, "fragile", "obj_x"), "with 10 OC already there, 18 vs 20 is a fight worth joining")

func test_fragile_squad_still_goes_when_the_army_can_contest() -> void:
	print("\n--- fragile squad sent first; three friendly squads that are not moving could reach obj_x too ---")
	var snap = _snapshot()
	var enemies = {}
	_add_unit(snap, "fragile", 2, OBJ_X + Vector2(0, 8.0 * PX), 4, 3, 1)
	# one move (M6 + 2") from obj_x's control range, obj_x their nearest objective
	for off in [Vector2(-250, 240), Vector2(250, 240), Vector2(0, 440)]:
		_add_unit(snap, "army_%d" % snap.units.size(), 2, OBJ_X + off, 4, 6, 3)
	_add_enemies(snap, enemies, 10.0)
	var plan = _plan(snap, ["fragile"], enemies)
	_assert(_goes_to(plan, "fragile", "obj_x"), "the enemy does not out-OC our army there (20 vs 32), so it is not a lost fight")

func test_param_zero_restores_base() -> void:
	print("\n--- FIX_LONE_TRIP = 0 ---")
	AIDecisionMaker._config_overrides["FIX_LONE_TRIP"] = 0.0
	var snap = _snapshot()
	var enemies = {}
	_add_unit(snap, "fragile", 2, OBJ_X + Vector2(0, 8.0 * PX), 4, 3, 1)
	_add_enemies(snap, enemies, 10.0)
	var plan = _plan(snap, ["fragile"], enemies)
	AIDecisionMaker._config_overrides.erase("FIX_LONE_TRIP")
	_assert(_goes_to(plan, "fragile", "obj_x"), "with the fix off the fragile squad is sent to obj_x as before")
