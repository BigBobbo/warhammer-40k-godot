extends "res://addons/gut/test.gd"

# Every 11e terrain layout's home objectives must sit in their owner's
# deployment zone: obj_home_1 (zone "player1") inside player 1's zone and
# obj_home_2 (zone "player2") inside player 2's, for the layout's recommended
# deployment.
#
# Regression: the layout generator tagged the TOP-most home marker "player1".
# On Dawn of War / Sweeping Engagement (left/right zones) that labelled each
# player's home as the opponent's in 14 layouts, so primary cards that exclude
# or pay for "home" scored the wrong objective and the AI read its own empty
# home as the enemy's (no "home undefended" weight) — e.g. Purge the Foe vs
# Take and Hold variant 1.

const LAYOUT_DIR := "res://terrain_layouts/"

func _layout_files() -> Array:
	var out: Array = []
	var dir := DirAccess.open(LAYOUT_DIR)
	assert_not_null(dir, "terrain_layouts dir must open")
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json") and f != "index_11e.json":
			out.append(f)
	out.sort()
	return out

func _zone_poly(deployment: String, player: int) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for z in DeploymentZoneData.get_zones(deployment):
		if int(z.get("player", 0)) == player:
			for p in z.get("poly", []):
				poly.append(Vector2(float(p.x), float(p.y)))
	return poly

func test_home_objectives_sit_in_their_owners_zone():
	var checked := 0
	var bad: Array = []
	for f in _layout_files():
		var data = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_DIR + f))
		if not data is Dictionary:
			continue
		var deps: Array = data.get("recommended_deployments", [])
		if deps.is_empty():
			continue
		var dep := str(deps[0])
		for o in data.get("objectives", []):
			var zone := str(o.get("zone", ""))
			if not zone in ["player1", "player2"]:
				continue
			var owner := int(zone.substr(6))
			var pos := Vector2(float(o.position[0]), float(o.position[1]))
			checked += 1
			if not Geometry2D.is_point_in_polygon(pos, _zone_poly(dep, owner)):
				bad.append("%s (%s): %s zone=%s at %s" % [f, dep, o.get("id", "?"), zone, pos])
	print("test_layout_home_objective_zones: checked %d home markers, %d misplaced" % [checked, bad.size()])
	for b in bad:
		print("  MISPLACED ", b)
	assert_gt(checked, 0, "some home markers were checked")
	assert_eq(bad.size(), 0, "home markers outside their owner's zone: %s" % ", ".join(bad))

func test_home_ids_match_zone_owner():
	# obj_home_1 is player 1's home, obj_home_2 player 2's, in every layout.
	for f in _layout_files():
		var data = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_DIR + f))
		if not data is Dictionary:
			continue
		for o in data.get("objectives", []):
			var oid := str(o.get("id", ""))
			if oid == "obj_home_1":
				assert_eq(str(o.get("zone", "")), "player1", "%s obj_home_1 zone" % f)
			elif oid == "obj_home_2":
				assert_eq(str(o.get("zone", "")), "player2", "%s obj_home_2 zone" % f)
