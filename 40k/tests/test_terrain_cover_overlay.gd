extends SceneTree

# T07 — per-tile terrain cover icons (design doc §6).
#
# Covers the pieces of TerrainCoverOverlay that do not need a window:
#   - TerrainManager.cover_type_of(): the glyph is the 11e terrain category
#     (13.02-13.05) on the doc's light / heavy / blocking ladder —
#     exposed "+1", light "+2", dense "LB" — and height does NOT change it
#     (the old height-based derivation labelled a light tall ruin "LB").
#   - TerrainCoverOverlay.centroid_of(): the polygon AREA centroid, not the
#     vertex average (an L-shaped corner ruin / trapezoid differ by ~20-48px).
#   - One icon per terrain piece, named TerrainCoverIcon_<id>, labelled with
#     cover_type_of, at the centroid, below the tokens — on the shipped default
#     layout, and still addressable by name after a terrain reload (the old
#     queue_free() rebuild left the dying icons in place, so the new ones were
#     auto-renamed "@Node2D@N").
#   - Screen-space sizing: icons are counter-scaled / counter-rotated against
#     BoardRoot's zoom + rotation so the glyph keeps its on-screen size upright.
#
# Usage: godot --headless --path . -s tests/test_terrain_cover_overlay.gd

var passed := 0
var failed := 0
var _ran := false


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _init():
	create_timer(0.1).timeout.connect(_run_tests)


func _rect(cx: float, cy: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(cx - w / 2, cy - h / 2), Vector2(cx + w / 2, cy - h / 2),
		Vector2(cx + w / 2, cy + h / 2), Vector2(cx - w / 2, cy + h / 2)])


func _area_centroid(poly: PackedVector2Array) -> Vector2:
	var a2 := 0.0
	var acc := Vector2.ZERO
	for i in range(poly.size()):
		var p: Vector2 = poly[i]
		var q: Vector2 = poly[(i + 1) % poly.size()]
		var cr := p.x * q.y - q.x * p.y
		a2 += cr
		acc += (p + q) * cr
	return acc / (3.0 * a2)


func _finish() -> void:
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _run_tests() -> void:
	if _ran:
		return
	_ran = true
	print("\n=== test_terrain_cover_overlay (T07) ===\n")
	var tm = root.get_node_or_null("TerrainManager")
	if tm == null:
		_check("TerrainManager reachable", false)
		_finish()
		return
	# Loaded at runtime (not preloaded): the overlay looks autoloads up by
	# path, and a compile before autoload registration would be noise.
	var Overlay = load("res://scripts/TerrainCoverOverlay.gd")
	_check("TerrainCoverOverlay script loads", Overlay != null)
	if Overlay == null:
		_finish()
		return
	# API presence first, so a missing helper fails cleanly instead of
	# aborting the run on a script error (and hanging until the timeout).
	var overlay_api := []
	for m in Overlay.get_script_method_list():
		overlay_api.append(str(m.get("name", "")))
	var has_cover_type: bool = tm.has_method("cover_type_of")
	var has_centroid: bool = overlay_api.has("centroid_of")
	var has_sync: bool = overlay_api.has("_sync_screen_transform")
	_check("TerrainManager.cover_type_of exists", has_cover_type)
	_check("TerrainCoverOverlay.centroid_of exists", has_centroid)
	_check("TerrainCoverOverlay._sync_screen_transform exists", has_sync)
	if not (has_cover_type and has_centroid and has_sync):
		_finish()
		return

	print("-- cover_type_of: 11e category -> glyph --")
	_check("dense -> LB", tm.cover_type_of({"type": "ruins", "category": "dense"}) == "LB")
	_check("light -> +2", tm.cover_type_of({"type": "ruins", "category": "light"}) == "+2")
	_check("exposed -> +1", tm.cover_type_of({"type": "ruins", "category": "exposed"}) == "+1")
	_check("light TALL ruin is still +2 (height does not change 11e cover)",
		tm.cover_type_of({"type": "ruins", "category": "light", "height_category": "tall"}) == "+2",
		tm.cover_type_of({"type": "ruins", "category": "light", "height_category": "tall"}))
	_check("dense MEDIUM piece is LB",
		tm.cover_type_of({"type": "ruins", "category": "dense", "height_category": "medium"}) == "LB")
	_check("legacy ruins (no category) -> dense -> LB", tm.cover_type_of({"type": "ruins"}) == "LB")
	_check("legacy barricade (no category) -> light -> +2", tm.cover_type_of({"type": "barricade"}) == "+2")
	_check("legacy crater (no category) -> exposed -> +1", tm.cover_type_of({"type": "crater"}) == "+1")
	_check("glyph constants are the doc's three", [tm.COVER_TYPE_EXPOSED, tm.COVER_TYPE_LIGHT, tm.COVER_TYPE_DENSE] == ["+1", "+2", "LB"])

	print("\n-- centroid_of: polygon area centroid --")
	# L-shaped corner ruin: 4x4 square with the top-right 2x2 cut away.
	var ell := PackedVector2Array([
		Vector2(0, 0), Vector2(80, 0), Vector2(80, 80), Vector2(160, 80),
		Vector2(160, 160), Vector2(0, 160)])
	var ell_c: Vector2 = Overlay.centroid_of({"polygon": ell})
	var expect_ell := _area_centroid(ell)
	var vertex_avg := Vector2.ZERO
	for p in ell:
		vertex_avg += p
	vertex_avg /= ell.size()
	_check("L-shape: area centroid", ell_c.distance_to(expect_ell) < 0.01, "%s vs %s" % [ell_c, expect_ell])
	_check("L-shape: NOT the vertex average (the old fallback)", ell_c.distance_to(vertex_avg) > 5.0,
		"%s vs avg %s" % [ell_c, vertex_avg])
	_check("rectangle: its centre", Overlay.centroid_of({"polygon": _rect(300, 200, 120, 60)}).distance_to(Vector2(300, 200)) < 0.01)
	var tri_cw := PackedVector2Array([Vector2(0, 0), Vector2(0, 90), Vector2(90, 0)])
	_check("winding order does not matter", Overlay.centroid_of({"polygon": tri_cw}).distance_to(Vector2(30, 30)) < 0.01)
	_check("Array of {x,y} dicts (snapshot form) works",
		Overlay.centroid_of({"polygon": [{"x": 0, "y": 0}, {"x": 100, "y": 0}, {"x": 100, "y": 40}, {"x": 0, "y": 40}]}).distance_to(Vector2(50, 20)) < 0.01)
	_check("degenerate polygon falls back to position",
		Overlay.centroid_of({"polygon": PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)]), "position": Vector2(7, 9)}) == Vector2(7, 9))
	# The shipped layouts author `position` as the area centroid: the overlay
	# must agree with it on every piece of the default layout.
	var prev_layout: String = tm.current_layout
	tm.load_terrain_layout(tm.DEFAULT_LAYOUT)
	var worst := 0.0
	for f in tm.terrain_features:
		worst = maxf(worst, Overlay.centroid_of(f).distance_to(f.position))
	_check("default layout: centroid_of == authored centre on all %d pieces" % tm.terrain_features.size(),
		tm.terrain_features.size() > 0 and worst < 0.5, "worst %.2fpx" % worst)

	print("\n-- icons on the default layout --")
	var board := Node2D.new()
	board.name = "T07Board"
	root.add_child(board)
	var ov = Overlay.new()
	board.add_child(ov)
	await process_frame
	var n_features: int = tm.terrain_features.size()
	_check("overlay named TerrainCoverOverlay", ov.name == "TerrainCoverOverlay", str(ov.name))
	_check("one icon per terrain piece", ov.get_child_count() == n_features, "%d vs %d" % [ov.get_child_count(), n_features])
	var bad := []
	var kinds := {}
	for f in tm.terrain_features:
		var icon = ov.get_node_or_null("TerrainCoverIcon_" + str(f.id))
		if icon == null:
			bad.append(str(f.id) + " missing")
			continue
		var text: String = icon.get_node("Label").text
		kinds[text] = true
		if text != tm.cover_type_of(f):
			bad.append("%s label %s" % [f.id, text])
		if icon.position.distance_to(_area_centroid(f.polygon)) > 8.0:
			bad.append("%s off-centre" % f.id)
		if icon.modulate.a < 0.8:
			bad.append("%s alpha %.2f" % [f.id, icon.modulate.a])
		if icon.get_node_or_null("Shield") == null:
			bad.append("%s no Shield" % f.id)
	_check("every icon: named by id, labelled cover_type_of, at the centroid, alpha >= 0.8", bad.is_empty(), str(bad.slice(0, 5)))
	_check("default layout shows both LB and +2", kinds.has("LB") and kinds.has("+2"), str(kinds.keys()))
	_check("icons draw below tokens (TokenVisual z_index 10)", ov.z_index < 10, str(ov.z_index))

	print("\n-- terrain reload keeps icon names --")
	tm.load_terrain_layout(tm.DEFAULT_LAYOUT)
	await process_frame
	var renamed := []
	for c in ov.get_children():
		if not str(c.name).begins_with("TerrainCoverIcon_"):
			renamed.append(str(c.name))
	var missing := []
	for f in tm.terrain_features:
		if ov.get_node_or_null("TerrainCoverIcon_" + str(f.id)) == null:
			missing.append(str(f.id))
	_check("after reload: still one icon per piece", ov.get_child_count() == tm.terrain_features.size(),
		"%d vs %d" % [ov.get_child_count(), tm.terrain_features.size()])
	_check("after reload: no auto-renamed icons", renamed.is_empty(), str(renamed.slice(0, 3)))
	_check("after reload: every piece addressable by name", missing.is_empty(), str(missing.slice(0, 3)))

	print("\n-- constant on-screen size, upright --")
	ov.visible = true
	board.scale = Vector2(0.5, 0.5)
	board.rotation = PI / 2.0
	ov._sync_screen_transform(true)
	var icon0: Node2D = ov.get_child(0)
	var xf: Transform2D = icon0.get_global_transform_with_canvas()
	_check("zoom 0.5: icon counter-scaled x2", is_equal_approx(icon0.scale.x, 2.0), str(icon0.scale))
	_check("zoom 0.5: on-screen scale 1", absf(xf.get_scale().x - 1.0) < 0.001, str(xf.get_scale()))
	_check("board rotated 90deg: icon upright on screen", absf(xf.get_rotation()) < 0.001, str(xf.get_rotation()))
	_check("position (the centroid) untouched by the counter-scale",
		icon0.position.distance_to(Overlay.centroid_of(tm.terrain_features[0])) < 0.01)
	board.scale = Vector2(2.0, 2.0)
	board.rotation = 0.0
	await process_frame
	await process_frame
	xf = icon0.get_global_transform_with_canvas()
	_check("zoom 2.0 (via _process): on-screen scale 1", absf(xf.get_scale().x - 1.0) < 0.001, str(xf.get_scale()))
	_check("zoom 2.0: rotation back to 0", absf(icon0.rotation) < 0.001, str(icon0.rotation))

	board.queue_free()
	tm.load_terrain_layout(prev_layout)
	_finish()
