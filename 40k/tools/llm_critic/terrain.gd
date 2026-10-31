# LLM critic terrain — execute_script once per game (multiline, no func defs).
# Every terrain piece in board inches (40 px = 1"): footprint polygon,
# height, traits (obscuring, difficult_ground, ...) and who may move through.
var out := []
var to_in := func(v: float) -> float: return snappedf(v / 40.0, 0.1)
for t in TerrainManager.terrain_features:
	var poly := []
	var raw = t.get("polygon", [])
	if raw is PackedVector2Array or raw is Array:
		for p in raw:
			if p is Vector2:
				poly.append([to_in.call(p.x), to_in.call(p.y)])
	var row := {"id": str(t.get("id", "")), "type": str(t.get("type", "")),
		"height_in": t.get("height_inches", t.get("height_category", "")),
		"traits": t.get("traits", [])}
	if not poly.is_empty():
		row["polygon_in"] = poly
	else:
		var pos = t.get("position", [0, 0])
		var size = t.get("size", [0, 0])
		row["center_in"] = [to_in.call(float(pos[0])), to_in.call(float(pos[1]))]
		row["size_in"] = [to_in.call(float(size[0])), to_in.call(float(size[1]))]
		row["rotation"] = t.get("rotation", 0.0)
	var cmt = t.get("can_move_through", {})
	if cmt is Dictionary and not cmt.is_empty():
		row["blocks_movement_for"] = cmt.keys().filter(func(k): return not cmt[k])
	out.append(row)
return out
