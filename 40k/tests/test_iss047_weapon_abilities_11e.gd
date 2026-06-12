extends SceneTree

# ISS-047 (step 1): 11e weapon-ability primitives.
#   A) 24.01 keyword scoping: [LETHAL HITS: VEHICLE] applies only vs
#      VEHICLE targets; unscoped entries always apply; scope validated.
#   B) 24.05 [BLAST X] worked example: A3 [BLAST 2] vs 12 models -> +4
#      dice (total 7).
#   C) 24.06 [CLEAVE X] worked example: A3 [CLEAVE 1] vs 16 models,
#      single target -> +3 dice (total 6); split targets -> +0.
#
# Usage: godot --headless --path . -s tests/test_iss047_weapon_abilities_11e.gd

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
	print("\n=== test_iss047_weapon_abilities_11e ===\n")

	print("-- A: keyword scoping (24.01) --")
	var lethal_scoped = {"id": "lethal_hits", "scope": ["VEHICLE"]}
	var sustained_scoped = {"id": "sustained_hits", "x": 1, "scope": ["INFANTRY", "BEASTS"]}
	var plain = {"id": "twin_linked"}
	_check("scoped ability applies vs matching keyword",
		AbilityRegistry.entry_applies_to_target(lethal_scoped, ["VEHICLE", "TITANIC"]))
	_check("scoped ability does NOT apply vs non-matching target",
		not AbilityRegistry.entry_applies_to_target(lethal_scoped, ["INFANTRY"]))
	_check("multi-keyword scope: any match applies",
		AbilityRegistry.entry_applies_to_target(sustained_scoped, ["BEASTS"]))
	_check("unscoped ability always applies",
		AbilityRegistry.entry_applies_to_target(plain, []))
	var vs = AbilityRegistry.abilities_vs_target([lethal_scoped, sustained_scoped, plain], ["vehicle"])
	_check("abilities_vs_target filters (case-insensitive)",
		vs.size() == 2 and vs[0].id == "lethal_hits" and vs[1].id == "twin_linked", str(vs))
	_check("scope param accepted by validation",
		AbilityRegistry.validate([lethal_scoped]).is_empty())
	_check("non-array scope rejected by validation",
		not AbilityRegistry.validate([{"id": "lethal_hits", "scope": "VEHICLE"}]).is_empty())

	print("\n-- B: BLAST X (24.05) --")
	_check("[BLAST 2] A3 vs 12 models: +4 dice (worked example)",
		AbilityRegistry.blast_bonus_dice(2, 12) == 4)
	_check("plain [BLAST] vs 11 models: +2", AbilityRegistry.blast_bonus_dice(1, 11) == 2)
	_check("BLAST vs 4 models: +0 (rounds down)", AbilityRegistry.blast_bonus_dice(1, 4) == 0)

	print("\n-- C: CLEAVE X (24.06) --")
	_check("[CLEAVE 1] A3 vs 16 models, single target: +3 (worked example)",
		AbilityRegistry.cleave_bonus_dice(1, 16, true) == 3)
	_check("CLEAVE disabled when attacks were split between targets",
		AbilityRegistry.cleave_bonus_dice(1, 16, false) == 0)
	_check("[CLEAVE 2] vs 10 models single target: +4",
		AbilityRegistry.cleave_bonus_dice(2, 10, true) == 4)

	print("\n-- D: LETHAL HITS is a choice (24.23) --")
	var rules = root.get_node_or_null("RulesEngine")
	var lethal_board = {"units": {"U": {"id": "U", "owner": 1, "flags": {},
		"meta": {"stats": {}, "weapons": [
			{"name": "LGun", "type": "Ranged", "range": "24", "attacks": "2",
				"ballistic_skill": "3", "strength": "4", "ap": "0", "damage": "1",
				"special_rules": "lethal hits"},
			{"name": "LDGun", "type": "Ranged", "range": "24", "attacks": "2",
				"ballistic_skill": "3", "strength": "4", "ap": "0", "damage": "1",
				"special_rules": "lethal hits, devastating wounds"}]},
		"models": []}}, "meta": {}}
	GameConstants.edition = 10
	_check("10e: lethal crits always auto-wound",
		rules.lethal_hits_auto_wound_11e("LDGun", lethal_board, {}))
	GameConstants.edition = 11
	_check("11e: plain lethal weapon defaults to auto-wound",
		rules.lethal_hits_auto_wound_11e("LGun", lethal_board, {}))
	_check("11e: lethal + devastating defaults to ROLL (keeps crit-wound trigger)",
		not rules.lethal_hits_auto_wound_11e("LDGun", lethal_board, {}))
	_check("11e: explicit lethal_hits_choice=auto overrides",
		rules.lethal_hits_auto_wound_11e("LDGun", lethal_board, {"lethal_hits_choice": "auto"}))
	_check("11e: explicit lethal_hits_choice=roll overrides",
		not rules.lethal_hits_auto_wound_11e("LGun", lethal_board, {"lethal_hits_choice": "roll"}))

	print("\n-- E: PRECISION selects the allocation group (24.28) --")
	var prec_models = [
		{"id": "b0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32,
			"base_type": "circular", "position": {"x": 300, "y": 100}},
		{"id": "b1", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32,
			"base_type": "circular", "position": {"x": 300, "y": 135}},
		{"id": "c0", "alive": true, "wounds": 3, "current_wounds": 3, "is_character": true,
			"base_mm": 32, "base_type": "circular", "position": {"x": 300, "y": 170}}]
	var prec_board = {"units": {
		"U_S": {"id": "U_S", "owner": 1, "flags": {},
			"meta": {"name": "S", "keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 3, "wounds": 2},
				"weapons": [{"name": "Sniper", "type": "Ranged", "range": "24", "attacks": "6",
					"ballistic_skill": "3", "strength": "8", "ap": "0", "damage": "1",
					"special_rules": "torrent, precision"}]},
			"models": [{"id": "s0", "alive": true, "wounds": 2, "current_wounds": 2,
				"base_mm": 32, "base_type": "circular", "position": {"x": 100, "y": 100}}]},
		"U_T": {"id": "U_T", "owner": 2, "flags": {},
			"meta": {"name": "T", "keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 7, "wounds": 1}},
			"models": prec_models}}, "meta": {}}
	# Find a seed with exactly 4 wounds from 6 torrent attacks (2+).
	var pseed := -1
	for ps in range(500):
		var pw := 0
		for r in rules.RNGService.new(ps).roll_d6(6):
			if r >= 2:
				pw += 1
		if pw == 4:
			pseed = ps
			break
	_check("precision seed found", pseed != -1)
	var paction = {"type": "SHOOT", "actor_unit_id": "U_S",
		"payload": {"assignments": [{"weapon_id": "Sniper", "target_unit_id": "U_T", "model_ids": ["s0"]}]}}
	var pres = rules.resolve_shoot(paction, prec_board, rules.RNGService.new(pseed))
	_check("PRECISION: the CHARACTER group is the CURRENT group — char dies FIRST (3 wounds), 4th hits a bodyguard",
		prec_board.units["U_T"].models[2].alive == false
		and (prec_board.units["U_T"].models[0].alive == false) != (prec_board.units["U_T"].models[1].alive == false),
		str(prec_board.units["U_T"].models))

	print("\n-- F: PSYCHIC ignores harmful hit-side modifiers (24.29) --")
	var psy_board = {"units": {
		"U_P": {"id": "U_P", "owner": 1, "flags": {},
			"meta": {"name": "P", "keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 3, "wounds": 2},
				"weapons": [{"name": "Witch Bolt", "type": "Ranged", "range": "24", "attacks": "6",
					"ballistic_skill": "3", "strength": "8", "ap": "0", "damage": "1",
					"special_rules": "psychic"}]},
			"models": [{"id": "p0", "alive": true, "wounds": 2, "current_wounds": 2,
				"base_mm": 32, "base_type": "circular", "position": {"x": 100, "y": 100}}]},
		"U_PT": {"id": "U_PT", "owner": 2, "flags": {},
			"meta": {"name": "PT", "keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 7, "wounds": 1},
				"abilities": ["Stealth"]},
			"models": [{"id": "t0", "alive": true, "wounds": 1, "current_wounds": 1,
				"base_mm": 32, "base_type": "circular", "position": {"x": 300, "y": 100}},
				{"id": "t1", "alive": true, "wounds": 1, "current_wounds": 1,
				"base_mm": 32, "base_type": "circular", "position": {"x": 300, "y": 135}}]}},
		"meta": {}}
	var qseed := -1
	var exp_hits3 := 0
	for qs in range(500):
		var hr = rules.RNGService.new(qs).roll_d6(6)
		if 3 in hr:
			qseed = qs
			for r in hr:
				if r >= 3:
					exp_hits3 += 1
			break
	_check("psychic seed found", qseed != -1)
	var qaction = {"type": "SHOOT", "actor_unit_id": "U_P",
		"payload": {"assignments": [{"weapon_id": "Witch Bolt", "target_unit_id": "U_PT", "model_ids": ["p0"]}]}}
	var qres = rules.resolve_shoot(qaction, psy_board, rules.RNGService.new(qseed))
	var qhit = {}
	for d in qres.get("dice", []):
		if d.get("context", "") == "to_hit":
			qhit = d
	_check("PSYCHIC vs STEALTH: cover's BS worsening ignored — hits at unmodified 3+",
		qhit.get("successes", -1) == exp_hits3,
		"successes=%s expected=%d" % [str(qhit.get("successes")), exp_hits3])

	GameConstants.edition = 10
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
