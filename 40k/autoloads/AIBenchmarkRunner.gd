extends Node

# AIBenchmarkRunner — plays one full AI-vs-AI game headless and reports the
# result as JSON, so a shell loop can benchmark AI changes by win rate / VP
# differential instead of vibes.
#
# Activates only when `--ai-benchmark` is on the cmdline; otherwise a no-op
# autoload (same pattern as ScenarioRunner).
#
# Wire protocol:
#   godot --path 40k -- --ai-benchmark \
#     --bench-fixture=audit_baseline_postdeploy \
#     --bench-seed=42 \
#     --bench-out=test_results/bench/run_1.json \
#     [--bench-p1-profile=path.json] [--bench-p2-profile=path.json] \
#     [--bench-difficulty=1] [--bench-max-seconds=600] [--bench-time-scale=3] \
#     [--bench-git-sha=abc1234] [--bench-arm=candidate] [--bench-record-out=path.json]
#
# Profiles are AIDecisionMaker parameter-override files (the ai_config.json /
# load_player_profile format): {"parameters": {...}, "rules": [...]}.
#
# Output: one JSON file + a parse-friendly `[AIBench] RESULT {...}` line.
# Exit code 0 = game completed, 2 = stalled/aborted.
#
# M1 (AI learning loop): alongside the result JSON, every run also writes a
# `wh40k_ai_game_record` — the AI's own decision records joined to the game's
# outcome, its VP events, and full provenance (fixture hash, profile hashes,
# git sha). Until this existed the AI produced a complete "here were my
# options, here is how I scored each one, here is what I picked, here are the
# parameters I used" trace every game and discarded all of it at quit.
# See research/ai_learning_framework_design.md §7.

var _active: bool = false
var _fixture: String = "audit_baseline_postdeploy"
var _seed: int = -1
var _out_path: String = "test_results/bench/result.json"
var _p1_profile_path: String = ""
var _p2_profile_path: String = ""
var _difficulty: int = 1  # Normal — the default players face
var _max_seconds: float = 600.0
var _time_scale: float = 3.0

var _git_sha: String = ""
var _arm: String = ""
var _record_out_path: String = ""

var _start_ticks: int = 0
var _last_progress_ticks: int = 0
var _last_progress_sig: String = ""
const STALL_SECONDS := 90.0

# M1: the record schema lives in scripts/AIGameRecord.gd — a plain
# RefCounted with no autoload dependencies, so it stays testable without
# standing up a whole game (this autoload is not).

# The decision-record ring buffer is sized for a desktop play session (500
# batches). A benchmark process plays exactly one game and then exits, so it
# can afford to keep every batch: a measured game is ~150 batches / ~0.6 MB,
# so even a 10x outlier stays around 10 MB of RAM. Dropping batches would
# silently bias the dataset toward the END of the game, which is exactly the
# part a learner most wants to trust.
const BENCH_RECORD_BATCH_CAP := 100000

# (round, phase, player, points, reason) for every VP award, as emitted by
# MissionManager.victory_points_scored. This is the intermediate reward
# signal that the terminal margin alone cannot provide.
var _vp_events: Array = []
# Parsed profile JSON per player, kept for INLINE provenance so a record
# stays self-describing even if the profile file is later edited or deleted.
var _profile_inline: Dictionary = {1: {}, 2: {}}

func _ready() -> void:
	var args = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if not "--ai-benchmark" in args:
		return
	for a in args:
		if typeof(a) != TYPE_STRING:
			continue
		if a.begins_with("--bench-fixture="):
			_fixture = a.split("=", true, 1)[1]
		elif a.begins_with("--bench-seed="):
			_seed = int(a.split("=", true, 1)[1])
		elif a.begins_with("--bench-out="):
			_out_path = a.split("=", true, 1)[1]
		elif a.begins_with("--bench-p1-profile="):
			_p1_profile_path = a.split("=", true, 1)[1]
		elif a.begins_with("--bench-p2-profile="):
			_p2_profile_path = a.split("=", true, 1)[1]
		elif a.begins_with("--bench-difficulty="):
			_difficulty = int(a.split("=", true, 1)[1])
		elif a.begins_with("--bench-max-seconds="):
			_max_seconds = float(a.split("=", true, 1)[1])
		elif a.begins_with("--bench-time-scale="):
			_time_scale = float(a.split("=", true, 1)[1])
		elif a.begins_with("--bench-git-sha="):
			_git_sha = a.split("=", true, 1)[1]
		elif a.begins_with("--bench-arm="):
			_arm = a.split("=", true, 1)[1]
		elif a.begins_with("--bench-record-out="):
			_record_out_path = a.split("=", true, 1)[1]
	# Default the record alongside the result file:
	#   test_results/bench/run_1.json -> test_results/bench/run_1.record.json
	if _record_out_path == "":
		_record_out_path = _out_path.get_basename() + ".record.json"
	_active = true
	print("[AIBench] Activating: fixture=%s seed=%d difficulty=%d time_scale=%.1f" % [
		_fixture, _seed, _difficulty, _time_scale])
	call_deferred("_kick_off")

func _kick_off() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	# 1) Load the fixture (a post-deployment save = full game from round 1)
	var save_mgr = get_node_or_null("/root/SaveLoadManager")
	if save_mgr == null or not save_mgr.load_game(_fixture):
		_finish_with_error("fixture load failed: %s" % _fixture)
		return
	GameState.state["meta"]["from_save"] = true
	GameConstants.edition = 11

	# Both players are AI for the whole game. This must be written into
	# game_config, not just AIPlayer — engine human-gates (e.g. the 03.03
	# coherency-removal pause in ScoringPhase) read playerN_type and DEFAULT
	# to HUMAN, which would stall an unattended game.
	var meta = GameState.state.get("meta", {})
	var gc = meta.get("game_config", {})
	gc["player1_type"] = "AI"
	gc["player2_type"] = "AI"
	meta["game_config"] = gc
	GameState.state["meta"] = meta

	# 2) Deterministic dice
	if _seed >= 0:
		var rules = get_node_or_null("/root/RulesEngine")
		if rules != null:
			rules.set_test_seed(_seed)
		# Deterministic secondary-mission deck shuffles too — otherwise the
		# card draws differ per run and a stall found at seed N cannot be
		# reproduced by re-running seed N.
		var smm = get_node_or_null("/root/SecondaryMissionManager")
		if smm != null and smm.has_method("set_test_seed"):
			smm.set_test_seed(_seed)
		# M2: and the AI layer's own RNG — score noise, Easy-mode picks and
		# scatter all drew from the GLOBAL generator, which is why two
		# same-seed games diverged at the fifth movement decision.
		AIDecisionMaker.set_ai_seed(_seed)

	# 3) Live battle scene (phases/controllers need it)
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
	var waited := 0
	while waited < 240 and (get_tree().current_scene == null or not get_tree().current_scene.is_node_ready()):
		await get_tree().process_frame
		waited += 1
	for i in range(8):
		await get_tree().process_frame

	# 4) Both players AI at the requested difficulty, fastest pacing
	var ai = get_node_or_null("/root/AIPlayer")
	if ai == null:
		_finish_with_error("AIPlayer autoload missing")
		return
	ai.configure({1: "AI", 2: "AI"}, {1: _difficulty, 2: _difficulty})
	ai.set_ai_speed_preset(0)  # FAST
	# M1: keep every decision batch (see BENCH_RECORD_BATCH_CAP). configure()
	# clears the accumulator, so this must come AFTER it.
	ai._max_decision_record_batches = BENCH_RECORD_BATCH_CAP
	_connect_vp_events()
	_load_profile(1, _p1_profile_path)
	_load_profile(2, _p2_profile_path)

	# 5) Accelerate the AI's pacing timers
	Engine.time_scale = maxf(1.0, _time_scale)

	# 6) Kick the game from the save's phase (COMMAND at round 1 for the
	# baseline fixture) and let the AI drive to the end
	var pm = get_node_or_null("/root/PhaseManager")
	var start_phase = int(GameState.state.get("meta", {}).get("phase", 6))
	pm.transition_to_phase(start_phase)

	_start_ticks = Time.get_ticks_msec()
	_last_progress_ticks = _start_ticks
	print("[AIBench] Game started (phase %d, round %d)" % [
		start_phase, GameState.get_battle_round()])
	_watch_loop()

func _watch_loop() -> void:
	var pm = get_node_or_null("/root/PhaseManager")
	var ai = get_node_or_null("/root/AIPlayer")
	while true:
		await get_tree().create_timer(0.5).timeout
		if pm.game_ended:
			_finish_completed()
			return
		var elapsed = (Time.get_ticks_msec() - _start_ticks) / 1000.0
		if elapsed > _max_seconds:
			_finish_stalled("max_seconds exceeded (%.0fs)" % elapsed)
			return
		# Progress signature: round | phase | actions taken. If it freezes for
		# STALL_SECONDS of real time, the game is stuck — that is itself a
		# benchmark finding.
		var sig = "%d|%d|%d" % [GameState.get_battle_round(), GameState.get_current_phase(),
			ai._action_log.size() if ai != null else 0]
		if sig != _last_progress_sig:
			_last_progress_sig = sig
			_last_progress_ticks = Time.get_ticks_msec()
		elif (Time.get_ticks_msec() - _last_progress_ticks) / 1000.0 > STALL_SECONDS:
			_finish_stalled("no progress for %.0fs at %s" % [STALL_SECONDS, sig])
			return

func _load_profile(player: int, path: String) -> void:
	if path == "":
		return
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("[AIBench] WARNING: profile not found: %s" % path)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		AIDecisionMaker.load_player_profile(player, parsed)
		_profile_inline[player] = parsed
		print("[AIBench] Loaded profile for P%d from %s (%d parameters)" % [
			player, path, parsed.get("parameters", {}).size()])

func _collect_result(status: String, note: String) -> Dictionary:
	var mm = get_node_or_null("/root/MissionManager")
	var vp = mm.get_vp_summary() if mm != null else {}
	var p1_total = int(vp.get("player1", {}).get("total", 0))
	var p2_total = int(vp.get("player2", {}).get("total", 0))
	var winner = 0
	if p1_total > p2_total:
		winner = 1
	elif p2_total > p1_total:
		winner = 2
	var ai = get_node_or_null("/root/AIPlayer")
	return {
		"status": status,
		"note": note,
		"fixture": _fixture,
		"seed": _seed,
		"difficulty": _difficulty,
		"p1_profile": _p1_profile_path,
		"p2_profile": _p2_profile_path,
		"winner": winner,
		"vp": vp,
		"vp_diff_p2_minus_p1": p2_total - p1_total,
		"battle_round": GameState.get_battle_round(),
		"actions_taken": ai._action_log.size() if ai != null else 0,
		"wall_seconds": (Time.get_ticks_msec() - _start_ticks) / 1000.0,
		"time_scale": _time_scale,
	}

func _finish_completed() -> void:
	_write_and_quit(_collect_result("completed", ""), 0)

func _finish_stalled(reason: String) -> void:
	_write_and_quit(_collect_result("stalled", reason), 2)

func _finish_with_error(reason: String) -> void:
	_write_and_quit({"status": "error", "note": reason, "fixture": _fixture, "seed": _seed}, 2)

# =============================================================================
# M1 — per-game learning record
# =============================================================================

func _connect_vp_events() -> void:
	"""Collect every VP award as an intermediate reward signal.

	MissionManager is an autoload, so this connection survives the scene change
	the runner performs; connecting here (before the opening transition_to_phase)
	catches the whole game."""
	var mm = get_node_or_null("/root/MissionManager")
	if mm == null or not mm.has_signal("victory_points_scored"):
		print("[AIBench] WARNING: MissionManager.victory_points_scored unavailable; vp_events will be empty")
		return
	mm.victory_points_scored.connect(_on_vp_scored)

func _on_vp_scored(player: int, points: int, reason: String) -> void:
	_vp_events.append({
		"round": GameState.get_battle_round(),
		"phase": GameState.get_current_phase(),
		"player": player,
		"points": points,
		"reason": reason,
		"wall_seconds": _elapsed_seconds(),
	})

func _elapsed_seconds() -> float:
	"""Seconds since the game began. VP can be awarded during the opening
	transition_to_phase, before _watch_loop sets _start_ticks — without this
	guard those events would be stamped with the whole process uptime."""
	if _start_ticks == 0:
		return 0.0
	return (Time.get_ticks_msec() - _start_ticks) / 1000.0

static func _sha256_of(path: String) -> String:
	if path == "" or not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_sha256(path)

func _fixture_path() -> String:
	"""Where the loaded fixture actually lives.

	SaveLoadManager.save_directory is user://saves/, populated by migration from
	the repo's res://saves/. Hash whichever copy exists so the record pins the
	EXACT environment the game was played on — the corrupt-fixture episode
	(a 2000-pt army-list header row imported as a unit) invalidated every
	historical baseline precisely because nothing recorded this."""
	for base in ["user://saves/", "res://saves/"]:
		var p = base + _fixture + ".w40ksave"
		if FileAccess.file_exists(p):
			return p
	return ""

func _profile_provenance(player: int) -> Dictionary:
	var path = _p1_profile_path if player == 1 else _p2_profile_path
	return {
		"path": path,
		"sha256": _sha256_of(path),
		"inline": _profile_inline.get(player, {}),
	}

func _build_provenance() -> Dictionary:
	var fixture_path = _fixture_path()
	return AIGameRecord.build_provenance(
		_git_sha, Engine.get_version_info().get("string", ""), _fixture,
		fixture_path, _sha256_of(fixture_path),
		_profile_provenance(1), _profile_provenance(2),
		_difficulty, _seed, _time_scale, _arm)


func _write_game_record(result: Dictionary) -> void:
	"""Write the record. Called from _write_and_quit so it covers EVERY exit
	path — completed, stalled and errored games alike. A stalled game is one of
	the most informative records there is, and the pre-existing game-complete
	export hook never fires for one."""
	var ai = get_node_or_null("/root/AIPlayer")
	var decisions: Array = []
	var action_log: Array = []
	var batches_total := 0
	var batches_dropped := 0
	if ai != null:
		decisions = ai._all_decision_records
		action_log = ai._action_log
		batches_total = ai._decision_batches_total
		batches_dropped = ai._decision_records_dropped

	var record = AIGameRecord.build(_out_path.get_file().get_basename(), _build_provenance(),
		result, _vp_events, decisions, action_log, batches_total, batches_dropped)
	# Catch a malformed record at write time rather than as a confusing gap
	# three thousand games into a season.
	var problems = AIGameRecord.validate(record)
	if not problems.is_empty():
		print("[AIBench] WARNING: game record failed validation: %s" % str(problems))

	var out = "user://" + _record_out_path
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out).get_base_dir())
	var f = FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		print("[AIBench] WARNING: could not write game record to %s" % out)
		return
	# Compact (not pretty-printed): roughly halves the on-disk size, and nothing
	# reads these by eye — build_index.py does.
	f.store_string(JSON.stringify(record))
	f.close()
	print("[AIBench] RECORD %s decisions=%d dropped=%d vp_events=%d actions=%d" % [
		ProjectSettings.globalize_path(out), decisions.size(), batches_dropped,
		_vp_events.size(), action_log.size()])

func _write_and_quit(result: Dictionary, code: int) -> void:
	Engine.time_scale = 1.0
	var out = "user://" + _out_path
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out).get_base_dir())
	var f = FileAccess.open(out, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(result, "  "))
		f.close()
	_write_game_record(result)
	print("[AIBench] RESULT %s" % JSON.stringify(result))
	print("[AIBench] written: %s" % ProjectSettings.globalize_path(out))
	await get_tree().process_frame
	get_tree().quit(code)
