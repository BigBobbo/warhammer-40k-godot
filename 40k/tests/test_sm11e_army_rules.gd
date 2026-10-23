extends SceneTree

# Codex: Space Marines (11e) — ARMY RULES for every Space Marine army (WP-M2a:
# SWArmyRules11e.gd generalised from Space Wolves to SWCommon.is_sm_army, the
# Librarius budget API in SWCommon). Rules text:
# .llm/codex_11e_wahapedia/space-marines/SPACE_MARINES_GENERIC.md. Against the
# real fixture tests/saves/sm11e_m2a_marines_active.w40ksave (P1 generic Space
# Marines ACTIVE, Command phase of battle round 2, P1 took the first turn; P2
# Orks; built by tests/helpers/gen_sm11e_m2a_fixtures.gd):
#   A. gating — a generic Space Marines army gets the codex army rules; Orks
#      / edition 10 do not; the 10e Gladius-only doctrine path is gone at 11e
#   B. TRANSHUMAN STRATEGIST — +1CP at the start of the battle round (WARLORD)
#   C. COMBAT DOCTRINES selection — own Command phase only, once per Command
#      phase, each doctrine once per battle, skip, Game Log, re-entry keeps it
#   D. CODEX DISCIPLINE (Gladius Task Force): one doctrine twice
#   E. effects — ASSAULT (advance then charge), DEVASTATOR ([ASSAULT] shooting
#      type), TACTICAL (fall back then shoot + charge); Orks unaffected
#   F. expiry — at the start of the owner's next Command phase only
#   G. LIBRARIUS — psyker levels, psychic levels, budget per battle round,
#      once per phase per power, shared with the Space Wolves (Njal) budget
#   H. Command panel — the COMBAT DOCTRINES block is shown for the SM army
#   I. AI — synchronous choice, never stalls the Command phase
#
# Usage: godot --headless --path 40k --script tests/test_sm11e_army_rules.gd

const FIXTURE := "sm11e_m2a_marines_active"
const PHASE_COMMAND := 6
const PHASE_MOVEMENT := 7
const PHASE_SHOOTING := 8
const PHASE_CHARGE := 9
const PX := 40.0

const CAPTAIN := "U_CAPTAIN_A"
const INTER := "U_INTERCESSOR_SQUAD_A"
const ANCIENT := "U_ANCIENT_A"
const REDEMPTOR := "U_REDEMPTOR_DREADNOUGHT_A"
const INFIL := "U_INFILTRATOR_SQUAD_A"
const LIB := "U_LIBRARIAN_A"
const TIG := "U_CHIEF_LIBRARIAN_TIGURIUS_A"
const LIB_PHOBOS := "U_LIBRARIAN_IN_PHOBOS_ARMOUR_A"
const JUDICIAR := "U_JUDICIAR_A"
const BOYZ := "U_BOYZ_B"
const GRETS := "U_GRETCHIN_C"

const ALL_DETS := ["Gladius Task Force", "Ironstorm Spearhead", "Stormlance Task Force", "Gauntlet Task Force",
	"Phobos Shadow Force", "Tacticus Attack Force", "Phobos Shock Force"]
const NO_GLADIUS := ["Ironstorm Spearhead", "Stormlance Task Force"]

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
			if str(k).begins_with("sm11e_listbuild_") or str(k) == AR.F_TRANSHUMAN_ROUND:
				keep[k] = u.flags[k]
		u["flags"] = keep
		if u.get("embarked_in", null) == null:
			u["status"] = GS.UnitStatus.DEPLOYED
	GS.state.meta["active_player"] = 1
	GS.state.meta["battle_round"] = 2
	_fac(1)["detachments"] = ALL_DETS.duplicate()
	_fac(1)["detachment"] = ALL_DETS[0]
	for p in ["1", "2"]:
		for k in _fac(int(p)).keys():
			if str(k).begins_with("sw11e_") or str(k).begins_with("sm11e_"):
				_fac(int(p)).erase(k)


func _enter(phase_id: int):
	PM.transition_to_phase(phase_id)
	var phase = PM.get_current_phase_instance()
	if phase.phase_completed.is_connected(PM._on_phase_completed):
		phase.phase_completed.disconnect(PM._on_phase_completed)
	return phase


func _act(phase, action: Dictionary) -> Dictionary:
	return phase.execute_action(action)


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


func _game_log_contains(needle: String) -> bool:
	var gel = root.get_node_or_null("GameEventLog")
	if gel == null:
		return false
	for e in gel.get_all_entries():
		if str(e.get("text", "")).contains(needle):
			return true
	return false


func _shooting_types(uid: String) -> Array:
	return ShootingTypes.available_for(uid, GS.state)


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

	print("\n=== test_sm11e_army_rules ===\n")
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
	_section_librarius()
	_section_ui()
	_section_ai()


# ---------------------------------------------------------------------------
func _section_gating() -> void:
	print("\n-- A. gating --")
	_check("P1 (faction Space Marines) is a Space Marine army", C.is_sm_army(1))
	_check("P1 is NOT a Space Wolves army (generic Codex: Space Marines)", not C.is_sw_army(1))
	_check("P2 (Orks) is not a Space Marine army", not C.is_sm_army(2))
	_check("Intercessors have Combat Doctrines", C.has_combat_doctrines(_unit(INTER)))
	_check("Ork Boyz have no Combat Doctrines", not C.has_combat_doctrines(_unit(BOYZ)))
	GS.set_edition(10)
	_check("edition 10: no codex Space Marine army", not C.is_sm_army(1))
	_check("edition 10: the army rule's Command actions are not offered", AR.command_actions(1).is_empty())
	GS.set_edition(11)
	# The 10e Gladius-only path never runs at 11e (Gladius is taken by the fixture army).
	var fam = root.get_node("FactionAbilityManager")
	fam.detect_player_detachment(1)
	var phase = PM.get_current_phase_instance()
	var acts: Array = phase.get_available_actions()
	var n_sel := 0
	var n_skip := 0
	for a in acts:
		if str(a.get("type", "")) == "SELECT_COMBAT_DOCTRINE":
			n_sel += 1
			_check("doctrine action %s is the codex army rule (sw11e marker)" % str(a.get("doctrine_key", "")), bool(a.get("sw11e", false)))
		if str(a.get("type", "")) == "SKIP_COMBAT_DOCTRINE":
			n_skip += 1
	_check("exactly 3 doctrine actions + 1 skip (no 10e Gladius duplicate)", n_sel == 3 and n_skip == 1, str(_types(acts)))
	_check("10e FactionAbilityManager: no doctrines offered at 11e", fam.get_available_doctrines(1).is_empty())
	var r10: Dictionary = fam.select_combat_doctrine(1, "assault")
	_check("10e FactionAbilityManager.select_combat_doctrine refuses at 11e", not r10.get("success", true), str(r10))
	_check("... and its state stays empty", fam.get_active_doctrine(1) == "")
	# A non-SM army is refused by the codex validation.
	_check("Orks: SELECT_COMBAT_DOCTRINE refused", not AR.validate_action(2, {"type": "SELECT_COMBAT_DOCTRINE", "doctrine_key": "assault"}).is_empty())


func _section_transhuman() -> void:
	print("\n-- B. Transhuman Strategist --")
	# Fixture load = start of battle round 2 (P1 first): 6 + 1 (Command phase) + 1.
	_check("P1 (WARLORD Captain) has 8 CP after the round-2 start", _cp(1) == 8, str(_cp(1)))
	_check("P2 (Orks) has 7 CP", _cp(2) == 7, str(_cp(2)))
	_check("WARLORD carries the round marker", int(_flags(CAPTAIN).get(AR.F_TRANSHUMAN_ROUND, -1)) == 2)
	_check("Game Log line names Transhuman Strategist", _game_log_contains("Transhuman Strategist"))
	AR.on_battle_round_start(2)
	_check("once per battle round: re-resolving round 2 adds nothing", _cp(1) == 8, str(_cp(1)))
	GS.state.meta["battle_round"] = 3
	GS.state.players["1"]["cp"] = 2
	GS.state.players["2"]["cp"] = 2
	_enter(PHASE_COMMAND)
	_check("round 3 Command phase: P1 +1 (phase) +1 (Transhuman Strategist) = 4", _cp(1) == 4, str(_cp(1)))
	_check("round 3: P2 +1 only", _cp(2) == 3, str(_cp(2)))
	# A WARLORD without the ability (the Judiciar has none) gains nothing.
	GS.state.meta["battle_round"] = 4
	_unit(CAPTAIN).meta["is_warlord"] = false
	_unit(JUDICIAR).meta["is_warlord"] = true
	var before := _cp(1)
	AR.on_battle_round_start(4)
	_check("Judiciar WARLORD (no Transhuman Strategist): no CP", _cp(1) == before)
	_unit(CAPTAIN).meta["is_warlord"] = true
	_unit(JUDICIAR).meta["is_warlord"] = false
	GS.state.meta["battle_round"] = 5
	for m in _unit(CAPTAIN).models:
		m["alive"] = false
	before = _cp(1)
	AR.on_battle_round_start(5)
	_check("destroyed WARLORD: no CP", _cp(1) == before)
	_restore()
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 6


func _section_selection() -> void:
	print("\n-- C. Combat Doctrines selection --")
	_restore()
	_fac(1)["detachments"] = NO_GLADIUS.duplicate()
	_fac(1)["detachment"] = NO_GLADIUS[0]
	var phase = _enter(PHASE_COMMAND)
	_check("selection open at the start of P1's Command phase", AR.selection_open(1))
	_check("not for P2 in P1's Command phase", not AR.selection_open(2))
	var bad: Dictionary = _act(phase, {"type": "SELECT_COMBAT_DOCTRINE", "doctrine_key": "berserk", "player": 1})
	_check("unknown doctrine refused", not bad.get("success", false))
	var r: Dictionary = _act(phase, {"type": "SELECT_COMBAT_DOCTRINE", "doctrine_key": "assault", "player": 1})
	_check("SELECT assault succeeds", r.get("success", false), str(r))
	_check("army doctrine = assault", AR.army_doctrine(1) == "assault")
	_check("Intercessors: assault active (SWCommon API)", C.doctrine_active(_unit(INTER), "assault"))
	_check("Redemptor Dreadnought: assault active", C.doctrine_active(_unit(REDEMPTOR), "assault"))
	_check("Ork Boyz: no doctrine", C.active_doctrines(_unit(BOYZ)).is_empty())
	_check("Game Log line for the doctrine", _game_log_contains("Assault Doctrine active"))
	_check("no second selection this Command phase", not AR.selection_open(1))
	var again: Dictionary = _act(phase, {"type": "SELECT_COMBAT_DOCTRINE", "doctrine_key": "devastator", "player": 1})
	_check("a second doctrine in the same Command phase is refused", not again.get("success", false))
	_enter(PHASE_COMMAND)
	_check("re-entering P1's Command phase keeps the choice", AR.army_doctrine(1) == "assault")
	GS.state.meta["battle_round"] = 3
	phase = _enter(PHASE_COMMAND)
	_check("round 3: last doctrine expired at the start of the Command phase", AR.army_doctrine(1) == "")
	var keys: Array = AR.available_doctrines(1).map(func(d): return str(d.key))
	_check("assault not offered again (once per battle, no Gladius)", not "assault" in keys and "devastator" in keys and "tactical" in keys, str(keys))
	var refused: Dictionary = _act(phase, {"type": "SELECT_COMBAT_DOCTRINE", "doctrine_key": "assault", "player": 1})
	_check("assault a second time refused", not refused.get("success", false))
	var sk: Dictionary = _act(phase, {"type": "SKIP_COMBAT_DOCTRINE", "player": 1})
	_check("SKIP succeeds", sk.get("success", false), str(sk))
	_check("skip: no doctrine, decided this phase", AR.army_doctrine(1) == "" and AR.decided_this_command_phase(1))
	_check("skip uses nothing", AR.times_used(1, "devastator") == 0 and AR.times_used(1, "tactical") == 0)
	GS.state.meta["battle_round"] = 4
	_enter(PHASE_MOVEMENT)
	_check("no selection outside the Command phase", not AR.selection_open(1))
	_restore()


func _section_codex_discipline() -> void:
	print("\n-- D. Codex Discipline (Gladius Task Force) --")
	_restore()
	_fac(1)["detachments"] = NO_GLADIUS.duplicate()
	_fac(1)["detachment"] = NO_GLADIUS[0]
	_fac(1)["sw11e_doctrines_used"] = {"assault": 1}
	_check("without Gladius: assault used up", not AR.doctrine_available(1, "assault"))
	_fac(1)["detachments"] = ALL_DETS.duplicate()
	_fac(1)["detachment"] = ALL_DETS[0]
	_check("with Gladius (Codex Discipline): assault may be selected one more time", AR.doctrine_available(1, "assault"))
	var phase = _enter(PHASE_COMMAND)
	var r: Dictionary = _act(phase, {"type": "SELECT_COMBAT_DOCTRINE", "doctrine_key": "assault", "player": 1})
	_check("second assault succeeds (Codex Discipline)", r.get("success", false), str(r))
	_check("assault used twice", AR.times_used(1, "assault") == 2)
	_check("Game Log names Codex Discipline", _game_log_contains("Codex Discipline"))
	_fac(1)["sw11e_doctrines_used"] = {"assault": 2, "tactical": 1}
	_check("the extra selection is spent: tactical only once", not AR.doctrine_available(1, "tactical"))
	_check("devastator still once", AR.doctrine_available(1, "devastator"))
	_check("assault never a third time", not AR.doctrine_available(1, "assault"))
	_restore()


func _section_effects() -> void:
	print("\n-- E. doctrine effects --")
	_restore()
	var EP = load("res://autoloads/EffectPrimitives.gd")
	# ASSAULT: an advanced unit may declare a charge — the real ChargePhase gate.
	_flags(INTER)["advanced"] = true
	_flags(INTER)["cannot_charge"] = true
	_unit(INTER)["status"] = GS.UnitStatus.MOVED
	var charge = _enter(PHASE_CHARGE)
	_check("no doctrine: the advanced Intercessors cannot charge", not charge._can_unit_charge(_unit(INTER)))
	_fac(1)["sw11e_doctrine"] = "assault"
	_check("ASSAULT: advance_and_charge", EP.has_effect_advance_and_charge(_unit(INTER)))
	_check("ASSAULT: ChargePhase lets the advanced Intercessors charge", charge._can_unit_charge(_unit(INTER)))
	_check("ASSAULT does not give advance-and-shoot", not EP.has_effect_advance_and_shoot(_unit(INTER)))
	# DEVASTATOR: ranged [ASSAULT] — the Redemptor Dreadnought (no printed [ASSAULT] weapon).
	_flags(REDEMPTOR)["advanced"] = true
	_flags(REDEMPTOR)["cannot_charge"] = true
	_fac(1)["sw11e_doctrine"] = ""
	var types_none: Array = _shooting_types(REDEMPTOR)
	_fac(1)["sw11e_doctrine"] = "devastator"
	var types_dev: Array = _shooting_types(REDEMPTOR)
	_check("no doctrine: the advanced Redemptor has no Assault shooting type", not "assault" in types_none and not "normal" in types_none, str(types_none))
	_check("DEVASTATOR: the Assault shooting type is selectable", "assault" in types_dev, str(types_dev))
	_check("DEVASTATOR: advance_and_shoot", EP.has_effect_advance_and_shoot(_unit(REDEMPTOR)))
	# TACTICAL: fall back and still shoot and charge.
	_restore()
	_flags(INFIL)["fell_back"] = true
	_flags(INFIL)["cannot_shoot"] = true
	_flags(INFIL)["cannot_charge"] = true
	_unit(INFIL)["status"] = GS.UnitStatus.MOVED
	charge = _enter(PHASE_CHARGE)
	_check("no doctrine: a unit that fell back cannot charge", not charge._can_unit_charge(_unit(INFIL)))
	_check("no doctrine: a unit that fell back has no shooting type", _shooting_types(INFIL).is_empty(), str(_shooting_types(INFIL)))
	_fac(1)["sw11e_doctrine"] = "tactical"
	_check("TACTICAL: fall_back_and_shoot + fall_back_and_charge", EP.has_effect_fall_back_and_shoot(_unit(INFIL)) and EP.has_effect_fall_back_and_charge(_unit(INFIL)))
	_check("TACTICAL: ChargePhase lets the Infiltrators charge after falling back", charge._can_unit_charge(_unit(INFIL)))
	_check("TACTICAL: Normal shooting selectable after falling back", "normal" in _shooting_types(INFIL), str(_shooting_types(INFIL)))
	_restore()
	_fac(1)["sw11e_doctrine"] = "assault"
	_flags(BOYZ)["advanced"] = true
	_check("Ork Boyz: no advance-and-charge from the Space Marine doctrine", not EP.has_effect_advance_and_charge(_unit(BOYZ)))
	GS.set_edition(10)
	_flags(INTER)["advanced"] = true
	_check("edition 10: no codex doctrine effect", not EP.has_effect_advance_and_charge(_unit(INTER)))
	GS.set_edition(11)
	_restore()


func _section_expiry() -> void:
	print("\n-- F. expiry --")
	_restore()
	_fac(1)["detachments"] = NO_GLADIUS.duplicate()
	_fac(1)["detachment"] = NO_GLADIUS[0]
	var phase = _enter(PHASE_COMMAND)
	_act(phase, {"type": "SELECT_COMBAT_DOCTRINE", "doctrine_key": "tactical", "player": 1})
	_flags(INTER)["sw11e_doctrine"] = "assault"
	_flags(INTER)["sw11e_doctrine_expires_player"] = 1
	GS.state.meta["active_player"] = 2
	_enter(PHASE_COMMAND)
	_check("P1's doctrine lasts through the opponent's Command phase", AR.army_doctrine(1) == "tactical")
	_check("P1's per-unit doctrine kept in P2's Command phase", str(_flags(INTER).get("sw11e_doctrine", "")) == "assault")
	_check("doctrine active in the opponent's turn", C.doctrine_active(_unit(INFIL), "tactical"))
	GS.state.meta["active_player"] = 1
	GS.state.meta["battle_round"] = 3
	_enter(PHASE_COMMAND)
	_check("the start of P1's next Command phase ends the army doctrine", AR.army_doctrine(1) == "")
	_check("... and P1's per-unit doctrine", not _flags(INTER).has("sw11e_doctrine"))
	_check("used count persists (once per battle)", AR.times_used(1, "tactical") == 1)
	_restore()


func _section_librarius() -> void:
	print("\n-- G. Librarius (psyker-level budget API) --")
	_restore()
	var lib := _unit(LIB)
	var tig := _unit(TIG)
	_check("Librarian (Librarius, 'Librarian'): psyker level 1", C.librarius_psyker_level(lib) == 1, str(C.librarius_psyker_level(lib)))
	_check("Chief Librarian Tigurius ('Chief Librarian'): psyker level 3", C.librarius_psyker_level(tig) == 3, str(C.librarius_psyker_level(tig)))
	_check("Librarian in Phobos Armour: psyker level 1", C.librarius_psyker_level(_unit(LIB_PHOBOS)) == 1)
	_check("Intercessors: not a psyker", C.librarius_psyker_level(_unit(INTER)) == 0 and not C.librarius_psyker(_unit(INTER)))
	var wardens := {"owner": 1, "meta": {"keywords": ["ADEPTUS ASTARTES", "PSYKER", "INFANTRY"], "abilities": ["Combat Doctrines", "Raise the Banner"]}}
	_check("an ADEPTUS ASTARTES PSYKER without Librarius / a psyker level (Wardens of Ultramar): no budget", not C.librarius_psyker(wardens))
	_check("Prescience is psychic level 2", C.librarius_psychic_level("Prescience") == 2)
	_check("Telepathic Assault is psychic level 1", C.librarius_psychic_level("Telepathic Assault") == 1)
	_check("an explicit '(psychic level 3)' in the name wins", C.librarius_psychic_level("Some Power (psychic level 3)") == 3)
	_check("an Ork unit is never budgeted", not C.librarius_psyker(_unit(BOYZ)))
	_enter(PHASE_SHOOTING)
	var ok1: Dictionary = C.librarius_can_use(TIG, "Prescience")
	_check("Tigurius may use Prescience (2 <= 3)", ok1.ok and int(ok1.cost) == 2 and int(ok1.level) == 3, str(ok1))
	GS.apply_state_changes(C.librarius_use_diffs(TIG, "Prescience"))
	_check("budget: 2 of 3 used", C.librarius_levels_used(_unit(TIG)) == 2)
	var once: Dictionary = C.librarius_can_use(TIG, "Prescience")
	_check("the same power again this phase refused", not once.ok and str(once.reason).contains("already used"), str(once))
	var ta: Dictionary = C.librarius_can_use(TIG, "Telepathic Assault")
	_check("Telepathic Assault (1) fits the remaining budget", ta.ok, str(ta))
	GS.apply_state_changes(C.librarius_use_diffs(TIG, "Telepathic Assault"))
	_check("budget: 3 of 3 used", C.librarius_levels_used(_unit(TIG)) == 3)
	_enter(PHASE_CHARGE)
	var over: Dictionary = C.librarius_can_use(TIG, "Prescience")
	_check("another phase: Prescience (2) would exceed psyker level 3", not over.ok and str(over.reason).contains("Librarius"), str(over))
	GS.state.meta["battle_round"] = 3
	_check("next battle round: the budget resets", C.librarius_levels_used(_unit(TIG)) == 0 and C.librarius_can_use(TIG, "Prescience").ok)
	GS.state.meta["battle_round"] = 2
	var l1: Dictionary = C.librarius_can_use(LIB, "Might of Heroes")
	_check("Librarian: Might of Heroes (1) ok", l1.ok, str(l1))
	GS.apply_state_changes(C.librarius_use_diffs(LIB, "Might of Heroes"))
	var l2: Dictionary = C.librarius_can_use(LIB, "Thunderous Force")
	_check("Librarian (psyker level 1): a second power this round refused", not l2.ok, str(l2))
	_check("non-psyker refused with a reason", not C.librarius_can_use(INTER, "Might of Heroes").ok)
	var SWA = load("res://scripts/codex/space_wolves/SWAbilities11e.gd")
	_check("the budget flags are the ones SWAbilities11e (Njal) reads", int(SWA.psychic_levels_used(_unit(LIB))) == 1, str(SWA.psychic_levels_used(_unit(LIB))))
	_restore()


func _section_ui() -> void:
	print("\n-- H. Command panel --")
	_restore()
	_enter(PHASE_COMMAND)
	_check("the COMBAT DOCTRINES block is shown for the generic Space Marines army", AR.show_command_ui(1))
	_check("not for the Orks", not AR.show_command_ui(2))
	var box := VBoxContainer.new()
	var emitted: Array = []
	AR.build_command_ui(box, 1, func(a): emitted.append(a))
	var dbox = box.get_node_or_null("SW11eDoctrinesBox")
	_check("block built with the three doctrine buttons", dbox != null and dbox.get_node_or_null("SW11eDoctrine_assault") != null and dbox.get_node_or_null("SW11eDoctrine_tactical") != null)
	_check("the status line mentions Codex Discipline (Gladius taken)", dbox != null and str(dbox.get_node("SW11eDoctrineStatus").text).contains("Codex Discipline"))
	if dbox != null:
		dbox.get_node("SW11eDoctrine_devastator").emit_signal("pressed")
	_check("a button press emits SELECT_COMBAT_DOCTRINE devastator", emitted.size() == 1 and str(emitted[0].get("doctrine_key", "")) == "devastator", str(emitted))
	box.free()
	_restore()


func _section_ai() -> void:
	print("\n-- I. AI --")
	_restore()
	var phase = _enter(PHASE_COMMAND)
	var AID = load("res://scripts/AIDecisionMaker.gd")
	var d: Dictionary = AID._decide_command(GS.create_snapshot(), phase.get_available_actions(), 1)
	_check("AI picks a Combat Doctrines action first", str(d.get("type", "")) in ["SELECT_COMBAT_DOCTRINE", "SKIP_COMBAT_DOCTRINE"], str(d))
	_check("AI: engaged doctrine units (Ancient vs Boyz) -> Tactical Doctrine", str(d.get("doctrine_key", "")) == "tactical", str(d))
	var r: Dictionary = _act(phase, d)
	_check("AI's action executes", r.get("success", false), str(r))
	var d2: Dictionary = AID._decide_command(GS.create_snapshot(), phase.get_available_actions(), 1)
	_check("after deciding, the AI moves on (no doctrine action again)", str(d2.get("type", "")) != "SELECT_COMBAT_DOCTRINE" and str(d2.get("type", "")) != "SKIP_COMBAT_DOCTRINE", str(d2))
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
