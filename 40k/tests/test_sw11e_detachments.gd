extends SceneTree

# Codex: Space Marines (11e) — Space Wolves DETACHMENT RULES (WP-S2,
# SWDetachments11e.gd). Fixture tests/saves/sw11e_s2_wolves_active.w40ksave
# (P1 Space Wolves: Saga of the Great Wolf + Champions of Fenris; P2 Orks).
#   A. CHAMPIONS OF FENRIS — The Great Wolf Watches / Countercharge: Heroic
#      Intervention -1CP on an ADEPTUS ASTARTES CHARACTER unit (Attached unit
#      counts), once per battle round per unit, only with the detachment;
#      a 0-CP player can still be offered it
#   B. SAGA OF THE BEASTSLAYER — Legendary Slayers [LETHAL HITS: CHARACTER/
#      MONSTER/VEHICLE] for Blood Claws / Thunderwolf Cavalry / Wulfen (A/B on a
#      real melee resolution with the same seed)
#   C. SAGA OF THE GREAT WOLF — Master of Wolves: Encircling Jaws (+1 advance /
#      charge, a real Movement-phase advance roll), Hunter's Eye (ranged re-roll
#      1s), Ferocious Strike (9" [SUSTAINED HITS 1]); MONSTER / VEHICLE excluded
#   D. Howling Onslaught — Logan Grimnar, once per battle, Command phase,
#      expiry, AI
#   E. the Saga of the Great Wolf chapter restriction (army validation)
#
# Usage: godot --headless --path 40k --script tests/test_sw11e_detachments.gd

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
const VEN := "U_VENERABLE_DREADNOUGHT_A"
const BOYZ := "U_BOYZ_B"
const DREAD := "U_DEFF_DREAD_A"
const GRETS := "U_GRETCHIN_C"

var passed := 0
var failed := 0
var GS = null
var PM = null
var RE = null
var SM = null
var D = null
var AR = null
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
			if str(k).begins_with("sw11e_listbuild_") or str(k) == "sw11e_transhuman_round":
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


func _src_names(m: Dictionary) -> Array:
	return m.get("sources", []).map(func(s): return str(s.get("name", "")))


func _game_log_contains(needle: String) -> bool:
	for e in root.get_node("GameEventLog").get_all_entries():
		if str(e.get("text", "")).contains(needle):
			return true
	return false


# ---------------------------------------------------------------------------
func _run() -> void:
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	SM = root.get_node("StratagemManager")
	D = load("res://scripts/codex/space_wolves/SWDetachments11e.gd")
	AR = load("res://scripts/codex/space_wolves/SWArmyRules11e.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	GS.set_edition(11)
	print("\n=== test_sw11e_detachments ===\n")
	_check("fixture %s loads" % FIXTURE, _stage_fixture())
	GS.set_edition(11)
	root.get_node("SettingsService").set("auto_allocate_wounds", true)
	_enter(PHASE_COMMAND)
	_remember()
	_section_countercharge()
	_section_legendary_slayers()
	_section_master_of_wolves()
	_section_howling_onslaught()
	_section_restriction()


# ---------------------------------------------------------------------------
func _section_countercharge() -> void:
	print("\n-- A. The Great Wolf Watches (Countercharge) --")
	_restore()
	# The opponent's Charge phase (HEROIC INTERVENTION is used in it).
	GS.state.meta["active_player"] = 2
	_enter(PHASE_CHARGE)
	GS.state.players["1"]["cp"] = 3
	_check("HI on Arjac Rockfist (ADEPTUS ASTARTES CHARACTER) costs 0CP", SM.preview_cp_cost(1, "heroic_intervention", ARJAC) == 0, str(SM.preview_cp_cost(1, "heroic_intervention", ARJAC)))
	_check("HI on the Grey Hunters (not a CHARACTER unit) costs 1CP", SM.preview_cp_cost(1, "heroic_intervention", GH) == 1)
	_check("another stratagem on Arjac: no discount", D.stratagem_cp_discount(1, "fire_overwatch_11e", ARJAC).is_empty())
	var r: Dictionary = SM.use_stratagem(1, "heroic_intervention", ARJAC)
	_check("HI on Arjac used", r.get("success", false), str(r))
	_check("... for 0CP (3 -> 3)", _cp(1) == 3, str(_cp(1)))
	_check("Countercharge marked for this battle round", int(_flags(ARJAC).get(D.F_COUNTERCHARGE_ROUND, -1)) == 2)
	_check("Game Log names Countercharge", _game_log_contains("Countercharge"))
	_check("once per battle round per unit: Arjac's next HI this round costs 1CP", SM.preview_cp_cost(1, "heroic_intervention", ARJAC) == 1)
	_check("another CHARACTER unit (Logan) still gets it this round", SM.preview_cp_cost(1, "heroic_intervention", LOGAN) == 0)
	GS.state.meta["battle_round"] = 3
	_check("next battle round: Arjac's Countercharge is back", SM.preview_cp_cost(1, "heroic_intervention", ARJAC) == 0)
	GS.state.meta["battle_round"] = 2
	# Attached unit with a CHARACTER: an ADEPTUS ASTARTES CHARACTER unit.
	_unit(WGBL)["attached_to"] = GH
	_unit(GH)["attachment_data"] = {"attached_characters": [WGBL]}
	_check("Grey Hunters led by the Battle Leader: HI costs 0CP", SM.preview_cp_cost(1, "heroic_intervention", GH) == 0)
	_unit(WGBL).erase("attached_to")
	_unit(GH)["attachment_data"] = {"attached_characters": []}
	# Without the detachment.
	_set_dets(1, ["Saga of the Great Wolf"])
	_check("without Champions of Fenris: HI on Logan costs 1CP", SM.preview_cp_cost(1, "heroic_intervention", LOGAN) == 1)
	_set_dets(1, ["Saga of the Great Wolf", "Champions of Fenris"])
	# 0 CP: still offered (a CHARACTER unit can afford it).
	_restore()
	GS.state.meta["active_player"] = 2
	_enter(PHASE_CHARGE)
	GS.state.players["1"]["cp"] = 0
	_move_to(GRETS, 38.0, 44.5)
	var avail: Dictionary = SM.is_heroic_intervention_available(1)
	var rows: Array = SM.get_heroic_intervention_eligible_units_11e(1).map(func(x): return str(x.unit_id))
	_check("0CP and Arjac (CHARACTER) has an HI target: the window is available", ARJAC in rows and avail.available, "%s %s" % [str(rows), str(avail)])
	_check("0CP: HI on Arjac can be used", SM.can_use_stratagem(1, "heroic_intervention", ARJAC).can_use)
	_check("0CP: HI on the Grey Hunters cannot", not SM.can_use_stratagem(1, "heroic_intervention", GH).can_use)
	GS.set_edition(10)
	_check("edition 10: no codex discount", D.stratagem_cp_discount(1, "heroic_intervention", ARJAC).is_empty())
	GS.set_edition(11)
	_restore()


func _melee_lethal(atk: String, tgt: String, seed_val: int) -> Dictionary:
	var board: Dictionary = GS.create_snapshot()
	RE.set_test_seed(seed_val)
	var res: Dictionary = RE.resolve_melee_attacks({"type": "FIGHT", "actor_unit_id": atk,
		"payload": {"assignments": [{"attacker": atk, "target": tgt, "weapon": "Wolf Guard Weapon"}]}}, board, RE.RNGService.new(seed_val))
	var out := {"lethal": false, "dice": res.get("dice", []).size(), "auto": 0}
	for b in res.get("dice", []):
		if bool(b.get("lethal_hits_weapon", false)):
			out.lethal = true
		out.auto += int(b.get("lethal_hits_auto_wounds", b.get("lethal_auto_wounds", 0)))
	return out


func _section_legendary_slayers() -> void:
	print("\n-- B. Legendary Slayers --")
	_restore()
	_check("without Saga of the Beastslayer: no lethal hits", not bool(_mods(TWC, DREAD, true).get("lethal", false)))
	_set_dets(1, ["Saga of the Beastslayer", "Champions of Fenris"])
	var m := _mods(TWC, DREAD, true)
	_check("Thunderwolf Cavalry vs Deff Dread (VEHICLE): [LETHAL HITS]", bool(m.get("lethal", false)), str(m))
	_check("... source named for the ledger", "Legendary Slayers (Saga of the Beastslayer)" in _src_names(m))
	_check("ranged attacks too (Blood Claws vs the Deff Dread)", bool(_mods(BC, DREAD, false).get("lethal", false)))
	_unit(BOYZ).meta.keywords.append("CHARACTER")
	_check("Wulfen vs a CHARACTER unit: lethal", bool(_mods(WULFEN, BOYZ, true).get("lethal", false)))
	_unit(BOYZ).meta.keywords.erase("CHARACTER")
	_check("Blood Claws vs Boyz (INFANTRY): no lethal", not bool(_mods(BC, BOYZ, true).get("lethal", false)))
	_check("Grey Hunters (not a slayer unit) vs the Deff Dread: no lethal", not bool(_mods(GH, DREAD, true).get("lethal", false)))
	# A/B on a real melee resolution, same seed.
	var with_det := _melee_lethal(TWC, DREAD, 11)
	_set_dets(1, ["Saga of the Great Wolf", "Champions of Fenris"])
	var without := _melee_lethal(TWC, DREAD, 11)
	_check("real melee: the attack block carries [LETHAL HITS] with the detachment", with_det.lethal, str(with_det))
	_check("real melee: not without it (same seed)", not without.lethal, str(without))
	_restore()


func _section_master_of_wolves() -> void:
	print("\n-- C. Master of Wolves --")
	_restore()
	_check("no doctrine: no Encircling Jaws", D.advance_roll_bonus(_unit(GH)) == 0 and D.charge_roll_bonus(_unit(GH)) == 0)
	_fac(1)["sw11e_doctrine"] = "assault"
	_check("ASSAULT: Encircling Jaws +1 advance", D.advance_roll_bonus(_unit(GH)) == 1)
	_check("ASSAULT: Encircling Jaws +1 charge", D.charge_roll_bonus(_unit(GH)) == 1)
	_check("VEHICLE excluded (Venerable Dreadnought)", D.advance_roll_bonus(_unit(VEN)) == 0)
	_check("Orks never", D.advance_roll_bonus(_unit(BOYZ)) == 0)
	_set_dets(1, ["Champions of Fenris"])
	_check("without Saga of the Great Wolf: none", D.advance_roll_bonus(_unit(GH)) == 0)
	_set_dets(1, ["Saga of the Great Wolf", "Champions of Fenris"])
	# A real advance roll in the Movement phase (seeded) gets +1.
	var mv = _enter(PHASE_MOVEMENT)
	RE.set_test_seed(5)
	var r: Dictionary = mv.execute_action({"type": "BEGIN_ADVANCE", "actor_unit_id": GH, "player": 1, "payload": {"rng_seed": 5}})
	if "_awaiting_reroll_decision" in mv and mv._awaiting_reroll_decision:
		r = mv.execute_action({"type": "DECLINE_COMMAND_REROLL", "player": 1})
	var ej := false
	for dl in mv.dice_log:
		if typeof(dl) == TYPE_DICTIONARY and str(dl.get("type", "")) == "Encircling Jaws":
			ej = true
	_check("real BEGIN_ADVANCE: the dice log shows Encircling Jaws +1", ej, str(mv.dice_log).substr(0, 400))
	_restore()
	# Hunter's Eye: devastator — ranged hit rolls of 1.
	_fac(1)["sw11e_doctrine"] = "devastator"
	var m := _mods(GH, GRETS, false)
	_check("DEVASTATOR: Hunter's Eye ranged re-roll hit 1s", str(m.get("hit_reroll", "")) == "ones" and "Hunter's Eye (Master of Wolves)" in _src_names(m), str(m))
	_check("Hunter's Eye: not on melee attacks", str(_mods(GH, GRETS, true).get("hit_reroll", "")) == "")
	_check("Hunter's Eye: not for a VEHICLE", str(_mods(VEN, GRETS, false).get("hit_reroll", "")) == "")
	# Ferocious Strike: tactical — vs a target within 9".
	_fac(1)["sw11e_doctrine"] = "tactical"
	m = _mods(BC, BOYZ, true)
	_check("TACTICAL: Ferocious Strike [SUSTAINED HITS 1] vs the engaged Boyz", int(m.get("sustained", 0)) == 1 and "Ferocious Strike (Master of Wolves)" in _src_names(m), str(m))
	_check("Ferocious Strike: ranged too, within 9\" (Grey Hunters vs the Gretchin ~9\")", int(_mods(GH, GRETS, false).get("sustained", 0)) == (1 if D._group_distance(_unit(GH), _unit(GRETS)) <= 9.0 else 0))
	_move_to(GRETS, 30.0, 30.0)
	_check("Ferocious Strike: not vs a target farther than 9\"", int(_mods(GH, GRETS, false).get("sustained", 0)) == 0, "%.1f\"" % D._group_distance(_unit(GH), _unit(GRETS)))
	_restore()
	_check("no doctrine: no Master of Wolves modifiers", _src_names(_mods(BC, BOYZ, true)).is_empty(), str(_src_names(_mods(BC, BOYZ, true))))
	# Per-unit doctrine keys drive it too (Grimnar's Command / Guile of the Wolf).
	_flags(GH)["sw11e_doctrine"] = "assault"
	_check("a per-unit assault doctrine gives Encircling Jaws", D.advance_roll_bonus(_unit(GH)) == 1)
	_restore()


func _section_howling_onslaught() -> void:
	print("\n-- D. Howling Onslaught --")
	_restore()
	var phase = _enter(PHASE_COMMAND)
	_check("available in P1's Command phase (Logan on the battlefield)", D.howling_onslaught_available(1))
	var acts: Array = phase.get_available_actions().filter(func(a): return str(a.get("type", "")) == "USE_HOWLING_ONSLAUGHT")
	_check("the Command phase offers USE_HOWLING_ONSLAUGHT", acts.size() == 1)
	_fac(1)["sw11e_doctrine"] = "assault"
	_check("before: the VEHICLE has no Encircling Jaws", D.advance_roll_bonus(_unit(VEN)) == 0)
	var r: Dictionary = phase.execute_action({"type": "USE_HOWLING_ONSLAUGHT", "player": 1})
	_check("USE_HOWLING_ONSLAUGHT succeeds", r.get("success", false), str(r))
	_check("after: the Venerable Dreadnought (VEHICLE) benefits (Encircling Jaws)", D.advance_roll_bonus(_unit(VEN)) == 1)
	_check("Game Log names Howling Onslaught", _game_log_contains("Howling Onslaught"))
	_check("once per battle: not offered again", not D.howling_onslaught_available(1))
	var again: Dictionary = phase.execute_action({"type": "USE_HOWLING_ONSLAUGHT", "player": 1})
	_check("a second use is refused", not again.get("success", false))
	# Lasts through P2's turn; ends at the start of P1's next Command phase.
	GS.state.meta["active_player"] = 2
	_enter(PHASE_COMMAND)
	_check("still active in the opponent's Command phase", D.howling_onslaught_active(1))
	GS.state.meta["active_player"] = 1
	GS.state.meta["battle_round"] = 3
	_enter(PHASE_COMMAND)
	_check("ended at the start of P1's next Command phase", not D.howling_onslaught_active(1))
	_fac(1)["sw11e_doctrine"] = "assault"
	_check("... the VEHICLE is excluded again", D.advance_roll_bonus(_unit(VEN)) == 0)
	_check("and never offered again this battle", not D.howling_onslaught_available(1))
	# Not without Logan / not in P2's turn / not without the detachment.
	_restore()
	_enter(PHASE_COMMAND)
	for m in _unit(LOGAN).models:
		m["alive"] = false
	_check("Logan destroyed: not available", not D.howling_onslaught_available(1))
	_restore()
	_set_dets(1, ["Champions of Fenris"])
	_check("without Saga of the Great Wolf: not available", not D.howling_onslaught_available(1))
	_restore()
	GS.state.meta["active_player"] = 2
	_check("not in the opponent's Command phase", not D.howling_onslaught_available(1))
	# AI.
	_restore()
	_enter(PHASE_COMMAND)
	_check("AI: no doctrine running -> holds Howling Onslaught", D.ai_command_action(1).is_empty())
	_fac(1)["sw11e_doctrine"] = "assault"
	var ai_pick: Dictionary = D.ai_command_action(1)
	_check("AI: doctrine running + a VEHICLE on the battlefield -> uses it", str(ai_pick.get("type", "")) == "USE_HOWLING_ONSLAUGHT", str(ai_pick))
	_fac(1)["sw11e_decided_round"] = 2
	_fac(1)["sw11e_doctrine_decided_round"] = 2
	var AID = load("res://scripts/AIDecisionMaker.gd")
	var dc: Dictionary = AID._decide_command(GS.create_snapshot(), PM.get_current_phase_instance().get_available_actions(), 1)
	_check("AIDecisionMaker routes to Howling Onslaught", str(dc.get("type", "")) == "USE_HOWLING_ONSLAUGHT", str(dc))
	_restore()


func _section_restriction() -> void:
	print("\n-- E. Saga of the Great Wolf restriction --")
	var army := {"faction": {"name": "Space Wolves", "points": 2000, "detachment": "Saga of the Great Wolf", "detachments": ["Saga of the Great Wolf"]},
		"units": {
			"A": {"meta": {"name": "Grey Hunters", "keywords": ["ADEPTUS ASTARTES", "SPACE WOLVES", "INFANTRY"], "points": 100}},
			"B": {"meta": {"name": "Intercessor Squad", "keywords": ["ADEPTUS ASTARTES", "INFANTRY", "BATTLELINE"], "points": 80}},
		}}
	_check("Space Wolves + generic Codex: Space Marines datasheets: allowed", D.validate_army(army).errors.is_empty())
	army.units["C"] = {"meta": {"name": "Death Company Marines", "keywords": ["ADEPTUS ASTARTES", "BLOOD ANGELS", "INFANTRY"], "points": 90}}
	var v: Dictionary = D.validate_army(army)
	_check("a BLOOD ANGELS unit is an error", v.errors.size() == 1 and str(v.errors[0]).contains("BLOOD ANGELS"), str(v))
	var alm = root.get_node("ArmyListManager")
	var v11: Dictionary = alm.validate_army_construction_11e(army)
	_check("ArmyListManager 11e check reports it", not v11.valid and str(v11.errors).contains("Master of Wolves"), str(v11.errors))
	army.faction["detachments"] = ["Champions of Fenris"]
	army.faction["detachment"] = "Champions of Fenris"
	_check("without Saga of the Great Wolf: no restriction", D.validate_army(army).errors.is_empty())
