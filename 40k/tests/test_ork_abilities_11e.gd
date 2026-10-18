extends SceneTree

# WP-O6 — Codex: Orks (11e) DATASHEET abilities (scripts/codex/orks/OrkAbilities11e.gd).
#
# One check group per implemented / re-keyed ability: the condition (on/off),
# the effect (modifier, or an A/B attack resolution with the same seed) and the
# usage limit where the ability has one. Board: tests/saves/ork11e_orks_active
# (P2 Custodian Guard A–C kept as targets); P1 = the three codex rosters
# tests/fixtures/ork11e_ab_roster_{a,b,c}.json (army files generated from the
# codex data, so every ability name is the codex spelling).
#
# Usage: godot --headless --path 40k --script tests/test_ork_abilities_11e.gd

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
var PM = null
var OA = null
var EP = null
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
# board helpers
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


## Fresh board: the fixture save, P1 replaced by the three codex rosters (all
## units off the table until _place), P2 = Custodian Guard A–C.
func _fresh(phase: int = P_SHOOT, active: int = 1, battle_round: int = 2) -> void:
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
	SM.load_faction_stratagems_for_player(1)
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


func _u(uid: String) -> Dictionary:
	return GS.state.units.get(uid, {})


func _flags(uid: String) -> Dictionary:
	return _u(uid).get("flags", {})


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


func _wound(uid: String, lost: int) -> void:
	var m: Dictionary = GS.state.units[uid].models[0]
	m["current_wounds"] = maxi(1, int(m.get("wounds", 1)) - lost)


func _phase(p: int, active: int = 1) -> void:
	GS.state.meta["phase"] = p
	GS.state.meta["active_player"] = active


func _sid(slug: String) -> String:
	return OA.sid_of(slug)


func _offer(player: int, window_id: String, ctx: Dictionary, slug: String) -> Dictionary:
	var c := ctx.duplicate(true)
	c["window_id"] = window_id
	for o in OA.window_offers(player, window_id, c):
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


func _mods(actor: String, target: String, melee: bool, wname: String = "", bearers: Array = []) -> Dictionary:
	var prof := {"name": wname, "type": "Melee" if melee else "Ranged", "range": 0 if melee else 24}
	return OA.attack_mods(_u(actor), _u(target), prof, melee, GS.state, bearers)


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


## A test seed whose first RulesEngine.make_rng() rolls `n` D6 satisfying
## `pred`. set_test_seed resets the counter, so the call under test (whose
## first make_rng() is the ability's own) sees exactly those rolls.
func _seed_where(n: int, pred: Callable) -> int:
	for s in range(1, 800):
		RE.set_test_seed(s)
		var rolls: Array = RE.make_rng().roll_d6(n)
		if pred.call(rolls):
			RE.set_test_seed(s)
			return s
	RE.set_test_seed(-1)
	return -1


func _first_weapon(uid: String, ranged: bool) -> String:
	var ws: Dictionary = RE.get_unit_weapons(uid, GS.state) if ranged else RE.get_unit_melee_weapons(uid, GS.state)
	for mid in ws:
		for wid in ws[mid]:
			var prof: Dictionary = RE.get_weapon_profile(str(wid), GS.state)
			if ranged == (str(prof.get("type", "")).to_lower() != "melee"):
				return str(wid)
	return ""


## Total hits of one ranged batch (`uid` all models, weapon `wid`) vs `target`, seed `seed`.
func _ranged_hits(uid: String, wid: String, target: String, seed: int) -> int:
	var mids: Array = []
	for i in range(_u(uid).models.size()):
		mids.append(str(_u(uid).models[i].get("id", "m%d" % (i + 1))))
	var act := {"type": "SHOOT", "actor_unit_id": uid, "payload": {"assignments": [{"weapon_id": wid, "target_unit_id": target, "model_ids": mids}]}}
	var res = RE.resolve_shoot(act, GS.state.duplicate(true), RE.RNGService.new(seed))
	var hits := 0
	for d in res.get("dice", []):
		if str(d.get("context", "")) in ["to_hit", "hit_roll"]:
			hits += int(d.get("successes", 0))
	return hits


# ---------------------------------------------------------------------------
func _run() -> void:
	GS = root.get_node("GameState")
	SM = root.get_node("StratagemManager")
	RE = root.get_node("RulesEngine")
	PM = root.get_node("PhaseManager")
	OA = load("res://scripts/codex/orks/OrkAbilities11e.gd")
	EP = load("res://autoloads/EffectPrimitives.gd")
	var alm = root.get_node("ArmyListManager")
	for r in ROSTERS:
		# The same processing a loaded army gets (transport_data, ability-name
		# canon, wargear stat bonuses, model profiles).
		_rosters[r] = alm._process_army_data(_json(r), 1)
	print("\n=== test_ork_abilities_11e (WP-O6) ===")
	_section_names()
	_section_ammo_runts()
	_section_pulsa_rokkit()
	_section_bomb_squigs()
	_section_might_paired_tide()
	_section_meganobz()
	_section_kff_more_dakka()
	_section_prophet_ladz()
	_section_lone_operatives()
	_section_rokkit_charge_warpath()
	_section_krushin_motivation()
	_section_know_wotz()
	_section_makari()
	_section_found_em_skorchin()
	_section_gut_hatch_idol_beastscent()
	_section_supreme_kunnin()
	_section_reserves_abilities()
	_section_bombers()
	_section_post_shot()
	_section_heals()
	_section_full_throttle()
	_section_da_jump()
	_section_vehicle_passives()
	_section_beast_snagga()
	_section_misc_passives()
	_section_taktikal()
	_section_thatll_learn_ya()
	_section_shokk_boosta()
	_section_ai()
	_section_dropped()


# ---------------------------------------------------------------------------
# 0. every codex ability the rosters carry resolves to a module slug
# ---------------------------------------------------------------------------
func _section_names() -> void:
	print("\n-- 0. ability names fold to module slugs --")
	_fresh()
	_check("Boss' Ammo Runt (Warboss)", OA.has(_u("U_WARBOSS_A"), "boss_ammo_runt"))
	_check("Ammo Runts (Boyz, '(Once per battle, per unit)' suffix folded)", OA.has(_u("U_BOYZ_C"), "ammo_runts"))
	_check("Prophet of Da Great Waaagh! (Ghazghkull)", OA.has(_u("U_GHAZGHKULL_THRAKA_A"), "prophet"))
	_check("Da Bigger Dey iz... (Mozrog, '...' vs '…')", OA.has(_u("U_MOZROG_SKRAGBAD_A"), "da_bigger_dey_iz"))
	_check("Sumfin' to Prove (Bigboss)", OA.has(_u("U_BIGBOSS_A"), "sumfin_to_prove"))
	_check("no false positive: Boyz do not have Bomb Squigs", not OA.has(_u("U_BOYZ_C"), "bomb_squigs"))
	_check("Bomb Squig (singular) is not Bomb Squigs", OA.has(_u("U_SQUIGHOG_BOYZ_A"), "bomb_squig") and not OA.has(_u("U_SQUIGHOG_BOYZ_A"), "bomb_squigs"))


# ---------------------------------------------------------------------------
# 1. Boss' Ammo Runt / Ammo Runts (once per battle, +1 to hit, ranged)
# ---------------------------------------------------------------------------
func _section_ammo_runts() -> void:
	print("\n-- 1. Boss' Ammo Runt (this model) / Ammo Runts (this unit) --")
	_fresh(P_SHOOT)
	_place("U_BOYZ_C", 10, 30)
	_place("U_WARBOSS_A", 10, 31.5)
	_attach("U_WARBOSS_A", "U_BOYZ_C")
	var ctx := {"phase": "shooting", "unit_id": "U_BOYZ_C"}
	var o_bar := _offer(1, "unit_selected_to_shoot", ctx, "boss_ammo_runt")
	_check("Boss' Ammo Runt offered when the Warboss' attached unit is selected to shoot", _offer_units(o_bar) == ["U_WARBOSS_A"], str(_offer_units(o_bar)))
	var o_ar := _offer(1, "unit_selected_to_shoot", ctx, "ammo_runts")
	_check("Ammo Runts offered on the Boyz", _offer_units(o_ar) == ["U_BOYZ_C"], str(_offer_units(o_ar)))
	_check("not offered to the opponent", _offer(2, "unit_selected_to_shoot", ctx, "ammo_runts").is_empty())
	_check("not offered in another window", _offer(1, "unit_has_shot", ctx, "ammo_runts").is_empty())
	var before := _mods("U_BOYZ_C", "U_CUSTODIAN_GUARD_A", false)
	_check("before: no +1 to hit", not bool(before.hit_plus))
	var r := _use(1, "boss_ammo_runt", "U_WARBOSS_A", "unit_selected_to_shoot", ctx)
	_check("USE Boss' Ammo Runt succeeds (0 CP)", r.get("success", false) and int(GS.state.players["1"].cp) == 6, str(r.get("error", "")))
	_check("Warboss model batch: +1 to hit", bool(_mods("U_BOYZ_C", "U_CUSTODIAN_GUARD_A", false, "", ["U_WARBOSS_A:m1"]).hit_plus))
	_check("Boyz-only batch: no +1 (this MODEL's attacks)", not bool(_mods("U_BOYZ_C", "U_CUSTODIAN_GUARD_A", false, "", ["m1", "m2"]).hit_plus))
	_check("Boss' Ammo Runt: once per battle (no 2nd offer)", _offer(1, "unit_selected_to_shoot", ctx, "boss_ammo_runt").is_empty())
	r = _use(1, "ammo_runts", "U_BOYZ_C", "unit_selected_to_shoot", ctx)
	_check("USE Ammo Runts succeeds", r.get("success", false), str(r.get("error", "")))
	_check("Ammo Runts: the unit's ranged attacks have +1 to hit", bool(_mods("U_BOYZ_C", "U_CUSTODIAN_GUARD_A", false, "", ["m1"]).hit_plus))
	_check("Ammo Runts: melee attacks unaffected", not bool(_mods("U_BOYZ_C", "U_CUSTODIAN_GUARD_A", true).hit_plus))
	OA.on_phase_transition(P_SHOOT, P_CHG)
	_check("expires at the end of the phase", not bool(_mods("U_BOYZ_C", "U_CUSTODIAN_GUARD_A", false, "", ["m1"]).hit_plus))
	_phase(P_SHOOT)
	_check("Ammo Runts: once per battle", _offer(1, "unit_selected_to_shoot", ctx, "ammo_runts").is_empty())
	# A/B: the same seed, +1 to hit -> at least as many hits, more on some seed.
	_fresh(P_SHOOT)
	_place("U_BOYZ_D", 10, 40)
	var wid := _first_weapon("U_BOYZ_D", true)
	_place("U_CUSTODIAN_GUARD_A", 10, 46)
	var more := false
	var never_less := true
	for s in [3, 5, 7, 11, 13]:
		_flags("U_BOYZ_D").erase(OA.F_AMMO_RUNTS)
		var a := _ranged_hits("U_BOYZ_D", wid, "U_CUSTODIAN_GUARD_A", s)
		_flags("U_BOYZ_D")[OA.F_AMMO_RUNTS] = true
		var b := _ranged_hits("U_BOYZ_D", wid, "U_CUSTODIAN_GUARD_A", s)
		if b < a:
			never_less = false
		if b > a:
			more = true
	_check("A/B (same seeds): Ammo Runts never fewer hits, more on some seed", never_less and more, "weapon %s" % wid)


# ---------------------------------------------------------------------------
# 2. Pulsa Rokkit (once per battle; +1 AP and [LETHAL HITS] vs the selected MONSTER/VEHICLE)
# ---------------------------------------------------------------------------
func _section_pulsa_rokkit() -> void:
	print("\n-- 2. Pulsa Rokkit --")
	_fresh(P_SHOOT)
	var tb: Dictionary = _u("U_TANKBUSTAS_A")
	tb.meta.abilities.append({"name": "Pulsa Rokkit (Once per battle, per unit)", "type": "Wargear"})
	_place("U_TANKBUSTAS_A", 10, 20)
	var ctx := {"phase": "shooting", "unit_id": "U_TANKBUSTAS_A"}
	_check("no enemy MONSTER/VEHICLE within 24\": not offered", _offer(1, "unit_selected_to_shoot", ctx, "pulsa_rokkit").is_empty())
	# Orks vs Orks: give P2 a vehicle (the Gunwagon) within 24".
	_u("U_GUNWAGON_A")["owner"] = 2
	_place("U_GUNWAGON_A", 10, 35)
	var o := _offer(1, "unit_selected_to_shoot", ctx, "pulsa_rokkit")
	_check("offered with the enemy VEHICLE as the target option", _secondary_ids(o, "U_TANKBUSTAS_A") == ["U_GUNWAGON_A"], str(_secondary_ids(o, "U_TANKBUSTAS_A")))
	var bad := _use(1, "pulsa_rokkit", "U_TANKBUSTAS_A", "unit_selected_to_shoot", ctx, "U_CUSTODIAN_GUARD_A")
	_check("USE with an invalid target refused", not bad.get("success", true))
	var r := _use(1, "pulsa_rokkit", "U_TANKBUSTAS_A", "unit_selected_to_shoot", ctx, "U_GUNWAGON_A")
	_check("USE succeeds", r.get("success", false), str(r.get("error", "")))
	var m := _mods("U_TANKBUSTAS_A", "U_GUNWAGON_A", false)
	_check("vs the selected unit: +1 AP and [LETHAL HITS]", int(m.ap) == 1 and bool(m.lethal), str(m))
	var m2 := _mods("U_TANKBUSTAS_A", "U_CUSTODIAN_GUARD_A", false)
	_check("vs another unit: nothing", int(m2.ap) == 0 and not bool(m2.lethal))
	_check("once per battle", _offer(1, "unit_selected_to_shoot", ctx, "pulsa_rokkit").is_empty())


# ---------------------------------------------------------------------------
# 3. Bomb Squigs (once per turn, twice per battle) / Bomb Squig (once per battle)
# ---------------------------------------------------------------------------
func _section_bomb_squigs() -> void:
	print("\n-- 3. Bomb Squigs / Bomb Squig --")
	_fresh(P_MOV)
	_place("U_TANKBUSTAS_A", 10, 40)
	_place("U_CUSTODIAN_GUARD_A", 10, 48)
	var ctx := {"phase": "movement", "unit_id": "U_TANKBUSTAS_A"}
	var o := _offer(1, "unit_ended_normal_move", ctx, "bomb_squigs")
	_check("offered after a normal move with a visible enemy within 12\"", "U_CUSTODIAN_GUARD_A" in _secondary_ids(o, "U_TANKBUSTAS_A"), str(_secondary_ids(o, "U_TANKBUSTAS_A")))
	_check("not offered in the opponent's turn", _offer(2, "unit_ended_normal_move", {"phase": "movement", "unit_id": "U_TANKBUSTAS_A"}, "bomb_squigs").is_empty())
	_place("U_CUSTODIAN_GUARD_A", 10, 56)
	_check("enemy beyond 12\": not an option", not "U_CUSTODIAN_GUARD_A" in _secondary_ids(_offer(1, "unit_ended_normal_move", ctx, "bomb_squigs"), "U_TANKBUSTAS_A"))
	_place("U_CUSTODIAN_GUARD_A", 10, 48)
	# A/B: a seed where the D6 is 3+ (MW) and one where it is 1-2 (nothing).
	var hit_seed := _seed_where(1, func(r): return int(r[0]) >= 3)
	var miss_seed := _seed_where(1, func(r): return int(r[0]) <= 2)
	var w0 := _wounds_left("U_CUSTODIAN_GUARD_A")
	RE.set_test_seed(miss_seed)
	var r := _use(1, "bomb_squigs", "U_TANKBUSTAS_A", "unit_ended_normal_move", ctx, "U_CUSTODIAN_GUARD_A")
	_check("USE (D6 1-2): no mortal wounds", r.get("success", false) and _wounds_left("U_CUSTODIAN_GUARD_A") == w0, str(r.get("error", "")))
	_check("once per turn", _offer(1, "unit_ended_normal_move", ctx, "bomb_squigs").is_empty())
	GS.state.meta["battle_round"] = 3
	RE.set_test_seed(hit_seed)
	r = _use(1, "bomb_squigs", "U_TANKBUSTAS_A", "unit_ended_normal_move", ctx, "U_CUSTODIAN_GUARD_A")
	_check("USE next turn (D6 3+): D3 mortal wounds", r.get("success", false) and _wounds_left("U_CUSTODIAN_GUARD_A") < w0, "%d -> %d" % [w0, _wounds_left("U_CUSTODIAN_GUARD_A")])
	GS.state.meta["battle_round"] = 4
	_check("twice per battle: no third use", _offer(1, "unit_ended_normal_move", ctx, "bomb_squigs").is_empty())
	RE.set_test_seed(-1)
	# Bomb Squig (Squighog Boyz): once per battle.
	_place("U_SQUIGHOG_BOYZ_A", 20, 40)
	_place("U_CUSTODIAN_GUARD_B", 20, 47)
	var c2 := {"phase": "movement", "unit_id": "U_SQUIGHOG_BOYZ_A"}
	_check("Bomb Squig offered on Squighog Boyz", not _offer(1, "unit_ended_normal_move", c2, "bomb_squig").is_empty())
	r = _use(1, "bomb_squig", "U_SQUIGHOG_BOYZ_A", "unit_ended_normal_move", c2, "U_CUSTODIAN_GUARD_B")
	_check("USE Bomb Squig succeeds", r.get("success", false), str(r.get("error", "")))
	GS.state.meta["battle_round"] = 5
	_check("Bomb Squig: once per battle", _offer(1, "unit_ended_normal_move", c2, "bomb_squig").is_empty())


# ---------------------------------------------------------------------------
# 4. Might Is Right / Paired Krumpas / Tide of Muscle / Get Out da Way!
# ---------------------------------------------------------------------------
func _section_might_paired_tide() -> void:
	print("\n-- 4. Might Is Right / Paired Krumpas / Tide of Muscle / Get Out da Way! --")
	_fresh(P_FIGHT)
	_place("U_WARBOSS_A", 10, 30)
	_place("U_BOYZ_C", 20, 30)
	var m := _mods("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", true)
	_check("Might Is Right: no charge — no bonus", int(m.attacks) == 0 and int(m.strength) == 0)
	_flags("U_WARBOSS_A")["charged_this_turn"] = true
	m = _mods("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", true)
	_check("Might Is Right: charged — melee +3 A, +2 S", int(m.attacks) == 3 and int(m.strength) == 2, str(m))
	_check("Might Is Right: ranged unaffected", int(_mods("U_WARBOSS_A", "U_CUSTODIAN_GUARD_A", false).attacks) == 0)
	# A/B melee: total attacks with the same seed.
	var wid := _first_weapon("U_WARBOSS_A", false)
	_place("U_CUSTODIAN_GUARD_A", 10, 31.6)
	var act := {"type": "FIGHT", "actor_unit_id": "U_WARBOSS_A", "payload": {"assignments": [{"attacker": "U_WARBOSS_A", "target": "U_CUSTODIAN_GUARD_A", "weapon": wid}]}}
	var res_b = RE.resolve_melee_attacks(act, GS.state.duplicate(true), RE.RNGService.new(5))
	_flags("U_WARBOSS_A").erase("charged_this_turn")
	var res_a = RE.resolve_melee_attacks(act, GS.state.duplicate(true), RE.RNGService.new(5))
	var att_a := 0
	var att_b := 0
	for d in res_a.get("dice", []):
		if str(d.get("context", "")) == "hit_roll_melee":
			att_a += int(d.get("total_attacks", 0))
	for d in res_b.get("dice", []):
		if str(d.get("context", "")) == "hit_roll_melee":
			att_b += int(d.get("total_attacks", 0))
	_check("A/B melee (seed 5): charged Warboss makes 3 more attacks", att_b == att_a + 3, "%d vs %d (%s)" % [att_a, att_b, wid])
	# Paired Krumpas (wargear ability on the Kustom Krumpa).
	_u("U_NOBZ_A").meta.abilities.append({"name": "Paired Krumpas", "type": "Wargear"})
	_place("U_NOBZ_A", 10, 20)
	var pk := _mods("U_NOBZ_A", "U_CUSTODIAN_GUARD_A", true, "Kustom Krumpa")
	_check("Paired Krumpas: Kustom Krumpa re-rolls hits and wounds", str(pk.hit_reroll) == "failed" and str(pk.wound_reroll) == "failed", str(pk))
	var pk2 := _mods("U_NOBZ_A", "U_CUSTODIAN_GUARD_A", true, "Big Choppa")
	_check("Paired Krumpas: other weapons unaffected", str(pk2.hit_reroll) == "" and str(pk2.wound_reroll) == "")
	# Tide of Muscle.
	_check("Tide of Muscle: not charged — no [LETHAL HITS]", not bool(_mods("U_BOYZ_C", "U_CUSTODIAN_GUARD_A", true).lethal))
	_flags("U_BOYZ_C")["charged_this_turn"] = true
	_check("Tide of Muscle: charged, Fight phase — melee [LETHAL HITS]", bool(_mods("U_BOYZ_C", "U_CUSTODIAN_GUARD_A", true).lethal))
	_phase(P_SHOOT)
	_check("Tide of Muscle: only in the Fight phase", not bool(_mods("U_BOYZ_C", "U_CUSTODIAN_GUARD_A", true).lethal))
	# Get Out da Way! — the engine's charge move has no model-crossing gate (end overlap only).
	_check("Get Out da Way!: detected on Nobz", OA.charge_moves_through_models("U_NOBZ_A"))
	_check("Get Out da Way!: not on Boyz", not OA.charge_moves_through_models("U_BOYZ_C"))


# ---------------------------------------------------------------------------
# 5. Meganobz: Arrogant Invulnerability / Krumpin' Time
# ---------------------------------------------------------------------------
func _section_meganobz() -> void:
	print("\n-- 5. Arrogant Invulnerability / Krumpin' Time --")
	_fresh(P_FIGHT)
	_place("U_MEGANOBZ_B", 10, 30)
	var d: Dictionary = OA.defence_mods(_u("U_MEGANOBZ_B"), false)
	_check("Arrogant Invulnerability: incoming AP worsened by 1", int(d.ap_worsen) == 1)
	_check("EffectPrimitives.get_effect_worsen_ap reads it", int(EP.get_effect_worsen_ap(_u("U_MEGANOBZ_B"))) >= 1)
	var wid := _first_weapon("U_CUSTODIAN_GUARD_A", false)
	var prof: Dictionary = RE.get_weapon_profile(wid, GS.state)
	var sr: Dictionary = RE.prepare_melee_save_resolution(1, "U_MEGANOBZ_B", "U_CUSTODIAN_GUARD_A", prof, GS.state)
	_check("A/B save AP: Custodian %s AP %d -> %d vs Meganobz" % [wid, int(prof.get("ap", 0)), int(sr.get("ap", 99))],
		int(prof.get("ap", 0)) == 0 or int(sr.get("ap", 99)) == RE.worsen_ap(int(prof.get("ap", 0)), 1))
	_check("Krumpin' Time: not riled up — no bonus", not bool(_mods("U_MEGANOBZ_B", "U_CUSTODIAN_GUARD_A", true).hit_plus))
	_flags("U_MEGANOBZ_B")["ork11e_riled_up"] = true
	_check("Krumpin' Time: riled up in the Fight phase — +1 to hit", bool(_mods("U_MEGANOBZ_B", "U_CUSTODIAN_GUARD_A", true).hit_plus))
	_phase(P_SHOOT)
	_check("Krumpin' Time: not in the Shooting phase", not bool(_mods("U_MEGANOBZ_B", "U_CUSTODIAN_GUARD_A", false).hit_plus))


# ---------------------------------------------------------------------------
# 6. Kustom Force Field / More Dakka / Kustom Dakka / Even More Dakka / Nazdreg
# ---------------------------------------------------------------------------
func _section_kff_more_dakka() -> void:
	print("\n-- 6. Kustom Force Field / More Dakka / Kustom Dakka / Even More Dakka --")
	_fresh(P_SHOOT)
	_place("U_MEGANOBZ_B", 10, 30)
	_place("U_BIG_MEK_IN_MEGA_ARMOUR_A", 10, 32)
	_attach("U_BIG_MEK_IN_MEGA_ARMOUR_A", "U_MEGANOBZ_B")
	_check("Kustom Force Field: the whole attached unit has a 4+ invuln vs ranged", int(OA.defence_mods(_u("U_MEGANOBZ_B"), false).invuln) == 4)
	_check("Kustom Force Field: not vs melee", int(OA.defence_mods(_u("U_MEGANOBZ_B"), true).invuln) == 0)
	_check("EffectPrimitives.get_effect_invuln (Shooting phase) = 4", int(EP.get_effect_invuln(_u("U_MEGANOBZ_B"))) == 4)
	var m := _mods("U_MEGANOBZ_B", "U_CUSTODIAN_GUARD_A", false)
	_check("More Dakka: ranged [IGNORES COVER]", bool(m.ignores_cover))
	_check("More Dakka: not riled up — no [SUSTAINED HITS]", int(m.sustained) == 0)
	_flags("U_MEGANOBZ_B")["ork11e_riled_up"] = true
	_check("More Dakka: riled up — ranged [SUSTAINED HITS 1]", int(_mods("U_MEGANOBZ_B", "U_CUSTODIAN_GUARD_A", false).sustained) == 1)
	_place("U_MEK_A", 20, 30)
	_check("Kustom Dakka (Mek): ranged [IGNORES COVER]", bool(_mods("U_MEK_A", "U_CUSTODIAN_GUARD_A", false).ignores_cover))
	_check("Kustom Dakka: melee unaffected", not bool(_mods("U_MEK_A", "U_CUSTODIAN_GUARD_A", true).ignores_cover))
	_place("U_BIG_MEK_DAKKARIG_A", 30, 30)
	_check("Even More Dakka: not riled up — nothing", int(_mods("U_BIG_MEK_DAKKARIG_A", "U_CUSTODIAN_GUARD_A", false).sustained) == 0)
	_flags("U_BIG_MEK_DAKKARIG_A")["ork11e_riled_up"] = true
	_check("Even More Dakka: riled up — [SUSTAINED HITS 1]", int(_mods("U_BIG_MEK_DAKKARIG_A", "U_CUSTODIAN_GUARD_A", false).sustained) == 1)
	_place("U_NAZDREG_A", 40, 30)
	_check("Nazdreg's Know-wotz: ranged [IGNORES COVER]", bool(_mods("U_NAZDREG_A", "U_CUSTODIAN_GUARD_A", false).ignores_cover))


# ---------------------------------------------------------------------------
# 7. Prophet of da Great Waaagh! (Aura 6") / Da Grand Warlord's Ladz
# ---------------------------------------------------------------------------
func _section_prophet_ladz() -> void:
	print("\n-- 7. Prophet of da Great Waaagh! / Da Grand Warlord's Ladz --")
	_fresh(P_FIGHT)
	_place("U_GHAZGHKULL_THRAKA_A", 20, 20)
	_place("U_BOYZ_C", 20, 24)
	_place("U_BOYZ_D", 20, 40)
	var m := _mods("U_BOYZ_C", "U_CUSTODIAN_GUARD_A", true)
	_check("Prophet aura: ORKS unit within 6\" — melee +1 hit and +1 wound", bool(m.hit_plus) and bool(m.wound_plus), str(m.sources))
	var m2 := _mods("U_BOYZ_D", "U_CUSTODIAN_GUARD_A", true)
	_check("Prophet aura: unit beyond 6\" — nothing", not bool(m2.hit_plus) and not bool(m2.wound_plus))
	_check("Prophet aura: ranged attacks unaffected", not bool(_mods("U_BOYZ_C", "U_CUSTODIAN_GUARD_A", false).wound_plus))
	_check("Prophet aura: Ghazghkull is within his own aura", bool(_mods("U_GHAZGHKULL_THRAKA_A", "U_CUSTODIAN_GUARD_A", true).wound_plus))
	_place("U_BOYZ_C", 20, 40)
	_place("U_BOYZ_D", 30, 50)
	_check("Da Grand Warlord's Ladz: no ORKS INFANTRY within 3\" — no Lone Operative", not OA.conditional_lone_operative(_u("U_GHAZGHKULL_THRAKA_A")))
	_place("U_BOYZ_C", 20, 21.5)
	_check("Da Grand Warlord's Ladz: Boyz within 3\" — Lone Operative (RulesEngine.has_lone_operative)", RE.has_lone_operative(_u("U_GHAZGHKULL_THRAKA_A")))
	_attach("U_GHAZGHKULL_THRAKA_A", "U_MEGANOBZ_B")
	_place("U_MEGANOBZ_B", 20, 19)
	_place("U_BOYZ_C", 20, 40)
	_check("...his own bodyguard does not count", not OA.conditional_lone_operative(_u("U_GHAZGHKULL_THRAKA_A")))


# ---------------------------------------------------------------------------
# 8. conditional Lone Operative: Support Shokka / Boss of da Hunt / Beast
#    Snagga Following / Speednob Support
# ---------------------------------------------------------------------------
func _section_lone_operatives() -> void:
	print("\n-- 8. Support Shokka / Boss of da Hunt / Beast Snagga Following / Speednob Support --")
	_fresh(P_SHOOT)
	_place("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A", 10, 10)
	_check("Support Shokka: alone — no Lone Operative", not RE.has_lone_operative(_u("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A")))
	_place("U_BOYZ_C", 10, 12)
	_check("Support Shokka: within 3\" of Boyz — Lone Operative", RE.has_lone_operative(_u("U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A")))
	_place("U_BEASTBOSS_ON_SQUIGOSAUR_A", 30, 10)
	_place("U_MOZROG_SKRAGBAD_A", 40, 30)
	_check("Boss of da Hunt: alone — no", not OA.conditional_lone_operative(_u("U_BEASTBOSS_ON_SQUIGOSAUR_A")))
	_place("U_BEAST_SNAGGA_BOYZ_B", 30, 13)
	_check("Boss of da Hunt: within 3\" of Beast Snagga Boyz — Lone Operative", OA.conditional_lone_operative(_u("U_BEASTBOSS_ON_SQUIGOSAUR_A")))
	_check("Beast Snagga Following: Mozrog away from every BEAST SNAGGA unit — no", not OA.conditional_lone_operative(_u("U_MOZROG_SKRAGBAD_A")))
	_place("U_MOZROG_SKRAGBAD_A", 34, 15.5)
	_check("Beast Snagga Following: within 3\" of Beast Snagga Boyz — Lone Operative", OA.conditional_lone_operative(_u("U_MOZROG_SKRAGBAD_A")))
	_place("U_WARTRAKKS_A", 10, 30)
	_check("Speednob Support: alone — no", not OA.conditional_lone_operative(_u("U_WARTRAKKS_A")))
	_place("U_WARBIKERS_A", 10, 32)
	_check("Speednob Support: each model within 3\" of Speed Freeks — Lone Operative", OA.conditional_lone_operative(_u("U_WARTRAKKS_A")))


# ---------------------------------------------------------------------------
# 9. Rokkit Charge / Warpath (Weirdboy, Kill Rig)
# ---------------------------------------------------------------------------
func _section_rokkit_charge_warpath() -> void:
	print("\n-- 9. Rokkit Charge / Warpath --")
	_fresh(P_FIGHT)
	_place("U_STORMBOYZ_A", 10, 30)
	var ctx := {"phase": "fight", "unit_id": "U_STORMBOYZ_A"}
	_check("Rokkit Charge: not charged — not offered", _offer(1, "unit_selected_to_fight", ctx, "rokkit_charge").is_empty())
	_flags("U_STORMBOYZ_A")["charged_this_turn"] = true
	_check("Rokkit Charge: charged — offered", not _offer(1, "unit_selected_to_fight", ctx, "rokkit_charge").is_empty())
	var r := _use(1, "rokkit_charge", "U_STORMBOYZ_A", "unit_selected_to_fight", ctx)
	var m := _mods("U_STORMBOYZ_A", "U_CUSTODIAN_GUARD_A", true)
	_check("Rokkit Charge: melee +1 A, +1 S and [HAZARDOUS]", r.get("success", false) and int(m.attacks) == 1 and int(m.strength) == 1 and bool(_flags("U_STORMBOYZ_A").get("effect_grant_hazardous_melee", false)), str(m))
	_check("Rokkit Charge: not offered twice", _offer(1, "unit_selected_to_fight", ctx, "rokkit_charge").is_empty())
	OA.on_phase_transition(P_FIGHT, 11)
	_check("Rokkit Charge expires with the phase (and its [HAZARDOUS] grant)", not _flags("U_STORMBOYZ_A").has(OA.F_ROKKIT_CHARGE) and not _flags("U_STORMBOYZ_A").get("effect_grant_hazardous_melee", false))
	# Warpath — Weirdboy: re-roll wound rolls of 1 + [PSYCHIC]; Kill Rig: [LETHAL HITS] + [PSYCHIC].
	_fresh(P_FIGHT)
	_place("U_WEIRDBOY_A", 10, 30)
	_place("U_KILL_RIG_A", 30, 30)
	var cw := {"phase": "fight", "unit_id": "U_WEIRDBOY_A"}
	_check("Warpath offered on the Weirdboy when selected to fight", not _offer(1, "unit_selected_to_fight", cw, "warpath").is_empty())
	var seed2 := _seed_where(1, func(r): return int(r[0]) >= 2)
	RE.set_test_seed(seed2)
	r = _use(1, "warpath", "U_WEIRDBOY_A", "unit_selected_to_fight", cw)
	var mw := _mods("U_WEIRDBOY_A", "U_CUSTODIAN_GUARD_A", true)
	_check("Warpath (Weirdboy): melee re-roll wound rolls of 1 + [PSYCHIC]", r.get("success", false) and str(mw.wound_reroll) == "ones" and bool(mw.psychic), str(mw))
	_check("psychic roll 2+: not battle-shocked", not _flags("U_WEIRDBOY_A").get("battle_shocked", false))
	_check("Warpath: not offered again this phase", _offer(1, "unit_selected_to_fight", cw, "warpath").is_empty())
	var ck := {"phase": "fight", "unit_id": "U_KILL_RIG_A"}
	r = _use(1, "warpath", "U_KILL_RIG_A", "unit_selected_to_fight", ck)
	var mk := _mods("U_KILL_RIG_A", "U_CUSTODIAN_GUARD_A", true)
	_check("Warpath (Kill Rig, Wurrboy): melee [LETHAL HITS] + [PSYCHIC]", r.get("success", false) and bool(mk.lethal) and bool(mk.psychic), str(mk))
	var seed1 := _seed_where(1, func(r): return int(r[0]) == 1)
	_fresh(P_FIGHT)
	_place("U_WEIRDBOY_A", 10, 30)
	RE.set_test_seed(seed1)
	r = _use(1, "warpath", "U_WEIRDBOY_A", "unit_selected_to_fight", cw)
	_check("psychic roll of 1: the unit is battle-shocked (effect still applies)", r.get("success", false) and _flags("U_WEIRDBOY_A").get("battle_shocked", false) and str(_mods("U_WEIRDBOY_A", "U_CUSTODIAN_GUARD_A", true).wound_reroll) == "ones")
	_check("battle-shocked: Warpath not offered", _offer(1, "unit_selected_to_fight", cw, "warpath").is_empty())
	RE.set_test_seed(-1)


# ---------------------------------------------------------------------------
# 10. Krushin' Impetus / Intimidating Motivation / Get Back in da Race! / Keep Huntin'!
# ---------------------------------------------------------------------------
func _section_krushin_motivation() -> void:
	print("\n-- 10. Krushin' Impetus / Intimidating Motivation / Get Back in da Race! / Keep Huntin'! --")
	_fresh(P_CHG)
	_place("U_WARBOSS_IN_MEGA_ARMOUR_A", 10, 51)
	_place("U_CUSTODIAN_GUARD_A", 9, 52.4)
	var ctx := {"phase": "charge", "unit_id": "U_WARBOSS_IN_MEGA_ARMOUR_A"}
	var o := _offer(1, "unit_ended_charge_move", ctx, "krushin_impetus")
	_check("Krushin' Impetus offered with the engaged enemy", "U_CUSTODIAN_GUARD_A" in _secondary_ids(o, "U_WARBOSS_IN_MEGA_ARMOUR_A"), str(_secondary_ids(o, "U_WARBOSS_IN_MEGA_ARMOUR_A")))
	var w0 := _wounds_left("U_CUSTODIAN_GUARD_A")
	var s3 := _seed_where(1, func(r): return int(r[0]) >= 3)
	RE.set_test_seed(s3)
	var r := _use(1, "krushin_impetus", "U_WARBOSS_IN_MEGA_ARMOUR_A", "unit_ended_charge_move", ctx, "U_CUSTODIAN_GUARD_A")
	_check("Krushin' Impetus: one D6 per engaged model, 3+ = 1 MW", r.get("success", false) and _wounds_left("U_CUSTODIAN_GUARD_A") == w0 - 1, "%d -> %d" % [w0, _wounds_left("U_CUSTODIAN_GUARD_A")])
	RE.set_test_seed(-1)
	_place("U_CUSTODIAN_GUARD_A", 30, 52)
	_check("Krushin' Impetus: nothing engaged — not offered", _offer(1, "unit_ended_charge_move", ctx, "krushin_impetus").is_empty())
	# Intimidating Motivation (once per battle round, per army).
	_fresh(P_MOV)
	_place("U_WARBOSS_A", 10, 30)
	_place("U_BOYZ_C", 10, 33)
	_flags("U_BOYZ_C")["battle_shocked"] = true
	var c2 := {"phase": "movement", "unit_id": "U_WARBOSS_A", "move_type": "normal"}
	o = _offer(1, "unit_selected_to_move", c2, "intimidating_motivation")
	_check("Intimidating Motivation: offered at the start of the move (friendly ORKS within 6\")", "U_BOYZ_C" in _secondary_ids(o, "U_WARBOSS_A"))
	_check("Intimidating Motivation: also at the end of a normal move", not _offer(1, "unit_ended_normal_move", c2, "intimidating_motivation").is_empty())
	r = _use(1, "intimidating_motivation", "U_WARBOSS_A", "unit_selected_to_move", c2, "U_BOYZ_C")
	_check("USE: Boyz no longer battle-shocked and riled up", r.get("success", false) and not _flags("U_BOYZ_C").get("battle_shocked", false) and OA.group_riled_up("U_BOYZ_C"))
	_place("U_NAZDREG_A", 24, 30)
	var cn := {"phase": "movement", "unit_id": "U_NAZDREG_A", "move_type": "normal"}
	_check("once per battle round PER ARMY: Nazdreg's Intimidating Motivation not offered", _offer(1, "unit_selected_to_move", cn, "intimidating_motivation").is_empty())
	# riled up until the start of your next turn.
	OA.on_phase_transition(P_MOV, P_SHOOT)
	_check("still riled up later this turn", OA.group_riled_up("U_BOYZ_C"))
	_phase(P_CMD, 2)
	OA.on_phase_transition(11, P_CMD)
	_check("still riled up in the opponent's turn", OA.group_riled_up("U_BOYZ_C"))
	GS.state.meta["battle_round"] = 3
	_phase(P_CMD, 1)
	OA.on_phase_transition(11, P_CMD)
	_check("riled up ends at the start of your next turn", not OA.group_riled_up("U_BOYZ_C"))
	_phase(P_MOV, 1)
	_check("next battle round: offered again (Nazdreg too)", not _offer(1, "unit_selected_to_move", c2, "intimidating_motivation").is_empty() and not _offer(1, "unit_selected_to_move", cn, "intimidating_motivation").is_empty())
	# Get Back in da Race! — SPEED FREEKS only; Keep Huntin'! — BEAST SNAGGA only.
	_fresh(P_MOV)
	_place("U_DEFFKILLA_WARTRIKE_A", 10, 30)
	_place("U_WARBIKERS_A", 10, 33)
	_place("U_BOYZ_C", 14, 30)
	var c3 := {"phase": "movement", "unit_id": "U_DEFFKILLA_WARTRIKE_A", "move_type": "normal"}
	var opts := _secondary_ids(_offer(1, "unit_selected_to_move", c3, "get_back_in_da_race"), "U_DEFFKILLA_WARTRIKE_A")
	_check("Get Back in da Race!: SPEED FREEKS options only", "U_WARBIKERS_A" in opts and not "U_BOYZ_C" in opts, str(opts))
	_place("U_BEASTBOSS_A", 30, 30)
	_place("U_BEAST_SNAGGA_BOYZ_B", 30, 33)
	var opts2 := _secondary_ids(_offer(1, "unit_selected_to_move", {"phase": "movement", "unit_id": "U_BEASTBOSS_A", "move_type": "normal"}, "keep_huntin"), "U_BEASTBOSS_A")
	_check("Keep Huntin'!: BEAST SNAGGA options only", "U_BEAST_SNAGGA_BOYZ_B" in opts2 and not "U_BOYZ_C" in opts2, str(opts2))


# ---------------------------------------------------------------------------
# 11. Clever Know-wotz (Mek)
# ---------------------------------------------------------------------------
func _section_know_wotz() -> void:
	print("\n-- 11. Clever Know-wotz --")
	_fresh(P_MOV)
	_place("U_MEK_A", 10, 30)
	_place("U_GUNWAGON_A", 10, 32)
	_wound("U_GUNWAGON_A", 4)
	var w0 := _wounds_left("U_GUNWAGON_A")
	var ctx := {"phase": "movement", "unit_id": "U_MEK_A", "move_type": "normal"}
	var o := _offer(1, "unit_selected_to_move", ctx, "clever_know_wotz")
	_check("offered with the ORKS VEHICLE within 3\"", "U_GUNWAGON_A" in _secondary_ids(o, "U_MEK_A"), str(_secondary_ids(o, "U_MEK_A")))
	var r := _use(1, "clever_know_wotz", "U_MEK_A", "unit_selected_to_move", ctx, "U_GUNWAGON_A")
	_check("heals D3 wounds", r.get("success", false) and _wounds_left("U_GUNWAGON_A") > w0 and _wounds_left("U_GUNWAGON_A") <= w0 + 3, "%d -> %d" % [w0, _wounds_left("U_GUNWAGON_A")])
	_check("its attacks have +1 to hit", bool(_mods("U_GUNWAGON_A", "U_CUSTODIAN_GUARD_A", false).hit_plus))
	_check("once per phase per Mek", _offer(1, "unit_ended_normal_move", ctx, "clever_know_wotz").is_empty())
	_place("U_STOMPA_B", 14, 30)
	OA.on_phase_transition(P_MOV, P_SHOOT)
	_check("+1 to hit survives into the Shooting phase", bool(_mods("U_GUNWAGON_A", "U_CUSTODIAN_GUARD_A", false).hit_plus))
	GS.state.meta["battle_round"] = 3
	OA.on_phase_transition(P_CMD, P_MOV)
	_check("+1 to hit ends at the start of your next Movement phase", not bool(_mods("U_GUNWAGON_A", "U_CUSTODIAN_GUARD_A", false).hit_plus))
	_check("TITANIC vehicles are not eligible", not "U_STOMPA_B" in _secondary_ids(_offer(1, "unit_selected_to_move", ctx, "clever_know_wotz"), "U_MEK_A"))


# ---------------------------------------------------------------------------
# 12. Makari, Hoist Dat Banner! (once per battle, up to battle-round-number units)
# ---------------------------------------------------------------------------
func _section_makari() -> void:
	print("\n-- 12. Makari, Hoist Dat Banner! --")
	_fresh(P_MOV, 1, 2)
	_place("U_GHAZGHKULL_THRAKA_A", 10, 10)
	_place("U_BOYZ_C", 10, 30)
	_place("U_BOYZ_D", 30, 30)
	_place("U_MEGANOBZ_B", 40, 30)
	var ctx := {"phase": "movement"}
	var o := _offer(1, "movement_phase_start", ctx, "makari")
	_check("offered at the start of the Movement phase", not o.is_empty())
	var r := _use(1, "makari", "U_GHAZGHKULL_THRAKA_A", "movement_phase_start", ctx, "U_BOYZ_C")
	_check("1st pick riled up + re-offer follow-up", r.get("success", false) and OA.group_riled_up("U_BOYZ_C") and str(r.get("followup", {}).get("type", "")) == "ork11e_reoffer")
	o = _offer(1, "movement_phase_start", ctx, "makari")
	_check("2nd pick offered (battle round 2), the 1st is no option", not o.is_empty() and not "U_BOYZ_C" in _secondary_ids(o, "U_GHAZGHKULL_THRAKA_A"))
	r = _use(1, "makari", "U_GHAZGHKULL_THRAKA_A", "movement_phase_start", ctx, "U_BOYZ_D")
	_check("2nd pick riled up", r.get("success", false) and OA.group_riled_up("U_BOYZ_D"))
	_check("no 3rd pick in battle round 2", _offer(1, "movement_phase_start", ctx, "makari").is_empty())
	GS.state.meta["battle_round"] = 4
	_check("once per battle", _offer(1, "movement_phase_start", ctx, "makari").is_empty())


# ---------------------------------------------------------------------------
# 13. Found 'Em! / Drive-by Skorchin'
# ---------------------------------------------------------------------------
func _section_found_em_skorchin() -> void:
	print("\n-- 13. Found 'Em! / Drive-by Skorchin' --")
	_fresh(P_MOV)
	_place("U_KOMMANDOS_A", 10, 40)
	_place("U_CUSTODIAN_GUARD_A", 10, 48)
	var ctx := {"phase": "movement", "unit_id": "U_KOMMANDOS_A", "move_type": "normal"}
	var tm = root.get_node("TerrainManager")
	var base_det: float = tm.detection_range_base_inches(_u("U_CUSTODIAN_GUARD_A"))
	var r := _use(1, "found_em", "U_KOMMANDOS_A", "unit_selected_to_move", ctx, "U_CUSTODIAN_GUARD_A")
	var det: float = tm.detection_range_inches_for(_u("U_CUSTODIAN_GUARD_A").models[0], _u("U_CUSTODIAN_GUARD_A"), _u("U_KOMMANDOS_A").models[0])
	_check("Found 'Em!: target +3\" detection range (TerrainManager)", r.get("success", false) and is_equal_approx(det, base_det + 3.0), "%.1f vs base %.1f" % [det, base_det])
	_check("Found 'Em!: once per phase", _offer(1, "unit_ended_normal_move", ctx, "found_em").is_empty())
	OA.on_phase_transition(P_MOV, P_SHOOT)
	_check("still +3\" later this turn", OA.detection_range_bonus(_u("U_CUSTODIAN_GUARD_A")) == 3.0)
	OA.on_phase_transition(11, P_CMD)
	_check("ends at the end of the turn", OA.detection_range_bonus(_u("U_CUSTODIAN_GUARD_A")) == 0.0)
	# Drive-by Skorchin' (Warbuggies)
	_fresh(P_MOV)
	_place("U_WARBUGGIES_A", 10, 44)
	_place("U_CUSTODIAN_GUARD_A", 10, 48)
	var c2 := {"phase": "movement", "unit_id": "U_WARBUGGIES_A", "move_type": "normal"}
	var o := _offer(1, "unit_ended_normal_move", c2, "drive_by_skorchin")
	_check("Drive-by Skorchin': non-MONSTER/VEHICLE enemy within 6\" offered", "U_CUSTODIAN_GUARD_A" in _secondary_ids(o, "U_WARBUGGIES_A"), str(_secondary_ids(o, "U_WARBUGGIES_A")))
	r = _use(1, "drive_by_skorchin", "U_WARBUGGIES_A", "unit_ended_normal_move", c2, "U_CUSTODIAN_GUARD_A")
	_check("the enemy cannot be targeted with Fire Overwatch", r.get("success", false) and OA.blocks_fire_overwatch("U_CUSTODIAN_GUARD_A"))
	var ow: Array = SM.get_fire_overwatch_eligible_units(2, "U_WARBUGGIES_A", GS.state).map(func(e): return str(e.get("unit_id", "")))
	_check("StratagemManager's Fire Overwatch eligibility skips it (other Custodians still eligible)", not "U_CUSTODIAN_GUARD_A" in ow and "U_CUSTODIAN_GUARD_B" in ow, str(ow))


# ---------------------------------------------------------------------------
# 14. Gut Hatch / Idol of Belligerence / Beastscent
# ---------------------------------------------------------------------------
func _section_gut_hatch_idol_beastscent() -> void:
	print("\n-- 14. Gut Hatch / Idol of Belligerence / Beastscent --")
	_fresh(P_MOV)
	_place("U_MORKANAUT_A", 10, 30)
	var ctx := {"phase": "movement", "unit_id": "U_MORKANAUT_A"}
	_check("Gut Hatch: nobody embarked — not offered", _offer(1, "unit_ended_normal_move", ctx, "gut_hatch").is_empty())
	_embark("U_BOYZ_C", "U_MORKANAUT_A")
	var r := _use(1, "gut_hatch", "U_MORKANAUT_A", "unit_ended_normal_move", ctx)
	_check("Gut Hatch: assault_disembark follow-up", r.get("success", false) and str(r.get("followup", {}).get("type", "")) == "assault_disembark", str(r.get("followup", {})))
	_place("U_STOMPA_B", 30, 30)
	_embark("U_BOYZ_D", "U_STOMPA_B")
	var d: Array = OA.on_disembark("U_BOYZ_D", "U_STOMPA_B")
	_check("Idol of Belligerence: the disembarking unit is riled up", not d.is_empty() and OA.group_riled_up("U_BOYZ_D"))
	_check("...until the start of your next turn", str(_flags("U_BOYZ_D").get(OA.F_RILED, {}).get("until", "")) == "start_of_your_next_turn")
	_phase(P_MOV, 2)
	_place("U_BOYZ_C", 40, 30)
	_check("Idol: not in the opponent's turn", OA.on_disembark("U_BOYZ_C", "U_STOMPA_B").is_empty())
	_phase(P_MOV, 1)
	_place("U_KILL_RIG_A", 10, 45)
	_embark("U_NOBZ_A", "U_KILL_RIG_A")
	OA.on_disembark("U_NOBZ_A", "U_KILL_RIG_A")
	_check("Beastscent: disembarking unit +1 to wound vs MONSTER/VEHICLE", bool(_mods("U_NOBZ_A", "U_GUNWAGON_A", true).wound_plus) or bool(_mods("U_NOBZ_A", "U_STOMPA_B", true).wound_plus) or _flags("U_NOBZ_A").has(OA.F_BEASTSCENT))
	_check("Beastscent: not vs INFANTRY", not bool(_mods("U_NOBZ_A", "U_CUSTODIAN_GUARD_A", true).wound_plus))


# ---------------------------------------------------------------------------
# 15. Supreme Kunnin' (Nazdreg)
# ---------------------------------------------------------------------------
func _section_supreme_kunnin() -> void:
	print("\n-- 15. Supreme Kunnin' --")
	_fresh(P_MOV, 2)
	_place("U_NAZDREG_A", 10, 40)
	_place("U_CUSTODIAN_GUARD_A", 10, 46)
	var ctx := {"phase": "movement", "enemy_unit_id": "U_CUSTODIAN_GUARD_A"}
	var o := _offer(1, "enemy_ended_move", ctx, "supreme_kunnin")
	_check("offered when an enemy ends a move within 8\" (opponent's turn)", _offer_units(o) == ["U_NAZDREG_A"])
	_check("variants: D6\" only while not riled up", o.get("targets", [{}])[0].get("variants", []).size() == 1)
	_flags("U_NAZDREG_A")["ork11e_riled_up"] = true
	o = _offer(1, "enemy_ended_move", ctx, "supreme_kunnin")
	_check("riled up: the 5\" option too", o.get("targets", [{}])[0].get("variants", []).size() == 2)
	var r := _use(1, "supreme_kunnin", "U_NAZDREG_A", "enemy_ended_move", ctx, "", "riled5")
	_check("USE: reactive normal move follow-up of up to 5\"", r.get("success", false) and str(r.followup.type) == "reactive_normal_move" and float(r.followup.max_inches) == 5.0, str(r.get("followup", {})))
	_check("once per phase per army", _offer(1, "enemy_ended_move", ctx, "supreme_kunnin").is_empty())
	_phase(P_MOV, 1)
	_check("not in your own turn", OA._targets("supreme_kunnin", 1, "enemy_ended_move", ctx).is_empty())


# ---------------------------------------------------------------------------
# 16. Kunnin' Infiltrator / Aerial Manoover / Shokk Attack Engine (strategic reserves)
# ---------------------------------------------------------------------------
func _section_reserves_abilities() -> void:
	print("\n-- 16. Kunnin' Infiltrator / Aerial Manoover --")
	_fresh(P_FIGHT, 2)
	_place("U_DEFFKOPTAS_A", 10, 30)
	var ctx := {"phase": "fight"}
	var o := _offer(1, "fight_phase_end", ctx, "aerial_manoover")
	_check("Aerial Manoover: end of the opponent's Fight phase, unengaged — offered", "U_DEFFKOPTAS_A" in _offer_units(o))
	var r := _use(1, "aerial_manoover", "U_DEFFKOPTAS_A", "fight_phase_end", ctx)
	_check("Aerial Manoover: placed in strategic reserves", r.get("success", false) and int(_u("U_DEFFKOPTAS_A").get("status", 0)) == 7, str(_u("U_DEFFKOPTAS_A").get("status")))
	_place("U_BOSS_SNIKROT_A", 30, 30)
	_check("Kunnin' Infiltrator: not hidden (no dense terrain) — not offered", not "U_BOSS_SNIKROT_A" in _offer_units(_offer(1, "fight_phase_end", ctx, "kunnin_infiltrator")))
	_phase(P_FIGHT, 1)
	_check("not in your own Fight phase", _offer(1, "fight_phase_end", ctx, "aerial_manoover").is_empty())


# ---------------------------------------------------------------------------
# 17. Burna Bomb / Boom Bomb
# ---------------------------------------------------------------------------
func _section_bombers() -> void:
	print("\n-- 17. Burna Bomb / Boom Bomb --")
	_fresh(P_FIGHT, 2)
	_place("U_BURNA_BOMMER_A", 10, 30)
	_place("U_CUSTODIAN_GUARD_A", 10, 50)
	var ctx := {"phase": "fight"}
	var o := _offer(1, "fight_phase_end", ctx, "burna_bomb")
	_check("Burna Bomb offered (end of the opponent's Fight phase, visible enemy within 36\")", "U_CUSTODIAN_GUARD_A" in _secondary_ids(o, "U_BURNA_BOMMER_A"), str(_secondary_ids(o, "U_BURNA_BOMMER_A")))
	var s2 := _seed_where(1, func(r): return int(r[0]) >= 2)
	RE.set_test_seed(s2)
	var w0 := _wounds_left("U_CUSTODIAN_GUARD_A")
	var r := _use(1, "burna_bomb", "U_BURNA_BOMMER_A", "fight_phase_end", ctx, "U_CUSTODIAN_GUARD_A")
	_check("Burna Bomb (2+): D3 mortal wounds", r.get("success", false) and _wounds_left("U_CUSTODIAN_GUARD_A") < w0)
	_check("...the unit cannot be hidden", OA.cannot_be_hidden(_u("U_CUSTODIAN_GUARD_A")) and not root.get_node("TerrainManager").is_model_hidden(_u("U_CUSTODIAN_GUARD_A").models[0], _u("U_CUSTODIAN_GUARD_A")))
	_phase(P_SHOOT, 1)
	_place("U_BOYZ_C", 10, 40)
	_check("...ranged attacks against it have [IGNORES COVER] (Burna-bommer's player)", bool(_mods("U_BOYZ_C", "U_CUSTODIAN_GUARD_A", false).ignores_cover))
	OA.on_phase_transition(P_FIGHT, P_CMD)  # P1's next turn begins
	_check("...still active during the user's next turn", OA.cannot_be_hidden(_u("U_CUSTODIAN_GUARD_A")))
	_phase(P_CMD, 2)
	OA.on_phase_transition(11, P_CMD)
	_check("...ends after the user's next turn", not OA.cannot_be_hidden(_u("U_CUSTODIAN_GUARD_A")))
	RE.set_test_seed(-1)
	_fresh(P_FIGHT, 2)
	_place("U_BLITZA_BOMMER_A", 10, 30)
	_place("U_CUSTODIAN_GUARD_A", 10, 50)
	w0 = _wounds_left("U_CUSTODIAN_GUARD_A")
	r = _use(1, "boom_bomb", "U_BLITZA_BOMMER_A", "fight_phase_end", ctx, "U_CUSTODIAN_GUARD_A")
	_check("Boom Bomb: always inflicts mortal wounds (D3 / 3 / D3+3)", r.get("success", false) and _wounds_left("U_CUSTODIAN_GUARD_A") < w0)
	_check("Boom Bomb: one drop per phase (the trigger happens once)", not "U_BLITZA_BOMMER_A" in _offer_units(_offer(1, "fight_phase_end", ctx, "boom_bomb")))
	_flags("U_BLITZA_BOMMER_A").erase(OA.F_USES)
	_check("Boom Bomb: offered again once the use is cleared (control)", "U_BLITZA_BOMMER_A" in _offer_units(_offer(1, "fight_phase_end", ctx, "boom_bomb")))
	_place("U_CUSTODIAN_GUARD_A", 10, 58)
	_place("U_BLITZA_BOMMER_A", 10, 30)
	_check("Boom Bomb: enemy beyond 24\" — not an option", not "U_CUSTODIAN_GUARD_A" in _secondary_ids(_offer(1, "fight_phase_end", ctx, "boom_bomb"), "U_BLITZA_BOMMER_A"))


# ---------------------------------------------------------------------------
# 18. post-shot: Rokkit Barrage / Squig Barrage / Bust 'Em / Madcap Artillery
# ---------------------------------------------------------------------------
func _section_post_shot() -> void:
	print("\n-- 18. Rokkit Barrage / Squig Barrage / Bust 'Em / Madcap Artillery --")
	_fresh(P_SHOOT)
	_place("U_TANKBUSTAS_A", 10, 30)
	var ctx := {"phase": "shooting", "unit_id": "U_TANKBUSTAS_A", "hit_unit_ids": ["U_CUSTODIAN_GUARD_A", "U_CUSTODIAN_GUARD_B"]}
	var o := _offer(1, "unit_has_shot", ctx, "rokkit_barrage")
	_check("Rokkit Barrage: 2 units hit — offered with both", _secondary_ids(o, "U_TANKBUSTAS_A").size() == 2, str(_secondary_ids(o, "U_TANKBUSTAS_A")))
	var r := _use(1, "rokkit_barrage", "U_TANKBUSTAS_A", "unit_has_shot", ctx, "U_CUSTODIAN_GUARD_B")
	_check("USE: the selected unit makes a battle-shock roll", r.get("success", false))
	_check("once per phase", _offer(1, "unit_has_shot", ctx, "rokkit_barrage").is_empty())
	# one unit hit -> resolved automatically by after_unit_shot
	_fresh(P_SHOOT)
	_place("U_TANKBUSTAS_A", 10, 30)
	var ld = OA.best_leadership("U_CUSTODIAN_GUARD_A")
	var shocked_seed := _seed_where(2, func(r): return int(r[0]) + int(r[1]) - 1 < ld and int(r[0]) + int(r[1]) >= ld)
	RE.set_test_seed(shocked_seed)
	var diffs: Array = OA.after_unit_shot("U_TANKBUSTAS_A", ["U_CUSTODIAN_GUARD_A"])
	_check("1 unit hit: Rokkit Barrage resolves automatically (a roll that passes at +0 fails at -1)", _flags("U_CUSTODIAN_GUARD_A").get("battle_shocked", false), str(diffs))
	RE.set_test_seed(-1)
	# Squig Barrage (Rukkatrukk Squigbuggies)
	_fresh(P_SHOOT)
	_place("U_RUKKATRUKK_SQUIGBUGGIES_A", 10, 30)
	OA.after_unit_shot("U_RUKKATRUKK_SQUIGBUGGIES_A", ["U_CUSTODIAN_GUARD_A"])
	_place("U_BOYZ_C", 10, 20)
	_check("Squig Barrage: the hit unit's attacks have -1 to hit", bool(OA.attack_mods(_u("U_CUSTODIAN_GUARD_A"), _u("U_BOYZ_C"), {"name": "x"}, true, GS.state).hit_minus))
	# Bust 'Em (Wartrakks): SPEED FREEKS attacks vs it have [LETHAL HITS]
	_fresh(P_SHOOT)
	_place("U_WARTRAKKS_A", 10, 30)
	_place("U_WARBIKERS_A", 20, 30)
	_place("U_BOYZ_C", 30, 30)
	OA.after_unit_shot("U_WARTRAKKS_A", ["U_CUSTODIAN_GUARD_A"])
	_check("Bust 'Em: SPEED FREEKS attacks vs it have [LETHAL HITS]", bool(_mods("U_WARBIKERS_A", "U_CUSTODIAN_GUARD_A", false).lethal))
	_check("Bust 'Em: other ORKS units do not", not bool(_mods("U_BOYZ_C", "U_CUSTODIAN_GUARD_A", false).lethal))
	OA.on_phase_transition(11, P_CMD)
	_check("Bust 'Em: ends at the end of the turn", not bool(_mods("U_WARBIKERS_A", "U_CUSTODIAN_GUARD_A", false).lethal))
	# Madcap Artillery — weapon-dependent effect (every Mek Gun the same weapon).
	_fresh(P_SHOOT)
	_place("U_MEK_GUNZ_A", 10, 30)
	var mg: Dictionary = _u("U_MEK_GUNZ_A")
	var only_traktor: Array = []
	for w in mg.meta.get("weapons", []):
		if str(w.get("name", "")).to_lower().contains("traktor") or str(w.get("type", "")).to_lower() == "melee":
			only_traktor.append(w)
	mg.meta["weapons"] = only_traktor
	OA.after_unit_shot("U_MEK_GUNZ_A", ["U_CUSTODIAN_GUARD_A"])
	_check("Madcap Artillery (Traktor Kannon): the hit unit is grounded — cannot take to the skies", OA.cannot_take_to_skies("U_CUSTODIAN_GUARD_A"), str(_flags("U_CUSTODIAN_GUARD_A").get(OA.F_MADCAP, null)))
	# The equipped gun comes from the roster's wargear (MA-LOADOUT), not the
	# datasheet's full option list.
	_fresh(P_SHOOT)
	_place("U_MEK_GUNZ_A", 10, 30)
	_check("Madcap Artillery: every option listed, no wargear — no single weapon, no effect", OA._madcap_effect("U_MEK_GUNZ_A") == "")
	_u("U_MEK_GUNZ_A").meta["wargear"] = ["1x Smasha Gun"]
	_u("U_MEK_GUNZ_A").erase("_loadout_version")
	for m in _u("U_MEK_GUNZ_A").models:
		m.erase("ranged_loadout")
	_check("Madcap Artillery: wargear '1x Smasha Gun' — smashed", OA._madcap_effect("U_MEK_GUNZ_A") == "smashed", OA._madcap_effect("U_MEK_GUNZ_A"))
	_flags("U_CUSTODIAN_GUARD_B")[OA.F_MADCAP] = {"player": 1, "effect": "smashed"}
	_check("Madcap 'smashed': -2\" M", OA.move_modifier(_u("U_CUSTODIAN_GUARD_B")) == -2.0)
	_flags("U_CUSTODIAN_GUARD_C")[OA.F_MADCAP] = {"player": 1, "effect": "zapped"}
	_check("Madcap 'zapped': -1 Ld (needs 1 more on the battle-shock roll)", OA.leadership_penalty("U_CUSTODIAN_GUARD_C") == 1)
	_flags("U_CUSTODIAN_GUARD_C")[OA.F_MADCAP] = {"player": 1, "effect": "wobbled"}
	_check("Madcap 'wobbled': its targets have the benefit of cover", bool(OA.attack_mods(_u("U_CUSTODIAN_GUARD_C"), _u("U_BOYZ_C"), {"name": "x"}, false, GS.state).target_cover))


# ---------------------------------------------------------------------------
# 19. Crude Surgery + Catch Dat Red Bit / Fix Dat Armour Up / Push Dat Bit Back In
# ---------------------------------------------------------------------------
func _section_heals() -> void:
	print("\n-- 19. Crude Surgery / Catch Dat Red Bit / Fix Dat Armour Up / Push Dat Bit Back In --")
	_fresh(P_CMD)
	_place("U_BOYZ_C", 10, 30)
	_place("U_PAINBOY_A", 10, 31.5)
	_attach("U_PAINBOY_A", "U_BOYZ_C")
	for i in [8, 9]:
		_u("U_BOYZ_C").models[i]["alive"] = false
		_u("U_BOYZ_C").models[i]["current_wounds"] = 0
	var ctx := {"phase": "command"}
	var o := _offer(1, "battle_shock_step_start", ctx, "crude_surgery")
	_check("Crude Surgery offered (wounds lost), with the Catch Dat Red Bit option", "U_PAINBOY_A" in _offer_units(o) and o.targets[0].get("variants", []).size() == 2)
	var r := _use(1, "crude_surgery", "U_PAINBOY_A", "battle_shock_step_start", ctx, "", "heal3")
	_check("heal 3: two destroyed Boyz return (1 wound each) ...", r.get("success", false) and _alive("U_BOYZ_C") == 10, str(_alive("U_BOYZ_C")))
	_check("once per Command phase", _offer(1, "battle_shock_step_start", ctx, "crude_surgery").is_empty())
	# Crude Surgery is automatic: unused at the end of the Command phase -> auto heal 3.
	_fresh(P_CMD)
	_place("U_BOYZ_C", 10, 30)
	_place("U_PAINBOY_A", 10, 31.5)
	_attach("U_PAINBOY_A", "U_BOYZ_C")
	_u("U_BOYZ_C").models[9]["alive"] = false
	OA.on_phase_transition(P_CMD, P_MOV)
	_check("not used in the window: heals 3 at the end of the Command phase", _alive("U_BOYZ_C") == 10)
	# Catch Dat Red Bit: +D3, once per battle
	_fresh(P_CMD)
	_place("U_BOYZ_C", 10, 30)
	_place("U_PAINBOY_A", 10, 31.5)
	_attach("U_PAINBOY_A", "U_BOYZ_C")
	for i in range(4, 10):
		_u("U_BOYZ_C").models[i]["alive"] = false
	r = _use(1, "crude_surgery", "U_PAINBOY_A", "battle_shock_step_start", ctx, "", "heal3_d3")
	_check("Catch Dat Red Bit: 3 + D3 models back", r.get("success", false) and _alive("U_BOYZ_C") >= 8, str(_alive("U_BOYZ_C")))
	GS.state.meta["battle_round"] = 3
	for i in range(4, 10):
		_u("U_BOYZ_C").models[i]["alive"] = false
	o = _offer(1, "battle_shock_step_start", ctx, "crude_surgery")
	_check("Catch Dat Red Bit: once per battle (only the plain option next turn)", o.targets[0].get("variants", []).size() == 1)
	# Fix Dat Armour Up: heal 3, once per battle
	_fresh(P_CMD)
	_place("U_BIG_MEK_IN_MEGA_ARMOUR_A", 10, 30)
	_check("Fix Dat Armour Up: no wounds lost — not offered", _offer(1, "battle_shock_step_start", ctx, "fix_dat_armour_up").is_empty())
	_wound("U_BIG_MEK_IN_MEGA_ARMOUR_A", 4)
	var w0 := _wounds_left("U_BIG_MEK_IN_MEGA_ARMOUR_A")
	r = _use(1, "fix_dat_armour_up", "U_BIG_MEK_IN_MEGA_ARMOUR_A", "battle_shock_step_start", ctx)
	_check("Fix Dat Armour Up: heals 3", r.get("success", false) and _wounds_left("U_BIG_MEK_IN_MEGA_ARMOUR_A") == w0 + 3)
	_wound("U_BIG_MEK_IN_MEGA_ARMOUR_A", 4)
	GS.state.meta["battle_round"] = 3
	_check("Fix Dat Armour Up: once per battle", _offer(1, "battle_shock_step_start", ctx, "fix_dat_armour_up").is_empty())
	# Push Dat Bit Back In: friendly BEAST SNAGGA within 6"
	_fresh(P_CMD)
	_place("U_PAINBOSS_A", 10, 30)
	_place("U_BEAST_SNAGGA_BOYZ_B", 10, 34)
	_u("U_BEAST_SNAGGA_BOYZ_B").models[9]["alive"] = false
	o = _offer(1, "battle_shock_step_start", ctx, "push_dat_bit_back_in")
	_check("Push Dat Bit Back In: wounded BEAST SNAGGA unit within 6\" offered", "U_BEAST_SNAGGA_BOYZ_B" in _secondary_ids(o, "U_PAINBOSS_A"))
	r = _use(1, "push_dat_bit_back_in", "U_PAINBOSS_A", "battle_shock_step_start", ctx, "U_BEAST_SNAGGA_BOYZ_B")
	_check("heals 3 (the destroyed model returns)", r.get("success", false) and _alive("U_BEAST_SNAGGA_BOYZ_B") == 10)


# ---------------------------------------------------------------------------
# 20. Full Throttle (Turbo Engine / Shokk Attack Engine)
# ---------------------------------------------------------------------------
func _section_full_throttle() -> void:
	print("\n-- 20. Full Throttle --")
	_fresh(P_CMD)
	_place("U_WAZDAKKA_GUTSMEK_A", 10, 30)
	var ctx := {"phase": "command"}
	var o := _offer(1, "battle_shock_step_start", ctx, "full_throttle")
	_check("Full Throttle offered with the engines as options", "U_WAZDAKKA_GUTSMEK_A" in _offer_units(o) and o.targets[0].get("variants", []).size() >= 2)
	var r := _use(1, "full_throttle", "U_WAZDAKKA_GUTSMEK_A", "battle_shock_step_start", ctx, "", "turbo")
	_check("Turbo Engine: advance / fall back and still charge", r.get("success", false) and _flags("U_WAZDAKKA_GUTSMEK_A").get("effect_advance_and_charge", false) and _flags("U_WAZDAKKA_GUTSMEK_A").get("effect_fall_back_and_charge", false))
	_check("Shokk Attack Engine not available (Turbo chosen)", _offer(1, "battle_shock_step_start", ctx, "shokk_attack_engine").is_empty())
	GS.state.meta["battle_round"] = 3
	OA.on_phase_transition(11, P_CMD)
	_check("ends at the start of your next Command phase", not _flags("U_WAZDAKKA_GUTSMEK_A").get("effect_advance_and_charge", false))
	r = _use(1, "full_throttle", "U_WAZDAKKA_GUTSMEK_A", "battle_shock_step_start", ctx, "", "shokk")
	_check("Shokk Attack Engine chosen", r.get("success", false) and OA.engine_of("U_WAZDAKKA_GUTSMEK_A") == "shokk")
	r = _use(1, "shokk_attack_engine", "U_WAZDAKKA_GUTSMEK_A", "battle_shock_step_start", ctx)
	_check("Shokk Attack Engine: unengaged — placed in strategic reserves", r.get("success", false) and int(_u("U_WAZDAKKA_GUTSMEK_A").status) == 7)


# ---------------------------------------------------------------------------
# 21. Da Jump (psychic, once per army per battle round)
# ---------------------------------------------------------------------------
func _section_da_jump() -> void:
	print("\n-- 21. Da Jump --")
	_fresh(P_MOV)
	_place("U_WEIRDBOY_A", 10, 30)
	var ctx := {"phase": "movement"}
	var o := _offer(1, "movement_phase_start", ctx, "da_jump")
	_check("offered at the start (and the end) of the Movement phase", "U_WEIRDBOY_A" in _offer_units(o) and not _offer(1, "movement_phase_end", ctx, "da_jump").is_empty())
	_check("before: no Deep Strike", not GS.unit_has_deep_strike("U_WEIRDBOY_A"))
	var r := _use(1, "da_jump", "U_WEIRDBOY_A", "movement_phase_start", ctx)
	_check("USE: strategic reserves + Deep Strike (GameState.unit_has_deep_strike)", r.get("success", false) and int(_u("U_WEIRDBOY_A").status) == 7 and GS.unit_has_deep_strike("U_WEIRDBOY_A"))
	_check("once per army per battle round", _offer(1, "movement_phase_end", ctx, "da_jump").is_empty())
	_place("U_WEIRDBOY_A", 10, 30)
	OA.on_phase_transition(P_MOV, P_SHOOT)
	_check("Deep Strike ends once the unit has arrived", not GS.unit_has_deep_strike("U_WEIRDBOY_A"))


# ---------------------------------------------------------------------------
# 22. vehicle passives: Blastajet Force Field / Mobile Fortress / Dread 'Ard /
#     Strafing Run / Go fer da Weak Spot / Deff from Above / Big an' Shooty /
#     Big an' Stompy / Mobile Arsenal / Spiteful Power Trip / Walking Bastion /
#     Blitz Dem Gitz! / Fully Loaded Butchery / Tramplasquig Charge / Waaagh! Effigy
# ---------------------------------------------------------------------------
func _section_vehicle_passives() -> void:
	print("\n-- 22. vehicle passives --")
	_fresh(P_SHOOT)
	for uid in ["U_WAZBOM_BLASTAJET_A", "U_BATTLEWAGON_A", "U_DEFF_DREAD_A", "U_DAKKAJET_A", "U_DEFFKOPTAS_A", "U_MORKANAUT_A", "U_GORKANAUT_A", "U_GUNWAGON_A", "U_KILLA_KANS_A", "U_GARGANTUAN_SQUIGGOTH_A", "U_BIG_MEK_DAKKARIG_A", "U_HUNTA_RIG_A", "U_STOMPA_B"]:
		pass
	_place("U_WAZBOM_BLASTAJET_A", 4, 10)
	_check("Blastajet Force Field: 5+ invuln (ranged and melee)", int(OA.defence_mods(_u("U_WAZBOM_BLASTAJET_A"), false).invuln) == 5 and int(OA.defence_mods(_u("U_WAZBOM_BLASTAJET_A"), true).invuln) == 5)
	_check("Go fer da Weak Spot: vs INFANTRY — no", not bool(_mods("U_WAZBOM_BLASTAJET_A", "U_CUSTODIAN_GUARD_A", false).wound_plus))
	_u("U_GUNWAGON_A")["owner"] = 2
	_place("U_GUNWAGON_A", 30, 50)
	_check("Go fer da Weak Spot: vs a VEHICLE in your Shooting phase — +1 to wound", bool(_mods("U_WAZBOM_BLASTAJET_A", "U_GUNWAGON_A", false).wound_plus))
	_place("U_BATTLEWAGON_A", 14, 10)
	_check("Mobile Fortress: -1 D vs ranged only", int(OA.defence_mods(_u("U_BATTLEWAGON_A"), false).damage_minus) == 1 and int(OA.defence_mods(_u("U_BATTLEWAGON_A"), true).damage_minus) == 0)
	_place("U_DEFF_DREAD_A", 24, 10)
	_check("Dread 'Ard: -1 D vs every attack", int(OA.defence_mods(_u("U_DEFF_DREAD_A"), true).damage_minus) == 1 and int(OA.defence_mods(_u("U_DEFF_DREAD_A"), false).damage_minus) == 1)
	_check("EffectPrimitives.get_effect_minus_damage reads Dread 'Ard", int(EP.get_effect_minus_damage(_u("U_DEFF_DREAD_A"))) == 1)
	_place("U_DAKKAJET_A", 34, 10)
	_check("Strafing Run: vs a non-FLY unit — +1 to hit", bool(_mods("U_DAKKAJET_A", "U_CUSTODIAN_GUARD_A", false).hit_plus))
	_u("U_DEFFKOPTAS_A")["owner"] = 2
	_place("U_DEFFKOPTAS_A", 34, 50)
	_check("Strafing Run: vs a FLY unit — nothing", not bool(_mods("U_DAKKAJET_A", "U_DEFFKOPTAS_A", false).hit_plus))
	# A/B Strafing Run with the real resolver: hits with the ability vs the same unit without it.
	var wid := _first_weapon("U_DAKKAJET_A", true)
	_place("U_CUSTODIAN_GUARD_A", 34, 22)  # within the dual supa shootas' range
	var more := false
	var never_less := true
	var abil: Array = _u("U_DAKKAJET_A").meta.abilities
	for s in [2, 4, 6, 8, 10]:
		_u("U_DAKKAJET_A").meta["abilities"] = abil.filter(func(a): return str(a.get("name", "")) != "Strafing Run")
		var a := _ranged_hits("U_DAKKAJET_A", wid, "U_CUSTODIAN_GUARD_A", s)
		_u("U_DAKKAJET_A").meta["abilities"] = abil
		var b := _ranged_hits("U_DAKKAJET_A", wid, "U_CUSTODIAN_GUARD_A", s)
		print("    Strafing Run A/B seed %d: %d -> %d hits" % [s, a, b])
		if b < a:
			never_less = false
		if b > a:
			more = true
	_check("A/B (same seeds): Strafing Run never fewer hits, more on some seed", never_less and more, wid)
	_u("U_DEFFKOPTAS_A")["owner"] = 1
	_place("U_DEFFKOPTAS_A", 4, 20)
	_check("Deff from Above: no ingress this turn — no +1", not bool(_mods("U_DEFFKOPTAS_A", "U_CUSTODIAN_GUARD_A", false).hit_plus))
	_u("U_DEFFKOPTAS_A")["arrived_from_reserves_turn"] = 2
	_check("Deff from Above: ingress move this turn — +1 to hit (your Shooting phase)", bool(_mods("U_DEFFKOPTAS_A", "U_CUSTODIAN_GUARD_A", false).hit_plus))
	_phase(P_SHOOT, 2)
	_check("Deff from Above: not in the opponent's Shooting phase", not bool(_mods("U_DEFFKOPTAS_A", "U_CUSTODIAN_GUARD_A", false).hit_plus))
	_phase(P_SHOOT, 1)
	_place("U_MORKANAUT_A", 4, 30)
	_check("Big an' Shooty: your Shooting phase — re-roll hit rolls of 1", str(_mods("U_MORKANAUT_A", "U_CUSTODIAN_GUARD_A", false).hit_reroll) == "ones")
	_place("U_GORKANAUT_A", 14, 30)
	_check("Big an' Stompy: melee — re-roll hit rolls of 1", str(_mods("U_GORKANAUT_A", "U_CUSTODIAN_GUARD_A", true).hit_reroll) == "ones")
	_check("Big an' Stompy: ranged unaffected", str(_mods("U_GORKANAUT_A", "U_CUSTODIAN_GUARD_A", false).hit_reroll) == "")
	_u("U_GUNWAGON_A")["owner"] = 1
	_place("U_GUNWAGON_A", 24, 30)
	_check("Mobile Arsenal: your Shooting phase — re-roll hit rolls of 1", str(_mods("U_GUNWAGON_A", "U_CUSTODIAN_GUARD_A", false).hit_reroll) == "ones")
	_phase(P_SHOOT, 2)
	_check("Mobile Arsenal: not in the opponent's Shooting phase (overwatch)", str(_mods("U_GUNWAGON_A", "U_CUSTODIAN_GUARD_A", false).hit_reroll) == "")
	_phase(P_SHOOT, 1)
	_place("U_KILLA_KANS_A", 34, 30)
	_check("Spiteful Power Trip: target without T7+ models — +1 to hit", bool(_mods("U_KILLA_KANS_A", "U_CUSTODIAN_GUARD_A", false).hit_plus))
	_u("U_STOMPA_B")["owner"] = 2
	_place("U_STOMPA_B", 34, 46)
	_check("Spiteful Power Trip: target with T7+ — nothing", not bool(_mods("U_KILLA_KANS_A", "U_STOMPA_B", false).hit_plus))
	_place("U_GARGANTUAN_SQUIGGOTH_A", 4, 40)
	var wb := _mods("U_GARGANTUAN_SQUIGGOTH_A", "U_CUSTODIAN_GUARD_A", false)
	_check("Walking Bastion: ignores hit-roll penalties", bool(wb.ignore_hit_penalties))
	var bits: int = RE.ork11e_ab_hit_bits(RE.HitModifier.MINUS_ONE, [], wb)
	_check("Walking Bastion: a -1 to hit is stripped from the hit modifiers", not (bits & RE.HitModifier.MINUS_ONE))
	_place("U_BIG_MEK_DAKKARIG_A", 14, 40)
	_check("Blitz Dem Gitz!: blitzkannon vs non-MONSTER/VEHICLE — +6 A", int(_mods("U_BIG_MEK_DAKKARIG_A", "U_CUSTODIAN_GUARD_A", false, "Blitzkannon").attacks) == 6)
	_check("Blitz Dem Gitz!: vs a MONSTER/VEHICLE — nothing", int(_mods("U_BIG_MEK_DAKKARIG_A", "U_STOMPA_B", false, "Blitzkannon").attacks) == 0)
	_place("U_HUNTA_RIG_A", 24, 40)
	_check("Fully Loaded Butchery: nobody embarked — +0 A", int(_mods("U_HUNTA_RIG_A", "U_CUSTODIAN_GUARD_A", true, "Butcha Boyz").attacks) == 0)
	_embark("U_BEAST_SNAGGA_BOYZ_B", "U_HUNTA_RIG_A")
	_check("Fully Loaded Butchery: 10 embarked models — +20 A on Butcha Boyz", int(_mods("U_HUNTA_RIG_A", "U_CUSTODIAN_GUARD_A", true, "Butcha Boyz").attacks) == 20, str(_mods("U_HUNTA_RIG_A", "U_CUSTODIAN_GUARD_A", true, "Butcha Boyz").attacks))
	_check("Tramplasquig Charge: Crushing Impact on the Hunta Rig is -1 CP", OA.stratagem_cp_discount("CRUSHING IMPACT", "U_HUNTA_RIG_A") == 1)
	_check("Tramplasquig Charge: other stratagems / units unaffected", OA.stratagem_cp_discount("SMOKESCREEN", "U_HUNTA_RIG_A") == 0 and OA.stratagem_cp_discount("CRUSHING IMPACT", "U_GUNWAGON_A") == 0)
	_u("U_STOMPA_B")["owner"] = 1
	OA.on_phase_transition(P_SHOOT, P_CHG)
	_check("Waaagh! Effigy: the Stompa is riled up (permanently)", OA.group_riled_up("U_STOMPA_B"))


# ---------------------------------------------------------------------------
# 23. Beast Snagga: Dodge Dis! / Thundering Stampede / Hardy Bioniks / Runnin'
#     wiv da Herd / One Last Kill / Da Bigger Dey Iz / Mobbed / Brutal Impact
# ---------------------------------------------------------------------------
func _section_beast_snagga() -> void:
	print("\n-- 23. Beast Snagga datasheet abilities --")
	_fresh(P_FIGHT)
	_place("U_BEASTBOSS_A", 10, 10)
	_check("Dodge Dis!: +1 to hit (all attacks)", bool(_mods("U_BEASTBOSS_A", "U_CUSTODIAN_GUARD_A", true).hit_plus) and bool(_mods("U_BEASTBOSS_A", "U_CUSTODIAN_GUARD_A", false).hit_plus))
	_place("U_BEASTBOSS_ON_SQUIGOSAUR_A", 20, 10)
	_place("U_BEAST_SNAGGA_BOYZ_B", 20, 14)
	_place("U_BOYZ_C", 20, 15.5)
	_check("Thundering Stampede: BEAST SNAGGA unit within 6\" — +1 to charge rolls", int(OA.charge_roll_bonus("U_BEAST_SNAGGA_BOYZ_B").bonus) == 1)
	_check("Thundering Stampede: not for non-BEAST SNAGGA units", int(OA.charge_roll_bonus("U_BOYZ_C").bonus) == 0)
	_place("U_BEAST_SNAGGA_BOYZ_B", 20, 40)
	_check("Thundering Stampede: beyond 6\" — nothing", int(OA.charge_roll_bonus("U_BEAST_SNAGGA_BOYZ_B").bonus) == 0)
	_place("U_PAINBOSS_A", 30, 10)
	var t := int(_u("U_PAINBOSS_A").meta.stats.get("toughness", 5))
	_check("Hardy Bioniks: S > T attacks have -1 to wound", OA.incoming_wound_penalty(_u("U_PAINBOSS_A"), t + 1, t) and RE.ork11e_ab_wound_penalty(_u("U_PAINBOSS_A"), t + 1, t))
	_check("Hardy Bioniks: S <= T — no penalty", not OA.incoming_wound_penalty(_u("U_PAINBOSS_A"), t, t))
	_place("U_SQUIGHOG_BOYZ_A", 40, 20)
	_check("Runnin' wiv da Herd: unattached — +0\" M", OA.move_modifier(_u("U_PAINBOSS_A")) == 0.0)
	_attach("U_PAINBOSS_A", "U_SQUIGHOG_BOYZ_A")
	_check("Runnin' wiv da Herd: attached to a MOUNTED unit — +4\" M", OA.move_modifier(_u("U_PAINBOSS_A")) == 4.0)
	_place("U_MOZROG_SKRAGBAD_A", 10, 30)
	OA.on_phase_transition(P_CHG, P_FIGHT)
	_check("One Last Kill: Fight On Death marker at the start of the Fight phase", str(_flags("U_MOZROG_SKRAGBAD_A").get(OA.F_FOD_MODE, "")) == "one_last_kill")
	var fight = load("res://scripts/stratagems/ork_codex/OrkCodexFight.gd")
	var mi: Dictionary = fight.fod_roll_modifier("U_MOZROG_SKRAGBAD_A")
	_check("One Last Kill: the roll passes on a 2+ (4+ with +2)", fight.FOD_PASS - int(mi.mod) == 2, str(mi))
	OA.on_phase_transition(P_FIGHT, 11)
	_check("One Last Kill: marker cleared after the Fight phase", not _flags("U_MOZROG_SKRAGBAD_A").has(OA.F_FOD_MODE))
	_u("U_GUNWAGON_A")["owner"] = 2
	_place("U_GUNWAGON_A", 10, 33)
	_phase(P_FIGHT)
	_check("Da Bigger Dey Iz: melee vs a VEHICLE — re-roll the wound roll", str(_mods("U_MOZROG_SKRAGBAD_A", "U_GUNWAGON_A", true).wound_reroll) == "failed")
	_check("Da Bigger Dey Iz: vs INFANTRY — nothing", str(_mods("U_MOZROG_SKRAGBAD_A", "U_CUSTODIAN_GUARD_A", true).wound_reroll) == "")
	# Brutal Impact (Squighog Boyz): +1 D after a charge move
	_check("Brutal Impact: no charge — +0 D", int(_mods("U_SQUIGHOG_BOYZ_A", "U_CUSTODIAN_GUARD_A", true).damage) == 0)
	_flags("U_SQUIGHOG_BOYZ_A")["charged_this_turn"] = true
	_check("Brutal Impact: charged — +1 D", int(_mods("U_SQUIGHOG_BOYZ_A", "U_CUSTODIAN_GUARD_A", true).damage) == 1)
	# Mobbed: enemy MONSTER/VEHICLE engaged after the charge makes a battle-shock roll at -1 (-2 with 13+).
	_fresh(P_CHG)
	_u("U_GUNWAGON_A")["owner"] = 2
	_place("U_GUNWAGON_A", 10, 30)
	_place("U_BEAST_SNAGGA_BOYZ_B", 8, 33.2)
	var ld = OA.best_leadership("U_GUNWAGON_A")
	_check("Mobbed precondition: the Gunwagon is engaged with the Beast Snagga Boyz", "U_GUNWAGON_A" in OA._engaged_enemy_ids("U_BEAST_SNAGGA_BOYZ_B"), str(OA._engaged_enemy_ids("U_BEAST_SNAGGA_BOYZ_B")))
	var fail_seed := _seed_where(2, func(r): return int(r[0]) + int(r[1]) >= ld and int(r[0]) + int(r[1]) - 1 < ld)
	RE.set_test_seed(fail_seed)
	var md: Array = OA.on_charge_move_ended("U_BEAST_SNAGGA_BOYZ_B")
	_check("Mobbed: the -1 turns a pass into a failed battle-shock roll (seed %d)" % fail_seed, _flags("U_GUNWAGON_A").get("battle_shocked", false), str(md))
	RE.set_test_seed(-1)
	_flags("U_GUNWAGON_A").erase("battle_shocked")
	_place("U_GUNWAGON_A", 30, 30)
	_check("Mobbed: nothing engaged — no roll", OA.on_charge_move_ended("U_BEAST_SNAGGA_BOYZ_B").is_empty())


# ---------------------------------------------------------------------------
# 24. misc passives: Sumfin' to Prove / Waaagh! Banner / Trophy Hunters /
#     Fuel-mixa Grot / Super Runts / Finderz Keeperz / High-speed Carnage /
#     Downtrodden / Never Too Busy to Fight / Thievin' Scavengers
# ---------------------------------------------------------------------------
func _section_misc_passives() -> void:
	print("\n-- 24. misc passives --")
	_fresh(P_FIGHT)
	_place("U_BIGBOSS_A", 10, 10)
	_check("Sumfin' to Prove: melee +1 to hit", bool(_mods("U_BIGBOSS_A", "U_CUSTODIAN_GUARD_A", true).hit_plus))
	_check("Sumfin' to Prove: ranged — nothing", not bool(_mods("U_BIGBOSS_A", "U_CUSTODIAN_GUARD_A", false).hit_plus))
	_place("U_BANNERNOB_A", 20, 10)
	_check("Waaagh! Banner: +1 to charge rolls", int(OA.charge_roll_bonus("U_BANNERNOB_A").bonus) == 1)
	_place("U_BREAKA_BOYZ_A", 30, 10)
	_check("Trophy Hunters: +1 to charge rolls", int(OA.charge_roll_bonus("U_BREAKA_BOYZ_A").bonus) == 1)
	_check("no charge bonus without an ability", int(OA.charge_roll_bonus("U_BIGBOSS_A").bonus) == 0)
	_place("U_DEFFKILLA_WARTRIKE_A", 40, 10)
	_check("Fuel-mixa Grot: +1 to advance rolls", OA.advance_roll_bonus("U_DEFFKILLA_WARTRIKE_A") == 1 and OA.advance_roll_bonus("U_BIGBOSS_A") == 0)
	_place("U_ZODGROD_WORTSNAGGA_A", 10, 20)
	_place("U_GRETCHIN_E", 10, 22)
	_attach("U_ZODGROD_WORTSNAGGA_A", "U_GRETCHIN_E")
	OA.on_phase_transition(P_FIGHT, 11)
	_check("Super Runts: the unit is riled up (whole attached unit)", OA.group_riled_up("U_GRETCHIN_E"))
	var sr := _mods("U_GRETCHIN_E", "U_CUSTODIAN_GUARD_A", true, "Scavenged Shivs")
	_check("Super Runts: Scavenged Shivs +1 A, WS and S", int(sr.attacks) == 1 and int(sr.ws) == 1 and int(sr.strength) == 1, str(sr))
	_check("Super Runts: other weapons unaffected", int(_mods("U_GRETCHIN_E", "U_CUSTODIAN_GUARD_A", true, "Grot Blasta").attacks) == 0)
	# Finderz Keeperz (Flash Gitz): +1 AP while it or its target is within range of an objective.
	_fresh(P_SHOOT)
	_place("U_FLASH_GITZ_A", 2, 40)
	_check("Finderz Keeperz: nobody on an objective — +0 AP", int(_mods("U_FLASH_GITZ_A", "U_CUSTODIAN_GUARD_A", false).ap) == 0)
	_place("U_FLASH_GITZ_A", 19.5, 4)  # obj_home_1 at (22, 4)
	_check("Finderz Keeperz: the unit within range of an objective — +1 AP", int(_mods("U_FLASH_GITZ_A", "U_CUSTODIAN_GUARD_A", false).ap) == 1)
	_phase(P_SHOOT, 2)
	_check("Finderz Keeperz: only in your Shooting phase", int(_mods("U_FLASH_GITZ_A", "U_CUSTODIAN_GUARD_A", false).ap) == 0)
	_phase(P_FIGHT, 1)
	_place("U_WARBIKERS_A", 10, 30)
	_flags("U_WARBIKERS_A")["charged_this_turn"] = true
	var hs := _mods("U_WARBIKERS_A", "U_CUSTODIAN_GUARD_A", true)
	_check("High-speed Carnage: charged — melee +1 S, +1 D", int(hs.strength) == 1 and int(hs.damage) == 1)
	_flags("U_WARBIKERS_A").erase("charged_this_turn")
	_check("High-speed Carnage: no charge — nothing", int(_mods("U_WARBIKERS_A", "U_CUSTODIAN_GUARD_A", true).strength) == 0)
	_check("Downtrodden: 10 Gretchin take 5 transport spaces", OA.transport_space("U_GRETCHIN_A", 10) == 5)
	_check("Downtrodden: other units unaffected", OA.transport_space("U_BOYZ_C", 10) == 10)
	var tm = root.get_node("TransportManager")
	_check("TransportManager capacity cost uses Downtrodden", int(tm._get_unit_capacity_cost(_u("U_GRETCHIN_A"), _u("U_BATTLEWAGON_A"))) == 5)
	# Never Too Busy to Fight
	_place("U_BOYZ_C", 10, 51.2)
	_place("U_CUSTODIAN_GUARD_A", 10, 52.6)
	_check("Never Too Busy to Fight: engaged Boyz may still start an action", OA.engaged_can_start_action("U_BOYZ_C"))
	var am = load("res://scripts/rules/ActionsManager.gd")
	var reasons: Array = am.can_start_action("U_BOYZ_C", GS.state).get("reasons", [])
	_check("ActionsManager: no 'engaged' reason for the Boyz", not reasons.any(func(x): return str(x).contains("engaged")), str(reasons))
	# Thievin' Scavengers: end of your Movement phase, controlling an objective -> secured
	_fresh(P_MOV)
	_place("U_GRETCHIN_A", 19.0, 4.0)
	var mm = root.get_node("MissionManager")
	mm.check_all_objectives()
	OA.on_movement_phase_end(1)
	var sec = mm.get_sticky_objectives()
	_check("Thievin' Scavengers: the objective the Gretchin control is secured", sec.has("obj_home_1") and int(sec["obj_home_1"].player) == 1, str(sec))


# ---------------------------------------------------------------------------
# 25. Taktikal Know-wotz (re-key of Patrol Squad)
# ---------------------------------------------------------------------------
func _section_taktikal() -> void:
	print("\n-- 25. Taktikal Know-wotz --")
	_fresh(P_MOV)
	var sib: String = GS.split_unit_at_deployment("U_KOMMANDOS_A")
	_check("split into two 5-model units", sib != "" and _u("U_KOMMANDOS_A").models.size() == 5 and _u(sib).models.size() == 5)
	_check("Squad A keeps Bomb Squig only", OA.has(_u("U_KOMMANDOS_A"), "bomb_squig") and not OA.has(_u("U_KOMMANDOS_A"), "found_em"))
	_check("Squad B has Found 'Em! only", OA.has(_u(sib), "found_em") and not OA.has(_u(sib), "bomb_squig"))
	_check("both keep Nowhere to Hide", OA.has(_u(sib), "nowhere_to_hide") and OA.has(_u("U_KOMMANDOS_A"), "nowhere_to_hide"))


# ---------------------------------------------------------------------------
# 26. That'll Learn Ya (Runtherd)
# ---------------------------------------------------------------------------
func _section_thatll_learn_ya() -> void:
	print("\n-- 26. That'll Learn Ya --")
	_fresh(P_CMD)
	_place("U_GRETCHIN_A", 10, 30)
	_place("U_RUNTHERD_A", 10, 32)
	_attach("U_RUNTHERD_A", "U_GRETCHIN_A")
	for gid in ["U_GRETCHIN_A", "U_RUNTHERD_A"]:
		_flags(gid)["battle_shocked"] = true
	var ctx := {"phase": "command", "unit_id": "U_GRETCHIN_A"}
	var o := _offer(1, "unit_battle_shocked", ctx, "thatll_learn_ya")
	_check("offered when the unit becomes battle-shocked (4+ Gretchin)", not o.is_empty())
	var r := _use(1, "thatll_learn_ya", _offer_units(o)[0] if not o.is_empty() else "U_GRETCHIN_A", "unit_battle_shocked", ctx)
	_check("D3 Gretchin destroyed, the unit no longer battle-shocked", r.get("success", false) and _alive("U_GRETCHIN_A") < 10 and _alive("U_GRETCHIN_A") >= 7 and not _flags("U_GRETCHIN_A").get("battle_shocked", false) and not _flags("U_RUNTHERD_A").get("battle_shocked", false))
	_flags("U_GRETCHIN_A")["battle_shocked"] = true
	_check("once per battle round", _offer(1, "unit_battle_shocked", ctx, "thatll_learn_ya").is_empty())


# ---------------------------------------------------------------------------
# 27. Shokk-boosta (Big Mek): advance roll 6, hazard rolls at the end
# ---------------------------------------------------------------------------
func _section_shokk_boosta() -> void:
	print("\n-- 27. Shokk-boosta --")
	_fresh(P_MOV)
	_place("U_BIG_MEK_A", 10, 30)
	_check("not offered for a normal move", _offer(1, "unit_selected_to_move", {"phase": "movement", "unit_id": "U_BIG_MEK_A", "move_type": "normal"}, "shokk_boosta").is_empty())
	var ctx := {"phase": "movement", "unit_id": "U_BIG_MEK_A", "move_type": "advance"}
	var r := _use(1, "shokk_boosta", "U_BIG_MEK_A", "unit_selected_to_move", ctx)
	_check("USE (advance): Shokk-boosta active", r.get("success", false) and OA.shokk_boosta_active("U_BIG_MEK_A"))
	var hz_seed := _seed_where(1, func(r): return int(r[0]) <= 2)
	RE.set_test_seed(hz_seed)
	var w0 := _wounds_left("U_BIG_MEK_A")
	OA.on_advance_move_ended("U_BIG_MEK_A")
	_check("end of the advance: one hazard roll per model (failed on a 1-2: mortal wound)", _wounds_left("U_BIG_MEK_A") < w0 and not OA.shokk_boosta_active("U_BIG_MEK_A"), "%d -> %d" % [w0, _wounds_left("U_BIG_MEK_A")])
	RE.set_test_seed(-1)


# ---------------------------------------------------------------------------
# 28. AI: every activated ability has a score; the window never stalls
# ---------------------------------------------------------------------------
func _section_ai() -> void:
	print("\n-- 28. AI decides ability offers synchronously --")
	_fresh(P_SHOOT)
	_place("U_BOYZ_C", 10, 30)
	var ctx := {"phase": "shooting", "unit_id": "U_BOYZ_C", "window_id": "unit_selected_to_shoot"}
	var offers: Array = SM.get_all_window_offers(1, "unit_selected_to_shoot", ctx)
	_check("get_all_window_offers carries the ability offer", offers.any(func(o): return bool(o.get("is_ability", false))))
	_check("get_window_offers (stratagems only) does not", not SM.get_window_offers(1, "unit_selected_to_shoot", ctx).any(func(o): return bool(o.get("is_ability", false))))
	var aidm = load("res://scripts/AIDecisionMaker.gd")
	var dec: Dictionary = aidm.decide_window_stratagem(1, "unit_selected_to_shoot", offers, ctx)
	_check("AI answers the ability window (use or decline, no stall)", dec.has("use"), str(dec))
	var all_slugs: Array = []
	for w in OA.WINDOW_ABILITIES:
		for s in OA.WINDOW_ABILITIES[w]:
			if not s in all_slugs:
				all_slugs.append(s)
	var scored := true
	for s in all_slugs:
		var v = OA.ai_score(1, OA.sid_of(s), "U_BOYZ_C", "unit_selected_to_shoot", ctx)
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			scored = false
	_check("ai_score returns a number for all %d activated abilities" % all_slugs.size(), scored)


# ---------------------------------------------------------------------------
# 29. dropped pre-codex names no longer dispatch
# ---------------------------------------------------------------------------
func _section_dropped() -> void:
	print("\n-- 29. pre-codex abilities removed --")
	var uam = root.get_node("UnitAbilityManager")
	for n in ["Mekaniak", "Sawbonez", "Grot Oiler", "Grot Riggers", "Grot Orderly", "Shooty Power Trip", "Distraction Grot", "Ammo Runt",
			"Da Biggest and da Best", "Dead Brutal", "Da Boss' Ladz", "Splat!", "Drive-by Dakka", "Hold Still and Say 'Aargh!'",
			"Piston-driven Brutality", "Clankin' Forward", "Stompin' Forward", "Special Dose", "Monster Hunters", "Runtherd",
			"Patrol Squad", "Get Da Good Bitz", "Ramshackle", "Gun-crazy Show-offs", "Blastajet Attack Run", "Red Skull Kommandos"]:
		_check("ABILITY_EFFECTS has no '%s' row" % n, not uam.ABILITY_EFFECTS.has(n))
	_check("Tank Hunters kept (Death Guard)", uam.ABILITY_EFFECTS.has("Tank Hunters"))
	for n in ["Might is Right", "Kustom Force Field", "More Dakka", "Krumpin' Time", "Big an' Shooty", "Fuel-mixa Grot", "Da Jump"]:
		var row: Dictionary = uam.ABILITY_EFFECTS.get(n, {})
		_check("collision row '%s' is an inert ork11e row (no effects)" % n, str(row.get("condition", "")) == "ork11e" and row.get("effects", [1]).is_empty())
	_check("ABILITY_NAME_CANON drops 'Ramshackle but Rugged'", not root.get_node("ArmyListManager").ABILITY_NAME_CANON.has("Ramshackle but Rugged"))
	var mp = load("res://phases/MovementPhase.gd")
	var src: String = mp.source_code
	_check("MovementPhase: no USE_MEKANIAK / USE_SAWBONEZ / USE_GROT_OILER / USE_DA_JUMP handlers", not src.contains("\"USE_MEKANIAK\"") and not src.contains("\"USE_SAWBONEZ\"") and not src.contains("\"USE_GROT_OILER\"") and not src.contains("\"USE_DA_JUMP\""))
	var sp = load("res://phases/ShootingPhase.gd")
	_check("ShootingPhase: no USE_AMMO_RUNT / USE_PULSA_ROKKIT / USE_SHOOTY_POWER_TRIP / USE_DISTRACTION_GROT", not sp.source_code.contains("\"USE_AMMO_RUNT\"") and not sp.source_code.contains("\"USE_PULSA_ROKKIT\"") and not sp.source_code.contains("\"USE_SHOOTY_POWER_TRIP\"") and not sp.source_code.contains("\"USE_DISTRACTION_GROT\""))
