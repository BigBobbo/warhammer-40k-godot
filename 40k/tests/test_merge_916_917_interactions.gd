extends SceneTree

# Regression net for the interactions between PR #916 (core-rules fixes:
# mandatory fights 12.04, p.74 pass, Fight-step multiplayer, turn timer) and
# PR #917 (Codex: Orks 11e stratagem windows, Fight On Death, RV-2 host phase
# delegation), found when main (#917) was merged into #916:
#
#   A. FC-2   Fight On Death models are removed when the unit's activation
#             ends with SKIP_UNIT (it has fought — #916 stamps has_fought).
#   B. MPGM-4 A stale END_FIGHT / END_MOVEMENT / END_COMMAND that reaches
#             GameManager after its phase is over is a no-op — it no longer
#             completes whatever phase is current (Scoring without
#             END_SCORING, no turn switch).
#   C. MPGM-3 Online, END_FIGHT during the Pile In / Consolidate steps only
#             ends the SENDER's own half (the waiting player's button cannot
#             end the opponent's half); hot-seat stays unscoped.
#   D. MPGM-1 / MPGM-2 / FC-3  The AFK turn timer charges the player the
#             game is actually waiting on: a pending stratagem window's
#             decider, the active fighter's owner mid-activation, the Pile In
#             half owner — and a timeout with a pending window auto-DECLINES
#             it instead of submitting a refused END_* action.
#   E. MPGM-6 A multiplayer client closes its Consolidate step when the
#             host's result opens the fight_phase_end window.
#   F. SHOOT-2 Computer-allocated saves (#916 P1-3) use the 05.03 GROUP
#             order the casualty preference implies, within the 05.03
#             constraints (CasualtyPreference.group_order_for).
#
# Usage: godot --headless --path . -s tests/test_merge_916_917_interactions.gd

# OrkCodexFight.FLAG_FOD_PENDING / FLAG_FOD_SOURCE (the class is not a global
# in a -s script).
const FOD_PENDING := "ork11e_fod_pending"
const FOD_SOURCE := "ork11e_fod_source"
# GameStateData.Phase values — referencing GameStateData in a -s script compiles
# GameState.gd before the autoloads exist (noise in the log).
const PH_COMMAND := 6
const PH_MOVEMENT := 7
const PH_FIGHT := 10
const PH_SCORING := 11

var passed := 0
var failed := 0
var _game_over: Array = []

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	create_timer(0.1).timeout.connect(_run_tests)

# 40px = 1"; 25mm base radius ~19.7px.
func _unit(id: String, owner: int, x: float, y: float, n_models: int = 1, flags: Dictionary = {}) -> Dictionary:
	var models: Array = []
	for i in range(n_models):
		models.append({"id": "%s_m%d" % [id, i], "alive": true, "wounds": 2, "current_wounds": 2,
			"base_mm": 25, "base_type": "circular", "position": {"x": x, "y": y + i * 45.0}})
	return {"id": id, "owner": owner, "status": 2, "flags": flags,
		"meta": {"name": id, "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 2, "toughness": 4, "save": 7, "objective_control": 1}, "weapons": []},
		"models": models}

func _fight_phase(gs, pm, units: Dictionary, end_pile_in: bool = true):
	gs.state["units"] = units
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = PH_FIGHT
	pm.transition_to_phase(PH_FIGHT)
	var fp = pm.get_current_phase_instance()
	if end_pile_in:
		for _i in [1, 2]:
			if int(fp.pile_in_step_11e) == int(fp.PileInStep11e.ACTIVE):
				fp.execute_action({"type": "END_PILE_IN", "player": int(fp.piling_in_player_11e)})
	return fp

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_merge_916_917_interactions ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var gm = root.get_node_or_null("GameManager")
	var nm = root.get_node_or_null("NetworkManager")
	if gs == null or pm == null or gm == null or nm == null:
		_check("autoloads", false); _finish(); return
	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	nm.game_over.connect(func(w, why): _game_over.append([w, why]))

	_section_a_fod_skip(gs, pm)
	_section_b_stale_end_phase(gs, pm, gm)
	_section_c_half_scoped(gs, pm, nm)
	_section_d_afk_timer(gs, pm, nm)
	_section_e_client_consolidation(gs, pm, nm)
	_section_f_group_order()

	nm.stop_turn_timer()
	nm.network_mode = nm.NetworkMode.OFFLINE
	pm.game_ended = false
	gs.state = prev_state
	GameConstants.edition = prev_edition
	_finish()

# ---------------------------------------------------------------------------
func _section_a_fod_skip(gs, pm) -> void:
	print("\n-- A. FC-2: SKIP_UNIT removes the models Fight On Death kept --")
	# U_ORK (P1, 2 models) engaged with U_PROS (P2). Model 1 was destroyed and
	# kept on the battlefield by ORKS IS NEVER BEATEN (alive, 0 wounds).
	var ork := _unit("U_ORK", 1, 500, 500, 2, {
		FOD_PENDING: [1], FOD_SOURCE: "ORKS IS NEVER BEATEN"})
	ork.models[1]["current_wounds"] = 0
	var fp = _fight_phase(gs, pm, {"U_ORK": ork, "U_PROS": _unit("U_PROS", 2, 560, 500)})
	_check("Fight step running, P1 selects", int(fp.get_end_fight_status().selecting_player) == 1, str(fp.get_end_fight_status()))
	var sel = fp.execute_action({"type": "SELECT_FIGHTER", "unit_id": "U_ORK", "player": 1})
	_check("U_ORK selected to fight", sel.get("success", false), str(sel.get("errors", sel.get("error", ""))))
	_check("kept model still on the battlefield before the activation ends", gs.state.units.U_ORK.models[1].get("alive", false))
	var skip = fp.execute_action({"type": "SKIP_UNIT", "unit_id": "U_ORK", "player": 1})
	_check("SKIP_UNIT ends U_ORK's activation", skip.get("success", false), str(skip.get("errors", skip.get("error", ""))))
	_check("the kept model is removed (alive=false)", not gs.state.units.U_ORK.models[1].get("alive", true))
	_check("Fight On Death pending list cleared", gs.state.units.U_ORK.flags.get(FOD_PENDING, [0]).is_empty())
	var removal_in_changes := false
	for c in skip.get("changes", []):
		if str(c.get("path", "")) == "units.U_ORK.models.1.alive" and c.get("value", true) == false:
			removal_in_changes = true
	_check("removal diff carried in the action's changes (replay / network)", removal_in_changes)
	_check("the surviving model stays", gs.state.units.U_ORK.models[0].get("alive", false))

# ---------------------------------------------------------------------------
func _section_b_stale_end_phase(gs, pm, gm) -> void:
	print("\n-- B. MPGM-4: a stale END_* after its phase is over is a no-op --")
	gs.state["units"] = {"U_A": _unit("U_A", 1, 300, 300), "U_B": _unit("U_B", 2, 1500, 1500)}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = PH_SCORING
	pm.transition_to_phase(PH_SCORING)
	var scoring = pm.get_current_phase_instance()
	_check("Scoring phase current", int(scoring.phase_type) == PH_SCORING)
	for t in ["END_FIGHT", "END_MOVEMENT", "END_COMMAND"]:
		var r = gm.apply_action({"type": t, "player": 2})
		_check("stale %s accepted as a no-op" % t, r.get("success", false) and r.get("diffs", []).is_empty(), str(r))
		_check("…Scoring is still the phase (same instance)", pm.get_current_phase_instance() == scoring and gs.get_current_phase() == PH_SCORING,
			"phase %d" % gs.get_current_phase())
		_check("…no turn switch", int(gs.get_active_player()) == 1)

# ---------------------------------------------------------------------------
func _section_c_half_scoped(gs, pm, nm) -> void:
	print("\n-- C. MPGM-3: online END_FIGHT only ends the sender's own Pile In half --")
	var fp = _fight_phase(gs, pm, {"U_ORK": _unit("U_ORK", 1, 500, 500), "U_PROS": _unit("U_PROS", 2, 560, 500)}, false)
	var piler := int(fp.piling_in_player_11e)
	_check("Pile In step running", int(fp.pile_in_step_11e) == int(fp.PileInStep11e.ACTIVE) and piler > 0, "piler %d" % piler)
	var hot = fp.validate_action({"type": "END_FIGHT", "player": 3 - piler})
	_check("hot-seat: END_FIGHT stays unscoped (either seat ends the half)", hot.get("valid", false), str(hot))
	nm.network_mode = nm.NetworkMode.HOST
	var other = fp.validate_action({"type": "END_FIGHT", "player": 3 - piler})
	_check("online: the waiting player's END_FIGHT is refused", not other.get("valid", true), str(other))
	_check("…naming whose half it is", str(other.get("errors", [])).find("Player %d is piling in" % piler) >= 0, str(other))
	var own = fp.validate_action({"type": "END_FIGHT", "player": piler})
	_check("online: the piling-in player's END_FIGHT is valid", own.get("valid", false), str(own))
	var unscoped = fp.validate_action({"type": "END_FIGHT"})
	_check("online: an END_FIGHT without a player (AI default) is not scoped", unscoped.get("valid", false), str(unscoped))
	nm.network_mode = nm.NetworkMode.OFFLINE

# ---------------------------------------------------------------------------
func _section_d_afk_timer(gs, pm, nm) -> void:
	print("\n-- D. MPGM-1/2, FC-3: the AFK timer charges the player being waited on --")
	# D1: Movement, P1 active, a window pending for P2.
	gs.state["units"] = {"U_A": _unit("U_A", 1, 300, 300), "U_B": _unit("U_B", 2, 1500, 1500)}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = PH_MOVEMENT
	pm.transition_to_phase(PH_MOVEMENT)
	var mp = pm.get_current_phase_instance()
	mp._window_pending = {"player": 2, "window_id": "movement_phase_end", "offers": [{"stratagem_id": "x", "name": "X", "targets": []}], "ctx": {}}
	nm.network_mode = nm.NetworkMode.HOST
	nm.peer_to_player_map = {1: 1, 2: 2}
	nm.consecutive_timeout_count = 0
	_game_over.clear()
	_check("D1: a pending window's decider (P2) is charged, not the active player",
		nm._afk_player_for_current_phase() == 2, "charged P%d" % nm._afk_player_for_current_phase())
	nm._on_turn_timeout()
	_check("D1: the timeout auto-DECLINED the window", not mp.has_pending_stratagem_window())
	_check("D1: still the Movement phase (the decline does not end it)", gs.get_current_phase() == PH_MOVEMENT)
	_check("D1: timer re-armed", not nm.turn_timer.is_stopped())
	_check("D1: no game over", _game_over.is_empty(), str(_game_over))
	_check("D1: with the window answered the active player is charged again", nm._afk_player_for_current_phase() == 1)
	nm.stop_turn_timer()

	# D2: Fight step, window pending for the non-selecting player.
	var fp = _fight_phase(gs, pm, {"U_ORK": _unit("U_ORK", 1, 500, 500), "U_PROS": _unit("U_PROS", 2, 560, 500)}, false)
	var piler := int(fp.piling_in_player_11e)
	_check("D2: Pile In step — the piling-in player (P%d) is charged" % piler, nm._afk_player_for_current_phase() == piler,
		"charged P%d" % nm._afk_player_for_current_phase())
	for _i in [1, 2]:
		if int(fp.pile_in_step_11e) == int(fp.PileInStep11e.ACTIVE):
			fp.execute_action({"type": "END_PILE_IN", "player": int(fp.piling_in_player_11e)})
	var sel := int(fp.get_end_fight_status().selecting_player)
	fp._window_pending = {"player": 3 - sel, "window_id": "enemy_targets_unit_fight", "offers": [{"stratagem_id": "x", "name": "X", "targets": []}], "ctx": {}}
	_check("D2: Fight step window — its decider (P%d) is charged, not the selecting player" % (3 - sel),
		nm._afk_player_for_current_phase() == 3 - sel, "charged P%d" % nm._afk_player_for_current_phase())
	fp._window_pending = {}

	# D3: mid-activation — select_to_fight already points peek_selection at
	# the NEXT picker; the fighter's owner is the one being waited on.
	var fighter_unit := "U_ORK" if sel == 1 else "U_PROS"
	var r = fp.execute_action({"type": "SELECT_FIGHTER", "unit_id": fighter_unit, "player": sel})
	_check("D3: P%d selected %s" % [sel, fighter_unit], r.get("success", false) and str(fp.active_fighter_id) == fighter_unit, str(r.get("errors", "")))
	_check("D3: the sequencer already names the next picker", int(fp.get_end_fight_status().selecting_player) == 3 - sel, str(fp.get_end_fight_status()))
	_check("D3: mid-activation the fighter's owner (P%d) is charged" % sel, nm._afk_player_for_current_phase() == sel,
		"charged P%d" % nm._afk_player_for_current_phase())
	nm.consecutive_timeout_count = 0
	_game_over.clear()
	nm._on_turn_timeout()
	_check("D3: a mid-activation timeout submits nothing (the fighter is still active)", str(fp.active_fighter_id) == fighter_unit)
	nm._on_turn_timeout()
	_check("D3: a 2nd consecutive timeout ends the game AGAINST the fighter's owner",
		not _game_over.is_empty() and int(_game_over[0][0]) == 3 - sel, str(_game_over))
	nm.stop_turn_timer()
	pm.game_ended = false
	nm.network_mode = nm.NetworkMode.OFFLINE

# ---------------------------------------------------------------------------
func _section_e_client_consolidation(gs, pm, nm) -> void:
	print("\n-- E. MPGM-6: the client closes its Consolidate step on the fight_phase_end window --")
	var fp = _fight_phase(gs, pm, {"U_A": _unit("U_A", 1, 300, 300), "U_B": _unit("U_B", 2, 1500, 1500)})
	fp.consolidation_step_11e = fp.ConsolidationStep11e.ACTIVE
	fp.consolidating_player_11e = 1
	_check("client Consolidate step ACTIVE before the result", fp.get_fight_step_11e() == "CONSOLIDATE")
	var transitions: Array = []
	fp.subphase_transition.connect(func(a, b): transitions.append([a, b]))
	nm.network_mode = nm.NetworkMode.CLIENT
	nm._emit_client_visual_updates({"success": true, "action_type": "END_CONSOLIDATION", "action_data": {},
		"stratagem_window_opened": {"window_id": "fight_phase_end", "player": 2, "offers": [], "ctx": {}}})
	nm.network_mode = nm.NetworkMode.OFFLINE
	_check("client Consolidate step closed (DONE)", int(fp.consolidation_step_11e) == int(fp.ConsolidationStep11e.DONE))
	_check("subphase_transition CONSOLIDATE -> FIGHT re-emitted (step panel hides, button relabels)",
		transitions.has(["CONSOLIDATE", "FIGHT"]), str(transitions))

# ---------------------------------------------------------------------------
func _section_f_group_order() -> void:
	print("\n-- F. SHOOT-2: the allocation group order follows the casualty preference --")
	var CP = load("res://scripts/rules/CasualtyPreference.gd")
	var nob := {"id": "grp_2_5_0", "character": false, "model_indices": [0], "w": 2, "sv": 5, "insv": 0, "has_wounded": false}
	var boyz := {"id": "grp_1_5_0", "character": false, "model_indices": [1, 2, 3, 4], "w": 1, "sv": 5, "insv": 0, "has_wounded": false}
	var boss := {"id": "char_5", "character": true, "model_indices": [5], "w": 6, "sv": 4, "insv": 5, "has_wounded": false}
	# Default (model-index) order would allocate to the Nob first.
	var order: Array = CP.group_order_for([nob, boyz, boss], [3, 1, 4, 2, 0, 5])
	_check("Nob kept last by the preference -> the Boyz group is allocated first", order == ["grp_1_5_0", "grp_2_5_0", "char_5"], str(order))
	order = CP.group_order_for([nob, boyz, boss], [0, 3, 1, 4, 2, 5])
	_check("Nob first in the preference -> its group first", order == ["grp_2_5_0", "grp_1_5_0", "char_5"], str(order))
	var wounded_nob := nob.duplicate()
	wounded_nob["has_wounded"] = true
	order = CP.group_order_for([wounded_nob, boyz, boss], [3, 1, 4, 2, 0, 5])
	_check("05.03: a wounded non-CHARACTER group stays first", order[0] == "grp_2_5_0", str(order))
	order = CP.group_order_for([boss, nob, boyz], [5, 3, 1, 4, 2, 0])
	_check("05.03: CHARACTER groups stay last whatever the preference", order[order.size() - 1] == "char_5", str(order))

func _finish() -> void:
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
