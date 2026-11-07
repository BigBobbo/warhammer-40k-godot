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
#   * 0 deployment actions refused by the phase — counted at the source by
#     AIPlayer (DeploymentEval.count_rejected_deploy_actions over
#     AIPlayer.get_deploy_rejections(): first tries, retries, the reserves
#     fallback), cross-checked by the legacy GameEventLog "deployment failed ("
#     count and no "(retry" action — and 0 FormationBuilder gate rejections,
#   * every unit that was deployable when DEPLOYMENT began is on the table or
#     embarked (declared reserves stay declared),
#   * DeploymentEval.audit_legality: 0 violations (zone / Infiltrators, walls,
#     board, overlaps both ways, coherency with attached units merged);
#   * with attachments: every attached character was set up WITH its bodyguard
#     (COMPOSITE_DEPLOY) and its attached unit is coherent as one unit.
# Plus: the first config replayed gives the identical board (determinism; the
# reference is CONFIGS[0]'s own digest — a replay that cannot run is a FAIL).
#
# Attached leaders (C-2): the gate scenario's pairs (each Deffkilla Wartrike
# leads a 6-bike Warbikers unit, both seats) on the harness's Search and
# Destroy layout and on the layouts where they used to be forced into reserves
# (growth seeds only near the spot, L2-2) or took Wazdakka's last set-up (the
# unguarded column spot, C-1); and the L2-2 regression army — 20 Boyz led by a
# 40 mm + a 32 mm character in place of three P1 units.
#
# Wall clock: PER_CONFIG_TIMEOUT_MS is a generous HANG guard (a config that
# times out is NAMED before the next one starts); the file stays well under
# tests/run_pretrigger_tests.sh's 180 s kill (FILE_BUDGET_MS). Work per drop is
# asserted by counts in test_ai_deploy_terrain_11e.gd.
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
	# [fixture, zone ("fixture" = keep the save's own board; "layout@zone" = that
	#  terrain layout on that map), seed, edition, note, setup ("" / "gate" /
	#  "boyz_small")]
	["mirror_orks_2000_predeploy", "fixture", 7, 11, "crucible triangle, 6-bike ovals, Stompa", ""],
	["mirror_orks_2000_predeploy", "hammer_anvil", 7, 11, "rectangular 18\" strips", ""],
	["mirror_orks_2000_predeploy", "dawn_of_war", 7, 11, "long-edge strips", ""],
	["mirror_orks_2000_predeploy", "search_and_destroy", 7, 11, "concave L-shaped quarters", ""],
	["mirror_orks_2000_predeploy", "sweeping_engagement", 7, 11, "stepped zones", ""],
	["asym_2000_predeploy", "fixture", 7, 11, "Custodes vs Orks, round + oval bases", ""],
	["mirror_orks_2000_predeploy", "fixture", 7, 10, "edition 10 (2 neighbours at 7+, no envelope)", ""],
	["bw_load_deploy_pretrigger", "fixture", 7, 11, "attached Big Meks + Battlewagon carrying Gretchin", ""],
	["mirror_orks_2000_predeploy", "search_and_destroy", 7, 11, "Wartrikes leading Warbikers (C-2: grown set-ups, L2-2)", "gate"],
	["mirror_orks_2000_predeploy", "disruption_vs_reconnaissance_3@search_and_destroy", 7, 11, "Wartrikes leading Warbikers (C-1: Wazdakka keeps its room)", "gate"],
	["mirror_orks_2000_predeploy", "reconnaissance_vs_reconnaissance_2@crucible_of_battle", 7, 11, "Wartrikes leading Warbikers (L2-2 growth)", "gate"],
	["mirror_orks_2000_predeploy", "tipping_point", 7, 11, "20 Boyz + 40 mm / 32 mm leaders (L2-2)", "boyz_small"],
	["mirror_orks_2000_predeploy", "sweeping_engagement", 7, 11, "20 Boyz + 40 mm / 32 mm leaders (L2-2)", "boyz_small"],
]
# The gate scenario's attachments (ai_deploy_p0_legal_formations), both seats.
const GATE_PAIRS := {"U_DEFFKILLA_WARTRIKE_A": "U_WARBIKERS_C", "U_DEFFKILLA_WARTRIKE_B": "U_WARBIKERS_D"}
const PER_CONFIG_TIMEOUT_MS := 45000   # a hang guard, not a speed assertion
const FILE_BUDGET_MS := 150000
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
		for i in range(CONFIGS.size()):
			var c: Array = CONFIGS[i]
			if Time.get_ticks_msec() - _t_file > FILE_BUDGET_MS:
				_assert(false, "[%s/%s ed%d] not run: the file budget of %d s is spent" % [c[0], c[1], int(c[3]), FILE_BUDGET_MS / 1000])
				continue
			var d: String = await _run_config(str(c[0]), str(c[1]), int(c[2]), int(c[3]), str(c[4]), str(c[5]))
			if i == 0:
				first_digest = d   # L6-8: the reference is CONFIGS[0]'s own board, or nothing
		# Determinism: the first config again, same seed -> the same board.
		var c0: Array = CONFIGS[0]
		if first_digest == "":
			_assert(false, "determinism: CONFIGS[0] (%s/%s) produced no board to replay" % [c0[0], c0[1]])
		elif Time.get_ticks_msec() - _t_file > FILE_BUDGET_MS:
			_assert(false, "determinism replay not run: the file budget of %d s is spent" % (FILE_BUDGET_MS / 1000))
		else:
			var again: String = await _run_config(str(c0[0]), str(c0[1]), int(c0[2]), int(c0[3]), "determinism replay", str(c0[5]))
			_assert(again != "" and again == first_digest,
				"same fixture + seed reproduces the same deployed board (%s vs %s)" % [again.substr(0, 8), first_digest.substr(0, 8)])
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

func _setup_board(zone_spec: String) -> void:
	if zone_spec == "fixture":
		return
	var zone := zone_spec
	var layout := ""
	if zone_spec.contains("@"):
		layout = zone_spec.split("@")[0]
		zone = zone_spec.split("@")[1]
	else:
		layout = LAYOUT_FOR_ZONE[zone]
	TMN.load_terrain_layout(layout)
	GS.state["board"]["terrain_layout"] = layout
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

func _attach_pairs(pairs: Dictionary) -> int:
	"""Attach each CHARACTER to its bodyguard as Declare Battle Formations
	leaves them (19.01), on both seats (a second seat's copy is keyed _P2)."""
	var n := 0
	for cid0 in pairs:
		for sfx in ["", "_P2"]:
			var cid: String = str(cid0) + str(sfx)
			var bid: String = str(pairs[cid0]) + str(sfx)
			if not GS.state.units.has(cid) or not GS.state.units.has(bid):
				continue
			var bg: Dictionary = GS.state.units[bid]
			var ad = bg.get("attachment_data", {})
			if ad == null:
				ad = {}
			var lst: Array = ad.get("attached_characters", [])
			if not (cid in lst):
				lst.append(cid)
			ad["attached_characters"] = lst
			bg["attachment_data"] = ad
			GS.state.units[cid]["attached_to"] = bid
			n += 1
	return n

func _add_unit(uid: String, owner: int, n: int, base_mm: int, keywords: Array, extra: Dictionary = {}) -> void:
	var ms: Array = []
	for i in range(n):
		ms.append({"id": "m%d" % (i + 1), "alive": true, "position": null, "rotation": 0.0, "wounds": 1, "current_wounds": 1,
			"base_mm": base_mm, "base_type": "circular"})
	var u := {"id": uid, "owner": owner, "status": 0, "models": ms, "flags": {},
		"meta": {"name": uid, "keywords": keywords, "abilities": [], "points": 50,
			"stats": {"move": 6, "toughness": 5, "save": 5, "wounds": 1, "leadership": 7, "objective_control": 2}, "weapons": []}}
	for k in extra:
		u[k] = extra[k]
	GS.state.units[uid] = u

func _apply_setup(setup: String) -> String:
	"""Config setup on top of the fixture. "gate": the gate's attached
	Wartrikes. "boyz_small" (L2-2 regression, the reviewer's verifier probe
	v_ai_flow3 V_SWAP=1 V_LEADER=small): P1 drops Wazdakka Gutsmek and
	Stormboyz Gamma / Delta for 20 Boyz (32 mm) led by a 40 mm and a 32 mm
	CHARACTER. Returns a note for the log."""
	if setup == "gate":
		return "%d attached Wartrikes" % _attach_pairs(GATE_PAIRS)
	if setup == "boyz_small":
		for rid in ["U_WAZDAKKA_GUTSMEK_A", "U_STORMBOYZ_C", "U_STORMBOYZ_D"]:
			GS.state.units.erase(rid)
		_add_unit("T_BOYZ", 1, 20, 32, ["INFANTRY", "ORKS"], {"attachment_data": {"attached_characters": ["T_BOSS", "T_PAINBOY"]}})
		_add_unit("T_BOSS", 1, 1, 40, ["CHARACTER", "INFANTRY", "ORKS"], {"attached_to": "T_BOYZ"})
		_add_unit("T_PAINBOY", 1, 1, 32, ["CHARACTER", "INFANTRY", "ORKS"], {"attached_to": "T_BOYZ"})
		return "20 Boyz + 40 mm / 32 mm leaders for P1"
	return ""

func _run_config(fix: String, zone: String, seed_v: int, edition: int, note: String, setup: String = "") -> String:
	var tag := "%s/%s/s%d/ed%d%s" % [fix, zone, seed_v, edition, "" if setup == "" else "/" + setup]
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
	var setup_note := _apply_setup(setup)
	if setup_note != "":
		print("  setup: %s" % setup_note)
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
	AIDecisionMaker.reset_deploy_drop_stats()
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
		# P0.4: the gate metric is AIPlayer's own record of every refused
		# deployment-type action (first tries, retries, the reserves fallback);
		# the legacy game-log count and the "(retry" action-log entries are kept
		# as cross-checks.
		var rejected: int = DE.count_rejected_deploy_actions(AI.get_deploy_rejections(), p)
		var failed: int = DE.count_failed_deploy_attempts(GEL.entries, p)
		var retries := 0
		for entry in alog:
			if int(entry.get("player", 0)) == p and str(entry.get("description", "")).contains("(retry"):
				retries += 1
		_check(tag, forced == 0, "P%d: 0 units forced into Strategic Reserves (got %d)" % [p, forced])
		_check(tag, rejected == 0 and failed == 0 and retries == 0,
			"P%d: 0 deployment actions refused by the phase (rejected %d, game-log rejections %d, retries %d)" % [p, rejected, failed, retries])
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
	var dd: Dictionary = _latch.get("drop_stats", {})
	print("  %s: config %d ms (latch eval+audit %d ms); builder %s; worst drop %.0f ms (%s), per-drop max evals %d fresh %d growth %d" % [
		tag, Time.get_ticks_msec() - t_cfg, int(_latch.eval_ms), str(stats), float(dd.get("max_us", 0)) / 1000.0, str(dd.get("max_unit", "")),
		int(dd.get("max_evals", 0)), int(dd.get("max_fresh", 0)), int(dd.get("max_grow_work", 0))])
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
		"fb_stats": FB.stats(), "drop_stats": AIDecisionMaker.deploy_drop_stats(), "phase": int(new_phase), "eval_ms": Time.get_ticks_msec() - t}
