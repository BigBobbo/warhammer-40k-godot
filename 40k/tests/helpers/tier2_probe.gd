extends RefCounted

# Probe helpers for the tier2_asset_polish scenario. The scenario runner's
# execute_script act evaluates a single Expression (no multi-statement `var`
# blocks), so the tree-walking assertions live here and are invoked as chained
# single expressions, e.g.:
#   ResourceLoader.load("res://tests/helpers/tier2_probe.gd").new().count_marker_trims(main)

func _walk(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while stack.size() > 0:
		var nd = stack.pop_back()
		for c in nd.get_children():
			stack.append(c)
		out.append(nd)
	return out

## Number of ObjectiveVisual nodes whose marker disc rim (marker_trim) exists.
func count_marker_trims(main: Node) -> int:
	var n := 0
	for nd in _walk(main.get_node("BoardRoot")):
		if "marker_trim" in nd and nd.get("marker_trim") != null:
			n += 1
	return n

## Number of ObjectiveVisual nodes with the full disc/emblem/hub set present.
func count_full_marker_discs(main: Node) -> int:
	var n := 0
	for nd in _walk(main.get_node("BoardRoot")):
		if "marker_emblem" in nd and nd.get("marker_emblem") != null \
				and nd.get_node_or_null("ObjectiveMarker/MarkerDisc") != null \
				and nd.get_node_or_null("ObjectiveMarker/MarkerHub") != null:
			n += 1
	return n

## Number of VEHICLE tokens on the board.
func vehicle_token_count(main: Node) -> int:
	var vehicles := 0
	for nd in _walk(main.get_node("BoardRoot")):
		if "_tank_body_tex" in nd and nd.has_method("_get_unit_type"):
			if nd._get_unit_type() == "VEHICLE":
				vehicles += 1
	return vehicles

## True when every VEHICLE token resolved a tank body sprite.
func all_vehicles_have_tank_sprite(main: Node) -> bool:
	var vehicles := 0
	for nd in _walk(main.get_node("BoardRoot")):
		if "_tank_body_tex" in nd and nd.has_method("_get_unit_type") and nd.has_method("_get_tank_body_texture"):
			if nd._get_unit_type() == "VEHICLE":
				vehicles += 1
				if nd._get_tank_body_texture() == null:
					return false
	return vehicles > 0

## Number of scatter Sprite2D nodes textured from the imported tilepack.
func count_tilepack_scatter(main: Node) -> int:
	var n := 0
	for nd in _walk(main.get_node("BoardRoot")):
		if nd is Sprite2D and nd.texture != null and str(nd.texture.resource_path).contains("assets/tilepack"):
			n += 1
	return n

## Spawn a casualty explosion and return how many DeathExplosion sprites exist.
func trigger_explosion_count(main: Node, x: float, y: float) -> int:
	var dfb = main.get_node("BoardRoot/DamageFeedbackVisual")
	dfb.play_death_animation(Vector2(x, y), 45.0)
	var n := 0
	for c in dfb.get_children():
		if c is Sprite2D and str(c.name) == "DeathExplosion":
			n += 1
	return n
