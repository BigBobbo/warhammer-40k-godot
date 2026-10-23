extends SceneTree

# Codex: Space Marines (11e) — generic DETACHMENT RULES + ENHANCEMENTS, group
# A (WP-M2a, scripts/codex/space_marines/SMDetachmentsA.gd): Gladius Task
# Force, Ironstorm Spearhead, Stormlance Task Force, Gauntlet Task Force,
# Phobos Shadow Force, Tacticus Attack Force, Phobos Shock Force. Rules text:
# .llm/codex_11e_wahapedia/space-marines/SPACE_MARINES_GENERIC.md. Against the
# real fixture tests/saves/sm11e_m2a_marines_active.w40ksave (P1 generic Space
# Marines with all seven detachments, P2 Orks; gen_sm11e_m2a_fixtures.gd).
#   A. gating (detachment taken, Space Marine army, edition 11)
#   B. enhancement bearer restrictions (data-driven EnhancementRules11e)
#   C. list build — Standard of the Emperor Ascendant, Artificer Armour,
#      Redoubtable Machine Spirit (idempotent, detachment-gated)
#   D. Gladius — Laurels of Triumph (A/B real melee), Ancient Exhortation
#      (window card, once per battle, +1 A, A/B real melee), Adept of the Codex
#   E. Ironstorm — Auto-targeters (single-die re-rolls, A/B real shooting),
#      Gunnery Honours [HEAVY], Redoubtable heal (real END_COMMAND)
#   F. Stormlance — Lightning-fast Strike +2" M, Supercharged Engines (free
#      advance re-roll), Auspex Triangulation Shrines (phase_start card)
#   G. Gauntlet — Combined Deployment (unit_has_shot card + [SUSTAINED HITS 1]),
#      Linebreaker Onslaught, Damocles-class Uplink (phase_start card)
#   H. Phobos Shadow Force — Shadow Masters (both choices), Execute and
#      Redeploy, Venator Omni-auspex
#   I. Tacticus — Wrath of the Chapter (real advance), Martial Paragon,
#      Spearpoint War Leader (Scouts 6")
#   J. Phobos Shock Force — Vanguard Ambushers (real end of Movement phase),
#      Seal of Shrouding (snap-shooting targets)
#   K. AI — every card answered synchronously, never stalls
#
# Usage: godot --headless --path 40k --script tests/test_sm11e_detachments_a.gd

const FIXTURE := "sm11e_m2a_marines_active"
const PHASE_COMMAND := 6
const PHASE_MOVEMENT := 7
const PHASE_SHOOTING := 8
const PHASE_CHARGE := 9
const PHASE_FIGHT := 10
const PX := 40.0

const ANCIENT := "U_ANCIENT_A"
const LT := "U_LIEUTENANT_A"
const CAPTAIN := "U_CAPTAIN_A"
const CHAPLAIN := "U_CHAPLAIN_A"
const REPULSOR := "U_REPULSOR_A"
const LANCER := "U_GLADIATOR_LANCER_A"
const OUTRIDERS := "U_OUTRIDER_SQUAD_A"
const SPEEDER := "U_LAND_SPEEDER_A"
const TECH := "U_TECHMARINE_A"
const CAP_PHOBOS := "U_CAPTAIN_IN_PHOBOS_ARMOUR_A"
const LT_PHOBOS := "U_LIEUTENANT_IN_PHOBOS_ARMOUR_A"
const LT_COMBI := "U_LIEUTENANT_WITH_COMBI_WEAPON_A"
const JUDICIAR := "U_JUDICIAR_A"
const APOTH := "U_APOTHECARY_A"
const LIB_PHOBOS := "U_LIBRARIAN_IN_PHOBOS_ARMOUR_A"
const INTER := "U_INTERCESSOR_SQUAD_A"
const IMPULSOR := "U_IMPULSOR_A"
const RHINO := "U_RHINO_A"
const REDEMPTOR := "U_REDEMPTOR_DREADNOUGHT_A"
const INFIL := "U_INFILTRATOR_SQUAD_A"
const SCOUTS := "U_SCOUT_SQUAD_A"
const BOYZ := "U_BOYZ_B"
const GRETS := "U_GRETCHIN_C"
const DREAD := "U_DEFF_DREAD_A"
const MEGA := "U_MEGANOBZ_A"

const ALL_DETS := ["Gladius Task Force", "Ironstorm Spearhead", "Stormlance Task Force", "Gauntlet Task Force",
	"Phobos Shadow Force", "Tacticus Attack Force", "Phobos Shock Force"]

var passed := 0
var failed := 0
var GS = null
var PM = null
var RE = null
var D = null
var C = null
var TM = null
var _base: Dictionary = {}


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


func _fac(p: int) -> Dictionary:
	return GS.state.factions[str(p)]


func _set_dets(dets: Array) -> void:
	_fac(1)["detachments"] = dets.duplicate()
	_fac(1)["detachment"] = str(dets[0]) if not dets.is_empty() else ""


func _remember() -> void:
	for uid in GS.state.units:
		var arr: Array = []
		for m in GS.state.units[uid].models:
			arr.append(m.get("position").duplicate() if m.get("position") is Dictionary else m.get("position"))
		_base[uid] = {"pos": arr, "embarked": GS.state.units[uid].get("embarked_in", null)}


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
		var keep := {}
		for k in u.get("flags", {}):
			if str(k).begins_with("sm11e_listbuild_") or str(k) == "sw11e_transhuman_round":
				keep[k] = u.flags[k]
		u["flags"] = keep
		u.erase("attached_to")
		if u.has("attachment_data"):
			u["attachment_data"] = {"attached_characters": []}
		u.erase("disembarked_this_phase")
		if b.get("embarked", null) != null:
			u["embarked_in"] = b.embarked
		else:
			u.erase("embarked_in")
			u["status"] = GS.UnitStatus.DEPLOYED
	GS.state.meta["active_player"] = 1
	GS.state.meta["battle_round"] = 2
	_set_dets(ALL_DETS)
	for p in ["1", "2"]:
		for k in _fac(int(p)).keys():
			if str(k).begins_with("sw11e_") or str(k).begins_with("sm11e_"):
				_fac(int(p)).erase(k)
	TM.terrain_features = []
	D.reset_reroll_ledger()


func _enter(phase_id: int):
	PM.transition_to_phase(phase_id)
	var phase = PM.get_current_phase_instance()
	if phase.phase_completed.is_connected(PM._on_phase_completed):
		phase.phase_completed.disconnect(PM._on_phase_completed)
	return phase


## Enter a phase and decline the windows it opened at its start (the
## phase_start cards of this module — Damocles-class Uplink — would otherwise
## block the phase's actions).
func _enter_clear(phase_id: int):
	var phase = _enter(phase_id)
	for _i in range(6):
		if not phase.has_pending_stratagem_window():
			break
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": phase.get_pending_stratagem_window_decider()})
	return phase


func _set_phase(phase_id: int) -> void:
	GS.state.meta["phase"] = phase_id


func _move_to(uid: String, x: float, y: float) -> void:
	var c := Vector2.ZERO
	var n := 0
	for m in GS.state.units[uid].models:
		var p = m.position
		c += Vector2(float(p.x), float(p.y))
		n += 1
	var d: Vector2 = Vector2(x, y) * PX - c / float(n)
	for m in GS.state.units[uid].models:
		m["position"] = {"x": float(m.position.x) + d.x, "y": float(m.position.y) + d.y}


## A dense ruin (TerrainManager) covering a rectangle in inches.
func _ruin_around(x0: float, y0: float, x1: float, y1: float) -> void:
	var poly := PackedVector2Array([Vector2(x0, y0) * PX, Vector2(x1, y0) * PX, Vector2(x1, y1) * PX, Vector2(x0, y1) * PX])
	TM.terrain_features.append({"id": "sm11e_ruin_%d" % TM.terrain_features.size(), "type": "ruins", "polygon": poly, "height_category": "tall"})


func _mods(atk: String, tgt: String, melee: bool, wp: Dictionary = {"name": "test"}) -> Dictionary:
	return RE.ork11e_ab_mods(_unit(atk), _unit(tgt), wp, melee, GS.state)


func _src_names(m: Dictionary) -> Array:
	return m.get("sources", []).map(func(s): return str(s.get("name", "")))


func _game_log_contains(needle: String) -> bool:
	for e in root.get_node("GameEventLog").get_all_entries():
		if str(e.get("text", "")).contains(needle):
			return true
	return false


func _offers(player: int, window_id: String, ctx: Dictionary) -> Array:
	return root.get_node("StratagemManager").get_window_offers(player, window_id, ctx)


func _offer(player: int, window_id: String, ctx: Dictionary, sid: String) -> Dictionary:
	for o in _offers(player, window_id, ctx):
		if str(o.get("stratagem_id", "")) == sid:
			return o
	return {}


func _use(player: int, sid: String, target: String, ctx: Dictionary = {}) -> Dictionary:
	return root.get_node("StratagemManager").use_stratagem(player, sid, target, ctx)


func _weapon_id(uid: String, name_part: String) -> String:
	var w: Dictionary = RE.get_unit_weapons(uid, GS.state)
	for mid in w:
		for wid in w[mid]:
			if str(RE.get_weapon_profile(str(wid), GS.state).get("name", "")).to_lower().contains(name_part.to_lower()):
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
	var board: Dictionary = GS.create_snapshot()
	RE.set_test_seed(seed_val)
	return RE.resolve_shoot({"type": "SHOOT", "actor_unit_id": uid, "payload": {"assignments": [_assign(board, uid, wid, tid)]}}, board, RE.RNGService.new(seed_val))


func _melee(atk: String, tgt: String, weapon_name: String, seed_val: int) -> Dictionary:
	var board: Dictionary = GS.create_snapshot()
	RE.set_test_seed(seed_val)
	return RE.resolve_melee_attacks({"type": "FIGHT", "actor_unit_id": atk,
		"payload": {"assignments": [{"attacker": atk, "target": tgt, "weapon": weapon_name}]}}, board, RE.RNGService.new(seed_val))


func _block(res: Dictionary, context: String) -> Dictionary:
	for b in res.get("dice", []):
		if str(b.get("context", "")) == context:
			return b
	return {}


func _dice_text(res: Dictionary) -> String:
	return JSON.stringify(res.get("dice", []))


# ---------------------------------------------------------------------------
func _run() -> void:
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	TM = root.get_node("TerrainManager")
	D = load("res://scripts/codex/space_marines/SMDetachmentsA.gd")
	C = load("res://scripts/codex/space_wolves/SWCommon.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	GS.set_edition(11)

	print("\n=== test_sm11e_detachments_a ===\n")
	_check("fixture %s loads" % FIXTURE, _stage_fixture())
	GS.set_edition(11)
	root.get_node("SettingsService").set("auto_allocate_wounds", true)
	_enter(PHASE_COMMAND)
	_remember()
	_restore()

	_section_gating()
	_section_validation()
	_section_list_build()
	_section_gladius()
	_section_ironstorm()
	_section_stormlance()
	_section_gauntlet()
	_section_shadow()
	_section_tacticus()
	_section_shock()
	_section_ai()


# ---------------------------------------------------------------------------
func _section_gating() -> void:
	print("\n-- A. gating --")
	_restore()
	for det in D.DETACHMENTS:
		_check("P1 took %s" % det, D.has_det(1, det))
	_check("P2 (Orks) took none of them", not D.has_det(2, D.GLADIUS))
	_set_dets(["Ironstorm Spearhead"])
	_check("narrowed to Ironstorm: no Tacticus Attack Force", not D.has_det(1, D.TACTICUS) and D.has_det(1, D.IRONSTORM))
	_check("an enhancement of a detachment not taken is inactive (Laurels / Gladius)", not D.has_enh(_unit(LT), D.LAURELS))
	_check("Gunnery Honours active with Ironstorm", D.has_enh(_unit(LANCER), D.GUNNERY))
	GS.set_edition(10)
	_check("edition 10: no detachment rule", not D.has_det(1, D.IRONSTORM) and not D.has_enh(_unit(LANCER), D.GUNNERY))
	GS.set_edition(11)
	_restore()
	_check("Venator Omni-auspex counts for Phobos Shadow Force OR Phobos Shock Force", D.has_enh(_unit(LT_PHOBOS), D.VENATOR))
	_set_dets(["Phobos Shock Force"])
	_check("... Shock Force alone", D.has_enh(_unit(LT_PHOBOS), D.VENATOR))
	_set_dets(["Phobos Shadow Force"])
	_check("... Shadow Force alone", D.has_enh(_unit(LT_PHOBOS), D.VENATOR))
	_set_dets(["Gladius Task Force"])
	_check("... neither: inactive", not D.has_enh(_unit(LT_PHOBOS), D.VENATOR))
	_restore()


func _army(dets: Array, units: Dictionary) -> Dictionary:
	return {"faction": {"name": "Space Marines", "points": 2000, "detachment": dets[0], "detachments": dets}, "units": units}


func _au(src_uid: String, enh: String) -> Dictionary:
	var u: Dictionary = _unit(src_uid).duplicate(true)
	u.meta["enhancements"] = [enh]
	return u


func _section_validation() -> void:
	print("\n-- B. enhancement bearer restrictions (EnhancementRules11e) --")
	var ER = load("res://scripts/codex/EnhancementRules11e.gd")
	var good := {
		"Standard of the Emperor Ascendant": [ANCIENT, "Gladius Task Force"],
		"Laurels of Triumph": [LT, "Gladius Task Force"],
		"Adept of the Codex": [CAPTAIN, "Gladius Task Force"],
		"Artificer Armour": [CHAPLAIN, "Gladius Task Force"],
		"Redoubtable Machine Spirit": [REPULSOR, "Ironstorm Spearhead"],
		"Gunnery Honours": [LANCER, "Ironstorm Spearhead"],
		"Supercharged Engines": [OUTRIDERS, "Stormlance Task Force"],
		"Auspex Triangulation Shrines": [SPEEDER, "Stormlance Task Force"],
		"Linebreaker Onslaught": [TECH, "Gauntlet Task Force"],
		"Damocles-class Uplink": [CAP_PHOBOS, "Gauntlet Task Force"],
		"Venator Omni-auspex": [LT_PHOBOS, "Phobos Shadow Force"],
		"Execute and Redeploy": [LT_COMBI, "Phobos Shadow Force"],
		"Martial Paragon": [JUDICIAR, "Tacticus Attack Force"],
		"Spearpoint War Leader": [APOTH, "Tacticus Attack Force"],
		"Seal of Shrouding": [LIB_PHOBOS, "Phobos Shock Force"],
	}
	for enh in good:
		var spec: Array = good[enh]
		var r: Dictionary = ER.validate_army(_army([spec[1]], {"A": _au(str(spec[0]), enh)}))
		_check("%s on %s (%s): clean" % [enh, _unit(str(spec[0])).meta.name, spec[1]], r.warnings.is_empty(), str(r.warnings))
	var bad := {
		"Standard of the Emperor Ascendant": [LT, "Gladius Task Force", "not an Ancient"],
		"Adept of the Codex": [LT, "Gladius Task Force", "not a Captain"],
		"Redoubtable Machine Spirit": [IMPULSOR, "Ironstorm Spearhead", "a DEDICATED TRANSPORT"],
		"Gunnery Honours": [REDEMPTOR, "Ironstorm Spearhead", "a WALKER"],
		"Supercharged Engines": [SPEEDER, "Stormlance Task Force", "not MOUNTED"],
		"Auspex Triangulation Shrines": [OUTRIDERS, "Stormlance Task Force", "not a SPEEDER"],
		"Damocles-class Uplink": [LT, "Gauntlet Task Force", "not a Captain"],
		"Venator Omni-auspex": [LT, "Phobos Shadow Force", "not PHOBOS"],
		"Martial Paragon": [LT_PHOBOS, "Tacticus Attack Force", "not TACTICUS"],
		"Seal of Shrouding": [CHAPLAIN, "Phobos Shock Force", "not PHOBOS"],
	}
	for enh in bad:
		var spec: Array = bad[enh]
		var r: Dictionary = ER.validate_army(_army([spec[1]], {"A": _au(str(spec[0]), enh)}))
		_check("%s on %s (%s): bearer warning" % [enh, _unit(str(spec[0])).meta.name, spec[2]], not r.warnings.is_empty(), str(r.warnings))
	var wrong_det: Dictionary = ER.validate_army(_army(["Ironstorm Spearhead"], {"A": _au(LT, "Laurels of Triumph")}))
	_check("Laurels of Triumph without Gladius Task Force: warning", not wrong_det.warnings.is_empty(), str(wrong_det.warnings))


func _section_list_build() -> void:
	print("\n-- C. list build --")
	_restore()
	var army = JSON.parse_string(FileAccess.get_file_as_string("res://armies/sm11e_codex_test.json"))
	var anc: Dictionary = army.units[ANCIENT]
	var oc0 := int(anc.meta.stats.get("objective_control", 0))
	var ld0 := int(anc.meta.stats.get("leadership", 7))
	anc.meta["enhancements"] = ["Standard of the Emperor Ascendant"]
	D.apply_list_build(ANCIENT, anc, ["Gladius Task Force"])
	_check("Standard: +1 OC", int(anc.meta.stats.objective_control) == oc0 + 1, "%d -> %d" % [oc0, int(anc.meta.stats.objective_control)])
	_check("Standard: Ld improved by 1", int(anc.meta.stats.leadership) == ld0 - 1, "%d -> %d" % [ld0, int(anc.meta.stats.leadership)])
	_check("Standard: Feel No Pain 5+ (RulesEngine.get_unit_fnp)", RE.get_unit_fnp(anc) == 5)
	D.apply_list_build(ANCIENT, anc, ["Gladius Task Force"])
	_check("idempotent: a second pass changes nothing", int(anc.meta.stats.objective_control) == oc0 + 1 and int(anc.meta.stats.leadership) == ld0 - 1)
	var anc2: Dictionary = army.units["U_ANCIENT_IN_TERMINATOR_ARMOUR_A"]
	var oc_b := int(anc2.meta.stats.get("objective_control", 0))
	anc2.meta["enhancements"] = ["Standard of the Emperor Ascendant"]
	var lines: Array = D.apply_list_build("U_ANCIENT_IN_TERMINATOR_ARMOUR_A", anc2, ["Ironstorm Spearhead"])
	_check("without Gladius Task Force: not applied", int(anc2.meta.stats.objective_control) == oc_b and str(lines).contains("not applied"), str(lines))
	var ch: Dictionary = army.units[CHAPLAIN]
	ch.meta["enhancements"] = ["Artificer Armour"]
	D.apply_list_build(CHAPLAIN, ch, ["Gladius Task Force"])
	_check("Artificer Armour: Sv 2+", int(ch.meta.stats.save) == 2)
	_check("Artificer Armour: Feel No Pain 5+", RE.get_unit_fnp(ch) == 5)
	var rep: Dictionary = army.units[REPULSOR]
	rep.meta["enhancements"] = ["Redoubtable Machine Spirit"]
	D.apply_list_build(REPULSOR, rep, ["Ironstorm Spearhead"])
	_check("Redoubtable Machine Spirit: 5+ invulnerable save (stats + every model)", int(rep.meta.stats.invuln) == 5 and int(rep.models[0].get("invuln", 0)) == 5)
	# The fixture (built through the same pass) carries them in the game.
	_check("fixture: the Ancient has FNP 5+ in the game", RE.get_unit_fnp(_unit(ANCIENT)) == 5)
	_check("fixture: the Chaplain has Sv 2+", int(_unit(CHAPLAIN).meta.stats.save) == 2)
	_check("fixture: the Repulsor has a 5+ invulnerable save", int(_unit(REPULSOR).models[0].get("invuln", 0)) == 5)


func _section_gladius() -> void:
	print("\n-- D. Gladius Task Force enhancements --")
	_restore()
	# Laurels of Triumph.
	var m := _mods(LT, BOYZ, true)
	_check("Laurels: the Lieutenant's melee attacks +1 S and +1 AP", int(m.get("strength", 0)) == 1 and int(m.get("ap", 0)) == 1, str(m))
	_check("Laurels: named for the ledger", "Laurels of Triumph" in _src_names(m))
	_check("Laurels: not ranged", int(_mods(LT, BOYZ, false).get("strength", 0)) == 0)
	_check("Laurels: not the Ancient (not the bearer)", int(_mods(ANCIENT, BOYZ, true).get("strength", 0)) == 0)
	_fac(1)["sw11e_doctrine"] = "assault"
	var m2 := _mods(LT, BOYZ, true)
	_check("Laurels + assault doctrine: +2 S and +2 AP", int(m2.get("strength", 0)) == 2 and int(m2.get("ap", 0)) == 2, str(m2))
	_fac(1)["sw11e_doctrine"] = ""
	var with_l := _melee(LT, BOYZ, "Master-crafted Power Weapon", 21)
	_set_dets(["Ironstorm Spearhead"])
	var without_l := _melee(LT, BOYZ, "Master-crafted Power Weapon", 21)
	_set_dets(ALL_DETS)
	var w_s := int(_block(with_l, "wound_roll_melee").get("strength", -1))
	var wo_s := int(_block(without_l, "wound_roll_melee").get("strength", -1))
	_check("real melee (same seed): Laurels gives the Lieutenant +1 S", w_s == wo_s + 1 and wo_s > 0, "with S%d / without S%d" % [w_s, wo_s])
	# Ancient Exhortation — unit_selected_to_fight card, once per battle per army.
	_enter(PHASE_FIGHT)
	var ctx := {"phase": "fight", "unit_id": ANCIENT, "window_id": "unit_selected_to_fight"}
	_check("not offered for another unit (the Lieutenant)", _offer(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": LT}, D.RULE_EXHORTATION).is_empty())
	_check("not offered to the opponent", _offer(2, "unit_selected_to_fight", ctx, D.RULE_EXHORTATION).is_empty())
	var off := _offer(1, "unit_selected_to_fight", ctx, D.RULE_EXHORTATION)
	_check("ANCIENT EXHORTATION offered when the Ancient is selected to fight (free)", not off.is_empty() and int(off.get("cp_cost", 1)) == 0, str(off))
	var a_before := _melee(ANCIENT, BOYZ, "Power Weapon", 31)
	var cp_before := int(GS.state.players["1"].cp)
	var r := _use(1, D.RULE_EXHORTATION, ANCIENT)
	_check("used", r.get("success", false), str(r))
	_check("no CP spent", int(GS.state.players["1"].cp) == cp_before)
	_check("+1 A on the Ancient's melee attacks this phase", int(_mods(ANCIENT, BOYZ, true).get("attacks", 0)) == 1)
	_check("not on ranged attacks", int(_mods(ANCIENT, BOYZ, false).get("attacks", 0)) == 0)
	_check("Game Log line", _game_log_contains("ANCIENT EXHORTATION"))
	var a_after := _melee(ANCIENT, BOYZ, "Power Weapon", 31)
	var hb := _block(a_before, "hit_roll_melee")
	var ha := _block(a_after, "hit_roll_melee")
	_check("real melee (same seed): one more attack", (ha.get("rolls_raw", []) as Array).size() == (hb.get("rolls_raw", []) as Array).size() + 1,
		"before %d / after %d" % [(hb.get("rolls_raw", []) as Array).size(), (ha.get("rolls_raw", []) as Array).size()])
	_check("once per battle: not offered again", _offer(1, "unit_selected_to_fight", ctx, D.RULE_EXHORTATION).is_empty())
	GS.state.meta["phase"] = PHASE_SHOOTING
	_check("expires with the phase (stamp)", int(_mods(ANCIENT, BOYZ, true).get("attacks", 0)) == 0)
	GS.state.meta["phase"] = PHASE_FIGHT
	# Adept of the Codex — tactical doctrine in addition.
	_restore()
	_enter(PHASE_COMMAND)  # phase transition hook refreshes it
	_fac(1)["sw11e_doctrine"] = "assault"
	_check("Adept of the Codex: tactical active for the Captain", C.doctrine_active(_unit(CAPTAIN), "tactical"))
	_check("... in addition to the army doctrine (assault)", C.doctrine_active(_unit(CAPTAIN), "assault"))
	_check("not for the Intercessors (not his unit)", not C.doctrine_active(_unit(INTER), "tactical"))
	_unit(CAPTAIN)["attached_to"] = INTER
	_unit(INTER)["attachment_data"] = {"attached_characters": [CAPTAIN]}
	D.refresh_adept_of_the_codex()
	_check("Captain leads the Intercessors: tactical active for the whole Attached unit", C.doctrine_active(_unit(INTER), "tactical"))
	_unit(CAPTAIN).erase("attached_to")
	_unit(INTER)["attachment_data"] = {"attached_characters": []}
	D.refresh_adept_of_the_codex()
	_check("he leaves: the Intercessors lose it", not C.doctrine_active(_unit(INTER), "tactical") and not _flags(INTER).has("sw11e_doctrine_extra"))
	_set_dets(["Ironstorm Spearhead"])
	D.refresh_adept_of_the_codex()
	_check("without Gladius: no extra doctrine", not C.doctrine_active(_unit(CAPTAIN), "tactical"))
	_restore()


func _section_ironstorm() -> void:
	print("\n-- E. Ironstorm Spearhead --")
	_restore()
	_enter(PHASE_SHOOTING)
	_check("Auto-targeters: the Impulsor (VEHICLE) re-rolls one hit roll", D.reroll_one_source(_unit(IMPULSOR), "hit", false) == "Ironstorm Auto-targeters")
	_check("... and one wound roll", D.reroll_one_source(_unit(IMPULSOR), "wound", false) == "Ironstorm Auto-targeters")
	_check("not the Redemptor (WALKER)", D.reroll_one_source(_unit(REDEMPTOR), "hit", false) == "")
	_check("not melee", D.reroll_one_source(_unit(IMPULSOR), "hit", true) == "")
	_check("not INFANTRY", D.reroll_one_source(_unit(INTER), "hit", false) == "")
	D.reroll_one_consume(_unit(IMPULSOR), "hit", "Ironstorm Auto-targeters")
	_check("once per phase: the hit re-roll is spent", D.reroll_one_source(_unit(IMPULSOR), "hit", false) == "")
	_check("... the wound re-roll is not", D.reroll_one_source(_unit(IMPULSOR), "wound", false) != "")
	GS.state.meta["phase"] = PHASE_FIGHT
	_check("another phase: available again", D.reroll_one_source(_unit(IMPULSOR), "hit", false) != "")
	GS.state.meta["phase"] = PHASE_SHOOTING
	_set_dets(["Gladius Task Force"])
	_check("without Ironstorm: none", D.reroll_one_source(_unit(IMPULSOR), "wound", false) == "")
	_restore()
	_enter(PHASE_SHOOTING)
	# A/B real ranged resolution, same seed: a failed die is re-rolled and named.
	var wid := _weapon_id(IMPULSOR, "storm bolter")
	var found := false
	var seed_used := -1
	for s in range(1, 40):
		D.reset_reroll_ledger()
		var with_r := _shoot(IMPULSOR, wid, GRETS, 100 + s)
		if _dice_text(with_r).contains("Ironstorm Auto-targeters"):
			found = true
			seed_used = 100 + s
			break
	_check("real shooting: Ironstorm Auto-targeters re-rolls a failed die (ledger names it)", found, "weapon %s" % wid)
	if found:
		_set_dets(["Gladius Task Force"])
		var without_r := _shoot(IMPULSOR, wid, GRETS, seed_used)
		_check("same seed without Ironstorm: no re-roll", not _dice_text(without_r).contains("Ironstorm Auto-targeters"))
		_set_dets(ALL_DETS)
	# Gunnery Honours — [HEAVY] for the Gladiator Lancer.
	_restore()
	var lwid := _weapon_id(LANCER, "defensive")
	var lprof: Dictionary = RE.get_weapon_profile(lwid, GS.state)
	_flags(LANCER)["remained_stationary"] = true
	var gm := _mods(LANCER, DREAD, false, lprof)
	_check("Gunnery Honours: stationary Lancer's ranged attacks +1 to hit ([HEAVY])", bool(gm.get("hit_plus", false)) and "Gunnery Honours" in _src_names(gm), str(gm))
	_flags(LANCER).erase("remained_stationary")
	_flags(LANCER)["moved_max_inches"] = 8.0
	_check("moved more than 3\": no [HEAVY] bonus", not bool(_mods(LANCER, DREAD, false, lprof).get("hit_plus", false)))
	_flags(LANCER)["moved_max_inches"] = 2.0
	_check("moved 3\" or less: bonus", bool(_mods(LANCER, DREAD, false, lprof).get("hit_plus", false)))
	_check("not melee", not bool(_mods(LANCER, DREAD, true, lprof).get("hit_plus", false)))
	_check("a weapon that already has [HEAVY] is not doubled", not bool(_mods(LANCER, DREAD, false, {"name": "x", "keywords": ["HEAVY"]}).get("hit_plus", false)))
	# Redoubtable Machine Spirit — heals 1 at the end of your Command phase (real END_COMMAND).
	_restore()
	var rm: Dictionary = _unit(REPULSOR).models[0]
	var full := int(rm.wounds)
	rm["current_wounds"] = full - 3
	var cp = _enter(PHASE_COMMAND)
	cp.execute_action({"type": "SKIP_COMBAT_DOCTRINE", "player": 1})
	var er: Dictionary = cp.execute_action({"type": "END_COMMAND", "player": 1})
	if er.get("success", false) and cp.has_method("has_pending_stratagem_window") and cp.has_pending_stratagem_window():
		for _i in range(4):
			if not cp.has_pending_stratagem_window():
				break
			cp.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": cp.get_pending_stratagem_window_decider()})
	_check("END_COMMAND: Redoubtable Machine Spirit healed 1 wound", int(_unit(REPULSOR).models[0].current_wounds) == full - 2, "%d/%d (end result %s)" % [int(_unit(REPULSOR).models[0].current_wounds), full, str(er.get("success", false))])
	_check("Game Log line", _game_log_contains("Redoubtable Machine Spirit"))
	_set_phase(PHASE_COMMAND)
	D.on_command_phase_end(1)
	_check("once per Command phase", int(_unit(REPULSOR).models[0].current_wounds) == full - 2)
	_restore()
	_set_phase(PHASE_COMMAND)
	D.on_command_phase_end(1)
	_check("an undamaged vehicle: nothing", int(_unit(REPULSOR).models[0].current_wounds) == full)
	_restore()


func _section_stormlance() -> void:
	print("\n-- F. Stormlance Task Force --")
	_restore()
	var mv = _enter(PHASE_MOVEMENT)
	var base_m := float(_unit(OUTRIDERS).meta.stats.get("move", 0))
	_check("Lightning-fast Strike: Outriders (MOUNTED) +2\" M", D.move_bonus_inches(_unit(OUTRIDERS)) == 2.0)
	_check("Land Speeder (SPEEDER) +2\" M", D.move_bonus_inches(_unit(SPEEDER)) == 2.0)
	_check("Intercessors: no bonus", D.move_bonus_inches(_unit(INTER)) == 0.0)
	_check("MovementPhase.get_unit_movement: Outriders M + 2", absf(mv.get_unit_movement(_unit(OUTRIDERS)) - (base_m + 2.0)) < 0.01, "%.1f (base %.1f)" % [mv.get_unit_movement(_unit(OUTRIDERS)), base_m])
	_set_dets(["Gladius Task Force"])
	_check("without Stormlance: M unchanged", absf(mv.get_unit_movement(_unit(OUTRIDERS)) - base_m) < 0.01)
	_restore()
	# Supercharged Engines — free advance re-roll.
	_check("Supercharged Engines: Outriders can re-roll advance rolls", D.free_advance_reroll_source(_unit(OUTRIDERS)) == "Supercharged Engines")
	_check("Land Speeder (no enhancement, not TACTICUS): no re-roll", D.free_advance_reroll_source(_unit(SPEEDER)) == "")
	mv = _enter(PHASE_MOVEMENT)
	var got_free := false
	for s in range(1, 30):
		_restore()
		mv = _enter_clear(PHASE_MOVEMENT)
		var r: Dictionary = mv.execute_action({"type": "BEGIN_ADVANCE", "actor_unit_id": OUTRIDERS, "player": 1, "payload": {"rng_seed": 300 + s}})
		if bool(r.get("awaiting_reroll", false)) and str(mv._reroll_pending_data.get("free_ability", "")) == "Supercharged Engines":
			got_free = true
			var cp_before := int(GS.state.players["1"].cp)
			var rr: Dictionary = mv.execute_action({"type": "USE_COMMAND_REROLL", "player": 1})
			_check("the free re-roll resolves (no CP)", rr.get("success", false) and int(GS.state.players["1"].cp) == cp_before, "%s cp %d -> %d" % [str(rr.get("error", "")), cp_before, int(GS.state.players["1"].cp)])
			break
	_check("real advance roll below 6: the free Supercharged Engines re-roll is offered", got_free)
	# Auspex Triangulation Shrines — phase_start card of your Shooting phase.
	_restore()
	_enter(PHASE_SHOOTING)
	var ctx := {"phase": "shooting", "window_id": "phase_start"}
	var off := _offer(1, "phase_start", ctx, D.RULE_AUSPEX)
	_check("AUSPEX offered at the start of P1's Shooting phase", not off.is_empty(), str(_offers(1, "phase_start", ctx).map(func(o): return o.name)))
	var opts: Array = []
	if not off.is_empty():
		for o in off.targets[0].secondary.options:
			opts.append(str(o.id))
	_check("Meganobz (within 12\", visible) is a choice", MEGA in opts, str(opts))
	_check("Boyz (far away) are not", not BOYZ in opts, str(opts))
	_check("an entry for the phase_start window is queued", not D.phase_start_entries(PHASE_SHOOTING, []).is_empty())
	var meg_model: Dictionary = _unit(MEGA).models[0]
	var obs: Dictionary = _unit(INTER).models[0]
	var det0 := float(TM.detection_range_inches_for(meg_model, _unit(MEGA), obs))
	var r2 := _use(1, D.RULE_AUSPEX, SPEEDER, {"secondary_id": MEGA})
	_check("used", r2.get("success", false), str(r2))
	var det1 := float(TM.detection_range_inches_for(meg_model, _unit(MEGA), obs))
	_check("spotted: +3\" detection range", absf(det1 - det0 - 3.0) < 0.01, "%.1f -> %.1f" % [det0, det1])
	_check("once per phase: not offered again", _offer(1, "phase_start", ctx, D.RULE_AUSPEX).is_empty())
	GS.state.meta["active_player"] = 2
	_check("expires at the end of the turn", D.detection_range_bonus(_unit(MEGA)) == 0.0)
	GS.state.meta["active_player"] = 1
	_enter(PHASE_MOVEMENT)
	_check("not offered in the Movement phase", _offer(1, "phase_start", {"phase": "movement"}, D.RULE_AUSPEX).is_empty())
	_restore()


func _section_gauntlet() -> void:
	print("\n-- G. Gauntlet Task Force --")
	_restore()
	_enter(PHASE_SHOOTING)
	var ctx := {"phase": "shooting", "unit_id": IMPULSOR, "hit_unit_ids": [DREAD, GRETS], "window_id": "unit_has_shot"}
	var off := _offer(1, "unit_has_shot", ctx, D.RULE_COMBINED)
	_check("COMBINED DEPLOYMENT offered when the Impulsor (TRANSPORT) has shot", not off.is_empty())
	_check("not when the Intercessors have shot", _offer(1, "unit_has_shot", {"phase": "shooting", "unit_id": INTER, "hit_unit_ids": [GRETS]}, D.RULE_COMBINED).is_empty())
	_check("not when nothing was hit", _offer(1, "unit_has_shot", {"phase": "shooting", "unit_id": IMPULSOR, "hit_unit_ids": []}, D.RULE_COMBINED).is_empty())
	var r := _use(1, D.RULE_COMBINED, IMPULSOR, {"secondary_id": DREAD, "hit_unit_ids": [DREAD, GRETS]})
	_check("used: the Deff Dread is assailed", r.get("success", false) and str(_flags(DREAD).get(D.F_ASSAILED, "")) == D.turn_stamp(), str(r))
	_check("a unit not hit cannot be picked", not _use(1, D.RULE_COMBINED, IMPULSOR, {"secondary_id": BOYZ, "hit_unit_ids": [DREAD]}).get("success", false))
	_check("Intercessors that did NOT disembark: no [SUSTAINED HITS 1]", int(_mods(INTER, DREAD, false).get("sustained", 0)) == 0)
	_flags(INTER)["disembarked_this_turn"] = true
	var m := _mods(INTER, DREAD, false)
	_check("Intercessors that disembarked this turn: [SUSTAINED HITS 1] vs the assailed Deff Dread", int(m.get("sustained", 0)) == 1 and "Combined Deployment (Gauntlet Task Force)" in _src_names(m), str(m))
	_check("... melee too", int(_mods(INTER, DREAD, true).get("sustained", 0)) == 1)
	_check("... not vs a unit that is not assailed", int(_mods(INTER, GRETS, false).get("sustained", 0)) == 0)
	GS.state.meta["active_player"] = 2
	_check("assailed ends with the turn", int(_mods(INTER, DREAD, false).get("sustained", 0)) == 0)
	GS.state.meta["active_player"] = 1
	_set_dets(["Gladius Task Force"])
	_check("without Gauntlet: no card", _offer(1, "unit_has_shot", ctx, D.RULE_COMBINED).is_empty())
	_restore()
	# Linebreaker Onslaught.
	_check("Linebreaker: no charge re-roll before disembarking", D.charge_reroll_source(_unit(TECH)) == "")
	_check("... no snap block", D.snap_block_reason(_unit(TECH)) == "")
	_flags(TECH)["disembarked_this_turn"] = true
	_check("disembarked this turn: re-roll charge rolls", D.charge_reroll_source(_unit(TECH)) == "Linebreaker Onslaught")
	_check("FactionAbilityManager charge re-roll gate sees it", root.get_node("FactionAbilityManager").unit_has_detachment_charge_reroll(_unit(TECH)))
	_check("disembarked: enemy units cannot snap-shoot it", D.snap_block_reason(_unit(TECH)) != "")
	_restore()
	# Damocles-class Uplink — phase_start card of your Movement phase.
	_enter(PHASE_MOVEMENT)
	var mctx := {"phase": "movement", "window_id": "phase_start"}
	var doff := _offer(1, "phase_start", mctx, D.RULE_DAMOCLES)
	_check("DAMOCLES-CLASS UPLINK offered (Captain in Phobos Armour embarked in the Rhino)", not doff.is_empty())
	var tids: Array = []
	if not doff.is_empty():
		for t in doff.targets:
			tids.append(str(t.unit_id))
	_check("the Intercessors (INFANTRY within 6\" of the Rhino) are a choice", INTER in tids, str(tids))
	_check("the Land Speeder (not INFANTRY) is not", not SPEEDER in tids)
	_check("each choice carries the three doctrines", not doff.is_empty() and (doff.targets[0].variants as Array).size() == 3)
	_fac(1)["sw11e_doctrine"] = "devastator"
	var r2 := _use(1, D.RULE_DAMOCLES, INTER, {"variant_id": "assault"})
	_check("used: assault doctrine for the Intercessors", r2.get("success", false) and C.doctrine_active(_unit(INTER), "assault"), str(r2))
	_check("... it replaces the army doctrine for them (only one doctrine)", not C.doctrine_active(_unit(INTER), "devastator"))
	_check("... other units keep the army doctrine", C.doctrine_active(_unit(REDEMPTOR), "devastator"))
	_check("once per phase", _offer(1, "phase_start", mctx, D.RULE_DAMOCLES).is_empty())
	GS.state.meta["battle_round"] = 3
	_enter(PHASE_COMMAND)
	_check("expires at the start of P1's next Command phase", not C.doctrine_active(_unit(INTER), "assault") and not _flags(INTER).has("sw11e_doctrine"))
	_restore()
	_unit(CAP_PHOBOS).erase("embarked_in")
	_enter(PHASE_MOVEMENT)
	_check("not embarked: no card", _offer(1, "phase_start", {"phase": "movement"}, D.RULE_DAMOCLES).is_empty())
	_restore()


func _section_shadow() -> void:
	print("\n-- H. Phobos Shadow Force --")
	_restore()
	_enter(PHASE_SHOOTING)
	var ctx := {"phase": "shooting", "unit_id": INFIL, "hit_unit_ids": [GRETS]}
	var off := _offer(1, "unit_has_shot", ctx, D.RULE_SHADOW)
	_check("SHADOW MASTERS offered when the Infiltrators (PHOBOS) have shot", not off.is_empty())
	_check("... for the Scout Squad (SCOUT SQUAD)", not _offer(1, "unit_has_shot", {"phase": "shooting", "unit_id": SCOUTS}, D.RULE_SHADOW).is_empty())
	_check("not for the Intercessors", _offer(1, "unit_has_shot", {"phase": "shooting", "unit_id": INTER}, D.RULE_SHADOW).is_empty())
	_check("two choices for an unengaged unit", not off.is_empty() and (off.targets[0].variants as Array).size() == 2)
	# Choice 1: those attacks do not prevent it from being hidden.
	_ruin_around(7.0, 38.0, 19.0, 44.0)
	var idx: int = GS.get_battle_round() * 2
	_flags(INFIL)["last_shot_idx"] = idx
	_check("after shooting, the Infiltrators in the ruin are NOT hidden", not D.unit_is_hidden(_unit(INFIL)))
	var r := _use(1, D.RULE_SHADOW, INFIL, {"variant_id": "hidden"})
	_check("stay-hidden used", r.get("success", false), str(r))
	_check("... the Infiltrators are hidden again", D.unit_is_hidden(_unit(INFIL)))
	_check("Game Log line", _game_log_contains("SHADOW MASTERS"))
	# Choice 2: normal move of up to D6" (no charge).
	_restore()
	_enter(PHASE_SHOOTING)
	var r2 := _use(1, D.RULE_SHADOW, INFIL, {"variant_id": "move"})
	_check("move used: reactive normal move follow-up of up to D6\"", r2.get("success", false) and str(r2.get("followup", {}).get("type", "")) == "reactive_normal_move"
		and float(r2.followup.max_inches) >= 1.0 and float(r2.followup.max_inches) <= 6.0, str(r2))
	_check("... not eligible to declare a charge this turn", bool(_flags(INFIL).get("cannot_charge", false)))
	# Engaged: no move choice.
	_restore()
	_enter(PHASE_SHOOTING)
	_move_to(INFIL, 9.0, 32.0)
	var eoff := _offer(1, "unit_has_shot", {"phase": "shooting", "unit_id": INFIL}, D.RULE_SHADOW)
	_check("an engaged unit: only the stay-hidden choice", not eoff.is_empty() and (eoff.targets[0].variants as Array).size() == 1, str(eoff.get("targets", [])))
	_check("... the move is refused", not _use(1, D.RULE_SHADOW, INFIL, {"variant_id": "move"}).get("success", false))
	_restore()
	# Execute and Redeploy.
	_enter(PHASE_SHOOTING)
	var ectx := {"phase": "shooting", "unit_id": LT_COMBI}
	_check("EXECUTE AND REDEPLOY offered after the bearer has shot", not _offer(1, "unit_has_shot", ectx, D.RULE_EXECUTE).is_empty())
	var r3 := _use(1, D.RULE_EXECUTE, LT_COMBI)
	_check("used: a 6\" normal move follow-up, no charge", r3.get("success", false) and float(r3.get("followup", {}).get("max_inches", 0)) == 6.0 and bool(_flags(LT_COMBI).get("cannot_charge", false)), str(r3))
	_check("once per phase", _offer(1, "unit_has_shot", ectx, D.RULE_EXECUTE).is_empty())
	_check("not for a unit without it", _offer(1, "unit_has_shot", {"phase": "shooting", "unit_id": INFIL}, D.RULE_EXECUTE).is_empty())
	_restore()
	_enter(PHASE_SHOOTING)
	_move_to(LT_COMBI, 12.2, 30.9)
	_check("the Lieutenant with Combi-weapon is engaged with the Boyz", C.is_engaged(LT_COMBI))
	_check("engaged: not offered", _offer(1, "unit_has_shot", ectx, D.RULE_EXECUTE).is_empty())
	_restore()
	# Venator Omni-auspex — vs a hidden unit.
	_ruin_around(16.0, 33.0, 28.0, 38.0)  # around the Gretchin (INFANTRY, never shot)
	_check("the Gretchin are hidden in the ruin", D.unit_is_hidden(_unit(GRETS)))
	var vm := _mods(LT_PHOBOS, GRETS, false)
	_check("Venator: re-roll wound rolls of 1 vs a hidden unit", str(vm.get("wound_reroll", "")) == "ones" and "Venator Omni-auspex" in _src_names(vm), str(vm))
	_fac(1)["sw11e_doctrine"] = "assault"
	var vm2 := _mods(LT_PHOBOS, GRETS, true)
	_check("Venator + assault doctrine: re-roll wound rolls of 1-2", str(vm2.get("wound_reroll", "")) == "ones_twos", str(vm2))
	var bits: int = RE.ork11e_ab_wound_bits(0, [], vm2)
	_check("... folded into the REROLL_ONES_TWOS wound modifier", (bits & RE.WoundModifier.REROLL_ONES_TWOS) != 0)
	_fac(1)["sw11e_doctrine"] = ""
	_check("vs a unit that is not hidden (Boyz): nothing", str(_mods(LT_PHOBOS, BOYZ, false).get("wound_reroll", "")) == "")
	_restore()


func _section_tacticus() -> void:
	print("\n-- I. Tacticus Attack Force --")
	_restore()
	_check("Wrath of the Chapter: Intercessors (TACTICUS) re-roll advance rolls", D.free_advance_reroll_source(_unit(INTER)) == "Wrath of the Chapter")
	_check("not the Infiltrators (PHOBOS)", D.free_advance_reroll_source(_unit(INFIL)) == "")
	var got := false
	for s in range(1, 30):
		_restore()
		var mv = _enter_clear(PHASE_MOVEMENT)
		var r: Dictionary = mv.execute_action({"type": "BEGIN_ADVANCE", "actor_unit_id": INTER, "player": 1, "payload": {"rng_seed": 500 + s}})
		if bool(r.get("awaiting_reroll", false)):
			got = str(mv._reroll_pending_data.get("free_ability", "")) == "Wrath of the Chapter"
			mv.execute_action({"type": "DECLINE_COMMAND_REROLL", "player": 1})
			if got:
				break  # (a roll of 6 offers only the Command Re-roll — try the next seed)
	_check("real advance: the free Wrath of the Chapter re-roll is offered", got)
	_restore()
	_set_dets(["Gladius Task Force"])
	_check("without Tacticus: none", D.free_advance_reroll_source(_unit(INTER)) == "")
	_restore()
	# Martial Paragon.
	_enter(PHASE_FIGHT)
	_check("Martial Paragon: the Judiciar re-rolls one hit roll (melee)", D.reroll_one_source(_unit(JUDICIAR), "hit", true) == "Martial Paragon")
	_check("... one wound roll (ranged)", D.reroll_one_source(_unit(JUDICIAR), "wound", false) == "Martial Paragon")
	_check("not another unit (the Lieutenant)", D.reroll_one_source(_unit(LT), "hit", true) == "")
	_move_to(JUDICIAR, 12.2, 30.9)
	var found := false
	for s in range(1, 40):
		D.reset_reroll_ledger()
		_melee(JUDICIAR, BOYZ, "Executioner Relic Blade", 700 + s)
		if not D._reroll_one_used.is_empty():
			found = true
			break
	_check("real melee: Martial Paragon re-rolls a failed die (spent in the resolver)", found)
	_restore()
	# Spearpoint War Leader.
	_check("Spearpoint War Leader: the Apothecary has Scouts", GS.unit_has_scout(APOTH))
	_check("... 6\"", absf(GS.get_scout_distance(APOTH) - 6.0) < 0.01, str(GS.get_scout_distance(APOTH)))
	_unit(APOTH)["attached_to"] = INTER
	_unit(INTER)["attachment_data"] = {"attached_characters": [APOTH]}
	_check("leading the Intercessors: the Attached unit has Scouts 6\"", GS.unit_has_scout(INTER) and absf(GS.get_scout_distance(INTER) - 6.0) < 0.01)
	_restore()
	_set_dets(["Gladius Task Force"])
	_check("without Tacticus: no Scouts", not GS.unit_has_scout(APOTH))
	_restore()


func _section_shock() -> void:
	print("\n-- J. Phobos Shock Force --")
	_restore()
	_ruin_around(7.0, 38.0, 19.0, 44.0)
	_check("the Infiltrators (not shot) are hidden in the ruin", D.unit_is_hidden(_unit(INFIL)))
	var mv = _enter_clear(PHASE_MOVEMENT)
	var r: Dictionary = mv.execute_action({"type": "END_MOVEMENT", "player": 1})
	_check("END_MOVEMENT accepted", r.get("success", false), str(r.get("error", "")))
	_check("Vanguard Ambushers: hidden PHOBOS Infiltrators marked at the end of the Movement phase", str(_flags(INFIL).get(D.F_AMBUSH, "")) == D.turn_stamp(), str(_flags(INFIL)))
	_check("not the Intercessors (not PHOBOS / not hidden)", not _flags(INTER).has(D.F_AMBUSH))
	_check("not the Librarian in Phobos (not hidden)", not _flags(LIB_PHOBOS).has(D.F_AMBUSH))
	var m := _mods(INFIL, GRETS, false)
	_check("their attacks re-roll wound rolls of 1", str(m.get("wound_reroll", "")) == "ones" and "Vanguard Ambushers (Phobos Shock Force)" in _src_names(m), str(m))
	_check("Game Log line", _game_log_contains("Vanguard Ambushers"))
	GS.state.meta["active_player"] = 2
	_check("until the end of the turn", str(_mods(INFIL, GRETS, false).get("wound_reroll", "")) == "")
	GS.state.meta["active_player"] = 1
	_restore()
	_ruin_around(7.0, 38.0, 19.0, 44.0)
	_set_dets(["Gladius Task Force"])
	D.on_movement_phase_end(1)
	_check("without Shock Force: nothing", not _flags(INFIL).has(D.F_AMBUSH))
	_restore()
	# Seal of Shrouding — snap shooting.
	_check("Seal of Shrouding: snap block on the bearer's unit", D.snap_block_reason(_unit(LIB_PHOBOS)) == "Seal of Shrouding")
	_move_to(LIB_PHOBOS, 30.0, 36.0)
	var board: Dictionary = GS.create_snapshot()
	var tg: Array = RE.snap_shooting_targets_11e(MEGA, board).map(func(t): return str(t.unit_id))
	_check("Meganobz snap-shooting targets exclude the Librarian in Phobos Armour", not LIB_PHOBOS in tg, str(tg))
	_check("... but include other units in range", not tg.is_empty(), str(tg))
	_set_dets(["Gladius Task Force"])
	board = GS.create_snapshot()
	tg = RE.snap_shooting_targets_11e(MEGA, board).map(func(t): return str(t.unit_id))
	_check("without Shock Force: the Librarian can be snap-shot", LIB_PHOBOS in tg, str(tg))
	_restore()


func _section_ai() -> void:
	print("\n-- K. AI --")
	_restore()
	var AID = load("res://scripts/AIDecisionMaker.gd")
	_enter(PHASE_FIGHT)
	var fctx := {"phase": "fight", "unit_id": ANCIENT}
	var fo := _offers(1, "unit_selected_to_fight", fctx)
	var pick: Dictionary = D.ai_decide(1, "unit_selected_to_fight", fo, fctx)
	_check("AI: Ancient Exhortation when the engaged Ancient fights", str(pick.get("stratagem_id", "")) == D.RULE_EXHORTATION, str(pick))
	_restore()
	_enter(PHASE_SHOOTING)
	var sctx := {"phase": "shooting", "unit_id": IMPULSOR, "hit_unit_ids": [DREAD, GRETS]}
	var so := _offers(1, "unit_has_shot", sctx)
	var p2: Dictionary = D.ai_decide(1, "unit_has_shot", so, sctx)
	_check("AI: Combined Deployment on the most expensive unit hit (the Deff Dread)", str(p2.get("stratagem_id", "")) == D.RULE_COMBINED and str(p2.get("context", {}).get("secondary_id", "")) == DREAD, str(p2))
	var used: Dictionary = _use(1, str(p2.stratagem_id), str(p2.target_unit_id), p2.context)
	_check("AI's choice executes", used.get("success", false), str(used))
	var octx := {"phase": "shooting", "window_id": "phase_start"}
	var p3: Dictionary = D.ai_decide(1, "phase_start", _offers(1, "phase_start", octx), octx)
	_check("AI: Auspex Triangulation Shrines picks a target", str(p3.get("stratagem_id", "")) == D.RULE_AUSPEX and str(p3.get("context", {}).get("secondary_id", "")) != "", str(p3))
	var ictx := {"phase": "shooting", "unit_id": INFIL}
	var p4: Dictionary = D.ai_decide(1, "unit_has_shot", _offers(1, "unit_has_shot", ictx), ictx)
	_check("AI: Shadow Masters declined in the open (cannot be hidden)", str(p4.get("stratagem_id", "")) != D.RULE_SHADOW, str(p4))
	_ruin_around(7.0, 38.0, 19.0, 44.0)
	var p5: Dictionary = D.ai_decide(1, "unit_has_shot", _offers(1, "unit_has_shot", ictx), ictx)
	_check("AI: Shadow Masters 'stay hidden' inside dense terrain", str(p5.get("stratagem_id", "")) == D.RULE_SHADOW and str(p5.get("context", {}).get("variant_id", "")) == "hidden", str(p5))
	_restore()
	_enter(PHASE_MOVEMENT)
	var mctx := {"phase": "movement", "window_id": "phase_start"}
	var p6: Dictionary = D.ai_decide(1, "phase_start", _offers(1, "phase_start", mctx), mctx)
	_check("AI: Damocles-class Uplink picks a unit and a doctrine", str(p6.get("stratagem_id", "")) == D.RULE_DAMOCLES and str(p6.get("context", {}).get("variant_id", "")) in C.DOCTRINES, str(p6))
	# The full AI window path (AIDecisionMaker) returns the codex pick too.
	var p7: Dictionary = AID.decide_window_stratagem(1, "phase_start", _offers(1, "phase_start", mctx), mctx)
	_check("AIDecisionMaker.decide_window_stratagem returns the codex pick", str(p7.get("stratagem_id", "")) == D.RULE_DAMOCLES, str(p7))
	_restore()
