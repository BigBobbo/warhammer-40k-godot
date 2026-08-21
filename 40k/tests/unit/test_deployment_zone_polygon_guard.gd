extends SceneTree

# PM-F1 / PM-F6 — the deployment FORMULA must not emit placements outside the
# real deployment-zone polygon.
#
# _decide_deployment derives every position from a RECTANGULAR zone_bounds, and
# _resolve_formation_collisions clamps back to that same rectangle. For
# hammer_anvil and dawn_of_war the rectangle IS the zone and nothing goes
# wrong; for the triangular and stepped zones it is a strict over-approximation,
# so the formula proposed placements DeploymentPhase refuses as "not wholly
# within deployment zone". Each refusal costs a retry, and a unit that runs out
# of retries is dumped into Strategic Reserves.
#
# The plan path has had a polygon guard since PM-2a. This covers the formula
# path getting the same one.
#
# Run with: godot --headless --path . -s tests/unit/test_deployment_zone_polygon_guard.gd

const AIDM_PATH := "res://scripts/AIDecisionMaker.gd"
const DZD_PATH := "res://scripts/data/DeploymentZoneData.gd"

const PX := 40.0
const BASE_MM := 32

var AIDM
var DZD

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	create_timer(0.3).timeout.connect(_run)

func _run():
	print("\n=== Deployment zone polygon guard (PM-F1) Tests ===\n")
	AIDM = load(AIDM_PATH)
	DZD = load(DZD_PATH)
	if AIDM == null or DZD == null:
		_assert(false, "AIDecisionMaker and DeploymentZoneData load")
	else:
		_run_tests()
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	print("ALL TESTS PASSED" if _fail_count == 0 else "SOME TESTS FAILED")
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

# ---------------------------------------------------------------------------

func _snapshot(zone_id: String) -> Dictionary:
	return {
		"meta": {"deployment_type": zone_id, "battle_round": 1, "phase": 1},
		"board": {"size": {"width": 44, "height": 60},
			"deployment_zones": DZD.get_zones(zone_id),
			"terrain_features": [], "objectives": DZD.get_objectives(zone_id)},
		"units": {},
	}

func _models(n: int) -> Array:
	var out: Array = []
	for i in range(n):
		out.append({"id": "m%d" % i, "alive": true, "base_mm": BASE_MM,
			"base_type": "circular", "position": null, "rotation": 0.0})
	return out

func _radius_px() -> float:
	return AIDM._model_bounding_radius_px(BASE_MM, "circular", {})

func _naive_grid(bounds: Dictionary) -> Array:
	"""The shape the formula's own column grid produces, straight off the
	rectangle — this is what used to be emitted."""
	var out: Array = []
	var w: float = bounds.max_x - bounds.min_x
	for col in range(6):
		for row in range(4):
			var cx: float = bounds.min_x + (w / 6.0) * (col + 0.5)
			var cy: float = clampf(bounds.min_y + 80.0 + row * 60.0,
				bounds.min_y + 60.0, bounds.max_y - 60.0)
			out.append(Vector2(cx, cy))
	return out

# ---------------------------------------------------------------------------

func _run_tests() -> void:
	test_rectangular_zones_were_never_broken()
	test_non_rectangular_zones_do_leak_without_the_guard()
	test_guard_returns_an_in_zone_formation()
	test_guard_is_a_no_op_without_a_polygon()

func test_rectangular_zones_were_never_broken() -> void:
	# The guard must not "fix" anything on the zones that already worked, or it
	# would be changing deployment behaviour for every normal game.
	for zone_id in ["hammer_anvil", "dawn_of_war"]:
		for player in [1, 2]:
			var snap := _snapshot(zone_id)
			var bounds: Dictionary = AIDM._get_deployment_zone_bounds(snap, player)
			var poly: PackedVector2Array = AIDM._get_deployment_zone_polygon_pixels(snap, player)
			var leaked := 0
			for centre in _naive_grid(bounds):
				var pos: Array = AIDM._generate_formation_positions(centre, 5, BASE_MM, bounds)
				if not AIDM._formation_inside_zone(pos, _models(5), _radius_px(), poly):
					leaked += 1
			_assert(leaked == 0,
				"%s seat %d: the rectangle IS the zone, so nothing leaks (got %d of 24)" % [zone_id, player, leaked])

func test_non_rectangular_zones_do_leak_without_the_guard() -> void:
	# CONTROL. If the naive rectangle-derived grid did not actually leak, the
	# guard would be solving a problem that does not exist and the test below
	# would prove nothing.
	var worst_zone := ""
	var worst := 0
	for zone_id in ["crucible_of_battle", "search_and_destroy", "sweeping_engagement", "tipping_point"]:
		for player in [1, 2]:
			var snap := _snapshot(zone_id)
			var bounds: Dictionary = AIDM._get_deployment_zone_bounds(snap, player)
			var poly: PackedVector2Array = AIDM._get_deployment_zone_polygon_pixels(snap, player)
			var leaked := 0
			for centre in _naive_grid(bounds):
				var pos: Array = AIDM._generate_formation_positions(centre, 5, BASE_MM, bounds)
				if not AIDM._formation_inside_zone(pos, _models(5), _radius_px(), poly):
					leaked += 1
			if leaked > worst:
				worst = leaked
				worst_zone = "%s seat %d" % [zone_id, player]
	_assert(worst > 0,
		"CONTROL: the rectangle-derived grid really does leak outside the polygon — worst is %s at %d of 24 centres" % [worst_zone, worst])

func test_guard_returns_an_in_zone_formation() -> void:
	# Every shipped zone, both seats: the guard finds a formation that is
	# wholly inside the polygon.
	for zone_id in DZD.DEPLOYMENT_TYPES:
		for player in [1, 2]:
			var snap := _snapshot(zone_id)
			var bounds: Dictionary = AIDM._get_deployment_zone_bounds(snap, player)
			var poly: PackedVector2Array = AIDM._get_deployment_zone_polygon_pixels(snap, player)
			if poly.size() < 3:
				continue
			var models := _models(5)
			var found: Array = AIDM._find_in_zone_formation(models, BASE_MM, "circular", {},
				bounds, poly, [], ["INFANTRY"])
			_assert(not found.is_empty(),
				"%s seat %d: the guard finds an in-zone formation" % [zone_id, player])
			if found.is_empty():
				continue
			_assert(AIDM._formation_inside_zone(found, models, _radius_px(), poly),
				"…and every one of its %d models is wholly inside the polygon" % found.size())

func test_guard_is_a_no_op_without_a_polygon() -> void:
	# A zone with no polygon (or a snapshot that carries none) must defer to the
	# phase rather than refuse everything.
	var models := _models(5)
	var empty := PackedVector2Array()
	_assert(AIDM._formation_inside_zone([Vector2(0, 0), Vector2(9999, 9999)], models, _radius_px(), empty),
		"with no polygon the containment check passes everything through")
	_assert(AIDM._find_in_zone_formation(models, BASE_MM, "circular", {},
		{"min_x": 0.0, "max_x": 100.0, "min_y": 0.0, "max_y": 100.0}, empty, [], []).is_empty(),
		"…and the repair declines rather than inventing a position")
