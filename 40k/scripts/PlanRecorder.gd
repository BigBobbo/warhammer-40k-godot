extends RefCounted
class_name PlanRecorder

# PM-5 — turn a laid-out board into a `wh40k_ai_plan`.
#
# The Plan Editor (PM-4) leaves the session parked at the end of DEPLOYMENT with
# the author's army placed exactly where they want it. This file reads that live
# state back out and serialises it into the v1 plan format, so the AI can
# reproduce it later (PM-2a/PM-2b consume the result).
#
# Everything here is a STATIC function over a plain state Dictionary. That is
# deliberate, for the same reason PlanValidator avoids preloading
# DeploymentZoneData: a `-s` headless test has no autoloads in the tree during
# `_init()`, so anything that reaches for Measurement / TerrainManager /
# MissionManager at parse time cannot be tested headless. Terrain pieces are
# passed IN by the caller rather than pulled from TerrainManager for the same
# reason.
#
# What is read from where:
#   keys              -> PlanManager.resolve_game_identity + meta.game_config
#   deployment.order  -> state.phase_log, in dispatch order (PM-4 holds the
#                        DEPLOYMENT phase open, so the log is never committed to
#                        history and still holds every action)
#   placements        -> units[*].models[*].position, px -> inches
#   reserves          -> units[*].status == IN_RESERVES
#   embarkations      -> units[*].embarked_in  (set by both the FORMATIONS
#                        declaration and DEPLOYMENT's COMPOSITE_DEPLOY)
#   attachments       -> units[*].attached_to  (likewise)
#   earmarks          -> left empty; PM-6's intent painter fills them in
#
# Reference: 40k/docs/PLAN_FORMAT.md

const PlanValidatorScript = preload("res://scripts/PlanValidator.gd")
const PlanManagerScript = preload("res://scripts/PlanManager.gd")

# Mirrors Measurement.PX_PER_INCH / AIDecisionMaker.PIXELS_PER_INCH. Duplicated
# rather than imported so this file stays autoload-free (see the header).
const PIXELS_PER_INCH: float = 40.0

# Board inches are rounded to this many decimals in the emitted JSON. 0.01" is
# 0.4px — two orders of magnitude inside the 0.5" round-trip tolerance, and it
# keeps a hand-edited plan file readable.
const POSITION_DECIMALS: int = 2

# Deployment-phase actions that put a unit on the board, in the order a player
# can produce them. COMPOSITE_DEPLOY is the same placement bundled with an
# embark/attach declaration (DeploymentController.gd:1118-1199).
const PLACEMENT_ACTIONS := ["DEPLOY_UNIT", "COMPOSITE_DEPLOY"]
const RESERVE_ACTIONS := ["PLACE_IN_RESERVES"]

# A recorded reserve has no arrival round in game state — the game only stores
# WHAT is in reserve and by which route. The plan format requires one (2-3), so
# a recording defaults to the earliest legal round; the author can edit it.
const DEFAULT_ARRIVAL_ROUND: int = 2

# GameStateData.UnitStatus.IN_RESERVES, spelled out rather than referenced.
# Naming the class here would pull GameState.gd -> DeploymentZoneData.gd -> the
# Measurement autoload into parse time, which is exactly what makes a script
# uncompilable from a `-s` headless test (see the header).
const STATUS_IN_RESERVES: int = 7


# ============================================================
# Entry point
# ============================================================

static func build_plan(state: Dictionary, info: Dictionary = {}, terrain_pieces: Array = []) -> Dictionary:
	"""Serialise `state` into a wh40k_ai_plan for one seat.

	`info` accepts: name, description, author, player (default 1),
	arrival_round (default 2).
	`terrain_pieces` is TerrainManager.terrain_features, or [] to omit the
	nearest-terrain anchor. Each entry needs `id` and `position` (board px).

	Returns the plan Dictionary. It is NOT validated here — the caller decides
	what to do with errors (PlanManager.save_plan refuses an invalid plan)."""
	var player: int = int(info.get("player", 1))
	var units: Dictionary = state.get("units", {})
	if not (units is Dictionary):
		units = {}

	var identity: Dictionary = PlanManagerScript.resolve_game_identity(player, state)
	var game_config: Dictionary = state.get("meta", {}).get("game_config", {})
	if not (game_config is Dictionary):
		game_config = {}

	var zone_id := str(identity.get("zone_id", ""))
	if zone_id.is_empty():
		zone_id = str(game_config.get("deployment", ""))
	var layout_id := str(identity.get("layout_id", ""))
	if layout_id.is_empty():
		layout_id = str(game_config.get("terrain", ""))
	# "" means "matches any layout" and is a legal, weaker key. An id that does
	# not resolve to a shipped layout file is an ERROR in the validator, so drop
	# it rather than hand the author a plan that can never be saved.
	if not layout_id.is_empty() and not PlanValidatorScript.layout_exists(layout_id):
		layout_id = ""

	var army_file := str(identity.get("army_key", ""))
	if army_file.is_empty():
		army_file = str(game_config.get("player%d_army" % player, ""))

	var zone_poly: PackedVector2Array = PlanValidatorScript.get_zone_polygon(zone_id, 1)
	var objectives: Array = _objectives_in_inches(state)

	var plan := {
		"format": PlanValidatorScript.FORMAT_TAG,
		"version": PlanValidatorScript.SCHEMA_VERSION,
		"name": str(info.get("name", "")).strip_edges(),
		"description": str(info.get("description", "")),
		"author": str(info.get("author", "")),
		"keys": {
			"army_file": army_file,
			"detachment_hint": str(identity.get("detachment", "")),
			"deployment_zone_id": zone_id,
			"terrain_layout_id": layout_id,
			"mission_id": str(game_config.get("mission", "")),
		},
		"deployment": {
			"order": [],
			"placements": [],
			"reserves": [],
			"embarkations": [],
			"attachments": [],
		},
		# PM-6 (intent painter) fills these in. The schema allows absence, but an
		# explicit empty list makes a recorded plan obviously "not painted yet".
		"earmarks": [],
	}
	if plan["name"].is_empty():
		plan["name"] = default_plan_name(state, player)

	var arrival_round: int = int(info.get("arrival_round", DEFAULT_ARRIVAL_ROUND))

	# --- placements, reserves, embarkations, attachments ------------------
	for unit_id in units.keys():
		var unit = units[unit_id]
		if not (unit is Dictionary):
			continue
		if int(unit.get("owner", 0)) != player:
			continue

		var attached_to = unit.get("attached_to", null)
		if attached_to != null and str(attached_to) != "":
			plan["deployment"]["attachments"].append({
				"character": str(unit_id),
				"bodyguard": str(attached_to),
			})
			# An attached CHARACTER has no placement of its own — it is set up
			# with its bodyguard (DeploymentPhase._all_units_deployed skips it).
			continue

		var embarked_in = unit.get("embarked_in", null)
		if embarked_in != null and str(embarked_in) != "":
			plan["deployment"]["embarkations"].append({
				"unit": str(unit_id),
				"transport": str(embarked_in),
			})
			# Likewise: a passenger is deployed inside the transport.
			continue

		if int(unit.get("status", 0)) == STATUS_IN_RESERVES:
			plan["deployment"]["reserves"].append({
				"unit": str(unit_id),
				"arrival_round": arrival_round,
			})
			continue

		var models_inches := _models_in_inches(unit)
		if models_inches.is_empty():
			# Nothing placed (or a partially placed unit) — recording half a unit
			# would produce a placement the consumer must reject, so skip it and
			# let the formula handle that unit.
			continue

		var placement := {
			"unit": str(unit_id),
			"unit_name": str(unit.get("meta", {}).get("name", unit_id)),
			"models_inches": models_inches,
		}
		var anchors := _anchors_for(models_inches, objectives, zone_poly, terrain_pieces)
		if not anchors.is_empty():
			placement["anchors"] = anchors
		plan["deployment"]["placements"].append(placement)

	# --- order ------------------------------------------------------------
	plan["deployment"]["order"] = _order_from_phase_log(
		state, plan["deployment"]["placements"], units, player)

	return plan


static func default_plan_name(state: Dictionary, player: int = 1) -> String:
	"""'<army_file> — <zone_id>'. Pre-filled in the save dialog so a scenario
	never has to type, and so two plans for different zones do not collide on
	the same slug."""
	var identity: Dictionary = PlanManagerScript.resolve_game_identity(player, state)
	var game_config: Dictionary = state.get("meta", {}).get("game_config", {})
	if not (game_config is Dictionary):
		game_config = {}
	var army := str(identity.get("army_key", ""))
	if army.is_empty():
		army = str(game_config.get("player%d_army" % player, ""))
	if army.is_empty():
		army = str(identity.get("faction_name", "army"))
	var zone := str(identity.get("zone_id", ""))
	if zone.is_empty():
		zone = str(game_config.get("deployment", "zone"))
	return "%s — %s" % [army, zone]


static func own_army(state: Dictionary, player: int = 1) -> Dictionary:
	"""The seat's own units in the shape PlanValidator.coverage/_army_units want.

	Using the LIVE units rather than re-reading the army file matters: coverage
	resolves plan references against these ids, and the reserve caps are a
	fraction of THIS army's points and unit count."""
	var out := {}
	var units = state.get("units", {})
	if not (units is Dictionary):
		return {"units": out}
	for unit_id in units.keys():
		var unit = units[unit_id]
		if unit is Dictionary and int(unit.get("owner", 0)) == player:
			out[unit_id] = unit
	return {"units": out}


static func record_and_save(state: Dictionary, info: Dictionary = {}, terrain_pieces: Array = [], army: Dictionary = {}) -> Dictionary:
	"""build_plan + PlanManager.save_plan in one call.

	`army` defaults to this seat's own units so the coverage and reserve-cap
	checks actually run — passing {} to the validator silently skips them.

	Returns {success, path, errors, warnings, plan} — `plan` is always present
	so a caller can show the author exactly what was refused."""
	var plan := build_plan(state, info, terrain_pieces)
	var army_for_validation := army
	if army_for_validation.is_empty():
		army_for_validation = own_army(state, int(info.get("player", 1)))
	var result: Dictionary = PlanManagerScript.save_plan(plan, army_for_validation)
	result["plan"] = plan
	return result


# ============================================================
# Internals
# ============================================================

static func _models_in_inches(unit: Dictionary) -> Array:
	"""Every model of `unit` as [x, y] board inches, in MODEL ORDER.

	Model order matters: AIDecisionMaker._plan_positions_px indexes
	models_inches by model index, so a gap would silently mis-seat the unit.
	Returns [] if any model lacks a position — a partial unit is not
	recordable."""
	var models = unit.get("models", [])
	if not (models is Array) or models.is_empty():
		return []
	var out: Array = []
	for model in models:
		if not (model is Dictionary):
			return []
		var pos = model.get("position", null)
		if pos == null:
			return []
		var v := _to_vector2(pos)
		out.append([
			snappedf(v.x / PIXELS_PER_INCH, pow(0.1, POSITION_DECIMALS)),
			snappedf(v.y / PIXELS_PER_INCH, pow(0.1, POSITION_DECIMALS)),
		])
	return out


static func _to_vector2(value) -> Vector2:
	"""Positions arrive as Vector2 live and as {x, y} after a save/load or a
	JSON round-trip."""
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	return Vector2.ZERO


static func _order_from_phase_log(state: Dictionary, placements: Array, units: Dictionary, player: int) -> Array:
	"""Deployment order, as the author actually produced it.

	PM-4 holds DEPLOYMENT open, so state.phase_log still carries every action of
	the phase in dispatch order (GameState.add_action_to_phase_log; it is only
	cleared by commit_phase_log_to_history on a phase transition). Any placed
	unit the log does not mention — e.g. one deployed before a reload — is
	appended afterwards so `order` covers every placement and the validator does
	not warn about an orphan."""
	var placed := {}
	for p in placements:
		placed[str(p.get("unit", ""))] = true

	var order: Array = []
	var seen := {}
	var log_entries = state.get("phase_log", [])
	if log_entries is Array:
		for entry in log_entries:
			if not (entry is Dictionary):
				continue
			var action_type := str(entry.get("type", ""))
			if not (action_type in PLACEMENT_ACTIONS or action_type in RESERVE_ACTIONS):
				continue
			var unit_id := str(entry.get("unit_id", ""))
			if unit_id.is_empty() or seen.has(unit_id):
				continue
			# Only this seat's units, and only ones that survived into a
			# placement (a unit deployed then re-declared into reserves must not
			# appear in `order` as if it were on the board).
			if int(units.get(unit_id, {}).get("owner", 0)) != player:
				continue
			if not placed.has(unit_id):
				continue
			seen[unit_id] = true
			order.append(unit_id)

	for p in placements:
		var pid := str(p.get("unit", ""))
		if not seen.has(pid):
			seen[pid] = true
			order.append(pid)
	return order


static func _objectives_in_inches(state: Dictionary) -> Array:
	"""[{id, position(inches)}] from state.board.objectives (stored in px)."""
	var out: Array = []
	var board = state.get("board", {})
	if not (board is Dictionary):
		return out
	var objectives = board.get("objectives", [])
	if not (objectives is Array):
		return out
	for obj in objectives:
		if not (obj is Dictionary):
			continue
		var pos = obj.get("position", null)
		if pos == null:
			continue
		out.append({
			"id": str(obj.get("id", "")),
			"position": _to_vector2(pos) / PIXELS_PER_INCH,
		})
	return out


static func _anchors_for(models_inches: Array, objectives: Array, zone_poly: PackedVector2Array, terrain_pieces: Array) -> Dictionary:
	"""RECORDED-ONLY context for a placement (PLAN_FORMAT.md: anchors are never
	resolved in v1). Everything is measured from the unit's centroid:

	  nearest_objective        id of the closest objective marker
	  depth_from_zone_edge_in  distance to the NEAREST edge of the player-1
	                           deployment zone, i.e. how far inside the zone the
	                           unit is tucked
	  nearest_terrain_piece    id of the closest terrain feature"""
	var centroid := _centroid(models_inches)
	var anchors := {}

	var best_obj := ""
	var best_obj_dist := INF
	for obj in objectives:
		var d: float = centroid.distance_to(obj.get("position", Vector2.ZERO))
		if d < best_obj_dist:
			best_obj_dist = d
			best_obj = str(obj.get("id", ""))
	if not best_obj.is_empty():
		anchors["nearest_objective"] = best_obj

	if zone_poly.size() >= 3:
		anchors["depth_from_zone_edge_in"] = snappedf(
			_distance_to_polygon_edge(centroid, zone_poly), 0.1)

	var best_piece := ""
	var best_piece_dist := INF
	for piece in terrain_pieces:
		if not (piece is Dictionary):
			continue
		var piece_pos = piece.get("position", null)
		if piece_pos == null:
			continue
		var d2: float = centroid.distance_to(_to_vector2(piece_pos) / PIXELS_PER_INCH)
		if d2 < best_piece_dist:
			best_piece_dist = d2
			best_piece = str(piece.get("id", ""))
	if not best_piece.is_empty():
		anchors["nearest_terrain_piece"] = best_piece

	return anchors


static func _centroid(models_inches: Array) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for pair in models_inches:
		if pair is Array and pair.size() >= 2:
			sum += Vector2(float(pair[0]), float(pair[1]))
			n += 1
	if n == 0:
		return Vector2.ZERO
	return sum / float(n)


static func _distance_to_polygon_edge(point: Vector2, poly: PackedVector2Array) -> float:
	"""Shortest distance from `point` to the polygon's boundary (not its
	interior) — the same number whether the point is inside or outside, so a
	placement that pokes out of the zone still reports a sane depth."""
	var best := INF
	var n := poly.size()
	for i in range(n):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
		var d := point.distance_to(closest)
		if d < best:
			best = d
	return 0.0 if best == INF else best
