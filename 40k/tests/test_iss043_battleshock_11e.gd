extends SceneTree

# ISS-043: leadership roll + 11e battle-shock step semantics (01.06-01.07,
# 08.03), edition-gated.
#
# Usage: godot --headless --path . -s tests/test_iss043_battleshock_11e.gd

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

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss043_battleshock_11e ===\n")
	var rules = root.get_node_or_null("RulesEngine")

	print("-- leadership roll (2D6 >= Ld) --")
	var unit = {"meta": {"stats": {"leadership": 7}}}
	var r = AttackSequence.leadership_roll(unit, rules.RNGService.new(5))
	_check("returns 2 dice + total", r.dice.size() == 2 and r.total == r.dice[0] + r.dice[1])
	_check("threshold from unit Ld", r.threshold == 7)
	_check("success iff total >= Ld", r.success == (r.total >= 7))
	var stats := {"pass": 0}
	for i in range(2000):
		if AttackSequence.leadership_roll(unit, rules.RNGService.new(10000 + i)).success:
			stats["pass"] += 1
	# P(2D6 >= 7) = 21/36 = 0.5833
	_check("pass rate ~0.583 for Ld 7 (%.3f)" % (stats["pass"] / 2000.0),
		abs(stats["pass"] / 2000.0 - 0.5833) < 0.04)
	_check("default Ld 7 when stats missing",
		AttackSequence.leadership_roll({"meta": {}}, rules.RNGService.new(1)).threshold == 7)

	print("\n-- step eligibility per edition (08.03) --")
	GameConstants.edition = 10
	_check("10e: below half tests", AttackSequence.battleshock_test_required(false, true, false))
	_check("10e: AT half does not test", not AttackSequence.battleshock_test_required(false, false, true))
	_check("10e: already-shocked does not retest", not AttackSequence.battleshock_test_required(true, false, false))
	GameConstants.edition = 11
	_check("11e: below half tests", AttackSequence.battleshock_test_required(false, true, false))
	_check("11e: AT half tests", AttackSequence.battleshock_test_required(false, false, true))
	_check("11e: already-shocked RETESTS (recovery path)", AttackSequence.battleshock_test_required(true, false, false))
	_check("11e: full-strength unshocked does not test", not AttackSequence.battleshock_test_required(false, false, false))
	GameConstants.edition = 10

	print("\n-- outcome --")
	_check("pass -> not shocked (recovery when 11e offered the roll)",
		AttackSequence.battleshock_outcome(true) == false)
	_check("fail -> shocked", AttackSequence.battleshock_outcome(false) == true)

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
