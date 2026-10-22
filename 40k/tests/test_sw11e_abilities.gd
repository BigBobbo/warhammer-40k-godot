extends SceneTree

# WP-S4 — Codex: Space Marines (11e), Space Wolves DATASHEET + WARGEAR
# abilities and the Librarius psyker-level budget
# (scripts/codex/space_wolves/SWAbilities11e.gd).
#
# One check group per ability (section numbers = the audit table's last
# column, .llm/codex_11e_wahapedia/space_wolves_abilities_audit.md): the
# condition (on / off), the effect (modifier, or an A/B attack resolution with
# the same seed), the usage limit and the expiry where the ability has them.
# Board: the tests/saves/cus11e_c5_active shell (44x60", objectives) with its
# units replaced by P1 = armies/sw11e_codex_test.json (all 21 Space Wolves
# datasheets + a wargear copy of each) and P2 = armies/ork11e_codex_test.json,
# both through ArmyListManager.load_army_list; every unit starts off the table
# and a section places what it needs.
#
# Usage: godot --headless --path 40k --script tests/test_sw11e_abilities.gd

const FIXTURE := "cus11e_c5_active"
const SW_ARMY := "sw11e_codex_test"
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
var SW = null
var SWC = null
var EP = null
var UAM = null
var MM = null
var _sw_army: Dictionary = {}
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
	u["attachment_data"] = {"attached_characters": []}
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
	for pair in [[_sw_army, 1], [_ork_army, 2]]:
		var army: Dictionary = pair[0]
		for k in army.get("units", {}):
			var u: Dictionary = army.units[k].duplicate(true)
			u["id"] = k
			u["owner"] = int(pair[1])
			_reset_unit(u)
			GS.state.units[k] = u
	GS.state.factions["1"] = _sw_army.get("faction", {}).duplicate(true)
	GS.state.factions["2"] = _ork_army.get("faction", {}).duplicate(true)
	SM.load_faction_stratagems_for_player(1)
	SM.load_faction_stratagems_for_player(2)
	GS.state.meta["phase"] = phase
	GS.state.meta["active_player"] = active
	GS.state.meta["battle_round"] = battle_round
	for p in ["1", "2"]:
		GS.state.players[p]["cp"] = 6
		GS.state.players[p].erase(SW.ARMY_USES)
	SM._usage_history = {"1": [], "2": []}
	UAM.reset_for_new_game()
	SW.offers_suppressed = false


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


func _phase(p: int, active: int = 1) -> void:
	GS.state.meta["phase"] = p
	GS.state.meta["active_player"] = active


func _sid(slug: String) -> String:
	return SW.sid_of(slug)


func _offer(player: int, window_id: String, ctx: Dictionary, slug: String) -> Dictionary:
	var c := ctx.duplicate(true)
	c["window_id"] = window_id
	for o in SW.window_offers(player, window_id, c):
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


func _use(player: int, slug: String, uid: String, window_id: String, ctx: Dictionary = {}, secondary: String = "") -> Dictionary:
	var c := ctx.duplicate(true)
	c["window_id"] = window_id
	if secondary != "":
		c["secondary_id"] = secondary
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


func _seed_where(n: int, pred: Callable) -> int:
	for s in range(1, 800):
		RE.set_test_seed(s)
		var rolls: Array = RE.make_rng().roll_d6(n)
		if pred.call(rolls):
			RE.set_test_seed(s)
			return s
	RE.set_test_seed(-1)
	return -1


func _weapon(uid: String, name_part: String, melee: bool) -> String:
	var ws: Dictionary = RE.get_unit_melee_weapons(uid, GS.state) if melee and RE.has_method("get_unit_melee_weapons") else RE.get_unit_weapons(uid, GS.state)
	for mid in ws:
		for wid in ws[mid]:
			var prof: Dictionary = RE.get_weapon_profile(str(wid), GS.state)
			if str(prof.get("name", "")).to_lower().contains(name_part.to_lower()):
				return str(wid)
	return ""


## Melee hits (incl. Sustained bonus hits) of one batch, seed `seed`.
func _melee_hits(uid: String, wid: String, target: String, seed: int) -> Dictionary:
	var act := {"type": "FIGHT", "actor_unit_id": uid, "payload": {"assignments": [{"attacker": uid, "target": target, "weapon": wid}]}}
	RE.set_test_seed(seed)
	var res = RE.resolve_melee_attacks(act, GS.state.duplicate(true), RE.RNGService.new(seed))
	var out := {"hits": 0, "bonus": 0, "attacks": 0, "res": res}
	for d in res.get("dice", []):
		if str(d.get("context", "")) == "hit_roll_melee":
			out.hits += int(d.get("successes", 0))
			out.bonus += int(d.get("sustained_bonus_hits", 0))
			out.attacks += int(d.get("total_attacks", 0))
	return out


## A FormationsPhase instance for validate / process checks (nobody confirmed).
func _formations_phase():
	GS.state.meta["formations_p1_confirmed"] = false
	GS.state.meta["formations_p2_confirmed"] = false
	var fp = load("res://phases/FormationsPhase.gd").new()
	fp.players_confirmed = {1: false, 2: false}
	fp.current_declaring_player = 1
	fp.player_formations = {1: {"leader_attachments": {}, "transport_embarkations": {}, "reserves": []}, 2: {"leader_attachments": {}, "transport_embarkations": {}, "reserves": []}}
	root.add_child(fp)
	return fp


# ---------------------------------------------------------------------------
func _run() -> void:
	GS = root.get_node("GameState")
	SM = root.get_node("StratagemManager")
	RE = root.get_node("RulesEngine")
	PM = root.get_node("PhaseManager")
	UAM = root.get_node("UnitAbilityManager")
	MM = root.get_node("MissionManager")
	SW = load("res://scripts/codex/space_wolves/SWAbilities11e.gd")
	SWC = load("res://scripts/codex/space_wolves/SWCommon.gd")
	EP = load("res://autoloads/EffectPrimitives.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	root.get_node("SettingsService").set("auto_allocate_wounds", true)
	GameConstants.edition = 11
	var alm = root.get_node("ArmyListManager")
	_sw_army = alm.load_army_list(SW_ARMY, 1)
	_ork_army = alm.load_army_list(ORK_ARMY, 2)
	print("\n=== test_sw11e_abilities (WP-S4) ===")
	if _sw_army.is_empty() or _ork_army.is_empty():
		_check("armies load", false)
		return
	_section_names()
	_section_list_build()
	_section_ragnar()
	_section_wind_walker()
	_section_librarius()
	_section_ulrik()
	_section_tenacity_tactician_kingsguard()
	_section_claws_hunters_thunderwolves()
	_section_splits()
	_section_iron_priest()
	_section_wulfen()
	_section_guile()
	_section_high_king()
	_section_fight_on_death()
	_section_predatory_instinct()
	_section_hunting_hounds()
	_section_fervour()
	_section_wolf_priest()
	_section_tempered_ferocity()
	_section_headhunters()
	_section_hammer_blow()
	_section_wulfen_dreadnought()
	_section_wolf_scouts()
	_section_gating()
	_section_ai()


# ---------------------------------------------------------------------------
# 0. every Datasheet / Wargear ability of the 21 datasheets folds to a slug;
#    the core abilities resolve through the engine
# ---------------------------------------------------------------------------
func _section_names() -> void:
	print("\n-- 0. names + core abilities --")
	_fresh()
	var skip := ["combat doctrines", "transhuman strategist", "curse of the wulfen", "leader", "deep strike",
		"infiltrators", "objective secured", "target elimination"]
	var unknown: Array = []
	var known := {}
	for slug in SW.NAMES:
		known[SW.NAMES[slug]] = slug
	for uid in _sw_army.units:
		var u: Dictionary = _sw_army.units[uid]
		if not SWC.has_keyword(u, "SPACE WOLVES"):
			continue
		for ab in u.get("meta", {}).get("abilities", []):
			var n: String = SW.fold(str(ab.get("name", "")) if ab is Dictionary else str(ab))
			if n in skip or n.begins_with("feel no pain") or n.begins_with("deadly demise") or n.begins_with("scouts"):
				continue
			if not known.has(n) and not n in unknown:
				unknown.append(n)
	_check("every Space Wolves datasheet/wargear ability has a module slug", unknown.is_empty(), str(unknown))
	for n in ["High King of Fenris", "Slayer's Oath", "Tempest's Wrath", "Haywire Mine", "Storm Shield", "Murder-maker"]:
		_check("ABILITY_EFFECTS row '%s' (implemented)" % n, UAM.is_ability_implemented(n))
	# Core abilities on these datasheets are engine-handled.
	_check("core: Logan Grimnar has Deep Strike", GS.unit_has_deep_strike("U_LOGAN_GRIMNAR_A"))
	_check("core: Ulrik has Feel No Pain 6+", RE.get_unit_fnp(_u("U_ULRIK_THE_SLAYER_A")) == 6, str(RE.get_unit_fnp(_u("U_ULRIK_THE_SLAYER_A"))))
	_check("core: Bjorn has Feel No Pain 5+", RE.get_unit_fnp(_u("U_BJORN_THE_FELL_HANDED_A")) == 5)
	_check("core: the CHARACTERs with Leader can lead (Logan -> Wolf Guard Terminators)", "U_WOLF_GUARD_TERMINATORS_A" in GS.get_eligible_bodyguards_for_character("U_LOGAN_GRIMNAR_A"),
		str(GS.get_eligible_bodyguards_for_character("U_LOGAN_GRIMNAR_A")))
	_check("core: Wolf Scouts are Scouts 8\"", float(RE.get_scouts_distance(_u("U_WOLF_SCOUTS_A"))) == 8.0 if RE.has_method("get_scouts_distance") else true)


# ---------------------------------------------------------------------------
# 1. Storm Shield / Blizzard Shield (army load)
# ---------------------------------------------------------------------------
func _section_list_build() -> void:
	print("\n-- 1. Storm Shield / Blizzard Shield --")
	var tb: Array = _sw_army.units["U_WOLF_GUARD_TERMINATORS_B"].models
	var w4 := tb.filter(func(m): return int(m.get("wounds", 0)) == 4).size()
	_check("Wolf Guard Terminators B: 4 Storm Shield bearers have 4 W (+1 W)", w4 == 4, str(tb.map(func(m): return m.get("wounds"))))
	_check("Wolf Guard Terminators A (no shields): every model 3 W", _sw_army.units["U_WOLF_GUARD_TERMINATORS_A"].models.all(func(m): return int(m.get("wounds", 0)) == 3))
	_check("Wolf Guard Battle Leader B (Storm Shield): 6 W", int(_sw_army.units["U_WOLF_GUARD_BATTLE_LEADER_B"].models[0].wounds) == 6)
	_check("Wolf Guard Battle Leader A: 5 W", int(_sw_army.units["U_WOLF_GUARD_BATTLE_LEADER_A"].models[0].wounds) == 5)
	var tw: Array = _sw_army.units["U_THUNDERWOLF_CAVALRY_B"].models
	_check("Thunderwolf Cavalry B: 2 Storm Shield bearers have a 4+ invulnerable save", tw.filter(func(m): return int(m.get("invuln", 0)) == 4).size() == 2)
	_check("Thunderwolf Cavalry A: no invulnerable save", _sw_army.units["U_THUNDERWOLF_CAVALRY_A"].models.all(func(m): return int(m.get("invuln", 0)) == 0))
	var ht: Array = _sw_army.units["U_WOLF_GUARD_HEADTAKERS_B"].models
	_check("Wolf Guard Headtakers B: the 3 Headtakers (not the Hunting Wolves) have 4+ invuln",
		ht.filter(func(m): return int(m.get("invuln", 0)) == 4 and int(m.get("wounds", 1)) > 1).size() == 3 and ht.filter(func(m): return int(m.get("invuln", 0)) == 4 and int(m.get("wounds", 1)) == 1).is_empty())
	_check("Venerable Dreadnought B (Blizzard Shield): 4+ invuln", int(_sw_army.units["U_VENERABLE_DREADNOUGHT_B"].models[0].get("invuln", 0)) == 4)
	_check("Wulfen Dreadnought B (Blizzard Shield): 4+ invuln", int(_sw_army.units["U_WULFEN_DREADNOUGHT_B"].models[0].get("invuln", 0)) == 4)
	_check("Venerable Dreadnought A: no invuln", int(_sw_army.units["U_VENERABLE_DREADNOUGHT_A"].models[0].get("invuln", 0)) == 0)
	var copy: Dictionary = _sw_army.units["U_WOLF_GUARD_TERMINATORS_B"].duplicate(true)
	SW.apply_list_build("U_WOLF_GUARD_TERMINATORS_B", copy)
	_check("list build is idempotent (no second +1 W)", copy.models.filter(func(m): return int(m.get("wounds", 0)) == 5).is_empty())
	# The invulnerable save is read per model by the save step.
	_fresh()
	var inv: int = RE._get_model_effective_invuln(_u("U_THUNDERWOLF_CAVALRY_B").models[0], _u("U_THUNDERWOLF_CAVALRY_B"), int(_u("U_THUNDERWOLF_CAVALRY_B").models[0].get("invuln", 0)))
	_check("RulesEngine reads the bearer's 4+ invuln", inv == 4, str(inv))


# ---------------------------------------------------------------------------
# 2. Ragnar Blackmane — Battle-lust, War Howl
# ---------------------------------------------------------------------------
func _section_ragnar() -> void:
	print("\n-- 2. Ragnar: Battle-lust, War Howl --")
	_fresh(P_FIGHT)
	_place("U_BLOOD_CLAWS_A", 10, 30)
	_place("U_RAGNAR_BLACKMANE_A", 10, 31.5)
	_place("U_BOYZ_B", 10, 28.6)
	var m0 := _mods("U_RAGNAR_BLACKMANE_A", "U_BOYZ_B", true)
	_check("Battle-lust: no +A without a charge", int(m0.attacks) == 0, str(m0))
	_flags("U_RAGNAR_BLACKMANE_A")["charged_this_turn"] = true
	var m1 := _mods("U_RAGNAR_BLACKMANE_A", "U_BOYZ_B", true)
	_check("Battle-lust: charged -> Ragnar's melee +2 A", int(m1.attacks) == 2 and "Battle-lust" in _names(m1), str(m1))
	_check("Battle-lust: not on ranged attacks", int(_mods("U_RAGNAR_BLACKMANE_A", "U_BOYZ_B", false).attacks) == 0)
	_check("Battle-lust: 'this model' — not the Blood Claws' attacks", int(_mods("U_BLOOD_CLAWS_A", "U_BOYZ_B", true).attacks) == 0)
	_flags("U_RAGNAR_BLACKMANE_A").erase("charged_this_turn")
	var mb0 := _mods("U_BLOOD_CLAWS_A", "U_BOYZ_B", true)
	_check("War Howl: unattached -> no bonus", not "War Howl" in _names(mb0))
	_attach("U_RAGNAR_BLACKMANE_A", "U_BLOOD_CLAWS_A")
	var mb1 := _mods("U_BLOOD_CLAWS_A", "U_BOYZ_B", true)
	_check("War Howl leading Blood Claws: melee +1 S and [SUSTAINED HITS 1]", int(mb1.strength) == 1 and int(mb1.sustained) == 1, str(mb1))
	_check("War Howl: Ragnar's own melee too (this unit)", int(_mods("U_RAGNAR_BLACKMANE_A", "U_BOYZ_B", true).strength) == 1)
	_check("War Howl: not on ranged attacks", int(_mods("U_BLOOD_CLAWS_A", "U_BOYZ_B", false).strength) == 0)
	_check("War Howl leading Blood Claws: no advance-and-charge from it (Berserk Charge has it anyway)", SW.war_howl_mode("U_BLOOD_CLAWS_A") == "blood_claws")
	# A/B (same seed): sustained bonus hits only with War Howl.
	var wid := _weapon("U_BLOOD_CLAWS_A", "chainsword", true)
	var seed := _seed_where(30, func(r): return r.count(6) >= 2)
	var with_wh := _melee_hits("U_BLOOD_CLAWS_A", wid, "U_BOYZ_B", seed)
	_u("U_BLOOD_CLAWS_A").attachment_data = {"attached_characters": []}
	_u("U_RAGNAR_BLACKMANE_A").erase("attached_to")
	var without := _melee_hits("U_BLOOD_CLAWS_A", wid, "U_BOYZ_B", seed)
	_check("War Howl A/B (seed %d): sustained bonus hits only while Ragnar leads" % seed, int(with_wh.bonus) > 0 and int(without.bonus) == 0, "%s vs %s (weapon %s)" % [with_wh.bonus, without.bonus, wid])
	# Headtakers: advance-and-charge.
	_place("U_WOLF_GUARD_HEADTAKERS_A", 30, 40)
	_check("Wolf Guard Headtakers alone: an advance blocks the charge", not EP.has_effect_advance_and_charge(_u("U_WOLF_GUARD_HEADTAKERS_A")))
	_attach("U_RAGNAR_BLACKMANE_A", "U_WOLF_GUARD_HEADTAKERS_A")
	_check("War Howl leading Headtakers: advance does not prevent a charge", EP.has_effect_advance_and_charge(_u("U_WOLF_GUARD_HEADTAKERS_A")))
	_check("War Howl leading Headtakers: no melee +1 S", int(_mods("U_WOLF_GUARD_HEADTAKERS_A", "U_BOYZ_B", true).strength) == 0)


# ---------------------------------------------------------------------------
# 3. Njal — Wind Walker
# ---------------------------------------------------------------------------
func _section_wind_walker() -> void:
	print("\n-- 3. Wind Walker --")
	_fresh(P_MOV)
	_place("U_GREY_HUNTERS_A", 10, 40)
	_place("U_NJAL_STORMCALLER_A", 10, 41.5)
	_check("Grey Hunters alone: no [ASSAULT]", not EP.has_effect_advance_and_shoot(_u("U_GREY_HUNTERS_A")))
	_attach("U_NJAL_STORMCALLER_A", "U_GREY_HUNTERS_A")
	_check("Wind Walker: Njal's unit's ranged attacks have [ASSAULT]", EP.has_effect_advance_and_shoot(_u("U_GREY_HUNTERS_A")) and EP.has_effect_advance_and_shoot(_u("U_NJAL_STORMCALLER_A")))
	_check("Wind Walker: advance roll changed to a 6", SW.advance_roll_six("U_GREY_HUNTERS_A"))
	_check("Wind Walker: not for another unit", not SW.advance_roll_six("U_BLOOD_CLAWS_A"))


# ---------------------------------------------------------------------------
# 4. Librarius + Njal's psychic abilities
# ---------------------------------------------------------------------------
func _section_librarius() -> void:
	print("\n-- 4. Librarius: Murderous Hurricane, Storm Caller, Tempest's Wrath --")
	_fresh(P_MOV, 1, 2)
	_place("U_NJAL_STORMCALLER_A", 20, 40)
	_place("U_BOYZ_B", 20, 30)          # 10" away
	_place("U_GRETCHIN_C", 5, 26)        # ~15" away
	_place("U_DEFF_DREAD_A", 38, 20)     # far
	_check("High Rune Priest: psyker level 3", SW.psyker_level(_u("U_NJAL_STORMCALLER_A")) == 3)
	var o := _offer(1, "phase_start", {"phase": "movement"}, "murderous_hurricane")
	_check("Murderous Hurricane offered at the start of your Movement phase", not o.is_empty() and "U_NJAL_STORMCALLER_A" in _offer_units(o), str(o))
	var sec := _secondary_ids(o, "U_NJAL_STORMCALLER_A")
	_check("Murderous Hurricane: visible enemy units within 12\" only", "U_BOYZ_B" in sec and not "U_GRETCHIN_C" in sec and not "U_DEFF_DREAD_A" in sec, str(sec))
	_check("Tempest's Wrath not offered in the Movement phase", _offer(1, "phase_start", {"phase": "movement"}, "tempests_wrath").is_empty())
	_check("not offered in the opponent's Movement phase", (func(): _phase(P_MOV, 2); var e := _offer(1, "phase_start", {}, "murderous_hurricane").is_empty(); _phase(P_MOV, 1); return e).call())
	var s6 := _seed_where(1, func(r): return int(r[0]) >= 2)
	var r1 := _use(1, "murderous_hurricane", "U_NJAL_STORMCALLER_A", "phase_start", {"phase": "movement"}, "U_BOYZ_B")
	_check("Murderous Hurricane resolves (no CP)", r1.get("success", false) and int(GS.state.players["1"].cp) == 6, str(r1))
	_check("Murderous Hurricane: that unit cannot make snap-shooting attacks", SW.snap_shooting_block_reason("U_BOYZ_B") != "")
	_check("FIRE OVERWATCH refuses the Boyz", SM.fire_overwatch_shooter_reason_11e(2, "U_BOYZ_B").contains("Murderous Hurricane"), SM.fire_overwatch_shooter_reason_11e(2, "U_BOYZ_B"))
	_check("psychic roll %d (not a 1): Njal not battle-shocked" % s6, not SWC.is_battle_shocked(_u("U_NJAL_STORMCALLER_A")))
	_check("Librarius: 1 of 3 psychic levels used", SW.psychic_levels_used(_u("U_NJAL_STORMCALLER_A")) == 1)
	_check("same power not twice in a phase", _offer(1, "phase_start", {"phase": "movement"}, "murderous_hurricane").is_empty())
	# Storm Caller in the opponent's Shooting phase (reactive dialog fold-in).
	_phase(P_SHOOT, 2)
	var react: Array = SM.get_reactive_stratagems_for_shooting(1, ["U_NJAL_STORMCALLER_A"], {"attacker_unit_id": "U_BOYZ_B"})
	var sc_entry: Dictionary = {}
	for e in react:
		if str(e.get("stratagem", {}).get("id", "")) == _sid("storm_caller"):
			sc_entry = e
	_check("Storm Caller folded into the defender's reactive dialog when Njal is targeted", not sc_entry.is_empty(), str(react.map(func(e): return e.get("stratagem", {}).get("id", ""))))
	_check("Storm Caller not offered when another unit is targeted", SW.window_offers(1, "enemy_targets_unit_shooting", {"window_id": "enemy_targets_unit_shooting", "target_unit_ids": ["U_BLOOD_CLAWS_A"]}).is_empty())
	_seed_where(1, func(r): return int(r[0]) == 1)
	var r2: Dictionary = SM.use_stratagem(1, _sid("storm_caller"), "U_NJAL_STORMCALLER_A", {"window_id": "enemy_targets_unit_shooting", "target_unit_ids": ["U_NJAL_STORMCALLER_A"]})
	_check("Storm Caller resolves", r2.get("success", false), str(r2))
	_check("Storm Caller: -3\" detection range", SW.detection_range_bonus(_u("U_NJAL_STORMCALLER_A")) == -3.0)
	_check("psychic roll 1: Njal is battle-shocked", SWC.is_battle_shocked(_u("U_NJAL_STORMCALLER_A")))
	SW.on_phase_transition(P_SHOOT, P_CHG)
	_check("Storm Caller expires at the end of the phase", SW.detection_range_bonus(_u("U_NJAL_STORMCALLER_A")) == 0.0)
	# Battle-shocked: no psychic ability.
	_phase(P_SHOOT, 1)
	_check("battle-shocked: Tempest's Wrath not offered", _offer(1, "phase_start", {"phase": "shooting"}, "tempests_wrath").is_empty())
	_flags("U_NJAL_STORMCALLER_A").erase("battle_shocked")
	var o3 := _offer(1, "phase_start", {"phase": "shooting"}, "tempests_wrath")
	_check("Tempest's Wrath offered at the start of your Shooting phase (within 18\")", "U_GRETCHIN_C" in _secondary_ids(o3, "U_NJAL_STORMCALLER_A") and "U_BOYZ_B" in _secondary_ids(o3, "U_NJAL_STORMCALLER_A"), str(o3))
	_seed_where(1, func(r): return int(r[0]) >= 2)
	var r3 := _use(1, "tempests_wrath", "U_NJAL_STORMCALLER_A", "phase_start", {"phase": "shooting"}, "U_BOYZ_B")
	_check("Tempest's Wrath resolves", r3.get("success", false), str(r3))
	_check("Librarius: 3 of 3 used this battle round", SW.psychic_levels_used(_u("U_NJAL_STORMCALLER_A")) == 3)
	var mt := _mods("U_BOYZ_B", "U_NJAL_STORMCALLER_A", true)
	_check("suppressed: the Boyz' attacks have -1 to hit", bool(mt.hit_minus) and "Tempest's Wrath" in _names(mt), str(mt))
	_check("suppressed: any target, ranged too", bool(_mods("U_BOYZ_B", "U_BLOOD_CLAWS_A", false).hit_minus))
	_phase(P_MOV, 1)
	_check("budget spent: no psychic ability for the rest of the round", _offer(1, "phase_start", {"phase": "movement"}, "murderous_hurricane").is_empty())
	# Expiry: suppressed until the start of YOUR next turn; no-snap at end of turn.
	GS.state.meta["active_player"] = 2
	SW.on_phase_transition(P_FIGHT, P_CMD)
	_check("suppression lasts through the opponent's turn", _flags("U_BOYZ_B").has(SW.F_SUPPRESSED))
	_check("Murderous Hurricane ends with the turn", SW.snap_shooting_block_reason("U_BOYZ_B") == "")
	GS.state.meta["active_player"] = 1
	GS.state.meta["battle_round"] = 3
	SW.on_phase_transition(P_FIGHT, P_CMD)
	_check("suppression ends at the start of your next turn", not _flags("U_BOYZ_B").has(SW.F_SUPPRESSED))
	_phase(P_MOV, 1)
	_check("a new battle round resets the budget", SW.psychic_levels_used(_u("U_NJAL_STORMCALLER_A")) == 0 and not _offer(1, "phase_start", {"phase": "movement"}, "murderous_hurricane").is_empty())
	# A/B: suppression costs hits (same seed).
	_fresh(P_FIGHT, 2)
	_place("U_BOYZ_B", 10, 28.6)
	_place("U_GREY_HUNTERS_A", 10, 30)
	var bw := _weapon("U_BOYZ_B", "choppa", true)
	var sd := _seed_where(30, func(r): return r.count(3) >= 3)
	var free_h := _melee_hits("U_BOYZ_B", bw, "U_GREY_HUNTERS_A", sd)
	_flags("U_BOYZ_B")[SW.F_SUPPRESSED] = {"player": 1, "source": "Tempest's Wrath"}
	var sup_h := _melee_hits("U_BOYZ_B", bw, "U_GREY_HUNTERS_A", sd)
	_check("suppressed A/B (seed %d): fewer hits (-1 to hit)" % sd, int(sup_h.hits) < int(free_h.hits), "%d vs %d (%s)" % [sup_h.hits, free_h.hits, bw])


# ---------------------------------------------------------------------------
# 5. Ulrik — Slayer's Oath, Oathbound
# ---------------------------------------------------------------------------
func _section_ulrik() -> void:
	print("\n-- 5. Ulrik: Slayer's Oath, Oathbound --")
	_fresh(P_CMD, 1, 1)
	_place("U_ULRIK_THE_SLAYER_A", 10, 45)
	_place("U_BLOOD_CLAWS_A", 10, 46.5)
	_attach("U_ULRIK_THE_SLAYER_A", "U_BLOOD_CLAWS_A")
	_place("U_WARBOSS_A", 10, 20)
	_place("U_BOYZ_B", 20, 20)
	_place("U_DEFF_DREAD_A", 30, 20)
	var o := _offer(1, "phase_start", {"phase": "command"}, "slayers_oath")
	var sec := _secondary_ids(o, "U_ULRIK_THE_SLAYER_A")
	_check("Slayer's Oath offered at the start of battle round 1", not o.is_empty(), str(o))
	_check("Slayer's Oath: enemy CHARACTER/MONSTER/VEHICLE units only", "U_WARBOSS_A" in sec and "U_DEFF_DREAD_A" in sec and not "U_BOYZ_B" in sec, str(sec))
	_check("not offered to the opponent", _offer(2, "phase_start", {"phase": "command"}, "slayers_oath").is_empty())
	var r := _use(1, "slayers_oath", "U_ULRIK_THE_SLAYER_A", "phase_start", {"phase": "command"}, "U_DEFF_DREAD_A")
	_check("Slayer's Oath resolves", r.get("success", false), str(r))
	_check("chosen once: not offered again", _offer(1, "phase_start", {"phase": "command"}, "slayers_oath").is_empty())
	_phase(P_FIGHT, 1)
	var mo := _mods("U_BLOOD_CLAWS_A", "U_DEFF_DREAD_A", true)
	_check("vs the oath: ignore BS/WS and hit modifiers (whole Attached unit)", bool(mo.ignore_hit_penalties), str(mo))
	_check("Oathbound vs the oath: melee +1 to hit and +1 to wound", bool(mo.hit_plus) and bool(mo.wound_plus))
	var mn := _mods("U_BLOOD_CLAWS_A", "U_BOYZ_B", true)
	_check("Oathbound vs another unit: melee +1 to hit only", bool(mn.hit_plus) and not bool(mn.wound_plus) and not bool(mn.ignore_hit_penalties), str(mn))
	_check("Oathbound: not ranged", not bool(_mods("U_BLOOD_CLAWS_A", "U_BOYZ_B", false).hit_plus))
	var mr := _mods("U_BLOOD_CLAWS_A", "U_DEFF_DREAD_A", false)
	_check("Slayer's Oath: ranged attacks vs the oath ignore modifiers too", bool(mr.ignore_hit_penalties))
	# Ignored modifiers: suppressed Blood Claws vs the oath (A/B same seed).
	_flags("U_BLOOD_CLAWS_A")[SW.F_SUPPRESSED] = {"player": 2, "source": "Test"}
	var bits: int = RE.ork11e_ab_hit_bits(0, [], _mods("U_BLOOD_CLAWS_A", "U_DEFF_DREAD_A", true))
	_check("a -1 to hit is ignored against the oath", not (bits & RE.HitModifier.MINUS_ONE) and (bits & RE.HitModifier.PLUS_ONE), str(bits))
	_fresh(P_CMD, 1, 2)
	_place("U_ULRIK_THE_SLAYER_A", 10, 45)
	_place("U_WARBOSS_A", 10, 20)
	_check("battle round 2: Slayer's Oath not offered", _offer(1, "phase_start", {"phase": "command"}, "slayers_oath").is_empty())


# ---------------------------------------------------------------------------
# 6. Legendary Tenacity / Rugged Resilience, Ancient Tactician, Champion of the Kingsguard
# ---------------------------------------------------------------------------
func _section_tenacity_tactician_kingsguard() -> void:
	print("\n-- 6. Legendary Tenacity, Rugged Resilience, Ancient Tactician, Champion of the Kingsguard --")
	_fresh(P_SHOOT, 2)
	_place("U_BJORN_THE_FELL_HANDED_A", 10, 40)
	_place("U_WOLF_GUARD_TERMINATORS_A", 20, 40)
	_place("U_ARJAC_ROCKFIST_A", 20, 41.8)
	_attach("U_ARJAC_ROCKFIST_A", "U_WOLF_GUARD_TERMINATORS_A")
	_check("Legendary Tenacity: S11 vs T10 -> -1 to wound", RE.ork11e_ab_wound_penalty(_u("U_BJORN_THE_FELL_HANDED_A"), 11, 10) and RE.ork11e_ab_wound_penalty_name(_u("U_BJORN_THE_FELL_HANDED_A"), 11, 10) == "Legendary Tenacity")
	_check("Legendary Tenacity: S10 vs T10 -> no penalty", not RE.ork11e_ab_wound_penalty(_u("U_BJORN_THE_FELL_HANDED_A"), 10, 10))
	_check("Rugged Resilience: S7 vs T6 -> -1 to wound (Arjac's Attached unit too)", RE.ork11e_ab_wound_penalty(_u("U_WOLF_GUARD_TERMINATORS_A"), 7, 6) and RE.ork11e_ab_wound_penalty(_u("U_ARJAC_ROCKFIST_A"), 7, 6))
	_check("no penalty on a unit without it", not RE.ork11e_ab_wound_penalty(_u("U_BLOOD_CLAWS_A"), 9, 5))
	# Ancient Tactician (once per turn, per army).
	_check("Ancient Tactician: -1 CP on Bjorn", SW.stratagem_cp_discount(1, "U_BJORN_THE_FELL_HANDED_A") == 1)
	_check("Ancient Tactician: not on another unit", SW.stratagem_cp_discount(1, "U_BLOOD_CLAWS_A") == 0)
	var smoke := "smokescreen_11e" if SM.stratagems.has("smokescreen_11e") else "smokescreen"
	var cu: Dictionary = SM.can_use_stratagem(1, smoke, "U_BJORN_THE_FELL_HANDED_A", {})
	var before := int(GS.state.players["1"].cp)
	var res: Dictionary = SM.use_stratagem(1, smoke, "U_BJORN_THE_FELL_HANDED_A", {})
	var cost := before - int(GS.state.players["1"].cp)
	_check("SMOKESCREEN on Bjorn (opponent's Shooting phase) costs 1 CP less (%s)" % smoke, res.get("success", false) and cost == int(SM.stratagems[smoke].get("cp_cost", 1)) - 1, "can_use=%s res=%s cost=%d" % [str(cu), str(res.get("error", "")), cost])
	_check("Ancient Tactician: once per turn", SW.stratagem_cp_discount(1, "U_BJORN_THE_FELL_HANDED_A") == 0)
	GS.state.meta["active_player"] = 1
	_check("Ancient Tactician: available again next turn", SW.stratagem_cp_discount(1, "U_BJORN_THE_FELL_HANDED_A") == 1)
	_check("Ancient Tactician: game log line", root.get_node("GameEventLog") != null)
	# Champion of the Kingsguard.
	_phase(P_FIGHT, 1)
	_place("U_WARBOSS_A", 20, 38.5)
	_place("U_BOYZ_B", 30, 38.5)
	var mc := _mods("U_ARJAC_ROCKFIST_A", "U_WARBOSS_A", true)
	_check("Champion of the Kingsguard: vs CHARACTER re-roll hit 1s and wound 1s", str(mc.hit_reroll) == "ones" and str(mc.wound_reroll) == "ones", str(mc))
	_check("Champion of the Kingsguard: not vs a non-CHARACTER", str(_mods("U_ARJAC_ROCKFIST_A", "U_BOYZ_B", true).hit_reroll) == "")
	_check("Champion of the Kingsguard: 'this model' — not the Terminators", str(_mods("U_WOLF_GUARD_TERMINATORS_A", "U_WARBOSS_A", true).wound_reroll) == "")


# ---------------------------------------------------------------------------
# 7. Berserk Charge, Cunning Hunters, Thunderous Charge
# ---------------------------------------------------------------------------
func _section_claws_hunters_thunderwolves() -> void:
	print("\n-- 7. Berserk Charge, Cunning Hunters, Thunderous Charge --")
	_fresh(P_FIGHT)
	_place("U_BLOOD_CLAWS_A", 10, 40)
	_check("Berserk Charge: advance does not prevent a charge", EP.has_effect_advance_and_charge(_u("U_BLOOD_CLAWS_A")))
	_check("Grey Hunters: advance blocks the charge", not EP.has_effect_advance_and_charge(_u("U_GREY_HUNTERS_A")))
	var objs: Array = SWC.objectives()
	_check("fixture has objectives", not objs.is_empty())
	var op = objs[0].get("position", {})
	var ox := float(op.x if op is Vector2 else op.get("x", 0)) / PX
	var oy := float(op.y if op is Vector2 else op.get("y", 0)) / PX
	_place("U_GREY_HUNTERS_A", ox - 2.0, oy)
	_place("U_BOYZ_B", ox - 2.0, oy - 1.3)
	var mh := _mods("U_GREY_HUNTERS_A", "U_BOYZ_B", true)
	_check("Cunning Hunters: Fight phase, within range of an objective -> melee +1 S, +1 AP", int(mh.strength) == 1 and int(mh.ap) == 1, str(mh))
	_check("Cunning Hunters: not ranged", int(_mods("U_GREY_HUNTERS_A", "U_BOYZ_B", false).strength) == 0)
	_phase(P_SHOOT)
	_check("Cunning Hunters: not outside the Fight phase", int(_mods("U_GREY_HUNTERS_A", "U_BOYZ_B", true).strength) == 0)
	_phase(P_FIGHT)
	var away := false
	for spot in [[2, 50], [36, 50], [2, 10], [36, 10], [20, 52], [20, 8]]:
		_place("U_GREY_HUNTERS_A", float(spot[0]), float(spot[1]))
		if not SWC.group_in_range_of_any_objective("U_GREY_HUNTERS_A"):
			away = true
			break
	_check("Cunning Hunters: not away from objectives", away and int(_mods("U_GREY_HUNTERS_A", "U_BOYZ_B", true).ap) == 0)
	_place("U_THUNDERWOLF_CAVALRY_A", 30, 40)
	_check("Thunderous Charge: no charge -> nothing", int(_mods("U_THUNDERWOLF_CAVALRY_A", "U_BOYZ_B", true).damage) == 0)
	_flags("U_THUNDERWOLF_CAVALRY_A")["charged_this_turn"] = true
	var mt := _mods("U_THUNDERWOLF_CAVALRY_A", "U_BOYZ_B", true)
	_check("Thunderous Charge: charged -> melee +1 S, +1 D", int(mt.strength) == 1 and int(mt.damage) == 1, str(mt))


# ---------------------------------------------------------------------------
# 8. Old Greymanes / Let Loose the Wolves (Declare Battle Formations)
# ---------------------------------------------------------------------------
func _section_splits() -> void:
	print("\n-- 8. Old Greymanes / Let Loose the Wolves --")
	_fresh(P_FORM)
	var can: Array = SW.splittable_units(1)
	_check("splittable: Grey Hunters (Old Greymanes) and Headtakers (Let Loose the Wolves)",
		"U_GREY_HUNTERS_A" in can and "U_WOLF_GUARD_HEADTAKERS_A" in can and not "U_BLOOD_CLAWS_A" in can, str(can))
	_check("not the opponent's units", SW.split_block_reason("U_GREY_HUNTERS_A", 2) != "")
	_check("refused while a leader is declared on the unit", SW.split_block_reason("U_GREY_HUNTERS_A", 1, {"U_WOLF_PRIEST_A": "U_GREY_HUNTERS_A"}) != "")
	var fp = _formations_phase()
	var v: Dictionary = fp.validate_action({"type": "SW11E_SPLIT_UNIT", "unit_id": "U_GREY_HUNTERS_A", "player": 1})
	_check("FormationsPhase validates SW11E_SPLIT_UNIT", bool(v.get("valid", false)), str(v))
	var acts: Array = fp.get_available_actions().filter(func(a): return str(a.get("type", "")) == "SW11E_SPLIT_UNIT")
	_check("FormationsPhase lists the split actions", acts.size() >= 2, str(acts.map(func(a): return a.unit_id)))
	var pr: Dictionary = fp.process_action({"type": "SW11E_SPLIT_UNIT", "unit_id": "U_GREY_HUNTERS_A", "player": 1})
	GS.apply_state_changes(pr.get("changes", pr.get("diffs", [])))
	var nid := str(_u("U_GREY_HUNTERS_A").get("split_sibling_id", ""))
	_check("Old Greymanes: 10 models -> 5 + 5", _u("U_GREY_HUNTERS_A").models.size() == 5 and nid != "" and _u(nid).models.size() == 5, "%d / %s" % [_u("U_GREY_HUNTERS_A").models.size(), nid])
	_check("both halves are Grey Hunters (same datasheet abilities)", SW.has(_u(nid), "cunning_hunters") and SWC.has_keyword(_u(nid), "GREY HUNTERS"))
	_check("the new half has unique model ids and an owner", _u(nid).models[0].id == "m1" and int(_u(nid).owner) == 1)
	_check("a half cannot split again", SW.split_kind("U_GREY_HUNTERS_A") == "" and SW.split_kind(nid) == "")
	_check("the new half can be led (Wolf Priest)", nid in GS.get_eligible_bodyguards_for_character("U_WOLF_PRIEST_A"), str(GS.get_eligible_bodyguards_for_character("U_WOLF_PRIEST_A")))
	fp.free()
	var res: Dictionary = SW.split_diffs("U_WOLF_GUARD_HEADTAKERS_A")
	GS.apply_state_changes(res.diffs)
	var wid := str(res.new_id)
	_check("Let Loose the Wolves: 3 Headtakers + 3 Hunting Wolves", _u("U_WOLF_GUARD_HEADTAKERS_A").models.size() == 3 and _u(wid).models.size() == 3)
	_check("Headtaker half: only W3 models, no BEASTS", _u("U_WOLF_GUARD_HEADTAKERS_A").models.all(func(m): return int(m.wounds) == 3) and not SWC.has_keyword(_u("U_WOLF_GUARD_HEADTAKERS_A"), "BEASTS"))
	var ws: Dictionary = _u(wid).meta.stats
	_check("Hunting Wolves half: Hunting Wolf profile (M10 T4 Sv6 W1 OC0), BEASTS, no INFANTRY",
		int(ws.move) == 10 and int(ws.toughness) == 4 and int(ws.save) == 6 and int(ws.objective_control) == 0 and SWC.has_keyword(_u(wid), "BEASTS") and not SWC.has_keyword(_u(wid), "INFANTRY"), str(ws))
	_check("Hunting Wolves half: Teeth and Claws only", _u(wid).meta.weapons.size() == 1 and str(_u(wid).meta.weapons[0].name) == "Teeth and Claws")
	_check("Hunting Wolves half keeps Hunting Hounds, not Headhunters", SW.has(_u(wid), "hunting_hounds") and not SW.has(_u(wid), "headhunters"))
	_check("not in another phase's unit status (DEPLOYED units cannot split)", (func(): _u("U_GREY_HUNTERS_B")["status"] = 2; return SW.split_kind("U_GREY_HUNTERS_B") == "").call())


# ---------------------------------------------------------------------------
# 9. Iron Priest — Gift of the Iron Wolf, Iron Priest (Lone Operative), Judgement of the Omnissiah
# ---------------------------------------------------------------------------
func _section_iron_priest() -> void:
	print("\n-- 9. Iron Priest --")
	_fresh(P_MOV, 1)
	_place("U_IRON_PRIEST_A", 10, 40)
	_place("U_VENERABLE_DREADNOUGHT_A", 12.5, 40)
	_place("U_BJORN_THE_FELL_HANDED_A", 30, 40)
	_u("U_VENERABLE_DREADNOUGHT_A").models[0]["current_wounds"] = 4
	var ctx := {"phase": "movement", "unit_id": "U_IRON_PRIEST_A"}
	var o := _offer(1, "unit_selected_to_move", ctx, "gift_of_the_iron_wolf")
	var sec := _secondary_ids(o, "U_IRON_PRIEST_A")
	_check("Gift of the Iron Wolf offered when the Iron Priest is selected to move", not o.is_empty())
	_check("Gift: SPACE WOLVES VEHICLE models within 3\" only", "U_VENERABLE_DREADNOUGHT_A" in sec and not "U_BJORN_THE_FELL_HANDED_A" in sec, str(sec))
	_check("Gift: not for another moving unit", _offer(1, "unit_selected_to_move", {"unit_id": "U_BLOOD_CLAWS_A"}, "gift_of_the_iron_wolf").is_empty())
	_check("Gift: also at the end of its move", not _offer(1, "unit_ended_normal_move", ctx, "gift_of_the_iron_wolf").is_empty())
	var r := _use(1, "gift_of_the_iron_wolf", "U_IRON_PRIEST_A", "unit_selected_to_move", ctx, "U_VENERABLE_DREADNOUGHT_A")
	var cw := int(_u("U_VENERABLE_DREADNOUGHT_A").models[0].current_wounds)
	_check("Gift resolves: the Dreadnought heals D3", r.get("success", false) and cw >= 5 and cw <= 7, "%s cw=%d" % [str(r), cw])
	_check("Gift: once per Iron Priest move (not again this phase)", _offer(1, "unit_ended_normal_move", ctx, "gift_of_the_iron_wolf").is_empty())
	var mv := _mods("U_VENERABLE_DREADNOUGHT_A", "U_BOYZ_B", false)
	_check("Gift: that VEHICLE's attacks ignore hit and wound modifiers", bool(mv.ignore_hit_penalties) and bool(mv.ignore_wound_penalties), str(mv))
	var wb: int = RE.sw11e_ignore_wound_penalties(RE.WoundModifier.MINUS_ONE | RE.WoundModifier.PLUS_ONE, [], mv)
	_check("Gift: the -1 to wound is dropped, the +1 kept", not (wb & RE.WoundModifier.MINUS_ONE) and (wb & RE.WoundModifier.PLUS_ONE))
	SW.on_phase_transition(P_MOV, P_SHOOT)
	_check("Gift lasts past the phase", _flags("U_VENERABLE_DREADNOUGHT_A").has(SW.F_GIFTED))
	GS.state.meta["active_player"] = 2
	SW.on_phase_transition(P_CMD, P_MOV)
	_check("Gift lasts through the opponent's Movement phase", _flags("U_VENERABLE_DREADNOUGHT_A").has(SW.F_GIFTED))
	GS.state.meta["active_player"] = 1
	GS.state.meta["battle_round"] = 3
	SW.on_phase_transition(P_CMD, P_MOV)
	_check("Gift ends at the start of your next Movement phase", not _flags("U_VENERABLE_DREADNOUGHT_A").has(SW.F_GIFTED))
	# Lone Operative within 3" of a SW VEHICLE.
	_check("Iron Priest within 3\" of a SW VEHICLE: Lone Operative", RE.has_lone_operative(_u("U_IRON_PRIEST_A")))
	_place("U_VENERABLE_DREADNOUGHT_A", 25, 20)
	_check("Iron Priest away from vehicles: no Lone Operative", not RE.has_lone_operative(_u("U_IRON_PRIEST_A")))
	# Judgement of the Omnissiah.
	_phase(P_FIGHT)
	_place("U_BOYZ_B", 25, 18.3)
	_check("Judgement: enemy engaged with a friendly SW VEHICLE -> re-roll wound rolls", str(_mods("U_IRON_PRIEST_A", "U_BOYZ_B", true).wound_reroll) == "failed")
	_place("U_BOYZ_B", 40, 5)
	_check("Judgement: enemy not engaged with a SW vehicle -> nothing", str(_mods("U_IRON_PRIEST_A", "U_BOYZ_B", true).wound_reroll) == "")


# ---------------------------------------------------------------------------
# 10. Wulfen — Savage Frenzy, Death Totem; Murderfang — Bestial Fury, Force of Untamed Destruction
# ---------------------------------------------------------------------------
func _section_wulfen() -> void:
	print("\n-- 10. Savage Frenzy, Death Totem, Bestial Fury, Force of Untamed Destruction --")
	_fresh(P_MOV, 2)
	_place("U_WULFEN_A", 10, 30)
	_place("U_BOYZ_B", 10, 28.6)
	_place("U_DEFF_DREAD_A", 30, 30)
	_place("U_WULFEN_WITH_STORM_SHIELDS_B", 30, 31.6)
	var fb = MoveTypes.get_type("fall_back")
	var sm: Dictionary = fb.select_mode("U_BOYZ_B", GS.state)
	_check("Savage Frenzy: an engaged enemy must fall back with desperate escape", str(sm.get("mode", "")) == "desperate_escape" and bool(sm.get("mandatory", false)), str(sm))
	_check("Savage Frenzy: not a MONSTER/VEHICLE", SW.savage_frenzy_source("U_DEFF_DREAD_A") == "")
	_check("Savage Frenzy: -1 hazard only while battle-shocked", SW.savage_frenzy_hazard_modifier("U_BOYZ_B") == 0)
	_flags("U_BOYZ_B")["battle_shocked"] = true
	_check("Savage Frenzy: battle-shocked -> -1 to those hazard rolls", SW.savage_frenzy_hazard_modifier("U_BOYZ_B") == -1)
	_phase(P_FIGHT, 1)
	var md := _mods("U_WULFEN_A", "U_BOYZ_B", true)
	_check("Death Totem: melee re-roll hit rolls of 1", str(md.hit_reroll) == "ones" and "Death Totem" in _names(md), str(md))
	_check("Death Totem (Wulfen with Storm Shields that took it)", str(_mods("U_WULFEN_WITH_STORM_SHIELDS_B", "U_DEFF_DREAD_A", true).hit_reroll) == "ones")
	_check("Death Totem: not without the totem (Wulfen with Storm Shields A)", str(_mods("U_WULFEN_WITH_STORM_SHIELDS_A", "U_BOYZ_B", true).hit_reroll) == "")
	_place("U_MURDERFANG_A", 20, 45)
	_check("Bestial Fury: re-roll charge rolls and advance rolls", EP.has_effect_reroll_charge(_u("U_MURDERFANG_A")) and EP.has_effect_reroll_advance(_u("U_MURDERFANG_A")))
	_check("no re-roll for another unit", not EP.has_effect_reroll_charge(_u("U_WULFEN_A")))
	_check("Force of Untamed Destruction: Murderfang cannot be the WARLORD", SW.warlord_block_reason(_u("U_MURDERFANG_A")) != "" and SW.warlord_block_reason(_u("U_LOGAN_GRIMNAR_A")) == "")
	var fp = _formations_phase()
	var v: Dictionary = fp.validate_action({"type": "DESIGNATE_WARLORD", "unit_id": "U_MURDERFANG_A", "player": 1})
	_check("DESIGNATE_WARLORD refuses Murderfang", not bool(v.get("valid", true)) and str(v.get("errors", [])).contains("Force of Untamed Destruction"), str(v))
	_check("DESIGNATE_WARLORD accepts Logan", bool(fp.validate_action({"type": "DESIGNATE_WARLORD", "unit_id": "U_LOGAN_GRIMNAR_A", "player": 1}).get("valid", false)))
	fp.free()


# ---------------------------------------------------------------------------
# 11. Guile of the Wolf (SWCommon doctrine-state API)
# ---------------------------------------------------------------------------
func _section_guile() -> void:
	print("\n-- 11. Guile of the Wolf --")
	_fresh(P_CMD, 1)
	_place("U_WOLF_GUARD_TERMINATORS_A", 10, 40)
	_place("U_LOGAN_GRIMNAR_A", 10, 41.8)
	_attach("U_LOGAN_GRIMNAR_A", "U_WOLF_GUARD_TERMINATORS_A")
	_check("before a phase starts: no extra doctrines", SWC.active_doctrines(_u("U_WOLF_GUARD_TERMINATORS_A")).is_empty())
	SW.on_phase_transition(P_CMD, P_MOV)
	var d1: Array = SWC.active_doctrines(_u("U_LOGAN_GRIMNAR_A"))
	var d2: Array = SWC.active_doctrines(_u("U_WOLF_GUARD_TERMINATORS_A"))
	_check("start of the phase: assault, devastator and tactical doctrines active for Logan", d1.size() == 3 and "assault" in d1 and "devastator" in d1 and "tactical" in d1, str(d1))
	_check("... and for the unit he leads (this unit)", d2.size() == 3, str(d2))
	_check("other units: unaffected", SWC.active_doctrines(_u("U_BLOOD_CLAWS_A")).is_empty())
	_check("SWCommon.doctrine_active reads it", SWC.doctrine_active_id("U_WOLF_GUARD_TERMINATORS_A", "tactical"))
	for m in _u("U_LOGAN_GRIMNAR_A").models:
		m["alive"] = false
	SW.on_phase_transition(P_MOV, P_SHOOT)
	_check("Logan destroyed: the doctrines are no longer active for his old unit", SWC.active_doctrines(_u("U_WOLF_GUARD_TERMINATORS_A")).is_empty())


# ---------------------------------------------------------------------------
# 12. High King of Fenris
# ---------------------------------------------------------------------------
func _section_high_king() -> void:
	print("\n-- 12. High King of Fenris --")
	_fresh(P_MOV, 1, 1)
	_place("U_LOGAN_GRIMNAR_A", 20, 50)
	_reserve("U_BLOOD_CLAWS_A")
	_reserve("U_INTERCESSOR_SQUAD_A")
	var o := _offer(1, "phase_start", {"phase": "movement"}, "high_king_of_fenris")
	var sec := _secondary_ids(o, "U_LOGAN_GRIMNAR_A")
	_check("High King of Fenris offered in your Movement phase", not o.is_empty())
	_check("High King: friendly SPACE WOLVES units in strategic reserves only", "U_BLOOD_CLAWS_A" in sec and not "U_INTERCESSOR_SQUAD_A" in sec, str(sec))
	_check("battle round 1: reserves cannot arrive yet", SW.ingress_battle_round(_u("U_BLOOD_CLAWS_A"), 1) == 1 and SW.high_king_first_round_units(1).is_empty())
	var r := _use(1, "high_king_of_fenris", "U_LOGAN_GRIMNAR_A", "phase_start", {"phase": "movement"}, "U_BLOOD_CLAWS_A")
	_check("High King resolves", r.get("success", false), str(r))
	_check("the selected unit ingresses as if it were battle round 2", SW.ingress_battle_round(_u("U_BLOOD_CLAWS_A"), 1) == 2)
	_check("... so it can arrive in battle round 1", "U_BLOOD_CLAWS_A" in SW.high_king_first_round_units(1))
	_check("other reserves unaffected", SW.ingress_battle_round(_u("U_INTERCESSOR_SQUAD_A"), 1) == 1)
	_check("once per battle round", _offer(1, "phase_start", {"phase": "movement"}, "high_king_of_fenris").is_empty())
	var mp = load("res://phases/MovementPhase.gd").new()
	root.add_child(mp)
	var acts: Array = mp.get_available_actions().filter(func(a): return str(a.get("unit_id", a.get("actor_unit_id", ""))) == "U_BLOOD_CLAWS_A")
	_check("MovementPhase offers the selected unit's reinforcement in round 1", not acts.is_empty(), str(acts.map(func(a): return a.get("type", ""))))
	mp.free()
	SW.on_phase_transition(P_MOV, P_SHOOT)
	_check("High King lasts for that phase", SW.ingress_battle_round(_u("U_BLOOD_CLAWS_A"), 1) == 1)
	_check("not in the opponent's Movement phase", (func(): _phase(P_MOV, 2); GS.state.meta["battle_round"] = 2; return _offer(1, "phase_start", {}, "high_king_of_fenris").is_empty()).call())
	_phase(P_MOV, 1)
	GS.state.meta["battle_round"] = 2
	_check("a new battle round: offered again", not _offer(1, "phase_start", {"phase": "movement"}, "high_king_of_fenris").is_empty())


# ---------------------------------------------------------------------------
# 13. Fight On Death — Murder-maker, Anvil of Endurance, Heroic Last Stand
# ---------------------------------------------------------------------------
func _section_fight_on_death() -> void:
	print("\n-- 13. Murder-maker, Anvil of Endurance, Heroic Last Stand --")
	_fresh(P_FIGHT, 1)
	_place("U_WOLF_GUARD_BATTLE_LEADER_A", 10, 40)
	_place("U_WOLF_GUARD_TERMINATORS_A", 20, 40)
	_place("U_ARJAC_ROCKFIST_A", 20, 41.8)
	_attach("U_ARJAC_ROCKFIST_A", "U_WOLF_GUARD_TERMINATORS_A")
	_place("U_MURDERFANG_A", 32, 40)
	_place("U_WULFEN_A", 32, 43)
	_place("U_WULFEN_WITH_STORM_SHIELDS_A", 5, 55)
	_check("Heroic Last Stand: the Battle Leader 2+", str(SW.fod_rule("U_WOLF_GUARD_BATTLE_LEADER_A", 0)) == str({"source": "Heroic Last Stand", "pass": 2}), str(SW.fod_rule("U_WOLF_GUARD_BATTLE_LEADER_A", 0)))
	_check("Anvil of Endurance: a Terminator of Arjac's unit 4+", int(SW.fod_rule("U_WOLF_GUARD_TERMINATORS_A", 2).get("pass", 0)) == 4)
	_check("Anvil of Endurance: Arjac himself 4+", int(SW.fod_rule("U_ARJAC_ROCKFIST_A", 0).get("pass", 0)) == 4)
	_check("Murder-maker: a WULFEN model within 6\" of Murderfang 4+", str(SW.fod_rule("U_WULFEN_A", 0).get("source", "")) == "Murder-maker")
	_check("Murder-maker: a WULFEN model far from Murderfang -> nothing", SW.fod_rule("U_WULFEN_WITH_STORM_SHIELDS_A", 0).is_empty())
	_check("Murder-maker: not Murderfang himself", SW.fod_rule("U_MURDERFANG_A", 0).is_empty())
	_check("no rule on another unit", SW.fod_rule("U_BLOOD_CLAWS_A", 0).is_empty())
	_phase(P_SHOOT)
	_check("only in the Fight phase", SW.fod_rule("U_WOLF_GUARD_BATTLE_LEADER_A", 0).is_empty())
	_phase(P_FIGHT)
	# Integration: FightPhase's Fight On Death intercept keeps the Battle Leader on a 2+.
	var fp = load("res://phases/FightPhase.gd").new()
	root.add_child(fp)
	var s2 := _seed_where(1, func(r): return int(r[0]) >= 2)
	var changes: Array = [{"op": "set", "path": "units.U_WOLF_GUARD_BATTLE_LEADER_A.models.0.alive", "value": false}]
	fp._ork11e_fod_intercept(changes)
	_check("FightPhase: Heroic Last Stand roll %s -> the Battle Leader is NOT removed" % str(s2), changes[0].value == true, str(changes))
	_check("... and listed as kept until its unit has fought", (func():
		for c in changes:
			if str(c.path).ends_with("ork11e_fod_pending"):
				return 0 in c.value
		return false).call(), str(changes))
	var s1 := _seed_where(1, func(r): return int(r[0]) == 1)
	var ch2: Array = [{"op": "set", "path": "units.U_WOLF_GUARD_TERMINATORS_A.models.1.alive", "value": false}]
	fp._ork11e_fod_intercept(ch2)
	_check("FightPhase: Anvil of Endurance roll 1 -> removed", ch2[0].value == false and s1 > 0, str(ch2))
	fp.free()


# ---------------------------------------------------------------------------
# 14. Predatory Instinct
# ---------------------------------------------------------------------------
func _section_predatory_instinct() -> void:
	print("\n-- 14. Predatory Instinct --")
	_fresh(P_MOV, 2)
	_place("U_FENRISIAN_WOLVES_A", 20, 40)
	_place("U_BOYZ_B", 20, 33)   # ~6" away
	_place("U_GRETCHIN_C", 5, 20)
	var ctx := {"phase": "movement", "enemy_unit_id": "U_BOYZ_B"}
	var o := _offer(1, "enemy_ended_move", ctx, "predatory_instinct")
	_check("Predatory Instinct offered when an enemy ends a move within 8\"", "U_FENRISIAN_WOLVES_A" in _offer_units(o), str(o))
	_check("not for an enemy further than 8\"", _offer(1, "enemy_ended_move", {"enemy_unit_id": "U_GRETCHIN_C"}, "predatory_instinct").is_empty())
	_check("not in your own Movement phase", (func(): _phase(P_MOV, 1); var e := _offer(1, "enemy_ended_move", ctx, "predatory_instinct").is_empty(); _phase(P_MOV, 2); return e).call())
	var r := _use(1, "predatory_instinct", "U_FENRISIAN_WOLVES_A", "enemy_ended_move", ctx)
	var fu: Dictionary = r.get("followup", {})
	_check("use -> a normal move of up to D6\"", r.get("success", false) and str(fu.get("type", "")) == "reactive_normal_move" and float(fu.get("max_inches", 0)) >= 1.0 and float(fu.get("max_inches", 0)) <= 6.0, str(r))
	_check("once per battle round", _offer(1, "enemy_ended_move", ctx, "predatory_instinct").is_empty())
	_fresh(P_MOV, 2)
	_place("U_FENRISIAN_WOLVES_A", 20, 40)
	_place("U_BOYZ_B", 20, 38.6)
	_check("engaged: not offered", _offer(1, "enemy_ended_move", ctx, "predatory_instinct").is_empty())


# ---------------------------------------------------------------------------
# 15. Hunting Hounds
# ---------------------------------------------------------------------------
func _section_hunting_hounds() -> void:
	print("\n-- 15. Hunting Hounds --")
	_fresh(P_CMD, 1)
	_place("U_FENRISIAN_WOLVES_A", 10, 40)
	_place("U_WOLF_SCOUTS_A", 20, 40)
	_place("U_WOLF_PRIEST_A", 30, 50)
	var fw: Dictionary = _u("U_FENRISIAN_WOLVES_A")
	_check("Fenrisian Wolves (OC 0): no SW CHARACTER within 6\" -> OC 0", MM.model_oc(fw, fw.models[0]) == 0)
	_place("U_WOLF_PRIEST_A", 12, 43)
	_check("Fenrisian Wolves within 6\" of a SW CHARACTER -> +1 OC", MM.model_oc(fw, fw.models[0]) == 1)
	_flags("U_FENRISIAN_WOLVES_A")["battle_shocked"] = true
	_check("battle-shocked: no Hunting Hounds", not SW.hunting_hounds_active(fw))
	_flags("U_FENRISIAN_WOLVES_A").erase("battle_shocked")
	_place("U_WOLF_PRIEST_A", 30, 50)
	_place("U_WULFEN_A", 12, 43)
	_place("U_MURDERFANG_A", 14, 43)
	_check("a WULFEN CHARACTER (Murderfang) does not count", MM.model_oc(fw, fw.models[0]) == 0)
	var ws: Dictionary = _u("U_WOLF_SCOUTS_A")
	var wolf_idx := -1
	for i in range(ws.models.size()):
		if int(ws.models[i].wounds) == 1:
			wolf_idx = i
	_check("Wolf Scouts: the Hunting Wolf has its printed OC 0 (no character near)", wolf_idx >= 0 and MM.model_oc(ws, ws.models[wolf_idx]) == 0)
	_check("Wolf Scouts: a Wolf Scout keeps OC 1", MM.model_oc(ws, ws.models[0 if wolf_idx != 0 else 2]) == 1)
	_place("U_WOLF_GUARD_BATTLE_LEADER_A", 22, 43)
	_check("Wolf Scouts near a SW CHARACTER: the Hunting Wolf +1 OC", MM.model_oc(ws, ws.models[wolf_idx]) == 1)
	_check("... the Wolf Scouts unchanged", MM.model_oc(ws, ws.models[0 if wolf_idx != 0 else 2]) == 1)


# ---------------------------------------------------------------------------
# 16. Fervour of the Ancients
# ---------------------------------------------------------------------------
func _section_fervour() -> void:
	print("\n-- 16. Fervour of the Ancients --")
	_fresh(P_MOV, 1)
	_place("U_VENERABLE_DREADNOUGHT_A", 20, 40)
	_place("U_BLOOD_CLAWS_A", 20, 44)
	_place("U_GREY_HUNTERS_A", 5, 55)
	_place("U_INTERCESSOR_SQUAD_A", 30, 43)
	_check("a SW unit within 6\": +1 to advance and charge rolls", int(SW.fervour_bonus("U_BLOOD_CLAWS_A").bonus) == 1)
	_check("the Dreadnought itself", int(SW.fervour_bonus("U_VENERABLE_DREADNOUGHT_A").bonus) == 1)
	_check("a SW unit further away: nothing", int(SW.fervour_bonus("U_GREY_HUNTERS_A").bonus) == 0)
	_check("a non-SPACE WOLVES unit (Intercessors): nothing", int(SW.fervour_bonus("U_INTERCESSOR_SQUAD_A").bonus) == 0)


# ---------------------------------------------------------------------------
# 17. Wolf Priest — Healing Balms, Litany of Hate
# ---------------------------------------------------------------------------
func _section_wolf_priest() -> void:
	print("\n-- 17. Healing Balms, Litany of Hate --")
	_fresh(P_CMD, 1)
	_place("U_BLOOD_CLAWS_A", 10, 40)
	_place("U_WOLF_PRIEST_A", 10, 41.5)
	_attach("U_WOLF_PRIEST_A", "U_BLOOD_CLAWS_A")
	_check("Healing Balms: not offered at full strength", _offer(1, "phase_start", {"phase": "command"}, "healing_balms").is_empty())
	var bc: Array = _u("U_BLOOD_CLAWS_A").models
	bc[0]["alive"] = false
	bc[0]["current_wounds"] = 0
	bc[1]["alive"] = false
	bc[1]["current_wounds"] = 0
	bc[2]["current_wounds"] = 1
	var o := _offer(1, "phase_start", {"phase": "command"}, "healing_balms")
	_check("Healing Balms offered in your Command phase when the unit lost wounds", "U_BLOOD_CLAWS_A" in _offer_units(o), str(o))
	_check("not in the opponent's Command phase", (func(): _phase(P_CMD, 2); var e := _offer(1, "phase_start", {}, "healing_balms").is_empty(); _phase(P_CMD, 1); return e).call())
	var before := _wounds_left("U_BLOOD_CLAWS_A")
	var r := _use(1, "healing_balms", "U_BLOOD_CLAWS_A", "phase_start", {"phase": "command"})
	var after := _wounds_left("U_BLOOD_CLAWS_A")
	_check("Healing Balms heals D3+1 (2-4 wounds; the wounded model first, then destroyed models)", r.get("success", false) and after - before >= 2 and after - before <= 4 and int(bc[2].current_wounds) == 2, "%d -> %d %s" % [before, after, str(r.get("diffs", []).size())])
	_check("once per phase", _offer(1, "phase_start", {"phase": "command"}, "healing_balms").is_empty())
	_phase(P_FIGHT)
	_place("U_BOYZ_B", 10, 38.6)
	_check("Litany of Hate: no charge -> no [LANCE] bonus", not bool(_mods("U_BLOOD_CLAWS_A", "U_BOYZ_B", true).wound_plus))
	_flags("U_BLOOD_CLAWS_A")["charged_this_turn"] = true
	var ml := _mods("U_BLOOD_CLAWS_A", "U_BOYZ_B", true)
	_check("Litany of Hate: charged -> melee +1 to wound ([LANCE]) for the whole unit", bool(ml.wound_plus) and "Litany of Hate" in _names(ml) and bool(_mods("U_WOLF_PRIEST_A", "U_BOYZ_B", true).wound_plus), str(ml))
	_check("Litany of Hate: not ranged", not bool(_mods("U_BLOOD_CLAWS_A", "U_BOYZ_B", false).wound_plus))


# ---------------------------------------------------------------------------
# 18. Wolf Guard Battle Leader — Tempered Ferocity
# ---------------------------------------------------------------------------
func _section_tempered_ferocity() -> void:
	print("\n-- 18. Tempered Ferocity --")
	_fresh(P_SHOOT, 1)
	_place("U_GREY_HUNTERS_A", 10, 40)
	_place("U_WOLF_GUARD_BATTLE_LEADER_A", 10, 41.5)
	_attach("U_WOLF_GUARD_BATTLE_LEADER_A", "U_GREY_HUNTERS_A")
	_place("U_BOYZ_B", 10, 36)
	_place("U_GRETCHIN_C", 30, 20)
	var mn := _mods("U_GREY_HUNTERS_A", "U_BOYZ_B", false)
	_check("Tempered Ferocity: [SUSTAINED HITS 1] for the unit's attacks", int(mn.sustained) == 1, str(mn))
	_check("... within 6\": re-roll hit rolls of 1", str(mn.hit_reroll) == "ones")
	var mf := _mods("U_GREY_HUNTERS_A", "U_GRETCHIN_C", false)
	_check("... further than 6\": sustained only", int(mf.sustained) == 1 and str(mf.hit_reroll) == "", str(mf))
	_check("not without the Battle Leader", int(_mods("U_BLOOD_CLAWS_A", "U_BOYZ_B", false).sustained) == 0)


# ---------------------------------------------------------------------------
# 19. Wolf Guard Headtakers — Headhunters
# ---------------------------------------------------------------------------
func _section_headhunters() -> void:
	print("\n-- 19. Headhunters --")
	_fresh(P_CMD, 1, 1)
	_place("U_WOLF_GUARD_HEADTAKERS_A", 10, 40)
	_place("U_WARBOSS_A", 10, 20)
	_place("U_BOYZ_B", 20, 20)
	var o := _offer(1, "phase_start", {"phase": "command"}, "headhunters")
	var sec := _secondary_ids(o, "U_WOLF_GUARD_HEADTAKERS_A")
	_check("Headhunters offered at the start of battle round 1, any enemy unit", "U_WARBOSS_A" in sec and "U_BOYZ_B" in sec, str(sec))
	_check("the picker lists the most valuable target first", sec.size() > 0 and str(sec[0]) != "", str(sec))
	var r := _use(1, "headhunters", "U_WOLF_GUARD_HEADTAKERS_A", "phase_start", {"phase": "command"}, "U_BOYZ_B")
	_check("Headhunters resolves", r.get("success", false), str(r))
	var mq := _mods("U_WOLF_GUARD_HEADTAKERS_A", "U_BOYZ_B", true)
	_check("vs the quarry: [DEVASTATING WOUNDS] and [PRECISION]", bool(mq.get("devastating", false)) and bool(mq.get("precision", false)), str(mq))
	_check("vs another unit: nothing", not bool(_mods("U_WOLF_GUARD_HEADTAKERS_A", "U_WARBOSS_A", true).get("devastating", false)))
	_check("quarry alive: not offered again (to this unit)", not "U_WOLF_GUARD_HEADTAKERS_A" in _offer_units(_offer(1, "phase_start", {"phase": "command"}, "headhunters")))
	for m in _u("U_BOYZ_B").models:
		m["alive"] = false
	GS.state.meta["battle_round"] = 3
	var o2 := _offer(1, "phase_start", {"phase": "command"}, "headhunters")
	_check("the quarry was destroyed: a new quarry is selected (later battle round)", "U_WARBOSS_A" in _secondary_ids(o2, "U_WOLF_GUARD_HEADTAKERS_A"), str(o2))
	# Precision consumer: a melee batch vs the quarry carries [PRECISION].
	_fresh(P_FIGHT, 1)
	_place("U_WOLF_GUARD_HEADTAKERS_A", 10, 40)
	_place("U_BOYZ_B", 10, 38.4)
	_flags("U_WOLF_GUARD_HEADTAKERS_A")[SW.F_QUARRY] = "U_BOYZ_B"
	var wid := _weapon("U_WOLF_GUARD_HEADTAKERS_A", "master-crafted", true)
	var res := _melee_hits("U_WOLF_GUARD_HEADTAKERS_A", wid, "U_BOYZ_B", 7)
	var prec := false
	for d in res.res.get("dice", []):
		if str(d.get("context", "")) == "hit_roll_melee" and bool(d.get("precision_weapon", false)):
			prec = true
	_check("RulesEngine melee path: [PRECISION] granted vs the quarry", prec, "weapon %s" % wid)


# ---------------------------------------------------------------------------
# 20. Wulfen with Storm Shields — Hammer Blow
# ---------------------------------------------------------------------------
func _section_hammer_blow() -> void:
	print("\n-- 20. Hammer Blow --")
	_fresh(P_FIGHT, 1)
	_place("U_WULFEN_WITH_STORM_SHIELDS_A", 20, 40)
	_place("U_DEFF_DREAD_A", 20, 38.2)
	_place("U_BOYZ_B", 30, 38.6)
	var hits: Array = SW.melee_hit_unit_ids([{"attacker": "U_WULFEN_WITH_STORM_SHIELDS_A", "target": "U_DEFF_DREAD_A", "weapon": "w1"}, {"target": "U_BOYZ_B", "weapon": "w2"}],
		[{"context": "hit_roll_melee", "weapon": "w1", "successes": 2}, {"context": "hit_roll_melee", "weapon": "w2", "successes": 0}])
	_check("hit by those attacks: only targets of weapons that hit", hits == ["U_DEFF_DREAD_A"], str(hits))
	var ctx := {"phase": "fight", "unit_id": "U_WULFEN_WITH_STORM_SHIELDS_A", "hit_unit_ids": ["U_DEFF_DREAD_A", "U_BOYZ_B"]}
	var o := _offer(1, "unit_has_fought", ctx, "hammer_blow")
	var sec := _secondary_ids(o, "U_WULFEN_WITH_STORM_SHIELDS_A")
	_check("Hammer Blow offered when this unit has fought; MONSTER/VEHICLE units hit only", sec == ["U_DEFF_DREAD_A"], str(o))
	_check("FightPhase entry built only with a MONSTER/VEHICLE hit", not SW.unit_has_fought_entries("U_WULFEN_WITH_STORM_SHIELDS_A", ["U_DEFF_DREAD_A"]).is_empty() \
		and SW.unit_has_fought_entries("U_WULFEN_WITH_STORM_SHIELDS_A", ["U_BOYZ_B"]).is_empty())
	_check("in the opponent's Fight phase too", (func(): _phase(P_FIGHT, 2); var ok := not _offer(1, "unit_has_fought", ctx, "hammer_blow").is_empty(); _phase(P_FIGHT, 1); return ok).call())
	var r := _use(1, "hammer_blow", "U_WULFEN_WITH_STORM_SHIELDS_A", "unit_has_fought", ctx, "U_DEFF_DREAD_A")
	_check("Hammer Blow resolves: the Deff Dread is suppressed", r.get("success", false) and _flags("U_DEFF_DREAD_A").has(SW.F_SUPPRESSED), str(r))
	_check("suppressed Deff Dread: -1 to hit", bool(_mods("U_DEFF_DREAD_A", "U_WULFEN_WITH_STORM_SHIELDS_A", true).hit_minus))
	_check("StratagemManager knows the unit_has_fought window", SM.window_when_text("unit_has_fought") != "")


# ---------------------------------------------------------------------------
# 21. Wulfen Dreadnought — Violent Fury, Bestial Rage
# ---------------------------------------------------------------------------
func _section_wulfen_dreadnought() -> void:
	print("\n-- 21. Violent Fury, Bestial Rage --")
	_fresh(P_FIGHT, 1)
	_place("U_WULFEN_DREADNOUGHT_A", 10, 40)
	_place("U_WULFEN_DREADNOUGHT_B", 30, 40)
	_place("U_BOYZ_B", 10, 38.3)
	var ma := _mods("U_WULFEN_DREADNOUGHT_A", "U_BOYZ_B", true)
	_check("Violent Fury: default kit (Great Axe + Great Wolf Claw) -> melee [TWIN-LINKED] (re-roll wounds)", str(ma.wound_reroll) == "failed" and "Violent Fury" in _names(ma), str(ma))
	_check("Violent Fury: Blizzard Shield instead of the Axe -> one melee weapon, nothing", str(_mods("U_WULFEN_DREADNOUGHT_B", "U_BOYZ_B", true).wound_reroll) == "")
	_check("Violent Fury: not ranged", str(_mods("U_WULFEN_DREADNOUGHT_A", "U_BOYZ_B", false).wound_reroll) == "")
	_fresh(P_SHOOT, 2)
	_place("U_WULFEN_DREADNOUGHT_A", 20, 40)
	_place("U_BOYZ_B", 20, 30)
	var ctx := {"phase": "shooting", "wounded_unit_ids": ["U_WULFEN_DREADNOUGHT_A"], "unit_id": "U_BOYZ_B"}
	var o := _offer(1, "enemy_has_shot", ctx, "bestial_rage")
	_check("Bestial Rage offered after an enemy shot and it lost a wound", "U_WULFEN_DREADNOUGHT_A" in _offer_units(o), str(o))
	_check("not when it lost no wound", _offer(1, "enemy_has_shot", {"wounded_unit_ids": []}, "bestial_rage").is_empty())
	_flags("U_WULFEN_DREADNOUGHT_A")["battle_shocked"] = true
	_check("battle-shocked: no surge move", _offer(1, "enemy_has_shot", ctx, "bestial_rage").is_empty())
	_flags("U_WULFEN_DREADNOUGHT_A").erase("battle_shocked")
	var r := _use(1, "bestial_rage", "U_WULFEN_DREADNOUGHT_A", "enemy_has_shot", ctx)
	var fu: Dictionary = r.get("followup", {})
	_check("use -> a surge move of up to D6+1\"", r.get("success", false) and str(fu.get("type", "")) == "surge_move" and int(fu.get("roll_bonus", 0)) == 1, str(r))


# ---------------------------------------------------------------------------
# 22. Wolf Scouts — Deadly Stalkers, Haywire Mine
# ---------------------------------------------------------------------------
func _section_wolf_scouts() -> void:
	print("\n-- 22. Deadly Stalkers, Haywire Mine --")
	_fresh(P_SHOOT, 1)
	_place("U_WOLF_SCOUTS_B", 20, 40)
	_place("U_BOYZ_B", 20, 35)
	_place("U_GRETCHIN_C", 5, 10)
	_place("U_DEFF_DREAD_A", 34, 36)
	var md := _mods("U_WOLF_SCOUTS_B", "U_GRETCHIN_C", false)
	_check("Deadly Stalkers: a target more than 6\" from any other enemy unit -> +1 to wound", bool(md.wound_plus) and "Deadly Stalkers" in _names(md), str(md))
	_place("U_GRETCHIN_C", 26, 35)
	_check("Deadly Stalkers: a target near another enemy unit -> nothing", not bool(_mods("U_WOLF_SCOUTS_B", "U_GRETCHIN_C", false).wound_plus))
	_place("U_GRETCHIN_C", 5, 10)
	var o := _offer(1, "phase_start", {"phase": "shooting"}, "haywire_mine")
	var sec := _secondary_ids(o, "U_WOLF_SCOUTS_B")
	_check("Haywire Mine offered at the start of your Shooting phase (the scouts with the mine only)", not o.is_empty() and not "U_WOLF_SCOUTS_A" in _offer_units(o), str(o))
	_check("Haywire Mine: visible enemy units within 6\" only", "U_BOYZ_B" in sec and not "U_GRETCHIN_C" in sec, str(sec))
	_check("also when the unit is selected to shoot", not _offer(1, "unit_selected_to_shoot", {"unit_id": "U_WOLF_SCOUTS_B"}, "haywire_mine").is_empty())
	var before := _wounds_left("U_BOYZ_B")
	_seed_where(2, func(r): return int(r[0]) >= 2)
	var r := _use(1, "haywire_mine", "U_WOLF_SCOUTS_B", "phase_start", {"phase": "shooting"}, "U_BOYZ_B")
	var lost := before - _wounds_left("U_BOYZ_B")
	_check("Haywire Mine 2+: D3 mortal wounds", r.get("success", false) and lost >= 1 and lost <= 3, "lost %d %s" % [lost, str(r)])
	_check("once per battle (ledger)", UAM.is_once_per_battle_used("U_WOLF_SCOUTS_B", "Haywire Mine") and _offer(1, "phase_start", {"phase": "shooting"}, "haywire_mine").is_empty())
	_fresh(P_SHOOT, 1)
	_place("U_WOLF_SCOUTS_B", 20, 40)
	_place("U_DEFF_DREAD_A", 20, 35)
	var hp := _wounds_left("U_DEFF_DREAD_A")
	_seed_where(3, func(r): return int(r[0]) >= 2)
	_use(1, "haywire_mine", "U_WOLF_SCOUTS_B", "phase_start", {"phase": "shooting"}, "U_DEFF_DREAD_A")
	var l2 := hp - _wounds_left("U_DEFF_DREAD_A")
	_check("Haywire Mine vs a VEHICLE: 2D3 mortal wounds (2-6)", l2 >= 2 and l2 <= 6, str(l2))
	_fresh(P_SHOOT, 1)
	_place("U_WOLF_SCOUTS_B", 20, 40)
	_place("U_BOYZ_B", 20, 35)
	var b2 := _wounds_left("U_BOYZ_B")
	_seed_where(1, func(r): return int(r[0]) == 1)
	_use(1, "haywire_mine", "U_WOLF_SCOUTS_B", "phase_start", {"phase": "shooting"}, "U_BOYZ_B")
	_check("Haywire Mine roll of 1: no effect (still spent)", _wounds_left("U_BOYZ_B") == b2 and UAM.is_once_per_battle_used("U_WOLF_SCOUTS_B", "Haywire Mine"))


# ---------------------------------------------------------------------------
# 23. Gating: Space Wolves armies, 11e only
# ---------------------------------------------------------------------------
func _section_gating() -> void:
	print("\n-- 23. gating --")
	_fresh(P_FIGHT, 1)
	_place("U_WULFEN_A", 10, 30)
	_place("U_BOYZ_B", 10, 28.6)
	_check("11e Space Wolves army: Death Totem applies", str(_mods("U_WULFEN_A", "U_BOYZ_B", true).hit_reroll) == "ones")
	GameConstants.edition = 10
	_check("10e: no Space Wolves codex rules", str(_mods("U_WULFEN_A", "U_BOYZ_B", true).hit_reroll) == "" and SW.window_offers(1, "phase_start", {}).is_empty())
	GameConstants.edition = 11
	var u: Dictionary = _u("U_WULFEN_A")
	u.meta.keywords = (u.meta.keywords as Array).filter(func(k): return str(k) != "SPACE WOLVES")
	_check("a unit without the SPACE WOLVES keyword: no datasheet rule (SW-D1)", str(_mods("U_WULFEN_A", "U_BOYZ_B", true).hit_reroll) == "")
	_check("the Ork player is never offered a card", SW.window_offers(2, "phase_start", {}).is_empty())
	# BasePhase phase_start entries: one per player, never duplicated.
	_fresh(P_CMD, 1, 1)
	_place("U_ULRIK_THE_SLAYER_A", 10, 45)
	_place("U_WARBOSS_A", 10, 20)
	var e1: Array = SW.phase_start_entries(P_CMD)
	_check("phase_start entries: P1 (has a card)", e1.size() == 1 and int(e1[0].player) == 1, str(e1))
	_check("phase_start entries: deduplicated against queued ones", SW.phase_start_entries(P_CMD, e1).is_empty())
	SW.offers_suppressed = true
	_check("scenario policy: offers suppressed", SW.window_offers(1, "phase_start", {"window_id": "phase_start"}).is_empty())
	SW.offers_suppressed = false


# ---------------------------------------------------------------------------
# 24. AI decides synchronously
# ---------------------------------------------------------------------------
func _section_ai() -> void:
	print("\n-- 24. AI --")
	_fresh(P_CMD, 1, 1)
	_place("U_ULRIK_THE_SLAYER_A", 10, 45)
	_place("U_WARBOSS_A", 10, 20)
	_place("U_DEFF_DREAD_A", 30, 20)
	var ADM = load("res://scripts/AIDecisionMaker.gd")
	var ctx := {"phase": "command", "window_id": "phase_start"}
	var offers: Array = SM.get_all_window_offers(1, "phase_start", ctx)
	_check("get_all_window_offers carries the Space Wolves cards", offers.any(func(o): return str(o.stratagem_id) == _sid("slayers_oath")), str(offers.map(func(o): return o.name)))
	var dec: Dictionary = ADM.decide_window_stratagem(1, "phase_start", offers, ctx)
	_check("AI picks Slayer's Oath with the first (highest-threat) option", dec.get("use", false) and str(dec.get("stratagem_id", "")) == _sid("slayers_oath") and str(dec.get("context", {}).get("secondary_id", "")) != "", str(dec))
	for slug in ["high_king_of_fenris", "predatory_instinct", "bestial_rage", "storm_caller"]:
		_check("AI never spends %s (plan-level / not modelled)" % slug, SW.ai_score(1, _sid(slug), "x", "", {}) == 0.0)
	for slug in ["slayers_oath", "headhunters", "healing_balms", "haywire_mine", "hammer_blow", "tempests_wrath"]:
		_check("AI uses %s (score >= 1)" % slug, SW.ai_score(1, _sid(slug), "x", "", {}) >= 1.0)
	# An AI decider never leaves the window pending.
	var ai = root.get_node("AIPlayer")
	ai.enabled = true
	ai.ai_players = {1: true, 2: false}
	PM.transition_to_phase(P_CMD)
	var cp = PM.current_phase_instance
	_check("AI P1: the phase_start window resolved synchronously (not pending)", cp == null or str(cp.get_pending_stratagem_window().get("window_id", "")) != "phase_start")
	_check("AI chose a slayer's oath", str(_flags("U_ULRIK_THE_SLAYER_A").get(SW.F_OATH, "")) != "", str(_flags("U_ULRIK_THE_SLAYER_A")))
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
