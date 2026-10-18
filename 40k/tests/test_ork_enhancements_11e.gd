extends SceneTree

# WP-O5 — Codex: Orks (11e) ENHANCEMENTS (scripts/codex/orks/OrkEnhancements11e.gd).
#
# One check group per codex enhancement (38): the condition (on/off), the
# effect (modifier, grant, or an A/B resolution with the same seed), the usage
# limit and the expiry where the rule has one; plus the data records, the
# army-construction validation, the list-build effects, detachment / edition
# gating and the AI path. Board: tests/saves/ork11e_orks_active (P2 Custodian
# Guard A–C kept as targets); P1 = the three codex rosters
# tests/fixtures/ork11e_ab_roster_{a,b,c}.json (WP-O6's codex-generated army
# files), the detachment set per group.
#
# Usage: godot --headless --path 40k --script tests/test_ork_enhancements_11e.gd

const FIXTURE := "ork11e_orks_active"
const ROSTERS := ["ork11e_ab_roster_a", "ork11e_ab_roster_b", "ork11e_ab_roster_c"]
const PX := 40.0
const P_CMD := 6
const P_MOV := 7
const P_SHOOT := 8
const P_CHG := 9
const P_FIGHT := 10
const KEEP_P2 := ["U_CUSTODIAN_GUARD_A", "U_CUSTODIAN_GUARD_B", "U_CUSTODIAN_GUARD_C"]

var passed := 0
var failed := 0
var GS = null
var SM = null
var RE = null
var OA = null
var E = null
var DET = null
var AR = null
var EP = null
var FAM = null
var _rosters: Dictionary = {}


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
# board helpers (the WP-O6 test's, same fixture and rosters)
# ---------------------------------------------------------------------------

func _json(name: String) -> Dictionary:
	var f := FileAccess.open("res://tests/fixtures/%s.json" % name, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}


func _stage_fixture() -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + FIXTURE + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + FIXTURE + ext))
	return slm.load_game(FIXTURE)


## Fresh board in `det` (P1 detachment): the fixture, P1 = the three codex
## rosters (all off the table until _place), P2 = Custodian Guard A–C.
func _fresh(det: String, phase: int = P_SHOOT, active: int = 1, battle_round: int = 2) -> void:
	_stage_fixture()
	GameConstants.edition = 11
	RE.set_test_seed(-1)
	for uid in GS.state.units.keys():
		var u: Dictionary = GS.state.units[uid]
		if int(u.get("owner", 0)) == 1 or not uid in KEEP_P2:
			GS.state.units.erase(uid)
	var fac: Dictionary = {}
	for r in ROSTERS:
		var data: Dictionary = _rosters[r]
		fac = data.get("faction", {})
		for k in data.get("units", {}):
			var u: Dictionary = data.units[k].duplicate(true)
			u["id"] = k
			u["owner"] = 1
			u["status"] = 0
			u["flags"] = {}
			u.erase("attached_to")
			u["attachment_data"] = {"attached_characters": []}
			for m in u.get("models", []):
				m["alive"] = true
				m["position"] = null
				m["current_wounds"] = int(m.get("wounds", 1))
			GS.state.units[k] = u
	GS.state.factions["1"] = fac.duplicate(true)
	GS.state.factions["1"]["detachment"] = det
	for i in range(KEEP_P2.size()):
		_place(KEEP_P2[i], 6.0 + i * 12.0, 52.0)
		GS.state.units[KEEP_P2[i]]["flags"] = {}
	GS.state.meta["phase"] = phase
	GS.state.meta["active_player"] = active
	GS.state.meta["battle_round"] = battle_round
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 6
	GS.state.players["1"].erase("ork11e_ab_uses")
	GS.state.players["2"].erase("ork11e_ab_uses")
	GS.state.players["1"].erase(E.P_MORGOG)


func _u(uid: String) -> Dictionary:
	return GS.state.units.get(uid, {})


func _flags(uid: String) -> Dictionary:
	return _u(uid).get("flags", {})


func _give(uid: String, enh: String) -> void:
	_u(uid).meta["enhancements"] = [enh]


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
	GS.state.units[bodyguard_id]["attachment_data"] = {"attached_characters": [char_id]}
	GS.state.units[char_id]["attached_to"] = bodyguard_id


func _embark(uid: String, transport_id: String) -> void:
	var u: Dictionary = GS.state.units[uid]
	u["status"] = 2
	u["embarked_in"] = transport_id
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


func _offer(player: int, window_id: String, ctx: Dictionary, slug: String) -> Dictionary:
	var c := ctx.duplicate(true)
	c["window_id"] = window_id
	for o in OA.window_offers(player, window_id, c):
		if str(o.get("stratagem_id", "")) == E.sid_of(slug):
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
	return SM.use_stratagem(player, E.sid_of(slug), uid, c)


func _mods(actor: String, target: String, melee: bool, wname: String = "", bearers: Array = []) -> Dictionary:
	var prof := {"name": wname, "type": "Melee" if melee else "Ranged", "range": 0 if melee else 24}
	return OA.attack_mods(_u(actor), _u(target), prof, melee, GS.state, bearers)


func _alive(uid: String) -> int:
	var n := 0
	for m in _u(uid).get("models", []):
		if m.get("alive", true):
			n += 1
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


## Weapon id of `uid` whose profile name contains `needle` (any type).
func _weapon(uid: String, needle: String, ranged: bool = true) -> String:
	var ws: Dictionary = RE.get_unit_weapons(uid, GS.state) if ranged else RE.get_unit_melee_weapons(uid, GS.state)
	for mid in ws:
		for wid in ws[mid]:
			var prof: Dictionary = RE.get_weapon_profile(str(wid), GS.state)
			if str(prof.get("name", "")).to_lower().contains(needle.to_lower()):
				return str(wid)
	return ""


func _first_melee(uid: String) -> String:
	var ws: Dictionary = RE.get_unit_melee_weapons(uid, GS.state)
	for mid in ws:
		for wid in ws[mid]:
			return str(wid)
	return ""


func _melee_attacks(uid: String, target: String, wid: String, seed: int) -> int:
	var act := {"type": "FIGHT", "actor_unit_id": uid, "payload": {"assignments": [{"attacker": uid, "target": target, "weapon": wid}]}}
	var res = RE.resolve_melee_attacks(act, GS.state.duplicate(true), RE.RNGService.new(seed))
	var n := 0
	for d in res.get("dice", []):
		if str(d.get("context", "")) == "hit_roll_melee":
			n += int(d.get("total_attacks", 0))
	return n


func _shoot(uid: String, wid: String, target: String, seed: int) -> Dictionary:
	var mids: Array = []
	for i in range(_u(uid).models.size()):
		mids.append(str(_u(uid).models[i].get("id", "m%d" % (i + 1))))
	var act := {"type": "SHOOT", "actor_unit_id": uid, "payload": {"assignments": [{"weapon_id": wid, "target_unit_id": target, "model_ids": mids}]}}
	return RE.resolve_shoot(act, GS.state.duplicate(true), RE.RNGService.new(seed))


## An explicit RNGService seed whose first n d6 satisfy pred (for code that
## takes an rng argument rather than make_rng()).
func _explicit_seed(n: int, pred: Callable) -> int:
	for s in range(1, 2000):
		if pred.call(RE.RNGService.new(s).roll_d6(n)):
			return s
	return -1


## Number of hit dice rolled (attacks) across the to_hit entries.
func _hit_dice(res: Dictionary) -> int:
	var n := 0
	for d in res.get("dice", []):
		if str(d.get("context", "")) in ["to_hit", "hit_roll"]:
			n += (d.get("rolls_raw", []) as Array).size()
	return n


func _dice_sum(res: Dictionary, contexts: Array, key: String) -> int:
	var n := 0
	for d in res.get("dice", []):
		if str(d.get("context", "")) in contexts:
			n += int(d.get(key, 0))
	return n


# ---------------------------------------------------------------------------
func _run() -> void:
	GS = root.get_node("GameState")
	SM = root.get_node("StratagemManager")
	RE = root.get_node("RulesEngine")
	FAM = root.get_node("FactionAbilityManager")
	OA = load("res://scripts/codex/orks/OrkAbilities11e.gd")
	E = load("res://scripts/codex/orks/OrkEnhancements11e.gd")
	DET = load("res://scripts/codex/orks/OrkDetachments11e.gd")
	AR = load("res://scripts/codex/orks/OrkArmyRules11e.gd")
	EP = load("res://autoloads/EffectPrimitives.gd")
	GameConstants.edition = 11
	var alm = root.get_node("ArmyListManager")
	for r in ROSTERS:
		_rosters[r] = alm._process_army_data(_json(r), 1)
	print("\n=== test_ork_enhancements_11e (WP-O5) ===")
	_section_data()
	_section_validation()
	_section_list_build()
	_section_gating()
	_section_war_horde()
	_section_da_big_hunt()
	_section_kult_of_speed()
	_section_dread_mob()
	_section_green_tide()
	_section_bully_boyz()
	_section_taktikal()
	_section_blitz()
	_section_wreckas()
	_section_runt_swarm()
	_section_shoota_boyz()
	_section_madcap_meks()
	_section_brute_bosses()
	_section_flyboyz()
	_section_wurrband()
	_section_ai()
	_section_dropped()


# ---------------------------------------------------------------------------
# 0. data — the 38 codex records the module reads
# ---------------------------------------------------------------------------
func _section_data() -> void:
	print("\n-- 0. codex enhancement records (data/40kdc) --")
	var recs: Dictionary = E.codex_records()
	var n := 0
	for d in recs:
		n += (recs[d] as Array).size()
	_check("15 codex detachments, 38 enhancement records", recs.size() == 15 and n == 38, "%d / %d" % [recs.size(), n])
	var all_found := true
	var missing: Array = []
	for slug in E.NAMES:
		if E.record(E.DETACHMENT[slug], E.display(slug)).is_empty():
			all_found = false
			missing.append(slug)
	_check("every module slug has its record in its detachment", all_found, str(missing))
	var costs := {"Morgog's Finkin' Cap": [50, "brute bosses"], "Targetin' Gizmos": [25, "blitz brigade"], "Supa-snazz Dakka": [25, "wreckas"],
		"Dreadherder": [30, "dread mob"], "Kill Kommanda": [20, "taktikal brigade"], "Mekwaaagh! Mastermind": [30, "madcap meks"]}
	for nm in costs:
		var r: Dictionary = E.record(costs[nm][1], nm)
		_check("%s costs %d pts" % [nm, costs[nm][0]], int(r.get("cost", -1)) == int(costs[nm][0]), str(r.get("cost", null)))
	_check("Throat-slittas is an Upgrade, Kill Kommanda is not",
		bool(E.record("taktikal brigade", "Throat-slittas").get("upgrade_tag", false)) and not bool(E.record("taktikal brigade", "Kill Kommanda").get("upgrade_tag", true)))
	_check("Kill Kommanda carries the page-only LEADER: KOMMANDOS line", E.record("taktikal brigade", "Kill Kommanda").get("attachment_bodyguard_ids", []) == ["kommandos"])
	_check("Da Krunch carries its weapon profile (Blast 3, Hazardous, Lethal Hits, Psychic)",
		E.record("wurrband", "Da Krunch").get("granted_weapon", {}).get("keywords", []) == ["Blast 3", "Hazardous", "Lethal Hits", "Psychic"])
	_check("pre-codex Mork's Kunnin' is not a Taktikal Brigade enhancement", E.record("taktikal brigade", "Mork's Kunnin'").is_empty())
	_check("name folding: Kunnin’ But Brutal (curly) == Kunnin' But Brutal", E.slug_of_name("Kunnin’ But Brutal") == "kunnin_but_brutal")
	_check("name folding: '(Upgrade)' suffix dropped", E.slug_of_name("Smoky Gubbinz (Upgrade)") == "smoky_gubbinz")


# ---------------------------------------------------------------------------
# 1. army-construction validation (11e muster + codex bearer lines)
# ---------------------------------------------------------------------------
func _army(det: String, pts: int, units: Dictionary) -> Dictionary:
	var out := {"faction": {"name": "Orks", "detachment": det, "points": pts}, "units": {}}
	for k in units:
		out.units[k] = {"meta": {"name": units[k][0], "keywords": units[k][1], "enhancements": units[k][2]}}
	return out


func _warns(army: Dictionary) -> Array:
	return E.validate_army(army).warnings


func _section_validation() -> void:
	print("\n-- 1. army-construction validation --")
	var w := ["Warboss", ["CHARACTER", "INFANTRY", "ORKS", "WARBOSS"]]
	var k := ["Kommandos", ["INFANTRY", "ORKS", "KOMMANDOS"]]
	var s := ["Stormboyz", ["INFANTRY", "ORKS", "STORMBOYZ", "FLY"]]
	var b := ["Boyz", ["INFANTRY", "ORKS", "BOYZ", "BATTLELINE"]]
	var ok := _army("Taktikal Brigade", 2000, {"W": [w[0], w[1], ["Kill Kommanda"]], "K": [k[0], k[1], ["Throat-slittas"]], "S": [s[0], s[1], ["Throat-slittas"]]})
	_check("legal list (Kill Kommanda on a Warboss, Throat-slittas x2) — no warnings", _warns(ok).is_empty(), str(_warns(ok)))
	_check("a codex Ork army is owned by this module's validation", E.owns_army_validation(ok))
	var bad1 := _army("Taktikal Brigade", 2000, {"B": [b[0], b[1], ["Kill Kommanda"]]})
	_check("Kill Kommanda on Boyz: only CHARACTER units (not an Upgrade) + bearer line",
		_warns(bad1).any(func(x): return str(x).contains("only CHARACTER")) and _warns(bad1).any(func(x): return str(x).contains("WARBOSS INFANTRY only")), str(_warns(bad1)))
	var bad2 := _army("Taktikal Brigade", 2000, {"B": [b[0], b[1], ["Throat-slittas"]]})
	_check("Throat-slittas (Upgrade) on Boyz: KOMMANDOS/STORMBOYZ only", _warns(bad2).any(func(x): return str(x).contains("KOMMANDOS/STORMBOYZ only")), str(_warns(bad2)))
	var four := _army("Taktikal Brigade", 2000, {"K1": [k[0], k[1], ["Throat-slittas"]], "K2": [k[0], k[1], ["Throat-slittas"]], "S1": [s[0], s[1], ["Throat-slittas"]], "S2": [s[0], s[1], ["Throat-slittas"]]})
	_check("four copies of an Upgrade: up to three", _warns(four).any(func(x): return str(x).contains("up to three")), str(_warns(four)))
	var three := _army("Taktikal Brigade", 1000, {"K1": [k[0], k[1], ["Throat-slittas"]], "K2": [k[0], k[1], ["Throat-slittas"]], "S1": [s[0], s[1], ["Throat-slittas"]], "W": [w[0], w[1], ["Kill Kommanda"]]})
	_check("three Upgrade copies count once: 2 choices at 1000 pts — within the cap", _warns(three).is_empty(), str(_warns(three)))
	_check("… choices counted = 2", int(E.validate_army(three).choices) == 2)
	var twice := _army("Taktikal Brigade", 2000, {"W1": [w[0], w[1], ["Kill Kommanda"]], "W2": [w[0], w[1], ["Kill Kommanda"]]})
	_check("the same non-Upgrade enhancement twice: one of each", _warns(twice).any(func(x): return str(x).contains("one of each")), str(_warns(twice)))
	var cap := _army("Brute Bosses", 1000, {"W1": [w[0], w[1], ["Proper Killy"]], "W2": [w[0], w[1], ["Blitzboss"]], "W3": [w[0], w[1], ["Brutal But Kunnin'"]]})
	_check("3 enhancements at 1000 pts: over the 2-per-1000 cap", _warns(cap).any(func(x): return str(x).contains("exceed the cap")), str(_warns(cap)))
	var epic := _army("War Horde", 2000, {"G": ["Ghazghkull Thraka", ["CHARACTER", "EPIC HERO", "ORKS", "WARBOSS"], ["Follow Me Ladz"]]})
	_check("EPIC HERO cannot be given enhancements", _warns(epic).any(func(x): return str(x).contains("EPIC HERO")), str(_warns(epic)))
	var stale := _army("Taktikal Brigade", 2000, {"W": [w[0], w[1], ["Mork's Kunnin'"]]})
	_check("pre-codex Mork's Kunnin' in Taktikal Brigade: not one of its enhancements", _warns(stale).any(func(x): return str(x).contains("not one of")), str(_warns(stale)))
	var weird := _army("Shoota Boyz", 2000, {"Wb": ["Weirdboy", ["CHARACTER", "INFANTRY", "ORKS", "PSYKER", "WEIRDBOY"], ["Supa-glowy Fing"]]})
	_check("Supa-glowy Fing on a Weirdboy: excluding WEIRDBOY", _warns(weird).any(func(x): return str(x).contains("excluding WEIRDBOY")), str(_warns(weird)))
	var two := _army("Brute Bosses", 2000, {"W": [w[0], w[1], ["Proper Killy", "Blitzboss"]]})
	_check("two enhancements on one unit: each on a different unit", _warns(two).any(func(x): return str(x).contains("different unit")), str(_warns(two)))
	var sag := _army("Madcap Meks", 2000, {"SAG": ["Big Mek with Shokk Attack Gun", ["BIG MEK", "CHARACTER", "INFANTRY", "ORKS"], ["Temperamental Shokka"]]})
	_check("an Upgrade restricted to a CHARACTER datasheet (Temperamental Shokka) is legal on it", _warns(sag).is_empty(), str(_warns(sag)))
	_check("non-codex detachment (Freebooter Krew) is not owned", not E.owns_army_validation(_army("Freebooter Krew", 2000, {})))
	_check("a Custodes army is not owned", not E.owns_army_validation({"faction": {"name": "Adeptus Custodes", "detachment": "Shield Host", "points": 2000}, "units": {}}))
	# ArmyListManager integration: the codex checks replace the generic loop.
	var alm = root.get_node("ArmyListManager")
	var bw := _army("Blitz Brigade", 2000, {"BW1": ["Battlewagon", ["ORKS", "TRANSPORT", "VEHICLE", "WAGON"], ["Targetin' Gizmos"]], "BW2": ["Battlewagon", ["ORKS", "TRANSPORT", "VEHICLE", "WAGON"], ["Targetin' Gizmos"]]})
	bw.units["W"] = {"meta": {"name": "Warboss", "keywords": ["CHARACTER", "INFANTRY", "ORKS", "WARBOSS"], "enhancements": [], "is_warlord": true}}
	var v11: Dictionary = alm.validate_army_construction_11e(bw)
	var gen_bad := false
	for x in v11.warnings:
		if str(x).contains("enhancement") and not str(x).contains("Codex: Orks"):
			gen_bad = true
	_check("validate_army_construction_11e: two Targetin' Gizmos wagons (Upgrade) — no enhancement warning", not gen_bad and not v11.warnings.any(func(x): return str(x).contains("Codex: Orks")), str(v11.warnings))
	var v10: Dictionary = alm.validate_army_construction_points(bw)
	_check("validate_army_construction_points: no 10e 'not a CHARACTER' warning for an Upgrade on a WAGON", not v10.warnings.any(func(x): return str(x).contains("not a CHARACTER")), str(v10.warnings))
	var bwbad := _army("Blitz Brigade", 2000, {"T": ["Trukk", ["ORKS", "TRANSPORT", "VEHICLE", "DEDICATED TRANSPORT"], ["Targetin' Gizmos"]]})
	_check("validate_army_construction_11e reports the codex bearer line (Targetin' Gizmos on a Trukk: WAGON only)",
		alm.validate_army_construction_11e(bwbad).warnings.any(func(x): return str(x).contains("WAGON only")), str(alm.validate_army_construction_11e(bwbad).warnings))


# ---------------------------------------------------------------------------
# 2. list-build effects (ArmyListManager hook)
# ---------------------------------------------------------------------------
func _section_list_build() -> void:
	print("\n-- 2. list-build: 'Ardboyz, It Came from da Drops, Flyboss, Warphead, weapons --")
	_fresh("Green Tide")
	var boyz: Dictionary = _u("U_BOYZ_C").duplicate(true)
	boyz.meta["enhancements"] = ["'Ardboyz"]
	var sv0 := int(boyz.meta.stats.save)
	E.apply_list_build("U_BOYZ_C", boyz, "Green Tide")
	_check("'Ardboyz: Boyz Sv %d+ -> 4+" % sv0, int(boyz.meta.stats.save) == 4, str(boyz.meta.stats.save))
	E.apply_list_build("U_BOYZ_C", boyz, "Green Tide")
	_check("idempotent (second load does nothing more)", int(boyz.meta.stats.save) == 4 and boyz.meta.get(E.F_LIST_BUILD, []) == ["ardboyz"])
	var boyz2: Dictionary = _u("U_BOYZ_D").duplicate(true)
	boyz2.meta["enhancements"] = ["'Ardboyz"]
	E.apply_list_build("U_BOYZ_D", boyz2, "War Horde")
	_check("'Ardboyz in a War Horde roster (not its detachment): no effect", int(boyz2.meta.stats.save) == sv0)
	var bos: Dictionary = _u("U_BEASTBOSS_ON_SQUIGOSAUR_A").duplicate(true)
	bos.meta["enhancements"] = ["It Came from da Drops"]
	var t0 := int(bos.meta.stats.toughness)
	E.apply_list_build("U_BEASTBOSS_ON_SQUIGOSAUR_A", bos, "Da Big Hunt")
	_check("It Came from da Drops: T %d -> %d" % [t0, t0 + 1], int(bos.meta.stats.toughness) == t0 + 1)
	var dj: Dictionary = _u("U_DAKKAJET_A").duplicate(true)
	dj.meta["enhancements"] = ["Flyboss"]
	E.apply_list_build("U_DAKKAJET_A", dj, "Flyboyz")
	_check("Flyboss: the aircraft has CHARACTER", "CHARACTER" in dj.meta.keywords)
	var wb: Dictionary = _u("U_WEIRDBOY_A").duplicate(true)
	wb.meta["enhancements"] = ["Warphead"]
	E.apply_list_build("U_WEIRDBOY_A", wb, "Wurrband")
	var dd: Array = wb.meta.abilities.filter(func(a): return (str(a.get("name", "")) if a is Dictionary else str(a)).to_lower().begins_with("deadly demise"))
	_check("Warphead: one Deadly Demise ability, D6", dd.size() == 1 and str(dd[0].get("name", "")) == "Deadly Demise D6", str(dd))
	var wk: Dictionary = _u("U_WEIRDBOY_A").duplicate(true)
	wk.meta["enhancements"] = ["Da Krunch"]
	E.apply_list_build("U_WEIRDBOY_A", wk, "Wurrband")
	var krunch: Array = wk.meta.weapons.filter(func(x): return str(x.get("name", "")) == "Da Krunch")
	_check("Da Krunch: the weapon is added (24\" A3 BS4+ S5 AP-1 D1)", krunch.size() == 1 and str(krunch[0].range) == "24" and str(krunch[0].attacks) == "3"
		and str(krunch[0].ballistic_skill) == "4" and str(krunch[0].strength) == "5" and str(krunch[0].ap) == "-1" and str(krunch[0].damage) == "1", str(krunch))
	_check("Da Krunch: [BLAST 3] [HAZARDOUS] [LETHAL HITS] [PSYCHIC] as structured abilities",
		krunch.size() == 1 and krunch[0].abilities.any(func(a): return a.id == "blast" and int(a.get("x", 0)) == 3) and krunch[0].abilities.any(func(a): return a.id == "psychic")
		and krunch[0].abilities.any(func(a): return a.id == "lethal_hits") and krunch[0].abilities.any(func(a): return a.id == "hazardous"), str(krunch))
	_check("Da Krunch: wargear line added", "1x Da Krunch" in wk.meta.wargear)
	var we: Dictionary = _u("U_WEIRDBOY_A").duplicate(true)
	we.meta["enhancements"] = ["'Eadbanger"]
	E.apply_list_build("U_WEIRDBOY_A", we, "Wurrband")
	var eb: Array = we.meta.weapons.filter(func(x): return str(x.get("name", "")) == "'Eadbanger")
	_check("'Eadbanger: 24\" A2 S6 AP-3 D3 [HAZARDOUS] [PRECISION] [PSYCHIC]", eb.size() == 1 and str(eb[0].ap) == "-3" and str(eb[0].damage) == "3"
		and eb[0].abilities.any(func(a): return a.id == "precision"), str(eb))
	var wgb: Dictionary = _u("U_WARBOSS_A").duplicate(true)
	wgb.meta["enhancements"] = ["Da Gobshot Thunderbuss"]
	E.apply_list_build("U_WARBOSS_A", wgb, "Brute Bosses")
	var gb: Array = wgb.meta.weapons.filter(func(x): return str(x.get("name", "")) == "Da Gobshot Thunderbuss")
	_check("Da Gobshot Thunderbuss: 24\" A6 BS4+ S7 AP-2 D2 [RAPID FIRE 6]; Lethal Hits is per-target (not on the weapon)",
		gb.size() == 1 and str(gb[0].attacks) == "6" and gb[0].abilities.any(func(a): return a.id == "rapid_fire" and int(a.get("x", 0)) == 6)
		and not gb[0].abilities.any(func(a): return str(a.id).begins_with("lethal")), str(gb))
	# The real ArmyListManager load path runs the hook.
	var alm = root.get_node("ArmyListManager")
	var army := _json("ork11e_ab_roster_c")
	army.faction["detachment"] = "Brute Bosses"
	army.units.U_WARBOSS_A.meta["enhancements"] = ["Da Gobshot Thunderbuss"]
	var proc: Dictionary = alm._process_army_data(army, 1)
	_check("ArmyListManager._process_army_data adds the enhancement weapon (cloud / builder path)",
		proc.units.U_WARBOSS_A.meta.weapons.any(func(x): return str(x.get("name", "")) == "Da Gobshot Thunderbuss"))


# ---------------------------------------------------------------------------
# 3. gating: detachment, edition, UnitAbilityManager skip
# ---------------------------------------------------------------------------
func _section_gating() -> void:
	print("\n-- 3. detachment / edition gating --")
	_fresh("War Horde", P_FIGHT)
	_place("U_WARBOSS_A", 10, 30)
	_give("U_WARBOSS_A", "Brutal But Kunnin'")
	_check("Brutal But Kunnin' in a War Horde army (the 10e Green Tide name): no codex effect", int(_mods("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", true).damage) == 0)
	GS.state.factions["1"]["detachment"] = "Brute Bosses"
	_check("… in Brute Bosses: +1 D", int(_mods("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", true).damage) == 1)
	GameConstants.edition = 10
	_check("… at edition 10: no codex effect", not E.has(_u("U_WARBOSS_A"), "brutal_but_kunnin"))
	GameConstants.edition = 11
	_check("UnitAbilityManager skips a name this module owns", E.owns_name(_u("U_WARBOSS_A"), "Brutal But Kunnin'"))
	GS.state.factions["1"]["detachment"] = "More Dakka!"
	_give("U_WARBOSS_A", "Da Gobshot Thunderbuss")
	_check("More Dakka! (non-codex) keeps its own 10e row for Da Gobshot Thunderbuss", not E.owns_name(_u("U_WARBOSS_A"), "Da Gobshot Thunderbuss"))


# ---------------------------------------------------------------------------
# 4. WAR HORDE — Headwoppa's Killchoppa, Da Boss is Watchin', Kunnin' But
#    Brutal, Follow Me Ladz
# ---------------------------------------------------------------------------
func _section_war_horde() -> void:
	print("\n-- 4. War Horde --")
	_fresh("War Horde", P_FIGHT)
	_place("U_BOYZ_C", 10, 30)
	_place("U_WARBOSS_A", 10, 31.6)
	_attach("U_WARBOSS_A", "U_BOYZ_C")
	_give("U_WARBOSS_A", "Headwoppa's Killchoppa")
	_check("Headwoppa's: no charge — no AP", int(_mods("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", true).ap) == 0)
	_flags("U_BOYZ_C")["charged_this_turn"] = true
	_check("Headwoppa's: the unit charged — this model's melee +1 AP", int(_mods("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", true).ap) == 1, str(_mods("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", true)))
	_check("Headwoppa's: the bodyguard Boyz' melee unaffected (this model only)", int(_mods("U_BOYZ_C", "U_CUSTODIAN_GUARD_A", true).ap) == 0)
	_check("Headwoppa's: ranged unaffected", int(_mods("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", false).ap) == 0)
	# Follow Me Ladz: this unit +2" M (the whole Attached unit).
	_give("U_WARBOSS_A", "Follow Me Ladz")
	_check("Follow Me Ladz: the Boyz (bodyguard) +2\" M", OA.move_modifier(_u("U_BOYZ_C")) == 2.0, str(OA.move_modifier(_u("U_BOYZ_C"))))
	_check("Follow Me Ladz: the Warboss +2\" M", OA.move_modifier(_u("U_WARBOSS_A")) == 2.0)
	_u("U_BOYZ_C")["attachment_data"] = {"attached_characters": []}
	_u("U_WARBOSS_A").erase("attached_to")
	_check("Follow Me Ladz: not attached — the Boyz move normally", OA.move_modifier(_u("U_BOYZ_C")) == 0.0)
	# Kunnin' But Brutal: fall back -> shoot + charge.
	_attach("U_WARBOSS_A", "U_BOYZ_C")
	_give("U_WARBOSS_A", "Kunnin' But Brutal")
	_check("Kunnin' But Brutal: fall back and shoot (EffectPrimitives)", EP.has_effect_fall_back_and_shoot(_u("U_BOYZ_C")))
	_check("Kunnin' But Brutal: fall back and charge", EP.has_effect_fall_back_and_charge(_u("U_BOYZ_C")))
	_give("U_WARBOSS_A", "")
	_check("without it: neither", not EP.has_effect_fall_back_and_shoot(_u("U_BOYZ_C")) and not EP.has_effect_fall_back_and_charge(_u("U_BOYZ_C")))
	# Da Boss is Watchin' — once per battle, per army; Movement phase.
	_fresh("War Horde", P_MOV)
	_place("U_BOYZ_C", 10, 30)
	_place("U_WARBOSS_A", 10, 31.6)
	_attach("U_WARBOSS_A", "U_BOYZ_C")
	_give("U_WARBOSS_A", "Da Boss is Watchin'")
	var o := _offer(1, "movement_phase_start", {"phase": "movement"}, "da_boss_is_watchin")
	_check("Da Boss is Watchin': offered at the start of your Movement phase (on the Attached unit)", _offer_units(o) == ["U_BOYZ_C"], str(_offer_units(o)))
	_check("… and when the unit is selected to move", _offer_units(_offer(1, "unit_selected_to_move", {"phase": "movement", "unit_id": "U_BOYZ_C", "move_type": "normal"}, "da_boss_is_watchin")) == ["U_BOYZ_C"])
	_check("… not when another unit is selected", _offer(1, "unit_selected_to_move", {"phase": "movement", "unit_id": "U_NOBZ_A", "move_type": "normal"}, "da_boss_is_watchin").is_empty())
	_check("… not in the opponent's Movement phase", _offer(1, "movement_phase_start", {"phase": "movement"}, "da_boss_is_watchin").is_empty() == false and _offer(2, "movement_phase_start", {"phase": "movement"}, "da_boss_is_watchin").is_empty())
	var r := _use(1, "da_boss_is_watchin", "U_BOYZ_C", "movement_phase_start", {"phase": "movement"})
	_check("USE: success, 0 CP", r.get("success", false) and int(GS.state.players["1"].cp) == 6, str(r))
	_check("the Boyz and the Warboss are riled up", OA.group_riled_up("U_BOYZ_C") and bool(_flags("U_WARBOSS_A").get("ork11e_riled_up", false)))
	_check("riled up: 5+ InSv", EP.get_effect_invuln(_u("U_BOYZ_C")) == 5)
	_check("once per battle, per army", _offer(1, "movement_phase_start", {"phase": "movement"}, "da_boss_is_watchin").is_empty())
	_phase(P_CMD, 2)
	OA.on_phase_transition(P_MOV, P_CMD)
	_check("still riled up in the opponent's turn", OA.group_riled_up("U_BOYZ_C"))
	GS.state.meta["battle_round"] = 3
	_phase(P_CMD, 1)
	OA.on_phase_transition(11, P_CMD)
	_check("expires at the start of your next turn", not OA.group_riled_up("U_BOYZ_C"), str(_flags("U_BOYZ_C").get(OA.F_RILED, null)))


# ---------------------------------------------------------------------------
# 5. DA BIG HUNT — Glory Hog, It Came from da Drops
# ---------------------------------------------------------------------------
func _section_da_big_hunt() -> void:
	print("\n-- 5. Da Big Hunt --")
	_fresh("Da Big Hunt", P_MOV)
	_place("U_BEAST_SNAGGA_BOYZ_B", 10, 30)
	_place("U_BEASTBOSS_A", 10, 31.6)
	_attach("U_BEASTBOSS_A", "U_BEAST_SNAGGA_BOYZ_B")
	_check("Glory Hog: without it, no fall-back-and-charge", not EP.has_effect_fall_back_and_charge(_u("U_BEAST_SNAGGA_BOYZ_B")))
	_give("U_BEASTBOSS_A", "Glory Hog")
	_check("Glory Hog: the Attached unit can fall back and charge", EP.has_effect_fall_back_and_charge(_u("U_BEAST_SNAGGA_BOYZ_B")))
	_check("Glory Hog: but not fall back and shoot", not EP.has_effect_fall_back_and_shoot(_u("U_BEAST_SNAGGA_BOYZ_B")))
	_check("Glory Hog: no 10e Scouts 9\"", not GS.unit_has_scout("U_BEAST_SNAGGA_BOYZ_B"))
	# It Came from da Drops (+1 T) is a list-build effect — section 2; the
	# toughness feeds the wound roll: A/B same seed vs the raised T.
	_fresh("Da Big Hunt", P_SHOOT)
	_u("U_BEASTBOSS_ON_SQUIGOSAUR_A").meta["enhancements"] = ["It Came from da Drops"]
	var t0 := int(_u("U_BEASTBOSS_ON_SQUIGOSAUR_A").meta.stats.toughness)
	E.apply_list_build("U_BEASTBOSS_ON_SQUIGOSAUR_A", _u("U_BEASTBOSS_ON_SQUIGOSAUR_A"), "Da Big Hunt")
	_check("It Came from da Drops: the in-game unit's T is %d" % (t0 + 1), int(_u("U_BEASTBOSS_ON_SQUIGOSAUR_A").meta.stats.toughness) == t0 + 1)


# ---------------------------------------------------------------------------
# 6. KULT OF SPEED — Smoky Gubbinz, Competitive Streak
# ---------------------------------------------------------------------------
func _section_kult_of_speed() -> void:
	print("\n-- 6. Kult of Speed --")
	_fresh("Kult of Speed", P_SHOOT, 2)
	var tm = root.get_node("TerrainManager")
	# Boyz behind Warbikers (Smoky Gubbinz) from a Custodian Guard's view.
	_place("U_BOYZ_C", 10, 20)
	_place("U_WARBIKERS_A", 12, 35)
	_place("U_CUSTODIAN_GUARD_A", 12, 50)
	var attacker: Dictionary = _u("U_CUSTODIAN_GUARD_A").models[0]
	var before: bool = tm.unit_has_cover_11e(_u("U_BOYZ_C"), attacker)
	_u("U_WARBIKERS_A").meta["enhancements"] = ["Smoky Gubbinz"]
	var after: bool = tm.unit_has_cover_11e(_u("U_BOYZ_C"), attacker)
	_check("Smoky Gubbinz: a Boyz unit seen past the Warbikers has the benefit of cover", (not before) and after, "before %s after %s" % [before, after])
	_place("U_WARBIKERS_A", 40, 35)
	_check("Smoky Gubbinz: Warbikers out of the line — no cover", not tm.unit_has_cover_11e(_u("U_BOYZ_C"), attacker))
	_place("U_WARBIKERS_A", 12, 35)
	_check("Smoky Gubbinz: the Warbikers themselves get no cover from their own models", not tm.unit_has_cover_11e(_u("U_WARBIKERS_A"), attacker))
	GS.state.factions["1"]["detachment"] = "War Horde"
	_check("Smoky Gubbinz: not in a War Horde army", not tm.unit_has_cover_11e(_u("U_BOYZ_C"), attacker))
	# Competitive Streak: this unit can re-roll charge rolls.
	_fresh("Kult of Speed", P_CHG)
	_place("U_DEFFKILLA_WARTRIKE_A", 10, 30)
	_check("Competitive Streak: no re-roll source without it", DET.charge_reroll_source(_u("U_DEFFKILLA_WARTRIKE_A")) == "")
	_give("U_DEFFKILLA_WARTRIKE_A", "Competitive Streak")
	_check("Competitive Streak: charge re-roll source", DET.charge_reroll_source(_u("U_DEFFKILLA_WARTRIKE_A")) == "Competitive Streak")
	_check("… FactionAbilityManager.unit_has_detachment_charge_reroll", FAM.unit_has_detachment_charge_reroll(_u("U_DEFFKILLA_WARTRIKE_A")))


# ---------------------------------------------------------------------------
# 7. DREAD MOB — Cybork Boosta, Dreadherder
# ---------------------------------------------------------------------------
func _section_dread_mob() -> void:
	print("\n-- 7. Dread Mob --")
	_fresh("Dread Mob", P_MOV)
	_place("U_MEK_A", 10, 30)
	_place("U_BOYZ_C", 20, 30)
	_attach("U_MEK_A", "U_BOYZ_C")
	_give("U_MEK_A", "Cybork Boosta")
	_check("Cybork Boosta: this model +2\" M", OA.move_modifier(_u("U_MEK_A")) == 2.0)
	_check("Cybork Boosta: the bodyguard unaffected (this model only)", OA.move_modifier(_u("U_BOYZ_C")) == 0.0)
	# Dreadherder
	_fresh("Dread Mob", P_SHOOT)
	_place("U_BIG_MEK_A", 10, 30)
	_place("U_DEFF_DREAD_A", 10, 31.7)
	_give("U_BIG_MEK_A", "Dreadherder")
	_check("Dreadherder: Lone Operative within 3\" of an ORKS WALKER", RE.has_lone_operative(_u("U_BIG_MEK_A")))
	_place("U_DEFF_DREAD_A", 30, 30)
	_check("Dreadherder: no Lone Operative away from the walker", not RE.has_lone_operative(_u("U_BIG_MEK_A")))
	_place("U_DEFF_DREAD_A", 10, 31.7)
	var ctx := {"phase": "shooting", "unit_id": "U_DEFF_DREAD_A"}
	var o := _offer(1, "unit_selected_to_shoot", ctx, "dreadherder")
	_check("Dreadherder: offered when the walker within 3\" is selected to shoot", _offer_units(o) == ["U_DEFF_DREAD_A"], str(o))
	var ob := _offer(1, "unit_selected_to_shoot", {"phase": "shooting", "unit_id": "U_BIG_MEK_A"}, "dreadherder")
	_check("Dreadherder: offered on the Big Mek's selection with the walker to pick", _secondary_ids(ob, "U_BIG_MEK_A") == ["U_DEFF_DREAD_A"], str(ob))
	_check("Dreadherder: not offered for a non-walker", _offer(1, "unit_selected_to_shoot", {"phase": "shooting", "unit_id": "U_BOYZ_C"}, "dreadherder").is_empty())
	_check("before: the walker has no re-roll", str(_mods("U_DEFF_DREAD_A", "U_CUSTODIAN_GUARD_A", false).hit_reroll) == "")
	var r := _use(1, "dreadherder", "U_DEFF_DREAD_A", "unit_selected_to_shoot", ctx)
	_check("USE: success", r.get("success", false), str(r))
	_check("the walker re-rolls hit rolls of 1 (ranged)", str(_mods("U_DEFF_DREAD_A", "U_CUSTODIAN_GUARD_A", false).hit_reroll) == "ones")
	_phase(P_FIGHT)
	_check("… and in the Fight phase (until the end of the turn)", str(_mods("U_DEFF_DREAD_A", "U_CUSTODIAN_GUARD_A", true).hit_reroll) == "ones")
	_phase(P_SHOOT)
	_check("once per Shooting phase per Big Mek", _offer(1, "unit_selected_to_shoot", {"phase": "shooting", "unit_id": "U_KILLA_KANS_A"}, "dreadherder").is_empty())
	_phase(P_CMD, 2)
	OA.on_phase_transition(11, P_CMD)
	_check("expires at the end of the turn", str(_mods("U_DEFF_DREAD_A", "U_CUSTODIAN_GUARD_A", false).hit_reroll) == "")


# ---------------------------------------------------------------------------
# 8. GREEN TIDE — Ferocious Show-off, 'Ardboyz
# ---------------------------------------------------------------------------
func _section_green_tide() -> void:
	print("\n-- 8. Green Tide --")
	_fresh("Green Tide", P_FIGHT)
	_place("U_WARBOSS_A", 10, 30)
	_place("U_CUSTODIAN_GUARD_A", 10, 31.6)
	_give("U_WARBOSS_A", "Ferocious Show-off")
	_check("Ferocious Show-off: alone — +1 A", int(_mods("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", true).attacks) == 1)
	var wid := _first_melee("U_WARBOSS_A")
	var a_with := _melee_attacks("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", wid, 7)
	_give("U_WARBOSS_A", "")
	var a_without := _melee_attacks("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", wid, 7)
	_check("A/B melee (seed 7): +1 attack", a_with == a_without + 1, "%d vs %d" % [a_with, a_without])
	_give("U_WARBOSS_A", "Ferocious Show-off")
	_place("U_BOYZ_C", 10, 28)
	_attach("U_WARBOSS_A", "U_BOYZ_C")
	_check("Ferocious Show-off: attached to %d Boyz (11+ models) — +2 A" % _alive("U_BOYZ_C"), _alive("U_BOYZ_C") + 1 >= 11 and int(_mods("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", true).attacks) == 2, str(_alive("U_BOYZ_C")))
	_check("Ferocious Show-off: the Boyz' own attacks unchanged", int(_mods("U_BOYZ_C", "U_CUSTODIAN_GUARD_A", true).attacks) == 0)
	_check("Ferocious Show-off: ranged unchanged", int(_mods("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", false).attacks) == 0)
	# 'Ardboyz: the in-game save after list-build.
	_fresh("Green Tide", P_SHOOT)
	_u("U_BOYZ_C").meta["enhancements"] = ["'Ardboyz"]
	E.apply_list_build("U_BOYZ_C", _u("U_BOYZ_C"), "Green Tide")
	_check("'Ardboyz: the Boyz' Sv is 4+ in game", int(_u("U_BOYZ_C").meta.stats.save) == 4)


# ---------------------------------------------------------------------------
# 9. BULLY BOYZ — Wimp-kickaz, Tellyporta Boss
# ---------------------------------------------------------------------------
func _section_bully_boyz() -> void:
	print("\n-- 9. Bully Boyz --")
	_fresh("Bully Boyz", P_MOV, 2)
	_place("U_NOBZ_A", 10, 30)
	_place("U_CUSTODIAN_GUARD_A", 10, 31.6)
	var fb = load("res://scripts/rules/movetypes/FallBackMove.gd").new()
	var sel0: Dictionary = fb.select_mode("U_CUSTODIAN_GUARD_A", GS.state)
	_check("Wimp-kickaz: without it, ordered retreat is available", sel0.mode == "ordered_retreat", str(sel0))
	_u("U_NOBZ_A").meta["enhancements"] = ["Wimp-kickaz"]
	var sel1: Dictionary = fb.select_mode("U_CUSTODIAN_GUARD_A", GS.state)
	_check("Wimp-kickaz: an engaged enemy must select desperate escape", sel1.mode == "desperate_escape" and bool(sel1.mandatory), str(sel1))
	_check("Wimp-kickaz: not riled up — no hazard modifier", E.desperate_escape_hazard_modifier("U_CUSTODIAN_GUARD_A") == 0)
	_flags("U_NOBZ_A")["ork11e_riled_up"] = true
	_check("Wimp-kickaz: riled up — -1 to those hazard rolls", E.desperate_escape_hazard_modifier("U_CUSTODIAN_GUARD_A") == -1)
	# A/B: same seed, failures with and without the -1.
	var hseed := _explicit_seed(_alive("U_CUSTODIAN_GUARD_A"), func(r): return r.has(3))
	var hz_with: Dictionary = fb.before_moving("U_CUSTODIAN_GUARD_A", GS.state, RE.RNGService.new(hseed), {"mode": "desperate_escape"})
	_flags("U_NOBZ_A").erase("ork11e_riled_up")
	var hz_without: Dictionary = fb.before_moving("U_CUSTODIAN_GUARD_A", GS.state, RE.RNGService.new(hseed), {"mode": "desperate_escape"})
	_check("A/B hazard rolls (same seed): the -1 fails a roll of 3", int(hz_with.hazard.failures) > int(hz_without.hazard.failures), "%s vs %s" % [str(hz_with.hazard), str(hz_without.hazard)])
	_place("U_NOBZ_A", 30, 20)
	_check("Wimp-kickaz: not engaged — ordered retreat again", fb.select_mode("U_CUSTODIAN_GUARD_A", GS.state).mode == "ordered_retreat")
	# Tellyporta Boss
	_fresh("Bully Boyz", P_MOV)
	_place("U_MEGANOBZ_B", 10, 30)
	_place("U_WARBOSS_IN_MEGA_ARMOUR_A", 10, 31.6)
	_attach("U_WARBOSS_IN_MEGA_ARMOUR_A", "U_MEGANOBZ_B")
	_check("Tellyporta Boss: without it, no Deep Strike", not GS.unit_has_deep_strike("U_MEGANOBZ_B"))
	_give("U_WARBOSS_IN_MEGA_ARMOUR_A", "Tellyporta Boss")
	_check("Tellyporta Boss: the Attached unit (Meganobz + bearer) has Deep Strike", GS.unit_has_deep_strike("U_MEGANOBZ_B") and GS.unit_has_deep_strike("U_WARBOSS_IN_MEGA_ARMOUR_A"))
	_give("U_WARBOSS_IN_MEGA_ARMOUR_A", "Tellyporta")
	_check("Tellyporta Boss: the 10e 'Tellyporta' name grants nothing", not GS.unit_has_deep_strike("U_MEGANOBZ_B"))
	_give("U_WARBOSS_IN_MEGA_ARMOUR_A", "Tellyporta Boss")
	GS.state.factions["1"]["detachment"] = "War Horde"
	_check("Tellyporta Boss in a War Horde army: no Deep Strike", not GS.unit_has_deep_strike("U_MEGANOBZ_B"))


# ---------------------------------------------------------------------------
# 10. TAKTIKAL BRIGADE — Kill Kommanda, Throat-slittas
# ---------------------------------------------------------------------------
func _section_taktikal() -> void:
	print("\n-- 10. Taktikal Brigade --")
	_fresh("Taktikal Brigade", P_MOV)
	var cam = root.get_node("CharacterAttachmentManager")
	_place("U_KOMMANDOS_A", 10, 30)
	_place("U_WARBOSS_A", 10, 31.6)
	_check("Kill Kommanda: without it a Warboss cannot lead Kommandos", not cam.can_attach("U_WARBOSS_A", "U_KOMMANDOS_A").valid)
	_give("U_WARBOSS_A", "Kill Kommanda")
	_check("Kill Kommanda: LEADER: KOMMANDOS — can attach", cam.can_attach("U_WARBOSS_A", "U_KOMMANDOS_A").valid, str(cam.can_attach("U_WARBOSS_A", "U_KOMMANDOS_A")))
	_check("… eligible bodyguards include the Kommandos", GS.get_eligible_bodyguards_for_character("U_WARBOSS_A").has("U_KOMMANDOS_A"))
	_check("Kill Kommanda: not attached — no Infiltrators / Stealth", not GS.unit_has_infiltrators("U_WARBOSS_A") and not RE.has_stealth_ability(_u("U_WARBOSS_A")))
	_attach("U_WARBOSS_A", "U_KOMMANDOS_A")
	_check("Kill Kommanda: attached — the bearer has Infiltrators and Stealth", GS.unit_has_infiltrators("U_WARBOSS_A") and RE.has_stealth_ability(_u("U_WARBOSS_A")))
	_check("the Kommandos keep their own Infiltrators", GS.unit_has_infiltrators("U_KOMMANDOS_A"))
	# Throat-slittas (Upgrade on the Kommandos): melee [LETHAL HITS: non-MONSTER/VEHICLE]
	_fresh("Taktikal Brigade", P_FIGHT)
	_place("U_KOMMANDOS_A", 10, 30)
	_place("U_BATTLEWAGON_A", 30, 30)
	_check("Throat-slittas: without it, no [LETHAL HITS]", not bool(_mods("U_KOMMANDOS_A", "U_CUSTODIAN_GUARD_A", true).lethal))
	_u("U_KOMMANDOS_A").meta["enhancements"] = ["Throat-slittas"]
	_check("Throat-slittas: melee vs INFANTRY — [LETHAL HITS]", bool(_mods("U_KOMMANDOS_A", "U_CUSTODIAN_GUARD_A", true).lethal))
	GS.state.units["U_FAKE_VEHICLE"] = _u("U_BATTLEWAGON_A").duplicate(true)
	GS.state.units["U_FAKE_VEHICLE"]["id"] = "U_FAKE_VEHICLE"
	GS.state.units["U_FAKE_VEHICLE"]["owner"] = 2
	_check("Throat-slittas: vs a VEHICLE — no [LETHAL HITS]", not bool(_mods("U_KOMMANDOS_A", "U_FAKE_VEHICLE", true).lethal))
	_check("Throat-slittas: ranged unaffected", not bool(_mods("U_KOMMANDOS_A", "U_CUSTODIAN_GUARD_A", false).lethal))
	GS.state.units.erase("U_FAKE_VEHICLE")


# ---------------------------------------------------------------------------
# 11. BLITZ BRIGADE — Targetin' Gizmos, Boss Boomer
# ---------------------------------------------------------------------------
func _section_blitz() -> void:
	print("\n-- 11. Blitz Brigade --")
	_fresh("Blitz Brigade", P_SHOOT)
	_place("U_BATTLEWAGON_A", 10, 30)
	_u("U_BATTLEWAGON_A").meta["enhancements"] = ["Targetin' Gizmos"]
	_check("Targetin' Gizmos: no Big Mek embarked — no [IGNORES COVER]", not bool(_mods("U_BATTLEWAGON_A", "U_CUSTODIAN_GUARD_A", false).ignores_cover))
	_embark("U_BIG_MEK_A", "U_BATTLEWAGON_A")
	var m := _mods("U_BATTLEWAGON_A", "U_CUSTODIAN_GUARD_A", false)
	_check("Targetin' Gizmos: Big Mek embarked — ranged [IGNORES COVER]", bool(m.ignores_cover) and int(m.sustained) == 0, str(m))
	_flags("U_BATTLEWAGON_A")["ork11e_riled_up"] = true
	_check("Targetin' Gizmos: riled up — [SUSTAINED HITS 1]", int(_mods("U_BATTLEWAGON_A", "U_CUSTODIAN_GUARD_A", false).sustained) == 1)
	_check("the 10e Rollin' Deff Targetin' Gizmos sustained does not also fire", FAM.targetin_gizmos_sustained(_u("U_BATTLEWAGON_A")) == 0)
	# Boss Boomer: the wagon has the embarked Warboss's Intimidating Motivation.
	_fresh("Blitz Brigade", P_MOV)
	_place("U_BATTLEWAGON_A", 10, 30)
	_u("U_BATTLEWAGON_A").meta["enhancements"] = ["Boss Boomer"]
	_check("Boss Boomer: no Warboss embarked — no Intimidating Motivation", not OA.has(_u("U_BATTLEWAGON_A"), "intimidating_motivation"))
	_embark("U_WARBOSS_A", "U_BATTLEWAGON_A")
	_check("Boss Boomer: Warboss embarked — the wagon has Intimidating Motivation", OA.has(_u("U_BATTLEWAGON_A"), "intimidating_motivation"))
	_check("Boss Boomer: … not Keep Huntin' (the Warboss does not have it)", not OA.has(_u("U_BATTLEWAGON_A"), "keep_huntin"))
	_place("U_BOYZ_C", 10, 26)
	_flags("U_BOYZ_C")["battle_shocked"] = true
	var o := _o_offer(1, "unit_selected_to_move", {"phase": "movement", "unit_id": "U_BATTLEWAGON_A", "move_type": "normal"}, "intimidating_motivation")
	_check("Boss Boomer: Intimidating Motivation offered when the wagon is selected to move (O6 offer)", not o.is_empty(), str(OA.window_offers(1, "unit_selected_to_move", {"phase": "movement", "unit_id": "U_BATTLEWAGON_A", "move_type": "normal", "window_id": "unit_selected_to_move"})))


func _o_offer(player: int, window_id: String, ctx: Dictionary, slug: String) -> Dictionary:
	var c := ctx.duplicate(true)
	c["window_id"] = window_id
	for o in OA.window_offers(player, window_id, c):
		if str(o.get("stratagem_id", "")) == OA.sid_of(slug):
			return o
	return {}


# ---------------------------------------------------------------------------
# 12. WRECKAS — Kaptin's Hat, Supa-snazz Dakka
# ---------------------------------------------------------------------------
func _section_wreckas() -> void:
	print("\n-- 12. Wreckas --")
	_fresh("Wreckas", P_SHOOT)
	var cam = root.get_node("CharacterAttachmentManager")
	_place("U_FLASH_GITZ_A", 10, 30)
	_place("U_WARBOSS_A", 10, 31.6)
	_check("Kaptin's Hat: without it a Warboss cannot lead Flash Gitz", not cam.can_attach("U_WARBOSS_A", "U_FLASH_GITZ_A").valid)
	_give("U_WARBOSS_A", "Kaptin's Hat")
	_check("Kaptin's Hat: LEADER: FLASH GITZ — can attach", cam.can_attach("U_WARBOSS_A", "U_FLASH_GITZ_A").valid)
	_check("Kaptin's Hat: the redeploy enhancement (Razgit's machinery)", str(FAM.get_redeploy_enhancement(1).get("name", "")) == "Kaptin's Hat")
	_place("U_BOYZ_C", 20, 20)
	_place("U_BATTLEWAGON_A", 30, 20)
	var elig: Array = FAM.get_razgit_eligible_units(1).map(func(e): return str(e.unit_id))
	_check("Kaptin's Hat: ORKS INFANTRY units are eligible, a vehicle is not", "U_BOYZ_C" in elig and "U_FLASH_GITZ_A" in elig and not "U_BATTLEWAGON_A" in elig, str(elig))
	_check("Kaptin's Hat: up to three", FAM.get_razgit_redeploys_remaining(1) == 3)
	GS.state.factions["1"]["detachment"] = "War Horde"
	_check("Kaptin's Hat in War Horde: no redeploy", FAM.get_redeploy_enhancement(1).is_empty())
	# Supa-snazz Dakka: Snazzgun weapons [RAPID FIRE 1].
	_fresh("Wreckas", P_SHOOT)
	_place("U_FLASH_GITZ_A", 10, 30)
	var wid := _weapon("U_FLASH_GITZ_A", "snazzgun – dakka")
	if wid == "":
		wid = _weapon("U_FLASH_GITZ_A", "snazzgun")
	var prof: Dictionary = RE.get_weapon_profile(wid, GS.state)
	_check("Supa-snazz Dakka: off — no grant", E.rapid_fire_grant(_u("U_FLASH_GITZ_A"), prof) == 0)
	_u("U_FLASH_GITZ_A").meta["enhancements"] = ["Supa-snazz Dakka"]
	_check("Supa-snazz Dakka: Snazzgun [RAPID FIRE 1]", E.rapid_fire_grant(_u("U_FLASH_GITZ_A"), prof) == 1, wid)
	_check("Supa-snazz Dakka: not other guns", E.rapid_fire_grant(_u("U_FLASH_GITZ_A"), {"name": "Slugga"}) == 0)
	_place("U_CUSTODIAN_GUARD_A", 10, 40)  # within half range of the 24" Snazzgun – Dakka
	var with_a := _hit_dice(_shoot("U_FLASH_GITZ_A", wid, "U_CUSTODIAN_GUARD_A", 3))
	_u("U_FLASH_GITZ_A").meta["enhancements"] = []
	var without_a := _hit_dice(_shoot("U_FLASH_GITZ_A", wid, "U_CUSTODIAN_GUARD_A", 3))
	_check("A/B shooting at half range (seed 3): one extra attack per model", with_a == without_a + _alive("U_FLASH_GITZ_A"), "%d vs %d (%d models, %s)" % [with_a, without_a, _alive("U_FLASH_GITZ_A"), wid])


# ---------------------------------------------------------------------------
# 13. RUNT SWARM — Extra Sneaky, Minefield Detail
# ---------------------------------------------------------------------------
func _section_runt_swarm() -> void:
	print("\n-- 13. Runt Swarm --")
	_fresh("Runt Swarm", P_SHOOT)
	var tm = root.get_node("TerrainManager")
	_place("U_GRETCHIN_A", 10, 30)
	var base_dr: float = tm.detection_range_inches(_u("U_GRETCHIN_A")) if tm.has_method("detection_range_inches") else 15.0
	_u("U_GRETCHIN_A").meta["enhancements"] = ["Extra Sneaky"]
	_check("Extra Sneaky: -3\" detection range bonus", OA.detection_range_bonus(_u("U_GRETCHIN_A")) == -3.0)
	if tm.has_method("detection_range_inches"):
		_check("Extra Sneaky: the Gretchin's detection range is %.0f\"" % (base_dr - 3.0), is_equal_approx(float(tm.detection_range_inches(_u("U_GRETCHIN_A"))), base_dr - 3.0), str(tm.detection_range_inches(_u("U_GRETCHIN_A"))))
	_check("Minefield Detail: without it, no Scouts", not GS.unit_has_scout("U_GRETCHIN_A"))
	_u("U_GRETCHIN_A").meta["enhancements"] = ["Minefield Detail"]
	_check("Minefield Detail: Scouts 6\"", GS.unit_has_scout("U_GRETCHIN_A") and GS.get_scout_distance("U_GRETCHIN_A") == 6.0, str(GS.get_scout_distance("U_GRETCHIN_A")))
	_embark("U_GRETCHIN_A", "U_TRUKK_A")
	_check("Minefield Detail: embarked — no Scouts", E.scouts_distance(_u("U_GRETCHIN_A")) == 0.0)


# ---------------------------------------------------------------------------
# 14. SHOOTA BOYZ — Supa-glowy Fing, Targetin' Squigs
# ---------------------------------------------------------------------------
func _section_shoota_boyz() -> void:
	print("\n-- 14. Shoota Boyz --")
	_fresh("Shoota Boyz", P_SHOOT)
	_place("U_WARBOSS_A", 10, 30)
	_place("U_CUSTODIAN_GUARD_A", 10, 42)
	var wid := _weapon("U_WARBOSS_A", "kustom shoota")
	var m0 := _mods("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", false)
	_check("Supa-glowy Fing: off — no DW / anti", not bool(m0.get("devastating", false)) and m0.get("anti", []).is_empty())
	_give("U_WARBOSS_A", "Supa-glowy Fing")
	var m1 := _mods("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", false)
	_check("Supa-glowy Fing: ranged [DEVASTATING WOUNDS] + [ANTI-INFANTRY 4+]", bool(m1.devastating) and E.anti_threshold(m1, _u("U_CUSTODIAN_GUARD_A")) == 4, str(m1))
	_check("Supa-glowy Fing: melee unaffected", not bool(_mods("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", true).get("devastating", false)))
	# A/B: same seed — critical wounds on 4+ vs INFANTRY; DW turns them into mortal wounds.
	var res_b := _shoot("U_WARBOSS_A", wid, "U_CUSTODIAN_GUARD_A", 11)
	_give("U_WARBOSS_A", "")
	var res_a := _shoot("U_WARBOSS_A", wid, "U_CUSTODIAN_GUARD_A", 11)
	var crit := func(res):
		var n := 0
		for d in res.get("dice", []):
			if str(d.get("context", "")) in ["to_wound", "wound_roll"]:
				n += int(d.get("critical_wounds", d.get("crits", 0)))
		return n
	_check("A/B shooting (seed 11): at least as many critical wounds with ANTI-INFANTRY 4+", int(crit.call(res_b)) >= int(crit.call(res_a)), "%d vs %d" % [crit.call(res_b), crit.call(res_a)])
	# [SUPA-HAZARDOUS]: two hazard rolls per selected weapon, after the shooting.
	_give("U_WARBOSS_A", "Supa-glowy Fing")
	E.on_targets_confirmed("U_WARBOSS_A", [{"weapon_id": wid, "target_unit_id": "U_CUSTODIAN_GUARD_A", "model_ids": ["m1"]}])
	_check("[SUPA-HAZARDOUS]: 1 weapon selected recorded", int(_flags("U_WARBOSS_A").get(E.F_SUPA_SEL, 0)) == 1)
	var w0 := int(_u("U_WARBOSS_A").models[0].current_wounds)
	var hz_seed := _seed_where(2, func(r): return int(r[0]) <= 2 and int(r[1]) <= 2)
	E.after_unit_shot("U_WARBOSS_A", ["U_CUSTODIAN_GUARD_A"])
	_check("[SUPA-HAZARDOUS]: two failed hazard rolls cost the Warboss 2 wounds", int(_u("U_WARBOSS_A").models[0].current_wounds) == w0 - 2, "%d -> %d (seed %d)" % [w0, int(_u("U_WARBOSS_A").models[0].current_wounds), hz_seed])
	_check("[SUPA-HAZARDOUS]: bookkeeping cleared", not _flags("U_WARBOSS_A").has(E.F_SUPA_SEL))
	RE.set_test_seed(-1)
	# Targetin' Squigs: this unit's ranged (non-Torrent) +3" R.
	_fresh("Shoota Boyz", P_SHOOT)
	_place("U_BOYZ_C", 10, 30)
	_place("U_WARBOSS_A", 10, 31.6)
	_attach("U_WARBOSS_A", "U_BOYZ_C")
	var shoota := {"name": "Shoota", "type": "Ranged", "range": 18, "special_rules": ""}
	var skorcha := {"name": "Skorcha", "type": "Ranged", "range": 12, "special_rules": "blast, torrent"}
	_check("Targetin' Squigs: off — +0", RE.ork11e_det_range_bonus(_u("U_BOYZ_C"), shoota) == 0.0)
	_give("U_WARBOSS_A", "Targetin' Squigs")
	_check("Targetin' Squigs: the Boyz' Shoota +3\" R", RE.ork11e_det_range_bonus(_u("U_BOYZ_C"), shoota) == 3.0)
	_check("Targetin' Squigs: [TORRENT] excluded", RE.ork11e_det_range_bonus(_u("U_BOYZ_C"), skorcha) == 0.0)
	_flags("U_BOYZ_C")["ork11e_riled_up"] = true
	_check("Targetin' Squigs + Dakka! Dakka! Dakka! (riled up): +6\" (different rules stack)", RE.ork11e_det_range_bonus(_u("U_BOYZ_C"), shoota) == 6.0)
	_check("no 10e Targetin' Squigs +1 to hit", not bool(_mods("U_BOYZ_C", "U_CUSTODIAN_GUARD_A", false).hit_plus))


# ---------------------------------------------------------------------------
# 15. MADCAP MEKS — Mekwaaagh! Mastermind, Temperamental Shokka, Enhanced Runt-maw
# ---------------------------------------------------------------------------
func _section_madcap_meks() -> void:
	print("\n-- 15. Madcap Meks --")
	_fresh("Madcap Meks", P_MOV)
	_place("U_BIG_MEK_A", 10, 30)
	_place("U_BOYZ_C", 10, 28)
	_attach("U_BIG_MEK_A", "U_BOYZ_C")
	_give("U_BIG_MEK_A", "Mekwaaagh! Mastermind")
	_check("Mekwaaagh! Mastermind: before a phase start — not yet", not OA.group_riled_up("U_BOYZ_C"))
	OA.on_phase_transition(P_CMD, P_MOV)
	_check("Mekwaaagh! Mastermind: this unit (the Attached unit) is riled up", OA.group_riled_up("U_BOYZ_C") and Common_riled(_u("U_BIG_MEK_A")))
	GS.state.meta["battle_round"] = 3
	_phase(P_CMD, 1)
	OA.on_phase_transition(11, P_CMD)
	_check("Mekwaaagh! Mastermind: permanent (still riled up next turn)", OA.group_riled_up("U_BOYZ_C"))
	# Temperamental Shokka
	_fresh("Madcap Meks", P_SHOOT)
	_place("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A", 10, 30)
	_u("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A").meta["enhancements"] = ["Temperamental Shokka"]
	var ctx := {"phase": "shooting", "unit_id": "U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A"}
	var o := _offer(1, "unit_selected_to_shoot", ctx, "temperamental_shokka")
	_check("Temperamental Shokka: offered when selected to shoot", _offer_units(o) == ["U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A"], str(o))
	_phase(P_FIGHT)
	_check("… only in your Shooting phase", _offer(1, "unit_selected_to_shoot", ctx, "temperamental_shokka").is_empty())
	_phase(P_SHOOT)
	var s4 := _seed_where(1, func(r): return int(r[0]) == 4)
	var r := _use(1, "temperamental_shokka", "U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A", "unit_selected_to_shoot", ctx)
	_check("USE (rolled 4): recorded", r.get("success", false) and int(_flags("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A").get(E.F_TSHOKKA, {}).get("result", 0)) == 4, str(_flags("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A").get(E.F_TSHOKKA, null)) + " seed %d" % s4)
	_check("2-5: the Shokk Attack Gun has +1 A", int(_mods("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A", "U_CUSTODIAN_GUARD_A", false, "Shokk Attack Gun").attacks) == 1)
	_check("… other weapons unaffected", int(_mods("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A", "U_CUSTODIAN_GUARD_A", false, "Kustom mega-slugga").attacks) == 0)
	_check("once per phase", _offer(1, "unit_selected_to_shoot", ctx, "temperamental_shokka").is_empty())
	E.after_unit_shot("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A", ["U_CUSTODIAN_GUARD_A"])
	_check("effect ends when the unit has shot", not _flags("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A").has(E.F_TSHOKKA) and _alive("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A") == 1)
	_flags("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A")[E.F_TSHOKKA] = {"result": 6}
	_check("6: [SUSTAINED HITS 2]", int(_mods("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A", "U_CUSTODIAN_GUARD_A", false, "Shokk Attack Gun").sustained) == 2)
	_flags("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A")[E.F_TSHOKKA] = {"result": 1}
	_check("1: [TORRENT]", bool(_mods("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A", "U_CUSTODIAN_GUARD_A", false, "Shokk Attack Gun").get("torrent", false)))
	var sag := _weapon("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A", "shokk attack gun")
	var tres := _shoot("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A", sag, "U_CUSTODIAN_GUARD_A", 4)
	_check("1: the attack resolves as auto-hits (no hit roll)", _dice_sum(tres, ["auto_hit"], "total_attacks") > 0 or tres.get("dice", []).any(func(d): return str(d.get("context", "")) == "auto_hit"), str(tres.get("dice", []).map(func(d): return d.get("context", ""))))
	E.after_unit_shot("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A", ["U_CUSTODIAN_GUARD_A"])
	_check("1: the Big Mek is destroyed when the unit has shot", _alive("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A") == 0)
	_flags("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A")[E.F_TSHOKKA] = {"result": 5}
	OA.on_phase_transition(P_SHOOT, P_CHG)
	_check("cleared at the end of the Shooting phase", not _flags("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A").has(E.F_TSHOKKA))
	RE.set_test_seed(-1)
	# Enhanced Runt-maw
	_fresh("Madcap Meks", P_SHOOT)
	_place("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A", 10, 30)
	_u("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A").meta["enhancements"] = ["Enhanced Runt-maw"]
	var ld0: int = OA.leadership_penalty("U_CUSTODIAN_GUARD_A")
	E.after_unit_shot("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A", ["U_CUSTODIAN_GUARD_A"])
	_check("Enhanced Runt-maw: one unit hit — infested automatically (-1 to leadership rolls)", OA.leadership_penalty("U_CUSTODIAN_GUARD_A") == ld0 + 1)
	var cp = load("res://phases/CommandPhase.gd")
	_check("… CommandPhase effective Ld worsened by 1", cp._get_effective_leadership("U_CUSTODIAN_GUARD_A") == int(_u("U_CUSTODIAN_GUARD_A").meta.stats.leadership) + 1, str(cp._get_effective_leadership("U_CUSTODIAN_GUARD_A")))
	_phase(P_CMD, 2)
	OA.on_phase_transition(11, P_CMD)
	_check("… lasts through the opponent's turn", OA.leadership_penalty("U_CUSTODIAN_GUARD_A") == 1)
	GS.state.meta["battle_round"] = 3
	_phase(P_CMD, 1)
	OA.on_phase_transition(11, P_CMD)
	_check("… until the start of your next turn", OA.leadership_penalty("U_CUSTODIAN_GUARD_A") == 0)
	_fresh("Madcap Meks", P_SHOOT)
	_place("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A", 10, 30)
	_u("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A").meta["enhancements"] = ["Enhanced Runt-maw"]
	var hctx := {"phase": "shooting", "unit_id": "U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A", "hit_unit_ids": ["U_CUSTODIAN_GUARD_A", "U_CUSTODIAN_GUARD_B"]}
	E.after_unit_shot("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A", hctx.hit_unit_ids)
	_check("two units hit: not resolved automatically", OA.leadership_penalty("U_CUSTODIAN_GUARD_A") == 0 and OA.leadership_penalty("U_CUSTODIAN_GUARD_B") == 0)
	var ro := _offer(1, "unit_has_shot", hctx, "enhanced_runt_maw")
	_check("two units hit: offered with both", _secondary_ids(ro, "U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A").size() == 2, str(ro))
	var rr := _use(1, "enhanced_runt_maw", "U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A", "unit_has_shot", hctx, "U_CUSTODIAN_GUARD_B")
	_check("USE: the picked unit is infested", rr.get("success", false) and OA.leadership_penalty("U_CUSTODIAN_GUARD_B") == 1 and OA.leadership_penalty("U_CUSTODIAN_GUARD_A") == 0)
	_check("once per shooting", _offer(1, "unit_has_shot", hctx, "enhanced_runt_maw").is_empty())


func Common_riled(u: Dictionary) -> bool:
	var f: Dictionary = u.get("flags", {})
	return bool(f.get("waaagh_active", false)) or bool(f.get("ork11e_riled_up", false))


# ---------------------------------------------------------------------------
# 16. BRUTE BOSSES — Surly as a Squiggoth, Brutal But Kunnin', Blitzboss,
#     Proper Killy, Morgog's Finkin' Cap, Da Gobshot Thunderbuss
# ---------------------------------------------------------------------------
func _section_brute_bosses() -> void:
	print("\n-- 16. Brute Bosses --")
	_fresh("Brute Bosses", P_FIGHT)
	_place("U_WARBOSS_A", 10, 30)
	_place("U_CUSTODIAN_GUARD_A", 10, 31.6)
	_give("U_WARBOSS_A", "Brutal But Kunnin'")
	_check("Brutal But Kunnin': melee +1 D", int(_mods("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", true).damage) == 1)
	_check("Brutal But Kunnin': ranged unaffected", int(_mods("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", false).damage) == 0)
	_check("Brutal But Kunnin': no 10e Command-phase CP roll (gone)", not FAM.has_method("process_command_phase_cp_enhancements"))
	_give("U_WARBOSS_A", "Proper Killy")
	_check("Proper Killy: melee re-roll hit rolls of 1", str(_mods("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", true).hit_reroll) == "ones")
	_check("Proper Killy: ranged too (this model)", str(_mods("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", false).hit_reroll) == "ones")
	_place("U_BOYZ_C", 10, 28)
	_attach("U_WARBOSS_A", "U_BOYZ_C")
	_check("Proper Killy: the bodyguard's attacks unaffected", str(_mods("U_BOYZ_C", "U_CUSTODIAN_GUARD_A", true).hit_reroll) == "")
	_check("Proper Killy: the Boyz' ranged batch (bearer ids = Boyz models) unaffected",
		str(_mods("U_BOYZ_C", "U_CUSTODIAN_GUARD_A", false, "Slugga", ["m1", "m2"]).hit_reroll) == "")
	_check("Proper Killy: the Warboss' ranged batch inside the Attached unit (composite bearer id)",
		str(_mods("U_BOYZ_C", "U_CUSTODIAN_GUARD_A", false, "Kustom shoota", ["U_WARBOSS_A:m1"]).hit_reroll) == "ones")
	# Blitzboss: transport +2" M, 5+ InSv.
	_fresh("Brute Bosses", P_MOV)
	_place("U_TRUKK_A", 10, 30)
	_give("U_WARBOSS_A", "Blitzboss")
	_check("Blitzboss: not embarked — the Trukk unchanged", OA.move_modifier(_u("U_TRUKK_A")) == 0.0 and EP.get_effect_invuln(_u("U_TRUKK_A")) == 0)
	_embark("U_WARBOSS_A", "U_TRUKK_A")
	_check("Blitzboss: the Trukk carrying the Warboss +2\" M", OA.move_modifier(_u("U_TRUKK_A")) == 2.0)
	_check("Blitzboss: … and 5+ InSv", EP.get_effect_invuln(_u("U_TRUKK_A")) == 5, str(EP.get_effect_invuln(_u("U_TRUKK_A"))))
	# Da Gobshot Thunderbuss: [LETHAL HITS: non-MONSTER/VEHICLE] per target.
	_fresh("Brute Bosses", P_SHOOT)
	_place("U_WARBOSS_A", 10, 30)
	_give("U_WARBOSS_A", "Da Gobshot Thunderbuss")
	_check("Da Gobshot Thunderbuss: [LETHAL HITS] vs INFANTRY", bool(_mods("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", false, "Da Gobshot Thunderbuss").lethal))
	_check("… not for the Warboss' other guns", not bool(_mods("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", false, "Kustom shoota").lethal))
	# Surly as a Squiggoth
	_fresh("Brute Bosses", P_FIGHT, 2)
	_place("U_WARBOSS_A", 10, 30)
	_place("U_CUSTODIAN_GUARD_A", 10, 31.6)
	_give("U_WARBOSS_A", "Surly as a Squiggoth")
	OA.on_phase_transition(P_CHG, P_FIGHT)
	_check("Surly: alive at the phase start is recorded", bool(_flags("U_WARBOSS_A").get(E.F_SURLY, {}).get("alive", false)))
	_u("U_WARBOSS_A").models[0]["alive"] = false
	_u("U_WARBOSS_A").models[0]["current_wounds"] = 0
	var s2 := _seed_where(1, func(r): return int(r[0]) >= 2)
	OA.on_phase_transition(P_FIGHT, P_CMD)
	var m0: Dictionary = _u("U_WARBOSS_A").models[0]
	_check("Surly (2+): set back up with 3 wounds", bool(m0.get("alive", false)) and int(m0.current_wounds) == 3, str(m0) + " seed %d" % s2)
	var meas = root.get_node("Measurement")
	var min_d := INF
	for em in _u("U_CUSTODIAN_GUARD_A").models:
		if em.get("alive", true):
			min_d = minf(min_d, float(meas.model_to_model_distance_inches(m0, em)))
	_check("Surly: unengaged (> %.0f\" from the enemy)" % GameConstants.engagement_range_inches(), min_d > GameConstants.engagement_range_inches(), str(min_d))
	_check("Surly: close to where it fell (< 6\")", Vector2(float(m0.position.x), float(m0.position.y)).distance_to(Vector2(10.5 * PX, 30 * PX)) < 6.0 * PX * 1.2)
	_u("U_WARBOSS_A").models[0]["alive"] = false
	OA.on_phase_transition(P_CMD, P_MOV)
	OA.on_phase_transition(P_MOV, P_SHOOT)
	_check("Surly: once per battle", not bool(_u("U_WARBOSS_A").models[0].get("alive", true)))
	RE.set_test_seed(-1)
	_fresh("Brute Bosses", P_FIGHT, 2)
	_place("U_WARBOSS_A", 10, 30)
	_give("U_WARBOSS_A", "Surly as a Squiggoth")
	OA.on_phase_transition(P_CHG, P_FIGHT)
	_u("U_WARBOSS_A").models[0]["alive"] = false
	_seed_where(1, func(r): return int(r[0]) == 1)
	OA.on_phase_transition(P_FIGHT, P_CMD)
	_check("Surly (1): stays destroyed", not bool(_u("U_WARBOSS_A").models[0].get("alive", true)))
	RE.set_test_seed(-1)
	# Morgog's Finkin' Cap — end of the OPPONENT's Movement phase.
	_fresh("Brute Bosses", P_MOV, 2)
	_place("U_WARBOSS_A", 10, 20)
	_give("U_WARBOSS_A", "Morgog's Finkin' Cap")
	_phase(P_MOV, 1)
	_check("Morgog's: not in your own Movement phase", _offer(1, "movement_phase_end", {"phase": "movement"}, "morgogs_finkin_cap").is_empty())
	_phase(P_MOV, 2)
	var mo := _offer(1, "movement_phase_end", {"phase": "movement"}, "morgogs_finkin_cap")
	_check("Morgog's: offered at the end of the opponent's Movement phase", _offer_units(mo) == ["U_WARBOSS_A"], str(mo))
	_place("U_CUSTODIAN_GUARD_A", 10, 21.6)
	_check("Morgog's: not while engaged", _offer(1, "movement_phase_end", {"phase": "movement"}, "morgogs_finkin_cap").is_empty())
	_place("U_CUSTODIAN_GUARD_A", 10, 52)
	var s3 := _seed_where(1, func(r): return int(r[0]) == 3)
	var mr := _use(1, "morgogs_finkin_cap", "U_WARBOSS_A", "movement_phase_end", {"phase": "movement"})
	_check("USE (not riled up, rolled 3): a normal move of up to 3\" follows", mr.get("success", false) and str(mr.get("followup", {}).get("type", "")) == "reactive_normal_move"
		and float(mr.followup.max_inches) == 3.0, str(mr) + " seed %d" % s3)
	_check("once per battle, per army", _offer(1, "movement_phase_end", {"phase": "movement"}, "morgogs_finkin_cap").is_empty())
	RE.set_test_seed(-1)
	_fresh("Brute Bosses", P_MOV, 2)
	_place("U_WARBOSS_A", 10, 20)
	_give("U_WARBOSS_A", "Morgog's Finkin' Cap")
	_flags("U_WARBOSS_A")["ork11e_riled_up"] = true
	_seed_where(1, func(r): return int(r[0]) == 2)
	var mr1 := _use(1, "morgogs_finkin_cap", "U_WARBOSS_A", "movement_phase_end", {"phase": "movement"})
	_check("riled up (rolled 2): the window re-opens with keep / re-roll", mr1.get("success", false) and str(mr1.get("followup", {}).get("type", "")) == "ork11e_reoffer", str(mr1))
	var po := _offer(1, "movement_phase_end", {"phase": "movement"}, "morgogs_finkin_cap")
	var vids: Array = po.get("targets", [{}])[0].get("variants", []).map(func(v): return v.id)
	_check("… variants: keep / reroll (AI hint: reroll a 2)", vids == ["keep", "reroll"] and str(po.targets[0].get("ai_variant", "")) == "reroll", str(po))
	_seed_where(1, func(r): return int(r[0]) == 5)
	var mr2 := _use(1, "morgogs_finkin_cap", "U_WARBOSS_A", "movement_phase_end", {"phase": "movement"}, "", "reroll")
	_check("re-roll (5): a normal move of up to 5\"", str(mr2.get("followup", {}).get("type", "")) == "reactive_normal_move" and float(mr2.followup.max_inches) == 5.0, str(mr2))
	_check("pending roll cleared", E._morgog_pending(1).is_empty())
	RE.set_test_seed(-1)


# ---------------------------------------------------------------------------
# 17. FLYBOYZ — Flyboss, Impulsive Recon
# ---------------------------------------------------------------------------
func _section_flyboyz() -> void:
	print("\n-- 17. Flyboyz --")
	_fresh("Flyboyz", P_MOV, 1, 2)
	_place("U_DAKKAJET_A", 10, 20)
	_place("U_DEFFKOPTAS_A", 14, 20)
	_place("U_BURNA_BOMMER_A", 40, 50)
	_u("U_WAZBOM_BLASTAJET_A")["status"] = 7  # in reserves
	_u("U_WAZBOM_BLASTAJET_A").meta["enhancements"] = ["Flyboss"]
	var arrival: Array = [Vector2(12 * PX, 26 * PX)]
	var d: Array = E.on_ingress_move_ended("U_WAZBOM_BLASTAJET_A", arrival)
	var riled_ids := {}
	for x in d:
		if str(x.path).ends_with(".flags.ork11e_riled_up"):
			riled_ids[str(x.path).split(".")[1]] = true
	_check("Flyboss: ingress end — Dakkajet and Deffkoptas within 6\" riled up", riled_ids.has("U_DAKKAJET_A") and riled_ids.has("U_DEFFKOPTAS_A"), str(riled_ids.keys()))
	_check("Flyboss: the Burna-bommer far away is not", not riled_ids.has("U_BURNA_BOMMER_A"))
	_check("Flyboss: other units (Boyz) never", not riled_ids.has("U_BOYZ_C"))
	_u("U_WAZBOM_BLASTAJET_A").meta["enhancements"] = []
	_check("without Flyboss: nothing", E.on_ingress_move_ended("U_WAZBOM_BLASTAJET_A", arrival).is_empty())
	# Impulsive Recon
	_fresh("Flyboyz", P_MOV, 1, 1)
	_u("U_DAKKAJET_A")["status"] = 7
	_u("U_BURNA_BOMMER_A")["status"] = 7
	_u("U_DAKKAJET_A").meta["enhancements"] = ["Impulsive Recon"]
	_check("Impulsive Recon: battle round 1, own turn — may arrive", E.allows_first_round_ingress(_u("U_DAKKAJET_A")))
	_check("… others may not", not E.allows_first_round_ingress(_u("U_BURNA_BOMMER_A")))
	_check("first_round_ingress_units filters the list", E.first_round_ingress_units(["U_DAKKAJET_A", "U_BURNA_BOMMER_A"]) == ["U_DAKKAJET_A"])
	_phase(P_MOV, 2)
	_check("… not in the opponent's first Movement phase", not E.allows_first_round_ingress(_u("U_DAKKAJET_A")))
	_phase(P_MOV, 1)
	GS.state.meta["battle_round"] = 2
	_check("… battle round 2: the normal rule applies (not this enhancement)", not E.allows_first_round_ingress(_u("U_DAKKAJET_A")))


# ---------------------------------------------------------------------------
# 18. WURRBAND — Da Krunch, 'Eadbanger (weapons: section 2), Warphead
# ---------------------------------------------------------------------------
func _section_wurrband() -> void:
	print("\n-- 18. Wurrband --")
	_fresh("Wurrband", P_FIGHT)
	_place("U_WEIRDBOY_A", 10, 30)
	_check("Weirdboy psyker level 1", AR.psyker_level(_u("U_WEIRDBOY_A")) == 1)
	_give("U_WEIRDBOY_A", "Warphead")
	_check("Warphead: psyker level 2", AR.psyker_level(_u("U_WEIRDBOY_A")) == 2)
	_seed_where(1, func(r): return int(r[0]) == 4)
	var rng = RE.make_rng()
	_check("Warphead: a psychic roll of 1 is re-rolled", E.psychic_reroll("U_WEIRDBOY_A", 1, rng) == 4)
	_check("Warphead: other rolls are kept", E.psychic_reroll("U_WEIRDBOY_A", 3, RE.make_rng()) == 3)
	_give("U_WEIRDBOY_A", "")
	_check("without Warphead: a 1 stays a 1", E.psychic_reroll("U_WEIRDBOY_A", 1, RE.make_rng()) == 1)
	RE.set_test_seed(-1)
	# Warpath via the O6 path: the roll site calls the re-roll hook.
	_give("U_WEIRDBOY_A", "Warphead")
	_place("U_CUSTODIAN_GUARD_A", 10, 31.6)
	_seed_where(2, func(r): return int(r[0]) == 1 and int(r[1]) >= 2)
	var wr: Dictionary = SM.use_stratagem(1, OA.sid_of("warpath"), "U_WEIRDBOY_A", {"window_id": "unit_selected_to_fight", "phase": "fight", "unit_id": "U_WEIRDBOY_A"})
	_check("Warpath with Warphead: the 1 is re-rolled — not battle-shocked", wr.get("success", false) and not bool(_flags("U_WEIRDBOY_A").get("battle_shocked", false)), str(wr))
	RE.set_test_seed(-1)


# ---------------------------------------------------------------------------
# 19. AI — every activated enhancement scored synchronously
# ---------------------------------------------------------------------------
func _section_ai() -> void:
	print("\n-- 19. AI --")
	_fresh("Dread Mob", P_SHOOT)
	_place("U_BIG_MEK_A", 10, 30)
	_place("U_DEFF_DREAD_A", 10, 31.7)
	_give("U_BIG_MEK_A", "Dreadherder")
	var ctx := {"phase": "shooting", "unit_id": "U_DEFF_DREAD_A", "window_id": "unit_selected_to_shoot"}
	var offers: Array = SM.get_all_window_offers(1, "unit_selected_to_shoot", ctx)
	_check("get_all_window_offers carries the enhancement offer", offers.any(func(o): return str(o.get("stratagem_id", "")) == E.sid_of("dreadherder")))
	var aidm = load("res://scripts/AIDecisionMaker.gd")
	var dec_all: Dictionary = aidm.decide_window_stratagem(1, "unit_selected_to_shoot", offers, ctx)
	_check("AI decides the full window synchronously (a Dictionary, no stall)", dec_all.has("use"), str(dec_all))
	var only: Array = offers.filter(func(o): return str(o.get("stratagem_id", "")) == E.sid_of("dreadherder"))
	var dec: Dictionary = aidm.decide_window_stratagem(1, "unit_selected_to_shoot", only, ctx)
	_check("AI uses Dreadherder (score 2.0) when it is the offer", bool(dec.get("use", false)) and str(dec.get("stratagem_id", "")) == E.sid_of("dreadherder"), str(dec))
	var scored := true
	for w in E.WINDOW_ENHANCEMENTS:
		for s in E.WINDOW_ENHANCEMENTS[w]:
			var v = OA.ai_score(1, E.sid_of(s), "U_BIG_MEK_A", w, ctx)
			if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
				scored = false
	_check("ai_score returns a number for every activated enhancement", scored)
	_check("AI declines Temperamental Shokka (a 1 destroys the Big Mek)", OA.ai_score(1, E.sid_of("temperamental_shokka"), "U_BIG_MEK_A", "unit_selected_to_shoot", ctx) == 0.0)
	_check("AI declines Morgog's move (plan-level), but finishes a parked roll", OA.ai_score(1, E.sid_of("morgogs_finkin_cap"), "U_WARBOSS_A", "movement_phase_end", ctx) == 0.0)


# ---------------------------------------------------------------------------
# 20. pre-codex enhancements removed
# ---------------------------------------------------------------------------
func _section_dropped() -> void:
	print("\n-- 20. pre-codex Ork enhancements removed --")
	var uam = root.get_node("UnitAbilityManager")
	for n in ["Follow Me Ladz", "Headwoppa's Killchoppa", "Kunnin' But Brutal", "Supa-Cybork Body", "Skwad Leader", "Mek Kaptin",
			"Gob Boomer", "Raucous Warcaller", "Bloodthirsty Belligerence", "Ferocious Show Off", "Brutal But Kunnin'", "Glory Hog",
			"Proper Killy", "Skrag Every Stash!", "Surly as a Squiggoth", "Fasta Than Yooz", "Speed Makes Right", "Squig-hide Tyres",
			"Wazblasta", "Gitfinder Googlez", "Smoky Gubbinz", "Supa-glowy Fing", "Press It Fasta!", "Runnin' Boots", "Blitzkaptin",
			"Supercharged Squig Oil", "Tuff Git"]:
		_check("ABILITY_EFFECTS has no 10e '%s' row" % n, not uam.ABILITY_EFFECTS.has(n))
	for n in ["Da Gobshot Thunderbuss", "Targetin' Squigs", "Targetin' Gizmos", "Git-spotter Squig"]:
		_check("non-codex detachment row kept: '%s'" % n, uam.ABILITY_EFFECTS.has(n))
	_check("ArmyListManager: no Da Biggest Boss +2 W", not root.get_node("ArmyListManager").ENHANCEMENT_STAT_BONUSES.has("Da Biggest Boss"))
	for f in ["has_morks_kunnin", "has_blitzkaptin", "process_big_gob", "process_skrag_every_stash", "process_supa_glowy_fing", "runnin_boots_charge_bonus", "ferocious_show_off_strength_bonus"]:
		_check("FactionAbilityManager has no %s" % f, not FAM.has_method(f))
	var sp = load("res://phases/ShootingPhase.gd")
	_check("ShootingPhase: no USE_WAZBLASTA", not sp.source_code.contains("\"USE_WAZBLASTA\""))
	_check("RulesEngine: no Mek Kaptin / 'Eadstompa helpers", not RE.has_method("unit_has_mek_kaptin_reroll") and not RE.has_method("get_eadstompa_reroll_scope"))
