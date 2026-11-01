extends SceneTree

# T11 — the LOS line tool (design doc §6).
#
# Covers the parts of LOSLineVisual that do not need a window:
#   - LOSLineVisual.judge(): clear / obscured / blocked, decided by the rules
#     engine's OWN predicates — RulesEngine.unit_sight_line for sight and
#     TerrainManager.unit_has_cover_11e (13.08, per firing model) for cover —
#     on the three curated boards the windowed scenario uses:
#       (a) open ground                         -> clear
#       (b) light terrain between, hiding part  -> obscured
#           of the target's base (visible, not
#           fully visible: benefit of cover)
#       (c) a dense ruin between                -> blocked
#   - the old bug: an 11e barricade (light terrain, Obscuring 13.10) right
#     across the line. The old version asked LineOfSightManager.check_los (10e
#     point rules, where low terrain never blocks) and said "obscured" for a
#     target the target list rejects for no line of sight; it must be blocked.
#   - the other cover sources the hit roll applies: an INFANTRY target within
#     an exposed area (sight passes through, 13.08 in-area cover) and a
#     stratagem-granted cover flag; a VEHICLE in the same crater has no cover.
#   - the line's endpoints are the base centres of the pair that proved
#     sight: a squad whose nearest model is walled off draws from the model
#     that CAN see, not from the nearest one.
#   - nothing to draw ({} / null) when a unit has no model on the battlefield.
#   - the node: current_line keys, Line2D points == [from, to], default_color
#     == the UIConstants slot, visible / hidden, z_index above the tokens,
#     a stroke of LINE_SCREEN_PX on screen at any zoom, and show_line()'s
#     cache (an unchanged pair is not re-judged; a moved model or a terrain
#     reload is).
#
# Usage: godot --headless --path . -s tests/test_los_line_visual.gd

var passed := 0
var failed := 0
var _ran := false

const S_POS := Vector2(400, 1200)
const T_POS := Vector2(1000, 1200)


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _init():
	create_timer(0.1).timeout.connect(_run_tests)


func _finish() -> void:
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _model(id: String, pos: Vector2, base_mm: int) -> Dictionary:
	return {"id": id, "alive": true, "base_mm": base_mm, "base_type": "circular",
		"rotation": 0.0, "position": {"x": pos.x, "y": pos.y}}


func _unit(owner: int, keywords: Array, models: Array) -> Dictionary:
	return {"owner": owner, "flags": {}, "models": models, "status": 2,
		"meta": {"name": "U", "display_name": "U", "keywords": keywords,
			"stats": {}, "weapons": [], "abilities": []}}


# A legacy rectangle piece, exactly what TerrainManager.load_terrain_from_save
# builds (the scenario installs its curated terrain through that path).
func _piece(id: String, type: String, center: Vector2, size: Vector2, height: String = "tall") -> Dictionary:
	var h := size * 0.5
	return {"id": id, "type": type, "height_category": height, "position": center,
		"size": size, "rotation": 0.0, "traits": [],
		"can_move_through": {"INFANTRY": true, "VEHICLE": false, "MONSTER": false},
		"polygon": PackedVector2Array([center + Vector2(-h.x, -h.y), center + Vector2(h.x, -h.y),
			center + Vector2(h.x, h.y), center + Vector2(-h.x, h.y)])}


func _decor() -> Dictionary:
	return _piece("t11_decor", "ruins", Vector2(1500, 600), Vector2(120, 120))


func _light_partial() -> Dictionary:
	# Above the centre line, between the units: hides the top of the target's
	# base from the shooter's centre, never the centre line itself.
	return _piece("t11_light", "barricade", Vector2(850, 1160), Vector2(60, 50), "low")


func _dense_across() -> Dictionary:
	return _piece("t11_dense", "ruins", Vector2(700, 1200), Vector2(80, 300))


func _set_terrain(tm, pieces: Array) -> void:
	tm.terrain_features = pieces
	tm.emit_signal("terrain_loaded", tm.terrain_features)


func _board(units: Dictionary, tm) -> Dictionary:
	return {"units": units, "terrain_features": tm.terrain_features}


func _run_tests() -> void:
	if _ran:
		return
	_ran = true
	print("\n=== test_los_line_visual (T11) ===\n")
	var tm = root.get_node_or_null("TerrainManager")
	var rules = root.get_node_or_null("RulesEngine")
	var gs = root.get_node_or_null("GameState")
	var uic = root.get_node_or_null("UIConstants")
	_check("autoloads reachable", tm != null and rules != null and gs != null and uic != null)
	if tm == null or rules == null or gs == null or uic == null:
		_finish()
		return
	var LV = load("res://scripts/LOSLineVisual.gd")
	_check("LOSLineVisual script loads", LV != null)
	if LV == null:
		_finish()
		return
	# API presence first, so a missing helper fails cleanly instead of
	# aborting the run on a script error (and hanging until the timeout).
	var api := []
	for m in LV.get_script_method_list():
		api.append(str(m.get("name", "")))
	for fn in ["judge", "target_has_cover", "show_line", "compute_line", "clear_line"]:
		_check("LOSLineVisual.%s exists" % fn, api.has(fn))
	_check("TerrainManager.unit_has_cover_11e exists", tm.has_method("unit_has_cover_11e"))
	_check("RulesEngine.unit_sight_line exists", rules.has_method("unit_sight_line"))
	if not (api.has("judge") and api.has("target_has_cover") and api.has("show_line") \
			and api.has("compute_line") and api.has("clear_line")):
		_finish()
		return

	var prev_edition = GameConstants.edition
	var prev_terrain = tm.terrain_features.duplicate(true)
	var prev_units = gs.state.get("units", {}).duplicate(true)
	GameConstants.edition = 11

	var shooter := _unit(2, ["INFANTRY", "CHARACTER"], [_model("m1", S_POS, 40)])
	var target := _unit(1, ["VEHICLE", "WALKER"], [_model("m1", T_POS, 60)])
	var units := {"U_S": shooter, "U_T": target}
	var target_model: Dictionary = target.models[0]
	var shooter_model: Dictionary = shooter.models[0]

	print("-- (a) open ground --")
	_set_terrain(tm, [_decor()])
	rules.clear_los_memo()
	var b := _board(units, tm)
	var v = LV.judge("U_S", "U_T", b)
	_check("(a) clear", v.get("los_state", "") == "clear", str(v))
	_check("(a) agrees with RulesEngine.unit_sight_line (sees)",
		rules.unit_sight_line("U_S", "U_T", b, false).has_los)
	_check("(a) agrees with unit_has_cover_11e (no cover)",
		not tm.unit_has_cover_11e(target, shooter_model))
	_check("(a) line runs base centre to base centre",
		v.get("from", Vector2.INF) == S_POS and v.get("to", Vector2.INF) == T_POS,
		"%s -> %s" % [str(v.get("from")), str(v.get("to"))])

	print("\n-- (b) light terrain between, hiding part of the target --")
	_set_terrain(tm, [_decor(), _light_partial()])
	rules.clear_los_memo()
	b = _board(units, tm)
	v = LV.judge("U_S", "U_T", b)
	_check("(b) obscured", v.get("los_state", "") == "obscured", str(v))
	_check("(b) the target is still visible (unit_sight_line)",
		rules.unit_sight_line("U_S", "U_T", b, false).has_los)
	_check("(b) visible but not fully visible (06.01)",
		tm.model_visible_11e(shooter_model, target_model) and not tm.model_fully_visible_11e(shooter_model, target_model))
	_check("(b) the hit roll's 13.08 test grants cover", tm.unit_has_cover_11e(target, shooter_model))
	_check("(b) same endpoints as (a)",
		v.get("from", Vector2.INF) == S_POS and v.get("to", Vector2.INF) == T_POS)

	print("\n-- (c) dense ruin between --")
	_set_terrain(tm, [_decor(), _dense_across()])
	rules.clear_los_memo()
	b = _board(units, tm)
	v = LV.judge("U_S", "U_T", b)
	_check("(c) blocked", v.get("los_state", "") == "blocked", str(v))
	_check("(c) agrees with RulesEngine.unit_sight_line (no sight)",
		not rules.unit_sight_line("U_S", "U_T", b, false).has_los)
	_check("(c) a blocked line still runs between the nearest base centres",
		v.get("from", Vector2.INF) == S_POS and v.get("to", Vector2.INF) == T_POS)

	print("\n-- regression: 11e barricade right across the line --")
	_set_terrain(tm, [_decor(), _piece("t11_barricade", "barricade", Vector2(700, 1200), Vector2(40, 300), "low")])
	rules.clear_los_memo()
	b = _board(units, tm)
	v = LV.judge("U_S", "U_T", b)
	_check("barricade across the line: blocked (light terrain is Obscuring, 13.10)",
		v.get("los_state", "") == "blocked", str(v))
	_check("…and the rules engine agrees: no sight line",
		not rules.unit_sight_line("U_S", "U_T", b, false).has_los)
	var los_mgr = root.get_node_or_null("LineOfSightManager")
	if los_mgr != null:
		_check("…which the old path, LineOfSightManager.check_los (10e: low terrain never blocks), got wrong",
			los_mgr.check_los(S_POS, T_POS, shooter_model, target_model),
			"if this flips, the old bug's premise changed — the verdict above is what matters")

	print("\n-- a terrain change drops the sight-line memo --")
	# GameState snapshots nest terrain under board.board, so RulesEngine's
	# terrain-epoch guard never fired; TerrainManager now clears the memo on
	# every terrain_loaded. Without it the node checks below judged (c) on the
	# memoized (b) answer and drew yellow for a walled-off target.
	rules.unit_sight_line("U_S", "U_T", gs.create_snapshot(false), false)
	rules._los_memo["t11_probe"] = true
	_set_terrain(tm, [_decor()])
	_check("terrain_loaded clears RulesEngine._los_memo", not rules._los_memo.has("t11_probe"),
		"%d memo entries survived" % rules._los_memo.size())

	print("\n-- other cover sources the hit roll applies --")
	var crater := _piece("t11_crater", "craters", Vector2(1000, 1500), Vector2(200, 200))
	_set_terrain(tm, [_decor(), crater])
	rules.clear_los_memo()
	var inf := _unit(1, ["INFANTRY"], [_model("m1", Vector2(1000, 1500), 32)])
	var veh := _unit(1, ["VEHICLE"], [_model("m1", Vector2(1000, 1500), 60)])
	b = _board({"U_S": shooter, "U_INF": inf, "U_VEH": veh}, tm)
	v = LV.judge("U_S", "U_INF", b)
	_check("INFANTRY within an exposed area: obscured (13.08 in-area cover)",
		v.get("los_state", "") == "obscured", str(v))
	v = LV.judge("U_S", "U_VEH", b)
	_check("a VEHICLE in the same area has no cover: clear", v.get("los_state", "") == "clear", str(v))
	_set_terrain(tm, [_decor()])
	rules.clear_los_memo()
	var covered := _unit(1, ["VEHICLE"], [_model("m1", T_POS, 60)])
	covered.flags["stratagem_cover"] = true
	b = _board({"U_S": shooter, "U_T": covered}, tm)
	v = LV.judge("U_S", "U_T", b)
	_check("stratagem cover flag in open ground: obscured", v.get("los_state", "") == "obscured", str(v))

	print("\n-- the line starts at the model that can see --")
	_set_terrain(tm, [_decor(), _piece("t11_wall", "ruins", Vector2(700, 1200), Vector2(80, 160))])
	rules.clear_los_memo()
	var squad := _unit(2, ["INFANTRY"], [_model("a", S_POS, 40), _model("b", Vector2(400, 900), 40)])
	b = _board({"U_SQ": squad, "U_T": target}, tm)
	v = LV.judge("U_SQ", "U_T", b)
	_check("squad with its nearest model walled off: clear", v.get("los_state", "") == "clear", str(v))
	_check("…drawn from the model that sees (400, 900), not the nearest (400, 1200)",
		v.get("from", Vector2.INF) == Vector2(400, 900), str(v.get("from")))
	_check("…to the target's base centre", v.get("to", Vector2.INF) == T_POS)

	print("\n-- nothing to draw --")
	var dead := _unit(1, ["VEHICLE"], [_model("m1", T_POS, 60)])
	dead.models[0]["alive"] = false
	b = _board({"U_S": shooter, "U_DEAD": dead}, tm)
	_check("a unit with no alive model: {}", LV.judge("U_S", "U_DEAD", b).is_empty())
	_check("an unknown unit: {}", LV.judge("U_S", "NOPE", b).is_empty())

	print("\n-- the node --")
	gs.state["units"] = {"U_S": shooter.duplicate(true), "U_T": target.duplicate(true)}
	_set_terrain(tm, [_decor()])
	rules.clear_los_memo()
	var lv = LV.new()
	root.add_child(lv)
	var line2d: Line2D = lv.get_node_or_null("Line")
	_check("Line child exists", line2d != null)
	_check("draws above the tokens (TokenVisual z_index 10)", lv.z_index > 10, str(lv.z_index))
	_check("nothing drawn before a hover", lv.current_line == null and line2d != null and not line2d.visible)
	var line = lv.compute_line("U_S", "U_T")
	_check("(a) current_line.color_slot == CONFIRMED_GREEN",
		line != null and line.color_slot == "CONFIRMED_GREEN", str(line))
	if line != null:
		_check("(a) current_line.los_state == clear", line.los_state == "clear")
		_check("current_line carries the pair", line.shooter_id == "U_S" and line.target_id == "U_T")
		_check("from / to are the base centres", line.from == S_POS and line.to == T_POS)
		_check("the Line2D runs from -> to",
			line2d.points.size() == 2 and line2d.points[0] == S_POS and line2d.points[1] == T_POS, str(line2d.points))
		_check("the Line2D is painted CONFIRMED_GREEN",
			line2d.default_color.is_equal_approx(uic.CONFIRMED_GREEN), line2d.default_color.to_html())
		_check("the Line2D is visible", line2d.visible)
		_check("stroke = LINE_SCREEN_PX at zoom 1", is_equal_approx(line2d.width, LV.LINE_SCREEN_PX), str(line2d.width))

	var again = lv.show_line("U_S", "U_T")
	var third = lv.show_line("U_S", "U_T")
	_check("show_line: an unchanged pair is not re-judged (same dict)", is_same(again, third))

	_set_terrain(tm, [_decor(), _light_partial()])
	var after_reload = lv.show_line("U_S", "U_T")
	_check("show_line: a terrain reload re-judges -> MARGINAL_YELLOW / obscured",
		after_reload != null and not is_same(after_reload, third) \
			and after_reload.color_slot == "MARGINAL_YELLOW" and after_reload.los_state == "obscured", str(after_reload))
	_check("the Line2D is painted MARGINAL_YELLOW",
		line2d.default_color.is_equal_approx(uic.MARGINAL_YELLOW), line2d.default_color.to_html())

	_set_terrain(tm, [_decor(), _dense_across()])
	var blocked = lv.show_line("U_S", "U_T")
	_check("(c) INVALID_RED / blocked",
		blocked != null and blocked.color_slot == "INVALID_RED" and blocked.los_state == "blocked", str(blocked))
	_check("the Line2D is painted INVALID_RED",
		line2d.default_color.is_equal_approx(uic.INVALID_RED), line2d.default_color.to_html())

	# A moved model is a different board: re-judged without any terrain event.
	_set_terrain(tm, [_decor()])
	var before_move = lv.show_line("U_S", "U_T")
	gs.state["units"]["U_T"]["models"][0]["position"] = {"x": 1000.0, "y": 1300.0}
	var after_move = lv.show_line("U_S", "U_T")
	_check("show_line: a moved model re-judges, and the line follows the base",
		after_move != null and not is_same(after_move, before_move) and after_move.to == Vector2(1000, 1300),
		str(after_move))

	lv.clear_line()
	_check("clear_line: current_line null and the Line2D hidden",
		lv.current_line == null and not line2d.visible)
	_check("compute_line(\"\", \"\") draws nothing", lv.compute_line("", "") == null and not line2d.visible)
	_check("compute_line on an unknown shooter draws nothing", lv.compute_line("NOPE", "U_T") == null)

	# Constant on-screen stroke: under a half-scale parent the board-space
	# width doubles, so the screen width stays LINE_SCREEN_PX.
	var holder := Node2D.new()
	holder.scale = Vector2(0.5, 0.5)
	root.add_child(holder)
	var lv2 = LV.new()
	holder.add_child(lv2)
	lv2.compute_line("U_S", "U_T")
	var l2: Line2D = lv2.get_node("Line")
	_check("stroke stays LINE_SCREEN_PX on screen at zoom 0.5 (board width doubles)",
		is_equal_approx(l2.width, LV.LINE_SCREEN_PX / 0.5), str(l2.width))

	lv.queue_free()
	holder.queue_free()
	gs.state["units"] = prev_units
	tm.terrain_features = prev_terrain
	GameConstants.edition = prev_edition
	rules.clear_los_memo()
	_finish()
