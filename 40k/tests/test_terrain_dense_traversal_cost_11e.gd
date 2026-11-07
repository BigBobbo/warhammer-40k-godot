extends SceneTree

# 13.06 TERRAIN AND MOVEMENT (Dense) on a Normal / Advance / Fall Back move:
#   ▪ "INFANTRY/BEASTS/SWARM/MOBILE models can move horizontally through dense
#     terrain features" and "INFANTRY/BEASTS/SWARM models can move vertically
#     through dense terrain features" — CROSSING a dense feature (or moving
#     within its terrain area) costs them nothing: no climb, no difficult
#     ground, exactly as on a charge.
#   ▪ MOVING VERTICALLY: "Add the distance moved vertically up, and the
#     distance moved vertically down, to any other distance that model has
#     moved" — a BEASTS / SWARM model that ENDS on a dense feature's surface
#     (a generator / gantry / catwalk top on the 11e layouts) pays the climb.
#   ▪ SETTING UP OR ENDING A MOVE: only INFANTRY/BEASTS/SWARM/FLY/MONSTER
#     models may end on a surface that is not ground level — a MOBILE-only
#     unit (a bike or walker with a rule-granted MOBILE) may cross a dense
#     feature but may not end on it.
#
# History. bd9392c made TerrainManager.get_terrain_at_position return the
# FEATURE at a point, so a BEASTS model stepping from its area's open ground
# onto a dense wall in the same area climbed the wall's 6" (+2" area difficult
# ground: a 2.9" Fenrisian Wolves move cost 10.9" and was refused). f8d9786
# then exempted every INFANTRY/BEASTS/SWARM/MOBILE unit from the climb onto
# ANY dense piece the move ends in (TerrainManager.unit_traverses_piece) — the
# horizontal-traversal rule applied to where a model ENDS. The 2026-11 review:
# on the 11e layouts a model whose centre ends inside a dense feature is never
# on ground level — it is on a platform top (the climb counts; MOBILE-only
# units may not end there) or through a Solid wall (13.06.01: illegal for every
# model; EA-66, still open) — and the free step onto a dense wall became a free
# 6" elevator for the NEXT move (wall -> tall light ruin: 0" climb, where open
# ground -> the same ruin paid 6"). Now:
#   ▪ the difficult-ground exemption keeps the 13.06 traversal predicate
#     (TerrainManager.unit_traverses_piece, shared with the charge cost);
#   ▪ the climb onto the piece a move ENDS in exempts only the legacy
#     can_move_through map (INFANTRY's ground-floor model), as before f8d9786;
#   ▪ TerrainManager.solid_terrain_endpoint_blocker_11e exempts
#     INFANTRY/BEASTS/SWARM only — MOBILE no longer.
#
# Known, unchanged and labelled below: the charge cost still exempts the dense
# piece a charge ends in (charge-side over-exemption); INFANTRY / BEASTS /
# SWARM may still end through a Solid wall (EA-66); light / exposed features
# still cost non-INFANTRY units their climb and difficult ground (rules audit
# TER-02 — not 13.06, which makes them free for all models).
#
# Drives the real MovementPhase: BEGIN_NORMAL_MOVE / BEGIN_ADVANCE /
# BEGIN_FALL_BACK + STAGE_MODEL_MOVE (the action the drag UI dispatches), and
# reads the per-model distance the phase books (raw + terrain penalty).
#
# Usage: godot --headless --path . -s tests/test_terrain_dense_traversal_cost_11e.gd

const PHASE_MOVEMENT := 7
const RECON := "take_and_hold_vs_reconnaissance_1"
const MIRROR := "take_and_hold_mirror_1"

const WOLVES := ["BEASTS", "FENRISIAN WOLVES", "IMPERIUM", "SPACE WOLVES"]
const SWARM := ["SWARM", "TYRANIDS", "RIPPER SWARMS"]
const WALKER := ["VEHICLE", "WALKER", "ORKS", "KILLA KANS"]
const BIKE := ["MOUNTED", "IMPERIUM", "ADEPTUS ASTARTES", "OUTRIDER SQUAD"]
const WALL_ERR := "Cannot end move overlapping a wall"

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

## One-model unit U_TEST (owner 1, M10, 32mm) at pos_px with `kws` and
## `flags`; with enemy_px set, an enemy INFANTRY model there (owner 2).
func _seed(kws: Array, pos_px: Vector2, flags: Dictionary = {}, enemy_px = null) -> void:
	var units := {
		"U_TEST": {"id": "U_TEST", "owner": 1, "status": 2, "flags": flags.duplicate(),
			"meta": {"name": "Probe", "keywords": kws.duplicate(), "abilities": [],
				"stats": {"move": 10, "toughness": 4, "save": 5, "wounds": 2, "leadership": 7, "objective_control": 1}},
			"models": [{"id": "m0", "alive": true, "wounds": 2, "current_wounds": 2,
				"base_mm": 32, "base_type": "circular", "position": {"x": pos_px.x, "y": pos_px.y}}]},
	}
	if enemy_px != null:
		units["U_FOE"] = {"id": "U_FOE", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Foe", "keywords": ["INFANTRY"], "abilities": [],
				"stats": {"move": 6, "toughness": 4, "save": 5, "wounds": 1, "leadership": 7, "objective_control": 1}},
			"models": [{"id": "f0", "alive": true, "wounds": 1, "current_wounds": 1,
				"base_mm": 32, "base_type": "circular", "position": {"x": enemy_px.x, "y": enemy_px.y}}]}
	GS.state["units"] = units
	GS.state["meta"]["active_player"] = 1
	GS.state["meta"]["phase"] = PHASE_MOVEMENT

## A move of mode `begin` ("BEGIN_NORMAL_MOVE" / "BEGIN_ADVANCE" /
## "BEGIN_FALL_BACK") from start_in to dest_in (board inches) through the real
## MovementPhase. Returns the costs the phase measured and books.
func _move(kws: Array, start_in: Vector2, dest_in: Vector2, begin: String = "BEGIN_NORMAL_MOVE",
		flags: Dictionary = {}, enemy_in = null) -> Dictionary:
	var start := start_in * PPI
	var dest := dest_in * PPI
	_seed(kws, start, flags, (enemy_in * PPI) if enemy_in != null else null)
	PM.transition_to_phase(PHASE_MOVEMENT)
	var phase = PM.get_current_phase_instance()
	var b: Dictionary = phase.execute_action({"type": begin, "actor_unit_id": "U_TEST", "player": 1, "payload": {}})
	if begin == "BEGIN_ADVANCE" and bool(phase.get("_awaiting_reroll_decision")):
		phase.execute_action({"type": "DECLINE_COMMAND_REROLL", "actor_unit_id": "U_TEST", "player": 1, "payload": {}})
	var md: Dictionary = phase.active_moves.get("U_TEST", {})
	var out := {
		"begun": bool(b.get("success", false)) and not md.is_empty(),
		"mode": str(md.get("mode", "")),
		"cap": float(md.get("move_cap_inches", 0.0)),
		"raw": start.distance_to(dest) / PPI,
		"to": str(TM.get_terrain_at_position(dest).get("id", "")),
		"climb": float(phase._get_vertical_climb_cost(start, dest, "U_TEST")),
		"penalty": float(phase._get_movement_terrain_penalty(start, dest, "U_TEST", false)),
		"charge": float(TM.calculate_charge_terrain_penalty(start, dest, false, phase._terrain_rule_keywords("U_TEST", md))),
	}
	var r: Dictionary = phase.execute_action({"type": "STAGE_MODEL_MOVE", "actor_unit_id": "U_TEST",
		"player": 1, "payload": {"model_id": "m0", "dest": [dest.x, dest.y]}})
	out["staged"] = bool(r.get("success", false))
	# model_distances is keyed "<unit id>:<model id>" (attached-unit models move with their bodyguard).
	out["booked"] = float(phase.active_moves.get("U_TEST", {}).get("model_distances", {}).get("U_TEST:m0", -1.0))
	out["errors"] = str(r.get("errors", r.get("error", "")))
	return out

func _run() -> void:
	print("\n=== test_terrain_dense_traversal_cost_11e ===")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	TM = root.get_node("TerrainManager")
	PPI = float(root.get_node("Measurement").PX_PER_INCH)
	var prev_terrain = TM.terrain_features.duplicate(true)
	var prev_units = GS.state.units.duplicate(true)
	GameConstants.edition = 11
	TM.load_terrain_layout(RECON)

	# recon_1: area-large-7 (25.5-37 x 48-55", dense, difficult ground) holds the
	# dense L-wall corner-ruin-balanced-right-13 (vertical arm x 25.84-26.34,
	# y 48.3-53.3; 5" / "tall" = 6") and the light ruin corner-short-15.
	# area-medium-9 (24-30 x 41-45", dense, difficult ground) holds the dense
	# generator-11 (25-29 x 41.5-44.5"; 3" / "medium" = 3.5"), a platform.
	print("\n-- setup --")
	var a7 := _piece("area-large-7")
	var wall := _piece("corner-ruin-balanced-right-13")
	var gen := _piece("generator-11")
	_check("setup: area-large-7 is a dense AREA with difficult ground",
		str(a7.get("piece_class", "")) == "area" and TM.category_of(a7) == "dense" and TM.has_terrain_trait(a7, "difficult_ground"))
	_check("setup: corner-ruin-balanced-right-13 is a dense FEATURE of area-large-7, 6\" to the climb model",
		str(wall.get("piece_class", "")) == "feature" and TM.category_of(wall) == "dense" \
			and str(wall.get("parent_area_id", "")) == "area-large-7" and float(TM.get_height_inches(wall)) == 6.0)
	_check("setup: generator-11 is a dense FEATURE (a platform) of area-medium-9, 3.5\" to the climb model",
		str(gen.get("piece_class", "")) == "feature" and TM.category_of(gen) == "dense" \
			and str(gen.get("parent_area_id", "")) == "area-medium-9" and float(TM.get_height_inches(gen)) == 3.5)
	var has_pred: bool = TM.has_method("unit_traverses_piece")
	_check("TerrainManager.unit_traverses_piece (the shared difficult-ground / charge traversal predicate) exists", has_pred)
	if has_pred:
		_check("unit_traverses_piece: BEASTS / SWARM / MOBILE / INFANTRY traverse the dense wall; VEHICLE does not",
			TM.unit_traverses_piece(["BEASTS"], wall) and TM.unit_traverses_piece(["SWARM"], wall) \
				and TM.unit_traverses_piece(["VEHICLE", "MOBILE"], wall) and TM.unit_traverses_piece(["INFANTRY"], wall) \
				and not TM.unit_traverses_piece(["VEHICLE"], wall))
		# TER-02 pin (engine model, NOT the 13.06 rule — "All models can move
		# horizontally and vertically through exposed and light terrain
		# features"): flip this when TER-02 lands.
		_check("TER-02 pin (current engine model, not 13.06): only INFANTRY traverses the LIGHT ruin corner-short-15",
			TM.unit_traverses_piece(["INFANTRY"], _piece("corner-short-15")) and not TM.unit_traverses_piece(["BEASTS"], _piece("corner-short-15")))

	var in_area := Vector2(29.0, 51.0)    # area-large-7 open ground
	var on_wall := Vector2(26.1, 51.0)    # centre in the wall's vertical arm (same area)
	var past_wall := Vector2(24.5, 51.0)  # open battlefield west of the wall and the area
	var gen_east := Vector2(31.5, 43.0)   # open battlefield east of area-medium-9
	var gen_top := Vector2(27.5, 43.0)    # on the generator's top
	var gen_west := Vector2(23.0, 43.0)   # open battlefield west of area-medium-9 (past the generator)

	print("\n-- A. BEASTS (Fenrisian Wolves, M10) CROSS the dense wall: horizontally through dense, free --")
	var n := _move(WOLVES, in_area, past_wall)
	_check("Normal move across the wall to its far side: the destination is open ground", n.to == "", str(n))
	_check("... no climb", n.climb == 0.0, str(n))
	_check("... no terrain penalty: the dense wall and the dense area are traversed (base 1b6765b: 2\" area difficult ground)",
		n.penalty == 0.0, str(n))
	_check("... staged and booked at its raw distance", n.staged and absf(n.booked - n.raw) < 0.01, str(n))
	_check("... a charge along the same line costs the same (0\")", n.charge == n.penalty, str(n))

	var adv := _move(WOLVES, in_area, past_wall, "BEGIN_ADVANCE")
	_check("Advance: begun (cap M + D6)", adv.begun and adv.mode == "ADVANCE" and adv.cap > 10.0, str(adv))
	_check("... across the wall: no climb, no penalty, staged and booked at the raw distance",
		adv.climb == 0.0 and adv.penalty == 0.0 and adv.staged and absf(adv.booked - adv.raw) < 0.01, str(adv))

	var fb := _move(WOLVES, in_area, past_wall, "BEGIN_FALL_BACK", {}, Vector2(30.6, 51.0))
	_check("Fall Back (engaged with a foe at 1.6\"): begun", fb.begun and fb.mode == "FALL_BACK", str(fb))
	_check("... across the wall: no climb, no penalty, staged and booked at the raw distance",
		fb.climb == 0.0 and fb.penalty == 0.0 and fb.staged and absf(fb.booked - fb.raw) < 0.01, str(fb))

	var xg := _move(WOLVES, gen_east, gen_west)
	_check("across the dense generator to its far side (vertically through dense): no climb, no penalty, staged at the raw 8.5\"",
		xg.climb == 0.0 and xg.penalty == 0.0 and xg.staged and absf(xg.booked - xg.raw) < 0.01, str(xg))

	print("\n-- B. BEASTS that END on a dense feature pay its climb (13.06 MOVING VERTICALLY) --")
	var top := _move(WOLVES, gen_east, gen_top)
	_check("onto the generator top: the destination is the generator", top.to == "generator-11", str(top))
	_check("... the 3.5\" climb counts (f8d9786 made it 0\")", top.climb == 3.5, str(top))
	_check("... and only the climb: the dense area's difficult ground is traversed", top.penalty == 3.5, str(top))
	_check("... staged (BEASTS may end on a surface that is not ground level), booked raw + 3.5\"",
		top.staged and absf(top.booked - (top.raw + 3.5)) < 0.01, str(top))
	# Known, unchanged: the charge cost exempts the dense piece a charge ENDS in.
	print("  INFO: charge cost along the same line %.1f\" (charge-side over-exemption, unchanged; the move pays %.1f\")" % [top.charge, top.penalty])
	var w := _move(WOLVES, in_area, on_wall)
	_check("onto the dense wall in its own area: the wall's 6\" climb counts again (f8d9786 made it 0\"; no free step)",
		w.to == "corner-ruin-balanced-right-13" and w.climb == 6.0 and w.penalty == 6.0, str(w))
	# The engine still accepts this end (8.9" <= 10"): 13.06.01 forbids a base
	# through a Solid wall for EVERY model — EA-66, open, not asserted here.

	print("\n-- C. SWARM --")
	var s := _move(SWARM, in_area, past_wall)
	_check("SWARM across the dense wall: no climb, no penalty, staged", s.climb == 0.0 and s.penalty == 0.0 and s.staged, str(s))
	var st := _move(SWARM, gen_east, gen_top)
	_check("SWARM onto the generator top: pays the 3.5\" climb, staged", st.climb == 3.5 and st.penalty == 3.5 and st.staged, str(st))

	print("\n-- D. MOBILE granted by a rule (flags.ork11e_mobile: STOMPING JUGGERNAUT, Skilled Riders, ...) --")
	var mob := _move(WALKER, in_area, past_wall, "BEGIN_NORMAL_MOVE", {"ork11e_mobile": true})
	_check("a MOBILE walker CROSSES the dense wall (13.06: horizontally through dense): no climb, no penalty, staged",
		mob.climb == 0.0 and mob.penalty == 0.0 and mob.staged, str(mob))
	_check("... the charge cost (ChargePhase adds the same MOBILE) agrees", mob.charge == mob.penalty, str(mob))
	var mob_top := _move(WALKER, gen_east, gen_top, "BEGIN_NORMAL_MOVE", {"ork11e_mobile": true})
	_check("a MOBILE walker may NOT end on the generator top (SETTING UP OR ENDING A MOVE: not INFANTRY/BEASTS/SWARM/FLY/MONSTER)",
		not mob_top.staged and WALL_ERR in mob_top.errors, str(mob_top))
	var mob_wall := _move(WALKER, in_area, on_wall, "BEGIN_NORMAL_MOVE", {"ork11e_mobile": true})
	_check("... nor in the dense wall (f8d9786 staged it for 2.9\")", not mob_wall.staged and WALL_ERR in mob_wall.errors, str(mob_wall))
	var bike_top := _move(BIKE, gen_east, gen_top, "BEGIN_NORMAL_MOVE", {"ork11e_mobile": true})
	_check("a MOUNTED bike with MOBILE (Skilled Riders) may NOT end on the generator top either",
		not bike_top.staged and WALL_ERR in bike_top.errors, str(bike_top))
	var bike_x := _move(BIKE, gen_east, gen_west, "BEGIN_NORMAL_MOVE", {"ork11e_mobile": true})
	_check("... but crosses the generator to its far side for its raw distance", bike_x.staged and absf(bike_x.booked - bike_x.raw) < 0.01, str(bike_x))
	_check("solid_terrain_endpoint_blocker_11e: MOBILE no longer exempts an end on a dense feature; INFANTRY / BEASTS / SWARM do",
		TM.solid_terrain_endpoint_blocker_11e({"position": gen_top * PPI, "base_mm": 32, "base_type": "circular"}, ["MOUNTED"], ["MOBILE"]) == "generator-11" \
			and TM.solid_terrain_endpoint_blocker_11e({"position": gen_top * PPI, "base_mm": 32, "base_type": "circular"}, ["BEASTS"]) == "" \
			and TM.solid_terrain_endpoint_blocker_11e({"position": gen_top * PPI, "base_mm": 32, "base_type": "circular"}, ["SWARM"]) == "" \
			and TM.solid_terrain_endpoint_blocker_11e({"position": gen_top * PPI, "base_mm": 32, "base_type": "circular"}, ["INFANTRY"]) == "")

	print("\n-- E. guards: what does not change --")
	var inf := _move(["INFANTRY"], in_area, on_wall)
	_check("INFANTRY onto the wall: no climb, no penalty, staged (the legacy ground-floor model, unchanged)",
		inf.climb == 0.0 and inf.penalty == 0.0 and inf.staged, str(inf))
	var inf_top := _move(["INFANTRY"], gen_east, gen_top)
	_check("INFANTRY onto the generator top: no climb (legacy model, unchanged)", inf_top.climb == 0.0 and inf_top.staged, str(inf_top))
	var veh := _move(WALKER, in_area, on_wall)
	_check("a walker WITHOUT MOBILE may not end in the dense wall (13.06 gate / endpoint, unchanged)", not veh.staged, str(veh))
	_check("... and still pays the wall's climb", veh.climb == 6.0, str(veh))
	var veh_x := _move(WALKER, in_area, past_wall)
	_check("... nor cross it (the 13.06 path gate: dense > 2\")", not veh_x.staged, str(veh_x))
	# corner-short-15: the LIGHT ruin inside area-large-7 (vertical arm x 36.04-36.54).
	var lf := _move(WOLVES, Vector2(34.0, 50.0), Vector2(36.3, 50.0))
	_check("TER-02 pin (current engine model, not 13.06): BEASTS onto the LIGHT ruin corner-short-15 pay its 6\" climb, as the charge cost",
		lf.to == "corner-short-15" and lf.climb == 6.0 and lf.charge >= 6.0, str(lf))
	var dg := _move(WOLVES, Vector2(32.0, 58.0), Vector2(32.0, 54.0))
	_check("BEASTS into the dense area's open ground: no difficult-ground penalty (as the charge cost)",
		dg.penalty == 0.0 and dg.charge == 0.0 and dg.staged, str(dg))

	print("\n-- F. the default layout (take_and_hold_mirror_1) --")
	TM.load_terrain_layout(MIRROR)
	# area-large-13 (23-30 x 42.49-53.99", dense) holds the dense L-wall
	# corner-ruin-left-19 (vertical arm x 29.56-30.06, y 42.76-45.76).
	var m1 := _move(WOLVES, Vector2(27.0, 45.0), Vector2(31.2, 45.0))
	_check("BEASTS from area-large-13's open ground ACROSS the dense wall corner-ruin-left-19: no climb, no penalty, staged at the raw 4.2\"",
		m1.climb == 0.0 and m1.penalty == 0.0 and m1.staged and absf(m1.booked - m1.raw) < 0.01, str(m1))
	var m2 := _move(WOLVES, Vector2(27.0, 46.0), Vector2(29.8, 45.0))
	_check("... ONTO that wall: the feature is measured and its 6\" climb counts",
		m2.to == "corner-ruin-left-19" and m2.climb == 6.0 and m2.penalty == 6.0, str(m2))
	# No free elevator (review of f8d9786): the climb a model pays to get onto a
	# dense feature is the same as stepping onto a feature of that height from
	# the ground. area-trapezoid-43 open ground -> the dense wall
	# corner-ruin-balanced-left-45 (vertical arm x 26.83-27.33), then -> the tall
	# LIGHT ruin corner-tiny-47 (vertical arm x 26.77-27.27, y 25.95-27.45).
	var a := _move(WOLVES, Vector2(24.02, 30.0), Vector2(27.08, 30.0))
	var b := _move(WOLVES, Vector2(27.08, 30.0), Vector2(27.02, 27.0))
	var c := _move(WOLVES, Vector2(24.02, 27.0), Vector2(27.02, 27.0))
	_check("setup: (a) ends in the dense wall, (b) and (c) in the light ruin",
		a.to == "corner-ruin-balanced-left-45" and b.to == "corner-tiny-47" and c.to == "corner-tiny-47", "%s | %s | %s" % [str(a), str(b), str(c)])
	_check("ground -> dense wall -> light ruin climbs exactly what ground -> light ruin climbs (6\"; f8d9786: 0\" + 0\")",
		absf((a.climb + b.climb) - c.climb) < 0.01 and c.climb == 6.0, "a %.1f + b %.1f vs c %.1f" % [a.climb, b.climb, c.climb])

	print("\n-- G. 10e keeps the legacy climb (13.06 dense traversal is an 11e rule) --")
	TM.load_terrain_layout(RECON)
	GameConstants.edition = 10
	var ten := _move(WOLVES, in_area, on_wall)
	_check("edition 10: BEASTS onto the wall pay the climb", ten.climb == 6.0, str(ten))
	GameConstants.edition = 11

	TM.terrain_features = prev_terrain
	GS.state.units = prev_units
	GameConstants.edition = 10
	_completed = true
