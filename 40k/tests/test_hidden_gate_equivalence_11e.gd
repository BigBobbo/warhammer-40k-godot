extends SceneTree

# PERF refactor of the 13.09 HIDDEN gate — proof that it is RESULT-IDENTICAL.
#
# TerrainManager.hidden_model_visible_to used to compute the full per-pair
# detection range (detection_range_inches_for -> _obscured_by_dense_11e: group
# map + exclusions + 9 sight lines, ~1 ms) for every hidden pair. It now
# answers distance-first: the range is one of two values (with / without the
# 3" Gone to Ground term), so beyond `hi` is never visible, within `lo` always,
# and only in (lo, hi] is the dense-terrain check run. RulesEngine
# (_check_target_visibility, explain_target_ineligibility, unit_sight_line,
# PRECISION group visibility) and the ShootingController LoS fan compute the
# observer-independent half (hidden_gate_for) once per target model.
#
# This test embeds the OLD per-pair formula verbatim (_old_*) and compares it
# with the new code on thousands of seeded random model pairs — inside / out of
# light, dense and exposed terrain, datasheet "Detection Range X\"", shot and
# waived-shot records, intervening dense strips — and the hoisted RulesEngine
# loops against brute-force references built on the old gate.
#
# Usage: godot --headless --path . -s tests/test_hidden_gate_equivalence_11e.gd

const PX := 40.0
const BONUS_SCRIPTS := [
	"res://scripts/codex/orks/OrkAbilities11e.gd",
	"res://scripts/codex/custodes/CustodesAbilities.gd",
	"res://scripts/codex/space_wolves/SWAbilities11e.gd",
	"res://scripts/codex/space_marines/SMDetachmentsA.gd",
	"res://scripts/codex/space_marines/SMAbilitiesB.gd",
	"res://scripts/codex/space_marines/SMAbilitiesC.gd",
	"res://scripts/codex/space_marines/SMAbilitiesA.gd",
]

var passed := 0
var failed := 0
var _completed := false  # set by the last line of _run(): an aborted run (script error) counts as a failure
var TM = null
var RE = null
var GS = null
var MEAS = null

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

# --- the OLD gate, verbatim (pre-refactor TerrainManager) ---------------------

func _old_detection_range(model: Dictionary, unit: Dictionary, observer_model: Dictionary) -> float:
	var range_in: float = TM.detection_range_base_inches(unit)
	if TM.can_go_to_ground(unit) and TM._obscured_by_dense_11e(observer_model, model):
		range_in -= GameConstants.gone_to_ground_penalty_inches()
	for path in BONUS_SCRIPTS:
		range_in += load(path).detection_range_bonus(unit)
	return maxf(range_in, GameConstants.detection_range_floor_inches())

func _old_visible(model: Dictionary, unit: Dictionary, observer_model: Dictionary) -> bool:
	if not TM.is_model_hidden(model, unit):
		return true
	var det_px = MEAS.inches_to_px(_old_detection_range(model, unit, observer_model))
	return MEAS.model_to_model_distance_px(observer_model, model) <= det_px

# --- random boards --------------------------------------------------------------

func _rect(cx: float, cy: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(cx - w / 2, cy - h / 2), Vector2(cx + w / 2, cy - h / 2),
		Vector2(cx + w / 2, cy + h / 2), Vector2(cx - w / 2, cy + h / 2)])

func _model(id: String, p: Vector2, base_mm: int) -> Dictionary:
	return {"id": id, "alive": true, "base_mm": base_mm, "base_type": "circular",
		"position": {"x": p.x, "y": p.y}, "wounds": 1, "current_wounds": 1}

func _random_terrain(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for k in range(7):
		var t: String = ["ruins", "barricade", "crater", "woods", "ruins"][rng.randi_range(0, 4)]
		out.append({"id": "area_%d" % k, "type": t, "height_category": "tall" if t == "ruins" else "low",
			"polygon": _rect(rng.randf_range(250, 1500), rng.randf_range(250, 2150), rng.randf_range(120, 420), rng.randf_range(120, 420))})
	# thin dense strips: intervening Solid features (Gone to Ground)
	for k in range(6):
		out.append({"id": "strip_%d" % k, "type": "ruins", "height_category": "tall",
			"polygon": _rect(rng.randf_range(250, 1500), rng.randf_range(250, 2150), rng.randf_range(10, 30), rng.randf_range(40, 160))})
	return out

func _random_unit(rng: RandomNumberGenerator, uid: String, owner: int, center: Vector2, n: int) -> Dictionary:
	var kw_roll := rng.randi_range(0, 9)
	var kws: Array = ["INFANTRY"] if kw_roll < 6 else (["SWARM"] if kw_roll == 6 else (["VEHICLE"] if kw_roll == 7 else ["INFANTRY", "CHARACTER"]))
	var abilities: Array = []
	if rng.randf() < 0.25:
		abilities.append("Detection Range %d\"" % [9, 10, 12, 18][rng.randi_range(0, 3)])
	var flags := {}
	var r := rng.randf()
	if r < 0.12:
		flags["last_shot_idx"] = 4       # shot this turn
	elif r < 0.2:
		flags["last_shot_idx"] = 3       # shot the previous turn
	elif r < 0.25:
		flags["last_shot_idx"] = 2       # two turns ago: hidden again
	elif r < 0.35:
		flags["last_shot_idx"] = -100    # waived this turn: hidden, no Gone to Ground
		flags["last_ranged_attack_idx"] = 4
	var models: Array = []
	for i in range(n):
		models.append(_model("m%d" % i, center + Vector2(rng.randf_range(-90, 90), rng.randf_range(-90, 90)), [25, 32, 40][rng.randi_range(0, 2)]))
	return {"id": uid, "owner": owner, "status": 2, "flags": flags, "models": models,
		"meta": {"name": uid, "display_name": uid, "keywords": kws, "stats": {"toughness": 4, "save": 4},
			"abilities": abilities,
			"weapons": [{"id": "gun_%s" % uid, "name": "Gun %s" % uid, "type": "Ranged", "range": str([18, 24, 36][rng.randi_range(0, 2)]),
				"attacks": "1", "ballistic_skill": "3", "strength": "4", "ap": "0", "damage": "1"},
				{"id": "pistol_%s" % uid, "name": "Pistol %s" % uid, "type": "Ranged", "range": "12",
				"attacks": "1", "ballistic_skill": "3", "strength": "4", "ap": "0", "damage": "1"}]}}

func _center_of(piece: Dictionary) -> Vector2:
	var poly: PackedVector2Array = TM._to_packed_polygon(piece.get("polygon", PackedVector2Array()))
	var c := Vector2.ZERO
	for v in poly:
		c += v
	return c / float(maxi(poly.size(), 1))

# --- the gate itself ------------------------------------------------------------

func _section_gate() -> void:
	print("\n-- A. hidden_model_visible_to / hidden_gate_allows / detection_range_inches_for == the old per-pair formula --")
	var stats := {"pairs": 0, "not_hidden": 0, "hidden_vis": 0, "hidden_beyond": 0, "band": 0, "band_gtg": 0}
	var mismatches: Array = []
	var old_us := 0
	var new_us := 0
	for bi in range(12):
		var rng := RandomNumberGenerator.new()
		rng.seed = 7700 + bi
		if bi % 3 == 0:
			TM.load_terrain_layout(["take_and_hold_mirror_1", "take_and_hold_vs_reconnaissance_1", "search_and_destroy_mirror_1", "take_and_hold_mirror_1"][int(bi / 3)])
			if TM.terrain_features.is_empty():
				TM.terrain_features = _random_terrain(rng)
		else:
			TM.terrain_features = _random_terrain(rng)
		var feats: Array = TM.terrain_features
		for ui in range(8):
			# target unit centred inside a random terrain piece (mostly hidden)
			var piece: Dictionary = feats[rng.randi_range(0, feats.size() - 1)]
			var unit := _random_unit(rng, "T%d_%d" % [bi, ui], 2, _center_of(piece), rng.randi_range(1, 5))
			for tmod in unit.models:
				var tpos := Vector2(float(tmod.position.x), float(tmod.position.y))
				for oi in range(14):
					# observers concentrated around the 9-18" band
					var ang := rng.randf_range(0, TAU)
					var dist_in := rng.randf_range(6.0, 21.0)
					var obs := _model("o%d" % oi, tpos + Vector2(cos(ang), sin(ang)) * dist_in * PX, [25, 32, 40][rng.randi_range(0, 2)])
					var t0 := Time.get_ticks_usec()
					var old_v := _old_visible(tmod, unit, obs)
					var old_dr := _old_detection_range(tmod, unit, obs) if TM.is_model_hidden(tmod, unit) else -1.0
					var t1 := Time.get_ticks_usec()
					var new_v: bool = TM.hidden_model_visible_to(tmod, unit, obs)
					var t2 := Time.get_ticks_usec()
					var gate: Dictionary = TM.hidden_gate_for(tmod, unit)
					var gate_v: bool = TM.hidden_gate_allows(gate, tmod, obs)
					var new_dr: float = TM.detection_range_inches_for(tmod, unit, obs) if gate.get("hidden", false) else -1.0
					old_us += t1 - t0
					new_us += t2 - t1
					stats.pairs += 1
					if not gate.get("hidden", false):
						stats.not_hidden += 1
					else:
						var d: float = MEAS.model_to_model_distance_px(obs, tmod)
						if d > float(gate.lo_px) and d <= float(gate.hi_px):
							stats.band += 1
							if not old_v:
								stats.band_gtg += 1
						elif old_v:
							stats.hidden_vis += 1
						else:
							stats.hidden_beyond += 1
					if old_v != new_v or old_v != gate_v or old_dr != new_dr:
						if mismatches.size() < 8:
							mismatches.append("board %d unit %s model %s obs %s: old=%s new=%s gate=%s old_dr=%.3f new_dr=%.3f" % [
								bi, unit.id, tmod.id, str(obs.position), str(old_v), str(new_v), str(gate_v), old_dr, new_dr])
						else:
							mismatches.append("...")
	print("   pairs=%d not_hidden=%d hidden_visible=%d hidden_beyond=%d gone_to_ground_band=%d (of which refused by Gone to Ground %d)" % [
		stats.pairs, stats.not_hidden, stats.hidden_vis, stats.hidden_beyond, stats.band, stats.band_gtg])
	print("   time: old per-pair formula %.0f ms, new distance-first gate %.0f ms" % [old_us / 1000.0, new_us / 1000.0])
	_check("%d random model pairs: new gate == old formula (visible + detection range), 0 mismatches" % stats.pairs, mismatches.is_empty(), str(mismatches))
	_check("the sample covers every branch (not hidden / hidden in range / beyond / Gone to Ground band)",
		stats.not_hidden >= 200 and stats.hidden_vis >= 200 and stats.hidden_beyond >= 200 and stats.band >= 50 and stats.band_gtg >= 10, str(stats))
	_check("the distance-first gate is faster than the old per-pair formula (%.0f vs %.0f ms)" % [new_us / 1000.0, old_us / 1000.0], new_us < old_us)

# --- the hoisted RulesEngine loops ----------------------------------------------

func _ref_check_target_visibility(actor: Dictionary, target: Dictionary, range_in: float, board: Dictionary) -> bool:
	var range_px: float = MEAS.inches_to_px(range_in)
	for am in actor.models:
		if not am.get("alive", true):
			continue
		for tmod in target.models:
			if not tmod.get("alive", true):
				continue
			if MEAS.model_to_model_distance_px(am, tmod) <= range_px:
				if not _old_visible(tmod, target, am):
					continue
				if RE._check_line_of_sight(RE._get_model_position(am), RE._get_model_position(tmod), board, am, tmod):
					return true
	return false

func _ref_has_los(actor: Dictionary, target: Dictionary, board: Dictionary) -> bool:
	for am in actor.models:
		if not am.get("alive", true):
			continue
		for tmod in target.models:
			if not tmod.get("alive", true):
				continue
			if not _old_visible(tmod, target, am):
				continue
			if RE._check_line_of_sight(RE._get_model_position(am), RE._get_model_position(tmod), board, am, tmod):
				return true
	return false

## The per-weapon loop of explain_target_ineligibility, pre-refactor, on the
## old gate: [any_in_range, any_in_los, any_hidden_blocked, min_dist, det_range].
func _ref_explain_numbers(actor_id: String, target: Dictionary, board: Dictionary) -> Array:
	var actor: Dictionary = board.units[actor_id]
	var any_in_range := false
	var any_in_los := false
	var any_hidden := false
	var min_d := INF
	var det := GameConstants.hidden_detection_range_inches()
	var uw: Dictionary = RE.get_unit_weapons(actor_id, board)
	for model_id in uw:
		for wid in uw[model_id]:
			var prof: Dictionary = RE.get_weapon_profile(wid, board)
			var range_px: float = MEAS.inches_to_px(prof.get("range", 12))
			for am in actor.models:
				if not am.get("alive", true):
					continue
				for tmod in target.models:
					if not tmod.get("alive", true):
						continue
					var dist: float = MEAS.model_to_model_distance_px(am, tmod)
					if dist <= range_px:
						any_in_range = true
						if RE._check_line_of_sight(RE._get_model_position(am), RE._get_model_position(tmod), board, am, tmod):
							if not _old_visible(tmod, target, am):
								any_hidden = true
								var d_in: float = MEAS.px_to_inches(dist)
								if d_in < min_d:
									min_d = d_in
									det = _old_detection_range(tmod, target, am)
							else:
								any_in_los = true
	return [any_in_range, any_in_los, any_hidden, min_d, det]

func _section_rules_engine() -> void:
	print("\n-- B. hoisted RulesEngine loops == brute-force references on the old gate --")
	GS.state["meta"]["battle_round"] = 2
	GS.state["meta"]["active_player"] = 1
	GS.state["meta"]["first_turn_player"] = 1
	var checked := {"vis": 0, "los": 0, "explain": 0, "hidden_codes": 0, "eligible": 0}
	var bad: Array = []
	for bi in range(16):
		var rng := RandomNumberGenerator.new()
		rng.seed = 9100 + bi
		if bi % 2 == 0:
			TM.load_terrain_layout("take_and_hold_mirror_1")
		else:
			TM.terrain_features = _random_terrain(rng)
		var feats: Array = TM.terrain_features
		var units := {}
		for ui in range(6):
			var c := Vector2(rng.randf_range(200, 1550), rng.randf_range(200, 2200))
			if ui >= 3:
				c = _center_of(feats[rng.randi_range(0, feats.size() - 1)])
			var u := _random_unit(rng, "U%d_%d" % [bi, ui], 1 if ui < 3 else 2, c, rng.randi_range(1, 5))
			# keep the per-weapon analysis reachable: no engagement anywhere
			units[u.id] = u
		var board := {"units": units, "terrain_features": TM.terrain_features, "meta": GS.state["meta"].duplicate(true)}
		RE.clear_los_memo()
		for aid in units:
			if int(units[aid].owner) != 1:
				continue
			var elig: Dictionary = RE.get_eligible_targets(aid, board)
			for tid in units:
				if int(units[tid].owner) != 2:
					continue
				var target: Dictionary = units[tid]
				var ex: Dictionary = RE.explain_target_ineligibility(aid, tid, board)
				if not str(ex.get("code", "")) in ["", "out_of_range", "hidden", "no_los"]:
					checked["skipped_" + str(ex.get("code", ""))] = int(checked.get("skipped_" + str(ex.get("code", "")), 0)) + 1
					continue  # an earlier gate (e.g. friendly engagement) answered first
				var uw: Dictionary = RE.get_unit_weapons(aid, board)
				var any_vis := false
				for mid in uw:
					for wid in uw[mid]:
						var prof: Dictionary = RE.get_weapon_profile(wid, board)
						var got: bool = RE._check_target_visibility(aid, tid, wid, board).visible
						var want := _ref_check_target_visibility(units[aid], target, float(prof.get("range", 12)), board)
						checked.vis += 1
						if got:
							any_vis = true
						if got != want:
							bad.append("vis %s->%s %s got=%s want=%s" % [aid, tid, wid, str(got), str(want)])
				checked.eligible += 1
				if elig.has(tid) != any_vis:
					bad.append("eligible %s->%s got=%s want=%s" % [aid, tid, str(elig.has(tid)), str(any_vis)])
				var sl: bool = RE.unit_sight_line(aid, tid, board, false).has_los
				checked.los += 1
				if sl != _ref_has_los(units[aid], target, board):
					bad.append("unit_sight_line %s->%s got=%s" % [aid, tid, str(sl)])
				var ref := _ref_explain_numbers(aid, target, board)
				var want_code := ""
				if not ref[0]:
					want_code = "out_of_range"
				elif not ref[1]:
					want_code = "hidden" if ref[2] else "no_los"
				checked.explain += 1
				if str(ex.get("code", "")) != want_code:
					bad.append("explain %s->%s code=%s want=%s" % [aid, tid, str(ex.get("code", "")), want_code])
				elif want_code == "hidden":
					checked.hidden_codes += 1
					if float(ex.get("closest_in", -1)) != float(ref[3]) or float(ex.get("detection_in", -1)) != float(ref[4]):
						bad.append("explain %s->%s numbers closest=%s/%s det=%s/%s" % [aid, tid, str(ex.get("closest_in")), str(ref[3]), str(ex.get("detection_in")), str(ref[4])])
	print("   checked: %s" % str(checked))
	_check("_check_target_visibility, get_eligible_targets, unit_sight_line and explain_target_ineligibility agree with the old-gate references (%d checks)" % (checked.vis + checked.los + checked.explain + checked.eligible),
		bad.is_empty(), str(bad.slice(0, 8)))
	_check("the RulesEngine sample includes Hidden refusals (%d)" % checked.hidden_codes, checked.hidden_codes >= 3, str(checked))

# --- the cost a hidden-beyond-detection target used to add --------------------

func _ms(c: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	c.call()
	return (Time.get_ticks_usec() - t0) / 1000.0

func _section_cost() -> void:
	print("\n-- C. a hidden target beyond detection range no longer costs ~1 ms per model pair --")
	# The review's bench: 20 Boyz inside the light area-medium-7 of
	# take_and_hold_mirror_1, ~17" from 5 Custodian Guard (24" spears).
	TM.load_terrain_layout("take_and_hold_mirror_1")
	var boyz: Array = []
	for r in range(4):
		for c in range(5):
			boyz.append(_model("b%d" % (r * 5 + c), Vector2(1140 + c * 50, 365 + r * 50), 32))
	var tgt := {"id": "U_BOYZ", "owner": 2, "flags": {}, "models": boyz, "meta": {"name": "Boyz", "display_name": "Boyz",
		"keywords": ["INFANTRY"], "stats": {"toughness": 5, "save": 5}, "weapons": [], "abilities": []}}
	var guard: Array = []
	for k in range(5):
		guard.append(_model("g%d" % k, Vector2(1140 + k * 50, 1240), 40))
	var cust := {"id": "U_CUST", "owner": 1, "flags": {}, "models": guard, "meta": {"name": "Custodian Guard", "display_name": "Custodian Guard",
		"keywords": ["INFANTRY"], "stats": {}, "abilities": [],
		"weapons": [{"id": "spear", "name": "spear", "type": "Ranged", "range": "24", "attacks": "1", "ballistic_skill": "3", "strength": "4", "ap": "0", "damage": "1"}]}}
	var board := {"units": {"U_CUST": cust, "U_BOYZ": tgt}, "terrain_features": TM.terrain_features, "meta": GS.state["meta"].duplicate(true)}
	var hidden_n := 0
	for m in boyz:
		if TM.is_model_hidden(m, tgt):
			hidden_n += 1
	_check("setup: all 20 Boyz are hidden in the light area (%d/20)" % hidden_n, hidden_n == 20)
	RE.clear_los_memo()
	var elig := {}
	var t_hidden := _ms(func(): elig.merge(RE.get_eligible_targets("U_CUST", board)))
	var why := {}
	var t_explain := _ms(func(): why.merge(RE.explain_target_ineligibility("U_CUST", "U_BOYZ", board)))
	_check("the hidden Boyz are not a legal target (code %s)" % str(why.get("code", "")), not elig.has("U_BOYZ") and str(why.get("code", "")) == "hidden")
	# What the old code paid at the very least: the old per-pair gate for every
	# in-range pair (get_eligible_targets ran it before each sight line). The
	# review measured 119-556 ms for this call before the refactor.
	var range_px: float = MEAS.inches_to_px(24.0)
	var in_range_pairs: Array = []
	for gm_ in guard:
		for bm in boyz:
			if MEAS.model_to_model_distance_px(gm_, bm) <= range_px:
				in_range_pairs.append([gm_, bm])
	var in_range := in_range_pairs.size()
	var t_old_gate := _ms(func():
		for pr in in_range_pairs:
			_old_visible(pr[1], tgt, pr[0]))
	print("   get_eligible_targets (hidden Boyz) %.1f ms vs the old per-pair gate alone %.1f ms over %d in-range pairs; explain %.1f ms" % [
		t_hidden, t_old_gate, in_range, t_explain])
	_check("get_eligible_targets costs less than half of what the old per-pair gate alone cost (%.1f vs %.1f ms)" % [t_hidden, t_old_gate],
		in_range >= 50 and t_hidden <= 0.5 * t_old_gate)

func _run() -> void:
	print("\n=== test_hidden_gate_equivalence_11e ===")
	TM = root.get_node("TerrainManager")
	RE = root.get_node("RulesEngine")
	GS = root.get_node("GameState")
	MEAS = root.get_node("Measurement")
	var prev_terrain = TM.terrain_features.duplicate(true)
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	GS.state["meta"]["battle_round"] = 2
	GS.state["meta"]["active_player"] = 1
	GS.state["meta"]["first_turn_player"] = 1
	_section_gate()
	_section_rules_engine()
	_section_cost()
	TM.terrain_features = prev_terrain
	GameConstants.edition = prev_edition
	_completed = true
