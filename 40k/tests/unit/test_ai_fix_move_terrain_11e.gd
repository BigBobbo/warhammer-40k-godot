extends SceneTree

# FIX-MOVE-TERRAIN-11E (11e rules audit TER-01, protocol V2-4): Normal and
# Advance moves of non-INFANTRY units were priced with the CHARGE terrain cost
# and blocked by every terrain piece.
#
# Root cause — _compute_movement_toward_target and the per-model cap in
# _try_move_with_collision_check priced a Normal/Advance move with
# _estimate_charge_terrain_penalty (TerrainManager.calculate_charge_terrain_
# penalty: 1x or 2x the piece height for every piece the unit cannot move
# through, plus 2" difficult ground; FLY pays a diagonal climb). The engine
# validates a Normal/Advance move with MovementPhase._get_movement_terrain_
# penalty: 2" per difficult-ground piece (TerrainManager.calculate_movement_
# terrain_penalty) plus the climb onto the piece at the destination (ascent
# only); FLY pays 0. And _path_blocked_by_terrain blocked every piece (FLY
# excepted), while the engine (TerrainManager.can_move_through_11e, 13.06)
# blocks only dense features taller than 2" — light features and terrain areas
# never block, and a FLY VEHICLE that does not take to the skies is blocked by
# them too.
#
# The climb contrast is a terrain FEATURE's (2026-11, bd9392c): a terrain AREA
# is a boundary on the ground, not a surface (TerrainManager.get_height_inches
# = 0, 13.06), so both costs now charge only its 2" difficult ground — the old
# fixture here (a bike leaving the open ground of the tall area area-large-13:
# off 8", 3.4" planned; on 2", 9.4") plans the same move on and off, and a guard
# below pins that. A FEATURE keeps its height: a bike standing in the light
# ruin corner-short-21 (6" to the climb model, difficult ground, inside
# area-large-13) that leaves it pays the charge cost's 6" "climb down" + 2" + 2"
# = 10" with the flag off (1.4" planned), but only the engine's 4" of
# difficult ground with it on (descent is free; 7.4" planned). On the
# bench fixture, a Warbikers model's off-plan spot crosses the light ruin
# corner-short-9 unpriced (the placement step does not price terrain) and the
# engine rejects it; the flag's engine-exact placement gate does not.
#
# With FIX_MOVE_TERRAIN_11E = 1 Normal/Advance moves use the engine's movement
# cost and the engine's 13.06 path gate. Guards: INFANTRY moves are unchanged;
# a dense feature taller than 2" still blocks; FIX_MOVE_TERRAIN_11E = 0
# restores the old plan.
#
# What each contrast rests on (2026-11 review). The COST contrasts here — the
# Wartrike leaving the light ruin corner-short-21 (off 1.4" / on 7.4") and the
# Warbikers' m6 crossing the light ruin corner-short-9 (+4") — rest on the
# engine's current model of LIGHT terrain: for a non-INFANTRY unit a light
# feature's height is a climb (the charge cost's "climb down" when leaving it)
# and light pieces are difficult ground. That model is a tracked engine
# deviation (rules audit TER-02), NOT 13.06 — "All models can move horizontally
# and vertically through exposed and light terrain features" — so a TER-02 fix
# flattens these the way bd9392c flattened the area contrast; their messages say
# so. The remaining charge-cost / engine disagreements the flag reconciles are
# engine-model choices too (the charge cost's "climb down", its exemption of a
# dense piece a charge ends in), not 13.06. The seat checks (cross-seat and
# AIPlayer.recompute_destinations_for_cap) therefore use a contrast that
# survives TER-02: the 13.06 PATH GATE. Off, every terrain piece blocks a
# VEHICLE's path, so a Trukk heading west across the light terrain area
# area-medium-8 detours; on, only dense features over 2" block, so it drives
# straight (test_light_area_does_not_block_vehicle pins the gate itself).
#
# Seat: the fix acts only on a unit of the seat the AI decides for (unit owner
# == _current_player; decide() sets it). AIPlayer re-plans a rolled Advance
# (recompute_destinations_for_cap, AIPlayer.gd:1699) and a failed staging
# (AIPlayer.gd:2788) through the class_name AIDecisionMaker for BOTH seats, so
# in the two-version bench (--cand HEAD --cand-profile) HEAD planned base-seat
# units while its _current_player was the candidate seat and read the
# candidate's profile. The plans below are made for the unit's own seat, as
# decide() makes them; two tests pin the cross-seat case.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_fix_move_terrain_11e.gd

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const LAYOUT := "take_and_hold_mirror_1"  # the terrain of the asym_2000_postdeploy bench fixture
const PX := 40.0
# Inside area-large-13 (P2 home terrain area: dense ruin, tall, difficult
# ground; x 920-1200, y 1700-2160), clear of its walls.
const IN_AREA_13 := Vector2(980, 1950)
# Inside the light ruin corner-short-21 (a 0.5"-thick L of light, "tall" (6" to
# the climb model) difficult-ground terrain in area-large-13; its east arm spans
# x 29.06-29.56", y 51.65-53.65"): a model whose centre stands in the feature.
const IN_LIGHT_RUIN_21 := Vector2(1172.5, 2096)
const OBJ_NML_2 := Vector2(260, 1650)
const OBJ_CENTER := Vector2(880, 1200)
# East of area-medium-8 (light terrain area, x 10-16", y 47-51", with the light
# corner features corner-short-9 / -11): a Trukk here heading west crosses it.
const EAST_OF_AREA_8 := Vector2(700, 1960)
const WEST_OF_AREA_8 := Vector2(300, 1960)
const TER02 := " [engine model of LIGHT terrain, rules audit TER-02 — not 13.06; update this check when TER-02 lands]"

var _pass_count: int = 0
var _fail_count: int = 0
var _ran := false
var AIDM = null
var _mp = null

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
	print("\n=== FIX-MOVE-TERRAIN-11E: Normal/Advance moves use the engine's movement terrain cost and 13.06 gate ===\n")
	var tm = root.get_node_or_null("TerrainManager")
	var gs = root.get_node_or_null("GameState")
	_assert(tm != null and gs != null, "TerrainManager / GameState autoloads present")
	if tm == null or gs == null:
		print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
		quit(1)
		return
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	var prev_terrain: Array = tm.terrain_features.duplicate(true)
	var prev_state: Dictionary = gs.state.duplicate(true)
	tm.load_terrain_layout(LAYOUT)
	_assert(tm.terrain_features.size() > 0, "bench layout %s loaded (%d pieces)" % [LAYOUT, tm.terrain_features.size()])
	AIDM = load(AI_PATH)
	var prev_current_player: int = AIDM._current_player
	var prev_profiles: Dictionary = AIDM._player_profiles.duplicate(true)
	# The engine's own validator (MovementPhase) for the staged destinations.
	_mp = load("res://phases/MovementPhase.gd").new()
	root.add_child(_mp)

	test_bike_leaving_light_ruin_moves_full_distance()
	test_param_zero_restores_charge_cost()
	test_area_open_ground_same_on_and_off()
	test_light_area_does_not_block_vehicle()
	test_fly_vehicle_blocked_by_dense_wall()
	test_dense_wall_still_blocks()
	test_infantry_unchanged()
	test_profile_fix_stays_in_its_seat()
	test_aiplayer_recompute_stays_in_its_seat()
	test_bench_fixture_stompa_moves_pass_engine_validation()

	AIDM._config_overrides.erase("FIX_MOVE_TERRAIN_11E")
	AIDM._player_profiles = prev_profiles
	AIDM._current_player = prev_current_player
	_mp.queue_free()
	gs.state = prev_state
	tm.terrain_features = prev_terrain
	GameConstants.edition = prev_edition
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

# --- fixtures ---------------------------------------------------------------

func _unit(uid: String, keywords: Array, move: float, positions: Array, base_mm: int = 60) -> Dictionary:
	var models = []
	for i in range(positions.size()):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": base_mm, "base_type": "circular",
			"base_dimensions": {}, "position": positions[i], "wounds": 4, "current_wounds": 4})
	return {"id": uid, "owner": 2, "status": 2,
		"meta": {"name": uid, "points": 80, "keywords": keywords,
			"stats": {"move": move, "toughness": 6, "save": 4, "wounds": 4, "leadership": 7, "objective_control": 3},
			"weapons": []},
		"models": models, "flags": {}}

func _snapshot(units: Dictionary) -> Dictionary:
	var tm = root.get_node("TerrainManager")
	return {"battle_round": 2, "meta": {"battle_round": 2, "active_player": 2},
		"board": {"objectives": [], "terrain_features": tm.terrain_features.duplicate(true)},
		"units": units}

## The AI's Normal-move plan for `unit` toward `target` with the fix at `fix`
## (global config), planned for the unit's own seat as decide() plans it:
## {dests, max_raw (inches), engine_ok (every model: raw + the engine's
## movement terrain penalty <= M)}.
func _plan(unit: Dictionary, target: Vector2, fix: float) -> Dictionary:
	AIDM._config_overrides["FIX_MOVE_TERRAIN_11E"] = fix
	return _plan_for_seat(unit, target, int(unit.owner))

## The same plan with whatever FIX_MOVE_TERRAIN_11E the config and the player
## profiles give, made while the AI decides for `seat` (_current_player).
func _plan_for_seat(unit: Dictionary, target: Vector2, seat: int) -> Dictionary:
	AIDM._current_player = seat
	var uid: String = unit.id
	var snap = _snapshot({uid: unit})
	root.get_node("GameState").state["units"] = snap.units.duplicate(true)
	var move := float(unit.meta.stats.move)
	var dests: Dictionary = AIDM._compute_movement_toward_target(unit, uid, target, move, snap, {}, 0.0, [], [])
	var max_raw := 0.0
	var engine_ok := not dests.is_empty()
	var worst := ""
	for mdl in unit.models:
		var mid := str(mdl.id)
		if not dests.has(mid):
			engine_ok = false
			continue
		var o: Vector2 = mdl.position
		var d := Vector2(float(dests[mid][0]), float(dests[mid][1]))
		var raw := o.distance_to(d) / PX
		var pen := float(_mp._get_movement_terrain_penalty(o, d, uid, false))
		max_raw = maxf(max_raw, raw)
		if raw + pen > move + 0.01:
			engine_ok = false
			worst = "%s %.2f\" + %.2f\" > %.0f\"" % [mid, raw, pen, move]
	return {"dests": dests, "max_raw": max_raw, "engine_ok": engine_ok, "worst": worst}

## _find_unblocked_move_enhanced returns the direct vector when the path is
## open (no enemies: no cover detour) and another vector when it is blocked.
func _direct_open(unit: Dictionary, from: Vector2, to: Vector2, fix: float) -> bool:
	AIDM._config_overrides["FIX_MOVE_TERRAIN_11E"] = fix
	AIDM._current_player = int(unit.owner)  # the unit's own seat, as decide() sets it
	var tm = root.get_node("TerrainManager")
	var mv := to - from
	var got: Vector2 = AIDM._find_unblocked_move_enhanced(from, mv, mv.length(), unit.meta.keywords,
		tm.terrain_features, {}, unit)
	return got.is_equal_approx(mv)

# --- tests --------------------------------------------------------------------

func _wartrike() -> Dictionary:
	# Deffkilla Wartrike: MOUNTED, M12 (bench Ork roster), one model, in the
	# open ground of area-large-13.
	return _unit("U_WARTRIKE_T", ["CHARACTER", "MOUNTED", "ORKS", "SPEED FREEKS"], 12.0, [IN_AREA_13])

## The same Wartrike standing in the light ruin corner-short-21 (a FEATURE:
## its height is a climb in the engine's current light-terrain model, TER-02;
## the area around it is not).
func _ruin_trike() -> Dictionary:
	return _unit("U_WARTRIKE_T", ["CHARACTER", "MOUNTED", "ORKS", "SPEED FREEKS"], 12.0, [IN_LIGHT_RUIN_21])

## A Trukk (VEHICLE, M12, 90mm) east of the light terrain area area-medium-8 —
## the seat checks' contrast: the 13.06 path gate (off: every piece blocks a
## VEHICLE; on: only dense features over 2"), which TER-02 does not touch.
func _gate_trukk() -> Dictionary:
	return _unit("U_TRUKK_T", ["ORKS", "TRANSPORT", "VEHICLE"], 12.0, [EAST_OF_AREA_8], 90)

func test_bike_leaving_light_ruin_moves_full_distance() -> void:
	print("\n--- Wartrike (MOUNTED, M12) leaves the light ruin corner-short-21 toward obj_nml_2, FIX = 1 ---")
	var tm = root.get_node("TerrainManager")
	_assert(str(tm.get_terrain_at_position(IN_LIGHT_RUIN_21).get("id", "")) == "corner-short-21",
		"setup: the bike stands in the light ruin corner-short-21 (the FEATURE at the point)")
	var p = _plan(_ruin_trike(), OBJ_NML_2, 1.0)
	print("  planned %.2f\" (engine-valid: %s %s)" % [p.max_raw, str(p.engine_ok), p.worst])
	# Engine: 2" difficult ground for the ruin + 2" for the area; stepping down
	# off the ruin is free (ascent only). The AI caps the move at 95% of M
	# (11.4") less the terrain cost -> 7.4".
	_assert(p.max_raw >= 7.0, "the bike plans at least 7\" (95%% of M - 4\" difficult ground), got %.2f\"%s" % [p.max_raw, TER02])
	_assert(p.engine_ok, "every staged model passes MovementPhase validation (raw + movement terrain penalty <= M) %s" % p.worst)

func test_param_zero_restores_charge_cost() -> void:
	print("\n--- same move, FIX = 0 (old charge cost: the ruin's 6\" climb down + 2\" + the area's 2\") ---")
	var p = _plan(_ruin_trike(), OBJ_NML_2, 0.0)
	print("  planned %.2f\"" % p.max_raw)
	_assert(p.max_raw > 0.0 and p.max_raw <= 2.5, "off: the old plan is cut to about 1.4\" (11.4\" - 10\"; got %.2f\")%s" % [p.max_raw, TER02])

## Guard (bd9392c): a terrain AREA's open ground is no climb for either cost
## (get_height_inches(area) = 0), so the fixture this test used before — the
## bike leaving area-large-13's open ground — plans the same move on and off.
## If an area ever reads as a surface again, the two part and this fails.
func test_area_open_ground_same_on_and_off() -> void:
	print("\n--- guard: Wartrike leaves area-large-13's OPEN GROUND (no feature): on = off ---")
	var on := _plan(_wartrike(), OBJ_NML_2, 1.0)
	var off := _plan(_wartrike(), OBJ_NML_2, 0.0)
	print("  on %.2f\" / off %.2f\"" % [on.max_raw, off.max_raw])
	_assert(not on.dests.is_empty() and str(on.dests) == str(off.dests) and on.max_raw >= 9.0,
		"area open ground: the same ~9.4\" move on and off (2\" difficult ground only; got on %.2f\" / off %.2f\")" % [on.max_raw, off.max_raw])

func test_light_area_does_not_block_vehicle() -> void:
	print("\n--- VEHICLE path across area-medium-8 (light terrain area with light corner features) ---")
	var v = _unit("U_TRUKK_T", ["ORKS", "TRANSPORT", "VEHICLE"], 12.0, [Vector2(700, 1960)], 90)
	var from := Vector2(700, 1960)
	var to := Vector2(300, 1960)
	var on := _direct_open(v, from, to, 1.0)
	var off := _direct_open(v, from, to, 0.0)
	print("  direct path open: on=%s off=%s" % [str(on), str(off)])
	_assert(on, "on: the direct path across the light area is open (13.06: only dense features over 2\" block)")
	_assert(not off, "off: the old rule blocks it (every terrain piece blocks a VEHICLE)")

func test_fly_vehicle_blocked_by_dense_wall() -> void:
	print("\n--- FLY VEHICLE (Deffkoptas) path across corner-ruin-left-19 (dense feature, 5\") ---")
	var k = _unit("U_KOPTAS_T", ["FLY", "ORKS", "SPEED FREEKS", "VEHICLE"], 12.0, [Vector2(1050, 1640)], 75)
	var from := Vector2(1050, 1640)
	var to := Vector2(1050, 1950)
	var on := _direct_open(k, from, to, 1.0)
	var off := _direct_open(k, from, to, 0.0)
	print("  direct path open: on=%s off=%s" % [str(on), str(off)])
	_assert(not on, "on: the wall blocks a FLY VEHICLE that does not take to the skies (engine 13.06 gate)")
	_assert(off, "off: the old rule let every FLY unit pass")

func test_dense_wall_still_blocks() -> void:
	print("\n--- guard: MOUNTED path across corner-ruin-left-19 (dense feature, 5\") ---")
	var b = _unit("U_BIKE_T", ["MOUNTED", "ORKS"], 12.0, [Vector2(1050, 1640)])
	var from := Vector2(1050, 1640)
	var to := Vector2(1050, 1950)
	var on := _direct_open(b, from, to, 1.0)
	var off := _direct_open(b, from, to, 0.0)
	_assert(not on and not off, "a dense feature over 2\" blocks the bike on and off (on open=%s, off open=%s)" % [str(on), str(off)])

func test_infantry_unchanged() -> void:
	print("\n--- guard: INFANTRY leaving area-large-13 (moves through ruins: no cost) ---")
	var pos: Array = [IN_AREA_13, IN_AREA_13 + Vector2(40, 0), IN_AREA_13 + Vector2(0, 40)]
	var inf_on = _plan(_unit("U_BOYZ_T", ["INFANTRY", "ORKS"], 6.0, pos, 32), OBJ_CENTER, 1.0)
	var inf_off = _plan(_unit("U_BOYZ_T", ["INFANTRY", "ORKS"], 6.0, pos, 32), OBJ_CENTER, 0.0)
	print("  on %.2f\" / off %.2f\"" % [inf_on.max_raw, inf_off.max_raw])
	_assert(str(inf_on.dests) == str(inf_off.dests) and not inf_on.dests.is_empty(),
		"INFANTRY plans the identical move on and off (%.2f\")" % inf_on.max_raw)
	var open_on := _direct_open(_unit("U_BOYZ_T", ["INFANTRY", "ORKS"], 6.0, [Vector2(700, 1960)], 32), Vector2(700, 1960), Vector2(300, 1960), 1.0)
	var open_off := _direct_open(_unit("U_BOYZ_T", ["INFANTRY", "ORKS"], 6.0, [Vector2(700, 1960)], 32), Vector2(700, 1960), Vector2(300, 1960), 0.0)
	_assert(open_on and open_off, "INFANTRY path across terrain is open on and off")

## The two-version bench (tools/ai_lab/ai_versions.py run --cand HEAD
## --cand-profile): HEAD plays P2 with FIX_MOVE_TERRAIN_11E = 1 in its
## profile, P1 an extracted copy. AIPlayer's Advance re-plan and staging retry
## call the class_name AIDecisionMaker for BOTH seats, so HEAD plans a P1 unit
## while its _current_player is 2 and get_param reads P2's profile. The fix
## must stay in P2's seat: the P1 unit plans its FIX = 0 move, the P2 unit the
## fix-on move.
func test_profile_fix_stays_in_its_seat() -> void:
	print("\n--- cross-seat: P2 profile FIX = 1, _current_player = 2; a P1 and a P2 Trukk head west across the light area area-medium-8 (path-gate contrast) ---")
	var p1_trukk := _gate_trukk()
	p1_trukk["owner"] = 1
	var p2_trukk := _gate_trukk()
	# References (global config), each unit planned for its own seat.
	var p1_off := _plan(p1_trukk, WEST_OF_AREA_8, 0.0)
	var p1_on := _plan(p1_trukk, WEST_OF_AREA_8, 1.0)
	var p2_off := _plan(p2_trukk, WEST_OF_AREA_8, 0.0)
	var p2_on := _plan(p2_trukk, WEST_OF_AREA_8, 1.0)
	_assert(str(p1_on.dests) != str(p1_off.dests) and str(p2_on.dests) != str(p2_off.dests),
		"the fix changes this move in its own seat (P1 off %s / on %s, P2 off %s / on %s)" % [
		str(p1_off.dests), str(p1_on.dests), str(p2_off.dests), str(p2_on.dests)])
	# Bench state: no global override, FIX = 1 only in P2's profile, HEAD deciding for P2.
	AIDM._config_overrides.erase("FIX_MOVE_TERRAIN_11E")
	AIDM.load_player_profile(2, {"parameters": {"FIX_MOVE_TERRAIN_11E": 1.0}})
	var p1_cross := _plan_for_seat(p1_trukk, WEST_OF_AREA_8, 2)
	var p2_cross := _plan_for_seat(p2_trukk, WEST_OF_AREA_8, 2)
	AIDM.clear_player_profile(2)
	print("  while P2 decides: P1 unit %.2f\" (off %.2f\", on %.2f\") | P2 unit %.2f\" (off %.2f\", on %.2f\")" % [
		p1_cross.max_raw, p1_off.max_raw, p1_on.max_raw, p2_cross.max_raw, p2_off.max_raw, p2_on.max_raw])
	_assert(not p1_cross.dests.is_empty() and str(p1_cross.dests) == str(p1_off.dests),
		"a P1 unit planned while P2 decides keeps its FIX = 0 plan (%.2f\"): P2's profile does not reach it" % p1_cross.max_raw)
	_assert(not p2_cross.dests.is_empty() and str(p2_cross.dests) == str(p2_on.dests),
		"a P2 unit planned with P2's profile gets the fix-on plan (%.2f\")" % p2_cross.max_raw)

## The same through the real call site: AIPlayer.recompute_destinations_for_cap
## (AIPlayer.gd:1699) re-plans a rolled Advance through the class_name
## AIDecisionMaker for whichever seat rolled it.
func test_aiplayer_recompute_stays_in_its_seat() -> void:
	print("\n--- cross-seat via AIPlayer.recompute_destinations_for_cap (Advance rolled 1: cap 13\") ---")
	var ai = root.get_node_or_null("AIPlayer")
	_assert(ai != null and ai.has_method("recompute_destinations_for_cap"), "AIPlayer autoload with recompute_destinations_for_cap present")
	if ai == null or not ai.has_method("recompute_destinations_for_cap"):
		return
	for seat_owner in [1, 2]:
		var trukk := _gate_trukk()
		trukk["owner"] = seat_owner
		# The pre-roll plan gives the heading the re-plan keeps: the FIX = 1 plan
		# (own seat) drives straight across the light area, so the re-plan's
		# 13.06 path gate decides it (off: every piece blocks a VEHICLE -> detour).
		var pre := _plan(trukk, WEST_OF_AREA_8, 1.0)
		var decision := {"type": "BEGIN_ADVANCE", "actor_unit_id": trukk.id, "_ai_model_destinations": pre.dests}
		var off := _recompute(ai, trukk, decision, 0.0, seat_owner)
		var on := _recompute(ai, trukk, decision, 1.0, seat_owner)
		AIDM._config_overrides.erase("FIX_MOVE_TERRAIN_11E")
		AIDM.load_player_profile(2, {"parameters": {"FIX_MOVE_TERRAIN_11E": 1.0}})
		var cross := _recompute(ai, trukk, decision, -1.0, 2)
		AIDM.clear_player_profile(2)
		print("  P%d unit: off %s | on %s | while P2 decides with its profile %s" % [seat_owner, str(off), str(on), str(cross)])
		_assert(not off.is_empty() and not on.is_empty() and str(on) != str(off),
			"P%d: the fix changes the re-planned Advance in its own seat" % seat_owner)
		if seat_owner == 1:
			_assert(str(cross) == str(off), "a P1 unit re-planned by AIPlayer while P2 decides keeps its FIX = 0 destinations")
		else:
			_assert(str(cross) == str(on), "a P2 unit re-planned by AIPlayer with P2's profile gets the fix-on destinations")

## AIPlayer.recompute_destinations_for_cap for `unit` (its owner rolled a 1:
## cap M + 1 = 13") with the fix at `fix` in the global config (< 0: no global
## override), while the AI decides for `seat` (_current_player).
func _recompute(ai, unit: Dictionary, decision: Dictionary, fix: float, seat: int) -> Dictionary:
	if fix >= 0.0:
		AIDM._config_overrides["FIX_MOVE_TERRAIN_11E"] = fix
	AIDM._current_player = seat
	root.get_node("GameState").state["units"] = {str(unit.id): unit.duplicate(true)}
	return ai.recompute_destinations_for_cap(int(unit.owner), str(unit.id), unit, decision, 13.0)

## Every staged model of `dests` passes the engine's checks for a Normal move:
## raw + MovementPhase._get_movement_terrain_penalty <= M, and the 13.06 dense
## gate (TerrainManager.can_move_through_11e with the model's base).
func _engine_rejects(unit: Dictionary, uid: String, dests: Dictionary) -> Array:
	var tm = root.get_node("TerrainManager")
	var move := float(unit.meta.stats.move)
	var out: Array = []
	for mdl in unit.models:
		var mid := str(mdl.id)
		if not dests.has(mid):
			continue
		var o := Vector2(float(mdl.position.x), float(mdl.position.y))
		var d := Vector2(float(dests[mid][0]), float(dests[mid][1]))
		var raw := o.distance_to(d) / PX
		var pen := float(_mp._get_movement_terrain_penalty(o, d, uid, false))
		var gate: Dictionary = tm.can_move_through_11e(unit.meta.keywords, o, d, [], {"position": o,
			"base_mm": mdl.get("base_mm", 32), "base_type": mdl.get("base_type", "circular"),
			"base_dimensions": mdl.get("base_dimensions", {}), "rotation": mdl.get("rotation", 0.0)})
		if raw + pen > move + 0.01 or not gate.allowed:
			out.append("%s %.2f\" + %.2f\" (gate %s)" % [mid, raw, pen, str(gate.allowed)])
	return out

## The bench fixture (asym_2000_postdeploy, P2 Orks): Normal moves of the P2
## Stompa (VEHICLE, M10) toward three objectives and of Warbikers D (MOUNTED,
## M12, six models) toward obj_nml_1. Warbikers D's m6 crosses area-medium-8
## and its light ruin corner-short-9 (a FEATURE): the old plan's placement step
## (formation / collision spots, after the cap was set) prices no terrain, so
## m6 is staged 11.4" out and the engine adds 4" of difficult ground (15.4" >
## 12"); the fix's engine-exact placement gate retries it shorter. The Stompa
## checks guard the fix against producing moves the engine rejects. (Before
## bd9392c the Stompa's own off plans were rejected too — tall areas read as
## climbs; with area height 0 they no longer are.)
func test_bench_fixture_stompa_moves_pass_engine_validation() -> void:
	print("\n--- asym_2000_postdeploy: P2 Stompa (VEHICLE, M10) toward three objectives, Warbikers D (MOUNTED, M12) toward obj_nml_1 ---")
	var gs = root.get_node("GameState")
	var ser = root.get_node("StateSerializer")
	var state: Dictionary = ser.deserialize_game_state(FileAccess.get_file_as_string("res://tests/saves/asym_2000_postdeploy.w40ksave"))
	gs.load_from_snapshot(state)  # also loads the fixture's terrain layout into TerrainManager
	var snap: Dictionary = gs.create_snapshot()
	var enemies = AIDM._get_enemy_units(snap, 2)
	var objs: Array = AIDM._get_objectives(snap)
	var moves := [
		["U_STOMPA_A", "obj_home_2", Vector2(1060, 1929.6)],
		["U_STOMPA_A", "obj_nml_2", Vector2(260, 1650)],
		["U_STOMPA_A", "obj_center", Vector2(880, 1200)],
		["U_WARBIKERS_D", "obj_nml_1", Vector2(1500, 750)],
	]
	var old_bad := 0
	var new_bad := 0
	var new_moved := 0
	var feature_crossing_rejected := false
	for mv in moves:
		var uid: String = mv[0]
		var unit: Dictionary = snap.units[uid]
		var move := float(unit.meta.stats.move)
		AIDM._current_player = int(unit.owner)  # P2 decides for its own unit, as decide() sets it
		AIDM._config_overrides["FIX_MOVE_TERRAIN_11E"] = 0.0
		var off: Dictionary = AIDM._compute_movement_toward_target(unit, uid, mv[2], move, snap, enemies, 0.0, [], objs)
		AIDM._config_overrides["FIX_MOVE_TERRAIN_11E"] = 1.0
		var on: Dictionary = AIDM._compute_movement_toward_target(unit, uid, mv[2], move, snap, enemies, 0.0, [], objs)
		var rej_off := _engine_rejects(unit, uid, off)
		var rej_on := _engine_rejects(unit, uid, on)
		print("  %s -> %s: off rejected %s | on rejected %s (on: %d dests)" % [uid, mv[1], str(rej_off), str(rej_on), on.size()])
		old_bad += rej_off.size()
		new_bad += rej_on.size()
		if not on.is_empty():
			new_moved += 1
		if uid == "U_WARBIKERS_D" and not rej_off.is_empty() and _crosses_piece(unit, off, "corner-short-9"):
			feature_crossing_rejected = true
	_assert(old_bad > 0, "off: the old plans include moves the engine rejects (%d)%s" % [old_bad, TER02])
	_assert(feature_crossing_rejected, "off: the rejected Warbikers spot crosses the light ruin corner-short-9 (a feature, priced by neither the placement step nor the old cap)" + TER02)
	_assert(new_bad == 0, "on: every planned move passes the engine's terrain cost and 13.06 gate (%d rejected)" % new_bad)
	_assert(new_moved == moves.size(), "on: every move is planned (%d/%d)" % [new_moved, moves.size()])

## Does any model of `unit` cross (or end in) the piece `piece_id` on its way
## to its destination in `dests`?
func _crosses_piece(unit: Dictionary, dests: Dictionary, piece_id: String) -> bool:
	var tm = root.get_node("TerrainManager")
	for mdl in unit.models:
		var mid := str(mdl.id)
		if not dests.has(mid):
			continue
		var o := Vector2(float(mdl.position.x), float(mdl.position.y))
		var d := Vector2(float(dests[mid][0]), float(dests[mid][1]))
		for pc in tm.features_crossing(o, d):
			if str(pc.get("id", "")) == piece_id:
				return true
		for pc in tm.pieces_at_position(d):
			if str(pc.get("id", "")) == piece_id:
				return true
	return false
