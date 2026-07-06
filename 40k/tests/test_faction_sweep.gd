extends SceneTree

# Faction-wide sweep regression test (Orks + Adeptus Custodes — ALL detachments).
#
# Guards the "implement every sourced Ork/Custodes rule" build-out:
#   1. Every one of the 21 detachments (12 Ork + 9 Custodes) has a
#      DETACHMENT_ABILITIES entry; only the two engine-out-of-scope rules
#      (Dread Mob's Try Dat Button!, Speedwaaagh!'s Turbo Boostas) are
#      display-only.
#   2. Data-driven passive detachment rules apply the right EffectPrimitives
#      flags to the right units (keyword filters, condition flags,
#      keyword grants, proximity pairs) and clear at phase end.
#   3. Designated-target rules (Da Big Hunt Prey / Auric Champions
#      Assemblage), Da Boss Is Watchin' (Bully Boyz), Creeping Dread
#      (Null Maiden Vigil) and Auric Armour OC (Solar Spearhead) behave.
#   4. Lions of the Emperor enhancements: Praesidius flags, Fierce Conqueror
#      computed melee Attacks bonus, Superior Creation end-of-phase return.
#   5. Stratagem coverage: >= 92 of 110 Ork/Custodes detachment stratagems
#      load mechanically implemented; every unimplemented one is on the
#      known intentional-stub list (no silent regressions).
#   6. Generated ability effects (40kdc-compiled) resolve as implemented
#      through the UnitAbilityManager merge layer.
#
# Usage: godot --headless --path . -s tests/test_faction_sweep.gd

var passed := 0
var failed := 0
var _done := false

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

func _norm(s: String) -> String:
	return s.replace("’", "'")

# ----------------------------------------------------------------------------
# Fixtures
# ----------------------------------------------------------------------------

func _mk_unit(id: String, owner: int, kws: Array, pos: Dictionary = {"x": 100.0, "y": 100.0},
		name: String = "", model_count: int = 1) -> Dictionary:
	var models := []
	for i in range(model_count):
		models.append({"id": "m%d" % i, "alive": true, "wounds": 2, "current_wounds": 2,
			"position": {"x": pos.x + i * 30.0, "y": pos.y}, "base_mm": 32, "base_type": "circular"})
	return {
		"id": id, "owner": owner, "status": 2,
		"meta": {"name": name if name != "" else id, "keywords": kws,
			"stats": {"toughness": 4, "save": 4, "wounds": 2, "move": 6, "leadership": 7, "objective_control": 2},
			"abilities": [], "enhancements": []},
		"flags": {},
		"models": models
	}

func _set_detachment(player: int, det: String) -> void:
	var gs = root.get_node("GameState")
	if not gs.state.has("factions"):
		gs.state["factions"] = {}
	gs.state["factions"][str(player)] = {"detachment": det}
	root.get_node("FactionAbilityManager").detect_player_detachment(player)

func _reset_state(units: Dictionary, det1: String = "", det2: String = "") -> void:
	var gs = root.get_node("GameState")
	gs.state["units"] = units
	if not gs.state.has("meta"):
		gs.state["meta"] = {}
	gs.state["meta"]["battle_round"] = 1
	_set_detachment(1, det1)
	_set_detachment(2, det2)

# ----------------------------------------------------------------------------

func _run_tests() -> void:
	if _done:
		return
	_done = true

	_test_detachment_table_coverage()
	_test_green_tide_and_more_dakka()
	_test_kult_of_speed_and_moritoi()
	_test_condition_flag_passives()
	_test_keyword_grant_and_proximity()
	_test_solar_spearhead_oc()
	_test_designated_targets()
	_test_da_boss_watchin()
	_test_creeping_dread()
	_test_lions_enhancements()
	_test_superior_creation()
	_test_stratagem_coverage()
	_test_generated_effects_integrity()

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

# 1 ---------------------------------------------------------------------------

func _test_detachment_table_coverage() -> void:
	print("\n-- Detachment rule table: all 21 Ork/Custodes detachments covered --")
	var fam = root.get_node("FactionAbilityManager")
	var expected := [
		# Orks (12)
		"War Horde", "Freebooter Krew", "Kult of Speed", "Da Big Hunt", "Dread Mob",
		"Bully Boyz", "Green Tide", "Taktikal Brigade", "More Dakka!", "Rollin’ Deff",
		"Blitz Brigade", "Speedwaaagh!",
		# Adeptus Custodes (9)
		"Shield Host", "Lions of the Emperor", "Auric Champions", "Solar Spearhead",
		"Null Maiden Vigil", "Talons of the Emperor", "Might of the Moritoi",
		"Silent Hunters", "Tharanatoi Hammerblow"
	]
	var keys_norm := {}
	for k in fam.DETACHMENT_ABILITIES:
		keys_norm[_norm(k)] = k
	var missing := []
	for det in expected:
		if not keys_norm.has(_norm(det)):
			missing.append(det)
	_check("all 21 detachments have a DETACHMENT_ABILITIES entry", missing.is_empty(), str(missing))

	var allowed_triggers := ["passive", "passive_effects", "proximity_pair",
		"command_phase_start", "activated_unit_waaagh", "opponent_command_battle_shock",
		"per_battle_choice", "per_round_choice", "objective_selection", "unimplemented"]
	var display_only := []
	var bad_triggers := []
	for k in fam.DETACHMENT_ABILITIES:
		var trig = str(fam.DETACHMENT_ABILITIES[k].get("trigger", ""))
		if trig == "unimplemented":
			display_only.append(_norm(k))
		elif trig != "" and not trig in allowed_triggers:
			bad_triggers.append("%s:%s" % [k, trig])
	display_only.sort()
	_check("only Dread Mob + Speedwaaagh! are display-only",
		display_only == ["Dread Mob", "Speedwaaagh!"], str(display_only))

# 2 ---------------------------------------------------------------------------

func _test_green_tide_and_more_dakka() -> void:
	print("\n-- Green Tide (BOYZ 5++ invuln) / More Dakka! (ORKS INFANTRY assault) --")
	var uam = root.get_node("UnitAbilityManager")
	var gs = root.get_node("GameState")

	_reset_state({
		"U_BOYZ": _mk_unit("U_BOYZ", 1, ["ORKS", "INFANTRY", "BOYZ"]),
		"U_TRUKK": _mk_unit("U_TRUKK", 1, ["ORKS", "VEHICLE", "TRANSPORT"])
	}, "Green Tide", "")
	uam.on_phase_start(8)  # shooting
	var boyz_flags = gs.state["units"]["U_BOYZ"]["flags"]
	var trukk_flags = gs.state["units"]["U_TRUKK"]["flags"]
	_check("Green Tide: BOYZ get effect_invuln 5", int(boyz_flags.get("effect_invuln", 0)) == 5, str(boyz_flags))
	_check("Green Tide: invuln source recorded", str(boyz_flags.get("effect_invuln_source", "")) == "Mob Mentality")
	_check("Green Tide: non-BOYZ unit unaffected", int(trukk_flags.get("effect_invuln", 0)) == 0, str(trukk_flags))
	uam.on_phase_end(8)
	_check("Green Tide: invuln cleared at phase end",
		int(gs.state["units"]["U_BOYZ"]["flags"].get("effect_invuln", 0)) == 0,
		str(gs.state["units"]["U_BOYZ"]["flags"]))

	_reset_state({
		"U_LOOTAS": _mk_unit("U_LOOTAS", 1, ["ORKS", "INFANTRY"]),
		"U_TRUKK": _mk_unit("U_TRUKK", 1, ["ORKS", "VEHICLE"])
	}, "More Dakka!", "")
	uam.on_phase_start(8)
	_check("More Dakka!: ORKS INFANTRY get effect_assault_ranged",
		gs.state["units"]["U_LOOTAS"]["flags"].get("effect_assault_ranged", false))
	_check("More Dakka!: ORKS VEHICLE (no INFANTRY) excluded by AND filter",
		not gs.state["units"]["U_TRUKK"]["flags"].get("effect_assault_ranged", false))
	uam.on_phase_end(8)

# 3 ---------------------------------------------------------------------------

func _test_kult_of_speed_and_moritoi() -> void:
	print("\n-- Kult of Speed (SPEED FREEKS eligibility) / Might of the Moritoi (+2\" M, +1 charge) --")
	var uam = root.get_node("UnitAbilityManager")
	var gs = root.get_node("GameState")

	_reset_state({
		"U_BUGGY": _mk_unit("U_BUGGY", 1, ["ORKS", "VEHICLE", "SPEED FREEKS"]),
		"U_GUARD": _mk_unit("U_GUARD", 2, ["ADEPTUS CUSTODES", "INFANTRY"])
	}, "Kult of Speed", "Might of the Moritoi")
	# Movement-phase eligibility path (advance/fall-back decisions happen here)
	uam.on_movement_phase_start()
	var buggy_flags = gs.state["units"]["U_BUGGY"]["flags"]
	_check("Kult of Speed: advance_and_shoot", buggy_flags.get("effect_advance_and_shoot", false), str(buggy_flags))
	_check("Kult of Speed: advance_and_charge", buggy_flags.get("effect_advance_and_charge", false))
	_check("Kult of Speed: fall_back_and_shoot", buggy_flags.get("effect_fall_back_and_shoot", false))
	_check("Kult of Speed: fall_back_and_charge", buggy_flags.get("effect_fall_back_and_charge", false))
	var guard_flags = gs.state["units"]["U_GUARD"]["flags"]
	_check("Moritoi: +2 Move flag on Custodes unit (movement phase)", int(guard_flags.get("effect_plus_move", 0)) == 2, str(guard_flags))
	uam.on_movement_phase_end()
	# Charge-phase pass sets plus_charge for the charge roll
	uam.on_phase_start(9)  # charge
	guard_flags = gs.state["units"]["U_GUARD"]["flags"]
	_check("Moritoi: +1 charge flag in charge phase", int(guard_flags.get("effect_plus_charge", 0)) == 1, str(guard_flags))
	uam.on_phase_end(9)

# 4 ---------------------------------------------------------------------------

func _test_condition_flag_passives() -> void:
	print("\n-- Blitz Brigade (disembarked) / Tharanatoi (from reserves) / Rollin' Deff (wagons) --")
	var uam = root.get_node("UnitAbilityManager")
	var fam = root.get_node("FactionAbilityManager")
	var gs = root.get_node("GameState")

	var u_out = _mk_unit("U_OUT", 1, ["ORKS", "INFANTRY"])
	u_out["flags"]["disembarked_this_turn"] = true
	_reset_state({
		"U_OUT": u_out,
		"U_IN": _mk_unit("U_IN", 1, ["ORKS", "INFANTRY"])
	}, "Blitz Brigade", "")
	uam.on_phase_start(9)  # charge
	_check("Blitz Brigade: disembarked unit gets reroll_charge",
		gs.state["units"]["U_OUT"]["flags"].get("effect_reroll_charge", false))
	_check("Blitz Brigade: disembarked unit gets reroll_advance",
		gs.state["units"]["U_OUT"]["flags"].get("effect_reroll_advance", false))
	_check("Blitz Brigade: unit that stayed embarked-free gets nothing",
		not gs.state["units"]["U_IN"]["flags"].get("effect_reroll_charge", false))
	uam.on_phase_end(9)
	# Live decision-time helper (covers mid-phase disembark before flags re-apply)
	_check("Blitz Brigade: live reroll query (advance)",
		fam.unit_benefits_from_detachment_reroll(gs.state["units"]["U_OUT"], "reroll_advance"))
	_check("Blitz Brigade: live reroll query rejects unflagged unit",
		not fam.unit_benefits_from_detachment_reroll(gs.state["units"]["U_IN"], "reroll_advance"))

	var u_dropped = _mk_unit("U_DROPPED", 2, ["ADEPTUS CUSTODES", "TERMINATOR"])
	u_dropped["arrived_from_reserves_turn"] = 2
	var u_walked = _mk_unit("U_WALKED", 2, ["ADEPTUS CUSTODES", "TERMINATOR"])
	_reset_state({"U_DROPPED": u_dropped, "U_WALKED": u_walked}, "", "Tharanatoi Hammerblow")
	gs.state["meta"]["battle_round"] = 2
	uam.on_phase_start(9)
	_check("Tharanatoi: unit that arrived from reserves this round gets reroll_charge",
		gs.state["units"]["U_DROPPED"]["flags"].get("effect_reroll_charge", false))
	_check("Tharanatoi: unit deployed normally gets nothing",
		not gs.state["units"]["U_WALKED"]["flags"].get("effect_reroll_charge", false))
	uam.on_phase_end(9)

	_reset_state({
		"U_WAGON": _mk_unit("U_WAGON", 1, ["ORKS", "VEHICLE", "BATTLEWAGON"]),
		"U_BOYZ": _mk_unit("U_BOYZ", 1, ["ORKS", "INFANTRY", "BOYZ"])
	}, "Rollin’ Deff", "")
	uam.on_phase_start(9)
	_check("Rollin' Deff: BATTLEWAGON gets reroll_charge",
		gs.state["units"]["U_WAGON"]["flags"].get("effect_reroll_charge", false))
	_check("Rollin' Deff: non-wagon unit gets nothing",
		not gs.state["units"]["U_BOYZ"]["flags"].get("effect_reroll_charge", false))
	uam.on_phase_end(9)

# 5 ---------------------------------------------------------------------------

func _test_keyword_grant_and_proximity() -> void:
	print("\n-- Taktikal Brigade (Stormboyz gain BATTLELINE) / Talons of the Emperor (pair buff) --")
	var uam = root.get_node("UnitAbilityManager")
	var gs = root.get_node("GameState")

	_reset_state({
		"U_STORM": _mk_unit("U_STORM", 1, ["ORKS", "INFANTRY", "STORMBOYZ"], {"x": 100.0, "y": 100.0}, "Stormboyz")
	}, "Taktikal Brigade", "")
	uam.on_phase_start(8)
	var kws: Array = gs.state["units"]["U_STORM"]["meta"]["keywords"]
	_check("Taktikal Brigade: Stormboyz gained BATTLELINE", "BATTLELINE" in kws, str(kws))
	uam.on_phase_end(8)
	uam.on_phase_start(10)
	var battleline_count := 0
	for kw in gs.state["units"]["U_STORM"]["meta"]["keywords"]:
		if kw == "BATTLELINE":
			battleline_count += 1
	_check("Taktikal Brigade: keyword grant is idempotent", battleline_count == 1)
	uam.on_phase_end(10)

	# Talons: 100px = 2.5" apart (40 px/inch) → within 6"
	_reset_state({
		"U_CUST": _mk_unit("U_CUST", 2, ["ADEPTUS CUSTODES", "INFANTRY"], {"x": 100.0, "y": 100.0}),
		"U_SIST": _mk_unit("U_SIST", 2, ["ANATHEMA PSYKANA", "INFANTRY"], {"x": 200.0, "y": 100.0})
	}, "", "Talons of the Emperor")
	uam.on_phase_start(8)
	var cust_flags = gs.state["units"]["U_CUST"]["flags"]
	var sist_flags = gs.state["units"]["U_SIST"]["flags"]
	_check("Talons: Custodes unit near Sisters gets FNP 5", int(cust_flags.get("effect_fnp", 0)) == 5, str(cust_flags))
	_check("Talons: Custodes unit near Sisters gets +1 hit", cust_flags.get("effect_plus_one_hit", false))
	_check("Talons: Sisters unit near Custodes gets FNP 5", int(sist_flags.get("effect_fnp", 0)) == 5, str(sist_flags))
	uam.on_phase_end(8)
	# Out of range → no buff
	gs.state["units"]["U_SIST"]["models"][0]["position"] = {"x": 3000.0, "y": 3000.0}
	uam.on_phase_start(8)
	_check("Talons: no buff when pair is beyond 6\"",
		int(gs.state["units"]["U_CUST"]["flags"].get("effect_fnp", 0)) == 0,
		str(gs.state["units"]["U_CUST"]["flags"]))
	uam.on_phase_end(8)

# 6 ---------------------------------------------------------------------------

func _test_solar_spearhead_oc() -> void:
	print("\n-- Solar Spearhead: Auric Armour +2 OC (live, conditional) --")
	var fam = root.get_node("FactionAbilityManager")
	var gs = root.get_node("GameState")

	_reset_state({
		"U_FULL": _mk_unit("U_FULL", 2, ["ADEPTUS CUSTODES", "VEHICLE"], {"x": 100.0, "y": 100.0}, "", 2),
		"U_HURT": _mk_unit("U_HURT", 2, ["ADEPTUS CUSTODES", "VEHICLE"], {"x": 300.0, "y": 100.0}, "", 2),
		"U_PLANE": _mk_unit("U_PLANE", 2, ["ADEPTUS CUSTODES", "AIRCRAFT"], {"x": 500.0, "y": 100.0})
	}, "", "Solar Spearhead")
	gs.state["units"]["U_HURT"]["models"][1]["alive"] = false
	_check("Auric Armour: +2 OC at Starting Strength",
		fam.get_detachment_oc_bonus(gs.state["units"]["U_FULL"]) == 2)
	_check("Auric Armour: no bonus below Starting Strength",
		fam.get_detachment_oc_bonus(gs.state["units"]["U_HURT"]) == 0)
	_check("Auric Armour: AIRCRAFT excluded",
		fam.get_detachment_oc_bonus(gs.state["units"]["U_PLANE"]) == 0)
	gs.state["units"]["U_FULL"]["flags"]["battle_shocked"] = true
	_check("Auric Armour: battle-shocked unit gets no bonus",
		fam.get_detachment_oc_bonus(gs.state["units"]["U_FULL"]) == 0)

# 7 ---------------------------------------------------------------------------

func _test_designated_targets() -> void:
	print("\n-- Da Big Hunt (Prey) / Auric Champions (Assemblage of Might) --")
	var fam = root.get_node("FactionAbilityManager")
	var gs = root.get_node("GameState")

	_reset_state({
		"U_SNAGGA": _mk_unit("U_SNAGGA", 1, ["ORKS", "INFANTRY", "BEAST SNAGGA"]),
		"U_BOYZ": _mk_unit("U_BOYZ", 1, ["ORKS", "INFANTRY", "BOYZ"]),
		"U_PREY1": _mk_unit("U_PREY1", 2, ["ADEPTUS CUSTODES", "INFANTRY"], {"x": 500.0, "y": 100.0}),
		"U_PREY2": _mk_unit("U_PREY2", 2, ["ADEPTUS CUSTODES", "VEHICLE"], {"x": 700.0, "y": 100.0})
	}, "Da Big Hunt", "Auric Champions")

	var res = fam.set_detachment_target(1, "prey", "U_PREY1")
	_check("Prey: designation succeeds", res.get("success", false), str(res))
	_check("Prey: flag set on enemy unit", gs.state["units"]["U_PREY1"]["flags"].get("prey_target", false))
	_check("Prey: BEAST SNAGGA attacker gets +1 AP vs Prey",
		fam.attacker_benefits_from_prey_ap(gs.state["units"]["U_SNAGGA"], gs.state["units"]["U_PREY1"]) == 1)
	_check("Prey: non-SNAGGA attacker gets nothing",
		fam.attacker_benefits_from_prey_ap(gs.state["units"]["U_BOYZ"], gs.state["units"]["U_PREY1"]) == 0)
	_check("Prey: no bonus vs non-designated unit",
		fam.attacker_benefits_from_prey_ap(gs.state["units"]["U_SNAGGA"], gs.state["units"]["U_PREY2"]) == 0)
	_check("Prey: BEAST SNAGGA charge re-roll active once Prey designated",
		fam.unit_benefits_from_prey_charge_reroll(gs.state["units"]["U_SNAGGA"]))
	_check("Prey: BOYZ get no charge re-roll",
		not fam.unit_benefits_from_prey_charge_reroll(gs.state["units"]["U_BOYZ"]))
	fam.set_detachment_target(1, "prey", "U_PREY2")
	_check("Prey: re-designation clears the old flag",
		not gs.state["units"]["U_PREY1"]["flags"].get("prey_target", false))

	# Assemblage of Might — player 2 designates a player-1 unit
	var res2 = fam.set_detachment_target(2, "assemblage", "U_SNAGGA")
	_check("Assemblage: designation succeeds", res2.get("success", false), str(res2))
	var cust_char = _mk_unit("U_CHAR", 2, ["ADEPTUS CUSTODES", "CHARACTER"])
	var cust_squad = _mk_unit("U_SQUAD", 2, ["ADEPTUS CUSTODES", "INFANTRY"])
	_check("Assemblage: CUSTODES CHARACTER gets +1 wound vs designated unit",
		fam.attacker_benefits_from_assemblage(cust_char, gs.state["units"]["U_SNAGGA"]))
	_check("Assemblage: non-CHARACTER unit gets nothing",
		not fam.attacker_benefits_from_assemblage(cust_squad, gs.state["units"]["U_SNAGGA"]))

# 8 ---------------------------------------------------------------------------

func _test_da_boss_watchin() -> void:
	print("\n-- Bully Boyz: Da Boss Is Watchin' (per-unit Waaagh!, rest of battle) --")
	var fam = root.get_node("FactionAbilityManager")
	var gs = root.get_node("GameState")

	_reset_state({
		"U_MEGA": _mk_unit("U_MEGA", 1, ["ORKS", "INFANTRY", "MEGANOBZ"]),
		"U_GRETCH": _mk_unit("U_GRETCH", 1, ["ORKS", "INFANTRY", "GRETCHIN"])
	}, "Bully Boyz", "")
	fam._da_boss_watchin_used.clear()

	_check("available for Bully Boyz player", fam.is_da_boss_watchin_available(1))
	var eligible = fam.get_da_boss_watchin_eligible_units(1)
	var ids := []
	for e in eligible:
		ids.append(e.unit_id)
	_check("MEGANOBZ eligible, GRETCHIN not", "U_MEGA" in ids and not "U_GRETCH" in ids, str(ids))

	var res = fam.activate_da_boss_watchin(1, "U_MEGA")
	_check("activation succeeds", res.get("success", false), str(res))
	var flags = gs.state["units"]["U_MEGA"]["flags"]
	_check("waaagh_active set", flags.get("waaagh_active", false))
	_check("5+ invuln set", int(flags.get("effect_invuln", 0)) == 5)
	_check("advance+charge set", flags.get("effect_advance_and_charge", false))
	_check("permanent marker set", flags.get("da_boss_watchin_permanent", false))
	_check("RulesEngine sees Waaagh! active for the unit",
		fam.is_waaagh_active_for_unit(gs.state["units"]["U_MEGA"]))

	# The army-wide Waaagh! ending must NOT strip the per-unit Waaagh!
	fam._clear_waaagh_effects(1)
	flags = gs.state["units"]["U_MEGA"]["flags"]
	_check("survives army Waaagh! clear (waaagh_active)", flags.get("waaagh_active", false))
	_check("survives army Waaagh! clear (invuln)", int(flags.get("effect_invuln", 0)) == 5, str(flags))

	var res2 = fam.activate_da_boss_watchin(1, "U_MEGA")
	_check("once per battle enforced", not res2.get("success", true))

# 9 ---------------------------------------------------------------------------

func _test_creeping_dread() -> void:
	print("\n-- Null Maiden Vigil: Creeping Dread forces battle-shock tests --")
	var fam = root.get_node("FactionAbilityManager")
	var gs = root.get_node("GameState")

	# 160px = 4" (within 6") — Sisters belong to player 2, active player is 1
	var psyker = _mk_unit("U_PSYKER", 1, ["PSYKER", "INFANTRY"], {"x": 100.0, "y": 100.0})
	var weakened = _mk_unit("U_WEAK", 1, ["INFANTRY"], {"x": 140.0, "y": 100.0}, "", 2)
	var healthy = _mk_unit("U_HEALTHY", 1, ["INFANTRY"], {"x": 180.0, "y": 100.0})
	var far_psyker = _mk_unit("U_FARPSY", 1, ["PSYKER"], {"x": 4000.0, "y": 4000.0})
	weakened["models"][1]["alive"] = false
	_reset_state({
		"U_PSYKER": psyker, "U_WEAK": weakened, "U_HEALTHY": healthy, "U_FARPSY": far_psyker,
		"U_SIST": _mk_unit("U_SIST", 2, ["ANATHEMA PSYKANA", "INFANTRY"], {"x": 260.0, "y": 100.0})
	}, "", "Null Maiden Vigil")

	var forced = fam.get_creeping_dread_forced_units(1)
	_check("PSYKER within 6\" is forced", "U_PSYKER" in forced, str(forced))
	_check("below-starting-strength unit within 6\" is forced", "U_WEAK" in forced, str(forced))
	_check("full-strength non-psyker not forced", not "U_HEALTHY" in forced)
	_check("PSYKER beyond 6\" not forced", not "U_FARPSY" in forced)
	# No effect when the opponent runs a different detachment
	_set_detachment(2, "Shield Host")
	_check("no forced tests without Null Maiden Vigil", fam.get_creeping_dread_forced_units(1).is_empty())

# 10 --------------------------------------------------------------------------

func _test_lions_enhancements() -> void:
	print("\n-- Lions of the Emperor: Praesidius / Fierce Conqueror --")
	var uam = root.get_node("UnitAbilityManager")
	var gs = root.get_node("GameState")
	var rules = root.get_node("RulesEngine")

	var bearer = _mk_unit("U_BLADE", 2, ["ADEPTUS CUSTODES", "CHARACTER"])
	bearer["meta"]["enhancements"] = ["Praesidius"]
	_reset_state({"U_BLADE": bearer}, "", "Lions of the Emperor")
	uam.on_phase_start(8)
	var flags = gs.state["units"]["U_BLADE"]["flags"]
	_check("Praesidius: Lone Operative flag", flags.get("effect_lone_operative", false), str(flags))
	_check("Praesidius: Stealth flag", flags.get("effect_stealth", false))
	uam.on_phase_end(8)

	# Fierce Conqueror: 12 enemy models within 6" → floor(12/5)*2 = +4 A
	var fc_bearer = _mk_unit("U_CAPT", 2, ["ADEPTUS CUSTODES", "CHARACTER"])
	fc_bearer["meta"]["enhancements"] = ["Fierce Conqueror"]
	# Cluster the horde tightly so all 12 models sit within 6" of the bearer
	var horde = _mk_unit("U_HORDE", 1, ["ORKS", "INFANTRY"], {"x": 140.0, "y": 100.0}, "", 12)
	for i in range(horde["models"].size()):
		horde["models"][i]["position"] = {"x": 140.0 + (i % 4) * 20.0, "y": 100.0 + floor(i / 4.0) * 20.0}
	var board = {"units": {"U_CAPT": fc_bearer, "U_HORDE": horde}}
	_check("Fierce Conqueror: +4 Attacks with 12 enemy models within 6\"",
		rules.get_fierce_conqueror_attack_bonus(fc_bearer, board) == 4,
		str(rules.get_fierce_conqueror_attack_bonus(fc_bearer, board)))
	var few = _mk_unit("U_FEW", 1, ["ORKS", "INFANTRY"], {"x": 140.0, "y": 100.0}, "", 4)
	var board2 = {"units": {"U_CAPT": fc_bearer, "U_FEW": few}}
	_check("Fierce Conqueror: no bonus with only 4 enemy models",
		rules.get_fierce_conqueror_attack_bonus(fc_bearer, board2) == 0)
	var no_enh = _mk_unit("U_PLAIN", 2, ["ADEPTUS CUSTODES", "CHARACTER"])
	_check("Fierce Conqueror: no bonus without the enhancement",
		rules.get_fierce_conqueror_attack_bonus(no_enh, board) == 0)

# 11 --------------------------------------------------------------------------

func _test_superior_creation() -> void:
	print("\n-- Lions of the Emperor: Superior Creation (return on 2+ at phase end) --")
	var uam = root.get_node("UnitAbilityManager")
	var gs = root.get_node("GameState")
	var rules = root.get_node("RulesEngine")

	# Find a seed whose first D6 through make_rng() is >= 2 and reproducible
	var seed_val := 0
	var probe := 0
	for s in range(1, 12):
		rules.set_test_seed(s)
		var a = rules.make_rng().roll_d6(1)[0]
		rules.set_test_seed(s)
		var b = rules.make_rng().roll_d6(1)[0]
		if a == b and a >= 2:
			seed_val = s
			probe = a
			break
	_check("found reproducible seed with roll >= 2", seed_val != 0, "make_rng not seed-stable")

	var bearer = _mk_unit("U_SHIELD", 2, ["ADEPTUS CUSTODES", "CHARACTER", "INFANTRY"])
	bearer["meta"]["enhancements"] = ["Superior Creation"]
	bearer["models"][0]["alive"] = false
	bearer["models"][0]["current_wounds"] = 0
	_reset_state({"U_SHIELD": bearer}, "", "Lions of the Emperor")
	uam._once_per_battle_used.erase("U_SHIELD:Superior Creation")

	rules.set_test_seed(seed_val)
	uam.on_phase_end(8)
	var model = gs.state["units"]["U_SHIELD"]["models"][0]
	_check("bearer returned alive (rolled %d)" % probe, model.get("alive", false), str(model))
	_check("bearer returned at full wounds", int(model.get("current_wounds", 0)) == int(model.get("wounds", -1)))
	_check("once-per-battle usage recorded", uam._once_per_battle_used.get("U_SHIELD:Superior Creation", false))

	# Second destruction: no second chance
	gs.state["units"]["U_SHIELD"]["models"][0]["alive"] = false
	rules.set_test_seed(seed_val)
	uam.on_phase_end(8)
	_check("no return on second destruction",
		not gs.state["units"]["U_SHIELD"]["models"][0].get("alive", false))
	rules.set_test_seed(0)

# 12 --------------------------------------------------------------------------

func _test_stratagem_coverage() -> void:
	print("\n-- Stratagem coverage: every non-stub Ork/Custodes stratagem implemented --")
	var sm = root.get_node("StratagemManager")
	var loader = FactionStratagemLoaderData.new()
	loader.load_faction_codes()

	# Intentional stubs: no rules source (FULL THROTTLE, ARMED TO DA TEEF,
	# CUT' EM DOWN) or out-of-scope engine subsystems (reactive/out-of-phase
	# move windows, weapon-stat rewrites, enemy-Ld auras).
	var allowed_stubs := [
		"FULL THROTTLE", "MORE GITZ OVER 'ERE!", "WHERE D'YA FINK YOU'RE GOING?",
		"ARMED TO DA TEEF", "CUT' EM DOWN", "ON TO DA NEXT", "CALL DAT DAKKA?",
		"BRUTAL BROADSIDE", "IMPENDING CRUNCH", "DEVASTATING DRIFT",
		"YOOZ IN TROUBLE NOW", "TALONED PINCER", "SHIELD OF HONOUR",
		"UNSTOPPABLE ADVANCE", "PRIORITISED ERADICATION",
		"UMBRAL PROSECUTION", "SYNCHRONISED INFERNO", "ELECTROEXORCIST SATURATION"
	]
	var dets = {
		"Orks": ["War Horde", "Freebooter Krew", "Kult of Speed", "Da Big Hunt", "Dread Mob",
			"Bully Boyz", "Green Tide", "Taktikal Brigade", "More Dakka!", "Rollin’ Deff", "Blitz Brigade"],
		"Adeptus Custodes": ["Shield Host", "Lions of the Emperor", "Auric Champions", "Solar Spearhead",
			"Null Maiden Vigil", "Talons of the Emperor", "Might of the Moritoi", "Silent Hunters", "Tharanatoi Hammerblow"],
	}
	var total := 0
	var implemented := 0
	var unexpected_stubs := []
	for fac in dets:
		for det in dets[fac]:
			for s in loader.load_faction_stratagems(fac, det):
				total += 1
				var nm = _norm(str(s.get("name", ""))).to_upper()
				if s.get("implemented", false) or nm in sm.CUSTOM_IMPLEMENTED_STRATAGEMS:
					implemented += 1
				elif nm in allowed_stubs:
					pass
				else:
					unexpected_stubs.append(s.get("name", ""))
	_check("all 110 Ork/Custodes detachment stratagems load", total == 110, str(total))
	_check("at least 92 mechanically implemented", implemented >= 92, "%d/%d" % [implemented, total])
	_check("every unimplemented stratagem is a known intentional stub",
		unexpected_stubs.is_empty(), str(unexpected_stubs))

# 13 --------------------------------------------------------------------------

func _test_generated_effects_integrity() -> void:
	print("\n-- Generated ability effects (40kdc-compiled) resolve as implemented --")
	var uam = root.get_node("UnitAbilityManager")

	var f = FileAccess.open("res://data/generated_ability_effects.json", FileAccess.READ)
	_check("generated_ability_effects.json readable", f != null)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	_check("generated file parses to a Dictionary", data is Dictionary)
	if not data is Dictionary:
		return

	var gen_implemented := 0
	var broken := []
	for name in data:
		if data[name].get("implemented", false):
			gen_implemented += 1
			# Merge layer must resolve it as implemented (hand-written may shadow)
			if not uam.get_effect_def(name, {}).get("implemented", false):
				broken.append(name)
	_check("at least 17 generated entries implemented", gen_implemented >= 17, str(gen_implemented))
	_check("all implemented generated entries resolve through the merge layer",
		broken.is_empty(), str(broken))

	# Sourced entries that MUST stay implemented (regression pins)
	var must_be_implemented := [
		"Ferocious Rage", "Know-wotz", "Deft Parry", "Resolute Will",
		"Tactical Perception", "Shoutin' Pole (Aura)", "Runnin' Boots",
		"Praesidius", "Superior Creation", "Fierce Conqueror",
		"Blastajet Force Field", "Devoted to Destruction"
	]
	var missing := []
	for name in must_be_implemented:
		if not uam.get_effect_def(name, {}).get("implemented", false):
			missing.append(name)
	_check("all sourced ability/enhancement entries implemented", missing.is_empty(), str(missing))
