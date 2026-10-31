extends SceneTree

# LONE-FLIP (FIX_LONE_FLIP): on an objective we do not control, a unit that
# HOLDS (remains stationary) fills none of the OC need — the need (enemy OC -
# friendly OC + 1) already counts its models in range. Pass 1 subtracted the
# holder's whole unit OC again, so a squad with one model in range of an
# enemy-held centre marked it "already taken" and the next unit was sent to
# flip a far stronger objective alone. LLM-critic cluster lone_flip
# (value-checked, 2026-10-30): s7454 r3, Custodian Guard Gamma sent to flip a
# 14-OC objective while the centre (5 vs 8 OC) read as taken; Advancing to the
# centre measured +21.5 VP over 36 seeds.
# Run with: godot --headless --path 40k -s tests/unit/test_ai_fix_lone_flip.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

const MOVABLE := ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]
const PX := 40.0  # pixels per inch
const OBJ_X := Vector2(880, 1200)    # the enemy-held objective
const OBJ_SIDE := Vector2(200, 1700) # a quiet objective on our side, nobody near it

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== A holder already in range fills no need (LONE-FLIP) ===\n")
	AIDecisionMaker._config_overrides["FIX_LONE_FLIP"] = 1.0
	test_partial_holder_does_not_mark_enemy_objective_taken()
	test_held_objective_ledger_unchanged()
	test_contested_objective_gets_a_runner()
	test_two_co_holders_both_hold_without_consuming()
	test_attack_conversion_reopens_only_in_range_oc()
	test_holder_without_oc_in_range_keeps_base_ledger()
	test_param_zero_restores_base()
	AIDecisionMaker._config_overrides.erase("FIX_LONE_FLIP")
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
	var objs = [{"id": "obj_x", "position": OBJ_X, "zone": "no_mans_land"},
		{"id": "obj_side", "position": OBJ_SIDE, "zone": "no_mans_land"}]
	return {"battle_round": 3, "meta": {"battle_round": 3},
		"board": {"objectives": objs, "terrain_features": []}, "units": {}}

# Durable models (T6, 3 wounds, OC 2) at the given positions.
func _add_unit(snapshot: Dictionary, unit_id: String, owner: int, positions: Array, move: int = 6,
		weapons: Array = [], oc: int = 2) -> void:
	var models = []
	for i in range(positions.size()):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 32,
			"base_type": "circular", "base_dimensions": {},
			"position": positions[i], "wounds": 3, "current_wounds": 3})
	snapshot.units[unit_id] = {
		"id": unit_id, "owner": owner, "status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"name": unit_id, "points": 200, "stats": {"move": move, "toughness": 6, "save": 3,
			"wounds": 3, "leadership": 6, "objective_control": oc}, "keywords": ["INFANTRY"], "weapons": weapons},
		"models": models, "flags": {}}

func _row(center: Vector2, n: int) -> Array:
	var out = []
	for i in range(n):
		out.append(Vector2(center.x + (i - (n - 1) / 2.0) * 45.0, center.y))
	return out

# Enemy 4-model squad on obj_x (8 OC); our "holder" squad with ONE model in
# range (2 OC there, 10 OC in all); our "runner" squad 10" below obj_x.
func _board(enemies: Dictionary) -> Dictionary:
	var snap = _snapshot()
	_add_unit(snap, "theirs", 1, _row(OBJ_X + Vector2(0, -1.0 * PX), 4))
	enemies["theirs"] = snap.units["theirs"]
	var holder_pos = [OBJ_X + Vector2(-3.0 * PX, 1.0 * PX)]
	for i in range(4):
		holder_pos.append(OBJ_X + Vector2(-3.0 * PX - (i + 1) * 1.9 * PX, 1.0 * PX))
	_add_unit(snap, "holder", 2, holder_pos)
	_add_unit(snap, "runner", 2, _row(OBJ_X + Vector2(0, 10.0 * PX), 4))
	return snap

func _friendlies(snap: Dictionary) -> Dictionary:
	var friendlies = {}
	for uid in snap.units:
		if int(snap.units[uid].owner) == 2:
			friendlies[uid] = snap.units[uid]
	return friendlies

func _evals(snap: Dictionary, enemies: Dictionary) -> Array:
	var objectives = []
	for o in snap.board.objectives:
		objectives.append(o.position)
	return AIDecisionMaker._evaluate_all_objectives(snap, objectives, 2, enemies, _friendlies(snap), 3)

func _plan(snap: Dictionary, movable_ids: Array, enemies: Dictionary, battle_round: int = 3) -> Dictionary:
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
	var evals = AIDecisionMaker._evaluate_all_objectives(snap, objectives, 2, enemies, friendlies, battle_round)
	for ev in evals:
		print("  eval %s: state %s, friendly %d, enemy %d" % [ev.id, ev.state, int(ev.friendly_oc), int(ev.enemy_oc)])
	var plan = AIDecisionMaker._assign_units_to_objectives(snap, movable, evals, objectives, enemies, friendlies, 2, battle_round)
	for uid in plan:
		print("  %s: %s %s [%s] (%s)" % [uid, plan[uid].get("action", ""), plan[uid].get("objective_id", ""),
			plan[uid].get("assign_pass", ""), str(plan[uid].get("reason", "")).substr(0, 110)])
	return plan

func _goes_to(plan: Dictionary, uid: String, oid: String) -> bool:
	var a: Dictionary = plan.get(uid, {})
	return str(a.get("objective_id", "")) == oid and str(a.get("action", "")) in ["move", "advance"]

func test_partial_holder_does_not_mark_enemy_objective_taken() -> void:
	print("\n--- enemy 8 OC on obj_x, our holder has 1 model (2 OC) in range, runner 10\" out ---")
	var enemies = {}
	var snap = _board(enemies)
	var plan = _plan(snap, ["holder", "runner"], enemies)
	_assert(str(plan.get("holder", {}).get("action", "")) == "hold" and str(plan.get("holder", {}).get("objective_id", "")) == "obj_x",
		"the holder holds obj_x")
	_assert(int(plan.get("holder", {}).get("oc_consumed", -1)) == 0,
		"a stationary holder fills none of the need (oc_consumed %d)" % int(plan.get("holder", {}).get("oc_consumed", -1)))
	_assert(_goes_to(plan, "runner", "obj_x"),
		"obj_x (2 vs 8 OC) is not 'already taken' — the runner goes there, not to obj_side")

func test_held_objective_ledger_unchanged() -> void:
	print("\n--- obj_x held by us (3 models, 6 OC), enemy 8 OC one move away: the holder fills the need as before ---")
	var enemies = {}
	var snap = _snapshot()
	_add_unit(snap, "holder", 2, _row(OBJ_X, 3))
	_add_unit(snap, "theirs", 1, _row(OBJ_X + Vector2(0, -9.0 * PX), 4))
	enemies["theirs"] = snap.units["theirs"]
	_add_unit(snap, "free", 2, _row(OBJ_X + Vector2(0, 10.0 * PX), 2))
	var evals = _evals(snap, enemies)
	var need := 0
	for ev in evals:
		if ev.id == "obj_x":
			need = AIDecisionMaker._initial_objective_oc_needs(evals, _friendlies(snap)).get("obj_x", 0)
	var plan = _plan(snap, ["holder", "free"], enemies)
	_assert(need > 0, "the enemy one move away makes a projected need on our held objective (%d)" % need)
	_assert(str(plan.get("holder", {}).get("action", "")) == "hold", "the holder holds its own objective")
	_assert(int(plan.get("holder", {}).get("oc_consumed", -1)) == mini(6, need),
		"on a held objective the holder still consumes min(unit OC, need) (%d)" % int(plan.get("holder", {}).get("oc_consumed", -1)))
	_assert(not _goes_to(plan, "free", "obj_x"), "the free unit is not sent to the held objective")

func test_contested_objective_gets_a_runner() -> void:
	print("\n--- contested obj_x (our holder 2 OC in range vs enemy 2 OC): a free unit is still sent ---")
	var enemies = {}
	var snap = _snapshot()
	_add_unit(snap, "theirs", 1, [OBJ_X + Vector2(0, -1.0 * PX)])
	enemies["theirs"] = snap.units["theirs"]
	var holder_pos = [OBJ_X + Vector2(-3.0 * PX, 1.0 * PX)]
	for i in range(4):
		holder_pos.append(OBJ_X + Vector2(-3.0 * PX - (i + 1) * 1.9 * PX, 1.0 * PX))
	_add_unit(snap, "holder", 2, holder_pos)
	_add_unit(snap, "runner", 2, _row(OBJ_X + Vector2(0, 10.0 * PX), 2))
	var plan = _plan(snap, ["holder", "runner"], enemies)
	_assert(int(plan.get("holder", {}).get("oc_consumed", -1)) == 0,
		"the contested holder consumes nothing (%d)" % int(plan.get("holder", {}).get("oc_consumed", -1)))
	_assert(_goes_to(plan, "runner", "obj_x"), "the tie needs a unit — the runner goes to obj_x")

func test_two_co_holders_both_hold_without_consuming() -> void:
	print("\n--- enemy-held obj_x, two of our squads each with one model in range ---")
	var enemies = {}
	var snap = _board(enemies)
	var co_pos = [OBJ_X + Vector2(3.0 * PX, 1.0 * PX)]
	for i in range(4):
		co_pos.append(OBJ_X + Vector2(3.0 * PX + (i + 1) * 1.9 * PX, 1.0 * PX))
	_add_unit(snap, "coholder", 2, co_pos)
	var plan = _plan(snap, ["holder", "coholder"], enemies)
	for uid in ["holder", "coholder"]:
		_assert(str(plan.get(uid, {}).get("action", "")) == "hold" and str(plan.get(uid, {}).get("objective_id", "")) == "obj_x"
			and int(plan.get(uid, {}).get("oc_consumed", -1)) == 0,
			"%s holds obj_x with oc_consumed 0 (%s, %d)" % [uid, str(plan.get(uid, {}).get("action", "")),
				int(plan.get(uid, {}).get("oc_consumed", -1))])

# Custodian Guard profile: guardian spear shooting (S4 A2 AP-1 D2) and melee
# (S7 A5 AP-2 D2) — a melee seeker.
const SPEAR := [
	{"name": "Guardian spear", "type": "Ranged", "range": "24", "attacks": "2", "ballistic_skill": "2",
		"strength": "4", "ap": "-1", "damage": "2", "special_rules": ""},
	{"name": "Guardian spear", "type": "Melee", "range": "Melee", "attacks": "5", "weapon_skill": "2",
		"strength": "7", "ap": "-2", "damage": "2", "special_rules": ""}]

# PASS 2.5: the partial holder (1 model in range, centroid ~7" from the marker)
# is a melee seeker 7" from the enemy on obj_x — it converts to ATTACK. Pass 2
# already filled the need with the runner (8 OC >= 7). Only the holder's 2 OC
# in range leaves, so the backfill needs one unit — not the base re-open of
# enemy 8 - (2 - 10) + 1 = 17 on top of the filled need, which pulls every spare.
func test_attack_conversion_reopens_only_in_range_oc() -> void:
	print("\n--- melee-seeker partial holder converts to ATTACK: COORD-4 re-opens only its in-range OC ---")
	var enemies = {}
	var snap = _board(enemies)
	snap.units["holder"].meta["weapons"] = SPEAR.duplicate(true)
	_add_unit(snap, "spare_a", 2, _row(OBJ_X + Vector2(-6.0 * PX, 12.0 * PX), 2))
	_add_unit(snap, "spare_b", 2, _row(OBJ_X + Vector2(6.0 * PX, 12.0 * PX), 2))
	_add_unit(snap, "spare_c", 2, _row(OBJ_X + Vector2(0, 14.0 * PX), 2))
	# MERGE (main OBJ-GAP-2): the chase gate now reads "on a contested
	# objective" per model (our holder's model AND the enemy's are in range),
	# so from round 2 on it keeps the holder on obj_x instead of converting it.
	# Round 1 has no contested-objective stay, so the conversion — and the
	# COORD-4 re-open this test is about — still happens.
	snap["battle_round"] = 1
	snap["meta"]["battle_round"] = 1
	var plan = _plan(snap, ["holder", "runner", "spare_a", "spare_b", "spare_c"], enemies, 1)
	_assert(str(plan.get("holder", {}).get("action", "")) == "attack", "the holder converts to ATTACK (%s)" % str(plan.get("holder", {}).get("action", "")))
	_assert(int(plan.get("holder", {}).get("oc_consumed", 0)) == 0, "the converted holder consumes no OC")
	# capture assignments (pass 2 + COORD-4 backfill); pass 3's support fallback is not the ledger
	var sent: Array = []
	for uid in ["runner", "spare_a", "spare_b", "spare_c"]:
		if _goes_to(plan, uid, "obj_x") and str(plan[uid].get("assign_pass", "")) == "capture":
			sent.append(uid)
	# need 7 (8 - 2 + 1): one 8-OC runner fills it; the 2 OC that leaves takes one 4-OC spare
	_assert(sent.size() <= 2, "at most one unit backfills the holder's 2 in-range OC (captures on obj_x: %s)" % str(sent))

# A battle-shocked holder has 0 OC in range, so friendly_oc does not count it:
# the zero-consumption rule does not apply and the ledger is the base one.
func test_holder_without_oc_in_range_keeps_base_ledger() -> void:
	print("\n--- battle-shocked holder on enemy-held obj_x (0 OC in range) ---")
	var enemies = {}
	var snap = _board(enemies)
	snap.units["holder"].flags["battle_shocked"] = true
	var plan = _plan(snap, ["holder", "runner"], enemies)
	_assert(str(plan.get("holder", {}).get("action", "")) == "hold" and int(plan.get("holder", {}).get("oc_consumed", 0)) > 0
		and not plan.get("holder", {}).get("lone_flip_hold", false),
		"a holder with no OC in range consumes OC as on the base (oc_consumed %d)" % int(plan.get("holder", {}).get("oc_consumed", 0)))

func test_param_zero_restores_base() -> void:
	print("\n--- FIX_LONE_FLIP = 0 ---")
	AIDecisionMaker._config_overrides["FIX_LONE_FLIP"] = 0.0
	var enemies = {}
	var snap = _board(enemies)
	var plan = _plan(snap, ["holder", "runner"], enemies)
	AIDecisionMaker._config_overrides["FIX_LONE_FLIP"] = 1.0
	_assert(not _goes_to(plan, "runner", "obj_x"),
		"with the fix off the holder's whole 10 OC fills the need and the runner goes elsewhere")
