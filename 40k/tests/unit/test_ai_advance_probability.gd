extends SceneTree

# ADV-PROB: a long trip Advances when the D6 roll has a real chance to arrive a
# whole turn sooner, not only when the MEAN roll does. Found by the old-vs-new
# benchmark (2026-10-29): with REACH-CR's gap to control range, an 11" gap at
# M6 is 2 turns walking and 2 turns at the mean Advance, so units walked — but
# a 5+ arrives this turn and scores at the next Command phase. The plan held
# ~1.05 objectives at the round-2 scoring against 2.65 for the previous AI.
# Run with: godot --headless --path . -s tests/unit/test_ai_advance_probability.gd

const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== Advance probability (ADV-PROB) ===\n")
	test_sum_d6_probabilities()
	test_long_trip_advance()
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func test_sum_d6_probabilities() -> void:
	_assert(is_equal_approx(AIDecisionMaker._prob_sum_d6_at_least(1, 5.0), 2.0 / 6.0), "one D6 >= 5 is 2/6")
	_assert(is_equal_approx(AIDecisionMaker._prob_sum_d6_at_least(1, 4.2), 2.0 / 6.0), "one D6 >= 4.2 needs a 5+ (2/6)")
	_assert(is_equal_approx(AIDecisionMaker._prob_sum_d6_at_least(2, 12.0), 1.0 / 36.0), "two D6 >= 12 is 1/36")
	_assert(is_equal_approx(AIDecisionMaker._prob_sum_d6_at_least(0, 0.0), 1.0), "no roll needed: certain")

func test_long_trip_advance() -> void:
	# 14" from the marker = 10.2" gap to control range at M6: 2 turns either way
	# at the mean, but a 5+ arrives this turn (1/3).
	_assert(AIDecisionMaker._long_trip_advance_saves_turn(10.2, 6.0), "10.2\" gap at M6 Advances (5+ arrives this turn)")
	# 11.5" gap at M6 needs a 6 (1/6): below the 0.3 threshold, walk.
	_assert(not AIDecisionMaker._long_trip_advance_saves_turn(11.5, 6.0), "11.5\" gap at M6 walks (needs a 6)")
	# Within one move: no Advance needed.
	_assert(not AIDecisionMaker._long_trip_advance_saves_turn(5.0, 6.0), "a gap within one move does not Advance")
	# 20" at M6: 4 turns walking, 3 Advances need only 2" from 3D6.
	_assert(AIDecisionMaker._long_trip_advance_saves_turn(20.0, 6.0), "20\" gap at M6 Advances (3 Advances save a turn)")
