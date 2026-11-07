extends SceneTree

# TERRAIN-DATA (AI deployment plan P0, DECISIONS D8): every shipped terrain
# layout folds into terrain-area groups that are each ONE contiguous area.
#
# TerrainManager.build_area_group_map turns layout pieces into 13.01 terrain
# areas: link_group wins, else the parent_area_id chain, else the piece is its
# own area. 13.09 HIDDEN (dense if ANY piece of the group is dense) and the
# 13.10/13.11 visibility exclusions (a model ignores every obscuring piece of a
# group it is within) treat a group as one area, so a group spanning two
# separate places on the board corrupts both rules for every player.
#
# The 40kdc 1.0.19 source data (the 45 GW layouts) was authored by
# point-mirroring half a board, and the mirror copied the links:
#   * 30 features in 8 files were parented to an area 3-38" away (26 of them
#     to the point-mirror twin of the area they stand in, e.g.
#     take_and_hold_mirror_1 corner-short-9..12 -> area-medium-7/8; 4 in
#     take_and_hold_vs_reconnaissance_1 to a neighbouring area instead of the
#     home-objective ruin they stand in, which left that ruin "exposed");
#   * 26 link_group labels in 21 files were shared by a cluster and its
#     mirrored twin (6.5-45" apart), merging separate areas into one group.
# tools/check_terrain_layouts.py is the offline checker / fixer (and also
# checks each area's generator-derived category/height/traits); no CI job runs
# it, so THIS test is the CI net for its error checks. It pins the same
# invariant through the ENGINE (load_terrain_layout + build_area_group_map +
# Geometry2D) and pins the player-visible effects:
#   A. all layouts: parent within 0.5" (checker parent-far), and a feature that
#      straddles its parent (centroid outside it or < 50% inside it) does not
#      stand in an area of ANOTHER engine group -- the area holding >= 50% of
#      it, and more of it than the parent, shares the parent's group (checker
#      parent-wrong-area: touching the wrong area is not enough); each engine
#      group contiguous; each area's category = the densest feature parented
#      to it (engine category_of); and each area's category / height_inches /
#      height / traits = the generator's aggregate of its features, computed
#      from the raw layout JSON exactly as the checker's area-aggregate
#      (_area_aggregate mirrors check_terrain_layouts.area_aggregate)
#   B. take_and_hold_mirror_1: a model standing in area-medium-7 no longer
#      excludes the far corner walls / area-medium-8 (37" away). On this
#      layout the defect changed exclusion sets only: an engine sweep found no
#      model_visible_11e / is_model_hidden flip (0 of 58,080 pairs), because
#      every line between the twins also crosses other obscuring terrain.
#   C. take_and_hold_vs_reconnaissance_1: the home ruin area-large-7 hides
#      INFANTRY (13.09) and blocks a sight line it used to leak through the
#      dense area-medium-9.
#   D. reconnaissance_vs_reconnaissance_2: a model in area-medium-29 no longer
#      sees through the separate areas that shared link_group "2".
#   E. negative controls for A, applied in memory: a dense wall re-parented to
#      the light area it leans against (0.18" away; both areas re-derived, so
#      only the wrong-area rule can see it), and an area whose height / traits
#      went stale while its category stayed right -- both are caught.
# Every focused check also re-applies the pre-fix values in memory and asserts
# the defect reproduces ([pre-fix] / [mutation] lines), so the test cannot pass
# vacuously.
#
# Run with: godot --headless --path . -s tests/unit/test_terrain_layout_area_groups.gd

const LAYOUT_DIR := "res://terrain_layouts"
const PX := 40.0                  # Measurement.PX_PER_INCH
const ABUT_TOL_PX := 0.5 * PX     # "overlaps or abuts": within 0.5"
const MAJORITY := 0.5             # fraction of a feature's footprint (checker MAJORITY)
const CATEGORY_RANK := {"exposed": 0, "light": 1, "dense": 2}
const AGGREGATE_FIELDS := ["category", "height_inches", "height", "traits"]

var _pass_count := 0
var _fail_count := 0
var _ran := false
var tm = null

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func _run_tests():
	if _ran:
		return
	_ran = true
	await process_frame
	print("\n=== TERRAIN-DATA: terrain-area groups are contiguous in every shipped layout ===\n")
	tm = root.get_node_or_null("TerrainManager")
	_assert(tm != null, "TerrainManager autoload present")
	if tm == null:
		print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
		quit(1)
		return
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	var prev_layout: String = tm.current_layout
	var prev_terrain: Array = tm.terrain_features.duplicate(true)

	test_all_layouts_invariant()
	test_mirror_1_far_walls_not_excluded()
	test_recon_1_home_ruin_hides_and_obscures()
	test_recon_vs_recon_2_link_group_split()
	test_wrong_area_parent_is_caught()
	test_stale_area_aggregate_is_caught()

	tm.current_layout = prev_layout
	tm.terrain_features = prev_terrain
	GameConstants.edition = prev_edition
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

# ── geometry / invariant helpers (pixels) ───────────────────────────────

static func _poly_gap(a: PackedVector2Array, b: PackedVector2Array) -> float:
	for v in a:
		if Geometry2D.is_point_in_polygon(v, b):
			return 0.0
	for v in b:
		if Geometry2D.is_point_in_polygon(v, a):
			return 0.0
	var best := INF
	for i in range(a.size()):
		var a1: Vector2 = a[i]
		var a2: Vector2 = a[(i + 1) % a.size()]
		for j in range(b.size()):
			var b1: Vector2 = b[j]
			var b2: Vector2 = b[(j + 1) % b.size()]
			if Geometry2D.segment_intersects_segment(a1, a2, b1, b2) != null:
				return 0.0
			var cp: PackedVector2Array = Geometry2D.get_closest_points_between_segments(a1, a2, b1, b2)
			best = minf(best, cp[0].distance_to(cp[1]))
	return best

static func _by_id(features: Array) -> Dictionary:
	var out := {}
	for p in features:
		out[str(p.get("id", ""))] = p
	return out

## Connected components of `ids` under <= 0.5" adjacency (transitive).
static func _clusters(ids: Array, by_id: Dictionary) -> Array:
	var remaining: Array = ids.duplicate()
	var comps: Array = []
	while not remaining.is_empty():
		var comp: Array = [remaining.pop_front()]
		var k := 0
		while k < comp.size():
			var cur: PackedVector2Array = by_id[comp[k]].polygon
			for other in remaining.duplicate():
				if _poly_gap(cur, by_id[other].polygon) <= ABUT_TOL_PX:
					comp.append(other)
					remaining.erase(other)
			k += 1
		comps.append(comp)
	return comps

## Polygon area (shoelace, absolute).
static func _poly_area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) / 2.0

## Fraction of the feature's footprint inside the area polygon (the checker's
## overlap_fraction). The intersection of two simple polygons has no holes, so
## the pieces Geometry2D returns are summed as they are.
static func _overlap_fraction(feature: PackedVector2Array, area: PackedVector2Array) -> float:
	var fa := _poly_area(feature)
	if fa == 0.0:
		return 0.0
	var inside := 0.0
	for piece in Geometry2D.intersect_polygons(feature, area):
		inside += _poly_area(piece)
	return minf(1.0, inside / fa)

## Vertex average (the checker's centroid()).
static func _vertex_centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for v in poly:
		c += v
	return c / float(maxi(1, poly.size()))

## check_terrain_layouts parent-wrong-area, for a feature that touches its
## parent: "" when the feature passes the STRICT criterion (centroid inside the
## parent and >= 50% of it inside), or when the area holding most of it shares
## the parent's engine group, or when no area holds >= 50% of it and more of it
## than the parent. Otherwise the feature stands in an area of ANOTHER group
## and the engine folds it into the wrong 13.01 area: returns the violation.
## out_straddle (size-1 Array) counts the features that fail STRICT.
func _wrong_area(p: Dictionary, parent: Dictionary, features: Array, group_map: Dictionary, out_straddle: Array) -> String:
	var frac := _overlap_fraction(p.polygon, parent.polygon)
	var c_in := Geometry2D.is_point_in_polygon(_vertex_centroid(p.polygon), parent.polygon)
	if c_in and frac >= MAJORITY:
		return ""
	out_straddle[0] = int(out_straddle[0]) + 1
	# The majority area: most of the footprint, then the smaller gap, then the id
	# (the checker's touching_areas sort), among the areas within 0.5".
	var best_id := ""
	var best_frac := -1.0
	var best_gap := INF
	for a in features:
		if str(a.get("piece_class", "")) != "area":
			continue
		var gap := _poly_gap(p.polygon, a.polygon)
		if gap > ABUT_TOL_PX:
			continue
		var f := _overlap_fraction(p.polygon, a.polygon)
		var aid := str(a.get("id", ""))
		if f > best_frac or (f == best_frac and (gap < best_gap or (gap == best_gap and aid < best_id))):
			best_id = aid
			best_frac = f
			best_gap = gap
	if best_id == "" or group_map.get(best_id) == group_map.get(str(parent.get("id", ""))):
		return ""
	if best_frac < MAJORITY or best_frac <= frac:
		return ""
	return "%s -> %s (touches it, %.0f%% inside, centroid %s) but %.0f%% of it stands in %s, engine group %s != the parent's %s" % [
		str(p.get("id", "")), str(parent.get("id", "")), frac * 100.0, "inside" if c_in else "outside",
		best_frac * 100.0, best_id, str(group_map.get(best_id)), str(group_map.get(str(parent.get("id", ""))))]

## check_terrain_layouts.height_category / area_aggregate, line for line: the
## category / height_inches / height / traits the generator
## (scripts/40kdc/generate-terrain-layouts.mjs areaContents, pieceGameplay,
## pieceTraits, heightCategory) derives for an area from its parented features.
static func _height_category(h) -> String:
	return "low" if h < 2 else ("medium" if h <= 4 else "tall")

static func _area_aggregate(children: Array) -> Dictionary:
	var cat := "exposed"
	var max_h = 0
	for c in children:
		var cc := str(c.get("category", "exposed"))
		if int(CATEGORY_RANK.get(cc, 0)) > int(CATEGORY_RANK[cat]):
			cat = cc
		max_h = max(max_h, c.get("height_inches", 0))
	var traits: Array = []
	if cat == "dense":
		traits.append("obscuring")
	traits.append("difficult_ground")
	return {"category": cat, "height_inches": max_h, "height": _height_category(max_h), "traits": traits}

## Python `!=` semantics for JSON values: int and float compare by value, any
## other type mismatch is "different" (GDScript would raise on it), arrays
## compare element by element.
static func _same_value(a, b) -> bool:
	var num := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) in num and typeof(b) in num:
		return float(a) == float(b)
	if typeof(a) != typeof(b):
		return false
	if typeof(a) == TYPE_ARRAY:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not _same_value(a[i], b[i]):
				return false
		return true
	return a == b

## The checker's area-aggregate check over a layout's RAW JSON pieces -- the
## bytes the checker reads (the engine copies category / height_inches /
## traits onto its runtime pieces as they are, but parses `height` into
## height_category with a "tall" fallback, so the raw file is the exact
## mirror). Same piece filter (polygon of >= 3 vertices) and children (pieces
## of class "feature" with a parent_area_id) as check_layout.
static func _aggregate_violations(raw_pieces: Array) -> Array:
	var pieces: Array = []
	for p in raw_pieces:
		if p is Dictionary and p.get("polygon", []) is Array and (p.get("polygon", []) as Array).size() >= 3:
			pieces.append(p)
	var kids := {}
	for p in pieces:
		var pa = p.get("parent_area_id", null)
		if str(p.get("piece_class", "")) != "feature" or pa == null or str(pa) == "":
			continue
		if not kids.has(str(pa)):
			kids[str(pa)] = []
		kids[str(pa)].append(p)
	var bad: Array = []
	for a in pieces:
		if str(a.get("piece_class", "")) != "area":
			continue
		var want: Dictionary = _area_aggregate(kids.get(str(a.get("id", "")), []))
		var diffs: Array = []
		for k in AGGREGATE_FIELDS:
			if not _same_value(a.get(k, null), want[k]):
				diffs.append("%s %s -> %s" % [k, str(a.get(k, null)), str(want[k])])
		if not diffs.is_empty():
			bad.append("%s: %s" % [str(a.get("id", "")), ", ".join(diffs)])
	return bad

static func _raw_layout(layout: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("%s/%s.json" % [LAYOUT_DIR, layout]))
	return parsed if parsed is Dictionary else {}

## The invariant over one feature set. Returns the violations as strings:
##   parent  — feature not within 0.5" of its parent (or parent missing / not
##             an area), or touching its parent while standing in an area of
##             another engine group (_wrong_area)
##   group   — an engine group made of separate clusters
##   category— an area whose category is not the densest of its parented features
##   straddle— count of features that fail STRICT (centroid outside / < 50%
##             inside their parent) but touch it -- the ones _wrong_area judged
func _violations(features: Array, group_map: Dictionary) -> Dictionary:
	var by_id := _by_id(features)
	var parent_bad: Array = []
	var group_bad: Array = []
	var category_bad: Array = []
	var densest := {}
	var n_parented := 0
	var straddle: Array = [0]
	for p in features:
		if str(p.get("piece_class", "")) != "feature" or str(p.get("parent_area_id", "")) == "":
			continue
		n_parented += 1
		var pid := str(p.get("id", ""))
		var parent_id := str(p.parent_area_id)
		if not by_id.has(parent_id):
			parent_bad.append("%s -> %s (missing)" % [pid, parent_id])
			continue
		var parent: Dictionary = by_id[parent_id]
		if str(parent.get("piece_class", "")) != "area":
			parent_bad.append("%s -> %s (not an area)" % [pid, parent_id])
		var gap := _poly_gap(p.polygon, parent.polygon)
		if gap > ABUT_TOL_PX:
			parent_bad.append("%s -> %s (%.1f\" away)" % [pid, parent_id, gap / PX])
		else:
			var wrong := _wrong_area(p, parent, features, group_map, straddle)
			if wrong != "":
				parent_bad.append(wrong)
		var cat := str(tm.category_of(p))
		if not densest.has(parent_id) or int(CATEGORY_RANK.get(cat, 0)) > int(CATEGORY_RANK.get(densest[parent_id], 0)):
			densest[parent_id] = cat
	var members := {}
	for pid in group_map:
		if not members.has(group_map[pid]):
			members[group_map[pid]] = []
		members[group_map[pid]].append(pid)
	for key in members:
		var comps := _clusters(members[key], by_id)
		if comps.size() > 1:
			group_bad.append("%s = %s" % [key, str(comps)])
	for p in features:
		if str(p.get("piece_class", "")) != "area":
			continue
		var aid := str(p.get("id", ""))
		var want := str(densest.get(aid, "exposed"))
		if str(tm.category_of(p)) != want:
			category_bad.append("%s is %s, its features make it %s" % [aid, tm.category_of(p), want])
	return {"parent": parent_bad, "group": group_bad, "category": category_bad, "parented": n_parented,
		"straddle": int(straddle[0])}

static func _model(id: String, pos_px: Vector2, base_mm: int = 32) -> Dictionary:
	return {"id": id, "alive": true, "base_mm": base_mm, "base_type": "circular",
		"position": {"x": pos_px.x, "y": pos_px.y}}

## Overwrite fields on the loaded features; returns the previous values.
func _apply_fields(fields: Dictionary) -> Dictionary:
	var saved := {}
	for piece in tm.terrain_features:
		var pid := str(piece.get("id", ""))
		if not fields.has(pid):
			continue
		saved[pid] = {}
		for k in fields[pid]:
			saved[pid][k] = piece.get(k, null)
			piece[k] = fields[pid][k]
	return saved

func _restore_fields(saved: Dictionary) -> void:
	for piece in tm.terrain_features:
		var pid := str(piece.get("id", ""))
		if not saved.has(pid):
			continue
		for k in saved[pid]:
			if saved[pid][k] == null:
				piece.erase(k)
			else:
				piece[k] = saved[pid][k]

func _excluded_pieces(group_map: Dictionary, groups: Dictionary) -> Array:
	var out: Array = []
	for pid in group_map:
		if groups.has(group_map[pid]):
			out.append(pid)
	out.sort()
	return out

# ── A. every layout ─────────────────────────────────────────────────────

func test_all_layouts_invariant() -> void:
	print("\n-- A. invariant over every res://terrain_layouts/*.json --")
	var names: Array = []
	for f in DirAccess.get_files_at(LAYOUT_DIR):
		if f.ends_with(".json") and f != "index_11e.json":
			names.append(f.get_basename())
	names.sort()
	_assert(names.size() >= 47, "found %d layout files (45 GW + legacy fallback + test field)" % names.size())
	var total_parented := 0
	var total_groups := 0
	var total_straddle := 0
	var total_areas := 0
	for layout in names:
		tm.load_terrain_layout(layout)
		_assert(tm.current_layout == layout, "%s: loads as itself (no fallback)" % layout)
		var feats: Array = tm.terrain_features
		var gm: Dictionary = tm.build_area_group_map(feats)
		var v := _violations(feats, gm)
		total_parented += int(v.parented)
		total_straddle += int(v.straddle)
		var keys := {}
		for pid in gm:
			keys[gm[pid]] = true
		total_groups += keys.size()
		_assert(v.parent.is_empty(), "%s: every parented feature overlaps/abuts its parent area and does not stand in another group's area (%d checked, %d straddle their parent)%s"
			% [layout, v.parented, v.straddle, "" if v.parent.is_empty() else " -- " + ", ".join(v.parent)])
		_assert(v.group.is_empty(), "%s: every engine area group is one contiguous area (%d groups)%s"
			% [layout, keys.size(), "" if v.group.is_empty() else " -- " + "; ".join(v.group)])
		_assert(v.category.is_empty(), "%s: every area's category is the densest of its features%s"
			% [layout, "" if v.category.is_empty() else " -- " + "; ".join(v.category)])
		var raw := _raw_layout(layout)
		var raw_pieces: Array = raw.get("pieces", []) if raw.get("pieces", null) is Array else []
		for rp in raw_pieces:
			if rp is Dictionary and str(rp.get("piece_class", "")) == "area":
				total_areas += 1
		var agg := _aggregate_violations(raw_pieces)
		_assert(raw.get("pieces", null) is Array and agg.is_empty(),
			"%s: every area's category / height_inches / height / traits are the generator's aggregate of its features (raw JSON, checker area-aggregate)%s"
			% [layout, "" if agg.is_empty() else " -- " + "; ".join(agg)])
	_assert(total_parented >= 1260, "checked %d parented features across all layouts (not vacuous)" % total_parented)
	_assert(total_areas >= 700, "checked the aggregate fields of %d areas across all layouts (not vacuous)" % total_areas)
	print("  (%d layouts, %d parented features, %d of them straddle their parent and went through the wrong-area rule, %d engine groups, %d areas)"
		% [names.size(), total_parented, total_straddle, total_groups, total_areas])

# ── B. take_and_hold_mirror_1 ───────────────────────────────────────────

func test_mirror_1_far_walls_not_excluded() -> void:
	print("\n-- B. take_and_hold_mirror_1: a model in area-medium-7 ignores only its own area --")
	tm.load_terrain_layout("take_and_hold_mirror_1")
	var by_id := _by_id(tm.terrain_features)
	var meas = root.get_node("Measurement")
	# 32mm model inside area-medium-7 (x 28-34", y 9-13"), base resting on the
	# vertical leg of corner-short-10 (x 28.35-28.85") without standing in it.
	var m_pos := Vector2(29.0, 11.0) * PX
	var m7 = _model("in_area_medium_7", m_pos)
	var far = _model("far_target", Vector2(22.0, 45.0) * PX)
	_assert(Geometry2D.is_point_in_polygon(m_pos, by_id["area-medium-7"].polygon), "precondition: model centre is inside area-medium-7")
	_assert(tm._circle_overlaps_polygon(m_pos, meas.base_radius_px(32), by_id["corner-short-10"].polygon)
		and not Geometry2D.is_point_in_polygon(m_pos, by_id["corner-short-10"].polygon),
		"precondition: its base touches the corner-short-10 wall (inside area-medium-7) without occupying it")
	_assert(tm.pieces_model_within(far).is_empty(), "precondition: the other model stands in open ground")

	var fixed_walls := {"corner-short-9": "area-medium-8", "corner-short-11": "area-medium-8",
		"corner-short-10": "area-medium-7", "corner-short-12": "area-medium-7"}
	for wid in fixed_walls:
		_assert(str(by_id[wid].get("parent_area_id", "")) == fixed_walls[wid],
			"shipped data: %s is parented to %s, the area it stands in" % [wid, fixed_walls[wid]])
	var gm: Dictionary = tm.build_area_group_map(tm.terrain_features)
	var ex: Dictionary = tm.visibility_exclusions_for(m7, far, tm.terrain_features, gm)
	var after := _excluded_pieces(gm, ex.groups)
	print("  AFTER  excluded pieces for the model in area-medium-7: %s" % str(after))
	_assert(after == ["area-medium-7", "corner-short-10", "corner-short-12"],
		"after: the model's 13.10 exclusions are exactly area-medium-7 and its two walls (got %s)" % str(after))
	_assert(not after.has("corner-short-9") and not after.has("corner-short-11"),
		"after: the far corner walls (37\" away, in area-medium-8) are NOT excluded from its sight lines")
	_assert(not after.has("area-medium-8"), "after: the far area-medium-8 still obscures its sight lines")
	var max_gap := 0.0
	for pid in after:
		max_gap = maxf(max_gap, _poly_gap(by_id[pid].polygon, by_id["area-medium-7"].polygon))
	_assert(max_gap <= ABUT_TOL_PX, "after: every excluded piece is within 0.5\" of area-medium-7 (max %.1f\")" % (max_gap / PX))

	# [pre-fix] the 40kdc 1.0.19 links, re-applied in memory.
	var saved := _apply_fields({"corner-short-9": {"parent_area_id": "area-medium-7"}, "corner-short-11": {"parent_area_id": "area-medium-7"},
		"corner-short-10": {"parent_area_id": "area-medium-8"}, "corner-short-12": {"parent_area_id": "area-medium-8"}})
	var gm_old: Dictionary = tm.build_area_group_map(tm.terrain_features)
	var ex_old: Dictionary = tm.visibility_exclusions_for(m7, far, tm.terrain_features, gm_old)
	var before := _excluded_pieces(gm_old, ex_old.groups)
	print("  BEFORE excluded pieces for the model in area-medium-7: %s" % str(before))
	_assert(before.has("corner-short-9") and before.has("corner-short-11") and before.has("area-medium-8"),
		"[pre-fix] the far walls and area-medium-8 (37\" away) WERE excluded for this model (%s)" % str(before))
	var v_old := _violations(tm.terrain_features, gm_old)
	_assert(v_old.parent.size() == 4 and v_old.group.size() == 2,
		"[pre-fix] the invariant flags the 4 far walls and the 2 split groups (%d / %d)" % [v_old.parent.size(), v_old.group.size()])
	_restore_fields(saved)

# ── C. take_and_hold_vs_reconnaissance_1 ────────────────────────────────

func test_recon_1_home_ruin_hides_and_obscures() -> void:
	print("\n-- C. take_and_hold_vs_reconnaissance_1: the home ruin area-large-7 owns its walls --")
	tm.load_terrain_layout("take_and_hold_vs_reconnaissance_1")
	var by_id := _by_id(tm.terrain_features)
	var infantry := {"meta": {"keywords": ["INFANTRY"]}, "flags": {}}
	# Inside area-large-7 (x 25.5-37", y 48-55"), clear of both walls.
	var in_ruin = _model("in_ruin", Vector2(32.5, 53.5) * PX)
	var within_ids: Array = tm.pieces_model_within(in_ruin).map(func(p): return str(p.id))
	_assert(within_ids == ["area-large-7"], "precondition: the INFANTRY model is within area-large-7 only (%s)" % str(within_ids))
	# Observer in the ruin with its base on the dense wall corner-ruin-balanced-right-13;
	# target 20" north-west, behind the dense area-medium-9 (x 24-30", y 41-45").
	var obs = _model("on_wall", Vector2(25.81, 48.27) * PX)
	var tgt = _model("behind_area_medium_9", Vector2(19.0, 29.0) * PX)

	var gm: Dictionary = tm.build_area_group_map(tm.terrain_features)
	_assert(gm["corner-ruin-balanced-right-13"] == gm["area-large-7"] and gm["corner-short-15"] == gm["area-large-7"],
		"shipped data: both walls standing in area-large-7 are in its group")
	_assert(str(tm.category_of(by_id["area-large-7"])) == "dense", "shipped data: area-large-7 is dense (it contains a dense wall)")
	var hidden_after: bool = tm.is_model_hidden(in_ruin, infantry)
	var vis_after: bool = tm.model_visible_11e(obs, tgt)
	print("  AFTER  hidden in area-large-7=%s  sight line through area-medium-9 visible=%s" % [hidden_after, vis_after])
	_assert(hidden_after, "after: INFANTRY within the home ruin is hidden (13.09: its area contains a dense wall)")
	_assert(not vis_after, "after: the dense area-medium-9 blocks the model touching the wall (13.10)")

	var saved := _apply_fields({
		"corner-ruin-balanced-right-13": {"parent_area_id": "area-medium-9"},
		"corner-short-15": {"parent_area_id": "area-medium-9"},
		"area-large-7": {"category": "exposed", "height_category": "low", "height_inches": 0.0}})
	var hidden_before: bool = tm.is_model_hidden(in_ruin, infantry)
	var vis_before: bool = tm.model_visible_11e(obs, tgt)
	print("  BEFORE hidden in area-large-7=%s  sight line through area-medium-9 visible=%s" % [hidden_before, vis_before])
	_assert(not hidden_before, "[pre-fix] the same model was NOT hidden (its ruin was 'exposed', the walls grouped with area-medium-9)")
	_assert(vis_before, "[pre-fix] the model touching the wall saw THROUGH area-medium-9 (it excluded that area)")
	_restore_fields(saved)

# ── D. reconnaissance_vs_reconnaissance_2 ───────────────────────────────

func test_recon_vs_recon_2_link_group_split() -> void:
	print("\n-- D. reconnaissance_vs_reconnaissance_2: link_group \"2\" no longer merges four areas --")
	tm.load_terrain_layout("reconnaissance_vs_reconnaissance_2")
	var gm: Dictionary = tm.build_area_group_map(tm.terrain_features)
	_assert(gm["area-medium-29"] == gm["area-short-line-25"], "shipped data: area-medium-29 stays linked with the area-short-line-25 it abuts")
	_assert(gm["area-long-line-35"] == gm["area-short-line-43"], "shipped data: area-long-line-35 stays linked with area-short-line-43")
	_assert(gm["area-medium-29"] != gm["area-long-line-35"] and gm["area-medium-29"] != gm["area-medium-30"]
		and gm["area-long-line-35"] != gm["area-long-line-36"], "shipped data: the four separate clusters are four groups")
	var obs = _model("in_area_medium_29", Vector2(33.0, 28.0) * PX)
	var tgt = _model("behind_area_long_line_35", Vector2(30.0, 46.0) * PX)
	var within_ids: Array = tm.pieces_model_within(obs).map(func(p): return str(p.id))
	_assert(within_ids == ["area-medium-29"], "precondition: the observer is within area-medium-29 only (%s)" % str(within_ids))
	var vis_after: bool = tm.model_visible_11e(obs, tgt)
	var saved := _apply_fields({"area-short-line-26": {"link_group": "2"}, "area-medium-30": {"link_group": "2"},
		"area-long-line-35": {"link_group": "2"}, "area-short-line-43": {"link_group": "2"},
		"area-long-line-36": {"link_group": "2"}, "area-short-line-44": {"link_group": "2"}})
	var vis_before: bool = tm.model_visible_11e(obs, tgt)
	_restore_fields(saved)
	print("  AFTER visible=%s   BEFORE (one shared label) visible=%s" % [vis_after, vis_before])
	_assert(not vis_after, "after: the area 13\" south (area-long-line-35 / -43) obscures the model in area-medium-29")
	_assert(vis_before, "[pre-fix] with one shared label the model ignored that separate area and saw through it")

# ── E. negative controls for invariant A ────────────────────────────────

## The runtime fields an area's aggregate lands in (JSON `height` is the
## engine's height_category).
func _rederive_area_fields(area_ids: Array) -> Dictionary:
	var kids := {}
	for p in tm.terrain_features:
		if str(p.get("piece_class", "")) == "feature" and str(p.get("parent_area_id", "")) != "":
			if not kids.has(str(p.parent_area_id)):
				kids[str(p.parent_area_id)] = []
			kids[str(p.parent_area_id)].append(p)
	var fields := {}
	for aid in area_ids:
		var want: Dictionary = _area_aggregate(kids.get(aid, []))
		fields[aid] = {"category": want.category, "height_inches": float(want.height_inches),
			"height_category": want.height, "traits": want.traits}
	return fields

func test_wrong_area_parent_is_caught() -> void:
	print("\n-- E1. invariant A: a wall parented to the area it only LEANS against is caught --")
	# disruption_vs_reconnaissance_3: the dense corner-ruin-left-31 stands wholly in
	# area-large-29 and its edge passes 0.18" from the light area-medium-35.
	tm.load_terrain_layout("disruption_vs_reconnaissance_3")
	var by_id := _by_id(tm.terrain_features)
	var wall: Dictionary = by_id["corner-ruin-left-31"]
	var home: Dictionary = by_id["area-large-29"]
	var lean: Dictionary = by_id["area-medium-35"]
	var gm: Dictionary = tm.build_area_group_map(tm.terrain_features)
	_assert(str(wall.get("parent_area_id", "")) == "area-large-29" and _overlap_fraction(wall.polygon, home.polygon) > 0.99,
		"shipped data: corner-ruin-left-31 stands wholly in its parent area-large-29")
	var gap := _poly_gap(wall.polygon, lean.polygon)
	_assert(gap <= ABUT_TOL_PX and _overlap_fraction(wall.polygon, lean.polygon) == 0.0,
		"precondition: it touches area-medium-35 (%.2f\" away) without standing in it" % (gap / PX))
	_assert(gm["area-medium-35"] != gm["area-large-29"] and str(tm.category_of(lean)) == "light",
		"precondition: area-medium-35 is a separate, light engine group")

	# The slip: parent the wall to the area it leans against, then re-derive both
	# areas the generator's way, as a regenerated layout would carry them
	# (area-medium-35 turns dense). Same mutation as the L5 verifier's l51_mutate.py.
	var saved := _apply_fields({"corner-ruin-left-31": {"parent_area_id": "area-medium-35"}})
	var saved_areas := _apply_fields(_rederive_area_fields(["area-large-29", "area-medium-35"]))
	var gm_bad: Dictionary = tm.build_area_group_map(tm.terrain_features)
	var v := _violations(tm.terrain_features, gm_bad)
	print("  [mutation] parent violations: %s" % str(v.parent))
	_assert(gm_bad["corner-ruin-left-31"] == gm_bad["area-medium-35"] and str(tm.category_of(lean)) == "dense",
		"[mutation] the engine folds the dense wall into area-medium-35's group and makes that empty area dense")
	_assert(v.group.is_empty() and v.category.is_empty(),
		"[mutation] the gap, contiguity and category checks are blind to it (it touches its wrong parent; areas re-derived)")
	_assert(v.parent.size() == 1 and str(v.parent[0]).begins_with("corner-ruin-left-31 -> area-medium-35")
		and str(v.parent[0]).contains("area-large-29"),
		"[mutation] the wrong-area rule flags it: 100%% of it stands in area-large-29, another engine group (%s)" % str(v.parent))
	_restore_fields(saved_areas)
	_restore_fields(saved)
	var v_back := _violations(tm.terrain_features, tm.build_area_group_map(tm.terrain_features))
	_assert(v_back.parent.is_empty() and str(tm.category_of(lean)) == "light", "restored: the layout is clean again")

func test_stale_area_aggregate_is_caught() -> void:
	print("\n-- E2. invariant A: an area whose height / traits went stale is caught --")
	# take_and_hold_vs_reconnaissance_1: the home ruins area-large-7/8 hold 5" dense
	# walls. Put back the pre-fix height / height_inches / traits but keep the right
	# category -- what a partial revert or a hand re-parent leaves behind (the L5
	# verifier's l52_mutate.py). Charge / move climb costs read the stale height.
	var raw := _raw_layout("take_and_hold_vs_reconnaissance_1")
	var raw_pieces: Array = raw.get("pieces", []) if raw.get("pieces", null) is Array else []
	_assert(not raw_pieces.is_empty() and _aggregate_violations(raw_pieces).is_empty(),
		"shipped data: every area of take_and_hold_vs_reconnaissance_1 matches its features")
	var by_id := _by_id(raw_pieces)
	for aid in ["area-large-7", "area-large-8"]:
		var a: Dictionary = by_id[aid]
		_assert(str(a.get("category", "")) == "dense" and str(a.get("height", "")) == "tall",
			"shipped data: %s is dense and tall (its walls are 5\")" % aid)
		a["height"] = "low"
		a["height_inches"] = 0
		a["traits"] = ["difficult_ground"]
	var bad := _aggregate_violations(raw_pieces)
	print("  [mutation] aggregate violations: %s" % str(bad))
	_assert(bad.size() == 2 and str(bad[0]).begins_with("area-large-7:") and str(bad[1]).begins_with("area-large-8:")
		and str(bad[0]).contains("height low -> tall") and str(bad[0]).contains("height_inches 0 -> 5")
		and str(bad[0]).contains("traits"),
		"[mutation] the aggregate check flags both areas' height, height_inches and traits")
	var cat_blind := true
	for aid in ["area-large-7", "area-large-8"]:
		var densest := "exposed"
		for p in raw_pieces:
			if str(p.get("parent_area_id", "")) == aid and int(CATEGORY_RANK.get(str(tm.category_of(p)), 0)) > int(CATEGORY_RANK[densest]):
				densest = str(tm.category_of(p))
		cat_blind = cat_blind and str(tm.category_of(by_id[aid])) == densest
	_assert(cat_blind, "[mutation] the category check alone (the invariant before the aggregate check) is blind to it")
