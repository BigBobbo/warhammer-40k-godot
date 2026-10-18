extends SceneTree

# WP-C7 — Codex: Adeptus Custodes (11e) DATASHEET + WARGEAR abilities
# (scripts/codex/custodes/CustodesAbilities.gd).
#
# One check group per ability: the condition (on / off), the effect (modifier,
# or an A/B attack resolution with the same seed) and the usage limit where the
# ability has one. Board: tests/saves/cus11e_c5_active (P2 Orks kept, parked
# off the table until a section places them); P1 = the codex roster
# tests/fixtures/cus11e_ab_roster.json (every one of the 29 codex datasheets,
# generated from the codex data by scripts/40kdc/generate-armies.mjs, so every
# ability carries its codex name) processed through ArmyListManager.
#
# Usage: godot --headless --path 40k --script tests/test_custodes_abilities_11e.gd

const FIXTURE := "cus11e_c5_active"
const ROSTER := "cus11e_ab_roster"
const PX := 40.0
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
var CA = null
var EP = null
var UAM = null
var _roster: Dictionary = {}


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


## Fresh board: the fixture save, P1 replaced by the codex roster (all units
## off the table until _place), P2 Orks parked in reserves.
func _fresh(phase: int = P_SHOOT, active: int = 1, battle_round: int = 2) -> void:
	_stage_fixture()
	GameConstants.edition = 11
	RE.set_test_seed(-1)
	for uid in GS.state.units.keys():
		var u: Dictionary = GS.state.units[uid]
		if int(u.get("owner", 0)) == 1:
			GS.state.units.erase(uid)
		else:
			u["flags"] = {}
			u["status"] = 7
			u.erase("attached_to")
			u["attachment_data"] = {"attached_characters": []}
			for m in u.get("models", []):
				m["alive"] = true
				m["position"] = null
				m["current_wounds"] = int(m.get("wounds", 1))
	for k in _roster.get("units", {}):
		var u: Dictionary = _roster.units[k].duplicate(true)
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
	GS.state.factions["1"] = _roster.get("faction", {}).duplicate(true)
	SM.load_faction_stratagems_for_player(1)
	GS.state.meta["phase"] = phase
	GS.state.meta["active_player"] = active
	GS.state.meta["battle_round"] = battle_round
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 6
	GS.state.players["1"].erase(CA.ARMY_USES)
	SM._usage_history = {"1": [], "2": []}
	UAM.reset_for_new_game()


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


func _attach(char_id: String, bodyguard_id: String) -> void:
	GS.state.units[bodyguard_id]["attachment_data"] = {"attached_characters": [char_id]}
	GS.state.units[char_id]["attached_to"] = bodyguard_id


func _phase(p: int, active: int = 1) -> void:
	GS.state.meta["phase"] = p
	GS.state.meta["active_player"] = active


func _sid(slug: String) -> String:
	return CA.sid_of(slug)


func _offer(player: int, window_id: String, ctx: Dictionary, slug: String) -> Dictionary:
	var c := ctx.duplicate(true)
	c["window_id"] = window_id
	for o in CA.window_offers(player, window_id, c):
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
	var m: Dictionary = RE.ork11e_ab_mods(_u(actor), _u(target), prof, melee, GS.state)
	return m


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


func _weapon(uid: String, name_part: String) -> String:
	for gid in [uid]:
		var ws: Dictionary = RE.get_unit_weapons(gid, GS.state)
		for mid in ws:
			for wid in ws[mid]:
				var prof: Dictionary = RE.get_weapon_profile(str(wid), GS.state)
				if str(prof.get("name", "")).to_lower().contains(name_part.to_lower()):
					return str(wid)
		var mws: Dictionary = RE.get_unit_melee_weapons(gid, GS.state) if RE.has_method("get_unit_melee_weapons") else {}
		for mid in mws:
			for wid in mws[mid]:
				var prof2: Dictionary = RE.get_weapon_profile(str(wid), GS.state)
				if str(prof2.get("name", "")).to_lower().contains(name_part.to_lower()):
					return str(wid)
	return ""


## Melee hits (incl. Sustained bonus hits) of one batch, seed `seed`.
func _melee_hits(uid: String, wid: String, target: String, seed: int) -> Dictionary:
	var act := {"type": "FIGHT", "actor_unit_id": uid, "payload": {"assignments": [{"attacker": uid, "target": target, "weapon": wid}]}}
	RE.set_test_seed(seed)
	var res = RE.resolve_melee_attacks(act, GS.state.duplicate(true), RE.RNGService.new(seed))
	var out := {"hits": 0, "bonus": 0, "res": res}
	for d in res.get("dice", []):
		var c := str(d.get("context", ""))
		if c in ["hit_roll_melee", "to_hit", "hit_roll", "melee_hit"]:
			out.hits += int(d.get("successes", 0))
			out.bonus += int(d.get("sustained_bonus_hits", 0))
	return out


func _pending(phase_node) -> Dictionary:
	return phase_node.get_pending_stratagem_window() if phase_node != null else {}


func _pending_sids(phase_node) -> Array:
	return _pending(phase_node).get("offers", []).map(func(o): return str(o.get("stratagem_id", "")))


# ---------------------------------------------------------------------------
func _run() -> void:
	GS = root.get_node("GameState")
	SM = root.get_node("StratagemManager")
	RE = root.get_node("RulesEngine")
	PM = root.get_node("PhaseManager")
	UAM = root.get_node("UnitAbilityManager")
	CA = load("res://scripts/codex/custodes/CustodesAbilities.gd")
	EP = load("res://autoloads/EffectPrimitives.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	root.get_node("SettingsService").set("auto_allocate_wounds", true)
	var alm = root.get_node("ArmyListManager")
	_roster = alm._process_army_data(_json(ROSTER), 1)
	print("\n=== test_custodes_abilities_11e (WP-C7) ===")
	_section_names()
	_section_captain_general()
	_section_moment_shackle()
	_section_supreme_commander()
	_section_vengeful_surge()
	_section_praesidium_shield()
	_section_teleport_shunter()
	_section_sweeping_advance()
	_section_wardens_vexilla()
	_section_slayer_of_tyrants()
	_section_quicksilver_execution()
	_section_unyielding_ancient()
	_section_destructor_optics()
	_section_repulsor_suspensor()
	_section_assault_vehicle()
	_section_guardian_eternal()
	_section_mobile_hunter()
	_section_assault_dropship()
	_section_infernus_firebombs()
	_section_swift_onslaught_seekers()
	_section_sword_of_the_throne()
	_section_corner_the_quarry()
	_section_impenetrable_stand_vigil()
	_section_purity_of_execution()
	_section_take_wing()
	_section_neutronium_cascade_mine()
	_section_swift_ruin()
	_section_dread_foe_death_blow()
	_section_sanctified_flames()
	_section_deft_parry_reap()
	_section_strike_from_the_skies()
	_section_advanced_firepower()
	_section_phase_start_window()
	_section_ai()
	_section_dropped()


# ---------------------------------------------------------------------------
# 0. every Datasheet / Wargear ability the roster carries resolves to a slug
# ---------------------------------------------------------------------------
func _section_names() -> void:
	print("\n-- 0. codex ability names fold to module slugs --")
	_fresh()
	var skip := ["martial katah", "deep strike", "leader", "aegis of the emperor", "aquila commander",
		"master of katahs", "feel no pain 5", "scouts 7", "support", "daughters of the abyss", "hover",
		"firing deck 2", "transport", "deadly demise"]
	var unknown: Array = []
	var slugs := {}
	for slug in CA.NAMES:
		slugs[CA.NAMES[slug]] = slug
	for uid in _roster.units:
		for ab in _roster.units[uid].get("meta", {}).get("abilities", []):
			var n: String = CA.fold(str(ab.get("name", "")) if ab is Dictionary else str(ab))
			if n in skip or n.begins_with("damaged") or n.begins_with("deadly demise") or n.begins_with("feel no pain") or n.begins_with("scouts") or n.begins_with("firing deck"):
				continue
			if not slugs.has(n) and not n in unknown:
				unknown.append(n)
	_check("every codex Datasheet/Wargear ability on the 29 datasheets has a module slug", unknown.is_empty(), str(unknown))
	_check("'Captain-General' (army file drops '(Aura)') -> captain_general", CA.has(_u("U_TRAJANN_A"), "captain_general"))
	_check("\"Seeker's Instincts\" (apostrophe) -> seekers_instincts", CA.has(_u("U_KNIGHT_CENTURA_A"), "seekers_instincts"))
	_check("'Archeotech Teleport-shunter' (hyphen) -> archeotech_teleport_shunter", CA.has(_u("U_SC_ALLARUS_A"), "archeotech_teleport_shunter"))
	_check("no false positive: Custodian Guard has no Stand Vigil", not CA.has(_u("U_GUARD_A"), "stand_vigil"))
	_check("fold drops a printed '(Once per battle, per unit)' suffix", CA.fold("Vengeful Surge (Once per battle, per unit)") == "vengeful surge")


# ---------------------------------------------------------------------------
# 1. Captain-General (Aura): re-roll hit 1s and wound 1s within 6"
# ---------------------------------------------------------------------------
func _section_captain_general() -> void:
	print("\n-- 1. Captain-General (Aura) --")
	_fresh(P_SHOOT)
	_place("U_TRAJANN_A", 20, 40)
	_place("U_GUARD_A", 20, 44)        # within 6"
	_place("U_GUARD_B", 34, 40)        # > 6"
	_place("U_TELEMON_A", 26, 40)      # VEHICLE within 6"
	_place("U_BOYZ_B", 10, 20)
	var m := _mods("U_GUARD_A", "U_BOYZ_B", false)
	_check("Guard within 6\": re-roll hit rolls of 1", str(m.hit_reroll) == "ones", str(m))
	_check("Guard within 6\": re-roll wound rolls of 1", str(m.wound_reroll) == "ones")
	_check("named in the modifier sources", "Captain-General" in _names(m))
	m = _mods("U_GUARD_B", "U_BOYZ_B", false)
	_check("Guard beyond 6\": no re-roll", str(m.hit_reroll) == "" and str(m.wound_reroll) == "", str(m))
	m = _mods("U_TELEMON_A", "U_BOYZ_B", false)
	_check("VEHICLE within 6\" (Telemon): excluded", not "Captain-General" in _names(m), str(_names(m)))
	m = _mods("U_TRAJANN_A", "U_BOYZ_B", true)
	_check("Trajann himself is within his own aura (22.01)", "Captain-General" in _names(m))
	_phase(P_SHOOT, 2)
	m = _mods("U_GUARD_A", "U_BOYZ_B", false)
	_check("applies in the opponent's turn too (overwatch / defensive fights)", "Captain-General" in _names(m))
	# Ork attackers near Trajann gain nothing.
	_place("U_BOYZ_B", 20, 47)
	m = _mods("U_BOYZ_B", "U_GUARD_A", true)
	_check("enemy units within 6\" are not affected", not "Captain-General" in _names(m))


# ---------------------------------------------------------------------------
# 2. Moment Shackle (Once per battle, per army; start of any phase)
# ---------------------------------------------------------------------------
func _section_moment_shackle() -> void:
	print("\n-- 2. Moment Shackle --")
	_fresh(P_FIGHT)
	_place("U_TRAJANN_A", 20, 40)
	_place("U_BOYZ_B", 20, 38.2)
	var ctx := {"phase": "fight"}
	var o := _offer(1, "phase_start", ctx, "moment_shackle")
	_check("offered at the start of your Fight phase", _offer_units(o) == ["U_TRAJANN_A"], str(_offer_units(o)))
	var t: Dictionary = o.get("targets", [{}])[0] if not o.is_empty() else {}
	_check("two options (+3 A / 3+ InSv), one must be chosen", t.get("variants", []).size() == 2 and bool(t.get("require_variant", false)))
	_phase(P_FIGHT, 2)
	_check("offered at the start of the opponent's Fight phase", not _offer(1, "phase_start", ctx, "moment_shackle").is_empty())
	_phase(P_SHOOT, 2)
	_check("offered at the start of the opponent's Shooting phase (3+ InSv)", not _offer(1, "phase_start", {"phase": "shooting"}, "moment_shackle").is_empty())
	for pp in [[P_SHOOT, 1], [P_MOV, 1], [P_CMD, 1], [P_CHG, 2]]:
		_phase(pp[0], pp[1])
		_check("not offered at the start of phase %d (P%d active): no attack it changes" % [pp[0], pp[1]], _offer(1, "phase_start", ctx, "moment_shackle").is_empty())
	_check("not offered in another window", _offer(1, "fight_phase_start", ctx, "moment_shackle").is_empty())
	_phase(P_FIGHT, 1)
	var res := _use(1, "moment_shackle", "U_TRAJANN_A", "phase_start", ctx)
	_check("refused without an option", not res.get("success", false))
	res = _use(1, "moment_shackle", "U_TRAJANN_A", "phase_start", ctx, "", "attacks")
	_check("use (+3 A) succeeds, 0 CP", res.get("success", false) and _offer_units(o).size() == 1 and int(GS.state.players["1"].cp) == 6, str(res))
	_check("flag set + once-per-battle marker (GILDED CHAMPION reads it)", str(_flags("U_TRAJANN_A").get(CA.F_MOMENT_SHACKLE, "")) == "attacks" and bool(_flags("U_TRAJANN_A").get("moment_shackle_used", false)))
	var m := _mods("U_TRAJANN_A", "U_BOYZ_B", true, "Watcher's Axe")
	_check("Watcher's Axe: +3 A", int(m.attacks) == 3, str(m.attacks))
	m = _mods("U_TRAJANN_A", "U_BOYZ_B", false, "Eagle's Scream")
	_check("other weapons: no bonus", int(m.attacks) == 0)
	_check("once per battle, per army: not offered again", _offer(1, "phase_start", ctx, "moment_shackle").is_empty())
	# A/B: the +3 A shows in a real melee resolution with the same seed.
	var axe := _weapon("U_TRAJANN_A", "watcher")
	_check("Trajann has the Watcher's Axe", axe != "")
	var with_ms: Dictionary = _melee_hits("U_TRAJANN_A", axe, "U_BOYZ_B", 7)
	_flags("U_TRAJANN_A").erase(CA.F_MOMENT_SHACKLE)
	var without_ms: Dictionary = _melee_hits("U_TRAJANN_A", axe, "U_BOYZ_B", 7)
	var a_with := 0
	var a_without := 0
	for d in with_ms.res.get("dice", []):
		a_with = maxi(a_with, (d.get("rolls_raw", []) as Array).size()) if str(d.get("context", "")).contains("hit") else a_with
	for d in without_ms.res.get("dice", []):
		a_without = maxi(a_without, (d.get("rolls_raw", []) as Array).size()) if str(d.get("context", "")).contains("hit") else a_without
	_check("A/B (same seed): 3 more hit dice with Moment Shackle (%d vs %d)" % [a_with, a_without], a_with == a_without + 3, "%d vs %d" % [a_with, a_without])
	# 3+ invulnerable save ("this model").
	_flags("U_TRAJANN_A")[CA.F_MOMENT_SHACKLE] = "invuln"
	_check("3+ InSv on Trajann (EffectPrimitives)", EP.get_effect_invuln(_u("U_TRAJANN_A")) == 3, str(EP.get_effect_invuln(_u("U_TRAJANN_A"))))
	_place("U_GUARD_A", 22, 41)
	_attach("U_TRAJANN_A", "U_GUARD_A")
	_check("not the bodyguard's save (\"this model\")", EP.get_effect_invuln(_u("U_GUARD_A")) == 0)
	var virt: Dictionary = RE.build_attached_allocation_unit_11e("U_GUARD_A", GS.state)
	var tri: Dictionary = {}
	for vm in virt.unit.models:
		if str(vm.get("cus11e_src_unit_id", "")) == "U_TRAJANN_A":
			tri = vm
	_check("attached-unit allocation: Trajann's model copy has InSv 3", int(tri.get("invuln", 0)) == 3, str(tri.get("invuln", "")))
	PM.transition_to_phase(P_SHOOT)
	_check("expires at the end of the phase", not _flags("U_TRAJANN_A").has(CA.F_MOMENT_SHACKLE))
	_check("the once-per-battle marker stays", bool(_flags("U_TRAJANN_A").get("moment_shackle_used", false)))


# ---------------------------------------------------------------------------
# 3. SUPREME COMMANDER
# ---------------------------------------------------------------------------
func _section_supreme_commander() -> void:
	print("\n-- 3. SUPREME COMMANDER --")
	_fresh(P_CMD)
	var fp = load("res://phases/FormationsPhase.gd").new()
	_check("FormationsPhase finds Trajann ('SUPREME COMMANDER', case-insensitive)", fp._find_supreme_commander_unit(1) == "U_TRAJANN_A", str(fp._find_supreme_commander_unit(1)))
	fp.free()
	_check("module recognises it", CA.is_supreme_commander(_u("U_TRAJANN_A")))


# ---------------------------------------------------------------------------
# 4. Vengeful Surge (Once per battle, per unit)
# ---------------------------------------------------------------------------
func _section_vengeful_surge() -> void:
	print("\n-- 4. Vengeful Surge --")
	_fresh(P_SHOOT, 2)
	_place("U_SHIELD_CAPTAIN_A", 20, 40)
	_place("U_BOYZ_B", 20, 30)
	var ctx := {"phase": "shooting", "attacker_unit_id": "U_BOYZ_B", "hit_unit_ids": ["U_SHIELD_CAPTAIN_A"], "wounded_unit_ids": ["U_SHIELD_CAPTAIN_A"]}
	var o := _offer(1, "enemy_has_shot", ctx, "vengeful_surge")
	_check("offered when an enemy unit has shot and the Shield-Captain lost a wound", _offer_units(o) == ["U_SHIELD_CAPTAIN_A"], str(_offer_units(o)))
	var ctx2 := ctx.duplicate(true)
	ctx2["wounded_unit_ids"] = []
	_check("not offered when it lost no wound", _offer(1, "enemy_has_shot", ctx2, "vengeful_surge").is_empty())
	_phase(P_SHOOT, 1)
	_check("not in your own Shooting phase", _offer(1, "enemy_has_shot", ctx, "vengeful_surge").is_empty())
	_phase(P_SHOOT, 2)
	_flags("U_SHIELD_CAPTAIN_A")["battle_shocked"] = true
	_check("not while battle-shocked (surge move 21.02)", _offer(1, "enemy_has_shot", ctx, "vengeful_surge").is_empty())
	_flags("U_SHIELD_CAPTAIN_A").erase("battle_shocked")
	# Attached: a bodyguard model losing a wound counts ("a model in this unit").
	_place("U_GUARD_A", 22, 41)
	_attach("U_SHIELD_CAPTAIN_A", "U_GUARD_A")
	var ctx3 := ctx.duplicate(true)
	ctx3["wounded_unit_ids"] = ["U_GUARD_A"]
	o = _offer(1, "enemy_has_shot", ctx3, "vengeful_surge")
	_check("Attached unit: a bodyguard's lost wound counts — the card targets the unit", _offer_units(o) == ["U_GUARD_A"], str(_offer_units(o)))
	var res := _use(1, "vengeful_surge", "U_GUARD_A", "enemy_has_shot", ctx3)
	_check("use succeeds: surge-move follow-up of D6+2\"", res.get("success", false) and str(res.get("followup", {}).get("type", "")) == "surge_move" \
		and int(res.followup.get("roll_bonus", 0)) == 2 and str(res.followup.get("unit_id", "")) == "U_GUARD_A", str(res))
	_check("once per battle (UnitAbilityManager ledger, holder = the Shield-Captain)", UAM.is_once_per_battle_used("U_SHIELD_CAPTAIN_A", "Vengeful Surge"))
	_check("not offered again", _offer(1, "enemy_has_shot", ctx3, "vengeful_surge").is_empty())
	# The ShootingPhase follow-up applies the +2 to the D6.
	GS.state.units["U_SHIELD_CAPTAIN_A"].erase("attached_to")
	GS.state.units["U_GUARD_A"]["attachment_data"] = {"attached_characters": []}
	PM.transition_to_phase(P_SHOOT)
	var sp = PM.current_phase_instance
	var paused: bool = sp._ork11e_start_reactive_move(1, "surge", {"unit_id": "U_SHIELD_CAPTAIN_A", "source": "Vengeful Surge", "roll_bonus": 2})
	var fu: Dictionary = sp._ork11e_followup
	_check("ShootingPhase surge follow-up: max distance = D6 + 2", paused and int(fu.get("max_inches", 0)) == int(fu.get("roll", 0)) + 2, str(fu))
	sp._ork11e_followup = {}


# ---------------------------------------------------------------------------
# 5. Praesidium Shield — Shield-Captain -1 D (per model), Sentinel Guard -1 to wound
# ---------------------------------------------------------------------------
func _alloc(target: String, n: int, dmg: String) -> Dictionary:
	var rolls: Array = []
	for _i in range(n):
		rolls.append(1)
	var sd := {"target_unit_id": target, "wounds_to_save": n, "ap": -4, "damage_raw": dmg, "damage": int(dmg),
		"shooter_unit_id": "U_BOYZ_B", "devastating_wounds": 0, "has_devastating_wounds": false}
	return RE.resolve_allocation_batch_11e(sd, [], GS.state, RE.make_rng(), {"forced_save_rolls": rolls})


func _section_praesidium_shield() -> void:
	print("\n-- 5. Praesidium Shield --")
	_fresh(P_SHOOT, 2)
	_place("U_SHIELD_CAPTAIN_A", 20, 40)
	_place("U_BOYZ_B", 20, 30)
	var sc := _u("U_SHIELD_CAPTAIN_A")
	var r: Dictionary = CA.allocated_damage(2, sc, sc.models[0], 0)
	_check("D2 attack allocated to the Shield-Captain: 1 damage", int(r.damage) == 1 and str(r.note).contains("Praesidium Shield"), str(r))
	_check("minimum 1 (D1 stays 1)", int(CA.allocated_damage(1, sc, sc.models[0], 0).damage) == 1)
	_check("D3 -> 2", int(CA.allocated_damage(3, sc, sc.models[0], 0).damage) == 2)
	_check("not cumulative with another -1 D already applied", int(CA.allocated_damage(3, sc, sc.models[0], 1).damage) == 3)
	var sent := _u("U_SENTINEL_A")
	_check("Sentinel Guard's Praesidium Shield is not the -1 D rule", int(CA.allocated_damage(2, sent, sent.models[0], 0).damage) == 2)
	# A/B real allocation (failed saves forced): 2 x D2 vs the Shield-Captain.
	var w0 := _wounds_left("U_SHIELD_CAPTAIN_A")
	var out: Dictionary = _alloc("U_SHIELD_CAPTAIN_A", 2, "2")
	var notes: Array = out.get("dice", []).filter(func(d): return str(d.get("context", "")) == "damage_modifier")
	_check("allocation: 2 failed saves x D2 deal 2 damage (not 4)", int(out.damage_applied) == 2, "damage %d" % int(out.damage_applied))
	_check("the dice log carries a 'Praesidium Shield: -1 Damage' line per attack", notes.size() == 2 and str(notes[0].get("message", "")).contains("-1 Damage"), str(notes))
	_flags("U_SHIELD_CAPTAIN_A")
	var save_ab: Array = GS.state.units["U_SHIELD_CAPTAIN_A"].meta.abilities.duplicate()
	GS.state.units["U_SHIELD_CAPTAIN_A"].meta.abilities = save_ab.filter(func(a): return CA.fold(str(a.get("name", "")) if a is Dictionary else str(a)) != "praesidium shield")
	out = _alloc("U_SHIELD_CAPTAIN_A", 2, "2")
	_check("A/B without the shield: 4 damage", int(out.damage_applied) == 4, "damage %d" % int(out.damage_applied))
	GS.state.units["U_SHIELD_CAPTAIN_A"].meta.abilities = save_ab
	# Attached to Custodian Guard: only attacks allocated to the Captain's model.
	_place("U_GUARD_A", 22, 41)
	_attach("U_SHIELD_CAPTAIN_A", "U_GUARD_A")
	out = _alloc("U_GUARD_A", 1, "2")
	_check("Attached: an attack allocated to a bodyguard model keeps D2", int(out.damage_applied) == 2 and out.get("dice", []).filter(func(d): return str(d.get("context", "")) == "damage_modifier").is_empty(), str(out.damage_applied))
	for m in GS.state.units["U_GUARD_A"].models:
		m["alive"] = false
		m["current_wounds"] = 0
	out = _alloc("U_GUARD_A", 1, "2")
	_check("Attached: the attack allocated to the Shield-Captain's model has -1 D", int(out.damage_applied) == 1, str(out.damage_applied))
	# Sentinel Guard: S > T attacks have -1 to wound.
	_check("Sentinel Guard (shield): S8 vs T7 -1 to wound", CA.incoming_wound_penalty(_u("U_SENTINEL_A"), 8, 7))
	_check("S7 vs T7: no penalty", not CA.incoming_wound_penalty(_u("U_SENTINEL_A"), 7, 7))
	_check("Shield-Captain's shield is not the -1 to wound rule", not CA.incoming_wound_penalty(_u("U_SHIELD_CAPTAIN_B"), 8, 7))
	_check("RulesEngine ledger name", RE.ork11e_ab_wound_penalty_name(_u("U_SENTINEL_A"), 8, 7) == "Praesidium Shield")


# ---------------------------------------------------------------------------
# 6. Archeotech Teleport-shunter (Once per battle, per unit)
# ---------------------------------------------------------------------------
func _section_teleport_shunter() -> void:
	print("\n-- 6. Archeotech Teleport-shunter --")
	_fresh(P_MOV, 1, 2)
	_place("U_SC_ALLARUS_A", 20, 50)
	_place("U_ALLARUS_A", 22, 52)
	_attach("U_SC_ALLARUS_A", "U_ALLARUS_A")
	var ctx := {"phase": "movement"}
	var o := _offer(1, "movement_phase_start", ctx, "archeotech_teleport_shunter")
	_check("offered at the start of your Movement phase (the Attached unit)", _offer_units(o) == ["U_ALLARUS_A"], str(_offer_units(o)))
	_phase(P_MOV, 2)
	_check("not in the opponent's Movement phase", _offer(1, "movement_phase_start", ctx, "archeotech_teleport_shunter").is_empty())
	_phase(P_MOV, 1)
	GS.state.meta["battle_round"] = 1
	_check("not in battle round 1 (reserves cannot arrive — it must make an ingress move this phase)", _offer(1, "movement_phase_start", ctx, "archeotech_teleport_shunter").is_empty())
	GS.state.meta["battle_round"] = 2
	_place("U_BOYZ_B", 22, 53.8)
	_check("not while engaged", _offer(1, "movement_phase_start", ctx, "archeotech_teleport_shunter").is_empty())
	GS.state.units["U_BOYZ_B"]["status"] = 7
	for m in GS.state.units["U_BOYZ_B"].models:
		m["position"] = null
	var res := _use(1, "archeotech_teleport_shunter", "U_ALLARUS_A", "movement_phase_start", ctx)
	_check("use: both components in strategic reserves", res.get("success", false) and int(_u("U_ALLARUS_A").status) == 7 and int(_u("U_SC_ALLARUS_A").status) == 7 \
		and str(_u("U_ALLARUS_A").get("reserve_type", "")) == "strategic_reserves", str(res))
	_check("models off the table", _u("U_ALLARUS_A").models[0].get("position") == null)
	_check("must make an ingress move this phase", CA.pending_forced_ingress(1) == ["U_ALLARUS_A"], str(CA.pending_forced_ingress(1)))
	_check("once per battle", UAM.is_once_per_battle_used("U_SC_ALLARUS_A", "Archeotech Teleport-shunter"))
	PM.transition_to_phase(P_MOV)
	CA.on_phase_transition(P_CMD, P_MOV)  # (transition_to_phase clears phase-scoped flags: restore the use's state)
	GS.state.units["U_ALLARUS_A"].flags[CA.F_MUST_INGRESS] = {"player": 1, "round": 2}
	var mp = PM.current_phase_instance
	var v: Dictionary = mp._validate_end_movement({"type": "END_MOVEMENT"})
	_check("END_MOVEMENT refused while it is still in reserves", not v.get("valid", true) and str(v.get("errors", [])).contains("Teleport-shunter"), str(v))
	_place("U_ALLARUS_A", 22, 30)
	GS.state.units["U_ALLARUS_A"]["status"] = 2
	v = mp._validate_end_movement({"type": "END_MOVEMENT"})
	_check("END_MOVEMENT allowed once it arrived", not str(v.get("errors", [])).contains("Teleport-shunter"), str(v))
	PM.transition_to_phase(P_SHOOT)
	_check("the forced-ingress flag expires with the phase", not _u("U_ALLARUS_A").get("flags", {}).has(CA.F_MUST_INGRESS))


# ---------------------------------------------------------------------------
# 7. Sweeping Advance — "if this unit was eligible to fight this phase"
# ---------------------------------------------------------------------------
func _section_sweeping_advance() -> void:
	print("\n-- 7. Sweeping Advance eligibility --")
	_fresh(P_FIGHT)
	_place("U_SC_JETBIKE_A", 20, 40)
	_place("U_BOYZ_B", 30, 20)
	_check("not eligible: unengaged, did not fight, not eligible at the phase start", CA.sweeping_advance_candidates([]).is_empty())
	_check("eligible: it fought", CA.sweeping_advance_candidates(["U_SC_JETBIKE_A"]) == ["U_SC_JETBIKE_A"])
	_place("U_BOYZ_B", 20, 38.2)
	_check("eligible: engaged now (eligible to fight) though it did not fight", CA.sweeping_advance_candidates([]) == ["U_SC_JETBIKE_A"])
	_place("U_BOYZ_B", 30, 20)
	_flags("U_SC_JETBIKE_A")[CA.F_FIGHT_ELIGIBLE] = true
	_check("eligible: engaged at the start of the phase (its enemy died before it fought)", CA.sweeping_advance_candidates([]) == ["U_SC_JETBIKE_A"])
	_flags("U_SC_JETBIKE_A").erase(CA.F_FIGHT_ELIGIBLE)
	# The phase entry stamp.
	_place("U_BOYZ_B", 20, 38.2)
	CA.on_phase_transition(P_CHG, P_FIGHT)
	_check("stamped at the start of the Fight phase while engaged", bool(_flags("U_SC_JETBIKE_A").get(CA.F_FIGHT_ELIGIBLE, false)))
	CA.on_phase_transition(P_FIGHT, P_CMD)
	_check("stamp cleared after the Fight phase", not _flags("U_SC_JETBIKE_A").has(CA.F_FIGHT_ELIGIBLE))


# ---------------------------------------------------------------------------
# 8. Living Fortress / Vexilla
# ---------------------------------------------------------------------------
func _section_wardens_vexilla() -> void:
	print("\n-- 8. Living Fortress / Vexilla --")
	_fresh(P_SHOOT, 2)
	_place("U_WARDENS_A", 20, 40)
	_check("Living Fortress: attacks that target the Wardens have -1 AP", EP.get_effect_worsen_ap(_u("U_WARDENS_A")) == 1)
	_check("not other units", EP.get_effect_worsen_ap(_u("U_GUARD_A")) == 0)
	_place("U_SC_ALLARUS_A", 22, 42)
	_place("U_ALLARUS_A", 24, 44)
	_check("Vexilla: +1 OC applied at army load (Wardens 2 -> 3)", int(_u("U_WARDENS_A").meta.stats.objective_control) == 3, str(_u("U_WARDENS_A").meta.stats.objective_control))
	_check("no Vexilla: OC unchanged (Guard B 3)", int(_u("U_GUARD_B").meta.stats.objective_control) == 3)
	var CP = load("res://phases/CommandPhase.gd")
	_place("U_GUARD_A", 30, 40)
	_place("U_GUARD_B", 36, 40)
	var base_a: int = CP._get_effective_leadership("U_GUARD_A")
	var base_b: int = CP._get_effective_leadership("U_GUARD_B")
	for uid in ["U_GUARD_A", "U_GUARD_B"]:
		_flags(uid)["ork11e_ab_madcap"] = {"player": 2, "effect": "zapped"}
	_check("Vexilla: the Madcap 'zapped' Ld worsening is ignored", CP._get_effective_leadership("U_GUARD_A") == base_a, "%d vs %d" % [CP._get_effective_leadership("U_GUARD_A"), base_a])
	_check("without a Vexilla it applies (+1 to the Ld roll needed)", CP._get_effective_leadership("U_GUARD_B") == base_b + 1, "%d vs %d" % [CP._get_effective_leadership("U_GUARD_B"), base_b])
	_flags("U_GUARD_B")["effect_improve_leadership"] = 1
	_flags("U_GUARD_A")["effect_improve_leadership"] = 1
	_check("beneficial Ld modifiers are kept with a Vexilla", CP._get_effective_leadership("U_GUARD_A") == base_a - 1)


# ---------------------------------------------------------------------------
# 9. Slayer of Tyrants
# ---------------------------------------------------------------------------
func _section_slayer_of_tyrants() -> void:
	print("\n-- 9. Slayer of Tyrants --")
	_fresh(P_FIGHT)
	_place("U_ALLARUS_A", 20, 40)
	_place("U_DEFF_DREAD_A", 20, 38)
	_place("U_BOYZ_B", 30, 38)
	var m := _mods("U_ALLARUS_A", "U_DEFF_DREAD_A", true)
	_check("melee vs a higher T (Deff Dread T9 > T8): +1 to wound", bool(m.wound_plus) and "Slayer of Tyrants" in _names(m), str(_names(m)))
	m = _mods("U_ALLARUS_A", "U_BOYZ_B", true)
	_check("melee vs a lower T (Boyz T5): no bonus", not bool(m.wound_plus))
	m = _mods("U_ALLARUS_A", "U_DEFF_DREAD_A", false)
	_check("ranged attacks: no bonus", not "Slayer of Tyrants" in _names(m))


# ---------------------------------------------------------------------------
# 10. Quicksilver Execution — charged: melee [SUSTAINED HITS 1]
# ---------------------------------------------------------------------------
func _section_quicksilver_execution() -> void:
	print("\n-- 10. Quicksilver Execution --")
	_fresh(P_FIGHT)
	_place("U_VERTUS_A", 20, 40)
	_place("U_BOYZ_B", 20, 37.8)
	var m := _mods("U_VERTUS_A", "U_BOYZ_B", true)
	_check("no charge: no [SUSTAINED HITS]", int(m.sustained) == 0)
	_flags("U_VERTUS_A")["charged_this_turn"] = true
	m = _mods("U_VERTUS_A", "U_BOYZ_B", true)
	_check("charged: melee [SUSTAINED HITS 1]", int(m.sustained) == 1 and "Quicksilver Execution" in _names(m))
	_check("charged: ranged attacks unaffected", int(_mods("U_VERTUS_A", "U_BOYZ_B", false).sustained) == 0)
	# A/B: the melee resolver applies the granted Sustained Hits (consumer hook).
	var lance := _weapon("U_VERTUS_A", "lance")
	var s6 := _seed_where(9, func(r): return r.count(6) >= 2)
	var a: Dictionary = _melee_hits("U_VERTUS_A", lance, "U_BOYZ_B", s6)
	_flags("U_VERTUS_A").erase("charged_this_turn")
	var b: Dictionary = _melee_hits("U_VERTUS_A", lance, "U_BOYZ_B", s6)
	var a_txt := str(a.res.get("log_text", ""))
	_check("A/B (same seed): more hits with the charge (%d vs %d)" % [int(a.hits) + int(a.bonus), int(b.hits) + int(b.bonus)],
		int(a.hits) + int(a.bonus) > int(b.hits) + int(b.bonus), "%s | %s" % [str(a.hits), str(b.hits)])


# ---------------------------------------------------------------------------
# 11. Unyielding Ancient — S > T: -1 to wound
# ---------------------------------------------------------------------------
func _section_unyielding_ancient() -> void:
	print("\n-- 11. Unyielding Ancient --")
	_fresh(P_SHOOT, 2)
	_check("Contemptor-Achillus: S11 vs T10 -1 to wound", CA.incoming_wound_penalty(_u("U_ACHILLUS_A"), 11, 10))
	_check("Contemptor-Galatus too", CA.incoming_wound_penalty(_u("U_GALATUS_A"), 12, 10))
	_check("S10 vs T10: no penalty", not CA.incoming_wound_penalty(_u("U_ACHILLUS_A"), 10, 10))
	_check("RulesEngine reads it (ork11e_ab_wound_penalty)", RE.ork11e_ab_wound_penalty(_u("U_ACHILLUS_A"), 11, 10))
	_check("ledger name", RE.ork11e_ab_wound_penalty_name(_u("U_ACHILLUS_A"), 11, 10) == "Unyielding Ancient")
	_check("other units: none", not CA.incoming_wound_penalty(_u("U_TELEMON_A"), 12, 11))


# ---------------------------------------------------------------------------
# 12. Destructor Optics — ranged +1 AP vs non-MONSTER/VEHICLE
# ---------------------------------------------------------------------------
func _section_destructor_optics() -> void:
	print("\n-- 12. Destructor Optics --")
	_fresh(P_SHOOT)
	_place("U_CALADIUS_A", 20, 40)
	_place("U_BOYZ_B", 20, 30)
	_place("U_DEFF_DREAD_A", 30, 30)
	_check("vs INFANTRY: +1 AP", int(_mods("U_CALADIUS_A", "U_BOYZ_B", false).ap) == 1)
	_check("vs VEHICLE: none", int(_mods("U_CALADIUS_A", "U_DEFF_DREAD_A", false).ap) == 0)
	_check("melee: none", int(_mods("U_CALADIUS_A", "U_BOYZ_B", true).ap) == 0)


# ---------------------------------------------------------------------------
# 13. Repulsor Suspensor Technology (Once per phase, per unit)
# ---------------------------------------------------------------------------
func _section_repulsor_suspensor() -> void:
	print("\n-- 13. Repulsor Suspensor Technology --")
	_fresh(P_SHOOT, 2)
	_place("U_CORONUS_A", 20, 40)
	_place("U_BOYZ_B", 20, 30)
	var ctx := {"phase": "shooting", "attacker_unit_id": "U_BOYZ_B", "hit_unit_ids": ["U_CORONUS_A"], "wounded_unit_ids": ["U_CORONUS_A"]}
	var o := _offer(1, "enemy_has_shot", ctx, "repulsor_suspensor_technology")
	_check("offered when the Coronus lost a wound to the enemy's shooting", _offer_units(o) == ["U_CORONUS_A"], str(_offer_units(o)))
	var c2 := ctx.duplicate(true)
	c2["wounded_unit_ids"] = []
	_check("not when it lost no wound", _offer(1, "enemy_has_shot", c2, "repulsor_suspensor_technology").is_empty())
	_place("U_GRETCHIN_C", 20, 38.0)
	_check("not while engaged", _offer(1, "enemy_has_shot", ctx, "repulsor_suspensor_technology").is_empty())
	GS.state.units["U_GRETCHIN_C"]["status"] = 7
	for m in GS.state.units["U_GRETCHIN_C"].models:
		m["position"] = null
	var res := _use(1, "repulsor_suspensor_technology", "U_CORONUS_A", "enemy_has_shot", ctx)
	var fu: Dictionary = res.get("followup", {})
	_check("use: normal move of up to D6\" (reactive normal move follow-up)", res.get("success", false) and str(fu.get("type", "")) == "reactive_normal_move" \
		and float(fu.get("max_inches", 0)) >= 1.0 and float(fu.get("max_inches", 0)) <= 6.0, str(res))
	_check("once per phase", _offer(1, "enemy_has_shot", ctx, "repulsor_suspensor_technology").is_empty())
	GS.state.meta["phase"] = P_SHOOT
	GS.state.meta["battle_round"] = 3
	_check("usable again in a later phase", not _offer(1, "enemy_has_shot", ctx, "repulsor_suspensor_technology").is_empty())


# ---------------------------------------------------------------------------
# 14. Assault Vehicle — not implemented (no shock disembark move in the rules)
# ---------------------------------------------------------------------------
func _section_assault_vehicle() -> void:
	print("\n-- 14. Assault Vehicle (not implemented) --")
	_fresh(P_MOV)
	_place("U_CORONUS_A", 20, 40)
	var c := {"phase": "movement", "unit_id": "U_CORONUS_A", "window_id": "unit_ended_advance_move"}
	_check("no ability card at the end of an advance move (documented gap)", CA.window_offers(1, "unit_ended_advance_move", c).is_empty())
	_check("ABILITY_EFFECTS row says it is not implemented", str(UAM.ABILITY_EFFECTS.get("Assault Vehicle", {}).get("description", "")).contains("not implemented"))
	_check("... and is_ability_implemented says so", not UAM.is_ability_implemented("Assault Vehicle"))


# ---------------------------------------------------------------------------
# 15. Guardian Eternal — ranged attacks -1 D
# ---------------------------------------------------------------------------
func _section_guardian_eternal() -> void:
	print("\n-- 15. Guardian Eternal --")
	_fresh(P_SHOOT, 2)
	_place("U_TELEMON_A", 20, 40)
	_check("Shooting phase (ranged): -1 D", EP.get_effect_minus_damage(_u("U_TELEMON_A")) == 1)
	_phase(P_FIGHT, 2)
	_check("Fight phase (melee): no reduction (the 10e 'all attacks' row is gone)", EP.get_effect_minus_damage(_u("U_TELEMON_A")) == 0)
	_check("the ABILITY_EFFECTS row no longer grants a flag", UAM.ABILITY_EFFECTS.get("Guardian Eternal", {}).get("effects", [1]).is_empty())


# ---------------------------------------------------------------------------
# 16. Mobile Hunter
# ---------------------------------------------------------------------------
func _section_mobile_hunter() -> void:
	print("\n-- 16. Mobile Hunter --")
	_fresh(P_SHOOT)
	_place("U_PALLAS_A", 20, 40)
	_place("U_BOYZ_B", 20, 25)
	var ctx := {"phase": "shooting", "unit_id": "U_PALLAS_A", "hit_unit_ids": ["U_BOYZ_B"]}
	var o := _offer(1, "unit_has_shot", ctx, "mobile_hunter")
	_check("offered when the Pallas has shot", _offer_units(o) == ["U_PALLAS_A"])
	_check("not for another shooter", _offer(1, "unit_has_shot", {"phase": "shooting", "unit_id": "U_CALADIUS_A"}, "mobile_hunter").is_empty())
	_phase(P_SHOOT, 2)
	_check("not in the opponent's Shooting phase", _offer(1, "unit_has_shot", ctx, "mobile_hunter").is_empty())
	_phase(P_SHOOT, 1)
	var res := _use(1, "mobile_hunter", "U_PALLAS_A", "unit_has_shot", ctx)
	_check("use: normal move up to D6\" follow-up + no-charge lock", res.get("success", false) and str(res.get("followup", {}).get("type", "")) == "reactive_normal_move" \
		and bool(_flags("U_PALLAS_A").get(CA.F_NO_CHARGE, false)), str(res))
	PM.transition_to_phase(P_CHG)
	var cp = PM.current_phase_instance
	_check("not eligible to declare a charge this turn", not cp._can_unit_charge(_u("U_PALLAS_A")))
	_check("... RulesEngine.eligible_to_charge agrees", not RE.eligible_to_charge("U_PALLAS_A", GS.state))
	_check("... and the 11e charge template", not bool(MoveTypes.get_type("charge").eligible("U_PALLAS_A", GS.state).get("eligible", true)))
	CA.on_phase_transition(P_FIGHT, P_CMD)
	_check("the lock ends with the turn", not _flags("U_PALLAS_A").has(CA.F_NO_CHARGE))


# ---------------------------------------------------------------------------
# 17. Assault Dropship
# ---------------------------------------------------------------------------
func _section_assault_dropship() -> void:
	print("\n-- 17. Assault Dropship --")
	_fresh(P_MOV)
	var d: Array = CA.on_disembark("U_GUARD_A", "U_ORION_A", "tactical")
	_check("tactical disembark from the Orion: flag diffs", d.size() == 1 and str(d[0].path).ends_with(CA.F_DROPSHIP), str(d))
	_check("rapid disembark: no", CA.on_disembark("U_GUARD_A", "U_ORION_A", "rapid").is_empty())
	_check("from another transport (Coronus): no", CA.on_disembark("U_GUARD_A", "U_CORONUS_A", "tactical").is_empty())
	_flags("U_GUARD_A")[CA.F_DROPSHIP] = true
	_check("the advance move does not prevent a charge (advance_and_charge)", EP.has_effect_advance_and_charge(_u("U_GUARD_A")))
	_check("other units: unchanged", not EP.has_effect_advance_and_charge(_u("U_GUARD_B")))
	CA.on_phase_transition(P_FIGHT, P_CMD)
	_check("expires at the end of the turn", not _flags("U_GUARD_A").has(CA.F_DROPSHIP))


# ---------------------------------------------------------------------------
# 18. Infernus Firebombs
# ---------------------------------------------------------------------------
func _section_infernus_firebombs() -> void:
	print("\n-- 18. Infernus Firebombs --")
	_fresh(P_FIGHT, 2)
	_place("U_ARES_A", 20, 50)
	_place("U_BOYZ_B", 20, 35)
	_place("U_GRETCHIN_C", 5, 10)   # > 24"
	var ctx := {"phase": "fight"}
	var o := _offer(1, "fight_phase_end", ctx, "infernus_firebombs")
	_check("offered at the end of the opponent's Fight phase", _offer_units(o) == ["U_ARES_A"])
	_check("targets: visible enemy units within 24\" only", _secondary_ids(o, "U_ARES_A") == ["U_BOYZ_B"], str(_secondary_ids(o, "U_ARES_A")))
	_phase(P_FIGHT, 1)
	_check("not at the end of your own Fight phase", _offer(1, "fight_phase_end", ctx, "infernus_firebombs").is_empty())
	_phase(P_FIGHT, 2)
	var s := _seed_where(10, func(r): return r.count(6) >= 1)
	var sixes: int = RE.make_rng().roll_d6(10).count(6)
	RE.set_test_seed(s)
	var w0 := _wounds_left("U_BOYZ_B")
	var res := _use(1, "infernus_firebombs", "U_ARES_A", "fight_phase_end", ctx, "U_BOYZ_B")
	_check("use: one D6 per model, each 6 is a mortal wound (%d six(es))" % sixes, res.get("success", false) and w0 - _wounds_left("U_BOYZ_B") == mini(sixes, 6), "%d lost" % (w0 - _wounds_left("U_BOYZ_B")))
	RE.set_test_seed(-1)
	_check("the target is marked", typeof(_flags("U_BOYZ_B").get(CA.F_FIREBOMBED, null)) == TYPE_DICTIONARY)
	_check("one trigger per unit: not re-offered in the same window (the re-offer / AI loop guard)", _offer(1, "fight_phase_end", ctx, "infernus_firebombs").is_empty())
	_check("... and a second use is refused", not _use(1, "infernus_firebombs", "U_ARES_A", "fight_phase_end", ctx, "U_BOYZ_B").get("success", false))
	_place("U_CALADIUS_A", 30, 50)
	var m := _mods("U_CALADIUS_A", "U_BOYZ_B", false)
	_check("your ranged attacks that target it have [IGNORES COVER]", bool(m.ignores_cover) and "Infernus Firebombs" in _names(m))
	_check("melee attacks: no", not bool(_mods("U_CALADIUS_A", "U_BOYZ_B", true).ignores_cover))
	_check("the opponent's attacks: no", not bool(_mods("U_GRETCHIN_C", "U_BOYZ_B", false).ignores_cover))
	# "until the end of your next turn": P1's next turn starts (armed), then ends.
	GS.state.meta["active_player"] = 1
	CA.on_phase_transition(P_FIGHT, P_CMD)
	_check("lasts into your next turn", typeof(_flags("U_BOYZ_B").get(CA.F_FIREBOMBED, null)) == TYPE_DICTIONARY)
	GS.state.meta["active_player"] = 2
	CA.on_phase_transition(P_FIGHT, P_CMD)
	_check("ends when your next turn has ended", not _flags("U_BOYZ_B").has(CA.F_FIREBOMBED))
	# AIRCRAFT / Lone Operative excluded.
	_fresh(P_FIGHT, 2)
	_place("U_ARES_A", 20, 50)
	_place("U_WARBOSS_A", 20, 40)
	_flags("U_WARBOSS_A")
	var ab: Array = GS.state.units["U_WARBOSS_A"].meta.abilities
	ab.append({"name": "Lone Operative"})
	o = _offer(1, "fight_phase_end", ctx, "infernus_firebombs")
	_check("Lone Operative units cannot be selected", not "U_WARBOSS_A" in _secondary_ids(o, "U_ARES_A"), str(_secondary_ids(o, "U_ARES_A")))


# ---------------------------------------------------------------------------
# 19. Swift Onslaught / Seeker's Instincts — re-roll advance / charge rolls
# ---------------------------------------------------------------------------
func _section_swift_onslaught_seekers() -> void:
	print("\n-- 19. Swift Onslaught / Seeker's Instincts --")
	_fresh(P_CHG)
	_place("U_GUARD_A", 20, 40)
	_place("U_BLADE_CHAMPION_A", 23, 40)
	_check("Custodian Guard alone: no re-roll", not EP.has_effect_reroll_charge(_u("U_GUARD_A")))
	_attach("U_BLADE_CHAMPION_A", "U_GUARD_A")
	_check("led by the Blade Champion: charge re-roll (this unit)", EP.has_effect_reroll_charge(_u("U_GUARD_A")) and CA.charge_reroll_source(_u("U_GUARD_A")) == "Swift Onslaught")
	_check("advance re-roll", EP.has_effect_reroll_advance(_u("U_GUARD_A")))
	_place("U_KNIGHT_CENTURA_A", 10, 40)
	_check("Seeker's Instincts: +2\" M", CA.move_modifier(_u("U_KNIGHT_CENTURA_A")) == 2.0)
	_check("Seeker's Instincts: charge re-roll", CA.charge_reroll_source(_u("U_KNIGHT_CENTURA_A")) == "Seeker's Instincts")
	PM.transition_to_phase(P_MOV)
	var base_m: float = float(_u("U_KNIGHT_CENTURA_A").meta.stats.move)
	_check("MovementPhase move characteristic includes the +2\"", float(PM.current_phase_instance.get_unit_movement(_u("U_KNIGHT_CENTURA_A"))) == base_m + 2.0, str(PM.current_phase_instance.get_unit_movement(_u("U_KNIGHT_CENTURA_A"))))
	PM.transition_to_phase(P_CHG)
	_check("ChargePhase names the re-roll source", PM.current_phase_instance._get_charge_reroll_ability_name("U_GUARD_A") == "Swift Onslaught", PM.current_phase_instance._get_charge_reroll_ability_name("U_GUARD_A"))


# ---------------------------------------------------------------------------
# 20. Sword of the Throne
# ---------------------------------------------------------------------------
func _section_sword_of_the_throne() -> void:
	print("\n-- 20. Sword of the Throne --")
	_fresh(P_CMD, 1, 1)
	_place("U_BLADE_CHAMPION_A", 20, 40)
	_place("U_BOYZ_B", 20, 30)
	_place("U_DEFF_DREAD_A", 30, 30)
	var ctx := {"phase": "command"}
	var o := _offer(1, "phase_start", ctx, "sword_of_the_throne")
	_check("offered at the start of the first battle round", _offer_units(o) == ["U_BLADE_CHAMPION_A"])
	_check("any enemy unit can be the mark (closest first)", _secondary_ids(o, "U_BLADE_CHAMPION_A").size() >= 2 and _secondary_ids(o, "U_BLADE_CHAMPION_A")[0] == "U_BOYZ_B", str(_secondary_ids(o, "U_BLADE_CHAMPION_A")))
	_phase(P_CMD, 2)
	_check("also when the opponent's turn starts the round", not _offer(1, "phase_start", ctx, "sword_of_the_throne").is_empty())
	var res := _use(1, "sword_of_the_throne", "U_BLADE_CHAMPION_A", "phase_start", ctx, "U_DEFF_DREAD_A")
	_check("use: the Deff Dread is the mark", res.get("success", false) and str(_flags("U_BLADE_CHAMPION_A").get(CA.F_MARK, "")) == "U_DEFF_DREAD_A")
	_check("not offered again while the mark lives", _offer(1, "phase_start", ctx, "sword_of_the_throne").is_empty())
	_phase(P_FIGHT, 1)
	var m := _mods("U_BLADE_CHAMPION_A", "U_DEFF_DREAD_A", true)
	_check("this model's attacks vs its mark: +1 to wound", bool(m.wound_plus) and "Sword of the Throne" in _names(m))
	_check("vs another unit: none", not bool(_mods("U_BLADE_CHAMPION_A", "U_BOYZ_B", true).wound_plus))
	_place("U_GUARD_A", 22, 41)
	_attach("U_BLADE_CHAMPION_A", "U_GUARD_A")
	_check("the bodyguard's attacks vs the mark: none (\"this model\")", not "Sword of the Throne" in _names(_mods("U_GUARD_A", "U_DEFF_DREAD_A", true)))
	# Mark destroyed -> select a new one.
	for mm in GS.state.units["U_DEFF_DREAD_A"].models:
		mm["alive"] = false
	GS.state.meta["battle_round"] = 3
	o = _offer(1, "phase_start", ctx, "sword_of_the_throne")
	_check("its mark destroyed: a new mark is offered at the next phase start", _offer_units(o) == ["U_BLADE_CHAMPION_A"] and not "U_DEFF_DREAD_A" in _secondary_ids(o, "U_BLADE_CHAMPION_A"))
	_fresh(P_CMD, 1, 2)
	_place("U_BLADE_CHAMPION_A", 20, 40)
	_place("U_BOYZ_B", 20, 30)
	_check("battle round 2 with no mark (game loaded past round 1): not offered", _offer(1, "phase_start", ctx, "sword_of_the_throne").is_empty())


# ---------------------------------------------------------------------------
# 21. Corner the Quarry
# ---------------------------------------------------------------------------
func _section_corner_the_quarry() -> void:
	print("\n-- 21. Corner the Quarry --")
	_fresh(P_MOV, 2)
	_place("U_KNIGHT_CENTURA_A", 20, 40)
	_place("U_BOYZ_B", 20, 38.3)
	var fb = load("res://scripts/rules/movetypes/FallBackMove.gd").new()
	var sel: Dictionary = fb.select_mode("U_BOYZ_B", GS.state)
	_check("an engaged enemy unit must use desperate escape", str(sel.mode) == "desperate_escape" and bool(sel.mandatory), str(sel))
	_check("no hazard modifier while not battle-shocked", CA.corner_the_quarry_hazard_modifier("U_BOYZ_B") == 0)
	_flags("U_BOYZ_B")["battle_shocked"] = true
	_check("battle-shocked: -1 to those hazard rolls", CA.corner_the_quarry_hazard_modifier("U_BOYZ_B") == -1)
	_flags("U_BOYZ_B").erase("battle_shocked")
	_place("U_BOYZ_B", 20, 20)
	_place("U_DEFF_DREAD_A", 20, 38.0)
	_check("VEHICLE enemy units are excluded", CA.corner_the_quarry_source("U_DEFF_DREAD_A") == "")
	_check("an enemy that is not engaged with it: free choice", str(fb.select_mode("U_BOYZ_B", GS.state).mode) == "ordered_retreat")


# ---------------------------------------------------------------------------
# 22. Impenetrable Defence / Stand Vigil (objective range, non-MONSTER/VEHICLE)
# ---------------------------------------------------------------------------
func _section_impenetrable_stand_vigil() -> void:
	print("\n-- 22. Impenetrable Defence / Stand Vigil --")
	_fresh(P_SHOOT)
	_place("U_GUARD_A", 33, 38)       # on obj_nml_2 (34, 38)
	_place("U_SENTINEL_A", 9, 22)     # on obj_nml_1 (10, 22)
	_place("U_GUARD_B", 20, 50)       # off objectives
	_place("U_BOYZ_B", 20, 44)
	_place("U_DEFF_DREAD_A", 40, 30)
	_check("Guard on an objective: [SUSTAINED HITS 1] vs INFANTRY", int(_mods("U_GUARD_A", "U_BOYZ_B", false).sustained) == 1)
	_check("melee too", int(_mods("U_GUARD_A", "U_BOYZ_B", true).sustained) == 1)
	_check("vs a VEHICLE: none", int(_mods("U_GUARD_A", "U_DEFF_DREAD_A", false).sustained) == 0)
	_check("Guard B off objectives, target off: none", int(_mods("U_GUARD_B", "U_BOYZ_B", false).sustained) == 0)
	_place("U_BOYZ_B", 30, 34)        # Boyz within range of obj_nml_2
	_check("the target within range of an objective: yes", int(_mods("U_GUARD_B", "U_BOYZ_B", false).sustained) == 1)
	_check("Sentinel Guard on an objective: [LETHAL HITS] vs INFANTRY", bool(_mods("U_SENTINEL_A", "U_BOYZ_B", false).lethal))
	_check("Sentinel vs a VEHICLE: none", not bool(_mods("U_SENTINEL_A", "U_DEFF_DREAD_A", false).lethal))


# ---------------------------------------------------------------------------
# 23. Purity of Execution
# ---------------------------------------------------------------------------
func _section_purity_of_execution() -> void:
	print("\n-- 23. Purity of Execution --")
	_fresh(P_SHOOT)
	_place("U_PROSECUTORS_A", 20, 40)
	_place("U_BOYZ_B", 20, 28)        # within 18"
	_place("U_GRETCHIN_C", 5, 5)      # beyond 18"
	var ctx := {"phase": "shooting", "unit_id": "U_PROSECUTORS_A"}
	var o := _offer(1, "unit_selected_to_shoot", ctx, "purity_of_execution")
	_check("offered when the Prosecutors are selected to shoot", _offer_units(o) == ["U_PROSECUTORS_A"])
	_check("targets: visible enemies within 18\"", _secondary_ids(o, "U_PROSECUTORS_A") == ["U_BOYZ_B"], str(_secondary_ids(o, "U_PROSECUTORS_A")))
	var tm = root.get_node("TerrainManager")
	var bm: Dictionary = _u("U_BOYZ_B").models[0]
	var pm: Dictionary = _u("U_PROSECUTORS_A").models[0]
	var before: float = tm.detection_range_inches_for(bm, _u("U_BOYZ_B"), pm)
	var res := _use(1, "purity_of_execution", "U_PROSECUTORS_A", "unit_selected_to_shoot", ctx, "U_BOYZ_B")
	_check("use: the Boyz are detected", res.get("success", false) and typeof(_flags("U_BOYZ_B").get(CA.F_DETECTED, null)) == TYPE_DICTIONARY)
	var after: float = tm.detection_range_inches_for(bm, _u("U_BOYZ_B"), pm)
	_check("+3\" detection range (%.0f\" -> %.0f\")" % [before, after], is_equal_approx(after, before + 3.0))
	_check("once per phase", _offer(1, "unit_selected_to_shoot", ctx, "purity_of_execution").is_empty())
	CA.on_phase_transition(P_SHOOT, P_CHG)
	_check("ends with the phase", not _flags("U_BOYZ_B").has(CA.F_DETECTED))


# ---------------------------------------------------------------------------
# 24. Take Wing
# ---------------------------------------------------------------------------
func _section_take_wing() -> void:
	print("\n-- 24. Take Wing --")
	_fresh(P_FIGHT, 2)
	_place("U_VENATARI_VL_A", 20, 40)
	_place("U_VENATARI_KD_A", 30, 40)
	_place("U_BOYZ_B", 30, 38.0)
	var ctx := {"phase": "fight"}
	var o := _offer(1, "fight_phase_end", ctx, "take_wing")
	_check("offered at the end of the opponent's Fight phase, unengaged only", _offer_units(o) == ["U_VENATARI_VL_A"], str(_offer_units(o)))
	_phase(P_FIGHT, 1)
	_check("not at the end of your own Fight phase", _offer(1, "fight_phase_end", ctx, "take_wing").is_empty())
	_phase(P_FIGHT, 2)
	var res := _use(1, "take_wing", "U_VENATARI_VL_A", "fight_phase_end", ctx)
	_check("use: strategic reserves", res.get("success", false) and int(_u("U_VENATARI_VL_A").status) == 7 and _u("U_VENATARI_VL_A").models[0].get("position") == null)


# ---------------------------------------------------------------------------
# 25. Neutronium Cascade Mine (Once per battle, per unit)
# ---------------------------------------------------------------------------
func _section_neutronium_cascade_mine() -> void:
	print("\n-- 25. Neutronium Cascade Mine --")
	_fresh(P_CHG, 2)
	_place("U_VENATARI_KD_A", 20, 40)
	_place("U_BOYZ_B", 20, 37.5)       # within 3"
	_place("U_DEFF_DREAD_A", 40, 20)   # far
	var ctx := {"phase": "charge"}
	var o := _offer(1, "phase_start", ctx, "neutronium_cascade_mine")
	_check("offered at the start of any phase (the opponent's Charge phase) with an enemy within 3\"", _offer_units(o) == ["U_VENATARI_KD_A"])
	_check("targets: enemy units within 3\"", _secondary_ids(o, "U_VENATARI_KD_A") == ["U_BOYZ_B"], str(_secondary_ids(o, "U_VENATARI_KD_A")))
	var s := _seed_where(2, func(r): return int(r[0]) >= 2)
	var w0 := _wounds_left("U_BOYZ_B")
	var res := _use(1, "neutronium_cascade_mine", "U_VENATARI_KD_A", "phase_start", ctx, "U_BOYZ_B")
	RE.set_test_seed(-1)
	var lost := w0 - _wounds_left("U_BOYZ_B")
	_check("2+: D3 mortal wounds (%d)" % lost, res.get("success", false) and lost >= 1 and lost <= 3, str(res))
	_check("once per battle", _offer(1, "phase_start", ctx, "neutronium_cascade_mine").is_empty())
	_fresh(P_CHG, 2)
	_place("U_VENATARI_KD_A", 20, 40)
	_place("U_DEFF_DREAD_A", 20, 37.0)
	_seed_where(3, func(r): return int(r[0]) >= 2)
	var dw0 := _wounds_left("U_DEFF_DREAD_A")
	_use(1, "neutronium_cascade_mine", "U_VENATARI_KD_A", "phase_start", ctx, "U_DEFF_DREAD_A")
	RE.set_test_seed(-1)
	var dlost := dw0 - _wounds_left("U_DEFF_DREAD_A")
	_check("vs a VEHICLE: 2D3 mortal wounds (%d, 2..6)" % dlost, dlost >= 2 and dlost <= 6)
	_fresh(P_CHG, 2)
	_place("U_VENATARI_KD_A", 20, 40)
	_place("U_BOYZ_B", 20, 37.5)
	_seed_where(2, func(r): return int(r[0]) == 1)
	var bw0 := _wounds_left("U_BOYZ_B")
	_use(1, "neutronium_cascade_mine", "U_VENATARI_KD_A", "phase_start", ctx, "U_BOYZ_B")
	RE.set_test_seed(-1)
	_check("a 1: no effect (and the use is spent)", _wounds_left("U_BOYZ_B") == bw0 and UAM.is_once_per_battle_used("U_VENATARI_KD_A", "Neutronium Cascade Mine"))
	_place("U_BOYZ_B", 20, 30)
	_place("U_VENATARI_VL_A", 2, 2)
	_check("no enemy within 3\": not offered", _offer(1, "phase_start", ctx, "neutronium_cascade_mine").is_empty())


# ---------------------------------------------------------------------------
# 26. Swift Ruin (Once per phase, per army) — Rapid Ingress
# ---------------------------------------------------------------------------
func _ri_id() -> String:
	for sid in ["rapid_ingress_11e", "rapid_ingress"]:
		if not SM.get_stratagem(sid).is_empty():
			return sid
	return ""


## The phase the engine's Rapid Ingress row is used in (its timing.phase).
func _ri_phase() -> int:
	var ph := str(SM.get_stratagem(_ri_id()).get("timing", {}).get("phase", "movement"))
	return {"command": P_CMD, "movement": P_MOV, "shooting": P_SHOOT, "charge": P_CHG, "fight": P_FIGHT}.get(ph, P_MOV)


func _section_swift_ruin() -> void:
	print("\n-- 26. Swift Ruin --")
	_fresh(_ri_phase(), 2, 2)
	for uid in ["U_VENATARI_VL_A", "U_GUARD_A"]:
		GS.state.units[uid]["status"] = 7
		GS.state.units[uid]["reserve_type"] = "strategic_reserves"
	var ri := _ri_id()
	var strat: Dictionary = SM.get_stratagem(ri)
	_check("Rapid Ingress exists (%s)" % ri, ri != "")
	_check("applies to the Venatari with Verutum Lances", CA.swift_ruin_applies(1, strat, "U_VENATARI_VL_A"))
	_check("not to other units", not CA.swift_ruin_applies(1, strat, "U_GUARD_A"))
	_check("not to other stratagems", not CA.swift_ruin_applies(1, SM.get_stratagem("command_re_roll_11e") if not SM.get_stratagem("command_re_roll_11e").is_empty() else {"name": "COMMAND RE-ROLL"}, "U_VENATARI_VL_A"))
	# A Rapid Ingress already used this phase on another unit.
	SM._usage_history["1"].append({"stratagem_id": ri, "player": 1, "target_unit_id": "U_GUARD_A",
		"turn": GS.get_battle_round(), "phase": GS.get_current_phase(), "active_player": GS.get_active_player()})
	var chk: Dictionary = SM.can_use_stratagem(1, ri, "U_GUARD_A", {"window_id": str(strat.get("timing", {}).get("windows", [""])[0]) if not strat.get("timing", {}).get("windows", []).is_empty() else ""})
	_check("another unit: once per phase", not chk.get("can_use", true) and str(chk.get("reason", "")).contains("phase"), str(chk))
	var wid: String = str(strat.get("timing", {}).get("windows", [""])[0]) if not strat.get("timing", {}).get("windows", []).is_empty() else ""
	chk = SM.can_use_stratagem(1, ri, "U_VENATARI_VL_A", {"window_id": wid})
	_check("the Venatari: regardless of other uses this phase", chk.get("can_use", false), str(chk))
	var cp0 := int(GS.state.players["1"].cp)
	var res: Dictionary = SM.use_stratagem(1, ri, "U_VENATARI_VL_A", {"window_id": wid})
	var cost := cp0 - int(GS.state.players["1"].cp)
	_check("that use is -1 CP (%d CP)" % cost, res.get("success", false) and cost == maxi(0, int(strat.get("cp_cost", 1)) - 1), str(res.get("error", "")))
	_check("recorded as not counting against the limit", bool(SM._usage_history["1"][-1].get("cus11e_swift_ruin", false)))
	_check("once per phase, per army", not CA.swift_ruin_applies(1, strat, "U_VENATARI_VL_A"))
	# It does not prevent uses on other units: a fresh phase with only the Swift Ruin use.
	_fresh(_ri_phase(), 2, 3)
	for uid in ["U_VENATARI_VL_A", "U_GUARD_A"]:
		GS.state.units[uid]["status"] = 7
		GS.state.units[uid]["reserve_type"] = "strategic_reserves"
	res = SM.use_stratagem(1, ri, "U_VENATARI_VL_A", {"window_id": wid})
	_check("Swift Ruin use first", res.get("success", false), str(res.get("error", "")))
	chk = SM.can_use_stratagem(1, ri, "U_GUARD_A", {"window_id": wid})
	_check("Rapid Ingress still usable on another unit this phase", chk.get("can_use", false), str(chk))


# ---------------------------------------------------------------------------
# 27. Dread Foe / Death Blow (+1 AP)
# ---------------------------------------------------------------------------
func _section_dread_foe_death_blow() -> void:
	print("\n-- 27. Dread Foe / Death Blow --")
	_fresh(P_FIGHT)
	_place("U_AQUILON_G_A", 20, 40)
	_place("U_GYRFALCON_A", 30, 40)
	_place("U_BOYZ_B", 20, 38)
	_place("U_DEFF_DREAD_A", 30, 38)
	_check("Dread Foe: melee vs INFANTRY +1 AP", int(_mods("U_AQUILON_G_A", "U_BOYZ_B", true).ap) == 1)
	_check("Dread Foe: vs VEHICLE none", int(_mods("U_AQUILON_G_A", "U_DEFF_DREAD_A", true).ap) == 0)
	_check("Dread Foe: ranged none", int(_mods("U_AQUILON_G_A", "U_BOYZ_B", false).ap) == 0)
	_check("Death Blow: no charge, no AP", int(_mods("U_GYRFALCON_A", "U_DEFF_DREAD_A", true).ap) == 0)
	_flags("U_GYRFALCON_A")["charged_this_turn"] = true
	_check("Death Blow: charged, melee +1 AP (any target)", int(_mods("U_GYRFALCON_A", "U_DEFF_DREAD_A", true).ap) == 1)
	_check("Death Blow: ranged none", int(_mods("U_GYRFALCON_A", "U_DEFF_DREAD_A", false).ap) == 0)


# ---------------------------------------------------------------------------
# 28. Sanctified Flames
# ---------------------------------------------------------------------------
func _section_sanctified_flames() -> void:
	print("\n-- 28. Sanctified Flames --")
	_fresh(P_SHOOT)
	_place("U_WITCHSEEKERS_A", 20, 40)
	_place("U_BOYZ_B", 20, 34)
	_place("U_GRETCHIN_C", 30, 34)
	var ctx := {"phase": "shooting", "unit_id": "U_WITCHSEEKERS_A", "hit_unit_ids": ["U_BOYZ_B", "U_GRETCHIN_C"]}
	var o := _offer(1, "unit_has_shot", ctx, "sanctified_flames")
	_check("offered when the Witchseekers have shot", _offer_units(o) == ["U_WITCHSEEKERS_A"])
	_check("targets: the enemy units hit (highest Ld first)", _secondary_ids(o, "U_WITCHSEEKERS_A") == ["U_GRETCHIN_C", "U_BOYZ_B"], str(_secondary_ids(o, "U_WITCHSEEKERS_A")))
	var c2 := ctx.duplicate(true)
	c2["hit_unit_ids"] = []
	_check("nothing hit: not offered", _offer(1, "unit_has_shot", c2, "sanctified_flames").is_empty())
	# A failing roll (2D6 total 2 vs Ld 8+).
	_seed_where(2, func(r): return int(r[0]) + int(r[1]) <= 3)
	var res := _use(1, "sanctified_flames", "U_WITCHSEEKERS_A", "unit_has_shot", ctx, "U_GRETCHIN_C")
	RE.set_test_seed(-1)
	_check("a failed battle-shock roll battle-shocks the target", res.get("success", false) and bool(_flags("U_GRETCHIN_C").get("battle_shocked", false)), str(res))
	_check("one use per shot: not re-offered in the same window (the re-offer / AI loop guard)", _offer(1, "unit_has_shot", ctx, "sanctified_flames").is_empty())
	_check("... and a second use is refused", not _use(1, "sanctified_flames", "U_WITCHSEEKERS_A", "unit_has_shot", ctx, "U_BOYZ_B").get("success", false))
	# PSYKER: -1 to the roll.
	GS.state.units["U_BOYZ_B"].meta.keywords.append("PSYKER")
	var s7 := _seed_where(2, func(r): return int(r[0]) + int(r[1]) == 7)
	var bs: Dictionary = CA.battle_shock_roll("U_BOYZ_B", -1, "Sanctified Flames")
	RE.set_test_seed(-1)
	_check("PSYKER target: -1 to the roll (7 - 1 = 6 vs Ld 7+: fails)", int(bs.total) == 6 and not bool(bs.passed), str(bs))
	_check("the 10e automatic test is gone (ShootingPhase has no _check_sanctified_flames)", not load("res://phases/ShootingPhase.gd").new().has_method("_check_sanctified_flames"))


# ---------------------------------------------------------------------------
# 29. Deft Parry / Reap a Terrible Tally
# ---------------------------------------------------------------------------
func _section_deft_parry_reap() -> void:
	print("\n-- 29. Deft Parry / Reap a Terrible Tally --")
	_fresh(P_FIGHT, 2)
	_place("U_VIGILATORS_A", 20, 40)
	_place("U_BOYZ_B", 20, 38.2)
	var m := _mods("U_BOYZ_B", "U_VIGILATORS_A", true)
	_check("Deft Parry: melee attacks that target the Vigilators -1 to hit", bool(m.hit_minus) and "Deft Parry" in _names(m))
	_check("ranged attacks: none", not bool(_mods("U_BOYZ_B", "U_VIGILATORS_A", false).hit_minus))
	_check("other targets: none", not bool(_mods("U_BOYZ_B", "U_GUARD_A", true).hit_minus))
	_phase(P_FIGHT, 1)
	_place("U_AQUILON_T_A", 30, 40)
	_place("U_DEFF_DREAD_A", 30, 38)
	m = _mods("U_AQUILON_T_A", "U_BOYZ_B", true)
	_check("Reap a Terrible Tally: vs INFANTRY re-roll hit and wound 1s", str(m.hit_reroll) == "ones" and str(m.wound_reroll) == "ones")
	_check("Reap a Terrible Tally: ranged too", str(_mods("U_AQUILON_T_A", "U_BOYZ_B", false).hit_reroll) == "ones")
	_check("vs a VEHICLE: none", str(_mods("U_AQUILON_T_A", "U_DEFF_DREAD_A", true).hit_reroll) == "")


# ---------------------------------------------------------------------------
# 30. Strike from the Skies
# ---------------------------------------------------------------------------
func _section_strike_from_the_skies() -> void:
	print("\n-- 30. Strike from the Skies --")
	_fresh(P_SHOOT)
	_place("U_VENATARI_KD_A", 20, 40)
	_place("U_BOYZ_B", 20, 30)
	_check("no ingress this turn: none", str(_mods("U_VENATARI_KD_A", "U_BOYZ_B", false).hit_reroll) == "")
	_flags("U_VENATARI_KD_A")["arrived_from_reserves"] = true
	var m := _mods("U_VENATARI_KD_A", "U_BOYZ_B", false)
	_check("ingress move this turn: ranged attacks re-roll hit rolls", str(m.hit_reroll) == "failed" and "Strike from the Skies" in _names(m))
	_check("melee: none", str(_mods("U_VENATARI_KD_A", "U_BOYZ_B", true).hit_reroll) == "")
	_phase(P_SHOOT, 2)
	_check("not in the opponent's Shooting phase", str(_mods("U_VENATARI_KD_A", "U_BOYZ_B", false).hit_reroll) == "")


# ---------------------------------------------------------------------------
# 31. Advanced Firepower — not implemented (10e Lethal Hits rule removed)
# ---------------------------------------------------------------------------
func _section_advanced_firepower() -> void:
	print("\n-- 31. Advanced Firepower --")
	_fresh(P_SHOOT)
	_place("U_ANNIHILATOR_A", 20, 40)
	_place("U_DEFF_DREAD_A", 20, 30)
	var m := _mods("U_ANNIHILATOR_A", "U_DEFF_DREAD_A", false)
	_check("the 10e weapon/target [LETHAL HITS] rule is gone", not bool(m.lethal))
	_check("RulesEngine.check_advanced_firepower_lethal_hits removed", not RE.has_method("check_advanced_firepower_lethal_hits"))
	_check("the ABILITY_EFFECTS row is honest: not implemented (single-die re-rolls)", not UAM.is_ability_implemented("Advanced Firepower"))


# ---------------------------------------------------------------------------
# 32. The phase_start window (BasePhase) and its re-offer
# ---------------------------------------------------------------------------
func _section_phase_start_window() -> void:
	print("\n-- 32. phase_start window --")
	_fresh(P_CHG, 1)
	_place("U_TRAJANN_A", 20, 40)
	_place("U_VENATARI_KD_A", 30, 40)
	_place("U_BOYZ_B", 20, 38.2)
	_place("U_GRETCHIN_C", 30, 38.0)
	var entries: Array = CA.phase_start_entries(P_FIGHT)
	_check("entries only for players with an offer (P1)", entries.size() == 1 and int(entries[0].player) == 1, str(entries))
	PM.transition_to_phase(P_FIGHT)
	var fp = PM.current_phase_instance
	var sids := _pending_sids(fp)
	_check("entering the Fight phase opens phase_start for P1 first", str(_pending(fp).get("window_id", "")) == "phase_start" \
		and _sid("moment_shackle") in sids and _sid("neutronium_cascade_mine") in sids, "%s %s" % [str(_pending(fp).get("window_id", "")), str(sids)])
	var r: Dictionary = fp.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "phase_start",
		"stratagem_id": _sid("moment_shackle"), "target_unit_id": "U_TRAJANN_A", "context": {"variant_id": "invuln"}})
	_check("USE_WINDOW_STRATAGEM (Moment Shackle) succeeds", r.get("success", false), str(r.get("error", "")))
	sids = _pending_sids(fp)
	_check("the window is offered again with what is left (Neutronium Cascade Mine)", str(_pending(fp).get("window_id", "")) == "phase_start" and _sid("neutronium_cascade_mine") in sids and not _sid("moment_shackle") in sids, str(sids))
	r = fp.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 1, "window_id": "phase_start"})
	_check("decline closes it and the phase goes on", r.get("success", false) and str(_pending(fp).get("window_id", "")) != "phase_start", str(_pending(fp).get("window_id", "")))
	_fresh(P_SHOOT, 1)
	_place("U_TRAJANN_A", 20, 40)
	PM.transition_to_phase(P_SHOOT)
	_check("your own Shooting phase: no phase_start window (nothing to offer)", str(_pending(PM.current_phase_instance).get("window_id", "")) != "phase_start")


# ---------------------------------------------------------------------------
# 33. AI
# ---------------------------------------------------------------------------
func _section_ai() -> void:
	print("\n-- 33. AI decides synchronously --")
	_fresh(P_CHG, 1)
	_place("U_TRAJANN_A", 20, 40)
	_place("U_VENATARI_KD_A", 30, 40)
	_place("U_BOYZ_B", 20, 38.2)
	_place("U_GRETCHIN_C", 30, 38.0)
	var ADM = load("res://scripts/AIDecisionMaker.gd")
	var ctx := {"phase": "fight", "window_id": "phase_start"}
	_phase(P_FIGHT, 1)
	var offers: Array = SM.get_all_window_offers(1, "phase_start", ctx)
	_check("get_all_window_offers carries the ability cards", offers.size() == 2, str(offers.map(func(o): return o.name)))
	var dec: Dictionary = ADM.decide_window_stratagem(1, "phase_start", offers, ctx)
	_check("AI uses the mine first (score 3) on the closest enemy within 3\"", dec.get("use", false) and str(dec.get("stratagem_id", "")) == _sid("neutronium_cascade_mine") \
		and str(dec.get("context", {}).get("secondary_id", "")) in ["U_GRETCHIN_C", "U_BOYZ_B"], str(dec))
	_check("AI scores Moment Shackle in an engaged Fight phase (variant hint)", CA.ai_score(1, _sid("moment_shackle"), "U_TRAJANN_A", "phase_start", ctx) >= 1.0)
	_check("AI never uses the repositioning abilities", CA.ai_score(1, _sid("archeotech_teleport_shunter"), "x", "movement_phase_start", {}) == 0.0 \
		and CA.ai_score(1, _sid("take_wing"), "x", "fight_phase_end", {}) == 0.0 and CA.ai_score(1, _sid("mobile_hunter"), "x", "unit_has_shot", {}) == 0.0)
	# An AI decider never leaves the window pending.
	var ai = root.get_node("AIPlayer")
	ai.enabled = true
	ai.ai_players = {1: true, 2: false}
	PM.transition_to_phase(P_FIGHT)
	var fp = PM.current_phase_instance
	_check("AI P1: the phase_start window resolved synchronously (not pending)", str(_pending(fp).get("window_id", "")) != "phase_start")
	_check("AI used the mine (once per battle spent)", UAM.is_once_per_battle_used("U_VENATARI_KD_A", "Neutronium Cascade Mine"))
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}


# ---------------------------------------------------------------------------
# 34. 10e dispatch the codex dropped
# ---------------------------------------------------------------------------
func _section_dropped() -> void:
	print("\n-- 34. dropped 10e dispatch --")
	for n in ["Martial Inspiration", "Sentinel Storm", "Strategic Mastery", "Slayers of Tyrants", "Devoted to Destruction"]:
		_check("ABILITY_EFFECTS has no '%s' row" % n, not UAM.ABILITY_EFFECTS.has(n))
	for fn in ["has_shoot_again_ability", "has_sanctified_flames_ability", "has_dread_foe", "has_strategic_mastery"]:
		_check("UnitAbilityManager.%s removed" % fn, not UAM.has_method(fn))
	for fn in ["has_captain_general", "has_slayers_of_tyrants_vs_target", "has_purity_of_execution_vs_target", "resolve_dread_foe"]:
		_check("RulesEngine.%s removed" % fn, not RE.has_method(fn))
	var fpn = load("res://phases/FightPhase.gd").new()
	_check("FightPhase: no 10e Moment Shackle prompt", not "_moment_shackle_pending_units" in fpn and not fpn.has_method("_process_use_moment_shackle"))
	fpn.free()
	var mpn = load("res://phases/MovementPhase.gd").new()
	_check("MovementPhase: no 10e Quicksilver Execution fly-over", not mpn.has_method("_process_use_quicksilver_execution"))
	mpn.free()
	_check("dialogs removed", not ResourceLoader.exists("res://dialogs/MomentShackleDialog.gd") and not ResourceLoader.exists("res://dialogs/SentinelStormDialog.gd"))
	for n in ["Captain-General", "Moment Shackle", "Purity of Execution", "Quicksilver Execution", "Dread Foe", "Stand Vigil", "Swift Onslaught"]:
		var row: Dictionary = UAM.ABILITY_EFFECTS.get(n, {})
		_check("'%s' row is the inert codex description (cus11e)" % n, str(row.get("condition", "")) == "cus11e" and row.get("effects", [1]).is_empty())
