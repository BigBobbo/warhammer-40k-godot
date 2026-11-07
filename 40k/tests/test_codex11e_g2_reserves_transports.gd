extends SceneTree

# WP-G2 (.llm/codex_11e_wahapedia/PLAN_GAPS.md) — the remaining Custodes + Ork
# reserves / transport datasheet abilities:
#
#   ASSAULT VEHICLE (Coronus Grav-Carrier, Anathema Psykana Rhino): "In your
#     Movement phase, when this unit ends an advance move, units embarked within
#     this unit can make a shock disembark move." — the rapid disembark mode
#     with the advanced-transport bar lifted (ShockDisembark11e.gd).
#   PILIN' OUT (Trukk): "In your opponent's Movement phase, when an enemy unit
#     ends a move within 8" of this model, units embarked within this model can
#     make a disembark move using the rapid disembark mode." — an ability card
#     in the Ork player's enemy_ended_move window + the disembark follow-up.
#   DEFF FROM THE SHADOWS (Boss Snikrot, first battle round onwards): "At the
#     end of your opponent's Movement phase, if this unit is in strategic
#     reserves, this unit can make an ingress move." — a free row of the
#     end-of-Movement reserves prompt (EndOfMovementArrivals11e.gd).
#   SWIFT RUIN (Venatari with Verutum Lances, once per phase per army): Rapid
#     Ingress on the unit regardless of other uses this phase, -1 CP, and it
#     does not prevent other uses — per-unit rows of the same prompt.
#
# Boards: tests/saves/cus11e_g2_* / ork11e_g2_* (tests/helpers/
# gen_codex11e_g2_fixtures.gd). Everything that has an engine path goes through
# the real MovementPhase.execute_action (END_MOVEMENT -> USE / PLACE_RAPID_
# INGRESS..., CONFIRM_UNIT_MOVE -> enemy_ended_move -> USE_WINDOW_STRATAGEM ->
# CONFIRM_DISEMBARK).
#
# Usage: godot --headless --path 40k -s tests/test_codex11e_g2_reserves_transports.gd

const PX := 40.0
const P_MOV := 7
const P_SHOOT := 8
const P_CHG := 9

var passed := 0
var failed := 0

var GS
var SM
var PM
var RE
var MM
var AI
var TM
var OA
var CA
var ARR
var SD


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, ("  --  " + detail) if detail != "" else ""])


func _init():
	create_timer(0.3).timeout.connect(_run_tests)


# ── helpers ──────────────────────────────────────────────────────────

func _load(name: String) -> void:
	var slm = root.get_node("SaveLoadManager")
	var ok: bool = slm.load_game_from_file_path("res://tests/saves/%s.w40ksave" % name)
	# Written AFTER the load (a load re-applies the boot edition).
	GameConstants.edition = 11
	if not ok:
		_check("fixture %s loads" % name, false)
		return
	SM._usage_history = {"1": [], "2": []}
	MM.objective_control_state = {}
	MM.objective_contested_state = {}
	AI.enabled = false
	AI.ai_players = {1: false, 2: false}
	root.get_node("SettingsService").auto_allocate_wounds = true
	RE.set_test_seed(42)


func _mt(id: String):
	return load("res://scripts/rules/movetypes/MoveTypes.gd").get_type(id)


func _u(uid: String) -> Dictionary:
	return GS.state.units.get(uid, {})


func _flags(uid: String) -> Dictionary:
	var u := _u(uid)
	if not u.has("flags"):
		u["flags"] = {}
	return u.flags


func _pos(uid: String, i: int = 0) -> Vector2:
	var p = _u(uid).models[i].position
	return Vector2(float(p.x), float(p.y))


func _set_phase(phase: int, active: int) -> void:
	GS.state.meta["phase"] = phase
	GS.state.meta["active_player"] = active


## Decline every pending stratagem window (any player), up to `n`.
func _drain(phase: Node, n: int = 8) -> void:
	var guard := 0
	while phase != null and phase.has_pending_stratagem_window() and guard < n:
		var w = phase.get_pending_stratagem_window()
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.player), "window_id": str(w.window_id)})
		guard += 1


func _movement() -> Node:
	PM.transition_to_phase(P_MOV)
	var phase = PM.get_current_phase_instance()
	_drain(phase, 6)
	return phase


## Shift every alive model of `uid` by (dx, dy) inches through the real
## STAGE_MODEL_MOVE action (the drag tool's per-model action).
func _stage(phase: Node, uid: String, dx: float, dy: float, player: int) -> bool:
	var ok := true
	for m in _u(uid).models:
		if not m.get("alive", true) or m.get("position", null) == null:
			continue
		var p = m.position
		var r: Dictionary = phase.execute_action({"type": "STAGE_MODEL_MOVE", "player": player, "actor_unit_id": uid,
			"payload": {"model_id": str(m.id), "dest": [float(p.x) + dx * PX, float(p.y) + dy * PX], "rotation": float(m.get("rotation", 0.0))}})
		if not r.get("success", false):
			print("    stage failed: %s" % str(r.get("errors", r.get("error", ""))))
			ok = false
	return ok


func _rows(res: Dictionary) -> Array:
	return res.get("rapid_ingress_eligible_units", [])


func _row(rows: Array, uid: String) -> Dictionary:
	for r in rows:
		if str(r.get("unit_id", "")) == uid:
			return r
	return {}


func _row_ids(rows: Array) -> Array:
	return rows.map(func(r): return str(r.get("unit_id", "")))


## Model positions for an ingress set-up: a row along x at `y_in`, starting at x_in.
func _line(uid: String, x_in: float, y_in: float, step_in: float = 2.2) -> Array:
	var out: Array = []
	var i := 0
	for m in _u(uid).models:
		if m.get("alive", true):
			out.append(Vector2((x_in + i * step_in) * PX, y_in * PX))
			i += 1
	return out


func _place_ri(phase: Node, uid: String, positions: Array, player: int) -> Dictionary:
	var rots: Array = []
	for _p in positions:
		rots.append(0.0)
	return phase.execute_action({"type": "PLACE_RAPID_INGRESS_REINFORCEMENT", "unit_id": uid, "player": player,
		"model_positions": positions, "model_rotations": rots, "phase": P_MOV})


func _offer_slugs(player: int, window_id: String, ctx: Dictionary) -> Array:
	return OA.window_offers(player, window_id, ctx).map(func(o): return OA.slug_of(str(o.get("stratagem_id", ""))))


func _offer_targets(player: int, window_id: String, ctx: Dictionary, slug: String) -> Array:
	for o in OA.window_offers(player, window_id, ctx):
		if OA.slug_of(str(o.get("stratagem_id", ""))) == slug:
			return o.get("targets", []).map(func(t): return str(t.get("unit_id", "")))
	return []


# ── run ──────────────────────────────────────────────────────────────

func _run_tests() -> void:
	GS = root.get_node("GameState")
	SM = root.get_node("StratagemManager")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	MM = root.get_node("MissionManager")
	AI = root.get_node("AIPlayer")
	TM = root.get_node("TransportManager")
	OA = load("res://scripts/codex/orks/OrkAbilities11e.gd")
	CA = load("res://scripts/codex/custodes/CustodesAbilities.gd")
	ARR = load("res://scripts/codex/EndOfMovementArrivals11e.gd")
	SD = load("res://scripts/codex/ShockDisembark11e.gd")
	print("\n=== WP-G2: Assault Vehicle / Pilin' Out / Deff from the Shadows / Swift Ruin ===")
	_test_assault_vehicle_rules()
	_test_assault_vehicle_action_path()
	_test_pilin_out_offer()
	_test_pilin_out_action_path()
	_test_pilin_out_ai()
	_test_deff_from_the_shadows()
	await _test_deff_round2_mixed_and_ai()
	_test_swift_ruin()
	_test_swift_ruin_reverse_and_limits()
	_test_dialogs()
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)


# ── 1. ASSAULT VEHICLE ───────────────────────────────────────────────

func _test_assault_vehicle_rules() -> void:
	print("\n-- 1. Assault Vehicle: shock disembark = rapid mode after the transport's advance --")
	_load("cus11e_g2_assault_vehicle")
	_set_phase(P_MOV, 2)
	var DM = _mt("disembark")
	_check("before the Coronus moved: tactical disembark (control)", str(DM.select_mode("U_GUARD_A", GS.state, {}).mode) == "tactical")
	_check("before the advance: no shock disembark", not SD.transport_allows(_u("U_CORONUS_A")))
	_flags("U_CORONUS_A")["advanced"] = true
	_check("advance BEGUN (not ended): still barred (18.04)", not DM.eligible("U_GUARD_A", GS.state).eligible and not TM.can_disembark("U_GUARD_A").valid)
	_flags("U_CORONUS_A")["moved"] = true
	_check("advance ENDED: the Guard can disembark (DisembarkMove)", DM.eligible("U_GUARD_A", GS.state).eligible, str(DM.eligible("U_GUARD_A", GS.state)))
	_check("... TransportManager agrees", TM.can_disembark("U_GUARD_A").valid, str(TM.can_disembark("U_GUARD_A")))
	var sel = DM.select_mode("U_GUARD_A", GS.state, {})
	_check("... shock disembark = rapid mode, 3\" set-up", str(sel.mode) == "rapid" and float(DM.setup_distance_inches({"mode": "rapid"})) == 3.0, str(sel))
	var fx: Array = DM.after_moving_effects("U_GUARD_A", {"mode": "rapid"})
	_check("... AFTER: not eligible to declare a charge", fx.any(func(c): return str(c.get("path", "")).ends_with(".cannot_charge") and c.get("value") == true))
	_check("source names the ability", SD.source(_u("U_CORONUS_A")) == "Assault Vehicle")
	# The Anathema Psykana Rhino has it too.
	_flags("U_AP_RHINO_A")["advanced"] = true
	_flags("U_AP_RHINO_A")["moved"] = true
	_check("Anathema Psykana Rhino: shock disembark after its advance", DM.eligible("U_PROSECUTORS_A", GS.state).eligible and str(DM.select_mode("U_PROSECUTORS_A", GS.state, {}).mode) == "rapid")
	# Edges.
	_flags("U_CORONUS_A")["fell_back"] = true
	_check("fell back: barred (18.04, not lifted)", not DM.eligible("U_GUARD_A", GS.state).eligible)
	_flags("U_CORONUS_A").erase("fell_back")
	_set_phase(P_MOV, 1)
	_check("not in the opponent's Movement phase", not SD.transport_allows(_u("U_CORONUS_A")))
	_set_phase(P_SHOOT, 2)
	_check("not outside the Movement phase", not SD.transport_allows(_u("U_CORONUS_A")))
	_set_phase(P_MOV, 2)
	var abil: Array = _u("U_AP_RHINO_A").meta.abilities
	_u("U_AP_RHINO_A").meta["abilities"] = abil.filter(func(a): return not (str(a.get("name", "") if a is Dictionary else a).begins_with("Assault Vehicle")))
	_check("a transport without the ability: an advance still bars disembarking", not DM.eligible("U_PROSECUTORS_A", GS.state).eligible)
	GameConstants.edition = 10
	_check("edition 10: no shock disembark", not SD.transport_allows(_u("U_CORONUS_A")))
	GameConstants.edition = 11


func _test_assault_vehicle_action_path() -> void:
	print("\n-- 2. Assault Vehicle through the real actions: BEGIN_ADVANCE -> CONFIRM_UNIT_MOVE -> CONFIRM_DISEMBARK --")
	_load("cus11e_g2_assault_vehicle")
	var phase = _movement()
	_check("P2's Movement phase", GS.get_current_phase() == P_MOV and GS.get_active_player() == 2)
	var r: Dictionary = phase.execute_action({"type": "BEGIN_ADVANCE", "actor_unit_id": "U_CORONUS_A", "player": 2})
	if phase.get("_awaiting_reroll_decision"):
		r = phase.execute_action({"type": "DECLINE_COMMAND_REROLL", "actor_unit_id": "U_CORONUS_A", "player": 2})
	_drain(phase)
	_check("BEGIN_ADVANCE (Coronus)", r.get("success", false), str(r.get("errors", r.get("error", ""))))
	var pre: Dictionary = phase.execute_action({"type": "CONFIRM_DISEMBARK", "actor_unit_id": "U_GUARD_A", "player": 2, "payload": {"positions": [_pos("U_CORONUS_A") + Vector2(0, -90)]}})
	_check("mid-advance (move not ended): CONFIRM_DISEMBARK refused", not pre.get("success", true))
	_check("stage the Coronus 4\" up the board", _stage(phase, "U_CORONUS_A", 0.0, -4.0, 2))
	var c: Dictionary = phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_CORONUS_A", "player": 2})
	_drain(phase)
	_check("CONFIRM_UNIT_MOVE (advance ended)", c.get("success", false), str(c.get("errors", c.get("error", ""))))
	_check("the Coronus advanced and moved", bool(_flags("U_CORONUS_A").get("advanced", false)) and bool(_flags("U_CORONUS_A").get("moved", false)))
	_check("DISEMBARK_UNIT accepted after the advance", phase.validate_action({"type": "DISEMBARK_UNIT", "actor_unit_id": "U_GUARD_A", "player": 2}).get("valid", false))
	var payload: Dictionary = phase._ork11e_greedy_disembark_payload("U_GUARD_A", ["U_GUARD_A"], "U_CORONUS_A", 2)
	_check("a legal 3\" set-up exists", not payload.is_empty())
	var d: Dictionary = phase.execute_action({"type": "CONFIRM_DISEMBARK", "actor_unit_id": "U_GUARD_A", "player": 2, "payload": payload})
	_drain(phase)
	_check("CONFIRM_DISEMBARK (shock disembark) succeeds", d.get("success", false), str(d.get("errors", d.get("error", ""))))
	_check("the Guard is on the battlefield", _u("U_GUARD_A").get("embarked_in", null) == null and _u("U_GUARD_A").models[0].get("position", null) != null)
	_check("... not eligible to declare a charge (rapid mode)", bool(_flags("U_GUARD_A").get("cannot_charge", false)))
	_check("... cannot move further (the transport moved)", bool(_flags("U_GUARD_A").get("cannot_move", false)))
	# A 6" set-up is refused (rapid = 3").
	var far: Array = []
	for i in range(_u("U_PROSECUTORS_A").models.size()):
		far.append({"x": _pos("U_AP_RHINO_A").x + (i - 2) * 1.6 * PX, "y": _pos("U_AP_RHINO_A").y - 5.5 * PX})
	var rr: Dictionary = phase.execute_action({"type": "BEGIN_ADVANCE", "actor_unit_id": "U_AP_RHINO_A", "player": 2})
	if phase.get("_awaiting_reroll_decision"):
		phase.execute_action({"type": "DECLINE_COMMAND_REROLL", "actor_unit_id": "U_AP_RHINO_A", "player": 2})
	_drain(phase)
	_stage(phase, "U_AP_RHINO_A", 0.0, -1.0, 2)
	phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_AP_RHINO_A", "player": 2})
	_drain(phase)
	var bad: Dictionary = phase.execute_action({"type": "CONFIRM_DISEMBARK", "actor_unit_id": "U_PROSECUTORS_A", "player": 2, "payload": {"positions": far}})
	_check("AP Rhino: a set-up 5.5\" away is refused (3\" rapid set-up)", rr.get("success", false) and not bad.get("success", true), str(bad.get("error", "")))


# ── 3-5. PILIN' OUT ──────────────────────────────────────────────────

func _test_pilin_out_offer() -> void:
	print("\n-- 3. Pilin' Out: the offer (enemy_ended_move, opponent's Movement phase, within 8\") --")
	_load("ork11e_g2_pilin_out")
	_set_phase(P_MOV, 2)
	var ctx := {"phase": "movement", "enemy_unit_id": "U_CUSTODIAN_GUARD_B", "window_id": "enemy_ended_move"}
	var d0: float = OA.dist_in("U_TRUKK_A", "U_CUSTODIAN_GUARD_B")
	_check("fixture: the Guard starts more than 8\" away (%.1f\")" % d0, d0 > 8.0)
	_check("enemy ends a move > 8\" away: not offered", not "pilin_out" in _offer_slugs(1, "enemy_ended_move", ctx))
	for m in _u("U_CUSTODIAN_GUARD_B").models:
		m.position = {"x": float(m.position.x), "y": float(m.position.y) - 5.0 * PX}
	_check("within 8\" (%.1f\"): offered to the Ork player on the Trukk" % OA.dist_in("U_TRUKK_A", "U_CUSTODIAN_GUARD_B"),
		_offer_targets(1, "enemy_ended_move", ctx, "pilin_out") == ["U_TRUKK_A"], str(_offer_slugs(1, "enemy_ended_move", ctx)))
	_check("the card is a free ability", OA.window_offers(1, "enemy_ended_move", ctx).any(func(o): return OA.slug_of(str(o.stratagem_id)) == "pilin_out" and int(o.cp_cost) == 0 and bool(o.is_ability)))
	_check("not to the active player", not "pilin_out" in _offer_slugs(2, "enemy_ended_move", ctx))
	_set_phase(P_MOV, 1)
	_check("not in the Ork player's own Movement phase", not "pilin_out" in _offer_slugs(1, "enemy_ended_move", {"phase": "movement", "enemy_unit_id": "U_CUSTODIAN_GUARD_B"}))
	_set_phase(P_CHG, 2)
	_check("not in the opponent's Charge phase", not "pilin_out" in _offer_slugs(1, "enemy_ended_move", ctx))
	_set_phase(P_MOV, 2)
	_check("not in other windows (unit_ended_normal_move)", not "pilin_out" in _offer_slugs(1, "unit_ended_normal_move", {"unit_id": "U_TRUKK_A"}))
	_flags("U_NOBZ_A")["embarked_this_phase"] = true
	_check("a unit that embarked this phase cannot disembark: no offer", not "pilin_out" in _offer_slugs(1, "enemy_ended_move", ctx))
	_flags("U_NOBZ_A").erase("embarked_this_phase")
	var keep: Array = _u("U_TRUKK_A").transport_data.embarked_units.duplicate()
	_u("U_TRUKK_A").transport_data["embarked_units"] = []
	_check("an empty Trukk: no offer", not "pilin_out" in _offer_slugs(1, "enemy_ended_move", ctx))
	_u("U_TRUKK_A").transport_data["embarked_units"] = keep
	GameConstants.edition = 10
	_check("edition 10: no offer", OA.window_offers(1, "enemy_ended_move", ctx).is_empty())
	GameConstants.edition = 11


func _test_pilin_out_action_path() -> void:
	print("\n-- 4. Pilin' Out through the real actions: the Guard's move -> window -> rapid disembark --")
	_load("ork11e_g2_pilin_out")
	var phase = _movement()
	var cp1 := int(GS.state.players["1"]["cp"])
	var b: Dictionary = phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_B", "player": 2})
	_drain(phase)
	_check("BEGIN_NORMAL_MOVE (Custodian Guard B)", b.get("success", false), str(b.get("errors", b.get("error", ""))))
	_check("stage the Guard 5\" toward the Trukk", _stage(phase, "U_CUSTODIAN_GUARD_B", 0.0, -5.0, 2))
	var c: Dictionary = phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_B", "player": 2})
	_check("CONFIRM_UNIT_MOVE", c.get("success", false), str(c.get("errors", c.get("error", ""))))
	var w: Dictionary = phase.get_pending_stratagem_window() if phase.has_pending_stratagem_window() else {}
	_check("the Ork player's enemy_ended_move window is open", str(w.get("window_id", "")) == "enemy_ended_move" and int(w.get("player", 0)) == 1, str(w.keys()))
	var has_card := false
	for o in w.get("offers", []):
		if str(o.get("stratagem_id", "")) == "ork11e_ab_pilin_out":
			has_card = true
	_check("... with the Pilin' Out card", has_card)
	var u: Dictionary = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "enemy_ended_move",
		"stratagem_id": "ork11e_ab_pilin_out", "target_unit_id": "U_TRUKK_A"})
	_check("USE (Pilin' Out) succeeds", u.get("success", false), str(u.get("errors", u.get("error", ""))))
	_check("free (no CP)", int(GS.state.players["1"]["cp"]) == cp1)
	_check("the disembark follow-up waits for the Nobz (the Ork player decides)", phase.is_ork11e_assault_disembark_pending("U_NOBZ_A") and phase.get_pending_stratagem_window_decider() == 1)
	_check("the mode is RAPID (Pilin' Out), not tactical", str(_mt("disembark").select_mode("U_NOBZ_A", GS.state, {}).mode) == "rapid")
	var gate: Dictionary = phase.validate_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_WITCHSEEKERS_C", "player": 2})
	_check("the active player waits for the follow-up (the gate names Pilin' Out)", not gate.get("valid", true) and str(gate.get("errors", [""])[0]).contains("Finish Pilin' Out first"), str(gate))
	var payload: Dictionary = phase._ork11e_greedy_disembark_payload("U_NOBZ_A", ["U_NOBZ_A"], "U_TRUKK_A", 1)
	_check("a legal 3\" set-up exists", not payload.is_empty())
	var wrong: Dictionary = phase.execute_action({"type": "CONFIRM_DISEMBARK", "actor_unit_id": "U_NOBZ_A", "player": 2, "payload": payload})
	_check("the active player cannot make the Ork disembark", not wrong.get("success", true))
	var d: Dictionary = phase.execute_action({"type": "CONFIRM_DISEMBARK", "actor_unit_id": "U_NOBZ_A", "player": 1, "payload": payload})
	_check("CONFIRM_DISEMBARK by the Ork player succeeds", d.get("success", false), str(d.get("errors", d.get("error", ""))))
	_check("the Nobz are on the battlefield", _u("U_NOBZ_A").get("embarked_in", null) == null and _u("U_NOBZ_A").models[0].get("position", null) != null)
	_check("... rapid: not eligible to declare a charge (until the end of the turn)", bool(_flags("U_NOBZ_A").get("cannot_charge", false)))
	_check("... and no further move this phase", bool(_flags("U_NOBZ_A").get("cannot_move", false)))
	_check("the grant is spent (flag cleared)", not _flags("U_TRUKK_A").has(OA.F_PILIN_OUT))
	_check("the follow-up / window is closed", phase.get_pending_stratagem_window_decider() == 0 and not phase.has_pending_stratagem_window())
	_check("the game log names it", root.get_node("GameEventLog").get_all_entries().any(func(e): return str(e.get("text", "")).contains("Pilin' Out")))
	# A later enemy move within 8": the Trukk is empty — no offer.
	var ctx := {"phase": "movement", "enemy_unit_id": "U_CUSTODIAN_GUARD_B"}
	_check("the Trukk is empty now: no further offer", not "pilin_out" in _offer_slugs(1, "enemy_ended_move", ctx))
	# Stay-embarked path.
	_load("ork11e_g2_pilin_out")
	phase = _movement()
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_B", "player": 2})
	_drain(phase)
	_stage(phase, "U_CUSTODIAN_GUARD_B", 0.0, -5.0, 2)
	phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_B", "player": 2})
	phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "enemy_ended_move", "stratagem_id": "ork11e_ab_pilin_out", "target_unit_id": "U_TRUKK_A"})
	var sk: Dictionary = phase.execute_action({"type": "SKIP_ASSAULT_DISEMBARK", "player": 1, "actor_unit_id": "U_NOBZ_A", "payload": {"unit_id": "U_NOBZ_A"}})
	_check("Stay Embarked (SKIP) ends the follow-up", sk.get("success", false) and phase.get_pending_stratagem_window_decider() == 0, str(sk.get("error", "")))
	_check("... the Nobz stay in the Trukk; the grant is spent", str(_u("U_NOBZ_A").get("embarked_in", "")) == "U_TRUKK_A" and not _flags("U_TRUKK_A").has(OA.F_PILIN_OUT))
	_check("... the Trukk's later disembark (own turn) is the normal 18.04 mode again", str(_mt("disembark").select_mode("U_NOBZ_A", GS.state, {}).mode) == "tactical")
	var again: Dictionary = phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_B", "player": 2})
	_check("the active player's phase continues", again.get("success", false) or str(again.get("errors", [])).contains("already"), str(again.get("errors", again.get("error", ""))))


func _test_pilin_out_ai() -> void:
	print("\n-- 5. Pilin' Out, AI Ork player: answered synchronously, the Nobz are auto-placed, no stall --")
	_load("ork11e_g2_pilin_out")
	var phase = _movement()
	AI.enabled = true
	AI.ai_players = {1: true, 2: false}
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_B", "player": 2})
	_drain(phase)
	_stage(phase, "U_CUSTODIAN_GUARD_B", 0.0, -5.0, 2)
	var c: Dictionary = phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_B", "player": 2})
	_check("CONFIRM_UNIT_MOVE succeeds", c.get("success", false), str(c.get("errors", c.get("error", ""))))
	_check("the AI answered the window (nothing pending for P1)", not phase.has_pending_stratagem_window() and phase.get_pending_stratagem_window_decider() == 0)
	_check("the AI used Pilin' Out: the Nobz disembarked", _u("U_NOBZ_A").get("embarked_in", null) == null and _u("U_NOBZ_A").models[0].get("position", null) != null)
	_check("... with the rapid mode's charge lock", bool(_flags("U_NOBZ_A").get("cannot_charge", false)))
	var e: Dictionary = phase.execute_action({"type": "END_MOVEMENT", "player": 2})
	_drain(phase)
	_check("the phase can still end", e.get("success", false) and GS.get_current_phase() != P_MOV, str(e.get("errors", e.get("error", ""))) + " phase=" + str(GS.get_current_phase()))
	AI.enabled = false
	AI.ai_players = {1: false, 2: false}


# ── 6-7. DEFF FROM THE SHADOWS ───────────────────────────────────────

func _test_deff_from_the_shadows() -> void:
	print("\n-- 6. Deff from the Shadows: free ingress at the end of the opponent's Movement phase, round 1 too --")
	_load("ork11e_g2_deff_shadows")
	_check("fixture: battle round 1, Snikrot in strategic reserves", GS.get_battle_round() == 1 and int(_u("U_BOSS_SNIKROT_A").status) == 7)
	_set_phase(P_MOV, 2)
	_check("offered to the Ork player in the opponent's Movement phase", OA.deff_from_the_shadows_units(1) == ["U_BOSS_SNIKROT_A"])
	_check("not to the active player", OA.deff_from_the_shadows_units(2).is_empty())
	_set_phase(P_MOV, 1)
	_check("not in the Ork player's own Movement phase", OA.deff_from_the_shadows_units(1).is_empty())
	_set_phase(P_SHOOT, 2)
	_check("not at another phase", OA.deff_from_the_shadows_units(1).is_empty())
	var phase = _movement()
	var cp1 := int(GS.state.players["1"]["cp"])
	var end_res: Dictionary = phase.execute_action({"type": "END_MOVEMENT", "player": 2})
	_check("END_MOVEMENT (round 1) offers the prompt to the Ork player", end_res.get("trigger_rapid_ingress", false) and int(end_res.get("rapid_ingress_player", 0)) == 1, str(end_res.keys()))
	var rows: Array = _rows(end_res)
	var r: Dictionary = _row(rows, "U_BOSS_SNIKROT_A")
	_check("Snikrot's row: Deff from the Shadows, 0 CP", str(r.get("via", "")) == "deff_from_the_shadows" and int(r.get("cp_cost", -1)) == 0, str(r))
	_check("round 1: no Rapid Ingress rows (15.07)", rows.size() == 1)
	_check("RAPID INGRESS itself is still barred in round 1", not SM.can_use_stratagem(1, "rapid_ingress").can_use)
	var u: Dictionary = phase.execute_action({"type": "USE_RAPID_INGRESS", "player": 1, "unit_id": "U_BOSS_SNIKROT_A"})
	_check("USE (Snikrot) succeeds", u.get("success", false), str(u.get("error", u.get("errors", ""))))
	_check("no CP spent, no stratagem use recorded", int(GS.state.players["1"]["cp"]) == cp1 and SM._usage_history.get("1", []).is_empty())
	_check("the round-1 set-up is allowed for it", ARR.round_one_allowed("U_BOSS_SNIKROT_A"))
	var near_enemy: Dictionary = _place_ri(phase, "U_BOSS_SNIKROT_A", [Vector2(22.0 * PX, 18.0 * PX)], 1)
	_check("20.04: a set-up not near a battlefield edge is refused", not near_enemy.get("success", true), str(near_enemy.get("error", "")))
	var in_dz: Dictionary = _place_ri(phase, "U_BOSS_SNIKROT_A", [Vector2(1.0 * PX, 55.0 * PX)], 1)
	_check("20.04 before round 3: not in the opponent's deployment zone", not in_dz.get("success", true), str(in_dz.get("error", "")))
	var ok: Dictionary = _place_ri(phase, "U_BOSS_SNIKROT_A", [Vector2(1.0 * PX, 30.0 * PX)], 1)
	_check("a legal ingress set-up (left edge, mid-board) succeeds", ok.get("success", false), str(ok.get("error", ok.get("errors", ""))))
	_check("Snikrot is DEPLOYED", int(_u("U_BOSS_SNIKROT_A").status) == 2)
	_check("no re-offer (nothing left), the Movement phase moves on", not ok.get("trigger_rapid_ingress", false))
	_drain(phase)
	_check("... and ends", GS.get_current_phase() != P_MOV, str(GS.get_current_phase()))
	# Battle-shocked: not a stratagem — still offered.
	_load("ork11e_g2_deff_shadows")
	_flags("U_BOSS_SNIKROT_A")["battle_shocked"] = true
	_set_phase(P_MOV, 2)
	_check("battle-shocked: still offered (an ability, not a stratagem)", OA.deff_from_the_shadows_units(1) == ["U_BOSS_SNIKROT_A"])
	# Decline.
	_flags("U_BOSS_SNIKROT_A").erase("battle_shocked")
	phase = _movement()
	phase.execute_action({"type": "END_MOVEMENT", "player": 2})
	var dec: Dictionary = phase.execute_action({"type": "DECLINE_RAPID_INGRESS", "player": 1})
	_drain(phase)
	_check("DECLINE: Snikrot stays in reserves, the phase ends", dec.get("success", false) and int(_u("U_BOSS_SNIKROT_A").status) == 7 and GS.get_current_phase() != P_MOV)
	# A normal reserve unit still cannot arrive in round 1.
	_load("ork11e_g2_deff_shadows")
	_check("a unit without the ability gets no round-1 allowance", not ARR.round_one_allowed("U_BOYZ_C"))


func _test_deff_round2_mixed_and_ai() -> void:
	print("\n-- 7. Deff from the Shadows in round 2 next to Rapid Ingress; the AI path --")
	_load("ork11e_g2_deff_shadows")
	GS.state.meta["battle_round"] = 2
	var bz: Dictionary = _u("U_BOYZ_C")
	bz["status"] = 7
	bz["reserve_type"] = "strategic_reserves"
	for m in bz.models:
		m["position"] = null
	var phase = _movement()
	var e: Dictionary = phase.execute_action({"type": "END_MOVEMENT", "player": 2})
	var rows: Array = _rows(e)
	_check("two rows: Snikrot (free) + Boyz (Rapid Ingress, 1 CP)", str(_row(rows, "U_BOSS_SNIKROT_A").get("via", "")) == "deff_from_the_shadows"
		and str(_row(rows, "U_BOYZ_C").get("via", "")) == "rapid_ingress" and int(_row(rows, "U_BOYZ_C").get("cp_cost", 0)) == 1, str(rows))
	phase.execute_action({"type": "USE_RAPID_INGRESS", "player": 1, "unit_id": "U_BOSS_SNIKROT_A"})
	var p1: Dictionary = _place_ri(phase, "U_BOSS_SNIKROT_A", [Vector2(1.0 * PX, 30.0 * PX)], 1)
	_check("Snikrot arrives; the prompt is offered again (Rapid Ingress still unused)", p1.get("success", false) and p1.get("trigger_rapid_ingress", false) and _row_ids(_rows(p1)) == ["U_BOYZ_C"], str(_row_ids(_rows(p1))))
	var cp := int(GS.state.players["1"]["cp"])
	var u2: Dictionary = phase.execute_action({"type": "USE_RAPID_INGRESS", "player": 1, "unit_id": "U_BOYZ_C"})
	_check("Rapid Ingress on the Boyz costs 1 CP", u2.get("success", false) and int(GS.state.players["1"]["cp"]) == cp - 1, str(u2.get("error", "")))
	var two_rows: Array = _line("U_BOYZ_C", 30.0, 1.2, 1.45).slice(0, 5)
	two_rows.append_array(_line("U_BOYZ_C", 30.0, 2.7, 1.45).slice(0, 5))
	var p2: Dictionary = _place_ri(phase, "U_BOYZ_C", two_rows, 1)
	_check("the Boyz arrive; nothing left to offer", p2.get("success", false) and not p2.get("trigger_rapid_ingress", false), str(p2.get("error", p2.get("errors", ""))))
	_drain(phase)
	# AI: a free row is not refused for lack of CP.
	_load("ork11e_g2_deff_shadows")
	GS.state.players["1"]["cp"] = 0
	_set_phase(P_MOV, 2)
	var arows: Array = ARR.offer_rows(1, [])
	var ADM = load("res://scripts/AIDecisionMaker.gd")
	var dec: Dictionary = ADM.evaluate_rapid_ingress(1, arows, GS.create_snapshot(false))
	_check("AI with 0 CP: the free Deff row is evaluated (not declined for CP)", not str(dec.get("_ai_description", "")).contains("insufficient CP") and not str(dec.get("_ai_description", "")).contains("saving CP"), str(dec.get("_ai_description", "")))
	# Full AI flow: END_MOVEMENT with the AI as the Ork player — the signal path must not stall.
	phase = _movement()
	AI.enabled = true
	AI.ai_players = {1: true, 2: false}
	AI._connect_phase_stratagem_signals()
	var ae: Dictionary = phase.execute_action({"type": "END_MOVEMENT", "player": 2})
	_check("AI Ork player: the prompt is raised", ae.get("trigger_rapid_ingress", false))
	for i in range(30):
		await process_frame
		if GS.get_current_phase() != P_MOV or not phase.has_pending_end_of_phase_prompt():
			break
	_check("AI Ork player: the prompt is answered (no stall)", not phase.has_pending_end_of_phase_prompt() or GS.get_current_phase() != P_MOV,
		"awaiting=%s unit=%s" % [str(phase._awaiting_rapid_ingress), str(phase._rapid_ingress_unit_id)])
	print("    (AI decision: Snikrot status %d)" % int(_u("U_BOSS_SNIKROT_A").status))
	AI.enabled = false
	AI.ai_players = {1: false, 2: false}


# ── 8-9. SWIFT RUIN ──────────────────────────────────────────────────

func _test_swift_ruin() -> void:
	print("\n-- 8. Swift Ruin through the end-of-Movement Rapid Ingress prompt --")
	_load("cus11e_g2_swift_ruin")
	var phase = _movement()
	var cp := int(GS.state.players["2"]["cp"])
	var e: Dictionary = phase.execute_action({"type": "END_MOVEMENT", "player": 1})
	var rows: Array = _rows(e)
	_check("END_MOVEMENT offers Rapid Ingress to the Custodes player", e.get("trigger_rapid_ingress", false) and int(e.get("rapid_ingress_player", 0)) == 2)
	var vr: Dictionary = _row(rows, "U_VENATARI_VL_A")
	var wr: Dictionary = _row(rows, "U_WITCHSEEKERS_A")
	_check("Venatari row: 0 CP (Swift Ruin -1 CP) with a note", int(vr.get("cp_cost", -1)) == 0 and str(vr.get("note", "")).contains("Swift Ruin"), str(vr))
	_check("Witchseekers row: 1 CP, no note", int(wr.get("cp_cost", -1)) == 1 and not wr.has("note"), str(wr))
	var u: Dictionary = phase.execute_action({"type": "USE_RAPID_INGRESS", "player": 2, "unit_id": "U_VENATARI_VL_A"})
	_check("USE on the Venatari succeeds at 0 CP", u.get("success", false) and int(GS.state.players["2"]["cp"]) == cp, str(u.get("error", "")) + " cp=" + str(GS.state.players["2"]["cp"]))
	var hist: Array = SM._usage_history.get("2", [])
	_check("the use is recorded as the Swift Ruin one", hist.size() == 1 and bool(hist[0].get("cus11e_swift_ruin", false)))
	var pl: Dictionary = _place_ri(phase, "U_VENATARI_VL_A", [Vector2(1.2 * PX, 28.0 * PX), Vector2(1.2 * PX, 30.0 * PX), Vector2(1.2 * PX, 32.0 * PX)], 2)
	_check("the Venatari arrive", pl.get("success", false) and int(_u("U_VENATARI_VL_A").status) == 2, str(pl.get("error", pl.get("errors", ""))))
	_check("the prompt is offered again: Swift Ruin does not prevent the Witchseekers' Rapid Ingress", pl.get("trigger_rapid_ingress", false) and _row_ids(_rows(pl)) == ["U_WITCHSEEKERS_A"], str(_row_ids(_rows(pl))))
	_check("... the phase still holds", phase.has_pending_end_of_phase_prompt() and GS.get_current_phase() == P_MOV)
	var u2: Dictionary = phase.execute_action({"type": "USE_RAPID_INGRESS", "player": 2, "unit_id": "U_WITCHSEEKERS_A"})
	_check("second Rapid Ingress this phase (Witchseekers) succeeds, 1 CP", u2.get("success", false) and int(GS.state.players["2"]["cp"]) == cp - 1, str(u2.get("error", "")))
	var pl2: Dictionary = _place_ri(phase, "U_WITCHSEEKERS_A", [Vector2(42.8 * PX, 26.0 * PX), Vector2(42.8 * PX, 27.6 * PX), Vector2(42.8 * PX, 29.2 * PX), Vector2(42.8 * PX, 30.8 * PX), Vector2(42.8 * PX, 32.4 * PX)], 2)
	_check("the Witchseekers arrive; nothing left, the phase moves on", pl2.get("success", false) and not pl2.get("trigger_rapid_ingress", false), str(pl2.get("error", pl2.get("errors", ""))))
	_drain(phase)
	_check("... and the Movement phase ends", GS.get_current_phase() != P_MOV)


func _test_swift_ruin_reverse_and_limits() -> void:
	print("\n-- 9. Swift Ruin: after another Rapid Ingress; once per phase per army; CP edges --")
	_load("cus11e_g2_swift_ruin")
	var phase = _movement()
	var cp := int(GS.state.players["2"]["cp"])
	phase.execute_action({"type": "END_MOVEMENT", "player": 1})
	var u: Dictionary = phase.execute_action({"type": "USE_RAPID_INGRESS", "player": 2, "unit_id": "U_WITCHSEEKERS_A"})
	_check("Witchseekers first (1 CP)", u.get("success", false) and int(GS.state.players["2"]["cp"]) == cp - 1)
	var pl: Dictionary = _place_ri(phase, "U_WITCHSEEKERS_A", [Vector2(42.8 * PX, 26.0 * PX), Vector2(42.8 * PX, 27.6 * PX), Vector2(42.8 * PX, 29.2 * PX), Vector2(42.8 * PX, 30.8 * PX), Vector2(42.8 * PX, 32.4 * PX)], 2)
	_check("re-offer: the Venatari, regardless of the use this phase, at 0 CP", pl.get("trigger_rapid_ingress", false) and _row_ids(_rows(pl)) == ["U_VENATARI_VL_A"] and int(_row(_rows(pl), "U_VENATARI_VL_A").get("cp_cost", -1)) == 0, str(_rows(pl)))
	var u2: Dictionary = phase.execute_action({"type": "USE_RAPID_INGRESS", "player": 2, "unit_id": "U_VENATARI_VL_A"})
	_check("... the use succeeds (0 CP)", u2.get("success", false) and int(GS.state.players["2"]["cp"]) == cp - 1, str(u2.get("error", "")))
	var pl2: Dictionary = _place_ri(phase, "U_VENATARI_VL_A", [Vector2(1.2 * PX, 28.0 * PX), Vector2(1.2 * PX, 30.0 * PX), Vector2(1.2 * PX, 32.0 * PX)], 2)
	_check("... the Venatari arrive; nothing left to offer", pl2.get("success", false) and not pl2.get("trigger_rapid_ingress", false), str(pl2.get("error", pl2.get("errors", ""))))
	_drain(phase)
	# Limits, at the row level.
	_load("cus11e_g2_swift_ruin")
	_set_phase(P_MOV, 1)
	var cands: Array = [{"unit_id": "U_VENATARI_VL_A", "unit_name": "V", "reserve_type": "strategic_reserves"},
		{"unit_id": "U_WITCHSEEKERS_A", "unit_name": "W", "reserve_type": "strategic_reserves"}]
	GS.state.players["2"]["cp"] = 0
	var r0: Array = ARR.offer_rows(2, cands)
	_check("0 CP: only the Venatari row (Swift Ruin, 0 CP)", _row_ids(r0) == ["U_VENATARI_VL_A"], str(_row_ids(r0)))
	GS.state.players["2"]["cp"] = 6
	CA.swift_ruin_record(2)
	var r1: Array = ARR.offer_rows(2, cands)
	_check("Swift Ruin already used this phase (once per phase, per army): the Venatari row costs 1 CP", int(_row(r1, "U_VENATARI_VL_A").get("cp_cost", -1)) == 1 and not _row(r1, "U_VENATARI_VL_A").has("note"), str(r1))
	GS.state.players["2"].erase(CA.ARMY_USES)
	_check("battle round 1: no Rapid Ingress rows, Swift Ruin included (15.07)", _round1_rows(cands).is_empty())
	_check("preview_cp_cost shows Swift Ruin", SM.preview_cp_cost(2, "rapid_ingress", "U_VENATARI_VL_A") == 0 and SM.preview_cp_cost(2, "rapid_ingress", "U_WITCHSEEKERS_A") == 1)
	_flags("U_VENATARI_VL_A")["battle_shocked"] = true
	_check("battle-shocked Venatari: no stratagem target (15.07), no row", not "U_VENATARI_VL_A" in _row_ids(ARR.offer_rows(2, _phase_candidates(2))))


func _round1_rows(cands: Array) -> Array:
	var keep := int(GS.state.meta.get("battle_round", 2))
	GS.state.meta["battle_round"] = 1
	var r: Array = ARR.offer_rows(2, cands)
	GS.state.meta["battle_round"] = keep
	return r


func _phase_candidates(player: int) -> Array:
	var phase = PM.get_current_phase_instance()
	if phase != null and phase.has_method("_get_rapid_ingress_eligible_units"):
		return phase._get_rapid_ingress_eligible_units(player)
	return []


# ── 10. Dialog text ──────────────────────────────────────────────────

func _test_dialogs() -> void:
	print("\n-- 10. Dialogs: the rows' costs and notes; the shock / Pilin' Out disembark text --")
	_load("cus11e_g2_swift_ruin")
	_set_phase(P_MOV, 1)
	var rows: Array = ARR.offer_rows(2, _phase_candidates(2)) if not _phase_candidates(2).is_empty() else ARR.offer_rows(2, [
		{"unit_id": "U_VENATARI_VL_A", "unit_name": "Venatari with Verutum Lances", "reserve_type": "strategic_reserves"},
		{"unit_id": "U_WITCHSEEKERS_A", "unit_name": "Witchseeker Squad", "reserve_type": "strategic_reserves"}])
	var dlg = AcceptDialog.new()
	dlg.set_script(load("res://dialogs/RapidIngressDialog.gd"))
	root.add_child(dlg)
	dlg.setup(2, rows)
	var vb = dlg.find_child("Use_U_VENATARI_VL_A", true, false)
	var wb = dlg.find_child("Use_U_WITCHSEEKERS_A", true, false)
	var note = dlg.find_child("Note_U_VENATARI_VL_A", true, false)
	_check("RapidIngressDialog: 'Arrive (0 CP)' on the Venatari, 'Arrive (1 CP)' on the Witchseekers", vb != null and vb.text == "Arrive (0 CP)" and wb != null and wb.text == "Arrive (1 CP)",
		"%s / %s" % [vb.text if vb else "-", wb.text if wb else "-"])
	_check("... with the Swift Ruin note", note != null and str(note.text).contains("Swift Ruin"))
	_check("... and a per-row cost line", str(dlg.find_child("CostLabel", true, false).text).contains("shown on each unit"))
	dlg._resolved = true
	dlg.queue_free()
	_load("ork11e_g2_deff_shadows")
	_set_phase(P_MOV, 2)
	var drows: Array = ARR.offer_rows(1, [])
	var d2 = AcceptDialog.new()
	d2.set_script(load("res://dialogs/RapidIngressDialog.gd"))
	root.add_child(d2)
	d2.setup(1, drows)
	var sb = d2.find_child("Use_U_BOSS_SNIKROT_A", true, false)
	_check("Deff only: header DEFF FROM THE SHADOWS, 'Arrive (free)'", str(d2.find_child("Header", true, false).text) == "DEFF FROM THE SHADOWS" and sb != null and sb.text == "Arrive (free)")
	d2._resolved = true
	d2.queue_free()
	# DisembarkDialog: the advanced Coronus no longer says "Cannot disembark".
	_load("cus11e_g2_assault_vehicle")
	_set_phase(P_MOV, 2)
	_flags("U_CORONUS_A")["advanced"] = true
	_flags("U_CORONUS_A")["moved"] = true
	var dd = load("res://scripts/DisembarkDialog.gd").new()
	root.add_child(dd)
	dd.setup("U_GUARD_A")
	_check("DisembarkDialog after the Coronus' advance: ASSAULT VEHICLE shock disembark, OK enabled",
		str(dd.dialog_text).contains("ASSAULT VEHICLE") and not dd.get_ok_button().disabled, str(dd.dialog_text).substr(0, 160))
	dd.queue_free()
	_load("ork11e_g2_pilin_out")
	_set_phase(P_MOV, 2)
	_flags("U_TRUKK_A")[OA.F_PILIN_OUT] = OA._phase_key()
	var pd = load("res://scripts/DisembarkDialog.gd").new()
	root.add_child(pd)
	pd.setup("U_NOBZ_A")
	_check("DisembarkDialog during Pilin' Out: PILIN' OUT rapid disembark, no combat toggle", str(pd.dialog_text).contains("PILIN' OUT") and pd.combat_checkbox == null)
	pd.queue_free()
