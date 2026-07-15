extends SceneTree

# ISS — Consolidate onto a TERRAIN-HOSTED objective (11e 14.01 + 12.08).
#
# Bug: a unit standing ON a large central terrain objective (controlling it)
# was told "no consolidation mode applies — the unit cannot move". Objective
# control (MissionManager) treats a model as in range when its base overlaps
# the hosting terrain area(s), but ConsolidationMove measured only
# model-edge -> marker CENTRE vs 3"+20mm, so a unit whose bases sat >3.78"
# from the marker centre (easy on a ~11" wide central ruin) fell through to
# "no mode". The two now share MissionManager.model_in_objective_range so they
# can never disagree.
#
# This test drives the pure-logic layer:
#   1. Terrain objective, model in the area but >3.78" from centre → objective
#      mode applies (regression guard for the fix).
#   2. Open-ground objective, model within 3.78" of centre → objective mode
#      still applies (no regression to the classic path).
#   3. Open-ground objective, model well beyond range → no mode (still gated).
#
# Usage: godot --headless --path . -s tests/test_repro_consolidate_terrain_obj.gd

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
	root.connect("ready", Callable(self, "_run"))

func _run() -> void:
	var mm = root.get_node("/root/MissionManager")
	var tm = root.get_node("/root/TerrainManager")
	var meas = root.get_node("/root/Measurement")
	var gs = root.get_node("/root/GameState")
	var tmpl: ConsolidationMove = MoveTypes.get_type("consolidation")

	# The real game runs 11e (terrain-hosted objectives active); autoload init
	# leaves the headless default at 10, so opt in explicitly like the other
	# 11e tests do.
	GameConstants.edition = 11

	# ── Case 1: terrain-hosted central objective ────────────────────────────
	# obj_center is hosted by two trapezoids spanning x[16.25,27.75] y[25,35];
	# marker centre (22,30). A model deep in a corner is inside the area but
	# ~6" from the centre point.
	tm.load_terrain_layout("take_and_hold_mirror_1")
	var objectives := []
	for obj in tm.layout_objectives:
		var p = obj.get("position", [0, 0])
		objectives.append({
			"id": str(obj.get("id", "")),
			"position": Vector2(meas.inches_to_px(float(p[0])), meas.inches_to_px(float(p[1]))),
			"radius_mm": int(obj.get("radius_mm", 40)),
			"zone": str(obj.get("zone", "no_mans_land")),
			"source_pieces": obj.get("source_pieces", []).duplicate()
		})

	var corner_in = Vector2(17.5, 34.0)
	_setup_board(gs, meas, objectives, corner_in)
	var d_centre = corner_in.distance_to(Vector2(22, 30))
	_check("case1: model is >3.79\" from marker centre", d_centre > ConsolidationMove.OBJECTIVE_RANGE_INCHES,
		"dist=%.2f" % d_centre)
	var objs1 = tmpl._objectives_within("U_TEST", gs.state, ConsolidationMove.OBJECTIVE_WITHIN_INCHES)
	var mode1 = str(tmpl.select_mode("U_TEST", gs.state).get("mode", ""))
	_check("case1: MissionManager agrees model controls obj_center", _obj_in_range(mm, gs, "obj_center"))
	_check("case1: obj_center within consolidate range (terrain-aware)", objs1.has("obj_center"),
		"objs=%s" % str(objs1))
	_check("case1: objective mode applies (was '' before fix)", mode1 == "objective", "mode='%s'" % mode1)

	# ── Case 1b: WITHIN 3" of the terrain area but NOT on it ────────────────
	# (22,37.5): ~2.5" below the area's y=35 edge — the unit does not control
	# the objective yet, but 12.08 BEFORE offers Objective mode ("within 3" of
	# the objective") so it can consolidate ONTO the ruin.
	_setup_board(gs, meas, objectives, Vector2(22.0, 37.5))
	var ctrl_1b = _obj_in_range(mm, gs, "obj_center")
	var mode1b = str(tmpl.select_mode("U_TEST", gs.state).get("mode", ""))
	_check("case1b: model does NOT yet control obj_center (not on the area)", not ctrl_1b)
	_check("case1b: objective mode still applies (within 3\" of the area)", mode1b == "objective",
		"mode='%s'" % mode1b)

	# ── Case 1c: MORE than 3" from every objective area → no mode ───────────
	# (10,38) sits ~5"+ from the nearest objective area (obj_center's ruin and
	# obj_home_2's ruin), with no enemies near → Objective mode must NOT be
	# offered. (Picked clear of ALL five terrain objectives — a spot only just
	# past obj_center would still be within 3" of obj_home_2's area.)
	_setup_board(gs, meas, objectives, Vector2(10.0, 38.0))
	var mode1c = str(tmpl.select_mode("U_TEST", gs.state).get("mode", ""))
	_check("case1c: >3\" from every objective area → no consolidation mode", mode1c == "",
		"mode='%s'" % mode1c)

	# ── Case 2: open-ground objective, model within the marker radius ───────
	# Plain objective (no source_pieces) at (10,10); model edge within 3.78".
	var open_objs := [{
		"id": "obj_open", "position": Vector2(meas.inches_to_px(10), meas.inches_to_px(10)),
		"radius_mm": 40, "zone": "no_mans_land", "source_pieces": []
	}]
	_setup_board(gs, meas, open_objs, Vector2(12.0, 10.0))  # 2" from centre → in range
	var mode2 = str(tmpl.select_mode("U_TEST", gs.state).get("mode", ""))
	_check("case2: open-ground objective within radius → objective mode", mode2 == "objective",
		"mode='%s'" % mode2)

	# ── Case 3: open-ground objective, model far away → no mode ─────────────
	_setup_board(gs, meas, open_objs, Vector2(30.0, 40.0))  # ~36" away
	var mode3 = str(tmpl.select_mode("U_TEST", gs.state).get("mode", ""))
	_check("case3: model far from any objective → no consolidation mode", mode3 == "",
		"mode='%s'" % mode3)

	print("\n==== RESULT: %d passed, %d failed ====" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _setup_board(gs, meas, objectives: Array, model_pos_in: Vector2) -> void:
	var px = Vector2(meas.inches_to_px(model_pos_in.x), meas.inches_to_px(model_pos_in.y))
	var unit := {
		"id": "U_TEST", "owner": 1,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"stats": {"objective_control": 2}},
		"flags": {"was_eligible_to_fight": true},
		"models": [{
			"id": "m1", "alive": true, "owner": 1,
			"position": {"x": px.x, "y": px.y},
			"base_mm": 32, "base_type": "circular", "rotation": 0.0
		}]
	}
	gs.state["board"] = {"objectives": objectives, "size": {"width": 44, "height": 60}}
	gs.state["units"] = {"U_TEST": unit}

func _obj_in_range(mm, gs, obj_id: String) -> bool:
	var model = gs.state["units"]["U_TEST"]["models"][0]
	for o in gs.state["board"]["objectives"]:
		if str(o.get("id", "")) == obj_id:
			return mm.model_in_objective_range(model, o)
	return false
