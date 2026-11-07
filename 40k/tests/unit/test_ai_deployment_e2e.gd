extends SceneTree

# Headless END-TO-END AI deployment through the REAL production path
# (docs/AI_DEPLOYMENT_PLAN.md P0.1, DECISIONS D1-D5):
#   AIPlayer._process -> _evaluate_and_act -> _execute_next_action ->
#   AIDecisionMaker._decide_deployment (formula + FormationBuilder) ->
#   NetworkIntegration.route_action -> PhaseManager's DeploymentPhase
#   (validate + process, TurnManager alternation, TITANIC skips) and, on a
#   rejection, the real AIPlayer retry / _fallback_to_reserves.
# A phase_changed hook switches both AI seats off the instant DEPLOYMENT ends
# (synchronously, inside the action that placed the last unit), so the board is
# graded exactly as deployment left it — with DeploymentEval only.
#
# Per config and seat:
#   * 0 units forced into Strategic Reserves (DeploymentEval.count_forced_reserves),
#   * 0 placements refused by the phase (GameEventLog "deployment failed (",
#     no "(retry" action) and 0 FormationBuilder gate rejections,
#   * every unit that was deployable when DEPLOYMENT began is on the table or
#     embarked (declared reserves stay declared),
#   * DeploymentEval.audit_legality: 0 violations (zone / Infiltrators, walls,
#     board, overlaps both ways, coherency with attached units merged);
#   * with attachments: every attached character was set up WITH its bodyguard
#     (COMPOSITE_DEPLOY) and its attached unit is coherent as one unit.
# Plus: the first config replayed gives the identical board (determinism).
#
# Budget: each config must finish deployment within PER_CONFIG_TIMEOUT_MS and
# the file stays under ~150 s (tests/run_pretrigger_tests.sh kills a file at
# 180 s); a config that times out is NAMED before the next one starts.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_deployment_e2e.gd

const LAYOUT_FOR_ZONE := {   # tools/deploy_harness.py LAYOUT_FOR_ZONE
	"crucible_of_battle": "take_and_hold_mirror_1",
	"hammer_anvil": "purge_the_foe_vs_priority_assets_3",
	"dawn_of_war": "take_and_hold_mirror_2",
	"search_and_destroy": "disruption_vs_priority_assets_3",
	"sweeping_engagement": "disruption_vs_disruption_3",
	"tipping_point": "disruption_vs_disruption_2",
}
const CONFIGS := [
	# [fixture, zone ("fixture" = keep the save's own board), seed, edition, note]
	["mirror_orks_2000_predeploy", "fixture", 7, 11, "crucible triangle, 6-bike ovals, Stompa"],
	["mirror_orks_2000_predeploy", "hammer_anvil", 7, 11, "rectangular 18\" strips"],
	["mirror_orks_2000_predeploy", "dawn_of_war", 7, 11, "long-edge strips"],
	["mirror_orks_2000_predeploy", "search_and_destroy", 7, 11, "concave L-shaped quarters"],
	["mirror_orks_2000_predeploy", "sweeping_engagement", 7, 11, "stepped zones"],
	["asym_2000_predeploy", "fixture", 7, 11, "Custodes vs Orks, round + oval bases"],
	["mirror_orks_2000_predeploy", "fixture", 7, 10, "edition 10 (2 neighbours at 7+, no envelope)"],
	["bw_load_deploy_pretrigger", "fixture", 7, 11, "attached Big Meks + Battlewagon carrying Gretchin"],
]
const PER_CONFIG_TIMEOUT_MS := 16000
const FILE_BUDGET_MS := 140000
const TIME_SCALE := 8.0          # AI pacing only; decisions do not depend on it

var DE
var FB
var GS
var PM
var AI
var SL
var GEL
var TMN
var MM

var _latch: Dictionary = {}
var _armed := false
var _pass_count := 0
var _fail_count := 0
var _failed_configs: Array = []
var _t_file := 0

func _init():
	create_timer(0.3).timeout.connect(_run)

func _run():
	print("\n=== AI deployment end-to-end (P0.1) Tests ===\n")
	_t_file = Time.get_ticks_msec()
	DE = load("res://scripts/ai/DeploymentEval.gd")
	FB = load("res://scripts/ai/FormationBuilder.gd")
	GS = root.get_node_or_null("GameState")
	PM = root.get_node_or_null("PhaseManager")
	AI = root.get_node_or_null("AIPlayer")
	SL = root.get_node_or_null("SaveLoadManager")
	GEL = root.get_node_or_null("GameEventLog")
	TMN = root.get_node_or_null("TerrainManager")
	MM = root.get_node_or_null("MissionManager")
	if DE == null or FB == null or GS == null or PM == null or AI == null or SL == null or GEL == null or TMN == null or MM == null:
		_assert(false, "DeploymentEval, FormationBuilder + autoloads reachable")
	else:
		PM.phase_changed.connect(_on_phase_changed)
		var first_digest := ""
		for c in CONFIGS:
			if Time.get_ticks_msec() - _t_file > FILE_BUDGET_MS:
				_assert(false, "[%s/%s ed%d] not run: the file budget of %d s is spent" % [c[0], c[1], int(c[3]), FILE_BUDGET_MS / 1000])
				continue
			var d: String = await _run_config(str(c[0]), str(c[1]), int(c[2]), int(c[3]), str(c[4]))
			if first_digest == "":
				first_digest = d
		# Determinism: the first config again, same seed -> the same board.
		if first_digest != "" and Time.get_ticks_msec() - _t_file < FILE_BUDGET_MS - PER_CONFIG_TIMEOUT_MS:
			var c0: Array = CONFIGS[0]
			var again: String = await _run_config(str(c0[0]), str(c0[1]), int(c0[2]), int(c0[3]), "determinism replay")
			_assert(again != "" and again == first_digest,
				"same fixture + seed reproduces the same deployed board (%s vs %s)" % [again.substr(0, 8), first_digest.substr(0, 8)])
		else:
			print("NOTE: determinism replay skipped (first config failed or the file budget is nearly spent)")
		print("E2E total %d ms" % (Time.get_ticks_msec() - _t_file))
	Engine.time_scale = 1.0
	GameConstants.edition = 11
	if not _failed_configs.is_empty():
		print("FAILED CONFIGS: %s" % ", ".join(_failed_configs))
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

func _check(tag: String, condition: bool, message: String) -> void:
	_assert(condition, "[%s] %s" % [tag, message])
	if not condition and not (tag in _failed_configs):
		_failed_configs.append(tag)

func _setup_board(zone: String) -> void:
	if zone == "fixture":
		return
	TMN.load_terrain_layout(LAYOUT_FOR_ZONE[zone])
	GS.state["board"]["terrain_layout"] = LAYOUT_FOR_ZONE[zone]
	var zs = DeploymentZoneData.get_zones(zone)
	var dz: Array = []
	for i in range(zs.size()):
		dz.append(zs[i] if zs[i] is Dictionary else {"player": i + 1, "poly": zs[i]})
	GS.state["board"]["deployment_zones"] = dz
	GS.state["meta"]["deployment_type"] = zone
	MM._setup_objectives_for_deployment(zone)

func _deployable_at_start() -> Dictionary:
	"""{player: [unit ids the AI must set up]} — what DeploymentPhase offers
	(not embarked, not attached, not in reserves, UNDEPLOYED) plus the
	UNDEPLOYED characters attached to those bodyguards (set up with them)."""
	var out := {1: [], 2: []}
	var units: Dictionary = GS.state.units
	for uid in units:
		var u: Dictionary = units[uid]
		var p := int(u.get("owner", 0))
		if not out.has(p) or int(u.get("status", 0)) != 0:
			continue
		if u.get("embarked_in", null) != null or u.get("attached_to", null) != null:
			continue
		out[p].append(str(uid))
		for cid in u.get("attachment_data", {}).get("attached_characters", []):
			if units.has(cid) and int(units[cid].get("status", 0)) == 0:
				out[p].append(str(cid))
	return out

func _attached_bodyguards() -> Array:
	var out: Array = []
	for uid in GS.state.units:
		var u: Dictionary = GS.state.units[uid]
		if int(u.get("status", 0)) != 0 or u.get("embarked_in", null) != null or u.get("attached_to", null) != null:
			continue
		for cid in u.get("attachment_data", {}).get("attached_characters", []):
			if GS.state.units.has(cid) and int(GS.state.units[cid].get("status", 0)) == 0:
				out.append(str(uid))
				break
	return out

func _run_config(fix: String, zone: String, seed_v: int, edition: int, note: String) -> String:
	var tag := "%s/%s/s%d/ed%d" % [fix, zone, seed_v, edition]
	print("\n-- %s (%s) --" % [tag, note])
	var t_cfg := Time.get_ticks_msec()
	_latch = {}
	_armed = false
	AI.enabled = false
	AI.ai_players = {1: false, 2: false}
	if not SL.load_game_from_file_path("res://tests/saves/%s.w40ksave" % fix):
		_check(tag, false, "fixture loads")
		return ""
	GameConstants.edition = edition
	_setup_board(zone)
	var gc = GS.state["meta"].get("game_config", {})
	if gc == null:
		gc = {}
	gc["player1_type"] = "AI"
	gc["player2_type"] = "AI"
	GS.state["meta"]["game_config"] = gc
	root.get_node("RulesEngine").set_test_seed(seed_v)
	AIDecisionMaker.set_ai_seed(seed_v)
	GEL.clear()
	FB.reset_stats()
	var expect := _deployable_at_start()
	var attached_bgs := _attached_bodyguards()
	var reserves_at_start := {1: 0, 2: 0}
	for uid in GS.state.units:
		var u: Dictionary = GS.state.units[uid]
		if int(u.get("status", 0)) == 7 and reserves_at_start.has(int(u.get("owner", 0))):
			reserves_at_start[int(u.owner)] += 1
	PM.transition_to_phase(1)             # DEPLOYMENT (TurnManager seats the first deployer)
	_armed = true
	AI.configure({1: "AI", 2: "AI"})       # clears the action log, plans and profiles
	AIDecisionMaker.clear_all_plans()
	AIDecisionMaker._config_overrides["PLANS_ENABLED"] = 0.0
	AI.set_ai_speed_preset(0)
	AI.set_spectator_speed_index(4)
	Engine.time_scale = TIME_SCALE
	var t0 := Time.get_ticks_msec()
	while _latch.is_empty() and Time.get_ticks_msec() - t0 < PER_CONFIG_TIMEOUT_MS:
		await process_frame
	Engine.time_scale = 1.0
	if _latch.is_empty():
		AI.ai_players = {1: false, 2: false}
		var und := []
		for p in [1, 2]:
			und.append(int(DE.evaluate(GS.state, p, {}).undeployed))
		_check(tag, false, "deployment ended within %d s — TIMED OUT (still undeployed: P1 %d, P2 %d)" % [PER_CONFIG_TIMEOUT_MS / 1000, und[0], und[1]])
		GameConstants.edition = 11
		return ""
	_check(tag, true, "deployment ended in %d ms" % (Time.get_ticks_msec() - t0))
	for i in range(5):                    # let the AI's call stack unwind (last-unit fallback log line)
		await process_frame
	_check(tag, not AI.is_ai_player(1) and not AI.is_ai_player(2) and int(GS.get_current_phase()) != 1
		and DE.positions_digest(GS.state) == _latch.digest,
		"the AI stopped at the end of deployment and nothing moved after (phase %d)" % int(GS.get_current_phase()))
	var alog: Array = AI.get_action_log()
	var stats: Dictionary = _latch.fb_stats
	for p in [1, 2]:
		var e: Dictionary = _latch.eval[p]
		var forced: int = DE.count_forced_reserves(alog, p)
		var failed: int = DE.count_failed_deploy_attempts(GEL.entries, p)
		var retries := 0
		for entry in alog:
			if int(entry.get("player", 0)) == p and str(entry.get("description", "")).contains("(retry"):
				retries += 1
		_check(tag, forced == 0, "P%d: 0 units forced into Strategic Reserves (got %d)" % [p, forced])
		_check(tag, failed == 0 and retries == 0, "P%d: 0 placements refused by the phase (rejections %d, retries %d)" % [p, failed, retries])
		_check(tag, int(e.in_reserves) == int(reserves_at_start[p]),
			"P%d: no unit added to reserves (in reserves %d, declared %d)" % [p, int(e.in_reserves), int(reserves_at_start[p])])
		var missing: Array = []
		for uid in expect[p]:
			var u: Dictionary = GS.state.units[uid]
			var embarked: bool = u.get("embarked_in", null) != null and str(u.get("embarked_in", "")) != ""
			if not embarked and not DE.is_on_table(u):
				missing.append("%s(status %d)" % [uid, int(u.get("status", 0))])
		_check(tag, missing.is_empty(), "P%d: all %d deployable units are on the table or embarked (missing: %s)" % [p, expect[p].size(), str(missing)])
	_check(tag, int(stats.get("gate_rejections", 0)) == 0 and int(stats.get("no_legal", 0)) == 0,
		"FormationBuilder: %d builds, 0 gate rejections, 0 'no legal set-up' (got %d / %d), worst drop %.0f ms (%s)" % [
			int(stats.get("builds", 0)), int(stats.get("gate_rejections", 0)), int(stats.get("no_legal", 0)),
			float(stats.get("max_us", 0)) / 1000.0, str(stats.get("max_unit", ""))])
	if not attached_bgs.is_empty():
		var composite := {}
		for entry in alog:
			if str(entry.get("action_type", "")) == "COMPOSITE_DEPLOY":
				composite[int(entry.get("player", 0))] = int(composite.get(int(entry.get("player", 0)), 0)) + 1
		var placed_with := 0
		for bg in attached_bgs:
			var ok := true
			for cid in GS.state.units[bg].get("attachment_data", {}).get("attached_characters", []):
				if not DE.is_on_table(GS.state.units[cid]):
					ok = false
			if ok:
				placed_with += 1
		var n_comp := int(composite.get(1, 0)) + int(composite.get(2, 0))
		_check(tag, placed_with == attached_bgs.size() and n_comp >= attached_bgs.size(),
			"every attached character was set up with its bodyguard (%d/%d attached units, %d COMPOSITE_DEPLOY actions)" % [
				placed_with, attached_bgs.size(), n_comp])
	var audit: Dictionary = _latch.audit
	_check(tag, int(audit.violations) == 0, "legality audit: 0 violations over %d models (got %d: %s)" % [int(audit.models), int(audit.violations), str(audit.problems)])
	print("  %s: config %d ms (latch eval+audit %d ms); builder %s" % [tag, Time.get_ticks_msec() - t_cfg, int(_latch.eval_ms), str(stats)])
	GameConstants.edition = 11
	return str(_latch.digest)

func _on_phase_changed(new_phase) -> void:
	# Synchronous, inside the action that placed the last unit.
	if not _armed or not _latch.is_empty() or int(new_phase) == 1:
		return
	AI.ai_players = {1: false, 2: false}
	var t := Time.get_ticks_msec()
	var ev := {}
	for p in [1, 2]:
		ev[p] = DE.evaluate(GS.state, p, {})
	_latch = {"eval": ev, "audit": DE.audit_legality(GS.state), "digest": DE.positions_digest(GS.state),
		"fb_stats": FB.stats(), "phase": int(new_phase), "eval_ms": Time.get_ticks_msec() - t}
