extends SceneTree

# 13.09 HIDDEN — the shared shot record (scripts/rules/HiddenShotRecord.gd):
# "That model's unit did not make one or more ranged attacks during this turn
# or during the previous turn."
#
# Regressions covered:
#   ▪ FIRE OVERWATCH (15.08) shoots "using snap shooting" and SNAP SHOOTING
#     (15.09) is "Your unit shoots as described in Making Attacks (04)" — ranged
#     attacks — but only Shooting-phase completions wrote flags.last_shot_idx,
#     so a unit that overwatched stayed hidden in the opponent's Shooting phase
#     and in its own next turn. The out-of-phase "your unit shoots" follow-ups
#     (RAPID REACTIONS, Ork forced shooting) did not stamp either, nor did two
#     Shooting-phase completions that close an activation after skipping
#     weapons whose target was destroyed.
#   ▪ 19.01: an Attached unit is ONE unit — the stamp went to the bodyguard
#     only, so the attached leader kept no record.
#   ▪ Shadow Masters' waiver erased the previous turn's attacks too; it now
#     drops only THIS turn's (prev_shot_idx), and the unit still cannot go to
#     ground (13.11.01 Designer's Note, last_ranged_attack_idx).
#
#   A. HiddenShotRecord on a hand-built Attached unit (both link directions)
#   B. ShootingPhase completions: _hidden_shot_stamp (every component), the
#      miss-path auto-complete and the skipped-weapons completion
#   C. REAL FIRE OVERWATCH: END_MOVEMENT -> movement_phase_end window ->
#      USE_WINDOW_STRATAGEM fire_overwatch_11e (ork11e_orks_reactive fixture)
#   D. RAPID REACTIONS (MovementPhase) and Ork forced shooting (ShootingPhase)
#      follow-up executors
#
# Usage: godot --headless --path . -s tests/test_hidden_shot_record_11e.gd

const FIXTURE := "res://tests/saves/ork11e_orks_reactive.w40ksave"
const PX := 40.0
const PHASE_MOVEMENT := 7
const PHASE_SHOOTING := 8

var passed := 0
var failed := 0
var _completed := false  # set by the last line of _run(): an aborted run (script error) counts as a failure
var GS = null
var TM = null
var PM = null
var SM = null
var HSR = null

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
	if not _completed:
		failed += 1
		print("  FAIL: the run aborted before its last check (see the SCRIPT ERROR above)")
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _rect(cx: float, cy: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(cx - w / 2, cy - h / 2), Vector2(cx + w / 2, cy - h / 2),
		Vector2(cx + w / 2, cy + h / 2), Vector2(cx - w / 2, cy + h / 2)])

func _rect_in(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0 * PX, y0 * PX), Vector2(x1 * PX, y0 * PX),
		Vector2(x1 * PX, y1 * PX), Vector2(x0 * PX, y1 * PX)])

func _set_turn(first: int, rnd: int, active: int) -> void:
	GS.state["meta"]["first_turn_player"] = first
	GS.state["meta"]["battle_round"] = rnd
	GS.state["meta"]["active_player"] = active

func _model(id: String, x: float, y: float) -> Dictionary:
	return {"id": id, "alive": true, "base_mm": 32, "base_type": "circular",
		"position": {"x": x, "y": y}, "wounds": 1, "current_wounds": 1}

func _unit(id: String, owner: int, kws: Array, models: Array) -> Dictionary:
	return {"id": id, "owner": owner, "status": 2, "flags": {},
		"meta": {"name": id, "keywords": kws, "stats": {"move": 6}}, "models": models}

func _hidden(uid: String) -> bool:
	var u: Dictionary = GS.state["units"][uid]
	return TM.is_model_hidden(u["models"][0], u)

func _flag(uid: String, f: String, dflt = null):
	return GS.state["units"][uid].get("flags", {}).get(f, dflt)

func _paths(diffs: Array) -> Array:
	var out: Array = []
	for d in diffs:
		out.append(str(d.get("path", "")))
	return out

# --- A ------------------------------------------------------------------------

func _attached_state() -> void:
	GS.initialize_default_state()
	GameConstants.edition = 11
	var units := {
		"U_BG": _unit("U_BG", 1, ["INFANTRY"], [_model("m1", 400, 400), _model("m2", 430, 400)]),
		"U_LDR": _unit("U_LDR", 1, ["INFANTRY", "CHARACTER"], [_model("l1", 400, 430)]),
		"U_LDR2": _unit("U_LDR2", 1, ["INFANTRY", "CHARACTER"], [_model("k1", 430, 430)]),
		"U_SOLO": _unit("U_SOLO", 1, ["INFANTRY"], [_model("s1", 460, 400)]),
	}
	units["U_BG"]["attachment_data"] = {"attached_characters": ["U_LDR"]}
	units["U_LDR"]["attached_to"] = "U_BG"
	units["U_LDR2"]["attached_to"] = "U_BG"  # linked ONLY by its own back-pointer
	GS.state["units"] = units
	TM.terrain_features = [{"id": "ruin", "type": "ruins", "polygon": _rect(420, 420, 300, 300), "height_category": "tall"}]

func _section_record() -> void:
	print("\n-- A. HiddenShotRecord: Attached-unit stamp, waiver, Gone to Ground --")
	_attached_state()
	_set_turn(1, 2, 1)  # index 4
	_check("everything in the ruin starts hidden", _hidden("U_BG") and _hidden("U_LDR") and _hidden("U_LDR2") and _hidden("U_SOLO"))
	var d: Array = HSR.stamp_diffs("U_BG")
	var p := _paths(d)
	for uid in ["U_BG", "U_LDR", "U_LDR2"]:
		_check("stamp from the bodyguard reaches %s (last/prev/attack)" % uid,
			("units.%s.flags.last_shot_idx" % uid) in p and ("units.%s.flags.prev_shot_idx" % uid) in p
			and ("units.%s.flags.last_ranged_attack_idx" % uid) in p, str(p))
	_check("... and not the unrelated unit", not "units.U_SOLO.flags.last_shot_idx" in p)
	var from_leader := _paths(HSR.stamp_diffs("U_LDR2"))
	_check("stamping from an attached leader id covers the same Attached unit", "units.U_BG.flags.last_shot_idx" in from_leader and "units.U_LDR.flags.last_shot_idx" in from_leader)
	PM.apply_state_changes(d)
	_check("after the stamp no component is hidden (this turn)", not _hidden("U_BG") and not _hidden("U_LDR") and not _hidden("U_LDR2"))
	_check("the unrelated unit is still hidden", _hidden("U_SOLO"))
	_set_turn(1, 2, 2)
	_check("next turn: still not hidden", not _hidden("U_BG") and not _hidden("U_LDR"))
	_set_turn(1, 3, 1)
	_check("two turns later: hidden again", _hidden("U_BG") and _hidden("U_LDR") and _hidden("U_LDR2"))

	print("\n   waiver (Shadow Masters semantics)")
	_attached_state()
	_set_turn(1, 2, 1)
	PM.apply_state_changes(HSR.stamp_diffs("U_BG"))
	_check("same-turn second stamp keeps prev_shot_idx (no record before = %d)" % HSR.NEVER,
		int(_flag("U_BG", "prev_shot_idx", 0)) == HSR.NEVER)
	PM.apply_state_changes(HSR.stamp_diffs("U_BG"))
	_check("... still %d after a second stamp in the same turn" % HSR.NEVER, int(_flag("U_BG", "prev_shot_idx", 0)) == HSR.NEVER)
	PM.apply_state_changes(HSR.waive_this_turn_diffs("U_LDR"))
	_check("waived: every component hidden again this turn", _hidden("U_BG") and _hidden("U_LDR") and _hidden("U_LDR2"))
	_check("waived: but the unit cannot go to ground this turn (13.11.01)", not TM.can_go_to_ground(GS.state["units"]["U_BG"]))
	_set_turn(1, 2, 2)
	_check("waived: hidden next turn, still cannot go to ground", _hidden("U_BG") and not TM.can_go_to_ground(GS.state["units"]["U_LDR"]))
	_set_turn(1, 3, 1)
	_check("two turns later it can go to ground again", TM.can_go_to_ground(GS.state["units"]["U_BG"]))

	_attached_state()
	_set_turn(1, 1, 2)  # index 3: the unit FIRE OVERWATCHes in the opponent's turn
	PM.apply_state_changes(HSR.stamp_diffs("U_BG"))
	_set_turn(1, 2, 1)  # index 4: it shoots in its own turn, then waives THOSE attacks
	PM.apply_state_changes(HSR.stamp_diffs("U_BG"))
	_check("own-turn stamp remembers the previous turn's record (prev = 3)", int(_flag("U_BG", "prev_shot_idx", 0)) == 3)
	PM.apply_state_changes(HSR.waive_this_turn_diffs("U_BG"))
	_check("waiver keeps the previous turn's overwatch: last_shot_idx back to 3", int(_flag("U_BG", "last_shot_idx", 0)) == 3)
	_check("... so the unit is NOT hidden this turn (it attacked in the previous turn)", not _hidden("U_BG"))
	_set_turn(1, 2, 2)
	_check("... and hidden in the next turn", _hidden("U_BG"))

	print("\n   Gone to Ground after a waiver")
	_attached_state()
	_set_turn(1, 2, 1)
	var hidden_m: Dictionary = GS.state["units"]["U_SOLO"]["models"][0]
	var obs := _model("o1", 460 + 14 * PX, 400)
	TM.terrain_features.append({"id": "dense_strip", "type": "ruins", "polygon": _rect(460 + 7 * PX, 400, 20, 60), "height_category": "tall"})
	_check("no shots: Gone to Ground applies (12\")", TM.detection_range_inches_for(hidden_m, GS.state["units"]["U_SOLO"], obs) == 12.0)
	PM.apply_state_changes(HSR.stamp_diffs("U_SOLO"))
	PM.apply_state_changes(HSR.waive_this_turn_diffs("U_SOLO"))
	_check("waived shot: hidden, but detection stays 15\" (cannot go to ground)",
		_hidden("U_SOLO") and TM.detection_range_inches_for(hidden_m, GS.state["units"]["U_SOLO"], obs) == 15.0)
	_check("waived shot: visible at ~12.7\" (would be hidden at 12\")", TM.hidden_model_visible_to(hidden_m, GS.state["units"]["U_SOLO"], obs))

# --- B ------------------------------------------------------------------------

func _shooting_phase() -> Node:
	GS.state["meta"]["phase"] = PHASE_SHOOTING
	var phase = load("res://phases/ShootingPhase.gd").new()
	root.add_child(phase)
	phase.game_state_snapshot = GS.create_snapshot()
	return phase

func _free(phase: Node) -> void:
	root.remove_child(phase)
	phase.free()

func _stamp_in(changes: Array, uid: String) -> bool:
	return ("units.%s.flags.last_shot_idx" % uid) in _paths(changes)

func _section_shooting_phase() -> void:
	print("\n-- B. Shooting-phase completions stamp every component --")
	_attached_state()
	_set_turn(1, 2, 1)
	var units: Dictionary = GS.state["units"]
	units["U_FOE_A"] = _unit("U_FOE_A", 2, ["INFANTRY"], [_model("a1", 1400, 400)])
	units["U_FOE_B"] = _unit("U_FOE_B", 2, ["INFANTRY"], [_model("b1", 1400, 600)])
	units["U_FOE_B"]["models"][0]["alive"] = false  # destroyed by an earlier weapon
	var phase := _shooting_phase()
	var d: Array = phase._hidden_shot_stamp("U_BG")
	_check("_hidden_shot_stamp returns one stamp per component", _stamp_in(d, "U_BG") and _stamp_in(d, "U_LDR") and _stamp_in(d, "U_LDR2"), str(_paths(d)))
	# Miss-path auto-complete: weapon 1 (at A) misses, weapon 2's target B is
	# already destroyed -> the activation closes at once.
	phase.active_shooter_id = "U_BG"
	phase.resolution_state = {"mode": "sequential", "current_index": 0, "completed_weapons": [],
		"weapon_order": [{"weapon_id": "w_gun_1", "target_unit_id": "U_FOE_A", "model_ids": ["m1"]},
			{"weapon_id": "w_gun_2", "target_unit_id": "U_FOE_B", "model_ids": ["m2"]}]}
	var r: Dictionary = phase._finish_weapon_resolution(phase.resolution_state.weapon_order[0], "w_gun_1", 0,
		[{"context": "to_hit", "rolls_raw": [1, 2], "successes": 0}], {"successes": 0, "total": 2}, {}, "U_FOE_A", [], "", [])
	var ch: Array = r.get("changes", [])
	_check("miss-path auto-complete closes the activation (has_shot)", "units.U_BG.flags.has_shot" in _paths(ch), str(_paths(ch)))
	_check("... and stamps the shot record of the bodyguard and both leaders", _stamp_in(ch, "U_BG") and _stamp_in(ch, "U_LDR") and _stamp_in(ch, "U_LDR2"), str(_paths(ch)))
	# Skipped-weapons completion in _resolve_next_weapon.
	phase.active_shooter_id = "U_BG"
	phase.resolution_state = {"mode": "sequential", "current_index": 1,
		"completed_weapons": [{"weapon_id": "w_gun_1", "target_unit_id": "U_FOE_A", "hits": 1, "total_attacks": 2}],
		"weapon_order": [{"weapon_id": "w_gun_1", "target_unit_id": "U_FOE_A", "model_ids": ["m1"]},
			{"weapon_id": "w_gun_2", "target_unit_id": "U_FOE_B", "model_ids": ["m2"]}]}
	var r2: Dictionary = phase._resolve_next_weapon()
	var ch2: Array = r2.get("changes", [])
	_check("skipped-weapons completion after a fired weapon stamps the record", _stamp_in(ch2, "U_BG") and _stamp_in(ch2, "U_LDR"), str(_paths(ch2)))
	phase.active_shooter_id = "U_BG"
	phase.resolution_state = {"mode": "sequential", "current_index": 0, "completed_weapons": [],
		"weapon_order": [{"weapon_id": "w_gun_2", "target_unit_id": "U_FOE_B", "model_ids": ["m2"]}]}
	var r3: Dictionary = phase._resolve_next_weapon()
	var ch3: Array = r3.get("changes", [])
	_check("every weapon skipped (nothing fired): has_shot but NO stamp",
		"units.U_BG.flags.has_shot" in _paths(ch3) and not _stamp_in(ch3, "U_BG"), str(_paths(ch3)))
	_free(phase)

# --- C ------------------------------------------------------------------------

func _load_fixture(keep: Array) -> bool:
	var slm = root.get_node("SaveLoadManager")
	var ok: bool = slm.load_game_from_file_path(FIXTURE)
	GameConstants.edition = 11
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
	TM.terrain_features = []
	SM._usage_history = {"1": [], "2": []}
	var mm = root.get_node("MissionManager")
	mm.objective_control_state = {}
	mm.objective_contested_state = {}
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	root.get_node("SettingsService").auto_allocate_wounds = true
	return ok

func _place(uid: String, x_in: float, y_in: float, step: float = 1.8) -> void:
	var i := 0
	for m in GS.state.units[uid].models:
		if m.get("alive", true):
			m["position"] = {"x": (x_in + i * step) * PX, "y": y_in * PX}
			i += 1

func _first_alive(uid: String) -> Dictionary:
	for m in GS.state.units[uid].models:
		if m.get("alive", true):
			return m
	return {}

func _any_hidden(uid: String) -> bool:
	var u: Dictionary = GS.state.units[uid]
	for m in u.models:
		if m.get("alive", true) and TM.is_model_hidden(m, u):
			return true
	return false

func _all_hidden(uid: String) -> bool:
	var u: Dictionary = GS.state.units[uid]
	for m in u.models:
		if m.get("alive", true) and not TM.is_model_hidden(m, u):
			return false
	return true

func _section_fire_overwatch() -> void:
	print("\n-- C. REAL FIRE OVERWATCH (15.08 snap shooting) stamps the overwatching unit --")
	if not _load_fixture(["U_CUSTODIAN_GUARD_A", "U_CUSTODIAN_GUARD_B", "U_GRETCHIN_C"]):
		_check("fixture loaded", false)
		return
	_place("U_CUSTODIAN_GUARD_A", 8.0, 20.0)
	_place("U_CUSTODIAN_GUARD_B", 30.0, 6.0)
	_place("U_GRETCHIN_C", 6.0, 30.0, 1.4)
	TM.terrain_features = [{"id": "fo_ruin", "type": "ruins", "height_category": "tall",
		"polygon": _rect_in(3.0, 27.5, 24.0, 32.5), "position": Vector2(13.5 * PX, 30.0 * PX),
		"size": Vector2(21.0 * PX, 5.0 * PX), "rotation": 0.0,
		"can_move_through": {"INFANTRY": true, "VEHICLE": false, "MONSTER": false}}]
	GS.state.units["U_GRETCHIN_C"]["flags"] = {}
	_check("before: the Gretchin in the ruin are hidden", _all_hidden("U_GRETCHIN_C"))
	var g_m := _first_alive("U_GRETCHIN_C")
	var far_obs := _first_alive("U_CUSTODIAN_GUARD_B")
	_check("before: a P1 observer beyond 15\" cannot see them",
		not TM.hidden_model_visible_to(g_m, GS.state.units["U_GRETCHIN_C"], far_obs))
	var turn_idx: int = int(GS.get_player_turn_index())
	PM.transition_to_phase(PHASE_MOVEMENT)
	var phase = PM.get_current_phase_instance()
	var guard := 0
	while phase != null and phase.has_pending_stratagem_window() and guard < 6:
		var w = phase.get_pending_stratagem_window()
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.player), "window_id": str(w.window_id)})
		guard += 1
	phase.execute_action({"type": "END_MOVEMENT", "player": 1})
	guard = 0
	while phase.has_pending_stratagem_window() and int(phase.get_pending_stratagem_window().player) == 1 and guard < 4:
		var w2 = phase.get_pending_stratagem_window()
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 1, "window_id": str(w2.window_id)})
		guard += 1
	var res: Dictionary = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 2, "window_id": "movement_phase_end",
		"stratagem_id": "fire_overwatch_11e", "target_unit_id": "U_GRETCHIN_C", "context": {"secondary_id": "U_CUSTODIAN_GUARD_A"}})
	_check("FIRE OVERWATCH resolved (snap shooting)", res.get("success", false) and res.get("fire_overwatch_used", false), str(res.get("error", "")))
	var hit_dice := 0
	for db in res.get("dice", []):
		if str(db.get("context", "")) == "to_hit":
			hit_dice += int(db.get("rolls_raw", db.get("rolls", [])).size())
	_check("the Gretchin made ranged attacks (%d hit dice rolled)" % hit_dice, hit_dice > 0)
	_check("the result carries the 13.09 stamp", "units.U_GRETCHIN_C.flags.last_shot_idx" in _paths(res.get("changes", [])), str(_paths(res.get("changes", []))))
	_check("stamp = this turn's index (%d)" % turn_idx, int(_flag("U_GRETCHIN_C", "last_shot_idx", -1)) == turn_idx,
		str(GS.state.units["U_GRETCHIN_C"].get("flags", {})))
	_check("same turn (opponent's Shooting phase): the Gretchin are NOT hidden", not _any_hidden("U_GRETCHIN_C"))
	g_m = _first_alive("U_GRETCHIN_C")
	_check("... so the far P1 observer can see them now",
		TM.hidden_model_visible_to(g_m, GS.state.units["U_GRETCHIN_C"], far_obs))
	# The overwatch happened in Player 1's turn (index T). The Gretchin's own
	# next turn is T+1: Player 2 in the same round when Player 1 went first,
	# else Player 2 in the next round. T+2 is Player 1's next turn.
	var r0 := int(GS.state.meta["battle_round"])
	var p1_first: bool = int(GS.get_first_turn_player()) == 1
	GS.state.meta["active_player"] = 2
	GS.state.meta["battle_round"] = r0 if p1_first else r0 + 1
	_check("their own next turn (index %d): still not hidden" % (turn_idx + 1),
		int(GS.get_player_turn_index()) == turn_idx + 1 and not _any_hidden("U_GRETCHIN_C"), "index=%d" % int(GS.get_player_turn_index()))
	GS.state.meta["active_player"] = 1
	GS.state.meta["battle_round"] = r0 + 1
	_check("two turns later (index %d): hidden again" % (turn_idx + 2),
		int(GS.get_player_turn_index()) == turn_idx + 2 and _all_hidden("U_GRETCHIN_C"), "index=%d" % int(GS.get_player_turn_index()))
	GS.state.meta["battle_round"] = r0
	GS.state.meta["active_player"] = 1

# --- D ------------------------------------------------------------------------

func _section_followups() -> void:
	print("\n-- D. out-of-phase 'your unit shoots' follow-ups stamp too --")
	if not _load_fixture(["U_CUSTODIAN_GUARD_A", "U_GRETCHIN_C", "U_BOYZ_B"]):
		_check("fixture loaded", false)
		return
	_place("U_CUSTODIAN_GUARD_A", 8.0, 20.0)
	_place("U_GRETCHIN_C", 8.0, 26.0, 1.4)
	_place("U_BOYZ_B", 30.0, 26.0, 1.4)
	for uid in GS.state.units:
		GS.state.units[uid]["flags"] = {}
	var idx: int = int(GS.get_player_turn_index())
	GS.state.meta["phase"] = PHASE_MOVEMENT
	var mp = load("res://phases/MovementPhase.gd").new()
	root.add_child(mp)
	mp.game_state_snapshot = GS.create_snapshot()
	mp._cus11e_followup_shoot(1, {"unit_id": "U_CUSTODIAN_GUARD_A", "forced_target_id": "U_GRETCHIN_C", "source": "RAPID REACTIONS"})
	root.remove_child(mp)
	mp.free()
	_check("RAPID REACTIONS (normal shooting) stamps the shooter's record (turn %d)" % idx,
		int(_flag("U_CUSTODIAN_GUARD_A", "last_shot_idx", -1)) == idx, str(GS.state.units["U_CUSTODIAN_GUARD_A"].get("flags", {})))
	var sp := _shooting_phase()
	sp._ork11e_forced_shoot(2, {"unit_id": "U_GRETCHIN_C", "forced_target_id": "U_CUSTODIAN_GUARD_A", "source": "TEST FORCED SHOOT"})
	_free(sp)
	_check("Ork forced shooting stamps the forced shooter's record (turn %d)" % idx,
		int(_flag("U_GRETCHIN_C", "last_shot_idx", -1)) == idx, str(GS.state.units["U_GRETCHIN_C"].get("flags", {})))
	_check("a unit that did not shoot has no record", _flag("U_BOYZ_B", "last_shot_idx", null) == null)

func _run() -> void:
	print("\n=== test_hidden_shot_record_11e ===")
	GS = root.get_node("GameState")
	TM = root.get_node("TerrainManager")
	PM = root.get_node("PhaseManager")
	SM = root.get_node("StratagemManager")
	HSR = load("res://scripts/rules/HiddenShotRecord.gd")
	var prev_terrain = TM.terrain_features.duplicate(true)
	_section_record()
	_section_shooting_phase()
	_section_fire_overwatch()
	_section_followups()
	TM.terrain_features = prev_terrain
	_completed = true
