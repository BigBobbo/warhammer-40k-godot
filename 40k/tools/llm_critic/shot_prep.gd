# LLM critic screenshot prep — execute_script (multiline, no func defs).
# Run while the game is frozen, right after capture.gd stored the decision in
# tree.root meta "llm_critic_decision". Draws the K-card board overlay for it
# (AISuggestionBoardOverlay: cyan SUGGESTED ring on the actor, red TARGET ring
# + dashed line on targets, ghost bases + GOAL marker for moves), hides every
# top-level UI Control and the fading AI movement trails so the board is
# unobstructed, and fits the camera to MODE ("board" = whole board, "zoom" =
# the actor and its targets). shot_restore.gd undoes all of it.
# Returns the board's on-screen rect and pixels-per-inch so the screenshot can
# be cropped and its pixels mapped back to board inches.
var mode := "__MODE__"
var m = tree.current_scene
var board = m.get_node("BoardRoot")
var decision: Dictionary = tree.root.get_meta("llm_critic_decision", {})
if not tree.root.has_meta("llm_critic_view"):
	tree.root.set_meta("llm_critic_view", [m.view_offset, m.view_zoom])
var hidden: Array = tree.root.get_meta("llm_critic_hidden", [])
for n in tree.root.find_children("*", "Control", true, false):
	if not n.visible or board.is_ancestor_of(n) or n.get_parent() is Control:
		continue
	n.visible = false
	hidden.append(n)
for n in board.find_children("*", "Node2D", true, false):
	if n.visible and n is AIMovementPathVisual:
		n.visible = false
		hidden.append(n)
tree.root.set_meta("llm_critic_hidden", hidden)
m._show_ai_suggestion_overlay(decision)
var ids := []
for k in ["actor_unit_id", "unit_id", "target_unit_id"]:
	if str(decision.get(k, "")) != "" and not (str(decision[k]) in ids):
		ids.append(str(decision[k]))
var payload = decision.get("payload", {})
if payload is Dictionary:
	for t in payload.get("target_unit_ids", []):
		if not (str(t) in ids):
			ids.append(str(t))
for a in decision.get("assignments", []):
	if a is Dictionary and str(a.get("target_unit_id", "")) != "" and not (str(a.target_unit_id) in ids):
		ids.append(str(a.target_unit_id))
var vp: Vector2 = m.get_viewport().get_visible_rect().size
var zoomed := false
if mode == "zoom":
	# Frame the actor, its targets AND the chosen option's board point (a
	# move's destination) — Main.fit_view_to_decision frames units only.
	var pts := []
	for uid in ids:
		var u = GameState.get_unit(uid)
		if typeof(u) != TYPE_DICTIONARY:
			continue
		for mm in u.get("models", []):
			var pos = mm.get("position", null) if mm is Dictionary and mm.get("alive", true) else null
			if pos is Vector2:
				pts.append(pos)
			elif pos is Dictionary and pos.has("x"):
				pts.append(Vector2(float(pos.x), float(pos.y)))
	for rec in AISuggestionTestCases._main_records(decision).slice(0, 1):
		var ci := int(rec.get("chosen_index", -1))
		var cands: Array = rec.get("candidates", [])
		if ci >= 0 and ci < cands.size() and cands[ci].get("pos", null) is Array and cands[ci].pos.size() == 2:
			pts.append(Vector2(float(cands[ci].pos[0]), float(cands[ci].pos[1])))
	if not pts.is_empty():
		var lo: Vector2 = pts[0]
		var hi: Vector2 = pts[0]
		for p in pts:
			lo = Vector2(min(lo.x, p.x), min(lo.y, p.y))
			hi = Vector2(max(hi.x, p.x), max(hi.y, p.y))
		const PAD_PX := 280.0
		var zf: float = min(min(vp.x / (hi.x - lo.x + PAD_PX * 2.0), vp.y / (hi.y - lo.y + PAD_PX * 2.0)), 1.2)
		var center: Vector2 = (lo + hi) * 0.5
		m.camera.position = center
		m.camera.zoom = Vector2(zf, zf)
		m.view_zoom = zf
		m.view_offset = center - vp / (2.0 * zf)
		m.update_view_transform()
		zoomed = true
else:
	m.fit_view_to_board()
var z: float = m.view_zoom
var bw := float(SettingsService.get_board_width_px())
var bh := float(SettingsService.get_board_height_px())
var origin: Vector2 = (Vector2.ZERO - m.view_offset) * z
return {"mode": mode, "zoomed": zoomed, "ids": ids, "viewport": [vp.x, vp.y],
	"board_rect": [origin.x, origin.y, bw * z, bh * z],
	"px_per_inch": z * bw / float(GameState.state.get("board", {}).get("size", {}).get("width", 44)),
	"overlay": m._ai_suggestion_overlay.summary()}
