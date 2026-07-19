extends SceneTree

# Regression: reinforcements arriving from Strategic Reserves / Deep Strike
# (PLACE_REINFORCEMENT, and Rapid Ingress's PLACE_RAPID_INGRESS_REINFORCEMENT)
# must NOT be set up overlapping models already on the board, overlapping each
# other, or on top of walls (03.02 set-up).
#
# Root cause (fixed): the 11e ingress template (IngressMove.validate_setup)
# only enforced distance rules and _validate_place_reinforcement early-returns
# on its verdict, so the engine accepted overlapping arrival formations. The
# AI relied on that rejection ("will likely fail validation, but retry logic
# will handle it") after its spiral search gave up, so AI-vs-AI games showed
# reserve units (e.g. Warbikers) stacked on themselves and on parked vehicles
# in the board-edge arrival strip.
#
# Also covers the AI-side gate: AIDecisionMaker._formation_really_overlaps
# must flag such formations (exact base shapes, not circle approximations).
#
# Usage: godot --headless --path . -s tests/test_reinforcement_setup_overlap_11e.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, ("  --  " + detail) if detail != "" else ""])

func _init():
	create_timer(0.2).timeout.connect(_run)

func _bike_model(id: String) -> Dictionary:
	# Warbikers: oval 75x42mm base, as shipped in Orks_2000.json
	return {"id": id, "alive": true, "wounds": 3, "current_wounds": 3,
		"base_mm": 75, "base_type": "oval",
		"base_dimensions": {"length": 42, "width": 75}, "position": null}

func _seed_state(gs) -> void:
	gs.state["meta"] = {
		"phase": GameStateData.Phase.MOVEMENT,
		"battle_round": 2,
		"turn_number": 2,
		"active_player": 1,
		"game_config": {"player1_type": "HUMAN", "player2_type": "HUMAN"}
	}
	gs.state["board"] = {
		"size": {"width": 44, "height": 60},
		"terrain": [],
		"deployment_zones": [
			{"player": 1, "poly": [{"x": 0, "y": 0}, {"x": 44, "y": 0}, {"x": 44, "y": 12}, {"x": 0, "y": 12}]},
			{"player": 2, "poly": [{"x": 0, "y": 48}, {"x": 44, "y": 48}, {"x": 44, "y": 60}, {"x": 0, "y": 60}]}
		]
	}
	gs.state["players"] = {"1": {"cp": 3}, "2": {"cp": 3}}
	gs.state["units"] = {
		# Battlewagon-like parked vehicle in the top-edge arrival strip
		"U_PARKED": {"id": "U_PARKED", "owner": 1, "status": GameStateData.UnitStatus.DEPLOYED, "flags": {},
			"meta": {"name": "Parked Wagon", "keywords": ["ORKS", "VEHICLE"], "abilities": [],
				"stats": {"move": 10, "toughness": 10, "save": 3, "wounds": 16, "objective_control": 5}},
			"models": [{"id": "m1", "alive": true, "wounds": 16, "current_wounds": 16,
				"base_mm": 180, "base_type": "rectangular",
				"base_dimensions": {"length": 100, "width": 180},
				"position": {"x": 400.0, "y": 120.0}, "rotation": 0.0}]},
		# The arriving unit (in strategic reserves)
		"U_BIKES": {"id": "U_BIKES", "owner": 1, "status": GameStateData.UnitStatus.IN_RESERVES,
			"flags": {"in_reserves": true}, "reserve_type": "strategic_reserves",
			"meta": {"name": "Warbikers", "keywords": ["ORKS", "MOUNTED"], "abilities": [],
				"stats": {"move": 12, "toughness": 6, "save": 4, "wounds": 3, "objective_control": 2}},
			"models": [_bike_model("m1"), _bike_model("m2"), _bike_model("m3")]},
		# A far-away enemy so the >8"/9" checks pass for top-edge arrivals
		"U_ENEMY": {"id": "U_ENEMY", "owner": 2, "status": GameStateData.UnitStatus.DEPLOYED, "flags": {},
			"meta": {"name": "Enemy", "keywords": ["INFANTRY"], "abilities": [],
				"stats": {"move": 6, "toughness": 4, "save": 4, "wounds": 1, "objective_control": 2}},
			"models": [{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1,
				"base_mm": 32, "base_type": "circular", "position": {"x": 880.0, "y": 2300.0}}]}
	}

func _action(positions: Array) -> Dictionary:
	return {"type": "PLACE_REINFORCEMENT", "unit_id": "U_BIKES",
		"model_positions": positions, "model_rotations": [0.0, 0.0, 0.0], "player": 1}

func _run():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_reinforcement_setup_overlap_11e ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	if gs == null or pm == null:
		_check("autoloads present", false)
		_finish()
		return
	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11

	_seed_state(gs)
	pm.transition_to_phase(GameStateData.Phase.MOVEMENT)
	var phase = pm.get_current_phase_instance()
	if phase == null:
		_check("movement phase instance", false)
		GameConstants.edition = prev_edition
		gs.state = prev_state
		_finish()
		return

	# --- Case A: models landing on the parked vehicle must be rejected ---
	# RectangularBase maps length->local X, width->local Y, so the wagon
	# (length=100, width=180) at rotation 0 occupies x 321..479, y -22..262.
	var on_wagon = [Vector2(360, 120), Vector2(440, 120), Vector2(420, 200)]
	var va = phase.validate_action(_action(on_wagon))
	_check("arrival overlapping a parked vehicle is rejected", not va.get("valid", true),
		str(va.get("errors", [])))
	var mentions_parked := false
	for e in va.get("errors", []):
		if "U_PARKED" in str(e):
			mentions_parked = true
	_check("rejection names the overlapped unit", mentions_parked, str(va.get("errors", [])))

	# --- Case B: arriving models stacked on each other must be rejected ---
	var stacked = [Vector2(900, 120), Vector2(920, 120), Vector2(1100, 120)]
	var vb = phase.validate_action(_action(stacked))
	_check("arrival with models overlapping each other is rejected", not vb.get("valid", true),
		str(vb.get("errors", [])))

	# --- Case C: a clear, legal arrival is still accepted ---
	var clear = [Vector2(900, 120), Vector2(1040, 120), Vector2(1180, 120)]
	var vc = phase.validate_action(_action(clear))
	_check("clear arrival in the edge strip is still accepted", vc.get("valid", false),
		str(vc.get("errors", [])))

	# --- Case D: the pre-11e path gets the same gate (no early return there) ---
	GameConstants.edition = 10
	var vd = phase.validate_action(_action(on_wagon))
	_check("pre-11e reinforcement overlap is rejected too", not vd.get("valid", true),
		str(vd.get("errors", [])))
	GameConstants.edition = 11

	# --- Case E: Rapid Ingress placement gets the same gate ---
	# Rapid Ingress fires on the OPPONENT's turn: player 1 ingresses while
	# player 2 is active (the validator derives the DZ ban from the active player).
	gs.state["meta"]["active_player"] = 2
	phase._rapid_ingress_unit_id = "U_BIKES"
	phase._rapid_ingress_player = 1
	var ve = phase.validate_action({"type": "PLACE_RAPID_INGRESS_REINFORCEMENT", "unit_id": "U_BIKES",
		"model_positions": on_wagon, "model_rotations": [0.0, 0.0, 0.0], "player": 1})
	_check("rapid ingress overlapping a parked vehicle is rejected", not ve.get("valid", true),
		str(ve.get("errors", [])))
	var vf = phase.validate_action({"type": "PLACE_RAPID_INGRESS_REINFORCEMENT", "unit_id": "U_BIKES",
		"model_positions": clear, "model_rotations": [0.0, 0.0, 0.0], "player": 1})
	_check("clear rapid ingress is still accepted", vf.get("valid", false),
		str(vf.get("errors", [])))
	phase._rapid_ingress_unit_id = ""
	gs.state["meta"]["active_player"] = 1

	# --- Case F: AI-side engine-exact formation gate ---
	var AIDM = load("res://scripts/AIDecisionMaker.gd")
	var obstacles = [{"position": Vector2(400, 120), "base_mm": 180, "base_type": "rectangular",
		"base_dimensions": {"length": 100, "width": 180}, "rotation": 0.0}]
	var dims = {"length": 42, "width": 75}
	_check("AI gate flags formation on the vehicle",
		AIDM._formation_really_overlaps(on_wagon, 75, "oval", dims, obstacles))
	_check("AI gate flags self-stacked formation",
		AIDM._formation_really_overlaps(stacked, 75, "oval", dims, obstacles))
	_check("AI gate passes a clear formation",
		not AIDM._formation_really_overlaps(clear, 75, "oval", dims, obstacles))
	# Circle-approximation blind spot: a bike off the wagon's LONG (Y) side.
	# Center distance 180px > averaged-radii threshold (~157px) so the AI's
	# circular pre-check calls it clear, but the real oval/rect bases overlap
	# (wagon reaches y=262, the bike's oval reaches up to y=241).
	var near_edge = [Vector2(400, 300), Vector2(900, 120), Vector2(1040, 120)]
	_check("AI gate catches oval-vs-rect overlap the circle approximation misses",
		AIDM._formation_really_overlaps(near_edge, 75, "oval", dims, obstacles))

	GameConstants.edition = prev_edition
	gs.state = prev_state
	_finish()

func _finish():
	print("\n=== RESULTS: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
