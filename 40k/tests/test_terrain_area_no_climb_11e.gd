extends SceneTree

# 13.06 TERRAIN AND MOVEMENT: only terrain FEATURES impede a move ("This
# INFANTRY model is not being moved over or through any terrain features. Its
# move through the terrain area shown is therefore unimpeded.").
#
# Regression: the legacy climb model (MovementPhase._get_vertical_climb_cost,
# AIDecisionMaker._estimate_move_terrain_penalty — TerrainManager
# get_terrain_at_position + get_height_inches) and the charge penalty
# (TerrainManager.calculate_charge_terrain_penalty) read a terrain AREA's
# height_category as a surface to climb. 7846f06 re-derived recon_1's home
# objective areas (area-large-7/-8) from "low" to "tall", so a VEHICLE / MONSTER
# 4" move from the open battlefield into their open ground cost 12" of a 10"
# Move and was refused, and a charge paid 8". Every tall area on every 11e
# layout already did this (the control area-large-25).
#
# Now get_height_inches(area) = 0 and get_terrain_at_position prefers the
# FEATURE at the point (the 11e layouts list each area before its features),
# so open ground costs no climb and a feature inside an area keeps its own
# climb. MissionManager's Death Trap check reads every piece under a model
# (pieces_at_position), so a kill inside a ruin within a trapped AREA still
# counts.
#
# Usage: godot --headless --path . -s tests/test_terrain_area_no_climb_11e.gd

const LAYOUT := "take_and_hold_vs_reconnaissance_1"
const PHASE_MOVEMENT := 7

var passed := 0
var failed := 0
var _completed := false  # set by the last line of _run(): an aborted run (script error) counts as a failure
var GS = null
var PM = null
var TM = null
var PPI := 40.0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _initialize() -> void:
	await create_timer(0.3).timeout
	_run()
	if not _completed:
		failed += 1
		print("  FAIL: the run aborted before its last check (see the SCRIPT ERROR above)")
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _piece(pid: String) -> Dictionary:
	for p in TM.terrain_features:
		if str(p.get("id", "")) == pid:
			return p
	return {}

func _seed(kws: Array, pos_px: Vector2) -> void:
	GS.state["units"] = {
		"U_TEST": {"id": "U_TEST", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Probe", "keywords": kws.duplicate(), "abilities": [],
				"stats": {"move": 10, "toughness": 10, "save": 3, "wounds": 12, "objective_control": 3}},
			"models": [{"id": "m0", "alive": true, "wounds": 12, "current_wounds": 12,
				"base_mm": 32, "base_type": "circular", "position": {"x": pos_px.x, "y": pos_px.y}}]},
	}
	GS.state["meta"]["active_player"] = 1
	GS.state["meta"]["phase"] = PHASE_MOVEMENT

## A 4" Normal move (10" Move) from start to dest (board inches) through the
## real MovementPhase validation; returns the measured pieces and costs.
func _move(kws: Array, start_in: Vector2, dest_in: Vector2) -> Dictionary:
	var start := start_in * PPI
	var dest := dest_in * PPI
	_seed(kws, start)
	PM.transition_to_phase(PHASE_MOVEMENT)
	var phase = PM.get_current_phase_instance()
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_TEST", "player": 1, "payload": {}})
	var out := {
		"to": str(TM.get_terrain_at_position(dest).get("id", "")),
		"climb": float(phase._get_vertical_climb_cost(start, dest, "U_TEST")),
		"penalty": float(phase._get_movement_terrain_penalty(start, dest, "U_TEST", false)),
		"charge": float(TM.calculate_charge_terrain_penalty(start, dest, false, kws)),
	}
	var r: Dictionary = phase.execute_action({"type": "STAGE_MODEL_MOVE", "actor_unit_id": "U_TEST",
		"player": 1, "payload": {"model_id": "m0", "dest": [dest.x, dest.y]}})
	out["staged"] = bool(r.get("success", false))
	out["errors"] = str(r.get("errors", r.get("error", "")))
	return out

func _run() -> void:
	print("\n=== test_terrain_area_no_climb_11e ===")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	TM = root.get_node("TerrainManager")
	PPI = float(root.get_node("Measurement").PX_PER_INCH)
	var prev_terrain = TM.terrain_features.duplicate(true)
	var prev_units = GS.state.units.duplicate(true)
	GameConstants.edition = 11
	TM.load_terrain_layout(LAYOUT)

	print("\n-- A. pieces: an area is not a surface; the feature at a point wins --")
	var a7 := _piece("area-large-7")
	var ruin := _piece("corner-ruin-balanced-right-13")
	_check("setup: area-large-7 is a tall dense AREA (re-derived by 7846f06)",
		str(a7.get("piece_class", "")) == "area" and str(a7.get("height_category", "")) == "tall", str(a7.get("height_category", "")))
	_check("get_height_inches(area) = 0", float(TM.get_height_inches(a7)) == 0.0)
	_check("get_height_inches(feature) unchanged (tall = 6\")", float(TM.get_height_inches(ruin)) == 6.0)
	_check("open ground of area-large-7 -> the area", str(TM.get_terrain_at_position(Vector2(32.0, 54.0) * PPI).get("id", "")) == "area-large-7")
	var in_ruin := Vector2(26.1, 50.5) * PPI
	var under: Array = TM.pieces_at_position(in_ruin).map(func(p): return str(p.get("id", "")))
	_check("inside the ruin within the area: both pieces are under the point", "area-large-7" in under and "corner-ruin-balanced-right-13" in under, str(under))
	_check("... and get_terrain_at_position returns the FEATURE", str(TM.get_terrain_at_position(in_ruin).get("id", "")) == "corner-ruin-balanced-right-13")

	print("\n-- B. moves into an area's open ground (no feature on the line) --")
	for kws in [["VEHICLE"], ["MONSTER"]]:
		for seg in [["area-large-7", Vector2(32.0, 58.0), Vector2(32.0, 54.0)],
				["area-large-8", Vector2(12.0, 2.0), Vector2(12.0, 6.0)],
				["area-large-25 (control, unchanged by 7846f06)", Vector2(12.5, 50.0), Vector2(12.5, 46.0)]]:
			var m := _move(kws, seg[1], seg[2])
			_check("%s into %s: no climb (was 6\")" % [kws[0], seg[0]], m.climb == 0.0, str(m))
			_check("... move penalty 2\" (the area's difficult ground only; was 8\")", absf(m.penalty - 2.0) < 0.01, str(m))
			_check("... the 4\" move (6\" of 10\") is accepted (was refused at 12\")", m.staged, str(m))
			_check("... a charge on the same line pays 2\" (was 8\")", absf(m.charge - 2.0) < 0.01, str(m))
	var inf := _move(["INFANTRY"], Vector2(32.0, 58.0), Vector2(32.0, 54.0))
	_check("INFANTRY into area-large-7: no climb, accepted", inf.climb == 0.0 and inf.staged, str(inf))

	print("\n-- C. a feature inside an area keeps its own climb --")
	# corner-short-15: LIGHT, tall ruin inside area-large-7 (13.06: all models
	# may move through light features). The climb now comes from the feature
	# itself, not from the area listed before it.
	var lf := _move(["VEHICLE"], Vector2(35.6, 46.5), Vector2(35.6, 48.7))
	_check("VEHICLE onto the light ruin corner-short-15: the feature is measured", lf.to == "corner-short-15", str(lf))
	_check("... and its 6\" climb is still charged", lf.climb == 6.0, str(lf))

	print("\n-- D. Death Trap still matches a kill inside a ruin within a trapped AREA --")
	var mm = root.get_node("MissionManager")
	var prev_alive = mm._alive_at_turn_start_11e.duplicate(true)
	var prev_primary = mm._primary_state_11e.duplicate(true)
	GS.state["meta"]["active_player"] = 1
	GS.state["units"] = {"U_FOE": {"id": "U_FOE", "owner": 2, "status": 2, "flags": {},
		"meta": {"name": "Foe", "keywords": ["INFANTRY"], "stats": {"move": 6}},
		"models": [{"id": "f0", "alive": false, "wounds": 1, "current_wounds": 0, "base_mm": 32,
			"base_type": "circular", "position": {"x": in_ruin.x, "y": in_ruin.y}}]}}
	mm._alive_at_turn_start_11e = {"1": {"U_FOE": true}}
	mm._primary_state_11e = {"1": {"trapped": ["area-large-7"]}}
	_check("a unit destroyed in the ruin inside trapped area-large-7 counts for Death Trap",
		mm._destroyed_enemy_in_terrain_11e(1, true))
	mm._primary_state_11e = {"1": {"trapped": ["area-large-8"]}}
	_check("... but not for a different trapped area", not mm._destroyed_enemy_in_terrain_11e(1, true))
	_check("... and it counts as a kill 'in terrain' (untrapped rule)", mm._destroyed_enemy_in_terrain_11e(1, false))
	mm._alive_at_turn_start_11e = prev_alive
	mm._primary_state_11e = prev_primary

	TM.terrain_features = prev_terrain
	GS.state.units = prev_units
	GameConstants.edition = 10
	_completed = true
