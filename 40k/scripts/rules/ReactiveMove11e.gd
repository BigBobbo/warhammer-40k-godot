extends RefCounted

## ReactiveMove11e — moves a rule grants OUTSIDE the Movement phase's own
## activation flow (11e), executed by the phase that opened a stratagem
## window (design .llm/ork_codex_11e_design.md §3.2 follow-ups):
##
##   kind "normal" — a NORMAL MOVE (09.05) with a stated maximum distance,
##     e.g. GRAB IT: "a normal move of up to 6\", and must end that move
##     within range of an objective" (opts.end_condition =
##     "within_objective_range").
##   kind "surge"  — a SURGE MOVE (21.02), e.g. GOADED INTO ACTION: "a surge
##     move of up to D6\"". BEFORE: the closest enemy unit is the surge
##     target (the engine's SurgeMove template). WHILE: each model must end
##     engaged with the surge target if possible, otherwise as close as
##     possible to it. AFTER: not engaged with any other enemy unit
##     (SurgeMove.after_moving_conditions).
##
## Positions are keyed "<unit_id>:<model_index>" -> Vector2 (px) and cover
## the unit AND its attached characters (19.03: an Attached unit moves as one).
## validate() is the single judge for the human's staged positions and for the
## engine's own placement; solve() is the auto-placement used by an AI decider
## and by the human's "Auto-move" button. Distances are straight-line per model
## (the shooting-phase reactive moves never cross terrain in the engine's
## current model), bases may not overlap other models, leave the board, or
## end in impassable terrain, and the moved unit must stay coherent.

const PX_PER_INCH := 40.0
const B2B_GAP_PX := 1.0          # keep a hair between bases so the strict overlap check accepts base contact
const STEP_IN := 0.25            # solver step (inches)


static func _n(node_name: String) -> Node:
	var main = Engine.get_main_loop()
	if main is SceneTree and main.root:
		return main.root.get_node_or_null(node_name)
	return null

static func _pos(m: Dictionary) -> Vector2:
	var p = m.get("position", null)
	if p is Vector2:
		return p
	if p is Dictionary:
		return Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	return Vector2.INF

static func _radius_px(m: Dictionary) -> float:
	var meas = _n("Measurement")
	if meas and meas.has_method("base_radius_px"):
		return float(meas.base_radius_px(int(m.get("base_mm", 32))))
	return float(m.get("base_mm", 32)) / 25.4 * PX_PER_INCH / 2.0


# ---------------------------------------------------------------------------
# Group / positions
# ---------------------------------------------------------------------------

## The unit plus its attached characters (or, for a character id, its
## bodyguard and the bodyguard's other characters). Bodyguard first.
static func group_ids(unit_id: String, board: Dictionary) -> Array:
	var units: Dictionary = board.get("units", {})
	var head := unit_id
	var attached_to = units.get(unit_id, {}).get("attached_to", null)
	if attached_to != null and str(attached_to) != "" and units.has(str(attached_to)):
		head = str(attached_to)
	var out: Array = [head]
	for cid in units.get(head, {}).get("attachment_data", {}).get("attached_characters", []):
		if units.has(str(cid)) and not str(cid) in out:
			out.append(str(cid))
	if not unit_id in out:
		out.append(unit_id)
	return out

## Current positions of every alive model of the group.
static func current_positions(unit_id: String, board: Dictionary) -> Dictionary:
	var out := {}
	var units: Dictionary = board.get("units", {})
	for gid in group_ids(unit_id, board):
		var models: Array = units.get(gid, {}).get("models", [])
		for i in range(models.size()):
			var m = models[i]
			if not m.get("alive", true):
				continue
			var p := _pos(m)
			if p == Vector2.INF:
				continue
			out["%s:%d" % [gid, i]] = p
	return out

static func _split_key(key: String) -> Array:
	var idx := key.rfind(":")
	return [key.substr(0, idx), int(key.substr(idx + 1))]

## Board copy (shallow) with the group's units deep-copied and `positions`
## applied — the hypothetical board every check runs against.
static func board_with_positions(board: Dictionary, unit_id: String, positions: Dictionary) -> Dictionary:
	var units: Dictionary = board.get("units", {}).duplicate(false)
	for gid in group_ids(unit_id, board):
		if units.has(gid):
			units[gid] = units[gid].duplicate(true)
	for key in positions:
		var parts := _split_key(str(key))
		var u = units.get(parts[0], null)
		if u == null:
			continue
		var models: Array = u.get("models", [])
		if parts[1] >= 0 and parts[1] < models.size():
			var p: Vector2 = positions[key]
			models[parts[1]]["position"] = {"x": p.x, "y": p.y}
	var out: Dictionary = board.duplicate(false)
	out["units"] = units
	return out

## Position diffs (the replay/network-safe form) for `positions`.
static func position_diffs(positions: Dictionary) -> Array:
	var diffs: Array = []
	for key in positions:
		var parts := _split_key(str(key))
		var p: Vector2 = positions[key]
		diffs.append({"op": "set", "path": "units.%s.models.%d.position" % [parts[0], parts[1]], "value": {"x": p.x, "y": p.y}})
	return diffs

## Every model of the group folded into one unit dict (coherency of an
## Attached unit is judged over all of its models — 19.03).
static func folded_group(board: Dictionary, unit_id: String) -> Dictionary:
	var units: Dictionary = board.get("units", {})
	var head = group_ids(unit_id, board)[0]
	var folded: Dictionary = units.get(head, {}).duplicate(false)
	var models: Array = []
	for gid in group_ids(unit_id, board):
		for m in units.get(gid, {}).get("models", []):
			models.append(m)
	folded["models"] = models
	return folded


# ---------------------------------------------------------------------------
# Surge target (21.02 BEFORE) — the engine's SurgeMove template
# ---------------------------------------------------------------------------

static func surge_target(unit_id: String, board: Dictionary) -> String:
	var tmpl = MoveTypes.get_type("surge")
	if tmpl == null:
		return ""
	return str(tmpl.before_moving(unit_id, board, null, {}).get("surge_target", ""))

## Edge-to-edge distance (inches) from a model dict to the closest alive
## model of `target_id` on `board`.
static func model_to_unit_inches(m: Dictionary, target_id: String, board: Dictionary) -> float:
	var meas = _n("Measurement")
	var best := INF
	for tm in board.get("units", {}).get(target_id, {}).get("models", []):
		if not tm.get("alive", true) or _pos(tm) == Vector2.INF:
			continue
		var d := INF
		if meas and meas.has_method("model_to_model_distance_inches"):
			d = float(meas.model_to_model_distance_inches(m, tm))
		else:
			d = (_pos(m).distance_to(_pos(tm)) - _radius_px(m) - _radius_px(tm)) / PX_PER_INCH
		best = minf(best, d)
	return best


# ---------------------------------------------------------------------------
# Validation — the single judge (human staging AND engine placement)
# ---------------------------------------------------------------------------

## kind: "normal" | "surge". origin/proposed: key -> Vector2.
## opts: {end_condition?: "within_objective_range", surge_target?: unit_id,
##        reference?: positions the solver reached (surge "as close as possible")}
## Returns {ok: bool, violations: Array[String]}.
static func validate(kind: String, unit_id: String, origin: Dictionary, proposed: Dictionary, max_inches: float, opts: Dictionary, board: Dictionary) -> Dictionary:
	var violations: Array = []
	var meas = _n("Measurement")
	var tol_px := 0.05 * PX_PER_INCH
	var max_px := max_inches * PX_PER_INCH
	var hypo := board_with_positions(board, unit_id, proposed)
	var units: Dictionary = hypo.get("units", {})
	var group := group_ids(unit_id, board)
	# Every other model that could block (alive, on the battlefield).
	var others: Array = []
	for oid in units:
		if oid in group:
			continue
		var ou = units[oid]
		if ou.get("embarked_in", null) != null:
			continue
		for om in ou.get("models", []):
			if om.get("alive", true) and _pos(om) != Vector2.INF:
				others.append(om)
	var moved_models: Array = []
	for key in proposed:
		var parts := _split_key(str(key))
		var u = units.get(parts[0], {})
		var models: Array = u.get("models", [])
		if parts[1] < 0 or parts[1] >= models.size():
			violations.append("unknown model %s" % key)
			continue
		var m = models[parts[1]]
		var start: Vector2 = origin.get(key, _pos(m))
		var dest := _pos(m)
		var moved_px := start.distance_to(dest)
		if moved_px > max_px + tol_px:
			violations.append("%s moved %.1f\" (max %.1f\")" % [key, moved_px / PX_PER_INCH, max_inches])
		if moved_px > 0.01 and meas:
			if meas.has_method("model_outside_board") and meas.model_outside_board(dest, m):
				violations.append("%s would leave the battlefield" % key)
			if meas.has_method("model_overlaps_any_wall") and meas.model_overlaps_any_wall(m, u.get("meta", {}).get("keywords", [])):
				violations.append("%s would end inside impassable terrain" % key)
		moved_models.append(m)
	if meas and meas.has_method("models_overlap"):
		for i in range(moved_models.size()):
			var mi = moved_models[i]
			for om in others:
				if meas.models_overlap(mi, om):
					violations.append("a model would overlap another unit's model")
					break
			for j in range(i + 1, moved_models.size()):
				if meas.models_overlap(mi, moved_models[j]):
					violations.append("two models of the unit would overlap")
					break
	if not violations.is_empty():
		return {"ok": false, "violations": violations}
	# AFTER MOVING (03.01 / 09.05 / 21.02)
	var coh = AttackSequence.check_unit_coherency(folded_group(hypo, unit_id))
	if not coh.get("coherent", true):
		violations.append("the unit would not be in coherency")
	var re = _n("RulesEngine")
	if kind == "normal":
		for gid in group:
			if re and re.is_unit_engaged(gid, hypo):
				violations.append("a normal move must end unengaged")
				break
		if str(opts.get("end_condition", "")) == "within_objective_range" and not group_within_objective_range(hypo, unit_id):
			violations.append("the move must end within range of an objective")
	elif kind == "surge":
		var target := str(opts.get("surge_target", ""))
		var tmpl = MoveTypes.get_type("surge")
		for gid in group:
			var after = tmpl.after_moving_conditions(gid, hypo, {"surge_target": target}) if tmpl else {"ok": true}
			if not after.get("ok", true):
				for v in after.get("violations", []):
					if not "coherency" in str(v):
						violations.append(str(v))
				break
		# WHILE MOVING: each model ends engaged with the surge target if
		# possible, else as close as possible — judged against what the
		# solver could reach for that model (opts.reference).
		var reference: Dictionary = opts.get("reference", {})
		if target != "" and not reference.is_empty():
			var ref_board := board_with_positions(board, unit_id, reference)
			var er := GameConstants.engagement_range_inches()
			for key in proposed:
				if not reference.has(key):
					continue
				var parts := _split_key(str(key))
				var pm = units.get(parts[0], {}).get("models", [])[parts[1]]
				var rm = ref_board.get("units", {}).get(parts[0], {}).get("models", [])[parts[1]]
				var d_prop := model_to_unit_inches(pm, target, hypo)
				var d_ref := model_to_unit_inches(rm, target, ref_board)
				if d_prop <= er + 0.05:
					continue
				if d_prop > d_ref + 0.5:
					violations.append("%s must end engaged with (or as close as possible to) the surge target" % key)
					break
	return {"ok": violations.is_empty(), "violations": violations}

static func group_within_objective_range(board: Dictionary, unit_id: String) -> bool:
	var mm = _n("MissionManager")
	if mm == null or not mm.has_method("model_in_objective_range"):
		return false
	var objectives: Array = board.get("board", {}).get("objectives", [])
	if objectives.is_empty():
		var gs = _n("GameState")
		if gs:
			objectives = gs.state.get("board", {}).get("objectives", [])
	var units: Dictionary = board.get("units", {})
	for gid in group_ids(unit_id, board):
		for m in units.get(gid, {}).get("models", []):
			if not m.get("alive", true) or _pos(m) == Vector2.INF:
				continue
			for obj in objectives:
				if mm.model_in_objective_range(m, obj):
					return true
	return false


# ---------------------------------------------------------------------------
# Solver — auto placement (AI decider, human "Auto-move")
# ---------------------------------------------------------------------------

## Returns proposed positions (key -> Vector2) that validate(), or {} when no
## legal placement was found (the unit then does not move).
static func solve(kind: String, unit_id: String, origin: Dictionary, max_inches: float, opts: Dictionary, board: Dictionary) -> Dictionary:
	if kind == "surge":
		return _solve_surge(unit_id, origin, max_inches, opts, board)
	return _solve_normal_to_objective(unit_id, origin, max_inches, opts, board)

static func _translated(origin: Dictionary, v: Vector2) -> Dictionary:
	var out := {}
	for key in origin:
		out[key] = origin[key] + v
	return out

## GRAB IT: translate the whole unit (formation kept, so coherency holds)
## toward the nearest reachable objective by the shortest distance that ends
## with a model within range of it; small angle offsets get around blockers.
static func _solve_normal_to_objective(unit_id: String, origin: Dictionary, max_inches: float, opts: Dictionary, board: Dictionary) -> Dictionary:
	if group_within_objective_range(board, unit_id):
		return origin.duplicate()  # already in range: a 0" move satisfies the rule
	var mm = _n("MissionManager")
	var gs = _n("GameState")
	if mm == null or gs == null:
		return {}
	var objectives: Array = gs.state.get("board", {}).get("objectives", [])
	var units: Dictionary = board.get("units", {})
	# (gap_in, objective_pos, closest model pos) per objective, nearest first
	var cands: Array = []
	for obj in objectives:
		var op = obj.get("position", Vector2.ZERO)
		if op is Dictionary:
			op = Vector2(float(op.get("x", 0)), float(op.get("y", 0)))
		var best_gap := INF
		var best_pos := Vector2.ZERO
		for key in origin:
			var parts := _split_key(str(key))
			var m = units.get(parts[0], {}).get("models", [])[parts[1]]
			var gap := maxf(0.0, float(mm.model_distance_to_objective_px(m, obj)) / PX_PER_INCH - 3.0)
			if gap < best_gap:
				best_gap = gap
				best_pos = origin[key]
		if best_gap <= max_inches + 0.001:
			cands.append({"gap": best_gap, "obj_pos": op, "from": best_pos})
	cands.sort_custom(func(a, b): return a.gap < b.gap)
	for c in cands:
		var base_dir: Vector2 = (c.obj_pos - c.from).normalized()
		if base_dir == Vector2.ZERO:
			continue
		for angle_deg in [0.0, 15.0, -15.0, 30.0, -30.0, 45.0, -45.0]:
			var dir := base_dir.rotated(deg_to_rad(angle_deg))
			var t: float = float(c.gap) + 0.1
			while t <= max_inches + 0.001:
				var proposed := _translated(origin, dir * (t * PX_PER_INCH))
				if validate("normal", unit_id, origin, proposed, max_inches, opts, board).ok:
					return proposed
				t += STEP_IN
	return {}

## GOADED INTO ACTION: per-model surge toward the surge target (base contact
## when reachable, otherwise the full distance straight at it), closest
## models placed first, colliding models backed off along their line. Falls
## back to a formation-keeping translation when per-model placement breaks
## coherency or engages a non-target unit.
static func _solve_surge(unit_id: String, origin: Dictionary, max_inches: float, opts: Dictionary, board: Dictionary) -> Dictionary:
	var target := str(opts.get("surge_target", ""))
	if target == "" or max_inches <= 0.0:
		return {}
	var units: Dictionary = board.get("units", {})
	var target_models: Array = []
	for tm in units.get(target, {}).get("models", []):
		if tm.get("alive", true) and _pos(tm) != Vector2.INF:
			target_models.append(tm)
	if target_models.is_empty():
		return {}
	var max_px := max_inches * PX_PER_INCH
	# closest target model per group model
	var entries: Array = []
	for key in origin:
		var parts := _split_key(str(key))
		var m = units.get(parts[0], {}).get("models", [])[parts[1]]
		var best_d := INF
		var best_tm = null
		for tm in target_models:
			var d: float = (origin[key] as Vector2).distance_to(_pos(tm)) - _radius_px(m) - _radius_px(tm)
			if d < best_d:
				best_d = d
				best_tm = tm
		entries.append({"key": key, "model": m, "gap_px": best_d, "tm": best_tm})
	entries.sort_custom(func(a, b): return a.gap_px < b.gap_px)
	var proposed := origin.duplicate()
	# Coherency is an AFTER-MOVING condition (03.01) and "as close as possible"
	# never licenses breaking it (01.04.03): the closest model goes straight at
	# its target; every later model takes the point closest to the target that
	# is within coherency of a model already placed — first along its straight
	# line, else on a ring around a placed model within its move budget.
	var coh_px := (GameConstants.coherency_distance_inches() - 0.25) * PX_PER_INCH
	var placed_keys: Array = []
	for e in entries:
		var start: Vector2 = origin[e.key]
		var tpos := _pos(e.tm)
		var tr := _radius_px(e.tm)
		var mr := _radius_px(e.model)
		var dir := (tpos - start).normalized()
		var best = null
		var best_score := INF
		if dir != Vector2.ZERO:
			var d := clampf(float(e.gap_px) - B2B_GAP_PX, 0.0, max_px)
			while d >= 0.0:
				var cand := start + dir * d
				var trial := proposed.duplicate()
				trial[e.key] = cand
				if _placement_clear(unit_id, e.key, trial, board) and _coherent_with_placed(cand, mr, placed_keys, proposed, units):
					best = cand
					best_score = cand.distance_to(tpos) - mr - tr
					break
				d -= STEP_IN * PX_PER_INCH
		if not placed_keys.is_empty() and best_score > B2B_GAP_PX * 2.0:
			for pk in placed_keys:
				var pparts := _split_key(str(pk))
				var pm = units.get(pparts[0], {}).get("models", [])[pparts[1]]
				var ppos: Vector2 = proposed[pk]
				var ring := mr + _radius_px(pm) + coh_px * 0.75
				for step_i in range(24):
					var cand2 := ppos + Vector2.RIGHT.rotated(TAU * float(step_i) / 24.0) * ring
					if start.distance_to(cand2) > max_px:
						continue
					var trial2 := proposed.duplicate()
					trial2[e.key] = cand2
					if not _placement_clear(unit_id, e.key, trial2, board):
						continue
					var score := cand2.distance_to(tpos) - mr - tr
					if score < best_score:
						best_score = score
						best = cand2
		proposed[e.key] = best if best != null else start
		placed_keys.append(e.key)
	var ref_opts := opts.duplicate()
	ref_opts.erase("reference")
	if validate("surge", unit_id, origin, proposed, max_inches, ref_opts, board).ok:
		return proposed
	# Fallback: keep the formation, translate toward the target.
	var lead = entries[0]
	var lead_dir: Vector2 = (_pos(lead.tm) - (origin[lead.key] as Vector2)).normalized()
	var t := clampf(float(lead.gap_px) - B2B_GAP_PX, 0.0, max_px)
	while t > 0.0:
		var trial2 := _translated(origin, lead_dir * t)
		if validate("surge", unit_id, origin, trial2, max_inches, ref_opts, board).ok:
			return trial2
		t -= STEP_IN * PX_PER_INCH
	return {}

## True when a model of radius `r` at `pos` is within coherency range (edge to
## edge) of one of the already-placed models (always true for the first one).
static func _coherent_with_placed(pos: Vector2, r: float, placed_keys: Array, positions: Dictionary, units: Dictionary) -> bool:
	if placed_keys.is_empty():
		return true
	var coh_px := GameConstants.coherency_distance_inches() * PX_PER_INCH
	for pk in placed_keys:
		var parts := _split_key(str(pk))
		var pm = units.get(parts[0], {}).get("models", [])[parts[1]]
		if pos.distance_to(positions[pk]) - r - _radius_px(pm) <= coh_px:
			return true
	return false

## True when the model `key` at its trial position overlaps no other model
## (other units and the group's already-placed models) and stays on the board.
static func _placement_clear(unit_id: String, key: String, trial: Dictionary, board: Dictionary) -> bool:
	var meas = _n("Measurement")
	if meas == null:
		return true
	var hypo := board_with_positions(board, unit_id, trial)
	var units: Dictionary = hypo.get("units", {})
	var parts := _split_key(key)
	var m = units.get(parts[0], {}).get("models", [])[parts[1]]
	if meas.has_method("model_outside_board") and meas.model_outside_board(_pos(m), m):
		return false
	for oid in units:
		var ou = units[oid]
		if ou.get("embarked_in", null) != null:
			continue
		var omodels: Array = ou.get("models", [])
		for i in range(omodels.size()):
			if oid == parts[0] and i == parts[1]:
				continue
			var om = omodels[i]
			if not om.get("alive", true) or _pos(om) == Vector2.INF:
				continue
			if meas.models_overlap(m, om):
				return false
	return true
