var PPI = 40.0
var vm = load("res://scripts/VisionMapOverlay.gd").new()
tree.root.add_child(vm)
vm._prepare_terrain()
var pieces = vm._pieces
var memb = func(p: Vector2) -> Array:
	var g = {}
	var f = {}
	for pc in pieces:
		if not pc.bbox.has_point(p):
			continue
		if Geometry2D.is_point_in_polygon(p, pc.polygon):
			if pc.pclass != "feature":
				g[pc.group_key] = true
			else:
				f[pc.id] = true
	return [g, f]
var zpoly = {}
for z in GameState.state.board.deployment_zones:
	var pts = PackedVector2Array()
	for v in z.get("poly", []):
		pts.append(Vector2(float(v.get("x", 0)) * PPI, float(v.get("y", 0)) * PPI) if v is Dictionary else Vector2(v.x * PPI, v.y * PPI))
	zpoly[int(z.get("player", 0))] = pts
var obs = []
var ostep = 3.0 * PPI
var oy = ostep / 2.0
while oy < 60 * PPI:
	var ox = ostep / 2.0
	while ox < 44 * PPI:
		var p = Vector2(ox, oy)
		var d = INF
		var ez = zpoly[2]
		if Geometry2D.is_point_in_polygon(p, ez):
			d = 0.0
		else:
			for i in range(ez.size()):
				d = min(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, ez[i], ez[(i + 1) % ez.size()])))
		if d <= 10.0 * PPI and not Geometry2D.is_point_in_polygon(p, zpoly[1]):
			var m = memb.call(p)
			obs.append({"p": p, "g": m[0], "f": m[1]})
		ox += ostep
	oy += ostep
var t0 = Time.get_ticks_usec()
var checks = 0
var shadow = 0
var cells = 0
var step = 2.0 * PPI
var y = step / 2.0
while y < 60 * PPI:
	var x = step / 2.0
	while x < 44 * PPI:
		var c = Vector2(x, y)
		if Geometry2D.is_point_in_polygon(c, zpoly[1]):
			cells += 1
			var m = memb.call(c)
			var seen = 0
			for o in obs:
				checks += 1
				if not vm._line_blocked_11e_fast(o.p, c, o.g, m[0], o.f, m[1], true):
					seen += 1
			if seen == 0:
				shadow += 1
		x += step
	y += step
var us = Time.get_ticks_usec() - t0
vm.queue_free()
return {"cells": cells, "observers": obs.size(), "checks": checks, "ms": us / 1000.0, "us_per_line": float(us) / max(1, checks), "shadow_cells_centre_line": shadow}
