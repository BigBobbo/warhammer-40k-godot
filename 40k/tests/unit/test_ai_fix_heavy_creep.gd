extends SceneTree

# FIX_HEAVY_CREEP (movement: keep [HEAVY] while moving 3" or less — 11e 24.16
# [HEAVY], 13.08 Benefit of Cover, 13.10 Obscuring, 13.11 Solid, 14.02 level of
# control). 24.16: each [HEAVY] attack in your Shooting phase adds 1 to the hit
# roll if the attacking unit is unengaged, was not set up on the battlefield
# this turn and no model in it moved more than 3" this turn. T7-26
# (_should_hold_for_heavy_bonus) still keeps the bonus the 10e way — it
# freezes the unit on centroid range alone, with no line of sight and no move
# of 3" or less considered (exam mv10_creep_to_keep_heavy: a heavy bolter
# froze for +1 to hit on nothing behind a light area it could step into).
#
# Fix: inside T7-26's hold, _heavy_creep_stage looks for a Normal move of 3"
# or less for every model (attached CHARACTERs included, the engine's own
# distance) that buys cover (FIX_MOVE_COVER's _mc_eval), the objective's range
# or a firing lane (the engine's get_eligible_targets), keeps every [HEAVY]
# target the unit has, and beats holding still by HEAVY_CREEP_MIN_GAIN; the
# mover is called once at a 3" cap and its destinations are re-checked. A
# unit set up on the battlefield this turn makes its planned move instead.
#
# Cases: ON — the creep into a light area that sees out and takes cover (the
# engine agrees: eligible target, [HEAVY] applies, cover), pure cover, the
# objective footprint, a lane round a Solid wall, an attached CHARACTER
# carried along, the ledger sums; param 0 — byte-identical decide() output,
# the flag read is the only footprint; guards — no gain, a creep that would
# lose a [HEAVY] target, set up this turn, [INDIRECT FIRE], a VEHICLE's
# terrain cost, the re-check's 3" limit, elevated / AIRCRAFT, T7-26 not
# holding (the flag is never read), the batch-1 flags compose, AIPlayer's
# re-plan cap helper. Review fixes: with F002 on the creep prices Hidden OR
# the shot, never both, and claims no +1 to hit it would not take (n), nor
# the stay's shot F002 would decline (q); the re-check prices Gone to Ground
# on its own budget (r); a reserves arrival is a set-up only by its turn
# stamp, while the engine's never-cleared flag (MV-1) still denies [HEAVY]
# and the AI says so (g2); the chain's hold exits explain themselves (g3);
# AIPlayer's deferred re-plan and staging retry, driven on a real board (l2).
#
# Run with: godot --headless --path . -s tests/unit/test_ai_fix_heavy_creep.gd
# (runs once the scene tree is up: the stage reads RulesEngine /
# TerrainManager / MissionManager / GameState)

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const GameStateData = preload("res://autoloads/GameState.gd")
const PX := 40.0  # pixels per inch
const STEP := 65.0
## Beta's formation (the exam's shape, 40 mm bases ≥ 64 px apart): a front row
## at y 660 and a back row at y 605, every base north of the light area.
const B_FORM := [Vector2(340, 660), Vector2(406, 660), Vector2(472, 660), Vector2(373, 605), Vector2(439, 605)]
const OBJ_FAR := Vector2(1300.0, 640.0)    # open ground ~22" east: T7-26's hold (beyond 2M)
const HEAVY_BOLTER := {"name": "Heavy bolter", "type": "Ranged", "range": "36", "attacks": "3", "ballistic_skill": "4",
	"strength": "5", "ap": "-1", "damage": "2", "special_rules": "heavy"}
const HEAVY_SHORT := {"name": "Short heavy bolter", "type": "Ranged", "range": "24", "attacks": "3", "ballistic_skill": "4",
	"strength": "5", "ap": "-1", "damage": "2", "special_rules": "heavy"}
const HEAVY_MORTAR := {"name": "Heavy mortar", "type": "Ranged", "range": "36", "attacks": "2", "ballistic_skill": "4",
	"strength": "8", "ap": "-2", "damage": "2", "special_rules": "blast, heavy, indirect fire"}
## A 36" gun without [HEAVY]: MOV-1 (_should_hold_for_shooting) reads the
## longest range, T7-26 only the [HEAVY] weapons'.
const LONG_GUN := {"name": "Long gun", "type": "Ranged", "range": "36", "attacks": "1", "ballistic_skill": "4",
	"strength": "4", "ap": "0", "damage": "1", "special_rules": ""}
const SPEAR_R := {"name": "Guardian spear - Ranged", "type": "Ranged", "range": "24", "attacks": "2",
	"ballistic_skill": "2", "strength": "4", "ap": "-1", "damage": "2", "special_rules": "assault"}
const SPEAR_M := {"name": "Guardian spear - Melee", "type": "Melee", "range": "Melee", "attacks": "5",
	"weapon_skill": "2", "strength": "7", "ap": "-2", "damage": "2", "special_rules": ""}
## A chip-shot rifle (the Gone-to-Ground board's enemy squad) and the
## FIX_INDIRECT_STATIONARY test's spotter kit.
const RIFLE := {"name": "Rifle", "type": "Ranged", "range": "24", "attacks": "2", "ballistic_skill": "3",
	"strength": "4", "ap": "-1", "damage": "1", "special_rules": ""}
const BOLTGUN := {"name": "Boltgun", "type": "Ranged", "range": "24", "attacks": "2", "ballistic_skill": "3",
	"strength": "4", "ap": "0", "damage": "1", "special_rules": ""}
const CCW := {"name": "Close combat weapon", "type": "Melee", "range": "Melee", "attacks": "2",
	"weapon_skill": "3", "strength": "4", "ap": "0", "damage": "1", "special_rules": ""}
## A melee-focused unit's [HEAVY] gun (MOV-1 does not hold it; T7-26 does).
const HEAVY_STUB := {"name": "Heavy stub", "type": "Ranged", "range": "36", "attacks": "3", "ballistic_skill": "4",
	"strength": "4", "ap": "0", "damage": "1", "special_rules": "heavy"}
const KNOBS := ["FIX_HEAVY_CREEP", "HEAVY_CREEP_MIN_GAIN", "HEAVY_CREEP_PROBES", "FIX_MOVE_COVER", "FIX_MOVE_FOR_SHOT",
	"FIX_MOVE_FOR_CHARGE", "FIX_INDIRECT_STATIONARY", "HIDDEN_FORFEIT_PENALTY", "FIX_MOVE_TERRAIN_11E",
	"MOVE_COVER_MAX_GTG_CHECKS"]

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
	print("\n=== FIX_HEAVY_CREEP: keep [HEAVY] while moving 3\" or less (11e 24.16) ===\n")
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

	test_on_creep_into_light_area()
	test_on_pure_cover()
	test_param_zero_restores_old_reads()
	test_guard_no_gain_holds()
	test_guard_keeps_heavy_targets()
	test_on_objective_footprint()
	test_on_lane_round_solid_wall()
	test_guard_set_up_this_turn()
	test_guard_arrival_stamp_and_engine_flag()
	test_guard_hold_exits_explain()
	test_guard_indirect_keeps_hold()
	test_guard_vehicle_terrain_cost()
	test_on_attached_character_carried()
	test_guard_recheck_three_inch_limit()
	test_aiplayer_move_cap_helper()
	test_aiplayer_replan_call_sites()
	test_ledger_sums()
	test_composes_with_batch1_flags()
	test_f002_stay_shot_not_taken()
	test_recheck_own_gtg_budget()
	test_guard_t726_not_holding_no_read()
	test_guard_elevated_and_aircraft()

	for k in KNOBS:
		AIDM._config_overrides.erase(k)
	AIDM._suggest_focus_unit_id = ""
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

## A LIGHT terrain AREA (13.10: obscuring; 13.08: in-area cover for INFANTRY).
func _light_area(id: String, x0: float, y0: float, x1: float, y1: float) -> Dictionary:
	return {"id": id, "piece_class": "area", "type": "ruins", "category": "light", "height_category": "tall",
		"traits": ["difficult_ground"], "can_move_through": {"INFANTRY": true, "MONSTER": false, "VEHICLE": false},
		"polygon": _rect(x0, y0, x1, y1)}

## A DENSE terrain AREA (13.09 Hidden; 13.11.01 Gone to Ground behind it).
func _dense_area(id: String, x0: float, y0: float, x1: float, y1: float) -> Dictionary:
	return {"id": id, "piece_class": "area", "type": "ruins", "category": "dense", "height_category": "tall",
		"can_move_through": {"INFANTRY": true, "MONSTER": false, "VEHICLE": false}, "polygon": _rect(x0, y0, x1, y1)}

## A Solid wall: a dense FEATURE (13.11 — blocks sight lines at ground level).
func _wall(id: String, x0: float, y0: float, x1: float, y1: float) -> Dictionary:
	return {"id": id, "piece_class": "feature", "type": "wall", "category": "dense", "height_category": "tall",
		"can_move_through": {"INFANTRY": true, "MONSTER": false, "VEHICLE": false}, "polygon": _rect(x0, y0, x1, y1)}

func _obj(pos: Vector2, id: String = "obj") -> Dictionary:
	return {"id": id, "position": pos, "zone": "no_mans_land"}

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

func _add(snap: Dictionary, uid: String, owner: int, positions: Array, weapons: Array,
		keywords: Array = ["INFANTRY"], wounds: int = 3, base_mm: int = 40, points: int = 150) -> Dictionary:
	var models = []
	for i in range(positions.size()):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": base_mm, "base_type": "circular",
			"base_dimensions": {}, "position": positions[i], "wounds": wounds, "current_wounds": wounds})
	var u = {"id": uid, "owner": owner, "status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"name": uid, "points": points, "stats": {"move": 6, "toughness": 6, "save": 2, "wounds": wounds,
			"leadership": 6, "objective_control": 2}, "keywords": keywords, "weapons": weapons, "abilities": []},
		"models": models, "flags": {}, "attachment_data": {"attached_characters": []}}
	snap.units[uid] = u
	return u

func _line(x0: float, y: float, n: int = 5, step: float = STEP) -> Array:
	var out: Array = []
	for k in range(n):
		out.append(Vector2(x0 + step * float(k), y))
	return out

func _shift(points: Array, d: Vector2) -> Array:
	var out: Array = []
	for p in points:
		out.append(Vector2(p) + d)
	return out

## The base case (exam mv10's geometry, scaled down): Beta B (5 x 40 mm, a
## [HEAVY] heavy bolter + a melee spear) just north of the light area A
## (x 300-560, y 700-860) with no base in it; its only target T (5 x 40 mm,
## spears) ~25" south, every line between them crossing A — no sight line
## from where B stands. The objective is in the open ~22" east, so T7-26
## holds (beyond M, and beyond the 2M override).
func _board(weapon: Dictionary = HEAVY_BOLTER, objs: Array = []) -> Dictionary:
	var snap = _snapshot([_light_area("A", 300.0, 700.0, 560.0, 860.0)], objs if not objs.is_empty() else [_obj(OBJ_FAR)])
	_add(snap, "B", 1, B_FORM, [weapon, SPEAR_M])
	_add(snap, "T", 2, _line(300.0, 1660.0), [SPEAR_R, SPEAR_M])
	return snap

func _knob(knob: String, v: float) -> void:
	AIDM._config_overrides[knob] = v

func _fix(v: float) -> void:
	_knob("FIX_HEAVY_CREEP", v)

func _reset() -> void:
	AIDM.reset_caches()
	AIDM.clear_all_plans()
	AIDM.set_ai_seed(7)
	AIDM._suggest_focus_unit_id = ""

func _actions(uid: String = "B", allow_advance: bool = true) -> Array:
	var actions = [{"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": uid}]
	if allow_advance:
		actions.append({"type": "BEGIN_ADVANCE", "actor_unit_id": uid})
	actions.append({"type": "REMAIN_STATIONARY", "actor_unit_id": uid})
	actions.append({"type": "END_MOVEMENT"})
	return actions

func _decide(snap: Dictionary) -> Dictionary:
	_reset()
	var board: Dictionary = snap.duplicate(true)
	return AIDM.decide(7, board, _actions(), 1)

func _shape(d: Dictionary) -> String:
	return "%s | %s | %s | %s" % [str(d.get("type", "")), str(d.get("_ai_model_destinations", {})),
		str(d.get("_ai_move_adjustments", [])), str(d.get("_ai_description", ""))]

## The board as it would stand with `uid`'s models at `dests` (unengaged).
func _board_at(snap: Dictionary, uid: String, dests: Dictionary) -> Dictionary:
	var s2: Dictionary = snap.duplicate(true)
	for m in s2.units[uid].models:
		var mid := str(m.id)
		if dests.has(mid):
			m["position"] = Vector2(float(dests[mid][0]), float(dests[mid][1]))
	s2.units[uid].flags["in_engagement"] = false
	return s2

## A direct call of the stage for B on `snap` (the arguments the T7-26 branch
## passes), filling `diag`.
func _stage(snap: Dictionary, target: Vector2, diag: Dictionary, uid: String = "B") -> Dictionary:
	_reset()
	var unit: Dictionary = snap.units[uid]
	var enemies: Dictionary = AIDM._get_enemy_units(snap, 1)
	return AIDM._heavy_creep_stage(unit, uid, snap, AIDM._get_unit_centroid(unit), target, "obj", 6.0, enemies,
		AIDM._get_objectives(snap), AIDM._calculate_enemy_threat_data(enemies), 36.0, diag)

func _sum(terms: Dictionary) -> float:
	var s := 0.0
	for k in terms:
		s += float(terms[k])
	return s

func _all_in_area(dests: Dictionary, area_id: String) -> bool:
	if dests.is_empty():
		return false
	for mid in dests:
		var p := Vector2(float(dests[mid][0]), float(dests[mid][1]))
		if str(tm.area_at(p).get("id", "")) != area_id:
			return false
	return true

func _steps_text(d: Dictionary) -> String:
	return "\n".join(PackedStringArray(d.get("_ai_thinking_steps", [])))

## Every parameter the decision read: the resolver's leftovers plus what its
## decision records drained (_add_decision_record takes them).
func _reads(d: Dictionary) -> Dictionary:
	var out: Dictionary = AIDM.take_param_reads()
	for r in d.get("_ai_decision_records", []):
		for k in r.get("parameters_used", {}):
			out[k] = r.parameters_used[k]
	return out

func _behind_flag(reads: Dictionary) -> Array:
	var out: Array = []
	for k in reads:
		var ks := str(k)
		if ks.begins_with("HEAVY_CREEP_") or ks.begins_with("MOVE_COVER_"):
			out.append(ks)
	return out

# --- (a) ON -------------------------------------------------------------------

func test_on_creep_into_light_area() -> void:
	print("\n--- (a) ON: creep 3\" or less into the light area — it sees out (13.10) and takes cover (13.08), keeping [HEAVY] ---")
	var snap = _board()
	_assert(not re.unit_sight_line("B", "T", snap, false).has_los, "premise (engine): area A blocks every B->T line where B stands (13.10)")
	_fix(0.0)
	var d_off = _decide(snap)
	_assert(str(d_off.get("type", "")) == "REMAIN_STATIONARY" and str(d_off.get("_ai_description", "")).begins_with("B holds for Heavy weapon bonus"),
		"premise: flag off, T7-26 freezes B (got %s)" % str(d_off.get("_ai_description", d_off.get("type", ""))))
	_fix(1.0)
	var d = _decide(snap)
	var dests: Dictionary = d.get("_ai_model_destinations", {})
	print("  on: %s" % _shape(d))
	_assert(str(d.get("type", "")) == "BEGIN_NORMAL_MOVE", "on: a Normal move instead of the freeze")
	_assert(_all_in_area(dests, "A"), "on: every destination centre is inside area A")
	var models: Array = AIDM._get_alive_models_with_positions(snap.units["B"])
	var max_mv: float = AIDM._destinations_max_move_inches(models, dests)
	_assert(max_mv > 1.0 and max_mv <= 2.9, "on: the longest straight model move is 1-2.9\" (got %.2f\")" % max_mv)
	var members: Array = AIDM._move_cover_members(snap.units["B"], snap, true)
	var moved: float = AIDM._heavy_creep_moved_inches("B", members, dests)
	_assert(moved <= 3.0, "on: the engine-distance mirror says no model moves more than 3\" (got %.2f\")" % moved)
	var at := _board_at(snap, "B", dests)
	var elig: Dictionary = re.get_eligible_targets("B", at, false)
	_assert(elig.has("T") and "heavy_bolter_ranged" in elig.T.get("weapons_in_range", []),
		"engine: from the destinations T is an eligible target of the heavy bolter (got %s)" % str(elig.keys()))
	var bu: Dictionary = at.units["B"]
	bu.flags["moved"] = true
	bu.flags["moved_max_inches"] = moved
	_assert(ModifierStack.heavy_applies_11e(bu, at), "engine: [HEAVY] still applies after the creep (24.16)")
	_assert(tm.unit_has_cover_11e(bu, {}), "engine: every model's centre in a terrain area — the Benefit of Cover (13.08)")
	var desc := str(d.get("_ai_description", ""))
	_assert(desc.begins_with("B moves toward obj (") and desc.find("to keep its [HEAVY] +1 to hit") >= 0,
		"the action line keeps 'moves toward obj' and says why (got %s)" % desc)
	var notes: Array = d.get("_ai_move_adjustments", [])
	_assert(not notes.is_empty() and str(notes[0]).find("no model moves more than 3\"") >= 0 and str(notes[0]).find("Benefit of Cover") >= 0,
		"the K card's move note names the 3\" limit and the cover (got %s)" % str(notes))
	_assert(is_equal_approx(float(d.get("_ai_move_cap_inches", 0.0)), 3.0), "the decision carries the 3\" re-plan cap for AIPlayer")
	_assert(_steps_text(d).find("keeps its [HEAVY] +1 to hit") >= 0, "a thinking step explains the creep")

func test_on_pure_cover() -> void:
	print("\n--- (a2) ON: pure cover — the target is already in sight; the creep buys in-area cover, no lane ---")
	# T to the east (its lines miss A); the objective south past A, so the
	# creep into A costs no objective progress.
	var snap = _snapshot([_light_area("A", 300.0, 700.0, 560.0, 860.0)], [_obj(Vector2(430.0, 1450.0))])
	_add(snap, "B", 1, B_FORM, [HEAVY_BOLTER, SPEAR_M])
	_add(snap, "T", 2, _line(1340.0, 640.0), [SPEAR_R, SPEAR_M])
	_assert(re.unit_sight_line("B", "T", snap, false).has_los, "premise (engine): B sees T from where it stands")
	var diag := {}
	var hc = _stage(snap, Vector2(430.0, 1450.0), diag)
	_assert(not hc.is_empty(), "the stage creeps (diag %s)" % str(diag))
	if hc.is_empty():
		return
	var terms: Dictionary = hc.check.terms
	_assert(float(terms.get("hc_cover", 0.0)) > 0.0, "hc_cover > 0 (got %s)" % str(terms))
	_assert(absf(float(terms.get("hc_lane", 0.0))) < 1e-6, "hc_lane = 0: the same target and shot as holding still")
	_assert(int(diag.get("pairs_stay", 0)) >= 1 and int(hc.check.n_pairs) >= int(diag.get("pairs_stay", 0)),
		"the stay's [HEAVY] pair (T, heavy bolter) is kept")
	_assert(_all_in_area(hc.dests, "A"), "every destination centre is inside area A")

# --- (b) param 0 ----------------------------------------------------------------

func test_param_zero_restores_old_reads() -> void:
	print("\n--- (b) FIX_HEAVY_CREEP = 0 / unset: decide() is byte-identical; the flag read is the only footprint ---")
	var snap = _board()
	AIDM._config_overrides.erase("FIX_HEAVY_CREEP")
	AIDM.take_param_reads()
	var d_unset = _decide(snap)
	var reads_unset := _reads(d_unset)
	_fix(0.0)
	var d_zero = _decide(snap)
	var reads_zero := _reads(d_zero)
	_fix(1.0)
	var d_on = _decide(snap)
	AIDM.take_param_reads()
	print("  unset: %s" % _shape(d_unset))
	print("  zero : %s" % _shape(d_zero))
	print("  on   : %s" % _shape(d_on))
	_assert(_shape(d_unset) == _shape(d_zero), "0.0 == unset: same type, destinations, notes and description")
	_assert(str(d_zero.get("type", "")) == "REMAIN_STATIONARY", "off: T7-26's REMAIN_STATIONARY")
	_assert(_shape(d_on) != _shape(d_zero), "on differs (it creeps)")
	_assert(not d_zero.has("_ai_move_cap_inches"), "off: no re-plan cap key")
	_assert(reads_zero.has("FIX_HEAVY_CREEP") and reads_unset.has("FIX_HEAVY_CREEP"), "off: the flag is read on a T7-26 hold")
	var behind := _behind_flag(reads_zero)
	_assert(behind.is_empty(), "off: no HEAVY_CREEP_* / MOVE_COVER_* knob is read behind the flag (got %s)" % str(behind))
	var kz: Array = reads_zero.keys()
	var ku: Array = reads_unset.keys()
	kz.sort()
	ku.sort()
	_assert(kz == ku, "0.0 and unset read the same parameters")

# --- (c) guards -------------------------------------------------------------------

func test_guard_no_gain_holds() -> void:
	print("\n--- (c) guard: no terrain anywhere, the target in sight — nothing a 3\" move can buy: it holds ---")
	var snap = _snapshot([], [_obj(OBJ_FAR)])
	_add(snap, "B", 1, B_FORM, [HEAVY_BOLTER, SPEAR_M])
	_add(snap, "T", 2, _line(300.0, 1660.0), [SPEAR_R, SPEAR_M])
	_assert(re.unit_sight_line("B", "T", snap, false).has_los, "premise (engine): B sees T")
	_fix(1.0)
	var d_on = _decide(snap)
	_fix(0.0)
	var d_off = _decide(snap)
	_assert(_shape(d_on) == _shape(d_off) and str(d_on.get("type", "")) == "REMAIN_STATIONARY",
		"decide(): T7-26's REMAIN_STATIONARY unchanged (got %s)" % _shape(d_on))
	_fix(1.0)
	var d_on2 = _decide(snap)
	_assert(_steps_text(d_on2).find("holds still for [HEAVY] — no move of 3\" or less buys enough") >= 0,
		"a thinking step says no creep buys enough")
	var diag := {}
	var hc = _stage(snap, OBJ_FAR, diag)
	_assert(hc.is_empty() and float(diag.get("best_gain", -INF)) < AIDM.HEAVY_CREEP_MIN_GAIN,
		"the stage's best gain stays below HEAVY_CREEP_MIN_GAIN (got %s)" % str(diag.get("best_gain", "?")))

func test_guard_keeps_heavy_targets() -> void:
	print("\n--- (d) guard: the only cover would take T out of the 24\" [HEAVY] weapon's range — it holds ---")
	# T ~23.9" centroid to centroid (T7-26 holds on the 24" [HEAVY] weapon) and
	# ~21.8" edge to edge (in range, in sight); the only area is BEHIND B, so
	# creeping into it puts T beyond 24". The 36" gun keeps MOV-1 from holding
	# first (a 6" move east keeps T within 36").
	var snap = _snapshot([_light_area("N", 300.0, 440.0, 560.0, 560.0)], [_obj(OBJ_FAR)])
	_add(snap, "B", 1, B_FORM, [HEAVY_SHORT, LONG_GUN, SPEAR_M])
	_add(snap, "T", 2, _line(300.0, 1594.0), [SPEAR_R, SPEAR_M])
	var elig: Dictionary = re.get_eligible_targets("B", snap, false)
	_assert(elig.has("T") and "short_heavy_bolter_ranged" in elig.T.get("weapons_in_range", []),
		"premise (engine): T is a [HEAVY] target from where B stands (got %s)" % str(elig))
	_fix(0.0)
	var d_off = _decide(snap)
	_assert(str(d_off.get("_ai_description", "")).begins_with("B holds for Heavy weapon bonus"),
		"premise: flag off, T7-26 holds (got %s)" % str(d_off.get("_ai_description", "")))
	_fix(1.0)
	var d_on = _decide(snap)
	_assert(_shape(d_on) == _shape(d_off), "decide(): the hold is unchanged (got %s)" % _shape(d_on))
	var diag := {}
	var hc = _stage(snap, OBJ_FAR, diag)
	var rej: Dictionary = diag.get("rej", {})
	_assert(hc.is_empty(), "no creep is returned")
	_assert(int(rej.get("lane_lost", 0)) >= 1, "the cover spot was probed and dropped: it loses the [HEAVY] pair (rej %s)" % str(rej))

func test_on_objective_footprint() -> void:
	print("\n--- (e) ON: a creep puts a model within range of the plan objective (14.02) ---")
	# Open-ground objective ~1.9\" beyond the range of B's nearest model; no terrain.
	var b_near := Vector2(406.0, 660.0)
	var obj_pos := b_near + Vector2(0.0, AIDM.OBJECTIVE_CONTROL_RANGE_PX + 31.5 + 1.9 * PX)
	var snap = _snapshot([], [_obj(obj_pos)])
	_add(snap, "B", 1, B_FORM, [HEAVY_BOLTER, SPEAR_M])
	_add(snap, "T", 2, _line(1340.0, 640.0), [SPEAR_R, SPEAR_M])
	var probe: Dictionary = snap.units["B"]
	_assert(not AIDM._unit_has_model_in_control_range(probe, obj_pos), "premise: no B model is within the objective's range now")
	var diag := {}
	var hc = _stage(snap, obj_pos, diag)
	_assert(not hc.is_empty(), "the stage creeps (diag %s)" % str(diag))
	if hc.is_empty():
		return
	_assert(is_equal_approx(float(hc.check.terms.get("hc_objective", 0.0)), AIDM.HEAVY_CREEP_OBJECTIVE_WEIGHT),
		"hc_objective = HEAVY_CREEP_OBJECTIVE_WEIGHT (got %s)" % str(hc.check.terms))
	var at := _board_at(snap, "B", hc.dests)
	_assert(AIDM._unit_has_model_in_control_range(at.units["B"], obj_pos), "at the destinations a model is within the objective's range")
	_assert(float(hc.check.moved_in) <= 3.0, "within 3\" (got %.2f)" % float(hc.check.moved_in))

func test_on_lane_round_solid_wall() -> void:
	print("\n--- (f) ON: a Solid wall (13.11) hides T; a sidestep of 3\" or less sees round it ---")
	var snap = _snapshot([_wall("W", 200.0, 1000.0, 600.0, 1040.0)], [_obj(Vector2(1300.0, 600.0))])
	_add(snap, "B", 1, _line(300.0, 600.0), [HEAVY_BOLTER, SPEAR_M])
	var t := _add(snap, "T", 2, _line(300.0, 1500.0), [SPEAR_R, SPEAR_M], ["INFANTRY"], 1)
	t.meta.stats["toughness"] = 3
	t.meta.stats["save"] = 5
	_assert(not re.unit_sight_line("B", "T", snap, false).has_los, "premise (engine): the wall blocks every B->T line")
	_fix(0.0)
	var d_off = _decide(snap)
	_assert(str(d_off.get("type", "")) == "REMAIN_STATIONARY", "premise: flag off, T7-26 holds on centroid range")
	_fix(1.0)
	var d = _decide(snap)
	_assert(str(d.get("type", "")) == "BEGIN_NORMAL_MOVE", "on: it creeps (got %s)" % _shape(d))
	var diag := {}
	var hc = _stage(snap, Vector2(1300.0, 600.0), diag)
	_assert(not hc.is_empty() and float(hc.check.terms.get("hc_lane", 0.0)) > 0.0, "hc_lane > 0 (diag %s)" % str(diag))
	if hc.is_empty():
		return
	var elig: Dictionary = re.get_eligible_targets("B", _board_at(snap, "B", hc.dests), false)
	_assert(elig.has("T"), "engine: T is eligible from the destinations")
	_assert(float(hc.check.moved_in) <= 3.0, "within 3\" (got %.2f)" % float(hc.check.moved_in))
	_assert(str(hc.notes[0]).find("can see T") >= 0, "the note names the new target (got %s)" % str(hc.notes[0]))

func test_guard_set_up_this_turn() -> void:
	print("\n--- (g) guard: set up on the battlefield this turn (a disembark, 18.04) — no bonus to keep: its planned move ---")
	var snap = _board()
	snap.units["B"]["disembarked_this_phase"] = true
	_assert(AIDM._heavy_creep_set_up_this_turn(snap.units["B"], snap), "_heavy_creep_set_up_this_turn: disembarked")
	_fix(0.0)
	var d_off = _decide(snap)
	_assert(str(d_off.get("type", "")) == "REMAIN_STATIONARY", "off: T7-26 still holds it")
	_fix(1.0)
	var d_on = _decide(snap)
	var desc := str(d_on.get("_ai_description", ""))
	_assert(str(d_on.get("type", "")) == "BEGIN_NORMAL_MOVE" and desc.begins_with("B moves toward obj")
		and desc.find("to keep its [HEAVY]") < 0 and not d_on.has("_ai_move_cap_inches"),
		"on: the planned Normal move, no creep (got %s)" % desc)
	_assert(_steps_text(d_on).find("set up on the battlefield this turn") >= 0, "a thinking step says why")
	var f_unit := {"flags": {"deep_struck": true}, "attachment_data": {"attached_characters": []}}
	_assert(AIDM._heavy_creep_set_up_this_turn(f_unit, snap), "deep struck counts as set up this turn")
	var plain := {"flags": {}, "attachment_data": {"attached_characters": []}}
	_assert(not AIDM._heavy_creep_set_up_this_turn(plain, snap), "a unit that started the turn on the battlefield does not")

func test_guard_arrival_stamp_and_engine_flag() -> void:
	print("\n--- (g2) a reserves arrival is a set-up only in its own turn (the stamp); the engine's never-cleared flag (MV-1) still denies [HEAVY] — the AI follows the engine and says why ---")
	# Battle round 3; B arrived from reserves in round 2. IngressMove set
	# flags.arrived_from_reserves and MovementPhase stamped the round; no reset
	# path ever removes the flag (MV-1), and ModifierStack still reads it.
	var snap = _snapshot([_light_area("A", 300.0, 700.0, 560.0, 860.0)], [_obj(OBJ_FAR)], 3)
	_add(snap, "B", 1, B_FORM, [HEAVY_BOLTER, SPEAR_M])
	_add(snap, "T", 2, _line(300.0, 1660.0), [SPEAR_R, SPEAR_M])
	var bu: Dictionary = snap.units["B"]
	bu.flags["arrived_from_reserves"] = true
	bu["arrived_from_reserves_turn"] = 2
	_assert(not AIDM._heavy_creep_set_up_this_turn(bu, snap), "arrived in round 2, now round 3: NOT set up this turn (24.16)")
	var held: Dictionary = bu.duplicate(true)
	held.flags["remained_stationary"] = true
	_assert(not ModifierStack.heavy_applies_11e(held, snap), "engine premise (MV-1): ModifierStack still denies [HEAVY] after holding still")
	var deny: Dictionary = AIDM._heavy_creep_engine_denies_heavy(bu, snap)
	_assert(not deny.is_empty() and int(deny.get("round", -1)) == 2 and bool(deny.get("arrived", false)),
		"_heavy_creep_engine_denies_heavy names the round-2 arrival (got %s)" % str(deny))
	_fix(0.0)
	var d_off = _decide(snap)
	_assert(str(d_off.get("_ai_description", "")).begins_with("B holds for Heavy weapon bonus"), "off: T7-26 holds (got %s)" % str(d_off.get("_ai_description", "")))
	_fix(1.0)
	var d_on = _decide(snap)
	var steps := _steps_text(d_on)
	print("  on: %s" % _shape(d_on))
	_assert(str(d_on.get("type", "")) == "BEGIN_NORMAL_MOVE" and not d_on.has("_ai_move_cap_inches"),
		"on: its planned move — no creep for a bonus the engine will not give (got %s)" % _shape(d_on))
	_assert(steps.find("still counts its arrival from reserves in battle round 2") >= 0 and steps.find("set up on the battlefield this turn") < 0,
		"the step names the engine's stale arrival, not a set-up this turn (got %s)" % steps)
	# Once the engine clears the flag (MV-1 fixed), the old stamp alone neither
	# sets it up nor denies [HEAVY]: the creep runs as on any other turn.
	bu.flags.erase("arrived_from_reserves")
	_assert(AIDM._heavy_creep_engine_denies_heavy(bu, snap).is_empty(), "flag cleared: the engine allows [HEAVY] again")
	var d_clear = _decide(snap)
	_assert(str(d_clear.get("type", "")) == "BEGIN_NORMAL_MOVE" and d_clear.has("_ai_move_cap_inches"),
		"flag cleared: the creep (got %s)" % _shape(d_clear))
	# The stamp for THIS turn: the round it arrived in, its owner's turn.
	var snap2 = _board()
	snap2["meta"]["active_player"] = 1
	var b2: Dictionary = snap2.units["B"]
	b2.flags["arrived_from_reserves"] = true
	b2["arrived_from_reserves_turn"] = 2
	_assert(AIDM._heavy_creep_set_up_this_turn(b2, snap2), "arrived this round in its owner's turn: set up this turn")
	snap2["meta"]["active_player"] = 2
	_assert(not AIDM._heavy_creep_set_up_this_turn(b2, snap2), "the same stamp in the opponent's turn: not its turn of arrival")

func test_guard_hold_exits_explain() -> void:
	print("\n--- (g3) no bonus to keep, but the chain holds it after all: the steps never say it makes its planned move ---")
	# Lone Operative: a genuine disembark (18.04), an enemy 13\" north and one
	# 13\" south of B's centroid (406, 638) — no safe retreat, so T7-11 holds
	# it. No melee weapons on either side, so no charge intent overrides T7-26.
	var snap = _snapshot([_light_area("A", 300.0, 700.0, 560.0, 860.0)], [_obj(OBJ_FAR)])
	_add(snap, "B", 1, B_FORM, [HEAVY_BOLTER])
	_add(snap, "N", 2, [Vector2(406.0, 638.0 - 13.0 * PX)], [SPEAR_R])
	_add(snap, "T", 2, [Vector2(406.0, 638.0 + 13.0 * PX)], [SPEAR_R])
	snap.units["B"]["disembarked_this_phase"] = true
	snap.units["B"].meta["abilities"] = ["Lone Operative"]
	_fix(1.0)
	var d_lo = _decide(snap)
	var steps_lo := _steps_text(d_lo)
	print("  lone op: %s" % _shape(d_lo))
	if str(d_lo.get("_ai_description", "")).find("Lone Operative safe") >= 0:
		_assert(steps_lo.find("makes its planned move") < 0 and steps_lo.find("as a Lone Operative it is safe where it stands") >= 0,
			"Lone Operative hold: the step says it holds anyway (got %s)" % steps_lo)
	else:
		_assert(false, "premise: T7-11 holds the Lone Operative (got %s)" % _shape(d_lo))
	# FIX_INDIRECT_STATIONARY's stay: the IS test's spotted-battery board, the
	# mortar unit carrying the engine's stale arrival flag from round 1.
	var snap2 = _snapshot([_dense_area("hide", 1250.0, 1460.0, 1610.0, 1540.0)], [_obj(Vector2(430.0, 1300.0))])
	_add(snap2, "B", 1, _line(300.0, 600.0), [HEAVY_MORTAR, SPEAR_M])
	_add(snap2, "T", 2, _line(1300.0, 1500.0), [SPEAR_M])
	_add(snap2, "S", 1, _line(900.0, 1300.0, 4, 55.0), [BOLTGUN, CCW], ["INFANTRY"], 1, 32, 45)
	snap2.units["B"].flags["arrived_from_reserves"] = true
	snap2.units["B"]["arrived_from_reserves_turn"] = 1
	_knob("FIX_INDIRECT_STATIONARY", 1.0)
	var d_is = _decide(snap2)
	AIDM._config_overrides.erase("FIX_INDIRECT_STATIONARY")
	var steps_is := _steps_text(d_is)
	print("  IS stay: %s" % _shape(d_is))
	_assert(str(d_is.get("type", "")) == "REMAIN_STATIONARY" and bool(d_is.get("_ai_indirect_hold", false)),
		"premise: FIX_INDIRECT_STATIONARY keeps the battery stationary (got %s)" % _shape(d_is))
	_assert(steps_is.find("makes its planned move") < 0 and steps_is.find("it stays put anyway, to arm its indirect fire") >= 0,
		"IS stay: the step says it stays put anyway (got %s)" % steps_is)
	# The planned move finds no legal placement (the mover's range clamp zeroes
	# it): a melee-focused unit 35.9\" from its only target, its objective the
	# other way, after a same-turn disembark.
	var snap3 = _snapshot([], [_obj(Vector2(880.0, 60.0))])
	_add(snap3, "B", 1, _line(750.0, 700.0), [HEAVY_STUB, SPEAR_M])
	_add(snap3, "T", 2, _line(750.0, 700.0 + 1436.0), [SPEAR_M])
	snap3.units["B"]["disembarked_this_phase"] = true
	var d_np = _decide(snap3)
	var steps_np := _steps_text(d_np)
	print("  no placement: %s" % _shape(d_np))
	_assert(str(d_np.get("type", "")) == "REMAIN_STATIONARY", "premise: no legal placement, so it remains stationary (got %s)" % _shape(d_np))
	_assert(steps_np.find("makes its planned move instead of holding still") < 0 and steps_np.find("no legal placement was found for it") >= 0,
		"no placement: the step says the planned move found no legal placement (got %s)" % steps_np)

func test_guard_indirect_keeps_hold() -> void:
	print("\n--- (h) guard: [INDIRECT FIRE] + [HEAVY] — Remaining Stationary arms 10.07's band: the hold is kept ---")
	var snap = _board(HEAVY_MORTAR)
	_fix(0.0)
	var d_off = _decide(snap)
	_fix(1.0)
	AIDM.take_param_reads()
	var d_on = _decide(snap)
	var reads := _reads(d_on)
	_assert(str(d_off.get("type", "")) == "REMAIN_STATIONARY" and _shape(d_on) == _shape(d_off),
		"decide(): unchanged T7-26 hold (got %s)" % _shape(d_on))
	var behind := _behind_flag(reads)
	_assert(behind.is_empty(), "no HEAVY_CREEP_* knob is read (got %s)" % str(behind))

func test_guard_vehicle_terrain_cost() -> void:
	print("\n--- (i) guard: a VEHICLE pays 2\" to enter difficult ground it cannot move through — never a creep into it ---")
	var area := _light_area("A", 300.0, 700.0, 560.0, 860.0)
	var snap = _snapshot([area], [_obj(OBJ_FAR)])
	var v := _add(snap, "V", 1, [Vector2(430.0, 600.0)], [HEAVY_BOLTER], ["VEHICLE"], 12, 100, 200)
	_add(snap, "T", 2, _line(300.0, 1660.0), [SPEAR_R, SPEAR_M])
	var members: Array = AIDM._move_cover_members(v, snap, true)
	var dests := {"m1": [430.0, 720.0]}
	var moved: float = AIDM._heavy_creep_moved_inches("V", members, dests)
	_assert(is_equal_approx(moved, 120.0 / PX + 2.0), "moved inches = 3\" raw + 2\" difficult ground (got %.2f)" % moved)
	_assert(AIDM._heavy_creep_penalty(members, [Vector2(430.0, 720.0)], Vector2(430.0, 600.0), Vector2(430.0, 720.0), ["VEHICLE"], v),
		"the penalty screen rejects that spot")
	_knob("FIX_MOVE_TERRAIN_11E", 1.0)  # areas are enterable regions: the path screen lets the spot through
	var diag := {}
	var hc = _stage(snap, OBJ_FAR, diag, "V")
	AIDM._config_overrides.erase("FIX_MOVE_TERRAIN_11E")
	var rej: Dictionary = diag.get("rej", {})
	# The ladder mirror (_mc_place_fail: the move cap less the 2" cost) or the
	# penalty screen itself — either way the terrain cost keeps it out.
	_assert(int(rej.get("penalty", 0)) + int(rej.get("path", 0)) + int(rej.get("place", 0)) >= 1,
		"a spot into the area was screened out (rej %s)" % str(rej))
	_assert(hc.is_empty() or not _all_in_area(hc.dests, "A"), "no creep into the area is returned")

func test_on_attached_character_carried() -> void:
	print("\n--- (j) ON: an attached CHARACTER is carried along — counted in the 3\" check and in the cover ---")
	var snap = _board()
	var c := _add(snap, "C", 1, [Vector2(505.0, 605.0)], [HEAVY_BOLTER, SPEAR_M], ["INFANTRY", "CHARACTER"], 6, 40, 100)
	c["attached_to"] = "B"
	snap.units["B"].attachment_data.attached_characters = ["C"]
	var diag := {}
	var hc = _stage(snap, OBJ_FAR, diag)
	_assert(not hc.is_empty(), "the stage creeps (diag %s)" % str(diag))
	if hc.is_empty():
		return
	var members: Array = AIDM._move_cover_members(snap.units["B"], snap, true)
	var pos: Array = AIDM._mfs_positions_from_dests(members, hc.dests)
	var c_pos := Vector2.INF
	var c_orig := Vector2.INF
	for i in range(members.size()):
		if members[i].is_char:
			c_pos = pos[i]
			c_orig = members[i].orig
	_assert(c_pos != Vector2.INF and str(tm.area_at(c_pos).get("id", "")) == "A", "the character's centre ends inside area A too")
	_assert(c_orig.distance_to(c_pos) / PX <= 3.0, "the character moves 3\" or less (got %.2f)" % (c_orig.distance_to(c_pos) / PX))
	_assert(float(hc.check.moved_in) >= c_orig.distance_to(c_pos) / PX - 1e-6, "the moved check counts the character")

func test_guard_recheck_three_inch_limit() -> void:
	print("\n--- (k) guard: the re-check drops destinations that move a model more than 3\" ---")
	_reset()
	var snap = _board()
	var members: Array = AIDM._move_cover_members(snap.units["B"], snap, true)
	var dests := {}
	for mb in members:
		var p: Vector2 = mb.orig + Vector2(0.0, 100.0)
		dests[str(mb.model.id)] = [p.x, p.y]
	dests["m1"] = [B_FORM[0].x, B_FORM[0].y + 3.4 * PX]
	var check: Dictionary = AIDM._heavy_creep_recheck({"unit_id": "B", "members": members}, dests)
	_assert(not bool(check.keep) and str(check.why).find("3\"") >= 0, "keep == false and the why names the 3\" limit (got %s)" % str(check.why))
	_assert(absf(float(check.moved_in) - 3.4) < 0.01, "moved_in = 3.4\" (got %.2f)" % float(check.moved_in))

func test_aiplayer_move_cap_helper() -> void:
	print("\n--- (l) AIPlayer._ai_move_cap_for: a re-plan stays inside the decision's cap ---")
	var ai = root.get_node_or_null("AIPlayer")
	_assert(ai != null, "AIPlayer autoload present")
	if ai == null:
		return
	_assert(is_equal_approx(ai._ai_move_cap_for({"_ai_move_cap_inches": 3.0}, 6.0), 3.0), "with the key: min(M, 3\") = 3\"")
	_assert(is_equal_approx(ai._ai_move_cap_for({"_ai_move_cap_inches": 3.0}, 2.0), 2.0), "a cap above M never raises it")
	_assert(is_equal_approx(ai._ai_move_cap_for({}, 6.0), 6.0), "without the key: M, as before")

func test_aiplayer_replan_call_sites() -> void:
	print("\n--- (l2) AIPlayer's re-plan call sites: a deferred move is re-planned only below the creep's 3\"; a staging retry scales 3\", not M ---")
	var ai = root.get_node_or_null("AIPlayer")
	_assert(ai != null, "AIPlayer autoload present")
	if ai == null:
		return
	var creep := {"type": "BEGIN_NORMAL_MOVE", "_ai_move_cap_inches": 3.0}
	var plain := {"type": "BEGIN_NORMAL_MOVE"}
	var adv := {"type": "BEGIN_ADVANCE"}
	# _deferred_move_replan: the rule _execute_pending_advance_move applies. The
	# cases that tell it from the old abs(cap - M) > 0.1 test: a cap of 3" or
	# more that differs from M.
	var r: Dictionary = ai._deferred_move_replan(creep, 8.0, 6.0)
	_assert(not bool(r.replan), "creep, cap raised to M+2 = 8\" (FUNGUS-FUEL INJECTION): no re-plan — the old test re-planned at 8\" and lost the creep")
	r = ai._deferred_move_replan(creep, 4.0, 6.0)
	_assert(not bool(r.replan), "creep, cap lowered to 4\" (a -2\" debuff): no re-plan — the old test re-planned at 4\"")
	r = ai._deferred_move_replan(creep, 2.0, 6.0)
	_assert(bool(r.replan) and is_equal_approx(float(r.cap), 2.0), "creep, cap 2\": re-planned within 2\" (got %s)" % str(r))
	r = ai._deferred_move_replan(plain, 8.0, 6.0)
	_assert(bool(r.replan) and is_equal_approx(float(r.cap), 8.0) and is_equal_approx(float(r.estimate), 6.0),
		"no key: a normal move planned at M 6 with cap 8 is re-planned at 8\", as before (got %s)" % str(r))
	r = ai._deferred_move_replan(plain, 6.0, 6.0)
	_assert(not bool(r.replan), "no key: cap == M, no re-plan")
	r = ai._deferred_move_replan(adv, 7.0, 6.0)
	_assert(bool(r.replan) and is_equal_approx(float(r.estimate), 8.0) and is_equal_approx(float(r.cap), 7.0),
		"an Advance planned at M+2 = 8\" that rolled 7\": re-planned at 7\" (got %s)" % str(r))
	r = ai._deferred_move_replan(adv, 8.0, 6.0)
	_assert(not bool(r.replan), "an Advance that rolled its estimate: no re-plan")
	_assert(is_equal_approx(ai._retry_move_inches(creep, 6.0, 0.75), 2.25) and is_equal_approx(ai._retry_move_inches(plain, 6.0, 0.75), 4.5),
		"staging retry at 75%: 2.25\" for a creep (the old code: 4.5\"), 4.5\" without the key")
	# The call sites' own steps on a real board in GameState (they stage nothing):
	# the creep decide() returns, re-planned as the deferred move and as the
	# first staging retry would.
	var snap = _board()
	_fix(1.0)
	var d = _decide(snap)
	_assert(str(d.get("type", "")) == "BEGIN_NORMAL_MOVE" and d.has("_ai_move_cap_inches"), "premise: decide() creeps")
	if not d.has("_ai_model_destinations"):
		return
	var had_units: bool = gs.state.has("units")
	var prev_units = gs.state.get("units", {})
	gs.state["units"] = snap.units.duplicate(true)
	var models: Array = AIDM._get_alive_models_with_positions(snap.units["B"])
	var dests0: Dictionary = (d._ai_model_destinations as Dictionary).duplicate(true)
	var dec_hi: Dictionary = d.duplicate(true)
	ai._replan_deferred_move(1, dec_hi, "B", 8.0)
	_assert(str(dec_hi._ai_model_destinations) == str(dests0), "_replan_deferred_move, cap 8\": the creep's own destinations are kept")
	var dec_lo: Dictionary = d.duplicate(true)
	ai._replan_deferred_move(1, dec_lo, "B", 2.0)
	var mv_lo: float = AIDM._destinations_max_move_inches(models, dec_lo._ai_model_destinations)
	_assert(str(dec_lo._ai_model_destinations) != str(dests0) and mv_lo <= 2.0 + 0.05,
		"_replan_deferred_move, cap 2\": re-planned, no model moves more than 2\" (got %.2f\")" % mv_lo)
	var dec_plain: Dictionary = d.duplicate(true)
	dec_plain.erase("_ai_move_cap_inches")
	var dec_plain_retry: Dictionary = dec_plain.duplicate(true)
	ai._replan_deferred_move(1, dec_plain, "B", 8.0)
	var mv_plain: float = AIDM._destinations_max_move_inches(models, dec_plain._ai_model_destinations)
	_assert(str(dec_plain._ai_model_destinations) != str(dests0) and mv_plain > 3.0,
		"_replan_deferred_move without the key, cap 8\": re-planned at 8\" as before (largest model move %.2f\")" % mv_plain)
	var unit_fresh: Dictionary = gs.state.units["B"]
	var rd_creep: Dictionary = ai._retry_move_destinations(1, unit_fresh, "B", d, 6.0, 0.75)
	var mv_rc: float = AIDM._destinations_max_move_inches(models, rd_creep)
	_assert(not rd_creep.is_empty() and mv_rc <= 2.25 + 0.05,
		"_retry_move_destinations at 75%%: the creep is re-planned within 2.25\" (got %.2f\")" % mv_rc)
	var rd_plain: Dictionary = ai._retry_move_destinations(1, unit_fresh, "B", dec_plain_retry, 6.0, 0.75)
	var mv_rp: float = AIDM._destinations_max_move_inches(models, rd_plain)
	_assert(mv_rp > 2.25 + 0.05, "_retry_move_destinations without the key: 75%% of M (4.5\"), as before (got %.2f\")" % mv_rp)
	if had_units:
		gs.state["units"] = prev_units
	else:
		gs.state.erase("units")

func test_ledger_sums() -> void:
	print("\n--- (m) ledger: the creep's terms sum to its gain ---")
	var snap = _board()
	var diag := {}
	var hc = _stage(snap, OBJ_FAR, diag)
	_assert(not hc.is_empty(), "the stage creeps")
	if hc.is_empty():
		return
	_assert(absf(_sum(hc.check.terms) - float(hc.check.gain)) < 1e-6, "Σ terms == gain (%s vs %.4f)" % [str(hc.check.terms), float(hc.check.gain)])
	_assert(float(hc.check.gain) >= AIDM.HEAVY_CREEP_MIN_GAIN, "the kept gain clears HEAVY_CREEP_MIN_GAIN")
	for k in hc.check.terms:
		_assert(AIReasoningGlossary.TERMS.has(str(k)), "glossary labels ledger key %s" % str(k))

func test_composes_with_batch1_flags() -> void:
	print("\n--- (n) composes: FIX_MOVE_COVER / FIX_MOVE_FOR_SHOT / FIX_MOVE_FOR_CHARGE / FIX_INDIRECT_STATIONARY on change nothing; with F002 the creep prices Hidden OR the shot, never both ---")
	var snap = _board()
	_fix(1.0)
	var d_alone = _decide(snap)
	for k in ["FIX_MOVE_COVER", "FIX_MOVE_FOR_SHOT", "FIX_MOVE_FOR_CHARGE", "FIX_INDIRECT_STATIONARY"]:
		_knob(k, 1.0)
	var d_all = _decide(snap)
	_assert(_shape(d_all) == _shape(d_alone), "the same creep with every batch-1 flag on (T7-26's branch returns before their stages)")
	_knob("HIDDEN_FORFEIT_PENALTY", 3.0)
	var d_f002 = _decide(snap)
	_assert(str(d_f002.get("type", "")) == "BEGIN_NORMAL_MOVE" and d_f002.has("_ai_move_cap_inches"),
		"with HIDDEN_FORFEIT_PENALTY 3 it still creeps (got %s)" % _shape(d_f002))
	# F002 on: 13.09 voids Hidden next turn after a ranged attack this turn, so
	# the creep prices Hidden (hc_cover) OR the shot (hc_lane), never both, and
	# claims no +1 to hit for a shot it would hold fire on.
	var note_f := "\n".join(PackedStringArray(d_f002.get("_ai_move_adjustments", [])))
	var hidden_claim := note_f.find("ends Hidden next turn") >= 0
	_assert(hidden_claim, "F002: the note says it ends Hidden next turn (got %s)" % note_f)
	_assert(not (hidden_claim and note_f.find("can see") >= 0), "the note never claims both Hidden next turn and a new sight line (got %s)" % note_f)
	_assert(not hidden_claim or (note_f.find("keep +1 to hit") < 0 and note_f.find("in its sights") < 0),
		"a Hidden note claims no kept +1 to hit and no target kept in its sights (got %s)" % note_f)
	var desc_f := str(d_f002.get("_ai_description", ""))
	_assert(desc_f.begins_with("B moves toward obj (") and desc_f.find("ending Hidden") >= 0
		and desc_f.find("to keep its [HEAVY] +1 to hit") < 0 and desc_f.find("into cover") < 0,
		"the action line says 'ending Hidden', not 'into cover' or the +1 to hit (got %s)" % desc_f)
	var diag := {}
	var hc = _stage(snap, OBJ_FAR, diag)
	_assert(not hc.is_empty(), "F002: the stage creeps (diag %s)" % str(diag))
	if not hc.is_empty():
		var ev: Dictionary = hc.check.ev
		var terms: Dictionary = hc.check.terms
		print("  F002 creep: terms %s gain %.3f ev all_hidden=%s hold_fire_ok=%s n_blind=%d in_area=%s why=%s" % [
			str(terms), float(hc.check.gain), str(ev.get("all_hidden")), str(ev.get("hold_fire_ok")),
			int(ev.get("n_blind", 0)), str(ev.get("in_area")), str(hc.check.why_code)])
		_assert(bool(ev.get("all_hidden", false)) and bool(ev.get("hold_fire_ok", false)),
			"premise: _mc_eval credits Hidden at the creep spot (every model Hidden, F002 would hold fire)")
		_assert(bool(hc.check.f002_hold), "the re-check predicts F002 holds fire at the creep spot")
		_assert(absf(float(terms.get("hc_lane", 0.0))) < 1e-9, "hc_lane = 0 where hold_fire_ok holds: no shot priced (got %s)" % str(terms))
		_assert(float(terms.get("hc_cover", 0.0)) > 0.0 and str(hc.check.why_code) == "hidden",
			"the gain is the Hidden in hc_cover and the why says so (why %s)" % str(hc.check.why_code))
		_assert(absf(_sum(terms) - float(hc.check.gain)) < 1e-6, "Σ terms == gain")
		# The engine half of the claim: the real shooting decision from the
		# destinations holds fire (F002) — the shot hc_lane no longer prices.
		var sb := _board_at(snap, "B", hc.dests)
		sb.units["B"].flags["moved"] = true
		sb.units["B"].flags["moved_max_inches"] = float(hc.check.moved_in)
		sb.units["B"]["status"] = GameStateData.UnitStatus.MOVED
		_reset()
		var ds: Dictionary = AIDM.decide(8, sb, [{"type": "SELECT_SHOOTER", "actor_unit_id": "B"}, {"type": "END_SHOOTING"}], 1)
		_assert(str(ds.get("type", "")) == "SKIP_UNIT", "the shooting decision from the creep spot holds fire to stay Hidden (got %s: %s)" % [
			str(ds.get("type", "")), str(ds.get("_ai_description", ""))])
	for k in ["FIX_MOVE_COVER", "FIX_MOVE_FOR_SHOT", "FIX_MOVE_FOR_CHARGE", "FIX_INDIRECT_STATIONARY", "HIDDEN_FORFEIT_PENALTY"]:
		AIDM._config_overrides.erase(k)
	# F002 off again: the same board's creep shoots, and says so (case (a)).
	var d_back = _decide(snap)
	_assert(str(d_back.get("_ai_description", "")).find("to keep its [HEAVY] +1 to hit") >= 0,
		"F002 off: the action line claims the +1 to hit again (got %s)" % str(d_back.get("_ai_description", "")))

func test_f002_stay_shot_not_taken() -> void:
	print("\n--- (q) F002 holding still: Hidden where it stands with only a chip shot — that shot is priced as not taken ---")
	# Every B base inside the light area A (Hidden, 13.09 as errata'd); T in the
	# open ~25" south is visible (13.10 skips the area B is within) and its
	# heavy bolter's shot is a chip shot (1.7 of T's 15 wounds).
	var snap = _snapshot([_light_area("A", 300.0, 560.0, 560.0, 860.0)], [_obj(OBJ_FAR)])
	_add(snap, "B", 1, B_FORM, [HEAVY_BOLTER, SPEAR_M])
	_add(snap, "T", 2, _line(300.0, 1660.0), [SPEAR_R, SPEAR_M])
	var unit: Dictionary = snap.units["B"]
	var elig: Dictionary = re.get_eligible_targets("B", snap, false)
	_assert(elig.has("T"), "premise (engine): T is an eligible target from where B stands (got %s)" % str(elig.keys()))
	var members: Array = AIDM._move_cover_members(unit, snap, true)
	var hc_min := {"unit": unit, "snapshot": snap, "members": members, "enemies": AIDM._get_enemy_units(snap, 1)}
	var stay_pos: Array = AIDM._move_cover_shift(members, Vector2.ZERO)
	var centroid: Vector2 = AIDM._get_unit_centroid(unit)
	_assert(not AIDM._heavy_creep_f002_holds(hc_min, stay_pos, centroid, elig), "F002 off: no hold-fire predicted (and nothing priced)")
	_knob("HIDDEN_FORFEIT_PENALTY", 3.0)
	_assert(AIDM._heavy_creep_f002_holds(hc_min, stay_pos, centroid, elig), "F002 3: hold-fire predicted where it stands")
	_assert(not AIDM._heavy_creep_f002_holds(hc_min, stay_pos, centroid, {}), "no eligible target: nothing to hold fire on")
	# The real shooting decision agrees with the prediction.
	var sb: Dictionary = snap.duplicate(true)
	sb.units["B"].flags["remained_stationary"] = true
	sb.units["B"].flags["in_engagement"] = false
	sb.units["B"]["status"] = GameStateData.UnitStatus.MOVED
	_reset()
	var ds: Dictionary = AIDM.decide(8, sb, [{"type": "SELECT_SHOOTER", "actor_unit_id": "B"}, {"type": "END_SHOOTING"}], 1)
	_assert(str(ds.get("type", "")) == "SKIP_UNIT", "engine-side: the shooting decision holds fire there (got %s: %s)" % [
		str(ds.get("type", "")), str(ds.get("_ai_description", ""))])
	_fix(1.0)
	var diag := {}
	var hc = _stage(snap, OBJ_FAR, diag)
	print("  stage: %s diag %s" % ["{}" if hc.is_empty() else str(hc.check.terms), str(diag)])
	_assert(bool(diag.get("f002_stay", false)) and float(diag.get("shot_stay", 0.0)) > 0.0,
		"the stage marks the stay's shot as not taken (f002_stay) while its raw shot is > 0 (diag %s)" % str(diag))
	_assert(is_equal_approx(AIDM._hc_taken_shot(1.5, true), 0.0) and is_equal_approx(AIDM._hc_taken_shot(1.5, false), 1.5),
		"_hc_taken_shot: none where F002 holds fire, else the shot")
	AIDM._config_overrides.erase("HIDDEN_FORFEIT_PENALTY")

func test_recheck_own_gtg_budget() -> void:
	print("\n--- (r) the re-check prices Gone to Ground on its own budget (FIX_MOVE_COVER's re-check rule) ---")
	# The review's board: light area A with B north of it, a dense wall W and a
	# 10-model rifle squad S beyond it — the pick's Hidden needs Gone-to-Ground
	# checks (13.11.01), more than half of MOVE_COVER_MAX_GTG_CHECKS.
	var snap = _snapshot([_light_area("A", 300.0, 700.0, 560.0, 860.0), _wall("W", 100.0, 1100.0, 800.0, 1130.0)], [_obj(OBJ_FAR)])
	_add(snap, "B", 1, B_FORM, [HEAVY_BOLTER, SPEAR_M])
	var s_pos: Array = []
	for row_y in [1560.0, 1612.0]:
		for k in range(5):
			s_pos.append(Vector2(302.0 + 52.0 * float(k), row_y))
	_add(snap, "S", 2, s_pos, [RIFLE, SPEAR_M], ["INFANTRY"], 3, 32)
	_fix(1.0)
	_knob("HIDDEN_FORFEIT_PENALTY", 3.0)
	var diag := {}
	var hc = _stage(snap, OBJ_FAR, diag)
	print("  default cap: %s diag why=%s recheck_why=%s best_gain=%s" % ["{}" if hc.is_empty() else str(hc.check.terms),
		str(diag.get("why", "")), str(diag.get("recheck_why", "")), str(diag.get("best_gain", ""))])
	_assert(not hc.is_empty() and str(diag.get("why", "")) == "creep",
		"the picked creep survives its own re-check at the default Gone-to-Ground cap (diag why %s / %s)" % [
			str(diag.get("why", "")), str(diag.get("recheck_why", ""))])
	if not hc.is_empty():
		_assert(int(hc.check.ev.get("n_blind", 0)) >= 1, "the re-check still credits the Hidden the search priced (n_blind %d)" % int(hc.check.ev.get("n_blind", 0)))
		# S stands behind the dense wall: no target from the spot, so no shot to claim.
		_assert(str(hc.check.get("shot_mode", "")) == "no_target" and (hc.check.elig as Dictionary).is_empty(),
			"premise: the engine accepts no target from the spot (shot_mode %s)" % str(hc.check.get("shot_mode", "")))
	var d = _decide(snap)
	var desc := str(d.get("_ai_description", ""))
	_assert(str(d.get("type", "")) == "BEGIN_NORMAL_MOVE" and d.has("_ai_move_cap_inches"),
		"decide(): the creep, not T7-26's hold (got %s)" % desc)
	_assert(desc.find("ending Hidden") >= 0 and desc.find("with no target from there") >= 0 and desc.find("+1 to hit") < 0,
		"no target from the spot: the action line claims no +1 to hit (got %s)" % desc)
	var note := "\n".join(PackedStringArray(d.get("_ai_move_adjustments", [])))
	_assert(note.find("no model moves more than 3\"") >= 0 and note.find("it has no target from there") >= 0 and note.find("keep +1 to hit") < 0,
		"the note keeps the 3\" anchor and says it has no target there (got %s)" % note)
	AIDM._config_overrides.erase("HIDDEN_FORFEIT_PENALTY")

func test_guard_t726_not_holding_no_read() -> void:
	print("\n--- (o) guard: T7-26 does not hold (the objective is within M) — on == off, the flag never read ---")
	# ~5.75" south of the centroid (within M: T7-26 lets it move) and more than
	# the range (3.79" + a base radius) from every model (no hold plan).
	var snap = _board(HEAVY_BOLTER, [_obj(Vector2(406.0, 868.0))])
	_fix(1.0)
	AIDM.take_param_reads()
	var d_on = _decide(snap)
	var reads := _reads(d_on)
	_fix(0.0)
	var d_off = _decide(snap)
	_assert(_shape(d_on) == _shape(d_off) and str(d_on.get("type", "")) != "REMAIN_STATIONARY",
		"decide(): on == off, not a hold (got %s)" % _shape(d_on))
	_assert(not reads.has("FIX_HEAVY_CREEP"), "FIX_HEAVY_CREEP is not read without a T7-26 hold")
	_assert(_behind_flag(reads).filter(func(k): return str(k).begins_with("HEAVY_CREEP_")).is_empty(), "no HEAVY_CREEP_* knob is read")

func test_guard_elevated_and_aircraft() -> void:
	print("\n--- (p) guard: an elevated model (13.06 descent is not modelled) or an AIRCRAFT — the hold is kept ---")
	var snap = _board()
	snap.units["B"].models[0]["elevation_inches"] = 3.0
	_fix(1.0)
	var d_elev = _decide(snap)
	_assert(str(d_elev.get("type", "")) == "REMAIN_STATIONARY", "elevated model: REMAIN_STATIONARY (got %s)" % _shape(d_elev))
	var diag := {}
	var hc = _stage(snap, OBJ_FAR, diag)
	_assert(hc.is_empty() and str(diag.get("why", "")) == "elevated", "the stage says why (got %s)" % str(diag.get("why", "")))
	var snap2 = _board()
	snap2.units["B"].meta.keywords = ["VEHICLE", "AIRCRAFT", "FLY"]
	var diag2 := {}
	var hc2 = _stage(snap2, OBJ_FAR, diag2)
	_assert(hc2.is_empty() and str(diag2.get("why", "")) == "aircraft", "an AIRCRAFT never creeps (got %s)" % str(diag2.get("why", "")))
