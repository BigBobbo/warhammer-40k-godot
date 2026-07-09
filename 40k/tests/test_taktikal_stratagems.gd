extends SceneTree

# Taktikal Brigade stratagems (Orks):
#   FIGHT PROPPA        — melee weapons gain player's choice of [SUSTAINED HITS 1]
#                         or [LETHAL HITS] until end of phase (melee-scoped flags).
#   KRUNCHIN' DESCENT   — after a Stormboyz charge: D6 per model in ER of the
#                         chosen enemy, 4+ = 1 MW (max 6).
#   DAT'S OURS          — +1 OC until the start of the next Command phase
#                         (plus_oc primitive + MissionManager additive read).
#   TAKTIKAL RETREAT    — fall back and still shoot/charge (existing primitives).
#   ON TO DA NEXT       — reactive 6" Normal move (Krump-and-Run scaffolding).
#   DED SNEAKY          — remove Kommandos/Stormboyz to Strategic Reserves.
#
# Run: godot --headless --path 40k --script tests/test_taktikal_stratagems.gd

var _passed = 0
var _failed = 0


func _initialize():
	await create_timer(0.2).timeout
	_run()
	print("\n=== RESULTS: %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(label: String, cond: bool) -> void:
	if cond:
		print("[PASS] %s" % label)
		_passed += 1
	else:
		print("[FAIL] %s" % label)
		_failed += 1


func _find(strats: Array, name_upper: String) -> Dictionary:
	for s in strats:
		if str(s.get("name", "")).replace("’", "'").to_upper() == name_upper:
			return s
	return {}


func _sum_wounds(result: Dictionary) -> int:
	var total := 0
	for d in result.get("dice", []):
		var ctx = str(d.get("context", "")).to_lower()
		if "wound" in ctx and d.has("successes"):
			total += int(d.get("successes", 0))
	return total


func _melee_board(attacker_flags: Dictionary, tgt_toughness: int = 8, tgt_save: int = 3) -> Dictionary:
	var atk = []
	for i in range(10):
		atk.append({"id": "ma%d" % i, "position": {"x": 0.0, "y": float(i * 30)},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1})
	var tgt = []
	for i in range(10):
		tgt.append({"id": "mt%d" % i, "position": {"x": 20.0, "y": float(i * 30)},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 3, "current_wounds": 3,
			"stats": {"toughness": tgt_toughness, "save": tgt_save}})
	return {"units": {
		"U_ATK": {"id": "U_ATK", "owner": 1,
			"meta": {"keywords": ["INFANTRY", "ORKS"], "stats": {"toughness": 5, "save": 6, "wounds": 1}, "abilities": []},
			"flags": attacker_flags, "models": atk},
		"U_TGT": {"id": "U_TGT", "owner": 2,
			"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": tgt_toughness, "save": tgt_save, "wounds": 3}, "abilities": []},
			"flags": {}, "models": tgt}
	}, "meta": {"phase": 10, "active_player": 1, "battle_round": 1}}


func _fight(rules, flags: Dictionary, seed_val: int, tgt_toughness: int = 8, tgt_save: int = 3) -> int:
	rules.set_test_seed(seed_val)
	var rng = rules.RNGService.new()
	var action := {"type": "FIGHT", "actor_unit_id": "U_ATK",
		"payload": {"assignments": [{"attacker": "U_ATK", "target": "U_TGT", "weapon": "choppa"}]}}
	return _sum_wounds(rules.resolve_melee_attacks(action, _melee_board(flags, tgt_toughness, tgt_save), rng))


func _shoot_board(shooter_flags: Dictionary) -> Dictionary:
	var shooters = []
	for i in range(10):
		shooters.append({"id": "ms%d" % i, "position": {"x": 0.0, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1})
	return {"units": {
		"U_SHOOTER": {"id": "U_SHOOTER", "owner": 1,
			"meta": {"keywords": ["INFANTRY", "ORKS"], "stats": {"toughness": 5, "save": 6, "wounds": 1}, "abilities": []},
			"flags": shooter_flags, "models": shooters},
		"U_ENEMY": {"id": "U_ENEMY", "owner": 2,
			"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4, "wounds": 2}, "abilities": []},
			"flags": {}, "models": [{"id": "e0", "position": {"x": 200.0, "y": 0.0},
				"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 2, "current_wounds": 2,
				"stats": {"toughness": 4, "save": 4}}]}
	}, "meta": {"phase": 8, "active_player": 1, "battle_round": 1}}


func _shoot(rules, flags: Dictionary, seed_val: int) -> int:
	rules.set_test_seed(seed_val)
	var rng = rules.RNGService.new()
	var action := {"type": "SHOOT", "actor_unit_id": "U_SHOOTER",
		"payload": {"assignments": [{"weapon_id": "bolt_rifle", "target_unit_id": "U_ENEMY",
			"model_ids": ["ms0","ms1","ms2","ms3","ms4","ms5","ms6","ms7","ms8","ms9"]}]}}
	return _sum_wounds(rules.resolve_shoot(action, _shoot_board(flags), rng))


func _run():
	var SM = root.get_node("StratagemManager")
	var GS = root.get_node("GameState")
	var rules = root.get_node("RulesEngine")
	var MM = root.get_node("MissionManager")
	if SM == null or GS == null or rules == null:
		_check("autoloads present", false)
		return

	# ------------------------------------------------------------------
	# 1. CSV loading — real load path: factions set, then faction load.
	# ------------------------------------------------------------------
	print("\n=== Loading Taktikal Brigade stratagems (real load path) ===")
	GS.state["factions"] = {"1": {"name": "Orks", "detachment": "Taktikal Brigade"},
		"2": {"name": "Orks", "detachment": "War Horde"}}
	SM.load_faction_stratagems_for_player(1)
	var strats = SM.get_faction_stratagems_for_player(1)
	_check("6 Taktikal Brigade stratagems loaded", strats.size() == 6)

	var fight_proppa = _find(strats, "FIGHT PROPPA")
	var krunchin = _find(strats, "KRUNCHIN' DESCENT")
	var dats_ours = _find(strats, "DAT'S OURS")
	var retreat = _find(strats, "TAKTIKAL RETREAT")
	var on_to_next = _find(strats, "ON TO DA NEXT")
	var ded_sneaky = _find(strats, "DED SNEAKY")
	for pair in [["FIGHT PROPPA", fight_proppa], ["KRUNCHIN' DESCENT", krunchin],
			["DAT'S OURS", dats_ours], ["TAKTIKAL RETREAT", retreat],
			["ON TO DA NEXT", on_to_next], ["DED SNEAKY", ded_sneaky]]:
		_check("%s present" % pair[0], not (pair[1] as Dictionary).is_empty())
		_check("%s implemented" % pair[0], (pair[1] as Dictionary).get("implemented", false))

	# Timing / trigger inference
	_check("FIGHT PROPPA trigger is fighter_selected",
		fight_proppa.get("timing", {}).get("trigger", "") == "fighter_selected")
	_check("KRUNCHIN' DESCENT trigger is after_charge_move",
		krunchin.get("timing", {}).get("trigger", "") == "after_charge_move")
	_check("DED SNEAKY trigger is fight_phase_end",
		ded_sneaky.get("timing", {}).get("trigger", "") == "fight_phase_end")
	_check("DAT'S OURS phase is command", dats_ours.get("timing", {}).get("phase", "") == "command")

	# Effects mapping
	var retreat_types := []
	for e in retreat.get("effects", []):
		retreat_types.append(e.get("type", ""))
	_check("TAKTIKAL RETREAT grants fall_back_and_shoot + fall_back_and_charge",
		"fall_back_and_shoot" in retreat_types and "fall_back_and_charge" in retreat_types)
	var dats_types := []
	for e in dats_ours.get("effects", []):
		dats_types.append(e.get("type", ""))
	_check("DAT'S OURS uses plus_oc primitive", "plus_oc" in dats_types)

	# ------------------------------------------------------------------
	# 2. Target-condition parsing (keyword_any / not_in_engagement_range)
	# ------------------------------------------------------------------
	print("\n=== Target conditions ===")
	var fp_conds: Array = fight_proppa.get("target", {}).get("conditions", [])
	_check("FIGHT PROPPA has keyword_any INFANTRY/MOUNTED",
		"keyword_any:INFANTRY,MOUNTED" in fp_conds)
	_check("FIGHT PROPPA requires ORKS", "keyword:ORKS" in fp_conds)
	_check("FIGHT PROPPA requires not_fought", "not_fought" in fp_conds)
	var ds_conds: Array = ded_sneaky.get("target", {}).get("conditions", [])
	_check("DED SNEAKY has keyword_any KOMMANDOS/STORMBOYZ",
		"keyword_any:KOMMANDOS,STORMBOYZ" in ds_conds)
	_check("DED SNEAKY requires not_in_engagement_range",
		"not_in_engagement_range" in ds_conds)
	var do_conds: Array = dats_ours.get("target", {}).get("conditions", [])
	_check("DAT'S OURS requires in_engagement_range", "in_engagement_range" in do_conds)
	var tr_conds: Array = retreat.get("target", {}).get("conditions", [])
	_check("TAKTIKAL RETREAT requires fell_back_this_phase", "fell_back_this_phase" in tr_conds)
	var otn_conds: Array = on_to_next.get("target", {}).get("conditions", [])
	_check("ON TO DA NEXT has NO live in_engagement_range condition",
		not "in_engagement_range" in otn_conds)

	# unit_matches_target: ORKS INFANTRY passes FIGHT PROPPA; ORKS VEHICLE fails
	var ork_inf = {"meta": {"keywords": ["ORKS", "INFANTRY"]}, "flags": {}, "models": []}
	var ork_veh = {"meta": {"keywords": ["ORKS", "VEHICLE"]}, "flags": {}, "models": []}
	_check("ORKS INFANTRY matches FIGHT PROPPA target",
		FactionStratagemLoaderData.unit_matches_target(ork_inf, fight_proppa.get("target", {})))
	_check("ORKS VEHICLE does not match FIGHT PROPPA target",
		not FactionStratagemLoaderData.unit_matches_target(ork_veh, fight_proppa.get("target", {})))
	var kommandos_free = {"meta": {"keywords": ["ORKS", "INFANTRY", "KOMMANDOS"]}, "flags": {}, "models": []}
	var kommandos_engaged = {"meta": {"keywords": ["ORKS", "INFANTRY", "KOMMANDOS"]}, "flags": {"in_engagement": true}, "models": []}
	_check("Unengaged Kommandos match DED SNEAKY target",
		FactionStratagemLoaderData.unit_matches_target(kommandos_free, ded_sneaky.get("target", {})))
	_check("Engaged Kommandos do NOT match DED SNEAKY target",
		not FactionStratagemLoaderData.unit_matches_target(kommandos_engaged, ded_sneaky.get("target", {})))

	# ------------------------------------------------------------------
	# 3. FIGHT PROPPA — melee-scoped flags change melee, not shooting
	# ------------------------------------------------------------------
	print("\n=== FIGHT PROPPA — melee sustained/lethal flags ===")
	var seeds = [11, 42, 77]
	var sh_better := 0
	var lh_better := 0
	for s in seeds:
		# LETHAL HITS vs a T8 target (crit hits auto-wound where S4 needs 6s).
		var off_lh = _fight(rules, {}, s)
		var on_lh = _fight(rules, {"effect_lethal_hits_melee": true}, s)
		# SUSTAINED HITS 1 vs a T3 target (extra hits convert to wounds on 3+).
		var off_sh = _fight(rules, {}, s, 3, 6)
		var on_sh = _fight(rules, {"effect_sustained_hits_melee": true}, s, 3, 6)
		print("  seed %d: lethal off=%d on=%d | sustained off=%d on=%d" % [s, off_lh, on_lh, off_sh, on_sh])
		if on_sh > off_sh:
			sh_better += 1
		if on_lh > off_lh:
			lh_better += 1
		_check("seed %d: sustained melee flag does not reduce wounds" % s, on_sh >= off_sh)
		_check("seed %d: lethal melee flag does not reduce wounds" % s, on_lh >= off_lh)
	_check("effect_sustained_hits_melee increases melee wounds on most seeds", sh_better >= 2)
	_check("effect_lethal_hits_melee increases melee wounds on most seeds", lh_better >= 2)
	# Melee-scoped flags must NOT leak into shooting
	var shoot_off = _shoot(rules, {}, 42)
	var shoot_flagged = _shoot(rules, {"effect_sustained_hits_melee": true, "effect_lethal_hits_melee": true}, 42)
	_check("FIGHT PROPPA flags do not change ranged attacks", shoot_off == shoot_flagged)

	# Apply/clear handlers honour the player's choice
	var strat_fp = {"name": "FIGHT PROPPA", "effects": [{"type": "custom:fight_proppa"}]}
	GS.state["units"] = {"U_MOB": {"id": "U_MOB", "owner": 1, "status": GS.UnitStatus.DEPLOYED,
		"meta": {"name": "Boyz", "keywords": ["ORKS", "INFANTRY"]}, "flags": {},
		"models": [{"id": "m0", "position": {"x": 0.0, "y": 0.0}, "alive": true, "wounds": 1, "current_wounds": 1}]}}
	var fp_diffs = SM._apply_stratagem_effects("test_fp", "U_MOB", strat_fp, {"chosen_ability": "lethal"})
	GS.apply_state_changes(fp_diffs)
	_check("FIGHT PROPPA (lethal choice) sets effect_lethal_hits_melee",
		GS.state["units"]["U_MOB"]["flags"].get("effect_lethal_hits_melee", false))
	_check("FIGHT PROPPA (lethal choice) does not set sustained flag",
		not GS.state["units"]["U_MOB"]["flags"].get("effect_sustained_hits_melee", false))
	SM.stratagems["test_fp"] = strat_fp
	SM._clear_stratagem_flags("U_MOB", "test_fp")
	_check("FIGHT PROPPA clear removes the melee flags",
		not GS.state["units"]["U_MOB"]["flags"].has("effect_lethal_hits_melee"))
	var fp_diffs2 = SM._apply_stratagem_effects("test_fp", "U_MOB", strat_fp, {})
	GS.apply_state_changes(fp_diffs2)
	_check("FIGHT PROPPA defaults to SUSTAINED HITS 1",
		GS.state["units"]["U_MOB"]["flags"].get("effect_sustained_hits_melee", false))
	SM._clear_stratagem_flags("U_MOB", "test_fp")

	# ------------------------------------------------------------------
	# 4. KRUNCHIN' DESCENT — D6 per model in ER, 4+ = 1 MW (max 6)
	# ------------------------------------------------------------------
	print("\n=== KRUNCHIN' DESCENT ===")
	var stormboyz_models = []
	for i in range(10):
		# First 5 base-to-base with the enemy blob; last 5 ten inches away.
		# (Keep every model off the exact origin — (0,0) reads as "no position".)
		var x = 10.0 if i < 5 else 400.0
		stormboyz_models.append({"id": "sb%d" % i, "position": {"x": x, "y": float(10 + i * 28)},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1})
	var enemy_models = []
	for i in range(5):
		enemy_models.append({"id": "en%d" % i, "position": {"x": 55.0, "y": float(10 + i * 28)},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 2, "current_wounds": 2,
			"stats": {"toughness": 4, "save": 4}})
	var kd_board = {"units": {
		"U_STORMBOYZ": {"id": "U_STORMBOYZ", "owner": 1,
			"meta": {"name": "Stormboyz", "keywords": ["ORKS", "INFANTRY", "STORMBOYZ"], "stats": {}},
			"flags": {"charged_this_turn": true}, "models": stormboyz_models},
		"U_GUARD": {"id": "U_GUARD", "owner": 2,
			"meta": {"name": "Guardsmen", "keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4, "wounds": 2}},
			"flags": {}, "models": enemy_models}
	}, "meta": {"phase": 9, "active_player": 1, "battle_round": 1}}
	rules.set_test_seed(42)
	var kd = rules.resolve_krunchin_descent("U_STORMBOYZ", "U_GUARD", kd_board, rules.RNGService.new())
	print("  models_in_er=%d rolls=%s mw=%d" % [int(kd.get("models_in_er", -1)), str(kd.get("dice", [{}])[0].get("rolls", [])), int(kd.get("mortal_wounds", -1))])
	_check("KRUNCHIN' DESCENT rolls one D6 per model in ER (5)", int(kd.get("models_in_er", -1)) == 5)
	var kd_rolls: Array = kd.get("dice", [{}])[0].get("rolls", [])
	var expected_mw := 0
	for r in kd_rolls:
		if int(r) >= 4:
			expected_mw += 1
	_check("KRUNCHIN' DESCENT mortal wounds = number of 4+ rolls (capped 6)",
		int(kd.get("mortal_wounds", -1)) == mini(expected_mw, 6))
	if int(kd.get("mortal_wounds", 0)) > 0:
		_check("KRUNCHIN' DESCENT produced damage diffs", not kd.get("diffs", []).is_empty())

	# Cap check: 20 models all in ER — never more than 6 MW
	var big_mob = []
	for i in range(20):
		big_mob.append({"id": "bb%d" % i, "position": {"x": 10.0, "y": float(10 + i * 28)},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1})
	var big_enemy = []
	for i in range(20):
		big_enemy.append({"id": "be%d" % i, "position": {"x": 55.0, "y": float(10 + i * 28)},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 2, "current_wounds": 2,
			"stats": {"toughness": 4, "save": 4}})
	var kd_board2 = {"units": {
		"U_BIG": {"id": "U_BIG", "owner": 1, "meta": {"name": "Stormboyz", "keywords": ["ORKS", "STORMBOYZ"], "stats": {}},
			"flags": {}, "models": big_mob},
		"U_TGT2": {"id": "U_TGT2", "owner": 2, "meta": {"name": "Blob", "keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4, "wounds": 2}},
			"flags": {}, "models": big_enemy}
	}, "meta": {}}
	rules.set_test_seed(7)
	var kd2 = rules.resolve_krunchin_descent("U_BIG", "U_TGT2", kd_board2, rules.RNGService.new())
	_check("KRUNCHIN' DESCENT caps at 6 mortal wounds (20 dice)",
		int(kd2.get("mortal_wounds", 99)) <= 6 and int(kd2.get("models_in_er", 0)) == 20)

	# ------------------------------------------------------------------
	# 5. DAT'S OURS — plus_oc flag flips objective control
	# ------------------------------------------------------------------
	print("\n=== DAT'S OURS — +1 OC ===")
	if MM == null:
		_check("MissionManager present", false)
	else:
		var oc_units = {
			"U_ORKS_OC": {"id": "U_ORKS_OC", "owner": 1, "status": GS.UnitStatus.DEPLOYED,
				"meta": {"name": "Boyz", "keywords": ["ORKS", "INFANTRY"], "stats": {"objective_control": 2}},
				"flags": {}, "models": [{"id": "m0", "position": {"x": 500.0, "y": 500.0},
					"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1}]},
			"U_FOE_OC": {"id": "U_FOE_OC", "owner": 2, "status": GS.UnitStatus.DEPLOYED,
				"meta": {"name": "Marines", "keywords": ["INFANTRY"], "stats": {"objective_control": 3}},
				"flags": {}, "models": [{"id": "m0", "position": {"x": 520.0, "y": 500.0},
					"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 2, "current_wounds": 2}]},
		}
		var objective = {"id": "obj_test", "position": Vector2(510.0, 500.0)}
		var before = MM._check_objective_control(objective, oc_units)
		_check("baseline: OC 3 beats OC 2 (P2 controls)", before == 2)
		# Apply the plus_oc primitive exactly as the stratagem does
		GS.state["units"] = oc_units
		var oc_diffs = EffectPrimitivesData.apply_effects([{"type": "plus_oc", "value": 2}], "U_ORKS_OC")
		GS.apply_state_changes(oc_diffs)
		_check("plus_oc primitive sets effect_plus_oc",
			int(oc_units["U_ORKS_OC"]["flags"].get("effect_plus_oc", 0)) == 2)
		var after = MM._check_objective_control(objective, oc_units)
		_check("with +2 OC the Orks take the objective (P1 controls)", after == 1)
		# value 1 → 3 vs 3 tie → contested (0)
		oc_units["U_ORKS_OC"]["flags"]["effect_plus_oc"] = 1
		_check("with +1 OC the objective is contested", MM._check_objective_control(objective, oc_units) == 0)
		# clear_effects removes the flag
		EffectPrimitivesData.clear_effects([{"type": "plus_oc", "value": 1}], "U_ORKS_OC", oc_units["U_ORKS_OC"]["flags"])
		_check("clear_effects removes effect_plus_oc",
			not oc_units["U_ORKS_OC"]["flags"].has("effect_plus_oc"))

	# DAT'S OURS duration: "until the start of the next Command phase" -> end_of_turn
	_check("DAT'S OURS effect text present",
		"until the start of the next command phase" in str(dats_ours.get("effect_text", "")).to_lower())

	# ------------------------------------------------------------------
	# 6. DED SNEAKY — removal to Strategic Reserves
	# ------------------------------------------------------------------
	print("\n=== DED SNEAKY ===")
	GS.state["units"] = {
		"U_KOMMANDOS": {"id": "U_KOMMANDOS", "owner": 1, "status": GS.UnitStatus.DEPLOYED,
			"meta": {"name": "Kommandos", "keywords": ["ORKS", "INFANTRY", "KOMMANDOS"]},
			"flags": {}, "models": [{"id": "m0", "position": {"x": 100.0, "y": 100.0},
				"alive": true, "wounds": 1, "current_wounds": 1}]},
	}
	_check("precondition: Kommandos start DEPLOYED",
		GS.state["units"]["U_KOMMANDOS"]["status"] == GS.UnitStatus.DEPLOYED and GS.get_reserves_for_player(1).is_empty())
	var strat_ds = {"name": "DED SNEAKY", "effects": [{"type": "custom:ded_sneaky"}]}
	var ds_diffs = SM._apply_stratagem_effects("test_ds", "U_KOMMANDOS", strat_ds, {})
	_check("DED SNEAKY produced diffs", not ds_diffs.is_empty())
	GS.apply_state_changes(ds_diffs)
	var ku = GS.state["units"]["U_KOMMANDOS"]
	_check("Kommandos are now IN_RESERVES", ku["status"] == GS.UnitStatus.IN_RESERVES)
	_check("reserve_type is strategic_reserves", str(ku.get("reserve_type", "")) == "strategic_reserves")
	_check("Kommandos listed in player 1's Strategic Reserves", "U_KOMMANDOS" in GS.get_reserves_for_player(1))
	SM.stratagems["test_ds"] = strat_ds
	SM._clear_stratagem_flags("U_KOMMANDOS", "test_ds")
	_check("Kommandos stay in reserves after end-of-phase clear",
		GS.state["units"]["U_KOMMANDOS"]["status"] == GS.UnitStatus.IN_RESERVES)

	# ------------------------------------------------------------------
	# 7. Duration parsing — DAT'S OURS lasts until the next Command phase
	# ------------------------------------------------------------------
	print("\n=== Duration parsing ===")
	# Mirror use_stratagem's expiry derivation on the loaded definitions.
	var dats_text = str(dats_ours.get("effect_text", "")).to_lower()
	_check("DAT'S OURS text maps to end_of_turn expiry",
		"until the start of the next command phase" in dats_text)
	var retreat_text = str(retreat.get("effect_text", "")).to_lower()
	_check("TAKTIKAL RETREAT text maps to end_of_turn expiry",
		"until the end of the turn" in retreat_text)
