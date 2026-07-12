extends SceneTree

# Stompa-on-walls fix (13.06 solid terrain vs VEHICLE/MONSTER movement).
#
# Regression suite for the bug where a Stompa (VEHICLE/TITANIC, 180mm base)
# walked through and parked on 5"-tall ruin walls on the converted 11e
# layouts (take_and_hold_mirror_1 etc.):
#   ▪ the 13.06 dense-terrain gate now runs on STAGE_MODEL_MOVE (the action
#     the drag UI and the AI dispatch), not just SET_MODEL_DEST;
#   ▪ the gate is shape-aware — the whole base is swept, so a wide base
#     cannot straddle a wall its centre line never crosses;
#   ▪ ending overlapped is refused via the keyword-aware endpoint rule
#     (model_overlaps_any_wall now also covers solid dense feature pieces);
#   ▪ piece_class "area" footprints are enterable (only "feature" walls are
#     solid), infantry remain exempt, and OA-28/29 / SUPER-HEAVY WALKER get
#     the 4" step-over;
#   ▪ models stranded inside walls by pre-fix saves can move OUT (escape
#     clause) but not stay;
#   ▪ charge paths are swept too (FLY chargers exempt at the caller).
#
# Usage: godot --headless --path . -s tests/test_solid_terrain_movement_11e.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, ("  --  " + detail) if detail != "" else ""])

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.2).timeout.connect(_run_tests)

const STOMPA_KW := ["ORKS", "STOMPA", "TITANIC", "TOWERING", "TRANSPORT", "VEHICLE", "WALKER"]

func _seed_unit(gs, keywords: Array, base_mm: int, pos_px: Vector2, move: int, abilities: Array, name: String) -> void:
	gs.state["units"] = {
		"U_TEST": {"id": "U_TEST", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": name, "keywords": keywords.duplicate(),
				"abilities": abilities.duplicate(),
				"stats": {"move": move, "toughness": 10, "save": 3, "wounds": 20, "objective_control": 5}},
			"models": [
				{"id": "m0", "alive": true, "wounds": 20, "current_wounds": 20,
				 "base_mm": base_mm, "base_type": "circular",
				 "position": {"x": pos_px.x, "y": pos_px.y}},
			]},
	}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = GameStateData.Phase.MOVEMENT

func _begin_move(pm, gs) -> Object:
	pm.transition_to_phase(GameStateData.Phase.MOVEMENT)
	var phase = pm.get_current_phase_instance()
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_TEST", "player": 1, "payload": {}})
	return phase

func _stage(phase, dest: Vector2) -> Dictionary:
	return phase._validate_stage_model_move({"actor_unit_id": "U_TEST",
		"payload": {"model_id": "m0", "dest": [dest.x, dest.y]}})

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_solid_terrain_movement_11e (Stompa-on-walls fix) ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var tm = root.get_node_or_null("TerrainManager")
	var meas = root.get_node_or_null("Measurement")
	if gs == null or pm == null or tm == null or meas == null:
		_check("autoloads reachable", false)
		_finish(); return

	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition
	var prev_terrain = tm.terrain_features.duplicate(true)
	GameConstants.edition = 11
	tm.load_terrain_layout("take_and_hold_mirror_1")
	var ppi: float = meas.PX_PER_INCH

	# Geometry (board inches): the L-shaped 5"-tall dense wall
	# corner-ruin-balanced-left-46 — vertical stroke x 26.83..27.33,
	# y 25.38..30.38 — inside enterable footprint area-trapezoid-44.
	var wall_id := "corner-ruin-balanced-left-46"
	var start := Vector2(32.0, 28.0) * ppi        # open ground, base fully clear
	var in_wall := Vector2(27.08, 28.0) * ppi     # centre inside the wall stroke
	var straddle := Vector2(28.6, 28.0) * ppi     # centre clear, 180mm base overlaps wall
	var stompa_abilities := ["Waaagh!", "Deadly Demise 2D6", "Stompin' Forward", "Waaagh! Effigy (Aura)", "TRANSPORT"]

	print("-- T1: STAGE_MODEL_MOVE gate — Stompa cannot cross the 5\" wall --")
	_seed_unit(gs, STOMPA_KW, 180, start, 10, stompa_abilities, "Stompa")
	var phase = _begin_move(pm, gs)
	var v1 = _stage(phase, in_wall)
	_check("crossing into the wall is INVALID", not v1.get("valid", true), str(v1))
	_check("refusal cites the 13.06 dense-terrain gate",
		not v1.get("valid", true) and str(v1.get("errors", [])).contains("13.06"), str(v1))
	_check("blockers name the wall feature", str(v1.get("errors", [])).contains(wall_id), str(v1))
	_check("the enterable area footprint is NOT a blocker",
		not str(v1.get("errors", [])).contains("area-trapezoid-44"), str(v1))
	var r1 = phase.execute_action({"type": "STAGE_MODEL_MOVE", "actor_unit_id": "U_TEST",
		"player": 1, "payload": {"model_id": "m0", "dest": [in_wall.x, in_wall.y]}})
	_check("STAGE_MODEL_MOVE action is rejected end-to-end", not r1.get("success", true), str(r1))

	print("\n-- T2: shape-aware sweep — base straddle blocked (centre line clear) --")
	var trav_center = tm.can_move_through_11e(STOMPA_KW, start, straddle)
	_check("centre-line-only test would have allowed it (the old blind spot)",
		trav_center.get("allowed", false), str(trav_center))
	var v2 = _stage(phase, straddle)
	_check("swept-base gate refuses the straddle destination", not v2.get("valid", true), str(v2))

	print("\n-- T3: escape clause — a model stranded IN a wall may move out --")
	_seed_unit(gs, STOMPA_KW, 180, in_wall, 10, stompa_abilities, "Stompa")
	phase = _begin_move(pm, gs)
	var v3 = _stage(phase, start)
	_check("moving from inside the wall to open ground is VALID", v3.get("valid", false), str(v3))

	print("\n-- T4: endpoint net — cannot END still overlapping the wall --")
	_seed_unit(gs, STOMPA_KW, 180, straddle, 10, stompa_abilities, "Stompa")
	phase = _begin_move(pm, gs)
	var v4 = _stage(phase, Vector2(28.2, 28.0) * ppi)  # short slide, still overlapping
	_check("ending overlapped is INVALID (endpoint rule)", not v4.get("valid", true), str(v4))
	_check("refusal is the wall-overlap endpoint error",
		str(v4.get("errors", [])).contains("overlapping a wall"), str(v4))

	print("\n-- T5: INFANTRY exemption — walk through and stand among walls --")
	_seed_unit(gs, ["ORKS", "INFANTRY"], 32, start, 10, [], "Boyz")
	phase = _begin_move(pm, gs)
	var v5 = _stage(phase, in_wall)
	_check("infantry may stage into the wall footprint", v5.get("valid", false), str(v5))

	print("\n-- T6: area footprints are enterable — vehicle through the gap --")
	_seed_unit(gs, ["ORKS", "VEHICLE"], 50, Vector2(21.5, 23.0) * ppi, 14, [], "Trukk")
	phase = _begin_move(pm, gs)
	var v6 = _stage(phase, Vector2(21.5, 27.5) * ppi)
	_check("50mm vehicle enters the trapezoid area between walls", v6.get("valid", false), str(v6))

	print("\n-- T7: 4\" step-over — Stompin' Forward crosses a 3\" generator, plain vehicle cannot --")
	# Start far enough that a 180mm base is fully clear of generator-38
	# (start at `start` would already overlap it, engaging the escape clause).
	var gen_start := Vector2(31.5, 30.5) * ppi
	_seed_unit(gs, STOMPA_KW, 180, gen_start, 12, stompa_abilities, "Stompa")  # M12: terrain penalties (+5.5") must not mask the gate verdict
	phase = _begin_move(pm, gs)
	var over_gen := Vector2(34.0, 25.5) * ppi  # inside generator-38 (dense, 3")
	var v7a = _stage(phase, over_gen)
	_check("Stompa (Stompin' Forward -> 4\" limit) may cross/stand on the 3\" generator",
		v7a.get("valid", false), str(v7a))
	_seed_unit(gs, ["ORKS", "VEHICLE"], 180, gen_start, 12, [], "Big Trukk")
	phase = _begin_move(pm, gs)
	var v7b = _stage(phase, over_gen)
	_check("plain VEHICLE (2\" limit) is blocked by the 3\" generator",
		not v7b.get("valid", true), str(v7b))
	_check("plain VEHICLE refusal cites 13.06 and the generator",
		str(v7b.get("errors", [])).contains("13.06") and str(v7b.get("errors", [])).contains("generator-38"), str(v7b))

	print("\n-- T8: keyword-aware endpoint predicate (model_overlaps_any_wall) --")
	var stompa_probe = {"position": in_wall, "base_mm": 180, "base_type": "circular"}
	_check("VEHICLE overlapping the wall -> true",
		meas.model_overlaps_any_wall(stompa_probe, STOMPA_KW) == true)
	_check("INFANTRY overlapping the wall -> false (exempt)",
		meas.model_overlaps_any_wall(stompa_probe, ["INFANTRY"]) == false)
	_check("layout still authors zero wall segments (solid features carry the rule)",
		prev_terrain != null)  # sanity anchor; segments counted below
	var seg_count := 0
	for piece in tm.terrain_features:
		seg_count += piece.get("walls", []).size()
	_check("zero authored wall segments on this layout", seg_count == 0, str(seg_count))

	print("\n-- T9: edition-10 sensitivity — solid-feature rule is inert --")
	GameConstants.edition = 10
	_seed_unit(gs, STOMPA_KW, 180, start, 10, stompa_abilities, "Stompa")
	phase = _begin_move(pm, gs)
	var v9 = _stage(phase, straddle)
	_check("e10: the straddle destination is allowed (pre-11e behaviour kept)",
		v9.get("valid", false), str(v9))
	GameConstants.edition = 11

	print("\n-- T10: charge path sweep (ChargePhase helper) --")
	_seed_unit(gs, STOMPA_KW, 180, start, 10, stompa_abilities, "Stompa")
	gs.state["meta"]["phase"] = GameStateData.Phase.CHARGE
	pm.transition_to_phase(GameStateData.Phase.CHARGE)
	var charge_phase = pm.get_current_phase_instance()
	var paths = {"m0": [[start.x, start.y], [in_wall.x, in_wall.y]]}
	var c1 = charge_phase._validate_no_solid_terrain_on_paths("U_TEST", paths, STOMPA_KW)
	_check("Stompa charge path through the wall is INVALID", not c1.get("valid", true), str(c1))
	var c2 = charge_phase._validate_no_solid_terrain_on_paths("U_TEST", paths, ["INFANTRY"])
	_check("infantry charge path through the wall is VALID", c2.get("valid", false), str(c2))
	var c3 = charge_phase._validate_no_wall_overlaps("U_TEST", paths)
	_check("charge endpoint overlapping the wall is INVALID (keyword-aware)",
		not c3.get("valid", true), str(c3))

	print("\n-- T11: AI screening predicates --")
	_check("AI _dest_overlaps_wall flags a wall destination for the Stompa",
		AIDecisionMaker._dest_overlaps_wall(in_wall, 180, "circular", {}, STOMPA_KW) == true)
	_check("AI _dest_overlaps_wall clears it for infantry",
		AIDecisionMaker._dest_overlaps_wall(in_wall, 32, "circular", {}, ["INFANTRY"]) == false)
	_check("AI _path_blocked_by_solid_terrain flags the crossing",
		AIDecisionMaker._path_blocked_by_solid_terrain(start, in_wall, 180, "circular", {}, STOMPA_KW) == true)
	_check("AI path check clears open ground",
		AIDecisionMaker._path_blocked_by_solid_terrain(start, start + Vector2(2.0 * ppi, 0), 180, "circular", {}, STOMPA_KW) == false)

	gs.state = prev_state
	GameConstants.edition = prev_edition
	tm.terrain_features = prev_terrain
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
