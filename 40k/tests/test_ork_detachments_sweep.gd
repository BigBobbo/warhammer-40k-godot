extends SceneTree

# Ork detachment sweep — one section per detachment, added as each detachment's
# stratagems + enhancements are implemented. Covers loading (real load path:
# factions set + load_faction_stratagems_for_player), handler effects, and the
# new engine primitives each detachment introduced.
#
# Run: godot --headless --path 40k --script tests/test_ork_detachments_sweep.gd

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


func _load_detachment(SM, GS, detachment: String) -> Dictionary:
	"""Load a detachment's stratagems for player 1 via the real load path.
	Returns {count, implemented, by_name}."""
	GS.state["factions"] = {"1": {"name": "Orks", "detachment": detachment},
		"2": {"name": "Orks", "detachment": "War Horde"}}
	SM.load_faction_stratagems_for_player(1)
	var out = {"count": 0, "implemented": 0, "by_name": {}}
	for s in SM.get_faction_stratagems_for_player(1):
		out.count += 1
		if s.get("implemented", false):
			out.implemented += 1
		out.by_name[str(s.get("name", "")).replace("’", "'").to_upper()] = s
	return out


func _sum_wounds(result: Dictionary) -> int:
	var total := 0
	for d in result.get("dice", []):
		var ctx = str(d.get("context", "")).to_lower()
		if "wound" in ctx and d.has("successes"):
			total += int(d.get("successes", 0))
	return total


func _fight(rules, flags: Dictionary, seed_val: int, tgt_toughness: int = 8, tgt_save: int = 3) -> int:
	var atk = []
	for i in range(10):
		atk.append({"id": "ma%d" % i, "position": {"x": 10.0, "y": 10.0 + i * 30},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1})
	var tgt = []
	for i in range(10):
		tgt.append({"id": "mt%d" % i, "position": {"x": 30.0, "y": 10.0 + i * 30},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 3, "current_wounds": 3,
			"stats": {"toughness": tgt_toughness, "save": tgt_save}})
	var board = {"units": {
		"U_ATK": {"id": "U_ATK", "owner": 1,
			"meta": {"keywords": ["INFANTRY", "ORKS"], "stats": {"toughness": 5, "save": 6, "wounds": 1}, "abilities": []},
			"flags": flags, "models": atk},
		"U_TGT": {"id": "U_TGT", "owner": 2,
			"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": tgt_toughness, "save": tgt_save, "wounds": 3}, "abilities": []},
			"flags": {}, "models": tgt}
	}, "meta": {"phase": 10, "active_player": 1, "battle_round": 1}}
	rules.set_test_seed(seed_val)
	var rng = rules.RNGService.new()
	var action := {"type": "FIGHT", "actor_unit_id": "U_ATK",
		"payload": {"assignments": [{"attacker": "U_ATK", "target": "U_TGT", "weapon": "choppa"}]}}
	return _sum_wounds(rules.resolve_melee_attacks(action, board, rng))


func _boyz_unit(id: String, n_models: int, owner: int = 1, dead: int = 0) -> Dictionary:
	var models = []
	for i in range(n_models):
		models.append({"id": "m%d" % i, "position": {"x": 20.0 + i * 25, "y": 20.0},
			"base_mm": 32, "base_type": "circular", "alive": i >= dead,
			"wounds": 1, "current_wounds": 0 if i < dead else 1})
	return {"id": id, "owner": owner, "status": 2,
		"meta": {"name": id, "keywords": ["BATTLELINE", "BOYZ", "INFANTRY", "MOB", "ORKS"],
			"stats": {"toughness": 5, "save": 6, "wounds": 1}, "abilities": [], "enhancements": []},
		"flags": {}, "models": models}


func _run():
	var SM = root.get_node("StratagemManager")
	var GS = root.get_node("GameState")
	var FAM = root.get_node("FactionAbilityManager")
	var rules = root.get_node("RulesEngine")
	if SM == null or GS == null or FAM == null or rules == null:
		_check("autoloads present", false)
		return

	_green_tide(SM, GS, FAM, rules)
	_more_dakka(SM, GS, FAM, rules)


# ==========================================================================
# MORE DAKKA!
# ==========================================================================
func _more_dakka(SM, GS, FAM, rules):
	print("\n===== MORE DAKKA! =====")
	var md = _load_detachment(SM, GS, "More Dakka!")
	_check("More Dakka!: 6 stratagems loaded", md.count == 6)
	_check("More Dakka!: all 6 implemented", md.implemented == 6)
	_check("GET STUCK IN, LADZ! costs 2 CP",
		int(md.by_name.get("GET STUCK IN, LADZ!", {}).get("cp_cost", 0)) == 2)
	_check("HUGE SHOW-OFFS excludes Killa Kans",
		"not_keyword:KILLA KANS" in md.by_name.get("HUGE SHOW-OFFS", {}).get("target", {}).get("conditions", []))

	# GET STUCK IN, LADZ! — unit-scoped Waaagh!
	GS.state["units"] = {"U_GSL": _boyz_unit("U_GSL", 10)}
	var strat_gsl = {"id": "t_gsl", "name": "GET STUCK IN, LADZ!", "effects": [{"type": "custom:get_stuck_in_ladz"}]}
	GS.apply_state_changes(SM._apply_stratagem_effects("t_gsl", "U_GSL", strat_gsl, {}))
	var gsl_flags = GS.get_unit("U_GSL")["flags"]
	_check("GET STUCK IN, LADZ! activates Waaagh! for the unit",
		gsl_flags.get("waaagh_active", false) and int(gsl_flags.get("effect_invuln", 0)) == 5)
	SM.stratagems["t_gsl"] = strat_gsl
	SM._clear_stratagem_flags("U_GSL", "t_gsl")
	_check("GET STUCK IN, LADZ! clear removes the Waaagh! flags",
		not GS.get_unit("U_GSL")["flags"].has("waaagh_active"))

	# HUGE SHOW-OFFS — stat flags land
	GS.state["units"] = {"U_HSO": _boyz_unit("U_HSO", 1)}
	var strat_hso = {"id": "t_hso", "name": "HUGE SHOW-OFFS", "effects": [{"type": "custom:huge_show_offs"}]}
	GS.apply_state_changes(SM._apply_stratagem_effects("t_hso", "U_HSO", strat_hso, {}))
	var hso_flags = GS.get_unit("U_HSO")["flags"]
	_check("HUGE SHOW-OFFS sets +1 Move/OC/Hit/Ld flags",
		int(hso_flags.get("effect_plus_move", 0)) == 1 and int(hso_flags.get("effect_plus_oc", 0)) == 1
		and hso_flags.get("effect_plus_one_hit", false) and int(hso_flags.get("effect_improve_leadership", 0)) == 1)

	# SPESHUL SHELLS — AP bonus only within 18"
	var near_shooter = {"meta": {}, "flags": {"effect_speshul_shells_md": true},
		"models": [{"id": "m0", "position": {"x": 10.0, "y": 10.0}, "base_mm": 32, "alive": true}]}
	var near_target = {"meta": {}, "flags": {},
		"models": [{"id": "t0", "position": {"x": 400.0, "y": 10.0}, "base_mm": 32, "alive": true}]}   # ~9"
	var far_target = {"meta": {}, "flags": {},
		"models": [{"id": "t1", "position": {"x": 900.0, "y": 10.0}, "base_mm": 32, "alive": true}]}   # ~22"
	_check("SPESHUL SHELLS +1 AP within 18\"", rules.get_speshul_shells_ap_bonus(near_shooter, near_target) == 1)
	_check("SPESHUL SHELLS no bonus beyond 18\"", rules.get_speshul_shells_ap_bonus(near_shooter, far_target) == 0)
	near_shooter["flags"] = {}
	_check("SPESHUL SHELLS requires the flag", rules.get_speshul_shells_ap_bonus(near_shooter, near_target) == 0)

	# ORKS IS STILL ORKS — melee wound reroll flag improves output (seeded)
	var oso_better := 0
	for s in [11, 42, 77]:
		var off = _fight(rules, {}, s, 3, 6)
		var on = _fight(rules, {"effect_orks_is_still_orks": true}, s, 3, 6)
		if on > off:
			oso_better += 1
	_check("ORKS IS STILL ORKS improves melee wounds on some seeds", oso_better >= 1)

	# CALL DAT DAKKA? — shoot-back at normal BS beats overwatch 6s (aggregate)
	var total_ow := 0
	var total_cdd := 0
	for s in [3, 42, 99, 123]:
		rules.set_test_seed(s)
		var ow = rules.resolve_overwatch_shooting("U_SHOOTBACK", "U_ATTACKER", _shootback_board(), rules.RNGService.new())
		rules.set_test_seed(s)
		var cdd = rules.resolve_overwatch_shooting("U_SHOOTBACK", "U_ATTACKER", _shootback_board(), rules.RNGService.new(), false)
		total_ow += int(ow.get("total_hits", 0))
		total_cdd += int(cdd.get("total_hits", 0))
	print("  CALL DAT DAKKA?: hits at BS=%d vs overwatch-6s=%d" % [total_cdd, total_ow])
	_check("CALL DAT DAKKA? shoots at normal BS (more hits than overwatch 6s)", total_cdd > total_ow)

	# Enhancements: flags via UnitAbilityManager entries
	var UAM = root.get_node("UnitAbilityManager")
	GS.state["units"] = {"U_GITZ_MD": _boyz_unit("U_GITZ_MD", 5)}
	GS.state["units"]["U_GITZ_MD"]["meta"]["enhancements"] = ["Targetin' Squigs", "Dead Shiny Shootas", "Zog Off and Eat Dakka!"]
	UAM._applied_this_phase = {}
	UAM._apply_enhancement_abilities(8)  # ranged entries apply in the SHOOTING phase
	var md_flags = GS.get_unit("U_GITZ_MD")["flags"]
	_check("Targetin' Squigs sets effect_plus_one_hit_ranged", md_flags.get("effect_plus_one_hit_ranged", false))
	_check("Dead Shiny Shootas sets effect_grant_rapid_fire_1", md_flags.get("effect_grant_rapid_fire_1", false))
	_check("Zog Off and Eat Dakka! sets effect_fall_back_and_shoot", md_flags.get("effect_fall_back_and_shoot", false))

	# HUGE SHOW-OFFS leadership improvement is read by battle-shock tests via
	# CommandPhase._get_effective_leadership (static).
	GS.state["units"] = {"U_LD": _boyz_unit("U_LD", 5)}
	GS.state["units"]["U_LD"]["meta"]["stats"]["leadership"] = 7
	var CommandPhaseScript = load("res://phases/CommandPhase.gd")
	var ld_before = CommandPhaseScript._get_effective_leadership("U_LD")
	GS.state["units"]["U_LD"]["flags"]["effect_improve_leadership"] = 1
	var ld_after = CommandPhaseScript._get_effective_leadership("U_LD")
	_check("effect_improve_leadership lowers the required battle-shock roll", ld_before == 7 and ld_after == 6)


func _shootback_board() -> Dictionary:
	var shooters = []
	for i in range(6):
		shooters.append({"id": "ms%d" % i, "position": {"x": 10.0, "y": 10.0 + i * 35},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1,
			"weapons": ["bolt_rifle"]})
	var attackers = []
	for i in range(5):
		attackers.append({"id": "ma%d" % i, "position": {"x": 300.0, "y": 10.0 + i * 35},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 2, "current_wounds": 2,
			"stats": {"toughness": 4, "save": 3}})
	return {"units": {
		"U_SHOOTBACK": {"id": "U_SHOOTBACK", "owner": 1,
			"meta": {"name": "Lootas", "keywords": ["ORKS", "INFANTRY"], "abilities": [],
				"stats": {"toughness": 5, "save": 6, "wounds": 1},
				"weapons": [{"name": "Bolt Rifle", "type": "Ranged", "range": "24", "attacks": "2",
					"ballistic_skill": "5", "strength": "4", "ap": "1", "damage": "1"}]},
			"flags": {}, "models": shooters},
		"U_ATTACKER": {"id": "U_ATTACKER", "owner": 2,
			"meta": {"name": "Marines", "keywords": ["INFANTRY"], "abilities": [],
				"stats": {"toughness": 4, "save": 3, "wounds": 2}},
			"flags": {}, "models": attackers}
	}, "meta": {"phase": 8, "active_player": 2, "battle_round": 1}}


# ==========================================================================
# GREEN TIDE
# ==========================================================================
func _green_tide(SM, GS, FAM, rules):
	print("\n===== GREEN TIDE =====")
	var gt = _load_detachment(SM, GS, "Green Tide")
	_check("Green Tide: 6 stratagems loaded", gt.count == 6)
	_check("Green Tide: all 6 implemented", gt.implemented == 6)
	var bulldozer = gt.by_name.get("BULLDOZER BRUTALITY", {})
	_check("BULLDOZER target requires BOYZ keyword",
		"keyword:BOYZ" in bulldozer.get("target", {}).get("conditions", []))

	# counts-as-10 helper
	var small = _boyz_unit("U_SMALL", 5)
	var big = _boyz_unit("U_BIG", 12)
	_check("unit_counts_as_10 false for 5 models", not FAM.unit_counts_as_10(small))
	_check("unit_counts_as_10 true for 12 models", FAM.unit_counts_as_10(big))
	small["flags"]["effect_counts_as_10"] = true
	_check("unit_counts_as_10 true via Raucous Warcaller/Braggin' Rights flag",
		FAM.unit_counts_as_10(small))

	# BRAGGIN' RIGHTS — pairs the nearest other Boyz unit within 6"
	GS.state["units"] = {
		"U_MOB_A": _boyz_unit("U_MOB_A", 5),
		"U_MOB_B": _boyz_unit("U_MOB_B", 5),
		"U_FAR": _boyz_unit("U_FAR", 5),
	}
	for m in GS.state["units"]["U_MOB_B"]["models"]:
		m["position"]["y"] = 120.0  # ~2.5" away
	for m in GS.state["units"]["U_FAR"]["models"]:
		m["position"]["y"] = 2000.0  # far away
	var strat_br = {"id": "t_br", "name": "BRAGGIN’ RIGHTS", "effects": [{"type": "custom:braggin_rights"}]}
	var br_diffs = SM._apply_stratagem_effects("t_br", "U_MOB_A", strat_br, {})
	GS.apply_state_changes(br_diffs)
	_check("BRAGGIN' RIGHTS flags the target", GS.get_unit("U_MOB_A")["flags"].get("effect_counts_as_10", false))
	_check("BRAGGIN' RIGHTS flags the nearest Boyz within 6\"", GS.get_unit("U_MOB_B")["flags"].get("effect_counts_as_10", false))
	_check("BRAGGIN' RIGHTS does not flag distant units", not GS.get_unit("U_FAR")["flags"].get("effect_counts_as_10", false))

	# COME ON LADZ! — revive D3+2 dead models
	GS.state["units"] = {"U_HURT": _boyz_unit("U_HURT", 10, 1, 6)}
	rules.set_test_seed(42)
	var strat_cl = {"id": "t_cl", "name": "COME ON LADZ!", "effects": [{"type": "custom:come_on_ladz"}]}
	var cl_diffs = SM._apply_stratagem_effects("t_cl", "U_HURT", strat_cl, {})
	GS.apply_state_changes(cl_diffs)
	var alive_after := 0
	for m in GS.get_unit("U_HURT")["models"]:
		if m.get("alive", false):
			alive_after += 1
	print("  COME ON LADZ!: alive after revive = %d (was 4)" % alive_after)
	_check("COME ON LADZ! revives between 3 and 5 models", alive_after >= 7 and alive_after <= 9)

	# COMPETITIVE STREAK — reroll scope depends on model count
	GS.state["units"] = {"U_SMALLMOB": _boyz_unit("U_SMALLMOB", 5), "U_BIGMOB": _boyz_unit("U_BIGMOB", 12)}
	var strat_cs = {"id": "t_cs", "name": "COMPETITIVE STREAK", "effects": [{"type": "custom:competitive_streak"}]}
	GS.apply_state_changes(SM._apply_stratagem_effects("t_cs", "U_SMALLMOB", strat_cs, {}))
	GS.apply_state_changes(SM._apply_stratagem_effects("t_cs", "U_BIGMOB", strat_cs, {}))
	_check("COMPETITIVE STREAK small mob rerolls 1s",
		GS.get_unit("U_SMALLMOB")["flags"].get("effect_reroll_wounds", "") == "ones")
	_check("COMPETITIVE STREAK 10+ mob rerolls all",
		GS.get_unit("U_BIGMOB")["flags"].get("effect_reroll_wounds", "") == "failed")
	SM.stratagems["t_cs"] = strat_cs
	SM._clear_stratagem_flags("U_BIGMOB", "t_cs")
	_check("COMPETITIVE STREAK clear removes the flag",
		not GS.get_unit("U_BIGMOB")["flags"].has("effect_reroll_wounds"))

	# TIDE OF MUSCLE — +1 charge, re-roll while 10+
	var strat_tm = {"id": "t_tm", "name": "TIDE OF MUSCLE", "effects": [{"type": "custom:tide_of_muscle"}]}
	GS.apply_state_changes(SM._apply_stratagem_effects("t_tm", "U_BIGMOB", strat_tm, {}))
	_check("TIDE OF MUSCLE sets +1 charge", int(GS.get_unit("U_BIGMOB")["flags"].get("effect_plus_charge", 0)) == 1)
	_check("TIDE OF MUSCLE grants charge re-roll for 10+ mob",
		GS.get_unit("U_BIGMOB")["flags"].get("effect_reroll_charge", false))

	# BULLDOZER BRUTALITY — 3" melee eligibility
	var atk_models = []
	for i in range(4):
		# Models 0-1 base-to-base with the enemy; models 2-3 at ~2.2" edge
		# distance (inside 3" but outside 1" ER): 75 + 2.2*40 + 50.4 ≈ 213.
		var x = 30.0 if i < 2 else 213.0
		atk_models.append({"id": "a%d" % i, "position": {"x": x, "y": 20.0 + i * 30},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1})
	var enemy_models = []
	for i in range(4):
		enemy_models.append({"id": "e%d" % i, "position": {"x": 75.0, "y": 20.0 + i * 30},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 2, "current_wounds": 2,
			"stats": {"toughness": 4, "save": 4}})
	var bb_board = {"units": {
		"U_BB": {"id": "U_BB", "owner": 1, "meta": {"name": "Boyz", "keywords": ["BOYZ", "ORKS", "INFANTRY"], "stats": {}},
			"flags": {}, "models": atk_models},
		"U_BB_TGT": {"id": "U_BB_TGT", "owner": 2, "meta": {"name": "Guard", "keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4}},
			"flags": {}, "models": enemy_models}
	}}
	var base_eligible = rules.get_eligible_melee_model_indices(bb_board["units"]["U_BB"], bb_board)
	bb_board["units"]["U_BB"]["flags"]["effect_fight_range_3"] = true
	var boosted_eligible = rules.get_eligible_melee_model_indices(bb_board["units"]["U_BB"], bb_board)
	print("  BULLDOZER: eligible without flag=%s with flag=%s" % [str(base_eligible), str(boosted_eligible)])
	_check("BULLDOZER: base eligibility excludes the 2\"+ models", base_eligible.size() == 2)
	_check("BULLDOZER: 3\" flag makes all 4 models eligible", boosted_eligible.size() == 4)

	# Ferocious Show Off — melee strength live bonus
	var fso_unit = _boyz_unit("U_FSO", 12)
	fso_unit["meta"]["enhancements"] = ["Ferocious Show Off"]
	_check("Ferocious Show Off: +3 S while 10+ models", FAM.ferocious_show_off_strength_bonus(fso_unit) == 3)
	var fso_small = _boyz_unit("U_FSO2", 5)
	fso_small["meta"]["enhancements"] = ["Ferocious Show Off"]
	_check("Ferocious Show Off: +1 S under 10 models", FAM.ferocious_show_off_strength_bonus(fso_small) == 1)
	_check("Ferocious Show Off: 0 without the enhancement", FAM.ferocious_show_off_strength_bonus(_boyz_unit("U_FSO3", 12)) == 0)

	# Bloodthirsty Belligerence — charge re-roll only while 10+
	var bb_unit = _boyz_unit("U_BLOOD", 12)
	bb_unit["meta"]["enhancements"] = ["Bloodthirsty Belligerence"]
	_check("Bloodthirsty: charge re-roll while 10+", FAM.unit_has_green_tide_charge_reroll(bb_unit, {}))
	var bb_small = _boyz_unit("U_BLOOD2", 5)
	bb_small["meta"]["enhancements"] = ["Bloodthirsty Belligerence"]
	_check("Bloodthirsty: no charge re-roll under 10", not FAM.unit_has_green_tide_charge_reroll(bb_small, {}))

	# Brutal But Kunnin' — command-phase CP roll respects the bonus-CP cap
	GS.state["units"] = {"U_BBK": _boyz_unit("U_BBK", 12)}
	GS.state["units"]["U_BBK"]["meta"]["keywords"].append("CHARACTER")
	GS.state["units"]["U_BBK"]["meta"]["enhancements"] = ["Brutal But Kunnin'"]
	GS.state["players"] = {"1": {"cp": 3, "vp": 0, "primary_vp": 0, "secondary_vp": 0, "bonus_cp_gained_this_round": 0},
		"2": {"cp": 3, "vp": 0, "primary_vp": 0, "secondary_vp": 0, "bonus_cp_gained_this_round": 0}}
	rules.set_test_seed(7)
	FAM.process_command_phase_cp_enhancements(1)
	var cp_now = int(GS.state["players"]["1"]["cp"])
	print("  Brutal But Kunnin': CP now %d (12-model unit rolls D6+2, 5+ = +1 CP)" % cp_now)
	_check("Brutal But Kunnin' CP stays 3 or becomes 4", cp_now == 3 or cp_now == 4)
	if cp_now == 4:
		_check("bonus CP recorded against the round cap", GS.get_bonus_cp_gained_this_round(1) == 1)
		FAM.process_command_phase_cp_enhancements(1)
		_check("second roll blocked by the bonus-CP cap", int(GS.state["players"]["1"]["cp"]) == 4)
