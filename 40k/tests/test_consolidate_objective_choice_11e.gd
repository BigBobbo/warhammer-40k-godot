extends SceneTree

# 11e 12.08 BEFORE MOVING — Objective Consolidation: "select ONE of those
# objectives".
#
# Bug: the phase never let the player select. ConsolidationMove.before_moving
# took `objs[0]` — the first eligible objective in BOARD ORDER — and the UI had
# no picker. The official 11e terrain layouts author their markers in the order
# obj_home_1, obj_home_2, obj_nml_1, obj_nml_2, obj_center, so the centre
# objective is considered LAST: a unit within 3" of both its backfield marker
# and the centre was told to consolidate backwards toward the corner, and every
# drag toward the centre was reverted.
#
# Covered here:
#   1. The default is the CLOSEST selectable objective, not the first authored.
#   2. objective_candidates_scored() lists every selectable marker, closest first.
#   3. A player's pick (chosen_objective) is honoured end to end.
#   4. A pick the unit cannot select falls back to the closest at template level,
#      and is REJECTED with a 12.08 reason when it rides on a CONSOLIDATE action.
#   5. The pick changes the geometry: the same drag is legal toward one
#      objective and illegal toward the other (the drag verdict, the client-side
#      validation and the real CONSOLIDATE all agree).
#
# Usage: godot --headless --path . -s tests/test_consolidate_objective_choice_11e.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

# 40px = 1". A 32mm base is ~0.63" of radius, so edge-to-marker distances are
# ~0.63" shorter than the centre-to-centre spans below.
#   obj_home_1 (400,400) = 10", obj_center (600,400) = 15", obj_far (1600,400) = 40"
#   U_A single model at (520,400) = 13" — 2.37" from HOME 1's marker, 1.37" from
#   CENTER's, and nowhere near obj_far. BOTH are selectable; CENTER is closer,
#   but HOME 1 is authored first, exactly like the real layouts.
func _board() -> void:
	var gs = root.get_node("GameState")
	gs.state["board"] = {
		"size": {"width": 44, "height": 60},
		"objectives": [
			{"id": "obj_home_1", "position": Vector2(400, 400), "radius_mm": 40, "zone": "player1"},
			{"id": "obj_center", "position": Vector2(600, 400), "radius_mm": 40, "zone": "no_mans_land"},
			{"id": "obj_far", "position": Vector2(1600, 400), "radius_mm": 40, "zone": "no_mans_land"},
		],
		"terrain": []
	}
	gs.state["units"] = {
		"U_A": {"id": "U_A", "owner": 1, "status": 2, "flags": {"was_eligible_to_fight": true},
			"meta": {"name": "Consolidators", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1, "objective_control": 2}},
			"models": [
				{"id": "m0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32, "base_type": "circular", "rotation": 0.0, "position": {"x": 520, "y": 400}},
			]},
		# Far-off enemy: no Ongoing/Engaging mode can pre-empt Objective mode.
		"U_B": {"id": "U_B", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Enemy", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [
				{"id": "e0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32, "base_type": "circular", "rotation": 0.0, "position": {"x": 1600, "y": 1600}},
			]},
	}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 10

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_consolidate_objective_choice_11e ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	if gs == null or pm == null:
		_check("autoloads", false); _finish(); return
	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition

	GameConstants.edition = 11
	# Open ground: the default terrain layout the autoload boots with would
	# otherwise HOST these synthetic markers (14.01), and a terrain objective is
	# "in range" by base overlap rather than by distance.
	var tm = root.get_node_or_null("/root/TerrainManager")
	var prev_terrain: Array = []
	if tm != null:
		prev_terrain = tm.terrain_features.duplicate(true)
		tm.terrain_features.clear()
	_board()
	pm.transition_to_phase(10)  # FIGHT
	var fp = pm.get_current_phase_instance()
	fp.execute_action({"type": "END_PILE_IN", "player": 1})
	fp.execute_action({"type": "END_PILE_IN", "player": 2})
	# 12.08 ELIGIBLE IF: "was eligible to fight this phase". U_A never fought
	# (no enemy near it), so stamp it here — phase entry clears the stamps.
	gs.state["units"]["U_A"]["flags"]["was_eligible_to_fight"] = true

	var tmpl: ConsolidationMove = MoveTypes.get_type("consolidation")
	var meas = root.get_node("/root/Measurement")

	print("-- the board deliberately authors the FAR objective first --")
	_check("board order is HOME 1 then CENTER (as the real 11e layouts do)",
		str(gs.state.board.objectives[0].id) == "obj_home_1" and str(gs.state.board.objectives[1].id) == "obj_center")

	print("\n-- 1/2: candidates are every selectable marker, CLOSEST first --")
	var scored = tmpl.objective_candidates_scored("U_A", gs.state)
	var ids: Array = []
	for e in scored:
		ids.append(str(e.id))
	_check("both markers within 3\" are selectable, obj_far is not", ids == ["obj_center", "obj_home_1"], str(ids))
	var d_center = meas.px_to_inches(float(scored[0].distance_px))
	var d_home = meas.px_to_inches(float(scored[1].distance_px))
	# Base edge -> marker EDGE (the 40mm disc is 0.79" of radius), so these are
	# the numbers a player would measure with a tape.
	_check("distances are measured base edge -> marker edge (~0.58\" / ~1.58\")",
		abs(d_center - 0.58) < 0.1 and abs(d_home - 1.58) < 0.1, "center=%.2f home=%.2f" % [d_center, d_home])

	var before_default = tmpl.before_moving("U_A", gs.state, null, {"mode": "objective"})
	_check("default objective is the CLOSEST (obj_center), not the first authored (obj_home_1)",
		str(before_default.get("objective", "")) == "obj_center", str(before_default.get("objective", "")))

	print("\n-- 3: the player's pick is honoured --")
	var before_pick = tmpl.before_moving("U_A", gs.state, null, {"mode": "objective", "chosen_objective": "obj_home_1"})
	_check("chosen_objective obj_home_1 is taken", str(before_pick.get("objective", "")) == "obj_home_1",
		str(before_pick.get("objective", "")))

	print("\n-- 4: an unselectable pick falls back to the closest --")
	var before_bad = tmpl.before_moving("U_A", gs.state, null, {"mode": "objective", "chosen_objective": "obj_far"})
	_check("obj_far (>3\" away) is not taken — falls back to obj_center",
		str(before_bad.get("objective", "")) == "obj_center", str(before_bad.get("objective", "")))

	print("\n-- the phase context the UI reads --")
	var ctx_default = fp.get_consolidation_context_11e("U_A")
	_check("phase context mode is objective", str(ctx_default.get("mode", "")) == "objective", str(ctx_default.get("mode", "")))
	_check("phase context defaults to obj_center", str(ctx_default.get("objective", "")) == "obj_center",
		str(ctx_default.get("objective", "")))
	var options: Array = ctx_default.get("objective_options", [])
	_check("picker options carry both markers, closest first", options.size() == 2
		and str(options[0].get("id", "")) == "obj_center" and str(options[1].get("id", "")) == "obj_home_1", str(options))
	_check("picker labels name the marker the way the board does (CENTER / HOME 1)",
		str(options[0].get("label", "")) == "CENTER" and str(options[1].get("label", "")) == "HOME 1", str(options))
	_check("aim point is the SELECTED objective's centre",
		ctx_default.get("objective_position", Vector2.ZERO) == Vector2(600, 400),
		str(ctx_default.get("objective_position", Vector2.ZERO)))
	var ctx_home = fp.get_consolidation_context_11e("U_A", "obj_home_1")
	_check("phase context honours the pick (obj_home_1)", str(ctx_home.get("objective", "")) == "obj_home_1",
		str(ctx_home.get("objective", "")))
	_check("aim point follows the pick", ctx_home.get("objective_position", Vector2.ZERO) == Vector2(400, 400),
		str(ctx_home.get("objective_position", Vector2.ZERO)))

	print("\n-- 5: the pick changes what the drag will accept --")
	# 13" -> 16": onto CENTER (ends in range of it) but 3" further from HOME 1
	# (and out of its range), so it is legal only while CENTER is selected.
	var toward_center = Vector2(640, 400)
	var drag_center = fp.check_consolidation_model_move_11e("U_A", "0", toward_center, ctx_default)
	var drag_home = fp.check_consolidation_model_move_11e("U_A", "0", toward_center, ctx_home)
	_check("drag onto CENTER is allowed while CENTER is selected", drag_center.get("allowed", false), str(drag_center))
	_check("the same drag is refused while HOME 1 is selected", not drag_home.get("allowed", true), str(drag_home))

	print("\n-- the Consolidate step: the step data names the default marker --")
	fp._begin_consolidation_step_11e()
	_check("Consolidate step is ACTIVE", fp.consolidation_step_11e == fp.ConsolidationStep11e.ACTIVE)
	_check("P1 (active) consolidates first", fp.consolidating_player_11e == 1)
	var step_data = fp._build_consolidation_step_data_11e(["U_A"])
	var row = step_data.get("eligible_units", {}).get("U_A", {})
	_check("the picker row names the default objective (CENTER)",
		str(row.get("mode", "")) == "objective" and str(row.get("objective_label", "")) == "CENTER", str(row))

	print("\n-- CONSOLIDATE validation follows the pick --")
	var move_action = {"type": "CONSOLIDATE", "unit_id": "U_A", "movements": {"0": toward_center}, "player": 1}
	var v_default = fp._validate_consolidate(move_action)
	_check("move onto CENTER is valid by default (was rejected pre-fix: HOME 1 was picked for you)",
		v_default.valid, str(v_default))
	var v_home = fp._validate_consolidate({"type": "CONSOLIDATE", "unit_id": "U_A",
		"movements": {"0": toward_center}, "player": 1, "chosen_objective": "obj_home_1"})
	_check("the same move is rejected when the player selected HOME 1", not v_home.valid, str(v_home))
	var v_bad = fp._validate_consolidate({"type": "CONSOLIDATE", "unit_id": "U_A",
		"movements": {"0": toward_center}, "player": 1, "chosen_objective": "obj_far"})
	_check("selecting an objective the unit is not within 3\" of is rejected with a 12.08 reason",
		not v_bad.valid and str(v_bad.errors).contains("12.08"), str(v_bad))

	print("\n-- the whole move, through the real action pipeline --")
	# The player picks the FARTHER marker on purpose and shuffles toward it —
	# still legal (it ends in range of the selected objective).
	var r = fp.execute_action({"type": "CONSOLIDATE", "unit_id": "U_A",
		"movements": {"0": Vector2(480, 400)}, "player": 1, "chosen_objective": "obj_home_1"})
	_check("CONSOLIDATE toward the PLAYER-SELECTED objective succeeds", r.get("success", false), str(r))
	_check("the model actually moved toward HOME 1",
		float(gs.state["units"]["U_A"]["models"][0]["position"]["x"]) == 480.0,
		str(gs.state["units"]["U_A"]["models"][0]["position"]))

	print("\n-- 6: a TERRAIN-HOSTED objective is ranked by its AREA (14.01) --")
	# The reported case: a Stompa (180mm base) touching the wide central ruin
	# that HOSTS obj_center, with a backfield marker whose DOT is nearer than the
	# ruin's centre dot. Ranking by marker centres would send the Stompa
	# backwards; ranking by the objective itself keeps it on the ruin it is
	# standing on.
	if tm != null:
		tm.load_terrain_layout("take_and_hold_mirror_1")
		var objectives: Array = []
		for obj in tm.layout_objectives:
			var pos = obj.get("position", [0, 0])
			objectives.append({
				"id": str(obj.get("id", "")),
				"position": Vector2(meas.inches_to_px(float(pos[0])), meas.inches_to_px(float(pos[1]))),
				"radius_mm": int(obj.get("radius_mm", 40)),
				"zone": str(obj.get("zone", "no_mans_land")),
				"source_pieces": obj.get("source_pieces", []).duplicate()
			})
		# A plain marker 5" to the west of the Stompa — nearer by marker dot,
		# further from the model than the ruin it is already touching.
		objectives.append({"id": "obj_nml_9", "position": Vector2(meas.inches_to_px(9.5), meas.inches_to_px(30.0)),
			"radius_mm": 40, "zone": "no_mans_land", "source_pieces": []})
		gs.state["board"]["objectives"] = objectives
		gs.state["units"] = {"U_STOMPA": {"id": "U_STOMPA", "owner": 1, "status": 2,
			"flags": {"was_eligible_to_fight": true},
			"meta": {"name": "Stompa", "keywords": ["VEHICLE", "TITANIC"], "stats": {"move": 8, "wounds": 30}},
			"models": [{"id": "m0", "alive": true, "wounds": 30, "current_wounds": 30, "base_mm": 180,
				"base_type": "circular", "rotation": 0.0,
				"position": {"x": meas.inches_to_px(14.5), "y": meas.inches_to_px(30.0)}}]}}
		var stompa_model = gs.state["units"]["U_STOMPA"]["models"][0]
		var mm = root.get_node("/root/MissionManager")
		var d_ruin = meas.px_to_inches(mm.model_distance_to_objective_px(stompa_model, objectives[_index_of(objectives, "obj_center")]))
		var d_dot = meas.px_to_inches(meas.model_edge_to_point_distance_px(stompa_model, objectives[_index_of(objectives, "obj_center")].position))
		var d_nml9 = meas.px_to_inches(mm.model_distance_to_objective_px(stompa_model, objectives[_index_of(objectives, "obj_nml_9")]))
		_check("the Stompa is ON the ruin hosting CENTER (distance 0) though its dot is ~4\" away",
			d_ruin < 0.01 and d_dot > 3.0, "area=%.2f dot=%.2f" % [d_ruin, d_dot])
		_check("the plain marker's dot is nearer than CENTER's dot", d_nml9 < d_dot, "nml9=%.2f dot=%.2f" % [d_nml9, d_dot])
		var scored_t = tmpl.objective_candidates_scored("U_STOMPA", gs.state)
		var ids_t: Array = []
		for e in scored_t:
			ids_t.append(str(e.id))
		_check("the objective it is standing on is the default, not the nearer dot",
			not ids_t.is_empty() and ids_t[0] == "obj_center", str(ids_t))
		_check("the other marker is still offered as a choice", "obj_nml_9" in ids_t, str(ids_t))

	GameConstants.edition = prev_edition
	if tm != null:
		tm.terrain_features = prev_terrain
	gs.state = prev_state
	_finish()

func _index_of(objectives: Array, obj_id: String) -> int:
	for i in range(objectives.size()):
		if str(objectives[i].get("id", "")) == obj_id:
			return i
	return -1

func _finish() -> void:
	print("\n==== RESULT: %d passed, %d failed ====" % [passed, failed])
	quit(0 if failed == 0 else 1)
