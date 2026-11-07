class_name DeploymentEval
extends RefCounted

## Deployment-quality metrics (docs/AI_DEPLOYMENT_PLAN.md §1.3 / §8).
##
## A pure READ of GameState-shaped data. Every rules question is answered by
## the engine's own predicates — TerrainManager.is_model_hidden (13.09),
## model_visible_11e + hidden_model_visible_to (06.01 / 13.10 / 13.11) and
## MissionManager.model_in_objective_range (14.01) — so the metrics can never
## disagree with what the game will actually enforce. Nothing here mutates
## state.
##
## Used by:
##   * tools/deploy_harness.py — before/after measurement across fixtures,
##     deployment maps and seeds (P0 of the deployment plan);
##   * tests/scenarios/sp/ai_deploy_p0_legal_formations.json — the windowed
##     gate that the AI deploys a full army with no forced reserves;
##   * headless unit tests.
##
## Autoloads are reached late-bound (same pattern as AIDecisionMaker) so this
## script compiles in `godot --headless --script` test mode.

const PX_PER_INCH: float = 40.0
const HIDE_KEYWORDS: Array = ["INFANTRY", "BEASTS", "SWARM"]
# GameStateData.UnitStatus values, mirrored so the script has no compile-time
# dependency on GameState's inner enum (UNDEPLOYED=0 … IN_RESERVES=7).
const STATUS_UNDEPLOYED: int = 0
const STATUS_IN_RESERVES: int = 7

static func _autoload(node_name: String):
	var main = Engine.get_main_loop()
	if main is SceneTree and main.root:
		return main.root.get_node_or_null(node_name)
	return null

static func _vec(pos) -> Vector2:
	if pos is Vector2:
		return pos
	if pos is Dictionary:
		return Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	return Vector2.INF

static func is_hide_capable(unit: Dictionary) -> bool:
	"""13.09: only INFANTRY/BEASTS/SWARM models can ever be Hidden."""
	var keywords: Array = unit.get("meta", {}).get("keywords", [])
	for kw in HIDE_KEYWORDS:
		if kw in keywords:
			return true
	return false

static func alive_placed_models(unit: Dictionary) -> Array:
	var out: Array = []
	for m in unit.get("models", []):
		if not (m is Dictionary):
			continue
		if not m.get("alive", true):
			continue
		if _vec(m.get("position", null)) == Vector2.INF:
			continue
		out.append(m)
	return out

static func is_on_table(unit: Dictionary) -> bool:
	var status := int(unit.get("status", STATUS_UNDEPLOYED))
	if status == STATUS_UNDEPLOYED or status == STATUS_IN_RESERVES:
		return false
	if str(unit.get("embarked_in", "")) not in ["", "<null>"] and unit.get("embarked_in", null) != null:
		return false
	return not alive_placed_models(unit).is_empty()

static func zone_polygon_px(state: Dictionary, player: int) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for zone in state.get("board", {}).get("deployment_zones", []):
		if not (zone is Dictionary) or int(zone.get("player", 0)) != player:
			continue
		for v in zone.get("poly", []):
			if v is Dictionary:
				poly.append(Vector2(float(v.get("x", 0.0)), float(v.get("y", 0.0))) * PX_PER_INCH)
			elif v is Vector2:
				poly.append(v * PX_PER_INCH)
		break
	return poly

static func _dist_to_polygon_px(p: Vector2, poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return INF
	if Geometry2D.is_point_in_polygon(p, poly):
		return 0.0
	var best := INF
	for i in range(poly.size()):
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, p.distance_to(q))
	return best

static func unit_hidden_counts(unit: Dictionary) -> Dictionary:
	"""{models, hidden} using the engine's own 13.09 predicate."""
	var tm = _autoload("TerrainManager")
	var models := alive_placed_models(unit)
	var hidden := 0
	if tm != null and tm.has_method("is_model_hidden"):
		for m in models:
			if tm.is_model_hidden(m, unit):
				hidden += 1
	return {"models": models.size(), "hidden": hidden}

static func unit_seen_by_enemy_units(state: Dictionary, unit: Dictionary, enemy_ids: Array) -> int:
	"""How many DEPLOYED enemy units have at least one model that can see at
	least one model of `unit` right now (06.01 visible + the 13.09 detection
	gate). Static positions only — it is the "before anyone moves" exposure."""
	var tm = _autoload("TerrainManager")
	if tm == null or not tm.has_method("model_visible_11e"):
		return -1
	var units: Dictionary = state.get("units", {})
	var targets := alive_placed_models(unit)
	var count := 0
	for eid in enemy_ids:
		var enemy: Dictionary = units.get(eid, {})
		var sees := false
		for em in alive_placed_models(enemy):
			for tmod in targets:
				if tm.model_visible_11e(em, tmod) and tm.hidden_model_visible_to(tmod, unit, em):
					sees = true
					break
			if sees:
				break
		if sees:
			count += 1
	return count

static func home_objective_occupied(state: Dictionary, player: int) -> Dictionary:
	"""Is any OC>0 model of `player` within its home objective (14.01 terrain
	objective range, via MissionManager)? Home = objective whose `zone` is this
	player's (MissionManager designations; ids do not encode the owner)."""
	var mm = _autoload("MissionManager")
	var zone_key := "player%d" % player
	var homes: Array = []
	for obj in state.get("board", {}).get("objectives", []):
		if obj is Dictionary and str(obj.get("zone", "")) == zone_key:
			homes.append(obj)
	if homes.is_empty() or mm == null or not mm.has_method("model_in_objective_range"):
		return {"known": false, "occupied": false, "ids": []}
	var ids: Array = []
	var occupied := false
	for obj in homes:
		ids.append(str(obj.get("id", "")))
		for uid in state.get("units", {}):
			var u: Dictionary = state.units[uid]
			if int(u.get("owner", 0)) != player or not is_on_table(u):
				continue
			var oc := int(u.get("meta", {}).get("stats", {}).get("objective_control", 1))
			if oc <= 0:
				continue
			for m in alive_placed_models(u):
				if mm.model_in_objective_range(m, obj):
					occupied = true
					break
			if occupied:
				break
	return {"known": true, "occupied": occupied, "ids": ids}

static func evaluate(state: Dictionary, player: int, opts: Dictionary = {}) -> Dictionary:
	"""Deployment-quality metrics for one player. opts:
	   visibility (bool, default false) — also count enemy units that can see
	     each unit (slow: model-pair LoS);
	   per_unit (bool, default false) — include one row per unit."""
	var want_vis: bool = bool(opts.get("visibility", false))
	var want_rows: bool = bool(opts.get("per_unit", false))
	var units: Dictionary = state.get("units", {})
	var enemy := 3 - player
	var enemy_zone := zone_polygon_px(state, enemy)
	var enemy_ids: Array = []
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) == enemy and is_on_table(u):
			enemy_ids.append(uid)

	var out := {
		"player": player,
		"units_total": 0, "on_table": 0, "in_reserves": 0, "reserves_points": 0,
		"undeployed": 0, "embarked": 0,
		"hide_capable": 0, "hide_capable_multi": 0,
		"fully_hidden": 0, "fully_hidden_multi": 0,
		"leakers": 0, "open": 0, "non_hideable": 0,
		"seen_by_enemy_units_any": -1,
		"min_gap_to_enemy_zone_in": -1.0,
		"rows": [],
	}
	var min_gap := INF
	var seen_any := 0
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) != player:
			continue
		out.units_total += 1
		var status := int(u.get("status", STATUS_UNDEPLOYED))
		if status == STATUS_IN_RESERVES:
			out.in_reserves += 1
			out.reserves_points += int(u.get("meta", {}).get("points", 0))
			continue
		if u.get("embarked_in", null) != null and str(u.get("embarked_in", "")) != "":
			out.embarked += 1
			continue
		if not is_on_table(u):
			out.undeployed += 1
			continue
		out.on_table += 1
		var models := alive_placed_models(u)
		var row := {"id": uid, "name": str(u.get("meta", {}).get("name", uid)), "models": models.size()}
		for m in models:
			min_gap = minf(min_gap, _dist_to_polygon_px(_vec(m.get("position")), enemy_zone))
		if is_hide_capable(u):
			var hc := unit_hidden_counts(u)
			out.hide_capable += 1
			if hc.models > 1:
				out.hide_capable_multi += 1
			if hc.hidden == hc.models and hc.models > 0:
				out.fully_hidden += 1
				if hc.models > 1:
					out.fully_hidden_multi += 1
				row["hidden"] = "full"
			elif hc.hidden > 0:
				out.leakers += 1
				row["hidden"] = "partial %d/%d" % [hc.hidden, hc.models]
			else:
				out.open += 1
				row["hidden"] = "none"
		else:
			out.non_hideable += 1
			row["hidden"] = "n/a"
		if want_vis:
			var seen := unit_seen_by_enemy_units(state, u, enemy_ids)
			row["seen_by"] = seen
			if seen > 0:
				seen_any += 1
		if want_rows:
			out.rows.append(row)
	if want_vis:
		out.seen_by_enemy_units_any = seen_any
	if min_gap < INF:
		out.min_gap_to_enemy_zone_in = snappedf(min_gap / PX_PER_INCH, 0.1)
	out["home_objective"] = home_objective_occupied(state, player)
	return out

static func count_forced_reserves(action_log: Array, player: int) -> int:
	"""Units the AI pushed into Strategic Reserves because no legal placement
	was found (AIPlayer._fallback_to_reserves) — never a reserves *decision*.
	Matches both the capped fallback and the past-the-caps stuck fallback."""
	var n := 0
	for e in action_log:
		if not (e is Dictionary):
			continue
		if int(e.get("player", 0)) != player:
			continue
		if str(e.get("action_type", "")) != "PLACE_IN_RESERVES":
			continue
		var d := str(e.get("description", ""))
		if d.contains("(fallback)") or d.contains("past the caps"):
			n += 1
	return n

const OVERLAP_PREFILTER_PX: float = 400.0   # 10": no two bases in the game touch from further apart

static func positions_digest(state: Dictionary) -> String:
	"""md5 over every unit's status, embarked_in, attached_to and every model's
	position / rotation, in unit-id order (0.1 px / 0.01 rad). Two equal
	digests = nothing on the board moved, appeared, embarked, attached or
	changed status in between."""
	var units: Dictionary = state.get("units", {})
	var ids: Array = units.keys()
	ids.sort()
	var parts := PackedStringArray()
	for uid in ids:
		var u: Dictionary = units[uid]
		var s := "%s:%d:%s:%s:" % [str(uid), int(u.get("status", STATUS_UNDEPLOYED)),
			str(u.get("embarked_in", "")), str(u.get("attached_to", ""))]
		for m in u.get("models", []):
			var p := _vec(m.get("position", null)) if m is Dictionary else Vector2.INF
			if p == Vector2.INF:
				s += "_;"
			else:
				s += "%.1f,%.1f,%.2f;" % [p.x, p.y, float(m.get("rotation", 0.0))]
		parts.append(s)
	return "|".join(parts).md5_text()

static func _audit_units(state: Dictionary, player: int) -> Array:
	"""On-table units (DeploymentEval.is_on_table: not undeployed, not in
	reserves, not embarked, at least one alive placed model) of `player`
	(0 = both). Embarked units have no table position and are not audited."""
	var out: Array = []
	var units: Dictionary = state.get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if player != 0 and int(u.get("owner", 0)) != player:
			continue
		if is_on_table(u):
			out.append(str(uid))
	out.sort()
	return out

static func _placed_copy(m: Dictionary) -> Dictionary:
	var mm: Dictionary = m.duplicate()
	mm["position"] = _vec(m.get("position", null))
	return mm

static func audit_legality(state: Dictionary, player: int = 0) -> Dictionary:
	"""Whole-board set-up legality after deployment, read-only. player = 0
	audits both sides. Checks every alive, placed model of every on-table unit
	(embarked / undeployed / reserve units are skipped) with the engine's own
	predicates — the ones DeploymentPhase validates a set-up with:
	  zone      Measurement.shape_wholly_in_polygon in the owner's zone — EXCEPT
	            for a unit with Infiltrators, which is judged as the phase judges
	            it (24.20, edition-aware distance from GameConstants): centre on
	            the battlefield, more than 8" (edge to edge, base_mm circle as in
	            the phase) from the enemy deployment zone and every enemy model.
	            An attached character counts as an Infiltrator only if it AND its
	            bodyguard have the ability (19.01 + 24.20);
	  wall      Measurement.model_overlaps_any_wall(model, its OWN unit's keywords);
	  board     Measurement.model_outside_board;
	  overlap   BaseShape.overlaps_with for every pair of models — within one
	            unit (the phase's intra-unit check, attached characters included)
	            and between units — tested in BOTH directions. That is stricter
	            than the phase, which tests only the newly placed model against
	            the existing one (and CircularBase vs a non-circle is a sampled,
	            asymmetric test). Pairs involving a unit the
	            SettingsService.unit_skips_collision override exempts are skipped,
	            as the phase skips them;
	  coherency AttackSequence.check_unit_coherency per coherency group
	            (AttackSequence.coherency_group_ids: an attached unit — bodyguard
	            plus characters — is judged as ONE unit, 19.01 + 03.03).
	Returns {models, zone, infiltrators, wall, board, overlap_pairs,
	incoherent_units, violations, problems (first 20, human-readable)}."""
	var meas = _autoload("Measurement")
	var gs = _autoload("GameState")
	var settings = _autoload("SettingsService")
	var out := {"models": 0, "zone": 0, "infiltrators": 0, "wall": 0, "board": 0, "overlap_pairs": 0,
		"incoherent_units": 0, "violations": 0, "problems": []}
	if meas == null:
		out["violations"] = -1
		out["problems"].append("Measurement autoload unavailable")
		return out
	var units: Dictionary = state.get("units", {})
	var audited := _audit_units(state, player)
	var infil_min: float = GameConstants.infiltrators_min_enemy_distance_inches()
	var entries: Array = []   # {uid, idx, model, shape, skip}
	for uid in audited:
		var u: Dictionary = units[uid]
		var owner := int(u.get("owner", 0))
		var poly := zone_polygon_px(state, owner)
		var kws: Array = u.get("meta", {}).get("keywords", [])
		var infil: bool = gs != null and gs.has_method("unit_has_infiltrators") and gs.unit_has_infiltrators(uid)
		var at = u.get("attached_to", null)
		if infil and at != null and str(at) != "":
			infil = gs.unit_has_infiltrators(str(at))
		var skip: bool = settings != null and settings.has_method("unit_skips_collision") and settings.unit_skips_collision(uid)
		var models: Array = u.get("models", [])
		for i in range(models.size()):
			var raw = models[i]
			if not (raw is Dictionary) or not raw.get("alive", true) or _vec(raw.get("position", null)) == Vector2.INF:
				continue
			var m := _placed_copy(raw)
			var pos: Vector2 = m.position
			var rot := float(m.get("rotation", 0.0))
			out.models += 1
			if infil:
				var why := _infiltrator_problem(state, owner, m, infil_min)
				if why != "":
					out.infiltrators += 1
					_problem(out, "%s m%d (Infiltrators) %s" % [uid, i, why])
			elif poly.size() >= 3 and not meas.shape_wholly_in_polygon(pos, m, rot, poly):
				out.zone += 1
				_problem(out, "%s m%d not wholly within the P%d zone" % [uid, i, owner])
			if meas.model_overlaps_any_wall(m, kws):
				out.wall += 1
				_problem(out, "%s m%d overlaps a wall / solid feature" % [uid, i])
			if meas.model_outside_board(pos, m):
				out.board += 1
				_problem(out, "%s m%d off the board" % [uid, i])
			entries.append({"uid": uid, "idx": i, "model": m, "shape": meas.create_base_shape(m), "skip": skip})
	for i in range(entries.size()):
		var a: Dictionary = entries[i]
		for j in range(i + 1, entries.size()):
			var b: Dictionary = entries[j]
			if a.skip or b.skip:
				continue
			var pa: Vector2 = a.model.position
			var pb: Vector2 = b.model.position
			if pa.distance_to(pb) > OVERLAP_PREFILTER_PX:
				continue
			var ra := float(a.model.get("rotation", 0.0))
			var rb := float(b.model.get("rotation", 0.0))
			if a.shape.overlaps_with(b.shape, pa, ra, pb, rb) or b.shape.overlaps_with(a.shape, pb, rb, pa, ra):
				out.overlap_pairs += 1
				_problem(out, "%s m%d overlaps %s m%d" % [a.uid, a.idx, b.uid, b.idx])
	var judged := {}
	for uid in audited:
		var group: Array = AttackSequence.coherency_group_ids(uid, units)
		var key := ",".join(group)
		if judged.has(key):
			continue
		judged[key] = true
		var models: Array = []
		for gid in group:
			if not units.has(gid) or not is_on_table(units[gid]):
				continue
			for raw in units[gid].get("models", []):
				if raw is Dictionary and raw.get("alive", true) and _vec(raw.get("position", null)) != Vector2.INF:
					models.append(_placed_copy(raw))
		if models.size() < 2:
			continue
		if not AttackSequence.check_unit_coherency({"models": models}).get("coherent", true):
			out.incoherent_units += 1
			_problem(out, "%s out of coherency%s" % [key, " (attached unit judged as one, 19.01)" if group.size() > 1 else ""])
	out["violations"] = int(out.zone) + int(out.infiltrators) + int(out.wall) + int(out.board) \
		+ int(out.overlap_pairs) + int(out.incoherent_units)
	return out

static func _infiltrator_problem(state: Dictionary, owner: int, m: Dictionary, min_in: float) -> String:
	"""DeploymentPhase._validate_infiltrators_position (24.20) — "" when legal."""
	var pos: Vector2 = m.position
	var size: Dictionary = state.get("board", {}).get("size", {})
	var w := float(size.get("width", 44)) * PX_PER_INCH
	var h := float(size.get("height", 60)) * PX_PER_INCH
	if pos.x < 0.0 or pos.x > w or pos.y < 0.0 or pos.y > h:
		return "is not on the battlefield"
	var r_in := (float(m.get("base_mm", 32)) / 2.0) / 25.4
	var ez := zone_polygon_px(state, 3 - owner)
	if ez.size() >= 3:
		if Geometry2D.is_point_in_polygon(pos, ez):
			return "is inside the enemy deployment zone"
		var best := INF
		for i in range(ez.size()):
			best = minf(best, pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, ez[i], ez[(i + 1) % ez.size()])))
		if best / PX_PER_INCH - r_in < min_in:
			return "is %.1f\" from the enemy deployment zone (needs more than %.0f\")" % [best / PX_PER_INCH - r_in, min_in]
	for uid in state.get("units", {}):
		var e: Dictionary = state.units[uid]
		if int(e.get("owner", 0)) == owner or not is_on_table(e):
			continue
		for em in alive_placed_models(e):
			var d := pos.distance_to(_vec(em.get("position"))) / PX_PER_INCH - r_in - (float(em.get("base_mm", 32)) / 2.0) / 25.4
			if d < min_in:
				return "is %.1f\" from enemy model %s m (needs more than %.0f\")" % [d, str(uid), min_in]
	return ""

static func _problem(out: Dictionary, text: String) -> void:
	if out.problems.size() < 20:
		out.problems.append(text)

# Deployment-type actions — the list AIPlayer.DEPLOY_ACTION_TYPES records
# (mirrored so this script has no compile-time dependency on the autoload).
const DEPLOY_ACTION_TYPES: Array = ["DEPLOY_UNIT", "COMPOSITE_DEPLOY", "EMBARK_UNITS_DEPLOYMENT",
	"PLACE_IN_RESERVES", "ATTACH_CHARACTER_DEPLOYMENT"]

static func count_rejected_deploy_actions(rejections: Array, player: int) -> int:
	"""THE rejected-placement gate metric (P0.4, plan §5.8): every deployment-type
	action AIPlayer routed that the game refused, as AIPlayer recorded it AT THE
	SOURCE (AIPlayer.get_deploy_rejections()) — the AI's own decision, every
	retry, the reserves fallback (capped and past the caps), the max-actions
	escape and accepted K-card suggestions alike, for every type in
	DEPLOY_ACTION_TYPES. Counted from structured records, so it does not depend on
	any log wording. player 0 = both seats."""
	var n := 0
	for rec in rejections:
		if not (rec is Dictionary):
			continue
		if player != 0 and int(rec.get("player", 0)) != player:
			continue
		if str(rec.get("action_type", "")) in DEPLOY_ACTION_TYPES:
			n += 1
	return n

static func count_failed_deploy_attempts(event_entries: Array, player: int) -> int:
	"""LEGACY game-log metric, kept so new runs stay comparable with the P0.0
	baseline (docs/ai_deployment_evidence/p0_baseline_harness.md, 298): units
	whose FIRST DEPLOY_UNIT / COMPOSITE_DEPLOY was refused, read from the line
	AIPlayer writes to the Game Log for it ("P<n>: <unit> deployment failed
	(<reason>) — retrying"). It does NOT see refused retries, a refused reserves
	fallback or a refused PLACE_IN_RESERVES / EMBARK_UNITS_DEPLOYMENT, and it
	depends on that wording — the gate metric is count_rejected_deploy_actions,
	which is always >= this one."""
	var n := 0
	var prefix := "P%d: " % player  # GameEventLog.add_ai_entry prefix
	for e in event_entries:
		var text := ""
		if e is Dictionary:
			text = str(e.get("text", ""))
		else:
			text = str(e)
		if text.begins_with(prefix) and text.contains("deployment failed ("):
			n += 1
	return n
