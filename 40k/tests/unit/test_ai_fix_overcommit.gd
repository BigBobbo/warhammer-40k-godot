extends SceneTree

# OVERCOMMIT (FIX_OVERCOMMIT): a TOP-UP on a multi-turn trip — a unit sent to
# an objective that another unit of the plan already heads for — is not
# stacked onto a race the plan still loses with it. When the OC the plan puts
# there (holders, units en route, units sent, this unit) is below the enemy OC
# that can be there by the time it arrives, the unit takes its best other
# objective that still needs OC and that it reaches no later. LLM-critic
# cluster overcommit (value-checked, 2026-10-30): COORD-5's capped projected
# need left a 2-OC remainder at the centre after Custodian Guard Alpha, so
# Custodian Guard Beta advanced two turns into an 18 vs 30 OC race there while
# an enemy-held objective it reaches as soon went uncontested.
# The top-up stands when it wins the race, or when no such objective exists.
# Merged with FAR-TRIP: the redirect target is NOT filtered by FAR-TRIP — a
# lone race the unit loses still beats the lost top-up (see
# test_redirect_takes_lone_race_over_lost_top_up).
# Run with: godot --headless --path 40k -s tests/unit/test_ai_fix_overcommit.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

const MOVABLE := ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]
const PX := 40.0  # pixels per inch
const OBJ_X := Vector2(880, 1200)     # the hot objective the enemy floods
const OBJ_SIDE := Vector2(300, 1500)  # an objective a small enemy squad holds
const ALPHA_POS := Vector2(1180, 1400)  # 9" from obj_x: there this turn; 22" from obj_side
# MERGE (main OBJ-GAP-1 + ADV-ODDS-1): beta moved ~1" (was (810, 1776)).
# From its nearest model the old spot was a 9.6" gap to obj_side, which an
# Advance closes on a 4+ — ADV-ODDS-1 plans that as a this-turn arrival, so
# obj_side was no longer a 2-turn trip. Here both gaps are over M+4"
# (obj_x ~11.2", obj_side ~10.6"): two moves to either, as the tests assume.
const BETA_POS := Vector2(840, 1800)    # ~15" from obj_x AND ~14.5" from obj_side: two moves to either

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== Top-ups onto a lost race (OVERCOMMIT) ===\n")
	AIDecisionMaker._config_overrides["FIX_OVERCOMMIT"] = 1.0  # the fix may be off by default; the checks switch it on
	test_second_unit_not_stacked_on_lost_race()
	test_top_up_stands_when_it_wins_the_race()
	test_top_up_stands_without_a_near_alternative()
	test_redirect_takes_lone_race_over_lost_top_up()
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

func _snapshot(side_pos: Vector2 = OBJ_SIDE) -> Dictionary:
	var objs = [{"id": "obj_x", "position": OBJ_X, "zone": "no_mans_land"},
		{"id": "obj_side", "position": side_pos, "zone": "no_mans_land"}]
	return {"battle_round": 1, "meta": {"battle_round": 1},
		"board": {"objectives": objs, "terrain_features": []}, "units": {}}

# `n` durable models (T6, 3 wounds, OC `oc` each) whose centroid is at `pos`.
func _add_unit(snapshot: Dictionary, unit_id: String, owner: int, pos: Vector2, n: int, oc: int) -> void:
	var models = []
	for i in range(n):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 40,
			"base_type": "circular", "base_dimensions": {},
			"position": Vector2(pos.x + (i - (n - 1) / 2.0) * 50.0, pos.y), "wounds": 3, "current_wounds": 3})
	snapshot.units[unit_id] = {
		"id": unit_id, "owner": owner, "status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"name": unit_id, "points": 200, "stats": {"move": 6, "toughness": 6, "save": 2,
			"wounds": 3, "leadership": 6, "objective_control": oc}, "keywords": ["INFANTRY"], "weapons": []},
		"models": models, "flags": {}}

# Our two 3-model OC 3 squads (9 OC each): alpha reaches obj_x this turn, so
# the plan sends it first; beta is two moves from obj_x and from obj_side.
# `enemy_squads` 5-model OC 2 squads (10 OC each) sit one move above obj_x
# (their nearest objective; the first is two moves from obj_side); a 4-model
# OC 2 squad (8 OC) holds obj_side.
func _board(enemies: Dictionary, enemy_squads: int, side_pos: Vector2 = OBJ_SIDE) -> Dictionary:
	var snap = _snapshot(side_pos)
	_add_unit(snap, "alpha", 2, ALPHA_POS, 3, 3)
	_add_unit(snap, "beta", 2, BETA_POS, 3, 3)
	for i in range(enemy_squads):
		var eid = "theirs_%d" % i
		_add_unit(snap, eid, 1, Vector2(580.0 + i * 300.0, 840.0), 5, 2)
		enemies[eid] = snap.units[eid]
	_add_unit(snap, "holder", 1, side_pos, 4, 2)
	enemies["holder"] = snap.units["holder"]
	return snap

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
	var evals = AIDecisionMaker._evaluate_all_objectives(snap, objectives, 2, enemies, friendlies, 1)
	var plan = AIDecisionMaker._assign_units_to_objectives(snap, movable, evals, objectives, enemies, friendlies, 2, 1)
	for uid in plan:
		print("  %s: %s %s [%s] (%s)" % [uid, plan[uid].get("action", ""), plan[uid].get("objective_id", ""),
			plan[uid].get("assign_pass", ""), str(plan[uid].get("reason", "")).substr(0, 110)])
	for uid in ["alpha", "beta"]:
		for c in AIDecisionMaker._last_movement_candidates.get(uid, []):
			print("    %s -> %s: %s score %.1f, %d turn(s), race lost %s (enemy ~%d OC)" % [uid, c.objective_id,
				c.action, float(c.score), int(c.turns_to_reach), str(c.get("race_lost", false)), int(c.get("race_enemy_oc", 0))])
	return plan

func _goes_to(plan: Dictionary, uid: String, oid: String) -> bool:
	var a: Dictionary = plan.get(uid, {})
	return str(a.get("objective_id", "")) == oid and str(a.get("action", "")) in ["move", "advance"]

func test_second_unit_not_stacked_on_lost_race() -> void:
	print("\n--- 30 enemy OC one move from obj_x; alpha there this turn, beta two moves out (18 OC) ---")
	var enemies = {}
	var snap = _board(enemies, 3)
	var plan = _plan(snap, ["alpha", "beta"], enemies)
	_assert(_goes_to(plan, "alpha", "obj_x"), "alpha still races for obj_x (the first unit is priced by contest_race, as before)")
	_assert(_goes_to(plan, "beta", "obj_side"), "beta is not stacked on obj_x (18 vs ~34 OC there by then) — it takes obj_side, as near, instead")
	_assert(str(plan.get("beta", {}).get("coordination_note", "")).begins_with("not stacking on obj_x"),
		"its card says why (%s)" % str(plan.get("beta", {}).get("coordination_note", "")))

func test_top_up_stands_when_it_wins_the_race() -> void:
	print("\n--- only 10 enemy OC one move from obj_x: alpha + beta (18 OC) win it ---")
	var enemies = {}
	var snap = _board(enemies, 1)
	var plan = _plan(snap, ["alpha", "beta"], enemies)
	_assert(_goes_to(plan, "alpha", "obj_x") and _goes_to(plan, "beta", "obj_x"),
		"both still go to obj_x — the second unit turns the race (top-up kept)")

func test_top_up_stands_without_a_near_alternative() -> void:
	print("\n--- obj_side moved out of beta's two-move reach ---")
	var enemies = {}
	var snap = _board(enemies, 3, Vector2(1700, 300))
	var plan = _plan(snap, ["alpha", "beta"], enemies)
	_assert(_goes_to(plan, "beta", "obj_x"), "with no objective beta reaches as soon, the top-up stands (base behaviour)")

# FAR-TRIP x OVERCOMMIT (merge): obj_side is a 2-turn race beta loses alone
# (9 vs ~13 OC, nobody can join it) — FAR-TRIP keeps beta off it when beta is
# on its own — yet as alpha's lost top-up at obj_x (18 vs ~34) beta is still
# redirected there. At the overcommit finding (s7434) the redirect target was
# such a race too (obj_nml_2, 9 vs 18), and it beat the 18 vs 30 top-up
# (rollout E +5.7 VP, 12 seeds); filtering the redirect by FAR-TRIP undid it.
func test_redirect_takes_lone_race_over_lost_top_up() -> void:
	print("\n--- FAR-TRIP x OVERCOMMIT: beta on its own, then beta as alpha's top-up ---")
	var enemies = {}
	var snap = _board(enemies, 3)
	snap.units.erase("alpha")
	var plan = _plan(snap, ["beta"], enemies)
	_assert(not _goes_to(plan, "beta", "obj_side"),
		"on its own, beta is kept off obj_side, a 2-turn race it loses 9 vs ~13 (FAR-TRIP)")
	enemies = {}
	snap = _board(enemies, 3)
	plan = _plan(snap, ["alpha", "beta"], enemies)
	_assert(_goes_to(plan, "beta", "obj_side"),
		"as alpha's lost top-up, beta is still redirected to obj_side (the redirect does not apply FAR-TRIP)")

func test_param_zero_restores_base() -> void:
	print("\n--- FIX_OVERCOMMIT = 0 ---")
	AIDecisionMaker._config_overrides["FIX_OVERCOMMIT"] = 0.0
	var enemies = {}
	var snap = _board(enemies, 3)
	var plan = _plan(snap, ["alpha", "beta"], enemies)
	AIDecisionMaker._config_overrides["FIX_OVERCOMMIT"] = 1.0  # the fix may be off by default; the checks switch it on
	_assert(_goes_to(plan, "alpha", "obj_x") and _goes_to(plan, "beta", "obj_x"),
		"with the fix off beta tops up obj_x as before")
