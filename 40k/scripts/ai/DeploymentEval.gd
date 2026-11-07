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

static func count_failed_deploy_attempts(event_entries: Array, player: int) -> int:
	"""Rejected DEPLOY_UNIT submissions logged by AIPlayer ("P<n>: <unit>
	deployment failed (<reason>) — retrying" in GameEventLog)."""
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
