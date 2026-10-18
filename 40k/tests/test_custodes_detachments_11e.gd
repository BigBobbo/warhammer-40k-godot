extends SceneTree

# Codex: Adeptus Custodes (11e) DETACHMENT RULES — WP-C46
# (scripts/codex/custodes/CustodesDetachments.gd). Rules text:
# .llm/codex_11e_wahapedia/custodes/RULES.md; rulings: RULINGS.md § WP-C46.
# Against the real fixture tests/saves/cus11e_c3_custodes_active.w40ksave
# (P1 Custodes, P2 Orks, P1's Command phase of battle round 2) plus synthetic
# melee boards for the A/B dice comparisons (same seeds, rule on / off):
#   A. Guardians of the Throne — Martial Mastery (free fight-selection choice)
#   B. Aquilan Shield — Gilded Guardians + Favoured SALVUS (+6" Range)
#   C. Dread Host — charge re-rolls + Favoured DACATARAI (-2" enemy pile-in)
#   D. Emperor's Chosen — Magna Imperator + Favoured RENDAX (mortal wounds)
#   E. Emissaries Imperatus — Heralds of the Throne (Fights First) +
#      Favoured CONSERVAI (advance / fall back keep action eligibility)
#   F. Shadowkeepers — Wardens of the Dark Cells + Favoured KAPTARIS
#   G. Solar Watch — Talon Sortie (fall back + charge) + Favoured CALISTUS
#   H. Honoured Companions — Companion's Watch
#   I. Auric Champions — Assemblage of Might (dreadful foe)
#   J. Lions of the Emperor — On Gilded Wings
#   K. Might of the Moritoi — Moritoi Ancients (OC, re-rolls)
#   L. Grav-Assault Force — Flare Shields
#   M. Null Maiden Vigil — Silent Sisterhood (warlord, BATTLELINE, Creeping Dread)
#   N. AI answers every rule choice synchronously (never stalls a window)
#   O. the 10e Custodes detachment code is gone
#
# Usage: godot --headless --path 40k --script tests/test_custodes_detachments_11e.gd

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
const WS_C := "U_WITCHSEEKERS_C"
const WS_D := "U_WITCHSEEKERS_D"
const CALADIUS := "U_CALADIUS_GRAV-TANK_E"
const BOYZ := "U_BOYZ_B"
const DREAD := "U_DEFF_DREAD_A"
const MEGA := "U_MEGANOBZ_A"
const GRETS := "U_GRETCHIN_C"

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var RE = null
var K = null
var D = null
# Loaded at run time (after the autoloads exist) so this script compiles
# cleanly in the pre-autoload pass of `godot -s`.
var AIDM = null
var EP = null
var AM = null
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


func _unit(uid: String) -> Dictionary:
	return GS.state.units.get(uid, {})


func _flags(uid: String) -> Dictionary:
	var u = _unit(uid)
	if not u.has("flags"):
		u["flags"] = {}
	return u.flags


func _remember() -> void:
	for uid in GS.state.units:
		var arr: Array = []
		for m in GS.state.units[uid].models:
			arr.append(m.get("position").duplicate() if m.get("position") is Dictionary else m.get("position"))
		_base[uid] = {"pos": arr, "kw": GS.state.units[uid].meta.get("keywords", []).duplicate()}


## Positions, wounds, keywords and flags back to the fixture (un-readied).
func _restore() -> void:
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		var b: Dictionary = _base.get(uid, {})
		var arr: Array = b.get("pos", [])
		for i in range(u.models.size()):
			if i < arr.size():
				u.models[i]["position"] = arr[i].duplicate() if arr[i] is Dictionary else arr[i]
			u.models[i]["alive"] = true
			u.models[i]["current_wounds"] = u.models[i].get("wounds", 1)
		if b.has("kw"):
			u.meta["keywords"] = b.kw.duplicate()
		u["flags"] = {}
		u["status"] = GS.UnitStatus.DEPLOYED
	GS.state.meta["active_player"] = 1
	GS.state.meta["battle_round"] = 2


func _set_det(name: String, player: int = 1) -> void:
	GS.state.factions[str(player)]["detachment"] = name


func _no_phase_advance(phase) -> void:
	_phase_done = false
	if phase.phase_completed.is_connected(PM._on_phase_completed):
		phase.phase_completed.disconnect(PM._on_phase_completed)
	phase.phase_completed.connect(func(): _phase_done = true)


## Enter `phase_id` directly (fresh phase instance), keeping the board.
func _enter(phase_id: int):
	PM.transition_to_phase(phase_id)
	var phase = PM.get_current_phase_instance()
	_no_phase_advance(phase)
	# Un-ready the Custodes so ka'tah windows (WP-C3) do not interleave.
	for uid in GS.state.units:
		var f = GS.state.units[uid].get("flags", {})
		if f.has(K.FLAG_READIED):
			f[K.FLAG_READIED] = false
	return phase


func _offer_ids(offers: Array) -> Array:
	return offers.map(func(o): return str(o.get("stratagem_id", "")))


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


## Put model 0 of `uid` just touching model 0 of `target_uid` (below it).
func _touch(uid: String, target_uid: String) -> void:
	var meas = root.get_node("Measurement")
	var tm: Dictionary = _unit(target_uid).models[0]
	var mm: Dictionary = _unit(uid).models[0]
	var tp := _pos(tm)
	var gap: float = meas.base_extent_px(tm) + meas.base_extent_px(mm) + 2.0
	mm["position"] = {"x": tp.x, "y": tp.y + gap}
	# keep the rest of the unit in coherency below the first model
	for i in range(1, _unit(uid).models.size()):
		_unit(uid).models[i]["position"] = {"x": tp.x + 60.0 * i, "y": tp.y + gap + 10.0}


## Move every model of `uid` onto objective `obj_id` (around its centre).
func _onto_objective(uid: String, obj_id: String) -> void:
	var c := Vector2.ZERO
	for o in GS.state.board.objectives:
		if str(o.id) == obj_id:
			c = _pos({"position": o.position}) if o.position is Dictionary else o.position
	var models: Array = _unit(uid).models
	for i in range(models.size()):
		models[i]["position"] = {"x": c.x + (i - (models.size() - 1) / 2.0) * 45.0, "y": c.y + 20.0}


func _far_away(uid: String) -> void:
	var models: Array = _unit(uid).models
	for i in range(models.size()):
		models[i]["position"] = {"x": 100.0 + i * 45.0, "y": 2350.0}


func _engaged_ids(uid: String) -> Array:
	return load("res://scripts/codex/custodes/CustodesCommon.gd").engaged_enemy_ids(uid)


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


## Synthetic melee board (attacker vs target), like test_custodes_army_rules_11e.gd.
func _melee_board(atk_flags: Dictionary, tgt_flags: Dictionary, tgt_kw: Array, rules: String, atk_kw: Array = ["ADEPTUS CUSTODES", "INFANTRY"], n_att: int = 5) -> Dictionary:
	var atk: Array = []
	for i in range(n_att):
		atk.append({"id": "ma%d" % i, "position": {"x": 10.0, "y": 10.0 + i * 30}, "base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 3, "current_wounds": 3})
	var tgt: Array = []
	for i in range(5):
		tgt.append({"id": "mt%d" % i, "position": {"x": 30.0, "y": 10.0 + i * 30}, "base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 30, "current_wounds": 30})
	var weapon := {"name": "Test Spear", "type": "Melee", "range": "Melee", "attacks": "6", "weapon_skill": "3",
		"strength": "6", "ap": "-1", "damage": "1", "special_rules": rules}
	return {"units": {
		"U_ATK": {"id": "U_ATK", "owner": 1,
			"meta": {"name": "Custodians", "keywords": atk_kw, "stats": {"toughness": 6, "save": 2, "wounds": 3},
				"abilities": [], "weapons": [weapon]},
			"flags": atk_flags, "models": atk},
		"U_TGT": {"id": "U_TGT", "owner": 2,
			"meta": {"name": "Targets", "keywords": tgt_kw, "stats": {"toughness": 5, "save": 6, "wounds": 30}, "abilities": []},
			"flags": tgt_flags, "models": tgt},
	}, "meta": {"phase": 10, "active_player": 1, "battle_round": 2}}


## Synthetic melee board with an S8 ORK attacker (owner 2) and a T6 Custodes
## INFANTRY target (owner 1) standing on obj_nml_1 (400, 880).
func _reverse_board() -> Dictionary:
	var atk: Array = []
	for i in range(5):
		atk.append({"id": "ma%d" % i, "position": {"x": 330.0 + i * 30, "y": 840.0}, "base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 3, "current_wounds": 3})
	var tgt: Array = []
	for i in range(5):
		tgt.append({"id": "mt%d" % i, "position": {"x": 340.0 + i * 30, "y": 880.0}, "base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 30, "current_wounds": 30})
	var weapon := {"name": "Test Spear", "type": "Melee", "range": "Melee", "attacks": "6", "weapon_skill": "3",
		"strength": "8", "ap": "-1", "damage": "1", "special_rules": ""}
	return {"units": {
		"U_ATK": {"id": "U_ATK", "owner": 2,
			"meta": {"name": "Nobz", "keywords": ["ORKS", "INFANTRY"], "stats": {"toughness": 5, "save": 4, "wounds": 3},
				"abilities": [], "weapons": [weapon]},
			"flags": {}, "models": atk},
		"U_TGT": {"id": "U_TGT", "owner": 1,
			"meta": {"name": "Custodians", "keywords": ["ADEPTUS CUSTODES", "INFANTRY"], "stats": {"toughness": 6, "save": 6, "wounds": 30}, "abilities": []},
			"flags": {}, "models": tgt},
	}, "meta": {"phase": 10, "active_player": 2, "battle_round": 2}}


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
	AIDM = load("res://scripts/AIDecisionMaker.gd")
	EP = load("res://autoloads/EffectPrimitives.gd")
	AM = load("res://scripts/rules/ActionsManager.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	GS.set_edition(11)

	print("\n=== test_custodes_detachments_11e ===\n")
	_check("fixture %s loads" % FIXTURE, _stage_fixture())
	GS.set_edition(11)
	root.get_node("SettingsService").set("auto_allocate_wounds", true)
	_enter(PHASE_COMMAND)
	_remember()

	_section_martial_mastery()
	_section_aquilan_shield()
	_section_dread_host()
	_section_emperors_chosen()
	_section_emissaries()
	_section_shadowkeepers()
	_section_solar_watch()
	_section_honoured_companions()
	_section_auric_champions()
	_section_lions()
	_section_moritoi()
	_section_grav_assault()
	_section_null_maiden()
	_section_ai()
	_section_10e_gone()


# ---------------------------------------------------------------------------
func _section_martial_mastery() -> void:
	print("\n-- A. Guardians of the Throne — Martial Mastery --")
	_restore()
	_set_det("Guardians of the Throne")
	_enter(PHASE_FIGHT)
	var offers: Array = SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": CG})
	var mm := _offer(offers, D.RULE_MARTIAL_MASTERY)
	_check("Martial Mastery offered when a Custodes unit is selected to fight", not mm.is_empty(), str(_offer_ids(offers)))
	_check("free (0 CP), a rule not a stratagem", int(mm.get("cp_cost", 9)) == 0 and bool(mm.get("cus11e_rule", false)))
	var t: Dictionary = mm.get("targets", [{}])[0]
	_check("the choice is [SUSTAINED HITS 1] or [LETHAL HITS] (require_variant)",
		bool(t.get("require_variant", false)) and t.get("variants", []).map(func(v): return str(v.id)) == ["sustained", "lethal"])
	_check("not offered for an Ork unit", _offer(SM.get_window_offers(2, "unit_selected_to_fight", {"unit_id": BOYZ}), D.RULE_MARTIAL_MASTERY).is_empty())
	_check("not offered in the Command phase window", _offer(SM.get_window_offers(1, "command_phase_main", {}), D.RULE_MARTIAL_MASTERY).is_empty())
	_set_det("Shadowkeepers")
	_check("not offered under another detachment", _offer(SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": CG}), D.RULE_MARTIAL_MASTERY).is_empty())
	_set_det("Guardians of the Throne")
	var bad: Dictionary = SM.use_stratagem(1, D.RULE_MARTIAL_MASTERY, CG, {})
	_check("using it without picking an option is refused", not bad.get("success", true))
	var cp_before := int(GS.state.players["1"].cp)
	var res: Dictionary = SM.use_stratagem(1, D.RULE_MARTIAL_MASTERY, CG, {"variant_id": "lethal"})
	_check("[LETHAL HITS] chosen", res.get("success", false), str(res))
	_check("costs no CP", int(GS.state.players["1"].cp) == cp_before)
	_check("flag on the unit = lethal", str(_flags(CG).get(D.F_MARTIAL_MASTERY, "")) == "lethal")
	_check("melee_weapon_grants: lethal from Martial Mastery", str(D.melee_weapon_grants(_unit(CG), _unit(BOYZ)).lethal).find("Martial Mastery") >= 0)
	_check("one choice per fight: no second offer", _offer(SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": CG}), D.RULE_MARTIAL_MASTERY).is_empty())
	D.on_phase_end(PHASE_FIGHT)
	_check("expires at the end of the phase", not _flags(CG).has(D.F_MARTIAL_MASTERY))
	# A/B dice: same seeds, sustained vs nothing, lethal vs nothing.
	var hits_plain := 0
	var hits_sus := 0
	var sus_flag := true
	var lethal_flag := true
	var plain_flags := false
	for s in range(12):
		var p = _melee(_melee_board({}, {}, ["INFANTRY"], ""), 300 + s)
		var su = _melee(_melee_board({D.F_MARTIAL_MASTERY: "sustained"}, {}, ["INFANTRY"], ""), 300 + s)
		var le = _melee(_melee_board({D.F_MARTIAL_MASTERY: "lethal"}, {}, ["INFANTRY"], ""), 300 + s)
		hits_plain += int(_block(p, "hit_roll_melee").get("total_hits_for_wounds", 0))
		hits_sus += int(_block(su, "hit_roll_melee").get("total_hits_for_wounds", 0))
		sus_flag = sus_flag and bool(_block(su, "hit_roll_melee").get("sustained_hits_weapon", false))
		lethal_flag = lethal_flag and bool(_block(le, "hit_roll_melee").get("lethal_hits_weapon", false))
		plain_flags = plain_flags or bool(_block(p, "hit_roll_melee").get("sustained_hits_weapon", false)) or bool(_block(p, "hit_roll_melee").get("lethal_hits_weapon", false))
	_check("[SUSTAINED HITS 1] applied in melee (every seed)", sus_flag)
	_check("[SUSTAINED HITS 1] yields more hits for wounds: %d -> %d" % [hits_plain, hits_sus], hits_sus > hits_plain)
	_check("[LETHAL HITS] applied in melee (every seed)", lethal_flag)
	_check("neither without the choice", not plain_flags)


func _section_aquilan_shield() -> void:
	print("\n-- B. Aquilan Shield — Gilded Guardians + Favoured SALVUS --")
	_restore()
	_set_det("Aquilan Shield")
	_onto_objective(CG, "obj_nml_1")
	var boyz := _unit(BOYZ)
	var cg := _unit(CG)
	_check("Custodian Guard is within range of obj_nml_1", D.within_objective_range(cg))
	_check("ranged S8 vs T6 on an objective: -1 to wound",
		_has_kind(D.wound_effects(boyz, cg, false, 8, 6), "minus_one", "Gilded Guardians"))
	_check("melee attacks unaffected (the rule is ranged only)",
		not _has_kind(D.wound_effects(boyz, cg, true, 8, 6), "minus_one", "Gilded Guardians"))
	_check("S not greater than T: unaffected",
		not _has_kind(D.wound_effects(boyz, cg, false, 6, 6), "minus_one", "Gilded Guardians"))
	_far_away(CG)
	_check("off the objective: unaffected",
		not _has_kind(D.wound_effects(boyz, _unit(CG), false, 8, 6), "minus_one", "Gilded Guardians"))
	_onto_objective(CONT, "obj_nml_1")
	_check("a VEHICLE / MONSTER unit is excluded",
		not _has_kind(D.wound_effects(boyz, _unit(CONT), false, 14, 9), "minus_one", "Gilded Guardians"))
	_set_det("Guardians of the Throne")
	_onto_objective(CG, "obj_nml_1")
	_check("another detachment: no Gilded Guardians",
		not _has_kind(D.wound_effects(boyz, _unit(CG), false, 8, 6), "minus_one", "Gilded Guardians"))
	_set_det("Aquilan Shield")
	var ranged := {"type": "Ranged", "range": "24"}
	var melee := {"type": "Melee", "range": "Melee"}
	_check("SALVUS not used: no Range bonus", D.range_bonus_inches(_unit(CG), ranged) == 0.0)
	_flags(CG)[K.flag_for("salvus")] = true
	_check("Favoured SALVUS: ranged attacks +6\" Range", D.range_bonus_inches(_unit(CG), ranged) == 6.0)
	_check("Favoured SALVUS: no Range on melee weapons", D.range_bonus_inches(_unit(CG), melee) == 0.0)
	_check("RulesEngine range hook includes it", RE.ork11e_det_range_bonus(_unit(CG), ranged) >= 6.0)
	_check("the Favoured text names the rider", D.favoured_katah_text(1, "salvus").find("+6") >= 0)
	_set_det("Dread Host")
	_check("other detachments' Salvus has no Range rider", D.range_bonus_inches(_unit(CG), ranged) == 0.0)


func _section_dread_host() -> void:
	print("\n-- C. Dread Host — Instruments of the Emperor's Wrath + Favoured DACATARAI --")
	_restore()
	_set_det("Dread Host")
	var fam = root.get_node("FactionAbilityManager")
	_check("Custodes unit can re-roll charge rolls", D.charge_reroll_source(_unit(CG)).find("Instruments") >= 0)
	_check("the charge phase sees the re-roll (FactionAbilityManager)", fam.unit_has_detachment_charge_reroll(_unit(CG)))
	_check("an Ork unit does not", not fam.unit_has_detachment_charge_reroll(_unit(BOYZ)))
	_set_det("Guardians of the Throne")
	_check("other detachments: no charge re-roll", D.charge_reroll_source(_unit(CG)) == "")
	_set_det("Dread Host")
	_touch(BOYZ, CG)
	_check("Boyz engaged with the Custodian Guard", CG in _engaged_ids(BOYZ), str(_engaged_ids(BOYZ)))
	_check("no Dacatarai: Boyz pile in 3\"", D.fight_move_cap(BOYZ, 3.0) == 3.0)
	_flags(CG)[K.flag_for("dacatarai")] = true
	_check("Favoured DACATARAI: the engaged enemy pile-in / consolidation is -2\" (3\" -> 1\")", D.fight_move_cap(BOYZ, 3.0) == 1.0)
	var fight = _enter(PHASE_FIGHT)
	_flags(CG)[K.flag_for("dacatarai")] = true
	_check("FightPhase validator uses the 1\" cap", fight._fight_base_move_cap(BOYZ) == 1.0)
	_check("FightPhase consolidation distance follows it", fight._get_consolidation_distance(BOYZ) == 1.0)
	_check("the AI plans with the same cap", is_equal_approx(AIDM._fight_move_cap_px(BOYZ), 40.0))
	_check("the Dacatarai unit itself is unaffected", D.fight_move_cap(CG, 3.0) == 3.0)
	_set_det("Solar Watch")
	_check("Dacatarai under another detachment: no rider", D.fight_move_cap(BOYZ, 3.0) == 3.0)


func _section_emperors_chosen() -> void:
	print("\n-- D. Emperor's Chosen — Magna Imperator + Favoured RENDAX --")
	_restore()
	_set_det("Emperor's Chosen")
	_enter(PHASE_FIGHT)
	D.on_phase_end(PHASE_FIGHT)
	var atk := {"id": "U_ATK", "owner": 1, "meta": {"keywords": ["ADEPTUS CUSTODES", "INFANTRY"]}}
	_check("one hit re-roll available", D.magna_imperator_available(atk, "hit"))
	D.magna_imperator_consume(atk, "hit")
	_check("used up for the phase", not D.magna_imperator_available(atk, "hit"))
	_check("the wound re-roll is separate", D.magna_imperator_available(atk, "wound"))
	D.on_phase_end(PHASE_FIGHT)
	_check("available again next phase", D.magna_imperator_available(atk, "hit"))
	_set_det("Guardians of the Throne")
	_check("other detachments: none", not D.magna_imperator_available(atk, "hit"))
	_set_det("Emperor's Chosen")
	var used_hit := 0
	var used_wound := 0
	var hits_off := 0
	var hits_on := 0
	var wounds_off := 0
	var wounds_on := 0
	for s in range(16):
		_set_det("Guardians of the Throne")
		var off = _melee(_melee_board({}, {}, ["INFANTRY"], ""), 500 + s)
		_set_det("Emperor's Chosen")
		D.on_phase_end(PHASE_FIGHT)
		var on = _melee(_melee_board({}, {}, ["INFANTRY"], ""), 500 + s)
		hits_off += int(_block(off, "hit_roll_melee").get("successes", 0))
		hits_on += int(_block(on, "hit_roll_melee").get("successes", 0))
		wounds_off += int(_block(off, "wound_roll_melee").get("successes", 0))
		wounds_on += int(_block(on, "wound_roll_melee").get("successes", 0))
		if _ledger_has(_block(on, "hit_roll_melee"), "Magna Imperator"):
			used_hit += 1
		if _ledger_has(_block(on, "wound_roll_melee"), "Magna Imperator"):
			used_wound += 1
	_check("Magna Imperator re-rolled a failed hit (ledger) in most fights: %d/16" % used_hit, used_hit >= 12)
	_check("Magna Imperator re-rolled a failed wound (ledger) in most fights: %d/16" % used_wound, used_wound >= 10)
	_check("never fewer hits than without it: %d -> %d" % [hits_off, hits_on], hits_on >= hits_off)
	_check("wounds overall not fewer: %d -> %d" % [wounds_off, wounds_on], wounds_on >= wounds_off - 2)
	D.on_phase_end(PHASE_FIGHT)
	var first = _melee(_melee_board({}, {}, ["INFANTRY"], ""), 77)
	var second = _melee(_melee_board({}, {}, ["INFANTRY"], ""), 77)
	_check("once per selection to attack: a second attack in the same phase gets no re-roll",
		not _ledger_has(_block(second, "hit_roll_melee"), "Magna Imperator") and not _ledger_has(_block(second, "wound_roll_melee"), "Magna Imperator"),
		str(_block(second, "hit_roll_melee").get("modifier_ledger", [])))
	# RENDAX rider
	_touch(BC, DREAD)
	_check("Blade Champion engaged with the Deff Dread", DREAD in _engaged_ids(BC), str(_engaged_ids(BC)))
	var sec: Dictionary = D.favoured_katah_secondary(1, "rendax", BC, {})
	_check("RENDAX rider offers the engaged VEHICLE", sec.get("options", []).map(func(o): return str(o.id)).has(DREAD), str(sec))
	_touch(BC, BOYZ)
	var sec2: Dictionary = D.favoured_katah_secondary(1, "rendax", BC, {})
	_check("no MONSTER / VEHICLE engaged: no rider pick", sec2.is_empty() or not sec2.get("options", []).map(func(o): return str(o.id)).has(BOYZ), str(sec2))
	_touch(BC, DREAD)
	var before := 0
	for m in _unit(DREAD).models:
		before += int(m.get("current_wounds", 0))
	RE.set_test_seed(9)
	var diffs: Array = D.favoured_katah_extra_effect(1, "rendax", BC, {"secondary_id": DREAD})
	var after := 0
	for m in _unit(DREAD).models:
		after += int(m.get("current_wounds", 0)) if m.get("alive", true) else 0
	_check("RENDAX: the Deff Dread suffers 1-3 mortal wounds (%d -> %d)" % [before, after], before - after >= 1 and before - after <= 3, str(diffs))
	_set_det("Guardians of the Throne")
	_check("RENDAX rider only for Emperor's Chosen", D.favoured_katah_extra_effect(1, "rendax", BC, {"secondary_id": DREAD}).is_empty())


func _section_emissaries() -> void:
	print("\n-- E. Emissaries Imperatus — Heralds of the Throne + Favoured CONSERVAI --")
	_restore()
	_set_det("Emissaries Imperatus")
	_check("Custodes units have Fights First", D.has_fights_first(_unit(CG)))
	_check("Ork units do not", not D.has_fights_first(_unit(BOYZ)))
	var seq = load("res://scripts/rules/FightSequencer.gd").new()
	_check("FightSequencer puts the unit in the Fights First step", seq.is_fights_first(_unit(CG)))
	_check("… not the Orks", not seq.is_fights_first(_unit(BOYZ)))
	var fight = _enter(PHASE_FIGHT)
	_check("board priority tint = Fights First", fight._get_fight_priority(_unit(CG)) == 0)
	_set_det("Guardians of the Throne")
	_check("other detachments: no Fights First", not seq.is_fights_first(_unit(CG)))
	_set_det("Emissaries Imperatus")
	# CONSERVAI rider: advance / fall back keep action eligibility.
	_far_away(BOYZ)
	_flags(CG)["advanced"] = true
	var plain: Dictionary = AM.can_start_action(CG, GS.state)
	_check("advanced, no Conservai: cannot start an action", not plain.eligible, str(plain))
	_flags(CG)[K.flag_for("conservai")] = true
	_check("Favoured CONSERVAI: advance keeps the unit eligible", D.move_keeps_action_eligibility(_unit(CG)))
	var withc: Dictionary = AM.can_start_action(CG, GS.state)
	_check("ActionsManager agrees (advanced + Conservai -> eligible)", withc.eligible, str(withc))
	_set_det("Guardians of the Throne")
	var gott: Dictionary = AM.can_start_action(CG, GS.state)
	_check("another detachment's Conservai does not lift the advance lock", not gott.eligible, str(gott))


func _section_shadowkeepers() -> void:
	print("\n-- F. Shadowkeepers — Wardens of the Dark Cells + Favoured KAPTARIS --")
	_restore()
	_set_det("Shadowkeepers")
	_onto_objective(CG, "obj_nml_1")
	var boyz := _unit(BOYZ)
	_check("melee S7 vs T6 on an objective: -1 to wound",
		_has_kind(D.wound_effects(boyz, _unit(CG), true, 7, 6), "minus_one", "Wardens of the Dark Cells"))
	_check("ranged attacks unaffected (melee only)",
		not _has_kind(D.wound_effects(boyz, _unit(CG), false, 7, 6), "minus_one", "Wardens"))
	_check("S not greater than T: unaffected",
		not _has_kind(D.wound_effects(boyz, _unit(CG), true, 5, 6), "minus_one", "Wardens"))
	# A/B through the melee resolver: an S8 Ork attacking a T6 Custodes unit
	# that stands on obj_nml_1 (same seeds, Shadowkeepers vs another detachment).
	var w_off := 0
	var w_on := 0
	var w_ledger := true
	for s in range(12):
		_set_det("Guardians of the Throne")
		var off = _melee(_reverse_board(), 600 + s)
		_set_det("Shadowkeepers")
		var on = _melee(_reverse_board(), 600 + s)
		w_off += int(_block(off, "wound_roll_melee").get("successes", 0))
		w_on += int(_block(on, "wound_roll_melee").get("successes", 0))
		if not _ledger_has(_block(on, "wound_roll_melee"), "Wardens of the Dark Cells"):
			w_ledger = false
	_check("resolver: Wardens of the Dark Cells -1 to wound (%d -> %d wounds, ledger every fight)" % [w_off, w_on], w_on < w_off and w_ledger)
	_enter(PHASE_FIGHT)
	_touch(BOYZ, CG)
	_onto_objective(CG, "obj_nml_1")
	_touch(BOYZ, CG)
	# KAPTARIS rider
	var sec: Dictionary = D.favoured_katah_secondary(1, "kaptaris", CG, {})
	_check("KAPTARIS rider offers the engaged enemy unit", sec.get("options", []).map(func(o): return str(o.id)).has(BOYZ), str(sec))
	var diffs: Array = D.favoured_katah_extra_effect(1, "kaptaris", CG, {"secondary_id": BOYZ})
	_check("KAPTARIS: the Boyz were made to take a battle-shock roll (stamped this phase)",
		str(_flags(BOYZ).get(D.F_SK_KAPTARIS, "")) == D.stamp(), str(diffs))
	var sec2: Dictionary = D.favoured_katah_secondary(1, "kaptaris", CG, {})
	_check("not the same enemy unit twice in a phase", sec2.is_empty() or not sec2.get("options", []).map(func(o): return str(o.id)).has(BOYZ), str(sec2))
	D.on_phase_end(PHASE_FIGHT)
	_check("stamp cleared at the end of the phase", not _flags(BOYZ).has(D.F_SK_KAPTARIS))
	_set_det("Guardians of the Throne")
	_check("KAPTARIS rider only for Shadowkeepers", D.favoured_katah_secondary(1, "kaptaris", CG, {}).is_empty())


func _section_solar_watch() -> void:
	print("\n-- G. Solar Watch — Talon Sortie + Favoured CALISTUS --")
	_restore()
	_set_det("Solar Watch")
	_check("fall back does not prevent a charge (Talon Sortie)", EP.has_effect_fall_back_and_charge(_unit(CG)))
	_check("not for the Orks", not EP.has_effect_fall_back_and_charge(_unit(BOYZ)))
	_set_det("Guardians of the Throne")
	_check("not under another detachment", not EP.has_effect_fall_back_and_charge(_unit(CG)))
	_set_det("Solar Watch")
	var mv = _enter(PHASE_MOVEMENT)
	var base_m: float = mv.get_unit_movement(_unit(CG))
	_flags(CG)[K.flag_for("calistus")] = true
	_check("Favoured CALISTUS: +2\" M (%.0f -> %.0f)" % [base_m, mv.get_unit_movement(_unit(CG))], mv.get_unit_movement(_unit(CG)) == base_m + 2.0)
	_set_det("Aquilan Shield")
	_check("Calistus under another detachment: no +2\"", mv.get_unit_movement(_unit(CG)) == base_m)


func _section_honoured_companions() -> void:
	print("\n-- H. Honoured Companions — Companion's Watch --")
	_restore()
	_set_det("Honoured Companions")
	_onto_objective(CG, "obj_nml_1")
	_check("TRUSTED SENTINEL within range of an objective re-rolls wound rolls of 1",
		_has_kind(D.wound_effects(_unit(CG), _unit(BOYZ), true, 6, 5), "reroll_ones", "Companion's Watch"))
	_onto_objective(WS_C, "obj_nml_2")
	_check("a unit without TRUSTED SENTINEL does not",
		not _has_kind(D.wound_effects(_unit(WS_C), _unit(BOYZ), true, 3, 5), "reroll_ones", "Companion's Watch"))
	_far_away(CG)
	_check("off the objective: no re-roll",
		not _has_kind(D.wound_effects(_unit(CG), _unit(BOYZ), true, 6, 5), "reroll_ones", "Companion's Watch"))


func _section_auric_champions() -> void:
	print("\n-- I. Auric Champions — Assemblage of Might --")
	_restore()
	_set_det("Auric Champions")
	_enter(PHASE_COMMAND)
	var offers: Array = SM.get_window_offers(1, "command_phase_main", {})
	var df := _offer(offers, D.RULE_DREADFUL_FOE)
	_check("dreadful foe choice offered in the Command phase", not df.is_empty(), str(_offer_ids(offers)))
	_check("every enemy unit on the battlefield is selectable", BOYZ in _target_ids(df) and DREAD in _target_ids(df) and not CG in _target_ids(df))
	_check("not offered to the opponent", _offer(SM.get_window_offers(2, "command_phase_main", {}), D.RULE_DREADFUL_FOE).is_empty())
	var res: Dictionary = SM.use_stratagem(1, D.RULE_DREADFUL_FOE, MEGA, {})
	_check("Meganobz selected as the dreadful foe", res.get("success", false), str(res))
	_check("flag = P1", int(_flags(MEGA).get(D.F_DREADFUL_FOE, 0)) == 1)
	_check("only one dreadful foe at a time", _offer(SM.get_window_offers(1, "command_phase_main", {}), D.RULE_DREADFUL_FOE).is_empty())
	_check("a CHARACTER model's attacks vs the dreadful foe: +1 to wound",
		_has_kind(D.wound_effects(_unit(SC), _unit(MEGA), true, 6, 5), "plus_one", "Assemblage of Might"))
	_check("a non-CHARACTER unit's attacks: no bonus",
		not _has_kind(D.wound_effects(_unit(CG), _unit(MEGA), true, 6, 5), "plus_one", "Assemblage"))
	_check("other enemies: no bonus",
		not _has_kind(D.wound_effects(_unit(SC), _unit(BOYZ), true, 6, 5), "plus_one", "Assemblage"))
	D.on_command_phase_start(2)
	_check("persists through the opponent's Command phase", int(_flags(MEGA).get(D.F_DREADFUL_FOE, 0)) == 1)
	D.on_command_phase_start(1)
	_check("expires at the start of P1's next Command phase", not _flags(MEGA).has(D.F_DREADFUL_FOE))


func _section_lions() -> void:
	print("\n-- J. Lions of the Emperor — On Gilded Wings --")
	_restore()
	_set_det("Lions of the Emperor")
	_unit(CG).meta.keywords.append("TERMINATOR")
	_far_away(BOYZ)
	_enter(PHASE_FIGHT)
	GS.state.meta["active_player"] = 2
	var offers: Array = SM.get_window_offers(1, "fight_phase_end", {})
	var gw := _offer(offers, D.RULE_GILDED_WINGS)
	_check("offered at the end of the opponent's Fight phase", not gw.is_empty(), str(_offer_ids(offers)))
	_check("only ADEPTUS CUSTODES TERMINATOR units", _target_ids(gw) == [CG], str(_target_ids(gw)))
	GS.state.meta["active_player"] = 1
	_check("not at the end of P1's own Fight phase", _offer(SM.get_window_offers(1, "fight_phase_end", {}), D.RULE_GILDED_WINGS).is_empty())
	GS.state.meta["active_player"] = 2
	_touch(BOYZ, CG)
	_check("an engaged TERMINATOR unit is not offered", _offer(SM.get_window_offers(1, "fight_phase_end", {}), D.RULE_GILDED_WINGS).is_empty())
	_far_away(BOYZ)
	var res: Dictionary = SM.use_stratagem(1, D.RULE_GILDED_WINGS, CG, {})
	_check("the unit is placed in strategic reserves", res.get("success", false) and int(_unit(CG).status) == GS.UnitStatus.IN_RESERVES, str(res))
	_check("its models leave the battlefield", _unit(CG).models.all(func(m): return m.get("position", null) == null))
	_check("reserve type strategic reserves + repositioned flag",
		str(_unit(CG).get("reserve_type", "")) == "strategic_reserves" and bool(_flags(CG).get("repositioned_to_reserves", false)))
	GS.state.meta["active_player"] = 1


func _section_moritoi() -> void:
	print("\n-- K. Might of the Moritoi — Moritoi Ancients --")
	_restore()
	_set_det("Might of the Moritoi")
	var cont := _unit(CONT)
	_check("DREADNOUGHT at starting strength: +2 OC", D.oc_bonus(cont) == 2)
	_check("…and no re-roll yet", not _has_kind(D.hit_effects(cont, _unit(MEGA), true), "reroll_ones", "Moritoi"))
	cont.models[0]["current_wounds"] = int(cont.models[0].wounds) - 1
	_check("below starting strength (lost a wound): no OC bonus", D.oc_bonus(cont) == 0)
	_check("below starting strength: re-roll hit rolls of 1", _has_kind(D.hit_effects(cont, _unit(MEGA), true), "reroll_ones", "Moritoi"))
	_check("…but not yet the wound re-roll", not _has_kind(D.wound_effects(cont, _unit(MEGA), true, 8, 5), "reroll_ones", "Moritoi"))
	cont.models[0]["current_wounds"] = 2
	_check("below half-strength: re-roll wound rolls of 1 too", _has_kind(D.wound_effects(cont, _unit(MEGA), true, 8, 5), "reroll_ones", "Moritoi"))
	_check("a non-DREADNOUGHT unit gets nothing", D.oc_bonus(_unit(CG)) == 0)
	_set_det("Guardians of the Throne")
	cont.models[0]["current_wounds"] = int(cont.models[0].wounds)
	_check("other detachments: no OC bonus", D.oc_bonus(cont) == 0)
	# Objective control end to end (MissionManager): Contemptor vs an Ork unit
	# with one more OC than its statline.
	_set_det("Might of the Moritoi")
	var mm = root.get_node("MissionManager")
	var obj := {"id": "obj_test", "position": Vector2(880, 1200)}
	var c_oc := int(cont.meta.stats.get("objective_control", 2))
	var c_unit: Dictionary = cont.duplicate(true)
	c_unit.models[0]["position"] = {"x": 880.0, "y": 1200.0}
	var o_unit: Dictionary = _unit(MEGA).duplicate(true)
	o_unit.meta.stats["objective_control"] = c_oc + 1
	for i in range(o_unit.models.size()):
		o_unit.models[i]["position"] = {"x": 860.0 + i * 20.0, "y": 1240.0}
	var units := {CONT: c_unit, MEGA: o_unit}
	_check("Moritoi Ancients: OC %d + 2 beats the Orks' %d" % [c_oc, c_oc + 1], mm._check_objective_control(obj, units) == 1)
	_set_det("Guardians of the Throne")
	_check("without the rule the Orks control it", mm._check_objective_control(obj, units) == 2)


func _section_grav_assault() -> void:
	print("\n-- L. Grav-Assault Force — Flare Shields --")
	_restore()
	_set_det("Grav-Assault Force")
	var cal := _unit(CALADIUS)
	_check("GRAV-ASSAULT unit: 4+ invulnerable save vs ranged attacks", D.invuln_save(cal, false) == 4)
	_check("not vs melee attacks", D.invuln_save(cal, true) == 0)
	_check("RulesEngine save hook takes the 4+ over none", RE.cus11e_invuln(cal, false, 0) == 4)
	_check("…but keeps a better existing save", RE.cus11e_invuln(cal, false, 3) == 3)
	_check("a non-GRAV-ASSAULT unit gets nothing", D.invuln_save(_unit(CG), false) == 0)
	_set_det("Guardians of the Throne")
	_check("other detachments: nothing", D.invuln_save(cal, false) == 0)


func _section_null_maiden() -> void:
	print("\n-- M. Null Maiden Vigil — Silent Sisterhood --")
	_restore()
	_set_det("Null Maiden Vigil")
	_check("an ANATHEMA PSYKANA CHARACTER may be the WARLORD", D.allows_anathema_psykana_warlord("Null Maiden Vigil"))
	_check("…not under other detachments", not D.allows_anathema_psykana_warlord("Guardians of the Throne"))
	# BATTLELINE for PROSECUTOR SQUAD units.
	var pros: Dictionary = _unit(WS_C).duplicate(true)
	pros["id"] = "U_PROSECUTORS_T"
	pros.meta["name"] = "Prosecutor Squad"
	pros.meta["keywords"] = ["ADEPTUS CUSTODES", "ANATHEMA PSYKANA", "IMPERIUM", "INFANTRY", "PROSECUTOR SQUAD"]
	GS.state.units["U_PROSECUTORS_T"] = pros
	var diffs: Array = D.apply_keyword_grants(1)
	_check("Prosecutor Squad gains BATTLELINE", "BATTLELINE" in _unit("U_PROSECUTORS_T").meta.keywords, str(diffs))
	_check("granted once (idempotent)", D.apply_keyword_grants(1).is_empty())
	_check("Witchseekers are not granted BATTLELINE", not "BATTLELINE" in _unit(WS_C).meta.keywords)
	GS.state.units.erase("U_PROSECUTORS_T")
	_set_det("Guardians of the Throne")
	var pros2: Dictionary = pros.duplicate(true)
	pros2.meta["keywords"] = ["ADEPTUS CUSTODES", "ANATHEMA PSYKANA", "INFANTRY", "PROSECUTOR SQUAD"]
	GS.state.units["U_PROSECUTORS_T"] = pros2
	D.apply_keyword_grants(1)
	_check("no BATTLELINE under another detachment", not "BATTLELINE" in _unit("U_PROSECUTORS_T").meta.keywords)
	GS.state.units.erase("U_PROSECUTORS_T")
	# Creeping Dread in the Orks' Command phase.
	_set_det("Null Maiden Vigil")
	_unit(GRETS).models[0]["alive"] = false
	var cmd = _enter(PHASE_COMMAND)
	GS.state.meta["active_player"] = 2
	var dread: Array = D.creeping_dread_units(2)
	_check("Gretchin below starting strength within 12\" of Witchseekers must test", GRETS in dread, str(dread))
	_check("Boyz at starting strength do not", not BOYZ in dread)
	_check("their battle-shock roll is at -1", D.battle_shock_roll_modifier(GRETS) == -1)
	_check("other units: no modifier", D.battle_shock_roll_modifier(BOYZ) == 0)
	cmd._units_needing_test = []
	cmd._identify_units_needing_tests()
	_check("the Command phase lists the Gretchin for a battle-shock test", GRETS in cmd._units_needing_test, str(cmd._units_needing_test))
	_check("not during the Custodes' own Command phase", D.creeping_dread_units(1).is_empty())
	_set_det("Guardians of the Throne")
	_check("no Creeping Dread under another detachment", D.creeping_dread_units(2).is_empty())
	GS.state.meta["active_player"] = 1


func _section_ai() -> void:
	print("\n-- N. AI answers every rule choice synchronously --")
	_restore()
	_set_det("Guardians of the Throne")
	_enter(PHASE_FIGHT)
	_touch(BOYZ, CG)
	var offers: Array = SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": CG})
	var t0 := Time.get_ticks_msec()
	var pick: Dictionary = AIDM.decide_window_stratagem(1, "unit_selected_to_fight", offers, {"unit_id": CG})
	_check("Martial Mastery: AI uses it with a variant", pick.get("use", false) and str(pick.get("stratagem_id", "")) == D.RULE_MARTIAL_MASTERY
		and str(pick.get("context", {}).get("variant_id", "")) in ["sustained", "lethal"], str(pick))
	_check("…answered synchronously (%d ms)" % (Time.get_ticks_msec() - t0), Time.get_ticks_msec() - t0 < 2000)
	var res: Dictionary = SM.use_stratagem(1, str(pick.stratagem_id), str(pick.target_unit_id), pick.get("context", {}))
	_check("the AI's pick is legal", res.get("success", false), str(res))
	_restore()
	_set_det("Auric Champions")
	_enter(PHASE_COMMAND)
	offers = SM.get_window_offers(1, "command_phase_main", {})
	pick = AIDM.decide_window_stratagem(1, "command_phase_main", offers, {})
	_check("Assemblage of Might: AI selects a dreadful foe", pick.get("use", false) and str(pick.get("stratagem_id", "")) == D.RULE_DREADFUL_FOE and _unit(str(pick.get("target_unit_id", ""))).get("owner", 0) == 2, str(pick))
	_restore()
	_set_det("Lions of the Emperor")
	_unit(CG).meta.keywords.append("TERMINATOR")
	_enter(PHASE_FIGHT)
	GS.state.meta["active_player"] = 2
	for m in _unit(CG).models:
		m["current_wounds"] = 1
	_unit(CG).models[0]["alive"] = false
	_unit(CG).models[1]["alive"] = false
	_far_away(BOYZ)
	offers = SM.get_window_offers(1, "fight_phase_end", {})
	pick = AIDM.decide_window_stratagem(1, "fight_phase_end", offers, {})
	_check("On Gilded Wings: AI lifts a TERMINATOR unit below half-strength", pick.get("use", false) and str(pick.get("target_unit_id", "")) == CG, str(pick))
	GS.state.meta["active_player"] = 1
	var empty_pick: Dictionary = D.ai_decide(1, "fight_phase_end", [], {})
	_check("no offers: the AI declines at once", empty_pick.is_empty())


func _section_10e_gone() -> void:
	print("\n-- O. the 10e Custodes detachment code is gone --")
	var fam = root.get_node("FactionAbilityManager")
	for fn in ["is_martial_mastery_available", "select_martial_mastery", "check_against_all_odds", "is_against_all_odds_active",
			"get_against_all_odds_status", "check_skin_crawling_disorientation"]:
		_check("FactionAbilityManager.%s removed" % fn, not fam.has_method(fn))
	var cmd_src := FileAccess.get_file_as_string("res://phases/CommandPhase.gd")
	_check("no SELECT_MARTIAL_MASTERY Command-phase step", cmd_src.find("\"SELECT_MARTIAL_MASTERY\"") < 0)
	var dep_src := FileAccess.get_file_as_string("res://phases/DeploymentPhase.gd")
	_check("no 10e CASTELLAN_REDEPLOY deployment hold", dep_src.find("CASTELLAN_REDEPLOY") < 0)
	var uam = root.get_node("UnitAbilityManager")
	for n in ["Auric Mantle", "Panoptispex", "Null Aegis (Aura)", "Deadly Unity (Aura)"]:
		_check("UnitAbilityManager has no 10e '%s' row" % n, not uam.ABILITY_EFFECTS.has(n))
	_check("13 codex detachments known", D.RULE_NAMES.size() == 13)
	for det in ["Shield Host", "Silent Hunters", "Talons of the Emperor", "Tharanatoi Hammerblow", "Solar Spearhead"]:
		_check("'%s' is not a codex detachment" % det, not D.is_codex_detachment(det))
