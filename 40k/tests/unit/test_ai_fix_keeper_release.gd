extends SceneTree

# KEEPER-RELEASE (FIX_KEEPER_RELEASE): the sole keeper of our HOME objective
# leaves it for its best objective elsewhere when holding pays nothing before
# the enemy can threaten it — our primary card counts home in none of its rules
# (every hold rule excludes home), no enemy unit can be in range of it by the
# end of the enemy's next turn (on-board reach, reserves that can arrive), and
# another of our units can stand on it within one move. LLM-critic cluster
# keeper_release (value-checked, 2026-10-30): going first in round 1, a
# Custodian Guard unit idled a whole turn on a home objective the
# Reconnaissance card does not pay for while the Orks were 30" away (sending it
# forward measured +8.0 VP [3.4, 12.6] over 12 rollouts). Guardrail: a home
# objective the card does pay for (Destroyer's Wrath hold_more), or enemy
# reserves that arrive in the enemy's next turn, keep the keeper.
# Run with: godot --headless --path 40k -s tests/unit/test_ai_fix_keeper_release.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

const MOVABLE := ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]
const PX := 40.0  # pixels per inch
const HOME := Vector2(510, 340)      # our home objective (player 1 zone)
const NML := Vector2(890, 560)       # a no man's land objective ~11" away
const FAR_NML := Vector2(1370, 660)  # a no man's land objective ~23" away (an Advance trip)
const ENEMY_HOME := Vector2(1250, 2060)

# Reconnaissance Sweep: table quarters, kills, and hold_min that excludes home.
const RECON_RULES := [
	{"type": "quarters", "min": 3, "vp": 3, "when": "eot"},
	{"type": "destroyed_per_unit", "vp_per": 1, "when": "eot"},
	{"type": "hold_min", "exclude_home": true, "min": 1, "vp": 3, "when": "command", "rounds": [2, 5]},
]
# Purge and Secure: every objective rule excludes home.
const PURGE_RULES := [
	{"type": "destroyed_started_on_objective", "vp": 3, "when": "eot"},
	{"type": "per_objective", "exclude_home": true, "vp_per": 4, "when": "command", "rounds": [2, 5]},
	{"type": "hold_new", "exclude_home": true, "vp": 3, "when": "eot", "rounds": [2, 5]},
]
# Destroyer's Wrath: hold_more counts every objective, home included.
const WRATH_RULES := [
	{"type": "destroyed_min", "min": 1, "vp": 3, "when": "eot"},
	{"type": "hold_min", "exclude_home": true, "min": 1, "vp": 4, "when": "command", "rounds": [2, 5]},
	{"type": "hold_more", "vp": 6, "when": "command", "rounds": [2, 5]},
]

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== Sole keeper of a home objective that pays nothing (KEEPER-RELEASE) ===\n")
	AIDecisionMaker._config_overrides["FIX_KEEPER_RELEASE"] = 1.0
	test_keeper_goes_forward_when_home_pays_nothing()
	test_other_units_keep_their_plan()
	test_keeper_holds_when_the_backup_is_sent_elsewhere()
	test_keeper_advances_on_a_long_trip_alone()
	test_keeper_joining_a_quicker_unit_makes_a_normal_move()
	test_keeper_holds_when_primary_pays_for_home()
	test_keeper_holds_when_enemy_reserves_arrive_next_turn()
	test_round_one_reserves_do_not_hold_it_back()
	test_keeper_holds_when_reserve_can_arrive_in_round_one()
	test_keeper_holds_when_enemy_can_reach_home()
	test_keeper_holds_without_a_unit_to_retake_home()
	test_fragile_keeper_holds()
	test_keeper_with_a_plan_order_to_hold_home_holds()
	test_param_zero_restores_base()
	AIDecisionMaker._config_overrides.erase("FIX_KEEPER_RELEASE")
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func _snapshot(first_turn_player: int = 1, nml_pos: Vector2 = NML) -> Dictionary:
	return {"battle_round": 1, "meta": {"battle_round": 1, "first_turn_player": first_turn_player},
		"board": {"objectives": [
			{"id": "obj_home_1", "position": HOME, "zone": "player1"},
			{"id": "obj_nml_1", "position": nml_pos, "zone": "no_mans_land"},
			{"id": "obj_home_2", "position": ENEMY_HOME, "zone": "player2"},
		], "terrain_features": []}, "units": {}}

# `n` models (OC `oc` each) whose centroid is at `pos`.
func _add_unit(snapshot: Dictionary, unit_id: String, owner: int, pos: Vector2, n: int,
		toughness: int, wounds: int, oc: int, move: int, points: int,
		status: int = GameStateData.UnitStatus.DEPLOYED) -> void:
	var models = []
	for i in range(n):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 40,
			"base_type": "circular", "base_dimensions": {},
			"position": Vector2(pos.x + (i - (n - 1) / 2.0) * 45.0, pos.y), "wounds": wounds, "current_wounds": wounds})
	snapshot.units[unit_id] = {
		"id": unit_id, "owner": owner, "status": status,
		"meta": {"name": unit_id, "points": points, "stats": {"move": move, "toughness": toughness, "save": 2,
			"wounds": wounds, "leadership": 6, "objective_control": oc}, "keywords": ["INFANTRY"], "weapons": []},
		"models": models, "flags": {}}

# The s7437 shape: a 240 pt Custodian Guard unit on home, a 45 pt squad 10"
# away (it can step onto home in one move), the enemy army 40"+ away.
func _board(first_turn_player: int = 1, nml_pos: Vector2 = NML) -> Dictionary:
	var snap = _snapshot(first_turn_player, nml_pos)
	_add_unit(snap, "keeper", 1, HOME, 3, 7, 5, 3, 8, 240)
	_add_unit(snap, "backup", 1, HOME + Vector2(-300, -250), 4, 3, 1, 2, 7, 45)
	_add_unit(snap, "orks", 2, ENEMY_HOME, 10, 5, 1, 2, 6, 80)
	return snap

func _plan(snap: Dictionary, movable_ids: Array, rules: Array) -> Dictionary:
	AIDecisionMaker._primary_awareness_p1 = {"card_name": "test", "active_rules": rules.size(), "vp_rules": rules.duplicate(true),
		"objective_pressure": 0.0, "enemy_home_bonus": 0.0, "central_bonus": 0.0, "hold_home_required": false,
		"kill_pressure": false, "quarters": false}
	AIDecisionMaker._secondary_awareness_p1 = {}
	var friendlies = {}
	var enemies = {}
	var movable = {}
	for uid in snap.units:
		var u = snap.units[uid]
		if int(u.owner) == 1:
			friendlies[uid] = u
		elif int(u.status) != GameStateData.UnitStatus.IN_RESERVES:
			enemies[uid] = u
	for uid in movable_ids:
		movable[uid] = MOVABLE
	var objectives = []
	for o in snap.board.objectives:
		objectives.append(o.position)
	var evals = AIDecisionMaker._evaluate_all_objectives(snap, objectives, 1, enemies, friendlies, 1)
	var plan = AIDecisionMaker._assign_units_to_objectives(snap, movable, evals, objectives, enemies, friendlies, 1, 1)
	for uid in plan:
		print("  %s: %s %s [%s] (%s)" % [uid, plan[uid].get("action", ""), plan[uid].get("objective_id", ""),
			plan[uid].get("assign_pass", ""), str(plan[uid].get("reason", "")).substr(0, 110)])
	for c in AIDecisionMaker._last_movement_candidates.get("keeper", []):
		print("    keeper candidate %s %s score %.1f" % [c.get("action", ""), c.get("objective_id", ""), float(c.get("score", 0.0))])
	AIDecisionMaker._primary_awareness_p1 = {}
	return plan

func _holds_home(plan: Dictionary) -> bool:
	var a: Dictionary = plan.get("keeper", {})
	return str(a.get("objective_id", "")) == "obj_home_1" and str(a.get("action", "")) == "hold"

func _goes_forward(plan: Dictionary) -> bool:
	var a: Dictionary = plan.get("keeper", {})
	return str(a.get("objective_id", "")) == "obj_nml_1" and str(a.get("action", "")) in ["move", "advance"]

func test_keeper_goes_forward_when_home_pays_nothing() -> void:
	print("\n--- going first, round 1: home pays nothing (Reconnaissance), enemy 40\"+ away ---")
	var plan = _plan(_board(), ["keeper"], RECON_RULES)
	_assert(_goes_forward(plan), "the keeper leaves home for obj_nml_1 (it scores far more there)")
	_assert(str(plan.get("keeper", {}).get("assign_pass", "")) == "keeper_release", "the plan says the keeper was released (%s)" % str(plan.get("keeper", {}).get("assign_pass", "")))
	_assert(str(plan.get("keeper", {}).get("coordination_note", "")).begins_with("leaving obj_home_1"),
		"its card says why (%s)" % str(plan.get("keeper", {}).get("coordination_note", "")))

func test_other_units_keep_their_plan() -> void:
	print("\n--- a second unit (runner) moves this phase: its plan is the same with the fix on and off ---")
	var snap_on = _board()
	_add_unit(snap_on, "runner", 1, HOME + Vector2(100, 700), 3, 6, 3, 2, 6, 150)
	var on_plan = _plan(snap_on, ["keeper", "runner"], RECON_RULES)
	AIDecisionMaker._config_overrides["FIX_KEEPER_RELEASE"] = 0.0
	var snap_off = _board()
	_add_unit(snap_off, "runner", 1, HOME + Vector2(100, 700), 3, 6, 3, 2, 6, 150)
	var off_plan = _plan(snap_off, ["keeper", "runner"], RECON_RULES)
	AIDecisionMaker._config_overrides["FIX_KEEPER_RELEASE"] = 1.0
	var on_r: Dictionary = on_plan.get("runner", {})
	var off_r: Dictionary = off_plan.get("runner", {})
	_assert(str(on_r.get("objective_id", "")) == str(off_r.get("objective_id", "")) and str(on_r.get("action", "")) == str(off_r.get("action", "")),
		"runner: %s %s with the fix, %s %s without" % [on_r.get("action", ""), on_r.get("objective_id", ""), off_r.get("action", ""), off_r.get("objective_id", "")])
	_assert(_goes_forward(on_plan), "the keeper still goes forward (%s %s)" % [on_plan.get("keeper", {}).get("action", ""), on_plan.get("keeper", {}).get("objective_id", "")])
	if str(on_r.get("objective_id", "")) == "obj_nml_1":
		_assert(str(on_plan.get("keeper", {}).get("reason", "")).begins_with("joining runner"),
			"it joins the runner the plan already sends there (%s)" % str(on_plan.get("keeper", {}).get("reason", "")))

func test_keeper_holds_when_the_backup_is_sent_elsewhere() -> void:
	print("\n--- the only unit near home moves this phase and the plan sends it to obj_nml_1 ---")
	var plan = _plan(_board(), ["keeper", "backup"], RECON_RULES)
	_assert(str(plan.get("backup", {}).get("objective_id", "")) == "obj_nml_1", "the backup squad takes obj_nml_1 (%s)" % str(plan.get("backup", {}).get("objective_id", "")))
	_assert(_holds_home(plan), "with nobody left to step back onto home, the keeper holds")

func test_keeper_advances_on_a_long_trip_alone() -> void:
	print("\n--- Purge and Secure, obj_nml_1 23\" away and nobody else going: the keeper captures it ---")
	var plan = _plan(_board(1, FAR_NML), ["keeper"], PURGE_RULES)
	_assert(_goes_forward(plan), "the keeper leaves home for the far obj_nml_1 (%s %s)" % [
		plan.get("keeper", {}).get("action", ""), plan.get("keeper", {}).get("objective_id", "")])
	_assert(str(plan.get("keeper", {}).get("action", "")) == "advance",
		"capturing it alone it Advances to arrive a turn sooner, like any long trip (RACE-1)")

func test_keeper_joining_a_quicker_unit_makes_a_normal_move() -> void:
	print("\n--- same, but the plan sends a unit that gets to obj_nml_1 first ---")
	var snap = _board(1, FAR_NML)
	_add_unit(snap, "runner", 1, FAR_NML + Vector2(-200, 300), 3, 6, 3, 2, 6, 150)
	var plan = _plan(snap, ["keeper", "runner"], PURGE_RULES)
	_assert(str(plan.get("runner", {}).get("objective_id", "")) == "obj_nml_1", "the runner takes obj_nml_1 (%s)" % str(plan.get("runner", {}).get("objective_id", "")))
	_assert(_goes_forward(plan), "the keeper still leaves home for obj_nml_1")
	_assert(str(plan.get("keeper", {}).get("action", "")) == "move",
		"joining a unit that arrives first, it makes a Normal move — arriving sooner gains nothing (%s)" % str(plan.get("keeper", {}).get("action", "")))

func test_keeper_holds_when_primary_pays_for_home() -> void:
	print("\n--- same board, Destroyer's Wrath: hold_more counts home ---")
	var plan = _plan(_board(), ["keeper"], WRATH_RULES)
	_assert(_holds_home(plan), "a home objective the primary pays for keeps its keeper")

func test_keeper_holds_when_enemy_reserves_arrive_next_turn() -> void:
	print("\n--- going second (the enemy's next turn is round 2), enemy has a unit in reserves ---")
	var snap = _board(2)
	_add_unit(snap, "stormboyz", 2, Vector2.ZERO, 10, 5, 1, 1, 12, 140, GameStateData.UnitStatus.IN_RESERVES)
	var plan = _plan(snap, ["keeper"], RECON_RULES)
	_assert(_holds_home(plan), "reserves that can deep strike onto home next turn keep the keeper")

func test_round_one_reserves_do_not_hold_it_back() -> void:
	print("\n--- going first in round 1, enemy has a unit in reserves (it cannot arrive in round 1) ---")
	var snap = _board(1)
	_add_unit(snap, "stormboyz", 2, Vector2.ZERO, 10, 5, 1, 1, 12, 140, GameStateData.UnitStatus.IN_RESERVES)
	var plan = _plan(snap, ["keeper"], RECON_RULES)
	_assert(_goes_forward(plan), "round-1 reserves cannot arrive in the enemy's round-1 turn (15.07): the keeper goes")

func test_keeper_holds_when_reserve_can_arrive_in_round_one() -> void:
	print("\n--- going first in round 1, the enemy reserve carries an enhancement (e.g. Lightning Descent) ---")
	var snap = _board(1)
	_add_unit(snap, "allarus", 2, Vector2.ZERO, 3, 8, 6, 2, 7, 270, GameStateData.UnitStatus.IN_RESERVES)
	snap.units["allarus"].meta["enhancements"] = ["Lightning Descent"]
	var plan = _plan(snap, ["keeper"], RECON_RULES)
	_assert(_holds_home(plan), "a reserve unit a rule may bring in round 1 keeps the keeper")

func test_keeper_holds_when_enemy_can_reach_home() -> void:
	print("\n--- an enemy M12 unit 26\" from home (move + charge + pile-in/consolidate reach it) ---")
	var snap = _board()
	_add_unit(snap, "bikers", 2, HOME + Vector2(0, 26.0 * PX), 3, 6, 3, 2, 12, 140)
	var plan = _plan(snap, ["keeper"], RECON_RULES)
	_assert(_holds_home(plan), "an enemy that can be on home by the end of its next turn keeps the keeper")

func test_keeper_holds_without_a_unit_to_retake_home() -> void:
	print("\n--- no other unit within one move of home ---")
	var snap = _board()
	snap.units.erase("backup")
	_add_unit(snap, "backup", 1, HOME + Vector2(0, 20.0 * PX), 4, 3, 1, 2, 7, 45)
	var plan = _plan(snap, ["keeper"], RECON_RULES)
	_assert(_holds_home(plan), "with nobody to step back onto home, the keeper holds")

func test_fragile_keeper_holds() -> void:
	print("\n--- the keeper is a fragile squad (T3, 1 wound per model) ---")
	var snap = _board()
	snap.units.erase("keeper")
	_add_unit(snap, "keeper", 1, HOME, 4, 3, 1, 2, 7, 45)
	var plan = _plan(snap, ["keeper"], RECON_RULES)
	_assert(_holds_home(plan), "a fragile keeper (KEEPER-PICK's natural keeper) holds")

func test_keeper_with_a_plan_order_to_hold_home_holds() -> void:
	print("\n--- an authored plan orders the keeper to hold home (PM-3 HOLD_OBJECTIVE earmark) ---")
	# The earmark's +8 hold bonus is set to 0 so the scores are the ones that
	# release the keeper above: only the plan's order keeps it.
	AIDecisionMaker._config_overrides["PLAN_EARMARK_HOLD_BONUS"] = 0.0
	AIDecisionMaker.set_player_plan(1, {"format": "wh40k_ai_plan", "version": 1, "name": "Keeper Hold Test Plan",
		"description": "", "author": "test", "keys": {},
		"deployment": {"order": [], "placements": [], "reserves": [], "embarkations": [], "attachments": []},
		"earmarks": [{"unit": "keeper", "verb": "HOLD_OBJECTIVE", "target": "obj_home_1"}],
		"profile_fragment": {"parameters": {}, "rules": []}})
	var plan = _plan(_board(), ["keeper"], RECON_RULES)
	AIDecisionMaker.clear_player_plan(1)
	AIDecisionMaker._config_overrides.erase("PLAN_EARMARK_HOLD_BONUS")
	_assert(_holds_home(plan), "the keeper keeps the plan's order to hold home")

func test_param_zero_restores_base() -> void:
	print("\n--- FIX_KEEPER_RELEASE = 0 ---")
	AIDecisionMaker._config_overrides["FIX_KEEPER_RELEASE"] = 0.0
	var plan = _plan(_board(), ["keeper"], RECON_RULES)
	AIDecisionMaker._config_overrides["FIX_KEEPER_RELEASE"] = 1.0
	_assert(_holds_home(plan), "with the fix off the sole keeper holds home as before")
