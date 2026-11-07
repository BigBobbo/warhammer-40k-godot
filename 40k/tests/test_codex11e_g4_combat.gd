extends SceneTree

# WP-G4 — Codex: Adeptus Custodes (11e) ADVANCED FIREPOWER (Caladius Annihilator)
# and Codex: Orks (11e) BIG'ED BOSSBUNKA (Raucous Occupants, Fortification,
# Ramshackle Cover).
#
# Advanced Firepower lives in scripts/codex/custodes/CustodesAbilities.gd (it
# rides the PRIME TARGET single-re-roll grant); the Bossbunka rules in
# scripts/codex/orks/OrkFortification11e.gd.
#
# Boards:
#   A. tests/saves/cus11e_c5_active (P2 Orks kept) + P1 = the Custodes codex
#      roster tests/fixtures/cus11e_ab_roster.json (Caladius Annihilator).
#   B. tests/saves/ork11e_orks_active (P2 Custodian Guard A-C kept) + P1 = the
#      Ork codex roster tests/fixtures/ork11e_ab_roster_b.json (Big'ed Bossbunka).
#
# Usage: godot --headless --path 40k --script tests/test_codex11e_g4_combat.gd

const PX := 40.0
const P_CMD := 6
const P_MOV := 7
const P_SHOOT := 8
const P_CHG := 9
const P_FIGHT := 10

const FIX_C := "cus11e_c5_active"
const FIX_O := "ork11e_orks_active"
const KEEP_P2_O := ["U_CUSTODIAN_GUARD_A", "U_CUSTODIAN_GUARD_B", "U_CUSTODIAN_GUARD_C"]

var passed := 0
var failed := 0
var GS = null
var SM = null
var RE = null
var PM = null
var MM = null
var TM = null
var CA = null
var CX = null
var FT = null
var UAM = null
var _cus_roster: Dictionary = {}
var _ork_rosters: Array = []


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


func _stage(fixture: String) -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + fixture + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + fixture + ext))
	return slm.load_game(fixture)


func _add_roster(roster: Dictionary) -> void:
	for k in roster.get("units", {}):
		var u: Dictionary = roster.units[k].duplicate(true)
		u["id"] = k
		u["owner"] = 1
		u["status"] = 0
		u["flags"] = {}
		u.erase("attached_to")
		u.erase("embarked_in")
		u["attachment_data"] = {"attached_characters": []}
		for m in u.get("models", []):
			m["alive"] = true
			m["position"] = null
			m["current_wounds"] = int(m.get("wounds", 1))
		GS.state.units[k] = u
	GS.state.factions["1"] = roster.get("faction", {}).duplicate(true)


func _common_reset(phase: int, active: int) -> void:
	GS.state.meta["phase"] = phase
	GS.state.meta["active_player"] = active
	GS.state.meta["battle_round"] = 2
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 6
	SM.load_faction_stratagems_for_player(1)
	SM._usage_history = {"1": [], "2": []}


## Board A: Custodes (P1, roster off the table until placed) vs the fixture's Orks (P2, parked).
func _fresh_c(phase: int = P_SHOOT, active: int = 1) -> void:
	_stage(FIX_C)
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
	_add_roster(_cus_roster)
	_common_reset(phase, active)


## Board B: Orks (P1, roster b off the table until placed) vs Custodian Guard A-C (P2, parked).
func _fresh_o(phase: int = P_SHOOT, active: int = 1) -> void:
	_stage(FIX_O)
	GameConstants.edition = 11
	RE.set_test_seed(-1)
	for uid in GS.state.units.keys():
		var u: Dictionary = GS.state.units[uid]
		if int(u.get("owner", 0)) == 1 or not uid in KEEP_P2_O:
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
	for r in _ork_rosters:
		_add_roster(r)
	_common_reset(phase, active)


func _u(uid: String) -> Dictionary:
	return GS.state.units.get(uid, {})


func _flags(uid: String) -> Dictionary:
	var u := _u(uid)
	if not u.has("flags"):
		u["flags"] = {}
	return u.flags


## Every model of `uid` in a row starting at (x, y) inches.
func _place(uid: String, x: float, y: float) -> void:
	var u: Dictionary = GS.state.units[uid]
	u["status"] = 2
	u.erase("embarked_in")
	var cx := x
	for m in u.get("models", []):
		var r_in := float(m.get("base_mm", 32)) / 25.4
		m["position"] = {"x": (cx + r_in / 2.0) * PX, "y": y * PX}
		cx += r_in + 0.2


## Every model of `uid` in a column going DOWN (+y) from (x, y) inches.
func _place_col(uid: String, x: float, y: float) -> void:
	var u: Dictionary = GS.state.units[uid]
	u["status"] = 2
	u.erase("embarked_in")
	var cy := y
	for m in u.get("models", []):
		var r_in := float(m.get("base_mm", 32)) / 25.4
		m["position"] = {"x": x * PX, "y": (cy + r_in / 2.0) * PX}
		cy += r_in + 0.2


func _park(uid: String) -> void:
	var u: Dictionary = GS.state.units[uid]
	u["status"] = 7
	for m in u.get("models", []):
		m["position"] = null


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


func _weapon(uid: String, name_part: String) -> String:
	var ws: Dictionary = RE.get_unit_weapons(uid, GS.state)
	for mid in ws:
		for wid in ws[mid]:
			var prof: Dictionary = RE.get_weapon_profile(str(wid), GS.state)
			if str(prof.get("name", "")).to_lower().contains(name_part.to_lower()):
				return str(wid)
	return ""


func _mids(board: Dictionary, uid: String) -> Array:
	var out: Array = []
	var ms: Array = board.units[uid].models
	for i in range(ms.size()):
		if ms[i].get("alive", true):
			out.append(str(ms[i].get("id", "m%d" % (i + 1))))
	return out


## One auto-resolved ranged batch on `board` (RulesEngine.resolve_shoot — the
## auto / AI / Fire Overwatch resolver). Returns hits, wounds, the hit / wound
## re-roll counts of the dice blocks, and the raw result.
func _shoot(board: Dictionary, uid: String, wid: String, tid: String, seed: int, extra: Dictionary = {}) -> Dictionary:
	RE.set_test_seed(seed)
	var asg := {"weapon_id": wid, "target_unit_id": tid, "model_ids": _mids(board, uid)}
	for k in extra:
		asg[k] = extra[k]
	var res = RE.resolve_shoot({"type": "SHOOT", "actor_unit_id": uid, "payload": {"assignments": [asg]}}, board, RE.RNGService.new(seed))
	var out := {"hits": 0, "wounds": 0, "hit_rr": 0, "wound_rr": 0, "res": res}
	for d in res.get("dice", []):
		var c := str(d.get("context", ""))
		if c in ["to_hit", "hit_roll"]:
			out.hits += int(d.get("successes", 0))
			out.hit_rr += (d.get("rerolls", []) as Array).size()
		elif c == "to_wound":
			out.wounds += int(d.get("successes", 0))
			out.wound_rr += (d.get("rerolls", []) as Array).size()
	return out


func _strip_ability(board: Dictionary, uid: String, ability: String) -> void:
	var u: Dictionary = board.units[uid]
	u.meta.abilities = u.meta.abilities.filter(func(a): return str(a.get("name", "") if a is Dictionary else a) != ability)


func _game_log_count(needle: String) -> int:
	var gel = root.get_node("GameEventLog")
	var n := 0
	for e in gel.entries:
		if str(e.get("text", "")).find(needle) >= 0:
			n += 1
	return n


func _ab_mods(actor: String, target: String, prof: Dictionary, melee: bool = false) -> Dictionary:
	return RE.ork11e_ab_mods(_u(actor), _u(target), prof, melee, GS.state)


func _src_names(m: Dictionary) -> Array:
	return m.get("sources", []).map(func(x): return str(x.get("name", "")))


# ---------------------------------------------------------------------------
func _run() -> void:
	GS = root.get_node("GameState")
	SM = root.get_node("StratagemManager")
	RE = root.get_node("RulesEngine")
	PM = root.get_node("PhaseManager")
	MM = root.get_node("MissionManager")
	TM = root.get_node("TerrainManager")
	UAM = root.get_node("UnitAbilityManager")
	CA = load("res://scripts/codex/custodes/CustodesAbilities.gd")
	CX = load("res://scripts/codex/custodes/CustodesCodex11e.gd")
	FT = load("res://scripts/codex/orks/OrkFortification11e.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	root.get_node("SettingsService").set("auto_allocate_wounds", true)
	var alm = root.get_node("ArmyListManager")
	_cus_roster = alm._process_army_data(_json("cus11e_ab_roster"), 1)
	for r in ["ork11e_ab_roster_a", "ork11e_ab_roster_c", "ork11e_ab_roster_b"]:
		_ork_rosters.append(alm._process_army_data(_json(r), 1))
	print("\n=== test_codex11e_g4_combat (WP-G4) ===")
	_section_af_data()
	_section_af_projection()
	_section_af_once_per_phase()
	_section_af_snap_and_expiry()
	_section_af_ab()
	_section_af_damage()
	_section_af_beside_prime_target()
	_section_bunka_data()
	_section_fortification_targeting()
	_section_fortification_to_hit()
	_section_fortification_fall_back()
	_section_raucous_occupants()
	_section_ramshackle_cover()


# ---------------------------------------------------------------------------
# A1. data
# ---------------------------------------------------------------------------
func _section_af_data() -> void:
	print("\n-- A1. Advanced Firepower: data / ABILITY_EFFECTS row --")
	_fresh_c()
	_check("the Caladius Annihilator carries Advanced Firepower", CA.has(_u("U_ANNIHILATOR_A"), "advanced_firepower"))
	_check("the Caladius Grav-tank does not", not CA.has(_u("U_CALADIUS_A"), "advanced_firepower"))
	var row: Dictionary = UAM.ABILITY_EFFECTS.get("Advanced Firepower", {})
	_check("ABILITY_EFFECTS row is implemented", bool(row.get("implemented", false)), str(row))


# ---------------------------------------------------------------------------
# A2. projection vs MONSTER/VEHICLE only
# ---------------------------------------------------------------------------
func _section_af_projection() -> void:
	print("\n-- A2. Advanced Firepower: one hit / wound / damage re-roll vs MONSTER/VEHICLE --")
	_fresh_c()
	_place("U_ANNIHILATOR_A", 20, 40)
	_place("U_DEFF_DREAD_A", 20, 20)
	_place("U_BOYZ_B", 35, 20)
	var prof := {"name": "Arachnus blaze carronade", "type": "Ranged", "range": 48}
	_ab_mods("U_ANNIHILATOR_A", "U_DEFF_DREAD_A", prof)
	var pt = _flags("U_ANNIHILATOR_A").get(CA.PT_FLAG, null)
	_check("vs a VEHICLE: the grant is projected (hit, wound, damage)", typeof(pt) == TYPE_DICTIONARY and pt.hit and pt.wound and pt.damage and pt.get(CA.AF_MARK, false), str(pt))
	_check("the grant names its source", str(CX.single_reroll_source(_u("U_ANNIHILATOR_A"))) == "Advanced Firepower")
	_check("CustodesCodex11e.single_reroll_available sees it (hit / wound / damage)", CX.single_reroll_available(_u("U_ANNIHILATOR_A"), "hit") and CX.single_reroll_available(_u("U_ANNIHILATOR_A"), "wound") and CX.single_reroll_available(_u("U_ANNIHILATOR_A"), "damage"))
	_ab_mods("U_ANNIHILATOR_A", "U_BOYZ_B", prof)
	_check("vs INFANTRY (not MONSTER/VEHICLE): nothing", not _flags("U_ANNIHILATOR_A").has(CA.PT_FLAG), str(_flags("U_ANNIHILATOR_A")))
	_ab_mods("U_ANNIHILATOR_A", "U_DEFF_DREAD_A", {"name": "Armoured hull", "type": "Melee", "range": 0}, true)
	_check("melee attacks: no projection change (still the last ranged answer, never melee-usable)", not CX.single_reroll_available(_u("U_ANNIHILATOR_A"), "wound", true))
	_ab_mods("U_CALADIUS_A", "U_DEFF_DREAD_A", prof)
	_check("a unit without the ability gets nothing", not _flags("U_CALADIUS_A").has(CA.PT_FLAG))


# ---------------------------------------------------------------------------
# A3. one of each per phase; board-copy spends reach the live ledger
# ---------------------------------------------------------------------------
func _section_af_once_per_phase() -> void:
	print("\n-- A3. Advanced Firepower: one re-roll of each kind per phase --")
	_fresh_c()
	_place("U_ANNIHILATOR_A", 20, 40)
	_place("U_DEFF_DREAD_A", 20, 20)
	_place("U_BOYZ_B", 35, 20)
	var prof := {"name": "Arachnus blaze carronade", "type": "Ranged", "range": 48}
	_ab_mods("U_ANNIHILATOR_A", "U_DEFF_DREAD_A", prof)
	# Interactive spend (the staged dock's PRIME TARGET path).
	var diffs: Array = CX.single_reroll_spend_diffs("U_ANNIHILATOR_A", "hit")
	_check("the interactive spend also writes the per-phase ledger", diffs.any(func(d): return str(d.get("path", "")).ends_with(CA.F_AF)), str(diffs))
	PM.apply_state_changes(diffs)
	_ab_mods("U_ANNIHILATOR_A", "U_BOYZ_B", prof)
	_ab_mods("U_ANNIHILATOR_A", "U_DEFF_DREAD_A", prof)
	var pt: Dictionary = _flags("U_ANNIHILATOR_A").get(CA.PT_FLAG, {})
	_check("a spent hit re-roll stays spent across targets (hit gone, wound / damage left)", not bool(pt.get("hit", true)) and bool(pt.get("wound", false)) and bool(pt.get("damage", false)), str(pt))
	# Auto spend on a BOARD COPY (the phases resolve on game_state_snapshot).
	var b: Dictionary = GS.state.duplicate(true)
	RE.ork11e_ab_mods(b.units.U_ANNIHILATOR_A, b.units.U_DEFF_DREAD_A, prof, false, b)
	var took: bool = load("res://scripts/codex/custodes/CustodesCodexShooting.gd").take_single_reroll(b.units.U_ANNIHILATOR_A, "wound")
	_check("auto spend on a board copy succeeds", took)
	var led: Dictionary = CA.af_ledger("U_ANNIHILATOR_A")
	_check("... and reaches the LIVE ledger (wound spent)", not bool(led.wound) and not bool(led.hit) and bool(led.damage), str(led))
	_ab_mods("U_ANNIHILATOR_A", "U_DEFF_DREAD_A", prof)
	pt = _flags("U_ANNIHILATOR_A").get(CA.PT_FLAG, {})
	_check("the next weapon's projection only has the damage re-roll left", not bool(pt.get("hit", true)) and not bool(pt.get("wound", true)) and bool(pt.get("damage", false)), str(pt))
	# A Mathhammer trial board (no "meta") never spends the live ledger.
	var trial := {"units": {"U_ANNIHILATOR_A": _u("U_ANNIHILATOR_A").duplicate(true), "U_DEFF_DREAD_A": _u("U_DEFF_DREAD_A").duplicate(true)}}
	RE.ork11e_ab_mods(trial.units.U_ANNIHILATOR_A, trial.units.U_DEFF_DREAD_A, prof, false, trial)
	load("res://scripts/codex/custodes/CustodesCodexShooting.gd").take_single_reroll(trial.units.U_ANNIHILATOR_A, "damage")
	_check("a Mathhammer trial spend leaves the live damage re-roll", bool(CA.af_ledger("U_ANNIHILATOR_A").damage))


# ---------------------------------------------------------------------------
# A4. snap shooting (Fire Overwatch): no hit re-roll; expiry at phase end
# ---------------------------------------------------------------------------
func _section_af_snap_and_expiry() -> void:
	print("\n-- A4. Advanced Firepower: Fire Overwatch, expiry --")
	_fresh_c(P_MOV, 2)
	_place("U_ANNIHILATOR_A", 20, 40)
	_place("U_DEFF_DREAD_A", 20, 20)
	var prof := {"name": "Arachnus blaze carronade", "type": "Ranged", "range": 48}
	_ab_mods("U_ANNIHILATOR_A", "U_DEFF_DREAD_A", prof)
	var pt: Dictionary = _flags("U_ANNIHILATOR_A").get(CA.PT_FLAG, {})
	_check("snap shooting in the opponent's Movement phase: wound + damage, no hit re-roll (15.09)", not bool(pt.get("hit", true)) and bool(pt.get("wound", false)) and bool(pt.get("damage", false)), str(pt))
	_check("... and the ledger keeps its hit re-roll (nothing was spent)", bool(CA.af_ledger("U_ANNIHILATOR_A").hit))
	CA.on_phase_transition(P_MOV, P_SHOOT)
	_check("the projection and ledger expire at the end of the phase", not _flags("U_ANNIHILATOR_A").has(CA.PT_FLAG) and not _flags("U_ANNIHILATOR_A").has(CA.F_AF))
	# Spend in Shooting phase round 2, then a later phase gives fresh re-rolls.
	_fresh_c(P_SHOOT, 1)
	_place("U_ANNIHILATOR_A", 20, 40)
	_place("U_DEFF_DREAD_A", 20, 20)
	_ab_mods("U_ANNIHILATOR_A", "U_DEFF_DREAD_A", prof)
	PM.apply_state_changes(CX.single_reroll_spend_diffs("U_ANNIHILATOR_A", "hit"))
	GS.state.meta["battle_round"] = 3
	_ab_mods("U_ANNIHILATOR_A", "U_DEFF_DREAD_A", prof)
	_check("next Shooting phase: the hit re-roll is back", bool(_flags("U_ANNIHILATOR_A").get(CA.PT_FLAG, {}).get("hit", false)))


# ---------------------------------------------------------------------------
# A5. A/B resolution (auto resolver) with the same seeds
# ---------------------------------------------------------------------------
func _section_af_ab() -> void:
	print("\n-- A5. Advanced Firepower: A/B, same seeds --")
	_fresh_c()
	_place("U_ANNIHILATOR_A", 20, 40)
	_place("U_DEFF_DREAD_A", 20, 20)
	_place("U_BOYZ_B", 35, 20)
	var wid := _weapon("U_ANNIHILATOR_A", "carronade")
	_check("weapon found (Arachnus blaze carronade)", wid != "", wid)
	var helped := 0
	var max_hit_rr := 0
	var max_wound_rr := 0
	var rr_seen := 0
	var gel_before := _game_log_count("Advanced Firepower")
	var infantry_same := true
	var wound_spent_seeds := 0
	for sd in range(700, 740):
		var b_on: Dictionary = GS.state.duplicate(true)
		var b_off: Dictionary = GS.state.duplicate(true)
		_strip_ability(b_off, "U_ANNIHILATOR_A", "Advanced Firepower")
		_flags("U_ANNIHILATOR_A").erase(CA.F_AF)
		_flags("U_ANNIHILATOR_A").erase(CA.PT_FLAG)
		b_on.units.U_ANNIHILATOR_A.flags.erase(CA.F_AF)
		var on := _shoot(b_on, "U_ANNIHILATOR_A", wid, "U_DEFF_DREAD_A", sd)
		if not bool(CA.af_ledger("U_ANNIHILATOR_A").wound):
			wound_spent_seeds += 1
		var off := _shoot(b_off, "U_ANNIHILATOR_A", wid, "U_DEFF_DREAD_A", sd)
		if int(on.hits) > int(off.hits) or int(on.wounds) > int(off.wounds):
			helped += 1
		max_hit_rr = maxi(max_hit_rr, int(on.hit_rr))
		max_wound_rr = maxi(max_wound_rr, int(on.wound_rr))
		rr_seen += int(on.hit_rr) + int(on.wound_rr)
		# Not a MONSTER/VEHICLE: identical with and without the ability.
		_flags("U_ANNIHILATOR_A").erase(CA.F_AF)
		var b_on2: Dictionary = GS.state.duplicate(true)
		var b_off2: Dictionary = GS.state.duplicate(true)
		_strip_ability(b_off2, "U_ANNIHILATOR_A", "Advanced Firepower")
		var on2 := _shoot(b_on2, "U_ANNIHILATOR_A", wid, "U_BOYZ_B", sd)
		var off2 := _shoot(b_off2, "U_ANNIHILATOR_A", wid, "U_BOYZ_B", sd)
		if int(on2.hits) != int(off2.hits) or int(on2.wounds) != int(off2.wounds) or int(on2.hit_rr) != int(off2.hit_rr):
			infantry_same = false
	_flags("U_ANNIHILATOR_A").erase(CA.F_AF)
	_check("A/B (40 seeds) vs the Deff Dread: the re-rolls turn a miss / failed wound around on some seeds (%d)" % helped, helped > 0)
	_check("at most ONE hit die re-rolled per activation (max %d in the to_hit block)" % max_hit_rr, max_hit_rr <= 1)
	_check("the wound re-roll is used on some seeds (%d) — the grant holds one, spent once (to_wound blocks carry no re-roll list)" % wound_spent_seeds, wound_spent_seeds > 0)
	_check("re-rolls were actually made (%d)" % rr_seen, rr_seen > 0)
	_check("A/B vs Boyz (INFANTRY): identical results on every seed", infantry_same)
	_check("auto re-rolls on a live board write Game Log lines (%d new)" % (_game_log_count("Advanced Firepower") - gel_before), _game_log_count("Advanced Firepower") > gel_before)
	# Same-seed: one activation of two weapons shares the single re-roll.
	_flags("U_ANNIHILATOR_A").erase(CA.F_AF)
	var lastrum := _weapon("U_ANNIHILATOR_A", "lastrum")
	var b2: Dictionary = GS.state.duplicate(true)
	var first := _shoot(b2, "U_ANNIHILATOR_A", wid, "U_DEFF_DREAD_A", 911)
	var led: Dictionary = CA.af_ledger("U_ANNIHILATOR_A")
	var b3: Dictionary = GS.state.duplicate(true)
	var second := _shoot(b3, "U_ANNIHILATOR_A", lastrum, "U_DEFF_DREAD_A", 911)
	_check("a second weapon of the same activation gets no hit re-roll once it was spent (first %d, second %d, ledger %s)" % [int(first.hit_rr), int(second.hit_rr), str(led)], (bool(led.hit) or int(second.hit_rr) == 0))
	_flags("U_ANNIHILATOR_A").erase(CA.F_AF)


# ---------------------------------------------------------------------------
# A6. damage roll
# ---------------------------------------------------------------------------
func _section_af_damage() -> void:
	print("\n-- A6. Advanced Firepower: one damage roll --")
	_fresh_c()
	_place("U_ANNIHILATOR_A", 20, 40)
	_place("U_DEFF_DREAD_A", 20, 20)
	var prof := {"name": "Arachnus blaze carronade", "type": "Ranged", "range": 48}
	_ab_mods("U_ANNIHILATOR_A", "U_DEFF_DREAD_A", prof)
	var rng = RE.RNGService.new(5)
	var a: Dictionary = _u("U_ANNIHILATOR_A")
	var out: Dictionary = CX.auto_single_reroll_damage({"value": 3, "rolled": true}, "D6+2", a, rng)
	_check("a below-average damage roll (3 on D6+2) is re-rolled", out.has("prime_target_reroll_from"), str(out))
	var out2: Dictionary = CX.auto_single_reroll_damage({"value": 3, "rolled": true}, "D6+2", a, rng)
	_check("only one damage roll per phase", not out2.has("prime_target_reroll_from"), str(out2))
	_check("the spend reached the ledger", not bool(CA.af_ledger("U_ANNIHILATOR_A").damage))
	_check("Game Log names Advanced Firepower for the damage re-roll", _game_log_count("Advanced Firepower: Caladius Annihilator") > 0 or _game_log_count("re-rolls one damage roll") > 0)


# ---------------------------------------------------------------------------
# A7. a real PRIME TARGET on the unit: the two stack (fallback grant)
# ---------------------------------------------------------------------------
func _section_af_beside_prime_target() -> void:
	print("\n-- A7. Advanced Firepower beside a real PRIME TARGET --")
	_fresh_c()
	_place("U_ANNIHILATOR_A", 20, 40)
	_place("U_DEFF_DREAD_A", 20, 20)
	_flags("U_ANNIHILATOR_A")[CA.PT_FLAG] = {"hit": true, "wound": true, "damage": true}
	var prof := {"name": "Arachnus blaze carronade", "type": "Ranged", "range": 48}
	_ab_mods("U_ANNIHILATOR_A", "U_DEFF_DREAD_A", prof)
	var pt: Dictionary = _flags("U_ANNIHILATOR_A").get(CA.PT_FLAG, {})
	_check("the genuine PRIME TARGET grant is not overwritten", not pt.has(CA.AF_MARK) and bool(pt.get("hit", false)), str(pt))
	_check("the fallback grant is set", CA.af_fallback_available(_u("U_ANNIHILATOR_A"), "hit") and CA.af_fallback_available(_u("U_ANNIHILATOR_A"), "wound"))
	var evals := [{"raw": 1, "is_hit": false, "rerolled": false}, {"raw": 1, "is_hit": false, "rerolled": false}]
	var mr := [1, 1]
	var rrd: Array = []
	var ledger: Array = []
	RE.cus11e_magna_reroll_hit(_u("U_ANNIHILATOR_A"), evals, mr, rrd, [2, 2], 2, 0, 6, RE.RNGService.new(3), 1, ledger)
	_check("the resolver's single-die chain re-rolls one hit die for Advanced Firepower", rrd.size() == 1 and bool(evals[0].get("rerolled", false)) and not bool(evals[1].get("rerolled", false)), str(evals))
	_check("named in the modifier ledger", str(ledger).find("Advanced Firepower") >= 0, str(ledger))
	RE.cus11e_magna_reroll_hit(_u("U_ANNIHILATOR_A"), evals, mr, rrd, [2, 2], 2, 0, 6, RE.RNGService.new(4), 1, ledger)
	_check("... once (the second failed die is left)", rrd.size() == 1)
	var d1: Dictionary = CA.af_fallback_reroll_damage({"value": 3, "rolled": true}, "D6+2", _u("U_ANNIHILATOR_A"), RE.RNGService.new(9), false)
	_check("fallback damage re-roll", d1.has("cus11e_af_reroll_from"), str(d1))
	_check("... once", not CA.af_fallback_reroll_damage({"value": 3, "rolled": true}, "D6+2", _u("U_ANNIHILATOR_A"), RE.RNGService.new(9), false).has("cus11e_af_reroll_from"))
	_check("PRIME TARGET's own re-rolls are untouched", bool(_flags("U_ANNIHILATOR_A").get(CA.PT_FLAG, {}).get("hit", false)) and bool(_flags("U_ANNIHILATOR_A").get(CA.PT_FLAG, {}).get("damage", false)))


# ---------------------------------------------------------------------------
# B1. Bossbunka data
# ---------------------------------------------------------------------------
func _section_bunka_data() -> void:
	print("\n-- B1. Big'ed Bossbunka: data --")
	_fresh_o()
	var b: Dictionary = _u("U_BIGED_BOSSBUNKA_A")
	var kws: Array = b.get("meta", {}).get("keywords", [])
	_check("keywords include FORTIFICATION and TRANSPORT", "FORTIFICATION" in kws and "TRANSPORT" in kws, str(kws))
	_check("Raucous Occupants / Fortification / Ramshackle Cover resolve", FT.has(b, "raucous_occupants") and FT.has(b, "fortification") and FT.has(b, "ramshackle_cover"))
	_check("transport_data built (capacity 11)", int(b.get("transport_data", {}).get("capacity", 0)) == 11, str(b.get("transport_data", {})))
	_check("printed OC 0", int(b.meta.stats.objective_control) == 0)


## The Bossbunka at (20, 20) and Custodian Guard A engaged with it (P2).
func _engage_guard_with_bunka() -> void:
	_place("U_BIGED_BOSSBUNKA_A", 20, 20)
	# Guard models in a column right below the Bossbunka, base edge 0.5" away.
	var bunka_r := float(_u("U_BIGED_BOSSBUNKA_A").models[0].get("base_mm", 32)) / 25.4 / 2.0
	var bx := (20.0 + bunka_r)
	var gm: Array = _u("U_CUSTODIAN_GUARD_A").models
	var g_r := float(gm[0].get("base_mm", 40)) / 25.4 / 2.0
	_place_col("U_CUSTODIAN_GUARD_A", bx, 20.0 + bunka_r + 0.5)
	# keep only the first guard model within reach is fine: the unit is engaged.
	var _unused := g_r


# ---------------------------------------------------------------------------
# B2. Fortification: targeting
# ---------------------------------------------------------------------------
func _section_fortification_targeting() -> void:
	print("\n-- B2. Fortification: an enemy engaged with only FORTIFICATIONs can be targeted --")
	_fresh_o()
	_engage_guard_with_bunka()
	_place("U_BOYZ_D", 20, 34)
	_check("setup: Custodian Guard A is engaged", RE.is_unit_engaged("U_CUSTODIAN_GUARD_A", GS.state))
	_check("engaged with only FORTIFICATION units", FT.engaged_only_with_fortifications("U_CUSTODIAN_GUARD_A", GS.state))
	var et: Dictionary = RE.get_eligible_targets("U_BOYZ_D", GS.state)
	_check("the Boyz can select it as a target (get_eligible_targets)", et.has("U_CUSTODIAN_GUARD_A"), str(et.keys()))
	var st = ShootingTypes.get_type("normal")
	var wid := _weapon("U_BOYZ_D", "slugga")
	if wid == "":
		wid = _weapon("U_BOYZ_D", "shoota")
	var tok: Dictionary = st.target_allowed("U_BOYZ_D", "U_CUSTODIAN_GUARD_A", RE.get_weapon_profile(wid, GS.state), GS.state)
	_check("normal shooting's target_allowed lets it through", bool(tok.get("allowed", false)), str(tok))
	var v: Dictionary = RE.validate_shoot({"type": "SHOOT", "actor_unit_id": "U_BOYZ_D", "payload": {"assignments": [{"weapon_id": wid, "target_unit_id": "U_CUSTODIAN_GUARD_A", "model_ids": _mids(GS.state, "U_BOYZ_D")}]}}, GS.state)
	_check("validate_shoot accepts it", bool(v.get("valid", false)), str(v.get("errors", [])))
	_check("explain_target_ineligibility: no friendly_engagement refusal", str(RE.explain_target_ineligibility("U_BOYZ_D", "U_CUSTODIAN_GUARD_A", GS.state).get("code", "")) != "friendly_engagement")
	# Edge: also engaged with a non-FORTIFICATION unit -> normal 04.02 rule.
	_fresh_o()
	_engage_guard_with_bunka()
	var gm0 = _u("U_CUSTODIAN_GUARD_A").models[0].position
	_place("U_GRETCHIN_A", float(gm0.x) / PX + 1.2, float(gm0.y) / PX)
	_place("U_BOYZ_D", 20, 34)
	_check("engaged with the Bossbunka AND an Ork infantry unit: not only FORTIFICATIONs", not FT.engaged_only_with_fortifications("U_CUSTODIAN_GUARD_A", GS.state))
	_check("... so it cannot be targeted", not RE.get_eligible_targets("U_BOYZ_D", GS.state).has("U_CUSTODIAN_GUARD_A"))
	# Edge: not engaged at all -> the rule is not in play.
	_fresh_o()
	_place("U_BIGED_BOSSBUNKA_A", 20, 20)
	_place("U_CUSTODIAN_GUARD_A", 30, 26)
	_check("unengaged: the rule does not apply", not FT.engaged_only_with_fortifications("U_CUSTODIAN_GUARD_A", GS.state))
	# Edge: [BLAST] still cannot target it (17.03 / 24.05 engaged-target rule).
	_fresh_o()
	_engage_guard_with_bunka()
	_place("U_BOYZ_D", 20, 34)
	var blast_ok: Dictionary = st.target_allowed("U_BOYZ_D", "U_CUSTODIAN_GUARD_A", {"name": "test blast", "type": "Ranged", "range": 24, "special_rules": "blast", "abilities": [{"id": "blast"}]}, GS.state)
	_check("a [BLAST] weapon still cannot target it", not bool(blast_ok.get("allowed", true)), str(blast_ok))
	# Snap shooting list (Fire Overwatch) also lists it.
	var snap: Array = RE.snap_shooting_targets_11e("U_BOYZ_D", GS.state)
	_check("snap-shooting (Fire Overwatch) targets include it", snap.any(func(t): return str(t.unit_id) == "U_CUSTODIAN_GUARD_A"), str(snap))


# ---------------------------------------------------------------------------
# B3. Fortification: -1 to hit (excluding [CLOSE-QUARTERS])
# ---------------------------------------------------------------------------
func _section_fortification_to_hit() -> void:
	print("\n-- B3. Fortification: -1 to hit vs that unit --")
	_fresh_o()
	_engage_guard_with_bunka()
	_place("U_BOYZ_D", 20, 34)
	var shoota := {"name": "Shoota", "type": "Ranged", "range": 18}
	var m := _ab_mods("U_BOYZ_D", "U_CUSTODIAN_GUARD_A", shoota)
	_check("ranged: -1 to hit, named Fortification", bool(m.get("hit_minus", false)) and "Fortification" in _src_names(m), str(_src_names(m)))
	var cq := {"name": "Slugga", "type": "Ranged", "range": 12, "special_rules": "close quarters", "abilities": [{"id": "close_quarters"}]}
	_check("[CLOSE-QUARTERS] attacks: excluded", not ("Fortification" in _src_names(_ab_mods("U_BOYZ_D", "U_CUSTODIAN_GUARD_A", cq))))
	_check("melee: excluded", not ("Fortification" in _src_names(_ab_mods("U_BOYZ_D", "U_CUSTODIAN_GUARD_A", {"name": "Choppa", "type": "Melee"}, true))))
	_place("U_CUSTODIAN_GUARD_B", 40, 40)
	_check("a target that is not engaged: none", not ("Fortification" in _src_names(_ab_mods("U_BOYZ_D", "U_CUSTODIAN_GUARD_B", shoota))))
	# A/B: same seeds, Fortification on vs off (the Bossbunka without the rule).
	var wid := _weapon("U_BOYZ_D", "shoota")
	if wid == "":
		wid = _weapon("U_BOYZ_D", "slugga")
	var on_total := 0
	var off_total := 0
	var never_more := true
	for sd in range(40, 70):
		var b_on: Dictionary = GS.state.duplicate(true)
		var b_off: Dictionary = GS.state.duplicate(true)
		_strip_ability(b_off, "U_BIGED_BOSSBUNKA_A", "Fortification")
		var on := _shoot(b_on, "U_BOYZ_D", wid, "U_CUSTODIAN_GUARD_A", sd)
		var off := _shoot(b_off, "U_BOYZ_D", wid, "U_CUSTODIAN_GUARD_A", sd)
		on_total += int(on.hits)
		off_total += int(off.hits)
		if int(on.hits) > int(off.hits):
			never_more = false
	_check("A/B (30 seeds): fewer hits with the -1 (%d vs %d)" % [on_total, off_total], on_total < off_total)
	_check("A/B: never more hits on any seed", never_more)
	var res: Dictionary = _shoot(GS.state.duplicate(true), "U_BOYZ_D", wid, "U_CUSTODIAN_GUARD_A", 41).res
	var led_txt := ""
	for d in res.get("dice", []):
		if str(d.get("context", "")) == "to_hit":
			led_txt = str(d.get("modifier_ledger", []))
	_check("the hit roll's modifier ledger names Fortification", led_txt.find("Fortification") >= 0, led_txt)


# ---------------------------------------------------------------------------
# B4. Fortification: fall-back hazard rolls automatically passed
# ---------------------------------------------------------------------------
func _section_fortification_fall_back() -> void:
	print("\n-- B4. Fortification: fall-back hazard rolls --")
	var fb = MoveTypes.get_type("fall_back")
	_fresh_o(P_MOV, 2)
	_engage_guard_with_bunka()
	var hz_auto: Dictionary = {}
	var any_seed_would_fail := false
	for sd in range(1, 60):
		var ctx: Dictionary = fb.before_moving("U_CUSTODIAN_GUARD_A", GS.state, RE.RNGService.new(sd), {"mode": "desperate_escape"})
		var hz: Dictionary = ctx.get("hazard", {})
		if hz.has("auto_passed"):
			hz_auto = hz
		# the same seed with the rule switched off
		var b_off: Dictionary = GS.state.duplicate(true)
		_strip_ability(b_off, "U_BIGED_BOSSBUNKA_A", "Fortification")
		var ctx_off: Dictionary = fb.before_moving("U_CUSTODIAN_GUARD_A", b_off, RE.RNGService.new(sd), {"mode": "desperate_escape"})
		if int(ctx_off.get("hazard", {}).get("failures", 0)) > 0:
			any_seed_would_fail = true
			_check("seed %d: would fail without the rule, automatically passed with it (0 failures, 0 MW)" % sd, int(hz.get("failures", -1)) == 0 and int(ctx.get("mortal_wounds", -1)) == 0, str(hz))
			break
	_check("a failing seed was found for the A/B", any_seed_would_fail)
	_check("auto-passed rolls are reported (source Fortification)", str(hz_auto.get("auto_passed_source", "")) == "Fortification", str(hz_auto))
	# Battle-shocked: not auto-passed.
	_flags("U_CUSTODIAN_GUARD_A")["battle_shocked"] = true
	var fail_seen := false
	for sd in range(1, 60):
		var hz2: Dictionary = fb.before_moving("U_CUSTODIAN_GUARD_A", GS.state, RE.RNGService.new(sd), {"mode": "desperate_escape"}).get("hazard", {})
		if hz2.has("auto_passed"):
			fail_seen = false
			break
		if int(hz2.get("failures", 0)) > 0:
			fail_seen = true
			break
	_check("battle-shocked: hazard rolls are rolled normally (a failure occurs)", fail_seen)
	_flags("U_CUSTODIAN_GUARD_A").erase("battle_shocked")
	# Also engaged with a non-FORTIFICATION unit: not auto-passed.
	var gm0 = _u("U_CUSTODIAN_GUARD_A").models[0].position
	_place("U_BOYZ_C", float(gm0.x) / PX + 1.2, float(gm0.y) / PX)
	var auto_any := false
	for sd in range(1, 20):
		if fb.before_moving("U_CUSTODIAN_GUARD_A", GS.state, RE.RNGService.new(sd), {"mode": "desperate_escape"}).get("hazard", {}).has("auto_passed"):
			auto_any = true
	_check("also engaged with Ork infantry: never auto-passed", not auto_any)
	_check("ordered retreat still the default mode (not battle-shocked)", str(fb.select_mode("U_CUSTODIAN_GUARD_A", GS.state).mode) == "ordered_retreat")


# ---------------------------------------------------------------------------
# B5. Raucous Occupants
# ---------------------------------------------------------------------------
func _home_obj_pos(player: int) -> Vector2:
	var h: Dictionary = FT.home_objective(player)
	var p = h.get("position", null)
	if p == null:
		return Vector2.INF
	return Vector2(float(p.x if p is Vector2 else p.get("x", 0)) / PX, float(p.y if p is Vector2 else p.get("y", 0)) / PX)


func _section_raucous_occupants() -> void:
	print("\n-- B5. Raucous Occupants --")
	_fresh_o(P_CMD)
	var hp := _home_obj_pos(1)
	_check("the mission has a P1 home objective", hp != Vector2.INF, str(FT.home_objective(1)))
	if hp == Vector2.INF:
		return
	var bunka := "U_BIGED_BOSSBUNKA_A"
	var bm: Dictionary = _u(bunka).models[0]
	bm["position"] = {"x": hp.x * PX, "y": hp.y * PX}
	_u(bunka)["status"] = 2
	_embark("U_BOYZ_D", bunka)
	var boyz_oc := 0
	for m in _u("U_BOYZ_D").models:
		boyz_oc += int(MM.model_oc(_u("U_BOYZ_D"), m))
	_check("setup: the embarked Boyz have OC (%d)" % boyz_oc, boyz_oc > 0)
	var oc: int = MM.model_oc(_u(bunka), bm)
	_check("on the home objective: OC 0 + embarked models' OC = %d (got %d)" % [boyz_oc, oc], oc == boyz_oc)
	var home: Dictionary = FT.home_objective(1)
	var loc: Dictionary = MM.get_level_of_control(home)
	_check("level of control on the home objective counts it (%s)" % str(loc), int(loc.get(1, 0)) >= boyz_oc)
	_flags("U_BOYZ_D")["battle_shocked"] = true
	_check("battle-shocked occupants add nothing", int(MM.model_oc(_u(bunka), bm)) == 0)
	_flags("U_BOYZ_D").erase("battle_shocked")
	bm["position"] = {"x": (hp.x + 12.0) * PX, "y": hp.y * PX}
	_check("off the home objective: OC 0", int(MM.model_oc(_u(bunka), bm)) == 0)
	# The enemy's home objective is not "your home objective".
	var ep := _home_obj_pos(2)
	if ep != Vector2.INF:
		bm["position"] = {"x": ep.x * PX, "y": ep.y * PX}
		_check("on the ENEMY home objective: OC 0", int(MM.model_oc(_u(bunka), bm)) == 0)
	bm["position"] = {"x": hp.x * PX, "y": hp.y * PX}
	_u("U_BOYZ_D").erase("embarked_in")
	_check("nobody embarked: OC 0", int(MM.model_oc(_u(bunka), bm)) == 0)


# ---------------------------------------------------------------------------
# B6. Ramshackle Cover
# ---------------------------------------------------------------------------
func _section_ramshackle_cover() -> void:
	print("\n-- B6. Ramshackle Cover --")
	_fresh_o()
	# Attacker Custodian Guard B (P2) at y=10, target Boyz D (P1) at y=30, the Bossbunka between.
	_place("U_CUSTODIAN_GUARD_B", 20, 10)
	_place("U_BOYZ_D", 20, 30)
	var tgt := "U_BOYZ_D"
	var att: Dictionary = _u("U_CUSTODIAN_GUARD_B").models[0]
	var t0 = _u(tgt).models[0].position
	_u("U_BIGED_BOSSBUNKA_A")["status"] = 2
	_u("U_BIGED_BOSSBUNKA_A").models[0]["position"] = {"x": (float(att.position.x) + float(t0.x)) / 2.0, "y": (float(att.position.y) + float(t0.y)) / 2.0}
	_check("the Bossbunka hides part of the target: Ramshackle Cover", FT.ramshackle_cover(_u(tgt), att))
	_check("TerrainManager.unit_has_cover_11e (the 13.08 choke point) agrees", bool(TM.unit_has_cover_11e(_u(tgt), att)))
	_u("U_BIGED_BOSSBUNKA_A").models[0]["position"] = {"x": float(att.position.x) + 30.0 * PX, "y": float(att.position.y)}
	_check("moved out of the sight lines: no cover", not FT.ramshackle_cover(_u(tgt), att))
	_u("U_BIGED_BOSSBUNKA_A").models[0]["position"] = {"x": (float(att.position.x) + float(t0.x)) / 2.0, "y": (float(att.position.y) + float(t0.y)) / 2.0}
	_check("the Bossbunka as the target: no cover from itself", not FT.ramshackle_cover(_u("U_BIGED_BOSSBUNKA_A"), att))
	var bunka_m: Dictionary = _u("U_BIGED_BOSSBUNKA_A").models[0]
	_check("the Bossbunka's own attacks: no cover from itself", not FT.ramshackle_cover(_u(tgt), bunka_m))
	_park("U_BIGED_BOSSBUNKA_A")
	_check("Bossbunka not on the battlefield: no cover", not FT.ramshackle_cover(_u(tgt), att))
