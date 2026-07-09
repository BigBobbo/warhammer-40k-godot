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
