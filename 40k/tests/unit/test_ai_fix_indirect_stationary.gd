extends SceneTree

# FIX_INDIRECT_STATIONARY (movement: Remain Stationary to arm [INDIRECT FIRE]
# — 11e 10.07 Indirect shooting, 09.04 Remain Stationary, 13.08 benefit of
# cover, 13.09 Hidden as errata'd, 02.02.01 the BS clamp at 6+). An
# [INDIRECT FIRE] attack at a target none of the unit's models can see gives
# it the benefit of cover, cannot re-roll the hit roll and fails on an
# unmodified 1-5 — only 1-3 if the unit Remained Stationary this turn AND a
# friendly unit sees the target. Any move, even 1", loses the band, and the
# AI never asked: a battery assigned to move walked off its armed spot (exam
# mv09_arm_the_indirect_battery).
#
# Fix: a stage AFTER the mover in the normal-move chain
# (_indirect_stationary_evaluate) prices next Shooting phase's damage with
# RulesEngine.preview_attack on two hypothetical boards — the unit Remaining
# Stationary where it stands, and at the destinations the chain settled on —
# plus what the move buys on the objectives, and returns REMAIN_STATIONARY
# when staying wins by INDIRECT_STATIONARY_MIN_MARGIN, its best target is
# unseen, the engine's band there is 1-3 and a RELIABLE friendly unit sees it.
#
# Cases: ON — decide() stays with the note, the action line and the hold key,
# and the engine agrees the band is armed; param 0 — byte-identical decide()
# output, the flag read is the only footprint; guards — no [INDIRECT FIRE]
# weapon (the flag is never read), no spotter, spotters that have yet to move
# (and an attached CHARACTER judged by its bodyguard), a BS 5+ battery (6+
# after the indirect cover either way), a target it can see, an objective the
# move would take (the term decides), it cannot arm (disembarked, cannot
# shoot), a minority [INDIRECT FIRE] unit, a planned charge / an Advance
# plan, F002 hold fire; the ledgers sum and price 3x for BS 3+; [HEAVY] is
# priced as the engine applies it; _finalize_movement_decision stops booking
# the plan's objective; the batch-1 flags compose with it.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_fix_indirect_stationary.gd
# (runs once the scene tree is up: the stage reads RulesEngine /
# TerrainManager / MissionManager / GameState)

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const GameStateData = preload("res://autoloads/GameState.gd")
const PX := 40.0  # pixels per inch
const OBJ := Vector2(430.0, 1300.0)       # open ground, ~12.9" from the battery's front: no arrival this move
const OBJ_NEAR := Vector2(430.0, 960.0)   # (h): ~4.4" — the move reaches its range
const STEP := 65.0
const B_X0 := 300.0
const B_Y := 600.0
const T_X0 := 1300.0
const T_Y := 1500.0
const S_X0 := 900.0
const S_Y := 1300.0
## The 11e Whirlwind vengeance launcher's BS and keywords (no [HEAVY]).
const MORTAR := {"name": "Mortar", "type": "Ranged", "range": "36", "attacks": "2", "ballistic_skill": "3",
	"strength": "8", "ap": "-2", "damage": "2", "special_rules": "blast, indirect fire"}
const LOBBA := {"name": "Lobba", "type": "Ranged", "range": "36", "attacks": "2", "ballistic_skill": "5",
	"strength": "8", "ap": "-2", "damage": "2", "special_rules": "blast, indirect fire"}
const DIRECT_MORTAR := {"name": "Direct mortar", "type": "Ranged", "range": "36", "attacks": "2", "ballistic_skill": "3",
	"strength": "8", "ap": "-2", "damage": "2", "special_rules": "blast"}
const HEAVY_MORTAR := {"name": "Heavy mortar", "type": "Ranged", "range": "36", "attacks": "2", "ballistic_skill": "4",
	"strength": "8", "ap": "-2", "damage": "2", "special_rules": "blast, heavy, indirect fire"}
const PLAIN_MORTAR4 := {"name": "Mortar four", "type": "Ranged", "range": "36", "attacks": "2", "ballistic_skill": "4",
	"strength": "8", "ap": "-2", "damage": "2", "special_rules": "blast, indirect fire"}
const MISSILE := {"name": "Hunter missile", "type": "Ranged", "range": "48", "attacks": "1", "ballistic_skill": "3",
	"strength": "10", "ap": "-2", "damage": "6", "special_rules": "indirect fire, one shot"}
const SPEAR_R := {"name": "Guardian spear - Ranged", "type": "Ranged", "range": "24", "attacks": "2",
	"ballistic_skill": "2", "strength": "4", "ap": "-1", "damage": "2", "special_rules": "assault"}
const SPEAR_M := {"name": "Guardian spear - Melee", "type": "Melee", "range": "Melee", "attacks": "5",
	"weapon_skill": "2", "strength": "7", "ap": "-2", "damage": "2", "special_rules": ""}
const BOLTGUN := {"name": "Boltgun", "type": "Ranged", "range": "24", "attacks": "2", "ballistic_skill": "3",
	"strength": "4", "ap": "0", "damage": "1", "special_rules": ""}
const CCW := {"name": "Close combat weapon", "type": "Melee", "range": "Melee", "attacks": "2",
	"weapon_skill": "3", "strength": "4", "ap": "0", "damage": "1", "special_rules": ""}
const KNOBS := ["FIX_INDIRECT_STATIONARY", "INDIRECT_STATIONARY_OBJECTIVE_PTS", "INDIRECT_STATIONARY_TRUST_UNMOVED",
	"HIDDEN_FORFEIT_PENALTY", "FIX_MOVE_COVER", "FIX_MOVE_FOR_SHOT", "FIX_MOVE_FOR_CHARGE"]

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
	print("\n=== FIX_INDIRECT_STATIONARY: Remain Stationary to arm [INDIRECT FIRE] (11e 10.07 / 09.04) ===\n")
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

	test_on_spotted_battery_stays()
	test_param_zero_restores_old_reads()
	test_guard_no_indirect_weapon_no_read()
	test_guard_no_spotter_moves()
	test_guard_unreliable_spotter_moves()
	test_guard_bs5_battery_moves()
	test_guard_visible_target_moves()
	test_guard_objective_arrival()
	test_guard_cannot_arm()
	test_guard_minority_indirect_moves()
	test_guard_charge_and_advance_unchanged()
	test_guard_f002_hold_fire_predicted()
	test_ledger_sums_and_ratio()
	test_heavy_indirect_priced()
	test_finalize_intent_not_credited()
	test_composes_with_batch1_flags()

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

## A dense terrain AREA (13.09 as errata'd: Hidden in light OR dense areas).
func _dense_area(id: String, x0: float, y0: float, x1: float, y1: float) -> Dictionary:
	return {"id": id, "piece_class": "area", "type": "ruins", "category": "dense", "height_category": "tall",
		"can_move_through": {"INFANTRY": true, "MONSTER": false, "VEHICLE": false}, "polygon": _rect(x0, y0, x1, y1)}

## The target's hiding place: every T base overlaps it.
func _hide() -> Dictionary:
	return _dense_area("hide", 1250.0, 1460.0, 1610.0, 1540.0)

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

## The base case: battery B (5 x 40 mm, `battery_weapon` + a melee spear) on
## the west, its only target T (5 x 40 mm, 150 pts, W3: 10 pts per wound)
## Hidden in a dense area ~27" away — beyond its 15" detection range before
## and after any 6" move — and the spotter S (4 x 32 mm) ~6" from T with a
## clear line. S is not offered a move (it counts as unable to move: a
## reliable spotter). One open-ground objective ~12.9" south of B.
func _board(battery_weapon: Dictionary = MORTAR, hidden: bool = true, objs: Array = [], spotter: bool = true) -> Dictionary:
	var pieces: Array = [_hide()] if hidden else []
	var snap = _snapshot(pieces, objs if not objs.is_empty() else [_obj(OBJ)])
	_add(snap, "B", 1, _line(B_X0, B_Y), [battery_weapon, SPEAR_M])
	_add(snap, "T", 2, _line(T_X0, T_Y), [SPEAR_M])
	if spotter:
		_add(snap, "S", 1, _line(S_X0, S_Y, 4, 55.0), [BOLTGUN, CCW], ["INFANTRY"], 1, 32, 45)
	return snap

func _knob(knob: String, v: float) -> void:
	AIDM._config_overrides[knob] = v

func _fix(v: float) -> void:
	_knob("FIX_INDIRECT_STATIONARY", v)

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

func _decide(snap: Dictionary, inject_charge_on: String = "") -> Dictionary:
	_reset()
	var board: Dictionary = snap.duplicate(true)
	if inject_charge_on != "":
		AIDM._phase_plan[1] = {"charge_intent": {"B": {"target_id": inject_charge_on, "target_name": inject_charge_on,
			"score": 10.0, "distance_inches": 20.0}}, "lock_targets": [], "shooting_lanes": {},
			"charge_target_ids": [inject_charge_on]}
		AIDM._phase_plan_built[1] = true
		AIDM._phase_plan_round = int(board.get("meta", {}).get("battle_round", 1))
	return AIDM.decide(7, board, _actions(), 1)

func _shape(d: Dictionary) -> String:
	return "%s | %s | %s | %s" % [str(d.get("type", "")), str(d.get("_ai_model_destinations", {})),
		str(d.get("_ai_move_adjustments", [])), str(d.get("_ai_description", ""))]

## The board as it would stand with `uid`'s models at `dests`.
func _board_at(snap: Dictionary, uid: String, dests: Dictionary) -> Dictionary:
	var s2: Dictionary = snap.duplicate(true)
	for m in s2.units[uid].models:
		var mid := str(m.id)
		if dests.has(mid):
			m["position"] = Vector2(float(dests[mid][0]), float(dests[mid][1]))
	s2.units[uid].flags["in_engagement"] = false
	return s2

## The flag-off destinations of B's move (decide() with the flag at 0).
func _off_dests(snap: Dictionary) -> Dictionary:
	_fix(0.0)
	var d = _decide(snap)
	return d.get("_ai_model_destinations", {})

## A direct call of the stage on `dests` (the move the chain settled on).
## `movable` / `plan`: the movable-units map and the plan's assignments the
## executor passes (default: only B movable, no plan entries).
func _evaluate(snap: Dictionary, dests: Dictionary, target: Vector2 = OBJ, movable: Dictionary = {},
		plan: Dictionary = {}) -> Dictionary:
	var unit: Dictionary = snap.units["B"]
	var mv: Dictionary = movable if not movable.is_empty() else {"B": ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]}
	return AIDM._indirect_stationary_evaluate(unit, "B", snap, AIDM._get_unit_centroid(unit), target, "obj",
		dests, AIDM._get_objectives(snap), AIDM._get_enemy_units(snap, 1), 1, mv, plan)

func _sum(terms: Dictionary) -> float:
	var s := 0.0
	for k in terms:
		s += float(terms[k])
	return s

# --- (a) ON -----------------------------------------------------------------

func test_on_spotted_battery_stays() -> void:
	print("\n--- (a) ON: a spotted BS 3+ battery Remains Stationary instead of walking off the 1-3 band ---")
	var snap = _board()
	var t: Dictionary = snap.units["T"]
	var hid := true
	for m in t.models:
		hid = hid and bool(tm.is_model_hidden(m, t))
	_assert(hid, "precondition (engine): every T model is Hidden (13.09, dense area)")
	_assert(not bool(re.unit_sight_line("B", "T", snap, false).has_los), "precondition (engine): B cannot see T")
	_assert(bool(re.unit_sight_line("S", "T", snap, false).has_los), "precondition (engine): S sees T (within its detection range)")
	_assert(re.get_eligible_targets("B", _board_at(snap, "B", {}), false).has("T"), "precondition (engine): T is an eligible [INDIRECT FIRE] target for B (range alone)")
	var off_dests := _off_dests(snap)
	_assert(not off_dests.is_empty(), "flag off: B makes its planned Normal move")
	var moved := _board_at(snap, "B", off_dests)
	_assert(not bool(re.unit_sight_line("B", "T", moved, false).has_los), "precondition (engine): T is still unseen after the move")
	_fix(1.0)
	var d = _decide(snap)
	print("  decision: %s" % _shape(d))
	_assert(str(d.get("type", "")) == "REMAIN_STATIONARY" and str(d.get("actor_unit_id", "")) == "B",
		"fix on: B Remains Stationary (got %s)" % str(d.get("type", "")))
	_assert(str(d.get("_ai_description", "")).begins_with("B remains stationary to arm its indirect fire at T"),
		"the action line says why (got %s)" % str(d.get("_ai_description", "")))
	_assert(not str(d.get("_ai_description", "")).contains("holds obj"), "the action line is not a 'holds obj' line (the plan said MOVE)")
	_assert(bool(d.get("_ai_indirect_hold", false)), "the decision carries _ai_indirect_hold")
	var adj: Array = d.get("_ai_move_adjustments", [])
	_assert(not adj.is_empty() and str(adj[0]).contains("fail only on an unmodified 1-3 instead of 1-5 (10.07)") and str(adj[0]).contains("S can see T"),
		"the first move-shape note names the band and the spotter (got %s)" % str(adj))
	_assert(adj.size() >= 2 and str(adj[1]).begins_with("Gives up") and str(adj[1]).contains("toward obj"),
		"the second note prices the progress given up (got %s)" % str(adj))
	var steps := str(d.get("_ai_thinking_steps", []))
	_assert(steps.contains("stays put to arm its indirect fire") and steps.contains("Shot if it stays"),
		"the thinking steps carry the ledger in the glossary's words")
	# Engine truth: as the Movement phase leaves it, B's band is 1-3.
	var st_board := _board_at(snap, "B", {})
	st_board.units["B"].flags["remained_stationary"] = true
	st_board.units["B"].flags["moved_max_inches"] = 0.0
	_assert(int(re._indirect_hit_fail_band_11e("B", "T", st_board)) == 3, "engine: stationary B's hits at T fail only on 1-3")
	var mv_board := _board_at(snap, "B", off_dests)
	mv_board.units["B"].flags["remained_stationary"] = false
	_assert(int(re._indirect_hit_fail_band_11e("B", "T", mv_board)) == 5, "engine: after the move they fail on 1-5")

# --- (b) param 0 --------------------------------------------------------------

func test_param_zero_restores_old_reads() -> void:
	print("\n--- (b) FIX_INDIRECT_STATIONARY = 0 / unset: decide() is byte-identical; the flag read is the only footprint ---")
	var snap = _board()
	AIDM._config_overrides.erase("FIX_INDIRECT_STATIONARY")
	var d_unset = _decide(snap)
	var reads_unset: Dictionary = AIDM.take_param_reads()
	_fix(0.0)
	var d_zero = _decide(snap)
	var reads_zero: Dictionary = AIDM.take_param_reads()
	_fix(1.0)
	var d_on = _decide(snap)
	print("  unset: %s" % _shape(d_unset))
	print("  zero : %s" % _shape(d_zero))
	print("  on   : %s" % _shape(d_on))
	_assert(_shape(d_unset) == _shape(d_zero), "0.0 == unset: same type, destinations, notes and description")
	_assert(str(d_zero.get("type", "")) == "BEGIN_NORMAL_MOVE", "off: the planned Normal move")
	_assert(_shape(d_on) != _shape(d_zero), "on differs (it stays)")
	_assert(not d_zero.has("_ai_indirect_hold"), "off: no hold key")
	_assert(reads_zero.has("FIX_INDIRECT_STATIONARY") and reads_unset.has("FIX_INDIRECT_STATIONARY"),
		"off: the flag is read for a unit with an [INDIRECT FIRE] weapon")
	var behind: Array = []
	for k in reads_zero:
		if str(k).begins_with("INDIRECT_STATIONARY_"):
			behind.append(k)
	_assert(behind.is_empty(), "off: no INDIRECT_STATIONARY_* knob is read behind the flag (got %s)" % str(behind))
	var reads_keys_zero: Array = reads_zero.keys()
	var reads_keys_unset: Array = reads_unset.keys()
	reads_keys_zero.sort()
	reads_keys_unset.sort()
	_assert(reads_keys_zero == reads_keys_unset, "0.0 and unset read the same parameters")

# --- (c) guards ---------------------------------------------------------------

func test_guard_no_indirect_weapon_no_read() -> void:
	print("\n--- (c) guard: no [INDIRECT FIRE] weapon — unchanged, and the flag is never read ---")
	var snap = _board(DIRECT_MORTAR)
	_assert(not AIDM._unit_has_indirect_weapon(snap.units["B"], snap), "precondition: B has no [INDIRECT FIRE] weapon")
	_fix(1.0)
	var d_on = _decide(snap)
	var reads_on: Dictionary = AIDM.take_param_reads()
	_fix(0.0)
	var d_off = _decide(snap)
	_assert(_shape(d_on) == _shape(d_off), "decide(): on == off")
	_assert(not reads_on.has("FIX_INDIRECT_STATIONARY"), "the flag is not read at all (zero footprint for armies without artillery)")
	# [ONE SHOT] indirect weapons do not count (24.26: it can fire once a battle).
	var missile_unit := {"meta": {"weapons": [MISSILE, SPEAR_M]}, "attachment_data": {"attached_characters": []}}
	_assert(not AIDM._unit_has_indirect_weapon(missile_unit, snap), "an [INDIRECT FIRE, ONE SHOT] missile is not a battery weapon")

func test_guard_no_spotter_moves() -> void:
	print("\n--- (c) guard: no friendly unit sees the target — nothing to arm, it moves ---")
	var snap = _board()
	for m in snap.units["S"].models:
		m["alive"] = false
	var dests := _off_dests(snap)
	var ind := _evaluate(snap, dests)
	_assert(ind.is_empty(), "the stage finds nothing to arm (band 1-5 even when stationary)")
	_fix(1.0)
	var d_on = _decide(snap)
	_fix(0.0)
	var d_off = _decide(snap)
	_assert(_shape(d_on) == _shape(d_off) and str(d_on.get("type", "")) == "BEGIN_NORMAL_MOVE", "decide(): the flag-off Normal move")

func test_guard_unreliable_spotter_moves() -> void:
	print("\n--- (c) guard: only a spotter that has yet to move sees the target — it moves (unless trusted) ---")
	var snap = _board()
	var dests := _off_dests(snap)
	var movable := {"B": ["BEGIN_NORMAL_MOVE", "REMAIN_STATIONARY"], "S": ["BEGIN_NORMAL_MOVE", "REMAIN_STATIONARY"]}
	var plan_move := {"S": {"action": "move", "objective_id": "obj"}}
	_fix(1.0)
	var ind := _evaluate(snap, dests, OBJ, movable, plan_move)
	_assert(ind.is_empty(), "S movable, planned to move, not yet moved: no reliable spotter -> {}")
	_knob("INDIRECT_STATIONARY_TRUST_UNMOVED", 1.0)
	var ind_t := _evaluate(snap, dests, OBJ, movable, plan_move)
	_assert(not ind_t.is_empty() and bool(ind_t.stay) and str(ind_t.spotter_id) == "S", "TRUST_UNMOVED 1.0: S counts and B stays")
	AIDM._config_overrides.erase("INDIRECT_STATIONARY_TRUST_UNMOVED")
	var ind_h := _evaluate(snap, dests, OBJ, movable, {"S": {"action": "hold", "objective_id": "obj"}})
	_assert(not ind_h.is_empty() and bool(ind_h.stay) and str(ind_h.spotter_why) == "is planned to hold", "S planned to hold: reliable, B stays")
	snap.units["S"].flags["moved"] = true
	var ind_m := _evaluate(snap, dests, OBJ, movable, plan_move)
	_assert(not ind_m.is_empty() and bool(ind_m.stay) and str(ind_m.spotter_why) == "has already moved", "S has already moved this phase: reliable, B stays")
	# An attached CHARACTER is judged by the bodyguard it moves with.
	var snap2 = _board()
	for m in snap2.units["S"].models:
		m["alive"] = false
	_add(snap2, "BG", 1, _line(100.0, 2000.0, 3), [BOLTGUN, CCW])
	var c = _add(snap2, "C", 1, [Vector2(1150.0, 1300.0)], [BOLTGUN, CCW], ["INFANTRY", "CHARACTER"])
	c["attached_to"] = "BG"
	snap2.units["BG"]["attachment_data"] = {"attached_characters": ["C"]}
	_assert(bool(re.unit_sight_line("C", "T", snap2, false).has_los), "precondition (engine): the attached character C sees T")
	var dests2 := _off_dests(snap2)
	_fix(1.0)
	var movable2 := {"B": ["BEGIN_NORMAL_MOVE", "REMAIN_STATIONARY"], "BG": ["BEGIN_NORMAL_MOVE", "REMAIN_STATIONARY"]}
	var ind_c := _evaluate(snap2, dests2, OBJ, movable2, {"BG": {"action": "move", "objective_id": "obj"}})
	_assert(ind_c.is_empty(), "C's bodyguard has yet to move: C is not a reliable spotter")
	snap2.units["BG"].flags["moved"] = true
	var ind_c2 := _evaluate(snap2, dests2, OBJ, movable2, {"BG": {"action": "move", "objective_id": "obj"}})
	_assert(not ind_c2.is_empty() and bool(ind_c2.stay) and str(ind_c2.spotter_id) == "C", "once its bodyguard has moved, C spots and B stays")

func test_guard_bs5_battery_moves() -> void:
	print("\n--- (c) guard: a BS 5+ battery gains nothing (6+ after the indirect cover either way, 02.02.01) ---")
	var snap = _board(LOBBA)
	var dests := _off_dests(snap)
	_fix(1.0)
	var ind := _evaluate(snap, dests)
	print("  ledger: %s" % str({"stay": ind.get("stay_terms"), "move": ind.get("move_terms")}))
	_assert(not ind.is_empty() and str(ind.target_id) == "T" and str(ind.move_target_id) == "T", "both options are priced on T")
	_assert(not ind.is_empty() and absf(float(ind.stay_terms.get("ind_stay_shot", 0.0)) - float(ind.move_terms.get("ind_move_shot", 0.0))) < 1e-6,
		"ind_stay_shot == ind_move_shot (the band buys nothing at BS 6+)")
	_assert(not ind.is_empty() and not bool(ind.stay), "it keeps the move")
	var d_on = _decide(snap)
	_fix(0.0)
	var d_off = _decide(snap)
	_assert(_shape(d_on) == _shape(d_off), "decide(): on == off")

func test_guard_visible_target_moves() -> void:
	print("\n--- (c) guard: B can see the target — a normal shot, nothing to arm ---")
	var snap = _board(MORTAR, false)
	_assert(bool(re.unit_sight_line("B", "T", snap, false).has_los), "precondition (engine): B sees T in the open")
	var dests := _off_dests(snap)
	_fix(1.0)
	_assert(_evaluate(snap, dests).is_empty(), "the stage stands down")
	var d_on = _decide(snap)
	_fix(0.0)
	var d_off = _decide(snap)
	_assert(_shape(d_on) == _shape(d_off) and str(d_on.get("type", "")) == "BEGIN_NORMAL_MOVE", "decide(): the flag-off Normal move")

func test_guard_objective_arrival() -> void:
	print("\n--- (c) guard: the move takes an objective this turn — ind_move_objective decides it ---")
	var snap = _board(MORTAR, true, [_obj(OBJ_NEAR)])
	var dests := _off_dests(snap)
	var mm = root.get_node_or_null("MissionManager")
	var in_range := false
	for m in _board_at(snap, "B", dests).units["B"].models:
		in_range = in_range or bool(mm.model_in_objective_range(m, gs.state.board.objectives[0]))
	_assert(in_range, "precondition (engine): the flag-off move ends with a model in the objective's range")
	_fix(1.0)
	var ind := _evaluate(snap, dests, OBJ_NEAR)
	print("  ledger: %s" % str({"stay": ind.get("stay_terms"), "move": ind.get("move_terms"), "margin": ind.get("margin")}))
	_assert(not ind.is_empty() and absf(float(ind.move_terms.get("ind_move_objective", 0.0)) - 25.0) < 1e-6, "ind_move_objective = 25")
	_assert(not ind.is_empty() and not bool(ind.stay), "it takes the objective (moves)")
	var d_on = _decide(snap)
	_assert(str(d_on.get("type", "")) == "BEGIN_NORMAL_MOVE", "decide(): the Normal move")
	_knob("INDIRECT_STATIONARY_OBJECTIVE_PTS", 0.0)
	var ind0 := _evaluate(snap, dests, OBJ_NEAR)
	_assert(not ind0.is_empty() and bool(ind0.stay), "INDIRECT_STATIONARY_OBJECTIVE_PTS 0: it stays — the term decided it")
	AIDM._config_overrides.erase("INDIRECT_STATIONARY_OBJECTIVE_PTS")

func test_guard_cannot_arm() -> void:
	print("\n--- (c) guard: it cannot arm — disembarked this phase (not Remaining Stationary, 09.04) / cannot shoot ---")
	var snap = _board()
	var dests := _off_dests(snap)
	_fix(1.0)
	_assert(not _evaluate(snap, dests).is_empty(), "precondition: the base case evaluates")
	snap.units["B"]["disembarked_this_phase"] = true
	_assert(_evaluate(snap, dests).is_empty(), "disembarked this phase: {}")
	snap.units["B"]["disembarked_this_phase"] = false
	snap.units["B"].flags["cannot_shoot"] = true
	_assert(_evaluate(snap, dests).is_empty(), "cannot shoot: {}")

func test_guard_minority_indirect_moves() -> void:
	print("\n--- (c) guard: [INDIRECT FIRE] is a minority of its ranged output — not a battery ---")
	var snap = _board()
	snap.units["B"].meta.weapons = [MORTAR, SPEAR_R, SPEAR_M]
	var share: float = AIDM._indirect_battery_share(snap.units["B"], snap)
	_assert(share > 0.0 and share < 0.5, "precondition: the mortar is %.0f%% of its nominal ranged output" % (share * 100.0))
	var dests := _off_dests(snap)
	_fix(1.0)
	_assert(_evaluate(snap, dests).is_empty(), "the stage stands down (INDIRECT_STATIONARY_MIN_SHARE)")
	var only := _board()
	_assert(absf(float(AIDM._indirect_battery_share(only.units["B"], only)) - 1.0) < 1e-6, "a mortar-only unit is a full battery (share 1.0)")

func test_guard_charge_and_advance_unchanged() -> void:
	print("\n--- (c) guard: a planned charge / an Advance plan never reach the stage ---")
	var snap = _board()
	_fix(1.0)
	var d_on = _decide(snap, "T")
	_fix(0.0)
	var d_off = _decide(snap, "T")
	_assert(_shape(d_on) == _shape(d_off), "planned charge: on == off")
	# An Advance plan (injected as the stored battle plan): the advance branch returns first.
	var shapes: Array = []
	for v in [1.0, 0.0]:
		_fix(v)
		_reset()
		var board: Dictionary = snap.duplicate(true)
		AIDM._phase_plan_round = 2
		AIDM._turn_movement_plan[1] = {"round": 2, "consumed": {}, "replans": 0, "announce": {},
			"assignments": {"B": {"objective_id": "obj", "objective_pos": OBJ, "action": "advance",
				"reason": "test advance", "score": 5.0, "distance": 700.0}}}
		var d = AIDM.decide(7, board, _actions(), 1)
		shapes.append(_shape(d))
		_assert(str(d.get("type", "")) == "BEGIN_ADVANCE", "advance plan (flag %.0f): BEGIN_ADVANCE (got %s)" % [v, str(d.get("type", ""))])
	_assert(shapes.size() == 2 and shapes[0] == shapes[1], "advance plan: on == off")

func test_guard_f002_hold_fire_predicted() -> void:
	print("\n--- (c) guard: F002 would hold fire at its spot to stay Hidden — no claim ---")
	var snap = _board()
	# B Hidden in a dense area of its own; T gets a gun, so Hidden protects B
	# from a shooter (B is outside T's 15" detection range).
	var pieces: Array = [_hide(), _dense_area("b_ruin", 260.0, 560.0, 600.0, 640.0)]
	tm.terrain_features = pieces.duplicate(true)
	snap.board["terrain_features"] = pieces.duplicate(true)
	re.clear_los_memo()
	snap.units["T"].meta.weapons = [SPEAR_R, SPEAR_M]
	var b: Dictionary = snap.units["B"]
	_assert(bool(tm.is_model_hidden(b.models[0], b)), "precondition (engine): B is Hidden where it stands")
	var dests := _off_dests(snap)
	_fix(1.0)
	_knob("HIDDEN_FORFEIT_PENALTY", 0.0)
	var ind0 := _evaluate(snap, dests)
	_assert(not ind0.is_empty() and bool(ind0.stay), "F002 off (penalty 0): it stays")
	_knob("HIDDEN_FORFEIT_PENALTY", 5.0)
	_assert(_evaluate(snap, dests).is_empty(), "F002 at 5.0 would hold its fire to stay Hidden: nothing to arm")
	AIDM._config_overrides.erase("HIDDEN_FORFEIT_PENALTY")

# --- (d) the ledger -----------------------------------------------------------

func test_ledger_sums_and_ratio() -> void:
	print("\n--- (d) the ledgers sum to their scores; BS 3+ unseen on both boards prices 3x ---")
	var snap = _board()
	var dests := _off_dests(snap)
	_fix(1.0)
	var ind := _evaluate(snap, dests)
	print("  ledger: %s" % str({"stay": ind.get("stay_terms"), "move": ind.get("move_terms"), "margin": ind.get("margin"), "ev": [ind.get("ev_stay"), ind.get("ev_move")]}))
	_assert(not ind.is_empty(), "the base case evaluates")
	if ind.is_empty():
		return
	_assert(absf(_sum(ind.stay_terms) - float(ind.stay_score)) < 1e-6, "Σ stay_terms == stay_score")
	_assert(absf(_sum(ind.move_terms) - float(ind.move_score)) < 1e-6, "Σ move_terms == move_score")
	var s := float(ind.stay_terms.get("ind_stay_shot", 0.0))
	var m := float(ind.move_terms.get("ind_move_shot", 0.0))
	_assert(m > 0.0 and absf(s / m - 3.0) < 0.01, "ind_stay_shot / ind_move_shot = 3.0 (1/2 vs 1/6 to hit; got %.3f)" % (s / m if m > 0.0 else -1.0))
	# 15 attacks (A2 + [BLAST] 1 vs 5 models, x5) x 1/2 x 2/3 (S8 v T6) x 1/2 (4+ after AP-2) x D2 = 5.0 wounds.
	_assert(absf(float(ind.ev_stay) - 5.0) < 0.01, "engine preview: 5.0 expected wounds if it stays (got %.3f)" % float(ind.ev_stay))
	_assert(absf(s - 50.0) < 0.01, "ind_stay_shot = 5.0 wounds x 10 pts per wound (got %.2f)" % s)
	var gap_now: float = AIDM._unit_gap_to_objective_px(snap.units["B"], OBJ)
	var gap_aft: float = AIDM._unit_gap_to_objective_px(_board_at(snap, "B", dests).units["B"], OBJ)
	var prog := maxf(0.0, gap_now - gap_aft) / PX
	_assert(absf(float(ind.progress_in) - prog) < 0.01 and prog > 1.0, "progress_in = the gap the move closes (%.2f\" vs %.2f\")" % [float(ind.progress_in), prog])
	_assert(absf(float(ind.move_terms.get("ind_move_progress", 0.0)) - prog) < 0.01, "ind_move_progress = 1 pt per inch")
	_assert(bool(ind.stay) and float(ind.margin) >= 5.0, "stay - move %.1f >= the 5-point margin" % float(ind.margin))

func test_heavy_indirect_priced() -> void:
	print("\n--- (d) [HEAVY] is priced as the engine applies it (24.16: +1 to hit when it Remained Stationary) ---")
	var snap = _board(HEAVY_MORTAR)
	var dests := _off_dests(snap)
	_fix(1.0)
	var ind := _evaluate(snap, dests)
	var snap4 = _board(PLAIN_MORTAR4)
	var dests4 := _off_dests(snap4)
	_fix(1.0)
	var ind4 := _evaluate(snap4, dests4)
	var r_heavy := -1.0
	var r_plain := -1.0
	if not ind.is_empty() and float(ind.move_terms.get("ind_move_shot", 0.0)) > 0.0:
		r_heavy = float(ind.stay_terms.get("ind_stay_shot", 0.0)) / float(ind.move_terms.get("ind_move_shot", 0.0))
	if not ind4.is_empty() and float(ind4.move_terms.get("ind_move_shot", 0.0)) > 0.0:
		r_plain = float(ind4.stay_terms.get("ind_stay_shot", 0.0)) / float(ind4.move_terms.get("ind_move_shot", 0.0))
	print("  BS 4+ ratio: heavy %.3f, plain %.3f" % [r_heavy, r_plain])
	_assert(absf(r_plain - 2.0) < 0.01, "BS 4+ indirect: stationary doubles the hits (1/3 vs 1/6)")
	_assert(absf(r_heavy - 3.0) < 0.01, "BS 4+ [HEAVY, INDIRECT FIRE]: the stay board gets [HEAVY]'s +1 too (1/2 vs 1/6)")

# --- (e) the OC ledger --------------------------------------------------------

func test_finalize_intent_not_credited() -> void:
	print("\n--- (e) _finalize_movement_decision: a battery that stays is not booked as incoming OC on the plan's objective ---")
	var snap = _board()
	_reset()
	var asg := {"action": "move", "objective_id": "obj_x", "objective_pos": OBJ}
	AIDM._finalize_movement_decision({"type": "REMAIN_STATIONARY", "actor_unit_id": "B", "_ai_indirect_hold": true,
		"_ai_assignment": asg, "_ai_description": "B remains stationary to arm its indirect fire at T"}, snap, 1)
	var with_key: String = str(AIDM._get_movement_intents(1).get("B", {}).get("objective_id", "?"))
	_reset()
	AIDM._finalize_movement_decision({"type": "REMAIN_STATIONARY", "actor_unit_id": "B",
		"_ai_assignment": asg, "_ai_description": "B holds obj_x"}, snap, 1)
	var without: String = str(AIDM._get_movement_intents(1).get("B", {}).get("objective_id", "?"))
	_assert(with_key == "", "with _ai_indirect_hold: no objective claimed (got '%s')" % with_key)
	_assert(without == "obj_x", "without it: the old assignment credit (got '%s')" % without)

# --- (f) composition ----------------------------------------------------------

func test_composes_with_batch1_flags() -> void:
	print("\n--- (f) with FIX_MOVE_COVER / FIX_MOVE_FOR_SHOT / FIX_MOVE_FOR_CHARGE on: the hold wins when it pays, and defers when it does not ---")
	var snap = _board()
	for k in ["FIX_MOVE_COVER", "FIX_MOVE_FOR_SHOT", "FIX_MOVE_FOR_CHARGE"]:
		_knob(k, 1.0)
	_fix(1.0)
	var d_all = _decide(snap)
	_assert(str(d_all.get("type", "")) == "REMAIN_STATIONARY" and bool(d_all.get("_ai_indirect_hold", false)),
		"all four on: B still Remains Stationary (got %s)" % str(d_all.get("type", "")))
	var lob = _board(LOBBA)
	_fix(1.0)
	var d_lob_on = _decide(lob)
	_fix(0.0)
	var d_lob_off = _decide(lob)
	_assert(_shape(d_lob_on) == _shape(d_lob_off), "BS 5+ with the batch-1 flags on: this flag changes nothing (their move stands)")
	for k in ["FIX_MOVE_COVER", "FIX_MOVE_FOR_SHOT", "FIX_MOVE_FOR_CHARGE"]:
		AIDM._config_overrides.erase(k)
