extends SceneTree

# Codex: Orks (11e) — the 15 detachment rules (WP-O34, plan O4). Against the
# real fixture tests/saves/ork11e_o34_active.w40ksave (P1 Orks, codex-era army
# file + a Weirdboy, ACTIVE vs P2 Custodes), detachment switched per section.
# One section per rule: trigger / condition edge cases, the effect through the
# real RulesEngine resolver paths (A/B with identical seeds), expiry, the AI
# path, BATTLELINE grants.
#   A. detection + BATTLELINE grants (Kult of Speed / Taktikal / Runt Swarm)
#   B. War Horde — Get Stuck In            C. Bully Boyz — Displays of Savagery
#   D. Green Tide — Mob-handed Brutality   E. Da Big Hunt — Da Hunt is On
#   F. Kult of Speed — Adrenaline Junkies  G. Taktikal — Suspiciously Well Organised
#   H. Blitz Brigade — Unstoppable Momentum
#   I. Wreckas — Wreckin' and Lootin'      J. Runt Swarm — Sneaky Little Gitz
#   K. Shoota Boyz — Dakka! Dakka! Dakka!  L. Flyboyz — Skyborne Loons
#   M. Madcap Meks — Unpredictable Genius  N. Dread Mob — Try Dat Button!
#   O. Brute Bosses — 'Ard as Nails        P. Wurrband — Powers of da Waaagh!
#   Q. rule offers through the window framework (reopen, AI never stalls)
#
# Usage: godot --headless --path 40k --script tests/test_ork_detachments_11e.gd

const FIXTURE := "ork11e_o34_active"
const PHASE_COMMAND := 6
const PHASE_MOVEMENT := 7
const PHASE_SHOOTING := 8
const PHASE_CHARGE := 9
const PHASE_FIGHT := 10
const PX := 40.0
const Det = preload("res://scripts/codex/orks/OrkDetachments11e.gd")
const ArmyRules = preload("res://scripts/codex/orks/OrkArmyRules11e.gd")

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var RE = null
var FAM = null
var _base_positions: Dictionary = {}


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _initialize() -> void:
	await create_timer(0.3).timeout
	await _run()
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func _stage_fixture() -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + FIXTURE + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + FIXTURE + ext))
	return slm.load_game(FIXTURE)


func _reload(det: String) -> void:
	_stage_fixture()
	GS.set_edition(11)
	FAM.load_state({})
	_set_detachment(1, det)


func _set_detachment(player: int, det: String) -> void:
	GS.state.factions[str(player)]["detachment"] = det
	SM.load_faction_stratagems_for_player(player)
	FAM.detect_player_detachment(player)


func _u(uid: String) -> Dictionary:
	return GS.state.units.get(uid, {})


func _flags(uid: String) -> Dictionary:
	return _u(uid).get("flags", {})


func _kw(uid: String) -> Array:
	return _u(uid).get("meta", {}).get("keywords", [])


func _set_turn(round_no: int, active: int, phase: int) -> void:
	GS.state.meta["battle_round"] = round_no
	GS.state.meta["active_player"] = active
	GS.state.meta["phase"] = phase


func _place_unit(uid: String, x_in: float, y_in: float, spacing: float = 1.6) -> void:
	var models: Array = _u(uid).get("models", [])
	var n := models.size()
	for i in range(n):
		var p = Vector2((x_in + (float(i) - float(n - 1) / 2.0) * spacing) * PX, y_in * PX)
		models[i]["position"] = {"x": p.x, "y": p.y}


func _assign(board: Dictionary, uid: String, wid: String, tid: String) -> Dictionary:
	var model_ids: Array = []
	var w = RE.get_unit_weapons(uid, board)
	for mid in w:
		if wid in w[mid]:
			model_ids.append(str(mid))
	return {"weapon_id": wid, "target_unit_id": tid, "model_ids": model_ids}


func _ranged_weapon(uid: String, name_part: String = "") -> String:
	var w = RE.get_unit_weapons(uid, GS.state)
	for mid in w:
		for wid in w[mid]:
			if name_part == "" or name_part.to_lower() in str(wid).to_lower():
				return str(wid)
	return ""


func _melee_weapon(uid: String) -> String:
	var w = RE.get_unit_melee_weapons(uid, GS.state)
	for mid in w:
		for wname in w[mid]:
			return str(wname)
	return ""


func _auto(board: Dictionary, uid: String, assignment: Dictionary, seed_val: int) -> Dictionary:
	return RE.resolve_shoot({"type": "SHOOT", "actor_unit_id": uid, "payload": {"assignments": [assignment]}}, board, RE.RNGService.new(seed_val))


func _interactive(board: Dictionary, uid: String, assignment: Dictionary, seed_val: int) -> Dictionary:
	return RE.resolve_shoot_until_wounds({"type": "SHOOT", "actor_unit_id": uid, "payload": {"assignments": [assignment]}}, board, RE.RNGService.new(seed_val))


func _melee(board: Dictionary, uid: String, tid: String, weapon: String, seed_val: int) -> Dictionary:
	RE.set_test_seed(seed_val)
	return RE.resolve_melee_attacks({"type": "FIGHT", "actor_unit_id": uid,
		"payload": {"assignments": [{"attacker": uid, "target": tid, "weapon": weapon}]}}, board, RE.RNGService.new())


func _block(res: Dictionary, ctx_name: String) -> Dictionary:
	for d in res.get("dice", []):
		if str(d.get("context", "")) == ctx_name:
			return d
	return {}


func _save_ap(res: Dictionary) -> int:
	for sd in res.get("save_data_list", []):
		return int(sd.get("ap", 99))
	for d in res.get("dice", []):
		if str(d.get("context", "")) in ["save", "save_roll_melee"] and d.has("ap"):
			return int(d.ap)
	return 99


## Same seed through two boards until both resolutions reach a save (bounded).
func _ap_pair(fn: Callable, board_a: Dictionary, board_b: Dictionary, first_seed: int) -> Array:
	for s in range(first_seed, first_seed + 40):
		var a := _save_ap(fn.call(board_a.duplicate(true), s))
		var b := _save_ap(fn.call(board_b.duplicate(true), s))
		if a != 99 and b != 99:
			return [a, b, s]
	return [99, 99, -1]


func _ledger_has(block: Dictionary, needle: String) -> bool:
	for e in block.get("modifier_ledger", []):
		if needle in str(e):
			return true
	return false


# ---------------------------------------------------------------------------
func _run() -> void:
	SM = root.get_node("StratagemManager")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	FAM = root.get_node("FactionAbilityManager")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	GS.set_edition(11)
	root.get_node("SettingsService").set("auto_allocate_wounds", true)

	print("\n=== test_ork_detachments_11e ===\n")
	_check("fixture %s loads" % FIXTURE, _stage_fixture())
	GS.set_edition(11)

	_section_detection_battleline()
	_section_war_horde()
	_section_bully_boyz()
	_section_green_tide()
	_section_da_big_hunt()
	_section_kult_of_speed()
	_section_taktikal()
	_section_blitz_brigade()
	_section_wreckas()
	_section_runt_swarm()
	_section_shoota_boyz()
	_section_flyboyz()
	_section_madcap_meks()
	_section_dread_mob()
	_section_brute_bosses()
	_section_wurrband()
	_section_rule_offer_framework()


# ---------------------------------------------------------------------------
func _section_detection_battleline() -> void:
	print("\n-- A. detection + BATTLELINE grants --")
	_reload("Wreckas")
	_check("detachment key folds apostrophes / case", Det.det_key("Wreckin’ and Lootin’") == "wreckin' and lootin'")
	_check("detachment_of(1) = wreckas", Det.detachment_of(1) == Det.WRECKAS)
	GS.set_edition(10)
	_check("10e: no 11e detachment", Det.detachment_of(1) == "")
	GS.set_edition(11)
	for det in [["Kult of Speed", "U_WARBIKERS_A"], ["Taktikal Brigade", "U_STORMBOYZ_A"], ["Runt Swarm", "U_GRETCHIN_C"]]:
		_reload(det[0])
		_check("%s: %s has no BATTLELINE before the grant" % [det[0], det[1]], not "BATTLELINE" in _kw(det[1]))
		var d: Array = Det.apply_keyword_grants(1)
		_check("%s: %s gains BATTLELINE" % [det[0], det[1]], "BATTLELINE" in _kw(det[1]) and not d.is_empty())
		_check("%s: grant is idempotent" % det[0], Det.apply_keyword_grants(1).is_empty())
	_check("Runt Swarm: both Gretchin units", "BATTLELINE" in _kw("U_GRETCHIN_D"))
	_reload("Runt Swarm")
	FAM.on_command_phase_start(1)
	_check("the grant is (re)applied at the Command phase start", "BATTLELINE" in _kw("U_GRETCHIN_C"))
	_reload("Dread Mob")
	FAM.on_command_phase_start(1)
	_check("Dread Mob (11e) grants nothing — the 10e Gretchin grant is gone", not "BATTLELINE" in _kw("U_GRETCHIN_C"))
	_reload("War Horde")
	FAM.on_command_phase_start(1)
	_check("War Horde: no BATTLELINE grant", not "BATTLELINE" in _kw("U_WARBIKERS_A") and not "BATTLELINE" in _kw("U_STORMBOYZ_A"))
	# What the game reads BATTLELINE for: stratagem targeting keywords.
	_reload("Kult of Speed")
	Det.apply_keyword_grants(1)
	_check("a granted unit reads as BATTLELINE to keyword checks (RulesEngine.unit_has_keyword)", RE.unit_has_keyword(_u("U_WARBIKERS_A"), "BATTLELINE"))


func _section_war_horde() -> void:
	print("\n-- B. War Horde — Get Stuck In --")
	_reload("War Horde")
	var sh: Dictionary = Det.melee_sustained_hits(_u("U_BOYZ_B"))
	_check("ORKS melee: [SUSTAINED HITS 1]", int(sh.value) == 1 and "Get Stuck In" in str(sh.source))
	_check("the attached Warboss too", int(Det.melee_sustained_hits(_u("U_WARBOSS_A")).value) == 1)
	_check("Custodes: none", int(Det.melee_sustained_hits(_u("U_CUSTODIAN_GUARD_A")).value) == 0)
	var w := _melee_weapon("U_BOYZ_B")
	var a := _block(_melee(GS.state.duplicate(true), "U_BOYZ_B", "U_CUSTODIAN_GUARD_A", w, 41), "hit_roll_melee")
	_set_detachment(1, "Kult of Speed")
	var b := _block(_melee(GS.state.duplicate(true), "U_BOYZ_B", "U_CUSTODIAN_GUARD_A", w, 41), "hit_roll_melee")
	_check("A/B melee (%s, seed 41): War Horde rolls [SUSTAINED HITS 1], Kult of Speed does not" % w,
		int(a.get("sustained_hits_value", 0)) == 1 and int(b.get("sustained_hits_value", 0)) == 0, "%s / %s" % [str(a.get("sustained_hits_value")), str(b.get("sustained_hits_value"))])
	_check("same hit dice either way", a.get("rolls_raw", []) == b.get("rolls_raw", []))
	_check("no 10e get_stuck_in flag is written at 11e", not _flags("U_BOYZ_B").get("get_stuck_in", false))
	GS.set_edition(10)
	_check("10e: the module adds nothing", int(Det.melee_sustained_hits(_u("U_BOYZ_B")).value) == 0)
	GS.set_edition(11)


func _section_bully_boyz() -> void:
	print("\n-- C. Bully Boyz — Displays of Savagery --")
	_reload("Bully Boyz")
	_check("Nobz: [SUSTAINED HITS 1]", int(Det.melee_sustained_hits(_u("U_NOBZ_A")).value) == 1)
	_check("Meganobz: [SUSTAINED HITS 1]", int(Det.melee_sustained_hits(_u("U_MEGANOBZ_A")).value) == 1)
	_check("Boyz: no (not a Nobz unit)", int(Det.melee_sustained_hits(_u("U_BOYZ_B")).value) == 0)
	var w := _melee_weapon("U_NOBZ_A")
	var a := _block(_melee(GS.state.duplicate(true), "U_NOBZ_A", "U_CUSTODIAN_GUARD_B", w, 7), "hit_roll_melee")
	_check("melee resolution carries it (Nobz %s)" % w, int(a.get("sustained_hits_value", 0)) == 1)
	FAM.detect_faction_abilities(1)
	FAM.activate_waaagh(1)
	FAM.deactivate_waaagh(1)
	_check("the 10e second Waaagh! (Da Boss Is Watchin') is gone at 11e", not FAM.is_boss_watchin_waaagh_available(1))


func _section_green_tide() -> void:
	print("\n-- D. Green Tide — Mob-handed Brutality --")
	_reload("Green Tide")
	_check("Boyz: [SUSTAINED HITS 1]", int(Det.melee_sustained_hits(_u("U_BOYZ_B")).value) == 1 and "Mob-handed" in str(Det.melee_sustained_hits(_u("U_BOYZ_B")).source))
	_check("Nobz: no SUSTAINED HITS (not Boyz)", int(Det.melee_sustained_hits(_u("U_NOBZ_A")).value) == 0)
	_check("no [LETHAL HITS] without a charge", Det.melee_lethal_hits_source(_u("U_NOBZ_A"), _u("U_CUSTODIAN_GUARD_B")) == "")
	_flags("U_NOBZ_A")["charged_this_turn"] = true
	_check("charged ORKS INFANTRY: [LETHAL HITS] vs infantry", Det.melee_lethal_hits_source(_u("U_NOBZ_A"), _u("U_CUSTODIAN_GUARD_B")) != "")
	_check("... but not vs a VEHICLE", Det.melee_lethal_hits_source(_u("U_NOBZ_A"), _u("U_DEFF_DREAD_A")) == "")
	_flags("U_DEFF_DREAD_A")["charged_this_turn"] = true
	_check("a charged VEHICLE (not INFANTRY): none", Det.melee_lethal_hits_source(_u("U_DEFF_DREAD_A"), _u("U_PROSECUTORS_A")) == "")
	var w := _melee_weapon("U_NOBZ_A")
	var a := _block(_melee(GS.state.duplicate(true), "U_NOBZ_A", "U_CUSTODIAN_GUARD_B", w, 9), "hit_roll_melee")
	_flags("U_NOBZ_A").erase("charged_this_turn")
	var b := _block(_melee(GS.state.duplicate(true), "U_NOBZ_A", "U_CUSTODIAN_GUARD_B", w, 9), "hit_roll_melee")
	_check("A/B melee (seed 9): charged Nobz have [LETHAL HITS], uncharged do not", bool(a.get("lethal_hits_weapon", false)) and not bool(b.get("lethal_hits_weapon", false)))
	_check("the 10e Mob Mentality invulnerable save is not applied at 11e", (func():
		FAM.on_command_phase_start(1)
		return str(_flags("U_BOYZ_B").get("effect_invuln_source", "")) != "Mob Mentality").call())


func _section_da_big_hunt() -> void:
	print("\n-- E. Da Big Hunt — Da Hunt is On --")
	_reload("Da Big Hunt")
	_check("own VEHICLE is never a target", Det.attack_ap_bonus(_u("U_BEAST_SNAGGA_BOYZ_A"), _u("U_DEFF_DREAD_A")) == 0)
	_check("Beast Snagga vs INFANTRY: none", Det.attack_ap_bonus(_u("U_BEAST_SNAGGA_BOYZ_A"), _u("U_ALLARUS_CUSTODIANS_A")) == 0)
	# The fixture's Custodes have no MONSTER/VEHICLE: the engaged Allarus is
	# given the VEHICLE keyword in GameState for this section.
	_u("U_ALLARUS_CUSTODIANS_A").meta.keywords.append("VEHICLE")
	_check("Beast Snagga vs an enemy VEHICLE: +1 AP", Det.attack_ap_bonus(_u("U_BEAST_SNAGGA_BOYZ_A"), _u("U_ALLARUS_CUSTODIANS_A")) == 1)
	_check("Boyz (not Beast Snagga) vs a VEHICLE: none", Det.attack_ap_bonus(_u("U_BOYZ_B"), _u("U_ALLARUS_CUSTODIANS_A")) == 0)
	_check("routed through RulesEngine.get_prey_ap_bonus at 11e", RE.get_prey_ap_bonus(_u("U_BEAST_SNAGGA_BOYZ_A"), _u("U_ALLARUS_CUSTODIANS_A")) == 1)
	var w := _melee_weapon("U_BEAST_SNAGGA_BOYZ_A")
	var fn := func(board, s): return _melee(board, "U_BEAST_SNAGGA_BOYZ_A", "U_ALLARUS_CUSTODIANS_A", w, s)
	var board_hunt: Dictionary = GS.state.duplicate(true)
	_set_detachment(1, "War Horde")
	var board_horde: Dictionary = GS.state.duplicate(true)
	_set_detachment(1, "Da Big Hunt")
	# Each resolution reads the detachment from GameState: run the pair per detachment.
	var pair_a: Array = [99, 99, -1]
	for s in range(13, 53):
		var ap_hunt := _save_ap(fn.call(board_hunt.duplicate(true), s))
		_set_detachment(1, "War Horde")
		var ap_horde := _save_ap(fn.call(board_horde.duplicate(true), s))
		_set_detachment(1, "Da Big Hunt")
		if ap_hunt != 99 and ap_horde != 99:
			pair_a = [ap_hunt, ap_horde, s]
			break
	_check("A/B melee %s vs VEHICLE (seed %d): Da Big Hunt AP %d, War Horde AP %d" % [w, int(pair_a[2]), int(pair_a[0]), int(pair_a[1])],
		int(pair_a[2]) > 0 and int(pair_a[0]) == int(pair_a[1]) - 1)
	_u("U_ALLARUS_CUSTODIANS_A").meta.keywords.erase("VEHICLE")
	_check("no 10e Prey selected at 11e", (func():
		FAM.on_command_phase_start(1)
		for uid in GS.state.units:
			if GS.state.units[uid].get("flags", {}).get("is_prey_of_1", false):
				return false
		return true).call())


func _section_kult_of_speed() -> void:
	print("\n-- F. Kult of Speed — Adrenaline Junkies --")
	_reload("Kult of Speed")
	var bikes := _u("U_WARBIKERS_A")
	_check("Speed Freeks: advancing never prevents a charge", EffectPrimitivesData.has_effect_advance_and_charge(bikes))
	_check("Speed Freeks: falling back never prevents a charge", EffectPrimitivesData.has_effect_fall_back_and_charge(bikes))
	_check("no [ASSAULT] before an advance / fall-back move", not EffectPrimitivesData.has_effect_advance_and_shoot(bikes))
	bikes.flags["advanced"] = true
	_check("advanced Speed Freeks: ranged attacks have [ASSAULT]", EffectPrimitivesData.has_effect_advance_and_shoot(bikes))
	var wid := _ranged_weapon("U_WARBIKERS_A")
	var v: Dictionary = RE.validate_shoot({"actor_unit_id": "U_WARBIKERS_A", "payload": {"assignments": [_assign(GS.state, "U_WARBIKERS_A", wid, "U_CUSTODIAN_GUARD_C")]}}, GS.state)
	_check("validate_shoot: no 'non-Assault after Advancing' error", not str(v.get("errors", [])).contains("after Advancing"), str(v.get("errors", [])))
	_check("11e Assault shooting (10.05): eligible for the advanced Warbikers",
		bool(load("res://scripts/rules/shootingtypes/AssaultShooting.gd").new().eligible("U_WARBIKERS_A", GS.state).get("eligible", false)))
	bikes.flags.erase("advanced")
	bikes.flags["fell_back"] = true
	v = RE.validate_shoot({"actor_unit_id": "U_WARBIKERS_A", "payload": {"assignments": [_assign(GS.state, "U_WARBIKERS_A", wid, "U_CUSTODIAN_GUARD_C")]}}, GS.state)
	_check("fell back: still not eligible to shoot (09.07 — [ASSAULT] does not override it)", str(v.get("errors", [])).contains("fell back"), str(v.get("errors", [])))
	_check("Kommandos (not Speed Freeks): no advance-and-charge", not EffectPrimitivesData.has_effect_advance_and_charge(_u("U_KOMMANDOS_A")))
	_check("the 10e helpers are off at 11e", not FAM.unit_has_adrenaline_junkies(bikes) and not FAM.unit_has_detachment_assault(bikes))
	# 11e charge template: a Speed Freeks unit that advanced can still declare a charge.
	bikes.flags.erase("fell_back")
	bikes.flags["advanced"] = true
	bikes.flags["cannot_charge"] = true
	var tmpl = load("res://scripts/rules/movetypes/MoveTypes.gd").get_type("charge")
	var el: Dictionary = tmpl.eligible("U_WARBIKERS_A", GS.state)
	_check("11e charge template: advanced Warbikers are eligible to charge", bool(el.get("eligible", false)) or not str(el.get("reasons", [])).contains("advanced"), str(el))
	var kom := _u("U_KOMMANDOS_A")
	kom.flags["advanced"] = true
	kom.flags["cannot_charge"] = true
	el = tmpl.eligible("U_KOMMANDOS_A", GS.state)
	_check("... advanced Kommandos are not", not bool(el.get("eligible", true)), str(el))


func _section_taktikal() -> void:
	print("\n-- G. Taktikal Brigade — Suspiciously Well Organised --")
	_reload("Taktikal Brigade")
	for uid in ["U_BOYZ_B", "U_KOMMANDOS_A", "U_STORMBOYZ_A"]:
		_check("%s: falling back does not prevent a charge" % uid, EffectPrimitivesData.has_effect_fall_back_and_charge(_u(uid)))
	_check("Nobz: no", not EffectPrimitivesData.has_effect_fall_back_and_charge(_u("U_NOBZ_A")))
	_check("advancing still prevents it (fall-back only)", not EffectPrimitivesData.has_effect_advance_and_charge(_u("U_KOMMANDOS_A")))
	var kom := _u("U_KOMMANDOS_A")
	kom.flags["fell_back"] = true
	kom.flags["cannot_charge"] = true
	var tmpl = load("res://scripts/rules/movetypes/MoveTypes.gd").get_type("charge")
	var el: Dictionary = tmpl.eligible("U_KOMMANDOS_A", GS.state)
	_check("11e charge template: Kommandos that fell back are not refused for it", bool(el.get("eligible", false)) or not str(el.get("reasons", [])).contains("advanced or fell back"), str(el))
	_check("10e Lissen 'Ere Taktiks are not offered at 11e", FAM.get_taktik_issuers(1).is_empty() and not bool(FAM.can_issue_taktik("U_WARBOSS_A", "Get Stuck In", "U_BOYZ_B").get("can", true)))


func _section_blitz_brigade() -> void:
	print("\n-- H. Blitz Brigade — Unstoppable Momentum --")
	_reload("Blitz Brigade")
	_check("WAGON: advance roll changed to a 6", Det.advance_roll_override(_u("U_BATTLEWAGON_A")) == 6)
	_check("Trukk (not WAGON): no", Det.advance_roll_override(_u("U_TRUKK_A")) == 0)
	_check("WAGON: free charge re-roll (Unstoppable Momentum)", Det.charge_reroll_source(_u("U_BATTLEWAGON_A")) == "Unstoppable Momentum"
		and FAM.unit_has_detachment_charge_reroll(_u("U_BATTLEWAGON_A")))
	_check("Trukk: no charge re-roll", not FAM.unit_has_detachment_charge_reroll(_u("U_TRUKK_A")))
	_check("the 10e disembark advance re-roll is off", not FAM.unit_has_detachment_advance_reroll(_u("U_BATTLEWAGON_A")))
	PM.transition_to_phase(PHASE_MOVEMENT)
	var phase = PM.get_current_phase_instance()
	# WP-O6: the codex Da Jump (Weirdboy) is offered at the start of the
	# Movement phase — decline that window before the advance.
	for _i in range(3):
		if phase.has_pending_stratagem_window():
			var sw: Dictionary = phase.get_pending_stratagem_window()
			phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(sw.get("player", 1)), "window_id": str(sw.get("window_id", ""))})
	var seed_low := 1
	for s in range(1, 300):
		if int(RE.RNGService.new(s).roll_d6(1)[0]) <= 2:
			seed_low = s
			break
	var res: Dictionary = phase.execute_action({"type": "BEGIN_ADVANCE", "actor_unit_id": "U_BATTLEWAGON_A", "player": 1, "payload": {"rng_seed": seed_low}})
	for _i in range(3):
		if phase.has_pending_stratagem_window():
			var pw: Dictionary = phase.get_pending_stratagem_window()
			phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 1, "window_id": str(pw.get("window_id", ""))})
	_check("a changed 6 is not re-rolled: no Waaagh! / Command Re-roll pause", not phase._awaiting_reroll_decision,
		str(phase._reroll_pending_data))
	if phase._awaiting_reroll_decision:
		phase.execute_action({"type": "DECLINE_COMMAND_REROLL", "actor_unit_id": "U_BATTLEWAGON_A", "player": 1})
	_check("BEGIN_ADVANCE (rolled a 1-2): the Battlewagon advances 6\"", int(phase.active_moves.get("U_BATTLEWAGON_A", {}).get("advance_roll", -1)) == 6, str(res.get("error", "")))
	PM.transition_to_phase(PHASE_CHARGE)
	var cphase = PM.get_current_phase_instance()
	_check("the charge re-roll is named Unstoppable Momentum", cphase._get_charge_reroll_ability_name("U_BATTLEWAGON_A") == "Unstoppable Momentum")


func _section_wreckas() -> void:
	print("\n-- I. Wreckas — Wreckin' and Lootin' --")
	_reload("Wreckas")
	_set_turn(2, 1, PHASE_SHOOTING)
	# Fixture: obj_home_1 at (22, 4)"; Flash Gitz near (4, 15.7)" — out of range.
	_check("Flash Gitz away from objectives, target away: none", Det.hit_reroll_ones_source(_u("U_FLASH_GITZ_A"), _u("U_CUSTODIAN_GUARD_C"), false) == "")
	_place_unit("U_FLASH_GITZ_A", 22.0, 5.0)
	_check("unit within range of an objective: re-roll 1s", "unit within range" in Det.hit_reroll_ones_source(_u("U_FLASH_GITZ_A"), _u("U_CUSTODIAN_GUARD_C"), false))
	_place_unit("U_FLASH_GITZ_A", 4.0, 16.0)
	_place_unit("U_CUSTODIAN_GUARD_C", 10.0, 22.0)  # obj_nml_1 at (10, 22)"
	_check("target within range of an objective: re-roll 1s", "target within range" in Det.hit_reroll_ones_source(_u("U_FLASH_GITZ_A"), _u("U_CUSTODIAN_GUARD_C"), false))
	_check("Boyz (not Breaka/Flash Gitz/Tankbustas): none", Det.hit_reroll_ones_source(_u("U_BOYZ_B"), _u("U_CUSTODIAN_GUARD_C"), false) == "")
	_check("melee: none", Det.hit_reroll_ones_source(_u("U_FLASH_GITZ_A"), _u("U_CUSTODIAN_GUARD_C"), true) == "")
	_set_turn(2, 2, PHASE_SHOOTING)
	_check("the opponent's turn (Overwatch): none", Det.hit_reroll_ones_source(_u("U_FLASH_GITZ_A"), _u("U_CUSTODIAN_GUARD_C"), false) == "")
	_set_turn(2, 1, PHASE_SHOOTING)
	var wid := _ranged_weapon("U_FLASH_GITZ_A")
	var a := _block(_interactive(GS.state.duplicate(true), "U_FLASH_GITZ_A", _assign(GS.state, "U_FLASH_GITZ_A", wid, "U_CUSTODIAN_GUARD_C"), 3), "to_hit")
	_set_detachment(1, "War Horde")
	var b := _block(_interactive(GS.state.duplicate(true), "U_FLASH_GITZ_A", _assign(GS.state, "U_FLASH_GITZ_A", wid, "U_CUSTODIAN_GUARD_C"), 3), "to_hit")
	_check("A/B interactive ranged: the ledger names Wreckin' and Lootin' (re-roll 1s) only for Wreckas", _ledger_has(a, "Wreckin") and not _ledger_has(b, "Wreckin"), str(a.get("modifier_ledger", [])))
	_set_detachment(1, "Wreckas")
	var c := _block(_auto(GS.state.duplicate(true), "U_FLASH_GITZ_A", _assign(GS.state, "U_FLASH_GITZ_A", wid, "U_CUSTODIAN_GUARD_C"), 3), "to_hit")
	_check("auto-resolve path too", _ledger_has(c, "Wreckin"))
	var ones := 0
	for r in a.get("rolls_raw", []):
		if int(r) == 1:
			ones += 1
	_check("every unmodified 1 was re-rolled (%d ones, %d re-rolls)" % [ones, a.get("rerolls", []).size()], a.get("rerolls", []).size() >= ones)


func _section_runt_swarm() -> void:
	print("\n-- J. Runt Swarm — Sneaky Little Gitz --")
	_reload("Runt Swarm")
	var am = load("res://scripts/rules/ActionsManager.gd")
	var g := _u("U_GRETCHIN_D")
	_check("Gretchin: an advance / fall-back keeps action eligibility", Det.move_keeps_action_eligibility(g))
	_check("Boyz: no", not Det.move_keeps_action_eligibility(_u("U_BOYZ_B")))
	g.flags["advanced"] = true
	var chk: Dictionary = am.can_start_action("U_GRETCHIN_D", GS.state)
	_check("advanced Gretchin can still start an action", not str(chk.get("reasons", [])).contains("advance"), str(chk))
	g.flags.erase("advanced")
	g.flags["fell_back"] = true
	chk = am.can_start_action("U_GRETCHIN_D", GS.state)
	_check("fell-back Gretchin can still start an action", not str(chk.get("reasons", [])).contains("advance"), str(chk))
	_set_detachment(1, "War Horde")
	chk = am.can_start_action("U_GRETCHIN_D", GS.state)
	_check("War Horde Gretchin that fell back cannot", str(chk.get("reasons", [])).contains("advance"), str(chk))


func _section_shoota_boyz() -> void:
	print("\n-- K. Shoota Boyz — Dakka! Dakka! Dakka! --")
	_reload("Shoota Boyz")
	_check("ORKS INFANTRY: ranged [ASSAULT]", EffectPrimitivesData.has_effect_advance_and_shoot(_u("U_KOMMANDOS_A")))
	_check("Deff Dread (WALKER): no", not EffectPrimitivesData.has_effect_advance_and_shoot(_u("U_DEFF_DREAD_A")))
	var wid := _ranged_weapon("U_KOMMANDOS_A")
	_u("U_KOMMANDOS_A").flags["advanced"] = true
	var v: Dictionary = RE.validate_shoot({"actor_unit_id": "U_KOMMANDOS_A", "payload": {"assignments": [_assign(GS.state, "U_KOMMANDOS_A", wid, "U_CUSTODIAN_GUARD_C")]}}, GS.state)
	_check("advanced Kommandos may fire %s" % wid, not str(v.get("errors", [])).contains("after Advancing"), str(v.get("errors", [])))
	# The 11e shooting-type template (10.05 Assault shooting) the UI selects through.
	var ast = load("res://scripts/rules/shootingtypes/AssaultShooting.gd").new()
	var ae: Dictionary = ast.eligible("U_KOMMANDOS_A", GS.state)
	_check("11e Assault shooting (10.05): eligible for the advanced Kommandos", bool(ae.get("eligible", false)), str(ae))
	_check("... and it allows their printed non-[ASSAULT] %s" % wid, bool(ast.weapon_allowed(RE.get_weapon_profile(wid, GS.state), _u("U_KOMMANDOS_A"), GS.state).get("allowed", false)))
	_set_detachment(1, "War Horde")
	ae = ast.eligible("U_KOMMANDOS_A", GS.state)
	_check("War Horde, not riled up: no Assault shooting type (no [ASSAULT] weapons)", not bool(ae.get("eligible", true)) and str(ae.get("reasons", [])).contains("ASSAULT"), str(ae))
	FAM.detect_faction_abilities(1)
	FAM.activate_waaagh(1)
	ae = ast.eligible("U_KOMMANDOS_A", GS.state)
	_check("War Horde, riled up (War Cry): Assault shooting type eligible — riled-up ranged [ASSAULT]", bool(ae.get("eligible", false)), str(ae))
	FAM.deactivate_waaagh(1)
	FAM.load_state({})  # War Cry is once per battle: reset it for the range checks below
	_set_detachment(1, "Shoota Boyz")
	_check("not riled up: no range bonus", Det.range_bonus_inches(_u("U_KOMMANDOS_A"), RE.get_weapon_profile(wid, GS.state)) == 0.0)
	FAM.detect_faction_abilities(1)
	FAM.activate_waaagh(1)
	_check("riled up: +3\" Range", Det.range_bonus_inches(_u("U_KOMMANDOS_A"), RE.get_weapon_profile(wid, GS.state)) == 3.0)
	_check("melee profiles never gain range", Det.range_bonus_inches(_u("U_KOMMANDOS_A"), {"type": "Melee", "range": "Melee"}) == 0.0)
	# Range gate: a target just beyond the weapon's range becomes eligible.
	var rng_in := float(RE.get_weapon_profile(wid, GS.state).get("range", 12))
	_place_unit("U_KOMMANDOS_A", 22.0, 10.0, 1.0)
	_place_unit("U_CUSTODIAN_GUARD_C", 22.0, 10.0 + rng_in + 2.0, 2.0)
	var elig: Dictionary = RE.get_eligible_shooter_models("U_KOMMANDOS_A", wid, "U_CUSTODIAN_GUARD_C", GS.state)
	FAM.deactivate_waaagh(1)
	var elig_plain: Dictionary = RE.get_eligible_shooter_models("U_KOMMANDOS_A", wid, "U_CUSTODIAN_GUARD_C", GS.state)
	_check("riled up: models %.0f\"+2\" away are in range (+3\")" % rng_in, not elig.get("eligible", []).is_empty(), str(elig.get("reasons", {})))
	_check("not riled up: out of range", elig_plain.get("eligible", []).is_empty())


func _section_flyboyz() -> void:
	print("\n-- L. Flyboyz — Skyborne Loons --")
	_reload("Flyboyz")
	_check("AIRCRAFT do not count towards the reserves points", Det.reserves_points_value(_u("U_DAKKAJET_A")) == 0 and int(_u("U_DAKKAJET_A").meta.get("points", 0)) > 0)
	_check("Deffkoptas (not AIRCRAFT) count", Det.reserves_points_value(_u("U_DEFFKOPTAS_A")) == int(_u("U_DEFFKOPTAS_A").meta.get("points", 0)))
	_u("U_DAKKAJET_A")["status"] = GS.UnitStatus.IN_RESERVES
	_check("GameState.get_reserves_points ignores the Dakkajet", GS.get_reserves_points(1) == 0)
	_set_detachment(1, "War Horde")
	_check("other detachments: the Dakkajet counts", GS.get_reserves_points(1) == int(_u("U_DAKKAJET_A").meta.get("points", 0)))
	_set_detachment(1, "Flyboyz")
	_u("U_DAKKAJET_A")["status"] = GS.UnitStatus.DEPLOYED
	_check("not riled up: no +1 to hit", Det.hit_plus_one_source(_u("U_DEFFKOPTAS_A"), _u("U_CUSTODIAN_GUARD_C"), false) == "")
	FAM.detect_faction_abilities(1)
	FAM.activate_waaagh(1)
	_check("riled-up Deffkoptas: +1 to hit (ranged)", Det.hit_plus_one_source(_u("U_DEFFKOPTAS_A"), _u("U_CUSTODIAN_GUARD_C"), false) != "")
	_check("riled-up Dakkajet: +1 to hit", Det.hit_plus_one_source(_u("U_DAKKAJET_A"), _u("U_CUSTODIAN_GUARD_C"), false) != "")
	_check("riled-up Boyz: no", Det.hit_plus_one_source(_u("U_BOYZ_B"), _u("U_CUSTODIAN_GUARD_C"), false) == "")
	_check("melee: no", Det.hit_plus_one_source(_u("U_DEFFKOPTAS_A"), _u("U_CUSTODIAN_GUARD_C"), true) == "")
	_set_turn(2, 1, PHASE_SHOOTING)
	var wid := _ranged_weapon("U_DEFFKOPTAS_A")
	_place_unit("U_CUSTODIAN_GUARD_C", 26.0, 20.0, 2.0)
	var a := _block(_interactive(GS.state.duplicate(true), "U_DEFFKOPTAS_A", _assign(GS.state, "U_DEFFKOPTAS_A", wid, "U_CUSTODIAN_GUARD_C"), 5), "to_hit")
	_check("interactive ranged: +1 to hit named Skyborne Loons", _ledger_has(a, "Skyborne"), str(a.get("modifier_ledger", [])))
	var c := _block(_auto(GS.state.duplicate(true), "U_DEFFKOPTAS_A", _assign(GS.state, "U_DEFFKOPTAS_A", wid, "U_CUSTODIAN_GUARD_C"), 5), "to_hit")
	_check("auto-resolve: +1 to hit named Skyborne Loons", _ledger_has(c, "Skyborne"))
	# Formations validation (the 50% reserves points cap is per points).
	var fphase = load("res://phases/FormationsPhase.gd").new()
	fphase.player_formations = {1: {"reserves": [{"unit_id": "U_DAKKAJET_A", "reserve_type": "strategic_reserves"}]}, 2: {}}
	_check("FormationsPhase: a declared Dakkajet adds 0 reserves points", fphase._get_declared_reserves_points(1) == 0)
	fphase.free()


func _section_madcap_meks() -> void:
	print("\n-- M. Madcap Meks — Unpredictable Genius --")
	_reload("Madcap Meks")
	_set_turn(2, 1, PHASE_SHOOTING)
	_check("Mek Gunz are eligible", Det.ug_eligible(_u("U_MEK_GUNZ_A")))
	_check("Boyz are not", not Det.ug_eligible(_u("U_BOYZ_B")))
	var wid := _ranged_weapon("U_MEK_GUNZ_A")
	var a1 := _assign(GS.state, "U_MEK_GUNZ_A", wid, "U_CUSTODIAN_GUARD_C")
	var a2 := _assign(GS.state, "U_MEK_GUNZ_A", wid, "U_CUSTODIAN_GUARD_D")
	_check("split fire: no roll", not Det.ug_on_targets_confirmed("U_MEK_GUNZ_A", [a1, a2]).get("applied", true))
	_set_turn(2, 2, PHASE_SHOOTING)
	_check("not in the opponent's turn", not Det.ug_on_targets_confirmed("U_MEK_GUNZ_A", [a1]).get("applied", true))
	_set_turn(2, 1, PHASE_SHOOTING)
	var r: Dictionary = Det.ug_on_targets_confirmed("U_MEK_GUNZ_A", [a1], -1, true)
	_check("single target: rolled (result %d)" % int(r.get("result", 0)), r.get("applied", false) and int(r.result) >= 1 and int(r.result) <= 6)
	_check("result recorded on the shooter", int(_flags("U_MEK_GUNZ_A").get(Det.F_UG, {}).get("result", 0)) == int(r.result))
	_check("rolled once per shooting (a repeat confirm does not re-roll)", not Det.ug_on_targets_confirmed("U_MEK_GUNZ_A", [a1]).get("applied", true))
	# Each result's effect (the result itself is forced — the trigger above is real).
	var shooter := _u("U_MEK_GUNZ_A")
	var tgt := _u("U_CUSTODIAN_GUARD_C")
	shooter.flags[Det.F_UG] = {"result": 1, "target": "U_CUSTODIAN_GUARD_C", "stamp": "x"}
	_check("1 Dat's Weird: target 4+ InSv vs this shooter", Det.target_invuln(shooter, tgt, 0) == 4 and Det.target_invuln(shooter, tgt, 3) == 3)
	_check("... not for another shooter", Det.target_invuln(_u("U_KOMMANDOS_A"), tgt, 0) == 0)
	shooter.flags[Det.F_UG] = {"result": 4, "target": "U_CUSTODIAN_GUARD_C", "stamp": "x"}
	_check("4 Seekerz: +1 to hit", Det.hit_plus_one_source(shooter, tgt, false) != "")
	_check("... only at that target", Det.hit_plus_one_source(shooter, _u("U_CUSTODIAN_GUARD_D"), false) == "")
	shooter.flags[Det.F_UG] = {"result": 6, "target": "U_CUSTODIAN_GUARD_C", "stamp": "x"}
	var t0 := int(tgt.meta.stats.get("toughness", 6))
	_check("6 Runtified: target T-1 (%d -> %d)" % [t0, t0 - 1], Det.target_toughness(shooter, tgt, t0) == t0 - 1)
	var board6: Dictionary = GS.state.duplicate(true)
	var w6 := _block(_interactive(board6, "U_MEK_GUNZ_A", a1, 8), "to_wound")
	shooter.flags.erase(Det.F_UG)
	var w6b := _block(_interactive(GS.state.duplicate(true), "U_MEK_GUNZ_A", a1, 8), "to_wound")
	_check("A/B interactive (seed 8): Runtified T-1 moves the wound roll %s -> %s" % [str(w6b.get("threshold", "")), str(w6.get("threshold", ""))],
		not w6.is_empty() and not w6b.is_empty() and str(w6.get("threshold", "")).to_int() < str(w6b.get("threshold", "")).to_int())
	shooter.flags[Det.F_UG] = {"result": 5, "target": "U_CUSTODIAN_GUARD_C", "stamp": "x"}
	_check("5 Lifted: this shooter's attacks ignore cover", Det.attacks_deny_cover(shooter) and ModifierStack.attack_ignores_cover(shooter, {}, {}))
	# Lifted grants FLY through the real trigger: force by re-rolling until a 5 (bounded).
	_reload("Madcap Meks")
	_set_turn(2, 1, PHASE_SHOOTING)
	var lifted := false
	for _i in range(60):
		_flags("U_MEK_GUNZ_A").erase(Det.F_UG)
		var rr: Dictionary = Det.ug_on_targets_confirmed("U_MEK_GUNZ_A", [a1], -1, true)
		if int(rr.get("result", 0)) == 5:
			lifted = true
			break
		Det.on_unit_has_shot("U_MEK_GUNZ_A")
	_check("a rolled 5 (Lifted) gives the target FLY", lifted and "FLY" in _kw("U_CUSTODIAN_GUARD_C"))
	Det.on_unit_has_shot("U_MEK_GUNZ_A")
	_check("FLY removed and the result cleared when the unit has shot", not "FLY" in _kw("U_CUSTODIAN_GUARD_C") and not _flags("U_MEK_GUNZ_A").has(Det.F_UG))
	# Hop Splat: other enemy units within 3" of the target.
	_place_unit("U_CUSTODIAN_GUARD_C", 10.0, 30.0, 2.0)
	_place_unit("U_CUSTODIAN_GUARD_D", 10.0, 33.0, 2.0)
	_place_unit("U_BLADE_CHAMPION_B", 14.0, 30.0)
	var opts: Array = Det.hop_splat_options(_u("U_MEK_GUNZ_A"), "U_CUSTODIAN_GUARD_C")
	_check("Hop Splat candidates within 3\": %s" % str(opts), "U_CUSTODIAN_GUARD_D" in opts and "U_BLADE_CHAMPION_B" in opts and not "U_CUSTODIAN_GUARD_C" in opts)
	var wounds_before := 0
	for m in _u("U_CUSTODIAN_GUARD_D").models:
		wounds_before += int(m.get("current_wounds", m.get("wounds", 1)))
	var hs: Array = Det.resolve_hop_splat("U_MEK_GUNZ_A", "U_CUSTODIAN_GUARD_D")
	var wounds_after := 0
	for m in _u("U_CUSTODIAN_GUARD_D").models:
		if m.get("alive", true):
			wounds_after += int(m.get("current_wounds", m.get("wounds", 1)))
	_check("Hop Splat: D3 mortal wounds applied (%d -> %d)" % [wounds_before, wounds_after], wounds_after < wounds_before and wounds_before - wounds_after <= 3 and not hs.is_empty())
	var entry: Dictionary = Det.hop_splat_window_entry("U_MEK_GUNZ_A", "U_CUSTODIAN_GUARD_C", opts)
	var offers: Array = SM.get_window_offers(1, Det.WINDOW_HOP_SPLAT, entry.ctx)
	_check("Hop Splat window offers each candidate", offers.size() == 1 and offers[0].targets.size() == opts.size())
	var dec: Array = Det.hop_splat_after_window(entry.ctx, {"used": false})
	_check("a declined Hop Splat hits the closest candidate", not dec.is_empty())
	var hs_use: Dictionary = SM.use_stratagem(1, Det.RULE_HOP_SPLAT, "U_CUSTODIAN_GUARD_D", entry.ctx)
	_check("a Hop Splat pick succeeds and its rule-only window is NOT re-offered (one Hop Splat per roll)",
		hs_use.get("success", false) and not bool(hs_use.get("reopen_window", true)), str(hs_use))
	_check("... and the window's after-hook adds nothing once a unit was picked", Det.hop_splat_after_window(entry.ctx, {"used": true}).is_empty())
	_check("AI pick is a candidate", Det.ai_pick_hop_splat(opts) in opts)
	# The real CONFIRM_TARGETS path rolls and the post-shot hook clears it.
	_reload("Madcap Meks")
	PM.transition_to_phase(PHASE_SHOOTING)
	var phase = PM.get_current_phase_instance()
	var sres: Dictionary = phase.execute_action({"type": "SHOOT", "actor_unit_id": "U_MEK_GUNZ_A", "player": 1,
		"payload": {"assignments": [_assign(GS.state, "U_MEK_GUNZ_A", wid, "U_CUSTODIAN_GUARD_C")], "rng_seed": 4}})
	for _i in range(3):
		if phase.has_pending_stratagem_window():
			var pw: Dictionary = phase.get_pending_stratagem_window()
			sres = phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(pw.get("player", 1)), "window_id": str(pw.get("window_id", ""))})
	_check("atomic SHOOT resolves", sres.get("success", false) and "U_MEK_GUNZ_A" in phase.units_that_shot, str(sres.get("error", "")))
	var logged := false
	var gel = root.get_node_or_null("GameEventLog")
	if gel and "entries" in gel:
		for e in gel.entries:
			if "UNPREDICTABLE GENIUS" in str(e.get("text", e)):
				logged = true
	_check("the roll is in the Game Log", logged or gel == null)
	_check("cleared once the unit has shot", not _flags("U_MEK_GUNZ_A").has(Det.F_UG))
	SM.on_phase_end(PHASE_SHOOTING)


func _section_dread_mob() -> void:
	print("\n-- N. Dread Mob — Try Dat Button! --")
	_reload("Dread Mob")
	_set_turn(2, 1, PHASE_SHOOTING)
	_check("Deff Dread (ORKS WALKER) eligible", Det.try_dat_eligible(_u("U_DEFF_DREAD_A")))
	_check("Killa Kans (WALKER) eligible", Det.try_dat_eligible(_u("U_KILLA_KANS_A")))
	_check("Battlewagon (not WALKER) not", not Det.try_dat_eligible(_u("U_BATTLEWAGON_A")))
	var offers: Array = Det.window_offers(1, "unit_selected_to_shoot", {"unit_id": "U_DEFF_DREAD_A"})
	_check("offered in unit_selected_to_shoot (two variants, free)", offers.size() == 1 and offers[0].targets[0].variants.size() == 2 and bool(offers[0].rule))
	_check("offered in unit_selected_to_fight", Det.window_offers(1, "unit_selected_to_fight", {"unit_id": "U_DEFF_DREAD_A"}).size() == 1)
	_set_turn(2, 2, PHASE_SHOOTING)
	_check("not in the opponent's Shooting phase", Det.window_offers(1, "unit_selected_to_shoot", {"unit_id": "U_DEFF_DREAD_A"}).is_empty())
	_set_turn(2, 1, PHASE_SHOOTING)
	_check("not for the Battlewagon", Det.window_offers(1, "unit_selected_to_shoot", {"unit_id": "U_BATTLEWAGON_A"}).is_empty())
	# Two dice land on two different table rows.
	var distinct := true
	for _i in range(40):
		var r: Dictionary = Det.roll_try_dat(true, RE.make_rng())
		if r.rows.size() != 2 or r.rows[0] == r.rows[1]:
			distinct = false
	_check("two D6: duplicate results re-rolled (always two different rules, 40 rolls)", distinct)
	var one: Dictionary = Det.roll_try_dat(false, RE.make_rng())
	_check("one D6: one rule", one.rows.size() == 1)
	# Use through the stratagem-manager hook (no CP).
	var cp1 := int(GS.state.players["1"].cp)
	var use: Dictionary = SM.use_stratagem(1, Det.RULE_TRY_DAT_BUTTON, "U_DEFF_DREAD_A", {"variant_id": "two", "window_id": "unit_selected_to_shoot"})
	_check("use: success, reopen_window, no CP", use.get("success", false) and bool(use.get("reopen_window", false)) and int(GS.state.players["1"].cp) == cp1)
	var tdb: Dictionary = _flags("U_DEFF_DREAD_A").get(Det.F_TDB, {})
	_check("flag holds two rows and the hazard marker", tdb.get("rows", []).size() == 2 and bool(tdb.get("two", false)))
	_check("not offered again for this selection", Det.window_offers(1, "unit_selected_to_shoot", {"unit_id": "U_DEFF_DREAD_A"}).is_empty())
	_check("a plain (variant-less) use is refused", not SM.use_stratagem(1, Det.RULE_TRY_DAT_BUTTON, "U_KILLA_KANS_A", {}).get("success", true))
	# Effect A/B through the resolvers (forced rows on a board copy).
	var wid := _ranged_weapon("U_DEFF_DREAD_A", "shoota")
	if wid == "":
		wid = _ranged_weapon("U_DEFF_DREAD_A")
	_place_unit("U_CUSTODIAN_GUARD_C", 14.0, 30.0, 2.0)
	var base_board: Dictionary = GS.state.duplicate(true)
	base_board.units.U_DEFF_DREAD_A.flags.erase(Det.F_TDB)
	var a_board: Dictionary = base_board.duplicate(true)
	a_board.units.U_DEFF_DREAD_A.flags[Det.F_TDB] = {"a": 1, "s": 0, "ap": 0, "rows": ["+1 A"], "two": false}
	var hit_a := _block(_interactive(a_board, "U_DEFF_DREAD_A", _assign(base_board, "U_DEFF_DREAD_A", wid, "U_CUSTODIAN_GUARD_C"), 6), "to_hit")
	var hit_0 := _block(_interactive(base_board, "U_DEFF_DREAD_A", _assign(base_board, "U_DEFF_DREAD_A", wid, "U_CUSTODIAN_GUARD_C"), 6), "to_hit")
	_check("+1 A: one more attack per model (%d vs %d dice)" % [hit_a.get("rolls_raw", []).size(), hit_0.get("rolls_raw", []).size()],
		hit_a.get("rolls_raw", []).size() == hit_0.get("rolls_raw", []).size() + 1)
	var s_board: Dictionary = base_board.duplicate(true)
	s_board.units.U_DEFF_DREAD_A.flags[Det.F_TDB] = {"a": 0, "s": 2, "ap": 0, "rows": ["+2 S"], "two": false}
	var mw := _melee_weapon("U_DEFF_DREAD_A")
	# (the 11e melee allocation writes casualties into the board it is given: copies)
	var ws := _block(_melee(s_board.duplicate(true), "U_DEFF_DREAD_A", "U_PROSECUTORS_A", mw, 2), "wound_roll_melee")
	var w0 := _block(_melee(base_board.duplicate(true), "U_DEFF_DREAD_A", "U_PROSECUTORS_A", mw, 2), "wound_roll_melee")
	_check("+2 S (melee %s): strength %s vs %s" % [mw, str(ws.get("strength", "?")), str(w0.get("strength", "?"))],
		not ws.is_empty() and not w0.is_empty() and int(ws.get("strength", 0)) == int(w0.get("strength", 0)) + 2)
	var ap_board: Dictionary = base_board.duplicate(true)
	ap_board.units.U_DEFF_DREAD_A.flags[Det.F_TDB] = {"a": 0, "s": 0, "ap": 1, "rows": ["+1 AP"], "two": false}
	_check("+1 AP through get_prey_ap_bonus", RE.get_prey_ap_bonus(ap_board.units.U_DEFF_DREAD_A, ap_board.units.U_PROSECUTORS_A) == 1)
	var asg := _assign(base_board, "U_DEFF_DREAD_A", wid, "U_CUSTODIAN_GUARD_C")
	var p_auto: Array = _ap_pair(func(b, s): return _auto(b, "U_DEFF_DREAD_A", asg, s), ap_board, base_board, 6)
	_check("+1 AP in the auto-resolve save data (seed %d: AP %d vs %d)" % [int(p_auto[2]), int(p_auto[0]), int(p_auto[1])], int(p_auto[2]) > 0 and int(p_auto[0]) == int(p_auto[1]) - 1)
	var p_int: Array = _ap_pair(func(b, s): return _interactive(b, "U_DEFF_DREAD_A", asg, s), ap_board, base_board, 6)
	_check("+1 AP in the interactive save data (seed %d: AP %d vs %d)" % [int(p_int[2]), int(p_int[0]), int(p_int[1])], int(p_int[2]) > 0 and int(p_int[0]) == int(p_int[1]) - 1)
	var p_mel: Array = _ap_pair(func(b, s): return _melee(b, "U_DEFF_DREAD_A", "U_PROSECUTORS_A", mw, s), ap_board, base_board, 2)
	_check("+1 AP in melee (seed %d: AP %d vs %d)" % [int(p_mel[2]), int(p_mel[0]), int(p_mel[1])], int(p_mel[2]) > 0 and int(p_mel[0]) == int(p_mel[1]) - 1)
	# When the unit has attacked: one hazard roll (two dice), then the effect ends.
	var wounds_before := 0
	for m in _u("U_DEFF_DREAD_A").models:
		wounds_before += int(m.get("current_wounds", m.get("wounds", 1)))
	var d: Array = Det.on_unit_has_shot("U_DEFF_DREAD_A")
	_check("has shot: the effect ends", not _flags("U_DEFF_DREAD_A").has(Det.F_TDB))
	var gel = root.get_node_or_null("GameEventLog")
	var haz := false
	if gel and "entries" in gel:
		for e in gel.entries:
			if "hazard roll" in str(e.get("text", e)):
				haz = true
	_check("... after the two-dice hazard roll (Game Log)", haz or gel == null, str(d))
	# One die: no hazard roll; phase end clears without one.
	SM.use_stratagem(1, Det.RULE_TRY_DAT_BUTTON, "U_KILLA_KANS_A", {"variant_id": "one", "window_id": "unit_selected_to_shoot"})
	_check("Killa Kans rolled one die", _flags("U_KILLA_KANS_A").get(Det.F_TDB, {}).get("rows", []).size() == 1)
	Det.on_phase_end("shooting")
	_check("end of phase clears a leftover result", not _flags("U_KILLA_KANS_A").has(Det.F_TDB))
	# AI: picks a variant (two dice only with a large wound pool).
	_reload("Dread Mob")
	_set_turn(2, 1, PHASE_SHOOTING)
	var ai_offers: Array = Det.window_offers(1, "unit_selected_to_shoot", {"unit_id": "U_DEFF_DREAD_A"})
	var pick: Dictionary = Det.ai_decide(1, "unit_selected_to_shoot", ai_offers, {"unit_id": "U_DEFF_DREAD_A"})
	_check("AI uses Try Dat Button! with a variant", pick.get("use", false) and str(pick.get("context", {}).get("variant_id", "")) in ["one", "two"], str(pick))
	# The real window: Deff Dread selected to shoot -> the window holds the rule offer.
	PM.transition_to_phase(PHASE_SHOOTING)
	var phase = PM.get_current_phase_instance()
	phase.execute_action({"type": "SELECT_SHOOTER", "actor_unit_id": "U_DEFF_DREAD_A", "player": 1})
	var pending: Dictionary = phase.get_pending_stratagem_window()
	var has_rule := false
	for o in pending.get("offers", []):
		if str(o.get("stratagem_id", "")) == Det.RULE_TRY_DAT_BUTTON:
			has_rule = true
	_check("SELECT_SHOOTER opens unit_selected_to_shoot with TRY DAT BUTTON!", str(pending.get("window_id", "")) == "unit_selected_to_shoot" and has_rule, str(pending.get("window_id", "")))
	var res: Dictionary = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_shoot",
		"stratagem_id": Det.RULE_TRY_DAT_BUTTON, "target_unit_id": "U_DEFF_DREAD_A", "context": {"variant_id": "one"}})
	_check("USE through the window succeeds", res.get("success", false), str(res.get("error", "")))
	var reopened: Dictionary = phase.get_pending_stratagem_window()
	var still_rule := false
	for o in reopened.get("offers", []):
		if str(o.get("stratagem_id", "")) == Det.RULE_TRY_DAT_BUTTON:
			still_rule = true
	_check("the window is re-offered for its stratagems without the rule (or closes if none)", not still_rule)
	if phase.has_pending_stratagem_window():
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_shoot"})
	_check("the Deff Dread carries its Try Dat Button! result", not _flags("U_DEFF_DREAD_A").get(Det.F_TDB, {}).is_empty())
	SM.on_phase_end(PHASE_SHOOTING)


func _section_brute_bosses() -> void:
	print("\n-- O. Brute Bosses — 'Ard as Nails --")
	_reload("Brute Bosses")
	_check("Warboss: applies", Det.ard_as_nails_applies(_u("U_WARBOSS_A")))
	_check("Boyz: no", not Det.ard_as_nails_applies(_u("U_BOYZ_B")))
	_check("not riled up: +0", int(Det.ard_as_nails_roll_modifier(_u("U_WARBOSS_A")).mod) == 0)
	FAM.detect_faction_abilities(1)
	FAM.activate_waaagh(1)
	_check("riled up: +1", int(Det.ard_as_nails_roll_modifier(_u("U_WARBOSS_A")).mod) == 1)
	_check("pass value 3+", Det.ARD_AS_NAILS_PASS == 3)
	# Through the Fight phase's Fight On Death intercept.
	PM.transition_to_phase(PHASE_FIGHT)
	var phase = PM.get_current_phase_instance()
	var kept_seen := false
	var removed_seen := false
	for s in range(1, 40):
		RE.set_test_seed(s)
		phase._ork11e_fod_rolled.clear()
		GS.state.units.U_WARBOSS_A.models[0]["alive"] = true
		GS.state.units.U_WARBOSS_A.flags.erase("ork11e_fod_pending")
		var changes: Array = [{"op": "set", "path": "units.U_WARBOSS_A.models.0.alive", "value": false}]
		phase._ork11e_fod_intercept(changes)
		if bool(changes[0].value):
			if "Ard as Nails" in str(changes):
				kept_seen = true
		else:
			removed_seen = true
		if kept_seen and removed_seen:
			break
	_check("'Ard as Nails keeps a destroyed Warboss on a pass, sourced 'Ard as Nails (seen across seeds)", kept_seen)
	_check("... and removes it on a fail (riled up: only a natural 1)", removed_seen)
	# Not for a non-Warboss model; not once the unit was selected to fight.
	phase._ork11e_fod_rolled.clear()
	var boy_changes: Array = [{"op": "set", "path": "units.U_BOYZ_B.models.0.alive", "value": false}]
	phase._ork11e_fod_intercept(boy_changes)
	_check("a Boy is removed normally", boy_changes[0].value == false)
	phase._ork11e_fod_rolled.clear()
	phase._ork11e_selected_to_fight["U_WARBOSS_A"] = true
	var sel_changes: Array = [{"op": "set", "path": "units.U_WARBOSS_A.models.0.alive", "value": false}]
	phase._ork11e_fod_intercept(sel_changes)
	_check("selected to fight this phase: no roll", sel_changes[0].value == false)
	phase._ork11e_selected_to_fight.erase("U_WARBOSS_A")
	_set_detachment(1, "War Horde")
	phase._ork11e_fod_rolled.clear()
	var wh_changes: Array = [{"op": "set", "path": "units.U_WARBOSS_A.models.0.alive", "value": false}]
	phase._ork11e_fod_intercept(wh_changes)
	_check("War Horde: no 'Ard as Nails", wh_changes[0].value == false)


func _section_wurrband() -> void:
	print("\n-- P. Wurrband — Powers of da Waaagh! / Roar of Mork / Visions of Violence --")
	_reload("Wurrband")
	var pv := ""
	var w = RE.get_unit_weapons("U_WEIRDBOY_A", GS.state)
	for mid in w:
		for wid in w[mid]:
			if RE.is_psychic_weapon(str(wid), GS.state):
				pv = str(wid)
	_check("the Weirdboy has a [PSYCHIC] weapon (%s)" % pv, pv != "")
	var sb: Dictionary = Det.strength_bonus(_u("U_WEIRDBOY_A"), pv)
	_check("[PSYCHIC] attacks: +1 S (+0 per 5 models: 1 model)", int(sb.value) == 1, str(sb))
	var wb_melee := _melee_weapon("U_WEIRDBOY_A")
	_check("the [PSYCHIC] melee %s: +1 S too" % wb_melee, int(Det.strength_bonus(_u("U_WEIRDBOY_A"), wb_melee).value) == 1)
	_check("a non-[PSYCHIC] weapon: none", int(Det.strength_bonus(_u("U_WEIRDBOY_A"), "slugga_ranged").value) == 0, str(Det.strength_bonus(_u("U_WEIRDBOY_A"), "slugga_ranged")))
	# A/B through the resolvers (same seed): Wurrband vs War Horde.
	_place_unit("U_WEIRDBOY_A", 20.0, 33.0)
	_place_unit("U_CUSTODIAN_GUARD_D", 20.0, 34.6, 2.0)
	_place_unit("U_PROSECUTORS_A", 20.0, 40.0, 1.5)
	var asg_pv := _assign(GS.state, "U_WEIRDBOY_A", pv, "U_PROSECUTORS_A")
	var wa := _block(_interactive(GS.state.duplicate(true), "U_WEIRDBOY_A", asg_pv, 21), "to_wound")
	_set_detachment(1, "War Horde")
	var wbb := _block(_interactive(GS.state.duplicate(true), "U_WEIRDBOY_A", asg_pv, 21), "to_wound")
	_set_detachment(1, "Wurrband")
	_check("A/B interactive Power Vomit (S5 vs T3 Prosecutors, seed 21): Wurrband wounds on %s (S6), War Horde on %s" % [str(wa.get("threshold", "")), str(wbb.get("threshold", ""))],
		not wa.is_empty() and not wbb.is_empty() and str(wa.get("threshold", "")).to_int() < str(wbb.get("threshold", "")).to_int())
	var am := _block(_melee(GS.state.duplicate(true), "U_WEIRDBOY_A", "U_CUSTODIAN_GUARD_D", wb_melee, 21), "wound_roll_melee")
	_set_detachment(1, "War Horde")
	var bm := _block(_melee(GS.state.duplicate(true), "U_WEIRDBOY_A", "U_CUSTODIAN_GUARD_D", wb_melee, 21), "wound_roll_melee")
	_set_detachment(1, "Wurrband")
	_check("A/B melee %s: strength %s vs %s" % [wb_melee, str(am.get("strength", "?")), str(bm.get("strength", "?"))],
		not am.is_empty() and not bm.is_empty() and int(am.get("strength", 0)) == int(bm.get("strength", 0)) + 1)
	_check("non-PSYKER unit: none", int(Det.strength_bonus(_u("U_BOYZ_B"), pv).value) == 0)
	# Attached to 10 Boyz: 11 models -> +1 +2.
	var board: Dictionary = GS.state.duplicate(true)
	board.units.U_WEIRDBOY_A["attached_to"] = "U_KOMMANDOS_A"
	board.units.U_KOMMANDOS_A["attachment_data"] = {"attached_characters": ["U_WEIRDBOY_A"]}
	GS.state.units.U_WEIRDBOY_A["attached_to"] = "U_KOMMANDOS_A"
	GS.state.units.U_KOMMANDOS_A["attachment_data"] = {"attached_characters": ["U_WEIRDBOY_A"]}
	_check("in an attached unit of 11 models: +3 S", int(Det.strength_bonus(GS.state.units.U_WEIRDBOY_A, pv, board).value) == 3, str(Det.strength_bonus(GS.state.units.U_WEIRDBOY_A, pv, board)))
	GS.state.units.U_WEIRDBOY_A.erase("attached_to")
	GS.state.units.U_KOMMANDOS_A["attachment_data"] = {"attached_characters": []}
	# Roar of Mork at the end of the Movement phase.
	_place_unit("U_WEIRDBOY_A", 20.0, 33.0)
	_check("Custodians within 12\" are Roar targets", "U_CUSTODIAN_GUARD_D" in Det.roar_of_mork_targets("U_WEIRDBOY_A"))
	_set_turn(2, 1, PHASE_MOVEMENT)
	var offers: Array = Det.window_offers(1, "movement_phase_end", {"phase": "movement"})
	_check("movement_phase_end offers ROAR OF MORK with an enemy pick", offers.size() == 1 and str(offers[0].stratagem_id) == Det.RULE_ROAR_OF_MORK
		and not offers[0].targets[0].secondary.options.is_empty())
	_check("not offered to the opponent", Det.window_offers(2, "movement_phase_end", {"phase": "movement"}).is_empty())
	var use: Dictionary = SM.use_stratagem(1, Det.RULE_ROAR_OF_MORK, "U_WEIRDBOY_A", {"secondary_id": "U_CUSTODIAN_GUARD_D", "window_id": "movement_phase_end"})
	_check("Roar of Mork: used", use.get("success", false), str(use.get("error", "")))
	_check("... the psychic level is spent", ArmyRules.psychic_levels_used(_u("U_WEIRDBOY_A")) == 1)
	_check("... the target made a battle-shock roll (Game Log)", "battle-shock roll" in str(use.get("message", "")))
	_check("a second Roar is refused (budget / once per phase)", not SM.use_stratagem(1, Det.RULE_ROAR_OF_MORK, "U_WEIRDBOY_A", {"secondary_id": "U_CUSTODIAN_GUARD_D"}).get("success", true))
	_check("a MONSTER/VEHICLE pick is refused", not Det.roar_of_mork_targets("U_WEIRDBOY_A").has("U_DEFF_DREAD_A"))
	# Visions of Violence: blocked by the spent budget this round, with feedback.
	_set_turn(2, 1, PHASE_FIGHT)
	_check("Visions not offered — Unstable Energies (budget spent)", Det.window_offers(1, Det.WINDOW_FIGHT_START, {}).is_empty())
	var gel = root.get_node_or_null("GameEventLog")
	var fed := false
	if gel and "entries" in gel:
		for e in gel.entries:
			if "Unstable Energies" in str(e.get("text", e)) and "Visions of Violence" in str(e.get("text", e)):
				fed = true
	_check("player-facing feedback names Unstable Energies + Visions of Violence", fed or gel == null)
	# Next battle round: offered; use -> Fights First until the end of the phase.
	_set_turn(3, 1, PHASE_FIGHT)
	_check("next round: fight-start window entry for the Orks", not Det.fight_start_window_entries(1).is_empty())
	offers = Det.window_offers(1, Det.WINDOW_FIGHT_START, {})
	_check("next round: VISIONS OF VIOLENCE offered", offers.size() == 1 and str(offers[0].stratagem_id) == Det.RULE_VISIONS)
	use = SM.use_stratagem(1, Det.RULE_VISIONS, "U_WEIRDBOY_A", {"window_id": Det.WINDOW_FIGHT_START})
	_check("Visions: Fights First", use.get("success", false) and bool(_flags("U_WEIRDBOY_A").get("fights_first", false)) and bool(_flags("U_WEIRDBOY_A").get(Det.F_VISIONS_FF, false)))
	var fs = load("res://scripts/rules/FightSequencer.gd").new()
	_check("the FightSequencer reads it as a Fights First unit", fs.is_fights_first(_u("U_WEIRDBOY_A")))
	Det.on_phase_end("fight")
	_check("cleared at the end of the Fight phase", not bool(_flags("U_WEIRDBOY_A").get("fights_first", false)) and not _flags("U_WEIRDBOY_A").has(Det.F_VISIONS_FF))
	# Real FightPhase entry: the start-of-phase window opens before the Pile In step.
	_reload("Wurrband")
	_place_unit("U_WEIRDBOY_A", 20.0, 33.0)
	PM.transition_to_phase(PHASE_FIGHT)
	var phase = PM.get_current_phase_instance()
	_check("FightPhase entry pauses on the Visions window", phase.has_pending_stratagem_window()
		and str(phase.get_pending_stratagem_window().get("window_id", "")) == Det.WINDOW_FIGHT_START)
	_check("... before the Pile In step started", int(phase.pile_in_step_11e) == int(phase.PileInStep11e.NOT_STARTED))
	var res: Dictionary = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": Det.WINDOW_FIGHT_START,
		"stratagem_id": Det.RULE_VISIONS, "target_unit_id": "U_WEIRDBOY_A"})
	_check("USE resumes the phase (fight sequence + Pile In begin)", res.get("success", false) and phase.sequencer_11e != null, str(res.get("error", "")))
	# AI decider: no stall.
	_reload("Wurrband")
	var ai = root.get_node("AIPlayer")
	ai.enabled = true
	ai.ai_players = {1: true, 2: false}
	PM.transition_to_phase(PHASE_FIGHT)
	phase = PM.get_current_phase_instance()
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI decider at the start of the Fight phase: no pending window", not phase.has_pending_stratagem_window() and phase.sequencer_11e != null)


func _section_rule_offer_framework() -> void:
	print("\n-- Q. rule offers in the window framework --")
	_reload("Dread Mob")
	_set_turn(2, 1, PHASE_SHOOTING)
	var all_offers: Array = SM.get_window_offers(1, "unit_selected_to_shoot", {"unit_id": "U_DEFF_DREAD_A", "phase": "shooting"})
	_check("rule offers are listed first", not all_offers.is_empty() and bool(all_offers[0].get("rule", false)))
	_check("an unknown rule id is refused", not SM.use_stratagem(1, "ork11e_rule_nope", "", {}).get("success", true))
	GS.set_edition(10)
	_check("10e: no rule offers", Det.window_offers(1, "unit_selected_to_shoot", {"unit_id": "U_DEFF_DREAD_A"}).is_empty())
	GS.set_edition(11)
	# AI with stratagems disabled by difficulty still answers rule offers.
	var dec: Dictionary = load("res://scripts/AIDecisionMaker.gd").decide_window_stratagem(1, "unit_selected_to_shoot", all_offers, {"unit_id": "U_DEFF_DREAD_A"})
	_check("AIDecisionMaker answers the rule offer first", dec.get("use", false) and str(dec.get("stratagem_id", "")) == Det.RULE_TRY_DAT_BUTTON, str(dec))
	# AI end-to-end: SELECT_SHOOTER with an AI decider -> rule used, then stratagems weighed, no stall.
	var ai = root.get_node("AIPlayer")
	ai.enabled = true
	ai.ai_players = {1: true, 2: true}
	PM.transition_to_phase(PHASE_SHOOTING)
	var phase = PM.get_current_phase_instance()
	var res: Dictionary = phase.execute_action({"type": "SELECT_SHOOTER", "actor_unit_id": "U_DEFF_DREAD_A", "player": 1})
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI: SELECT_SHOOTER completes without a pending window", res.get("success", false) and not phase.has_pending_stratagem_window(), str(res.get("error", "")))
	_check("AI: Try Dat Button! rolled", not _flags("U_DEFF_DREAD_A").get(Det.F_TDB, {}).is_empty())
	SM.on_phase_end(PHASE_SHOOTING)
