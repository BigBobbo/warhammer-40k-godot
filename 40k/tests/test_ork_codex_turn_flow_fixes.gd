extends SceneTree

# Codex: Orks (11e) — verification fixes, cluster C (fight / charge / scoring /
# command). Regression checks for the verified defects, against the real
# fixtures (tests/saves/ork11e_orks_active / _reactive), real phase actions
# where the flow matters:
#   A. per-turn charge / fight flags end with the turn that set them
#      (WH-1 / UC-1 / KIR-2): MOW 'EM DOWN, UNBRIDLED CARNAGE, Fights First,
#      eligibility and KEEP IT RUNNIN' in the opponent's Fight phase; SP/MP sync
#   B. STOMPING JUGGERNAUT MOBILE and the charge climb penalty (r2:F2)
#   C. INSTINCTIVE HUNTERS leaves no ghost on the battlefield (r3:F1)
#   D. transport markers: disembark only blocks embarking that turn (KIR-1),
#      embarked_this_phase (RB-1), wholly within the set-up distance (RB-2)
#   E. Fight On Death stratagems not offered once selected to fight (WH-5/F3)
#   F. ARMED TO DA TEEF: re-roll non-critical hits variant (F4), clear()
#      leaves / restores another source's re-roll (F5)
#   G. [CLEAVE] counts the whole Attached target unit (WH-2)
#   H. Fight On Death removal credited to the destroying attacker (framework:F13)
#   I. secured objectives only break at the END of a phase (DR-1)
#   J. Command Re-roll hidden for a unit already targeted this phase (EWG-1)
#   K. AI KEEP IT RUNNIN' keeps objective holders on the table (KIR-AI)
#   L. Deadly Demise resolves outside the Shooting / Fight phases (r5:F13)
#   M. FightPhase has no ungated print() (RG-F3)
#
# Usage: godot --headless --path 40k --script tests/test_ork_codex_turn_flow_fixes.gd

const ACTIVE := "ork11e_orks_active"
const REACTIVE := "ork11e_orks_reactive"
const PHASE_COMMAND := 6
const PHASE_MOVEMENT := 7
const PHASE_SHOOTING := 8
const PHASE_CHARGE := 9
const PHASE_FIGHT := 10
const PHASE_SCORING := 11
const PX := 40.0

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var RE = null
var MM = null
var AI = null
var ADM = null
var Fight = null


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

func _load(fixture: String) -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + fixture + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + fixture + ext))
	var ok: bool = slm.load_game(fixture)
	GameConstants.edition = 11
	_ai_off()
	SM._usage_history = {"1": [], "2": []}
	SM.active_effects = []
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 6
	MM._sticky_objectives.clear()
	return ok


func _ai_off() -> void:
	AI.enabled = false
	AI.ai_players = {1: false, 2: false}


func _set_detachment(player: int, det: String) -> void:
	GS.state.factions[str(player)]["detachment"] = det
	SM.load_faction_stratagems_for_player(player)


func _sid(player: int, csv: String) -> String:
	for s in SM.get_faction_stratagems_for_player(player):
		if str(s.get("csv_id", "")) == csv:
			return str(s.id)
	return ""


func _cp(p: int) -> int:
	return int(GS.state.players[str(p)].cp)


func _phase():
	return PM.get_current_phase_instance()


func _unit(uid: String) -> Dictionary:
	return GS.state.units.get(uid, {})


func _flags(uid: String) -> Dictionary:
	return _unit(uid).get("flags", {})


func _pos(m: Dictionary) -> Vector2:
	var p = m.get("position")
	return Vector2(float(p.x), float(p.y)) if p is Dictionary else p


func _centroid(uid: String) -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for m in _unit(uid).get("models", []):
		if m.get("position", null) == null:
			continue
		c += _pos(m)
		n += 1
	return c / float(max(1, n))


func _move_to(uid: String, at_in: Vector2) -> void:
	var d: Vector2 = at_in * PX - _centroid(uid)
	for m in _unit(uid).get("models", []):
		if m.get("position", null) == null:
			continue
		var p := _pos(m)
		m["position"] = {"x": p.x + d.x, "y": p.y + d.y}


func _place_rows(uid: String, x0: float, y0: float, per_row: int, dx: float, dy: float) -> void:
	var ms: Array = _unit(uid).models
	for i in range(ms.size()):
		ms[i]["position"] = {"x": (x0 + (i % per_row) * dx) * PX, "y": (y0 + int(i / per_row) * dy) * PX}


func _kill(uid: String, n: int) -> void:
	var k := 0
	for m in _unit(uid).get("models", []):
		if k >= n:
			break
		if m.get("alive", true):
			m["alive"] = false
			m["current_wounds"] = 0
			k += 1


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


func _drain(phase) -> void:
	for _i in range(8):
		if not phase.has_pending_stratagem_window():
			return
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(phase.get_pending_stratagem_window().player),
			"window_id": str(phase.get_pending_stratagem_window().get("window_id", ""))})


func _end_turn() -> Dictionary:
	# The real END_SCORING action of the Scoring phase.
	PM.transition_to_phase(PHASE_SCORING)
	return _phase().execute_action({"type": "END_SCORING", "player": GS.get_active_player()})


func _pass_pile_in(phase) -> void:
	for _i in [1, 2]:
		if int(phase.pile_in_step_11e) != int(phase.PileInStep11e.ACTIVE):
			break
		phase.execute_action({"type": "END_PILE_IN", "player": int(phase.piling_in_player_11e)})


func _obj(oid: String) -> Dictionary:
	for o in GS.state.board.get("objectives", []):
		if str(o.get("id", "")) == oid:
			return o
	return {}


func _melee_weapon(uid: String) -> String:
	for w in _unit(uid).get("meta", {}).get("weapons", []):
		if str(w.get("type", "")).to_lower() == "melee":
			return str(w.get("name", ""))
	return ""


func _hit_block(result: Dictionary) -> Dictionary:
	for d in result.get("dice", []):
		if str(d.get("context", "")) == "hit_roll_melee":
			return d
	return {}


# ---------------------------------------------------------------------------
func _run() -> void:
	SM = root.get_node("StratagemManager")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	MM = root.get_node("MissionManager")
	AI = root.get_node("AIPlayer")
	ADM = load("res://scripts/AIDecisionMaker.gd")
	Fight = load("res://scripts/stratagems/ork_codex/OrkCodexFight.gd")
	var ss = root.get_node_or_null("SettingsService")
	if ss:
		ss.set("auto_allocate_wounds", true)
	GameConstants.edition = 11
	print("\n=== test_ork_codex_turn_flow_fixes ===\n")

	await _section_turn_flags()
	await _section_mobile_charge()
	await _section_instinctive_hunters_ghost()
	await _section_transport_markers()
	await _section_fod_offers()
	await _section_armed_to_da_teef()
	await _section_cleave_attached()
	await _section_fod_attribution()
	await _section_secured_objective()
	await _section_command_reroll_15_01()
	await _section_kir_ai()
	await _section_deadly_demise_other_phases()
	_section_gated_prints()
	_ai_off()


# ---------------------------------------------------------------------------
# A. per-turn charge / fight flags
# ---------------------------------------------------------------------------
func _section_turn_flags() -> void:
	print("\n-- A. charge / fight 'this turn' flags end with the turn (WH-1 / UC-1 / KIR-2) --")
	_check("fixture loads", _load(ACTIVE))
	var mow := _sid(1, "mow-em-down-war-horde")
	GS.state.players["2"]["cp"] = 0  # no Fire Overwatch / Heroic Intervention
	_move_to("U_CUSTODIAN_GUARD_E", Vector2(40, 52))
	_move_to("U_BATTLEWAGON_A", Vector2(40, 44.5))
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_CHARGE)
	var phase = _phase()
	var applied := {}
	for s in [11, 21, 31, 41, 51]:
		applied = _charge(phase, "U_BATTLEWAGON_A", "U_CUSTODIAN_GUARD_E", s)
		if applied.get("success", false):
			break
		PM.transition_to_phase(PHASE_CHARGE)
		phase = _phase()
	_drain(phase)
	_check("real charge: the Battlewagon made a charge move", applied.get("success", false) and bool(_flags("U_BATTLEWAGON_A").get("charged_this_turn", false)), str(applied.get("error", "")))
	_check("…and has Fights First this turn", bool(_flags("U_BATTLEWAGON_A").get("fights_first", false)))
	# A BOYZ unit that charged in the same turn (ChargePhase writes these).
	for uid in ["U_BOYZ_B", "U_WARBOSS_A"]:
		_flags(uid)["charged_this_turn"] = true
		_flags(uid)["fights_first"] = true
	PM.transition_to_phase(PHASE_FIGHT)
	_check("own turn: MOW 'EM DOWN offered for the charged Battlewagon", mow in _offer_ids(SM.get_window_offers(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_BATTLEWAGON_A"})))
	_check("own turn: the charged Battlewagon is Fights First", _phase().sequencer_11e.group_is_fights_first("U_BATTLEWAGON_A", GS.state))

	var es := _end_turn()
	_check("real END_SCORING ends P1's turn", es.get("success", false) and GS.get_active_player() == 2, str(es.get("error", "")))
	for uid in ["U_BATTLEWAGON_A", "U_BOYZ_B", "U_WARBOSS_A"]:
		_check("%s: charged_this_turn / fights_first cleared at the end of the turn" % uid,
			not _flags(uid).has("charged_this_turn") and not _flags(uid).has("fights_first"), str(_flags(uid)))
	var removed_ended := false
	for c in es.get("changes", []):
		if str(c.get("path", "")) == "units.U_BATTLEWAGON_A.flags.charged_this_turn" and str(c.get("op", "")) == "remove":
			removed_ended = true
	_check("the clear rides in the END_SCORING result (replay / network)", removed_ended)

	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_MOVEMENT)
	PM.transition_to_phase(PHASE_SHOOTING)
	PM.transition_to_phase(PHASE_CHARGE)
	PM.transition_to_phase(PHASE_FIGHT)
	phase = _phase()
	_check("P2's Fight phase", GS.get_current_phase() == PHASE_FIGHT and GS.get_active_player() == 2)
	_check("opponent's Fight phase: MOW 'EM DOWN not offered (no charge move this turn)",
		not mow in _offer_ids(SM.get_window_offers(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_BATTLEWAGON_A"})))
	var mow_check = SM.can_use_stratagem(1, mow, "U_BATTLEWAGON_A", {"window_id": "unit_selected_to_fight", "unit_id": "U_BATTLEWAGON_A"})
	_check("MOW 'EM DOWN refused: has not made a charge move this turn", not mow_check.can_use and "charge move" in str(mow_check.reason), str(mow_check))
	_check("Battlewagon not Fights First in the opponent's turn", not phase.sequencer_11e.group_is_fights_first("U_BATTLEWAGON_A", GS.state))
	_check("Boyz not Fights First in the opponent's turn", not phase.sequencer_11e.group_is_fights_first("U_BOYZ_B", GS.state))
	_pass_pile_in(phase)
	var peek: Dictionary = phase.sequencer_11e.peek_selection(GS.state)
	_check("fights-first ordering: no Fights First step, the ACTIVE player (P2) picks first", str(peek.get("step", "")) == "remaining" and int(peek.get("player", 0)) == 2, str(peek))
	_set_detachment(1, "Green Tide")
	var uc := _sid(1, "unbridled-carnage-green-tide")
	_check("opponent's Fight phase: UNBRIDLED CARNAGE not offered for the Boyz",
		not uc in _offer_ids(SM.get_window_offers(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_BOYZ_B"})))
	# KEEP IT RUNNIN': an unengaged unit that only charged LAST turn was not
	# eligible to fight this phase.
	_move_to("U_KOMMANDOS_A", Vector2(17.5, 14.0))
	_flags("U_KOMMANDOS_A").erase("was_eligible_to_fight")
	_check("unengaged unit that did not charge this turn: not eligible to fight", not phase.sequencer_11e.eligible_to_fight("U_KOMMANDOS_A", GS.state))

	# SP / MP sync: GameManager mirrors the end-of-turn clear.
	var SPS = load("res://phases/ScoringPhase.gd")
	var GM = root.get_node("GameManager")
	_check("ScoringPhase.ENDED_TURN_FLAGS == GameManager.ENDED_TURN_FLAGS", str(SPS.ENDED_TURN_FLAGS) == str(GM.ENDED_TURN_FLAGS), "%s vs %s" % [str(SPS.ENDED_TURN_FLAGS), str(GM.ENDED_TURN_FLAGS)])
	_flags("U_NOBZ_A")["charged_this_turn"] = true
	_flags("U_NOBZ_A")["has_fought"] = true
	_flags("U_CUSTODIAN_GUARD_A")["charged_this_turn"] = true
	var gm_diffs: Array = GM._create_ended_turn_flag_reset_diffs(1)
	var paths: Array = gm_diffs.map(func(d): return str(d.get("path", "")))
	_check("GameManager: the ending player's charge/fight flags removed", "units.U_NOBZ_A.flags.charged_this_turn" in paths and "units.U_NOBZ_A.flags.has_fought" in paths, str(paths))
	_check("GameManager: the other player's flags untouched", not "units.U_CUSTODIAN_GUARD_A.flags.charged_this_turn" in paths)


func _charge(phase, charger: String, target: String, seed_val: int) -> Dictionary:
	var dec = phase.execute_action({"type": "DECLARE_CHARGE", "actor_unit_id": charger, "player": 1, "payload": {"target_unit_ids": [target]}})
	if not dec.get("success", false):
		return {"error": "DECLARE_CHARGE: %s" % str(dec.get("error", dec.get("errors", "")))}
	_drain(phase)
	if phase.awaiting_fire_overwatch:
		phase.execute_action({"type": "DECLINE_FIRE_OVERWATCH", "player": 2})
	var roll = phase.execute_action({"type": "CHARGE_ROLL", "actor_unit_id": charger, "player": 1, "payload": {"rng_seed": seed_val}})
	if not roll.get("success", false):
		return {"error": "CHARGE_ROLL: %s" % str(roll.get("error", ""))}
	if phase.awaiting_ability_reroll:
		phase.execute_action({"type": "DECLINE_ABILITY_REROLL", "actor_unit_id": charger, "player": 1})
	if phase.awaiting_reroll_decision:
		phase.execute_action({"type": "DECLINE_COMMAND_REROLL", "actor_unit_id": charger, "player": 1})
	if not phase.pending_charges.has(charger):
		return {"error": "charge failed after the roll"}
	var dist := int(phase.pending_charges[charger].get("distance", 0))
	var mv: Dictionary = ADM._compute_charge_move(GS.create_snapshot(), charger, dist, [target], 1)
	if str(mv.get("type", "")) != "APPLY_CHARGE_MOVE":
		return {"error": "no legal charge move"}
	mv["player"] = 1
	return phase.execute_action(mv)


# ---------------------------------------------------------------------------
# B. STOMPING JUGGERNAUT MOBILE vs the charge climb penalty
# ---------------------------------------------------------------------------
func _wall_between(k0: Vector2) -> Dictionary:
	return {"id": "c_wall", "type": "ruins", "category": "dense", "height_category": "tall", "height": 5.0, "height_inches": 5.0,
		"piece_class": "feature", "can_move_through": {"INFANTRY": true, "VEHICLE": false, "MONSTER": false},
		"polygon": PackedVector2Array([k0 + Vector2(-200, 3.0 * PX), k0 + Vector2(200, 3.0 * PX), k0 + Vector2(200, 3.5 * PX), k0 + Vector2(-200, 3.5 * PX)])}


func _section_mobile_charge() -> void:
	print("\n-- B. MOBILE (STOMPING JUGGERNAUT) and the charge climb penalty (r2:F2) --")
	var TM = root.get_node("TerrainManager")
	var saved: Array = TM.terrain_features.duplicate(true)
	var a := Vector2(400, 400)
	var wall := _wall_between(a)
	TM.terrain_features = [wall]
	var walker_kw := ["VEHICLE", "WALKER", "ORKS"]
	var b := a + Vector2(0, 6.0 * PX)
	_check("walker crossing a tall dense wall pays height x2 (12\")", is_equal_approx(TM.calculate_charge_terrain_penalty(a, b, false, walker_kw), 12.0), str(TM.calculate_charge_terrain_penalty(a, b, false, walker_kw)))
	_check("MOBILE walker: no climb (13.06 horizontal through dense)", is_zero_approx(TM.calculate_charge_terrain_penalty(a, b, false, walker_kw + ["MOBILE"])))
	_check("BEASTS / SWARM: no climb either", is_zero_approx(TM.calculate_charge_terrain_penalty(a, b, false, ["BEASTS"])) and is_zero_approx(TM.calculate_charge_terrain_penalty(a, b, false, ["SWARM"])))
	var light := wall.duplicate(true)
	light["category"] = "light"
	light["type"] = "barricade"
	TM.terrain_features = [light]
	_check("MOBILE does not exempt a LIGHT piece's climb (dense only)", TM.calculate_charge_terrain_penalty(a, b, false, walker_kw + ["MOBILE"]) > 0.0)
	TM.terrain_features = [wall]
	GameConstants.edition = 10
	_check("10e: MOBILE gives no exemption (11e rule)", TM.calculate_charge_terrain_penalty(a, b, false, walker_kw + ["MOBILE"]) > 0.0)
	GameConstants.edition = 11
	TM.terrain_features = saved

	# Real path: SELECT / DECLARE_CHARGE -> window (USE SJ) -> CHARGE_ROLL through the wall.
	for with_sj in [false, true]:
		_load(ACTIVE)
		_set_detachment(1, "Dread Mob")
		var sj := _sid(1, "stomping-juggernaut-dread-mob")
		GS.state.players["2"]["cp"] = 0
		PM.transition_to_phase(PHASE_COMMAND)
		PM.transition_to_phase(PHASE_CHARGE)
		var cphase = _phase()
		var k0 := _pos(_unit("U_KILLA_KANS_A").models[0])
		var cg: Array = _unit("U_CUSTODIAN_GUARD_C").models
		for i in range(cg.size()):
			cg[i]["position"] = {"x": k0.x + (i - 2) * 1.6 * PX, "y": k0.y + 8.0 * PX}
		cphase.game_state_snapshot = GS.create_snapshot()
		saved = TM.terrain_features.duplicate(true)
		TM.terrain_features.append(_wall_between(k0))
		cphase.execute_action({"type": "SELECT_CHARGE_UNIT", "actor_unit_id": "U_KILLA_KANS_A", "player": 1})
		var dec = cphase.execute_action({"type": "DECLARE_CHARGE", "actor_unit_id": "U_KILLA_KANS_A", "player": 1, "payload": {"target_unit_ids": ["U_CUSTODIAN_GUARD_C"]}})
		var pend_id := str(cphase.get_pending_stratagem_window().get("window_id", "")) if cphase.has_pending_stratagem_window() else ""
		if with_sj:
			_check("unit_declares_charge window offers STOMPING JUGGERNAUT", dec.get("success", false) and pend_id == "unit_declares_charge")
			var use = cphase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_declares_charge", "stratagem_id": sj, "target_unit_id": "U_KILLA_KANS_A"})
			_check("SJ used: the Kans have MOBILE", use.get("success", false) and bool(_flags("U_KILLA_KANS_A").get("ork11e_mobile", false)), str(use.get("error", "")))
			_check("the charge's terrain keywords include MOBILE", "MOBILE" in cphase._charge_terrain_keywords("U_KILLA_KANS_A"))
		else:
			_drain(cphase)
		cphase.execute_action({"type": "CHARGE_ROLL", "actor_unit_id": "U_KILLA_KANS_A", "player": 1, "payload": {"rng_seed": 14}})
		if cphase.awaiting_ability_reroll:
			cphase.execute_action({"type": "DECLINE_ABILITY_REROLL", "actor_unit_id": "U_KILLA_KANS_A", "player": 1})
		if cphase.awaiting_reroll_decision:
			cphase.execute_action({"type": "DECLINE_COMMAND_REROLL", "actor_unit_id": "U_KILLA_KANS_A", "player": 1})
		var pc: Dictionary = cphase.pending_charges.get("U_KILLA_KANS_A", {})
		if with_sj:
			_check("MOBILE: 11\" roll vs ~6\" through the tall dense wall -> charge succeeds", pc.has("distance"), str(pc))
		else:
			_check("control: same 11\" roll without MOBILE fails (6\" + 12\" climb)", not pc.has("distance"), str(pc))
		TM.terrain_features = saved


# ---------------------------------------------------------------------------
# C. INSTINCTIVE HUNTERS: no ghost unit
# ---------------------------------------------------------------------------
func _section_instinctive_hunters_ghost() -> void:
	print("\n-- C. INSTINCTIVE HUNTERS leaves the battlefield for real (r3:F1) --")
	_load(REACTIVE)
	_set_detachment(2, "Da Big Hunt")
	_place_rows("U_BEAST_SNAGGA_BOYZ_A", 1.0, 40.0, 5, 1.4, 1.4)
	_place_rows("U_CUSTODIAN_GUARD_F", 1.0, 35.0, 5, 1.6, 1.6)
	_move_to("U_STORMBOYZ_A", Vector2(30, 50))  # keep other Ork units off the probe spot
	var old_pos := _pos(_unit("U_BEAST_SNAGGA_BOYZ_A").models[2])
	var probe_obj := {"id": "c_probe_obj", "position": old_pos}
	var before_target: bool = RE.get_eligible_targets("U_CUSTODIAN_GUARD_F", GS.state).has("U_BEAST_SNAGGA_BOYZ_A")
	var before_oc: int = MM._check_objective_control(probe_obj, GS.state.units)
	_check("before: Beast Snagga targetable by Custodian Guard F", before_target)
	_check("before: Beast Snagga control a marker on their position (P2)", before_oc == 2, str(before_oc))
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_FIGHT)
	var fphase = _phase()
	PM.apply_state_changes(fphase._ork11e_strategic_reserves_followup_diffs("U_BEAST_SNAGGA_BOYZ_A"))
	var u := _unit("U_BEAST_SNAGGA_BOYZ_A")
	_check("IN_RESERVES / strategic_reserves", int(u.get("status", -1)) == int(GS.UnitStatus.IN_RESERVES) and str(u.get("reserve_type", "")) == "strategic_reserves")
	var all_null := true
	for m in u.models:
		if m.get("position", null) != null:
			all_null = false
	_check("every model's position cleared (left the battlefield)", all_null)
	_check("not an eligible target any more", not RE.get_eligible_targets("U_CUSTODIAN_GUARD_F", GS.state).has("U_BEAST_SNAGGA_BOYZ_A"))
	_check("no objective control from the reserved unit", MM._check_objective_control(probe_obj, GS.state.units) == 0)
	_place_rows("U_CUSTODIAN_GUARD_F", 1.0, 38.0, 5, 1.6, 1.6)
	_check("an enemy next to the old spot is not engaged", not RE.is_unit_engaged("U_CUSTODIAN_GUARD_F", GS.state))
	var res_mgr = root.get_node_or_null("MovementPhase")
	_check("still a strategic-reserves unit that can arrive later", GS.get_units_in_reserves(2).has("U_BEAST_SNAGGA_BOYZ_A") if GS.has_method("get_units_in_reserves") else true)


# ---------------------------------------------------------------------------
# D. transport markers
# ---------------------------------------------------------------------------
func _section_transport_markers() -> void:
	print("\n-- D. disembark / embark markers (KIR-1, RB-1, RB-2) --")
	_load(ACTIVE)
	_set_detachment(1, "Blitz Brigade")
	var TMgr = root.get_node("TransportManager")
	TMgr.embark_unit("U_KOMMANDOS_A", "U_BATTLEWAGON_A")
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_MOVEMENT)
	var phase = _phase()
	_drain(phase)
	var w := _pos(_unit("U_BATTLEWAGON_A").models[0])
	var positions := []
	for i in range(_unit("U_KOMMANDOS_A").models.size()):
		positions.append({"x": w.x + (2.9 + int(i / 5) * 1.4) * PX, "y": w.y + (-3.0 + (i % 5) * 1.4) * PX})
	var d = phase.execute_action({"type": "CONFIRM_DISEMBARK", "actor_unit_id": "U_KOMMANDOS_A", "payload": {"positions": positions}})
	_check("real CONFIRM_DISEMBARK", d.get("success", false), str(d.get("error", "")))
	var ce = TMgr.can_embark("U_KOMMANDOS_A", "U_BATTLEWAGON_A")
	_check("same turn: cannot embark again (18.02: set up this turn)", not ce.get("valid", true) and "this turn" in str(ce.get("reason", "")), str(ce))
	var es := _end_turn()
	_check("END_SCORING (P1's turn ends)", es.get("success", false))
	_check("disembark marker cleared at the end of the turn", not bool(_unit("U_KOMMANDOS_A").get("disembarked_this_phase", false)) and not _flags("U_KOMMANDOS_A").has("disembarked_this_turn"), str(_unit("U_KOMMANDOS_A").get("disembarked_this_phase")))
	ce = TMgr.can_embark("U_KOMMANDOS_A", "U_BATTLEWAGON_A")
	_check("a later turn: can embark again (KEEP IT RUNNIN' / Movement embark)", ce.get("valid", false), str(ce))
	_end_turn()
	_check("P1's next turn: still embark-able", TMgr.can_embark("U_KOMMANDOS_A", "U_BATTLEWAGON_A").get("valid", false))

	# RB-1: a real EMBARK_UNIT marks embarked_this_phase; no disembark this phase.
	_load(ACTIVE)
	_set_detachment(1, "Blitz Brigade")
	var bw := _pos(_unit("U_BATTLEWAGON_A").models[0])
	var km: Array = _unit("U_KOMMANDOS_A").models
	for i in range(km.size()):
		km[i]["position"] = {"x": bw.x + (3.5 + int(i / 5) * 1.3) * PX, "y": bw.y + (-2.6 + (i % 5) * 1.3) * PX}
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_MOVEMENT)
	phase = _phase()
	_drain(phase)
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_KOMMANDOS_A"})
	_drain(phase)
	phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_KOMMANDOS_A", "payload": {}})
	_drain(phase)
	var emb = phase.execute_action({"type": "EMBARK_UNIT", "actor_unit_id": "U_KOMMANDOS_A", "payload": {"transport_id": "U_BATTLEWAGON_A"}})
	_check("real EMBARK_UNIT", emb.get("success", false), str(emb.get("error", emb.get("errors", ""))))
	_check("embarked_this_phase written", bool(_flags("U_KOMMANDOS_A").get("embarked_this_phase", false)))
	var dm = load("res://scripts/rules/MoveTypes.gd").get_type("disembark") if ResourceLoader.exists("res://scripts/rules/MoveTypes.gd") else null
	if dm != null:
		_check("18.04: cannot disembark the phase it embarked", not dm.eligible("U_KOMMANDOS_A", GS.state).get("eligible", true))
	PM.transition_to_phase(PHASE_SHOOTING)
	_check("embarked_this_phase cleared when the phase ends", not _flags("U_KOMMANDOS_A").has("embarked_this_phase"))

	# RB-2: wholly within the set-up distance.
	var transport := _unit("U_BATTLEWAGON_A")
	var tm0: Dictionary = transport.models[0]
	var boy: Dictionary = _unit("U_BOYZ_B").models[0].duplicate(true)
	var probe := tm0.duplicate(true)
	probe["position"] = {"x": float(_pos(tm0).x), "y": float(_pos(tm0).y)}
	var dir := Vector2(1, 0)
	var edge_x := 0.0
	# distance along +x where the boy's near edge is 2.9" from the hull
	var lo := 0.0
	var hi := 30.0 * PX
	for _it in range(40):
		var mid := (lo + hi) * 0.5
		var r0 = TMgr.is_position_within_disembark_range(_pos(tm0) + dir * mid, boy, transport, 3.0)
		if float(r0.distance_inches) < 2.9:
			lo = mid
		else:
			hi = mid
	edge_x = lo
	var far = TMgr.is_position_within_disembark_range(_pos(tm0) + dir * edge_x, boy, transport, 3.0)
	_check("near edge 2.9\" but the base reaches past 3\": NOT wholly within", not far.within_range and float(far.farthest_inches) > 3.0, str(far))
	var near = TMgr.is_position_within_disembark_range(_pos(tm0) + dir * (edge_x - 1.6 * PX), boy, transport, 3.0)
	_check("base fully inside 3\": wholly within", near.within_range and float(near.farthest_inches) <= 3.01, str(near))


# ---------------------------------------------------------------------------
# E. Fight On Death offers once selected to fight
# ---------------------------------------------------------------------------
func _section_fod_offers() -> void:
	print("\n-- E. ORKS IS NEVER BEATEN / TOO ARROGANT TO DIE not offered once selected (WH-5 / F3) --")
	_load(ACTIVE)
	var oinb := _sid(1, "orks-is-never-beaten-war-horde")
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_FIGHT)
	var phase = _phase()
	_pass_pile_in(phase)
	var ctx := {"phase": "fight", "attacker_unit_id": "U_CUSTODIAN_GUARD_A", "target_unit_ids": ["U_BOYZ_B"]}
	_check("before the Boyz are selected: ORKS IS NEVER BEATEN offered", oinb in _offer_ids(SM.get_window_offers(1, "enemy_targets_unit_fight", ctx)))
	var sel = phase.execute_action({"type": "SELECT_FIGHTER", "unit_id": "U_BOYZ_B", "player": 1})
	_check("real SELECT_FIGHTER (Boyz)", sel.get("success", false), str(sel.get("error", "")))
	_drain(phase)
	_check("selected to fight this phase -> not offered (the effect could never apply)", not oinb in _offer_ids(SM.get_window_offers(1, "enemy_targets_unit_fight", ctx)))
	_check("validate stays permissive (RAW the stratagem may still be used)", SM.can_use_stratagem(1, oinb, "U_BOYZ_B", {"window_id": "enemy_targets_unit_fight", "attacker_unit_id": "U_CUSTODIAN_GUARD_A", "target_unit_ids": ["U_BOYZ_B"]}).can_use)
	_set_detachment(1, "Bully Boyz")
	var tatd := _sid(1, "too-arrogant-to-die-bully-boyz")
	var nctx := {"phase": "fight", "attacker_unit_id": "U_CUSTODIAN_GUARD_B", "target_unit_ids": ["U_NOBZ_A"]}
	_check("TOO ARROGANT TO DIE offered on unselected Nobz", tatd in _offer_ids(SM.get_window_offers(1, "enemy_targets_unit_fight", nctx)))
	phase._ork11e_selected_to_fight["U_NOBZ_A"] = true
	_check("…not once the Nobz were selected to fight", not tatd in _offer_ids(SM.get_window_offers(1, "enemy_targets_unit_fight", nctx)))


# ---------------------------------------------------------------------------
# F. ARMED TO DA TEEF
# ---------------------------------------------------------------------------
func _section_armed_to_da_teef() -> void:
	print("\n-- F. ARMED TO DA TEEF: any hit roll when riled up (F4) / clear() (F5) --")
	_load(ACTIVE)
	_set_detachment(1, "Bully Boyz")
	var sid := _sid(1, "armed-to-da-teef-bully-boyz")
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_FIGHT)
	var phase = _phase()
	var fctx := {"phase": "fight", "unit_id": "U_MEGANOBZ_A"}
	var e := _offer_entry(SM.get_window_offers(1, "unit_selected_to_fight", fctx), sid, "U_MEGANOBZ_A")
	_check("not riled up: no variant (re-roll 1s only)", not e.is_empty() and e.get("variants", []).is_empty(), str(e))
	_flags("U_MEGANOBZ_A")["waaagh_active"] = true
	_flags("U_MEGANOBZ_A")["effect_lethal_hits_melee"] = true  # a critical-hit payoff for these attacks
	e = _offer_entry(SM.get_window_offers(1, "unit_selected_to_fight", fctx), sid, "U_MEGANOBZ_A")
	var vids: Array = e.get("variants", []).map(func(v): return str(v.get("id", "")))
	_check("riled up + critical-hit weapon: 'non-critical hits too' variant offered", "non_crit" in vids, str(e))
	_flags("U_MEGANOBZ_A").erase("effect_lethal_hits_melee")
	e = _offer_entry(SM.get_window_offers(1, "unit_selected_to_fight", fctx), sid, "U_MEGANOBZ_A")
	var has_payoff: bool = Fight._group_has_crit_hit_payoff("U_MEGANOBZ_A", true)
	_check("no critical-hit payoff for the melee attacks -> no variant", has_payoff or e.get("variants", []).is_empty(), str(e))
	_flags("U_MEGANOBZ_A")["effect_lethal_hits_melee"] = true
	phase.open_stratagem_window(1, "unit_selected_to_fight", fctx, "")
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_fight", "stratagem_id": sid, "target_unit_id": "U_MEGANOBZ_A", "context": {"variant_id": "non_crit"}})
	_check("USE (variant) succeeds", use.get("success", false), str(use.get("error", "")))
	_check("scope 'non_crit' written", str(_flags("U_MEGANOBZ_A").get("effect_reroll_hits", "")) == "non_crit", str(_flags("U_MEGANOBZ_A")))
	SM.on_phase_end(PHASE_FIGHT)
	_check("expires cleanly", not _flags("U_MEGANOBZ_A").has("effect_reroll_hits"))

	# Engine: REROLL_NON_CRIT re-rolls successful non-critical hits too.
	var rng = RE.RNGService.new(5)
	var HM = RE.HitModifier
	_check("REROLL_NON_CRIT: a successful non-critical 4 (3+) is re-rolled", RE.apply_hit_modifiers(4, HM.REROLL_NON_CRIT, rng, 3, 6).rerolled)
	_check("REROLL_NON_CRIT: a critical 6 is kept", not RE.apply_hit_modifiers(6, HM.REROLL_NON_CRIT, rng, 3, 6).rerolled)
	_check("REROLL_FAILED alone keeps a successful 4", not RE.apply_hit_modifiers(4, HM.REROLL_FAILED, rng, 3, 6).rerolled)
	_check("crit threshold honoured (crit on 5+: a 5 is kept)", not RE.apply_hit_modifiers(5, HM.REROLL_NON_CRIT, rng, 3, 5).rerolled)
	var lethal_bits: int = RE._non_crit_hit_reroll_bits({"flags": {"effect_lethal_hits_melee": true}}, "no_such_weapon", {}, true)
	var plain_bits: int = RE._non_crit_hit_reroll_bits({"flags": {}}, "no_such_weapon", {}, true)
	_check("payoff weapon: failed + non-critical re-rolls", (lethal_bits & HM.REROLL_NON_CRIT) != 0 and (lethal_bits & HM.REROLL_FAILED) != 0)
	_check("no payoff: failed hits only (successes kept)", (plain_bits & HM.REROLL_NON_CRIT) == 0 and (plain_bits & HM.REROLL_FAILED) != 0)

	# F5: clear() leaves / restores another source's re-roll.
	_load(ACTIVE)
	_set_detachment(1, "Bully Boyz")
	sid = _sid(1, "armed-to-da-teef-bully-boyz")
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_FIGHT)
	phase = _phase()
	_flags("U_NOBZ_A")["effect_reroll_hits"] = "ones"
	phase.open_stratagem_window(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_NOBZ_A"}, "")
	phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_fight", "stratagem_id": sid, "target_unit_id": "U_NOBZ_A"})
	_check("existing 'ones' + ATDT 'ones': nothing claimed", str(_flags("U_NOBZ_A").get("ork11e_armed_to_da_teef", "x")) == "")
	SM.on_phase_end(PHASE_FIGHT)
	_check("clear() leaves the other source's 'ones' alone", str(_flags("U_NOBZ_A").get("effect_reroll_hits", "")) == "ones", str(_flags("U_NOBZ_A")))
	SM._usage_history = {"1": [], "2": []}
	SM.active_effects = []
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_FIGHT)
	phase = _phase()
	_flags("U_NOBZ_A")["effect_reroll_hits"] = "ones"
	_flags("U_NOBZ_A")["waaagh_active"] = true
	phase.open_stratagem_window(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_NOBZ_A"}, "")
	phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_fight", "stratagem_id": sid, "target_unit_id": "U_NOBZ_A"})
	_check("riled up upgrades 'ones' -> 'all'", str(_flags("U_NOBZ_A").get("effect_reroll_hits", "")) == "all")
	SM.on_phase_end(PHASE_FIGHT)
	_check("clear() restores the other source's 'ones'", str(_flags("U_NOBZ_A").get("effect_reroll_hits", "")) == "ones", str(_flags("U_NOBZ_A")))


# ---------------------------------------------------------------------------
# G. [CLEAVE] vs an Attached unit
# ---------------------------------------------------------------------------
func _section_cleave_attached() -> void:
	print("\n-- G. [CLEAVE] counts the whole Attached unit (WH-2) --")
	_load(ACTIVE)
	# 4 Boyz + the attached Warboss = 5 models (keep the front rank, which is
	# engaged with Custodian Guard A: remove the rear models).
	var bm: Array = _unit("U_BOYZ_B").models
	bm.sort_custom(func(a, b): return float(_pos(a).y) > float(_pos(b).y))
	for i in range(bm.size()):
		if i >= 4:
			bm[i]["alive"] = false
			bm[i]["current_wounds"] = 0
	_check("attached unit alive count = 5 (4 Boyz + Warboss)", RE.attached_unit_alive_model_count("U_BOYZ_B", GS.state) == 5, str(RE.attached_unit_alive_model_count("U_BOYZ_B", GS.state)))
	var wid := _melee_weapon("U_CUSTODIAN_GUARD_A")
	_check("Custodian Guard melee weapon found", wid != "")
	var base_dice := -1
	var mow_dice := -1
	for with_mow in [false, true]:
		var board: Dictionary = GS.create_snapshot()
		board.units.U_CUSTODIAN_GUARD_A.flags["ork11e_mow_em_down"] = with_mow
		RE.set_test_seed(4242)
		var r = RE.resolve_melee_attacks({"type": "FIGHT", "actor_unit_id": "U_CUSTODIAN_GUARD_A",
			"payload": {"assignments": [{"attacker": "U_CUSTODIAN_GUARD_A", "target": "U_BOYZ_B", "weapon": wid}]}}, board, RE.RNGService.new())
		var n := int(_hit_block(r).get("total_attacks", -1))
		if with_mow:
			mow_dice = n
		else:
			base_dice = n
	RE.set_test_seed(-1)
	var cx: int = RE.get_cleave_value(wid)
	var expected_extra := 1  # [CLEAVE 1] (or +1) vs 5 models -> one extra die per 5
	if cx > 0:
		expected_extra = 0  # the weapon already has CLEAVE: both runs add dice; compare the delta of one step
	_check("[CLEAVE] vs 4 Boyz + Warboss adds a die (%d -> %d)" % [base_dice, mow_dice], base_dice > 0 and (mow_dice - base_dice) >= expected_extra and mow_dice > base_dice, "cleave_x=%d" % cx)


# ---------------------------------------------------------------------------
# H. Fight On Death removal attribution
# ---------------------------------------------------------------------------
func _section_fod_attribution() -> void:
	print("\n-- H. Fight On Death removal credited to the destroying attacker (framework:F13) --")
	_load(ACTIVE)
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_FIGHT)
	var phase = _phase()
	# Intercept records the enemy fighter whose attacks destroyed the kept model.
	_flags("U_BOYZ_B")["ork11e_fod_mode"] = "riled_up"
	_flags("U_BOYZ_B")["ork11e_fod_source"] = "ORKS IS NEVER BEATEN"
	_flags("U_BOYZ_B")["waaagh_active"] = true
	phase.active_fighter_id = "U_CUSTODIAN_GUARD_A"
	var kept := false
	for s in range(1, 40):
		RE.set_test_seed(s)
		var ch: Array = [{"op": "set", "path": "units.U_BOYZ_B.models.%d.alive" % (s % 10), "value": false}]
		phase._ork11e_fod_intercept(ch)
		if ch[0].value == true:
			kept = true
			break
	RE.set_test_seed(-1)
	_check("a model was kept by the Fight On Death roll", kept)
	_check("its destroyer recorded", str(phase._ork11e_fod_destroyer.get("U_BOYZ_B", "")) == "U_CUSTODIAN_GUARD_A", str(phase._ork11e_fod_destroyer))
	# The kept models are removed in the Boyz' own activation: the unit dies
	# then, but the events credit Custodian Guard A.
	var boyz: Array = _unit("U_BOYZ_B").models
	for i in range(boyz.size()):
		boyz[i]["alive"] = i < 2
	for m in _unit("U_WARBOSS_A").models:
		m["alive"] = false
	_flags("U_BOYZ_B")["ork11e_fod_pending"] = [0, 1]
	phase._window_events_detect()  # baseline
	phase.active_fighter_id = "U_BOYZ_B"
	phase._ev_action_attacker = "U_BOYZ_B"
	PM.apply_state_changes(phase._ork11e_fod_remove(["U_BOYZ_B"], "has fought"))
	phase._window_events_detect()
	var ud := {}
	var eha := {}
	for entry in phase._ev_deferred:
		if str(entry.get("window_id", "")) == "unit_destroyed" and str(entry.ctx.get("unit_id", "")) == "U_BOYZ_B":
			ud = entry
		if str(entry.get("window_id", "")) == "enemy_unit_has_attacked":
			eha = entry
	_check("unit_destroyed credits Custodian Guard A", str(ud.get("ctx", {}).get("attacker_unit_id", "")) == "U_CUSTODIAN_GUARD_A", str(ud))
	_check("enemy_unit_has_attacked raised for Custodian Guard A", str(eha.get("ctx", {}).get("attacker_unit_id", "")) == "U_CUSTODIAN_GUARD_A" and "U_BOYZ_B" in eha.get("ctx", {}).get("destroyed_unit_ids", []), str(eha))
	phase._ev_deferred.clear()


# ---------------------------------------------------------------------------
# I. secured objectives
# ---------------------------------------------------------------------------
func _section_secured_objective() -> void:
	print("\n-- I. a secured objective only breaks at the END of a phase (DR-1) --")
	_load(ACTIVE)
	MM.check_all_objectives()
	MM.secure_objective("obj_center", 1, "")
	_move_to("U_BOYZ_B", Vector2(22, 12))
	_move_to("U_WARBOSS_A", Vector2(24, 12))
	_move_to("U_CUSTODIAN_GUARD_A", Vector2(22, 42))
	MM.check_all_objectives()
	_check("secured with nobody in range -> P1", int(MM.objective_control_state.get("obj_center", 0)) == 1)
	_move_to("U_CUSTODIAN_GUARD_A", Vector2(22, 31))
	MM.check_all_objectives(false)  # the per-move display refresh
	_check("mid-phase refresh: the enemy is ahead (display)", int(MM.objective_control_state.get("obj_center", 0)) == 2)
	_check("mid-phase refresh: the secured lock holds", MM.is_objective_secured("obj_center").get("secured", false))
	for m in _unit("U_CUSTODIAN_GUARD_A").models:
		m["alive"] = false
	MM.check_all_objectives()  # end of phase
	_check("enemy gone by the end of the phase: still P1's", int(MM.objective_control_state.get("obj_center", 0)) == 1 and MM.is_objective_secured("obj_center").get("secured", false))
	for m in _unit("U_CUSTODIAN_GUARD_A").models:
		m["alive"] = true
	MM.check_all_objectives()
	_check("enemy ahead AT the end of a phase: the lock breaks", int(MM.objective_control_state.get("obj_center", 0)) == 2 and not MM.is_objective_secured("obj_center").get("secured", true))
	var mv_src := FileAccess.get_file_as_string("res://phases/MovementPhase.gd")
	var ch_src := FileAccess.get_file_as_string("res://phases/ChargePhase.gd")
	_check("Movement / Charge per-move refreshes are display-only", not mv_src.contains("call_deferred(\"check_all_objectives\")") and not ch_src.contains("call_deferred(\"check_all_objectives\")")
		and mv_src.contains("call_deferred(\"check_all_objectives\", false)") and ch_src.contains("call_deferred(\"check_all_objectives\", false)"))

	# Real path: in the Movement phase an enemy stands on the secured objective
	# mid-phase; a real move (deferred per-move refresh) leaves the lock; the
	# enemy is gone before END_MOVEMENT -> the end-of-phase check keeps P1.
	_load(ACTIVE)
	_move_to("U_BOYZ_B", Vector2(22, 12))
	_move_to("U_WARBOSS_A", Vector2(24, 12))
	_move_to("U_CUSTODIAN_GUARD_A", Vector2(22, 42))
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_MOVEMENT)
	var phase = _phase()
	_drain(phase)
	MM._sticky_objectives.clear()
	MM.secure_objective("obj_center", 1, "")
	_move_to("U_CUSTODIAN_GUARD_A", Vector2(22, 31))
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_GRETCHIN_D"})
	_drain(phase)
	phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_GRETCHIN_D", "payload": {}})
	_drain(phase)
	await process_frame
	await process_frame
	_check("after a real CONFIRM_UNIT_MOVE (deferred refresh): lock still held", MM.is_objective_secured("obj_center").get("secured", false))
	for m in _unit("U_CUSTODIAN_GUARD_A").models:
		m["alive"] = false
	phase.execute_action({"type": "END_MOVEMENT", "player": 1})
	_drain(phase)
	await process_frame
	_check("END_MOVEMENT (end-of-phase determination): obj_center still P1's", int(MM.objective_control_state.get("obj_center", 0)) == 1 and MM.is_objective_secured("obj_center").get("secured", false), str(MM.objective_control_state.get("obj_center")))


# ---------------------------------------------------------------------------
# J. Command Re-roll vs 15.01
# ---------------------------------------------------------------------------
func _section_command_reroll_15_01() -> void:
	print("\n-- J. Command Re-roll not offered on a unit already targeted this phase (EWG-1) --")
	_load(ACTIVE)
	_set_detachment(1, "Green Tide")
	var sid := _sid(1, "ere-we-go-green-tide")
	_move_to("U_CUSTODIAN_GUARD_A", Vector2(22, 39))
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_MOVEMENT)
	var phase = _phase()
	_drain(phase)
	var m_in := float(phase.get_unit_movement(_unit("U_BOYZ_B")))
	RE.set_test_seed(9090)
	phase.execute_action({"type": "BEGIN_ADVANCE", "actor_unit_id": "U_BOYZ_B"})
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_move", "stratagem_id": sid, "target_unit_id": "U_BOYZ_B"})
	RE.set_test_seed(-1)
	_check("'ERE WE GO used on the advancing Boyz", use.get("success", false), str(use.get("error", "")))
	_check("no Command Re-roll prompt for its advance roll", not phase._awaiting_reroll_decision)
	var mvd: Dictionary = phase.active_moves.get("U_BOYZ_B", {})
	var adv := int(mvd.get("advance_roll", -1))
	_check("the advance resolved with the +2 (cap = M + roll)", adv >= 3 and absf(float(mvd.get("move_cap_inches", -1)) - (m_in + adv)) < 0.01, str(mvd.get("move_cap_inches")))
	var chk = SM.is_command_reroll_available(1, "U_BOYZ_B")
	_check("availability for that unit: refused with the 15.01 reason", not chk.available and "15.01" in str(chk.reason), str(chk))
	_check("availability without a unit: still available", SM.is_command_reroll_available(1).available)


# ---------------------------------------------------------------------------
# K. AI KEEP IT RUNNIN' and objectives
# ---------------------------------------------------------------------------
func _section_kir_ai() -> void:
	print("\n-- K. AI KEEP IT RUNNIN' keeps objective holders on the table (KIR-AI) --")
	_load(ACTIVE)
	_set_detachment(1, "Blitz Brigade")
	MM.check_all_objectives()
	var kir = SM.get_stratagem(_sid(1, "keep-it-runnin-blitz-brigade"))
	_check("setup: P1 controls obj_center (Boyz on it)", int(MM.objective_control_state.get("obj_center", 0)) == 1)
	_check("Boyz holding obj_center (enemy within 12\"): AI keeps them (score 0)", Fight.ai_score(kir, 1, "U_BOYZ_B", "fight_phase_end", {}) == 0.0)
	_check("exposed unit off the objectives, enemy within 12\": worth it", Fight.ai_score(kir, 1, "U_NOBZ_A", "fight_phase_end", {}) >= 2.0)


# ---------------------------------------------------------------------------
# L. Deadly Demise outside the Shooting / Fight phases
# ---------------------------------------------------------------------------
func _section_deadly_demise_other_phases() -> void:
	print("\n-- L. Deadly Demise in the Movement / Charge / Command phases (r5:F13) --")
	_load(REACTIVE)
	_set_detachment(2, "Flyboyz")
	var fh := _sid(2, "flyin-headbutt-flyboyz")
	_move_to("U_DAKKAJET_A", Vector2(41, 35))
	_move_to("U_CUSTODIAN_GUARD_F", Vector2(41, 26))
	# Custodian Guard F reduced to one model with 1 wound and given Deadly Demise.
	var cgf: Dictionary = _unit("U_CUSTODIAN_GUARD_F")
	for i in range(cgf.models.size()):
		cgf.models[i]["alive"] = i == 0
		cgf.models[i]["current_wounds"] = 1 if i == 0 else 0
	cgf.meta["abilities"] = cgf.meta.get("abilities", []) + [{"name": "Deadly Demise 1"}]
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_MOVEMENT)
	var phase = _phase()
	_drain(phase)
	_check("MovementPhase resolves Deadly Demise generically", not phase._phase_resolves_deadly_demise() and phase.has_method("_resolve_deadly_demise_if_applicable"))
	phase._window_events_detect()  # baseline
	PM.apply_state_changes([{"op": "set", "path": "units.U_DAKKAJET_A.models.0.alive", "value": false},
		{"op": "set", "path": "units.U_DAKKAJET_A.models.0.current_wounds", "value": 0}])
	phase._window_events_flush({})
	var w: Dictionary = phase.get_pending_stratagem_window() if phase.has_pending_stratagem_window() else {}
	_check("Dakkajet destroyed in the Movement phase: unit_destroyed window for P2", str(w.get("window_id", "")) == "unit_destroyed" and int(w.get("player", 0)) == 2, str(w.get("window_id", "")))
	_check("…and its Deadly Demise is held until the window closes", phase._ev_dd_held.has("U_DAKKAJET_A"))
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 2, "window_id": "unit_destroyed", "stratagem_id": fh, "target_unit_id": "U_DAKKAJET_A", "context": {"secondary_id": "U_CUSTODIAN_GUARD_F"}})
	_check("FLYIN' HEADBUTT used", use.get("success", false), str(use.get("error", "")))
	var mw := int(_flags("U_DAKKAJET_A").get("ork11e_flyin_headbutt", {}).get("mortal_wounds", 0))
	if mw > 0:
		_check("Custodian Guard F destroyed by the headbutt's mortal wounds", not cgf.models[0].get("alive", true))
		_check("the destroyed enemy's Deadly Demise was resolved in the Movement phase", "U_CUSTODIAN_GUARD_F" in phase._ev_dd_released, str(phase._ev_dd_released))
	else:
		_check("(no 4+ in 8D6 — rerun) ", false, "mortal_wounds=0")
	_check("the aircraft's own Deadly Demise skipped (FLYIN' HEADBUTT removes it)", "U_DAKKAJET_A" in phase._ev_dd_released and not root.get_node("UnitAbilityManager").has_deadly_demise("U_DAKKAJET_A"))
	# The generic resolver deals the mortal wounds when it triggers (D6 = 6).
	_load(REACTIVE)
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_CHARGE)
	var cphase = _phase()
	_move_to("U_TRUKK_A", Vector2(20, 30))
	_move_to("U_CUSTODIAN_GUARD_D", Vector2(20, 34))
	var trukk: Dictionary = _unit("U_TRUKK_A")
	trukk.meta["abilities"] = trukk.meta.get("abilities", []) + [{"name": "Deadly Demise D3"}]
	for m in trukk.models:
		m["alive"] = false
	var wounds_before := 0
	for m in _unit("U_CUSTODIAN_GUARD_D").models:
		wounds_before += int(m.get("current_wounds", m.get("wounds", 1)))
	var triggered := false
	for s in range(1, 60):
		RE.set_test_seed(s)
		var probe = RE.resolve_deadly_demise("U_TRUKK_A", "D3", GS.create_snapshot())
		if probe.get("triggered", false):
			RE.set_test_seed(s)
			cphase._resolve_deadly_demise_if_applicable("U_TRUKK_A")
			triggered = true
			break
	RE.set_test_seed(-1)
	var wounds_after := 0
	for m in _unit("U_CUSTODIAN_GUARD_D").models:
		if m.get("alive", true):
			wounds_after += int(m.get("current_wounds", m.get("wounds", 1)))
	_check("Charge phase: a triggered Deadly Demise wounds the unit within 6\" (%d -> %d)" % [wounds_before, wounds_after], triggered and wounds_after < wounds_before)


# ---------------------------------------------------------------------------
# M. gated prints
# ---------------------------------------------------------------------------
func _section_gated_prints() -> void:
	print("\n-- M. FightPhase has no ungated print() (RG-F3) --")
	var rx = RegEx.new()
	rx.compile("(?m)^[ \\t]*print\\(")
	for p in ["res://phases/FightPhase.gd", "res://phases/CommandPhase.gd", "res://phases/ScoringPhase.gd", "res://phases/BasePhase.gd", "res://phases/ShootingPhase.gd"]:
		var n := rx.search_all(FileAccess.get_file_as_string(p)).size()
		_check("%s: 0 ungated print()" % p.get_file(), n == 0, "%d remaining" % n)
