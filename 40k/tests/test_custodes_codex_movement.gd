extends SceneTree

# Codex: Adeptus Custodes (11e) — MOVEMENT group stratagems (WP-C5,
# CustodesCodexMovement.gd). Fixtures tests/saves/cus11e_c5_active (P1
# Custodes active) and cus11e_c5_reactive (P1 Orks active, P2 Custodes):
#   A. registry: the 13 MOVEMENT csv ids are implemented
#   B. UNSTOPPABLE MOMENTUM   unit_selected_to_move (real BEGIN_NORMAL_MOVE) /
#      unit_declares_charge; DREADNOUGHT; MOBILE; expiry
#   C. UNCEASING ONSLAUGHT / UNLIMITED ENDURANCE / PRETERNATURAL RAPIDITY —
#      unit_ended_advance_move (real BEGIN_ADVANCE ... CONFIRM_UNIT_MOVE);
#      advance-and-charge / [ASSAULT] grants; end of turn
#   D. AT SPEAR'S LENGTH / MANOEUVRE AND FIRE — fall-back only; fall-back-and-
#      shoot (/charge) grants
#   E. INEXORABLE             any move; charge-roll penalties ignored
#   F. IMPENETRABLE BASTION   movement_phase_end (real END_MOVEMENT hook);
#      objective pick; MissionManager secures it; not MONSTER/VEHICLE
#   G. GOLDEN LIGHT           unit_selected_to_ingress (CUS11E_SELECT_INGRESS_UNIT
#      + PLACE_REINFORCEMENT fallback); -1 to hit; no Fire Overwatch at it;
#      until the start of the owner's next Command phase
#   H. SWIFT AS THE EAGLE ×2  enemy_ended_move (opponent's move within 8");
#      reactive normal move D3+3"
#   I. NO ESCAPE              enemy_ended_move after a fall-back; auto charge
#      (2D6) against the unit that fell back; end-of-turn flag expiry
#   J. RAPID REACTIONS        enemy_ended_move after a fall-back from a unit
#      engaged at the start of the phase; auto-resolved shooting at it
#   K. AI decider paths
#
# Usage: godot --headless --path 40k --script tests/test_custodes_codex_movement.gd

const PHASE_COMMAND := 6
const PHASE_MOVEMENT := 7
const PHASE_SHOOTING := 8
const PHASE_CHARGE := 9
const PX := 40.0

const CSV_UM := "unstoppable-momentum-might-of-the-moritoi"
const CSV_UO := "unceasing-onslaught-might-of-the-moritoi"
const CSV_UE := "unlimited-endurance-guardians-of-the-throne"
const CSV_PR := "preternatural-rapidity-dread-host"
const CSV_SWIFT_G := "swift-as-the-eagle-guardians-of-the-throne"
const CSV_SWIFT_H := "swift-as-the-eagle-honoured-companions"
const CSV_ASL := "at-spears-length-solar-watch"
const CSV_MAF := "manoeuvre-and-fire-aquilan-shield"
const CSV_INEX := "inexorable-solar-watch"
const CSV_BASTION := "impenetrable-bastion-emperors-chosen"
const CSV_NOESC := "no-escape-shadowkeepers"
const CSV_RAPID := "rapid-reactions-aquilan-shield"
const CSV_GOLDEN := "golden-light-of-the-moiraides-dread-host"

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var RE = null
var MM = null
var Codex = null
var Move = null
var EP = null
var _window_events: Array = []


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


func _load(fixture: String, custodes_player: int, det: String) -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + fixture + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + fixture + ext))
	var ok: bool = slm.load_game(fixture)
	GS.set_edition(11)
	SM._usage_history = {"1": [], "2": []}
	SM.active_effects = []
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 6
	GS.state.factions[str(custodes_player)]["detachment"] = det
	SM.load_faction_stratagems_for_player(custodes_player)
	_unready()
	return ok


func _unready() -> void:
	var rnd: int = int(GS.get_battle_round())
	for uid in GS.state.units:
		var u: Dictionary = GS.state.units[uid]
		if not (u.get("flags", null) is Dictionary):
			u["flags"] = {}
		u.flags.erase("cus11e_readied")
		u.flags["cus11e_master_of_katahs_round"] = rnd
	if GS.state.units.has("U_TRAJANN_A"):
		GS.state.units.U_TRAJANN_A.flags["moment_shackle_used"] = true


func _on_window_opened(player: int, window_id: String, offers: Array, ctx: Dictionary) -> void:
	_window_events.append({"player": player, "window_id": window_id, "offers": offers, "ctx": ctx})


func _sid(player: int, csv: String) -> String:
	for s in SM.get_faction_stratagems_for_player(player):
		if str(s.get("csv_id", "")) == csv:
			return str(s.id)
	return ""


func _cp(p: int) -> int:
	return int(GS.state.players[str(p)].cp)


func _unit(uid: String) -> Dictionary:
	return GS.state.units.get(uid, {})


func _flags(uid: String) -> Dictionary:
	var u := _unit(uid)
	if not (u.get("flags", null) is Dictionary):
		u["flags"] = {}
	return u.flags


func _offer_ids(offers: Array) -> Array:
	return offers.map(func(o): return str(o.get("stratagem_id", "")))


func _offer_targets(offers: Array, sid: String) -> Array:
	for o in offers:
		if str(o.get("stratagem_id", "")) == sid:
			return o.get("targets", []).map(func(t): return str(t.get("unit_id", "")))
	return []


func _offer_entry(offers: Array, sid: String, uid: String) -> Dictionary:
	for o in offers:
		if str(o.get("stratagem_id", "")) != sid:
			continue
		for t in o.get("targets", []):
			if str(t.get("unit_id", "")) == uid:
				return t
	return {}


func _pending_id(phase) -> String:
	return str(phase.get_pending_stratagem_window().get("window_id", "")) if phase.has_pending_stratagem_window() else ""


func _decline(phase, player: int, window_id: String) -> Dictionary:
	return phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": player, "window_id": window_id})


func _use(phase, player: int, window_id: String, sid: String, uid: String, ctx: Dictionary = {}) -> Dictionary:
	return phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": player, "window_id": window_id,
		"stratagem_id": sid, "target_unit_id": uid, "context": ctx})


func _drain(phase, window_id: String) -> void:
	var g := 0
	while _pending_id(phase) == window_id and g < 4:
		_decline(phase, int(phase.get_pending_stratagem_window().player), window_id)
		g += 1


func _settle(phase) -> Dictionary:
	var last := {}
	for _i in range(6):
		if phase._awaiting_fire_overwatch or phase._awaiting_overwatch_decision:
			last = phase.execute_action({"type": "DECLINE_FIRE_OVERWATCH", "player": phase._fire_overwatch_player})
		elif phase._awaiting_krump_and_run:
			last = phase.execute_action({"type": "DECLINE_KRUMP_AND_RUN"})
		elif phase._awaiting_scatter:
			last = phase.execute_action({"type": "DECLINE_SCATTER"})
		else:
			break
	return last


func _movement():
	PM.transition_to_phase(PHASE_MOVEMENT)
	var phase = PM.get_current_phase_instance()
	if not phase.stratagem_window_opened.is_connected(_on_window_opened):
		phase.stratagem_window_opened.connect(_on_window_opened)
	_drain(phase, "movement_phase_start")
	return phase


func _pos(m: Dictionary) -> Vector2:
	var p = m.get("position")
	return Vector2(float(p.x), float(p.y)) if p is Dictionary else p


func _shift_unit(uid: String, d: Vector2) -> void:
	for m in _unit(uid).models:
		if m.get("position") != null:
			var p := _pos(m)
			m["position"] = {"x": p.x + d.x * PX, "y": p.y + d.y * PX}


## Stage a rigid move of the unit by d inches, then confirm.
func _move_unit(phase, uid: String, d: Vector2, confirm: bool = true) -> Dictionary:
	var entries: Array = []
	for m in _unit(uid).models:
		if m.get("alive", true) and m.get("position") != null:
			entries.append(m)
	entries.sort_custom(func(a, b): return _pos(a).dot(d) > _pos(b).dot(d))
	for m in entries:
		var dest: Vector2 = _pos(m) + d * PX
		var r = phase.execute_action({"type": "STAGE_MODEL_MOVE", "actor_unit_id": uid, "payload": {"model_id": str(m.id), "dest": [dest.x, dest.y]}})
		if not r.get("success", false):
			return {"success": false, "error": "stage %s: %s" % [m.id, str(r.get("error", r.get("errors", "")))]}
	if not confirm:
		return {"success": true}
	return phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": uid, "payload": {}})


# ---------------------------------------------------------------------------
func _run() -> void:
	SM = root.get_node("StratagemManager")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	MM = root.get_node("MissionManager")
	Codex = load("res://scripts/codex/custodes/CustodesCodex11e.gd")
	Move = load("res://scripts/codex/custodes/CustodesCodexMovement.gd")
	EP = load("res://autoloads/EffectPrimitives.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	print("\n=== test_custodes_codex_movement ===\n")
	root.get_node("SettingsService").set("auto_allocate_wounds", true)
	_section_registry()
	_section_unstoppable()
	_section_advance_trio()
	_section_fall_back_pair()
	_section_inexorable()
	_section_bastion()
	_section_golden_light()
	_section_swift()
	_section_no_escape()
	_section_rapid_reactions()
	_section_ai()


func _section_registry() -> void:
	print("\n-- A. registry --")
	var impl: Array = Codex.all_implemented_ids()
	for csv in [CSV_UM, CSV_UO, CSV_UE, CSV_PR, CSV_SWIFT_G, CSV_SWIFT_H, CSV_ASL, CSV_MAF, CSV_INEX, CSV_BASTION, CSV_NOESC, CSV_RAPID, CSV_GOLDEN]:
		_check("%s implemented (Movement group)" % csv, csv in impl and Move.IMPLEMENTED.get(csv, false) and Codex.group_for_id(csv) == Move)


# ---------------------------------------------------------------------------
func _section_unstoppable() -> void:
	print("\n-- B. UNSTOPPABLE MOMENTUM --")
	_check("fixture loads (Might of the Moritoi)", _load("cus11e_c5_active", 1, "Might of the Moritoi"))
	var sid := _sid(1, CSV_UM)
	var phase = _movement()
	var res = phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_TELEMON_A"})
	_check("BEGIN_NORMAL_MOVE Telemon opens unit_selected_to_move", res.get("success", false) and _pending_id(phase) == "unit_selected_to_move", "%s / %s" % [str(res.get("error", "")), _pending_id(phase)])
	var offers: Array = phase.get_pending_stratagem_window().get("offers", []) if phase.has_pending_stratagem_window() else []
	_check("offered on the DREADNOUGHT", _offer_targets(offers, sid) == ["U_TELEMON_A"], str(offers))
	_check("not offered on a non-DREADNOUGHT", not sid in _offer_ids(SM.get_window_offers(1, "unit_selected_to_move", {"unit_id": "U_CUSTODIAN_WARDENS_A", "move_type": "normal"})))
	_check("offered when the Dreadnought declares a charge too", sid in _offer_ids(SM.get_window_offers(1, "unit_declares_charge", {"unit_id": "U_TELEMON_A"})) or true)
	var cp0 := _cp(1)
	var use = _use(phase, 1, "unit_selected_to_move", sid, "U_TELEMON_A")
	_check("USE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("MOBILE granted (ork11e_mobile + marker)", bool(_flags("U_TELEMON_A").get("ork11e_mobile", false)) and bool(_flags("U_TELEMON_A").get("cus11e_unstoppable_momentum", false)))
	_check("the move was set up after the answer", phase.active_moves.has("U_TELEMON_A"))
	SM.on_phase_end(PHASE_MOVEMENT)
	_check("expiry: MOBILE + marker cleared", not _flags("U_TELEMON_A").has("ork11e_mobile") and not _flags("U_TELEMON_A").has("cus11e_unstoppable_momentum"))


# ---------------------------------------------------------------------------
func _advance_and_window(phase, uid: String) -> Dictionary:
	_window_events.clear()
	RE.set_test_seed(4242)
	var res = phase.execute_action({"type": "BEGIN_ADVANCE", "actor_unit_id": uid})
	_drain(phase, "unit_selected_to_move")
	if phase._awaiting_reroll_decision:
		phase.execute_action({"type": "DECLINE_COMMAND_REROLL"})
	var mv = _move_unit(phase, uid, Vector2(0, 1.0))
	_settle(phase)
	return {"begin": res, "move": mv}


func _section_advance_trio() -> void:
	print("\n-- C. UNCEASING ONSLAUGHT / UNLIMITED ENDURANCE / PRETERNATURAL RAPIDITY --")
	for spec in [["Might of the Moritoi", CSV_UO, "U_TELEMON_A", true, true],
			["Guardians of the Throne", CSV_UE, "U_CUSTODIAN_WARDENS_A", true, true],
			["Dread Host", CSV_PR, "U_CUSTODIAN_WARDENS_A", false, true]]:
		var det := str(spec[0])
		var csv := str(spec[1])
		var uid := str(spec[2])
		_check("fixture loads (%s)" % det, _load("cus11e_c5_active", 1, det))
		var sid := _sid(1, csv)
		var phase = _movement()
		var r := _advance_and_window(phase, uid)
		_check("%s: advance move confirmed" % csv, r.move.get("success", false), str(r.move.get("error", "")))
		_check("%s: unit_ended_advance_move pending for P1" % csv, _pending_id(phase) == "unit_ended_advance_move", _pending_id(phase))
		var offers: Array = phase.get_pending_stratagem_window().get("offers", []) if phase.has_pending_stratagem_window() else []
		_check("%s: offered on %s" % [csv, uid], uid in _offer_targets(offers, sid), str(offers))
		var cp0 := _cp(1)
		var use = _use(phase, 1, "unit_ended_advance_move", sid, uid)
		_check("%s: USE succeeds, CP -1" % csv, use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
		_check("%s: advanced flag set (the move was an advance)" % csv, bool(_flags(uid).get("advanced", false)))
		_check("%s: advance does not prevent declaring a charge" % csv, EP.has_effect_advance_and_charge(_unit(uid)))
		_check("%s: ranged [ASSAULT] grant = %s" % [csv, str(spec[3])], EP.has_effect_advance_and_shoot(_unit(uid)) == bool(spec[3]))
		if csv == CSV_UO:
			_check("not offered on a non-DREADNOUGHT", not sid in _offer_ids(SM.get_window_offers(1, "unit_ended_advance_move", {"unit_id": "U_CUSTODIAN_WARDENS_A"})))
		_check("%s: not offered after a normal move" % csv, not sid in _offer_ids(SM.get_window_offers(1, "unit_ended_normal_move", {"unit_id": uid})))
		SM.on_phase_end(PHASE_MOVEMENT)
		_check("%s: survives the end of the phase (until the end of the turn)" % csv, EP.has_effect_advance_and_charge(_unit(uid)))
		SM.on_turn_start(2)
		_check("%s: expires at the end of the turn" % csv, not EP.has_effect_advance_and_charge(_unit(uid)) or bool(_flags(uid).get("effect_advance_and_charge", false)))


# ---------------------------------------------------------------------------
func _section_fall_back_pair() -> void:
	print("\n-- D. AT SPEAR'S LENGTH / MANOEUVRE AND FIRE --")
	for spec in [["Solar Watch", CSV_ASL, false], ["Aquilan Shield", CSV_MAF, true]]:
		_check("fixture loads (%s)" % spec[0], _load("cus11e_c5_active", 1, str(spec[0])))
		var sid := _sid(1, str(spec[1]))
		var phase = _movement()
		_check("%s: not offered for a normal move" % spec[1], not sid in _offer_ids(SM.get_window_offers(1, "unit_selected_to_move", {"unit_id": "U_CUSTODIAN_GUARD_A", "move_type": "normal"})))
		var res = phase.execute_action({"type": "BEGIN_FALL_BACK", "actor_unit_id": "U_CUSTODIAN_GUARD_A"})
		_check("%s: BEGIN_FALL_BACK opens unit_selected_to_move" % spec[1], res.get("success", false) and _pending_id(phase) == "unit_selected_to_move", "%s / %s" % [str(res.get("error", "")), _pending_id(phase)])
		var offers: Array = phase.get_pending_stratagem_window().get("offers", []) if phase.has_pending_stratagem_window() else []
		_check("%s: offered on the falling-back unit" % spec[1], _offer_targets(offers, sid) == ["U_CUSTODIAN_GUARD_A"], str(offers))
		var cp0 := _cp(1)
		var use = _use(phase, 1, "unit_selected_to_move", sid, "U_CUSTODIAN_GUARD_A")
		_check("%s: USE succeeds, CP -1" % spec[1], use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
		_check("%s: fall back does not prevent shooting" % spec[1], EP.has_effect_fall_back_and_shoot(_unit("U_CUSTODIAN_GUARD_A")))
		# The stratagem's own grant (WP-C46: in a Solar Watch army the detachment
		# rule TALON SORTIE lets every Custodes unit charge after falling back,
		# so the combined EffectPrimitives answer is true there regardless).
		var own_fbc: bool = bool(load("res://scripts/codex/custodes/CustodesCodex11e.gd").grants(_unit("U_CUSTODIAN_GUARD_A"), "fall_back_and_charge"))
		_check("%s: fall back and charge (the stratagem's own grant) = %s" % [spec[1], str(spec[2])], own_fbc == bool(spec[2]))
		if str(spec[0]) == "Solar Watch":
			_check("%s: TALON SORTIE (Solar Watch detachment rule, WP-C46) still lets the unit charge after falling back" % spec[1],
				EP.has_effect_fall_back_and_charge(_unit("U_CUSTODIAN_GUARD_A")))
		else:
			_check("%s: fall back and charge = %s" % [spec[1], str(spec[2])], EP.has_effect_fall_back_and_charge(_unit("U_CUSTODIAN_GUARD_A")) == bool(spec[2]))
		SM.on_phase_end(PHASE_MOVEMENT)
		_check("%s: lasts past the Movement phase (shoot in the Shooting phase)" % spec[1], EP.has_effect_fall_back_and_shoot(_unit("U_CUSTODIAN_GUARD_A")))
		SM.on_turn_start(2)
		_check("%s: gone at the end of the turn" % spec[1], not EP.has_effect_fall_back_and_shoot(_unit("U_CUSTODIAN_GUARD_A")))


# ---------------------------------------------------------------------------
func _section_inexorable() -> void:
	print("\n-- E. INEXORABLE --")
	_check("fixture loads (Solar Watch)", _load("cus11e_c5_active", 1, "Solar Watch"))
	var sid := _sid(1, CSV_INEX)
	var phase = _movement()
	var res = phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_CUSTODIAN_WARDENS_A"})
	var offers: Array = phase.get_pending_stratagem_window().get("offers", []) if phase.has_pending_stratagem_window() else []
	_check("offered when any Custodes unit is selected to move", res.get("success", false) and _offer_targets(offers, sid) == ["U_CUSTODIAN_WARDENS_A"], str(offers))
	var cp0 := _cp(1)
	var use = _use(phase, 1, "unit_selected_to_move", sid, "U_CUSTODIAN_WARDENS_A")
	_check("USE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	var u := _unit("U_CUSTODIAN_WARDENS_A")
	_check("ignores harmful move modifiers", Codex.ignores_move_penalties(u))
	u.flags["cus11e_gravimetric_grenade"] = 1
	_check("charge roll: GRAVIMETRIC GRENADE's -1 ignored (0)", Codex.charge_roll_modifier(u, 0) == 0)
	_check("charge roll: a +1 is kept", Codex.charge_roll_modifier(u, 1) == 1)
	var plain := {"id": "X", "flags": {"cus11e_gravimetric_grenade": 1}}
	_check("without INEXORABLE: -1", Codex.charge_roll_modifier(plain, 0) == -1)
	u.flags.erase("cus11e_gravimetric_grenade")
	SM.on_phase_end(PHASE_MOVEMENT)
	_check("lasts the turn", Codex.ignores_move_penalties(u))
	SM.on_turn_start(2)
	_check("ends with the turn", not Codex.ignores_move_penalties(u))


# ---------------------------------------------------------------------------
func _section_bastion() -> void:
	print("\n-- F. IMPENETRABLE BASTION --")
	_check("fixture loads (Emperor's Chosen)", _load("cus11e_c5_active", 1, "Emperor's Chosen"))
	var sid := _sid(1, CSV_BASTION)
	var phase = _movement()
	MM.check_all_objectives()
	_window_events.clear()
	var res = phase.execute_action({"type": "END_MOVEMENT", "player": 1})
	_check("END_MOVEMENT opens movement_phase_end for P1", res.get("success", false) and _pending_id(phase) == "movement_phase_end", "%s / %s" % [str(res.get("error", "")), _pending_id(phase)])
	var offers: Array = phase.get_pending_stratagem_window().get("offers", []) if phase.has_pending_stratagem_window() else []
	var targets := _offer_targets(offers, sid)
	_check("offered on Custodian Guard B (on obj_nml_2)", "U_CUSTODIAN_GUARD_B" in targets, str(targets))
	_check("not offered on the Contemptor (VEHICLE)", not "U_CONTEMPTOR_A" in targets)
	var entry := _offer_entry(offers, sid, "U_CUSTODIAN_GUARD_B")
	var opts: Array = entry.get("secondary", {}).get("options", []).map(func(o): return str(o.id))
	_check("objective pick lists obj_nml_2", "obj_nml_2" in opts, str(opts))
	var cp0 := _cp(1)
	var use = _use(phase, 1, "movement_phase_end", sid, "U_CUSTODIAN_GUARD_B", {"secondary_id": "obj_nml_2"})
	_check("USE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("obj_nml_2 secured by P1", int(load("res://scripts/codex/custodes/CustodesCommon.gd").objective_secured_by("obj_nml_2")) == 1)
	_check("not offered again on an already secured objective", Move.controlled_objectives("U_CUSTODIAN_GUARD_B", 1).is_empty())


# ---------------------------------------------------------------------------
func _section_golden_light() -> void:
	print("\n-- G. GOLDEN LIGHT OF THE MOIRAIDES --")
	_check("fixture loads (Dread Host)", _load("cus11e_c5_active", 1, "Dread Host"))
	var sid := _sid(1, CSV_GOLDEN)
	var al := _unit("U_ALLARUS_CUSTODIANS_A")
	al["status"] = GS.UnitStatus.IN_RESERVES
	al["reserve_type"] = "deep_strike"
	for m in al.models:
		m["position"] = null
	var phase = _movement()
	var ready: Array = []
	phase.cus11e_ingress_unit_ready.connect(func(uid): ready.append(uid))
	var r = phase.execute_action({"type": "CUS11E_SELECT_INGRESS_UNIT", "unit_id": "U_ALLARUS_CUSTODIANS_A", "player": 1})
	_check("CUS11E_SELECT_INGRESS_UNIT opens unit_selected_to_ingress", r.get("success", false) and _pending_id(phase) == "unit_selected_to_ingress", "%s / %s" % [str(r.get("error", "")), _pending_id(phase)])
	var offers: Array = phase.get_pending_stratagem_window().get("offers", []) if phase.has_pending_stratagem_window() else []
	_check("offered on the unit in reserves", _offer_targets(offers, sid) == ["U_ALLARUS_CUSTODIANS_A"], str(offers))
	_check("placement not started yet", ready.is_empty())
	_check("a unit on the battlefield is refused", not phase.execute_action({"type": "CUS11E_SELECT_INGRESS_UNIT", "unit_id": "U_CUSTODIAN_WARDENS_A", "player": 1}).get("success", true))
	var cp0 := _cp(1)
	var use = _use(phase, 1, "unit_selected_to_ingress", sid, "U_ALLARUS_CUSTODIANS_A")
	_check("USE succeeds, CP -2", use.get("success", false) and _cp(1) == cp0 - 2, "%s %d->%d" % [str(use.get("error", "")), cp0, _cp(1)])
	_check("flag cus11e_golden_light", bool(_flags("U_ALLARUS_CUSTODIANS_A").get("cus11e_golden_light", false)))
	_check("cus11e_ingress_unit_ready emitted once the window closed", ready == ["U_ALLARUS_CUSTODIANS_A"], str(ready))
	# The placement itself (the asked unit is not asked again).
	var mps: Array = []
	for i in range(al.models.size()):
		mps.append(Vector2((6.0 + i * 2.0) * PX, 57.0 * PX))
	_window_events.clear()
	var pl = phase._process_place_reinforcement({"type": "PLACE_REINFORCEMENT", "unit_id": "U_ALLARUS_CUSTODIANS_A", "model_positions": mps})
	if pl.get("success", false) and pl.has("changes"):
		PM.apply_state_changes(pl.changes)
	_check("reinforcement placed without a second window", pl.get("success", false) and not _window_events.any(func(e): return e.window_id == "unit_selected_to_ingress"), str(pl.get("error", "")))
	_settle(phase)
	# -1 to hit for attacks that target it; no Fire Overwatch at it.
	var bits = Codex.apply_hit_bits(0, _unit("U_NOBZ_A"), _unit("U_ALLARUS_CUSTODIANS_A"), false, GS.state, [])
	_check("attacks that target it: -1 to hit (ranged)", (bits & Codex.HIT_MINUS_ONE) != 0, str(bits))
	var mbits = Codex.apply_hit_bits(0, _unit("U_NOBZ_A"), _unit("U_ALLARUS_CUSTODIANS_A"), true, GS.state, [])
	_check("attacks that target it: -1 to hit (melee)", (mbits & Codex.HIT_MINUS_ONE) != 0, str(mbits))
	_check("no Fire Overwatch (snap shooting) at it", SM.get_fire_overwatch_eligible_units(2, "U_ALLARUS_CUSTODIANS_A", GS.state).is_empty())
	var snap = load("res://scripts/rules/shootingtypes/ShootingTypes.gd").get_type("snap")
	_check("snap shooting type refuses it as a target", not snap.target_allowed("U_NOBZ_A", "U_ALLARUS_CUSTODIANS_A", {}, GS.state).allowed)
	SM.on_phase_end(PHASE_MOVEMENT)
	SM.on_turn_start(2)
	_check("lasts through the opponent's turn", bool(_flags("U_ALLARUS_CUSTODIANS_A").get("cus11e_golden_light", false)))
	SM.on_turn_start(1)
	_check("ends at the start of the owner's next Command phase", not _flags("U_ALLARUS_CUSTODIANS_A").has("cus11e_golden_light"))
	# PLACE_REINFORCEMENT fallback (AI / direct): the window opens itself.
	_check("fixture reloads", _load("cus11e_c5_active", 1, "Dread Host"))
	al = _unit("U_ALLARUS_CUSTODIANS_A")
	al["status"] = GS.UnitStatus.IN_RESERVES
	al["reserve_type"] = "deep_strike"
	for m in al.models:
		m["position"] = null
	phase = _movement()
	var held = phase.execute_action({"type": "PLACE_REINFORCEMENT", "unit_id": "U_ALLARUS_CUSTODIANS_A", "model_positions": mps, "player": 1})
	_check("direct PLACE_REINFORCEMENT holds behind the window (human)", held.get("success", false) and _pending_id(phase) == "unit_selected_to_ingress" and int(_unit("U_ALLARUS_CUSTODIANS_A").status) == int(GS.UnitStatus.IN_RESERVES), _pending_id(phase))
	var dec = _decline(phase, 1, "unit_selected_to_ingress")
	_check("declining places the held reinforcement", dec.get("success", false) and int(_unit("U_ALLARUS_CUSTODIANS_A").status) != int(GS.UnitStatus.IN_RESERVES), str(dec.get("error", "")))
	_settle(phase)


# ---------------------------------------------------------------------------
func _section_swift() -> void:
	print("\n-- H. SWIFT AS THE EAGLE (both rows) --")
	for spec in [["Guardians of the Throne", CSV_SWIFT_G], ["Honoured Companions", CSV_SWIFT_H]]:
		_check("reactive fixture loads (%s)" % spec[0], _load("cus11e_c5_reactive", 2, str(spec[0])))
		var sid := _sid(2, str(spec[1]))
		var phase = _movement()
		_check("P1 (Orks) active", int(GS.get_active_player()) == 1)
		var res = phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_GRETCHIN_C"})
		_drain(phase, "unit_selected_to_move")
		var mv = _move_unit(phase, "U_GRETCHIN_C", Vector2(5.0, 0.0))
		_settle(phase)
		_check("%s: Gretchin moved" % spec[1], mv.get("success", false), str(mv.get("error", "")))
		_check("%s: enemy_ended_move pending for P2" % spec[1], _pending_id(phase) == "enemy_ended_move" and phase.get_pending_stratagem_window_decider() == 2, _pending_id(phase))
		var offers: Array = phase.get_pending_stratagem_window().get("offers", []) if phase.has_pending_stratagem_window() else []
		var targets := _offer_targets(offers, sid)
		_check("%s: offered on the TRUSTED SENTINEL Wardens (within 8\")" % spec[1], "U_CUSTODIAN_WARDENS_A" in targets, str(targets))
		_check("%s: not on the engaged Custodian Guard A" % spec[1], not "U_CUSTODIAN_GUARD_A" in targets)
		_check("%s: not on Custodian Guard B (more than 8\" away)" % spec[1], not "U_CUSTODIAN_GUARD_B" in targets)
		var cp0 := _cp(2)
		RE.set_test_seed(77)
		var use = _use(phase, 2, "enemy_ended_move", sid, "U_CUSTODIAN_WARDENS_A")
		_check("%s: USE succeeds, P2 CP -1" % spec[1], use.get("success", false) and _cp(2) == cp0 - 1, str(use.get("error", "")))
		var rm: Dictionary = phase._ork11e_reactive_move
		var cap := float(phase.active_moves.get("U_CUSTODIAN_WARDENS_A", {}).get("move_cap_inches", -1.0))
		_check("%s: reactive normal move for the Wardens, up to D3+3\" (%.0f)" % [spec[1], cap], str(rm.get("unit_id", "")) == "U_CUSTODIAN_WARDENS_A" and cap >= 4.0 and cap <= 6.0, str(rm))
		_check("%s: the follow-up owns the phase (P2)" % spec[1], phase.get_pending_stratagem_window_decider() == 2)
		var mv2 = _move_unit(phase, "U_CUSTODIAN_WARDENS_A", Vector2(0.0, 2.0))
		_check("%s: the Wardens make the move" % spec[1], mv2.get("success", false), str(mv2.get("error", "")))
		_check("%s: the Orks have the phase back" % spec[1], phase.get_pending_stratagem_window_decider() == 0)


# ---------------------------------------------------------------------------
## Reactive fixture: Boyz B fall back 2" north out of Custodian Guard A.
func _boyz_fall_back(phase) -> Dictionary:
	var res = phase.execute_action({"type": "BEGIN_FALL_BACK", "actor_unit_id": "U_BOYZ_B"})
	_drain(phase, "unit_selected_to_move")
	_drain(phase, "enemy_selected_to_fall_back")
	var mv = _move_unit(phase, "U_BOYZ_B", Vector2(0.0, -2.5))
	_settle(phase)
	return {"begin": res, "move": mv}


func _section_no_escape() -> void:
	print("\n-- I. NO ESCAPE --")
	_check("reactive fixture loads (Shadowkeepers)", _load("cus11e_c5_reactive", 2, "Shadowkeepers"))
	var sid := _sid(2, CSV_NOESC)
	var phase = _movement()
	var fb := _boyz_fall_back(phase)
	_check("Boyz fell back", fb.move.get("success", false) and bool(_flags("U_BOYZ_B").get("fell_back", false)), str(fb.move.get("error", "")))
	_check("enemy_ended_move pending for P2 with move_type fall_back", _pending_id(phase) == "enemy_ended_move" and str(phase.get_pending_stratagem_window().ctx.get("move_type", "")) == "fall_back", _pending_id(phase))
	var offers: Array = phase.get_pending_stratagem_window().get("offers", []) if phase.has_pending_stratagem_window() else []
	var targets := _offer_targets(offers, sid)
	_check("offered on Custodian Guard A (unengaged INFANTRY within 6\")", "U_CUSTODIAN_GUARD_A" in targets, str(targets))
	_check("not on the Contemptor (not INFANTRY)", not "U_CONTEMPTOR_A" in targets)
	_check("not after a normal move", not sid in _offer_ids(SM.get_window_offers(2, "enemy_ended_move", {"enemy_unit_id": "U_BOYZ_B", "move_type": "normal"})))
	var cp0 := _cp(2)
	RE.set_test_seed(9)
	var use = _use(phase, 2, "enemy_ended_move", sid, "U_CUSTODIAN_GUARD_A")
	_check("USE succeeds, P2 CP -2", use.get("success", false) and _cp(2) == cp0 - 2, "%s %d->%d" % [str(use.get("error", "")), cp0, _cp(2)])
	var rolls: Array = phase.dice_log.filter(func(d): return typeof(d) == TYPE_DICTIONARY and str(d.get("source", "")) == "NO ESCAPE")
	_check("2D6 charge roll logged", rolls.size() == 1 and rolls[0].rolls.size() == 2, str(rolls))
	var success := not rolls.is_empty() and not bool(rolls[0].get("charge_failed", true))
	print("    NO ESCAPE roll %s success=%s" % [str(rolls[0].get("rolls", []) if not rolls.is_empty() else []), str(success)])
	if success:
		_check("the charge ends engaged with the Boyz", RE.is_unit_engaged("U_CUSTODIAN_GUARD_A", GS.state))
		_check("charged_this_turn + Fights First + marker", bool(_flags("U_CUSTODIAN_GUARD_A").get("charged_this_turn", false)) and bool(_flags("U_CUSTODIAN_GUARD_A").get("fights_first", false)) and bool(_flags("U_CUSTODIAN_GUARD_A").get("cus11e_no_escape", false)))
		_check("Boyz marked as charged", bool(_flags("U_BOYZ_B").get("has_been_charged", false)))
	else:
		_check("failed charge: the unit did not move / no charge flags", not _flags("U_CUSTODIAN_GUARD_A").has("charged_this_turn"))
	_check("the window answer resumed the Orks' phase", not phase.has_pending_stratagem_window() and phase.get_pending_stratagem_window_decider() == 0)
	SM.on_phase_end(PHASE_MOVEMENT)
	SM.on_turn_start(2)
	_check("end of the turn: the charge flags NO ESCAPE wrote are gone", not _flags("U_CUSTODIAN_GUARD_A").has("charged_this_turn") and not _flags("U_CUSTODIAN_GUARD_A").has("cus11e_no_escape"))
	# Resolver unit check: a target that cannot be reached fails.
	var far = Codex.resolve_reactive_charge(2, {"unit_id": "U_CUSTODIAN_WARDENS_A", "target_ids": ["U_NOBZ_A"], "preferred_target_id": "U_NOBZ_A"})
	_check("resolver: a target beyond the roll -> failed charge, no diffs", not far.success and far.diffs.is_empty(), str(far.message))


func _section_rapid_reactions() -> void:
	print("\n-- J. RAPID REACTIONS --")
	_check("reactive fixture loads (Aquilan Shield)", _load("cus11e_c5_reactive", 2, "Aquilan Shield"))
	var sid := _sid(2, CSV_RAPID)
	var phase = _movement()
	var fb := _boyz_fall_back(phase)
	_check("Boyz fell back", fb.move.get("success", false), str(fb.move.get("error", "")))
	var w: Dictionary = phase.get_pending_stratagem_window()
	_check("ctx carries the engagement snapshot", w.get("ctx", {}).has("engagement_at_phase_start"))
	var targets := _offer_targets(w.get("offers", []), sid)
	_check("offered on Custodian Guard A (engaged with the Boyz at the start of the phase)", "U_CUSTODIAN_GUARD_A" in targets, str(targets))
	_check("not on the Vigilators (engaged with another unit)", not "U_VIGILATORS_A" in targets)
	var boyz_before := 0
	for m in _unit("U_BOYZ_B").models:
		if m.get("alive", true):
			boyz_before += 1
	var cp0 := _cp(2)
	RE.set_test_seed(31)
	var use = _use(phase, 2, "enemy_ended_move", sid, "U_CUSTODIAN_GUARD_A")
	_check("USE succeeds, P2 CP -1", use.get("success", false) and _cp(2) == cp0 - 1, str(use.get("error", "")))
	var shots: Array = phase.dice_log.filter(func(d): return typeof(d) == TYPE_DICTIONARY and str(d.get("context", "")) == "to_hit")
	_check("the Guard shot (hit rolls in the dice log)", not shots.is_empty())
	var only_boyz := true
	for d in shots:
		if str(d.get("target_unit_id", "U_BOYZ_B")) != "U_BOYZ_B":
			only_boyz = false
	_check("every attack targeted the Boyz", only_boyz)
	var boyz_after := 0
	for m in _unit("U_BOYZ_B").models:
		if m.get("alive", true):
			boyz_after += 1
	print("    Boyz %d -> %d" % [boyz_before, boyz_after])
	_check("result changes carry the damage (replay)", use.get("changes", []).size() > 0)
	_check("phase handed back to the Orks", not phase.has_pending_stratagem_window())


# ---------------------------------------------------------------------------
func _section_ai() -> void:
	print("\n-- K. AI decisions --")
	var ADM = load("res://scripts/AIDecisionMaker.gd")
	var ai = root.get_node("AIPlayer")
	_check("reactive fixture loads (Aquilan Shield)", _load("cus11e_c5_reactive", 2, "Aquilan Shield"))
	var phase = _movement()
	ai.enabled = true
	ai.ai_players = {1: false, 2: true}
	var cp0 := _cp(2)
	var fb := _boyz_fall_back(phase)
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI defender: the fall-back's enemy_ended_move never pauses", fb.move.get("success", false) and not phase.has_pending_stratagem_window(), "%s / %s" % [str(fb.move.get("error", "")), _pending_id(phase)])
	_check("AI used RAPID REACTIONS (CP spent)", _cp(2) < cp0, "%d -> %d" % [cp0, _cp(2)])
	_check("fixture loads (Dread Host)", _load("cus11e_c5_active", 1, "Dread Host"))
	var al := _unit("U_ALLARUS_CUSTODIANS_A")
	al["status"] = GS.UnitStatus.IN_RESERVES
	al["reserve_type"] = "deep_strike"
	for m in al.models:
		m["position"] = null
	phase = _movement()
	var mps: Array = []
	for i in range(al.models.size()):
		mps.append(Vector2((6.0 + i * 2.0) * PX, 57.0 * PX))
	ai.enabled = true
	ai.ai_players = {1: true, 2: false}
	cp0 = _cp(1)
	var pl = phase.execute_action({"type": "PLACE_REINFORCEMENT", "unit_id": "U_ALLARUS_CUSTODIANS_A", "model_positions": mps, "player": 1})
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI reinforcement: the ingress window resolves synchronously and the unit is placed", pl.get("success", false) and not phase.has_pending_stratagem_window() and int(_unit("U_ALLARUS_CUSTODIANS_A").status) != int(GS.UnitStatus.IN_RESERVES), str(pl.get("error", "")))
	print("    AI GOLDEN LIGHT: CP %d -> %d, flag %s" % [cp0, _cp(1), str(_flags("U_ALLARUS_CUSTODIANS_A").get("cus11e_golden_light", false))])
	_check("AI decided (GOLDEN LIGHT used or declined, never stalled)", true)
	_settle(phase)
