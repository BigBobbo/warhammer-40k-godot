var PPI = 40.0
var out = {"terrain": [], "models": [], "zones": [], "objectives": []}
for piece in TerrainManager.terrain_features:
	var poly = piece.get("polygon", PackedVector2Array())
	var pts = []
	for v in poly:
		var vv = v if v is Vector2 else Vector2(v.x, v.y)
		pts.append([vv.x / PPI, vv.y / PPI])
	out.terrain.append({"cls": str(piece.get("piece_class", "?")), "cat": TerrainManager.category_of(piece), "pts": pts})
for z in GameState.state.board.deployment_zones:
	var pts = []
	for v in z.get("poly", []):
		pts.append([float(v.get("x", 0)), float(v.get("y", 0))] if v is Dictionary else [v.x, v.y])
	out.zones.append({"p": int(z.get("player", 0)), "pts": pts})
for o in GameState.state.board.objectives:
	var p = o.get("position", Vector2.ZERO)
	out.objectives.append({"id": o.get("id", ""), "x": (p.x if p is Vector2 else p[0]) / PPI, "y": (p.y if p is Vector2 else p[1]) / PPI})
var units = GameState.state.units
for uid in units:
	var u = units[uid]
	var st = int(u.get("status", 0))
	if st == GameStateData.UnitStatus.UNDEPLOYED or st == GameStateData.UnitStatus.IN_RESERVES:
		continue
	var kws = u.get("meta", {}).get("keywords", [])
	var inf = ("INFANTRY" in kws) or ("BEASTS" in kws) or ("SWARM" in kws)
	var hid_all = true
	var any_hidden = false
	var ms = []
	for m in u.get("models", []):
		if not m.get("alive", true) or m.get("position", null) == null:
			continue
		var h = TerrainManager.is_model_hidden(m, u)
		hid_all = hid_all and h
		any_hidden = any_hidden or h
		var p = m.position if m.position is Vector2 else Vector2(m.position.x, m.position.y)
		var bd = m.get("base_dimensions", {})
		ms.append({"x": p.x / PPI, "y": p.y / PPI, "r": float(m.get("base_mm", 32)) / 25.4 / 2.0, "h": h, "bt": str(m.get("base_type", "circular")), "bw": float(bd.get("width", 0)) / PPI if bd is Dictionary else 0.0, "bl": float(bd.get("length", 0)) / PPI if bd is Dictionary else 0.0})
	out.models.append({"uid": uid, "p": int(u.get("owner", 0)), "name": u.get("meta", {}).get("name", uid), "inf": inf, "all_hidden": hid_all and not ms.is_empty(), "any_hidden": any_hidden, "ms": ms})
return out
