extends SceneTree

# P0.2 rules distances: the AI's Scout and reserve-arrival stand-offs against
# the REAL engine validators, at editions 11 and 10.
#
#   11e 24.32 SCOUT MOVE, AFTER MOVING: "more than 8\" horizontally from all
#   enemy units" (10e: 9"). 20.04 INGRESS MOVE / 24.09 DEEP STRIKE: set up
#   "more than 8\" horizontally from all enemy units" (10e: 9").
#
# Every AI destination here is fed to the engine: ScoutPhase's
# SET_SCOUT_MODEL_DEST + CONFIRM_SCOUT_MOVE validators, IngressMove.
# validate_setup and MovementPhase._validate_place_reinforcement — not to an
# AI-side mirror. Includes the mixed-base regression from the P0.2 review
# (one 32mm model + one 60mm oval, base_dimensions length 35.5 / width 60):
# measured by models[0]'s base, the AI put the larger base inside the
# stand-off once the 1" of 9" slack was gone.
#
# Run: godot --headless --script tests/unit/test_ai_rules_distances_11e.gd

const PPI := 40.0
const R32 := (32.0 / 2.0) / 25.4   # 32mm base radius, inches
const R60 := (60.0 / 2.0) / 25.4   # 60mm base_mm radius (the engine's circular approximation), inches

var passed := 0
var failed := 0
var gs = null
var tm = null
var _saved_units = null
var _saved_meta = null
var _saved_terrain = null

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

# -- fixtures ---------------------------------------------------------------

func _model(mid: String, pos, base_mm: int, base_type: String = "circular", dims: Dictionary = {}) -> Dictionary:
	return {"id": mid, "alive": true, "base_mm": base_mm, "base_type": base_type, "base_dimensions": dims,
		"position": pos, "wounds": 2, "current_wounds": 2}

func _unit(uid: String, owner: int, status: int, models: Array, abilities: Array = [], reserve_type: String = "") -> Dictionary:
	var u := {"id": uid, "owner": owner, "status": status,
		"meta": {"name": uid, "points": 100,
			"stats": {"move": 6, "toughness": 4, "save": 3, "wounds": 2, "objective_control": 2},
			"keywords": ["INFANTRY"], "abilities": abilities,
			"weapons": [{"type": "melee", "name": "cc", "range": "Melee", "attacks": "3", "skill": "3",
				"strength": "4", "ap": "0", "damage": "1"}]},
		"models": models, "flags": {}}
	if reserve_type != "":
		u["reserve_type"] = reserve_type
	return u

func _snap(objectives: Array, battle_round: int = 1) -> Dictionary:
	var objs := []
	var k := 0
	for o in objectives:
		k += 1
		objs.append({"id": "obj_%d" % k, "position": o, "zone": "no_mans_land"})
	return {"battle_round": battle_round, "meta": {"battle_round": battle_round, "active_player": 2},
		"board": {"objectives": objs, "terrain_features": [], "deployment_zones": []}, "units": {}}

func _scout_abilities() -> Array:
	return [{"name": "Scouts 6\"", "type": "Core", "value": 6}]

## Copy the snapshot's units into the LIVE GameState (positions as {x, y}),
## so the engine validators see exactly what the AI saw.
func _load_units_into_gs(snap: Dictionary) -> void:
	var units := {}
	for uid in snap.units:
		var u: Dictionary = snap.units[uid].duplicate(true)
		for m in u.models:
			if m.position is Vector2:
				m.position = {"x": m.position.x, "y": m.position.y}
		units[uid] = u
	gs.state["units"] = units

## Stage every AI destination through the REAL ScoutPhase: each
## SET_SCOUT_MODEL_DEST validated (per-model stand-off, distance cap, overlap)
## and processed, then CONFIRM_SCOUT_MOVE validated (stand-off again, overlap,
## coherency). "" = the engine accepts the whole move, else the first error.
func _engine_scout_verdict(snap: Dictionary, uid: String, dests: Dictionary, scout_in: float) -> String:
	_load_units_into_gs(snap)
	var sp = load("res://phases/ScoutPhase.gd").new()
	var orig := {}
	for m in gs.state.units[uid].models:
		orig[m.id] = m.position
	sp.active_scout_moves = {uid: {"scout_distance": scout_in, "staged_positions": {}, "original_positions": orig}}
	var err := ""
	for mid in dests:
		var p = dests[mid]
		var act := {"type": "SET_SCOUT_MODEL_DEST", "unit_id": uid, "model_id": mid,
			"destination": {"x": float(p[0]), "y": float(p[1])}}
		var r: Dictionary = sp._validate_set_scout_model_dest(act)
		if not r.valid:
			err = "SET %s: %s" % [mid, str(r.errors)]
			break
		sp._process_set_scout_model_dest(act)
	if err == "":
		var c: Dictionary = sp._validate_confirm_scout_move({"type": "CONFIRM_SCOUT_MOVE", "unit_id": uid})
		if not c.valid:
			err = "CONFIRM: %s" % str(c.errors)
	sp.free()
	return err

## Smallest per-model edge-to-edge gap (inches) from the destinations to any
## enemy model, each base measured with its own base_mm radius (as the engine does).
func _min_edge(unit: Dictionary, dests: Dictionary, enemies: Dictionary) -> float:
	var radius_by_id := {}
	for m in unit.models:
		radius_by_id[m.id] = (m.base_mm / 2.0) / 25.4
	var best := INF
	for mid in dests:
		var v := Vector2(float(dests[mid][0]), float(dests[mid][1]))
		for eid in enemies:
			for em in enemies[eid].models:
				var ep: Vector2 = em.position if em.position is Vector2 else Vector2(em.position.x, em.position.y)
				best = minf(best, v.distance_to(ep) / PPI - radius_by_id[mid] - (em.base_mm / 2.0) / 25.4)
	return best

# -- F1: Scout stand-off ------------------------------------------------------

func _test_scout_fraction_uses_8in_band(ed: int) -> void:
	print("\n-- F1 scout: fraction ladder uses the 8-9\" band at 11e (edition %d) --" % ed)
	var snap := _snap([Vector2(880, 1200)])
	snap.units["scout_1"] = _unit("scout_1", 2, GameStateData.UnitStatus.DEPLOYED,
		[_model("m1", Vector2(880, 1700), 32), _model("m2", Vector2(940, 1700), 32)], _scout_abilities())
	snap.units["enemy_1"] = _unit("enemy_1", 1, GameStateData.UnitStatus.DEPLOYED,
		[_model("e1", Vector2(880, 1200), 32), _model("e2", Vector2(940, 1200), 32)])
	_load_units_into_gs(snap)
	var unit: Dictionary = snap.units["scout_1"]
	var enemies := AIDecisionMaker._get_enemy_units(snap, 2)
	var dests: Dictionary = AIDecisionMaker._compute_scout_movement(unit, "scout_1", Vector2(880, 1200), 6.0, snap, enemies)
	_check("ed %d: AI found a scout move" % ed, not dests.is_empty())
	if dests.is_empty():
		return
	var y := float(dests["m1"][1])
	var edge := _min_edge(unit, dests, enemies)
	print("    m1 -> y=%.1f, min edge to enemy %.2f\"" % [y, edge])
	if ed >= 11:
		_check("ed 11: the 50% move (m1 y=1580 +-1) the old hard-coded 9\" refused", absf(y - 1580.0) <= 1.0, "y=%.1f" % y)
		_check("ed 11: ends in the 8-9\" band (8.0 <= %.2f < 9.0)" % edge, edge >= 8.0 and edge < 9.0)
	else:
		_check("ed 10: unchanged 25% move (m1 y=1640 +-1)", absf(y - 1640.0) <= 1.0, "y=%.1f" % y)
		_check("ed 10: ends >= 9\" (%.2f)" % edge, edge >= 9.0)
	var v := _engine_scout_verdict(snap, "scout_1", dests, 6.0)
	_check("ed %d: the REAL ScoutPhase accepts every staged model and the confirm" % ed, v == "", v)

func _test_scout_skip_becomes_move(ed: int) -> void:
	print("\n-- F1 scout: SKIP becomes a legal move at 11e (edition %d) --" % ed)
	var snap := _snap([Vector2(880, 1100)])
	snap.units["scout_1"] = _unit("scout_1", 2, GameStateData.UnitStatus.DEPLOYED,
		[_model("m1", Vector2(880, 1640), 32), _model("m2", Vector2(940, 1640), 32)], _scout_abilities())
	snap.units["enemy_1"] = _unit("enemy_1", 1, GameStateData.UnitStatus.DEPLOYED,
		[_model("e1", Vector2(880, 1200), 32), _model("e2", Vector2(940, 1200), 32)])
	_load_units_into_gs(snap)
	var avail := [{"type": "BEGIN_SCOUT_MOVE", "unit_id": "scout_1"}, {"type": "SKIP_SCOUT_MOVE", "unit_id": "scout_1"}]
	var dec: Dictionary = AIDecisionMaker._decide_scout(snap, avail, 2)
	print("    decision: %s | %s" % [str(dec.get("type", "")), str(dec.get("_ai_description", ""))])
	if ed >= 11:
		_check("ed 11: BEGIN_SCOUT_MOVE (was SKIP 'no valid path')", dec.get("type", "") == "BEGIN_SCOUT_MOVE", str(dec.get("type", "")))
		var dests: Dictionary = dec.get("_ai_scout_destinations", {})
		if not dests.is_empty():
			_check("ed 11: m1 ends at y=1580 +-1 (8.24\")", absf(float(dests["m1"][1]) - 1580.0) <= 1.0, str(dests["m1"]))
			var v := _engine_scout_verdict(snap, "scout_1", dests, 6.0)
			_check("ed 11: the REAL ScoutPhase accepts the move", v == "", v)
	else:
		_check("ed 10: SKIP_SCOUT_MOVE (no legal end beyond 9\")", dec.get("type", "") == "SKIP_SCOUT_MOVE", str(dec.get("type", "")))

func _mixed_scout_snap(start_y: float) -> Dictionary:
	# Wolf Scouts shape: a 32mm model first, then a 60mm oval (35.5 x 60).
	var snap := _snap([Vector2(930, 1200)])
	snap.units["ws"] = _unit("ws", 2, GameStateData.UnitStatus.DEPLOYED,
		[_model("m1", Vector2(880, start_y), 32), _model("m2", Vector2(980, start_y), 60, "oval", {"length": 35.5, "width": 60})],
		_scout_abilities())
	snap.units["en"] = _unit("en", 1, GameStateData.UnitStatus.DEPLOYED,
		[_model("e1", Vector2(880, 1200), 32), _model("e2", Vector2(980, 1200), 32)])
	return snap

func _test_mixed_base_scout(ed: int) -> void:
	print("\n-- F1 scout: mixed bases, 32mm first + 60mm oval (edition %d) --" % ed)
	var standoff := GameConstants.scout_min_enemy_distance_inches()
	for start_y in [1700.0, 1640.0]:
		var snap := _mixed_scout_snap(start_y)
		_load_units_into_gs(snap)
		var unit: Dictionary = snap.units["ws"]
		var enemies := AIDecisionMaker._get_enemy_units(snap, 2)
		var dests: Dictionary = AIDecisionMaker._compute_scout_movement(unit, "ws", Vector2(930, 1200), 6.0, snap, enemies)
		if dests.is_empty():
			print("    start y=%.0f: AI skips (no legal fraction)" % start_y)
			_check("ed %d start y=%.0f: a skip is legal (expected: no fraction keeps the 60mm oval beyond %.0f\")" % [ed, start_y, standoff],
				start_y == 1640.0, "the AI skipped from y=1700, where the 25% move is legal")
			continue
		var edge := _min_edge(unit, dests, enemies)
		print("    start y=%.0f: m1 y=%.1f m2 y=%.1f, per-model min edge %.2f\"" % [start_y, float(dests["m1"][1]), float(dests["m2"][1]), edge])
		_check("ed %d start y=%.0f: every model (own base) ends beyond %.0f\" (%.2f)" % [ed, start_y, standoff, edge], edge >= standoff)
		var v := _engine_scout_verdict(snap, "ws", dests, 6.0)
		_check("ed %d start y=%.0f: the REAL ScoutPhase accepts every staged model and the confirm" % [ed, start_y], v == "", v)
		if start_y == 1700.0:
			_check("ed %d start y=1700: the 25%% move (y=1640 +-1); the 50%% move puts the oval 7.7\" away" % ed,
				absf(float(dests["m1"][1]) - 1640.0) <= 1.0, str(dests))

func _test_first_model_larger_scout(ed: int) -> void:
	# models[0] is the LARGER base: the engine's confirm used to measure every
	# staged model with models[0]'s radius and so rejected the small model's
	# legal 8-9" end (the AI now measures each model with its own base).
	print("\n-- F1 scout: models[0] is the larger base (edition %d) --" % ed)
	var snap := _snap([Vector2(880, 1200)])
	snap.units["mx"] = _unit("mx", 2, GameStateData.UnitStatus.DEPLOYED,
		[_model("m1", Vector2(1000, 1700), 60, "oval", {"length": 35.5, "width": 60}), _model("m2", Vector2(880, 1700), 32)],
		_scout_abilities())
	snap.units["en"] = _unit("en", 1, GameStateData.UnitStatus.DEPLOYED, [_model("e1", Vector2(880, 1200), 32)])
	_load_units_into_gs(snap)
	var unit: Dictionary = snap.units["mx"]
	var enemies := AIDecisionMaker._get_enemy_units(snap, 2)
	var dests: Dictionary = AIDecisionMaker._compute_scout_movement(unit, "mx", Vector2(880, 1200), 6.0, snap, enemies)
	_check("ed %d: AI found a scout move" % ed, not dests.is_empty())
	if dests.is_empty():
		return
	var edge := _min_edge(unit, dests, enemies)
	print("    m1 (oval) y=%.1f, m2 (32mm) y=%.1f, per-model min edge %.2f\"" % [float(dests["m1"][1]), float(dests["m2"][1]), edge])
	if ed >= 11:
		_check("ed 11: uses the 8-9\" band (8.0 <= %.2f < 9.0)" % edge, edge >= 8.0 and edge < 9.0)
	else:
		_check("ed 10: ends >= 9\" (%.2f)" % edge, edge >= 9.0)
	var v := _engine_scout_verdict(snap, "mx", dests, 6.0)
	_check("ed %d: the REAL ScoutPhase accepts set-dest AND confirm (per-model confirm)" % ed, v == "", v)

# -- F3 / F4: reserve arrivals -----------------------------------------------

## The engine's own verdict on an AI PLACE_REINFORCEMENT: IngressMove.
## validate_setup (the 11e gate, with each model's base) and the whole
## MovementPhase._validate_place_reinforcement (set-up overlap gate + the
## 11e ingress gate, or the legacy 10e branch). "" = accepted.
func _engine_reserve_verdict(snap: Dictionary, uid: String, dec: Dictionary) -> String:
	_load_units_into_gs(snap)
	gs.state["meta"]["battle_round"] = int(snap.meta.battle_round)
	gs.state["meta"]["active_player"] = 2
	var unit: Dictionary = gs.state.units[uid]
	var pos_vecs := []
	var pos_models := []
	var mp_list: Array = dec.get("model_positions", [])
	for i in range(mp_list.size()):
		if mp_list[i] == null:
			continue
		pos_vecs.append(mp_list[i])
		pos_models.append((unit.models[i] as Dictionary).duplicate())
	var ptype := str(dec.get("placement_type", unit.get("reserve_type", "deep_strike")))
	var ingress = load("res://scripts/rules/movetypes/IngressMove.gd").new()
	var iv: Dictionary = ingress.validate_setup(uid, gs.state, pos_vecs, {
		"battle_round": int(snap.meta.battle_round), "deep_strike": ptype == "deep_strike",
		"board_size_inches": Vector2(44, 60), "opponent_zone": PackedVector2Array(), "models": pos_models})
	if not iv.valid:
		return "IngressMove: %s" % str(iv.errors)
	var mph = load("res://phases/MovementPhase.gd").new()
	var mv: Dictionary = mph._validate_place_reinforcement({"type": "PLACE_REINFORCEMENT", "unit_id": uid,
		"model_positions": mp_list, "model_rotations": dec.get("model_rotations", []), "placement_type": ptype})
	mph.free()
	if not mv.valid:
		return "MovementPhase: %s" % str(mv.errors)
	return ""

func _ds_ring_snap() -> Dictionary:
	# Objective with four single 32mm enemies on the diagonals, 9.76" centre to
	# centre: a 32mm model ON the objective is 8.50" base to base from each.
	var obj := Vector2(830, 1150)
	var snap := _snap([obj], 2)
	var k := 0
	for off in [Vector2(276, 276), Vector2(-276, 276), Vector2(276, -276), Vector2(-276, -276)]:
		k += 1
		snap.units["E%d" % k] = _unit("E%d" % k, 1, GameStateData.UnitStatus.DEPLOYED, [_model("m1", obj + off, 32)])
	snap.units["DS"] = _unit("DS", 2, GameStateData.UnitStatus.IN_RESERVES, [_model("m1", null, 32)],
		[{"name": "Deep Strike"}], "deep_strike")
	return snap

func _test_ds_ring_arrival(ed: int) -> void:
	print("\n-- F3 deep strike: the 8-9\" ring around an objective (edition %d) --" % ed)
	var obj := Vector2(830, 1150)
	var snap := _ds_ring_snap()
	var objectives := AIDecisionMaker._get_objectives(snap)
	var enemies := AIDecisionMaker._get_enemy_units(snap, 2)
	var emp := AIDecisionMaker._get_enemy_model_positions_from_snapshot(snap, 2)
	var cands: Array = AIDecisionMaker._compute_reinforcement_positions(snap.units["DS"], "DS", "deep_strike", snap, 2, objectives, enemies, emp, 2)
	var has_obj := false
	for c in cands:
		if (c as Vector2).distance_to(obj) < 0.5:
			has_obj = true
	if ed >= 11:
		_check("ed 11: the objective itself is a candidate (8.50\" > 8\")", has_obj, "%d candidates" % cands.size())
	else:
		_check("ed 10: the objective is not a candidate (8.50\" < 9\")", not has_obj)
	var dec: Dictionary = AIDecisionMaker._decide_reserves_arrival(snap, [{"type": "PLACE_REINFORCEMENT", "unit_id": "DS"}], 2)
	_check("ed %d: AI places the unit" % ed, dec.get("type", "") == "PLACE_REINFORCEMENT", str(dec.get("type", "")))
	if dec.get("type", "") != "PLACE_REINFORCEMENT":
		return
	var p: Vector2 = dec.model_positions[0]
	var d_obj := p.distance_to(obj) / PPI
	var gap := INF
	for e in emp:
		gap = minf(gap, p.distance_to(e.position) / PPI - 2.0 * R32)
	print("    lands (%.0f, %.0f): %.2f\" from the objective, %.2f\" base to base from the nearest enemy" % [p.x, p.y, d_obj, gap])
	if ed >= 11:
		_check("ed 11: lands on the objective (<= 1\", was 15\" with the 9\" pre-filter)", d_obj <= 1.0, "%.2f" % d_obj)
	else:
		_check("ed 10: off the objective (> 6\")", d_obj > 6.0, "%.2f" % d_obj)
	_check("ed %d: beyond the stand-off from every enemy model (%.2f > %.0f)" % [ed, gap, GameConstants.reinforcement_min_enemy_distance_inches()],
		gap >= GameConstants.reinforcement_min_enemy_distance_inches())
	var v := _engine_reserve_verdict(snap, "DS", dec)
	_check("ed %d: the engine accepts the arrival (IngressMove + MovementPhase)" % ed, v == "", v)

func _test_mixed_base_reserves(ed: int) -> void:
	# A 32mm model first, then a 60mm oval. One enemy model sits so the AI's
	# favourite spot (on the objective) is legal for 32mm bases but puts the
	# oval 7.7" away: the reserve gate must measure each model with its own
	# base or the engine rejects the arrival.
	print("\n-- reserves: mixed bases, 32mm first + 60mm oval (edition %d) --" % ed)
	var obj := Vector2(830, 1150)
	var snap := _snap([obj], 2)
	snap.units["EN"] = _unit("EN", 1, GameStateData.UnitStatus.DEPLOYED, [_model("m1", Vector2(830, 1529), 32)])
	snap.units["MX"] = _unit("MX", 2, GameStateData.UnitStatus.IN_RESERVES,
		[_model("m1", null, 32), _model("m2", null, 60, "oval", {"length": 35.5, "width": 60})],
		[{"name": "Deep Strike"}], "deep_strike")
	var dec: Dictionary = AIDecisionMaker._decide_reserves_arrival(snap, [{"type": "PLACE_REINFORCEMENT", "unit_id": "MX"}], 2)
	_check("ed %d: AI places the mixed unit" % ed, dec.get("type", "") == "PLACE_REINFORCEMENT", str(dec.get("type", "")))
	if dec.get("type", "") != "PLACE_REINFORCEMENT":
		return
	var p0: Vector2 = dec.model_positions[0]
	var p1: Vector2 = dec.model_positions[1]
	var en_pos := Vector2(830, 1529)
	var oval_gap := p1.distance_to(en_pos) / PPI - R60 - R32
	print("    m1 (32mm) (%.0f, %.0f), m2 (60mm oval) (%.0f, %.0f): oval %.2f\" from the enemy" % [p0.x, p0.y, p1.x, p1.y, oval_gap])
	_check("ed %d: the 60mm oval, measured with its own base, is beyond the stand-off (%.2f)" % [ed, oval_gap],
		oval_gap >= GameConstants.reinforcement_min_enemy_distance_inches())
	var v := _engine_reserve_verdict(snap, "MX", dec)
	_check("ed %d: the engine accepts the mixed arrival (IngressMove + MovementPhase)" % ed, v == "", v)

func _test_sr_edge_strip_candidate(ed: int) -> void:
	print("\n-- F3 strategic reserves: an 8-9\" edge spot (edition %d) --" % ed)
	var snap := _snap([Vector2(880, 1200)], 2)
	snap.units["EN"] = _unit("EN", 1, GameStateData.UnitStatus.DEPLOYED, [_model("m1", Vector2(500, 1240), 32)])
	snap.units["SR"] = _unit("SR", 2, GameStateData.UnitStatus.IN_RESERVES, [_model("m1", null, 32)], [], "strategic_reserves")
	var objectives := AIDecisionMaker._get_objectives(snap)
	var enemies := AIDecisionMaker._get_enemy_units(snap, 2)
	var emp := AIDecisionMaker._get_enemy_model_positions_from_snapshot(snap, 2)
	var cands: Array = AIDecisionMaker._compute_reinforcement_positions(snap.units["SR"], "SR", "strategic_reserves", snap, 2, objectives, enemies, emp, 2)
	var spot := Vector2(120, 1240)  # 3" from the left edge, 9.5" centre / 8.24" base to base from the enemy
	var found := false
	for c in cands:
		if (c as Vector2).distance_to(spot) < 0.5:
			found = true
	if ed >= 11:
		_check("ed 11: (120, 1240) is proposed (8.24\" > 8\")", found, "%d candidates" % cands.size())
	else:
		_check("ed 10: (120, 1240) is not proposed (8.24\" < 9\")", not found)

func _test_ds_clear_objective_term(ed: int) -> void:
	print("\n-- F4 arrival urgency: deep-strike objective clearance (edition %d) --" % ed)
	var snap := _snap([Vector2(880, 1200)], 2)
	snap.units["EN"] = _unit("EN", 1, GameStateData.UnitStatus.DEPLOYED, [_model("m1", Vector2(880, 1016), 32)])  # 4.60" from the marker
	snap.units["DS"] = _unit("DS", 2, GameStateData.UnitStatus.IN_RESERVES, [_model("m1", null, 32)], [{"name": "Deep Strike"}], "deep_strike")
	var terms := {}
	AIDecisionMaker._score_reserves_deployment(snap.units["DS"], "DS", "deep_strike", AIDecisionMaker._get_objectives(snap),
		AIDecisionMaker._get_enemy_units(snap, 2), snap, 2, 2, terms)
	var t := float(terms.get("arrive_objectives", 0.0))
	print("    arrive_objectives = %.2f" % t)
	if ed >= 11:
		_check("ed 11: the objective counts (it can be reached > 8\" from the enemy)", t > 0.0, "%.2f" % t)
	else:
		_check("ed 10: the objective does not count (needs > 9\")", t == 0.0, "%.2f" % t)

# -- threat model (decision D6: unchanged) and charge odds ---------------------

func _test_threat_reach_unchanged(ed: int) -> void:
	print("\n-- threat model: charge radius unchanged, M + 12 + ER (edition %d) --" % ed)
	var snap := _snap([Vector2(880, 1200)])
	snap.units["EN"] = _unit("EN", 1, GameStateData.UnitStatus.DEPLOYED, [_model("m1", Vector2(800, 600), 32)])
	var td: Array = AIDecisionMaker._calculate_enemy_threat_data(AIDecisionMaker._get_enemy_units(snap, 2))
	var want := (6.0 + 12.0 + GameConstants.engagement_range_inches()) * PPI
	_check("ed %d: M6 charge_threat_px == %.0f (D6 keeps the +ER centroid allowance)" % [ed, want],
		td.size() == 1 and absf(float(td[0].charge_threat_px) - want) < 0.01, str(td))

func _test_charge_odds(ed: int) -> void:
	print("\n-- charge odds follow 11.04 (edition %d) --" % ed)
	var mismatches := 0
	var first_bad := ""
	var er := GameConstants.engagement_range_inches()
	for i in range(210, 1201):
		var d := float(i) / 100.0
		for pen in [0.0, 1.0, 2.0, 3.0]:
			var ai := AIDecisionMaker._charge_success_probability(AIDecisionMaker._charge_roll_needed(d, pen))
			var ok_rolls := 0
			for a in range(1, 7):
				for b in range(1, 7):
					var roll := float(a + b)
					var ok := false
					if ed >= 11:
						ok = d <= ChargeMove11e.selectable_distance_ceiling(roll) + ChargeMove11e.WITHIN_TOLERANCE_INCHES \
							and maxf(0.0, d - er) + pen <= roll + ChargeMove11e.WITHIN_TOLERANCE_INCHES
					else:
						ok = roll >= ceilf(maxf(0.0, d - er) + pen)
					if ok:
						ok_rolls += 1
			var brute := float(ok_rolls) / 36.0
			if absf(ai - brute) > 1e-9:
				mismatches += 1
				if first_bad == "":
					first_bad = "d=%.2f pen=%.0f ai=%.4f rule=%.4f" % [d, pen, ai, brute]
	_check("ed %d: AI charge odds == the rule over d 2.10-12.00 x pen 0-3 (%d mismatches)" % [ed, mismatches], mismatches == 0, first_bad)
	if ed >= 11:
		for pin in [[7.00, 21], [7.02, 21], [7.03, 15], [9.00, 10]]:
			var pr := AIDecisionMaker._charge_success_probability(AIDecisionMaker._charge_roll_needed(pin[0], 0.0))
			_check("ed 11: %.2f\" charge = %d/36" % [pin[0], pin[1]], absf(pr - float(pin[1]) / 36.0) < 1e-9, "%.4f" % pr)

# -- F2: Scouts X" ---------------------------------------------------------------

func _test_scout_distance_parsing() -> void:
	print("\n-- F2 scout distance: the engine's value, with a purity guard --")
	# Not in GameState -> snapshot-only parse (the engine pattern now).
	var s8 := _unit("not_in_gs_8", 1, GameStateData.UnitStatus.DEPLOYED, [_model("m1", Vector2(100, 100), 32)], [{"name": "Scouts 8\"", "type": "Core"}])
	_check("'Scouts 8\"' (no value field) reads 8 (was 6)", AIDecisionMaker._get_scout_distance_from_unit(s8, {}) == 8.0,
		str(AIDecisionMaker._get_scout_distance_from_unit(s8, {})))
	var s9 := _unit("not_in_gs_9", 1, GameStateData.UnitStatus.DEPLOYED, [_model("m1", Vector2(100, 100), 32)], ["Scout 9\""])
	_check("'Scout 9\"' (string ability) reads 9", AIDecisionMaker._get_scout_distance_from_unit(s9, {}) == 9.0)
	var s6 := _unit("not_in_gs_6", 1, GameStateData.UnitStatus.DEPLOYED, [_model("m1", Vector2(100, 100), 32)], [{"name": "Scouts 6\"", "value": 6}])
	_check("{value: 6} reads 6", AIDecisionMaker._get_scout_distance_from_unit(s6, {}) == 6.0)

	# Live units whose Scouts value only the engine reads (description-only
	# 'Core' entry; a `parameter` field): the AI must use the engine's value
	# when the snapshot unit IS the live unit, and only then.
	var snap := _snap([Vector2(880, 1200)])
	snap.units["U_DESC"] = _unit("U_DESC", 2, GameStateData.UnitStatus.DEPLOYED, [_model("m1", Vector2(300, 2000), 32)],
		[{"name": "Core", "description": "Scouts 7\": this unit can make a scout move."}])
	snap.units["U_PARAM"] = _unit("U_PARAM", 2, GameStateData.UnitStatus.DEPLOYED, [_model("m1", Vector2(400, 2000), 32)],
		[{"name": "Scouts", "type": "Core", "parameter": "8\""}])
	_load_units_into_gs(snap)
	var live_snap: Dictionary = gs.create_snapshot(false)
	for pair in [["U_DESC", 7.0], ["U_PARAM", 8.0]]:
		var uid: String = pair[0]
		var eng := float(gs.get_scout_distance(uid))
		var su: Dictionary = live_snap.units[uid]
		_check("%s: engine reads %.0f\"" % [uid, pair[1]], eng == pair[1], str(eng))
		_check("%s: purity guard matches the live snapshot copy" % uid, AIDecisionMaker._scout_snapshot_unit_is_live(su, gs.get_unit(uid)))
		_check("%s: AI uses the engine's %.0f\" (snapshot matches GameState)" % [uid, pair[1]],
			AIDecisionMaker._get_scout_distance_from_unit(su, live_snap) == eng, str(AIDecisionMaker._get_scout_distance_from_unit(su, live_snap)))
		# A hypothetical snapshot (edited abilities) must NOT read live state.
		var hypo: Dictionary = su.duplicate(true)
		hypo.meta.abilities = [{"name": "Scouts 5\"", "value": 5}]
		_check("%s: guard rejects a hypothetical copy (edited abilities)" % uid, not AIDecisionMaker._scout_snapshot_unit_is_live(hypo, gs.get_unit(uid)))
		_check("%s: hypothetical copy reads its own 5\", not the live %.0f\"" % [uid, eng],
			AIDecisionMaker._get_scout_distance_from_unit(hypo, {}) == 5.0, str(AIDecisionMaker._get_scout_distance_from_unit(hypo, {})))
		var hypo_flags: Dictionary = su.duplicate(true)
		hypo_flags.flags["p02_probe"] = true
		_check("%s: guard rejects a copy whose flags differ" % uid, not AIDecisionMaker._scout_snapshot_unit_is_live(hypo_flags, gs.get_unit(uid)))

	# A real fixture: Invictor Tactical Warsuit, Scouts 8".
	var sl = root.get_node_or_null("SaveLoadManager")
	if sl == null or not sl.has_method("load_game_from_file_path"):
		_check("SaveLoadManager reachable for the fixture check", false)
		return
	sl.load_game_from_file_path("res://tests/saves/sm11e_m4a_round1.w40ksave")
	for ed in [11, 10]:
		GameConstants.edition = ed
		var fsnap: Dictionary = gs.create_snapshot(false)
		var inv: Dictionary = fsnap.units.get("U_INVICTOR_TACTICAL_WARSUIT_A", {})
		_check("ed %d: fixture has U_INVICTOR_TACTICAL_WARSUIT_A" % ed, not inv.is_empty())
		if inv.is_empty():
			continue
		var e_sd := float(gs.get_scout_distance("U_INVICTOR_TACTICAL_WARSUIT_A"))
		var a_sd := AIDecisionMaker._get_scout_distance_from_unit(inv, fsnap)
		_check("ed %d: Invictor AI Scouts %.0f\" == engine %.0f\" == 8\"" % [ed, a_sd, e_sd], a_sd == e_sd and e_sd == 8.0)
	GameConstants.edition = 11

# -- runner --------------------------------------------------------------------

func _initialize():
	await process_frame
	await process_frame
	print("\n=== test_ai_rules_distances_11e ===")
	gs = root.get_node_or_null("GameState")
	tm = root.get_node_or_null("TerrainManager")
	if gs == null:
		print("FAIL: GameState autoload missing")
		quit(1)
		return
	var ed0 := GameConstants.edition
	_saved_units = gs.state.get("units", {}).duplicate(true)
	_saved_meta = gs.state.get("meta", {}).duplicate(true)
	# The synthetic boards have no terrain; give the engine the same view.
	if tm != null:
		_saved_terrain = tm.terrain_features.duplicate(true)
		tm.terrain_features.clear()
	for ed in [11, 10]:
		GameConstants.edition = ed
		print("\n##### edition %d (scout stand-off %.0f\", ingress stand-off %.0f\") #####" % [
			ed, GameConstants.scout_min_enemy_distance_inches(), GameConstants.reinforcement_min_enemy_distance_inches()])
		_test_scout_fraction_uses_8in_band(ed)
		_test_scout_skip_becomes_move(ed)
		_test_mixed_base_scout(ed)
		_test_first_model_larger_scout(ed)
		_test_ds_ring_arrival(ed)
		_test_mixed_base_reserves(ed)
		_test_sr_edge_strip_candidate(ed)
		_test_ds_clear_objective_term(ed)
		_test_threat_reach_unchanged(ed)
		_test_charge_odds(ed)
	GameConstants.edition = 11
	_test_scout_distance_parsing()
	# Restore what this test changed.
	GameConstants.edition = ed0
	gs.state["units"] = _saved_units
	gs.state["meta"] = _saved_meta
	if tm != null and _saved_terrain != null:
		tm.terrain_features.clear()
		tm.terrain_features.append_array(_saved_terrain)
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	print("ALL TESTS PASSED" if failed == 0 else "SOME TESTS FAILED")
	quit(0 if failed == 0 else 1)
