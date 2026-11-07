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
#     [--bench-max-seconds=600] [--bench-time-scale=3] \
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
# PM-2a: AI plans, the artifact the whole Plan Maker workstream exists to
# measure. Mirrors the profile flags exactly so a paired A/B can swap sides.
var _p1_plan_path: String = ""
var _p2_plan_path: String = ""
var _plan_inline: Dictionary = {1: {}, 2: {}}
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
# EXAM-DET-1: an exam grades the state at the END of its phase, and nothing
# later. The AI is never told an exam is over, so it plays straight on into the
# next phase and the opponent's turn; the runner used to notice the phase change
# on a 0.25 s poll and then wait 20 frames before grading, and everything the AI
# did in between was graded too. How much fit in depended on frame time, i.e. on
# machine load: on identical code mv04 counted 54, 59 or 94 terms-sum
# mismatches (0, 3 or 18 of player 2's movement actions included). The runner
# now stops the AI synchronously, inside the signal that ends the exam (see
# _exam_stop_ai), and records where it stopped.
var _exam_stopped: bool = false
var _exam_stop: Dictionary = {}
var _exam_start_round: int = 0
var _exam_max_actions: int = 400
# EXAM-DET-1: provenance stamped into the exam result, so a verdict always says
# which board it was graded on (see _ensure_fixture_in_user_saves).
var _fixture_sha256: String = ""
var _fixture_note: String = ""

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
# AB-SEC: secondary-card events (drawn / scored / discarded) per player, kept in
# the outcome so a campaign can say WHICH cards a version loses VP on.
var _secondary_events: Array = []
# Parsed profile JSON per player, kept for INLINE provenance so a record
# stays self-describing even if the profile file is later edited or deleted.
var _profile_inline: Dictionary = {1: {}, 2: {}}
# AB-SEAT: optional per-seat AIDecisionMaker version (script path), for
# old-vs-new AI head-to-head games. "" = the current AIDecisionMaker.
var _seat_ai: Dictionary = {1: "", 2: ""}
# AB-11E: "p1,p2" force dispositions. Older fixture saves carry no 11e primary
# cards, so the game falls back to legacy Take and Hold scoring (5 VP/objective)
# and the AI has no card to plan for. "" = keep what the fixture has.
var _dispositions: String = ""
# AB-11E: --bench-11e plays the fixture under the 11e GDM 2026 mission rules:
# disposition-paired primary cards (from --bench-dispositions, or derived from
# the seed so a campaign rotates through the 25 pairings) and a fresh 11e
# tactical secondary deck built by the normal Command-phase flow. Older
# fixtures carry legacy Take and Hold scoring and the 10e secondary deck.
var _bench_11e: bool = false
# OBJ-CACHE: --bench-no-objective-cache turns the objective-control cache off;
# --bench-verify-objective-cache recomputes on every hit and counts mismatches.
var _obj_cache_mode: String = "on"
# ROLLOUT (tools/ai_lab/rollout.py): counterfactual rollouts from a saved
# mid-game position. --bench-override=<json> arms one-shot forced decisions in
# AIDecisionMaker; --bench-stop-round=N ends the game the moment battle round
# N+1 begins (before it scores anything), so a short horizon is measured at an
# exact, deterministic point. The result carries VP and material (points lost)
# at the start and at the end, so the driver can take deltas.
var _override_path: String = ""
var _stop_round: int = 0
var _vp_start: Dictionary = {}
var _material_start: Dictionary = {}
var _start_round: int = 0

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
		elif a.begins_with("--bench-p1-plan="):
			_p1_plan_path = a.split("=", true, 1)[1]
		elif a.begins_with("--bench-p2-plan="):
			_p2_plan_path = a.split("=", true, 1)[1]
		elif a.begins_with("--bench-p1-ai="):
			_seat_ai[1] = a.split("=", true, 1)[1]
		elif a.begins_with("--bench-p2-ai="):
			_seat_ai[2] = a.split("=", true, 1)[1]
		elif a.begins_with("--bench-override="):
			_override_path = a.split("=", true, 1)[1]
		elif a.begins_with("--bench-stop-round="):
			_stop_round = int(a.split("=", true, 1)[1])
		elif a == "--bench-no-objective-cache":
			_obj_cache_mode = "off"
		elif a == "--bench-verify-objective-cache":
			_obj_cache_mode = "verify"
		elif a == "--bench-11e":
			_bench_11e = true
		elif a.begins_with("--bench-dispositions="):
			_dispositions = a.split("=", true, 1)[1]
		elif a.begins_with("--bench-difficulty="):
			# Legacy flag: the AI has a single strength now. Accepted and
			# ignored so older lab scripts keep running.
			print("[AIBench] NOTE: %s ignored — the AI has no difficulty levels" % a)
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
	print("[AIBench] Activating: fixture=%s seed=%d time_scale=%.1f%s" % [
		_fixture, _seed, _time_scale,
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
	var out := _exam_result_base(verdict, passed, failed)
	_write_exam_trace(out)
	_write_exam_result(out)
	print("[AIExam] RESULT %s" % JSON.stringify(out))
	print("[AIExam] trace %s records_sha256=%s units_sha256=%s fixture_sha256=%s" % [
		str(out.get("trace", "")), str(out.get("records_sha256", "")).left(16),
		str(out.get("units_sha256", "")).left(16), _fixture_sha256.left(16)])
	print("[AIExam] %s: %d passed, %d failed -> %s" % [out.id, passed, failed, verdict])
	get_tree().quit(0 if verdict == "PASS" else 1)

func _exam_result_base(verdict: String, passed: int, failed: int) -> Dictionary:
	var ai = get_node_or_null("/root/AIPlayer")
	var batches := 0
	if ai != null and "_all_decision_records" in ai:
		batches = ai._all_decision_records.size()
	return {
		"id": _exam.get("id", "exam"), "verdict": verdict,
		"passed": passed, "failed": failed,
		"rationale": _exam.get("rationale", ""),
		"phase": _exam_phase, "player": _exam.get("player", 1),
		"seed": _seed,
		"decision_batches": batches,
		"assertions": _exam_results,
		# EXAM-DET-1: where the AI was stopped, which board was graded, which build.
		"stopped": _exam_stop,
		"fixture": {"name": _fixture, "path": _fixture_path(), "sha256": _fixture_sha256,
			"note": _fixture_note},
		"git_sha": _git_sha,
	}

func _write_exam_result(out: Dictionary) -> void:
	var dir := _exam_out_path.get_base_dir()
	if dir != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://" + dir))
	var fh = FileAccess.open("user://" + _exam_out_path, FileAccess.WRITE)
	if fh != null:
		fh.store_string(JSON.stringify(out, "  "))
		fh.close()

## EXAM-DET-1: everything a verdict was computed from, written next to the
## result as <exam-out>.trace.json — the AI's decision batches and action log as
## of the stop, and every model's final position — so two runs can be diffed
## directly instead of through a hacked spec. `records_sha256` / `units_sha256`
## in the result compare them at a glance. Same code + same fixture + same seed
## must give the same trace; when it does not, that is a determinism bug to
## chase, not noise to average over.
func _write_exam_trace(out: Dictionary) -> void:
	var ai = get_node_or_null("/root/AIPlayer")
	var records: Array = []
	var action_log: Array = []
	if ai != null and "_all_decision_records" in ai:
		records = ai._all_decision_records
		action_log = ai._action_log
	var units := {}
	for uid in GameState.state.get("units", {}):
		var u = GameState.state.units[uid]
		var models := []
		for m in u.get("models", []):
			var p = m.get("position")
			var xy = null
			if p is Vector2:
				xy = [p.x, p.y]
			elif p is Dictionary:
				xy = [float(p.get("x", 0.0)), float(p.get("y", 0.0))]
			models.append({"pos": xy, "alive": bool(m.get("alive", true)),
				"wounds": m.get("current_wounds", null)})
		units[uid] = {"models": models, "status": u.get("status", null), "flags": u.get("flags", {})}
	out["records_sha256"] = JSON.stringify(records).sha256_text()
	out["units_sha256"] = JSON.stringify(units).sha256_text()
	var trace_path := _exam_out_path.get_basename() + ".trace.json"
	out["trace"] = trace_path
	var trace := {
		"id": out.get("id", "exam"), "seed": _seed, "fixture_sha256": _fixture_sha256,
		"git_sha": _git_sha, "stopped": _exam_stop,
		"decision_batches": records, "action_log": action_log, "units": units,
	}
	var dir := trace_path.get_base_dir()
	if dir != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://" + dir))
	var fh = FileAccess.open("user://" + trace_path, FileAccess.WRITE)
	if fh != null:
		fh.store_string(JSON.stringify(trace, " "))
		fh.close()

func _exam_watch_loop() -> void:
	"""Run exactly one phase for the player under test, then grade.

	EXAM-DET-1: the end of the exam is caught by SIGNAL, not by the poll —
	PhaseManager.phase_changed for the end of the phase, AIPlayer.ai_action_taken
	for the action cap — and the AI is stopped inside that signal, so the graded
	state is the same at any frame rate. The poll only watches the two things no
	signal reports: the game ending (the AI stops itself then) and the wall-clock
	cap, which grades nothing (see _exam_timeout)."""
	var pm = get_node_or_null("/root/PhaseManager")
	var ai = get_node_or_null("/root/AIPlayer")
	_exam_start_round = GameState.get_battle_round()
	_exam_max_actions = int(_exam.get("max_actions", 400))
	if not pm.phase_changed.is_connected(_on_exam_phase_changed):
		pm.phase_changed.connect(_on_exam_phase_changed)
	if ai != null and ai.has_signal("ai_action_taken") \
			and not ai.ai_action_taken.is_connected(_on_exam_ai_action_taken):
		ai.ai_action_taken.connect(_on_exam_ai_action_taken)
	# A phase that completes on entry is already over: the AI has not acted yet
	# (it only acts from _process), so stopping here is as exact as the signal.
	_check_exam_phase_over()
	while not _exam_stopped:
		await get_tree().create_timer(0.25).timeout
		if _exam_stopped:
			break
		if pm.game_ended:
			_exam_stop_ai("game ended during the exam phase")
			break
		if (Time.get_ticks_msec() - _start_ticks) / 1000.0 > _max_seconds:
			_exam_timeout()
			return
	# The AI is stopped and nothing else drives the game, so these frames only
	# let deferred calls queued by the exam phase's last action finish.
	for i in range(20):
		await get_tree().process_frame
	_exam_evaluate()

func _on_exam_phase_changed(_new_phase) -> void:
	_check_exam_phase_over()

func _check_exam_phase_over() -> void:
	if _exam_stopped:
		return
	var cur_phase = int(GameState.state.get("meta", {}).get("phase", -1))
	if cur_phase != _exam_phase or GameState.get_battle_round() != _exam_start_round:
		_exam_stop_ai("phase %d complete (now %d)" % [_exam_phase, cur_phase])

func _on_exam_ai_action_taken(_player, _action, _description) -> void:
	if _exam_stopped:
		return
	var ai = get_node_or_null("/root/AIPlayer")
	if ai != null and ai._action_log.size() >= _exam_max_actions:
		_exam_stop_ai("action cap %d reached" % _exam_max_actions)

## EXAM-DET-1: freeze the AI where the exam ends. Called synchronously from the
## signal that ended it (phase_changed is emitted at the very end of
## PhaseManager.transition_to_phase, once the next phase has been entered), so
## the next phase's actions — and the opponent's whole turn — can never leak
## into the graded state or the decision records, however long frames take.
## AIPlayer.enabled gates _process, _evaluate_and_act and its deferred
## executors; nothing else submits actions in an all-AI exam.
func _exam_stop_ai(reason: String) -> void:
	if _exam_stopped:
		return
	_exam_stopped = true
	var ai = get_node_or_null("/root/AIPlayer")
	var acted := 0
	var batches := 0
	if ai != null:
		ai.enabled = false
		acted = ai._action_log.size()
		batches = ai._all_decision_records.size()
	_exam_stop = {
		"reason": reason,
		"phase": int(GameState.state.get("meta", {}).get("phase", -1)),
		"round": GameState.get_battle_round(),
		"active_player": GameState.get_active_player(),
		"actions": acted,
		"decision_batches": batches,
	}
	print("[AIExam] %s after %d actions — AI stopped (%d decision batches)" % [
		reason, acted, batches])

## A wall-clock overrun is not a verdict. Grading a half-played phase made the
## result depend on how fast the box was, so a timeout grades nothing: it writes
## a TIMEOUT result, prints no verdict line (run_exams.sh then lists the exam as
## ERROR, "no verdict"), and exits 3 — the benchmark's timeout code.
func _exam_timeout() -> void:
	_exam_stop_ai("wall-clock cap %.0fs reached" % _max_seconds)
	var out := _exam_result_base("TIMEOUT", 0, 0)
	out["note"] = "the exam phase did not finish within %.0f s of wall clock; nothing was graded" % _max_seconds
	_write_exam_trace(out)
	_write_exam_result(out)
	print("[AIExam] RESULT %s" % JSON.stringify(out))
	print("[AIExam] TIMEOUT %s — no verdict: the phase did not finish within %.0fs of wall clock (raise the spec's max_seconds, or re-run on a less loaded box)" % [
		str(_exam.get("id", "exam")), _max_seconds])
	get_tree().quit(3)

func _kick_off() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	# 1) Load the fixture (a post-deployment save = full game from round 1)
	_ensure_fixture_in_user_saves()
	_fixture_sha256 = _sha256_of(_fixture_path())
	print("[AIBench] fixture %s sha256=%s (%s; %s)" % [_fixture, _fixture_sha256, _fixture_path(), _fixture_note])
	var save_mgr = get_node_or_null("/root/SaveLoadManager")
	if save_mgr == null or not save_mgr.load_game(_fixture):
		_finish_with_error("fixture load failed: %s" % _fixture)
		return
	GameState.state["meta"]["from_save"] = true
	GameConstants.edition = 11
	var mm_cache = get_node_or_null("/root/MissionManager")
	if mm_cache != null and "control_cache_enabled" in mm_cache:
		mm_cache.control_cache_enabled = _obj_cache_mode != "off"
		mm_cache.control_cache_verify = _obj_cache_mode == "verify"
		mm_cache.invalidate_control_cache()
		print("[AIBench] OBJ-CACHE mode: %s" % _obj_cache_mode)
	if _bench_11e and _dispositions == "":
		var d = PrimaryMissionData11e.DISPOSITIONS
		var s_ = maxi(_seed, 0)
		_dispositions = "%s,%s" % [d[s_ % d.size()], d[(s_ / d.size()) % d.size()]]
	if _bench_11e:
		# Empty the fixture's secondary state: CommandPhase then builds the
		# edition's (11e) deck and draws for the active player, as in a new game.
		var smm_11e = get_node_or_null("/root/SecondaryMissionManager")
		if smm_11e == null:
			_finish_with_error("--bench-11e: SecondaryMissionManager missing")
			return
		smm_11e.initialize_for_game()
		print("[AIBench] AB-11E secondary decks reset; CommandPhase builds the 11e deck")
	if _dispositions != "":
		var mm = get_node_or_null("/root/MissionManager")
		var parts = _dispositions.split(",")
		if mm == null or parts.size() != 2:
			_finish_with_error("bad --bench-dispositions: %s" % _dispositions)
			return
		mm.initialize_dispositions_11e(parts[0], parts[1])
		print("[AIBench] AB-11E dispositions %s -> P1 '%s', P2 '%s'" % [_dispositions,
			mm.player_primary_missions.get("1", {}).get("name", "?"),
			mm.player_primary_missions.get("2", {}).get("name", "?")])

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

	# 4) Both players AI, fastest pacing
	var ai = get_node_or_null("/root/AIPlayer")
	if ai == null:
		_finish_with_error("AIPlayer autoload missing")
		return
	ai.configure({1: "AI", 2: "AI"})
	ai.set_ai_speed_preset(0)  # FAST
	# M1: keep every decision batch (see BENCH_RECORD_BATCH_CAP). configure()
	# clears the accumulator, so this must come AFTER it.
	ai._max_decision_record_batches = BENCH_RECORD_BATCH_CAP
	_connect_vp_events()
	for seat in [1, 2]:
		if _seat_ai[seat] == "":
			continue
		if not ai.set_seat_decision_maker(seat, _seat_ai[seat]):
			_finish_with_error("AI version for P%d could not be loaded: %s" % [seat, _seat_ai[seat]])
			return
		var seat_dm = ai.get_seat_decision_makers()[seat]
		seat_dm.reset_caches()
		if _seed >= 0:
			seat_dm.set_ai_seed(_seed)
	_load_profile(1, _p1_profile_path)
	_load_profile(2, _p2_profile_path)
	# PM-2a: plans, like profiles, must be applied AFTER configure() — it calls
	# clear_all_profiles(), which also clears plans.
	_load_plan(1, _p1_plan_path)
	_load_plan(2, _p2_plan_path)
	if _override_path != "":
		var of := FileAccess.open(_override_path, FileAccess.READ)
		var parsed_ov = JSON.parse_string(of.get_as_text()) if of != null else null
		if not (parsed_ov is Array):
			_finish_with_error("--bench-override: %s is not a JSON array" % _override_path)
			return
		AIDecisionMaker.set_rollout_overrides(parsed_ov)
	var mm_start = get_node_or_null("/root/MissionManager")
	_vp_start = mm_start.get_vp_summary() if mm_start != null else {}
	_material_start = _material_lost()
	_start_round = GameState.get_battle_round()
	if _stop_round > 0:
		var pm_stop = get_node_or_null("/root/PhaseManager")
		if pm_stop != null and pm_stop.has_signal("battle_round_started"):
			pm_stop.battle_round_started.connect(_on_round_started_stop)

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
		print("[AIExam] %s: running phase %d, round %d, player %s" % [
			_exam.get("id", "?"), start_phase, GameState.get_battle_round(),
			str(_exam.get("player", 1))])
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

## Load an AI plan and hand it to the decision maker. Like a profile, a plan
## that was ASKED FOR and could not be loaded is FATAL: the game would play on
## with formula deployment and report a perfectly ordinary result, so a
## plan-vs-formula A/B would measure nothing while looking like a null effect.
func _load_plan(player: int, path: String) -> void:
	if path == "":
		return
	var resolved = _resolve_profile_path(path)
	if resolved == "":
		_finish_with_error("plan for P%d could not be resolved: %s" % [player, path])
		return
	var plan = PlanValidator.load_plan_file(resolved)
	if plan.is_empty():
		_finish_with_error("plan for P%d could not be read as JSON: %s" % [player, resolved])
		return
	var verdict = PlanValidator.validate_plan(plan)
	if not verdict.get("valid", false):
		_finish_with_error("plan for P%d is invalid: %s (%s)" % [
			player, resolved, "; ".join(verdict.get("errors", []))])
		return
	AIDecisionMaker.set_player_plan(player, plan)
	_plan_inline[player] = plan
	print("[AIBench] Loaded plan '%s' for P%d from %s (%d placements, %d warnings)" % [
		plan.get("name", "?"), player, resolved,
		plan.get("deployment", {}).get("placements", []).size(),
		verdict.get("warnings", []).size()])

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
		"rules": "11e" if _bench_11e else ("11e_primary_only" if _dispositions != "" else "legacy_fixture"),
		"dispositions": _dispositions,
		"fixture": _fixture,
		"seed": _seed,
		"p1_profile": _p1_profile_path,
		"p2_profile": _p2_profile_path,
		"p1_plan": _p1_plan_path,
		"p2_plan": _p2_plan_path,
		"p1_plan_name": str(_plan_inline.get(1, {}).get("name", "")),
		"p2_plan_name": str(_plan_inline.get(2, {}).get("name", "")),
		"winner": winner,
		"vp": vp,
		"vp_diff_p2_minus_p1": p2_total - p1_total,
		"battle_round": GameState.get_battle_round(),
		"actions_taken": ai._action_log.size() if ai != null else 0,
		"wall_seconds": (Time.get_ticks_msec() - _start_ticks) / 1000.0,
		"time_scale": _time_scale,
		"perf_seconds": _perf_seconds(ai),
		"vp_start": _vp_start,
		"material_start": _material_start,
		"material_end": _material_lost(),
		"start_round": _start_round,
		"rollout_overrides": AIDecisionMaker.get_rollout_overrides(),
		"secondary_events": _secondary_events,
	}

func _perf_seconds(ai) -> Dictionary:
	var out := {}
	if ai == null:
		return out
	for k in ai._perf_usec:
		out[k] = snappedf(float(ai._perf_usec[k]) / 1000000.0, 0.01)
	var mm = get_node_or_null("/root/MissionManager")
	if mm != null and "perf_check_objectives_usec" in mm:
		out["check_all_objectives"] = snappedf(float(mm.perf_check_objectives_usec) / 1000000.0, 0.01)
		out["check_all_objectives_calls"] = mm.perf_check_objectives_calls
		if "perf_check_objectives_hits" in mm:
			out["check_all_objectives_cache_hits"] = mm.perf_check_objectives_hits
			out["objective_cache_mismatches"] = mm.control_cache_mismatches
			out["objective_cache_mode"] = _obj_cache_mode
	return out

func _on_round_started_stop(round_now: int) -> void:
	if _stop_round > 0 and round_now > _stop_round:
		_stop_round = 0  # once
		_write_and_quit(_collect_result("completed", "horizon: stopped at the start of round %d" % round_now), 0)

## Points lost per player: each unit's points x the share of its wounds gone
## (a destroyed unit loses all its points). Units that never had wounds count 0.
func _material_lost() -> Dictionary:
	var out := {"1": 0.0, "2": 0.0}
	for uid in GameState.state.get("units", {}):
		var u = GameState.state.units[uid]
		var owner := str(int(u.get("owner", 0)))
		if not out.has(owner):
			continue
		var pts := float(u.get("meta", {}).get("points", 0))
		var w_stat := float(u.get("meta", {}).get("stats", {}).get("wounds", 1))
		var total := 0.0
		var left := 0.0
		for m in u.get("models", []):
			var mw := float(m.get("wounds", w_stat))
			total += mw
			if m.get("alive", true):
				left += clampf(float(m.get("current_wounds", mw)), 0.0, mw)
		if total > 0.0:
			out[owner] = float(out[owner]) + pts * (1.0 - left / total)
	return out

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
	var smm = get_node_or_null("/root/SecondaryMissionManager")
	if smm != null:
		if smm.has_signal("mission_drawn"):
			smm.mission_drawn.connect(func(pl, mid): _on_secondary_event("drawn", pl, str(mid), 0, ""))
		if smm.has_signal("secondary_vp_scored"):
			smm.secondary_vp_scored.connect(func(pl, vp, mid): _on_secondary_event("scored", pl, str(mid), int(vp), ""))
		if smm.has_signal("mission_discarded"):
			smm.mission_discarded.connect(func(pl, mid, why): _on_secondary_event("discarded", pl, str(mid), 0, str(why)))

func _on_secondary_event(kind: String, player: int, mission_id: String, vp: int, note: String) -> void:
	_secondary_events.append({"round": GameState.get_battle_round(), "phase": GameState.get_current_phase(),
		"active": GameState.get_active_player(), "player": player, "kind": kind, "mission": mission_id,
		"vp": vp, "note": note})

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

## The game loads user://saves/<fixture>.w40ksave (SaveLoadManager.save_directory).
## A fresh container has no copy there, so copy it (and its .meta) from the repo.
##
## EXAM-DET-1: the TRACKED copy in res://tests/saves/ is the source of truth. It
## is copied in when the user:// copy is missing OR its bytes differ. This used
## to copy only when missing — like run_exams.sh's `cp -n` and SaveLoadManager's
## non-destructive legacy migration from res://saves/ — so a user dir that
## outlived a fixture change kept serving the OLD board, and a verdict depended
## on the history of the machine instead of on the code: on identical code
## mv01 passed against a dbdb29f-era copy (obj_nml_1 at (400, 880)) and failed
## against the tracked fixture (obj_nml_1 at (1500, 750) since 6f07340).
## ScenarioRunner learned the same lesson on 2026-10-17. A fixture that is NOT
## tracked (a rollout save, a dev save in res://saves/) keeps first-copy-wins,
## since nothing says which copy is right. Either way the loaded file's sha256
## is stamped into the result (_fixture_sha256).
func _ensure_fixture_in_user_saves() -> void:
	var dst_dir := "user://saves/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dst_dir))
	var dst := dst_dir + _fixture + ".w40ksave"
	var tracked_dir := "res://tests/saves/"
	if FileAccess.file_exists(tracked_dir + _fixture + ".w40ksave"):
		var had := FileAccess.file_exists(dst)
		var old_sha := _sha256_of(dst)
		var new_sha := _sha256_of(tracked_dir + _fixture + ".w40ksave")
		var copied := _sync_fixture_files(tracked_dir, dst_dir)
		if not had:
			_fixture_note = "copied from %s" % tracked_dir
			print("[AIBench] fixture %s copied from %s to %s" % [_fixture, tracked_dir, dst_dir])
		elif old_sha != new_sha:
			_fixture_note = "replaced a stale user://saves copy (sha256 %s) from %s" % [old_sha.left(16), tracked_dir]
			print("[AIBench] fixture %s: the %s copy was STALE (sha256 %s, tracked %s) — replaced from %s" % [
				_fixture, dst_dir, old_sha.left(16), new_sha.left(16), tracked_dir])
		elif copied > 0:
			_fixture_note = "refreshed the .meta from %s" % tracked_dir
		else:
			_fixture_note = "user://saves copy matches %s" % tracked_dir
		return
	if FileAccess.file_exists(dst):
		_fixture_note = "untracked fixture: using the existing user://saves copy"
		return
	if FileAccess.file_exists("res://saves/" + _fixture + ".w40ksave"):
		_sync_fixture_files("res://saves/", dst_dir)
		_fixture_note = "untracked fixture: copied from res://saves/"
		print("[AIBench] fixture %s copied from res://saves/ to %s" % [_fixture, dst_dir])
		return
	_fixture_note = "not found in res://tests/saves/ or res://saves/"
	print("[AIBench] WARNING: fixture %s not found in res://tests/saves/ or res://saves/" % _fixture)

## Copy <fixture>.w40ksave and .meta from src_dir to dst_dir wherever the
## destination is missing or differs byte-for-byte. Returns how many it wrote.
func _sync_fixture_files(src_dir: String, dst_dir: String) -> int:
	var n := 0
	for ext in [".w40ksave", ".meta"]:
		var src: String = src_dir + _fixture + ext
		var dst: String = dst_dir + _fixture + ext
		if not FileAccess.file_exists(src):
			continue
		if FileAccess.file_exists(dst) and _sha256_of(dst) == _sha256_of(src):
			continue
		var data := FileAccess.get_file_as_bytes(src)
		var f := FileAccess.open(dst, FileAccess.WRITE)
		if f != null:
			f.store_buffer(data)
			f.close()
			n += 1
		else:
			print("[AIBench] WARNING: could not write %s" % dst)
	return n

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
	var plan_path = _p1_plan_path if player == 1 else _p2_plan_path
	var out := {
		"path": path,
		"sha256": _sha256_of(path),
		"inline": _profile_inline.get(player, {}),
	}
	# PM-2a: a record has to say which PLAN produced these decisions, for the
	# same reason it says which profile did — a plan-vs-formula A/B is
	# unreadable if the arm is not stamped into the artifact.
	if plan_path != "":
		out["plan_path"] = plan_path
		out["plan_sha256"] = _sha256_of(plan_path)
		out["plan_name"] = str(_plan_inline.get(player, {}).get("name", ""))
	return out

func _build_provenance() -> Dictionary:
	var fixture_path = _fixture_path()
	return AIGameRecord.build_provenance(
		_git_sha, Engine.get_version_info().get("string", ""), _fixture,
		fixture_path, _sha256_of(fixture_path),
		_profile_provenance(1), _profile_provenance(2),
		_seed, _time_scale, _arm)


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
