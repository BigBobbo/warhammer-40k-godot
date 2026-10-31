extends SceneTree

# R1-HOME-LAST (FIX_R1_HOME_CAPTURE): in battle round 1 a durable unit is not
# spent capturing our own uncontrolled home objective while it has a forward
# objective worth at least as much VP — home goes, after the forward captures,
# to a unit the plan left spare. Only when no enemy can reach home by the end
# of its next turn and no card pays for holding home. And a spare unit sent in
# support on a round-1 trip its capture candidate would Advance (RACE-1)
# Advances when OC there matters (a race the enemy wins) — not when its walk
# could bring a gun without [ASSAULT] into range (range + M), nor with units
# embarked in it (18.04: no disembark after an Advance). LLM-critic cluster
# r1_home_capture (value-checked, 2026-10-30, 36 rollouts): a Custodian Guard
# unit walked home while a second squad reinforced it (Advancing forward
# +6.86 VP [4.45, 9.27]); a support squad walked a 3-turn trip to a contested
# centre (Advancing +5.86 [3.09, 8.63]).
# Run with: godot --headless --path 40k -s tests/unit/test_ai_fix_r1_home_capture.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

const MOVABLE := ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]
const PX := 40.0  # pixels per inch
const HOME := Vector2(510, 340)      # our home objective (player 1 zone)
const NML := Vector2(1150, 760)      # a no man's land objective
const ENEMY_HOME := Vector2(1250, 2060)

# A card that counts no man's land and not home (home_last needs a primary
# card that counts home in none of its rules).
const HOME_FREE_RULES := [
	{"type": "hold_min", "exclude_home": true, "min": 1, "vp": 4, "when": "command", "rounds": [2, 5]},
	{"type": "hold_central_plus_nml", "vp": 5, "when": "command", "rounds": [2, 5]},
]
# A card that pays for every objective, more for no man's land than for home.
const HOLD_RULES := [
	{"type": "hold_min", "exclude_home": true, "min": 1, "vp": 4, "when": "command", "rounds": [2, 5]},
	{"type": "per_objective", "vp_per": 1, "when": "command", "rounds": [2, 5]},
]

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== Round 1: strong units go forward, home goes to a spare unit (R1-HOME-LAST) ===\n")
	AIDecisionMaker._config_overrides["FIX_R1_HOME_CAPTURE"] = 1.0
	AIDecisionMaker._config_overrides["FIX_R1_SUPPORT_ADVANCE"] = 1.0
	test_durable_unit_goes_forward_and_spare_takes_home()
	test_lone_unit_still_takes_home()
	test_fragile_unit_takes_home()
	test_enemy_near_home_keeps_base()
	test_card_paying_for_home_keeps_base()
	test_primary_counting_home_keeps_base()
	test_round_two_keeps_base()
	test_secondary_cards()
	test_slow_spare_does_not_take_home()
	test_obj_assign_does_not_hand_home_back()
	test_second_player_enemy_reserves_keeps_base()
	test_support_trip_into_lost_race_advances()
	test_support_joiner_of_race_not_lost_walks()
	test_support_ability_text_charge_walks()
	test_support_non_assault_in_range_walks()
	test_support_non_assault_in_range_after_walk_walks()
	test_support_non_assault_out_of_reach_advances()
	test_support_loaded_transport_walks()
	test_support_reach_band_walks()
	test_param_zero_restores_base()
	test_support_param_zero_restores_base()
	AIDecisionMaker._config_overrides.erase("FIX_R1_HOME_CAPTURE")
	AIDecisionMaker._config_overrides.erase("FIX_R1_SUPPORT_ADVANCE")
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func _snapshot(battle_round: int = 1) -> Dictionary:
	return {"battle_round": battle_round, "meta": {"battle_round": battle_round, "first_turn_player": 1},
		"board": {"objectives": [
			{"id": "obj_home_1", "position": HOME, "zone": "player1"},
			{"id": "obj_nml_1", "position": NML, "zone": "no_mans_land"},
			{"id": "obj_home_2", "position": ENEMY_HOME, "zone": "player2"},
		], "terrain_features": []}, "units": {}}

# `n` models (OC `oc` each) whose centroid is at `pos`.
func _add_unit(snapshot: Dictionary, unit_id: String, owner: int, pos: Vector2, n: int,
		toughness: int, wounds: int, oc: int, move: int, points: int, weapons: Array = [], abilities: Array = []) -> void:
	var models = []
	for i in range(n):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 40,
			"base_type": "circular", "base_dimensions": {},
			"position": Vector2(pos.x + (i - (n - 1) / 2.0) * 45.0, pos.y), "wounds": wounds, "current_wounds": wounds})
	snapshot.units[unit_id] = {
		"id": unit_id, "owner": owner, "status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"name": unit_id, "points": points, "stats": {"move": move, "toughness": toughness, "save": 2,
			"wounds": wounds, "leadership": 6, "objective_control": oc}, "keywords": ["INFANTRY"], "weapons": weapons.duplicate(true),
			"abilities": abilities.duplicate(true)},
		"models": models, "flags": {}}

# The s7468 shape: two Custodian Guard units ~9" from our empty home, a no
# man's land objective a 2-turn trip away, the enemy army 40"+ away.
func _board(battle_round: int = 1) -> Dictionary:
	var snap = _snapshot(battle_round)
	_add_unit(snap, "gamma", 1, HOME + Vector2(9.0 * PX, 0), 3, 7, 3, 3, 6, 160)
	_add_unit(snap, "alpha", 1, HOME + Vector2(0, 9.5 * PX), 3, 7, 3, 3, 6, 160)
	_add_unit(snap, "orks", 2, ENEMY_HOME, 10, 5, 1, 2, 6, 80)
	return snap

func _plan(snap: Dictionary, movable_ids: Array, rules: Array, hold_home_required: bool = false,
		secondary: Dictionary = {}) -> Dictionary:
	AIDecisionMaker._primary_awareness_p1 = {"card_name": "test", "active_rules": rules.size(), "vp_rules": rules.duplicate(true),
		"objective_pressure": 0.0, "enemy_home_bonus": 0.0, "central_bonus": 0.0, "hold_home_required": hold_home_required,
		"kill_pressure": false, "quarters": false}
	AIDecisionMaker._secondary_awareness_p1 = secondary.duplicate(true)
	var friendlies = {}
	var enemies = {}
	var movable = {}
	for uid in snap.units:
		var u = snap.units[uid]
		if int(u.owner) == 1:
			friendlies[uid] = u
		else:
			enemies[uid] = u
	for uid in movable_ids:
		movable[uid] = MOVABLE
	var objectives = []
	for o in snap.board.objectives:
		objectives.append(o.position)
	var br := int(snap.battle_round)
	var evals = AIDecisionMaker._evaluate_all_objectives(snap, objectives, 1, enemies, friendlies, br)
	var plan = AIDecisionMaker._assign_units_to_objectives(snap, movable, evals, objectives, enemies, friendlies, 1, br)
	for uid in plan:
		print("  %s: %s %s [%s] (%s)" % [uid, plan[uid].get("action", ""), plan[uid].get("objective_id", ""),
			plan[uid].get("assign_pass", ""), str(plan[uid].get("reason", "")).substr(0, 110)])
	AIDecisionMaker._primary_awareness_p1 = {}
	AIDecisionMaker._secondary_awareness_p1 = {}
	return plan

func _obj(plan: Dictionary, uid: String) -> String:
	return str(plan.get(uid, {}).get("objective_id", ""))

func _act(plan: Dictionary, uid: String) -> String:
	return str(plan.get(uid, {}).get("action", ""))

func _home_takers(plan: Dictionary) -> Array:
	var out := []
	for uid in plan:
		if _obj(plan, uid) == "obj_home_1" and _act(plan, uid) in ["move", "advance", "hold"]:
			out.append(uid)
	return out

func test_durable_unit_goes_forward_and_spare_takes_home() -> void:
	print("\n--- round 1, two durable units near an empty home, nml worth more, enemy far ---")
	var plan = _plan(_board(), ["gamma", "alpha"], HOME_FREE_RULES)
	var fwd := 0
	for uid in ["gamma", "alpha"]:
		if _obj(plan, uid) == "obj_nml_1" and _act(plan, uid) in ["move", "advance"]:
			fwd += 1
	_assert(fwd == 1, "one Custodian Guard unit goes forward to obj_nml_1 (gamma %s %s, alpha %s %s)" % [
		_act(plan, "gamma"), _obj(plan, "gamma"), _act(plan, "alpha"), _obj(plan, "alpha")])
	_assert(_home_takers(plan).size() == 1, "exactly one unit still takes home (%s)" % str(_home_takers(plan)))
	_assert(_obj(plan, "gamma") == "obj_nml_1", "the unit nearest home (gamma) is the one sent forward (%s)" % _obj(plan, "gamma"))

func test_lone_unit_still_takes_home() -> void:
	print("\n--- only gamma moves (no spare): it takes home after all ---")
	var snap = _board()
	snap.units.erase("alpha")
	var plan = _plan(snap, ["gamma"], HOME_FREE_RULES)
	_assert(_obj(plan, "gamma") == "obj_home_1", "with nobody spare, home is not left open (%s %s)" % [_act(plan, "gamma"), _obj(plan, "gamma")])

func test_fragile_unit_takes_home() -> void:
	print("\n--- a fragile squad (T3, 1W) is the one near home ---")
	var snap = _board()
	snap.units.erase("gamma")
	snap.units.erase("alpha")
	_add_unit(snap, "squad", 1, HOME + Vector2(9.0 * PX, 0), 4, 3, 1, 2, 7, 45)
	_add_unit(snap, "alpha", 1, HOME + Vector2(0, 9.5 * PX), 3, 7, 3, 3, 6, 160)
	var plan = _plan(snap, ["squad", "alpha"], HOME_FREE_RULES)
	_assert(_obj(plan, "squad") == "obj_home_1", "the fragile squad still captures home (%s)" % _obj(plan, "squad"))

func test_enemy_near_home_keeps_base() -> void:
	print("\n--- an enemy M12 unit 26\" from home ---")
	var snap_on = _board()
	_add_unit(snap_on, "bikers", 2, HOME + Vector2(-2.0 * PX, 26.0 * PX), 3, 6, 3, 2, 12, 140)
	var on_plan = _plan(snap_on, ["gamma", "alpha"], HOME_FREE_RULES)
	AIDecisionMaker._config_overrides["FIX_R1_HOME_CAPTURE"] = 0.0
	var snap_off = _board()
	_add_unit(snap_off, "bikers", 2, HOME + Vector2(-2.0 * PX, 26.0 * PX), 3, 6, 3, 2, 12, 140)
	var off_plan = _plan(snap_off, ["gamma", "alpha"], HOME_FREE_RULES)
	AIDecisionMaker._config_overrides["FIX_R1_HOME_CAPTURE"] = 1.0
	_assert(_obj(on_plan, "gamma") == _obj(off_plan, "gamma") and _obj(on_plan, "alpha") == _obj(off_plan, "alpha"),
		"an enemy that can reach home keeps the base plan (gamma %s / %s)" % [_obj(on_plan, "gamma"), _obj(off_plan, "gamma")])

func test_card_paying_for_home_keeps_base() -> void:
	print("\n--- the primary requires holding home ---")
	var plan = _plan(_board(), ["gamma", "alpha"], HOME_FREE_RULES, true)
	_assert(_obj(plan, "gamma") == "obj_home_1", "a card that pays for holding home keeps gamma's capture (%s)" % _obj(plan, "gamma"))

func test_secondary_cards() -> void:
	print("\n--- Defend Stronghold (pays for home) vs Burden of Trust (pays for any objective) ---")
	var stronghold := {"active_mission_ids": ["defend_stronghold"], "defend_home": 3.5,
		"vp_objective_hints": [{"kind": "home", "vp": 3.0, "card": "Defend Stronghold"}]}
	var plan = _plan(_board(), ["gamma", "alpha"], HOME_FREE_RULES, false, stronghold)
	_assert(_obj(plan, "gamma") == "obj_home_1", "Defend Stronghold keeps gamma's home capture (%s)" % _obj(plan, "gamma"))
	var burden := {"active_mission_ids": ["burden_of_trust"], "defend_home": 2.45, "nml_priority": 2.45,
		"vp_objective_hints": [{"kind": "any", "vp": 2.0, "card": "Burden of Trust"}]}
	plan = _plan(_board(), ["gamma", "alpha"], HOME_FREE_RULES, false, burden)
	_assert(_obj(plan, "gamma") == "obj_nml_1" and _home_takers(plan).size() == 1,
		"Burden of Trust pays for the forward objective too: gamma goes forward, home still taken (gamma %s, home %s)" % [_obj(plan, "gamma"), str(_home_takers(plan))])

func test_round_two_keeps_base() -> void:
	print("\n--- same board in battle round 2 ---")
	var plan = _plan(_board(2), ["gamma", "alpha"], HOME_FREE_RULES)
	_assert(_obj(plan, "gamma") == "obj_home_1", "round 2+ is unchanged (%s)" % _obj(plan, "gamma"))

# s7451 shape: obj_nml_1 a 3-turn walk (2 at the Advance pace) for "trailer",
# a quicker unit already takes it, and enemy OC that out-races ours is close.
func _race_board() -> Dictionary:
	var snap = _snapshot(1)
	snap.board.objectives.pop_back()  # no enemy home to wander off to
	_add_unit(snap, "lead", 1, NML + Vector2(-8.0 * PX, -10.0 * PX), 3, 7, 3, 3, 6, 160)
	_add_unit(snap, "trailer", 1, NML + Vector2(-19.0 * PX, -6.0 * PX), 3, 7, 3, 3, 6, 160)
	_add_unit(snap, "home_squad", 1, HOME, 4, 3, 1, 2, 7, 45)
	# MERGE (main OBJ-GAP-1): the boyz moved 3" further south (was 10"). They
	# stand in a 21"-wide row, and the race/threat tables now measure from the
	# NEAREST model: at 10" an end model was one M6 + 2" move from range
	# (COORD-5 raised obj_nml_1's need to 14 and trailer became a capture).
	# Here the nearest boy is ~9.5" out — two moves, the race this board is about.
	_add_unit(snap, "boyz", 2, NML + Vector2(8.0 * PX, 13.0 * PX), 20, 5, 1, 2, 6, 170)
	return snap

func test_support_trip_into_lost_race_advances() -> void:
	print("\n--- support trip of 3 turns (2 Advancing) into a race the enemy wins ---")
	var plan = _plan(_race_board(), ["lead", "trailer"], HOLD_RULES)
	_assert(_obj(plan, "trailer") == "obj_nml_1" and str(plan.get("trailer", {}).get("assign_pass", "")) == "support",
		"trailer supports obj_nml_1 (%s %s [%s])" % [_act(plan, "trailer"), _obj(plan, "trailer"), str(plan.get("trailer", {}).get("assign_pass", ""))])
	_assert(_act(plan, "trailer") == "advance", "it Advances to be there with the lead unit for the fight (%s)" % _act(plan, "trailer"))
	AIDecisionMaker._config_overrides["FIX_R1_SUPPORT_ADVANCE"] = 0.0
	var off_plan = _plan(_race_board(), ["lead", "trailer"], HOLD_RULES)
	AIDecisionMaker._config_overrides["FIX_R1_SUPPORT_ADVANCE"] = 1.0
	_assert(_act(off_plan, "trailer") == "move", "with the fix off it walks (%s)" % _act(off_plan, "trailer"))

func test_param_zero_restores_base() -> void:
	print("\n--- FIX_R1_HOME_CAPTURE = 0 ---")
	AIDecisionMaker._config_overrides["FIX_R1_HOME_CAPTURE"] = 0.0
	var plan = _plan(_board(), ["gamma", "alpha"], HOME_FREE_RULES)
	AIDecisionMaker._config_overrides["FIX_R1_HOME_CAPTURE"] = 1.0
	_assert(_obj(plan, "gamma") == "obj_home_1", "with the fix off gamma captures home as before (%s)" % _obj(plan, "gamma"))

func test_primary_counting_home_keeps_base() -> void:
	print("\n--- the primary card counts home (per_objective) ---")
	var plan = _plan(_board(), ["gamma", "alpha"], HOLD_RULES)
	_assert(_obj(plan, "gamma") == "obj_home_1", "a primary that counts home keeps gamma's capture (%s)" % _obj(plan, "gamma"))

func test_slow_spare_does_not_take_home() -> void:
	print("\n--- the only spare unit needs 2 turns to reach home ---")
	var snap = _board()
	snap.units.erase("alpha")
	_add_unit(snap, "alpha", 1, HOME + Vector2(0, 15.0 * PX), 3, 7, 3, 3, 6, 160)
	var plan = _plan(snap, ["gamma", "alpha"], HOME_FREE_RULES)
	_assert(_obj(plan, "gamma") == "obj_home_1", "a spare that gets there in 2 turns does not take home: gamma does (gamma %s, alpha %s %s)" % [
		_obj(plan, "gamma"), _act(plan, "alpha"), _obj(plan, "alpha")])

func test_obj_assign_does_not_hand_home_back() -> void:
	print("\n--- a quicker deferred unit is not handed home by OBJ-ASSIGN-1 ---")
	var snap = _board()
	snap.units.erase("gamma")
	snap.units.erase("alpha")
	_add_unit(snap, "gamma", 1, HOME + Vector2(6.0 * PX, 0), 3, 7, 3, 3, 6, 160)
	_add_unit(snap, "alpha", 1, HOME + Vector2(0, 11.5 * PX), 3, 7, 3, 3, 8, 160)
	var plan = _plan(snap, ["gamma", "alpha"], HOME_FREE_RULES)
	_assert(_obj(plan, "gamma") == "obj_nml_1" and _obj(plan, "alpha") == "obj_home_1",
		"gamma goes forward, alpha takes home (gamma %s %s, alpha %s %s)" % [_act(plan, "gamma"), _obj(plan, "gamma"), _act(plan, "alpha"), _obj(plan, "alpha")])

func test_second_player_enemy_reserves_keeps_base() -> void:
	print("\n--- we go second and the enemy has a unit in reserve ---")
	var snap = _board()
	snap.meta["first_turn_player"] = 2
	_add_unit(snap, "deepstrikers", 2, Vector2(-1000, -1000), 5, 4, 2, 1, 6, 100)
	snap.units["deepstrikers"]["status"] = GameStateData.UnitStatus.IN_RESERVES
	var plan = _plan(snap, ["gamma", "alpha"], HOME_FREE_RULES)
	_assert(_obj(plan, "gamma") == "obj_home_1", "a reserve that can arrive before our next turn keeps gamma's capture (%s)" % _obj(plan, "gamma"))

# The joiner shape (s7437): a race we are not losing — the enemy is a lone
# small unit far off. The trip stays a Normal move.
func test_support_joiner_of_race_not_lost_walks() -> void:
	print("\n--- support trip into a race we are not losing ---")
	var snap = _race_board()
	snap.units.erase("boyz")
	_add_unit(snap, "grots", 2, ENEMY_HOME, 2, 2, 1, 1, 5, 20)
	var plan = _plan(snap, ["lead", "trailer"], HOLD_RULES)
	_assert(_act(plan, "trailer") == "move", "a joiner of a race we are not losing keeps its Normal move (%s %s)" % [_act(plan, "trailer"), _obj(plan, "trailer")])

func test_support_ability_text_charge_walks() -> void:
	print("\n--- ability text says Advance & Charge, no engine flag, enemy within M+12 ---")
	var snap = _race_board()
	snap.units.erase("trailer")
	_add_unit(snap, "trailer", 1, NML + Vector2(-19.0 * PX, -6.0 * PX), 3, 7, 3, 3, 6, 160, [],
		[{"name": "Fury", "description": "This unit can Advance and still declare a charge."}])
	_add_unit(snap, "scouts", 2, NML + Vector2(-33.0 * PX, -14.0 * PX), 1, 3, 1, 1, 6, 15)
	var plan = _plan(snap, ["lead", "trailer"], HOLD_RULES)
	_assert(_obj(plan, "trailer") == "obj_nml_1" and _act(plan, "trailer") == "move",
		"without the engine flag it keeps its charge: the support trip walks (%s %s)" % [_act(plan, "trailer"), _obj(plan, "trailer")])

func test_support_non_assault_in_range_walks() -> void:
	print("\n--- non-[ASSAULT] ranged unit with an enemy in range ---")
	var snap = _race_board()
	snap.units.erase("trailer")
	_add_unit(snap, "trailer", 1, NML + Vector2(-19.0 * PX, -6.0 * PX), 3, 7, 3, 3, 6, 160,
		[{"name": "Bolter", "type": "Ranged", "range": "48", "special_rules": "heavy"}],
		[{"name": "Steady", "description": "This unit can shoot after it Advances."}])
	var plan = _plan(snap, ["lead", "trailer"], HOLD_RULES)
	_assert(_obj(plan, "trailer") == "obj_nml_1" and _act(plan, "trailer") == "move",
		"Advancing would lose its non-[ASSAULT] shooting: the support trip walks (%s %s)" % [_act(plan, "trailer"), _obj(plan, "trailer")])

# The s7470 r1 P2 shape (Battlewagon Alpha): a transport, M10, whose only gun
# is a 36" Big shoota without [ASSAULT], on the race board's support trip to
# obj_nml_1 (27.8" away). The nearest enemy (boyz) is ~42" away: out of range
# where the wagon stands, ~32" away after the 10" walk the Advance replaces.
# `cargo`: a unit is embarked in it (models off the battlefield, as
# TransportManager.embark_unit leaves them).
func _wagon_board(gun_range: String, cargo: bool = false) -> Dictionary:
	var snap = _race_board()
	snap.units.erase("trailer")
	_add_unit(snap, "wagon", 1, NML + Vector2(-24.0 * PX, -14.0 * PX), 1, 10, 16, 5, 10, 180,
		[{"name": "Big shoota", "type": "Ranged", "range": gun_range, "special_rules": "lethal hits, rapid fire 2"}])
	snap.units["wagon"]["meta"]["keywords"] = ["VEHICLE", "TRANSPORT"]
	snap.units["wagon"]["transport_data"] = {"capacity": 22, "capacity_keywords": ["INFANTRY"],
		"embarked_units": [], "firing_deck": 0}
	if cargo:
		_add_unit(snap, "cargo", 1, Vector2.ZERO, 10, 5, 1, 2, 6, 90)
		for m in snap.units["cargo"]["models"]:
			m["position"] = null
		snap.units["cargo"]["embarked_in"] = "wagon"
		snap.units["wagon"]["transport_data"]["embarked_units"] = ["cargo"]
	return snap

func test_support_non_assault_in_range_after_walk_walks() -> void:
	print("\n--- 36\" gun without [ASSAULT], M10, nearest enemy 40\" away (in range after the walk) ---")
	var snap = _wagon_board("36")
	var gap := AIDecisionMaker._get_unit_centroid(snap.units["wagon"]).distance_to(
		AIDecisionMaker._get_unit_centroid(snap.units["boyz"])) / PX
	_assert(gap > 36.0 and gap <= 46.0, "board: the nearest enemy is out of range now, within range + M (%.1f\")" % gap)
	var plan = _plan(snap, ["lead", "wagon"], HOLD_RULES)
	_assert(_obj(plan, "wagon") == "obj_nml_1" and str(plan.get("wagon", {}).get("assign_pass", "")) == "support",
		"the wagon supports obj_nml_1 (%s %s [%s])" % [_act(plan, "wagon"), _obj(plan, "wagon"), str(plan.get("wagon", {}).get("assign_pass", ""))])
	_assert(_act(plan, "wagon") == "move",
		"its walk would bring the boyz into range: the support trip walks and keeps the shot (%s)" % _act(plan, "wagon"))

# Regression net (not binding on the change): the reach is range + M, not
# "never for a non-[ASSAULT] gun" — a 24" gun (24 + 10 = 34" < 40") has
# nothing to shoot after the walk, so the trip still Advances.
func test_support_non_assault_out_of_reach_advances() -> void:
	print("\n--- 24\" gun without [ASSAULT], M10, nearest enemy 40\" away (out of range + M) ---")
	var plan = _plan(_wagon_board("24"), ["lead", "wagon"], HOLD_RULES)
	_assert(_obj(plan, "wagon") == "obj_nml_1" and _act(plan, "wagon") == "advance",
		"no enemy within range + M: the support trip still Advances (%s %s)" % [_act(plan, "wagon"), _obj(plan, "wagon")])
	AIDecisionMaker._config_overrides["FIX_R1_SUPPORT_ADVANCE"] = 0.0
	var off_plan = _plan(_wagon_board("24"), ["lead", "wagon"], HOLD_RULES)
	AIDecisionMaker._config_overrides["FIX_R1_SUPPORT_ADVANCE"] = 1.0
	_assert(_obj(off_plan, "wagon") == "obj_nml_1" and _act(off_plan, "wagon") == "move",
		"that Advance is R1-SUPPORT-ADVANCE's: with the switch off the wagon walks as before (%s %s)" % [_act(off_plan, "wagon"), _obj(off_plan, "wagon")])

func test_support_loaded_transport_walks() -> void:
	print("\n--- the same wagon (24\" gun) with a unit embarked ---")
	var plan = _plan(_wagon_board("24", true), ["lead", "wagon"], HOLD_RULES)
	_assert(_obj(plan, "wagon") == "obj_nml_1" and _act(plan, "wagon") == "move",
		"a transport that Advances bars disembarking (18.04): the loaded wagon walks (%s %s)" % [_act(plan, "wagon"), _obj(plan, "wagon")])

func test_support_reach_band_walks() -> void:
	print("\n--- support trip in the reach band (gap in (M, M+2]) ---")
	var snap = _race_board()
	snap.units.erase("trailer")
	_add_unit(snap, "trailer", 1, NML + Vector2(-11.0 * PX, -0.0 * PX), 3, 7, 3, 3, 6, 160)
	var plan = _plan(snap, ["lead", "trailer"], HOLD_RULES)
	_assert(_act(plan, "trailer") != "advance" or str(plan.get("trailer", {}).get("assign_pass", "")) != "support",
		"a reach-band trip is not a RACE-1 long trip: no support Advance (%s %s [%s])" % [_act(plan, "trailer"), _obj(plan, "trailer"), str(plan.get("trailer", {}).get("assign_pass", ""))])

func test_support_param_zero_restores_base() -> void:
	print("\n--- FIX_R1_SUPPORT_ADVANCE = 0 ---")
	AIDecisionMaker._config_overrides["FIX_R1_SUPPORT_ADVANCE"] = 0.0
	var plan = _plan(_race_board(), ["lead", "trailer"], HOLD_RULES)
	AIDecisionMaker._config_overrides["FIX_R1_SUPPORT_ADVANCE"] = 1.0
	_assert(_act(plan, "trailer") == "move" and _obj(plan, "trailer") == "obj_nml_1",
		"with the switch off the support trip walks as before (%s %s)" % [_act(plan, "trailer"), _obj(plan, "trailer")])
