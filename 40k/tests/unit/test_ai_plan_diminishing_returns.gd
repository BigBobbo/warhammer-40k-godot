extends SceneTree

# DIM-RETURNS: the movement plan re-prices each NEW objective as if the ones it
# is already taking were held, and does not send a unit to an objective that
# would then add almost no primary VP (15 VP/turn cap, flat "hold at least one"
# awards). Raised by the LLM-critic review (2026-10-28): units were spread one
# per objective across the board for objectives that scored nothing extra.
#
# Board: P2 holds its home objective with a unit that is not moving this phase;
# four movable P2 units each stand 8" from their own free non-home objective.
# Run with: godot --headless --path . -s tests/unit/test_ai_plan_diminishing_returns.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

const MOVABLE := ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]
const HOME := Vector2(880, 2200)
const NML := [Vector2(300, 1200), Vector2(700, 1200), Vector2(1100, 1200), Vector2(1500, 1200)]

# Battlefield Dominance (PrimaryMissionData11e): 3/objective + 2/non-home while home is held
const BD_RULES = [
	{"when": "command", "type": "per_objective", "vp_per": 3, "exclude_home": false, "rounds": [2, 5]},
	{"when": "command", "type": "per_objective", "vp_per": 2, "exclude_home": true, "require_hold_home": true, "rounds": [2, 5]},
]
# Meatgrinder's Command-phase objective award: flat 4 VP for >= 1 non-home objective
const FLAT_RULES = [
	{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4, "rounds": [2, 5]},
]

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== Plan diminishing returns (DIM-RETURNS) ===\n")
	test_per_objective_card_stops_at_cap()
	test_flat_card_takes_one()
	test_no_card_info_spreads_as_before()
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
	var objs = [{"id": "obj_home_2", "position": HOME, "zone": "player2"}]
	for i in range(NML.size()):
		objs.append({"id": "obj_nml_%d" % (i + 1), "position": NML[i], "zone": "no_mans_land"})
	return {"battle_round": 2, "meta": {"battle_round": 2},
		"board": {"objectives": objs, "terrain_features": []}, "units": {}}

func _add_unit(snapshot: Dictionary, unit_id: String, owner: int, pos: Vector2) -> void:
	var models = []
	for i in range(3):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 40,
			"base_type": "circular", "base_dimensions": {},
			"position": Vector2(pos.x + (i - 1) * 50, pos.y), "wounds": 3, "current_wounds": 3})
	snapshot.units[unit_id] = {
		"owner": owner, "status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"name": unit_id, "stats": {"move": 8, "toughness": 6, "save": 2, "wounds": 3,
			"leadership": 6, "objective_control": 2}, "keywords": ["INFANTRY"], "weapons": []},
		"models": models, "flags": {}}

func _plan(rules: Array) -> Dictionary:
	AIDecisionMaker._primary_awareness_p2 = {"card_name": "test", "vp_rules": rules} if not rules.is_empty() else {}
	AIDecisionMaker._secondary_awareness_p2 = {}
	var snap = _snapshot()
	_add_unit(snap, "home_holder", 2, HOME)
	var movable = {}
	for i in range(NML.size()):
		var uid = "u%d" % (i + 1)
		_add_unit(snap, uid, 2, NML[i] + Vector2(0, 8.0 * 40.0))
		movable[uid] = MOVABLE
	var friendlies = {}
	for uid in snap.units:
		friendlies[uid] = snap.units[uid]
	var objectives = [HOME] + NML
	var evals = AIDecisionMaker._evaluate_all_objectives(snap, objectives, 2, {}, friendlies, 2)
	return AIDecisionMaker._assign_units_to_objectives(snap, movable, evals, objectives, {}, friendlies, 2, 2)

func _captured(plan: Dictionary) -> Array:
	var objs: Array = []
	for uid in plan:
		var a = plan[uid]
		if a.get("assign_pass", "") == "capture" and str(a.objective_id).begins_with("obj_nml") and not (a.objective_id in objs):
			objs.append(a.objective_id)
	return objs

func _notes(plan: Dictionary) -> Array:
	var out: Array = []
	for uid in plan:
		if plan[uid].has("coordination_note"):
			out.append(str(plan[uid].coordination_note))
	return out

func test_per_objective_card_stops_at_cap() -> void:
	print("\n--- Battlefield Dominance: home + 3 non-home reaches the 15 VP cap ---")
	var plan = _plan(BD_RULES)
	var caps = _captured(plan)
	print("  captured: %s  notes: %s" % [str(caps), str(_notes(plan))])
	for uid in plan:
		print("  %s: %s %s pass=%s reason=%s" % [uid, plan[uid].get("action",""), plan[uid].get("objective_id",""), plan[uid].get("assign_pass",""), plan[uid].get("reason","")])
	_assert(caps.size() == 3, "takes 3 non-home objectives (13 -> 15 VP), not the 4th that adds 0 (got %d)" % caps.size())
	var noted := false
	for n in _notes(plan):
		if "adds only" in n:
			noted = true
	_assert(noted, "the unit left out says why (diminishing returns)")

func test_flat_card_takes_one() -> void:
	print("\n--- flat 'hold >= 1 non-home' card: one objective scores ---")
	var plan = _plan(FLAT_RULES)
	var caps = _captured(plan)
	print("  captured: %s" % str(caps))
	_assert(caps.size() == 1, "takes exactly 1 non-home objective on a flat card (got %d)" % caps.size())

func test_no_card_info_spreads_as_before() -> void:
	print("\n--- no primary info: the plan is unchanged ---")
	var plan = _plan([])
	var caps = _captured(plan)
	_assert(caps.size() == 4, "without card info every free objective is still taken (got %d)" % caps.size())
