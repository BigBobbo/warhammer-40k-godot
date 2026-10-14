extends SceneTree

# Codex: Orks (11e) stratagem-window framework — regression checks for the
# verified defects fixed after the codex fold-in (cluster A: framework /
# network / AI / dialog UI). One section per finding key:
#   N. framework:F3 + ai:AI-04 + ai:AI-05 — networked reactive moves: the
#      follow-up owner passes NetworkManager's turn layer, the follow-up gate
#      refuses anyone else, hot-seat actions are stamped with the owner, and
#      the client mirrors the follow-up start / end (unit_move_begun,
#      ork11e_assault_disembark_requested, ork11e_reactive_move_started/ended).
#   C. framework:F4 — a network client never opens windows / raises event
#      windows; phase-ending window openers are not executed optimistically.
#   P. framework:F1 — the phase does not complete while a window / follow-up
#      is pending, and completes once it is answered.
#   E. live:LIVE-1 + framework:F2 — casualties a save overlay wrote into
#      GameState BEFORE APPLY_SAVES are detected (unit_destroyed + held
#      Deadly Demise + enemy_unit_has_attacked); setup writes before other
#      actions are still ignored.
#
# Fixtures: tests/saves/ork11e_orks_active / ork11e_orks_reactive (design §6.6).
# Usage: godot --headless --path 40k --script tests/test_ork_codex_framework_fixes.gd

const PHASE_COMMAND := 6
const PHASE_MOVEMENT := 7
const PHASE_SHOOTING := 8
const PHASE_CHARGE := 9
const PHASE_FIGHT := 10
const PX := 40.0

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var RE = null
var AI = null
var NM = null


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _initialize() -> void:
	await create_timer(0.3).timeout
	SM = root.get_node("StratagemManager")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	AI = root.get_node("AIPlayer")
	NM = root.get_node("NetworkManager")
	var ss = root.get_node_or_null("SettingsService")
	if ss:
		ss.auto_allocate_wounds = true
	GameConstants.edition = 11
	print("\n=== test_ork_codex_framework_fixes ===")
	_boot_faction_ids = SM._player_faction_stratagems.get("1", []).duplicate() + SM._player_faction_stratagems.get("2", []).duplicate()
	await _section_s_stale_boot_stratagems()
	await _section_n_network_reactive_move()
	await _section_n_mirror()
	await _section_c_client_windows()
	await _section_p_phase_completion()
	await _section_e_preapplied_casualties()
	await _section_o_event_order()
	await _section_l_save_load()
	await _section_a_ai()
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)


# ---------------------------------------------------------------------------
# Helpers
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


func _phase():
	return PM.get_current_phase_instance()


func _unit(uid: String) -> Dictionary:
	return GS.state.units.get(uid, {})


func _alive(uid: String) -> int:
	var n := 0
	for m in _unit(uid).get("models", []):
		if m.get("alive", true):
			n += 1
	return n


func _centroid(uid: String) -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for m in _unit(uid).get("models", []):
		if m.get("position", null) == null:
			continue
		c += Vector2(float(m.position.x), float(m.position.y))
		n += 1
	return c / max(1, n)


func _move_to(uid: String, at: Vector2) -> void:
	var d: Vector2 = at * PX - _centroid(uid)
	for m in _unit(uid).get("models", []):
		var p = m.get("position", null)
		if p == null:
			continue
		m["position"] = {"x": float(p.x) + d.x, "y": float(p.y) + d.y}


func _pending_id(phase) -> String:
	return str(phase.get_pending_stratagem_window().get("window_id", "")) if phase.has_pending_stratagem_window() else ""


func _decline_pending(phase) -> void:
	var guard := 0
	while phase.has_pending_stratagem_window() and guard < 6:
		var w: Dictionary = phase.get_pending_stratagem_window()
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.player), "window_id": str(w.window_id)})
		guard += 1


## NetworkIntegration.route_action, loaded at run time (a parse-time reference
## pulls autoload identifiers into the `godot -s` compile — SCRIPT ERROR cascade).
func _route(action: Dictionary) -> Dictionary:
	return load("res://utils/NetworkIntegration.gd").route_action(action)


func _new_phase_instance(script_path: String) -> Node:
	var n := Node.new()
	n.set_script(load(script_path))
	root.add_child(n)
	return n


# ---------------------------------------------------------------------------
# S. F5 / LIVE-4 — the boot army's faction stratagems must not survive a load
# ---------------------------------------------------------------------------

var _boot_faction_ids: Array = []

func _section_s_stale_boot_stratagems() -> void:
	print("\n-- S. stale boot-army faction stratagems after loading a save (F5 / LIVE-4) --")
	_check("boot armies registered faction stratagems", not _boot_faction_ids.is_empty(), str(_boot_faction_ids.size()))
	_check("fixture ork11e_orks_active (War Horde vs Custodes)", _load("ork11e_orks_active"))
	var loaded: Array = SM._player_faction_stratagems.get("1", []) + SM._player_faction_stratagems.get("2", [])
	var stale: Array = []
	for sid in _boot_faction_ids:
		if not sid in loaded and SM.stratagems.has(sid):
			stale.append(sid)
	_check("no boot-only faction stratagem left in the registry", stale.is_empty(), str(stale))
	var ownerless: Array = []
	for sid in SM.stratagems:
		if SM.is_faction_stratagem(str(sid)) and SM.get_stratagem_owner(str(sid)) == 0:
			ownerless.append(sid)
	_check("every registered faction stratagem has an owner", ownerless.is_empty(), str(ownerless))
	var des := "faction_ork_kult_of_speed_delicious_eating_squigs"
	_check("Kult of Speed's DELICIOUS EATING SQUIGS is not usable by the War Horde player", not SM.can_use_stratagem(1, des).get("can_use", false))
	# An owner-less faction definition (however it got there) is nobody's.
	SM.stratagems["faction_test_orphan"] = {"id": "faction_test_orphan", "name": "ORPHAN", "cp_cost": 1, "implemented": true,
		"timing": {"turn": "either", "phase": "any"}, "target": {"type": "unit", "owner": "friendly", "conditions": []}, "effects": []}
	var orphan: Dictionary = SM.can_use_stratagem(1, "faction_test_orphan")
	_check("owner-0 faction stratagem refused for P1", not orphan.get("can_use", true) and str(orphan.get("reason", "")).contains("not a stratagem of either army"), str(orphan))
	_check("... and for P2", not SM.can_use_stratagem(2, "faction_test_orphan").get("can_use", true))
	SM.stratagems.erase("faction_test_orphan")


# ---------------------------------------------------------------------------
# N. F3 / AI-04 / AI-05 — networked reactive normal move (SCARPER!-style)
# ---------------------------------------------------------------------------

func _section_n_network_reactive_move() -> void:
	print("\n-- N. reactive normal move by the NON-active player: network turn layer + follow-up gate (F3 / AI-04 / AI-05) --")
	_check("fixture ork11e_orks_reactive", _load("ork11e_orks_reactive"))
	PM.transition_to_phase(PHASE_COMMAND)
	_decline_pending(_phase())
	PM.transition_to_phase(PHASE_MOVEMENT)
	var ph = _phase()
	_decline_pending(ph)
	var prev_map: Dictionary = NM.peer_to_player_map.duplicate()
	NM.peer_to_player_map = {1: 1, 7: 2}
	var m0 = GS.state.units.U_GRETCHIN_C.models[0]
	var dest := [float(m0.position.x), float(m0.position.y) + 40.0]

	# Without a follow-up the turn layer still refuses the non-active player.
	var v_no = NM.validate_action({"type": "STAGE_MODEL_MOVE", "player": 2, "actor_unit_id": "U_GRETCHIN_C", "payload": {"model_id": "m1", "dest": dest}}, 7)
	_check("no follow-up: P2 STAGE_MODEL_MOVE refused 'Not your turn'", not v_no.get("valid", true) and str(v_no.get("reason", "")) == "Not your turn", str(v_no))

	var started: bool = ph._ork11e_begin_reactive_normal_move(2, {"unit_id": "U_GRETCHIN_C", "max_inches": 6.0, "source": "SCARPER!"})
	_check("reactive move follow-up started for human P2", started and not ph._ork11e_reactive_move.is_empty())
	_check("phase reports P2 as the follow-up owner", ph.get_pending_stratagem_window_decider() == 2)
	# A legal 1" step for model m1 (geometry is the phase's business, not this test's).
	for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(-0.6, -0.6), Vector2(0.6, 0.6)]:
		var cand := [float(m0.position.x) + off.x * PX, float(m0.position.y) + off.y * PX]
		if ph.validate_action({"type": "STAGE_MODEL_MOVE", "player": 2, "actor_unit_id": "U_GRETCHIN_C", "payload": {"model_id": "m1", "dest": cand}}).get("valid", false):
			dest = cand
			break
	for t in ["STAGE_MODEL_MOVE", "SET_MODEL_DEST", "CONFIRM_UNIT_MOVE"]:
		var v = NM.validate_action({"type": t, "player": 2, "actor_unit_id": "U_GRETCHIN_C", "payload": {"model_id": "m1", "dest": dest}}, 7)
		_check("network: P2 (owner, non-active) %s passes" % t, v.get("valid", false), str(v.get("reason", v.get("errors", ""))))
	for t in ["RESET_UNIT_MOVE", "UNDO_LAST_MODEL_MOVE"]:
		var v = NM.validate_action({"type": t, "player": 2, "actor_unit_id": "U_GRETCHIN_C", "payload": {}}, 7)
		_check("network: P2 %s not refused by the turn layer" % t, str(v.get("reason", "")) != "Not your turn", str(v))
	# Authority is still enforced: peer 7 cannot claim to be P1, P1 cannot be P2.
	var v_auth = NM.validate_action({"type": "STAGE_MODEL_MOVE", "player": 2, "actor_unit_id": "U_GRETCHIN_C", "payload": {"model_id": "m1", "dest": dest}}, 1)
	_check("network: peer 1 claiming P2 refused (authority)", not v_auth.get("valid", true) and str(v_auth.get("reason", "")).contains("mismatch"), str(v_auth))
	# AI-05: the opponent (active P1, e.g. the AI) cannot stage or end P2's move.
	var v_p1 = NM.validate_action({"type": "CONFIRM_UNIT_MOVE", "player": 1, "actor_unit_id": "U_GRETCHIN_C", "payload": {}}, 1)
	_check("network: P1 CONFIRM_UNIT_MOVE of P2's reactive unit refused", not v_p1.get("valid", true) and str(v_p1.get("errors", v_p1.get("reason", ""))).contains("Player 2 is making"), str(v_p1))
	var r_p1 = ph.execute_action({"type": "CONFIRM_UNIT_MOVE", "player": 1, "actor_unit_id": "U_GRETCHIN_C", "payload": {}})
	_check("local: P1 CONFIRM_UNIT_MOVE of P2's reactive unit refused (AI-05)", not r_p1.get("success", true) and str(r_p1.get("error", "")).contains("Player 2 is making"), str(r_p1.get("error", "")))
	_check("... and the follow-up is still pending", not ph._ork11e_reactive_move.is_empty())
	# Other actions of P2 pass the turn layer but the follow-up gate refuses them.
	var v_end = NM.validate_action({"type": "END_MOVEMENT", "player": 2}, 7)
	_check("network: P2 END_MOVEMENT refused by the follow-up gate (not the turn layer)", not v_end.get("valid", true) and str(v_end.get("reason", "")) != "Not your turn", str(v_end))
	# Hot-seat: an un-stamped local action is stamped with the follow-up owner.
	var stamped := {"type": "STAGE_MODEL_MOVE", "actor_unit_id": "U_GRETCHIN_C", "payload": {"model_id": "m1", "dest": dest}}
	var r_stage = _route(stamped)
	_check("hot-seat: route_action stamps the follow-up owner (P2)", int(stamped.get("player", 0)) == 2, str(stamped.get("player", "")))
	_check("hot-seat: P2's staged move accepted", r_stage.get("success", false), str(r_stage.get("error", "")))
	var r_conf = _route({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_GRETCHIN_C", "payload": {}})
	_check("hot-seat: P2 confirms the reactive move", r_conf.get("success", false), str(r_conf.get("error", "")))
	_check("follow-up finished", ph._ork11e_reactive_move.is_empty() and ph.get_pending_stratagem_window_decider() == 0)
	var stamped2 := {"type": "RESET_UNIT_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_C", "payload": {}}
	_route(stamped2)
	_check("no follow-up: route_action stamps the active player again", int(stamped2.get("player", 0)) == 1, str(stamped2.get("player", "")))

	# Pre-existing reactive move (Krump and Run / Scatter! shape): its owner
	# may move that unit during the opponent's turn too.
	ph.active_moves["U_GRETCHIN_D"] = {"mode": "NORMAL", "is_reactive_move": true, "reactive_source": "krump_and_run", "completed": false,
		"move_cap_inches": 6.0, "model_moves": [], "staged_moves": [], "original_positions": {}, "original_rotations": {}, "model_distances": {}}
	ph._reactive_move_owner = 2
	var v_kr = NM.validate_action({"type": "STAGE_MODEL_MOVE", "player": 2, "actor_unit_id": "U_GRETCHIN_D", "payload": {"model_id": "m1", "dest": dest}}, 7)
	_check("network: Krump-and-Run-style reactive move owner passes the turn layer", str(v_kr.get("reason", "")) != "Not your turn", str(v_kr))
	var v_kr_other = NM.validate_action({"type": "STAGE_MODEL_MOVE", "player": 2, "actor_unit_id": "U_GRETCHIN_C", "payload": {"model_id": "m1", "dest": dest}}, 7)
	_check("network: ... but not for another unit", str(v_kr_other.get("reason", "")) == "Not your turn", str(v_kr_other))
	ph.active_moves.erase("U_GRETCHIN_D")
	ph._reactive_move_owner = 0
	NM.peer_to_player_map = prev_map


# ---------------------------------------------------------------------------
# N2. F3 — client mirror of the follow-up start / end
# ---------------------------------------------------------------------------

var _mirror_events: Array = []

func _on_mirror_move_begun(uid: String, mode: String) -> void:
	_mirror_events.append(["unit_move_begun", uid, mode])

func _on_mirror_disembark(player: int, tid: String, uid: String) -> void:
	_mirror_events.append(["assault_disembark", player, tid, uid])

func _on_mirror_rm_started(info: Dictionary) -> void:
	_mirror_events.append(["rm_started", str(info.get("unit_id", "")), int(info.get("player", 0))])

func _on_mirror_rm_ended(info: Dictionary) -> void:
	_mirror_events.append(["rm_ended", str(info.get("unit_id", ""))])

func _section_n_mirror() -> void:
	print("\n-- N2. follow-up mirror: host snapshot -> client phase + start/end signals (F3) --")
	_check("fixture ork11e_orks_reactive", _load("ork11e_orks_reactive"))
	PM.transition_to_phase(PHASE_COMMAND)
	_decline_pending(_phase())
	PM.transition_to_phase(PHASE_MOVEMENT)
	var host = _phase()
	_decline_pending(host)
	host._ork11e_begin_reactive_normal_move(2, {"unit_id": "U_GRETCHIN_C", "max_inches": 5.0, "source": "SCARPER!"})
	var snap: Dictionary = NM._followup_mirror_snapshot()
	_check("host snapshot = movement_reactive_move", str(snap.get("kind", "")) == "movement_reactive_move", str(snap))
	_check("snapshot survives JSON", JSON.parse_string(JSON.stringify(snap)) is Dictionary)
	var client = _new_phase_instance("res://phases/MovementPhase.gd")
	client.unit_move_begun.connect(_on_mirror_move_begun)
	client.ork11e_assault_disembark_requested.connect(_on_mirror_disembark)
	_mirror_events = []
	NM._apply_followup_mirror(client, JSON.parse_string(JSON.stringify(snap)), 1)
	_check("non-decider client: state mirrored", int(client._ork11e_reactive_move.get("player", 0)) == 2 and client.get_pending_stratagem_window_decider() == 2)
	_check("non-decider client: no move UI signal", _mirror_events.is_empty(), str(_mirror_events))
	_check("non-decider client: its gate now refuses its own END_MOVEMENT", not client._ork11e_followup_gate({"type": "END_MOVEMENT", "player": 1}).is_empty())
	var client2 = _new_phase_instance("res://phases/MovementPhase.gd")
	client2.unit_move_begun.connect(_on_mirror_move_begun)
	_mirror_events = []
	NM._apply_followup_mirror(client2, JSON.parse_string(JSON.stringify(snap)), 2)
	_check("decider client: unit_move_begun(U_GRETCHIN_C, NORMAL) re-emitted", _mirror_events == [["unit_move_begun", "U_GRETCHIN_C", "NORMAL"]], str(_mirror_events))
	_check("decider client: reactive active move with the 5\" cap", float(client2.get_active_move_data("U_GRETCHIN_C").get("move_cap_inches", 0.0)) == 5.0 \
		and bool(client2.get_active_move_data("U_GRETCHIN_C").get("is_reactive_move", false)))
	_check("decider client: allows its own cross-turn move action", client2.allows_cross_turn_action({"type": "STAGE_MODEL_MOVE", "player": 2, "actor_unit_id": "U_GRETCHIN_C"}))
	_mirror_events = []
	NM._apply_followup_mirror(client2, JSON.parse_string(JSON.stringify(snap)), 2)
	_check("same snapshot again: no duplicate start signal", _mirror_events.is_empty(), str(_mirror_events))
	NM._apply_followup_mirror(client2, {}, 2)
	_check("host finished: mirror cleared", client2._ork11e_reactive_move.is_empty() and client2.get_pending_stratagem_window_decider() == 0 \
		and bool(client2.get_active_move_data("U_GRETCHIN_C").get("completed", false)))
	# READIED BRAWLERS assault disembark request
	_mirror_events = []
	var ad := {"kind": "movement_assault_disembark", "data": {"player": 1, "transport_id": "U_BATTLEWAGON_A", "remaining": ["U_BOYZ_X", "U_BOYZ_Y"]}}
	NM._apply_followup_mirror(client, ad, 1)
	_check("assault disembark request re-emitted for the first unit", _mirror_events == [["assault_disembark", 1, "U_BATTLEWAGON_A", "U_BOYZ_X"]], str(_mirror_events))
	ad.data.remaining = ["U_BOYZ_Y"]
	NM._apply_followup_mirror(client, ad, 1)
	_check("... and for the next unit when the host moves on", _mirror_events.size() == 2 and _mirror_events[1][3] == "U_BOYZ_Y", str(_mirror_events))
	NM._apply_followup_mirror(client, {}, 1)
	_check("assault disembark mirror cleared", client._ork11e_assault_disembark.is_empty())
	client.queue_free()
	client2.queue_free()

	# Shooting: GRAB IT reactive move (ork11e_reactive_move_started / _ended)
	_check("fixture ork11e_orks_active", _load("ork11e_orks_active"))
	PM.transition_to_phase(PHASE_COMMAND)
	_decline_pending(_phase())
	PM.transition_to_phase(PHASE_SHOOTING)
	var sh = _phase()
	_decline_pending(sh)
	var s_started: bool = sh._ork11e_start_reactive_move(1, "normal", {"unit_id": "U_FLASH_GITZ_A", "max_inches": 6.0, "source": "GRAB IT", "end_condition": "objective"})
	_check("host shooting follow-up started (human P1)", s_started)
	var s_snap: Dictionary = NM._followup_mirror_snapshot()
	_check("host snapshot = shooting_reactive_move", str(s_snap.get("kind", "")) == "shooting_reactive_move", str(s_snap.get("kind", "")))
	var s_client = _new_phase_instance("res://phases/ShootingPhase.gd")
	s_client.ork11e_reactive_move_started.connect(_on_mirror_rm_started)
	s_client.ork11e_reactive_move_ended.connect(_on_mirror_rm_ended)
	_mirror_events = []
	NM._apply_followup_mirror(s_client, JSON.parse_string(JSON.stringify(s_snap)), 1)
	_check("client: ork11e_reactive_move_started re-emitted (Flash Gitz, P1)", _mirror_events == [["rm_started", "U_FLASH_GITZ_A", 1]], str(_mirror_events))
	var origin: Dictionary = s_client._ork11e_followup.get("origin", {})
	_check("client: origin positions restored as Vector2", not origin.is_empty() and origin.values()[0] is Vector2)
	_check("client: reactive move info available for the panel", float(s_client.ork11e_reactive_move_info().get("max_inches", 0.0)) == 6.0)
	_mirror_events = []
	NM._apply_followup_mirror(s_client, {}, 1, {"ork11e_reactive_move_ended": {"player": 1, "unit_id": "U_FLASH_GITZ_A", "source": "GRAB IT", "moved": true}})
	_check("client: ork11e_reactive_move_ended re-emitted + mirror cleared", _mirror_events == [["rm_ended", "U_FLASH_GITZ_A"]] and s_client._ork11e_followup.is_empty(), str(_mirror_events))
	s_client.queue_free()
	sh._ork11e_followup = {}
	sh._window_followup_pending = false


# ---------------------------------------------------------------------------
# C. F4 — network clients open no windows
# ---------------------------------------------------------------------------

func _section_c_client_windows() -> void:
	print("\n-- C. network client: no local windows / event windows; phase-end openers not optimistic (F4) --")
	_check("fixture ork11e_orks_active", _load("ork11e_orks_active"))
	PM.transition_to_phase(PHASE_COMMAND)
	_decline_pending(_phase())
	PM.transition_to_phase(PHASE_FIGHT)
	var ph = _phase()
	_decline_pending(ph)
	var heh := _sid(1, "hit-em-harder-war-horde")
	var offers: Array = SM.get_window_offers(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_BOYZ_B"})
	_check("host: HIT 'EM HARDER offered on Boyz selected to fight", offers.any(func(o): return str(o.get("stratagem_id", "")) == heh))
	var prev_mode = NM.network_mode
	NM.network_mode = NM.NetworkMode.CLIENT
	var opened: bool = ph.open_stratagem_window(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_BOYZ_B"}, "")
	_check("client: open_stratagem_window returns false", not opened)
	_check("client: nothing pending, nothing queued", not ph.has_pending_stratagem_window() and ph._window_queue.is_empty() and ph._ev_deferred.is_empty())
	# event detection: a kill on the client raises no event window
	ph._window_events_detect()
	for m in _unit("U_GRETCHIN_C").models:
		m["alive"] = false
	ph._window_events_detect()
	_check("client: a destroyed unit raises no unit_destroyed event", ph._ev_deferred.is_empty() and ph._ev_destroyed_open.is_empty())
	_check("client: Deadly Demise never held", not ph._window_hold_deadly_demise("U_GRETCHIN_C"))
	NM.network_mode = prev_mode
	_check("phase-end window opener END_MOVEMENT not optimistic with codex windows in play", NM._optimistic_blocked_by_windows("END_MOVEMENT"))
	_check("END_FIGHT likewise", NM._optimistic_blocked_by_windows("END_FIGHT"))
	_check("BEGIN_NORMAL_MOVE stays optimistic", not NM._optimistic_blocked_by_windows("BEGIN_NORMAL_MOVE"))


# ---------------------------------------------------------------------------
# P. F1 — the phase must not complete with a window / follow-up pending
# ---------------------------------------------------------------------------

func _mark_others_shot(ph, keep: String) -> void:
	var active := int(GS.get_active_player())
	for uid in GS.state.units:
		if int(GS.state.units[uid].get("owner", 0)) == active and str(uid) != keep and not str(uid) in ph.units_that_shot:
			ph.units_that_shot.append(str(uid))


func _ranged_assignments(shooter: String, target: String) -> Array:
	var board: Dictionary = GS.create_snapshot()
	var weapons: Array = RE.get_eligible_targets(shooter, board).get(target, {}).get("weapons_in_range", [])
	var by_weapon := {}
	var uw: Dictionary = RE.get_unit_weapons(shooter, board)
	for mid in uw:
		for wid in uw[mid]:
			if wid in weapons:
				if not by_weapon.has(wid):
					by_weapon[wid] = []
				by_weapon[wid].append(mid)
	var out: Array = []
	for wid in by_weapon:
		out.append({"weapon_id": wid, "target_unit_id": target, "model_ids": by_weapon[wid]})
	return out


func _section_p_phase_completion() -> void:
	print("\n-- P. last shooter: the Shooting phase waits for the pending window, then completes (F1) --")
	_check("fixture ork11e_orks_active", _load("ork11e_orks_active"))
	_set_detachment(1, "Wreckas")
	PM.transition_to_phase(PHASE_COMMAND)
	_decline_pending(_phase())
	PM.transition_to_phase(PHASE_SHOOTING)
	var ph = _phase()
	_decline_pending(ph)
	_mark_others_shot(ph, "U_TANKBUSTAS_A")
	var res = ph.execute_action({"type": "SHOOT", "actor_unit_id": "U_TANKBUSTAS_A", "player": 1,
		"payload": {"assignments": _ranged_assignments("U_TANKBUSTAS_A", "U_CUSTODIAN_GUARD_C"), "rng_seed": 3}})
	_check("last shooter's SHOOT ok", res.get("success", false), str(res.get("error", "")))
	_check("every unit has shot", ph._should_complete_phase())
	_check("phase still Shooting with unit_has_shot (GRAB IT) pending", int(GS.get_current_phase()) == PHASE_SHOOTING and _phase() == ph and _pending_id(ph) == "unit_has_shot", "phase=%d pending=%s" % [int(GS.get_current_phase()), _pending_id(ph)])
	var dec = ph.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_has_shot"})
	_check("decline accepted", dec.get("success", false), str(dec.get("error", "")))
	_check("phase completed once the window was answered (now Charge)", int(GS.get_current_phase()) == PHASE_CHARGE, "phase=%d" % int(GS.get_current_phase()))

	print("\n-- P2. last enemy shooter destroys the Dakkajet: held Deadly Demise, phase waits (F1) --")
	_check("fixture ork11e_orks_reactive", _load("ork11e_orks_reactive"))
	_set_detachment(2, "Flyboyz")
	_move_to("U_DAKKAJET_A", Vector2(41, 35))
	_move_to("U_CUSTODIAN_GUARD_F", Vector2(41, 24))
	var jet = GS.state.units["U_DAKKAJET_A"]
	jet.models[0]["current_wounds"] = 1
	jet.meta.stats["toughness"] = 2
	jet.meta.stats["save"] = 7
	PM.transition_to_phase(PHASE_COMMAND)
	_decline_pending(_phase())
	PM.transition_to_phase(PHASE_SHOOTING)
	ph = _phase()
	_decline_pending(ph)
	_mark_others_shot(ph, "U_CUSTODIAN_GUARD_F")
	res = ph.execute_action({"type": "SHOOT", "actor_unit_id": "U_CUSTODIAN_GUARD_F", "player": 1,
		"payload": {"assignments": _ranged_assignments("U_CUSTODIAN_GUARD_F", "U_DAKKAJET_A"), "rng_seed": 5}})
	_check("SHOOT ok + Dakkajet destroyed", res.get("success", false) and _alive("U_DAKKAJET_A") == 0, str(res.get("error", "")))
	_check("phase still Shooting, unit_destroyed pending, Deadly Demise held", int(GS.get_current_phase()) == PHASE_SHOOTING and _pending_id(ph) == "unit_destroyed" and ph._ev_dd_held.has("U_DAKKAJET_A"),
		"phase=%d pending=%s held=%s" % [int(GS.get_current_phase()), _pending_id(ph), str(ph._ev_dd_held)])
	var end_try = ph.execute_action({"type": "END_SHOOTING", "player": 1})
	_check("END_SHOOTING refused while P2 decides", not end_try.get("success", true))
	dec = ph.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 2, "window_id": "unit_destroyed"})
	_check("P2 declines", dec.get("success", false), str(dec.get("error", "")))
	_check("held Deadly Demise released on the SAME phase instance", ph._ev_dd_released.has("U_DAKKAJET_A"))
	_check("phase completed after the decision (now Charge)", int(GS.get_current_phase()) == PHASE_CHARGE, "phase=%d" % int(GS.get_current_phase()))


# ---------------------------------------------------------------------------
# E. LIVE-1 / F2 — casualties the save overlay wrote before APPLY_SAVES
# ---------------------------------------------------------------------------

func _section_e_preapplied_casualties() -> void:
	print("\n-- E. casualties written into GameState before APPLY_SAVES / APPLY_MELEE_SAVES are detected (LIVE-1 / F2) --")
	_check("fixture ork11e_orks_reactive", _load("ork11e_orks_reactive"))
	_set_detachment(2, "Flyboyz")
	PM.transition_to_phase(PHASE_COMMAND)
	_decline_pending(_phase())
	PM.transition_to_phase(PHASE_SHOOTING)
	var ph = _phase()
	_decline_pending(ph)
	ph.active_shooter_id = "U_CUSTODIAN_GUARD_F"
	# The defender's overlay removes the jet (direct GameState write) ...
	GS.state.units["U_DAKKAJET_A"].models[0]["alive"] = false
	GS.state.units["U_DAKKAJET_A"].models[0]["current_wounds"] = 0
	# ... then Done sends APPLY_SAVES: detection must see the death.
	ph._window_events_begin({"type": "APPLY_SAVES"})
	_check("APPLY_SAVES begin: unit_destroyed raised for the Dakkajet", ph._ev_destroyed_open.has("U_DAKKAJET_A") \
		and ph._ev_deferred.any(func(e): return str(e.get("window_id", "")) == "unit_destroyed" and str(e.ctx.get("unit_id", "")) == "U_DAKKAJET_A"), str(ph._ev_deferred))
	_check("... credited to the active shooter", ph._ev_deferred.any(func(e): return str(e.ctx.get("attacker_unit_id", "")) == "U_CUSTODIAN_GUARD_F"))
	_check("... and recorded for enemy_unit_has_attacked", ph._ev_attacks.get("U_CUSTODIAN_GUARD_F", []).has("U_DAKKAJET_A"))
	_check("Deadly Demise of the jet is held (FLYIN' HEADBUTT offered)", ph._window_hold_deadly_demise("U_DAKKAJET_A"))
	ph._ev_depth = 0
	ph._ev_deferred = []
	ph._ev_attacks = {}
	ph._ev_destroyed_open = {}
	ph._ev_dd_held = {}
	# Other actions keep ignoring writes made between actions (scenario / test setup).
	ph._window_events_detect()
	for m in _unit("U_GRETCHIN_D").models:
		m["alive"] = false
	ph._window_events_begin({"type": "SELECT_SHOOTER", "actor_unit_id": "U_CUSTODIAN_GUARD_F"})
	_check("SELECT_SHOOTER begin: a setup write is not an event", ph._ev_deferred.is_empty() and not ph._ev_destroyed_open.has("U_GRETCHIN_D"), str(ph._ev_deferred))
	ph._ev_depth = 0


# ---------------------------------------------------------------------------
# O. F10 — a shot's destruction windows open BEFORE the post-shot windows
# ---------------------------------------------------------------------------

func _section_o_event_order() -> void:
	print("\n-- O. unit_destroyed (and held Deadly Demise) before unit_has_shot (F10) --")
	_check("fixture ork11e_orks_active", _load("ork11e_orks_active"))
	_set_detachment(1, "Wreckas")
	# P2 becomes an Ork Flyboyz army owning the Dakkajet (orks-vs-orks).
	GS.state.factions["2"] = GS.state.factions["1"].duplicate(true)
	GS.state.units["U_DAKKAJET_A"]["owner"] = 2
	_set_detachment(2, "Flyboyz")
	var jet = GS.state.units["U_DAKKAJET_A"]
	jet.models[0]["current_wounds"] = 1
	jet.meta.stats["toughness"] = 2
	jet.meta.stats["save"] = 7
	_move_to("U_DAKKAJET_A", _centroid("U_TANKBUSTAS_A") / PX + Vector2(0, 9))
	PM.transition_to_phase(PHASE_COMMAND)
	_decline_pending(_phase())
	PM.transition_to_phase(PHASE_SHOOTING)
	var ph = _phase()
	_decline_pending(ph)
	var res = ph.execute_action({"type": "SHOOT", "actor_unit_id": "U_TANKBUSTAS_A", "player": 1,
		"payload": {"assignments": _ranged_assignments("U_TANKBUSTAS_A", "U_DAKKAJET_A"), "rng_seed": 3}})
	_check("Tankbustas SHOOT ok + Dakkajet destroyed", res.get("success", false) and _alive("U_DAKKAJET_A") == 0, str(res.get("error", "")))
	_check("FIRST window: unit_destroyed for P2 (FLYIN' HEADBUTT), not unit_has_shot", _pending_id(ph) == "unit_destroyed" and ph.get_pending_stratagem_window_decider() == 2,
		"pending=%s P%d" % [_pending_id(ph), ph.get_pending_stratagem_window_decider()])
	_check("Deadly Demise held for the window", ph._ev_dd_held.has("U_DAKKAJET_A"))
	_check("unit_has_shot (GRAB IT) queued behind it", ph._window_queue.any(func(e): return str(e.get("window_id", "")) == "unit_has_shot"),
		str(ph._window_queue.map(func(e): return e.get("window_id", ""))))
	var dec = ph.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 2, "window_id": "unit_destroyed"})
	_check("P2 declines FLYIN' HEADBUTT", dec.get("success", false), str(dec.get("error", "")))
	_check("Deadly Demise resolved before the post-shot windows", ph._ev_dd_released.has("U_DAKKAJET_A"))
	var guard := 0
	while ph.has_pending_stratagem_window() and _pending_id(ph) != "unit_has_shot" and guard < 4:
		var w: Dictionary = ph.get_pending_stratagem_window()
		ph.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.player), "window_id": str(w.window_id)})
		guard += 1
	_check("then unit_has_shot opens for P1", _pending_id(ph) == "unit_has_shot" and ph.get_pending_stratagem_window_decider() == 1, _pending_id(ph))
	_decline_pending(ph)


# ---------------------------------------------------------------------------
# L. F11 — window / follow-up state is not saved; a load never leaves the
#    phase stuck (documented limitation: a paid follow-up is lost)
# ---------------------------------------------------------------------------

func _section_l_save_load() -> void:
	print("\n-- L. save during a GRAB IT follow-up, load: the phase is free again (F11) --")
	_check("fixture ork11e_orks_active", _load("ork11e_orks_active"))
	_set_detachment(1, "Wreckas")
	var gi := _sid(1, "grab-it-wreckas")
	PM.transition_to_phase(PHASE_COMMAND)
	_decline_pending(_phase())
	PM.transition_to_phase(PHASE_SHOOTING)
	var ph = _phase()
	_decline_pending(ph)
	ph.execute_action({"type": "SHOOT", "actor_unit_id": "U_TANKBUSTAS_A", "player": 1,
		"payload": {"assignments": _ranged_assignments("U_TANKBUSTAS_A", "U_CUSTODIAN_GUARD_C"), "rng_seed": 3}})
	var use = ph.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_has_shot", "stratagem_id": gi, "target_unit_id": "U_TANKBUSTAS_A"})
	_check("GRAB IT used, follow-up pending", use.get("success", false) and ph.get_pending_stratagem_window_decider() == 1, str(use.get("error", "")))
	var slm = root.get_node("SaveLoadManager")
	_check("save mid-follow-up", slm.save_game("ork11e_fixes_mid_followup"))
	_check("load", slm.load_game("ork11e_fixes_mid_followup"))
	GameConstants.edition = 11
	PM.transition_to_phase(int(GS.get_current_phase()))
	var ph2 = _phase()
	_check("after load: no window / follow-up holds the phase", ph2.get_pending_stratagem_window_decider() == 0 and not ph2.has_pending_stratagem_window())
	var r = ph2.execute_action({"type": "SELECT_SHOOTER", "actor_unit_id": "U_FLASH_GITZ_A", "player": 1})
	_check("after load: the active player can act (select another shooter)", r.get("success", false), str(r.get("error", "")))


# ---------------------------------------------------------------------------
# A. AI — AI-01 (seat taken over mid-decision) and AI-07 (15.01 retry loop)
# ---------------------------------------------------------------------------

func _section_a_ai() -> void:
	print("\n-- A1. AI-01: the AI answers a window / follow-up of a seat it took over --")
	_check("fixture ork11e_orks_reactive", _load("ork11e_orks_reactive"))
	_set_detachment(2, "Runt Swarm")
	PM.transition_to_phase(PHASE_COMMAND)
	_decline_pending(_phase())
	PM.transition_to_phase(PHASE_MOVEMENT)
	var ph = _phase()
	_decline_pending(ph)
	# A human P2 window, opened while P2 was human.
	_move_to("U_CUSTODIAN_GUARD_C", _centroid("U_GRETCHIN_C") / PX + Vector2(0, -6))
	var opened: bool = ph.open_stratagem_window(2, "enemy_ended_move", {"phase": "movement", "enemy_unit_id": "U_CUSTODIAN_GUARD_C", "move_type": "normal"}, "")
	_check("human P2 enemy_ended_move window pending (SCARPER! offered)", opened and ph.get_pending_stratagem_window_decider() == 2, str(ph.get_pending_stratagem_window()))
	AI.enabled = true
	AI.ai_players = {1: false, 2: true}
	_check("the AI sees the window as its own (watchdog keeps evaluating)", AI._ai_owned_pending_item() == 2 and AI._is_any_ai_player_active())
	_check("AI submits P2's answer", AI._answer_ai_owned_pending_window())
	_check("... once (in flight, no duplicate)", AI._answer_ai_owned_pending_window() and bool(AI._ai01_answer.get("inflight", false)))
	await process_frame
	await process_frame
	_check("window answered by the AI (no longer pending)", not ph.has_pending_stratagem_window(), str(ph.get_pending_stratagem_window()))
	_check("no follow-up left behind for P2", ph.get_pending_stratagem_window_decider() == 0)
	# A human P2 reactive normal move in progress.
	AI.ai_players = {1: false, 2: false}
	AI._ai01_answer = {}
	ph._ork11e_begin_reactive_normal_move(2, {"unit_id": "U_GRETCHIN_D", "max_inches": 6.0, "source": "SCARPER!"})
	_check("human P2 SCARPER! move in progress", ph.get_pending_stratagem_window_decider() == 2)
	AI.ai_players = {1: false, 2: true}
	_check("AI finishes P2's pending move", AI._answer_ai_owned_pending_window())
	await process_frame
	await process_frame
	_check("follow-up completed by P2's AI seat", ph._ork11e_reactive_move.is_empty() and ph.get_pending_stratagem_window_decider() == 0)
	_check("nothing left for the AI to answer", not AI._answer_ai_owned_pending_window())
	_ai_off()

	print("\n-- A2. AI-07: UNLEASH THE LIONS is not re-picked when 15.01 refuses it --")
	_check("fixture ork11e_orks_reactive", _load("ork11e_orks_reactive"))
	PM.transition_to_phase(PHASE_COMMAND)
	var cph = _phase()
	_decline_pending(cph)
	var utl := str(SM.find_faction_stratagem_by_name(1, "UNLEASH THE LIONS"))
	_check("Custodes have UNLEASH THE LIONS", utl != "")
	var utl_action := {}
	for a in cph.get_available_actions():
		if str(a.get("type", "")) == "USE_UNLEASH_THE_LIONS":
			utl_action = a
			break
	_check("offered for an Allarus unit", not utl_action.is_empty(), str(utl_action))
	var ADM = load("res://scripts/AIDecisionMaker.gd")
	var d0: Dictionary = ADM._decide_command(GS.create_snapshot(), [utl_action], 1)
	_check("AI uses it when legal (round 2, 6 CP)", str(d0.get("type", "")) == "USE_UNLEASH_THE_LIONS", str(d0))
	SM._usage_history["1"].append({"stratagem_id": "core_command_re_roll", "target_unit_id": str(utl_action.get("unit_id", "")),
		"turn": GS.get_battle_round(), "phase": GS.get_current_phase(), "active_player": GS.get_active_player()})
	_check("15.01 now refuses it on that unit", not SM.can_use_stratagem(1, utl, str(utl_action.get("unit_id", ""))).get("can_use", true))
	var d1: Dictionary = ADM._decide_command(GS.create_snapshot(), [utl_action], 1)
	_check("AI no longer picks the refused use", str(d1.get("type", "")) != "USE_UNLEASH_THE_LIONS", str(d1))
