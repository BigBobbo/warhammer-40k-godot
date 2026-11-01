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
# only); FLY pays 0. So a bike leaving a tall terrain area paid 8" (6" "climb
# down" + 2") instead of 2" and moved 3-4" instead of 9-10". And
# _path_blocked_by_terrain blocked every piece (FLY excepted), while the
# engine (TerrainManager.can_move_through_11e, 13.06) blocks only dense
# features taller than 2" — light features and terrain areas never block, and
# a FLY VEHICLE that does not take to the skies is blocked by them too.
#
# With FIX_MOVE_TERRAIN_11E = 1 Normal/Advance moves use the engine's movement
# cost and the engine's 13.06 path gate. Guards: INFANTRY moves are unchanged;
# a dense feature taller than 2" still blocks; FIX_MOVE_TERRAIN_11E = 0
# restores the old plan.
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
const OBJ_NML_2 := Vector2(260, 1650)
const OBJ_CENTER := Vector2(880, 1200)

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

	test_bike_leaving_tall_area_moves_full_distance()
	test_param_zero_restores_charge_cost()
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
	# Deffkilla Wartrike: MOUNTED, M12 (bench Ork roster), one model.
	return _unit("U_WARTRIKE_T", ["CHARACTER", "MOUNTED", "ORKS", "SPEED FREEKS"], 12.0, [IN_AREA_13])

func test_bike_leaving_tall_area_moves_full_distance() -> void:
	print("\n--- Wartrike (MOUNTED, M12) leaves area-large-13 toward obj_nml_2, FIX = 1 ---")
	var p = _plan(_wartrike(), OBJ_NML_2, 1.0)
	print("  planned %.2f\" (engine-valid: %s %s)" % [p.max_raw, str(p.engine_ok), p.worst])
	# Engine: 2" difficult ground for leaving the area, no climb onto open
	# ground -> 10" raw; the AI's own 5% cap margin leaves ~9.4".
	_assert(p.max_raw >= 9.0, "the bike plans at least 9\" (M - 2\" difficult ground - 5%% margin), got %.2f\"" % p.max_raw)
	_assert(p.engine_ok, "every staged model passes MovementPhase validation (raw + movement terrain penalty <= M) %s" % p.worst)

func test_param_zero_restores_charge_cost() -> void:
	print("\n--- same move, FIX = 0 (old charge cost: 6\" climb down + 2\") ---")
	var p = _plan(_wartrike(), OBJ_NML_2, 0.0)
	print("  planned %.2f\"" % p.max_raw)
	_assert(p.max_raw > 0.0 and p.max_raw <= 4.5, "off: the old plan is cut to about 3.4\" (got %.2f\")" % p.max_raw)

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
	print("\n--- cross-seat: P2 profile FIX = 1, _current_player = 2; a P1 and a P2 Wartrike leave area-large-13 ---")
	var p1_trike := _wartrike()
	p1_trike["owner"] = 1
	var p2_trike := _wartrike()
	# References (global config), each unit planned for its own seat.
	var p1_off := _plan(p1_trike, OBJ_NML_2, 0.0)
	var p1_on := _plan(p1_trike, OBJ_NML_2, 1.0)
	var p2_off := _plan(p2_trike, OBJ_NML_2, 0.0)
	var p2_on := _plan(p2_trike, OBJ_NML_2, 1.0)
	_assert(str(p1_on.dests) != str(p1_off.dests) and str(p2_on.dests) != str(p2_off.dests),
		"the fix changes this move in its own seat (P1 off %.2f\" / on %.2f\", P2 off %.2f\" / on %.2f\")" % [
		p1_off.max_raw, p1_on.max_raw, p2_off.max_raw, p2_on.max_raw])
	# Bench state: no global override, FIX = 1 only in P2's profile, HEAD deciding for P2.
	AIDM._config_overrides.erase("FIX_MOVE_TERRAIN_11E")
	AIDM.load_player_profile(2, {"parameters": {"FIX_MOVE_TERRAIN_11E": 1.0}})
	var p1_cross := _plan_for_seat(p1_trike, OBJ_NML_2, 2)
	var p2_cross := _plan_for_seat(p2_trike, OBJ_NML_2, 2)
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
		var trike := _wartrike()
		trike["owner"] = seat_owner
		# The pre-roll plan (FIX = 0, own seat) gives the heading the re-plan keeps.
		var pre := _plan(trike, OBJ_NML_2, 0.0)
		var decision := {"type": "BEGIN_ADVANCE", "actor_unit_id": trike.id, "_ai_model_destinations": pre.dests}
		var off := _recompute(ai, trike, decision, 0.0, seat_owner)
		var on := _recompute(ai, trike, decision, 1.0, seat_owner)
		AIDM._config_overrides.erase("FIX_MOVE_TERRAIN_11E")
		AIDM.load_player_profile(2, {"parameters": {"FIX_MOVE_TERRAIN_11E": 1.0}})
		var cross := _recompute(ai, trike, decision, -1.0, 2)
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

func test_bench_fixture_stompa_moves_pass_engine_validation() -> void:
	print("\n--- asym_2000_postdeploy: P2 Stompa (VEHICLE, M10) Normal moves toward three objectives ---")
	var gs = root.get_node("GameState")
	var ser = root.get_node("StateSerializer")
	var state: Dictionary = ser.deserialize_game_state(FileAccess.get_file_as_string("res://tests/saves/asym_2000_postdeploy.w40ksave"))
	gs.load_from_snapshot(state)  # also loads the fixture's terrain layout into TerrainManager
	var snap: Dictionary = gs.create_snapshot()
	var uid := "U_STOMPA_A"
	var unit: Dictionary = snap.units[uid]
	var enemies = AIDM._get_enemy_units(snap, 2)
	var objs: Array = AIDM._get_objectives(snap)
	var targets := {"obj_home_2": Vector2(1060, 1929.6), "obj_nml_2": Vector2(260, 1650), "obj_center": Vector2(880, 1200)}
	var old_bad := 0
	var new_bad := 0
	var new_moved := 0
	for oid in targets:
		AIDM._current_player = int(unit.owner)  # P2 decides for its own Stompa, as decide() sets it
		AIDM._config_overrides["FIX_MOVE_TERRAIN_11E"] = 0.0
		var off: Dictionary = AIDM._compute_movement_toward_target(unit, uid, targets[oid], 10.0, snap, enemies, 0.0, [], objs)
		AIDM._config_overrides["FIX_MOVE_TERRAIN_11E"] = 1.0
		var on: Dictionary = AIDM._compute_movement_toward_target(unit, uid, targets[oid], 10.0, snap, enemies, 0.0, [], objs)
		var rej_off := _engine_rejects(unit, uid, off)
		var rej_on := _engine_rejects(unit, uid, on)
		print("  -> %s: off rejected %s | on rejected %s (on: %d dests)" % [oid, str(rej_off), str(rej_on), on.size()])
		old_bad += rej_off.size()
		new_bad += rej_on.size()
		if not on.is_empty():
			new_moved += 1
	_assert(old_bad > 0, "off: the old plans include moves the engine rejects (%d)" % old_bad)
	_assert(new_bad == 0, "on: every planned Stompa move passes the engine's terrain cost and 13.06 gate (%d rejected)" % new_bad)
	_assert(new_moved == targets.size(), "on: a move is planned toward every objective (%d/%d)" % [new_moved, targets.size()])
