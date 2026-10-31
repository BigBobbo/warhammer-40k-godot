extends SceneTree

# KEEPER-RELEASE (FIX_KEEPER_RELEASE): the sole keeper of our HOME objective
# leaves it for its best objective elsewhere when holding pays nothing before
# the enemy can threaten it — our primary card counts home in none of its rules
# (every hold rule excludes home), no enemy unit can be in range of it by the
# end of the enemy's next turn (on-board reach, reserves that can arrive), and
# another of our units can stand on it within one move and still can when the
# plan is done. LLM-critic cluster keeper_release (value-checked, 2026-10-30):
# going first in round 1, a Custodian Guard unit idled a whole turn on a home
# objective the Reconnaissance card does not pay for while the Orks were 30"
# away (sending it forward measured +8.0 VP [3.4, 12.6] over 12 rollouts).
# Guardrail: a home objective the card does pay for (Destroyer's Wrath
# hold_more), or enemy reserves that arrive in the enemy's next turn, keep the
# keeper.
#
# The release is applied after pass 3, so every other unit keeps its base
# plan. A keeper that joins a unit getting to its target first walks (Normal
# move) instead of RACE-1's Advance; that walk is the candidate it acts on and
# is recorded with (a Normal move's turns, race and score, the same numbers the
# planner's own loop gives a Normal move), and it must not be a trip the
# planner refuses outright (TOO-LATE, RACE-SKIP).
# Run with: godot --headless --path 40k -s tests/unit/test_ai_fix_keeper_release.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

const MOVABLE := ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]
const PX := 40.0  # pixels per inch
const HOME := Vector2(510, 340)      # our home objective (player 1 zone)
const NML := Vector2(890, 560)       # a no man's land objective ~11" away
const FAR_NML := Vector2(1370, 660)  # a no man's land objective ~23" away (an Advance trip)
const ENEMY_HOME := Vector2(1250, 2060)
const NML_2 := Vector2(300, 1200)    # a second no man's land objective (DIM-RETURNS board)

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
var _last_evals: Array = []     # the objective evaluations of the last _plan
var _last_kr: Dictionary = {}   # _keeper_release_check on the last plan's keeper (pass 1)

func _init():
	print("\n=== Sole keeper of a home objective that pays nothing (KEEPER-RELEASE) ===\n")
	AIDecisionMaker._config_overrides["FIX_KEEPER_RELEASE"] = 1.0
	test_keeper_goes_forward_when_home_pays_nothing()
	test_other_units_keep_their_plan()
	test_keeper_holds_when_the_backup_is_sent_elsewhere()
	test_keeper_holds_when_pass_3_moves_the_backup_away()
	test_keeper_advances_on_a_long_trip_alone()
	test_keeper_joining_a_quicker_unit_makes_a_normal_move()
	test_keeper_holds_when_its_walk_arrives_too_late()
	test_normal_pace_matches_the_planner()
	test_keeper_holds_when_dim_returns_skips_the_target()
	test_keeper_holds_when_primary_pays_for_home()
	test_keeper_holds_when_enemy_reserves_arrive_next_turn()
	test_round_one_reserves_do_not_hold_it_back()
	test_keeper_holds_when_reserve_can_arrive_in_round_one()
	test_keeper_holds_when_enemy_can_reach_home()
	test_melee_keeper_that_would_go_hunting_holds()
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

func _snapshot(first_turn_player: int = 1, nml_pos: Vector2 = NML, battle_round: int = 1, extra: Array = []) -> Dictionary:
	var objs = [
		{"id": "obj_home_1", "position": HOME, "zone": "player1"},
		{"id": "obj_nml_1", "position": nml_pos, "zone": "no_mans_land"},
		{"id": "obj_home_2", "position": ENEMY_HOME, "zone": "player2"},
	]
	for e in extra:
		objs.append(e)
	return {"battle_round": battle_round, "meta": {"battle_round": battle_round, "first_turn_player": first_turn_player},
		"board": {"objectives": objs, "terrain_features": []}, "units": {}}

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
func _board(first_turn_player: int = 1, nml_pos: Vector2 = NML, battle_round: int = 1, extra: Array = []) -> Dictionary:
	var snap = _snapshot(first_turn_player, nml_pos, battle_round, extra)
	_add_unit(snap, "keeper", 1, HOME, 3, 7, 5, 3, 8, 240)
	_add_unit(snap, "backup", 1, HOME + Vector2(-300, -250), 4, 3, 1, 2, 7, 45)
	_add_unit(snap, "orks", 2, ENEMY_HOME, 10, 5, 1, 2, 6, 80)
	return snap

func _plan(snap: Dictionary, movable_ids: Array, rules: Array, sec: Dictionary = {}) -> Dictionary:
	var battle_round := int(snap.get("battle_round", 1))
	AIDecisionMaker._primary_awareness_p1 = {"card_name": "test", "active_rules": rules.size(), "vp_rules": rules.duplicate(true),
		"objective_pressure": 0.0, "enemy_home_bonus": 0.0, "central_bonus": 0.0, "hold_home_required": false,
		"kill_pressure": false, "quarters": false}
	AIDecisionMaker._secondary_awareness_p1 = sec
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
	var evals = AIDecisionMaker._evaluate_all_objectives(snap, objectives, 1, enemies, friendlies, battle_round)
	_last_evals = evals
	var plan = AIDecisionMaker._assign_units_to_objectives(snap, movable, evals, objectives, enemies, friendlies, 1, battle_round)
	for uid in plan:
		print("  %s: %s %s [%s] (%s)" % [uid, plan[uid].get("action", ""), plan[uid].get("objective_id", ""),
			plan[uid].get("assign_pass", ""), str(plan[uid].get("reason", "")).substr(0, 110)])
	for c in AIDecisionMaker._last_movement_candidates.get("keeper", []):
		print("    keeper candidate %s %s score %.3f turns %d" % [c.get("action", ""), c.get("objective_id", ""),
			float(c.get("score", 0.0)), int(c.get("turns_to_reach", 0))])
	# Pass 1's verdict for the keeper's hold of obj_home_1 (the guard that kept
	# it, or a target), asked with the same card and candidates.
	_last_kr = {}
	var all_cands: Array = []
	var hold_cand: Dictionary = {}
	for uid in AIDecisionMaker._last_movement_candidates:
		for c in AIDecisionMaker._last_movement_candidates[uid]:
			all_cands.append(c)
			if str(uid) == "keeper" and c.get("already_on_obj", false) and str(c.objective_id) == "obj_home_1":
				hold_cand = c
	if not hold_cand.is_empty():
		_last_kr = _call_ai("_keeper_release_check", [snap, hold_cand, _eval("obj_home_1"), all_cands,
			enemies, 1, battle_round])
	AIDecisionMaker._primary_awareness_p1 = {}
	AIDecisionMaker._secondary_awareness_p1 = {}
	return plan

# The fix's helpers, called by name so this file also runs (and fails) against
# a copy of the AI without them ({} back there).
func _call_ai(fn: String, args: Array) -> Dictionary:
	var ai_script: Object = AIDecisionMaker
	var out = ai_script.callv(fn, args)
	return out if out is Dictionary else {}

func _eval(obj_id: String) -> Dictionary:
	for ev in _last_evals:
		if str(ev.get("id", "")) == obj_id:
			return ev
	return {}

func _holds_home(plan: Dictionary) -> bool:
	var a: Dictionary = plan.get("keeper", {})
	return str(a.get("objective_id", "")) == "obj_home_1" and str(a.get("action", "")) == "hold"

func _goes_forward(plan: Dictionary) -> bool:
	var a: Dictionary = plan.get("keeper", {})
	return str(a.get("objective_id", "")) == "obj_nml_1" and str(a.get("action", "")) in ["move", "advance"]

func _kept_by(text: String) -> bool:
	return str(_last_kr.get("kept", "")).find(text) >= 0

func _terms_sum(c: Dictionary) -> float:
	var s := 0.0
	for k in c.get("score_terms", {}):
		s += float(c.score_terms[k])
	return s

# The keeper's candidates for `obj_id` in the last plan, in record order.
func _keeper_cands(obj_id: String) -> Array:
	var out: Array = []
	for c in AIDecisionMaker._last_movement_candidates.get("keeper", []):
		if str(c.get("objective_id", "")) == obj_id:
			out.append(c)
	return out

# Same objective, same pace, same numbers (every score term included).
func _same_candidate(a: Dictionary, b: Dictionary) -> String:
	if a.is_empty() or b.is_empty():
		return "missing"
	if int(a.get("turns_to_reach", 0)) != int(b.get("turns_to_reach", 0)):
		return "turns %d vs %d" % [int(a.get("turns_to_reach", 0)), int(b.get("turns_to_reach", 0))]
	if absf(float(a.score) - float(b.score)) > 1e-6:
		return "score %.4f vs %.4f" % [float(a.score), float(b.score)]
	for k in ["race_lost", "race_enemy_oc", "race_army_oc"]:
		if a.get(k) != b.get(k):
			return "%s %s vs %s" % [k, str(a.get(k)), str(b.get(k))]
	var ta: Dictionary = a.get("score_terms", {})
	var tb: Dictionary = b.get("score_terms", {})
	for k in ta:
		if absf(float(ta[k]) - float(tb.get(k, 0.0))) > 1e-6:
			return "term %s %.4f vs %.4f" % [k, float(ta[k]), float(tb.get(k, 0.0))]
	for k in tb:
		if not ta.has(k) and absf(float(tb[k])) > 1e-6:
			return "term %s missing (%.4f)" % [k, float(tb[k])]
	return ""

func test_keeper_goes_forward_when_home_pays_nothing() -> void:
	print("\n--- going first, round 1: home pays nothing (Reconnaissance), enemy 40\"+ away ---")
	var plan = _plan(_board(), ["keeper"], RECON_RULES)
	_assert(_goes_forward(plan), "the keeper leaves home for obj_nml_1 (it scores far more there)")
	_assert(str(plan.get("keeper", {}).get("assign_pass", "")) == "keeper_release", "the plan says the keeper was released (%s)" % str(plan.get("keeper", {}).get("assign_pass", "")))
	_assert(str(plan.get("keeper", {}).get("coordination_note", "")).begins_with("leaving obj_home_1"),
		"its card says why (%s)" % str(plan.get("keeper", {}).get("coordination_note", "")))

func test_other_units_keep_their_plan() -> void:
	print("\n--- other units, one of them left to pass 3: every one has the same plan with the fix on and off ---")
	var on_plan := {}
	var off_plan := {}
	for fix in [1.0, 0.0]:
		AIDecisionMaker._config_overrides["FIX_KEEPER_RELEASE"] = fix
		var snap = _board()
		_add_unit(snap, "runner", 1, NML + Vector2(-100, 200), 3, 6, 3, 2, 6, 150)
		# a cheap slow squad no objective needs (obj_home_2 is TOO-LATE for
		# it): pass 3 places it — a deep-strike denial screen, as the enemy
		# has a unit in reserves (it cannot arrive in round 1)
		_add_unit(snap, "spare", 1, HOME + Vector2(150, -150), 5, 3, 1, 1, 4, 50)
		_add_unit(snap, "stormboyz", 2, Vector2.ZERO, 10, 5, 1, 1, 12, 140, GameStateData.UnitStatus.IN_RESERVES)
		var p = _plan(snap, ["keeper", "runner", "spare"], RECON_RULES)
		if fix > 0.5:
			on_plan = p
		else:
			off_plan = p
	AIDecisionMaker._config_overrides["FIX_KEEPER_RELEASE"] = 1.0
	_assert(_goes_forward(on_plan), "the keeper goes forward (%s %s)" % [on_plan.get("keeper", {}).get("action", ""), on_plan.get("keeper", {}).get("objective_id", "")])
	_assert(_holds_home(off_plan), "without the fix it holds home")
	var same := true
	var passes: Array = []
	for uid in off_plan:
		if uid == "keeper":
			continue
		var a: Dictionary = on_plan.get(uid, {})
		var b: Dictionary = off_plan[uid]
		passes.append("%s:%s" % [uid, b.get("assign_pass", "")])
		for k in ["objective_id", "action", "assign_pass", "objective_pos", "reason"]:
			if str(a.get(k, "")) != str(b.get(k, "")):
				same = false
				print("  differs: %s.%s %s vs %s" % [uid, k, str(a.get(k, "")), str(b.get(k, ""))])
	_assert(same and on_plan.size() == off_plan.size(), "every other unit's final assignment is the same (%s)" % ", ".join(passes))
	_assert(str(off_plan.get("spare", {}).get("assign_pass", "")) in ["screen_denial", "screen_protect", "corridor_block", "support", ""],
		"one of them is placed by pass 3 (%s)" % str(off_plan.get("spare", {}).get("assign_pass", "")))
	if str(on_plan.get("runner", {}).get("objective_id", "")) == "obj_nml_1":
		_assert(str(on_plan.get("keeper", {}).get("reason", "")).begins_with("joining runner"),
			"it joins the runner the plan already sends there (%s)" % str(on_plan.get("keeper", {}).get("reason", "")))

func test_keeper_holds_when_the_backup_is_sent_elsewhere() -> void:
	print("\n--- the only unit near home moves this phase and the plan sends it to obj_nml_1 ---")
	var plan = _plan(_board(), ["keeper", "backup"], RECON_RULES)
	_assert(str(plan.get("backup", {}).get("objective_id", "")) == "obj_nml_1", "the backup squad takes obj_nml_1 (%s)" % str(plan.get("backup", {}).get("objective_id", "")))
	_assert(_holds_home(plan), "with nobody left to step back onto home, the keeper holds")

func test_keeper_holds_when_pass_3_moves_the_backup_away() -> void:
	print("\n--- the backup has no objective (TOO-LATE) and pass 3 sends it to screen far from home ---")
	var snap = _board()
	_add_unit(snap, "runner", 1, NML + Vector2(-100, 200), 3, 6, 3, 2, 6, 150)
	snap.units["backup"].meta.stats["move"] = 5
	var plan = _plan(snap, ["keeper", "runner", "backup"], RECON_RULES)
	var b: Dictionary = plan.get("backup", {})
	var b_dest: Vector2 = b.get("objective_pos", Vector2.INF)
	var b_gap_in := (b_dest.distance_to(HOME) - 151.5) / PX if b_dest != Vector2.INF else -1.0
	_assert(str(b.get("action", "")) == "screen" and b_gap_in > 7.0,
		"pass 3 sends the backup to %s at %.1f\" from home's control range (more than its M5 + 2\")" % [str(b.get("objective_id", "")), b_gap_in])
	_assert(_last_kr.has("target"), "pass 1 had released the keeper (target %s)" % str(_last_kr.get("target", {}).get("objective_id", "-")))
	_assert(_holds_home(plan), "with the backup screening away from home in the finished plan, the keeper holds")

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
	var a: Dictionary = plan.get("keeper", {})
	_assert(str(plan.get("runner", {}).get("objective_id", "")) == "obj_nml_1", "the runner takes obj_nml_1 (%s)" % str(plan.get("runner", {}).get("objective_id", "")))
	_assert(_goes_forward(plan), "the keeper still leaves home for obj_nml_1")
	_assert(str(a.get("action", "")) == "move",
		"joining a unit that arrives first, it makes a Normal move (%s)" % str(a.get("action", "")))
	# The candidate it acts on is the Normal move: its record card is that
	# move's turns and score, the numbers the planner's own loop gives a Normal
	# move of this unit to this objective (MOVE_LONG_ADVANCE = 0).
	var cands := _keeper_cands("obj_nml_1")
	var walk: Dictionary = cands[0] if not cands.is_empty() else {}
	var adv: Dictionary = cands[1] if cands.size() > 1 else {}
	_assert(str(walk.get("action", "")) == "move" and str(adv.get("action", "")) == "advance",
		"its record lists the Normal move first (the chosen card) and RACE-1's Advance after it (%s, %s)" % [
		str(walk.get("action", "")), str(adv.get("action", ""))])
	_assert(int(walk.get("turns_to_reach", 0)) == 3 and int(adv.get("turns_to_reach", 0)) == 2,
		"the Normal move takes 3 turns, the Advance 2 (%d, %d)" % [int(walk.get("turns_to_reach", 0)), int(adv.get("turns_to_reach", 0))])
	_assert(int(a.get("turns_to_reach", 0)) == 3 and absf(float(walk.get("score", 0.0)) - float(a.get("score", -1.0))) < 1e-6,
		"the assignment carries the Normal move's turns and score (%d, %.3f)" % [int(a.get("turns_to_reach", 0)), float(a.get("score", 0.0))])
	_assert(absf(_terms_sum(walk) - float(walk.get("score", 0.0))) < 0.01,
		"its score terms add up to its score (%.3f vs %.3f)" % [_terms_sum(walk), float(walk.get("score", 0.0))])
	AIDecisionMaker._config_overrides["MOVE_LONG_ADVANCE"] = 0.0
	var snap0 = _board(1, FAR_NML)
	_add_unit(snap0, "runner", 1, FAR_NML + Vector2(-200, 300), 3, 6, 3, 2, 6, 150)
	_plan(snap0, ["keeper", "runner"], PURGE_RULES)
	AIDecisionMaker._config_overrides.erase("MOVE_LONG_ADVANCE")
	var loop_walk: Dictionary = {}
	for c in _keeper_cands("obj_nml_1"):
		if str(c.get("action", "")) == "move" and str(c.get("reason", "")) == "moving to objective":
			loop_walk = c
	var diff := _same_candidate(walk, loop_walk) if not loop_walk.is_empty() else "no loop candidate"
	_assert(diff == "", "the Normal move matches the planner's own Normal-move candidate (score %.3f vs %.3f) %s" % [
		float(walk.get("score", 0.0)), float(loop_walk.get("score", 0.0)), diff])
	_assert(str(a.get("coordination_note", "")).find("a Normal move: 3 turns") >= 0,
		"its card says it walks, at what pace and score (%s)" % str(a.get("coordination_note", "")))

func test_keeper_holds_when_its_walk_arrives_too_late() -> void:
	print("\n--- round 3: joining with a Normal move, the trip would end after round 5 (TOO-LATE) ---")
	# obj_nml_1 30.8" from home, 38" from the Orks: 3 turns at the Advance
	# pace (arrives in round 5), 4 at a Normal move (round 6).
	var far := HOME + Vector2(1200, 280)
	var sec := {"active_mission_ids": ["test"], "nml_priority": 8.0}
	var snap = _board(1, far, 3)
	_add_unit(snap, "runner", 1, far + Vector2(-200, 200), 3, 6, 3, 2, 6, 150)
	var plan = _plan(snap, ["keeper", "runner"], RECON_RULES, sec)
	var adv: Dictionary = {}
	for c in _keeper_cands("obj_nml_1"):
		if str(c.get("action", "")) == "advance":
			adv = c
	_assert(str(plan.get("runner", {}).get("objective_id", "")) == "obj_nml_1", "the runner takes obj_nml_1 (%s)" % str(plan.get("runner", {}).get("objective_id", "")))
	_assert(_last_kr.has("target") and str(_last_kr.get("target", {}).get("action", "")) == "advance" \
			and int(adv.get("turns_to_reach", 0)) == 3,
		"pass 1 releases the keeper for its 3-turn Advance there (%s, %d turns)" % [
		str(_last_kr.get("target", {}).get("action", _last_kr.get("kept", ""))), int(adv.get("turns_to_reach", 0))])
	var walk := _call_ai("_keeper_release_normal_pace", [adv, _eval("obj_nml_1"), 3]) if not adv.is_empty() else {}
	_assert(int(walk.get("turns_to_reach", 0)) == 4, "walking, it needs 4 turns (%d)" % int(walk.get("turns_to_reach", 0)))
	_assert(_holds_home(plan), "a walk that ends after the last battle round keeps the keeper home")

func test_normal_pace_matches_the_planner() -> void:
	print("\n--- _keeper_release_normal_pace == the planner's own Normal-move candidates (races included) ---")
	# Centre objective, P1 units 27-34" from it (RACE-1 Advances), enemies at
	# 3-4 moves from it: the race is lost walking and not when advancing.
	var snap := {"battle_round": 1, "meta": {"battle_round": 1, "first_turn_player": 1},
		"board": {"objectives": [
			{"id": "obj_home_1", "position": Vector2(440, 600), "zone": "player1"},
			{"id": "obj_center", "position": Vector2(880, 1200), "zone": "no_mans_land"},
			{"id": "obj_home_2", "position": Vector2(1320, 1800), "zone": "player2"},
		], "terrain_features": []}, "units": {}}
	_add_unit(snap, "keeper", 1, Vector2(440, 600), 3, 7, 5, 3, 8, 240)
	_add_unit(snap, "walker_a", 1, Vector2(200, 100), 3, 6, 3, 2, 8, 150)
	_add_unit(snap, "walker_b", 1, Vector2(1500, 160), 5, 4, 2, 1, 6, 100)
	_add_unit(snap, "walker_c", 1, Vector2(120, 380), 3, 7, 5, 3, 10, 200)
	_add_unit(snap, "boyz", 2, Vector2(165, 2154), 10, 5, 1, 2, 6, 80)
	_add_unit(snap, "nobz", 2, Vector2(1700, 2250), 5, 5, 2, 2, 6, 120)
	var movable := ["keeper", "walker_a", "walker_b", "walker_c"]
	_plan(snap, movable, PURGE_RULES)
	var adv_evals := _last_evals.duplicate(true)
	var adv_cands := {}
	for uid in AIDecisionMaker._last_movement_candidates:
		for c in AIDecisionMaker._last_movement_candidates[uid]:
			adv_cands["%s|%s" % [uid, c.objective_id]] = c
	AIDecisionMaker._config_overrides["MOVE_LONG_ADVANCE"] = 0.0
	_plan(snap, movable, PURGE_RULES)
	AIDecisionMaker._config_overrides.erase("MOVE_LONG_ADVANCE")
	var compared := 0
	var race_flips := 0
	var bad: Array = []
	for key in adv_cands:
		var c: Dictionary = adv_cands[key]
		if str(c.get("action", "")) != "advance":
			continue
		# MERGE (main ADV-ODDS-1): a this-turn Advance priced at its roll odds
		# (adv_chance > 0) is ADV-ODDS-1's, which MOVE_LONG_ADVANCE = 0 does not
		# turn off — the oracle loop still Advances it, so only RACE-1 long
		# trips are compared with the loop's Normal move.
		if float(c.get("adv_chance", 0.0)) > 0.0:
			continue
		var ev: Dictionary = {}
		for e in adv_evals:
			if str(e.id) == str(c.objective_id):
				ev = e
		var walk := _call_ai("_keeper_release_normal_pace", [c, ev, 1])
		var loop_c: Dictionary = {}
		for lc in AIDecisionMaker._last_movement_candidates.get(str(c.unit_id), []):
			if str(lc.objective_id) == str(c.objective_id):
				loop_c = lc
		var diff := _same_candidate(walk, loop_c) if not loop_c.is_empty() and not walk.is_empty() else "missing"
		compared += 1
		if not walk.is_empty() and bool(walk.get("race_lost", false)) and not bool(c.get("race_lost", false)):
			race_flips += 1
		print("  %s: advance %d turns %.3f (race lost %s) -> walk %d turns %.3f (race lost %s, enemy %d, army %d) loop %.3f %s" % [
			key, int(c.turns_to_reach), float(c.score), str(c.get("race_lost", false)), int(walk.get("turns_to_reach", 0)),
			float(walk.get("score", 0.0)), str(walk.get("race_lost", false)), int(walk.get("race_enemy_oc", 0)), int(walk.get("race_army_oc", 0)),
			float(loop_c.get("score", 0.0)), diff])
		if diff != "":
			bad.append("%s: %s" % [key, diff])
	_assert(compared >= 4, "compares every Advance candidate of the plan with the loop's Normal move (%d)" % compared)
	_assert(race_flips >= 1, "at least one of them is a race lost walking and not lost advancing (%d)" % race_flips)
	_assert(bad.is_empty(), "turns, race and every score term match (%s)" % "; ".join(bad))

func test_keeper_holds_when_dim_returns_skips_the_target() -> void:
	print("\n--- Reconnaissance (one non-home objective scores): the runner takes obj_nml_2, so obj_nml_1 adds nothing ---")
	var snap = _board(1, NML, 1, [{"id": "obj_nml_2", "position": NML_2, "zone": "no_mans_land"}])
	_add_unit(snap, "runner", 1, NML_2 + Vector2(0, -200), 3, 6, 3, 2, 6, 150)
	var plan = _plan(snap, ["keeper", "runner"], RECON_RULES)
	_assert(str(plan.get("runner", {}).get("objective_id", "")) == "obj_nml_2", "the runner takes obj_nml_2 (%s)" % str(plan.get("runner", {}).get("objective_id", "")))
	_assert(_last_kr.has("target") and str(_last_kr.get("target", {}).get("objective_id", "")) == "obj_nml_1",
		"pass 1 releases the keeper for obj_nml_1 (%s)" % str(_last_kr.get("target", {}).get("objective_id", _last_kr.get("kept", ""))))
	_assert(_holds_home(plan), "with obj_nml_2 taken, obj_nml_1 adds nothing (DIM-RETURNS): the keeper holds")

func test_keeper_holds_when_primary_pays_for_home() -> void:
	print("\n--- same board, Destroyer's Wrath: hold_more counts home ---")
	var plan = _plan(_board(), ["keeper"], WRATH_RULES)
	_assert(_holds_home(plan), "a home objective the primary pays for keeps its keeper")
	_assert(_kept_by("our primary pays for it"), "kept by the primary-card guard (%s)" % str(_last_kr.get("kept", "-")))

func test_keeper_holds_when_enemy_reserves_arrive_next_turn() -> void:
	print("\n--- going second (the enemy's next turn is round 2), enemy has a unit in reserves ---")
	var snap = _board(2)
	_add_unit(snap, "stormboyz", 2, Vector2.ZERO, 10, 5, 1, 1, 12, 140, GameStateData.UnitStatus.IN_RESERVES)
	var plan = _plan(snap, ["keeper"], RECON_RULES)
	_assert(_holds_home(plan), "reserves that can deep strike onto home next turn keep the keeper")
	_assert(_kept_by("stormboyz can arrive from reserves"), "kept by the reserves guard (%s)" % str(_last_kr.get("kept", "-")))

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
	_assert(_kept_by("allarus can arrive from reserves"), "kept by the early-ingress guard (%s)" % str(_last_kr.get("kept", "-")))

func test_keeper_holds_when_enemy_can_reach_home() -> void:
	print("\n--- an enemy M12 unit 26\" from home (move + charge + pile-in/consolidate reach it) ---")
	var snap = _board()
	_add_unit(snap, "bikers", 2, HOME + Vector2(0, 26.0 * PX), 3, 6, 3, 2, 12, 140)
	var plan = _plan(snap, ["keeper"], RECON_RULES)
	_assert(_holds_home(plan), "an enemy that can be on home by the end of its next turn keeps the keeper")
	_assert(_kept_by("bikers can reach it in one turn"), "kept by the on-board reach guard (%s)" % str(_last_kr.get("kept", "-")))

func test_melee_keeper_that_would_go_hunting_holds() -> void:
	print("\n--- a melee keeper (M10, chase cap 24\") and one slow enemy model 23.9\" away: no threat to home, but in chase range ---")
	var snap = _board()
	snap.units.erase("keeper")
	_add_unit(snap, "keeper", 1, HOME, 3, 7, 5, 3, 10, 240)
	snap.units["keeper"].meta["weapons"] = [{"name": "claws", "type": "Melee", "range": "Melee",
		"attacks": "4", "weapon_skill": "2", "strength": "6", "ap": "-2", "damage": "2"}]
	_add_unit(snap, "grot_tank", 2, HOME + Vector2(0, 23.9 * PX), 1, 6, 6, 1, 2, 40)
	var plan = _plan(snap, ["keeper"], RECON_RULES)
	_assert(_last_kr.has("target"), "pass 1 releases it: the enemy (M2) cannot reach home in its next turn (%s)" % str(
		_last_kr.get("target", {}).get("objective_id", _last_kr.get("kept", ""))))
	_assert(_holds_home(plan), "its move there would turn into a hunt (pass 2.5's chase gate), so it keeps home as on the base (%s %s)" % [
		plan.get("keeper", {}).get("action", ""), plan.get("keeper", {}).get("objective_id", "")])

func test_keeper_holds_without_a_unit_to_retake_home() -> void:
	print("\n--- no other unit within one move of home ---")
	var snap = _board()
	snap.units.erase("backup")
	_add_unit(snap, "backup", 1, HOME + Vector2(0, 20.0 * PX), 4, 3, 1, 2, 7, 45)
	var plan = _plan(snap, ["keeper"], RECON_RULES)
	_assert(_holds_home(plan), "with nobody to step back onto home, the keeper holds")
	_assert(_kept_by("no other unit can stand on it within one move"), "kept by the backup guard (%s)" % str(_last_kr.get("kept", "-")))

func test_fragile_keeper_holds() -> void:
	print("\n--- the keeper is a fragile squad (T3, 1 wound per model) ---")
	var snap = _board()
	snap.units.erase("keeper")
	_add_unit(snap, "keeper", 1, HOME, 4, 3, 1, 2, 7, 45)
	var plan = _plan(snap, ["keeper"], RECON_RULES)
	_assert(_holds_home(plan), "a fragile keeper (KEEPER-PICK's natural keeper) holds")
	_assert(_kept_by("a fragile keeper"), "kept by the fragile guard (%s)" % str(_last_kr.get("kept", "-")))

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
	_assert(_kept_by("the plan orders it to hold"), "kept by the plan-order guard (%s)" % str(_last_kr.get("kept", "-")))

func test_param_zero_restores_base() -> void:
	print("\n--- FIX_KEEPER_RELEASE = 0 ---")
	AIDecisionMaker._config_overrides["FIX_KEEPER_RELEASE"] = 0.0
	var plan = _plan(_board(), ["keeper"], RECON_RULES)
	AIDecisionMaker._config_overrides["FIX_KEEPER_RELEASE"] = 1.0
	_assert(_holds_home(plan), "with the fix off the sole keeper holds home as before")
