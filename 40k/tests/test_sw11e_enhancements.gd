extends SceneTree

# Codex: Space Marines (11e) — the 8 Space Wolves ENHANCEMENTS (WP-S2,
# SWEnhancements11e.gd). Fixture tests/saves/sw11e_s2_wolves_active.w40ksave:
# Howlmaw on the Wolf Priest, Skjald's Foretelling on the Wolf Guard Battle
# Leader, Preyslayer on Arjac Rockfist, A Giant Amongst Giants on Ragnar.
#   A. army validation — bearer restrictions + detachment gating (data-driven)
#   B. A Giant Amongst Giants (+2 W list build, +1 S melee for the model)
#   C. Preyslayer (charge re-roll, Attached unit)
#   D. Wolf-Touched (WULFEN keyword, +2" M, leads Wulfen INFANTRY)
#   E. Skjald's Foretelling (melee [LANCE] — real melee A/B)
#   F. Howlmaw (fight_phase_start card, battle-shock at -1, once per turn, AI)
#   G. Grimnar's Mark (HI / Rapid Ingress -1CP regardless of other uses)
#   H. Hunter's Guile / Chariots of the Storm (redeploy table, engine/AI side)
#   I. every runtime effect needs the enhancement's detachment
#
# Usage: godot --headless --path 40k --script tests/test_sw11e_enhancements.gd

const FIXTURE := "sw11e_s2_wolves_active"
const PHASE_COMMAND := 6
const PHASE_MOVEMENT := 7
const PHASE_CHARGE := 9
const PHASE_FIGHT := 10
const PX := 40.0

const LOGAN := "U_LOGAN_GRIMNAR_A"
const GH := "U_GREY_HUNTERS_A"
const BC := "U_BLOOD_CLAWS_A"
const TWC := "U_THUNDERWOLF_CAVALRY_A"
const WULFEN := "U_WULFEN_A"
const WGBL := "U_WOLF_GUARD_BATTLE_LEADER_A"
const ARJAC := "U_ARJAC_ROCKFIST_A"
const PRIEST := "U_WOLF_PRIEST_A"
const RAGNAR := "U_RAGNAR_BLACKMANE_A"
const VEN := "U_VENERABLE_DREADNOUGHT_A"
const BOYZ := "U_BOYZ_B"
const MEGA := "U_MEGANOBZ_A"
const DREAD := "U_DEFF_DREAD_A"
const GRETS := "U_GRETCHIN_C"

var passed := 0
var failed := 0
var GS = null
var PM = null
var RE = null
var SM = null
var E = null
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


func _cp(p: int) -> int:
	return int(GS.state.players[str(p)].cp)


func _fac(p: int) -> Dictionary:
	return GS.state.factions[str(p)]


func _set_dets(p: int, dets: Array) -> void:
	_fac(p)["detachment"] = dets[0]
	_fac(p)["detachments"] = dets


func _set_enh(uid: String, names: Array) -> void:
	_unit(uid).meta["enhancements"] = names


func _remember() -> void:
	for uid in GS.state.units:
		var arr: Array = []
		for m in GS.state.units[uid].models:
			arr.append(m.get("position").duplicate() if m.get("position") is Dictionary else m.get("position"))
		_base[uid] = {"pos": arr, "enh": GS.state.units[uid].meta.get("enhancements", []).duplicate(), "kw": GS.state.units[uid].meta.get("keywords", []).duplicate()}


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
			if str(k).begins_with("sw11e_listbuild_") or str(k) == "sw11e_transhuman_round":
				keep[k] = u.flags[k]
		u["flags"] = keep
		u["status"] = GS.UnitStatus.DEPLOYED
		u.erase("attached_to")
		if u.has("attachment_data"):
			u["attachment_data"] = {"attached_characters": []}
		u.meta["enhancements"] = b.get("enh", []).duplicate()
		u.meta["keywords"] = b.get("kw", []).duplicate()
	GS.state.meta["active_player"] = 1
	GS.state.meta["battle_round"] = 2
	for p in ["1", "2"]:
		for k in _fac(int(p)).keys():
			if str(k).begins_with("sw11e_"):
				_fac(int(p)).erase(k)
	_set_dets(1, ["Saga of the Great Wolf", "Champions of Fenris"])
	SM._usage_history = {"1": [], "2": []}


func _enter(phase_id: int):
	PM.transition_to_phase(phase_id)
	var phase = PM.get_current_phase_instance()
	if phase.phase_completed.is_connected(PM._on_phase_completed):
		phase.phase_completed.disconnect(PM._on_phase_completed)
	return phase


func _move_to(uid: String, x: float, y: float) -> void:
	var c := Vector2.ZERO
	var n := 0
	for m in GS.state.units[uid].models:
		c += Vector2(float(m.position.x), float(m.position.y))
		n += 1
	var d: Vector2 = Vector2(x, y) * PX - c / float(n)
	for m in GS.state.units[uid].models:
		m["position"] = {"x": float(m.position.x) + d.x, "y": float(m.position.y) + d.y}


func _mods(atk: String, tgt: String, melee: bool) -> Dictionary:
	return RE.ork11e_ab_mods(_unit(atk), _unit(tgt), {"name": "test"}, melee, GS.state)


func _game_log_contains(needle: String) -> bool:
	for e in root.get_node("GameEventLog").get_all_entries():
		if str(e.get("text", "")).contains(needle):
			return true
	return false


func _army(dets: Array, units: Dictionary) -> Dictionary:
	return {"faction": {"name": "Space Wolves", "points": 2000, "detachment": dets[0], "detachments": dets}, "units": units}


func _au(name: String, kws: Array, enh: Array) -> Dictionary:
	return {"meta": {"name": name, "keywords": kws, "points": 100, "enhancements": enh, "stats": {"wounds": 4}}, "models": [{"id": "m1", "wounds": 4, "current_wounds": 4}]}


# ---------------------------------------------------------------------------
func _run() -> void:
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	SM = root.get_node("StratagemManager")
	E = load("res://scripts/codex/space_wolves/SWEnhancements11e.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	GS.set_edition(11)
	print("\n=== test_sw11e_enhancements ===\n")
	_check("fixture %s loads" % FIXTURE, _stage_fixture())
	GS.set_edition(11)
	root.get_node("SettingsService").set("auto_allocate_wounds", true)
	_enter(PHASE_COMMAND)
	_remember()
	_section_validation()
	_section_giant()
	_section_preyslayer()
	_section_wolf_touched()
	_section_skjald()
	_section_howlmaw()
	_section_grimnars_mark()
	_section_redeploy()
	_section_gating()


# ---------------------------------------------------------------------------
func _section_validation() -> void:
	print("\n-- A. army validation --")
	var ER = load("res://scripts/codex/EnhancementRules11e.gd")
	var wp_kw := ["ADEPTUS ASTARTES", "SPACE WOLVES", "CHARACTER", "INFANTRY", "WOLF PRIEST"]
	var ok: Dictionary = ER.validate_army(_army(["Saga of the Great Wolf"], {"A": _au("Wolf Priest", wp_kw, ["Howlmaw"])}))
	_check("Howlmaw on a Wolf Priest (Saga of the Great Wolf): clean", ok.warnings.is_empty(), str(ok.warnings))
	var bad: Dictionary = ER.validate_army(_army(["Saga of the Great Wolf"], {"A": _au("Iron Priest", ["ADEPTUS ASTARTES", "SPACE WOLVES", "CHARACTER", "INFANTRY", "IRON PRIEST"], ["Howlmaw"])}))
	_check("Howlmaw on an Iron Priest: bearer warning", not bad.warnings.is_empty(), str(bad.warnings))
	var wgbl_kw := ["ADEPTUS ASTARTES", "SPACE WOLVES", "CHARACTER", "INFANTRY", "WOLF GUARD BATTLE LEADER"]
	var gm: Dictionary = ER.validate_army(_army(["Saga of the Great Wolf"], {"A": _au("Wolf Guard Battle Leader", wgbl_kw, ["Grimnar's Mark"])}))
	_check("Grimnar's Mark on a Battle Leader (not a Terminator Captain): warning", not gm.warnings.is_empty(), str(gm.warnings))
	var tc: Dictionary = ER.validate_army(_army(["Saga of the Great Wolf"], {"A": _au("Captain in Terminator Armour", ["ADEPTUS ASTARTES", "CHARACTER", "INFANTRY", "CAPTAIN", "TERMINATOR"], ["Grimnar's Mark"])}))
	_check("Grimnar's Mark on a Terminator Captain: clean", tc.warnings.is_empty(), str(tc.warnings))
	var det: Dictionary = ER.validate_army(_army(["Champions of Fenris"], {"A": _au("Wolf Priest", wp_kw, ["Howlmaw"])}))
	_check("Howlmaw without Saga of the Great Wolf: not a detachment enhancement", not det.warnings.is_empty(), str(det.warnings))
	var giant: Dictionary = ER.validate_army(_army(["Champions of Fenris"], {"A": _au("Wolf Guard Battle Leader", wgbl_kw, ["A Giant Amongst Giants"])}))
	_check("A Giant Amongst Giants on an ADEPTUS ASTARTES INFANTRY character: clean", giant.warnings.is_empty(), str(giant.warnings))
	var epic: Dictionary = ER.validate_army(_army(["Champions of Fenris"], {"A": _au("Ragnar Blackmane", wgbl_kw + ["EPIC HERO"], ["Preyslayer"])}))
	_check("an EPIC HERO cannot take an enhancement", not epic.warnings.is_empty(), str(epic.warnings))
	var wt: Dictionary = ER.validate_army(_army(["Saga of the Beastslayer"], {"A": _au("Wolf Guard Battle Leader", wgbl_kw, ["Wolf-Touched"])}))
	_check("Wolf-Touched on an ADEPTUS ASTARTES character (Beastslayer): clean", wt.warnings.is_empty(), str(wt.warnings))
	var sk: Dictionary = ER.validate_army(_army(["Saga of the Great Wolf"], {"A": _au("Wolf Guard Battle Leader", wgbl_kw, ["Skjald's Foretelling"])}))
	_check("Skjald's Foretelling on a Wolf Guard Battle Leader: clean", sk.warnings.is_empty(), str(sk.warnings))


func _section_giant() -> void:
	print("\n-- B. A Giant Amongst Giants --")
	_restore()
	var base_w := 0
	var army = JSON.parse_string(FileAccess.get_file_as_string("res://armies/sw11e_codex_test.json"))
	base_w = int(army.units[RAGNAR].models[0].get("wounds", 0))
	_check("list build: Ragnar's model +2 W (%d -> %d)" % [base_w, int(_unit(RAGNAR).models[0].wounds)], int(_unit(RAGNAR).models[0].wounds) == base_w + 2)
	_check("list build: full wounds", int(_unit(RAGNAR).models[0].current_wounds) == base_w + 2)
	var u := {"meta": {"name": "x", "enhancements": ["A Giant Amongst Giants"], "stats": {"wounds": 4}}, "models": [{"id": "m", "wounds": 4, "current_wounds": 4}], "flags": {}}
	E.apply_list_build("X", u, ["Champions of Fenris"])
	E.apply_list_build("X", u, ["Champions of Fenris"])
	_check("list build is idempotent (+2 once)", int(u.models[0].wounds) == 6, str(u.models[0].wounds))
	var u2 := {"meta": {"name": "x", "enhancements": ["A Giant Amongst Giants"], "stats": {"wounds": 4}}, "models": [{"id": "m", "wounds": 4, "current_wounds": 4}], "flags": {}}
	E.apply_list_build("Y", u2, ["Saga of the Great Wolf"])
	_check("list build: not applied without Champions of Fenris", int(u2.models[0].wounds) == 4)
	var m := _mods(RAGNAR, BOYZ, true)
	_check("Ragnar's melee attacks +1 S", int(m.get("strength", 0)) == 1, str(m))
	_check("not his ranged attacks", int(_mods(RAGNAR, BOYZ, false).get("strength", 0)) == 0)
	_check("not another unit's melee attacks", int(_mods(GH, BOYZ, true).get("strength", 0)) == 0)
	# Attached to the Blood Claws: only HIS attacks (his own unit id).
	_unit(RAGNAR)["attached_to"] = BC
	_unit(BC)["attachment_data"] = {"attached_characters": [RAGNAR]}
	# Ragnar leading Blood Claws also gives the whole unit War Howl (+1 S,
	# WP-S4), so the enhancement's +1 S shows as the difference: the Blood
	# Claws get War Howl only, Ragnar War Howl + A Giant Amongst Giants.
	_check("attached: the Blood Claws' own melee attacks get no enhancement +1 S (War Howl's +1 only)", int(_mods(BC, BOYZ, true).get("strength", 0)) == 1, str(_mods(BC, BOYZ, true)))
	_check("attached: Ragnar's still do (War Howl +1, enhancement +1)", int(_mods(RAGNAR, BOYZ, true).get("strength", 0)) == 2, str(_mods(RAGNAR, BOYZ, true)))
	_restore()


func _section_preyslayer() -> void:
	print("\n-- C. Preyslayer --")
	_restore()
	var FAM = root.get_node("FactionAbilityManager")
	_check("Arjac (bearer) can re-roll charge rolls", E.charge_reroll_source(_unit(ARJAC)) == "Preyslayer")
	_check("FactionAbilityManager charge re-roll gate sees it", FAM.unit_has_detachment_charge_reroll(_unit(ARJAC)))
	var ch = _enter(PHASE_CHARGE)
	_check("ChargePhase names the re-roll source Preyslayer", str(ch._get_charge_reroll_ability_name(ARJAC)) == "Preyslayer", str(ch._get_charge_reroll_ability_name(ARJAC)))
	_check("Grey Hunters: no", E.charge_reroll_source(_unit(GH)) == "")
	_unit(ARJAC)["attached_to"] = GH
	_unit(GH)["attachment_data"] = {"attached_characters": [ARJAC]}
	_check("Arjac leading the Grey Hunters: the unit re-rolls charges", E.charge_reroll_source(_unit(GH)) == "Preyslayer")
	_restore()


func _section_wolf_touched() -> void:
	print("\n-- D. Wolf-Touched --")
	_restore()
	_set_dets(1, ["Saga of the Beastslayer", "Champions of Fenris"])
	_set_enh(WGBL, ["Wolf-Touched"])
	var u: Dictionary = _unit(WGBL)
	E.apply_list_build(WGBL, u, ["Saga of the Beastslayer"])
	_check("list build: the bearer has the WULFEN keyword", "WULFEN" in u.meta.keywords)
	var MV = load("res://phases/MovementPhase.gd").new()
	var base_m := float(u.meta.stats.get("move", u.meta.stats.get("movement", 6)))
	_check("+2\" M for the bearer", E.move_bonus_inches(u) == 2.0)
	var got: float = MV.get_unit_movement(u)
	_check("MovementPhase movement includes +2\" (%.0f -> %.0f)" % [base_m, got], got >= base_m + 2.0 - 0.01, str(got))
	MV.free()
	var cam = root.get_node("CharacterAttachmentManager")
	var r: Dictionary = cam.can_attach(WGBL, WULFEN)
	_check("the bearer can lead the Wulfen (INFANTRY)", r.valid, str(r))
	_check("leader extras: WULFEN", "WULFEN" in cam.get_enhancement_can_lead_extras(u))
	# A WULFEN VEHICLE (Wulfen Dreadnought stand-in) is not a Wulfen INFANTRY unit.
	_unit(VEN).meta.keywords.append("WULFEN")
	var rv: Dictionary = cam.can_attach(WGBL, VEN)
	_check("... but not a WULFEN VEHICLE", not rv.valid, str(rv))
	_unit(VEN).meta.keywords.erase("WULFEN")
	_unit(WGBL)["attached_to"] = WULFEN
	_unit(WULFEN)["attachment_data"] = {"attached_characters": [WGBL]}
	_check("attached: the Wulfen unit has +2\" M", E.move_bonus_inches(_unit(WULFEN)) == 2.0)
	_restore()
	_check("without the enhancement: cannot lead the Wulfen", not cam.can_attach(WGBL, WULFEN).valid)
	_check("without Saga of the Beastslayer: no +2\" M", E.move_bonus_inches(_unit(WGBL)) == 0.0)


func _lance_wounds(seed_val: int) -> Dictionary:
	var board: Dictionary = GS.create_snapshot()
	board.units[WGBL]["flags"]["charged_this_turn"] = true
	var wid := ""
	for w in _unit(WGBL).meta.weapons:
		if str(w.get("type", "")).to_lower() == "melee":
			wid = str(w.name)
			break
	RE.set_test_seed(seed_val)
	var res: Dictionary = RE.resolve_melee_attacks({"type": "FIGHT", "actor_unit_id": WGBL,
		"payload": {"assignments": [{"attacker": WGBL, "target": MEGA, "weapon": wid}]}}, board, RE.RNGService.new(seed_val))
	var lance := false
	for b in res.get("dice", []):
		for e in b.get("modifier_ledger", []):
			if str(e.get("source", "")).contains("LANCE"):
				lance = true
	return {"lance": lance, "weapon": wid}


func _section_skjald() -> void:
	print("\n-- E. Skjald's Foretelling --")
	_restore()
	_check("the bearer's melee attacks have [LANCE]", E.melee_lance_source(_unit(WGBL)) == "Skjald's Foretelling")
	_unit(WGBL)["attached_to"] = GH
	_unit(GH)["attachment_data"] = {"attached_characters": [WGBL]}
	_check("leading the Grey Hunters: the whole unit's melee attacks", E.melee_lance_source(_unit(GH)) == "Skjald's Foretelling")
	_restore()
	_move_to(WGBL, 34.0, 31.0)
	var with_enh := _lance_wounds(9)
	_set_enh(WGBL, [])
	var without := _lance_wounds(9)
	_check("real melee after charging: [LANCE] +1 to wound in the ledger (%s)" % with_enh.weapon, with_enh.lance, str(with_enh))
	_check("without the enhancement (same seed): no [LANCE]", not without.lance, str(without))
	_restore()


func _section_howlmaw() -> void:
	print("\n-- F. Howlmaw --")
	_restore()
	var fight = _enter(PHASE_FIGHT)
	var offers: Array = SM.get_window_offers(1, "fight_phase_start", {})
	var hm: Dictionary = {}
	for o in offers:
		if str(o.get("stratagem_id", "")) == E.RULE_HOWLMAW:
			hm = o
	_check("P1's fight_phase_start offers HOWLMAW (free)", not hm.is_empty() and int(hm.get("cp_cost", 1)) == 0, str(offers.map(func(o): return o.name)))
	var opts: Array = hm.get("targets", [{}])[0].get("secondary", {}).get("options", []).map(func(o): return str(o.id))
	_check("enemy within 6\" of the Wolf Priest: Meganobz", MEGA in opts, str(opts))
	_check("far enemies not offered (Gretchin)", not GRETS in opts)
	_check("not offered in another window", SM.get_window_offers(1, "unit_selected_to_fight", {}).filter(func(o): return str(o.get("stratagem_id", "")) == E.RULE_HOWLMAW).is_empty())
	var cp_before := _cp(1)
	RE.set_test_seed(3)
	var r: Dictionary = SM.use_stratagem(1, E.RULE_HOWLMAW, PRIEST, {"secondary_id": MEGA, "window_id": "fight_phase_start"})
	_check("use: success", r.get("success", false), str(r))
	_check("free (no CP)", _cp(1) == cp_before)
	_check("the message reports the battle-shock roll at -1", str(r.get("message", "")).contains("-1"), str(r.get("message", "")))
	_check("Game Log names Howlmaw", _game_log_contains("HOWLMAW"))
	_check("battle-shocked state matches the roll", bool(_flags(MEGA).get("battle_shocked", false)) == (not bool(r.get("passed", true))), str(r))
	_check("once per turn: not offered again this turn", SM.get_window_offers(1, "fight_phase_start", {}).filter(func(o): return str(o.get("stratagem_id", "")) == E.RULE_HOWLMAW).is_empty())
	# The opponent's turn (either player's Fight phase): a new turn — offered again.
	_flags(MEGA).erase("battle_shocked")
	GS.state.meta["active_player"] = 2
	_enter(PHASE_FIGHT)
	_check("the opponent's Fight phase (a new turn): offered again", not SM.get_window_offers(1, "fight_phase_start", {}).filter(func(o): return str(o.get("stratagem_id", "")) == E.RULE_HOWLMAW).is_empty())
	# AI: synchronous pick.
	var AID = load("res://scripts/AIDecisionMaker.gd")
	var d: Dictionary = AID.decide_window_stratagem(1, "fight_phase_start", SM.get_window_offers(1, "fight_phase_start", {}), {})
	_check("AI uses Howlmaw on the Meganobz", bool(d.get("use", false)) and str(d.get("stratagem_id", "")) == E.RULE_HOWLMAW and str(d.get("context", {}).get("secondary_id", "")) == MEGA, str(d))
	_restore()
	_move_to(MEGA, 34.0, 15.0)
	_enter(PHASE_FIGHT)
	_check("no enemy within 6\": not offered", SM.get_window_offers(1, "fight_phase_start", {}).filter(func(o): return str(o.get("stratagem_id", "")) == E.RULE_HOWLMAW).is_empty())
	_restore()


func _section_grimnars_mark() -> void:
	print("\n-- G. Grimnar's Mark --")
	_restore()
	_set_dets(1, ["Saga of the Great Wolf"])  # isolate from Countercharge
	_set_enh(ARJAC, ["Grimnar's Mark"])
	GS.state.meta["active_player"] = 2
	_enter(PHASE_CHARGE)
	GS.state.players["1"]["cp"] = 4
	_check("HI on the bearer: -1CP (1 -> 0)", SM.preview_cp_cost(1, "heroic_intervention", ARJAC) == 0)
	var r1: Dictionary = SM.use_stratagem(1, "heroic_intervention", GH)
	_check("HI on the Grey Hunters first (1CP)", r1.get("success", false) and _cp(1) == 3, str(r1))
	_check("a second HI this phase on another unit is blocked (15.01)", not SM.can_use_stratagem(1, "heroic_intervention", LOGAN).can_use)
	_check("... but on the bearer it is allowed regardless", SM.can_use_stratagem(1, "heroic_intervention", ARJAC).can_use, str(SM.can_use_stratagem(1, "heroic_intervention", ARJAC)))
	var r2: Dictionary = SM.use_stratagem(1, "heroic_intervention", ARJAC)
	_check("HI on the bearer: success for 0CP", r2.get("success", false) and _cp(1) == 3, "%s cp=%d" % [str(r2), _cp(1)])
	_check("Game Log names Grimnar's Mark", _game_log_contains("Grimnar's Mark"))
	_check("once per battle round, per army: no second discount", SM.preview_cp_cost(1, "heroic_intervention", ARJAC) == 1)
	GS.state.meta["battle_round"] = 3
	_check("next battle round: back", SM.preview_cp_cost(1, "heroic_intervention", ARJAC) == 0)
	_check("Rapid Ingress on the bearer: -1CP too", SM.preview_cp_cost(1, "rapid_ingress", ARJAC) == maxi(0, SM.preview_cp_cost(1, "rapid_ingress", GH) - 1))
	_restore()


func _section_redeploy() -> void:
	print("\n-- H. Hunter's Guile / Chariots of the Storm --")
	_restore()
	var FAM = root.get_node("FactionAbilityManager")
	_set_dets(1, ["Saga of the Beastslayer", "Champions of Fenris"])
	_set_enh(WGBL, ["Hunter's Guile"])
	var entry: Dictionary = FAM.get_redeploy_enhancement(1)
	_check("Hunter's Guile is the redeploy enhancement", str(entry.get("name", "")) == "Hunter's Guile", str(entry))
	var ids: Array = FAM.get_razgit_eligible_units(1).map(func(x): return str(x.unit_id))
	_check("eligible: Blood Claws, Thunderwolf Cavalry, Wulfen", BC in ids and TWC in ids and WULFEN in ids, str(ids))
	_check("not the Grey Hunters / Logan", not GH in ids and not LOGAN in ids)
	_check("GameState redeploy list includes them", BC in GS.get_redeploy_units_for_player(1))
	_restore()
	_set_enh(WGBL, ["Chariots of the Storm"])
	entry = FAM.get_redeploy_enhancement(1)
	_check("Chariots of the Storm is the redeploy enhancement", str(entry.get("name", "")) == "Chariots of the Storm", str(entry))
	ids = FAM.get_razgit_eligible_units(1).map(func(x): return str(x.unit_id))
	_check("eligible: every ADEPTUS ASTARTES unit (Grey Hunters, Logan, Venerable Dreadnought)", GH in ids and LOGAN in ids and VEN in ids, str(ids))
	_check("not the Orks", not BOYZ in ids)
	_set_dets(1, ["Champions of Fenris"])
	_check("without Saga of the Great Wolf: no redeploy enhancement", FAM.get_redeploy_enhancement(1).is_empty())
	_restore()


func _section_gating() -> void:
	print("\n-- I. detachment gating --")
	_restore()
	_set_dets(1, ["Saga of the Great Wolf"])
	_check("Preyslayer without Champions of Fenris: no re-roll", E.charge_reroll_source(_unit(ARJAC)) == "")
	_check("A Giant Amongst Giants without Champions: no +1 S", int(_mods(RAGNAR, BOYZ, true).get("strength", 0)) == 0)
	_set_dets(1, ["Champions of Fenris"])
	_check("Skjald's Foretelling without Saga of the Great Wolf: no [LANCE]", E.melee_lance_source(_unit(WGBL)) == "")
	_enter(PHASE_FIGHT)
	_check("Howlmaw without Saga of the Great Wolf: not offered", SM.get_window_offers(1, "fight_phase_start", {}).filter(func(o): return str(o.get("stratagem_id", "")) == E.RULE_HOWLMAW).is_empty())
	GS.set_edition(10)
	_set_dets(1, ["Saga of the Great Wolf", "Champions of Fenris"])
	_check("edition 10: nothing", E.charge_reroll_source(_unit(ARJAC)) == "" and E.melee_lance_source(_unit(WGBL)) == "")
	GS.set_edition(11)
	_restore()
