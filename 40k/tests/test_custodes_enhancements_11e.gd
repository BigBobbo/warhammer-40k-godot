extends SceneTree

# Codex: Adeptus Custodes (11e) ENHANCEMENTS — WP-C46
# (scripts/codex/custodes/CustodesEnhancements.gd, list-build half in
# ArmyListManager, army construction in scripts/codex/EnhancementRules11e.gd).
# Rules text: .llm/codex_11e_wahapedia/custodes/RULES.md; rulings: RULINGS.md
# § WP-C46. One group per enhancement (29) plus the army-construction checks,
# against the real fixture tests/saves/cus11e_c3_custodes_active.w40ksave
# (P1 Custodes, P2 Orks) and synthetic boards for A/B dice comparisons.
#
# Usage: godot --headless --path 40k --script tests/test_custodes_enhancements_11e.gd

const FIXTURE := "cus11e_c3_custodes_active"
const PHASE_COMMAND := 6
const PHASE_MOVEMENT := 7
const PHASE_SHOOTING := 8
const PHASE_CHARGE := 9
const PHASE_FIGHT := 10
const PX := 40.0

const CG := "U_CUSTODIAN_GUARD_B"
const SC := "U_SHIELD_CAPTAIN_A"
const BC := "U_BLADE_CHAMPION_A"
const CONT := "U_CONTEMPTOR-ACHILLUS_DREADNOUGHT_H"
const TELEMON := "U_TELEMON_HEAVY_DREADNOUGHT_I"
const WS_C := "U_WITCHSEEKERS_C"
const WS_D := "U_WITCHSEEKERS_D"
const CALADIUS := "U_CALADIUS_GRAV-TANK_E"
const JETBIKE := "U_SHIELD_CAPTAIN_JETBIKE_A"
const BOYZ := "U_BOYZ_B"
const DREAD := "U_DEFF_DREAD_A"
const MEGA := "U_MEGANOBZ_A"
const GRETS := "U_GRETCHIN_C"
const ALLARUS_SC := "U_SC_ALLARUS_T"

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var RE = null
var K = null
var D = null
var E = null
var R = null
var AIDM = null
var EP = null
var _base: Dictionary = {}
var _phase_done := false


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
# helpers (same shape as test_custodes_detachments_11e.gd)
# ---------------------------------------------------------------------------

func _stage_fixture() -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + FIXTURE + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + FIXTURE + ext))
	return slm.load_game(FIXTURE)


func _unit(uid: String) -> Dictionary:
	return GS.state.units.get(uid, {})


func _flags(uid: String) -> Dictionary:
	var u = _unit(uid)
	if not u.has("flags"):
		u["flags"] = {}
	return u.flags


## Units of `player` whose 11e snap-shooting targets (RulesEngine.
## snap_shooting_targets_11e — the FIRE OVERWATCH offer's target list) include
## `target_id`.
func _snap_shooters_at(player: int, target_id: String) -> Array:
	var re = root.get_node("RulesEngine")
	var board: Dictionary = GS.create_snapshot()
	var out: Array = []
	for uid in board.units:
		if int(board.units[uid].get("owner", 0)) != player:
			continue
		for t in re.snap_shooting_targets_11e(str(uid), board):
			if str(t.get("unit_id", "")) == target_id:
				out.append(str(uid))
	return out


func _remember() -> void:
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		var arr: Array = []
		for m in u.models:
			arr.append(m.get("position").duplicate() if m.get("position") is Dictionary else m.get("position"))
		_base[uid] = {"pos": arr, "meta": u.meta.duplicate(true)}


func _restore() -> void:
	GS.state.units.erase(ALLARUS_SC)
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		var b: Dictionary = _base.get(uid, {})
		var arr: Array = b.get("pos", [])
		if b.has("meta"):
			u["meta"] = b.meta.duplicate(true)
		for i in range(u.models.size()):
			if i < arr.size():
				u.models[i]["position"] = arr[i].duplicate() if arr[i] is Dictionary else arr[i]
			u.models[i]["alive"] = true
			u.models[i]["wounds"] = int(u.meta.get("stats", {}).get("wounds", u.models[i].get("wounds", 1)))
			u.models[i]["current_wounds"] = u.models[i]["wounds"]
		u["flags"] = {}
		u["status"] = GS.UnitStatus.DEPLOYED
		u["attached_to"] = null
		u["embarked_in"] = null
		u["attachment_data"] = {"attached_characters": []}
	GS.state.meta["active_player"] = 1
	GS.state.meta["battle_round"] = 2
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 6
	D.on_phase_end(-1)


func _set_det(name: String, player: int = 1) -> void:
	GS.state.factions[str(player)]["detachment"] = name


func _give(uid: String, enh_name: String) -> void:
	var u = _unit(uid)
	u.meta["enhancements"] = [enh_name]
	E.apply_list_build(uid, u)


func _attach(char_id: String, bodyguard_id: String) -> void:
	_unit(char_id)["attached_to"] = bodyguard_id
	var bg = _unit(bodyguard_id)
	if not bg.has("attachment_data"):
		bg["attachment_data"] = {"attached_characters": []}
	bg.attachment_data["attached_characters"] = [char_id]


func _no_phase_advance(phase) -> void:
	_phase_done = false
	if phase.phase_completed.is_connected(PM._on_phase_completed):
		phase.phase_completed.disconnect(PM._on_phase_completed)
	phase.phase_completed.connect(func(): _phase_done = true)


func _enter(phase_id: int):
	PM.transition_to_phase(phase_id)
	var phase = PM.get_current_phase_instance()
	_no_phase_advance(phase)
	for uid in GS.state.units:
		var f = GS.state.units[uid].get("flags", {})
		if f.has(K.FLAG_READIED):
			f[K.FLAG_READIED] = false
	return phase


func _offer(offers: Array, sid: String) -> Dictionary:
	for o in offers:
		if str(o.get("stratagem_id", "")) == sid:
			return o
	return {}


func _target_ids(offer: Dictionary) -> Array:
	return offer.get("targets", []).map(func(t): return str(t.get("unit_id", "")))


func _pos(m: Dictionary) -> Vector2:
	var p = m.get("position")
	if p is Dictionary:
		return Vector2(float(p.x), float(p.y))
	return p


func _touch(uid: String, target_uid: String) -> void:
	var meas = root.get_node("Measurement")
	var tm: Dictionary = _unit(target_uid).models[0]
	var mm: Dictionary = _unit(uid).models[0]
	var tp := _pos(tm)
	var gap: float = meas.base_extent_px(tm) + meas.base_extent_px(mm) + 2.0
	mm["position"] = {"x": tp.x, "y": tp.y + gap}
	for i in range(1, _unit(uid).models.size()):
		_unit(uid).models[i]["position"] = {"x": tp.x + 60.0 * i, "y": tp.y + gap + 10.0}


func _place(uid: String, at: Vector2) -> void:
	var models: Array = _unit(uid).models
	for i in range(models.size()):
		models[i]["position"] = {"x": at.x + i * 45.0, "y": at.y}


func _has_kind(contribs: Array, kind: String, source_part: String) -> bool:
	for c in contribs:
		if str(c.get("kind", "")) == kind and str(c.get("source", "")).find(source_part) >= 0:
			return true
	return false


func _block(res: Dictionary, ctx_name: String) -> Dictionary:
	for d in res.get("dice", []):
		if str(d.get("context", "")) == ctx_name:
			return d
	return {}


func _ledger_has(block: Dictionary, source: String) -> bool:
	for e in block.get("modifier_ledger", []):
		if str(e.get("source", "")).find(source) >= 0:
			return true
	return false


func _weapon_id(uid: String, name_part: String, melee: bool) -> String:
	var w = RE.get_unit_weapons(uid, GS.state) if not melee else {}
	if melee:
		for wd in _unit(uid).meta.get("weapons", []):
			if str(wd.get("type", "")).to_lower() == "melee" and str(wd.get("name", "")).find(name_part) >= 0:
				return str(wd.name)
		return ""
	for mid in w:
		for wid in w[mid]:
			var prof = RE.get_weapon_profile(str(wid), GS.state)
			if str(prof.get("name", "")).find(name_part) >= 0:
				return str(wid)
	return ""


func _first_ranged(uid: String) -> String:
	var w = RE.get_unit_weapons(uid, GS.state)
	for mid in w:
		for wid in w[mid]:
			var prof = RE.get_weapon_profile(str(wid), GS.state)
			if str(prof.get("type", "")).to_lower() != "melee" and str(prof.get("range", "melee")).to_lower() != "melee":
				return str(wid)
	return ""


func _shoot(uid: String, wid: String, tid: String, seed_val: int) -> Dictionary:
	var model_ids: Array = []
	var w = RE.get_unit_weapons(uid, GS.state)
	for mid in w:
		if wid in w[mid]:
			model_ids.append(str(mid))
	return RE.resolve_shoot({"type": "SHOOT", "actor_unit_id": uid, "payload": {"assignments": [{"weapon_id": wid, "target_unit_id": tid, "model_ids": model_ids}]}}, GS.state, RE.RNGService.new(seed_val))


func _melee_board(atk_enh: Array, atk_flags: Dictionary, tgt_kw: Array, tgt_enh: Array = [], atk_kw: Array = ["ADEPTUS CUSTODES", "INFANTRY", "CHARACTER"], n_att: int = 1, n_tgt: int = 5) -> Dictionary:
	var atk: Array = []
	for i in range(n_att):
		atk.append({"id": "ma%d" % i, "position": {"x": 10.0, "y": 10.0 + i * 30}, "base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 6, "current_wounds": 6})
	var tgt: Array = []
	for i in range(n_tgt):
		tgt.append({"id": "mt%d" % i, "position": {"x": 30.0, "y": 10.0 + i * 30}, "base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 30, "current_wounds": 30})
	var weapon := {"name": "Test Spear", "type": "Melee", "range": "Melee", "attacks": "6", "weapon_skill": "3",
		"strength": "6", "ap": "-1", "damage": "1", "special_rules": ""}
	return {"units": {
		"U_ATK": {"id": "U_ATK", "owner": 1,
			"meta": {"name": "Custodian", "keywords": atk_kw, "stats": {"toughness": 6, "save": 2, "wounds": 6},
				"abilities": [], "weapons": [weapon], "enhancements": atk_enh},
			"flags": atk_flags, "models": atk},
		"U_TGT": {"id": "U_TGT", "owner": 2,
			"meta": {"name": "Targets", "keywords": tgt_kw, "stats": {"toughness": 5, "save": 6, "wounds": 30}, "abilities": [],
				"enhancements": tgt_enh},
			"flags": {}, "models": tgt},
	}, "meta": {"phase": 10, "active_player": 1, "battle_round": 2}}


func _melee(board: Dictionary, seed_val: int) -> Dictionary:
	RE.set_test_seed(seed_val)
	return RE.resolve_melee_attacks({"type": "FIGHT", "actor_unit_id": "U_ATK",
		"payload": {"assignments": [{"attacker": "U_ATK", "target": "U_TGT", "weapon": "Test Spear"}]}}, board, RE.RNGService.new(seed_val))


# ---------------------------------------------------------------------------
func _run() -> void:
	SM = root.get_node("StratagemManager")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	K = load("res://scripts/codex/custodes/CustodesKatah.gd")
	D = load("res://scripts/codex/custodes/CustodesDetachments.gd")
	E = load("res://scripts/codex/custodes/CustodesEnhancements.gd")
	R = load("res://scripts/codex/EnhancementRules11e.gd")
	AIDM = load("res://scripts/AIDecisionMaker.gd")
	EP = load("res://autoloads/EffectPrimitives.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	GS.set_edition(11)

	print("\n=== test_custodes_enhancements_11e ===\n")
	_check("fixture %s loads" % FIXTURE, _stage_fixture())
	GS.set_edition(11)
	root.get_node("SettingsService").set("auto_allocate_wounds", true)
	_enter(PHASE_COMMAND)
	_remember()

	_section_registry()
	_section_bane()
	_section_emperors_light()
	_section_castellans_mark()
	_section_eagles_eye()
	_section_not_a_shell()
	_section_caducatrix()
	_section_flawless_hall_exemplar()
	_section_radiant_mantle()
	_section_edge_of_the_blade()
	_section_auriferous_orb()
	_section_unstoppable()
	_section_fnp_enhancements()
	_section_sally_forth()
	_section_auric_eagle()
	_section_arae_shrike()
	_section_celeritous_and_leonine()
	_section_shroud()
	_section_superior_creation()
	_section_inspirational()
	_section_lightning_descent()
	_section_memento()
	_section_anti_grav_and_combat_deployment()
	_section_oblivion_knight()
	_section_huntress()
	_section_army_construction()
	_section_cloud_load()
	_section_ai()


# ---------------------------------------------------------------------------
func _section_registry() -> void:
	print("\n-- 0. registry --")
	_check("29 codex enhancements registered", E.ENHANCEMENTS.size() == 29, str(E.ENHANCEMENTS.size()))
	var per_det := {}
	for k in E.ENHANCEMENTS:
		var d := str(E.ENHANCEMENTS[k].detachment)
		per_det[d] = int(per_det.get(d, 0)) + 1
	_check("every codex detachment has its enhancements (13 detachments)", per_det.size() == 13, str(per_det))
	_check("names normalise ('(one per army)' dropped)", E.enh_key("Memento Moritoi (one per army)") == E.MEMENTO)
	_check("curly apostrophes fold", E.enh_key("Castellan’s Mark") == E.CASTELLANS_MARK)
	# Every codex enhancement exists in the 40kdc dataset under its detachment.
	var missing: Array = []
	for k in E.ENHANCEMENTS:
		var rec: Dictionary = R.find_enhancement(str(E.ENHANCEMENTS[k].detachment), str(E.ENHANCEMENTS[k].name))
		if rec.is_empty() or str(rec.get("rules_text", "")) == "":
			missing.append(k)
	_check("all 29 found in data/40kdc/enhancements.json with rules text", missing.is_empty(), str(missing))


func _section_bane() -> void:
	print("\n-- 1. Bane of Abominations --")
	_restore()
	_give(SC, "Bane of Abominations")
	_check("+1 to wound vs a VEHICLE", _has_kind(E.wound_effects(_unit(SC), _unit(DREAD), true, 6, 10), "plus_one", "Bane"))
	_unit(MEGA).meta.keywords.append("CHARACTER")
	_check("+1 to wound vs a CHARACTER unit", _has_kind(E.wound_effects(_unit(SC), _unit(MEGA), true, 6, 5), "plus_one", "Bane"))
	_check("not vs plain infantry", not _has_kind(E.wound_effects(_unit(SC), _unit(BOYZ), true, 6, 5), "plus_one", "Bane"))
	_check("not for another unit", not _has_kind(E.wound_effects(_unit(CG), _unit(DREAD), true, 6, 10), "plus_one", "Bane"))
	_attach(SC, CG)
	_check("ranged batch of the bodyguard's models: no bearer-only bonus (ruling)",
		not _has_kind(E.wound_effects(_unit(CG), _unit(DREAD), false, 6, 10, {}, {"model_ids": ["0", "1"]}), "plus_one", "Bane"))
	_check("ranged batch of the bearer's own model: bonus",
		_has_kind(E.wound_effects(_unit(CG), _unit(DREAD), false, 6, 10, {}, {"model_ids": [SC + ":0"]}), "plus_one", "Bane"))


func _section_emperors_light() -> void:
	print("\n-- 2. Emperor's Light --")
	_restore()
	_give(SC, "Emperor's Light")
	var w: Dictionary = {}
	for wd in _unit(SC).meta.weapons:
		if str(wd.get("name", "")) == "Emperor's Light":
			w = wd
	_check("the bearer gains the Emperor's Light weapon", not w.is_empty())
	_check("profile A3 WS2+ S5 AP-2 D2 [EXTRA ATTACKS]", str(w.get("attacks", "")) == "3" and str(w.get("weapon_skill", "")) == "2"
		and str(w.get("strength", "")) == "5" and str(w.get("ap", "")) == "-2" and str(w.get("damage", "")) == "2"
		and str(w.get("special_rules", "")).find("extra attacks") >= 0, str(w))
	_check("flagged as enhancement-granted", str(w.get("granted_by", "")) == "Emperor's Light")
	E.apply_list_build(SC, _unit(SC))
	var n := 0
	for wd in _unit(SC).meta.weapons:
		if str(wd.get("name", "")) == "Emperor's Light":
			n += 1
	_check("list build is idempotent (one copy)", n == 1)
	# The model carries it even when its melee loadout was narrowed by the roster.
	var m: Dictionary = _unit(SC).models[0]
	m["melee_loadout"] = ["Pyrithite Spear"]
	var ids: Array = RE._get_model_weapon_ids(_unit(SC), m, "Melee")
	_check("granted weapon survives the MA-LOADOUT narrowing", ids.any(func(x): return str(x).to_lower().find("emperor") >= 0), str(ids))
	m.erase("melee_loadout")
	var mw: Dictionary = RE.get_unit_melee_weapons(SC, GS.state) if RE.has_method("get_unit_melee_weapons") else {}
	var listed := false
	for mid in mw:
		listed = listed or "Emperor's Light" in mw[mid]
	_check("the Fight phase lists it for the bearer", listed, str(mw))


func _section_castellans_mark() -> void:
	print("\n-- 3. Castellan's Mark --")
	_restore()
	var fam = root.get_node("FactionAbilityManager")
	_check("no bearer: no redeploy enhancement", fam.get_redeploy_enhancement_name(1) == "")
	_unit(SC).meta["enhancements"] = ["Castellan's Mark"]
	_check("bearer: Castellan's Mark is the player's redeploy enhancement", fam.get_redeploy_enhancement_name(1) == "Castellan's Mark")
	var ids: Array = fam.get_razgit_eligible_units(1).map(func(e): return str(e.unit_id))
	_check("friendly ADEPTUS CUSTODES units are eligible", CG in ids and CONT in ids)
	_check("the bearer's own unit is included (ruling: 'up to three friendly ADEPTUS CUSTODES units')", SC in ids)
	_check("no Ork unit", not BOYZ in ids)
	fam._razgit_redeploys_used = {"1": 0, "2": 0}
	_check("up to three units", fam.get_razgit_redeploys_remaining(1) == 3)
	_unit(SC).meta["enhancements"] = ["Castellan’s Mark"]
	_check("curly-apostrophe spelling (40kdc) also recognised", fam.get_redeploy_enhancement_name(1) == "Castellan's Mark",
		"curly name not normalised by FactionAbilityManager.has_enhancement")


func _section_eagles_eye() -> void:
	print("\n-- 4. Eagle's Eye --")
	_restore()
	var w0 := int(_unit(SC).meta.stats.wounds)
	_give(SC, "Eagle's Eye")
	_check("+1 W at list build (%d -> %d)" % [w0, int(_unit(SC).meta.stats.wounds)], int(_unit(SC).meta.stats.wounds) == w0 + 1)
	_check("model wounds raised too", int(_unit(SC).models[0].wounds) == w0 + 1 and int(_unit(SC).models[0].current_wounds) == w0 + 1)
	_enter(PHASE_SHOOTING)
	GS.state.meta["active_player"] = 2
	var offers: Array = SM.get_window_offers(1, "enemy_targets_unit_shooting", {"target_unit_ids": [SC]})
	_check("offered when attacks target the bearer", not _offer(offers, E.RULE_EAGLES_EYE).is_empty(), str(offers.map(func(o): return o.stratagem_id)))
	_check("not offered when another unit is targeted", _offer(SM.get_window_offers(1, "enemy_targets_unit_shooting", {"target_unit_ids": [CG]}), E.RULE_EAGLES_EYE).is_empty())
	var res: Dictionary = SM.use_stratagem(1, E.RULE_EAGLES_EYE, SC, {"window_id": "enemy_targets_unit_shooting"})
	_check("used", res.get("success", false), str(res))
	_check("3+ invulnerable save this phase", E.invuln_save(_unit(SC), false) == 3 and RE.cus11e_invuln(_unit(SC), false, 0) == 3)
	_check("once per battle: no second offer", _offer(SM.get_window_offers(1, "enemy_targets_unit_shooting", {"target_unit_ids": [SC]}), E.RULE_EAGLES_EYE).is_empty())
	D.on_phase_end(PHASE_SHOOTING)
	_check("the 3+ ends with the phase", E.invuln_save(_unit(SC), false) == 0)
	GS.state.meta["active_player"] = 1


func _section_not_a_shell() -> void:
	print("\n-- 5. Not a Shell Wasted --")
	_restore()
	_check("no enhancement: no bonus", RE.cus11e_ranged_attacks_per_model(_unit(CG), GS.state) == 0)
	_unit(CG).meta["enhancements"] = ["Not a Shell Wasted"]
	_check("the bearer's unit: +1 A on ranged attacks", RE.cus11e_ranged_attacks_per_model(_unit(CG), GS.state) == 1)
	var wid := _first_ranged(CG)
	if wid == "":
		_check("Custodian Guard has a ranged weapon", false)
		return
	_enter(PHASE_SHOOTING)
	_place(BOYZ, Vector2(300, 1050))
	_unit(CG).meta["enhancements"] = []
	var off = _shoot(CG, wid, BOYZ, 41)
	_unit(CG).meta["enhancements"] = ["Not a Shell Wasted"]
	var on = _shoot(CG, wid, BOYZ, 41)
	var n_off: int = _block(off, "to_hit").get("rolls_raw", []).size()
	var n_on: int = _block(on, "to_hit").get("rolls_raw", []).size()
	var models := 0
	for m in _unit(CG).models:
		if m.get("alive", true):
			models += 1
	_check("resolver: +1 attack per firing model (%d -> %d hit rolls)" % [n_off, n_on], n_off > 0 and n_on == n_off + models, str(on.get("log_text", "")))


func _section_caducatrix() -> void:
	print("\n-- 6. Pareldor's Caducatrix --")
	_restore()
	_give(SC, "Pareldor's Caducatrix")
	_enter(PHASE_MOVEMENT)
	_check("not offered while the bearer is unwounded", _offer(SM.get_window_offers(1, E.WINDOW_PHASE_START, {}), E.RULE_CADUCATRIX).is_empty())
	_unit(SC).models[0]["current_wounds"] = 2
	var phase = _enter(PHASE_SHOOTING)
	_check("start of the phase: the rule window opens for the wounded bearer", phase.has_pending_stratagem_window()
		and str(phase.get_pending_stratagem_window().get("window_id", "")) == E.WINDOW_PHASE_START,
		str(phase.get_pending_stratagem_window()) if phase.has_pending_stratagem_window() else "no window")
	var res: Dictionary = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": E.WINDOW_PHASE_START,
		"stratagem_id": E.RULE_CADUCATRIX, "target_unit_id": SC, "context": {}})
	var cw := int(_unit(SC).models[0].current_wounds)
	_check("heals D3+3 wounds (2 -> %d)" % cw, res.get("success", false) and cw >= 6 and cw <= 8, str(res))
	_check("once per battle", bool(_flags(SC).get(E.F_CADUCATRIX_USED, false)))
	_unit(SC).models[0]["current_wounds"] = 2
	_check("no second use", _offer(SM.get_window_offers(1, E.WINDOW_PHASE_START, {}), E.RULE_CADUCATRIX).is_empty())


func _section_flawless_hall_exemplar() -> void:
	print("\n-- 7-9. Flawless Bladework / From the Hall of Armouries / Auric Exemplar --")
	_restore()
	var plain = _melee(_melee_board([], {}, ["INFANTRY"]), 11)
	var fl = _melee(_melee_board(["Flawless Bladework"], {}, ["INFANTRY"]), 11)
	_check("Flawless Bladework: melee [SUSTAINED HITS 1]", bool(_block(fl, "hit_roll_melee").get("sustained_hits_weapon", false))
		and not bool(_block(plain, "hit_roll_melee").get("sustained_hits_weapon", false)))
	var ha = _melee(_melee_board(["From the Hall of Armouries"], {}, ["INFANTRY"]), 11)
	_check("From the Hall of Armouries: melee [DEVASTATING WOUNDS]", bool(_block(ha, "wound_roll_melee").get("devastating_wounds_weapon", false))
		and not bool(_block(plain, "wound_roll_melee").get("devastating_wounds_weapon", false)))
	var ex = _melee(_melee_board(["Auric Exemplar"], {}, ["INFANTRY"], [], ["ADEPTUS CUSTODES", "INFANTRY", "CHARACTER"], 1, 10), 11)
	var ex0 = _melee(_melee_board([], {}, ["INFANTRY"], [], ["ADEPTUS CUSTODES", "INFANTRY", "CHARACTER"], 1, 10), 11)
	var a0 := int(_block(ex0, "hit_roll_melee").get("total_attacks", 0))
	var a1 := int(_block(ex, "hit_roll_melee").get("total_attacks", 0))
	_check("Auric Exemplar: [CLEAVE 1] adds dice vs a 10-model target (%d -> %d)" % [a0, a1], a1 > a0)
	_check("10e Hall of Armouries +1 S/+1 D no longer applies",
		int(_block(ha, "wound_roll_melee").get("strength", 0)) == int(_block(plain, "wound_roll_melee").get("strength", -1)))


func _section_radiant_mantle() -> void:
	print("\n-- 10. Radiant Mantle --")
	_restore()
	var h_off := 0
	var h_on := 0
	var ledger := true
	for s in range(10):
		var off = _melee(_melee_board([], {}, ["INFANTRY"]), 20 + s)
		var on = _melee(_melee_board([], {}, ["INFANTRY", "ADEPTUS CUSTODES"], ["Radiant Mantle"]), 20 + s)
		h_off += int(_block(off, "hit_roll_melee").get("successes", 0))
		h_on += int(_block(on, "hit_roll_melee").get("successes", 0))
		ledger = ledger and _ledger_has(_block(on, "hit_roll_melee"), "Radiant Mantle")
	_check("attacks that target the bearer's unit: -1 to hit (%d -> %d, named every time)" % [h_off, h_on], h_on < h_off and ledger)
	_check("hit_effects agrees", _has_kind(E.hit_effects(_unit(BOYZ), {"id": "X", "owner": 1, "meta": {"enhancements": ["Radiant Mantle"]}}, true), "minus_one", "Radiant Mantle"))


func _section_edge_of_the_blade() -> void:
	print("\n-- 11. Edge of the Blade --")
	_restore()
	var nc = _melee(_melee_board(["Edge of the Blade"], {}, ["INFANTRY"]), 31)
	var ch = _melee(_melee_board(["Edge of the Blade"], {"charged_this_turn": true}, ["INFANTRY"]), 31)
	_check("charged this turn: re-roll hit rolls of 1", _ledger_has(_block(ch, "hit_roll_melee"), "Edge of the Blade"))
	_check("charged this turn: re-roll wound rolls of 1", _ledger_has(_block(ch, "wound_roll_melee"), "Edge of the Blade"))
	_check("no charge: no re-rolls", not _ledger_has(_block(nc, "hit_roll_melee"), "Edge of the Blade") and not _ledger_has(_block(nc, "wound_roll_melee"), "Edge of the Blade"))


func _section_auriferous_orb() -> void:
	print("\n-- 12. Auriferous Orb (BLINDING LIGHT) --")
	_restore()
	_give(SC, "Auriferous Orb")
	var w: Dictionary = {}
	for wd in _unit(SC).meta.weapons:
		if str(wd.get("name", "")) == "Auriferous Orb":
			w = wd
	_check("the bearer gains the Auriferous Orb (12\" A3 BS2+ S1 AP0 D1)", str(w.get("range", "")) == "12" and str(w.get("attacks", "")) == "3"
		and str(w.get("ballistic_skill", "")) == "2" and str(w.get("special_rules", "")).find("anti-non-monster/vehicle 2+") >= 0, str(w))
	_enter(PHASE_SHOOTING)
	_place(BOYZ, Vector2(512, 1100))
	var wid := _weapon_id(SC, "Auriferous Orb", false)
	_check("the Orb is a shooting option", wid != "", str(RE.get_unit_weapons(SC, GS.state)))
	var hits := 0
	for s in range(6):
		var res = _shoot(SC, wid, BOYZ, 60 + s)
		hits += int(_block(res, "to_hit").get("successes", 0))
		if hits > 0:
			break
	_check("the Orb hit the Boyz (resolver)", hits > 0)
	_check("the hit is recorded for BLINDING LIGHT", BOYZ in E.orb_hit_unit_ids(SC), str(E.orb_hit_unit_ids(SC)))
	var offers: Array = SM.get_window_offers(1, "unit_has_shot", {"unit_id": SC})
	var bl := _offer(offers, E.RULE_BLINDING_LIGHT)
	_check("BLINDING LIGHT offered when the unit has shot", not bl.is_empty(), str(offers.map(func(o): return o.stratagem_id)))
	var opts: Array = bl.get("targets", [{}])[0].get("secondary", {}).get("options", []) if not bl.is_empty() else []
	_check("only the units the Orb hit are selectable", opts.map(func(o): return str(o.id)) == [BOYZ], str(opts))
	var r: Dictionary = SM.use_stratagem(1, E.RULE_BLINDING_LIGHT, SC, {"secondary_id": BOYZ, "unit_id": SC})
	_check("selected", r.get("success", false), str(r))
	_check("the Boyz' attacks have -1 to hit", _has_kind(E.hit_effects(_unit(BOYZ), _unit(CG), true), "minus_one", "Blinding Light"))
	_check("once per phase for the bearer", _offer(SM.get_window_offers(1, "unit_has_shot", {"unit_id": SC}), E.RULE_BLINDING_LIGHT).is_empty())
	D.on_command_phase_start(2)
	_check("still blinded in the opponent's turn", _has_kind(E.hit_effects(_unit(BOYZ), _unit(CG), true), "minus_one", "Blinding Light"))
	D.on_command_phase_start(1)
	_check("ends at the start of the Orb player's next turn", not _has_kind(E.hit_effects(_unit(BOYZ), _unit(CG), true), "minus_one", "Blinding Light"))


func _section_unstoppable() -> void:
	print("\n-- 13. Unstoppable Destroyer --")
	_restore()
	_check("no enhancement: pile-in / consolidation 3\"", D.fight_move_cap(SC, 3.0) == 3.0)
	_unit(SC).meta["enhancements"] = ["Unstoppable Destroyer"]
	_check("the bearer's unit can move up to 4\"", D.fight_move_cap(SC, 3.0) == 4.0)
	var fight = _enter(PHASE_FIGHT)
	_check("FightPhase validator cap = 4\"", fight._fight_base_move_cap(SC) == 4.0)
	_check("any consolidation mode is selectable", D.any_consolidation_mode(SC))
	# Engaged AND within 3" of an objective: the mandatory order would force
	# Ongoing; Unstoppable lets the player pick Objective.
	_place(SC, Vector2(880, 1215))
	_place(BC, Vector2(700, 1500))
	_touch(BOYZ, SC)
	_flags(SC)["was_eligible_to_fight"] = true
	var tmpl = load("res://scripts/rules/movetypes/MoveTypes.gd").get_type("consolidation")
	var sel: Dictionary = tmpl.select_mode(SC, GS.state)
	_check("engaged near obj_center: Ongoing and Objective both available", "ongoing" in sel.get("available", []) and "objective" in sel.get("available", []), str(sel))
	_check("…default stays the mandatory Ongoing", str(sel.get("mode", "")) == "ongoing")
	var pick: Dictionary = tmpl.select_mode(SC, GS.state, {"chosen_mode": "objective"})
	_check("…and the Objective mode can be chosen", str(pick.get("mode", "")) == "objective")
	var ctx: Dictionary = fight.get_consolidation_context_11e(SC, "", "objective")
	_check("FightPhase context carries the choice for the dialog", str(ctx.get("mode", "")) == "objective" and ctx.get("available_modes", []).size() >= 2, str(ctx.get("available_modes", [])))
	_unit(SC).meta["enhancements"] = []
	var sel2: Dictionary = tmpl.select_mode(SC, GS.state, {"chosen_mode": "objective"})
	_check("without it the 12.08 order is mandatory (Ongoing)", str(sel2.get("mode", "")) == "ongoing" and bool(sel2.get("mandatory", false)))


func _section_fnp_enhancements() -> void:
	print("\n-- 14 / 25. Genalchemic Warding / Augury Uplink --")
	_restore()
	_check("no enhancement: no FNP", RE.get_unit_fnp(_unit(SC)) == 0)
	_unit(SC).meta["enhancements"] = ["Genalchemic Warding"]
	_check("Genalchemic Warding: Feel No Pain 5+", RE.get_unit_fnp(_unit(SC)) == 5)
	_unit(CONT).meta["enhancements"] = ["Augury Uplink (one per army)"]
	_check("Augury Uplink (Dreadnought upgrade): Feel No Pain 5+", RE.get_unit_fnp(_unit(CONT)) == 5)
	_check("the bearer only", RE.get_unit_fnp(_unit(CG)) == 0)


func _section_sally_forth() -> void:
	print("\n-- 15. Sally Forth --")
	_restore()
	_give(SC, "Sally Forth")
	_flags(CG)["advanced"] = true
	_enter(PHASE_MOVEMENT)
	_check("not offered outside the Charge phase", _offer(SM.get_window_offers(1, E.WINDOW_PHASE_START, {}), E.RULE_SALLY_FORTH).is_empty())
	var phase = _enter(PHASE_CHARGE)
	_flags(CG)["advanced"] = true
	var offers: Array = SM.get_window_offers(1, E.WINDOW_PHASE_START, {})
	var sf := _offer(offers, E.RULE_SALLY_FORTH)
	_check("start of the Charge phase: friendly INFANTRY within 6\" offered", CG in _target_ids(sf), str(_target_ids(sf)))
	_check("the advanced unit cannot charge yet", not EP.has_effect_advance_and_charge(_unit(CG)))
	var res: Dictionary = SM.use_stratagem(1, E.RULE_SALLY_FORTH, CG, {})
	_check("selected", res.get("success", false), str(res))
	_check("its advance move no longer prevents a charge", EP.has_effect_advance_and_charge(_unit(CG)))
	_check("other units unaffected", not EP.has_effect_advance_and_charge(_unit(WS_C)))
	_check("one unit per Charge phase", _offer(SM.get_window_offers(1, E.WINDOW_PHASE_START, {}), E.RULE_SALLY_FORTH).is_empty())
	var cm = load("res://scripts/rules/movetypes/ChargeMove11e.gd").new()
	var el: Dictionary = cm.eligible(CG, GS.state)
	_check("ChargeMove11e: advanced CG eligible to declare a charge", el.get("eligible", false) or not "advanced" in str(el.get("reasons", [])), str(el))


func _section_auric_eagle() -> void:
	print("\n-- 16. Auric Eagle --")
	_restore()
	_unit(CG).meta["enhancements"] = ["Auric Eagle"]
	_check("+1 to advance rolls", D.advance_roll_bonus(_unit(CG)) == 1)
	_check("+1 to charge rolls", D.charge_roll_bonus(_unit(CG)) == 1)
	_check("other units: none", D.advance_roll_bonus(_unit(WS_C)) == 0 and D.charge_roll_bonus(_unit(WS_C)) == 0)


func _section_arae_shrike() -> void:
	print("\n-- 17. Arae-Shrike --")
	_restore()
	_unit(CG).meta["enhancements"] = ["Arae-Shrike"]
	_unit(GRETS)["status"] = GS.UnitStatus.IN_RESERVES
	var ingress = load("res://scripts/rules/movetypes/MoveTypes.gd").get_type("ingress")
	var cg0 := _pos(_unit(CG).models[0])
	var ctx := {"battle_round": 3, "deep_strike": true, "board_size_inches": Vector2(44, 60), "models": [_unit(GRETS).models[0]]}
	var near: Dictionary = ingress.validate_setup(GRETS, GS.state, [cg0 + Vector2(0, 11.0 * PX)], ctx)
	_check("an enemy unit cannot be set up within 12\" of the bearer's unit", not near.valid and str(near.errors).find("Arae-Shrike") >= 0, str(near))
	var far: Dictionary = ingress.validate_setup(GRETS, GS.state, [cg0 + Vector2(0, 15.0 * PX)], ctx)
	_check("more than 12\" away: no Arae-Shrike error", str(far.get("errors", [])).find("Arae-Shrike") < 0, str(far))
	_unit(WS_C)["status"] = GS.UnitStatus.IN_RESERVES
	var own: Dictionary = ingress.validate_setup(WS_C, GS.state, [cg0 + Vector2(0, 11.0 * PX)], ctx)
	_check("friendly arrivals unaffected", str(own.get("errors", [])).find("Arae-Shrike") < 0, str(own))
	var deny: Array = AIDM._get_omni_scrambler_positions_from_snapshot(GS.state, 2)
	_check("the Ork AI treats the bearer as a 12\" no-arrival ring", deny.any(func(d): return str(d.get("unit_name", "")).find("Custodian") >= 0), str(deny.size()))


func _section_celeritous_and_leonine() -> void:
	print("\n-- 18 / 23. Celeritous Sentries / Leonine Ferocity --")
	_restore()
	_unit(CG).meta["enhancements"] = ["Celeritous Sentries"]
	var ov: Dictionary = E.stratagem_override(1, "heroic_intervention_11e", CG)
	_check("HEROIC INTERVENTION on the TRUSTED SENTINEL bearer unit: -1 CP, other uses allowed", bool(ov.get("applies", false)) and int(ov.get("cost_delta", 0)) == -1, str(ov))
	_check("StratagemManager sees it", bool(SM._cus11e_stratagem_override(1, "heroic_intervention", CG).get("applies", false)))
	E.record_stratagem_override(ov)
	_check("once per phase per unit", not bool(E.stratagem_override(1, "heroic_intervention", CG).get("applies", false)))
	_unit(WS_C).meta["enhancements"] = ["Celeritous Sentries"]
	_check("a unit without TRUSTED SENTINEL gets nothing", not bool(E.stratagem_override(1, "heroic_intervention", WS_C).get("applies", false)))
	# Leonine Ferocity on a Shield-Captain in Allarus Terminator Armour.
	var allarus: Dictionary = _unit(SC).duplicate(true)
	allarus["id"] = ALLARUS_SC
	allarus.meta["name"] = "Shield-Captain in Allarus Terminator Armour"
	allarus.meta["keywords"] = ["ADEPTUS CUSTODES", "CHARACTER", "IMPERIUM", "INFANTRY", "SHIELD-CAPTAIN", "TERMINATOR"]
	allarus.meta["enhancements"] = ["Leonine Ferocity"]
	allarus["status"] = GS.UnitStatus.IN_RESERVES
	GS.state.units[ALLARUS_SC] = allarus
	var lov: Dictionary = E.stratagem_override(1, "rapid_ingress_11e", ALLARUS_SC)
	_check("RAPID INGRESS on the bearer: -1 CP regardless of other uses", bool(lov.get("applies", false)) and int(lov.get("cost_delta", 0)) == -1, str(lov))
	E.record_stratagem_override(lov)
	_check("once per phase, per army", not bool(E.stratagem_override(1, "rapid_ingress", ALLARUS_SC).get("applies", false)))
	_check("not on another stratagem", not bool(E.stratagem_override(1, "fire_overwatch", ALLARUS_SC).get("applies", false)))
	GS.state.units.erase(ALLARUS_SC)


func _section_shroud() -> void:
	print("\n-- 19. Shroud of the Hidden Blade --")
	_restore()
	_check("before: no Lone Operative / Stealth", not RE.has_lone_operative(_unit(BC)) and not RE.has_stealth_ability(_unit(BC)))
	_give(BC, "Shroud of the Hidden Blade")
	_check("the bearer has Lone Operative", RE.has_lone_operative(_unit(BC)))
	_check("the bearer has Stealth", RE.has_stealth_ability(_unit(BC)))
	var n: int = _unit(BC).meta.abilities.size()
	E.apply_list_build(BC, _unit(BC))
	_check("idempotent", _unit(BC).meta.abilities.size() == n)


func _section_superior_creation() -> void:
	print("\n-- 20. Superior Creation --")
	_restore()
	_unit(BC).meta["enhancements"] = ["Superior Creation"]
	_check("alive bearer: nothing to roll", E.resolve_superior_creation(RE.RNGService.new(1)).diffs.is_empty())
	_touch(BOYZ, BC)
	var death := _pos(_unit(BC).models[0])
	_unit(BC).models[0]["alive"] = false
	_unit(BC).models[0]["current_wounds"] = 0
	var revived := false
	var tries := 0
	var out: Dictionary = {}
	for s in range(20):
		tries += 1
		_flags(BC).erase(E.F_SUPERIOR_CREATION_DONE)
		_unit(BC).models[0]["alive"] = false
		_unit(BC).models[0]["position"] = {"x": death.x, "y": death.y}
		out = E.resolve_superior_creation(RE.RNGService.new(100 + s))
		GS.apply_state_changes(out.diffs)
		if _unit(BC).models[0].get("alive", false):
			revived = true
			break
	_check("2+: set back up (after %d seed(s))" % tries, revived, str(out.get("log_lines", [])))
	_check("with 3 wounds remaining", int(_unit(BC).models[0].current_wounds) == 3)
	var meas = root.get_node("Measurement")
	var min_d := INF
	for m in _unit(BOYZ).models:
		min_d = minf(min_d, meas.model_to_model_distance_inches(_unit(BC).models[0], m))
	_check("not within Engagement Range of an enemy (%.2f\")" % min_d, min_d > GameConstants.engagement_range_inches())
	_check("as close as possible to where it died (%.1f\")" % (death.distance_to(_pos(_unit(BC).models[0])) / PX), death.distance_to(_pos(_unit(BC).models[0])) / PX < 4.0)
	_unit(BC).models[0]["alive"] = false
	_check("once per battle, per army", E.resolve_superior_creation(RE.RNGService.new(5)).diffs.is_empty())


func _section_inspirational() -> void:
	print("\n-- 21. Inspirational Exemplar --")
	_restore()
	_unit(SC).meta["enhancements"] = ["Inspirational Exemplar"]
	_enter(PHASE_MOVEMENT)
	_check("nobody battle-shocked: no offer", _offer(SM.get_window_offers(1, E.WINDOW_PHASE_START, {}), E.RULE_INSPIRATIONAL).is_empty())
	_flags(CG)["battle_shocked"] = true
	_flags(WS_D)["battle_shocked"] = true
	var io := _offer(SM.get_window_offers(1, E.WINDOW_PHASE_START, {}), E.RULE_INSPIRATIONAL)
	_check("battle-shocked unit within 9\" offered", CG in _target_ids(io), str(_target_ids(io)))
	_check("…one farther than 9\" is not", not WS_D in _target_ids(io))
	var res: Dictionary = SM.use_stratagem(1, E.RULE_INSPIRATIONAL, CG, {})
	_check("no longer battle-shocked", res.get("success", false) and not bool(_flags(CG).get("battle_shocked", true)), str(res))
	_flags(WS_C)["battle_shocked"] = true
	_check("once per battle round, per army", _offer(SM.get_window_offers(1, E.WINDOW_PHASE_START, {}), E.RULE_INSPIRATIONAL).is_empty())
	GS.state.meta["battle_round"] = 3
	_flags(CG)["battle_shocked"] = true
	_check("available again next battle round", not _offer(SM.get_window_offers(1, E.WINDOW_PHASE_START, {}), E.RULE_INSPIRATIONAL).is_empty())
	GS.state.meta["battle_round"] = 2


func _section_lightning_descent() -> void:
	print("\n-- 22. Lightning Descent --")
	_restore()
	var allarus: Dictionary = _unit(SC).duplicate(true)
	allarus["id"] = ALLARUS_SC
	allarus.meta["name"] = "Shield-Captain in Allarus Terminator Armour"
	allarus.meta["keywords"] = ["ADEPTUS CUSTODES", "CHARACTER", "IMPERIUM", "INFANTRY", "SHIELD-CAPTAIN", "TERMINATOR"]
	allarus.meta["enhancements"] = ["Lightning Descent"]
	allarus["status"] = GS.UnitStatus.IN_RESERVES
	allarus["reserve_type"] = "deep_strike"
	for m in allarus.models:
		m["position"] = null
	GS.state.units[ALLARUS_SC] = allarus
	var mv = _enter(PHASE_MOVEMENT)
	GS.state.meta["battle_round"] = 1
	_check("battle round 1, own Movement phase: can make an ingress move", D.can_ingress_first_round(_unit(ALLARUS_SC)))
	var acts: Array = mv.get_available_actions().filter(func(a): return str(a.get("type", "")) == "PLACE_REINFORCEMENT")
	_check("the Movement phase offers its arrival in round 1", acts.any(func(a): return str(a.get("unit_id", "")) == ALLARUS_SC), str(acts))
	_check("…and no other reserve unit", acts.size() == 1)
	var v: Dictionary = mv.validate_action({"type": "PLACE_REINFORCEMENT", "unit_id": ALLARUS_SC, "model_positions": [{"x": 880.0, "y": 1700.0}], "placement_type": "deep_strike"})
	_check("validation does not refuse it for the battle round", str(v.get("errors", [])).find("Battle Round 2") < 0, str(v))
	GS.state.meta["active_player"] = 2
	_check("not in the opponent's Movement phase", not D.can_ingress_first_round(_unit(ALLARUS_SC)))
	GS.state.meta["active_player"] = 1
	allarus.meta["enhancements"] = []
	_check("without the enhancement: round 1 arrival refused", not D.can_ingress_first_round(_unit(ALLARUS_SC)))
	GS.state.meta["battle_round"] = 2
	GS.state.units.erase(ALLARUS_SC)


func _section_memento() -> void:
	print("\n-- 24. Memento Moritoi --")
	_restore()
	var kw := ["ADEPTUS CUSTODES", "VEHICLE", "WALKER", "DREADNOUGHT"]
	var p = _melee(_melee_board([], {}, ["INFANTRY"], [], kw), 51)
	var m = _melee(_melee_board(["Memento Moritoi (one per army)"], {}, ["INFANTRY"], [], kw), 51)
	_check("+1 A (6 -> 7 attacks)", int(_block(p, "hit_roll_melee").get("total_attacks", 0)) == 6 and int(_block(m, "hit_roll_melee").get("total_attacks", 0)) == 7,
		"%s / %s" % [_block(p, "hit_roll_melee").get("total_attacks", 0), _block(m, "hit_roll_melee").get("total_attacks", 0)])
	_check("+1 S (6 -> 7)", int(_block(m, "wound_roll_melee").get("strength", 0)) == int(_block(p, "wound_roll_melee").get("strength", 0)) + 1)
	var pb: Dictionary = RE.cus11e_melee_profile_bonus({"meta": {"enhancements": ["Memento Moritoi"]}})
	_check("+1 D", int(pb.get("d", 0)) == 1)
	_check("damage string helper adds it", RE.cus11e_damage_raw_plus("D3", 1) == "D3+1" and RE.cus11e_damage_raw_plus("2", 1) == "3")


func _section_anti_grav_and_combat_deployment() -> void:
	print("\n-- 26 / 27. Anti-gravitic Mobility / Combat Deployment --")
	_restore()
	_check("before: fall back blocks shooting", not EP.has_effect_fall_back_and_shoot(_unit(CALADIUS)))
	_unit(CALADIUS).meta["enhancements"] = ["Anti-gravitic Mobility"]
	_check("GRAV-ASSAULT bearer: fall back does not prevent shooting", EP.has_effect_fall_back_and_shoot(_unit(CALADIUS)))
	_unit(CG).meta["enhancements"] = ["Anti-gravitic Mobility"]
	_check("a non-GRAV-ASSAULT bearer gets nothing", not EP.has_effect_fall_back_and_shoot(_unit(CG)))
	_restore()
	_unit(CALADIUS).meta["enhancements"] = ["Combat Deployment"]
	# Embark the Custodian Guard, then disembark through TransportManager.
	var cal := _unit(CALADIUS)
	if not cal.has("transport_data"):
		cal["transport_data"] = {"capacity": 6, "embarked_units": []}
	cal.transport_data["embarked_units"] = [CG]
	_unit(CG)["embarked_in"] = CALADIUS
	var tm = root.get_node("TransportManager")
	var cp := _pos(cal.models[0])
	var positions: Array = []
	for i in range(_unit(CG).models.size()):
		positions.append(cp + Vector2(-120 + i * 60, -150))
	tm.disembark_unit(CG, positions)
	_check("the disembarked unit is marked for this turn", str(_flags(CG).get(E.F_COMBAT_DEPLOYMENT, "")) == E.turn_stamp())
	_check("…it can re-roll charge rolls", D.charge_reroll_source(_unit(CG)) == "Combat Deployment")
	_check("…the charge phase sees the re-roll", root.get_node("FactionAbilityManager").unit_has_detachment_charge_reroll(_unit(CG)))
	_check("…and cannot be targeted by snap shooting", D.blocks_snap_shooting(_unit(CG)))
	_check("Fire Overwatch offers the Orks nothing against it", SM.get_fire_overwatch_eligible_units(2, CG, GS.state).is_empty())
	# 11e FIRE OVERWATCH (15.08, end of the opponent's Movement phase): its
	# rows' snap targets (RulesEngine.snap_shooting_targets_11e) leave it out.
	var cd_shooters := _snap_shooters_at(2, CG)
	_check("11e FIRE OVERWATCH: no Ork unit may snap-shoot it", cd_shooters.is_empty(), str(cd_shooters))
	var cd_stamp = _flags(CG).get(E.F_COMBAT_DEPLOYMENT, "")
	_flags(CG).erase(E.F_COMBAT_DEPLOYMENT)
	var cd_control := _snap_shooters_at(2, CG)
	_flags(CG)[E.F_COMBAT_DEPLOYMENT] = cd_stamp
	_check("(control) without the Combat Deployment mark an Ork unit could snap-shoot it", not cd_control.is_empty(), str(cd_control))
	GS.state.meta["active_player"] = 2
	_check("the mark is for this turn only", not D.blocks_snap_shooting(_unit(CG)))
	GS.state.meta["active_player"] = 1


func _section_oblivion_knight() -> void:
	print("\n-- 28. Oblivion Knight --")
	_restore()
	var ws := _unit(WS_C)
	ws.meta["enhancements"] = ["Oblivion Knight"]
	_check("+1 to hit always", _has_kind(E.hit_effects(ws, _unit(BOYZ), true), "plus_one", "Oblivion Knight"))
	_check("no +1 to wound vs a plain target", not _has_kind(E.wound_effects(ws, _unit(BOYZ), true, 3, 5), "plus_one", "Oblivion Knight"))
	_flags(BOYZ)["battle_shocked"] = true
	_check("+1 to wound vs a battle-shocked target", _has_kind(E.wound_effects(ws, _unit(BOYZ), true, 3, 5), "plus_one", "Oblivion Knight"))
	_flags(BOYZ).erase("battle_shocked")
	_unit(BOYZ).meta.keywords.append("PSYKER")
	_check("+1 to wound vs a PSYKER target", _has_kind(E.wound_effects(ws, _unit(BOYZ), true, 3, 5), "plus_one", "Oblivion Knight"))


func _section_huntress() -> void:
	print("\n-- 29. Huntress' Eye --")
	_restore()
	_unit(WS_C).meta["enhancements"] = ["Huntress' Eye"]
	_place(GRETS, Vector2(240, 1600))
	var mv = _enter(PHASE_MOVEMENT)
	var offers: Array = SM.get_window_offers(1, "movement_phase_end", {})
	var he := _offer(offers, E.RULE_HUNTRESS)
	_check("offered in the bearer's Movement phase", not he.is_empty(), str(offers.map(func(o): return o.stratagem_id)))
	var opts: Array = he.get("targets", [{}])[0].get("secondary", {}).get("options", []) if not he.is_empty() else []
	_check("a visible enemy unit within 12\" is selectable", opts.any(func(o): return str(o.id) == GRETS), str(opts))
	_check("an enemy farther than 12\" is not", not opts.any(func(o): return str(o.id) == MEGA))
	var res: Dictionary = SM.use_stratagem(1, E.RULE_HUNTRESS, WS_C, {"secondary_id": GRETS})
	_check("used: the Gretchin make a battle-shock roll at -1", res.get("success", false) and str(res.get("message", "")).find("-1") >= 0, str(res))
	_check("once per Movement phase", _offer(SM.get_window_offers(1, "movement_phase_end", {}), E.RULE_HUNTRESS).is_empty())
	GS.state.meta["active_player"] = 2
	_check("not in the opponent's Movement phase", _offer(SM.get_window_offers(1, "movement_phase_end", {}), E.RULE_HUNTRESS).is_empty())
	GS.state.meta["active_player"] = 1


# ---------------------------------------------------------------------------
func _army(det: String, units: Dictionary, points: int = 2000) -> Dictionary:
	return {"faction": {"name": "Adeptus Custodes", "detachment": det, "points": points}, "units": units}


func _u(name: String, kws: Array, enh: Array) -> Dictionary:
	return {"meta": {"name": name, "keywords": kws, "enhancements": enh}}


func _warned(v: Dictionary, part: String) -> bool:
	for w in v.get("warnings", []):
		if str(w).find(part) >= 0:
			return true
	return false


func _section_army_construction() -> void:
	print("\n-- A. army construction (data-driven, 40kdc enhancements.json) --")
	var sc_kw := ["ADEPTUS CUSTODES", "CHARACTER", "IMPERIUM", "INFANTRY", "SHIELD-CAPTAIN"]
	var allarus_kw := ["ADEPTUS CUSTODES", "CHARACTER", "IMPERIUM", "INFANTRY", "SHIELD-CAPTAIN", "TERMINATOR"]
	var cg_kw := ["ADEPTUS CUSTODES", "BATTLELINE", "IMPERIUM", "INFANTRY", "TRUSTED SENTINEL"]
	var ws_kw := ["ADEPTUS CUSTODES", "ANATHEMA PSYKANA", "CHARACTER", "IMPERIUM", "INFANTRY"]
	var dread_kw := ["ADEPTUS CUSTODES", "DREADNOUGHT", "IMPERIUM", "VEHICLE", "WALKER"]
	var r: Dictionary = R.parse_restriction(R.find_enhancement("Lions of the Emperor", "Lightning Descent"))
	_check("restriction parsed: 'Shield-Captain in Allarus Terminator Armour model only'", str(r.get("phrase", "")) == "Shield-Captain in Allarus Terminator Armour" and str(r.scope) == "model", str(r))
	var ae: Dictionary = R.parse_restriction(R.find_enhancement("Solar Watch", "Auric Eagle"))
	_check("restriction parsed with exclusion: Infantry/Mounted unit only (excluding Terminator units)", str(ae.get("excluding", "")) == "Terminator" and str(ae.scope) == "unit", str(ae))
	var ok: Dictionary = R.validate_army(_army("Guardians of the Throne", {"A": _u("Shield-Captain", sc_kw, ["Eagle's Eye"]), "B": _u("Blade Champion", ["ADEPTUS CUSTODES", "CHARACTER", "INFANTRY"], ["Bane of Abominations"])}))
	_check("a legal list: no warnings", ok.warnings.is_empty(), str(ok.warnings))
	var wrong_det: Dictionary = R.validate_army(_army("Guardians of the Throne", {"A": _u("Shield-Captain", sc_kw, ["Radiant Mantle"])}))
	_check("an enhancement of another detachment is flagged", _warned(wrong_det, "not a Guardians of the Throne enhancement"), str(wrong_det.warnings))
	var ld_foot: Dictionary = R.validate_army(_army("Lions of the Emperor", {"A": _u("Shield-Captain", sc_kw, ["Lightning Descent"])}))
	_check("bearer restriction: Lightning Descent on a foot Shield-Captain is flagged", _warned(ld_foot, "bearer restriction"), str(ld_foot.warnings))
	var ld_allarus: Dictionary = R.validate_army(_army("Lions of the Emperor", {"A": _u("Shield-Captain in Allarus Terminator Armour", allarus_kw, ["Lightning Descent"])}))
	_check("…on a Shield-Captain in Allarus Terminator Armour it is legal", ld_allarus.warnings.is_empty(), str(ld_allarus.warnings))
	var hunt_ok: Dictionary = R.validate_army(_army("Null Maiden Vigil", {"A": _u("Knight-Centura", ws_kw, ["Huntress' Eye"])}))
	_check("Anathema Psykana model only: a Knight-Centura is legal", hunt_ok.warnings.is_empty(), str(hunt_ok.warnings))
	var hunt_bad: Dictionary = R.validate_army(_army("Null Maiden Vigil", {"A": _u("Shield-Captain", sc_kw, ["Huntress' Eye"])}))
	_check("…a Shield-Captain is not", _warned(hunt_bad, "bearer restriction"), str(hunt_bad.warnings))
	var twice: Dictionary = R.validate_army(_army("Guardians of the Throne", {"A": _u("Shield-Captain", sc_kw, ["Eagle's Eye"]), "B": _u("Shield-Captain", sc_kw, ["Eagle's Eye"])}))
	_check("one of each per army", _warned(twice, "once per army"), str(twice.warnings))
	var upg: Dictionary = R.validate_army(_army("Solar Watch", {"A": _u("Custodian Guard", cg_kw, ["Auric Eagle"])}))
	_check("an Upgrade on a non-CHARACTER unit is legal", upg.warnings.is_empty(), str(upg.warnings))
	# Core rules (Select Enhancements): Upgrades "can be given to non-CHARACTER
	# units" — they are not LIMITED to them; the printed restriction decides.
	var upg_char: Dictionary = R.validate_army(_army("Solar Watch", {"A": _u("Shield-Captain", sc_kw, ["Auric Eagle"])}))
	_check("an Upgrade on a CHARACTER that meets its restriction is legal (Auric Eagle on a foot Shield-Captain)", upg_char.warnings.is_empty(), str(upg_char.warnings))
	# A CHARACTER-restricted Upgrade (the Ork codex "Big Mek with Shokk Attack
	# Gun model only" Upgrades — Temperamental Shokka, Enhanced Runt-maw).
	var shokka := {"name": "Temperamental Shokka (Upgrade)", "upgrade_tag": true,
		"rules_text": "Big Mek with Shokk Attack Gun model only. This model's Shokk Attack Gun has +1 S."}
	var big_mek := _u("Big Mek with Shokk Attack Gun", ["CHARACTER", "INFANTRY", "ORKS", "BIG MEK WITH SHOKK ATTACK GUN"], [])
	var boyz := _u("Boyz", ["BATTLELINE", "BOYZ", "INFANTRY", "MOB", "ORKS"], [])
	_check("CHARACTER-restricted Upgrade: legal on its CHARACTER bearer", R.bearer_problem(shokka, big_mek, true) == "", R.bearer_problem(shokka, big_mek, true))
	_check("…refused on another unit by its printed restriction", R.bearer_problem(shokka, boyz, true).find("bearer restriction") >= 0, R.bearer_problem(shokka, boyz, true))
	_check("a normal enhancement still needs a CHARACTER", R.bearer_problem({}, boyz, false).find("CHARACTER") >= 0)
	_check("no Upgrade on an EPIC HERO either", R.bearer_problem({}, _u("Ghazghkull Thraka", ["CHARACTER", "EPIC HERO", "ORKS"], []), true).find("EPIC HERO") >= 0)
	var two_on_one: Dictionary = R.validate_army(_army("Solar Watch", {"A": _u("Shield-Captain", sc_kw, ["Auric Eagle", "Sally Forth"])}))
	_check("one enhancement per unit (an Upgrade and a normal one on the same unit are flagged)", _warned(two_on_one, "different unit"), str(two_on_one.warnings))
	var upg_term: Dictionary = R.validate_army(_army("Solar Watch", {"A": _u("Allarus Custodians", ["ADEPTUS CUSTODES", "INFANTRY", "TERMINATOR"], ["Auric Eagle"])}))
	_check("Auric Eagle 'excluding Terminator units' is enforced", _warned(upg_term, "excluding"), str(upg_term.warnings))
	var three: Dictionary = R.validate_army(_army("Solar Watch", {"A": _u("Custodian Guard", cg_kw, ["Auric Eagle"]), "B": _u("Custodian Guard", cg_kw, ["Auric Eagle"]), "C": _u("Custodian Guard", cg_kw, ["Auric Eagle"])}))
	_check("an Upgrade on up to three units counts as one choice", three.warnings.is_empty(), str(three.warnings))
	var four: Dictionary = R.validate_army(_army("Solar Watch", {"A": _u("Custodian Guard", cg_kw, ["Auric Eagle"]), "B": _u("Custodian Guard", cg_kw, ["Auric Eagle"]), "C": _u("Custodian Guard", cg_kw, ["Auric Eagle"]), "D": _u("Custodian Guard", cg_kw, ["Auric Eagle"])}))
	_check("…a fourth is flagged", _warned(four, "max 3"), str(four.warnings))
	var memento: Dictionary = R.validate_army(_army("Might of the Moritoi", {"A": _u("Contemptor-Achillus Dreadnought", dread_kw, ["Memento Moritoi (one per army)"]), "B": _u("Contemptor-Galatus Dreadnought", dread_kw, ["Memento Moritoi (one per army)"])}))
	_check("'(one per army)' Upgrade on two units is flagged", _warned(memento, "max 1"), str(memento.warnings))
	var cap: Dictionary = R.validate_army(_army("Guardians of the Throne", {"A": _u("Shield-Captain", sc_kw, ["Eagle's Eye"]), "B": _u("Shield-Captain", sc_kw, ["Bane of Abominations"]), "C": _u("Blade Champion", ["ADEPTUS CUSTODES", "CHARACTER", "INFANTRY"], ["Emperor's Light"])}, 1000))
	_check("2 per 1000 pts cap", _warned(cap, "exceed the cap of 2"), str(cap.warnings))
	var epic: Dictionary = R.validate_army(_army("Guardians of the Throne", {"A": _u("Trajann Valoris", ["ADEPTUS CUSTODES", "CHARACTER", "EPIC HERO", "INFANTRY"], ["Eagle's Eye"])}))
	_check("no enhancement on an EPIC HERO", _warned(epic, "EPIC HERO"), str(epic.warnings))
	var alm = root.get_node("ArmyListManager")
	var v11: Dictionary = alm.validate_army_construction_11e(_army("Guardians of the Throne", {"A": _u("Shield-Captain", sc_kw, ["Eagle's Eye"]), "B": _u("Shield-Captain", sc_kw, ["Eagle's Eye"])}))
	_check("ArmyListManager 11e validation runs the data-driven checks", _warned(v11, "once per army"), str(v11.warnings))
	var orks: Dictionary = alm.load_army_list("orks", 2)
	_check("the Orks base list still validates clean", alm.validate_army_construction_11e(orks).warnings.is_empty(), str(alm.validate_army_construction_11e(orks).warnings))


func _section_cloud_load() -> void:
	print("\n-- B. list build through the army loaders --")
	var alm = root.get_node("ArmyListManager")
	var army: Dictionary = alm.load_army_list("adeptus_custodes", 1)
	var sc_id := ""
	for uid in army.units:
		if str(army.units[uid].meta.get("name", "")) == "Shield-Captain":
			sc_id = uid
	_check("adeptus_custodes list has a Shield-Captain", sc_id != "")
	if sc_id == "":
		return
	var raw: Dictionary = army.duplicate(true)
	var w0 := int(raw.units[sc_id].meta.stats.wounds)
	raw.units[sc_id].meta["enhancements"] = ["Eagle's Eye"]
	for k in raw.units[sc_id].get("flags", {}).keys():
		if str(k).begins_with("cus11e_listbuild_"):
			raw.units[sc_id].flags.erase(k)
	var processed: Dictionary = alm._process_army_data(raw, 1)
	_check("cloud (browser builder) path applies Eagle's Eye +1 W (%d -> %d)" % [w0, int(processed.units[sc_id].meta.stats.wounds)],
		int(processed.units[sc_id].meta.stats.wounds) == w0 + 1)
	var again: Dictionary = alm._process_army_data(processed, 1)
	_check("…and only once", int(again.units[sc_id].meta.stats.wounds) == w0 + 1)


func _section_ai() -> void:
	print("\n-- C. AI answers the enhancement choices synchronously --")
	_restore()
	_unit(SC).meta["enhancements"] = ["Pareldor's Caducatrix"]
	_unit(SC).models[0]["current_wounds"] = 3
	_enter(PHASE_MOVEMENT)
	var offers: Array = SM.get_window_offers(1, E.WINDOW_PHASE_START, {})
	var pick: Dictionary = AIDM.decide_window_stratagem(1, E.WINDOW_PHASE_START, offers, {})
	_check("Caducatrix: the AI heals a badly wounded bearer", pick.get("use", false) and str(pick.get("stratagem_id", "")) == E.RULE_CADUCATRIX, str(pick))
	_restore()
	_unit(SC).meta["enhancements"] = ["Inspirational Exemplar"]
	_enter(PHASE_MOVEMENT)
	_flags(CG)["battle_shocked"] = true
	offers = SM.get_window_offers(1, E.WINDOW_PHASE_START, {})
	pick = AIDM.decide_window_stratagem(1, E.WINDOW_PHASE_START, offers, {})
	_check("Inspirational Exemplar: the AI rallies the battle-shocked unit", pick.get("use", false) and str(pick.get("target_unit_id", "")) == CG, str(pick))
	_restore()
	_unit(WS_C).meta["enhancements"] = ["Huntress' Eye"]
	_place(GRETS, Vector2(240, 1600))
	_enter(PHASE_MOVEMENT)
	offers = SM.get_window_offers(1, "movement_phase_end", {})
	pick = AIDM.decide_window_stratagem(1, "movement_phase_end", offers, {})
	_check("Huntress' Eye: the AI picks a target", pick.get("use", false) and str(pick.get("context", {}).get("secondary_id", "")) != "", str(pick))
	var res: Dictionary = SM.use_stratagem(1, str(pick.get("stratagem_id", "")), str(pick.get("target_unit_id", "")), pick.get("context", {}))
	_check("…which is legal", res.get("success", false), str(res))
	_restore()
	_give(SC, "Eagle's Eye")
	_enter(PHASE_SHOOTING)
	GS.state.meta["active_player"] = 2
	offers = SM.get_window_offers(1, "enemy_targets_unit_shooting", {"target_unit_ids": [SC]})
	pick = AIDM.decide_window_stratagem(1, "enemy_targets_unit_shooting", offers, {"target_unit_ids": [SC]})
	_check("Eagle's Eye: the AI answers at once (use or decline)", pick.has("use"), str(pick))
	GS.state.meta["active_player"] = 1
