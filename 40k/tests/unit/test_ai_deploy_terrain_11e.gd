extends SceneTree

# P0.3 — the 11e deployment terrain scorer and the zone frame
# (docs/AI_DEPLOYMENT_PLAN.md §5 / §7 P0(c); FIX_DEPLOY_FRAME, FIX_DEPLOY_TERRAIN_11E).
#
# Frame: forward from the own zone toward the enemy zone on all 6 shipped maps,
# the column baseline equal to the old formula on Hammer and Anvil and inside the
# zone polygon everywhere, the counter-deployment golden table, the side-map axis.
# Scorer: 11e category semantics, the fragile_shooter swap fix, the anti_tank arm.
# Picker (live game state, real fixtures): candidates only from terrain AREA groups
# (group keys are VALUES of TerrainManager.build_area_group_map), group geometry
# from area polygons only (cross-parented wall features cannot drag anchors away),
# inside fills Hidden + legal, behind spots for non-hide-capable units, the K-card
# record written from the final positions with >= 2 options and chosen = the best
# ELIGIBLE option (also when no terrain spot builds), no partly Hidden units,
# determinism, both kill switches, the per-drop time bound, and attached Big Meks
# + a Battlewagon with embarked Gretchin (bw_load_deploy_pretrigger).
#
# Deployment loops route the AI's own decisions through PhaseManager /
# NetworkIntegration (the real DeploymentPhase + TurnManager order, TITANIC skip
# included) — the same calls AIPlayer makes, without its timers.
#
# Run: godot --headless --path . -s tests/unit/test_ai_deploy_terrain_11e.gd

const MAPS := ["hammer_anvil", "dawn_of_war", "crucible_of_battle", "tipping_point", "sweeping_engagement", "search_and_destroy"]
# P1 forward (P2 is its negation) and gap_min in inches (docs/AI_DEPLOYMENT_PLAN.md §2 table).
const EXPECT := {
	"hammer_anvil": [Vector2(0.0, 1.0), 24.0],
	"dawn_of_war": [Vector2(-1.0, 0.0), 20.0],
	"crucible_of_battle": [Vector2(0.34, 0.94), 24.8],
	"tipping_point": [Vector2(0.13, 0.99), 20.0],
	"sweeping_engagement": [Vector2(-0.97, -0.25), 16.0],
	"search_and_destroy": [Vector2(0.59, 0.81), 12.7],
}
const LAYOUT_FOR_ZONE := {
	"crucible_of_battle": "take_and_hold_mirror_1",
	"hammer_anvil": "purge_the_foe_vs_priority_assets_3",
	"dawn_of_war": "take_and_hold_mirror_2",
	"search_and_destroy": "disruption_vs_priority_assets_3",
	"sweeping_engagement": "disruption_vs_disruption_3",
	"tipping_point": "disruption_vs_disruption_2",
}
# probe11 golden values from the pre-P0.3 _apply_counter_deployment on Hammer and Anvil.
const GOLDEN := {
	1: {"melee": [Vector2(727.50, 400.00), Vector2(467.50, 660.00), Vector2(1475.00, 110.00)],
		"fragile_shooter": [Vector2(560.00, 330.00), Vector2(60.00, 620.00), Vector2(1700.00, 60.00)],
		"durable_shooter": [Vector2(592.92, 360.00), Vector2(337.92, 650.00), Vector2(1326.04, 70.00)],
		"character": [Vector2(337.50, 335.00), Vector2(60.00, 625.00), Vector2(1700.00, 60.00)],
		"general": [Vector2(555.00, 360.00), Vector2(215.00, 650.00), Vector2(1532.50, 70.00)]},
	2: {"melee": [Vector2(727.50, 2000.00), Vector2(467.50, 2290.00), Vector2(1475.00, 1740.00)],
		"fragile_shooter": [Vector2(560.00, 2070.00), Vector2(60.00, 2340.00), Vector2(1700.00, 1780.00)],
		"durable_shooter": [Vector2(592.92, 2040.00), Vector2(337.92, 2330.00), Vector2(1326.04, 1750.00)],
		"character": [Vector2(337.50, 2065.00), Vector2(60.00, 2340.00), Vector2(1700.00, 1775.00)],
		"general": [Vector2(555.00, 2040.00), Vector2(215.00, 2330.00), Vector2(1532.50, 1750.00)]},
}
const DROP_BUDGET_MS := 1200.0   # D10: <= ~1.2 s worst case per drop

var pass_count := 0
var fail_count := 0
var GS
var PM
var SL
var TMN
var MM
var NI
var AI
var FB
var DE

func _initialize():
	await process_frame
	print("=== P0.3: 11e deployment terrain scorer + zone frame ===")
	GS = root.get_node_or_null("GameState")
	PM = root.get_node_or_null("PhaseManager")
	SL = root.get_node_or_null("SaveLoadManager")
	TMN = root.get_node_or_null("TerrainManager")
	MM = root.get_node_or_null("MissionManager")
	NI = load("res://utils/NetworkIntegration.gd")
	AI = root.get_node_or_null("AIPlayer")
	FB = load("res://scripts/ai/FormationBuilder.gd")
	DE = load("res://scripts/ai/DeploymentEval.gd")
	if GS == null or PM == null or SL == null or TMN == null or MM == null or NI == null or AI == null:
		_check(false, "autoloads reachable (GameState, PhaseManager, SaveLoadManager, TerrainManager, MissionManager, AIPlayer) + NetworkIntegration")
		_finish()
		return
	GameConstants.edition = 11
	AIDecisionMaker._config_overrides["PLANS_ENABLED"] = 0.0
	var t0 := Time.get_ticks_msec()
	_test_frame_directions_all_maps()
	_test_frame_baseline_equals_legacy_on_hammer_anvil()
	_test_frame_baseline_inside_polygon_all_maps()
	_test_row1_baseline_faces_enemy_on_side_maps()
	_test_chord_non_convex()
	_test_counter_deploy_golden_hammer_anvil()
	_test_counter_deploy_axis_dawn_of_war()
	_test_fit_11e_category_semantics()
	_test_fragile_swap_fixed()
	_test_anti_tank_branch()
	_test_pocket_fill_unit_math()
	await _test_candidates_only_from_area_groups()
	await _test_cross_parented_features_do_not_move_anchors()
	await _test_inside_fill_hidden_and_legal()
	await _test_behind_spots_for_non_hide_units()
	await _test_record_coherent_first_drop()
	await _test_record_when_no_terrain_spot_builds()
	await _test_flag_off_uses_legacy()
	await _test_frame_flag_off_restores_old_baseline()
	await _test_full_deployment_asym_no_leakers_and_determinism()
	await _test_perf_budget_orks()
	await _test_bw_load_attached_leaders_and_transport()
	print("total %d ms" % (Time.get_ticks_msec() - t0))
	_finish()

func _finish() -> void:
	AIDecisionMaker._config_overrides.erase("PLANS_ENABLED")
	GameConstants.edition = 11
	print("\n=== Results: %d passed, %d failed ===" % [pass_count, fail_count])
	print("ALL TESTS PASSED" if fail_count == 0 else "SOME TESTS FAILED")
	quit(1 if fail_count > 0 else 0)

func _check(cond: bool, msg: String) -> void:
	if cond:
		pass_count += 1
		print("PASS: %s" % msg)
	else:
		fail_count += 1
		print("FAIL: %s" % msg)

# -----------------------------------------------------------------------------
# helpers
# -----------------------------------------------------------------------------

func _zones(map_id: String) -> Array:
	var zs = DeploymentZoneData.get_zones(map_id)
	var dz: Array = []
	for i in range(zs.size()):
		dz.append(zs[i] if zs[i] is Dictionary else {"player": i + 1, "poly": zs[i]})
	return dz

func _map_objectives(map_id: String) -> Array:
	var out: Array = []
	var js = JSON.parse_string(FileAccess.get_file_as_string("res://deployment_zones/%s.json" % map_id))
	if js is Dictionary:
		for o in js.get("objectives", []):
			out.append(Vector2(float(o.position[0]), float(o.position[1])) * 40.0)
	return out

func _old_objective_pos(zb: Dictionary, objectives: Array) -> Vector2:
	# verbatim from the pre-P0.3 _decide_deployment
	var zone_center = Vector2((zb.min_x + zb.max_x) / 2.0, (zb.min_y + zb.max_y) / 2.0)
	var objective_pos = zone_center
	var best_dist = INF
	for obj_pos in objectives:
		var clamped = Vector2(clamp(obj_pos.x, zb.min_x, zb.max_x), clamp(obj_pos.y, zb.min_y, zb.max_y))
		var dist = clamped.distance_to(obj_pos)
		if dist < best_dist:
			best_dist = dist
			objective_pos = clamped
	return objective_pos

func _old_baseline(zb: Dictionary, deployed_count: int, n_units: int, objective_pos: Vector2) -> Vector2:
	# verbatim copy of the pre-P0.3 column baseline (AIDecisionMaker :5405-5439 at 94c2adf)
	var zone_width = zb.max_x - zb.min_x
	var zone_height = zb.max_y - zb.min_y
	var num_columns = maxi(3, mini(5, n_units))
	var col_width = zone_width / num_columns
	var col_index = deployed_count % num_columns
	var depth_row = deployed_count / num_columns
	var col_center_x = zb.min_x + col_width * (col_index + 0.5)
	var depth_step = mini(200, int(zone_height / 3.0))
	var depth_offset = depth_row * depth_step
	var is_top_zone = zb.min_y < AIDecisionMaker.BOARD_HEIGHT_PX / 2.0
	var deploy_y: float
	if is_top_zone:
		deploy_y = zb.max_y - 80.0 - depth_offset
	else:
		deploy_y = zb.min_y + 80.0 + depth_offset
	var baseline_pos = Vector2.ZERO
	baseline_pos.x = col_center_x * 0.7 + objective_pos.x * 0.3
	baseline_pos.y = clamp(deploy_y, zb.min_y + 60, zb.max_y - 60)
	return baseline_pos

func _setup_board(zone: String) -> void:
	if zone == "fixture":
		return
	TMN.load_terrain_layout(LAYOUT_FOR_ZONE[zone])
	GS.state["board"]["terrain_layout"] = LAYOUT_FOR_ZONE[zone]
	GS.state["board"]["deployment_zones"] = _zones(zone)
	GS.state["meta"]["deployment_type"] = zone
	MM._setup_objectives_for_deployment(zone)

func _load(fix: String, zone: String, seed_v: int) -> bool:
	AI.enabled = false
	AI.ai_players = {1: false, 2: false}
	if not SL.load_game_from_file_path("res://tests/saves/%s.w40ksave" % fix):
		_check(false, "fixture %s loads" % fix)
		return false
	GameConstants.edition = 11
	_setup_board(zone)
	root.get_node("RulesEngine").set_test_seed(seed_v)
	AIDecisionMaker.set_ai_seed(seed_v)
	AIDecisionMaker.clear_all_plans()
	AIDecisionMaker._config_overrides["PLANS_ENABLED"] = 0.0
	PM.transition_to_phase(1)
	AI.enabled = false
	AI.ai_players = {1: false, 2: false}
	await process_frame
	return int(GS.get_current_phase()) == 1

func _as_player(pl: int) -> int:
	"""The live phase validates against the ACTIVE player: probes for a seat
	that is not up yet run as that seat. Returns the previous active player."""
	var prev := int(GS.state["meta"].get("active_player", 1))
	GS.state["meta"]["active_player"] = pl
	return prev

func _first_deploy_actions(player: int) -> Array:
	var out: Array = []
	for a in PM.get_available_actions():
		if str(a.get("type", "")) == "DEPLOY_UNIT":
			out.append(a)
	return out

func _decide_for(player: int, actions: Array) -> Dictionary:
	var snap = GS.create_snapshot(false)
	var d: Dictionary = AIDecisionMaker.decide(1, snap, actions, player)
	return {"decision": d, "records": AIDecisionMaker._decision_records.duplicate(true), "snapshot": snap}

func _deployment_record(records: Array) -> Dictionary:
	for r in records:
		if str(r.get("decision_type", "")) == "deployment":
			return r
	return {}

func _deploy_all(max_drops: int = 80) -> Dictionary:
	"""Run the AI's deployment decisions through the real phase until DEPLOYMENT
	ends. {drops: [{player, unit_id, type, ms, record, relation, desc, ccd}], ok, digest}."""
	var drops: Array = []
	var ok := true
	var forced := 0
	for i in range(max_drops):
		if int(GS.get_current_phase()) != 1:
			break
		var player := int(GS.get_active_player())
		var avail: Array = PM.get_available_actions()
		var snap = GS.create_snapshot(false)
		var t0 := Time.get_ticks_usec()
		var d: Dictionary = AIDecisionMaker.decide(1, snap, avail, player)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		var rec := _deployment_record(AIDecisionMaker._decision_records)
		if d.is_empty():
			var routed := false
			for a in avail:
				if str(a.get("type", "")) in ["SWITCH_PLAYER", "END_DEPLOYMENT"]:
					var a2: Dictionary = a.duplicate()
					a2["player"] = player
					NI.route_action(a2)
					routed = true
					break
			if not routed:
				print("  no decision and nothing to route (P%d)" % player)
				ok = false
				break
			await process_frame
			continue
		if bool(d.get("_ai_no_legal_formation", false)):
			# What AIPlayer does: Strategic Reserves (a forced reserve).
			print("  NO LEGAL FORMATION for %s -> Strategic Reserves" % str(d.get("unit_id", "")))
			ok = false
			forced += 1
			NI.route_action({"type": "PLACE_IN_RESERVES", "unit_id": str(d.get("unit_id", "")),
				"reserve_type": "strategic_reserves", "player": player})
			await process_frame
			continue
		d["player"] = player
		var t := str(d.get("type", ""))
		var res = NI.route_action(d)
		if t == "DEPLOY_UNIT" or t == "COMPOSITE_DEPLOY":
			var success: bool = res != null and bool(res.get("success", false))
			if not success:
				print("  REJECTED %s: %s" % [str(d.get("unit_id", "")), str(res)])
				ok = false
			drops.append({"player": player, "unit_id": str(d.get("unit_id", "")), "type": t, "ms": ms,
				"record": rec, "relation": str(rec.get("context", {}).get("relation", "")),
				"desc": str(d.get("_ai_description", "")), "ccd": d.get("combined_char_data", {}),
				"positions": d.get("model_positions", []), "success": success})
		await process_frame
	return {"drops": drops, "ok": ok and int(GS.get_current_phase()) != 1, "forced": forced, "digest": DE.positions_digest(GS.state)}

func _unit_hidden(uid: String) -> Dictionary:
	var u: Dictionary = GS.state.units[uid]
	return DE.unit_hidden_counts(u)

func _ovr_set(params: Dictionary) -> void:
	for k in params:
		AIDecisionMaker._config_overrides[k] = params[k]

func _ovr_unset(params: Dictionary) -> void:
	for k in params:
		AIDecisionMaker._config_overrides.erase(k)

# -----------------------------------------------------------------------------
# frame
# -----------------------------------------------------------------------------

func _test_frame_directions_all_maps() -> void:
	print("\n-- frame directions on all 6 maps --")
	for map_id in MAPS:
		var snap := {"board": {"deployment_zones": _zones(map_id)}}
		for pl in [1, 2]:
			var fr: Dictionary = AIDecisionMaker._deployment_frame(snap, pl)
			var want: Vector2 = EXPECT[map_id][0] if pl == 1 else -(EXPECT[map_id][0] as Vector2)
			var fwd: Vector2 = fr.fwd
			var lat: Vector2 = fr.lat
			var gap_in: float = float(fr.gap_min) / 40.0
			_check(fwd.distance_to(want) <= 0.02, "%s P%d fwd (%.2f,%.2f) ~ (%.2f,%.2f)" % [map_id, pl, fwd.x, fwd.y, want.x, want.y])
			_check(lat.x > 1e-6 or (absf(lat.x) <= 1e-6 and lat.y > 0.0), "%s P%d lat (%.2f,%.2f) oriented +x" % [map_id, pl, lat.x, lat.y])
			_check(absf(gap_in - float(EXPECT[map_id][1])) <= 0.2, "%s P%d gap_min %.2f\" ~ %.1f\"" % [map_id, pl, gap_in, float(EXPECT[map_id][1])])

func _test_frame_baseline_equals_legacy_on_hammer_anvil() -> void:
	print("\n-- frame baseline == pre-P0.3 baseline on Hammer and Anvil --")
	var snap := {"board": {"deployment_zones": _zones("hammer_anvil")}}
	var objs := _map_objectives("hammer_anvil")
	var worst := 0.0
	var same_cells := true
	for pl in [1, 2]:
		var zb: Dictionary = AIDecisionMaker._get_deployment_zone_bounds(snap, pl)
		var fr: Dictionary = AIDecisionMaker._deployment_frame(snap, pl)
		var op := _old_objective_pos(zb, objs)
		for k in range(15):
			var nb: Dictionary = AIDecisionMaker._frame_baseline(fr, zb, k, 15, op)
			worst = maxf(worst, (nb.pos as Vector2).distance_to(_old_baseline(zb, k, 15, op)))
			if int(nb.col) != k % 5 or int(nb.row) != k / 5:
				same_cells = false
	_check(worst <= 0.5, "15 drops x 2 seats: max |frame - old| = %.3f px (<= 0.5)" % worst)
	_check(same_cells, "column / row indices unchanged")

func _test_frame_baseline_inside_polygon_all_maps() -> void:
	print("\n-- frame baselines inside the zone polygon on all maps --")
	for map_id in MAPS:
		var snap := {"board": {"deployment_zones": _zones(map_id)}}
		var objs := _map_objectives(map_id)
		for pl in [1, 2]:
			var zb: Dictionary = AIDecisionMaker._get_deployment_zone_bounds(snap, pl)
			var fr: Dictionary = AIDecisionMaker._deployment_frame(snap, pl)
			var poly: PackedVector2Array = fr.own_poly
			var op := _old_objective_pos(zb, objs)
			var inside := 0
			var old_inside := 0
			for k in range(15):
				var p: Vector2 = AIDecisionMaker._frame_baseline(fr, zb, k, 15, op).pos
				if Geometry2D.is_point_in_polygon(p, poly) and AIDecisionMaker._dist_to_boundary_px(p, poly) >= 59.5:
					inside += 1
				if Geometry2D.is_point_in_polygon(_old_baseline(zb, k, 15, op), poly):
					old_inside += 1
			_check(inside == 15, "%s P%d: %d/15 baselines inside the polygon >= 1.5\" from its edge (old formula: %d/15 inside)" % [map_id, pl, inside, old_inside])

func _test_row1_baseline_faces_enemy_on_side_maps() -> void:
	print("\n-- row-1 baselines face the enemy --")
	for map_id in ["dawn_of_war", "sweeping_engagement", "tipping_point", "search_and_destroy", "crucible_of_battle"]:
		var snap := {"board": {"deployment_zones": _zones(map_id)}}
		var objs := _map_objectives(map_id)
		for pl in [1, 2]:
			var zb: Dictionary = AIDecisionMaker._get_deployment_zone_bounds(snap, pl)
			var fr: Dictionary = AIDecisionMaker._deployment_frame(snap, pl)
			var op := _old_objective_pos(zb, objs)
			var worst := INF
			var worst_old := INF
			for k in range(5):
				worst = minf(worst, AIDecisionMaker._frame_forwardness(fr, AIDecisionMaker._frame_baseline(fr, zb, k, 15, op).pos))
				worst_old = minf(worst_old, AIDecisionMaker._frame_forwardness(fr, _old_baseline(zb, k, 15, op)))
			_check(worst >= 0.55, "%s P%d: row-1 forwardness >= 0.55 (min %.2f; old formula %.2f)" % [map_id, pl, worst, worst_old])

func _test_chord_non_convex() -> void:
	print("\n-- chord through a non-convex zone --")
	# A U-shaped zone: the line x = 100 crosses it twice (y 0-100 and y 300-400).
	var u := PackedVector2Array([Vector2(0, 0), Vector2(400, 0), Vector2(400, 400), Vector2(0, 400), Vector2(0, 300),
		Vector2(300, 300), Vector2(300, 100), Vector2(0, 100)])
	var fr := {"own_poly": u, "fwd": Vector2(0, 1), "s_min": -9999.0, "s_max": 9999.0}
	var ch: Array = AIDecisionMaker._frame_chord(fr, Vector2(100, 50))
	_check(absf(float(ch[0]) + 50.0) < 0.5 and absf(float(ch[1]) - 50.0) < 0.5, "the segment containing p0 is chosen ([%.1f, %.1f], want [-50, 50])" % [float(ch[0]), float(ch[1])])
	var ch2: Array = AIDecisionMaker._frame_chord(fr, Vector2(100, 200))
	_check(absf(float(ch2[1]) - float(ch2[0]) - 100.0) < 0.5, "p0 outside the zone: the longest in-zone segment ([%.1f, %.1f])" % [float(ch2[0]), float(ch2[1])])
	var ch3: Array = AIDecisionMaker._frame_chord(fr, Vector2(350, 200))
	_check(absf(float(ch3[0]) + 200.0) < 0.5 and absf(float(ch3[1]) - 200.0) < 0.5, "a vertex-free full crossing ([%.1f, %.1f], want [-200, 200])" % [float(ch3[0]), float(ch3[1])])

func _counter_snapshot(map_id: String, pl: int) -> Dictionary:
	var zs := _zones(map_id)
	var enemy_pl := 3 - pl
	var snap0 := {"board": {"deployment_zones": zs}, "units": {}}
	var ez: Dictionary = AIDecisionMaker._get_deployment_zone_bounds(snap0, enemy_pl)
	var efr: Dictionary = AIDecisionMaker._deployment_frame(snap0, enemy_pl)
	var units := {}
	var specs := [["E1", "melee", 300.0, 150], ["E2", "fragile_shooter", 1400.0, 80], ["E3", "durable_shooter", 900.0, 200]]
	for sp in specs:
		var wpn = [{"type": "melee", "attacks": "4", "damage": "2", "strength": "5", "ap": "-1"}] if sp[1] == "melee" else [{"type": "ranged", "range": "24", "attacks": "2", "damage": "1", "strength": "4", "ap": "0"}]
		var stats = {"toughness": 3 if sp[1] == "fragile_shooter" else 6, "save": 5 if sp[1] == "fragile_shooter" else 2, "wounds": 1 if sp[1] == "fragile_shooter" else 3}
		var p := Vector2(float(sp[2]), (ez.min_y + ez.max_y) / 2.0)
		if map_id != "hammer_anvil":
			p = efr.inner + (efr.lat as Vector2) * (float(sp[2]) - 880.0) * 0.3
		units[sp[0]] = {"owner": enemy_pl, "status": 2, "meta": {"name": sp[0], "keywords": ["INFANTRY"], "points": sp[3], "stats": stats, "weapons": wpn},
			"models": [{"id": "m1", "alive": true, "base_mm": 32, "position": {"x": p.x, "y": p.y}}]}
	return {"board": {"deployment_zones": zs}, "units": units}

func _test_counter_deploy_golden_hammer_anvil() -> void:
	print("\n-- counter-deployment in the frame == pre-P0.3 golden table (Hammer and Anvil) --")
	var worst := 0.0
	for pl in [1, 2]:
		var snap := _counter_snapshot("hammer_anvil", pl)
		var zb: Dictionary = AIDecisionMaker._get_deployment_zone_bounds(snap, pl)
		var fr: Dictionary = AIDecisionMaker._deployment_frame(snap, pl)
		var bases := [Vector2(500, (zb.min_y + zb.max_y) / 2.0), Vector2(100, zb.max_y - 70.0), Vector2(1650, zb.min_y + 70.0)]
		for role in ["melee", "fragile_shooter", "durable_shooter", "character", "general"]:
			for bi in range(3):
				var adj: Vector2 = AIDecisionMaker._apply_counter_deployment_frame(bases[bi], role, {"meta": {"keywords": ["INFANTRY"]}}, snap, pl, zb, fr, [])
				worst = maxf(worst, adj.distance_to(GOLDEN[pl][role][bi]))
	_check(worst <= 0.01, "5 roles x 3 bases x 2 seats: max |frame - golden| = %.4f px (<= 0.01)" % worst)

func _test_counter_deploy_axis_dawn_of_war() -> void:
	print("\n-- counter-deployment on Dawn of War moves along the real axis --")
	for pl in [1, 2]:
		var snap := _counter_snapshot("dawn_of_war", pl)
		var zb: Dictionary = AIDecisionMaker._get_deployment_zone_bounds(snap, pl)
		var fr: Dictionary = AIDecisionMaker._deployment_frame(snap, pl)
		var base: Vector2 = fr.inner
		var fwd: Vector2 = fr.fwd
		var poly: PackedVector2Array = fr.own_poly
		var unit := {"meta": {"keywords": ["INFANTRY"]}}
		var m: Vector2 = AIDecisionMaker._apply_counter_deployment_frame(base, "melee", unit, snap, pl, zb, fr, [])
		var f: Vector2 = AIDecisionMaker._apply_counter_deployment_frame(base, "fragile_shooter", unit, snap, pl, zb, fr, [])
		var c: Vector2 = AIDecisionMaker._apply_counter_deployment_frame(base, "character", unit, snap, pl, zb, fr, [])
		_check((m - base).dot(fwd) > 0.0, "DoW P%d melee moves toward the enemy ((adj-base).fwd = %.1f)" % [pl, (m - base).dot(fwd)])
		_check((f - base).dot(fwd) < 0.0, "DoW P%d fragile (enemy melee present) moves back (%.1f)" % [pl, (f - base).dot(fwd)])
		_check((c - base).dot(fwd) < 0.0, "DoW P%d character (enemy shooters present) moves back (%.1f)" % [pl, (c - base).dot(fwd)])
		_check(Geometry2D.is_point_in_polygon(m, poly) and Geometry2D.is_point_in_polygon(f, poly) and Geometry2D.is_point_in_polygon(c, poly),
			"DoW P%d adjusted spots stay inside the zone polygon" % pl)

# -----------------------------------------------------------------------------
# scorer
# -----------------------------------------------------------------------------

func _test_fit_11e_category_semantics() -> void:
	print("\n-- 11e terrain fit by category and relation --")
	var a := AIDecisionMaker._deploy_terrain_fit_11e("character", "dense", "inside", 1.0, 0.0)
	var b := AIDecisionMaker._deploy_terrain_fit_11e("fragile_shooter", "light", "behind", 0.5, 0.0)
	var c := AIDecisionMaker._deploy_terrain_fit_11e("durable_shooter", "exposed", "behind", 1.0, 0.0)
	var d := AIDecisionMaker._deploy_terrain_fit_11e("anti_tank", "dense", "behind", 1.0, 0.0)
	var e := AIDecisionMaker._deploy_terrain_fit_11e("melee", "dense", "inside", 1.0, 1.0)
	var f := AIDecisionMaker._deploy_terrain_fit_11e("character", "dense", "inside", 1.0, 0.0, true)
	_check(is_equal_approx(a, 7.0), "character inside dense = cover 2 + Hidden LoS 5 = 7.0 (got %.2f)" % a)
	_check(is_equal_approx(b, 3.25), "fragile behind light, half the sight lines blocked = (3.5 + 3.0) x 0.5 = 3.25 (got %.2f)" % b)
	_check(is_equal_approx(c, 0.0), "behind an exposed area = 0 (got %.2f)" % c)
	_check(is_equal_approx(d, 3.5), "anti_tank behind dense = 2.5 + 1.0 = 3.5 (got %.2f)" % d)
	_check(is_equal_approx(e, 7.5), "melee inside dense at the front edge = 1.5 + 4.0 + forward 2.0 = 7.5 (got %.2f)" % e)
	_check(is_equal_approx(f, 2.0), "inside dense but within detection range of the enemy zone: cover only (13.08) = 2.0 (got %.2f)" % f)

func _test_fragile_swap_fixed() -> void:
	print("\n-- fragile_shooter cover / LoS weights no longer swapped --")
	var ov := {"DEPLOY_TERRAIN_FRAGILE_COVER": 10.0, "DEPLOY_TERRAIN_FRAGILE_LOS_BLOCK": 0.0}
	_ovr_set(ov)
	var woods := {"type": "woods", "height_category": "low"}
	var zb := {"min_x": 40.0, "max_x": 1720.0, "min_y": 10.0, "max_y": 470.0}
	var fr: Dictionary = AIDecisionMaker._deployment_frame({}, 1)
	var s1 := AIDecisionMaker._score_terrain_for_role_frame(woods, "fragile_shooter", Vector2(400, 200), fr)
	var s2 := AIDecisionMaker._score_terrain_for_role(woods, "fragile_shooter", Vector2(400, 200), zb, true)
	var s3 := AIDecisionMaker._deploy_terrain_fit_11e("fragile_shooter", "light", "inside", 1.0, 0.0)
	_check(is_equal_approx(s1, 10.0), "frame scorer: low woods (cover, no LoS block) -> FRAGILE_COVER = 10 (got %.2f; 0 before the fix)" % s1)
	_check(is_equal_approx(s2, 10.0), "legacy-signature scorer, same (got %.2f)" % s2)
	_check(is_equal_approx(s3, 10.0), "11e fit, inside light (unit math only: the picker never generates inside-light spots) = COVER (got %.2f)" % s3)
	_ovr_set({"FIX_DEPLOY_TERRAIN_11E": 0.0})
	var s4 := AIDecisionMaker._score_terrain_for_role(woods, "fragile_shooter", Vector2(400, 200), zb, true)
	var s5 := AIDecisionMaker._score_terrain_for_role_frame(woods, "fragile_shooter", Vector2(400, 200), fr)
	_check(is_equal_approx(s4, 0.0) and is_equal_approx(s5, 0.0), "FIX_DEPLOY_TERRAIN_11E = 0 keeps the old swap (got %.2f / %.2f)" % [s4, s5])
	_ovr_unset({"FIX_DEPLOY_TERRAIN_11E": 0.0})
	_ovr_unset(ov)

func _test_anti_tank_branch() -> void:
	print("\n-- anti_tank has a terrain arm --")
	var tall := {"type": "ruins", "height_category": "tall"}
	var zb := {"min_x": 40.0, "max_x": 1720.0, "min_y": 10.0, "max_y": 470.0}
	AIDecisionMaker.take_param_reads()
	var s := AIDecisionMaker._score_terrain_for_role(tall, "anti_tank", Vector2(400, 200), zb, true)
	var reads: Dictionary = AIDecisionMaker.take_param_reads()
	_check(s > 0.0 and is_equal_approx(s, 3.5), "anti_tank on tall ruins = 2.5 + 1.0 (got %.2f; 0 before)" % s)
	_check(reads.has("DEPLOY_TERRAIN_ANTITANK_COVER") and reads.has("DEPLOY_TERRAIN_ANTITANK_LOS_BLOCK"), "the ANTITANK weights are read through get_param")
	_ovr_set({"FIX_DEPLOY_TERRAIN_11E": 0.0})
	var s0 := AIDecisionMaker._score_terrain_for_role(tall, "anti_tank", Vector2(400, 200), zb, true)
	_ovr_unset({"FIX_DEPLOY_TERRAIN_11E": 0.0})
	_check(is_equal_approx(s0, 0.0), "FIX_DEPLOY_TERRAIN_11E = 0 keeps the old missing arm (got %.2f)" % s0)

func _test_pocket_fill_unit_math() -> void:
	print("\n-- pocket fill: seed, capacity, characters --")
	var pocket := PackedVector2Array([Vector2(0, 0), Vector2(400, 0), Vector2(400, 300), Vector2(0, 300)])
	var r := 25.0
	var fill: Dictionary = AIDecisionMaker._deploy_pocket_fill([pocket], [r, r, r, r, r], 5, [], [])
	_check(not fill.is_empty() and (fill.positions as Array).size() == 5, "a 10x7.5\" pocket takes 5 x 32mm")
	if not fill.is_empty():
		# the seed is the lattice point deepest inside the pocket
		var pitch := 2.0 * r + 10.0
		var best := -1.0
		var row := 0
		var y := 0.0
		while y <= 300.01:
			var x := 0.0 + (pitch * 0.5 if row % 2 == 1 else 0.0)
			while x <= 400.01:
				var q := Vector2(x, y)
				if Geometry2D.is_point_in_polygon(q, pocket):
					best = maxf(best, AIDecisionMaker._dist_to_boundary_px(q, pocket))
				x += pitch
			y += pitch * 0.8660254
			row += 1
		var p0: Vector2 = fill.positions[0]
		_check(is_equal_approx(AIDecisionMaker._dist_to_boundary_px(p0, pocket), best) and p0 == fill.seed, "positions[0] is the deepest lattice point (%.1f px from the edge)" % best)
		var coherent := true
		for i in range(1, 5):
			var near := INF
			for j in range(5):
				if i != j:
					near = minf(near, (fill.positions[i] as Vector2).distance_to(fill.positions[j]) - 2.0 * r)
			if near > 80.0 or near < 0.0:
				coherent = false
		_check(coherent, "every fill model is within 2\" of another and overlaps none")
	var tiny := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)])
	_check(AIDecisionMaker._deploy_pocket_fill([tiny], [r, r, r, r, r], 5, [], []).is_empty(), "a pocket too small for the unit gives no fill (never a partial one)")
	var mixed: Dictionary = AIDecisionMaker._deploy_pocket_fill([pocket], [r, r, r, r, r, 39.4], 5, [], [], pocket)
	var ok_mixed := not mixed.is_empty() and (mixed.positions as Array).size() == 6
	if ok_mixed:
		var c: Vector2 = mixed.positions[5]
		var linked := false
		for j in range(5):
			var gap: float = c.distance_to(mixed.positions[j]) - 39.4 - r
			if gap < 5.9:
				ok_mixed = false
			if gap <= 70.1:
				linked = true
		ok_mixed = ok_mixed and linked and AIDecisionMaker._dist_to_boundary_px(c, pocket) >= 39.4 - 0.01
	_check(ok_mixed, "an attached 50mm character gets its own clear spot within 1.75\" of the bodyguard, inside the zone")

# -----------------------------------------------------------------------------
# picker on live fixtures
# -----------------------------------------------------------------------------

func _pick_for(uid: String, player: int) -> Dictionary:
	_as_player(player)
	var snap = GS.create_snapshot(false)
	var unit: Dictionary = snap.units[uid]
	var zb: Dictionary = AIDecisionMaker._get_deployment_zone_bounds(snap, player)
	var fr: Dictionary = AIDecisionMaker._deployment_frame(snap, player)
	var objs: Array = AIDecisionMaker._get_objectives(snap)
	var role := AIDecisionMaker._classify_deployment_role(unit)
	var feats: Array = snap.board.terrain_features
	var pick: Dictionary = AIDecisionMaker._find_terrain_spot_11e(fr.inner, role, unit, uid, feats, zb, fr, objs, snap, player)
	return {"pick": pick, "snapshot": snap, "frame": fr, "unit": unit, "role": role}

func _test_candidates_only_from_area_groups() -> void:
	print("\n-- candidates come from terrain AREA groups only --")
	if not await _load("asym_2000_predeploy", "fixture", 7):
		return
	_check(AIDecisionMaker._deploy_11e_active(GS.create_snapshot(false).board.terrain_features), "the 11e picker is active on the live fixture")
	var a := _pick_for("U_ALLARUS_CUSTODIANS_A", 1)
	var b := _pick_for("U_ALLARUS_CUSTODIANS_A", 1)
	var gm: Dictionary = TMN.build_area_group_map(TMN.terrain_features)
	var values := {}
	for pid in gm:
		values[str(gm[pid])] = true
	var piece_class := {}
	for p in TMN.terrain_features:
		piece_class[str(p.get("id", ""))] = str(p.get("piece_class", ""))
	var groups: Dictionary = {}
	for g in AIDecisionMaker._deploy_area_groups(TMN.terrain_features):
		groups[str(g.key)] = g
	var all_c: Array = (a.pick.ranked as Array) + (a.pick.below_bar as Array)
	var keys_ok := true
	var area_ok := true
	for cd in all_c:
		if not values.has(str(cd.key)):
			keys_ok = false
		var g: Dictionary = groups.get(str(cd.key), {})
		var has_area := false
		for pid in g.get("ids", []):
			if piece_class.get(pid, "") != "feature":
				has_area = true
		if not has_area:
			area_ok = false
	_check(not all_c.is_empty(), "Allarus Custodians get terrain candidates (%d ranked, %d under the bar)" % [(a.pick.ranked as Array).size(), (a.pick.below_bar as Array).size()])
	_check(keys_ok, "every candidate's group key is a VALUE of build_area_group_map (an area id or a link group)")
	_check(area_ok, "every candidate's group contains a terrain AREA piece (no wall / gantry feature on its own)")
	var same: bool = (a.pick.ranked as Array).size() == (b.pick.ranked as Array).size() and (a.pick.below_bar as Array).size() == (b.pick.below_bar as Array).size()
	if same:
		for i in range((a.pick.ranked as Array).size()):
			if not is_equal_approx(float(a.pick.ranked[i].score), float(b.pick.ranked[i].score)) or (a.pick.ranked[i].anchor as Vector2) != (b.pick.ranked[i].anchor as Vector2):
				same = false
	_check(same, "the same candidates, scores and anchors on a second call")
	var inside := 0
	for cd in a.pick.ranked:
		if str(cd.rel) == "inside":
			inside += 1
	_check(inside >= 1, "at least one INSIDE dense spot for a hide-capable unit (%d)" % inside)

func _test_cross_parented_features_do_not_move_anchors() -> void:
	print("\n-- group geometry from AREA polygons only (cross-parented features) --")
	# take_and_hold_mirror_1 (the asym fixture's layout) parents some wall
	# features to an area far away (corner-short-9..12 -> area-medium-7 / -8,
	# ~37" apart; layout data fix tracked separately, D8). Anchors must stay by
	# the AREA whatever the data says.
	var groups: Array = AIDecisionMaker._deploy_area_groups(TMN.terrain_features)
	var cross := 0
	for g in groups:
		for fp in g.feature_polys:
			var far := true
			for ap in g.area_polys:
				for v in fp:
					if AIDecisionMaker._dist_point_polygon_px(v, ap) <= 400.0:
						far = false
			if far:
				cross += 1
	print("  cross-parented feature polygons (> 10\" from their own area): %d" % cross)
	for spec in [["U_STOMPA_A", 2], ["U_WARBIKERS_C", 2], ["U_ALLARUS_CUSTODIANS_A", 1]]:
		var info := _pick_for(str(spec[0]), int(spec[1]))
		var by: Dictionary = {}
		for g in groups:
			by[str(g.key)] = g
		var worst := 0.0
		var n := 0
		for cd in (info.pick.ranked as Array) + (info.pick.below_bar as Array):
			if str(cd.rel) != "behind":
				continue
			n += 1
			var d := INF
			for ap in by[str(cd.key)].area_polys:
				d = minf(d, AIDecisionMaker._dist_point_polygon_px(cd.anchor, ap))
			worst = maxf(worst, d)
		_check(n == 0 or worst <= 12.0 * 40.0, "%s P%d: %d behind anchors, all within 12\" of their own area (worst %.1f\")" % [str(spec[0]), int(spec[1]), n, worst / 40.0])

func _test_inside_fill_hidden_and_legal() -> void:
	print("\n-- the top inside spot builds legally and every model is Hidden --")
	var info := _pick_for("U_ALLARUS_CUSTODIANS_A", 1)
	var top: Dictionary = {}
	for cd in info.pick.ranked:
		if str(cd.rel) == "inside":
			top = cd
			break
	if top.is_empty():
		_check(false, "an inside spot exists for Allarus Custodians")
		return
	var res: Dictionary = AIDecisionMaker._deploy_build_spot(top, info.snapshot, 1, "U_ALLARUS_CUSTODIANS_A", info.unit, 3000, 8000, 80.0)
	_check(bool(res.ok), "the inside spot builds (%s)" % str(res.get("reason", "")))
	if not bool(res.ok):
		return
	var b: Dictionary = res.built
	var pos: Array = b.model_positions
	var hidden := 0
	var inside_dense := 0
	for p in pos:
		if p == null:
			continue
		if AIDecisionMaker._position_would_be_hidden(info.unit, p, 40):
			hidden += 1
		for ap in top.inside_polys:
			if Geometry2D.is_point_in_polygon(p, ap):
				inside_dense += 1
				break
	_check(hidden == 5, "all 5 models Hidden by the engine's 13.09 predicate (%d)" % hidden)
	_check(inside_dense == 5, "every model centre is inside an area polygon of the dense group (%d)" % inside_dense)
	var errs: Array = FB.final_check(info.snapshot, 1, "U_ALLARUS_CUSTODIANS_A", pos, b.model_rotations, b.get("combined_char_data", {}))
	_check(errs.is_empty(), "the phase's own validation accepts it (%s)" % str(errs))
	_check(str(b.template) == "seed" and (pos[0] as Vector2) == (top.fill[0] as Vector2), "the pocket fill went through verbatim as the builder's seed (template %s)" % str(b.template))

func _test_behind_spots_for_non_hide_units() -> void:
	print("\n-- non-hide-capable units: behind spots only --")
	for spec in [["U_STOMPA_A", 2], ["U_WARBIKERS_A", 2], ["U_DEFFKILLA_WARTRIKE_A", 2]]:
		var uid := str(spec[0])
		var pl := int(spec[1])
		var info := _pick_for(uid, pl)
		var fwd: Vector2 = info.frame.fwd
		_check(int(info.pick.n_inside) == 0, "%s: no inside spot (not INFANTRY / BEASTS / SWARM)" % uid)
		var groups: Dictionary = {}
		for g in AIDecisionMaker._deploy_area_groups(TMN.terrain_features):
			groups[str(g.key)] = g
		var behind_ok := true
		var shadow_ok := true
		var n := 0
		for cd in info.pick.ranked:
			n += 1
			var g: Dictionary = groups[str(cd.key)]
			var c0 := Vector2.ZERO
			for ap in g.area_polys:
				c0 += AIDecisionMaker._polygon_centroid_px(ap)
			c0 /= float((g.area_polys as Array).size())
			if ((cd.anchor as Vector2) - c0).dot(fwd) >= 0.0:
				behind_ok = false
			if float(cd.shadow) < 0.25:
				shadow_ok = false
		_check(n > 0, "%s: %d behind spots" % [uid, n])
		_check(behind_ok, "%s: every behind anchor is on the side of its area away from the enemy" % uid)
		_check(shadow_ok, "%s: every behind spot blocks >= 25%% of the enemy-front sight lines" % uid)
		var built := 0
		var clear := true
		for i in range(mini(3, (info.pick.ranked as Array).size())):
			var cd: Dictionary = info.pick.ranked[i]
			var res: Dictionary = AIDecisionMaker._deploy_build_spot(cd, info.snapshot, pl, uid, info.unit, 3000, 8000, 80.0)
			if not bool(res.ok):
				continue
			built += 1
			# The builder's own bounding circles (an oval's is half its length).
			var slots: Array = FB.model_slots(info.snapshot, pl, uid).slots
			for sl in slots:
				if bool(sl.is_char):
					continue
				var p = res.built.model_positions[int(sl.idx)]
				if p == null:
					continue
				for ap in groups[str(cd.key)].area_polys:
					if FB._circle_overlaps_polygon(p, float(sl.r_out) - 0.5, ap):
						clear = false
		_check(built > 0, "%s: at least one of the top 3 behind spots builds (%d)" % [uid, built])
		_check(clear, "%s: no built model's bounding circle overlaps its area (so the area obscures it)" % uid)

func _check_record(rec: Dictionary, tag: String, final_positions: Array) -> void:
	var cands: Array = rec.get("candidates", [])
	var chosen := int(rec.get("chosen_index", -1))
	_check(cands.size() >= 2, "%s: the record lists >= 2 options (%d)" % [tag, cands.size()])
	if chosen < 0 or chosen >= cands.size():
		_check(false, "%s: the record has a chosen option" % tag)
		return
	var best_eligible := -INF
	for c in cands:
		if bool(c.get("eligible", true)):
			best_eligible = maxf(best_eligible, float(c.score))
	_check(float(cands[chosen].score) >= best_eligible - 1e-6, "%s: the chosen option has the best score among ELIGIBLE options (%.2f vs %.2f)" % [tag, float(cands[chosen].score), best_eligible])
	var ledger_ok := true
	for c in cands:
		var bd: Dictionary = c.get("score_breakdown", {})
		var s := 0.0
		for k in bd:
			s += float(bd[k])
		if absf(s - float(c.score)) > 0.01:
			ledger_ok = false
	_check(ledger_ok, "%s: every option's terms add up to its score" % tag)
	var ctx: Dictionary = rec.get("context", {})
	var c0 := Vector2.ZERO
	var n := 0
	for p in final_positions:
		if p != null:
			c0 += (p as Vector2) if p is Vector2 else Vector2(float(p.x), float(p.y))
			n += 1
	if n > 0:
		c0 /= float(n)
		var up = ctx.get("unit_pos", [0, 0])
		_check(Vector2(float(up[0]), float(up[1])).distance_to(c0) <= 0.5, "%s: context.unit_pos is the centroid of the final positions" % tag)
		var cp = cands[chosen].get("pos", [0, 0])
		_check(Vector2(float(cp[0]), float(cp[1])).distance_to(c0) <= 0.5, "%s: the chosen option's pos is the final centroid" % tag)
	for c in cands:
		if str(ctx.get("source", "")) != "terrain-aware placement":
			break
		if not bool(c.get("eligible", true)) and str(c.get("reason", "")) == "":
			_check(false, "%s: an ineligible option carries a reason (%s)" % [tag, str(c.description)])
			return

func _test_record_coherent_first_drop() -> void:
	print("\n-- the K-card record is written from the final positions --")
	if not await _load("asym_2000_predeploy", "fixture", 7):
		return
	var player := int(GS.get_active_player())
	var out := _decide_for(player, PM.get_available_actions())
	var d: Dictionary = out.decision
	var rec := _deployment_record(out.records)
	_check(not rec.is_empty(), "a deployment record was emitted for %s" % str(d.get("unit_id", "")))
	if rec.is_empty():
		return
	_check_record(rec, "asym first drop", d.get("model_positions", []))
	var ctx: Dictionary = rec.context
	var chosen: Dictionary = rec.candidates[int(rec.chosen_index)]
	print("  first drop: %s -> %s" % [str(d.get("_ai_description", "")), str(chosen.description)])
	_check(str(ctx.get("source", "")) == "terrain-aware placement", "source is 'terrain-aware placement'")
	_check(str(chosen.description).begins_with("Inside "), "the chosen spot is an Inside spot (%s)" % str(chosen.description))
	_check((chosen.score_breakdown as Dictionary).has("deploy_hidden") and float(chosen.score_breakdown.deploy_hidden) > 0.0, "the chosen spot books the Whole-unit-Hidden term")
	_check(not ctx.has("override_reason"), "no higher-scoring option was skipped (no 'scored higher' banner)")
	var params: Dictionary = rec.get("parameters_used", {})
	_check(params.has("FIX_DEPLOY_TERRAIN_11E") and params.has("FIX_DEPLOY_FRAME") and params.has("DEPLOY_11E_HIDDEN_BONUS"),
		"parameters_used lists the P0.3 knobs it read")

func _test_record_when_no_terrain_spot_builds() -> void:
	print("\n-- no terrain spot builds: the record still has >= 2 options, chosen = best eligible --")
	if not await _load("asym_2000_predeploy", "fixture", 7):
		return
	_ovr_set({"DEPLOY_11E_MAX_BUILD_TRIES": 0})
	var player := int(GS.get_active_player())
	var out := _decide_for(player, PM.get_available_actions())
	_ovr_unset({"DEPLOY_11E_MAX_BUILD_TRIES": 0})
	var d: Dictionary = out.decision
	var rec := _deployment_record(out.records)
	_check(str(d.get("type", "")) in ["DEPLOY_UNIT", "COMPOSITE_DEPLOY"] and not bool(d.get("_ai_no_legal_formation", false)), "the unit is still deployed (column spot)")
	if rec.is_empty():
		_check(false, "a deployment record was emitted")
		return
	_check_record(rec, "no spot built", d.get("model_positions", []))
	var chosen: Dictionary = rec.candidates[int(rec.chosen_index)]
	var ineligible := 0
	for c in rec.candidates:
		if not bool(c.get("eligible", true)):
			ineligible += 1
	_check(str(chosen.key) == "baseline", "the column-layout spot is chosen (%s)" % str(chosen.description))
	_check(ineligible >= 1, "the skipped terrain spots are listed with eligible: false (%d)" % ineligible)
	_check(str(rec.context.get("override_reason", "")) != "", "context.override_reason explains why the higher-scoring spots were not used ('%s')" % str(rec.context.get("override_reason", "")))

func _test_flag_off_uses_legacy() -> void:
	print("\n-- FIX_DEPLOY_TERRAIN_11E = 0: the legacy picker and record --")
	if not await _load("asym_2000_predeploy", "fixture", 7):
		return
	_ovr_set({"FIX_DEPLOY_TERRAIN_11E": 0.0})
	var player := int(GS.get_active_player())
	var out := _decide_for(player, PM.get_available_actions())
	_ovr_unset({"FIX_DEPLOY_TERRAIN_11E": 0.0})
	var rec := _deployment_record(out.records)
	var any_inside := false
	var any_hidden := false
	var next_to := false
	for c in rec.get("candidates", []):
		if str(c.description).begins_with("Inside "):
			any_inside = true
		if str(c.description).begins_with("Next to "):
			next_to = true
		if (c.get("score_breakdown", {}) as Dictionary).has("deploy_hidden"):
			any_hidden = true
	_check(next_to and not any_inside and not any_hidden, "flag 0: 'Next to' candidates, no Inside spot, no deploy_hidden term")
	var out1 := _decide_for(player, PM.get_available_actions())
	var rec1 := _deployment_record(out1.records)
	var chosen1: Dictionary = rec1.candidates[int(rec1.chosen_index)] if not rec1.is_empty() else {}
	_check(str(chosen1.get("description", "")).begins_with("Inside "), "flag 1: the chosen spot is Inside (%s)" % str(chosen1.get("description", "")))

func _test_frame_flag_off_restores_old_baseline() -> void:
	print("\n-- FIX_DEPLOY_FRAME = 0 (with FIX_DEPLOY_TERRAIN_11E = 0): the pre-P0.3 column baseline --")
	if not await _load("mirror_orks_2000_predeploy", "dawn_of_war", 7):
		return
	var flags := {"FIX_DEPLOY_FRAME": 0.0, "FIX_DEPLOY_TERRAIN_11E": 0.0}
	_ovr_set(flags)
	var player := int(GS.get_active_player())
	var out := _decide_for(player, PM.get_available_actions())
	_ovr_unset(flags)
	var snap: Dictionary = out.snapshot
	var zb: Dictionary = AIDecisionMaker._get_deployment_zone_bounds(snap, player)
	var objs: Array = AIDecisionMaker._get_objectives(snap)
	var old_b := _old_baseline(zb, 0, AIDecisionMaker._get_units_for_player(snap, player).size(), _old_objective_pos(zb, objs))
	# The legacy picker keeps the column spot it started from (first drop: no
	# enemy deployed yet, so counter-deployment leaves it as is).
	var bl: Vector2 = AIDecisionMaker._deploy_terrain_choice.get("baseline", Vector2.INF)
	_check(bl != Vector2.INF and bl.distance_to(old_b) <= 0.01, "DoW first drop: the picker's column spot (%.1f, %.1f) == the old formula (%.1f, %.1f)" % [bl.x, bl.y, old_b.x, old_b.y])
	var fr: Dictionary = AIDecisionMaker._deployment_frame(snap, player)
	var new_b: Vector2 = AIDecisionMaker._frame_baseline(fr, zb, 0, AIDecisionMaker._get_units_for_player(snap, player).size(), _old_objective_pos(zb, objs)).pos
	_check(new_b.distance_to(old_b) > 40.0, "with the flag on the DoW baseline moves to the real front (%.0f px away)" % new_b.distance_to(old_b))

func _hide_tally(player: int) -> Dictionary:
	var out := {"multi": 0, "full_multi": 0, "leak": 0}
	for uid in GS.state.units:
		var u: Dictionary = GS.state.units[uid]
		if int(u.get("owner", 0)) != player or not DE.is_on_table(u) or not DE.is_hide_capable(u):
			continue
		var hc: Dictionary = DE.unit_hidden_counts(u)
		if int(hc.models) > 1:
			out.multi += 1
			if int(hc.hidden) == int(hc.models):
				out.full_multi += 1
		if int(hc.hidden) > 0 and int(hc.hidden) < int(hc.models):
			out.leak += 1
	return out

func _test_full_deployment_asym_no_leakers_and_determinism() -> void:
	print("\n-- full AI deployment, asym fixture: no partly Hidden units; deterministic --")
	if not await _load("asym_2000_predeploy", "fixture", 7):
		return
	var run1 := await _deploy_all()
	_check(bool(run1.ok), "deployment completed with every placement accepted (%d drops)" % (run1.drops as Array).size())
	var t1 := _hide_tally(1)
	var t2 := _hide_tally(2)
	_check(int(t1.leak) == 0 and int(t2.leak) == 0, "no partly Hidden unit on either side (leakers P1 %d, P2 %d)" % [int(t1.leak), int(t2.leak)])
	_check(int(t1.full_multi) >= 4, "P1: >= 4 of %d multi-model units fully Hidden (%d; the pre-P0.3 formula managed 1-2)" % [int(t1.multi), int(t1.full_multi)])
	_check(int(t1.full_multi) + int(t2.full_multi) >= 6, "both sides: >= 6 multi-model units fully Hidden (%d)" % (int(t1.full_multi) + int(t2.full_multi)))
	var audit: Dictionary = DE.audit_legality(GS.state)
	_check(int(audit.violations) == 0, "legality audit: 0 violations (%s)" % str(audit.problems))
	var records_ok := true
	for dr in run1.drops:
		var rec: Dictionary = dr.record
		if rec.is_empty() or (rec.get("candidates", []) as Array).size() < 2:
			records_ok = false
			print("  record missing / < 2 options for %s" % str(dr.unit_id))
	_check(records_ok, "every drop wrote a deployment record with >= 2 options")
	var rel_inside := 0
	for dr in run1.drops:
		if str(dr.relation) == "inside":
			var hc: Dictionary = _unit_hidden(str(dr.unit_id))
			if int(hc.hidden) != int(hc.models):
				records_ok = false
			rel_inside += 1
	_check(records_ok, "every unit set up 'inside' is fully Hidden on the board (%d units)" % rel_inside)
	# Determinism: the whole deployment again, same fixture and seed.
	if not await _load("asym_2000_predeploy", "fixture", 7):
		return
	var run2 := await _deploy_all()
	_check(str(run1.digest) == str(run2.digest), "a second run gives the identical board (%s vs %s)" % [str(run1.digest).substr(0, 8), str(run2.digest).substr(0, 8)])
	var same_records := (run1.drops as Array).size() == (run2.drops as Array).size()
	if same_records:
		for i in range((run1.drops as Array).size()):
			var r1: Dictionary = run1.drops[i].record
			var r2: Dictionary = run2.drops[i].record
			if int(r1.get("chosen_index", -1)) != int(r2.get("chosen_index", -2)) or (r1.get("candidates", []) as Array).size() != (r2.get("candidates", []) as Array).size():
				same_records = false
				break
			for j in range((r1.candidates as Array).size()):
				if str(r1.candidates[j].description) != str(r2.candidates[j].description) or not is_equal_approx(float(r1.candidates[j].score), float(r2.candidates[j].score)):
					same_records = false
	_check(same_records, "... and identical records (descriptions, scores, chosen index) for every drop")

func _test_perf_budget_orks() -> void:
	print("\n-- per-drop time, Ork mirror on Search and Destroy (both seats) --")
	if not await _load("mirror_orks_2000_predeploy", "search_and_destroy", 11):
		return
	var run := await _deploy_all()
	var ms: Array = []
	var worst := ""
	var worst_ms := 0.0
	for dr in run.drops:
		ms.append(float(dr.ms))
		if float(dr.ms) > worst_ms:
			worst_ms = float(dr.ms)
			worst = str(dr.unit_id)
	ms.sort()
	var n := ms.size()
	if n == 0:
		_check(false, "drops were timed")
		return
	print("  %d drops: p50 %.1f ms, p95 %.1f ms, max %.1f ms (%s)" % [n, ms[n / 2], ms[int(n * 0.95)], worst_ms, worst])
	_check(bool(run.ok) and int(run.forced) == 0, "deployment completed with every placement accepted, 0 forced reserves (%d)" % int(run.forced))
	_check(worst_ms < DROP_BUDGET_MS, "worst drop %.0f ms < %.0f ms (D10)" % [worst_ms, DROP_BUDGET_MS])
	var t1 := _hide_tally(1)
	var t2 := _hide_tally(2)
	_check(int(t1.leak) == 0 and int(t2.leak) == 0, "no partly Hidden unit (S&D: zones 12.7\" apart — Hidden is not worth points within 15\")")

func _test_bw_load_attached_leaders_and_transport() -> void:
	print("\n-- bw_load_deploy_pretrigger: attached Big Meks + a Battlewagon with embarked Gretchin --")
	if not await _load("bw_load_deploy_pretrigger", "fixture", 7):
		return
	var run := await _deploy_all()
	_check(bool(run.ok), "deployment completed with every placement accepted (%d drops)" % (run.drops as Array).size())
	var lootas_done := 0
	for dr in run.drops:
		var uid := str(dr.unit_id)
		if not (uid in ["U_LOOTAS_A", "U_LOOTAS_B"]):
			continue
		var want_char := "U_BIG_MEK_B" if uid == "U_LOOTAS_A" else "U_BIG_MEK_C"
		var ccd: Dictionary = dr.ccd
		_check(str(dr.type) == "COMPOSITE_DEPLOY" and ccd.has(want_char), "%s is set up together with %s (COMPOSITE_DEPLOY, %s)" % [uid, want_char, str(dr.relation)])
		lootas_done += 1
		if str(dr.relation) == "inside":
			var lh: Dictionary = _unit_hidden(uid)
			var ch: Dictionary = _unit_hidden(want_char)
			_check(int(lh.hidden) == int(lh.models) and int(ch.hidden) == int(ch.models),
				"%s inside: every Loota (%d/%d) AND the Big Mek (%d/%d) Hidden" % [uid, int(lh.hidden), int(lh.models), int(ch.hidden), int(ch.models)])
			var groups: Array = AIDecisionMaker._deploy_area_groups(TMN.terrain_features)
			var mek_pos = GS.state.units[want_char].models[0].position
			var mp := Vector2(float(mek_pos.x), float(mek_pos.y))
			var in_dense := false
			for g in groups:
				if str(g.category) != "dense":
					continue
				for ap in g.area_polys:
					if Geometry2D.is_point_in_polygon(mp, ap):
						in_dense = true
			_check(in_dense, "%s's Big Mek centre is inside a dense area polygon too (the inside constraint covers characters)" % uid)
	_check(lootas_done == 2, "both Lootas units with attached Big Meks were deployed by the AI (%d)" % lootas_done)
	var bw: Dictionary = GS.state.units["U_BATTLEWAGON_A"]
	_check(DE.is_on_table(bw), "Battlewagon Alpha is on the table")
	var emb_ok := true
	for gid in ["U_GRETCHIN_A", "U_GRETCHIN_B"]:
		var g: Dictionary = GS.state.units[gid]
		if str(g.get("embarked_in", "")) != "U_BATTLEWAGON_A" or DE.is_on_table(g):
			emb_ok = false
	_check(emb_ok, "Gretchin Alpha / Beta stay embarked in Battlewagon Alpha")
	var t1 := _hide_tally(1)
	var t2 := _hide_tally(2)
	_check(int(t1.leak) == 0 and int(t2.leak) == 0, "no partly Hidden unit (P1 %d, P2 %d)" % [int(t1.leak), int(t2.leak)])
	var audit: Dictionary = DE.audit_legality(GS.state)
	_check(int(audit.violations) == 0, "legality audit (attached units judged as one unit): 0 violations (%s)" % str(audit.problems))
