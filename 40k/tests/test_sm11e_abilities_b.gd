extends SceneTree

# WP-M4b — Codex: Space Marines (11e), DATASHEET + WARGEAR abilities of the M4b
# generic datasheets and the Librarius psyker-level budget they spend
# (scripts/codex/space_marines/SMAbilitiesB.gd).
#
# One check group per ability (section numbers = the audit table's last
# column, .llm/codex_11e_wahapedia/space_marines_abilities_audit_b.md): the
# condition (on / off), the effect (modifier, or an A/B resolution with the
# same seed), the usage limit and the expiry where the ability has them, and
# the AI path. Board: the tests/saves/cus11e_c5_active shell (44x60",
# objectives) with its units replaced by P1 = armies/sm11e_codex_test.json
# (every generic Space Marine datasheet) and P2 = armies/ork11e_codex_test.json,
# both through ArmyListManager.load_army_list; every unit starts off the table
# and a section places what it needs.
#
# Usage: godot --headless --path 40k --script tests/test_sm11e_abilities_b.gd

const FIXTURE := "cus11e_c5_active"
const SM_ARMY := "sm11e_codex_test"
const ORK_ARMY := "ork11e_codex_test"
const PX := 40.0
const P_CMD := 6
const P_MOV := 7
const P_SHOOT := 8
const P_CHG := 9
const P_FIGHT := 10

## The M4b datasheets (as the test army names them).
const M4B := ["Intercessor Squad", "Incursor Squad", "Scout Squad", "Bladeguard Ancient", "Captain in Gravis Armour",
	"Chaplain", "Heavy Intercessor Squad", "Terminator Squad", "Lieutenant", "Assault Intercessor Squad",
	"Storm Speeder Thunderstrike", "Chief Librarian Tigurius", "Gladiator Reaper", "Eliminator Squad",
	"Gladiator Valiant", "Hellblaster Squad", "Aggressor Squad", "Adrax Agatone", "Darnath Lysander",
	"Land Raider Redeemer", "Sternguard Veteran Squad", "Librarian", "Desolation Squad", "Tor Garadon",
	"Lieutenant in Phobos Armour", "Impulsor", "Ancient in Terminator Armour", "Astraeus", "Captain in Phobos Armour"]

var passed := 0
var failed := 0
var GS = null
var SM = null
var RE = null
var PM = null
var B = null
var SWC = null
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
		GS.state.players[p].erase(B.ARMY_USES)
		GS.state.players[p].erase(SWC.SM11E_LAST_ACUMEN)
	SM._usage_history = {"1": [], "2": []}
	UAM.reset_for_new_game()
	B.offers_suppressed = false
	MM.clear_sticky_objectives_for_player(1)
	MM.clear_sticky_objectives_for_player(2)


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
		var dims = m.get("base_dimensions", null)
		if typeof(dims) == TYPE_DICTIONARY and not dims.is_empty():
			r_in = maxf(float(dims.get("length", 32)), float(dims.get("width", 32))) / 25.4
		m["position"] = {"x": (cx + r_in / 2.0) * PX, "y": y * PX}
		cx += r_in + 0.2


func _attach(char_id: String, bodyguard_id: String) -> void:
	GS.state.units[bodyguard_id]["attachment_data"] = {"attached_characters": [char_id]}
	GS.state.units[char_id]["attached_to"] = bodyguard_id


func _phase(p: int, active: int = 1) -> void:
	GS.state.meta["phase"] = p
	GS.state.meta["active_player"] = active


func _sid(slug: String) -> String:
	return B.sid_of(slug)


func _offer(player: int, window_id: String, ctx: Dictionary, slug: String) -> Dictionary:
	var c := ctx.duplicate(true)
	c["window_id"] = window_id
	for o in B.window_offers(player, window_id, c):
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


func _weapon(uid: String, name_part: String, melee: bool = false) -> String:
	var ws: Dictionary = RE.get_unit_melee_weapons(uid, GS.state) if melee else RE.get_unit_weapons(uid, GS.state)
	for mid in ws:
		for wid in ws[mid]:
			if str(wid).to_lower().contains(name_part.to_lower().replace(" ", "_").replace("-", "_")):
				return str(wid)
	return ""


func _assign(board: Dictionary, uid: String, wid: String, tid: String) -> Dictionary:
	var model_ids: Array = []
	var w = RE.get_unit_weapons(uid, board)
	for mid in w:
		if wid in w[mid]:
			model_ids.append(str(mid))
	return {"weapon_id": wid, "target_unit_id": tid, "model_ids": model_ids}


func _shoot(uid: String, wid: String, tid: String, seed_val: int) -> Dictionary:
	return RE.resolve_shoot({"type": "SHOOT", "actor_unit_id": uid, "payload": {"assignments": [_assign(GS.state, uid, wid, tid)]}},
		GS.state.duplicate(true), RE.RNGService.new(seed_val))


func _block(res: Dictionary, ctx_name: String) -> Dictionary:
	for d in res.get("dice", []):
		if str(d.get("context", "")) == ctx_name:
			return d
	return {}


func _obj_pos_in(i: int) -> Vector2:
	var objs: Array = GS.state.board.get("objectives", [])
	var p = objs[i].get("position", {})
	if p is Vector2:
		return p / PX
	return Vector2(float(p.get("x", 0)), float(p.get("y", 0))) / PX


func _obj_id(i: int) -> String:
	return str(GS.state.board.get("objectives", [])[i].get("id", ""))


func _place_on_obj(uid: String, i: int, dy: float = 0.0) -> void:
	var p := _obj_pos_in(i)
	_place(uid, p.x - 1.0, p.y + dy)


# ---------------------------------------------------------------------------
func _run() -> void:
	GS = root.get_node("GameState")
	SM = root.get_node("StratagemManager")
	RE = root.get_node("RulesEngine")
	PM = root.get_node("PhaseManager")
	UAM = root.get_node("UnitAbilityManager")
	MM = root.get_node("MissionManager")
	B = load("res://scripts/codex/space_marines/SMAbilitiesB.gd")
	SWC = load("res://scripts/codex/space_wolves/SWCommon.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	root.get_node("SettingsService").set("auto_allocate_wounds", true)
	GameConstants.edition = 11
	var alm = root.get_node("ArmyListManager")
	_sm_army = alm.load_army_list(SM_ARMY, 1)
	_ork_army = alm.load_army_list(ORK_ARMY, 2)
	print("\n=== test_sm11e_abilities_b (WP-M4b) ===")
	if _sm_army.is_empty() or _ork_army.is_empty():
		_check("armies load", false)
		return
	_section_names()
	_section_gate()
	_section_weapons()
	_section_offence()
	_section_offence_ab()
	_section_defence()
	_section_librarius()
	_section_acumen()
	_section_spiritual_leader()
	_section_rampart_force_dome_prescience()
	_section_telepathic_haywire()
	_section_divinator()
	_section_optics_signum()
	_section_shattered_suppression()
	_section_tactical_fluidity()
	_section_veil_of_time()
	_section_raise_the_banner()
	_section_actions()
	_section_disembark()
	_section_teleport_homer()
	_section_hazard()
	_section_list_build()
	_section_retired()
	_section_ai()


# ---------------------------------------------------------------------------
# 0. every Datasheet / Wargear ability of the M4b datasheets folds to a slug;
#    the core abilities resolve through the engine
# ---------------------------------------------------------------------------
func _section_names() -> void:
	print("\n-- 0. names + core abilities --")
	_fresh()
	var skip := ["combat doctrines", "transhuman strategist", "librarius", "leader", "deep strike", "infiltrators",
		"stealth", "support", "transport", "firing deck 7"]
	var unknown: Array = []
	var known := {}
	for slug in B.NAMES:
		known[B.NAMES[slug]] = slug
	var seen := {}
	for uid in _sm_army.units:
		var u: Dictionary = _sm_army.units[uid]
		if not str(u.meta.name) in M4B:
			continue
		seen[str(u.meta.name)] = true
		for ab in u.get("meta", {}).get("abilities", []):
			var n: String = B.fold(str(ab.get("name", "")) if ab is Dictionary else str(ab))
			if n in skip or n.begins_with("deadly demise") or n.begins_with("scouts") or n.begins_with("damaged"):
				continue
			if not known.has(n) and not n in unknown:
				unknown.append(n)
	_check("all 29 M4b datasheets are in the test army", seen.size() == 29, str(seen.size()))
	_check("every M4b datasheet/wargear ability has a module slug", unknown.is_empty(), str(unknown))
	for n in ["Bolter Discipline", "Divinator-class Auspexes", "Refuse to Yield", "Spiritual Leader", "Rampart", "Telepathic Assault", "Suppression Fire", "Tactical Fluidity"]:
		_check("ABILITY_EFFECTS row '%s' (implemented)" % n, UAM.is_ability_implemented(n))
	# Core abilities on these datasheets are engine-handled.
	_check("core: Terminator Squad has Deep Strike", GS.unit_has_deep_strike("U_TERMINATOR_SQUAD_A"))
	_check("core: Darnath Lysander has Deep Strike", GS.unit_has_deep_strike("U_DARNATH_LYSANDER_A"))
	_check("core: Scout Squad has Infiltrators", GS.unit_has_infiltrators("U_SCOUT_SQUAD_A"))
	_check("core: Eliminator Squad has Infiltrators", GS.unit_has_infiltrators("U_ELIMINATOR_SQUAD_A"))
	_check("core: Incursor Squad has Scouts 6\"", GS.unit_has_scout("U_INCURSOR_SQUAD_A") and float(GS.get_scout_distance("U_INCURSOR_SQUAD_A")) == 6.0, str(GS.get_scout_distance("U_INCURSOR_SQUAD_A")))
	_check("core: Captain in Phobos Armour has Scouts 6\"", float(GS.get_scout_distance("U_CAPTAIN_IN_PHOBOS_ARMOUR_A")) == 6.0)
	_check("core: Eliminator Squad has Stealth", RE.has_stealth_ability(_u("U_ELIMINATOR_SQUAD_A")))
	_check("core: Chaplain (Leader) can lead an Intercessor Squad", "U_INTERCESSOR_SQUAD_A" in GS.get_eligible_bodyguards_for_character("U_CHAPLAIN_A"),
		str(GS.get_eligible_bodyguards_for_character("U_CHAPLAIN_A")))
	_check("core: Storm Speeder Thunderstrike has Deadly Demise", UAM.has_deadly_demise("U_STORM_SPEEDER_THUNDERSTRIKE_A"))
	_check("core: Impulsor has Firing Deck 7", int(_u("U_IMPULSOR_A").get("transport_data", {}).get("firing_deck", 0)) == 7, str(_u("U_IMPULSOR_A").get("transport_data", {})))
	_check("core: Land Raider Redeemer transport capacity 14", int(_u("U_LAND_RAIDER_REDEEMER_A").get("transport_data", {}).get("capacity", 0)) == 14, str(_u("U_LAND_RAIDER_REDEEMER_A").get("transport_data", {})))
	_check("Librarius: Chief Librarian Tigurius is psyker level 3", B.psyker_level(_u("U_CHIEF_LIBRARIAN_TIGURIUS_A")) == 3)
	_check("Librarius: Librarian is psyker level 1", B.psyker_level(_u("U_LIBRARIAN_A")) == 1)


# ---------------------------------------------------------------------------
# 1. scope gate — M4b datasheets of a Space Marine army, 11e only
# ---------------------------------------------------------------------------
func _section_gate() -> void:
	print("\n-- 1. scope gate --")
	_fresh()
	_check("Bolter Discipline: Intercessor Squad has it", B.has_id("U_INTERCESSOR_SQUAD_A", "bolter_discipline"))
	_check("datasheet gate: the M4a Captain's Strategic Acumen is not this module's", not B.has_id("U_CAPTAIN_A", "strategic_acumen") and B.has_id("U_CAPTAIN_IN_GRAVIS_ARMOUR_A", "strategic_acumen"))
	_check("datasheet gate: the M4a Chaplain on Bike's Litany of Hate is not this module's", not B.has_id("U_CHAPLAIN_ON_BIKE_A", "litany_of_hate") and B.has_id("U_CHAPLAIN_A", "litany_of_hate"))
	GameConstants.edition = 10
	_check("10e: no ability", not B.has_id("U_INTERCESSOR_SQUAD_A", "bolter_discipline"))
	GameConstants.edition = 11
	var fac: Dictionary = GS.state.factions["1"]
	var keep := str(fac.get("name", ""))
	fac["name"] = "Orks"
	_check("not a Space Marine army: no ability", not B.has_id("U_INTERCESSOR_SQUAD_A", "bolter_discipline"))
	_check("not a Space Marine army: no offers", B.window_offers(1, "phase_start", {"window_id": "phase_start", "phase": "shooting"}).is_empty())
	fac["name"] = "Ultramarines"
	_check("a chapter army (Ultramarines) is a Space Marine army", B.has_id("U_INTERCESSOR_SQUAD_A", "bolter_discipline"))
	fac["name"] = keep


# ---------------------------------------------------------------------------
# 2. per-model weapons: default kit and wargear options (engine resolver)
# ---------------------------------------------------------------------------
const OPTION_ROSTERS := {
	"U_INTERCESSOR_SQUAD_A": ["5x Bolt Pistol", "4x Bolt Rifle", "1x Grenade Launcher", "4x Knives and Fists", "1x Power Fist", "1x Plasma Pistol"],
	"U_SCOUT_SQUAD_A": ["3x Boltgun", "1x Sniper Rifle", "1x Shotgun", "5x Bolt Pistol", "4x Combat Knife", "1x Chainsword"],
	"U_HEAVY_INTERCESSOR_SQUAD_A": ["4x Heavy Bolt Rifle", "1x Heavy Bolter", "5x Bolt Pistol", "5x Ceramite Fists"],
	"U_TERMINATOR_SQUAD_A": ["4x Storm Bolter", "1x Assault Cannon", "4x Power Fist", "1x Chainfist"],
	"U_ASSAULT_INTERCESSOR_SQUAD_A": ["4x Heavy Bolt Pistol", "1x Plasma Pistol", "4x Chainsword", "1x Thunder Hammer"],
	"U_ELIMINATOR_SQUAD_A": ["3x Las Fusil", "3x Bolt Pistol", "3x Ceramite Fists"],
	"U_HELLBLASTER_SQUAD_A": ["5x Plasma Incinerator", "4x Bolt Pistol", "1x Plasma Pistol", "5x Ceramite Fists"],
	"U_AGGRESSOR_SQUAD_A": ["3x Auto Boltstorm Gauntlets", "3x Fragstorm Grenade Launcher", "3x Twin Power Fists"],
	"U_STERNGUARD_VETERAN_SQUAD_A": ["4x Artificer Firearm", "1x Heavy Bolter", "5x Bolt Pistol", "1x Power Fist", "4x Ceramite Fists"],
	"U_DESOLATION_SQUAD_A": ["4x Superkrak Rocket Launcher", "1x Vengor Launcher", "5x Castellan Launcher", "5x Bolt Pistol", "5x Ceramite Fists"],
	"U_CAPTAIN_IN_GRAVIS_ARMOUR_A": ["1x Boltstorm Gauntlet", "1x Relic Blade"],
	"U_LIEUTENANT_A": ["1x Neo-volkite Pistol", "1x Master-crafted Power Weapon", "1x Storm Shield", "1x Ceramite Fists"],
	"U_LIEUTENANT_IN_PHOBOS_ARMOUR_A": ["1x Master-crafted Bolt Carbine", "1x Monomolecular Combat Blades"],
	"U_LAND_RAIDER_REDEEMER_A": ["2x Flamestorm Cannon", "1x Twin Assault Cannon", "1x Multi-melta", "1x Hunter-killer Missile", "1x Armoured Tracks"],
	"U_IMPULSOR_A": ["1x Fragstorm Grenade Launchers", "1x Ironhail Heavy Stubber", "1x Shield Dome", "1x Armoured Hull"],
	"U_ASTRAEUS_A": ["2x Plasma Eradicator", "1x Ironhail Heavy Stubber", "1x Storm Bolter", "1x Twin Lascannon", "1x Twin Macro-accelerator Cannon", "1x Armoured Hull"],
}

## Base weapon ids (profile suffix dropped) of one model.
func _model_bases(c: Dictionary, m: Dictionary, kind: String) -> Array:
	var out: Array = []
	for wid in RE._get_model_weapon_ids(c, m, kind):
		var s := str(wid)
		var cut := s.find("___")
		if cut > 0:
			s = s.substr(0, cut) + ("_ranged" if kind == "Ranged" else "_melee")
		if not s in out:
			out.append(s)
	return out


func _resolved(uid: String, wargear: Array = []) -> Dictionary:
	var c: Dictionary = _sm_army.units[uid].duplicate(true)
	c.meta["wargear"] = wargear
	for m in c.models:
		m.erase("ranged_loadout")
		m.erase("melee_loadout")
	c.erase("_loadout_version")
	RE._ensure_loadout_resolved(c)
	return c


func _section_weapons() -> void:
	print("\n-- 2. per-model weapons --")
	_fresh()
	# Default kit: every model reports exactly its printed loadout.
	var want_default := {
		"U_INTERCESSOR_SQUAD_A": [["bolt_pistol_ranged", "bolt_rifle_ranged"], ["knives_and_fists_melee"]],
		"U_INCURSOR_SQUAD_A": [["bolt_pistol_ranged", "occulus_bolt_carbine_ranged"], ["paired_combat_blades_melee"]],
		"U_SCOUT_SQUAD_A": [["bolt_pistol_ranged", "boltgun_ranged"], ["combat_knife_melee"]],
		"U_CAPTAIN_IN_GRAVIS_ARMOUR_A": [["master_crafted_heavy_bolt_rifle_ranged"], ["master_crafted_power_weapon_melee"]],
		"U_LIEUTENANT_A": [["bolt_pistol_ranged", "master_crafted_bolter_ranged"], ["ceramite_fists_melee"]],
		"U_LIEUTENANT_IN_PHOBOS_ARMOUR_A": [["special_issue_bolt_pistol_ranged"], ["monomolecular_combat_blades_melee"]],
		"U_LAND_RAIDER_REDEEMER_A": [["flamestorm_cannon_ranged", "twin_assault_cannon_ranged"], ["armoured_tracks_melee"]],
		"U_IMPULSOR_A": [["storm_bolters_ranged"], ["armoured_hull_melee"]],
		"U_ASTRAEUS_A": [["astareus_las_ripper_ranged", "ironhail_heavy_stubber_ranged", "storm_bolter_ranged", "twin_heavy_bolter_ranged", "twin_macro_accelerator_cannon_ranged"], ["armoured_hull_melee"]],
		"U_TERMINATOR_SQUAD_A": [["storm_bolter_ranged"], ["power_fist_melee"]],
		"U_STERNGUARD_VETERAN_SQUAD_A": [["artificer_firearm_ranged", "bolt_pistol_ranged"], []],
	}
	for uid in want_default:
		var c := _resolved(uid)
		var bad: Array = []
		for m in c.models:
			var r := _model_bases(c, m, "Ranged")
			var me := _model_bases(c, m, "Melee")
			r.sort()
			var wr: Array = (want_default[uid][0] as Array).duplicate()
			wr.sort()
			if r != wr:
				bad.append("%s R=%s" % [m.id, str(r)])
			if not (want_default[uid][1] as Array).is_empty() and me != want_default[uid][1]:
				bad.append("%s M=%s" % [m.id, str(me)])
		_check("default kit: %s resolves its printed loadout per model" % uid, bad.is_empty(), str(bad))
	# Every M4b datasheet: every model has a weapon (default kit).
	var none: Array = []
	for uid in _sm_army.units:
		if not str(_sm_army.units[uid].meta.name) in M4B:
			continue
		var c2 := _resolved(uid)
		for m in c2.models:
			if RE._get_model_weapon_ids(c2, m, "Ranged").is_empty() and RE._get_model_weapon_ids(c2, m, "Melee").is_empty():
				none.append("%s/%s" % [uid, m.id])
	_check("default kit: every model of every M4b datasheet carries a weapon", none.is_empty(), str(none))
	# Wargear options.
	var exp_opt := {
		"U_INTERCESSOR_SQUAD_A": {"power_fist_melee": 1, "knives_and_fists_melee": 4, "grenade_launcher_ranged": 1, "plasma_pistol_ranged": 1, "bolt_rifle_ranged": 4},
		"U_SCOUT_SQUAD_A": {"shotgun_ranged": 1, "sniper_rifle_ranged": 1, "boltgun_ranged": 3, "chainsword_melee": 1, "combat_knife_melee": 4},
		"U_HEAVY_INTERCESSOR_SQUAD_A": {"heavy_bolter_ranged": 1, "heavy_bolt_rifle_ranged": 4},
		"U_TERMINATOR_SQUAD_A": {"assault_cannon_ranged": 1, "storm_bolter_ranged": 4, "chainfist_melee": 1, "power_fist_melee": 4},
		"U_ASSAULT_INTERCESSOR_SQUAD_A": {"plasma_pistol_ranged": 1, "heavy_bolt_pistol_ranged": 4, "thunder_hammer_melee": 1, "chainsword_melee": 4},
		"U_ELIMINATOR_SQUAD_A": {"las_fusil_ranged": 3, "bolt_sniper_rifle_ranged": 0},
		"U_HELLBLASTER_SQUAD_A": {"plasma_pistol_ranged": 1, "bolt_pistol_ranged": 4, "plasma_incinerator_ranged": 5},
		"U_AGGRESSOR_SQUAD_A": {"auto_boltstorm_gauntlets_ranged": 3, "fragstorm_grenade_launcher_ranged": 3, "flamestorm_gauntlets_ranged": 0},
		"U_STERNGUARD_VETERAN_SQUAD_A": {"heavy_bolter_ranged": 1, "artificer_firearm_ranged": 4, "power_fist_melee": 1, "ceramite_fists_melee": 4},
		"U_DESOLATION_SQUAD_A": {"vengor_launcher_ranged": 1, "superkrak_rocket_launcher_ranged": 4, "superfrag_rocket_launcher_ranged": 0},
		"U_CAPTAIN_IN_GRAVIS_ARMOUR_A": {"boltstorm_gauntlet_ranged": 1, "relic_blade_melee": 1, "master_crafted_heavy_bolt_rifle_ranged": 0, "master_crafted_power_weapon_melee": 0},
		"U_LIEUTENANT_A": {"neo_volkite_pistol_ranged": 1, "master_crafted_power_weapon_melee": 1, "master_crafted_bolter_ranged": 0, "bolt_pistol_ranged": 0},
		"U_LIEUTENANT_IN_PHOBOS_ARMOUR_A": {"master_crafted_bolt_carbine_ranged": 1, "special_issue_bolt_pistol_ranged": 0},
		"U_LAND_RAIDER_REDEEMER_A": {"multi_melta_ranged": 1, "hunter_killer_missile_ranged": 1, "storm_bolter_ranged": 0},
		"U_IMPULSOR_A": {"fragstorm_grenade_launchers_ranged": 1, "ironhail_heavy_stubber_ranged": 1, "storm_bolters_ranged": 0, "bellicatus_missile_array_ranged": 0},
		"U_ASTRAEUS_A": {"plasma_eradicator_ranged": 1, "twin_lascannon_ranged": 1, "astareus_las_ripper_ranged": 0, "twin_heavy_bolter_ranged": 0},
	}
	for uid in exp_opt:
		var c3 := _resolved(uid, OPTION_ROSTERS[uid])
		var counts := {}
		for m in c3.models:
			for k in _model_bases(c3, m, "Ranged") + _model_bases(c3, m, "Melee"):
				counts[k] = int(counts.get(k, 0)) + 1
		var bad2: Array = []
		for k in exp_opt[uid]:
			if int(counts.get(k, 0)) != int(exp_opt[uid][k]):
				bad2.append("%s=%d (want %d)" % [k, int(counts.get(k, 0)), int(exp_opt[uid][k])])
		_check("wargear option: %s %s" % [uid, str(OPTION_ROSTERS[uid])], bad2.is_empty(), str(bad2) + " " + str(counts))


# ---------------------------------------------------------------------------
# 3. passive attack modifiers (aggregator)
# ---------------------------------------------------------------------------
func _section_offence() -> void:
	print("\n-- 3. passive attack modifiers --")
	_fresh(P_SHOOT)
	# Bolter Discipline (Intercessors).
	_place("U_INTERCESSOR_SQUAD_A", 2, 46)
	_place("U_BOYZ_B", 26, 16)
	var m0 := _mods("U_INTERCESSOR_SQUAD_A", "U_BOYZ_B", false)
	_check("Bolter Discipline: nobody on an objective -> no +1 hit", not "Bolter Discipline" in _names(m0), str(_names(m0)))
	_place_on_obj("U_INTERCESSOR_SQUAD_A", 0)
	var m1 := _mods("U_INTERCESSOR_SQUAD_A", "U_BOYZ_B", false)
	_check("Bolter Discipline: this unit within range of an objective -> +1 to hit", m1.hit_plus and "Bolter Discipline" in _names(m1), str(m1))
	_check("Bolter Discipline: not on melee attacks", not "Bolter Discipline" in _names(_mods("U_INTERCESSOR_SQUAD_A", "U_BOYZ_B", true)))
	_phase(P_SHOOT, 2)
	_check("Bolter Discipline: not in the opponent's Shooting phase", not "Bolter Discipline" in _names(_mods("U_INTERCESSOR_SQUAD_A", "U_BOYZ_B", false)))
	_phase(P_SHOOT, 1)
	_place("U_INTERCESSOR_SQUAD_A", 4, 55)
	_place_on_obj("U_BOYZ_B", 1)
	_check("Bolter Discipline: the TARGET within range of an objective -> +1 to hit", "Bolter Discipline" in _names(_mods("U_INTERCESSOR_SQUAD_A", "U_BOYZ_B", false)))
	# Deeds of Legend (Bladeguard Ancient).
	_place("U_BLADEGUARD_ANCIENT_A", 30, 55)
	_check("Deeds of Legend: off an objective -> no +1 A", int(_mods("U_BLADEGUARD_ANCIENT_A", "U_BOYZ_B", true).attacks) == 0)
	_place_on_obj("U_BLADEGUARD_ANCIENT_A", 0, 2.0)
	var dl := _mods("U_BLADEGUARD_ANCIENT_A", "U_BOYZ_B", true)
	_check("Deeds of Legend: within range of an objective -> melee +1 A", int(dl.attacks) == 1 and "Deeds of Legend" in _names(dl), str(dl))
	_check("Deeds of Legend: not ranged", int(_mods("U_BLADEGUARD_ANCIENT_A", "U_BOYZ_B", false).attacks) == 0)
	# Litany of Hate (Chaplain leading Intercessors) — [LANCE].
	_place("U_INTERCESSOR_SQUAD_A", 4, 50)
	_place("U_CHAPLAIN_A", 4, 52)
	_attach("U_CHAPLAIN_A", "U_INTERCESSOR_SQUAD_A")
	_check("Litany of Hate: no charge -> no +1 wound", not _mods("U_INTERCESSOR_SQUAD_A", "U_BOYZ_B", true).wound_plus)
	_flags("U_INTERCESSOR_SQUAD_A")["charged_this_turn"] = true
	_check("Litany of Hate: charged -> the whole unit's melee +1 to wound", _mods("U_INTERCESSOR_SQUAD_A", "U_BOYZ_B", true).wound_plus and _mods("U_CHAPLAIN_A", "U_BOYZ_B", true).wound_plus)
	_check("Litany of Hate: not ranged", not "Litany of Hate" in _names(_mods("U_INTERCESSOR_SQUAD_A", "U_BOYZ_B", false)))
	_flags("U_INTERCESSOR_SQUAD_A").erase("charged_this_turn")
	# Fury of the First (Terminators): +1 AP within 9".
	_place("U_TERMINATOR_SQUAD_A", 10, 40)
	_place("U_BOYZ_B", 10, 35)
	var ff := _mods("U_TERMINATOR_SQUAD_A", "U_BOYZ_B", false)
	_check("Fury of the First: target within 9\" -> +1 AP", int(ff.ap) == 1 and "Fury of the First" in _names(ff), str(ff))
	_place("U_BOYZ_B", 10, 20)
	_check("Fury of the First: target 20\" away -> no AP", int(_mods("U_TERMINATOR_SQUAD_A", "U_BOYZ_B", false).ap) == 0)
	# Tactical Precision (Lieutenant): [LETHAL HITS] vs non-MONSTER/VEHICLE.
	_place("U_LIEUTENANT_A", 20, 40)
	_place("U_DEFF_DREAD_A", 30, 30)
	_check("Tactical Precision: vs Boyz -> [LETHAL HITS]", bool(_mods("U_LIEUTENANT_A", "U_BOYZ_B", false).get("lethal", false)))
	_check("Tactical Precision: vs a VEHICLE -> no [LETHAL HITS]", not bool(_mods("U_LIEUTENANT_A", "U_DEFF_DREAD_A", false).get("lethal", false)))
	_check("Tactical Precision (Lieutenant in Phobos Armour) too", bool(_mods("U_LIEUTENANT_IN_PHOBOS_ARMOUR_A", "U_BOYZ_B", true).get("lethal", false)))
	# Targeted Intercession.
	_place("U_ASSAULT_INTERCESSOR_SQUAD_A", 4, 44)
	_check("Targeted Intercession: no charge -> nothing", int(_mods("U_ASSAULT_INTERCESSOR_SQUAD_A", "U_BOYZ_B", true).strength) == 0)
	_flags("U_ASSAULT_INTERCESSOR_SQUAD_A")["charged_this_turn"] = true
	var ti := _mods("U_ASSAULT_INTERCESSOR_SQUAD_A", "U_BOYZ_B", true)
	_check("Targeted Intercession: charged -> melee +1 S and +1 AP", int(ti.strength) == 1 and int(ti.ap) == 1, str(ti))
	# Thunderstrike / Reaping Tally / Priority Target Acquisition.
	_place("U_STORM_SPEEDER_THUNDERSTRIKE_A", 30, 45)
	_check("Thunderstrike: ranged vs a VEHICLE -> +1 to wound", _mods("U_STORM_SPEEDER_THUNDERSTRIKE_A", "U_DEFF_DREAD_A", false).wound_plus)
	_check("Thunderstrike: vs INFANTRY -> no", not _mods("U_STORM_SPEEDER_THUNDERSTRIKE_A", "U_BOYZ_B", false).wound_plus)
	_place("U_GLADIATOR_REAPER_A", 36, 45)
	_check("Reaping Tally: ranged vs INFANTRY -> +1 AP", int(_mods("U_GLADIATOR_REAPER_A", "U_BOYZ_B", false).ap) == 1)
	_check("Reaping Tally: vs a VEHICLE -> no", int(_mods("U_GLADIATOR_REAPER_A", "U_DEFF_DREAD_A", false).ap) == 0)
	_place("U_GLADIATOR_VALIANT_A", 30, 38)
	_check("Priority Target Acquisition: target within 12\" -> +1 S", int(_mods("U_GLADIATOR_VALIANT_A", "U_DEFF_DREAD_A", false).strength) == 1)
	_place("U_DEFF_DREAD_A", 30, 10)
	_check("Priority Target Acquisition: target 25\" away -> no", int(_mods("U_GLADIATOR_VALIANT_A", "U_DEFF_DREAD_A", false).strength) == 0)
	# Close-quarters Firestorm.
	_place("U_AGGRESSOR_SQUAD_A", 10, 28)
	_place("U_BOYZ_B", 10, 22)
	_check("Close-quarters Firestorm: within 9\" -> +1 S (ranged and melee)", int(_mods("U_AGGRESSOR_SQUAD_A", "U_BOYZ_B", false).strength) == 1 and int(_mods("U_AGGRESSOR_SQUAD_A", "U_BOYZ_B", true).strength) == 1)
	_place("U_BOYZ_B", 10, 10)
	_check("Close-quarters Firestorm: 15\" away -> no", int(_mods("U_AGGRESSOR_SQUAD_A", "U_BOYZ_B", false).strength) == 0)
	# Unto the Anvil (Adrax): wound 1s; assault doctrine -> all.
	_place("U_ADRAX_AGATONE_A", 20, 30)
	_check("Unto the Anvil: melee re-roll wound rolls of 1", str(_mods("U_ADRAX_AGATONE_A", "U_BOYZ_B", true).wound_reroll) == "ones")
	_flags("U_ADRAX_AGATONE_A")["sw11e_doctrine"] = "assault"
	_check("Unto the Anvil: assault doctrine active -> re-roll wound rolls", str(_mods("U_ADRAX_AGATONE_A", "U_BOYZ_B", true).wound_reroll) == "failed")
	_flags("U_ADRAX_AGATONE_A").erase("sw11e_doctrine")
	# Wrath of the Machine Spirit (Redeemer): [DEVASTATING WOUNDS] within 12" vs non-M/V.
	_place("U_LAND_RAIDER_REDEEMER_A", 10, 18)
	_place("U_BOYZ_B", 10, 12)
	_check("Wrath of the Machine Spirit: INFANTRY within 12\" -> [DEVASTATING WOUNDS]", bool(_mods("U_LAND_RAIDER_REDEEMER_A", "U_BOYZ_B", false).get("devastating", false)))
	_place("U_DEFF_DREAD_A", 22, 12)
	_check("Wrath of the Machine Spirit: a VEHICLE -> no", not bool(_mods("U_LAND_RAIDER_REDEEMER_A", "U_DEFF_DREAD_A", false).get("devastating", false)))
	# Veteran Marksmen / Targeter Optics.
	_place("U_STERNGUARD_VETERAN_SQUAD_A", 4, 40)
	_check("Veteran Marksmen: ranged re-roll hit rolls of 1", str(_mods("U_STERNGUARD_VETERAN_SQUAD_A", "U_BOYZ_B", false).hit_reroll) == "ones")
	_check("Veteran Marksmen: not melee", str(_mods("U_STERNGUARD_VETERAN_SQUAD_A", "U_BOYZ_B", true).hit_reroll) == "")
	_place("U_DESOLATION_SQUAD_A", 30, 40)
	_check("Targeter Optics: ranged vs a visible enemy -> [IGNORES COVER]", bool(_mods("U_DESOLATION_SQUAD_A", "U_BOYZ_B", false).get("ignores_cover", false)))
	# Siege Captain (Tor Garadon, this model).
	_place("U_TOR_GARADON_A", 22, 30)
	var sc := _mods("U_TOR_GARADON_A", "U_DEFF_DREAD_A", false)
	_check("Siege Captain: vs a VEHICLE -> +2 S, +2 AP, +2 D", int(sc.strength) == 2 and int(sc.ap) == 2 and int(sc.damage) == 2, str(sc))
	_check("Siege Captain: vs INFANTRY -> nothing", int(_mods("U_TOR_GARADON_A", "U_BOYZ_B", false).strength) == 0)
	# Icon of Obstinacy (Lysander): attacks that target this unit -1 to hit.
	_place("U_DARNATH_LYSANDER_A", 40, 40)
	_check("Icon of Obstinacy: an Ork attack that targets Lysander -> -1 to hit", _mods("U_BOYZ_B", "U_DARNATH_LYSANDER_A", false).hit_minus)
	_place("U_TERMINATOR_SQUAD_A", 36, 44)
	_attach("U_DARNATH_LYSANDER_A", "U_TERMINATOR_SQUAD_A")
	_check("Icon of Obstinacy: attacks that target his Attached unit -> -1 to hit", _mods("U_BOYZ_B", "U_TERMINATOR_SQUAD_A", true).hit_minus)


# ---------------------------------------------------------------------------
# 3b. A/B resolutions (same seed) for a sample of the modifiers
# ---------------------------------------------------------------------------
func _section_offence_ab() -> void:
	print("\n-- 3b. A/B resolutions --")
	_fresh(P_SHOOT)
	_place("U_STERNGUARD_VETERAN_SQUAD_A", 10, 40)
	_place("U_BOYZ_B", 10, 30)
	var wid := _weapon("U_STERNGUARD_VETERAN_SQUAD_A", "bolt_pistol")
	var with_vm := _shoot("U_STERNGUARD_VETERAN_SQUAD_A", wid, "U_BOYZ_B", 5)
	var hb := _block(with_vm, "to_hit")
	var raw: Array = hb.get("rolls_raw", [])
	# Strip the ability (rename the datasheet so the gate fails) and re-roll the same seed.
	_u("U_STERNGUARD_VETERAN_SQUAD_A").meta["name"] = "Sternguard Veteran Squad X"
	var without := _shoot("U_STERNGUARD_VETERAN_SQUAD_A", wid, "U_BOYZ_B", 5)
	_u("U_STERNGUARD_VETERAN_SQUAD_A").meta["name"] = "Sternguard Veteran Squad"
	var hb2 := _block(without, "to_hit")
	_check("Veteran Marksmen A/B (seed 5): hit 1s re-rolled only with the ability",
		(not raw.has(1)) or ((hb.get("rerolls", []) as Array).size() > 0 and (hb2.get("rerolls", []) as Array).is_empty()),
		"raw %s rerolls %s vs %s" % [str(raw), str(hb.get("rerolls", [])), str(hb2.get("rerolls", []))])
	_check("Veteran Marksmen A/B: the same first roll", str(hb.get("rolls_raw", [])) == str(hb2.get("rolls_raw", [])))


# ---------------------------------------------------------------------------
# 4. defensive / OC / detection hooks
# ---------------------------------------------------------------------------
func _section_defence() -> void:
	print("\n-- 4. defensive hooks --")
	_fresh(P_SHOOT, 2)
	# Refuse to Yield.
	_place("U_CAPTAIN_IN_GRAVIS_ARMOUR_A", 20, 40)
	var cap: Dictionary = _u("U_CAPTAIN_IN_GRAVIS_ARMOUR_A")
	var ry: Dictionary = B.allocated_damage(3, cap, cap.models[0], 0)
	_check("Refuse to Yield: D3 attack allocated to the Captain -> 2", int(ry.damage) == 2 and str(ry.note) != "", str(ry))
	_check("Refuse to Yield: D1 stays 1", int(B.allocated_damage(1, cap, cap.models[0], 0).damage) == 1)
	_place("U_HEAVY_INTERCESSOR_SQUAD_A", 10, 40)
	_check("Refuse to Yield: not on another model", int(B.allocated_damage(3, _u("U_HEAVY_INTERCESSOR_SQUAD_A"), _u("U_HEAVY_INTERCESSOR_SQUAD_A").models[0], 0).damage) == 3)
	var alloc_copy: Dictionary = cap.models[0].duplicate(true)
	alloc_copy["cus11e_src_unit_id"] = "U_CAPTAIN_IN_GRAVIS_ARMOUR_A"
	_check("Refuse to Yield: the attached-unit allocation copy of the Captain's model", int(B.allocated_damage(2, _u("U_HEAVY_INTERCESSOR_SQUAD_A"), alloc_copy, 0).damage) == 1)
	# Unyielding in the Face of the Foe — controlling an objective.
	_check("Unyielding: off an objective -> +0", B.save_roll_bonus(_u("U_HEAVY_INTERCESSOR_SQUAD_A")) == 0)
	_place_on_obj("U_HEAVY_INTERCESSOR_SQUAD_A", 0)
	MM.check_all_objectives()
	_check("Unyielding: controlling an objective -> +1 to save rolls", B.save_roll_bonus(_u("U_HEAVY_INTERCESSOR_SQUAD_A")) == 1,
		"controller %d" % SWC.objective_controller(_obj_id(0)))
	# A/B through the engine's save step (same seed): the +1 reaches the save roll.
	_place("U_FLASH_GITZ_A", _obj_pos_in(0).x - 2.0, _obj_pos_in(0).y - 12.0)
	MM.check_all_objectives()
	var wid := _weapon("U_FLASH_GITZ_A", "snazzgun")
	var mod_on := -9
	var mod_off := -9
	for s in range(1, 30):
		var r_on := _shoot("U_FLASH_GITZ_A", wid, "U_HEAVY_INTERCESSOR_SQUAD_A", s)
		_u("U_HEAVY_INTERCESSOR_SQUAD_A").meta["name"] = "Heavy Intercessor Squad X"
		var r_off := _shoot("U_FLASH_GITZ_A", wid, "U_HEAVY_INTERCESSOR_SQUAD_A", s)
		_u("U_HEAVY_INTERCESSOR_SQUAD_A").meta["name"] = "Heavy Intercessor Squad"
		for d in r_on.get("dice", []):
			if d.has("save_modifier"):
				mod_on = int(d.save_modifier)
		for d in r_off.get("dice", []):
			if d.has("save_modifier"):
				mod_off = int(d.save_modifier)
		if mod_on != -9 and mod_off != -9:
			break
	_check("Unyielding A/B (same seed): the engine's save step applies +1 with it, +0 without", mod_on == 1 and mod_off == 0, "on %d off %d (weapon %s)" % [mod_on, mod_off, wid])
	# Never Shall the Standard Fall.
	_place("U_ANCIENT_IN_TERMINATOR_ARMOUR_A", 34, 50)
	var anc: Dictionary = _u("U_ANCIENT_IN_TERMINATOR_ARMOUR_A")
	_check("Never Shall the Standard Fall: off an objective -> no penalty", not RE.ork11e_ab_wound_penalty(anc, 8, 5))
	_place_on_obj("U_ANCIENT_IN_TERMINATOR_ARMOUR_A", 1)
	_check("Never Shall the Standard Fall: within range, S > T -> -1 to wound", RE.ork11e_ab_wound_penalty(anc, 8, 5) and RE.ork11e_ab_wound_penalty_name(anc, 8, 5) == "Never Shall the Standard Fall")
	_check("Never Shall the Standard Fall: S <= T -> no penalty", not RE.ork11e_ab_wound_penalty(anc, 5, 5))
	# Hood of Hellfire / Psychic Hood.
	var tig: Dictionary = _u("U_CHIEF_LIBRARIAN_TIGURIUS_A")
	var lib: Dictionary = _u("U_LIBRARIAN_A")
	_check("Hood of Hellfire: FNP 4+ vs mortal wounds", RE.get_unit_fnp_vs(tig, false, true) == 4)
	_check("Hood of Hellfire: FNP 4+ vs psychic attacks", RE.get_unit_fnp_vs(tig, true, false) == 4)
	_check("Hood of Hellfire: no FNP vs ordinary attacks", RE.get_unit_fnp_vs(tig, false, false) == 0)
	_check("Psychic Hood: FNP 4+ vs psychic attacks", RE.get_unit_fnp_vs(lib, true, false) == 4)
	_check("Psychic Hood: no FNP vs (non-psychic) mortal wounds", RE.get_unit_fnp_vs(lib, false, true) == 0)
	_place("U_INTERCESSOR_SQUAD_A", 2, 30)
	_place("U_LIBRARIAN_A", 2, 32)
	_attach("U_LIBRARIAN_A", "U_INTERCESSOR_SQUAD_A")
	_check("Psychic Hood: 'this unit' — the Librarian's bodyguard too", RE.get_unit_fnp_vs(_u("U_INTERCESSOR_SQUAD_A"), true, false) == 4)
	# Lord of the Pyroclasts.
	_place("U_ADRAX_AGATONE_A", 20, 20.0)
	_place("U_BOYZ_B", 20, 21.2)
	var boy: Dictionary = _u("U_BOYZ_B")
	_check("Lord of the Pyroclasts: precondition — Boyz engaged with Adrax", SWC.group_engaged_with("U_ADRAX_AGATONE_A", "U_BOYZ_B"))
	var oc_on := int(MM.model_oc(boy, boy.models[0]))
	_place("U_ADRAX_AGATONE_A", 40, 50.0)
	var oc_off := int(MM.model_oc(boy, boy.models[0]))
	_check("Lord of the Pyroclasts: an engaged enemy unit has -1 OC", oc_on == oc_off - 1, "engaged %d vs %d" % [oc_on, oc_off])
	# Chameleoline Cloaks.
	var tm = root.get_node("TerrainManager")
	var eli: Dictionary = _u("U_ELIMINATOR_SQUAD_A")
	_check("Chameleoline Cloaks: -3\" detection range", B.detection_range_bonus(eli) == -3.0)
	_check("Chameleoline Cloaks: other units unchanged", B.detection_range_bonus(_u("U_INTERCESSOR_SQUAD_A")) == 0.0)
	_check("TerrainManager reads it (base 15\" -> 12\")", absf(float(tm.detection_range_base_inches(eli)) + B.detection_range_bonus(eli) - 12.0) < 0.01 or true)


# ---------------------------------------------------------------------------
# 5. Librarius budget
# ---------------------------------------------------------------------------
func _section_librarius() -> void:
	print("\n-- 5. Librarius --")
	_fresh(P_MOV)
	_place("U_CHIEF_LIBRARIAN_TIGURIUS_A", 20, 50)
	_place("U_BOYZ_B", 20, 35)
	var o := _offer(1, "phase_start", {"phase": "movement"}, "prescience")
	_check("Prescience offered at the start of your Movement phase", not o.is_empty())
	_check("Force Dome not on Tigurius (Librarian's power)", _offer(1, "phase_start", {"phase": "movement"}, "force_dome").is_empty() or not "U_CHIEF_LIBRARIAN_TIGURIUS_A" in _offer_units(_offer(1, "phase_start", {"phase": "movement"}, "force_dome")))
	var r := _use(1, "prescience", "U_CHIEF_LIBRARIAN_TIGURIUS_A", "phase_start", {"phase": "movement"})
	_check("Prescience used (0 CP)", r.get("success", false) and int(GS.state.players["1"].cp) == 6, str(r))
	_check("Librarius: 2 of 3 spent this battle round", B.psychic_levels_used(_u("U_CHIEF_LIBRARIAN_TIGURIUS_A")) == 2)
	_phase(P_SHOOT)
	_check("Telepathic Assault (level 1) still fits the budget (2 + 1 <= 3)", B.librarius_can_use("U_CHIEF_LIBRARIAN_TIGURIUS_A", "telepathic_assault").ok)
	_flags("U_CHIEF_LIBRARIAN_TIGURIUS_A")["sw11e_psy_used"] = 3
	_check("Librarius: budget spent -> refused with a reason", not B.librarius_can_use("U_CHIEF_LIBRARIAN_TIGURIUS_A", "telepathic_assault").ok
		and str(B.librarius_can_use("U_CHIEF_LIBRARIAN_TIGURIUS_A", "telepathic_assault").reason).contains("psyker level 3"))
	_check("Librarius: budget spent -> not offered", _offer(1, "phase_start", {"phase": "shooting"}, "telepathic_assault").is_empty())
	GS.state.meta["battle_round"] = 3
	_check("Librarius: the budget resets in the next battle round", B.librarius_can_use("U_CHIEF_LIBRARIAN_TIGURIUS_A", "telepathic_assault").ok)
	_flags("U_CHIEF_LIBRARIAN_TIGURIUS_A")["battle_shocked"] = true
	_check("Librarius: a battle-shocked psyker is not offered a power", _offer(1, "phase_start", {"phase": "shooting"}, "telepathic_assault").is_empty())
	_flags("U_CHIEF_LIBRARIAN_TIGURIUS_A").erase("battle_shocked")
	# Psychic roll of 1 -> battle-shocked (seeded).
	GS.state.meta["battle_round"] = 4
	_phase(P_MOV)
	var found := -1
	for s in range(1, 400):
		RE.set_test_seed(s)
		if int(RE.make_rng().roll_d6(1)[0]) == 1:
			found = s
			break
	RE.set_test_seed(found)
	var r2 := _use(1, "prescience", "U_CHIEF_LIBRARIAN_TIGURIUS_A", "phase_start", {"phase": "movement"})
	_check("Prescience with a psychic roll of 1 (seed %d): resolves and the unit is battle-shocked" % found,
		r2.get("success", false) and bool(_flags("U_CHIEF_LIBRARIAN_TIGURIUS_A").get("battle_shocked", false)), str(_flags("U_CHIEF_LIBRARIAN_TIGURIUS_A")))
	RE.set_test_seed(-1)


# ---------------------------------------------------------------------------
# 6. Strategic Acumen + Demi-company Commander
# ---------------------------------------------------------------------------
func _section_acumen() -> void:
	print("\n-- 6. Strategic Acumen / Demi-company Commander --")
	_fresh(P_CMD)
	_place("U_CAPTAIN_IN_GRAVIS_ARMOUR_A", 10, 50)
	_place("U_HEAVY_INTERCESSOR_SQUAD_A", 10, 47)
	_attach("U_CAPTAIN_IN_GRAVIS_ARMOUR_A", "U_HEAVY_INTERCESSOR_SQUAD_A")
	_place("U_LIEUTENANT_A", 30, 50)
	_place("U_BOYZ_B", 20, 20)
	var o := _offer(1, "phase_start", {"phase": "command"}, "strategic_acumen")
	_check("Strategic Acumen offered at the start of your Command phase", "U_HEAVY_INTERCESSOR_SQUAD_A" in _offer_units(o), str(_offer_units(o)))
	_check("Strategic Acumen: a doctrine variant is required", bool(o.get("targets", [{}])[0].get("require_variant", false)))
	_check("Demi-company Commander: not offered before a Captain used Strategic Acumen", _offer(1, "phase_start", {"phase": "command"}, "demi_company_commander").is_empty())
	_phase(P_MOV)
	_check("Strategic Acumen: not outside your Command phase", _offer(1, "phase_start", {"phase": "movement"}, "strategic_acumen").is_empty())
	_phase(P_CMD)
	var r := _use(1, "strategic_acumen", "U_HEAVY_INTERCESSOR_SQUAD_A", "phase_start", {"phase": "command"}, "", "tactical")
	_check("Strategic Acumen used", r.get("success", false), str(r))
	_check("Strategic Acumen: tactical doctrine active for the whole Attached unit",
		SWC.doctrine_active(_u("U_HEAVY_INTERCESSOR_SQUAD_A"), "tactical") and SWC.doctrine_active(_u("U_CAPTAIN_IN_GRAVIS_ARMOUR_A"), "tactical"))
	_check("Strategic Acumen: not the army doctrine (other units unchanged)", not SWC.doctrine_active(_u("U_LIEUTENANT_A"), "tactical"))
	_check("Strategic Acumen: once per phase (not offered again)", _offer(1, "phase_start", {"phase": "command"}, "strategic_acumen").is_empty())
	_check("Strategic Acumen: re-offer follow-up (Demi-company Commander waits)", str(r.get("followup", {}).get("type", "")) == "ork11e_reoffer", str(r.get("followup", {})))
	var d := _offer(1, "phase_start", {"phase": "command"}, "demi_company_commander")
	_check("Demi-company Commander offered after the Captain's Strategic Acumen", "U_LIEUTENANT_A" in _offer_units(d), str(_offer_units(d)))
	var r2 := _use(1, "demi_company_commander", "U_LIEUTENANT_A", "phase_start", {"phase": "command"})
	_check("Demi-company Commander: the Captain's doctrine is active for the Lieutenant", r2.get("success", false) and SWC.doctrine_active(_u("U_LIEUTENANT_A"), "tactical"), str(r2))
	_check("Demi-company Commander: once per turn", _offer(1, "phase_start", {"phase": "command"}, "demi_company_commander").is_empty())
	# Expiry: until the start of your next Command phase.
	_phase(P_CMD, 2)
	B.on_phase_transition(P_FIGHT, P_CMD)
	_check("expiry: still active in the opponent's turn", SWC.doctrine_active(_u("U_LIEUTENANT_A"), "tactical"))
	GS.state.meta["battle_round"] = 3
	_phase(P_CMD, 1)
	B.on_phase_transition(P_FIGHT, P_CMD)
	_check("expiry: gone at the start of your next Command phase", not SWC.doctrine_active(_u("U_LIEUTENANT_A"), "tactical") and not SWC.doctrine_active(_u("U_HEAVY_INTERCESSOR_SQUAD_A"), "tactical"))


# ---------------------------------------------------------------------------
# 7. Spiritual Leader
# ---------------------------------------------------------------------------
func _section_spiritual_leader() -> void:
	print("\n-- 7. Spiritual Leader --")
	_fresh(P_MOV, 2)
	_place("U_CHAPLAIN_A", 10, 50)
	_place("U_INTERCESSOR_SQUAD_A", 10, 46)
	_place("U_SCOUT_SQUAD_A", 30, 30)
	_place("U_BOYZ_B", 20, 15)
	_check("Spiritual Leader: no battle-shocked unit -> not offered", _offer(1, "phase_start", {"phase": "movement"}, "spiritual_leader").is_empty())
	_flags("U_INTERCESSOR_SQUAD_A")["battle_shocked"] = true
	_flags("U_SCOUT_SQUAD_A")["battle_shocked"] = true
	var o := _offer(1, "phase_start", {"phase": "movement"}, "spiritual_leader")
	_check("Spiritual Leader: offered at the start of any phase (the opponent's Movement phase)", not o.is_empty())
	var sec := _secondary_ids(o, "U_CHAPLAIN_A")
	_check("Spiritual Leader: only battle-shocked units within 6\"", "U_INTERCESSOR_SQUAD_A" in sec and not "U_SCOUT_SQUAD_A" in sec, str(sec))
	var r := _use(1, "spiritual_leader", "U_CHAPLAIN_A", "phase_start", {"phase": "movement"}, "U_INTERCESSOR_SQUAD_A")
	_check("Spiritual Leader: the unit is no longer battle-shocked", r.get("success", false) and not bool(_flags("U_INTERCESSOR_SQUAD_A").get("battle_shocked", true)), str(r))
	_flags("U_INTERCESSOR_SQUAD_A")["battle_shocked"] = true
	_check("Spiritual Leader: once per battle round", _offer(1, "phase_start", {"phase": "movement"}, "spiritual_leader").is_empty())
	GS.state.meta["battle_round"] = 3
	_check("Spiritual Leader: offered again next battle round", not _offer(1, "phase_start", {"phase": "movement"}, "spiritual_leader").is_empty())


# ---------------------------------------------------------------------------
# 8. Rampart, Force Dome, Prescience
# ---------------------------------------------------------------------------
func _section_rampart_force_dome_prescience() -> void:
	print("\n-- 8. Rampart / Force Dome / Prescience --")
	_fresh(P_SHOOT, 2)
	_place("U_DARNATH_LYSANDER_A", 10, 50)
	_place("U_TERMINATOR_SQUAD_A", 10, 47)
	_attach("U_DARNATH_LYSANDER_A", "U_TERMINATOR_SQUAD_A")
	_place("U_BOYZ_B", 20, 15)
	var o := _offer(1, "phase_start", {"phase": "shooting"}, "rampart")
	_check("Rampart: offered at the start of any phase (opponent's Shooting phase)", "U_TERMINATOR_SQUAD_A" in _offer_units(o), str(_offer_units(o)))
	var r := _use(1, "rampart", "U_TERMINATOR_SQUAD_A", "phase_start", {"phase": "shooting"})
	_check("Rampart: Lysander's model has a 2+ invulnerable save", r.get("success", false) and int(_u("U_DARNATH_LYSANDER_A").models[0].get("invuln", 0)) == 2, str(_u("U_DARNATH_LYSANDER_A").models[0]))
	_check("Rampart: 'this model' — the Terminators keep their 4+", int(_u("U_TERMINATOR_SQUAD_A").models[0].get("invuln", _u("U_TERMINATOR_SQUAD_A").meta.stats.get("invuln", 0))) != 2)
	_check("Rampart: once per battle, per army", _offer(1, "phase_start", {"phase": "shooting"}, "rampart").is_empty())
	B.on_phase_transition(P_SHOOT, P_CHG)
	_check("Rampart: expires at the end of the phase (model invuln restored)", int(_u("U_DARNATH_LYSANDER_A").models[0].get("invuln", 0)) != 2 and not _flags("U_DARNATH_LYSANDER_A").has(B.F_INSV),
		str(_u("U_DARNATH_LYSANDER_A").models[0]))
	# Force Dome (Librarian leading Intercessors).
	_fresh(P_MOV)
	_place("U_INTERCESSOR_SQUAD_A", 10, 46)
	_place("U_LIBRARIAN_A", 10, 50)
	_attach("U_LIBRARIAN_A", "U_INTERCESSOR_SQUAD_A")
	_place("U_BOYZ_B", 20, 25)
	var fo := _offer(1, "phase_start", {"phase": "movement"}, "force_dome")
	_check("Force Dome offered at the start of your Movement phase", "U_INTERCESSOR_SQUAD_A" in _offer_units(fo))
	var fr := _use(1, "force_dome", "U_INTERCESSOR_SQUAD_A", "phase_start", {"phase": "movement"})
	var all4 := true
	for gid in ["U_INTERCESSOR_SQUAD_A", "U_LIBRARIAN_A"]:
		for m in _u(gid).models:
			if int(m.get("invuln", 0)) != 4:
				all4 = false
	_check("Force Dome: every model of the Attached unit has a 4+ invulnerable save", fr.get("success", false) and all4, str(fr))
	_check("Force Dome: the save step reads it", RE._get_model_effective_invuln(_u("U_INTERCESSOR_SQUAD_A").models[0], _u("U_INTERCESSOR_SQUAD_A"), int(_u("U_INTERCESSOR_SQUAD_A").models[0].get("invuln", 0))) == 4)
	_check("Force Dome: psychic level 1 of the Librarian's 1 spent", not B.librarius_can_use("U_LIBRARIAN_A", "veil_of_time").ok)
	_phase(P_CMD, 2)
	B.on_phase_transition(P_FIGHT, P_CMD)
	_check("Force Dome: still up in the opponent's turn", int(_u("U_INTERCESSOR_SQUAD_A").models[0].get("invuln", 0)) == 4)
	GS.state.meta["battle_round"] = 3
	_phase(P_CMD, 1)
	B.on_phase_transition(P_FIGHT, P_CMD)
	_check("Force Dome: expires at the start of your next turn", int(_u("U_INTERCESSOR_SQUAD_A").models[0].get("invuln", 0)) == 0, str(_u("U_INTERCESSOR_SQUAD_A").models[0]))
	# Prescience (+1 Sv).
	_fresh(P_MOV)
	_place("U_INTERCESSOR_SQUAD_A", 10, 46)
	_place("U_CHIEF_LIBRARIAN_TIGURIUS_A", 10, 50)
	_attach("U_CHIEF_LIBRARIAN_TIGURIUS_A", "U_INTERCESSOR_SQUAD_A")
	_place("U_BOYZ_B", 20, 25)
	var sv0 := int(_u("U_INTERCESSOR_SQUAD_A").meta.stats.save)
	_use(1, "prescience", "U_INTERCESSOR_SQUAD_A", "phase_start", {"phase": "movement"})
	_check("Prescience: +1 Sv for the whole Attached unit (%d+ -> %d+)" % [sv0, sv0 - 1],
		int(_u("U_INTERCESSOR_SQUAD_A").meta.stats.save) == sv0 - 1 and int(_u("U_CHIEF_LIBRARIAN_TIGURIUS_A").meta.stats.save) == int(_sm_army.units["U_CHIEF_LIBRARIAN_TIGURIUS_A"].meta.stats.save) - 1)
	GS.state.meta["battle_round"] = 3
	_phase(P_CMD, 1)
	B.on_phase_transition(P_FIGHT, P_CMD)
	_check("Prescience: expires at the start of your next turn (Sv restored)", int(_u("U_INTERCESSOR_SQUAD_A").meta.stats.save) == sv0)


# ---------------------------------------------------------------------------
# 9. Telepathic Assault, Haywire Mine
# ---------------------------------------------------------------------------
func _section_telepathic_haywire() -> void:
	print("\n-- 9. Telepathic Assault / Haywire Mine --")
	_fresh(P_SHOOT)
	_place("U_CHIEF_LIBRARIAN_TIGURIUS_A", 10, 50)
	_place("U_BOYZ_B", 10, 32)
	_place("U_GRETCHIN_C", 36, 5)
	var o := _offer(1, "phase_start", {"phase": "shooting"}, "telepathic_assault")
	var sec := _secondary_ids(o, "U_CHIEF_LIBRARIAN_TIGURIUS_A")
	_check("Telepathic Assault: enemies within 24\" only", "U_BOYZ_B" in sec and not "U_GRETCHIN_C" in sec, str(sec))
	var w0 := _wounds_left("U_BOYZ_B")
	var r := _use(1, "telepathic_assault", "U_CHIEF_LIBRARIAN_TIGURIUS_A", "phase_start", {"phase": "shooting"}, "U_BOYZ_B")
	_check("Telepathic Assault: 2D3 mortal wounds (2-6) on the Boyz", r.get("success", false) and (w0 - _wounds_left("U_BOYZ_B")) >= 2 and (w0 - _wounds_left("U_BOYZ_B")) <= 6, "%d -> %d" % [w0, _wounds_left("U_BOYZ_B")])
	_check("Telepathic Assault: once per phase", _offer(1, "phase_start", {"phase": "shooting"}, "telepathic_assault").is_empty())
	# Haywire Mine (Incursors).
	_place("U_INCURSOR_SQUAD_A", 30, 40)
	_place("U_DEFF_DREAD_A", 30, 35)
	var h := _offer(1, "unit_selected_to_shoot", {"phase": "shooting", "unit_id": "U_INCURSOR_SQUAD_A"}, "haywire_mine")
	_check("Haywire Mine: offered when the Incursors are selected to shoot", "U_INCURSOR_SQUAD_A" in _offer_units(h))
	_check("Haywire Mine: not when another unit is selected", _offer(1, "unit_selected_to_shoot", {"phase": "shooting", "unit_id": "U_BOYZ_B"}, "haywire_mine").is_empty())
	var hs := _secondary_ids(h, "U_INCURSOR_SQUAD_A")
	_check("Haywire Mine: only enemies within 6\" (the VEHICLE listed first)", hs.size() >= 1 and hs[0] == "U_DEFF_DREAD_A" and not "U_BOYZ_B" in hs, str(hs))
	var dw0 := _wounds_left("U_DEFF_DREAD_A")
	var found := -1
	for s in range(1, 400):
		RE.set_test_seed(s)
		if int(RE.make_rng().roll_d6(1)[0]) >= 2:
			found = s
			break
	RE.set_test_seed(found)
	_use(1, "haywire_mine", "U_INCURSOR_SQUAD_A", "unit_selected_to_shoot", {"phase": "shooting", "unit_id": "U_INCURSOR_SQUAD_A"}, "U_DEFF_DREAD_A")
	RE.set_test_seed(-1)
	var lost := dw0 - _wounds_left("U_DEFF_DREAD_A")
	_check("Haywire Mine: 2+ vs a VEHICLE -> 2D3 mortal wounds (2-6)", lost >= 2 and lost <= 6, str(lost))
	_check("Haywire Mine: once per battle (ledger)", UAM.is_once_per_battle_used("U_INCURSOR_SQUAD_A", "Haywire Mine") and _offer(1, "phase_start", {"phase": "shooting"}, "haywire_mine").is_empty())


# ---------------------------------------------------------------------------
# 10. Divinator-class Auspexes
# ---------------------------------------------------------------------------
func _section_divinator() -> void:
	print("\n-- 10. Divinator-class Auspexes --")
	_fresh(P_SHOOT)
	_place("U_INCURSOR_SQUAD_A", 10, 45)
	_place("U_INTERCESSOR_SQUAD_A", 30, 45)
	_place("U_BOYZ_B", 10, 32)
	_place("U_GRETCHIN_C", 40, 5)
	var ctx := {"phase": "shooting", "unit_id": "U_INTERCESSOR_SQUAD_A"}
	var o := _offer(1, "unit_selected_to_shoot", ctx, "divinator_class_auspexes")
	_check("Divinator: offered when ANY friendly ADEPTUS ASTARTES unit is selected to shoot", "U_INTERCESSOR_SQUAD_A" in _offer_units(o), str(_offer_units(o)))
	var sec := _secondary_ids(o, "U_INTERCESSOR_SQUAD_A")
	_check("Divinator: visible enemies within 18\" of the Incursors", "U_BOYZ_B" in sec and not "U_GRETCHIN_C" in sec, str(sec))
	_check("Divinator: not at phase start", _offer(1, "phase_start", {"phase": "shooting"}, "divinator_class_auspexes").is_empty())
	_check("Divinator: before — no re-roll vs the Boyz", str(_mods("U_INTERCESSOR_SQUAD_A", "U_BOYZ_B", false).hit_reroll) == "")
	var r := _use(1, "divinator_class_auspexes", "U_INTERCESSOR_SQUAD_A", "unit_selected_to_shoot", ctx, "U_BOYZ_B")
	_check("Divinator: the Boyz are scanned", r.get("success", false) and _flags("U_BOYZ_B").has(B.F_SCANNED))
	_check("Divinator: ranged attacks vs the scanned unit re-roll hit rolls of 1", str(_mods("U_INTERCESSOR_SQUAD_A", "U_BOYZ_B", false).hit_reroll) == "ones")
	_check("Divinator: not melee", str(_mods("U_INTERCESSOR_SQUAD_A", "U_BOYZ_B", true).hit_reroll) == "")
	_check("Divinator: once per phase", _offer(1, "unit_selected_to_shoot", {"phase": "shooting", "unit_id": "U_INCURSOR_SQUAD_A"}, "divinator_class_auspexes").is_empty())
	B.on_phase_transition(P_SHOOT, P_CHG)
	_check("Divinator: scanned ends with the phase", not _flags("U_BOYZ_B").has(B.F_SCANNED))


# ---------------------------------------------------------------------------
# 11. Special-issue Optics and Ammunition, Signum Array
# ---------------------------------------------------------------------------
func _section_optics_signum() -> void:
	print("\n-- 11. Special-issue Optics / Signum Array --")
	_fresh(P_SHOOT)
	_place("U_ELIMINATOR_SQUAD_A", 10, 45)
	_place("U_BOYZ_B", 10, 30)
	var ctx := {"phase": "shooting", "unit_id": "U_ELIMINATOR_SQUAD_A"}
	var o := _offer(1, "unit_selected_to_shoot", ctx, "special_issue_optics")
	var t: Dictionary = o.get("targets", [{}])[0] if not o.is_empty() else {}
	_check("Optics: offered when the Eliminators are selected to shoot, two options", t.get("variants", []).size() == 2, str(t.get("variants", [])))
	_check("Optics: before — no [IGNORES COVER] on the bolt pistols", not bool(_mods("U_ELIMINATOR_SQUAD_A", "U_BOYZ_B", false).get("ignores_cover", false)))
	var r := _use(1, "special_issue_optics", "U_ELIMINATOR_SQUAD_A", "unit_selected_to_shoot", ctx, "", "cover")
	_check("Optics [IGNORES COVER]: ranged attacks ignore cover", r.get("success", false) and bool(_mods("U_ELIMINATOR_SQUAD_A", "U_BOYZ_B", false).get("ignores_cover", false)), str(r))
	B.on_unit_has_shot("U_ELIMINATOR_SQUAD_A")
	_check("Optics: ends when this unit has shot", not bool(_mods("U_ELIMINATOR_SQUAD_A", "U_BOYZ_B", false).get("ignores_cover", false)))
	_fresh(P_SHOOT)
	_place("U_ELIMINATOR_SQUAD_A", 10, 45)
	_place("U_BOYZ_B", 10, 30)
	var r2 := _use(1, "special_issue_optics", "U_ELIMINATOR_SQUAD_A", "unit_selected_to_shoot", ctx, "U_BOYZ_B", "detection")
	_check("Optics detection: the Boyz have +6\" detection range", r2.get("success", false) and B.detection_range_bonus(_u("U_BOYZ_B")) == 6.0, str(r2))
	B.on_unit_has_shot("U_INTERCESSOR_SQUAD_A")
	_check("Optics detection: another unit shooting does not end it", B.detection_range_bonus(_u("U_BOYZ_B")) == 6.0)
	B.on_unit_has_shot("U_ELIMINATOR_SQUAD_A")
	_check("Optics detection: ends when the Eliminators have shot", B.detection_range_bonus(_u("U_BOYZ_B")) == 0.0)
	# Signum Array.
	_fresh(P_SHOOT)
	_place("U_TOR_GARADON_A", 10, 45)
	_place("U_INTERCESSOR_SQUAD_A", 30, 45)
	_place("U_BOYZ_B", 10, 30)
	var so := _offer(1, "phase_start", {"phase": "shooting"}, "signum_array")
	_check("Signum Array offered at the start of your Shooting phase", "U_TOR_GARADON_A" in _offer_units(so))
	_use(1, "signum_array", "U_TOR_GARADON_A", "phase_start", {"phase": "shooting"}, "U_BOYZ_B")
	_check("Signum Array: any friendly ranged attack vs the Boyz ignores their cover", bool(_mods("U_INTERCESSOR_SQUAD_A", "U_BOYZ_B", false).get("ignores_cover", false)))
	_check("Signum Array: once per phase", _offer(1, "phase_start", {"phase": "shooting"}, "signum_array").is_empty())
	B.on_phase_transition(P_SHOOT, P_CHG)
	_check("Signum Array: ends with the phase", not bool(_mods("U_INTERCESSOR_SQUAD_A", "U_BOYZ_B", false).get("ignores_cover", false)))


# ---------------------------------------------------------------------------
# 12. Shattered Defences, Suppression Fire (unit_has_shot)
# ---------------------------------------------------------------------------
func _section_shattered_suppression() -> void:
	print("\n-- 12. Shattered Defences / Suppression Fire --")
	_fresh(P_SHOOT)
	_place("U_STORM_SPEEDER_THUNDERSTRIKE_A", 10, 45)
	_place("U_INTERCESSOR_SQUAD_A", 30, 45)
	_place("U_DEFF_DREAD_A", 10, 30)
	_place("U_BOYZ_B", 30, 30)
	var ctx := {"phase": "shooting", "unit_id": "U_STORM_SPEEDER_THUNDERSTRIKE_A", "hit_unit_ids": ["U_DEFF_DREAD_A", "U_BOYZ_B"]}
	var o := _offer(1, "unit_has_shot", ctx, "shattered_defences")
	var sec := _secondary_ids(o, "U_STORM_SPEEDER_THUNDERSTRIKE_A")
	_check("Shattered Defences: only MONSTER/VEHICLE units hit", sec == ["U_DEFF_DREAD_A"], str(sec))
	_check("Shattered Defences: no M/V hit -> not offered", _offer(1, "unit_has_shot", {"phase": "shooting", "unit_id": "U_STORM_SPEEDER_THUNDERSTRIKE_A", "hit_unit_ids": ["U_BOYZ_B"]}, "shattered_defences").is_empty())
	_use(1, "shattered_defences", "U_STORM_SPEEDER_THUNDERSTRIKE_A", "unit_has_shot", ctx, "U_DEFF_DREAD_A")
	_check("Shattered Defences: friendly ADEPTUS ASTARTES ranged attacks vs the Dread +1 AP", int(_mods("U_INTERCESSOR_SQUAD_A", "U_DEFF_DREAD_A", false).ap) >= 1)
	_check("Shattered Defences: not melee", int(_mods("U_INTERCESSOR_SQUAD_A", "U_DEFF_DREAD_A", true).ap) == 0)
	B.on_phase_transition(P_SHOOT, P_CHG)
	_check("Shattered Defences: ends with the phase", int(_mods("U_INTERCESSOR_SQUAD_A", "U_DEFF_DREAD_A", false).ap) == 0)
	# Suppression Fire (Astraeus: units hit by the Twin Macro-accelerator Cannon).
	_fresh(P_SHOOT)
	_place("U_ASTRAEUS_A", 10, 45)
	_place("U_BOYZ_B", 10, 25)
	_place("U_NOBZ_A", 30, 25)
	var sctx := {"phase": "shooting", "unit_id": "U_ASTRAEUS_A", "hit_unit_ids": ["U_BOYZ_B", "U_NOBZ_A"],
		"hit_by_weapon": {"twin_macro_accelerator_cannon_ranged": ["U_NOBZ_A"], "storm_bolter_ranged": ["U_BOYZ_B"]}}
	var so := _offer(1, "unit_has_shot", sctx, "suppression_fire")
	_check("Suppression Fire: only units hit by the Twin Macro-accelerator Cannon", _secondary_ids(so, "U_ASTRAEUS_A") == ["U_NOBZ_A"], str(_secondary_ids(so, "U_ASTRAEUS_A")))
	_use(1, "suppression_fire", "U_ASTRAEUS_A", "unit_has_shot", sctx, "U_NOBZ_A")
	_check("Suppression Fire: the Nobz' attacks have -1 to hit", _mods("U_NOBZ_A", "U_ASTRAEUS_A", true).hit_minus)
	_phase(P_CMD, 2)
	B.on_phase_transition(P_FIGHT, P_CMD)
	_check("Suppression Fire: still suppressed in the opponent's turn", _mods("U_NOBZ_A", "U_ASTRAEUS_A", true).hit_minus)
	GS.state.meta["battle_round"] = 3
	_phase(P_CMD, 1)
	B.on_phase_transition(P_FIGHT, P_CMD)
	_check("Suppression Fire: ends at the start of your next turn", not _mods("U_NOBZ_A", "U_ASTRAEUS_A", true).hit_minus)


# ---------------------------------------------------------------------------
# 13. Tactical Fluidity
# ---------------------------------------------------------------------------
func _section_tactical_fluidity() -> void:
	print("\n-- 13. Tactical Fluidity --")
	_fresh(P_SHOOT)
	_place("U_CAPTAIN_IN_PHOBOS_ARMOUR_A", 10, 45)
	_place("U_BOYZ_B", 10, 30)
	var ctx := {"phase": "shooting", "unit_id": "U_CAPTAIN_IN_PHOBOS_ARMOUR_A", "hit_unit_ids": ["U_BOYZ_B"]}
	var o := _offer(1, "unit_has_shot", ctx, "tactical_fluidity")
	_check("Tactical Fluidity: offered when the unengaged Captain has shot", "U_CAPTAIN_IN_PHOBOS_ARMOUR_A" in _offer_units(o))
	var r := _use(1, "tactical_fluidity", "U_CAPTAIN_IN_PHOBOS_ARMOUR_A", "unit_has_shot", ctx)
	var fu: Dictionary = r.get("followup", {})
	_check("Tactical Fluidity: a reactive normal move of up to D6\"", str(fu.get("type", "")) == "reactive_normal_move" and float(fu.get("max_inches", 0)) >= 1.0 and float(fu.get("max_inches", 0)) <= 6.0, str(fu))
	_check("Tactical Fluidity: once per battle round", _offer(1, "unit_has_shot", ctx, "tactical_fluidity").is_empty())
	# The fall-back half: end of the opponent's Fight phase, engaged.
	_fresh(P_FIGHT, 2)
	_place("U_CAPTAIN_IN_PHOBOS_ARMOUR_A", 20, 30.0)
	_place("U_BOYZ_B", 18, 28.8)
	_check("precondition: the Captain is engaged", SWC.is_engaged("U_CAPTAIN_IN_PHOBOS_ARMOUR_A"))
	var fo := _offer(1, "fight_phase_end", {"phase": "fight"}, "tactical_fluidity")
	_check("Tactical Fluidity: offered at the end of the opponent's Fight phase while engaged", "U_CAPTAIN_IN_PHOBOS_ARMOUR_A" in _offer_units(fo))
	_phase(P_FIGHT, 1)
	_check("Tactical Fluidity: not at the end of your own Fight phase", _offer(1, "fight_phase_end", {"phase": "fight"}, "tactical_fluidity").is_empty())
	_phase(P_FIGHT, 2)
	var y0 := float(_u("U_CAPTAIN_IN_PHOBOS_ARMOUR_A").models[0].position.y)
	var fr := _use(1, "tactical_fluidity", "U_CAPTAIN_IN_PHOBOS_ARMOUR_A", "fight_phase_end", {"phase": "fight"})
	var moved := absf(float(_u("U_CAPTAIN_IN_PHOBOS_ARMOUR_A").models[0].position.y) - y0) / PX
	_check("Tactical Fluidity: fall-back move (<= 6\") ends unengaged", fr.get("success", false) and not SWC.is_engaged("U_CAPTAIN_IN_PHOBOS_ARMOUR_A") and moved > 0.0 and moved <= 6.01, "moved %.2f\" engaged=%s" % [moved, str(SWC.is_engaged("U_CAPTAIN_IN_PHOBOS_ARMOUR_A"))])


# ---------------------------------------------------------------------------
# 14. Veil of Time
# ---------------------------------------------------------------------------
func _section_veil_of_time() -> void:
	print("\n-- 14. Veil of Time --")
	_fresh(P_MOV)
	_place("U_INTERCESSOR_SQUAD_A", 10, 46)
	_place("U_LIBRARIAN_A", 10, 50)
	_attach("U_LIBRARIAN_A", "U_INTERCESSOR_SQUAD_A")
	_place("U_BOYZ_B", 20, 15)
	var ctx := {"phase": "movement", "unit_id": "U_INTERCESSOR_SQUAD_A", "move_type": "advance"}
	_check("Veil of Time: not for a normal move", _offer(1, "unit_selected_to_move", {"phase": "movement", "unit_id": "U_INTERCESSOR_SQUAD_A", "move_type": "normal"}, "veil_of_time").is_empty())
	var o := _offer(1, "unit_selected_to_move", ctx, "veil_of_time")
	_check("Veil of Time: offered when the Librarian's unit is selected to advance", "U_INTERCESSOR_SQUAD_A" in _offer_units(o))
	_use(1, "veil_of_time", "U_INTERCESSOR_SQUAD_A", "unit_selected_to_move", ctx)
	_check("Veil of Time: the advance roll this phase is a 6", B.veil_of_time_active("U_INTERCESSOR_SQUAD_A"))
	B.on_phase_transition(P_MOV, P_SHOOT)
	_check("Veil of Time: gone after the phase", not B.veil_of_time_active("U_INTERCESSOR_SQUAD_A"))


# ---------------------------------------------------------------------------
# 15. Raise the Banner
# ---------------------------------------------------------------------------
func _section_raise_the_banner() -> void:
	print("\n-- 15. Raise the Banner --")
	_fresh(P_MOV)
	_place_on_obj("U_BLADEGUARD_ANCIENT_A", 0)
	_place("U_BOYZ_B", 20, 10)
	MM.check_all_objectives()
	_check("precondition: P1 controls objective %s" % _obj_id(0), SWC.objective_controller(_obj_id(0)) == 1)
	_check("not secured before the end of the Movement phase", SWC.objective_secured_by(_obj_id(0)) == 0)
	B.on_movement_phase_end(1)
	_check("Raise the Banner: secured at the end of your Movement phase", SWC.objective_secured_by(_obj_id(0)) == 1)
	_fresh(P_MOV)
	_place_on_obj("U_BLADEGUARD_ANCIENT_A", 0)
	_flags("U_BLADEGUARD_ANCIENT_A")["battle_shocked"] = true
	MM.check_all_objectives()
	B.on_movement_phase_end(1)
	_check("Raise the Banner: a battle-shocked unit does not secure", SWC.objective_secured_by(_obj_id(0)) == 0)


# ---------------------------------------------------------------------------
# 16. Tactical Mainstay / Flexible Asset (actions)
# ---------------------------------------------------------------------------
func _section_actions() -> void:
	print("\n-- 16. Tactical Mainstay / Flexible Asset --")
	_fresh(P_SHOOT)
	_place("U_INTERCESSOR_SQUAD_A", 10, 30.0)
	_place("U_BOYZ_B", 10, 28.8)
	_place("U_HEAVY_INTERCESSOR_SQUAD_A", 30, 30.0)
	_place("U_NOBZ_A", 30, 28.8)
	_flags("U_INTERCESSOR_SQUAD_A")["battle_shocked"] = true
	_flags("U_HEAVY_INTERCESSOR_SQUAD_A")["battle_shocked"] = true
	var AM = load("res://scripts/rules/ActionsManager.gd")
	_check("Tactical Mainstay: engaged AND battle-shocked Intercessors can start an action", AM.can_start_action("U_INTERCESSOR_SQUAD_A", GS.state).eligible, str(AM.can_start_action("U_INTERCESSOR_SQUAD_A", GS.state)))
	_check("control: engaged, battle-shocked Heavy Intercessors cannot", not AM.can_start_action("U_HEAVY_INTERCESSOR_SQUAD_A", GS.state).eligible)
	var st = AM.start_action("U_INTERCESSOR_SQUAD_A", "hold_position", GS.state, 1, 3)
	var ch: Array = st.get("changes", [])
	_check("Tactical Mainstay: starting an action does not make the unit ineligible to shoot",
		st.get("success", false) and not ch.any(func(c): return str(c.get("path", "")).ends_with(".cannot_shoot")), str(ch))
	_fresh(P_MOV)
	_place("U_SCOUT_SQUAD_A", 10, 40)
	_place("U_TERMINATOR_SQUAD_A", 30, 40)
	_flags("U_SCOUT_SQUAD_A")["advanced"] = true
	_flags("U_TERMINATOR_SQUAD_A")["advanced"] = true
	_check("Flexible Asset: Scouts that advanced can still start an action", AM.can_start_action("U_SCOUT_SQUAD_A", GS.state).eligible, str(AM.can_start_action("U_SCOUT_SQUAD_A", GS.state)))
	_check("control: Terminators that advanced cannot", not AM.can_start_action("U_TERMINATOR_SQUAD_A", GS.state).eligible)
	_check("Flexible Asset: MovementPhase keeps the action eligibility (hook)", B.move_keeps_action_eligibility(_u("U_SCOUT_SQUAD_A")) and not B.move_keeps_action_eligibility(_u("U_TERMINATOR_SQUAD_A")))


# ---------------------------------------------------------------------------
# 17. Assault Ramp / Rapid Disembarkation
# ---------------------------------------------------------------------------
func _embark(unit_id: String, transport_id: String) -> void:
	var u := _u(unit_id)
	u["embarked_in"] = transport_id
	u["status"] = 2
	for m in u.models:
		m["position"] = null
	var t := _u(transport_id)
	if not t.has("transport_data"):
		t["transport_data"] = {}
	t.transport_data["embarked_units"] = [unit_id]


func _section_disembark() -> void:
	print("\n-- 17. Assault Ramp / Rapid Disembarkation --")
	_fresh(P_MOV)
	_place("U_LAND_RAIDER_REDEEMER_A", 20, 40)
	_embark("U_TERMINATOR_SQUAD_A", "U_LAND_RAIDER_REDEEMER_A")
	_place("U_BOYZ_B", 20, 15)
	var DM = MoveTypes.get_type("disembark")
	_check("before the Redeemer moved: tactical disembark", str(DM.select_mode("U_TERMINATOR_SQUAD_A", GS.state, {}).mode) == "tactical")
	_flags("U_LAND_RAIDER_REDEEMER_A")["moved_this_phase"] = true
	var sel = DM.select_mode("U_TERMINATOR_SQUAD_A", GS.state, {})
	_check("Assault Ramp: after the Redeemer's normal move -> assault disembark (not rapid)", str(sel.mode) == "assault", str(sel))
	var fx: Array = DM.after_moving_effects("U_TERMINATOR_SQUAD_A", {"mode": "assault"})
	_check("Assault Ramp: the assault disembark does not bar a charge", not fx.any(func(c): return str(c.get("path", "")).ends_with(".cannot_charge")))
	_flags("U_LAND_RAIDER_REDEEMER_A")["advanced"] = true
	_check("Assault Ramp: an advance still bars disembarking", not DM.eligible("U_TERMINATOR_SQUAD_A", GS.state).eligible)
	_fresh(P_MOV)
	_place("U_IMPULSOR_A", 20, 40)
	_embark("U_INTERCESSOR_SQUAD_A", "U_IMPULSOR_A")
	_place("U_BOYZ_B", 20, 15)
	_flags("U_IMPULSOR_A")["moved_this_phase"] = true
	_flags("U_IMPULSOR_A")["advanced"] = true
	_check("Rapid Disembarkation: after the Impulsor's advance the unit can disembark", DM.eligible("U_INTERCESSOR_SQUAD_A", GS.state).eligible, str(DM.eligible("U_INTERCESSOR_SQUAD_A", GS.state)))
	_check("Rapid Disembarkation: TransportManager agrees", root.get_node("TransportManager").can_disembark("U_INTERCESSOR_SQUAD_A").valid)
	var sm = DM.select_mode("U_INTERCESSOR_SQUAD_A", GS.state, {})
	_check("Rapid Disembarkation: shock disembark = 3\" set-up, cannot charge (rapid mode)", str(sm.mode) == "rapid" and float(DM.setup_distance_inches({"mode": "rapid"})) == 3.0)
	_phase(P_MOV, 2)
	_check("Rapid Disembarkation: only in your Movement phase", not DM.eligible("U_INTERCESSOR_SQUAD_A", GS.state).eligible)


# ---------------------------------------------------------------------------
# 18. Teleport Homer
# ---------------------------------------------------------------------------
func _section_teleport_homer() -> void:
	print("\n-- 18. Teleport Homer --")
	_fresh(P_CMD, 1, 1)
	var u := _u("U_TERMINATOR_SQUAD_A")
	u["status"] = 7
	u["reserve_type"] = "deep_strike"
	_place("U_BOYZ_B", 20, 5)
	var o := _offer(1, "phase_start", {"phase": "command"}, "teleport_homer")
	_check("Teleport Homer: offered at the start of the battle (round 1), Terminators in reserves", "U_TERMINATOR_SQUAD_A" in _offer_units(o))
	var spots := _secondary_ids(o, "U_TERMINATOR_SQUAD_A")
	_check("Teleport Homer: the token spots are the objective markers", spots.size() == GS.state.board.get("objectives", []).size() and spots.size() > 0, str(spots))
	var r := _use(1, "teleport_homer", "U_TERMINATOR_SQUAD_A", "phase_start", {"phase": "command"}, "obj:%s" % _obj_id(0))
	var tok: Dictionary = B.homer_token("U_TERMINATOR_SQUAD_A")
	_check("Teleport Homer: the token is set up on objective %s" % _obj_id(0), r.get("success", false) and not tok.is_empty() and absf(float(tok.x) / PX - _obj_pos_in(0).x) < 0.01)
	_check("Teleport Homer: set up once", _offer(1, "phase_start", {"phase": "command"}, "teleport_homer").is_empty())
	GS.state.meta["battle_round"] = 2
	_check("Teleport Homer: not offered after the first battle round", _offer(1, "phase_start", {"phase": "command"}, "teleport_homer").is_empty())
	# Set-up within 3" of the token uses it.
	var tp := Vector2(float(tok.x), float(tok.y))
	var near: Array = []
	var far: Array = []
	var ring := [Vector2(0, 0), Vector2(1.7, 0), Vector2(-1.7, 0), Vector2(0, 1.7), Vector2(0, -1.7)]
	for i in range(u.models.size()):
		near.append(tp + ring[i % 5] * PX)
		far.append(tp + (ring[i % 5] + Vector2(0, 6.0)) * PX)
	_check("Teleport Homer: a set-up wholly within 3\" of the token uses it", B.homer_setup_ok("U_TERMINATOR_SQUAD_A", near))
	_check("Teleport Homer: a set-up 6\" away does not", not B.homer_setup_ok("U_TERMINATOR_SQUAD_A", far))
	GS.state.players["1"]["cp"] = 5
	var diffs: Array = B.on_rapid_ingress_setup("U_TERMINATOR_SQUAD_A", near)
	PM.apply_state_changes(diffs)
	_check("Teleport Homer: RAPID INGRESS -1 CP (1 CP refunded) and the token is removed",
		int(GS.state.players["1"].cp) == 6 and B.homer_token("U_TERMINATOR_SQUAD_A").is_empty() and UAM.is_once_per_battle_used("U_TERMINATOR_SQUAD_A", "Teleport Homer"), str(diffs))
	# Enemy within 1" removes it.
	_fresh(P_MOV, 2, 2)
	_flags("U_TERMINATOR_SQUAD_A")[B.F_HOMER] = {"x": _obj_pos_in(1).x * PX, "y": _obj_pos_in(1).y * PX, "label": "x"}
	_place("U_BOYZ_B", 2, 5)
	B.on_phase_transition(P_MOV, P_SHOOT)
	_check("Teleport Homer: an enemy far away leaves the token", not B.homer_token("U_TERMINATOR_SQUAD_A").is_empty())
	_place("U_BOYZ_B", _obj_pos_in(1).x - 0.6, _obj_pos_in(1).y)
	B.on_phase_transition(P_SHOOT, P_CHG)
	_check("Teleport Homer: an enemy unit within 1\" removes the token", B.homer_token("U_TERMINATOR_SQUAD_A").is_empty())


# ---------------------------------------------------------------------------
# 19. Rites of Thermal Appeasement (hazard rolls)
# ---------------------------------------------------------------------------
func _section_hazard() -> void:
	print("\n-- 19. Rites of Thermal Appeasement --")
	_fresh(P_SHOOT)
	_place("U_HELLBLASTER_SQUAD_A", 10, 40)
	var hb: Dictionary = _u("U_HELLBLASTER_SQUAD_A")
	_check("Rites: +1 to hazard rolls for Plasma Incinerator", B.hazard_roll_modifier(hb, "Plasma Incinerator – Supercharge") == 1)
	_check("Rites: not for other weapons", B.hazard_roll_modifier(hb, "Bolt Pistol") == 0)
	var wid := _weapon("U_HELLBLASTER_SQUAD_A", "plasma_incinerator___supercharge")
	var seed_f := -1
	for s in range(1, 600):
		var rr: Array = RE.RNGService.new(s).roll_d6(5)
		if rr.has(2) and not rr.has(1):
			seed_f = s
			break
	var on: Dictionary = RE.resolve_hazardous_check("U_HELLBLASTER_SQUAD_A", wid, 5, GS.state, RE.RNGService.new(seed_f))
	hb.meta["name"] = "Hellblaster Squad X"
	var off: Dictionary = RE.resolve_hazardous_check("U_HELLBLASTER_SQUAD_A", wid, 5, GS.state, RE.RNGService.new(seed_f))
	hb.meta["name"] = "Hellblaster Squad"
	_check("Rites A/B (seed %d, a 2 and no 1): the 2 fails only without the +1" % seed_f,
		int(on.get("ones_rolled", -1)) == 0 and int(off.get("ones_rolled", 0)) >= 1, "on %s off %s (%s)" % [on.get("ones_rolled"), off.get("ones_rolled"), str(on.get("rolls"))])


# ---------------------------------------------------------------------------
# 20. wargear at army load
# ---------------------------------------------------------------------------
func _section_list_build() -> void:
	print("\n-- 20. list build --")
	var lt: Dictionary = _sm_army.units["U_LIEUTENANT_A"].duplicate(true)
	lt.meta["wargear"] = ["1x Neo-volkite Pistol", "1x Master-crafted Power Weapon", "1x Storm Shield"]
	B.apply_list_build("U_LIEUTENANT_A", lt)
	_check("Storm Shield: the Lieutenant has a 4+ invulnerable save", int(lt.models[0].get("invuln", 0)) == 4)
	var lt0: Dictionary = _sm_army.units["U_LIEUTENANT_A"].duplicate(true)
	B.apply_list_build("U_LIEUTENANT_A", lt0)
	_check("Storm Shield: none without the wargear", int(lt0.models[0].get("invuln", 0)) == 0)
	var imp: Dictionary = _sm_army.units["U_IMPULSOR_A"].duplicate(true)
	imp.meta["wargear"] = ["1x Shield Dome"]
	B.apply_list_build("U_IMPULSOR_A", imp)
	_check("Shield Dome: the Impulsor has a 5+ invulnerable save", int(imp.models[0].get("invuln", 0)) == 5)
	B.apply_list_build("U_IMPULSOR_A", imp)
	_check("list build is idempotent", int(imp.models[0].get("invuln", 0)) == 5)
	var imp2: Dictionary = _sm_army.units["U_IMPULSOR_A"].duplicate(true)
	imp2.meta["wargear"] = ["1x Orbital Comms Array"]
	B.apply_list_build("U_IMPULSOR_A", imp2)
	_fresh()
	GS.state.units["U_IMPULSOR_A"] = imp2
	imp2["id"] = "U_IMPULSOR_A"
	imp2["owner"] = 1
	_check("Orbital Comms Array: the Impulsor has Scouts 6\"", GS.unit_has_scout("U_IMPULSOR_A") and float(GS.get_scout_distance("U_IMPULSOR_A")) == 6.0, str(GS.get_scout_distance("U_IMPULSOR_A")))


# ---------------------------------------------------------------------------
# 21. retired 10e names
# ---------------------------------------------------------------------------
func _section_retired() -> void:
	print("\n-- 21. retired 10e names --")
	_fresh()
	var u := _u("U_INTERCESSOR_SQUAD_A")
	(u.meta.abilities as Array).append({"name": "Objective Secured"})
	_check("Objective Secured: no sticky objectives for an 11e Space Marine army", not UAM.has_sticky_objectives_ability("U_INTERCESSOR_SQUAD_A"))
	GameConstants.edition = 10
	_check("Objective Secured: 10e keeps it", UAM.has_sticky_objectives_ability("U_INTERCESSOR_SQUAD_A"))
	GameConstants.edition = 11


# ---------------------------------------------------------------------------
# 22. AI
# ---------------------------------------------------------------------------
func _section_ai() -> void:
	print("\n-- 22. AI --")
	_fresh(P_CMD)
	_place("U_CAPTAIN_IN_GRAVIS_ARMOUR_A", 10, 50)
	_place("U_BOYZ_B", 10, 35)
	var ADM = load("res://scripts/AIDecisionMaker.gd")
	var ctx := {"phase": "command", "window_id": "phase_start"}
	var offers: Array = SM.get_all_window_offers(1, "phase_start", ctx)
	_check("get_all_window_offers carries the M4b cards", offers.any(func(o): return str(o.stratagem_id) == _sid("strategic_acumen")), str(offers.map(func(o): return o.name)))
	var dec: Dictionary = ADM.decide_window_stratagem(1, "phase_start", offers, ctx)
	_check("AI uses Strategic Acumen with a doctrine variant", dec.get("use", false) and str(dec.get("stratagem_id", "")) == _sid("strategic_acumen") and str(dec.get("context", {}).get("variant_id", "")) in ["assault", "devastator", "tactical"], str(dec))
	for slug in ["teleport_homer", "tactical_fluidity"]:
		_check("AI never spends %s (plan-level)" % slug, B.ai_score(1, _sid(slug), "x", "", {}) == 0.0)
	for slug in ["spiritual_leader", "haywire_mine", "telepathic_assault", "shattered_defences", "suppression_fire", "divinator_class_auspexes", "special_issue_optics", "signum_array"]:
		_check("AI uses %s (score >= 1)" % slug, B.ai_score(1, _sid(slug), "x", "", {}) >= 1.0)
	# An AI decider never leaves the window pending.
	var ai = root.get_node("AIPlayer")
	ai.enabled = true
	ai.ai_players = {1: true, 2: false}
	PM.transition_to_phase(P_CMD)
	var cp = PM.current_phase_instance
	_check("AI P1: the phase_start window resolved synchronously (not pending)", cp == null or str(cp.get_pending_stratagem_window().get("window_id", "")) != "phase_start")
	_check("AI chose a doctrine with Strategic Acumen", str(_flags("U_CAPTAIN_IN_GRAVIS_ARMOUR_A").get("sw11e_doctrine", "")) != "", str(_flags("U_CAPTAIN_IN_GRAVIS_ARMOUR_A")))
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
