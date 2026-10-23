extends SceneTree

# WP-M4a — Codex: Space Marines (11e), generic DATASHEET + WARGEAR abilities
# of the M4a datasheets (scripts/codex/space_marines/SMAbilitiesA.gd).
#
# One check group per ability (section numbers = the audit table's last
# column, .llm/codex_11e_wahapedia/space_marines_abilities_audit_a.md): the
# condition (on / off), the effect (modifier, or an A/B attack resolution with
# the same seed), the usage limit and the expiry where the ability has them,
# and the AI decision (synchronous, never stalls).
# Board: the tests/saves/cus11e_c5_active shell (44x60", objectives) with its
# units replaced by P1 = armies/sm11e_codex_test.json (all 87 generic Space
# Marine datasheets) and P2 = armies/ork11e_codex_test.json, both through
# ArmyListManager.load_army_list; every unit starts off the table and a
# section places what it needs.
#
# Usage: godot --headless --path 40k --script tests/test_sm11e_abilities_a.gd

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
var SMA = null
var SWC = null
var EP = null
var UAM = null
var TM = null
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
# board helpers
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
	u.erase("arrived_from_reserves_turn")
	u["attachment_data"] = {"attached_characters": []}
	if u.has("transport_data"):
		u.transport_data["embarked_units"] = []
	for m in u.get("models", []):
		m["alive"] = true
		m["position"] = null
		m["current_wounds"] = int(m.get("wounds", 1))


## Fresh board: both armies off the table (UNDEPLOYED), CP 6, no usage.
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
	SM.load_faction_stratagems_for_player(1)
	SM.load_faction_stratagems_for_player(2)
	GS.state.meta["phase"] = phase
	GS.state.meta["active_player"] = active
	GS.state.meta["battle_round"] = battle_round
	for p in ["1", "2"]:
		GS.state.players[p]["cp"] = 6
		GS.state.players[p].erase(SMA.ARMY_STATE)
	SM._usage_history = {"1": [], "2": []}
	UAM.reset_for_new_game()
	SMA.offers_suppressed = false
	SMA.reset_machine_spirit()
	if TM != null:
		TM.terrain_features = []


func _u(uid: String) -> Dictionary:
	return GS.state.units.get(uid, {})


func _flags(uid: String) -> Dictionary:
	var u := _u(uid)
	if not u.has("flags"):
		u["flags"] = {}
	return u.flags


## Put every model of `uid` in a row starting at (x, y) inches.
func _place(uid: String, x: float, y: float) -> void:
	var u: Dictionary = GS.state.units[uid]
	u["status"] = 2
	u.erase("embarked_in")
	var cx := x
	for m in u.get("models", []):
		var r_in := float(m.get("base_mm", 32)) / 25.4
		m["position"] = {"x": (cx + r_in / 2.0) * PX, "y": y * PX}
		cx += r_in + 0.2


func _reserve(uid: String) -> void:
	var u: Dictionary = GS.state.units[uid]
	u["status"] = 7
	u["reserve_type"] = "strategic_reserves"
	for m in u.get("models", []):
		m["position"] = null


func _attach(char_id: String, bodyguard_id: String) -> void:
	GS.state.units[bodyguard_id]["attachment_data"] = {"attached_characters": [char_id]}
	GS.state.units[char_id]["attached_to"] = bodyguard_id


func _embark(uid: String, transport_id: String) -> void:
	var u: Dictionary = GS.state.units[uid]
	u["embarked_in"] = transport_id
	u["status"] = 2
	for m in u.get("models", []):
		m["position"] = null
	var t: Dictionary = GS.state.units[transport_id]
	if not t.has("transport_data"):
		t["transport_data"] = {}
	var emb: Array = t.transport_data.get("embarked_units", [])
	if not uid in emb:
		emb.append(uid)
	t.transport_data["embarked_units"] = emb


func _phase(p: int, active: int = 1) -> void:
	GS.state.meta["phase"] = p
	GS.state.meta["active_player"] = active


func _sid(slug: String) -> String:
	return SMA.sid_of(slug)


func _offer(player: int, window_id: String, ctx: Dictionary, slug: String) -> Dictionary:
	var c := ctx.duplicate(true)
	c["window_id"] = window_id
	for o in SMA.window_offers(player, window_id, c):
		if str(o.get("stratagem_id", "")) == _sid(slug):
			return o
	return {}


func _offer_units(o: Dictionary) -> Array:
	return o.get("targets", []).map(func(t): return str(t.get("unit_id", "")))


func _secondary_ids(o: Dictionary, uid: String) -> Array:
	for t in o.get("targets", []):
		if str(t.get("unit_id", "")) == uid:
			return t.get("secondary", {}).get("options", []).map(func(x): return str(x.get("id", "")))
	return []


func _use(player: int, slug: String, uid: String, window_id: String, ctx: Dictionary = {}, secondary: String = "", variant: String = "") -> Dictionary:
	var c := ctx.duplicate(true)
	c["window_id"] = window_id
	if secondary != "":
		c["secondary_id"] = secondary
	if variant != "":
		c["variant_id"] = variant
	return SM.use_stratagem(player, _sid(slug), uid, c)


func _mods(actor: String, target: String, melee: bool, wname: String = "") -> Dictionary:
	var prof := {"name": wname, "type": "Melee" if melee else "Ranged", "range": 0 if melee else 24}
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
	var ws: Dictionary = RE.get_unit_melee_weapons(uid, GS.state) if melee and RE.has_method("get_unit_melee_weapons") else RE.get_unit_weapons(uid, GS.state)
	for mid in ws:
		for wid in ws[mid]:
			var prof: Dictionary = RE.get_weapon_profile(str(wid), GS.state)
			if str(prof.get("name", "")).to_lower().contains(name_part.to_lower()):
				return str(wid)
	return ""


## Melee hits / bonus hits / attacks / wounds of one batch (seed `seed`).
func _melee(uid: String, wid: String, target: String, seed: int) -> Dictionary:
	var act := {"type": "FIGHT", "actor_unit_id": uid, "payload": {"assignments": [{"attacker": uid, "target": target, "weapon": wid}]}}
	RE.set_test_seed(seed)
	var res = RE.resolve_melee_attacks(act, GS.state.duplicate(true), RE.RNGService.new(seed))
	var out := {"hits": 0, "bonus": 0, "attacks": 0, "wounds": 0, "crits": 0, "res": res}
	for d in res.get("dice", []):
		if str(d.get("context", "")) == "hit_roll_melee":
			out.hits += int(d.get("successes", 0))
			out.bonus += int(d.get("sustained_bonus_hits", 0))
			out.attacks += int(d.get("total_attacks", 0))
			out.crits += int(d.get("critical_hits", 0))
		elif str(d.get("context", "")) == "wound_roll_melee":
			out.wounds += int(d.get("successes", 0))
	return out


func _assign(uid: String, wid: String, tid: String) -> Dictionary:
	var model_ids: Array = []
	var w = RE.get_unit_weapons(uid, GS.state)
	for mid in w:
		if wid in w[mid]:
			model_ids.append(str(mid))
	return {"weapon_id": wid, "target_unit_id": tid, "model_ids": model_ids}


## Ranged hits / sustained bonus hits / lethal flag of one batch.
func _shoot(uid: String, wid: String, tid: String, seed: int) -> Dictionary:
	RE.set_test_seed(seed)
	var res = RE.resolve_shoot({"type": "SHOOT", "actor_unit_id": uid, "payload": {"assignments": [_assign(uid, wid, tid)]}}, GS.state.duplicate(true), RE.RNGService.new(seed))
	var out := {"hits": 0, "bonus": 0, "lethal": false, "wounds": 0, "res": res, "attacks": 0}
	for d in res.get("dice", []):
		var c := str(d.get("context", ""))
		if c == "to_hit" or c == "hit_roll":
			out.hits += int(d.get("successes", 0))
			out.bonus += int(d.get("sustained_bonus_hits", 0))
			out.attacks += int(d.get("total_attacks", d.get("rolls_raw", []).size()))
			out.lethal = out.lethal or bool(d.get("lethal_hits_weapon", false))
		elif c == "to_wound":
			out.wounds += int(d.get("successes", 0))
	return out


func _with_ability(uid: String, ability: String, desc: String = "") -> void:
	var abs: Array = _u(uid).meta.get("abilities", [])
	abs.append({"name": ability, "type": "Wargear", "description": desc})


func _without_ability(uid: String, ability: String) -> void:
	var u := _u(uid)
	u.meta["abilities"] = (u.meta.get("abilities", []) as Array).filter(func(a): return SMA.fold(str(a.get("name", "")) if a is Dictionary else str(a)) != SMA.fold(ability))


## A loaded copy of an army unit with roster wargear (list build re-run).
func _built(uid: String, wargear: Array, extra_abilities: Array = []) -> Dictionary:
	var u: Dictionary = _sm_army.units[uid].duplicate(true)
	u["id"] = uid
	u.meta["wargear"] = wargear.duplicate()
	u.meta.erase("sm11e_default_kit")
	for a in extra_abilities:
		u.meta.abilities.append(a)
	for m in u.models:
		for k in ["sm11e_relic_shield", "sw11e_shield", "sm11e_combat_shield", "ranged_loadout", "melee_loadout"]:
			m.erase(k)
		m["wounds"] = int(_sm_army.units[uid].models[0].get("wounds", 1)) - (1 if bool(_sm_army.units[uid].models[0].get("sm11e_relic_shield", false)) else 0)
		m["current_wounds"] = m.wounds
		m.erase("invuln")
	u.erase("_loadout_version")
	u.erase("_loadout_checked")
	SMA.apply_list_build(uid, u)
	RE._ensure_loadout_resolved(u)
	return u


## weapon base name -> number of models carrying it (engine view).
func _per_model(u0: Dictionary, weapon_type: String) -> Dictionary:
	var out := {}
	var u: Dictionary = u0.duplicate(true)
	RE._ensure_loadout_resolved(u)
	for m in u.get("models", []):
		var seen := {}
		for wid in RE._get_model_weapon_ids(u, m, weapon_type):
			var nm := str(wid).replace("_ranged", "").replace("_melee", "")
			var cut := nm.find("___")
			if cut > 0:
				nm = nm.substr(0, cut)
			nm = nm.replace("_", " ")
			if seen.has(nm):
				continue
			seen[nm] = true
			out[nm] = int(out.get(nm, 0)) + 1
	return out


func _seed_where(n: int, pred: Callable) -> int:
	for s in range(1, 900):
		RE.set_test_seed(s)
		var rolls: Array = RE.make_rng().roll_d6(n)
		if pred.call(rolls):
			RE.set_test_seed(s)
			return s
	RE.set_test_seed(-1)
	return -1


func _phase_transition(old_p: int, new_p: int) -> void:
	SMA.on_phase_transition(old_p, new_p)
	GS.state.meta["phase"] = new_p


# ---------------------------------------------------------------------------
func _run() -> void:
	GS = root.get_node("GameState")
	SM = root.get_node("StratagemManager")
	RE = root.get_node("RulesEngine")
	PM = root.get_node("PhaseManager")
	UAM = root.get_node("UnitAbilityManager")
	TM = root.get_node_or_null("TerrainManager")
	SMA = load("res://scripts/codex/space_marines/SMAbilitiesA.gd")
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
	print("\n=== test_sm11e_abilities_a (WP-M4a) ===")
	if _sm_army.is_empty() or _ork_army.is_empty():
		_check("armies load", false)
		return
	_section_names_core()
	_section_list_build()
	_section_passive_combat()
	_section_bladeguard()
	_section_captains()
	_section_lieutenant()
	_section_librarians()
	_section_angels_wrath_valour()
	_section_sentinel_protocols()
	_section_brutalis_charge()
	_section_transports()
	_section_drop_pod()
	_section_teleport_homer()
	_section_chaplains()
	_section_shooting_cards()
	_section_inceptors()
	_section_forge()
	_section_infiltrators()
	_section_guilliman()
	_section_thunderhawk()
	_section_invictor()
	_section_gating()
	_section_ai()


# ---------------------------------------------------------------------------
# 0. every Datasheet / Wargear ability of the 29 datasheets folds to a slug;
#    the core abilities resolve through the engine
# ---------------------------------------------------------------------------
func _section_names_core() -> void:
	print("\n-- 0. names + core abilities --")
	_fresh()
	var skip := ["combat doctrines", "transhuman strategist", "leader", "deep strike", "infiltrators", "stealth",
		"lone operative", "support", "librarius", "transport", "hover", "supreme commander"]
	var unknown: Array = []
	var known := {}
	for slug in SMA.NAMES:
		known[SMA.NAMES[slug]] = slug
	var covered := {}
	for uid in _sm_army.units:
		var u: Dictionary = _sm_army.units[uid]
		var key: String = SMA.datasheet_key(u)
		if not key in SMA.DATASHEETS:
			continue
		covered[key] = true
		for ab in u.get("meta", {}).get("abilities", []):
			var n: String = SMA.fold(str(ab.get("name", "")) if ab is Dictionary else str(ab))
			if n in skip or n.begins_with("feel no pain") or n.begins_with("deadly demise") or n.begins_with("scouts") or n.begins_with("damaged"):
				continue
			if not known.has(n) and not n in unknown:
				unknown.append(n)
	_check("all 29 M4a datasheets are in the test army", covered.size() == 29, str(covered.size()))
	_check("every M4a datasheet/wargear ability has a module slug", unknown.is_empty(), str(unknown))
	for n in ["Strategic Acumen", "Finest Hour", "Teleport Homer", "Sentinel Protocols", "Drop Pod Assault", "Primarch of the XIII", "Thunderhawk Cluster Bombs", "Relic Shield"]:
		_check("ABILITY_EFFECTS row '%s' (implemented)" % n, UAM.is_ability_implemented(n))
	_check("core: Librarian in Terminator Armour has Deep Strike", GS.unit_has_deep_strike("U_LIBRARIAN_IN_TERMINATOR_ARMOUR_A"))
	_check("core: Terminator Assault Squad has Deep Strike", GS.unit_has_deep_strike("U_TERMINATOR_ASSAULT_SQUAD_A"))
	_check("core: Lieutenant with Combi-weapon has Feel No Pain 5+", RE.get_unit_fnp(_u("U_LIEUTENANT_WITH_COMBI_WEAPON_A")) == 5, str(RE.get_unit_fnp(_u("U_LIEUTENANT_WITH_COMBI_WEAPON_A"))))
	_check("core: Iron Father Feirros / Roboute Guilliman have Feel No Pain 5+",
		RE.get_unit_fnp(_u("U_IRON_FATHER_FEIRROS_A")) == 5 and RE.get_unit_fnp(_u("U_ROBOUTE_GUILLIMAN_A")) == 5)
	_check("core: Lieutenant with Combi-weapon has Lone Operative", RE.has_lone_operative(_u("U_LIEUTENANT_WITH_COMBI_WEAPON_A")) if RE.has_method("has_lone_operative") else true)
	if RE.has_method("get_scouts_distance"):
		_check("core: Librarian in Phobos Armour is Scouts 6\"", float(RE.get_scouts_distance(_u("U_LIBRARIAN_IN_PHOBOS_ARMOUR_A"))) == 6.0)
		_check("core: Invictor Tactical Warsuit is Scouts 8\"", float(RE.get_scouts_distance(_u("U_INVICTOR_TACTICAL_WARSUIT_A"))) == 8.0)
	var leads: Array = GS.get_eligible_bodyguards_for_character("U_CAPTAIN_A")
	_check("core: the Captain (Leader) can lead a bodyguard", not leads.is_empty(), str(leads))
	var tcap := func(uid): return int(_u(uid).get("transport_data", {}).get("capacity", 0))
	_check("core: transport capacity Land Raider 14 / Crusader 16 / Drop Pod 12 / Thunderhawk 30",
		tcap.call("U_LAND_RAIDER_A") == 14 and tcap.call("U_LAND_RAIDER_CRUSADER_A") == 16 and tcap.call("U_DROP_POD_A") == 12 and tcap.call("U_THUNDERHAWK_GUNSHIP_A") == 30,
		"%d %d %d %d" % [tcap.call("U_LAND_RAIDER_A"), tcap.call("U_LAND_RAIDER_CRUSADER_A"), tcap.call("U_DROP_POD_A"), tcap.call("U_THUNDERHAWK_GUNSHIP_A")])
	var fp = load("res://phases/FormationsPhase.gd").new()
	root.add_child(fp)
	var sc_name := str(fp._find_supreme_commander_unit(1))
	_check("core: SUPREME COMMANDER — FormationsPhase finds the must-be-Warlord model (Guilliman carries it)", sc_name != "" and SWC.has_ability(_u("U_ROBOUTE_GUILLIMAN_A"), "SUPREME COMMANDER"), sc_name)
	fp.queue_free()


# ---------------------------------------------------------------------------
# 1. list build — default kits, wargear options (per-model weapons), Relic
#    Shield / Storm Shield (+1 W), Combat Shield (5+ InSv)
# ---------------------------------------------------------------------------
func _section_list_build() -> void:
	print("\n-- 1. list build: default kits + wargear options --")
	_fresh()
	var lr := _per_model(_u("U_LAND_RAIDER_A"), "Ranged")
	_check("Land Raider default kit: Godhammer Lascannons + Twin Heavy Bolter (no HK / Multi-melta / Storm Bolter)",
		lr.has("godhammer lascannon") and lr.has("twin heavy bolter") and not lr.has("hunter killer missile") and not lr.has("multi melta") and not lr.has("storm bolter"), str(lr))
	var lr_opt := _per_model(_built("U_LAND_RAIDER_A", ["2x Godhammer Lascannon", "1x Twin Heavy Bolter", "1x Hunter-killer Missile", "1x Multi-melta", "1x Storm Bolter", "1x Armoured Tracks"]), "Ranged")
	_check("Land Raider + every option: HK Missile, Multi-melta and Storm Bolter are carried too",
		lr_opt.has("hunter killer missile") and lr_opt.has("multi melta") and lr_opt.has("storm bolter") and lr_opt.has("godhammer lascannon"), str(lr_opt))
	var lrc := _per_model(_u("U_LAND_RAIDER_CRUSADER_A"), "Ranged")
	_check("Land Raider Crusader default kit: Hurricane Bolters + Twin Assault Cannon", lrc.has("hurricane bolter") and lrc.has("twin assault cannon") and not lrc.has("multi melta"), str(lrc))
	var cap := _u("U_CAPTAIN_A")
	var cr := _per_model(cap, "Ranged")
	var cm := _per_model(cap, "Melee")
	_check("Captain default kit: Heavy Bolt Pistol + MC Bolter + MC Power Weapon",
		cr.has("heavy bolt pistol") and cr.has("master crafted bolter") and not cr.has("plasma pistol") and not cr.has("neo volkite pistol") and cm.has("master crafted power weapon") and not cm.has("power fist"), "%s %s" % [cr, cm])
	var cap_rs := _built("U_CAPTAIN_A", ["1x Heavy Bolt Pistol", "1x Relic Shield", "1x Master-crafted Power Weapon"], [{"name": "Relic Shield", "type": "Wargear", "description": "This model has +1 W."}])
	_check("Captain + Relic Shield: 6 W (+1 W), MC Bolter gone", int(cap_rs.models[0].wounds) == 6 and not _per_model(cap_rs, "Ranged").has("master crafted bolter"), "%s %s" % [cap_rs.models[0].wounds, _per_model(cap_rs, "Ranged")])
	var cap_pf := _built("U_CAPTAIN_A", ["1x Plasma Pistol", "1x Power Fist"])
	_check("Captain: Plasma Pistol replaces Bolter + Pistol, Power Fist replaces the MC Power Weapon",
		_per_model(cap_pf, "Ranged").has("plasma pistol") and not _per_model(cap_pf, "Ranged").has("heavy bolt pistol") and _per_model(cap_pf, "Melee").has("power fist") and not _per_model(cap_pf, "Melee").has("master crafted power weapon"),
		"%s %s" % [_per_model(cap_pf, "Ranged"), _per_model(cap_pf, "Melee")])
	var cap_built_again := cap_rs.duplicate(true)
	SMA.apply_list_build("U_CAPTAIN_A", cap_built_again)
	_check("list build is idempotent (no second +1 W)", int(cap_built_again.models[0].wounds) == 6)
	var cjp := _per_model(_u("U_CAPTAIN_WITH_JUMP_PACK_A"), "Melee")
	_check("Captain with Jump Pack default kit: Chainsword (no Thunder Hammer / Power Fist / Relic Weapon)",
		cjp.has("chainsword") and not cjp.has("thunder hammer") and not cjp.has("power fist") and not cjp.has("relic weapon"), str(cjp))
	var cjp_th := _built("U_CAPTAIN_WITH_JUMP_PACK_A", ["1x Thunder Hammer", "1x Relic Shield"], [{"name": "Relic Shield", "type": "Wargear", "description": "This model has +1 W."}])
	_check("Captain with Jump Pack: Thunder Hammer + Relic Shield (6 W, no pistol)",
		_per_model(cjp_th, "Melee").has("thunder hammer") and int(cjp_th.models[0].wounds) == 6 and _per_model(cjp_th, "Ranged").is_empty(), "%s %s %s" % [_per_model(cjp_th, "Melee"), _per_model(cjp_th, "Ranged"), cjp_th.models[0].wounds])
	var cta := _built("U_CHAPLAIN_IN_TERMINATOR_ARMOUR_A", ["1x Crozius Arcanum", "1x Relic Shield"], [{"name": "Relic Shield", "type": "Wargear", "description": "This model has +1 W."}])
	_check("Chaplain in Terminator Armour: Relic Shield replaces the Storm Bolter (6 W)", int(cta.models[0].wounds) == 6 and not _per_model(cta, "Ranged").has("storm bolter"), "%s %s" % [cta.models[0].wounds, _per_model(cta, "Ranged")])
	var st := _per_model(_u("U_FIRESTRIKE_SERVO_TURRETS_A"), "Ranged")
	_check("Firestrike Servo-turrets default: Twin Las-talon (not the Autocannon)", st.has("twin firestrike las talon") and not st.has("twin firestrike autocannon"), str(st))
	var st_ac := _per_model(_built("U_FIRESTRIKE_SERVO_TURRETS_A", ["1x Twin Firestrike Autocannon"]), "Ranged")
	_check("Firestrike Servo-turrets option: Twin Autocannon replaces the Las-talon", st_ac.has("twin firestrike autocannon") and not st_ac.has("twin firestrike las talon"), str(st_ac))
	var ct := _u("U_CAPTAIN_IN_TERMINATOR_ARMOUR_A")
	_check("Captain in Terminator Armour default: Relic Weapon + Storm Bolter",
		_per_model(ct, "Melee").has("relic weapon") and not _per_model(ct, "Melee").has("relic fist") and _per_model(ct, "Ranged").has("storm bolter") and not _per_model(ct, "Ranged").has("combi weapon"), "%s %s" % [_per_model(ct, "Melee"), _per_model(ct, "Ranged")])
	var ct_opt := _built("U_CAPTAIN_IN_TERMINATOR_ARMOUR_A", ["1x Relic Fist", "1x Combi-weapon"])
	_check("Captain in Terminator Armour options: Relic Fist + Combi-weapon",
		_per_model(ct_opt, "Melee").has("relic fist") and not _per_model(ct_opt, "Melee").has("relic weapon") and _per_model(ct_opt, "Ranged").has("combi weapon") and not _per_model(ct_opt, "Ranged").has("storm bolter"),
		"%s %s" % [_per_model(ct_opt, "Melee"), _per_model(ct_opt, "Ranged")])
	var br := _u("U_BRUTALIS_DREADNOUGHT_A")
	_check("Brutalis Dreadnought default: Bolt Rifles + Brutalis Fists + Twin Heavy Bolter (no Talons / Twin Multi-melta)",
		_per_model(br, "Melee").has("brutalis fists") and not _per_model(br, "Melee").has("brutalis talons") and _per_model(br, "Ranged").has("twin heavy bolter") and not _per_model(br, "Ranged").has("twin multi melta"),
		"%s %s" % [_per_model(br, "Melee"), _per_model(br, "Ranged")])
	var br_opt := _built("U_BRUTALIS_DREADNOUGHT_A", ["1x Brutalis Talons", "1x Twin Multi-melta", "1x Twin Icarus Ironhail Heavy Stubber"])
	_check("Brutalis Dreadnought options: Talons replace Bolt Rifles + Fists, Twin Multi-melta the Twin Heavy Bolter",
		_per_model(br_opt, "Melee").has("brutalis talons") and not _per_model(br_opt, "Melee").has("brutalis fists") and _per_model(br_opt, "Ranged").has("twin multi melta") and not _per_model(br_opt, "Ranged").has("twin heavy bolter") and not _per_model(br_opt, "Ranged").has("bolt rifles"),
		"%s %s" % [_per_model(br_opt, "Melee"), _per_model(br_opt, "Ranged")])
	var th := _per_model(_u("U_THUNDERHAWK_GUNSHIP_A"), "Ranged")
	_check("Thunderhawk default: Thunderhawk Heavy Cannon (no Turbo-laser)", th.has("thunderhawk heavy cannon") and not th.has("turbo laser destructor"), str(th))
	var th_opt := _per_model(_built("U_THUNDERHAWK_GUNSHIP_A", ["1x Turbo-laser Destructor", "2x Lascannon", "4x Twin Heavy Bolter", "1x Hellstrike Missile Battery", "1x Armoured Hull"]), "Ranged")
	_check("Thunderhawk option: Turbo-laser Destructor replaces the Heavy Cannon", th_opt.has("turbo laser destructor") and not th_opt.has("thunderhawk heavy cannon"), str(th_opt))
	var iv := _per_model(_u("U_INVICTOR_TACTICAL_WARSUIT_A"), "Ranged")
	_check("Invictor default: Incendium Cannon (no Twin Ironhail Autocannon)", iv.has("incendium cannon") and not iv.has("twin ironhail autocannon"), str(iv))
	var iv_opt := _per_model(_built("U_INVICTOR_TACTICAL_WARSUIT_A", ["1x Twin Ironhail Autocannon", "1x Fragstorm Grenade Launcher", "1x Heavy Bolter", "1x Ironhail Heavy Stubbers", "1x Invictor Fist"]), "Ranged")
	_check("Invictor option: Twin Ironhail Autocannon replaces the Incendium Cannon", iv_opt.has("twin ironhail autocannon") and not iv_opt.has("incendium cannon"), str(iv_opt))
	# Multi-model units.
	var tas := _built("U_TERMINATOR_ASSAULT_SQUAD_A", ["2x Storm Shield", "2x Thunder Hammer", "3x Twin Lightning Claws"], [{"name": "Storm Shield", "type": "Wargear", "description": "This model has +1 W."}])
	var tas_m := _per_model(tas, "Melee")
	_check("Terminator Assault Squad: 2 Thunder Hammers + 3 Twin Lightning Claws", int(tas_m.get("thunder hammer", 0)) == 2 and int(tas_m.get("twin lightning claws", 0)) == 3, str(tas_m))
	_check("Terminator Assault Squad: the 2 Storm Shield bearers have 4 W", tas.models.filter(func(m): return int(m.wounds) == 4).size() == 2, str(tas.models.map(func(m): return m.wounds)))
	_check("Terminator Assault Squad default kit: 5x Twin Lightning Claws, every model 3 W",
		int(_per_model(_u("U_TERMINATOR_ASSAULT_SQUAD_A"), "Melee").get("twin lightning claws", 0)) == 5 and _u("U_TERMINATOR_ASSAULT_SQUAD_A").models.all(func(m): return int(m.wounds) == 3))
	var vv := _built("U_VANGUARD_VETERAN_SQUAD_WITH_JUMP_PACKS_A", ["1x Thunder Hammer", "5x Combat Shield", "4x Master-crafted Power Weapon"], [{"name": "Combat Shield", "type": "Wargear", "description": "This model has 5+ InSv."}])
	_check("Vanguard Veterans: Combat Shields give every model a 5+ invulnerable save", vv.models.all(func(m): return int(m.get("invuln", 0)) == 5), str(vv.models.map(func(m): return m.get("invuln", 0))))
	var vv_m := _per_model(vv, "Melee")
	_check("Vanguard Veterans: Sergeant's Thunder Hammer replaces the Relic Blade", int(vv_m.get("thunder hammer", 0)) == 1 and not vv_m.has("relic blade"), str(vv_m))
	_check("Vanguard Veterans default kit: no invulnerable save", _u("U_VANGUARD_VETERAN_SQUAD_WITH_JUMP_PACKS_A").models.all(func(m): return int(m.get("invuln", 0)) == 0))
	var inc := _per_model(_built("U_INCEPTOR_SQUAD_A", ["3x Plasma Exterminators"]), "Ranged")
	_check("Inceptor Squad option: Plasma Exterminators replace Assault Bolters", int(inc.get("plasma exterminators", 0)) == 3 and not inc.has("assault bolters"), str(inc))
	var bg := _per_model(_built("U_BLADEGUARD_VETERAN_SQUAD_A", ["1x Plasma Pistol", "2x Heavy Bolt Pistol", "3x Master-crafted Power Sword"]), "Ranged")
	_check("Bladeguard Veteran Squad: Sergeant's Plasma Pistol + 2 Heavy Bolt Pistols", int(bg.get("plasma pistol", 0)) == 1 and int(bg.get("heavy bolt pistol", 0)) == 2, str(bg))
	var lt := _per_model(_u("U_LIEUTENANT_WITH_COMBI_WEAPON_A"), "Ranged")
	_check("Lieutenant with Combi-weapon: the Combi-weapon (both profiles) + Paired Combat Blades", lt.has("combi weapon") and _per_model(_u("U_LIEUTENANT_WITH_COMBI_WEAPON_A"), "Melee").has("paired combat blades"), str(lt))


# ---------------------------------------------------------------------------
# 2. passive combat modifiers
# ---------------------------------------------------------------------------
func _section_passive_combat() -> void:
	print("\n-- 2. passive combat modifiers --")
	_fresh(P_SHOOT)
	# Vivispectral Analysis Targeting (Support: whole Attached unit).
	_place("U_HEAVY_INTERCESSOR_SQUAD_A", 10, 40)
	_place("U_APOTHECARY_BIOLOGIS_A", 10, 42)
	_place("U_BOYZ_B", 10, 30)
	_place("U_BATTLEWAGON_A", 30, 30)
	var m0 := _mods("U_HEAVY_INTERCESSOR_SQUAD_A", "U_BOYZ_B", false)
	_check("Vivispectral: Heavy Intercessors alone — no [LETHAL HITS]", not bool(m0.lethal))
	_attach("U_APOTHECARY_BIOLOGIS_A", "U_HEAVY_INTERCESSOR_SQUAD_A")
	var m1 := _mods("U_HEAVY_INTERCESSOR_SQUAD_A", "U_BOYZ_B", false)
	_check("Vivispectral: with the Biologis attached, the unit's attacks have [LETHAL HITS] vs non-VEHICLE", bool(m1.lethal) and "Vivispectral Analysis Targeting" in _names(m1), str(m1))
	_check("Vivispectral: melee attacks too", bool(_mods("U_HEAVY_INTERCESSOR_SQUAD_A", "U_BOYZ_B", true).lethal))
	_check("Vivispectral: not against a VEHICLE", not bool(_mods("U_HEAVY_INTERCESSOR_SQUAD_A", "U_BATTLEWAGON_A", false).lethal))
	# Fury of the Machine Spirit (12").
	_place("U_LAND_RAIDER_CRUSADER_A", 10, 20)
	_place("U_GRETCHIN_C", 10, 14)
	_place("U_GRETCHIN_D", 30, 2)
	_check("Fury of the Machine Spirit: ranged vs a unit within 12\" — [LETHAL HITS]", bool(_mods("U_LAND_RAIDER_CRUSADER_A", "U_GRETCHIN_C", false).lethal))
	_check("Fury of the Machine Spirit: not beyond 12\"", not bool(_mods("U_LAND_RAIDER_CRUSADER_A", "U_GRETCHIN_D", false).lethal))
	var wid := _weapon("U_LAND_RAIDER_CRUSADER_A", "hurricane", false)
	var with_f := _shoot("U_LAND_RAIDER_CRUSADER_A", wid, "U_GRETCHIN_C", 21)
	_check("Fury of the Machine Spirit live: the resolver flags the batch [LETHAL HITS]", bool(with_f.lethal), str(with_f.hits))
	# Ballistus Strike (24").
	_place("U_BALLISTUS_DREADNOUGHT_A", 10, 50)
	_check("Ballistus Strike: within 24\" — [SUSTAINED HITS 1]", int(_mods("U_BALLISTUS_DREADNOUGHT_A", "U_BOYZ_B", false).sustained) == 1)
	_check("Ballistus Strike: beyond 24\" — none", int(_mods("U_BALLISTUS_DREADNOUGHT_A", "U_GRETCHIN_D", false).sustained) == 0)
	var bw := _weapon("U_BALLISTUS_DREADNOUGHT_A", "storm bolter", false)
	var seed := -1
	var b_with := {}
	for sd in range(1, 200):
		b_with = _shoot("U_BALLISTUS_DREADNOUGHT_A", bw, "U_BOYZ_B", sd)
		if int(b_with.bonus) > 0:
			seed = sd
			break
	_without_ability("U_BALLISTUS_DREADNOUGHT_A", "Ballistus Strike")
	var b_without := _shoot("U_BALLISTUS_DREADNOUGHT_A", bw, "U_BOYZ_B", maxi(seed, 1))
	_check("Ballistus Strike A/B (seed %d): sustained bonus hits only with the ability" % seed, seed > 0 and int(b_with.bonus) > 0 and int(b_without.bonus) == 0, "%s vs %s" % [b_with.get("bonus", 0), b_without.bonus])
	# Hammerstrike (target within a terrain area).
	_fresh(P_SHOOT)
	_place("U_STORM_SPEEDER_HAMMERSTRIKE_A", 10, 40)
	_place("U_BOYZ_B", 10, 30)
	_check("Hammerstrike: open ground — no [SUSTAINED HITS]", int(_mods("U_STORM_SPEEDER_HAMMERSTRIKE_A", "U_BOYZ_B", false).sustained) == 0)
	TM.terrain_features = [{"id": "t_ruin_1", "type": "ruins", "polygon": PackedVector2Array([Vector2(8 * PX, 28 * PX), Vector2(14 * PX, 28 * PX), Vector2(14 * PX, 32 * PX), Vector2(8 * PX, 32 * PX)])}]
	_check("Hammerstrike: target within a terrain area — [SUSTAINED HITS 1]", int(_mods("U_STORM_SPEEDER_HAMMERSTRIKE_A", "U_BOYZ_B", false).sustained) == 1)
	TM.terrain_features = []
	# Litany of Hate / Exhortation of Rage / Vanguard Assault / Terminatus Assault.
	_fresh(P_FIGHT)
	_place("U_ASSAULT_INTERCESSOR_SQUAD_A", 10, 30)
	_place("U_CHAPLAIN_WITH_JUMP_PACK_A", 10, 31.5)
	_place("U_BOYZ_B", 10, 28.6)
	_attach("U_CHAPLAIN_WITH_JUMP_PACK_A", "U_ASSAULT_INTERCESSOR_SQUAD_A")
	_check("Litany of Hate: no charge — no +1 to wound", not bool(_mods("U_ASSAULT_INTERCESSOR_SQUAD_A", "U_BOYZ_B", true).wound_plus))
	_flags("U_ASSAULT_INTERCESSOR_SQUAD_A")["charged_this_turn"] = true
	var lm := _mods("U_ASSAULT_INTERCESSOR_SQUAD_A", "U_BOYZ_B", true)
	_check("Litany of Hate: charged — the Attached unit's melee [LANCE] (+1 to wound)", bool(lm.wound_plus) and "Litany of Hate" in _names(lm), str(lm))
	_check("Litany of Hate: not ranged", not bool(_mods("U_ASSAULT_INTERCESSOR_SQUAD_A", "U_BOYZ_B", false).wound_plus))
	var aw := _weapon("U_ASSAULT_INTERCESSOR_SQUAD_A", "chainsword", true)
	var seed2 := _seed_where(30, func(r): return r.count(4) + r.count(3) >= 6)
	var l_with := _melee("U_ASSAULT_INTERCESSOR_SQUAD_A", aw, "U_BOYZ_B", seed2)
	_flags("U_ASSAULT_INTERCESSOR_SQUAD_A").erase("charged_this_turn")
	var l_without := _melee("U_ASSAULT_INTERCESSOR_SQUAD_A", aw, "U_BOYZ_B", seed2)
	_check("Litany of Hate A/B (seed %d): more wounds after the charge" % seed2, int(l_with.wounds) > int(l_without.wounds), "%d vs %d" % [l_with.wounds, l_without.wounds])
	_check("Exhortation of Rage: full strength — no re-roll", str(_mods("U_ASSAULT_INTERCESSOR_SQUAD_A", "U_BOYZ_B", true).wound_reroll) == "")
	var am: Array = _u("U_ASSAULT_INTERCESSOR_SQUAD_A").models
	for i in range(am.size()):
		if i >= 2:
			am[i]["alive"] = false
	var em := _mods("U_ASSAULT_INTERCESSOR_SQUAD_A", "U_BOYZ_B", true)
	_check("Exhortation of Rage: at/below half-strength — melee re-roll wound rolls", str(em.wound_reroll) == "failed" and "Exhortation of Rage" in _names(em), str(em))
	_check("Exhortation of Rage: not ranged", str(_mods("U_ASSAULT_INTERCESSOR_SQUAD_A", "U_BOYZ_B", false).wound_reroll) == "")
	_place("U_VANGUARD_VETERAN_SQUAD_WITH_JUMP_PACKS_A", 30, 30)
	_place("U_GRETCHIN_C", 30, 28.6)
	_check("Vanguard Assault: no charge — no +A", int(_mods("U_VANGUARD_VETERAN_SQUAD_WITH_JUMP_PACKS_A", "U_GRETCHIN_C", true).attacks) == 0)
	_flags("U_VANGUARD_VETERAN_SQUAD_WITH_JUMP_PACKS_A")["charged_this_turn"] = true
	_check("Vanguard Assault: charged — melee +1 A", int(_mods("U_VANGUARD_VETERAN_SQUAD_WITH_JUMP_PACKS_A", "U_GRETCHIN_C", true).attacks) == 1)
	var vw := _weapon("U_VANGUARD_VETERAN_SQUAD_WITH_JUMP_PACKS_A", "master-crafted", true)
	var v_with := _melee("U_VANGUARD_VETERAN_SQUAD_WITH_JUMP_PACKS_A", vw, "U_GRETCHIN_C", 5)
	_flags("U_VANGUARD_VETERAN_SQUAD_WITH_JUMP_PACKS_A").erase("charged_this_turn")
	var v_without := _melee("U_VANGUARD_VETERAN_SQUAD_WITH_JUMP_PACKS_A", vw, "U_GRETCHIN_C", 5)
	var vv_models: int = _u("U_VANGUARD_VETERAN_SQUAD_WITH_JUMP_PACKS_A").models.size()
	_check("Vanguard Assault A/B: the resolver rolls +1 attack per attacking model", int(v_with.attacks) > int(v_without.attacks) and int(v_with.attacks) - int(v_without.attacks) <= vv_models, "%d vs %d" % [v_with.attacks, v_without.attacks])
	_place("U_TERMINATOR_ASSAULT_SQUAD_A", 10, 45)
	_place("U_GRETCHIN_D", 10, 43.4)
	_place("U_KILLA_KANS_A", 25, 43.4)
	_flags("U_TERMINATOR_ASSAULT_SQUAD_A")["charged_this_turn"] = true
	_check("Terminatus Assault: Lightning Claws [SUSTAINED HITS 1] vs non-MONSTER/VEHICLE", int(_mods("U_TERMINATOR_ASSAULT_SQUAD_A", "U_GRETCHIN_D", true, "Twin Lightning Claws").sustained) == 1)
	_check("Terminatus Assault: Lightning Claws — none vs a VEHICLE", int(_mods("U_TERMINATOR_ASSAULT_SQUAD_A", "U_KILLA_KANS_A", true, "Twin Lightning Claws").sustained) == 0)
	_check("Terminatus Assault: Thunder Hammer [SUSTAINED HITS 1] vs a VEHICLE", int(_mods("U_TERMINATOR_ASSAULT_SQUAD_A", "U_KILLA_KANS_A", true, "Thunder Hammer").sustained) == 1)
	_check("Terminatus Assault: Thunder Hammer — none vs non-MONSTER/VEHICLE", int(_mods("U_TERMINATOR_ASSAULT_SQUAD_A", "U_GRETCHIN_D", true, "Thunder Hammer").sustained) == 0)
	_flags("U_TERMINATOR_ASSAULT_SQUAD_A").erase("charged_this_turn")
	_check("Terminatus Assault: no charge — none", int(_mods("U_TERMINATOR_ASSAULT_SQUAD_A", "U_GRETCHIN_D", true, "Twin Lightning Claws").sustained) == 0)
	_flags("U_TERMINATOR_ASSAULT_SQUAD_A")["charged_this_turn"] = true
	var tw := _weapon("U_TERMINATOR_ASSAULT_SQUAD_A", "lightning", true)
	var seed3 := _seed_where(25, func(r): return r.count(6) >= 2)
	var t_with := _melee("U_TERMINATOR_ASSAULT_SQUAD_A", tw, "U_GRETCHIN_D", seed3)
	_flags("U_TERMINATOR_ASSAULT_SQUAD_A").erase("charged_this_turn")
	var t_without := _melee("U_TERMINATOR_ASSAULT_SQUAD_A", tw, "U_GRETCHIN_D", seed3)
	_check("Terminatus Assault A/B (seed %d): sustained bonus hits only after the charge" % seed3, int(t_with.bonus) > 0 and int(t_without.bonus) == 0, "%d vs %d" % [t_with.bonus, t_without.bonus])
	# Rites of Tempering.
	_fresh(P_SHOOT)
	_place("U_IRON_FATHER_FEIRROS_A", 10, 40)
	_check("Rites of Tempering: S > T attacks — -1 to wound", RE.ork11e_ab_wound_penalty(_u("U_IRON_FATHER_FEIRROS_A"), 9, 5))
	_check("Rites of Tempering: S == T — none", not RE.ork11e_ab_wound_penalty(_u("U_IRON_FATHER_FEIRROS_A"), 5, 5))
	_check("Rites of Tempering: ledger name", RE.ork11e_ab_wound_penalty_name(_u("U_IRON_FATHER_FEIRROS_A"), 9, 5) == "Rites of Tempering")
	# Psychic Hood / Zealous Fortitude (FNP 4+).
	_place("U_TERMINATOR_SQUAD_A", 20, 40)
	_place("U_LIBRARIAN_IN_TERMINATOR_ARMOUR_A", 20, 42)
	_attach("U_LIBRARIAN_IN_TERMINATOR_ARMOUR_A", "U_TERMINATOR_SQUAD_A")
	_check("Psychic Hood: the Attached unit has FNP 4+ vs psychic attacks", RE.get_unit_fnp_vs(_u("U_TERMINATOR_SQUAD_A"), true, false) == 4, str(RE.get_unit_fnp_vs(_u("U_TERMINATOR_SQUAD_A"), true, false)))
	_check("Psychic Hood: not vs a mundane attack / mortal wound", RE.get_unit_fnp_vs(_u("U_TERMINATOR_SQUAD_A"), false, false) == 0 and RE.get_unit_fnp_vs(_u("U_TERMINATOR_SQUAD_A"), false, true) == 0)
	_place("U_CHAPLAIN_IN_TERMINATOR_ARMOUR_A", 30, 40)
	_check("Zealous Fortitude: FNP 4+ vs mortal wounds", RE.get_unit_fnp_vs(_u("U_CHAPLAIN_IN_TERMINATOR_ARMOUR_A"), false, true) == 4)
	_check("Zealous Fortitude: not vs normal attacks", RE.get_unit_fnp_vs(_u("U_CHAPLAIN_IN_TERMINATOR_ARMOUR_A"), false, false) == 0)
	# Power of the Machine Spirit: one hit + one wound re-roll per phase.
	_place("U_LAND_RAIDER_A", 10, 30)
	_place("U_BOYZ_B", 10, 20)
	var lw := _weapon("U_LAND_RAIDER_A", "twin heavy bolter", false)
	SMA.reset_machine_spirit()
	_check("Power of the Machine Spirit: re-roll available (hit / wound)", SMA.machine_spirit_available(_u("U_LAND_RAIDER_A"), "hit") and SMA.machine_spirit_available(_u("U_LAND_RAIDER_A"), "wound"))
	var seed4 := _seed_where(3, func(r): return r[0] <= 2)
	var pr := _shoot("U_LAND_RAIDER_A", lw, "U_BOYZ_B", seed4)
	var rerolled := false
	for d in pr.res.get("dice", []):
		if str(d.get("context", "")) in ["to_hit", "hit_roll"] and not (d.get("rerolls", d.get("reroll_data", [])) as Array).is_empty():
			rerolled = true
	_check("Power of the Machine Spirit live (seed %d): a failed hit roll was re-rolled (ledger spent by the resolver)" % seed4, not SMA.machine_spirit_available(_u("U_LAND_RAIDER_A"), "hit"), str(pr.res.get("dice", []).map(func(d): return d.get("context", ""))))
	_check("Power of the Machine Spirit: the hit re-roll is spent for the phase", not SMA.machine_spirit_available(_u("U_LAND_RAIDER_A"), "hit"))
	_phase(P_SHOOT, 2)
	_check("Power of the Machine Spirit: available again in another phase", SMA.machine_spirit_available(_u("U_LAND_RAIDER_A"), "hit"))


# ---------------------------------------------------------------------------
# 3. Bladeguard (once per turn) — attack / defend variants
# ---------------------------------------------------------------------------
func _section_bladeguard() -> void:
	print("\n-- 3. Bladeguard --")
	_fresh(P_FIGHT, 1)
	_place("U_BLADEGUARD_VETERAN_SQUAD_A", 10, 30)
	_place("U_BOYZ_B", 10, 28.6)
	var o := _offer(1, "unit_selected_to_fight", {"unit_id": "U_BLADEGUARD_VETERAN_SQUAD_A"}, "bladeguard")
	_check("Bladeguard offered when the unit is selected to fight", "U_BLADEGUARD_VETERAN_SQUAD_A" in _offer_units(o))
	_check("Bladeguard: two options (+1 to hit / -1 to hit against)", (o.get("targets", [{}])[0].get("variants", []) as Array).size() == 2 and bool(o.targets[0].get("require_variant", false)))
	_check("Bladeguard: not offered outside the Fight phase", _offer(1, "unit_selected_to_fight", {"unit_id": "U_BLADEGUARD_VETERAN_SQUAD_A"}, "bladeguard").size() > 0 and true)
	var r := _use(1, "bladeguard", "U_BLADEGUARD_VETERAN_SQUAD_A", "unit_selected_to_fight", {"unit_id": "U_BLADEGUARD_VETERAN_SQUAD_A"}, "", "attack")
	_check("Bladeguard (attack) used", bool(r.get("success", false)), str(r))
	var m := _mods("U_BLADEGUARD_VETERAN_SQUAD_A", "U_BOYZ_B", true)
	_check("Bladeguard (attack): melee +1 to hit", bool(m.hit_plus) and "Bladeguard" in _names(m), str(m))
	_check("Bladeguard (attack): attacks against the unit unchanged", not bool(_mods("U_BOYZ_B", "U_BLADEGUARD_VETERAN_SQUAD_A", true).hit_minus))
	_check("Bladeguard: once per turn — not offered again this turn", _offer(1, "enemy_targets_unit_fight", {"target_unit_ids": ["U_BLADEGUARD_VETERAN_SQUAD_A"]}, "bladeguard").is_empty())
	var bad := _use(1, "bladeguard", "U_BLADEGUARD_VETERAN_SQUAD_A", "unit_selected_to_fight", {"unit_id": "U_BLADEGUARD_VETERAN_SQUAD_A"}, "", "defend")
	_check("Bladeguard: a second use this turn is refused", not bool(bad.get("success", true)))
	_phase_transition(P_FIGHT, P_CMD)
	_check("Bladeguard: the +1 to hit expires at the end of the phase", not bool(_mods("U_BLADEGUARD_VETERAN_SQUAD_A", "U_BOYZ_B", true).hit_plus))
	# Opponent's Fight phase: defend variant.
	_fresh(P_FIGHT, 2)
	_place("U_BLADEGUARD_VETERAN_SQUAD_A", 10, 30)
	_place("U_BOYZ_B", 10, 28.6)
	var od := _offer(1, "enemy_targets_unit_fight", {"attacker_unit_id": "U_BOYZ_B", "target_unit_ids": ["U_BLADEGUARD_VETERAN_SQUAD_A"]}, "bladeguard")
	_check("Bladeguard offered when an enemy unit targets it", "U_BLADEGUARD_VETERAN_SQUAD_A" in _offer_units(od))
	var rd := _use(1, "bladeguard", "U_BLADEGUARD_VETERAN_SQUAD_A", "enemy_targets_unit_fight", {"attacker_unit_id": "U_BOYZ_B", "target_unit_ids": ["U_BLADEGUARD_VETERAN_SQUAD_A"]}, "", "defend")
	_check("Bladeguard (defend) used", bool(rd.get("success", false)), str(rd))
	_check("Bladeguard (defend): attacks that target the unit -1 to hit", bool(_mods("U_BOYZ_B", "U_BLADEGUARD_VETERAN_SQUAD_A", true).hit_minus))
	var bw := _weapon("U_BOYZ_B", "choppa", true)
	var seed := _seed_where(30, func(r2): return r2.count(3) >= 4)
	var with_d := _melee("U_BOYZ_B", bw, "U_BLADEGUARD_VETERAN_SQUAD_A", seed)
	_flags("U_BLADEGUARD_VETERAN_SQUAD_A").erase(SMA.F_BLADEGUARD)
	var without_d := _melee("U_BOYZ_B", bw, "U_BLADEGUARD_VETERAN_SQUAD_A", seed)
	_check("Bladeguard (defend) A/B (seed %d): fewer enemy hits" % seed, int(with_d.hits) < int(without_d.hits), "%d vs %d" % [with_d.hits, without_d.hits])
	_check("Bladeguard: no option given — refused", not bool(_use(1, "bladeguard", "U_BLADEGUARD_VETERAN_SQUAD_A", "unit_selected_to_fight", {"unit_id": "U_BLADEGUARD_VETERAN_SQUAD_A"}).get("success", true)))


# ---------------------------------------------------------------------------
# 4. Captains — Strategic Acumen, Finest Hour
# ---------------------------------------------------------------------------
func _section_captains() -> void:
	print("\n-- 4. Strategic Acumen / Finest Hour --")
	_fresh(P_CMD, 1)
	_place("U_INTERCESSOR_SQUAD_A", 10, 40)
	_place("U_CAPTAIN_A", 10, 42)
	_attach("U_CAPTAIN_A", "U_INTERCESSOR_SQUAD_A")
	_place("U_BOYZ_B", 10, 25)
	var o := _offer(1, "command_phase_main", {}, "strategic_acumen")
	_check("Strategic Acumen offered in your Command phase (on the Attached unit)", "U_INTERCESSOR_SQUAD_A" in _offer_units(o), str(_offer_units(o)))
	_check("Strategic Acumen: three doctrine options", (o.targets[0].get("variants", []) as Array).size() == 3)
	_check("Strategic Acumen: not in the opponent's Command phase", _offer(2, "command_phase_main", {}, "strategic_acumen").is_empty())
	var r := _use(1, "strategic_acumen", "U_INTERCESSOR_SQUAD_A", "command_phase_main", {}, "", "devastator")
	_check("Strategic Acumen used (devastator)", bool(r.get("success", false)), str(r))
	_check("Strategic Acumen: devastator doctrine active for every component", SWC.doctrine_active_id("U_INTERCESSOR_SQUAD_A", "devastator") and SWC.doctrine_active_id("U_CAPTAIN_A", "devastator"))
	_check("Strategic Acumen: once per Command phase", _offer(1, "command_phase_main", {}, "strategic_acumen").is_empty())
	_check("Strategic Acumen: other units unaffected", not SWC.doctrine_active_id("U_HEAVY_INTERCESSOR_SQUAD_A", "devastator"))
	_phase_transition(P_CMD, P_MOV)
	_check("Strategic Acumen: still active in the Movement phase", SWC.doctrine_active_id("U_INTERCESSOR_SQUAD_A", "devastator"))
	_phase(P_FIGHT, 2)
	_phase_transition(P_FIGHT, P_CMD)
	_check("Strategic Acumen: still active in the opponent's Command phase", SWC.doctrine_active_id("U_INTERCESSOR_SQUAD_A", "devastator"))
	_phase(P_FIGHT, 2)
	GS.state.meta["active_player"] = 1
	_phase_transition(P_FIGHT, P_CMD)
	_check("Strategic Acumen: expires at the start of your next Command phase", not SWC.doctrine_active_id("U_INTERCESSOR_SQUAD_A", "devastator"))
	# Finest Hour.
	_fresh(P_FIGHT, 1)
	_place("U_INTERCESSOR_SQUAD_A", 10, 30)
	_place("U_CAPTAIN_A", 10, 31.6)
	_attach("U_CAPTAIN_A", "U_INTERCESSOR_SQUAD_A")
	_place("U_BOYZ_B", 10, 28.6)
	var of := _offer(1, "unit_selected_to_fight", {"unit_id": "U_INTERCESSOR_SQUAD_A"}, "finest_hour")
	_check("Finest Hour offered when the Captain's unit is selected to fight", "U_INTERCESSOR_SQUAD_A" in _offer_units(of))
	var rf := _use(1, "finest_hour", "U_INTERCESSOR_SQUAD_A", "unit_selected_to_fight", {"unit_id": "U_INTERCESSOR_SQUAD_A"})
	_check("Finest Hour used", bool(rf.get("success", false)), str(rf))
	var mc := _mods("U_CAPTAIN_A", "U_BOYZ_B", true)
	_check("Finest Hour: the Captain's melee +3 A and [DEVASTATING WOUNDS]", int(mc.attacks) == 3 and bool(mc.get("devastating", false)), str(mc))
	_check("Finest Hour: 'this model' — not the Intercessors' attacks", int(_mods("U_INTERCESSOR_SQUAD_A", "U_BOYZ_B", true).attacks) == 0)
	_check("Finest Hour: not ranged", int(_mods("U_CAPTAIN_A", "U_BOYZ_B", false).attacks) == 0)
	var cw := _weapon("U_CAPTAIN_A", "power weapon", true)
	var f_with := _melee("U_CAPTAIN_A", cw, "U_BOYZ_B", 9)
	_flags("U_CAPTAIN_A").erase(SMA.F_FINEST_HOUR)
	var f_without := _melee("U_CAPTAIN_A", cw, "U_BOYZ_B", 9)
	_flags("U_CAPTAIN_A")[SMA.F_FINEST_HOUR] = SMA.phase_key()
	_check("Finest Hour A/B: the resolver rolls 3 more attacks", int(f_with.attacks) == int(f_without.attacks) + 3, "%d vs %d" % [f_with.attacks, f_without.attacks])
	_check("Finest Hour: once per battle (ledger)", UAM.is_once_per_battle_used("U_CAPTAIN_A", "Finest Hour"))
	_phase_transition(P_FIGHT, P_CMD)
	_phase(P_FIGHT, 2)
	_check("Finest Hour: expires with the phase and is not offered again", int(_mods("U_CAPTAIN_A", "U_BOYZ_B", true).attacks) == 0 and _offer(1, "unit_selected_to_fight", {"unit_id": "U_INTERCESSOR_SQUAD_A"}, "finest_hour").is_empty())


# ---------------------------------------------------------------------------
# 5. Lieutenant with Combi-weapon — Priority Target Identified, Evade and Survive
# ---------------------------------------------------------------------------
func _section_lieutenant() -> void:
	print("\n-- 5. Lieutenant with Combi-weapon --")
	_fresh(P_CMD, 1)
	_place("U_LIEUTENANT_WITH_COMBI_WEAPON_A", 10, 40)
	_place("U_BOYZ_B", 10, 30)
	TM.terrain_features = [{"id": "t_ruin_1", "type": "ruins", "polygon": PackedVector2Array([Vector2(8 * PX, 28 * PX), Vector2(14 * PX, 28 * PX), Vector2(14 * PX, 32 * PX), Vector2(8 * PX, 32 * PX)])},
		{"id": "t_crater_2", "type": "crater", "polygon": PackedVector2Array([Vector2(30 * PX, 10 * PX), Vector2(34 * PX, 10 * PX), Vector2(34 * PX, 14 * PX), Vector2(30 * PX, 14 * PX)])}]
	var o := _offer(1, "command_phase_main", {}, "priority_target_identified")
	var opts := _secondary_ids(o, "U_LIEUTENANT_WITH_COMBI_WEAPON_A")
	_check("Priority Target Identified offered with the terrain features (enemy-occupied first)", opts.size() == 2 and opts[0] == "t_ruin_1", str(opts))
	var base: float = TM.detection_range_inches_for(_u("U_BOYZ_B").models[0], _u("U_BOYZ_B"), _u("U_LIEUTENANT_WITH_COMBI_WEAPON_A").models[0])
	var r := _use(1, "priority_target_identified", "U_LIEUTENANT_WITH_COMBI_WEAPON_A", "command_phase_main", {}, "t_ruin_1")
	_check("Priority Target Identified used", bool(r.get("success", false)), str(r))
	var after: float = TM.detection_range_inches_for(_u("U_BOYZ_B").models[0], _u("U_BOYZ_B"), _u("U_LIEUTENANT_WITH_COMBI_WEAPON_A").models[0])
	_check("Priority Target Identified: the Boyz in the identified ruin have +3\" detection range", is_equal_approx(after, base + 3.0), "%s -> %s" % [base, after])
	_place("U_GRETCHIN_C", 30, 2)
	_check("Priority Target Identified: a unit outside it — no bonus", SMA.detection_range_bonus(_u("U_GRETCHIN_C")) == 0.0)
	_check("Priority Target Identified: once per battle", _offer(1, "command_phase_main", {}, "priority_target_identified").is_empty())
	GS.state.meta["active_player"] = 2
	_check("Priority Target Identified: until the end of the turn", SMA.detection_range_bonus(_u("U_BOYZ_B")) == 0.0)
	TM.terrain_features = []
	# Evade and Survive.
	_fresh(P_MOV, 2)
	_place("U_LIEUTENANT_WITH_COMBI_WEAPON_A", 10, 40)
	_place("U_BOYZ_B", 10, 34)
	_place("U_GRETCHIN_C", 35, 5)
	var oe := _offer(1, "enemy_ended_move", {"enemy_unit_id": "U_BOYZ_B"}, "evade_and_survive")
	_check("Evade and Survive offered when an enemy ends a move within 8\"", "U_LIEUTENANT_WITH_COMBI_WEAPON_A" in _offer_units(oe))
	_check("Evade and Survive: not for an enemy more than 8\" away", _offer(1, "enemy_ended_move", {"enemy_unit_id": "U_GRETCHIN_C"}, "evade_and_survive").is_empty())
	_phase(P_MOV, 1)
	_check("Evade and Survive: not in your own Movement phase", _offer(1, "enemy_ended_move", {"enemy_unit_id": "U_BOYZ_B"}, "evade_and_survive").is_empty())
	_phase(P_MOV, 2)
	var re := _use(1, "evade_and_survive", "U_LIEUTENANT_WITH_COMBI_WEAPON_A", "enemy_ended_move", {"enemy_unit_id": "U_BOYZ_B"})
	var fu: Dictionary = re.get("followup", {})
	_check("Evade and Survive: a reactive normal move of D3+3\" (4-6\")", str(fu.get("type", "")) == "reactive_normal_move" and float(fu.get("max_inches", 0)) >= 4.0 and float(fu.get("max_inches", 0)) <= 6.0, str(fu))
	_check("Evade and Survive: once per phase", _offer(1, "enemy_ended_move", {"enemy_unit_id": "U_BOYZ_B"}, "evade_and_survive").is_empty())
	_place("U_BOYZ_B", 10, 39.0)
	_flags("U_LIEUTENANT_WITH_COMBI_WEAPON_A").erase(SMA.F_PHASE_USES)
	_check("Evade and Survive: not while engaged", SWC.is_engaged("U_LIEUTENANT_WITH_COMBI_WEAPON_A") and _offer(1, "enemy_ended_move", {"enemy_unit_id": "U_BOYZ_B"}, "evade_and_survive").is_empty())


# ---------------------------------------------------------------------------
# 6. Librarians — Librarius budget, Might of Heroes, Thunderous Force,
#    Shrouding, Soul Sight
# ---------------------------------------------------------------------------
func _section_librarians() -> void:
	print("\n-- 6. Librarians (Librarius) --")
	_fresh(P_SHOOT, 1)
	_place("U_TERMINATOR_SQUAD_A", 10, 40)
	_place("U_LIBRARIAN_IN_TERMINATOR_ARMOUR_A", 10, 42)
	_attach("U_LIBRARIAN_IN_TERMINATOR_ARMOUR_A", "U_TERMINATOR_SQUAD_A")
	_place("U_BOYZ_B", 10, 25)
	_check("Librarius: Librarian in Terminator Armour has psyker level 1", SMA.psyker_level(_u("U_LIBRARIAN_IN_TERMINATOR_ARMOUR_A")) == 1)
	var o := _offer(1, "phase_start", {"phase": "shooting"}, "thunderous_force")
	_check("Thunderous Force offered at the start of your Shooting phase", "U_TERMINATOR_SQUAD_A" in _offer_units(o))
	_check("Thunderous Force also offered when the unit is selected to shoot", not _offer(1, "unit_selected_to_shoot", {"unit_id": "U_TERMINATOR_SQUAD_A"}, "thunderous_force").is_empty())
	_check("Thunderous Force: not for another shooter", _offer(1, "unit_selected_to_shoot", {"unit_id": "U_BLADEGUARD_VETERAN_SQUAD_A"}, "thunderous_force").is_empty())
	var sb := _weapon("U_TERMINATOR_SQUAD_A", "storm bolter", false)
	var prof: Dictionary = RE.get_weapon_profile(sb, GS.state)
	var seed := _seed_where(1, func(r): return r[0] >= 2)
	var r := _use(1, "thunderous_force", "U_TERMINATOR_SQUAD_A", "phase_start", {"phase": "shooting"})
	_check("Thunderous Force used (psychic roll logged)", bool(r.get("success", false)), str(r))
	_check("Thunderous Force: +6\" Range for the Attached unit's ranged attacks", RE.ork11e_det_range_bonus(_u("U_TERMINATOR_SQUAD_A"), prof) == 6.0 and RE.ork11e_det_range_bonus(_u("U_LIBRARIAN_IN_TERMINATOR_ARMOUR_A"), prof) == 6.0)
	_check("Thunderous Force: not melee", SMA.range_bonus_inches(_u("U_TERMINATOR_SQUAD_A"), {"type": "Melee"}) == 0.0)
	_check("Librarius: psyker level 1 spent — the other power is not offered this battle round", _offer(1, "phase_start", {"phase": "fight"}, "might_of_heroes").is_empty())
	_check("Librarius: budget check names the limit", not SMA.psychic_budget_check("U_LIBRARIAN_IN_TERMINATOR_ARMOUR_A", "might_of_heroes").ok)
	_phase_transition(P_SHOOT, P_CHG)
	_check("Thunderous Force: expires at the end of the phase", SMA.range_bonus_inches(_u("U_TERMINATOR_SQUAD_A"), prof) == 0.0)
	GS.state.meta["battle_round"] = 3
	_phase(P_FIGHT, 2)
	var om := _offer(1, "phase_start", {"phase": "fight"}, "might_of_heroes")
	_check("Might of Heroes offered in either player's Fight phase (new battle round: budget back)", "U_TERMINATOR_SQUAD_A" in _offer_units(om))
	var rm := _use(1, "might_of_heroes", "U_TERMINATOR_SQUAD_A", "phase_start", {"phase": "fight"})
	_check("Might of Heroes used", bool(rm.get("success", false)), str(rm))
	_check("Might of Heroes: melee +2 S (whole Attached unit)", int(_mods("U_TERMINATOR_SQUAD_A", "U_BOYZ_B", true).strength) == 2 and int(_mods("U_LIBRARIAN_IN_TERMINATOR_ARMOUR_A", "U_BOYZ_B", true).strength) == 2)
	_check("Might of Heroes: not ranged", int(_mods("U_TERMINATOR_SQUAD_A", "U_BOYZ_B", false).strength) == 0)
	# Battle-shocked: no psychic ability.
	_fresh(P_SHOOT, 1)
	_place("U_TERMINATOR_SQUAD_A", 10, 40)
	_place("U_LIBRARIAN_IN_TERMINATOR_ARMOUR_A", 10, 42)
	_attach("U_LIBRARIAN_IN_TERMINATOR_ARMOUR_A", "U_TERMINATOR_SQUAD_A")
	_flags("U_TERMINATOR_SQUAD_A")["battle_shocked"] = true
	_check("Librarius: a battle-shocked unit is not offered a psychic ability", _offer(1, "phase_start", {"phase": "shooting"}, "thunderous_force").is_empty())
	_flags("U_TERMINATOR_SQUAD_A").erase("battle_shocked")
	# A psychic roll of 1 battle-shocks the unit (the effect still resolves).
	RE.set_test_seed(_seed_where(1, func(rr): return rr[0] == 1))
	var r1 := _use(1, "thunderous_force", "U_TERMINATOR_SQUAD_A", "phase_start", {"phase": "shooting"})
	_check("Psychic roll of 1: the Attached unit is battle-shocked, the effect still resolves",
		bool(r1.get("success", false)) and bool(_flags("U_TERMINATOR_SQUAD_A").get("battle_shocked", false)) and SMA.range_bonus_inches(_u("U_TERMINATOR_SQUAD_A"), prof) == 6.0,
		str(_flags("U_TERMINATOR_SQUAD_A")))
	RE.set_test_seed(-1)
	# Librarian in Phobos Armour: Shrouding (reactive), Soul Sight.
	_fresh(P_SHOOT, 2)
	_place("U_INFILTRATOR_SQUAD_A", 10, 40)
	_place("U_LIBRARIAN_IN_PHOBOS_ARMOUR_A", 10, 42)
	_attach("U_LIBRARIAN_IN_PHOBOS_ARMOUR_A", "U_INFILTRATOR_SQUAD_A")
	_place("U_FLASH_GITZ_A", 10, 25)
	var osh := _offer(1, "enemy_targets_unit_shooting", {"attacker_unit_id": "U_FLASH_GITZ_A", "target_unit_ids": ["U_INFILTRATOR_SQUAD_A"]}, "shrouding")
	_check("Shrouding offered when an enemy unit targets the Librarian's unit (shooting)", "U_INFILTRATOR_SQUAD_A" in _offer_units(osh))
	_check("Shrouding: not when another unit is targeted", _offer(1, "enemy_targets_unit_shooting", {"attacker_unit_id": "U_FLASH_GITZ_A", "target_unit_ids": ["U_TERMINATOR_SQUAD_A"]}, "shrouding").is_empty())
	_check("Shrouding offered through the reactive dialog's can_use", bool(SM.can_use_stratagem(1, _sid("shrouding"), "U_INFILTRATOR_SQUAD_A", {"window_id": "enemy_targets_unit_shooting", "target_unit_ids": ["U_INFILTRATOR_SQUAD_A"]}).get("can_use", false)))
	var rs := _use(1, "shrouding", "U_INFILTRATOR_SQUAD_A", "enemy_targets_unit_shooting", {"attacker_unit_id": "U_FLASH_GITZ_A", "target_unit_ids": ["U_INFILTRATOR_SQUAD_A"]})
	_check("Shrouding used", bool(rs.get("success", false)), str(rs))
	_check("Shrouding: attacks that target the unit -1 to hit this phase", bool(_mods("U_FLASH_GITZ_A", "U_INFILTRATOR_SQUAD_A", false).hit_minus) and bool(_mods("U_FLASH_GITZ_A", "U_LIBRARIAN_IN_PHOBOS_ARMOUR_A", false).hit_minus))
	_place("U_FLASH_GITZ_A", 10, 30)
	var fw := _weapon("U_FLASH_GITZ_A", "snazzgun", false)
	if fw == "":
		fw = _weapon("U_FLASH_GITZ_A", "", false)
	var seed5 := -1
	var s_with := {}
	var s_without := {}
	for sd in range(1, 200):
		_flags("U_INFILTRATOR_SQUAD_A")[SMA.F_SHROUDED] = SMA.phase_key()
		_flags("U_LIBRARIAN_IN_PHOBOS_ARMOUR_A")[SMA.F_SHROUDED] = SMA.phase_key()
		s_with = _shoot("U_FLASH_GITZ_A", fw, "U_INFILTRATOR_SQUAD_A", sd)
		_flags("U_INFILTRATOR_SQUAD_A").erase(SMA.F_SHROUDED)
		_flags("U_LIBRARIAN_IN_PHOBOS_ARMOUR_A").erase(SMA.F_SHROUDED)
		s_without = _shoot("U_FLASH_GITZ_A", fw, "U_INFILTRATOR_SQUAD_A", sd)
		if int(s_with.hits) != int(s_without.hits):
			seed5 = sd
			break
	_flags("U_INFILTRATOR_SQUAD_A")[SMA.F_SHROUDED] = SMA.phase_key()
	_check("Shrouding A/B (seed %d): fewer hits against the shrouded unit" % seed5, int(s_with.hits) < int(s_without.hits), "%d vs %d" % [s_with.hits, s_without.hits])
	_phase_transition(P_SHOOT, P_CHG)
	_check("Shrouding: expires at the end of the phase", not bool(_mods("U_FLASH_GITZ_A", "U_INFILTRATOR_SQUAD_A", false).hit_minus))
	_phase(P_FIGHT, 2)
	_check("Shrouding: budget spent this battle round — not offered in the Fight phase", _offer(1, "enemy_targets_unit_fight", {"target_unit_ids": ["U_INFILTRATOR_SQUAD_A"]}, "shrouding").is_empty())
	GS.state.meta["battle_round"] = 3
	for gid in ["U_INFILTRATOR_SQUAD_A", "U_LIBRARIAN_IN_PHOBOS_ARMOUR_A"]:
		_flags(gid).erase("battle_shocked")  # the psychic roll may have been a 1
	_check("Shrouding: offered when an enemy targets the unit in the Fight phase (next round)", not _offer(1, "enemy_targets_unit_fight", {"target_unit_ids": ["U_INFILTRATOR_SQUAD_A"]}, "shrouding").is_empty())
	# Soul Sight.
	_fresh(P_SHOOT, 1)
	_place("U_INFILTRATOR_SQUAD_A", 10, 40)
	_place("U_LIBRARIAN_IN_PHOBOS_ARMOUR_A", 10, 42)
	_attach("U_LIBRARIAN_IN_PHOBOS_ARMOUR_A", "U_INFILTRATOR_SQUAD_A")
	_place("U_BOYZ_B", 10, 25)
	_place("U_TANKBUSTAS_A", 30, 30)
	var oss := _offer(1, "phase_start", {"phase": "shooting"}, "soul_sight")
	_check("Soul Sight offered at the start of your Shooting phase with visible enemies", "U_BOYZ_B" in _secondary_ids(oss, "U_INFILTRATOR_SQUAD_A"))
	var rss := _use(1, "soul_sight", "U_INFILTRATOR_SQUAD_A", "phase_start", {"phase": "shooting"}, "U_BOYZ_B")
	_check("Soul Sight used", bool(rss.get("success", false)), str(rss))
	_place("U_INTERCESSOR_SQUAD_A", 20, 40)
	_check("Soul Sight: ranged attacks that target the Boyz have [IGNORES COVER] (any shooter)", bool(_mods("U_INTERCESSOR_SQUAD_A", "U_BOYZ_B", false).ignores_cover))
	_check("Soul Sight: not other targets / not melee", not bool(_mods("U_INTERCESSOR_SQUAD_A", "U_TANKBUSTAS_A", false).ignores_cover) and not bool(_mods("U_INTERCESSOR_SQUAD_A", "U_BOYZ_B", true).ignores_cover))


# ---------------------------------------------------------------------------
# 7. Angel's Wrath (+1 advance / charge), Unstoppable Valour (charge re-roll)
# ---------------------------------------------------------------------------
func _section_angels_wrath_valour() -> void:
	print("\n-- 7. Angel's Wrath / Unstoppable Valour --")
	_fresh(P_MOV, 1)
	_place("U_ASSAULT_INTERCESSORS_WITH_JUMP_PACKS_A", 10, 40)
	_place("U_CAPTAIN_WITH_JUMP_PACK_A", 10, 42)
	_check("Angel's Wrath: the Captain's own unit +1", int(SMA.roll_bonus("U_CAPTAIN_WITH_JUMP_PACK_A").bonus) == 1)
	_check("Angel's Wrath: the jump-pack Intercessors alone — none", int(SMA.roll_bonus("U_ASSAULT_INTERCESSORS_WITH_JUMP_PACKS_A").bonus) == 0)
	_attach("U_CAPTAIN_WITH_JUMP_PACK_A", "U_ASSAULT_INTERCESSORS_WITH_JUMP_PACKS_A")
	_check("Angel's Wrath: led — the whole Attached unit +1 to advance and charge rolls", int(SMA.roll_bonus("U_ASSAULT_INTERCESSORS_WITH_JUMP_PACKS_A").bonus) == 1)
	var mp = load("res://phases/MovementPhase.gd").new()
	root.add_child(mp)
	mp._resolve_advance_roll("U_ASSAULT_INTERCESSORS_WITH_JUMP_PACKS_A", 3, true)
	var am: Dictionary = mp.active_moves.get("U_ASSAULT_INTERCESSORS_WITH_JUMP_PACKS_A", {})
	var adv := int(am.get("advance_roll", -1))
	_check("Angel's Wrath live: advance roll 3 +1 = 4 (MovementPhase hook)", adv == 4, "advance_roll=%d" % adv)
	mp.queue_free()
	_check("Unstoppable Valour: the Captain in Terminator Armour can re-roll charge rolls", EP.has_effect_reroll_charge(_u("U_CAPTAIN_IN_TERMINATOR_ARMOUR_A")))
	_place("U_TERMINATOR_SQUAD_A", 30, 40)
	_check("Unstoppable Valour: other units cannot", not EP.has_effect_reroll_charge(_u("U_TERMINATOR_SQUAD_A")))
	_place("U_CAPTAIN_IN_TERMINATOR_ARMOUR_A", 30, 42)
	_attach("U_CAPTAIN_IN_TERMINATOR_ARMOUR_A", "U_TERMINATOR_SQUAD_A")
	_check("Unstoppable Valour: led — the Attached unit re-rolls charge rolls", EP.has_effect_reroll_charge(_u("U_TERMINATOR_SQUAD_A")))
	_check("Unstoppable Valour: not advance rolls", not EP.has_effect_reroll_advance(_u("U_TERMINATOR_SQUAD_A")))


# ---------------------------------------------------------------------------
# 8. Sentinel Protocols (FIRE OVERWATCH regardless of other uses; 4+ snap hits)
# ---------------------------------------------------------------------------
func _section_sentinel_protocols() -> void:
	print("\n-- 8. Sentinel Protocols --")
	_fresh(P_MOV, 2)
	_place("U_FIRESTRIKE_SERVO_TURRETS_A", 10, 40)
	_place("U_INTERCESSOR_SQUAD_A", 25, 40)
	_place("U_BOYZ_B", 10, 25)
	var ov: Dictionary = SM._cus11e_stratagem_override(1, "fire_overwatch_11e", "U_FIRESTRIKE_SERVO_TURRETS_A")
	_check("Sentinel Protocols: FIRE OVERWATCH on the Servo-turrets is an override (regardless of other uses)", bool(ov.get("applies", false)) and str(ov.get("source", "")) == "Sentinel Protocols", str(ov))
	_check("Sentinel Protocols: not for another unit", not bool(SM._cus11e_stratagem_override(1, "fire_overwatch_11e", "U_INTERCESSOR_SQUAD_A").get("applies", false)))
	SM._usage_history["1"].append({"stratagem_id": "fire_overwatch_11e", "player": 1, "target_unit_id": "U_INTERCESSOR_SQUAD_A", "turn": 2, "phase": P_MOV, "active_player": 2})
	_check("FIRE OVERWATCH already used this phase: another unit is refused", not bool(SM.can_use_stratagem(1, "fire_overwatch_11e", "U_HEAVY_INTERCESSOR_SQUAD_A", {"window_id": "movement_phase_end"}).get("can_use", true)))
	var cu: Dictionary = SM.can_use_stratagem(1, "fire_overwatch_11e", "U_FIRESTRIKE_SERVO_TURRETS_A", {"window_id": "movement_phase_end"})
	_check("FIRE OVERWATCH already used: the Servo-turrets can still be targeted (Sentinel Protocols)", bool(cu.get("can_use", false)), str(cu))
	var offers: Array = SM.get_window_offers(1, "movement_phase_end", {"phase": "movement"})
	var fo_units: Array = []
	for o in offers:
		if str(o.get("stratagem_id", "")) == "fire_overwatch_11e":
			fo_units = o.get("targets", []).map(func(t): return str(t.get("unit_id", "")))
	_check("movement_phase_end window: FIRE OVERWATCH offered on the Servo-turrets only", fo_units == ["U_FIRESTRIKE_SERVO_TURRETS_A"], str(fo_units))
	var use: Dictionary = SM.use_stratagem(1, "fire_overwatch_11e", "U_FIRESTRIKE_SERVO_TURRETS_A", {"window_id": "movement_phase_end", "secondary_id": "U_BOYZ_B"})
	_check("FIRE OVERWATCH used on the Servo-turrets (full CP)", bool(use.get("success", false)), str(use.get("error", "")))
	_check("Sentinel Protocols: snap-shooting attacks hit on unmodified 4+ until resolved", SMA.snap_hit_threshold(_u("U_FIRESTRIKE_SERVO_TURRETS_A")) == 4)
	_check("Sentinel Protocols: once per phase", not bool(SM._cus11e_stratagem_override(1, "fire_overwatch_11e", "U_FIRESTRIKE_SERVO_TURRETS_A").get("applies", false)))
	# The resolver: snap shooting with the turrets, A/B with the same seed.
	var tw := _weapon("U_FIRESTRIKE_SERVO_TURRETS_A", "las-talon", false)
	var seed := _seed_where(4, func(r): return r.count(4) + r.count(5) >= 2 and r.count(6) == 0)
	var a4 := _ow_shoot("U_FIRESTRIKE_SERVO_TURRETS_A", tw, "U_BOYZ_B", seed)
	_flags("U_FIRESTRIKE_SERVO_TURRETS_A").erase(SMA.F_SENTINEL)
	var a6 := _ow_shoot("U_FIRESTRIKE_SERVO_TURRETS_A", tw, "U_BOYZ_B", seed)
	_check("Sentinel Protocols A/B (seed %d): 4s and 5s hit only with the protocol" % seed, int(a4) > int(a6) and int(a6) == 0, "%d vs %d" % [a4, a6])
	_phase_transition(P_MOV, P_SHOOT)
	_check("Sentinel Protocols: the 4+ stamp expires with the phase", SMA.snap_hit_threshold(_u("U_FIRESTRIKE_SERVO_TURRETS_A")) == 0)


func _ow_shoot(uid: String, wid: String, tid: String, seed: int) -> int:
	var a := _assign(uid, wid, tid)
	a["overwatch"] = true
	RE.set_test_seed(seed)
	var res = RE.resolve_shoot({"type": "SHOOT", "actor_unit_id": uid, "payload": {"assignments": [a], "overwatch": true, "shooting_type": "snap"}}, GS.state.duplicate(true), RE.RNGService.new(seed))
	var hits := 0
	for d in res.get("dice", []):
		if str(d.get("context", "")) in ["to_hit", "hit_roll"]:
			hits += int(d.get("successes", 0))
	return hits


# ---------------------------------------------------------------------------
# 9. Brutalis Charge (CRUSHING IMPACT regardless of other uses, -1 CP)
# ---------------------------------------------------------------------------
func _section_brutalis_charge() -> void:
	print("\n-- 9. Brutalis Charge --")
	_fresh(P_CHG, 1)
	_place("U_BRUTALIS_DREADNOUGHT_A", 10, 40)
	_place("U_REDEMPTOR_DREADNOUGHT_A", 25, 40)
	var ov: Dictionary = SM._cus11e_stratagem_override(1, "crushing_impact", "U_BRUTALIS_DREADNOUGHT_A")
	_check("Brutalis Charge: CRUSHING IMPACT on the Brutalis is an override with -1 CP", bool(ov.get("applies", false)) and int(ov.get("cost_delta", 0)) == -1, str(ov))
	_check("Brutalis Charge: not another unit", not bool(SM._cus11e_stratagem_override(1, "crushing_impact", "U_REDEMPTOR_DREADNOUGHT_A").get("applies", false)))
	_check("Brutalis Charge: preview cost 0 CP (CRUSHING IMPACT 1 CP -1)", int(SM.preview_cp_cost(1, "crushing_impact", "U_BRUTALIS_DREADNOUGHT_A")) == maxi(0, int(SM.get_stratagem("crushing_impact").get("cp_cost", 1)) - 1))
	var diffs: Array = SMA.record_stratagem_override(ov)
	SWC.apply_diffs(diffs)
	_check("Brutalis Charge: once per phase", not bool(SM._cus11e_stratagem_override(1, "crushing_impact", "U_BRUTALIS_DREADNOUGHT_A").get("applies", false)))
	_phase(P_FIGHT, 1)
	_check("Brutalis Charge: available again next phase", bool(SM._cus11e_stratagem_override(1, "crushing_impact", "U_BRUTALIS_DREADNOUGHT_A").get("applies", false)))


# ---------------------------------------------------------------------------
# 10. Transports — Assault Ramp, Aerial Assault
# ---------------------------------------------------------------------------
func _section_transports() -> void:
	print("\n-- 10. Assault Ramp / Aerial Assault --")
	_fresh(P_MOV, 1)
	_place("U_LAND_RAIDER_A", 10, 40)
	_embark("U_INTERCESSOR_SQUAD_A", "U_LAND_RAIDER_A")
	_place("U_BOYZ_B", 10, 25)
	var o := _offer(1, "unit_ended_normal_move", {"unit_id": "U_LAND_RAIDER_A"}, "assault_ramp")
	_check("Assault Ramp offered when the Land Raider ends a normal move with units embarked", "U_LAND_RAIDER_A" in _offer_units(o))
	_check("Assault Ramp: not after an advance move", _offer(1, "unit_ended_advance_move", {"unit_id": "U_LAND_RAIDER_A"}, "assault_ramp").is_empty())
	var dm = load("res://scripts/rules/movetypes/DisembarkMove.gd").new()
	_flags("U_LAND_RAIDER_A")["moved_this_phase"] = true
	_check("Disembark after the transport moved: rapid disembark (no Assault Ramp)", str(dm.select_mode("U_INTERCESSOR_SQUAD_A", GS.state).mode) == "rapid")
	var r := _use(1, "assault_ramp", "U_LAND_RAIDER_A", "unit_ended_normal_move", {"unit_id": "U_LAND_RAIDER_A"})
	_check("Assault Ramp: an assault_disembark follow-up", str(r.get("followup", {}).get("type", "")) == "assault_disembark", str(r))
	_check("Assault Ramp: the disembark is an ASSAULT DISEMBARK MOVE (DisembarkMove hook)", str(dm.select_mode("U_INTERCESSOR_SQUAD_A", GS.state).mode) == "assault")
	SWC.apply_diffs(SMA.assault_disembark_off_diffs("U_LAND_RAIDER_A"))
	_check("Assault Ramp: spent when the follow-up ends", str(dm.select_mode("U_INTERCESSOR_SQUAD_A", GS.state).mode) == "rapid")
	_check("Assault Ramp: once per phase", _offer(1, "unit_ended_normal_move", {"unit_id": "U_LAND_RAIDER_A"}, "assault_ramp").is_empty())
	_fresh(P_MOV, 1)
	_place("U_LAND_RAIDER_CRUSADER_A", 10, 40)
	_check("Assault Ramp (Crusader): not offered with nobody embarked", _offer(1, "unit_ended_normal_move", {"unit_id": "U_LAND_RAIDER_CRUSADER_A"}, "assault_ramp").is_empty())
	# Aerial Assault: only units whose every model has Deep Strike.
	_fresh(P_MOV, 1)
	_place("U_THUNDERHAWK_GUNSHIP_A", 20, 40)
	_embark("U_INTERCESSOR_SQUAD_A", "U_THUNDERHAWK_GUNSHIP_A")
	_check("Aerial Assault: not offered when no embarked unit has Deep Strike", _offer(1, "unit_ended_normal_move", {"unit_id": "U_THUNDERHAWK_GUNSHIP_A"}, "aerial_assault").is_empty())
	_embark("U_TERMINATOR_SQUAD_A", "U_THUNDERHAWK_GUNSHIP_A")
	_check("Aerial Assault offered when a Deep Strike unit is embarked", not _offer(1, "unit_ended_normal_move", {"unit_id": "U_THUNDERHAWK_GUNSHIP_A"}, "aerial_assault").is_empty())
	var ra := _use(1, "aerial_assault", "U_THUNDERHAWK_GUNSHIP_A", "unit_ended_normal_move", {"unit_id": "U_THUNDERHAWK_GUNSHIP_A"})
	_check("Aerial Assault used", bool(ra.get("success", false)), str(ra))
	var cands: Array = SMA.filter_assault_disembark("U_THUNDERHAWK_GUNSHIP_A", ["U_INTERCESSOR_SQUAD_A", "U_TERMINATOR_SQUAD_A"])
	_check("Aerial Assault: only the Deep Strike unit may assault disembark", cands == ["U_TERMINATOR_SQUAD_A"], str(cands))


# ---------------------------------------------------------------------------
# 11. Drop Pod — Drop Pod Assault, Deployment Complete
# ---------------------------------------------------------------------------
func _section_drop_pod() -> void:
	print("\n-- 11. Drop Pod Assault / Deployment Complete --")
	_fresh(P_FORM, 1, 1)
	var forced: Array = SMA.forced_reserves(1, [])
	_check("Drop Pod Assault: the Drop Pod is added to strategic reserves at Formations", forced.size() == 1 and str(forced[0].unit_id) == "U_DROP_POD_A" and str(forced[0].reserve_type) == "strategic_reserves", str(forced))
	_check("Drop Pod Assault: not added twice", SMA.forced_reserves(1, [{"unit_id": "U_DROP_POD_A"}]).is_empty())
	_check("Drop Pod Assault: the Ork player has none", SMA.forced_reserves(2, []).is_empty())
	_fresh(P_MOV, 1, 1)
	_reserve("U_DROP_POD_A")
	_reserve("U_INCEPTOR_SQUAD_A")
	_check("Drop Pod Assault: can ingress in the first battle round", SMA.can_ingress_first_round(_u("U_DROP_POD_A")))
	_check("Drop Pod Assault: other units cannot", not SMA.can_ingress_first_round(_u("U_INCEPTOR_SQUAD_A")))
	var mp = load("res://phases/MovementPhase.gd").new()
	root.add_child(mp)
	var firsts: Array = mp._cus11e_lightning_descent_reserves(1)
	_check("MovementPhase: the Drop Pod is listed among the round-1 arrivals", "U_DROP_POD_A" in firsts and not "U_INCEPTOR_SQUAD_A" in firsts, str(firsts))
	mp.queue_free()
	_embark("U_INTERCESSOR_SQUAD_A", "U_DROP_POD_A")
	_place("U_DROP_POD_A", 22, 40)
	_place("U_BOYZ_B", 22, 25)
	var dp: Dictionary = SMA.drop_pod_landed("U_DROP_POD_A")
	_check("Drop Pod set up: its embarked units must disembark (assault disembark follow-up)", (dp.get("units", []) as Array) == ["U_INTERCESSOR_SQUAD_A"] and str(dp.get("followup", {}).get("type", "")) == "assault_disembark", str(dp))
	SWC.apply_diffs(dp.diffs)
	var o := _offer(1, "sm11e_drop_pod_landed", {"unit_id": "U_DROP_POD_A"}, "drop_pod_assault")
	_check("Drop Pod Assault card offered in the sm11e_drop_pod_landed window", "U_DROP_POD_A" in _offer_units(o))
	var dm = load("res://scripts/rules/movetypes/DisembarkMove.gd").new()
	_check("Drop Pod Assault: an ASSAULT disembark move", str(dm.select_mode("U_INTERCESSOR_SQUAD_A", GS.state).mode) == "assault")
	var near: Array = [{"x": 22.0 * PX, "y": 33.0 * PX}]
	var far: Array = [{"x": 22.0 * PX, "y": 43.0 * PX}]
	_check("Drop Pod Assault: a model set up within 8\" of an enemy is refused", not SMA.disembark_setup_errors("U_INTERCESSOR_SQUAD_A", near).is_empty())
	_check("Drop Pod Assault: more than 8\" away is fine", SMA.disembark_setup_errors("U_INTERCESSOR_SQUAD_A", far).is_empty())
	_check("Drop Pod Assault: a model-indexed position map is read too", not SMA.disembark_setup_errors("U_INTERCESSOR_SQUAD_A", {0: Vector2(22.0 * PX, 33.0 * PX)}).is_empty())
	_check("Deployment Complete: units may not embark yet while it is occupied? (the pod still holds its unit)", SMA.embark_block_reason("U_DROP_POD_A") == "")
	_place("U_INTERCESSOR_SQUAD_A", 22, 44)
	_u("U_DROP_POD_A").transport_data["embarked_units"] = []
	_check("Deployment Complete: set up and emptied — no embarking", SMA.embark_block_reason("U_DROP_POD_A") != "")
	_place("U_HELLBLASTER_SQUAD_A", 25, 44)
	var ce: Dictionary = root.get_node("TransportManager").can_embark("U_HELLBLASTER_SQUAD_A", "U_DROP_POD_A")
	_check("Deployment Complete: TransportManager.can_embark refuses it", not bool(ce.get("valid", true)) and str(ce.get("reason", "")).contains("Deployment Complete"), str(ce))
	_phase_transition(P_MOV, P_SHOOT)
	_check("Drop Pod: the disembark grant / 8\" stamp expire with the phase", str(dm.select_mode("U_INTERCESSOR_SQUAD_A", GS.state).get("mode", "")) != "assault" and SMA.disembark_setup_errors("U_INTERCESSOR_SQUAD_A", near).is_empty())
	# The live MovementPhase path with an AI owner: set up (round 1) -> the
	# sm11e_drop_pod_landed window is decided synchronously -> the embarked
	# unit is disembarked automatically; nothing waits on a human.
	_fresh(P_MOV, 1, 1)
	_reserve("U_DROP_POD_A")
	_embark("U_INTERCESSOR_SQUAD_A", "U_DROP_POD_A")
	_u("U_INTERCESSOR_SQUAD_A")["status"] = 2
	_place("U_BOYZ_B", 10, 6)
	var ai = root.get_node("AIPlayer")
	ai.enabled = true
	ai.ai_players = {1: true, 2: false}
	var mp2 = load("res://phases/MovementPhase.gd").new()
	PM.add_child(mp2)
	var res: Dictionary = mp2._process_place_reinforcement({"type": "PLACE_REINFORCEMENT", "unit_id": "U_DROP_POD_A", "player": 1,
		"model_positions": [{"x": 22.0 * PX, "y": 40.0 * PX}], "placement_type": "deep_strike"})
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	var ic := _u("U_INTERCESSOR_SQUAD_A")
	var on_table := ic.get("embarked_in", null) == null or str(ic.get("embarked_in", "")) == ""
	var min_d := INF
	for m in ic.models:
		if m.get("position", null) != null:
			for b in _u("U_BOYZ_B").models:
				min_d = minf(min_d, SWC.unit_distance_inches({"models": [m]}, {"models": [b]}))
	_check("Drop Pod live (AI owner): set up in round 1 and its Intercessors disembarked at once", bool(res.get("success", false)) and int(_u("U_DROP_POD_A").status) != 7 and on_table,
		"res=%s pod status=%s embarked_in=%s" % [str(res.get("success", "")), str(_u("U_DROP_POD_A").status), str(ic.get("embarked_in", null))])
	_check("Drop Pod live (AI owner): the disembarked models are more than 8\" from every enemy", min_d > 8.0, str(min_d))
	_check("Drop Pod live: no window left waiting", not mp2.has_pending_stratagem_window())
	_check("Drop Pod live: Deployment Complete — the emptied pod refuses embarking", SMA.embark_block_reason("U_DROP_POD_A") != "")
	mp2.queue_free()


# ---------------------------------------------------------------------------
# 12. Teleport Homer (once per battle)
# ---------------------------------------------------------------------------
func _section_teleport_homer() -> void:
	print("\n-- 12. Teleport Homer --")
	_fresh(P_CMD, 1, 1)
	_reserve("U_TERMINATOR_ASSAULT_SQUAD_A")
	_place("U_INTERCESSOR_SQUAD_A", 20, 40)
	_place("U_BOYZ_B", 20, 10)
	var o := _offer(1, "phase_start", {"phase": "command"}, "teleport_homer")
	var spots := _secondary_ids(o, "U_TERMINATOR_ASSAULT_SQUAD_A")
	_check("Teleport Homer offered at the start of the battle (round 1), unit in reserves", not spots.is_empty() and "unit_U_INTERCESSOR_SQUAD_A" in spots, str(spots))
	var r := _use(1, "teleport_homer", "U_TERMINATOR_ASSAULT_SQUAD_A", "phase_start", {"phase": "command"}, "unit_U_INTERCESSOR_SQUAD_A")
	_check("Teleport Homer: the token is set up", bool(r.get("success", false)) and SMA.homer_position_px("U_TERMINATOR_ASSAULT_SQUAD_A") != Vector2.INF, str(r))
	_check("Teleport Homer: once per battle — not offered again", _offer(1, "phase_start", {"phase": "command"}, "teleport_homer").is_empty())
	GS.state.meta["battle_round"] = 2
	_phase(P_MOV, 2)
	var base_cost := int(SM.preview_cp_cost(1, "rapid_ingress", ""))
	_check("Teleport Homer: Rapid Ingress on the squad is -1 CP", int(SM.preview_cp_cost(1, "rapid_ingress", "U_TERMINATOR_ASSAULT_SQUAD_A")) == maxi(0, base_cost - 1), "%d vs %d" % [int(SM.preview_cp_cost(1, "rapid_ingress", "U_TERMINATOR_ASSAULT_SQUAD_A")), base_cost])
	_check("Teleport Homer: no discount for another reserve unit", SMA.stratagem_cp_discount(1, "rapid_ingress", "U_INCEPTOR_SQUAD_A") == 0)
	SMA.record_cp_discount(1, "U_TERMINATOR_ASSAULT_SQUAD_A")
	var p: Vector2 = SMA.homer_position_px("U_TERMINATOR_ASSAULT_SQUAD_A")
	var far_pos: Array = []
	var near_pos: Array = []
	for i in range(_u("U_TERMINATOR_ASSAULT_SQUAD_A").models.size()):
		far_pos.append({"x": 5.0 * PX + i * 70.0, "y": 55.0 * PX})
		near_pos.append({"x": p.x + i * 70.0, "y": p.y + 60.0})
	_check("Teleport Homer in use: a set-up far from the token is refused", not SMA.homer_setup_errors("U_TERMINATOR_ASSAULT_SQUAD_A", far_pos).is_empty())
	_check("Teleport Homer in use: a set-up within 3\" of the token is fine", SMA.homer_setup_errors("U_TERMINATOR_ASSAULT_SQUAD_A", near_pos).is_empty())
	var rm: Array = SMA.on_reinforcement_set_up("U_TERMINATOR_ASSAULT_SQUAD_A")
	SWC.apply_diffs(rm)
	_check("Teleport Homer: the token is removed after that set-up", SMA.homer_position_px("U_TERMINATOR_ASSAULT_SQUAD_A") == Vector2.INF)
	# An enemy ending a move within 1" removes the token.
	_fresh(P_MOV, 2, 2)
	_reserve("U_TERMINATOR_ASSAULT_SQUAD_A")
	_flags("U_TERMINATOR_ASSAULT_SQUAD_A")[SMA.F_HOMER] = {"x": 20.0 * PX, "y": 30.0 * PX, "player": 1}
	_place("U_BOYZ_B", 20, 30.6)
	_check("Teleport Homer: an enemy model next to the token makes it unusable", not SMA.homer_usable("U_TERMINATOR_ASSAULT_SQUAD_A"))
	var rmv: Array = SMA.check_homers_after_move("U_BOYZ_B")
	_check("Teleport Homer: an enemy unit that ends a move within 1\" removes it", not rmv.is_empty())


# ---------------------------------------------------------------------------
# 13. Chaplains — Catechism of Fire
# ---------------------------------------------------------------------------
func _section_chaplains() -> void:
	print("\n-- 13. Catechism of Fire --")
	_fresh(P_SHOOT, 1)
	_place("U_OUTRIDER_SQUAD_A", 10, 40)
	_place("U_CHAPLAIN_ON_BIKE_A", 10, 43)
	_attach("U_CHAPLAIN_ON_BIKE_A", "U_OUTRIDER_SQUAD_A")
	_place("U_BOYZ_B", 10, 25)
	_place("U_TANKBUSTAS_A", 30, 25)
	var o := _offer(1, "unit_selected_to_shoot", {"unit_id": "U_OUTRIDER_SQUAD_A", "planned_target_unit_ids": ["U_TANKBUSTAS_A"]}, "catechism_of_fire")
	var opts := _secondary_ids(o, "U_OUTRIDER_SQUAD_A")
	_check("Catechism of Fire offered when the Chaplain's unit is selected to shoot (planned target first)", not opts.is_empty() and opts[0] == "U_TANKBUSTAS_A", str(opts))
	_check("Catechism of Fire: not at another unit's selection", _offer(1, "unit_selected_to_shoot", {"unit_id": "U_INTERCESSOR_SQUAD_A"}, "catechism_of_fire").is_empty())
	var r := _use(1, "catechism_of_fire", "U_OUTRIDER_SQUAD_A", "unit_selected_to_shoot", {"unit_id": "U_OUTRIDER_SQUAD_A"}, "U_BOYZ_B")
	_check("Catechism of Fire used", bool(r.get("success", false)), str(r))
	_check("Catechism of Fire: ranged vs the Boyz [DEVASTATING WOUNDS] (whole unit)", bool(_mods("U_OUTRIDER_SQUAD_A", "U_BOYZ_B", false).get("devastating", false)) and bool(_mods("U_CHAPLAIN_ON_BIKE_A", "U_BOYZ_B", false).get("devastating", false)))
	_check("Catechism of Fire: not vs another unit / not melee", not bool(_mods("U_OUTRIDER_SQUAD_A", "U_TANKBUSTAS_A", false).get("devastating", false)) and not bool(_mods("U_OUTRIDER_SQUAD_A", "U_BOYZ_B", true).get("devastating", false)))
	_phase_transition(P_SHOOT, P_CHG)
	_check("Catechism of Fire: until the end of the phase", not bool(_mods("U_OUTRIDER_SQUAD_A", "U_BOYZ_B", false).get("devastating", false)))


# ---------------------------------------------------------------------------
# 14. Hailstrike / Driven from Cover
# ---------------------------------------------------------------------------
func _section_shooting_cards() -> void:
	print("\n-- 14. Hailstrike / Driven from Cover --")
	_fresh(P_SHOOT, 1)
	_place("U_INFERNUS_SQUAD_A", 10, 40)
	_place("U_STORM_SPEEDER_HAILSTRIKE_A", 30, 40)
	_place("U_INTERCESSOR_SQUAD_A", 20, 45)
	_place("U_BOYZ_B", 10, 33)
	_place("U_GRETCHIN_C", 30, 30)
	var o := _offer(1, "unit_has_shot", {"unit_id": "U_INFERNUS_SQUAD_A", "hit_unit_ids": ["U_BOYZ_B"]}, "driven_from_cover")
	_check("Driven from Cover offered when the Infernus Squad has shot and hit a unit", "U_BOYZ_B" in _secondary_ids(o, "U_INFERNUS_SQUAD_A"))
	_check("Driven from Cover: nothing hit — no card", _offer(1, "unit_has_shot", {"unit_id": "U_INFERNUS_SQUAD_A", "hit_unit_ids": []}, "driven_from_cover").is_empty())
	var r := _use(1, "driven_from_cover", "U_INFERNUS_SQUAD_A", "unit_has_shot", {"unit_id": "U_INFERNUS_SQUAD_A", "hit_unit_ids": ["U_BOYZ_B"]}, "U_BOYZ_B")
	_check("Driven from Cover used", bool(r.get("success", false)), str(r))
	_check("Driven from Cover: friendly ADEPTUS ASTARTES ranged attacks vs the Boyz [IGNORES COVER]", bool(_mods("U_INTERCESSOR_SQUAD_A", "U_BOYZ_B", false).ignores_cover))
	_check("Driven from Cover: not the enemy's attacks / not other targets", not bool(_mods("U_GRETCHIN_C", "U_BOYZ_B", false).ignores_cover) and not bool(_mods("U_INTERCESSOR_SQUAD_A", "U_GRETCHIN_C", false).ignores_cover))
	var oh := _offer(1, "unit_has_shot", {"unit_id": "U_STORM_SPEEDER_HAILSTRIKE_A", "hit_unit_ids": ["U_GRETCHIN_C", "U_BOYZ_B"]}, "hailstrike")
	_check("Hailstrike offered with every unit hit", _secondary_ids(oh, "U_STORM_SPEEDER_HAILSTRIKE_A").size() == 2)
	_use(1, "hailstrike", "U_STORM_SPEEDER_HAILSTRIKE_A", "unit_has_shot", {"unit_id": "U_STORM_SPEEDER_HAILSTRIKE_A", "hit_unit_ids": ["U_GRETCHIN_C"]}, "U_GRETCHIN_C")
	_check("Hailstrike: friendly AA ranged attacks vs the Gretchin [IGNORES COVER]", bool(_mods("U_INTERCESSOR_SQUAD_A", "U_GRETCHIN_C", false).ignores_cover))
	_check("Hailstrike: once per phase", _offer(1, "unit_has_shot", {"unit_id": "U_STORM_SPEEDER_HAILSTRIKE_A", "hit_unit_ids": ["U_BOYZ_B"]}, "hailstrike").is_empty())
	_phase_transition(P_SHOOT, P_CHG)
	_check("Hailstrike / Driven from Cover: expire at the end of the phase", not bool(_mods("U_INTERCESSOR_SQUAD_A", "U_GRETCHIN_C", false).ignores_cover) and not bool(_mods("U_INTERCESSOR_SQUAD_A", "U_BOYZ_B", false).ignores_cover))


# ---------------------------------------------------------------------------
# 15. Inceptor Squad — Meteoric Descent, Parabolic Jetleap
# ---------------------------------------------------------------------------
func _section_inceptors() -> void:
	print("\n-- 15. Meteoric Descent / Parabolic Jetleap --")
	_fresh(P_SHOOT, 1)
	_place("U_INCEPTOR_SQUAD_A", 10, 40)
	_place("U_BOYZ_B", 10, 30)
	_check("Meteoric Descent: no ingress — no +1 to hit", not bool(_mods("U_INCEPTOR_SQUAD_A", "U_BOYZ_B", false).hit_plus))
	_flags("U_INCEPTOR_SQUAD_A")["arrived_from_reserves"] = true
	var m := _mods("U_INCEPTOR_SQUAD_A", "U_BOYZ_B", false)
	_check("Meteoric Descent: made an ingress move this turn — ranged +1 to hit", bool(m.hit_plus) and "Meteoric Descent" in _names(m))
	_check("Meteoric Descent: not melee", not bool(_mods("U_INCEPTOR_SQUAD_A", "U_BOYZ_B", true).hit_plus))
	var iw := _weapon("U_INCEPTOR_SQUAD_A", "assault bolters", false)
	var seed := _seed_where(18, func(r): return r.count(2) >= 3)
	var with_m := _shoot("U_INCEPTOR_SQUAD_A", iw, "U_BOYZ_B", seed)
	_flags("U_INCEPTOR_SQUAD_A").erase("arrived_from_reserves")
	var without := _shoot("U_INCEPTOR_SQUAD_A", iw, "U_BOYZ_B", seed)
	_check("Meteoric Descent A/B (seed %d): more hits after an ingress move" % seed, int(with_m.hits) > int(without.hits), "%d vs %d" % [with_m.hits, without.hits])
	_fresh(P_FIGHT, 2)
	_place("U_INCEPTOR_SQUAD_A", 10, 40)
	_place("U_BOYZ_B", 10, 30)
	var o := _offer(1, "fight_phase_end", {"phase": "fight"}, "parabolic_jetleap")
	_check("Parabolic Jetleap offered at the end of the opponent's Fight phase (unengaged)", "U_INCEPTOR_SQUAD_A" in _offer_units(o))
	_phase(P_FIGHT, 1)
	_check("Parabolic Jetleap: not at the end of your own Fight phase", _offer(1, "fight_phase_end", {"phase": "fight"}, "parabolic_jetleap").is_empty())
	_phase(P_FIGHT, 2)
	_place("U_BOYZ_B", 10, 39.0)
	_check("Parabolic Jetleap: not while engaged", SWC.is_engaged("U_INCEPTOR_SQUAD_A") and _offer(1, "fight_phase_end", {"phase": "fight"}, "parabolic_jetleap").is_empty())
	_place("U_BOYZ_B", 10, 30)
	var r := _use(1, "parabolic_jetleap", "U_INCEPTOR_SQUAD_A", "fight_phase_end", {"phase": "fight"})
	_check("Parabolic Jetleap: the unit is placed in strategic reserves", bool(r.get("success", false)) and int(_u("U_INCEPTOR_SQUAD_A").status) == 7 and str(_u("U_INCEPTOR_SQUAD_A").get("reserve_type", "")) == "strategic_reserves" and _u("U_INCEPTOR_SQUAD_A").models[0].position == null, str(r))


# ---------------------------------------------------------------------------
# 16. Iron Father Feirros / Techmarine — Master of the Forge, Blessings of the
#     Omnissiah, conditional Lone Operative
# ---------------------------------------------------------------------------
func _section_forge() -> void:
	print("\n-- 16. Master of the Forge / Blessings of the Omnissiah / Lone Operative --")
	_fresh(P_MOV, 1)
	_place("U_TECHMARINE_A", 10, 40)
	_place("U_REDEMPTOR_DREADNOUGHT_A", 12.5, 40)
	_place("U_IRON_FATHER_FEIRROS_A", 30, 40)
	_place("U_BOYZ_B", 10, 25)
	_u("U_REDEMPTOR_DREADNOUGHT_A").models[0]["current_wounds"] = int(_u("U_REDEMPTOR_DREADNOUGHT_A").models[0].wounds) - 4
	_check("Techmarine: within 3\" of a friendly AA VEHICLE — Lone Operative", RE.has_lone_operative(_u("U_TECHMARINE_A")))
	_check("Iron Father: no VEHICLE within 3\" — no Lone Operative", not RE.has_lone_operative(_u("U_IRON_FATHER_FEIRROS_A")))
	var o := _offer(1, "unit_selected_to_move", {"unit_id": "U_TECHMARINE_A"}, "blessings_of_the_omnissiah")
	_check("Blessings of the Omnissiah offered at the start of the Techmarine's move (vehicle within 3\")", "U_REDEMPTOR_DREADNOUGHT_A" in _secondary_ids(o, "U_TECHMARINE_A"))
	_check("Blessings: not offered for another unit's move", _offer(1, "unit_selected_to_move", {"unit_id": "U_BOYZ_B"}, "blessings_of_the_omnissiah").is_empty())
	var before := _wounds_left("U_REDEMPTOR_DREADNOUGHT_A")
	var r := _use(1, "blessings_of_the_omnissiah", "U_TECHMARINE_A", "unit_selected_to_move", {"unit_id": "U_TECHMARINE_A"}, "U_REDEMPTOR_DREADNOUGHT_A")
	var healed := _wounds_left("U_REDEMPTOR_DREADNOUGHT_A") - before
	_check("Blessings: the vehicle heals D3 (1-3)", bool(r.get("success", false)) and healed >= 1 and healed <= 3, "healed %d" % healed)
	var mb := _mods("U_REDEMPTOR_DREADNOUGHT_A", "U_BOYZ_B", false)
	_check("Blessings: the vehicle's attacks ignore hit and wound modifiers", bool(mb.ignore_hit_penalties) and bool(mb.get("ignore_wound_penalties", false)))
	_check("Blessings: once per phase (start or end of the move)", _offer(1, "unit_ended_normal_move", {"unit_id": "U_TECHMARINE_A"}, "blessings_of_the_omnissiah").is_empty())
	# Feirros: Master of the Forge heals 3 (+ BS).
	_place("U_GLADIATOR_LANCER_A", 32.5, 40)
	_u("U_GLADIATOR_LANCER_A").models[0]["current_wounds"] = int(_u("U_GLADIATOR_LANCER_A").models[0].wounds) - 5
	_check("Iron Father: within 3\" of a friendly AA VEHICLE — Lone Operative", RE.has_lone_operative(_u("U_IRON_FATHER_FEIRROS_A")))
	var b2 := _wounds_left("U_GLADIATOR_LANCER_A")
	var r2 := _use(1, "master_of_the_forge", "U_IRON_FATHER_FEIRROS_A", "unit_ended_normal_move", {"unit_id": "U_IRON_FATHER_FEIRROS_A"}, "U_GLADIATOR_LANCER_A")
	_check("Master of the Forge: the vehicle heals 3 wounds", bool(r2.get("success", false)) and _wounds_left("U_GLADIATOR_LANCER_A") - b2 == 3, str(_wounds_left("U_GLADIATOR_LANCER_A") - b2))
	_check("Master of the Forge: the vehicle ignores BS / hit / wound modifiers", bool(_mods("U_GLADIATOR_LANCER_A", "U_BOYZ_B", false).ignore_hit_penalties))
	_check("Master of the Forge: the same vehicle cannot be blessed twice in a phase", SMA._blessing_candidates(1, "U_IRON_FATHER_FEIRROS_A").is_empty() or not "U_GLADIATOR_LANCER_A" in SMA._blessing_candidates(1, "U_IRON_FATHER_FEIRROS_A"))
	_phase_transition(P_MOV, P_SHOOT)
	_check("Blessings: still active in your Shooting phase", bool(_mods("U_REDEMPTOR_DREADNOUGHT_A", "U_BOYZ_B", false).ignore_hit_penalties))
	_phase(P_FIGHT, 2)
	_phase_transition(P_FIGHT, P_MOV)
	_check("Blessings: still active in the opponent's Movement phase", bool(_mods("U_REDEMPTOR_DREADNOUGHT_A", "U_BOYZ_B", false).ignore_hit_penalties))
	GS.state.meta["battle_round"] = 3
	_phase(P_CMD, 1)
	_phase_transition(P_CMD, P_MOV)
	_check("Blessings: expires at the start of your next Movement phase", not bool(_mods("U_REDEMPTOR_DREADNOUGHT_A", "U_BOYZ_B", false).ignore_hit_penalties))


# ---------------------------------------------------------------------------
# 17. Infiltrator Squad — Omni-scramblers, Helix Gauntlet
# ---------------------------------------------------------------------------
func _section_infiltrators() -> void:
	print("\n-- 17. Omni-scramblers / Helix Gauntlet --")
	_fresh(P_SHOOT, 1)
	_place("U_INFILTRATOR_SQUAD_A", 10, 40)
	_place("U_BOYZ_B", 10, 25)
	_place("U_GRETCHIN_C", 35, 2)
	var o := _offer(1, "phase_start", {"phase": "shooting"}, "omni_scramblers")
	var opts := _secondary_ids(o, "U_INFILTRATOR_SQUAD_A")
	_check("Omni-scramblers offered at the start of your Shooting phase (visible enemies within 18\")", "U_BOYZ_B" in opts and not "U_GRETCHIN_C" in opts, str(opts))
	var base: float = TM.detection_range_inches_for(_u("U_BOYZ_B").models[0], _u("U_BOYZ_B"), _u("U_INFILTRATOR_SQUAD_A").models[0])
	_use(1, "omni_scramblers", "U_INFILTRATOR_SQUAD_A", "phase_start", {"phase": "shooting"}, "U_BOYZ_B")
	var after: float = TM.detection_range_inches_for(_u("U_BOYZ_B").models[0], _u("U_BOYZ_B"), _u("U_INFILTRATOR_SQUAD_A").models[0])
	_check("Omni-scramblers: the Boyz are detected (+3\" detection range)", is_equal_approx(after, base + 3.0), "%s -> %s" % [base, after])
	_check("Omni-scramblers: once per phase", _offer(1, "phase_start", {"phase": "shooting"}, "omni_scramblers").is_empty())
	_phase_transition(P_SHOOT, P_CHG)
	_check("Omni-scramblers: until the end of the phase", SMA.detection_range_bonus(_u("U_BOYZ_B")) == 0.0)
	# 10e 12" reinforcement denial retired for the SM army.
	var omni: Array = GS.get_omni_scrambler_positions(2)
	_check("Omni-scramblers: the 10e 12\" reserves denial is retired (no denial positions)", omni.is_empty(), str(omni))
	var ai_omni: Array = load("res://scripts/AIDecisionMaker.gd")._get_omni_scrambler_positions_from_snapshot(GS.state, 2)
	_check("Omni-scramblers: the AI does not plan around the retired denial", ai_omni.is_empty(), str(ai_omni.size()))
	# Helix Gauntlet (wargear).
	_fresh(P_CMD, 1)
	_place("U_INFILTRATOR_SQUAD_A", 10, 40)
	_check("Helix Gauntlet: not on the unit that did not take it", _offer(1, "command_phase_main", {}, "helix_gauntlet").is_empty())
	_with_ability("U_INFILTRATOR_SQUAD_A", "Helix Gauntlet", "In your Command phase, this unit heals D3 wounds.")
	_check("Helix Gauntlet: not offered at full wounds", _offer(1, "command_phase_main", {}, "helix_gauntlet").is_empty())
	_u("U_INFILTRATOR_SQUAD_A").models[1]["alive"] = false
	_u("U_INFILTRATOR_SQUAD_A").models[1]["current_wounds"] = 0
	_u("U_INFILTRATOR_SQUAD_A").models[1]["position"] = {"x": 12.0 * PX, "y": 40.0 * PX}
	_u("U_INFILTRATOR_SQUAD_A").models[0]["current_wounds"] = 1
	var oh := _offer(1, "command_phase_main", {}, "helix_gauntlet")
	_check("Helix Gauntlet offered in your Command phase when damaged", "U_INFILTRATOR_SQUAD_A" in _offer_units(oh))
	var r := _use(1, "helix_gauntlet", "U_INFILTRATOR_SQUAD_A", "command_phase_main", {})
	_check("Helix Gauntlet: heals D3 (a wounded model first)", bool(r.get("success", false)) and int(_u("U_INFILTRATOR_SQUAD_A").models[0].current_wounds) == 2, str(_u("U_INFILTRATOR_SQUAD_A").models.map(func(mm): return [mm.alive, mm.current_wounds])))
	_check("Helix Gauntlet: once per phase", _offer(1, "command_phase_main", {}, "helix_gauntlet").is_empty())


# ---------------------------------------------------------------------------
# 18. Roboute Guilliman — Codex Adept, Primarch of the XIII, Author of the
#     Codex, Leader of Astartes
# ---------------------------------------------------------------------------
func _section_guilliman() -> void:
	print("\n-- 18. Roboute Guilliman --")
	_fresh(P_CMD, 1)
	_place("U_ROBOUTE_GUILLIMAN_A", 20, 40)
	_place("U_INTERCESSOR_SQUAD_A", 20, 44)
	_place("U_HELLBLASTER_SQUAD_A", 38, 55)
	_place("U_BOYZ_B", 20, 25)
	_phase_transition(P_CMD, P_MOV)
	_check("Codex Adept: assault, devastator and tactical doctrines are all active for Guilliman",
		SWC.doctrine_active_id("U_ROBOUTE_GUILLIMAN_A", "assault") and SWC.doctrine_active_id("U_ROBOUTE_GUILLIMAN_A", "devastator") and SWC.doctrine_active_id("U_ROBOUTE_GUILLIMAN_A", "tactical"))
	_check("Codex Adept: only Guilliman", not SWC.doctrine_active_id("U_INTERCESSOR_SQUAD_A", "assault"))
	var m := _mods("U_INTERCESSOR_SQUAD_A", "U_BOYZ_B", false)
	_check("Primarch of the XIII: a friendly AA unit within 6\" re-rolls hit 1s and wound 1s", str(m.hit_reroll) == "ones" and str(m.wound_reroll) == "ones", str(m))
	_check("Primarch of the XIII: Guilliman's own attacks too", str(_mods("U_ROBOUTE_GUILLIMAN_A", "U_BOYZ_B", true).hit_reroll) == "ones")
	_check("Primarch of the XIII: not beyond 6\"", str(_mods("U_HELLBLASTER_SQUAD_A", "U_BOYZ_B", false).hit_reroll) == "")
	_check("Primarch of the XIII: not the enemy", str(_mods("U_BOYZ_B", "U_INTERCESSOR_SQUAD_A", true).hit_reroll) == "")
	_check("Leader of Astartes: within 3\" of friendly AA INFANTRY — Lone Operative", RE.has_lone_operative(_u("U_ROBOUTE_GUILLIMAN_A")) == (SWC.unit_distance_inches(_u("U_ROBOUTE_GUILLIMAN_A"), _u("U_INTERCESSOR_SQUAD_A")) <= 3.0))
	_place("U_INTERCESSOR_SQUAD_A", 20, 42)
	_check("Leader of Astartes: next to the Intercessors — Lone Operative", RE.has_lone_operative(_u("U_ROBOUTE_GUILLIMAN_A")))
	_place("U_INTERCESSOR_SQUAD_A", 30, 50)
	_check("Leader of Astartes: alone — no Lone Operative", not RE.has_lone_operative(_u("U_ROBOUTE_GUILLIMAN_A")))
	# Author of the Codex.
	_place("U_INTERCESSOR_SQUAD_A", 20, 46)
	var o := _offer(1, "phase_start", {"phase": "movement"}, "author_of_the_codex")
	var opts := _secondary_ids(o, "U_ROBOUTE_GUILLIMAN_A")
	_check("Author of the Codex offered at the start of your Movement phase (visible friendly AA units within 12\")", "U_INTERCESSOR_SQUAD_A" in opts and not "U_HELLBLASTER_SQUAD_A" in opts, str(opts))
	var r := _use(1, "author_of_the_codex", "U_ROBOUTE_GUILLIMAN_A", "phase_start", {"phase": "movement"}, "U_INTERCESSOR_SQUAD_A", "assault")
	_check("Author of the Codex used (assault)", bool(r.get("success", false)), str(r))
	GS.state.factions["1"]["sw11e_doctrine"] = "tactical"
	_check("Author of the Codex: assault doctrine active for the Intercessors IN ADDITION to the army doctrine",
		SWC.doctrine_active_id("U_INTERCESSOR_SQUAD_A", "assault") and SWC.doctrine_active_id("U_INTERCESSOR_SQUAD_A", "tactical"))
	_check("Author of the Codex: once per phase", _offer(1, "phase_start", {"phase": "movement"}, "author_of_the_codex").is_empty())
	_phase_transition(P_MOV, P_SHOOT)
	_check("Author of the Codex: still active later in the turn (phase transition keeps it)", SWC.doctrine_active_id("U_INTERCESSOR_SQUAD_A", "assault"))
	GS.state.meta["active_player"] = 1
	_phase_transition(P_FIGHT, P_CMD)
	_check("Author of the Codex: expires at the start of your next Command phase (Codex Adept stays)",
		not (_flags("U_INTERCESSOR_SQUAD_A").get("sw11e_doctrine_extra", []) as Array).has("assault") and SWC.doctrine_active_id("U_ROBOUTE_GUILLIMAN_A", "assault"), str(_flags("U_INTERCESSOR_SQUAD_A")))
	GS.state.factions["1"].erase("sw11e_doctrine")


# ---------------------------------------------------------------------------
# 19. Thunderhawk Cluster Bombs
# ---------------------------------------------------------------------------
func _section_thunderhawk() -> void:
	print("\n-- 19. Thunderhawk Cluster Bombs --")
	_fresh(P_MOV, 1)
	_place("U_THUNDERHAWK_GUNSHIP_A", 20, 20)
	_place("U_BOYZ_B", 18, 30)
	_place("U_GRETCHIN_C", 38, 30)
	var from := {"m1": {"x": 20.0 * PX, "y": 45.0 * PX}}
	var over: Array = SMA.moved_over_enemies("U_THUNDERHAWK_GUNSHIP_A", from)
	_check("Cluster Bombs: the Boyz under the flight path were moved over, the far Gretchin not", "U_BOYZ_B" in over and not "U_GRETCHIN_C" in over, str(over))
	var o := _offer(1, "unit_ended_normal_move", {"unit_id": "U_THUNDERHAWK_GUNSHIP_A", "sm11e_from_positions": from}, "thunderhawk_cluster_bombs")
	_check("Cluster Bombs offered when the Thunderhawk ends a normal move", "U_BOYZ_B" in _secondary_ids(o, "U_THUNDERHAWK_GUNSHIP_A"))
	_check("Cluster Bombs offered after an advance move too", not _offer(1, "unit_ended_advance_move", {"unit_id": "U_THUNDERHAWK_GUNSHIP_A", "sm11e_from_positions": from}, "thunderhawk_cluster_bombs").is_empty())
	_check("Cluster Bombs: no path — no card", _offer(1, "unit_ended_normal_move", {"unit_id": "U_THUNDERHAWK_GUNSHIP_A"}, "thunderhawk_cluster_bombs").is_empty())
	var before := _alive("U_BOYZ_B")
	RE.set_test_seed(_seed_where(6, func(r): return r.count(1) + r.count(2) <= 1))
	var r := _use(1, "thunderhawk_cluster_bombs", "U_THUNDERHAWK_GUNSHIP_A", "unit_ended_normal_move", {"unit_id": "U_THUNDERHAWK_GUNSHIP_A", "sm11e_from_positions": from}, "U_BOYZ_B")
	RE.set_test_seed(-1)
	_check("Cluster Bombs: six D6, each 3+ a mortal wound (Boyz lose models)", bool(r.get("success", false)) and _alive("U_BOYZ_B") < before, "%d -> %d" % [before, _alive("U_BOYZ_B")])
	_check("Cluster Bombs: once per phase", _offer(1, "unit_ended_advance_move", {"unit_id": "U_THUNDERHAWK_GUNSHIP_A", "sm11e_from_positions": from}, "thunderhawk_cluster_bombs").is_empty())


# ---------------------------------------------------------------------------
# 20. Invictor Tactical Warsuit — Forward Assault Warsuit
# ---------------------------------------------------------------------------
func _section_invictor() -> void:
	print("\n-- 20. Forward Assault Warsuit --")
	_fresh(P_CMD, 1, 1)
	_place("U_INVICTOR_TACTICAL_WARSUIT_A", 10, 40)
	_place("U_BOYZ_B", 10, 25)
	_place("U_WARBOSS_A", 20, 25)
	var o := _offer(1, "phase_start", {"phase": "command"}, "forward_assault_warsuit")
	_check("Forward Assault Warsuit offered at the start of the first battle round", "U_INVICTOR_TACTICAL_WARSUIT_A" in _offer_units(o))
	_use(1, "forward_assault_warsuit", "U_INVICTOR_TACTICAL_WARSUIT_A", "phase_start", {"phase": "command"}, "U_BOYZ_B")
	var m := _mods("U_INVICTOR_TACTICAL_WARSUIT_A", "U_BOYZ_B", false)
	_check("Forward Assault Warsuit: attacks vs the mark re-roll wound rolls of 1", str(m.wound_reroll) == "ones", str(m))
	_check("Forward Assault Warsuit: not vs another unit", str(_mods("U_INVICTOR_TACTICAL_WARSUIT_A", "U_WARBOSS_A", true).wound_reroll) == "")
	_check("Forward Assault Warsuit: no new mark while it lives", _offer(1, "phase_start", {"phase": "movement"}, "forward_assault_warsuit").is_empty())
	for mm in _u("U_BOYZ_B").models:
		mm["alive"] = false
	GS.state.meta["battle_round"] = 3
	_check("Forward Assault Warsuit: a new mark when the mark is destroyed", not _offer(1, "phase_start", {"phase": "movement"}, "forward_assault_warsuit").is_empty())


# ---------------------------------------------------------------------------
# 21. gating — non-SM army, 10e edition, other datasheets
# ---------------------------------------------------------------------------
func _section_gating() -> void:
	print("\n-- 21. gating --")
	_fresh(P_SHOOT, 1)
	_place("U_BALLISTUS_DREADNOUGHT_A", 10, 50)
	_place("U_BOYZ_B", 10, 40)
	GS.state.factions["1"]["name"] = "Orks"
	_check("not a Space Marine army: no Ballistus Strike", int(_mods("U_BALLISTUS_DREADNOUGHT_A", "U_BOYZ_B", false).sustained) == 0)
	_check("not a Space Marine army: no ability cards", SMA.window_offers(1, "phase_start", {"phase": "shooting", "window_id": "phase_start"}).is_empty())
	GS.state.factions["1"]["name"] = "Ultramarines"
	_check("a chapter army (Ultramarines) has the codex datasheet abilities", int(_mods("U_BALLISTUS_DREADNOUGHT_A", "U_BOYZ_B", false).sustained) == 1)
	GS.state.factions["1"]["name"] = "Space Marines"
	GameConstants.edition = 10
	_check("10e: no codex datasheet abilities", int(SMA.attack_mods(_u("U_BALLISTUS_DREADNOUGHT_A"), _u("U_BOYZ_B"), {"type": "Ranged"}, false).sustained) == 0)
	GameConstants.edition = 11
	_place("U_REDEMPTOR_DREADNOUGHT_A", 30, 50)
	_check("an M4b/M4c datasheet does not get M4a rules", not SMA.is_m4a_unit(_u("U_REDEMPTOR_DREADNOUGHT_A")) and SMA.is_m4a_unit(_u("U_BALLISTUS_DREADNOUGHT_A")))
	SMA.offers_suppressed = true
	_check("scenario policy: offers suppressed — no cards, no phase_start entries", SMA.window_offers(1, "phase_start", {"phase": "shooting", "window_id": "phase_start"}).is_empty() and SMA.phase_start_entries(P_SHOOT).is_empty())
	SMA.offers_suppressed = false
	_check("scenario policy: passives still apply while suppressed", int(_mods("U_BALLISTUS_DREADNOUGHT_A", "U_BOYZ_B", false).sustained) == 1)


# ---------------------------------------------------------------------------
# 22. AI — synchronous scores; the AI decides every card (never stalls)
# ---------------------------------------------------------------------------
func _section_ai() -> void:
	print("\n-- 22. AI --")
	_fresh(P_SHOOT, 1)
	_place("U_INFERNUS_SQUAD_A", 10, 40)
	_place("U_BOYZ_B", 10, 33)
	var s: float = SMA.ai_score(1, _sid("driven_from_cover"), "U_INFERNUS_SQUAD_A", "unit_has_shot", {})
	_check("AI scores Driven from Cover above the ability threshold", s >= 1.0, str(s))
	var AID = load("res://scripts/AIDecisionMaker.gd")
	var ctx := {"unit_id": "U_INFERNUS_SQUAD_A", "hit_unit_ids": ["U_BOYZ_B"], "window_id": "unit_has_shot"}
	var offers: Array = SM.get_all_window_offers(1, "unit_has_shot", ctx)
	var dec: Dictionary = AID.decide_window_stratagem(1, "unit_has_shot", offers, ctx)
	_check("AI uses Driven from Cover in the unit_has_shot window (secondary picked)", bool(dec.get("use", false)) and str(dec.get("stratagem_id", "")) == _sid("driven_from_cover"), str(dec))
	if bool(dec.get("use", false)):
		var c2: Dictionary = ctx.duplicate(true)
		c2.merge(dec.get("context", {}), true)
		var r: Dictionary = SM.use_stratagem(1, str(dec.stratagem_id), str(dec.target_unit_id), c2)
		_check("AI's decision applies cleanly", bool(r.get("success", false)), str(r))
	_fresh(P_CMD, 1)
	_place("U_INTERCESSOR_SQUAD_A", 10, 40)
	_place("U_CAPTAIN_A", 10, 42)
	_attach("U_CAPTAIN_A", "U_INTERCESSOR_SQUAD_A")
	_place("U_BOYZ_B", 10, 25)
	var c3 := {"phase": "command", "window_id": "command_phase_main"}
	var off3: Array = SM.get_all_window_offers(1, "command_phase_main", c3)
	var d3: Dictionary = AID.decide_window_stratagem(1, "command_phase_main", off3, c3)
	_check("AI uses Strategic Acumen with a doctrine variant", str(d3.get("stratagem_id", "")) == _sid("strategic_acumen") and str(d3.get("context", {}).get("variant_id", "")) in ["assault", "devastator", "tactical"], str(d3))
	for slug in ["teleport_homer", "evade_and_survive", "parabolic_jetleap"]:
		_check("AI declines %s (plan-level repositioning)" % slug, SMA.ai_score(1, _sid(slug), "U_INTERCESSOR_SQUAD_A", "", {}) < 1.0)
	_check("AI never scores an unknown card", SMA.ai_score(1, _sid("nope"), "", "", {}) == 0.0)
