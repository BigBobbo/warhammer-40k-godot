extends SceneTree

# FIX_MOVE_COVER (movement: end the move Hidden or in cover — 11e 13.08,
# 13.09 as errata'd, 13.11.01 Gone to Ground). A normal move toward the plan
# objective used to end wherever the straight approach put it: the legacy
# cover nudge only asks whether SOME polygon lies between the end point and
# SOME enemy centroid, and F001 (WEIGHT_HIDDEN_GAINED, off) prices one centroid
# probe. Exam mv05: Custodian Guard approaching obj_nml_1's ruin stops with the
# 5th model's base outside it — 4 of 5 Hidden, so 06.01 makes the whole unit
# targetable — when a 1.4" shift west hides all five and puts every centre in
# the ruin at no cost to the objective.
#
# Fix: a target-shaping stage in the normal-move chain (_pick_cover_spot)
# proposes formation fits into nearby terrain areas plus a heading fan — all
# held to the disc the move can reach (0.95 x M) — screens every proposal
# against the generator stages that would bend it, scores the survivors with
# TerrainManager's own predicates against EVERY enemy shooter that can reach
# the unit next turn (their M + max range), caps the objective progress it may
# give up, and re-checks the RETURNED destinations (_move_cover_recheck, which
# re-derives the kind); plus a "cover_gain" plan prior (ships at 0). Hidden is
# credited only where it survives our own shooting phase: no target in range,
# or F002 would hold fire there (the shot on offer is worth less than the
# forfeit, in F002's own currency).
#
# Cases: ON — the spot hides every model / decide() ends Hidden with the note
# and the integrity wording / a full-length move slides along the reachable
# arc into a ruin beside the straight end / Gone to Ground's -3" behind a dense
# wall / F002 or no target / a worthwhile target means no Hidden credit, and
# the shooting phase agrees / every reaching shooter is counted (past the
# sight-line cap, and one only the spot brings into reach) / an [INDIRECT FIRE]
# shooter is never blinded / a non-INFANTRY attached character rules Hidden and
# in-area cover out / an INFANTRY one moves with the unit and is Hidden too /
# the quiet threat dodge gives the same answer; param 0 — byte-identical
# decide() output, no cover_gain term; guards — no threat, loss cap, extra
# turn, lost control range, VEHICLE (where the stage WOULD act for INFANTRY)
# and charge-intent units unchanged; follow-through — the returned
# destinations are re-checked and the kind re-derived; plan — cover_gain lands
# in score_terms and keeps the ledger when its weight is set, absent at the v1
# default.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_fix_move_cover.gd
# (runs once the scene tree is up: the fix reads TerrainManager /
# MissionManager / GameState)

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const GameStateData = preload("res://autoloads/GameState.gd")
const PX := 40.0  # pixels per inch
const OBJ := Vector2(600, 1200)
const HALF := Vector2(140, 230)  # the objective's ruin: x 460-740, y 970-1430 (area-large-2's size)
const SQUAD_Y := 850.0           # 2.2" north of the ruin's top edge, bases clear of it
const SQUAD_X0 := 530.0          # a 65 px line 530..790: m5's base is past the east edge (740)
const STEP := 65.0
const SPEAR_R := {"name": "Guardian spear - Ranged", "type": "Ranged", "range": "24", "attacks": "2",
	"ballistic_skill": "2", "strength": "4", "ap": "-1", "damage": "2", "special_rules": "assault"}
const SPEAR_M := {"name": "Guardian spear - Melee", "type": "Melee", "range": "Melee", "attacks": "5",
	"weapon_skill": "2", "strength": "7", "ap": "-2", "damage": "2", "special_rules": ""}
const LAUNCHER := {"name": "Indirect launcher", "type": "Ranged", "range": "24", "attacks": "D6",
	"ballistic_skill": "4", "strength": "5", "ap": "0", "damage": "1", "special_rules": "indirect fire"}
const PISTOL := {"name": "Laspistol", "type": "Ranged", "range": "12", "attacks": "1",
	"ballistic_skill": "4", "strength": "3", "ap": "0", "damage": "1", "special_rules": "pistol"}
const BOLTER := {"name": "Boltgun", "type": "Ranged", "range": "24", "attacks": "2",
	"ballistic_skill": "3", "strength": "4", "ap": "0", "damage": "1", "special_rules": ""}
const KNOBS := ["FIX_MOVE_COVER", "HIDDEN_FORFEIT_PENALTY", "MOVE_COVER_MAX_LOSS_INCHES", "MOVE_COVER_LOSS_WEIGHT",
	"MOVE_COVER_PLAN_WEIGHT"]

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
	print("\n=== FIX_MOVE_COVER: end the normal move Hidden or in cover (11e 13.08 / 13.09) ===\n")
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

	test_on_spot_puts_every_model_hidden()
	test_on_decide_movement_ends_hidden()
	test_on_full_length_move_slides_along_the_arc()
	test_on_gone_to_ground_window()
	test_on_hidden_needs_f002_or_no_target()
	test_on_hidden_only_where_f002_holds_fire()
	test_on_every_reaching_shooter_counted()
	test_on_indirect_shooter_never_blind()
	test_on_attached_character_counted()
	test_on_attached_infantry_character_hidden_too()
	test_on_quiet_dodge_same_answer()
	test_param_zero_restores_old_reads()
	test_guard_no_threat_no_divert()
	test_guard_loss_cap()
	test_guard_turns_to_reach()
	test_guard_control_range_kept()
	test_guard_vehicle_and_charge_unchanged()
	test_follow_through_rechecks_returned_destinations()
	test_follow_through_rederives_the_kind()
	test_plan_cover_gain_term()

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

## The objective's ruin: a dense terrain AREA the size of area-large-2.
func _ruin() -> Dictionary:
	return {"id": "area_obj", "piece_class": "area", "type": "ruins", "category": "dense", "height_category": "tall",
		"can_move_through": {"INFANTRY": true, "MONSTER": false, "VEHICLE": false},
		"polygon": _rect(OBJ.x - HALF.x, OBJ.y - HALF.y, OBJ.x + HALF.x, OBJ.y + HALF.y)}

## A dense wall INSIDE the ruin, across its middle: between the squad (north
## half) and a shooter to the south — the Gone-to-Ground case (13.11.01).
func _wall() -> Dictionary:
	return {"id": "wall", "piece_class": "feature", "type": "ruins", "category": "dense", "height_category": "tall",
		"parent_area_id": "area_obj", "can_move_through": {"INFANTRY": true, "MONSTER": false, "VEHICLE": false},
		"polygon": _rect(462.0, 1200.0, 738.0, 1215.0)}

## An exposed crater area (13.03: in-area cover, never Hidden, never obscures).
func _crater(x0: float, y0: float, x1: float, y1: float) -> Dictionary:
	return {"id": "crater", "piece_class": "area", "type": "crater", "category": "exposed", "height_category": "low",
		"can_move_through": {"INFANTRY": true, "MONSTER": true, "VEHICLE": true}, "polygon": _rect(x0, y0, x1, y1)}

func _obj_area() -> Dictionary:
	return {"id": "obj_area", "position": OBJ, "zone": "no_mans_land", "source_pieces": ["area_obj"]}

## The TM predicates and MissionManager read the LIVE terrain and objectives;
## the mover reads the snapshot's — set both to the same thing.
func _snapshot(pieces: Array, objs: Array, battle_round: int = 2) -> Dictionary:
	tm.terrain_features = pieces.duplicate(true)
	gs.state["board"]["objectives"] = objs.duplicate(true)
	re.clear_los_memo()
	return {"battle_round": battle_round, "meta": {"battle_round": battle_round},
		"board": {"objectives": objs.duplicate(true), "terrain_features": pieces.duplicate(true)}, "units": {}}

func _add(snap: Dictionary, uid: String, owner: int, positions: Array, weapons: Array = [SPEAR_R, SPEAR_M],
		keywords: Array = ["INFANTRY"], toughness: int = 6, wounds: int = 3, save: int = 2) -> Dictionary:
	var models = []
	for i in range(positions.size()):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 40, "base_type": "circular",
			"base_dimensions": {}, "position": positions[i], "wounds": wounds, "current_wounds": wounds})
	var u = {"id": uid, "owner": owner, "status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"name": uid, "points": 150, "stats": {"move": 6, "toughness": toughness, "save": save, "wounds": wounds,
			"leadership": 6, "objective_control": 2}, "keywords": keywords, "weapons": weapons},
		"models": models, "flags": {}, "attachment_data": {"attached_characters": []}}
	snap.units[uid] = u
	return u

## A dense ruin AREA with an explicit footprint (the full-length case).
func _ruin_at(id: String, poly: PackedVector2Array) -> Dictionary:
	return {"id": id, "piece_class": "area", "type": "ruins", "category": "dense", "height_category": "tall",
		"can_move_through": {"INFANTRY": true, "MONSTER": false, "VEHICLE": false}, "polygon": poly}

## A free-standing dense wall (13.11 solid feature, no area): sight lines
## through it are blocked, so a unit behind it is not fully visible (13.08
## second bullet) — the one kind of cover a VEHICLE can get.
func _solo_wall(x0: float, y0: float, x1: float, y1: float) -> Dictionary:
	return {"id": "solo_wall", "piece_class": "feature", "type": "wall", "category": "dense", "height_category": "tall",
		"can_move_through": {"INFANTRY": false, "MONSTER": false, "VEHICLE": false}, "polygon": _rect(x0, y0, x1, y1)}

func _ids(threats: Array) -> Array:
	var out: Array = []
	for e in threats:
		out.append(str(e.id))
	return out

## The board as it stands after the move: `uid`'s models at `dests`.
func _apply_dests(snap: Dictionary, uid: String, dests: Dictionary) -> Dictionary:
	var s2: Dictionary = snap.duplicate(true)
	for m in s2.units[uid].models:
		var mid := str(m.id)
		if dests.has(mid):
			m["position"] = Vector2(float(dests[mid][0]), float(dests[mid][1]))
	return s2

## Our own shooting phase right after the move (battle round 2, player 1):
## what does the AI do with `uid`? F002 is consulted here, so this is the
## ground truth for "would it shoot its Hidden away".
func _shooting_choice(board: Dictionary, uid: String = "CG") -> Dictionary:
	if not gs.state.has("meta"):
		gs.state["meta"] = {}
	gs.state["meta"]["battle_round"] = 2
	gs.state["meta"]["active_player"] = 1
	_reset()
	return AIDM.decide(8, board, [{"type": "SELECT_SHOOTER", "actor_unit_id": uid}], 1)

func _line(x0: float, y: float, n: int = 5) -> Array:
	var out: Array = []
	for k in range(n):
		out.append(Vector2(x0 + STEP * float(k), y))
	return out

## Exam mv05's geometry on the synthetic ruin: the squad north of it, one
## enemy shooter south of it in the open.
func _base_case(shooter_y: float = 2010.0, shooter_x0: float = 540.0, with_wall: bool = false,
		shooter_weapons: Array = [SPEAR_R, SPEAR_M]) -> Dictionary:
	var pieces: Array = [_ruin()]
	if with_wall:
		pieces.append(_wall())
	var snap = _snapshot(pieces, [_obj_area()])
	_add(snap, "CG", 1, _line(SQUAD_X0, SQUAD_Y))
	_add(snap, "SHOOTER", 2, _line(shooter_x0, shooter_y), shooter_weapons)
	return snap

func _knob(knob: String, v: float) -> void:
	AIDM._config_overrides[knob] = v

func _fix(v: float, f002: float = 3.0) -> void:
	_knob("FIX_MOVE_COVER", v)
	_knob("HIDDEN_FORFEIT_PENALTY", f002)

func _reset() -> void:
	AIDM.reset_caches()
	AIDM.clear_all_plans()
	AIDM.set_ai_seed(7)

## The stage, called the way the normal-move chain calls it.
func _pick(snap: Dictionary, uid: String = "CG", target: Vector2 = OBJ, diag: Dictionary = {}) -> Dictionary:
	_reset()
	var unit: Dictionary = snap.units[uid]
	var centroid: Vector2 = AIDM._get_unit_centroid(unit)
	var enemies: Dictionary = AIDM._get_enemy_units(snap, 1)
	var move_target: Vector2 = AIDM._objective_approach_target(unit, target)
	return AIDM._pick_cover_spot(unit, uid, snap, centroid, move_target, target, 6.0, enemies,
		AIDM._calculate_enemy_threat_data(enemies), AIDM._get_objectives(snap), AIDM._get_max_weapon_range(unit),
		AIDM._unit_has_ranged_weapons(unit), diag)

## allow_advance = false offers only a Normal move (a far objective would
## otherwise be raced with an Advance, which the stage does not shape).
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

func _probe_hidden_count(unit: Dictionary, delta: Vector2) -> int:
	var n := 0
	for m in unit.models:
		var p: Dictionary = m.duplicate()
		p["position"] = (m.position as Vector2) + delta
		if tm.is_model_hidden(p, unit):
			n += 1
	return n

func _dests_hidden_count(unit: Dictionary, dests: Dictionary) -> int:
	var n := 0
	for m in unit.models:
		var mid := str(m.id)
		if not dests.has(mid):
			continue
		var p: Dictionary = m.duplicate()
		p["position"] = Vector2(float(dests[mid][0]), float(dests[mid][1]))
		if tm.is_model_hidden(p, unit):
			n += 1
	return n

## The unit as it would stand at `dests` (for engine predicates).
func _unit_at(unit: Dictionary, dests: Dictionary) -> Dictionary:
	var u: Dictionary = unit.duplicate(true)
	for m in u.models:
		var mid := str(m.id)
		if dests.has(mid):
			m["position"] = Vector2(float(dests[mid][0]), float(dests[mid][1]))
	return u

func _translated_dests(unit: Dictionary, delta: Vector2) -> Dictionary:
	var out := {}
	for m in unit.models:
		var p: Vector2 = (m.position as Vector2) + delta
		out[str(m.id)] = [p.x, p.y]
	return out

# --- (a) ON -----------------------------------------------------------------

func test_on_spot_puts_every_model_hidden() -> void:
	print("\n--- (a) ON: the spot puts every model in the ruin (exam mv05's geometry) ---")
	_fix(1.0)
	var snap = _base_case()
	var unit: Dictionary = snap.units["CG"]
	var centroid: Vector2 = AIDM._get_unit_centroid(unit)
	var diag := {}
	var pick = _pick(snap, "CG", OBJ, diag)
	print("  pick: kind=%s end=%s base_end=%s gain=%s loss=%s diag=%s" % [str(pick.get("kind", "")), str(pick.get("end", "")),
		str(pick.get("base_end", "")), str(pick.get("gain", "")), str(pick.get("loss_in", "")), str(diag)])
	_assert(not pick.is_empty(), "fix on: a cover spot is found")
	if pick.is_empty():
		return
	_assert(str(pick.kind) == "hidden" and bool(pick.in_area), "fix on: the spot is Hidden AND in-area cover (got kind=%s in_area=%s)" % [str(pick.kind), str(pick.in_area)])
	_assert(float(pick.loss_in) <= 0.01, "fix on: at no cost to objective progress (loss %.2f\")" % float(pick.loss_in))
	_assert(_probe_hidden_count(unit, pick.end - centroid) == 5, "fix on: all 5 models Hidden at the spot (engine is_model_hidden)")
	_assert(_probe_hidden_count(unit, pick.base_end - centroid) == 4, "the straight move leaves only 4 of 5 Hidden (the case the fix is for)")
	_assert(int(pick.n_blind) == 1 and int(pick.n_threats) == 1, "the one shooter that can reach it is blinded (%d/%d)" % [int(pick.n_blind), int(pick.n_threats)])
	_assert(centroid.distance_to(pick.pos) <= 6.0 * PX * 0.95 + 0.01, "the target is within the mover's 0.95 x M cap")

func test_on_decide_movement_ends_hidden() -> void:
	print("\n--- (a) ON: decide() ends the move Hidden, says so, and keeps the objective wording ---")
	_fix(1.0)
	var snap = _base_case()
	var d = _decide(snap)
	print("  decision: %s" % _shape(d))
	_assert(str(d.get("type", "")) == "BEGIN_NORMAL_MOVE", "fix on: a normal move (got %s)" % str(d.get("type", "")))
	var dests: Dictionary = d.get("_ai_model_destinations", {})
	_assert(_dests_hidden_count(snap.units["CG"], dests) == 5, "fix on: every returned destination is Hidden (got %d of 5)" % _dests_hidden_count(snap.units["CG"], dests))
	_assert(bool(tm.unit_has_cover_11e(_unit_at(snap.units["CG"], dests), {})), "fix on: and every centre is in the ruin (13.08 cover vs any attacker)")
	var adj: Array = d.get("_ai_move_adjustments", [])
	_assert(not adj.is_empty() and str(adj[0]).contains("Hidden next turn from"), "fix on: the first move-shape note explains it (got %s)" % str(adj))
	_assert(str(d.get("_ai_description", "")).contains("moves toward obj_area"), "fix on: the action line still says 'moves toward obj_area' (integrity gate)")
	_assert(str(d.get("_ai_description", "")).contains("ending Hidden"), "fix on: the reason says it ends Hidden")

## Review finding: on a full-length move the straight end lies ON the 0.95 x M
## circle, so every terrain fit beside it used to land outside the cap and be
## thrown away — the stage only ever fired on a short final approach. A ruin
## overlapping the straight end (3 of 5 models Hidden there) must now be
## entered by sliding along the reachable arc, within the 2" progress budget,
## at the same turns-to-reach.
func _full_length_case(obj_y: float) -> Dictionary:
	var snap = _snapshot([_ruin_at("side_ruin", _rect(680.0, 500.0, 1000.0, 800.0))],
		[{"id": "obj_far", "position": Vector2(660.0, obj_y), "zone": "no_mans_land"}])
	_add(snap, "CG", 1, _line(530.0, 400.0))
	_add(snap, "SHOOTER", 2, _line(700.0, 1500.0))
	return snap

func test_on_full_length_move_slides_along_the_arc() -> void:
	print("\n--- (a) ON: a full-length move slides along the reachable arc into the ruin beside its straight end ---")
	_fix(1.0)
	var target := Vector2(660.0, 1891.0)
	var snap = _full_length_case(target.y)
	var unit: Dictionary = snap.units["CG"]
	var centroid: Vector2 = AIDM._get_unit_centroid(unit)
	var cap_px := 6.0 * PX * 0.95
	var diag := {}
	var pick = _pick(snap, "CG", target, diag)
	print("  pick: kind=%s pos=%s end=%s base_end=%s gain=%s loss=%s diag=%s" % [str(pick.get("kind", "none")), str(pick.get("pos", "")),
		str(pick.get("end", "")), str(pick.get("base_end", "")), str(pick.get("gain", "")), str(pick.get("loss_in", "")), str(diag)])
	_assert(not pick.is_empty(), "full-length move: a spot is found (it used to be thrown away by the cap screen)")
	if pick.is_empty():
		return
	_assert(absf(centroid.distance_to(pick.base_end) - cap_px) < 1.0,
		"precondition: the straight end lies on the 0.95 x M circle (%.1f px vs cap %.1f)" % [centroid.distance_to(pick.base_end), cap_px])
	_assert(_probe_hidden_count(unit, pick.base_end - centroid) == 3, "precondition: the straight move hides only 3 of 5")
	_assert(int(diag.get("pulled", 0)) >= 1, "the spot came from a proposal pulled back onto the reachable disc (pulled=%s)" % str(diag.get("pulled", "?")))
	_assert(centroid.distance_to(pick.pos) <= cap_px and centroid.distance_to(pick.end) <= cap_px + 0.01,
		"the target and the end are within the mover's 0.95 x M cap (%.1f / %.1f px)" % [centroid.distance_to(pick.pos), centroid.distance_to(pick.end)])
	_assert(str(pick.kind) == "hidden" and _probe_hidden_count(unit, pick.end - centroid) == 5,
		"all 5 models Hidden at the spot (kind=%s)" % str(pick.kind))
	_assert(float(pick.loss_in) <= 2.0, "within the 2\" progress budget (loss %.2f\")" % float(pick.loss_in))
	# The real chain: decide() with a Normal move on offer. Off = the straight
	# move (3 of 5 Hidden); on = every returned destination Hidden.
	var d_on = _decide(snap, "CG", "", false)
	_fix(0.0)
	var d_off = _decide(snap, "CG", "", false)
	_fix(1.0)
	var n_on := _dests_hidden_count(unit, d_on.get("_ai_model_destinations", {}))
	var n_off := _dests_hidden_count(unit, d_off.get("_ai_model_destinations", {}))
	print("  decide on : %s" % _shape(d_on))
	print("  hidden on=%d off=%d" % [n_on, n_off])
	_assert(n_off == 3 and n_on == 5, "decide(): off ends 3 of 5 Hidden, on ends 5 of 5 (got off=%d on=%d)" % [n_off, n_on])
	_assert(str(d_on.get("_ai_move_adjustments", [])).contains("Hidden next turn from"), "decide(): the note explains it")
	_assert(str(d_on.get("_ai_description", "")).contains("moves toward obj_far"), "decide(): still 'moves toward obj_far'")
	# Same layout, objective 109 px further: every arc spot now costs a whole
	# extra turn to reach, and the extra-turn guard keeps the straight move.
	var snap2 = _full_length_case(2000.0)
	var diag2 := {}
	var pick2 = _pick(snap2, "CG", Vector2(660.0, 2000.0), diag2)
	print("  objective at y=2000: pick=%s diag=%s" % [str(pick2.get("kind", "none")), str(diag2)])
	_assert(pick2.is_empty() and int(diag2.get("rej", {}).get("turns", 0)) >= 1,
		"objective at y=2000: the arc spots add a turn — the guard keeps the straight move (rej=%s)" % str(diag2.get("rej", {})))

func test_on_gone_to_ground_window() -> void:
	print("\n--- (a) ON: shooter 13.5\" away after its move (between 12\" and 15\") — Gone to Ground decides ---")
	_fix(1.0)
	# The shooter directly south, every pair 13.5-14.5" apart after its 6" move.
	var snap = _base_case(1861.5, 475.0, true)
	var pick = _pick(snap)
	print("  with wall: kind=%s n_gtg=%s n_blind=%s end=%s" % [str(pick.get("kind", "")), str(pick.get("n_gtg", "")), str(pick.get("n_blind", "")), str(pick.get("end", ""))])
	_assert(not pick.is_empty() and str(pick.kind) == "hidden" and int(pick.n_gtg) == 1,
		"dense wall in the way: blinded only through Gone to Ground (kind=%s gtg=%s)" % [str(pick.get("kind", "")), str(pick.get("n_gtg", ""))])
	if not pick.is_empty():
		var unit: Dictionary = snap.units["CG"]
		var centroid: Vector2 = AIDM._get_unit_centroid(unit)
		var probe: Dictionary = unit.models[2].duplicate()
		probe["position"] = (unit.models[2].position as Vector2) + (pick.end - centroid)
		var det: float = tm.detection_range_inches_for(probe, unit, snap.units["SHOOTER"].models[2])
		_assert(absf(det - 12.0) < 0.01, "engine: detection range against that shooter is 15 - 3 = 12\" (got %.1f)" % det)
	var snap2 = _base_case(1861.5, 475.0, false)
	var pick2 = _pick(snap2)
	print("  no wall: kind=%s n_blind=%s" % [str(pick2.get("kind", "")), str(pick2.get("n_blind", ""))])
	_assert(pick2.is_empty() or (str(pick2.kind) == "cover" and int(pick2.n_blind) == 0),
		"no wall: within 15\" after its move, so not blinded — at best in-area cover (kind=%s)" % str(pick2.get("kind", "none")))

func test_on_hidden_needs_f002_or_no_target() -> void:
	print("\n--- (a) ON: Hidden is credited only if it survives our own shooting phase ---")
	# Shooter 22" away (a target for our 24" spears), 16" after its move (blind).
	var snap = _base_case(1961.5)
	_fix(1.0, 0.0)
	var pick0 = _pick(snap)
	print("  F002 off: kind=%s n_blind=%s" % [str(pick0.get("kind", "")), str(pick0.get("n_blind", ""))])
	_assert(pick0.is_empty() or (str(pick0.kind) == "cover" and int(pick0.n_blind) == 0),
		"F002 off and a target in range: the squad would shoot its Hidden away — no Hidden credit (kind=%s)" % str(pick0.get("kind", "none")))
	_fix(1.0, 3.0)
	var pick3 = _pick(snap)
	print("  F002 3.0: kind=%s n_blind=%s" % [str(pick3.get("kind", "")), str(pick3.get("n_blind", ""))])
	_assert(not pick3.is_empty() and str(pick3.kind) == "hidden", "F002 on: Hidden is credited (kind=%s)" % str(pick3.get("kind", "none")))
	if not pick3.is_empty():
		var unit: Dictionary = snap.units["CG"]
		var at := _unit_at(unit, _translated_dests(unit, pick3.end - AIDM._get_unit_centroid(unit)))
		var cost: float = AIDM._hidden_forfeit_cost(at, AIDM._get_enemy_units(snap, 1))
		_assert(cost > 0.0, "...and at the spot F002 really prices the forfeit (_hidden_forfeit_cost %.2f > 0)" % cost)
	# No target at all: shooter 26" away (beyond our 24"), still 20" after its move.
	var snap_far = _base_case(2120.0)
	_fix(1.0, 0.0)
	var pick_far = _pick(snap_far)
	print("  no target: kind=%s" % str(pick_far.get("kind", "")))
	_assert(not pick_far.is_empty() and str(pick_far.kind) == "hidden",
		"F002 off but nothing in range to shoot: Hidden survives our turn, credited (kind=%s)" % str(pick_far.get("kind", "none")))
	_fix(1.0, 3.0)

## Review finding: F002 only declines CHIP shots (shoot worth below
## HIDDEN_FORFEIT_PENALTY x the immunity share, <= 3.0 of a 10-point kill),
## yet Hidden used to be credited wherever F002 was switched on. A squad with
## a worthwhile target in range shoots in its own phase and loses Hidden for
## the enemy's turn (13.09), so the stage must not claim it — and the real
## shooting decision is the judge: Hidden credited <=> F002 holds fire.
func test_on_hidden_only_where_f002_holds_fire() -> void:
	print("\n--- (a) ON: Hidden is credited only where F002 would really hold fire ---")
	_fix(1.0, 3.0)
	for juicy in [false, true]:
		var snap = _base_case()
		if juicy:
			# One T3 W1 Sv6+ model 22-24" away: inside the spears' 24", outside its own reach.
			_add(snap, "FRAGILE", 2, [Vector2(900.0, 1930.0)], [PISTOL], ["INFANTRY"], 3, 1, 6)
		var label := "worthwhile target" if juicy else "chip shot only"
		var pick = _pick(snap)
		print("  %s: kind=%s gain=%s n_blind=%s" % [label, str(pick.get("kind", "none")), str(pick.get("gain", "")), str(pick.get("n_blind", ""))])
		var d = _decide(snap)
		var dests: Dictionary = d.get("_ai_model_destinations", {})
		var notes := str(d.get("_ai_move_adjustments", []))
		var shot = _shooting_choice(_apply_dests(snap, "CG", dests))
		print("  %s: move=%s | shooting=%s %s" % [label, str(d.get("_ai_description", "")), str(shot.get("type", "")), str(shot.get("_ai_description", ""))])
		_assert(_dests_hidden_count(snap.units["CG"], dests) == 5, "%s: the squad still ends inside the ruin (5 of 5 positions Hidden-eligible)" % label)
		if juicy:
			_assert(not pick.is_empty() and str(pick.kind) == "cover" and int(pick.n_blind) == 0,
				"%s: no Hidden credit — the spot is kept for its cover only (kind=%s)" % [label, str(pick.get("kind", "none"))])
			_assert(not notes.contains("Hidden next turn") and not str(d.get("_ai_description", "")).contains("ending Hidden"),
				"%s: neither the note nor the action line claims Hidden" % label)
			_assert(str(shot.get("type", "")) == "SHOOT", "%s: and the shooting phase does shoot (got %s)" % [label, str(shot.get("type", ""))])
		else:
			_assert(not pick.is_empty() and str(pick.kind) == "hidden", "%s: Hidden credited (kind=%s)" % [label, str(pick.get("kind", "none"))])
			_assert(notes.contains("Hidden next turn from 1 of 1"), "%s: the note claims Hidden" % label)
			_assert(str(shot.get("type", "")) == "SKIP_UNIT" and str(shot.get("_ai_description", "")).contains("holds fire to stay Hidden"),
				"%s: and the shooting phase holds fire to keep it (got %s)" % [label, str(shot.get("type", ""))])

## Review finding: the threat list was cut to MOVE_COVER_MAX_SHOOTERS (4) by
## shot volume and built at the straight end only, yet the note said "Hidden
## next turn from N of N enemy shooters that could reach it". Every reaching
## shooter now counts — past the cap (distance test only) and any the chosen
## spot brings into reach.
func test_on_every_reaching_shooter_counted() -> void:
	print("\n--- (a) ON: every shooter that can reach the unit is in the count ---")
	_fix(1.0)
	var snap = _snapshot([_ruin()], [_obj_area()])
	_add(snap, "CG", 1, _line(SQUAD_X0, SQUAD_Y))
	_add(snap, "S1", 2, _line(540.0, 2010.0))
	_add(snap, "S2", 2, _line(140.0, 2010.0))
	_add(snap, "S3", 2, _line(940.0, 2010.0))
	_add(snap, "S4", 2, _line(540.0, 2090.0))
	# Four Boltgun models: the lightest shot volume (8 vs 10 — 5th, past the cap
	# of 4) and the nearest — 10.7" from the squad after its 6" move, inside
	# detection range. 12 wounds of 2+ armour: only a chip shot for the spears,
	# so F002 holds fire and the Hidden credit stands (this case is about the
	# count, not the hold-fire test).
	_add(snap, "LIGHT", 2, [Vector2(1000.0, 1700.0), Vector2(1065.0, 1700.0), Vector2(1130.0, 1700.0), Vector2(1195.0, 1700.0)],
		[BOLTER], ["INFANTRY"])
	var pick = _pick(snap)
	print("  five shooters: kind=%s n_blind=%s n_threats=%s threats=%s" % [str(pick.get("kind", "none")), str(pick.get("n_blind", "")),
		str(pick.get("n_threats", "")), str(_ids(pick.get("threats", [])))])
	_assert(not pick.is_empty() and int(pick.n_threats) == 5 and "LIGHT" in _ids(pick.threats),
		"the 5th (lightest) shooter is counted, not cut by MOVE_COVER_MAX_SHOOTERS (n_threats=%s)" % str(pick.get("n_threats", "?")))
	_assert(not pick.is_empty() and int(pick.n_blind) == 4, "...and it is not blinded: it gets within detection range (n_blind=%s of 5)" % str(pick.get("n_blind", "?")))
	var d = _decide(snap)
	var notes := str(d.get("_ai_move_adjustments", []))
	print("  note: %s" % notes)
	_assert(notes.contains("Hidden next turn from 4 of 5 enemy shooters"), "the note says 4 of 5, not 4 of 4")
	# A 12" pistol unit the chosen spot brings into reach and the straight end
	# does not (its nearest model at (40,1639); 9 wounds: a chip shot again).
	var snap2 = _snapshot([_ruin()], [_obj_area()])
	var cg2 = _add(snap2, "CG", 1, _line(SQUAD_X0, SQUAD_Y))
	_add(snap2, "S1", 2, _line(540.0, 2010.0))
	_add(snap2, "PIS", 2, [Vector2(40.0, 1639.0), Vector2(40.0, 1704.0), Vector2(40.0, 1769.0)], [PISTOL], ["INFANTRY"])
	var pick2 = _pick(snap2)
	print("  pistol unit: kind=%s n_blind=%s n_threats=%s threats=%s end=%s" % [str(pick2.get("kind", "none")), str(pick2.get("n_blind", "")),
		str(pick2.get("n_threats", "")), str(_ids(pick2.get("threats", []))), str(pick2.get("end", ""))])
	if not pick2.is_empty():
		var c2: Vector2 = AIDM._get_unit_centroid(cg2)
		var enemies2 = AIDM._get_enemy_units(snap2, 1)
		var at_base: Array = AIDM._move_cover_threats(pick2.members, AIDM._move_cover_shift(pick2.members, pick2.base_end - c2), enemies2)
		var at_spot: Array = AIDM._move_cover_threats(pick2.members, AIDM._move_cover_shift(pick2.members, pick2.end - c2), enemies2)
		_assert(not ("PIS" in _ids(at_base)) and "PIS" in _ids(at_spot),
			"precondition: PIS reaches the chosen spot but not the straight end (base=%s spot=%s)" % [str(_ids(at_base)), str(_ids(at_spot))])
	_assert(not pick2.is_empty() and "PIS" in _ids(pick2.threats) and int(pick2.n_threats) == 2,
		"the shooter the spot brings into reach is priced (n_threats=%s)" % str(pick2.get("n_threats", "?")))
	_assert(not pick2.is_empty() and str(pick2.kind) == "hidden" and int(pick2.n_blind) == 1,
		"...Hidden from S1 only: PIS gets within detection range (kind=%s n_blind=%s)" % [str(pick2.get("kind", "none")), str(pick2.get("n_blind", "?"))])
	var d2 = _decide(snap2)
	var notes2 := str(d2.get("_ai_move_adjustments", []))
	print("  note: %s" % notes2)
	_assert(notes2.contains("Hidden next turn from 1 of 2 enemy shooters"), "the note says 1 of 2, not 1 of 1")

func test_on_indirect_shooter_never_blind() -> void:
	print("\n--- (a) ON: an [INDIRECT FIRE] shooter can target what it cannot see (10.07) ---")
	_fix(1.0)
	var snap = _base_case(2010.0, 540.0, false, [LAUNCHER])
	var pick = _pick(snap)
	print("  indirect: kind=%s n_blind=%s n_threats=%s" % [str(pick.get("kind", "")), str(pick.get("n_blind", "")), str(pick.get("n_threats", ""))])
	_assert(pick.is_empty() or (str(pick.kind) == "cover" and int(pick.n_blind) == 0),
		"indirect shooter: never counted as blinded (kind=%s)" % str(pick.get("kind", "none")))

func test_on_attached_character_counted() -> void:
	print("\n--- (a) ON: an attached MOUNTED character can never be Hidden, so the unit is not ---")
	_fix(1.0)
	var snap = _base_case()
	var ch = _add(snap, "CHAR", 1, [Vector2(660, 780)], [SPEAR_R, SPEAR_M], ["CHARACTER", "MOUNTED"])
	ch["attached_to"] = "CG"
	snap.units["CG"]["attachment_data"] = {"attached_characters": ["CHAR"]}
	_assert(AIDM._move_cover_members(snap.units["CG"], snap).size() == 6, "the formation counts 5 bodyguard + 1 character model")
	var pick = _pick(snap)
	print("  with MOUNTED leader: kind=%s n_blind=%s in_area=%s" % [str(pick.get("kind", "")), str(pick.get("n_blind", "")), str(pick.get("in_area", ""))])
	_assert(pick.is_empty() or str(pick.kind) != "hidden", "the leader is in every-model checks: no Hidden claim (kind=%s)" % str(pick.get("kind", "none")))
	_assert(pick.is_empty() or not bool(pick.in_area),
		"...and no in-area cover either: 13.08's first bullet needs every model INFANTRY/BEASTS/SWARM (in_area=%s)" % str(pick.get("in_area", "none")))

## An attached INFANTRY CHARACTER is moved by the engine at CONFIRM by the
## first bodyguard model's delta, so the spot must hide it too: placed where
## the straight translation leaves it outside the ruin, it must end Hidden at
## the pick AND on the destinations decide() returns (the re-check rebuilds
## its spot from that delta).
func test_on_attached_infantry_character_hidden_too() -> void:
	print("\n--- (a) ON: an attached INFANTRY character moves with the unit and must be Hidden too ---")
	_fix(1.0)
	var snap = _base_case()
	var ch = _add(snap, "CHAR", 1, [Vector2(790, 760)], [SPEAR_R, SPEAR_M], ["CHARACTER", "INFANTRY"])
	ch["attached_to"] = "CG"
	snap.units["CG"]["attachment_data"] = {"attached_characters": ["CHAR"]}
	var unit: Dictionary = snap.units["CG"]
	var centroid: Vector2 = AIDM._get_unit_centroid(unit)
	var char_at := func(delta: Vector2) -> bool:
		var p: Dictionary = ch.models[0].duplicate()
		p["position"] = (ch.models[0].position as Vector2) + delta
		return tm.is_model_hidden(p, ch)
	var pick = _pick(snap)
	print("  with INFANTRY leader: kind=%s members=%s end=%s base_end=%s" % [str(pick.get("kind", "none")),
		str((pick.get("members", []) as Array).size()), str(pick.get("end", "")), str(pick.get("base_end", ""))])
	_assert(AIDM._move_cover_members(unit, snap).size() == 6, "the formation counts 5 bodyguard + 1 character model")
	_assert(not pick.is_empty() and str(pick.kind) == "hidden", "a Hidden spot is found for all 6 (kind=%s)" % str(pick.get("kind", "none")))
	if pick.is_empty():
		return
	_assert(not bool(char_at.call(pick.base_end - centroid)), "precondition: the straight translation leaves the character outside the ruin")
	_assert(bool(char_at.call(pick.end - centroid)), "the character is Hidden at the spot")
	var d = _decide(snap)
	var dests: Dictionary = d.get("_ai_model_destinations", {})
	print("  decide: %s" % _shape(d))
	_assert(not dests.is_empty() and not dests.has("CHAR"), "decide(): bodyguard destinations only (the engine moves the character)")
	if dests.is_empty():
		return
	var first_mid := str(dests.keys()[0])
	var first_orig := Vector2.INF
	for m in unit.models:
		if str(m.id) == first_mid:
			first_orig = m.position
	var first_dest := Vector2(float(dests[first_mid][0]), float(dests[first_mid][1]))
	_assert(bool(char_at.call(first_dest - first_orig)), "decide(): moved by the first bodyguard model's delta, the character ends Hidden")
	var enemies = AIDM._get_enemy_units(snap, 1)
	var chk = AIDM._move_cover_recheck(unit, snap, pick, dests, OBJ, enemies, AIDM._calculate_enemy_threat_data(enemies), 24.0, true)
	_assert(bool(chk.keep) and bool(chk.all_hidden) and str(chk.kind) == "hidden",
		"the re-check on those destinations keeps it Hidden, character included (keep=%s all_hidden=%s kind=%s)" % [str(chk.keep), str(chk.all_hidden), str(chk.get("kind", ""))])
	_assert(str(d.get("_ai_move_adjustments", [])).contains("Ends with all 6 models inside"), "decide(): the note counts all 6 models")

func test_on_quiet_dodge_same_answer() -> void:
	print("\n--- (a) the quiet threat-dodge prediction gives the generator's answer, silently ---")
	# A fragile shooter (T3 W1) moving north toward an objective 40" away, with
	# a mob of big choppas ahead-left: the end point is deep in its charge zone
	# and inside 12"; a 4" sidestep right costs a fraction of an inch.
	var far_obj := Vector2(800, 200)
	var snap = _snapshot([], [{"id": "obj_far", "position": far_obj, "zone": "no_mans_land"}])
	var unit: Dictionary = _add(snap, "SHOOTY", 1, [Vector2(800, 1800)], [SPEAR_R])
	unit.meta.stats["toughness"] = 3
	unit.meta.stats["wounds"] = 1
	var choppa := {"name": "Big choppa", "type": "Melee", "range": "Melee", "attacks": "4", "weapon_skill": "3",
		"strength": "8", "ap": "-2", "damage": "2", "special_rules": ""}
	var mob: Array = []
	for k in range(10):
		mob.append(Vector2(620.0 + 40.0 * float(k % 5), 1280.0 + 40.0 * float(k / 5)))
	_add(snap, "BRUTE", 2, mob, [choppa])
	var enemies = AIDM._get_enemy_units(snap, 1)
	var td = AIDM._calculate_enemy_threat_data(enemies)
	var c: Vector2 = AIDM._get_unit_centroid(unit)
	# A 4" move: the dodge only tries sidesteps still within the unit's M.
	var desired := c + Vector2(0, -160)
	AIDM._move_shape_notes = []
	var loud: Vector2 = AIDM._find_safer_position(c, desired, 240.0, td, unit, [far_obj], enemies)
	var notes_loud: int = AIDM._move_shape_notes.size()
	AIDM._move_shape_notes = []
	var quiet: Vector2 = AIDM._find_safer_position(c, desired, 240.0, td, unit, [far_obj], enemies, true)
	print("  desired=%s loud=%s quiet=%s notes(loud)=%d notes(quiet)=%d" % [str(desired), str(loud), str(quiet), notes_loud, AIDM._move_shape_notes.size()])
	_assert(loud != desired, "the dodge fires in this position (it moved the end point)")
	_assert(loud.distance_to(quiet) < 0.001, "quiet: the same dodge")
	_assert(notes_loud == 1, "loud (the default, every existing caller): the move-shape note, as before")
	_assert(AIDM._move_shape_notes.is_empty(), "quiet: no move-shape note")

# --- (b) param 0 --------------------------------------------------------------

func test_param_zero_restores_old_reads() -> void:
	print("\n--- (b) FIX_MOVE_COVER = 0 / unset: decide() is byte-identical; no cover_gain term ---")
	var snap = _base_case()
	AIDM._config_overrides.erase("FIX_MOVE_COVER")
	_knob("HIDDEN_FORFEIT_PENALTY", 3.0)
	var d_unset = _decide(snap)
	var cands_unset: Dictionary = AIDM._last_movement_candidates.duplicate(true)
	_fix(0.0)
	var d_zero = _decide(snap)
	var cands_zero: Dictionary = AIDM._last_movement_candidates.duplicate(true)
	_fix(1.0)
	var d_on = _decide(snap)
	print("  unset: %s" % _shape(d_unset))
	print("  zero : %s" % _shape(d_zero))
	print("  on   : %s" % _shape(d_on))
	_assert(_shape(d_unset) == _shape(d_zero), "0.0 == unset: same type, destinations, notes and description")
	_assert(_shape(d_on) != _shape(d_zero), "on differs (the spot moved)")
	var has_term := false
	for cd in [cands_unset, cands_zero]:
		for uid in cd:
			for c in cd[uid]:
				if (c.get("score_terms", {}) as Dictionary).has("cover_gain"):
					has_term = true
	_assert(not has_term, "off: no plan candidate carries a cover_gain term")
	_assert(not str(d_zero.get("_ai_move_adjustments", [])).contains("Hidden next turn"), "off: no cover note")

# --- (c) guards ---------------------------------------------------------------

func test_guard_no_threat_no_divert() -> void:
	print("\n--- (c) guard: nobody can shoot it next turn — never burrow ---")
	var snap = _base_case(2350.0)  # 31.7" from the spot: 25.7" after its move, beyond its 24"
	_fix(1.0)
	var diag := {}
	var pick = _pick(snap, "CG", OBJ, diag)
	_assert(pick.is_empty() and int(diag.get("threats", -1)) == 0, "no threat: no spot (threats=%s)" % str(diag.get("threats", "?")))
	var d_on = _decide(snap)
	_fix(0.0)
	var d_off = _decide(snap)
	_assert(_shape(d_on) == _shape(d_off), "no threat: decide() on == off")
	_fix(1.0)

func test_guard_loss_cap() -> void:
	print("\n--- (c) guard: the only ruin in reach is behind the unit — costs > 2\" of progress ---")
	# Open-ground objective 32" south; a ruin directly BEHIND (north of) the squad.
	var far_obj := {"id": "obj_far", "position": Vector2(1300, 2100), "zone": "no_mans_land"}
	var back := {"id": "back_ruin", "piece_class": "area", "type": "ruins", "category": "dense", "height_category": "tall",
		"can_move_through": {"INFANTRY": true, "MONSTER": false, "VEHICLE": false}, "polygon": _rect(1100, 500, 1500, 700)}
	var snap = _snapshot([back], [far_obj])
	_add(snap, "CG", 1, _line(1170.0, 800.0))
	_add(snap, "SHOOTER", 2, _line(1500.0, 1900.0))
	_fix(1.0)
	var diag := {}
	var pick = _pick(snap, "CG", Vector2(1300, 2100), diag)
	print("  pick=%s diag=%s" % [str(pick.get("kind", "none")), str(diag)])
	_assert(pick.is_empty() and int(diag.get("rej", {}).get("loss", 0)) >= 1,
		"loss cap: the ruin behind is rejected for lost progress (rej=%s)" % str(diag.get("rej", {})))
	# The knob is what screens them: lift the cap and nothing is rejected for
	# lost progress any more (the ruin behind still costs a whole extra turn,
	# so the turn guard holds the line instead).
	_knob("MOVE_COVER_MAX_LOSS_INCHES", 20.0)
	var diag_free := {}
	var pick_free = _pick(snap, "CG", Vector2(1300, 2100), diag_free)
	print("  cap lifted: pick=%s diag=%s" % [str(pick_free.get("kind", "none")), str(diag_free)])
	_assert(int(diag_free.get("rej", {}).get("loss", -1)) == 0 and int(diag_free.get("rej", {}).get("turns", 0)) >= 1,
		"cap lifted: no loss rejections; the extra-turn guard still refuses the ruin behind (rej=%s)" % str(diag_free.get("rej", {})))
	_assert(pick_free.is_empty(), "...so it still makes the straight move")
	AIDM._config_overrides.erase("MOVE_COVER_MAX_LOSS_INCHES")

func test_guard_turns_to_reach() -> void:
	print("\n--- (c) guard: a spot within 2\" of progress that adds a turn to reach the objective ---")
	# Open-ground objective so the straight end's gap is 5.0" (1 turn at M6); an
	# exposed crater to the side whose in-area spot leaves a 6.6" gap (2 turns).
	var obj_y := 1028.0 + 383.0
	var snap = _snapshot([_crater(1040, 840, 1320, 970)], [{"id": "obj_open", "position": Vector2(1300, obj_y), "zone": "no_mans_land"}])
	_add(snap, "CG", 1, _line(1170.0, 800.0))
	_add(snap, "SHOOTER", 2, _line(1500.0, 1900.0))
	_fix(1.0)
	var diag := {}
	var pick = _pick(snap, "CG", Vector2(1300, obj_y), diag)
	print("  pick=%s diag=%s" % [str(pick.get("kind", "none")), str(diag)])
	_assert(pick.is_empty() and int(diag.get("rej", {}).get("turns", 0)) >= 1,
		"extra turn: the crater spot is rejected (rej=%s)" % str(diag.get("rej", {})))
	# The same spot is fine once it no longer costs a turn (objective 2" nearer, loss free).
	var snap2 = _snapshot([_crater(1040, 840, 1320, 970)], [{"id": "obj_open", "position": Vector2(1300, obj_y - 80.0), "zone": "no_mans_land"}])
	_add(snap2, "CG", 1, _line(1170.0, 800.0))
	_add(snap2, "SHOOTER", 2, _line(1500.0, 1900.0))
	_knob("MOVE_COVER_LOSS_WEIGHT", 0.0)
	var diag2 := {}
	var pick2 = _pick(snap2, "CG", Vector2(1300, obj_y - 80.0), diag2)
	print("  nearer objective: pick=%s diag=%s" % [str(pick2.get("kind", "none")), str(diag2)])
	_assert(not pick2.is_empty() and int(diag2.get("rej", {}).get("turns", 0)) == 0,
		"same turn count: the crater spot is taken (in-area cover, kind=%s)" % str(pick2.get("kind", "none")))
	AIDM._config_overrides.erase("MOVE_COVER_LOSS_WEIGHT")

func test_guard_control_range_kept() -> void:
	print("\n--- (c) guard: the straight move ends in range of an open-ground objective; the crater spot loses it ---")
	var o := Vector2(1500, 1080)
	var snap = _snapshot([_crater(1040, 840, 1320, 990)], [{"id": "obj_open", "position": o, "zone": "no_mans_land"}])
	_add(snap, "CG", 1, _line(1170.0, 800.0))
	_add(snap, "SHOOTER", 2, _line(1300.0, 1900.0))
	_fix(1.0)
	var diag := {}
	var pick = _pick(snap, "CG", o, diag)
	print("  pick=%s diag=%s" % [str(pick.get("kind", "none")), str(diag)])
	_assert(pick.is_empty() and int(diag.get("rej", {}).get("control", 0)) >= 1,
		"control range: a spot that drops the objective is rejected (rej=%s)" % str(diag.get("rej", {})))

## A squad heading for an open-ground objective 39" south whose straight end
## leaves its eastern model fully visible past a free-standing dense wall; a
## slide west along the reachable arc puts every model behind it (13.08 "not
## fully visible" — cover a VEHICLE could get too). `keywords` picks the
## squad's type; the geometry is otherwise identical.
func _wall_case(keywords: Array) -> Dictionary:
	var snap = _snapshot([_solo_wall(300.0, 1290.0, 700.0, 1310.0)],
		[{"id": "obj_open", "position": Vector2(660.0, 2400.0), "zone": "no_mans_land"}])
	_add(snap, "SQUAD", 1, _line(SQUAD_X0, SQUAD_Y), [SPEAR_R, SPEAR_M], keywords)
	_add(snap, "SHOOTER", 2, _line(540.0, 2000.0))
	return snap

func test_guard_vehicle_and_charge_unchanged() -> void:
	print("\n--- (c) guard: VEHICLE units and units with a planned charge move exactly as before ---")
	# Control: on this board the stage DOES move an INFANTRY squad (behind the
	# wall), so the VEHICLE twin below can only match its flag-off move because
	# the stage is gated off for it — not because there is nothing to find.
	_fix(1.0)
	var inf = _wall_case(["INFANTRY"])
	var i_pick = _pick(inf, "SQUAD", Vector2(660.0, 2400.0))
	var i_on = _decide(inf, "SQUAD", "", false)
	_fix(0.0)
	var i_off = _decide(inf, "SQUAD", "", false)
	print("  infantry twin: pick kind=%s | on : %s" % [str(i_pick.get("kind", "none")), _shape(i_on)])
	_assert(not i_pick.is_empty() and _shape(i_on) != _shape(i_off),
		"control: the INFANTRY twin is moved behind the wall (pick kind=%s, on != off)" % str(i_pick.get("kind", "none")))
	_fix(1.0)
	var veh = _wall_case(["VEHICLE"])
	var v_pick = _pick(veh, "SQUAD", Vector2(660.0, 2400.0))  # the stage called directly, past the gate
	var d_on = _decide(veh, "SQUAD", "", false)
	_fix(0.0)
	var d_off = _decide(veh, "SQUAD", "", false)
	print("  vehicle: direct pick kind=%s | on : %s" % [str(v_pick.get("kind", "none")), _shape(d_on)])
	_assert(not v_pick.is_empty(), "precondition: called directly, the stage would find the VEHICLE squad a not-fully-visible spot too")
	_assert(_shape(d_on) == _shape(d_off), "VEHICLE: on == off (the stage is gated to INFANTRY/BEASTS/SWARM)")
	var snap2 = _base_case()
	_fix(1.0)
	var c_on = _decide(snap2, "CG", "SHOOTER")
	_fix(0.0)
	var c_off = _decide(snap2, "CG", "SHOOTER")
	print("  charge on  : %s" % _shape(c_on))
	_assert(_shape(c_on) == _shape(c_off), "planned charge: on == off (the T7-23 steer keeps the move)")
	_assert(not str(c_on.get("_ai_move_adjustments", [])).contains("Hidden next turn"), "planned charge: no cover note")
	_fix(1.0)

# --- (d) follow-through and plan -------------------------------------------------

func test_follow_through_rechecks_returned_destinations() -> void:
	print("\n--- (d) follow-through: the spot is judged again on the destinations the mover returns ---")
	_fix(1.0)
	var snap = _base_case()
	var unit: Dictionary = snap.units["CG"]
	var pick = _pick(snap)
	_assert(not pick.is_empty(), "a spot to re-check")
	if pick.is_empty():
		return
	var enemies = AIDM._get_enemy_units(snap, 1)
	var td = AIDM._calculate_enemy_threat_data(enemies)
	var c: Vector2 = AIDM._get_unit_centroid(unit)
	var ok_dests := _translated_dests(unit, pick.end - c)
	var ok = AIDM._move_cover_recheck(unit, snap, pick, ok_dests, OBJ, enemies, td, 24.0, true)
	print("  as predicted: keep=%s gain=%s" % [str(ok.keep), str(ok.gain)])
	_assert(bool(ok.keep), "the predicted translation is kept")
	var bad_dests: Dictionary = ok_dests.duplicate(true)
	bad_dests["m5"] = [float(bad_dests["m5"][0]) + 120.0, float(bad_dests["m5"][1])]  # spiralled out east, off the ruin
	var bad = AIDM._move_cover_recheck(unit, snap, pick, bad_dests, OBJ, enemies, td, 24.0, true)
	print("  m5 off the ruin: keep=%s why=%s text=%s" % [str(bad.keep), str(bad.why), str(bad.why_text)])
	_assert(not bool(bad.keep) and str(bad.why_text).contains("outside the terrain"),
		"a model left outside: dropped, 'a model would have ended outside the terrain'")
	var none = AIDM._move_cover_recheck(unit, snap, pick, {}, OBJ, enemies, td, 24.0, true)
	_assert(not bool(none.keep), "no legal placement: dropped")
	var note: String = AIDM._move_cover_note(pick, ok, "obj_area")
	print("  note: %s" % note)
	_assert(note.contains("Hidden next turn from 1 of 1 enemy shooter") and note.contains("at no cost to objective progress"),
		"the note names the shooters blinded and the progress cost")

## Review finding: the re-check dropped a Hidden pick only when a model left
## the terrain; it never re-derived the kind. If the returned destinations put
## a model where a shooter now gets within detection range, the unit is still
## in the ruin (cover pays) but Hidden from nobody — the note must say cover,
## not "Hidden next turn from 0 of 1 ... (none of them can get within ...)".
func test_follow_through_rederives_the_kind() -> void:
	print("\n--- (d) follow-through: the kind is re-derived on the returned destinations ---")
	_fix(1.0)
	var snap = _base_case(1970.0)
	var unit: Dictionary = snap.units["CG"]
	var pick = _pick(snap)
	print("  pick: kind=%s n_blind=%s end=%s" % [str(pick.get("kind", "none")), str(pick.get("n_blind", "")), str(pick.get("end", ""))])
	_assert(not pick.is_empty() and str(pick.kind) == "hidden", "precondition: the predicted spot is Hidden (kind=%s)" % str(pick.get("kind", "none")))
	if pick.is_empty():
		return
	var c: Vector2 = AIDM._get_unit_centroid(unit)
	var dests := _translated_dests(unit, pick.end - c)
	# m3 ends 1.3" further south than predicted: still inside the ruin, still
	# within its own 0.95 x M of its start, clear of every other model.
	var m3_start: Vector2 = unit.models[2].position
	var m3_end := Vector2(float(dests["m3"][0]), float(dests["m3"][1]) + 52.0)
	dests["m3"] = [m3_end.x, m3_end.y]
	_assert(m3_start.distance_to(m3_end) <= 6.0 * PX * 0.95 and Geometry2D.is_point_in_polygon(m3_end, _ruin().polygon),
		"precondition: a legal divergence (%.2f\" from its start, inside the ruin)" % (m3_start.distance_to(m3_end) / PX))
	var enemies = AIDM._get_enemy_units(snap, 1)
	var chk = AIDM._move_cover_recheck(unit, snap, pick, dests, OBJ, enemies, AIDM._calculate_enemy_threat_data(enemies), 24.0, true)
	var note: String = AIDM._move_cover_note(pick, chk, "obj_area") if bool(chk.keep) else ""
	print("  diverged: keep=%s kind=%s all_hidden=%s n_blind=%s gain=%s note=%s" % [str(chk.keep), str(chk.get("kind", "")),
		str(chk.all_hidden), str(chk.n_blind), str(chk.gain), note])
	_assert(bool(chk.all_hidden) and int(chk.n_blind) == 0, "precondition: every model still in the terrain, but the shooter now gets within detection range")
	_assert(str(chk.get("kind", "")) == "cover", "the re-check re-derives kind=cover (got %s)" % str(chk.get("kind", "")))
	_assert(not bool(chk.keep) or (not note.contains("Hidden next turn") and note.contains("Benefit of Cover")),
		"kept for its cover alone, the note claims cover, not Hidden")

func test_plan_cover_gain_term() -> void:
	print("\n--- (d) plan prior: cover_gain when the approach already ends inside the ruin ---")
	# A broadside line whose straight approach puts every model inside the ruin.
	var snap = _snapshot([_ruin()], [_obj_area()])
	_add(snap, "CG", 1, _line(470.0, SQUAD_Y))
	_add(snap, "SHOOTER", 2, _line(480.0, 2010.0))
	# v1 ships the prior at 0 even with the flag on: its effect on the greedy
	# assignment cannot be fire-tagged (review finding) — no term by default.
	_fix(1.0)
	AIDM._config_overrides.erase("MOVE_COVER_PLAN_WEIGHT")
	var t_default := _cover_gain_terms(snap)
	print("  fix=1 weight=default (0): cover_gain=%s" % str(t_default.get("cover_gain", "absent")))
	_assert(not t_default.is_empty() and not t_default.has("cover_gain"), "fix on, MOVE_COVER_PLAN_WEIGHT at its v1 default (0): no cover_gain term")
	# With the weight set (exploratory runs), the term is there and keeps the
	# ledger; with the flag off it is absent whatever the weight.
	_knob("MOVE_COVER_PLAN_WEIGHT", 0.5)
	for v in [1.0, 0.0]:
		_fix(v)
		var cand := _plan_candidate(snap)
		var terms: Dictionary = cand.get("score_terms", {})
		var total := 0.0
		for k in terms:
			total += float(terms[k])
		print("  fix=%.0f weight=0.5 cover_gain=%s score=%s terms_sum=%.3f" % [v, str(terms.get("cover_gain", "absent")), str(cand.get("score", "?")), total])
		if v >= 0.5:
			_assert(float(terms.get("cover_gain", 0.0)) > 0.0, "fix on, weight 0.5: the obj_area candidate carries cover_gain > 0")
			_assert(absf(total - float(cand.get("score", 0.0))) < 0.01, "fix on, weight 0.5: the ledger still sums to the score")
		else:
			_assert(not cand.is_empty() and not terms.has("cover_gain"), "fix off: no cover_gain term")
	AIDM._config_overrides.erase("MOVE_COVER_PLAN_WEIGHT")
	_fix(1.0)

## The plan's obj_area candidate for CG on `snap` (its score and score_terms).
func _plan_candidate(snap: Dictionary) -> Dictionary:
	_reset()
	var objectives = AIDM._get_objectives(snap)
	var enemies = AIDM._get_enemy_units(snap, 1)
	var friendly = AIDM._get_units_for_player(snap, 1)
	var evals = AIDM._evaluate_all_objectives(snap, objectives, 1, enemies, friendly, 2)
	var movable = {"CG": ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]}
	AIDM._assign_units_to_objectives(snap, movable, evals, objectives, enemies, friendly, 1, 2,
		AIDM._calculate_enemy_threat_data(enemies))
	var cand: Dictionary = {}
	for c in AIDM._last_movement_candidates.get("CG", []):
		if str(c.get("objective_id", "")) == "obj_area":
			cand = c
	return cand

func _cover_gain_terms(snap: Dictionary) -> Dictionary:
	return _plan_candidate(snap).get("score_terms", {})
