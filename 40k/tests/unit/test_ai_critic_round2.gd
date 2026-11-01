extends SceneTree

# Second set of fixes from the LLM-critic review (final run, 2026-10-28):
#  KEEPER-PICK  the cheapest unit that holds alone keeps the objective
#  RETALIATION  a charge that does not kill pays for the target hitting back
#  RES-OBJ2     reserve arrival values the one best objective it can help with
#  RACE-1b      an enemy unit nearer another objective counts at half OC
# Run with: godot --headless --path . -s tests/unit/test_ai_critic_round2.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

const MOVABLE := ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]
const HOME := Vector2(880, 2200)
const NML := Vector2(880, 1200)
const NML_B := Vector2(1600, 1200)

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== Critic round 2 fixes ===\n")
	test_cheapest_holder_keeps_home()
	test_charge_pays_for_retaliation()
	test_reserve_objective_term_is_one_best()
	test_race_counts_other_objective_enemies_at_half()
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func _snapshot(objs: Array) -> Dictionary:
	return {"battle_round": 2, "meta": {"battle_round": 2},
		"board": {"objectives": objs, "terrain_features": []}, "units": {}}

func _add_unit(snapshot: Dictionary, unit_id: String, owner: int, pos: Vector2, points: int = 100,
		oc: int = 2, weapons: Array = []) -> void:
	var models = []
	for i in range(3):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 40,
			"base_type": "circular", "base_dimensions": {},
			"position": Vector2(pos.x + (i - 1) * 50, pos.y), "wounds": 3, "current_wounds": 3})
	snapshot.units[unit_id] = {
		"id": unit_id, "owner": owner, "status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"name": unit_id, "points": points, "stats": {"move": 8, "toughness": 6, "save": 3,
			"wounds": 3, "leadership": 6, "objective_control": oc}, "keywords": ["INFANTRY"], "weapons": weapons},
		"models": models, "flags": {}}

func _weapon(type: String, s: int, a: String, ap: String, d: String) -> Dictionary:
	return {"name": type + " weapon", "type": type, "range": "Melee" if type == "Melee" else "24",
		"strength": str(s), "attacks": a, "ap": ap, "damage": d, "special_rules": ""}

func test_cheapest_holder_keeps_home() -> void:
	print("\n--- KEEPER-PICK ---")
	AIDecisionMaker._primary_awareness_p2 = {}
	var snap = _snapshot([{"id": "obj_home_2", "position": HOME, "zone": "player2"},
		{"id": "obj_nml_1", "position": NML, "zone": "no_mans_land"}])
	_add_unit(snap, "elite", 2, HOME, 270)       # listed first: the old tie-break kept it
	_add_unit(snap, "cheap", 2, HOME + Vector2(0, 60), 45)
	var friendlies = {"elite": snap.units.elite, "cheap": snap.units.cheap}
	var objectives = [HOME, NML]
	var evals = AIDecisionMaker._evaluate_all_objectives(snap, objectives, 2, {}, friendlies, 2)
	var plan = AIDecisionMaker._assign_units_to_objectives(snap, {"elite": MOVABLE, "cheap": MOVABLE}, evals, objectives, {}, friendlies, 2, 2)
	print("  elite: %s %s | cheap: %s %s" % [plan.elite.get("action"), plan.elite.get("objective_id"), plan.cheap.get("action"), plan.cheap.get("objective_id")])
	_assert(plan.cheap.get("action", "") == "hold" and plan.cheap.get("objective_id", "") == "obj_home_2", "the 45 pt squad keeps home")
	_assert(plan.elite.get("objective_id", "") == "obj_nml_1", "the 270 pt unit goes forward to the open objective")

func test_charge_pays_for_retaliation() -> void:
	print("\n--- RETALIATION ---")
	var snap = _snapshot([])
	_add_unit(snap, "charger", 1, Vector2(0, 0), 100, 2, [_weapon("Melee", 4, "2", "0", "1")])
	_add_unit(snap, "brute", 2, Vector2(0, 200), 100, 2, [_weapon("Melee", 8, "6", "-2", "2")])
	var terms := {}
	AIDecisionMaker._score_charge_target(snap.units.charger, snap.units.brute, snap, 1, terms)
	print("  terms: %s" % str(terms))
	_assert(float(terms.get("ch_retaliation", 0.0)) < 0.0, "charging a survivor that hits hard costs score (%.2f)" % float(terms.get("ch_retaliation", 0.0)))
	var weak = _snapshot([])
	_add_unit(weak, "charger", 1, Vector2(0, 0), 100, 2, [_weapon("Melee", 4, "2", "0", "1")])
	_add_unit(weak, "unarmed", 2, Vector2(0, 200), 100, 2, [])
	var terms2 := {}
	AIDecisionMaker._score_charge_target(weak.units.charger, weak.units.unarmed, weak, 1, terms2)
	print("  unarmed retaliation: %.2f" % float(terms2.get("ch_retaliation", 0.0)))
	_assert(float(terms2.get("ch_retaliation", 0.0)) > float(terms.get("ch_retaliation", 0.0)) * 0.5,
		"a unit without melee weapons hits back far less than a melee brute (%.2f vs %.2f)" % [
		float(terms2.get("ch_retaliation", 0.0)), float(terms.get("ch_retaliation", 0.0))])

func test_reserve_objective_term_is_one_best() -> void:
	print("\n--- RES-OBJ2 ---")
	var objs = [{"id": "obj_home_1", "position": Vector2(880, 200), "zone": "player1"}]
	for i in range(4):
		objs.append({"id": "obj_nml_%d" % (i + 1), "position": Vector2(300 + i * 400, 1200), "zone": "no_mans_land"})
	var snap = _snapshot(objs)
	_add_unit(snap, "res", 1, Vector2(-1000, -1000))
	snap.units.res.status = GameStateData.UnitStatus.IN_RESERVES
	var objectives = []
	for o in objs:
		objectives.append(o.position)
	var terms := {}
	AIDecisionMaker._score_reserves_deployment(snap.units.res, "res", "deep_strike", objectives, {}, snap, 1, 2, terms)
	var open_one = AIDecisionMaker.RESERVE_DEPLOY_OPEN_OBJ * clampf(6.0 / 6.0, 0.5, 2.0)
	print("  arrive_objectives = %.2f (one open objective's base = %.2f)" % [float(terms.get("arrive_objectives", 0.0)), open_one])
	_assert(float(terms.get("arrive_objectives", 0.0)) < open_one * 2.0, "four open objectives do not add four bonuses")
	_assert(float(terms.get("arrive_objectives", 0.0)) >= open_one - 0.01, "the best open objective still counts")

func test_race_counts_other_objective_enemies_at_half() -> void:
	print("\n--- RACE-1b ---")
	AIDecisionMaker._primary_awareness_p2 = {}
	var snap = _snapshot([{"id": "obj_a", "position": NML, "zone": "no_mans_land"},
		{"id": "obj_b", "position": NML_B, "zone": "no_mans_land"}])
	# Enemy sits 1 move from obj_b and 2 moves from obj_a.
	_add_unit(snap, "them", 1, NML_B + Vector2(0, -8.0 * 40.0), 100, 2)
	var friendlies = {}
	var enemies = {"them": snap.units.them}
	var evals = AIDecisionMaker._evaluate_all_objectives(snap, [NML, NML_B], 2, enemies, friendlies, 2)
	var arr_a: Array = []
	for e in evals:
		if e.id == "obj_a":
			arr_a = e.enemy_arrivals
	_assert(arr_a.size() == 1 and not arr_a[0].get("nearest", true), "the enemy is listed for obj_a, flagged as nearer another objective")
