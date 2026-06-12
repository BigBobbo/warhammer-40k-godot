extends SceneTree

# ISS-056 (step 1): 11e per-unit stratagem restriction (15.01) — each
# player cannot target the same unit with more than one stratagem in the
# same phase. Edition-gated: 10e behavior unchanged.
#
# Usage: godot --headless --path . -s tests/test_iss056_stratagem_per_unit.gd

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
	print("\n=== test_iss056_stratagem_per_unit ===\n")
	var sm = root.get_node_or_null("StratagemManager")
	var gs = root.get_node_or_null("GameState")
	if sm == null or gs == null:
		_check("autoloads reachable", false)
		print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
		quit(1)
		return

	var prev_hist = sm._usage_history.duplicate(true)
	sm._usage_history = {"1": [], "2": []}
	var turn = gs.get_battle_round()
	var phase = gs.get_current_phase()

	# Simulate: player 1 already used a stratagem on U_TARGET this phase.
	sm._usage_history["1"].append({"stratagem_id": "go_to_ground", "player": 1,
		"target_unit_id": "U_TARGET", "turn": turn, "phase": phase, "timestamp": 0})
	# Give player 1 plenty of CP so cost checks pass.
	gs.state["players"]["1"]["cp"] = 10

	GameConstants.edition = 11
	var v = sm.can_use_stratagem(1, "command_re_roll_11e", "U_TARGET")
	_check("11e: second stratagem on the same unit this phase is refused",
		v.can_use == false and "15.01" in str(v.reason), str(v))
	v = sm.can_use_stratagem(1, "command_re_roll_11e", "U_OTHER")
	_check("11e: a different unit is fine", v.can_use, str(v))
	v = sm.can_use_stratagem(2, "command_re_roll_11e", "U_TARGET")
	# player 2 has their own budget per 15.01 ("each player")
	gs.state["players"]["2"]["cp"] = 10
	v = sm.can_use_stratagem(2, "command_re_roll_11e", "U_TARGET")
	_check("11e: the restriction is per player", v.can_use, str(v))

	# A different phase clears it
	sm._usage_history["1"][0]["phase"] = phase + 1 if phase < 12 else phase - 1
	v = sm.can_use_stratagem(1, "command_re_roll_11e", "U_TARGET")
	_check("11e: usage in a different phase does not block", v.can_use, str(v))
	sm._usage_history["1"][0]["phase"] = phase

	GameConstants.edition = 10
	v = sm.can_use_stratagem(1, "command_re_roll", "U_TARGET")
	_check("10e: behavior unchanged (no per-unit restriction)", v.can_use, str(v))
	GameConstants.edition = 10

	sm._usage_history = prev_hist
	print("\n-- 11e core set (15.02-15.12) --")
	var rules = root.get_node_or_null("RulesEngine")
	_check("11e core definitions registered (incl. COUNTEROFFENSIVE at 2CP)",
		sm.stratagems.has("explosives") and sm.stratagems.has("crushing_impact")
		and sm.stratagems.has("counteroffensive_11e")
		and sm.stratagems["counteroffensive_11e"].cp_cost == 2
		and sm.stratagems.has("heroic_intervention_11e")
		and sm.stratagems["heroic_intervention_11e"].effects[0].modes == ["leap_to_defend", "into_the_fray"])
	GameConstants.edition = 10
	_check("edition 10: 11e entries unavailable",
		not sm.can_use_stratagem(1, "explosives", "").can_use)
	GameConstants.edition = 11
	var r10 = sm.can_use_stratagem(1, "grenade", "")
	_check("edition 11: reworked 10e core entries retired",
		not r10.can_use and "retired" in r10.reason, str(r10))

	print("\n-- EXPLOSIVES (15.05) + CRUSHING IMPACT (15.06) dice effects --")
	var board = {"units": {
		"U_TANK": {"id": "U_TANK", "owner": 1, "flags": {},
			"meta": {"keywords": ["VEHICLE"], "stats": {"toughness": 10, "wounds": 12}},
			"models": [{"id": "t0", "alive": true, "wounds": 12, "current_wounds": 12,
				"base_mm": 100, "base_type": "circular", "position": {"x": 400, "y": 400}}]},
		"U_FOE": {"id": "U_FOE", "owner": 2, "flags": {},
			"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": 4, "wounds": 1}},
			"models": [
				{"id": "f0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32,
					"base_type": "circular", "position": {"x": 470, "y": 400}},
				{"id": "f1", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32,
					"base_type": "circular", "position": {"x": 470, "y": 435}},
				{"id": "f2", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32,
					"base_type": "circular", "position": {"x": 470, "y": 470}}]},
	}, "meta": {}}
	# Replicate the 6D6 to know the expected mortal wounds.
	var eseed := 17
	var erolls = rules.RNGService.new(eseed).roll_d6(6)
	var emw := 0
	for r in erolls:
		if r >= 4:
			emw += 1
	var eres = rules.resolve_explosives_11e("U_FOE", board, rules.RNGService.new(eseed))
	_check("EXPLOSIVES: 6D6, each 4+ = 1 MW (rolled %s -> %d)" % [str(erolls), emw],
		eres.mortal_wounds == emw and eres.casualties == mini(emw, 3), str(eres))

	# Crushing Impact: find a seed whose 10 dice include 1s AND >6 fives+
	# to prove BOTH directions and the 6-MW cap.
	var cseed := -1
	var c_self := 0
	var c_enemy := 0
	for cs in range(5000):
		var probe = rules.RNGService.new(cs).roll_d6(10)
		var ones := 0
		var fives := 0
		for r in probe:
			if r == 1:
				ones += 1
			elif r >= 5:
				fives += 1
		if ones >= 1 and fives >= 7:
			cseed = cs
			c_self = mini(ones, 6)
			c_enemy = mini(fives, 6)
			break
	_check("crushing-impact seed found (1s + >6 fives)", cseed != -1)
	var board2 = board.duplicate(true)
	var cres = rules.resolve_crushing_impact_11e("U_TANK", "U_FOE", board2, rules.RNGService.new(cseed))
	_check("CRUSHING IMPACT: T dice — 1s wound SELF, 5+ wound the enemy, capped at 6 (self=%d enemy=%d)" % [c_self, c_enemy],
		cres.self_mortals == c_self and cres.enemy_mortals == c_enemy, str(cres))
	_check("self mortal wounds landed on the tank",
		int(board2.units["U_TANK"].models[0].current_wounds) == 12 - c_self,
		str(board2.units["U_TANK"].models[0]))

	GameConstants.edition = 10
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
