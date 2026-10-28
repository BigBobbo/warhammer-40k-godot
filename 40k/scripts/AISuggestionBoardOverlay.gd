extends Node2D
class_name AISuggestionBoardOverlay

# AISuggestionBoardOverlay — the board half of the AI suggestion card (K).
#
# The breakdown card says "Boyz advance toward OBJ_3" or "Shoot Intercessors";
# this overlay shows WHICH unit and WHERE, on the board:
#
#   * a cyan ring round every model of the unit the suggestion is about, with a
#     "SUGGESTED" tag over it
#   * a red ring round every unit it targets (shooting / charge / fight /
#     stratagem target), with a "TARGET" tag and a dashed line from the actor
#   * for moves (normal / advance / fall back / scout / deploy): a dashed line
#     with an arrowhead from each model to its planned end point, and a
#     translucent "ghost" base (real base shape) at that end point
#   * for a move, the point the AI is heading for (the chosen option's board
#     position, e.g. the objective) as a cyan "GOAL" marker
#   * hovering an option in the card previews THAT option instead (amber):
#     its target unit ringed, or a dashed line to the point it was about
#
# Line widths, tags and the unit hull ring scale with the camera zoom so the
# marks stay readable on a zoomed-out board.
#
# Persistent while the card is open — unlike AIMovementPathVisual (fades after
# 2.5s). Main clears it when the card closes, the phase changes or an action
# lands (the drawn positions would be stale).
#
# Everything is resolved from live GameState when show_suggestion() is called;
# the drawn data is kept in plain dictionaries so tests can read it back.
#
# Public API:
#   show_suggestion(decision: Dictionary)
#   preview_candidate(record: Dictionary, cand_index: int, chosen: bool)
#   clear_preview()
#   clear()
#   summary() -> Dictionary   ({actors, targets, moves, preview} counts / ids)

const ACTOR_COLOR := Color(0.6, 0.9, 1.0, 0.95)      # cyan — matches the Suggest button
const TARGET_COLOR := Color(1.0, 0.35, 0.3, 0.95)
const PREVIEW_COLOR := Color(1.0, 0.75, 0.3, 0.95)    # amber — "the option you're hovering"
const GHOST_FILL_ALPHA := 0.4
const RING_WIDTH := 3.0
const RING_PAD := 5.0
const LINE_WIDTH := 2.5
const GLOW_WIDTH := 7.0
const DASH_LENGTH := 10.0
const GAP_LENGTH := 7.0
const ARROW_HEAD_SIZE := 12.0
const ARROW_HEAD_ANGLE := 0.45
const TAG_FONT_SIZE := 15
const TAG_OFFSET_Y := -44.0
const PULSE_SPEED := 1.6

# Keys a decision uses to name the unit doing the thing / the unit it targets.
const ACTOR_KEYS := ["actor_unit_id", "unit_id", "shooter_id", "charger_id", "attacker_id"]
const TARGET_KEYS := ["target_unit_id", "target_id", "defender_id"]
const TARGET_LIST_KEYS := ["target_unit_ids", "target_ids"]

# {unit_id: {name, models: [{pos, shape, rot}], centroid}}
var _actors: Dictionary = {}
var _targets: Dictionary = {}
# [{from: Vector2, to: Vector2, shape: BaseShape, rot: float}]
var _moves: Array = []
# {} or {unit_id?, unit: {...}, point?: Vector2, from: Vector2, label}
var _preview: Dictionary = {}
# {} or {point: Vector2, label: String} — where a suggested move is heading
var _goal: Dictionary = {}
var _pulse_time := 0.0
# Screen-constant scale factor for the current _draw (1 / camera zoom, >= 1)
var _k := 1.0


func _ready() -> void:
	# Above tokens (10), AI trails (11) and shooting lines (12); same layer as
	# the intent badges.
	z_index = 14


func _process(delta: float) -> void:
	if _is_empty():
		return
	_pulse_time += delta
	queue_redraw()


func show_suggestion(decision: Dictionary) -> void:
	_actors = {}
	_targets = {}
	_moves = []
	_preview = {}
	_goal = {}
	if decision.is_empty():
		queue_redraw()
		return

	var actor_ids := _collect_ids(decision, ACTOR_KEYS, [])
	var target_ids := _collect_ids(decision, TARGET_KEYS, TARGET_LIST_KEYS)
	# Records name the unit each sub-decision was about (e.g. a shooting
	# record per weapon) and the target the chosen candidate picked.
	for rec in decision.get("_ai_decision_records", []):
		if not (rec is Dictionary):
			continue
		var rid := str(rec.get("unit_id", ""))
		if rid != "" and not actor_ids.has(rid) and actor_ids.is_empty():
			actor_ids.append(rid)
		var cands: Array = rec.get("candidates", [])
		var ci := int(rec.get("chosen_index", -1))
		if ci >= 0 and ci < cands.size() and cands[ci] is Dictionary:
			var tid := str(cands[ci].get("target_unit_id", ""))
			if tid != "" and not target_ids.has(tid):
				target_ids.append(tid)

	for uid in actor_ids:
		var info := _unit_info(uid)
		if not info.is_empty():
			_actors[uid] = info
	for uid in target_ids:
		if _actors.has(uid):
			continue  # e.g. a stratagem "target" that is the acting unit itself
		var info := _unit_info(uid)
		if not info.is_empty():
			_targets[uid] = info

	_collect_moves(decision)
	if not _moves.is_empty():
		_goal = _chosen_point(decision)
	print("[AISuggestionBoardOverlay] Showing: actors=%s targets=%s moves=%d goal=%s" % [
		str(_actors.keys()), str(_targets.keys()), _moves.size(), str(_goal.get("point", "-"))])
	DebugLogger.info("AISuggestionBoardOverlay shown", summary())
	queue_redraw()


func preview_candidate(record: Dictionary, cand_index: int, chosen: bool = false) -> void:
	"""Hovering an option in the card: show what THAT option was about."""
	_preview = {}
	var cands: Array = record.get("candidates", [])
	if cand_index < 0 or cand_index >= cands.size() or not (cands[cand_index] is Dictionary):
		queue_redraw()
		return
	var cand: Dictionary = cands[cand_index]
	var from := Vector2.INF
	var rid := str(record.get("unit_id", ""))
	var r_info := _unit_info(rid)
	if not r_info.is_empty():
		from = r_info.centroid
	else:
		var up = record.get("context", {}).get("unit_pos", [])
		if up is Array and up.size() == 2:
			from = Vector2(float(up[0]), float(up[1]))
	var label := str(cand.get("description", ""))
	var tid := str(cand.get("target_unit_id", ""))
	var t_info := _unit_info(tid) if tid != "" else {}
	if not t_info.is_empty():
		_preview = {"unit_id": tid, "unit": t_info, "point": t_info.centroid, "from": from, "label": label, "chosen": chosen}
	else:
		var pos = cand.get("pos", [])
		if pos is Array and pos.size() == 2:
			_preview = {"point": Vector2(float(pos[0]), float(pos[1])), "from": from, "label": label, "chosen": chosen}
	if not _preview.is_empty():
		print("[AISuggestionBoardOverlay] Preview option '%s' (target=%s)" % [label, tid])
	queue_redraw()


func clear_preview() -> void:
	if _preview.is_empty():
		return
	_preview = {}
	queue_redraw()


func clear() -> void:
	if _is_empty():
		return
	_actors = {}
	_targets = {}
	_moves = []
	_preview = {}
	_goal = {}
	print("[AISuggestionBoardOverlay] Cleared")
	queue_redraw()


func summary() -> Dictionary:
	return {
		"actors": _actors.keys(),
		"targets": _targets.keys(),
		"moves": _moves.size(),
		"preview": str(_preview.get("label", "")),
		"preview_unit": str(_preview.get("unit_id", "")),
		"goal": str(_goal.get("label", "")),
	}


func _is_empty() -> bool:
	return _actors.is_empty() and _targets.is_empty() and _moves.is_empty() and _preview.is_empty() and _goal.is_empty()


# ---------------------------------------------------------------------------
# Resolving the decision against GameState
# ---------------------------------------------------------------------------

func _collect_ids(decision: Dictionary, keys: Array, list_keys: Array) -> Array:
	var out: Array = []
	var sources: Array = [decision]
	if decision.get("payload", null) is Dictionary:
		sources.append(decision.payload)
		var asg = decision.payload.get("assignments", null)
		if asg is Array:
			sources.append_array(asg.filter(func(x): return x is Dictionary))
	if decision.get("assignments", null) is Array:
		sources.append_array(decision.assignments.filter(func(x): return x is Dictionary))
	for src in sources:
		for k in keys:
			var v := str(src.get(k, ""))
			if v != "" and not out.has(v) and GameState.state.get("units", {}).has(v):
				out.append(v)
		for k in list_keys:
			var lst = src.get(k, null)
			if lst is Array:
				for v in lst:
					var s := str(v)
					if s != "" and not out.has(s) and GameState.state.get("units", {}).has(s):
						out.append(s)
	return out


func _unit_info(unit_id: String) -> Dictionary:
	if unit_id == "":
		return {}
	var unit: Dictionary = GameState.get_unit(unit_id)
	if unit.is_empty():
		return {}
	var models: Array = []
	var sum := Vector2.ZERO
	for m in unit.get("models", []):
		if not m.get("alive", true):
			continue
		var p = _to_vec(m.get("position", null))
		if p == Vector2.INF:
			continue
		models.append({"pos": p, "shape": Measurement.create_base_shape(m), "rot": float(m.get("rotation", 0.0))})
		sum += p
	if models.is_empty():
		return {}
	return {
		"name": str(unit.get("meta", {}).get("name", unit_id)),
		"models": models,
		"centroid": sum / models.size(),
		"owner": int(unit.get("owner", 1)),
	}


func _collect_moves(decision: Dictionary) -> void:
	var uid := str(decision.get("actor_unit_id", decision.get("unit_id", "")))
	var unit: Dictionary = GameState.get_unit(uid) if uid != "" else {}
	if unit.is_empty():
		return
	var models: Array = unit.get("models", [])
	var dests = decision.get("_ai_model_destinations", decision.get("_ai_scout_destinations", null))
	if dests is Dictionary:
		var wps: Dictionary = decision.get("_ai_model_waypoints", {})
		for m in models:
			var mid := str(m.get("id", ""))
			if not m.get("alive", true) or not dests.has(mid):
				continue
			_add_move(m, _to_vec(dests[mid]), float(m.get("rotation", 0.0)), _to_vec(wps.get(mid, null)))
		return
	# Deployment: positions are a list aligned with the unit's models.
	var positions = decision.get("model_positions", null)
	if positions is Array:
		var rots = decision.get("model_rotations", [])
		for i in range(mini(positions.size(), models.size())):
			var rot := float(rots[i]) if rots is Array and i < rots.size() and rots[i] != null else 0.0
			_add_move(models[i], _to_vec(positions[i]), rot)


func _chosen_point(decision: Dictionary) -> Dictionary:
	"""Board position of the first record's chosen option (a move's objective)."""
	for rec in decision.get("_ai_decision_records", []):
		if not (rec is Dictionary):
			continue
		var cands: Array = rec.get("candidates", [])
		var ci := int(rec.get("chosen_index", -1))
		if ci < 0 or ci >= cands.size() or not (cands[ci] is Dictionary):
			continue
		var p := _to_vec(cands[ci].get("pos", null))
		if p != Vector2.INF:
			return {"point": p, "label": str(cands[ci].get("description", ""))}
	return {}


func _add_move(model: Dictionary, to: Vector2, rot: float, via: Vector2 = Vector2.INF) -> void:
	"""`via` = TWO-LEG waypoint (the move bends there around solid terrain)."""
	if to == Vector2.INF:
		return
	var from := _to_vec(model.get("position", null))  # INF while in reserves / undeployed
	_moves.append({"from": from, "to": to, "via": via, "shape": Measurement.create_base_shape(model), "rot": rot})


static func _to_vec(v) -> Vector2:
	if v is Vector2:
		return v
	if v is Dictionary and v.has("x") and v.has("y"):
		return Vector2(float(v.x), float(v.y))
	if v is Array and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.INF


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	_k = clampf(1.0 / maxf(get_global_transform_with_canvas().get_scale().x, 0.01), 1.0, 6.0)
	var pulse := 0.75 + 0.25 * sin(_pulse_time * PULSE_SPEED * TAU)
	var dim := 0.35 if not _preview.is_empty() else 1.0  # the hovered option takes focus

	# Move paths + ghosts at the destination
	for mv in _moves:
		var col := Color(ACTOR_COLOR, ACTOR_COLOR.a * dim)
		if mv.from != Vector2.INF and mv.from.distance_to(mv.to) > 1.0:
			# A dogleg is drawn as its two legs; the arrow follows the last one
			var leg_from: Vector2 = mv.from
			if mv.via != Vector2.INF:
				_draw_dashed_line(mv.from, mv.via, Color(col, col.a * 0.25), GLOW_WIDTH)
				_draw_dashed_line(mv.from, mv.via, col, LINE_WIDTH)
				leg_from = mv.via
			_draw_dashed_line(leg_from, mv.to, Color(col, col.a * 0.25), GLOW_WIDTH)
			_draw_dashed_line(leg_from, mv.to, col, LINE_WIDTH)
			var tip: Vector2 = mv.shape.get_closest_edge_point(leg_from, mv.to, mv.rot) if mv.shape else mv.to
			_draw_arrowhead(tip, (mv.to - leg_from).normalized(), col)
		if mv.shape:
			mv.shape.draw(self, mv.to, mv.rot, Color(ACTOR_COLOR, GHOST_FILL_ALPHA * pulse * dim),
				col, 2.0 * _k)

	# Where the move is heading
	if not _goal.is_empty():
		var gc := Color(ACTOR_COLOR, ACTOR_COLOR.a * dim)
		var gp: Vector2 = _goal.point
		var lead := _moves_centroid()
		if lead != Vector2.INF and lead.distance_to(gp) > 30.0 * _k:
			_draw_dashed_line(lead, gp, Color(gc, gc.a * 0.45), LINE_WIDTH * 0.7)
		draw_arc(gp, 16.0 * _k, 0, TAU, 32, gc, RING_WIDTH * _k, true)
		draw_line(gp - Vector2(10, 0) * _k, gp + Vector2(10, 0) * _k, gc, 2.0 * _k, true)
		draw_line(gp - Vector2(0, 10) * _k, gp + Vector2(0, 10) * _k, gc, 2.0 * _k, true)
		_draw_tag(gp, "GOAL: " + _short(str(_goal.label)), Color(gc, maxf(dim, 0.6)))

	# Actor → target links
	for aid in _actors:
		for tid in _targets:
			var c := Color(TARGET_COLOR, 0.85 * dim)
			_draw_dashed_line(_actors[aid].centroid, _targets[tid].centroid, c, LINE_WIDTH)
			_draw_arrowhead(_targets[tid].centroid, (_targets[tid].centroid - _actors[aid].centroid).normalized(), c)

	for aid in _actors:
		_draw_unit_rings(_actors[aid], Color(ACTOR_COLOR, ACTOR_COLOR.a * dim), pulse)
	for tid in _targets:
		_draw_unit_rings(_targets[tid], Color(TARGET_COLOR, TARGET_COLOR.a * dim), pulse)
	for aid in _actors:
		_draw_tag(_actors[aid].centroid, "SUGGESTED: %s" % _actors[aid].name, Color(ACTOR_COLOR, maxf(dim, 0.6)))
	for tid in _targets:
		_draw_tag(_targets[tid].centroid, "TARGET: %s" % _targets[tid].name, Color(TARGET_COLOR, maxf(dim, 0.6)))

	# Hovered option
	if not _preview.is_empty():
		var pc := PREVIEW_COLOR
		var point: Vector2 = _preview.get("point", Vector2.INF)
		var from: Vector2 = _preview.get("from", Vector2.INF)
		if from != Vector2.INF and point != Vector2.INF and from.distance_to(point) > 1.0:
			_draw_dashed_line(from, point, Color(pc, 0.3), GLOW_WIDTH)
			_draw_dashed_line(from, point, pc, LINE_WIDTH)
			_draw_arrowhead(point, (point - from).normalized(), pc)
		if _preview.has("unit"):
			_draw_unit_rings(_preview.unit, pc, 1.0)
		elif point != Vector2.INF:
			draw_arc(point, 18.0 * _k, 0, TAU, 32, pc, RING_WIDTH * _k, true)
			draw_circle(point, 4.0 * _k, pc)
		if point != Vector2.INF:
			var lbl := ("PICKED: " if _preview.get("chosen", false) else "OPTION: ") + _short(str(_preview.get("label", "")))
			_draw_tag(point, lbl, pc)


func _draw_unit_rings(info: Dictionary, color: Color, pulse: float) -> void:
	# A hull ring round the whole unit (visible even zoomed out) …
	var hull := 0.0
	for m in info.models:
		hull = maxf(hull, (m.pos as Vector2).distance_to(info.centroid) + _base_radius(m.shape))
	hull += RING_PAD * 2.0 * _k
	draw_arc(info.centroid, hull, 0, TAU, 64, Color(color, color.a * 0.25), (RING_WIDTH + 4.0) * _k, true)
	draw_arc(info.centroid, hull, 0, TAU, 64, Color(color, color.a * pulse), RING_WIDTH * _k, true)
	# … and a ring per model so it is clear exactly which tokens are meant.
	for m in info.models:
		var r := _base_radius(m.shape) + RING_PAD
		draw_arc(m.pos, r, 0, TAU, 40, Color(color, color.a * pulse), RING_WIDTH, true)


func _moves_centroid() -> Vector2:
	if _moves.is_empty():
		return Vector2.INF
	var sum := Vector2.ZERO
	for mv in _moves:
		sum += mv.to
	return sum / _moves.size()


static func _base_radius(shape) -> float:
	if shape == null:
		return 20.0
	var b: Rect2 = shape.get_bounds()
	return maxf(b.size.x, b.size.y) * 0.5


static func _short(label: String) -> String:
	"""Option descriptions carry a '(reason …)' tail the card already shows."""
	var cut := label.find(" (")
	return label.substr(0, cut) if cut > 0 else label


func _draw_tag(at: Vector2, text: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	if text.length() > 48:
		text = text.substr(0, 47) + "…"
	var fs := roundi(TAG_FONT_SIZE * _k)
	var pad := 8.0 * _k
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var rect := Rect2(at + Vector2(-ts.x * 0.5 - pad, TAG_OFFSET_Y * _k - ts.y * 0.5 - pad * 0.5), Vector2(ts.x + pad * 2.0, ts.y + pad))
	draw_rect(rect, Color(0.07, 0.065, 0.05, 0.9), true)
	draw_rect(rect, color, false, 2.0 * _k)
	draw_string(font, Vector2(rect.position.x + pad, rect.position.y + pad * 0.5 + font.get_ascent(fs)),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.95, 0.85, color.a))


func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var total := from.distance_to(to)
	if total < 1.0:
		return
	var dir := (to - from) / total
	var d := 0.0
	while d < total:
		var e := minf(d + DASH_LENGTH * _k, total)
		draw_line(from + dir * d, from + dir * e, color, width * _k, true)
		d = e + GAP_LENGTH * _k


func _draw_arrowhead(tip: Vector2, direction: Vector2, color: Color) -> void:
	if direction == Vector2.ZERO:
		return
	var back := -direction * ARROW_HEAD_SIZE * _k
	var p1 := tip + back.rotated(ARROW_HEAD_ANGLE)
	var p2 := tip + back.rotated(-ARROW_HEAD_ANGLE)
	draw_colored_polygon(PackedVector2Array([tip, p1, p2]), color)
