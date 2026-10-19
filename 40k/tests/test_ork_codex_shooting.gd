extends SceneTree

# Codex: Orks (11e) — the SHOOTING group (own turn, "when a friendly … unit is
# selected to shoot"): CLOSE-RANGE DAKKA, VINDICTIVE ARTILLERISTS, DRIVE-BY
# BUSTIN', KUSTOM DAKKA, GLOWIN' DAKKA, NEVER ENOUGH DAKKA, LONG, UNCONTROLLED
# BURSTS, DAKKASTORM (design .llm/ork_codex_11e_design.md §3, §6;
# scripts/stratagems/ork_codex/OrkCodexShooting.gd).
#
# Against the real fixture tests/saves/ork11e_orks_active.w40ksave (P1 Orks
# active vs P2 Custodes; the P1 detachment is switched per stratagem):
#   A. registry: all eight implemented, offered only in unit_selected_to_shoot
#   B. offers + keyword gates per stratagem (positive / negative units), not
#      outside the window, not in another phase, not on the opponent's turn,
#      not to the other player, not without CP, target = the selected unit
#   C. ShootingPhase hook (SELECT_SHOOTER): pause, pending gate, USE -> CP -1,
#      flags on the Attached unit, selection resumes (targets offered);
#      decline + don't-offer-again; re-selection does not re-open
#   D. atomic SHOOT (AI / "Shoot All Remaining"): AI decider synchronous with
#      the CP diff in the SHOOT result; human decider pauses the SHOOT and the
#      answer resumes it to completion
#   E. effects, A/B with the same seeds through BOTH ranged resolvers
#      (interactive resolve_shoot_until_wounds / staged hits, auto resolve_shoot)
#   F. VINDICTIVE ARTILLERISTS variants (dialog has no plain Use button,
#      USE without a variant refused, granted [HAZARDOUS] really rolls)
#   G. expiry at the end of the phase (StratagemManager + the real phase exit)
#   H. AI scoring / decide_window_stratagem (variant pick, CP reserve)
#
# Usage: godot --headless --path 40k --script tests/test_ork_codex_shooting.gd

const FIXTURE := "ork11e_orks_active"
const WINDOW := "unit_selected_to_shoot"
# GameStateData.Phase values (ints — see test_ork_codex_framework.gd).
const PHASE_COMMAND := 6
const PHASE_SHOOTING := 8
const PHASE_CHARGE := 9
const PHASE_FIGHT := 10
const PX := 40.0

const CRD := "close-range-dakka-war-horde"
const VA := "vindictive-artillerists-madcap-meks"
const DBB := "drive-by-bustin-wreckas"
const KD := "kustom-dakka-shoota-boyz"
const GD := "glowin-dakka-shoota-boyz"
const NED := "never-enough-dakka-shoota-boyz"
const LUB := "long-uncontrolled-bursts-flyboyz"
const DS := "dakkastorm-kult-of-speed"

const DETACHMENT := {
	CRD: "War Horde", VA: "Madcap Meks", DBB: "Wreckas", KD: "Shoota Boyz",
	GD: "Shoota Boyz", NED: "Shoota Boyz", LUB: "Flyboyz", DS: "Kult of Speed",
}
const FLAG := {
	CRD: "ork11e_close_range_dakka", VA: "ork11e_vindictive_artillerists", DBB: "ork11e_drive_by_bustin",
	KD: "ork11e_kustom_dakka", GD: "ork11e_glowin_dakka", NED: "ork11e_never_enough_dakka",
	LUB: "ork11e_long_uncontrolled_bursts", DS: "ork11e_dakkastorm",
}
# csv id -> [eligible units], [ineligible P1 units]
const GATES := {
	CRD: [["U_TANKBUSTAS_A", "U_BATTLEWAGON_A", "U_GRETCHIN_C"], []],
	VA: [["U_MEK_GUNZ_A"], ["U_TANKBUSTAS_A", "U_KILLA_KANS_A"]],
	# The fixture Battlewagon has 'Ard Case (no Firing Deck): DRIVE-BY BUSTIN'
	# is not offered for it (r4:WS-4) — checked separately in _section_gates.
	DBB: [["U_TRUKK_A"], ["U_DEFF_DREAD_A", "U_RUKKATRUKK_SQUIGBUGGIES_A", "U_TANKBUSTAS_A"]],
	KD: [["U_TANKBUSTAS_A", "U_FLASH_GITZ_A", "U_STORMBOYZ_A"], ["U_DEFF_DREAD_A", "U_MEK_GUNZ_A", "U_WARBIKERS_A"]],
	GD: [["U_TANKBUSTAS_A", "U_KOMMANDOS_A"], ["U_KILLA_KANS_A", "U_DAKKAJET_A"]],
	NED: [["U_FLASH_GITZ_A", "U_GRETCHIN_D"], ["U_BATTLEWAGON_A", "U_DEFFKOPTAS_A"]],
	LUB: [["U_DAKKAJET_A", "U_DEFFKOPTAS_A"], ["U_STORMBOYZ_A", "U_WARBIKERS_A", "U_TRUKK_A"]],
	DS: [["U_WARBIKERS_A", "U_DEFFKOPTAS_A", "U_DAKKAJET_A", "U_TRUKK_A"], ["U_TANKBUSTAS_A", "U_BATTLEWAGON_A"]],  # Trukk: SPEED FREEKS per the codex (local-patches.mjs patch 4)
}

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var RE = null
var _window_events: Array = []
var _selected_events: Array = []


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


func _on_window_opened(player: int, window_id: String, offers: Array, ctx: Dictionary) -> void:
	_window_events.append({"player": player, "window_id": window_id, "offers": offers, "ctx": ctx})


func _on_unit_selected_for_shooting(unit_id: String) -> void:
	_selected_events.append(unit_id)


func _stage_fixture() -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + FIXTURE + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + FIXTURE + ext))
	return slm.load_game(FIXTURE)


func _cp(p: int) -> int:
	return int(GS.state.players[str(p)].cp)


## Switch P1's detachment and reload its faction stratagems; returns csv_id -> id.
func _use_detachment(det: String) -> Dictionary:
	GS.state.factions["1"]["detachment"] = det
	SM.load_faction_stratagems_for_player(1)
	var out := {}
	for s in SM.get_faction_stratagems_for_player(1):
		out[str(s.get("csv_id", ""))] = str(s.get("id", ""))
	return out


func _sid(csv_id: String) -> String:
	return str(_use_detachment(DETACHMENT[csv_id]).get(csv_id, ""))


func _reset_usage() -> void:
	# Expire whatever a previous section left active (clears its flags), then
	# forget the usage history so once-per-phase / 15.01 start fresh.
	SM._clear_expired_effects("end_of_phase")
	SM._usage_history = {"1": [], "2": []}
	SM.active_effects = []
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 6


func _fresh_shooting_phase():
	_reset_usage()
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_SHOOTING)
	var phase = PM.get_current_phase_instance()
	if phase and not phase.stratagem_window_opened.is_connected(_on_window_opened):
		phase.stratagem_window_opened.connect(_on_window_opened)
	if phase and not phase.unit_selected_for_shooting.is_connected(_on_unit_selected_for_shooting):
		phase.unit_selected_for_shooting.connect(_on_unit_selected_for_shooting)
	return phase


func _set_pos(m: Dictionary, x_in: float, y_in: float) -> void:
	var p = m.get("position", null)
	if p is Vector2:
		m["position"] = Vector2(x_in * PX, y_in * PX)
	else:
		m["position"] = {"x": x_in * PX, "y": y_in * PX}


## Place a unit's models in a row centred on x_in at y_in (inches).
func _place(units: Dictionary, uid: String, x_in: float, y_in: float, spacing: float = 2.0) -> void:
	var models: Array = units[uid].models
	var n := models.size()
	for i in range(n):
		_set_pos(models[i], x_in + (float(i) - float(n - 1) / 2.0) * spacing, y_in)


## Custodian Guard C 7" in front of the Ork rank R1 (Tankbustas x10) — inside
## 9" (GLOWIN' DAKKA) and inside half range of every 24" gun (CLOSE-RANGE DAKKA).
func _stage_target_near_r1() -> void:
	_place(GS.state.units, "U_CUSTODIAN_GUARD_C", 10.0, 24.5)


func _run() -> void:
	SM = root.get_node("StratagemManager")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	GameConstants.edition = 11

	print("\n=== test_ork_codex_shooting ===\n")
	_check("fixture %s loads" % FIXTURE, _stage_fixture())
	GameConstants.edition = 11
	_check("fixture: P1 is Orks", str(GS.state.factions["1"].get("name", "")) == "Orks", str(GS.state.factions["1"]))
	_stage_target_near_r1()

	_section_registry()
	_section_gates()
	await _section_hook()
	await _section_atomic_shoot()
	_section_effects()
	_section_vindictive()
	_section_expiry()
	_section_ai()


# ---------------------------------------------------------------------------
func _section_registry() -> void:
	print("\n-- A. registry --")
	var G = load("res://scripts/stratagems/ork_codex/OrkCodexShooting.gd")
	for csv in [CRD, VA, DBB, KD, GD, NED, LUB, DS]:
		_check("%s implemented + offensive" % csv, G.IMPLEMENTED.get(csv, false) and G.AI_KIND.get(csv, "") == "offensive")
		var sid := _sid(csv)
		var s = SM.get_stratagem(sid)
		_check("%s loads for its detachment (%s), marked implemented" % [csv, DETACHMENT[csv]], sid != "" and s.get("implemented", false), sid)
		_check("%s window = [unit_selected_to_shoot]" % csv, s.get("timing", {}).get("windows", []) == [WINDOW], str(s.get("timing", {})))


func _section_gates() -> void:
	print("\n-- B. offers + gates --")
	_reset_usage()
	PM.transition_to_phase(PHASE_SHOOTING)
	_check("in the Shooting phase, P1 active", GS.get_current_phase() == PHASE_SHOOTING and int(GS.state.meta.active_player) == 1)
	for csv in [CRD, VA, DBB, KD, GD, NED, LUB, DS]:
		var sid := _sid(csv)
		# DRIVE-BY BUSTIN' is only offered when a passenger can fire through
		# the Firing Deck (r4:WS-4) — give the eligible transports one.
		var dbb_saved := {}
		if csv == DBB:
			for tid in GATES[csv][0]:
				var td: Dictionary = GS.state.units[tid].get("transport_data", {})
				dbb_saved[tid] = td.get("embarked_units", []).duplicate()
				td["embarked_units"] = ["U_KOMMANDOS_A"]
		for uid in GATES[csv][0]:
			var offers = SM.get_window_offers(1, WINDOW, {"phase": "shooting", "unit_id": uid})
			var hit := false
			for o in offers:
				if str(o.stratagem_id) == sid and o.targets.size() == 1 and str(o.targets[0].unit_id) == uid:
					hit = true
			_check("%s offered when %s is selected" % [csv, uid], hit, str(offers.map(func(o): return o.name)))
		for tid in dbb_saved:
			GS.state.units[tid]["transport_data"]["embarked_units"] = dbb_saved[tid]
		if csv == DBB:
			# r4:WS-4: an 'Ard Case Battlewagon has no Firing Deck, so no weapon
			# can be selected for it — not offered even with a passenger.
			var bw_td: Dictionary = GS.state.units["U_BATTLEWAGON_A"].get("transport_data", {})
			var bw_saved: Array = bw_td.get("embarked_units", []).duplicate()
			bw_td["embarked_units"] = ["U_KOMMANDOS_A"]
			var bw_offers = SM.get_window_offers(1, WINDOW, {"phase": "shooting", "unit_id": "U_BATTLEWAGON_A"})
			var bw_hit := false
			for o in bw_offers:
				if str(o.stratagem_id) == sid:
					bw_hit = true
			_check("%s NOT offered for the 'Ard Case U_BATTLEWAGON_A (firing deck %d)" % [csv, int(bw_td.get("firing_deck", 0))],
				not bw_hit and int(bw_td.get("firing_deck", 0)) == 0, str(bw_offers.map(func(o): return o.name)))
			bw_td["embarked_units"] = bw_saved
		for uid in GATES[csv][1]:
			var offers2 = SM.get_window_offers(1, WINDOW, {"phase": "shooting", "unit_id": uid})
			var none := true
			for o in offers2:
				if str(o.stratagem_id) == sid:
					none = false
			var why = SM.can_use_stratagem(1, sid, uid, {"window_id": WINDOW, "unit_id": uid})
			_check("%s NOT offered for %s (%s)" % [csv, uid, str(why.reason)], none and not why.can_use)
		var pos: String = GATES[csv][0][0]
		var r = SM.can_use_stratagem(1, sid, pos)
		_check("%s outside a window -> 'Offered automatically when …'" % csv,
			not r.can_use and "Offered automatically when one of your units is selected to shoot" in str(r.reason), str(r))
		r = SM.can_use_stratagem(1, sid, pos, {"window_id": "unit_selected_to_fight", "unit_id": pos})
		_check("%s in another window refused" % csv, not r.can_use, str(r))
		r = SM.can_use_stratagem(1, sid, "U_CUSTODIAN_GUARD_C", {"window_id": WINDOW, "unit_id": "U_CUSTODIAN_GUARD_C"})
		_check("%s refuses an enemy unit" % csv, not r.can_use, str(r))
		var other: String = GATES[csv][0][1] if GATES[csv][0].size() > 1 else "U_KOMMANDOS_A"
		r = SM.can_use_stratagem(1, sid, other, {"window_id": WINDOW, "unit_id": pos})
		_check("%s must target the unit selected to shoot" % csv, not r.can_use, str(r))
		_check("%s: no offers for P2" % csv, SM.get_window_offers(2, WINDOW, {"phase": "shooting", "unit_id": pos}).is_empty())
		GS.state.players["1"]["cp"] = 0
		_check("%s: no offers with 0 CP" % csv, SM.get_window_offers(1, WINDOW, {"phase": "shooting", "unit_id": pos}).is_empty())
		GS.state.players["1"]["cp"] = 6
		GS.state.meta["active_player"] = 2
		r = SM.can_use_stratagem(1, sid, pos, {"window_id": WINDOW, "unit_id": pos})
		_check("%s refused on the opponent's turn" % csv, not r.can_use and "your turn" in str(r.reason), str(r))
		GS.state.meta["active_player"] = 1
	# Phase gate: the right window in the Fight phase is refused.
	var crd := _sid(CRD)
	PM.transition_to_phase(PHASE_FIGHT)
	var rf = SM.can_use_stratagem(1, crd, "U_TANKBUSTAS_A", {"window_id": WINDOW, "unit_id": "U_TANKBUSTAS_A"})
	_check("CLOSE-RANGE DAKKA refused outside the Shooting phase", not rf.can_use and "shooting phase" in str(rf.reason).to_lower(), str(rf))
	PM.transition_to_phase(PHASE_SHOOTING)
	GS.state.units.U_TANKBUSTAS_A.flags["battle_shocked"] = true
	var bs = SM.can_use_stratagem(1, crd, "U_TANKBUSTAS_A", {"window_id": WINDOW, "unit_id": "U_TANKBUSTAS_A"})
	_check("battle-shocked Tankbustas refused", not bs.can_use and "Battle-shocked" in str(bs.reason), str(bs))
	GS.state.units.U_TANKBUSTAS_A.flags.erase("battle_shocked")


# ---------------------------------------------------------------------------
func _section_hook() -> void:
	print("\n-- C. ShootingPhase hook (SELECT_SHOOTER) --")
	var crd := _sid(CRD)
	var phase = _fresh_shooting_phase()
	_check("ShootingPhase instance with the window framework", phase != null and phase.has_method("open_stratagem_window"))
	_window_events.clear()
	_selected_events.clear()
	var cp0 := _cp(1)
	var res = phase.execute_action({"type": "SELECT_SHOOTER", "actor_unit_id": "U_TANKBUSTAS_A", "player": 1})
	_check("SELECT_SHOOTER succeeds", res.get("success", false), str(res.get("error", "")))
	_check("window pending for P1 (the active player)", phase.has_pending_stratagem_window() and phase.get_pending_stratagem_window_decider() == 1)
	_check("result flags the pending window", res.get("stratagem_window_pending", false) and res.has("stratagem_window_opened"))
	_check("stratagem_window_opened emitted once with CLOSE-RANGE DAKKA",
		_window_events.size() == 1 and _window_events[0].window_id == WINDOW and _window_events[0].ctx.get("unit_id", "") == "U_TANKBUSTAS_A"
		and _window_events[0].offers.size() == 1 and str(_window_events[0].offers[0].stratagem_id) == crd, str(_window_events))
	_check("selection paused (no targets_available yet)", _selected_events.is_empty(), str(_selected_events))
	var blocked = phase.execute_action({"type": "ASSIGN_TARGET", "actor_unit_id": "U_TANKBUSTAS_A",
		"payload": {"weapon_id": "busta_rokkit_launcha_standard_ranged", "target_unit_id": "U_CUSTODIAN_GUARD_C"}})
	_check("other actions refused while the window waits", not blocked.get("success", true) and "Waiting for Player 1" in str(blocked.get("error", "")), str(blocked))
	var bad_player = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 2, "window_id": WINDOW, "stratagem_id": crd, "target_unit_id": "U_TANKBUSTAS_A"})
	_check("USE by the opponent refused", not bad_player.get("success", true))
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": WINDOW, "stratagem_id": crd, "target_unit_id": "U_TANKBUSTAS_A"})
	_check("USE_WINDOW_STRATAGEM succeeds", use.get("success", false), str(use.get("error", "")))
	_check("window closed", not phase.has_pending_stratagem_window())
	_check("CP %d -> %d" % [cp0, cp0 - 1], _cp(1) == cp0 - 1, str(_cp(1)))
	_check("flag set on Tankbustas", bool(GS.state.units.U_TANKBUSTAS_A.flags.get(FLAG[CRD], false)))
	# The selection continues where it was interrupted (targets). WP-O6: the
	# pre-codex Pulsa Rokkit prompt is gone — the codex Pulsa Rokkit is an
	# offer in this same unit_selected_to_shoot window.
	_check("selection resumed: active shooter + the rest of the selection ran (targets)",
		phase.active_shooter_id == "U_TANKBUSTAS_A" and _selected_events.has("U_TANKBUSTAS_A"),
		"%s" % str(_selected_events))
	var cp_diff := false
	for d in use.get("changes", []):
		if str(d.get("path", "")) == "players.1.cp":
			cp_diff = true
	_check("USE result carries the CP diff", cp_diff)
	_window_events.clear()
	var again = phase.execute_action({"type": "SELECT_SHOOTER", "actor_unit_id": "U_TANKBUSTAS_A", "player": 1})
	_check("re-selecting the same unit does not re-open the window", again.get("success", false) and not phase.has_pending_stratagem_window() and _window_events.is_empty())
	# Once per phase: another unit's selection has no CLOSE-RANGE DAKKA offer -> no window.
	var other = phase.execute_action({"type": "SELECT_SHOOTER", "actor_unit_id": "U_KOMMANDOS_A", "player": 1})
	_check("after the use, another selection opens no window (once per phase)", other.get("success", false) and not phase.has_pending_stratagem_window(), str(other.get("error", "")))

	# Attached unit: flags on every component (Boyz + Warboss) — via use_stratagem.
	_reset_usage()
	var r = SM.use_stratagem(1, crd, "U_BOYZ_B", {"window_id": WINDOW, "unit_id": "U_BOYZ_B", "phase": "shooting"})
	_check("CLOSE-RANGE DAKKA on Boyz succeeds", r.get("success", false), str(r.get("error", "")))
	_check("attached Warboss carries the flag too (19.03)", bool(GS.state.units.U_WARBOSS_A.flags.get(FLAG[CRD], false)))
	SM.on_phase_end(PHASE_SHOOTING)

	# Decline + don't offer again.
	phase = _fresh_shooting_phase()
	var cp1 := _cp(1)
	res = phase.execute_action({"type": "SELECT_SHOOTER", "actor_unit_id": "U_TANKBUSTAS_A", "player": 1})
	_check("fresh phase: window opens again", phase.has_pending_stratagem_window())
	var dec = phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 1, "window_id": WINDOW, "dont_offer_again": true})
	_check("DECLINE (don't offer again) succeeds and resumes the selection", dec.get("success", false) and phase.active_shooter_id == "U_TANKBUSTAS_A" and not phase.has_pending_stratagem_window(), str(dec.get("error", "")))
	_check("no CP spent, no flag", _cp(1) == cp1 and not GS.state.units.U_TANKBUSTAS_A.flags.has(FLAG[CRD]))
	res = phase.execute_action({"type": "SELECT_SHOOTER", "actor_unit_id": "U_KOMMANDOS_A", "player": 1})
	_check("suppressed for the rest of the phase", res.get("success", false) and not phase.has_pending_stratagem_window())


# ---------------------------------------------------------------------------
func _shoot_action(uid: String, wid: String, tid: String) -> Dictionary:
	return {"type": "SHOOT", "actor_unit_id": uid, "player": 1,
		"payload": {"assignments": [_assign(GS.state, uid, wid, tid)], "rng_seed": 7}}


func _first_ranged_weapon(uid: String) -> String:
	var w = RE.get_unit_weapons(uid, GS.state)
	for mid in w:
		for wid in w[mid]:
			return str(wid)
	return ""


func _section_atomic_shoot() -> void:
	print("\n-- D. atomic SHOOT (AI / Shoot All Remaining) --")
	var crd := _sid(CRD)
	var ai = root.get_node("AIPlayer")
	var phase = _fresh_shooting_phase()
	root.get_node("SettingsService").set("auto_allocate_wounds", true)
	var wid := _first_ranged_weapon("U_TANKBUSTAS_A")
	_check("Tankbustas have a ranged weapon (%s)" % wid, wid != "")
	# AI decider: synchronous, used, CP diff carried into the SHOOT result.
	ai.enabled = true
	ai.ai_players = {1: true, 2: true}
	var cp0 := _cp(1)
	var res = phase.execute_action(_shoot_action("U_TANKBUSTAS_A", wid, "U_CUSTODIAN_GUARD_C"))
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI SHOOT succeeds without pausing", res.get("success", false) and not phase.has_pending_stratagem_window(), str(res.get("error", "")))
	_check("AI used CLOSE-RANGE DAKKA (CP -1, flag)", _cp(1) == cp0 - 1 and bool(GS.state.units.U_TANKBUSTAS_A.flags.get(FLAG[CRD], false)), "%d -> %d" % [cp0, _cp(1)])
	var cp_diff := false
	for d in res.get("changes", []):
		if str(d.get("path", "")) == "players.1.cp":
			cp_diff = true
	_check("SHOOT result carries the AI's CP diff (replay / network)", cp_diff)
	_check("the shot resolved (unit has shot)", "U_TANKBUSTAS_A" in phase.units_that_shot, str(phase.units_that_shot))
	var rf_seen := false
	for blk in phase.dice_log:
		if typeof(blk) == TYPE_DICTIONARY and str(blk.get("context", "")) == "to_hit" and int(blk.get("rapid_fire_value", 0)) == 1:
			rf_seen = true
	_check("the SHOOT's hit roll used [RAPID FIRE 1] (0 -> 1)", rf_seen)

	# Human decider: the window pauses the SHOOT; the answer resumes it.
	phase = _fresh_shooting_phase()
	var wid2 := _first_ranged_weapon("U_KOMMANDOS_A")
	res = phase.execute_action(_shoot_action("U_KOMMANDOS_A", wid2, "U_CUSTODIAN_GUARD_C"))
	_check("human SHOOT pauses on the window", res.get("success", false) and phase.has_pending_stratagem_window() and res.get("stratagem_window_pending", false))
	_check("no shot yet", not ("U_KOMMANDOS_A" in phase.units_that_shot))
	var blocked = phase.execute_action(_shoot_action("U_TANKBUSTAS_A", wid, "U_CUSTODIAN_GUARD_C"))
	_check("a queued SHOOT is refused while the window waits", not blocked.get("success", true))
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": WINDOW, "stratagem_id": crd, "target_unit_id": "U_KOMMANDOS_A"})
	_check("USE resumes the SHOOT to completion", use.get("success", false) and "U_KOMMANDOS_A" in phase.units_that_shot, str(use.get("error", "")))
	_check("Kommandos carry the flag", bool(GS.state.units.U_KOMMANDOS_A.flags.get(FLAG[CRD], false)))
	SM.on_phase_end(PHASE_SHOOTING)


# ---------------------------------------------------------------------------
# E. effects — A/B with identical seeds on a copy of the live board.
func _board_with(flags_on: Dictionary, actor: String) -> Dictionary:
	var b: Dictionary = GS.state.duplicate(true)
	for k in flags_on:
		for uid in RE.attached_unit_component_ids(actor, b):
			b.units[uid].flags[k] = flags_on[k]
	return b


func _assign(board: Dictionary, uid: String, wid: String, tid: String, only_models: Array = []) -> Dictionary:
	var model_ids: Array = only_models.duplicate()
	if model_ids.is_empty():
		var w = RE.get_unit_weapons(uid, board)
		for mid in w:
			if wid in w[mid]:
				model_ids.append(str(mid))
	return {"weapon_id": wid, "target_unit_id": tid, "model_ids": model_ids}


func _auto(board: Dictionary, uid: String, assignment: Dictionary, seed_val: int) -> Dictionary:
	return RE.resolve_shoot({"type": "SHOOT", "actor_unit_id": uid, "payload": {"assignments": [assignment]}}, board, RE.RNGService.new(seed_val))


func _interactive(board: Dictionary, uid: String, assignment: Dictionary, seed_val: int) -> Dictionary:
	return RE.resolve_shoot_until_wounds({"type": "SHOOT", "actor_unit_id": uid, "payload": {"assignments": [assignment]}}, board, RE.RNGService.new(seed_val))


func _block(res: Dictionary, ctx_name: String) -> Dictionary:
	for d in res.get("dice", []):
		if str(d.get("context", "")) == ctx_name:
			return d
	return {}


func _sum(results: Array, ctx_name: String, key: String) -> int:
	var t := 0
	for r in results:
		var b = _block(r, ctx_name)
		t += int(b.get(key, 0))
	return t


func _weapon_of(uid: String, name_part: String) -> String:
	var w = RE.get_unit_weapons(uid, GS.state)
	for mid in w:
		for wid in w[mid]:
			if name_part in str(wid):
				return str(wid)
	return ""


func _section_effects() -> void:
	print("\n-- E. effects (A/B, same seeds, both resolvers) --")
	_stage_target_near_r1()
	var tgt := "U_CUSTODIAN_GUARD_C"

	# CLOSE-RANGE DAKKA — Busta rokkit launcha has no RAPID FIRE: 0 -> 1.
	var busta := _weapon_of("U_TANKBUSTAS_A", "standard")
	if busta == "":
		busta = _first_ranged_weapon("U_TANKBUSTAS_A")
	var off_b := _board_with({}, "U_TANKBUSTAS_A")
	var on_b := _board_with({FLAG[CRD]: true}, "U_TANKBUSTAS_A")
	var a_off = _interactive(off_b, "U_TANKBUSTAS_A", _assign(off_b, "U_TANKBUSTAS_A", busta, tgt), 11)
	var a_on = _interactive(on_b, "U_TANKBUSTAS_A", _assign(on_b, "U_TANKBUSTAS_A", busta, tgt), 11)
	var h_off = _block(a_off, "to_hit")
	var h_on = _block(a_on, "to_hit")
	var bearers: int = _assign(off_b, "U_TANKBUSTAS_A", busta, tgt).model_ids.size()
	_check("CRD interactive: %s RAPID FIRE 0 -> 1" % busta, int(h_off.get("rapid_fire_value", -1)) == 0 and int(h_on.get("rapid_fire_value", -1)) == 1, "%s / %s" % [h_off.get("rapid_fire_value"), h_on.get("rapid_fire_value")])
	_check("CRD interactive: +1 attack die per bearer in half range (%d bearers)" % bearers,
		h_on.get("rolls_raw", []).size() == h_off.get("rolls_raw", []).size() + bearers and int(h_on.get("rapid_fire_bonus", 0)) == bearers,
		"%d -> %d" % [h_off.get("rolls_raw", []).size(), h_on.get("rolls_raw", []).size()])
	var b_off = _block(_auto(off_b.duplicate(true), "U_TANKBUSTAS_A", _assign(off_b, "U_TANKBUSTAS_A", busta, tgt), 11), "to_hit")
	var b_on = _block(_auto(on_b.duplicate(true), "U_TANKBUSTAS_A", _assign(on_b, "U_TANKBUSTAS_A", busta, tgt), 11), "to_hit")
	_check("CRD auto: RAPID FIRE 0 -> 1 and +%d dice" % bearers, int(b_on.get("rapid_fire_value", -1)) == 1 and b_on.get("rolls_raw", []).size() == b_off.get("rolls_raw", []).size() + bearers)
	# Existing RAPID FIRE 2 (Battlewagon big shoota) -> 3.
	_place(GS.state.units, "U_CUSTODIAN_GUARD_D", 9.5, 15.0)
	var bw_w := _first_ranged_weapon("U_BATTLEWAGON_A")
	var bw_off := _board_with({}, "U_BATTLEWAGON_A")
	var bw_on := _board_with({FLAG[CRD]: true}, "U_BATTLEWAGON_A")
	var bw_h0 = _block(_interactive(bw_off, "U_BATTLEWAGON_A", _assign(bw_off, "U_BATTLEWAGON_A", bw_w, "U_CUSTODIAN_GUARD_D"), 5), "to_hit")
	var bw_h1 = _block(_interactive(bw_on, "U_BATTLEWAGON_A", _assign(bw_on, "U_BATTLEWAGON_A", bw_w, "U_CUSTODIAN_GUARD_D"), 5), "to_hit")
	_check("CRD: existing [RAPID FIRE 2] becomes [RAPID FIRE 3] (%s)" % bw_w, int(bw_h0.get("rapid_fire_value", 0)) == 2 and int(bw_h1.get("rapid_fire_value", 0)) == 3, "%s -> %s" % [bw_h0.get("rapid_fire_value"), bw_h1.get("rapid_fire_value")])
	_place(GS.state.units, "U_CUSTODIAN_GUARD_D", 22.0, 38.8)

	# SUSTAINED HITS 1 — NEVER ENOUGH DAKKA / DAKKASTORM / VINDICTIVE (sustained).
	for pair in [[NED, true], [DS, true], [VA, VA_VARIANT_SUSTAINED]]:
		var csv: String = pair[0]
		var val = pair[1]
		var on_sh := _board_with({FLAG[csv]: val}, "U_TANKBUSTAS_A")
		var ints_off: Array = []
		var ints_on: Array = []
		var autos_off: Array = []
		var autos_on: Array = []
		var never_less := true
		for s in range(25):
			var x0 = _interactive(off_b, "U_TANKBUSTAS_A", _assign(off_b, "U_TANKBUSTAS_A", busta, tgt), 300 + s)
			var x1 = _interactive(on_sh, "U_TANKBUSTAS_A", _assign(on_sh, "U_TANKBUSTAS_A", busta, tgt), 300 + s)
			ints_off.append(x0)
			ints_on.append(x1)
			if int(_block(x1, "to_hit").get("total_hits_for_wounds", 0)) < int(_block(x0, "to_hit").get("total_hits_for_wounds", 0)):
				never_less = false
			autos_off.append(_auto(off_b.duplicate(true), "U_TANKBUSTAS_A", _assign(off_b, "U_TANKBUSTAS_A", busta, tgt), 300 + s))
			autos_on.append(_auto(on_sh.duplicate(true), "U_TANKBUSTAS_A", _assign(on_sh, "U_TANKBUSTAS_A", busta, tgt), 300 + s))
		var crits := _sum(ints_on, "to_hit", "critical_hits")
		_check("%s interactive: [SUSTAINED HITS 1] on the hit block" % csv, int(_block(ints_on[0], "to_hit").get("sustained_hits_value", 0)) == 1 and int(_block(ints_off[0], "to_hit").get("sustained_hits_value", 0)) == 0)
		_check("%s interactive: bonus hits = critical hits (%d), never fewer hits" % [csv, crits],
			_sum(ints_on, "to_hit", "sustained_bonus_hits") == crits and crits > 0 and never_less)
		_check("%s auto: bonus hits = critical hits" % csv,
			_sum(autos_on, "to_hit", "sustained_bonus_hits") == _sum(autos_on, "to_hit", "critical_hits") and _sum(autos_on, "to_hit", "critical_hits") > 0 and _sum(autos_off, "to_hit", "sustained_bonus_hits") == 0)

	# A weapon with its own SUSTAINED HITS 1 (Killa Kans' Kan Blasta – Dakka) keeps 1, no stacking.
	var kan := _weapon_of("U_KILLA_KANS_A", "dakka")
	if kan != "":
		var kan_on := _board_with({FLAG[NED]: true}, "U_KILLA_KANS_A")
		var kh = _block(_interactive(kan_on, "U_KILLA_KANS_A", _assign(kan_on, "U_KILLA_KANS_A", kan, tgt), 9), "to_hit")
		_check("SH duplicates are not cumulative: %s stays [SUSTAINED HITS 1]" % kan, int(kh.get("sustained_hits_value", 0)) == 1, str(kh.get("sustained_hits_value")))

	# KUSTOM DAKKA — +1 to wound vs INFANTRY, nothing vs a VEHICLE/MONSTER target.
	# (Flash Gitz: Tankbustas' own Tank Hunters already give +1 vs MONSTER/VEHICLE.)
	var flash_w := _weapon_of("U_FLASH_GITZ_A", "kill_shot")
	if flash_w == "":
		flash_w = _first_ranged_weapon("U_FLASH_GITZ_A")
	var off_f := _board_with({}, "U_FLASH_GITZ_A")
	var kd_on := _board_with({FLAG[KD]: true}, "U_FLASH_GITZ_A")
	var kw = _block(_interactive(kd_on, "U_FLASH_GITZ_A", _assign(kd_on, "U_FLASH_GITZ_A", flash_w, tgt), 21), "to_wound")
	var kw0 = _block(_interactive(off_f, "U_FLASH_GITZ_A", _assign(off_f, "U_FLASH_GITZ_A", flash_w, tgt), 21), "to_wound")
	_check("KD interactive: +1 to wound vs INFANTRY", int(kw.get("wound_modifier_net", 0)) == 1 and int(kw0.get("wound_modifier_net", 0)) == 0, "%s / %s" % [kw0.get("wound_modifier_net"), kw.get("wound_modifier_net")])
	var kwa = _block(_auto(kd_on.duplicate(true), "U_FLASH_GITZ_A", _assign(kd_on, "U_FLASH_GITZ_A", flash_w, tgt), 21), "to_wound")
	_check("KD auto: +1 to wound vs INFANTRY", int(kwa.get("wound_modifier_net", 0)) == 1)
	for kwd in ["VEHICLE", "MONSTER"]:
		var kd_veh := kd_on.duplicate(true)
		kd_veh.units[tgt].meta.keywords.append(kwd)
		var kv = _block(_interactive(kd_veh, "U_FLASH_GITZ_A", _assign(kd_veh, "U_FLASH_GITZ_A", flash_w, tgt), 21), "to_wound")
		var kva = _block(_auto(kd_veh.duplicate(true), "U_FLASH_GITZ_A", _assign(kd_veh, "U_FLASH_GITZ_A", flash_w, tgt), 21), "to_wound")
		_check("KD: no bonus vs a %s target (both resolvers)" % kwd, int(kv.get("wound_modifier_net", 0)) == 0 and int(kva.get("wound_modifier_net", 0)) == 0)
	var kd_wounds := [0, 0]
	for s in range(25):
		kd_wounds[0] += int(_block(_interactive(off_f, "U_FLASH_GITZ_A", _assign(off_f, "U_FLASH_GITZ_A", flash_w, tgt), 500 + s), "to_wound").get("successes", 0))
		kd_wounds[1] += int(_block(_interactive(kd_on, "U_FLASH_GITZ_A", _assign(kd_on, "U_FLASH_GITZ_A", flash_w, tgt), 500 + s), "to_wound").get("successes", 0))
	_check("KD A/B: more wounds over 25 seeds (%d -> %d)" % kd_wounds, kd_wounds[1] > kd_wounds[0])

	# GLOWIN' DAKKA — +1 AP vs a target within 9"; nothing beyond 9".
	var gd_on := _board_with({FLAG[GD]: true}, "U_TANKBUSTAS_A")
	var ap0 := -999
	var ap1 := -999
	for s in range(30):
		var s0 = _interactive(off_b, "U_TANKBUSTAS_A", _assign(off_b, "U_TANKBUSTAS_A", busta, tgt), 700 + s)
		var s1 = _interactive(gd_on, "U_TANKBUSTAS_A", _assign(gd_on, "U_TANKBUSTAS_A", busta, tgt), 700 + s)
		if not s0.get("save_data_list", []).is_empty() and not s1.get("save_data_list", []).is_empty():
			ap0 = int(s0.save_data_list[0].ap)
			ap1 = int(s1.save_data_list[0].ap)
			break
	_check("GD interactive (save data): AP magnitude +1 within 9\" (%d -> %d)" % [ap0, ap1], ap0 != -999 and absi(ap1) == absi(ap0) + 1)
	var gs0 = _block(_auto(off_b.duplicate(true), "U_TANKBUSTAS_A", _assign(off_b, "U_TANKBUSTAS_A", busta, tgt), 701), "save")
	var gs1 = _block(_auto(gd_on.duplicate(true), "U_TANKBUSTAS_A", _assign(gd_on, "U_TANKBUSTAS_A", busta, tgt), 701), "save")
	_check("GD auto (save block): AP magnitude +1 within 9\"", not gs0.is_empty() and absi(int(gs1.get("ap", 0))) == absi(int(gs0.get("ap", 0))) + 1, "%s / %s" % [gs0.get("ap"), gs1.get("ap")])
	var far := gd_on.duplicate(true)
	_place(far.units, tgt, 10.0, 28.0)  # ~10.5" away: outside 9", still in range
	_check("GD helper: no bonus beyond 9\"", RE.ork11e_glowin_dakka_ap_bonus(far.units.U_TANKBUSTAS_A, far.units[tgt], far) == 0
		and RE.ork11e_glowin_dakka_ap_bonus(gd_on.units.U_TANKBUSTAS_A, gd_on.units[tgt], gd_on) == 1)
	_check("improve AP (02.02.06): -2 -> -3, 0 -> -1 (signed); legacy positive 1 -> 2", RE.ork11e_improve_ap(-2, 1) == -3 and RE.ork11e_improve_ap(0, 1) == -1 and RE.ork11e_improve_ap(1, 1) == 2)
	# The improved AP really worsens the save: Gretchin's AP0 grot blasta vs the
	# Custodian Guard's 2+ (4++): 2+ -> 3+ through the 11e allocation saves.
	_place(GS.state.units, "U_CUSTODIAN_GUARD_C", 6.0, 21.0)
	var grot := _first_ranged_weapon("U_GRETCHIN_D")
	var gr_off := _board_with({}, "U_GRETCHIN_D")
	var gr_on := _board_with({FLAG[GD]: true}, "U_GRETCHIN_D")
	var thr0 := ""
	var thr1 := ""
	for s in range(30):
		var gs_a = _block(_auto(gr_off.duplicate(true), "U_GRETCHIN_D", _assign(gr_off, "U_GRETCHIN_D", grot, tgt), 800 + s), "save")
		var gs_b = _block(_auto(gr_on.duplicate(true), "U_GRETCHIN_D", _assign(gr_on, "U_GRETCHIN_D", grot, tgt), 800 + s), "save")
		if not gs_a.is_empty() and not gs_b.is_empty():
			thr0 = str(gs_a.get("threshold", ""))
			thr1 = str(gs_b.get("threshold", ""))
			break
	_check("GD: AP0 -> AP-1 turns the Custodians' 2+ save into 3+ (%s -> %s)" % [thr0, thr1], thr0 == "2+" and thr1 == "3+")
	_stage_target_near_r1()

	# LONG, UNCONTROLLED BURSTS — re-roll hit rolls vs FLY only.
	var lub_on := _board_with({FLAG[LUB]: true}, "U_TANKBUSTAS_A")
	var fly := lub_on.duplicate(true)
	fly.units[tgt].meta.keywords.append("FLY")
	var fly_off := off_b.duplicate(true)
	fly_off.units[tgt].meta.keywords.append("FLY")
	var REROLL_FAILED: int = RE.HitModifier.REROLL_FAILED
	var lh = _block(_interactive(fly, "U_TANKBUSTAS_A", _assign(fly, "U_TANKBUSTAS_A", busta, tgt), 31), "to_hit")
	var lh_nofly = _block(_interactive(lub_on, "U_TANKBUSTAS_A", _assign(lub_on, "U_TANKBUSTAS_A", busta, tgt), 31), "to_hit")
	_check("LUB interactive: re-roll vs a FLY target", int(lh.get("modifiers_applied", 0)) & REROLL_FAILED != 0)
	_check("LUB: no re-roll vs a non-FLY target", int(lh_nofly.get("modifiers_applied", 0)) & REROLL_FAILED == 0)
	var lha = _block(_auto(fly.duplicate(true), "U_TANKBUSTAS_A", _assign(fly, "U_TANKBUSTAS_A", busta, tgt), 31), "to_hit")
	_check("LUB auto: re-roll vs a FLY target", int(lha.get("modifiers_applied", 0)) & REROLL_FAILED != 0)
	var lub_hits := [0, 0]
	for s in range(25):
		lub_hits[0] += int(_block(_interactive(fly_off, "U_TANKBUSTAS_A", _assign(fly_off, "U_TANKBUSTAS_A", busta, tgt), 900 + s), "to_hit").get("successes", 0))
		lub_hits[1] += int(_block(_interactive(fly, "U_TANKBUSTAS_A", _assign(fly, "U_TANKBUSTAS_A", busta, tgt), 900 + s), "to_hit").get("successes", 0))
	_check("LUB A/B vs FLY: more hits over 25 seeds (%d -> %d)" % lub_hits, lub_hits[1] > lub_hits[0])

	# DRIVE-BY BUSTIN' — +1 to hit only on Firing Deck weapons.
	_section_drive_by(tgt)


const VA_VARIANT_SUSTAINED := "sustained_hits"


func _section_drive_by(tgt: String) -> void:
	var PLUS_ONE: int = RE.HitModifier.PLUS_ONE
	var b: Dictionary = GS.state.duplicate(true)
	# Loan one of the Tankbustas' rokkits onto the Trukk (24.14) and park the
	# Trukk 6" from the target.
	_place(b.units, "U_TRUKK_A", 10.0, 14.0)
	var tb_w = RE.get_unit_weapons("U_TANKBUSTAS_A", b)
	var loan_mid := ""
	var loan_wid := ""
	for mid in tb_w:
		if not tb_w[mid].is_empty():
			loan_mid = str(mid)
			loan_wid = str(tb_w[mid][0])
			break
	b.units.U_TRUKK_A.flags["firing_deck_weapons"] = [{"unit_id": "U_TANKBUSTAS_A", "model_id": loan_mid, "weapon_id": loan_wid}]
	var tw = RE.get_unit_weapons("U_TRUKK_A", b)
	var fd_bearer := ""
	var hull_wid := ""
	var hull_mid := ""
	for mid in tw:
		if RE.ork11e_is_firing_deck_bearer(mid):
			fd_bearer = str(mid)
		else:
			hull_mid = str(mid)
			for w in tw[mid]:
				if hull_wid == "" and str(w) != loan_wid:
					hull_wid = str(w)
	_check("DBB: Firing Deck loan exposed as bearer %s carrying %s" % [fd_bearer, loan_wid], fd_bearer != "" and loan_wid in tw.get(fd_bearer, []))
	var on: Dictionary = b.duplicate(true)
	on.units.U_TRUKK_A.flags[FLAG[DBB]] = true
	var fd_assign := {"weapon_id": loan_wid, "target_unit_id": tgt, "model_ids": [fd_bearer]}
	var hull_assign := {"weapon_id": hull_wid, "target_unit_id": tgt, "model_ids": [hull_mid]}
	var h_fd = _block(_interactive(on, "U_TRUKK_A", fd_assign, 41), "to_hit")
	var h_fd0 = _block(_interactive(b, "U_TRUKK_A", fd_assign, 41), "to_hit")
	var h_hull = _block(_interactive(on, "U_TRUKK_A", hull_assign, 41), "to_hit")
	_check("DBB interactive: Firing Deck weapon gets +1 to hit", int(h_fd.get("modifiers_applied", 0)) & PLUS_ONE != 0 and int(h_fd0.get("modifiers_applied", 0)) & PLUS_ONE == 0)
	_check("DBB interactive: the Trukk's own %s gets nothing" % hull_wid, int(h_hull.get("modifiers_applied", 0)) & PLUS_ONE == 0)
	var a_fd = _block(_auto(on.duplicate(true), "U_TRUKK_A", fd_assign, 41), "to_hit")
	var a_hull = _block(_auto(on.duplicate(true), "U_TRUKK_A", hull_assign, 41), "to_hit")
	_check("DBB auto: +1 on the Firing Deck weapon only", int(a_fd.get("modifiers_applied", 0)) & PLUS_ONE != 0 and int(a_hull.get("modifiers_applied", 0)) & PLUS_ONE == 0)
	# Same base weapon on the hull AND on the deck: per-attack +1 (mixed batch).
	var mix: Dictionary = on.duplicate(true)
	mix.units.U_TRUKK_A.flags["firing_deck_weapons"] = [{"unit_id": "U_TANKBUSTAS_A", "model_id": loan_mid, "weapon_id": hull_wid}]
	var mixw = RE.get_unit_weapons("U_TRUKK_A", mix)
	var mix_fd := ""
	for mid in mixw:
		if RE.ork11e_is_firing_deck_bearer(mid):
			mix_fd = str(mid)
	var mix_assign := {"weapon_id": hull_wid, "target_unit_id": tgt, "model_ids": [hull_mid, mix_fd]}
	var hm = _interactive(mix, "U_TRUKK_A", mix_assign, 43)
	var hmb = _block(hm, "to_hit")
	var raw: Array = hmb.get("rolls_raw", [])
	var modded: Array = hmb.get("rolls_modified", [])
	var hull_attacks := 0
	var hull_prof = RE.get_weapon_profile(hull_wid, mix)
	# Every hull attack keeps its roll, every Firing Deck attack is +1 (no other modifiers here).
	# The two bearers' attacks differ by exactly +1 (whatever else applies).
	var offsets := {}
	for i in range(mini(raw.size(), modded.size())):
		var off_i := int(modded[i]) - int(raw[i])
		offsets[off_i] = int(offsets.get(off_i, 0)) + 1
	var offs: Array = offsets.keys()
	offs.sort()
	_check("DBB mixed batch: the Firing Deck attacks get +1, the hull's own do not (offsets %s)" % str(offsets),
		offs.size() == 2 and int(offs[1]) == int(offs[0]) + 1 and int(offsets[offs[1]]) == raw.size() / 2 and int(hmb.get("modifiers_applied", 0)) & PLUS_ONE == 0, str(hull_prof.get("attacks", "?")))
	var hits_res = RE.resolve_shoot_hits({"type": "SHOOT", "actor_unit_id": "U_TRUKK_A", "payload": {"assignments": [mix_assign]}}, mix, RE.RNGService.new(43))
	var hctx: Dictionary = hits_res.get("hit_context", {})
	_check("DBB staged path keeps the per-attack mask for Command Re-roll", hctx.get("ork11e_fd_plus_one", []).has(true) and hctx.get("ork11e_fd_plus_one", []).has(false))
	_check("DBB helper: a Trukk WITHOUT the flag gives no bonus", not RE.ork11e_drive_by_bustin_active(b.units.U_TRUKK_A))


# ---------------------------------------------------------------------------
func _section_vindictive() -> void:
	print("\n-- F. VINDICTIVE ARTILLERISTS variants --")
	var va := _sid(VA)
	PM.transition_to_phase(PHASE_SHOOTING)
	_reset_usage()
	var offers = SM.get_window_offers(1, WINDOW, {"phase": "shooting", "unit_id": "U_MEK_GUNZ_A"})
	var t: Dictionary = offers[0].targets[0] if offers.size() == 1 and offers[0].targets.size() == 1 else {}
	var vids: Array = t.get("variants", []).map(func(v): return str(v.id))
	_check("three variants offered (lethal / sustained / overcharge), all 1 CP", vids == ["lethal_hits", "sustained_hits", "overcharge"]
		and t.get("variants", []).all(func(v): return int(v.cp_cost) == 1), str(t))
	_check("require_variant (no plain use)", bool(t.get("require_variant", false)))

	# Dialog: variant buttons only.
	var dlg = load("res://dialogs/StratagemDialog.gd").new()
	dlg.name = "StratagemDialog"
	root.add_child(dlg)
	dlg.setup_window(1, WINDOW, offers, {"phase": "shooting", "unit_id": "U_MEK_GUNZ_A", "window_id": WINDOW})
	var safe: String = dlg.node_safe_id(va)
	var btns = dlg.get_node_or_null("Content/StratScroll/StratList/Card_%s/Buttons" % safe)
	var names: Array = []
	if btns:
		for c in btns.get_children():
			names.append(str(c.name))
	_check("dialog: no plain Use button", not ("Use_%s_U_MEK_GUNZ_A" % safe) in names, str(names))
	_check("dialog: Use_<sid>_U_MEK_GUNZ_A_<variant> for all three", names.size() == 3
		and ("Use_%s_U_MEK_GUNZ_A_overcharge" % safe) in names and ("Use_%s_U_MEK_GUNZ_A_lethal_hits" % safe) in names, str(names))
	dlg.queue_free()

	# Phase USE: without a variant refused, unknown variant refused, chosen variant applied.
	var phase = _fresh_shooting_phase()
	_stage_target_near_r1()
	var res = phase.execute_action({"type": "SELECT_SHOOTER", "actor_unit_id": "U_MEK_GUNZ_A", "player": 1})
	_check("Mek Gunz selection opens the window", res.get("success", false) and phase.has_pending_stratagem_window(), str(res.get("error", "")))
	var no_var = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": WINDOW, "stratagem_id": va, "target_unit_id": "U_MEK_GUNZ_A"})
	_check("USE without a variant refused", not no_var.get("success", true) and "options" in str(no_var.get("error", "")), str(no_var))
	var bad_var = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": WINDOW, "stratagem_id": va, "target_unit_id": "U_MEK_GUNZ_A", "context": {"variant_id": "nope"}})
	_check("USE with an unknown variant refused", not bad_var.get("success", true))
	var cp0 := _cp(1)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": WINDOW, "stratagem_id": va, "target_unit_id": "U_MEK_GUNZ_A", "context": {"variant_id": "overcharge"}})
	_check("USE overcharge succeeds (CP -1)", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	var f = GS.state.units.U_MEK_GUNZ_A.flags
	_check("overcharge: marker + ranged [LETHAL HITS] + ranged [HAZARDOUS]", str(f.get(FLAG[VA], "")) == "overcharge" and f.get("effect_lethal_hits_ranged", false) and f.get("effect_grant_hazardous", false), str(f))
	_check("overcharge: ranged [SUSTAINED HITS 1]", RE.ork11e_ranged_sustained_hits(GS.state.units.U_MEK_GUNZ_A) == 1)

	# Granted [HAZARDOUS] really makes hazard rolls (non-hazardous weapon).
	var mw := ""
	var w = RE.get_unit_weapons("U_MEK_GUNZ_A", GS.state)
	for mid in w:
		for wid in w[mid]:
			if not RE.is_hazardous_weapon(str(wid), GS.state):
				mw = str(wid)
	_check("Mek Gunz carry a non-[HAZARDOUS] gun (%s)" % mw, mw != "")
	if mw != "":
		var hz = RE.resolve_hazardous_check("U_MEK_GUNZ_A", mw, 1, GS.state.duplicate(true), RE.RNGService.new(3))
		_check("granted [HAZARDOUS]: resolve_hazardous_check rolls (11e: fail on 1-2)", hz.get("rolls", []).size() == 1, str(hz))
		var plain = GS.state.duplicate(true)
		plain.units.U_MEK_GUNZ_A.flags.erase("effect_grant_hazardous")
		_check("without the grant: no hazard roll", RE.resolve_hazardous_check("U_MEK_GUNZ_A", mw, 1, plain, RE.RNGService.new(3)).get("rolls", []).size() == 0)
		var until = RE.resolve_shoot_until_wounds({"type": "SHOOT", "actor_unit_id": "U_MEK_GUNZ_A", "payload": {"assignments": [_assign(GS.state, "U_MEK_GUNZ_A", mw, "U_CUSTODIAN_GUARD_C")]}}, GS.state.duplicate(true), RE.RNGService.new(4))
		_check("interactive resolver queues the hazard check for the granted weapon", not until.get("hazardous_weapons", []).is_empty())
		var lh = _block(until, "to_hit")
		_check("interactive: lethal + sustained on the hit block", lh.get("lethal_hits_weapon", false) and int(lh.get("sustained_hits_value", 0)) == 1, str(lh.get("lethal_hits_weapon")))
	SM.on_phase_end(PHASE_SHOOTING)
	_check("expiry: overcharge flags cleared", not GS.state.units.U_MEK_GUNZ_A.flags.has(FLAG[VA])
		and not GS.state.units.U_MEK_GUNZ_A.flags.has("effect_lethal_hits_ranged") and not GS.state.units.U_MEK_GUNZ_A.flags.has("effect_grant_hazardous"))

	# The lethal-only variant does not grant HAZARDOUS or SUSTAINED.
	_reset_usage()
	var r = SM.use_stratagem(1, va, "U_MEK_GUNZ_A", {"window_id": WINDOW, "unit_id": "U_MEK_GUNZ_A", "variant_id": "lethal_hits"})
	f = GS.state.units.U_MEK_GUNZ_A.flags
	_check("lethal variant: [LETHAL HITS] only", r.get("success", false) and f.get("effect_lethal_hits_ranged", false) and not f.has("effect_grant_hazardous") and RE.ork11e_ranged_sustained_hits(GS.state.units.U_MEK_GUNZ_A) == 0, str(f))
	SM.on_phase_end(PHASE_SHOOTING)
	_reset_usage()
	r = SM.use_stratagem(1, va, "U_MEK_GUNZ_A", {"window_id": WINDOW, "unit_id": "U_MEK_GUNZ_A", "variant_id": "sustained_hits"})
	f = GS.state.units.U_MEK_GUNZ_A.flags
	_check("sustained variant: [SUSTAINED HITS 1] only", r.get("success", false) and not f.has("effect_lethal_hits_ranged") and not f.has("effect_grant_hazardous") and RE.ork11e_ranged_sustained_hits(GS.state.units.U_MEK_GUNZ_A) == 1, str(f))
	SM.on_phase_end(PHASE_SHOOTING)


# ---------------------------------------------------------------------------
func _section_expiry() -> void:
	print("\n-- G. expiry --")
	var targets := {CRD: "U_TANKBUSTAS_A", DBB: "U_TRUKK_A", KD: "U_TANKBUSTAS_A", GD: "U_FLASH_GITZ_A", NED: "U_KOMMANDOS_A", LUB: "U_DAKKAJET_A", DS: "U_WARBIKERS_A"}
	for csv in targets:
		var sid := _sid(csv)
		PM.transition_to_phase(PHASE_COMMAND)
		PM.transition_to_phase(PHASE_SHOOTING)
		_reset_usage()
		var uid: String = targets[csv]
		var r = SM.use_stratagem(1, sid, uid, {"window_id": WINDOW, "unit_id": uid, "phase": "shooting"})
		_check("%s used on %s" % [csv, uid], r.get("success", false) and GS.state.units[uid].flags.get(FLAG[csv], false), str(r.get("error", "")))
		var eff_ok := false
		for e in SM.active_effects:
			if str(e.get("stratagem_id", "")) == sid and str(e.get("expires", "")) == "end_of_phase":
				eff_ok = true
		_check("%s expires end_of_phase" % csv, eff_ok)
		# Real phase exit (ShootingPhase._on_phase_exit -> StratagemManager.on_phase_end).
		PM.transition_to_phase(PHASE_CHARGE)
		_check("%s flag gone after the Shooting phase ends" % csv, not GS.state.units[uid].flags.has(FLAG[csv]))


# ---------------------------------------------------------------------------
func _section_ai() -> void:
	print("\n-- H. AI decider --")
	var ADM = load("res://scripts/AIDecisionMaker.gd")
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_SHOOTING)
	_reset_usage()
	_stage_target_near_r1()
	var va := _sid(VA)
	var ctx := {"phase": "shooting", "unit_id": "U_MEK_GUNZ_A", "planned_target_unit_ids": ["U_CUSTODIAN_GUARD_C"]}
	var G = load("res://scripts/stratagems/ork_codex/OrkCodexShooting.gd")
	var offers = SM.get_window_offers(1, WINDOW, ctx)
	var t = offers[0].targets[0] if not offers.is_empty() else {}
	_check("VINDICTIVE target entry carries an ai_variant hint", str(t.get("ai_variant", "")) in ["lethal_hits", "sustained_hits", "overcharge"], str(t))
	var lone: float = G.ai_score(SM.get_stratagem(va), 1, "U_MEK_GUNZ_A", WINDOW, ctx)
	var d = ADM.decide_window_stratagem(1, WINDOW, offers, ctx)
	_check("AI VINDICTIVE: a lone gun scores low (%.2f) -> declined" % lone, lone < 2.0 and not d.get("use", true), str(d))
	# A bigger battery (test-only: five extra gun models) is worth it — the AI
	# must then always pass a variant (no plain use exists) = the handler's hint.
	var mg: Array = GS.state.units.U_MEK_GUNZ_A.models
	var orig_models: Array = mg.duplicate(true)
	for k in range(5):
		var extra: Dictionary = mg[0].duplicate(true)
		extra["id"] = "mx%d" % k
		mg.append(extra)
	offers = SM.get_window_offers(1, WINDOW, ctx)
	t = offers[0].targets[0] if not offers.is_empty() else {}
	d = ADM.decide_window_stratagem(1, WINDOW, offers, ctx)
	_check("AI VINDICTIVE on a battery: used with the hinted variant", d.get("use", false)
		and str(d.get("context", {}).get("variant_id", "")) == str(t.get("ai_variant", "?")), "%s hint=%s" % [str(d), str(t.get("ai_variant", ""))])
	GS.state.units.U_MEK_GUNZ_A["models"] = orig_models

	var crd := _sid(CRD)
	ctx = {"phase": "shooting", "unit_id": "U_TANKBUSTAS_A", "planned_target_unit_ids": ["U_CUSTODIAN_GUARD_C"]}
	offers = SM.get_window_offers(1, WINDOW, ctx)
	d = ADM.decide_window_stratagem(1, WINDOW, offers, ctx)
	_check("AI uses CLOSE-RANGE DAKKA with every bearer in half range", d.get("use", false) and str(d.get("stratagem_id", "")) == crd, str(d))
	GS.state.players["1"]["cp"] = 1
	offers = SM.get_window_offers(1, WINDOW, ctx)
	d = ADM.decide_window_stratagem(1, WINDOW, offers, ctx)
	_check("AI keeps its last CP (offensive needs >= 2 CP)", not d.get("use", true), str(d))
	GS.state.players["1"]["cp"] = 6
	var far_ctx := {"phase": "shooting", "unit_id": "U_TANKBUSTAS_A", "planned_target_unit_ids": ["U_CUSTODIAN_GUARD_F"]}
	_check("CLOSE-RANGE DAKKA scores 0 with no target in half range", G.ai_score(SM.get_stratagem(crd), 1, "U_TANKBUSTAS_A", WINDOW, far_ctx) == 0.0)
	var lub := _sid(LUB)
	_check("LONG, UNCONTROLLED BURSTS scores 0 without a FLY target", G.ai_score(SM.get_stratagem(lub), 1, "U_DAKKAJET_A", WINDOW, {"planned_target_unit_ids": ["U_CUSTODIAN_GUARD_C"]}) == 0.0)
	var kd := _sid(KD)
	_check("KUSTOM DAKKA scores > 0 vs INFANTRY", G.ai_score(SM.get_stratagem(kd), 1, "U_KOMMANDOS_A", WINDOW, {"planned_target_unit_ids": ["U_CUSTODIAN_GUARD_C"]}) > 0.0)
	# DRIVE-BY BUSTIN': an AI SHOOT whose planned assignments carry no Firing
	# Deck bearer would waste the CP — score 0 (the loan comes after planning).
	var dbb := _sid(DBB)
	var tr = GS.state.units.U_TRUKK_A
	var saved_emb = tr.transport_data.get("embarked_units", []).duplicate()
	tr.transport_data["embarked_units"] = ["U_BREAKA_BOYZ_A"]
	var est: float = G.ai_score(SM.get_stratagem(dbb), 1, "U_TRUKK_A", WINDOW, {"planned_target_unit_ids": ["U_CUSTODIAN_GUARD_C"]})
	var none_planned: float = G.ai_score(SM.get_stratagem(dbb), 1, "U_TRUKK_A", WINDOW, {"planned_target_unit_ids": ["U_CUSTODIAN_GUARD_C"], "planned_bearer_ids": ["m1"]})
	var fd_planned: float = G.ai_score(SM.get_stratagem(dbb), 1, "U_TRUKK_A", WINDOW, {"planned_target_unit_ids": ["U_CUSTODIAN_GUARD_C"], "planned_bearer_ids": ["m1", "m1@fd0"]})
	tr.transport_data["embarked_units"] = saved_emb
	_check("DRIVE-BY BUSTIN' AI score: > 0 with passengers (%.2f), 0 when the SHOOT plans no Firing Deck gun, > 0 when it does" % est,
		est > 0.0 and none_planned == 0.0 and fd_planned > 0.0, "%.2f / %.2f / %.2f" % [est, none_planned, fd_planned])
