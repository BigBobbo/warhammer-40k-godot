extends SceneTree

# EA-08 review (online play, 11e 09.07 / 09.02.02): a Desperate Escape made by
# the web-relay CLIENT (the guest, Player 2) — every production online game.
#
# The client runs NetworkManager.DETERMINISTIC_ACTIONS optimistically against
# its OWN MovementPhase: it validates them there (a refusal shows a toast and
# the action is never sent), runs them, and skips the host's diffs when the
# host confirms. Every other action goes to the host only and the client just
# applies the host's diffs. The fall-back mode lives in the phase-local
# active_moves, so on the client it only changes for actions the client runs.
#
# Before the fix:
#   (A) The Desperate Escape box ticked AFTER Fall Back began sends
#       SET_FALL_BACK_MODE, which was host-only: the host made the hazard rolls
#       (and inflicted their mortal wounds) while the client's move stayed an
#       Ordered Retreat, so every drag through an enemy model was refused on
#       the client ("Ordered Retreat cannot move through enemy models") and
#       never reached the host.
#   (B) The box ticked BEFORE Fall Back rides BEGIN_FALL_BACK
#       (payload.fall_back_mode), which the client runs optimistically — but
#       the hazard rolls (and the AFTER MOVING battle-shock roll at
#       CONFIRM_UNIT_MOVE) used RulesEngine.make_rng(): on a client that is an
#       unseeded RNG ("Only host can generate RNG seeds!"), so the client kept
#       different wounds than the host (a confirmed optimistic action skips the
#       host's diffs): a lasting desync.
#   (C) Backstop: a client whose phase-local record missed the switch still
#       treats the move as a Desperate Escape once the synced hazard record
#       (units.<id>.flags.desperate_escape_hazards_this_phase) is there.
#
# Real code on both sides. The HOST run feeds each guest action through
# NetworkManager._on_web_relay_message (a JSON wire round trip, as the relay
# does) and records the host's reply; the CLIENT run starts from the same
# state, submits the same actions (same rng_seed) through
# NetworkManager.submit_action's relay-client branch and then receives the
# recorded host replies through _on_web_relay_message. The only fake is the
# WebSocketRelay transport: a node that records what would be sent.
#
# Usage: godot --headless --path . -s tests/test_ea08_fall_back_online_client_11e.gd

var passed := 0
var failed := 0
var _ran := false

const FLAG_DE := "desperate_escape_hazards_this_phase"
const ERR_OR := "Ordered Retreat cannot move through enemy models — choose Desperate Escape to move through them (09.07)"

var gs
var pm
var nm
var tm
var relay: Node
var base_state: Dictionary
var desyncs: Array = []

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _unit(id: String, owner: int, positions: Array, wounds: int, name: String) -> Dictionary:
	var models := []
	var i := 0
	for p in positions:
		models.append({"id": "m%d" % i, "alive": true, "wounds": wounds, "current_wounds": wounds,
			"base_mm": 32, "base_type": "circular", "position": {"x": p.x, "y": p.y}})
		i += 1
	return {"id": id, "owner": owner, "status": 2, "flags": {}, "status_effects": {},
		"meta": {"name": name, "keywords": ["INFANTRY"], "abilities": [],
			"stats": {"move": 8, "toughness": 4, "save": 3, "wounds": wounds, "leadership": 7, "objective_control": 1}},
		"models": models, "weapons": [], "attachment_data": {}}

## Player 2 (the relay client) is active in its Movement phase. Its 5 Boyz
## (6 wounds each: no hazard roll can kill one, so every model always moves)
## stand in a row at y=1000; a Player 1 Witchseeker stands 60 px north of m0
## (9.6 px edge gap: the unit is engaged). Moving every model 200 px straight
## north takes m0 THROUGH the Witchseeker and leaves the unit unengaged and in
## coherency.
func _setup() -> void:
	gs.state = base_state.duplicate(true)
	var row := []
	for i in range(5):
		row.append(Vector2(400 + 60 * i, 1000))
	gs.state["units"] = {
		"U_FB": _unit("U_FB", 2, row, 6, "Boyz"),
		"U_EN": _unit("U_EN", 1, [Vector2(400, 940)], 1, "Witchseeker")}
	gs.state["meta"]["active_player"] = 2
	gs.state["meta"]["phase"] = 7
	for pid in ["1", "2"]:
		if gs.state.get("players", {}).has(pid):
			gs.state["players"][pid]["cp"] = 0
	pm.transition_to_phase(7)
	nm.web_relay_mode = true
	nm.peer_to_player_map = {1: 1, 2: 2}
	nm.web_relay = relay
	nm.reset_optimistic_state()
	relay.sent.clear()

func _phase():
	return pm.get_current_phase_instance()

## What the relay does to a message: JSON (Vector2 -> {x, y}, ints -> floats).
func _wire(msg: Dictionary) -> Dictionary:
	var parsed = JSON.parse_string(JSON.stringify(nm._sanitize_for_json(msg)))
	return parsed if parsed is Dictionary else {}

func _actions(flow: String, seeds: Array) -> Array:
	var acts: Array = []
	var begin_payload := {"rng_seed": int(seeds[0])}
	if flow == "B":
		begin_payload["fall_back_mode"] = "desperate_escape"
	acts.append({"type": "BEGIN_FALL_BACK", "actor_unit_id": "U_FB", "player": 2, "payload": begin_payload})
	if flow == "A":
		acts.append({"type": "SET_FALL_BACK_MODE", "actor_unit_id": "U_FB", "player": 2,
			"payload": {"fall_back_mode": "desperate_escape", "rng_seed": int(seeds[1])}})
	for i in range(5):
		acts.append({"type": "STAGE_MODEL_MOVE", "actor_unit_id": "U_FB", "player": 2,
			"payload": {"model_id": "m%d" % i, "dest": [400.0 + 60.0 * i, 800.0], "rotation": 0.0, "rng_seed": 1000 + i}})
	acts.append({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_FB", "player": 2, "payload": {"rng_seed": int(seeds[2])}})
	return acts

func _bs_lines(from_idx: int) -> Array:
	var gel = root.get_node_or_null("GameEventLog")
	var out: Array = []
	if gel == null or not gel.has_method("get_all_entries"):
		return out
	var entries: Array = gel.get_all_entries()
	for i in range(from_idx, entries.size()):
		var t := str(entries[i].get("text", ""))
		if "Battle-shock test" in t:
			out.append(t)
	return out

func _log_size() -> int:
	var gel = root.get_node_or_null("GameEventLog")
	return gel.get_all_entries().size() if gel != null and gel.has_method("get_all_entries") else 0

func _pos(unit_id: String, idx: int) -> Vector2:
	var p = gs.state.units[unit_id].models[idx].get("position", {})
	if p is Vector2:
		return p
	if p is Dictionary:
		return Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	return Vector2.INF

func _wounds() -> Array:
	var w: Array = []
	for m in gs.state.units.U_FB.models:
		w.append(int(m.get("current_wounds", 0)))
	return w

## The hazard record's rolls as ints (a value that crossed the JSON relay holds floats).
func _rolls(flag: Dictionary) -> Array:
	return flag.get("rolls", []).map(func(v): return int(v))

## One flow, host run then client run. Returns what the checks need.
func _run_flow(flow: String, seeds: Array) -> Dictionary:
	var acts: Array = _actions(flow, seeds)
	# ---- HOST: the guest's actions arrive over the relay ----
	_setup()
	nm.is_online_host = true
	var replies: Array = []
	var host_rejections: Array = []
	var log0 := _log_size()
	for a in acts:
		relay.sent.clear()
		nm._on_web_relay_message(_wire({"msg_type": "game_action", "action": a.duplicate(true)}))
		var reply: Dictionary = _wire(relay.sent.back()) if not relay.sent.is_empty() else {}
		if str(reply.get("msg_type", "")) != "action_result":
			host_rejections.append("%s: %s" % [a.type, str(reply.get("reason", reply))])
		replies.append(reply)
	var host := {"hash": nm.compute_state_hash(), "flag": gs.state.units.U_FB.flags.get(FLAG_DE, {}).duplicate(true),
		"wounds": _wounds(), "m0": _pos("U_FB", 0), "shocked": bool(gs.state.units.U_FB.flags.get("battle_shocked", false)),
		"bs": _bs_lines(log0)}
	# ---- CLIENT: the same actions, submitted by the guest ----
	_setup()
	nm.is_online_host = false
	desyncs.clear()
	var refused_locally: Array = []
	var mode_after_switch := ""
	var log1 := _log_size()
	for i in range(acts.size()):
		var a: Dictionary = acts[i].duplicate(true)
		relay.sent.clear()
		nm.submit_action(a)
		var sent_types: Array = relay.sent.map(func(m): return str(m.get("action", {}).get("type", "")))
		if not a.type in sent_types:
			refused_locally.append(a.type + (" " + str(a.payload.get("model_id", "")) if a.type == "STAGE_MODEL_MOVE" else ""))
		if a.type in ["BEGIN_FALL_BACK", "SET_FALL_BACK_MODE"]:
			mode_after_switch = str(_phase().active_moves.get("U_FB", {}).get("fall_back_mode", ""))
		if not replies[i].is_empty():
			nm._on_web_relay_message(replies[i])
	var client := {"hash": nm.compute_state_hash(), "flag": gs.state.units.U_FB.flags.get(FLAG_DE, {}).duplicate(true),
		"wounds": _wounds(), "m0": _pos("U_FB", 0), "shocked": bool(gs.state.units.U_FB.flags.get("battle_shocked", false)),
		"bs": _bs_lines(log1), "mode": mode_after_switch, "refused_locally": refused_locally,
		"desyncs": desyncs.duplicate(), "pending": nm._pending_optimistic_actions.size()}
	return {"host": host, "client": client, "host_rejections": host_rejections}

func _brief(r: Dictionary) -> String:
	return "host{flag=%s wounds=%s m0=%s bs=%s rejected=%s} client{mode=%s flag=%s wounds=%s m0=%s bs=%s refused_locally=%s desyncs=%s pending=%d}" % [
		str(r.host.flag.get("rolls", [])), str(r.host.wounds), str(r.host.m0), str(r.host.bs), str(r.host_rejections),
		r.client.mode, str(r.client.flag.get("rolls", [])), str(r.client.wounds), str(r.client.m0), str(r.client.bs),
		str(r.client.refused_locally), str(r.client.desyncs), int(r.client.pending)]

func _run_tests():
	if _ran:
		return
	_ran = true
	print("\n=== test_ea08_fall_back_online_client_11e ===\n")
	gs = root.get_node_or_null("GameState")
	pm = root.get_node_or_null("PhaseManager")
	tm = root.get_node_or_null("TerrainManager")
	nm = root.get_node_or_null("NetworkManager")
	var rules = root.get_node_or_null("RulesEngine")
	if gs == null or pm == null or tm == null or nm == null or rules == null:
		_check("autoloads reachable", false)
		_finish()
		return
	var prev_edition: int = GameConstants.edition
	var prev_terrain: Array = tm.terrain_features.duplicate(true)
	var prev_state: Dictionary = gs.state.duplicate(true)
	rules.set_test_seed(-1)  # real randomness: an unseeded roll cannot match by accident
	GameConstants.edition = 11
	tm.terrain_features = []
	base_state = gs.state.duplicate(true)
	base_state["board"]["terrain"] = []
	var fake_src := "extends Node\nvar is_connected: bool = true\nvar sent: Array = []\nfunc send_game_data(d: Dictionary) -> void:\n\tsent.append(d)\n"
	var scr := GDScript.new()
	scr.source_code = fake_src
	scr.reload()
	relay = Node.new()
	relay.set_script(scr)
	root.add_child(relay)
	nm.desync_detected.connect(func(t): desyncs.append(str(t)))

	print("-- the actions the movement panel sends are run by the client --")
	_check("SET_FALL_BACK_MODE is one of NetworkManager.DETERMINISTIC_ACTIONS (the client runs it with the action's rng_seed)",
		"SET_FALL_BACK_MODE" in nm.DETERMINISTIC_ACTIONS)

	for flow in ["A", "B"]:
		var title: String = "box ticked after Fall Back (SET_FALL_BACK_MODE)" if flow == "A" else "box ticked before Fall Back (BEGIN_FALL_BACK payload)"
		for seeds in [[11, 22, 33], [4242, 5151, 6060], [987654, 123456, 777777]]:
			print("\n-- (%s) %s, seeds %s --" % [flow, title, str(seeds)])
			var r := _run_flow(flow, seeds)
			_check("(%s) the host accepts every action of the guest's Desperate Escape" % flow, r.host_rejections.is_empty(), _brief(r))
			_check("(%s) the host moved m0 through the Witchseeker" % flow, r.host.m0.distance_to(Vector2(400, 800)) < 0.5, _brief(r))
			_check("(%s) client: the move is a Desperate Escape on the client too" % flow, r.client.mode == "desperate_escape", _brief(r))
			_check("(%s) client: no action is refused locally — the drag through the enemy model reaches the host" % flow,
				r.client.refused_locally.is_empty(), _brief(r))
			_check("(%s) client: the hazard rolls are the host's (seeded by the action)" % flow,
				not r.host.flag.is_empty() and _rolls(r.client.flag) == _rolls(r.host.flag), _brief(r))
			_check("(%s) client: the hazard mortal wounds are the host's" % flow, r.client.wounds == r.host.wounds, _brief(r))
			_check("(%s) client: m0 ends where the host put it" % flow, r.client.m0.distance_to(r.host.m0) < 0.5, _brief(r))
			_check("(%s) client: the AFTER MOVING battle-shock roll is the host's (seeded by CONFIRM_UNIT_MOVE)" % flow,
				r.host.bs.size() == 1 and r.client.bs == r.host.bs and r.client.shocked == r.host.shocked, _brief(r))
			_check("(%s) client: every optimistic action confirmed, no desync detected, the same state hash" % flow,
				r.client.desyncs.is_empty() and int(r.client.pending) == 0 and int(r.client.hash) == int(r.host.hash), _brief(r))

	print("\n-- (C) backstop: the synced hazard record marks the move as a Desperate Escape --")
	_setup()
	nm.is_online_host = false
	nm.web_relay_mode = false  # plain local phase calls from here
	var phase = _phase()
	phase.execute_action({"type": "BEGIN_FALL_BACK", "actor_unit_id": "U_FB", "player": 2, "payload": {}})
	var stage_through := {"type": "STAGE_MODEL_MOVE", "actor_unit_id": "U_FB", "player": 2,
		"payload": {"model_id": "m0", "dest": [400.0, 800.0], "rotation": 0.0}}
	var v0: Dictionary = phase.validate_action(stage_through)
	_check("control: an Ordered Retreat without a hazard record is refused through the enemy model",
		not v0.get("valid", true) and ERR_OR in v0.get("errors", []), str(v0))
	# The host's SET_FALL_BACK_MODE result reached this peer (its diff), but the
	# phase-local record still says Ordered Retreat.
	gs.state.units.U_FB.flags[FLAG_DE] = {"rolls": [3, 4, 5, 6, 6], "failures": 0, "mortal_wounds": 0}
	phase.game_state_snapshot = gs.create_snapshot()
	var v1: Dictionary = phase.validate_action(stage_through)
	_check("with the synced hazard record the drag through the enemy model is legal", v1.get("valid", false), str(v1))
	var has_get: bool = phase.has_method("get_fall_back_mode")
	_check("MovementPhase.get_fall_back_mode reads it as a Desperate Escape (the movement panel's mode line)",
		has_get and str(phase.get_fall_back_mode("U_FB")) == "desperate_escape",
		"has=%s mode=%s" % [str(has_get), str(phase.get_fall_back_mode("U_FB")) if has_get else "-"])
	var sv: Dictionary = phase.validate_action({"type": "SET_FALL_BACK_MODE", "actor_unit_id": "U_FB", "player": 2,
		"payload": {"fall_back_mode": "ordered_retreat"}})
	_check("... and it cannot be switched back to Ordered Retreat", not sv.get("valid", true), str(sv))

	nm.web_relay_mode = false
	nm.is_online_host = false
	nm.web_relay = null
	nm.peer_to_player_map = {}
	nm.reset_optimistic_state()
	relay.queue_free()
	tm.terrain_features = prev_terrain
	gs.state = prev_state
	GameConstants.edition = prev_edition
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
