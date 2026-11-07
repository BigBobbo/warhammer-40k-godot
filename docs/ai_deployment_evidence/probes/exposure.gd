var PPI = 40.0
var t0 = Time.get_ticks_msec()
var zpoly = {}
for z in GameState.state.board.deployment_zones:
	var pts = PackedVector2Array()
	for v in z.get("poly", []):
		pts.append(Vector2(float(v.get("x", 0)) * PPI, float(v.get("y", 0)) * PPI) if v is Dictionary else Vector2(v.x * PPI, v.y * PPI))
	zpoly[int(z.get("player", 0))] = pts
var me = 1
var en = 2
# observer sample points: anywhere an enemy model could stand after a turn-1 move of up to 10" from its zone
var obs = []
var ostep = 3.0 * PPI
var oy = ostep / 2.0
while oy < 60 * PPI:
	var ox = ostep / 2.0
	while ox < 44 * PPI:
		var p = Vector2(ox, oy)
		var d = INF
		var ez = zpoly[en]
		if Geometry2D.is_point_in_polygon(p, ez):
			d = 0.0
		else:
			for i in range(ez.size()):
				d = min(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, ez[i], ez[(i + 1) % ez.size()])))
		if d <= 10.0 * PPI and not Geometry2D.is_point_in_polygon(p, zpoly[me]):
			obs.append({"position": p, "base_mm": 32})
		ox += ostep
	oy += ostep
var cells = []
var step = 2.0 * PPI
var y = step / 2.0
var checks = 0
while y < 60 * PPI:
	var x = step / 2.0
	while x < 44 * PPI:
		var p = Vector2(x, y)
		if Geometry2D.is_point_in_polygon(p, zpoly[me]):
			var probe = {"position": p, "base_mm": 32}
			var seen = 0
			var seen15 = 0
			var nearest = INF
			for o in obs:
				var dd = o.position.distance_to(p) / PPI
				nearest = min(nearest, dd)
				checks += 1
				if TerrainManager.model_visible_11e(o, probe):
					seen += 1
					if dd <= 15.0:
						seen15 += 1
			var area = TerrainManager.area_at(p)
			var dense = false
			if area is Dictionary and not area.is_empty():
				dense = TerrainManager.category_of(area) == "dense"
			cells.append([snapped(x / PPI, 0.1), snapped(y / PPI, 0.1), seen, seen15, dense, snapped(nearest, 0.1)])
		x += step
	y += step
var obs_in = []
for o in obs:
	obs_in.append([snapped(o.position.x / PPI, 0.1), snapped(o.position.y / PPI, 0.1)])
return {"ms": Time.get_ticks_msec() - t0, "observers": obs.size(), "obs": obs_in, "cells": cells, "checks": checks}
