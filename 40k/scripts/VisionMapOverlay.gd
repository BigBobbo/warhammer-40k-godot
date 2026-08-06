extends Node2D
class_name VisionMapOverlay

# VisionMapOverlay — whole-board visibility shading for ONE chosen unit,
# rendered as TRUE RAY-CAST GEOMETRY (v2).
#
# v1 classified a 1" grid of cells, which read as blocky stair-steps (user
# report 2026-08-06: "very blocky — can't you project, almost ray casting,
# from the models?"). v2 does exactly that: from every observer point it runs
# an angular visibility sweep — one ray AT every terrain vertex (±ε twin rays,
# the classic trick that makes corners crisp) plus a sparse uniform fill — and
# computes the exact blocked/visible intervals along each ray. Adjacent rays
# are stitched into triangle fans, so shadow boundaries land ON the terrain
# silhouettes: between two vertex-targeted rays every visibility boundary
# follows a straight polygon edge, which the stitched quad reproduces
# EXACTLY. No cells, no steps.
#
# ── Rules semantics (unchanged from v1, and still held to canon) ───────────
# Per sight line this implements the SAME 11e judgement as
# EnhancedLineOfSight._check_single_line_of_sight_11e — the per-line judge the
# targeting engine itself uses:
#   ▪ 13.10 Obscuring: light/dense terrain AREAS block from the point the ray
#     first crosses them, EXCEPT where the target point stands within that
#     area's group (windows of visibility inside the group's own footprints —
#     you can be seen while standing in a ruin) or the observer is within it.
#   ▪ 13.11 Solid: dense FEATURES block ground-level rays the same way, with
#     the piece's own footprint as the exception, and not at all for elevated
#     observers.
#   ▪ Explicit wall segments block outright.
# Along a ray these become interval operations: a blocker contributes
# [first_crossing, ∞) minus its exclusion windows; the union over blockers,
# inverted, is the visible set. run_self_check() still re-judges sampled
# points straight through the canonical EnhancedLineOfSight function AND
# cross-checks the rendered fan geometry against the per-point judge — the
# L-overlay lesson (a debug view with private LoS logic WILL drift) applies
# to a renderer too.
#
# ── Remaining approximations (documented, deliberate) ──────────────────────
#   ▪ The probed point is a point target at ground level: a real model's base
#     edge can peek past a corner from just inside the shadow. Rays from each
#     model's base rim (small units get rim points, see _prepare_observers)
#     show this as a soft fringe where fans from one base disagree.
#   ▪ 13.09 HIDDEN is a property of a real target unit's recent actions, not
#     of a board position, so it is intentionally NOT part of this map.
#   ▪ Requires the 11e ruleset (the game always plays 11e; only the legacy
#     test harness pins 10e — the map reports itself unavailable there).

signal vision_map_updated

const STATE_UNKNOWN := 0
const STATE_VISIBLE := 1
const STATE_HIDDEN := 2

# Base hues (shared with the panel legend). The map is drawn as OPAQUE fills
# inside a CanvasGroup that is then faded as ONE layer (GROUP_ALPHA), so
# overlapping fans from different models never double-darken — the flattened
# composite matches the v1 look that was validated for legibility over the
# khaki board, terrain fills and the pale deployment-zone tints.
const COLOR_VISIBLE := Color(1.0, 0.42, 0.16, 0.32)
const COLOR_HIDDEN := Color(0.05, 0.12, 0.55, 0.40)
const GROUP_ALPHA := 0.36
const SOURCE_RING_COLOR := Color(1.0, 0.85, 0.2, 0.95)

# Twin-ray offset around each vertex angle: at 3000px range this is ~0.6px of
# arc — the sliver between the twins is where a corner transition lives.
const EPS_ANG := 0.0002
# Sparse uniform fill on top of the vertex-targeted rays — belt and braces
# for numeric edge cases; the vertex rays carry all the real geometry.
const UNIFORM_FILL_RAYS := 96
const EPS_T := 0.05
# Per-frame compute budget (ms) while filling in progressively.
const FRAME_BUDGET_MS := 6.0
const REFRESH_POLL_SEC := 0.5

var source_unit_id: String = ""

# ── precomputed world data ──
# Terrain pieces: {id, polygon, bbox, cat, pclass, group_key}
var _pieces: Array = []
var _walls: Array = []  # {a: Vector2, b: Vector2, bbox: Rect2}
var _group_map: Dictionary = {}
# group_key -> Array of {polygon, bbox} (every footprint of that area group)
var _group_polys: Dictionary = {}
var _raw_features: Array = []
var _board_px: Vector2 = Vector2.ZERO
# Observer points: {model, pos, ground, groups, feats}
var _observers: Array = []

# ── sweep state ──
# Per observer: {obs, blockers, angles: PackedFloat64Array, intervals: Array,
#                next_ray: int, tris: PackedVector2Array,
#                gap_ranges: PackedInt32Array (per-gap start index into tris,
#                length n+1 — the fan is queried by ANGLE, not spatially)}
var _sweeps: Array = []
var _pending_observer: int = 0
var _total_rays: int = 0
var _done_rays: int = 0
var _compute_done: bool = false
var _no_models_reason: String = ""
var _seen_ratio_cache: float = -1.0

var _poll_accum: float = 0.0
var _world_sig: int = 0

# ── render nodes ──
var _map_group: CanvasGroup = null
var _base_rect: Polygon2D = null
var _fan_meshes: Array = []

func _ready() -> void:
	name = "VisionMapOverlay"
	z_index = -3  # above board(-10)/terrain(-8)/zones(-5), below tokens(10)
	set_process(false)
	var tm = get_node_or_null("/root/TerrainManager")
	if tm and tm.has_signal("terrain_loaded"):
		tm.terrain_loaded.connect(func(_features): if is_active(): _restart_compute())
	print("[VisionMapOverlay] Initialized (ray-cast sweep renderer)")

# ═══════════════════════════════ public API ═══════════════════════════════

func show_for_unit(unit_id: String) -> void:
	source_unit_id = unit_id
	if unit_id == "":
		clear_map()
		return
	print("[VisionMapOverlay] Vision map ON for unit %s" % unit_id)
	_restart_compute()
	set_process(true)

func clear_map() -> void:
	source_unit_id = ""
	_observers.clear()
	_sweeps.clear()
	_compute_done = false
	_no_models_reason = ""
	_seen_ratio_cache = -1.0
	_clear_render_nodes()
	set_process(false)
	queue_redraw()
	emit_signal("vision_map_updated")
	print("[VisionMapOverlay] Vision map cleared")

func is_active() -> bool:
	return source_unit_id != ""

func is_compute_done() -> bool:
	return _compute_done

func compute_progress() -> float:
	if _total_rays <= 0:
		return 1.0 if _compute_done else 0.0
	return float(_done_rays) / float(_total_rays)

## "" when the map is drawable; otherwise why it is not.
func status_reason() -> String:
	return _no_models_reason

## Synchronous full compute — tests and scenario asserts use this to avoid
## racing the frame-sliced path.
func compute_now() -> void:
	if not is_active() or _no_models_reason != "":
		return
	while not _compute_done:
		_advance_sweep(1_000_000_000)

## Fraction of the board the unit can see, by seeded point sampling through
## the exact per-point judge. Cached per compute; cheap, deterministic.
func seen_ratio(samples: int = 500, seed_value: int = 1337) -> float:
	if not is_active() or _observers.is_empty():
		return 0.0
	if _seen_ratio_cache >= 0.0:
		return _seen_ratio_cache
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var seen := 0
	for i in range(samples):
		var p := Vector2(rng.randf() * _board_px.x, rng.randf() * _board_px.y)
		if point_state_at(p) == STATE_VISIBLE:
			seen += 1
	_seen_ratio_cache = float(seen) / float(samples)
	return _seen_ratio_cache

# ═════════════════════════ exact per-point judge ═══════════════════════════
# The same segment judgement v1 used (mirrors the canonical
# _check_single_line_of_sight_11e branch for branch) — the sweep RENDERS the
# map, this ANSWERS point queries and anchors the self-checks.

func point_state_at(pos: Vector2) -> int:
	if not is_active() or _observers.is_empty() or _no_models_reason != "":
		return STATE_UNKNOWN
	if pos.x < 0.0 or pos.y < 0.0 or pos.x > _board_px.x or pos.y > _board_px.y:
		return STATE_UNKNOWN
	var cell_groups := {}
	var cell_feats := {}
	for piece in _pieces:
		if piece.bbox.grow(0.01).has_point(pos) and Geometry2D.is_point_in_polygon(pos, piece.polygon):
			cell_groups[piece.group_key] = true
			cell_feats[piece.id] = true
	for obs in _observers:
		if not _line_blocked_11e_fast(obs.pos, pos, obs.groups, cell_groups, obs.feats, cell_feats, obs.ground):
			return STATE_VISIBLE
	return STATE_HIDDEN

# Fast mirror of EnhancedLineOfSight._check_single_line_of_sight_11e for a
# point target: identical branch structure over precomputed piece data, plus a
# bbox reject. run_self_check() holds it to the canonical function.
func _line_blocked_11e_fast(a: Vector2, b: Vector2, obs_groups: Dictionary, cell_groups: Dictionary, obs_feats: Dictionary, cell_feats: Dictionary, ground_level: bool) -> bool:
	var seg_min := a.min(b)
	var seg_bbox := Rect2(seg_min, a.max(b) - seg_min)
	for piece in _pieces:
		if not seg_bbox.intersects(piece.bbox, true):
			continue
		if not _segment_hits_polygon(a, b, piece.polygon):
			continue
		# 13.10 Obscuring — terrain areas (authored boundaries + legacy pieces).
		if piece.pclass != "feature":
			if (piece.cat == TerrainManager.CATEGORY_LIGHT or piece.cat == TerrainManager.CATEGORY_DENSE) \
					and not obs_groups.has(piece.group_key) and not cell_groups.has(piece.group_key):
				return true
		# 13.11 Solid — dense physical structures (features + legacy pieces).
		if piece.pclass != "area":
			if piece.cat == TerrainManager.CATEGORY_DENSE and ground_level \
					and not obs_feats.has(piece.id) and not cell_feats.has(piece.id):
				return true
	for wall in _walls:
		if not seg_bbox.intersects(wall.bbox, true):
			continue
		if Geometry2D.segment_intersects_segment(a, b, wall.a, wall.b) != null:
			return true
	return false

static func _segment_hits_polygon(a: Vector2, b: Vector2, poly: PackedVector2Array) -> bool:
	var n := poly.size()
	for i in range(n):
		if Geometry2D.segment_intersects_segment(a, b, poly[i], poly[(i + 1) % n]) != null:
			return true
	if Geometry2D.is_point_in_polygon(a, poly):
		return true
	return Geometry2D.is_point_in_polygon(b, poly)

# ═════════════════════════════ world signature ═════════════════════════════

func _process(delta: float) -> void:
	if not is_active():
		set_process(false)
		return
	_poll_accum += delta
	if _poll_accum >= REFRESH_POLL_SEC:
		_poll_accum = 0.0
		var sig := _world_signature()
		if sig != _world_sig:
			_restart_compute()
			return
	if not _compute_done and _no_models_reason == "":
		_advance_sweep(int(FRAME_BUDGET_MS * 1000.0))

func _world_signature() -> int:
	var parts: Array = [source_unit_id, GameConstants.edition]
	var tm = get_node_or_null("/root/TerrainManager")
	if tm:
		parts.append(tm.terrain_features.size())
		parts.append(tm.current_layout)
	var unit: Dictionary = GameState.state.get("units", {}).get(source_unit_id, {})
	for m in unit.get("models", []):
		if typeof(m) != TYPE_DICTIONARY:
			continue
		parts.append(bool(m.get("alive", true)))
		var p := _model_pos(m)
		parts.append(int(p.x))
		parts.append(int(p.y))
		parts.append(float(m.get("elevation_inches", 0.0)))
	return hash(parts)

static func _model_pos(model: Dictionary) -> Vector2:
	var pos = model.get("position")
	if pos is Dictionary:
		return Vector2(float(pos.get("x", 0)), float(pos.get("y", 0)))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO

# ═══════════════════════════════ compute prep ═══════════════════════════════

func _restart_compute() -> void:
	_world_sig = _world_signature()
	_compute_done = false
	_no_models_reason = ""
	_seen_ratio_cache = -1.0
	_sweeps.clear()
	_pending_observer = 0
	_total_rays = 0
	_done_rays = 0

	var board_size: Dictionary = GameState.state.get("board", {}).get("size", {"width": 44, "height": 60})
	_board_px = Vector2(
		float(board_size.get("width", 44)) * Measurement.PX_PER_INCH,
		float(board_size.get("height", 60)) * Measurement.PX_PER_INCH)

	_prepare_terrain()
	_prepare_observers()
	_rebuild_render_nodes()

	var unit: Dictionary = GameState.state.get("units", {}).get(source_unit_id, {})
	if GameConstants.edition < 11:
		_no_models_reason = "Vision Map needs the 11e ruleset"
		_compute_done = true
	elif unit.is_empty():
		_no_models_reason = "Unit not found"
		_compute_done = true
	elif _observers.is_empty():
		_no_models_reason = "No models on the board yet"
		_compute_done = true
	else:
		for obs in _observers:
			_sweeps.append(_new_sweep(obs))
		for sweep in _sweeps:
			_total_rays += sweep.angles.size()
	queue_redraw()
	emit_signal("vision_map_updated")

func _prepare_terrain() -> void:
	_pieces.clear()
	_walls.clear()
	_group_polys.clear()
	_raw_features = []
	var tm = get_node_or_null("/root/TerrainManager")
	if tm:
		_raw_features = tm.terrain_features
	_group_map = TerrainManager.build_area_group_map(_raw_features)
	for piece in _raw_features:
		var poly: PackedVector2Array = EnhancedLineOfSight._to_packed_polygon(piece.get("polygon", PackedVector2Array()))
		var pid := str(piece.get("id", ""))
		if poly.size() >= 3:
			var bb_min := poly[0]
			var bb_max := poly[0]
			for v in poly:
				bb_min = bb_min.min(v)
				bb_max = bb_max.max(v)
			var gk: String = _group_map.get(pid, "id:" + pid)
			var entry := {
				"id": pid,
				"polygon": poly,
				"bbox": Rect2(bb_min, bb_max - bb_min),
				"cat": TerrainManager.category_of(piece),
				"pclass": str(piece.get("piece_class", "")),
				"group_key": gk,
			}
			_pieces.append(entry)
			if not _group_polys.has(gk):
				_group_polys[gk] = []
			_group_polys[gk].append({"polygon": poly, "bbox": entry.bbox})
		for wall in piece.get("walls", []):
			if not wall.get("blocks_los", true):
				continue
			var a: Vector2 = TerrainManager._wall_point_to_vec2(wall.get("start", Vector2.ZERO))
			var b: Vector2 = TerrainManager._wall_point_to_vec2(wall.get("end", Vector2.ZERO))
			var w_min := a.min(b)
			_walls.append({"a": a, "b": b, "bbox": Rect2(w_min, a.max(b) - w_min)})

func _prepare_observers() -> void:
	_observers.clear()
	var unit: Dictionary = GameState.state.get("units", {}).get(source_unit_id, {})
	var models: Array = []
	for m in unit.get("models", []):
		if typeof(m) != TYPE_DICTIONARY or not m.get("alive", true):
			continue
		if _model_pos(m) == Vector2.ZERO:
			continue
		models.append(m)
	# Rim rays reveal base-edge peeking, but every extra observer point is a
	# full sweep — spend them where they matter (small elite units) and fall
	# back to centre-only for mobs, whose many bases cover each other anyway.
	var rim_points := 0
	if models.size() <= 2:
		rim_points = 8
	elif models.size() <= 5:
		rim_points = 4
	for m in models:
		var pos := _model_pos(m)
		var radius: float = Measurement.base_radius_px(int(m.get("base_mm", 32)))
		var points: Array = [pos]
		for i in range(rim_points):
			var ang := TAU * float(i) / float(rim_points)
			points.append(pos + Vector2(cos(ang), sin(ang)) * radius)
		# Exclusions are per MODEL (base overlap), applied to all its points —
		# the same "within"/"occupies" split visibility_exclusions_for uses.
		var groups := {}
		var feats := {}
		for piece in _pieces:
			if not piece.bbox.grow(radius).has_point(pos):
				continue
			var center_in: bool = Geometry2D.is_point_in_polygon(pos, piece.polygon)
			if center_in or TerrainManager._circle_overlaps_polygon(pos, radius, piece.polygon):
				groups[piece.group_key] = true
				if center_in:
					feats[piece.id] = true
		var ground := float(m.get("elevation_inches", 0.0)) < 3.0
		for p in points:
			_observers.append({"model": m, "pos": p, "ground": ground, "groups": groups, "feats": feats})

# ═══════════════════════════════ the sweep ═════════════════════════════════

func _new_sweep(obs: Dictionary) -> Dictionary:
	# Blocker entries for THIS observer. A legacy piece (no piece_class) can
	# block in BOTH roles — two entries with different exclusion sets, exactly
	# like the two branches of the canonical judge. Each entry carries its
	# angular span from the observer so a ray only pays for blockers that can
	# actually lie in its direction.
	var blockers: Array = []
	for piece in _pieces:
		if piece.pclass != "feature" \
				and (piece.cat == TerrainManager.CATEGORY_LIGHT or piece.cat == TerrainManager.CATEGORY_DENSE) \
				and not obs.groups.has(piece.group_key):
			var e := {"polygon": piece.polygon, "bbox": piece.bbox,
				"excl": _group_polys.get(piece.group_key, [])}
			_stamp_angular_span(e, obs.pos, piece.polygon)
			blockers.append(e)
		if piece.pclass != "area" \
				and piece.cat == TerrainManager.CATEGORY_DENSE and obs.ground \
				and not obs.feats.has(piece.id):
			var e2 := {"polygon": piece.polygon, "bbox": piece.bbox,
				"excl": [{"polygon": piece.polygon, "bbox": piece.bbox}]}
			_stamp_angular_span(e2, obs.pos, piece.polygon)
			blockers.append(e2)
	for wall in _walls:
		var we := {"wall": true, "a": wall.a, "b": wall.b, "bbox": wall.bbox, "excl": []}
		_stamp_angular_span(we, obs.pos, PackedVector2Array([wall.a, wall.b]))
		blockers.append(we)

	# Ray fan: every terrain vertex (±ε twins) — INCLUDING vertices of pieces
	# that do not block this observer, because excluded footprints still shape
	# the visibility windows inside other blockers' shadows — plus wall ends,
	# board corners, and a sparse uniform fill.
	var angles_raw: Array = []
	var o: Vector2 = obs.pos
	for piece in _pieces:
		for v in piece.polygon:
			var ang: float = (v - o).angle()
			angles_raw.append(ang - EPS_ANG)
			angles_raw.append(ang + EPS_ANG)
	for wall in _walls:
		for v in [wall.a, wall.b]:
			var wang: float = (v - o).angle()
			angles_raw.append(wang - EPS_ANG)
			angles_raw.append(wang + EPS_ANG)
	for corner in [Vector2.ZERO, Vector2(_board_px.x, 0), _board_px, Vector2(0, _board_px.y)]:
		angles_raw.append((corner - o).angle())
	for i in range(UNIFORM_FILL_RAYS):
		angles_raw.append(-PI + TAU * float(i) / float(UNIFORM_FILL_RAYS))
	angles_raw.sort()
	var angles := PackedFloat64Array()
	var last := INF
	for ang in angles_raw:
		if last == INF or absf(ang - last) > 0.00001:
			angles.append(ang)
			last = ang
	return {"obs": obs, "blockers": blockers, "angles": angles,
		"intervals": [], "next_ray": 0, "tris": PackedVector2Array(),
		"gap_ranges": PackedInt32Array()}

## Precompute the blocker's angular extent as seen from `o`: a reference
## direction plus min/max offsets. A ray whose offset falls outside the span
## cannot touch the blocker — the cheap reject that keeps a ray from paying
## the slab+edge tests for all ~60 blockers. A shape subtending more than a
## half-turn (possible only for something wrapped AROUND the observer) is
## marked full and never filtered.
static func _stamp_angular_span(entry: Dictionary, o: Vector2, verts: PackedVector2Array) -> void:
	if verts.is_empty():
		entry["span_full"] = true
		return
	var ref := (verts[0] - o).angle()
	var lo := 0.0
	var hi := 0.0
	for v in verts:
		var d := wrapf((v - o).angle() - ref, -PI, PI)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	if hi - lo > PI:
		entry["span_full"] = true
		return
	entry["span_full"] = false
	entry["span_ref"] = ref
	entry["span_lo"] = lo - EPS_ANG * 8.0
	entry["span_hi"] = hi + EPS_ANG * 8.0

func _advance_sweep(budget_usec: int) -> void:
	var deadline := Time.get_ticks_usec() + budget_usec
	while _pending_observer < _sweeps.size():
		var sweep: Dictionary = _sweeps[_pending_observer]
		var n: int = sweep.angles.size()
		while sweep.next_ray < n:
			sweep.intervals.append(_cast_ray(sweep, sweep.angles[sweep.next_ray]))
			sweep.next_ray += 1
			_done_rays += 1
			if Time.get_ticks_usec() >= deadline:
				return
		_finish_observer(sweep, _pending_observer)
		_pending_observer += 1
		if Time.get_ticks_usec() >= deadline:
			break
	if _pending_observer >= _sweeps.size() and not _compute_done:
		_compute_done = true
		queue_redraw()
		emit_signal("vision_map_updated")
		print("[VisionMapOverlay] Sweep complete for %s: %d observers, %d rays, ~%d%% of board in sight" % [
			source_unit_id, _sweeps.size(), _total_rays, int(seen_ratio() * 100.0)])

## Visible intervals [t0, t1] along the ray from sweep.obs.pos at angle `ang`,
## capped at the board edge. Exact interval algebra over the blocker set.
func _cast_ray(sweep: Dictionary, ang: float) -> Array:
	var o: Vector2 = sweep.obs.pos
	var dir := Vector2(cos(ang), sin(ang))
	var t_max := _board_exit_t(o, dir)
	if t_max <= 0.0:
		return []
	var seg_end := o + dir * t_max

	var blocked: Array = []  # [t0, t1] pairs, unsorted
	for blocker in sweep.blockers:
		if not blocker.span_full:
			var d := wrapf(ang - blocker.span_ref, -PI, PI)
			if d < blocker.span_lo or d > blocker.span_hi:
				continue
		if not _ray_hits_rect(o, dir, t_max, blocker.bbox):
			continue
		if blocker.has("wall"):
			var hit = Geometry2D.segment_intersects_segment(o, seg_end, blocker.a, blocker.b)
			if hit != null:
				blocked.append([maxf((hit - o).dot(dir), 0.0), t_max])
			continue
		var ts := _polygon_crossings(o, seg_end, dir, blocker.polygon)
		if ts.is_empty():
			continue
		var t_enter: float = ts[0]
		# Exclusion windows: stretches of this blocker's shadow where the
		# target point stands within the excused footprints (13.10 group /
		# 13.11 own piece) — visible islands INSIDE the shadow.
		var windows: Array = []
		for ex in blocker.excl:
			if not _ray_hits_rect(o, dir, t_max, ex.bbox):
				continue
			var ets := _polygon_crossings(o, seg_end, dir, ex.polygon)
			if ets.is_empty():
				continue
			# Pair up in/out by midpoint containment — robust against grazes.
			var bounds: Array = [0.0]
			bounds.append_array(ets)
			bounds.append(t_max)
			for i in range(bounds.size() - 1):
				var lo: float = bounds[i]
				var hi: float = bounds[i + 1]
				if hi - lo < EPS_T:
					continue
				if Geometry2D.is_point_in_polygon(o + dir * ((lo + hi) * 0.5), ex.polygon):
					windows.append([lo, hi])
		if windows.is_empty():
			blocked.append([t_enter, t_max])
		else:
			windows.sort_custom(func(x, y): return x[0] < y[0])
			var cursor := t_enter
			for w in windows:
				if w[1] <= cursor:
					continue
				if w[0] > cursor:
					blocked.append([cursor, minf(w[0], t_max)])
				cursor = maxf(cursor, w[1])
				if cursor >= t_max:
					break
			if cursor < t_max:
				blocked.append([cursor, t_max])

	if blocked.is_empty():
		return [[0.0, t_max]]
	blocked.sort_custom(func(x, y): return x[0] < y[0])
	# Merge blocked, then invert into visible.
	var visible: Array = []
	var open := 0.0
	for b in blocked:
		if b[0] - open > EPS_T:
			visible.append([open, b[0]])
		open = maxf(open, b[1])
	if t_max - open > EPS_T:
		visible.append([open, t_max])
	return visible

## Sorted distances along o→dir at which the ray crosses the polygon outline.
func _polygon_crossings(o: Vector2, seg_end: Vector2, dir: Vector2, poly: PackedVector2Array) -> Array:
	var ts: Array = []
	var n := poly.size()
	for i in range(n):
		var hit = Geometry2D.segment_intersects_segment(o, seg_end, poly[i], poly[(i + 1) % n])
		if hit != null:
			ts.append(maxf((hit - o).dot(dir), 0.0))
	ts.sort()
	# Dedupe shared-vertex double hits.
	var out: Array = []
	for t in ts:
		if out.is_empty() or t - out[out.size() - 1] > EPS_T:
			out.append(t)
	return out

func _board_exit_t(o: Vector2, dir: Vector2) -> float:
	var t := INF
	if dir.x > 0.00001:
		t = minf(t, (_board_px.x - o.x) / dir.x)
	elif dir.x < -0.00001:
		t = minf(t, -o.x / dir.x)
	if dir.y > 0.00001:
		t = minf(t, (_board_px.y - o.y) / dir.y)
	elif dir.y < -0.00001:
		t = minf(t, -o.y / dir.y)
	return maxf(t, 0.0) if t != INF else 0.0

static func _ray_hits_rect(o: Vector2, dir: Vector2, t_max: float, rect: Rect2) -> bool:
	# Classic slab test for the segment o → o+dir*t_max.
	var t0 := 0.0
	var t1 := t_max
	for axis in 2:
		var d := dir.x if axis == 0 else dir.y
		var start := o.x if axis == 0 else o.y
		var lo := rect.position.x if axis == 0 else rect.position.y
		var hi := lo + (rect.size.x if axis == 0 else rect.size.y)
		if absf(d) < 0.0000001:
			if start < lo or start > hi:
				return false
		else:
			var ta := (lo - start) / d
			var tb := (hi - start) / d
			if ta > tb:
				var tmp := ta
				ta = tb
				tb = tmp
			t0 = maxf(t0, ta)
			t1 = minf(t1, tb)
			if t0 > t1:
				return false
	return true

# ═══════════════════════ fan stitching + rendering ═════════════════════════

func _finish_observer(sweep: Dictionary, observer_idx: int) -> void:
	var o: Vector2 = sweep.obs.pos
	var angles: PackedFloat64Array = sweep.angles
	var n := angles.size()
	var tris := PackedVector2Array()
	# gap_ranges[i] = first triangle index of gap i (the wedge between ray i
	# and ray i+1, wrapping); length n+1. Point queries binary-search the
	# angle to its gap and test only that wedge's few triangles.
	var gap_ranges := PackedInt32Array()
	for i in range(n):
		gap_ranges.append(tris.size() / 3)
		var j := (i + 1) % n
		var dir_i := Vector2(cos(angles[i]), sin(angles[i]))
		var dir_j := Vector2(cos(angles[j]), sin(angles[j]))
		var list_i: Array = sweep.intervals[i]
		var list_j: Array = sweep.intervals[j]
		# Stitch every overlapping interval pair into a quad using each ray's
		# OWN endpoints: between vertex-twin rays each boundary follows one
		# straight polygon edge, so the quad reproduces it exactly. The rare
		# many-to-one overlap at a corner lives inside the ±ε sliver and the
		# extra overlapping quads collapse invisibly (flat colour, union
		# rendering).
		for a in list_i:
			for b in list_j:
				if a[0] >= b[1] - EPS_T or b[0] >= a[1] - EPS_T:
					continue
				var a0: Vector2 = o + dir_i * a[0]
				var a1: Vector2 = o + dir_i * a[1]
				var b0: Vector2 = o + dir_j * b[0]
				var b1: Vector2 = o + dir_j * b[1]
				# Skip zero-area triangles: every quad rooted at the observer
				# has a0 == b0, and point_is_inside_triangle answers TRUE for
				# any COLLINEAR point against a degenerate triangle — which
				# made sweep_point_visible hallucinate visibility along exact
				# ray bearings (all sign tests are 0). Invisible when drawn,
				# poisonous when queried.
				if absf((a1 - a0).cross(b1 - a0)) > 0.5:
					tris.append(a0); tris.append(a1); tris.append(b1)
				if absf((b1 - a0).cross(b0 - a0)) > 0.5:
					tris.append(a0); tris.append(b1); tris.append(b0)
	gap_ranges.append(tris.size() / 3)
	sweep.tris = tris
	sweep.gap_ranges = gap_ranges
	_attach_fan_mesh(observer_idx, tris)
	queue_redraw()

## Is P inside this unit's RENDERED visible geometry? (What the player sees —
## cross-checked against the per-point judge by run_self_check part B.)
## Angle-indexed: binary-search the ray pair bracketing P's bearing, then test
## only that wedge's triangles.
func sweep_point_visible(p: Vector2) -> bool:
	for sweep in _sweeps:
		var n: int = sweep.angles.size()
		if n < 2 or sweep.next_ray < n or sweep.gap_ranges.is_empty():
			continue
		var theta: float = (p - sweep.obs.pos).angle()
		var gap: int
		if theta < sweep.angles[0] or theta >= sweep.angles[n - 1]:
			gap = n - 1  # the wrap wedge between the last and first rays
		else:
			var lo := 0
			var hi := n - 1
			while hi - lo > 1:
				var mid := (lo + hi) >> 1
				if sweep.angles[mid] <= theta:
					lo = mid
				else:
					hi = mid
			gap = lo
		for t in range(sweep.gap_ranges[gap], sweep.gap_ranges[gap + 1]):
			if Geometry2D.point_is_inside_triangle(p, sweep.tris[t * 3], sweep.tris[t * 3 + 1], sweep.tris[t * 3 + 2]):
				return true
	return false

func _rebuild_render_nodes() -> void:
	_clear_render_nodes()
	_map_group = CanvasGroup.new()
	_map_group.name = "MapGroup"
	# One flattened layer: opaque hidden base + opaque visible fans, faded
	# together — overlapping fans can never double-darken.
	_map_group.self_modulate = Color(1, 1, 1, GROUP_ALPHA)
	add_child(_map_group)
	_base_rect = Polygon2D.new()
	_base_rect.name = "HiddenBase"
	_base_rect.polygon = PackedVector2Array([
		Vector2.ZERO, Vector2(_board_px.x, 0), _board_px, Vector2(0, _board_px.y)])
	_base_rect.color = Color(COLOR_HIDDEN.r, COLOR_HIDDEN.g, COLOR_HIDDEN.b, 1.0)
	_map_group.add_child(_base_rect)
	_fan_meshes.clear()

func _clear_render_nodes() -> void:
	if _map_group and is_instance_valid(_map_group):
		_map_group.queue_free()
	_map_group = null
	_base_rect = null
	_fan_meshes.clear()

func _attach_fan_mesh(observer_idx: int, tris: PackedVector2Array) -> void:
	if _map_group == null or tris.is_empty():
		return
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = tris
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance2D.new()
	mi.name = "Fan%d" % observer_idx
	mi.mesh = mesh
	mi.modulate = Color(COLOR_VISIBLE.r, COLOR_VISIBLE.g, COLOR_VISIBLE.b, 1.0)
	_map_group.add_child(mi)
	_fan_meshes.append(mi)

# ═══════════════════════════════ self check ═══════════════════════════════

## Two-part agreement audit over `samples` seeded random board points:
##   A) the per-point judge vs the CANONICAL EnhancedLineOfSight per-line
##      function with identical exclusion contexts (mismatches must be 0);
##   B) the RENDERED fan geometry vs the per-point judge — points within a
##      hair of a shadow boundary (where ±ε stitching lives) are detected by
##      offset probing and skipped; everything else must agree exactly.
func run_self_check(samples: int = 100, seed_value: int = 1337) -> Dictionary:
	var out := {"checked": 0, "mismatches": 0, "render_checked": 0, "render_mismatches": 0, "examples": []}
	if _observers.is_empty() or not _compute_done or _no_models_reason != "":
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for s in range(samples):
		var p := Vector2(rng.randf() * _board_px.x, rng.randf() * _board_px.y)
		var judge_visible := point_state_at(p) == STATE_VISIBLE

		# Part A — judge vs canonical rules engine.
		var cell_groups := {}
		var cell_feats := {}
		for piece in _pieces:
			if piece.bbox.grow(0.01).has_point(p) and Geometry2D.is_point_in_polygon(p, piece.polygon):
				cell_groups[piece.group_key] = true
				cell_feats[piece.id] = true
		var canonical_visible := false
		for obs in _observers:
			var e11 := {
				"group_map": _group_map,
				"exclude_groups": _merged(obs.groups, cell_groups),
				"exclude_feature_ids": _merged(obs.feats, cell_feats),
				"ground_level": obs.ground,
			}
			var res: Dictionary = EnhancedLineOfSight._check_single_line_of_sight_11e(obs.pos, p, _raw_features, e11)
			if res.has_los:
				canonical_visible = true
				break
		out.checked += 1
		if canonical_visible != judge_visible:
			out.mismatches += 1
			if out.examples.size() < 5:
				out.examples.append({"at": p, "kind": "judge_vs_canonical", "judge": judge_visible, "canonical": canonical_visible})

		# Part B — rendered geometry vs judge, boundary points skipped.
		var near_boundary := false
		for off in [Vector2(1.5, 0), Vector2(-1.5, 0), Vector2(0, 1.5), Vector2(0, -1.5)]:
			var q: Vector2 = p + off
			if q.x < 0 or q.y < 0 or q.x > _board_px.x or q.y > _board_px.y:
				near_boundary = true
				break
			if (point_state_at(q) == STATE_VISIBLE) != judge_visible:
				near_boundary = true
				break
		if near_boundary:
			continue
		out.render_checked += 1
		if sweep_point_visible(p) != judge_visible:
			out.render_mismatches += 1
			if out.examples.size() < 5:
				out.examples.append({"at": p, "kind": "render_vs_judge", "judge": judge_visible})
	return out

static func _merged(a: Dictionary, b: Dictionary) -> Dictionary:
	var m := a.duplicate()
	m.merge(b)
	return m

# ═══════════════════════════════ drawing ═══════════════════════════════

func _draw() -> void:
	if not is_active():
		return
	if _map_group:
		_map_group.visible = _no_models_reason == ""
	# Gold rings mark WHOSE vision is being shaded (one ring per model, not
	# per rim point).
	var ringed := {}
	for obs in _observers:
		var mid: String = str(obs.model.get("id", ""))
		if ringed.has(mid):
			continue
		ringed[mid] = true
		var center := _model_pos(obs.model)
		var radius: float = Measurement.base_radius_px(int(obs.model.get("base_mm", 32)))
		draw_arc(center, radius + 6.0, 0, TAU, 48, SOURCE_RING_COLOR, 3.0, true)
		draw_arc(center, radius + 10.0, 0, TAU, 48, Color(SOURCE_RING_COLOR.r, SOURCE_RING_COLOR.g, SOURCE_RING_COLOR.b, 0.35), 1.5, true)
