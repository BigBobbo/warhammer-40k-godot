extends SceneTree

# FIX_MOVE_FOR_SHOT (movement: move so a ranged weapon has a shot next phase —
# 11e 04.02 Select Targets, 06.01 visibility, 13.09 Hidden as errata'd with
# 13.11.01 Gone to Ground, 13.10 Obscuring, 13.11 Solid, 24.24 Lone
# Operative). The enemy does not move between our Movement and Shooting
# phases, so where a normal move ends decides whether the unit shoots at all —
# and the movement planner never asked: every movement-side shooting check
# was a centroid-range test. Exam mv06: Custodian Guard walking straight onto
# obj_center's ruin end with every sight line to the only enemy in range cut
# by the ruin's inner Solid wall or a dense area (the engine says no_los),
# when a 22.5 degree re-angle onto the same objective sees it.
#
# Fix: a target-shaping stage in the normal-move chain, judged on the
# destinations the mover returned (_pick_shot_spot). When the engine
# (RulesEngine.get_eligible_targets on a hypothetical board) finds no
# eligible target there, it proposes a heading fan, a sidestep ring and aimed
# closing steps (range / detection range / Lone Operative / Psychic Veil),
# screens them against every generator stage that would bend them and the
# objective guards, asks the engine about a few, picks the least objective
# loss (ties to expected damage), moves once more and re-asks the engine on
# what comes back (_move_for_shot_recheck); a lost shot keeps the flag-off
# move.
#
# Cases: ON — a sight line round a Solid wall (no_los) / decide() moves for
# the shot with the note and the integrity wording / a step into weapon range
# (out_of_range) / a step inside a Hidden target's detection range (hidden) /
# a step within Lone Operative range / an enemy Attached unit only its
# leader's model can be brought into range of (19.01); param 0 —
# byte-identical decide() output, no note; guards — the straight move already
# has a shot, an enemy Attached unit whose leader alone is in range already
# is a target (both link directions), planned charge, Advance plan,
# melee-only unit, loss cap, control range kept, the objective's OC kept
# (14.02: every model in range counts), probe and pair budgets, the legacy
# cover nudge screened, the F002 hold-fire prediction, a kept FIX_MOVE_COVER
# spot wins; follow-through — the returned destinations are re-checked;
# wording.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_fix_move_for_shot.gd
# (runs once the scene tree is up: the stage reads RulesEngine /
# TerrainManager / MissionManager / GameState)

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const GameStateData = preload("res://autoloads/GameState.gd")
const PX := 40.0  # pixels per inch
const OBJ := Vector2(600, 1200)
const OBJ_FAR := Vector2(660.0, 1700.0)  # the attached-leader cases' open-ground objective
const OBJ_OC := Vector2(660.0, 1200.0)   # the per-model OC case's terrain-hosted objective
const SQUAD_X0 := 530.0  # a 65 px line 530..790
const SQUAD_Y := 900.0   # ~1" north of the ruin's top edge (y 970), bases clear of it
const STEP := 65.0
const SPEAR_R := {"name": "Guardian spear - Ranged", "type": "Ranged", "range": "24", "attacks": "2",
	"ballistic_skill": "2", "strength": "4", "ap": "-1", "damage": "2", "special_rules": "assault"}
const SPEAR_M := {"name": "Guardian spear - Melee", "type": "Melee", "range": "Melee", "attacks": "5",
	"weapon_skill": "2", "strength": "7", "ap": "-2", "damage": "2", "special_rules": ""}
const KNOBS := ["FIX_MOVE_FOR_SHOT", "FIX_MOVE_COVER", "HIDDEN_FORFEIT_PENALTY", "MOVE_FOR_SHOT_MAX_LOSS_INCHES",
	"MOVE_FOR_SHOT_PROBES", "MOVE_FOR_SHOT_MAX_PAIR_CHECKS", "MOVE_COVER_PLAN_WEIGHT"]

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
	print("\n=== FIX_MOVE_FOR_SHOT: move so a ranged weapon has a shot next phase (11e 04.02) ===\n")
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

	test_on_sight_line_round_a_wall()
	test_on_decide_moves_for_the_shot()
	test_on_range_step()
	test_on_hidden_detection_step()
	test_on_lone_operative_step()
	test_on_attached_leader_only_reachable()
	test_param_zero_restores_old_reads()
	test_guard_base_already_has_a_shot()
	test_guard_attached_leader_in_range_unchanged()
	test_guard_charge_advance_melee_unchanged()
	test_guard_loss_cap()
	test_guard_control_range_kept()
	test_guard_objective_oc_kept()
	test_guard_probe_and_pair_budgets()
	test_guard_legacy_nudge_screened()
	test_guard_f002_hold_fire_predicted()
	test_guard_cover_spot_wins()
	test_follow_through_rechecks_returned_destinations()
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

## The objective's ruin: a dense terrain AREA (13.10 obscuring) the size of
## area-large-2, x 460-740, y 970-1430. `y1` trims its south edge (the
## control-range case).
func _ruin(y1: float = 1430.0) -> Dictionary:
	return {"id": "area_obj", "piece_class": "area", "type": "ruins", "category": "dense", "height_category": "tall",
		"can_move_through": {"INFANTRY": true, "MONSTER": false, "VEHICLE": false},
		"polygon": _rect(460.0, 970.0, 740.0, y1)}

## A free-standing dense wall (13.11 Solid feature, no area): ground-level
## sight lines through it are blocked; nothing walks through it.
func _wall(x0: float, y0: float, x1: float, y1: float, id: String = "wall_e") -> Dictionary:
	return {"id": id, "piece_class": "feature", "type": "wall", "category": "dense", "height_category": "tall",
		"can_move_through": {"INFANTRY": false, "MONSTER": false, "VEHICLE": false}, "polygon": _rect(x0, y0, x1, y1)}

## A dense terrain AREA a target can hide in (13.09 as errata'd).
func _hide_area(x0: float, y0: float, x1: float, y1: float) -> Dictionary:
	return {"id": "hide", "piece_class": "area", "type": "ruins", "category": "dense", "height_category": "tall",
		"can_move_through": {"INFANTRY": true, "MONSTER": false, "VEHICLE": false}, "polygon": _rect(x0, y0, x1, y1)}

func _obj_area() -> Dictionary:
	return {"id": "obj_area", "position": OBJ, "zone": "no_mans_land", "source_pieces": ["area_obj"]}

## A dense terrain AREA with its own id (13.10 obscuring; can host an objective).
func _dense_area(id: String, x0: float, y0: float, x1: float, y1: float) -> Dictionary:
	return {"id": id, "piece_class": "area", "type": "ruins", "category": "dense", "height_category": "tall",
		"can_move_through": {"INFANTRY": true, "MONSTER": false, "VEHICLE": false}, "polygon": _rect(x0, y0, x1, y1)}

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

func _add(snap: Dictionary, uid: String, owner: int, positions: Array, weapons: Array = [SPEAR_R, SPEAR_M],
		keywords: Array = ["INFANTRY"], abilities: Array = [], wounds: int = 3) -> Dictionary:
	var models = []
	for i in range(positions.size()):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 40, "base_type": "circular",
			"base_dimensions": {}, "position": positions[i], "wounds": wounds, "current_wounds": wounds})
	var u = {"id": uid, "owner": owner, "status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"name": uid, "points": 150, "stats": {"move": 6, "toughness": 6, "save": 2, "wounds": wounds,
			"leadership": 6, "objective_control": 2}, "keywords": keywords, "weapons": weapons, "abilities": abilities},
		"models": models, "flags": {}, "attachment_data": {"attached_characters": []}}
	snap.units[uid] = u
	return u

func _line(x0: float, y: float, n: int = 5) -> Array:
	var out: Array = []
	for k in range(n):
		out.append(Vector2(x0 + STEP * float(k), y))
	return out

## (a1) the squad ~1" north of the objective's ruin; the only enemy east of
## it, 12.7" edge to edge from the straight end, behind a free-standing Solid
## wall that blocks every line from the straight end; 21" centroid to
## centroid from the squad's start (no planned charge).
func _wall_case(squad_weapons: Array = [SPEAR_R, SPEAR_M]) -> Dictionary:
	var snap = _snapshot([_ruin(), _wall(860.0, 940.0, 880.0, 1080.0)], [_obj_area()])
	_add(snap, "CG", 1, _line(SQUAD_X0, SQUAD_Y), squad_weapons)
	_add(snap, "TGT", 2, _line(1360.0, 1018.0))
	return snap

## Open ground, the objective far south (the straight move is a full 5.7"
## south and still short of it). TGT: a melee-only squad on the south-east
## diagonal, `d` px from the line's middle, its leader LDR 70 px nearer.
## `link`: "attached" (LDR.attached_to + TGT's attached_characters, as
## CharacterAttachmentManager writes it), "backptr" (only LDR.attached_to — real
## saves contain this, RulesEngine.attached_unit_component_ids) or "none" (no
## leader on the board).
func _leader_case(d: float, link: String) -> Dictionary:
	var snap = _snapshot([], [{"id": "obj_far", "position": OBJ_FAR, "zone": "no_mans_land"}])
	_add(snap, "CG", 1, _line(SQUAD_X0, SQUAD_Y))
	var u := Vector2(1.0, 1.0).normalized()
	var perp := Vector2(-u.y, u.x)
	var q: Vector2 = Vector2(660.0, SQUAD_Y) + u * d
	var tpos: Array = []
	for k in range(-2, 3):
		tpos.append(q + perp * STEP * float(k))
	var t = _add(snap, "TGT", 2, tpos, [SPEAR_M])
	if link != "none":
		var l = _add(snap, "LDR", 2, [q - u * 70.0], [SPEAR_M], ["INFANTRY", "CHARACTER"])
		l["attached_to"] = "TGT"
		if link == "attached":
			t["attachment_data"] = {"attached_characters": ["LDR"]}
	return snap

## obj_area hosted by a dense area x 560-760 (14.01); a dense screening area
## east of it from x `x0` blocks every line from the straight end to the only
## enemy (a melee-only line east of the screen). The squad walks south onto
## the objective: 4 of its 5 OC2 models end in range (OC 8).
func _oc_case(x0: float) -> Dictionary:
	var obj := {"id": "obj_area", "position": OBJ_OC, "zone": "no_mans_land", "source_pieces": ["area_obj"]}
	var snap = _snapshot([_dense_area("area_obj", 560.0, 970.0, 760.0, 1430.0),
		_dense_area("screen", x0, 900.0, x0 + 200.0, 1500.0)], [obj])
	_add(snap, "CG", 1, _line(520.0, SQUAD_Y))
	_add(snap, "TGT", 2, _line(1300.0, 1150.0), [SPEAR_M])
	return snap

## 14.02: [models within range of the live objective, their summed OC] for
## uid's models at `dests` (MissionManager's own predicate and model_oc).
func _on_objective(snap: Dictionary, uid: String, dests: Dictionary) -> Array:
	var mm = root.get_node_or_null("MissionManager")
	var obj: Dictionary = gs.state["board"]["objectives"][0]
	var u: Dictionary = _board_at(snap, uid, dests).units[uid]
	var n := 0
	var oc := 0
	for m in u.models:
		if m.get("alive", true) and mm.model_in_objective_range(m, obj):
			n += 1
			oc += int(mm.model_oc(u, m))
	return [n, oc]

func _knob(knob: String, v: float) -> void:
	AIDM._config_overrides[knob] = v

func _fix(v: float) -> void:
	_knob("FIX_MOVE_FOR_SHOT", v)

func _reset() -> void:
	AIDM.reset_caches()
	AIDM.clear_all_plans()
	AIDM.set_ai_seed(7)

## The flag-off destinations exactly as the chain computes them (approach
## target, threat data, weapon range), and the stage called on them.
func _base_dests(snap: Dictionary, uid: String = "CG", target: Vector2 = OBJ) -> Dictionary:
	_reset()
	var unit: Dictionary = snap.units[uid]
	var enemies: Dictionary = AIDM._get_enemy_units(snap, 1)
	var move_target: Vector2 = AIDM._objective_approach_target(unit, target)
	return AIDM._compute_movement_toward_target(unit, uid, move_target, 6.0, snap, enemies,
		AIDM._get_max_weapon_range(unit), AIDM._calculate_enemy_threat_data(enemies), AIDM._get_objectives(snap))

func _pick(snap: Dictionary, uid: String = "CG", target: Vector2 = OBJ, diag: Dictionary = {}) -> Dictionary:
	var base := _base_dests(snap, uid, target)
	diag["base_dests"] = base
	_reset()
	var unit: Dictionary = snap.units[uid]
	var enemies: Dictionary = AIDM._get_enemy_units(snap, 1)
	var move_target: Vector2 = AIDM._objective_approach_target(unit, target)
	return AIDM._pick_shot_spot(unit, uid, snap, AIDM._get_unit_centroid(unit), move_target, target, 6.0, base,
		enemies, AIDM._calculate_enemy_threat_data(enemies), AIDM._get_objectives(snap),
		AIDM._get_max_weapon_range(unit), 1, diag)

## allow_advance = false offers only a Normal move.
func _decide(snap: Dictionary, uid: String = "CG", inject_charge_on: String = "", allow_advance: bool = true) -> Dictionary:
	_reset()
	var board: Dictionary = snap.duplicate(true)
	if inject_charge_on != "":
		AIDM._phase_plan[1] = {"charge_intent": {uid: {"target_id": inject_charge_on, "target_name": inject_charge_on,
			"score": 10.0, "distance_inches": 20.0}}, "lock_targets": [], "shooting_lanes": {},
			"charge_target_ids": [inject_charge_on]}
		AIDM._phase_plan_built[1] = true
		AIDM._phase_plan_round = int(board.get("meta", {}).get("battle_round", 1))
	var actions = [{"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": uid}]
	if allow_advance:
		actions.append({"type": "BEGIN_ADVANCE", "actor_unit_id": uid})
	actions.append({"type": "REMAIN_STATIONARY", "actor_unit_id": uid})
	actions.append({"type": "END_MOVEMENT"})
	return AIDM.decide(7, board, actions, 1)

func _shape(d: Dictionary) -> String:
	return "%s | %s | %s | %s" % [str(d.get("type", "")), str(d.get("_ai_model_destinations", {})),
		str(d.get("_ai_move_adjustments", [])), str(d.get("_ai_description", ""))]

func _translated_dests(unit: Dictionary, delta: Vector2) -> Dictionary:
	var out := {}
	for m in unit.models:
		var p: Vector2 = (m.position as Vector2) + delta
		out[str(m.id)] = [p.x, p.y]
	return out

## Engine truth: the board as it would stand with `uid`'s models at `dests`
## (unengaged, as the Shooting phase refreshes it), and the targets
## RulesEngine.get_eligible_targets accepts there.
func _board_at(snap: Dictionary, uid: String, dests: Dictionary) -> Dictionary:
	var s2: Dictionary = snap.duplicate(true)
	for m in s2.units[uid].models:
		var mid := str(m.id)
		if dests.has(mid):
			m["position"] = Vector2(float(dests[mid][0]), float(dests[mid][1]))
	s2.units[uid].flags["in_engagement"] = false
	return s2

func _elig(snap: Dictionary, uid: String, dests: Dictionary) -> Dictionary:
	return re.get_eligible_targets(uid, _board_at(snap, uid, dests), false)

func _pick_dests(snap: Dictionary, uid: String, pick: Dictionary) -> Dictionary:
	var unit: Dictionary = snap.units[uid]
	return _translated_dests(unit, Vector2(pick.end) - AIDM._get_unit_centroid(unit))

## Does any 40 mm base at `dests` overlap `poly` (a Solid feature's footprint)?
func _base_through_wall(dests: Dictionary, poly: PackedVector2Array) -> bool:
	for mid in dests:
		var p := Vector2(float(dests[mid][0]), float(dests[mid][1]))
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
		for i in range(poly.size()):
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])) < 31.0:
				return true
	return false

func _max_gap_to(snap: Dictionary, uid: String, dests: Dictionary, tid: String) -> float:
	# the smallest edge distance (inches) from any of uid's models at dests to tid
	var best := INF
	for mid in dests:
		var a := Vector2(float(dests[mid][0]), float(dests[mid][1]))
		for tm_m in snap.units[tid].models:
			best = minf(best, (a.distance_to(tm_m.position) - 63.0) / PX)
	return best

# --- (a) ON -----------------------------------------------------------------

func test_on_sight_line_round_a_wall() -> void:
	print("\n--- (a) ON: a sight line round a Solid wall (13.11) the straight move is blind behind ---")
	_fix(1.0)
	var snap = _wall_case()
	var diag := {}
	var pick = _pick(snap, "CG", OBJ, diag)
	var base: Dictionary = diag.get("base_dests", {})
	print("  base dests: %s" % str(base))
	print("  pick: %s" % str({"pos": pick.get("pos"), "end": pick.get("end"), "why": pick.get("why_code"), "loss": pick.get("loss_in"), "ev": pick.get("ev"), "kind": pick.get("kind")}))
	print("  diag: %s" % str({"reachable": diag.get("reachable"), "proposals": diag.get("proposals"), "rej": diag.get("rej"), "survivors": diag.get("survivors"), "probed": diag.get("probed"), "shots": diag.get("shots")}))
	_assert(not base.is_empty() and _elig(snap, "CG", base).is_empty(), "precondition (engine): the straight move has no eligible target")
	_assert(not pick.is_empty(), "fix on: a shot spot is found")
	if pick.is_empty():
		return
	_assert(str(pick.why_code) == "no_los", "the engine's reason the straight move had no shot: no_los (got %s)" % str(pick.why_code))
	_assert(float(pick.loss_in) <= 0.01, "at no cost to objective progress (loss %.2f\")" % float(pick.loss_in))
	_assert(_elig(snap, "CG", _pick_dests(snap, "CG", pick)).has("TGT"), "engine: TGT is an eligible target from the predicted end spot")
	var c: Vector2 = AIDM._get_unit_centroid(snap.units["CG"])
	_assert(c.distance_to(pick.pos) <= 6.0 * PX * 0.95 + 0.01, "the target is within the mover's 0.95 x M cap")
	_assert(int(diag.get("probed", 99)) <= 8, "at most MOVE_FOR_SHOT_PROBES engine probes (%s)" % str(diag.get("probed")))
	# 13.06.01: the engine would accept the 2"-east sidestep that stands m5 IN
	# the wall (13.06 lets INFANTRY through dense features) and would then see
	# out of it — the stage must not claim that.
	var east := _translated_dests(snap.units["CG"], Vector2(80.0, 118.5))
	_assert(_elig(snap, "CG", east).has("TGT"), "precondition (engine): standing a model inside the wall would 'see' TGT")
	_assert(int(diag.get("rej", {}).get("solid", 0)) >= 1, "that spot is screened out (13.06.01; rej.solid=%s)" % str(diag.get("rej", {}).get("solid")))
	_assert(not _base_through_wall(_pick_dests(snap, "CG", pick), _rect(860.0, 940.0, 880.0, 1080.0)),
		"no base ends through the wall at the pick")

func test_on_decide_moves_for_the_shot() -> void:
	print("\n--- (a) ON: decide() moves for the shot, says so, and keeps the objective wording ---")
	_fix(1.0)
	var snap = _wall_case()
	var d = _decide(snap)
	print("  decision: %s" % _shape(d))
	_assert(str(d.get("type", "")) == "BEGIN_NORMAL_MOVE", "fix on: a normal move (got %s)" % str(d.get("type", "")))
	var dests: Dictionary = d.get("_ai_model_destinations", {})
	_assert(_elig(snap, "CG", dests).has("TGT"), "engine: the RETURNED destinations have TGT as an eligible target")
	var adj: Array = d.get("_ai_move_adjustments", [])
	_assert(not adj.is_empty() and str(adj[0]).contains("for a shot next phase"), "the first move-shape note explains it (got %s)" % str(adj))
	_assert(str(d.get("_ai_description", "")).contains("moves toward obj_area"), "the action line still says 'moves toward obj_area' (integrity gate)")
	_assert(str(d.get("_ai_description", "")).contains(", for a shot at TGT"), "the reason names the target")
	var unit_at: Dictionary = _board_at(snap, "CG", dests).units["CG"]
	_assert(AIDM._unit_has_model_in_control_range(unit_at, OBJ), "still in range of obj_area")
	_fix(0.0)
	var d_off = _decide(snap)
	_assert(_elig(snap, "CG", d_off.get("_ai_model_destinations", {})).is_empty(), "flag off on the same board: the move ends blind (the case the fix is for)")
	_fix(1.0)

## (a3) out of range: the target 24.8" from the straight end — an aimed
## closing step (~1.3" further) gets it inside the 24" spear.
func test_on_range_step() -> void:
	print("\n--- (a) ON: a step into weapon range (24.8\" -> inside 24\") ---")
	_fix(1.0)
	var snap = _snapshot([_ruin()], [_obj_area()])
	_add(snap, "CG", 1, _line(SQUAD_X0, SQUAD_Y))
	_add(snap, "TGT", 2, _line(600.0, 2073.0))
	var diag := {}
	var pick = _pick(snap, "CG", OBJ, diag)
	var base: Dictionary = diag.get("base_dests", {})
	print("  base gap to TGT %.2f\"; pick: %s" % [_max_gap_to(snap, "CG", base, "TGT"), str({"end": pick.get("end"), "why": pick.get("why_code"), "kind": pick.get("kind"), "loss": pick.get("loss_in")})])
	print("  diag: %s" % str({"proposals": diag.get("proposals"), "rej": diag.get("rej"), "probed": diag.get("probed"), "shots": diag.get("shots")}))
	_assert(_elig(snap, "CG", base).is_empty() and _max_gap_to(snap, "CG", base, "TGT") > 24.0, "precondition (engine): out of range from the straight end")
	_assert(not pick.is_empty() and str(pick.why_code) == "out_of_range", "a spot is found, why=out_of_range (got %s)" % str(pick.get("why_code", "none")))
	if pick.is_empty():
		return
	_assert(str(pick.kind).begins_with("step:range"), "the aimed range step wins (nearest the straight end; got %s)" % str(pick.kind))
	var pd := _pick_dests(snap, "CG", pick)
	_assert(_elig(snap, "CG", pd).has("TGT") and _max_gap_to(snap, "CG", pd, "TGT") <= 24.0, "engine: within 24\" and eligible from the spot")
	_assert(float(pick.loss_in) <= 0.01, "no objective progress lost")
	var d = _decide(snap, "CG", "", false)
	print("  decide: %s" % _shape(d))
	_assert(_elig(snap, "CG", d.get("_ai_model_destinations", {})).has("TGT"), "decide(): the returned destinations are in range of TGT")
	_assert(str(d.get("_ai_move_adjustments", [])).contains("out of range"), "the note says the straight move would have ended out of range")

## (a4) Hidden: the target INFANTRY inside a dense area 16.7" away, beyond its
## 15" detection range from the straight end (13.09): a step inside it.
func test_on_hidden_detection_step() -> void:
	print("\n--- (a) ON: a step inside a Hidden target's 15\" detection range (13.09) ---")
	_fix(1.0)
	var snap = _snapshot([_ruin(), _hide_area(480.0, 1690.0, 880.0, 1810.0)], [_obj_area()])
	_add(snap, "CG", 1, _line(SQUAD_X0, SQUAD_Y))
	_add(snap, "TGT", 2, _line(540.0, 1750.0))
	var tgt: Dictionary = snap.units["TGT"]
	_assert(bool(tm.is_model_hidden(tgt.models[0], tgt)), "precondition (engine): the target is Hidden (13.09)")
	var diag := {}
	var pick = _pick(snap, "CG", OBJ, diag)
	var base: Dictionary = diag.get("base_dests", {})
	print("  base gap to TGT %.2f\"; pick: %s" % [_max_gap_to(snap, "CG", base, "TGT"), str({"end": pick.get("end"), "why": pick.get("why_code"), "kind": pick.get("kind"), "loss": pick.get("loss_in")})])
	print("  diag: %s" % str({"proposals": diag.get("proposals"), "rej": diag.get("rej"), "probed": diag.get("probed"), "shots": diag.get("shots")}))
	_assert(_elig(snap, "CG", base).is_empty() and _max_gap_to(snap, "CG", base, "TGT") <= 24.0,
		"precondition (engine): in weapon range from the straight end, yet not eligible")
	_assert(not pick.is_empty() and str(pick.why_code) == "hidden", "a spot is found, why=hidden (got %s)" % str(pick.get("why_code", "none")))
	if pick.is_empty():
		return
	var pd := _pick_dests(snap, "CG", pick)
	_assert(_elig(snap, "CG", pd).has("TGT") and _max_gap_to(snap, "CG", pd, "TGT") <= 15.0,
		"engine: inside 15\" and eligible from the spot (%.2f\")" % _max_gap_to(snap, "CG", pd, "TGT"))
	var d = _decide(snap, "CG", "", false)
	print("  decide: %s" % _shape(d))
	_assert(_elig(snap, "CG", d.get("_ai_model_destinations", {})).has("TGT"), "decide(): the returned destinations see the Hidden target")
	_assert(str(d.get("_ai_move_adjustments", [])).contains("detection range"), "the note names the detection range")

## (a5) Lone Operative: a single standalone model 13.5" from the straight end
## can only be targeted from within 12" (24.24).
func test_on_lone_operative_step() -> void:
	print("\n--- (a) ON: a step within Lone Operative range (24.24) ---")
	_fix(1.0)
	var snap = _snapshot([_ruin()], [_obj_area()])
	_add(snap, "CG", 1, _line(SQUAD_X0, SQUAD_Y))
	_add(snap, "TGT", 2, [Vector2(660.0, 1018.5 + 63.0 + 13.5 * PX)], [SPEAR_R, SPEAR_M], ["INFANTRY", "CHARACTER"],
		[{"name": "Lone Operative", "type": "Core"}])
	var diag := {}
	var pick = _pick(snap, "CG", OBJ, diag)
	var base: Dictionary = diag.get("base_dests", {})
	print("  lone op: has=%s range=%s; base gap %.2f\"; pick: %s" % [str(re.has_lone_operative(snap.units["TGT"])),
		str(re.get_lone_operative_range(snap.units["TGT"])), _max_gap_to(snap, "CG", base, "TGT"),
		str({"end": pick.get("end"), "why": pick.get("why_code"), "kind": pick.get("kind")})])
	_assert(bool(re.has_lone_operative(snap.units["TGT"])) and _elig(snap, "CG", base).is_empty(),
		"precondition (engine): a Lone Operative, not targetable from the straight end")
	_assert(not pick.is_empty() and str(pick.why_code) == "lone_operative", "a spot is found, why=lone_operative (got %s)" % str(pick.get("why_code", "none")))
	if pick.is_empty():
		return
	var pd := _pick_dests(snap, "CG", pick)
	_assert(_elig(snap, "CG", pd).has("TGT"), "engine: eligible from the spot (%.2f\")" % _max_gap_to(snap, "CG", pd, "TGT"))

## (a6) an enemy Attached unit whose leader stands nearer than its bodyguard
## (19.01: one unit for all rules purposes; 06.01: one visible model is
## enough). From the straight end the leader is 24.65" away and the bodyguard
## 26.35", both out of the 24" spear's range; no spot within the move gets a
## bodyguard model in range, but a sidestep gets the leader in — and that
## makes TGT an eligible target. Measured to the bodyguard alone, the stage
## saw nothing it could reach and kept the blind straight move.
func test_on_attached_leader_only_reachable() -> void:
	print("\n--- (a) ON: an enemy Attached unit only its leader's model can be brought into range of (19.01) ---")
	_fix(1.0)
	var snap = _leader_case(1370.0, "attached")
	var diag := {}
	var pick = _pick(snap, "CG", OBJ_FAR, diag)
	var base: Dictionary = diag.get("base_dests", {})
	print("  base: bodyguard %.2f\", leader %.2f\"; pick: %s" % [_max_gap_to(snap, "CG", base, "TGT"), _max_gap_to(snap, "CG", base, "LDR"),
		str({"end": pick.get("end"), "target": pick.get("target_id"), "why": pick.get("why_code"), "kind": pick.get("kind"), "loss": pick.get("loss_in")})])
	print("  diag: %s" % str({"reachable": diag.get("reachable"), "proposals": diag.get("proposals"), "rej": diag.get("rej"), "probed": diag.get("probed"), "shots": diag.get("shots")}))
	_assert(_elig(snap, "CG", base).is_empty() and _max_gap_to(snap, "CG", base, "LDR") > 24.0,
		"precondition (engine): no target from the straight end, the leader included")
	_assert(not pick.is_empty() and str(pick.get("target_id", "")) == "TGT" and str(pick.get("why_code", "")) == "out_of_range",
		"a spot is found at TGT, why=out_of_range (got %s / %s)" % [str(pick.get("target_id", "none")), str(pick.get("why_code", ""))])
	var facts: Dictionary = AIDM._mfs_target_facts(re, tm, snap.units["TGT"], "TGT", false, snap)
	_assert((facts.get("models", []) as Array).size() == 6 and re._target_model_entries("TGT", snap).size() == 6,
		"the stage measures to the same 6 models the engine does (5 bodyguards + the leader)")
	if pick.is_empty():
		return
	var pd := _pick_dests(snap, "CG", pick)
	_assert(_elig(snap, "CG", pd).has("TGT") and _max_gap_to(snap, "CG", pd, "TGT") > 24.0,
		"engine: TGT eligible from the spot with only its leader within 24\" (bodyguard %.2f\")" % _max_gap_to(snap, "CG", pd, "TGT"))
	var d = _decide(snap, "CG", "", false)
	print("  decide: %s" % _shape(d))
	_assert(_elig(snap, "CG", d.get("_ai_model_destinations", {})).has("TGT"), "decide(): the returned destinations have TGT eligible")
	_assert(str(d.get("_ai_move_adjustments", [])).contains("for a shot next phase") \
			and str(d.get("_ai_move_adjustments", [])).contains("out of range"), "the note says the straight move would have ended out of range")
	# Control: the same bodyguard with no leader — nothing the move can reach.
	var snap_n = _leader_case(1370.0, "none")
	var diag_n := {}
	var pick_n = _pick(snap_n, "CG", OBJ_FAR, diag_n)
	_assert(pick_n.is_empty(), "control: without the leader there is no shot to move for (the leader's model is what makes it)")

# --- (b) param zero -------------------------------------------------------------

func test_param_zero_restores_old_reads() -> void:
	print("\n--- (b) FIX_MOVE_FOR_SHOT = 0 / unset: decide() is byte-identical; no note ---")
	var snap = _wall_case()
	AIDM._config_overrides.erase("FIX_MOVE_FOR_SHOT")
	var d_unset = _decide(snap)
	_fix(0.0)
	var d_zero = _decide(snap)
	_fix(1.0)
	var d_on = _decide(snap)
	print("  unset: %s" % _shape(d_unset))
	print("  zero : %s" % _shape(d_zero))
	print("  on   : %s" % _shape(d_on))
	_assert(_shape(d_unset) == _shape(d_zero), "0.0 == unset: same type, destinations, notes and description")
	_assert(_shape(d_on) != _shape(d_zero), "on differs (the end spot moved)")
	_assert(not str(d_zero.get("_ai_move_adjustments", [])).contains("for a shot next phase"), "off: no shot note")
	_assert(not str(d_zero.get("_ai_description", "")).contains("for a shot at"), "off: no reason suffix")

# --- (c) guards ---------------------------------------------------------------

func test_guard_base_already_has_a_shot() -> void:
	print("\n--- (c) guard: the straight move already has a shot — unchanged ---")
	_fix(1.0)
	var snap = _snapshot([_ruin()], [_obj_area()])
	_add(snap, "CG", 1, _line(SQUAD_X0, SQUAD_Y))
	_add(snap, "TGT", 2, _line(1360.0, 1018.0))  # (a1) without the wall: in the open, in range
	var diag := {}
	var pick = _pick(snap, "CG", OBJ, diag)
	_assert(_elig(snap, "CG", diag.get("base_dests", {})).has("TGT"), "precondition (engine): the straight move has TGT eligible")
	_assert(pick.is_empty() and bool(diag.get("base_has_shot", false)), "no spot searched (base_has_shot=%s)" % str(diag.get("base_has_shot")))
	var d_on = _decide(snap)
	_fix(0.0)
	var d_off = _decide(snap)
	_fix(1.0)
	_assert(_shape(d_on) == _shape(d_off), "decide(): on == off")

## (c) the review finding: only the enemy Attached unit's LEADER is in range of
## the straight end (bodyguard 24.22", leader 22.53") — the engine says TGT is
## an eligible target (06.01 / 19.01), so the move already has its shot. The
## stage once measured to the bodyguard alone, called it blind, re-aimed it
## (0.1-0.5" of progress given up) and printed a false
## "[FIX_MOVE_FOR_SHOT] ... old=no_shot" tag. That tag is printed only in the
## branch that also pushes the "for a shot next phase" note and the ", for a
## shot at" reason, so on == off with neither present means no tag. Both link
## directions (19.01 forward list; the attached_to back-pointer alone).
func test_guard_attached_leader_in_range_unchanged() -> void:
	print("\n--- (c) guard: an enemy Attached unit whose leader alone is in range is already a target — unchanged ---")
	_fix(1.0)
	for link in ["attached", "backptr"]:
		var snap = _leader_case(1285.0, link)
		var diag := {}
		var pick = _pick(snap, "CG", OBJ_FAR, diag)
		var base: Dictionary = diag.get("base_dests", {})
		print("  %s: bodyguard %.2f\", leader %.2f\"; engine %s; diag %s" % [link, _max_gap_to(snap, "CG", base, "TGT"),
			_max_gap_to(snap, "CG", base, "LDR"), str(_elig(snap, "CG", base).keys()),
			str({"base_candidates": diag.get("base_candidates"), "base_has_shot": diag.get("base_has_shot")})])
		_assert(_max_gap_to(snap, "CG", base, "TGT") > 24.0 and _max_gap_to(snap, "CG", base, "LDR") <= 24.0,
			"%s precondition: only the leader is within 24\" of the straight end" % link)
		_assert(_elig(snap, "CG", base).has("TGT"), "%s precondition (engine): TGT is an eligible target from the straight end" % link)
		_assert(pick.is_empty() and bool(diag.get("base_has_shot", false)) and int(diag.get("base_candidates", 0)) == 1,
			"%s: the stage agrees the straight move has a shot (base_has_shot=%s, pre-filter candidates=%s)" % [
				link, str(diag.get("base_has_shot")), str(diag.get("base_candidates"))])
		var d_on = _decide(snap, "CG", "", false)
		_fix(0.0)
		var d_off = _decide(snap, "CG", "", false)
		_fix(1.0)
		_assert(_shape(d_on) == _shape(d_off), "%s: decide() on == off" % link)
		_assert(not str(d_on.get("_ai_move_adjustments", [])).contains("for a shot next phase") \
				and not str(d_on.get("_ai_description", "")).contains("for a shot at"),
			"%s: no shot note and no reason suffix (so no [FIX_MOVE_FOR_SHOT] tag)" % link)
		# The pick-time belt and braces (should the pre-filter ever drift from
		# the engine again): asked about a target the straight move has, it
		# refuses; about nothing, it does not call the engine at all.
		var bb := _board_at(snap, "CG", base)
		_assert(bool(AIDM._mfs_base_had_target(re, "CG", {"TGT": true}, bb)) \
				and not bool(AIDM._mfs_base_had_target(re, "CG", {}, bb)),
			"%s: the drift guard answers from the engine's target list (TGT: had it; nothing asked: no)" % link)
	var far = _leader_case(1370.0, "attached")
	var far_base := _base_dests(far, "CG", OBJ_FAR)
	_assert(not bool(AIDM._mfs_base_had_target(re, "CG", {"TGT": true}, _board_at(far, "CG", far_base))),
		"the drift guard lets a real no-shot straight move through (leader 24.65\" away)")

func test_guard_charge_advance_melee_unchanged() -> void:
	print("\n--- (c) guard: a planned charge, an Advance plan and a melee-only unit move exactly as before ---")
	# Planned charge: the T7-23 steer owns the move.
	var snap = _wall_case()
	_fix(1.0)
	var c_on = _decide(snap, "CG", "TGT")
	_fix(0.0)
	var c_off = _decide(snap, "CG", "TGT")
	print("  charge on: %s" % _shape(c_on))
	_assert(_shape(c_on) == _shape(c_off), "planned charge: on == off")
	_assert(not str(c_on.get("_ai_move_adjustments", [])).contains("for a shot next phase"), "planned charge: no shot note")
	# Advance plan (10.04 / 10.05): the squad 8" short of the ruin races it.
	var snap_adv = _snapshot([_ruin(), _wall(860.0, 600.0, 880.0, 1080.0)], [_obj_area()])
	_add(snap_adv, "CG", 1, _line(SQUAD_X0, 970.0 - 31.5 - 8.0 * PX))
	_add(snap_adv, "TGT", 2, _line(1360.0, 800.0))
	_fix(1.0)
	var a_on = _decide(snap_adv)
	_fix(0.0)
	var a_off = _decide(snap_adv)
	print("  advance on: %s" % _shape(a_on))
	_assert(str(a_on.get("type", "")) == "BEGIN_ADVANCE", "precondition: the plan advances (got %s)" % str(a_on.get("type", "")))
	_assert(_shape(a_on) == _shape(a_off), "Advance plan: on == off")
	# Melee-only: nothing to shoot with.
	var snap_m = _wall_case([SPEAR_M])
	_fix(1.0)
	var m_on = _decide(snap_m)
	_fix(0.0)
	var m_off = _decide(snap_m)
	_assert(_shape(m_on) == _shape(m_off), "melee-only unit: on == off")
	_fix(1.0)

## An open-ground objective far south (so the straight move is a full 5.7"
## and still short of it), the target east behind a short Solid wall that
## covers the straight end's lines: every spot that sees round the wall gives
## up some progress.
func _loss_case() -> Dictionary:
	var objs := [{"id": "obj_far", "position": Vector2(660.0, 1900.0), "zone": "no_mans_land"}]
	var snap = _snapshot([_wall(1000.0, 1080.0, 1020.0, 1180.0)], objs)
	_add(snap, "CG", 1, _line(SQUAD_X0, SQUAD_Y))
	_add(snap, "TGT", 2, _line(1500.0, 1128.0))
	return snap

func test_guard_loss_cap() -> void:
	print("\n--- (c) guard: the objective-progress loss cap ---")
	_fix(1.0)
	var target := Vector2(660.0, 1900.0)
	var snap = _loss_case()
	_knob("MOVE_FOR_SHOT_MAX_LOSS_INCHES", 3.0)
	var diag3 := {}
	var pick3 = _pick(snap, "CG", target, diag3)
	print("  cap 3\": pick %s loss=%s why=%s; diag rej=%s" % [str(pick3.get("end", "none")), str(pick3.get("loss_in", "")), str(pick3.get("why_code", "")), str(diag3.get("rej"))])
	_assert(_elig(snap, "CG", diag3.get("base_dests", {})).is_empty(), "precondition (engine): the straight move is blind")
	_assert(not pick3.is_empty() and float(pick3.get("loss_in", 0.0)) > 0.05, "cap 3\": a spot that gives up some progress is taken")
	_knob("MOVE_FOR_SHOT_MAX_LOSS_INCHES", 0.0)
	var diag0 := {}
	var pick0 = _pick(snap, "CG", target, diag0)
	print("  cap 0\": pick %s; diag rej=%s" % [str(pick0.get("end", "none")), str(diag0.get("rej"))])
	_assert(pick0.is_empty() and int(diag0.get("rej", {}).get("loss", 0)) >= 1, "cap 0\": no spot, rejected for loss")
	AIDM._config_overrides.erase("MOVE_FOR_SHOT_MAX_LOSS_INCHES")

func test_guard_control_range_kept() -> void:
	print("\n--- (c) guard: never trades away control range the straight move had ---")
	_fix(1.0)
	# (a1) on a thin ruin (y 970-1040) with the wall run north to y 800: the
	# straight end overlaps the ruin and is blind; the spots that see round the
	# wall's south end (2" further south) do not overlap it.
	var snap = _snapshot([_ruin(1040.0), _wall(860.0, 800.0, 880.0, 1080.0)], [_obj_area()])
	_add(snap, "CG", 1, _line(SQUAD_X0, SQUAD_Y))
	_add(snap, "TGT", 2, _line(1360.0, 1018.0))
	var diag := {}
	var pick = _pick(snap, "CG", OBJ, diag)
	var base: Dictionary = diag.get("base_dests", {})
	var base_unit: Dictionary = _board_at(snap, "CG", base).units["CG"]
	var south := _translated_dests(snap.units["CG"], Vector2(0.0, 198.5))
	var south_unit: Dictionary = _board_at(snap, "CG", south).units["CG"]
	print("  pick %s; diag rej=%s" % [str(pick.get("end", "none")), str(diag.get("rej"))])
	_assert(AIDM._unit_has_model_in_control_range(base_unit, OBJ) and _elig(snap, "CG", base).is_empty(),
		"precondition: the straight end is in range and blind")
	_assert(_elig(snap, "CG", south).has("TGT") and not AIDM._unit_has_model_in_control_range(south_unit, OBJ),
		"precondition (engine): 2\" further south sees TGT but leaves the objective")
	_assert(pick.is_empty() and int(diag.get("rej", {}).get("control", 0)) >= 1, "no spot, rejected for lost control range")

## 14.02: the level of control adds up the OC of EVERY model within range, so
## "a model still in range" is not "no cost". The review's case: the straight
## move puts 4 of 5 OC2 models on obj_area (OC 8) and is blind behind a dense
## screen. The stage once took a spot 2" east that keeps ONE model on (gap 0,
## so "loss 0") but walks a second off — OC 8 down to 6 — and said "at no cost
## to objective progress".
func test_guard_objective_oc_kept() -> void:
	print("\n--- (c) guard: never less OC within range of the objective than the straight move (14.02) ---")
	_fix(1.0)
	# Screen at x 865: a spot that keeps all 4 models on AND sees TGT exists.
	var snap = _oc_case(865.0)
	var unit: Dictionary = snap.units["CG"]
	_fix(0.0)
	var d_off = _decide(snap, "CG", "", false)
	_fix(1.0)
	var d_on = _decide(snap, "CG", "", false)
	var off_d: Dictionary = d_off.get("_ai_model_destinations", {})
	var on_d: Dictionary = d_on.get("_ai_model_destinations", {})
	var r_off := _on_objective(snap, "CG", off_d)
	var r_on := _on_objective(snap, "CG", on_d)
	print("  x0 865: off %s on obj_area (models, OC), targets %s | on %s, targets %s" % [str(r_off), str(_elig(snap, "CG", off_d).keys()),
		str(r_on), str(_elig(snap, "CG", on_d).keys())])
	print("  on: %s" % _shape(d_on))
	_assert(_elig(snap, "CG", off_d).is_empty() and int(r_off[0]) == 4 and int(r_off[1]) == 8,
		"precondition: the flag-off move ends blind with 4 models (OC 8) on obj_area")
	# The spot the stage used to take: 2" east of the straight end keeps one
	# model on (gap 0) and sees TGT, but has fewer models in range.
	var c: Vector2 = AIDM._get_unit_centroid(unit)
	var old_spot := _translated_dests(unit, Vector2(730.0, 1019.0) - c)
	var r_old := _on_objective(snap, "CG", old_spot)
	_assert(_elig(snap, "CG", old_spot).has("TGT") and int(r_old[0]) >= 1 and int(r_old[1]) < 8,
		"precondition (engine): the old spot (730,1019) sees TGT with a model still on, but only OC %d" % int(r_old[1]))
	_assert(int(r_on[1]) >= int(r_off[1]), "fix on: OC within range of obj_area is never below the straight move's (%d vs %d)" % [int(r_on[1]), int(r_off[1])])
	_assert(_elig(snap, "CG", on_d).has("TGT"), "fix on: and the move still has TGT as a target (a spot that keeps every model on exists)")
	_assert(str(d_on.get("_ai_move_adjustments", [])).contains("at no cost to objective progress (still OC 8 within range of obj_area)"),
		"the note says what it kept on the objective")
	var diag := {}
	var pick = _pick(snap, "CG", OBJ_OC, diag)
	_assert(int(diag.get("rej", {}).get("oc", 0)) >= 1 and int(diag.get("base_oc", 0)) == 8,
		"spots with fewer models' OC in range are screened out (rej.oc=%s, base_oc=%s)" % [str(diag.get("rej", {}).get("oc")), str(diag.get("base_oc"))])
	if not pick.is_empty():
		var enemies = AIDM._get_enemy_units(snap, 1)
		var chk = AIDM._move_for_shot_recheck(unit, "CG", snap, pick, old_spot, OBJ_OC, enemies)
		print("  re-check on the old spot: keep=%s why=%s" % [str(chk.keep), str(chk.why)])
		_assert(not bool(chk.keep) and str(chk.why).contains("OC"), "the follow-through drops returned destinations that lose OC on the objective")
	# Screen at x 895: every spot with a shot keeps at most 3 models on — the
	# shot is turned down and the straight move stands.
	var snap2 = _oc_case(895.0)
	var diag2 := {}
	var pick2 = _pick(snap2, "CG", OBJ_OC, diag2)
	print("  x0 895: pick %s; rej %s" % [str(pick2.get("end", "none")), str(diag2.get("rej"))])
	_assert(pick2.is_empty() and int(diag2.get("rej", {}).get("oc", 0)) >= 1, "x0 895: no spot keeps the OC, so none is taken (rej.oc)")
	var d2_on = _decide(snap2, "CG", "", false)
	_fix(0.0)
	var d2_off = _decide(snap2, "CG", "", false)
	_fix(1.0)
	_assert(_shape(d2_on) == _shape(d2_off), "x0 895: decide() on == off (the OC is worth more than the chip shot)")

func test_guard_probe_and_pair_budgets() -> void:
	print("\n--- (c) guard: MOVE_FOR_SHOT_PROBES = 0 never probes; the pair budget skips probes ---")
	_fix(1.0)
	var snap = _wall_case()
	_knob("MOVE_FOR_SHOT_PROBES", 0)
	var diag := {}
	var pick = _pick(snap, "CG", OBJ, diag)
	_assert(pick.is_empty() and int(diag.get("probed", -1)) == 0, "PROBES 0: no engine probe, no spot (probed=%s)" % str(diag.get("probed")))
	AIDM._config_overrides.erase("MOVE_FOR_SHOT_PROBES")
	_knob("MOVE_FOR_SHOT_MAX_PAIR_CHECKS", 1)
	var diag2 := {}
	var pick2 = _pick(snap, "CG", OBJ, diag2)
	print("  pair cap 1: diag rej=%s probed=%s" % [str(diag2.get("rej")), str(diag2.get("probed"))])
	_assert(pick2.is_empty() and int(diag2.get("rej", {}).get("budget", 0)) >= 1, "PAIR_CHECKS 1: probes skipped for the budget, no spot")
	AIDM._config_overrides.erase("MOVE_FOR_SHOT_MAX_PAIR_CHECKS")

func test_guard_legacy_nudge_screened() -> void:
	print("\n--- (c) guard: a spot the legacy cover nudge would turn is never sent ---")
	_fix(1.0)
	var target := Vector2(660.0, 1900.0)
	var snap = _loss_case()
	var diag := {}
	var pick = _pick(snap, "CG", target, diag)
	print("  pick %s; diag rej=%s" % [str(pick.get("end", "none")), str(diag.get("rej"))])
	_assert(int(diag.get("rej", {}).get("nudge", 0)) >= 1, "at least one proposal rejected by the cover-nudge mirror")
	if not pick.is_empty():
		var unit: Dictionary = snap.units["CG"]
		var c: Vector2 = AIDM._get_unit_centroid(unit)
		var enemy_c: Array = [AIDM._get_unit_centroid(snap.units["TGT"])]
		_assert(not AIDM._mc_cover_nudge_would_rotate(c, pick.pos, ["INFANTRY"], snap.board.terrain_features, enemy_c, unit),
			"the picked target is one the nudge leaves alone")

## F002 holds fire only while holding fire keeps the unit untargetable: every
## model of it Hidden in the enemy's next turn (06.01 — one visible model makes
## the unit a target; 19.01). The prediction (_mfs_f002_would_hold) asks
## exactly that, so a spot that leaves a model outside the ruin is a shot F002
## really takes, and one that hides all of them for a chip shot is not.
func test_guard_f002_hold_fire_predicted() -> void:
	print("\n--- (c) guard: F002 would hold fire at a Hidden spot for a chip shot — no claim ---")
	_fix(1.0)
	var snap = _wall_case()
	_knob("HIDDEN_FORFEIT_PENALTY", 0.0)
	var pick0 = _pick(snap)
	_assert(not pick0.is_empty(), "F002 off: the spot is found")
	_knob("HIDDEN_FORFEIT_PENALTY", 3.0)
	var unit: Dictionary = snap.units["CG"]
	var enemies: Dictionary = AIDM._get_enemy_units(snap, 1)
	var members: Array = AIDM._move_cover_members(unit, snap)
	var c: Vector2 = AIDM._get_unit_centroid(unit)
	var chip := {"ev": 1.0, "hp": 15.0}  # 0.67 of a 10-point kill: below the 3.0 forfeit
	# Every model inside the ruin (x 460-740, y 970-1430): F002 holds there.
	var inside: Array = AIDM._move_cover_shift(members, Vector2(600.0, 1150.0) - c)
	var at_in: Dictionary = _board_at(snap, "CG", _translated_dests(unit, Vector2(600.0, 1150.0) - c))
	var cost_in: float = AIDM._hidden_forfeit_cost(at_in.units["CG"], enemies, at_in)
	_assert(cost_in > 0.0 and AIDM._mfs_f002_would_hold(unit, members, inside, Vector2(600.0, 1150.0), chip, enemies, snap),
		"every model Hidden next turn, a chip shot: F002 prices the forfeit (%.2f) and the prediction holds fire" % cost_in)
	# One model past the ruin's east edge: the unit is visible, F002 shoots.
	var one_out: Array = inside.duplicate()
	one_out[members.size() - 1] = Vector2(800.0, 1150.0)
	var d_out: Dictionary = _translated_dests(unit, Vector2(600.0, 1150.0) - c)
	d_out[str(members[members.size() - 1].model.id)] = [800.0, 1150.0]
	var at_out: Dictionary = _board_at(snap, "CG", d_out)
	var cost_out: float = AIDM._hidden_forfeit_cost(at_out.units["CG"], enemies, at_out)
	_assert(cost_out == 0.0 and not AIDM._mfs_f002_would_hold(unit, members, one_out, Vector2(600.0, 1150.0), chip, enemies, snap),
		"one model outside: holding fire buys nothing (forfeit %.2f) and the prediction lets it shoot" % cost_out)
	var diag := {}
	var pick3 = _pick(snap, "CG", OBJ, diag)
	print("  F002 3.0: pick %s; diag rej=%s" % [str(pick3.get("end", "none")), str(diag.get("rej"))])
	if not pick3.is_empty():
		var pd := _pick_dests(snap, "CG", pick3)
		var at_pick: Dictionary = _board_at(snap, "CG", pd)
		var cost_pick: float = AIDM._hidden_forfeit_cost(at_pick.units["CG"], enemies, at_pick)
		_assert(cost_pick == 0.0, "any spot kept with F002 on is one where F002 shoots (forfeit there %.2f == 0)" % cost_pick)
	AIDM._config_overrides.erase("HIDDEN_FORFEIT_PENALTY")

func test_guard_cover_spot_wins() -> void:
	print("\n--- (c) guard: a kept FIX_MOVE_COVER spot wins (the stage never runs) ---")
	var snap = _wall_case()
	_knob("FIX_MOVE_COVER", 1.0)
	_knob("HIDDEN_FORFEIT_PENALTY", 3.0)
	_knob("MOVE_COVER_PLAN_WEIGHT", 0.0)
	_fix(0.0)
	var d_mc = _decide(snap)
	_fix(1.0)
	var d_both = _decide(snap)
	print("  cover only: %s" % _shape(d_mc))
	_assert(str(d_mc.get("_ai_move_adjustments", [])).contains("Hidden next turn from") \
			or str(d_mc.get("_ai_description", "")).contains("ending in cover"), "precondition: FIX_MOVE_COVER keeps a spot here")
	_assert(_shape(d_both) == _shape(d_mc), "both on == cover alone")
	AIDM._config_overrides.erase("FIX_MOVE_COVER")
	AIDM._config_overrides.erase("HIDDEN_FORFEIT_PENALTY")
	AIDM._config_overrides.erase("MOVE_COVER_PLAN_WEIGHT")
	var d_shot = _decide(snap)
	_assert(_shape(d_shot) != _shape(d_mc), "control: the shot stage alone moves differently on this board")

# --- (d) follow-through -----------------------------------------------------------

func test_follow_through_rechecks_returned_destinations() -> void:
	print("\n--- (d) follow-through: the shot is judged again on the destinations the mover returns ---")
	_fix(1.0)
	var snap = _wall_case()
	var unit: Dictionary = snap.units["CG"]
	var diag := {}
	var pick = _pick(snap, "CG", OBJ, diag)
	_assert(not pick.is_empty(), "a spot to re-check")
	if pick.is_empty():
		return
	var enemies = AIDM._get_enemy_units(snap, 1)
	var c: Vector2 = AIDM._get_unit_centroid(unit)
	var ok = AIDM._move_for_shot_recheck(unit, "CG", snap, pick, _translated_dests(unit, pick.end - c), OBJ, enemies)
	print("  as predicted: keep=%s target=%s ev=%s" % [str(ok.keep), str(ok.target_id), str(ok.ev)])
	_assert(bool(ok.keep) and str(ok.target_id) == "TGT", "the predicted translation is kept, at TGT")
	var straight = AIDM._move_for_shot_recheck(unit, "CG", snap, pick, diag.get("base_dests", {}), OBJ, enemies)
	print("  straight: keep=%s why=%s" % [str(straight.keep), str(straight.why)])
	_assert(not bool(straight.keep) and str(straight.why).contains("lost every target"), "the straight end: dropped, every target lost")
	var none = AIDM._move_for_shot_recheck(unit, "CG", snap, pick, {}, OBJ, enemies)
	_assert(not bool(none.keep) and str(none.why).contains("no legal placement"), "no destinations: dropped")
	var stay = AIDM._move_for_shot_recheck(unit, "CG", snap, pick, _translated_dests(unit, Vector2.ZERO), OBJ, enemies)
	print("  stayed put: keep=%s why=%s" % [str(stay.keep), str(stay.why)])
	_assert(not bool(stay.keep) and str(stay.why).contains("within range of the objective"), "out of the objective's range the straight move had: dropped")

func test_note_wording() -> void:
	print("\n--- (e) wording: the player-visible note ---")
	_fix(1.0)
	var snap = _wall_case()
	var unit: Dictionary = snap.units["CG"]
	var pick = _pick(snap)
	if pick.is_empty():
		_assert(false, "a spot to describe")
		return
	var enemies = AIDM._get_enemy_units(snap, 1)
	var c: Vector2 = AIDM._get_unit_centroid(unit)
	var ok = AIDM._move_for_shot_recheck(unit, "CG", snap, pick, _translated_dests(unit, pick.end - c), OBJ, enemies)
	var note: String = AIDM._move_for_shot_note(pick, ok, "obj_area")
	print("  note: %s" % note)
	_assert(note.contains("for a shot next phase") and note.contains("TGT is in sight there") \
			and note.contains("at no cost to objective progress"), "names the target, why the straight move was blind, and the cost")
	var lossy: Dictionary = ok.duplicate()
	lossy["loss_in"] = 1.5
	var note2: String = AIDM._move_for_shot_note(pick, lossy, "obj_area")
	_assert(note2.contains("for 1.5\" less progress toward obj_area"), "a lossy spot says how much progress it gives up")
	# 14.02: the straight move stood on the objective, so the note says what
	# the spot keeps there (the re-check's per-model OC).
	_assert(int(ok.get("base_oc", 0)) > 0 and note.contains("(still OC %d within range of obj_area)" % int(ok.oc)),
		"the note says the OC it keeps on the objective (base %s, spot %s)" % [str(ok.get("base_oc")), str(ok.get("oc"))])
	var more: Dictionary = ok.duplicate()
	more["oc"] = int(ok.get("base_oc", 0)) + 2
	var note3: String = AIDM._move_for_shot_note(pick, more, "obj_area")
	_assert(note3.contains("up from %d" % int(ok.get("base_oc", 0))), "a spot with more OC in range says so")
