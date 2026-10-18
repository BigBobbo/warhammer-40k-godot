extends SceneTree

# Ork detachment sweep — one section per detachment. Covers the detachment
# rules and enhancements that still run in game (real autoload helpers and
# engine primitives), plus a load check that every detachment now carries its
# Codex: Orks (11e) stratagem rows.
#
# The 10e detachment STRATAGEM checks that used to open each section were
# retired on 2026-10-13 (Codex: Orks 11e replaced every Ork stratagem row);
# the list is in .llm/ork_codex_11e_retired_tests.md. The codex stratagems are
# tested in tests/test_ork_codex_{framework,fight,shooting,shooting_reactive,
# movement,other}.gd and the ork11e_* windowed scenarios.
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


func _fight_result(rules, flags: Dictionary, seed_val: int, tgt_toughness: int = 8, tgt_save: int = 3) -> Dictionary:
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
	return rules.resolve_melee_attacks(action, board, rng)


func _fight(rules, flags: Dictionary, seed_val: int, tgt_toughness: int = 8, tgt_save: int = 3) -> int:
	return _sum_wounds(_fight_result(rules, flags, seed_val, tgt_toughness, tgt_save))


func _sum_casualties(result: Dictionary) -> int:
	var n := 0
	for d in result.get("diffs", []):
		if str(d.get("path", "")).ends_with(".alive") and d.get("value", true) == false:
			n += 1
	return n


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

	_codex_stratagem_rows(SM, GS)
	_green_tide(SM, GS, FAM, rules)
	_more_dakka(SM, GS, FAM, rules)
	_bully_boyz(SM, GS, FAM, rules)
	_da_big_hunt(SM, GS, FAM, rules)
	_kult_of_speed(SM, GS, FAM, rules)
	_dread_mob(SM, GS, FAM, rules)
	_blitz_brigade(SM, GS, FAM, rules)
	_rollin_deff(SM, GS, FAM, rules)
	_detachment_rules(SM, GS, FAM, rules)


# ==========================================================================
# CODEX: ORKS (11e) STRATAGEM ROWS — every detachment loads its codex rows
# (custom:ork11e, implemented by the OrkCodex11e registry); the removed 10e
# detachments load none.
# ==========================================================================
const CODEX_ROWS_PER_DETACHMENT := {
	"War Horde": 6, "Madcap Meks": 1, "Wurrband": 0, "Runt Swarm": 3,
	"Wreckas": 3, "Brute Bosses": 0, "Bully Boyz": 3, "Da Big Hunt": 3,
	"Dread Mob": 3, "Shoota Boyz": 3, "Flyboyz": 3, "Kult of Speed": 3,
	"Blitz Brigade": 3, "Green Tide": 3, "Taktikal Brigade": 3,
}
const REMOVED_10E_DETACHMENTS := ["More Dakka!", "Rollin’ Deff", "Freebooter Krew", "Speedwaaagh!"]


func _codex_stratagem_rows(SM, GS):
	print("\n===== CODEX: ORKS (11e) STRATAGEM ROWS =====")
	var total := 0
	for det in CODEX_ROWS_PER_DETACHMENT:
		var want: int = CODEX_ROWS_PER_DETACHMENT[det]
		var d = _load_detachment(SM, GS, det)
		total += d.count
		var all_codex := true
		for sname in d.by_name:
			var effs: Array = d.by_name[sname].get("effects", [])
			if effs.size() != 1 or str(effs[0].get("type", "")) != "custom:ork11e":
				all_codex = false
		_check("%s: %d codex stratagem row(s) loaded" % [det, want], d.count == want)
		_check("%s: every row is a custom:ork11e row implemented by the codex registry" % det,
			d.implemented == d.count and all_codex)
	_check("Codex: Orks (11e): 40 stratagem rows across the 15 detachments", total == 40)
	for det in REMOVED_10E_DETACHMENTS:
		_check("%s (removed from the codex) loads no stratagems" % det,
			_load_detachment(SM, GS, det).count == 0)


# ==========================================================================
# BULLY BOYZ
# ==========================================================================
func _bully_boyz(SM, GS, FAM, rules):
	print("\n===== BULLY BOYZ =====")
	# Retired 2026-10-13: the 10e Bully Boyz stratagem checks (loading counts, parsed
	# TARGET conditions, legacy custom:<slug> handlers and their flag consumers).
	# Codex: Orks (11e) replaced those rows; see .llm/ork_codex_11e_retired_tests.md.
	# The codex rows are tested in test_ork_codex_fight.gd / test_ork_codex_shooting_reactive.gd.

	# hazard_rolls: -1 modifier increases failures (3s now fail) — the modifier
	# FallBackMove applies to WHERE D'YA FINK YOU'RE GOING?'s extra hazard rolls
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
func _da_big_hunt(SM, GS, FAM, rules):
	print("\n===== DA BIG HUNT =====")
	# Retired 2026-10-13: the 10e Da Big Hunt stratagem checks (loading counts, parsed
	# TARGET conditions, legacy custom:<slug> handlers and their flag consumers).
	# Codex: Orks (11e) replaced those rows; see .llm/ork_codex_11e_retired_tests.md.
	# The codex rows are tested in test_ork_codex_movement.gd / test_ork_codex_shooting_reactive.gd / test_ork_codex_fight.gd.

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
# KULT OF SPEED
# ==========================================================================
func _kult_of_speed(SM, GS, FAM, rules):
	print("\n===== KULT OF SPEED =====")
	# Retired 2026-10-13: the 10e Kult of Speed stratagem checks (loading counts, parsed
	# TARGET conditions, legacy custom:<slug> handlers and their flag consumers).
	# Codex: Orks (11e) replaced those rows; see .llm/ork_codex_11e_retired_tests.md.
	# The codex rows are tested in test_ork_codex_movement.gd / test_ork_codex_shooting.gd / test_ork_codex_shooting_reactive.gd.

	# ---- Enhancements -----------------------------------------------------------
	# Fasta Than Yooz — disembark after the transport's Normal move
	var TM = root.get_node("TransportManager")
	GS.state["units"] = {
		"U_FTY": {"id": "U_FTY", "owner": 1, "embarked_in": "U_TRUKK_T", "status": 2,
			"meta": {"name": "Boyz", "keywords": ["ORKS", "INFANTRY"], "enhancements": ["Fasta Than Yooz"], "abilities": [], "stats": {}},
			"flags": {}, "models": [{"id": "m0", "alive": true, "position": null, "base_mm": 32}]},
		"U_PLAINDIS": {"id": "U_PLAINDIS", "owner": 1, "embarked_in": "U_TRUKK_T", "status": 2,
			"meta": {"name": "Boyz 2", "keywords": ["ORKS", "INFANTRY"], "enhancements": [], "abilities": [], "stats": {}},
			"flags": {}, "models": [{"id": "m0", "alive": true, "position": null, "base_mm": 32}]},
		"U_TRUKK_T": {"id": "U_TRUKK_T", "owner": 1, "status": 2,
			"meta": {"name": "Trukk", "keywords": ["ORKS", "VEHICLE", "TRANSPORT", "TRUKK"], "enhancements": [], "abilities": [], "stats": {}},
			"flags": {"moved": true}, "models": [{"id": "m0", "alive": true, "position": {"x": 50.0, "y": 50.0}, "base_mm": 60}],
			"transport_data": {"embarked_units": ["U_FTY", "U_PLAINDIS"], "capacity": 12}},
	}
	TM.disembark_unit("U_FTY", [Vector2(80, 50)])
	TM.disembark_unit("U_PLAINDIS", [Vector2(120, 50)])
	_check("Fasta Than Yooz: still eligible to charge after transport moved",
		GS.get_unit("U_FTY")["flags"].get("cannot_charge", true) == false)
	_check("Without Fasta Than Yooz: cannot charge after transport moved",
		GS.get_unit("U_PLAINDIS")["flags"].get("cannot_charge", false) == true)

	# Squig-hide Tyres — 6" consolidation while the bearer leads
	GS.state["units"]["U_SHT"] = {"id": "U_SHT", "owner": 1, "status": 2,
		"meta": {"name": "Deffkilla Wartrike", "keywords": ["ORKS", "SPEED FREEKS", "VEHICLE", "CHARACTER"],
			"enhancements": ["Squig-hide Tyres"], "abilities": [], "stats": {}},
		"flags": {}, "models": [{"id": "m0", "alive": true, "position": {"x": 400.0, "y": 50.0}, "base_mm": 60}]}
	var FP = load("res://phases/FightPhase.gd").new()
	FP.game_state_snapshot = GS.state
	_check("Squig-hide Tyres: 6\" consolidation", FP._get_consolidation_distance("U_SHT") == 6.0)
	_check("Plain unit consolidates 3\"", FP._get_consolidation_distance("U_PLAINDIS") == 3.0)
	FP.free()

	# Wazblasta — post-shooting 6" move offer for the unengaged bearer
	GS.state["units"]["U_WAZ"] = {"id": "U_WAZ", "owner": 1, "status": 2,
		"meta": {"name": "Deffkilla Wartrike", "keywords": ["ORKS", "SPEED FREEKS", "VEHICLE", "CHARACTER"],
			"enhancements": ["Wazblasta"], "abilities": [], "stats": {}},
		"flags": {}, "models": [{"id": "m0", "alive": true, "position": {"x": 600.0, "y": 50.0}, "base_mm": 60}]}
	GS.state["meta"]["active_player"] = 1
	var SP = load("res://phases/ShootingPhase.gd").new()
	SP.game_state_snapshot = GS.state
	_check("Wazblasta offered for the unengaged bearer", SP._check_wazblasta("U_WAZ"))
	_check("Wazblasta not offered without the enhancement", not SP._check_wazblasta("U_SHT"))
	# Simulate the pending state, then use it
	SP.awaiting_wazblasta = true
	SP.wazblasta_pending_unit = "U_WAZ"
	var waz_use = SP._process_use_wazblasta({})
	var waz_diffs = waz_use.get("changes", [])
	var waz_paths := []
	for d in waz_diffs:
		waz_paths.append(str(d.get("path", "")))
	_check("Wazblasta use grants the 6\" post-shoot move and blocks charging",
		("units.U_WAZ.flags.swift_eagle_move_remaining" in waz_paths)
		and ("units.U_WAZ.flags.cannot_charge" in waz_paths))
	SP.free()

	# Speed Makes Right — Command-phase D6 (3+) while within 9" of an enemy
	var smr_grants := 0
	for s in range(1, 9):
		GS.state["units"] = {
			"U_SMR": {"id": "U_SMR", "owner": 1, "status": 2,
				"meta": {"name": "Deffkilla Wartrike", "keywords": ["ORKS", "SPEED FREEKS", "VEHICLE", "CHARACTER"],
					"enhancements": ["Speed Makes Right"], "abilities": [], "stats": {}},
				"flags": {}, "models": [{"id": "m0", "alive": true, "position": {"x": 100.0, "y": 100.0}, "base_mm": 60}]},
			"U_SMR_ENEMY": {"id": "U_SMR_ENEMY", "owner": 2, "status": 2,
				"meta": {"name": "Marines", "keywords": ["INFANTRY"], "enhancements": [], "abilities": [], "stats": {}},
				"flags": {}, "models": [{"id": "e0", "alive": true, "position": {"x": 300.0, "y": 100.0}, "base_mm": 32}]},
		}
		GS.state["players"] = {"1": {"cp": 3, "vp": 0, "primary_vp": 0, "secondary_vp": 0, "bonus_cp_gained_this_round": 0},
			"2": {"cp": 3, "vp": 0, "primary_vp": 0, "secondary_vp": 0, "bonus_cp_gained_this_round": 0}}
		rules.set_test_seed(s)
		FAM.process_command_phase_cp_enhancements(1)
		if int(GS.state["players"]["1"]["cp"]) == 4:
			smr_grants += 1
	print("  Speed Makes Right: %d/8 seeds granted CP" % smr_grants)
	_check("Speed Makes Right grants CP on 3+ (some seeds)", smr_grants >= 1)
	var smr_far_grants := 0
	for s in range(1, 9):
		GS.state["units"]["U_SMR_ENEMY"]["models"][0]["position"] = {"x": 2000.0, "y": 100.0}
		GS.state["players"]["1"] = {"cp": 3, "vp": 0, "primary_vp": 0, "secondary_vp": 0, "bonus_cp_gained_this_round": 0}
		rules.set_test_seed(s)
		FAM.process_command_phase_cp_enhancements(1)
		if int(GS.state["players"]["1"]["cp"]) == 4:
			smr_far_grants += 1
	_check("Speed Makes Right needs an enemy within 9\"", smr_far_grants == 0)


# ==========================================================================
# DREAD MOB
# ==========================================================================
func _dread_mob(SM, GS, FAM, rules):
	print("\n===== DREAD MOB =====")
	# Retired 2026-10-13: the 10e Dread Mob stratagem checks (loading counts, parsed
	# TARGET conditions, legacy custom:<slug> handlers and their flag consumers).
	# Codex: Orks (11e) replaced those rows; see .llm/ork_codex_11e_retired_tests.md.
	# The codex rows are tested in test_ork_codex_fight.gd / test_ork_codex_movement.gd / test_ork_codex_other.gd.

	# ---- Enhancements -----------------------------------------------------------
	var UAM_DM = root.get_node("UnitAbilityManager")
	GS.state["units"] = {"U_MEKGUNZ": _boyz_unit("U_MEKGUNZ", 3)}
	GS.get_unit("U_MEKGUNZ")["meta"]["keywords"] = ["ORKS", "INFANTRY", "MEK"]
	GS.get_unit("U_MEKGUNZ")["meta"]["enhancements"] = ["Gitfinder Googlez", "Smoky Gubbinz"]
	UAM_DM._applied_this_phase = {}
	UAM_DM._apply_enhancement_abilities(8)
	var dm_flags = GS.get_unit("U_MEKGUNZ")["flags"]
	_check("Gitfinder Googlez sets effect_ignores_cover", dm_flags.get("effect_ignores_cover", false))
	_check("Smoky Gubbinz sets effect_stealth", dm_flags.get("effect_stealth", false))
	_check("Press It Fasta! is implemented (extra Try Dat Button! die)",
		UAM_DM.ABILITY_EFFECTS.get("Press It Fasta!", {}).get("implemented", false) == true)

	# Supa-glowy Fing — D6 table vs the nearest visible enemy within 18"
	var sgf_seen := {"shock": false, "mw": false, "debuff": false}
	for s in range(1, 13):
		GS.state["units"] = {
			"U_SGF": {"id": "U_SGF", "owner": 1, "status": 2,
				"meta": {"name": "Big Mek", "keywords": ["ORKS", "INFANTRY", "CHARACTER", "MEK"],
					"enhancements": ["Supa-glowy Fing"], "abilities": [], "stats": {"leadership": 6}},
				"flags": {}, "models": [{"id": "m0", "position": {"x": 100.0, "y": 100.0}, "base_mm": 32, "base_type": "circular", "alive": true, "wounds": 4, "current_wounds": 4}]},
			"U_SGF_TGT": {"id": "U_SGF_TGT", "owner": 2, "status": 2,
				"meta": {"name": "Guardsmen", "keywords": ["INFANTRY"], "abilities": [], "enhancements": [], "stats": {"leadership": 12, "wounds": 2}},
				"flags": {}, "models": [{"id": "e0", "position": {"x": 300.0, "y": 100.0}, "base_mm": 32, "base_type": "circular", "alive": true, "wounds": 2, "current_wounds": 2}]},
		}
		rules.set_test_seed(s)
		FAM.process_supa_glowy_fing(1)
		var tgt = GS.get_unit("U_SGF_TGT")
		if tgt["flags"].get("battle_shocked", false):
			sgf_seen["shock"] = true
		elif tgt["flags"].get("effect_minus_one_hit", false):
			sgf_seen["debuff"] = true
			_check("Supa-glowy debuff records its owner for expiry",
				int(tgt["flags"].get("supa_glowy_debuff_from", 0)) == 1)
			FAM._clear_supa_glowy_debuffs(1)
			_check("Supa-glowy debuff expires at the owner's next Command phase",
				not GS.get_unit("U_SGF_TGT")["flags"].has("effect_minus_one_hit"))
		elif int(tgt["models"][0].get("current_wounds", 2)) < 2 or not tgt["models"][0].get("alive", true):
			sgf_seen["mw"] = true
	print("  Supa-glowy Fing outcomes seen: %s" % str(sgf_seen))
	_check("Supa-glowy Fing produced battle-shock, MW and debuff outcomes across seeds",
		sgf_seen["shock"] and sgf_seen["mw"] and sgf_seen["debuff"])


# ==========================================================================
# BLITZ BRIGADE
# ==========================================================================
func _blitz_brigade(SM, GS, FAM, rules):
	print("\n===== BLITZ BRIGADE =====")
	# Retired 2026-10-13: the 10e Blitz Brigade stratagem checks (loading counts, parsed
	# TARGET conditions, legacy custom:<slug> handlers and their flag consumers).
	# Codex: Orks (11e) replaced those rows; see .llm/ork_codex_11e_retired_tests.md.
	# The codex rows are tested in test_ork_codex_fight.gd / test_ork_codex_movement.gd / test_ork_codex_other.gd.

	# ---- Tuff Git: disembark hook ------------------------------------------------
	var TM_BB = root.get_node("TransportManager")
	GS.state["units"] = {
		"U_RIG": {"id": "U_RIG", "owner": 1, "status": 2,
			"meta": {"name": "Battlewagon", "keywords": ["ORKS", "VEHICLE", "TRANSPORT", "BATTLEWAGON"], "enhancements": [], "abilities": [], "stats": {}},
			"flags": {"moved": true},
			"models": [{"id": "m0", "alive": true, "position": {"x": 100.0, "y": 100.0}, "base_mm": 100}],
			"transport_data": {"embarked_units": ["U_BOYZ_TG"], "capacity": 22}},
		"U_BOYZ_TG": {"id": "U_BOYZ_TG", "owner": 1, "embarked_in": "U_RIG", "status": 2,
			"meta": {"name": "Boyz TG", "keywords": ["ORKS", "INFANTRY"], "enhancements": ["Tuff Git"], "abilities": [], "stats": {}},
			"flags": {"battle_shocked": true}, "models": [{"id": "m0", "alive": true, "position": null, "base_mm": 32}]},
	}
	TM_BB.disembark_unit("U_BOYZ_TG", [Vector2(180, 100)])
	_check("Tuff Git: Battle-shock cleared on disembark",
		GS.get_unit("U_BOYZ_TG")["flags"].get("battle_shocked", true) == false)

	# ---- Enhancements ---------------------------------------------------------------
	# Runnin' Boots — +1 charge after disembarking this turn
	var rb_unit = {"disembarked_this_phase": true, "meta": {"enhancements": ["Runnin' Boots"], "keywords": ["ORKS", "INFANTRY"]}, "flags": {}, "models": []}
	var rb_stay = {"meta": {"enhancements": ["Runnin' Boots"], "keywords": ["ORKS", "INFANTRY"]}, "flags": {}, "models": []}
	var rb_plain = {"disembarked_this_phase": true, "meta": {"enhancements": [], "keywords": ["ORKS", "INFANTRY"]}, "flags": {}, "models": []}
	_check("Runnin' Boots: +1 charge after disembarking", FAM.runnin_boots_charge_bonus(rb_unit, {}) == 1)
	_check("Runnin' Boots: no bonus without disembark", FAM.runnin_boots_charge_bonus(rb_stay, {}) == 0)
	_check("Runnin' Boots: no bonus without the enhancement", FAM.runnin_boots_charge_bonus(rb_plain, {}) == 0)

	# Blitzkaptin — 3 VEHICLE redeploys via the Mork's Kunnin' machinery
	GS.state["units"] = {
		"U_BK": {"id": "U_BK", "owner": 1, "status": 2,
			"meta": {"name": "Warboss", "keywords": ["ORKS", "CHARACTER", "INFANTRY"], "enhancements": ["Blitzkaptin"], "abilities": []},
			"flags": {}, "models": [{"id": "m0", "alive": true, "position": {"x": 50.0, "y": 50.0}, "base_mm": 40}]},
		"U_BK_VEH": {"id": "U_BK_VEH", "owner": 1, "status": 2,
			"meta": {"name": "Battlewagon", "keywords": ["ORKS", "VEHICLE", "BATTLEWAGON"], "enhancements": [], "abilities": []},
			"flags": {}, "models": [{"id": "m0", "alive": true, "position": {"x": 90.0, "y": 50.0}, "base_mm": 100}]},
		"U_BK_INF": {"id": "U_BK_INF", "owner": 1, "status": 2,
			"meta": {"name": "Boyz", "keywords": ["ORKS", "INFANTRY"], "enhancements": [], "abilities": []},
			"flags": {}, "models": [{"id": "m0", "alive": true, "position": {"x": 130.0, "y": 50.0}, "base_mm": 32}]},
	}
	_check("Blitzkaptin detected", FAM.has_blitzkaptin(1))
	var bk_eligible = FAM.get_morks_kunnin_eligible_units(1)
	var bk_ids: Array = []
	for e in bk_eligible:
		bk_ids.append(e.get("unit_id", ""))
	_check("Blitzkaptin: VEHICLE eligible, INFANTRY not",
		"U_BK_VEH" in bk_ids and not "U_BK_INF" in bk_ids)
	_check("Blitzkaptin: redeploy available", FAM.is_morks_kunnin_redeploy_available(1))
	_check("Blitzkaptin: vehicle appears in the redeploy list",
		"U_BK_VEH" in GS.get_redeploy_units_for_player(1))

	# (Retired, WP-O6: the Supercharged Squig Oil check rode on the 10e Mekaniak
	# ability, which no Codex: Orks (11e) datasheet has — the enhancement's codex
	# hook is WP-O5's. .llm/codex_11e_wahapedia/RETIRED_TESTS.md)


# ==========================================================================
# ROLLIN' DEFF — detachment removed from Codex: Orks (11e); its enhancement
# helpers are still in the code and pinned here
# ==========================================================================
func _rollin_deff(SM, GS, FAM, rules):
	print("\n===== ROLLIN' DEFF =====")
	# Retired 2026-10-13: the 10e Rollin' Deff stratagem checks (loading counts, parsed
	# TARGET conditions, legacy custom:<slug> handlers and their flag consumers).
	# Codex: Orks (11e) replaced those rows; see .llm/ork_codex_11e_retired_tests.md.

	# ---- Enhancements --------------------------------------------------------------
	# Boarding Ramps — +1 charge for units that left the flagged WAGON this turn
	var TM_RD = root.get_node("TransportManager")
	GS.state["units"] = {
		"U_BR_WAGON": {"id": "U_BR_WAGON", "owner": 1, "status": 2,
			"meta": {"name": "Battlewagon", "keywords": ["ORKS", "VEHICLE", "TRANSPORT", "BATTLEWAGON"], "enhancements": ["Boarding Ramps"], "abilities": [], "stats": {}},
			"flags": {}, "models": [{"id": "m0", "alive": true, "position": {"x": 100.0, "y": 100.0}, "base_mm": 100}],
			"transport_data": {"embarked_units": ["U_BR_BOYZ"], "capacity": 22}},
		"U_BR_BOYZ": {"id": "U_BR_BOYZ", "owner": 1, "embarked_in": "U_BR_WAGON", "status": 2,
			"meta": {"name": "Boyz", "keywords": ["ORKS", "INFANTRY"], "enhancements": [], "abilities": [], "stats": {}},
			"flags": {}, "models": [{"id": "m0", "alive": true, "position": null, "base_mm": 32}]},
	}
	TM_RD.disembark_unit("U_BR_BOYZ", [Vector2(170, 100)])
	_check("Boarding Ramps: +1 charge after disembarking from the flagged wagon",
		FAM.boarding_ramps_charge_bonus(GS.get_unit("U_BR_BOYZ"), GS.state.get("units", {})) == 1)
	GS.get_unit("U_BR_WAGON")["meta"]["enhancements"] = []
	_check("Boarding Ramps: no bonus when the wagon lacks the enhancement",
		FAM.boarding_ramps_charge_bonus(GS.get_unit("U_BR_BOYZ"), GS.state.get("units", {})) == 0)

	# Targetin' Gizmos — SUSTAINED HITS 1 on ranged only while a Waaagh! is active
	var tg_unit = {"owner": 1, "meta": {"enhancements": ["Targetin’ Gizmos"], "keywords": ["ORKS", "VEHICLE"]}, "flags": {}, "models": []}
	_check("Targetin' Gizmos: no sustained without a Waaagh!", FAM.targetin_gizmos_sustained(tg_unit) == 0)
	tg_unit["flags"]["waaagh_active"] = true
	_check("Targetin' Gizmos: SUSTAINED HITS 1 during a Waaagh!", FAM.targetin_gizmos_sustained(tg_unit) == 1)
	_check("Dead Shiny Shootas / Da Gobshot Thunderbuss shared entries exist",
		root.get_node("UnitAbilityManager").ABILITY_EFFECTS.has("Dead Shiny Shootas")
		and root.get_node("UnitAbilityManager").ABILITY_EFFECTS.has("Da Gobshot Thunderbuss"))


# ==========================================================================
# PASSIVE DETACHMENT RULES (Mob Mentality / Dakka!x3 / Adrenaline Junkies /
# Eager for the Fight / Thundering Wagons / keyword grants)
# ==========================================================================
func _set_detachment(GS, FAM, player: int, detachment: String) -> void:
	if not GS.state.has("factions"):
		GS.state["factions"] = {}
	GS.state["factions"][str(player)] = {"name": "Orks", "detachment": detachment}
	FAM.detect_player_detachment(player)


func _detachment_rules(_SM, GS, FAM, rules):
	print("\n===== PASSIVE DETACHMENT RULES =====")

	# ---- Green Tide — Mob Mentality --------------------------------------------
	_set_detachment(GS, FAM, 1, "Green Tide")
	GS.state["units"] = {
		"U_MM_BIG": _boyz_unit("U_MM_BIG", 12),
		"U_MM_SMALL": _boyz_unit("U_MM_SMALL", 5),
		"U_MM_GRETCHIN": _boyz_unit("U_MM_GRETCHIN", 10),
		"U_MM_SHIELDED": _boyz_unit("U_MM_SHIELDED", 12),
	}
	GS.get_unit("U_MM_GRETCHIN")["meta"]["keywords"] = ["ORKS", "INFANTRY", "GRETCHIN"]
	GS.get_unit("U_MM_SHIELDED")["flags"]["effect_invuln"] = 4
	GS.get_unit("U_MM_SHIELDED")["flags"]["effect_invuln_source"] = "Test Shield"
	FAM._apply_mob_mentality(1)
	_check("Mob Mentality: 5+ invulnerable for a 12-model BOYZ unit",
		int(GS.get_unit("U_MM_BIG")["flags"].get("effect_invuln", 0)) == 5)
	_check("Mob Mentality: 6+ invulnerable for a 5-model BOYZ unit",
		int(GS.get_unit("U_MM_SMALL")["flags"].get("effect_invuln", 0)) == 6)
	_check("Mob Mentality: non-BOYZ untouched",
		not GS.get_unit("U_MM_GRETCHIN")["flags"].has("effect_invuln"))
	_check("Mob Mentality: never overwrites a better invulnerable save",
		int(GS.get_unit("U_MM_SHIELDED")["flags"].get("effect_invuln", 0)) == 4
		and GS.get_unit("U_MM_SHIELDED")["flags"].get("effect_invuln_source", "") == "Test Shield")

	# ---- Keyword grants ----------------------------------------------------------
	_set_detachment(GS, FAM, 1, "Dread Mob")
	GS.state["units"] = {"U_KG_GROTS": _boyz_unit("U_KG_GROTS", 10), "U_KG_STORM": _boyz_unit("U_KG_STORM", 5)}
	GS.get_unit("U_KG_GROTS")["meta"]["keywords"] = ["ORKS", "INFANTRY", "GRETCHIN"]
	GS.get_unit("U_KG_STORM")["meta"]["keywords"] = ["ORKS", "INFANTRY", "STORMBOYZ"]
	FAM._apply_detachment_keyword_grants(1, "Dread Mob")
	_check("Dread Mob: Gretchin gain BATTLELINE",
		"BATTLELINE" in GS.get_unit("U_KG_GROTS")["meta"]["keywords"])
	_check("Dread Mob: Stormboyz do not",
		not "BATTLELINE" in GS.get_unit("U_KG_STORM")["meta"]["keywords"])
	FAM._apply_detachment_keyword_grants(1, "Taktikal Brigade")
	_check("Taktikal Brigade: Stormboyz gain BATTLELINE",
		"BATTLELINE" in GS.get_unit("U_KG_STORM")["meta"]["keywords"])

	# ---- More Dakka! — Dakka! Dakka! Dakka! ---------------------------------------
	_set_detachment(GS, FAM, 1, "More Dakka!")
	var md_inf = {"owner": 1, "meta": {"keywords": ["ORKS", "INFANTRY"]}, "flags": {}, "models": []}
	var md_veh = {"owner": 1, "meta": {"keywords": ["ORKS", "VEHICLE"]}, "flags": {}, "models": []}
	var md_walker = {"owner": 1, "meta": {"keywords": ["VEHICLE", "WALKER", "GROTS"]}, "flags": {}, "models": []}
	_check("Dakka!x3: ORKS INFANTRY have unit-wide ASSAULT", FAM.unit_has_detachment_assault(md_inf))
	_check("Dakka!x3: non-Walker VEHICLE does not", not FAM.unit_has_detachment_assault(md_veh))
	_check("Dakka!x3: no sustained without a Waaagh!", not FAM.unit_has_more_dakka_waaagh_sustained(md_inf))
	md_inf["flags"]["waaagh_active"] = true
	_check("Dakka!x3: SUSTAINED HITS 1 during the Waaagh!", FAM.unit_has_more_dakka_waaagh_sustained(md_inf))
	_check("Dakka!x3: Grots Walker lacks ORKS keyword — no ASSAULT", not FAM.unit_has_detachment_assault(md_walker))

	# ---- Kult of Speed — Adrenaline Junkies ----------------------------------------
	_set_detachment(GS, FAM, 1, "Kult of Speed")
	var aj_freek = {"owner": 1, "meta": {"keywords": ["ORKS", "SPEED FREEKS", "MOUNTED"]}, "flags": {}, "models": []}
	var aj_boyz = {"owner": 1, "meta": {"keywords": ["ORKS", "INFANTRY", "BOYZ"]}, "flags": {}, "models": []}
	_check("Adrenaline Junkies: Speed Freeks qualify", FAM.unit_has_adrenaline_junkies(aj_freek))
	_check("Adrenaline Junkies: Boyz do not", not FAM.unit_has_adrenaline_junkies(aj_boyz))
	_check("Adrenaline Junkies: Speed Freeks get unit-wide ASSAULT too", FAM.unit_has_detachment_assault(aj_freek))
	_set_detachment(GS, FAM, 1, "War Horde")
	_check("Adrenaline Junkies: inactive outside Kult of Speed", not FAM.unit_has_adrenaline_junkies(aj_freek))

	# ---- Blitz Brigade — Eager for the Fight ----------------------------------------
	_set_detachment(GS, FAM, 1, "Blitz Brigade")
	var ef_out = {"owner": 1, "disembarked_this_phase": true, "meta": {"keywords": ["ORKS", "INFANTRY"]}, "flags": {}, "models": []}
	var ef_in = {"owner": 1, "meta": {"keywords": ["ORKS", "INFANTRY"]}, "flags": {}, "models": []}
	_check("Eager for the Fight: charge re-roll after disembarking", FAM.unit_has_detachment_charge_reroll(ef_out))
	_check("Eager for the Fight: advance re-roll after disembarking", FAM.unit_has_detachment_advance_reroll(ef_out))
	_check("Eager for the Fight: nothing without a disembark", not FAM.unit_has_detachment_charge_reroll(ef_in))

	# ---- Rollin' Deff — Thundering Wagons ---------------------------------------------
	_set_detachment(GS, FAM, 1, "Rollin’ Deff")
	var tw_rig = {"owner": 1, "meta": {"keywords": ["MONSTER", "TRANSPORT", "KILL RIG"]}, "flags": {}, "models": []}
	var tw_trukk = {"owner": 1, "meta": {"keywords": ["ORKS", "VEHICLE", "TRUKK"]}, "flags": {}, "models": []}
	_check("Thundering Wagons: Kill Rig re-rolls charges", FAM.unit_has_detachment_charge_reroll(tw_rig))
	_check("Thundering Wagons: Kill Rig advances a flat 6\"", FAM.get_thundering_wagons_advance_override(tw_rig) == 6)
	_check("Thundering Wagons: Trukk is not a rig", FAM.get_thundering_wagons_advance_override(tw_trukk) == 0
		and not FAM.unit_has_detachment_charge_reroll(tw_trukk))

	# ---- Dread Mob — Try Dat Button! ---------------------------------------------
	_set_detachment(GS, FAM, 1, "Dread Mob")
	var tdb_bands = {"sustained": false, "lethal": false, "ap2": false}
	var tdb_one_each := true
	for s in range(1, 13):
		GS.state["units"] = {"U_TDB": _boyz_unit("U_TDB", 3)}
		GS.get_unit("U_TDB")["meta"]["keywords"] = ["VEHICLE", "WALKER", "GROTS"]
		rules.set_test_seed(s)
		FAM.process_try_dat_button("U_TDB", "ranged")
		var tf = GS.get_unit("U_TDB")["flags"]
		var set_count = int(tf.get("effect_try_dat_sustained_ranged", false)) \
			+ int(tf.get("effect_try_dat_lethal_ranged", false)) + int(tf.get("effect_try_dat_ap2", false))
		if set_count != 1:
			tdb_one_each = false
		if tf.get("effect_try_dat_sustained_ranged", false):
			tdb_bands["sustained"] = true
		if tf.get("effect_try_dat_lethal_ranged", false):
			tdb_bands["lethal"] = true
		if tf.get("effect_try_dat_ap2", false):
			tdb_bands["ap2"] = true
	print("  Try Dat Button! bands seen: %s" % str(tdb_bands))
	_check("Try Dat Button! grants exactly one Button Effect per roll", tdb_one_each)
	_check("Try Dat Button! all three bands appear across seeds",
		tdb_bands["sustained"] and tdb_bands["lethal"] and tdb_bands["ap2"])

	# Re-selecting keeps the first result
	var tdb_before = GS.get_unit("U_TDB")["flags"].duplicate()
	rules.set_test_seed(99)
	FAM.process_try_dat_button("U_TDB", "ranged")
	_check("Try Dat Button! does not re-roll on re-selection",
		str(GS.get_unit("U_TDB")["flags"]) == str(tdb_before))

	# Ineligible cases: wrong keywords / wrong detachment roll nothing
	GS.state["units"] = {"U_TDB_BOYZ": _boyz_unit("U_TDB_BOYZ", 5)}
	FAM.process_try_dat_button("U_TDB_BOYZ", "ranged")
	_check("Try Dat Button! ignores non-Mek/Walker/Grots-Vehicle units",
		not GS.get_unit("U_TDB_BOYZ")["flags"].has("try_dat_rolled_this_phase"))
	_set_detachment(GS, FAM, 1, "War Horde")
	GS.state["units"] = {"U_TDB2": _boyz_unit("U_TDB2", 1)}
	GS.get_unit("U_TDB2")["meta"]["keywords"] = ["ORKS", "WALKER", "VEHICLE"]
	FAM.process_try_dat_button("U_TDB2", "ranged")
	_check("Try Dat Button! only fires for Dread Mob",
		not GS.get_unit("U_TDB2")["flags"].has("try_dat_rolled_this_phase"))
	_set_detachment(GS, FAM, 1, "Dread Mob")

	# Press It Fasta!: two dice — two DISTINCT Button Effects on some seed
	var pif_double_seen := false
	for s in range(1, 13):
		GS.state["units"] = {"U_PIF": _boyz_unit("U_PIF", 3)}
		GS.get_unit("U_PIF")["meta"]["keywords"] = ["ORKS", "INFANTRY", "MEK"]
		GS.get_unit("U_PIF")["meta"]["enhancements"] = ["Press It Fasta!"]
		rules.set_test_seed(s)
		FAM.process_try_dat_button("U_PIF", "melee")
		var pf = GS.get_unit("U_PIF")["flags"]
		var pif_count = int(pf.get("effect_try_dat_sustained_melee", false)) \
			+ int(pf.get("effect_try_dat_lethal_melee", false)) + int(pf.get("effect_try_dat_ap2", false))
		if pif_count == 2:
			pif_double_seen = true
			break
	_check("Press It Fasta! yields two distinct Button Effects on some seed", pif_double_seen)

	# Melee flags feed the melee resolver; +2 AP raises casualties
	var tdb_cas_on := 0
	var tdb_cas_off := 0
	for s in [11, 42, 77]:
		tdb_cas_off += _sum_casualties(_fight_result(rules, {}, s, 3, 3))
		tdb_cas_on += _sum_casualties(_fight_result(rules, {"effect_try_dat_ap2": true}, s, 3, 3))
	print("  Try Dat Button! +2 AP: casualties with=%d, without=%d" % [tdb_cas_on, tdb_cas_off])
	_check("Try Dat Button! +2 AP raises melee casualties", tdb_cas_on > tdb_cas_off)
	var tdb_sus_on := 0
	var tdb_sus_off := 0
	for s in [11, 42, 77]:
		tdb_sus_off += _fight(rules, {}, s, 3, 6)
		tdb_sus_on += _fight(rules, {"effect_try_dat_sustained_melee": true}, s, 3, 6)
	print("  Try Dat Button! melee sustained: wounds with=%d, without=%d" % [tdb_sus_on, tdb_sus_off])
	_check("Try Dat Button! melee SUSTAINED HITS raises wounds", tdb_sus_on > tdb_sus_off)

	# End-of-phase clear
	GS.state["units"] = {"U_TDB3": _boyz_unit("U_TDB3", 1)}
	GS.get_unit("U_TDB3")["meta"]["keywords"] = ["ORKS", "WALKER", "VEHICLE"]
	rules.set_test_seed(3)
	FAM.process_try_dat_button("U_TDB3", "ranged")
	FAM.clear_try_dat_flags("ranged")
	var tdb3_flags = GS.get_unit("U_TDB3")["flags"]
	_check("Try Dat Button! effects expire at end of phase",
		not tdb3_flags.has("try_dat_rolled_this_phase")
		and not tdb3_flags.has("effect_try_dat_sustained_ranged")
		and not tdb3_flags.has("effect_try_dat_lethal_ranged")
		and not tdb3_flags.has("effect_try_dat_ap2"))
	_set_detachment(GS, FAM, 1, "War Horde")

	# ---- Taktikal Brigade — Lissen 'Ere (Taktiks) + Gob Boomer ------------------
	print("\n--- Lissen 'Ere — Taktiks (Taktikal Brigade) ---")
	_set_detachment(GS, FAM, 1, "Taktikal Brigade")
	GS.state["meta"]["battle_round"] = 1

	var tk_boss = _boyz_unit("U_TK_BOSS", 1)
	tk_boss["meta"]["keywords"] = ["CHARACTER", "INFANTRY", "ORKS", "WARBOSS"]
	var tk_near = _boyz_unit("U_TK_NEAR", 5)          # on top of the boss — inside 6"
	var tk_far = _boyz_unit("U_TK_FAR", 5)            # 12" out: outside 6", inside 18"
	for m in tk_far["models"]:
		m["position"]["x"] += 480.0
	var tk_shocked = _boyz_unit("U_TK_SHOCKED", 5)
	tk_shocked["flags"]["battle_shocked"] = true
	var tk_mega = _boyz_unit("U_TK_MEGA", 3)
	tk_mega["meta"]["keywords"] = ["ORKS", "INFANTRY", "MEGANOBZ"]
	var tk_wagon = _boyz_unit("U_TK_WAGON", 1)
	tk_wagon["meta"]["keywords"] = ["ORKS", "VEHICLE", "TRANSPORT", "BATTLEWAGON"]
	var tk_enemy = _boyz_unit("U_TK_ENEMY", 5, 2)
	GS.state["units"] = {
		"U_TK_BOSS": tk_boss, "U_TK_NEAR": tk_near, "U_TK_FAR": tk_far,
		"U_TK_SHOCKED": tk_shocked, "U_TK_MEGA": tk_mega,
		"U_TK_WAGON": tk_wagon, "U_TK_ENEMY": tk_enemy,
	}

	var tk_issuers = FAM.get_taktik_issuers(1)
	_check("Taktiks: Warboss is an issuer", "U_TK_BOSS" in tk_issuers)
	_check("Taktiks: plain Boyz are not issuers", not "U_TK_NEAR" in tk_issuers)

	# Validation matrix
	_check("Taktiks: mob inside 6\" is a legal target",
		FAM.can_issue_taktik("U_TK_BOSS", "Get Stuck In", "U_TK_NEAR").can)
	_check("Taktiks: an issuer can take its own Taktik",
		FAM.can_issue_taktik("U_TK_BOSS", "Get Stuck In", "U_TK_BOSS").can)
	_check("Taktiks: mob at 12\" is out of the 6\" range",
		not FAM.can_issue_taktik("U_TK_BOSS", "Get Stuck In", "U_TK_FAR").can)
	_check("Taktiks: Battle-shocked units refuse orders",
		not FAM.can_issue_taktik("U_TK_BOSS", "Get Stuck In", "U_TK_SHOCKED").can)
	_check("Taktiks: enemy units are not targets",
		not FAM.can_issue_taktik("U_TK_BOSS", "Get Stuck In", "U_TK_ENEMY").can)
	_check("Taktiks: unknown Taktik name rejected",
		not FAM.can_issue_taktik("U_TK_BOSS", "Krump Dem", "U_TK_NEAR").can)
	_check("Taktiks: non-issuer units cannot issue",
		not FAM.can_issue_taktik("U_TK_NEAR", "Get Stuck In", "U_TK_NEAR").can)
	_check("Taktiks: Sneaky Stalkin' excludes Meganobz",
		not FAM.can_issue_taktik("U_TK_BOSS", "Sneaky Stalkin'", "U_TK_MEGA").can)
	_check("Taktiks: Meganobz may still Get Stuck In",
		FAM.can_issue_taktik("U_TK_BOSS", "Get Stuck In", "U_TK_MEGA").can)
	_check("Taktiks: Shoota Drills refuses a Battlewagon (Infantry/Mounted only)",
		not FAM.can_issue_taktik("U_TK_BOSS", "Shoota Drills", "U_TK_WAGON").can)
	_check("Taktiks: a Battlewagon can still Get On Wiv It",
		FAM.can_issue_taktik("U_TK_BOSS", "Get On Wiv It", "U_TK_WAGON").can)
	_set_detachment(GS, FAM, 1, "War Horde")
	_check("Taktiks: require the Taktikal Brigade detachment",
		not FAM.can_issue_taktik("U_TK_BOSS", "Get Stuck In", "U_TK_NEAR").can
		and FAM.get_taktik_issuers(1).is_empty())
	_set_detachment(GS, FAM, 1, "Taktikal Brigade")

	# Gob Boomer — 18" reach, Infantry/Mounted targets only
	tk_boss["meta"]["enhancements"] = ["Gob Boomer"]
	_check("Gob Boomer: the 12\" Infantry mob comes into reach",
		FAM.can_issue_taktik("U_TK_BOSS", "Get Stuck In", "U_TK_FAR").can)
	for m in tk_wagon["models"]:
		m["position"]["x"] += 480.0
	_check("Gob Boomer: a 12\" Battlewagon stays out of reach (Infantry/Mounted only)",
		not FAM.can_issue_taktik("U_TK_BOSS", "Get On Wiv It", "U_TK_WAGON").can)
	tk_boss["meta"]["enhancements"] = []
	var UAM_TK = root.get_node("UnitAbilityManager")
	_check("Gob Boomer is implemented in UnitAbilityManager",
		UAM_TK.ABILITY_EFFECTS.get("Gob Boomer", {}).get("implemented", false) == true)

	# Leadership test outcomes across seeds: pass = no damage, fail = exactly
	# 1 mortal wound on the receiving unit (the Taktik lands either way)
	var tk_pass_seen := false
	var tk_fail_seen := false
	var tk_outcomes_ok := true
	for s in range(1, 15):
		GS.state["meta"]["battle_round"] = 1
		tk_boss["flags"] = {}
		tk_near["flags"] = {}
		for m in tk_near["models"]:
			m["alive"] = true
			m["current_wounds"] = 1
		rules.set_test_seed(s)
		var res = FAM.issue_taktik("U_TK_BOSS", "Get Stuck In", "U_TK_NEAR")
		if not res.get("success", false):
			tk_outcomes_ok = false
			continue
		var tk_lost := 0
		for m in tk_near["models"]:
			if not m.get("alive", true):
				tk_lost += 1
		if res.get("ld_passed", false):
			tk_pass_seen = true
			if tk_lost != 0:
				tk_outcomes_ok = false
		else:
			tk_fail_seen = true
			if tk_lost != 1:
				tk_outcomes_ok = false
		if not tk_near["flags"].get("effect_reroll_charge", false):
			tk_outcomes_ok = false
	_check("Taktiks: Ld test passes and fails both appear across seeds",
		tk_pass_seen and tk_fail_seen)
	_check("Taktiks: failed Ld = exactly 1 MW, passed = none, Taktik lands either way",
		tk_outcomes_ok)

	# Per-Taktik effect flags (issuer flag cleared between issues — effect test)
	GS.state["meta"]["battle_round"] = 1
	tk_boss["flags"] = {}
	tk_near["flags"] = {}
	rules.set_test_seed(42)
	var tk_gsi = FAM.issue_taktik("U_TK_BOSS", "Get Stuck In", "U_TK_NEAR")
	_check("Get Stuck In grants charge re-rolls",
		tk_gsi.get("success", false) and tk_near["flags"].get("effect_reroll_charge", false)
		and str(tk_near["flags"].get("taktik_active", "")) == "Get Stuck In")
	tk_boss["flags"] = {}
	for m in tk_wagon["models"]:
		m["position"]["x"] -= 480.0
	rules.set_test_seed(42)
	FAM.issue_taktik("U_TK_BOSS", "Get On Wiv It", "U_TK_WAGON")
	_check("Get On Wiv It sets effect_taktik_melee_strength 1",
		int(tk_wagon["flags"].get("effect_taktik_melee_strength", 0)) == 1)
	tk_boss["flags"] = {}
	rules.set_test_seed(42)
	FAM.issue_taktik("U_TK_BOSS", "Sneaky Stalkin'", "U_TK_MEGA")
	_check("Sneaky Stalkin' refuses Meganobz even direct-issued",
		not tk_mega["flags"].get("effect_stealth", false))
	rules.set_test_seed(42)
	FAM.issue_taktik("U_TK_BOSS", "Sneaky Stalkin'", "U_TK_SHOCKED")
	_check("Sneaky Stalkin' still refuses Battle-shocked units",
		not tk_shocked["flags"].get("effect_stealth", false))
	tk_shocked["flags"].erase("battle_shocked")
	rules.set_test_seed(42)
	FAM.issue_taktik("U_TK_BOSS", "Sneaky Stalkin'", "U_TK_SHOCKED")
	_check("Sneaky Stalkin' grants Stealth + Benefit of Cover",
		tk_shocked["flags"].get("effect_stealth", false)
		and tk_shocked["flags"].get("effect_cover", false))
	tk_boss["flags"] = {}
	rules.set_test_seed(42)
	FAM.issue_taktik("U_TK_BOSS", "Shoota Drills", "U_TK_MEGA")
	_check("Shoota Drills grants +1 to ranged Hit rolls",
		tk_mega["flags"].get("effect_plus_one_hit_ranged", false))

	# Get On Wiv It feeds the melee resolver: +1 S crosses the T8 wound band
	var gow_on := 0
	var gow_off := 0
	for s in [11, 42, 77]:
		gow_off += _fight(rules, {}, s)
		gow_on += _fight(rules, {"effect_taktik_melee_strength": 1}, s)
	print("  Get On Wiv It: melee wounds with +1S=%d, without=%d" % [gow_on, gow_off])
	_check("Get On Wiv It +1 S raises melee wounds", gow_on > gow_off)

	# Once-per-round bookkeeping: issuer and receiver both lock out
	GS.state["units"] = {
		"U_TK_BOSS": tk_boss, "U_TK_NEAR": tk_near, "U_TK_FAR": tk_far,
		"U_TK_SHOCKED": tk_shocked, "U_TK_MEGA": tk_mega,
		"U_TK_WAGON": tk_wagon, "U_TK_ENEMY": tk_enemy,
	}
	GS.state["meta"]["battle_round"] = 1
	tk_boss["flags"] = {}
	tk_near["flags"] = {}
	rules.set_test_seed(7)
	FAM.issue_taktik("U_TK_BOSS", "Get Stuck In", "U_TK_NEAR")
	var tk_again = FAM.issue_taktik("U_TK_BOSS", "Shoota Drills", "U_TK_MEGA")
	_check("Taktiks: an issuer only issues once per battle round",
		not tk_again.get("success", false)
		and not "U_TK_BOSS" in FAM.get_taktik_issuers(1))
	var tk_mek = _boyz_unit("U_TK_MEK", 1)
	tk_mek["meta"]["keywords"] = ["CHARACTER", "INFANTRY", "ORKS", "MEK"]
	GS.state["units"]["U_TK_MEK"] = tk_mek
	_check("Taktiks: a Mek is an issuer too", "U_TK_MEK" in FAM.get_taktik_issuers(1))
	_check("Taktiks: a unit only receives one Taktik per battle round",
		not FAM.can_issue_taktik("U_TK_MEK", "Shoota Drills", "U_TK_NEAR").can)
	GS.state["meta"]["battle_round"] = 2
	_check("Taktiks: a new battle round resets issuer and receiver",
		"U_TK_BOSS" in FAM.get_taktik_issuers(1)
		and FAM.can_issue_taktik("U_TK_MEK", "Shoota Drills", "U_TK_NEAR").can)

	# Auto-pick: no target given — nearest eligible friendly ORKS unit chosen
	rules.set_test_seed(7)
	var tk_auto = FAM.issue_taktik("U_TK_MEK", "Shoota Drills", "")
	_check("Taktiks: auto-pick chooses an eligible target",
		tk_auto.get("success", false) and tk_auto.get("target_unit_id", "") != "")

	# Expiry: effects fall off at the start of the issuing player's next
	# Command phase (via _clear_taktik_effects)
	FAM._clear_taktik_effects(1)
	var tk_expired := true
	for uid in GS.state["units"]:
		var uf = GS.state["units"][uid].get("flags", {})
		if uf.has("taktik_active") or uf.has("effect_taktik_melee_strength"):
			tk_expired = false
	_check("Taktiks: _clear_taktik_effects expires every issued Taktik", tk_expired)
	_check("Taktiks: charge re-roll flag gone after expiry",
		not tk_near["flags"].get("effect_reroll_charge", false))
	GS.state["meta"]["battle_round"] = 1

	# ---- Speedwaaagh! — Turbo Boostas eligibility -------------------------------
	print("\n--- Turbo Boostas (Speedwaaagh!) ---")
	_set_detachment(GS, FAM, 1, "Speedwaaagh!")
	var tb_freek = {"owner": 1, "meta": {"keywords": ["ORKS", "SPEED FREEKS", "MOUNTED"]}, "flags": {}, "models": []}
	var tb_trukk = {"owner": 1, "meta": {"keywords": ["ORKS", "VEHICLE", "TRANSPORT", "TRUKK"]}, "flags": {}, "models": []}
	var tb_jet = {"owner": 1, "meta": {"keywords": ["ORKS", "VEHICLE", "SPEED FREEKS", "AIRCRAFT", "FLY"]}, "flags": {}, "models": []}
	var tb_boyz = {"owner": 1, "meta": {"keywords": ["ORKS", "INFANTRY", "BOYZ"]}, "flags": {}, "models": []}
	_check("Turbo Boostas: Speed Freeks can turbo", FAM.unit_can_turbo_boost(tb_freek))
	_check("Turbo Boostas: Trukks can turbo", FAM.unit_can_turbo_boost(tb_trukk))
	_check("Turbo Boostas: Aircraft cannot", not FAM.unit_can_turbo_boost(tb_jet))
	_check("Turbo Boostas: non-Speed-Freek Boyz cannot", not FAM.unit_can_turbo_boost(tb_boyz))
	_set_detachment(GS, FAM, 1, "Kult of Speed")
	_check("Turbo Boostas: Speedwaaagh! detachment only", not FAM.unit_can_turbo_boost(tb_freek))

	# ---- Bully Boyz — Da Boss Is Watchin' (second, scoped Waaagh!) --------------
	print("\n--- Da Boss Is Watchin' (Bully Boyz) ---")
	_set_detachment(GS, FAM, 1, "Bully Boyz")
	var bw_boss = _boyz_unit("U_BW_BOSS", 1)
	bw_boss["meta"]["keywords"] = ["CHARACTER", "INFANTRY", "ORKS", "WARBOSS"]
	bw_boss["meta"]["abilities"] = [{"name": "Waaagh!", "type": "Faction"}]
	var bw_nobz = _boyz_unit("U_BW_NOBZ", 5)
	bw_nobz["meta"]["keywords"] = ["ORKS", "INFANTRY", "NOBZ"]
	bw_nobz["meta"]["abilities"] = [{"name": "Waaagh!", "type": "Faction"}]
	var bw_mega = _boyz_unit("U_BW_MEGA", 3)
	bw_mega["meta"]["keywords"] = ["ORKS", "INFANTRY", "MEGANOBZ"]
	bw_mega["meta"]["abilities"] = [{"name": "Waaagh!", "type": "Faction"}]
	var bw_boyz = _boyz_unit("U_BW_BOYZ", 10)
	bw_boyz["meta"]["abilities"] = [{"name": "Waaagh!", "type": "Faction"}]
	GS.state["units"] = {
		"U_BW_BOSS": bw_boss, "U_BW_NOBZ": bw_nobz,
		"U_BW_MEGA": bw_mega, "U_BW_BOYZ": bw_boyz,
	}
	FAM._waaagh_used = {"1": false, "2": false}
	FAM._waaagh_active = {"1": false, "2": false}
	FAM._boss_watchin_used = {"1": false, "2": false}
	FAM.detect_faction_abilities(1)

	_check("Boss Watchin: unavailable before the first Waaagh! is spent",
		not FAM.is_boss_watchin_waaagh_available(1))
	var bw_first = FAM.activate_waaagh(1)
	_check("Boss Watchin: first (regular) Waaagh! activates army-wide",
		bw_first.get("success", false)
		and bw_boyz["flags"].get("waaagh_active", false)
		and bw_boss["flags"].get("waaagh_active", false))
	_check("Boss Watchin: unavailable while a Waaagh! is active",
		not FAM.is_boss_watchin_waaagh_available(1))
	FAM.deactivate_waaagh(1)
	_check("Boss Watchin: available once the first Waaagh! has expired",
		FAM.is_boss_watchin_waaagh_available(1))
	_set_detachment(GS, FAM, 1, "War Horde")
	_check("Boss Watchin: Bully Boyz detachment only",
		not FAM.is_boss_watchin_waaagh_available(1))
	_set_detachment(GS, FAM, 1, "Bully Boyz")
	for m in bw_boss["models"]:
		m["alive"] = false
	_check("Boss Watchin: needs a living Warboss",
		not FAM.is_boss_watchin_waaagh_available(1))
	for m in bw_boss["models"]:
		m["alive"] = true
	bw_boss["status"] = GameStateData.UnitStatus.IN_RESERVES
	_check("Boss Watchin: a Warboss in Strategic Reserves does not count",
		not FAM.is_boss_watchin_waaagh_available(1))
	bw_boss["status"] = 2

	var bw_second = FAM.activate_boss_watchin_waaagh(1)
	_check("Boss Watchin: second Waaagh! activates", bw_second.get("success", false))
	_check("Boss Watchin: Warboss/Nobz/Meganobz gain the Waaagh! effects",
		bw_boss["flags"].get("waaagh_active", false)
		and bw_nobz["flags"].get("waaagh_active", false)
		and bw_mega["flags"].get("waaagh_active", false)
		and bw_nobz["flags"].get("effect_advance_and_charge", false)
		and int(bw_nobz["flags"].get("effect_invuln", 0)) == 5)
	_check("Boss Watchin: Boyz are OUTSIDE the second Waaagh!'s scope",
		not bw_boyz["flags"].get("waaagh_active", false)
		and not bw_boyz["flags"].has("effect_invuln"))
	_check("Boss Watchin: player-level Waaagh! is active during the second call",
		FAM.is_waaagh_active(1))
	_check("Boss Watchin: only once per battle",
		not FAM.is_boss_watchin_waaagh_available(1)
		and not FAM.activate_boss_watchin_waaagh(1).get("success", false))
	FAM.deactivate_waaagh(1)
	_check("Boss Watchin: expiry clears the scoped effects",
		not bw_nobz["flags"].get("waaagh_active", false)
		and not bw_nobz["flags"].has("effect_invuln"))

	# Save/load round-trip of the second-Waaagh! latch
	var bw_saved = FAM.save_state()
	FAM._boss_watchin_used = {"1": false, "2": false}
	FAM.load_state(bw_saved)
	_check("Boss Watchin: used-latch survives save/load",
		FAM._boss_watchin_used.get("1", false) == true)
	FAM._waaagh_used = {"1": false, "2": false}
	FAM._boss_watchin_used = {"1": false, "2": false}
	_set_detachment(GS, FAM, 1, "War Horde")


# ==========================================================================
# MORE DAKKA! — detachment removed from Codex: Orks (11e); its enhancement
# helpers and the generic effect_improve_leadership consumer are pinned here
# ==========================================================================
func _more_dakka(SM, GS, FAM, rules):
	print("\n===== MORE DAKKA! =====")
	# Retired 2026-10-13: the 10e More Dakka! stratagem checks (loading counts, parsed
	# TARGET conditions, legacy custom:<slug> handlers and their flag consumers).
	# Codex: Orks (11e) replaced those rows; see .llm/ork_codex_11e_retired_tests.md.

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

	# effect_improve_leadership (a generic EffectPrimitives flag) is read by
	# battle-shock tests via CommandPhase._get_effective_leadership (static).
	GS.state["units"] = {"U_LD": _boyz_unit("U_LD", 5)}
	GS.state["units"]["U_LD"]["meta"]["stats"]["leadership"] = 7
	var CommandPhaseScript = load("res://phases/CommandPhase.gd")
	var ld_before = CommandPhaseScript._get_effective_leadership("U_LD")
	GS.state["units"]["U_LD"]["flags"]["effect_improve_leadership"] = 1
	var ld_after = CommandPhaseScript._get_effective_leadership("U_LD")
	_check("effect_improve_leadership lowers the required battle-shock roll", ld_before == 7 and ld_after == 6)


# ==========================================================================
# GREEN TIDE
# ==========================================================================
func _green_tide(SM, GS, FAM, rules):
	print("\n===== GREEN TIDE =====")
	# Retired 2026-10-13: the 10e Green Tide stratagem checks (loading counts, parsed
	# TARGET conditions, legacy custom:<slug> handlers and their flag consumers).
	# Codex: Orks (11e) replaced those rows; see .llm/ork_codex_11e_retired_tests.md.
	# The codex rows are tested in test_ork_codex_fight.gd / test_ork_codex_movement.gd / test_ork_codex_other.gd.

	# counts-as-10 helper
	var small = _boyz_unit("U_SMALL", 5)
	var big = _boyz_unit("U_BIG", 12)
	_check("unit_counts_as_10 false for 5 models", not FAM.unit_counts_as_10(small))
	_check("unit_counts_as_10 true for 12 models", FAM.unit_counts_as_10(big))
	small["flags"]["effect_counts_as_10"] = true
	_check("unit_counts_as_10 true via the effect_counts_as_10 flag (Raucous Warcaller)",
		FAM.unit_counts_as_10(small))

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
