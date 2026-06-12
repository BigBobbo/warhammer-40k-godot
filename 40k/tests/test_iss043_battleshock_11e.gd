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

	print("\n-- wired step behavior (CommandPhase + StratagemManager) --")
	var gs = root.get_node_or_null("GameState")
	var sm = root.get_node_or_null("StratagemManager")
	var prev_state = gs.state.duplicate(true)
	gs.initialize_default_state()
	gs.state["units"]["U_SHOCKED"] = {"id": "U_SHOCKED", "owner": 1,
		"flags": {"battle_shocked": true}, "status": 2,
		"meta": {"name": "Shocked Boyz", "keywords": ["INFANTRY"],
			"stats": {"leadership": 7, "objective_control": 2}},
		"models": [{"id": "m0", "alive": true, "wounds": 1, "current_wounds": 1,
			"position": {"x": 500, "y": 500}, "base_mm": 32, "base_type": "circular"}]}
	gs.state["meta"]["active_player"] = 1
	gs.state["players"]["1"]["cp"] = 10

	# 01.07: battle-shocked units cannot be stratagem targets — discovered
	# during ISS-043 wiring that the existing check already enforces this in
	# BOTH editions (the rule is shared); asserted here so it never regresses.
	GameConstants.edition = 11
	var v = sm.can_use_stratagem(1, "go_to_ground", "U_SHOCKED")
	_check("11e: battle-shocked unit cannot be a stratagem target",
		v.can_use == false, str(v))
	GameConstants.edition = 10
	v = sm.can_use_stratagem(1, "go_to_ground", "U_SHOCKED")
	_check("10e: same ban applies (shared rule, pre-existing check)",
		v.can_use == false, str(v))

	# CommandPhase: shocked unit is queued for a recovery test at 11e and
	# its flag survives the phase start (no auto-clear).
	GameConstants.edition = 11
	var phase = load("res://phases/CommandPhase.gd").new()
	root.add_child(phase)
	phase.game_state_snapshot = gs.create_snapshot()
	phase._clear_battle_shocked_flags()
	_check("11e: battle-shocked flag persists into the step",
		gs.state["units"]["U_SHOCKED"]["flags"]["battle_shocked"] == true)
	phase._units_needing_test.clear()
	phase._identify_units_needing_tests()
	_check("11e: shocked unit queued for a recovery test",
		"U_SHOCKED" in phase._units_needing_test, str(phase._units_needing_test))

	# Recovery: pass the test with a forced roll of 12
	var result = phase.execute_action({"type": "BATTLE_SHOCK_TEST", "unit_id": "U_SHOCKED",
		"player": 1, "dice_roll": [6, 6]})
	_check("recovery test executed", result.get("success", false), str(result))
	_check("11e: passing recovers the unit (flag cleared)",
		gs.state["units"]["U_SHOCKED"]["flags"]["battle_shocked"] == false)

	GameConstants.edition = 10
	root.remove_child(phase)
	phase.free()
	gs.state = prev_state

	print("\n-- outcome --")
	_check("pass -> not shocked (recovery when 11e offered the roll)",
		AttackSequence.battleshock_outcome(true) == false)
	_check("fail -> shocked", AttackSequence.battleshock_outcome(false) == true)

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
