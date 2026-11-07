extends SceneTree

# 13.06 TERRAIN AND MOVEMENT (Dense): "INFANTRY/BEASTS/SWARM/MOBILE models can
# move horizontally through dense terrain features" and "INFANTRY/BEASTS/SWARM
# models can move vertically through dense terrain features". A dense feature
# is no climb for them, on any move: Normal, Advance, Fall Back or charge.
#
# Regression (cross-review of the Hidden follow-ups, bd9392c): the legacy climb
# model, MovementPhase._get_vertical_climb_cost, exempted only the units the
# per-piece can_move_through map names — INFANTRY. bd9392c made
# TerrainManager.get_terrain_at_position return the FEATURE at a point (the 11e
# layouts list each area before its features), so a BEASTS / SWARM model
# stepping from its terrain area's open ground onto a dense wall in the SAME
# area now climbed the wall's 6" (area 0" -> feature 6"); before, both ends
# read the area and the climb was 0. Fenrisian Wolves (M10) 2.9" onto the wall
# cost 2.9 + 6 + 2 = 10.9" and STAGE_MODEL_MOVE refused it. The charge cost
# (TerrainManager.calculate_charge_terrain_penalty) already let
# INFANTRY/BEASTS/SWARM/MOBILE through dense pieces for free
# (_passes_dense_feature_11e), so a charge and a move along the same line
# disagreed. MOBILE granted by a rule (STOMPING JUGGERNAUT's ork11e_mobile flag,
# the 24.35 SUPER-HEAVY WALKER gamble) was ignored by the move's costs too,
# though the 13.06 path gate honours it.
#
# Now TerrainManager.unit_traverses_piece (can_move_through OR 13.06 dense
# traversal) is the one predicate: the charge cost, the move's difficult-ground
# exemption (calculate_movement_terrain_penalty) and the move's climb
# (_get_vertical_climb_cost) all read it, with the move's terrain keywords
# (MovementPhase._terrain_rule_keywords: + rule-granted MOBILE).
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
	print("\n-- setup --")
	var a7 := _piece("area-large-7")
	var wall := _piece("corner-ruin-balanced-right-13")
	_check("setup: area-large-7 is a dense AREA with difficult ground",
		str(a7.get("piece_class", "")) == "area" and TM.category_of(a7) == "dense" and TM.has_terrain_trait(a7, "difficult_ground"))
	_check("setup: corner-ruin-balanced-right-13 is a dense FEATURE of area-large-7, 6\" to the climb model",
		str(wall.get("piece_class", "")) == "feature" and TM.category_of(wall) == "dense" \
			and str(wall.get("parent_area_id", "")) == "area-large-7" and float(TM.get_height_inches(wall)) == 6.0)
	var has_pred: bool = TM.has_method("unit_traverses_piece")
	_check("TerrainManager.unit_traverses_piece (the shared move / charge traversal predicate) exists", has_pred)
	if has_pred:
		_check("unit_traverses_piece: BEASTS / SWARM / MOBILE / INFANTRY traverse the dense wall; VEHICLE does not",
			TM.unit_traverses_piece(["BEASTS"], wall) and TM.unit_traverses_piece(["SWARM"], wall) \
				and TM.unit_traverses_piece(["VEHICLE", "MOBILE"], wall) and TM.unit_traverses_piece(["INFANTRY"], wall) \
				and not TM.unit_traverses_piece(["VEHICLE"], wall))
		_check("unit_traverses_piece: only INFANTRY traverses the LIGHT ruin corner-short-15 (13.06 dense rule only)",
			TM.unit_traverses_piece(["INFANTRY"], _piece("corner-short-15")) and not TM.unit_traverses_piece(["BEASTS"], _piece("corner-short-15")))

	var in_area := Vector2(29.0, 51.0)   # area-large-7 open ground
	var on_wall := Vector2(26.1, 51.0)   # centre in the wall's vertical arm (same area)
	var outside := Vector2(24.5, 51.0)   # open battlefield west of the area

	print("\n-- A. BEASTS (Fenrisian Wolves, M10): area open ground -> the dense wall in the same area --")
	var n := _move(WOLVES, in_area, on_wall)
	_check("Normal move: the destination is the wall feature", n.to == "corner-ruin-balanced-right-13", str(n))
	_check("... no climb (was 6\": area 0\" -> feature 6\")", n.climb == 0.0, str(n))
	_check("... no terrain penalty at all: the dense area and wall are traversed (was 8\")", n.penalty == 0.0, str(n))
	_check("... the 2.9\" move is staged (was refused: 10.9\" > 10\")", n.staged, str(n))
	_check("... and booked at its raw distance", absf(n.booked - n.raw) < 0.01, str(n))
	_check("... a charge along the same line costs the same (0\")", n.charge == n.penalty, str(n))

	var adv := _move(WOLVES, in_area, on_wall, "BEGIN_ADVANCE")
	_check("Advance: begun (cap M + D6)", adv.begun and adv.mode == "ADVANCE" and adv.cap > 10.0, str(adv))
	_check("... no climb, no penalty, staged and booked at the raw distance",
		adv.climb == 0.0 and adv.penalty == 0.0 and adv.staged and absf(adv.booked - adv.raw) < 0.01, str(adv))

	var fb := _move(WOLVES, in_area, on_wall, "BEGIN_FALL_BACK", {}, Vector2(30.6, 51.0))
	_check("Fall Back (engaged with a foe at 1.6\"): begun", fb.begun and fb.mode == "FALL_BACK", str(fb))
	_check("... no climb, no penalty, staged and booked at the raw distance",
		fb.climb == 0.0 and fb.penalty == 0.0 and fb.staged and absf(fb.booked - fb.raw) < 0.01, str(fb))

	var o := _move(WOLVES, outside, on_wall)
	_check("from outside the area onto the wall: no climb, no penalty (was 8\": 2\" area + 6\" climb)",
		o.climb == 0.0 and o.penalty == 0.0 and o.staged, str(o))
	_check("... the charge cost agrees", o.charge == o.penalty, str(o))

	print("\n-- B. SWARM --")
	var s := _move(SWARM, in_area, on_wall)
	_check("SWARM onto the dense wall from its area: no climb, no penalty, staged",
		s.climb == 0.0 and s.penalty == 0.0 and s.staged, str(s))

	print("\n-- C. MOBILE granted by a rule (STOMPING JUGGERNAUT: flags.ork11e_mobile) --")
	var mob := _move(WALKER, in_area, on_wall, "BEGIN_NORMAL_MOVE", {"ork11e_mobile": true})
	_check("a MOBILE walker onto the dense wall: no climb, no penalty, staged (13.06: horizontally through dense)",
		mob.climb == 0.0 and mob.penalty == 0.0 and mob.staged, str(mob))
	_check("... the charge cost (ChargePhase adds the same MOBILE) agrees", mob.charge == mob.penalty, str(mob))

	print("\n-- D. guards: what does not change --")
	var inf := _move(["INFANTRY"], in_area, on_wall)
	_check("INFANTRY onto the wall: no climb, no penalty, staged (unchanged)",
		inf.climb == 0.0 and inf.penalty == 0.0 and inf.staged, str(inf))
	var veh := _move(WALKER, in_area, on_wall)
	_check("a walker WITHOUT MOBILE may not end in the dense wall (13.06 gate / endpoint, unchanged)", not veh.staged, str(veh))
	_check("... and still pays the wall's climb", veh.climb == 6.0, str(veh))
	# corner-short-15: the LIGHT ruin inside area-large-7 (vertical arm x 36.04-36.54).
	var lf := _move(WOLVES, Vector2(34.0, 50.0), Vector2(36.3, 50.0))
	_check("BEASTS onto the LIGHT ruin corner-short-15: its 6\" climb is still charged (dense-only rule, as the charge cost)",
		lf.to == "corner-short-15" and lf.climb == 6.0 and lf.charge >= 6.0, str(lf))
	var dg := _move(WOLVES, Vector2(32.0, 58.0), Vector2(32.0, 54.0))
	_check("BEASTS into the dense area's open ground: no difficult-ground penalty (as the charge cost)",
		dg.penalty == 0.0 and dg.charge == 0.0 and dg.staged, str(dg))

	print("\n-- E. the default layout (take_and_hold_mirror_1): area-large-13 -> corner-ruin-left-19 --")
	TM.load_terrain_layout(MIRROR)
	var m1 := _move(WOLVES, Vector2(27.0, 46.0), Vector2(29.8, 45.0))
	_check("BEASTS from area-large-13's open ground onto the dense wall corner-ruin-left-19: the feature is measured",
		m1.to == "corner-ruin-left-19", str(m1))
	_check("... no climb, no penalty, the 2.97\" move staged (was refused: 10.97\" > 10\")",
		m1.climb == 0.0 and m1.penalty == 0.0 and m1.staged, str(m1))

	print("\n-- F. 10e keeps the legacy climb (13.06 dense traversal is an 11e rule) --")
	TM.load_terrain_layout(RECON)
	GameConstants.edition = 10
	var ten := _move(WOLVES, in_area, on_wall)
	_check("edition 10: BEASTS onto the wall still pay the climb", ten.climb == 6.0, str(ten))
	GameConstants.edition = 11

	TM.terrain_features = prev_terrain
	GS.state.units = prev_units
	GameConstants.edition = 10
	_completed = true
