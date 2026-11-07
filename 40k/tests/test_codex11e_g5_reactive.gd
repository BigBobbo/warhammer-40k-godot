extends SceneTree

# WP-G5 — player-controlled Codex: Adeptus Custodes (11e) reactive stratagems
# (scripts/codex/custodes/CustodesReactive.gd). Fixtures cus11e_c5_reactive
# (P1 Orks active, P2 Custodes) and cus11e_c5_active (the same board, P1
# Custodes — made the NON-active player here for the P1 cases):
#   A. NO ESCAPE (human, P2)  enemy_ended_move -> USE pauses -> ROLL -> only
#      fell-back units within the roll selectable -> TARGETS -> drag (STAGE)
#      -> End This Unit's Move judged as a charge (too short refused, then
#      engaged) -> charge flags, phase handed back, flags expire at turn end
#   B. NO ESCAPE give-up / nothing moved -> the charge fails, no move
#   C. NO ESCAPE (human, P1 Custodes in P2's turn)
#   D. NO ESCAPE (AI decider) keeps the auto path, never pauses
#   E. SELFLESS SERVICE (human) -> ROLL capped at 6 -> ANY enemy within 6"
#      selectable (two targets) -> the move must engage every selected
#      target -> give up / real move -> the end of the phase continues
#   F. SELFLESS SERVICE (AI decider) keeps the auto path
#   G. RAPID REACTIONS (human) -> weapon choices only at the fell-back unit
#      -> SHOOT with the chosen weapons -> attacks only at that unit; Don't shoot
#   H. RAPID REACTIONS (AI decider) keeps the auto path
#
# Usage: godot --headless --path 40k --script tests/test_codex11e_g5_reactive.gd

const PHASE_COMMAND := 6
const PHASE_MOVEMENT := 7
const PHASE_CHARGE := 9
const PX := 40.0

const CSV_NOESC := "no-escape-shadowkeepers"
const CSV_RAPID := "rapid-reactions-aquilan-shield"
const CSV_SELFLESS := "selfless-service-emissaries-imperatus"

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var RE = null
var R = null
var Common = null
var ADM = null


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
func _load(fixture: String, custodes_player: int, det: String) -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + fixture + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + fixture + ext))
	var ok: bool = slm.load_game(fixture)
	GS.set_edition(11)
	GameConstants.edition = 11
	SM._usage_history = {"1": [], "2": []}
	SM.active_effects = []
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 6
	GS.state.factions[str(custodes_player)]["detachment"] = det
	SM.load_faction_stratagems_for_player(custodes_player)
	var rnd: int = int(GS.get_battle_round())
	for uid in GS.state.units:
		var u: Dictionary = GS.state.units[uid]
		if not (u.get("flags", null) is Dictionary):
			u["flags"] = {}
		u.flags.erase("cus11e_readied")
		u.flags["cus11e_master_of_katahs_round"] = rnd
	if GS.state.units.has("U_TRAJANN_A"):
		GS.state.units.U_TRAJANN_A.flags["moment_shackle_used"] = true
	return ok


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


func _pending_id(phase) -> String:
	return str(phase.get_pending_stratagem_window().get("window_id", "")) if phase.has_pending_stratagem_window() else ""


func _offer_targets(phase, sid: String) -> Array:
	if not phase.has_pending_stratagem_window():
		return []
	for o in phase.get_pending_stratagem_window().get("offers", []):
		if str(o.get("stratagem_id", "")) == sid:
			return o.get("targets", []).map(func(t): return str(t.get("unit_id", "")))
	return []


func _decline_all(phase, only_window: String = "") -> void:
	var g := 0
	while phase != null and phase.has_pending_stratagem_window() and g < 8:
		var w: Dictionary = phase.get_pending_stratagem_window()
		if only_window != "" and str(w.window_id) != only_window:
			break
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.player), "window_id": str(w.window_id)})
		g += 1


func _use(phase, player: int, window_id: String, sid: String, uid: String) -> Dictionary:
	return phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": player, "window_id": window_id,
		"stratagem_id": sid, "target_unit_id": uid, "context": {}})


func _pos(m: Dictionary) -> Vector2:
	var p = m.get("position")
	return Vector2(float(p.x), float(p.y)) if p is Dictionary else p


func _stage_rigid(phase, uid: String, d: Vector2) -> Dictionary:
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
	return {"success": true}


func _settle(phase) -> void:
	for _i in range(6):
		if phase._awaiting_fire_overwatch or phase._awaiting_overwatch_decision:
			phase.execute_action({"type": "DECLINE_FIRE_OVERWATCH", "player": phase._fire_overwatch_player})
		elif phase._awaiting_krump_and_run:
			phase.execute_action({"type": "DECLINE_KRUMP_AND_RUN"})
		elif phase._awaiting_scatter:
			phase.execute_action({"type": "DECLINE_SCATTER"})
		else:
			break


func _movement():
	PM.transition_to_phase(PHASE_MOVEMENT)
	var phase = PM.get_current_phase_instance()
	_decline_all(phase, "movement_phase_start")
	_decline_all(phase, "phase_start")
	return phase


## The active player's `uid` falls back by d inches (BEGIN_FALL_BACK + drag + confirm).
func _fall_back(phase, uid: String, player: int, d: Vector2) -> Dictionary:
	var res = phase.execute_action({"type": "BEGIN_FALL_BACK", "actor_unit_id": uid, "player": player})
	_decline_all(phase, "unit_selected_to_move")
	_decline_all(phase, "enemy_selected_to_fall_back")
	var st := _stage_rigid(phase, uid, d)
	if not st.success:
		return st
	var c = phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": uid, "payload": {}, "player": player})
	_settle(phase)
	return c if res.get("success", false) else res


## A test seed whose first two D6 (CustodesCommon.roll_dice) sum to >= want.
func _seed_for(want: int, max_sum: int = 12) -> int:
	for s in range(1, 400):
		RE.set_test_seed(s)
		var r: Array = Common.roll_dice(2, 6)
		var t := int(r[0]) + int(r[1])
		if t >= want and t <= max_sum:
			return s
	return 1


func _dice(phase, source: String) -> Array:
	return phase.dice_log.filter(func(d): return typeof(d) == TYPE_DICTIONARY and str(d.get("source", "")) == source)


# ---------------------------------------------------------------------------
func _run() -> void:
	SM = root.get_node("StratagemManager")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	R = load("res://scripts/codex/custodes/CustodesReactive.gd")
	Common = load("res://scripts/codex/custodes/CustodesCommon.gd")
	ADM = load("res://scripts/AIDecisionMaker.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	root.get_node("SettingsService").set("auto_allocate_wounds", true)
	print("\n=== test_codex11e_g5_reactive ===\n")
	_section_no_escape_human()
	_section_no_escape_give_up()
	_section_no_escape_p1()
	_section_no_escape_ai()
	_section_selfless_human()
	_section_selfless_ai()
	_section_rapid_human()
	_section_rapid_ai()
	RE.set_test_seed(-1)


# ---------------------------------------------------------------------------
## Boyz B (P1) fall back 2.5" north out of Custodian Guard A (P2); returns the
## phase with P2's enemy_ended_move pending.
func _reactive_fall_back(det: String):
	_load("cus11e_c5_reactive", 2, det)
	var phase = _movement()
	var fb := _fall_back(phase, "U_BOYZ_B", 1, Vector2(0.0, -2.5))
	_check("[%s] Boyz fell back; enemy_ended_move pending for P2" % det, fb.get("success", false) and _pending_id(phase) == "enemy_ended_move"
		and int(phase.get_pending_stratagem_window().player) == 2, "%s / %s" % [str(fb.get("error", "")), _pending_id(phase)])
	return phase


func _section_no_escape_human() -> void:
	print("\n-- A. NO ESCAPE (human P2) --")
	var phase = _reactive_fall_back("Shadowkeepers")
	var sid := _sid(2, CSV_NOESC)
	_check("offered on Custodian Guard A", "U_CUSTODIAN_GUARD_A" in _offer_targets(phase, sid), str(_offer_targets(phase, sid)))
	var cp0 := _cp(2)
	var use = _use(phase, 2, "enemy_ended_move", sid, "U_CUSTODIAN_GUARD_A")
	var g: Dictionary = phase._cus11e_g5
	_check("USE succeeds, CP -2, the human flow owns the phase (stage roll)", use.get("success", false) and _cp(2) == cp0 - 2 and str(g.get("stage", "")) == "roll" and str(g.get("unit_id", "")) == "U_CUSTODIAN_GUARD_A", "%s %s" % [str(use.get("error", "")), str(g)])
	_check("no charge roll yet (the human rolls)", _dice(phase, "NO ESCAPE").is_empty())
	_check("decider = P2 (AI opponent idles)", phase.get_pending_stratagem_window_decider() == 2)
	var em = phase.execute_action({"type": "END_MOVEMENT", "player": 1})
	_check("the Ork player cannot end the phase meanwhile", not em.get("success", false))
	var early = phase.execute_action({"type": R.ACT_TARGETS, "player": 2, "payload": {"target_ids": ["U_BOYZ_B"]}})
	_check("targets before the roll are refused", not early.get("success", false))
	var wrong = phase.execute_action({"type": R.ACT_ROLL, "player": 1})
	_check("the opponent cannot roll it", not wrong.get("success", false))
	RE.set_test_seed(_seed_for(7))
	var roll = phase.execute_action({"type": R.ACT_ROLL, "player": 2})
	g = phase._cus11e_g5
	var rd := _dice(phase, "NO ESCAPE")
	_check("ROLL: 2D6 logged (source NO ESCAPE)", roll.get("success", false) and rd.size() == 1 and rd[0].rolls.size() == 2, "%s %s" % [str(roll.get("error", "")), str(rd)])
	print("    NO ESCAPE roll %s = %d, selectable %s" % [str(g.get("rolls", [])), int(g.get("roll", 0)), str(g.get("selectable", []))])
	_check("only units that fell back this phase are selectable (Boyz B, not the Meganobz)", g.get("selectable", []) == ["U_BOYZ_B"], str(g.get("selectable", [])))
	_check("result carries the dialog info", roll.has("cus11e_reactive_charge") and str(roll.cus11e_reactive_charge.get("stage", "")) == "targets")
	var bad = phase.execute_action({"type": R.ACT_TARGETS, "player": 2, "payload": {"target_ids": ["U_MEGANOBZ_A"]}})
	_check("a unit that did not fall back is refused as a target", not bad.get("success", false), str(bad.get("error", "")))
	var none = phase.execute_action({"type": R.ACT_TARGETS, "player": 2, "payload": {"target_ids": []}})
	_check("an empty target list is refused", not none.get("success", false))
	var tg = phase.execute_action({"type": R.ACT_TARGETS, "player": 2, "payload": {"target_ids": ["U_BOYZ_B"]}})
	var md: Dictionary = phase.active_moves.get("U_CUSTODIAN_GUARD_A", {})
	_check("TARGETS: the reactive charge move is set up (cap = roll, charge marker, owner P2)", tg.get("success", false) and md.has(R.ACTIVE_MOVE_KEY)
		and is_equal_approx(float(md.get("move_cap_inches", 0)), float(g.roll)) and phase._reactive_move_owner == 2 and str(phase._ork11e_reactive_move.get("unit_id", "")) == "U_CUSTODIAN_GUARD_A",
		"%s %s" % [str(tg.get("error", "")), str(md.keys())])
	var other = phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_NOBZ_A", "player": 1})
	_check("other units cannot move during the charge move", not other.get("success", false))
	# Too short: 0.5" — not engaged with the Boyz.
	var st := _stage_rigid(phase, "U_CUSTODIAN_GUARD_A", Vector2(0, -0.5))
	_check("a model may be staged (drag)", st.success, str(st.get("error", "")))
	var short = phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_A", "payload": {}, "player": 2})
	_check("End This Unit's Move short of engagement is refused (charge rules)", not short.get("success", false) and phase.active_moves.has("U_CUSTODIAN_GUARD_A") and not phase._cus11e_g5.is_empty(), str(short.get("error", "")))
	print("    refusal: %s" % str(short.get("error", "")))
	phase.execute_action({"type": "RESET_UNIT_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_A", "player": 2})
	# Staging may end engaged (a charge), unlike a normal move.
	st = _stage_rigid(phase, "U_CUSTODIAN_GUARD_A", Vector2(0, -2.6))
	_check("a charging model may be staged into engagement range", st.success, str(st.get("error", "")))
	var ok = phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_A", "payload": {}, "player": 2})
	_check("End This Unit's Move: the charge is made", ok.get("success", false), str(ok.get("error", "")))
	_check("Custodian Guard A ends engaged with the Boyz", Common.group_engaged_with("U_CUSTODIAN_GUARD_A", "U_BOYZ_B"))
	_check("charged_this_turn + Fights First + NO ESCAPE marker", bool(_flags("U_CUSTODIAN_GUARD_A").get("charged_this_turn", false)) and bool(_flags("U_CUSTODIAN_GUARD_A").get("fights_first", false)) and bool(_flags("U_CUSTODIAN_GUARD_A").get("cus11e_no_escape", false)))
	_check("Boyz marked has_been_charged", bool(_flags("U_BOYZ_B").get("has_been_charged", false)))
	_check("it is a charge, not a move (flags.moved not set)", not bool(_flags("U_CUSTODIAN_GUARD_A").get("moved", false)))
	_check("the phase is handed back to the Orks", phase._cus11e_g5.is_empty() and phase._ork11e_reactive_move.is_empty() and phase.get_pending_stratagem_window_decider() == 0 and not phase.has_pending_stratagem_window())
	_check("the confirm result carries the position diffs (replay)", ok.get("changes", []).any(func(c): return str(c.get("path", "")).ends_with(".position")))
	var nm = phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_NOBZ_A", "player": 1})
	_check("the Ork player moves on", nm.get("success", false) or _pending_id(phase) != "", str(nm.get("error", "")))
	SM.on_phase_end(PHASE_MOVEMENT)
	SM.on_turn_start(2)
	_check("end of the turn: the NO ESCAPE charge flags expire", not _flags("U_CUSTODIAN_GUARD_A").has("charged_this_turn") and not _flags("U_CUSTODIAN_GUARD_A").has("cus11e_no_escape"))


func _section_no_escape_give_up() -> void:
	print("\n-- B. NO ESCAPE give up / nothing moved --")
	var phase = _reactive_fall_back("Shadowkeepers")
	var sid := _sid(2, CSV_NOESC)
	_use(phase, 2, "enemy_ended_move", sid, "U_CUSTODIAN_GUARD_A")
	RE.set_test_seed(_seed_for(7))
	phase.execute_action({"type": R.ACT_ROLL, "player": 2})
	var fail = phase.execute_action({"type": R.ACT_FAIL, "player": 2})
	_check("CUS11E_REACTIVE_CHARGE_FAIL at the target step: the charge fails, nothing moves", fail.get("success", false) and phase._cus11e_g5.is_empty() and not _flags("U_CUSTODIAN_GUARD_A").has("charged_this_turn") and phase.get_pending_stratagem_window_decider() == 0, str(fail.get("error", "")))
	# Nothing moved at End This Unit's Move = a failed charge.
	phase = _reactive_fall_back("Shadowkeepers")
	var before := _pos(_unit("U_CUSTODIAN_GUARD_A").models[0])
	_use(phase, 2, "enemy_ended_move", sid, "U_CUSTODIAN_GUARD_A")
	RE.set_test_seed(_seed_for(7))
	phase.execute_action({"type": R.ACT_ROLL, "player": 2})
	phase.execute_action({"type": R.ACT_TARGETS, "player": 2, "payload": {"target_ids": ["U_BOYZ_B"]}})
	var still = phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_A", "payload": {}, "player": 2})
	_check("End This Unit's Move with nothing moved: the charge fails, the phase continues", still.get("success", false) and phase._cus11e_g5.is_empty() and phase._ork11e_reactive_move.is_empty() and phase.get_pending_stratagem_window_decider() == 0, str(still.get("error", "")))
	_check("the unit did not move / no charge flags", _pos(_unit("U_CUSTODIAN_GUARD_A").models[0]) == before and not _flags("U_CUSTODIAN_GUARD_A").has("charged_this_turn"))
	# Fail during the move stage (the bar's button).
	phase = _reactive_fall_back("Shadowkeepers")
	_use(phase, 2, "enemy_ended_move", sid, "U_CUSTODIAN_GUARD_A")
	RE.set_test_seed(_seed_for(7))
	phase.execute_action({"type": R.ACT_ROLL, "player": 2})
	phase.execute_action({"type": R.ACT_TARGETS, "player": 2, "payload": {"target_ids": ["U_BOYZ_B"]}})
	_stage_rigid(phase, "U_CUSTODIAN_GUARD_A", Vector2(0, -1.0))
	var mid = phase.execute_action({"type": R.ACT_FAIL, "player": 2})
	_check("FAIL during the move: staged models discarded, the phase continues", mid.get("success", false) and phase._ork11e_reactive_move.is_empty() and _pos(_unit("U_CUSTODIAN_GUARD_A").models[0]) == before and phase.get_pending_stratagem_window_decider() == 0, str(mid.get("error", "")))
	# A roll too low for any target: the charge fails at once.
	phase = _reactive_fall_back("Shadowkeepers")
	_use(phase, 2, "enemy_ended_move", sid, "U_CUSTODIAN_GUARD_A")
	RE.set_test_seed(_seed_for(2, 3))
	var low = phase.execute_action({"type": R.ACT_ROLL, "player": 2})
	_check("a roll of 2-3 (gap ~3.5\"): no legal target -> the charge fails, phase handed back", low.get("success", false) and phase._cus11e_g5.is_empty() and phase.get_pending_stratagem_window_decider() == 0 and bool(_dice(phase, "NO ESCAPE")[-1].get("charge_failed", false)), str(_dice(phase, "NO ESCAPE")))


func _section_no_escape_p1() -> void:
	print("\n-- C. NO ESCAPE (human, Custodes = P1, in P2's turn) --")
	_load("cus11e_c5_active", 1, "Shadowkeepers")
	GS.set_active_player(2)
	var phase = _movement()
	_check("P2 (Orks) is the active player", phase.get_current_player() == 2)
	var fb := _fall_back(phase, "U_BOYZ_B", 2, Vector2(0.0, -2.5))
	_check("P2's Boyz fell back; enemy_ended_move pending for P1", fb.get("success", false) and _pending_id(phase) == "enemy_ended_move" and int(phase.get_pending_stratagem_window().player) == 1, "%s / %s" % [str(fb.get("error", "")), _pending_id(phase)])
	var sid := _sid(1, CSV_NOESC)
	var use = _use(phase, 1, "enemy_ended_move", sid, "U_CUSTODIAN_GUARD_A")
	_check("P1 USE pauses for P1", use.get("success", false) and int(phase._cus11e_g5.get("player", 0)) == 1 and phase.get_pending_stratagem_window_decider() == 1, str(use.get("error", "")))
	RE.set_test_seed(_seed_for(7))
	phase.execute_action({"type": R.ACT_ROLL, "player": 1})
	var tg = phase.execute_action({"type": R.ACT_TARGETS, "player": 1, "payload": {"target_ids": ["U_BOYZ_B"]}})
	_check("P1 picks the Boyz", tg.get("success", false), str(tg.get("error", "")))
	_stage_rigid(phase, "U_CUSTODIAN_GUARD_A", Vector2(0, -2.6))
	var ok = phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_A", "payload": {}, "player": 1})
	_check("P1's charge is made and ends engaged; P2 has the phase back", ok.get("success", false) and Common.group_engaged_with("U_CUSTODIAN_GUARD_A", "U_BOYZ_B") and phase.get_pending_stratagem_window_decider() == 0, str(ok.get("error", "")))
	GS.set_active_player(1)


func _section_no_escape_ai() -> void:
	print("\n-- D. NO ESCAPE (AI decider keeps the auto path) --")
	_load("cus11e_c5_reactive", 2, "Shadowkeepers")
	var phase = _movement()
	var ai = root.get_node("AIPlayer")
	ai.enabled = true
	ai.ai_players = {1: false, 2: true}
	var cp0 := _cp(2)
	RE.set_test_seed(_seed_for(7))
	var fb := _fall_back(phase, "U_BOYZ_B", 1, Vector2(0.0, -2.5))
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI: the fall-back never pauses; no human flow state", fb.get("success", false) and not phase.has_pending_stratagem_window() and phase._cus11e_g5.is_empty() and phase.get_pending_stratagem_window_decider() == 0, str(fb.get("error", "")))
	print("    AI NO ESCAPE: CP %d -> %d, rolls %s" % [cp0, _cp(2), str(_dice(phase, "NO ESCAPE"))])
	_check("AI: if used, the auto charge rolled at once", _cp(2) == cp0 or _dice(phase, "NO ESCAPE").size() == 1)


# ---------------------------------------------------------------------------
func _charge_end(det: String):
	_load("cus11e_c5_reactive", 2, det)
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_CHARGE)
	var phase = PM.get_current_phase_instance()
	_decline_all(phase)
	return phase


func _section_selfless_human() -> void:
	print("\n-- E. SELFLESS SERVICE (human) --")
	var phase = _charge_end("Emissaries Imperatus")
	# A second enemy unit within 6" of the Witchseekers: the Warboss.
	var wb: Dictionary = _unit("U_WARBOSS_A")
	wb.models[0]["position"] = {"x": 1.5 * PX, "y": 41.5 * PX}
	var sid := _sid(2, CSV_SELFLESS)
	var res = phase.execute_action({"type": "END_CHARGE", "player": 1})
	_check("END_CHARGE opens charge_phase_end for P2", res.get("success", false) and _pending_id(phase) == "charge_phase_end", _pending_id(phase))
	var cp0 := _cp(2)
	var use = _use(phase, 2, "charge_phase_end", sid, "U_WITCHSEEKERS_A")
	_check("USE: CP -1, the human flow owns the phase (stage roll, no dice yet)", use.get("success", false) and _cp(2) == cp0 - 1 and str(phase._cus11e_g5.get("stage", "")) == "roll" and _dice(phase, "SELFLESS SERVICE").is_empty(), str(use.get("error", "")))
	_check("decider = P2; no HI move pending yet", phase.get_pending_stratagem_window_decider() == 2 and str(phase.heroic_intervention_unit_id) == "")
	var other = phase.execute_action({"type": "END_CHARGE", "player": 1})
	_check("nothing else happens meanwhile", not other.get("success", false))
	RE.set_test_seed(_seed_for(9))
	var roll = phase.execute_action({"type": R.ACT_ROLL, "player": 2})
	var g: Dictionary = phase._cus11e_g5
	var rd := _dice(phase, "SELFLESS SERVICE")
	print("    SELFLESS roll %s -> %d (uncapped %d), selectable %s" % [str(g.get("rolls", [])), int(g.get("roll", 0)), int(g.get("uncapped", 0)), str(g.get("selectable", []))])
	_check("ROLL: a 9+ is changed to 6", roll.get("success", false) and int(g.get("roll", 0)) == 6 and int(g.get("uncapped", 0)) >= 9 and rd.size() == 1 and bool(rd[0].get("capped", false)), str(rd))
	var sel: Array = g.get("selectable", [])
	_check("ANY enemy unit within 6\" is selectable (Gretchin C and the Warboss)", "U_GRETCHIN_C" in sel and "U_WARBOSS_A" in sel, str(sel))
	_check("an enemy beyond 6\" is not (Boyz B)", not "U_BOYZ_B" in sel)
	var bad = phase.execute_action({"type": R.ACT_TARGETS, "player": 2, "payload": {"target_ids": ["U_BOYZ_B"]}})
	_check("a target beyond 6\" is refused", not bad.get("success", false))
	var tg = phase.execute_action({"type": R.ACT_TARGETS, "player": 2, "payload": {"target_ids": ["U_GRETCHIN_C", "U_WARBOSS_A"]}})
	_check("TARGETS (two units): the HI charge path is armed with both", tg.get("success", false) and str(phase.heroic_intervention_unit_id) == "U_WITCHSEEKERS_A"
		and "U_GRETCHIN_C" in phase.heroic_intervention_pending_charge.get("targets", []) and "U_WARBOSS_A" in phase.heroic_intervention_pending_charge.get("targets", [])
		and int(phase.heroic_intervention_pending_charge.get("distance", 0)) == 6, "%s %s" % [str(tg.get("error", "")), str(phase.heroic_intervention_pending_charge)])
	_check("the move offer is APPLY_HEROIC_INTERVENTION_MOVE (the charge path tools)", phase.get_available_actions().any(func(a): return str(a.get("type", "")) == "APPLY_HEROIC_INTERVENTION_MOVE"))
	var mv_one: Dictionary = ADM._compute_charge_move(GS.create_snapshot(), "U_WITCHSEEKERS_A", 6, ["U_GRETCHIN_C"], 2, "APPLY_HEROIC_INTERVENTION_MOVE")
	if str(mv_one.get("type", "")) == "APPLY_HEROIC_INTERVENTION_MOVE":
		mv_one["player"] = 2
		var v: Dictionary = phase.validate_action(mv_one)
		_check("a move engaging only one of the two selected targets is refused", not v.get("valid", true) and str(v.get("errors", [])).contains("all targets"), str(v.get("errors", [])))
	else:
		_check("(a one-target move exists to test)", false, str(mv_one))
	var give_up = phase.execute_action({"type": R.ACT_FAIL, "player": 2})
	_check("give up during the move: the charge fails; the end of the phase continues (HI / completed)", give_up.get("success", false) and phase._cus11e_g5.is_empty() and str(phase.heroic_intervention_unit_id) == "" and not _flags("U_WITCHSEEKERS_A").has("charged_this_turn"), str(give_up.get("error", "")))
	if phase.awaiting_heroic_intervention:
		phase.execute_action({"type": "DECLINE_HEROIC_INTERVENTION", "player": 2})
	# A real one-target charge.
	phase = _charge_end("Emissaries Imperatus")
	phase.execute_action({"type": "END_CHARGE", "player": 1})
	_use(phase, 2, "charge_phase_end", sid, "U_WITCHSEEKERS_A")
	RE.set_test_seed(_seed_for(5))
	phase.execute_action({"type": R.ACT_ROLL, "player": 2})
	var roll2 := int(phase._cus11e_g5.get("roll", 0))
	var tg2 = phase.execute_action({"type": R.ACT_TARGETS, "player": 2, "payload": {"target_ids": ["U_GRETCHIN_C"]}})
	_check("one target picked (Gretchin C)", tg2.get("success", false) and phase.heroic_intervention_pending_charge.get("targets", []) == ["U_GRETCHIN_C"], str(tg2.get("error", "")))
	var mv: Dictionary = ADM._compute_charge_move(GS.create_snapshot(), "U_WITCHSEEKERS_A", roll2, ["U_GRETCHIN_C"], 2, "APPLY_HEROIC_INTERVENTION_MOVE")
	mv["player"] = 2
	var applied = phase.execute_action(mv)
	_check("the charge move is applied (APPLY_HEROIC_INTERVENTION_MOVE)", applied.get("success", false), str(applied.get("error", "")))
	_check("charged + Fights First, engaged with the Gretchin, Gretchin has_been_charged", bool(_flags("U_WITCHSEEKERS_A").get("charged_this_turn", false)) and bool(_flags("U_WITCHSEEKERS_A").get("fights_first", false))
		and Common.group_engaged_with("U_WITCHSEEKERS_A", "U_GRETCHIN_C") and bool(_flags("U_GRETCHIN_C").get("has_been_charged", false)))
	_check("the human flow is over", phase._cus11e_g5.is_empty() and not phase._cus11e_selfless_pending)
	if phase.awaiting_heroic_intervention:
		phase.execute_action({"type": "DECLINE_HEROIC_INTERVENTION", "player": 2})
	_check("the Charge phase ended", int(GS.get_current_phase()) != PHASE_CHARGE or PM.get_current_phase_instance() != phase, str(GS.get_current_phase()))


func _section_selfless_ai() -> void:
	print("\n-- F. SELFLESS SERVICE (AI decider keeps the auto path) --")
	var phase = _charge_end("Emissaries Imperatus")
	var ai = root.get_node("AIPlayer")
	ai.enabled = true
	ai.ai_players = {1: false, 2: true}
	RE.set_test_seed(_seed_for(5))
	phase.execute_action({"type": "END_CHARGE", "player": 1})
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI: no human flow state", phase._cus11e_g5.is_empty())
	var hi := str(phase.heroic_intervention_unit_id)
	if hi != "":
		_check("AI: the auto charge already rolled and waits for the AI's move", _dice(phase, "SELFLESS SERVICE").size() == 1 and phase.get_available_actions().any(func(a): return str(a.get("type", "")) == "APPLY_HEROIC_INTERVENTION_MOVE"))
		var mv: Dictionary = ADM._compute_charge_move(GS.create_snapshot(), hi, int(phase.heroic_intervention_pending_charge.distance), phase.heroic_intervention_pending_charge.targets, 2, "APPLY_HEROIC_INTERVENTION_MOVE")
		mv["player"] = 2
		phase.execute_action(mv)
	else:
		_check("AI: declined or the roll failed — nothing pending", phase.get_pending_stratagem_window_decider() == 0 or phase.awaiting_heroic_intervention)
	if phase.awaiting_heroic_intervention:
		phase.execute_action({"type": "DECLINE_HEROIC_INTERVENTION", "player": 2})
	_check("AI: the Charge phase ended (never stalled)", int(GS.get_current_phase()) != PHASE_CHARGE or not phase.has_pending_stratagem_window())


# ---------------------------------------------------------------------------
func _section_rapid_human() -> void:
	print("\n-- G. RAPID REACTIONS (human) --")
	var phase = _reactive_fall_back("Aquilan Shield")
	var sid := _sid(2, CSV_RAPID)
	var cp0 := _cp(2)
	var use = _use(phase, 2, "enemy_ended_move", sid, "U_CUSTODIAN_GUARD_A")
	var g: Dictionary = phase._cus11e_g5
	_check("USE: CP -1, the human picks the weapons (stage shoot, no dice yet)", use.get("success", false) and _cp(2) == cp0 - 1 and str(g.get("kind", "")) == "shoot"
		and phase.dice_log.filter(func(d): return typeof(d) == TYPE_DICTIONARY and str(d.get("context", "")) == "to_hit").is_empty(), "%s %s" % [str(use.get("error", "")), str(g)])
	var opts: Array = g.get("options", [])
	print("    options: %s" % str(opts.map(func(o): return [o.label, o.profiles.map(func(p): return p.weapon_id)])))
	_check("weapon choices exist, all of them aimed only at the Boyz", not opts.is_empty() and str(g.get("target_id", "")) == "U_BOYZ_B")
	_check("decider = P2", phase.get_pending_stratagem_window_decider() == 2)
	var bad = phase.execute_action({"type": R.ACT_SHOOT, "player": 2, "payload": {"weapons": [{"key": "nope", "weapon_id": "x"}]}})
	_check("an unknown weapon choice is refused", not bad.get("success", false))
	var bad2 = phase.execute_action({"type": R.ACT_SHOOT, "player": 2, "payload": {"weapons": [{"key": str(opts[0].key), "weapon_id": "not_a_profile"}]}})
	_check("a profile that cannot target the unit is refused", not bad2.get("success", false))
	var pick := [{"key": str(opts[0].key), "weapon_id": str(opts[0].profiles[0].weapon_id)}]
	RE.set_test_seed(31)
	var shot = phase.execute_action({"type": R.ACT_SHOOT, "player": 2, "payload": {"weapons": pick}})
	var hits: Array = phase.dice_log.filter(func(d): return typeof(d) == TYPE_DICTIONARY and str(d.get("context", "")) == "to_hit")
	_check("SHOOT: the chosen weapon fires (hit rolls in the dice log)", shot.get("success", false) and not hits.is_empty(), str(shot.get("error", "")))
	_check("every attack targeted the Boyz", hits.all(func(d): return str(d.get("target_unit_id", "U_BOYZ_B")) == "U_BOYZ_B"))
	_check("the result carries the summary for the dialog", shot.has("cus11e_reactive_shoot") and str(shot.cus11e_reactive_shoot.get("summary", "")).begins_with("RAPID REACTIONS"), str(shot.get("cus11e_reactive_shoot", {})))
	print("    %s" % str(shot.get("cus11e_reactive_shoot", {}).get("summary", "")))
	_check("the phase is handed back", phase._cus11e_g5.is_empty() and phase.get_pending_stratagem_window_decider() == 0 and not phase.has_pending_stratagem_window())
	# Don't shoot.
	phase = _reactive_fall_back("Aquilan Shield")
	_use(phase, 2, "enemy_ended_move", sid, "U_CUSTODIAN_GUARD_A")
	var n0: int = phase.dice_log.size()
	var skip = phase.execute_action({"type": R.ACT_SHOOT, "player": 2, "payload": {"weapons": []}})
	_check("Don't shoot: no attacks, the phase is handed back", skip.get("success", false) and phase.dice_log.size() == n0 and phase.get_pending_stratagem_window_decider() == 0, str(skip.get("error", "")))


func _section_rapid_ai() -> void:
	print("\n-- H. RAPID REACTIONS (AI decider keeps the auto path) --")
	_load("cus11e_c5_reactive", 2, "Aquilan Shield")
	var phase = _movement()
	var ai = root.get_node("AIPlayer")
	ai.enabled = true
	ai.ai_players = {1: false, 2: true}
	var cp0 := _cp(2)
	var fb := _fall_back(phase, "U_BOYZ_B", 1, Vector2(0.0, -2.5))
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI: used RAPID REACTIONS and never paused", fb.get("success", false) and _cp(2) < cp0 and phase._cus11e_g5.is_empty() and not phase.has_pending_stratagem_window(), "%s cp %d->%d" % [str(fb.get("error", "")), cp0, _cp(2)])
