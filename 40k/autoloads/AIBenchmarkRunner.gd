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
# Default to a fixture that PASSES tools/ai_lab/fixture_check.py. The previous
# default, audit_baseline_postdeploy, still carries the U_STRIKE_FORCE_A
# army-list header row imported as a unit — 2000 phantom points that break the
# Strategic Reserves cap and out-score every real unit in target selection. A
# no-argument run should not quietly produce numbers from that.
var _fixture: String = "mirror_custodes_2000_postdeploy"
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

# B4 — TACTICAL EXAM MODE.
# A full game is a noisy, expensive signal: SD 9-15 VP per seed and minutes of
# wall clock. Most regressions and most capability gains are visible in seconds
# in a CONSTRUCTED position — "does it take the uncontested objective 4 inches
# away", "does it finish the Knight on 5 wounds instead of spreading damage".
# Chess engines call these test suites. An exam reuses everything this runner
# already does (fixture load, deterministic seeding, both-players-AI config,
# the live battle scene) and differs in three ways: it may mutate the loaded
# state first, it runs ONE phase instead of a whole game, and it ends by
# evaluating machine-checkable assertions over the resulting state and the
# AI's own decision records.
var _exam_spec_path: String = ""
var _exam_out_path: String = ""
var _exam: Dictionary = {}
var _exam_phase: int = -1
var _exam_results: Array = []

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
		elif a.begins_with("--exam="):
			_exam_spec_path = a.split("=", true, 1)[1]
		elif a.begins_with("--exam-out="):
			_exam_out_path = a.split("=", true, 1)[1]
	# Default the record alongside the result file:
	#   test_results/bench/run_1.json -> test_results/bench/run_1.record.json
	if _record_out_path == "":
		_record_out_path = _out_path.get_basename() + ".record.json"
	_active = true
	if _exam_spec_path != "":
		if not _load_exam_spec():
			return
	print("[AIBench] Activating: fixture=%s seed=%d difficulty=%d time_scale=%.1f%s" % [
		_fixture, _seed, _difficulty, _time_scale,
		("  exam=%s" % _exam.get("id", "?")) if _exam_spec_path != "" else ""])
	call_deferred("_kick_off")

# ---------------------------------------------------------------- B4 exams --

func _load_exam_spec() -> bool:
	var fh = FileAccess.open(_exam_spec_path, FileAccess.READ)
	if fh == null:
		printerr("[AIExam] cannot read spec: %s" % _exam_spec_path)
		get_tree().quit(2)
		return false
	var parsed = JSON.parse_string(fh.get_as_text())
	fh.close()
	if not (parsed is Dictionary):
		printerr("[AIExam] spec is not a JSON object: %s" % _exam_spec_path)
		get_tree().quit(2)
		return false
	_exam = parsed
	_fixture = str(_exam.get("fixture", _fixture))
	_seed = int(_exam.get("seed", 4242))
	_difficulty = int(_exam.get("difficulty", 2))
	_exam_phase = int(_exam.get("phase", -1))
	_max_seconds = float(_exam.get("max_seconds", 120.0))
	_time_scale = float(_exam.get("time_scale", 6.0))
	if _exam_out_path == "":
		_exam_out_path = "test_results/exams/%s.json" % str(_exam.get("id", "exam"))
	return true

func _run_gdscript(src: String, label: String):
	"""Compile and run a snippet with the tree bound, the way the MCP bridge
	does. Exams are data, and their assertions have to be able to reach into
	live state — but they must not be able to fail silently, so a compile or
	run error is a FAILED exam, never a skipped one."""
	var full := "extends RefCounted\nfunc run(tree):\n"
	for line in src.split("\n"):
		full += "\t" + line + "\n"
	var sc := GDScript.new()
	sc.source_code = full
	var err := sc.reload()
	if err != OK:
		return {"_error": "%s: compile failed (err %d)" % [label, err]}
	var obj = sc.new()
	if obj == null or not obj.has_method("run"):
		return {"_error": "%s: could not instance" % label}
	return obj.run(get_tree())

func _exam_evaluate() -> void:
	var records := []
	var ai = get_node_or_null("/root/AIPlayer")
	if ai != null and "_all_decision_records" in ai:
		records = ai._all_decision_records
	var passed := 0
	var failed := 0
	for a in _exam.get("assert", []):
		var name = str(a.get("name", "?"))
		var body = a.get("script", "return null")
		if body is Array:
			body = "\n".join(body)
		var got = _run_gdscript(str(body), name)
		var ok := false
		var detail := ""
		if got is Dictionary and got.has("_error"):
			detail = str(got["_error"])
		elif a.has("equals"):
			ok = str(got) == str(a["equals"])
			detail = "got %s, expected %s" % [str(got), str(a["equals"])]
		elif a.has("expect_min"):
			ok = (got is float or got is int) and float(got) >= float(a["expect_min"])
			detail = "got %s, expected >= %s" % [str(got), str(a["expect_min"])]
		elif a.has("expect_max"):
			ok = (got is float or got is int) and float(got) <= float(a["expect_max"])
			detail = "got %s, expected <= %s" % [str(got), str(a["expect_max"])]
		else:
			detail = "assertion declares no expectation"
		if ok:
			passed += 1
		else:
			failed += 1
		_exam_results.append({"name": name, "ok": ok, "detail": detail})
		print("[AIExam]   %s %s — %s" % ["PASS" if ok else "FAIL", name, detail])
	var verdict := "PASS" if failed == 0 and passed > 0 else "FAIL"
	var out := {
		"id": _exam.get("id", "exam"), "verdict": verdict,
		"passed": passed, "failed": failed,
		"rationale": _exam.get("rationale", ""),
		"phase": _exam_phase, "player": _exam.get("player", 1),
		"seed": _seed, "difficulty": _difficulty,
		"decision_batches": records.size(),
		"assertions": _exam_results,
	}
	var dir := _exam_out_path.get_base_dir()
	if dir != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://" + dir))
	var fh = FileAccess.open("user://" + _exam_out_path, FileAccess.WRITE)
	if fh != null:
		fh.store_string(JSON.stringify(out, "  "))
		fh.close()
	print("[AIExam] RESULT %s" % JSON.stringify(out))
	print("[AIExam] %s: %d passed, %d failed -> %s" % [out.id, passed, failed, verdict])
	get_tree().quit(0 if verdict == "PASS" else 1)

func _exam_watch_loop() -> void:
	"""Run exactly one phase for the player under test, then grade."""
	var pm = get_node_or_null("/root/PhaseManager")
	var start_round = GameState.get_battle_round()
	var max_actions = int(_exam.get("max_actions", 400))
	var acted := 0
	var ai = get_node_or_null("/root/AIPlayer")
	while true:
		await get_tree().create_timer(0.25).timeout
		var elapsed = (Time.get_ticks_msec() - _start_ticks) / 1000.0
		if ai != null:
			acted = ai._action_log.size() if "_action_log" in ai else 0
		var cur_phase = int(GameState.state.get("meta", {}).get("phase", -1))
		if pm.game_ended:
			print("[AIExam] game ended during the exam phase")
			break
		if cur_phase != _exam_phase or GameState.get_battle_round() != start_round:
			print("[AIExam] phase %d complete (now %d) after %d actions" % [
				_exam_phase, cur_phase, acted])
			break
		if acted >= max_actions:
			print("[AIExam] action cap %d reached" % max_actions)
			break
		if elapsed > _max_seconds:
			print("[AIExam] wall-clock cap %.0fs reached" % _max_seconds)
			break
	# Let any in-flight resolution settle before grading.
	for i in range(20):
		await get_tree().process_frame
	_exam_evaluate()

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

	# B4: an exam constructs its position first, then runs one named phase.
	if _exam_spec_path != "":
		var setup = _exam.get("setup", "")
		if setup is Array:
			setup = "\n".join(setup)
		if str(setup) != "":
			var r = _run_gdscript(str(setup), "setup")
			if r is Dictionary and r.has("_error"):
				printerr("[AIExam] %s" % r["_error"])
				get_tree().quit(2)
				return
			print("[AIExam] setup applied -> %s" % str(r))
		var main = get_tree().current_scene
		if main != null and main.has_method("_recreate_unit_visuals"):
			main._recreate_unit_visuals()
		if _exam_phase >= 0:
			start_phase = _exam_phase
		else:
			_exam_phase = start_phase
		pm.transition_to_phase(start_phase)
		_start_ticks = Time.get_ticks_msec()
		print("[AIExam] %s: running phase %d, round %d, player %s at difficulty %d" % [
			_exam.get("id", "?"), start_phase, GameState.get_battle_round(),
			str(_exam.get("player", 1)), _difficulty])
		_exam_watch_loop()
		return

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
			# A wall-clock overrun is NOT a stall. The game was making progress; the
			# box was just too slow (usually because lanes were oversubscribed).
			# Conflating the two makes the stall-rate guardrail depend on machine
			# load, so a busy box would look like an AI regression.
			_finish_timeout("max_seconds exceeded (%.0fs) at round %d, %d actions" % [
				elapsed, GameState.get_battle_round(),
				ai._action_log.size() if ai != null else 0])
			return
		# Progress signature: round | phase | actions taken. If it freezes for
		# STALL_SECONDS of real time, the game is stuck — that is itself a
		# benchmark finding.
		var sig = "%d|%d|%d" % [GameState.get_battle_round(), GameState.get_current_phase(),
			ai._action_log.size() if ai != null else 0]
		if sig != _last_progress_sig:
			_last_progress_sig = sig
			_last_progress_ticks = Time.get_ticks_msec()
			# Collision-profile counters, printed alongside progress so a run
			# that never finishes still yields the numbers.
			AIDecisionMaker._dump_collision_profile("r%d p%d a%d elapsed=%.0fs" % [
				GameState.get_battle_round(), GameState.get_current_phase(),
				ai._action_log.size() if ai != null else 0, elapsed])
		elif (Time.get_ticks_msec() - _last_progress_ticks) / 1000.0 > STALL_SECONDS:
			_finish_stalled("no progress for %.0fs at %s" % [STALL_SECONDS, sig])
			return

## Resolve a profile path and load it. A profile that was ASKED FOR and
## could not be loaded is a fatal error, not a warning: the game would
## otherwise play with default behaviour and report a perfectly normal
## result, so an A/B comparing two unloadable profiles measures nothing and
## looks exactly like a candidate that had no effect. That happened — a
## whole paired campaign returned E = 0.00 because both arms silently fell
## back to defaults.
func _resolve_profile_path(path: String) -> String:
	var candidates := [path]
	if not path.begins_with("res://") and not path.begins_with("user://") \
			and not path.begins_with("/"):
		# Relative paths are ambiguous: Godot resolves them against res://,
		# but a driver launching from the repo root means them relative to
		# THAT. Try both rather than failing on a path that plainly exists.
		candidates.append("res://" + path)
		var repo_root = ProjectSettings.globalize_path("res://").path_join("..")
		candidates.append(repo_root.path_join(path))
		candidates.append(repo_root.path_join(path.trim_prefix("40k/")))
	for c in candidates:
		if FileAccess.file_exists(c):
			return c
	return ""

func _load_profile(player: int, path: String) -> void:
	if path == "":
		return
	var resolved = _resolve_profile_path(path)
	if resolved == "":
		_finish_with_error("profile for P%d could not be resolved: %s" % [player, path])
		return
	var f = FileAccess.open(resolved, FileAccess.READ)
	if f == null:
		_finish_with_error("profile for P%d could not be opened: %s" % [player, resolved])
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		_finish_with_error("profile for P%d is not a JSON object: %s" % [player, resolved])
		return
	if true:
		AIDecisionMaker.load_player_profile(player, parsed)
		_profile_inline[player] = parsed
		print("[AIBench] Loaded profile for P%d from %s (%d parameters)" % [
			player, resolved, parsed.get("parameters", {}).size()])

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
	"""Genuine deadlock: the progress signature froze for STALL_SECONDS."""
	_write_and_quit(_collect_result("stalled", reason), 2)

func _finish_timeout(reason: String) -> void:
	"""Ran out of wall clock while still progressing — a throughput problem,
	not an AI defect. Reported separately so campaign guardrails can count
	stalls without counting slow machines."""
	_write_and_quit(_collect_result("timeout", reason), 3)

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
