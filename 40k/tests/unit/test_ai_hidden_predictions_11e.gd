extends SceneTree

# The AI's 13.09 Hidden predictions ask the engine's own questions
# (11e 13.09 / 13.11.01 / 15.08 / 15.09 / 06.01 / 19.01).
#
# 13.09 HIDDEN, second bullet: "That model's unit did not make one or more
# ranged attacks during this turn or during the previous turn." FIRE OVERWATCH
# (15.08: "Your unit shoots using snap shooting"; 15.09: "Your unit shoots as
# described in Making Attacks (04)") and the other out-of-phase "your unit
# shoots" paths now stamp the shot record (scripts/rules/HiddenShotRecord.gd)
# in the OPPONENT's turn. So "Hidden now" and "Hidden in the enemy's next turn
# if it holds fire" are no longer the same question: a unit that overwatched
# in the enemy's last turn (stamp T-1) is not Hidden in its own turn T, but is
# Hidden in the enemy's turn T+1 if it holds fire at T. The AI's predictions
# (F001 _position_would_be_hidden, F002 _hidden_forfeit_cost, F003
# _target_regains_hidden_soon, FIX_MOVE_COVER's _mc_eval) are about that next
# turn; they used to read the live one.
#
# 06.01 UNIT VISIBLE ("If one or more models in a unit are visible ... that
# unit is visible") and 19.01 ("An attached unit is a single unit for all
# rules purposes"): the engine's target side walks every model of every
# component of an Attached unit, both link directions
# (RulesEngine._target_model_entries), so Hidden protects the unit only while
# EVERY model of it is Hidden.
#
# Cases:
#   A. engine helpers — TerrainManager.is_model_hidden_at / can_go_to_ground_at
#      / detection_range_bounds_inches_at / detection_range_inches_for_at give
#      the live predicates' answer at the live index and the 13.09 / 13.11.01
#      answer for any other turn.
#   B. AI1 — a REAL FIRE OVERWATCH (MovementPhase END_MOVEMENT ->
#      movement_phase_end window -> USE_WINDOW_STRATAGEM fire_overwatch_11e,
#      fixture ork11e_orks_reactive) stamps Custodian Guard B in Player 2's
#      turn (index 5). In Player 1's next turn (index 6) the unit is not Hidden
#      now and is Hidden at index 7 if it holds fire: F002 prices the forfeit
#      (> 0) and the shooting phase holds fire, F001 credits the Hidden spot,
#      FIX_MOVE_COVER still picks kind=hidden (exam mv05's geometry, also with
#      Gone to Ground behind a dense wall); once the unit has shot THIS turn,
#      F002 prices 0 and F001 credits nothing. F003 asks "Hidden in its next
#      turn": an enemy that fired in its own last turn (not Hidden now) and one
#      that never fired are; one that fired THIS turn is not.
#   D. AI3 — F002 holds fire only while every model of the Attached unit is
#      Hidden: a leader standing outside the terrain (forward link, or linked
#      only by its own attached_to back-pointer), or one bodyguard model
#      outside, makes the unit targetable (the engine agrees) and the forfeit
#      0; the control with every model inside still prices it.
#   E. AI5 — FIX_MOVE_COVER's members walk both link directions: a leader
#      linked only by attached_to (MovementPhase moves only the forward list,
#      so he stays where he stands) keeps the pick from claiming Hidden while
#      he stands in the open, and the engine agrees he makes the unit a
#      target; control: standing hidden himself, the claim stands.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_hidden_predictions_11e.gd

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const HSR := preload("res://scripts/rules/HiddenShotRecord.gd")
const GameStateData = preload("res://autoloads/GameState.gd")
const FIXTURE := "res://tests/saves/ork11e_orks_reactive.w40ksave"
const PX := 40.0
const PHASE_MOVEMENT := 7
const PHASE_SHOOTING := 8
# Exam mv05's geometry (tests/unit/test_ai_fix_move_cover.gd): the objective's
# dense ruin x 460-740, y 970-1430; the squad on a 65 px line 2.2" north of it
# (the 5th base past the east edge); the shooter south of it in the open.
const OBJ := Vector2(600, 1200)
const HALF := Vector2(140, 230)
const SQUAD_Y := 850.0
const SQUAD_X0 := 530.0
const STEP := 65.0
const KNOBS := ["FIX_MOVE_COVER", "HIDDEN_FORFEIT_PENALTY", "WEIGHT_HIDDEN_GAINED", "HIDDEN_WINDOW_BONUS"]

var passed := 0
var failed := 0
var _completed := false  # set by the last line of _run(): an aborted run (script error) counts as a failure
var AIDM = null
var GS = null
var TM = null
var PM = null
var SM = null
var RE = null
var MM = null
var AIP = null

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _initialize() -> void:
	await create_timer(0.3).timeout
	await _run()
	if not _completed:
		failed += 1
		print("  FAIL: the run aborted before its last check (see the SCRIPT ERROR above)")
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 or passed == 0 else 0)

# --- fixtures -----------------------------------------------------------------

func _rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])

func _rect_in(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return _rect(x0 * PX, y0 * PX, x1 * PX, y1 * PX)

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

func _light_area(x0: float, y0: float, x1: float, y1: float) -> Dictionary:
	return {"id": "light_area", "piece_class": "area", "type": "woods", "category": "light", "height_category": "low",
		"polygon": _rect_in(x0, y0, x1, y1), "can_move_through": {"INFANTRY": true, "VEHICLE": true, "MONSTER": true}}

func _obj_area() -> Dictionary:
	return {"id": "obj_area", "position": OBJ, "zone": "no_mans_land", "source_pieces": ["area_obj"]}

func _set_terrain(pieces: Array) -> void:
	TM.terrain_features = pieces.duplicate(true)
	GS.state.board["terrain_features"] = pieces.duplicate(true)
	RE.clear_los_memo()

func _set_turn(rnd: int, active: int) -> void:
	GS.state.meta["first_turn_player"] = 1
	GS.state.meta["battle_round"] = rnd
	GS.state.meta["active_player"] = active

func _load_fixture(keep: Array) -> bool:
	var slm = root.get_node("SaveLoadManager")
	var ok: bool = slm.load_game_from_file_path(FIXTURE)
	GameConstants.edition = 11
	var units: Dictionary = {}
	for uid in keep:
		if GS.state.units.has(uid):
			units[uid] = GS.state.units[uid]
	GS.state.units = units
	GS.state.board["objectives"] = []
	_set_turn(2, 1)
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 6
	_set_terrain([])
	SM._usage_history = {"1": [], "2": []}
	MM.objective_control_state = {}
	MM.objective_contested_state = {}
	AIP.enabled = false
	AIP.ai_players = {1: false, 2: false}
	root.get_node("SettingsService").auto_allocate_wounds = true
	for uid in units:
		units[uid]["flags"] = {}
	return ok

func _place_px(uid: String, x0: float, y: float, step: float) -> void:
	var i := 0
	for m in GS.state.units[uid].models:
		if m.get("alive", true):
			m["position"] = {"x": x0 + float(i) * step, "y": y}
			i += 1

func _place(uid: String, x_in: float, y_in: float, step: float = 1.8) -> void:
	_place_px(uid, x_in * PX, y_in * PX, step * PX)

func _knob(k: String, v: float) -> void:
	AIDM._config_overrides[k] = v

func _clear_knobs() -> void:
	for k in KNOBS:
		AIDM._config_overrides.erase(k)

func _reset_ai() -> void:
	AIDM.reset_caches()
	AIDM.clear_all_plans()
	AIDM.set_ai_seed(7)

func _vec(p) -> Vector2:
	if p is Vector2:
		return p
	if p is Dictionary:
		return Vector2(float(p.get("x", 0)), float(p.get("y", 0)))
	return Vector2.INF

## Engine truth for turn `idx` (Player 1 first: battle round R's turns are 2R
## and 2R + 1): the LIVE predicate with the turn counter set to idx — the
## oracle does not depend on the turn-indexed helpers under test.
func _n_hidden_at(u: Dictionary, idx: int) -> Array:
	var keep_r = GS.state.meta.get("battle_round", 1)
	var keep_a = GS.state.meta.get("active_player", 1)
	_set_turn(idx / 2, 1 if idx % 2 == 0 else 2)
	var out := _n_hidden_live(u)
	_set_turn(int(keep_r), int(keep_a))
	return out

func _n_hidden_live(u: Dictionary) -> Array:
	var n := 0
	var t := 0
	for m in u.get("models", []):
		if not m.get("alive", true) or m.get("position", null) == null:
			continue
		t += 1
		if TM.is_model_hidden(m, u):
			n += 1
	return [n, t]

## Movement phase for the active player, every start-of-phase window declined.
func _movement() -> Node:
	PM.transition_to_phase(PHASE_MOVEMENT)
	var phase = PM.get_current_phase_instance()
	var guard := 0
	while phase != null and phase.has_pending_stratagem_window() and guard < 6:
		var w = phase.get_pending_stratagem_window()
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.player), "window_id": str(w.window_id)})
		guard += 1
	return phase

## The REAL FIRE OVERWATCH at the end of the active player's Movement phase:
## `shooter_id` (the other player's unit) snap-shoots `target_id`.
func _real_overwatch(active: int, shooter_id: String, target_id: String) -> Dictionary:
	var phase = _movement()
	phase.execute_action({"type": "END_MOVEMENT", "player": active})
	var guard := 0
	while phase.has_pending_stratagem_window() and int(phase.get_pending_stratagem_window().player) == active and guard < 4:
		var w2 = phase.get_pending_stratagem_window()
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": active, "window_id": str(w2.window_id)})
		guard += 1
	return phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 3 - active, "window_id": "movement_phase_end",
		"stratagem_id": "fire_overwatch_11e", "target_unit_id": shooter_id, "context": {"secondary_id": target_id}})

## _pick_cover_spot, called the way the normal-move chain calls it.
func _pick(snap: Dictionary, uid: String, diag: Dictionary = {}) -> Dictionary:
	_reset_ai()
	var unit: Dictionary = snap.units[uid]
	var centroid: Vector2 = AIDM._get_unit_centroid(unit)
	var enemies: Dictionary = AIDM._get_enemy_units(snap, int(unit.get("owner", 1)))
	var move_target: Vector2 = AIDM._objective_approach_target(unit, OBJ)
	return AIDM._pick_cover_spot(unit, uid, snap, centroid, move_target, OBJ, 6.0, enemies,
		AIDM._calculate_enemy_threat_data(enemies), AIDM._get_objectives(snap), AIDM._get_max_weapon_range(unit),
		AIDM._unit_has_ranged_weapons(unit), diag)

func _unit_at_end(unit: Dictionary, delta: Vector2) -> Dictionary:
	var u: Dictionary = unit.duplicate(true)
	for m in u.models:
		if m.get("alive", true) and m.get("position", null) != null:
			m["position"] = _vec(m.position) + delta
	return u

## The squad of mv05 on the fixture: Custodian Guard B on the 65 px line north
## of the ruin, the Meganobz (T6 Sv2, the synthetic SHOOTER's profile) south of
## it in the open on the same line as the synthetic test's shooter.
func _mv05_board(with_wall: bool) -> void:
	var pieces: Array = [_ruin()]
	if with_wall:
		pieces.append(_wall())
	_set_terrain(pieces)
	GS.state.board["objectives"] = [_obj_area()]
	_place_px("U_CUSTODIAN_GUARD_B", SQUAD_X0, SQUAD_Y, STEP)
	_place_px("U_MEGANOBZ_A", 540.0, 2010.0, STEP)

# --- A ------------------------------------------------------------------------

func _section_engine_helpers() -> void:
	print("\n-- A. engine: the 13.09 / 13.11.01 predicates for a given turn --")
	var have: bool = TM.has_method("is_model_hidden_at") and TM.has_method("can_go_to_ground_at") \
			and TM.has_method("detection_range_bounds_inches_at") and TM.has_method("detection_range_inches_for_at")
	_check("TerrainManager has is_model_hidden_at / can_go_to_ground_at / detection_range_bounds_inches_at / detection_range_inches_for_at", have)
	if not have:
		return
	if not _load_fixture(["U_CUSTODIAN_GUARD_B", "U_MEGANOBZ_A"]):
		_check("fixture loaded", false)
		return
	_set_terrain([_ruin(), _wall()])
	_place_px("U_CUSTODIAN_GUARD_B", 500.0, 1100.0, 50.0)
	var u: Dictionary = GS.state.units["U_CUSTODIAN_GUARD_B"]
	var m: Dictionary = u.models[0]
	_set_turn(2, 2)  # index 5: the unit shoots (e.g. FIRE OVERWATCH) in the opponent's turn
	PM.apply_state_changes(HSR.stamp_diffs("U_CUSTODIAN_GUARD_B"))
	_set_turn(3, 1)  # index 6: its own turn
	var idx: int = int(GS.get_player_turn_index())
	_check("index 6 is Player 1's battle-round-3 turn", idx == 6, "idx=%d" % idx)
	_check("live index: is_model_hidden_at == is_model_hidden (both not Hidden: shot in the previous turn)",
		TM.is_model_hidden_at(m, u, idx) == TM.is_model_hidden(m, u) and not TM.is_model_hidden(m, u))
	_check("index 7 (the enemy's next turn): Hidden if it holds fire now", TM.is_model_hidden_at(m, u, idx + 1))
	_check("index 5 (the turn it shot): not Hidden", not TM.is_model_hidden_at(m, u, idx - 1))
	_check("can_go_to_ground_at: not at 6 (live agrees), yes at 7",
		not TM.can_go_to_ground_at(u, idx) and TM.can_go_to_ground(u) == TM.can_go_to_ground_at(u, idx)
		and TM.can_go_to_ground_at(u, idx + 1))
	var b_now: Dictionary = TM.detection_range_bounds_inches(u)
	var b_at6: Dictionary = TM.detection_range_bounds_inches_at(u, idx)
	var b_at7: Dictionary = TM.detection_range_bounds_inches_at(u, idx + 1)
	_check("detection_range_bounds_inches_at(6) == live bounds (lo == hi, no Gone to Ground)",
		float(b_at6.lo) == float(b_now.lo) and float(b_at6.hi) == float(b_now.hi) and float(b_now.lo) == float(b_now.hi),
		"now=%s at6=%s" % [str(b_now), str(b_at6)])
	_check("detection_range_bounds_inches_at(7): Gone to Ground's -3\" available (lo %.0f = hi %.0f - 3)" % [float(b_at7.lo), float(b_at7.hi)],
		float(b_at7.lo) == float(b_at7.hi) - 3.0 and bool(b_at7.can_go_to_ground))
	# An observer south of the wall, 13" away: Gone to Ground (12") hides the
	# model from it only when the unit can go to ground.
	var obs := {"id": "o1", "alive": true, "base_mm": 32, "base_type": "circular", "position": Vector2(500.0, 1100.0 + 14.0 * PX)}
	var d6: float = TM.detection_range_inches_for_at(m, u, obs, idx)
	var d7: float = TM.detection_range_inches_for_at(m, u, obs, idx + 1)
	_check("detection_range_inches_for_at: 15\" now (live agrees), 12\" at 7 behind the dense wall (got %.0f / %.0f)" % [d6, d7],
		d6 == TM.detection_range_inches_for(m, u, obs) and d6 == 15.0 and d7 == 12.0)
	u.flags["shot_recently"] = true
	_check("the legacy shot_recently flag counts at every turn", not TM.is_model_hidden_at(m, u, idx + 1) and not TM.is_model_hidden_at(m, u, idx + 5))
	u.flags.erase("shot_recently")
	_check("NO_TURN (no turn counter): only the legacy flag counts", TM.is_model_hidden_at(m, u, HSR.NO_TURN))

# --- B ------------------------------------------------------------------------

func _section_prev_turn_overwatch() -> void:
	print("\n-- B. AI1: a FIRE OVERWATCH stamp from the enemy's turn; the AI predicts the enemy's NEXT turn --")
	if not _load_fixture(["U_CUSTODIAN_GUARD_B", "U_MEGANOBZ_A"]):
		_check("fixture loaded", false)
		return
	# Player 2's battle-round-2 turn (index 5): Custodian Guard B overwatches the
	# Meganobz 12" away at the end of Player 2's Movement phase.
	_set_turn(2, 2)
	_place("U_CUSTODIAN_GUARD_B", 8.0, 20.0)
	_place("U_MEGANOBZ_A", 8.0, 32.0)
	var stamp_idx: int = int(GS.get_player_turn_index())
	var res: Dictionary = _real_overwatch(2, "U_CUSTODIAN_GUARD_B", "U_MEGANOBZ_A")
	_check("FIRE OVERWATCH resolved through the real window (snap shooting)",
		res.get("success", false) and res.get("fire_overwatch_used", false), str(res.get("error", "")))
	var flags: Dictionary = GS.state.units["U_CUSTODIAN_GUARD_B"].get("flags", {})
	_check("the overwatch stamped the opponent's turn (last_shot_idx %d)" % stamp_idx,
		int(flags.get("last_shot_idx", -1)) == stamp_idx and int(flags.get("last_ranged_attack_idx", -1)) == stamp_idx, str(flags))
	# Player 1's next turn: battle round 3 (index 6); the Meganobz stand in the
	# open south of the ruin (exam mv05's shooter line).
	_set_turn(3, 1)
	GS.state.meta["phase"] = PHASE_MOVEMENT
	var cur: int = int(GS.get_player_turn_index())
	_check("Player 1's own next turn is index %d" % (stamp_idx + 1), cur == stamp_idx + 1, "idx=%d" % cur)
	_knob("FIX_MOVE_COVER", 1.0)
	_knob("HIDDEN_FORFEIT_PENALTY", 3.0)

	# B1. F002 / F001 with the unit standing at the Hidden spot inside the ruin.
	_mv05_board(false)
	_place_px("U_CUSTODIAN_GUARD_B", 490.0, 1060.0, 50.0)
	var cg: Dictionary = GS.state.units["U_CUSTODIAN_GUARD_B"]
	var h_now := _n_hidden_live(cg)
	var h_next := _n_hidden_at(cg, cur + 1)
	_check("engine: in the ruin it is NOT Hidden now (%d/%d) but Hidden at index %d if it holds fire (%d/%d)" % [
		h_now[0], h_now[1], cur + 1, h_next[0], h_next[1]], h_now[0] == 0 and h_next[0] == h_next[1] and h_next[1] == 5)
	var snap: Dictionary = GS.create_snapshot()
	var enemies: Dictionary = AIDM._get_shootable_enemy_units(snap, 1)
	var cost: float = AIDM._hidden_forfeit_cost(snap.units["U_CUSTODIAN_GUARD_B"], enemies, snap)
	_check("F002: holding fire keeps Hidden next turn, so the forfeit is priced (%.2f > 0)" % cost, cost > 0.0)
	_check("F001: the spot in the ruin would be Hidden (next turn)",
		AIDM._position_would_be_hidden(snap.units["U_CUSTODIAN_GUARD_B"], Vector2(600.0, 1060.0)))
	_reset_ai()
	var d: Dictionary = AIDM.decide(PHASE_SHOOTING, GS.create_snapshot(),
		[{"type": "SELECT_SHOOTER", "actor_unit_id": "U_CUSTODIAN_GUARD_B"}], 1)
	_check("shooting phase: the chip shot at the Meganobz is declined to keep Hidden (got %s: %s)" % [
		str(d.get("type", "")), str(d.get("_ai_description", ""))], str(d.get("type", "")) == "SKIP_UNIT"
		and str(d.get("_ai_description", "")).contains("holds fire to be Hidden next turn"))
	# Control: the same unit once it has shot THIS turn (the engine's own stamp).
	var snap_shot: Dictionary = GS.create_snapshot()
	var f2: Dictionary = snap_shot.units["U_CUSTODIAN_GUARD_B"].flags
	f2["prev_shot_idx"] = int(f2.get("last_shot_idx", HSR.NEVER))
	f2["last_shot_idx"] = cur
	f2["last_ranged_attack_idx"] = cur
	var cost_shot: float = AIDM._hidden_forfeit_cost(snap_shot.units["U_CUSTODIAN_GUARD_B"], enemies, snap_shot)
	_check("control: after shooting THIS turn nothing is left to sell (forfeit %.2f == 0)" % cost_shot, cost_shot == 0.0)
	_check("control: ... and F001 credits no Hidden spot",
		not AIDM._position_would_be_hidden(snap_shot.units["U_CUSTODIAN_GUARD_B"], Vector2(600.0, 1060.0)))

	# B2. FIX_MOVE_COVER on exam mv05's approach.
	_mv05_board(false)
	snap = GS.create_snapshot()
	var diag := {}
	var pick: Dictionary = _pick(snap, "U_CUSTODIAN_GUARD_B", diag)
	print("  pick: kind=%s n_blind=%s/%s gain=%s diag=%s" % [str(pick.get("kind", "")), str(pick.get("n_blind", "")),
		str(pick.get("n_threats", "")), str(pick.get("gain", "")), str(diag)])
	_check("FIX_MOVE_COVER: the spot is still kind=hidden for the unit that overwatched last turn (got %s)" % str(pick.get("kind", "none")),
		str(pick.get("kind", "")) == "hidden" and int(pick.get("n_blind", 0)) >= 1)
	if not pick.is_empty():
		var centroid: Vector2 = AIDM._get_unit_centroid(snap.units["U_CUSTODIAN_GUARD_B"])
		var at_end := _unit_at_end(snap.units["U_CUSTODIAN_GUARD_B"], Vector2(pick.end) - centroid)
		var he := _n_hidden_at(at_end, cur + 1)
		_check("engine: every model at that spot is Hidden in the enemy's next turn (%d/%d)" % [he[0], he[1]], he[0] == he[1] and he[1] == 5)

	# B3. Gone to Ground (13.11.01) behind the dense wall, judged for the next
	# turn: the Meganobz directly south, every pair 13.5-14.5" apart after their
	# 5" move (between 12" and 15": only the dense wall's -3" blinds them).
	_mv05_board(true)
	_place_px("U_MEGANOBZ_A", 475.0, 1821.5, STEP)
	snap = GS.create_snapshot()
	var diag2 := {}
	var pick2: Dictionary = _pick(snap, "U_CUSTODIAN_GUARD_B", diag2)
	print("  pick (wall): kind=%s n_blind=%s n_gtg=%s diag=%s" % [str(pick2.get("kind", "")), str(pick2.get("n_blind", "")),
		str(pick2.get("n_gtg", "")), str(diag2)])
	_check("FIX_MOVE_COVER: Gone to Ground behind the dense wall counts for the next turn (kind=%s, gtg=%s)" % [
		str(pick2.get("kind", "none")), str(pick2.get("n_gtg", 0))],
		str(pick2.get("kind", "")) == "hidden" and int(pick2.get("n_gtg", 0)) >= 1)

	# B4. F003, from Player 1's seat at index 6: enemies standing in the ruin.
	_knob("HIDDEN_WINDOW_BONUS", 1.25)
	_mv05_board(false)
	_place_px("U_MEGANOBZ_A", 490.0, 1300.0, 60.0)
	var mg: Dictionary = GS.state.units["U_MEGANOBZ_A"]
	mg["flags"] = {}
	snap = GS.create_snapshot()
	var mg_hidden_now := _n_hidden_live(snap.units["U_MEGANOBZ_A"])
	_check("F003 setup: the Meganobz in the ruin are Hidden now (%d/%d)" % [mg_hidden_now[0], mg_hidden_now[1]],
		mg_hidden_now[0] == mg_hidden_now[1] and mg_hidden_now[1] > 0)
	_check("F003: an enemy Hidden now that has not fired is still Hidden in its next turn",
		AIDM._target_regains_hidden_soon(snap.units["U_MEGANOBZ_A"], snap))
	_set_turn(2, 2)
	PM.apply_state_changes(HSR.stamp_diffs("U_MEGANOBZ_A"))  # fired in its own turn (index 5)
	_set_turn(3, 1)
	snap = GS.create_snapshot()
	_check("F003: an enemy that fired in its own last turn (stamp %d) regains Hidden in its next turn" % stamp_idx,
		AIDM._target_regains_hidden_soon(snap.units["U_MEGANOBZ_A"], snap))
	var snap_ow: Dictionary = GS.create_snapshot()
	snap_ow.units["U_MEGANOBZ_A"].flags["last_shot_idx"] = cur
	_check("F003: one that fired THIS turn (e.g. overwatched our move) is not Hidden in its next turn",
		not AIDM._target_regains_hidden_soon(snap_ow.units["U_MEGANOBZ_A"], snap_ow))
	_clear_knobs()

# --- D ------------------------------------------------------------------------

func _attached_board(leader_inside: bool, boy_outside: bool, back_pointer_only: bool) -> void:
	_load_fixture(["U_CUSTODIAN_GUARD_A", "U_CUSTODIAN_GUARD_B", "U_BOYZ_B", "U_WARBOSS_A"])
	_set_turn(2, 2)  # Player 2's own turn (index 5): F002 is asked in its Shooting phase
	_set_terrain([_light_area(4.0, 24.0, 25.0, 28.0)])
	_place("U_BOYZ_B", 6.0, 26.0, 1.4)
	_place("U_WARBOSS_A", 22.0, 26.0 if leader_inside else 31.0)
	if boy_outside:
		GS.state.units["U_BOYZ_B"].models[0]["position"] = {"x": 6.0 * PX, "y": 31.0 * PX}
	# Both Custodian Guard units beyond 15" of every Boyz / Warboss model; B
	# inside the Boyz' 24" rokkits.
	_place("U_CUSTODIAN_GUARD_A", 40.0, 52.0)
	_place("U_CUSTODIAN_GUARD_B", 8.0, 50.0)
	if back_pointer_only:
		GS.state.units["U_BOYZ_B"]["attachment_data"] = {"attached_characters": []}
		GS.state.units["U_WARBOSS_A"]["attached_to"] = "U_BOYZ_B"
	_knob("HIDDEN_FORFEIT_PENALTY", 3.0)

func _f002_case(label: String, leader_inside: bool, boy_outside: bool, back_pointer_only: bool, expect_cost: bool) -> void:
	_attached_board(leader_inside, boy_outside, back_pointer_only)
	var snap: Dictionary = GS.create_snapshot()
	var enemies: Dictionary = AIDM._get_shootable_enemy_units(snap, 2)
	var cost: float = AIDM._hidden_forfeit_cost(snap.units["U_BOYZ_B"], enemies, snap)
	# The engine, in Player 1's next turn (index 6), after Player 2 held fire.
	_set_turn(3, 1)
	var targetable := false
	for p1 in ["U_CUSTODIAN_GUARD_A", "U_CUSTODIAN_GUARD_B"]:
		if "U_BOYZ_B" in RE.get_eligible_targets(p1, GS.state).keys():
			targetable = true
	_set_turn(2, 2)
	if expect_cost:
		_check("%s: every model Hidden, untargetable next turn (engine), forfeit priced (%.2f > 0)" % [label, cost],
			cost > 0.0 and not targetable)
	else:
		_check("%s: the unit is a target next turn anyway (engine: %s), so holding fire buys nothing (forfeit %.2f == 0)" % [
			label, str(targetable), cost], targetable and cost == 0.0)
	_clear_knobs()

func _section_attached_f002() -> void:
	print("\n-- D. AI3: F002 needs EVERY model of the Attached unit Hidden (06.01, 19.01) --")
	_f002_case("control (Boyz + Warboss all in the area)", true, false, false, true)
	_f002_case("Warboss outside the area", false, false, false, false)
	_f002_case("one Boy outside the area", true, true, false, false)
	_f002_case("Warboss linked only by attached_to, outside the area", false, false, true, false)
	_f002_case("Warboss linked only by attached_to, inside the area", true, false, true, true)

# --- E ------------------------------------------------------------------------

func _section_back_pointer_leader() -> void:
	print("\n-- E. AI5: FIX_MOVE_COVER walks both link directions (a leader linked only by attached_to) --")
	for inside in [false, true]:
		if not _load_fixture(["U_CUSTODIAN_GUARD_B", "U_MEGANOBZ_A", "U_BLADE_CHAMPION_A"]):
			_check("fixture loaded", false)
			return
		_set_turn(3, 1)
		_mv05_board(false)
		# The Meganobz 28" south of the ruin spot: they reach it next turn (M5 +
		# 24") but stay beyond 15" of it after their move, and out of the
		# squad's 24" spears.
		_place_px("U_MEGANOBZ_A", 540.0, 2200.0, STEP)
		# The leader, linked only by his own back-pointer: MovementPhase moves
		# only the forward list at CONFIRM, so he stays where he stands.
		GS.state.units["U_CUSTODIAN_GUARD_B"]["attachment_data"] = {"attached_characters": []}
		GS.state.units["U_BLADE_CHAMPION_A"]["attached_to"] = "U_CUSTODIAN_GUARD_B"
		# In the open east of the ruin, 16" from the Meganobz (in their range),
		# or inside the ruin beyond their reach after their move (Hidden himself).
		var lp := Vector2(800.0, 1500.0) if not inside else Vector2(720.0, 1300.0)
		GS.state.units["U_BLADE_CHAMPION_A"].models[0]["position"] = {"x": lp.x, "y": lp.y}
		_knob("FIX_MOVE_COVER", 1.0)
		_knob("HIDDEN_FORFEIT_PENALTY", 3.0)
		var snap: Dictionary = GS.create_snapshot()
		var members: Array = AIDM._move_cover_members(snap.units["U_CUSTODIAN_GUARD_B"], snap, true)
		var fwd_only: Array = AIDM._move_cover_members(snap.units["U_CUSTODIAN_GUARD_B"], snap)
		_check("without with_back_links the member list is the forward list, as before (n=%d)" % fwd_only.size(), fwd_only.size() == 5)
		var has_leader := false
		var leader_moves := true
		for mb in members:
			if str(mb.unit.get("id", "")) == "U_BLADE_CHAMPION_A":
				has_leader = true
				leader_moves = bool(mb.get("moves", true))
		_check("members include the back-pointer-only leader, held where he stands (n=%d, moves=%s)" % [members.size(), str(leader_moves)],
			has_leader and not leader_moves and members.size() == 6)
		var pick: Dictionary = _pick(snap, "U_CUSTODIAN_GUARD_B")
		var kind := str(pick.get("kind", "none"))
		if not inside:
			# Engine: the bodyguard at the pick's end (or at the ruin), the leader
			# where he stands, Player 2's turn (index 7): the Meganobz can target
			# the unit through him (06.01 / 19.01).
			var bg: Dictionary = GS.state.units["U_CUSTODIAN_GUARD_B"]
			var c0: Vector2 = AIDM._get_unit_centroid(bg)
			var end_c: Vector2 = Vector2(pick.end) if not pick.is_empty() else Vector2(600.0, 1060.0)
			for m in bg.models:
				m["position"] = _vec(m.position) + (end_c - c0)
			_set_turn(3, 2)
			var targets: Array = RE.get_eligible_targets("U_MEGANOBZ_A", GS.state).keys()
			_set_turn(3, 1)
			_check("leader in the open: no Hidden claim (kind=%s); the engine agrees the unit is a target (%s)" % [kind, str(targets)],
				kind != "hidden" and "U_CUSTODIAN_GUARD_B" in targets)
		else:
			_check("control, leader standing Hidden inside the ruin: the Hidden claim stands (kind=%s)" % kind, kind == "hidden")
		_clear_knobs()

# --- run ----------------------------------------------------------------------

func _run() -> void:
	GS = root.get_node("GameState")
	TM = root.get_node("TerrainManager")
	PM = root.get_node("PhaseManager")
	SM = root.get_node("StratagemManager")
	RE = root.get_node("RulesEngine")
	MM = root.get_node("MissionManager")
	AIP = root.get_node("AIPlayer")
	AIDM = load(AI_PATH)
	print("\n=== The AI's Hidden predictions ask the engine's questions (11e 13.09 / 15.08 / 06.01 / 19.01) ===")
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	_section_engine_helpers()
	_section_prev_turn_overwatch()
	_section_attached_f002()
	_section_back_pointer_leader()
	_clear_knobs()
	AIDM.reset_caches()
	GameConstants.edition = prev_edition
	_completed = true
