extends SceneTree

# 11e FIRE OVERWATCH (15.08) + RAPID INGRESS (15.07): the reactive core
# stratagems of the END of the opponent's Movement phase.
#
# docs/rules/40k_11th_edition_core_rules.txt:
#   FIRE OVERWATCH 15.08 — "WHEN: End of your opponent's Movement phase.
#     TARGET: One friendly unengaged unit (excluding TITANIC units).
#     EFFECT: Your unit shoots using snap shooting (see below)."
#   SNAP SHOOTING 15.09 — "WHILE SHOOTING: You can only target one visible
#     enemy unit within 24" of your unit (and only if it is an eligible
#     target). Each attack only hits on an unmodified hit roll of 6
#     (irrespective of the attacking weapon's BS characteristic or any
#     modifiers). You cannot re-roll hit rolls. AFTER SHOOTING: Until the end
#     of the phase, your unit is not eligible to start an action."
#   RAPID INGRESS 15.07 — "WHEN: End of your opponent's Movement phase.
#     TARGET: One friendly unit that is in strategic reserves (excluding
#     AIRCRAFT). ... RESTRICTIONS: You cannot use this stratagem during the
#     first battle round."
#   USING STRATAGEMS 15.01 — "Each player cannot use the same stratagem more
#     than once in the same phase." / "Reduce your CP total by the CP cost".
#   Battle-shock — "Its controlling player cannot target that unit with
#     stratagems (15)."
#   LONE OPERATIVE 24.24 — "this unit is not visible to enemy models unless
#     they are within 12" of this unit".
#   LEVEL OF CONTROL 14.02 — "At the end of each phase and turn, to determine
#     a player's level of control over an objective ...".
#   SAVE ROLLS 05.03 — "The opposing player resolves the following sequence:
#     1. Create Groups ... 2. Allocation Order ... 3. Make Save Rolls".
#
# Board: ork11e_orks_reactive (round 2, P1 Custodes active, P2 Orks), trimmed
# to the units each case needs and repositioned. Everything goes through the
# real MovementPhase.execute_action path (END_MOVEMENT -> movement_phase_end
# window -> USE/DECLINE_WINDOW_STRATAGEM).
#
# Usage: godot --headless --path . -s tests/test_fire_overwatch_15_08_11e.gd

const FIXTURE := "res://tests/saves/ork11e_orks_reactive.w40ksave"
const PX := 40.0
const FO := "fire_overwatch_11e"
const W_END := "movement_phase_end"

var passed := 0
var failed := 0
var _started := false

var GS
var SM
var PM
var RE
var MM
var AI

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

## Load the fixture, keep only `keep`, clear terrain/objectives/usage, 6 CP each.
func _load(keep: Array) -> void:
	var slm = root.get_node("SaveLoadManager")
	var ok: bool = slm.load_game_from_file_path(FIXTURE)
	# Written AFTER the load (a load re-applies the boot edition).
	GameConstants.edition = 11
	if not ok:
		_check("fixture %s loads" % FIXTURE, false)
		return
	var units: Dictionary = {}
	for uid in keep:
		if GS.state.units.has(uid):
			units[uid] = GS.state.units[uid]
	GS.state.units = units
	GS.state.board["objectives"] = []
	GS.state.meta["battle_round"] = 2
	GS.state.meta["active_player"] = 1
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 6
	root.get_node("TerrainManager").terrain_features = []
	SM._usage_history = {"1": [], "2": []}
	MM.objective_control_state = {}
	MM.objective_contested_state = {}
	AI.enabled = false
	AI.ai_players = {1: false, 2: false}
	# Most cases resolve the defender's saves with the engine's 11e allocation
	# (the "computer allocates wounds" setting) so the snap shot finishes in the
	# window answer; (l) turns it off and drives the defender's APPLY_SAVES.
	root.get_node("SettingsService").auto_allocate_wounds = true

## Put the alive models of `uid` in a row starting at (x_in, y_in), `step` inches apart.
func _place(uid: String, x_in: float, y_in: float, step: float = 1.8) -> void:
	var i := 0
	for m in GS.state.units[uid].models:
		if m.get("alive", true):
			m["position"] = {"x": (x_in + i * step) * PX, "y": y_in * PX}
			i += 1

func _movement() -> Node:
	PM.transition_to_phase(GameStateData.Phase.MOVEMENT)
	var phase = PM.get_current_phase_instance()
	var guard := 0
	while phase != null and phase.has_pending_stratagem_window() and guard < 6:
		var w = phase.get_pending_stratagem_window()
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.player), "window_id": str(w.window_id)})
		guard += 1
	return phase

## END_MOVEMENT by P1; the active player's own movement_phase_end window (if
## any) is declined. Returns {"end": result, "window": P2's pending window or {}}.
func _end_movement(phase: Node) -> Dictionary:
	var end_res: Dictionary = phase.execute_action({"type": "END_MOVEMENT", "player": 1})
	var guard := 0
	while phase.has_pending_stratagem_window() and int(phase.get_pending_stratagem_window().player) == 1 and guard < 4:
		var w = phase.get_pending_stratagem_window()
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 1, "window_id": str(w.window_id)})
		guard += 1
	var win: Dictionary = phase.get_pending_stratagem_window() if phase.has_pending_stratagem_window() else {}
	return {"end": end_res, "window": win}

func _fo_offer(window: Dictionary) -> Dictionary:
	for o in window.get("offers", []):
		if str(o.get("stratagem_id", "")) == FO:
			return o
	return {}

func _row(offer: Dictionary, uid: String) -> Dictionary:
	for t in offer.get("targets", []):
		if str(t.get("unit_id", "")) == uid:
			return t
	return {}

func _row_ids(offer: Dictionary) -> Array:
	return offer.get("targets", []).map(func(t): return str(t.get("unit_id", "")))

func _option_ids(row: Dictionary) -> Array:
	return row.get("secondary", {}).get("options", []).map(func(o): return str(o.get("id", "")))

func _snap_ids(shooter: String) -> Array:
	return RE.snap_shooting_targets_11e(shooter, GS.create_snapshot()).map(func(t): return str(t.unit_id))

func _log_has(fragment: String) -> bool:
	for e in root.get_node("GameEventLog").entries:
		if fragment in str(e.get("text", "")):
			return true
	return false

func _skip_p1_windows(phase: Node) -> void:
	var guard := 0
	while phase.has_pending_stratagem_window() and int(phase.get_pending_stratagem_window().player) == 1 and guard < 4:
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 1, "window_id": str(phase.get_pending_stratagem_window().window_id)})
		guard += 1

func _use_fo(phase: Node, shooter: String, target: String) -> Dictionary:
	return phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 2, "window_id": W_END,
		"stratagem_id": FO, "target_unit_id": shooter, "context": {"secondary_id": target}})

func _wall(id: String, x0_in: float, y0_in: float, x1_in: float, y1_in: float) -> Dictionary:
	var x0 := x0_in * PX
	var y0 := y0_in * PX
	var x1 := x1_in * PX
	var y1 := y1_in * PX
	return {"id": id, "type": "ruins", "height_category": "tall",
		"polygon": PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]),
		"position": Vector2((x0 + x1) / 2.0, (y0 + y1) / 2.0), "size": Vector2(x1 - x0, y1 - y0), "rotation": 0.0,
		"can_move_through": {"INFANTRY": true, "VEHICLE": false, "MONSTER": false}}

# Standard board: Custodian Guard A (P1) 10" north of Gretchin C (P2).
func _std_board(extra: Array = []) -> void:
	_load(["U_CUSTODIAN_GUARD_A", "U_CUSTODIAN_GUARD_B", "U_GRETCHIN_C", "U_BOYZ_B", "U_WARBOSS_A"] + extra)
	_place("U_CUSTODIAN_GUARD_A", 8.0, 20.0)
	_place("U_CUSTODIAN_GUARD_B", 30.0, 6.0)      # far away (> 24" from every Ork)
	_place("U_GRETCHIN_C", 6.0, 30.0, 1.4)       # ~8.7" edge from CG_A (grot blastas: 12")
	# Resolved loadout: the Boyz carry 12" sluggas / kombi-skorcha, their
	# attached Warboss an 18" kustom shoota — only HIS gun reaches CG_A.
	_place("U_BOYZ_B", 6.0, 36.0, 1.4)           # ~14.7" edge from CG_A
	_place("U_WARBOSS_A", 22.0, 36.0)

# ── run ──────────────────────────────────────────────────────────────

func _run_tests():
	if _started:
		return
	_started = true
	print("\n=== test_fire_overwatch_15_08_11e ===")
	GS = root.get_node("GameState")
	SM = root.get_node("StratagemManager")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	MM = root.get_node("MissionManager")
	AI = root.get_node("AIPlayer")
	var prev_edition = GameConstants.edition
	# Written AFTER the first timer (SettingsService overwrites _init writes).
	GameConstants.edition = 11
	_check("harness runs this suite at edition 11", GameConstants.edition == 11, str(GameConstants.edition))

	_test_no_per_move_offer()
	_test_window_offer_non_active_only()
	_test_shooter_restrictions()
	_test_snap_targets_range_visibility_lone_operative()
	_test_attached_leader_counts()
	_test_unmodified_sixes_and_no_rerolls()
	_test_use_spends_cp_and_resolves()
	_test_server_side_validation()
	_test_once_per_turn_and_decline()
	_test_rapid_ingress_window()
	_test_objective_recheck_after_kills()
	_test_ai_defender()
	_test_defender_allocates_saves()
	_test_summary_counts_target_casualties()
	_test_10e_unchanged()

	RE.set_test_seed(-1)
	GameConstants.edition = prev_edition
	print("\n=== %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

# ── (a) no per-move / per-set-up offer at 11e ─────────────────────────

func _test_no_per_move_offer() -> void:
	print("\n-- (a) 11e: no per-move Fire Overwatch offer (15.08 has one WHEN) --")
	_std_board()
	var phase = _movement()
	var r: Dictionary = phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_A", "player": 1})
	_check("BEGIN_NORMAL_MOVE succeeds next to the Gretchin", r.get("success", false), str(r.get("error", "")))
	_check("…and offers NO per-move Fire Overwatch (trigger_fire_overwatch absent)",
		not r.get("trigger_fire_overwatch", false) and not phase._awaiting_fire_overwatch, str(r.keys()))
	for ctx in ["normal move start", "move end", "fall back move start", "reinforcement set up", "rapid ingress set up"]:
		_check("_check_fire_overwatch_opportunity('%s') does not trigger at 11e" % ctx,
			not phase._check_fire_overwatch_opportunity("U_CUSTODIAN_GUARD_A", ctx).get("triggered", true))
	var v: Dictionary = SM.can_use_stratagem(2, "fire_overwatch")
	_check("outside the movement_phase_end window FIRE OVERWATCH is refused ('Offered automatically when the Movement phase ends')",
		not v.can_use and "Offered automatically" in str(v.reason) and "Movement phase ends" in str(v.reason), str(v))
	_check("…so the S panel cannot spend CP on it mid-phase", not SM.is_fire_overwatch_available(2).available)

# ── (b) END_MOVEMENT opens the window for the non-active player only ──

func _test_window_offer_non_active_only() -> void:
	print("\n-- (b) END_MOVEMENT: FIRE OVERWATCH offered once, to the NON-active player only --")
	_std_board()
	var phase = _movement()
	var p1_offers: Array = SM.get_window_offers(1, W_END, {"phase": "movement"})
	_check("the ACTIVE player (P1) is never offered FIRE OVERWATCH",
		p1_offers.filter(func(o): return o.stratagem_id == FO).is_empty(), str(p1_offers.map(func(o): return o.stratagem_id)))
	var em := _end_movement(phase)
	var win: Dictionary = em.window
	_check("END_MOVEMENT succeeded and the phase is still MOVEMENT (waiting)",
		em.end.get("success", false) and GS.get_current_phase() == GameStateData.Phase.MOVEMENT, str(em.end.get("error", "")))
	_check("the pending window is P2's movement_phase_end", int(win.get("player", 0)) == 2 and str(win.get("window_id", "")) == W_END, str(win.keys()))
	_check("the END_MOVEMENT result stamps the window for the network mirror",
		em.end.has("stratagem_window_opened") or phase.has_pending_stratagem_window())
	var offer := _fo_offer(win)
	_check("P2's window offers FIRE OVERWATCH (1 CP)", not offer.is_empty() and int(offer.get("cp_cost", 0)) == 1, str(win.get("offers", []).map(func(o): return o.stratagem_id)))
	var g := _row(offer, "U_GRETCHIN_C")
	_check("Gretchin C has a row whose secondary is the snap-target pick (kind 'unit')",
		not g.is_empty() and str(g.get("secondary", {}).get("kind", "")) == "unit", str(g))
	_check("…and Custodian Guard A (10\" away, visible) is its option", "U_CUSTODIAN_GUARD_A" in _option_ids(g), str(_option_ids(g)))
	_check("…Custodian Guard B (> 24\" away) is not", not ("U_CUSTODIAN_GUARD_B" in _option_ids(g)), str(_option_ids(g)))
	_check("19.01: the attached Warboss has NO row of his own; Boyz B heads the Attached unit's row",
		not ("U_WARBOSS_A" in _row_ids(offer)) and "U_BOYZ_B" in _row_ids(offer), str(_row_ids(offer)))
	_check("15.08 does not require the enemy to have moved (Custodian Guard A remained stationary)",
		GS.state.units["U_CUSTODIAN_GUARD_A"].get("flags", {}).get("remained_stationary", false) and "U_CUSTODIAN_GUARD_A" in _option_ids(g))
	_check("the decider is P2 (AIPlayer / UI idle on it)", phase.get_pending_stratagem_window_decider() == 2)

# ── (c) TARGET: unengaged, not TITANIC, not battle-shocked ────────────

func _test_shooter_restrictions() -> void:
	print("\n-- (c) TARGET: one friendly UNENGAGED unit, not TITANIC, not battle-shocked --")
	_load(["U_CUSTODIAN_GUARD_A", "U_CUSTODIAN_GUARD_B", "U_GRETCHIN_C", "U_GRETCHIN_D", "U_TANKBUSTAS_A", "U_NOBZ_A", "U_KOMMANDOS_A"])
	_place("U_CUSTODIAN_GUARD_A", 8.0, 20.0)
	_place("U_CUSTODIAN_GUARD_B", 30.0, 20.0)
	_place("U_GRETCHIN_C", 6.0, 30.0, 1.4)        # eligible
	_place("U_GRETCHIN_D", 30.0, 21.6, 1.4)       # base-to-base with CG_B -> engaged
	_place("U_TANKBUSTAS_A", 6.0, 34.0)           # battle-shocked
	_place("U_NOBZ_A", 6.0, 38.0)                 # given TITANIC below
	_place("U_KOMMANDOS_A", 20.0, 34.0, 1.4)
	GS.state.units["U_TANKBUSTAS_A"].flags["battle_shocked"] = true
	GS.state.units["U_NOBZ_A"].meta.keywords.append("TITANIC")
	var board = GS.create_snapshot()
	_check("Gretchin D is engaged (2\" engagement range, live check)", RE.is_attached_unit_engaged("U_GRETCHIN_D", board))
	_check("reason: engaged", "engaged" in SM.fire_overwatch_shooter_reason_11e(2, "U_GRETCHIN_D", board), SM.fire_overwatch_shooter_reason_11e(2, "U_GRETCHIN_D", board))
	_check("reason: battle-shocked", "battle-shocked" in SM.fire_overwatch_shooter_reason_11e(2, "U_TANKBUSTAS_A", board))
	_check("reason: TITANIC", "TITANIC" in SM.fire_overwatch_shooter_reason_11e(2, "U_NOBZ_A", board))
	_check("reason: Sneaky Gitz (Kommandos cannot fire overwatch)", "Sneaky Gitz" in SM.fire_overwatch_shooter_reason_11e(2, "U_KOMMANDOS_A", board))
	_check("reason: an enemy unit is never a target", SM.fire_overwatch_shooter_reason_11e(2, "U_CUSTODIAN_GUARD_A", board) != "")
	_check("Gretchin C may be targeted", SM.fire_overwatch_shooter_reason_11e(2, "U_GRETCHIN_C", board) == "", SM.fire_overwatch_shooter_reason_11e(2, "U_GRETCHIN_C", board))
	var phase = _movement()
	var offer := _fo_offer(_end_movement(phase).window)
	var rows := _row_ids(offer)
	_check("offer rows include Gretchin C", "U_GRETCHIN_C" in rows, str(rows))
	_check("no row for the ENGAGED Gretchin D", not ("U_GRETCHIN_D" in rows), str(rows))
	_check("no row for the BATTLE-SHOCKED Tankbustas", not ("U_TANKBUSTAS_A" in rows), str(rows))
	_check("no row for the TITANIC Nobz", not ("U_NOBZ_A" in rows), str(rows))
	_check("no row for the Sneaky Gitz Kommandos", not ("U_KOMMANDOS_A" in rows), str(rows))
	var g := _row(offer, "U_GRETCHIN_C")
	_check("17.03: the engaged (non-MONSTER/VEHICLE) Custodian Guard B is not a snap target",
		not ("U_CUSTODIAN_GUARD_B" in _option_ids(g)), str(_option_ids(g)))
	var v: Dictionary = SM.can_use_stratagem(2, FO, "U_TANKBUSTAS_A", {"window_id": W_END})
	_check("server-side: can_use_stratagem refuses the battle-shocked unit", not v.can_use, str(v))
	v = SM.can_use_stratagem(2, FO, "U_GRETCHIN_D", {"window_id": W_END})
	_check("server-side: can_use_stratagem refuses the engaged unit", not v.can_use and "engaged" in str(v.reason), str(v))

# ── (c2) 15.09: within 24", visible, eligible target (Lone Operative) ──

func _test_snap_targets_range_visibility_lone_operative() -> void:
	print("\n-- (c2) 15.09 snap target: within 24\", visible, eligible (Lone Operative 12\") --")
	# The Deff Dread carries a 36" big shoota, so the 24" / Lone Operative
	# exclusions below are 15.09 / 24.24 — never a weapon out of range.
	var SH := "U_DEFF_DREAD_A"
	_load(["U_CUSTODIAN_GUARD_A", "U_BLADE_CHAMPION_A", SH])
	_place(SH, 10.0, 40.0)
	_place("U_BLADE_CHAMPION_A", 40.0, 6.0)
	_place("U_CUSTODIAN_GUARD_A", 8.0, 13.0)
	var cg_d: float = RE._snap_min_distance_inches([SH], ["U_CUSTODIAN_GUARD_A"], GS.create_snapshot())
	_check("(setup) CG_A is over 24\" away (%.2f\") but inside the big shoota's 36\"" % cg_d, cg_d > 24.0 and cg_d < 30.0)
	_check("> 24\": Custodian Guard A is not a snap target", not ("U_CUSTODIAN_GUARD_A" in _snap_ids(SH)), str(_snap_ids(SH)))
	_check("(control) …though it IS an eligible target for normal shooting", RE.get_eligible_targets(SH, GS.create_snapshot()).has("U_CUSTODIAN_GUARD_A"))
	_place("U_CUSTODIAN_GUARD_A", 8.0, 30.0)
	_check("within 24\" and visible: it is a snap target", "U_CUSTODIAN_GUARD_A" in _snap_ids(SH), str(_snap_ids(SH)))
	# A long tall wall between them: not visible -> not a target.
	var tm = root.get_node("TerrainManager")
	tm.terrain_features = [_wall("fo_wall", 0.0, 34.0, 44.0, 35.0)]
	RE.clear_los_memo()
	var sight = RE.unit_sight_line(SH, "U_CUSTODIAN_GUARD_A", GS.create_snapshot(), false)
	_check("(the wall blocks every sight line)", not sight.get("has_los", true), str(sight))
	_check("not visible: Custodian Guard A is not a snap target", not ("U_CUSTODIAN_GUARD_A" in _snap_ids(SH)), str(_snap_ids(SH)))
	tm.terrain_features = []
	RE.clear_los_memo()
	# Lone Operative (24.24): not visible to enemy models beyond 12".
	_place("U_CUSTODIAN_GUARD_A", 30.0, 6.0)       # out of the way
	GS.state.units["U_BLADE_CHAMPION_A"].meta.abilities.append("Lone Operative")
	_place("U_BLADE_CHAMPION_A", 10.0, 24.0)
	var lo_d: float = RE._snap_min_distance_inches([SH], ["U_BLADE_CHAMPION_A"], GS.create_snapshot())
	_check("Lone Operative at %.1f\" (> 12\", within 24\", visible, in range): not a snap target" % lo_d,
		lo_d > 12.0 and lo_d < 24.0 and not ("U_BLADE_CHAMPION_A" in _snap_ids(SH)), str(_snap_ids(SH)))
	_place("U_BLADE_CHAMPION_A", 10.0, 31.0)
	_check("Lone Operative within 12\": a snap target", "U_BLADE_CHAMPION_A" in _snap_ids(SH), str(_snap_ids(SH)))

# ── (c3) 19.01: the attached leader counts for 24" and shoots ─────────

func _test_attached_leader_counts() -> void:
	print("\n-- (c3) 19.01: the attached Warboss counts for the 24\" and his guns shoot --")
	_load(["U_CUSTODIAN_GUARD_A", "U_BOYZ_B", "U_WARBOSS_A"])
	_place("U_CUSTODIAN_GUARD_A", 8.0, 14.0)
	_place("U_BOYZ_B", 6.0, 44.0, 1.4)             # ~28.7" from CG_A — beyond 24"
	_place("U_WARBOSS_A", 10.0, 30.0)              # ~14.7" from CG_A (kustom shoota 18")
	var ids := _snap_ids("U_BOYZ_B")
	_check("measured from the WHOLE Attached unit: the Warboss's model puts CG_A within 24\"", "U_CUSTODIAN_GUARD_A" in ids, str(ids))
	var asg: Array = RE.build_snap_assignments_11e("U_BOYZ_B", "U_CUSTODIAN_GUARD_A", GS.create_snapshot())
	var bearers: Array = []
	for a in asg:
		bearers.append_array(a.model_ids)
		_check("assignment %s is flagged overwatch + shooting_type snap" % a.weapon_id, a.get("overwatch", false) and str(a.get("shooting_type", "")) == "snap")
	_check("the Warboss's guns are among the bearers (composite U_WARBOSS_A:<model>)",
		bearers.any(func(b): return str(b).begins_with("U_WARBOSS_A:")), str(bearers))
	_place("U_WARBOSS_A", 30.0, 44.0)               # now beyond 24" too
	_check("…and with the Warboss also beyond 24\" there is no snap target", not ("U_CUSTODIAN_GUARD_A" in _snap_ids("U_BOYZ_B")), str(_snap_ids("U_BOYZ_B")))

# ── (d) unmodified 6s only, even with a lowered crit threshold; no re-rolls ─

func _test_unmodified_sixes_and_no_rerolls() -> void:
	print("\n-- (d) 15.09: hits only on an unmodified 6 (crit-threshold clamp), no hit re-rolls --")
	_check("_snap_critical_hit_threshold_11e(5) == 6 at 11e", RE._snap_critical_hit_threshold_11e(5) == 6)
	_check("_snap_critical_hit_threshold_11e(6) == 6", RE._snap_critical_hit_threshold_11e(6) == 6)
	_load(["U_CUSTODIAN_GUARD_A", "U_GRETCHIN_C"])
	_place("U_CUSTODIAN_GUARD_A", 8.0, 30.0)
	_place("U_GRETCHIN_C", 6.0, 36.0, 1.4)          # within 9" -> BLITZA FIRE crits on 5+
	var gf: Dictionary = GS.state.units["U_GRETCHIN_C"].flags
	gf["effect_blitza_fire"] = true                  # ranged crits on 5+ vs targets within 9"
	gf[EffectPrimitivesData.FLAG_REROLL_HITS] = "all"  # re-roll all hit rolls
	var board = GS.create_snapshot()
	var asg: Array = RE.build_snap_assignments_11e("U_GRETCHIN_C", "U_CUSTODIAN_GUARD_A", board)
	_check("snap assignments built for the Gretchin", not asg.is_empty(), str(asg))
	var sixes := 0
	var fives := 0
	var hits := 0
	var rerolls := 0
	var crit_seen := []
	for seed in [11, 12, 13, 14, 15, 16]:
		var res: Dictionary = RE.resolve_shoot({"type": "SHOOT", "actor_unit_id": "U_GRETCHIN_C",
			"payload": {"assignments": asg, "overwatch": true, "shooting_type": "snap"}}, GS.create_snapshot(), RE.RNGService.new(seed))
		for db in res.get("dice", []):
			if str(db.get("context", "")) != "to_hit":
				continue
			for r in db.get("rolls_raw", []):
				if int(r) == 6:
					sixes += 1
				elif int(r) == 5:
					fives += 1
			hits += int(db.get("successes", 0))
			rerolls += db.get("rerolls", []).size()
			crit_seen.append(int(db.get("critical_hit_threshold", 0)))
	_check("(the seeds rolled some 5s — BLITZA FIRE would have made them crits)", fives > 0, "fives=%d" % fives)
	_check("hits == unmodified 6s only (BLITZA FIRE's 5+ critical threshold clamped)", hits == sixes, "hits=%d sixes=%d fives=%d" % [hits, sixes, fives])
	_check("critical hit threshold reported as 6 on every snap hit roll", crit_seen.all(func(c): return c == 6), str(crit_seen))
	_check("no hit re-rolls despite 'reroll hits: all' on the unit", rerolls == 0, "rerolls=%d" % rerolls)
	# Sanity: the same flags DO re-roll / crit on 5s in a normal (non-snap) shot,
	# so the checks above prove the snap rules, not a dead flag.
	var normal_asg: Array = []
	for a in asg:
		var c: Dictionary = a.duplicate()
		c.erase("overwatch")
		c.erase("shooting_type")
		normal_asg.append(c)
	var n_rerolls := 0
	var n_crit := []
	for seed in [11, 12, 13]:
		var nres: Dictionary = RE.resolve_shoot({"type": "SHOOT", "actor_unit_id": "U_GRETCHIN_C",
			"payload": {"assignments": normal_asg}}, GS.create_snapshot(), RE.RNGService.new(seed))
		for db in nres.get("dice", []):
			if str(db.get("context", "")) == "to_hit":
				n_rerolls += db.get("rerolls", []).size()
				n_crit.append(int(db.get("critical_hit_threshold", 0)))
	_check("control: a normal shot with the same flags re-rolls hits", n_rerolls > 0, "n_rerolls=%d" % n_rerolls)
	_check("control: …and crits on 5+ (BLITZA FIRE active)", n_crit.all(func(c): return c == 5), str(n_crit))

# ── (e) USE: CP, shots, phase advance, AFTER SHOOTING lifted at phase end ─

func _test_use_spends_cp_and_resolves() -> void:
	print("\n-- (e) USE: 1 CP, snap shots resolved, the Movement phase then ends --")
	_std_board()
	var phase = _movement()
	var win: Dictionary = _end_movement(phase).window
	_check("window pending for P2", int(win.get("player", 0)) == 2)
	var res := _use_fo(phase, "U_GRETCHIN_C", "U_CUSTODIAN_GUARD_A")
	_check("USE_WINDOW_STRATAGEM (FIRE OVERWATCH, Gretchin C -> Custodian Guard A) succeeds", res.get("success", false), str(res.get("error", "")))
	_check("P2 spent exactly 1 CP (6 -> 5)", int(GS.state.players["2"]["cp"]) == 5, str(GS.state.players["2"]["cp"]))
	_check("P1's CP untouched", int(GS.state.players["1"]["cp"]) == 6)
	_check("result says Fire Overwatch was used by Gretchin C at CG A",
		res.get("fire_overwatch_used", false) and str(res.get("fire_overwatch_unit_id", "")) == "U_GRETCHIN_C"
		and str(res.get("fire_overwatch_target_id", "")) == "U_CUSTODIAN_GUARD_A", str(res.keys()))
	var hit_blocks: Array = res.get("dice", []).filter(func(d): return str(d.get("context", "")) == "to_hit")
	_check("the snap hit rolls ride the result (dice for the log / network)", not hit_blocks.is_empty(), str(res.get("dice", []).map(func(d): return d.get("context", ""))))
	_check("a player-facing summary line is in the result", "snap-shot" in str(res.get("fire_overwatch_summary", "")), str(res.get("fire_overwatch_summary", "")))
	_check("Game Log carries the >>> FIRE OVERWATCH <<< lines", _log_has(">>> FIRE OVERWATCH <<<") and _log_has("only unmodified 6s hit"))
	var used: Array = SM._usage_history.get("2", []).filter(func(u): return str(u.stratagem_id) == FO)
	_check("usage recorded once for P2 (target = the shooter)", used.size() == 1 and str(used[0].target_unit_id) == "U_GRETCHIN_C", str(used))
	_check("the window answer completed the phase: now SHOOTING", GS.get_current_phase() == GameStateData.Phase.SHOOTING, str(GS.get_current_phase()))
	var changes: Array = res.get("changes", [])
	var lock_on := changes.any(func(d): return str(d.get("path", "")) == "units.U_GRETCHIN_C.flags.cannot_start_action" and d.get("value") == true)
	var lock_off := changes.any(func(d): return str(d.get("path", "")) == "units.U_GRETCHIN_C.flags.cannot_start_action" and d.get("value") == false)
	_check("15.09 AFTER SHOOTING: cannot_start_action set for the shooter, and lifted at the end of the phase",
		lock_on and lock_off and not GS.state.units["U_GRETCHIN_C"].get("flags", {}).get("cannot_start_action", false), str(changes.filter(func(d): return "cannot_start_action" in str(d.get("path", "")))))
	_check("out-of-phase restriction released after the shot", not SM.is_out_of_phase_active())

# ── (f) server-side re-validation of shooter + target ─────────────────

func _test_server_side_validation() -> void:
	print("\n-- (f) the chosen shooter / snap target are validated by the phase, not trusted --")
	_std_board()
	_place("U_CUSTODIAN_GUARD_B", 32.0, 24.0)       # in the Warboss's 18" (Boyz row), not the Gretchin's 12"
	var phase = _movement()
	var win: Dictionary = _end_movement(phase).window
	var g := _row(_fo_offer(win), "U_GRETCHIN_C")
	_check("(setup) CG_B is not one of the Gretchin's options", not ("U_CUSTODIAN_GUARD_B" in _option_ids(g)), str(_option_ids(g)))
	var r := _use_fo(phase, "U_GRETCHIN_C", "U_CUSTODIAN_GUARD_B")
	_check("a snap target outside the offered options is refused", not r.get("success", true), str(r))
	_check("…nothing spent, window still pending", int(GS.state.players["2"]["cp"]) == 6 and phase.has_pending_stratagem_window())
	r = _use_fo(phase, "U_WARBOSS_A", "U_CUSTODIAN_GUARD_A")
	_check("a shooter that is not an offered row (attached Warboss) is refused", not r.get("success", true), str(r))
	r = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 2, "window_id": W_END,
		"stratagem_id": FO, "target_unit_id": "U_GRETCHIN_C", "context": {}})
	_check("USE without a snap target is refused", not r.get("success", true), str(r))
	r = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": W_END,
		"stratagem_id": FO, "target_unit_id": "U_GRETCHIN_C", "context": {"secondary_id": "U_CUSTODIAN_GUARD_A"}})
	_check("the ACTIVE player cannot answer P2's window", not r.get("success", true), str(r))
	var v: Dictionary = SM.can_use_stratagem(2, FO, "U_GRETCHIN_C", {"window_id": W_END, "secondary_id": "U_CUSTODIAN_GUARD_B"})
	_check("can_use_stratagem re-checks the snap target (15.09) before any CP is spent", not v.can_use and "snap-shooting target" in str(v.reason), str(v))
	_check("…and accepts a legal one", SM.can_use_stratagem(2, FO, "U_GRETCHIN_C", {"window_id": W_END, "secondary_id": "U_CUSTODIAN_GUARD_A"}).can_use)
	r = _use_fo(phase, "U_GRETCHIN_C", "U_CUSTODIAN_GUARD_A")
	_check("the legal choice then succeeds", r.get("success", false), str(r.get("error", "")))

# ── (g) once per phase/turn (15.01) + decline ─────────────────────────

func _test_once_per_turn_and_decline() -> void:
	print("\n-- (g) 15.01 once per phase; decline path --")
	_std_board()
	var phase = _movement()
	_end_movement(phase)
	_use_fo(phase, "U_GRETCHIN_C", "U_CUSTODIAN_GUARD_A")
	# Same player-turn, back in the Movement phase: the stratagem is spent.
	GS.state.meta["phase"] = GameStateData.Phase.MOVEMENT
	var v: Dictionary = SM.can_use_stratagem(2, FO, "U_BOYZ_B", {"window_id": W_END})
	_check("a second FIRE OVERWATCH in the same phase/turn is refused", not v.can_use and "once per" in str(v.reason), str(v))
	var again: Array = SM.get_window_offers(2, W_END, {"phase": "movement"})
	_check("…and is not offered again", again.filter(func(o): return o.stratagem_id == FO).is_empty())
	# Decline: phase ends, no CP spent.
	_std_board()
	phase = _movement()
	_end_movement(phase)
	var d: Dictionary = phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 2, "window_id": W_END})
	_check("DECLINE_WINDOW_STRATAGEM succeeds", d.get("success", false), str(d.get("error", "")))
	_check("…the Movement phase ends (SHOOTING)", GS.get_current_phase() == GameStateData.Phase.SHOOTING)
	_check("…no CP spent", int(GS.state.players["2"]["cp"]) == 6)
	_check("…no usage recorded", SM._usage_history.get("2", []).filter(func(u): return str(u.stratagem_id) == FO).is_empty())
	# Not enough CP: no offer at all.
	_std_board()
	GS.state.players["2"]["cp"] = 0
	phase = _movement()
	var em := _end_movement(phase)
	_check("0 CP: no FIRE OVERWATCH offer (the phase ends straight away)",
		_fo_offer(em.window).is_empty() and GS.get_current_phase() == GameStateData.Phase.SHOOTING, str(GS.get_current_phase()))

# ── (h) RAPID INGRESS 15.07 at the same point ─────────────────────────

func _ri_board(round_no: int) -> void:
	_std_board(["U_STORMBOYZ_A", "U_DAKKAJET_A"])
	for uid in ["U_STORMBOYZ_A", "U_DAKKAJET_A"]:
		var u: Dictionary = GS.state.units[uid]
		u["status"] = GameStateData.UnitStatus.IN_RESERVES
		u["reserve_type"] = "strategic_reserves"
		for m in u.models:
			m["position"] = null
	GS.state.meta["battle_round"] = round_no

func _test_rapid_ingress_window() -> void:
	print("\n-- (h) RAPID INGRESS 15.07: end of the opponent's Movement phase, non-active player, not round 1, not AIRCRAFT --")
	var ri: Dictionary = SM.stratagems.get("rapid_ingress_11e", {})
	_check("rapid_ingress_11e timing is the opponent's Movement phase, end of phase",
		str(ri.get("timing", {}).get("phase", "")) == "movement" and str(ri.get("timing", {}).get("turn", "")) == "opponent"
		and str(ri.get("timing", {}).get("trigger", "")) == "end_of_phase", str(ri.get("timing", {})))
	_ri_board(2)
	var phase = _movement()
	var end_res: Dictionary = phase.execute_action({"type": "END_MOVEMENT", "player": 1})
	_check("END_MOVEMENT offers RAPID INGRESS to P2", end_res.get("trigger_rapid_ingress", false) and int(end_res.get("rapid_ingress_player", 0)) == 2, str(end_res.keys()))
	var elig: Array = end_res.get("rapid_ingress_eligible_units", []).map(func(e): return str(e.unit_id))
	_check("the Stormboyz (strategic reserves) are eligible", "U_STORMBOYZ_A" in elig, str(elig))
	_check("15.07: the AIRCRAFT Dakkajet is not", not ("U_DAKKAJET_A" in elig), str(elig))
	_check("RAPID INGRESS comes BEFORE the movement_phase_end window (no window pending yet)", not phase.has_pending_stratagem_window())
	_check("the phase holds for the prompt (has_pending_end_of_phase_prompt)", phase.has_pending_end_of_phase_prompt())
	_check("network: P2 may answer it during P1's turn (allows_cross_turn_action)",
		phase.allows_cross_turn_action({"type": "USE_RAPID_INGRESS", "player": 2, "unit_id": "U_STORMBOYZ_A"})
		and not phase.allows_cross_turn_action({"type": "USE_RAPID_INGRESS", "player": 1, "unit_id": "U_STORMBOYZ_A"}))
	var bad: Dictionary = phase.execute_action({"type": "USE_RAPID_INGRESS", "player": 2, "unit_id": "U_DAKKAJET_A"})
	_check("USE_RAPID_INGRESS on the AIRCRAFT is refused", not bad.get("success", true), str(bad))
	var dec: Dictionary = phase.execute_action({"type": "DECLINE_RAPID_INGRESS", "player": 2})
	_check("DECLINE_RAPID_INGRESS succeeds", dec.get("success", false), str(dec.get("error", "")))
	_skip_p1_windows(phase)
	var w: Dictionary = phase.get_pending_stratagem_window() if phase.has_pending_stratagem_window() else {}
	_check("…then P2's movement_phase_end window opens with FIRE OVERWATCH", int(w.get("player", 0)) == 2 and not _fo_offer(w).is_empty(), str(w.keys()))
	phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 2, "window_id": W_END})
	_check("…and declining it ends the phase", GS.get_current_phase() == GameStateData.Phase.SHOOTING)
	# USE path: CP and the 11e ingress set-up.
	_ri_board(2)
	phase = _movement()
	phase.execute_action({"type": "END_MOVEMENT", "player": 1})
	var use: Dictionary = phase.execute_action({"type": "USE_RAPID_INGRESS", "player": 2, "unit_id": "U_STORMBOYZ_A"})
	_check("USE_RAPID_INGRESS (Stormboyz) succeeds and costs 1 CP", use.get("success", false) and int(GS.state.players["2"]["cp"]) == 5, str(use.get("error", "")) + " cp=" + str(GS.state.players["2"]["cp"]))
	_check("…the phase still holds for the placement", phase.has_pending_end_of_phase_prompt() and GS.get_current_phase() == GameStateData.Phase.MOVEMENT)
	# Host END_MOVEMENT (GameManager._end_phase_via_phase) must not force the
	# phase past the prompt (it used to "complete the phase as before").
	_ri_board(2)
	phase = _movement()
	var gm = root.get_node("GameManager")
	var gm_res: Dictionary = gm._end_phase_via_phase({"type": "END_MOVEMENT", "player": 1}, GameStateData.Phase.MOVEMENT)
	_check("GameManager END_MOVEMENT with the RAPID INGRESS prompt pending: phase NOT force-completed",
		gm_res.get("trigger_rapid_ingress", false) and GS.get_current_phase() == GameStateData.Phase.MOVEMENT
		and PM.get_current_phase_instance() == phase, str(gm_res.keys()) + " phase=" + str(GS.get_current_phase()))
	_check("…and no meta.phase advance rides its result", not gm_res.get("changes", []).any(func(d): return str(d.get("path", "")) == "meta.phase"))
	phase.execute_action({"type": "DECLINE_RAPID_INGRESS", "player": 2})
	_skip_p1_windows(phase)
	w = phase.get_pending_stratagem_window() if phase.has_pending_stratagem_window() else {}
	_check("…after the decline the FIRE OVERWATCH window opens there too", not _fo_offer(w).is_empty())
	phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 2, "window_id": W_END})
	# Battle round 1: no Rapid Ingress.
	_ri_board(1)
	phase = _movement()
	var r1: Dictionary = phase.execute_action({"type": "END_MOVEMENT", "player": 1})
	_check("battle round 1: no RAPID INGRESS offer (15.07 RESTRICTIONS)", not r1.get("trigger_rapid_ingress", false))
	_check("…can_use_stratagem says so", "battle round 1" in str(SM.can_use_stratagem(2, "rapid_ingress").reason), str(SM.can_use_stratagem(2, "rapid_ingress")))
	_skip_p1_windows(phase)
	if phase.has_pending_stratagem_window():
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 2, "window_id": W_END})

# ── (i) 14.02: objective control re-determined after the end-of-phase shots ─

func _test_objective_recheck_after_kills() -> void:
	print("\n-- (i) 14.02: objective control re-evaluated after FIRE OVERWATCH casualties --")
	var obj_pos := Vector2(20.0 * PX, 24.0 * PX)
	var killed := false
	var before := -1
	var after := -1
	var seed_used := -1
	for seed in range(1, 40):
		_load(["U_BLADE_CHAMPION_A", "U_BOYZ_B", "U_WARBOSS_A"])
		var bc: Dictionary = GS.state.units["U_BLADE_CHAMPION_A"]
		bc.meta.stats["toughness"] = 1
		bc.meta.stats["save"] = 7
		bc.meta.stats["invuln"] = 0
		bc.meta.stats["objective_control"] = 1
		for m in bc.models:
			m["current_wounds"] = 1
			m["wounds"] = 1
			m["invuln"] = 0
		_place("U_BLADE_CHAMPION_A", 20.0, 24.0)
		_place("U_BOYZ_B", 6.0, 34.0, 1.4)
		_place("U_WARBOSS_A", 22.0, 34.0)
		GS.state.board["objectives"] = [{"id": "OBJ_FO", "position": obj_pos}]
		RE.set_test_seed(seed)
		var phase = _movement()
		_end_movement(phase)
		before = int(MM.objective_control_state.get("OBJ_FO", -1))
		_use_fo(phase, "U_BOYZ_B", "U_BLADE_CHAMPION_A")
		killed = not GS.state.units["U_BLADE_CHAMPION_A"].models[0].get("alive", true)
		after = int(MM.objective_control_state.get("OBJ_FO", -1))
		if killed:
			seed_used = seed
			break
	RE.set_test_seed(-1)
	_check("(a seed where the snap shots kill the Blade Champion: %d)" % seed_used, killed)
	_check("at the phase-end check before the window, P1 controlled the objective", before == 1, "before=%d" % before)
	_check("after the casualty the objective is re-determined (no longer P1's)", after == 0, "after=%d" % after)
	_check("…and the phase moved on", GS.get_current_phase() == GameStateData.Phase.SHOOTING)

# ── (j) AI defender ───────────────────────────────────────────────────

func _test_ai_defender() -> void:
	print("\n-- (j) AI defender: scores expected damage on 6s vs CP --")
	# Hard target (Custodian Guard, T6 2+): not worth the CP.
	_std_board()
	AI.enabled = true
	AI.ai_players = {1: false, 2: true}
	var phase = _movement()
	phase.execute_action({"type": "END_MOVEMENT", "player": 1})
	_check("AI P2 declined a near-useless snap shot at 2+ Custodians (phase ended, CP kept)",
		GS.get_current_phase() == GameStateData.Phase.SHOOTING and int(GS.state.players["2"]["cp"]) == 6,
		"phase=%s cp=%s" % [str(GS.get_current_phase()), str(GS.state.players["2"]["cp"])])
	# Soft target (T3, no save) with the whole mob in slugga range: worth it.
	_std_board()
	_place("U_GRETCHIN_C", 30.0, 50.0, 1.4)
	_place("U_BOYZ_B", 6.0, 26.0, 1.4)
	_place("U_WARBOSS_A", 22.0, 26.0)
	var cg: Dictionary = GS.state.units["U_CUSTODIAN_GUARD_A"]
	cg.meta.stats["toughness"] = 3
	cg.meta.stats["save"] = 7
	cg.meta.stats["invuln"] = 0
	for m in cg.models:
		m["invuln"] = 0
	AI.enabled = true
	AI.ai_players = {1: false, 2: true}
	var log_before: int = AI.get_action_log().size()
	phase = _movement()
	var end_res: Dictionary = phase.execute_action({"type": "END_MOVEMENT", "player": 1})
	_check("AI P2 used FIRE OVERWATCH synchronously in the window (1 CP)", int(GS.state.players["2"]["cp"]) == 5, str(GS.state.players["2"]["cp"]))
	_check("…the phase still ended (no stall on the AI)", GS.get_current_phase() == GameStateData.Phase.SHOOTING)
	_check("…the END_MOVEMENT result carries the CP diff (replay / network)",
		end_res.get("changes", []).any(func(d): return str(d.get("path", "")) == "players.2.cp"))
	var new_entries: Array = AI.get_action_log().slice(log_before)
	_check("AI turn summary / action log counts it as USE_WINDOW_STRATAGEM",
		new_entries.any(func(e): return str(e.get("action_type", "")) == "USE_WINDOW_STRATAGEM"), str(new_entries))
	_check("…and categorises it as a stratagem", AI._categorize_action("USE_WINDOW_STRATAGEM") == "stratagems_used")
	# Low CP: the AI keeps its last CP.
	var offer := {"stratagem_id": FO, "name": "FIRE OVERWATCH", "cp_cost": 1,
		"targets": [{"unit_id": "U_GRETCHIN_C", "secondary": {"kind": "unit", "options": [{"id": "U_CUSTODIAN_GUARD_A"}]}}]}
	var dec: Dictionary = AIDecisionMaker._decide_fire_overwatch_window_11e(offer, 1, 2)
	_check("with 1 CP the AI does not fire overwatch", not dec.use, str(dec))
	AI.enabled = false
	AI.ai_players = {1: false, 2: false}

# ── (l) 05.03: the human defender allocates the snap shot's wounds ────

## Answer every pending snap-shot save batch the way AllocationGroupOverlay
## does (default legal order, the engine's batch resolution). Returns the
## final APPLY_SAVES result.
func _apply_all_snap_saves(phase: Node, defender: int) -> Dictionary:
	var last: Dictionary = {}
	var guard := 0
	while not phase._snap_saves.is_empty() and guard < 12:
		guard += 1
		var batch: Dictionary = phase.pending_save_data[0]
		var tgt := str(batch.get("target_unit_id", ""))
		var groups: Array = Allocation.build_groups(RE._build_attached_allocation_unit_11e(tgt, GS.state).unit)
		var summary: Dictionary = RE.resolve_allocation_batch_11e(batch, Allocation.default_order(groups), GS.state, RE.RNGService.new(100 + guard), {})
		last = phase.execute_action({"type": "APPLY_SAVES", "player": defender, "payload": {"save_results_list": [summary]}})
		if not last.get("success", false):
			break
	return last

func _soft_target() -> void:
	var cg: Dictionary = GS.state.units["U_CUSTODIAN_GUARD_A"]
	cg.meta.stats["toughness"] = 1
	cg.meta.stats["save"] = 7
	cg.meta.stats["invuln"] = 0
	for m in cg.models:
		m["invuln"] = 0
	_place("U_GRETCHIN_C", 30.0, 50.0, 1.4)
	_place("U_BOYZ_B", 6.0, 26.0, 1.4)
	_place("U_WARBOSS_A", 22.0, 26.0)

func _test_defender_allocates_saves() -> void:
	print("\n-- (l) 05.03: a human defender allocates the snap shot's wounds (APPLY_SAVES) --")
	var phase: Node = null
	var res: Dictionary = {}
	var seed_used := -1
	for seed in range(1, 30):
		_std_board()
		_soft_target()
		root.get_node("SettingsService").auto_allocate_wounds = false
		RE.set_test_seed(seed)
		phase = _movement()
		_end_movement(phase)
		res = _use_fo(phase, "U_BOYZ_B", "U_CUSTODIAN_GUARD_A")
		if not phase._snap_saves.is_empty():
			seed_used = seed
			break
	_check("(a seed whose snap shot wounds the target: %d)" % seed_used, seed_used > 0)
	_check("USE succeeds and the snap shot waits for the DEFENDER's allocation", res.get("success", false) and not phase._snap_saves.is_empty(), str(res.get("error", "")))
	_check("…the result hands P1 its save batch (network mirror re-emits it)",
		not res.get("save_data_list", []).is_empty() and res.get("fire_overwatch_awaiting_saves", false)
		and str(res.get("save_data_list", [{}])[0].get("target_unit_id", "")) == "U_CUSTODIAN_GUARD_A")
	_check("…the phase holds (MOVEMENT) and the decider is now P1, the defender",
		GS.get_current_phase() == GameStateData.Phase.MOVEMENT and phase.get_pending_stratagem_window_decider() == 1)
	_check("…P2's 1 CP is already spent", int(GS.state.players["2"]["cp"]) == 5)
	var blocked: Dictionary = phase.execute_action({"type": "END_MOVEMENT", "player": 1})
	_check("other actions are refused while P1 allocates", not blocked.get("success", true) and "allocate the FIRE OVERWATCH wounds" in str(blocked.get("error", "")), str(blocked))
	var batch: Dictionary = phase.pending_save_data[0]
	var groups: Array = Allocation.build_groups(RE._build_attached_allocation_unit_11e("U_CUSTODIAN_GUARD_A", GS.state).unit)
	var wrong: Dictionary = phase.execute_action({"type": "APPLY_SAVES", "player": 2, "payload": {"save_results_list": [
		RE.resolve_allocation_batch_11e(batch, Allocation.default_order(groups), GS.state, RE.RNGService.new(5), {})]}})
	_check("APPLY_SAVES from the attacker (P2) is refused", not wrong.get("success", true), str(wrong))
	var alive_before := 0
	for m in GS.state.units["U_CUSTODIAN_GUARD_A"].models:
		if m.get("alive", true):
			alive_before += 1
	var fin := _apply_all_snap_saves(phase, 1)
	_check("the defender's APPLY_SAVES finish the snap shot", fin.get("success", false) and phase._snap_saves.is_empty(), str(fin.get("error", "")))
	_check("…and the Movement phase then ends (SHOOTING)", GS.get_current_phase() == GameStateData.Phase.SHOOTING, str(GS.get_current_phase()))
	var alive_after := 0
	for m in GS.state.units["U_CUSTODIAN_GUARD_A"].models:
		if m.get("alive", true):
			alive_after += 1
	_check("the allocation's damage landed on the target (T1, no save: %d -> %d models)" % [alive_before, alive_after], alive_after < alive_before or
		GS.state.units["U_CUSTODIAN_GUARD_A"].models.any(func(m): return int(m.get("current_wounds", 3)) < 3))
	_check("…the final result carries the snap-shot summary", "snap-shot" in str(fin.get("fire_overwatch_summary", "")), str(fin.keys()))
	# AI attacker, human defender: the AI's synchronous window answer pauses
	# END_MOVEMENT for P1's allocation instead of resolving it for them.
	seed_used = -1
	var end_res: Dictionary = {}
	for seed in range(1, 30):
		_std_board()
		_soft_target()
		root.get_node("SettingsService").auto_allocate_wounds = false
		AI.enabled = true
		AI.ai_players = {1: false, 2: true}
		RE.set_test_seed(seed)
		phase = _movement()
		end_res = phase.execute_action({"type": "END_MOVEMENT", "player": 1})
		if not phase._snap_saves.is_empty():
			seed_used = seed
			break
	_check("AI P2 fires overwatch and END_MOVEMENT pauses for the HUMAN defender's saves (seed %d)" % seed_used,
		seed_used > 0 and GS.get_current_phase() == GameStateData.Phase.MOVEMENT and not end_res.get("save_data_list", []).is_empty())
	fin = _apply_all_snap_saves(phase, 1)
	_check("…P1's APPLY_SAVES finish it and the phase ends", fin.get("success", false) and GS.get_current_phase() == GameStateData.Phase.SHOOTING, str(fin.get("error", "")))
	AI.enabled = false
	AI.ai_players = {1: false, 2: false}
	RE.set_test_seed(-1)
	root.get_node("SettingsService").auto_allocate_wounds = true

# ── (k) 10e unchanged ─────────────────────────────────────────────────

# ── (m) the result line counts the TARGET's casualties only ─────────────
# Found live (two-process run): a Flash Gitz Snazzgun – Kill Shot [HAZARDOUS]
# check killed the shooter's own Kaptin after the snap shot, and the toast
# read "1 model(s) destroyed" although the Custodians saved the wound.

func _test_summary_counts_target_casualties() -> void:
	print("\n-- (m) snap-shot summary: target casualties vs own [HAZARDOUS] losses --")
	_std_board()
	var phase = _movement()
	var res := {"dice": [{"context": "to_hit", "successes": 2}, {"context": "to_wound", "successes": 1}],
		"diffs": [{"op": "set", "path": "units.U_GRETCHIN_C.models.0.alive", "value": false},
			{"op": "set", "path": "units.U_CUSTODIAN_GUARD_A.models.1.current_wounds", "value": 1}]}
	var line: String = phase._snap_shooting_summary("FIRE OVERWATCH", "Gretchin", "Custodian Guard", res, "U_CUSTODIAN_GUARD_A", ["U_GRETCHIN_C"])
	_check("own [HAZARDOUS] loss is not counted as a target casualty", "0 model(s) destroyed" in line, line)
	_check("…it is reported separately", "Hazardous: 1" in line, line)
	res.diffs.append({"op": "set", "path": "units.U_CUSTODIAN_GUARD_A.models.1.alive", "value": false})
	line = phase._snap_shooting_summary("FIRE OVERWATCH", "Gretchin", "Custodian Guard", res, "U_CUSTODIAN_GUARD_A", ["U_GRETCHIN_C"])
	_check("a destroyed target model is counted", "2 hit(s), 1 wound(s), 1 model(s) destroyed" in line, line)
	# The Game Log lines: the save shows the roll NEEDED (11e "threshold",
	# after AP) — not the characteristic — and an own [HAZARDOUS] loss is not
	# announced as "N model(s) destroyed!".
	var gel = root.get_node("GameEventLog")
	var n0: int = gel.entries.size()
	var res2 := {"dice": [{"context": "to_hit", "rolls_raw": [6, 3], "threshold": "7+", "successes": 1},
			{"context": "to_wound", "rolls_raw": [5], "threshold": "4+", "successes": 1},
			{"context": "save", "sv": "2+", "threshold": "4+", "ap": -2, "rolls_raw": [3], "fails": 1, "failed": 1, "successes": 0}],
		"diffs": [{"op": "set", "path": "units.U_GRETCHIN_C.models.0.alive", "value": false}]}
	phase._log_overwatch_results_to_game_log(gel, res2, "Gretchin", "Custodian Guard", 2, ["U_GRETCHIN_C"])
	var text := ""
	for e in gel.entries.slice(n0):
		text += str(e.get("text", "")) + "\n"
	_check("Game Log save line shows the roll needed (4+ after AP -2)", "Save roll: [3] vs 4+ (failed!)" in text, text)
	_check("…and does not announce the shooter's own [HAZARDOUS] loss as destroyed", not ("destroyed!" in text) and "1 failed save" in text, text)

func _test_10e_unchanged() -> void:
	print("\n-- (k) edition 10: the per-move Balance Dataslate offer is unchanged --")
	_std_board()
	GameConstants.edition = 10
	_check("edition pinned to 10 for this section", GameConstants.edition == 10)
	SM._usage_history = {"1": [], "2": []}
	var phase = _movement()
	_check("10e: FIRE OVERWATCH available mid-phase (no window)", SM.is_fire_overwatch_available(2).available, str(SM.is_fire_overwatch_available(2)))
	var r: Dictionary = phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_A", "player": 1})
	_check("10e: BEGIN_NORMAL_MOVE still offers the per-move Fire Overwatch to P2",
		r.get("trigger_fire_overwatch", false) and int(r.get("fire_overwatch_player", 0)) == 2, str(r.keys()))
	var d: Dictionary = phase.execute_action({"type": "DECLINE_FIRE_OVERWATCH", "player": 2})
	_check("10e: DECLINE_FIRE_OVERWATCH still works", d.get("success", false), str(d.get("error", "")))
	_check("10e: no FIRE OVERWATCH in the movement_phase_end window offers",
		SM.get_window_offers(2, W_END, {"phase": "movement"}).filter(func(o): return o.stratagem_id == FO).is_empty())
	_check("10e: snap crit clamp is a no-op (_snap_critical_hit_threshold_11e(5) == 5)", RE._snap_critical_hit_threshold_11e(5) == 5)
	_check("10e: rapid_ingress resolves to the 10e definition", SM._resolve_core_id("rapid_ingress") == "rapid_ingress")
	GameConstants.edition = 11
	_check("edition back to 11", GameConstants.edition == 11)
