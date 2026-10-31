extends SceneTree

# REINFORCE-INSURANCE (FIX_REINFORCE_INSURANCE): the movement planner valued a
# reinforcement of an objective we already hold, and the trip it competed
# with, with three wrong estimates (LLM-critic cluster reinforce_insurance,
# s7437 r2: Custodian Guard Beta reinforced a centre held with OC 6 instead of
# Advancing into the empty table quarter on the way to obj_nml_2; the Advance
# measured +4.36 VP over 36 rollouts, the gain from Reconnaissance Sweep's
# quarter tier at the end of the turn):
#   RI-RACE    a one-move reinforcement had no race test. The enemy's reach was
#              measured from unit centroids, so a 10-model squad whose front
#              rank was one move away did not count. When the enemy can stand
#              there with RI_RACE_LOST_RATIO (1.5) x our OC including this
#              unit, the reinforcement keeps MOVE_RACE_LOSS_FACTOR of its value.
#   RI-ASSAULT a unit whose ranged weapons are all [ASSAULT] gives up no
#              shooting by Advancing on a long trip.
#   RI-QUARTER the quarters card was a flat bonus on the walking spot; it is
#              now the card's tier VP for the spot the move really ends on.
# Guards: a reinforcement the enemy cannot match is untouched; a gun that
# cannot fire after Advancing still walks; FIX_REINFORCE_INSURANCE = 0 is base,
# and each part switch (FIX_RI_RACE / FIX_RI_ASSAULT / FIX_RI_QUARTER) at 0
# removes only its part. Judge follow-ups: RI-RACE reads 11e hosting areas
# (an enemy on the area is counted once, an enemy one move from the area edge
# is counted); RI-QUARTER leaves the mover's attached leader out of "the rest
# of the army".
# Run with: godot --headless --path 40k -s tests/unit/test_ai_fix_reinforce_insurance.gd
# (runs once the scene tree is up: the hosting-area test reads MissionManager)

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

const MOVABLE := ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]
const PX := 40.0  # pixels per inch
const OBJ_X := Vector2(880, 1200)     # the centre, held by our locked holder
const OBJ_SIDE := Vector2(390, 1740)  # open objective in the bottom-left quarter
const BETA_POS := Vector2(525, 913)   # s7437: 11.4" from the centre, 21" from obj_side

const RI_SWITCHES := ["FIX_REINFORCE_INSURANCE", "FIX_RI_RACE", "FIX_RI_ASSAULT", "FIX_RI_QUARTER"]

var _pass_count: int = 0
var _fail_count: int = 0
var _ran := false

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _run_tests():
	if _ran:
		return
	_ran = true
	await process_frame
	print("\n=== Reinforcing a held objective vs a trip elsewhere (REINFORCE-INSURANCE) ===\n")
	for sw in RI_SWITCHES:
		AIDecisionMaker._config_overrides[sw] = 1.0  # pin the fix on, whatever the default
	test_reinforcement_against_a_horde_front_rank_is_a_lost_race()
	test_reinforcement_the_enemy_cannot_match_is_kept()
	test_assault_gun_advances_on_long_trip()
	test_quarter_card_priced_at_the_spot_reached()
	test_attached_leader_moves_with_its_squad()
	test_race_reads_hosting_area()
	test_param_zero_restores_base()
	test_part_switches_remove_only_their_part()
	for sw in RI_SWITCHES:
		AIDecisionMaker._config_overrides.erase(sw)
	AIDecisionMaker._primary_awareness_p1 = {}
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
	return {"battle_round": 2, "meta": {"battle_round": 2},
		"board": {"objectives": objs, "terrain_features": []}, "units": {}}

# Models at `positions` (or `n` in a row centred on `pos`), OC `oc` each.
func _add_unit(snapshot: Dictionary, unit_id: String, owner: int, pos: Vector2, n: int, oc: int,
		move: int = 8, keywords: Array = ["INFANTRY"], weapons: Array = [], positions: Array = []) -> void:
	var models = []
	var pts: Array = positions
	if pts.is_empty():
		for i in range(n):
			pts.append(Vector2(pos.x + (i - (n - 1) / 2.0) * 50.0, pos.y))
	for i in range(pts.size()):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 32,
			"base_type": "circular", "base_dimensions": {},
			"position": pts[i], "wounds": 3, "current_wounds": 3})
	snapshot.units[unit_id] = {
		"id": unit_id, "owner": owner, "status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"name": unit_id, "points": 200, "stats": {"move": move, "toughness": 6, "save": 2,
			"wounds": 3, "leadership": 6, "objective_control": oc}, "keywords": keywords, "weapons": weapons},
		"models": models, "flags": {}}

# Our side (player 1, s7437's seat): a 2-model OC 2 holder on the centre (4 OC,
# not moving this phase) and beta (3 x OC 3 = 9) 11.4" from it.
# Enemy (player 2): a vehicle (OC 5) one move from the centre, and — when
# `horde` — a 15-model OC 1 squad in a column whose centroid is ~19" away
# (out of COORD-5's centroid reach) but whose front model is 11.1" away.
func _board(enemies: Dictionary, horde: bool, beta_weapons: Array = []) -> Dictionary:
	var snap = _snapshot()
	_add_unit(snap, "holder", 1, OBJ_X, 2, 2)
	_add_unit(snap, "beta", 1, BETA_POS, 3, 3, 8, ["INFANTRY"], beta_weapons)
	_add_unit(snap, "wagon", 2, Vector2(1200, 1450), 1, 5, 10, ["VEHICLE"])
	enemies["wagon"] = snap.units["wagon"]
	if horde:
		var col: Array = []
		for i in range(15):
			col.append(Vector2(1110 + i * 45.0, 1580 + i * 26.0))
		_add_unit(snap, "horde", 2, Vector2.ZERO, 15, 1, 6, ["INFANTRY"], [], col)
		enemies["horde"] = snap.units["horde"]
	return snap

func _plan(snap: Dictionary, movable_ids: Array, enemies: Dictionary, primary: Dictionary = {}) -> Dictionary:
	AIDecisionMaker._primary_awareness_p1 = primary
	AIDecisionMaker._secondary_awareness_p1 = {}
	var friendlies = {}
	var movable = {}
	for uid in snap.units:
		if int(snap.units[uid].owner) == 1:
			friendlies[uid] = snap.units[uid]
	for uid in movable_ids:
		movable[uid] = MOVABLE
	var objectives = []
	for o in snap.board.objectives:
		objectives.append(o.position)
	var evals = AIDecisionMaker._evaluate_all_objectives(snap, objectives, 1, enemies, friendlies, 2)
	for ev in evals:
		print("  %s: %s, ours %d, theirs %d, ~%d enemy OC one move away (centroid reach)" % [ev.id, ev.state,
			int(ev.friendly_oc), int(ev.enemy_oc), int(ev.get("projected_enemy_oc", 0))])
	var plan = AIDecisionMaker._assign_units_to_objectives(snap, movable, evals, objectives, enemies, friendlies, 1, 2)
	for uid in plan:
		print("  %s: %s %s [%s] (%s)" % [uid, plan[uid].get("action", ""), plan[uid].get("objective_id", ""),
			plan[uid].get("assign_pass", ""), str(plan[uid].get("reason", "")).substr(0, 110)])
	for uid in movable_ids:
		for c in AIDecisionMaker._last_movement_candidates.get(uid, []):
			print("    %s -> %s: %s score %.1f, %d turn(s), terms %s" % [uid, c.objective_id,
				c.action, float(c.score), int(c.turns_to_reach), str(c.get("score_terms", {}))])
	return plan

func _cand(uid: String, oid: String) -> Dictionary:
	for c in AIDecisionMaker._last_movement_candidates.get(uid, []):
		if str(c.objective_id) == oid:
			return c
	return {}

func _goes_to(plan: Dictionary, uid: String, oid: String) -> bool:
	var a: Dictionary = plan.get(uid, {})
	return str(a.get("objective_id", "")) == oid and str(a.get("action", "")) in ["move", "advance"]

func test_reinforcement_against_a_horde_front_rank_is_a_lost_race() -> void:
	print("\n--- centre held with OC 4; wagon (5) + a horde front rank (10) one move away ---")
	var enemies = {}
	var snap = _board(enemies, true)
	var plan = _plan(snap, ["beta"], enemies)
	var c: Dictionary = _cand("beta", "obj_x")
	_assert(c.get("score_terms", {}).has("reinforce_race"),
		"reinforcing obj_x is costed as a lost race (20 enemy OC vs our 13 with beta): %s" % str(c.get("score_terms", {}).get("reinforce_race", "none")))
	_assert(not _goes_to(plan, "beta", "obj_x"), "beta is not sent to a reinforcement that cannot keep the centre (%s %s)" % [
		str(plan.get("beta", {}).get("action", "")), str(plan.get("beta", {}).get("objective_id", ""))])

func test_reinforcement_the_enemy_cannot_match_is_kept() -> void:
	print("\n--- same, no horde: only the wagon (5) can reach; 4 + 9 OC beats it ---")
	var enemies = {}
	var snap = _board(enemies, false)
	var plan = _plan(snap, ["beta"], enemies)
	var c: Dictionary = _cand("beta", "obj_x")
	_assert(not c.get("score_terms", {}).has("reinforce_race"), "no race cost when the reinforcement wins the race")
	_assert(_goes_to(plan, "beta", "obj_x"), "beta still reinforces obj_x")

# Beta's 24" gun with an enemy 20.4" away (in range, out of M8 + 12" charge reach).
func test_assault_gun_advances_on_long_trip() -> void:
	print("\n--- long trip to obj_side: [ASSAULT] gun vs a gun that cannot fire after Advancing ---")
	var assault_gun := {"name": "spear", "type": "Ranged", "range": "24", "attacks": "2",
		"ballistic_skill": "2", "strength": "4", "ap": "-1", "damage": "2", "special_rules": "assault, rapid fire 2"}
	var plain_gun := assault_gun.duplicate()
	plain_gun["special_rules"] = "rapid fire 2"
	for gun in [assault_gun, plain_gun]:
		var enemies = {}
		var snap = _board(enemies, false, [gun])
		_add_unit(snap, "mek", 2, Vector2(911, 1626), 1, 1, 6, ["INFANTRY", "CHARACTER"])
		enemies["mek"] = snap.units["mek"]
		_plan(snap, ["beta"], enemies)
		var c: Dictionary = _cand("beta", "obj_side")
		if str(gun.special_rules).begins_with("assault"):
			_assert(str(c.get("action", "")) == "advance" and int(c.get("turns_to_reach", 0)) == 2,
				"[ASSAULT] gun: obj_side is a 2-turn Advance trip (%s, %d turns)" % [str(c.get("action", "")), int(c.get("turns_to_reach", 0))])
		else:
			_assert(str(c.get("action", "")) == "move" and int(c.get("turns_to_reach", 0)) == 3,
				"plain gun with a target in range: it walks, 3 turns (%s, %d turns)" % [str(c.get("action", "")), int(c.get("turns_to_reach", 0))])

# Reconnaissance Sweep (3 quarters -> 3 VP, 4 -> 6 at the end of our turn).
# Two more of our units cover the top-left and top-right quarters; beta
# Advancing toward obj_side ends wholly in the bottom-left quarter (the third
# quarter -> +3 VP).
func test_quarter_card_priced_at_the_spot_reached() -> void:
	print("\n--- Reconnaissance Sweep: beta's Advance ends wholly in the third quarter ---")
	var assault_gun := {"name": "spear", "type": "Ranged", "range": "24", "attacks": "2",
		"ballistic_skill": "2", "strength": "4", "ap": "-1", "damage": "2", "special_rules": "assault"}
	var primary := {"card_name": "Reconnaissance Sweep", "active_rules": 2, "quarters": true,
		"objective_pressure": 0.0, "vp_rules": [
			{"when": "eot", "type": "quarters", "min": 3, "vp": 3, "exclusive_group": "quarters_tier"},
			{"when": "eot", "type": "quarters", "min": 4, "vp": 6, "exclusive_group": "quarters_tier"}]}
	var enemies = {}
	var snap = _board(enemies, false, [assault_gun])
	_add_unit(snap, "tl", 1, Vector2(200, 300), 1, 1)
	_add_unit(snap, "tr", 1, Vector2(1500, 300), 1, 1)
	_plan(snap, ["beta"], enemies, primary)
	var side: Dictionary = _cand("beta", "obj_side")
	var x: Dictionary = _cand("beta", "obj_x")
	var q: float = float(side.get("score_terms", {}).get("quarter_vp", 0.0))
	# 3 VP x 1.2 per VP x (1 + 0.5 x 3 later rounds)
	_assert(absf(q - 9.0) < 0.01, "obj_side (Advance, ends wholly in bottom-left): quarter_vp = 9.0 (%.2f)" % q)
	_assert(not side.get("score_terms", {}).has("secondary_spread"), "the flat 4.2 bonus is replaced, not added to")
	_assert(not x.get("score_terms", {}).has("quarter_vp") and not x.get("score_terms", {}).has("secondary_spread"),
		"obj_x (within 6\" of the centre) earns no quarter value")

const RECON := {"card_name": "Reconnaissance Sweep", "active_rules": 2, "quarters": true,
	"objective_pressure": 0.0, "vp_rules": [
		{"when": "eot", "type": "quarters", "min": 3, "vp": 3, "exclusive_group": "quarters_tier"},
		{"when": "eot", "type": "quarters", "min": 4, "vp": 6, "exclusive_group": "quarters_tier"}]}
const ASSAULT_GUN := {"name": "spear", "type": "Ranged", "range": "24", "attacks": "2",
	"ballistic_skill": "2", "strength": "4", "ap": "-1", "damage": "2", "special_rules": "assault"}

# Beta (in the top-left quarter) leads a character standing with it; they are
# the only cover of top-left, "tr" covers top-right. Beta Advancing into the
# bottom-left quarter leaves top-left with it, so the army still covers 2
# quarters — no tier, no quarter_vp (the leader is not "the rest of the army").
func test_attached_leader_moves_with_its_squad() -> void:
	print("\n--- Reconnaissance Sweep: a led squad leaving the quarter it and its leader cover ---")
	var enemies = {}
	var snap = _board(enemies, false, [ASSAULT_GUN])
	_add_unit(snap, "leader", 1, Vector2(450, 960), 1, 1, 6, ["INFANTRY", "CHARACTER"])
	snap.units["beta"]["attachment_data"] = {"attached_characters": ["leader"]}
	_add_unit(snap, "tr", 1, Vector2(1500, 300), 1, 1)
	_plan(snap, ["beta"], enemies, RECON)
	var side: Dictionary = _cand("beta", "obj_side")
	_assert(str(side.get("action", "")) == "advance", "beta Advances toward obj_side (%s)" % str(side.get("action", "")))
	_assert(not side.get("score_terms", {}).has("quarter_vp"),
		"no quarter_vp: its leader leaves top-left with it, 2 quarters either way (%s)" % str(side.get("score_terms", {}).get("quarter_vp", "none")))

# 11e 14.01: the centre objective is a ruin (11.5" x 7") hosting the marker.
# "onarea" stands on the ruin 5" from the marker (in range by the area, out of
# 3.79" of the marker): it is in the objective's enemy_oc, so RI-RACE must not
# add it again. "edge" is 6.4" from the ruin's edge (one M6 + 2" move) but
# 9" from the marker's control range: it can stand there next move.
func test_race_reads_hosting_area() -> void:
	print("\n--- RI-RACE on a terrain-hosted objective (hosting area, not the marker) ---")
	var mm = root.get_node_or_null("MissionManager")
	var tm = root.get_node_or_null("TerrainManager")
	_assert(mm != null and tm != null, "MissionManager / TerrainManager autoloads present")
	if mm == null or tm == null:
		return
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	var prev_terrain = tm.terrain_features.duplicate(true)
	tm.terrain_features = [{"id": "area_x", "piece_class": "area", "type": "ruins",
		"height_category": "tall", "polygon": PackedVector2Array([
			OBJ_X + Vector2(-230, -140), OBJ_X + Vector2(230, -140),
			OBJ_X + Vector2(230, 140), OBJ_X + Vector2(-230, 140)])}]
	var snap = _snapshot()
	snap.board.objectives[0]["source_pieces"] = ["area_x"]
	_add_unit(snap, "onarea", 2, OBJ_X + Vector2(200, 0), 1, 4, 6)
	_add_unit(snap, "edge", 2, OBJ_X + Vector2(230 + 280, 0), 1, 3, 6)
	var enemies = {"onarea": snap.units["onarea"], "edge": snap.units["edge"]}
	var hd_obj: Dictionary = snap.board.objectives[0]
	var objs := [[OBJ_X, hd_obj], [OBJ_SIDE, {}]]
	# Called by name so the file still compiles against a base without it.
	var ai_script: Script = AIDecisionMaker
	var has_helper := false
	for m in ai_script.get_script_method_list():
		if str(m.name) == "_ri_enemy_next_move_oc":
			has_helper = true
	_assert(has_helper, "RI-RACE's next-move reach helper exists")
	var on_area: int = int(ai_script.call("_ri_enemy_next_move_oc", OBJ_X, objs, enemies, hd_obj, mm)) if has_helper else -1
	var on_marker: int = int(ai_script.call("_ri_enemy_next_move_oc", OBJ_X, objs, enemies)) if has_helper else -1
	print("  next-move enemy OC: hosting area %d, marker only %d" % [on_area, on_marker])
	_assert(on_area == 3, "hosting area: only 'edge' (OC 3) is added — 'onarea' is already in enemy_oc (%d)" % on_area)
	_assert(on_marker == 4, "marker-only read (no board entry): counts 'onarea' (1.2\" out) and misses 'edge' (%d)" % on_marker)
	var friendlies = {}
	var objectives = [OBJ_X, OBJ_SIDE]
	var evals = AIDecisionMaker._evaluate_all_objectives(snap, objectives, 1, enemies, friendlies, 2)
	_assert(int(evals[0].enemy_oc) == 4, "'onarea' counted once, in obj_x's enemy_oc (%d)" % int(evals[0].enemy_oc))
	tm.terrain_features = prev_terrain
	GameConstants.edition = prev_edition

func _part_case(sw: String, value: float) -> Dictionary:
	AIDecisionMaker._config_overrides[sw] = value
	var out := {}
	var enemies = {}
	var snap = _board(enemies, true)
	var plan = _plan(snap, ["beta"], enemies)
	out["race"] = _cand("beta", "obj_x").get("score_terms", {}).has("reinforce_race")
	out["reinforces"] = _goes_to(plan, "beta", "obj_x")
	enemies = {}
	snap = _board(enemies, false, [ASSAULT_GUN])
	_add_unit(snap, "mek", 2, Vector2(911, 1626), 1, 1, 6, ["INFANTRY", "CHARACTER"])
	enemies["mek"] = snap.units["mek"]
	_plan(snap, ["beta"], enemies)
	var c: Dictionary = _cand("beta", "obj_side")
	out["assault"] = str(c.get("action", "")) + "/" + str(int(c.get("turns_to_reach", 0)))
	enemies = {}
	snap = _board(enemies, false, [ASSAULT_GUN])
	_add_unit(snap, "tl", 1, Vector2(200, 300), 1, 1)
	_add_unit(snap, "tr", 1, Vector2(1500, 300), 1, 1)
	_plan(snap, ["beta"], enemies, RECON)
	var terms: Dictionary = _cand("beta", "obj_side").get("score_terms", {})
	out["quarter_vp"] = terms.has("quarter_vp")
	out["flat"] = terms.has("secondary_spread")
	AIDecisionMaker._config_overrides[sw] = 1.0
	print("  %s = %.0f: %s" % [sw, value, str(out)])
	return out

func test_param_zero_restores_base() -> void:
	print("\n--- FIX_REINFORCE_INSURANCE = 0 (master) ---")
	var o := _part_case("FIX_REINFORCE_INSURANCE", 0.0)
	_assert(not o.race, "with the fix off there is no race cost")
	_assert(o.reinforces, "with the fix off beta reinforces obj_x as before")
	_assert(o.assault == "move/3", "with the fix off the [ASSAULT] gun walks, 3 turns (%s)" % o.assault)
	_assert(o.flat and not o.quarter_vp, "with the fix off the flat 4.2 secondary_spread returns")

func test_part_switches_remove_only_their_part() -> void:
	print("\n--- each part switch at 0 removes only its part ---")
	var on := _part_case("FIX_RI_RACE", 1.0)
	_assert(on.race and on.assault == "advance/2" and on.quarter_vp and not on.flat, "all parts on: %s" % str(on))
	var r := _part_case("FIX_RI_RACE", 0.0)
	_assert(not r.race and r.reinforces and r.assault == "advance/2" and r.quarter_vp and not r.flat,
		"FIX_RI_RACE = 0: no race cost, beta reinforces; [ASSAULT] and quarters unchanged (%s)" % str(r))
	var a := _part_case("FIX_RI_ASSAULT", 0.0)
	_assert(a.race and a.assault == "move/3" and a.quarter_vp and not a.flat,
		"FIX_RI_ASSAULT = 0: the [ASSAULT] gun walks; race and quarters unchanged (%s)" % str(a))
	var q := _part_case("FIX_RI_QUARTER", 0.0)
	_assert(q.race and q.assault == "advance/2" and q.flat and not q.quarter_vp,
		"FIX_RI_QUARTER = 0: the flat 4.2 returns; race and [ASSAULT] unchanged (%s)" % str(q))
