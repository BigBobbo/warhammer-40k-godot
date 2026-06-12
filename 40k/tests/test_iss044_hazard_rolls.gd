extends SceneTree

# ISS-044: 11e hazard roll primitive (core rules 06.03).
# D6 per roll, simultaneous; 1-2 fails -> 1 MW (3 MW if every model in the
# unit is MONSTER/VEHICLE).
#
# Usage: godot --headless --path . -s tests/test_iss044_hazard_rolls.gd

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
	print("\n=== test_iss044_hazard_rolls ===\n")
	var rules = root.get_node_or_null("RulesEngine")

	var infantry = {"meta": {"keywords": ["INFANTRY"]},
		"models": [{"id": "m0", "alive": true}, {"id": "m1", "alive": true}]}
	var vehicle = {"meta": {"keywords": ["VEHICLE"]},
		"models": [{"id": "m0", "alive": true}]}
	var mixed = {"meta": {"keywords": []},
		"models": [{"id": "m0", "alive": true, "keywords": ["VEHICLE"]},
			{"id": "m1", "alive": true, "keywords": ["INFANTRY"]}]}

	# Statistical: over 600 seeded rolls, failure rate ~= 2/6.
	var rng = rules.RNGService.new(777)
	var res = AttackSequence.hazard_rolls(infantry, 600, rng)
	_check("rolls all returned (simultaneous batch)", res.rolls.size() == 600)
	_check("fail band is 1-2 (rate %.3f within [0.28, 0.39])" % (res.failures / 600.0),
		res.failures / 600.0 > 0.28 and res.failures / 600.0 < 0.39)
	_check("infantry: 1 MW per failure", res.mortal_wounds == res.failures and res.per_model_mw == 1)

	# Determinism: same seed -> same rolls
	var res2 = AttackSequence.hazard_rolls(infantry, 600, rules.RNGService.new(777))
	_check("deterministic with same seed", res2.rolls == res.rolls)

	# All-MONSTER/VEHICLE unit: 3 MW per failure
	var resv = AttackSequence.hazard_rolls(vehicle, 60, rules.RNGService.new(42))
	_check("all-VEHICLE unit: 3 MW per failure",
		resv.per_model_mw == 3 and resv.mortal_wounds == resv.failures * 3)

	# Mixed unit: NOT every model is M/V -> 1 MW per failure
	var resm = AttackSequence.hazard_rolls(mixed, 60, rules.RNGService.new(42))
	_check("mixed unit: 1 MW per failure", resm.per_model_mw == 1)

	# Exact roll check vs raw RNG: identical seed, identical D6 stream
	var raw = rules.RNGService.new(99).roll_d6(10)
	var rh = AttackSequence.hazard_rolls(infantry, 10, rules.RNGService.new(99))
	var expected_failures := 0
	for r in raw:
		if r <= 2:
			expected_failures += 1
	_check("uses the unit's D6 stream exactly", rh.rolls == raw and rh.failures == expected_failures)

	_check("zero count is a clean no-op",
		AttackSequence.hazard_rolls(infantry, 0, rules.RNGService.new(1)).mortal_wounds == 0)

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
