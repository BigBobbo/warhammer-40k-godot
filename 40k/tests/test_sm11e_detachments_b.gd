extends SceneTree

# Codex: Space Marines (11e) — generic detachments group B (WP-M2b,
# scripts/codex/space_marines/SMDetachmentsB.gd): the detachment rules and
# every enhancement of Terminator Storm Force, Assault Brethren, Gravis
# Linebreaker Force, Devastator Brethren, Gravis Siege Force, Tactical
# Brethren, Ironclad Champions and Tacticus Firestorm Force.
# Fixture tests/saves/sm11e_m2b_marines_active.w40ksave
# (tests/helpers/gen_sm11e_m2b_fixtures.gd): P1 Space Marines (faction Space
# Marines, all eight detachments) vs P2 Orks, round 2, P1's Command phase.
#
# Usage: godot --headless --path 40k --script tests/test_sm11e_detachments_b.gd

const FIXTURE := "sm11e_m2b_marines_active"
const PHASE_COMMAND := 6
const PHASE_MOVEMENT := 7
const PHASE_SHOOTING := 8
const PHASE_CHARGE := 9
const PHASE_FIGHT := 10
const PX := 40.0

const ALL_DETS := ["Terminator Storm Force", "Assault Brethren", "Gravis Linebreaker Force", "Devastator Brethren",
	"Gravis Siege Force", "Tactical Brethren", "Ironclad Champions", "Tacticus Firestorm Force"]

const AINT := "U_ASSAULT_INTERCESSOR_SQUAD_A"
const BOYZ := "U_BOYZ_B"
const REDEMPTOR := "U_REDEMPTOR_DREADNOUGHT_A"
const DREAD := "U_DEFF_DREAD_A"
const GRETS := "U_GRETCHIN_C"
const TERMS := "U_TERMINATOR_SQUAD_A"
const LT_COMBI := "U_LIEUTENANT_WITH_COMBI_WEAPON_A"
const INT := "U_INTERCESSOR_SQUAD_A"
const MEGA := "U_MEGANOBZ_A"
const JUDICIAR := "U_JUDICIAR_A"
const LT := "U_LIEUTENANT_A"
const BALLISTUS := "U_BALLISTUS_DREADNOUGHT_A"
const HINT := "U_HEAVY_INTERCESSOR_SQUAD_A"
const CAP_GRAVIS := "U_CAPTAIN_IN_GRAVIS_ARMOUR_A"
const BIOLOGIS := "U_APOTHECARY_BIOLOGIS_A"
const CAPTAIN := "U_CAPTAIN_A"
const ANCIENT := "U_ANCIENT_A"
const CAP_TERM := "U_CAPTAIN_IN_TERMINATOR_ARMOUR_A"
const LIB_TERM := "U_LIBRARIAN_IN_TERMINATOR_ARMOUR_A"
const CHAPLAIN := "U_CHAPLAIN_A"

var passed := 0
var failed := 0
var GS = null
var PM = null
var RE = null
var SM = null
var B = null
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


func _fac(p: int) -> Dictionary:
	return GS.state.factions[str(p)]


func _set_dets(p: int, dets: Array) -> void:
	_fac(p)["detachment"] = dets[0]
	_fac(p)["detachments"] = dets


func _without(det: String) -> Array:
	var out: Array = ALL_DETS.duplicate()
	out.erase(det)
	return out


func _attach(char_id: String, body_id: String) -> void:
	_unit(char_id)["attached_to"] = body_id
	_unit(body_id)["attachment_data"] = {"attached_characters": [char_id]}


func _remember() -> void:
	for uid in GS.state.units:
		var arr: Array = []
		for m in GS.state.units[uid].models:
			arr.append(m.get("position").duplicate() if m.get("position") is Dictionary else m.get("position"))
		_base[uid] = {"pos": arr, "enh": GS.state.units[uid].meta.get("enhancements", []).duplicate(),
			"stats": GS.state.units[uid].meta.get("stats", {}).duplicate(), "status": GS.state.units[uid].get("status", 2)}


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
		u["flags"] = {}
		u["status"] = GS.UnitStatus.DEPLOYED
		u.erase("attached_to")
		if u.has("attachment_data"):
			u["attachment_data"] = {"attached_characters": []}
		u.meta["enhancements"] = b.get("enh", []).duplicate()
		u.meta["stats"] = b.get("stats", {}).duplicate()
	GS.state.meta["active_player"] = 1
	GS.state.meta["battle_round"] = 2
	GS.state.meta["phase"] = PHASE_COMMAND
	for p in ["1", "2"]:
		for k in _fac(int(p)).keys():
			if str(k).begins_with("sw11e_") or str(k).begins_with("sm11e_"):
				_fac(int(p)).erase(k)
		GS.state.players[p]["cp"] = 6
	_set_dets(1, ALL_DETS.duplicate())
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


func _mods(atk: String, tgt: String, melee: bool, wp: Dictionary = {"name": "test"}) -> Dictionary:
	return RE.ork11e_ab_mods(_unit(atk), _unit(tgt), wp, melee, GS.state)


func _src_names(m: Dictionary) -> Array:
	return m.get("sources", []).map(func(x): return str(x.get("name", "")))


func _game_log_contains(needle: String) -> bool:
	for e in root.get_node("GameEventLog").get_all_entries():
		if str(e.get("text", "")).contains(needle):
			return true
	return false


func _army(dets: Array, units: Dictionary) -> Dictionary:
	return {"faction": {"name": "Space Marines", "points": 2000, "detachment": dets[0], "detachments": dets}, "units": units}


func _au(name: String, kws: Array, enh: Array) -> Dictionary:
	return {"meta": {"name": name, "keywords": kws, "points": 100, "enhancements": enh, "stats": {"wounds": 4}}, "models": [{"id": "m1", "wounds": 4, "current_wounds": 4}]}


func _weapon(uid: String, melee: bool, name_has: String = "") -> String:
	for w in _unit(uid).meta.weapons:
		var is_m := str(w.get("type", "")).to_lower() == "melee"
		if is_m == melee and (name_has == "" or str(w.name).contains(name_has)):
			return str(w.name)
	return ""


## A real melee resolution (same seed for A/B); returns the dice blocks.
func _melee(atk: String, tgt: String, weapon: String, seed_val: int) -> Array:
	var board: Dictionary = GS.create_snapshot()
	RE.set_test_seed(seed_val)
	var res: Dictionary = RE.resolve_melee_attacks({"type": "FIGHT", "actor_unit_id": atk,
		"payload": {"assignments": [{"attacker": atk, "target": tgt, "weapon": weapon}]}}, board, RE.RNGService.new(seed_val))
	return res.get("dice", [])


## A real (auto-resolved) ranged resolution; returns the full result.
func _shoot(atk: String, tgt: String, weapon_id: String, seed_val: int) -> Dictionary:
	var board: Dictionary = GS.create_snapshot()
	var model_ids: Array = []
	for m in board.units[atk].models:
		model_ids.append(str(m.id))
	RE.set_test_seed(seed_val)
	var sres: Dictionary = RE.resolve_shoot({"type": "SHOOT", "actor_unit_id": atk, "payload": {"assignments": [
		{"weapon_id": weapon_id, "target_unit_id": tgt, "model_ids": model_ids}]}}, board, RE.RNGService.new(seed_val))
	return sres


func _dice_of(blocks: Array, ctx_prefix: String) -> Array:
	return blocks.filter(func(b): return typeof(b) == TYPE_DICTIONARY and str(b.get("context", "")).begins_with(ctx_prefix))


func _ledger_has(blocks: Array, needle: String) -> bool:
	for b in blocks:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		for e in b.get("modifier_ledger", []):
			if str(e.get("source", "")).contains(needle):
				return true
	return false


func _ranged_weapon_id(uid: String, name_has: String) -> String:
	var w: Dictionary = RE.get_unit_weapons(uid, GS.state)
	for mid in w:
		for wid in w[mid]:
			if str(wid).ends_with("_melee"):
				continue
			if name_has == "" or str(wid).to_lower().contains(name_has.to_lower()):
				return str(wid)
	return ""


# ---------------------------------------------------------------------------
func _run() -> void:
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	SM = root.get_node("StratagemManager")
	B = load("res://scripts/codex/space_marines/SMDetachmentsB.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	GS.set_edition(11)
	print("\n=== test_sm11e_detachments_b ===\n")
	_check("fixture %s loads" % FIXTURE, _stage_fixture())
	GS.set_edition(11)
	root.get_node("SettingsService").set("auto_allocate_wounds", true)
	_enter(PHASE_COMMAND)
	_remember()
	_restore()
	_check("P1 is a Space Marine army (SM-D1)", B.Common.is_sm_army(1))
	_check("P2 (Orks) is not", not B.Common.is_sm_army(2))
	_section_validation()
	_section_mastery()
	_section_death_blow()
	_section_champion_first_company()
	_section_corporeum()
	_section_furious_assault()
	_section_imperiums_sword()
	_section_walking_fortress()
	_section_indefatigable()
	_section_relentless_advance()
	_section_master_forged()
	_section_honour_of_vigilance()
	_section_indomitable_defence()
	_section_immovable_conquerors()
	_section_narthecis()
	_section_laurels()
	_section_tactical_insight()
	_section_enduring_vengeance()
	_section_artificer()
	_section_venerable_champion()
	_section_fire_patterns()
	_section_cyber_familiar()
	_section_tempered()
	_section_gating_and_chapters()
	_section_ai()


# ---------------------------------------------------------------------------
func _section_validation() -> void:
	print("\n-- A. army validation (bearer restrictions, detachment gating) --")
	var ER = load("res://scripts/codex/EnhancementRules11e.gd")
	var term_cap := ["ADEPTUS ASTARTES", "CHARACTER", "INFANTRY", "CAPTAIN", "TERMINATOR", "IMPERIUM"]
	var tac_cap := ["ADEPTUS ASTARTES", "CHARACTER", "INFANTRY", "CAPTAIN", "TACTICUS", "IMPERIUM"]
	var grav_cap := ["ADEPTUS ASTARTES", "CHARACTER", "INFANTRY", "CAPTAIN", "GRAVIS", "IMPERIUM"]
	var bio := ["ADEPTUS ASTARTES", "CHARACTER", "INFANTRY", "APOTHECARY", "APOTHECARY BIOLOGIS", "GRAVIS", "IMPERIUM"]
	var dread := ["ADEPTUS ASTARTES", "VEHICLE", "WALKER", "DREADNOUGHT", "IMPERIUM"]
	var inf := ["ADEPTUS ASTARTES", "INFANTRY", "BATTLELINE", "TACTICUS", "IMPERIUM"]
	var cases := [
		["Champion of the First Company on a Terminator Captain", ["Terminator Storm Force"], "Captain in Terminator Armour", term_cap, "Champion of the First Company", true],
		["Champion of the First Company on a Tacticus Captain", ["Terminator Storm Force"], "Captain", tac_cap, "Champion of the First Company", false],
		["Corporeum Reliquary on a Terminator Captain", ["Terminator Storm Force"], "Captain in Terminator Armour", term_cap, "Corporeum Reliquary", true],
		["Furious Assault (Upgrade) on an INFANTRY unit", ["Assault Brethren"], "Assault Intercessor Squad", inf, "Furious Assault", true],
		["Furious Assault on a DREADNOUGHT", ["Assault Brethren"], "Redemptor Dreadnought", dread, "Furious Assault", false],
		["Imperium's Sword on an ADEPTUS ASTARTES character", ["Assault Brethren"], "Captain", tac_cap, "Imperium's Sword", true],
		["Indefatigable Fortitude on a Gravis Captain", ["Gravis Linebreaker Force"], "Captain in Gravis Armour", grav_cap, "Indefatigable Fortitude", true],
		["Relentless Advance on a Tacticus Captain", ["Gravis Linebreaker Force"], "Captain", tac_cap, "Relentless Advance", false],
		["Master-forged Firearms on an INFANTRY character", ["Devastator Brethren"], "Captain", tac_cap, "Master-forged Firearms", true],
		["Honour of Vigilance on an ADEPTUS ASTARTES character", ["Devastator Brethren"], "Captain", tac_cap, "Honour of Vigilance", true],
		["Immovable Conquerors (Upgrade) on a Gravis unit", ["Gravis Siege Force"], "Heavy Intercessor Squad", ["ADEPTUS ASTARTES", "INFANTRY", "BATTLELINE", "GRAVIS"], "Immovable Conquerors", true],
		["Immovable Conquerors on a Tacticus unit", ["Gravis Siege Force"], "Intercessor Squad", inf, "Immovable Conquerors", false],
		["Narthecis Gauntlet on an Apothecary Biologis", ["Gravis Siege Force"], "Apothecary Biologis", bio, "Narthecis Gauntlet", true],
		["Narthecis Gauntlet on a Gravis Captain", ["Gravis Siege Force"], "Captain in Gravis Armour", grav_cap, "Narthecis Gauntlet", false],
		["Laurels of Vigilance on an ADEPTUS ASTARTES character", ["Tactical Brethren"], "Lieutenant", ["ADEPTUS ASTARTES", "CHARACTER", "INFANTRY", "LIEUTENANT", "TACTICUS"], "Laurels of Vigilance", true],
		["Tactical Insight on a Captain", ["Tactical Brethren"], "Captain", tac_cap, "Tactical Insight", true],
		["Tactical Insight on a Lieutenant", ["Tactical Brethren"], "Lieutenant", ["ADEPTUS ASTARTES", "CHARACTER", "INFANTRY", "LIEUTENANT", "TACTICUS"], "Tactical Insight", false],
		["Artificer Sarcophagus (Upgrade) on a Dreadnought", ["Ironclad Champions"], "Redemptor Dreadnought", dread, "Artificer Sarcophagus", true],
		["Artificer Sarcophagus on an INFANTRY unit", ["Ironclad Champions"], "Intercessor Squad", inf, "Artificer Sarcophagus", false],
		["Venerable Champion (Aura) on a Dreadnought", ["Ironclad Champions"], "Ballistus Dreadnought", dread, "Venerable Champion (Aura)", true],
		["Cyber-familiar on a Tacticus character", ["Tacticus Firestorm Force"], "Chaplain", ["ADEPTUS ASTARTES", "CHARACTER", "INFANTRY", "CHAPLAIN", "TACTICUS"], "Cyber-familiar", true],
		["Cyber-familiar on a Gravis character", ["Tacticus Firestorm Force"], "Captain in Gravis Armour", grav_cap, "Cyber-familiar", false],
		["Tempered in Battle (Aura) on a Tacticus character", ["Tacticus Firestorm Force"], "Judiciar", ["ADEPTUS ASTARTES", "CHARACTER", "INFANTRY", "JUDICIAR", "TACTICUS"], "Tempered in Battle (Aura)", true],
		["Tactical Insight without Tactical Brethren", ["Assault Brethren"], "Captain", tac_cap, "Tactical Insight", false],
		["Artificer Sarcophagus without Ironclad Champions", ["Gravis Siege Force"], "Redemptor Dreadnought", dread, "Artificer Sarcophagus", false],
	]
	for c in cases:
		var r: Dictionary = ER.validate_army(_army(c[1], {"A": _au(str(c[2]), c[3], [str(c[4])])}))
		var clean: bool = r.warnings.is_empty() and r.get("errors", []).is_empty()
		_check("%s: %s" % [c[0], "clean" if c[5] else "warning"], clean == bool(c[5]), str(r))
	_check("every group-B enhancement exists in the data", ALL_DETS.size() == 8 and B.ENHANCEMENTS.keys().all(func(k): return ER.enhancement_exists(B.display_name(k))))


func _section_mastery() -> void:
	print("\n-- B. Assault / Devastator / Tactical Mastery --")
	_restore()
	var AR = load("res://scripts/codex/space_wolves/SWArmyRules11e.gd")
	_set_dets(1, ["Assault Brethren"])
	_check("Assault Brethren: assault doctrine 2 selections", AR.doctrine_limit(1, "assault") == 2)
	_check("... devastator / tactical 1", AR.doctrine_limit(1, "devastator") == 1 and AR.doctrine_limit(1, "tactical") == 1)
	_check("extra source named Assault Mastery", B.doctrine_extra_source(1, "assault") == "Assault Mastery")
	_set_dets(1, ["Devastator Brethren"])
	_check("Devastator Brethren: devastator 2, assault 1", AR.doctrine_limit(1, "devastator") == 2 and AR.doctrine_limit(1, "assault") == 1)
	_set_dets(1, ["Tactical Brethren"])
	_check("Tactical Brethren: tactical 2", AR.doctrine_limit(1, "tactical") == 2 and AR.doctrine_limit(1, "devastator") == 1)
	_set_dets(1, ["Assault Brethren", "Devastator Brethren"])
	_check("both: assault 2 and devastator 2", AR.doctrine_limit(1, "assault") == 2 and AR.doctrine_limit(1, "devastator") == 2)
	# Stacks with Codex Discipline (Gladius Task Force).
	_set_dets(1, ["Gladius Task Force", "Assault Brethren"])
	_check("+ Gladius: assault 3 (Mastery + Codex Discipline)", AR.doctrine_limit(1, "assault") == 3)
	_check("+ Gladius: tactical 2 (Codex Discipline)", AR.doctrine_limit(1, "tactical") == 2)
	_fac(1)["sw11e_doctrines_used"] = {"assault": 3}
	_check("Codex Discipline spent on assault (3rd use): tactical back to 1", AR.doctrine_limit(1, "tactical") == 1)
	_fac(1)["sw11e_doctrines_used"] = {"assault": 2}
	_check("assault used twice (Mastery only): Codex Discipline still free for tactical", AR.doctrine_limit(1, "tactical") == 2)
	_fac(1)["sw11e_doctrines_used"] = {"tactical": 2}
	_check("Codex Discipline spent on tactical: assault back to 2 (Mastery)", AR.doctrine_limit(1, "assault") == 2)
	_set_dets(1, ["Assault Brethren"])
	_fac(1)["sw11e_doctrines_used"] = {"assault": 1}
	_check("assault used once: still available (Assault Mastery)", AR.doctrine_available(1, "assault"))
	_fac(1)["sw11e_doctrines_used"] = {"assault": 2}
	_check("assault used twice: no more", not AR.doctrine_available(1, "assault"))
	_set_dets(1, ["Ironclad Champions"])
	_fac(1)["sw11e_doctrines_used"] = {"assault": 1}
	_check("without Assault Brethren: once", not AR.doctrine_available(1, "assault"))
	_check("Orks: no Mastery", B.doctrine_extra_selections(2, "assault") == 0)
	# A real selection through the Space Wolves pipeline (SWCommon state) — Assault Brethren
	# taken by a Space Wolves army: the second Assault Doctrine selection succeeds.
	_restore()
	var fac_name: String = str(_fac(1).get("name", ""))
	_fac(1)["name"] = "Space Wolves"
	_set_dets(1, ["Assault Brethren"])
	_fac(1)["sw11e_doctrines_used"] = {"assault": 1}
	var r1: Dictionary = AR.select_doctrine_diffs(1, "assault")
	_check("Space Wolves + Assault Brethren: second ASSAULT selection is valid", r1.get("success", false), str(r1))
	_fac(1)["sw11e_doctrines_used"] = {"assault": 2}
	var r2: Dictionary = AR.select_doctrine_diffs(1, "assault")
	_check("... a third is refused", not r2.get("success", false))
	_fac(1)["name"] = fac_name
	_restore()


func _section_death_blow() -> void:
	print("\n-- C. Death Blow (Terminator Storm Force) --")
	_restore()
	_check("Terminator Squad +1 to charge rolls", B.charge_roll_bonus(_unit(TERMS)) == 1)
	_check("Intercessors: no", B.charge_roll_bonus(_unit(INT)) == 0)
	_check("Orks: no", B.charge_roll_bonus(_unit(BOYZ)) == 0)
	_attach(CAP_TERM, INT)
	_check("an Attached unit with a TERMINATOR component: +1", B.charge_roll_bonus(_unit(INT)) == 1)
	_restore()
	_set_dets(1, _without("Terminator Storm Force"))
	_check("without Terminator Storm Force: none", B.charge_roll_bonus(_unit(TERMS)) == 0)
	_restore()
	# A real charge roll (seeded): the Terminators charge the Gretchin, +1 applied.
	var ch = _enter(PHASE_CHARGE)
	var a: Dictionary = ch.execute_action({"type": "DECLARE_CHARGE", "actor_unit_id": TERMS, "player": 1, "payload": {"target_unit_ids": [GRETS]}})
	_check("DECLARE_CHARGE Terminators -> Gretchin", a.get("success", false), str(a.get("errors", a.get("error", ""))))
	RE.set_test_seed(3)
	var r: Dictionary = ch.execute_action({"type": "CHARGE_ROLL", "actor_unit_id": TERMS, "player": 1})
	if bool(r.get("awaiting_reroll", false)):
		r = ch.execute_action({"type": "DECLINE_COMMAND_REROLL", "actor_unit_id": TERMS, "player": 1})
	var cr: Dictionary = r.get("dice", [{}])[0] if not r.get("dice", []).is_empty() else {}
	_check("the charge roll total is 2D6 + 1 (Death Blow): %s -> %s" % [str(cr.get("rolls", [])), str(cr.get("total", ""))],
		int(cr.get("charge_bonus", 0)) == 1 and int(cr.get("total", 0)) == int(cr.get("rolls", [0, 0])[0]) + int(cr.get("rolls", [0, 0])[1]) + 1, str(cr))
	_check("8 + 1 = 9 reaches the Gretchin 9\" away (charge not failed)", not bool(cr.get("charge_failed", true)), str(cr))
	_restore()


func _phase_logged(needle: String) -> bool:
	var ph = PM.get_current_phase_instance()
	for k in ["phase_log", "_log_messages", "log_messages"]:
		if k in ph:
			for l in ph.get(k):
				if str(l).contains(needle):
					return true
	return false


func _section_champion_first_company() -> void:
	print("\n-- D. Champion of the First Company --")
	_restore()
	var m := _mods(CAP_TERM, BOYZ, true)
	_check("bearer's melee attacks have [LETHAL HITS]", bool(m.get("lethal", false)) and "Champion of the First Company" in _src_names(m), str(m))
	_check("not ranged", not bool(_mods(CAP_TERM, BOYZ, false).get("lethal", false)))
	_check("Terminator Squad (unled): no", not bool(_mods(TERMS, BOYZ, true).get("lethal", false)))
	_attach(CAP_TERM, TERMS)
	_check("led Terminator Squad: 'this unit' — the bodyguard's melee too", bool(_mods(TERMS, BOYZ, true).get("lethal", false)))
	_restore()
	_set_dets(1, _without("Terminator Storm Force"))
	_check("without Terminator Storm Force: no", not bool(_mods(CAP_TERM, BOYZ, true).get("lethal", false)))
	_restore()


func _section_corporeum() -> void:
	print("\n-- E. Corporeum Reliquary --")
	_restore()
	GS.state.meta["battle_round"] = 1
	GS.state.meta["phase"] = PHASE_MOVEMENT
	_unit(LIB_TERM)["status"] = GS.UnitStatus.IN_RESERVES
	_unit(LIB_TERM)["reserve_type"] = "deep_strike"
	_check("round 1, own Movement phase: the bearer can make an ingress move", B.can_ingress_first_round(_unit(LIB_TERM)))
	_check("Terminator Squad (no bearer): no", not B.can_ingress_first_round(_unit(TERMS)))
	_attach(LIB_TERM, TERMS)
	_check("led Terminator Squad: the Attached unit can", B.can_ingress_first_round(_unit(TERMS)))
	GS.state.meta["active_player"] = 2
	_check("not in the opponent's Movement phase", not B.can_ingress_first_round(_unit(TERMS)))
	GS.state.meta["active_player"] = 1
	GS.state.meta["phase"] = PHASE_SHOOTING
	_check("not in the Shooting phase", not B.can_ingress_first_round(_unit(TERMS)))
	_restore()
	GS.state.meta["battle_round"] = 1
	_unit(LIB_TERM)["status"] = GS.UnitStatus.IN_RESERVES
	_unit(LIB_TERM)["reserve_type"] = "deep_strike"
	var mv = _enter(PHASE_MOVEMENT)
	GS.state.meta["battle_round"] = 1
	var listed := false
	for a in mv.get_available_actions():
		if str(a.get("unit_id", a.get("actor_unit_id", ""))) == LIB_TERM and str(a.get("type", "")).contains("REINFORCEMENT"):
			listed = true
	_check("MovementPhase round 1 lists the bearer's reinforcement action", listed)
	_set_dets(1, _without("Terminator Storm Force"))
	var listed2 := false
	for a in mv.get_available_actions():
		if str(a.get("unit_id", a.get("actor_unit_id", ""))) == LIB_TERM and str(a.get("type", "")).contains("REINFORCEMENT"):
			listed2 = true
	_check("... not without Terminator Storm Force", not listed2)
	_restore()
	_enter(PHASE_COMMAND)


func _melee_sustained(atk: String, tgt: String, seed_val: int) -> Dictionary:
	var blocks := _melee(atk, tgt, _weapon(atk, true), seed_val)
	var out := {"sustained": false, "extra": 0, "rerolled": false}
	for b in _dice_of(blocks, "hit_roll"):
		if int(b.get("sustained_bonus_hits", 0)) > 0 or int(b.get("sustained_hits_value", 0)) > 0 or bool(b.get("sustained_hits_weapon", false)):
			out.sustained = true
		out.extra += int(b.get("sustained_bonus_hits", 0))
		if not b.get("rerolls", []).is_empty() or not b.get("reroll_data", []).is_empty() or int(b.get("rerolled_count", 0)) > 0:
			out.rerolled = true
	out["ledger"] = out.sustained
	out["ev"] = _ledger_has(blocks, "Enduring Vengeance")
	out["blocks"] = blocks.size()
	return out


func _section_furious_assault() -> void:
	print("\n-- F. Furious Assault --")
	_restore()
	var m := _mods(AINT, BOYZ, true)
	_check("melee [SUSTAINED HITS 1] vs Boyz", int(m.get("sustained", 0)) == 1 and "Furious Assault" in _src_names(m), str(m))
	_check("not vs a VEHICLE (Deff Dread)", int(_mods(AINT, DREAD, true).get("sustained", 0)) == 0)
	_check("not ranged", int(_mods(AINT, BOYZ, false).get("sustained", 0)) == 0)
	var with_enh := _melee_sustained(AINT, BOYZ, 21)
	_set_dets(1, _without("Assault Brethren"))
	var without := _melee_sustained(AINT, BOYZ, 21)
	_check("real melee A/B (seed 21): the hit roll block carries [SUSTAINED HITS 1] with the detachment", bool(with_enh.ledger), str(with_enh))
	_check("... and not without it", not bool(without.ledger), str(without))
	_check("... sustained bonus hits %d vs %d (same seed, same hit dice)" % [int(with_enh.extra), int(without.extra)], int(with_enh.extra) > 0 and int(without.extra) == 0)
	_restore()


func _section_imperiums_sword() -> void:
	print("\n-- G. Imperium's Sword (no weapon profile in the source) --")
	_restore()
	_unit(CAPTAIN).meta["enhancements"] = ["Imperium's Sword"]
	var m := _mods(CAPTAIN, BOYZ, true)
	_check("no invented effect (the printed weapon profile is missing)", _src_names(m).filter(func(n): return n.contains("Imperium")).is_empty())
	_check("it is a known group-B enhancement (bearer restriction validated)", B.is_group_b_enhancement("Imperium's Sword"))
	_restore()


func _section_walking_fortress() -> void:
	print("\n-- H. Walking Fortress (Gravis Linebreaker Force) --")
	_restore()
	_check("no move: no bonus", not bool(_mods(HINT, MEGA, false).get("hit_plus", false)))
	_flags(HINT)["moved"] = true
	var m := _mods(HINT, MEGA, false)
	_check("normal move: ranged +1 to hit", bool(m.get("hit_plus", false)) and "Walking Fortress (Gravis Linebreaker Force)" in _src_names(m), str(m))
	_check("not melee", not bool(_mods(HINT, MEGA, true).get("hit_plus", false)))
	_flags(HINT)["advanced"] = true
	_check("advanced: no", not bool(_mods(HINT, MEGA, false).get("hit_plus", false)))
	_flags(HINT).erase("advanced")
	_flags(HINT)["fell_back"] = true
	_check("fell back: no", not bool(_mods(HINT, MEGA, false).get("hit_plus", false)))
	_flags(HINT).erase("fell_back")
	_flags(HINT)["remained_stationary"] = true
	_check("remained stationary: no", not bool(_mods(HINT, MEGA, false).get("hit_plus", false)))
	_flags(HINT).erase("remained_stationary")
	_flags(INT)["moved"] = true
	_check("a TACTICUS unit that moved: no", not bool(_mods(INT, MEGA, false).get("hit_plus", false)))
	_set_dets(1, _without("Gravis Linebreaker Force"))
	_check("without Gravis Linebreaker Force: no", not bool(_mods(HINT, MEGA, false).get("hit_plus", false)))
	_restore()
	# A/B: a real ranged resolution after a normal move — the hit ledger names it.
	_flags(HINT)["moved"] = true
	_flags(HINT)["moved_max_inches"] = 5.0
	var wid := _ranged_weapon_id(HINT, "heavy_bolt_rifle")
	var with_r := _shoot(HINT, GRETS, wid, 9)
	_set_dets(1, _without("Gravis Linebreaker Force"))
	var without_r := _shoot(HINT, GRETS, wid, 9)
	_check("real shooting (%s): ledger names Walking Fortress" % wid, _ledger_has(with_r.get("dice", []), "Walking Fortress"), str(with_r.get("dice", []).slice(0, 1)).substr(0, 300))
	_check("... not without the detachment (same seed)", not _ledger_has(without_r.get("dice", []), "Walking Fortress"))
	_restore()


func _section_indefatigable() -> void:
	print("\n-- I. Indefatigable Fortitude --")
	_restore()
	_unit(CAP_GRAVIS).meta["enhancements"] = ["Indefatigable Fortitude"]
	_check("S7 vs the bearer (T6): -1 to wound", RE.ork11e_ab_wound_penalty(_unit(CAP_GRAVIS), 7, 6))
	_check("... named for the ledger", RE.ork11e_ab_wound_penalty_name(_unit(CAP_GRAVIS), 7, 6) == "Indefatigable Fortitude")
	_check("S6 vs T6: no", not RE.ork11e_ab_wound_penalty(_unit(CAP_GRAVIS), 6, 6))
	_check("Heavy Intercessors (not led, off-objective rule aside): no bearer", B.group_bearer(_unit(HINT), B.INDEFATIGABLE).is_empty())
	_attach(CAP_GRAVIS, HINT)
	_move_to(HINT, 22.0, 46.0)  # off the objective (Indomitable Defence would also apply on it)
	_check("led Heavy Intercessors: 'this unit' — S7 attacks -1 to wound", RE.ork11e_ab_wound_penalty(_unit(HINT), 7, 6))
	_set_dets(1, _without("Gravis Linebreaker Force"))
	_check("without Gravis Linebreaker Force: no", not RE.ork11e_ab_wound_penalty(_unit(HINT), 7, 6))
	_restore()


func _section_relentless_advance() -> void:
	print("\n-- J. Relentless Advance --")
	_restore()
	_check("the bearer has Scouts 5\"", GS.unit_has_scout(CAP_GRAVIS) and is_equal_approx(GS.get_scout_distance(CAP_GRAVIS), 5.0), str(GS.get_scout_distance(CAP_GRAVIS)))
	_check("Heavy Intercessors (not led): no Scouts", not GS.unit_has_scout(HINT))
	_attach(CAP_GRAVIS, HINT)
	_check("led Heavy Intercessors: Scouts 5\"", GS.unit_has_scout(HINT) and is_equal_approx(GS.get_scout_distance(HINT), 5.0))
	_check("the Scouts eligibility list includes the unit", GS.get_scout_units_for_player(1).has(HINT), str(GS.get_scout_units_for_player(1)))
	_set_dets(1, _without("Gravis Linebreaker Force"))
	_check("without Gravis Linebreaker Force: no Scouts", not GS.unit_has_scout(HINT))
	_restore()


func _section_master_forged() -> void:
	print("\n-- K. Master-forged Firearms --")
	_restore()
	var wp := {"name": "Combi-weapon – Bolter", "type": "Ranged", "special_rules": "rapid fire 1, assault"}
	var m := _mods(LT_COMBI, GRETS, false, wp)
	_check("ranged +1 A, +1 S, +1 AP", int(m.get("attacks", 0)) == 1 and int(m.get("strength", 0)) == 1 and int(m.get("ap", 0)) == 1, str(m))
	_check("+1 D (ranged damage hook)", B.ranged_damage_bonus(_unit(LT_COMBI), wp) == 1)
	_check("not melee", int(_mods(LT_COMBI, GRETS, true).get("attacks", 0)) == 0 and B.ranged_damage_bonus(_unit(LT_COMBI), {"type": "Melee"}) == 0)
	var psy := {"name": "Smite", "type": "Ranged", "special_rules": "psychic"}
	_check("[PSYCHIC] attacks excluded", int(_mods(LT_COMBI, GRETS, false, psy).get("attacks", 0)) == 0 and B.ranged_damage_bonus(_unit(LT_COMBI), psy) == 0)
	_attach(LT_COMBI, INT)
	_check("'this model': the bodyguard's attacks get nothing", int(_mods(INT, GRETS, false, wp).get("attacks", 0)) == 0)
	_restore()
	# A/B on a real ranged resolution (same seed): the damage roll uses D 1 -> 2.
	var wid := _ranged_weapon_id(LT_COMBI, "bolter")
	var with_r := _shoot(LT_COMBI, GRETS, wid, 4)
	_set_dets(1, _without("Devastator Brethren"))
	var without_r := _shoot(LT_COMBI, GRETS, wid, 4)
	var hits_w := 0
	var hits_wo := 0
	for b in _dice_of(with_r.get("dice", []), "to_hit"):
		hits_w += b.get("rolls_raw", b.get("rolls", [])).size()
	for b in _dice_of(without_r.get("dice", []), "to_hit"):
		hits_wo += b.get("rolls_raw", b.get("rolls", [])).size()
	_check("real shooting A/B (%s): one more attack rolled with the enhancement (%d vs %d)" % [wid, hits_w, hits_wo], hits_w == hits_wo + 1, "%d vs %d" % [hits_w, hits_wo])
	_restore()


func _section_honour_of_vigilance() -> void:
	print("\n-- L. Honour of Vigilance --")
	_restore()
	var m := _mods(ANCIENT, GRETS, false)
	_check("ranged [LETHAL HITS]", bool(m.get("lethal", false)) and "Honour of Vigilance" in _src_names(m), str(m))
	_check("not melee", not bool(_mods(ANCIENT, GRETS, true).get("lethal", false)))
	_check("no doctrine: no free advance re-roll", B.free_advance_reroll_source(_unit(ANCIENT)) == "")
	_fac(1)["sw11e_doctrine"] = "assault"
	_check("assault doctrine: no", B.free_advance_reroll_source(_unit(ANCIENT)) == "")
	_fac(1)["sw11e_doctrine"] = "devastator"
	_check("devastator doctrine active: can re-roll advance rolls", B.free_advance_reroll_source(_unit(ANCIENT)) == "Honour of Vigilance")
	_check("another unit: no", B.free_advance_reroll_source(_unit(INT)) == "")
	# A real advance (seeded) offers the free re-roll in the dialog context.
	var mv = _enter(PHASE_MOVEMENT)
	_fac(1)["sw11e_doctrine"] = "devastator"
	var offered := false
	for s in range(1, 30):
		_restore()
		_fac(1)["sw11e_doctrine"] = "devastator"
		mv = _enter(PHASE_MOVEMENT)
		_fac(1)["sw11e_doctrine"] = "devastator"
		RE.set_test_seed(s)
		var r: Dictionary = mv.execute_action({"type": "BEGIN_ADVANCE", "actor_unit_id": ANCIENT, "player": 1, "payload": {"rng_seed": s}})
		if "_awaiting_reroll_decision" in mv and mv._awaiting_reroll_decision:
			offered = str(mv._reroll_pending_data.get("free_ability", "")) == "Honour of Vigilance"
			mv.execute_action({"type": "DECLINE_COMMAND_REROLL", "player": 1})
			if offered:
				break
	_check("BEGIN_ADVANCE: the free re-roll is offered as HONOUR OF VIGILANCE", offered)
	_restore()
	_enter(PHASE_COMMAND)


func _section_indomitable_defence() -> void:
	print("\n-- M. Indomitable Defence (Gravis Siege Force) --")
	_restore()
	_check("Heavy Intercessors start on obj_home_2", B.Common.group_in_range_of_any_objective(HINT))
	_check("on an objective: S7 vs T6 -1 to wound", RE.ork11e_ab_wound_penalty(_unit(HINT), 7, 6))
	_check("... named for the ledger", RE.ork11e_ab_wound_penalty_name(_unit(HINT), 7, 6) == "Indomitable Defence (Gravis Siege Force)")
	_check("S6 vs T6: no", not RE.ork11e_ab_wound_penalty(_unit(HINT), 6, 6))
	_move_to(HINT, 22.0, 46.0)
	_check("off the objective: no", not RE.ork11e_ab_wound_penalty(_unit(HINT), 7, 6))
	_restore()
	_check("Intercessors (TACTICUS) on obj_nml_2: no", not RE.ork11e_ab_wound_penalty(_unit(INT), 7, 5))
	_set_dets(1, _without("Gravis Siege Force"))
	_check("without Gravis Siege Force: no", not RE.ork11e_ab_wound_penalty(_unit(HINT), 7, 6))
	_restore()


func _section_immovable_conquerors() -> void:
	print("\n-- N. Immovable Conquerors --")
	_restore()
	var MM = root.get_node("MissionManager")
	var u := _unit(HINT)
	var oc: int = int(MM.model_oc(u, u.models[0]))
	_check("Heavy Intercessor model OC 2 + 1 = 3", oc == 3, str(oc))
	_set_dets(1, _without("Gravis Siege Force"))
	_check("without Gravis Siege Force: OC 2", int(MM.model_oc(u, u.models[0])) == 2)
	_restore()
	_attach(CAP_GRAVIS, HINT)
	_check("an attached leader's model +1 too ('this unit')", int(MM.model_oc(_unit(CAP_GRAVIS), _unit(CAP_GRAVIS).models[0])) == 2)
	_restore()


func _section_narthecis() -> void:
	print("\n-- O. Narthecis Gauntlet --")
	_restore()
	_enter(PHASE_COMMAND)
	_check("full wounds: no card", B.window_offers(1, "phase_start", {}).is_empty())
	_unit(BIOLOGIS).models[0]["current_wounds"] = 1
	var offers: Array = B.window_offers(1, "phase_start", {})
	_check("wounded: NARTHECIS GAUNTLET card in the Command phase", offers.size() == 1 and str(offers[0].stratagem_id) == B.RULE_NARTHECIS, str(offers))
	_check("StratagemManager lists it in phase_start", SM.get_window_offers(1, "phase_start", {}).any(func(o): return str(o.stratagem_id) == B.RULE_NARTHECIS))
	_check("BasePhase phase_start entry queued for the Command phase", not B.phase_start_entries(PHASE_COMMAND, []).is_empty())
	_check("... not when another module queued it already", B.phase_start_entries(PHASE_COMMAND, [{"player": 1, "window_id": "phase_start"}]).is_empty())
	_check("not for the opponent", B.window_offers(2, "phase_start", {}).is_empty())
	var cp_before := int(GS.state.players["1"].cp)
	RE.set_test_seed(7)
	var r: Dictionary = SM.use_stratagem(1, B.RULE_NARTHECIS, BIOLOGIS, {"window_id": "phase_start"})
	_check("use: success, free", r.get("success", false) and int(GS.state.players["1"].cp) == cp_before, str(r))
	var cw := int(_unit(BIOLOGIS).models[0].current_wounds)
	_check("healed D3+1 (2..4) wounds: 1 -> %d" % cw, cw >= 3 and cw <= 5)
	_check("Game Log line", _game_log_contains("NARTHECIS GAUNTLET"))
	_unit(BIOLOGIS).models[0]["current_wounds"] = 1
	_check("once per Command phase", B.window_offers(1, "phase_start", {}).is_empty())
	var rr: Dictionary = SM.use_stratagem(1, B.RULE_NARTHECIS, BIOLOGIS, {"window_id": "phase_start"})
	_check("a second use is refused", not rr.get("success", false))
	_restore()
	_unit(BIOLOGIS).models[0]["current_wounds"] = 2
	_attach(BIOLOGIS, HINT)
	_unit(HINT).models[0]["current_wounds"] = 1
	_unit(BIOLOGIS).models[0]["current_wounds"] = 5
	_check("led unit wounded: the card is offered for the bearer", not B.window_offers(1, "phase_start", {}).is_empty())
	var h: Dictionary = B.heal_diffs(BIOLOGIS, 4)
	_check("heals over the Attached unit (the wounded Heavy Intercessor)", int(h.healed) == 2, str(h))
	_restore()
	_unit(BIOLOGIS).models[0]["current_wounds"] = 1
	GS.state.meta["phase"] = PHASE_MOVEMENT
	_check("not in the Movement phase", B.window_offers(1, "phase_start", {}).is_empty())
	_restore()
	_unit(BIOLOGIS).models[0]["current_wounds"] = 1
	_set_dets(1, _without("Gravis Siege Force"))
	_check("without Gravis Siege Force: no card", B.window_offers(1, "phase_start", {}).is_empty())
	_restore()


func _section_laurels() -> void:
	print("\n-- P. Laurels of Vigilance --")
	_restore()
	var d1: float = B.Common.unit_distance_inches(_unit(LT), _unit(INT))
	_check("the bearer is within 12\" of the Intercessors (%.1f\")" % d1, d1 <= 12.0)
	_check("FIRE OVERWATCH on the Intercessors (BATTLELINE): 0CP", int(SM.preview_cp_cost(1, "fire_overwatch", INT)) == 0, str(SM.preview_cp_cost(1, "fire_overwatch", INT)))
	_check("HEROIC INTERVENTION on the Intercessors: 0CP (base 1)", int(SM.preview_cp_cost(1, "heroic_intervention", INT)) == int(SM.preview_cp_cost(1, "heroic_intervention", TERMS)) - 1)
	_check("Terminators (not BATTLELINE): full cost", int(SM.preview_cp_cost(1, "fire_overwatch", TERMS)) >= 1)
	_check("Assault Intercessors (BATTLELINE, > 12\" away): full cost", int(SM.preview_cp_cost(1, "fire_overwatch", AINT)) >= 1)
	_check("a different stratagem: no", B.stratagem_cp_discount(1, "rapid_ingress", INT).is_empty())
	_check("a discount is possible this round (the 0CP window gate)", B.cp_discount_possible(1, "fire_overwatch_11e"))
	GS.state.players["1"]["cp"] = 0
	GS.state.meta["active_player"] = 2
	GS.state.meta["phase"] = PHASE_MOVEMENT
	var fo_offers: Array = SM.get_window_offers(1, "movement_phase_end", {})
	var fo_rows: Array = []
	for o in fo_offers:
		if str(o.stratagem_id) == "fire_overwatch_11e":
			fo_rows = o.targets.map(func(t): return str(t.unit_id))
	_check("0CP: FIRE OVERWATCH offered for the discounted Intercessors only (%s)" % str(fo_rows), fo_rows == [INT], str(fo_offers))
	GS.state.players["1"]["cp"] = 6
	GS.state.meta["active_player"] = 1
	GS.state.meta["phase"] = PHASE_COMMAND
	var disc: Dictionary = B.stratagem_cp_discount(1, "fire_overwatch_11e", INT)
	B.record_cp_discount(disc)
	_check("after the use: no discount possible this round", not B.cp_discount_possible(1, "fire_overwatch"))
	_check("once per battle round: spent", B.stratagem_cp_discount(1, "fire_overwatch", INT).is_empty())
	_check("Game Log line", _game_log_contains("Laurels of Vigilance"))
	GS.state.meta["battle_round"] = 3
	_check("next battle round: available again", not B.stratagem_cp_discount(1, "fire_overwatch", INT).is_empty())
	_restore()
	_set_dets(1, _without("Tactical Brethren"))
	_check("without Tactical Brethren: no", B.stratagem_cp_discount(1, "fire_overwatch", INT).is_empty())
	_restore()
	# The real use path (StratagemManager.use_stratagem in the Shooting window is phase-bound):
	# can_use_stratagem's CP check sees the discount — a player with 0CP can afford it.
	GS.state.players["1"]["cp"] = 0
	var cu: Dictionary = SM.can_use_stratagem(1, "fire_overwatch", INT, {})
	_check("0CP: the CP check no longer blocks FIRE OVERWATCH on the Intercessors", not str(cu.get("reason", "")).to_lower().contains("cp"), str(cu))
	_restore()


func _section_tactical_insight() -> void:
	print("\n-- Q. Tactical Insight --")
	_restore()
	B.on_phase_enter(PHASE_COMMAND)
	_check("the Captain has the tactical doctrine (in addition)", B.Common.doctrine_active(_unit(CAPTAIN), "tactical"), str(_flags(CAPTAIN)))
	_fac(1)["sw11e_doctrine"] = "assault"
	_check("... in addition to the army doctrine (assault + tactical)", B.Common.doctrine_active(_unit(CAPTAIN), "assault") and B.Common.doctrine_active(_unit(CAPTAIN), "tactical"))
	_check("Intercessors (not led): assault only", B.Common.active_doctrines(_unit(INT)) == ["assault"], str(B.Common.active_doctrines(_unit(INT))))
	_attach(CAPTAIN, INT)
	B.on_phase_enter(PHASE_MOVEMENT)
	_check("led Intercessors: tactical too ('this unit')", B.Common.doctrine_active(_unit(INT), "tactical"))
	_check("TACTICAL effect reaches them: fall back and still shoot", load("res://scripts/codex/space_wolves/SWArmyRules11e.gd").fall_back_allows_shoot(_unit(INT)))
	_unit(CAPTAIN).meta["enhancements"] = []
	B.on_phase_enter(PHASE_SHOOTING)
	_check("enhancement gone: the extra doctrine is cleared", not B.Common.doctrine_active(_unit(INT), "tactical") and not _flags(INT).has("sm11e_tactical_insight"))
	_restore()
	_flags(INT)["sw11e_doctrine_extra"] = ["tactical"]
	B.on_phase_enter(PHASE_COMMAND)
	_check("another rule's extra doctrine is never cleared", _flags(INT).get("sw11e_doctrine_extra", []) == ["tactical"])
	_restore()
	_set_dets(1, _without("Tactical Brethren"))
	B.on_phase_enter(PHASE_COMMAND)
	_check("without Tactical Brethren: no extra doctrine", not B.Common.doctrine_active(_unit(CAPTAIN), "tactical"))
	_restore()
	# Real phase entry runs the sync (BasePhase hook).
	_enter(PHASE_MOVEMENT)
	_check("entering the Movement phase wrote it (BasePhase hook)", B.Common.doctrine_active(_unit(CAPTAIN), "tactical"))
	_restore()
	_enter(PHASE_COMMAND)


func _section_enduring_vengeance() -> void:
	print("\n-- R. Enduring Vengeance (Ironclad Champions) --")
	_restore()
	var m := _mods(REDEMPTOR, DREAD, true)
	_check("DREADNOUGHT melee: re-roll hit rolls of 1", str(m.get("hit_reroll", "")) == "ones" and "Enduring Vengeance (Ironclad Champions)" in _src_names(m), str(m))
	_check("ranged too", str(_mods(REDEMPTOR, MEGA, false).get("hit_reroll", "")) == "ones")
	_check("Terminators: no", str(_mods(TERMS, GRETS, true).get("hit_reroll", "")) == "")
	_check("Deff Dread (Orks): no", str(_mods(DREAD, REDEMPTOR, true).get("hit_reroll", "")) == "")
	var with_r := _melee(REDEMPTOR, DREAD, _weapon(REDEMPTOR, true), 13)
	_set_dets(1, _without("Ironclad Champions"))
	var without_r := _melee(REDEMPTOR, DREAD, _weapon(REDEMPTOR, true), 13)
	_check("real melee A/B: ledger names Enduring Vengeance", _ledger_has(with_r, "Enduring Vengeance"), str(with_r.slice(0, 1)).substr(0, 300))
	_check("... not without Ironclad Champions", not _ledger_has(without_r, "Enduring Vengeance"))
	_restore()


func _section_artificer() -> void:
	print("\n-- S. Artificer Sarcophagus --")
	_restore()
	var EP = load("res://autoloads/EffectPrimitives.gd")
	_check("attacks that target the Redemptor have -1 D", int(EP.get_effect_minus_damage(_unit(REDEMPTOR))) == 1)
	_check("Ballistus: no", int(EP.get_effect_minus_damage(_unit(BALLISTUS))) == 0)
	_set_dets(1, _without("Ironclad Champions"))
	_check("without Ironclad Champions: no", int(EP.get_effect_minus_damage(_unit(REDEMPTOR))) == 0)
	_restore()


func _section_venerable_champion() -> void:
	print("\n-- T. Venerable Champion (Aura) --")
	_restore()
	var d: float = B._group_distance(_unit(JUDICIAR), _unit(BALLISTUS))
	var m := _mods(JUDICIAR, MEGA, false)
	_check("Judiciar (INFANTRY, %.1f\" from the Ballistus): re-roll hit rolls of 1" % d, (str(m.get("hit_reroll", "")) == "ones") == (d <= 6.0) and d <= 6.0, str(m))
	_check("Terminators (far away): no", str(_mods(TERMS, GRETS, true).get("hit_reroll", "")) == "")
	_move_to(TERMS, 30.0, 49.5)
	var dt: float = B._group_distance(_unit(TERMS), _unit(BALLISTUS))
	_check("Terminators moved within 6\" (%.1f\"): yes" % dt, str(_mods(TERMS, GRETS, true).get("hit_reroll", "")) == "ones")
	_check("the Ballistus itself (not INFANTRY / MOUNTED): only Enduring Vengeance", "Venerable Champion (Aura)" not in _src_names(_mods(BALLISTUS, MEGA, false)))
	_set_dets(1, _without("Ironclad Champions"))
	_check("without Ironclad Champions: no", str(_mods(TERMS, GRETS, true).get("hit_reroll", "")) == "")
	_restore()


func _section_fire_patterns() -> void:
	print("\n-- U. Codex Fire-patterns (Tacticus Firestorm Force) --")
	_restore()
	var wid := _ranged_weapon_id(INT, "focused")
	var mids: Array = []
	for mm in _unit(INT).models:
		mids.append(str(mm.id))
	var full := int(RE.count_models_in_half_range(_unit(INT), _unit(MEGA), wid, mids, GS.state, true))
	var melta := int(RE.count_models_in_half_range(_unit(INT), _unit(MEGA), wid, mids, GS.state))
	_check("Meganobz 18\" away: every bolt rifle benefits from [RAPID FIRE] (5)", full == 5, str(full))
	_check("the MELTA/half-range count stays half range (0)", melta == 0, str(melta))
	_check("TACTICUS unit: full range", B.full_range_rapid_fire(_unit(INT)))
	_check("GRAVIS unit: no", not B.full_range_rapid_fire(_unit(HINT)))
	var with_r := _shoot(INT, MEGA, wid, 5)
	_set_dets(1, _without("Tacticus Firestorm Force"))
	var without_r := _shoot(INT, MEGA, wid, 5)
	var n_w := 0
	var n_wo := 0
	for b in _dice_of(with_r.get("dice", []), "to_hit"):
		n_w += b.get("rolls_raw", b.get("rolls", [])).size()
	for b in _dice_of(without_r.get("dice", []), "to_hit"):
		n_wo += b.get("rolls_raw", b.get("rolls", [])).size()
	_check("real shooting A/B: +5 attacks from [RAPID FIRE 1] at 18\" (%d vs %d)" % [n_w, n_wo], n_w == n_wo + 5, "%d vs %d" % [n_w, n_wo])
	_restore()


func _section_cyber_familiar() -> void:
	print("\n-- V. Cyber-familiar --")
	_restore()
	var FAM = root.get_node("FactionAbilityManager")
	_check("redeploy enhancement: Cyber-familiar", FAM.get_redeploy_enhancement_name(1) == "Cyber-familiar", FAM.get_redeploy_enhancement_name(1))
	var ids: Array = FAM.get_razgit_eligible_units(1).map(func(e): return str(e.unit_id))
	_check("eligible: ADEPTUS ASTARTES INFANTRY units (Intercessors, Terminators)", INT in ids and TERMS in ids, str(ids))
	_check("not a Dreadnought", not REDEMPTOR in ids)
	_check("up to three", FAM.get_razgit_redeploys_remaining(1) <= 3)
	_set_dets(1, _without("Tacticus Firestorm Force"))
	_check("without Tacticus Firestorm Force: none", FAM.get_redeploy_enhancement_name(1) == "")
	_restore()


func _section_tempered() -> void:
	print("\n-- W. Tempered in Battle (Aura) --")
	_restore()
	_check("Intercessors within 6\" of the Judiciar: re-roll", B.battle_shock_reroll_source(INT).begins_with("Tempered in Battle"))
	_check("the bearer's own unit: yes", B.battle_shock_reroll_source(JUDICIAR) != "")
	_check("Terminators (far): no", B.battle_shock_reroll_source(TERMS) == "")
	_check("Orks: no", B.battle_shock_reroll_source(BOYZ) == "")
	# Forced test (FactionAbilityManager): Ld 12 can never pass on 2D6 = 12? (needs 12) — re-rolled when failed.
	var FAM = root.get_node("FactionAbilityManager")
	_unit(INT).meta.stats["leadership"] = 13
	var r: Dictionary = FAM.force_battle_shock_test(INT, 0, "test")
	_check("forced test failed -> re-rolled by Tempered in Battle", str(r.get("rerolled_by", "")).begins_with("Tempered in Battle"), str(r))
	_unit(INT).meta.stats["leadership"] = 2
	var r2: Dictionary = FAM.force_battle_shock_test(INT, 0, "test")
	_check("a passed test is not re-rolled", str(r2.get("rerolled_by", "")) == "")
	_restore()
	_unit(TERMS).meta.stats["leadership"] = 13
	_check("outside the aura: no re-roll", str(FAM.force_battle_shock_test(TERMS, 0, "test").get("rerolled_by", "")) == "")
	_restore()
	# The Command phase battle-shock test: forced dice [1, 1] (fail) are re-rolled.
	var cp = _enter(PHASE_COMMAND)
	var rerolled := false
	for s in range(1, 12):
		var res: Dictionary = cp._handle_battle_shock_test({"unit_id": INT, "dice_roll": [1, 1], "payload": {"rng_seed": s}})
		var d1 := int(res.get("die1", 1))
		var d2 := int(res.get("die2", 1))
		cp._units_tested.erase(INT)
		_flags(INT).erase("battle_shocked")
		if d1 + d2 > 2:
			rerolled = true
			break
	_check("Command phase test: the failed [1, 1] is re-rolled (free)", rerolled)
	_set_dets(1, _without("Tacticus Firestorm Force"))
	var res2: Dictionary = cp._handle_battle_shock_test({"unit_id": INT, "dice_roll": [1, 1], "payload": {"rng_seed": 3}})
	_check("without Tacticus Firestorm Force: [1, 1] stands", int(res2.get("die1", 0)) + int(res2.get("die2", 0)) == 2, str(res2).substr(0, 200))
	_restore()


func _section_gating_and_chapters() -> void:
	print("\n-- X. gating (detachment, edition, chapter army) --")
	_restore()
	_set_dets(1, ["Gladius Task Force"])
	_check("no group-B detachment: no aggregator source", _mods(REDEMPTOR, DREAD, true).get("sources", []).filter(func(s): return str(s.name).contains("Ironclad") or str(s.name).contains("Venerable")).is_empty())
	_check("no group-B detachment: no charge bonus / no -1 D / no OC", B.charge_roll_bonus(_unit(TERMS)) == 0 and B.damage_minus(_unit(REDEMPTOR)) == 0 and B.oc_bonus(_unit(HINT)) == 0)
	_restore()
	GS.set_edition(10)
	_check("edition 10: nothing", B.charge_roll_bonus(_unit(TERMS)) == 0 and B.damage_minus(_unit(REDEMPTOR)) == 0)
	GS.set_edition(11)
	var fac_name := str(_fac(1).get("name", ""))
	_fac(1)["name"] = "Space Wolves"
	_check("a chapter army (Space Wolves) taking the detachments gets the rules", B.charge_roll_bonus(_unit(TERMS)) == 1 and B.damage_minus(_unit(REDEMPTOR)) == 1)
	_fac(1)["name"] = "Adeptus Custodes"
	_check("a non-Space Marine faction: no", B.charge_roll_bonus(_unit(TERMS)) == 0)
	_fac(1)["name"] = fac_name
	_restore()


func _section_ai() -> void:
	print("\n-- Y. AI --")
	_restore()
	_enter(PHASE_COMMAND)
	_unit(BIOLOGIS).models[0]["current_wounds"] = 2
	var AIDM = load("res://scripts/AIDecisionMaker.gd")
	var offers: Array = SM.get_all_window_offers(1, "phase_start", {"phase": "command"})
	var t0 := Time.get_ticks_msec()
	var pick: Dictionary = AIDM.decide_window_stratagem(1, "phase_start", offers, {"phase": "command"})
	_check("AI uses the free NARTHECIS GAUNTLET card (synchronous)", str(pick.get("stratagem_id", "")) == B.RULE_NARTHECIS and bool(pick.get("use", false)), str(pick))
	_check("... decided in < 2 s", Time.get_ticks_msec() - t0 < 2000)
	var res: Dictionary = SM.use_stratagem(1, str(pick.get("stratagem_id", "")), str(pick.get("target_unit_id", "")), {"window_id": "phase_start"})
	_check("AI pick resolves", res.get("success", false))
	var offers2: Array = SM.get_all_window_offers(1, "phase_start", {"phase": "command"})
	var pick2: Dictionary = AIDM.decide_window_stratagem(1, "phase_start", offers2, {"phase": "command"})
	_check("afterwards the AI does not loop on it (no card / decline)", str(pick2.get("stratagem_id", "")) != B.RULE_NARTHECIS, str(pick2))
	# AI doctrine choice with Assault Mastery: the second assault selection is a legal pick.
	_restore()
	var AR = load("res://scripts/codex/space_wolves/SWArmyRules11e.gd")
	_set_dets(1, ["Assault Brethren"])
	_fac(1)["sw11e_doctrines_used"] = {"assault": 1}
	var keys: Array = AR.available_doctrines(1).map(func(d): return str(d.key))
	_check("available doctrines include assault a second time", "assault" in keys, str(keys))
	_restore()
	GS.state.units.get(BIOLOGIS).models[0]["current_wounds"] = 5
