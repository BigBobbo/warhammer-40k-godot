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

	print("\n-- E2: PRECISION visibility gate + attacker choice (24.28, audit #13) --")
	# The character must be VISIBLE to an attacking model. A tall wall hides
	# ONLY the character (bodyguard b0 stays clear, so the unit is still a
	# legal target) — the promotion must NOT happen and the char survives.
	var tm = root.get_node_or_null("TerrainManager")
	var prev_tf = tm.terrain_features.duplicate(true)
	var prec_wall = {"id": "prec_wall", "type": "ruins", "height_category": "tall",
		"polygon": PackedVector2Array([Vector2(270, 120), Vector2(290, 120), Vector2(290, 220), Vector2(270, 220)])}
	tm.terrain_features = [prec_wall]
	var prec_board2 = {"units": {
		"U_S": {"id": "U_S", "owner": 1, "flags": {},
			"meta": {"name": "S", "keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 3, "wounds": 2},
				"weapons": prec_board.units["U_S"].meta.weapons},
			"models": [{"id": "s0", "alive": true, "wounds": 2, "current_wounds": 2,
				"base_mm": 32, "base_type": "circular", "position": {"x": 100, "y": 100}}]},
		"U_T": {"id": "U_T", "owner": 2, "flags": {},
			"meta": {"name": "T", "keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 7, "wounds": 1}},
			"models": [
				{"id": "b0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32,
					"base_type": "circular", "position": {"x": 300, "y": 100}},
				{"id": "b1", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32,
					"base_type": "circular", "position": {"x": 300, "y": 135}},
				{"id": "c0", "alive": true, "wounds": 3, "current_wounds": 3, "is_character": true,
					"base_mm": 32, "base_type": "circular", "position": {"x": 300, "y": 170}}]}},
		"meta": {}, "terrain_features": [prec_wall]}
	_check("wall hides the character from the shooter (setup sanity)",
		not tm.model_visible_11e(prec_board2.units["U_S"].models[0], prec_board2.units["U_T"].models[2]))
	_check("visibility gate: hidden character -> no promotion",
		rules._precision_group_11e(true, prec_board2.units["U_T"],
			prec_board2.units["U_S"], prec_board2, "") == "")
	var pres2 = rules.resolve_shoot(paction, prec_board2, rules.RNGService.new(pseed))
	_check("hidden character SURVIVES a PRECISION volley (wounds fall on bodyguards)",
		prec_board2.units["U_T"].models[2].alive == true
		and prec_board2.units["U_T"].models[0].alive == false
		and prec_board2.units["U_T"].models[1].alive == false,
		str(prec_board2.units["U_T"].models))
	tm.terrain_features = prev_tf

	# Attacker CHOICE: two visible character groups — chosen_gid wins.
	var choice_unit = {"id": "U_C2", "owner": 2, "flags": {},
		"meta": {"name": "C2", "keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 7, "wounds": 1}},
		"models": [
			{"id": "b0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32,
				"base_type": "circular", "position": {"x": 300, "y": 100}},
			{"id": "cA", "alive": true, "wounds": 3, "current_wounds": 3, "is_character": true,
				"base_mm": 32, "base_type": "circular", "position": {"x": 300, "y": 140}},
			{"id": "cB", "alive": true, "wounds": 3, "current_wounds": 3, "is_character": true,
				"base_mm": 32, "base_type": "circular", "position": {"x": 300, "y": 180}}]}
	var choice_board = {"units": {"U_S": prec_board.units["U_S"], "U_C2": choice_unit}, "meta": {}}
	var default_pick = rules._precision_group_11e(true, choice_unit, prec_board.units["U_S"], choice_board, "")
	var chosen_pick = rules._precision_group_11e(true, choice_unit, prec_board.units["U_S"], choice_board, "char_2")
	_check("auto-pick takes the first visible CHARACTER group", default_pick == "char_1", default_pick)
	_check("attacker's chosen group wins when eligible", chosen_pick == "char_2", chosen_pick)
	_check("bogus chosen group falls back to auto-pick",
		rules._precision_group_11e(true, choice_unit, prec_board.units["U_S"], choice_board, "grp_nope") == "char_1")

	print("\n-- E3: DEVASTATING WOUNDS is a CHOICE (24.10, audit #17) --")
	# Torrent DW gun vs a 2+ save target: by default a critical wound becomes
	# mortal wounds (bypasses the save, dice block context devastating_wounds_11e);
	# with devastating_wounds_choice="normal" the crit rolls a normal save.
	var dw_maker = func() -> Dictionary:
		return {"units": {
			"U_S": {"id": "U_S", "owner": 1, "flags": {},
				"meta": {"name": "S", "keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 3, "wounds": 2},
					"weapons": [{"name": "DWGun", "type": "Ranged", "range": "24", "attacks": "6",
						"ballistic_skill": "3", "strength": "8", "ap": "0", "damage": "2",
						"special_rules": "torrent, devastating wounds"}]},
				"models": [{"id": "s0", "alive": true, "wounds": 2, "current_wounds": 2,
					"base_mm": 32, "base_type": "circular", "position": {"x": 100, "y": 100}}]},
			"U_T": {"id": "U_T", "owner": 2, "flags": {},
				"meta": {"name": "T", "keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 2, "wounds": 4}},
				"models": [{"id": "t0", "alive": true, "wounds": 4, "current_wounds": 4,
					"base_mm": 32, "base_type": "circular", "position": {"x": 300, "y": 100}}]}},
			"meta": {}}
	# Seed with at least one 6 among the first 6 wound rolls (torrent skips hit rolls).
	var dwseed := -1
	for ds in range(500):
		var has6 := false
		for r in rules.RNGService.new(ds).roll_d6(6):
			if r == 6:
				has6 = true
		if has6:
			dwseed = ds
			break
	_check("DW seed found", dwseed != -1)
	var dw_action_default = {"type": "SHOOT", "actor_unit_id": "U_S",
		"payload": {"assignments": [{"weapon_id": "DWGun", "target_unit_id": "U_T", "model_ids": ["s0"]}]}}
	var dw_board1 = dw_maker.call()
	var dw_res1 = rules.resolve_shoot(dw_action_default, dw_board1, rules.RNGService.new(dwseed))
	var dw_block1 := false
	for d in dw_res1.get("dice", []):
		if str(d.get("context", "")) == "devastating_wounds_11e":
			dw_block1 = true
	_check("default: critical wound converts to mortal wounds (devastating dice block present)",
		dw_block1, str(dw_res1.get("dice", [])))
	var dw_action_normal = {"type": "SHOOT", "actor_unit_id": "U_S",
		"payload": {"assignments": [{"weapon_id": "DWGun", "target_unit_id": "U_T", "model_ids": ["s0"],
			"devastating_wounds_choice": "normal"}]}}
	var dw_board2 = dw_maker.call()
	var dw_res2 = rules.resolve_shoot(dw_action_normal, dw_board2, rules.RNGService.new(dwseed))
	var dw_block2 := false
	for d in dw_res2.get("dice", []):
		if str(d.get("context", "")) == "devastating_wounds_11e":
			dw_block2 = true
	_check("choice=normal: no mortal-wound conversion (crits roll normal saves)",
		not dw_block2, str(dw_res2.get("dice", [])))

	print("\n-- E4: damage modifier ORDER pins (audit #12: + before \u00f7 before \u2212) --")
	# Melta +2 on a D6 weapon vs a half-damage defender: 6+2=8 -> halve -> 4.
	# The wrong order (halve first) would give halve(6)=3, +2 = 5.
	var ord_board = {"units": {
		"U_S": {"id": "U_S", "owner": 1, "flags": {},
			"meta": {"name": "S", "keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 3, "wounds": 2},
				"weapons": [{"name": "MeltaGun", "type": "Ranged", "range": "24", "attacks": "1",
					"ballistic_skill": "3", "strength": "8", "ap": "0", "damage": "6",
					"special_rules": "torrent, melta 2"}]},
			"models": [{"id": "s0", "alive": true, "wounds": 2, "current_wounds": 2,
				"base_mm": 32, "base_type": "circular", "position": {"x": 100, "y": 100}}]},
		"U_T": {"id": "U_T", "owner": 2, "flags": {},
			"meta": {"name": "T", "keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 7, "wounds": 20, "half_damage": true}},
			"models": [{"id": "t0", "alive": true, "wounds": 20, "current_wounds": 20,
				"base_mm": 32, "base_type": "circular", "position": {"x": 200, "y": 100}}]}},
		"meta": {}}
	# Seed where the single wound roll is >= 2 (S8 vs T4 wounds on 2+).
	var oseed := -1
	for osd in range(200):
		if rules.RNGService.new(osd).roll_d6(1)[0] >= 2:
			oseed = osd
			break
	_check("order seed found", oseed != -1)
	var ord_action = {"type": "SHOOT", "actor_unit_id": "U_S",
		"payload": {"assignments": [{"weapon_id": "MeltaGun", "target_unit_id": "U_T", "model_ids": ["s0"]}]}}
	rules.resolve_shoot(ord_action, ord_board, rules.RNGService.new(oseed))
	var t_cw = int(ord_board.units["U_T"].models[0].get("current_wounds", 20))
	_check("halve applies AFTER melta: 20W target drops to exactly 16 (6+2 -> 4), not 15",
		t_cw == 16, "current_wounds=%d" % t_cw)

	print("\n-- E5: [EXTRA ATTACKS] modifiable at e11 (audit #14) --")
	# Waaagh! grants +1 melee attack. 10e Balance Dataslate suppressed it on
	# EXTRA ATTACKS weapons; 11e removes the restriction. Count hit rolls.
	var ea_maker = func() -> Dictionary:
		return {"units": {
			"U_EA": {"id": "U_EA", "owner": 1, "flags": {"waaagh_active": true},
				"meta": {"name": "EA", "keywords": ["INFANTRY", "ORKS"],
					"stats": {"toughness": 4, "save": 3, "wounds": 2},
					"weapons": [{"name": "Tusks", "type": "Melee", "range": "Melee", "attacks": "2",
						"weapon_skill": "3", "strength": "4", "ap": "0", "damage": "1",
						"special_rules": "extra attacks"}]},
				"models": [{"id": "e0", "alive": true, "wounds": 2, "current_wounds": 2,
					"base_mm": 32, "base_type": "circular", "position": {"x": 100, "y": 100}}]},
			"U_D": {"id": "U_D", "owner": 2, "flags": {},
				"meta": {"name": "D", "keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 7, "wounds": 4}},
				"models": [{"id": "d0", "alive": true, "wounds": 4, "current_wounds": 4,
					"base_mm": 32, "base_type": "circular", "position": {"x": 130, "y": 100}}]}},
			"meta": {}}
	var ea_action = {"type": "FIGHT", "actor_unit_id": "U_EA",
		"payload": {"assignments": [{"attacker": "U_EA", "weapon": "Tusks", "target": "U_D", "models": ["0"]}]}}
	var ea_hit_count = func(res: Dictionary) -> int:
		for d in res.get("dice", []):
			if str(d.get("context", "")) == "hit_roll_melee":
				return d.get("rolls_raw", d.get("rolls", [])).size()
		return -1
	GameConstants.edition = 10
	var ea_res10 = rules.resolve_melee_attacks(ea_action, ea_maker.call(), rules.RNGService.new(7))
	var ea_n10 = ea_hit_count.call(ea_res10)
	GameConstants.edition = 11
	var ea_res11 = rules.resolve_melee_attacks(ea_action, ea_maker.call(), rules.RNGService.new(7))
	var ea_n11 = ea_hit_count.call(ea_res11)
	_check("10e: Waaagh +1A suppressed on EXTRA ATTACKS (2 hit rolls)", ea_n10 == 2, "got %d" % ea_n10)
	_check("11e: EXTRA ATTACKS takes the modifier (3 hit rolls)", ea_n11 == 3, "got %d" % ea_n11)

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
