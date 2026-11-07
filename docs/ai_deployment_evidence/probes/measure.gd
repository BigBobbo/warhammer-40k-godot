var PPI = 40.0
var units = GameState.state.get("units", {})
var zones = GameState.state.get("board", {}).get("deployment_zones", [])
var zpoly = {}
for z in zones:
	var pts = PackedVector2Array()
	for v in z.get("poly", []):
		pts.append(Vector2(float(v.get("x", 0)) * PPI, float(v.get("y", 0)) * PPI) if v is Dictionary else Vector2(v.x * PPI, v.y * PPI))
	zpoly[int(z.get("player", 0))] = pts
var rows = []
var by_owner = {1: [], 2: []}
for uid in units:
	var u = units[uid]
	var st = int(u.get("status", 0))
	if st == GameStateData.UnitStatus.UNDEPLOYED or st == GameStateData.UnitStatus.IN_RESERVES:
		continue
	by_owner[int(u.get("owner", 0))].append(uid)
for uid in units:
	var u = units[uid]
	var owner = int(u.get("owner", 0))
	var st = int(u.get("status", 0))
	var kws = u.get("meta", {}).get("keywords", [])
	var row = {"id": uid, "p": owner, "name": u.get("meta", {}).get("name", uid), "pts": int(u.get("meta", {}).get("points", 0))}
	if st == GameStateData.UnitStatus.IN_RESERVES:
		row["status"] = "RESERVES"
		rows.append(row)
		continue
	if st == GameStateData.UnitStatus.UNDEPLOYED:
		row["status"] = "UNDEPLOYED"
		rows.append(row)
		continue
	if u.get("embarked_in", null) != null and str(u.get("embarked_in", "")) != "":
		row["status"] = "EMBARKED"
		rows.append(row)
		continue
	row["role"] = AIDecisionMaker._classify_deployment_role(u)
	row["inf"] = ("INFANTRY" in kws) or ("BEASTS" in kws) or ("SWARM" in kws)
	var alive = []
	for m in u.get("models", []):
		if m.get("alive", true) and m.get("position", null) != null:
			alive.append(m)
	if alive.is_empty():
		continue
	var c = Vector2.ZERO
	var in_area = 0
	var in_dense = 0
	var hidden = 0
	for m in alive:
		var p = m.position if m.position is Vector2 else Vector2(m.position.x, m.position.y)
		c += p
		var within = TerrainManager.pieces_model_within(m)
		if not within.is_empty():
			in_area += 1
			for piece in within:
				if TerrainManager.category_of(piece) == "dense":
					in_dense += 1
					break
		if TerrainManager.is_model_hidden(m, u):
			hidden += 1
	c /= alive.size()
	row["c_in"] = [snapped(c.x / PPI, 0.1), snapped(c.y / PPI, 0.1)]
	row["models"] = alive.size()
	row["in_area"] = in_area
	row["in_dense"] = in_dense
	row["hidden"] = hidden
	# distance to the enemy deployment zone (closest model to closest zone edge) in inches
	var enemy = 3 - owner
	var ez = zpoly.get(enemy, PackedVector2Array())
	var dmin = INF
	if ez.size() >= 3:
		for m in alive:
			var p = m.position if m.position is Vector2 else Vector2(m.position.x, m.position.y)
			for i in range(ez.size()):
				var a = ez[i]
				var b = ez[(i + 1) % ez.size()]
				var q = Geometry2D.get_closest_point_to_segment(p, a, b)
				dmin = min(dmin, p.distance_to(q))
	row["to_enemy_dz_in"] = snapped(dmin / PPI, 0.1)
	# how many deployed enemy units can see (visible incl. hidden gate) at least one model of this unit
	var seers = []
	var nearest = INF
	for euid in by_owner.get(enemy, []):
		var eu = units[euid]
		var sees = false
		for em in eu.get("models", []):
			if not em.get("alive", true) or em.get("position", null) == null:
				continue
			for m in alive:
				var d = Measurement.model_to_model_distance_px(em, m) / PPI
				nearest = min(nearest, d)
				if sees:
					continue
				if TerrainManager.model_visible_11e(em, m) and TerrainManager.hidden_model_visible_to(m, u, em):
					sees = true
		if sees:
			seers.append(eu.get("meta", {}).get("name", euid))
	row["seen_by"] = seers.size()
	row["nearest_enemy_in"] = snapped(nearest, 0.1)
	rows.append(row)
return {"rows": rows, "zones": zones.size(), "layout": GameState.state.get("board", {}).get("terrain_layout", "?")}
