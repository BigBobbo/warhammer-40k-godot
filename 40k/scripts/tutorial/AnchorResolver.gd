extends RefCounted
class_name TutorialAnchorResolver

# Resolves a lesson step's "anchor" spec to a screen-space rect the overlay can
# spotlight (PRPs/tutorial_system.md §5.1). The four selector kinds mirror the
# scenario runner's proven resolvers (ScenarioRunner._find_unit_token /
# _find_visible_button_by_text / _node2d_to_screen) so lesson authors and
# scenario authors share one vocabulary:
#
#   {"unit": "U_BOYZ_T"}            -> board token by unit id
#   {"node": "/root/Main/..."}      -> absolute NodePath (Control or Node2D)
#   {"button_text": "Confirm Move"} -> first visible enabled Button with text
#   {"board": [x, y]}               -> board-px point via world_to_screen
#
# Returns {"ok": bool, "rect": Rect2 (screen px), "node": Node|null}.

const TOKEN_HALF_EXTENT := 40.0
const POINT_HALF_EXTENT := 26.0


static func resolve(anchor: Dictionary, tree: SceneTree) -> Dictionary:
	if anchor.is_empty() or tree == null:
		return {"ok": false, "rect": Rect2(), "node": null}
	if anchor.has("unit"):
		var token := find_unit_token(str(anchor.unit), tree)
		if token == null:
			return {"ok": false, "rect": Rect2(), "node": null}
		return {"ok": true, "rect": rect_for_node(token, tree), "node": token}
	if anchor.has("node"):
		var n := tree.root.get_node_or_null(NodePath(str(anchor.node)))
		if n == null or (n is CanvasItem and not (n as CanvasItem).is_visible_in_tree()):
			# CanvasLayer autoloads (e.g. PadHintBar) are not CanvasItems —
			# anchor their first Control child instead.
			if n is CanvasLayer:
				var c := _first_control_child(n)
				if c != null and c.is_visible_in_tree():
					return {"ok": true, "rect": rect_for_node(c, tree), "node": c}
			return {"ok": false, "rect": Rect2(), "node": null}
		if n is CanvasLayer:
			var c2 := _first_control_child(n)
			if c2 != null and c2.is_visible_in_tree():
				return {"ok": true, "rect": rect_for_node(c2, tree), "node": c2}
			return {"ok": false, "rect": Rect2(), "node": null}
		return {"ok": true, "rect": rect_for_node(n, tree), "node": n}
	if anchor.has("button_text"):
		var b := find_visible_button_by_text(str(anchor.button_text), tree)
		if b == null:
			return {"ok": false, "rect": Rect2(), "node": null}
		return {"ok": true, "rect": rect_for_node(b, tree), "node": b}
	if anchor.has("board"):
		var arr = anchor.board
		if typeof(arr) == TYPE_ARRAY and arr.size() >= 2:
			var p := world_to_screen(Vector2(float(arr[0]), float(arr[1])), tree)
			if p != Vector2.INF:
				return {"ok": true,
					"rect": Rect2(p - Vector2.ONE * POINT_HALF_EXTENT, Vector2.ONE * POINT_HALF_EXTENT * 2.0),
					"node": null}
		return {"ok": false, "rect": Rect2(), "node": null}
	return {"ok": false, "rect": Rect2(), "node": null}


# Screen rect for an already-resolved node (cheap per-frame refresh path).
static func rect_for_node(n: Node, tree: SceneTree) -> Rect2:
	if n is Control:
		return (n as Control).get_global_rect()
	if n is Node2D:
		var center := node2d_to_screen(n as Node2D, tree)
		if center == Vector2.INF:
			return Rect2()
		return Rect2(center - Vector2.ONE * TOKEN_HALF_EXTENT, Vector2.ONE * TOKEN_HALF_EXTENT * 2.0)
	return Rect2()


static func find_unit_token(unit_id: String, tree: SceneTree) -> Node2D:
	for r in [tree.current_scene, tree.root]:
		if r == null:
			continue
		var found := _search_node_by_unit_id(r, unit_id)
		if found:
			return found
	return null


static func _search_node_by_unit_id(node: Node, unit_id: String) -> Node2D:
	if node is Node2D:
		var n2d := node as Node2D
		if n2d.name == unit_id:
			return n2d
		if "unit_id" in n2d and str(n2d.get("unit_id")) == unit_id:
			return n2d
		if n2d.has_meta("unit_id") and str(n2d.get_meta("unit_id")) == unit_id:
			return n2d
	for child in node.get_children():
		var found := _search_node_by_unit_id(child, unit_id)
		if found:
			return found
	return null


static func find_visible_button_by_text(wanted: String, tree: SceneTree) -> Button:
	var queue: Array = [tree.root]
	while not queue.is_empty():
		var n: Node = queue.pop_front()
		if n is Button and n.visible and n.is_visible_in_tree() and not n.disabled \
				and str(n.text).strip_edges() == wanted:
			return n
		for child in n.get_children(true):
			queue.append(child)
	return null


# Board px -> screen px through the scene's own lens (the same projection the
# scenario runner uses: Main.world_to_screen_position for board space).
static func world_to_screen(world_pos: Vector2, tree: SceneTree) -> Vector2:
	var scene := tree.current_scene
	if scene != null and scene.has_method("world_to_screen_position"):
		return scene.world_to_screen_position(world_pos)
	return Vector2.INF


static func node2d_to_screen(node: Node2D, tree: SceneTree) -> Vector2:
	var scene := tree.current_scene
	if scene != null and scene.has_method("world_to_screen_position"):
		var parent := node.get_parent()
		if parent != null and str(parent.name) == "TokenLayer":
			return scene.world_to_screen_position(node.position)
	var viewport := node.get_viewport()
	if viewport == null:
		return Vector2.INF
	return viewport.get_canvas_transform() * node.global_position


static func _first_control_child(n: Node) -> Control:
	for child in n.get_children():
		if child is Control:
			return child
	return null
