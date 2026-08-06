extends Node2D
class_name VisionMapOverlay

# VisionMapOverlay — whole-board visibility shading for ONE chosen unit.
#
# The existing LoS debug tools answer "can A see B?" for two units that are
# already on the table. During deployment the player's real question is the
# inverse: "if I put a model HERE, is it seen?" — which needs the whole board
# classified, not a line between two tokens. This overlay grid-samples the
# board (CELL_INCHES resolution) and shades every cell the chosen unit can see,
# ignoring weapon range entirely, so hideable real estate is readable at a
# glance in any phase. One unit at a time by design: overlapping several units'
# vision fields is unreadable (the user report asking for this said exactly
# that), so the selector (VisionMapPanel) applies it unit-by-unit.
#
# ── Semantics ──────────────────────────────────────────────────────────────
# Per sight line this mirrors EnhancedLineOfSight._check_single_line_of_sight_11e
# — the SAME per-line judge the eligibility path uses (via RulesEngine.
# _check_line_of_sight → check_enhanced_visibility) — with the piece list,
# bboxes and exclusion sets precomputed so a few thousand cells are affordable:
#   ▪ 13.10 Obscuring: light/dense terrain AREAS block unless the observer or
#     the probed point is within that area group;
#   ▪ 13.11 Solid: dense FEATURES block ground-level lines except the piece a
#     model occupies;
#   ▪ explicit wall segments block when no polygon already did.
# run_self_check() re-judges sampled cells straight through the canonical
# EnhancedLineOfSight function to prove the mirror never drifts — the L-overlay
# taught us (2026-08) that a debug view with its own private LoS logic WILL
# eventually contradict the rules engine.
#
# ── Approximations (documented, deliberate) ────────────────────────────────
#   ▪ The probed point is a point target at ground level, not a based model:
#     verdicts are exact for the cell CENTRE; a real model's base edge can peek
#     around a corner from within a "hidden" cell. Precision = cell size.
#   ▪ Observer rays: base centre + OBSERVER_EDGE_RAYS points on the base rim
#     (all base shapes approximated by their base_mm circle, matching
#     TerrainManager._sight_points). The rules' full base-to-base sampling can
#     rarely find a line these rays miss — sub-cell effect at shadow edges.
#   ▪ 13.09 HIDDEN is a property of a real target unit's recent actions, not of
#     a board position, so it is intentionally NOT part of this map.

signal vision_map_updated

const CELL_UNKNOWN := 0
const CELL_VISIBLE := 1
const CELL_HIDDEN := 2

# 1" cells: 2640 cells on a 44"x60" board — fills in about a second, and
# matches the precision a deployment decision actually needs.
const CELL_INCHES := 1.0
# Per-frame compute budget (ms). Keeps the UI at full framerate while the map
# fills in progressively.
const FRAME_BUDGET_MS := 6.0
# Observer rays per model beyond the centre ray (points on the base rim).
const OBSERVER_EDGE_RAYS := 8
# Re-check the world signature at this interval while active, so the map tracks
# deployments/moves/casualties without recomputing every frame.
const REFRESH_POLL_SEC := 0.5

# Visible = warm "you are exposed here" wash; hidden = cool "safe shadow".
# Both translucent enough that terrain, zones and tokens stay readable. The
# hidden blue is picked for how it COMPOSITES, not how it looks as a swatch
# (2026-08-06 windowed runs): at 0.38 alpha a dark navy multiplies into the
# khaki board as a neutral dark grey — the "hidden" read disappeared outside
# the pale-blue deployment-zone tint. A high blue channel keeps the composite
# unmistakably blue over khaki ground, terrain fills AND the zone tints.
const COLOR_VISIBLE := Color(1.0, 0.42, 0.16, 0.32)
const COLOR_HIDDEN := Color(0.05, 0.12, 0.55, 0.40)
const SOURCE_RING_COLOR := Color(1.0, 0.85, 0.2, 0.95)

var source_unit_id: String = ""

# ── grid state ──
var _cols: int = 0
var _rows: int = 0
var _cell_px: float = 40.0
var _board_px: Vector2 = Vector2.ZERO
var _cells: PackedByteArray = PackedByteArray()
var _pending_idx: int = 0
var _image: Image = null
var _texture: ImageTexture = null

# ── precomputed world data ──
# Terrain pieces: {id, polygon, bbox, cat, pclass, group_key, legacy walls[]}
var _pieces: Array = []
var _walls: Array = []  # {a: Vector2, b: Vector2, bbox: Rect2}
var _group_map: Dictionary = {}
var _raw_features: Array = []
# Observer models: {model, pos, ground, groups, feats, ruins (pre-11e), points: Array[Vector2]}
var _observers: Array = []
# Flattened try-order: centre rays of every model first (cheap early-exit for
# open ground), then the rim rays. Entries are [point: Vector2, observer_idx].
var _obs_points: Array = []

var _poll_accum: float = 0.0
var _world_sig: int = 0
var _compute_done: bool = false
var _no_models_reason: String = ""

func _ready() -> void:
	name = "VisionMapOverlay"
	z_index = -3  # above board(-10)/terrain(-8)/zones(-5), below tokens(10)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)
	var tm = get_node_or_null("/root/TerrainManager")
	if tm and tm.has_signal("terrain_loaded"):
		tm.terrain_loaded.connect(func(_features): if is_active(): _restart_compute())
	print("[VisionMapOverlay] Initialized")

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
	_cells = PackedByteArray()
	_observers.clear()
	_obs_points.clear()
	_image = null
	_texture = null
	_compute_done = false
	_no_models_reason = ""
	set_process(false)
	queue_redraw()
	emit_signal("vision_map_updated")
	print("[VisionMapOverlay] Vision map cleared")

func is_active() -> bool:
	return source_unit_id != ""

func is_compute_done() -> bool:
	return _compute_done

func compute_progress() -> float:
	if _cells.is_empty():
		return 0.0
	return float(_pending_idx) / float(_cells.size())

## "" when the map is drawable; otherwise why it is not (e.g. the chosen unit
## has nothing on the board yet — legal to select during deployment, the map
## auto-fills the moment its first model is placed).
func status_reason() -> String:
	return _no_models_reason

func visible_cell_count() -> int:
	return _count_state(CELL_VISIBLE)

func hidden_cell_count() -> int:
	return _count_state(CELL_HIDDEN)

func _count_state(state: int) -> int:
	var n := 0
	for c in _cells:
		if c == state:
			n += 1
	return n

## Cell verdict at a board position (CELL_* constants; CELL_UNKNOWN when the
## map is off, still computing that cell, or pos is off-board).
func cell_state_at(pos: Vector2) -> int:
	if _cells.is_empty() or _cell_px <= 0.0:
		return CELL_UNKNOWN
	var cx := int(pos.x / _cell_px)
	var cy := int(pos.y / _cell_px)
	if cx < 0 or cy < 0 or cx >= _cols or cy >= _rows:
		return CELL_UNKNOWN
	return _cells[cy * _cols + cx]

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
	if not _compute_done and not _cells.is_empty():
		_compute_chunk()

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
	_pending_idx = 0
	_no_models_reason = ""

	var board_size: Dictionary = GameState.state.get("board", {}).get("size", {"width": 44, "height": 60})
	_board_px = Vector2(
		float(board_size.get("width", 44)) * Measurement.PX_PER_INCH,
		float(board_size.get("height", 60)) * Measurement.PX_PER_INCH)
	_cell_px = CELL_INCHES * Measurement.PX_PER_INCH
	_cols = int(ceil(_board_px.x / _cell_px))
	_rows = int(ceil(_board_px.y / _cell_px))

	_prepare_terrain()
	_prepare_observers()

	_cells = PackedByteArray()
	_cells.resize(_cols * _rows)
	_image = Image.create(_cols, _rows, false, Image.FORMAT_RGBA8)
	_image.fill(Color(0, 0, 0, 0))
	_texture = ImageTexture.create_from_image(_image)

	var unit: Dictionary = GameState.state.get("units", {}).get(source_unit_id, {})
	if unit.is_empty():
		_no_models_reason = "Unit not found"
		_compute_done = true
	elif _observers.is_empty():
		_no_models_reason = "No models on the board yet"
		_compute_done = true
	queue_redraw()
	emit_signal("vision_map_updated")

func _prepare_terrain() -> void:
	_pieces.clear()
	_walls.clear()
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
			_pieces.append({
				"id": pid,
				"polygon": poly,
				"bbox": Rect2(bb_min, bb_max - bb_min),
				"cat": TerrainManager.category_of(piece),
				"pclass": str(piece.get("piece_class", "")),
				"group_key": _group_map.get(pid, "id:" + pid),
			})
		# Legacy/custom wall segments (11e layouts author walls as feature
		# pieces, so these arrays are normally empty).
		for wall in piece.get("walls", []):
			if not wall.get("blocks_los", true):
				continue
			var a: Vector2 = TerrainManager._wall_point_to_vec2(wall.get("start", Vector2.ZERO))
			var b: Vector2 = TerrainManager._wall_point_to_vec2(wall.get("end", Vector2.ZERO))
			var w_min := a.min(b)
			_walls.append({"a": a, "b": b, "bbox": Rect2(w_min, a.max(b) - w_min)})

func _prepare_observers() -> void:
	_observers.clear()
	_obs_points.clear()
	var unit: Dictionary = GameState.state.get("units", {}).get(source_unit_id, {})
	var board_stub := {"terrain_features": _raw_features}
	for m in unit.get("models", []):
		if typeof(m) != TYPE_DICTIONARY or not m.get("alive", true):
			continue
		var pos := _model_pos(m)
		if pos == Vector2.ZERO:
			continue
		var radius: float = Measurement.base_radius_px(int(m.get("base_mm", 32)))
		var points: Array = [pos]
		for i in range(OBSERVER_EDGE_RAYS):
			var ang := TAU * float(i) / float(OBSERVER_EDGE_RAYS)
			points.append(pos + Vector2(cos(ang), sin(ang)) * radius)
		var ctx := {
			"model": m,
			"pos": pos,
			"ground": float(m.get("elevation_inches", 0.0)) < 3.0,
			"groups": {},
			"feats": {},
			"ruins": [],
			"points": points,
		}
		if GameConstants.edition >= 11:
			# Same "within"/"occupies" split visibility_exclusions_for applies:
			# any base overlap excuses the piece's obscuring GROUP; only centre-
			# inside excuses a Solid feature (13.10/13.11 via 01.04).
			for piece in _pieces:
				if not _circle_overlaps_bbox(pos, radius, piece.bbox):
					continue
				var center_in: bool = Geometry2D.is_point_in_polygon(pos, piece.polygon)
				if center_in or TerrainManager._circle_overlaps_polygon(pos, radius, piece.polygon):
					ctx.groups[piece.group_key] = true
					if center_in:
						ctx.feats[piece.id] = true
		else:
			ctx.ruins = EnhancedLineOfSight._get_ruins_model_wholly_within(points, pos, m, board_stub)
		_observers.append(ctx)
	# Try-order: every model's centre ray first, then the rim rays — open
	# ground resolves on the first probe, and only genuinely contested cells
	# pay for the full fan.
	for oi in range(_observers.size()):
		_obs_points.append([_observers[oi].points[0], oi])
	for oi in range(_observers.size()):
		var pts: Array = _observers[oi].points
		for pi in range(1, pts.size()):
			_obs_points.append([pts[pi], oi])

static func _circle_overlaps_bbox(center: Vector2, radius: float, bbox: Rect2) -> bool:
	return bbox.grow(radius).has_point(center)

# ═══════════════════════════════ chunked compute ═══════════════════════════

func _compute_chunk() -> void:
	var deadline := Time.get_ticks_usec() + int(FRAME_BUDGET_MS * 1000.0)
	var total := _cells.size()
	while _pending_idx < total and Time.get_ticks_usec() < deadline:
		_compute_cell(_pending_idx)
		_pending_idx += 1
	_texture.update(_image)
	queue_redraw()
	if _pending_idx >= total:
		_compute_done = true
		emit_signal("vision_map_updated")
		print("[VisionMapOverlay] Map complete for %s: %d visible / %d hidden cells" % [
			source_unit_id, visible_cell_count(), hidden_cell_count()])

func _compute_cell(idx: int) -> void:
	var cx := idx % _cols
	var cy := int(float(idx) / float(_cols))
	var target := Vector2((float(cx) + 0.5) * _cell_px, (float(cy) + 0.5) * _cell_px)

	var state := CELL_HIDDEN
	if GameConstants.edition >= 11:
		# Target-side exclusions: the areas/pieces the probed point sits in
		# (a point target is "within" and "occupies" the same set). bbox grown
		# a hair so the precheck can never exclude an exact-boundary point the
		# polygon test would accept.
		var cell_groups := {}
		var cell_feats := {}
		for piece in _pieces:
			if piece.bbox.grow(0.01).has_point(target) and Geometry2D.is_point_in_polygon(target, piece.polygon):
				cell_groups[piece.group_key] = true
				cell_feats[piece.id] = true
		for op in _obs_points:
			var obs: Dictionary = _observers[op[1]]
			if not _line_blocked_11e_fast(op[0], target, obs.groups, cell_groups, obs.feats, cell_feats, obs.ground):
				state = CELL_VISIBLE
				break
	else:
		# Pre-11e fallback: judge each ray with the canonical 10e per-line
		# function directly (no fast mirror — this path is not hot for us).
		var board_stub := {"terrain_features": _raw_features}
		var fake_target := {"position": {"x": target.x, "y": target.y}, "base_mm": 32, "alive": true}
		for op in _obs_points:
			var obs: Dictionary = _observers[op[1]]
			var res: Dictionary = EnhancedLineOfSight._check_single_line_of_sight(
				op[0], target, board_stub, obs.model, fake_target, obs.ruins, {}, false)
			if res.has_los:
				state = CELL_VISIBLE
				break

	_cells[idx] = state
	_image.set_pixel(cx, cy, COLOR_VISIBLE if state == CELL_VISIBLE else COLOR_HIDDEN)

# Fast mirror of EnhancedLineOfSight._check_single_line_of_sight_11e for a
# point target: identical branch structure over precomputed piece data, plus a
# bbox reject. run_self_check() holds it to the canonical function — change one
# without the other and the self-check fails.
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
	# Wall segments only matter when no polygon already blocked (mirrors the
	# canonical ordering; the answer is the same either way for a bool).
	for wall in _walls:
		if not seg_bbox.intersects(wall.bbox, true):
			continue
		if Geometry2D.segment_intersects_segment(a, b, wall.a, wall.b) != null:
			return true
	return false

# _segment_intersects_polygon semantics (edges OR either endpoint inside),
# minus the coercion — polygons were packed once in _prepare_terrain.
static func _segment_hits_polygon(a: Vector2, b: Vector2, poly: PackedVector2Array) -> bool:
	var n := poly.size()
	for i in range(n):
		if Geometry2D.segment_intersects_segment(a, b, poly[i], poly[(i + 1) % n]) != null:
			return true
	if Geometry2D.is_point_in_polygon(a, poly):
		return true
	return Geometry2D.is_point_in_polygon(b, poly)

# ═══════════════════════════════ self check ═══════════════════════════════

## Re-judge `samples` random computed cells straight through the CANONICAL
## per-line function (EnhancedLineOfSight._check_single_line_of_sight_11e) with
## the same exclusion contexts, and count disagreements with the stored grid.
## 0 mismatches proves the fast mirror + chunked bookkeeping preserve rules
## semantics on this exact board. Scenario- and test-callable.
func run_self_check(samples: int = 100, seed_value: int = 1337) -> Dictionary:
	var out := {"checked": 0, "mismatches": 0, "examples": []}
	if _cells.is_empty() or _observers.is_empty():
		return out
	if GameConstants.edition < 11:
		# The pre-11e path already computes through the canonical function.
		out["note"] = "edition<11 computes via canonical path; nothing to cross-check"
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for s in range(samples):
		var idx := rng.randi_range(0, _cells.size() - 1)
		if _cells[idx] == CELL_UNKNOWN:
			continue
		var cx := idx % _cols
		var cy := int(float(idx) / float(_cols))
		var target := Vector2((float(cx) + 0.5) * _cell_px, (float(cy) + 0.5) * _cell_px)
		var cell_groups := {}
		var cell_feats := {}
		for piece in _pieces:
			if piece.bbox.grow(0.01).has_point(target) and Geometry2D.is_point_in_polygon(target, piece.polygon):
				cell_groups[piece.group_key] = true
				cell_feats[piece.id] = true
		var canonical_visible := false
		for op in _obs_points:
			var obs: Dictionary = _observers[op[1]]
			var e11 := {
				"group_map": _group_map,
				"exclude_groups": _merged(obs.groups, cell_groups),
				"exclude_feature_ids": _merged(obs.feats, cell_feats),
				"ground_level": obs.ground,
			}
			var res: Dictionary = EnhancedLineOfSight._check_single_line_of_sight_11e(op[0], target, _raw_features, e11)
			if res.has_los:
				canonical_visible = true
				break
		var stored_visible: bool = _cells[idx] == CELL_VISIBLE
		out.checked += 1
		if canonical_visible != stored_visible:
			out.mismatches += 1
			if out.examples.size() < 5:
				out.examples.append({"cell": Vector2i(cx, cy), "stored": _cells[idx], "canonical_visible": canonical_visible})
	return out

static func _merged(a: Dictionary, b: Dictionary) -> Dictionary:
	var m := a.duplicate()
	m.merge(b)
	return m

# ═══════════════════════════════ drawing ═══════════════════════════════

func _draw() -> void:
	if not is_active():
		return
	if _texture != null and _no_models_reason == "":
		draw_texture_rect(_texture, Rect2(Vector2.ZERO, _board_px), false)
	# Gold rings mark WHOSE vision is being shaded.
	for obs in _observers:
		var radius: float = Measurement.base_radius_px(int(obs.model.get("base_mm", 32)))
		draw_arc(obs.pos, radius + 6.0, 0, TAU, 48, SOURCE_RING_COLOR, 3.0, true)
		draw_arc(obs.pos, radius + 10.0, 0, TAU, 48, Color(SOURCE_RING_COLOR.r, SOURCE_RING_COLOR.g, SOURCE_RING_COLOR.b, 0.35), 1.5, true)
