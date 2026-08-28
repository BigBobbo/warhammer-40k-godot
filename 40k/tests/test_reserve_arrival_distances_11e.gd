extends SceneTree

# 11e 20.04 INGRESS MOVE — the two distances in the set-up, and how they are
# measured. Companion to test_reserve_opponent_dz_11e.gd (the DZ ban).
#
#   "Set up your unit wholly within the set-up distance [6"] of one or more
#    battlefield edges and more than 8" horizontally from all enemy units."
#
# Three defects this pins, all found while fixing the opponent-DZ ban:
#
#   1. THE STAND-OFF IS 8" AT 11e, NOT 9". DeploymentController baked 9.0 into
#      a const while MovementPhase read GameConstants (8" at 11e), so the
#      placement UI refused legal 8-9" arrivals that the engine would accept.
#   2. IT IS MEASURED BASE EDGE TO BASE EDGE. IngressMove compared centre
#      points, which let a unit arrive up to both base radii closer than the
#      rule allows — nearly 4" closer against a big enemy base.
#   3. THE 6" BAND IS "WHOLLY WITHIN". Every path measured the centre dot, so
#      a base could hang its own radius past the line (2" for a 100mm oval).
#
# Driven through the REAL MovementPhase._validate_place_reinforcement.
#
# Usage: godot --headless --path . -s tests/test_reserve_arrival_distances_11e.gd

var passed := 0
var failed := 0
var _ran := false

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.2).timeout.connect(_run_tests)

const PX := 40.0

# Radii in inches, for readable arithmetic in the cases below.
#   32mm base  -> 16mm  -> 0.6299"
#   160mm base -> 80mm  -> 3.1496"
const R32 := 0.6299
const R160 := 3.1496

func _seed(gs, arriving_base_mm: int, enemy_base_mm: int, enemy_x_inches: float) -> void:
	gs.state["meta"]["battle_round"] = 3   # past the opponent-DZ ban, isolating distances
	gs.state["meta"]["active_player"] = 1
	gs.state["units"] = {
		"U_RES": {"id": "U_RES", "owner": 1, "status": 7,
			"reserve_type": "strategic_reserves", "flags": {"in_reserves": true},
			"meta": {"name": "Reserve Squad", "keywords": ["INFANTRY"], "stats": {"move": 6}},
			"models": [{"id": "m0", "alive": true, "base_mm": arriving_base_mm,
				"base_type": "circular", "position": null}]},
		"U_FOE": {"id": "U_FOE", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Foe", "keywords": ["INFANTRY"], "stats": {"move": 6}},
			"models": [{"id": "e0", "alive": true, "base_mm": enemy_base_mm,
				"base_type": "circular", "position": {"x": enemy_x_inches * PX, "y": 30.0 * PX}}]},
	}

func _place(mp, x_in: float, y_in: float) -> Dictionary:
	return mp.validate_action({
		"type": "PLACE_REINFORCEMENT",
		"unit_id": "U_RES",
		"model_positions": [{"x": x_in * PX, "y": y_in * PX}],
		"model_rotations": [0.0],
	})

func _has(res: Dictionary, needle: String) -> bool:
	for e in res.get("errors", []):
		if needle in str(e):
			return true
	return false

func _run_tests():
	if _ran:
		return
	_ran = true
	print("\n=== test_reserve_arrival_distances_11e ===\n")

	var gs = root.get_node_or_null("GameState")
	if gs == null:
		_check("GameState autoload reachable", false); _finish(); return
	var prev_edition: int = gs.get_edition()
	gs.initialize_default_state("hammer_anvil")

	print("-- the constant is edition-aware (20.04 / 24.20) --")
	gs.set_edition(11)
	_check("11e reserves stand-off is 8\"", is_equal_approx(GameConstants.reinforcement_min_enemy_distance_inches(), 8.0))
	_check("11e Infiltrators stand-off is 8\"", is_equal_approx(GameConstants.infiltrators_min_enemy_distance_inches(), 8.0))
	gs.set_edition(10)
	_check("10e reserves stand-off is 9\"", is_equal_approx(GameConstants.reinforcement_min_enemy_distance_inches(), 9.0))
	_check("10e Infiltrators stand-off is 9\"", is_equal_approx(GameConstants.infiltrators_min_enemy_distance_inches(), 9.0))

	var mp = load("res://phases/MovementPhase.gd").new()
	root.add_child(mp)

	# ── 1. 8" vs 9" ───────────────────────────────────────────────────────
	# Two 32mm bases: radii sum 1.26". Enemy centred at x = 12", arrival at
	# x = 2.24" on the same row -> centres 9.76" apart -> 8.5" edge to edge.
	# Legal at 11e (>8"), illegal at 10e (not >9"). Both bases sit in the left
	# 6" band, well clear of it.
	# NOTE: the ENGINE already read GameConstants here, so this pair passed
	# before the fix too — defect 1 lived only in the placement UI
	# (DeploymentController's baked-in 9.0), which is pinned by the windowed
	# scenario reserves_arrival_distances_11e, not here. It is kept as the
	# engine-side anchor the UI is now required to agree with.
	print("\n-- 8.5\" from the enemy: legal at 11e, illegal at 10e --")
	_seed(gs, 32, 32, 12.0)
	gs.set_edition(11)
	mp.enter_phase(gs.create_snapshot())
	var v = _place(mp, 2.24, 30.0)
	_check("11e: 8.5\" edge-to-edge is legal", v.get("valid", false), str(v.get("errors")))

	gs.set_edition(10)
	mp.enter_phase(gs.create_snapshot())
	v = _place(mp, 2.24, 30.0)
	_check("10e: the same 8.5\" is rejected (9\" rule)",
		not v.get("valid", true) and _has(v, "from enemy models"), str(v.get("errors")))

	# ── 2. edge-to-edge, not centre-to-centre ─────────────────────────────
	# A 160mm enemy base (3.15" radius) at x = 10". Arrival at x = 1.5" is
	# 8.5" centre to centre -- which the old centre-point test waved through --
	# but only 4.72" base edge to base edge, which is nowhere near legal.
	print("\n-- big enemy base: centres 8.5\" apart, edges 4.7\" apart --")
	_seed(gs, 32, 160, 10.0)
	gs.set_edition(11)
	mp.enter_phase(gs.create_snapshot())
	var centre_gap := 10.0 - 1.5
	var edge_gap := centre_gap - R32 - R160
	_check("fixture really is centre>8\" but edge<8\"", centre_gap > 8.0 and edge_gap < 8.0,
		"centre %.2f edge %.2f" % [centre_gap, edge_gap])
	v = _place(mp, 1.5, 30.0)
	_check("11e: rejected on the BASE-EDGE gap, not the centre gap",
		not v.get("valid", true) and _has(v, "within 8\" of an enemy model"), str(v.get("errors")))

	# ...and pushing out until the BASES are >8" apart makes the same spot legal.
	# Centre at x = 10 - (8.1 + R32 + R160) = -1.88 would be off-board, so move
	# the enemy in from the right instead: enemy x = 22", arrival x = 22 - 11.9.
	_seed(gs, 32, 160, 22.0)
	mp.enter_phase(gs.create_snapshot())
	var legal_x := 22.0 - (8.1 + R32 + R160)   # 10.12" -> outside the 6" band, so
	_check("that separation is >8\" edge-to-edge", (22.0 - legal_x) - R32 - R160 > 8.0)

	# ── 3. "wholly within" the 6" band ────────────────────────────────────
	# 32mm base, enemy parked far away. x = 5.5" puts the base's far side at
	# 6.13" -- past the line; x = 5.3" puts it at 5.93" -- inside it. y = 30"
	# so only the LEFT band is in play (a corner would be inside two bands).
	print("\n-- the 6\" band is 'wholly within', not centre-only --")
	_seed(gs, 32, 32, 30.0)
	gs.set_edition(11)
	mp.enter_phase(gs.create_snapshot())
	_check("fixture: 5.5\" centre puts the base past the 6\" line", 5.5 + R32 > 6.0)
	v = _place(mp, 5.5, 30.0)
	_check("11e: base overhanging the 6\" line is REJECTED",
		not v.get("valid", true) and _has(v, "wholly within"), str(v.get("errors")))

	_check("fixture: 5.3\" centre keeps the base inside", 5.3 + R32 < 6.0)
	v = _place(mp, 5.3, 30.0)
	_check("11e: base wholly inside the 6\" line is legal", v.get("valid", false), str(v.get("errors")))

	# Same pair on the legacy 10e path, which carried the identical wording.
	gs.set_edition(10)
	mp.enter_phase(gs.create_snapshot())
	v = _place(mp, 5.5, 30.0)
	_check("10e: base overhanging the 6\" line is REJECTED",
		not v.get("valid", true) and _has(v, "wholly within"), str(v.get("errors")))
	v = _place(mp, 5.3, 30.0)
	_check("10e: base wholly inside the 6\" line is legal", v.get("valid", false), str(v.get("errors")))

	# A model 10" in from every edge is still out, as it always was.
	gs.set_edition(11)
	mp.enter_phase(gs.create_snapshot())
	v = _place(mp, 10.0, 30.0)
	_check("11e: 10\" from every edge is still rejected", not v.get("valid", true), str(v.get("errors")))

	gs.set_edition(prev_edition)
	mp.queue_free()
	_finish()

func _finish() -> void:
	print("\n=== %d passed, %d failed ===\n" % [passed, failed])
	quit(1 if failed > 0 else 0)
