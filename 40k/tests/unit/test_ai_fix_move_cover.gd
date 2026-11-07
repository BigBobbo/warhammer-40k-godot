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
# proposes formation fits into nearby terrain areas plus a heading fan, screens
# every proposal against the generator stages that would bend it, scores the
# survivors with TerrainManager's own predicates against the enemy shooters
# that can reach the unit next turn (their M + max range), caps the objective
# progress it may give up, and re-checks the RETURNED destinations
# (_move_cover_recheck); plus a "cover_gain" plan prior. Hidden is credited only
# where it survives our own shooting phase (F002 can hold fire, or no target).
#
# Cases: ON — the spot hides every model / decide() ends Hidden with the note
# and the integrity wording / Gone to Ground's -3" behind a dense wall / F002 or
# no target / an [INDIRECT FIRE] shooter is never blinded / a non-INFANTRY
# attached character rules Hidden out / the quiet threat dodge gives the same
# answer; param 0 — byte-identical decide() output, no cover_gain term;
# guards — no threat, loss cap, extra turn, lost control range, VEHICLE and
# charge-intent units unchanged; follow-through — the returned destinations
# are re-checked; plan — cover_gain lands in score_terms and keeps the ledger.
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
const KNOBS := ["FIX_MOVE_COVER", "HIDDEN_FORFEIT_PENALTY", "MOVE_COVER_MAX_LOSS_INCHES", "MOVE_COVER_LOSS_WEIGHT"]

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
	AIDM = load(AI_PATH)

	test_on_spot_puts_every_model_hidden()
	test_on_decide_movement_ends_hidden()
	test_on_gone_to_ground_window()
	test_on_hidden_needs_f002_or_no_target()
	test_on_indirect_shooter_never_blind()
	test_on_attached_character_counted()
	test_on_quiet_dodge_same_answer()
	test_param_zero_restores_old_reads()
	test_guard_no_threat_no_divert()
	test_guard_loss_cap()
	test_guard_turns_to_reach()
	test_guard_control_range_kept()
	test_guard_vehicle_and_charge_unchanged()
	test_follow_through_rechecks_returned_destinations()
	test_plan_cover_gain_term()

	for k in KNOBS:
		AIDM._config_overrides.erase(k)
	AIDM.reset_caches()
	tm.terrain_features = prev_terrain
	gs.state["board"]["objectives"] = prev_objs
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
		keywords: Array = ["INFANTRY"]) -> Dictionary:
	var models = []
	for i in range(positions.size()):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 40, "base_type": "circular",
			"base_dimensions": {}, "position": positions[i], "wounds": 3, "current_wounds": 3})
	var u = {"id": uid, "owner": owner, "status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"name": uid, "points": 150, "stats": {"move": 6, "toughness": 6, "save": 2, "wounds": 3,
			"leadership": 6, "objective_control": 2}, "keywords": keywords, "weapons": weapons},
		"models": models, "flags": {}, "attachment_data": {"attached_characters": []}}
	snap.units[uid] = u
	return u

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

func _decide(snap: Dictionary, uid: String = "CG", inject_charge_on: String = "") -> Dictionary:
	_reset()
	var board: Dictionary = snap.duplicate(true)
	if inject_charge_on != "":
		AIDM._phase_plan[1] = {"charge_intent": {uid: {"target_id": inject_charge_on, "target_name": inject_charge_on,
			"score": 10.0, "distance_inches": 20.0}}, "lock_targets": [], "shooting_lanes": {},
			"charge_target_ids": [inject_charge_on]}
		AIDM._phase_plan_built[1] = true
		AIDM._phase_plan_round = int(board.get("meta", {}).get("battle_round", 1))
	var actions = [{"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": uid}, {"type": "BEGIN_ADVANCE", "actor_unit_id": uid},
		{"type": "REMAIN_STATIONARY", "actor_unit_id": uid}, {"type": "END_MOVEMENT"}]
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
	var pick = _pick(snap)
	print("  with MOUNTED leader: kind=%s n_blind=%s" % [str(pick.get("kind", "")), str(pick.get("n_blind", ""))])
	_assert(pick.is_empty() or str(pick.kind) != "hidden", "the leader is in every-model checks: no Hidden claim (kind=%s)" % str(pick.get("kind", "none")))
	if not pick.is_empty():
		_assert((pick.members as Array).size() == 6, "the formation counts 5 bodyguard + 1 character model")

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

func test_guard_vehicle_and_charge_unchanged() -> void:
	print("\n--- (c) guard: VEHICLE units and units with a planned charge move exactly as before ---")
	var snap = _snapshot([_ruin()], [_obj_area()])
	_add(snap, "TANK", 1, [Vector2(660, 820)], [SPEAR_R], ["VEHICLE"])
	_add(snap, "SHOOTER", 2, _line(540.0, 2010.0))
	_fix(1.0)
	var d_on = _decide(snap, "TANK")
	_fix(0.0)
	var d_off = _decide(snap, "TANK")
	print("  vehicle on : %s" % _shape(d_on))
	_assert(_shape(d_on) == _shape(d_off), "VEHICLE: on == off")
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

func test_plan_cover_gain_term() -> void:
	print("\n--- (d) plan prior: cover_gain when the approach already ends inside the ruin ---")
	# A broadside line whose straight approach puts every model inside the ruin.
	var snap = _snapshot([_ruin()], [_obj_area()])
	_add(snap, "CG", 1, _line(470.0, SQUAD_Y))
	_add(snap, "SHOOTER", 2, _line(480.0, 2010.0))
	for v in [1.0, 0.0]:
		_fix(v)
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
		var terms: Dictionary = cand.get("score_terms", {})
		var total := 0.0
		for k in terms:
			total += float(terms[k])
		print("  fix=%.0f cover_gain=%s score=%s terms_sum=%.3f" % [v, str(terms.get("cover_gain", "absent")), str(cand.get("score", "?")), total])
		if v >= 0.5:
			_assert(float(terms.get("cover_gain", 0.0)) > 0.0, "fix on: the obj_area candidate carries cover_gain > 0")
			_assert(absf(total - float(cand.get("score", 0.0))) < 0.01, "fix on: the ledger still sums to the score")
		else:
			_assert(not cand.is_empty() and not terms.has("cover_gain"), "fix off: no cover_gain term")
	_fix(1.0)
