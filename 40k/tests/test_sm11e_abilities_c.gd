extends SceneTree

# WP-M4c — Codex: Space Marines (11e), generic DATASHEET + WARGEAR abilities
# of the 29 M4c datasheets (scripts/codex/space_marines/SMAbilitiesC.gd) and
# their per-model weapon resolution.
#
# One check group per ability (section numbers = the audit table's last
# column, .llm/codex_11e_wahapedia/space_marines_abilities_audit_c.md): the
# trigger / offer (in its window and not in others), the condition (on / off),
# the effect (a modifier, or an A/B resolution with the same seed), the usage
# limit and the expiry where the ability has them, and the AI decision.
# Board: the tests/saves/cus11e_c5_active shell (44x60", objectives) with its
# units replaced by P1 = armies/sm11e_codex_test.json (all 87 generic Space
# Marine datasheets) and P2 = armies/ork11e_codex_test.json, both through
# ArmyListManager.load_army_list; every unit starts off the table and a
# section places what it needs.
#
# Usage: godot --headless --path 40k --script tests/test_sm11e_abilities_c.gd

const FIXTURE := "cus11e_c5_active"
const SM_ARMY := "sm11e_codex_test"
const ORK_ARMY := "ork11e_codex_test"
const PX := 40.0
const P_FORM := 0
const P_CMD := 6
const P_MOV := 7
const P_SHOOT := 8
const P_CHG := 9
const P_FIGHT := 10

var passed := 0
var failed := 0
var GS = null
var SM = null
var RE = null
var PM = null
var C = null
var SWC = null
var EP = null
var UAM = null
var MM = null
var _sm_army: Dictionary = {}
var _ork_army: Dictionary = {}


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
# board helpers (the WP-S4 test's)
# ---------------------------------------------------------------------------

func _stage_fixture() -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + FIXTURE + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + FIXTURE + ext))
	return slm.load_game(FIXTURE)


func _reset_unit(u: Dictionary) -> void:
	u["flags"] = {}
	u["status"] = 0
	u.erase("attached_to")
	u.erase("embarked_in")
	u["attachment_data"] = {"attached_characters": []}
	for m in u.get("models", []):
		m["alive"] = true
		m["position"] = null
		m["current_wounds"] = int(m.get("wounds", 1))


func _fresh(phase: int = P_SHOOT, active: int = 1, battle_round: int = 2) -> void:
	_stage_fixture()
	GameConstants.edition = 11
	RE.set_test_seed(-1)
	GS.state.units = {}
	for pair in [[_sm_army, 1], [_ork_army, 2]]:
		var army: Dictionary = pair[0]
		for k in army.get("units", {}):
			var u: Dictionary = army.units[k].duplicate(true)
			u["id"] = k
			u["owner"] = int(pair[1])
			_reset_unit(u)
			GS.state.units[k] = u
	GS.state.factions["1"] = _sm_army.get("faction", {}).duplicate(true)
	GS.state.factions["2"] = _ork_army.get("faction", {}).duplicate(true)
	GS.state.factions["1"].erase("sw11e_doctrine")
	SM.load_faction_stratagems_for_player(1)
	SM.load_faction_stratagems_for_player(2)
	GS.state.meta["phase"] = phase
	GS.state.meta["active_player"] = active
	GS.state.meta["battle_round"] = battle_round
	for p in ["1", "2"]:
		GS.state.players[p]["cp"] = 6
		GS.state.players[p].erase(C.ARMY_USES)
	SM._usage_history = {"1": [], "2": []}
	UAM.reset_for_new_game()
	C.offers_suppressed = false


func _u(uid: String) -> Dictionary:
	return GS.state.units.get(uid, {})


func _flags(uid: String) -> Dictionary:
	var u := _u(uid)
	if not u.has("flags"):
		u["flags"] = {}
	return u.flags


func _place(uid: String, x: float, y: float) -> void:
	var u: Dictionary = GS.state.units[uid]
	u["status"] = 2
	u.erase("embarked_in")
	var cx := x
	for m in u.get("models", []):
		var r_in := float(m.get("base_mm", 32)) / 25.4
		m["position"] = {"x": (cx + r_in / 2.0) * PX, "y": y * PX}
		cx += r_in + 0.2


func _attach(char_id: String, bodyguard_id: String) -> void:
	var ad: Dictionary = GS.state.units[bodyguard_id].get("attachment_data", {"attached_characters": []})
	var arr: Array = ad.get("attached_characters", [])
	if not char_id in arr:
		arr.append(char_id)
	GS.state.units[bodyguard_id]["attachment_data"] = {"attached_characters": arr}
	GS.state.units[char_id]["attached_to"] = bodyguard_id


func _phase(p: int, active: int = 1) -> void:
	GS.state.meta["phase"] = p
	GS.state.meta["active_player"] = active


func _sid(slug: String) -> String:
	return C.sid_of(slug)


func _offer(player: int, window_id: String, ctx: Dictionary, slug: String) -> Dictionary:
	var c := ctx.duplicate(true)
	c["window_id"] = window_id
	for o in C.window_offers(player, window_id, c):
		if str(o.get("stratagem_id", "")) == _sid(slug):
			return o
	return {}


func _offer_units(o: Dictionary) -> Array:
	return o.get("targets", []).map(func(t): return str(t.get("unit_id", "")))


func _target(o: Dictionary, uid: String) -> Dictionary:
	for t in o.get("targets", []):
		if str(t.get("unit_id", "")) == uid:
			return t
	return {}


func _secondary_ids(o: Dictionary, uid: String) -> Array:
	return _target(o, uid).get("secondary", {}).get("options", []).map(func(x): return str(x.get("id", "")))


func _use(player: int, slug: String, uid: String, window_id: String, ctx: Dictionary = {}, secondary: String = "", variant: String = "") -> Dictionary:
	var c := ctx.duplicate(true)
	c["window_id"] = window_id
	if secondary != "":
		c["secondary_id"] = secondary
	if variant != "":
		c["variant_id"] = variant
	return SM.use_stratagem(player, _sid(slug), uid, c)


func _mods(actor: String, target: String, melee: bool, wname: String = "", kws: Array = []) -> Dictionary:
	var prof := {"name": wname, "type": "Melee" if melee else "Ranged", "range": 0 if melee else 24, "keywords": kws}
	return RE.ork11e_ab_mods(_u(actor), _u(target), prof, melee, GS.state)


func _names(m: Dictionary) -> Array:
	return m.get("sources", []).map(func(x): return str(x.get("name", "")))


func _alive(uid: String) -> int:
	var n := 0
	for m in _u(uid).get("models", []):
		if m.get("alive", true):
			n += 1
	return n


func _wounds_left(uid: String) -> int:
	var n := 0
	for m in _u(uid).get("models", []):
		if m.get("alive", true):
			n += int(m.get("current_wounds", m.get("wounds", 1)))
	return n


func _weapon(uid: String, name_part: String, melee: bool) -> String:
	var ws: Dictionary = RE.get_unit_melee_weapons(uid, GS.state) if melee else RE.get_unit_weapons(uid, GS.state)
	for mid in ws:
		for wid in ws[mid]:
			if not melee and str(wid).ends_with("_melee"):
				continue
			var prof: Dictionary = RE.get_weapon_profile(str(wid), GS.state)
			if str(prof.get("name", "")).to_lower().contains(name_part.to_lower()):
				return str(wid)
	return ""


func _melee(uid: String, wid: String, target: String, seed: int) -> Dictionary:
	var act := {"type": "FIGHT", "actor_unit_id": uid, "payload": {"assignments": [{"attacker": uid, "target": target, "weapon": wid}]}}
	RE.set_test_seed(seed)
	var res = RE.resolve_melee_attacks(act, GS.state.duplicate(true), RE.RNGService.new(seed))
	var out := {"hits": 0, "bonus": 0, "attacks": 0, "wounds": 0, "res": res}
	for d in res.get("dice", []):
		var c := str(d.get("context", ""))
		if c == "hit_roll_melee":
			out.hits += int(d.get("successes", 0))
			out.bonus += int(d.get("sustained_bonus_hits", 0))
			out.attacks += int(d.get("total_attacks", 0))
		elif c == "wound_roll_melee":
			out.wounds += int(d.get("successes", 0))
	return out


func _assign(board: Dictionary, uid: String, wid: String, tid: String) -> Dictionary:
	var model_ids: Array = []
	var w = RE.get_unit_weapons(uid, board)
	for mid in w:
		if wid in w[mid]:
			model_ids.append(str(mid))
	return {"weapon_id": wid, "target_unit_id": tid, "model_ids": model_ids}


func _shoot(board: Dictionary, uid: String, wid: String, tid: String, seed: int) -> Dictionary:
	RE.set_test_seed(seed)
	var res = RE.resolve_shoot({"type": "SHOOT", "actor_unit_id": uid, "payload": {"assignments": [_assign(board, uid, wid, tid)]}}, board, RE.RNGService.new(seed))
	var out := {"hits": 0, "wounds": 0, "attacks": 0, "res": res}
	for d in res.get("dice", []):
		var c := str(d.get("context", ""))
		if c in ["to_hit", "hit_roll"]:
			out.hits += int(d.get("successes", 0))
			out.attacks += int(d.get("total_attacks", d.get("rolls_raw", []).size()))
		elif c == "to_wound":
			out.wounds += int(d.get("successes", 0))
	return out


func _formations_phase():
	GS.state.meta["formations_p1_confirmed"] = false
	GS.state.meta["formations_p2_confirmed"] = false
	var fp = load("res://phases/FormationsPhase.gd").new()
	fp.players_confirmed = {1: false, 2: false}
	fp.current_declaring_player = 1
	fp.player_formations = {1: {"leader_attachments": {}, "transport_embarkations": {}, "reserves": []}, 2: {"leader_attachments": {}, "transport_embarkations": {}, "reserves": []}}
	root.add_child(fp)
	return fp


func _obj_pos(i: int = 0) -> Vector2:
	var objs: Array = SWC.objectives()
	var op = objs[i].get("position", {})
	return Vector2(float(op.x if op is Vector2 else op.get("x", 0)) / PX, float(op.y if op is Vector2 else op.get("y", 0)) / PX)


# ---------------------------------------------------------------------------
func _run() -> void:
	GS = root.get_node("GameState")
	SM = root.get_node("StratagemManager")
	RE = root.get_node("RulesEngine")
	PM = root.get_node("PhaseManager")
	UAM = root.get_node("UnitAbilityManager")
	MM = root.get_node("MissionManager")
	C = load("res://scripts/codex/space_marines/SMAbilitiesC.gd")
	SWC = load("res://scripts/codex/space_wolves/SWCommon.gd")
	EP = load("res://autoloads/EffectPrimitives.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	root.get_node("SettingsService").set("auto_allocate_wounds", true)
	GameConstants.edition = 11
	var alm = root.get_node("ArmyListManager")
	_sm_army = alm.load_army_list(SM_ARMY, 1)
	_ork_army = alm.load_army_list(ORK_ARMY, 2)
	print("\n=== test_sm11e_abilities_c (WP-M4c) ===")
	if _sm_army.is_empty() or _ork_army.is_empty():
		_check("armies load", false)
		return
	_section_names()
	_section_loadouts()
	_section_attack_mods()
	_section_defence()
	_section_strategic_acumen()
	_section_narthecium()
	_section_master_of_shadows()
	_section_seeker()
	_section_forgefather()
	_section_overlapping()
	_section_master_tactician_codex_adept()
	_section_cold()
	_section_purgation_run()
	_section_titus()
	_section_banner()
	_section_hammer_of_wrath()
	_section_knight_champion()
	_section_glory()
	_section_echo()
	_section_combat_embarkation()
	_section_reivers()
	_section_formations()
	_section_suboden()
	_section_cato_aethon_rhino()
	_section_kaius_judiciar_kayvaan()
	_section_aquilon_total_obliteration()
	_section_banner_objectives()
	_section_strategium()
	_section_gating()
	_section_ai()


# ---------------------------------------------------------------------------
# 0. every Datasheet / Wargear ability of the 29 datasheets has a module slug;
#    the core abilities on them resolve through the engine
# ---------------------------------------------------------------------------
func _section_names() -> void:
	print("\n-- 0. names + core abilities --")
	_fresh()
	var skip := ["combat doctrines", "transhuman strategist", "leader", "deep strike", "lone operative", "stealth",
		"support", "fights first", "transport", "firing deck 2"]
	var known := {}
	for slug in C.ABILITIES:
		known[str(C.ABILITIES[slug][0])] = slug
	var unknown: Array = []
	var sheets := {}
	for uid in _sm_army.units:
		var u: Dictionary = _sm_army.units[uid]
		if not C.is_m4c_sheet(u):
			continue
		sheets[C.sheet_of(u)] = true
		for ab in u.get("meta", {}).get("abilities", []):
			var n: String = C.fold(str(ab.get("name", "")) if ab is Dictionary else str(ab))
			if n in skip or n.begins_with("feel no pain") or n.begins_with("deadly demise") or n.begins_with("scouts") or n.begins_with("damaged"):
				continue
			if not known.has(n) and not n in unknown:
				unknown.append(n)
	_check("all 29 M4c datasheets are in the test army", sheets.size() == 29, str(sheets.size()))
	_check("every M4c datasheet/wargear ability has a module slug", unknown.is_empty(), str(unknown))
	for n in ["Into the Fray", "Aquilon Optics", "Combat Embarkation", "Righteous Fury", "Total Obliteration"]:
		_check("ABILITY_EFFECTS row '%s' (implemented)" % n, UAM.is_ability_implemented(n))
	_check("core: Kayvaan Shrike has Deep Strike", GS.unit_has_deep_strike("U_KAYVAAN_SHRIKE_A"))
	_check("core: Land Speeder has Deep Strike", GS.unit_has_deep_strike("U_LAND_SPEEDER_A"))
	_check("core: Assault Intercessors with Jump Packs have Deep Strike", GS.unit_has_deep_strike("U_ASSAULT_INTERCESSORS_WITH_JUMP_PACKS_A"))
	_check("core: Vulkan He'stan Feel No Pain 6+", RE.get_unit_fnp(_u("U_VULKAN_HE_STAN_A")) == 6, str(RE.get_unit_fnp(_u("U_VULKAN_HE_STAN_A"))))
	_check("core: Caanok Var / Captain Titus Feel No Pain 5+", RE.get_unit_fnp(_u("U_CAANOK_VAR_A")) == 5 and RE.get_unit_fnp(_u("U_CAPTAIN_TITUS_A")) == 5)
	_check("core: Reiver Squad Scouts 6\"", GS.get_scout_distance("U_REIVER_SQUAD_A") == 6.0, str(GS.get_scout_distance("U_REIVER_SQUAD_A")))
	_check("core: Aethon Shaan has Stealth and Lone Operative", RE.has_stealth_ability(_u("U_AETHON_SHAAN_A")) and RE.has_lone_operative(_u("U_AETHON_SHAAN_A")))
	var cam = root.get_node("CharacterAttachmentManager")
	_check("core: Judiciar / Apothecary / Ancient / Kaius attach as Support", cam.attachment_role(_u("U_JUDICIAR_A")) == "support" and cam.attachment_role(_u("U_APOTHECARY_A")) == "support" \
		and cam.attachment_role(_u("U_ANCIENT_A")) == "support" and cam.attachment_role(_u("U_KAIUS_KONORIUS_A")) == "support")
	_check("core: Captain on Bike can lead an Outrider Squad", "U_OUTRIDER_SQUAD_A" in GS.get_eligible_bodyguards_for_character("U_CAPTAIN_ON_BIKE_A"),
		str(GS.get_eligible_bodyguards_for_character("U_CAPTAIN_ON_BIKE_A")))
	_check("core: the Rhino is a TRANSPORT with Firing Deck 2", SWC.has_keyword(_u("U_RHINO_A"), "TRANSPORT") and SWC.has_ability(_u("U_RHINO_A"), "Firing Deck 2"))


# ---------------------------------------------------------------------------
# 1. per-model weapons (default kit and each wargear option)
# ---------------------------------------------------------------------------
func _per_model(uid: String, weapon_type: String, wargear: Array = []) -> Array:
	var u: Dictionary = _sm_army.units[uid].duplicate(true)
	if not wargear.is_empty():
		u.meta["wargear"] = wargear
	RE._ensure_loadout_resolved(u)
	var out: Array = []
	for m in u.get("models", []):
		var names: Array = []
		for wid in RE._get_model_weapon_ids(u, m, weapon_type):
			var n := str(wid).trim_suffix("_ranged").trim_suffix("_melee")
			var cut := n.find("___")
			if cut > 0:
				n = n.substr(0, cut)
			n = n.replace("_", " ")
			if not n in names:
				names.append(n)
		names.sort()
		out.append(names)
	return out


func _section_loadouts() -> void:
	print("\n-- 1. per-model weapons --")
	var cases := [
		["U_CAPTAIN_ON_BIKE_A", [], "Ranged", [["heavy bolt pistol", "twin bolt rifle"]]],
		["U_CAPTAIN_ON_BIKE_A", [], "Melee", [["master crafted power weapon"]]],
		["U_CAPTAIN_ON_BIKE_A", ["1x Plasma Pistol", "1x Thunder Hammer", "1x Twin Bolt Rifle"], "Ranged", [["plasma pistol", "twin bolt rifle"]]],
		["U_CAPTAIN_ON_BIKE_A", ["1x Plasma Pistol", "1x Thunder Hammer", "1x Twin Bolt Rifle"], "Melee", [["thunder hammer"]]],
		["U_LAND_SPEEDER_A", [], "Ranged", [["multi melta", "onslaught gatling cannon", "stormfury missile launcher"]]],
		["U_LAND_SPEEDER_A", ["1x Multi-melta", "1x Pyrecannon", "1x Stormfury Missile Launcher"], "Ranged", [["multi melta", "pyrecannon", "stormfury missile launcher"]]],
		["U_REDEMPTOR_DREADNOUGHT_A", [], "Ranged", [["fragstorm grenade launchers", "heavy flamer", "heavy onslaught gatling cannon"]]],
		["U_REDEMPTOR_DREADNOUGHT_A", ["1x Icarus Rocket Pod", "1x Storm Bolters", "1x Onslaught Gatling Cannon", "1x Macro Plasma Incinerator"], "Ranged",
			[["icarus rocket pod", "macro plasma incinerator", "onslaught gatling cannon", "storm bolters"]]],
		["U_REPULSOR_A", [], "Ranged", [["defensive array", "heavy onslaught gatling cannon", "hunter slayer missile", "twin heavy bolter"]]],
		["U_REPULSOR_A", ["1x Las-talon", "1x Twin Lascannon", "1x Hunter-slayer Missile", "1x Defensive Array"], "Ranged", [["defensive array", "hunter slayer missile", "las talon", "twin lascannon"]]],
		["U_REPULSOR_EXECUTIONER_A", [], "Ranged", [["defensive array", "heavy laser destroyer", "heavy onslaught gatling cannon", "twin heavy bolter"]]],
		["U_REPULSOR_EXECUTIONER_A", ["1x Macro Plasma Incinerator", "1x Heavy Onslaught Gatling Cannon", "1x Twin Heavy Bolter", "1x Defensive Array"], "Ranged",
			[["defensive array", "heavy onslaught gatling cannon", "macro plasma incinerator", "twin heavy bolter"]]],
		["U_RHINO_A", [], "Ranged", [["storm bolter"]]],
		["U_RHINO_A", ["1x Hunter-killer Missile", "1x Storm Bolter"], "Ranged", [["hunter killer missile", "storm bolter"]]],
		["U_ANCIENT_A", [], "Melee", [["ceramite fists"]]],
		["U_ANCIENT_A", ["1x Power Weapon", "1x Bolt Pistol"], "Ranged", [["bolt pistol"]]],
		["U_ANCIENT_A", ["1x Power Weapon", "1x Bolt Pistol"], "Melee", [["power weapon"]]],
		["U_INVADER_ATVS_A", [], "Ranged", [["bolt pistol", "onslaught gatling cannon", "twin bolt rifle"]]],
		["U_INVADER_ATVS_A", ["1x Multi-melta", "1x Bolt Pistol", "1x Twin Bolt Rifle"], "Ranged", [["bolt pistol", "multi melta", "twin bolt rifle"]]],
		["U_COMPANY_HEROES_A", [], "Ranged", [["master crafted bolt pistol", "master crafted bolt rifle"], ["master crafted bolt pistol"],
			["master crafted bolt pistol", "master crafted bolt rifle"], ["master crafted bolt pistol", "master crafted heavy bolter"]]],
		["U_COMPANY_HEROES_A", [], "Melee", [["combat knife"], ["master crafted power weapon"], ["combat knife"], ["combat knife"]]],
		["U_WARDENS_OF_ULTRAMAR_A", [], "Ranged", [["archeotech laspistol"], ["bolt rifle"], ["astropathic blast"], ["archeotech laspistol"], ["archeotech laspistol"], ["heavy bolt pistol"]]],
		["U_WARDENS_OF_ULTRAMAR_A", [], "Melee", [["power weapon"], ["ceramite fists"], ["force stave"], ["power weapon"], ["ultramarian combat weapons"], ["master crafted power weapon"]]],
		["U_REIVER_SQUAD_A", [], "Ranged", [["bolt carbine", "special issue bolt pistol"], ["bolt carbine", "special issue bolt pistol"], ["bolt carbine", "special issue bolt pistol"],
			["bolt carbine", "special issue bolt pistol"], ["bolt carbine", "special issue bolt pistol"]]],
		["U_REIVER_SQUAD_A", [], "Melee", [["monomolecular combat knife"], ["monomolecular combat knife"], ["monomolecular combat knife"], ["monomolecular combat knife"], ["monomolecular combat knife"]]],
		["U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A", [], "Ranged", [["bolt pistol", "heavy bolter"], ["bolt pistol", "heavy bolter"], ["bolt pistol", "heavy bolter"]]],
		["U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A", ["1x Multi-melta", "2x Melta Rifle", "3x Bolt Pistol"], "Ranged",
			[["bolt pistol", "melta rifle"], ["bolt pistol", "multi melta"], ["bolt pistol", "melta rifle"]]],
		["U_OUTRIDER_SQUAD_A", ["1x Thunder Hammer", "2x Chainsword", "1x Plasma Pistol", "2x Heavy Bolt Pistol", "3x Twin Bolt Rifle"], "Melee",
			[["thunder hammer"], ["chainsword"], ["chainsword"]]],
		["U_OUTRIDER_SQUAD_A", ["1x Thunder Hammer", "2x Chainsword", "1x Plasma Pistol", "2x Heavy Bolt Pistol", "3x Twin Bolt Rifle"], "Ranged",
			# Integration (RULINGS WP-M4b): a swap any model can take goes to the rank-and-file before the Sergeant.
			[["heavy bolt pistol", "twin bolt rifle"], ["plasma pistol", "twin bolt rifle"], ["heavy bolt pistol", "twin bolt rifle"]]],
		["U_ASSAULT_INTERCESSORS_WITH_JUMP_PACKS_A", ["1x Plasma Pistol", "4x Heavy Bolt Pistol", "1x Power Fist", "4x Chainsword"], "Melee",
			[["power fist"], ["chainsword"], ["chainsword"], ["chainsword"], ["chainsword"]]],
	]
	for c in cases:
		var got := _per_model(str(c[0]), str(c[2]), c[1])
		_check("%s %s %s" % [str(c[0]).trim_prefix("U_").trim_suffix("_A").to_lower(), str(c[2]), "default kit" if (c[1] as Array).is_empty() else str(c[1])], got == c[3], str(got))


# ---------------------------------------------------------------------------
# 2. passive attack modifiers (aggregator) + A/B resolutions
# ---------------------------------------------------------------------------
func _section_attack_mods() -> void:
	print("\n-- 2. Trophy Taker, For the Khan!, Full-throttle Assault, Executioner, Aggressive Reconnaissance, Press the Attack, Calgar's Champion, Into the Fray --")
	_fresh(P_FIGHT)
	_place("U_KOR_SARRO_KHAN_A", 10, 30)
	_place("U_WARBOSS_A", 10, 31.3)
	_place("U_BOYZ_B", 20, 31.3)
	var tt := _mods("U_KOR_SARRO_KHAN_A", "U_WARBOSS_A", true)
	_check("Trophy Taker: vs a CHARACTER unit re-roll hit 1s and wound 1s", tt.hit_reroll == "ones" and tt.wound_reroll == "ones" and "Trophy Taker" in _names(tt), str(tt))
	var tt2 := _mods("U_KOR_SARRO_KHAN_A", "U_BOYZ_B", true)
	_check("Trophy Taker: not vs a non-CHARACTER unit", not "Trophy Taker" in _names(tt2))
	_check("For the Khan!: melee [LANCE] only after a charge move", not tt2.wound_plus)
	_flags("U_KOR_SARRO_KHAN_A")["charged_this_turn"] = true
	_check("For the Khan!: charged -> melee +1 to wound ([LANCE])", bool(_mods("U_KOR_SARRO_KHAN_A", "U_BOYZ_B", true).wound_plus))
	_check("For the Khan!: [LANCE] is melee only", not bool(_mods("U_KOR_SARRO_KHAN_A", "U_BOYZ_B", false).wound_plus))
	_check("For the Khan!: ranged [ASSAULT] (advance and shoot)", EP.has_effect_advance_and_shoot(_u("U_KOR_SARRO_KHAN_A")))
	_check("no [ASSAULT] for a Captain (not this ability)", not EP.has_effect_advance_and_shoot(_u("U_CAPTAIN_A")))
	# Full-throttle Assault
	_place("U_OUTRIDER_SQUAD_A", 20, 30)
	var ft0 := _mods("U_OUTRIDER_SQUAD_A", "U_BOYZ_B", true, "Chainsword")
	_check("Full-throttle Assault: nothing without a charge", not "Full-throttle Assault" in _names(ft0))
	_flags("U_OUTRIDER_SQUAD_A")["charged_this_turn"] = true
	var ft1 := _mods("U_OUTRIDER_SQUAD_A", "U_BOYZ_B", true, "Chainsword")
	_check("Full-throttle Assault: charged, other melee +1 D and [SUSTAINED HITS 1]", int(ft1.damage) == 1 and int(ft1.sustained) == 1 and not ft1.hit_plus, str(ft1))
	var ft2 := _mods("U_OUTRIDER_SQUAD_A", "U_BOYZ_B", true, "Thunder Hammer")
	_check("Full-throttle Assault: Thunder Hammer +1 to hit and [SUSTAINED HITS 1] (no +1 D)", ft2.hit_plus and int(ft2.sustained) == 1 and int(ft2.damage) == 0, str(ft2))
	var wid := _weapon("U_OUTRIDER_SQUAD_A", "chainsword", true)
	var with_ft := _melee("U_OUTRIDER_SQUAD_A", wid, "U_BOYZ_B", 4242)
	_flags("U_OUTRIDER_SQUAD_A").erase("charged_this_turn")
	var without := _melee("U_OUTRIDER_SQUAD_A", wid, "U_BOYZ_B", 4242)
	_check("Full-throttle Assault A/B (seed 4242): same hit rolls with and without the charge (+1 D / [SUSTAINED HITS 1] only)", int(with_ft.hits) == int(without.hits) and int(with_ft.bonus) >= int(without.bonus),
		"%s/%s vs %s/%s" % [with_ft.hits, with_ft.bonus, without.hits, without.bonus])
	var sust_seen := false
	for sd in range(1, 40):
		_flags("U_OUTRIDER_SQUAD_A")["charged_this_turn"] = true
		var a := _melee("U_OUTRIDER_SQUAD_A", wid, "U_BOYZ_B", sd)
		if int(a.bonus) > 0:
			sust_seen = true
			break
	_check("Full-throttle Assault: [SUSTAINED HITS 1] produces bonus hits in the resolver", sust_seen)
	# Thunder Hammer +1 to hit A/B: the Captain on Bike (hammer option) leading the Outriders.
	_u("U_CAPTAIN_ON_BIKE_A").meta["wargear"] = ["1x Plasma Pistol", "1x Thunder Hammer", "1x Twin Bolt Rifle"]
	_u("U_CAPTAIN_ON_BIKE_A").models[0].erase("melee_loadout")
	_u("U_CAPTAIN_ON_BIKE_A").erase("_loadout_version")
	_place("U_CAPTAIN_ON_BIKE_A", 24, 30)
	_place("U_BOYZ_B", 20, 31.3)
	_attach("U_CAPTAIN_ON_BIKE_A", "U_OUTRIDER_SQUAD_A")
	var th := _weapon("U_CAPTAIN_ON_BIKE_A", "thunder hammer", true)
	var more_hits := 0
	var fewer_hits := 0
	for sd in range(100, 140):
		_flags("U_OUTRIDER_SQUAD_A")["charged_this_turn"] = true
		var h1 := _melee("U_CAPTAIN_ON_BIKE_A", th, "U_BOYZ_B", sd)
		_flags("U_OUTRIDER_SQUAD_A").erase("charged_this_turn")
		var h0 := _melee("U_CAPTAIN_ON_BIKE_A", th, "U_BOYZ_B", sd)
		if int(h1.hits) > int(h0.hits):
			more_hits += 1
		elif int(h1.hits) < int(h0.hits):
			fewer_hits += 1
	_check("Full-throttle Assault A/B (40 seeds): the attached Captain's Thunder Hammer +1 to hit after the charge (more hits on %d seeds, fewer on %d)" % [more_hits, fewer_hits], more_hits > 0 and fewer_hits == 0, th)
	_u("U_OUTRIDER_SQUAD_A")["attachment_data"] = {"attached_characters": []}
	_u("U_CAPTAIN_ON_BIKE_A").erase("attached_to")
	# Executioner
	_phase(P_SHOOT)
	_place("U_REPULSOR_EXECUTIONER_A", 30, 20)
	var ex := _mods("U_REPULSOR_EXECUTIONER_A", "U_BOYZ_B", false)
	_check("Executioner: vs a unit not below half-strength +1 to hit", ex.hit_plus and "Executioner" in _names(ex), str(ex))
	var boyz: Array = _u("U_BOYZ_B").models
	for i in range(boyz.size()):
		if i < int(ceil(boyz.size() / 2.0)) + 1:
			boyz[i]["alive"] = false
	_check("Executioner: not vs a unit below half-strength", not "Executioner" in _names(_mods("U_REPULSOR_EXECUTIONER_A", "U_BOYZ_B", false)))
	_check("Executioner: ranged only", not "Executioner" in _names(_mods("U_REPULSOR_EXECUTIONER_A", "U_WARBOSS_A", true)))
	for m in boyz:
		m["alive"] = true
	# Aggressive Reconnaissance
	_place("U_INVADER_ATVS_A", 30, 40)
	_place("U_DEFF_DREAD_A", 36, 50)
	_place("U_BOYZ_B", 2, 50)
	_place("U_WARBOSS_A", 2, 52)
	var ar := _mods("U_INVADER_ATVS_A", "U_DEFF_DREAD_A", false)
	_check("Aggressive Reconnaissance: your Shooting phase, target > 6\" from other enemies -> +1 to wound", ar.wound_plus and "Aggressive Reconnaissance" in _names(ar), str(ar))
	_check("Aggressive Reconnaissance: not vs a unit within 6\" of another enemy", not _mods("U_INVADER_ATVS_A", "U_BOYZ_B", false).wound_plus)
	_phase(P_SHOOT, 2)
	_check("Aggressive Reconnaissance: not in the opponent's Shooting phase", not _mods("U_INVADER_ATVS_A", "U_DEFF_DREAD_A", false).wound_plus)
	_phase(P_FIGHT)
	# Press the Attack
	_place("U_CAPTAIN_TITUS_A", 2, 49)
	var pa := _mods("U_CAPTAIN_TITUS_A", "U_BOYZ_B", true)
	_check("Press the Attack: melee [SUSTAINED HITS 1] vs a non-MONSTER/VEHICLE unit", int(pa.sustained) == 1 and "Press the Attack" in _names(pa), str(pa))
	_check("Press the Attack: not vs a VEHICLE", int(_mods("U_CAPTAIN_TITUS_A", "U_DEFF_DREAD_A", true).sustained) == 0)
	_flags("U_CAPTAIN_TITUS_A")["sw11e_doctrine"] = "assault"
	_check("Press the Attack: assault doctrine active -> [SUSTAINED HITS 1] vs a VEHICLE too", int(_mods("U_CAPTAIN_TITUS_A", "U_DEFF_DREAD_A", true).sustained) == 1)
	_flags("U_CAPTAIN_TITUS_A").erase("sw11e_doctrine")
	_check("Press the Attack: ranged attacks unaffected", int(_mods("U_CAPTAIN_TITUS_A", "U_BOYZ_B", false).sustained) == 0)
	# Calgar's Champion: this model only
	_place("U_KAIUS_KONORIUS_A", 3, 49)
	_place("U_MARNEUS_CALGAR_A", 4.5, 49)
	var cc := _mods("U_KAIUS_KONORIUS_A", "U_WARBOSS_A", true)
	_check("Calgar's Champion: Kaius vs a CHARACTER re-roll hit 1s and wound 1s", cc.hit_reroll == "ones" and cc.wound_reroll == "ones", str(cc))
	_attach("U_KAIUS_KONORIUS_A", "U_VICTRIX_HONOUR_GUARD_A")
	_place("U_VICTRIX_HONOUR_GUARD_A", 5, 47)
	_check("Calgar's Champion: 'this model' — not the bodyguard's attacks", not "Calgar's Champion" in _names(_mods("U_VICTRIX_HONOUR_GUARD_A", "U_WARBOSS_A", true)))
	# Into the Fray: [CLEAVE 1] after a charge (the whole Attached unit)
	_attach("U_CAPTAIN_ON_BIKE_A", "U_OUTRIDER_SQUAD_A")
	_flags("U_OUTRIDER_SQUAD_A").erase("charged_this_turn")
	_check("Into the Fray: no [CLEAVE] without a charge", C.melee_cleave(_u("U_OUTRIDER_SQUAD_A")) == 0)
	_flags("U_OUTRIDER_SQUAD_A")["charged_this_turn"] = true
	_check("Into the Fray: charged -> the Attached unit's melee [CLEAVE 1]", C.melee_cleave(_u("U_OUTRIDER_SQUAD_A")) == 1 and C.melee_cleave(_u("U_CAPTAIN_ON_BIKE_A")) == 1)
	var b10 := _melee("U_OUTRIDER_SQUAD_A", wid, "U_BOYZ_B", 77)
	_flags("U_OUTRIDER_SQUAD_A").erase("charged_this_turn")
	_u("U_OUTRIDER_SQUAD_A")["attachment_data"] = {"attached_characters": []}
	_u("U_CAPTAIN_ON_BIKE_A").erase("attached_to")
	var b0 := _melee("U_OUTRIDER_SQUAD_A", wid, "U_BOYZ_B", 77)
	_check("Into the Fray A/B (seed 77): +%d attack dice vs a %d-model target with [CLEAVE 1]" % [int(b10.attacks) - int(b0.attacks), _alive("U_BOYZ_B")],
		int(b10.attacks) - int(b0.attacks) == int(_alive("U_BOYZ_B") / 5), "%s vs %s" % [b10.attacks, b0.attacks])


# ---------------------------------------------------------------------------
# 3. Duty Eternal, Command Squad, Honour Guard of Macragge, Veteran Bodyguard
# ---------------------------------------------------------------------------
func _section_defence() -> void:
	print("\n-- 3. Duty Eternal, Command Squad, Honour Guard of Macragge --")
	_fresh(P_SHOOT, 2)
	_check("Duty Eternal: S > T -> -1 to wound", RE.ork11e_ab_wound_penalty(_u("U_REDEMPTOR_DREADNOUGHT_A"), 12, 10) and RE.ork11e_ab_wound_penalty_name(_u("U_REDEMPTOR_DREADNOUGHT_A"), 12, 10) == "Duty Eternal")
	_check("Duty Eternal: S = T no penalty", not RE.ork11e_ab_wound_penalty(_u("U_REDEMPTOR_DREADNOUGHT_A"), 10, 10))
	_check("Command Squad: attacks that target Company Heroes -1 to wound", EP.has_effect_minus_one_wound_defense(_u("U_COMPANY_HEROES_A")))
	_check("Honour Guard of Macragge: attacks that target Victrix -1 to wound", EP.has_effect_minus_one_wound_defense(_u("U_VICTRIX_HONOUR_GUARD_A")))
	_attach("U_CAPTAIN_A", "U_COMPANY_HEROES_A")
	_check("Command Squad: the whole Attached unit (the Captain too)", EP.has_effect_minus_one_wound_defense(_u("U_CAPTAIN_A")))
	_check("not on an Intercessor Squad", not EP.has_effect_minus_one_wound_defense(_u("U_INTERCESSOR_SQUAD_A")))
	# A/B: Ork shooting at Victrix wounds less often.
	_place("U_VICTRIX_HONOUR_GUARD_A", 20, 20)
	_place("U_INTERCESSOR_SQUAD_A", 26, 20)
	_place("U_BOYZ_B", 20, 28)
	var bw := _weapon("U_BOYZ_B", "slugga", false)
	var vw := 0
	var iw := 0
	for sd in range(1, 25):
		vw += int(_shoot(GS.state.duplicate(true), "U_BOYZ_B", bw, "U_VICTRIX_HONOUR_GUARD_A", sd).wounds)
		iw += int(_shoot(GS.state.duplicate(true), "U_BOYZ_B", bw, "U_INTERCESSOR_SQUAD_A", sd).wounds)
	_check("Honour Guard of Macragge A/B (24 seeds, same T): fewer wounds vs Victrix (%d) than vs Intercessors (%d)" % [vw, iw], vw < iw)
	# Veteran Bodyguard
	_fresh(P_FIGHT)
	_place("U_VICTRIX_HONOUR_GUARD_A", 10, 10)
	_place("U_KAIUS_KONORIUS_A", 10, 11.5)
	_place("U_MARNEUS_CALGAR_A", 12, 11.5)
	_check("Veteran Bodyguard: Kaius not attached -> Calgar has no FNP", RE.get_unit_fnp(_u("U_MARNEUS_CALGAR_A")) == 0, str(RE.get_unit_fnp(_u("U_MARNEUS_CALGAR_A"))))
	_attach("U_KAIUS_KONORIUS_A", "U_VICTRIX_HONOUR_GUARD_A")
	_attach("U_MARNEUS_CALGAR_A", "U_VICTRIX_HONOUR_GUARD_A")
	_check("Veteran Bodyguard: attached -> the other CHARACTER (Calgar) has Feel No Pain 4+", RE.get_unit_fnp(_u("U_MARNEUS_CALGAR_A")) == 4, str(RE.get_unit_fnp(_u("U_MARNEUS_CALGAR_A"))))
	_check("Veteran Bodyguard: not Kaius himself, not the bodyguard (not CHARACTER models)", RE.get_unit_fnp(_u("U_KAIUS_KONORIUS_A")) == 0 and RE.get_unit_fnp(_u("U_VICTRIX_HONOUR_GUARD_A")) == 0)


# ---------------------------------------------------------------------------
# 4. Strategic Acumen (Captain on Bike)
# ---------------------------------------------------------------------------
func _section_strategic_acumen() -> void:
	print("\n-- 4. Strategic Acumen --")
	_fresh(P_CMD)
	_place("U_CAPTAIN_ON_BIKE_A", 10, 40)
	_place("U_CAPTAIN_A", 20, 40)
	var o := _offer(1, "phase_start", {"phase": "command"}, "strategic_acumen")
	_check("offered at the start of your Command phase", _offer_units(o) == ["U_CAPTAIN_ON_BIKE_A"], str(_offer_units(o)))
	_check("scoped to the M4c datasheet (the Captain's copy is another package's)", not "U_CAPTAIN_A" in _offer_units(o))
	var t := _target(o, "U_CAPTAIN_ON_BIKE_A")
	_check("three doctrine options, one required", bool(t.get("require_variant", false)) and t.get("variants", []).size() == 3)
	_check("not offered in the opponent's Command phase", _offer(2, "phase_start", {"phase": "command"}, "strategic_acumen").is_empty())
	_phase(P_MOV)
	_check("not offered in the Movement phase", _offer(1, "phase_start", {"phase": "movement"}, "strategic_acumen").is_empty())
	_phase(P_CMD)
	var bad := _use(1, "strategic_acumen", "U_CAPTAIN_ON_BIKE_A", "phase_start", {"phase": "command"})
	_check("refused without a doctrine", not bad.get("success", true))
	var r := _use(1, "strategic_acumen", "U_CAPTAIN_ON_BIKE_A", "phase_start", {"phase": "command"}, "", "tactical")
	_check("used: free", r.get("success", false) and int(GS.state.players["1"].cp) == 6, str(r))
	_check("the tactical doctrine is active for the unit", SWC.doctrine_active_id("U_CAPTAIN_ON_BIKE_A", "tactical"), str(SWC.active_doctrines(_u("U_CAPTAIN_ON_BIKE_A"))))
	_check("not for another unit", not SWC.doctrine_active_id("U_CAPTAIN_A", "tactical"))
	_check("once per phase", _offer(1, "phase_start", {"phase": "command"}, "strategic_acumen").is_empty())
	C.on_phase_transition(P_CMD, P_MOV)
	_check("still active in the opponent's turn", SWC.doctrine_active_id("U_CAPTAIN_ON_BIKE_A", "tactical"))
	_phase(P_FIGHT, 2)
	_phase(P_FIGHT, 1)
	C.on_phase_transition(P_FIGHT, P_CMD)
	_check("expires at the start of your next Command phase", not SWC.doctrine_active_id("U_CAPTAIN_ON_BIKE_A", "tactical") and not _flags("U_CAPTAIN_ON_BIKE_A").has(C.F_DOCTRINE_SRC))


# ---------------------------------------------------------------------------
# 5. Narthecium (Apothecary)
# ---------------------------------------------------------------------------
func _section_narthecium() -> void:
	print("\n-- 5. Narthecium --")
	_fresh(P_CMD)
	_place("U_INTERCESSOR_SQUAD_A", 10, 10)
	_place("U_APOTHECARY_A", 10, 11.5)
	_attach("U_APOTHECARY_A", "U_INTERCESSOR_SQUAD_A")
	_check("not offered while nobody is wounded", _offer(1, "phase_start", {"phase": "command"}, "narthecium").is_empty())
	var ms: Array = _u("U_INTERCESSOR_SQUAD_A").models
	ms[0]["alive"] = false
	ms[1]["current_wounds"] = 1
	var o := _offer(1, "phase_start", {"phase": "command"}, "narthecium")
	_check("offered (your Command phase, the unit lost wounds)", _offer_units(o) == ["U_INTERCESSOR_SQUAD_A"], str(_offer_units(o)))
	var before := _wounds_left("U_INTERCESSOR_SQUAD_A")
	RE.set_test_seed(3)
	var r := _use(1, "narthecium", "U_INTERCESSOR_SQUAD_A", "phase_start", {"phase": "command"})
	var healed := _wounds_left("U_INTERCESSOR_SQUAD_A") - before
	_check("heals D3+1 (2-4) wounds: +%d" % healed, r.get("success", false) and healed >= 2 and healed <= 4)
	_check("the wounded model first, then a destroyed model returns", int(ms[1].current_wounds) == 2 and (healed < 2 or bool(ms[0].alive) or healed == 1))
	RE.set_test_seed(-1)
	_check("once per phase", _offer(1, "phase_start", {"phase": "command"}, "narthecium").is_empty())
	_phase(P_CMD, 2)
	_check("not in the opponent's Command phase", _offer(1, "phase_start", {"phase": "command"}, "narthecium").is_empty())


# ---------------------------------------------------------------------------
# 6. Master of Shadows (Aethon Shaan)
# ---------------------------------------------------------------------------
func _section_master_of_shadows() -> void:
	print("\n-- 6. Master of Shadows --")
	_fresh(P_CMD)
	_place("U_AETHON_SHAAN_A", 10, 10)
	_place("U_ASSAULT_INTERCESSOR_SQUAD_A", 14, 10)
	_place("U_REDEMPTOR_DREADNOUGHT_A", 20, 10)
	_place("U_BOYZ_B", 14, 20)
	var o := _offer(1, "phase_start", {"phase": "command"}, "master_of_shadows")
	var opts := _secondary_ids(o, "U_AETHON_SHAAN_A")
	_check("offered with friendly ADEPTUS ASTARTES INFANTRY units", "U_ASSAULT_INTERCESSOR_SQUAD_A" in opts and not "U_REDEMPTOR_DREADNOUGHT_A" in opts, str(opts))
	_check("no charge re-roll before", not EP.has_effect_reroll_charge(_u("U_ASSAULT_INTERCESSOR_SQUAD_A")))
	var r := _use(1, "master_of_shadows", "U_AETHON_SHAAN_A", "phase_start", {"phase": "command"}, "U_ASSAULT_INTERCESSOR_SQUAD_A")
	_check("used", r.get("success", false), str(r))
	_check("the unit can re-roll charge rolls", EP.has_effect_reroll_charge(_u("U_ASSAULT_INTERCESSOR_SQUAD_A")) and C.charge_reroll_source(_u("U_ASSAULT_INTERCESSOR_SQUAD_A")) == "Master of Shadows")
	_check("once per phase", _offer(1, "phase_start", {"phase": "command"}, "master_of_shadows").is_empty())
	C.on_phase_transition(P_CMD, P_MOV)
	_phase(P_CMD, 2)
	C.on_phase_transition(P_FIGHT, P_CMD)
	_check("still active in the opponent's turn", C.charge_reroll_source(_u("U_ASSAULT_INTERCESSOR_SQUAD_A")) != "")
	_phase(P_CMD, 1)
	C.on_phase_transition(P_FIGHT, P_CMD)
	_check("expires at the start of your next Command phase", C.charge_reroll_source(_u("U_ASSAULT_INTERCESSOR_SQUAD_A")) == "")


# ---------------------------------------------------------------------------
# 7. Seeker of the Unfound (Vulkan He'stan)
# ---------------------------------------------------------------------------
func _section_seeker() -> void:
	print("\n-- 7. Seeker of the Unfound --")
	_fresh(P_CMD)
	_check("not offered while Vulkan is not on the battlefield", _offer(1, "phase_start", {"phase": "command"}, "seeker_of_the_unfound").is_empty())
	var op := _obj_pos(0)
	_place("U_VULKAN_HE_STAN_A", op.x + 1.0, op.y)
	var o := _offer(1, "phase_start", {"phase": "command"}, "seeker_of_the_unfound")
	var opts := _secondary_ids(o, "U_VULKAN_HE_STAN_A")
	_check("offered once he is on the battlefield, objective picker (nearest first)", opts.size() == SWC.objectives().size() and opts[0] == str(SWC.objectives()[0].get("id", "")), str(opts))
	_phase(P_MOV, 2)
	_check("offered at any phase start until chosen (first time set up)", not _offer(1, "phase_start", {"phase": "movement"}, "seeker_of_the_unfound").is_empty())
	var oc0: int = MM.model_oc(_u("U_VULKAN_HE_STAN_A"), _u("U_VULKAN_HE_STAN_A").models[0])
	var r := _use(1, "seeker_of_the_unfound", "U_VULKAN_HE_STAN_A", "phase_start", {"phase": "movement"}, opts[0])
	_check("chosen", r.get("success", false), str(r))
	_check("never offered again", _offer(1, "phase_start", {"phase": "movement"}, "seeker_of_the_unfound").is_empty())
	var oc1: int = MM.model_oc(_u("U_VULKAN_HE_STAN_A"), _u("U_VULKAN_HE_STAN_A").models[0])
	_check("within range of it: OC %d -> 10" % oc0, oc1 == 10, str(oc1))
	_check("within range: Feel No Pain 4+ (better than his 6+)", RE.get_unit_fnp(_u("U_VULKAN_HE_STAN_A")) == 4)
	var cp = load("res://phases/CommandPhase.gd")
	_check("within range: Ld 5+", int(cp._get_effective_leadership("U_VULKAN_HE_STAN_A")) == 5, str(cp._get_effective_leadership("U_VULKAN_HE_STAN_A")))
	_place("U_VULKAN_HE_STAN_A", 2, 2)
	_check("out of range: printed OC, FNP 6+, Ld 6+", MM.model_oc(_u("U_VULKAN_HE_STAN_A"), _u("U_VULKAN_HE_STAN_A").models[0]) == oc0 and RE.get_unit_fnp(_u("U_VULKAN_HE_STAN_A")) == 6 \
		and int(cp._get_effective_leadership("U_VULKAN_HE_STAN_A")) == 6)


# ---------------------------------------------------------------------------
# 8. Forgefather (Vulkan He'stan)
# ---------------------------------------------------------------------------
func _section_forgefather() -> void:
	print("\n-- 8. Forgefather --")
	_fresh(P_SHOOT)
	_place("U_VULKAN_HE_STAN_A", 10, 10)
	_place("U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A", 12, 10)
	_place("U_DEFF_DREAD_A", 10, 25)
	_place("U_BOYZ_B", 30, 55)
	var o := _offer(1, "phase_start", {"phase": "shooting"}, "forgefather")
	var opts := _secondary_ids(o, "U_VULKAN_HE_STAN_A")
	_check("offered at the start of your Shooting phase with visible enemies within 24\"", "U_DEFF_DREAD_A" in opts and not "U_BOYZ_B" in opts, str(opts))
	_phase(P_SHOOT, 2)
	_check("not in the opponent's Shooting phase", _offer(1, "phase_start", {"phase": "shooting"}, "forgefather").is_empty())
	_phase(P_SHOOT, 1)
	_check("no +S before", int(_mods("U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A", "U_DEFF_DREAD_A", false, "Melta Rifle", ["MELTA 2"]).strength) == 0)
	var r := _use(1, "forgefather", "U_VULKAN_HE_STAN_A", "phase_start", {"phase": "shooting"}, "U_DEFF_DREAD_A")
	_check("used", r.get("success", false), str(r))
	var mm := _mods("U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A", "U_DEFF_DREAD_A", false, "Melta Rifle", ["MELTA 2"])
	_check("a friendly unit's [MELTA] attacks vs it: +2 S", int(mm.strength) == 2 and "Forgefather" in _names(mm), str(mm))
	_check("[TORRENT] too", int(_mods("U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A", "U_DEFF_DREAD_A", false, "Heavy Flamer", ["TORRENT"]).strength) == 2)
	_check("not other weapons", int(_mods("U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A", "U_DEFF_DREAD_A", false, "Bolt Pistol", ["PISTOL"]).strength) == 0)
	_check("not vs another target", int(_mods("U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A", "U_BOYZ_B", false, "Melta Rifle", ["MELTA 2"]).strength) == 0)
	_check("once per phase", _offer(1, "phase_start", {"phase": "shooting"}, "forgefather").is_empty())
	C.on_phase_transition(P_SHOOT, P_CHG)
	_phase(P_CHG)
	_check("expires at the end of the phase", not _flags("U_DEFF_DREAD_A").has(C.F_FORGEFATHER))


# ---------------------------------------------------------------------------
# 9. Overlapping Destruction (Eradicators with Heavy Bolters)
# ---------------------------------------------------------------------------
func _section_overlapping() -> void:
	print("\n-- 9. Overlapping Destruction --")
	_fresh(P_SHOOT)
	_place("U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A", 10, 10)
	_place("U_BOYZ_B", 10, 25)
	var o := _offer(1, "unit_selected_to_shoot", {"phase": "shooting", "unit_id": "U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A"}, "overlapping_destruction")
	_check("offered when the Eradicators are selected to shoot", _offer_units(o) == ["U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A"])
	_check("not for another shooter", _offer(1, "unit_selected_to_shoot", {"phase": "shooting", "unit_id": "U_INTERCESSOR_SQUAD_A"}, "overlapping_destruction").is_empty())
	_check("also at the start of your Shooting phase", not _offer(1, "phase_start", {"phase": "shooting"}, "overlapping_destruction").is_empty())
	var r := _use(1, "overlapping_destruction", "U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A", "unit_selected_to_shoot", {"phase": "shooting", "unit_id": "U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A"}, "U_BOYZ_B")
	_check("used", r.get("success", false), str(r))
	var n := _alive("U_BOYZ_B")
	var md := _mods("U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A", "U_BOYZ_B", false, "Heavy Bolter")
	_check("Heavy Bolters vs it: [BLAST 1] = +%d attack(s) per model (%d models)" % [int(n / 5), n], int(md.attacks) == int(n / 5), str(md))
	_check("not the Bolt Pistols", int(_mods("U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A", "U_BOYZ_B", false, "Bolt Pistol").attacks) == 0)
	var hb := _weapon("U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A", "heavy bolter", false)
	var on := _shoot(GS.state.duplicate(true), "U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A", hb, "U_BOYZ_B", 11)
	var board_off: Dictionary = GS.state.duplicate(true)
	board_off.units.U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A.flags.erase(C.F_OVERLAP)
	_flags("U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A").erase(C.F_OVERLAP)
	var off := _shoot(board_off, "U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A", hb, "U_BOYZ_B", 11)
	_check("A/B (seed 11): %d attacks with vs %d without" % [int(on.attacks), int(off.attacks)], int(on.attacks) == int(off.attacks) + 3 * int(n / 5), "%s %s" % [on.attacks, off.attacks])


# ---------------------------------------------------------------------------
# 10. Master Tactician + Codex Adept (Marneus Calgar)
# ---------------------------------------------------------------------------
func _section_master_tactician_codex_adept() -> void:
	print("\n-- 10. Master Tactician, Codex Adept --")
	_fresh(P_MOV)
	_place("U_MARNEUS_CALGAR_A", 10, 10)
	_place("U_INTERCESSOR_SQUAD_A", 14, 10)
	_place("U_HELLBLASTER_SQUAD_A", 30, 40)
	var o := _offer(1, "phase_start", {"phase": "movement"}, "master_tactician")
	var units := _offer_units(o)
	_check("offered at the start of your Movement phase: friendly units within 9\" (visible)", "U_INTERCESSOR_SQUAD_A" in units and not "U_HELLBLASTER_SQUAD_A" in units, str(units))
	var r := _use(1, "master_tactician", "U_INTERCESSOR_SQUAD_A", "phase_start", {"phase": "movement"}, "", "assault")
	_check("used: assault doctrine active for that unit", r.get("success", false) and SWC.doctrine_active_id("U_INTERCESSOR_SQUAD_A", "assault"), str(r))
	_check("once per phase", _offer(1, "phase_start", {"phase": "movement"}, "master_tactician").is_empty())
	C.on_phase_transition(P_MOV, P_SHOOT)
	_check("Codex Adept: all three doctrines active for Calgar's unit", SWC.active_doctrines(_u("U_MARNEUS_CALGAR_A")).size() == 3, str(SWC.active_doctrines(_u("U_MARNEUS_CALGAR_A"))))
	_attach("U_MARNEUS_CALGAR_A", "U_VICTRIX_HONOUR_GUARD_A")
	C.on_phase_transition(P_SHOOT, P_CHG)
	_check("Codex Adept: the Attached unit too", SWC.active_doctrines(_u("U_VICTRIX_HONOUR_GUARD_A")).size() == 3)
	for m in _u("U_MARNEUS_CALGAR_A").models:
		m["alive"] = false
	C.on_phase_transition(P_CHG, P_FIGHT)
	_check("Codex Adept: removed once Calgar is destroyed", SWC.active_doctrines(_u("U_VICTRIX_HONOUR_GUARD_A")).size() <= 1)
	_phase(P_FIGHT)
	C.on_phase_transition(P_FIGHT, P_CMD)
	_check("Master Tactician expires at the start of your next Command phase", not SWC.doctrine_active_id("U_INTERCESSOR_SQUAD_A", "assault"))


# ---------------------------------------------------------------------------
# 11. Cold and Calculating (Caanok Var)
# ---------------------------------------------------------------------------
func _section_cold() -> void:
	print("\n-- 11. Cold and Calculating --")
	_fresh(P_SHOOT)
	_place("U_CAANOK_VAR_A", 10, 10)
	_place("U_DEFF_DREAD_A", 10, 25)
	_place("U_BOYZ_B", 20, 25)
	var o := _offer(1, "unit_selected_to_shoot", {"phase": "shooting", "unit_id": "U_CAANOK_VAR_A"}, "cold_and_calculating")
	var t := _target(o, "U_CAANOK_VAR_A")
	_check("offered when selected to shoot: two options (no tactical doctrine)", t.get("variants", []).size() == 2, str(t.get("variants", [])))
	_check("not in the opponent's Shooting phase", (func(): _phase(P_SHOOT, 2); var e := _offer(1, "unit_selected_to_shoot", {"phase": "shooting", "unit_id": "U_CAANOK_VAR_A"}, "cold_and_calculating").is_empty(); _phase(P_SHOOT, 1); return e).call())
	var r := _use(1, "cold_and_calculating", "U_CAANOK_VAR_A", "unit_selected_to_shoot", {"phase": "shooting", "unit_id": "U_CAANOK_VAR_A"}, "", "lethal")
	_check("used (lethal)", r.get("success", false), str(r))
	_check("[LETHAL HITS] vs a VEHICLE", bool(_mods("U_CAANOK_VAR_A", "U_DEFF_DREAD_A", false).lethal))
	_check("no [SUSTAINED HITS] vs infantry with the lethal choice", int(_mods("U_CAANOK_VAR_A", "U_BOYZ_B", false).sustained) == 0 and not _mods("U_CAANOK_VAR_A", "U_BOYZ_B", false).lethal)
	_check("once per phase", _offer(1, "unit_selected_to_shoot", {"phase": "shooting", "unit_id": "U_CAANOK_VAR_A"}, "cold_and_calculating").is_empty())
	C.on_phase_transition(P_SHOOT, P_CHG)
	_check("expires at the end of the phase", not _flags("U_CAANOK_VAR_A").has(C.F_COLD))
	_phase(P_FIGHT)
	_flags("U_CAANOK_VAR_A")["sw11e_doctrine"] = "tactical"
	var o2 := _offer(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_CAANOK_VAR_A"}, "cold_and_calculating")
	_check("tactical doctrine active: a third option (both)", _target(o2, "U_CAANOK_VAR_A").get("variants", []).size() == 3 and str(_target(o2, "U_CAANOK_VAR_A").get("ai_variant", "")) == "both")
	_use(1, "cold_and_calculating", "U_CAANOK_VAR_A", "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_CAANOK_VAR_A"}, "", "both")
	_check("both: [LETHAL HITS] vs VEHICLE and [SUSTAINED HITS 1] vs others (melee)", bool(_mods("U_CAANOK_VAR_A", "U_DEFF_DREAD_A", true).lethal) and int(_mods("U_CAANOK_VAR_A", "U_BOYZ_B", true).sustained) == 1)


# ---------------------------------------------------------------------------
# 12. Purgation Run (Land Speeder)
# ---------------------------------------------------------------------------
func _section_purgation_run() -> void:
	print("\n-- 12. Purgation Run --")
	_fresh(P_SHOOT)
	_place("U_LAND_SPEEDER_A", 10, 10)
	_place("U_BOYZ_B", 10, 30)
	var o := _offer(1, "unit_has_shot", {"phase": "shooting", "unit_id": "U_LAND_SPEEDER_A"}, "purgation_run")
	_check("offered when the Land Speeder has shot", _offer_units(o) == ["U_LAND_SPEEDER_A"])
	_check("not for another unit that has shot", _offer(1, "unit_has_shot", {"phase": "shooting", "unit_id": "U_INTERCESSOR_SQUAD_A"}, "purgation_run").is_empty())
	_check("not when selected to shoot", _offer(1, "unit_selected_to_shoot", {"phase": "shooting", "unit_id": "U_LAND_SPEEDER_A"}, "purgation_run").is_empty())
	_check("not locked before", not C.blocks_charge(_u("U_LAND_SPEEDER_A")))
	RE.set_test_seed(5)
	var r := _use(1, "purgation_run", "U_LAND_SPEEDER_A", "unit_has_shot", {"phase": "shooting", "unit_id": "U_LAND_SPEEDER_A"})
	RE.set_test_seed(-1)
	var fu: Dictionary = r.get("followup", {})
	_check("follow-up: a normal move of up to D6\"", str(fu.get("type", "")) == "reactive_normal_move" and float(fu.get("max_inches", 0)) >= 1.0 and float(fu.get("max_inches", 0)) <= 6.0, str(fu))
	_check("then not eligible to declare a charge this turn", C.blocks_charge(_u("U_LAND_SPEEDER_A")))
	_phase(P_CHG)
	var cph = load("res://phases/ChargePhase.gd").new()
	_check("ChargePhase refuses the charge (hard lock)", not cph._can_unit_charge(_u("U_LAND_SPEEDER_A")))
	_check("RulesEngine refuses the charge (hard lock)", not RE.eligible_to_charge("U_LAND_SPEEDER_A", GS.state))
	cph.free()
	GS.state.meta["battle_round"] = 3
	_check("lock ends with the turn", not C.blocks_charge(_u("U_LAND_SPEEDER_A")))


# ---------------------------------------------------------------------------
# 13. Captain Titus — Righteous Fury, Honour of Ultramar
# ---------------------------------------------------------------------------
func _section_titus() -> void:
	print("\n-- 13. Righteous Fury, Honour of Ultramar --")
	_fresh(P_FIGHT)
	_place("U_INTERCESSOR_SQUAD_A", 10, 10)
	_place("U_CAPTAIN_TITUS_A", 10, 11.4)
	_attach("U_CAPTAIN_TITUS_A", "U_INTERCESSOR_SQUAD_A")
	_place("U_WARBOSS_A", 10, 12.6)
	var o := _offer(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_INTERCESSOR_SQUAD_A"}, "righteous_fury")
	_check("offered when Titus's unit is selected to fight", _offer_units(o) == ["U_INTERCESSOR_SQUAD_A"], str(_offer_units(o)))
	_check("not when selected to shoot", _offer(1, "unit_selected_to_shoot", {"phase": "shooting", "unit_id": "U_INTERCESSOR_SQUAD_A"}, "righteous_fury").is_empty())
	_u("U_CAPTAIN_TITUS_A").models[0]["current_wounds"] = 2
	var r := _use(1, "righteous_fury", "U_INTERCESSOR_SQUAD_A", "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_INTERCESSOR_SQUAD_A"})
	_check("used", r.get("success", false), str(r))
	_check("melee +1 S (the whole unit)", int(_mods("U_CAPTAIN_TITUS_A", "U_WARBOSS_A", true).strength) == 1 and int(_mods("U_INTERCESSOR_SQUAD_A", "U_WARBOSS_A", true).strength) == 1)
	_check("once per battle (per army)", _offer(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_INTERCESSOR_SQUAD_A"}, "righteous_fury").is_empty())
	RE.set_test_seed(2)
	C.on_unit_has_fought("U_INTERCESSOR_SQUAD_A")
	RE.set_test_seed(-1)
	var cw := int(_u("U_CAPTAIN_TITUS_A").models[0].current_wounds)
	_check("when the unit has fought: Titus heals D3 (no kill): 2 -> %d" % cw, cw >= 3 and cw <= 5)
	C.on_unit_has_fought("U_INTERCESSOR_SQUAD_A")
	_check("heals only once", int(_u("U_CAPTAIN_TITUS_A").models[0].current_wounds) == cw)
	# 2D3 after a kill
	_fresh(P_FIGHT)
	_place("U_CAPTAIN_TITUS_A", 10, 11.4)
	_place("U_BOYZ_B", 10, 12.6)
	_u("U_CAPTAIN_TITUS_A").models[0]["current_wounds"] = 1
	_use(1, "righteous_fury", "U_CAPTAIN_TITUS_A", "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_CAPTAIN_TITUS_A"})
	_u("U_BOYZ_B").models[0]["alive"] = false
	C.on_unit_has_fought("U_CAPTAIN_TITUS_A")
	_check("an enemy model destroyed this phase: heals 2D3 (>= 2)", int(_u("U_CAPTAIN_TITUS_A").models[0].current_wounds) >= 3)
	C.on_phase_transition(P_FIGHT, P_CMD)
	_check("+1 S expires at the end of the phase", int(_mods("U_CAPTAIN_TITUS_A", "U_BOYZ_B", true).strength) == 0)
	# Honour of Ultramar
	_phase(P_FIGHT)
	_check("Honour of Ultramar: Fight On Death 2+ for Titus's model", C.fod_rule("U_CAPTAIN_TITUS_A", 0).get("pass", 0) == 2)
	_check("not his bodyguard", C.fod_rule("U_INTERCESSOR_SQUAD_A", 0).is_empty())
	_phase(P_SHOOT)
	_check("not outside the Fight phase", C.fod_rule("U_CAPTAIN_TITUS_A", 0).is_empty())


# ---------------------------------------------------------------------------
# 14. Banner of Macragge (Victrix Honour Guard, once per battle)
# ---------------------------------------------------------------------------
func _section_banner() -> void:
	print("\n-- 14. Banner of Macragge (selected to fight) --")
	_fresh(P_FIGHT)
	_place("U_VICTRIX_HONOUR_GUARD_A", 10, 10)
	_place("U_BOYZ_B", 10, 11.4)
	var o := _offer(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_VICTRIX_HONOUR_GUARD_A"}, "banner_of_macragge")
	_check("offered when selected to fight", _offer_units(o) == ["U_VICTRIX_HONOUR_GUARD_A"])
	var r := _use(1, "banner_of_macragge", "U_VICTRIX_HONOUR_GUARD_A", "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_VICTRIX_HONOUR_GUARD_A"})
	var mb := _mods("U_VICTRIX_HONOUR_GUARD_A", "U_BOYZ_B", true)
	_check("melee +1 A and +1 S", r.get("success", false) and int(mb.attacks) == 1 and int(mb.strength) == 1, str(mb))
	_check("once per battle", _offer(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_VICTRIX_HONOUR_GUARD_A"}, "banner_of_macragge").is_empty())
	C.on_phase_transition(P_FIGHT, P_CMD)
	_check("expires at the end of the phase", int(_mods("U_VICTRIX_HONOUR_GUARD_A", "U_BOYZ_B", true).attacks) == 0)


# ---------------------------------------------------------------------------
# 15. Hammer of Wrath (Assault Intercessors with Jump Packs)
# ---------------------------------------------------------------------------
func _section_hammer_of_wrath() -> void:
	print("\n-- 15. Hammer of Wrath --")
	_fresh(P_CHG)
	_place("U_ASSAULT_INTERCESSORS_WITH_JUMP_PACKS_A", 10, 10)
	_place("U_BOYZ_B", 10, 11.3)
	var o := _offer(1, "unit_ended_charge_move", {"phase": "charge", "unit_id": "U_ASSAULT_INTERCESSORS_WITH_JUMP_PACKS_A"}, "hammer_of_wrath")
	_check("offered when the unit ends a charge move, engaged enemy picker", _secondary_ids(o, "U_ASSAULT_INTERCESSORS_WITH_JUMP_PACKS_A") == ["U_BOYZ_B"], str(o))
	_place("U_BOYZ_B", 10, 30)
	_check("not when nothing is engaged", _offer(1, "unit_ended_charge_move", {"phase": "charge", "unit_id": "U_ASSAULT_INTERCESSORS_WITH_JUMP_PACKS_A"}, "hammer_of_wrath").is_empty())
	_place("U_BOYZ_B", 10, 11.3)
	var before := _wounds_left("U_BOYZ_B")
	RE.set_test_seed(9)
	var r := _use(1, "hammer_of_wrath", "U_ASSAULT_INTERCESSORS_WITH_JUMP_PACKS_A", "unit_ended_charge_move", {"phase": "charge", "unit_id": "U_ASSAULT_INTERCESSORS_WITH_JUMP_PACKS_A"}, "U_BOYZ_B")
	RE.set_test_seed(-1)
	var lost := before - _wounds_left("U_BOYZ_B")
	_check("D6 per engaged model, 4+ = 1 mortal wound (lost %d, at most the engaged count %d)" % [lost, C._engaged_model_count("U_ASSAULT_INTERCESSORS_WITH_JUMP_PACKS_A", "U_BOYZ_B")],
		r.get("success", false) and lost >= 0 and lost <= C._engaged_model_count("U_ASSAULT_INTERCESSORS_WITH_JUMP_PACKS_A", "U_BOYZ_B"), str(r))
	var any_mw := false
	for sd in range(1, 30):
		_fresh(P_CHG)
		_place("U_ASSAULT_INTERCESSORS_WITH_JUMP_PACKS_A", 10, 10)
		_place("U_BOYZ_B", 10, 11.3)
		RE.set_test_seed(sd)
		var b := _wounds_left("U_BOYZ_B")
		_use(1, "hammer_of_wrath", "U_ASSAULT_INTERCESSORS_WITH_JUMP_PACKS_A", "unit_ended_charge_move", {"phase": "charge", "unit_id": "U_ASSAULT_INTERCESSORS_WITH_JUMP_PACKS_A"}, "U_BOYZ_B")
		if _wounds_left("U_BOYZ_B") < b:
			any_mw = true
			break
	RE.set_test_seed(-1)
	_check("mortal wounds are inflicted on some seed", any_mw)


# ---------------------------------------------------------------------------
# 16. Knight Champion of Macragge (Cato Sicarius)
# ---------------------------------------------------------------------------
func _section_knight_champion() -> void:
	print("\n-- 16. Knight Champion of Macragge --")
	_fresh(P_MOV, 2)
	_place("U_CATO_SICARIUS_A", 10, 10)
	_place("U_BOYZ_B", 10, 17)
	var ctx := {"phase": "movement", "enemy_unit_id": "U_BOYZ_B"}
	var o := _offer(1, "enemy_ended_move", ctx, "knight_champion_of_macragge")
	_check("offered when an enemy ends a move within 8\" in your opponent's Movement phase", _offer_units(o) == ["U_CATO_SICARIUS_A"], str(o))
	_place("U_BOYZ_B", 10, 30)
	_check("not beyond 8\"", _offer(1, "enemy_ended_move", ctx, "knight_champion_of_macragge").is_empty())
	_place("U_BOYZ_B", 10, 11.2)
	_check("not while engaged", _offer(1, "enemy_ended_move", ctx, "knight_champion_of_macragge").is_empty())
	_place("U_BOYZ_B", 10, 16)
	var r := _use(1, "knight_champion_of_macragge", "U_CATO_SICARIUS_A", "enemy_ended_move", ctx)
	_check("normal move of up to 6\" (follow-up)", str(r.get("followup", {}).get("type", "")) == "reactive_normal_move" and float(r.followup.get("max_inches", 0)) == 6.0, str(r))
	_check("once per phase (per army)", _offer(1, "enemy_ended_move", ctx, "knight_champion_of_macragge").is_empty())
	_phase(P_MOV, 1)
	_check("not in your own Movement phase", _offer(1, "enemy_ended_move", ctx, "knight_champion_of_macragge").is_empty())


# ---------------------------------------------------------------------------
# 17. Glory of Ultramar (Victrix Honour Guard)
# ---------------------------------------------------------------------------
func _section_glory() -> void:
	print("\n-- 17. Glory of Ultramar --")
	_fresh(P_SHOOT, 2)
	_place("U_VICTRIX_HONOUR_GUARD_A", 10, 10)
	_place("U_BOYZ_B", 10, 25)
	var ctx := {"phase": "shooting", "attacker_unit_id": "U_BOYZ_B", "wounded_unit_ids": ["U_VICTRIX_HONOUR_GUARD_A"], "models_destroyed_unit_ids": []}
	_check("not when it only lost wounds", _offer(1, "enemy_has_shot", ctx, "glory_of_ultramar").is_empty())
	ctx["models_destroyed_unit_ids"] = ["U_VICTRIX_HONOUR_GUARD_A"]
	var o := _offer(1, "enemy_has_shot", ctx, "glory_of_ultramar")
	_check("offered when a model of the unit was destroyed by those attacks", _offer_units(o) == ["U_VICTRIX_HONOUR_GUARD_A"])
	var r := _use(1, "glory_of_ultramar", "U_VICTRIX_HONOUR_GUARD_A", "enemy_has_shot", ctx)
	_check("surge move of up to D6\" (follow-up)", str(r.get("followup", {}).get("type", "")) == "surge_move", str(r))
	_check("once per enemy shot window (phase use recorded)", _offer(1, "enemy_has_shot", ctx, "glory_of_ultramar").is_empty())
	_phase(P_SHOOT, 1)
	_check("not in your own Shooting phase", _offer(1, "enemy_has_shot", ctx, "glory_of_ultramar").is_empty())
	# The ShootingPhase post-shot ctx reports units that lost a model.
	var sp = load("res://phases/ShootingPhase.gd").new()
	sp._sm11e_pre_shot_alive = {"U_VICTRIX_HONOUR_GUARD_A": 3, "U_INTERCESSOR_SQUAD_A": 5}
	_u("U_VICTRIX_HONOUR_GUARD_A").models[0]["alive"] = false
	var pctx: Dictionary = sp._ork11e_post_shot_ctx("U_BOYZ_B")
	_check("ShootingPhase post-shot ctx: models_destroyed_unit_ids", pctx.get("models_destroyed_unit_ids", []) == ["U_VICTRIX_HONOUR_GUARD_A"], str(pctx))
	sp.free()


# ---------------------------------------------------------------------------
# 18. Echo of the Ravenspire (Kayvaan Shrike)
# ---------------------------------------------------------------------------
func _section_echo() -> void:
	print("\n-- 18. Echo of the Ravenspire --")
	_fresh(P_FIGHT, 2)
	_place("U_KAYVAAN_SHRIKE_A", 10, 10)
	_place("U_BOYZ_B", 10, 30)
	var o := _offer(1, "fight_phase_end", {"phase": "fight"}, "echo_of_the_ravenspire")
	_check("offered at the end of your opponent's Fight phase (unengaged)", _offer_units(o) == ["U_KAYVAAN_SHRIKE_A"])
	_phase(P_FIGHT, 1)
	_check("not at the end of your own Fight phase", _offer(1, "fight_phase_end", {"phase": "fight"}, "echo_of_the_ravenspire").is_empty())
	_phase(P_FIGHT, 2)
	_place("U_BOYZ_B", 10, 11.2)
	_check("not while engaged", _offer(1, "fight_phase_end", {"phase": "fight"}, "echo_of_the_ravenspire").is_empty())
	_place("U_BOYZ_B", 10, 30)
	var r := _use(1, "echo_of_the_ravenspire", "U_KAYVAAN_SHRIKE_A", "fight_phase_end", {"phase": "fight"})
	_check("follow-up: placed in strategic reserves", str(r.get("followup", {}).get("type", "")) == "strategic_reserves", str(r))


# ---------------------------------------------------------------------------
# 19. Combat Embarkation (Repulsor)
# ---------------------------------------------------------------------------
func _section_combat_embarkation() -> void:
	print("\n-- 19. Combat Embarkation --")
	_fresh(P_CHG, 2)
	_place("U_REPULSOR_A", 10, 10)
	_place("U_INTERCESSOR_SQUAD_A", 9, 12.8)
	_place("U_HELLBLASTER_SQUAD_A", 30, 30)
	_place("U_BOYZ_B", 10, 22)
	var ctx := {"phase": "charge", "unit_id": "U_BOYZ_B", "enemy_unit_id": "U_BOYZ_B", "target_unit_ids": ["U_INTERCESSOR_SQUAD_A", "U_HELLBLASTER_SQUAD_A"]}
	var o := _offer(1, "enemy_declares_charge", ctx, "combat_embarkation")
	_check("offered: a charge target within 3\" of the Repulsor", _secondary_ids(o, "U_REPULSOR_A") == ["U_INTERCESSOR_SQUAD_A"], str(o))
	_phase(P_CHG, 1)
	_check("not in your own Charge phase", _offer(1, "enemy_declares_charge", ctx, "combat_embarkation").is_empty())
	_phase(P_CHG, 2)
	var r := _use(1, "combat_embarkation", "U_REPULSOR_A", "enemy_declares_charge", ctx, "U_INTERCESSOR_SQUAD_A")
	_check("used", r.get("success", false), str(r))
	_check("the Intercessors embarked (off the battlefield)", str(_u("U_INTERCESSOR_SQUAD_A").get("embarked_in", "")) == "U_REPULSOR_A" and _u("U_INTERCESSOR_SQUAD_A").models[0].get("position", null) == null \
		and "U_INTERCESSOR_SQUAD_A" in _u("U_REPULSOR_A").get("transport_data", {}).get("embarked_units", []))
	var tmpl = MoveTypes.get_type("charge")
	_check("the charger can no longer select it as a target", not "U_INTERCESSOR_SQUAD_A" in tmpl._targets_within("U_BOYZ_B", GS.state, 12.0))


# ---------------------------------------------------------------------------
# 20. Reiver Squad — Terror Troops, Fearsome Assault, Grapnel Launchers, Grav-chutes
# ---------------------------------------------------------------------------
func _section_reivers() -> void:
	print("\n-- 20. Terror Troops, Fearsome Assault, Grapnel Launchers, Grav-chutes --")
	_fresh(P_CMD)
	_place("U_BOYZ_B", 10, 10)
	var oc0: int = MM.model_oc(_u("U_BOYZ_B"), _u("U_BOYZ_B").models[0])
	_place("U_REIVER_SQUAD_A", 10, 12)
	var oc1: int = MM.model_oc(_u("U_BOYZ_B"), _u("U_BOYZ_B").models[0])
	_check("Terror Troops: an enemy model within 3\" of the Reivers has -1 OC (%d -> %d)" % [oc0, oc1], oc1 == maxi(oc0 - 1, 0) and oc0 > 0)
	_place("U_REIVER_SQUAD_A", 10, 30)
	_check("Terror Troops: beyond 3\" no change", MM.model_oc(_u("U_BOYZ_B"), _u("U_BOYZ_B").models[0]) == oc0)
	_check("Terror Troops: friendly models are not affected", MM.model_oc(_u("U_REIVER_SQUAD_A"), _u("U_REIVER_SQUAD_A").models[0]) == int(_u("U_REIVER_SQUAD_A").meta.stats.objective_control))
	# Fearsome Assault
	_fresh(P_FIGHT)
	_place("U_REIVER_SQUAD_A", 10, 10)
	_place("U_BOYZ_B", 10, 11.2)
	_place("U_WARBOSS_A", 30, 30)
	var tested := false
	var shocked_once := false
	for sd in range(1, 40):
		_flags("U_BOYZ_B").erase("battle_shocked")
		RE.set_test_seed(sd)
		var d: Array = C.on_fight_phase_start()
		tested = true
		if bool(_flags("U_BOYZ_B").get("battle_shocked", false)):
			shocked_once = true
			break
	RE.set_test_seed(-1)
	_check("Fearsome Assault: start of the Fight phase — the engaged enemy tests (battle-shocked on some seed)", tested and shocked_once)
	_check("Fearsome Assault: an unengaged enemy does not test", not bool(_flags("U_WARBOSS_A").get("battle_shocked", false)))
	# the -1 is applied: a roll equal to Ld passes without it, fails with it
	var mod_ok := false
	for sd in range(1, 200):
		var rr = RE.RNGService.new(sd)
		var probe = RE.RNGService.new(sd)
		var dd: Array = [probe.roll_d6(1)[0], probe.roll_d6(1)[0]]
		var res: Dictionary = C._battle_shock_roll("U_BOYZ_B", -1, rr)
		if int(res.total) == int(dd[0]) + int(dd[1]) - 1:
			mod_ok = true
			break
	_check("Fearsome Assault: -1 to that battle-shock roll", mod_ok)
	# Grapnel Launchers / Grav-chutes (wargear)
	_fresh(P_MOV)
	_check("Reivers without the wargear: no Deep Strike, no moving through models", not GS.unit_has_deep_strike("U_REIVER_SQUAD_A") and not C.moves_through_models("U_REIVER_SQUAD_A"))
	_u("U_REIVER_SQUAD_A").meta["wargear"] = ["1x Grav-chutes", "1x Grapnel Launchers"]
	_check("Grav-chutes: this unit has Deep Strike", GS.unit_has_deep_strike("U_REIVER_SQUAD_A"))
	_check("Grapnel Launchers: move through all types of model, ignore vertical distance", C.moves_through_models("U_REIVER_SQUAD_A") and C.ignores_vertical_distance("U_REIVER_SQUAD_A"))
	var mp = load("res://phases/MovementPhase.gd").new()
	_check("MovementPhase reads it (move through models)", mp._o6_moves_through_models("U_REIVER_SQUAD_A", {"mode": "NORMAL"}))
	mp.free()


# ---------------------------------------------------------------------------
# 21. Declare Battle Formations — Thunderhawk Insertion, Cerebrex Logic Engine
# ---------------------------------------------------------------------------
func _section_formations() -> void:
	print("\n-- 21. Thunderhawk Insertion, Cerebrex Logic Engine --")
	_fresh(P_FORM)
	var ch: Dictionary = C.formation_choices(1)
	_check("choices: Calgar (Thunderhawk Insertion) and Caanok Var (Cerebrex Logic Engine)", ch.get("U_MARNEUS_CALGAR_A", []) == ["thunderhawk_insertion"] and ch.get("U_CAANOK_VAR_A", []) == ["cerebrex_logic_engine"], str(ch))
	var th: Array = C.formation_candidates("U_MARNEUS_CALGAR_A", "thunderhawk_insertion")
	_check("Thunderhawk Insertion: GRAVIS/PHOBOS/TACTICUS units only", "U_INTERCESSOR_SQUAD_A" in th and "U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A" in th and not "U_REDEMPTOR_DREADNOUGHT_A" in th and not "U_TERMINATOR_SQUAD_A" in th, str(th.size()))
	var fp = _formations_phase()
	var bad: Dictionary = fp.validate_action({"type": "SM11E_FORMATION_GRANT", "holder_id": "U_MARNEUS_CALGAR_A", "slug": "thunderhawk_insertion", "unit_id": "U_REDEMPTOR_DREADNOUGHT_A", "player": 1})
	_check("refused for an ineligible unit", not bad.get("valid", true))
	_check("no Deep Strike before", not GS.unit_has_deep_strike("U_INTERCESSOR_SQUAD_A"))
	var act := {"type": "SM11E_FORMATION_GRANT", "holder_id": "U_MARNEUS_CALGAR_A", "slug": "thunderhawk_insertion", "unit_id": "U_INTERCESSOR_SQUAD_A", "player": 1}
	_check("valid for an Intercessor Squad", fp.validate_action(act).get("valid", false))
	var res: Dictionary = fp.process_action(act)
	PM.apply_state_changes(res.get("changes", []))
	_check("Thunderhawk Insertion: the Intercessors have Deep Strike", GS.unit_has_deep_strike("U_INTERCESSOR_SQUAD_A"))
	_check("used once", not fp.validate_action({"type": "SM11E_FORMATION_GRANT", "holder_id": "U_MARNEUS_CALGAR_A", "slug": "thunderhawk_insertion", "unit_id": "U_HELLBLASTER_SQUAD_A", "player": 1}).get("valid", true))
	var act2 := {"type": "SM11E_FORMATION_GRANT", "holder_id": "U_CAANOK_VAR_A", "slug": "cerebrex_logic_engine", "unit_id": "U_HELLBLASTER_SQUAD_A", "player": 1}
	_check("no Scouts before", not GS.unit_has_scout("U_HELLBLASTER_SQUAD_A"))
	PM.apply_state_changes(fp.process_action(act2).get("changes", []))
	_check("Cerebrex Logic Engine: the Hellblasters have Scouts 6\"", GS.unit_has_scout("U_HELLBLASTER_SQUAD_A") and GS.get_scout_distance("U_HELLBLASTER_SQUAD_A") == 6.0)
	var acts: Array = fp.get_available_actions()
	_check("no further choices offered once both are made", acts.filter(func(a): return str(a.get("type", "")) == "SM11E_FORMATION_GRANT").is_empty())
	fp.queue_free()
	# AI picks at confirm
	_fresh(P_FORM)
	var fp2 = _formations_phase()
	var aip = root.get_node("AIPlayer")
	aip.enabled = true
	aip.ai_players = {1: true, 2: false}
	_check("AIPlayer reports P1 as AI", aip.is_ai_player(1))
	fp2._process_confirm_formations({"type": "CONFIRM_FORMATIONS", "player": 1})
	aip.ai_players = {1: false, 2: false}
	aip.enabled = false
	var picked: Dictionary = _flags("U_MARNEUS_CALGAR_A").get(C.F_FORMATION_PICK, {})
	_check("AI: takes its Thunderhawk Insertion pick when it confirms", picked.has("thunderhawk_insertion") and GS.unit_has_deep_strike(str(picked.thunderhawk_insertion)), str(picked))
	fp2.queue_free()


# ---------------------------------------------------------------------------
# 22. Suboden Khan — Spear of Chogoris, Skilled Riders
# ---------------------------------------------------------------------------
func _section_suboden() -> void:
	print("\n-- 22. Spear of Chogoris, Skilled Riders --")
	_fresh(P_MOV)
	_place("U_OUTRIDER_SQUAD_A", 10, 10)
	_place("U_SUBODEN_KHAN_A", 10, 12)
	_check("Outriders alone: an advance blocks the charge", not EP.has_effect_advance_and_charge(_u("U_OUTRIDER_SQUAD_A")))
	_attach("U_SUBODEN_KHAN_A", "U_OUTRIDER_SQUAD_A")
	_check("Spear of Chogoris: advance does not prevent a charge (the Attached unit)", EP.has_effect_advance_and_charge(_u("U_OUTRIDER_SQUAD_A")))
	_check("Spear of Chogoris: ranged [ASSAULT]", EP.has_effect_advance_and_shoot(_u("U_OUTRIDER_SQUAD_A")))
	_check("no roll bonus without the assault doctrine", int(C.roll_bonus("U_OUTRIDER_SQUAD_A").bonus) == 0)
	_flags("U_SUBODEN_KHAN_A")["sw11e_doctrine"] = "assault"
	_check("assault doctrine active: +1 to advance and charge rolls", int(C.roll_bonus("U_OUTRIDER_SQUAD_A").bonus) == 1)
	C.on_phase_transition(P_CMD, P_MOV)
	_check("Skilled Riders: the unit has Mobile (the engine's MOBILE grant)", bool(_flags("U_OUTRIDER_SQUAD_A").get("ork11e_mobile", false)) and bool(_flags("U_SUBODEN_KHAN_A").get("ork11e_mobile", false)))
	_u("U_OUTRIDER_SQUAD_A")["attachment_data"] = {"attached_characters": []}
	_u("U_SUBODEN_KHAN_A").erase("attached_to")
	C.on_phase_transition(P_MOV, P_SHOOT)
	_check("Skilled Riders: removed from the bodyguard once Suboden left it", not bool(_flags("U_OUTRIDER_SQUAD_A").get("ork11e_mobile", false)) and bool(_flags("U_SUBODEN_KHAN_A").get("ork11e_mobile", false)))


# ---------------------------------------------------------------------------
# 23. Cato Sicarius, Aethon Shaan, Rhino — stratagem rules
# ---------------------------------------------------------------------------
func _section_cato_aethon_rhino() -> void:
	print("\n-- 23. Captain of the Honour Guard, Honour or Death, Blackwing Mantle, Veiling Smoke --")
	_fresh(P_CHG, 2)
	var cam = root.get_node("CharacterAttachmentManager")
	_check("Captain of the Honour Guard: Marneus Calgar in the army -> Cato is a Support", cam.attachment_role(_u("U_CATO_SICARIUS_A")) == "support")
	for m in _u("U_MARNEUS_CALGAR_A").models:
		m["alive"] = false
	_check("Captain of the Honour Guard: no Calgar -> Leader", cam.attachment_role(_u("U_CATO_SICARIUS_A")) == "leader")
	for m in _u("U_MARNEUS_CALGAR_A").models:
		m["alive"] = true
	var base: int = SM.preview_cp_cost(1, "heroic_intervention_11e", "U_INTERCESSOR_SQUAD_A")
	_check("Honour or Death: Heroic Intervention on Cato -1 CP (%d -> %d)" % [base, SM.preview_cp_cost(1, "heroic_intervention_11e", "U_CATO_SICARIUS_A")],
		SM.preview_cp_cost(1, "heroic_intervention_11e", "U_CATO_SICARIUS_A") == maxi(base - 1, 0))
	_check("Blackwing Mantle: Heroic Intervention on Aethon -1 CP regardless of other uses", bool(C.stratagem_override(1, "heroic_intervention_11e", "U_AETHON_SHAAN_A").get("applies", false)) \
		and SM.preview_cp_cost(1, "heroic_intervention_11e", "U_AETHON_SHAAN_A") == maxi(base - 1, 0))
	_flags("U_AETHON_SHAAN_A")["sm11e_abc_blackwing_stamp"] = C._phase_key()
	_check("Blackwing Mantle: once per phase (per army)", not bool(C.stratagem_override(1, "heroic_intervention_11e", "U_AETHON_SHAAN_A").get("applies", false)))
	_phase(P_SHOOT, 2)
	var sbase: int = SM.preview_cp_cost(1, "smokescreen_11e", "U_INTERCESSOR_SQUAD_A")
	_check("Veiling Smoke: Smokescreen on the Rhino -1 CP (%d -> %d)" % [sbase, SM.preview_cp_cost(1, "smokescreen_11e", "U_RHINO_A")], SM.preview_cp_cost(1, "smokescreen_11e", "U_RHINO_A") == maxi(sbase - 1, 0))
	var ov: Dictionary = C.stratagem_override(1, "smokescreen_11e", "U_RHINO_A")
	_check("Veiling Smoke: regardless of other uses (override)", bool(ov.get("applies", false)) and str(ov.get("source", "")) == "Veiling Smoke")
	_flags("U_RHINO_A")["sm11e_abc_veiling_smoke_stamp"] = C._phase_key()
	_check("Veiling Smoke: once per phase (per unit)", not bool(C.stratagem_override(1, "smokescreen_11e", "U_RHINO_A").get("applies", false)))
	_check("not on another unit", not bool(C.stratagem_override(1, "smokescreen_11e", "U_REPULSOR_A").get("applies", false)))


# ---------------------------------------------------------------------------
# 24. Kaius / Judiciar / Kayvaan
# ---------------------------------------------------------------------------
func _section_kaius_judiciar_kayvaan() -> void:
	print("\n-- 24. Tempormortis, Trifold Path of Shadow --")
	_fresh(P_FIGHT)
	var fs = load("res://scripts/rules/FightSequencer.gd").new()
	_check("Intercessors alone do not fight first", not fs.is_fights_first(_u("U_INTERCESSOR_SQUAD_A")))
	_attach("U_JUDICIAR_A", "U_INTERCESSOR_SQUAD_A")
	_check("Tempormortis: the Judiciar's Attached unit has Fights First", fs.is_fights_first(_u("U_INTERCESSOR_SQUAD_A")) and fs.is_fights_first(_u("U_JUDICIAR_A")))
	_place("U_KAYVAAN_SHRIKE_A", 10, 10)
	_check("Trifold Path of Shadow: Stealth", RE.has_stealth_ability(_u("U_KAYVAAN_SHRIKE_A")))
	_attach("U_KAYVAAN_SHRIKE_A", "U_ASSAULT_INTERCESSOR_SQUAD_A")
	_check("Trifold Path of Shadow: the Attached unit has Stealth", RE.has_stealth_ability(_u("U_ASSAULT_INTERCESSOR_SQUAD_A")))
	_check("Trifold Path of Shadow: -3\" detection range", C.detection_range_bonus(_u("U_KAYVAAN_SHRIKE_A")) == -3.0 and C.detection_range_bonus(_u("U_INTERCESSOR_SQUAD_A")) == 0.0)
	var tm = root.get_node("TerrainManager")
	var obs := {"position": {"x": 0, "y": 0}}
	if tm.has_method("detection_range_inches_for"):
		var d_k: float = tm.detection_range_inches_for(_u("U_KAYVAAN_SHRIKE_A").models[0], _u("U_KAYVAAN_SHRIKE_A"), obs)
		var d_i: float = tm.detection_range_inches_for(_u("U_INTERCESSOR_SQUAD_A").models[0], _u("U_INTERCESSOR_SQUAD_A"), obs)
		_check("TerrainManager detection range: %s\" vs %s\" (9\" floor)" % [d_k, d_i], d_k <= d_i and d_k >= 9.0)


# ---------------------------------------------------------------------------
# 25. Aquilon Optics (Gladiator Lancer), Total Obliteration (Eradicators)
# ---------------------------------------------------------------------------
func _section_aquilon_total_obliteration() -> void:
	print("\n-- 25. Aquilon Optics, Total Obliteration --")
	_fresh(P_SHOOT)
	_place("U_GLADIATOR_LANCER_A", 10, 10)
	_place("U_DEFF_DREAD_A", 10, 30)
	_place("U_BOYZ_B", 20, 30)
	_mods("U_GLADIATOR_LANCER_A", "U_DEFF_DREAD_A", false)
	var pt = _flags("U_GLADIATOR_LANCER_A").get("cus11e_prime_target", null)
	_check("vs a VEHICLE: one hit, one wound and one damage re-roll available", typeof(pt) == TYPE_DICTIONARY and pt.hit and pt.wound and pt.damage, str(pt))
	_mods("U_GLADIATOR_LANCER_A", "U_BOYZ_B", false)
	_check("vs an INFANTRY unit: none", not _flags("U_GLADIATOR_LANCER_A").has("cus11e_prime_target"))
	_mods("U_GLADIATOR_LANCER_A", "U_DEFF_DREAD_A", false)
	var cx = load("res://scripts/codex/custodes/CustodesCodex11e.gd")
	PM.apply_state_changes(cx.single_reroll_spend_diffs("U_GLADIATOR_LANCER_A", "hit"))
	_mods("U_GLADIATOR_LANCER_A", "U_BOYZ_B", false)
	_mods("U_GLADIATOR_LANCER_A", "U_DEFF_DREAD_A", false)
	pt = _flags("U_GLADIATOR_LANCER_A").get("cus11e_prime_target", {})
	_check("a spent re-roll stays spent across targets (hit spent, wound left)", not bool(pt.get("hit", true)) and bool(pt.get("wound", false)), str(pt))
	_check("not melee", not cx.single_reroll_available(_u("U_GLADIATOR_LANCER_A"), "wound", true))
	C.on_phase_transition(P_SHOOT, P_CHG)
	_check("expires at the end of the phase", not _flags("U_GLADIATOR_LANCER_A").has("cus11e_prime_target"))
	_phase(P_SHOOT)
	var helped := 0
	var ld := _weapon("U_GLADIATOR_LANCER_A", "laser destroyer", false)
	for sd in range(300, 330):
		var b_on: Dictionary = GS.state.duplicate(true)
		var b_off: Dictionary = GS.state.duplicate(true)
		b_off.units.U_GLADIATOR_LANCER_A.meta.abilities = b_off.units.U_GLADIATOR_LANCER_A.meta.abilities.filter(func(a): return str(a.get("name", "") if a is Dictionary else a) != "Aquilon Optics")
		b_off.units.U_GLADIATOR_LANCER_A.flags.erase("cus11e_prime_target")
		b_off.units.U_GLADIATOR_LANCER_A.flags.erase(C.F_AQUILON)
		_flags("U_GLADIATOR_LANCER_A").erase(C.F_AQUILON)
		var on := _shoot(b_on, "U_GLADIATOR_LANCER_A", ld, "U_DEFF_DREAD_A", sd)
		var off := _shoot(b_off, "U_GLADIATOR_LANCER_A", ld, "U_DEFF_DREAD_A", sd)
		if int(on.hits) > int(off.hits) or int(on.wounds) > int(off.wounds):
			helped += 1
	_check("A/B (30 seeds): the re-rolls turn a miss / failed wound around on some seeds (%d)" % helped, helped > 0)
	# Total Obliteration
	var rng = RE.RNGService.new(1)
	var low := {"value": 1, "rolled": true}
	var out: Dictionary = C.reroll_damage(low, "D6", _u("U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A"), rng, false)
	_check("Total Obliteration: a low damage roll (1 on D6) is re-rolled", out.has("sm11e_reroll_from"), str(out))
	_check("Total Obliteration: an above-average roll is kept", not C.reroll_damage({"value": 5, "rolled": true}, "D6", _u("U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A"), rng, false).has("sm11e_reroll_from"))
	_check("Total Obliteration: never melee, never another unit", not C.reroll_damage(low, "D6", _u("U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A"), rng, true).has("sm11e_reroll_from") \
		and not C.reroll_damage(low, "D6", _u("U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A"), rng, false).has("sm11e_reroll_from"))
	_check("Total Obliteration: a fixed damage value is not a roll", not C.reroll_damage({"value": 2, "rolled": false}, "2", _u("U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A"), rng, false).has("sm11e_reroll_from"))
	_place("U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A", 10, 20)
	var mr := _weapon("U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A", "melta rifle", false)
	var dmg_on := 0
	var dmg_off := 0
	for sd in range(500, 540):
		var b1: Dictionary = GS.state.duplicate(true)
		var b2: Dictionary = GS.state.duplicate(true)
		b2.units.U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A.meta.abilities = b2.units.U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A.meta.abilities.filter(func(a): return str(a.get("name", "") if a is Dictionary else a) != "Total Obliteration")
		dmg_on += int(_shoot(b1, "U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A", mr, "U_DEFF_DREAD_A", sd).res.get("damage_applied", 0))
		dmg_off += int(_shoot(b2, "U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A", mr, "U_DEFF_DREAD_A", sd).res.get("damage_applied", 0))
	_check("Total Obliteration A/B (40 seeds): damage %d with vs %d without (never less)" % [dmg_on, dmg_off], dmg_on >= dmg_off)


# ---------------------------------------------------------------------------
# 26. Raise the Banner / Honour of the Company
# ---------------------------------------------------------------------------
func _section_banner_objectives() -> void:
	print("\n-- 26. Raise the Banner, Honour of the Company --")
	_fresh(P_MOV)
	var op := _obj_pos(0)
	var oid := str(SWC.objectives()[0].get("id", ""))
	_place("U_ANCIENT_A", op.x, op.y)
	var oc_a: int = MM.model_oc(_u("U_ANCIENT_A"), _u("U_ANCIENT_A").models[0])
	_check("Honour of the Company: the Ancient has +1 OC (%d)" % oc_a, oc_a == int(_u("U_ANCIENT_A").meta.stats.objective_control) + 1)
	_attach("U_ANCIENT_A", "U_INTERCESSOR_SQUAD_A")
	_place("U_INTERCESSOR_SQUAD_A", op.x - 3, op.y + 1)
	_check("Honour of the Company: the Attached unit too", MM.model_oc(_u("U_INTERCESSOR_SQUAD_A"), _u("U_INTERCESSOR_SQUAD_A").models[0]) == int(_u("U_INTERCESSOR_SQUAD_A").meta.stats.objective_control) + 1)
	MM.check_all_objectives()
	_check("P1 controls the objective", SWC.objective_controller(oid) == 1, str(SWC.objective_controller(oid)))
	_check("not secured before", not bool(MM.is_objective_secured(oid).get("secured", false)))
	C.on_movement_phase_end(1)
	_check("Raise the Banner: end of your Movement phase -> the objective is secured", bool(MM.is_objective_secured(oid).get("secured", false)) and int(MM.is_objective_secured(oid).get("player", 0)) == 1)
	MM.clear_sticky_objectives_for_player(1)
	C.on_movement_phase_end(2)
	_check("not at the end of the opponent's Movement phase", not bool(MM.is_objective_secured(oid).get("secured", false)))
	_flags("U_ANCIENT_A")["battle_shocked"] = true
	C.on_movement_phase_end(1)
	_check("not while battle-shocked", not bool(MM.is_objective_secured(oid).get("secured", false)))
	MM.clear_sticky_objectives_for_player(1)


# ---------------------------------------------------------------------------
# 27. Strategium Command (Wardens of Ultramar) — Redeployment
# ---------------------------------------------------------------------------
func _section_strategium() -> void:
	print("\n-- 27. Strategium Command --")
	_fresh(P_FORM)
	_place("U_WARDENS_OF_ULTRAMAR_A", 10, 5)
	_place("U_INTERCESSOR_SQUAD_A", 14, 5)
	var fam = root.get_node("FactionAbilityManager")
	var entry: Dictionary = fam.get_redeploy_enhancement(1)
	_check("the redeploy entry is Strategium Command (3 units, ADEPTUS ASTARTES)", str(entry.get("name", "")) == "Strategium Command", str(entry))
	var elig: Array = fam.get_razgit_eligible_units(1).map(func(e): return str(e.unit_id))
	_check("deployed ADEPTUS ASTARTES units are eligible", "U_INTERCESSOR_SQUAD_A" in elig and "U_WARDENS_OF_ULTRAMAR_A" in elig, str(elig))
	_check("three redeploys", fam.get_razgit_redeploys_remaining(1) == 3)
	_check("the Redeployment phase lists them", "U_INTERCESSOR_SQUAD_A" in GS.get_redeploy_units_for_player(1))


# ---------------------------------------------------------------------------
# 28. gating
# ---------------------------------------------------------------------------
func _section_gating() -> void:
	print("\n-- 28. gating --")
	_fresh(P_FIGHT)
	var copy: Dictionary = _u("U_KOR_SARRO_KHAN_A").duplicate(true)
	copy["id"] = "X_KOR"
	copy["owner"] = 2
	GS.state.units["X_KOR"] = copy
	_place("X_KOR", 10, 10)
	_place("U_WARBOSS_A", 10, 11.3)
	_check("an M4c datasheet in a non-Space Marine army has no codex ability", not C.has(copy, "trophy_taker") and not "Trophy Taker" in _names(_mods("X_KOR", "U_WARBOSS_A", true)))
	GS.state.units.erase("X_KOR")
	GameConstants.edition = 10
	_check("edition 10: nothing", not C.has(_u("U_KOR_SARRO_KHAN_A"), "trophy_taker") and C.window_offers(1, "phase_start", {"phase": "command"}).is_empty())
	GameConstants.edition = 11
	C.offers_suppressed = true
	_phase(P_CMD)
	_place("U_CAPTAIN_ON_BIKE_A", 10, 40)
	_check("ScenarioRunner policy: offers suppressed -> no cards", C.window_offers(1, "phase_start", {"phase": "command"}).is_empty())
	C.offers_suppressed = false
	_check("phase_start_entries: queued for P1 when it has a card", C.phase_start_entries(P_CMD).map(func(e): return int(e.player)) == [1])


# ---------------------------------------------------------------------------
# 29. AI decisions (synchronous, never stalls)
# ---------------------------------------------------------------------------
func _section_ai() -> void:
	print("\n-- 29. AI --")
	var AID = load("res://scripts/AIDecisionMaker.gd")
	_fresh(P_CMD)
	_place("U_CAPTAIN_ON_BIKE_A", 10, 40)
	_place("U_BOYZ_B", 10, 50)
	var offers: Array = SM.get_all_window_offers(1, "phase_start", {"phase": "command"})
	var d: Dictionary = AID.decide_window_stratagem(1, "phase_start", offers, {"phase": "command"})
	_check("AI uses Strategic Acumen with a doctrine (variant chosen)", bool(d.get("use", false)) and str(d.get("stratagem_id", "")) == _sid("strategic_acumen") and str(d.get("context", {}).get("variant_id", "")) in SWC.DOCTRINES, str(d))
	_check("AI doctrine pick: assault for a melee unit 6-16\" from the enemy", C.ai_doctrine("U_CAPTAIN_ON_BIKE_A") in ["assault", "devastator"])
	var r: Dictionary = SM.use_stratagem(1, str(d.stratagem_id), str(d.target_unit_id), d.get("context", {}).merged({"window_id": "phase_start", "phase": "command"}))
	_check("the AI's choice is a legal use", r.get("success", false), str(r))
	_fresh(P_SHOOT)
	_place("U_VULKAN_HE_STAN_A", 10, 10)
	_place("U_DEFF_DREAD_A", 10, 25)
	_flags("U_VULKAN_HE_STAN_A")[C.F_SEEKER_OBJ] = str(SWC.objectives()[0].get("id", ""))
	var d2: Dictionary = AID.decide_window_stratagem(1, "phase_start", SM.get_all_window_offers(1, "phase_start", {"phase": "shooting"}), {"phase": "shooting"})
	_check("AI uses Forgefather on the VEHICLE first", bool(d2.get("use", false)) and str(d2.get("context", {}).get("secondary_id", "")) == "U_DEFF_DREAD_A", str(d2))
	_fresh(P_FIGHT)
	_place("U_CAPTAIN_TITUS_A", 10, 10)
	_place("U_BOYZ_B", 30, 30)
	_place("U_WARBOSS_A", 10, 11.3)
	var d3: Dictionary = AID.decide_window_stratagem(1, "unit_selected_to_fight", SM.get_all_window_offers(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_CAPTAIN_TITUS_A"}), {"phase": "fight", "unit_id": "U_CAPTAIN_TITUS_A"})
	_check("AI spends Righteous Fury vs an engaged CHARACTER", bool(d3.get("use", false)) and str(d3.get("stratagem_id", "")) == _sid("righteous_fury"), str(d3))
	_check("AI never takes a repositioning card (Purgation Run / Knight Champion / Glory) — scored 0", C.ai_score(1, _sid("purgation_run"), "", "", {}) == 0.0 and C.ai_score(1, _sid("glory_of_ultramar"), "", "", {}) == 0.0)
	_fresh(P_FIGHT, 2)
	_place("U_KAYVAAN_SHRIKE_A", 2, 2)
	_place("U_BOYZ_B", 40, 58)
	_check("AI Echo of the Ravenspire: no enemy within 12\", no objective in range -> uses it", C.ai_score(1, _sid("echo_of_the_ravenspire"), "U_KAYVAAN_SHRIKE_A", "fight_phase_end", {}) >= 1.0)
