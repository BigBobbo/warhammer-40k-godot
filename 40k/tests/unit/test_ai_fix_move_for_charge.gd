extends SceneTree

# FIX_MOVE_FOR_CHARGE (movement: end the move inside realistic charge reach of
# the melee target — 11e 11.02 Charge, 11.04 Charge Move, errata FAQ under 02.02
# and errata 02.02.01 on charge rolls, 09.05 Normal Move AFTER MOVING, 03.01,
# 13.06). The 2D6 roll comes first and only an enemy within 12" AND within the
# roll, base to base, can be selected — so where the Normal move before the
# charge ends decides the roll it needs, by the edge gap of the closest pair of
# models. The flag-off moves aim at centroids: the attack move steps straight at
# the target's centroid, the T7-23 steer blends toward it until the centroids
# end within 9". Exam mv07: the attack move ends 5.9" from the target's nearest
# model (a 6+, 72%) when the same step aimed from the closest model at that
# model ends 4.5" away (a 5+, 83%).
#
# Fix: a post-mover stage (_move_for_charge_stage) at the attack branch's
# Normal move and after the T7-23 follow-through. _pick_charge_spot proposes
# rigid translations of the whole unit (aimed lines, objective blends, a fan,
# multi-target midpoints), each cut short just outside engagement range of every
# enemy model (_mfc_max_travel), screens them with the generator mirrors and the
# objective guards, prices each as an option over the 2D6 roll on clean lanes
# (_mfc_eval / _mfc_lane), moves once more toward the best and re-prices what
# comes back (_move_for_charge_recheck); a lost gain keeps the flag-off move.
#
# Cases: ON — the attack move aims by the edge gap (decide, the injected ATTACK
# and the natural chase-gate ATTACK) / the engagement-range ring (a target
# within M + 2") / the lane rules (non-target engagement at the contact point,
# an enemy base across the path, beyond 12", a dense wall a VEHICLE cannot
# cross) / objective mode (a MOVE plan with a planned charge) / a backup target
# in reach, and the backup credit and the per-roll option value each moving
# the pick / an attached leader in front of its bodyguard (the bodyguard leads
# the lane and is priced at the roll the AI's own charge move needs, round the
# leader when it stands on the contact point) / the fire rule screening each
# spot (a non-firing best never vetoes a firing runner-up) / AIRCRAFT (a target
# only for a FLYING charger, 23.04; never a lane blocker, 23.02) / the odds
# (bonus, the 12 cap, free re-roll) / the analytic travel limit; param 0 —
# byte-identical decide() output, no note; guards — Advance plan, a disembark
# charge lock, a target out of reach, the realistic-odds floor, the objective
# loss cap, a unit with no real melee weapon, the move cover / move-for-shot
# fixes on alongside; follow-through — the re-check; wording (the GameEventLog
# integrity regexes).
#
# Run with: godot --headless --path . -s tests/unit/test_ai_fix_move_for_charge.gd

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const GameStateData = preload("res://autoloads/GameState.gd")
const PX := 40.0  # pixels per inch
const STEP := 65.0
const R2 := 63.0  # two 40 mm base radii, px
const OBJ_FAR := Vector2(1020.0, 160.0)  # an open-ground objective far behind the attack-case squad
const SPEAR_R := {"name": "Guardian spear - Ranged", "type": "Ranged", "range": "24", "attacks": "2",
	"ballistic_skill": "2", "strength": "4", "ap": "-1", "damage": "2", "special_rules": "assault"}
const SPEAR_M := {"name": "Guardian spear - Melee", "type": "Melee", "range": "Melee", "attacks": "5",
	"weapon_skill": "2", "strength": "7", "ap": "-2", "damage": "2", "special_rules": ""}
const RIFLE_R := {"name": "Heavy rifle", "type": "Ranged", "range": "24", "attacks": "2",
	"ballistic_skill": "3", "strength": "5", "ap": "-1", "damage": "1", "special_rules": ""}  # strong: not melee-focused
const BOLTGUN := {"name": "Boltgun", "type": "Ranged", "range": "24", "attacks": "1",
	"ballistic_skill": "3", "strength": "4", "ap": "0", "damage": "1", "special_rules": ""}
const CCW := {"name": "Close combat weapon", "type": "Melee", "range": "Melee", "attacks": "2",
	"weapon_skill": "3", "strength": "3", "ap": "0", "damage": "1", "special_rules": ""}
const MELEE := [SPEAR_R, SPEAR_M]   # melee-focused: the chase gate's ATTACK
const MIXED := [RIFLE_R, SPEAR_M]   # not melee-focused, a real melee weapon: MOVE + planned charge
const CCW_ONLY := [BOLTGUN, CCW]    # no real melee weapon
const KNOBS := ["FIX_MOVE_FOR_CHARGE", "FIX_CHARGE_REROLL_ODDS", "FIX_MOVE_COVER", "FIX_MOVE_FOR_SHOT",
	"MOVE_FOR_CHARGE_MAX_LOSS_INCHES", "MOVE_FOR_CHARGE_MIN_ODDS", "MOVE_FOR_CHARGE_MIN_GAIN", "MOVE_FOR_CHARGE_BACKUP_WEIGHT"]

var _pass_count: int = 0
var _fail_count: int = 0
var _ran := false
var AIDM = null
var tm = null
var gs = null
var re = null

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func _run_tests():
	if _ran:
		return
	_ran = true
	await process_frame
	print("\n=== FIX_MOVE_FOR_CHARGE: end the move inside realistic charge reach (11e 11.02 / 11.04) ===\n")
	tm = root.get_node_or_null("TerrainManager")
	gs = root.get_node_or_null("GameState")
	re = root.get_node_or_null("RulesEngine")
	var mm = root.get_node_or_null("MissionManager")
	_assert(tm != null and gs != null and re != null and mm != null, "TerrainManager / GameState / RulesEngine / MissionManager autoloads present")
	if tm == null or gs == null or re == null or mm == null:
		print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
		quit(1)
		return
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	var prev_terrain = tm.terrain_features.duplicate(true)
	if not gs.state.has("board"):
		gs.state["board"] = {}
	var prev_objs = gs.state["board"].get("objectives", []).duplicate(true)
	var had_meta: bool = gs.state.has("meta")
	var prev_meta: Dictionary = gs.state.get("meta", {}).duplicate(true)
	AIDM = load(AI_PATH)

	test_on_attack_edge_aim()
	test_on_attack_natural_chase()
	test_on_attack_er_ring()
	test_lane_rules()
	test_on_objective_steer()
	test_on_drop_useless_steer()
	test_on_backup_in_reach()
	test_on_backup_shapes_the_pick()
	test_attached_leader_lane()
	test_fire_rule_per_spot()
	test_aircraft_targets_and_lanes()
	test_odds_bonus_reroll_and_cap()
	test_max_travel_analytic()
	test_param_zero_restores_old_reads()
	test_guard_advance_unchanged()
	test_guard_cannot_charge_unchanged()
	test_guard_out_of_reach_unchanged()
	test_guard_min_odds_unchanged()
	test_guard_objective_loss_cap()
	test_guard_no_real_melee_weapon_unchanged()
	test_guard_cover_and_shot_fixes_alongside()
	test_follow_through_recheck()
	test_note_wording()

	for k in KNOBS:
		AIDM._config_overrides.erase(k)
	AIDM.reset_caches()
	tm.terrain_features = prev_terrain
	gs.state["board"]["objectives"] = prev_objs
	if had_meta:
		gs.state["meta"] = prev_meta
	else:
		gs.state.erase("meta")
	re.clear_los_memo()
	GameConstants.edition = prev_edition
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 or _pass_count == 0 else 0)

# --- fixtures ---------------------------------------------------------------

func _rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])

## A free-standing dense wall (13.11 Solid feature): non-INFANTRY / BEASTS /
## SWARM / MOBILE models cannot cross it (13.06).
func _wall(x0: float, y0: float, x1: float, y1: float, id: String = "wall") -> Dictionary:
	return {"id": id, "piece_class": "feature", "type": "wall", "category": "dense", "height_category": "tall",
		"height_inches": 5.0, "can_move_through": {"INFANTRY": true, "MONSTER": false, "VEHICLE": false},
		"polygon": _rect(x0, y0, x1, y1)}

## The TM predicates and MissionManager read the LIVE terrain and objectives;
## the mover reads the snapshot's — set both to the same thing.
func _snapshot(pieces: Array, objs: Array, battle_round: int = 2) -> Dictionary:
	tm.terrain_features = pieces.duplicate(true)
	gs.state["board"]["objectives"] = objs.duplicate(true)
	if not gs.state.has("meta"):
		gs.state["meta"] = {}
	gs.state["meta"]["battle_round"] = battle_round
	gs.state["meta"]["active_player"] = 1
	re.clear_los_memo()
	return {"battle_round": battle_round, "meta": {"battle_round": battle_round},
		"board": {"objectives": objs.duplicate(true), "terrain_features": pieces.duplicate(true)}, "units": {}}

func _add(snap: Dictionary, uid: String, owner: int, positions: Array, weapons: Array = MELEE,
		keywords: Array = ["INFANTRY"], wounds: int = 3, flags: Dictionary = {}) -> Dictionary:
	var models = []
	for i in range(positions.size()):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 40, "base_type": "circular",
			"base_dimensions": {}, "position": positions[i], "wounds": wounds, "current_wounds": wounds})
	var u = {"id": uid, "owner": owner, "status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"name": uid, "points": 150, "stats": {"move": 6, "toughness": 6, "save": 2, "wounds": wounds,
			"leadership": 6, "objective_control": 2}, "keywords": keywords, "weapons": weapons, "abilities": []},
		"models": models, "flags": flags.duplicate(), "attachment_data": {"attached_characters": []}}
	snap.units[uid] = u
	return u

func _line(x0: float, y: float, n: int = 5, step: float = STEP) -> Array:
	var out: Array = []
	for k in range(n):
		out.append(Vector2(x0 + step * float(k), y))
	return out

## mv07's geometry on an open board: the charger a 65 px line at y 650
## (x 890..1150), the target a wide 140 px line at y 1120 (x 1160..1720) —
## 10.2" edge to edge, 15.8" centroid to centroid.
func _attack_case(weapons: Array = MELEE, flags: Dictionary = {}) -> Dictionary:
	var snap = _snapshot([], [{"id": "obj_far", "position": OBJ_FAR, "zone": "no_mans_land"}])
	_add(snap, "CG", 1, _line(890.0, 650.0), weapons, ["INFANTRY"], 3, flags)
	_add(snap, "TGT", 2, _line(1160.0, 1120.0, 5, 140.0), [SPEAR_M])
	return snap

func _knob(knob: String, v: float) -> void:
	AIDM._config_overrides[knob] = v

func _fix(v: float) -> void:
	_knob("FIX_MOVE_FOR_CHARGE", v)

func _reset() -> void:
	AIDM.reset_caches()
	AIDM.clear_all_plans()
	AIDM.set_ai_seed(7)

## An ATTACK <tid> plan entry for uid (pass 2.5's shape), so decide() runs the
## attack branch on this board without the objective passes.
func _inject_attack(snap: Dictionary, uid: String, tid: String, advance: bool = false) -> void:
	var rnd := int(snap.get("meta", {}).get("battle_round", 1))
	AIDM._phase_plan[1] = {"charge_intent": {}, "lock_targets": [], "shooting_lanes": {}, "charge_target_ids": []}
	AIDM._phase_plan_built[1] = true
	AIDM._phase_plan_round = rnd
	AIDM._turn_movement_plan[1] = {"round": rnd, "consumed": {}, "replans": 0, "announce": {},
		"assignments": {uid: {"action": "attack", "attack_target_id": tid, "attack_target_name": tid,
			"attack_advance": advance, "objective_id": "obj_far", "objective_pos": OBJ_FAR,
			"reason": "closing to charge range", "score": 10.0, "distance": 600.0}}}

## A planned charge on tid in the phase plan (T7-23's charge_intent).
func _inject_charge(snap: Dictionary, uid: String, tid: String) -> void:
	AIDM._phase_plan[1] = {"charge_intent": {uid: {"target_id": tid, "target_name": tid, "score": 10.0,
		"distance_inches": 15.0}}, "lock_targets": [], "shooting_lanes": {}, "charge_target_ids": [tid]}
	AIDM._phase_plan_built[1] = true
	AIDM._phase_plan_round = int(snap.get("meta", {}).get("battle_round", 1))

## decide() for one unit. attack: inject an ATTACK on attack_tid; charge_on:
## inject a planned charge (the objective passes then plan the unit's MOVE).
## allow_advance = false offers only a Normal move (no Advance plans).
func _decide(snap: Dictionary, uid: String = "CG", attack_tid: String = "", charge_on: String = "",
		allow_advance: bool = false, stationary: bool = false, attack_advance: bool = false) -> Dictionary:
	_reset()
	var board: Dictionary = snap.duplicate(true)
	if attack_tid != "":
		_inject_attack(board, uid, attack_tid, attack_advance)
	elif charge_on != "":
		_inject_charge(board, uid, charge_on)
	var actions = [{"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": uid}]
	if allow_advance:
		actions.append({"type": "BEGIN_ADVANCE", "actor_unit_id": uid})
	if stationary:
		actions.append({"type": "REMAIN_STATIONARY", "actor_unit_id": uid})
	actions.append({"type": "END_MOVEMENT"})
	return AIDM.decide(7, board, actions, 1)

func _shape(d: Dictionary) -> String:
	return "%s | %s | %s | %s" % [str(d.get("type", "")), str(d.get("_ai_model_destinations", {})),
		str(d.get("_ai_move_adjustments", [])), str(d.get("_ai_description", ""))]

## Does any move-shape note of decision `d` contain `text`? (Per element:
## str(Array) escapes the apostrophes the notes use.)
func _adj_has(d: Dictionary, text: String) -> bool:
	for n in d.get("_ai_move_adjustments", []):
		if str(n).contains(text):
			return true
	return false

func _dvec(p) -> Vector2:
	return Vector2(float(p[0]), float(p[1])) if p is Array else Vector2(p)

## Edge gap (inches) from uid's models at dests (or where they stand) to tid's
## nearest model — Measurement's shape-aware distance, the engine's charge
## measure.
func _gap(snap: Dictionary, uid: String, dests: Dictionary, tid: String) -> float:
	var meas = root.get_node_or_null("Measurement")
	var best := INF
	for m in snap.units[uid].models:
		var m2: Dictionary = m.duplicate()
		if dests.has(str(m.id)):
			m2["position"] = _dvec(dests[str(m.id)])
		for e in snap.units[tid].models:
			best = minf(best, float(meas.model_to_model_distance_inches(m2, e)))
	return best

## The closest any of uid's models at dests comes to ANY enemy model (inches).
func _min_enemy_gap(snap: Dictionary, uid: String, dests: Dictionary) -> float:
	var best := INF
	for tid in snap.units:
		if int(snap.units[tid].owner) == int(snap.units[uid].owner):
			continue
		best = minf(best, _gap(snap, uid, dests, tid))
	return best

func _need(gap: float) -> int:
	return ceili(AIDM._charge_roll_needed(gap))

## The flag-off destinations exactly as the attack branch computes them, and
## the stage's pick on them (attack mode).
func _attack_base(snap: Dictionary, uid: String, tid: String) -> Dictionary:
	_reset()
	var unit: Dictionary = snap.units[uid]
	var enemies: Dictionary = AIDM._get_enemy_units(snap, 1)
	return AIDM._compute_movement_toward_target(unit, uid, AIDM._get_unit_centroid(enemies[tid]), 6.0, snap, enemies,
		0.0, [], AIDM._get_objectives(snap))

func _attack_pick(snap: Dictionary, uid: String, tid: String, diag: Dictionary = {}) -> Dictionary:
	var base := _attack_base(snap, uid, tid)
	diag["base_dests"] = base
	_reset()
	var unit: Dictionary = snap.units[uid]
	var enemies: Dictionary = AIDM._get_enemy_units(snap, 1)
	return AIDM._pick_charge_spot(unit, uid, snap, AIDM._get_unit_centroid(unit), "attack", tid, base,
		Vector2.INF, Vector2.INF, 6.0, enemies, [], 0.0, AIDM._get_objectives(snap), diag)

func _pick_positions_dests(snap: Dictionary, uid: String, pick: Dictionary) -> Dictionary:
	var unit: Dictionary = snap.units[uid]
	var delta: Vector2 = Vector2(pick.end) - AIDM._get_unit_centroid(unit)
	var out := {}
	for m in unit.models:
		var p: Vector2 = Vector2(m.position) + delta
		out[str(m.id)] = [p.x, p.y]
	return out

## The pure lane / odds context for hand-built boards.
func _members_at(snap: Dictionary, uid: String) -> Array:
	return AIDM._move_cover_members(snap.units[uid], snap)

func _origins(members: Array) -> Array:
	var out: Array = []
	for mb in members:
		out.append(mb.orig)
	return out

# --- (a) ON: attack mode ----------------------------------------------------

func test_on_attack_edge_aim() -> void:
	print("\n--- (a) ON: the attack move aims by the edge gap, not the centroid (mv07 on an open board) ---")
	_fix(1.0)
	var snap = _attack_case()
	var base := _attack_base(snap, "CG", "TGT")
	var g0 := _gap(snap, "CG", base, "TGT")
	print("  flag-off gap %.2f\" (a %d+)" % [g0, _need(g0)])
	_assert(g0 >= 5.5 and _need(g0) == 6, "precondition: the flag-off attack move ends >= 5.5\" away, a 6+ (got %.2f\")" % g0)
	var d = _decide(snap, "CG", "TGT")
	print("  decision: %s" % _shape(d))
	_assert(str(d.get("type", "")) == "BEGIN_NORMAL_MOVE", "a Normal move (got %s)" % str(d.get("type", "")))
	var dests: Dictionary = d.get("_ai_model_destinations", {})
	var g1 := _gap(snap, "CG", dests, "TGT")
	_assert(g1 <= 5.02 and _need(g1) == 5, "the returned destinations leave a 5+ (%.2f\")" % g1)
	_assert(_min_enemy_gap(snap, "CG", dests) > 2.0, "no model ends within engagement range (09.05; %.2f\")" % _min_enemy_gap(snap, "CG", dests))
	var desc := "P1: " + str(d.get("_ai_description", ""))
	var atk_re := RegEx.new()
	atk_re.compile("^P\\d: (.+?) (?:moves to attack|advances to attack) (.+?) \\(")
	var mt = atk_re.search(desc)
	_assert(mt != null and mt.get_string(2) == "TGT", "the action line passes GameEventLog's atk_re with the target name (got %s)" % (mt.get_string(2) if mt != null else "no match"))
	_assert(desc.contains(", staged for a 5+ charge)"), "the description says it is staged for a 5+ charge")
	var adj: Array = d.get("_ai_move_adjustments", [])
	_assert(not adj.is_empty() and str(adj[0]).contains("this turn's charge needs a 5+"), "the first move-shape note explains it (got %s)" % str(adj))
	_assert(not adj.is_empty() and str(adj[0]).contains("would have needed a 6+"), "and names the straight move's 6+")

func test_on_attack_natural_chase() -> void:
	print("\n--- (a) ON: the natural plan (melee chase gate -> ATTACK) is staged the same way ---")
	_fix(1.0)
	var snap = _attack_case()
	var d = _decide(snap, "CG", "", "", false, true)
	print("  decision: %s" % _shape(d))
	var desc := str(d.get("_ai_description", ""))
	_assert(desc.contains("moves to attack TGT"), "the plan's ATTACK reaches the attack branch (got %s)" % desc)
	var g1 := _gap(snap, "CG", d.get("_ai_model_destinations", {}), "TGT")
	_assert(g1 <= 5.02, "staged for a 5+ (%.2f\")" % g1)

## A target 7.5" straight south of the line: the full move would end inside
## engagement range, so the flag-off move is cut back; the stage stops the
## formation just outside it.
func test_on_attack_er_ring() -> void:
	print("\n--- (a) ON: a target within M + 2\" — stop just outside engagement range ---")
	_fix(1.0)
	var snap = _snapshot([], [{"id": "obj_far", "position": OBJ_FAR, "zone": "no_mans_land"}])
	_add(snap, "CG", 1, _line(890.0, 650.0))
	_add(snap, "TGT", 2, _line(890.0, 650.0 + R2 + 7.5 * PX))
	var diag := {}
	var pick = _attack_pick(snap, "CG", "TGT", diag)
	var base: Dictionary = diag.get("base_dests", {})
	var g0 := _gap(snap, "CG", base, "TGT")
	print("  flag-off gap %.2f\" (a %d+); pick: %s; diag exit=%s rej=%s" % [g0, _need(g0),
		str({"end": pick.get("end"), "kind": pick.get("kind"), "gain": pick.get("gain")}), str(diag.get("exit", "")), str(diag.get("rej", {}))])
	if _need(g0) <= 3:
		_assert(pick.is_empty() and str(diag.get("exit", "")) != "", "the flag-off move already needs a 3+: cheap exit")
	else:
		_assert(not pick.is_empty(), "a spot is found (the flag-off move needs a %d+)" % _need(g0))
	# The mv07 wide line 2.5" nearer (7.7" edge to edge): the centroid-aimed
	# move leaves a 4+; aimed from the closest model, the full step would end
	# inside engagement range, so the stage stops it on the 2.1" ring — a 3+.
	snap = _snapshot([], [{"id": "obj_far", "position": OBJ_FAR, "zone": "no_mans_land"}])
	_add(snap, "CG", 1, _line(890.0, 650.0))
	_add(snap, "TGT", 2, _line(1160.0, 1020.0, 5, 140.0), [SPEAR_M])
	diag = {}
	pick = _attack_pick(snap, "CG", "TGT", diag)
	g0 = _gap(snap, "CG", diag.get("base_dests", {}), "TGT")
	print("  ring case: flag-off gap %.2f\" (a %d+); pick: %s" % [g0, _need(g0),
		str({"end": pick.get("end"), "kind": pick.get("kind"), "gain": pick.get("gain")})])
	_assert(_need(g0) == 4, "precondition: the flag-off attack move leaves a 4+ (%.2f\")" % g0)
	_assert(not pick.is_empty(), "a spot is found")
	if pick.is_empty():
		return
	var pd := _pick_positions_dests(snap, "CG", pick)
	var g1 := _gap(snap, "CG", pd, "TGT")
	_assert(_min_enemy_gap(snap, "CG", pd) >= 2.09, "every member stays >= 2.1\" (ER + margin) from every enemy model (%.3f\")" % _min_enemy_gap(snap, "CG", pd))
	_assert(_need(g1) == 3, "it leaves a 3+ — the best the 2\" ring allows (%.2f\")" % g1)
	var d = _decide(snap, "CG", "TGT")
	var dests: Dictionary = d.get("_ai_model_destinations", {})
	_assert(_need(_gap(snap, "CG", dests, "TGT")) == 3 and _min_enemy_gap(snap, "CG", dests) > 2.0,
		"decide(): the returned destinations leave a 3+ and are unengaged (%.2f\")" % _gap(snap, "CG", dests, "TGT"))

# --- (b) the lane rules -------------------------------------------------------

func test_lane_rules() -> void:
	print("\n--- (b) the lane: non-target engagement, a base in the way, 12\", 13.06 ---")
	_fix(1.0)
	# b1: the contact point of the nearest pair is within engagement range of a
	# non-target unit (SCR) — that lane is blocked, the next pair carries it.
	var snap = _snapshot([], [])
	_add(snap, "CG", 1, [Vector2(600.0, 600.0)])
	_add(snap, "TGT", 2, [Vector2(600.0, 900.0), Vector2(700.0, 900.0)])
	_add(snap, "SCR", 2, [Vector2(470.0, 760.0)])  # 1.7" from the first contact point, 3.1" from the second
	var enemies: Dictionary = AIDM._get_enemy_units(snap, 1)
	var unit: Dictionary = snap.units["CG"]
	var members := _members_at(snap, "CG")
	var ctx: Dictionary = AIDM._mfc_lane_ctx(unit, "CG", snap, enemies)
	var facts: Dictionary = AIDM._mfc_target_facts(unit, snap, enemies, members, "TGT", 6.0)
	var tgt: Dictionary = facts.targets[0]
	var ln: Dictionary = AIDM._mfc_lane(ctx, members, _origins(members), tgt)
	print("  b1 lane: %s" % str({"blocked": ln.get("blocked"), "need": ln.get("need"), "pair": ln.get("pair"), "why": ln.get("why")}))
	_assert(not bool(ln.blocked) and int(ln.pair[1]) == 1 and str(ln.why).contains("SCR"),
		"the nearest lane would end engaged with SCR; the second pair is clean and priced (pair %s)" % str(ln.get("pair")))
	# b2: an enemy model of another unit across the lead model's path (03.01).
	snap = _snapshot([], [])
	_add(snap, "CG", 1, [Vector2(600.0, 600.0)])
	_add(snap, "TGT", 2, [Vector2(600.0, 1000.0)])
	_add(snap, "BLK", 2, [Vector2(600.0, 800.0)])
	enemies = AIDM._get_enemy_units(snap, 1)
	unit = snap.units["CG"]
	members = _members_at(snap, "CG")
	ctx = AIDM._mfc_lane_ctx(unit, "CG", snap, enemies)
	facts = AIDM._mfc_target_facts(unit, snap, enemies, members, "TGT", 6.0)
	ln = AIDM._mfc_lane(ctx, members, _origins(members), facts.targets[0])
	print("  b2 lane: %s" % str(ln))
	_assert(bool(ln.blocked) and str(ln.why).contains("in the way"), "a base across the path blocks the lane (03.01)")
	# b3: beyond 12" (11.02 / 11.04).
	snap = _snapshot([], [])
	_add(snap, "CG", 1, [Vector2(600.0, 600.0)])
	_add(snap, "TGT", 2, [Vector2(600.0, 600.0 + R2 + 12.3 * PX)])
	enemies = AIDM._get_enemy_units(snap, 1)
	unit = snap.units["CG"]
	members = _members_at(snap, "CG")
	ctx = AIDM._mfc_lane_ctx(unit, "CG", snap, enemies)
	facts = AIDM._mfc_target_facts(unit, snap, enemies, members, "TGT", 6.0)
	ln = AIDM._mfc_lane(ctx, members, _origins(members), facts.targets[0])
	_assert(bool(ln.blocked) and str(ln.why).contains("12"), "12.3\" away: out of reach whatever the roll (got %s)" % str(ln.get("why")))
	# b4: a dense wall between a VEHICLE and its target (13.06); INFANTRY passes.
	snap = _snapshot([_wall(560.0, 760.0, 640.0, 780.0)], [])
	_add(snap, "CG", 1, [Vector2(600.0, 600.0)], MELEE, ["VEHICLE"])
	_add(snap, "TGT", 2, [Vector2(600.0, 960.0)])
	enemies = AIDM._get_enemy_units(snap, 1)
	unit = snap.units["CG"]
	members = _members_at(snap, "CG")
	ctx = AIDM._mfc_lane_ctx(unit, "CG", snap, enemies)
	facts = AIDM._mfc_target_facts(unit, snap, enemies, members, "TGT", 6.0)
	ln = AIDM._mfc_lane(ctx, members, _origins(members), facts.targets[0])
	print("  b4 vehicle lane: %s" % str({"blocked": ln.get("blocked"), "why": ln.get("why")}))
	_assert(bool(ln.blocked) and str(ln.why).contains("dense terrain"), "a VEHICLE cannot charge through a dense wall (13.06)")
	snap.units["CG"].meta.keywords = ["INFANTRY"]
	unit = snap.units["CG"]
	ctx = AIDM._mfc_lane_ctx(unit, "CG", snap, enemies)
	ln = AIDM._mfc_lane(ctx, members, _origins(members), facts.targets[0])
	_assert(not bool(ln.blocked), "INFANTRY can (13.06)")

# --- (c) ON: objective mode -------------------------------------------------

## A MIXED squad (strong guns, a real melee weapon: the chase gate leaves its
## MOVE plan alone) heading east for an open-ground objective 20" away, with a
## planned charge on a wide line to the south-east the straight move leaves an
## 8+ from (T7-23 never steers: the centroids are more than M + 12" apart).
func _objective_case(tgt_x: float = 1100.0, tgt_y: float = 1250.0) -> Dictionary:
	var snap = _snapshot([], [{"id": "obj_e", "position": Vector2(1460.0, 900.0), "zone": "no_mans_land"}])
	_add(snap, "CG", 1, _line(530.0, 900.0), MIXED)
	_add(snap, "TGT", 2, _line(tgt_x, tgt_y, 5, 140.0), [SPEAR_M])
	return snap

func test_on_objective_steer() -> void:
	print("\n--- (c) ON: objective mode — steer for the planned charge within the progress budget ---")
	_fix(0.0)
	var snap = _objective_case()
	var d_off = _decide(snap, "CG", "", "TGT")
	var g0 := _gap(snap, "CG", d_off.get("_ai_model_destinations", {}), "TGT")
	print("  off: %s (gap %.2f\", a %d+)" % [_shape(d_off), g0, _need(g0)])
	_assert(str(d_off.get("_ai_description", "")).contains("moves toward obj_e"), "precondition: the plan is MOVE obj_e")
	_assert(_need(g0) >= 8, "precondition: the flag-off move leaves an 8+ or worse (%.2f\")" % g0)
	_fix(1.0)
	var d = _decide(snap, "CG", "", "TGT")
	var dests: Dictionary = d.get("_ai_model_destinations", {})
	var g1 := _gap(snap, "CG", dests, "TGT")
	print("  on : %s (gap %.2f\", a %d+)" % [_shape(d), g1, _need(g1)])
	_assert(_need(g1) <= 6, "the stage leaves a 6+ or better (%.2f\")" % g1)
	_assert(_min_enemy_gap(snap, "CG", dests) > 2.0, "unengaged (09.05)")
	var desc := str(d.get("_ai_description", ""))
	_assert(desc.contains("moves toward obj_e"), "the action line still says 'moves toward obj_e' (integrity gate)")
	_assert(desc.contains(", staged for a %d+ charge on TGT" % _need(g1)), "the reason says it is staged for the charge")
	var adj: Array = d.get("_ai_move_adjustments", [])
	_assert(not adj.is_empty() and str(adj[0]).begins_with("Steered toward its planned charge on TGT") \
		and str(adj[0]).contains("this turn's charge needs a"), "the first note explains the steer (got %s)" % str(adj))
	var act_re := RegEx.new()
	act_re.compile("^P\\d: (.+?) (?:moves toward|advances toward|holds) (obj[a-z_0-9]+)")
	var am = act_re.search("P1: " + desc)
	_assert(am != null and am.get_string(2) == "obj_e", "GameEventLog's act_re still reads obj_e")
	# the progress it gave up: at most MOVE_FOR_CHARGE_MAX_LOSS_INCHES, no extra turn
	var unit: Dictionary = snap.units["CG"]
	var obj := Vector2(1460.0, 900.0)
	var straight: Dictionary = AIDM._compute_movement_toward_target(unit, "CG", AIDM._objective_approach_target(unit, obj), 6.0,
		snap, AIDM._get_enemy_units(snap, 1), 0.0, [], [])
	var u_on: Dictionary = unit.duplicate(true)
	var u_st: Dictionary = unit.duplicate(true)
	for m in u_on.models:
		m.position = _dvec(dests[str(m.id)])
	for m in u_st.models:
		m.position = _dvec(straight[str(m.id)])
	var gap_on: float = AIDM._unit_gap_to_objective_px(u_on, obj)
	var gap_st: float = AIDM._unit_gap_to_objective_px(u_st, obj)
	print("  objective gap: staged %.2f\" vs straight %.2f\"" % [gap_on / PX, gap_st / PX])
	_assert((gap_on - gap_st) / PX <= 3.05, "gives up at most 3\" of progress (%.2f\")" % ((gap_on - gap_st) / PX))
	_assert(ceil(gap_on / 240.0) <= ceil(gap_st / 240.0), "no extra turn to reach the objective")

## A T7-23-style steer that buys too little: the flag-off destinations (here
## fabricated — the whole unit stepped 5.7" at 60 degrees off the objective
## line, toward a target 16" to the south) leave only a 12+ for over 3" of
## objective progress. The stage drops it for the straight objective move.
func test_on_drop_useless_steer() -> void:
	print("\n--- (c) ON: objective mode — drop a steer that buys too little ---")
	_fix(1.0)
	var obj := Vector2(1460.0, 900.0)
	var snap = _snapshot([], [{"id": "obj_e", "position": obj, "zone": "no_mans_land"}])
	_add(snap, "CG", 1, _line(530.0, 900.0), MIXED)
	_add(snap, "TGT", 2, _line(530.0, 900.0 + R2 + 16.0 * PX), [SPEAR_M])
	var unit: Dictionary = snap.units["CG"]
	var c: Vector2 = AIDM._get_unit_centroid(unit)
	var steer := Vector2.from_angle(deg_to_rad(60.0)) * 228.0
	var base := {}
	for m in unit.models:
		var p: Vector2 = Vector2(m.position) + steer
		base[str(m.id)] = [p.x, p.y]
	var g0 := _gap(snap, "CG", base, "TGT")
	print("  steered base: gap %.2f\" (a %d+)" % [g0, _need(g0)])
	_assert(_need(g0) == 12, "precondition: the steer leaves only a 12+ (%.2f\")" % g0)
	_reset()
	var enemies: Dictionary = AIDM._get_enemy_units(snap, 1)
	var aim: Vector2 = AIDM._objective_approach_target(unit, obj)
	var diag := {}
	var pick: Dictionary = AIDM._pick_charge_spot(unit, "CG", snap, c, "objective", "TGT", base, aim, obj, 6.0,
		enemies, [], 0.0, AIDM._get_objectives(snap), diag)
	print("  pick: %s; base_loss %.2f\"; rej %s" % [str({"end": pick.get("end"), "kind": pick.get("kind"), "gain": pick.get("gain")}),
		float(diag.get("base_loss_in", 0.0)), str(diag.get("rej", {}))])
	_assert(float(diag.get("base_loss_in", 0.0)) > 3.0, "precondition: the steer gives up more than 3\" of progress")
	_assert(not pick.is_empty() and str(pick.kind) == "drop", "the stage drops the steer (kind %s)" % str(pick.get("kind", "none")))
	if pick.is_empty():
		return
	var straight: Vector2 = AIDM._projected_move_end(c, aim, 6.0 * 0.95)
	_assert(Vector2(pick.end).distance_to(straight) <= 1.0, "for the straight objective move (end %s vs %s)" % [str(pick.end), str(straight)])
	var chk: Dictionary = AIDM._move_for_charge_recheck(unit, "CG", snap, pick, _pick_positions_dests(snap, "CG", pick), obj)
	_assert(bool(chk.keep), "the re-check keeps it (%s)" % str(chk.get("why", "")))
	var note: String = AIDM._move_for_charge_note(pick, chk, "obj_e")
	print("  note: %s" % note)
	_assert(note.begins_with("Dropped the steer toward its planned charge on TGT: it only bought a 12+ charge (3%)"), "the drop note")
	_assert(not note.contains("this turn's charge needs a"), "no charge claim in a drop note")

# --- (d) ON: a backup target in reach ---------------------------------------

## The planned target A and a weak-melee backup B a little further on: both are
## priced, the announced target's odds are kept, and the note names the backup
## the pick leaves within reach.
func test_on_backup_in_reach() -> void:
	print("\n--- (d) ON: a spot within reach of more than one target ---")
	_fix(1.0)
	var snap = _snapshot([], [{"id": "obj_far", "position": OBJ_FAR, "zone": "no_mans_land"}])
	_add(snap, "CG", 1, _line(890.0, 650.0))
	_add(snap, "TGT", 2, _line(1160.0, 1120.0, 5, 140.0), [SPEAR_M])
	_add(snap, "BKP", 2, _line(700.0, 1130.0, 3, 65.0), [CCW], ["INFANTRY"], 1)
	var diag := {}
	var pick = _attack_pick(snap, "CG", "TGT", diag)
	print("  pick: %s; targets %s" % [str({"end": pick.get("end"), "kind": pick.get("kind"), "gain": pick.get("gain")}), str(diag.get("targets"))])
	_assert(str(diag.get("targets", [])).contains("BKP"), "the backup is priced (within 12\" + M)")
	_assert(not pick.is_empty(), "a spot is found")
	if pick.is_empty():
		return
	var ev: Dictionary = pick.eval
	print("  eval: n_reach=%d p_plan=%.3f backup=%.3f odds=%s" % [int(ev.n_reach), float(ev.p_plan), float(ev.backup), str(ev.odds)])
	_assert(float(ev.p_plan) >= float(pick.base_eval.p_plan) - 0.03, "the announced target's odds are kept (ATTACK TGT)")
	_assert(int(ev.n_reach) >= 2 and float(ev.odds.get("BKP", 0.0)) >= 0.42,
		"precondition for the note: both targets within reach at the pick (n_reach %d, BKP %.3f)" % [int(ev.n_reach), float(ev.odds.get("BKP", 0.0))])
	var d = _decide(snap, "CG", "TGT")
	var adj: Array = d.get("_ai_move_adjustments", [])
	print("  note: %s" % str(adj))
	_assert(not adj.is_empty() and str(adj[0]).contains("also within reach of BKP"), "the note names the backup in reach")

## mv07's board plus a 3-model backup line at (bx..bx+130, by).
func _backup_case(bx: float, by: float, soft: bool) -> Dictionary:
	var snap = _attack_case()
	if soft:
		# Worth MORE than TGT: T3, Sv6+ (the spear's AP-2 leaves no save), W2.
		var b := _add(snap, "BKP", 2, _line(bx, by, 3, 65.0), [CCW], ["INFANTRY"], 2)
		b.meta.stats.toughness = 3
		b.meta.stats.save = 6
	else:
		# Worth half of TGT: W1 (the spear's D2 is capped at 1 per model).
		_add(snap, "BKP", 2, _line(bx, by, 3, 65.0), [CCW], ["INFANTRY"], 1)
	return snap

## Backup pricing must shape WHERE the move ends, not just be reported. (d1)
## The backup credit: a weak backup about 8" west of the edge-aimed spot (an
## 8+ from there); the fan spot 1.5" west of it ties on TGT's 5+ but brings the
## backup a roll nearer — the credit picks it, and with MOVE_FOR_CHARGE_BACKUP_WEIGHT = 0
## (the backup is worth less than TGT, so per roll it never beats it) the pick
## is the no-backup board's. (d2) The per-roll best-target option value: a
## backup worth more than TGT, BACKUP_WEIGHT = 0 — the pick still moves toward
## it (per roll, the best target in reach), keeping TGT's odds at the flag-off
## move's (the plan guard). Dropping either half of the pricing fails one.
func test_on_backup_shapes_the_pick() -> void:
	print("\n--- (d1/d2) ON: the backup credit and the per-roll option value move the pick ---")
	_fix(1.0)
	var p0: Dictionary = _attack_pick(_attack_case(), "CG", "TGT")
	_assert(not p0.is_empty(), "precondition: a pick on the board without the backup")
	if p0.is_empty():
		return
	var e0: Vector2 = p0.end
	print("  no-backup pick: end %s %s" % [str(e0), AIDM._mfc_roll_text(p0.eval)])
	# (d1) the backup credit
	var snap1 := _backup_case(390.0, 900.0, false)
	var d1 := {}
	var p1: Dictionary = _attack_pick(snap1, "CG", "TGT", d1)
	_knob("MOVE_FOR_CHARGE_BACKUP_WEIGHT", 0.0)
	var p1w: Dictionary = _attack_pick(snap1, "CG", "TGT")
	AIDM._config_overrides.erase("MOVE_FOR_CHARGE_BACKUP_WEIGHT")
	_assert(not p1.is_empty() and not p1w.is_empty(), "d1: picks with the default and the zero backup weight")
	if p1.is_empty() or p1w.is_empty():
		return
	print("  d1 default: end %s %s BKP k=%s p=%.3f backup %.3f gain %.3f | weight 0: end %s BKP k=%s p=%.3f" % [str(p1.end),
		AIDM._mfc_roll_text(p1.eval), str(p1.eval.ks.get("BKP", "-")), float(p1.eval.odds.get("BKP", 0.0)), float(p1.eval.backup),
		float(p1.gain), str(p1w.end), str(p1w.eval.ks.get("BKP", "-")), float(p1w.eval.odds.get("BKP", 0.0))])
	_assert(_backup_value(snap1, "BKP") < _backup_value(snap1, "TGT"),
		"d1 precondition: the backup is worth less than TGT (%.2f < %.2f)" % [_backup_value(snap1, "BKP"), _backup_value(snap1, "TGT")])
	_assert(int(p1.eval.k_plan) == int(p0.eval.k_plan), "d1: TGT's roll is the same as without the backup (%d+)" % int(p1.eval.k_plan))
	_assert(Vector2(p1.end).distance_to(e0) > 0.5 * PX, "d1: the backup credit moves the pick off the no-backup spot (%.2f\")" % (Vector2(p1.end).distance_to(e0) / PX))
	_assert(float(p1.eval.odds.get("BKP", 0.0)) > float(p1w.eval.odds.get("BKP", 0.0)) + 0.05,
		"d1: ...to a spot that brings the backup nearer (%.3f vs %.3f)" % [float(p1.eval.odds.get("BKP", 0.0)), float(p1w.eval.odds.get("BKP", 0.0))])
	_assert(Vector2(p1w.end).distance_to(e0) < 0.01 * PX, "d1: with MOVE_FOR_CHARGE_BACKUP_WEIGHT = 0 it is the no-backup pick (%.3f\")" % (Vector2(p1w.end).distance_to(e0) / PX))
	# (d2) the per-roll option value, with the credit off
	var snap2 := _backup_case(390.0, 900.0, true)
	_knob("MOVE_FOR_CHARGE_BACKUP_WEIGHT", 0.0)
	var p2: Dictionary = _attack_pick(snap2, "CG", "TGT")
	AIDM._config_overrides.erase("MOVE_FOR_CHARGE_BACKUP_WEIGHT")
	_assert(not p2.is_empty(), "d2: a pick with the zero backup weight")
	if p2.is_empty():
		return
	var v_t := _backup_value(snap2, "TGT")
	var v_b := _backup_value(snap2, "BKP")
	print("  d2 weight 0: end %s %s BKP k=%s p=%.3f evn %.3f (v TGT %.2f, BKP %.2f)" % [str(p2.end), AIDM._mfc_roll_text(p2.eval),
		str(p2.eval.ks.get("BKP", "-")), float(p2.eval.odds.get("BKP", 0.0)), float(p2.eval.evn), v_t, v_b])
	_assert(v_b > v_t, "d2 precondition: the backup is worth more than TGT (%.2f > %.2f)" % [v_b, v_t])
	_assert(p2.eval.ks.has("BKP") and Vector2(p2.end).distance_to(e0) > 0.5 * PX,
		"d2: the option value alone moves the pick toward the backup (%.2f\" off the no-backup spot)" % (Vector2(p2.end).distance_to(e0) / PX))
	_assert(float(p2.eval.p_plan) >= float(p2.base_eval.p_plan) - 0.03, "d2: TGT's odds stay at the flag-off move's (the plan guard)")
	_assert(float(p2.eval.evn) > float(p2.eval.p_plan) * v_t / v_b + 0.05,
		"d2: the priced value counts the backup on the rolls it is the best target (evn %.3f > TGT alone %.3f)" % [float(p2.eval.evn), float(p2.eval.p_plan) * v_t / v_b])

## A target's value as the stage prices it (facts.targets[].v).
func _backup_value(snap: Dictionary, tid: String) -> float:
	var unit: Dictionary = snap.units["CG"]
	var enemies: Dictionary = AIDM._get_enemy_units(snap, 1)
	var facts: Dictionary = AIDM._mfc_target_facts(unit, snap, enemies, _members_at(snap, "CG"), "TGT", 6.0)
	for tg in facts.targets:
		if str(tg.id) == tid:
			return float(tg.v)
	return -1.0

# --- (j) an attached leader: the bodyguard makes the charge move -------------

## Attach character unit `ch` to bodyguard `bg` (19.01).
func _attach(snap: Dictionary, bg: String, ch: String) -> void:
	snap.units[bg].attachment_data.attached_characters.append(ch)
	snap.units[ch]["attached_to"] = bg

## A 5-model bodyguard row at y 600 (x 900..1160) with an attached 40 mm
## CHARACTER `f_px` (centre to centre) in front of its middle model, and a
## 5-model target row (140 px apart, starting at tx0) `g_in` inches edge to
## edge in front of the leader.
func _leader_case(f_px: float, g_in: float, tx0: float = 750.0) -> Dictionary:
	var snap = _snapshot([], [{"id": "obj_far", "position": OBJ_FAR, "zone": "no_mans_land"}])
	_add(snap, "CG", 1, _line(900.0, 600.0))
	_add(snap, "LDR", 1, [Vector2(1030.0, 600.0 + f_px)], MELEE, ["INFANTRY", "CHARACTER"])
	_attach(snap, "CG", "LDR")
	_add(snap, "TGT", 2, _line(tx0, 600.0 + f_px + R2 + g_in * PX, 5, 140.0), [SPEAR_M])
	return snap

## The first roll (2..12) at which the AI's own charge move (_compute_charge_move,
## the bodyguard's models only) completes a charge on tid; -1 if none.
func _exec_first(snap: Dictionary, uid: String, tid: String) -> int:
	for r in range(2, 13):
		AIDM.reset_caches()
		if str(AIDM._compute_charge_move(snap, uid, r, [tid], 1).get("type", "")) == "APPLY_CHARGE_MOVE":
			return r
	return -1

## The first roll at which the engine lets uid select tid after the roll
## (11.04: within 12" and within the roll, from the whole Attached unit).
func _sel_first(snap: Dictionary, uid: String, tid: String) -> int:
	var tmpl = MoveTypes.get_type("charge")
	for r in range(2, 13):
		if tid in tmpl._targets_within(uid, snap, ChargeMove11e.selectable_distance_ceiling(float(r))):
			return r
	return -1

## The roll the AI really needs: the engine must offer the target AND its own
## charge move must complete.
func _real_roll(snap: Dictionary, uid: String, tid: String) -> int:
	var a := _sel_first(snap, uid, tid)
	var b := _exec_first(snap, uid, tid)
	return -1 if a < 0 or b < 0 else maxi(a, b)

## The lane eval of uid's formation where it stands.
func _eval_here(snap: Dictionary, uid: String, tid: String) -> Dictionary:
	AIDM.reset_caches()
	var unit: Dictionary = snap.units[uid]
	var enemies: Dictionary = AIDM._get_enemy_units(snap, 1)
	var members := _members_at(snap, uid)
	var ctx: Dictionary = AIDM._mfc_lane_ctx(unit, uid, snap, enemies)
	var facts: Dictionary = AIDM._mfc_target_facts(unit, snap, enemies, members, tid, 6.0)
	var ev: Dictionary = AIDM._mfc_eval(ctx, members, _origins(members), facts)
	ev["_members"] = members
	return ev

## The board after decision `d`: each bodyguard model at its destination, the
## attached leader moved by the bodyguard's delta (as MovementPhase does).
func _board_after(snap: Dictionary, d: Dictionary, bg: String, ch: String) -> Dictionary:
	var dests: Dictionary = d.get("_ai_model_destinations", {})
	var after: Dictionary = snap.duplicate(true)
	var delta := Vector2.INF
	for m in after.units[bg].models:
		if dests.has(str(m.id)):
			var to := _dvec(dests[str(m.id)])
			if delta == Vector2.INF:
				delta = to - Vector2(m.position)
			m.position = to
	if delta != Vector2.INF:
		for m in after.units[ch].models:
			m.position = Vector2(m.position) + delta
	return after

func test_attached_leader_lane() -> void:
	print("\n--- (j) an attached leader in front: the bodyguard leads the lane (the AI's charge move moves no leader) ---")
	_fix(1.0)
	# j1: the leader 3" (centre to centre) in front, 5.3" from the target row:
	# the leader makes TGT selectable on a 6, but the bodyguard (8.3" away) must
	# make the move — a 7+, which is what the AI's own charge move needs.
	var snap := _leader_case(120.0, 5.3, 750.0)
	var ev := _eval_here(snap, "CG", "TGT")
	var ln: Dictionary = ev.per.get("TGT", {})
	var members: Array = ev._members
	print("  j1 lane: %s" % str({"need": ln.get("need"), "gap": ln.get("gap"), "gap_char": ln.get("gap_char"), "edge": ln.get("edge"),
		"pair": ln.get("pair"), "detour": ln.get("detour")}))
	_assert(not bool(ln.get("blocked", true)) and not bool(members[int(ln.pair[0])].is_char),
		"j1: the lane is led by a bodyguard model (pair %s), never the attached leader" % str(ln.get("pair")))
	_assert(bool(ln.get("gap_char", false)) and absf(float(ln.gap) - 5.3) < 0.05, "j1: the leader is nearest (gap %.2f\") and still sets the 12\" / within-the-roll measure" % float(ln.get("gap", -1.0)))
	var real := _real_roll(snap, "CG", "TGT")
	print("  j1 stage %d+; engine selects on %d, the AI's charge move first completes on %d" % [int(ev.k_plan), _sel_first(snap, "CG", "TGT"), _exec_first(snap, "CG", "TGT")])
	_assert(int(ev.k_plan) == 7 and int(ev.k_plan) == real, "j1: priced at the roll the AI can really charge on (stage %d+, real %d)" % [int(ev.k_plan), real])
	# j2: the leader stands on the bodyguard's straight contact point (2.3" from
	# the target): the bodyguard has to end round it, and the price says so.
	snap = _leader_case(142.0, 2.3, 750.0)
	ev = _eval_here(snap, "CG", "TGT")
	ln = ev.per.get("TGT", {})
	real = _real_roll(snap, "CG", "TGT")
	print("  j2 lane: detour=%s need=%.3f stage %d+ real %d" % [str(ln.get("detour")), float(ln.get("need", -1.0)), int(ev.k_plan), real])
	_assert(bool(ln.get("detour", false)), "j2: the straight contact point is under the leader's base: the lane ends round it")
	_assert(real > 0 and int(ev.k_plan) == real, "j2: priced at the roll the AI can really charge on (stage %d+, real %d)" % [int(ev.k_plan), real])
	# j3: a sweep of leader offsets and gaps — the price is never below the roll
	# the AI really needs (the finding: it used to claim up to 2 less).
	var n := 0
	var n_low := 0
	var worst := ""
	for f_px in [80.0, 112.0, 142.0]:
		for g_in in [2.45, 3.3, 4.65, 6.1]:
			var s := _leader_case(f_px, g_in, 750.0)
			var e := _eval_here(s, "CG", "TGT")
			var rr := _real_roll(s, "CG", "TGT")
			n += 1
			if rr > int(e.k_plan):
				n_low += 1
				worst = "f=%.0f g=%.2f stage %d+ real %d" % [f_px, g_in, int(e.k_plan), rr]
	_assert(n_low == 0, "j3: never priced below the AI's real roll (%d/%d; %s)" % [n_low, n, worst])
	# j4: decide() — the stage claims only a gain the AI can use, at the roll it
	# can use: the target row off to the side (a real one-roll gain; the old
	# pricing claimed a 3+ here, the AI's real roll after its move was a 4) ...
	snap = _leader_case(112.0, 8.0, 1150.0)
	var d = _decide(snap, "CG", "TGT")
	var desc := str(d.get("_ai_description", ""))
	var re_k := RegEx.new()
	re_k.compile("staged for a (\\d+)\\+ charge")
	var mk = re_k.search(desc)
	var after := _board_after(snap, d, "CG", "LDR")
	var real_after := _real_roll(after, "CG", "TGT")
	print("  j4 decision: %s | real roll after the move %d" % [_shape(d), real_after])
	_assert(mk != null and int(mk.get_string(1)) == real_after, "j4: the claimed %s+ is the roll the AI really needs after the move (%d)" % [
		mk.get_string(1) if mk != null else "none", real_after])
	_assert(_adj_has(d, "its attached leader is nearest, but the bodyguard makes the charge move"), "j4: the note explains why the leader's distance is not the roll")
	# ... and straight ahead, where moving by the leader buys the AI nothing: the
	# stage used to fire there ("old=5+ new=4+" with the real roll 5 either way).
	snap = _leader_case(112.0, 9.0, 1050.0)
	var d_on = _decide(snap, "CG", "TGT")
	_fix(0.0)
	var d_off = _decide(snap, "CG", "TGT")
	_fix(1.0)
	_assert(_shape(d_on) == _shape(d_off), "j4: no gain the AI can use: on == off (got %s)" % str(d_on.get("_ai_description", "")))

# --- (k) the fire rule is per spot --------------------------------------------

## The reviewer's objective-mode board: a MIXED line heading for obj_e, a 3-model
## target 13" to the south. The best-gain spot is a cheap 10+ (17%) blend that
## fails MOVE_FOR_CHARGE_MIN_ODDS; a 9+ (28%) blend that costs more progress
## passes every screen. The 10+ must not veto it.
func _veto_case(tx: float) -> Dictionary:
	var snap = _snapshot([], [{"id": "obj_e", "position": Vector2(1460.0, 900.0), "zone": "no_mans_land"}])
	_add(snap, "CG", 1, _line(530.0, 900.0), MIXED)
	_add(snap, "TGT", 2, _line(tx, 1440.0, 3, 65.0), [SPEAR_M])
	return snap

func _veto_pick(snap: Dictionary, diag: Dictionary) -> Dictionary:
	_reset()
	var unit: Dictionary = snap.units["CG"]
	var enemies: Dictionary = AIDM._get_enemy_units(snap, 1)
	var obj := Vector2(1460.0, 900.0)
	var aim: Vector2 = AIDM._objective_approach_target(unit, obj)
	var base: Dictionary = AIDM._compute_movement_toward_target(unit, "CG", aim, 6.0, snap, enemies, 0.0, [], AIDM._get_objectives(snap))
	diag["base_dests"] = base
	_reset()
	return AIDM._pick_charge_spot(unit, "CG", snap, AIDM._get_unit_centroid(unit), "objective", "TGT", base, aim, obj, 6.0,
		enemies, [], 0.0, AIDM._get_objectives(snap), diag)

func test_fire_rule_per_spot() -> void:
	print("\n--- (k) the fire rule screens each spot: a non-firing best never vetoes a firing runner-up ---")
	_fix(1.0)
	var min_odds: float = AIDM.get_param("MOVE_FOR_CHARGE_MIN_ODDS", AIDM.MOVE_FOR_CHARGE_MIN_ODDS)
	var min_gain: float = AIDM.get_param("MOVE_FOR_CHARGE_MIN_GAIN", AIDM.MOVE_FOR_CHARGE_MIN_GAIN)
	var snap := _veto_case(520.0)
	var diag := {}
	var pick := _veto_pick(snap, diag)
	var top: Dictionary = diag.get("top", {})
	print("  top %s; pick %s; rej %s" % [str(top), str({"end": pick.get("end"), "kind": pick.get("kind"), "gain": pick.get("gain"),
		"roll": AIDM._mfc_roll_text(pick.eval) if pick.has("eval") else "-"}), str(diag.get("rej", {}))])
	_assert(not top.is_empty() and float(top.evn) < min_odds, "precondition: the best-gain spot leaves less than MOVE_FOR_CHARGE_MIN_ODDS (%.3f)" % float(top.get("evn", -1.0)))
	_assert(not pick.is_empty(), "the stage still fires on the runner-up")
	if pick.is_empty():
		return
	_assert(float(pick.eval.evn) >= min_odds and float(pick.gain) >= min_gain,
		"the pick passes the screens itself (option value %.3f, gain %.2f)" % [float(pick.eval.evn), float(pick.gain)])
	_assert(float(top.gain) > float(pick.gain), "and it is a runner-up on gain (%.2f < %.2f)" % [float(pick.gain), float(top.gain)])
	_assert(int(diag.get("rej", {}).get("odds", 0)) >= 1, "the debug counts record the spot the odds screen refused")
	var unit: Dictionary = snap.units["CG"]
	var obj := Vector2(1460.0, 900.0)
	var st: Dictionary = AIDM._move_for_charge_stage(unit, "CG", snap, AIDM._get_unit_centroid(unit), "objective", "TGT", diag.base_dests,
		AIDM._objective_approach_target(unit, obj), obj, 6.0, AIDM._get_enemy_units(snap, 1), [], 0.0, AIDM._get_objectives(snap), "obj_e")
	_assert(not st.is_empty() and str(st.notes[0]).begins_with("Steered toward its planned charge on TGT"),
		"the whole stage keeps it through the re-check (%s)" % ("dropped" if st.is_empty() else str(st.notes[0])))
	# Where the best-gain spot itself fires, it is the pick, exactly as before.
	var d2 := {}
	var p2 := _veto_pick(_veto_case(500.0), d2)
	var top2: Dictionary = d2.get("top", {})
	_assert(not p2.is_empty() and not top2.is_empty() and Vector2(p2.end) == Vector2(top2.p),
		"a best-gain spot that fires is the pick (tx 500: top %s)" % str(top2))

# --- (l) AIRCRAFT (23.02 / 23.04) -------------------------------------------------

## mv07's board plus an enemy VEHICLE / AIRCRAFT / FLY unit JET in reach.
func _aircraft_case(charger_kw: Array) -> Dictionary:
	var snap = _attack_case()
	snap.units["CG"].meta.keywords = charger_kw.duplicate()
	_add(snap, "JET", 2, [Vector2(760.0, 1080.0)], [SPEAR_R], ["VEHICLE", "AIRCRAFT", "FLY"], 10)
	return snap

func test_aircraft_targets_and_lanes() -> void:
	print("\n--- (l) AIRCRAFT: a target only for a FLYING charger (23.04), never a lane blocker (23.02) ---")
	_fix(1.0)
	# l1: which units are priced
	var snap := _aircraft_case(["INFANTRY"])
	var unit: Dictionary = snap.units["CG"]
	var enemies: Dictionary = AIDM._get_enemy_units(snap, 1)
	var f_ground: Dictionary = AIDM._mfc_target_facts(unit, snap, enemies, _members_at(snap, "CG"), "TGT", 6.0)
	var ids_ground: Array = []
	for tg in f_ground.targets:
		ids_ground.append(str(tg.id))
	var snap_fly := _aircraft_case(["INFANTRY", "FLY"])
	var f_fly: Dictionary = AIDM._mfc_target_facts(snap_fly.units["CG"], snap_fly, AIDM._get_enemy_units(snap_fly, 1),
		_members_at(snap_fly, "CG"), "TGT", 6.0)
	var ids_fly: Array = []
	for tg in f_fly.targets:
		ids_fly.append(str(tg.id))
	print("  l1 priced targets: no FLY %s, FLY %s; engine (no FLY): %s" % [str(ids_ground), str(ids_fly),
		str(re.charge_target_ineligibility_reason("CG", "JET", snap))])
	_assert(not ("JET" in ids_ground) and "JET" in ids_fly, "l1: JET is priced for a FLYING charger only (got %s / %s)" % [str(ids_ground), str(ids_fly)])
	# l2: the AIRCRAFT changes nothing for a charger without FLY
	var p_jet: Dictionary = _attack_pick(snap, "CG", "TGT")
	var p_none: Dictionary = _attack_pick(_attack_case(), "CG", "TGT")
	_assert(not p_jet.is_empty() and not p_none.is_empty() and Vector2(p_jet.end).distance_to(Vector2(p_none.end)) < 0.5,
		"l2: no FLY — the same pick as without JET (%s vs %s)" % [str(p_jet.get("end")), str(p_none.get("end"))])
	var d = _decide(snap, "CG", "TGT")
	_assert(not _adj_has(d, "JET") and _adj_has(d, "this turn's charge needs a"), "l2: the note never offers JET (%s)" % str(d.get("_ai_move_adjustments", [])))
	# l3: an AIRCRAFT as the planned target of a charger without FLY: no spot
	var diag := {}
	_reset()
	var base: Dictionary = AIDM._compute_movement_toward_target(unit, "CG", AIDM._get_unit_centroid(enemies["JET"]), 6.0, snap, enemies,
		0.0, [], AIDM._get_objectives(snap))
	var p_air: Dictionary = AIDM._pick_charge_spot(unit, "CG", snap, AIDM._get_unit_centroid(unit), "attack", "JET", base,
		Vector2.INF, Vector2.INF, 6.0, enemies, [], 0.0, AIDM._get_objectives(snap), diag)
	_assert(p_air.is_empty() and str(diag.get("exit", "")) == "aircraft", "l3: no charge spot for an AIRCRAFT it may not select (exit %s)" % str(diag.get("exit", "")))
	# l4: lane check (i) — models can be moved through AIRCRAFT models
	for blk_kw in [["VEHICLE", "AIRCRAFT", "FLY"], ["INFANTRY"]]:
		var s = _snapshot([], [])
		_add(s, "CG", 1, [Vector2(1000.0, 400.0)])
		_add(s, "TGT", 2, [Vector2(1000.0, 860.0)])
		_add(s, "BLK", 2, [Vector2(1000.0, 560.0)], [SPEAR_R], blk_kw, 10)
		var e := _eval_here(s, "CG", "TGT")
		var l4: Dictionary = e.per.get("TGT", {})
		print("  l4 %s across the path: %s" % [str(blk_kw), str({"blocked": l4.get("blocked"), "why": l4.get("why")})])
		if "AIRCRAFT" in blk_kw:
			_assert(not bool(l4.get("blocked", true)), "l4: an AIRCRAFT base across the path does not block the lane (23.02)")
		else:
			_assert(bool(l4.get("blocked", false)) and str(l4.get("why", "")).contains("in the way"), "l4: an INFANTRY base does (03.01)")

# --- (e) the odds ---------------------------------------------------------------

## One charger, one target `gap_in` away in the open; the plan eval there.
func _eval_at(gap_in: float, flags: Dictionary = {}, reroll: bool = false) -> Dictionary:
	var snap = _snapshot([], [])
	_add(snap, "CG", 1, [Vector2(600.0, 600.0)], MELEE, ["INFANTRY"], 3, flags)
	_add(snap, "TGT", 2, [Vector2(600.0, 600.0 + R2 + gap_in * PX)], [SPEAR_M])
	var enemies: Dictionary = AIDM._get_enemy_units(snap, 1)
	var unit: Dictionary = snap.units["CG"]
	var members := _members_at(snap, "CG")
	var ctx: Dictionary = AIDM._mfc_lane_ctx(unit, "CG", snap, enemies)
	var facts: Dictionary = AIDM._mfc_target_facts(unit, snap, enemies, members, "TGT", 6.0)
	if reroll:
		facts["reroll"] = true
	return AIDM._mfc_eval(ctx, members, _origins(members), facts)

func test_odds_bonus_reroll_and_cap() -> void:
	print("\n--- (e) the odds: 2D6, the +N bonus, the 12 cap, a free re-roll ---")
	var e7 := _eval_at(6.5)
	_assert(int(e7.k_plan) == 7 and absf(float(e7.p_plan) - 21.0 / 36.0) < 1e-4, "6.5\" needs a 7+: 58.3%% (got %d+/%.3f)" % [int(e7.k_plan), float(e7.p_plan)])
	_assert(absf(float(e7.evn) - 21.0 / 36.0) < 1e-4, "one target: the option value is its odds")
	var e7b := _eval_at(6.5, {"effect_plus_charge": 1})
	_assert(int(e7b.k_plan) == 6 and absf(float(e7b.p_plan) - 26.0 / 36.0) < 1e-4, "+1 to the roll: a 6+, 72.2%% (got %d+/%.3f)" % [int(e7b.k_plan), float(e7b.p_plan)])
	var e12 := _eval_at(12.4, {"effect_plus_charge": 2})
	_assert(not bool(e12.plan_ok) and float(e12.p_plan) == 0.0, "12.4\" is out of reach even with +2 (11.02: within 12\"; errata 02.02.01: never more than 12)")
	var e11 := _eval_at(11.5, {"effect_plus_charge": 1})
	_assert(int(e11.k_plan) == 11 and absf(float(e11.p_plan) - 3.0 / 36.0) < 1e-4, "11.5\" with +1: an 11+, 8.3%% (got %d+/%.3f)" % [int(e11.k_plan), float(e11.p_plan)])
	var er := _eval_at(6.5, {}, true)
	var want := 1.0 - pow(15.0 / 36.0, 2.0)
	_assert(absf(float(er.p_plan) - want) < 1e-4, "a free re-roll: 1 - 0.417^2 = %.3f (got %.3f)" % [want, float(er.p_plan)])
	# The re-roll is priced only with FIX_CHARGE_REROLL_ODDS on, as the charge
	# phase prices it.
	var snap = _snapshot([], [])
	_add(snap, "CG", 1, [Vector2(600.0, 600.0)], MELEE, ["INFANTRY"], 3, {"effect_reroll_charge": true})
	_add(snap, "TGT", 2, [Vector2(600.0, 900.0)], [SPEAR_M])
	var members := _members_at(snap, "CG")
	AIDM._config_overrides.erase("FIX_CHARGE_REROLL_ODDS")
	var f_off: Dictionary = AIDM._mfc_target_facts(snap.units["CG"], snap, AIDM._get_enemy_units(snap, 1), members, "TGT", 6.0)
	_knob("FIX_CHARGE_REROLL_ODDS", 1.0)
	var f_on: Dictionary = AIDM._mfc_target_facts(snap.units["CG"], snap, AIDM._get_enemy_units(snap, 1), members, "TGT", 6.0)
	AIDM._config_overrides.erase("FIX_CHARGE_REROLL_ODDS")
	_assert(not bool(f_off.reroll) and bool(f_on.reroll), "free re-roll priced only with FIX_CHARGE_REROLL_ODDS on")

func test_max_travel_analytic() -> void:
	print("\n--- (e) the travel limit: analytic first contact with the engagement-range ring ---")
	var origins: Array = [Vector2(600.0, 600.0), Vector2(665.0, 600.0), Vector2(730.0, 600.0)]
	var radii: Array = [31.5, 31.5, 31.5]
	var enemy_models: Array = [{"pos": Vector2(700.0, 900.0), "r": 31.5}, {"pos": Vector2(500.0, 820.0), "r": 31.5}]
	var clear := 2.1 * PX
	var worst := 0.0
	var seed_rng := RandomNumberGenerator.new()
	seed_rng.seed = 11
	for k in range(24):
		var h := Vector2.from_angle(seed_rng.randf_range(0.0, TAU))
		var s: float = AIDM._mfc_max_travel(origins, radii, h, 240.0, enemy_models, clear)
		# brute force: 1 px steps until any member is inside a ring
		var brute := 240.0
		var t := 0.0
		while t <= 240.0:
			var hit := false
			for i in range(origins.size()):
				for ek in enemy_models:
					if (Vector2(origins[i]) + h * t).distance_to(ek.pos) < float(radii[i]) + float(ek.r) + clear:
						hit = true
			if hit:
				brute = maxf(0.0, t - 1.0)
				break
			t += 1.0
		worst = maxf(worst, absf(s - brute))
	_assert(worst <= 1.0, "matches brute-force 1 px sampling on 24 headings (worst %.2f px)" % worst)

# --- (f) param 0 -----------------------------------------------------------------

func test_param_zero_restores_old_reads() -> void:
	print("\n--- (f) FIX_MOVE_FOR_CHARGE = 0 / unset: decide() is byte-identical; no note ---")
	for case_name in ["attack", "objective", "leader"]:
		var snap = _attack_case() if case_name == "attack" else (_objective_case() if case_name == "objective" else _leader_case(112.0, 9.0, 1150.0))
		var atk := "" if case_name == "objective" else "TGT"
		var chg := "TGT" if case_name == "objective" else ""
		AIDM._config_overrides.erase("FIX_MOVE_FOR_CHARGE")
		var d_unset = _decide(snap, "CG", atk, chg)
		_fix(0.0)
		var d_zero = _decide(snap, "CG", atk, chg)
		_fix(1.0)
		var d_on = _decide(snap, "CG", atk, chg)
		print("  %s unset: %s" % [case_name, _shape(d_unset)])
		print("  %s on   : %s" % [case_name, _shape(d_on)])
		_assert(_shape(d_unset) == _shape(d_zero), "%s: 0.0 == unset (type, destinations, notes, description)" % case_name)
		_assert(_shape(d_on) != _shape(d_zero), "%s: on differs (the end spot moved)" % case_name)
		_assert(_adj_has(d_on, "this turn's charge needs a"), "%s: on: the charge note (the anchor the off check looks for)" % case_name)
		_assert(not _adj_has(d_zero, "this turn's charge needs a"), "%s: off: no charge note" % case_name)
		_assert(not str(d_zero.get("_ai_description", "")).contains("staged for a"), "%s: off: no 'staged for a' suffix" % case_name)

# --- (g) guards -------------------------------------------------------------------

func test_guard_advance_unchanged() -> void:
	print("\n--- (g) guard: an Advance plan is untouched (09.06) ---")
	var snap = _attack_case()
	_fix(1.0)
	var d_on = _decide(snap, "CG", "TGT", "", true, false, true)
	_fix(0.0)
	var d_off = _decide(snap, "CG", "TGT", "", true, false, true)
	_fix(1.0)
	_assert(str(d_on.get("type", "")) == "BEGIN_ADVANCE", "the ATTACK plan with attack_advance Advances (got %s)" % str(d_on.get("type", "")))
	_assert(_shape(d_on) == _shape(d_off), "on == off")

func test_guard_cannot_charge_unchanged() -> void:
	print("\n--- (g) guard: a unit the engine says cannot charge (a Rapid Disembark lock, 18.04) ---")
	var snap = _attack_case(MELEE, {"cannot_charge": true})
	_assert(not bool(re.eligible_to_charge("CG", snap)), "precondition (engine): not eligible to declare a charge")
	_fix(1.0)
	var d_on = _decide(snap, "CG", "TGT")
	_fix(0.0)
	var d_off = _decide(snap, "CG", "TGT")
	_fix(1.0)
	_assert(_shape(d_on) == _shape(d_off), "on == off")

func test_guard_out_of_reach_unchanged() -> void:
	print("\n--- (g) guard: the target stays more than 12\" away from every spot ---")
	var snap = _snapshot([], [{"id": "obj_far", "position": OBJ_FAR, "zone": "no_mans_land"}])
	_add(snap, "CG", 1, _line(890.0, 650.0))
	_add(snap, "TGT", 2, _line(1160.0, 650.0 + R2 + 18.5 * PX, 5, 140.0), [SPEAR_M])
	_fix(1.0)
	var d_on = _decide(snap, "CG", "TGT")
	_fix(0.0)
	var d_off = _decide(snap, "CG", "TGT")
	_fix(1.0)
	_assert(_gap(snap, "CG", d_on.get("_ai_model_destinations", {}), "TGT") > 12.0, "precondition: more than 12\" after the move")
	_assert(_shape(d_on) == _shape(d_off), "on == off (no reachable target anywhere)")

func test_guard_min_odds_unchanged() -> void:
	print("\n--- (g) guard: a spot must leave realistic odds (MOVE_FOR_CHARGE_MIN_ODDS) ---")
	var snap = _attack_case()
	_fix(1.0)
	_knob("MOVE_FOR_CHARGE_MIN_ODDS", 0.9)
	var d_on = _decide(snap, "CG", "TGT")
	_fix(0.0)
	var d_off = _decide(snap, "CG", "TGT")
	_fix(1.0)
	AIDM._config_overrides.erase("MOVE_FOR_CHARGE_MIN_ODDS")
	_assert(_shape(d_on) == _shape(d_off), "with the floor at 0.9 the 5+ (83%) spot does not fire: on == off")

func test_guard_objective_loss_cap() -> void:
	print("\n--- (g) guard: objective mode never gives up more than MOVE_FOR_CHARGE_MAX_LOSS_INCHES ---")
	var snap = _objective_case()
	_fix(1.0)
	_knob("MOVE_FOR_CHARGE_MAX_LOSS_INCHES", 0.0)
	var unit: Dictionary = snap.units["CG"]
	var obj := Vector2(1460.0, 900.0)
	var d_on = _decide(snap, "CG", "", "TGT")
	var dests: Dictionary = d_on.get("_ai_model_destinations", {})
	var straight: Dictionary = AIDM._compute_movement_toward_target(unit, "CG", AIDM._objective_approach_target(unit, obj), 6.0,
		snap, AIDM._get_enemy_units(snap, 1), 0.0, [], [])
	var u_on: Dictionary = unit.duplicate(true)
	var u_st: Dictionary = unit.duplicate(true)
	for m in u_on.models:
		m.position = _dvec(dests[str(m.id)])
	for m in u_st.models:
		m.position = _dvec(straight[str(m.id)])
	var loss_in := (float(AIDM._unit_gap_to_objective_px(u_on, obj)) - float(AIDM._unit_gap_to_objective_px(u_st, obj))) / PX
	print("  on (cap 0\"): %s; loss %.2f\"" % [_shape(d_on), loss_in])
	_assert(loss_in <= 0.05, "with the cap at 0\" the move gives up no progress (%.2f\")" % loss_in)
	AIDM._config_overrides.erase("MOVE_FOR_CHARGE_MAX_LOSS_INCHES")

func test_guard_no_real_melee_weapon_unchanged() -> void:
	print("\n--- (g) guard: a unit with no real melee weapon keeps the T7-23 path ---")
	var snap = _objective_case()
	snap.units["CG"].meta.weapons = CCW_ONLY.duplicate(true)
	_fix(1.0)
	var d_on = _decide(snap, "CG", "", "TGT")
	_fix(0.0)
	var d_off = _decide(snap, "CG", "", "TGT")
	_fix(1.0)
	_assert(_shape(d_on) == _shape(d_off), "on == off")

func test_guard_cover_and_shot_fixes_alongside() -> void:
	print("\n--- (g) guard: FIX_MOVE_COVER / FIX_MOVE_FOR_SHOT on too — the charge stage still decides ---")
	var snap = _objective_case()
	_fix(1.0)
	var d_only = _decide(snap, "CG", "", "TGT")
	_knob("FIX_MOVE_COVER", 1.0)
	_knob("FIX_MOVE_FOR_SHOT", 1.0)
	var d_all = _decide(snap, "CG", "", "TGT")
	AIDM._config_overrides.erase("FIX_MOVE_COVER")
	AIDM._config_overrides.erase("FIX_MOVE_FOR_SHOT")
	_assert(_adj_has(d_all, "this turn's charge needs a"), "the charge note is there")
	_assert(not _adj_has(d_all, "for a shot next phase") and not _adj_has(d_all, "Hidden") and not _adj_has(d_all, "in cover"),
		"no shot / cover note (they never run with a planned charge)")
	_assert(_shape(d_all) == _shape(d_only), "same decision as the charge stage alone")

# --- (h) follow-through --------------------------------------------------------

func test_follow_through_recheck() -> void:
	print("\n--- (h) follow-through: the returned destinations are re-priced ---")
	_fix(1.0)
	var snap = _attack_case()
	var diag := {}
	var pick = _attack_pick(snap, "CG", "TGT", diag)
	_assert(not pick.is_empty(), "a pick to re-check")
	if pick.is_empty():
		return
	var unit: Dictionary = snap.units["CG"]
	var chk_base: Dictionary = AIDM._move_for_charge_recheck(unit, "CG", snap, pick, diag.get("base_dests", {}), Vector2.INF)
	_assert(not bool(chk_base.keep) and str(chk_base.why) != "", "handed back the flag-off destinations it refuses: %s" % str(chk_base.why))
	var chk_pick: Dictionary = AIDM._move_for_charge_recheck(unit, "CG", snap, pick, _pick_positions_dests(snap, "CG", pick), Vector2.INF)
	_assert(bool(chk_pick.keep), "handed the predicted spot it keeps it (%s)" % str(chk_pick.get("why", "")))
	var chk_none: Dictionary = AIDM._move_for_charge_recheck(unit, "CG", snap, pick, {}, Vector2.INF)
	_assert(not bool(chk_none.keep) and str(chk_none.why).contains("no legal placement"), "no destinations: dropped")

# --- (i) wording -------------------------------------------------------------------

func test_note_wording() -> void:
	print("\n--- (i) wording: the note anchors ---")
	_fix(1.0)
	var snap = _attack_case()
	var diag := {}
	var pick = _attack_pick(snap, "CG", "TGT", diag)
	if pick.is_empty():
		_assert(false, "a pick for the wording checks")
		return
	var unit: Dictionary = snap.units["CG"]
	var chk: Dictionary = AIDM._move_for_charge_recheck(unit, "CG", snap, pick, _pick_positions_dests(snap, "CG", pick), Vector2.INF)
	var note: String = AIDM._move_for_charge_note(pick, chk, "obj_far")
	print("  attack note: %s" % note)
	_assert(note.begins_with("Stops ") and note.contains("from TGT's nearest model so this turn's charge needs a 5+ on 2D6 (83%)"), "attack note")
	# objective-mode and drop notes, from the same pick re-labelled
	var p2: Dictionary = pick.duplicate()
	p2["mode"] = "objective"
	var obj_note: String = AIDM._move_for_charge_note(p2, chk, "obj_far")
	print("  objective note: %s" % obj_note)
	_assert(obj_note.begins_with("Steered toward its planned charge on TGT") and obj_note.contains("this turn's charge needs a 5+")
		and obj_note.contains("at no cost to objective progress"), "objective note")
	p2["kind"] = "drop"
	p2["base_loss_in"] = 2.5
	var drop_note: String = AIDM._move_for_charge_note(p2, chk, "obj_far")
	print("  drop note: %s" % drop_note)
	_assert(drop_note.begins_with("Dropped the steer toward its planned charge on TGT: it only bought a 6+ charge (72%)")
		and drop_note.contains("2.5\" of progress toward obj_far"), "drop note")
