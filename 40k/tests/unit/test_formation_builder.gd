extends SceneTree

# FormationBuilder (docs/AI_DEPLOYMENT_PLAN.md P0.1) — legal-by-construction
# deployment formations. Every builder result is judged by the REAL
# DeploymentPhase.validate_action (COMPOSITE_DEPLOY for attached characters,
# with the new combined_char_data validation) — never by the builder itself.
#
#  A. unit types (3- and 6-bike 75 mm ovals, 6 Deffkoptas, 150 mm oval Wartrike,
#     180 mm Stompa, 11 Gretchin on mixed 32/25 mm, a synthetic 180x100 mm
#     rectangular transport, 6 bikes + an attached Wartrike) on the crucible
#     triangle and hammer_anvil, both seats, empty and crowded boards, at
#     several desired spots;
#  B. an INFANTRY bodyguard with a MOUNTED character aimed at a dense solid
#     piece: the character is judged with ITS OWN keywords (verdict P2 repro);
#  C. leader + support of different sizes and shapes: satellite slots sized
#     per character, the oval rotated although a round one is listed first;
#  D. cold vs warm cache determinism (same output after unrelated builds);
#  E. a unit with a dead model (index-aligned output, null for the dead model)
#     and a DEPLOYED unit's dead-but-positioned model as an obstacle;
#  F. COMPOSITE_DEPLOY validation: accepts the builder's output, refuses a
#     character out of coherency / in a wall / on its bodyguard / not attached
#     / missing; RC7: empty and partial DEPLOY_UNIT refused;
#  G. count budgets: max_evals 0 without growth fails with a reason, with
#     growth succeeds (grown) and is phase-legal;
#  H. a legacy pixel-`vertices` zone; Infiltrators kept more than 8" away;
#  I. a unit-level refusal (AIRCRAFT, 23.01) through the LIVE phase gate
#     aborts at once (no position search, no DEFECT).
#
# Run with: godot --headless --path . -s tests/unit/test_formation_builder.gd

const FIXTURE := "res://tests/saves/mirror_orks_2000_predeploy.w40ksave"
const LAYOUT_FOR_ZONE := {
	"crucible_of_battle": "take_and_hold_mirror_1",
	"hammer_anvil": "purge_the_foe_vs_priority_assets_3",
	"dawn_of_war": "take_and_hold_mirror_2",
	"search_and_destroy": "disruption_vs_priority_assets_3",
	"sweeping_engagement": "disruption_vs_disruption_3",
	"tipping_point": "disruption_vs_disruption_2",
}
const CASES := {
	"warbikers_3_oval75": "U_WARBIKERS_A",
	"warbikers_6_oval75": "U_WARBIKERS_C",
	"deffkoptas_6_oval75": "U_DEFFKOPTAS_A",
	"wartrike_oval150": "U_DEFFKILLA_WARTRIKE_A",
	"stompa_180mm_titanic": "U_STOMPA_A",
	"gretchin_11_mixed32_25": "U_GRETCHIN_A",
	"rect_180x100_transport": "U_WAZDAKKA_GUTSMEK_A",   # base rewritten to a 180x100 mm rectangle
	"warbikers_6_plus_wartrike": "U_WARBIKERS_D",        # Wartrike B attached (data-legal pairing)
}

var FB
var GS
var MEAS
var TM
var SL
var MM
var phase

var _pass_count := 0
var _fail_count := 0

func _init():
	create_timer(0.3).timeout.connect(_run)

func _run():
	print("\n=== FormationBuilder (P0.1) Tests ===\n")
	FB = load("res://scripts/ai/FormationBuilder.gd")
	GS = root.get_node_or_null("GameState")
	MEAS = root.get_node_or_null("Measurement")
	TM = root.get_node_or_null("TerrainManager")
	SL = root.get_node_or_null("SaveLoadManager")
	MM = root.get_node_or_null("MissionManager")
	if FB == null or GS == null or MEAS == null or TM == null or SL == null or MM == null:
		_assert(false, "FormationBuilder + autoloads reachable")
	else:
		phase = load("res://phases/DeploymentPhase.gd").new()
		root.add_child(phase)
		AIDecisionMaker._config_overrides["PLANS_ENABLED"] = 0.0
		var t0 := Time.get_ticks_msec()
		test_unit_type_matrix()
		test_mixed_keyword_pair_on_dense_blocker()
		test_leader_and_support_of_different_sizes()
		test_cold_vs_warm_cache_determinism()
		test_dead_models()
		test_composite_deploy_validation()
		test_budgets_and_growth()
		test_legacy_zone_and_infiltrators()
		test_unit_level_gate_abort()   # leaves the live phase in DEPLOYMENT
		test_aiplayer_retry_and_marker()
		print("\nTotal %d ms; builder stats %s" % [Time.get_ticks_msec() - t0, str(FB.stats())])
		GameConstants.edition = 11
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	print("ALL TESTS PASSED" if _fail_count == 0 else "SOME TESTS FAILED")
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

# --- board helpers ------------------------------------------------------------

func _board(zone_id: String) -> void:
	SL.load_game_from_file_path(FIXTURE)
	GameConstants.edition = 11
	if zone_id != "fixture":
		TM.load_terrain_layout(LAYOUT_FOR_ZONE[zone_id])
		GS.state["board"]["terrain_layout"] = LAYOUT_FOR_ZONE[zone_id]
		var zs: Array = DeploymentZoneData.get_zones(zone_id)
		var dz: Array = []
		for i in range(zs.size()):
			dz.append(zs[i] if zs[i] is Dictionary else {"player": i + 1, "poly": zs[i]})
		GS.state["board"]["deployment_zones"] = dz
		GS.state["meta"]["deployment_type"] = zone_id
		MM._setup_objectives_for_deployment(zone_id)
	AIDecisionMaker.set_ai_seed(7)
	for sfx in ["", "_P2"]:
		# synthetic: a rectangular 180x100 mm transport hull
		var u: Dictionary = GS.state.units["U_WAZDAKKA_GUTSMEK_A" + sfx]
		u.models[0]["base_type"] = "rectangular"
		u.models[0]["base_mm"] = 180
		u.models[0]["base_dimensions"] = {"length": 180, "width": 100}
		u.meta["keywords"] = ["VEHICLE", "TRANSPORT"]
		# synthetic: Wartrike B leads Warbikers D (data-legal pairing)
		GS.state.units["U_WARBIKERS_D" + sfx]["attachment_data"] = {"attached_characters": ["U_DEFFKILLA_WARTRIKE_B" + sfx]}
		GS.state.units["U_DEFFKILLA_WARTRIKE_B" + sfx]["attached_to"] = "U_WARBIKERS_D" + sfx

func _zone_poly(player: int) -> PackedVector2Array:
	return FB._zone_polygon_px(GS.state, player)

func _zone_point(player: int, fx: float, fy: float) -> Vector2:
	var poly := _zone_poly(player)
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for v in poly:
		mn = Vector2(minf(mn.x, v.x), minf(mn.y, v.y))
		mx = Vector2(maxf(mx.x, v.x), maxf(mx.y, v.y))
	return Vector2(lerpf(mn.x, mx.x, fx), lerpf(mn.y, mx.y, fy))

func _action(uid: String, res: Dictionary, player: int) -> Dictionary:
	var act := {"type": str(res.get("action_type", "DEPLOY_UNIT")), "unit_id": uid,
		"model_positions": res.model_positions, "model_rotations": res.model_rotations, "player": player}
	if not (res.get("combined_char_data", {}) as Dictionary).is_empty():
		act["combined_char_data"] = res.combined_char_data
	return act

func _judge(uid: String, player: int, res: Dictionary) -> Array:
	"""The phase's verdict on the action the AI would send ([] = legal)."""
	GS.set_active_player(player)
	if not res.get("ok", false):
		return ["builder: %s" % str(res.get("reason", ""))]
	var v: Dictionary = phase.validate_action(_action(uid, res, player).duplicate(true))
	return [] if v.get("valid", false) else v.get("errors", ["rejected"])

func _apply(uid: String, res: Dictionary, player: int) -> bool:
	GS.set_active_player(player)
	var act := _action(uid, res, player)
	if not phase.validate_action(act.duplicate(true)).get("valid", false):
		return false
	return phase.process_action(act.duplicate(true)).get("success", false)

func _crowd(except: Array) -> int:
	"""Deploy every other unit of both seats with the builder (at its zone's
	centre, so the board around the test spots really is crowded)."""
	var n := 0
	for uid in GS.state.units.keys():
		var base := str(uid).replace("_P2", "")
		var u: Dictionary = GS.state.units[uid]
		if base in except or u.get("attached_to", null) != null or int(u.get("status", 0)) != 0:
			continue
		var p := int(u.owner)
		GS.set_active_player(p)
		var res: Dictionary = FB.build_deployment(GS.create_snapshot(false), p, uid, _zone_point(p, 0.5, 0.5))
		if res.ok and _apply(uid, res, p):
			n += 1
	return n

func _add_unit(uid: String, owner: int, models: Array, keywords: Array, extra: Dictionary = {}) -> void:
	var ms: Array = []
	for i in range(models.size()):
		var m: Dictionary = models[i].duplicate()
		m["id"] = "m%d" % (i + 1)
		m["alive"] = m.get("alive", true)
		m["position"] = m.get("position", null)
		m["rotation"] = 0.0
		m["wounds"] = 1
		m["current_wounds"] = 1
		ms.append(m)
	var u := {"id": uid, "owner": owner, "status": 0, "models": ms,
		"meta": {"name": uid, "keywords": keywords, "abilities": [], "points": 50}}
	for k in extra:
		u[k] = extra[k]
	GS.state.units[uid] = u

func _circles(n: int, mm: int) -> Array:
	var out: Array = []
	for i in range(n):
		out.append({"base_mm": mm, "base_type": "circular"})
	return out

func _dense_blocker_in_zone(player: int) -> Dictionary:
	"""A dense solid feature (taller than 2") whose centre lies in the zone and
	blocks a MOUNTED base but not an INFANTRY one at that centre."""
	var poly := _zone_poly(player)
	for piece in TM.terrain_features:
		if not TM._is_solid_blocker_11e(piece, 2.0):
			continue
		var pp: PackedVector2Array = piece.get("polygon", PackedVector2Array())
		if pp.size() < 3:
			continue
		var c := Vector2.ZERO
		for v in pp:
			c += v
		c /= float(pp.size())
		c = (c / 20.0).round() * 20.0
		if not Geometry2D.is_point_in_polygon(c, poly) or not Geometry2D.is_point_in_polygon(c, pp):
			continue
		var probe := {"base_mm": 40, "base_type": "circular", "position": c, "rotation": 0.0}
		if MEAS.model_overlaps_any_wall(probe, ["MOUNTED", "CHARACTER"]) and not MEAS.model_overlaps_any_wall(probe, ["INFANTRY"]):
			return {"id": str(piece.get("id", "?")), "centre": c}
	return {}

# --- A. unit types ------------------------------------------------------------

func test_unit_type_matrix() -> void:
	print("\n--- A. unit types x maps x seats x empty/crowded ---")
	var total := 0
	var legal := 0
	var max_us := 0
	var max_case := ""
	for zone_id in ["fixture", "hammer_anvil"]:
		for cond in ["empty", "crowded"]:
			for seat in [1, 2]:
				_board(zone_id)
				if cond == "crowded":
					_crowd(CASES.values())
				for case_name in CASES:
					var uid: String = CASES[case_name] + ("" if seat == 1 else "_P2")
					var spots := [_zone_point(seat, 0.5, 0.5), _zone_point(seat, 0.2, 0.3 if seat == 1 else 0.7)]
					var bad: Array = []
					for spot in spots:
						var res: Dictionary = FB.build_deployment(GS.create_snapshot(false), seat, uid, spot)
						total += 1
						if int(res.get("us", 0)) > max_us:
							max_us = int(res.get("us", 0))
							max_case = "%s/%s/P%d/%s" % [zone_id, cond, seat, case_name]
						var errs := _judge(uid, seat, res)
						if errs.is_empty():
							legal += 1
						else:
							bad.append(str(errs))
					_assert(bad.is_empty(), "%s %s P%d %s: every build is phase-legal %s" % [zone_id, cond, seat, case_name, "" if bad.is_empty() else str(bad)])
	_assert(legal == total, "unit-type matrix: %d/%d builds phase-legal (worst %.0f ms: %s)" % [legal, total, max_us / 1000.0, max_case])

# --- B. character keywords ------------------------------------------------------

func test_mixed_keyword_pair_on_dense_blocker() -> void:
	print("\n--- B. INFANTRY bodyguard + MOUNTED character aimed at a dense blocker ---")
	var found := {}
	var used := ""
	for zone_id in ["fixture", "dawn_of_war", "hammer_anvil", "search_and_destroy", "sweeping_engagement", "tipping_point"]:
		_board(zone_id)
		found = _dense_blocker_in_zone(1)
		if not found.is_empty():
			used = zone_id
			break
	_assert(not found.is_empty(), "CONTROL: a dense piece in a P1 zone blocks a MOUNTED base but not an INFANTRY one (%s on %s)" % [str(found.get("id", "none")), used])
	if found.is_empty():
		return
	_add_unit("T_GUARD", 1, _circles(5, 40), ["INFANTRY"], {"attachment_data": {"attached_characters": ["T_RIDER"]}})
	_add_unit("T_RIDER", 1, _circles(1, 40), ["CHARACTER", "MOUNTED"], {"attached_to": "T_GUARD"})
	var snap: Dictionary = GS.create_snapshot(false)
	var ctx: Dictionary = FB._make_ctx(snap, 1, "T_GUARD", {})
	_assert(ctx.mlist.size() == 6 and ctx.mlist[5].kws.has("MOUNTED") and ctx.mlist[0]["class"] != ctx.mlist[5]["class"],
		"the character is judged with its own keywords: separate memo class (%s vs %s)" % [ctx.mlist[0]["class"], ctx.mlist[5]["class"]])
	var res: Dictionary = FB.build_deployment(snap, 1, "T_GUARD", found.centre)
	var errs := _judge("T_GUARD", 1, res)
	_assert(errs.is_empty() and str(res.get("action_type", "")) == "COMPOSITE_DEPLOY",
		"aimed at %s: COMPOSITE_DEPLOY accepted by the phase %s" % [found.id, str(errs)])
	if res.ok:
		var e: Dictionary = res.combined_char_data["T_RIDER"][0]
		var rider := {"base_mm": 40, "base_type": "circular", "position": Vector2(e.x, e.y), "rotation": float(e.rotation)}
		_assert(not MEAS.model_overlaps_any_wall(rider, ["CHARACTER", "MOUNTED"]),
			"the MOUNTED character is NOT on a dense solid piece (own keywords), at (%.0f, %.0f)" % [e.x, e.y])

# --- C. leader + support of different sizes ---------------------------------------

func test_leader_and_support_of_different_sizes() -> void:
	print("\n--- C. leader + support of different sizes (round listed first) ---")
	_board("hammer_anvil")
	_add_unit("T_MOB", 1, _circles(5, 32), ["INFANTRY"], {"attachment_data": {"attached_characters": ["T_MEK", "T_TRIKE"]}})
	_add_unit("T_MEK", 1, _circles(1, 50), ["CHARACTER", "INFANTRY"], {"attached_to": "T_MOB"})
	_add_unit("T_TRIKE", 1, [{"base_mm": 150, "base_type": "oval", "base_dimensions": {"length": 95.0, "width": 150.0}}],
		["CHARACTER", "MOUNTED"], {"attached_to": "T_MOB"})
	var snap: Dictionary = GS.create_snapshot(false)
	var ctx: Dictionary = FB._make_ctx(snap, 1, "T_MOB", {})
	var blocks: Array = FB._blocks(ctx)
	var any_rotated_trike := false
	var sized_ok := true
	var detail := ""
	for blk in blocks:
		for t in blk.variants:
			for j in range(5, 7):
				var he: Vector2 = FB._he(ctx.mlist[j].info, t.rots[j])
				var o: Vector2 = t.offs[j]
				# clearance between this character's footprint and the block's footprint
				var gap := maxf(maxf(blk.fmn.x - (o.x + he.x), (o.x - he.x) - blk.fmx.x), maxf(blk.fmn.y - (o.y + he.y), (o.y - he.y) - blk.fmx.y))
				if gap < FB.GAP_PX - 0.01 or gap > FB.GAP_PX + FB.RASTER_PX + 0.01:
					sized_ok = false
					detail = "%s char %d gap %.1f px" % [t.name, j, gap]
				if j == 6 and absf(sin(t.rots[j])) > 0.5:
					any_rotated_trike = true
	_assert(sized_ok, "each character's slot is sized from ITS OWN base: footprint gap within [GAP, GAP+raster] %s" % detail)
	_assert(any_rotated_trike, "the oval support character is offered at 90 degrees although the round leader is listed first")
	var res: Dictionary = FB.build_deployment(snap, 1, "T_MOB", _zone_point(1, 0.5, 0.5))
	var errs := _judge("T_MOB", 1, res)
	_assert(errs.is_empty() and res.combined_char_data.size() == 2,
		"5 x 32 mm + 50 mm leader + 150 mm oval support: one COMPOSITE_DEPLOY, phase-legal (%s) %s" % [str(res.get("template", "")), str(errs)])

# --- D. determinism -------------------------------------------------------------

func _sig(res: Dictionary) -> String:
	return "%s|%s|%s|%s|%d|%d|%s" % [str(res.ok), str(res.model_positions), str(res.model_rotations),
		str(res.combined_char_data), int(res.evals), int(res.fresh), str(res.template)]

func test_cold_vs_warm_cache_determinism() -> void:
	print("\n--- D. cold vs warm cache ---")
	_board("fixture")
	_crowd(["U_WARBIKERS_D", "U_DEFFKILLA_WARTRIKE_B", "U_GRETCHIN_A"])
	var snap: Dictionary = GS.create_snapshot(false)
	var spot := _zone_point(1, 0.5, 0.5)
	FB.clear_caches()
	var cold: Dictionary = FB.build_deployment(snap, 1, "U_WARBIKERS_D", spot)
	# unrelated builds warm every cache (other signatures, other spots, other seat)
	for uid in ["U_GRETCHIN_A", "U_GRETCHIN_A_P2", "U_WARBIKERS_D_P2"]:
		var p := 1 if not uid.ends_with("_P2") else 2
		for f in [0.2, 0.8]:
			FB.build_deployment(snap, p, uid, _zone_point(p, f, 0.5))
	var warm: Dictionary = FB.build_deployment(snap, 1, "U_WARBIKERS_D", spot)
	FB.clear_caches()
	var cold2: Dictionary = FB.build_deployment(snap, 1, "U_WARBIKERS_D", spot)
	_assert(cold.ok and _sig(cold) == _sig(warm) and _sig(cold) == _sig(cold2),
		"identical output (positions, rotations, characters, evals, fresh) cold, warm and cold again (%s, evals %d fresh %d)" % [str(cold.get("template", "")), int(cold.evals), int(cold.fresh)])

# --- E. dead models -------------------------------------------------------------

func test_dead_models() -> void:
	print("\n--- E. dead models ---")
	_board("hammer_anvil")
	var models := _circles(5, 32)
	models[2]["alive"] = false
	_add_unit("T_HURT", 1, models, ["INFANTRY"])
	var spot := _zone_point(1, 0.5, 0.5)
	var res: Dictionary = FB.build_deployment(GS.create_snapshot(false), 1, "T_HURT", spot)
	var aligned: bool = res.ok and res.model_positions.size() == 5 and res.model_positions[2] == null
	for i in [0, 1, 3, 4]:
		aligned = aligned and res.model_positions[i] != null
	_assert(aligned, "index-aligned output: 5 entries, null for the dead model 3, a position for the 4 alive ones")
	_assert(_judge("T_HURT", 1, res).is_empty(), "…and the phase accepts it")
	# A DEPLOYED unit whose DEAD model still has a position is an obstacle to the
	# phase (DeploymentPhase._position_overlaps_existing_models_shape counts it).
	var wreck := _circles(2, 60)
	wreck[0]["position"] = {"x": spot.x + 400.0, "y": spot.y}
	wreck[1]["alive"] = false
	wreck[1]["position"] = {"x": spot.x, "y": spot.y}
	_add_unit("T_WRECK", 1, wreck, ["VEHICLE"])
	GS.state.units["T_WRECK"]["status"] = 2
	GS.state.units.erase("T_HURT")
	_add_unit("T_SOLO", 1, _circles(1, 32), ["INFANTRY"])
	var probe := {"base_mm": 32, "base_type": "circular"}
	_assert(phase._position_overlaps_existing_models_shape(spot, probe, 0.0, "T_SOLO"),
		"CONTROL: the phase refuses a model on top of the dead-but-positioned model")
	var res2: Dictionary = FB.build_deployment(GS.create_snapshot(false), 1, "T_SOLO", spot)
	var p0: Vector2 = res2.model_positions[0] if res2.ok else spot
	_assert(res2.ok and p0.distance_to(spot) >= 47.0 and _judge("T_SOLO", 1, res2).is_empty(),
		"the builder avoids it too (placed %.1f\" from it) and the phase accepts" % (p0.distance_to(spot) / 40.0))

# --- F. COMPOSITE_DEPLOY validation + RC7 ---------------------------------------

func _composite_errors(base: Dictionary, uid: String, ccd: Dictionary) -> Array:
	var act: Dictionary = base.duplicate(true)
	act["combined_char_data"] = ccd
	GS.set_active_player(1)
	var v: Dictionary = phase.validate_action(act)
	return [] if v.get("valid", false) else v.get("errors", [])

func _has(errs: Array, needle: String) -> bool:
	for e in errs:
		if str(e).find(needle) >= 0:
			return true
	return false

func test_composite_deploy_validation() -> void:
	print("\n--- F. COMPOSITE_DEPLOY combined_char_data validation + RC7 ---")
	var found := {}
	for zone_id in ["fixture", "dawn_of_war", "hammer_anvil", "search_and_destroy", "sweeping_engagement", "tipping_point"]:
		_board(zone_id)
		found = _dense_blocker_in_zone(1)
		if not found.is_empty():
			break
	_add_unit("T_GUARD", 1, _circles(5, 40), ["INFANTRY"], {"attachment_data": {"attached_characters": ["T_RIDER"]}})
	_add_unit("T_RIDER", 1, _circles(1, 40), ["CHARACTER", "MOUNTED"], {"attached_to": "T_GUARD"})
	_add_unit("T_LONER", 1, _circles(1, 40), ["CHARACTER", "INFANTRY"])
	var spot := _zone_point(1, 0.5, 0.4)
	var res: Dictionary = FB.build_deployment(GS.create_snapshot(false), 1, "T_GUARD", spot)
	_assert(res.ok and _judge("T_GUARD", 1, res).is_empty(), "the builder's COMPOSITE_DEPLOY is accepted")
	if not res.ok:
		return
	var base := _action("T_GUARD", res, 1)
	var good: Dictionary = res.combined_char_data
	var e0: Dictionary = good["T_RIDER"][0]
	var far := Vector2(e0.x, e0.y) + Vector2(12.0 * 40.0, 0.0)
	if not Geometry2D.is_point_in_polygon(far, _zone_poly(1)):
		far = Vector2(e0.x, e0.y) - Vector2(12.0 * 40.0, 0.0)
	var errs := _composite_errors(base, "T_GUARD", {"T_RIDER": [{"model_idx": 0, "x": far.x, "y": far.y, "rotation": 0.0}]})
	_assert(_has(errs, "Attached unit coherency broken"), "a character 12\" from its bodyguard is refused (19.01 + 03.03) %s" % str(errs))
	var p0: Vector2 = res.model_positions[0]
	errs = _composite_errors(base, "T_GUARD", {"T_RIDER": [{"model_idx": 0, "x": p0.x + 10.0, "y": p0.y, "rotation": 0.0}]})
	_assert(_has(errs, "overlaps a model of its attached unit"), "a character on top of a bodyguard model is refused %s" % str(errs))
	errs = _composite_errors(base, "T_GUARD", {"T_LONER": [{"model_idx": 0, "x": e0.x, "y": e0.y, "rotation": 0.0}]})
	_assert(_has(errs, "is not attached"), "a character that is not attached to this bodyguard is refused %s" % str(errs))
	errs = _composite_errors(base, "T_GUARD", {"T_RIDER": []})
	_assert(_has(errs, "has no position"), "an attached character listed without its model is refused %s" % str(errs))
	if not found.is_empty():
		errs = _composite_errors(base, "T_GUARD", {"T_RIDER": [{"model_idx": 0, "x": found.centre.x, "y": found.centre.y, "rotation": 0.0}]})
		_assert(_has(errs, "walls"), "a MOUNTED character on a dense solid piece is refused with ITS OWN keywords (%s) %s" % [found.id, str(errs)])
	# RC7: an empty or partial DEPLOY_UNIT no longer validates.
	GS.set_active_player(1)
	var empty := {"type": "DEPLOY_UNIT", "unit_id": "T_GUARD", "model_positions": [], "model_rotations": []}
	_assert(not phase.validate_action(empty).get("valid", true), "RC7: an empty DEPLOY_UNIT is refused")
	var partial := {"type": "DEPLOY_UNIT", "unit_id": "T_GUARD", "model_positions": [res.model_positions[0]], "model_rotations": [0.0]}
	var pv: Dictionary = phase.validate_action(partial)
	_assert(not pv.get("valid", true) and _has(pv.get("errors", []), "Every alive model must be given a position"),
		"RC7: a partial DEPLOY_UNIT (1 of 5) is refused %s" % str(pv.get("errors", [])))
	# The phase processes the accepted composite: positions, rotations, DEPLOYED.
	_assert(_apply("T_GUARD", res, 1) and int(GS.state.units["T_RIDER"].status) == 2
		and Vector2(GS.state.units["T_RIDER"].models[0].position.x, GS.state.units["T_RIDER"].models[0].position.y).distance_to(Vector2(e0.x, e0.y)) < 0.01,
		"processing the COMPOSITE_DEPLOY sets the character where the builder put it, DEPLOYED")

# --- G. budgets -----------------------------------------------------------------

func test_budgets_and_growth() -> void:
	print("\n--- G. count budgets and the growth fallback ---")
	_board("fixture")
	_crowd(["U_WARBIKERS_C"])
	var snap: Dictionary = GS.create_snapshot(false)
	var spot := _zone_point(1, 0.5, 0.5)
	var no_grow: Dictionary = FB.build_deployment(snap, 1, "U_WARBIKERS_C", spot, {"max_evals": 0, "grow": false})
	_assert(not no_grow.ok and str(no_grow.reason).find("budget") >= 0, "max_evals 0 without growth: ok=false with a reason ('%s')" % str(no_grow.reason))
	var grown: Dictionary = FB.build_deployment(snap, 1, "U_WARBIKERS_C", spot, {"max_evals": 0})
	_assert(grown.ok and grown.grown and _judge("U_WARBIKERS_C", 1, grown).is_empty(),
		"max_evals 0 with growth: the model-by-model fallback gives a phase-legal 6-bike set-up (%.1f ms)" % (float(grown.get("us", 0)) / 1000.0))
	var tiny: Dictionary = FB.build_deployment(snap, 1, "U_WARBIKERS_C", spot, {"max_evals": 0, "max_fresh": 5})
	_assert(not tiny.ok and str(tiny.reason) != "", "max_fresh 5: the growth budget also ends in ok=false with a reason ('%s')" % str(tiny.reason).left(80))

# --- H. legacy zone + Infiltrators ------------------------------------------------

func test_legacy_zone_and_infiltrators() -> void:
	print("\n--- H. legacy pixel-vertices zone; Infiltrators ---")
	var snap := {"meta": {"deployment_type": ""}, "board": {"size": {"width": 44, "height": 60},
		"deployment_zones": [{"player": 1, "vertices": [{"x": 40, "y": 10}, {"x": 1720, "y": 10}, {"x": 1720, "y": 470}, {"x": 40, "y": 470}]},
			{"player": 2, "vertices": [{"x": 40, "y": 1930}, {"x": 1720, "y": 1930}, {"x": 1720, "y": 2390}, {"x": 40, "y": 2390}]}],
		"terrain_features": [], "objectives": []},
		"units": {"unit_1": {"owner": 1, "status": 0, "meta": {"name": "Test Guardsmen", "keywords": ["INFANTRY"]},
			"models": _circles(5, 25)}}}
	var res: Dictionary = FB.build_deployment(snap, 1, "unit_1", Vector2(880, 390))
	var inside: bool = res.ok
	for p in (res.model_positions if res.ok else []):
		if p.x < 40 or p.x > 1720 or p.y < 10 or p.y > 470:
			inside = false
	_assert(inside, "a zone given only as legacy pixel `vertices`: 5 positions, all inside it")
	_board("hammer_anvil")
	var uid := "U_STORMBOYZ_A"
	var abil: Array = GS.state.units[uid].meta.get("abilities", [])
	abil.append({"name": "Infiltrators"})
	GS.state.units[uid].meta["abilities"] = abil
	var front := _zone_point(1, 0.5, 1.0)
	var enemy: Dictionary = GS.state.units["U_MEK_A_P2"]
	enemy.models[0]["position"] = {"x": front.x, "y": front.y + 240.0}
	enemy["status"] = 2
	_assert(GS.unit_has_infiltrators(uid), "CONTROL: the unit now has Infiltrators")
	var r2: Dictionary = FB.build_deployment(GS.create_snapshot(false), 1, uid, front)
	var min_gap := INF
	for p in (r2.model_positions if r2.ok else []):
		if p != null:
			min_gap = minf(min_gap, p.distance_to(Vector2(front.x, front.y + 240.0)) / 40.0 - (32.0 / 25.4))
	_assert(r2.ok and _judge(uid, 1, r2).is_empty() and min_gap > 8.0,
		"Infiltrators: phase-legal and more than 8\" from an enemy model 6\" in front of the zone (closest %.2f\")" % min_gap)

# --- I. unit-level gate abort -----------------------------------------------------

func test_unit_level_gate_abort() -> void:
	print("\n--- I. a unit-level refusal through the LIVE phase gate aborts at once ---")
	_board("hammer_anvil")
	var pm = root.get_node("PhaseManager")
	pm.transition_to_phase(1)
	var uid := "U_DEFFKOPTAS_A"
	GS.state.units[uid].meta["keywords"] = GS.state.units[uid].meta.keywords + ["AIRCRAFT"]
	GS.set_active_player(1)
	_assert(GS.unit_must_start_in_reserves(uid), "CONTROL: the unit is AIRCRAFT at 11e (23.01)")
	FB.reset_stats()
	var snap: Dictionary = GS.create_snapshot(false)
	var t0 := Time.get_ticks_msec()
	var res: Dictionary = FB.build_deployment(snap, 1, uid, _zone_point(1, 0.5, 0.5))
	var ms := Time.get_ticks_msec() - t0
	var st: Dictionary = FB.stats()
	_assert(not res.ok and str(res.reason).find("AIRCRAFT") >= 0 and int(res.gate_rejections) == 0 and int(st.gate_rejections) == 0,
		"the live DeploymentPhase gate refuses AIRCRAFT: ok=false, no DEFECT rejection counted ('%s')" % str(res.reason).left(90))
	_assert(int(res.evals) <= 2 and ms < 1000, "…at once: %d evaluation(s), %d ms" % [int(res.evals), ms])
	var fake: Dictionary = snap.duplicate(true)
	fake.units["U_GRETCHIN_A"]["status"] = 7   # not the live state -> placement_errors judges it
	var r2: Dictionary = FB.build_deployment(fake, 1, uid, _zone_point(1, 0.5, 0.5))
	_assert(not r2.ok and str(r2.reason).find("AIRCRAFT") >= 0 and int(r2.evals) <= 2,
		"a hypothetical snapshot is judged by placement_errors, which refuses AIRCRAFT the same way")

# --- J. AIPlayer: the retry after a phase rejection, and the no-legal marker ------

func test_aiplayer_retry_and_marker() -> void:
	print("\n--- J. AIPlayer retry (one builder call, refused placement excluded) and the marker ---")
	var ai = root.get_node_or_null("AIPlayer")
	_assert(ai != null, "AIPlayer autoload reachable")
	if ai == null:
		return
	# The live phase is DEPLOYMENT (test I). A placement the phase refused — the
	# whole unit stacked on one point — is retried ONCE through the builder.
	var uid := "U_GRETCHIN_A"
	GS.set_active_player(1)
	_assert(int(GS.state.units[uid].status) == 0, "CONTROL: %s is undeployed" % uid)
	var spot := _zone_point(1, 0.5, 0.5)
	var bad: Array = []
	for i in range(GS.state.units[uid].models.size()):
		bad.append(spot)
	var refused := {"type": "DEPLOY_UNIT", "unit_id": uid, "model_positions": bad, "model_rotations": [], "player": 1}
	_assert(not root.get_node("PhaseManager").current_phase_instance.validate_action(refused.duplicate(true)).get("valid", true),
		"CONTROL: the live phase refuses the stacked placement")
	var deployed_signals: Array = []
	var cb := func(_p, u): deployed_signals.append(str(u))
	ai.ai_unit_deployed.connect(cb)
	ai._handle_failed_deployment(1, refused, "simulated rejection (test)")
	ai.ai_unit_deployed.disconnect(cb)
	var retried := false
	for e in ai.get_action_log():
		if str(e.get("description", "")).contains("(retry 1)") and str(e.get("description", "")).contains("Gretchin"):
			retried = true
	_assert(int(GS.state.units[uid].status) == 2 and retried and uid in deployed_signals,
		"the retry deployed the unit (status %d), logged 'Deployed … (retry 1)' and emitted ai_unit_deployed" % int(GS.state.units[uid].status))
	# The marker is a finding, never an action: accepting it as a suggestion refuses.
	var marker := {"type": "DEPLOY_UNIT", "unit_id": "U_STORMBOYZ_A", "model_positions": [], "_ai_no_legal_formation": true,
		"_ai_description": "No legal set-up for Stormboyz anywhere in the deployment zone"}
	var out: Dictionary = ai._run_accepted_suggestion(1, marker)
	_assert(not out.get("success", true) and str(out.get("error", "")).contains("No legal set-up")
		and int(GS.state.units["U_STORMBOYZ_A"].status) == 0,
		"accepting a 'no legal set-up' suggestion is refused and changes nothing ('%s')" % str(out.get("error", "")))
