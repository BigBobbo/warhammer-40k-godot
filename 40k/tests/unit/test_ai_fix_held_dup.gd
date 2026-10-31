extends SceneTree

# FIX-HELD-DUP (critic cluster "held_dup", 2026-10-30): the AI sent units to,
# and deep-struck units onto, objectives its side already held.
#
# Root cause 1 — the AI read the level of control with its own approximation:
# a model counted only when its CENTRE was within 3.79" of the marker point.
# 11e 14.01 terrain-hosted objectives (the areas named in source_pieces) are
# the hosting AREA: a model counts as soon as its base overlaps the area
# (MissionManager.model_in_objective_range, what objective control scores
# with). Prosecutors standing on the home ruin 4-5" from the marker held it,
# but the plan read "uncontrolled" and sent a Custodian Guard squad to
# "capture" it (s7412 r1; s7422 r1 moved the squad already on it), and an Allarus
# squad that had just deep-struck onto obj_nml_2's ruin left it "uncontrolled"
# with "needs 2 more OC" (s7421 r2).
#
# Root cause 2 — reserve arrival spots were ranked by the distance to the
# nearest objective of ANY state, so a deep striker landed beside a home
# objective held with OC 17-20 and no enemy near (s7411 r2, s7406 r2). Spots
# now aim at objectives the movement plan's need ledger still wants OC at.
#
# Guard: a held objective the enemy can out-OC next move still needs OC, so it
# is still reinforced (real reinforcement is not stopped).
#
# Run with: godot --headless --path . -s tests/unit/test_ai_fix_held_dup.gd
# (runs once the scene tree is up: the fix reads MissionManager/TerrainManager)

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const MOVABLE := ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]
const PX := 40.0  # pixels per inch
# Home marker on the deep-strike grid (30 + 160k px), so on the old ranking a
# spot right on it (distance 0) beats any spot near the open objective.
const HOME := Vector2(830, 350)
const FAR := Vector2(880, 1200)
# MERGE (main ADV-ODDS-1): the threatened-home test puts obj_far 4" further
# south. At ~12" MOVER's 83% Advance onto it (ADV-ODDS-1 prices the roll)
# outscored reinforcing the threatened home; at ~16" no Advance reaches it this
# turn, so that test again isolates FIX-HELD-DUP's need.
const FAR_THREAT := Vector2(880, 1360)
const ENEMY_POS := Vector2(880, 2200)

var _pass_count: int = 0
var _fail_count: int = 0
var _ran := false
var AIDM = null

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
	print("\n=== FIX-HELD-DUP: held objectives read as held; no landing beside them ===\n")
	var mm = root.get_node_or_null("MissionManager")
	var tm = root.get_node_or_null("TerrainManager")
	_assert(mm != null and tm != null, "MissionManager / TerrainManager autoloads present")
	if mm == null or tm == null:
		print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
		quit(1)
		return
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	var prev_terrain = tm.terrain_features.duplicate(true)
	# The home objective's hosting area: an 11.5" x 7" ruin centred on the
	# marker (the official layouts' "area-large").
	tm.terrain_features = [{"id": "area_home", "piece_class": "area", "type": "ruins",
		"height_category": "tall", "polygon": PackedVector2Array([
			HOME + Vector2(-230, -140), HOME + Vector2(230, -140),
			HOME + Vector2(230, 140), HOME + Vector2(-230, 140)])}]
	# Loaded at run time so the AI script compiles after the autoloads exist.
	AIDM = load(AI_PATH)

	test_area_holder_reads_held()
	test_mover_not_sent_to_held_objective()
	test_threatened_held_objective_still_reinforced()
	test_param_zero_restores_old_read()
	test_deep_strike_spot_skips_held_objective()

	tm.terrain_features = prev_terrain
	GameConstants.edition = prev_edition
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

# --- fixtures ---------------------------------------------------------------

func _snapshot(battle_round: int = 1, far: Vector2 = FAR) -> Dictionary:
	var objs = [
		{"id": "obj_home_1", "position": HOME, "zone": "player1", "source_pieces": ["area_home"]},
		{"id": "obj_far", "position": far, "zone": "no_mans_land"},
	]
	return {"battle_round": battle_round, "meta": {"battle_round": battle_round},
		"board": {"objectives": objs, "terrain_features": []}, "units": {}}

func _add_unit(snap: Dictionary, uid: String, owner: int, positions: Array, oc: int,
		status: int = 2, base_mm: int = 32) -> Dictionary:  # 2 = UnitStatus.DEPLOYED
	var models = []
	for i in range(positions.size()):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": base_mm,
			"base_type": "circular", "base_dimensions": {}, "position": positions[i],
			"wounds": 3, "current_wounds": 3})
	var u = {"id": uid, "owner": owner, "status": status,
		"meta": {"name": uid, "points": 150, "stats": {"move": 6, "toughness": 6, "save": 2,
			"wounds": 3, "leadership": 6, "objective_control": oc},
			"keywords": ["INFANTRY"], "weapons": []},
		"models": models, "flags": {}}
	snap.units[uid] = u
	return u

## Our 4 x OC2 squad standing on the home ruin, 4-5.4" from the marker: every
## base overlaps the area, no centre is within 3.79" of the marker point.
func _area_holder_positions() -> Array:
	return [HOME + Vector2(165, 0), HOME + Vector2(190, 30), HOME + Vector2(215, 0), HOME + Vector2(190, -30)]

func _board(with_threat: bool, far: Vector2 = FAR) -> Dictionary:
	AIDM._primary_awareness_p1 = {}
	AIDM._secondary_awareness_p1 = {}
	var snap = _snapshot(1, far)
	_add_unit(snap, "HOLDER", 1, _area_holder_positions(), 2)
	# 3 x OC3 squad 9" from the home marker (there this turn), ~12" from obj_far.
	_add_unit(snap, "MOVER", 1, [HOME + Vector2(-50, 360), HOME + Vector2(0, 360), HOME + Vector2(50, 360)], 3)
	_add_unit(snap, "ENEMY_FAR", 2, [ENEMY_POS, ENEMY_POS + Vector2(50, 0)], 2)
	if with_threat:
		# 5 x OC3 enemy squad ~9.5" from the home marker, off the ruin: one
		# move (M6 + 2") puts it in range with OC 15 against our 8.
		var t := HOME + Vector2(-380, 0) + Vector2(0, 140)
		_add_unit(snap, "ENEMY_NEAR", 2, [t, t + Vector2(0, 40), t + Vector2(0, -40), t + Vector2(0, 80), t + Vector2(-40, 0)], 3)
	return snap

func _evals(snap: Dictionary) -> Array:
	var friendly = AIDM._get_units_for_player(snap, 1)
	var enemies = AIDM._get_enemy_units(snap, 1)
	return AIDM._evaluate_all_objectives(snap, AIDM._get_objectives(snap), 1, enemies, friendly, 1)

func _eval_of(evals: Array, oid: String) -> Dictionary:
	for ev in evals:
		if str(ev.get("id", "")) == oid:
			return ev
	return {}

func _plan(snap: Dictionary) -> Dictionary:
	var friendly = AIDM._get_units_for_player(snap, 1)
	var enemies = AIDM._get_enemy_units(snap, 1)
	var objectives = AIDM._get_objectives(snap)
	var evals = AIDM._evaluate_all_objectives(snap, objectives, 1, enemies, friendly, 1)
	# HOLDER already moved this phase: only MOVER is movable.
	return AIDM._assign_units_to_objectives(snap, {"MOVER": MOVABLE}, evals, objectives, enemies, friendly, 1, 1)

# --- tests --------------------------------------------------------------------

func test_area_holder_reads_held() -> void:
	print("\n--- our squad on the home ruin, 4-5\" from the marker ---")
	var mm = root.get_node("MissionManager")
	var snap = _board(false)
	var loc = mm.get_level_of_control(snap.board.objectives[0], snap.units)
	_assert(int(loc[1]) == 8, "MissionManager: our level of control on the ruin is 4 x OC2 = 8 (%s)" % str(loc))
	var ev = _eval_of(_evals(snap), "obj_home_1")
	print("  obj_home_1: state=%s friendly_oc=%s" % [ev.get("state"), ev.get("friendly_oc")])
	_assert(int(ev.get("friendly_oc", -1)) == 8, "the AI reads the same level of control (friendly_oc %s)" % str(ev.get("friendly_oc")))
	_assert(str(ev.get("state", "")) == "held_safe", "so the objective is held, not uncontrolled (%s)" % str(ev.get("state")))

func test_mover_not_sent_to_held_objective() -> void:
	print("\n--- no enemy near: the free squad goes where OC is needed ---")
	var plan = _plan(_board(false))
	var a: Dictionary = plan.get("MOVER", {})
	print("  MOVER: %s %s (%s)" % [a.get("action", ""), a.get("objective_id", ""), str(a.get("reason", "")).substr(0, 100)])
	_assert(str(a.get("objective_id", "")) != "obj_home_1", "the free squad is not sent to the home objective we already hold")
	_assert(str(a.get("objective_id", "")) == "obj_far", "it takes the open objective instead (%s)" % str(a.get("objective_id", "")))

func test_threatened_held_objective_still_reinforced() -> void:
	print("\n--- an enemy squad (OC 15) one move from our held home (OC 8) ---")
	var snap = _board(true, FAR_THREAT)
	var ev = _eval_of(_evals(snap), "obj_home_1")
	var friendly = AIDM._get_units_for_player(snap, 1)
	var needs = AIDM._initial_objective_oc_needs(_evals(snap), friendly)
	print("  obj_home_1: state=%s friendly_oc=%s projected=%s need=%s" % [ev.get("state"), ev.get("friendly_oc"), ev.get("projected_enemy_oc"), needs.get("obj_home_1")])
	_assert(int(needs.get("obj_home_1", 0)) > 0, "the threatened held objective still needs OC")
	var plan = _plan(snap)
	var a: Dictionary = plan.get("MOVER", {})
	print("  MOVER: %s %s (%s)" % [a.get("action", ""), a.get("objective_id", ""), str(a.get("reason", "")).substr(0, 100)])
	_assert(str(a.get("objective_id", "")) == "obj_home_1", "so the free squad reinforces it (%s)" % str(a.get("objective_id", "")))

func test_param_zero_restores_old_read() -> void:
	print("\n--- FIX_HELD_DUP = 0: the centre-distance read is back ---")
	AIDM._config_overrides["FIX_HELD_DUP"] = 0.0
	var ev = _eval_of(_evals(_board(false)), "obj_home_1")
	var plan = _plan(_board(false))
	AIDM._config_overrides.erase("FIX_HELD_DUP")
	print("  obj_home_1: state=%s friendly_oc=%s; MOVER -> %s" % [ev.get("state"), ev.get("friendly_oc"), plan.get("MOVER", {}).get("objective_id", "")])
	_assert(int(ev.get("friendly_oc", -1)) == 0 and str(ev.get("state", "")) == "uncontrolled",
		"off: the squad on the ruin is not counted (the old read)")
	_assert(str(plan.get("MOVER", {}).get("objective_id", "")) == "obj_home_1", "off: the free squad is sent to the home objective (old plan)")

func test_deep_strike_spot_skips_held_objective() -> void:
	print("\n--- deep strike: home held (OC 8 on the marker), obj_far open ---")
	AIDM._primary_awareness_p1 = {}
	AIDM._secondary_awareness_p1 = {}
	var snap = _snapshot(2)
	# Holder ON the marker, so the old read sees the hold too — this isolates
	# the spot ranking.
	_add_unit(snap, "HOLDER", 1, [HOME + Vector2(-60, 0), HOME + Vector2(-20, 40), HOME + Vector2(20, -40), HOME + Vector2(60, 0)], 2)
	_add_unit(snap, "ENEMY_FAR", 2, [ENEMY_POS, ENEMY_POS + Vector2(50, 0)], 2)
	var ds = _add_unit(snap, "DS", 1, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], 3, 7, 40)  # 7 = UnitStatus.IN_RESERVES
	ds["reserve_type"] = "deep_strike"
	var enemies = AIDM._get_enemy_units(snap, 1)
	var objectives = AIDM._get_objectives(snap)
	var ev = _eval_of(AIDM._evaluate_all_objectives(snap, objectives, 1, enemies, AIDM._get_units_for_player(snap, 1), 2), "obj_home_1")
	print("  obj_home_1: state=%s friendly_oc=%s" % [ev.get("state"), ev.get("friendly_oc")])
	_assert(str(ev.get("state", "")) == "held_safe", "home is held with no enemy near (%s)" % str(ev.get("state")))
	var enemy_models = AIDM._get_enemy_model_positions_from_snapshot(snap, 1)
	var spots: Array = AIDM._compute_reinforcement_positions(ds, "DS", "deep_strike", snap, 1, objectives, enemies, enemy_models, 2)
	_assert(not spots.is_empty(), "deep strike spots exist (%d)" % spots.size())
	if spots.is_empty():
		return
	var best: Vector2 = spots[0]
	var d_home = best.distance_to(HOME) / PX
	var d_far = best.distance_to(FAR) / PX
	print("  best spot (%.1f\", %.1f\"): %.1f\" from obj_home_1, %.1f\" from obj_far" % [best.x / PX, best.y / PX, d_home, d_far])
	_assert(d_far < d_home, "the best spot is by the open objective, not beside the one we hold")
	_assert(d_far <= 6.0, "and within 6\" of it (%.1f\")" % d_far)
