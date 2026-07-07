extends SceneTree

# Regression test for the "orc WAAAGH movement" bug.
#
# Symptom: the AI would announce "Boyz advances aggressively toward <enemy>",
# roll the advance, then barely move (or stay put entirely). Root cause:
# after the advance roll resolved, AIPlayer._execute_pending_advance_move()
# recomputed the per-model destinations toward the NEAREST OBJECTIVE instead of
# the enemy the AI had chosen. At the start of a game the nearest objective is
# the unit's own home objective — sitting directly behind it — so "advance 9\"
# toward the enemy" became a ~1\" shuffle backward that collided with the unit's
# own packed models and never landed.
#
# The fix: recompute toward the heading the AI originally chose, derived from the
# pre-roll per-model destinations, via AIPlayer._advance_heading_target().
# These tests pin that helper: it must return a point ALONG the original heading
# (toward the enemy), far enough to use the full move cap — never snap to a
# position behind the unit.
#
# Uses the live AIPlayer autoload (do NOT preload it — the script references other
# autoloads that only resolve once the project is running).
#
# Run with: godot --headless --script tests/unit/test_ai_advance_heading.gd

var _pass_count: int = 0
var _fail_count: int = 0
const PPI: float = 40.0  # AIDecisionMaker.PIXELS_PER_INCH

func _init():
	print("\n=== AI Advance Heading Tests ===\n")
	# Defer so autoloads (AIPlayer, Measurement, AIDecisionMaker) are ready.
	call_deferred("_run_tests")

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func _make_unit(centroid: Vector2) -> Dictionary:
	# 4 models arranged in a small square around `centroid`.
	var models = []
	var offs = [Vector2(-27, -27), Vector2(27, -27), Vector2(-27, 27), Vector2(27, 27)]
	for i in range(offs.size()):
		var p = centroid + offs[i]
		models.append({
			"id": "m%d" % (i + 1),
			"alive": true,
			"base_mm": 32.0,
			"position": {"x": p.x, "y": p.y},
		})
	return {"id": "U_TEST", "owner": 2, "meta": {"stats": {"move": 6}}, "models": models}

func _dests_toward(centroid: Vector2, direction: Vector2, inches: float) -> Dictionary:
	# Per-model destinations shifted `inches` along `direction` (an advance heading).
	var shift = direction.normalized() * inches * PPI
	var dests = {}
	var offs = [Vector2(-27, -27), Vector2(27, -27), Vector2(-27, 27), Vector2(27, 27)]
	for i in range(offs.size()):
		var d = centroid + offs[i] + shift
		dests["m%d" % (i + 1)] = [d.x, d.y]
	return dests

func _run_tests():
	var ai = root.get_node_or_null("/root/AIPlayer")
	if ai == null:
		print("FAIL: AIPlayer autoload not found")
		quit(1)
		return

	# --- Case 1: the reported bug. Unit is deployed at the bottom of the board;
	# the enemy it chose to advance on is NORTH (lower Y). The original
	# destinations point north. The recompute target MUST stay north. ---
	var centroid = Vector2(880, 2200)
	var north_enemy = Vector2(0, -1)  # toward lower Y = the enemy
	var dests_north = _dests_toward(centroid, north_enemy, 7.0)
	var target = ai._advance_heading_target(_make_unit(centroid), dests_north, 7.0)

	_assert(target != Vector2.INF, "heading target derived from non-empty destinations")
	_assert(target.y < centroid.y,
		"advance heads toward the enemy (north, y<%.0f), got y=%.0f — NOT back toward the home objective" % [centroid.y, target.y])
	# The projected point must be at least the cap away so the recompute can use
	# the full advance distance (the old estimate under-shot on high rolls).
	_assert(centroid.distance_to(target) >= 7.0 * PPI,
		"target projected at least the full move cap (%.0fpx) away, got %.0fpx" % [7.0 * PPI, centroid.distance_to(target)])

	# --- Case 2: heading is preserved for any direction, not just north.
	# A unit chasing an enemy to the EAST must get an eastward target. ---
	var east = Vector2(1, 0)
	var dests_east = _dests_toward(centroid, east, 9.0)
	var target_e = ai._advance_heading_target(_make_unit(centroid), dests_east, 9.0)
	_assert(target_e != Vector2.INF and target_e.x > centroid.x and abs(target_e.y - centroid.y) < 40.0,
		"eastward advance yields an eastward target (x>%.0f), got (%.0f,%.0f)" % [centroid.x, target_e.x, target_e.y])

	# --- Case 3: empty destinations -> INF so callers fall back safely. ---
	_assert(ai._advance_heading_target(_make_unit(centroid), {}, 7.0) == Vector2.INF,
		"empty destinations return Vector2.INF (caller falls back)")

	# --- Case 4: a degenerate zero-length heading (destinations == origin) -> INF. ---
	var dests_zero = _dests_toward(centroid, north_enemy, 0.0)
	_assert(ai._advance_heading_target(_make_unit(centroid), dests_zero, 7.0) == Vector2.INF,
		"zero-length heading returns Vector2.INF")

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	if _fail_count > 0:
		print("SOME TESTS FAILED")
	else:
		print("ALL TESTS PASSED")
	quit(1 if _fail_count > 0 else 0)
