extends Node

# TutorialManager — lesson lifecycle director for the in-game tutorial
# (PRPs/tutorial_system.md §5.1/§5.2). Data-driven: lessons are JSON files in
# res://data/tutorials/lessons/, checkpoint fixtures ship in
# res://data/tutorials/fixtures/ and are staged into user://saves/ exactly the
# way ScenarioRunner stages test fixtures (ScenarioRunner.gd:83-97).
#
# Two hooks into the rest of the game:
#   observe — PhaseManager.phase_action_taken (successful actions only)
#   gate    — BasePhase.execute_action consults is_action_allowed() and
#             returns the standard failure dict when a lesson blocks an action
#
# Step "done" conditions are outcome-based and deliberately reuse the windowed
# scenario assert vocabulary (tests/scenarios/_schema.md): state paths with
# equals/exists/expect_min/expect_max, node_visible/node_hidden, phase,
# action (matched against phase_action_taken payloads), multiline script
# predicates, and ack (explicit Continue). Combinators: any / all.

signal lesson_started(lesson_id: String)
signal step_changed(step_index: int)
signal lesson_completed(lesson_id: String)
signal tutorial_exited()

const TutorialScriptLib = preload("res://scripts/tutorial/TutorialScript.gd")

const LESSONS_DIR := "res://data/tutorials/lessons/"
const FIXTURES_DIR := "res://data/tutorials/fixtures/"
const PROGRESS_PATH := "user://tutorial_progress.cfg"

# Always-allowed action prefixes while gating — reactive declines must never
# soft-lock a lesson (PRP §4.3 failure-tolerance rules).
const IMPLICIT_SAFE_PREFIXES := ["DECLINE_"]
const TUTORIAL_PLAYER := 1
const BLOCK_TOAST_COOLDOWN_MS := 1500
const POLL_INTERVAL_S := 0.1
const SETTLE_FRAMES := 8

var active: bool = false
var current_lesson: Dictionary = {}
var current_step_index: int = -1
var course_mode: bool = false

var _steps: Array = []
var _captured: Dictionary = {}
var _ack_done: bool = false
var _action_hits: Dictionary = {}   # done-tree path ("0.1") -> true once seen
var _step_script: GDScript = null   # compiled per-step script predicate cache
var _script_cache: Dictionary = {}  # code -> GDScript for capture snippets
var _bypass_gate: bool = false
var _last_block_toast_ms: int = 0
var _poll_timer: Timer = null
var _hint_timer: Timer = null
var _progress: ConfigFile = ConfigFile.new()
var _lessons_cache: Array = []


func _ready() -> void:
	_progress.load(PROGRESS_PATH)  # missing file is fine (fresh profile)
	_poll_timer = Timer.new()
	_poll_timer.wait_time = POLL_INTERVAL_S
	_poll_timer.timeout.connect(_on_poll)
	add_child(_poll_timer)
	_hint_timer = Timer.new()
	_hint_timer.one_shot = true
	_hint_timer.timeout.connect(_on_hint_timeout)
	add_child(_hint_timer)
	PhaseManager.phase_action_taken.connect(_on_phase_action_taken)
	InputDeviceManager.device_changed.connect(func(_mode): refresh_prompt())
	print("TutorialManager: ready (%d lessons found)" % get_lessons().size())


# ------------------------------------------------------------- lifecycle ----

func start_lesson(lesson_id: String, as_course: bool = false) -> void:
	var meta := _lesson_meta(lesson_id)
	if meta.is_empty():
		ToastManager.show_error("Tutorial lesson not found: %s" % lesson_id)
		return
	var loaded: Dictionary = TutorialScriptLib.load_lesson(meta.path)
	if not loaded.ok:
		for e in loaded.errors:
			print("TutorialManager: lesson error: %s" % str(e))
		ToastManager.show_error("Tutorial lesson failed to load (see log)")
		return
	course_mode = as_course
	current_lesson = loaded.lesson
	_steps = current_lesson.get("steps", [])
	current_step_index = -1
	_mark_started(lesson_id)
	print("TutorialManager: starting lesson '%s' (%d steps)" % [lesson_id, _steps.size()])
	_boot_and_arm()


func start_full_course() -> void:
	var lessons := get_lessons()
	if lessons.is_empty():
		return
	start_lesson(str(lessons[0].id), true)


func next_lesson() -> void:
	var nid := _next_lesson_id(str(current_lesson.get("id", "")))
	if nid == "":
		exit_tutorial()
		return
	_teardown(false)
	start_lesson(nid, course_mode)


func exit_tutorial() -> void:
	print("TutorialManager: exit tutorial")
	_teardown(true)
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _teardown(emit_exit: bool) -> void:
	active = false
	_bypass_gate = false
	_poll_timer.stop()
	_hint_timer.stop()
	_step_script = null
	if GameState.state.has("meta"):
		GameState.state.meta.erase("tutorial")
		GameState.state.meta.erase("tutorial_lesson")
	var overlay := get_node_or_null("/root/TutorialOverlay")
	if overlay:
		overlay.hide_all()
	if emit_exit:
		emit_signal("tutorial_exited")


# Boot the lesson's world, wait for the Main scene to settle, then arm step 0.
func _boot_and_arm() -> void:
	var boot: Dictionary = current_lesson.get("boot", {})
	# Deterministic dice for taught rolls (PRP §5.4).
	var seed_val := int(boot.get("rng_seed", -1))
	if seed_val >= 0:
		if RulesEngine.has_method("set_test_seed"):
			RulesEngine.set_test_seed(seed_val)
		if SecondaryMissionManager and SecondaryMissionManager.has_method("set_test_seed"):
			SecondaryMissionManager.set_test_seed(seed_val)

	if boot.has("fixture"):
		if not _load_fixture(str(boot.fixture)):
			ToastManager.show_error("Tutorial: could not load lesson fixture")
			return
		GameState.state.meta["from_save"] = true
		GameState.state.meta.erase("from_menu")
	elif boot.has("config"):
		_initialize_from_config(boot.config)
		GameState.state.meta["from_menu"] = true
		GameState.state.meta.erase("from_save")
	GameState.state.meta["tutorial"] = true
	GameState.state.meta["tutorial_lesson"] = str(current_lesson.get("id", ""))

	get_tree().change_scene_to_file("res://scenes/Main.tscn")
	await _await_main_ready()

	# Fixtures are saved at the lesson's phase; transition only on mismatch.
	if boot.has("phase"):
		var want := int(boot.phase)
		if int(GameState.state.get("meta", {}).get("phase", -1)) != want:
			PhaseManager.transition_to_phase(want)
			for i in range(SETTLE_FRAMES):
				await get_tree().process_frame

	active = true
	emit_signal("lesson_started", str(current_lesson.get("id", "")))
	_enter_step(0)


func _await_main_ready() -> void:
	# Mirrors ScenarioRunner's post-load settling (ScenarioRunner.gd:83-186).
	var tries := 0
	while tries < 600:
		var scene := get_tree().current_scene
		if scene != null and scene.name == "Main" and scene.is_node_ready():
			break
		tries += 1
		await get_tree().process_frame
	for i in range(SETTLE_FRAMES):
		await get_tree().process_frame


func _load_fixture(fixture: String) -> bool:
	var fixture_file := fixture if fixture.ends_with(".w40ksave") else fixture + ".w40ksave"
	var src_path := FIXTURES_DIR + fixture_file
	var dst_path: String = SaveLoadManager.save_directory + fixture_file
	if FileAccess.file_exists(src_path):
		for pair in [[src_path, dst_path],
				[src_path.replace(".w40ksave", ".meta"), dst_path.replace(".w40ksave", ".meta")]]:
			if not FileAccess.file_exists(pair[0]):
				continue
			var src := FileAccess.open(pair[0], FileAccess.READ)
			var dst := FileAccess.open(pair[1], FileAccess.WRITE)
			if src == null or dst == null:
				print("TutorialManager: failed staging %s" % str(pair[0]))
				return false
			dst.store_buffer(src.get_buffer(src.get_length()))
			dst.close()
	else:
		print("TutorialManager: fixture not shipped at %s (trying user saves)" % src_path)
	return SaveLoadManager.load_game(fixture)


# Fresh-boot path for deployment-style lessons and fixture generation.
# Mirrors MainMenu._initialize_game_with_config (scripts/MainMenu.gd:1328) —
# kept in sync manually; the menu remains the source of truth for real games.
func _initialize_from_config(config: Dictionary) -> void:
	GameState.state.clear()
	GameState.initialize_default_state(config.get("deployment", "search_and_destroy"))
	GameState.state.meta["game_config"] = config
	if TerrainManager and config.has("terrain"):
		TerrainManager.current_layout = config.terrain
		TerrainManager.load_terrain_layout(config.terrain)
	if BoardState:
		BoardState.initialize_deployment_zones(config.get("deployment", "search_and_destroy"))
	if MissionManager:
		MissionManager.initialize_mission(config.get("mission", "take_and_hold"))
	GameState.state.units.clear()
	for player in [1, 2]:
		var army_name := str(config.get("player%d_army" % player, ""))
		var army: Dictionary = ArmyListManager.load_army_for_game(army_name, player)
		if army.is_empty():
			print("TutorialManager: FAILED to load army '%s' for player %d" % [army_name, player])
		else:
			ArmyListManager.apply_army_to_game_state(army, player)
	var secondary_mgr := get_node_or_null("/root/SecondaryMissionManager")
	if secondary_mgr:
		secondary_mgr.initialize_for_game()
		# Fixed secondaries keep the tactical draw modal out of lessons
		# (mirrors MainMenu._initialize_game_with_config, P2-85 block).
		for player in [1, 2]:
			if str(config.get("player%d_secondary_mode" % player, "tactical")) == "fixed":
				var fixed: Array = config.get("player%d_fixed_missions" % player, [])
				if fixed.size() == 2:
					var result: Dictionary = secondary_mgr.setup_fixed_missions(player, fixed)
					if not result.get("success", false):
						print("TutorialManager: fixed missions setup failed for player %d: %s" % [player, str(result.get("error", ""))])
	GameState.state.meta["game_config"] = config


# ----------------------------------------------------------------- steps ----

func _enter_step(index: int) -> void:
	if index >= _steps.size():
		_complete_lesson()
		return
	current_step_index = index
	var step: Dictionary = _steps[index]

	# Device-filtered steps (PRP §4.4) are skipped silently on the other device.
	var dev := str(step.get("device", "any"))
	if (dev == "pad" and not InputDeviceManager.is_pad_active()) \
			or (dev == "kbm" and InputDeviceManager.is_pad_active()):
		print("TutorialManager: skipping step '%s' (device=%s)" % [str(step.get("id", "")), dev])
		_enter_step(index + 1)
		return

	_ack_done = false
	_action_hits = {}
	_step_script = null
	_captured = {}
	var capture: Dictionary = step.get("capture", {})
	for key in capture:
		var spec = capture[key]
		if typeof(spec) == TYPE_DICTIONARY and spec.has("script"):
			_captured[key] = _run_snippet(str(spec.script))
	var done: Dictionary = step.get("done", {})
	if done.has("script"):
		_step_script = _compile_snippet(str(done.script))

	_show_current_step()
	var hint_after := float(step.get("hint_after_s", 25.0))
	if step.has("hint") and hint_after > 0.0:
		_hint_timer.start(hint_after)
	else:
		_hint_timer.stop()
	_poll_timer.start()
	emit_signal("step_changed", index)
	print("TutorialManager: step %d/%d '%s'" % [index + 1, _steps.size(), str(step.get("id", ""))])


func _show_current_step() -> void:
	var overlay := get_node_or_null("/root/TutorialOverlay")
	if overlay == null or current_step_index < 0 or current_step_index >= _steps.size():
		return
	var step: Dictionary = _steps[current_step_index]
	var pad := InputDeviceManager.is_pad_active()
	var body: String = TutorialScriptLib.render_text(TutorialScriptLib.body_for_device(step, pad), pad)
	overlay.show_step({
		"bark": str(step.get("prompt", {}).get("bark", "")),
		"body": body,
		"progress": "Step %d / %d — %s" % [current_step_index + 1, _steps.size(), str(current_lesson.get("title", ""))],
		"ack": _is_ack_step(step),
		"anchor": step.get("anchor", {}),
		"spotlight": str(step.get("spotlight", "soft" if step.has("anchor") else "none")),
	})


func refresh_prompt() -> void:
	if active:
		_show_current_step()


func _is_ack_step(step: Dictionary) -> bool:
	return bool(step.get("done", {}).get("ack", false))


func ack() -> void:
	if not active:
		return
	_ack_done = true
	_check_done()


func skip_step() -> void:
	if not active or current_step_index < 0 or current_step_index >= _steps.size():
		return
	var step: Dictionary = _steps[current_step_index]
	print("TutorialManager: skip step '%s'" % str(step.get("id", "")))
	var fallback: Dictionary = step.get("skip_fallback", {})
	if fallback.has("dispatch") and PhaseManager.current_phase_instance != null:
		_bypass_gate = true
		var result: Dictionary = PhaseManager.current_phase_instance.execute_action(fallback.dispatch)
		_bypass_gate = false
		if not result.get("success", false):
			print("TutorialManager: skip_fallback dispatch failed: %s" % str(result.get("error", "")))
	_advance_step()


func _complete_step() -> void:
	var step: Dictionary = _steps[current_step_index]
	var on_done: Dictionary = step.get("on_done", {})
	if on_done.has("toast"):
		ToastManager.show_success(str(on_done.toast))
	_advance_step()


func _advance_step() -> void:
	_poll_timer.stop()
	_hint_timer.stop()
	_enter_step(current_step_index + 1)


func _complete_lesson() -> void:
	var lesson_id := str(current_lesson.get("id", ""))
	print("TutorialManager: lesson '%s' COMPLETE" % lesson_id)
	_poll_timer.stop()
	_hint_timer.stop()
	_progress.set_value("lessons", lesson_id + "_completed", true)
	_progress.save(PROGRESS_PATH)
	emit_signal("lesson_completed", lesson_id)
	var summary: Dictionary = current_lesson.get("summary", {})
	var bullets: Array = summary.get("bullets", [])
	var body := ""
	for b in bullets:
		body += "•  %s\n" % str(b)
	var overlay := get_node_or_null("/root/TutorialOverlay")
	if overlay:
		overlay.show_summary({
			"bark": str(summary.get("bark", "PROPPA JOB!")),
			"body": body.strip_edges(),
			"progress": "%s — complete" % str(current_lesson.get("title", "")),
			"has_next": _next_lesson_id(lesson_id) != "",
		})
	# Stay active: the gate keeps the battle paused-in-place under the summary
	# card until the player picks Next Lesson / Back to Menu.


# ----------------------------------------------------------- done checks ----

func _on_phase_action_taken(action: Dictionary) -> void:
	if not active or current_step_index < 0 or current_step_index >= _steps.size():
		return
	var done: Dictionary = _steps[current_step_index].get("done", {})
	_latch_action_conditions(done, "0", action)
	_check_done()


func _latch_action_conditions(cond: Dictionary, path: String, action: Dictionary) -> void:
	if cond.has("any") or cond.has("all"):
		var arr: Array = cond.get("any", cond.get("all", []))
		for i in range(arr.size()):
			if typeof(arr[i]) == TYPE_DICTIONARY:
				_latch_action_conditions(arr[i], "%s.%d" % [path, i], action)
		return
	if cond.has("action") and typeof(cond.action) == TYPE_DICTIONARY:
		if _action_matches(cond.action, action):
			_action_hits[path] = true


func _action_matches(expected: Dictionary, action: Dictionary) -> bool:
	for key in expected:
		if not action.has(key):
			return false
		if str(action[key]) != str(expected[key]):
			return false
	return true


func _on_poll() -> void:
	_check_done()


func _check_done() -> void:
	if not active or current_step_index < 0 or current_step_index >= _steps.size():
		return
	var done: Dictionary = _steps[current_step_index].get("done", {})
	if _eval_condition(done, "0"):
		_complete_step()


func _eval_condition(cond: Dictionary, path: String) -> bool:
	if cond.has("any"):
		var arr: Array = cond.any
		for i in range(arr.size()):
			if _eval_condition(arr[i], "%s.%d" % [path, i]):
				return true
		return false
	if cond.has("all"):
		var arr2: Array = cond.all
		for i in range(arr2.size()):
			if not _eval_condition(arr2[i], "%s.%d" % [path, i]):
				return false
		return true
	if cond.has("ack"):
		return _ack_done
	if cond.has("action"):
		return _action_hits.get(path, false)
	if cond.has("phase"):
		return int(GameState.state.get("meta", {}).get("phase", -1)) == int(cond.phase)
	if cond.has("node_visible") or cond.has("node_hidden"):
		var want_visible: bool = cond.has("node_visible")
		var node_path := str(cond.get("node_visible", cond.get("node_hidden", "")))
		var n := get_tree().root.get_node_or_null(NodePath(node_path))
		var vis: bool = n != null and n is CanvasItem and (n as CanvasItem).is_visible_in_tree()
		return vis == want_visible
	if cond.has("state"):
		var value = _walk_path(GameState.state, str(cond.state))
		return _compare(cond, value)
	if cond.has("script"):
		# Compile on demand (cached by code string) — script leaves can sit
		# at the top level OR nested inside any/all combinators.
		var leaf_script := _compile_snippet(str(cond.script))
		if leaf_script == null:
			return false
		var value2 = _call_snippet(leaf_script)
		if cond.has("equals") or cond.has("not_equals") or cond.has("exists") \
				or cond.has("expect_min") or cond.has("expect_max"):
			return _compare(cond, value2)
		return bool(value2)
	return false


func _compare(cond: Dictionary, actual) -> bool:
	if cond.has("exists"):
		return (actual != null) == bool(cond.exists)
	if cond.has("equals"):
		return _loose_equals(actual, cond.equals)
	if cond.has("not_equals"):
		return not _loose_equals(actual, cond.not_equals)
	if cond.has("expect_min"):
		return actual != null and float(actual) >= float(cond.expect_min)
	if cond.has("expect_max"):
		return actual != null and float(actual) <= float(cond.expect_max)
	return actual != null


func _loose_equals(a, b) -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return is_equal_approx(float(a), float(b))
	return str(a) == str(b) if typeof(a) != typeof(b) else a == b


func _walk_path(root, path: String):
	if path == "":
		return root
	var cur = root
	for seg in path.split("."):
		if cur == null:
			return null
		if typeof(cur) == TYPE_DICTIONARY:
			if not cur.has(seg):
				return null
			cur = cur[seg]
		elif typeof(cur) == TYPE_ARRAY:
			if not seg.is_valid_int() or int(seg) >= (cur as Array).size():
				return null
			cur = cur[int(seg)]
		else:
			return null
	return cur


# ------------------------------------------------------------ gate + nudge --

# Consulted by BasePhase.execute_action while a lesson is active. Outcome-based
# lessons gate ACTIONS only — camera/selection/reading never dispatch actions
# and are always free.
func is_action_allowed(action: Dictionary) -> bool:
	if not active or _bypass_gate:
		return true
	# The opponent (AI player 2) always plays freely (PRP §5.4).
	if GameState.get_active_player() != TUTORIAL_PLAYER:
		return true
	var action_type := str(action.get("type", ""))
	for prefix in IMPLICIT_SAFE_PREFIXES:
		if action_type.begins_with(prefix):
			return true
	if current_step_index < 0 or current_step_index >= _steps.size():
		return false
	var allow = _steps[current_step_index].get("allow", [])
	if typeof(allow) == TYPE_STRING and str(allow) == "*":
		return true
	if typeof(allow) == TYPE_ARRAY:
		return allow.has(action_type)
	return false


func on_action_blocked(action: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_block_toast_ms < BLOCK_TOAST_COOLDOWN_MS:
		return
	_last_block_toast_ms = now
	var step_title := ""
	if current_step_index >= 0 and current_step_index < _steps.size():
		step_title = str(_steps[current_step_index].get("prompt", {}).get("bark", ""))
	if step_title == "":
		step_title = "follow da current step"
	ToastManager.show_warning("Oi! Not dat one, ya git — %s" % step_title)
	print("TutorialManager: blocked action '%s' at step %d" % [str(action.get("type", "")), current_step_index])
	var overlay := get_node_or_null("/root/TutorialOverlay")
	if overlay:
		overlay.shake()


func _on_hint_timeout() -> void:
	if not active or current_step_index < 0 or current_step_index >= _steps.size():
		return
	var step: Dictionary = _steps[current_step_index]
	var hint = step.get("hint", {})
	var pad := InputDeviceManager.is_pad_active()
	var text := ""
	if typeof(hint) == TYPE_DICTIONARY:
		text = TutorialScriptLib.body_for_device({"prompt": hint}, pad)
	else:
		text = str(hint)
	if text == "":
		return
	var overlay := get_node_or_null("/root/TutorialOverlay")
	if overlay:
		overlay.show_hint(TutorialScriptLib.render_text(text, pad))


# ------------------------------------------------------- snippets (script) --

# Statement-mode GDScript evaluation, same pattern as ScenarioRunner's
# execute_script multiline mode: autoloads resolve by global name; `node` is
# /root, `tree` the SceneTree, `main` the current scene, `captured` the step's
# captured baselines.
func _compile_snippet(code: String) -> GDScript:
	if _script_cache.has(code):
		return _script_cache[code]
	var lines := code.split("\n")
	var body := ""
	for line in lines:
		body += "\t" + line + "\n"
	var src := "extends RefCounted\nfunc _run(node, tree, main, captured):\n" + body
	if not code.contains("return"):
		src += "\treturn null\n"
	var script := GDScript.new()
	script.source_code = src
	var err := script.reload()
	if err != OK:
		print("TutorialManager: snippet failed to compile (err %d):\n%s" % [err, code])
		return null
	_script_cache[code] = script
	return script


func _call_snippet(script: GDScript):
	if script == null:
		return null
	var inst = script.new()
	return inst._run(get_tree().root, get_tree(), get_tree().current_scene, _captured)


func _run_snippet(code: String):
	return _call_snippet(_compile_snippet(code))


# ------------------------------------------------------ progress + picker ---

func get_lessons() -> Array:
	if not _lessons_cache.is_empty():
		return _lessons_cache
	var out: Array = []
	var dir := DirAccess.open(LESSONS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(LESSONS_DIR + fname))
			if typeof(parsed) == TYPE_DICTIONARY and parsed.has("id"):
				out.append({
					"id": str(parsed.id),
					"title": str(parsed.get("title", parsed.id)),
					"subtitle": str(parsed.get("subtitle", "")),
					"est_minutes": int(parsed.get("est_minutes", 5)),
					"order": int(parsed.get("order", 999)),
					"path": LESSONS_DIR + fname,
				})
		fname = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a, b): return a.order < b.order)
	_lessons_cache = out
	return out


func _lesson_meta(lesson_id: String) -> Dictionary:
	for l in get_lessons():
		if str(l.id) == lesson_id:
			return l
	return {}


func _next_lesson_id(lesson_id: String) -> String:
	var lessons := get_lessons()
	for i in range(lessons.size() - 1):
		if str(lessons[i].id) == lesson_id:
			return str(lessons[i + 1].id)
	return ""


func is_completed(lesson_id: String) -> bool:
	return bool(_progress.get_value("lessons", lesson_id + "_completed", false))


func _mark_started(lesson_id: String) -> void:
	var count := int(_progress.get_value("lessons", lesson_id + "_started", 0))
	_progress.set_value("lessons", lesson_id + "_started", count + 1)
	_progress.save(PROGRESS_PATH)


func any_lesson_completed() -> bool:
	for l in get_lessons():
		if is_completed(str(l.id)):
			return true
	return false


# Called by MainMenu when a real (non-tutorial) game starts — feeds the TM4
# first-launch nudge heuristic.
func note_real_game_started() -> void:
	var count := int(_progress.get_value("meta", "real_games_started", 0))
	_progress.set_value("meta", "real_games_started", count + 1)
	_progress.save(PROGRESS_PATH)


func reset_progress() -> void:
	_progress = ConfigFile.new()
	_progress.save(PROGRESS_PATH)


# Exposed for windowed scenarios.
func current_step_id() -> String:
	if current_step_index < 0 or current_step_index >= _steps.size():
		return ""
	return str(_steps[current_step_index].get("id", ""))
