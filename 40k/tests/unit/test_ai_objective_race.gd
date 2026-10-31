extends SceneTree

# RACE-1: multi-turn objective trips.
#   A. contest race   — enemy OC that can stand in range before we arrive
#   B. distance cost  — scales with the objective's value, not a flat -2/turn
#   C. long advance   — Advance on a trip that takes several turns when that
#                       saves a whole turn and costs no shooting
# Run with: godot --headless --path 40k -s tests/unit/test_ai_objective_race.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

const OBJ_POS := Vector2(880, 400)
const MOVABLE := ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== AI Objective Race Tests (RACE-1) ===\n")
	test_long_trip_advance_saves_turn()
	test_race_lost_discounts_objective()
	test_race_not_lost_when_enemy_too_far()
	test_distance_cost_scales_with_value()
	test_long_trip_advances_with_no_targets()
	test_long_trip_moves_when_it_can_shoot()
	test_long_trip_no_advance_with_enemy_in_charge_reach()
	test_too_late_trip_not_assigned()
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	print("SOME TESTS FAILED" if _fail_count > 0 else "ALL TESTS PASSED")
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

# One objective, so every unit's assignment is a candidate for it.
func _snapshot() -> Dictionary:
	return {
		"battle_round": 2,
		"board": {
			"objectives": [{"id": "obj_nml_2", "position": OBJ_POS, "zone": "no_mans_land"}],
			"terrain_features": []
		},
		"units": {}
	}

func _add_unit(snapshot: Dictionary, unit_id: String, owner: int, pos: Vector2,
		move: int, weapons: Array = []) -> void:
	var models = []
	for i in range(3):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 40,
			"base_type": "circular", "base_dimensions": {},
			"position": Vector2(pos.x + (i - 1) * 50, pos.y), "wounds": 3, "current_wounds": 3})
	snapshot.units[unit_id] = {
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": unit_id,
			"stats": {"move": move, "toughness": 6, "save": 2, "wounds": 3,
				"leadership": 6, "objective_control": 2},
			"keywords": ["INFANTRY"],
			"weapons": weapons
		},
		"models": models,
		"flags": {}
	}

func _assign(snapshot: Dictionary, our_ids: Array, enemy_ids: Array) -> Dictionary:
	var enemies = {}
	for e in enemy_ids:
		enemies[e] = snapshot.units[e]
	var friendlies = {}
	var movable = {}
	for u in our_ids:
		friendlies[u] = snapshot.units[u]
		movable[u] = MOVABLE
	var objectives = [OBJ_POS]
	var evals = AIDecisionMaker._evaluate_all_objectives(snapshot, objectives, 2, enemies, friendlies, 2)
	return AIDecisionMaker._assign_units_to_objectives(snapshot, movable, evals, objectives, enemies, friendlies, 2, 2)

# A 20.8" GAP to close, like the reported Sentinel Guard squad. OBJ-GAP-1:
# the planner measures the gap to control range (marker centre less 3.79" on
# open ground), so the squad stands 20.8" + 3.79" from the marker.
func _our_pos() -> Vector2:
	return OBJ_POS + Vector2(0, (20.8 + 3.79) * 40.0)

func test_long_trip_advance_saves_turn():
	print("\n--- test_long_trip_advance_saves_turn ---")
	_assert(AIDecisionMaker._long_trip_advance_saves_turn(20.8, 8.0), "M8, 20.8\": 3 turns moving vs 2 advancing")
	_assert(AIDecisionMaker._long_trip_advance_saves_turn(20.8, 6.0), "M6, 20.8\": 4 turns moving vs 3 advancing")
	_assert(not AIDecisionMaker._long_trip_advance_saves_turn(16.0, 8.0), "M8, 16\": 2 turns either way")
	_assert(not AIDecisionMaker._long_trip_advance_saves_turn(5.0, 6.0), "in normal-move range: no advance needed")

func test_race_lost_discounts_objective():
	print("\n--- test_race_lost_discounts_objective ---")
	var snap = _snapshot()
	_add_unit(snap, "us", 2, _our_pos(), 6)
	# Enemy squad 17.5" away at M6: out of COORD-5's one-move window, but in
	# range after 2 moves — before our 3-turn trip lands.
	_add_unit(snap, "them", 1, OBJ_POS + Vector2(0, -17.5 * 40.0), 6)
	var a = _assign(snap, ["us"], ["them"]).get("us", {})
	var terms: Dictionary = a.get("score_terms", {})
	print("  assignment: %s" % str(a.get("reason", "")))
	print("  terms: %s" % str(terms))
	_assert(a.get("race_lost", false), "race_lost flagged (enemy OC %d vs ours 6)" % int(a.get("race_enemy_oc", 0)))
	_assert(float(terms.get("contest_race", 0.0)) < 0.0, "contest_race term cuts the score (%.1f)" % float(terms.get("contest_race", 0.0)))
	_assert(str(a.get("reason", "")).begins_with("racing for it"), "reason tells the player the enemy gets there first")

func test_race_not_lost_when_enemy_too_far():
	print("\n--- test_race_not_lost_when_enemy_too_far ---")
	var snap = _snapshot()
	_add_unit(snap, "us", 2, _our_pos(), 6)
	_add_unit(snap, "them", 1, OBJ_POS + Vector2(0, -40.0 * 40.0), 6)
	var a = _assign(snap, ["us"], ["them"]).get("us", {})
	_assert(not a.get("race_lost", true), "no race loss when the enemy needs 5 moves")
	_assert(not a.get("score_terms", {}).has("contest_race"), "no contest_race term")

func test_distance_cost_scales_with_value():
	print("\n--- test_distance_cost_scales_with_value ---")
	var snap = _snapshot()
	# Ranged weapon + enemy in range => no long advance. _our_pos() stands a
	# 20.8" GAP from control range (OBJ-GAP-1 / REACH-CR both measure the gap,
	# not the marker distance) => ceil(20.8 / 6) = 4 turns at M6.
	_add_unit(snap, "us", 2, _our_pos(), 6, [{"name": "Rifle", "type": "Ranged", "range": "36"}])
	_add_unit(snap, "them", 1, _our_pos() + Vector2(1200, 0), 6)
	var a = _assign(snap, ["us"], ["them"]).get("us", {})
	var terms: Dictionary = a.get("score_terms", {})
	var turns := float(a.get("turns_to_reach", 0))
	var dp := float(terms.get("distance_penalty", 0.0))
	print("  turns=%d distance_penalty=%.2f objective_priority=%.2f" % [turns, dp, float(terms.get("objective_priority", 0.0))])
	_assert(turns == 4.0, "4 turns at M6 without advancing — 20.8\" gap to control range (got %d)" % turns)
	_assert(dp < -2.0 * (turns - 1.0), "distance cost (%.1f) exceeds the old flat -2/turn (%.1f)" % [dp, -2.0 * (turns - 1.0)])

func test_long_trip_advances_with_no_targets():
	print("\n--- test_long_trip_advances_with_no_targets ---")
	var snap = _snapshot()
	_add_unit(snap, "us", 2, _our_pos(), 8)
	var a = _assign(snap, ["us"], []).get("us", {})
	_assert(a.get("action", "") == "advance", "M8 unit 20.8\" out with nothing to shoot advances (action=%s)" % a.get("action", ""))
	_assert(int(a.get("turns_to_reach", 0)) == 2, "costed at the advance pace: 2 turns (got %d)" % int(a.get("turns_to_reach", 0)))

func test_long_trip_moves_when_it_can_shoot():
	print("\n--- test_long_trip_moves_when_it_can_shoot ---")
	var snap = _snapshot()
	_add_unit(snap, "us", 2, _our_pos(), 8, [{"name": "Rifle", "type": "Ranged", "range": "36"}])
	_add_unit(snap, "them", 1, _our_pos() + Vector2(1200, 0), 6)
	var a = _assign(snap, ["us"], ["them"]).get("us", {})
	_assert(a.get("action", "") == "move", "unit with a target in range keeps its shooting (action=%s)" % a.get("action", ""))

func test_long_trip_no_advance_with_enemy_in_charge_reach():
	print("\n--- test_long_trip_no_advance_with_enemy_in_charge_reach ---")
	var snap = _snapshot()
	# Melee-only unit, enemy 15" to its flank (inside M8 + 12"): Advancing would
	# throw away the charge, so it walks.
	_add_unit(snap, "us", 2, _our_pos(), 8)
	_add_unit(snap, "them", 1, _our_pos() + Vector2(15.0 * 40.0, 0), 6)
	var a = _assign(snap, ["us"], ["them"]).get("us", {})
	_assert(a.get("action", "") == "move", "enemy within charge reach: no long-trip advance (action=%s)" % a.get("action", ""))

# TOO-LATE: a capture that cannot finish before the end of round 5 is not
# assigned, even when it is the only objective still needing OC.
func test_too_late_trip_not_assigned():
	print("\n--- test_too_late_trip_not_assigned ---")
	var snap = _snapshot()
	_add_unit(snap, "us", 2, OBJ_POS + Vector2(0, 40.0 * 40.0), 6)  # 40" = 7 turns at M6
	var enemies = {}
	var friendlies = {"us": snap.units["us"]}
	var objectives = [OBJ_POS]
	var evals = AIDecisionMaker._evaluate_all_objectives(snap, objectives, 2, enemies, friendlies, 4)
	var plan = AIDecisionMaker._assign_units_to_objectives(snap, {"us": MOVABLE}, evals, objectives, enemies, friendlies, 2, 4)
	var a = plan.get("us", {})
	_assert(a.get("assign_pass", "") != "capture", "round 4, 7 turns away: not sent to capture (pass=%s)" % a.get("assign_pass", ""))
