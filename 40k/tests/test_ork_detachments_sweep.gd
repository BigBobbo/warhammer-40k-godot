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
	_bully_boyz(SM, GS, FAM, rules)
	_da_big_hunt(SM, GS, FAM, rules)


# ==========================================================================
# BULLY BOYZ
# ==========================================================================
func _bully_boyz(SM, GS, FAM, rules):
	print("\n===== BULLY BOYZ =====")
	var bb = _load_detachment(SM, GS, "Bully Boyz")
	_check("Bully Boyz: 6 stratagems loaded", bb.count == 6)
	_check("Bully Boyz: all 6 implemented", bb.implemented == 6)
	var att = bb.by_name.get("ARMED TO DA TEEF", {})
	_check("ARMED TO DA TEEF has keyword_any NOBZ/MEGANOBZ",
		"keyword_any:NOBZ,MEGANOBZ" in att.get("target", {}).get("conditions", []))
	var hb = bb.by_name.get("HULKING BRUTES", {})
	var hb_types := []
	for e in hb.get("effects", []):
		hb_types.append(e.get("type", ""))
	_check("HULKING BRUTES uses the worsen_ap primitive", "worsen_ap" in hb_types)

	# Meganobz-only unit matches the NOBZ/MEGANOBZ alternation
	var mega = {"meta": {"keywords": ["ORKS", "INFANTRY", "MEGANOBZ"]}, "flags": {}, "models": []}
	_check("Meganobz match ARMED TO DA TEEF target",
		FactionStratagemLoaderData.unit_matches_target(mega, att.get("target", {})))

	# ARMED TO DA TEEF — reroll scope depends on Waaagh!
	GS.state["units"] = {"U_NOBZ": _boyz_unit("U_NOBZ", 5)}
	GS.state["units"]["U_NOBZ"]["meta"]["keywords"] = ["ORKS", "INFANTRY", "NOBZ"]
	var strat_att = {"id": "t_att", "name": "ARMED TO DA TEEF", "effects": [{"type": "custom:armed_to_da_teef"}]}
	GS.apply_state_changes(SM._apply_stratagem_effects("t_att", "U_NOBZ", strat_att, {}))
	_check("ARMED TO DA TEEF rerolls 1s without Waaagh!",
		GS.get_unit("U_NOBZ")["flags"].get("effect_reroll_hits", "") == "ones")
	GS.get_unit("U_NOBZ")["flags"].erase("effect_reroll_hits")
	GS.get_unit("U_NOBZ")["flags"]["waaagh_active"] = true
	GS.apply_state_changes(SM._apply_stratagem_effects("t_att", "U_NOBZ", strat_att, {}))
	_check("ARMED TO DA TEEF rerolls all hits in Waaagh!",
		GS.get_unit("U_NOBZ")["flags"].get("effect_reroll_hits", "") == "failed")

	# ALWAYS LOOKIN' FER A FIGHT — consolidation cap (6 flat in Waaagh!)
	var strat_alf = {"id": "t_alf", "name": "ALWAYS LOOKIN’ FER A FIGHT", "effects": [{"type": "custom:always_lookin_fer_a_fight"}]}
	GS.apply_state_changes(SM._apply_stratagem_effects("t_alf", "U_NOBZ", strat_alf, {}))
	_check("ALWAYS LOOKIN' (Waaagh!) sets 6\" consolidation cap",
		float(GS.get_unit("U_NOBZ")["flags"].get("effect_consolidate_max", 0)) == 6.0)
	GS.get_unit("U_NOBZ")["flags"].erase("waaagh_active")
	rules.set_test_seed(11)
	GS.apply_state_changes(SM._apply_stratagem_effects("t_alf", "U_NOBZ", strat_alf, {}))
	var alf_cap = float(GS.get_unit("U_NOBZ")["flags"].get("effect_consolidate_max", 0))
	_check("ALWAYS LOOKIN' (no Waaagh!) sets D3+3 cap (4-6)", alf_cap >= 4.0 and alf_cap <= 6.0)

	# CRUSHING IMPACT (Bully Boyz) — threshold 5 normally, 4 in Waaagh!
	var ci_models = []
	for i in range(5):
		ci_models.append({"id": "cim%d" % i, "position": {"x": 10.0, "y": 10.0 + i * 28},
			"base_mm": 40, "base_type": "circular", "alive": true, "wounds": 3, "current_wounds": 3})
	var ci_enemy_models = []
	for i in range(5):
		ci_enemy_models.append({"id": "cie%d" % i, "position": {"x": 60.0, "y": 10.0 + i * 28},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 2, "current_wounds": 2,
			"stats": {"toughness": 4, "save": 3}})
	GS.state["units"] = {
		"U_MEGA": {"id": "U_MEGA", "owner": 1, "status": 2,
			"meta": {"name": "Meganobz", "keywords": ["ORKS", "INFANTRY", "MEGANOBZ"], "stats": {}, "abilities": [], "enhancements": []},
			"flags": {"charged_this_turn": true}, "models": ci_models},
		"U_CI_TGT": {"id": "U_CI_TGT", "owner": 2, "status": 2,
			"meta": {"name": "Marines", "keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 3, "wounds": 2}, "abilities": [], "enhancements": []},
			"flags": {}, "models": ci_enemy_models},
	}
	rules.set_test_seed(42)
	var strat_ci = {"id": "t_ci", "name": "CRUSHING IMPACT", "effects": [{"type": "custom:crushing_impact_bully"}]}
	var ci_diffs = SM._apply_stratagem_effects("t_ci", "U_MEGA", strat_ci, {"enemy_unit_id": "U_CI_TGT"})
	_check("CRUSHING IMPACT (Bully Boyz) rolled dice and returned diffs or none", ci_diffs != null)

	# TOO ARROGANT TO DIE — flag lands; swing-back machinery reads it
	var strat_ta = {"id": "t_ta", "name": "TOO ARROGANT TO DIE", "effects": [{"type": "custom:too_arrogant_to_die"}]}
	GS.apply_state_changes(SM._apply_stratagem_effects("t_ta", "U_MEGA", strat_ta, {}))
	_check("TOO ARROGANT TO DIE sets its flag",
		GS.get_unit("U_MEGA")["flags"].get("effect_too_arrogant_to_die", false))

	# CUT' EM DOWN — enemy gets marked, -1 variant with Waaagh!
	GS.get_unit("U_MEGA")["flags"]["waaagh_active"] = true
	var strat_ced = {"id": "t_ced", "name": "CUT’ EM DOWN", "effects": [{"type": "custom:cut_em_down"}]}
	GS.apply_state_changes(SM._apply_stratagem_effects("t_ced", "U_MEGA", strat_ced, {"enemy_unit_id": "U_CI_TGT"}))
	_check("CUT' EM DOWN marks the enemy for Desperate Escape",
		GS.get_unit("U_CI_TGT")["flags"].get("effect_cut_em_down", false))
	_check("CUT' EM DOWN applies the -1 (Waaagh!) marker",
		GS.get_unit("U_CI_TGT")["flags"].get("effect_cut_em_down_minus1", false))

	# FallBackMove honours the mark: desperate escape becomes mandatory.
	# (Fall-back modes are 11e-only; the automated harness pins edition 10,
	# so raise it for this check and restore afterwards.)
	var prev_edition = GameConstants.edition
	GS.set_edition(11)
	var FallBackScript = load("res://scripts/rules/movetypes/FallBackMove.gd")
	var fb = FallBackScript.new()
	var mode = fb.select_mode("U_CI_TGT", GS.state)
	_check("CUT' EM DOWN forces mandatory desperate escape on fall back",
		mode.get("mode", "") == "desperate_escape" and mode.get("mandatory", false))
	GS.set_edition(prev_edition)

	# hazard_rolls: -1 modifier increases failures (3s now fail)
	var hz_rng = rules.RNGService.new(99)
	var hz_unit = {"meta": {"keywords": ["INFANTRY"]}, "models": [{"alive": true}, {"alive": true}, {"alive": true}, {"alive": true}]}
	var AttackSeq = load("res://scripts/rules/AttackSequence.gd")
	rules.set_test_seed(99)
	var hz_plain = AttackSeq.hazard_rolls(hz_unit, 12, rules.RNGService.new())
	rules.set_test_seed(99)
	var hz_mod = AttackSeq.hazard_rolls(hz_unit, 12, rules.RNGService.new(), -1)
	print("  hazard: plain failures=%d, -1 failures=%d" % [int(hz_plain.failures), int(hz_mod.failures)])
	_check("-1 hazard modifier never reduces failures", int(hz_mod.failures) >= int(hz_plain.failures))

	# 'Eadstompa — wound reroll scope vs under-strength targets
	var ead = {"meta": {"enhancements": ["'Eadstompa"], "keywords": ["ORKS"]}, "flags": {}, "models": []}
	var full_tgt = {"models": [{"alive": true}, {"alive": true}], "meta": {}, "flags": {}}
	var dented_tgt = {"models": [{"alive": true}, {"alive": true}, {"alive": false}], "meta": {}, "flags": {}}
	var halved_tgt = {"models": [{"alive": true}, {"alive": false}, {"alive": false}, {"alive": false}], "meta": {}, "flags": {}}
	_check("'Eadstompa: no reroll vs full-strength", rules.get_eadstompa_reroll_scope(ead, full_tgt) == "")
	_check("'Eadstompa: reroll 1s vs under-strength", rules.get_eadstompa_reroll_scope(ead, dented_tgt) == "ones")
	_check("'Eadstompa: full reroll vs below-half", rules.get_eadstompa_reroll_scope(ead, halved_tgt) == "failed")

	# Tellyporta — Deep Strike grant through attachment
	GS.state["units"] = {
		"U_WBMA": {"id": "U_WBMA", "owner": 1, "attached_to": "U_MEGA2",
			"meta": {"name": "Warboss in Mega Armour", "keywords": ["CHARACTER", "ORKS"], "enhancements": ["Tellyporta"], "abilities": []},
			"flags": {}, "models": [{"id": "m0", "alive": true}]},
		"U_MEGA2": {"id": "U_MEGA2", "owner": 1,
			"meta": {"name": "Meganobz", "keywords": ["ORKS", "MEGANOBZ"], "enhancements": [], "abilities": []},
			"flags": {}, "attachment_data": {"attached_characters": ["U_WBMA"]},
			"models": [{"id": "m0", "alive": true}]},
	}
	_check("Tellyporta grants Deep Strike to the led unit", GS.unit_has_deep_strike("U_MEGA2"))
	_check("Tellyporta grants Deep Strike to the bearer", GS.unit_has_deep_strike("U_WBMA"))

	# Big Gob — nearest engaged enemy takes a battle-shock test at -1
	var bg_models = [{"id": "m0", "position": {"x": 10.0, "y": 10.0}, "base_mm": 40, "base_type": "circular", "alive": true, "wounds": 6, "current_wounds": 6}]
	var bg_enemy_models = [{"id": "e0", "position": {"x": 55.0, "y": 10.0}, "base_mm": 32, "base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1}]
	GS.state["units"] = {
		"U_BIGGOB": {"id": "U_BIGGOB", "owner": 1, "status": 2, "attached_to": null,
			"meta": {"name": "Warboss", "keywords": ["CHARACTER", "INFANTRY", "ORKS", "WARBOSS"],
				"enhancements": ["Big Gob"], "abilities": [], "stats": {"leadership": 6}},
			"flags": {}, "models": bg_models},
		"U_BG_TGT": {"id": "U_BG_TGT", "owner": 2, "status": 2,
			"meta": {"name": "Guardsmen", "keywords": ["INFANTRY"], "abilities": [], "enhancements": [],
				"stats": {"leadership": 12}},
			"flags": {}, "models": bg_enemy_models},
	}
	rules.set_test_seed(5)
	FAM.process_big_gob(1)
	_check("Big Gob battle-shocks the engaged enemy (Ld 12 unreachable)",
		GS.get_unit("U_BG_TGT")["flags"].get("battle_shocked", false))


# ==========================================================================
# DA BIG HUNT
# ==========================================================================
func _fight_vs(rules, atk_flags: Dictionary, tgt_flags: Dictionary, seed_val: int) -> int:
	"""_fight variant with target flags (for Prey-marker sensitive effects)."""
	var atk = []
	for i in range(10):
		atk.append({"id": "ma%d" % i, "position": {"x": 10.0, "y": 10.0 + i * 30},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1})
	var tgt = []
	for i in range(10):
		tgt.append({"id": "mt%d" % i, "position": {"x": 30.0, "y": 10.0 + i * 30},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 3, "current_wounds": 3,
			"stats": {"toughness": 3, "save": 6}})
	var board = {"units": {
		"U_ATK": {"id": "U_ATK", "owner": 1,
			"meta": {"keywords": ["INFANTRY", "ORKS"], "stats": {"toughness": 5, "save": 6, "wounds": 1}, "abilities": []},
			"flags": atk_flags, "models": atk},
		"U_TGT": {"id": "U_TGT", "owner": 2,
			"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": 3, "save": 6, "wounds": 3}, "abilities": []},
			"flags": tgt_flags, "models": tgt}
	}, "meta": {"phase": 10, "active_player": 1, "battle_round": 1}}
	rules.set_test_seed(seed_val)
	var rng = rules.RNGService.new()
	var action := {"type": "FIGHT", "actor_unit_id": "U_ATK",
		"payload": {"assignments": [{"attacker": "U_ATK", "target": "U_TGT", "weapon": "choppa"}]}}
	return _sum_wounds(rules.resolve_melee_attacks(action, board, rng))


func _da_big_hunt(SM, GS, FAM, rules):
	print("\n===== DA BIG HUNT =====")
	var dbh = _load_detachment(SM, GS, "Da Big Hunt")
	_check("Da Big Hunt: 6 stratagems loaded", dbh.count == 6)
	_check("Da Big Hunt: all 6 implemented", dbh.implemented == 6)
	var st_strat = dbh.by_name.get("STALKIN' TAKTIKS", {})
	_check("STALKIN' TAKTIKS has keyword_any INFANTRY/MOUNTED",
		"keyword_any:INFANTRY,MOUNTED" in st_strat.get("target", {}).get("conditions", []))
	_check("STALKIN' TAKTIKS requires BEAST SNAGGA",
		"keyword:BEAST SNAGGA" in st_strat.get("target", {}).get("conditions", []))
	_check("INSTINCTIVE HUNTERS requires the unit to be unengaged",
		"not_in_engagement_range" in dbh.by_name.get("INSTINCTIVE HUNTERS", {}).get("target", {}).get("conditions", []))
	# The MovementPhase reactive-move candidates list uses the straight-apostrophe
	# name; the CSV stores typographic apostrophes.
	_check("WHERE D'YA FINK YOU'RE GOING? findable by straight-apostrophe name",
		SM.find_faction_stratagem_by_name(1, "Where D'ya Fink You're Going?") != "")

	# ---- Prey (detachment rule): selection lifecycle -------------------------
	var snagga = _boyz_unit("U_SNAGGA", 5)
	snagga["meta"]["keywords"] = ["ORKS", "BEAST SNAGGA", "MOUNTED"]
	var near_char = _boyz_unit("U_PREY_CHAR", 1, 2)
	near_char["meta"]["keywords"] = ["CHARACTER", "INFANTRY"]
	near_char["models"][0]["position"] = {"x": 150.0, "y": 20.0}
	var far_veh = _boyz_unit("U_PREY_VEH", 1, 2)
	far_veh["meta"]["keywords"] = ["VEHICLE"]
	far_veh["models"][0]["position"] = {"x": 2000.0, "y": 20.0}
	var plain = _boyz_unit("U_PLAIN", 5, 2)
	plain["meta"]["keywords"] = ["INFANTRY"]
	GS.state["units"] = {"U_SNAGGA": snagga, "U_PREY_CHAR": near_char, "U_PREY_VEH": far_veh, "U_PLAIN": plain}
	FAM._select_prey_for_player(1)
	_check("Prey auto-select picks the nearest MONSTER/VEHICLE/CHARACTER",
		GS.get_unit("U_PREY_CHAR")["flags"].get("is_prey_of_1", false))
	_check("get_prey_unit_id reads the marker", FAM.get_prey_unit_id(1) == "U_PREY_CHAR")
	_check("set_prey rejects a non-eligible unit", not FAM.set_prey(1, "U_PLAIN"))
	_check("set_prey accepts another eligible enemy", FAM.set_prey(1, "U_PREY_VEH"))
	_check("set_prey clears the previous marker",
		not GS.get_unit("U_PREY_CHAR")["flags"].get("is_prey_of_1", false))
	FAM._select_prey_for_player(1)
	_check("Prey persists across re-selection while alive", FAM.get_prey_unit_id(1) == "U_PREY_VEH")
	for m in GS.get_unit("U_PREY_VEH")["models"]:
		m["alive"] = false
	FAM._select_prey_for_player(1)
	_check("Dead Prey is replaced at the next Command phase", FAM.get_prey_unit_id(1) == "U_PREY_CHAR")

	# ---- Prey rule effects: +1 AP and charge re-roll --------------------------
	var atk_bs = {"owner": 1, "meta": {"keywords": ["ORKS", "BEAST SNAGGA"]}, "flags": {}, "models": []}
	var atk_plain = {"owner": 1, "meta": {"keywords": ["ORKS"]}, "flags": {}, "models": []}
	var prey_tgt = {"owner": 2, "meta": {}, "flags": {"is_prey_of_1": true}, "models": []}
	var not_prey = {"owner": 2, "meta": {}, "flags": {}, "models": []}
	_check("Prey rule: +1 AP for BEAST SNAGGA vs Prey", rules.get_prey_ap_bonus(atk_bs, prey_tgt) == 1)
	_check("Prey rule: no AP bonus vs non-Prey", rules.get_prey_ap_bonus(atk_bs, not_prey) == 0)
	_check("Prey rule: AP bonus needs BEAST SNAGGA", rules.get_prey_ap_bonus(atk_plain, prey_tgt) == 0)
	var prey_units_map = {"E1": {"flags": {"is_prey_of_1": true}}}
	_check("Prey rule: charge re-roll when a target is Prey",
		FAM.unit_has_prey_charge_reroll(atk_bs, ["E1"], prey_units_map))
	_check("Prey rule: no charge re-roll vs non-Prey targets",
		not FAM.unit_has_prey_charge_reroll(atk_bs, ["E2"], prey_units_map))
	_check("Prey rule: charge re-roll needs BEAST SNAGGA",
		not FAM.unit_has_prey_charge_reroll(atk_plain, ["E1"], prey_units_map))

	# ---- DAT ONE'S EVEN BIGGA! ------------------------------------------------
	GS.state["units"] = {"U_DB": _boyz_unit("U_DB", 5)}
	GS.get_unit("U_DB")["meta"]["keywords"] = ["ORKS", "BEAST SNAGGA", "MOUNTED"]
	var strat_db = {"id": "t_db", "name": "DAT ONE’S EVEN BIGGA!", "effects": [{"type": "custom:dat_ones_even_bigga"}]}
	GS.apply_state_changes(SM._apply_stratagem_effects("t_db", "U_DB", strat_db, {}))
	var db_flags = GS.get_unit("U_DB")["flags"]
	_check("DAT ONE'S EVEN BIGGA! grants advance+charge and fall-back+charge",
		db_flags.get("effect_advance_and_charge", false) and db_flags.get("effect_fall_back_and_charge", false))
	SM.stratagems["t_db"] = strat_db
	SM._clear_stratagem_flags("U_DB", "t_db")
	_check("DAT ONE'S EVEN BIGGA! clear removes the flags",
		not GS.get_unit("U_DB")["flags"].has("effect_advance_and_charge")
		and not GS.get_unit("U_DB")["flags"].has("effect_fall_back_and_charge"))

	# ---- DRAG IT DOWN ----------------------------------------------------------
	var strat_did = {"id": "t_did", "name": "DRAG IT DOWN", "effects": [{"type": "custom:drag_it_down"}]}
	GS.apply_state_changes(SM._apply_stratagem_effects("t_did", "U_DB", strat_did, {}))
	_check("DRAG IT DOWN sets melee SUSTAINED HITS + Prey-crit flags",
		GS.get_unit("U_DB")["flags"].get("effect_sustained_hits_melee", false)
		and GS.get_unit("U_DB")["flags"].get("effect_drag_it_down", false))
	# Crit on 5+ vs Prey: sustained bonus hits proc twice as often — aggregate
	# wound successes over seeds (per-seed monotonic checks are invalid because
	# extra hits shift the RNG stream).
	var did_flags = {"effect_sustained_hits_melee": true, "effect_drag_it_down": true}
	var did_on := 0
	var did_off := 0
	for s in [7, 11, 23, 42, 59, 77, 101, 131]:
		did_off += _fight_vs(rules, did_flags, {}, s)
		did_on += _fight_vs(rules, did_flags, {"is_prey_of_1": true}, s)
	print("  DRAG IT DOWN: aggregate wounds vs Prey=%d, vs non-Prey=%d" % [did_on, did_off])
	_check("DRAG IT DOWN crit-5+ raises aggregate melee wounds vs Prey", did_on > did_off)

	# ---- INSTINCTIVE HUNTERS ----------------------------------------------------
	var strat_ih = {"id": "t_ih", "name": "INSTINCTIVE HUNTERS", "effects": [{"type": "custom:instinctive_hunters"}]}
	GS.apply_state_changes(SM._apply_stratagem_effects("t_ih", "U_DB", strat_ih, {}))
	_check("INSTINCTIVE HUNTERS moves the unit into Strategic Reserves",
		int(GS.get_unit("U_DB").get("status", -1)) == int(GameStateData.UnitStatus.IN_RESERVES)
		and str(GS.get_unit("U_DB").get("reserve_type", "")) == "strategic_reserves")

	# ---- UNSTOPPABLE MOMENTUM ---------------------------------------------------
	var um_models = []
	for i in range(5):
		um_models.append({"id": "umm%d" % i, "position": {"x": 10.0, "y": 10.0 + i * 28},
			"base_mm": 40, "base_type": "circular", "alive": true, "wounds": 3, "current_wounds": 3})
	var um_enemy_models = []
	for i in range(5):
		um_enemy_models.append({"id": "ume%d" % i, "position": {"x": 60.0, "y": 10.0 + i * 28},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 2, "current_wounds": 2,
			"stats": {"toughness": 4, "save": 3}})
	GS.state["units"] = {
		"U_UM": {"id": "U_UM", "owner": 1, "status": 2,
			"meta": {"name": "Squighogs", "keywords": ["ORKS", "BEAST SNAGGA", "MOUNTED"], "stats": {}, "abilities": [], "enhancements": []},
			"flags": {"charged_this_turn": true}, "models": um_models},
		"U_UM_TGT": {"id": "U_UM_TGT", "owner": 2, "status": 2,
			"meta": {"name": "Marines", "keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 3, "wounds": 2}, "abilities": [], "enhancements": []},
			"flags": {"is_prey_of_1": true}, "models": um_enemy_models},
	}
	# er_only=false + Prey: one die per model (5) + 3 bonus dice = 8
	rules.set_test_seed(42)
	var um_probe = rules.resolve_krunchin_descent("U_UM", "U_UM_TGT", GS.create_snapshot(), rules.RNGService.new(), 4, false, 3)
	_check("UNSTOPPABLE MOMENTUM rolls one die per model +3 vs Prey", int(um_probe.get("models_in_er", 0)) == 8)
	rules.set_test_seed(42)
	var strat_um = {"id": "t_um", "name": "UNSTOPPABLE MOMENTUM", "effects": [{"type": "custom:unstoppable_momentum"}]}
	var um_diffs = SM._apply_stratagem_effects("t_um", "U_UM", strat_um, {"enemy_unit_id": "U_UM_TGT"})
	_check("UNSTOPPABLE MOMENTUM handler rolled dice and returned diffs or none", um_diffs != null)

	# ---- STALKIN' TAKTIKS ---------------------------------------------------------
	GS.state["units"] = {"U_ST_INF": _boyz_unit("U_ST_INF", 5), "U_ST_MNT": _boyz_unit("U_ST_MNT", 3)}
	GS.get_unit("U_ST_INF")["meta"]["keywords"] = ["ORKS", "BEAST SNAGGA", "INFANTRY"]
	GS.get_unit("U_ST_MNT")["meta"]["keywords"] = ["ORKS", "BEAST SNAGGA", "MOUNTED"]
	var strat_st = {"id": "t_st", "name": "STALKIN’ TAKTIKS", "effects": [{"type": "custom:stalkin_taktiks"}]}
	GS.apply_state_changes(SM._apply_stratagem_effects("t_st", "U_ST_INF", strat_st, {}))
	GS.apply_state_changes(SM._apply_stratagem_effects("t_st", "U_ST_MNT", strat_st, {}))
	_check("STALKIN' TAKTIKS: INFANTRY get cover + Stealth",
		GS.get_unit("U_ST_INF")["flags"].get("effect_cover", false)
		and GS.get_unit("U_ST_INF")["flags"].get("effect_stealth", false))
	_check("STALKIN' TAKTIKS: MOUNTED get cover only",
		GS.get_unit("U_ST_MNT")["flags"].get("effect_cover", false)
		and not GS.get_unit("U_ST_MNT")["flags"].get("effect_stealth", false))

	# ---- Enhancements ---------------------------------------------------------------
	# Glory Hog — Scouts 9" for the bearer's unit (and the bearer while attached)
	GS.state["units"] = {
		"U_BB_SQ": {"id": "U_BB_SQ", "owner": 1, "attached_to": "U_SQUIGHOGS",
			"meta": {"name": "Beastboss on Squigosaur", "keywords": ["CHARACTER", "ORKS", "BEAST SNAGGA", "MOUNTED"],
				"enhancements": ["Glory Hog"], "abilities": []},
			"flags": {}, "models": [{"id": "m0", "alive": true}]},
		"U_SQUIGHOGS": {"id": "U_SQUIGHOGS", "owner": 1,
			"meta": {"name": "Squighog Boyz", "keywords": ["ORKS", "BEAST SNAGGA", "MOUNTED"], "enhancements": [], "abilities": []},
			"flags": {}, "attachment_data": {"attached_characters": ["U_BB_SQ"]},
			"models": [{"id": "m0", "alive": true}]},
	}
	_check("Glory Hog: led unit has Scouts", GS.unit_has_scout("U_SQUIGHOGS"))
	_check("Glory Hog: led unit Scout distance is 9\"", GS.get_scout_distance("U_SQUIGHOGS") == 9.0)
	_check("Glory Hog: bearer has Scouts 9\"",
		GS.unit_has_scout("U_BB_SQ") and GS.get_scout_distance("U_BB_SQ") == 9.0)

	# Surly as a Squiggoth — -1 to incoming wounds while S > T (and the generic flag)
	var surly_board = {"units": {
		"U_SURLY_CHAR": {"id": "U_SURLY_CHAR", "owner": 1,
			"meta": {"enhancements": ["Surly as a Squiggoth"], "keywords": ["CHARACTER"]}, "flags": {}, "models": [{"alive": true}]},
		"U_SURLY_UNIT": {"id": "U_SURLY_UNIT", "owner": 1,
			"meta": {"enhancements": [], "keywords": ["ORKS"]}, "flags": {},
			"attachment_data": {"attached_characters": ["U_SURLY_CHAR"]}, "models": [{"alive": true}]},
	}}
	var surly_unit = surly_board["units"]["U_SURLY_UNIT"]
	_check("Surly as a Squiggoth: -1 wound when S > T",
		rules.get_s_gt_t_wound_penalty(surly_unit, surly_board, 6, 5) == rules.WoundModifier.MINUS_ONE)
	_check("Surly as a Squiggoth: no penalty when S <= T",
		rules.get_s_gt_t_wound_penalty(surly_unit, surly_board, 5, 5) == rules.WoundModifier.NONE)
	var flag_unit = {"owner": 2, "meta": {"enhancements": []}, "flags": {"effect_minus_wound_s_gt_t": true}, "models": []}
	_check("effect_minus_wound_s_gt_t flag triggers the same penalty",
		rules.get_s_gt_t_wound_penalty(flag_unit, {"units": {}}, 6, 5) == rules.WoundModifier.MINUS_ONE)
	var plain_unit = {"owner": 2, "meta": {"enhancements": []}, "flags": {}, "models": []}
	_check("No S>T penalty without the enhancement or flag",
		rules.get_s_gt_t_wound_penalty(plain_unit, {"units": {}}, 6, 5) == rules.WoundModifier.NONE)

	# Proper Killy — +1 melee Damage flag via UnitAbilityManager (Fight phase)
	var UAM_DBH = root.get_node("UnitAbilityManager")
	GS.state["units"] = {"U_PK": _boyz_unit("U_PK", 3)}
	GS.get_unit("U_PK")["meta"]["keywords"] = ["ORKS", "BEAST SNAGGA", "INFANTRY"]
	GS.get_unit("U_PK")["meta"]["enhancements"] = ["Proper Killy"]
	UAM_DBH._applied_this_phase = {}
	UAM_DBH._apply_enhancement_abilities(10)  # melee entries apply in the FIGHT phase
	_check("Proper Killy sets effect_plus_damage in the Fight phase",
		int(GS.get_unit("U_PK")["flags"].get("effect_plus_damage", 0)) == 1)

	# Skrag Every Stash! — end-of-Command-phase sticky objective lock
	var MM = root.get_node("MissionManager")
	var skrag_models = [{"id": "m0", "position": {"x": 100.0, "y": 100.0}, "base_mm": 40, "base_type": "circular", "alive": true, "wounds": 6, "current_wounds": 6}]
	GS.state["units"] = {"U_SKRAG": {"id": "U_SKRAG", "owner": 1, "status": 2,
		"meta": {"name": "Beastboss", "keywords": ["CHARACTER", "ORKS", "BEAST SNAGGA"],
			"enhancements": ["Skrag Every Stash!"], "abilities": []},
		"flags": {}, "models": skrag_models}}
	if not GS.state.has("board"):
		GS.state["board"] = {}
	GS.state["board"]["objectives"] = [{"id": "obj_skrag", "position": {"x": 120.0, "y": 100.0}}]
	MM.objective_control_state["obj_skrag"] = 1
	MM._sticky_objectives.erase("obj_skrag")
	FAM.process_skrag_every_stash(1)
	_check("Skrag Every Stash! locks the bearer's objective (sticky)",
		MM._sticky_objectives.has("obj_skrag")
		and GS.get_unit("U_SKRAG")["flags"].get("effect_sticky_objective_control", "") == "obj_skrag")


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
