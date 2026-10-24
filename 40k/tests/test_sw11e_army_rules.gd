extends SceneTree

# Codex: Space Marines (11e) — Space Wolves ARMY RULES (WP-S2, SWArmyRules11e.gd).
# Rules text: .llm/codex_11e_wahapedia/space-marines/SPACE_WOLVES.md. Against
# the real fixture tests/saves/sw11e_s2_wolves_active.w40ksave (P1 Space Wolves
# ACTIVE, Command phase of battle round 2, P1 took the first turn; P2 Orks):
#   A. gating — Space Wolves army detection; the 10e Gladius doctrine path is off
#   B. COMBAT DOCTRINES selection — offered in your own Command phase only, once
#      per Command phase, each doctrine once per battle, skip, Game Log,
#      re-entering the phase keeps the choice
#   C. CODEX DISCIPLINE (Gladius Task Force also taken): one doctrine twice
#   D. effects — ASSAULT (advance then charge, real ChargePhase eligibility),
#      DEVASTATOR (ranged [ASSAULT]: the 11e Assault shooting type with every
#      ranged weapon), TACTICAL (fall back then shoot + charge); per-unit
#      doctrine keys (S3 / S4) replace / add; Attached units; Orks unaffected
#   E. expiry — at the start of the owner's next Command phase only
#   F. TRANSHUMAN STRATEGIST — +1CP at the start of the battle round (WARLORD)
#   G. CURSE OF THE WULFEN — OC aura, ranges, battle-shock, VEHICLE +3,
#      objective control; BESTIAL FORMS transport capacity
#   H. SONS OF RUSS — army validation + live warning
#   I. AI — synchronous choice, never stalls the Command phase
#
# Usage: godot --headless --path 40k --script tests/test_sw11e_army_rules.gd

const FIXTURE := "sw11e_s2_wolves_active"
const PHASE_COMMAND := 6
const PHASE_MOVEMENT := 7
const PHASE_SHOOTING := 8
const PHASE_CHARGE := 9
const PX := 40.0

const LOGAN := "U_LOGAN_GRIMNAR_A"
const GH := "U_GREY_HUNTERS_A"
const BC := "U_BLOOD_CLAWS_A"
const WULFEN := "U_WULFEN_A"
const WGBL := "U_WOLF_GUARD_BATTLE_LEADER_A"
const PRIEST := "U_WOLF_PRIEST_A"
const VEN := "U_VENERABLE_DREADNOUGHT_A"
const RAGNAR := "U_RAGNAR_BLACKMANE_A"
const BOYZ := "U_BOYZ_B"
const GRETS := "U_GRETCHIN_C"

var passed := 0
var failed := 0
var GS = null
var PM = null
var RE = null
var AR = null
var C = null
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


func _cp(p: int) -> int:
	return int(GS.state.players[str(p)].cp)


func _fac(p: int) -> Dictionary:
	return GS.state.factions[str(p)]


func _remember() -> void:
	for uid in GS.state.units:
		var arr: Array = []
		for m in GS.state.units[uid].models:
			arr.append(m.get("position").duplicate() if m.get("position") is Dictionary else m.get("position"))
		_base[uid] = arr


func _restore() -> void:
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		var arr: Array = _base.get(uid, [])
		for i in range(u.models.size()):
			if i < arr.size():
				u.models[i]["position"] = arr[i].duplicate() if arr[i] is Dictionary else arr[i]
			u.models[i]["alive"] = true
			u.models[i]["current_wounds"] = u.models[i].get("wounds", 1)
		var keep := {}
		for k in u.get("flags", {}):
			if str(k).begins_with("sw11e_listbuild_") or str(k) == AR.F_TRANSHUMAN_ROUND:
				keep[k] = u.flags[k]
		u["flags"] = keep
		u["status"] = GS.UnitStatus.DEPLOYED
		u.erase("attached_to")
		if u.has("attachment_data"):
			u["attachment_data"] = {"attached_characters": []}
	GS.state.meta["active_player"] = 1
	GS.state.meta["battle_round"] = 2
	for p in ["1", "2"]:
		for k in _fac(int(p)).keys():
			if str(k).begins_with("sw11e_"):
				_fac(int(p)).erase(k)


func _enter(phase_id: int):
	PM.transition_to_phase(phase_id)
	var phase = PM.get_current_phase_instance()
	if phase.phase_completed.is_connected(PM._on_phase_completed):
		phase.phase_completed.disconnect(PM._on_phase_completed)
	return phase


func _act(phase, action: Dictionary) -> Dictionary:
	var r: Dictionary = phase.execute_action(action)
	return r


func _types(actions: Array) -> Array:
	return actions.map(func(a): return "%s:%s" % [str(a.get("type", "")), str(a.get("doctrine_key", ""))])


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


# ---------------------------------------------------------------------------
func _run() -> void:
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	AR = load("res://scripts/codex/space_wolves/SWArmyRules11e.gd")
	C = load("res://scripts/codex/space_wolves/SWCommon.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	GS.set_edition(11)

	print("\n=== test_sw11e_army_rules ===\n")
	_check("fixture %s loads" % FIXTURE, _stage_fixture())
	GS.set_edition(11)
	root.get_node("SettingsService").set("auto_allocate_wounds", true)
	# The fixture sits in P1's Command phase of battle round 2 (P1 first):
	# entering it runs the start of the battle round, as loading the save does.
	_enter(PHASE_COMMAND)
	_remember()

	_section_gating()
	_section_transhuman()
	_section_selection()
	_section_codex_discipline()
	_section_effects()
	_section_expiry()
	_section_curse()
	_section_sons_of_russ()
	_section_ai()


# ---------------------------------------------------------------------------
func _section_gating() -> void:
	print("\n-- A. gating --")
	_check("P1 is a Space Wolves army", C.is_sw_army(1))
	_check("P2 (Orks) is not", not C.is_sw_army(2))
	_check("Grey Hunters have Combat Doctrines (SW army)", C.has_combat_doctrines(_unit(GH)))
	_check("Ork Boyz have no Combat Doctrines", not C.has_combat_doctrines(_unit(BOYZ)))
	GS.set_edition(10)
	_check("edition 10: not a codex Space Wolves army (index rules)", not C.is_sw_army(1))
	GS.set_edition(11)
	# The 10e Gladius path never runs for a Space Wolves army, even with Gladius taken.
	_fac(1)["detachments"] = ["Saga of the Great Wolf", "Champions of Fenris", "Gladius Task Force"]
	var fam = root.get_node("FactionAbilityManager")
	fam.detect_player_detachment(1)
	var phase = PM.get_current_phase_instance()
	var acts: Array = phase.get_available_actions()
	var n_sel := 0
	var n_skip := 0
	for a in acts:
		if str(a.get("type", "")) == "SELECT_COMBAT_DOCTRINE":
			n_sel += 1
			_check("doctrine action %s is the codex army rule (sw11e)" % str(a.get("doctrine_key", "")), bool(a.get("sw11e", false)))
		if str(a.get("type", "")) == "SKIP_COMBAT_DOCTRINE":
			n_skip += 1
	_check("exactly 3 doctrine actions + 1 skip (no duplicate 10e Gladius prompt)", n_sel == 3 and n_skip == 1, str(_types(acts)))
	_check("the 10e FactionAbilityManager doctrine state untouched", fam.get_active_doctrine(1) == "")
	_fac(1)["detachments"] = ["Saga of the Great Wolf", "Champions of Fenris"]


func _section_transhuman() -> void:
	print("\n-- F. Transhuman Strategist --")
	# Fixture load = start of battle round 2 (P1 first): 6 + 1 (Command phase) + 1.
	_check("P1 (WARLORD Logan Grimnar) has 8 CP after the round-2 start", _cp(1) == 8, str(_cp(1)))
	_check("P2 (Orks) has 7 CP", _cp(2) == 7, str(_cp(2)))
	_check("not counted against the 10e bonus-CP cap", GS.get_bonus_cp_gained_this_round(1) == 0)
	_check("WARLORD carries the round marker", int(_flags(LOGAN).get(AR.F_TRANSHUMAN_ROUND, -1)) == 2)
	AR.on_battle_round_start(2)
	_check("once per battle round: re-resolving round 2 adds nothing", _cp(1) == 8, str(_cp(1)))
	# Round 3 through the real Command phase (P1 first again).
	GS.state.meta["battle_round"] = 3
	GS.state.players["1"]["cp"] = 2
	GS.state.players["2"]["cp"] = 2
	_enter(PHASE_COMMAND)
	_check("round 3 Command phase: P1 +1 (phase) +1 (Transhuman Strategist) = 4", _cp(1) == 4, str(_cp(1)))
	_check("round 3: P2 +1 only", _cp(2) == 3, str(_cp(2)))
	_check("Game Log line names Transhuman Strategist", _game_log_contains("Transhuman Strategist"))
	# Not the WARLORD: Ragnar has the ability, but he is not the WARLORD.
	GS.state.meta["battle_round"] = 4
	_unit(LOGAN).meta["is_warlord"] = false
	_unit(GH).meta["is_warlord"] = true
	var before := _cp(1)
	AR.on_battle_round_start(4)
	_check("Grey Hunters WARLORD (no Transhuman Strategist): no CP", _cp(1) == before)
	_unit(LOGAN).meta["is_warlord"] = true
	_unit(GH).meta["is_warlord"] = false
	_unit(RAGNAR).meta["is_warlord"] = false
	# A destroyed WARLORD gains nothing.
	GS.state.meta["battle_round"] = 5
	for m in _unit(LOGAN).models:
		m["alive"] = false
	before = _cp(1)
	AR.on_battle_round_start(5)
	_check("destroyed WARLORD: no CP", _cp(1) == before)
	_restore()
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 6


func _game_log_contains(needle: String) -> bool:
	var gel = root.get_node_or_null("GameEventLog")
	if gel == null:
		return false
	for e in gel.get_all_entries():
		if str(e.get("text", "")).contains(needle):
			return true
	return false


func _section_selection() -> void:
	print("\n-- B. Combat Doctrines selection --")
	_restore()
	var phase = _enter(PHASE_COMMAND)
	_check("selection open at the start of P1's Command phase", AR.selection_open(1))
	_check("not for P2 in P1's Command phase", not AR.selection_open(2))
	var bad: Dictionary = _act(phase, {"type": "SELECT_COMBAT_DOCTRINE", "doctrine_key": "berserk", "player": 1})
	_check("unknown doctrine refused", not bad.get("success", false))
	var r: Dictionary = _act(phase, {"type": "SELECT_COMBAT_DOCTRINE", "doctrine_key": "assault", "player": 1})
	_check("SELECT assault succeeds", r.get("success", false), str(r))
	_check("army doctrine = assault", AR.army_doctrine(1) == "assault")
	_check("used once", AR.times_used(1, "assault") == 1)
	_check("Grey Hunters: assault active (SWCommon API)", C.doctrine_active(_unit(GH), "assault"))
	_check("Logan Grimnar (has the ability): assault active", C.doctrine_active(_unit(LOGAN), "assault"))
	_check("Ork Boyz: no doctrine", C.active_doctrines(_unit(BOYZ)).is_empty())
	_check("Game Log line for the doctrine", _game_log_contains("Assault Doctrine active"))
	_check("no second selection this Command phase", not AR.selection_open(1))
	var again: Dictionary = _act(phase, {"type": "SELECT_COMBAT_DOCTRINE", "doctrine_key": "devastator", "player": 1})
	_check("a second doctrine in the same Command phase is refused", not again.get("success", false))
	_check("no doctrine actions left this phase", AR.command_actions(1).is_empty())
	# Re-entering the same Command phase (a save loaded mid-phase) keeps it.
	_enter(PHASE_COMMAND)
	_check("re-entering P1's Command phase keeps the choice", AR.army_doctrine(1) == "assault")
	# Next battle round: assault is gone (once per battle), the others remain.
	GS.state.meta["battle_round"] = 3
	phase = _enter(PHASE_COMMAND)
	_check("round 3: last doctrine expired at the start of the Command phase", AR.army_doctrine(1) == "")
	var keys: Array = AR.available_doctrines(1).map(func(d): return str(d.key))
	_check("assault not offered again (once per battle)", not "assault" in keys and "devastator" in keys and "tactical" in keys, str(keys))
	var refused: Dictionary = _act(phase, {"type": "SELECT_COMBAT_DOCTRINE", "doctrine_key": "assault", "player": 1})
	_check("assault a second time refused", not refused.get("success", false))
	var sk: Dictionary = _act(phase, {"type": "SKIP_COMBAT_DOCTRINE", "player": 1})
	_check("SKIP succeeds", sk.get("success", false), str(sk))
	_check("skip: no doctrine, decided this phase", AR.army_doctrine(1) == "" and AR.decided_this_command_phase(1))
	_check("skip uses nothing", AR.times_used(1, "devastator") == 0 and AR.times_used(1, "tactical") == 0)
	# Not in the Movement phase.
	GS.state.meta["battle_round"] = 4
	_enter(PHASE_MOVEMENT)
	_check("no selection outside the Command phase", not AR.selection_open(1))
	_restore()


func _section_codex_discipline() -> void:
	print("\n-- C. Codex Discipline (Gladius Task Force) --")
	_restore()
	_fac(1)["sw11e_doctrines_used"] = {"assault": 1}
	_check("without Gladius: assault used up", not AR.doctrine_available(1, "assault"))
	_fac(1)["detachments"] = ["Saga of the Great Wolf", "Gladius Task Force"]
	_check("with Gladius: assault may be selected one more time", AR.doctrine_available(1, "assault"))
	var phase = _enter(PHASE_COMMAND)
	var r: Dictionary = _act(phase, {"type": "SELECT_COMBAT_DOCTRINE", "doctrine_key": "assault", "player": 1})
	_check("second assault succeeds (Codex Discipline)", r.get("success", false), str(r))
	_check("assault used twice", AR.times_used(1, "assault") == 2)
	_fac(1)["sw11e_doctrines_used"] = {"assault": 2, "tactical": 1}
	_check("the extra selection is spent: tactical only once", not AR.doctrine_available(1, "tactical"))
	_check("devastator still once", AR.doctrine_available(1, "devastator"))
	_check("assault never a third time", not AR.doctrine_available(1, "assault"))
	_fac(1)["detachments"] = ["Saga of the Great Wolf", "Champions of Fenris"]
	_restore()


func _shooting_types(uid: String) -> Array:
	return ShootingTypes.available_for(uid, GS.state)


func _section_effects() -> void:
	print("\n-- D. doctrine effects --")
	_restore()
	var EP = load("res://autoloads/EffectPrimitives.gd")
	# ASSAULT: an advanced unit may declare a charge — the real ChargePhase gate.
	_flags(GH)["advanced"] = true
	_flags(GH)["cannot_charge"] = true
	_unit(GH)["status"] = GS.UnitStatus.MOVED
	var charge = _enter(PHASE_CHARGE)
	_check("no doctrine: an advanced unit cannot charge", not charge._can_unit_charge(_unit(GH)))
	_fac(1)["sw11e_doctrine"] = "assault"
	_check("ASSAULT: advance_and_charge", EP.has_effect_advance_and_charge(_unit(GH)))
	_check("ASSAULT: ChargePhase lets the advanced Grey Hunters charge", charge._can_unit_charge(_unit(GH)))
	_check("ASSAULT does not give advance-and-shoot", not EP.has_effect_advance_and_shoot(_unit(GH)))
	# DEVASTATOR: ranged attacks have [ASSAULT] — the Assault shooting type with
	# every ranged weapon (Venerable Dreadnought: no printed [ASSAULT] weapon).
	_flags(VEN)["advanced"] = true
	_flags(VEN)["cannot_charge"] = true
	_fac(1)["sw11e_doctrine"] = ""
	var types_none: Array = _shooting_types(VEN)
	_fac(1)["sw11e_doctrine"] = "devastator"
	var types_dev: Array = _shooting_types(VEN)
	_check("no doctrine: the advanced Venerable Dreadnought (no [ASSAULT] weapon) cannot shoot", not "assault" in types_none and not "normal" in types_none, str(types_none))
	_check("DEVASTATOR: the Assault shooting type is selectable", "assault" in types_dev, str(types_dev))
	var sb := {}
	for w in _unit(VEN).meta.get("weapons", []):
		if str(w.get("name", "")).to_lower() == "storm bolter":
			sb = w
	var st = ShootingTypes.get_type("assault")
	_check("DEVASTATOR: the Storm Bolter is allowed under Assault shooting", not sb.is_empty() and st.weapon_allowed(sb, _unit(VEN), GS.state).allowed)
	_fac(1)["sw11e_doctrine"] = ""
	_check("no doctrine: the Storm Bolter is NOT allowed under Assault shooting", not st.weapon_allowed(sb, _unit(VEN), GS.state).allowed)
	_fac(1)["sw11e_doctrine"] = "devastator"
	_check("DEVASTATOR: advance_and_shoot (10e shoot gate)", EP.has_effect_advance_and_shoot(_unit(VEN)))
	_check("DEVASTATOR does not give advance-and-charge", not EP.has_effect_advance_and_charge(_unit(VEN)))
	# TACTICAL: fall back and still shoot and charge.
	_restore()
	_flags(BC)["fell_back"] = true
	_flags(BC)["cannot_shoot"] = true
	_flags(BC)["cannot_charge"] = true
	_unit(BC)["status"] = GS.UnitStatus.MOVED
	_move_to(BC, 9.0, 40.0)
	charge = _enter(PHASE_CHARGE)
	_check("no doctrine: a unit that fell back cannot charge", not charge._can_unit_charge(_unit(BC)))
	_check("no doctrine: a unit that fell back has no shooting type", _shooting_types(BC).is_empty(), str(_shooting_types(BC)))
	_fac(1)["sw11e_doctrine"] = "tactical"
	_check("TACTICAL: fall_back_and_shoot + fall_back_and_charge", EP.has_effect_fall_back_and_shoot(_unit(BC)) and EP.has_effect_fall_back_and_charge(_unit(BC)))
	_check("TACTICAL: ChargePhase lets the Blood Claws charge after falling back", charge._can_unit_charge(_unit(BC)))
	_check("TACTICAL: Normal shooting selectable after falling back", "normal" in _shooting_types(BC), str(_shooting_types(BC)))
	# Per-unit keys (Grimnar's Command / Guile of the Wolf write them — S3 / S4).
	_restore()
	_fac(1)["sw11e_doctrine"] = "assault"
	_flags(GH)["sw11e_doctrine"] = "tactical"
	_flags(GH)["sw11e_doctrine_expires_player"] = 1
	_check("a per-unit doctrine replaces the army doctrine for that unit", C.active_doctrines(_unit(GH)) == ["tactical"], str(C.active_doctrines(_unit(GH))))
	_check("per-unit tactical: fall back and charge, no advance-and-charge", EP.has_effect_fall_back_and_charge(_unit(GH)) and not EP.has_effect_advance_and_charge(_unit(GH)))
	_flags(LOGAN)["sw11e_doctrine_extra"] = ["assault", "devastator", "tactical"]
	_check("extra doctrines (Guile of the Wolf) add to the army doctrine", AR.group_doctrines(_unit(LOGAN)).size() == 3)
	# Attached unit: Logan leads the Grey Hunters' unit for the test — one unit, every component's doctrines.
	_unit(LOGAN)["attached_to"] = GH
	_unit(GH)["attachment_data"] = {"attached_characters": [LOGAN]}
	_check("Attached unit: Logan's Guile doctrines cover the unit he leads", AR.group_doctrine_active(_unit(GH), "devastator") and AR.group_doctrine_active(_unit(GH), "assault"))
	_restore()
	# Orks never benefit.
	_fac(1)["sw11e_doctrine"] = "assault"
	_flags(BOYZ)["advanced"] = true
	_check("Ork Boyz: no advance-and-charge from the Space Wolves doctrine", not EP.has_effect_advance_and_charge(_unit(BOYZ)))
	# Edition 10: nothing.
	GS.set_edition(10)
	_flags(GH)["advanced"] = true
	_check("edition 10: no codex doctrine effect", not EP.has_effect_advance_and_charge(_unit(GH)))
	GS.set_edition(11)
	_restore()


func _section_expiry() -> void:
	print("\n-- E. expiry --")
	_restore()
	var phase = _enter(PHASE_COMMAND)
	_act(phase, {"type": "SELECT_COMBAT_DOCTRINE", "doctrine_key": "tactical", "player": 1})
	_flags(GH)["sw11e_doctrine"] = "assault"
	_flags(GH)["sw11e_doctrine_expires_player"] = 1
	_flags(BOYZ)["sw11e_doctrine"] = "assault"
	_flags(BOYZ)["sw11e_doctrine_expires_player"] = 2
	# P2's turn: P2's Command phase does NOT end P1's doctrine.
	GS.state.meta["active_player"] = 2
	_enter(PHASE_COMMAND)
	_check("P1's doctrine lasts through the opponent's Command phase", AR.army_doctrine(1) == "tactical")
	_check("P1's per-unit doctrine kept in P2's Command phase", str(_flags(GH).get("sw11e_doctrine", "")) == "assault")
	_check("doctrine active in the opponent's turn", C.doctrine_active(_unit(BC), "tactical"))
	# Start of P1's next Command phase: ends.
	GS.state.meta["active_player"] = 1
	GS.state.meta["battle_round"] = 3
	_enter(PHASE_COMMAND)
	_check("the start of P1's next Command phase ends the army doctrine", AR.army_doctrine(1) == "")
	_check("... and P1's per-unit doctrine", not _flags(GH).has("sw11e_doctrine") and not _flags(GH).has("sw11e_doctrine_expires_player"))
	_check("another player's per-unit key untouched", str(_flags(BOYZ).get("sw11e_doctrine", "")) == "assault")
	_check("used count persists (once per battle)", AR.times_used(1, "tactical") == 1)
	_restore()


func _section_curse() -> void:
	print("\n-- G. Curse of the Wulfen --")
	_restore()
	var MM = root.get_node("MissionManager")
	var w := _unit(WULFEN)
	_check("Wulfen print OC 0", int(w.meta.stats.get("objective_control", -1)) == 0)
	_check("WGBL (SPACE WOLVES CHARACTER) within 6\": +1 OC (INFANTRY)", AR.oc_bonus(w) == 1, str(AR.oc_bonus(w)))
	_check("model OC 0 -> 1 through MissionManager", MM.model_oc(w, w.models[0]) == 1, str(MM.model_oc(w, w.models[0])))
	MM.check_all_objectives()
	_check("the cursed Wulfen control obj_nml_1 (OC 5 vs 0)", int(MM.objective_control_state.get("obj_nml_1", 0)) == 1, str(MM.objective_control_state))
	# Character out of 6": no curse (the Wolf Priest is ~26" away).
	_move_to(WGBL, 22.0, 18.0)
	_check("character 10\"+ away, no Wolf Priest within 12\": no bonus", AR.oc_bonus(w) == 0, AR.curse_source(w))
	MM.check_all_objectives()
	_check("... obj_nml_1 no longer controlled", int(MM.objective_control_state.get("obj_nml_1", 0)) == 0, str(MM.objective_control_state))
	# Wolf Priest within 12" (not 6").
	_move_to(PRIEST, 20.0, 22.5)
	_check("WOLF PRIEST within 12\": curse on", AR.oc_bonus(w) == 1, AR.curse_source(w))
	_move_to(PRIEST, 28.0, 22.5)
	_check("WOLF PRIEST 13\"+ away: curse off", AR.oc_bonus(w) == 0, AR.curse_source(w))
	_restore()
	# A WULFEN character never switches it on (Murderfang-like: give WGBL the WULFEN keyword).
	_unit(WGBL).meta.keywords.append("WULFEN")
	_check("a WULFEN CHARACTER does not switch the curse on", AR.oc_bonus(_unit(WULFEN)) == 0)
	_unit(WGBL).meta.keywords.erase("WULFEN")
	# Battle-shocked: no bonus.
	_flags(WULFEN)["battle_shocked"] = true
	_check("battle-shocked: no bonus", AR.oc_bonus(_unit(WULFEN)) == 0)
	_flags(WULFEN).erase("battle_shocked")
	# VEHICLE: +3 (a Wulfen Dreadnought stand-in: the Venerable Dreadnought given the ability).
	var v := _unit(VEN)
	v.meta.abilities.append({"name": "Curse of the Wulfen"})
	v.meta.keywords.append("WULFEN")
	_move_to(VEN, 18.0, 21.0)
	_check("VEHICLE with the curse near a character: +3 OC", AR.oc_bonus(v) == 3, str(AR.oc_bonus(v)))
	v.meta.abilities.pop_back()
	v.meta.keywords.erase("WULFEN")
	_check("a unit without the ability gets nothing", AR.oc_bonus(_unit(GH)) == 0)
	_restore()
	# BESTIAL FORMS — transport capacity.
	var TM = root.get_node("TransportManager")
	var transport := {"transport_data": {"capacity": 12, "capacity_multipliers": {}}}
	_check("5 Wulfen take the space of 10 models", TM._get_unit_capacity_cost(_unit(WULFEN), transport) == 10, str(TM._get_unit_capacity_cost(_unit(WULFEN), transport)))
	_check("10 Grey Hunters take 10", TM._get_unit_capacity_cost(_unit(GH), transport) == 10)
	GS.set_edition(10)
	_check("edition 10: 5 Wulfen take 5", TM._get_unit_capacity_cost(_unit(WULFEN), transport) == 5)
	GS.set_edition(11)


func _sw_army(units: Dictionary, dets: Array = ["Saga of the Great Wolf"]) -> Dictionary:
	return {"faction": {"name": "Space Wolves", "points": 2000, "detachment": dets[0], "detachments": dets}, "units": units}


func _u(name: String, kws: Array) -> Dictionary:
	return {"meta": {"name": name, "keywords": kws, "points": 100, "stats": {}, "abilities": []}, "models": [{"id": "m1"}]}


func _section_sons_of_russ() -> void:
	print("\n-- H. Sons of Russ --")
	var alm = root.get_node("ArmyListManager")
	var ok := _sw_army({"A": _u("Grey Hunters", ["ADEPTUS ASTARTES", "SPACE WOLVES", "INFANTRY"]),
		"B": _u("Intercessor Squad", ["ADEPTUS ASTARTES", "INFANTRY", "BATTLELINE"])})
	_check("a Space Wolves army without APOTHECARY units: no Sons of Russ error", AR.validate_army(ok).errors.is_empty())
	var bad := _sw_army({"A": _u("Grey Hunters", ["ADEPTUS ASTARTES", "SPACE WOLVES", "INFANTRY"]),
		"APO": _u("Apothecary", ["ADEPTUS ASTARTES", "CHARACTER", "INFANTRY", "APOTHECARY"])})
	var v: Dictionary = AR.validate_army(bad)
	_check("an APOTHECARY unit in a Space Wolves army is an error", v.errors.size() == 1 and str(v.errors[0]).contains("Sons of Russ"), str(v))
	var v11: Dictionary = alm.validate_army_construction_11e(bad)
	var found := false
	for e in v11.errors:
		if str(e).contains("Sons of Russ"):
			found = true
	_check("ArmyListManager 11e construction check reports it (invalid army)", found and not v11.valid, str(v11.errors))
	var sm_army := {"faction": {"name": "Space Marines", "points": 2000, "detachment": "Gladius Task Force"},
		"units": {"APO": _u("Apothecary", ["ADEPTUS ASTARTES", "CHARACTER", "INFANTRY", "APOTHECARY"])}}
	_check("a non-Space Wolves Space Marine army may include an Apothecary", AR.validate_army(sm_army).errors.is_empty())
	# Live warning (Formations phase hook) for an army on the board.
	_unit(GH).meta.keywords.append("APOTHECARY")
	var live: Array = AR.live_army_problems(1)
	_check("live: the board's APOTHECARY unit is reported", live.size() == 1 and str(live[0]).contains("Sons of Russ"), str(live))
	_unit(GH).meta.keywords.erase("APOTHECARY")
	_check("live: none on the fixture army", AR.live_army_problems(1).is_empty())


func _section_ai() -> void:
	print("\n-- I. AI --")
	_restore()
	var phase = _enter(PHASE_COMMAND)
	var AID = load("res://scripts/AIDecisionMaker.gd")
	var snap: Dictionary = GS.create_snapshot()
	var d: Dictionary = AID._decide_command(snap, phase.get_available_actions(), 1)
	_check("AI picks a Space Wolves doctrine action first", str(d.get("type", "")) in ["SELECT_COMBAT_DOCTRINE", "SKIP_COMBAT_DOCTRINE"], str(d))
	# Engaged doctrine units (Blood Claws vs Boyz) -> TACTICAL.
	_check("AI: engaged units -> Tactical Doctrine", str(d.get("doctrine_key", "")) == "tactical", str(d))
	var r: Dictionary = _act(phase, d)
	_check("AI's action executes", r.get("success", false), str(r))
	var d2: Dictionary = AID._decide_command(GS.create_snapshot(), phase.get_available_actions(), 1)
	_check("after deciding, the AI moves on (no doctrine action again)", str(d2.get("type", "")) != "SELECT_COMBAT_DOCTRINE" and str(d2.get("type", "")) != "SKIP_COMBAT_DOCTRINE", str(d2))
	# Holding the doctrines: nothing engaged, nothing close, round 1.
	_restore()
	GS.state.meta["battle_round"] = 1
	for uid in GS.state.units:
		if int(_unit(uid).owner) == 2:
			_move_to(uid, 40.0, 2.5)
	phase = _enter(PHASE_COMMAND)
	var hold: Dictionary = AR.ai_command_action(1)
	_check("round 1, enemy far away: the AI keeps its doctrines (SKIP)", str(hold.get("type", "")) == "SKIP_COMBAT_DOCTRINE", str(hold))
	_check("the SKIP executes", _act(phase, hold).get("success", false))
	_check("AI has nothing left to decide for doctrines (never stalls)", AR.ai_command_action(1).is_empty())
	_restore()
