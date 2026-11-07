var PPI = 40.0
var feats = TerrainManager.terrain_features
var gm = TerrainManager.build_area_group_map(feats)
var groups = {}
for piece in feats:
	var g = gm.get(str(piece.get("id", "")), "id:" + str(piece.get("id", "")))
	if not groups.has(g):
		groups[g] = {"pieces": 0, "dense": false, "light": false, "classes": {}, "minx": INF, "miny": INF, "maxx": -INF, "maxy": -INF, "area_sq_in": 0.0, "types": {}}
	var gg = groups[g]
	gg.pieces += 1
	var cat = TerrainManager.category_of(piece)
	if cat == "dense":
		gg.dense = true
	if cat == "light":
		gg.light = true
	gg.classes[str(piece.get("piece_class", "?"))] = true
	gg.types[str(piece.get("type", "?"))] = true
	var poly = piece.get("polygon", PackedVector2Array())
	if poly is Array:
		var pp = PackedVector2Array()
		for v in poly:
			pp.append(v if v is Vector2 else Vector2(v.x, v.y))
		poly = pp
	if poly.size() >= 3:
		for v in poly:
			gg.minx = min(gg.minx, v.x); gg.maxx = max(gg.maxx, v.x)
			gg.miny = min(gg.miny, v.y); gg.maxy = max(gg.maxy, v.y)
		if str(piece.get("piece_class", "")) == "area":
			var a = 0.0
			for i in range(poly.size()):
				var p1 = poly[i]; var p2 = poly[(i + 1) % poly.size()]
				a += p1.x * p2.y - p2.x * p1.y
			gg.area_sq_in += abs(a) / 2.0 / (PPI * PPI)
var zones = GameState.state.get("board", {}).get("deployment_zones", [])
var zp = {}
for z in zones:
	var pts = PackedVector2Array()
	for v in z.get("poly", []):
		pts.append(Vector2(float(v.get("x", 0)) * PPI, float(v.get("y", 0)) * PPI) if v is Dictionary else Vector2(v.x * PPI, v.y * PPI))
	zp[int(z.get("player", 0))] = pts
var out = []
for g in groups:
	var gg = groups[g]
	var c = Vector2((gg.minx + gg.maxx) / 2.0, (gg.miny + gg.maxy) / 2.0)
	var inz = []
	for p in zp:
		if Geometry2D.is_point_in_polygon(c, zp[p]):
			inz.append(p)
	out.append({"g": g, "cat": "dense" if gg.dense else ("light" if gg.light else "exposed"), "pieces": gg.pieces, "bbox_in": [snapped(gg.minx / PPI, 0.1), snapped(gg.miny / PPI, 0.1), snapped(gg.maxx / PPI, 0.1), snapped(gg.maxy / PPI, 0.1)], "area_sq_in": snapped(gg.area_sq_in, 1), "center_in_zone": inz, "classes": gg.classes.keys(), "types": gg.types.keys()})
var zinfo = {}
for p in zp:
	var a = 0.0
	var poly = zp[p]
	for i in range(poly.size()):
		var p1 = poly[i]; var p2 = poly[(i + 1) % poly.size()]
		a += p1.x * p2.y - p2.x * p1.y
	var pts_in = []
	for v in poly:
		pts_in.append([snapped(v.x / PPI, 0.1), snapped(v.y / PPI, 0.1)])
	zinfo[p] = {"area_sq_in": snapped(abs(a) / 2.0 / (PPI * PPI), 1), "poly_in": pts_in}
var objs = []
for o in GameState.state.get("board", {}).get("objectives", []):
	objs.append({"id": o.get("id", "?"), "pos": o.get("position", null), "kind": o.get("zone", o.get("type", o.get("designation", "")))})
return {"groups": out, "zones": zinfo, "objectives": objs, "layout": GameState.state.get("board", {}).get("terrain_layout", "?"), "board": GameState.state.get("board", {}).get("size", {})}
