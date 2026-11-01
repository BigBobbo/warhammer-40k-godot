extends SceneTree

# T03 — drag ruler with budget colouring (design doc §5 quick-win #1).
#
# 1. RulesEngine.movement_drag_budget: M and the Advance allowance per active
#    move — Normal (D6 max on top), Advance (the rolled value), Fall Back /
#    Surge / reactive moves (nothing on top), Turbo-boost style flat moves.
# 2. MovementController._split_path_by_budget: the coloured runs of a path —
#    CONFIRMED_GREEN within M, MARGINAL_YELLOW within M + Advance, INVALID_RED
#    beyond — for straight drags, movement already spent this phase, a SHIFT
#    waypoint corner, and the exact-M epsilon. Every run's distance_inches is
#    its geometric length.
# 3. MovementController.compute_drag_segments / drag_budget_for_unit: the what-if
#    API reads M from the unit (no hardcoded Advance any more).
# 4. MovementPhase BEGIN_MODEL_DRAG: validated (active move, live model of the
#    unit or an attached CHARACTER), state-free, and announces the pick-up on
#    model_drag_requested with the model's owning unit.
# 5. MovementRangeVisual.DragRuler: shows / clears the path and its label, and
#    paints each run in its UIConstants slot colour.
#
# Usage: godot --headless --path . -s tests/test_drag_ruler_budget.gd

const PX := 40.0  # Measurement.PX_PER_INCH

var passed := 0
var failed := 0


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _init() -> void:
	# Autoloads are added after SceneTree._init — run once they are live.
	call_deferred("_run")


func _run() -> void:
	print("\n=== test_drag_ruler_budget ===\n")
	var gs = root.get_node_or_null("GameState")
	var rules = root.get_node_or_null("RulesEngine")
	_check("GameState + RulesEngine autoloads live", gs != null and rules != null)
	if gs == null or rules == null:
		_finish()
		return
	var prev_state = gs.state.duplicate(true)
	gs.state["units"] = _units()

	_test_budget(rules)
	_test_split()
	_test_what_if()
	_test_begin_model_drag()
	_test_drag_ruler_visual()

	gs.state = prev_state
	_finish()


func _units() -> Dictionary:
	var m := func(id: String, x: float, y: float, alive: bool = true) -> Dictionary:
		return {"id": id, "alive": alive, "wounds": 2, "current_wounds": 2,
			"base_mm": 40, "base_type": "circular", "position": {"x": x, "y": y}}
	return {
		"U_MOVER": {"id": "U_MOVER", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Movers", "keywords": ["INFANTRY"], "stats": {"move": 6}},
			"attachment_data": {"attached_characters": ["U_CHAR"]},
			"models": [m.call("m1", 400, 400), m.call("m2", 470, 400, false)]},
		"U_CHAR": {"id": "U_CHAR", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Leader", "keywords": ["INFANTRY", "CHARACTER"], "stats": {"move": 6}},
			"attachment_data": {"attached_to": "U_MOVER"},
			"models": [m.call("m1", 400, 470)]},
		"U_BIKE": {"id": "U_BIKE", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Bike", "keywords": ["MOUNTED"], "stats": {"move": 12}},
			"models": [m.call("m1", 800, 400)]},
	}


# ---------------------------------------------------------------------------
# 1. RulesEngine.movement_drag_budget
# ---------------------------------------------------------------------------
func _test_budget(rules) -> void:
	print("-- RulesEngine.movement_drag_budget --")
	var b: Dictionary = rules.movement_drag_budget({"mode": "NORMAL", "move_cap_inches": 6.0})
	_check("Normal M6: move 6, advance = D6 max 6, total 12",
		b.get("move") == 6.0 and b.get("advance") == 6.0 and b.get("total") == 12.0, str(b))
	_check("D6 max constant is 6\"", rules.ADVANCE_DIE_MAX_INCHES == 6.0)
	b = rules.movement_drag_budget({"mode": "ADVANCE", "move_cap_inches": 9.0, "advance_roll": 3})
	_check("Advance rolled 3 on M6 (cap 9): move 6, advance 3",
		b.get("move") == 6.0 and b.get("advance") == 3.0 and b.get("total") == 9.0, str(b))
	b = rules.movement_drag_budget({"mode": "ADVANCE", "move_cap_inches": 24.0, "advance_roll": 0})
	_check("flat 24\" advance (no roll): move 24, advance 0",
		b.get("move") == 24.0 and b.get("advance") == 0.0, str(b))
	b = rules.movement_drag_budget({"mode": "ADVANCE", "move_cap_inches": 4.0, "advance_roll": 9})
	_check("an advance roll above the cap is clamped to it",
		b.get("advance") == 4.0 and b.get("move") == 0.0, str(b))
	for mode in ["FALL_BACK", "SURGE", "REMAIN_STATIONARY", ""]:
		b = rules.movement_drag_budget({"mode": mode, "move_cap_inches": 6.0})
		_check("%s: no Advance on top (move 6, advance 0)" % (mode if mode != "" else "<no mode>"),
			b.get("move") == 6.0 and b.get("advance") == 0.0, str(b))
	b = rules.movement_drag_budget({"mode": "NORMAL", "move_cap_inches": 6.0, "is_reactive_move": true})
	_check("reactive Normal move: no Advance on top", b.get("advance") == 0.0, str(b))
	b = rules.movement_drag_budget({})
	_check("empty move data: zero budget, no crash", b.get("total") == 0.0, str(b))


# ---------------------------------------------------------------------------
# 2. MovementController._split_path_by_budget
# ---------------------------------------------------------------------------
func _slots(runs: Array) -> Array:
	var out: Array = []
	for r in runs:
		out.append(str(r.color_slot))
	return out


func _dists(runs: Array) -> Array:
	var out: Array = []
	for r in runs:
		out.append(snappedf(float(r.distance_inches), 0.001))
	return out


func _near(a: float, b: float, tol: float = 0.01) -> bool:
	return absf(a - b) <= tol


func _test_split() -> void:
	print("-- MovementController._split_path_by_budget --")
	var mc = load("res://scripts/MovementController.gd").new()
	var budget := {"move": 6.0, "advance": 6.0}
	var o := Vector2(400, 400)

	var r: Array = mc._split_path_by_budget([o, o + Vector2(0, 4 * PX)], 0.0, budget, false)
	_check("4\" drag: one CONFIRMED_GREEN run of 4\"",
		_slots(r) == ["CONFIRMED_GREEN"] and _near(r[0].distance_inches, 4.0), "%s %s" % [_slots(r), _dists(r)])

	r = mc._split_path_by_budget([o, o + Vector2(0, 9 * PX)], 0.0, budget, false)
	_check("9\" drag: green 6\" then MARGINAL_YELLOW 3\"",
		_slots(r) == ["CONFIRMED_GREEN", "MARGINAL_YELLOW"] and _near(r[0].distance_inches, 6.0)
		and _near(r[1].distance_inches, 3.0), "%s %s" % [_slots(r), _dists(r)])
	_check("9\" drag: the yellow run starts where the green run ends (6\" out)",
		r.size() == 2 and (r[0].to as Vector2).is_equal_approx(r[1].from)
		and (r[1].from as Vector2).is_equal_approx(o + Vector2(0, 6 * PX)), str(r))

	r = mc._split_path_by_budget([o, o + Vector2(0, 14 * PX)], 0.0, budget, false)
	_check("14\" drag: green 6\", yellow 6\", INVALID_RED 2\"",
		_slots(r) == ["CONFIRMED_GREEN", "MARGINAL_YELLOW", "INVALID_RED"]
		and _near(r[0].distance_inches, 6.0) and _near(r[1].distance_inches, 6.0)
		and _near(r[2].distance_inches, 2.0), "%s %s" % [_slots(r), _dists(r)])
	_check("14\" drag: the red run ends on the cursor",
		r.size() == 3 and (r[2].to as Vector2).is_equal_approx(o + Vector2(0, 14 * PX)))

	r = mc._split_path_by_budget([o, o + Vector2(6 * PX, 0)], 0.0, budget, false)
	_check("exactly 6\": all green (no sliver of yellow)", _slots(r) == ["CONFIRMED_GREEN"], str(_slots(r)))

	# Movement already spent this phase (a staged leg, a paid pivot) eats into M.
	r = mc._split_path_by_budget([o, o + Vector2(0, 9 * PX)], 3.0, budget, false)
	_check("3\" already spent, 9\" drag: green 3\", yellow 6\"",
		_slots(r) == ["CONFIRMED_GREEN", "MARGINAL_YELLOW"] and _near(r[0].distance_inches, 3.0)
		and _near(r[1].distance_inches, 6.0), "%s %s" % [_slots(r), _dists(r)])
	r = mc._split_path_by_budget([o, o + Vector2(0, 2 * PX)], 7.0, budget, false)
	_check("7\" already spent: the whole drag is yellow", _slots(r) == ["MARGINAL_YELLOW"], str(_slots(r)))

	# A SHIFT waypoint: 4" east, then 4" south — the budget carries across the corner.
	var wp := o + Vector2(4 * PX, 0)
	r = mc._split_path_by_budget([o, wp, wp + Vector2(0, 4 * PX)], 0.0, budget, false)
	_check("waypoint path (4\" + 4\"): green 4\", green 2\", yellow 2\"",
		_slots(r) == ["CONFIRMED_GREEN", "CONFIRMED_GREEN", "MARGINAL_YELLOW"]
		and _near(r[0].distance_inches, 4.0) and _near(r[1].distance_inches, 2.0)
		and _near(r[2].distance_inches, 2.0), "%s %s" % [_slots(r), _dists(r)])
	_check("waypoint path: the second leg starts on the corner",
		r.size() == 3 and (r[1].from as Vector2).is_equal_approx(wp))

	# No Advance on top (Fall Back): straight from green to red.
	r = mc._split_path_by_budget([o, o + Vector2(0, 8 * PX)], 0.0, {"move": 6.0, "advance": 0.0}, false)
	_check("no Advance allowance: green 6\" then red 2\" (no yellow)",
		_slots(r) == ["CONFIRMED_GREEN", "INVALID_RED"], str(_slots(r)))

	_check("zero-length path: no runs", mc._split_path_by_budget([o, o], 0.0, budget, false).is_empty())

	var total := 0.0
	for run in mc._split_path_by_budget([o, o + Vector2(3 * PX, 4 * PX) * 2.6], 0.0, budget, false):
		total += float(run.distance_inches)
	_check("diagonal 13\" drag: run distances add up to the drag length",
		_near(total, 13.0), "sum %.3f" % total)
	mc.free()


# ---------------------------------------------------------------------------
# 3. compute_drag_segments / drag_budget_for_unit (what-if API)
# ---------------------------------------------------------------------------
func _test_what_if() -> void:
	print("-- MovementController.compute_drag_segments --")
	var mc = load("res://scripts/MovementController.gd").new()
	var b: Dictionary = mc.drag_budget_for_unit("U_BIKE")
	_check("drag_budget_for_unit: an M12 unit not yet moving gets move 12 + advance 6",
		b.get("move") == 12.0 and b.get("advance") == 6.0, str(b))
	_check("drag_budget_for_unit: unknown unit -> {}", mc.drag_budget_for_unit("NOPE").is_empty())
	var o := Vector2(800, 400)
	var r: Array = mc.compute_drag_segments("U_BIKE", o, o + Vector2(0, 14 * PX))
	_check("M12 unit, 14\" drag: green 12\" then yellow 2\" (M read from the unit)",
		_slots(r) == ["CONFIRMED_GREEN", "MARGINAL_YELLOW"] and _near(r[0].distance_inches, 12.0),
		"%s %s" % [_slots(r), _dists(r)])
	_check("compute_drag_segments stores its result in current_drag_segments",
		mc.current_drag_segments.size() == 2 and str(mc.current_drag_segments[-1].color_slot) == "MARGINAL_YELLOW")
	_check("compute_drag_segments for an unknown unit clears the ruler",
		mc.compute_drag_segments("NOPE", o, o + Vector2(0, 40)).is_empty() and mc.current_drag_segments.is_empty())
	mc.free()


# ---------------------------------------------------------------------------
# 4. MovementPhase BEGIN_MODEL_DRAG
# ---------------------------------------------------------------------------
func _drag_action(model_id: String, source: String = "") -> Dictionary:
	var payload := {"model_id": model_id}
	if source != "":
		payload["model_source_unit_id"] = source
	return {"type": "BEGIN_MODEL_DRAG", "actor_unit_id": "U_MOVER", "payload": payload}


func _test_begin_model_drag() -> void:
	print("-- MovementPhase BEGIN_MODEL_DRAG --")
	var mp = load("res://phases/MovementPhase.gd").new()
	root.add_child(mp)
	mp.active_moves = {}
	var v: Dictionary = mp.validate_action(_drag_action("m1"))
	_check("no active move: refused", not v.get("valid", true), str(v))

	mp.active_moves = {"U_MOVER": {"mode": "NORMAL", "completed": false, "move_cap_inches": 6.0,
		"staged_moves": [], "model_distances": {}, "original_positions": {}}}
	v = mp.validate_action(_drag_action("m1"))
	_check("active Normal move, live model: accepted", v.get("valid", false), str(v))
	v = mp.validate_action(_drag_action("m2"))
	_check("destroyed model: refused", not v.get("valid", true), str(v))
	v = mp.validate_action(_drag_action("m9"))
	_check("model not in the unit: refused", not v.get("valid", true), str(v))
	v = mp.validate_action({"type": "BEGIN_MODEL_DRAG", "actor_unit_id": "U_MOVER", "payload": {}})
	_check("no model_id: refused", not v.get("valid", true), str(v))
	v = mp.validate_action(_drag_action("m1", "U_CHAR"))
	_check("attached CHARACTER's model (source named): accepted", v.get("valid", false), str(v))
	v = mp.validate_action(_drag_action("m1", "U_BIKE"))
	_check("a source unit that is not attached falls back to the unit's own m1", v.get("valid", false), str(v))

	var heard: Array = []
	mp.model_drag_requested.connect(func(u, m, s): heard.append([u, m, s]))
	var res: Dictionary = mp.process_action(_drag_action("m1", "U_CHAR"))
	_check("process: success with no state changes",
		res.get("success", false) and res.get("changes", ["x"]).is_empty(), str(res))
	_check("process: model_drag_requested(U_MOVER, m1, U_CHAR) emitted once",
		heard.size() == 1 and heard[0] == ["U_MOVER", "m1", "U_CHAR"], str(heard))
	mp.process_action(_drag_action("m1"))
	_check("process without a source: owner resolves to the unit itself",
		heard.size() == 2 and heard[1] == ["U_MOVER", "m1", "U_MOVER"], str(heard))

	mp.active_moves["U_MOVER"]["completed"] = true
	v = mp.validate_action(_drag_action("m1"))
	_check("completed move: refused", not v.get("valid", true), str(v))
	mp.active_moves["U_MOVER"]["completed"] = false
	mp.active_moves["U_MOVER"]["mode"] = "REMAIN_STATIONARY"
	v = mp.validate_action(_drag_action("m1"))
	_check("Remain Stationary: refused", not v.get("valid", true), str(v))
	mp.queue_free()


# ---------------------------------------------------------------------------
# 5. MovementRangeVisual.DragRuler
# ---------------------------------------------------------------------------
func _test_drag_ruler_visual() -> void:
	print("-- MovementRangeVisual.DragRuler --")
	var ruler = load("res://scripts/MovementRangeVisual.gd").DragRuler.new()
	root.add_child(ruler)
	_check("starts empty", not ruler.is_showing())
	var o := Vector2(100, 100)
	var segs := [
		{"from": o, "to": o + Vector2(0, 240), "color_slot": "CONFIRMED_GREEN", "distance_inches": 6.0},
		{"from": o + Vector2(0, 240), "to": o + Vector2(0, 360), "color_slot": "MARGINAL_YELLOW", "distance_inches": 3.0},
	]
	ruler.show_path(segs, [], o + Vector2(0, 360), "9.0\" Advance", "MARGINAL_YELLOW", 32.0)
	_check("show_path: showing, 2 runs held", ruler.is_showing() and ruler.segments.size() == 2)
	var label: Label = ruler.get_node_or_null("DragRulerLabel")
	_check("label shows the cumulative inches", label != null and label.visible and label.text == "9.0\" Advance",
		str(label.text) if label != null else "<no label>")
	_check("label sits beside the cursor, clear of the base",
		label != null and label.position.x >= o.x + 32.0 and absf(label.position.y - (o.y + 360)) < 40.0,
		str(label.position) if label != null else "")
	var ui = root.get_node_or_null("UIConstants")
	if ui != null:
		_check("label colour is the slot colour (MARGINAL_YELLOW)",
			label != null and label.get_theme_color("font_color").is_equal_approx(ui.MARGINAL_YELLOW))
		_check("slot_color maps each slot to UIConstants",
			ruler.slot_color("CONFIRMED_GREEN") == ui.CONFIRMED_GREEN
			and ruler.slot_color("MARGINAL_YELLOW") == ui.MARGINAL_YELLOW
			and ruler.slot_color("INVALID_RED") == ui.INVALID_RED)
	ruler.clear_path()
	_check("clear_path: nothing showing, label hidden", not ruler.is_showing() and label != null and not label.visible)
	ruler.queue_free()


func _finish() -> void:
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
