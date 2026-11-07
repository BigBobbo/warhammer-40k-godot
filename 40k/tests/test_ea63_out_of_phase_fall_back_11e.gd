extends SceneTree

# EA-63 (11e 09.07 FALL-BACK MOVE / 09.02.02 Selecting Modes / 09.07.01
# Desperate Escape) — fall-back moves made OUTSIDE the Movement phase:
#   ▪ TACTICAL FLUIDITY (Captain in Phobos Armour etc., SMAbilitiesB): "at the
#     end of your opponent's Fight phase, this engaged unit can make a
#     fall-back move of up to 6"".
#   ▪ WIND-SWIFT EVASION (Stormlance Task Force, SMCodexAMovement): an engaged
#     MOUNTED unit makes a fall-back move at the end of the Fight phase.
# 09.07: BEFORE MOVING select the mode (Ordered Retreat if not battle-shocked,
# else Desperate Escape: a hazard roll per model); WHILE MOVING only a
# Desperate Escape may move through enemy models; AFTER MOVING a Desperate
# Escape by a unit that is not battle-shocked makes a battle-shock roll.
# 09.07.01: a rule that forces desperate escape -> hazard rolls AND the
# battle-shock roll.
#
# Before the fix Tactical Fluidity made no mode choice, no hazard rolls and no
# battle-shock roll (and moved straight through enemy models); WIND-SWIFT
# EVASION never made the battle-shock roll, never offered the choice and never
# checked a path.
#
# Fixtures: sm11e_m3a_active (WIND-SWIFT: P1 Space Marines vs P2 Orks; the
# Outrider Squad is engaged with Ork Nobz) and cus11e_c5_active with the
# sm11e / ork11e codex test armies (Tactical Fluidity), as in
# test_sm11e_stratagems_a.gd / test_sm11e_abilities_b.gd.
#
# Usage: godot --headless --path 40k --script tests/test_ea63_out_of_phase_fall_back_11e.gd

const WS_FIXTURE := "sm11e_m3a_active"
const TF_FIXTURE := "cus11e_c5_active"
const SM_ARMY := "sm11e_codex_test"
const ORK_ARMY := "ork11e_codex_test"
const P_CMD := 6
const P_SHOOT := 8
const P_FIGHT := 10
const PX := 40.0
const CSV_WINDSWIFT := "wind-swift-evasion-stormlance-task-force"
const DETS := ["Gladius Task Force", "Ironstorm Spearhead", "Stormlance Task Force", "Gauntlet Task Force",
	"Phobos Shadow Force", "Tacticus Attack Force", "Phobos Shock Force"]
const CAPTAIN := "U_CAPTAIN_IN_PHOBOS_ARMOUR_A"
const OUTRIDERS := "U_OUTRIDER_SQUAD_A"

var passed := 0
var failed := 0
var GS = null
var SM = null
var RE = null
var PM = null
var B = null
var SWC = null
var RM = null
var Movement = null
var _sm_army: Dictionary = {}
var _ork_army: Dictionary = {}


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
# shared helpers
# ---------------------------------------------------------------------------

func _copy_fixture(fixture: String) -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + fixture + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + fixture + ext))
	return slm.load_game(fixture)


func _u(uid: String) -> Dictionary:
	return GS.state.units.get(uid, {})


func _flags(uid: String) -> Dictionary:
	var u := _u(uid)
	if not (u.get("flags", null) is Dictionary):
		u["flags"] = {}
	return u.flags


func _log_count(fragment: String) -> int:
	var gel = root.get_node_or_null("GameEventLog")
	var n := 0
	if gel and "entries" in gel:
		for e in gel.entries:
			if fragment in str(e.get("text", "")):
				n += 1
	return n


func _log_since(start: int) -> Array:
	var gel = root.get_node_or_null("GameEventLog")
	var out: Array = []
	if gel and "entries" in gel:
		for i in range(start, gel.entries.size()):
			out.append(str(gel.entries[i].get("text", "")))
	return out


func _log_size() -> int:
	var gel = root.get_node_or_null("GameEventLog")
	return gel.entries.size() if gel and "entries" in gel else 0


func _any_has(lines: Array, parts: Array) -> bool:
	for l in lines:
		var ok := true
		for p in parts:
			if not str(p) in str(l):
				ok = false
				break
		if ok:
			return true
	return false


func _variant_ids(entry: Dictionary) -> Array:
	return entry.get("variants", []).map(func(v): return str(v.get("id", "")))


# ---------------------------------------------------------------------------
# WIND-SWIFT EVASION helpers (test_sm11e_stratagems_a.gd)
# ---------------------------------------------------------------------------

func _ws_stage() -> void:
	_copy_fixture(WS_FIXTURE)
	GameConstants.edition = 11
	GS.state.factions["1"]["detachment"] = DETS[0]
	GS.state.factions["1"]["detachments"] = DETS.duplicate()
	SM.load_faction_stratagems_for_player(1)
	root.get_node("TerrainManager").terrain_features = []
	SM._usage_history = {"1": [], "2": []}
	SM.active_effects = []
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 0


func _ws_phase():
	PM.transition_to_phase(P_CMD)
	PM.transition_to_phase(P_FIGHT)
	var phase = PM.get_current_phase_instance()
	if phase.phase_completed.is_connected(PM._on_phase_completed):
		phase.phase_completed.disconnect(PM._on_phase_completed)
	var n := 0
	while phase.has_pending_stratagem_window() and n < 8:
		var w: Dictionary = phase.get_pending_stratagem_window()
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.get("player", 0)), "window_id": str(w.get("window_id", ""))})
		n += 1
	GS.state.players["1"]["cp"] = 6
	return phase


func _ws_sid() -> String:
	for s in SM.get_faction_stratagems_for_player(1):
		if str(s.get("csv_id", "")) == CSV_WINDSWIFT:
			return str(s.id)
	return ""


func _ws_entry(uid: String) -> Dictionary:
	var sid := _ws_sid()
	for o in SM.get_window_offers(1, "fight_phase_end", {"phase": "fight"}):
		if str(o.get("stratagem_id", "")) != sid:
			continue
		for t in o.get("targets", []):
			if str(t.get("unit_id", "")) == uid:
				return t
	return {}


func _ws_use(phase, variant: String) -> Dictionary:
	phase.open_stratagem_window(1, "fight_phase_end", {"phase": "fight"}, "")
	var ctx := {}
	if variant != "":
		ctx["variant_id"] = variant
	return phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "fight_phase_end",
		"stratagem_id": _ws_sid(), "target_unit_id": OUTRIDERS, "context": ctx})


func _group_alive(uid: String) -> int:
	return RM.current_positions(uid, GS.state).size()


func _centroid(uid: String) -> Vector2:
	var pos: Dictionary = RM.current_positions(uid, GS.state)
	var c := Vector2.ZERO
	for k in pos:
		c += pos[k]
	return c / float(maxi(1, pos.size()))


# ---------------------------------------------------------------------------
# Tactical Fluidity helpers (test_sm11e_abilities_b.gd)
# ---------------------------------------------------------------------------

func _tf_fresh(phase: int, active: int) -> void:
	_copy_fixture(TF_FIXTURE)
	GameConstants.edition = 11
	RE.set_test_seed(-1)
	GS.state.units = {}
	for pair in [[_sm_army, 1], [_ork_army, 2]]:
		var army: Dictionary = pair[0]
		for k in army.get("units", {}):
			var u: Dictionary = army.units[k].duplicate(true)
			u["id"] = k
			u["owner"] = int(pair[1])
			u["flags"] = {}
			u["status"] = 0
			u.erase("attached_to")
			u.erase("embarked_in")
			u["attachment_data"] = {"attached_characters": []}
			for m in u.get("models", []):
				m["alive"] = true
				m["position"] = null
				m["current_wounds"] = int(m.get("wounds", 1))
			GS.state.units[k] = u
	GS.state.factions["1"] = _sm_army.get("faction", {}).duplicate(true)
	GS.state.factions["2"] = _ork_army.get("faction", {}).duplicate(true)
	SM.load_faction_stratagems_for_player(1)
	SM.load_faction_stratagems_for_player(2)
	GS.state.meta["phase"] = phase
	GS.state.meta["active_player"] = active
	GS.state.meta["battle_round"] = 2
	for p in ["1", "2"]:
		GS.state.players[p]["cp"] = 6
		GS.state.players[p].erase(B.ARMY_USES)
	SM._usage_history = {"1": [], "2": []}
	root.get_node("UnitAbilityManager").reset_for_new_game()
	B.offers_suppressed = false
	root.get_node("TerrainManager").terrain_features = []


func _place_at(uid: String, positions_in: Array) -> void:
	var u: Dictionary = GS.state.units[uid]
	u["status"] = 2
	var models: Array = u.get("models", [])
	for i in range(models.size()):
		if i < positions_in.size():
			models[i]["position"] = {"x": float(positions_in[i].x) * PX, "y": float(positions_in[i].y) * PX}
			models[i]["alive"] = true
		else:
			models[i]["alive"] = false
			models[i]["position"] = null


func _tf_offer() -> Dictionary:
	for o in B.window_offers(1, "fight_phase_end", {"window_id": "fight_phase_end", "phase": "fight"}):
		if str(o.get("stratagem_id", "")) == B.sid_of("tactical_fluidity"):
			for t in o.get("targets", []):
				if str(t.get("unit_id", "")) == CAPTAIN:
					return t
	return {}


func _tf_use(variant: String) -> Dictionary:
	var c := {"window_id": "fight_phase_end", "phase": "fight"}
	if variant != "":
		c["variant_id"] = variant
	return SM.use_stratagem(1, B.sid_of("tactical_fluidity"), CAPTAIN, c)


func _cap_pos() -> Vector2:
	var p = _u(CAPTAIN).models[0].position
	return Vector2(float(p.x), float(p.y)) / PX


## A synthetic Ork unit of `n` models (32 mm) on a circle of `r_in` inches
## around `c_in`.
func _ring_unit(uid: String, c_in: Vector2, r_in: float, n: int) -> void:
	var models: Array = []
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var p := c_in + Vector2(cos(a), sin(a)) * r_in
		models.append({"id": "r%d" % i, "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32, "base_type": "circular",
			"position": {"x": p.x * PX, "y": p.y * PX}})
	GS.state.units[uid] = {"id": uid, "owner": 2, "status": 2, "flags": {}, "attachment_data": {"attached_characters": []},
		"meta": {"name": "Gretchin Ring", "keywords": ["INFANTRY", "ORKS", "GRETCHIN"], "abilities": [],
			"stats": {"move": 5, "toughness": 2, "save": 7, "wounds": 1, "leadership": 8, "objective_control": 1}},
		"models": models, "weapons": []}


# ---------------------------------------------------------------------------
func _run() -> void:
	GS = root.get_node("GameState")
	SM = root.get_node("StratagemManager")
	RE = root.get_node("RulesEngine")
	PM = root.get_node("PhaseManager")
	B = load("res://scripts/codex/space_marines/SMAbilitiesB.gd")
	SWC = load("res://scripts/codex/space_wolves/SWCommon.gd")
	RM = load("res://scripts/rules/ReactiveMove11e.gd")
	Movement = load("res://scripts/codex/space_marines/SMCodexAMovement.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	root.get_node("SettingsService").set("auto_allocate_wounds", true)
	GameConstants.edition = 11
	print("\n=== test_ea63_out_of_phase_fall_back_11e ===")
	_section_wind_swift()
	_section_tactical_fluidity()
	_section_aircraft()


func _section_wind_swift() -> void:
	print("\n-- WIND-SWIFT EVASION: the fall-back follows the 09.07 modes --")
	_ws_stage()
	var phase = _ws_phase()
	_check("precondition: the Outriders are engaged", SWC.is_engaged(OUTRIDERS))
	var entry := _ws_entry(OUTRIDERS)
	_check("offered on the engaged Outriders as a mode choice: Ordered Retreat or Desperate Escape (require_variant)",
		bool(entry.get("require_variant", false)) and _variant_ids(entry) == ["ordered_retreat", "desperate_escape"]
		and str(entry.get("ai_variant", "")) == "ordered_retreat", str(entry))

	# Chosen Desperate Escape (not battle-shocked): hazard rolls, then the roll.
	var n := _group_alive(OUTRIDERS)
	var log0 := _log_size()
	RE.set_test_seed(9)
	var use: Dictionary = _ws_use(phase, "desperate_escape")
	var fm: Dictionary = phase.sm11e_fight_move
	_check("USE (Desperate Escape): the fall-back move waits for P1 as a desperate escape",
		use.get("success", false) and str(fm.get("move_kind", "")) == "fall_back" and str(fm.get("fall_back_mode", "")) == "desperate_escape",
		"use=%s fm=%s" % [str(use.get("error", use.get("success"))), str(fm.get("fall_back_mode", "<none>"))])
	_check("... one hazard roll per model of the unit (%d) before it moves, in the game log" % n,
		_any_has(_log_since(log0), ["Desperate Escape", "makes %d hazard roll(s)" % n]), str(_log_since(log0)))
	var auto: Dictionary = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_AUTO", "player": 1})
	var conf: Dictionary = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_CONFIRM", "player": 1})
	_check("... Auto-move + Confirm finish it, unengaged", auto.get("success", false) and conf.get("success", false) and not SWC.is_engaged(OUTRIDERS),
		"auto=%s conf=%s" % [str(auto.get("error", auto.get("success"))), str(conf.get("error", conf.get("success")))])
	_check("... and the unit makes its 09.07 battle-shock roll (it was not battle-shocked)",
		_any_has(_log_since(log0), ["Desperate Escape:", "takes a Battle-shock test"]), str(_log_since(log0)))

	# Forced: the Nobz it is engaged with carry Wimp-kickaz (Bully Boyz).
	print("\n-- WIND-SWIFT EVASION forced into Desperate Escape (Wimp-kickaz) --")
	_ws_stage()
	phase = _ws_phase()
	var nobz := ""
	for eid in SWC.engaged_enemy_ids(OUTRIDERS):
		if SWC.has_keyword(_u(str(eid)), "ORKS"):
			nobz = str(eid)
			break
	_check("precondition: an engaged Ork unit (%s)" % nobz, nobz != "")
	if nobz != "":
		_u(nobz).meta["enhancements"] = ["Wimp-kickaz"]
		GS.state.factions["2"]["detachment"] = "Bully Boyz"
		GS.state.factions["2"]["detachments"] = ["Bully Boyz"]
	var sel: Dictionary = MoveTypes.get_type("fall_back").select_mode(OUTRIDERS, GS.state)
	_check("precondition: Wimp-kickaz forces the desperate escape mode", bool(sel.get("mandatory", false)) and str(sel.get("mode", "")) == "desperate_escape", str(sel))
	entry = _ws_entry(OUTRIDERS)
	_check("only Desperate Escape is offered, marked (required)",
		_variant_ids(entry) == ["desperate_escape"] and "(required)" in str(entry.get("variants", [{}])[0].get("label", "")), str(entry))
	var plain: Dictionary = _ws_use(phase, "")
	_check("a plain USE with no option is refused — the mode must be chosen (the window stays open)",
		not plain.get("success", true) and "needs one of its options" in str(plain.get("error", "")) and phase.has_pending_stratagem_window(), str(plain))
	log0 = _log_size()
	n = _group_alive(OUTRIDERS)
	RE.set_test_seed(4)
	use = _ws_use(phase, "desperate_escape")
	fm = phase.sm11e_fight_move
	_check("USE (Desperate Escape, the only option): %d hazard rolls before it moves" % n,
		use.get("success", false) and str(fm.get("fall_back_mode", "")) == "desperate_escape" and _any_has(_log_since(log0), ["makes %d hazard roll(s)" % n]),
		"fm=%s log=%s" % [str(fm.get("fall_back_mode", "<none>")), str(_log_since(log0))])
	phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_AUTO", "player": 1})
	conf = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_CONFIRM", "player": 1})
	_check("forced desperate escape: confirmed AND the battle-shock roll is made (09.07.01: 'Must make a battle-shock roll')",
		conf.get("success", false) and _any_has(_log_since(log0), ["Desperate Escape:", "takes a Battle-shock test"]), str(_log_since(log0)))

	# Ordered Retreat: a translation through the engaged enemy is refused.
	print("\n-- WIND-SWIFT EVASION Ordered Retreat cannot move through enemy models --")
	_ws_stage()
	phase = _ws_phase()
	var enemies: Array = SWC.engaged_enemy_ids(OUTRIDERS)
	var target := _centroid(str(enemies[0])) if not enemies.is_empty() else Vector2.ZERO
	use = _ws_use(phase, "ordered_retreat")
	fm = phase.sm11e_fight_move
	_check("USE (Ordered Retreat): no hazard rolls", use.get("success", false) and str(fm.get("fall_back_mode", "")) == "ordered_retreat", str(fm.get("fall_back_mode", "<none>")))
	var v: Vector2 = (target - _centroid(OUTRIDERS)) * 2.2
	var st: Dictionary = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_STAGE", "player": 1, "payload": {"translation": {"x": v.x, "y": v.y}}})
	var viol: Array = st.get("ork11e_reactive_move", {}).get("violations", [])
	_check("a translation straight through the enemy unit is not a legal Ordered Retreat",
		_any_has(viol, ["an Ordered Retreat cannot move through enemy models"]), str(viol))
	var auto2: Dictionary = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_AUTO", "player": 1})
	_check("Auto-move still finds a legal Ordered Retreat (away from the enemy)",
		auto2.get("success", false) and bool(auto2.get("ork11e_reactive_move", {}).get("valid", false)), str(auto2.get("error", "")))


func _section_tactical_fluidity() -> void:
	print("\n-- TACTICAL FLUIDITY: the fall-back follows the 09.07 modes --")
	var alm = root.get_node("ArmyListManager")
	_sm_army = alm.load_army_list(SM_ARMY, 1)
	_ork_army = alm.load_army_list(ORK_ARMY, 2)
	if _sm_army.is_empty() or _ork_army.is_empty():
		_check("armies load", false)
		return
	_tf_fresh(P_FIGHT, 2)
	_place_at(CAPTAIN, [Vector2(20, 30)])
	_place_at("U_BOYZ_B", [Vector2(19.5, 28.6), Vector2(20.8, 28.6)])
	_check("precondition: the Captain is engaged", SWC.is_engaged(CAPTAIN))
	var entry := _tf_offer()
	_check("offered as a mode choice: Ordered Retreat or Desperate Escape (require_variant)",
		bool(entry.get("require_variant", false)) and _variant_ids(entry) == ["ordered_retreat", "desperate_escape"], str(entry))
	var log0 := _log_size()
	RE.set_test_seed(3)
	var r: Dictionary = _tf_use("desperate_escape")
	var lines := _log_since(log0)
	_check("Desperate Escape: the fall-back is made, after a hazard roll for the Captain's model",
		r.get("success", false) and not SWC.is_engaged(CAPTAIN) and _any_has(lines, ["as Desperate Escape", "1 hazard roll(s)"]), str(lines))
	_check("... and the battle-shock roll is made (not battle-shocked)", _any_has(lines, ["Desperate Escape:", "takes a Battle-shock test"]), str(lines))

	print("\n-- battle-shocked: Desperate Escape only --")
	_tf_fresh(P_FIGHT, 2)
	_place_at(CAPTAIN, [Vector2(20, 30)])
	_place_at("U_BOYZ_B", [Vector2(19.5, 28.6), Vector2(20.8, 28.6)])
	_flags(CAPTAIN)["battle_shocked"] = true
	entry = _tf_offer()
	_check("a battle-shocked unit is offered Desperate Escape only (required)",
		_variant_ids(entry) == ["desperate_escape"] and "(required)" in str(entry.get("variants", [{}])[0].get("label", "")), str(entry))
	log0 = _log_size()
	RE.set_test_seed(5)
	r = _tf_use("desperate_escape")
	lines = _log_since(log0)
	_check("... it makes the hazard roll and falls back", r.get("success", false) and _any_has(lines, ["as Desperate Escape", "hazard roll(s)"]), str(lines))
	_check("... and no battle-shock roll (it is battle-shocked already)", not _any_has(lines, ["takes a Battle-shock test"]), str(lines))

	print("\n-- Ordered Retreat cannot move through enemy models --")
	# A full ring of 12 Gretchin 2" around the Captain: every way out crosses one.
	_tf_fresh(P_FIGHT, 2)
	_place_at(CAPTAIN, [Vector2(20, 30)])
	_ring_unit("U_RING", Vector2(20, 30), 2.0, 12)
	_check("precondition: the Captain is engaged with the ring", SWC.is_engaged(CAPTAIN))
	var p0 := _cap_pos()
	log0 = _log_size()
	r = _tf_use("ordered_retreat")
	lines = _log_since(log0)
	_check("Ordered Retreat: no legal fall-back (every path crosses a Gretchin) — the Captain stays put",
		r.get("success", false) and _cap_pos().distance_to(p0) < 0.01 and _any_has(lines, ["no legal fall-back move as Ordered Retreat"]),
		"moved %.2f\" %s" % [_cap_pos().distance_to(p0), str(lines)])
	_tf_fresh(P_FIGHT, 2)
	_place_at(CAPTAIN, [Vector2(20, 30)])
	_ring_unit("U_RING", Vector2(20, 30), 2.0, 12)
	RE.set_test_seed(8)
	r = _tf_use("desperate_escape")
	_check("Desperate Escape: it moves through the ring and ends unengaged",
		r.get("success", false) and _cap_pos().distance_to(p0) > 3.0 and not SWC.is_engaged(CAPTAIN),
		"moved %.2f\" engaged=%s" % [_cap_pos().distance_to(p0), str(SWC.is_engaged(CAPTAIN))])


## EA-08/EA-63 review (11e 23.02 MOVEMENT): "Each time a unit makes any type of
## move, its models can be moved through AIRCRAFT models." The out-of-phase
## Ordered Retreat crossing check (ReactiveMove11e.validate with
## fall_back_mode, MoveType.path_crosses_enemy_models — WIND-SWIFT EVASION's
## staging / Auto-move / Confirm and Tactical Fluidity's placement) must let an
## AIRCRAFT model be passed. Board: an engaged MOUNTED Outrider (60 mm) with an
## enemy Boy just north of it; an enemy Dakkajet (keywords and 92x120 oval base
## as armies/ork11e_codex_test.json U_DAKKAJET_A) south of it. The fall-back
## goes 9.75" straight south, through the Dakkajet, and ends unengaged.
func _air_unit(id: String, owner: int, kws: Array, pos: Vector2, base: Dictionary) -> Dictionary:
	var m := {"id": "m0", "alive": true, "wounds": 3, "current_wounds": 3, "position": {"x": pos.x, "y": pos.y}}
	m.merge(base)
	return {"id": id, "owner": owner, "status": 2, "flags": {}, "status_effects": {},
		"meta": {"name": id, "keywords": kws, "abilities": [],
			"stats": {"move": 12, "toughness": 5, "save": 3, "wounds": 3, "leadership": 6, "objective_control": 2}},
		"models": [m], "weapons": [], "attachment_data": {}}

func _section_aircraft() -> void:
	print("\n-- 23.02: an Ordered Retreat made outside the Movement phase may pass an enemy AIRCRAFT model --")
	var MT = load("res://scripts/rules/movetypes/MoveType.gd")
	var tm = root.get_node("TerrainManager")
	var prev_terrain: Array = tm.terrain_features.duplicate(true)
	var prev_state: Dictionary = GS.state.duplicate(true)
	tm.terrain_features = []
	var from := Vector2(400, 1000)
	var to := Vector2(400, 1390)
	for jet_kws in [["AIRCRAFT", "DAKKAJET", "FLY", "ORKS", "SPEED FREEKS", "VEHICLE"], ["DAKKAJET", "ORKS", "SPEED FREEKS", "VEHICLE"]]:
		var is_air: bool = "AIRCRAFT" in jet_kws
		var board: Dictionary = prev_state.duplicate(true)
		board["board"]["terrain"] = []
		board["units"] = {
			"U_OUT": _air_unit("U_OUT", 1, ["ADEPTUS ASTARTES", "MOUNTED", "OUTRIDER SQUAD"], from, {"base_mm": 60, "base_type": "circular"}),
			"U_BOY": _air_unit("U_BOY", 2, ["INFANTRY", "ORKS"], Vector2(400, 1000 - 47.24 - 25.2 - 10.0), {"base_mm": 32, "base_type": "circular"}),
			"U_JET": _air_unit("U_JET", 2, jet_kws, Vector2(400, 1000 + 47.24 + 94.5 + 20.0), {"base_mm": 120, "base_type": "oval", "base_dimensions": {"length": 92, "width": 120}})}
		GS.state = board
		var origin := {"U_OUT:0": from}
		var proposed := {"U_OUT:0": to}
		var engaged0: bool = RE.is_unit_engaged("U_OUT", board)
		var engaged1: bool = RE.is_unit_engaged("U_OUT", RM.board_with_positions(board, "U_OUT", proposed))
		var r_or: Dictionary = RM.validate("normal", "U_OUT", origin, proposed, 12.0, {"fall_back_mode": "ordered_retreat"}, board)
		var crosses: bool = MT.path_crosses_enemy_models(board, 1, board.units.U_OUT.models[0], from, to)
		if is_air:
			_check("fixture: engaged at the start, unengaged at the end", engaged0 and not engaged1, "start=%s end=%s" % [str(engaged0), str(engaged1)])
			_check("WIND-SWIFT EVASION Ordered Retreat straight through an enemy Dakkajet is legal", r_or.get("ok", false), str(r_or))
			_check("MoveType.path_crosses_enemy_models: an AIRCRAFT model is not crossed (Tactical Fluidity's placement uses it too)", not crosses)
		else:
			_check("control: the same model without the AIRCRAFT keyword still blocks the Ordered Retreat",
				not r_or.get("ok", true) and _any_has(r_or.get("violations", []), ["an Ordered Retreat cannot move through enemy models"]), str(r_or))
			_check("control: ... and path_crosses_enemy_models reports it", crosses)
	GS.state = prev_state
	tm.terrain_features = prev_terrain
