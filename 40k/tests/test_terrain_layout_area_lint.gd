extends SceneTree

# Terrain layout lint (13.01): "a terrain feature is placed wholly within the
# boundary of its terrain area". Every runtime consumer of the area grouping —
# 13.09 HIDDEN (TerrainManager.is_model_hidden), 13.10 OBSCURING exclusions
# (visibility_exclusions_for) — follows a feature's parent_area_id, and the
# layout generator derives an area's category from the features parented to it.
# A feature parented to the WRONG area therefore moves its cover/hiding/
# obscuring effect across the board.
#
# Checks, over every layout in res://terrain_layouts/:
#   1. every parent_area_id names an existing "area" piece;
#   2. every feature lies within its parent area GROUP (link_group halves count
#      as one area) — allowing a 0.6" overhang: 128 catwalk / corner pieces
#      (124 in the 45 official layouts, 4 in the legacy fallback copy) overhang
#      their area edge by up to 0.50" (geometry quirk of the converted
#      templates, recorded here, not "fixed");
#   3. no feature lies wholly inside a DIFFERENT area while outside its own
#      (a mis-parented feature);
#   4. an area's category is the highest category of the features parented to
#      it, and 5. its height_inches the tallest of them (the generator's
#      derivation, scripts/40kdc/generate-terrain-layouts.mjs areaContents —
#      exposed / 0" when it has none).
# Plus the live consequence on take_and_hold_vs_reconnaissance_1: the home
# objective area "area-large-7" holds a dense ruin and a light ruin, so an
# INFANTRY model in its open ground is hidden and the area obscures (13.10).
#
# Regression: 30 features in 8 layouts (incl. the default take_and_hold_mirror_1
# and the legacy fallback) were parented to an area they do not touch: 26 to
# the mirrored area of a symmetric pair, 19-44" away (same category, so only the
# 13.10 exclusion grouping was wrong), and on take_and_hold_vs_reconnaissance_1
# the dense + light ruins of both home objective areas to a nearby generator
# area 3-9" away, which left those home areas "exposed" (never hiding, never
# obscuring).
#
# Usage: godot --headless --path . -s tests/test_terrain_layout_area_lint.gd

const LAYOUT_DIR := "res://terrain_layouts/"
const OVERHANG_TOL_IN := 0.6
const STRICT_TOL_IN := 0.05
const RANK := {"exposed": 0, "light": 1, "dense": 2}

var passed := 0
var failed := 0
var _completed := false  # set by the last line of _run(): an aborted run (script error) counts as a failure

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

func _poly(raw) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in raw:
		if v is Array:
			out.append(Vector2(float(v[0]), float(v[1])))
		elif v is Dictionary:
			out.append(Vector2(float(v.get("x", 0)), float(v.get("y", 0))))
	return out

## Vertices plus edge midpoints of a feature footprint.
func _sample_points(poly: PackedVector2Array) -> Array:
	var out: Array = []
	for i in range(poly.size()):
		out.append(poly[i])
		out.append((poly[i] + poly[(i + 1) % poly.size()]) / 2.0)
	return out

## How far (inches) `pt` lies outside the union of `polys` (0 when inside).
func _outside(pt: Vector2, polys: Array) -> float:
	var best := INF
	for poly in polys:
		if Geometry2D.is_point_in_polygon(pt, poly):
			return 0.0
		for i in range(poly.size()):
			var c := Geometry2D.get_closest_point_to_segment(pt, poly[i], poly[(i + 1) % poly.size()])
			best = minf(best, pt.distance_to(c))
	return best

func _max_outside(feature_poly: PackedVector2Array, polys: Array) -> float:
	var worst := 0.0
	for q in _sample_points(feature_poly):
		worst = maxf(worst, _outside(q, polys))
	return worst

func _lint_layout(name: String, pieces: Array, report: Dictionary) -> void:
	var by := {}
	var areas: Array = []
	for p in pieces:
		by[str(p.get("id", ""))] = p
		if str(p.get("piece_class", "")) == "area":
			areas.append(p)
	var group_polys := func(aid: String) -> Array:
		var a: Dictionary = by.get(aid, {})
		var lg := str(a.get("link_group", ""))
		var out: Array = []
		for ar in areas:
			if (lg != "" and str(ar.get("link_group", "")) == lg) or (lg == "" and str(ar.get("id", "")) == aid):
				out.append(_poly(ar.get("polygon", [])))
		return out
	for p in pieces:
		if str(p.get("piece_class", "")) != "feature" or str(p.get("parent_area_id", "")) == "":
			continue
		report.features += 1
		var fid := str(p.get("id", ""))
		var pid := str(p.parent_area_id)
		if not by.has(pid) or str(by[pid].get("piece_class", "")) != "area":
			report.bad_parent.append("%s: %s -> %s" % [name, fid, pid])
			continue
		var fpoly := _poly(p.get("polygon", []))
		var out_own := _max_outside(fpoly, group_polys.call(pid))
		if out_own > STRICT_TOL_IN and out_own <= OVERHANG_TOL_IN:
			report.overhangs += 1
		if out_own > OVERHANG_TOL_IN:
			var inside_other: Array = []
			for ar in areas:
				if _max_outside(fpoly, [_poly(ar.get("polygon", []))]) <= STRICT_TOL_IN:
					inside_other.append(str(ar.get("id", "")))
			report.outside_parent.append("%s: %s (%s) parent %s, %.1f\" outside it%s" % [name, fid, str(p.get("category", "")), pid, out_own,
				"; lies inside %s" % str(inside_other) if not inside_other.is_empty() else ""])
			if not inside_other.is_empty():
				report.misparented += 1
	for a in areas:
		var want := "exposed"
		var want_h := 0.0
		for p in pieces:
			if str(p.get("parent_area_id", "")) == str(a.get("id", "")) and str(p.get("piece_class", "")) == "feature":
				var c := str(p.get("category", "exposed"))
				if int(RANK.get(c, 0)) > int(RANK.get(want, 0)):
					want = c
				want_h = maxf(want_h, float(p.get("height_inches", 0.0)))
		if str(a.get("category", "")) != want:
			report.bad_category.append("%s: %s is %s, its features make it %s" % [name, str(a.get("id", "")), str(a.get("category", "")), want])
		if not is_equal_approx(float(a.get("height_inches", 0.0)), want_h):
			report.bad_height.append("%s: %s is %.1f\", its tallest feature %.1f\"" % [name, str(a.get("id", "")), float(a.get("height_inches", 0.0)), want_h])

func _run() -> void:
	print("\n=== test_terrain_layout_area_lint ===")
	var report := {"layouts": 0, "features": 0, "overhangs": 0, "misparented": 0,
		"bad_parent": [], "outside_parent": [], "bad_category": [], "bad_height": []}
	var dir := DirAccess.open(LAYOUT_DIR)
	_check("terrain_layouts/ readable", dir != null)
	if dir == null:
		return
	var files: Array = []
	for f in dir.get_files():
		if f.ends_with(".json"):
			files.append(f)
	files.sort()
	for f in files:
		var txt := FileAccess.get_file_as_string(LAYOUT_DIR + f)
		var data = JSON.parse_string(txt)
		if not (data is Dictionary) or not (data.get("pieces", null) is Array):
			continue
		report.layouts += 1
		_lint_layout(f, data.pieces, report)
	print("   %d layouts, %d parented features; %d overhang their area by <= %.1f\" (dataset geometry, tolerated)" % [
		report.layouts, report.features, report.overhangs, OVERHANG_TOL_IN])
	for line in report.outside_parent:
		print("   OUTSIDE: %s" % line)
	_check("lint ran over the official layouts (>= 45, >= 1000 features)", report.layouts >= 45 and report.features >= 1000, str(report.layouts))
	_check("every parent_area_id names an existing area piece", report.bad_parent.is_empty(), str(report.bad_parent))
	_check("every feature lies within its parent area (group), <= %.1f\" overhang" % OVERHANG_TOL_IN, report.outside_parent.is_empty(),
		"%d outside" % report.outside_parent.size())
	_check("no feature sits wholly inside a different area than its parent", report.misparented == 0, "%d mis-parented" % report.misparented)
	_check("every area's category = its features' highest category", report.bad_category.is_empty(), str(report.bad_category))
	_check("every area's height_inches = its tallest feature's", report.bad_height.is_empty(), str(report.bad_height))

	print("\n-- live: take_and_hold_vs_reconnaissance_1, home objective area-large-7 --")
	var tm = root.get_node("TerrainManager")
	var prev_terrain = tm.terrain_features.duplicate(true)
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	tm.load_terrain_layout("take_and_hold_vs_reconnaissance_1")
	var area: Dictionary = {}
	for p in tm.terrain_features:
		if str(p.get("id", "")) == "area-large-7":
			area = p
	_check("area-large-7 (home objective) is dense: it holds a dense and a light ruin", tm.category_of(area) == "dense", str(area.get("category", "")))
	# (31", 52"): open ground of area-large-7, touching neither ruin.
	var m := {"id": "m", "alive": true, "base_mm": 32, "base_type": "circular", "position": {"x": 31.0 * 40.0, "y": 52.0 * 40.0}}
	var within_ids: Array = []
	for p in tm.pieces_model_within(m):
		within_ids.append(str(p.get("id", "")))
	_check("probe model is within area-large-7 only (%s)" % str(within_ids), within_ids == ["area-large-7"])
	_check("an INFANTRY model in its open ground is hidden (13.09)", tm.is_model_hidden(m, {"meta": {"keywords": ["INFANTRY"]}, "flags": {}}))
	var a := {"id": "a", "alive": true, "base_mm": 32, "base_type": "circular", "position": {"x": 31.0 * 40.0, "y": 46.3 * 40.0}}
	var b := {"id": "b", "alive": true, "base_mm": 32, "base_type": "circular", "position": {"x": 31.0 * 40.0, "y": 57.5 * 40.0}}
	_check("a sight line across area-large-7 that touches neither ruin is obscured (13.10)", not tm.model_visible_11e(a, b))
	tm.terrain_features = prev_terrain
	GameConstants.edition = prev_edition
	_completed = true
