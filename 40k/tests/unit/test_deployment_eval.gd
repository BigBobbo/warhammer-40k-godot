extends SceneTree

# tests/unit/test_deployment_eval.gd (P0.4, docs/AI_DEPLOYMENT_PLAN.md §5.8).
#
# DeploymentEval is a pure read of GameState-shaped data that delegates every
# rules question to the engine's own predicates; these checks pin ITS logic
# (aggregation, classification, log parsing, purity) and the producer -> metric
# contracts with AIPlayer / GameEventLog — not the terrain oracle itself, so
# oracle-dependent cases first ASK the oracle for a hidden / open spot.
#
# The rejected-placement contract (verdict tests_and_gate: "make the counter
# hard to fool"): AIPlayer records every refused deployment-type action AT THE
# SOURCE. Here a really-invalid DEPLOY_UNIT, COMPOSITE_DEPLOY, PLACE_IN_RESERVES
# and EMBARK_UNITS_DEPLOYMENT each go through the REAL AIPlayer path —
# _execute_next_action with the decision supplied through the existing AB-SEAT
# seam (AIPlayer._seat_dm), then NetworkIntegration.route_action -> the real
# DeploymentPhase -> AIPlayer's real failure handling (builder retry) — and the
# count must be exactly 1. So do an accepted K-card suggestion and the reserves
# fallback refused by the 50% caps.
#
# Run with: godot --headless --path . -s tests/unit/test_deployment_eval.gd
#
# NOTE: nothing autoload-dependent is preloaded (see test_ai_plan_deployment.gd
# header); scripts are load()ed and autoloads fetched from the tree at run time.

const DE_PATH := "res://scripts/ai/DeploymentEval.gd"
const FIXTURE := "res://tests/saves/mirror_orks_2000_predeploy.w40ksave"
const PX := 40.0
const ST_UNDEPLOYED := 0
const ST_DEPLOYED := 2
const ST_IN_RESERVES := 7

var DE      # DeploymentEval
var GS
var TM
var MEAS
var GEL
var AI
var PM
var SL

var _pass_count := 0
var _fail_count := 0

# AB-SEAT seam stand-in: AIPlayer._execute_next_action asks _dm(player).decide()
# for its decision, then routes and handles it exactly as on the AI's own turn.
class StubDecisionMaker:
	var next_decision: Dictionary = {}
	func decide(_phase, _snapshot, _available, _player) -> Dictionary:
		var d: Dictionary = next_decision.duplicate(true)
		next_decision = {}
		return d
	func reset_caches() -> void:
		pass
	func reset_army_archetype_cache() -> void:
		pass
	func clear_movement_intent(_player, _unit_id) -> void:
		pass

func _init():
	create_timer(0.3).timeout.connect(_run)

func _run():
	print("\n=== DeploymentEval (P0.4) Tests ===\n")
	DE = load(DE_PATH)
	GS = root.get_node_or_null("GameState")
	TM = root.get_node_or_null("TerrainManager")
	MEAS = root.get_node_or_null("Measurement")
	GEL = root.get_node_or_null("GameEventLog")
	AI = root.get_node_or_null("AIPlayer")
	PM = root.get_node_or_null("PhaseManager")
	SL = root.get_node_or_null("SaveLoadManager")
	if DE == null or GS == null or TM == null or MEAS == null or GEL == null or AI == null or PM == null or SL == null:
		_assert(false, "DeploymentEval + autoloads reachable")
	else:
		GameConstants.edition = 11
		_assert(SL.load_game_from_file_path(FIXTURE), "mirror_orks_2000_predeploy loads (live 11e board for the terrain oracle)")
		test_count_forced_reserves_synthetic()
		test_count_failed_deploy_attempts_via_event_log()
		test_count_rejected_deploy_actions_synthetic()
		test_real_fallback_is_counted_once()
		test_rejected_deploy_unit_counted_once()
		test_rejected_composite_deploy_counted_once()
		test_rejected_place_in_reserves_counted_once()
		test_rejected_embark_counted_once()
		test_rejected_accepted_suggestion_counted_once()
		test_refused_fallback_counted_once()
		test_evaluate_classification_and_counts()
		test_evaluate_min_gap_and_purity()
		test_home_objective()
		test_positions_digest()
		test_audit_legality()
		AI.enabled = false
		AI.ai_players = {1: false, 2: false}
		AI._seat_dm.clear()
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	print("ALL TESTS PASSED" if _fail_count == 0 else "SOME TESTS FAILED")
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

# ---------------------------------------------------------------- builders --

func _model(id: String, x_in: float, y_in: float, alive: bool = true) -> Dictionary:
	return {"id": id, "alive": alive, "base_mm": 32, "base_type": "circular",
		"position": {"x": x_in * PX, "y": y_in * PX}, "rotation": 0.0, "wounds": 1, "current_wounds": 1}

func _unit(owner: int, name: String, keywords: Array, pts: int, status: int, models: Array, oc: int = 1) -> Dictionary:
	return {"owner": owner, "status": status, "flags": {}, "embarked_in": null, "attached_to": null,
		"meta": {"name": name, "keywords": keywords, "points": pts, "stats": {"objective_control": oc}},
		"models": models}

func _state(units: Dictionary) -> Dictionary:
	return {"meta": {"phase": 1, "battle_round": 1}, "board": GS.state.board.duplicate(true), "units": units}

func _probe_unit() -> Dictionary:
	return _unit(1, "probe", ["INFANTRY"], 0, ST_DEPLOYED, [])

func _find_spot(want_hidden: bool, inside_player_zone: int = 0) -> Vector2:
	"""Ask the engine's own oracle for a point (inches) where a 32 mm INFANTRY
	model is Hidden (want_hidden) or stands in the open, clear of every terrain
	piece and wall. Optionally inside a player's deployment zone."""
	var poly: PackedVector2Array = DE.zone_polygon_px(GS.state, inside_player_zone) if inside_player_zone > 0 else PackedVector2Array()
	var pu := _probe_unit()
	for yi in range(2, 59):
		for xi in range(2, 43):
			var m := _model("p", float(xi), float(yi))
			m["position"] = Vector2(xi * PX, yi * PX)
			if inside_player_zone > 0 and not MEAS.shape_wholly_in_polygon(m.position, m, 0.0, poly):
				continue
			if want_hidden:
				if TM.is_model_hidden(m, pu):
					return Vector2(xi, yi)
			else:
				if TM.pieces_model_within(m).is_empty() and not MEAS.model_overlaps_any_wall(m, ["INFANTRY"]) and not TM.is_model_hidden(m, pu):
					# room for a 3-model line along +x
					var ok := true
					for k in [1, 2]:
						var m2 := _model("q", xi + 1.4 * k, float(yi))
						m2["position"] = Vector2((xi + 1.4 * k) * PX, yi * PX)
						if not TM.pieces_model_within(m2).is_empty() or MEAS.model_overlaps_any_wall(m2, ["INFANTRY"]):
							ok = false
						if inside_player_zone > 0 and not MEAS.shape_wholly_in_polygon(m2.position, m2, 0.0, poly):
							ok = false
					if ok:
						return Vector2(xi, yi)
	return Vector2.INF

# --- live deployment set-up for the AIPlayer contract tests ---

func _deploy_setup(seat_type: String = "AI") -> int:
	"""Fresh fixture in DEPLOYMENT with both seats `seat_type`. The AI never acts
	on its own here (enabled = false): each check drives exactly one call."""
	SL.load_game_from_file_path(FIXTURE)
	GameConstants.edition = 11
	PM.transition_to_phase(1)   # DEPLOYMENT (TurnManager seats the first deployer)
	AI._seat_dm.clear()
	AI.configure({1: seat_type, 2: seat_type})   # clears the action log + deployment rejections
	AI.enabled = false
	AI._needs_evaluation = false
	GEL.clear()
	return int(GS.get_active_player())

func _uid(base: String, player: int) -> String:
	return base if player == 1 else base + "_P2"

func _bad_positions_in_enemy_zone(player: int, n: int) -> Array:
	"""n positions in a tidy 1.3"-spaced block around the ENEMY zone's centroid:
	the formation itself is well-formed, but no model is in the player's zone."""
	var ez: PackedVector2Array = DE.zone_polygon_px(GS.state, 3 - player)
	var c := Vector2.ZERO
	for v in ez:
		c += v
	c /= float(max(1, ez.size()))
	var out: Array = []
	for i in range(n):
		out.append(c + Vector2(float(i % 4) * 1.3 * PX, float(i / 4) * 1.3 * PX))
	return out

func _zero_rotations(n: int) -> Array:
	var r: Array = []
	for i in range(n):
		r.append(0.0)
	return r

func _drive_ai_decision(player: int, decision: Dictionary) -> void:
	"""One real AIPlayer step with `decision` as the decision maker's answer."""
	var stub := StubDecisionMaker.new()
	stub.next_decision = decision
	AI._seat_dm[player] = stub
	AI._execute_next_action(player)
	AI._seat_dm.erase(player)
	AI._needs_evaluation = false

func _really_invalid(action: Dictionary) -> bool:
	var v: Dictionary = PM.current_phase_instance.validate_action(action)
	return not bool(v.get("valid", true))

func _rec_summary() -> String:
	var parts: Array = []
	for r in AI.get_deploy_rejections():
		parts.append("%s/%s/%s/P%d" % [str(r.get("action_type", "")), str(r.get("source", "")), str(r.get("unit_id", "")), int(r.get("player", 0))])
	return str(parts)

# ------------------------------------------------------------------- tests --

func test_count_forced_reserves_synthetic() -> void:
	print("\n-- count_forced_reserves: the exact entries AIPlayer writes --")
	# AIPlayer._fallback_to_reserves: capped fallback and past the caps.
	var alog := [
		{"phase": 1, "action_type": "PLACE_IN_RESERVES", "description": "Deffkoptas placed in reserves (fallback)", "player": 1},
		{"phase": 2, "action_type": "PLACE_IN_RESERVES", "description": "Warbikers placed in reserves past the caps (no legal position)", "player": 1},
		{"phase": 1, "action_type": "PLACE_IN_RESERVES", "description": "Stompa placed in reserves (fallback)", "player": 2},
		{"phase": 1, "action_type": "DEPLOY_UNIT", "description": "Deployed Gretchin (retry 1)", "player": 1},
		{"phase": 0, "action_type": "PLACE_IN_RESERVES", "description": "Deffkoptas Alpha into Strategic Reserves (plan)", "player": 1},
		"not a dictionary",
	]
	_assert(int(DE.count_forced_reserves(alog, 1)) == 2, "P1: the capped AND the past-the-caps fallback count; a chosen reserve and a retry do not")
	_assert(int(DE.count_forced_reserves(alog, 2)) == 1, "P2 counted separately")
	_assert(int(DE.count_forced_reserves([], 1)) == 0, "empty log -> 0")

func test_count_failed_deploy_attempts_via_event_log() -> void:
	print("\n-- count_failed_deploy_attempts (legacy game-log metric) --")
	GEL.clear()
	# AIPlayer: the first-rejection line and the give-up line.
	GEL.add_ai_entry(1, "Deffkoptas deployment failed (Model cannot overlap with walls this unit can't cross) — retrying")
	GEL.add_ai_entry(1, "Deffkoptas deployment failed after retries — placed in Strategic Reserves")
	GEL.add_ai_entry(2, "Gretchin deployment failed (Model cannot overlap with existing models) — retrying")
	GEL.add_ai_thinking_entry(1, "Gretchin deployment failed (thinking aloud) — retrying")
	_assert(int(DE.count_failed_deploy_attempts(GEL.entries, 1)) == 1, "P1: one first-try rejection (the give-up line and AI-thinking text do not count)")
	_assert(int(DE.count_failed_deploy_attempts(GEL.entries, 2)) == 1, "P2 counted separately")
	_assert(int(DE.count_failed_deploy_attempts(["P1: X deployment failed (y) — retrying"], 1)) == 1, "plain-string entries are read too")
	GEL.clear()

func test_count_rejected_deploy_actions_synthetic() -> void:
	print("\n-- count_rejected_deploy_actions: AIPlayer's source records --")
	var recs := [
		{"player": 1, "action_type": "DEPLOY_UNIT", "source": "decision"},
		{"player": 1, "action_type": "DEPLOY_UNIT", "source": "retry"},
		{"player": 1, "action_type": "COMPOSITE_DEPLOY", "source": "decision"},
		{"player": 1, "action_type": "PLACE_IN_RESERVES", "source": "fallback"},
		{"player": 2, "action_type": "EMBARK_UNITS_DEPLOYMENT", "source": "decision"},
		{"player": 2, "action_type": "ATTACH_CHARACTER_DEPLOYMENT", "source": "decision"},
		{"player": 2, "action_type": "PLACE_REINFORCEMENT", "source": "decision"},   # not a deployment action
		"not a dictionary",
	]
	_assert(int(DE.count_rejected_deploy_actions(recs, 1)) == 4, "P1: every deployment type and every source counts — retries and the fallback included (got %d)" % int(DE.count_rejected_deploy_actions(recs, 1)))
	_assert(int(DE.count_rejected_deploy_actions(recs, 2)) == 2, "P2: embark + attach count; a reinforcement is not a deployment action (got %d)" % int(DE.count_rejected_deploy_actions(recs, 2)))
	_assert(int(DE.count_rejected_deploy_actions(recs, 0)) == 6, "player 0 = both seats")
	_assert(int(DE.count_rejected_deploy_actions([], 1)) == 0, "no records -> 0")
	var ai_types: Array = (AI.get_script().get_script_constant_map().get("DEPLOY_ACTION_TYPES", []) as Array).duplicate()
	ai_types.sort()
	var de_types: Array = DE.DEPLOY_ACTION_TYPES.duplicate()
	de_types.sort()
	_assert(ai_types == de_types, "DeploymentEval and AIPlayer agree on the deployment action types (%s)" % str(de_types))

func test_real_fallback_is_counted_once() -> void:
	print("\n-- contract: the REAL AIPlayer fallback is counted exactly once --")
	# Drive the production last-resort path on the real DeploymentPhase, so a
	# rewrite of AIPlayer._fallback_to_reserves cannot silently stop being
	# counted by the metric the P0 gate reads.
	var p := _deploy_setup()
	var uid := _uid("U_DEFFKOPTAS_A", p)
	AI._fallback_to_reserves(p, uid, "Deffkoptas")
	_assert(int(GS.state.units[uid].get("status", -1)) == ST_IN_RESERVES, "the unit really went to Strategic Reserves (status %d)" % int(GS.state.units[uid].get("status", -1)))
	_assert(int(DE.count_forced_reserves(AI.get_action_log(), p)) == 1, "count_forced_reserves sees it once (log: %s)" % str(AI.get_action_log()))
	_assert(int(DE.count_rejected_deploy_actions(AI.get_deploy_rejections(), p)) == 0, "the caps accepted it first time: 0 rejected actions (%s)" % _rec_summary())
	_assert(int(DE.count_failed_deploy_attempts(GEL.entries, p)) == 0, "the give-up message is not counted as a rejection")
	var ev: Dictionary = DE.evaluate(GS.state, p, {})
	_assert(int(ev.in_reserves) == 1 and int(ev.reserves_points) == int(GS.state.units[uid].meta.points), "evaluate(): in_reserves=1 at %d pts (got %d / %d)" % [int(GS.state.units[uid].meta.points), int(ev.in_reserves), int(ev.reserves_points)])

func test_rejected_deploy_unit_counted_once() -> void:
	print("\n-- contract: a really-invalid DEPLOY_UNIT through the real AIPlayer path counts exactly 1 --")
	var p := _deploy_setup()
	var uid := _uid("U_GRETCHIN_A", p)
	var n: int = GS.state.units[uid].models.size()
	var bad := {"type": "DEPLOY_UNIT", "unit_id": uid, "player": p,
		"model_positions": _bad_positions_in_enemy_zone(p, n), "model_rotations": _zero_rotations(n),
		"_ai_description": "Deployed Gretchin (deliberately in the enemy zone)"}
	_assert(_really_invalid(bad), "precondition: the phase refuses this placement (every model in the enemy zone)")
	_drive_ai_decision(p, bad)
	var recs: Array = AI.get_deploy_rejections()
	_assert(int(AI.get_deploy_rejection_count(p)) == 1 and int(DE.count_rejected_deploy_actions(recs, p)) == 1,
		"exactly 1 rejection recorded for P%d (%s)" % [p, _rec_summary()])
	_assert(recs.size() == 1 and str(recs[0].action_type) == "DEPLOY_UNIT" and str(recs[0].source) == "decision"
		and str(recs[0].unit_id) == uid and str(recs[0].error) != "", "the record names DEPLOY_UNIT / decision / %s with the phase's reason" % uid)
	_assert(int(DE.count_rejected_deploy_actions(recs, 3 - p)) == 0, "the other seat has none")
	_assert(int(GS.state.units[uid].get("status", -1)) == ST_DEPLOYED, "the real builder retry then set the unit up legally (status %d)" % int(GS.state.units[uid].get("status", -1)))
	var retried := false
	for e in AI.get_action_log():
		if str(e.get("description", "")).contains("(retry 1)"):
			retried = true
	_assert(retried, "the action log shows the accepted retry")
	_assert(int(DE.count_failed_deploy_attempts(GEL.entries, p)) == 1, "the legacy game-log metric agrees for a first-try DEPLOY_UNIT rejection")

func test_rejected_composite_deploy_counted_once() -> void:
	print("\n-- contract: a really-invalid COMPOSITE_DEPLOY through the real AIPlayer path counts exactly 1 --")
	var p := _deploy_setup()
	var uid := _uid("U_GRETCHIN_B", p)
	var mek := _uid("U_MEK_A", p)
	var n: int = GS.state.units[uid].models.size()
	var pos := _bad_positions_in_enemy_zone(p, n)
	var bad := {"type": "COMPOSITE_DEPLOY", "unit_id": uid, "player": p,
		"model_positions": pos, "model_rotations": _zero_rotations(n),
		"combined_char_data": {mek: [{"model_idx": 0, "x": pos[0].x + 2.0 * PX, "y": pos[0].y, "rotation": 0.0}]},
		"_ai_description": "Deployed Gretchin with Mek (deliberately invalid)"}
	_assert(_really_invalid(bad), "precondition: the phase refuses it (enemy zone; the Mek is not even attached)")
	_drive_ai_decision(p, bad)
	var recs: Array = AI.get_deploy_rejections()
	_assert(int(DE.count_rejected_deploy_actions(recs, p)) == 1 and recs.size() == 1 and str(recs[0].action_type) == "COMPOSITE_DEPLOY",
		"exactly 1 COMPOSITE_DEPLOY rejection recorded (%s)" % _rec_summary())
	_assert(int(GS.state.units[uid].get("status", -1)) == ST_DEPLOYED, "the builder retry set the bodyguard up legally afterwards")

func test_rejected_place_in_reserves_counted_once() -> void:
	print("\n-- contract: a really-invalid PLACE_IN_RESERVES through the real AIPlayer path counts exactly 1 --")
	var p := _deploy_setup()
	var enemy_unit := _uid("U_GRETCHIN_A", 3 - p)
	var bad := {"type": "PLACE_IN_RESERVES", "unit_id": enemy_unit, "reserve_type": "strategic_reserves", "player": p,
		"_ai_description": "Enemy Gretchin into reserves (deliberately invalid)"}
	_assert(_really_invalid(bad), "precondition: the phase refuses it (not the active player's unit)")
	_drive_ai_decision(p, bad)
	var recs: Array = AI.get_deploy_rejections()
	_assert(int(DE.count_rejected_deploy_actions(recs, p)) == 1 and recs.size() == 1 and str(recs[0].action_type) == "PLACE_IN_RESERVES",
		"exactly 1 PLACE_IN_RESERVES rejection recorded (%s)" % _rec_summary())
	_assert(int(GS.state.units[enemy_unit].get("status", -1)) == ST_UNDEPLOYED, "nothing happened to the enemy unit")
	_assert(int(DE.count_failed_deploy_attempts(GEL.entries, p)) == 0, "the legacy game-log metric is blind to it (why the gate reads the source records)")

func test_rejected_embark_counted_once() -> void:
	print("\n-- contract: a really-invalid EMBARK_UNITS_DEPLOYMENT through the real AIPlayer path counts exactly 1 --")
	var p := _deploy_setup()
	var bad := {"type": "EMBARK_UNITS_DEPLOYMENT", "transport_id": _uid("U_GRETCHIN_A", p),
		"unit_ids": [_uid("U_MEK_A", p)], "player": p, "_ai_description": "Mek into Gretchin (deliberately invalid)"}
	_assert(_really_invalid(bad), "precondition: the phase refuses it (Gretchin are not a transport)")
	_drive_ai_decision(p, bad)
	var recs: Array = AI.get_deploy_rejections()
	_assert(int(DE.count_rejected_deploy_actions(recs, p)) == 1 and recs.size() == 1 and str(recs[0].action_type) == "EMBARK_UNITS_DEPLOYMENT",
		"exactly 1 EMBARK_UNITS_DEPLOYMENT rejection recorded (%s)" % _rec_summary())

func test_rejected_accepted_suggestion_counted_once() -> void:
	print("\n-- contract: a refused accepted K-card deployment suggestion counts exactly 1 --")
	var p := _deploy_setup("HUMAN")
	AI.last_suggestion_meta = {}
	var uid := _uid("U_STORMBOYZ_A", p)
	var n: int = GS.state.units[uid].models.size()
	var bad := {"type": "DEPLOY_UNIT", "unit_id": uid, "player": p,
		"model_positions": _bad_positions_in_enemy_zone(p, n), "model_rotations": _zero_rotations(n),
		"_ai_description": "Deployed Stormboyz (deliberately in the enemy zone)"}
	_assert(_really_invalid(bad), "precondition: the phase refuses this placement")
	var out: Dictionary = AI.accept_suggestion(bad)
	_assert(not bool(out.get("success", true)), "accept_suggestion reports the refusal (%s)" % str(out.get("error", "")))
	var recs: Array = AI.get_deploy_rejections()
	_assert(int(DE.count_rejected_deploy_actions(recs, p)) == 1 and recs.size() == 1 and str(recs[0].source) == "accepted_suggestion",
		"exactly 1 rejection recorded, source accepted_suggestion (%s)" % _rec_summary())

func test_refused_fallback_counted_once() -> void:
	print("\n-- contract: the reserves fallback refused by the 50% caps counts exactly 1 (then past the caps) --")
	var p := _deploy_setup()
	# Test set-up: 8 of the seat's 17 units already in Strategic Reserves, so a
	# 9th breaks the 50% unit cap (8 + 1 > 8) while the points stay under 1000.
	for base in ["U_STORMBOYZ_A", "U_STORMBOYZ_B", "U_STORMBOYZ_C", "U_STORMBOYZ_D", "U_DEFFKOPTAS_A", "U_DEFFKOPTAS_B", "U_WARBIKERS_A", "U_WARBIKERS_B"]:
		GS.state.units[_uid(base, p)]["status"] = ST_IN_RESERVES
	var uid := _uid("U_GRETCHIN_A", p)
	var reserves_action := {"type": "PLACE_IN_RESERVES", "unit_id": uid, "reserve_type": "strategic_reserves", "player": p}
	_assert(_really_invalid(reserves_action), "precondition: the caps refuse a 9th reserve")
	# The past-the-caps bypass is only for a seat that IS an AI (DeploymentPhase).
	AI.enabled = true
	AI._fallback_to_reserves(p, uid, "Gretchin")
	AI.enabled = false
	AI._needs_evaluation = false
	var recs: Array = AI.get_deploy_rejections()
	_assert(int(DE.count_rejected_deploy_actions(recs, p)) == 1 and recs.size() == 1 and str(recs[0].source) == "fallback"
		and str(recs[0].action_type) == "PLACE_IN_RESERVES", "exactly 1 rejection: the capped fallback (%s)" % _rec_summary())
	_assert(int(DE.count_forced_reserves(AI.get_action_log(), p)) == 1, "then forced past the caps, counted once by count_forced_reserves")
	_assert(int(GS.state.units[uid].get("status", -1)) == ST_IN_RESERVES, "the unit is in reserves (deployment can finish)")
	AI.configure({1: "AI", 2: "AI"})
	AI.enabled = false
	AI._needs_evaluation = false
	_assert(AI.get_deploy_rejections().is_empty(), "configure() starts a new game's count at 0")

func test_evaluate_classification_and_counts() -> void:
	print("\n-- evaluate(): hide classification and status buckets --")
	_assert(SL.load_game_from_file_path(FIXTURE), "fixture reloads")
	GameConstants.edition = 11
	var H := _find_spot(true)
	var O := _find_spot(false)
	_assert(H != Vector2.INF, "the oracle offers a Hidden spot on this layout (%s)" % str(H))
	_assert(O != Vector2.INF, "the oracle offers an open spot on this layout (%s)" % str(O))
	if H == Vector2.INF or O == Vector2.INF:
		return
	var units := {
		"FULL": _unit(1, "Full", ["INFANTRY"], 60, ST_DEPLOYED, [_model("a", H.x, H.y), _model("b", H.x, H.y), _model("c", H.x, H.y)]),
		"LEAK": _unit(1, "Leak", ["INFANTRY"], 60, ST_DEPLOYED, [_model("a", H.x, H.y), _model("b", H.x, H.y), _model("c", O.x, O.y)]),
		"OPEN": _unit(1, "Open", ["INFANTRY"], 60, ST_DEPLOYED, [_model("a", O.x, O.y), _model("b", O.x + 1.4, O.y)]),
		"SOLO": _unit(1, "Solo char", ["INFANTRY", "CHARACTER"], 60, ST_DEPLOYED, [_model("a", H.x, H.y)]),
		"VEH": _unit(1, "Truck", ["VEHICLE"], 100, ST_DEPLOYED, [_model("a", O.x, O.y)]),
		"RES": _unit(1, "Reserved", ["INFANTRY"], 120, ST_IN_RESERVES, [_model("a", 0, 0)]),
		"UND": _unit(1, "Undeployed", ["INFANTRY"], 50, ST_UNDEPLOYED, [{"id": "a", "alive": true, "position": null}]),
		"EMB": _unit(1, "Embarked", ["INFANTRY"], 50, ST_DEPLOYED, [_model("a", O.x, O.y)]),
		"FOE": _unit(2, "Foe", ["INFANTRY"], 50, ST_DEPLOYED, [_model("a", O.x, O.y + 3.0)]),
	}
	units.EMB["embarked_in"] = "VEH"
	var state := _state(units)
	var r: Dictionary = DE.evaluate(state, 1, {"per_unit": true})
	var got := "%d %d %d %d %d %d" % [int(r.units_total), int(r.on_table), int(r.in_reserves), int(r.reserves_points), int(r.undeployed), int(r.embarked)]
	_assert(got == "8 5 1 120 1 1", "status buckets total/on_table/in_reserves/pts/undeployed/embarked = 8 5 1 120 1 1 (got %s)" % got)
	var hid := "%d %d %d %d %d %d %d" % [int(r.hide_capable), int(r.hide_capable_multi), int(r.fully_hidden), int(r.fully_hidden_multi), int(r.leakers), int(r.open), int(r.non_hideable)]
	_assert(hid == "4 3 2 1 1 1 1", "hide_capable/multi/full/full_multi/leakers/open/non_hideable = 4 3 2 1 1 1 1 (got %s)" % hid)
	var by_id := {}
	for row in r.rows:
		by_id[str(row.id)] = str(row.get("hidden", "?"))
	_assert(by_id.get("LEAK", "") == "partial 2/3", "the leaker row reads 'partial 2/3' (got %s)" % by_id.get("LEAK", "?"))
	_assert(by_id.get("FULL", "") == "full" and by_id.get("OPEN", "") == "none" and by_id.get("VEH", "") == "n/a", "full / none / n/a rows (got %s)" % str(by_id))
	_assert(DE.evaluate(state, 1, {}).rows.is_empty(), "rows only with per_unit")
	_assert(int(DE.evaluate(state, 1, {}).seen_by_enemy_units_any) == -1, "visibility is opt-in (-1 when not asked)")
	var rv: Dictionary = DE.evaluate(state, 1, {"visibility": true})
	_assert(int(rv.seen_by_enemy_units_any) >= 1, "with visibility, the foe 3\" away in the open sees at least the open unit (got %d)" % int(rv.seen_by_enemy_units_any))
	var r2: Dictionary = DE.evaluate(state, 2, {})
	_assert(int(r2.units_total) == 1 and int(r2.on_table) == 1, "player 2 is evaluated on its own units only")

func test_evaluate_min_gap_and_purity() -> void:
	print("\n-- evaluate(): min gap to the enemy zone, and it never mutates --")
	# Crucible P2 zone = (0,60)-(44,30)-(44,60): the closest point to (44,20) is
	# the vertex (44,30) -> exactly 10.0".
	var state := _state({"A": _unit(1, "A", ["INFANTRY"], 10, ST_DEPLOYED, [_model("a", 44.0, 20.0)])})
	var before := var_to_str(state)
	var r: Dictionary = DE.evaluate(state, 1, {"per_unit": true, "visibility": true})
	_assert(is_equal_approx(float(r.min_gap_to_enemy_zone_in), 10.0), "min gap = 10.0\" (got %s)" % str(r.min_gap_to_enemy_zone_in))
	_assert(var_to_str(state) == before, "evaluate() left the state untouched")
	var empty: Dictionary = DE.evaluate(_state({}), 1, {})
	_assert(float(empty.min_gap_to_enemy_zone_in) == -1.0 and int(empty.units_total) == 0, "no units -> gap -1, totals 0")

func test_home_objective() -> void:
	print("\n-- home objective held by an OC>0 model (14.01 via MissionManager) --")
	var home: Dictionary = {}
	for obj in GS.state.board.objectives:
		if str(obj.get("zone", "")) == "player1":
			home = obj
	_assert(not home.is_empty(), "the fixture tags a player1 home objective")
	if home.is_empty():
		return
	var p: Vector2 = DE._vec(home.position) / PX
	var held := _state({"H": _unit(1, "Holder", ["INFANTRY"], 10, ST_DEPLOYED, [_model("a", p.x, p.y)], 2)})
	var h: Dictionary = DE.evaluate(held, 1, {}).home_objective
	_assert(bool(h.known) and bool(h.occupied), "a model on the home objective holds it (%s)" % str(h))
	held.units.H.meta.stats.objective_control = 0
	_assert(not bool(DE.evaluate(held, 1, {}).home_objective.occupied), "OC 0 does not hold it")
	var untagged := _state({})
	for obj in untagged.board.objectives:
		obj.erase("zone")
	_assert(not bool(DE.evaluate(untagged, 1, {}).home_objective.known), "no zone tags -> known=false")

func test_positions_digest() -> void:
	print("\n-- positions_digest --")
	var s1 := _state({"A": _unit(1, "A", ["INFANTRY"], 10, ST_DEPLOYED, [_model("a", 5, 5), _model("b", 6.4, 5)]),
		"B": _unit(2, "B", ["INFANTRY"], 10, ST_UNDEPLOYED, [{"id": "a", "alive": true, "position": null}])})
	var d1: String = DE.positions_digest(s1)
	_assert(d1 == DE.positions_digest(s1.duplicate(true)), "a deep copy has the same digest")
	var s2 := _state({"B": s1.units.B.duplicate(true), "A": s1.units.A.duplicate(true)})
	_assert(d1 == DE.positions_digest(s2), "independent of dictionary insertion order")
	var s3 := s1.duplicate(true)
	s3.units.A.models[1].position.x += 1.0
	_assert(d1 != DE.positions_digest(s3), "a 1 px move changes it")
	var s4 := s1.duplicate(true)
	s4.units.B.status = ST_IN_RESERVES
	_assert(d1 != DE.positions_digest(s4), "a status change changes it")
	var s5 := s1.duplicate(true)
	s5.units.A.models[0].position = Vector2(5 * PX, 5 * PX)
	_assert(d1 == DE.positions_digest(s5), "Vector2 and {x,y} positions digest the same")
	var s6 := s1.duplicate(true)
	s6.units.B.embarked_in = "A"
	_assert(d1 != DE.positions_digest(s6), "an embark that moves no model changes it (embarked_in)")
	var s7 := s1.duplicate(true)
	s7.units.B.attached_to = "A"
	_assert(d1 != DE.positions_digest(s7), "an attach that moves no model changes it (attached_to)")

func test_audit_legality() -> void:
	print("\n-- audit_legality: the phase's own predicates over the whole board --")
	var P := _find_spot(false, 1)
	_assert(P != Vector2.INF, "an open, wall-free 3-model line exists inside the P1 zone (%s)" % str(P))
	if P == Vector2.INF:
		return
	var legal := {"A": _unit(1, "A", ["INFANTRY"], 10, ST_DEPLOYED, [_model("a", P.x, P.y), _model("b", P.x + 1.4, P.y), _model("c", P.x + 2.8, P.y)])}
	var a0: Dictionary = DE.audit_legality(_state(legal))
	_assert(int(a0.violations) == 0 and int(a0.models) == 3, "a legal unit: 0 violations over 3 models (%s)" % str(a0.problems))
	var ov := legal.duplicate(true)
	ov["B"] = _unit(1, "B", ["INFANTRY"], 10, ST_DEPLOYED, [_model("a", P.x + 0.5, P.y)])
	var a1: Dictionary = DE.audit_legality(_state(ov))
	_assert(int(a1.overlap_pairs) >= 1, "another unit's base overlapping is caught (%s)" % str(a1.problems))
	var intra := legal.duplicate(true)
	intra.A.models[1].position = {"x": (P.x + 0.5) * PX, "y": P.y * PX}
	var a1b: Dictionary = DE.audit_legality(_state(intra))
	_assert(int(a1b.overlap_pairs) >= 1, "two models of the SAME unit overlapping are caught, as the phase rejects them (%s)" % str(a1b.problems))
	var out := legal.duplicate(true)
	out["C"] = _unit(1, "C", ["INFANTRY"], 10, ST_DEPLOYED, [_model("a", 22.0, 45.0)])
	var a2: Dictionary = DE.audit_legality(_state(out))
	_assert(int(a2.zone) == 1, "a model outside its zone is caught (%s)" % str(a2.problems))
	var inc := {"D": _unit(1, "D", ["INFANTRY"], 10, ST_DEPLOYED, [_model("a", P.x, P.y), _model("b", P.x + 2.8, P.y)])}
	inc.D.models[1].position = {"x": (P.x + 10.0) * PX, "y": P.y * PX}
	var a3: Dictionary = DE.audit_legality(_state(inc))
	_assert(int(a3.incoherent_units) == 1, "a unit 10\" apart is out of coherency (%s)" % str(a3.problems))
	var skip := legal.duplicate(true)
	skip["R"] = _unit(1, "R", ["INFANTRY"], 10, ST_IN_RESERVES, [_model("a", P.x + 0.5, P.y)])
	skip["U"] = _unit(1, "U", ["INFANTRY"], 10, ST_UNDEPLOYED, [_model("a", P.x + 0.5, P.y)])
	_assert(int(DE.audit_legality(_state(skip)).violations) == 0, "reserves / undeployed units are not on the table and are skipped")
	_assert(int(DE.audit_legality(_state(ov), 2).models) == 0, "player filter: P2 audits none of P1's models")
