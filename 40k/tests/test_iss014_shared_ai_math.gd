extends SceneTree

# ISS-014: the AI consumes shared rules math (AttackSequence) instead of
# private reimplementations.
#
# Checks:
#   A) Hand-computed probability cases, including the two edge corrections
#      vs. the AI's old local math (nat 1 always fails -> cap 5/6; nat 6
#      always hits -> floor 1/6).
#   B) AIDecisionMaker's wrappers return exactly AttackSequence's values.
#   C) The wound chart exists once: RulesEngine._calculate_wound_threshold
#      delegates to AttackSequence.wound_threshold.
#
# Usage: godot --headless --path . -s tests/test_iss014_shared_ai_math.gd

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

func _eq(a: float, b: float) -> bool:
	return abs(a - b) < 0.0001

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss014_shared_ai_math ===\n")

	print("-- A: hand-computed cases --")
	_check("hit 4+ = 1/2", _eq(AttackSequence.hit_probability(4), 0.5))
	_check("hit 2+ = 5/6", _eq(AttackSequence.hit_probability(2), 5.0 / 6.0))
	_check("hit 1+ capped at 5/6 (nat 1 misses)", _eq(AttackSequence.hit_probability(1), 5.0 / 6.0))
	_check("hit 7+ floors at 1/6 (nat 6 hits)", _eq(AttackSequence.hit_probability(7), 1.0 / 6.0))
	_check("wound S8 vs T4 = 5/6 (2+)", _eq(AttackSequence.wound_probability(8, 4), 5.0 / 6.0))
	_check("wound S5 vs T4 = 4/6 (3+)", _eq(AttackSequence.wound_probability(5, 4), 4.0 / 6.0))
	_check("wound S4 vs T4 = 3/6 (4+)", _eq(AttackSequence.wound_probability(4, 4), 0.5))
	_check("wound S4 vs T5 = 2/6 (5+)", _eq(AttackSequence.wound_probability(4, 5), 2.0 / 6.0))
	_check("wound S3 vs T6 = 1/6 (6+)", _eq(AttackSequence.wound_probability(3, 6), 1.0 / 6.0))
	_check("save 3+ vs AP-1 = 1/2", _eq(AttackSequence.save_probability(3, -1), 0.5))
	_check("save 2+ vs AP0 = 5/6 (nat 1 fails)", _eq(AttackSequence.save_probability(2, 0), 5.0 / 6.0))
	_check("save 4+ vs AP-4 = 0 (no auto-pass)", _eq(AttackSequence.save_probability(4, -4), 0.0))
	_check("invuln 4+ beats AP-3 on 3+ armour", _eq(AttackSequence.save_probability(3, -3, 4), 0.5))

	print("\n-- B: AI wrappers delegate --")
	var ai = load("res://scripts/AIDecisionMaker.gd")
	for skill in range(1, 8):
		if not _eq(ai._hit_probability(skill), AttackSequence.hit_probability(skill)):
			_check("AI hit wrapper matches for %d+" % skill, false)
			break
	_check("AI hit wrapper matches AttackSequence for 1..7", true)
	_check("AI wound wrapper matches", _eq(ai._wound_probability(5, 4), AttackSequence.wound_probability(5, 4)))
	_check("AI save wrapper matches (incl. invuln)", _eq(ai._save_probability(3, -2, 5), AttackSequence.save_probability(3, -2, 5)))

	print("\n-- C: one wound chart --")
	var re_src = FileAccess.get_file_as_string("res://autoloads/RulesEngine.gd")
	_check("RulesEngine wound threshold delegates to AttackSequence",
		re_src.find("return AttackSequence.wound_threshold(strength, toughness)") != -1)
	var ai_src = FileAccess.get_file_as_string("res://scripts/AIDecisionMaker.gd")
	_check("AIDecisionMaker has no local wound chart",
		ai_src.find("return 5.0 / 6.0  # 2+") == -1)

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
