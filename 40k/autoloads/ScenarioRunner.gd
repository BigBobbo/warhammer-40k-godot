extends Node

# ScenarioRunner — executes a JSON-defined scenario file against the running
# game, simulating player input via real InputEvents and asserting against
# both the visible scene tree and the underlying GameState.
#
# Activates only when `--scenario-file=PATH` is on the cmdline. Otherwise it
# is a no-op autoload.
#
# See 40k/tests/scenarios/_schema.md for the scenario format.
#
# Wire protocol:
#   godot --path 40k --scenario-file=tests/scenarios/sp/<id>.json
#
# Output:
#   user://test_results/scenarios/<scenario_id>.json     — result summary
#   user://test_results/scenarios/<scenario_id>_<label>.png — screenshots
#   user://test_results/scenarios/<scenario_id>_FAIL_step_<n>.png — auto on failure
#
# Process exit code: 0 on all-pass, 1 on any failure.

signal scenario_finished(scenario_id: String, passed: int, failed: int)

var _scenario_path: String = ""
var _scenario: Dictionary = {}
var _step_results: Array = []
var _last_action_result = null
var _start_cp: Dictionary = {}  # player_id -> cp at scenario start (for delta_from_start)
var _started: bool = false

const RESULTS_SUBDIR := "test_results/scenarios"


func _ready() -> void:
	# Parse cmdline args. We accept either engine args or user args (after `--`).
	var args = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for a in args:
		if typeof(a) == TYPE_STRING and a.begins_with("--scenario-file="):
			_scenario_path = a.split("=", true, 1)[1]
			break

	if _scenario_path == "":
		return  # not in scenario mode — no-op autoload

	print("[ScenarioRunner] Activating, scenario_file=%s" % _scenario_path)
	# Defer to next idle frame so other autoloads (GameState, SaveLoadManager,
	# PhaseManager, etc.) finish their _ready before we touch them.
	call_deferred("_kick_off")


func _kick_off() -> void:
	if _started:
		return
	_started = true
	await get_tree().process_frame
	await get_tree().process_frame
	_run_scenario()


func _run_scenario() -> void:
	# 1) Read JSON
	var f := FileAccess.open(_scenario_path, FileAccess.READ)
	if f == null:
		_fail_and_quit("could not open scenario file: %s" % _scenario_path)
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		_fail_and_quit("scenario JSON failed to parse: %s" % _scenario_path)
		return
	_scenario = parsed

	var scenario_id: String = _scenario.get("id", "unnamed")
	print("[ScenarioRunner] === scenario id=%s ===" % scenario_id)

	# 2) Load fixture (optional)
	var fixture: String = _scenario.get("fixture", "")
	if fixture != "":
		var save_mgr = get_node_or_null("/root/SaveLoadManager")
		var game_state = get_node_or_null("/root/GameState")
		if save_mgr == null or game_state == null:
			_fail_and_quit("autoloads missing (SaveLoadManager / GameState)")
			return
		var ok = save_mgr.load_game(fixture)
		if not ok:
			_fail_and_quit("fixture load failed: %s" % fixture)
			return
		# Critical: tell Main._ready() to honour the loaded state instead of reinitializing
		game_state.state["meta"]["from_save"] = true
		print("[ScenarioRunner] fixture loaded: %s" % fixture)

	# 3) Set RNG seed (optional)
	var rng_seed = _scenario.get("rng_seed", null)
	if rng_seed != null and typeof(rng_seed) == TYPE_FLOAT:
		rng_seed = int(rng_seed)
	if typeof(rng_seed) == TYPE_INT:
		var rules = get_node_or_null("/root/RulesEngine")
		if rules != null:
			rules.set_test_seed(rng_seed)
			print("[ScenarioRunner] rng_seed=%d" % rng_seed)

	# 4) Switch to the live battle scene so the UI / TokenLayer renders the
	#    loaded fixture — this is the rendering pipeline that headless
	#    state-mutation tests bypassed.
	if fixture != "":
		print("[ScenarioRunner] switching to res://scenes/Main.tscn")
		get_tree().change_scene_to_file("res://scenes/Main.tscn")
		# Wait for the new scene to be ready
		var waited := 0
		while waited < 240 and (get_tree().current_scene == null or not get_tree().current_scene.is_node_ready()):
			await get_tree().process_frame
			waited += 1
		# Extra settling frames for TokenLayer / dialog instantiation
		for i in range(8):
			await get_tree().process_frame

	# 5) Phase transition (optional)
	if _scenario.has("transition_to_phase"):
		var phase_n = _scenario["transition_to_phase"]
		if typeof(phase_n) == TYPE_FLOAT:
			phase_n = int(phase_n)
		if typeof(phase_n) == TYPE_INT:
			var phase_mgr = get_node_or_null("/root/PhaseManager")
			if phase_mgr != null:
				phase_mgr.transition_to_phase(phase_n)
				print("[ScenarioRunner] transitioned to phase %d" % phase_n)
				for i in range(4):
					await get_tree().process_frame

	# 6) Capture starting CP for delta_from_start asserts
	_start_cp = _capture_cp_snapshot()

	# 7) Walk steps
	var steps = _scenario.get("steps", [])
	var passed := 0
	var failed := 0
	for i in range(steps.size()):
		var step = steps[i]
		var act = str(step.get("act", ""))
		print("[ScenarioRunner] step %d/%d: %s" % [i, steps.size() - 1, act])
		var rec: Dictionary = await _execute_step(i, act, step)
		_step_results.append(rec)
		if rec.get("pass", false):
			passed += 1
			print("  PASS")
		else:
			failed += 1
			var detail = rec.get("error", "")
			print("  FAIL  %s" % detail)
			_capture_failure_screenshot(scenario_id, i)

	# 8) Reset RNG so subsequent normal play is unaffected
	var rules2 = get_node_or_null("/root/RulesEngine")
	if rules2 != null:
		rules2.set_test_seed(-1)

	# 9) Write results
	_write_results(scenario_id, passed, failed)
	print("[ScenarioRunner] === %s: %d passed, %d failed ===" % [scenario_id, passed, failed])
	emit_signal("scenario_finished", scenario_id, passed, failed)
	get_tree().quit(0 if failed == 0 else 1)


# ============================================================================
# STEP DISPATCH
# ============================================================================

func _execute_step(i: int, act: String, step: Dictionary) -> Dictionary:
	var rec := {"step": i, "act": act}
	match act:
		"wait_seconds":
			var s = float(step.get("seconds", 0.1))
			await get_tree().create_timer(s).timeout
			rec["pass"] = true
		"wait_frames":
			var n = int(step.get("frames", 1))
			for j in range(n):
				await get_tree().process_frame
			rec["pass"] = true
		"screenshot":
			rec.merge(await _do_screenshot(step), true)
		"dispatch_action":
			rec.merge(await _do_dispatch_action(step), true)
		"click_unit":
			rec.merge(await _do_click_unit(step), true)
		"click_node":
			rec.merge(await _do_click_node(step), true)
		"simulate_key":
			rec.merge(await _do_simulate_key(step), true)
		"expect_state":
			rec.merge(_do_expect_state(step), true)
		"expect_cp":
			rec.merge(_do_expect_cp(step), true)
		"expect_action_result":
			rec.merge(_do_expect_action_result(step), true)
		"expect_phase":
			rec.merge(_do_expect_phase(step), true)
		"expect_phase_property":
			rec.merge(_do_expect_phase_property(step), true)
		"expect_node_visible":
			rec.merge(await _do_expect_node_visible(step), true)
		"expect_node_property":
			rec.merge(_do_expect_node_property(step), true)
		"expect_token_visible":
			rec.merge(await _do_expect_token_visible(step), true)
		"execute_script":
			rec.merge(_do_execute_script(step), true)
		"pixel_diff":
			rec.merge(_do_pixel_diff(step), true)
		"expect_baseline_unchanged":
			rec.merge(_do_expect_baseline_unchanged(step), true)
		_:
			rec["pass"] = false
			rec["error"] = "unknown act: %s" % act
	return rec


# ============================================================================
# STEP IMPLEMENTATIONS
# ============================================================================

func _do_screenshot(step: Dictionary) -> Dictionary:
	var label: String = str(step.get("label", "step"))
	var scenario_id: String = str(_scenario.get("id", "unnamed"))
	var dir_path = "user://%s" % RESULTS_SUBDIR
	var d = DirAccess.open("user://")
	if d != null:
		d.make_dir_recursive(RESULTS_SUBDIR)
	# Yield a frame so any pending render commits
	await get_tree().process_frame
	var vp := get_viewport()
	if vp == null:
		return {"pass": false, "error": "no viewport"}
	var img := vp.get_texture().get_image()
	if img == null:
		return {"pass": false, "error": "viewport returned no image"}
	var rel := "%s/%s_%s.png" % [RESULTS_SUBDIR, scenario_id, label]
	var abs := ProjectSettings.globalize_path("user://" + rel)
	if step.has("region"):
		var r = step["region"]
		if typeof(r) == TYPE_ARRAY and r.size() == 4:
			img = img.get_region(Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])))
	var err := img.save_png(abs)
	if err != OK:
		return {"pass": false, "error": "save_png failed: %d" % err, "path": abs}
	return {"pass": true, "path": rel}


func _do_dispatch_action(step: Dictionary) -> Dictionary:
	var phase_mgr = get_node_or_null("/root/PhaseManager")
	if phase_mgr == null:
		return {"pass": false, "error": "no PhaseManager"}
	var phase = phase_mgr.get_current_phase_instance()
	if phase == null:
		return {"pass": false, "error": "no current phase instance"}
	var action = step.get("action", {})
	# Convert JSON-friendly [x, y] arrays / {x, y} dicts to Vector2 for
	# action fields that the phase code expects as Vector2. Mirrors the
	# logic in addons/godot_mcp/handlers/wh40k_handlers._normalize_action_positions.
	# Without this, per_model_paths arrays sum to 0 inside Measurement and
	# multi-model moves silently no-op while validators report success.
	action = _normalize_action_positions(action)
	if not phase.has_method("execute_action"):
		return {"pass": false, "error": "phase lacks execute_action"}
	var result = phase.execute_action(action)
	# Phases sometimes return a Variant or a Dictionary; normalize
	_last_action_result = result
	# Yield a frame for any signal-driven UI updates
	await get_tree().process_frame
	return {"pass": true, "result_summary": _summarize_result(result)}


func _do_click_unit(step: Dictionary) -> Dictionary:
	var unit_id: String = str(step.get("unit_id", ""))
	if unit_id == "":
		return {"pass": false, "error": "click_unit needs unit_id"}
	var token: Node = _find_unit_token(unit_id)
	if token == null:
		return {"pass": false, "error": "no token found for unit %s" % unit_id}
	var screen_pos := _node2d_to_screen(token)
	if screen_pos == Vector2.INF:
		return {"pass": false, "error": "could not project token to screen"}
	await _send_click(screen_pos)
	return {"pass": true, "screen_position": [screen_pos.x, screen_pos.y]}


func _do_click_node(step: Dictionary) -> Dictionary:
	var node_path: String = str(step.get("node", ""))
	if node_path == "":
		return {"pass": false, "error": "click_node needs node"}
	var node: Node = get_node_or_null(node_path)
	if node == null:
		return {"pass": false, "error": "no node at path %s" % node_path}

	# Shortcut: emit pressed directly on Buttons (skips hit-testing pitfalls)
	if step.get("emit_pressed", false) and node.has_signal("pressed"):
		node.emit_signal("pressed")
		await get_tree().process_frame
		return {"pass": true, "via": "emit_pressed"}

	var screen_pos: Vector2
	if node is Control:
		var rect: Rect2 = (node as Control).get_global_rect()
		screen_pos = rect.position + rect.size * 0.5
	elif node is Node2D:
		screen_pos = _node2d_to_screen(node as Node2D)
	else:
		return {"pass": false, "error": "node is neither Control nor Node2D"}

	if screen_pos == Vector2.INF:
		return {"pass": false, "error": "could not compute click position"}
	await _send_click(screen_pos)
	return {"pass": true, "screen_position": [screen_pos.x, screen_pos.y]}


func _do_simulate_key(step: Dictionary) -> Dictionary:
	var keycode = step.get("keycode", "")
	var kc: int = 0
	if typeof(keycode) == TYPE_STRING:
		kc = OS.find_keycode_from_string(keycode)
	elif typeof(keycode) == TYPE_INT:
		kc = int(keycode)
	if kc == 0:
		return {"pass": false, "error": "could not resolve keycode: %s" % str(keycode)}
	var press := InputEventKey.new()
	press.keycode = kc
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	var release := InputEventKey.new()
	release.keycode = kc
	release.pressed = false
	Input.parse_input_event(release)
	await get_tree().process_frame
	return {"pass": true}


func _do_expect_state(step: Dictionary) -> Dictionary:
	var path: String = str(step.get("path", ""))
	if path == "":
		return {"pass": false, "error": "expect_state needs path"}
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return {"pass": false, "error": "no GameState"}
	var actual = _walk_path(gs.state, path)
	return _compare(step, actual, "state[%s]" % path)


func _do_expect_cp(step: Dictionary) -> Dictionary:
	var player = step.get("player", null)
	if player == null:
		return {"pass": false, "error": "expect_cp needs player"}
	var pid = str(int(player))
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return {"pass": false, "error": "no GameState"}
	var actual_cp = gs.state.get("players", {}).get(pid, {}).get("cp", null)
	if step.has("delta_from_start"):
		var start = _start_cp.get(pid, null)
		if start == null:
			return {"pass": false, "error": "no start CP recorded for player %s" % pid}
		var expected_delta = int(step["delta_from_start"])
		var actual_delta = int(actual_cp) - int(start)
		var ok = expected_delta == actual_delta
		return {"pass": ok, "expected_delta": expected_delta, "actual_delta": actual_delta, "start": start, "now": actual_cp,
				"error": "" if ok else "CP delta mismatch"}
	return _compare(step, actual_cp, "players.%s.cp" % pid)


func _do_expect_action_result(step: Dictionary) -> Dictionary:
	if _last_action_result == null:
		return {"pass": false, "error": "no prior dispatch_action result"}
	var path: String = str(step.get("path", ""))
	var actual = _last_action_result if path == "" else _walk_path(_last_action_result, path)
	return _compare(step, actual, "last_result[%s]" % path)


func _do_expect_phase(step: Dictionary) -> Dictionary:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return {"pass": false, "error": "no GameState"}
	var phase = gs.state.get("meta", {}).get("phase", -1)
	return _compare(step, phase, "meta.phase")


func _do_expect_phase_property(step: Dictionary) -> Dictionary:
	# Assert against a property on the *current phase instance* (e.g.
	# active_fighter_id, awaiting_counter_offensive). These live on the phase
	# Node, not in GameState, but are the canonical way to introspect phase
	# sub-state for tests.
	var prop: String = str(step.get("property", ""))
	if prop == "":
		return {"pass": false, "error": "expect_phase_property needs property"}
	var phase_mgr = get_node_or_null("/root/PhaseManager")
	if phase_mgr == null:
		return {"pass": false, "error": "no PhaseManager"}
	var phase = phase_mgr.get_current_phase_instance()
	if phase == null:
		return {"pass": false, "error": "no current phase instance"}
	if not (prop in phase):
		return {"pass": false, "error": "phase has no property '%s' (script=%s)" % [prop, phase.get_script().resource_path if phase.get_script() else "<none>"]}
	var actual = phase.get(prop)
	return _compare(step, actual, "phase.%s" % prop)


func _do_expect_node_visible(step: Dictionary) -> Dictionary:
	var node_path: String = str(step.get("node", ""))
	if node_path == "":
		return {"pass": false, "error": "expect_node_visible needs node"}
	var timeout_s = float(step.get("timeout_s", 2.0))
	var deadline = Time.get_ticks_msec() + int(timeout_s * 1000)
	while Time.get_ticks_msec() < deadline:
		var node = get_node_or_null(node_path)
		if node != null:
			var vis: bool = false
			if node.has_method("is_visible_in_tree"):
				vis = node.is_visible_in_tree()
			elif "visible" in node:
				vis = bool(node.visible)
			else:
				vis = true  # exists, no visibility property — accept
			if vis:
				return {"pass": true, "found_after_ms": Time.get_ticks_msec() - (deadline - int(timeout_s * 1000))}
		await get_tree().process_frame
	return {"pass": false, "error": "node not visible within %ss: %s" % [str(timeout_s), node_path]}


func _do_expect_node_property(step: Dictionary) -> Dictionary:
	var node_path: String = str(step.get("node", ""))
	var prop: String = str(step.get("property", ""))
	if node_path == "" or prop == "":
		return {"pass": false, "error": "expect_node_property needs node + property"}
	var node = get_node_or_null(node_path)
	if node == null:
		return {"pass": false, "error": "no node at %s" % node_path}
	if not (prop in node):
		return {"pass": false, "error": "node %s has no property %s" % [node_path, prop]}
	var actual = node.get(prop)
	return _compare(step, actual, "%s.%s" % [node_path, prop])


func _do_expect_token_visible(step: Dictionary) -> Dictionary:
	var unit_id: String = str(step.get("unit_id", ""))
	if unit_id == "":
		return {"pass": false, "error": "expect_token_visible needs unit_id"}
	var timeout_s = float(step.get("timeout_s", 2.0))
	var deadline = Time.get_ticks_msec() + int(timeout_s * 1000)
	while Time.get_ticks_msec() < deadline:
		var token = _find_unit_token(unit_id)
		if token != null and (token.has_method("is_visible_in_tree") and token.is_visible_in_tree()):
			return {"pass": true}
		await get_tree().process_frame
	return {"pass": false, "error": "no visible token for %s within %ss" % [unit_id, str(timeout_s)]}


# ----------------------------------------------------------------------------
# Tier-A step types (added in T02 for design-guidelines tasks).
#
# These three step types let visual scenarios make falsifiable claims about
# state, rendered pixels, and the regression-baseline file. See
# tests/scenarios/visual/_schema.md.
# ----------------------------------------------------------------------------

func _do_execute_script(step: Dictionary) -> Dictionary:
	# Evaluate a GDScript expression and compare its result against
	# equals / not_equals / exists / expect_min / expect_max.
	#
	# The expression has access to:
	#   - autoloads by name (GameState, PhaseManager, RulesEngine, ...)
	#   - the helper `main` referring to /root/Main if present
	#
	# Example:
	#   { "act": "execute_script",
	#     "script": "MovementController.current_drag_segments[-1].color_slot",
	#     "equals": "MARGINAL_YELLOW" }
	var code: String = str(step.get("script", ""))
	if code == "":
		return {"pass": false, "error": "execute_script needs `script`"}

	# Build input name/value pairs:
	#   - every autoload child of /root (referenced by node name)
	#   - common engine singletons (Engine, OS, Time, Input, RenderingServer)
	#   - `main` -> the live battle scene root, if loaded
	var input_names: Array = []
	var input_values: Array = []
	var root := get_tree().root
	for child in root.get_children():
		input_names.append(child.name)
		input_values.append(child)
	input_names.append_array(["Engine", "OS", "Time", "Input", "RenderingServer", "ProjectSettings", "main"])
	input_values.append_array([Engine, OS, Time, Input, RenderingServer, ProjectSettings, get_tree().current_scene])

	var expr := Expression.new()
	var parse_err := expr.parse(code, input_names)
	if parse_err != OK:
		return {"pass": false, "error": "parse failed: %s" % expr.get_error_text()}
	# Pass self as base instance so `self.foo` works and any singletons not in
	# input_names fall through to the runner's context.
	var actual = expr.execute(input_values, self, true)
	if expr.has_execute_failed():
		return {"pass": false, "error": "execute failed: %s" % expr.get_error_text()}

	# Tolerate "no expectation" — caller may just want to drive a side effect.
	if not (step.has("equals") or step.has("not_equals") or step.has("exists")
			or step.has("expect_min") or step.has("expect_max")):
		return {"pass": true, "actual": actual}

	# Numeric bounds
	if step.has("expect_min"):
		var lo = float(step["expect_min"])
		if typeof(actual) in [TYPE_INT, TYPE_FLOAT]:
			var ok = float(actual) >= lo
			return {"pass": ok, "actual": actual, "expect_min": lo,
					"error": "" if ok else "expected >= %s, got %s" % [str(lo), str(actual)]}
		return {"pass": false, "error": "expect_min requires numeric actual, got %s" % typeof(actual)}
	if step.has("expect_max"):
		var hi = float(step["expect_max"])
		if typeof(actual) in [TYPE_INT, TYPE_FLOAT]:
			var ok2 = float(actual) <= hi
			return {"pass": ok2, "actual": actual, "expect_max": hi,
					"error": "" if ok2 else "expected <= %s, got %s" % [str(hi), str(actual)]}
		return {"pass": false, "error": "expect_max requires numeric actual, got %s" % typeof(actual)}

	# equals / not_equals / exists -> reuse _compare
	return _compare(step, actual, "script[%s]" % code.substr(0, 60))


func _do_pixel_diff(step: Dictionary) -> Dictionary:
	# Compare two previously-captured screenshots (by `label`, matching the
	# `screenshot` step's label argument). Optionally clipped to a named region
	# from the scenario-level `regions` dict.
	#
	# Example:
	#   { "act": "pixel_diff",
	#     "before": "T03_at_M", "after": "T03_at_advance",
	#     "region": "drag_path",
	#     "expect_min_pct": 3.0 }
	var before_label: String = str(step.get("before", ""))
	var after_label: String = str(step.get("after", ""))
	if before_label == "" or after_label == "":
		return {"pass": false, "error": "pixel_diff needs `before` and `after` labels"}

	var scenario_id: String = str(_scenario.get("id", "unnamed"))
	var before_rel := "%s/%s_%s.png" % [RESULTS_SUBDIR, scenario_id, before_label]
	var after_rel := "%s/%s_%s.png" % [RESULTS_SUBDIR, scenario_id, after_label]
	var before_abs := ProjectSettings.globalize_path("user://" + before_rel)
	var after_abs := ProjectSettings.globalize_path("user://" + after_rel)

	# Optional region resolution against scenario-level dict
	var regions := {}
	if step.has("region"):
		var region_name: String = str(step["region"])
		var scenario_regions: Dictionary = _scenario.get("regions", {})
		if not scenario_regions.has(region_name):
			return {"pass": false, "error": "scenario has no region named '%s'" % region_name}
		regions[region_name] = scenario_regions[region_name]

	# Load the static utility class. Cannot use class_name PixelDiff here
	# without forcing it into the global namespace at parse time; load by path.
	var pd = load("res://tests/tools/pixel_diff.gd")
	if pd == null:
		return {"pass": false, "error": "could not load pixel_diff.gd"}
	var result: Dictionary = pd.diff(before_abs, after_abs, regions)
	if result.has("error"):
		return {"pass": false, "error": "pixel_diff: %s" % result["error"]}

	# Pick the pct to compare against: region if specified, else total
	var pct: float
	if step.has("region"):
		var region_name2: String = str(step["region"])
		var rr = result.get("regions", {}).get(region_name2, null)
		if typeof(rr) == TYPE_FLOAT or typeof(rr) == TYPE_INT:
			pct = float(rr)
		else:
			return {"pass": false, "error": "region '%s' diff failed: %s" % [region_name2, str(rr)]}
	else:
		pct = float(result.get("total_diff_pct", -1.0))

	# Always emit the diff to the results record so reviewers can see the
	# numbers without re-running.
	var record := {"pass": true, "diff_pct": pct, "result": result}

	if step.has("expect_min_pct"):
		var lo = float(step["expect_min_pct"])
		if pct < lo:
			record["pass"] = false
			record["error"] = "pixel_diff: expected >= %.2f%%, got %.2f%%" % [lo, pct]
	if step.has("expect_max_pct"):
		var hi = float(step["expect_max_pct"])
		if pct > hi:
			record["pass"] = false
			record["error"] = "pixel_diff: expected <= %.2f%%, got %.2f%%" % [hi, pct]
	if not (step.has("expect_min_pct") or step.has("expect_max_pct")):
		record["pass"] = false
		record["error"] = "pixel_diff needs expect_min_pct or expect_max_pct"
	return record


func _do_expect_baseline_unchanged(_step: Dictionary) -> Dictionary:
	# Asserts the regression baseline file exists and is non-empty. The
	# suite-level regression check (PASSED count >= baseline count) is
	# performed by run_scenarios.sh because it has cross-scenario visibility;
	# this step is the in-scenario sanity check that the baseline machinery is
	# wired up at all.
	var baseline_path := "res://tests/scenarios/visual/_baseline.json"
	var abs := ProjectSettings.globalize_path(baseline_path)
	if not FileAccess.file_exists(abs):
		return {"pass": false, "error": "baseline file missing: %s" % baseline_path}
	var f := FileAccess.open(abs, FileAccess.READ)
	if f == null:
		return {"pass": false, "error": "could not open baseline file"}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"pass": false, "error": "baseline JSON malformed"}
	var passing: Array = parsed.get("passing", [])
	var count: int = int(parsed.get("count", -1))
	if passing.is_empty() or count <= 0:
		return {"pass": false, "error": "baseline is empty (count=%d, passing=%d)" % [count, passing.size()]}
	if passing.size() != count:
		return {"pass": false, "error": "baseline count (%d) != passing array length (%d)" % [count, passing.size()]}
	return {"pass": true, "baseline_count": count}


# ============================================================================
# HELPERS
# ============================================================================

func _send_click(screen_pos: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = screen_pos
	press.global_position = screen_pos
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(press)
	await get_tree().process_frame
	await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = screen_pos
	release.global_position = screen_pos
	release.pressed = false
	release.button_mask = 0
	Input.parse_input_event(release)
	await get_tree().process_frame
	await get_tree().process_frame


func _find_unit_token(unit_id: String) -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	for r in [tree.current_scene, tree.root]:
		if r == null:
			continue
		var found := _search_node_by_unit_id(r, unit_id)
		if found:
			return found
	return null


func _search_node_by_unit_id(node: Node, unit_id: String) -> Node2D:
	if node is Node2D:
		var n2d := node as Node2D
		if n2d.name == unit_id:
			return n2d
		if "unit_id" in n2d and str(n2d.get("unit_id")) == unit_id:
			return n2d
		if n2d.has_meta("unit_id") and str(n2d.get_meta("unit_id")) == unit_id:
			return n2d
	for child in node.get_children():
		var found := _search_node_by_unit_id(child, unit_id)
		if found:
			return found
	return null


func _normalize_action_positions(action: Dictionary) -> Dictionary:
	# Mirror of wh40k_handlers._normalize_action_positions. Converts
	# JSON-shaped position fields ([x,y] / {x,y}) into Vector2.
	if typeof(action) != TYPE_DICTIONARY:
		return action
	var out: Dictionary = action.duplicate(true)
	for key in ["position", "destination", "dest", "target_position", "stage_position"]:
		if out.has(key):
			var v = _coerce_vector2(out[key])
			if v != null:
				out[key] = v
	if out.has("model_positions") and typeof(out["model_positions"]) == TYPE_ARRAY:
		var positions: Array = out["model_positions"]
		var converted: Array = []
		for p in positions:
			if p == null:
				converted.append(null)
			else:
				var v2 = _coerce_vector2(p)
				converted.append(v2 if v2 != null else p)
		out["model_positions"] = converted
	if out.has("payload") and typeof(out["payload"]) == TYPE_DICTIONARY:
		var payload: Dictionary = out["payload"]
		if payload.has("per_model_paths") and typeof(payload["per_model_paths"]) == TYPE_DICTIONARY:
			var paths: Dictionary = payload["per_model_paths"]
			var converted_paths: Dictionary = {}
			for model_id in paths:
				var p2 = paths[model_id]
				if typeof(p2) == TYPE_ARRAY:
					var converted_path: Array = []
					for q in p2:
						var v3 = _coerce_vector2(q)
						converted_path.append(v3 if v3 != null else q)
					converted_paths[model_id] = converted_path
				else:
					converted_paths[model_id] = p2
			payload["per_model_paths"] = converted_paths
			out["payload"] = payload
	return out


func _coerce_vector2(value):
	if typeof(value) == TYPE_VECTOR2:
		return value
	if typeof(value) == TYPE_ARRAY and value.size() >= 2:
		var x = value[0]
		var y = value[1]
		if (typeof(x) in [TYPE_INT, TYPE_FLOAT]) and (typeof(y) in [TYPE_INT, TYPE_FLOAT]):
			return Vector2(float(x), float(y))
	if typeof(value) == TYPE_DICTIONARY and value.has("x") and value.has("y"):
		var x2 = value["x"]
		var y2 = value["y"]
		if (typeof(x2) in [TYPE_INT, TYPE_FLOAT]) and (typeof(y2) in [TYPE_INT, TYPE_FLOAT]):
			return Vector2(float(x2), float(y2))
	return null


func _node2d_to_screen(node: Node2D) -> Vector2:
	var viewport := node.get_viewport()
	if viewport == null:
		return Vector2.INF
	var canvas_xform := viewport.get_canvas_transform()
	return canvas_xform * node.global_position


func _walk_path(root, path: String):
	# Dot-separated path. Accepts numeric segments for arrays.
	if path == "":
		return root
	var cur = root
	for seg in path.split("."):
		if cur == null:
			return null
		if typeof(cur) == TYPE_DICTIONARY:
			if cur.has(seg):
				cur = cur[seg]
			else:
				return null
		elif typeof(cur) == TYPE_ARRAY:
			var idx = seg.to_int()
			if idx < 0 or idx >= cur.size():
				return null
			cur = cur[idx]
		else:
			return null
	return cur


func _compare(step: Dictionary, actual, label: String) -> Dictionary:
	if step.has("equals"):
		var expected = step["equals"]
		var ok = _values_equal(actual, expected)
		return {"pass": ok, "label": label, "expected": expected, "actual": actual,
				"error": "" if ok else "%s: expected %s, got %s" % [label, str(expected), str(actual)]}
	if step.has("not_equals"):
		var expected2 = step["not_equals"]
		var ok2 = not _values_equal(actual, expected2)
		return {"pass": ok2, "label": label, "expected_not": expected2, "actual": actual,
				"error": "" if ok2 else "%s: expected NOT %s, got %s" % [label, str(expected2), str(actual)]}
	if step.has("exists"):
		var expected3: bool = bool(step["exists"])
		var got_exists: bool = actual != null
		var ok3 = got_exists == expected3
		return {"pass": ok3, "label": label, "expected_exists": expected3, "actual": actual,
				"error": "" if ok3 else "%s: expected exists=%s, got actual=%s" % [label, str(expected3), str(actual)]}
	return {"pass": false, "error": "%s: no expectation specified (equals|not_equals|exists)" % label}


func _values_equal(a, b) -> bool:
	# Loose comparison: int/float widen; str is exact; arrays/dicts deep
	if typeof(a) == typeof(b):
		return a == b
	if (typeof(a) in [TYPE_INT, TYPE_FLOAT]) and (typeof(b) in [TYPE_INT, TYPE_FLOAT]):
		return float(a) == float(b)
	# String<->Bool: tolerate "true"/"false" comparisons
	if typeof(a) == TYPE_STRING and typeof(b) == TYPE_BOOL:
		return a == str(b)
	if typeof(a) == TYPE_BOOL and typeof(b) == TYPE_STRING:
		return str(a) == b
	return false


func _capture_cp_snapshot() -> Dictionary:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return {}
	var out := {}
	var players = gs.state.get("players", {})
	for pid in players:
		out[str(pid)] = players[pid].get("cp", 0)
	return out


func _summarize_result(result) -> Variant:
	# Truncate large dicts so the results JSON stays readable
	if typeof(result) == TYPE_DICTIONARY:
		var summary := {}
		for k in result.keys():
			var v = result[k]
			if typeof(v) == TYPE_DICTIONARY or typeof(v) == TYPE_ARRAY:
				summary[k] = "<%s len=%d>" % ["dict" if typeof(v) == TYPE_DICTIONARY else "array", v.size()]
			else:
				summary[k] = v
		return summary
	return result


func _capture_failure_screenshot(scenario_id: String, step_idx: int) -> void:
	var d = DirAccess.open("user://")
	if d != null:
		d.make_dir_recursive(RESULTS_SUBDIR)
	var rel = "%s/%s_FAIL_step_%d.png" % [RESULTS_SUBDIR, scenario_id, step_idx]
	var abs = ProjectSettings.globalize_path("user://" + rel)
	var vp := get_viewport()
	if vp == null:
		return
	var img := vp.get_texture().get_image()
	if img == null:
		return
	img.save_png(abs)
	print("[ScenarioRunner] failure screenshot: %s" % abs)


func _write_results(scenario_id: String, passed: int, failed: int) -> void:
	var d = DirAccess.open("user://")
	if d != null:
		d.make_dir_recursive(RESULTS_SUBDIR)
	var rel = "%s/%s.json" % [RESULTS_SUBDIR, scenario_id]
	var abs = ProjectSettings.globalize_path("user://" + rel)
	var f = FileAccess.open(abs, FileAccess.WRITE)
	if f == null:
		print("[ScenarioRunner] could not open results file: %s" % abs)
		return
	var out := {
		"scenario_id": scenario_id,
		"passed": passed,
		"failed": failed,
		"total_steps": _step_results.size(),
		"steps": _step_results,
	}
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("[ScenarioRunner] results written: %s" % abs)


func _fail_and_quit(reason: String) -> void:
	print("[ScenarioRunner] FATAL: %s" % reason)
	get_tree().quit(2)
