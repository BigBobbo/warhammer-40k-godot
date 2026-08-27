extends Node

# PM-8b — run N seeded AI-vs-AI games back to back, in this process, to compare
# two plans (either of which may be "no plan").
#
# The load-bearing question — can consecutive games share a process without
# leaking state into each other? — was answered by the PM-8a spike
# (tests/bench_baselines/2026-08-11_pm8a_inline_reset_spike.md): yes, but ONLY
# with the full reset list below. With the obvious three-entry list two
# same-seed games diverged. Every entry in `_reset_between_games` earned its
# place by a measured divergence; do not trim it without re-running that spike.
#
# An autoload rather than a scene script because each game changes scene into
# Main.tscn — a Node owned by the menu scene would be freed on the first game.
#
# API:
#   start({zone_id, layout_id, mission_id, army1, army2, plan1, plan2,
#          games, seed_base, difficulty, time_scale, max_seconds_per_game})
#   cancel()
# Signals:
#   run_started(total_games)
#   game_finished(index, result)
#   run_finished(summary)
#   run_cancelled(summary)

const GameWatcherScript = preload("res://scripts/GameWatcher.gd")
const PlanValidatorScript = preload("res://scripts/PlanValidator.gd")

signal run_started(total_games: int)
signal game_finished(index: int, result: Dictionary)
signal run_finished(summary: Dictionary)
signal run_cancelled(summary: Dictionary)

const RESULTS_DIR := "user://plan_sim_results/"
const DEFAULT_GAMES: int = 5
const DEFAULT_SEED_BASE: int = 1000
const DEFAULT_DIFFICULTY: int = 3          # Competitive — the shipped default, so
#                                          benchmarks measure the AI players face.
#                                          NOTE: every baseline before 2026-08-27 was
#                                          recorded at Normal (1); pass difficulty
#                                          explicitly when comparing against those.
const DEFAULT_TIME_SCALE: float = 10.0
const DEFAULT_MAX_SECONDS: float = 900.0
const DEFAULT_STALL_SECONDS: float = 90.0

var running: bool = false
var cancel_requested: bool = false
var last_summary: Dictionary = {}
var results: Array = []

var _config: Dictionary = {}
var _plans: Dictionary = {1: {}, 2: {}}
var _progress_line: String = ""


func is_running() -> bool:
	return running


func get_progress_line() -> String:
	"""Latest human-readable progress, for PM-9's overlay and for scenarios."""
	return _progress_line


# ============================================================
# Run
# ============================================================

func start(options: Dictionary = {}) -> void:
	if running:
		push_warning("PlanSimulator: a run is already in progress")
		return
	_config = _normalise(options)
	_plans = {
		1: _load_plan(_config.get("plan1", "")),
		2: _load_plan(_config.get("plan2", "")),
	}
	results = []
	last_summary = {}
	cancel_requested = false
	running = true
	_log("Run starting: %d game(s), seeds %d..%d, %s vs %s on %s" % [
		_config.games, _config.seed_base, _config.seed_base + _config.games - 1,
		_plan_label(1), _plan_label(2), _config.zone_id])
	emit_signal("run_started", int(_config.games))
	_run_all.call_deferred()


func cancel() -> void:
	if not running:
		return
	cancel_requested = true
	_log("Cancel requested")


func _run_all() -> void:
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = float(_config.time_scale)

	for i in range(int(_config.games)):
		if cancel_requested:
			break
		var result := await _run_one(i)
		results.append(result)
		emit_signal("game_finished", i, result)
		if str(result.get("status", "")) == "cancelled":
			break

	Engine.time_scale = previous_time_scale
	_restore_randomness()

	var summary := build_summary()
	last_summary = summary
	summary["results_path"] = _write_results(summary)
	running = false
	if cancel_requested:
		_log("Run cancelled after %d game(s)" % results.size())
		emit_signal("run_cancelled", summary)
	else:
		_log("Run finished: %s" % summary.get("headline", ""))
		emit_signal("run_finished", summary)


func _run_one(index: int) -> Dictionary:
	var game_seed: int = int(_config.seed_base) + index
	# Order matters: stand the AI down, reset, and only then build the new game.
	# Resetting after the bootstrap wipes state the bootstrap just populated
	# (StratagemManager.reset_for_new_game clears the faction stratagems the
	# army application had just loaded). — PM-8a
	_quiesce_ai()
	_reset_between_games()
	var unit_count := _bootstrap(game_seed)
	await _enter_main_scene()
	_install_plans()

	_progress_line = "Game %d/%d starting (seed %d)" % [index + 1, int(_config.games), game_seed]
	var watched: Dictionary = await GameWatcherScript.watch(get_tree(), {
		"max_seconds": float(_config.max_seconds_per_game),
		"stall_seconds": DEFAULT_STALL_SECONDS,
		"on_progress": func(elapsed, battle_round, phase, actions):
			_progress_line = "Game %d/%d — %.0fs, round %d, %d actions" % [
				index + 1, int(_config.games), elapsed, battle_round, actions],
		"should_cancel": func(): return cancel_requested,
	})

	# Harvest BEFORE the next configure() — it clears the decision records.
	var result := _collect_result(index, game_seed, unit_count, watched)
	_log("Game %d/%d %s — %s (%.1fs)" % [
		index + 1, int(_config.games), result.get("status", "?"),
		result.get("headline", ""), float(result.get("wall_seconds", 0.0))])
	return result


# ============================================================
# Per-game construction
# ============================================================

func _game_config() -> Dictionary:
	return {
		"terrain": str(_config.layout_id),
		"mission": str(_config.mission_id),
		"deployment": str(_config.zone_id),
		"player1_army": str(_config.army1),
		"player2_army": str(_config.army2),
		"player1_type": "AI",
		"player2_type": "AI",
		"player1_difficulty": int(_config.difficulty1),
		"player2_difficulty": int(_config.difficulty2),
		"ai_speed": 0,
		"player1_secondary_mode": "tactical",
		"player2_secondary_mode": "tactical",
		"player1_fixed_missions": [],
		"player2_fixed_missions": [],
		"player1_disposition": "",
		"player2_disposition": "",
		"player1_name": "",
		"player2_name": "",
		# The simulator installs the plans itself after configure(); Main's own
		# PM-7a path must not also try, or "no plan" would auto-match one.
		"player1_plan": "none",
		"player2_plan": "none",
		"plan_sim": true,
	}


func _bootstrap(game_seed: int) -> int:
	"""Build a fresh game in place. Mirrors MainMenu._initialize_game_with_config
	without the scene change, then seeds every RNG channel. Returns unit count."""
	var config := _game_config()
	var root := get_tree().root

	GameState.state.clear()
	GameState.initialize_default_state(config.deployment)
	GameState.state.meta["game_config"] = config

	var terrain = root.get_node_or_null("TerrainManager")
	if terrain != null:
		terrain.current_layout = config.terrain
		terrain.load_terrain_layout(config.terrain)
	var board = root.get_node_or_null("BoardState")
	if board != null:
		board.initialize_deployment_zones(config.deployment)
	var mission = root.get_node_or_null("MissionManager")
	if mission != null:
		mission.initialize_mission(config.mission)

	GameState.state.units.clear()
	var armies = root.get_node_or_null("ArmyListManager")
	if armies != null:
		for player in [1, 2]:
			var army = armies.load_army_for_game(config["player%d_army" % player], player)
			if army.is_empty():
				push_warning("PlanSimulator: army '%s' failed to load for player %d" % [
					config["player%d_army" % player], player])
			else:
				armies.apply_army_to_game_state(army, player)
	var secondary = root.get_node_or_null("SecondaryMissionManager")
	if secondary != null:
		secondary.initialize_for_game()

	GameState.state.meta["game_config"] = config
	GameState.state.meta["from_menu"] = true

	_seed_everything(game_seed, secondary)
	return GameState.state.units.size()


func _seed_everything(game_seed: int, secondary) -> void:
	"""The documented seeding TRIPLE plus a fourth channel.

	Array.shuffle() / randi() / randf() draw from GDScript's GLOBAL generator,
	which the triple does not cover. A fresh process starts it from a fixed
	default — which is why two separate processes agree on a seed — but its
	state carries over between in-session games. PM-8a measured this changing
	game 2's outcome on its own."""
	seed(game_seed)
	if RulesEngine != null and RulesEngine.has_method("set_test_seed"):
		RulesEngine.set_test_seed(game_seed)
	if secondary != null and secondary.has_method("set_test_seed"):
		secondary.set_test_seed(game_seed)
	var AIDM = load("res://scripts/AIDecisionMaker.gd")
	if AIDM != null:
		AIDM.set_ai_seed(game_seed)
		if not AIDM.is_ai_seeded():
			push_warning("PlanSimulator: AIDecisionMaker.set_ai_seed did not take effect")


func _enter_main_scene() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
	var waited := 0
	while waited < 600 and (get_tree().current_scene == null or not get_tree().current_scene.is_node_ready()):
		await get_tree().process_frame
		waited += 1
	for _i in range(8):
		await get_tree().process_frame

	var ai = get_tree().root.get_node_or_null("AIPlayer")
	if ai != null:
		if ai.has_method("set_ai_speed_preset"):
			ai.set_ai_speed_preset(0)
		# The 500-batch ring drops the deployment batch on a full game, and the
		# deployment batch is exactly where plan adherence is measured
		# (AIBenchmarkRunner raises it for the same reason).
		ai._max_decision_record_batches = 100000


func _install_plans() -> void:
	"""AFTER Main._initialize_ai_player() has run configure(), which clears
	plans. A seat with no plan is SUPPRESSED, not merely cleared — clearing
	leaves the auto-match flag down and the seat would quietly match a plan off
	the search path, which would make a "no plan" arm meaningless."""
	var AIDM = load("res://scripts/AIDecisionMaker.gd")
	if AIDM == null:
		return
	for player in [1, 2]:
		var plan: Dictionary = _plans.get(player, {})
		if plan.is_empty():
			AIDM.suppress_player_plan(player)
		else:
			AIDM.set_player_plan(player, plan)


# ============================================================
# Reset (PM-8a's proven list — every entry earned by a divergence)
# ============================================================

func _quiesce_ai() -> void:
	"""Stand the AI down BEFORE the teardown.

	Between games AIPlayer is still `enabled` with `_needs_evaluation` set, so
	it keeps acting while the next game is assembled — and Main's later
	configure() wipes `_action_log`, hiding that it did. PM-8a: fixing only
	this moved the first action-trace divergence from index 0 to index 23."""
	var ai = get_tree().root.get_node_or_null("AIPlayer")
	if ai != null:
		ai.configure({1: "HUMAN", 2: "HUMAN"})


func _reset_between_games() -> void:
	var root := get_tree().root

	var strat = root.get_node_or_null("StratagemManager")
	if strat != null and strat.has_method("reset_for_new_game"):
		strat.reset_for_new_game()          # proven leak: _usage_history was 8/8
	var abilities = root.get_node_or_null("UnitAbilityManager")
	if abilities != null and abilities.has_method("reset_for_new_game"):
		abilities.reset_for_new_game()      # no production caller — risk unproven, not disproven

	var pm = root.get_node_or_null("PhaseManager")
	if pm != null:
		pm.reset()                          # game_ended stayed true through the bootstrap
		pm._last_round_started = -1         # reset() does not clear this; it stayed at 5

	_reset_faction_abilities(root)
	_reset_mission_manager(root)
	_reset_log_accumulators(root)


func _reset_faction_abilities(root: Node) -> void:
	"""THE determinism-breaker. FactionAbilityManager has no reset entry point
	of any kind, and its per-game dictionaries are fixed-shape {"1":…, "2":…} —
	so a size fingerprint cannot see them leak. PM-8a found it by action trace:
	game 2 skipped SELECT_MARTIAL_MASTERY because _active_mastery still held
	game 1's value, and the whole game diverged from there."""
	var fam = root.get_node_or_null("FactionAbilityManager")
	if fam == null:
		return
	fam._active_effects = {"1": {}, "2": {}}
	fam._player_abilities = {"1": [], "2": []}
	fam._waaagh_used = {"1": false, "2": false}
	fam._waaagh_active = {"1": false, "2": false}
	fam._boss_watchin_used = {"1": false, "2": false}
	fam._plant_waaagh_banner_used = {}
	fam._player_detachment = {"1": "", "2": ""}
	fam._doctrines_used = {"1": [], "2": []}
	fam._active_doctrine = {"1": "", "2": ""}
	fam._active_mastery = {"1": "", "2": ""}
	fam._mastery_selected_round = {"1": 0, "2": 0}
	fam._loot_objective = {"1": "", "2": ""}
	fam._loot_objective_round = {"1": 0, "2": 0}
	fam._da_kaptin_used_round = {"1": 0, "2": 0}
	fam._bionik_workshop_results = {}
	fam._bionik_workshop_resolved = false
	fam._razgit_redeploys_used = {"1": 0, "2": 0}
	fam._razgit_resolved = false
	fam._morks_kunnin_redeploys_used = {"1": 0, "2": 0}
	fam._aao_status = {}


func _reset_mission_manager(root: Node) -> void:
	var mission = root.get_node_or_null("MissionManager")
	if mission == null:
		return
	mission._units_alive_at_round_start.clear()

	# Main._setup_objectives() connects lambdas CAPTURING scene nodes to these
	# autoload signals. MissionManager outlives the scene, so each game adds N
	# more receivers that then fire on freed captures ("Lambda capture at index
	# 1 was freed" — 105 of them in a 3-game run). Note the obvious guard does
	# NOT work: a freed RECEIVER auto-disconnects, but a lambda's bound object
	# outlives the scene while its captures do not, so is_instance_valid() is
	# still true and Godot keeps calling it. An unconditional is_custom() sweep
	# is required; Main re-creates them for the new scene.
	var dropped := 0
	for signal_name in ["objective_control_changed", "objective_removed"]:
		if not mission.has_signal(signal_name):
			continue
		for connection in mission.get_signal_connection_list(signal_name):
			var callable: Callable = connection["callable"]
			var target = callable.get_object()
			if callable.is_custom() or target == null or not is_instance_valid(target):
				mission.disconnect(signal_name, callable)
				dropped += 1
	mission.objectives_visual_refs.clear()
	if dropped > 0:
		_log("Dropped %d stale MissionManager signal connection(s)" % dropped)


func _reset_log_accumulators(root: Node) -> void:
	"""No reset entry points, unbounded growth across a long run — and
	ActionLogger / GameEventLog feed AI-visible context."""
	var action_logger = root.get_node_or_null("ActionLogger")
	if action_logger != null and action_logger.has_method("_initialize_session"):
		action_logger.action_sequence = 0
		action_logger.session_actions.clear()
		action_logger.initial_snapshot = {}
		action_logger._initialize_session()
	var event_log = root.get_node_or_null("GameEventLog")
	if event_log != null:
		event_log.entries.clear()
	# ReplayManager.auto_record_ai is left ON: the auto-recorded replays are the
	# only way to rewatch a simulated game (ReplayManager.gd:39, 247-249). The
	# cost is one replay file per game, which is the price of that. Recording is
	# stopped here so each game starts a fresh one rather than appending.
	var replay = root.get_node_or_null("ReplayManager")
	if replay != null and replay.has_method("stop_recording"):
		replay.stop_recording()


func _restore_randomness() -> void:
	"""Undo the seeding so a normal game started afterwards is not deterministic."""
	if RulesEngine != null and RulesEngine.has_method("set_test_seed"):
		RulesEngine.set_test_seed(-1)
	var secondary = get_tree().root.get_node_or_null("SecondaryMissionManager")
	if secondary != null and secondary.has_method("set_test_seed"):
		secondary.set_test_seed(-1)
	var AIDM = load("res://scripts/AIDecisionMaker.gd")
	if AIDM != null:
		AIDM.set_ai_seed(-1)
	randomize()


# ============================================================
# Results
# ============================================================

func _collect_result(index: int, game_seed: int, unit_count: int, watched: Dictionary) -> Dictionary:
	var mission = get_tree().root.get_node_or_null("MissionManager")
	var vp: Dictionary = mission.get_vp_summary() if mission != null else {}
	var vp1 := int(vp.get("player1", {}).get("total", 0))
	var vp2 := int(vp.get("player2", {}).get("total", 0))
	var winner := 0
	if vp1 > vp2:
		winner = 1
	elif vp2 > vp1:
		winner = 2

	var adherence := _plan_adherence()
	var result := {
		"game": index + 1,
		"seed": game_seed,
		"status": str(watched.get("status", "unknown")),
		"note": str(watched.get("note", "")),
		"winner": winner,
		"vp_p1": vp1,
		"vp_p2": vp2,
		"margin": vp1 - vp2,
		"battle_round": int(watched.get("battle_round", 0)),
		"actions": int(watched.get("actions", 0)),
		"unit_count": unit_count,
		"plan_adherence_p1": int(adherence.get(1, 0)),
		"plan_adherence_p2": int(adherence.get(2, 0)),
		"difficulty": int(_config.difficulty),
		"difficulty_p1": int(_config.difficulty1),
		"difficulty_p2": int(_config.difficulty2),
		"wall_seconds": float(watched.get("wall_seconds", 0.0)),
	}
	result["headline"] = "P1 %d - %d P2 (round %d)" % [vp1, vp2, result.battle_round]
	return result


func _plan_adherence() -> Dictionary:
	"""Deployment decisions whose recorded source is `plan:<name>`, per seat.

	Seat 2's count is the one that matters: a plan is authored in the player-1
	frame, so a non-zero seat-2 count is the only proof the [44-x, 60-y]
	transform actually landed placements the phase accepted."""
	var out := {1: 0, 2: 0}
	var ai = get_tree().root.get_node_or_null("AIPlayer")
	if ai == null or not ("_all_decision_records" in ai):
		return out
	for batch in ai._all_decision_records:
		var seat := int(batch.get("player", 0))
		for record in batch.get("records", []):
			if str(record.get("decision_type", "")) != "deployment":
				continue
			if str(record.get("context", {}).get("source", "")).begins_with("plan:"):
				out[seat] = int(out.get(seat, 0)) + 1
	return out


func build_summary() -> Dictionary:
	var completed: Array = []
	for r in results:
		if str(r.get("status", "")) == "completed":
			completed.append(r)

	var wins := {1: 0, 2: 0, 0: 0}
	var margins: Array = []
	var seconds: Array = []
	for r in completed:
		wins[int(r.get("winner", 0))] = int(wins.get(int(r.get("winner", 0)), 0)) + 1
		margins.append(float(r.get("margin", 0)))
	for r in results:
		seconds.append(float(r.get("wall_seconds", 0.0)))

	var summary := {
		"games_requested": int(_config.get("games", 0)),
		"games_run": results.size(),
		"games_completed": completed.size(),
		"wins_p1": int(wins.get(1, 0)),
		"wins_p2": int(wins.get(2, 0)),
		"draws": int(wins.get(0, 0)),
		"mean_margin": _mean(margins),
		"sd_margin": _sd(margins),
		"mean_seconds_per_game": _mean(seconds),
		"seed_base": int(_config.get("seed_base", 0)),
		"difficulty": int(_config.get("difficulty", DEFAULT_DIFFICULTY)),
		"difficulty_p1": int(_config.get("difficulty1", DEFAULT_DIFFICULTY)),
		"difficulty_p2": int(_config.get("difficulty2", DEFAULT_DIFFICULTY)),
		"zone_id": str(_config.get("zone_id", "")),
		"layout_id": str(_config.get("layout_id", "")),
		"army1": str(_config.get("army1", "")),
		"army2": str(_config.get("army2", "")),
		"plan1": _plan_label(1),
		"plan2": _plan_label(2),
		"cancelled": cancel_requested,
		"stalls": _count_status("stalled"),
		"timeouts": _count_status("timeout"),
	}
	summary["headline"] = "P1 %d - %d P2 (%d draw(s)) over %d completed game(s), mean margin %+.1f ± %.1f" % [
		summary.wins_p1, summary.wins_p2, summary.draws, summary.games_completed,
		summary.mean_margin, summary.sd_margin]
	return summary


func _count_status(status: String) -> int:
	var n := 0
	for r in results:
		if str(r.get("status", "")) == status:
			n += 1
	return n


func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += float(v)
	return total / float(values.size())


func _sd(values: Array) -> float:
	"""Population standard deviation. 0.0 for a single sample — an honest 'we
	cannot say' rather than a divide-by-zero or a fabricated spread."""
	if values.size() < 2:
		return 0.0
	var mean := _mean(values)
	var acc := 0.0
	for v in values:
		acc += pow(float(v) - mean, 2.0)
	return sqrt(acc / float(values.size()))


func _write_results(summary: Dictionary) -> String:
	var dir = DirAccess.open("user://")
	if dir != null and not dir.dir_exists("plan_sim_results"):
		dir.make_dir("plan_sim_results")
	# Wall clock for the FILENAME only — never inside seeded game logic.
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "").replace("-", "").replace("T", "_")
	var path := "%s%s.json" % [RESULTS_DIR, stamp]
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("PlanSimulator: could not write %s" % path)
		return ""
	file.store_string(JSON.stringify({"summary": summary, "games": results}, "\t"))
	file.close()
	_log("Results written to %s" % path)
	return path


# ============================================================
# Helpers
# ============================================================

func _normalise(options: Dictionary) -> Dictionary:
	return {
		"zone_id": str(options.get("zone_id", "hammer_anvil")),
		"layout_id": str(options.get("layout_id", "")),
		"mission_id": str(options.get("mission_id", "take_and_hold")),
		"army1": str(options.get("army1", "")),
		"army2": str(options.get("army2", options.get("army1", ""))),
		"plan1": options.get("plan1", ""),
		"plan2": options.get("plan2", ""),
		"games": maxi(1, int(options.get("games", DEFAULT_GAMES))),
		"seed_base": int(options.get("seed_base", DEFAULT_SEED_BASE)),
		"difficulty": int(options.get("difficulty", DEFAULT_DIFFICULTY)),
		# Per-seat difficulty for cross-tier benchmarking ("is Hard actually
		# better than Normal?"). Both default to `difficulty`, so every existing
		# caller keeps the same-tier behaviour it had before.
		"difficulty1": int(options.get("difficulty1", options.get("difficulty", DEFAULT_DIFFICULTY))),
		"difficulty2": int(options.get("difficulty2", options.get("difficulty", DEFAULT_DIFFICULTY))),
		"time_scale": float(options.get("time_scale", DEFAULT_TIME_SCALE)),
		"max_seconds_per_game": float(options.get("max_seconds_per_game", DEFAULT_MAX_SECONDS)),
	}


func _load_plan(value) -> Dictionary:
	"""Accepts a plan Dictionary, a path, or "" / "none" for no plan."""
	if value is Dictionary:
		return value
	var text := str(value)
	if text.is_empty() or text == "none":
		return {}
	var plan: Dictionary = PlanValidatorScript.load_plan_file(text)
	if plan.is_empty():
		push_warning("PlanSimulator: could not read plan '%s' — that seat will run on the formula" % text)
	return plan


func _plan_label(player: int) -> String:
	var plan: Dictionary = _plans.get(player, {})
	return str(plan.get("name", "")) if not plan.is_empty() else "(no plan)"


func _log(message: String) -> void:
	print("PlanSimulator: %s" % message)
	var logger = get_tree().root.get_node_or_null("DebugLogger") if get_tree() != null else null
	if logger != null and logger.has_method("info"):
		logger.info("[PlanSimulator] %s" % message)
