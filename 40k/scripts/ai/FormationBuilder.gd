class_name FormationBuilder
extends RefCounted

## Legal-by-construction set-up formations for the AI (docs/AI_DEPLOYMENT_PLAN.md
## P0.1 / §5.8).
##
## build_deployment() finds a position and rotation for every ALIVE model of a
## bodyguard unit — and for every alive model of each UNDEPLOYED attached
## CHARACTER, since an attached unit is set up as one unit (11e 19.01) — that
## DeploymentPhase will accept, as near the desired spot as possible. The search
## is exhaustive over a fixed, deterministic candidate set:
##   1. uniform blocks ("shelf grids", rotation 0 / 90, every column count) whose
##      own spacing already satisfies 03.03 coherency (2" + the 11e 9" envelope);
##   2. attached characters as "satellites" on the block's perimeter, each sized
##      and rotated from its OWN base;
##   3. a 0.5" anchor lattice inside the zone polygon, nearest the desired spot
##      first;
##   4. when no block fits (or the count budget runs out), a model-by-model growth
##      fallback that only ever adds a model at a legal, coherent spot, seeded
##      at the ROOMIEST legal cells of the whole zone first (L2-2), so open
##      ground far from the desired spot is still found in a crowded zone.
## A failure therefore means no legal set-up was FOUND in that set within the
## count budgets — reported as "no legal set-up found", never as proof that
## none exists — not "unlucky random samples", which is what used to dump
## units into Strategic Reserves.
##
## Per-model legality copies DeploymentPhase's own predicates: zone
## (Measurement.shape_wholly_in_polygon sampling, without its debug prints),
## board (Measurement.model_outside_board), Infiltrators 24.20 (when the unit
## has it), overlap with models of DEPLOYED units (any model with a position,
## alive or not — that is what the phase checks) honouring
## SettingsService.unit_skips_collision, and walls / solid features
## (Measurement.model_overlaps_any_wall with the model's OWN unit keywords).
## Overlap is also tested in the reverse direction for mixed shape types,
## because CircularBase.overlaps_with(non-circle) is a sampled test that misses
## real circle-into-oval overlaps (D3 / RC8; the phase keeps its one-direction
## test). Character models are judged with their own unit's keywords and skip
## flag, never the bodyguard's.
##
## Inputs. The snapshot supplies units (status, models, keywords, attachments)
## and the deployment zones. These are read LIVE, as DeploymentPhase reads them:
## TerrainManager.terrain_features (walls / solid features), SettingsService
## (board size, vehicle-collision override), GameState (Infiltrators ability)
## and GameConstants.edition (coherency rules, Infiltrators distance). A
## hypothetical snapshot is therefore judged against the live terrain/settings.
##
## Determinism. No RNG anywhere. Every ordering has a total tie-break
## (distance², y, x for anchors, slots and growth cells; footprint, rotation,
## columns, name for blocks; free room, then distance, for growth seeds).
## Budgets are COUNTS (anchor×block evaluations, fresh per-position checks and
## growth work units), never wall-clock, so a build returns the same result on
## any machine. The static caches hold pure functions of their keys (blocks per
## base signature + edition, variant legality, anchor lattices per polygon);
## everything that depends on the search (memo, fail-first order, counters)
## lives in the per-build context, so a warm cache returns exactly what a cold
## one does.
##
## Work outside the count budgets (L2-1). Template legality — every candidate
## block's and every satellite variant's overlap pairs and coherency
## (_template_legal) — is not charged to evals / fresh (charging it only when
## computed would make a cold build differ from a warm one). It is bounded per
## unit SIGNATURE instead: at most 2 rotations x 2·n_bg column layouts of
## blocks, each with at most MAX_SAT_ROTATION_COMBOS x sat_variants (4 x 10)
## variants, each computed once per session (static caches). So the FIRST
## build of a signature in a session (cold) can take several times longer
## than a warm one at identical counts and an identical result; a satellite
## variant re-checks only its character pairs and the merged coherency.
##
## Output is index-aligned with unit.models: one entry per model, null for a
## dead model. combined_char_data uses the format DeploymentController sends
## with COMPOSITE_DEPLOY: {char_id: [{model_idx, x, y, rotation}]}.
##
## Final gate. Before a result is returned it is validated as the action the AI
## will send: by the live DeploymentPhase.validate_action when the live phase
## is a DeploymentPhase AND the snapshot is the live state, otherwise by
## placement_errors(). A unit-level refusal (anything not tied to a model
## position: AIRCRAFT 23.01, wrong player, unit not available) aborts at once;
## a position-level refusal excludes that candidate and continues, at most
## MAX_GATE_REJECTIONS times, each logged as a [FORMATION] DEFECT.
##
## Spot constraints (P0.3, AIDecisionMaker's 11e terrain picker): a build can
## be pinned to one terrain spot — seed_positions (a pocket fill tried first,
## verbatim), inside_polys (every model centre, attached characters included,
## inside an area), avoid_polys (no bounding circle touching them),
## anchor_region and max_displacement_px (a local search). They only narrow the
## search; the final gate is unchanged. See build_deployment().
##
## Autoloads are reached late-bound (DeploymentEval pattern) so this script
## compiles in `godot --headless --script` test mode. No dependency on
## AIDecisionMaker (the dependency runs AIDecisionMaker -> FormationBuilder).

const RASTER_PX := 10.0        # 0.25": every template offset lies on this raster
const GAP_PX := 6.0            # 0.15": minimum footprint clearance between template neighbours
const ANCHOR_STEP_PX := 20.0   # 0.5": anchor lattice (a subset of the raster)
const GROW_STEP_PX := 20.0     # growth-fallback lattice
const PX_PER_INCH := 40.0
const MM_PER_INCH := 25.4

# GameStateData.UnitStatus mirrored (no parse-time dependency on GameState.gd).
const STATUS_UNDEPLOYED := 0
const STATUS_DEPLOYING := 1
const STATUS_DEPLOYED := 2
const STATUS_IN_RESERVES := 7
const PHASE_DEPLOYMENT := 1

const DEFAULT_MAX_EVALS := 80000     # anchor x block evaluations
const DEFAULT_MAX_FRESH := 16000     # fresh (non-memoised) per-position checks
const DEFAULT_SAT_VARIANTS := 10     # satellite variants per character rotation combination
const DEFAULT_GROW_SEEDS := 120      # growth-fallback seeds (all plans together)
# Growth work, in units of roughly one microsecond on this machine: one per
# lattice cell enumerated / scored when ranking seeds, one per disc cell
# stamped into a growth frontier and per frontier cell returned, one per
# candidate tried, 15 per model-to-model distance in a coherency step. With the
# fresh-check allowance (half of max_fresh on top of the search's) it bounds
# the fallback's cost. A 7-model attached unit costs ~3-7k per seed, a
# 22-model one ~15-30k.
const DEFAULT_MAX_GROW_WORK := 800000
const MAX_GATE_REJECTIONS := 3
const MAX_SAT_ROTATION_COMBOS := 4

# The exact DeploymentPhase error phrases that are tied to a model POSITION
# (per-model checks, intra-unit overlap, coherency, combined_char_data). Any
# other error (unit not found / not available / wrong player / AIRCRAFT 23.01 —
# whose text says "...instead of on the battlefield" — / malformed action / not
# attached / RC7 missing positions) is unit-level: no other position can fix it.
const POSITION_ERROR_MARKERS := ["Model must be wholly within", "Model cannot overlap",
	"Model cannot be placed off the board", "Model must be on the battlefield", "overlap each other",
	"coherency broken", "Infiltrators must be >", "overlaps a model of its attached unit"]

static var _block_cache: Dictionary = {}          # signature -> Array[block] (immutable once built)
static var _variant_legal_cache: Dictionary = {}  # signature#variant -> bool (pure)
static var _lattice_cache: Dictionary = {}        # polygon key -> PackedVector2Array
static var _stats: Dictionary = {}

# =============================================================================
# Public API
# =============================================================================

static func build_deployment(snapshot: Dictionary, player: int, unit_id: String, desired: Vector2, opts: Dictionary = {}) -> Dictionary:
	"""Legal positions for `unit_id` (+ its UNDEPLOYED attached characters).

	opts (defaults): zone_poly (the player's zone; legacy pixel `vertices`, then
	the bounds rectangle, as fallbacks), max_evals 80000, max_fresh 16000,
	sat_variants 10, grow true, grow_seeds 60, final_gate true,
	preferred_offsets: Array[Vector2] (a rigid shape tried first at every anchor —
	plan repair), exclude_positions: Array of position Arrays (candidates whose
	bodyguard positions match one within 1 px are skipped — AIPlayer retry).

	Spot constraints (P0.3, the 11e terrain picker; search-only — the final
	gate is still exactly the phase's own rules):
	  seed_positions: Array[Vector2] in MODEL-SLOT order (model_slots(): alive
	    bodyguard models, then the alive models of each UNDEPLOYED attached
	    character), size = every slot. Tried first, verbatim (rotation 0):
	    accepted only if every model is legal there, every constraint holds,
	    the shape is coherent (bodyguard alone and merged) and the gate passes.
	  inside_polys: Array[PackedVector2Array] ("require" mode): every model
	    CENTRE — attached characters included — must lie in their union.
	  avoid_polys: Array[PackedVector2Array]: no model's bounding circle may
	    overlap any of them.
	  anchor_region: Array[PackedVector2Array]: block anchors and growth seeds
	    only inside these (and the zone), nearest `desired` first.
	  max_displacement_px: no anchor / growth seed further than this from
	    `desired`.
	  probe (bool): a constrained attempt at one spot. Its failure is
	    expected, so stats() counts it under probes / probe_fail, never as
	    no_legal (a unit for which no legal set-up was found).
	When a constraint is active and nothing fits, reason starts with
	"inside: ", "avoid: " or "near: " — never a partial result.

	Returns {ok, reason, model_positions, model_rotations, combined_char_data,
	action_type ("DEPLOY_UNIT" | "COMPOSITE_DEPLOY"), template, anchor,
	displacement_px, evals, fresh, grown, grow_work, gate_rejections,
	constraint_rejects, us}."""
	var t0 := Time.get_ticks_usec()
	var ctx := _make_ctx(snapshot, player, unit_id, opts)
	var out: Dictionary
	if not ctx.get("error", "").is_empty():
		out = _fail(ctx, str(ctx.error))
	else:
		out = _search(ctx, desired)
		var tag := str(ctx.get("constraint_tag", ""))
		if not bool(out.get("ok", false)) and tag != "" and not str(out.get("reason", "")).begins_with("refused"):
			out["reason"] = "%s: %s" % [tag, str(out.get("reason", ""))]
	out["constraint_rejects"] = int(ctx.get("constraint_rejects", 0))
	out["us"] = Time.get_ticks_usec() - t0
	_record_stats(unit_id, out, bool(opts.get("probe", false)))
	return out

static func model_slots(snapshot: Dictionary, player: int, unit_id: String, opts: Dictionary = {}) -> Dictionary:
	"""The model slots build_deployment places, in its order: the alive
	bodyguard models (model index order), then the alive models of each
	UNDEPLOYED attached character (attachment order). seed_positions use this
	order. Returns {ok, reason, n_bg, slots: [{unit_id, idx, is_char, r_out,
	base_mm, keywords}]} (r_out = bounding radius in px)."""
	var ctx := _make_ctx(snapshot, player, unit_id, opts)
	if not ctx.get("error", "").is_empty():
		return {"ok": false, "reason": str(ctx.error), "n_bg": 0, "slots": []}
	var slots: Array = []
	for mi in ctx.mlist:
		slots.append({"unit_id": str(mi.unit_id), "idx": int(mi.idx), "is_char": bool(mi.is_char),
			"r_out": float(mi.info.r_out), "base_mm": int(mi.m.get("base_mm", 32)), "keywords": mi.kws})
	return {"ok": true, "reason": "", "n_bg": int(ctx.n_bg), "slots": slots}

static func attach_satellites(snapshot: Dictionary, player: int, unit_id: String, positions: Array, rotations: Array, opts: Dictionary = {}) -> Dictionary:
	"""Fixed bodyguard positions (e.g. a plan placement already checked with
	placement_errors) -> legal positions for the unit's UNDEPLOYED attached
	characters. Returns {ok, reason, combined_char_data, gate_rejections}; ok
	with an empty combined_char_data when there is nothing to attach."""
	var ctx := _make_ctx(snapshot, player, unit_id, opts)
	if not ctx.get("error", "").is_empty():
		return {"ok": false, "reason": str(ctx.error), "combined_char_data": {}}
	if ctx.n_all == ctx.n_bg:
		return {"ok": true, "reason": "", "combined_char_data": {}}
	ctx["no_memo"] = true   # positions are not on the raster: memo keys would alias
	# Bodyguard frame: offsets about the alive models' centroid.
	var centre := Vector2.ZERO
	var count := 0
	for i in range(ctx.n_bg):
		var p = positions[ctx.mlist[i].idx] if ctx.mlist[i].idx < positions.size() else null
		if p == null:
			return {"ok": false, "reason": "bodyguard model %d has no position" % ctx.mlist[i].idx, "combined_char_data": {}}
		centre += _vec(p)
		count += 1
	centre /= float(count)
	var offs: Array = []
	var rots: Array = []
	for i in range(ctx.n_bg):
		offs.append(_vec(positions[ctx.mlist[i].idx]) - centre)
		var r = rotations[ctx.mlist[i].idx] if ctx.mlist[i].idx < rotations.size() else 0.0
		rots.append(0.0 if r == null else float(r))
	var block := _block_from_offsets(ctx, offs, rots, "fixed")
	# The fixed bodyguard shape once (overlaps + coherency); each variant then
	# only checks its characters (L2-1). An illegal shape fails every variant,
	# exactly as before.
	if not _template_legal(ctx, block, ctx.n_bg):
		return {"ok": false, "reason": "no satellite slot fits beside the fixed placement", "combined_char_data": {}}
	var variants := _make_variants(ctx, block)
	for t in variants:
		if not _template_legal(ctx, t, ctx.n_all, true):
			continue
		var fits := true
		for j in range(ctx.n_bg, ctx.n_all):
			if not _position_ok(ctx, ctx.mlist[j], centre + t.offs[j], t.rots[j]):
				fits = false
				break
		if not fits:
			continue
		var cand := _candidate(ctx, centre, t)
		# Keep the caller's exact bodyguard positions (not centre + offset).
		cand.positions = positions.duplicate()
		cand.rotations = rotations.duplicate()
		var g := _gate(ctx, cand)
		if g.ok:
			return {"ok": true, "reason": "", "combined_char_data": cand.ccd, "template": t.name, "gate_rejections": ctx.gate_rejections}
		# L2-3: the header's contract — a position-level refusal excludes the
		# candidate at most MAX_GATE_REJECTIONS times (each one is a DEFECT).
		if g.unit_level or ctx.gate_rejections >= MAX_GATE_REJECTIONS:
			return {"ok": false, "reason": "refused: %s" % "; ".join(g.errors), "combined_char_data": {}, "gate_rejections": ctx.gate_rejections}
	return {"ok": false, "reason": "no satellite slot fits beside the fixed placement", "combined_char_data": {}, "gate_rejections": ctx.gate_rejections}

static func placement_errors(snapshot: Dictionary, player: int, unit_id: String, positions: Array, rotations: Array, combined_char_data: Dictionary = {}, opts: Dictionary = {}) -> Array:
	"""Every reason DeploymentPhase would refuse this placement, plus the
	reverse-direction overlap test (mixed shape types) and merged 19.01 + 03.03
	coherency for attached characters. [] = legal.

	opts: unit (Dictionary — judge this unit dict instead of snapshot.units[unit_id]),
	zone_poly (PackedVector2Array — explicit zone; fewer than 3 points = no zone
	check, "defer to the phase"), obstacles (Array of {position, base_mm,
	base_type, base_dimensions, rotation} — explicit already-deployed models),
	check_unit_level (bool, default true)."""
	var ctx := _make_ctx(snapshot, player, unit_id, opts)
	if not ctx.get("error", "").is_empty():
		return ["UNIT: %s" % str(ctx.error)]
	ctx["no_memo"] = true
	ctx["phase_exact"] = true
	return _placement_errors_ctx(ctx, positions, rotations, combined_char_data)

static func final_check(snapshot: Dictionary, player: int, unit_id: String, positions: Array, rotations: Array, combined_char_data: Dictionary = {}) -> Array:
	"""The builder's exact final gate as a standalone check: the live
	DeploymentPhase.validate_action when the live phase is a DeploymentPhase
	and `snapshot` is the live state, otherwise placement_errors(). [] = legal."""
	var ctx := _make_ctx(snapshot, player, unit_id, {})
	if not ctx.get("error", "").is_empty():
		return ["UNIT: %s" % str(ctx.error)]
	ctx["no_memo"] = true
	ctx["quiet_gate"] = true
	var g := _gate(ctx, {"positions": positions, "rotations": rotations, "ccd": combined_char_data})
	return g.errors

static func stats() -> Dictionary:
	"""{builds, ok, grown, no_legal, gate_rejections, gate_aborts, evals, fresh,
	grow_work, max_us, max_unit, total_us, probes, probe_ok, probe_fail} since the last
	reset_stats(). builds / ok / grown / no_legal count unconstrained builds
	only; probe builds (opts.probe — one terrain spot, P0.3) are counted in
	probes / probe_ok / probe_fail. evals, fresh, gate_rejections and the
	timings cover both."""
	if _stats.is_empty():
		reset_stats()
	return _stats.duplicate()

static func reset_stats() -> void:
	_stats = {"builds": 0, "ok": 0, "grown": 0, "no_legal": 0, "gate_rejections": 0,
		"gate_aborts": 0, "evals": 0, "fresh": 0, "grow_work": 0, "max_us": 0, "max_unit": "", "total_us": 0,
		"probes": 0, "probe_ok": 0, "probe_fail": 0}

static func clear_caches() -> void:
	_block_cache.clear()
	_variant_legal_cache.clear()
	_lattice_cache.clear()

static func is_position_error(err: String) -> bool:
	for marker in POSITION_ERROR_MARKERS:
		if err.find(marker) >= 0:
			return true
	return false

# =============================================================================
# Context
# =============================================================================

static func _autoload(node_name: String):
	var main = Engine.get_main_loop()
	if main is SceneTree and main.root:
		return main.root.get_node_or_null(node_name)
	return null

static func _vec(p) -> Vector2:
	if p is Vector2:
		return p
	if p is Dictionary:
		return Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	if p is Array and p.size() >= 2:
		return Vector2(float(p[0]), float(p[1]))
	return Vector2.ZERO

static func _shape_key(model: Dictionary) -> String:
	return "%s|%s|%s" % [str(model.get("base_type", "circular")), str(model.get("base_mm", 32)), str(model.get("base_dimensions", {}))]

static func _kw_key(keywords: Array) -> String:
	var up: Array = []
	for k in keywords:
		up.append(str(k).to_upper())
	up.sort()
	return ",".join(up)

static func _info_for(ctx: Dictionary, model: Dictionary) -> Dictionary:
	var skey := _shape_key(model)
	var cache: Dictionary = ctx.shape_cache
	if cache.has(skey):
		return cache[skey]
	var sh = ctx.meas.create_base_shape(model)
	var bb: Rect2 = sh.get_bounds()
	var t: String = sh.get_type()
	var info := {"skey": skey, "shape": sh, "type": t,
		"r_out": (bb.size.length() * 0.5) if t == "rectangular" else maxf(bb.size.x, bb.size.y) * 0.5,
		"r_in": minf(bb.size.x, bb.size.y) * 0.5,
		"hx": bb.size.x * 0.5, "hy": bb.size.y * 0.5,
		"base_r_in": (float(model.get("base_mm", 32)) / 2.0) / MM_PER_INCH,
		"rots": [0.0] if t == "circular" else [0.0, PI / 2.0]}
	cache[skey] = info
	return info

static func _he(info: Dictionary, rot: float) -> Vector2:
	"""Half extents of the footprint AABB at rotation 0 or 90 degrees."""
	if absf(sin(rot)) > 0.5:
		return Vector2(info.hy, info.hx)
	return Vector2(info.hx, info.hy)

static func _make_ctx(snapshot: Dictionary, player: int, unit_id: String, opts: Dictionary) -> Dictionary:
	var meas = _autoload("Measurement")
	var ctx := {"error": "", "snapshot": snapshot, "player": player, "unit_id": unit_id, "opts": opts,
		"meas": meas, "settings": _autoload("SettingsService"), "gs": _autoload("GameState"),
		"shape_cache": {}, "memo": {}, "ff": {}, "fresh": 0, "memo_hits": 0, "no_memo": false,
		"gate_rejections": 0, "gate_errors": [], "edition": GameConstants.edition, "grow_work": 0}
	if meas == null:
		ctx.error = "Measurement autoload unavailable"
		return ctx
	var unit: Dictionary = opts.get("unit", {})
	if unit.is_empty():
		unit = snapshot.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		ctx.error = "unit %s not found" % unit_id
		return ctx
	ctx["unit"] = unit
	ctx["unit_name"] = str(unit.get("meta", {}).get("name", unit_id))
	var settings = ctx.settings
	var gs = ctx.gs
	# Zone polygon (pixels).
	var poly := PackedVector2Array()
	var explicit_zone := opts.has("zone_poly")
	if explicit_zone:
		poly = opts.zone_poly
	else:
		poly = _zone_polygon_px(snapshot, player)
	ctx["poly"] = poly
	ctx["check_zone"] = poly.size() >= 3 or not explicit_zone
	if poly.size() < 3 and not explicit_zone:
		ctx.error = "no deployment zone for player %d" % player
		return ctx
	ctx["board_w"] = settings.get_board_width_px() if settings != null and settings.has_method("get_board_width_px") else 1760.0
	ctx["board_h"] = settings.get_board_height_px() if settings != null and settings.has_method("get_board_height_px") else 2400.0
	# Models: alive bodyguard models, then alive models of each UNDEPLOYED attached character.
	var bg_skip: bool = settings != null and settings.has_method("unit_skips_collision") and settings.unit_skips_collision(unit_id)
	var bg_kws: Array = unit.get("meta", {}).get("keywords", [])
	var bg_infil: bool = gs != null and gs.has_method("unit_has_infiltrators") and gs.unit_has_infiltrators(unit_id)
	var chars: Array = []
	var units: Dictionary = snapshot.get("units", {})
	var ad = unit.get("attachment_data", {})
	if ad is Dictionary and opts.get("include_characters", true):
		for cid in ad.get("attached_characters", []):
			var cu: Dictionary = units.get(str(cid), {})
			if cu.is_empty() or int(cu.get("status", STATUS_UNDEPLOYED)) != STATUS_UNDEPLOYED:
				continue
			chars.append(str(cid))
	var merged_infil := bg_infil
	for cid in chars:
		if not (gs != null and gs.has_method("unit_has_infiltrators") and gs.unit_has_infiltrators(cid)):
			merged_infil = false
	var mlist: Array = []
	var models: Array = unit.get("models", [])
	for i in range(models.size()):
		if models[i] is Dictionary and models[i].get("alive", true):
			mlist.append(_model_entry(ctx, models[i], unit_id, i, bg_kws, bg_skip, bg_infil, false))
	var n_bg := mlist.size()
	if n_bg == 0:
		ctx.error = "unit %s has no alive models" % unit_id
		return ctx
	for cid in chars:
		var cu: Dictionary = units[cid]
		var c_kws: Array = cu.get("meta", {}).get("keywords", [])
		var c_skip: bool = settings != null and settings.has_method("unit_skips_collision") and settings.unit_skips_collision(cid)
		var cm: Array = cu.get("models", [])
		for ci in range(cm.size()):
			if cm[ci] is Dictionary and cm[ci].get("alive", true):
				mlist.append(_model_entry(ctx, cm[ci], cid, ci, c_kws, c_skip, merged_infil, true))
	ctx["mlist"] = mlist
	ctx["n_bg"] = n_bg
	ctx["n_all"] = mlist.size()
	ctx["chars"] = chars
	ctx["bg_infil"] = bg_infil
	ctx["bg_kws"] = bg_kws
	ctx["bg_skip"] = bg_skip
	ctx["merged_infil"] = merged_infil
	for mi in mlist:
		if not ctx.memo.has(mi["class"]):
			ctx.memo[mi["class"]] = {}
	# Obstacles: every model WITH A POSITION of every DEPLOYED unit, alive or not
	# (DeploymentPhase._position_overlaps_existing_models_shape), minus units the
	# vehicle-collision override exempts. Explicit opts.obstacles are taken as
	# given, except that an entry carrying a "unit_id" is filtered by the same
	# override as the default list (callers that know the owner pass it).
	var obstacles: Array = []
	if opts.has("obstacles"):
		for ob in opts.obstacles:
			if not (ob is Dictionary) or ob.get("position", null) == null:
				continue
			var ob_uid := str(ob.get("unit_id", ""))
			if ob_uid != "" and settings != null and settings.has_method("unit_skips_collision") and settings.unit_skips_collision(ob_uid):
				continue
			obstacles.append(_obstacle_entry(ctx, ob))
	else:
		for uid in units:
			var u = units[uid]
			if not (u is Dictionary) or int(u.get("status", STATUS_UNDEPLOYED)) != STATUS_DEPLOYED:
				continue
			if settings != null and settings.has_method("unit_skips_collision") and settings.unit_skips_collision(str(uid)):
				continue
			for m in u.get("models", []):
				if m is Dictionary and m.get("position", null) != null:
					obstacles.append(_obstacle_entry(ctx, m))
	ctx["grid"] = _build_grid(obstacles)
	# Terrain piece AABBs (polygon + wall end points): a model whose bounding box
	# meets none of them cannot overlap a wall or a solid feature.
	var piece_boxes: Array = []
	var tm = _autoload("TerrainManager")
	if tm != null:
		for piece in tm.terrain_features:
			var bb := Rect2()
			var has := false
			for v in piece.get("polygon", PackedVector2Array()):
				if not has:
					bb = Rect2(v, Vector2.ZERO)
					has = true
				else:
					bb = bb.expand(v)
			for w in piece.get("walls", []):
				for key in ["start", "end"]:
					var p = w.get(key, null)
					if p is Vector2:
						if not has:
							bb = Rect2(p, Vector2.ZERO)
							has = true
						else:
							bb = bb.expand(p)
			if has:
				piece_boxes.append(bb.grow(1.0))
	ctx["piece_boxes"] = piece_boxes
	# Infiltrators (24.20): the enemy zone and enemy models, from the snapshot
	# (the same filter as GameState.get_enemy_model_positions).
	ctx["enemy_zone"] = _zone_polygon_px(snapshot, 3 - player, false)
	var enemy_models: Array = []
	if bg_infil:
		for uid in units:
			var u = units[uid]
			if not (u is Dictionary) or int(u.get("owner", 0)) == player:
				continue
			var st := int(u.get("status", STATUS_UNDEPLOYED))
			if st != STATUS_DEPLOYED and st != 3:   # DEPLOYED / MOVED
				continue
			for m in u.get("models", []):
				if m is Dictionary and m.get("position", null) != null and m.get("alive", true):
					enemy_models.append({"pos": _vec(m.position), "r": (float(m.get("base_mm", 32)) / 2.0) / MM_PER_INCH})
	ctx["enemy_models"] = enemy_models
	ctx["infil_min_in"] = GameConstants.infiltrators_min_enemy_distance_inches()
	# phase_exact: judge exactly as the phase does (Infiltrators models are not
	# zone-checked). The SEARCH keeps every model inside its own zone in P0 —
	# stricter than the phase for Infiltrators, never looser.
	ctx["phase_exact"] = false
	# P0.3 spot constraints (search only; see build_deployment). Fixed for the
	# whole build, so the per-build memo may fold them into its verdicts.
	ctx["inside_polys"] = _poly_list(opts.get("inside_polys", []))
	ctx["avoid_polys"] = _poly_list(opts.get("avoid_polys", []))
	ctx["max_disp"] = float(opts.get("max_displacement_px", INF))
	ctx["constraint_rejects"] = 0
	var tag := ""
	if not (ctx.inside_polys as Array).is_empty():
		tag = "inside"
	elif not (ctx.avoid_polys as Array).is_empty():
		tag = "avoid"
	elif float(ctx.max_disp) < INF:
		tag = "near"
	ctx["constraint_tag"] = tag
	return ctx

static func _poly_list(raw) -> Array:
	"""[{poly: PackedVector2Array, box: Rect2}] for polygons with 3+ points."""
	var out: Array = []
	if not (raw is Array):
		return out
	for p in raw:
		var poly := PackedVector2Array()
		if p is PackedVector2Array:
			poly = p
		elif p is Array:
			for v in p:
				poly.append(_vec(v))
		if poly.size() < 3:
			continue
		var box := Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			box = box.expand(v)
		out.append({"poly": poly, "box": box.grow(1.0)})
	return out

static func _circle_overlaps_polygon(center: Vector2, radius: float, poly: PackedVector2Array) -> bool:
	"""Copy of TerrainManager._circle_overlaps_polygon (no autoload dependency)."""
	if poly.size() < 3:
		return false
	if Geometry2D.is_point_in_polygon(center, poly):
		return true
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		if a.distance_to(center) <= radius:
			return true
		if Geometry2D.segment_intersects_circle(a, b, center, radius) >= 0.0:
			return true
	return false

static func _constraints_ok(ctx: Dictionary, mi: Dictionary, pos: Vector2) -> bool:
	"""P0.3 spot constraints for one model at `pos` (cheap geometry, checked
	before the phase predicates so a rejected spot costs no fresh check)."""
	var inside: Array = ctx.inside_polys
	if not inside.is_empty():
		var hit := false
		for e in inside:
			if (e.box as Rect2).has_point(pos) and Geometry2D.is_point_in_polygon(pos, e.poly):
				hit = true
				break
		if not hit:
			ctx.constraint_rejects += 1
			return false
	var avoid: Array = ctx.avoid_polys
	if not avoid.is_empty():
		var r: float = mi.info.r_out
		for e in avoid:
			if (e.box as Rect2).grow(r).has_point(pos) and _circle_overlaps_polygon(pos, r, e.poly):
				ctx.constraint_rejects += 1
				return false
	return true

static func _model_entry(ctx: Dictionary, model: Dictionary, uid: String, idx: int, kws: Array, skip: bool, infil: bool, is_char: bool) -> Dictionary:
	var info := _info_for(ctx, model)
	var probe: Dictionary = model.duplicate()
	probe["alive"] = true
	return {"m": model, "unit_id": uid, "idx": idx, "info": info, "kws": kws, "skip": skip, "infil": infil,
		"is_char": is_char, "probe": probe,
		"class": "%s#%s#%s#%s" % [info.skey, _kw_key(kws), "S" if skip else "-", "I" if infil else "-"]}

static func _obstacle_entry(ctx: Dictionary, m: Dictionary) -> Dictionary:
	var info := _info_for(ctx, m)
	return {"pos": _vec(m.get("position")), "rot": float(m.get("rotation", 0.0)), "shape": info.shape,
		"type": info.type, "r_out": info.r_out, "r_in": info.r_in}

static var _map_zone_cache: Dictionary = {}

static func _zone_polygon_px(snapshot: Dictionary, player: int, bounds_fallback: bool = true) -> PackedVector2Array:
	"""The player's zone in pixels: the snapshot's `poly` (inches), else its
	legacy `vertices` (pixels); with no zone in the snapshot at all, the zone of
	its meta.deployment_type map (DeploymentZoneData); else the same fallback
	rectangle as AIDecisionMaker._get_deployment_zone_bounds."""
	var poly := PackedVector2Array()
	var listed := false
	for zone in snapshot.get("board", {}).get("deployment_zones", []):
		if not (zone is Dictionary) or int(zone.get("player", 0)) != player:
			continue
		listed = true
		for v in zone.get("poly", []):
			if v is Dictionary:
				poly.append(Vector2(float(v.get("x", 0.0)), float(v.get("y", 0.0))) * PX_PER_INCH)
			elif v is Vector2:
				poly.append(v * PX_PER_INCH)
		if poly.size() >= 3:
			return poly
		poly = PackedVector2Array()
		for v in zone.get("vertices", []):
			poly.append(_vec(v))
		if poly.size() >= 3:
			return poly
		break
	if not listed:
		var dtype := str(snapshot.get("meta", {}).get("deployment_type", ""))
		if dtype != "":
			if not _map_zone_cache.has(dtype):
				var dzd = load("res://scripts/data/DeploymentZoneData.gd")
				_map_zone_cache[dtype] = dzd.get_zones(dtype) if dzd != null else []
			var zones: Array = _map_zone_cache[dtype]
			for i in range(zones.size()):
				var z = zones[i]
				var zp: int = int(z.get("player", i + 1)) if z is Dictionary else i + 1
				if zp != player:
					continue
				var pts = z.get("poly", []) if z is Dictionary else z
				for v in pts:
					poly.append(_vec(v) * PX_PER_INCH)
				if poly.size() >= 3:
					return poly
				poly = PackedVector2Array()
	if not bounds_fallback:
		return PackedVector2Array()
	# Same fallback rectangles as AIDecisionMaker._get_deployment_zone_bounds.
	if player == 1:
		return PackedVector2Array([Vector2(40, 10), Vector2(1720, 10), Vector2(1720, 470), Vector2(40, 470)])
	return PackedVector2Array([Vector2(40, 1930), Vector2(1720, 1930), Vector2(1720, 2390), Vector2(40, 2390)])

static func _live_deployment_phase(snapshot: Dictionary):
	"""The live DeploymentPhase, but only when `snapshot` is the live state."""
	var pm = _autoload("PhaseManager")
	if pm == null:
		return null
	var phase = pm.get("current_phase_instance")
	if phase == null or not is_instance_valid(phase) or not phase.has_method("validate_action"):
		return null
	var script = phase.get_script()
	if script == null or not str(script.resource_path).ends_with("DeploymentPhase.gd"):
		return null
	var gs = _autoload("GameState")
	if gs == null or not _snapshot_is_live(snapshot, gs.state):
		return null
	return phase

static func _snapshot_is_live(snapshot: Dictionary, live: Dictionary) -> bool:
	var su: Dictionary = snapshot.get("units", {})
	var lu: Dictionary = live.get("units", {})
	if su.size() != lu.size():
		return false
	for uid in su:
		if not lu.has(uid):
			return false
		var a: Dictionary = su[uid]
		var b: Dictionary = lu[uid]
		if int(a.get("status", 0)) != int(b.get("status", 0)):
			return false
		var am: Array = a.get("models", [])
		var bm: Array = b.get("models", [])
		if am.size() != bm.size():
			return false
		for i in range(am.size()):
			var pa = am[i].get("position", null)
			var pb = bm[i].get("position", null)
			if (pa == null) != (pb == null):
				return false
			if pa != null and _vec(pa).distance_squared_to(_vec(pb)) > 0.01:
				return false
	var sz = snapshot.get("board", {}).get("deployment_zones", [])
	var lz = live.get("board", {}).get("deployment_zones", [])
	return hash(sz) == hash(lz)

# =============================================================================
# Obstacle grid (copy of AIDecisionMaker._build_obstacle_grid/_grid_nearby)
# =============================================================================

const BIG_OBSTACLE_RADIUS_PX := 100.0

static func _build_grid(entries: Array) -> Dictionary:
	var big: Array = []
	var small: Array = []
	var small_max := 0.0
	for e in entries:
		if e.r_out > BIG_OBSTACLE_RADIUS_PX:
			big.append(e)
		else:
			small.append(e)
			small_max = maxf(small_max, e.r_out)
	var cell: float = maxf(80.0, small_max * 2.0 + 40.0)
	var cells := {}
	for e in small:
		var key := Vector2i(int(floor(e.pos.x / cell)), int(floor(e.pos.y / cell)))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(e)
	return {"cell": cell, "cells": cells, "max_radius": small_max, "big": big, "count": entries.size()}

static func _grid_nearby(grid: Dictionary, pos: Vector2, query_radius: float) -> Array:
	"""A superset of the obstacles whose bounding circle can reach within
	query_radius of pos (oversized bases are always included)."""
	var out: Array = grid.big
	if grid.cells.is_empty():
		return out
	out = out.duplicate()
	var cell: float = grid.cell
	var reach: float = query_radius + grid.max_radius
	var cells: Dictionary = grid.cells
	for ix in range(int(floor((pos.x - reach) / cell)), int(floor((pos.x + reach) / cell)) + 1):
		for iy in range(int(floor((pos.y - reach) / cell)), int(floor((pos.y + reach) / cell)) + 1):
			var key := Vector2i(ix, iy)
			if cells.has(key):
				out.append_array(cells[key])
	return out

# =============================================================================
# Per-position legality (memoised)
# =============================================================================

static func _position_ok(ctx: Dictionary, mi: Dictionary, pos: Vector2, rot: float) -> bool:
	if ctx.no_memo:
		return _constraints_ok(ctx, mi, pos) and _check_model(ctx, mi, pos, rot, null)
	var key := Vector3i(int(round(pos.x / RASTER_PX)), int(round(pos.y / RASTER_PX)), 1 if absf(sin(rot)) > 0.5 else 0)
	var mm: Dictionary = ctx.memo[mi["class"]]
	if mm.has(key):
		ctx.memo_hits += 1
		return mm[key]
	var ok := _constraints_ok(ctx, mi, pos) and _check_model(ctx, mi, pos, rot, null)
	mm[key] = ok
	return ok

static func _check_model(ctx: Dictionary, mi: Dictionary, pos: Vector2, rot: float, errs) -> bool:
	"""DeploymentPhase's per-model checks. errs == null: stop at the first
	failure (search); errs is an Array: collect every message (placement_errors)."""
	ctx.fresh += 1
	var info: Dictionary = mi.info
	var meas = ctx.meas
	var ok := true
	var probe: Dictionary = mi.probe
	probe["position"] = pos
	probe["rotation"] = rot
	if mi.infil:
		# DeploymentPhase._validate_infiltrators_position (24.20).
		if pos.x < 0.0 or pos.x > ctx.board_w or pos.y < 0.0 or pos.y > ctx.board_h:
			if errs == null:
				return false
			ok = false
			errs.append("Model must be on the battlefield")
		var min_in: float = ctx.infil_min_in
		var ez: PackedVector2Array = ctx.enemy_zone
		if ez.size() > 0:
			if Geometry2D.is_point_in_polygon(pos, ez):
				if errs == null:
					return false
				ok = false
				errs.append("Infiltrators must be >%d\" from enemy deployment zone (model is inside enemy zone)" % int(min_in))
			else:
				var md := INF
				for i in range(ez.size()):
					md = minf(md, meas.point_to_line_distance(pos, ez[i], ez[(i + 1) % ez.size()]))
				if md / PX_PER_INCH - info.base_r_in < min_in:
					if errs == null:
						return false
					ok = false
					errs.append("Infiltrators must be >%d\" from enemy deployment zone (%.1f\")" % [int(min_in), md / PX_PER_INCH - info.base_r_in])
		for em in ctx.enemy_models:
			var ed: float = pos.distance_to(em.pos) / PX_PER_INCH - info.base_r_in - em.r
			if ed < min_in:
				if errs == null:
					return false
				ok = false
				errs.append("Infiltrators must be >%d\" from enemy models (%.1f\")" % [int(min_in), ed])
				break
	if ctx.check_zone and not (mi.infil and ctx.phase_exact):
		var poly: PackedVector2Array = ctx.poly
		var inside := Geometry2D.is_point_in_polygon(pos, poly)
		if inside and not meas.circle_wholly_in_polygon(pos, info.r_out, poly):
			inside = _shape_in_polygon_quiet(meas, info, pos, rot, poly)
		if not inside:
			if errs == null:
				return false
			ok = false
			errs.append("Model must be wholly within deployment zone")
	if not mi.skip:
		var hit := false
		for ob in _grid_nearby(ctx.grid, pos, info.r_out):
			var dd: float = pos.distance_to(ob.pos)
			if dd > info.r_out + ob.r_out:
				continue
			if dd < info.r_in + ob.r_in - 1.0 \
					or info.shape.overlaps_with(ob.shape, pos, rot, ob.pos, ob.rot) \
					or (info.type != ob.type and ob.shape.overlaps_with(info.shape, ob.pos, ob.rot, pos, rot)):
				hit = true
				break
		if hit:
			if errs == null:
				return false
			ok = false
			errs.append("Model cannot overlap with existing models")
	var r: float = info.r_out
	var box := Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0)
	var near_piece := false
	for bb in ctx.piece_boxes:
		if bb.intersects(box):
			near_piece = true
			break
	if near_piece and meas.model_overlaps_any_wall(probe, mi.kws):
		if errs == null:
			return false
		ok = false
		errs.append("Model cannot overlap with walls this unit can't cross")
	if meas.model_outside_board(pos, probe):
		if errs == null:
			return false
		ok = false
		errs.append("Model cannot be placed off the board")
	return ok

static func _shape_in_polygon_quiet(meas, info: Dictionary, center: Vector2, rot: float, poly: PackedVector2Array) -> bool:
	"""Measurement.shape_wholly_in_polygon without its per-call debug prints."""
	var shape = info.shape
	if info.type == "circular":
		return meas.circle_wholly_in_polygon(center, shape.radius, poly)
	if info.type == "oval":
		for i in range(16):
			var ang := (i * TAU) / 16
			if not Geometry2D.is_point_in_polygon(shape.to_world_space(Vector2(shape.length * cos(ang), shape.width * sin(ang)), center, rot), poly):
				return false
		return true
	var hw: float = info.hx
	var hh: float = info.hy
	for lp in [Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)]:
		if not Geometry2D.is_point_in_polygon(shape.to_world_space(lp, center, rot), poly):
			return false
	return true

# =============================================================================
# Templates: bodyguard blocks and character satellites
# =============================================================================

static func _q(v: float) -> float:
	return ceil(v / RASTER_PX - 0.0001) * RASTER_PX

static func _qs(v: float) -> float:
	# quantise AWAY from zero (keeps the gap >= GAP_PX on either side)
	return _q(v) if v >= 0.0 else -_q(-v)

static func _signature(ctx: Dictionary) -> String:
	var parts: Array = []
	for i in range(ctx.n_all):
		parts.append(ctx.mlist[i].info.skey + ("*" if ctx.mlist[i].is_char else ""))
	return ";".join(parts) + "#e%d#v%d" % [int(ctx.edition), int(ctx.opts.get("sat_variants", DEFAULT_SAT_VARIANTS))]

static func _blocks(ctx: Dictionary) -> Array:
	var sig := _signature(ctx)
	ctx["sig"] = sig
	if _block_cache.has(sig):
		return _block_cache[sig]
	var n: int = ctx.n_bg
	var rots: Array = [0.0]
	for i in range(n):
		if ctx.mlist[i].info.type != "circular":
			rots.append(PI / 2.0)
			break
	var out: Array = []
	for rot in rots:
		for cols in range(1, n + 1):
			for cl in [false, true]:
				if cl and (n % cols == 0):
					continue
				var blk := _make_block(ctx, rot, cols, cl)
				if not _template_legal(ctx, blk, n):
					continue
				if ctx.n_all > n:
					blk["variants"] = _make_variants(ctx, blk)
				out.append(blk)
	out.sort_custom(func(a, b):
		if a.key != b.key:
			return a.key < b.key
		if a.rot != b.rot:
			return a.rot < b.rot
		if a.cols != b.cols:
			return a.cols < b.cols
		return a.name < b.name)
	_block_cache[sig] = out
	return out

static func _make_block(ctx: Dictionary, rot: float, cols: int, center_last: bool) -> Dictionary:
	var n: int = ctx.n_bg
	var hx := 0.0
	var hy := 0.0
	for i in range(n):
		var he := _he(ctx.mlist[i].info, rot)
		hx = maxf(hx, he.x)
		hy = maxf(hy, he.y)
	var px := _q(hx * 2.0 + GAP_PX)
	var py := _q(hy * 2.0 + GAP_PX)
	var rows := int(ceil(float(n) / cols))
	var offs: Array = []
	for i in range(n):
		var r := i / cols
		var c := i % cols
		var in_row := cols if r < rows - 1 else n - cols * (rows - 1)
		var shift := 0.0
		if center_last and r == rows - 1 and in_row < cols:
			shift = _q((cols - in_row) * px * 0.5)
		offs.append(Vector2(c * px + shift, r * py))
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for o in offs:
		mn = Vector2(minf(mn.x, o.x), minf(mn.y, o.y))
		mx = Vector2(maxf(mx.x, o.x), maxf(mx.y, o.y))
	var c0 := ((mn + mx) * 0.5 / RASTER_PX).round() * RASTER_PX
	var rots: Array = []
	for i in range(n):
		offs[i] = offs[i] - c0
		rots.append(rot)
	var blk := _block_from_offsets(ctx, offs, rots, "%dx%d%s@%d" % [cols, rows, "c" if center_last else "", int(round(rad_to_deg(rot)))])
	blk["rot"] = rot
	blk["cols"] = cols
	blk["rows"] = rows
	return blk

static func _block_from_offsets(ctx: Dictionary, offs: Array, rots: Array, name: String) -> Dictionary:
	var fmn := Vector2(INF, INF)
	var fmx := Vector2(-INF, -INF)
	for i in range(offs.size()):
		var he := _he(ctx.mlist[i].info, rots[i])
		fmn = Vector2(minf(fmn.x, offs[i].x - he.x), minf(fmn.y, offs[i].y - he.y))
		fmx = Vector2(maxf(fmx.x, offs[i].x + he.x), maxf(fmx.y, offs[i].y + he.y))
	return {"offs": offs, "rots": rots, "fmn": fmn, "fmx": fmx, "name": name, "rot": 0.0, "cols": 0, "rows": 0,
		"key": int(round((fmx - fmn).length() / RASTER_PX)), "variants": []}

static func _satellite_slots(block: Dictionary, hc: Vector2) -> Array:
	"""Perimeter slots for a character whose footprint half extents are `hc`:
	on all four sides of the block's footprint AABB at GAP_PX clearance, aligned
	with every row / column centre and each side's midpoint, nearest first."""
	var fmn: Vector2 = block.fmn
	var fmx: Vector2 = block.fmx
	var ys := {}
	var xs := {}
	for o in block.offs:
		ys[o.y] = true
		xs[o.x] = true
	ys[_qs((fmn.y + fmx.y) * 0.5)] = true
	xs[_qs((fmn.x + fmx.x) * 0.5)] = true
	var right := _qs(fmx.x + GAP_PX + hc.x)
	var left := _qs(fmn.x - GAP_PX - hc.x)
	var bottom := _qs(fmx.y + GAP_PX + hc.y)
	var top := _qs(fmn.y - GAP_PX - hc.y)
	var out: Array = []
	for y in ys:
		out.append(Vector2(right, y))
		out.append(Vector2(left, y))
	for x in xs:
		out.append(Vector2(x, bottom))
		out.append(Vector2(x, top))
	out.sort_custom(func(a, b):
		var da: float = a.length_squared()
		var db: float = b.length_squared()
		if da != db:
			return da < db
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x)
	return out

static func _footprints_clear(p1: Vector2, h1: Vector2, p2: Vector2, h2: Vector2) -> bool:
	return absf(p1.x - p2.x) >= h1.x + h2.x + GAP_PX or absf(p1.y - p2.y) >= h1.y + h2.y + GAP_PX

static func _rotation_combos(ctx: Dictionary) -> Array:
	"""Rotation assignments for the character models: all-0 first, then by
	number of rotated models, then lexicographic; at most MAX_SAT_ROTATION_COMBOS."""
	var combos: Array = [[]]
	for j in range(ctx.n_bg, ctx.n_all):
		var next: Array = []
		for c in combos:
			for r in ctx.mlist[j].info.rots:
				var cc: Array = c.duplicate()
				cc.append(r)
				next.append(cc)
		combos = next
	combos.sort_custom(func(a, b):
		var na := 0
		var nb := 0
		for r in a:
			if r != 0.0:
				na += 1
		for r in b:
			if r != 0.0:
				nb += 1
		if na != nb:
			return na < nb
		for i in range(a.size()):
			if a[i] != b[i]:
				return a[i] < b[i]
		return false)
	return combos.slice(0, MAX_SAT_ROTATION_COMBOS)

static func _make_variants(ctx: Dictionary, block: Dictionary) -> Array:
	"""Satellite variants of `block`: each character model on a perimeter slot
	sized from ITS OWN base and rotation; at most sat_variants per rotation
	combination. Legality is checked lazily by the search."""
	var n_bg: int = ctx.n_bg
	var k: int = ctx.n_all - n_bg
	var max_v := int(ctx.opts.get("sat_variants", DEFAULT_SAT_VARIANTS))
	var variants: Array = []
	for combo in _rotation_combos(ctx):
		var hs: Array = []
		var slots: Array = []
		for j in range(k):
			var h := _he(ctx.mlist[n_bg + j].info, combo[j])
			hs.append(h)
			slots.append(_satellite_slots(block, h))
		var made := 0
		var seen := {}
		for start in range(slots[0].size()):
			if made >= max_v:
				break
			var chosen: Array = [slots[0][start]]
			for j in range(1, k):
				for cand in slots[j]:
					var clear := true
					for q in range(chosen.size()):
						if not _footprints_clear(cand, hs[j], chosen[q], hs[q]):
							clear = false
							break
					if clear:
						chosen.append(cand)
						break
			if chosen.size() < k:
				continue
			var vkey := str(chosen)
			if seen.has(vkey):
				continue
			seen[vkey] = true
			var offs: Array = block.offs.duplicate()
			var rots: Array = block.rots.duplicate()
			for j in range(k):
				offs.append(chosen[j])
				rots.append(combo[j])
			var cname := ""
			for r in combo:
				cname += "%d" % int(round(rad_to_deg(r)))
			variants.append({"offs": offs, "rots": rots, "name": "%s+sat%d@%s" % [block.name, start, cname]})
			made += 1
	return variants

static func _template_legal(ctx: Dictionary, t: Dictionary, n: int, bg_known_legal: bool = false) -> bool:
	"""Anchor-invariant legality of the first n models of template t: no two
	footprints overlap (both directions), the bodyguard alone is coherent and,
	with characters, the merged attached unit is coherent (19.01 + 03.03).
	bg_known_legal (L2-1): t's first n_bg offsets and rotations are those of a
	block that already passed this check (a satellite variant), so the
	bodyguard-pair overlaps and the bodyguard-only coherency are skipped — only
	the pairs with a character and the merged coherency are tested. Same
	verdict, about half the work."""
	var n_bg: int = mini(n, ctx.n_bg)
	for i in range(n):
		var si = ctx.mlist[i].info.shape
		for j in range(maxi(i + 1, n_bg) if bg_known_legal else i + 1, n):
			var sj = ctx.mlist[j].info.shape
			if si.overlaps_with(sj, t.offs[i], t.rots[i], t.offs[j], t.rots[j]) \
					or sj.overlaps_with(si, t.offs[j], t.rots[j], t.offs[i], t.rots[i]):
				return false
	var bg: Array = []
	var merged: Array = []
	for i in range(n):
		var m: Dictionary = ctx.mlist[i].m.duplicate()
		m["position"] = t.offs[i]
		m["rotation"] = t.rots[i]
		m["alive"] = true
		m["id"] = "f%d" % i
		merged.append(m)
		if i < n_bg:
			bg.append(m)
	if not bg_known_legal and n_bg > 1 and not AttackSequence.check_unit_coherency({"models": bg}).get("coherent", false):
		return false
	if n > n_bg and not AttackSequence.check_unit_coherency({"models": merged}).get("coherent", false):
		return false
	return true

static func _variant_legal(ctx: Dictionary, t: Dictionary) -> bool:
	"""A satellite variant of a block that passed _template_legal (_blocks,
	_preferred_block): only the character pairs and the merged coherency are
	left to check (L2-1)."""
	var key := str(ctx.sig) + "#" + str(t.name)
	if _variant_legal_cache.has(key):
		return _variant_legal_cache[key]
	var ok := _template_legal(ctx, t, ctx.n_all, true)
	_variant_legal_cache[key] = ok
	return ok

# =============================================================================
# Anchors
# =============================================================================

static func _lattice(poly: PackedVector2Array, step: float) -> PackedVector2Array:
	var key := "%d:%d:%d" % [poly.size(), hash(poly), int(step)]
	if _lattice_cache.has(key):
		return _lattice_cache[key]
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for v in poly:
		mn = Vector2(minf(mn.x, v.x), minf(mn.y, v.y))
		mx = Vector2(maxf(mx.x, v.x), maxf(mx.y, v.y))
	var out := PackedVector2Array()
	var y: float = ceil(mn.y / step) * step
	while y <= mx.y:
		var x: float = ceil(mn.x / step) * step
		while x <= mx.x:
			var p := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(p, poly):
				out.append(p)
			x += step
		y += step
	_lattice_cache[key] = out
	return out

static func _anchor_cursor(points: PackedVector2Array, desired: Vector2) -> Dictionary:
	"""Lattice points in (distance², y, x) order, produced ring by ring so a
	search that succeeds early never sorts the whole zone."""
	var buckets: Array = []
	for p in points:
		var b := int(p.distance_to(desired) / ANCHOR_STEP_PX)
		while buckets.size() <= b:
			buckets.append([])
		buckets[b].append(p)
	return {"buckets": buckets, "b": 0, "i": 0, "sorted": false, "desired": desired}

static func _next_anchor(cur: Dictionary):
	var buckets: Array = cur.buckets
	while cur.b < buckets.size():
		var bucket: Array = buckets[cur.b]
		if not cur.sorted:
			var d: Vector2 = cur.desired
			bucket.sort_custom(func(a, b):
				var da: float = a.distance_squared_to(d)
				var db: float = b.distance_squared_to(d)
				if da != db:
					return da < db
				if a.y != b.y:
					return a.y < b.y
				return a.x < b.x)
			cur.sorted = true
		if cur.i < bucket.size():
			var p: Vector2 = bucket[cur.i]
			cur.i += 1
			return p
		cur.b += 1
		cur.i = 0
		cur.sorted = false
	return null

# =============================================================================
# Search
# =============================================================================

static func _search(ctx: Dictionary, desired: Vector2) -> Dictionary:
	var opts: Dictionary = ctx.opts
	var max_evals := int(opts.get("max_evals", DEFAULT_MAX_EVALS))
	var max_fresh := int(opts.get("max_fresh", DEFAULT_MAX_FRESH))
	# P0.3: a caller-supplied shape (the 11e picker's pocket fill) goes first.
	var seed = opts.get("seed_positions", [])
	if seed is Array and not seed.is_empty():
		var seeded := _try_seed(ctx, seed, desired)
		if not seeded.is_empty():
			return seeded
	var blocks: Array = _blocks(ctx)
	var build_blocks: Array = []
	var pref = opts.get("preferred_offsets", [])
	if pref is Array and pref.size() == ctx.unit.get("models", []).size() and not pref.is_empty():
		var pb := _preferred_block(ctx, pref)
		if not pb.is_empty():
			build_blocks.append(pb)
	build_blocks.append_array(blocks)
	if build_blocks.is_empty():
		return _grow_or_fail(ctx, desired, "no legal block for this unit's bases", 0)
	var cur := _anchor_cursor(_anchor_points(ctx, ANCHOR_STEP_PX), desired)
	var max_disp: float = ctx.max_disp
	var evals := 0
	var why := ""
	while why.is_empty():
		var a = _next_anchor(cur)
		if a == null:
			why = "nothing fits: %d blocks over the %s lattice" % [build_blocks.size(), "region" if _has_region(ctx) else "zone"]
			break
		if (a as Vector2).distance_to(desired) > max_disp:
			why = "nothing fits within %.1f\" of the spot (%d blocks)" % [max_disp / PX_PER_INCH, build_blocks.size()]
			break
		for bi in range(build_blocks.size()):
			evals += 1
			if evals > max_evals or ctx.fresh > max_fresh:
				why = "budget (evals=%d fresh=%d)" % [evals, ctx.fresh]
				break
			var blk: Dictionary = build_blocks[bi]
			if not _bodyguard_fits(ctx, blk, bi, a):
				continue
			var chosen: Dictionary = blk
			if ctx.n_all > ctx.n_bg:
				chosen = _fit_satellites(ctx, blk, a)
				if chosen.is_empty():
					continue
			var cand := _candidate(ctx, a, chosen)
			if _excluded(ctx, cand):
				continue
			var g := _gate(ctx, cand)
			if g.ok:
				return _success(ctx, cand, chosen.name, a, a.distance_to(desired), evals, false)
			if g.unit_level or ctx.gate_rejections >= MAX_GATE_REJECTIONS:
				return _fail(ctx, "refused by the phase: %s" % "; ".join(g.errors), evals)
	return _grow_or_fail(ctx, desired, why, evals)

static func _has_region(ctx: Dictionary) -> bool:
	var region = ctx.opts.get("anchor_region", [])
	return region is Array and not region.is_empty()

static func _anchor_points(ctx: Dictionary, step: float) -> PackedVector2Array:
	"""Anchor / growth-seed lattice: the zone lattice, or — with anchor_region
	— its points inside the region polygons (region order, then y, then x;
	the cursor re-sorts by distance with a total tie-break)."""
	if not _has_region(ctx):
		return _lattice(ctx.poly, step)
	var out := PackedVector2Array()
	var seen := {}
	for e in _poly_list(ctx.opts.anchor_region):
		var pk: PackedVector2Array = e.poly
		var box: Rect2 = e.box
		var y: float = ceil(box.position.y / step) * step
		while y <= box.end.y:
			var x: float = ceil(box.position.x / step) * step
			while x <= box.end.x:
				var p := Vector2(x, y)
				var key := Vector2i(int(round(x / step)), int(round(y / step)))
				if not seen.has(key) and Geometry2D.is_point_in_polygon(p, pk) \
						and (not ctx.check_zone or (ctx.poly as PackedVector2Array).size() < 3 or Geometry2D.is_point_in_polygon(p, ctx.poly)):
					seen[key] = true
					out.append(p)
				x += step
			y += step
	return out

static func _try_seed(ctx: Dictionary, seed: Array, desired: Vector2) -> Dictionary:
	"""seed_positions, verbatim at rotation 0: every model legal there (phase
	predicates + spot constraints), no overlaps (both directions), the
	bodyguard and the merged attached unit coherent, then the gate. {} = the
	seed does not hold; the search continues. Not memoised: seed points are not
	on the raster, so memo keys would alias."""
	var n: int = ctx.n_all
	if seed.size() != n:
		ctx["seed_reason"] = "seed has %d positions for %d models" % [seed.size(), n]
		return {}
	var pts: Array = []
	var centre := Vector2.ZERO
	for p in seed:
		if p == null:
			ctx["seed_reason"] = "seed has an empty slot"
			return {}
		var v := _vec(p)
		pts.append(v)
		centre += v
	centre /= float(n)
	for i in range(n):
		if not _constraints_ok(ctx, ctx.mlist[i], pts[i]) or not _check_model(ctx, ctx.mlist[i], pts[i], 0.0, null):
			ctx["seed_reason"] = "model slot %d is not legal at its seed spot" % i
			return {}
	var offs: Array = []
	var rots: Array = []
	for i in range(n):
		offs.append(pts[i] - centre)
		rots.append(0.0)
	var t := {"offs": offs, "rots": rots, "name": "seed"}
	if not _template_legal(ctx, t, n):
		ctx["seed_reason"] = "seed shape overlaps or is not coherent"
		return {}
	var cand := _candidate(ctx, centre, t)
	# Keep the caller's exact positions (not centre + offset).
	for i in range(ctx.n_bg):
		cand.positions[ctx.mlist[i].idx] = pts[i]
	var k: int = ctx.n_bg
	for cid in cand.ccd:
		for entry in cand.ccd[cid]:
			entry["x"] = (pts[k] as Vector2).x
			entry["y"] = (pts[k] as Vector2).y
			k += 1
	if _excluded(ctx, cand):
		ctx["seed_reason"] = "seed is an excluded placement"
		return {}
	var g := _gate(ctx, cand)
	if g.ok:
		return _success(ctx, cand, "seed", centre, centre.distance_to(desired), 0, false)
	if g.unit_level or ctx.gate_rejections >= MAX_GATE_REJECTIONS:
		return _fail(ctx, "refused by the phase: %s" % "; ".join(g.errors), 0)
	ctx["seed_reason"] = "the phase refused the seed"
	return {}

static func _bodyguard_fits(ctx: Dictionary, blk: Dictionary, bi: int, a: Vector2) -> bool:
	# Fail-first: start with the model that failed last time for this block (per build).
	var mlist: Array = ctx.mlist
	var ff := int(ctx.ff.get(bi, 0))
	if not _position_ok(ctx, mlist[ff], a + blk.offs[ff], blk.rots[ff]):
		return false
	for i in range(ctx.n_bg):
		if i == ff:
			continue
		if not _position_ok(ctx, mlist[i], a + blk.offs[i], blk.rots[i]):
			ctx.ff[bi] = i
			return false
	return true

static func _fit_satellites(ctx: Dictionary, blk: Dictionary, a: Vector2) -> Dictionary:
	for t in blk.variants:
		if not _variant_legal(ctx, t):
			continue
		var fits := true
		for j in range(ctx.n_bg, ctx.n_all):
			if not _position_ok(ctx, ctx.mlist[j], a + t.offs[j], t.rots[j]):
				fits = false
				break
		if fits:
			return t
	return {}

static func _preferred_block(ctx: Dictionary, pref: Array) -> Dictionary:
	"""The caller's rigid shape (plan repair), snapped to the raster, if it is a
	legal block on its own. Characters get satellite variants as usual."""
	var offs: Array = []
	var rots: Array = []
	for i in range(ctx.n_bg):
		var o = pref[ctx.mlist[i].idx]
		if o == null:
			return {}
		offs.append((_vec(o) / RASTER_PX).round() * RASTER_PX)
		rots.append(0.0)
	# The name keys the variant-legality cache, so it must identify the shape.
	var blk := _block_from_offsets(ctx, offs, rots, "preferred%d" % hash(str(offs)))
	if not _template_legal(ctx, blk, ctx.n_bg):
		return {}
	if ctx.n_all > ctx.n_bg:
		blk["variants"] = _make_variants(ctx, blk)
	return blk

static func _candidate(ctx: Dictionary, a: Vector2, t: Dictionary) -> Dictionary:
	var models: Array = ctx.unit.get("models", [])
	var positions: Array = []
	var rotations: Array = []
	positions.resize(models.size())
	rotations.resize(models.size())
	for i in range(models.size()):
		positions[i] = null
		rotations[i] = 0.0
	for i in range(ctx.n_bg):
		positions[ctx.mlist[i].idx] = a + t.offs[i]
		rotations[ctx.mlist[i].idx] = t.rots[i]
	var ccd := {}
	for j in range(ctx.n_bg, ctx.n_all):
		var mi: Dictionary = ctx.mlist[j]
		if not ccd.has(mi.unit_id):
			ccd[mi.unit_id] = []
		var p: Vector2 = a + t.offs[j]
		ccd[mi.unit_id].append({"model_idx": mi.idx, "x": p.x, "y": p.y, "rotation": t.rots[j]})
	return {"positions": positions, "rotations": rotations, "ccd": ccd}

static func _excluded(ctx: Dictionary, cand: Dictionary) -> bool:
	for ex in ctx.opts.get("exclude_positions", []):
		if not (ex is Array) or ex.size() != cand.positions.size():
			continue
		var same := true
		for i in range(ex.size()):
			var a = ex[i]
			var b = cand.positions[i]
			if (a == null) != (b == null):
				same = false
				break
			if a != null and _vec(a).distance_to(_vec(b)) > 1.0:
				same = false
				break
		if same:
			return true
	return false

static func _gate(ctx: Dictionary, cand: Dictionary) -> Dictionary:
	"""Exact final check of the action the AI will send."""
	if not ctx.opts.get("final_gate", true):
		return {"ok": true, "unit_level": false, "errors": []}
	var errors: Array = []
	var source := "placement_errors"
	if not ctx.has("live_phase"):
		ctx["live_phase"] = _live_deployment_phase(ctx.snapshot)
	var phase = ctx.live_phase
	if phase != null and is_instance_valid(phase):
		source = "DeploymentPhase.validate_action"
		var action := {"type": "COMPOSITE_DEPLOY" if not cand.ccd.is_empty() else "DEPLOY_UNIT",
			"unit_id": ctx.unit_id, "model_positions": cand.positions.duplicate(),
			"model_rotations": cand.rotations.duplicate(), "player": ctx.player}
		if not cand.ccd.is_empty():
			action["combined_char_data"] = cand.ccd.duplicate(true)
		var v: Dictionary = phase.validate_action(action)
		if not v.get("valid", false):
			errors = v.get("errors", [])
			if errors.is_empty():
				errors = [str(v.get("reason", "rejected"))]
	else:
		var saved_memo: bool = ctx.no_memo
		var saved_fresh: int = ctx.fresh
		ctx.no_memo = true
		ctx.phase_exact = true
		errors = _placement_errors_ctx(ctx, cand.positions, cand.rotations, cand.ccd)
		ctx.phase_exact = false
		ctx.no_memo = saved_memo
		ctx.fresh = saved_fresh   # the gate is not part of the search budget
	if errors.is_empty():
		return {"ok": true, "unit_level": false, "errors": []}
	var unit_level := false
	for e in errors:
		if not is_position_error(str(e)):
			unit_level = true
	if not unit_level and not ctx.get("quiet_gate", false):
		ctx.gate_rejections += 1
		var msg := "%s refused a builder placement for %s (%d/%d): %s" % [source, ctx.unit_name,
			ctx.gate_rejections, MAX_GATE_REJECTIONS, "; ".join(errors)]
		_defect(msg)
	return {"ok": false, "unit_level": unit_level, "errors": errors}

static func _success(ctx: Dictionary, cand: Dictionary, template: String, anchor: Vector2, disp: float, evals: int, grown: bool) -> Dictionary:
	return {"ok": true, "reason": "", "model_positions": cand.positions, "model_rotations": cand.rotations,
		"combined_char_data": cand.ccd, "action_type": "COMPOSITE_DEPLOY" if not cand.ccd.is_empty() else "DEPLOY_UNIT",
		"template": template, "anchor": anchor, "displacement_px": disp, "evals": evals, "fresh": ctx.fresh,
		"memo_hits": ctx.memo_hits, "grown": grown, "gate_rejections": ctx.gate_rejections, "grow_work": int(ctx.get("grow_work", 0))}

static func _fail(ctx: Dictionary, reason: String, evals: int = 0) -> Dictionary:
	return {"ok": false, "reason": reason, "model_positions": [], "model_rotations": [], "combined_char_data": {},
		"action_type": "DEPLOY_UNIT", "template": "", "anchor": Vector2.INF, "displacement_px": 0.0,
		"evals": evals, "fresh": int(ctx.get("fresh", 0)), "memo_hits": int(ctx.get("memo_hits", 0)),
		"grown": false, "gate_rejections": int(ctx.get("gate_rejections", 0)), "grow_work": int(ctx.get("grow_work", 0))}

# =============================================================================
# Growth fallback
# =============================================================================
# Seeds (L2-2): every legal model-0 cell of the zone lattice (or anchor_region,
# within max_displacement_px), ranked by FREE ROOM — the number of legal
# model-0 cells within 3" (GROW_ROOM_CELLS lattice steps) — roomiest first,
# ties nearest the desired spot first ((distance², y, x)). Nearest-first seeds
# used to cluster round the desired spot: in a crowded zone every one of them
# was a dead end that spent the shared work budget, and a unit with open
# ground elsewhere was reported as having no legal set-up (and went to
# Strategic Reserves). From a seed, add each next model at the legal cell
# nearest the placed centroid that overlaps no placed model (both
# directions), is within 2" of enough placed models (1; at 10e, 2 once a 7+
# model unit has two placed) and — at 11e — within 9" of all of them (03.03).
# Characters are grown last, so the bodyguard alone is coherent too; the whole
# formation is then re-checked with AttackSequence. Budgets unchanged: at most
# grow_seeds seeds, 1.5 x max_fresh fresh checks (search included) and
# max_grow_work work units in all (seed ranking included), no per-seed cap.

const GROW_ROOM_CELLS := 6     # growth-seed free room: at least 6 lattice steps (3"), more for a bigger unit
const GROW_ROOM_MAX_CELLS := 16  # ... and at most 16 (8")

static func _grow_or_fail(ctx: Dictionary, desired: Vector2, why: String, evals: int) -> Dictionary:
	if not ctx.opts.get("grow", true):
		return _fail(ctx, why, evals)
	var g := _grow(ctx, desired)
	if g.ok:
		return _success(ctx, g.cand, "grown", g.anchor, g.centroid.distance_to(desired), evals, true)
	return _fail(ctx, "%s; %s" % [why, str(g.reason)], evals)

static func _grow_seed_order(ctx: Dictionary, desired: Vector2, fresh_cap: int, max_work: int, max_seeds: int, slots: Array = [0]) -> Dictionary:
	"""Growth seeds ranked by free room (L2-2). The growth lattice within
	max_displacement_px is enumerated in (distance², y, x) order (the anchor
	cursor; anchor_region honoured) and every cell is given ROOM = the number
	of legal model-0 cells (the bulk of the unit) within _grow_room_cells
	lattice steps (a disc, the cell itself included; row prefix sums, 2R+1
	reads a cell). Seeds per requested slot, by (room desc, distance rank asc)
	— deterministic, no sort: slot 0, the legal model-0 cells; another slot (a
	big character, see _grow_plans), the cells where THAT model is legal,
	tested lazily in room order until max_seeds are found. Work: 1 per lattice
	cell enumerated, 1 per prefix-sum cell, 2R+1 per cell scored; the lazy
	tests are fresh checks. {ok, reason, orders: {slot: [[cell, rot]]},
	legal (legal model-0 cells)}."""
	var mi0: Dictionary = ctx.mlist[0]
	var cur := _anchor_cursor(_anchor_points(ctx, GROW_STEP_PX), desired)
	var max_disp: float = ctx.max_disp
	var cells: Array = []    # [cell, rot (model 0) or null, ix, iy] in distance order
	var n_legal := 0
	var x0 := 1 << 30
	var y0 := 1 << 30
	var x1 := -(1 << 30)
	var y1 := -(1 << 30)
	while true:
		if ctx.fresh > fresh_cap or int(ctx.grow_work) > max_work:
			return {"ok": false, "legal": n_legal, "orders": {},
				"reason": "grow budget (fresh=%d work=%d) ranking seeds (%d legal cells so far)" % [ctx.fresh, int(ctx.grow_work), n_legal]}
		var c = _next_anchor(cur)
		if c == null or (c as Vector2).distance_to(desired) > max_disp:
			break
		ctx.grow_work += 1
		var ix := int(round((c as Vector2).x / GROW_STEP_PX))
		var iy := int(round((c as Vector2).y / GROW_STEP_PX))
		var r0 = null
		for rot in mi0.info.rots:
			if _position_ok(ctx, mi0, c, rot):
				r0 = float(rot)
				break
		if r0 != null:
			n_legal += 1
			x0 = mini(x0, ix)
			y0 = mini(y0, iy)
			x1 = maxi(x1, ix)
			y1 = maxi(y1, iy)
		if r0 != null or slots != [0]:
			cells.append([c, r0, ix, iy])
	if n_legal == 0:
		return {"ok": true, "reason": "", "orders": {}, "legal": 0}
	var R := _grow_room_cells(ctx)
	var pad := 2 * R                         # a scored cell may lie up to R outside the legal box
	var stride := x1 - x0 + 1 + 2 * pad + 1  # padded row width + the prefix column
	var rows := y1 - y0 + 1 + 2 * pad
	var pre := PackedInt32Array()
	pre.resize(rows * stride)
	pre.fill(0)
	for e in cells:
		if e[1] != null:
			pre[(int(e[3]) - y0 + pad) * stride + (int(e[2]) - x0 + pad) + 1] = 1
	for row in range(rows):
		var base := row * stride
		for col in range(1, stride):
			pre[base + col] += pre[base + col - 1]
	ctx.grow_work += rows * stride
	var half: Array = []     # disc half-width per row offset -R..R
	for dy in range(-R, R + 1):
		var w := 0
		while (w + 1) * (w + 1) + dy * dy <= R * R:
			w += 1
		half.append(w)
	var buckets: Array = []  # room -> entries, distance order kept
	buckets.resize((2 * R + 1) * (2 * R + 1) + 1)
	for i in range(buckets.size()):
		buckets[i] = []
	var scored := 0
	for e in cells:
		var ix: int = e[2]
		var iy: int = e[3]
		if ix < x0 - R or ix > x1 + R or iy < y0 - R or iy > y1 + R:
			(buckets[0] as Array).append(e)   # no legal model-0 cell within R: no room
			continue
		var col := ix - x0 + pad
		var row := iy - y0 + pad
		var sc := 0
		for k in range(2 * R + 1):
			var base := (row + k - R) * stride
			sc += pre[base + col + int(half[k]) + 1] - pre[base + col - int(half[k])]
		(buckets[sc] as Array).append(e)
		scored += 1
	ctx.grow_work += scored * (2 * R + 1)
	var orders := {}
	for slot in slots:
		var order: Array = []
		var ms: Dictionary = ctx.mlist[int(slot)]
		for sc in range(buckets.size() - 1, -1, -1):
			for e in buckets[sc]:
				if order.size() >= max_seeds:
					break
				if int(slot) == 0:
					if e[1] != null:
						order.append([e[0], e[1]])
					continue
				if ctx.fresh > fresh_cap:
					break
				for rot in ms.info.rots:
					if _position_ok(ctx, ms, e[0], rot):
						order.append([e[0], float(rot)])
						break
			if order.size() >= max_seeds:
				break
		orders[int(slot)] = order
	return {"ok": true, "reason": "", "orders": orders, "legal": n_legal}

static func _grow_room_cells(ctx: Dictionary) -> int:
	"""Radius (lattice steps) of the free-room disc that ranks growth seeds: the
	disc whose area is the unit's whole footprint (every slot's footprint box
	plus the template gap), at least GROW_ROOM_CELLS (3") and at most
	GROW_ROOM_MAX_CELLS. A 3" disc holds 10 Boyz but not 20 Boyz and a Wartrike."""
	var area := 0.0
	for mi in ctx.mlist:
		area += (2.0 * float(mi.info.hx) + GAP_PX) * (2.0 * float(mi.info.hy) + GAP_PX)
	var r_cells := int(ceil(sqrt(area / PI) / GROW_STEP_PX))
	return clampi(r_cells, GROW_ROOM_CELLS, GROW_ROOM_MAX_CELLS)

static func _grow(ctx: Dictionary, desired: Vector2) -> Dictionary:
	var max_fresh := int(ctx.opts.get("max_fresh", DEFAULT_MAX_FRESH))
	var fresh_cap: int = max_fresh + max_fresh / 2
	var max_work := int(ctx.opts.get("max_grow_work", DEFAULT_MAX_GROW_WORK))
	var max_seeds := int(ctx.opts.get("grow_seeds", DEFAULT_GROW_SEEDS))
	var plans := _grow_plans(ctx)
	var slots: Array = []
	for plan in plans:
		if not (int(plan.seed_slot) in slots):
			slots.append(int(plan.seed_slot))
	var ranked := _grow_seed_order(ctx, desired, fresh_cap, max_work, max_seeds, slots)
	if not bool(ranked.ok):
		return {"ok": false, "reason": str(ranked.reason)}
	var legal := int(ranked.legal)
	for plan in plans:
		var sl := int(plan.seed_slot)
		if sl != 0 and (ranked.orders.get(sl, []) as Array).is_empty() and ctx.fresh <= fresh_cap:
			# Every lattice cell was tested: the character fits nowhere, so no
			# grown formation can hold it (exact for the growth lattice).
			var mb: Dictionary = ctx.mlist[sl]
			return {"ok": false, "reason": "grow: %s (%smm) has no legal position on the zone's 0.5\" growth lattice" % [str(mb.unit_id), str(mb.m.get("base_mm", 32))]}
	# Round-robin over the plans: seed 1 of each plan, then seed 2 of each ...
	# at most grow_seeds seeds in all.
	var queue: Array = []
	var longest := 0
	for plan in plans:
		longest = maxi(longest, (ranked.orders.get(int(plan.seed_slot), []) as Array).size())
	for si in range(longest):
		for plan in plans:
			var po: Array = ranked.orders.get(int(plan.seed_slot), [])
			if si < po.size() and queue.size() < max_seeds:
				queue.append([po[si], plan.order])
	var seeds := 0
	var stuck := {}   # why each seed failed: "model <k>" / "coherency" / "excluded" / "gate"
	for q in queue:
		var e0: Array = q[0]
		var gorder: Array = q[1]
		if ctx.fresh > fresh_cap or int(ctx.grow_work) > max_work:
			return {"ok": false, "reason": "grow budget (fresh=%d work=%d, %d seeds of %d legal cells, roomiest first%s)" % [
				ctx.fresh, int(ctx.grow_work), seeds, legal, _stuck_text(ctx, stuck)]}
		seeds += 1
		var gr := _grow_from_seed(ctx, e0[0], float(e0[1]), gorder, fresh_cap, max_work)
		if not bool(gr.ok):
			_stuck_note(stuck, str(gr.stuck))
			continue
		var placed: Array = gr.placed
		var t := {"offs": [], "rots": [], "name": "grown"}
		for e in placed:
			t.offs.append(e.pos)
			t.rots.append(e.rot)
		var cand := _candidate(ctx, Vector2.ZERO, t)
		if _excluded(ctx, cand):
			_stuck_note(stuck, "excluded")
			continue
		var g := _gate(ctx, cand)
		if g.ok:
			return {"ok": true, "cand": cand, "anchor": e0[0], "centroid": _centroid(placed), "seeds": seeds}
		_stuck_note(stuck, "gate")
		if g.unit_level or ctx.gate_rejections >= MAX_GATE_REJECTIONS:
			return {"ok": false, "reason": "refused by the phase: %s" % "; ".join(g.errors)}
	return {"ok": false, "reason": "grow: no seed grew to %d models (%d seeds of %d legal cells, roomiest first%s)" % [
		ctx.n_all, seeds, legal, _stuck_text(ctx, stuck)]}

static func _grow_from_seed(ctx: Dictionary, seed_cell: Vector2, seed_rot: float, gorder: Array, fresh_cap: int, max_work: int) -> Dictionary:
	"""Grow one formation from model 0 at seed_cell, adding models in gorder
	(model-slot indices). {ok, placed (slot order), stuck ("model <k>" — no
	legal coherent cell for slot k, or the budget ran out there — or
	"coherency": the whole formation failed AttackSequence's check)}."""
	var mlist: Array = ctx.mlist
	var n: int = ctx.n_all
	var n_bg: int = ctx.n_bg
	var s0: int = gorder[0]
	var placed: Array = [{"pos": seed_cell, "rot": seed_rot, "mi": mlist[s0], "i": s0}]
	var bg_down := 1 if s0 < n_bg else 0
	var frontiers := {}   # incremental candidate cells per model shape (see _frontier_cells)
	for step in range(1, n):
		var k: int = gorder[step]
		if ctx.fresh > fresh_cap or int(ctx.grow_work) > max_work:
			return {"ok": false, "stuck": "model %d" % k}
		var cen := _centroid(placed)
		# A bodyguard model must be in 2" coherency with the BODYGUARD (the
		# bodyguard alone stays coherent, as before) — except the first one
		# down after a character seed, which joins the character; a character
		# joins any placed model. The 9" envelope (11e) is checked against all.
		var bg_step := k < n_bg and bg_down > 0
		var group_n := n_bg if k < n_bg else n
		var cells := _frontier_cells(ctx, frontiers, placed, mlist[k], ctx.poly, bg_step)
		cells.sort_custom(func(a, b):
			var da: float = a.distance_squared_to(cen)
			var db: float = b.distance_squared_to(cen)
			if da != db:
				return da < db
			if a.y != b.y:
				return a.y < b.y
			return a.x < b.x)
		var best = null
		for c in cells:
			for rot in mlist[k].info.rots:
				ctx.grow_work += 1
				if not _position_ok(ctx, mlist[k], c, rot):
					continue
				if _overlaps_placed(c, mlist[k], rot, placed):
					continue
				if not _coherent_step(ctx, c, mlist[k], rot, placed, group_n, bg_step):
					continue
				best = {"pos": c, "rot": rot, "mi": mlist[k], "i": k}
				break
			if best != null:
				break
		if best == null:
			return {"ok": false, "stuck": "model %d" % k}
		placed.append(best)
		if k < n_bg:
			bg_down += 1
	# Back to model-slot order (the template is indexed like mlist).
	var by_slot: Array = []
	by_slot.resize(n)
	for e in placed:
		by_slot[int(e.i)] = e
	var bg: Array = []
	var merged: Array = []
	for i in range(n):
		var pm := _placed_model(by_slot[i], i)
		merged.append(pm)
		if i < n_bg:
			bg.append(pm)
	if n_bg > 1 and not AttackSequence.check_unit_coherency({"models": bg}).get("coherent", false):
		return {"ok": false, "stuck": "coherency"}
	if n > n_bg and not AttackSequence.check_unit_coherency({"models": merged}).get("coherent", false):
		return {"ok": false, "stuck": "coherency"}
	return {"ok": true, "placed": by_slot, "stuck": ""}

static func _grow_plans(ctx: Dictionary) -> Array:
	"""Growth plans [{seed_slot, order}] (model-slot indices), tried in turn
	under the one budget. A unit with characters bigger than every bodyguard
	model is SEEDED at its biggest character, ranked by that model's own free
	room — the 150mm Wartrike, not a 32mm Boy, is what decides whether a seed
	can grow: grown after 20 Boyz it found no room left beside them, and a seed
	roomy for a Boy had no 150mm cell beside it — then grows the other big
	characters, the bodyguard and the other characters. Otherwise the seed is
	bodyguard model 0 and characters grow last. opts grow_plan (experiment
	switch): "auto" (above), "model0" (seed at model 0, big characters right
	after it), "last" (seed at model 0, characters last)."""
	var mode := str(ctx.opts.get("grow_plan", "auto"))
	if OS.get_environment("F1_GROW_PLAN") != "" and not ctx.opts.has("grow_plan"):   # F1-EXPERIMENT (remove)
		mode = OS.get_environment("F1_GROW_PLAN")
	var big := _grow_big_slots(ctx)
	var bg: Array = []
	for i in range(ctx.n_bg):
		bg.append(i)
	var small: Array = []
	var chars: Array = []
	for j in range(ctx.n_bg, ctx.n_all):
		chars.append(j)
		if not (j in big):
			small.append(j)
	var p_last := {"seed_slot": 0, "order": bg + chars}
	if mode == "last" or big.is_empty():
		return [p_last]
	var p_model0 := {"seed_slot": 0, "order": [0] + big + bg.slice(1) + small}
	var p_big := {"seed_slot": int(big[0]), "order": big + bg + small}
	if mode == "model0":
		return [p_model0]
	if mode == "big":
		return [p_big]
	return [p_model0, p_big, p_last]

static func _grow_big_slots(ctx: Dictionary) -> Array:
	"""Character slots whose footprint is larger than every bodyguard model's
	(bounding radius + 0.5 px), largest first, then slot order."""
	var bg_r := 0.0
	for i in range(ctx.n_bg):
		bg_r = maxf(bg_r, float(ctx.mlist[i].info.r_out))
	var big: Array = []
	for j in range(ctx.n_bg, ctx.n_all):
		if float(ctx.mlist[j].info.r_out) > bg_r + 0.5:
			big.append(j)
	big.sort_custom(func(a, b):
		var ra: float = ctx.mlist[a].info.r_out
		var rb: float = ctx.mlist[b].info.r_out
		if ra != rb:
			return ra > rb
		return a < b)
	return big

static func _stuck_note(stuck: Dictionary, key: String) -> void:
	stuck[key] = int(stuck.get(key, 0)) + 1

static func _stuck_text(ctx: Dictionary, stuck: Dictionary) -> String:
	"""'; stuck: model 21 (T_TRIKE 150mm) x3, coherency x1' — where each failed
	seed stopped (diagnostics for the failure reason)."""
	if stuck.is_empty():
		return ""
	var keys: Array = stuck.keys()
	keys.sort()
	var parts: Array = []
	for key in keys:
		var label := str(key)
		if label.begins_with("model "):
			var k := int(label.substr(6))
			if k >= 0 and k < (ctx.mlist as Array).size():
				var mi: Dictionary = ctx.mlist[k]
				label += " (%s %smm%s)" % [str(mi.unit_id), str(mi.m.get("base_mm", 32)), " char" if bool(mi.is_char) else ""]
		parts.append("%s x%d" % [label, int(stuck[key])])
	return "; stuck: " + ", ".join(parts)

static func _placed_model(entry: Dictionary, i: int) -> Dictionary:
	var m: Dictionary = entry.mi.m.duplicate()
	m["position"] = entry.pos
	m["rotation"] = entry.rot
	m["alive"] = true
	m["id"] = "g%d" % i
	return m

static func _overlaps_placed(pos: Vector2, mi: Dictionary, rot: float, placed: Array) -> bool:
	var sh = mi.info.shape
	for e in placed:
		if pos.distance_to(e.pos) > mi.info.r_out + e.mi.info.r_out + 1.0:
			continue
		var so = e.mi.info.shape
		if sh.overlaps_with(so, pos, rot, e.pos, e.rot) or so.overlaps_with(sh, e.pos, e.rot, pos, rot):
			return true
	return false

static func _coherent_step(ctx: Dictionary, pos: Vector2, mi: Dictionary, rot: float, placed: Array, group_n: int,
		near_bg_only: bool = false) -> bool:
	"""Within 2" of enough placed models (1; at 10e 2 once a 7+ model group has
	two placed) and — at 11e — within 9" of every placed model. near_bg_only:
	only placed BODYGUARD models count as 2" neighbours (a bodyguard model of an
	attached unit grown after its big characters)."""
	var meas = ctx.meas
	var tol: float = meas.DISTANCE_TOLERANCE_INCHES
	var coh_px: float = meas.inches_to_px(GameConstants.coherency_distance_inches() + tol) - 1.0
	var env_px: float = INF
	if int(ctx.edition) >= 11:
		env_px = meas.inches_to_px(GameConstants.coherency_envelope_inches() + tol) - 1.0
	var counted := 0
	for e in placed:
		if not near_bg_only or not bool(e.mi.is_char):
			counted += 1
	var need := 1
	if int(ctx.edition) < 11 and group_n >= 7 and counted >= 2:
		need = 2
	var probe: Dictionary = mi.m.duplicate()
	probe["position"] = pos
	probe["rotation"] = rot
	ctx.grow_work += 15 * placed.size()
	var near := 0
	for i in range(placed.size()):
		var e: Dictionary = placed[i]
		var cd: float = pos.distance_to(e.pos)
		if cd - mi.info.r_out - e.mi.info.r_out > env_px:
			return false
		var d: float = meas.model_to_model_distance_px(probe, _placed_model(e, i))
		if d > env_px:
			return false
		if d <= coh_px and (not near_bg_only or not bool(e.mi.is_char)):
			near += 1
	return near >= need

static func _frontier_cells(ctx: Dictionary, frontiers: Dictionary, placed: Array, mi: Dictionary,
		poly: PackedVector2Array, reach_bg_only: bool = false) -> Array:
	"""Growth candidate cells for model mi: lattice cells within 2" reach of a
	placed model (reach_bg_only: of a placed BODYGUARD model), not inside any
	placed model's inner circle (r_in + r_in - 1 px), inside the zone polygon;
	unordered (the caller sorts them with a total order). Kept incrementally
	for one growth attempt: each placed model's reach and clash discs are
	stamped ONCE per model shape (and reach_bg_only). This returns exactly the
	cells the earlier full re-scan of the blob's box against every placed model
	did (verified step by step, 2,890 growth steps), at a tenth of the cost —
	that scan was ~80% of a growth seed's time. Work: 1 per disc cell stamped,
	1 per cell returned."""
	var key := "%s|%s" % [str(mi.info.skey), "B" if reach_bg_only else "A"]
	var fr: Dictionary = frontiers.get(key, {})
	if fr.is_empty():
		fr = {"n": 0, "reach": {}, "clash": {}, "cand": {}}
		frontiers[key] = fr
	if not frontiers.has("_in_poly"):
		frontiers["_in_poly"] = {}
	var in_poly: Dictionary = frontiers["_in_poly"]
	var reach_extra: float = GameConstants.coherency_distance_inches() * PX_PER_INCH + mi.info.r_out
	var reach: Dictionary = fr.reach
	var clash: Dictionary = fr.clash
	var cand: Dictionary = fr.cand
	var visited := 0
	for idx in range(int(fr.n), placed.size()):
		var e: Dictionary = placed[idx]
		var p: Vector2 = e.pos
		# Clash disc first (strict <), then the reach disc (<=), as _cells_near.
		var rc: float = mi.info.r_in + e.mi.info.r_in - 1.0
		if rc > 0.0:
			for iy in range(int(floor((p.y - rc) / GROW_STEP_PX)), int(ceil((p.y + rc) / GROW_STEP_PX)) + 1):
				for ix in range(int(floor((p.x - rc) / GROW_STEP_PX)), int(ceil((p.x + rc) / GROW_STEP_PX)) + 1):
					visited += 1
					var c := Vector2(ix * GROW_STEP_PX, iy * GROW_STEP_PX)
					if c.distance_to(p) < rc:
						var kc := Vector2i(ix, iy)
						clash[kc] = true
						cand.erase(kc)
		if reach_bg_only and bool(e.mi.is_char):
			continue
		var rr: float = e.mi.info.r_out + reach_extra
		for iy in range(int(floor((p.y - rr) / GROW_STEP_PX)), int(ceil((p.y + rr) / GROW_STEP_PX)) + 1):
			for ix in range(int(floor((p.x - rr) / GROW_STEP_PX)), int(ceil((p.x + rr) / GROW_STEP_PX)) + 1):
				visited += 1
				var kr := Vector2i(ix, iy)
				if reach.has(kr):
					continue
				var c := Vector2(ix * GROW_STEP_PX, iy * GROW_STEP_PX)
				if c.distance_to(p) > rr:
					continue
				reach[kr] = true
				if clash.has(kr):
					continue
				if not in_poly.has(kr):
					in_poly[kr] = Geometry2D.is_point_in_polygon(c, poly)
				if in_poly[kr]:
					cand[kr] = c
	fr.n = placed.size()
	ctx.grow_work += visited + cand.size()
	return cand.values()

static func _centroid(placed: Array) -> Vector2:
	var c := Vector2.ZERO
	for e in placed:
		c += e.pos
	return c / float(placed.size())

# =============================================================================
# placement_errors (exact replica of DeploymentPhase + reverse overlap + merged coherency)
# =============================================================================

static func _placement_errors_ctx(ctx: Dictionary, positions: Array, rotations: Array, ccd: Dictionary) -> Array:
	var errs: Array = []
	var unit: Dictionary = ctx.unit
	var models: Array = unit.get("models", [])
	var opts: Dictionary = ctx.opts
	if opts.get("check_unit_level", true):
		var st := int(unit.get("status", STATUS_UNDEPLOYED))
		if st != STATUS_UNDEPLOYED and st != STATUS_DEPLOYING:
			errs.append("Unit is not available for deployment: %s" % ctx.unit_id)
		if int(unit.get("owner", 0)) != int(ctx.player):
			errs.append("Unit does not belong to active player")
		if int(ctx.edition) >= 11:
			for kw in unit.get("meta", {}).get("keywords", []):
				if str(kw).to_upper() == "AIRCRAFT":
					errs.append("AIRCRAFT must start in Strategic Reserves (23.01) — place it in reserves instead of on the battlefield")
					break
	# RC7: every alive model needs a position.
	for i in range(models.size()):
		if models[i] is Dictionary and models[i].get("alive", true) and (i >= positions.size() or positions[i] == null):
			errs.append("Every alive model must be given a position (model %d has none)" % i)
	# Per model: every NON-NULL position is validated, as the phase does (a
	# position given for a dead model is checked too, and it joins the overlap
	# and coherency sets exactly as in DeploymentPhase).
	var by_idx := {}
	for e in range(ctx.n_bg):
		by_idx[ctx.mlist[e].idx] = ctx.mlist[e]
	var placed: Array = []    # [{mi, pos, rot}] for overlap / coherency
	for i in range(positions.size()):
		if positions[i] == null:
			continue
		if i >= models.size():
			errs.append("Model index out of range")
			continue
		var mi: Dictionary = by_idx.get(i, {})
		if mi.is_empty():
			mi = _model_entry(ctx, models[i], ctx.unit_id, i, ctx.bg_kws, ctx.bg_skip, ctx.bg_infil, false)
		var pos := _vec(positions[i])
		var rot := float(rotations[i]) if i < rotations.size() and rotations[i] != null else 0.0
		_check_model(ctx, mi, pos, rot, errs)
		placed.append({"mi": mi, "pos": pos, "rot": rot})
	# Intra-unit overlap (the phase checks i<j; both directions here).
	for a in range(placed.size()):
		for b in range(a + 1, placed.size()):
			var pa: Dictionary = placed[a]
			var pb: Dictionary = placed[b]
			if pa.mi.info.shape.overlaps_with(pb.mi.info.shape, pa.pos, pa.rot, pb.pos, pb.rot) \
					or pb.mi.info.shape.overlaps_with(pa.mi.info.shape, pb.pos, pb.rot, pa.pos, pa.rot):
				errs.append("Models %s and %s overlap each other" % [str(pa.mi.m.get("id", pa.mi.idx)), str(pb.mi.m.get("id", pb.mi.idx))])
	var bg_models: Array = []
	for p in placed:
		var m: Dictionary = p.mi.m.duplicate()
		m["position"] = p.pos
		m["rotation"] = p.rot
		m["alive"] = true
		bg_models.append(m)
	if bg_models.size() > 1 and not AttackSequence.check_unit_coherency({"models": bg_models}).get("coherent", true):
		errs.append("Unit coherency broken: every model must be within 2\" of at least one other model AND within 9\" of every other model in the unit.")
	if not ccd.is_empty():
		errs.append_array(_char_errors(ctx, placed, bg_models, ccd))
	return errs

static func _char_errors(ctx: Dictionary, placed_bg: Array, bg_models: Array, ccd: Dictionary) -> Array:
	"""Mirror of DeploymentPhase._validate_combined_char_data (+ reverse overlap
	against existing models for mixed shapes)."""
	var errs: Array = []
	var units: Dictionary = ctx.snapshot.get("units", {})
	var attached: Array = ctx.unit.get("attachment_data", {}).get("attached_characters", []) if ctx.unit.get("attachment_data", {}) is Dictionary else []
	var placed: Array = placed_bg.duplicate()
	var merged: Array = bg_models.duplicate()
	for cid in ccd:
		var c := str(cid)
		if not (c in attached):
			errs.append("Character %s is not attached to %s" % [c, ctx.unit_id])
			continue
		var cu: Dictionary = units.get(c, {})
		if cu.is_empty() or int(cu.get("status", STATUS_UNDEPLOYED)) != STATUS_UNDEPLOYED:
			errs.append("Character %s is not undeployed" % c)
			continue
		var entries = ccd[cid]
		var seen := {}
		for entry in entries:
			var idx := int(entry.get("model_idx", -1))
			var cmodels: Array = cu.get("models", [])
			if idx < 0 or idx >= cmodels.size():
				errs.append("Character %s model index %d out of range" % [c, idx])
				continue
			if seen.has(idx):
				errs.append("Character %s model %d is listed twice" % [c, idx])
				continue
			seen[idx] = true
			var mi := {}
			for e in ctx.mlist:
				if e.unit_id == c and e.idx == idx:
					mi = e
					break
			if mi.is_empty():
				# Dead model or a character the builder did not expect.
				errs.append("Character %s model %d is not an alive model of an undeployed attached character" % [c, idx])
				continue
			var pos := Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)))
			var rot := float(entry.get("rotation", 0.0)) if entry.get("rotation", null) != null else 0.0
			var merrs: Array = []
			_check_model(ctx, mi, pos, rot, merrs)
			for me in merrs:
				errs.append("Character %s model %d: %s" % [c, idx, me])
			for p in placed:
				if mi.info.shape.overlaps_with(p.mi.info.shape, pos, rot, p.pos, p.rot) \
						or p.mi.info.shape.overlaps_with(mi.info.shape, p.pos, p.rot, pos, rot):
					errs.append("Character %s model %d overlaps a model of its attached unit" % [c, idx])
					break
			placed.append({"mi": mi, "pos": pos, "rot": rot})
			var cm: Dictionary = mi.m.duplicate()
			cm["position"] = pos
			cm["rotation"] = rot
			cm["alive"] = true
			merged.append(cm)
		for ci in range(cu.get("models", []).size()):
			var cmod = cu.models[ci]
			if cmod is Dictionary and cmod.get("alive", true) and not seen.has(ci):
				errs.append("Character %s model %d has no position" % [c, ci])
	if merged.size() > 1 and not AttackSequence.check_unit_coherency({"models": merged}).get("coherent", true):
		errs.append("Attached unit coherency broken (19.01 + 03.03): the bodyguard and its characters must be in coherency as one unit")
	return errs

# =============================================================================
# Logging and stats
# =============================================================================

static func _defect(msg: String) -> void:
	push_error("[FORMATION] DEFECT: %s" % msg)
	print("FormationBuilder: [FORMATION] DEFECT: %s" % msg)
	var dl = _autoload("DebugLogger")
	if dl != null and dl.has_method("error"):
		dl.error("[FORMATION] DEFECT: %s" % msg, {})

static func _record_stats(unit_id: String, out: Dictionary, probe: bool = false) -> void:
	if _stats.is_empty():
		reset_stats()
	var us := int(out.get("us", 0))
	_stats.total_us += us
	_stats.evals += int(out.get("evals", 0))
	_stats.fresh += int(out.get("fresh", 0))
	_stats.grow_work += int(out.get("grow_work", 0))
	_stats.gate_rejections += int(out.get("gate_rejections", 0))
	if str(out.get("reason", "")).begins_with("refused"):
		_stats.gate_aborts += 1
	if probe:
		_stats.probes += 1
		if out.get("ok", false):
			_stats.probe_ok += 1
		else:
			_stats.probe_fail += 1
	else:
		_stats.builds += 1
		if out.get("ok", false):
			_stats.ok += 1
			if out.get("grown", false):
				_stats.grown += 1
		else:
			_stats.no_legal += 1
	if us > int(_stats.max_us):
		_stats.max_us = us
		_stats.max_unit = unit_id
